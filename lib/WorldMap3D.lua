-- The town map, as the region it describes.
--
-- WHAT THIS REPLACES. `src.ui.TownMap` draws the Game Boy's town map: a
-- 20x18 grid of 8x8 tiles in four shades, 160x144, with a blinking square
-- for where you are. Beside a diorama you can walk around in, it reads as a
-- different game -- and it is the screen you open most often to answer the
-- one question the diorama answers best: where is this place, and what is
-- around it.
--
-- So the map becomes the region. All 34 outdoor maps of Kanto, standing
-- where the engine's own connection graph says they stand, as voxels, with
-- the sea around them and the water moving.
--
-- WHERE THE GEOMETRY COMES FROM, and none of it is drawn by hand:
--
--   the placing    OverworldController.computeNeighbors walked from Pallet
--                  Town at 40 hops -- the engine's own BFS over
--                  `def.connections`, the same one lib/WorldAtlas.lua uses
--                  for the skyline, just further. 33 outdoor maps come back
--                  (plus the root), in world pixels, bounding 340x360 cells.
--   the cells      MapLoader.load per map, then this mod's own tile
--                  classifier (lib/TileShape.lua over data/voxel_heights.lua)
--                  at CELL granularity -- the same classes the voxel
--                  overworld extrudes, so a hill on the world map is the
--                  hill you climbed.
--   the water      lib/WaterMap.lua, which is the engine's tileset gate plus
--                  the three shore rules. 7,846 cells of Kanto are water and
--                  every one of them is where the game says it is.
--
-- Measured over the whole region (tests/worldmap_probe3.lua): 40,140 cells,
-- 366 ms to load and 11 ms to classify. That is the whole cost, it is paid
-- once per session, and it is spread over frames behind a progress bar
-- rather than taken as a stall.
--
-- WHY IT IS DRAWN FROM Renderer.endFrame, which is not where anything else
-- in this mod draws. The start menu is painted from the render pipeline's
-- present hook (lib/StartMenuXY.lua) because the world is still being drawn
-- behind it. The town map declares `isOpaque = true`, and an opaque screen
-- is one the stack stops descending past: measured, the world stage runs
-- zero times while the map is open (tests/worldmap_probe4.lua), so there is
-- no present hook to paint from. Painting the window from inside the
-- screen's own draw does not survive either -- the engine composites the
-- 160x144 UI canvas over the window afterwards, and the screenshot comes
-- back white (tests/worldmap_probe5.lua). `Renderer.endFrame` is the first
-- seam after that composite: the window is bound, it is full resolution,
-- and it runs once per rendered frame (tests/worldmap_probe6.lua).
--
-- Two halves, as ever, and both are needed or the frame carries two maps:
-- this file DRAWS the region, and it SILENCES the engine's own draw -- on
-- the screen INSTANCE, never on the class.
--
-- WHAT IT DOES NOT TOUCH. The screen's behaviour is still the engine's: the
-- cursor, which locations are known, what the list says. `screen.sel` is
-- read once a frame and the camera flies to whatever it points at. Up and
-- down still move the cursor and B still closes; left, right, A and SELECT
-- were measured to do nothing on this screen (probe 4), which is why the
-- camera may have them.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local TileShape = V.require("TileShape")
local WaterMap = V.require("WaterMap")
local BattleHudXY = V.require("BattleHudXY")
local WorldMapQuest = V.require("WorldMapQuest")

local WorldMap3D = {}

WorldMap3D.ENABLED = true

-- Where the walk starts and how far it goes. Pallet Town because it is the
-- one map every save has reached, and 40 hops because Kanto's outdoor graph
-- closes at 12 -- measured, hops 12, 25 and 40 all return the same 33 maps
-- (tests/worldmap_probe2.lua). Rooting anywhere else would place the same
-- region at a different origin, which the camera would not notice and the
-- cache would.
WorldMap3D.ROOT = "PALLET_TOWN"
WorldMap3D.HOPS = 40

-- Milliseconds of build allowed per frame. The whole region is ~380 ms of
-- work, so this is about 45 frames of progress bar and then it is done for
-- the session. Larger stalls the frame; smaller makes the wait visible.
WorldMap3D.BUILD_MS = 9

-- How far from the bank the shore field is measured, in cells. See the shore
-- pass in the build for why it goes further than any foam needs.
WorldMap3D.SHORE_SPAN = 12

-- The water, borrowed whole from lib/Water.lua and in ITS units (world
-- pixels). SWELL is that file's own CALM row -- the surface here moves
-- exactly as much as the surface in the game does, which is not much: the
-- look is carried by the shading, not by the displacement.
WorldMap3D.SWELL = 0.8
WorldMap3D.ART_SCALE = 64          -- Water.ART_SCALE: four map cells
WorldMap3D.ART_MIX = 0.35          -- Water.ART_MIX
WorldMap3D.ASSET_DIR = "assets/water/"
WorldMap3D.ASSET_FILE = "water.png"

-- ---------------------------------------------------------------- the classes
--
-- lib/TileShape.lua's class names, as small integers, because the grid holds
-- one per cell for 122k cells and a string key per cell is a hash lookup per
-- cell in every pass that follows.
local VOID, GROUND, WATER, WALL, TREE, LEDGE, TALL, POST, SIGN, PROP, OCEAN,
      MASS = 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11

local CLASS_ID = {
  ground = GROUND, water = WATER, wall = WALL,
  -- The OVERWORLD profile pins the tree wall as `cylinder` (it is a round
  -- drawing; see the note in lib/TerrainAtlas.lua). 12.8% of Kanto is this
  -- one class and all of it is forest canopy.
  cylinder = TREE,
  ledge = LEDGE, grass = TALL, post = POST, signpost = SIGN, prop = PROP,
}

-- Height per class, in CELLS (a cell is 16 world pixels, and the classes'
-- own heights are in pixels: ground 0, water -2, ledge 6, fence 10, sign 12,
-- wall and tree 16). A world map is a relief map, so the vertical is
-- exaggerated -- at this zoom an unexaggerated 16px wall is a third of a
-- pixel on screen and Kanto reads as a flat sticker. Buildings and mountains
-- get their height from their FOOTPRINT instead (see relief()).
local HEIGHT = {
  [VOID] = -0.30, [OCEAN] = -0.30,
  [GROUND] = 0.00,
  [WATER] = -0.22,
  [WALL] = 1.05,
  [TREE] = 1.15,
  [LEDGE] = 0.34,
  [TALL] = 0.16,
  [POST] = 0.55,
  [SIGN] = 0.70,
  [PROP] = 0.45,
}

-- Base colour per class. The lightness of the cell's own tile moves each of
-- these along a ramp (see cellColor), which is what separates a route's pale
-- path from the grass beside it: both are class `ground`, 42% of the region
-- between them, and the town map has always drawn them as different things.
local COLOR = {
  [GROUND]   = { 0.24, 0.47, 0.20 },   -- grass, the dark end of the ramp
  [SIGN]     = { 0.40, 0.31, 0.19 },
  [POST]     = { 0.52, 0.43, 0.28 },
  [TALL]     = { 0.17, 0.40, 0.15 },
  [TREE]     = { 0.11, 0.33, 0.13 },
  [LEDGE]    = { 0.44, 0.41, 0.26 },
  [PROP]     = { 0.48, 0.41, 0.32 },
}
local PATH_COLOR = { 0.80, 0.74, 0.55 }   -- the light end of the ground ramp
local ROCK_COLOR = { 0.47, 0.45, 0.42 }
local ROOF_COLOR = { 0.74, 0.24, 0.21 }   -- a Kanto roof, seen from above
local WALL_COLOR = { 0.88, 0.86, 0.80 }
local MASS_LOW  = { 0.13, 0.29, 0.15 }    -- the interior's wooded skirts
local MASS_HIGH = { 0.53, 0.51, 0.45 }    -- and its bare tops

-- A footprint this size or smaller is a building; anything larger is the
-- landscape (a cliff wall, a mountain, the border). Measured against Kanto:
-- a Gen 1 house is 6 cells, a Mart or Centre 12, Silph 40; the Route 3 and
-- Route 4 cliff faces run into the hundreds.
local BUILDING_MAX = 44

-- Face shading, the same idea as Voxel3D.FACE_SHADE: a box that is one flat
-- colour on every face reads as a sticker, not a solid. The sun is in the
-- south-east here too, so south and east are the lit flanks.
local SHADE_TOP, SHADE_S, SHADE_E, SHADE_N, SHADE_W = 1.00, 0.90, 0.82, 0.68, 0.66

-- ---------------------------------------------------------------- build state
local R = nil          -- the built region, or nil
local build = nil      -- the in-progress build (a coroutine and its report)
local failed = false   -- a build that threw; never retried in the same session

-- The live game, captured where it is handed over: `TownMap.new(game)`. The
-- frame hook is Renderer.endFrame, which is given a renderer and not a game,
-- and there is no global to ask -- so the screen's own constructor is the one
-- place both things are in the same room.
--
-- Declared HERE rather than beside the install that fills it, because the
-- objective drawing reads it and a Lua local only becomes an upvalue for
-- functions written after it: declared later, every read would silently be a
-- read of a global that does not exist.
local activeGame = nil

-- What lib/WorldMapQuest.lua last answered, and which placed map it points
-- at. Up here with the rest of the state because BOTH the objective drawing
-- and the name plates read them, and those two are written far apart.
local quest = nil
local questTargetPlace = nil

local function log(msg)
  print("[TERRARIUM] worldmap: " .. tostring(msg))
end

-- Value noise on a lattice of `cell` cells, bilinear between corners. Not
-- random(): the same coordinate has to answer the same thing every time the
-- region is built, or the interior of Kanto is a different shape each
-- session.
--
-- Arithmetic, with no bitwise operator in it, because this engine runs on
-- LuaJIT -- Lua 5.1, where `~` and `>>` are not operators at all and a hash
-- written with them is a syntax error in a file that then fails to load.
local function hash2(ix, iy)
  local s = math.sin(ix * 12.9898 + iy * 78.233) * 43758.5453
  return s - math.floor(s)
end

local function noise2(x, y, cell)
  local fx, fy = x / cell, y / cell
  local ix, iy = math.floor(fx), math.floor(fy)
  local tx, ty = fx - ix, fy - iy
  tx = tx * tx * (3 - 2 * tx)
  ty = ty * ty * (3 - 2 * ty)
  local a = hash2(ix, iy)
  local b = hash2(ix + 1, iy)
  local c = hash2(ix, iy + 1)
  local d = hash2(ix + 1, iy + 1)
  return (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * ty
end

-- ============================================================================
-- 1. THE REGION
-- ============================================================================

-- Mean lightness of every tile in a tileset, 0..1, straight off the atlas
-- image. One table per tileset id, and Kanto is one tileset.
--
-- The raw atlas is the four-shade drawing, before any palette: that is the
-- point. What is wanted here is not the tile's colour (a palette decides
-- that, and it changes with the map) but how LIGHT the drawing is, which is
-- what tells a path from the grass beside it in every palette Gen 1 has.
local lumCache = {}
local function tileLightness(tileset)
  local id = tileset and tileset.id
  if not id then return nil end
  if lumCache[id] ~= nil then return lumCache[id] or nil end
  local ok, out = pcall(function()
    local Assets = require("src.render.Assets")
    local raw = Assets.imageData(tileset.image)
    if not raw then return nil end
    local iw, ih = raw:getDimensions()
    local perRow = tileset.tilesPerRow or 16
    local count = math.floor(iw / 8) * math.floor(ih / 8)
    local out = {}
    for t = 0, count - 1 do
      local sx, sy = (t % perRow) * 8, math.floor(t / perRow) * 8
      if sx + 8 <= iw and sy + 8 <= ih then
        local sum = 0
        for py = 0, 7 do
          for px = 0, 7 do
            local r, g, b = raw:getPixel(sx + px, sy + py)
            sum = sum + (0.30 * r + 0.59 * g + 0.11 * b)
          end
        end
        out[t] = sum / 64
      end
    end
    return out
  end)
  lumCache[id] = (ok and out) or false
  return lumCache[id] or nil
end

-- Everything outdoor the connection graph reaches, plus the root itself --
-- which computeNeighbors leaves out, being the thing the offsets are
-- relative to.
local function placeRegion()
  local Game = require("src.core.Game")
  local Map = require("src.world.Map")
  local maps = Game.data and Game.data.maps
  if type(maps) ~= "table" or not maps[WorldMap3D.ROOT] then return nil end

  local OverworldState = require("src.world.OverworldController")
  local ok, raw = pcall(OverworldState.computeNeighbors, maps,
                        WorldMap3D.ROOT, WorldMap3D.HOPS)
  if not ok or type(raw) ~= "table" then return nil end

  local list = { { id = WorldMap3D.ROOT, ox = 0, oy = 0,
                   def = maps[WorldMap3D.ROOT] } }
  for _, nb in ipairs(raw) do
    local def = maps[nb.id]
    -- pcall's second return, kept in its own local: `def and pcall(f, def)`
    -- truncates it to one value and every map reads as indoor. It did, in
    -- the first cut of tests/worldmap_probe.lua, and the walk reported an
    -- empty Kanto.
    local okO, outdoor = false, false
    if def then okO, outdoor = pcall(Map.isOutdoor, def) end
    if okO and outdoor then
      list[#list + 1] = { id = nb.id, ox = nb.ox, oy = nb.oy, def = def }
    end
  end
  return list
end

-- The build, as a coroutine: it yields whenever it has spent its slice, and
-- the caller resumes it next frame. Nothing here draws.
local function buildCoroutine()
  return coroutine.create(function()
    local t0 = os.clock()
    local slice = os.clock()
    local function breathe()
      if (os.clock() - slice) * 1000 >= WorldMap3D.BUILD_MS then
        coroutine.yield()
        slice = os.clock()
      end
    end

    ------------------------------------------------------------- 1. the walk
    build.phase = "placing"
    local list = placeRegion()
    if not list or #list == 0 then error("the walk placed nothing", 0) end
    build.total = #list

    local minx, miny, maxx, maxy = 1e9, 1e9, -1e9, -1e9
    for _, e in ipairs(list) do
      local w = (e.def.width or 0) * 32     -- a block is 32 world px (2 cells)
      local h = (e.def.height or 0) * 32
      if e.ox < minx then minx = e.ox end
      if e.oy < miny then miny = e.oy end
      if e.ox + w > maxx then maxx = e.ox + w end
      if e.oy + h > maxy then maxy = e.oy + h end
    end
    -- one cell of margin so the coastline is never flush with the grid edge
    local MARGIN = 6
    local gw = math.floor((maxx - minx) / 16 + 0.5) + MARGIN * 2
    local gh = math.floor((maxy - miny) / 16 + 0.5) + MARGIN * 2
    local originX, originY = minx - MARGIN * 16, miny - MARGIN * 16

    -- Dense, preallocated, and filled with OCEAN rather than left sparse:
    -- two thirds of the bounding box is not covered by any map, and what is
    -- out there is the sea Kanto sits in. Filling it is what makes the
    -- region an island group instead of a ragged sheet of map rectangles.
    local n = gw * gh
    local cls, hgt, lum = {}, {}, {}
    for i = 1, n do cls[i] = OCEAN; hgt[i] = HEIGHT[OCEAN]; lum[i] = 0.5 end
    breathe()

    ------------------------------------------------------ 2. the cells
    build.phase = "reading"
    local MapLoader = require("src.world.MapLoader")
    local Game = require("src.core.Game")
    local places = {}
    local groundHist, groundCount = {}, 0
    for mi, e in ipairs(list) do
      build.done = mi
      local okL, m = pcall(MapLoader.load, Game.data, e.id)
      if okL and m then
        local okS, shapes = pcall(TileShape.forMap, m)
        if okS and shapes then
          local light = tileLightness(m.tileset)
          local mw, mh = m.widthCells or 0, m.heightCells or 0
          local bx = math.floor((e.ox - originX) / 16 + 0.5)
          local by = math.floor((e.oy - originY) / 16 + 0.5)
          places[#places + 1] = {
            id = e.id, x = bx, y = by, w = mw, h = mh,
            cx = bx + mw * 0.5, cy = by + mh * 0.5,
            label = e.def.label or e.id,
          }
          for cy = 0, mh - 1 do
            local gy = by + cy
            if gy >= 0 and gy < gh then
              for cx = 0, mw - 1 do
                local gx = bx + cx
                if gx >= 0 and gx < gw then
                  -- collision is judged by the cell's bottom-left 8x8 tile
                  -- and so is this (lib/WaterMap.lua, rule 3)
                  local tx, ty = cx * 2, cy * 2 + 1
                  local tile = m:tileAt(tx, ty)
                  local id = GROUND
                  if WaterMap.surfaceCell(m, cx, cy) then
                    id = WATER
                  else
                    local shp = tile and TileShape.at(m, shapes, tile, tx, ty)
                    local name = type(shp) == "table" and shp.class or nil
                    id = CLASS_ID[name or ""] or GROUND
                  end
                  local i = gy * gw + gx + 1
                  local l = (light and tile and light[tile]) or 0.5
                  cls[i] = id
                  hgt[i] = HEIGHT[id] or 0
                  lum[i] = l
                  -- the ground ramp is set from the region's own numbers,
                  -- not from a guessed cutoff: see rampFromHistogram
                  if id == GROUND then
                    local b = math.floor(math.max(0, math.min(1, l)) * 63) + 1
                    groundHist[b] = (groundHist[b] or 0) + 1
                    groundCount = groundCount + 1
                  end
                end
              end
            end
            breathe()
          end
        end
      end
      breathe()
    end

    -- THE GROUND RAMP, from the region's own distribution rather than from a
    -- number typed here.
    --
    -- `ground` is 42% of Kanto and it is two different things: the grass a
    -- route runs through and the path it runs along. The only thing that
    -- tells them apart without a hand-written tile list is how LIGHT the
    -- drawing is -- and where the useful part of that range sits is a
    -- property of the tileset, not of this file. Guessing it cost a whole
    -- first draft: the cutoff was set at 0.42 and every ground cell in Kanto
    -- came out above it, so the region rendered as one sheet of pale sand
    -- with no grass anywhere in it (probe_out_worldmap/look/01_region.png).
    -- Percentiles cannot be wrong that way.
    local rampLo, rampHi = 0.42, 0.80
    if groundCount > 64 then
      local function percentile(p)
        local want, run = groundCount * p, 0
        for b = 1, 64 do
          run = run + (groundHist[b] or 0)
          if run >= want then return (b - 0.5) / 64 end
        end
        return 1
      end
      rampLo, rampHi = percentile(0.30), percentile(0.90)
      if rampHi - rampLo < 0.02 then           -- a tileset with no contrast
        rampLo, rampHi = rampLo - 0.01, rampLo + 0.01
      end
    end

    ------------------------------------------------------ 3. closing the gaps
    -- Maps that touch do not always tile flush, and a one-cell trench of
    -- ocean running down the seam between two routes is the most visible
    -- wrong thing on the whole map. A cell of sea with land most of the way
    -- around it is a seam, not a lake: it takes the land.
    build.phase = "closing"
    local fixes = 0
    for gy = 1, gh - 2 do
      for gx = 1, gw - 2 do
        local i = gy * gw + gx + 1
        if cls[i] == OCEAN then
          local land, sumH, sumL, best = 0, 0, 0, GROUND
          for dy = -1, 1 do
            for dx = -1, 1 do
              if dx ~= 0 or dy ~= 0 then
                local j = (gy + dy) * gw + (gx + dx) + 1
                local c = cls[j]
                if c ~= OCEAN and c ~= VOID then
                  land = land + 1
                  sumH = sumH + hgt[j]; sumL = sumL + lum[j]
                  if c == GROUND then best = GROUND end
                end
              end
            end
          end
          if land >= 5 then
            cls[i] = best; hgt[i] = sumH / land; lum[i] = sumL / land
            fixes = fixes + 1
          end
        end
      end
      breathe()
    end
    build.seamFixes = fixes

    ------------------------------------------------- 3b. sea from the OUTSIDE
    -- Two thirds of the bounding box is covered by no map at all, and the
    -- first cut called all of it sea. It is not: the holes INSIDE Kanto are
    -- the places the overworld graph does not walk through -- Mt. Moon and
    -- the Rock Tunnel under their mountains, Viridian Forest, the Safari
    -- Zone, Cerulean Cave, the power plant. Flooding them turned the region
    -- into a lagoon with the routes as causeways over it, which is exactly
    -- what it looked like (probe_out_worldmap/look/01_region.png) and
    -- exactly as confusing to read as that sounds.
    --
    -- So the sea is only what the OUTSIDE reaches: flood inward from the
    -- border, and every pocket the flood never gets to is land -- highland,
    -- because that is what those places are, and because a wall of rock is
    -- the honest way to draw somewhere you cannot walk.
    build.phase = "coastline"
    local sea = {}
    do
      local q, head = {}, 1
      local function push(i)
        if not sea[i] and cls[i] == OCEAN then sea[i] = true; q[#q + 1] = i end
      end
      for gx = 0, gw - 1 do
        push(gx + 1); push((gh - 1) * gw + gx + 1)
      end
      for gy = 0, gh - 1 do
        push(gy * gw + 1); push(gy * gw + gw)
      end
      while head <= #q do
        local i = q[head]; head = head + 1
        local y = math.floor((i - 1) / gw)
        local x = (i - 1) - y * gw
        for d = 1, 4 do
          local nx = x + (d == 1 and 1 or d == 2 and -1 or 0)
          local ny = y + (d == 3 and 1 or d == 4 and -1 or 0)
          if nx >= 0 and nx < gw and ny >= 0 and ny < gh then
            push(ny * gw + nx + 1)
          end
        end
        if head % 4096 == 0 then breathe() end
      end
    end

    -- the pockets, and how deep into each one every cell sits: a mountain
    -- that rises toward its middle reads as terrain, a flat plateau reads as
    -- a mistake
    local inland, depth = {}, {}
    for i = 1, n do
      if cls[i] == OCEAN and not sea[i] then
        cls[i] = MASS
        inland[#inland + 1] = i
        depth[i] = 0
      end
    end
    do
      local frontier = {}
      for _, i in ipairs(inland) do
        local y = math.floor((i - 1) / gw)
        local x = (i - 1) - y * gw
        local edge = false
        for d = 1, 4 do
          local nx = x + (d == 1 and 1 or d == 2 and -1 or 0)
          local ny = y + (d == 3 and 1 or d == 4 and -1 or 0)
          if nx < 0 or nx >= gw or ny < 0 or ny >= gh then edge = true
          elseif cls[ny * gw + nx + 1] ~= MASS then edge = true end
        end
        if edge then depth[i] = 1; frontier[#frontier + 1] = i end
      end
      local step = 1
      while #frontier > 0 and step < 40 do
        step = step + 1
        local nextf = {}
        for _, i in ipairs(frontier) do
          local y = math.floor((i - 1) / gw)
          local x = (i - 1) - y * gw
          for d = 1, 4 do
            local nx = x + (d == 1 and 1 or d == 2 and -1 or 0)
            local ny = y + (d == 3 and 1 or d == 4 and -1 or 0)
            if nx >= 0 and nx < gw and ny >= 0 and ny < gh then
              local j = ny * gw + nx + 1
              if cls[j] == MASS and depth[j] == 0 then
                depth[j] = step; nextf[#nextf + 1] = j
              end
            end
          end
        end
        frontier = nextf
        breathe()
      end
      -- SMOOTH, and quantised, and both for the same reason. A per-cell hash
      -- makes every neighbour a different height: it looks like television
      -- static rather than hills, and it defeats the run merger completely --
      -- measured, the land mesh went from 156k vertices to 658k the moment
      -- these cells got their own jitter. Value noise over a coarse lattice
      -- gives the interior real shape, and rounding the result to a step puts
      -- long stretches back at the same height so they merge again.
      local STEP = 0.22
      for _, i in ipairs(inland) do
        local y = math.floor((i - 1) / gw)
        local x = (i - 1) - y * gw
        -- two octaves: ridges at 19 cells, and a coarser swell at 47 that
        -- keeps a 200-cell interior from reading as one texture
        local nz = noise2(x, y, 19) * 0.62 + noise2(x, y, 47) * 0.38
        -- the depth term is what lifts a pocket away from its own coastline,
        -- and it has to SATURATE early: uncapped it pinned every cell more
        -- than ten from an edge at the ceiling, and the whole interior of
        -- Kanto came out as one flat plateau at maximum height with the
        -- noise invisible under it. Past about six cells in, the shape is
        -- the noise's job.
        local rise = math.min(1.5, (depth[i] or 1) * 0.26)
        hgt[i] = math.floor((0.35 + rise + (nz - 0.42) * 3.0) / STEP + 0.5) * STEP
        if hgt[i] < 0.25 then hgt[i] = 0.25 end
        -- bare rock on the tops, trees on the skirts, in six bands so the
        -- colour merges into runs the same way the height does
        local t = math.min(1, math.max(0, (hgt[i] - 0.25) / 2.3))
        lum[i] = 0.34 + math.floor(t * 6) / 6 * 0.30
      end
    end
    build.inland = #inland

    ------------------------------------------------------ 4. relief
    -- A wall cell is a building in a town and a mountain on a route, and the
    -- 2D artwork says nothing about which. Its FOOTPRINT does: flood the
    -- connected blob and read its area. Small blobs are buildings and get a
    -- roof; large ones are the landscape and rise with their own size, which
    -- is what gives the region's edges a skyline instead of a kerb.
    build.phase = "relief"
    local seen, roof = {}, {}
    local stack = {}
    local blobs, buildings = 0, 0
    for gy = 0, gh - 1 do
      for gx = 0, gw - 1 do
        local start = gy * gw + gx + 1
        if cls[start] == WALL and not seen[start] then
          local cells, count = {}, 0
          stack[1] = start; seen[start] = true
          local sp = 1
          while sp > 0 do
            local i = stack[sp]; sp = sp - 1
            count = count + 1; cells[count] = i
            local y = math.floor((i - 1) / gw)
            local x = (i - 1) - y * gw
            for k = 1, 4 do
              local nx = x + (k == 1 and 1 or k == 2 and -1 or 0)
              local ny = y + (k == 3 and 1 or k == 4 and -1 or 0)
              if nx >= 0 and nx < gw and ny >= 0 and ny < gh then
                local j = ny * gw + nx + 1
                if cls[j] == WALL and not seen[j] then
                  seen[j] = true; sp = sp + 1; stack[sp] = j
                end
              end
            end
          end
          blobs = blobs + 1
          local isBuilding = count <= BUILDING_MAX
          if isBuilding then buildings = buildings + 1 end
          -- A building's height grows with its footprint but flattens fast,
          -- so a Pokemon Centre is taller than a house and Silph does not
          -- become a needle. A landscape blob rises further and keeps rising
          -- with area, capped so the border mountains do not eat the sky.
          local h
          if isBuilding then
            h = 1.5 + math.min(1.5, count * 0.055)
          else
            h = 1.25 + math.min(1.6, math.sqrt(count) * 0.075)
          end
          for k = 1, count do
            hgt[cells[k]] = h
            roof[cells[k]] = isBuilding
          end
          breathe()
        end
      end
    end
    build.blobs, build.buildings = blobs, buildings

    -- Trees jitter so a forest reads as canopy rather than a mown hedge. A
    -- hash of the position, not random(): the same cell has to come back the
    -- same height every time the region is rebuilt, or a forest crawls.
    for i = 1, n do
      if cls[i] == TREE then
        local y = math.floor((i - 1) / gw)
        local x = (i - 1) - y * gw
        local hsh = (x * 73856093 + y * 19349663) % 1024 / 1024
        hgt[i] = HEIGHT[TREE] + hsh * 0.45
      end
    end
    breathe()

    ------------------------------------------------------ 5. the shore
    -- How far each water cell is from land, three steps out. It is what the
    -- foam is drawn from, and what keeps the deep sea a different colour
    -- from a harbour. A plain BFS off the land edge.
    -- HOW FAR FROM THE BANK, in cells, out to SHORE_SPAN.
    --
    -- Two different things read this and they want different ranges, which
    -- is why it goes further than the foam needs. The foam ring lives in the
    -- first cell or two. The DEPTH ramp saturates at Water.SHORE_MAX (6
    -- tiles = 3 cells). And the SIZE of the body -- which is what decides
    -- whether a piece of water gets a long swell or short chop, exactly as
    -- lib/WaterBody.lua decides it for the overworld -- needs to tell a pond
    -- from an ocean, and a pond is small in a way you cannot see inside four
    -- cells. Twelve is enough for all three.
    build.phase = "shore"
    local SHORE_SPAN = WorldMap3D.SHORE_SPAN
    local shore = {}
    local frontier, nextf = {}, {}
    for i = 1, n do
      local c = cls[i]
      if c == WATER or c == OCEAN then
        shore[i] = SHORE_SPAN     -- open water until the flood says otherwise
      else
        shore[i] = -1             -- land: not water, never drawn as sea
        frontier[#frontier + 1] = i
      end
    end
    for step = 1, SHORE_SPAN do
      for k = 1, #frontier do
        local i = frontier[k]
        local y = math.floor((i - 1) / gw)
        local x = (i - 1) - y * gw
        for d = 1, 4 do
          local nx = x + (d == 1 and 1 or d == 2 and -1 or 0)
          local ny = y + (d == 3 and 1 or d == 4 and -1 or 0)
          if nx >= 0 and nx < gw and ny >= 0 and ny < gh then
            local j = ny * gw + nx + 1
            -- land was seeded at -1, so only unreached WATER matches
            if shore[j] == SHORE_SPAN then
              shore[j] = step
              nextf[#nextf + 1] = j
            end
          end
        end
      end
      frontier, nextf = nextf, {}
      breathe()
      if #frontier == 0 then break end
    end

    -- WHICH PLACED MAPS TOUCH, which is what a route is walked over.
    --
    -- Geometry, not `def.connections`. The connection records are the
    -- engine's own and nothing in this mod has ever had to read their shape;
    -- two outdoor maps that connect are two rectangles that ABUT, and that
    -- is a fact about the placement the walk already produced. One cell of
    -- slack, because a connection can be offset along its shared edge.
    build.phase = "routes"
    local adj = {}
    for i = 1, #places do adj[i] = {} end
    for i = 1, #places do
      local a = places[i]
      for j = i + 1, #places do
        local b = places[j]
        local gapX = math.max(a.x - (b.x + b.w), b.x - (a.x + a.w))
        local gapY = math.max(a.y - (b.y + b.h), b.y - (a.y + a.h))
        if gapX <= 1 and gapY <= 1 then
          adj[i][#adj[i] + 1] = j
          adj[j][#adj[j] + 1] = i
        end
      end
      breathe()
    end

    R = {
      adj = adj,
      gw = gw, gh = gh, n = n,
      cls = cls, hgt = hgt, lum = lum, shore = shore, roof = roof,
      places = places,
      originX = originX, originY = originY,
      rampLo = rampLo, rampHi = rampHi,
      seamFixes = fixes, blobs = blobs, buildings = buildings,
      inland = build.inland or 0,
      ms = (os.clock() - t0) * 1000,
    }
    build.phase = "meshing"
    coroutine.yield()
  end)
end

-- ============================================================================
-- 2. THE MESH
-- ============================================================================

-- FLOAT colour, not byte, and the reason is worth a line because it cost a
-- whole render.
--
-- LOVE 11 takes colours in 0..1 everywhere, vertex colours included. Written
-- as 0..255 -- which is what LOVE 0.10 wanted and what every older example
-- shows -- every channel clamps to 1 and the entire region draws WHITE: land,
-- sky and all, with the water's shore attribute pinned at 1 so the foam ran
-- everywhere at once. That is exactly the frame that came back
-- (probe_out_worldmap/look/08_elsewhere_close.png). Floats leave no room for
-- the ambiguity, and 12 bytes a vertex over 200k vertices is 2 MB.
local FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexTexCoord", "float", 2 },   -- world x,z in cells: fog, waves, noise
  { "VertexColor", "float", 4 },      -- shaded colour; alpha carries the shore
}

-- A cell's colour before shading. `lum` is how light the cell's own tile is
-- drawn, and it does two different jobs: on ground it chooses along the
-- grass-to-path ramp (which is the whole reason routes read as routes), and
-- everywhere else it just varies the surface so a wall of forty identical
-- boxes is not forty identical boxes.
local function cellColor(id, l, isRoof, top)
  if id == GROUND then
    local lo, hi = R.rampLo, R.rampHi
    local t = (l - lo) / math.max(0.001, hi - lo)
    t = math.min(1, math.max(0, t))
    t = t * t * (3 - 2 * t)      -- smoothstep: the middle of the ramp is mud
    local g, p = COLOR[GROUND], PATH_COLOR
    return g[1] + (p[1] - g[1]) * t,
           g[2] + (p[2] - g[2]) * t,
           g[3] + (p[3] - g[3]) * t
  elseif id == WALL then
    local base = isRoof and (top and ROOF_COLOR or WALL_COLOR) or ROCK_COLOR
    local k = 0.86 + l * 0.28
    return base[1] * k, base[2] * k, base[3] * k
  elseif id == MASS then
    -- The unwalked interior: forest nearly everywhere, bare rock only where
    -- it is genuinely high. Ramped from the middle of the height range at
    -- first, which put most of the interior halfway along a green-to-grey
    -- mix -- and a region-sized field of half-grey green is the exact colour
    -- of a desert mesa, which is what it drew as.
    local t = math.min(1, math.max(0, (l - 0.50) / 0.14))
    local f, r2 = MASS_LOW, MASS_HIGH
    return f[1] + (r2[1] - f[1]) * t,
           f[2] + (r2[2] - f[2]) * t,
           f[3] + (r2[3] - f[3]) * t
  end
  local c = COLOR[id] or ROCK_COLOR
  local k = 0.84 + l * 0.32
  return c[1] * k, c[2] * k, c[3] * k
end

-- One quad, four vertices, into the running vertex list. Wound so the front
-- face is the one you can see; nothing culls here, so the winding only has
-- to be consistent for the shader's sake.
local function quad(V4, x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4,
                    r, g, b, a)
  local m = #V4
  V4[m + 1] = { x1, y1, z1, x1, z1, r, g, b, a }
  V4[m + 2] = { x2, y2, z2, x2, z2, r, g, b, a }
  V4[m + 3] = { x3, y3, z3, x3, z3, r, g, b, a }
  V4[m + 4] = { x4, y4, z4, x4, z4, r, g, b, a }
end

-- A side quad, whose FOOT is darker than its head.
--
-- Every side emitted below is wound top-pair first, bottom-pair second, so
-- one factor on vertices 3 and 4 is a contact shadow along the whole base of
-- every wall, tree and cliff in the region -- the cheapest ambient occlusion
-- there is, and at this zoom the thing that stops a raised block from
-- looking like a sticker floating over the grass.
local AO_FOOT = 0.58
local function sideQuad(V4, x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4,
                        r, g, b)
  local m = #V4
  local fr, fg, fb = r * AO_FOOT, g * AO_FOOT, b * AO_FOOT
  V4[m + 1] = { x1, y1, z1, x1, z1, r, g, b, 1 }
  V4[m + 2] = { x2, y2, z2, x2, z2, r, g, b, 1 }
  V4[m + 3] = { x3, y3, z3, x3, z3, fr, fg, fb, 1 }
  V4[m + 4] = { x4, y4, z4, x4, z4, fr, fg, fb, 1 }
end

-- Quads to triangles. LOVE will take a "triangles" mesh with an index map,
-- which is what keeps a 30k-quad region at 120k vertices instead of 180k.
local function quadIndices(quads)
  local idx, k = {}, 0
  for q = 0, quads - 1 do
    local b = q * 4
    idx[k + 1] = b + 1; idx[k + 2] = b + 2; idx[k + 3] = b + 3
    idx[k + 4] = b + 1; idx[k + 5] = b + 3; idx[k + 6] = b + 4
    k = k + 6
  end
  return idx
end

local function buildMeshes()
  local gw, gh = R.gw, R.gh
  local cls, hgt, lum, shore, roof = R.cls, R.hgt, R.lum, R.shore, R.roof
  local hx, hz = gw * 0.5, gh * 0.5      -- the region is centred on its middle

  local land, water = {}, {}
  local lumTol = (R.rampHi - R.rampLo) * 0.16 + 0.004

  local function isSea(i) return cls[i] == WATER or cls[i] == OCEAN end

  -- HILLSHADE: a top face lit by which way the ground is TILTING, read off
  -- the height difference toward the north-west.
  --
  -- Side faces carry the relief when you are close to it, and carry nothing
  -- at the zoom that fits a region on screen -- a one-cell step is a single
  -- pixel of wall there. Shading the tops is what makes the interior read as
  -- hills rather than as a flat green field with mottling on it. Quantised
  -- to five steps so that flat ground (every cell of which shades the same)
  -- still merges into long runs.
  local function hillshade(gx, gy, h)
    local hnw = h
    if gx > 0 and gy > 0 then hnw = hgt[(gy - 1) * gw + (gx - 1) + 1] or h end
    local d = (h - hnw) * 2.0
    if d > 2 then d = 2 elseif d < -2 then d = -2 end
    return math.floor(d + 0.5)
  end

  for gy = 0, gh - 1 do
    local gx = 0
    while gx < gw do
      local i = gy * gw + gx + 1
      local id = cls[i]
      local h = hgt[i]

      if isSea(i) then
        -- SEA. Merge along x while the shore band is the same, so the foam
        -- has geometry to sit on and the open water is a handful of quads.
        local s = shore[i]
        local run = 1
        while gx + run < gw do
          local j = gy * gw + gx + run + 1
          if not isSea(j) or shore[j] ~= s then break end
          run = run + 1
        end
        local x1, x2 = gx - hx, gx + run - hx
        local z1, z2 = gy - hz, gy + 1 - hz
        -- ALPHA carries the distance to the bank, in cells, normalised over
        -- SHORE_SPAN. Three separate things in lib/Water.lua's model read it
        -- and each wants a different slice of the range: the foam ring
        -- (the first cell), the depth ramp (Water.SHORE_MAX, 6 tiles), and
        -- the size of the body, which is what decides between a long swell
        -- and short chop -- WaterBody's job on the overworld, and here the
        -- only measurement of it available.
        local a = math.max(0, math.min(1, s / WorldMap3D.SHORE_SPAN))
        quad(water, x1, h, z1, x2, h, z1, x2, h, z2, x1, h, z2,
             1, 1, 1, a)
        gx = gx + run
      else
        -- LAND. Merge along x while class and height agree. Ground is 42% of
        -- the region and mostly flat, so most of it collapses into runs.
        local l = lum[i]
        local isRoof = roof[i]
        local hs = hillshade(gx, gy, h)
        local run = 1
        while gx + run < gw do
          local j = gy * gw + gx + run + 1
          if isSea(j) or cls[j] ~= id or hgt[j] ~= h then break end
          if hillshade(gx + run, gy, h) ~= hs then break end
          -- keep the ground ramp from banding: a run only extends while the
          -- lightness is close enough that one colour can stand for all of
          -- it. The tolerance is a fraction of the ramp's OWN width, because
          -- that width is a measured property of the tileset (percentiles,
          -- see the build) and a fixed 0.06 is either the whole range or
          -- none of it depending on which tileset this is.
          if math.abs((lum[j] or 0.5) - l) > lumTol then break end
          if roof[j] ~= isRoof then break end
          run = run + 1
        end
        local x1, x2 = gx - hx, gx + run - hx
        local z1, z2 = gy - hz, gy + 1 - hz

        local r, g, b = cellColor(id, l, isRoof, true)
        local function shaded(k)
          return math.min(1, r * k), math.min(1, g * k), math.min(1, b * k)
        end
        local tr, tg, tb = shaded(SHADE_TOP * (1 + hs * 0.11))
        quad(land, x1, h, z1, x2, h, z1, x2, h, z2, x1, h, z2, tr, tg, tb, 1)

        -- Sides, per cell of the run and only where the neighbour is lower.
        -- The flat majority of the region emits none of these at all.
        local sr, sg, sb = cellColor(id, l, isRoof, false)
        local function sideShade(k)
          return math.min(1, sr * k), math.min(1, sg * k), math.min(1, sb * k)
        end
        local function neighbourH(nx, ny)
          if nx < 0 or nx >= gw or ny < 0 or ny >= gh then return -0.30 end
          return hgt[ny * gw + nx + 1] or 0
        end
        for c = 0, run - 1 do
          local cxp = gx + c
          local ax, bx = cxp - hx, cxp + 1 - hx
          -- north (-z)
          local nh = neighbourH(cxp, gy - 1)
          if nh < h then
            local r2, g2, b2 = sideShade(SHADE_N)
            sideQuad(land, ax, h, z1, bx, h, z1, bx, nh, z1, ax, nh, z1, r2, g2, b2)
          end
          -- south (+z)
          nh = neighbourH(cxp, gy + 1)
          if nh < h then
            local r2, g2, b2 = sideShade(SHADE_S)
            sideQuad(land, bx, h, z2, ax, h, z2, ax, nh, z2, bx, nh, z2, r2, g2, b2)
          end
          -- west (-x), only at the run's own edge
          if c == 0 then
            nh = neighbourH(cxp - 1, gy)
            if nh < h then
              local r2, g2, b2 = sideShade(SHADE_W)
              sideQuad(land, ax, h, z2, ax, h, z1, ax, nh, z1, ax, nh, z2, r2, g2, b2)
            end
          end
          -- east (+x)
          if c == run - 1 then
            nh = neighbourH(cxp + 1, gy)
            if nh < h then
              local r2, g2, b2 = sideShade(SHADE_E)
              sideQuad(land, bx, h, z1, bx, h, z2, bx, nh, z2, bx, nh, z1, r2, g2, b2)
            end
          end
        end
        gx = gx + run
      end
    end
  end

  local function makeMesh(verts)
    if #verts < 4 then return nil, 0 end
    local ok, mesh = pcall(love.graphics.newMesh, FORMAT, verts, "triangles", "static")
    if not ok or not mesh then
      log("mesh failed: " .. tostring(mesh))
      return nil, 0
    end
    pcall(mesh.setVertexMap, mesh, quadIndices(#verts / 4))
    return mesh, #verts
  end

  -- THE SKIRT: open sea, far past the grid, so the region sits IN an ocean
  -- instead of on a slab with a cut edge.
  --
  -- The drop below the grid's own ocean has to clear the WAVE, not just the
  -- surface: both planes are displaced by the same vertex shader, so a skirt
  -- 0.05 under a sea that swings +/-0.11 spends half of every cycle above it
  -- and the two interpenetrate. That drew as horizontal stripes across the
  -- whole ocean and it looked like a broken depth buffer, which is what it
  -- was. A third of a cell clears the swing with room to spare.
  do
    local sk = math.max(gw, gh) * 4
    local y = HEIGHT[OCEAN] - 0.34
    -- alpha 1, NOT 0: in the ported water model alpha is the distance to the
    -- nearest bank, and the open sea is as far from one as water gets. Sent
    -- as 0 it read as the shallowest possible water, so the whole horizon
    -- came back as pale sand-through-water and the region sat on a slab with
    -- a hard edge where the grid's own deep ocean stopped.
    quad(water, -sk, y, -sk, sk, y, -sk, sk, y, sk, -sk, y, sk, 1, 1, 1, 1)
  end

  local lm, lc = makeMesh(land)
  local wm, wc = makeMesh(water)
  R.landMesh, R.waterMesh = lm, wm
  R.landVerts, R.waterVerts = lc, wc
end

-- ============================================================================
-- 3. THE SHADERS
-- ============================================================================
--
-- No texture is sampled anywhere: the colour is per vertex and the water is
-- arithmetic. That is deliberate -- this has to run on the phone build too,
-- and lib/Voxel3D.lua's shader ladder exists because a vertex stage that
-- fetches a texture does not link on some Adreno drivers. Nothing here
-- fetches anything in either stage.

-- FOG IS COMPUTED PER PIXEL, from a world position passed across, and not
-- per vertex.
--
-- Per-vertex is the cheaper and usual way and it is wrong for this geometry:
-- the run merger makes quads hundreds of cells long and the sea skirt is a
-- SINGLE quad three thousand cells across, so a value interpolated from its
-- corners is the same everywhere on it. The ocean therefore came out
-- uniformly hazy right up to the camera, with a hard line where the skirt
-- met the grid. Distance belongs to the pixel, so it is measured there.
local LAND_VS = [[
extern mat4 mvp;
varying vec3 vWorldPos;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vWorldPos = vertex_position.xyz;
  return mvp * vec4(vertex_position.xyz, 1.0);
}
]]

local LAND_FS = [[
extern vec3 camPos;
extern vec2 fogRange;
extern vec3 fogColor;
extern vec3 sunTint;
varying vec3 vWorldPos;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  float d = distance(vWorldPos, camPos);
  float f = clamp((d - fogRange.x) / max(0.001, fogRange.y - fogRange.x),
                  0.0, 1.0);
  vec3 c = color.rgb * sunTint;
  c = mix(c, fogColor, f * f * 0.72);
  return vec4(c, 1.0);
}
]]

-- ---------------------------------------------------------------- THE WATER
--
-- This is lib/Water.lua's surface, ported. Not "inspired by" -- the same
-- three trains at the same wavenumbers, the same dispersion, the same
-- Gerstner-ish crest steepening, the same terraced bed under the same
-- Beer-Lambert absorption, the same Fresnel share of the sky, the same
-- cel-quantised glint rings with the window kept as a FRACTION of the slope
-- this water can actually make, and the same lapping foam ring at the bank.
-- The constants below are that file's constants, unchanged and in its units.
--
-- ITS UNITS ARE WORLD PIXELS, and this renderer's are CELLS, so world
-- position is multiplied by 16 before any of it is touched. Copying the
-- numbers and then feeding them cells would give waves sixteen times too
-- long, which is the kind of thing that looks deliberate.
--
-- WHAT IS NOT PORTED, and why: ice, rain chop, wind streaks, thermal
-- inertia, snow veil. All of those are driven by lib/Water.lua's BODY state,
-- which lags live weather on the map the player is standing on -- there is no
-- such thing for thirty-four maps at once, and a world map showing Fuchsia's
-- weather over Pewter's sea would be worse than showing none.
local WATER_VS = [[
extern mat4 mvp;
extern float time;
extern float swellAmp;      // world pixels of displacement, Water's row
varying vec3 vWorldPos;
varying vec2 vPx;           // world PIXELS, which is Water.lua's unit
varying float vShoreN;      // 0..1 over SHORE_SPAN cells from the bank
varying float vH;           // the swell here, -1..1, steepened
varying vec3 vN;            // and its analytic normal

// Water.WAVE_L0 / M0 / S0 -- long swell, mid cross, short chop. Fixed
// vectors: a wave vector that is a function of position (which is how this
// used to be written) has a gradient with a world-position term in it, and
// four thousand pixels out that term is 28x the wave it perturbs. That is
// not a shorter wave, it is noise with a period.
const vec2 KA = vec2(0.05040, 0.02736);
const vec2 KB = vec2(-0.02232, 0.04176);
const vec2 KC = vec2(0.10763, -0.14825);
const vec3 WAVE_K = vec3(0.05735, 0.04735, 0.18319);
// Water.RATE_LONG / MID / SHORT: omega ~ sqrt(k), so each train keeps its
// own tempo instead of the three sliding as one sheet.
const vec3 RATE = vec3(1.0, 0.90867, 1.78730);
const float STEEP = 0.22;

// Water.MIX_*: how LOUD each train is, by the size of the body. The long one
// dies on a puddle, the short one dies at sea, and the mid one never dies --
// a single surviving train is corduroy, and the smallest puddle still has to
// keep two directions crossing or it stops reading as water.
vec3 waveMix(float size) {
  float hi = clamp(size, 0.0, 1.0);
  vec3 w = vec3(0.55 * (0.10 + 0.90 * hi),
                0.45,
                0.55 * (1.0 - hi));
  return w / max(w.x + w.y + w.z, 1e-6);
}

float swellEval(vec2 px, float size, out vec3 ang, out vec3 wmix, out float ah) {
  wmix = waveMix(size);
  vec3 ph = time * 0.55 * RATE;          // Water.RATE
  ang = vec3(dot(px, KA) - ph.x,
             dot(px, KB) + ph.y,
             dot(px, KC) - ph.z);
  float h = sin(ang.x) * wmix.x + sin(ang.y) * wmix.y + sin(ang.z) * wmix.z;
  ah = abs(h);
  return h + STEEP * h * ah;
}

vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vec3 w = vertex_position.xyz;
  vPx = w.xz * 16.0;
  vShoreN = VertexColor.a;

  // The size of this body of water, out of the only measurement of it there
  // is here: how far from the bank. A pond is near a bank everywhere; an
  // ocean is not. It is what lib/WaterBody.lua measures off the map for the
  // overworld, arrived at differently.
  float size = clamp(vShoreN * 1.6, 0.0, 1.0);

  vec3 ang, wmix; float ah;
  float h = swellEval(vPx, size, ang, wmix, ah);
  vH = h;

  // The analytic normal, in Water.lua's own terms: the gradient of the sum
  // of the trains, scaled by the amplitude, straight into a normal. No
  // normal map, no derivative, no second render target.
  float sc = 1.0 + 2.0 * STEEP * ah;
  vec2 g = (cos(ang.x) * wmix.x * KA
          + cos(ang.y) * wmix.y * KB
          + cos(ang.z) * wmix.z * KC) * sc;
  vN = normalize(vec3(-g.x * swellAmp, 1.0, -g.y * swellAmp));

  // and the sheet itself moves: swellAmp is in world pixels, this is cells
  w.y += swellAmp * h / 16.0;

  vWorldPos = w;
  return mvp * vec4(w, 1.0);
}
]]

local WATER_FS = [[
extern vec3 camPos;
extern vec2 fogRange;
extern vec3 fogColor;
extern vec3 sunTint;
extern vec3 skyColor;       // what the surface mirrors
extern vec3 sunRay;         // the direction the light travels
extern float time;
extern float swellAmp;
extern float shoreSpan;     // cells the shore field spans
extern float artOn;         // is assets/water/water.png bound
extern float artMix;        // Water.ART_MIX
extern float artScale;      // Water.ART_SCALE, in world pixels
// 1 when the camera is close enough for a wave to be worth drawing, 0 when
// the whole region is on screen and a wave is a third of a pixel
extern float near;
varying vec3 vWorldPos;
varying vec2 vPx;
varying float vShoreN;
varying float vH;
varying vec3 vN;

// Water.SAND / ABSORB / DEEP_TINT / ALPHA_* / REFLECT / FOAM / BED, and the
// tile blue the overworld's water sheet wears. Absorption is per world PIXEL
// of depth, per channel: four pixels down the sand is already a green
// shallow, twelve down it is the deep blue.
const vec3 SAND      = vec3(0.92, 0.86, 0.66);
const vec3 ABSORB    = vec3(0.220, 0.090, 0.030);
const vec3 DEEP_TINT = vec3(0.42, 0.58, 0.92);
const vec3 FOAM      = vec3(0.93, 0.97, 1.00);
const vec3 TILE_BLUE = vec3(0.29, 0.53, 0.85);
const float ALPHA_SHALLOW = 0.15;
const float ALPHA_DEEP    = 0.62;
const float REFLECT       = 0.85;
const float SHORE_MAX     = 6.0;    // TILES from the bank where deep saturates
const float GLINT_LO      = 0.34;
const float GLINT_HI      = 1.00;
const float SPARKLE       = 0.55;
const float STEEP         = 0.22;
const vec3  WAVE_K = vec3(0.05735, 0.04735, 0.18319);

vec3 waveMix(float size) {
  float hi = clamp(size, 0.0, 1.0);
  vec3 w = vec3(0.55 * (0.10 + 0.90 * hi), 0.45, 0.55 * (1.0 - hi));
  return w / max(w.x + w.y + w.z, 1e-6);
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  float d = distance(vWorldPos, camPos);
  float fog = clamp((d - fogRange.x) / max(0.001, fogRange.y - fogRange.x),
                    0.0, 1.0);

  // the two-pixel screen checker this mod dithers every hard step with
  vec2 gc = floor(sc / 2.0);
  float check = mod(gc.x + gc.y, 2.0);

  // How much fine detail this PIXEL is entitled to.
  //
  // `near` is a property of the camera and it is not enough on its own: in a
  // close view the sea still runs to the horizon. A wave crest is about 110
  // world pixels of wavelength, so out there a whole train fits inside one
  // screen pixel, and what the glint does with that is draw the crest lines
  // as long thin diagonal scratches across the water. SQUARED, because a
  // linear falloff still left them legible through the middle distance,
  // which is where they were most visible.
  float dfar = 1.0 - fog;
  float detail = near * dfar * dfar;

  float shoreCells = vShoreN * shoreSpan;
  float shoreTiles = shoreCells * 2.0;          // a cell is two tiles
  float deep = clamp(shoreTiles / SHORE_MAX, 0.0, 1.0);
  float size = clamp(vShoreN * 1.6, 0.0, 1.0);

  // THE BED, in terraces of two tiles, exactly as Water.BED lays it out:
  // -5, -7, -9, -11, -13 world pixels. One smooth ramp instead read as a
  // swimming pool's deep end from a camera this high.
  // the cell touching the bank is the FIRST terrace (-5), not the second:
  // the shore field counts that cell as one cell out, which is two tiles,
  // and dividing that straight away started every shoreline one step deep
  float terrace = clamp(floor((shoreTiles - 1.0) / 2.0), 0.0, 4.0);
  float depthPx = 5.0 + terrace * 2.0;
  // Beer-Lambert: what is left of the sand after the water has taken its
  // share, per channel. Red goes first, which is why shallow water is green
  // and deep water is blue in every ocean anyone has looked at.
  vec3 through = SAND * exp(-ABSORB * depthPx);

  // THE BODY: the water's own colour, with the surface art riding on it at a
  // third if there is any (assets/water/water.png -- the same sheet and the
  // same ART_MIX the overworld uses, sampled in world XZ so it does not swim
  // when the camera moves), leaning to the deep tint away from the bank.
  vec3 body = TILE_BLUE;
  if (artOn > 0.5) {
    // faded out with the rest of the fine detail: the sheet repeats every 64
    // world pixels, and at the zoom that fits a region on screen that is a
    // couple of pixels a tile -- a caustic drawn at that size is not a
    // caustic, it is grain over the whole sea.
    vec3 art = Texel(tex, vPx / artScale).rgb;
    body = mix(body, art, artMix * detail);
  }
  body = mix(body, body * DEEP_TINT, deep);

  // coverage: the shallows are mostly bed seen through water, the deep is
  // mostly the body's own colour
  float alpha = mix(ALPHA_SHALLOW, ALPHA_DEEP, deep);
  vec3 c = mix(through, body, alpha);

  // FRESNEL off the swell's own normal: looking down into water shows the
  // bed, looking across it shows the sky. Smooth on purpose -- stepped and
  // dithered it blotches, because the normal sweeps every threshold every
  // second.
  vec3 V = normalize(camPos - vWorldPos);
  float f1 = 1.0 - clamp(dot(vN, V), 0.0, 1.0);
  float f2 = f1 * f1;
  float reflW = clamp((0.04 + 0.96 * f2 * f2) * REFLECT, 0.0, 1.0);
  c = mix(c, skyColor, reflW);

  // VALUE MASS: trough dark, crest light, three hard rungs with the checker
  // jittering the edge. This is what keeps it a four-colour diorama rather
  // than an airbrush.
  float h = vH + (check - 0.5) * 0.16;
  float band = - step(h, -0.35) * 0.06
               + step(0.30, h) * 0.05
               + step(0.60, h) * 0.05;
  c *= 1.0 + band * detail;

  // THE GLINT: the analytic normal against the sun, quantised to rings.
  //
  // The window is a pair of FRACTIONS of the slope this particular water can
  // reach, never an absolute deviation. Measured in the overworld at the
  // default row, the largest deviation anywhere on the water was 0.0269
  // against an absolute LO of 0.020 -- so the rings were not rare, they were
  // unreachable, and the effect had never once been visible outside dawn.
  // As a fraction the window rides the amplitude by construction: a crest on
  // an ocean and a crest on a puddle both glint.
  vec3 wmix = waveMix(size);
  float ah = abs(vH);
  float gradMax = dot(wmix, WAVE_K) * (1.0 + 2.0 * STEEP * ah);
  float devMax = max(swellAmp * gradMax * length(sunRay.xz), 1e-5);
  float flatDot = -sunRay.y;
  float sg = smoothstep(flatDot + GLINT_LO * devMax,
                        flatDot + GLINT_HI * devMax,
                        dot(vN, -sunRay));
  sg = floor(sg * 4.0 + 0.5) / 4.0;
  c = mix(c, FOAM, sg * SPARKLE * detail);

  // THE SHORE: a foam ring where the sheet meets the bank, lapping on its
  // own clock. In tiles, like Water.SHORE_FOAM, but reaching a whole cell
  // further -- the overworld measures the bank per tile and this grid cannot
  // see inside a cell, so a quarter-tile ring would land on nothing at all.
  float lap = 0.45 * sin(time * 2.0 + vPx.x * 0.021 + vPx.y * 0.016);
  float ring = step(shoreTiles, 2.2 + lap + (check - 0.5) * 0.5);
  c = mix(c, FOAM, ring * 0.62);

  c *= sunTint;
  c = mix(c, fogColor, fog * fog * 0.72);
  return vec4(c, 1.0);
}
]]

local shaders = { land = nil, water = nil, tried = false }
local function ensureShaders()
  if shaders.tried then return shaders.land ~= nil end
  shaders.tried = true
  local ok1, s1 = pcall(love.graphics.newShader, LAND_FS, LAND_VS)
  local ok2, s2 = pcall(love.graphics.newShader, WATER_FS, WATER_VS)
  if not ok1 then log("land shader: " .. tostring(s1)) end
  if not ok2 then log("water shader: " .. tostring(s2)) end
  shaders.land = ok1 and s1 or nil
  shaders.water = ok2 and s2 or nil
  return shaders.land ~= nil
end

-- ============================================================================
-- 4. THE CAMERA
-- ============================================================================

-- NORTH IS UP, and the yaw starts at zero for that reason alone. The first
-- cut opened at 0.42 radians with a drifting sway on top, and a map of a
-- place you know, turned twenty-five degrees and rocking, does not read as
-- that place at all -- it reads as upside down. A world map may be tilted
-- toward the viewer (it is a diorama), but it may not be rotated off north
-- unless the player rotates it.
local cam = {
  fx = 0, fz = 0, dist = 240, yaw = 0, pitch = 0.86,        -- current
  tfx = 0, tfz = 0, tdist = 240, tyaw = 0, tpitch = 0.86,   -- wanted
  wide = true, drift = 0, eye = { 0, 0, 0 }, mvp = nil,
}

local function approach(a, b, rate, dt)
  local k = 1 - math.exp(-rate * dt)
  return a + (b - a) * k
end

local FOV = math.rad(42)

-- The distance that fits a box of `cw` by `ch` cells on screen, given how far
-- the camera is tilted over.
--
-- Closed form first, then MEASURED and corrected, because the closed form is
-- wrong and cannot be made right: under a tilt the near edge of the ground is
-- much closer to the eye than the far edge, so it projects much larger, and
-- no single foreshortening factor describes both. The first cut used
-- `ch * sin(pitch)` and cut the top and bottom off Kanto. What follows fits
-- the actual thing being fitted: put the four corners through the actual
-- matrix, look at how far outside the frame they land, and back off by that
-- much. Three rounds is enough -- each one overshoots by less than the last.
local buildViewProjection    -- forward: shares the matrix the frame uses

local function fitDistance(cw, ch, pitch, cx, cz, headroom)
  local w, h = love.graphics.getDimensions()
  local aspect = w / math.max(1, h)
  local needV = math.max(ch * math.sin(pitch), cw / aspect)
  local dist = needV * 1.16 / (2 * math.tan(FOV / 2))
  cx, cz = cx or 0, cz or 0
  local want = headroom or 0.90

  for _ = 1, 3 do
    local m = buildViewProjection(cx, cz, dist, pitch, cam.yaw)
    local worst = 0
    for sx = -1, 1, 2 do
      for sz = -1, 1, 2 do
        for _, y in ipairs({ 0, 2.5 }) do
          local x = cx + sx * cw * 0.5
          local z = cz + sz * ch * 0.5
          local px = m[1] * x + m[2] * y + m[3] * z + m[4]
          local py = m[5] * x + m[6] * y + m[7] * z + m[8]
          local pw = m[13] * x + m[14] * y + m[15] * z + m[16]
          if pw > 0.001 then
            worst = math.max(worst, math.abs(px / pw), math.abs(py / pw))
          else
            worst = math.max(worst, 2)     -- behind the eye: much too close
          end
        end
      end
    end
    if worst <= want then break end
    dist = dist * (worst / want)
  end
  return dist
end

local function frameWholeRegion()
  cam.tfx, cam.tfz = 0, 0
  cam.tpitch = 0.86
  -- the banner across the bottom eats a tenth of the frame, so the region is
  -- fitted into rather less than all of it
  cam.tdist = fitDistance(R.gw, R.gh, cam.tpitch, 0, 0, 0.96)
  cam.wide = true
end

local function frameOn(px, pz)
  cam.tfx, cam.tfz = px - R.gw * 0.5, pz - R.gh * 0.5
  cam.tpitch = 0.70
  cam.tdist = fitDistance(84, 84, cam.tpitch, cam.tfx, cam.tfz, 0.90)
  cam.wide = false
end

-- Where the eye sits for a given pose, and the matrix that goes with it. One
-- function so the fit above and the frame below can never disagree about
-- what the camera is -- which they would, written twice.
local function eyeFor(cx, cz, dist, pitch, yaw)
  local ch = math.cos(pitch)
  return {
    cx + math.sin(yaw) * ch * dist,
    math.sin(pitch) * dist,
    cz + math.cos(yaw) * ch * dist,
  }
end

buildViewProjection = function(cx, cz, dist, pitch, yaw)
  local w, h = love.graphics.getDimensions()
  local far = math.max(dist * 6, 4000)
  local proj = Mat4.perspective(FOV, w / math.max(1, h), 1.0, far)

  -- FLIP CLIP-SPACE Y, and this is not optional.
  --
  -- Mat4.perspective emits textbook GL clip space with +Y up. This renderer
  -- bypasses LOVE's own transform_projection and draws into a CANVAS, whose
  -- coordinates run Y DOWN -- so without the flip the entire region
  -- composites mirrored top to bottom. It did, and the giveaway was in the
  -- perspective rather than in the map: the camera sits south of Kanto, so
  -- the south edge is the near one and should be the WIDE one, and the wide
  -- edge was coming out at the top of the frame.
  --
  -- lib/Voxel3D.lua's viewProjection does exactly this and says exactly why;
  -- this file had to learn it the second time. Winding flips with it, which
  -- costs nothing here because the pass culls nothing.
  proj = Mat4.mul(Mat4.scale(1, -1, 1), proj)

  local view = Mat4.lookAt(eyeFor(cx, cz, dist, pitch, yaw),
                           { cx, 0, cz }, { 0, 1, 0 })
  return Mat4.mul(proj, view)
end

local function updateCamera(dt)
  cam.drift = cam.drift + dt * 0.045
  local rate = 3.2
  cam.fx = approach(cam.fx, cam.tfx, rate, dt)
  cam.fz = approach(cam.fz, cam.tfz, rate, dt)
  cam.dist = approach(cam.dist, cam.tdist, rate * 0.8, dt)
  cam.pitch = approach(cam.pitch, cam.tpitch, rate, dt)
  cam.yaw = approach(cam.yaw, cam.tyaw, rate, dt)

  -- the idle sway is for the CLOSE view, where it makes a place feel looked
  -- at. In the wide view it is a map being rocked, so there is none.
  local yaw = cam.yaw + (cam.wide and 0 or math.sin(cam.drift) * 0.05)
  cam.eye = eyeFor(cam.fx, cam.fz, cam.dist, cam.pitch, yaw)
  cam.mvp = buildViewProjection(cam.fx, cam.fz, cam.dist, cam.pitch, yaw)

  -- FOG, and the first cut had it eating the picture: the band ran from
  -- 0.55x to 1.9x the camera distance, which in the close view put the far
  -- half of everything at full fog and rendered Kanto as a sheet of white
  -- (probe_out_worldmap/look/01_region.png). Haze belongs BEHIND the
  -- subject, so the near edge starts past the thing being looked at and the
  -- far edge is out where the sea meets the sky.
  cam.near = cam.dist * 1.25
  cam.far = cam.dist * 3.4
end

-- World point to screen pixel, through the same matrix the mesh went
-- through. Returns nil behind the camera, which is the case a pin has to
-- handle or it appears mirrored on the far side of the screen.
local function project(x, y, z)
  local m = cam.mvp
  if not m then return nil end
  local cx = m[1] * x + m[2] * y + m[3] * z + m[4]
  local cy = m[5] * x + m[6] * y + m[7] * z + m[8]
  local cw = m[13] * x + m[14] * y + m[15] * z + m[16]
  if cw <= 0.001 then return nil end
  local w, h = love.graphics.getDimensions()
  -- No Y flip here: the matrix already carries it (buildViewProjection). It
  -- used to be flipped in BOTH places, which cancelled out for the pins and
  -- not for the mesh -- so every name plate sat on the wrong city while
  -- looking perfectly plausible on its own.
  return (cx / cw * 0.5 + 0.5) * w, (cy / cw * 0.5 + 0.5) * h, cw
end

-- ============================================================================
-- 5. THE FRAME
-- ============================================================================

local canvases = { color = nil, depth = nil, w = 0, h = 0 }
local function ensureCanvases(w, h)
  if canvases.color and canvases.w == w and canvases.h == h then return true end
  if canvases.color and canvases.color.release then pcall(canvases.color.release, canvases.color) end
  if canvases.depth and canvases.depth.release then pcall(canvases.depth.release, canvases.depth) end
  local ok1, c = pcall(love.graphics.newCanvas, w, h)
  local ok2, d = pcall(love.graphics.newCanvas, w, h,
                       { format = "depth24", readable = false })
  if not (ok1 and ok2 and c and d) then
    canvases.color, canvases.depth = nil, nil
    return false
  end
  canvases.color, canvases.depth, canvases.w, canvases.h = c, d, w, h
  return true
end

-- The sky, and the colours everything else is tinted by. One place, because
-- the fog has to be the sky or the horizon shows a seam.
local SKY_TOP = { 0.20, 0.42, 0.72 }
local SKY_LOW = { 0.60, 0.76, 0.88 }
local FOG = { 0.57, 0.72, 0.85 }
local SUN = { 1.04, 1.00, 0.93 }

-- The direction the sunlight TRAVELS, which is what the glint window is
-- measured against. South-east and about 45 degrees up, which is where
-- lib/ShadowMap.lua hangs it for the overworld -- so a crest on the world
-- map catches the light from the same place a crest in the game does. Kept
-- normalised: the glint reads `length(sunRay.xz)` and `-sunRay.y` directly.
local SUN_RAY = { -0.4507, -0.7724, -0.4507 }

-- The surface art, if the player has one. Same contract as the overworld's:
-- drop a PNG at assets/water/water.png and the water wears it; delete it and
-- the water is its own colour again. Looked up once and remembered, false
-- included, so a missing file is not re-resolved every frame.
local artImage = nil
local function waterArt()
  if artImage ~= nil then return artImage or nil end
  local ok, img = pcall(function()
    local Assets = require("src.render.Assets")
    local path = V.path .. "/" .. WorldMap3D.ASSET_DIR .. WorldMap3D.ASSET_FILE
    if not Assets.exists(path) then return nil end

    -- MIPMAPS, which is why this builds its own image instead of taking the
    -- cached one. The sheet repeats every 64 world pixels and this camera
    -- looks along the sea rather than down at it, so out toward the horizon
    -- one screen pixel covers many repeats of it. Without a mipmap chain
    -- that samples as long diagonal smears across the water -- visible, and
    -- exactly the kind of artefact that reads as a broken texture rather
    -- than as distance.
    local i
    local okD, data = pcall(Assets.imageData, path)
    if okD and data then
      local okM, made = pcall(love.graphics.newImage, data, { mipmaps = true })
      if okM and made then
        i = made
        pcall(i.setMipmapFilter, i, "linear")
      end
    end
    -- a driver that will not build the chain still gets the sheet
    if not i then i = Assets.image(path) end
    if i then
      -- world XZ tiles across it, so it has to repeat rather than clamp
      pcall(i.setWrap, i, "repeat", "repeat")
      pcall(i.setFilter, i, "linear", "linear")
    end
    return i
  end)
  artImage = (ok and img) or false
  return artImage or nil
end

-- 0..1, like every other colour in LOVE 11: written as bytes this painted a
-- white sky, which is how the vertex-colour range was caught in the first
-- place (see FORMAT).
local function drawSky(w, h)
  local ok, mesh = pcall(love.graphics.newMesh, {
    { 0, 0, 0, 0, SKY_TOP[1], SKY_TOP[2], SKY_TOP[3], 1 },
    { w, 0, 1, 0, SKY_TOP[1], SKY_TOP[2], SKY_TOP[3], 1 },
    { w, h, 1, 1, SKY_LOW[1], SKY_LOW[2], SKY_LOW[3], 1 },
    { 0, h, 0, 1, SKY_LOW[1], SKY_LOW[2], SKY_LOW[3], 1 },
  }, "fan", "stream")
  if ok and mesh then love.graphics.draw(mesh) end
end

local clock = 0

local function drawRegion(w, h)
  if not ensureCanvases(w, h) then return false end
  local g = love.graphics

  g.push("all")
  g.setCanvas({ canvases.color, depthstencil = canvases.depth })
  g.clear(0, 0, 0, 1, true, true)
  g.setBlendMode("alpha")

  -- sky first, with depth off, so it is the backdrop and never occludes
  g.setDepthMode("always", false)
  g.setColor(1, 1, 1, 1)
  drawSky(w, h)

  g.setDepthMode("lequal", true)
  g.setMeshCullMode("none")

  local fogNear, fogFar = cam.near, cam.far
  if R.landMesh and shaders.land then
    g.setShader(shaders.land)
    pcall(shaders.land.send, shaders.land, "mvp", "row", cam.mvp)
    pcall(shaders.land.send, shaders.land, "camPos", cam.eye)
    pcall(shaders.land.send, shaders.land, "fogRange", { fogNear, fogFar })
    pcall(shaders.land.send, shaders.land, "fogColor", FOG)
    pcall(shaders.land.send, shaders.land, "sunTint", SUN)
    g.draw(R.landMesh)
  end
  if R.waterMesh and shaders.water then
    g.setShader(shaders.water)
    local s = shaders.water
    pcall(s.send, s, "mvp", "row", cam.mvp)
    pcall(s.send, s, "camPos", cam.eye)
    pcall(s.send, s, "fogRange", { fogNear, fogFar })
    pcall(s.send, s, "fogColor", FOG)
    pcall(s.send, s, "sunTint", SUN)
    pcall(s.send, s, "skyColor", SKY_LOW)
    pcall(s.send, s, "sunRay", SUN_RAY)
    pcall(s.send, s, "time", clock)
    pcall(s.send, s, "swellAmp", WorldMap3D.SWELL)
    pcall(s.send, s, "shoreSpan", WorldMap3D.SHORE_SPAN)
    local art = waterArt()
    pcall(s.send, s, "artOn", art and 1 or 0)
    pcall(s.send, s, "artMix", WorldMap3D.ART_MIX)
    pcall(s.send, s, "artScale", WorldMap3D.ART_SCALE)
    if art then pcall(R.waterMesh.setTexture, R.waterMesh, art) end
    -- The fine detail -- the value bands, the glint rings, the crest of the
    -- swell -- is a few world pixels across. It is worth drawing when the
    -- camera is over a harbour and worth nothing at all when the whole
    -- region is on screen, where it can only alias into stripes across the
    -- sea. Which it did, until this faded it out.
    pcall(s.send, s, "near",
          math.max(0, math.min(1, (320 - cam.dist) / 200)))
    g.draw(R.waterMesh)
  end

  g.setShader()
  g.setDepthMode()
  g.setCanvas()
  g.pop()

  g.push("all")
  g.setColor(1, 1, 1, 1)
  g.setBlendMode("alpha", "premultiplied")
  g.draw(canvases.color, 0, 0)
  g.pop()
  return true
end

-- ---------------------------------------------------------------- the plates
local function text(s, x, y, size, r, g, b, a)
  if BattleHudXY.available() then
    local ok = pcall(BattleHudXY.text, s, x, y, size, { r, g, b, a })
    if ok then return end
  end
  love.graphics.setColor(r, g, b, a)
  love.graphics.print(s, x, y)
end

-- How wide `s` will be at cell height `size`.
--
-- BattleHudXY.text scales by `h / fontHeight` and fontHeight is private to
-- it, so the ratio is measured once instead of assumed: draw one glyph
-- off-screen at a known height and compare what came back with what
-- textWidth said. Assuming 16 made every name plate on the map about twice
-- the width of the name inside it.
local fontRatio = nil
local function textW(s, size)
  if BattleHudXY.available() then
    if not fontRatio then
      local okA, drawn = pcall(BattleHudXY.text, "A", -9000, -9000, 64,
                               { 0, 0, 0, 0 })
      local okB, raw = pcall(BattleHudXY.textWidth, "A")
      if okA and okB and drawn and raw and raw > 0 and drawn > 0 then
        fontRatio = (drawn / raw) / 64
      else
        fontRatio = false
      end
    end
    if fontRatio then
      local ok, w = pcall(BattleHudXY.textWidth, s)
      if ok and w then return w * fontRatio * size end
    end
  end
  return #s * size * 0.5
end

local function drawPins(screen, w, h)
  local g = love.graphics
  local selName = nil
  if screen.locs and screen.sel and screen.locs[screen.sel] then
    selName = screen.locs[screen.sel].name
  end
  local hereName = screen.playerLoc and screen.playerLoc.name

  for _, p in ipairs(R.places) do
    local loc = screen.byMap and screen.byMap[p.id]
    local name = loc and loc.name or p.label
    local isSel = selName and name == selName
    local isHere = hereName and name == hereName
    local town = p.id:find("CITY") or p.id:find("TOWN") or p.id:find("ISLAND")
                 or p.id:find("PLATEAU")
    local isGoalPlace = questTargetPlace and questTargetPlace.id == p.id
    if isSel or isHere or town or isGoalPlace then
      local wx = p.cx - R.gw * 0.5
      local wz = p.cy - R.gh * 0.5
      local sx, sy = project(wx, 3.2, wz)
      -- BANNER_H is not decoration: a plate half under the banner is a name
      -- you cannot read, and one off the side of the frame is a plate
      -- pointing at nothing. Both were in the first frames this drew.
      local BANNER_H = 96
      if sx and sx > 90 and sx < w - 90
         and sy > 46 and sy < h - BANNER_H then
        local size = isSel and 26 or 19
        local label = name or p.label
        local tw = textW(label, size)
        local px, py = math.floor(sx - tw * 0.5), math.floor(sy - size - 14)

        -- the stem, so the plate is attached to a place rather than floating
        g.setColor(0, 0, 0, isSel and 0.55 or 0.32)
        g.setLineWidth(2)
        g.line(sx, sy, sx, py + size + 6)
        g.setColor(isSel and 1 or 0.9, isSel and 0.86 or 0.9, isSel and 0.35 or 0.9,
                   isSel and 1 or 0.8)
        g.circle("fill", sx, sy, isSel and 5 or 3)

        local isGoal = questTargetPlace and questTargetPlace.id == p.id
        g.setColor(isGoal and 0.16 or 0.05, isGoal and 0.12 or 0.07,
                   isGoal and 0.02 or 0.10, (isSel or isGoal) and 0.88 or 0.62)
        g.rectangle("fill", px - 8, py - 4, tw + 16, size + 10, 5, 5)
        if isSel or isGoal then
          g.setColor(1, 0.86, 0.35, 0.95)
          g.setLineWidth(2)
          g.rectangle("line", px - 8, py - 4, tw + 16, size + 10, 5, 5)
        end
        if isSel then
          text(label, px, py, size, 1, 0.93, 0.6, 1)
        elseif isHere then
          text(label, px, py, size, 0.6, 0.95, 1, 1)
        else
          text(label, px, py, size, 0.92, 0.94, 0.98, 0.92)
        end
      end
    end
  end

  -- the banner: what the cursor is on, bottom left, always legible
  if selName then
    g.setColor(0.04, 0.06, 0.09, 0.78)
    g.rectangle("fill", 0, h - 84, w, 84)
    g.setColor(1, 0.86, 0.35, 0.9)
    g.rectangle("fill", 0, h - 84, w, 2)
    text(selName, 34, h - 66, 34, 1, 0.95, 0.72, 1)
    local hint = "CIMA/BAIXO  LOCAL     ESQ/DIR  GIRAR     A  ZOOM     B  SAIR"
    text(hint, 34, h - 26, 15, 0.72, 0.78, 0.86, 0.9)
  end
end

-- ============================================================================
-- 5b. THE OBJECTIVE
-- ============================================================================
--
-- What lib/WorldMapQuest.lua worked out, drawn onto the region: a beacon
-- standing on the town it names, a dashed route from where the player
-- actually is to that town, and a panel saying it in words.
--
-- The route is the part worth having. A marker tells you WHERE; a line
-- through the maps you would actually walk tells you HOW, and that line is
-- not decoration -- it is a breadth-first search over which placed maps
-- touch, so it goes the way the routes go and around the sea rather than
-- across it.

local function placeIndex(mapId)
  if not (R and mapId) then return nil end
  for i, p in ipairs(R.places) do
    if p.id == mapId then return i, p end
  end
  return nil
end

-- Shortest chain of placed maps from one to the other, as a list of places.
-- Nil when either end is not on the map (an indoor id, or Route 23, which
-- the outdoor walk never reaches because its way in is a gate).
local function routeBetween(fromId, toId)
  local si = placeIndex(fromId)
  local ti = placeIndex(toId)
  if not (si and ti) then return nil end
  if si == ti then return { R.places[si] } end
  local prev, seen = {}, { [si] = true }
  local q, head = { si }, 1
  while head <= #q do
    local i = q[head]; head = head + 1
    for _, j in ipairs(R.adj[i] or {}) do
      if not seen[j] then
        seen[j] = true; prev[j] = i
        if j == ti then
          local chain, at = {}, j
          while at do table.insert(chain, 1, R.places[at]); at = prev[at] end
          return chain
        end
        q[#q + 1] = j
      end
    end
  end
  return nil
end

-- Word wrap against the real drawn width, because the alphabet is
-- proportional and a character count wraps the wrong word every time.
local function wrap(text, size, maxW)
  local lines, line = {}, nil
  for word in tostring(text):gmatch("%S+") do
    local try = line and (line .. " " .. word) or word
    if line and textW(try, size) > maxW then
      lines[#lines + 1] = line
      line = word
    else
      line = try
    end
  end
  if line then lines[#lines + 1] = line end
  return lines
end

local function drawBeacon(sx, sy, t, r, g2, b2)
  local g = love.graphics
  g.push("all")
  g.setBlendMode("add")
  -- Tall and bright enough to be seen over a lit map. The first cut was a
  -- 132px beam at alpha 0.15 and it vanished completely at the zoom that
  -- fits the region -- a marker nobody can find is the one thing a marker
  -- must not be. It also breathes, because a static glow reads as part of
  -- the terrain.
  local H = 190
  local pulse = 0.80 + 0.20 * math.sin(t * 2.6)
  for i = 0, 17 do
    local f0, f1 = i / 18, (i + 1) / 18
    local a = (1 - (f0 + f1) * 0.5) * 0.34 * pulse
    local w0 = 13 * (1 - f0 * 0.6)
    local w1 = 13 * (1 - f1 * 0.6)
    g.setColor(r, g2, b2, a)
    g.polygon("fill", sx - w0, sy - f0 * H, sx + w0, sy - f0 * H,
                      sx + w1, sy - f1 * H, sx - w1, sy - f1 * H)
  end
  -- a hard core down the middle, which is what survives being seen small
  g.setColor(1, 0.97, 0.85, 0.55 * pulse)
  g.setLineWidth(2)
  g.line(sx, sy, sx, sy - H * 0.72)
  g.pop()
  -- the ring, which is what makes it read as standing ON something
  for k = 0, 1 do
    local p = ((t * 0.75) + k * 0.5) % 1
    g.setColor(r, g2, b2, (1 - p) * 0.75)
    g.setLineWidth(3)
    g.ellipse("line", sx, sy, 9 + p * 32, (9 + p * 32) * 0.40)
  end
  g.setColor(r, g2, b2, 1)
  g.circle("fill", sx, sy, 4)
end

local function drawTrail(pts, t)
  local g = love.graphics
  local DASH, GAP = 12, 10
  local phase = (t * 30) % (DASH + GAP)
  -- the caller owns the width: this is drawn twice, wide then narrow
  for i = 1, #pts - 1 do
    local ax, ay = pts[i][1], pts[i][2]
    local bx, by = pts[i + 1][1], pts[i + 1][2]
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 1 then
      local ux, uy = dx / len, dy / len
      local s = -phase
      while s < len do
        local a = math.max(0, s)
        local b = math.min(len, s + DASH)
        if b > a then
          g.line(ax + ux * a, ay + uy * a, ax + ux * b, ay + uy * b)
        end
        s = s + DASH + GAP
      end
    end
  end
end

local function drawQuest(screen, w, h)
  if not (quest and quest.step) then return end
  local g = love.graphics
  local tp = questTargetPlace
  local t = clock

  ------------------------------------------------------------------ the route
  local save = activeGame and activeGame.save
  local fromId = WorldMapQuest.playerMap(save)
  local chain = tp and routeBetween(fromId, tp.id) or nil
  local pts = {}
  if chain and #chain > 1 then
    for _, p in ipairs(chain) do
      local sx, sy = project(p.cx - R.gw * 0.5, 1.6, p.cy - R.gh * 0.5)
      if sx then pts[#pts + 1] = { sx, sy } end
    end
    if #pts > 1 then
      -- twice: a wide soft pass under a narrow bright one, so the line reads
      -- over grass, over sand and over the sea without picking a colour that
      -- only works on one of them
      g.setColor(0.20, 0.14, 0.02, 0.45)
      g.setLineWidth(9)
      drawTrail(pts, t)
      g.setColor(1, 0.90, 0.42, 0.95)
      g.setLineWidth(4)
      drawTrail(pts, t)
    end
  end

  ----------------------------------------------------------------- the player
  local fi, fp = placeIndex(fromId)
  if fp then
    local sx, sy = project(fp.cx - R.gw * 0.5, 1.2, fp.cy - R.gh * 0.5)
    if sx then
      g.setColor(0.35, 0.78, 1, 0.85)
      g.setLineWidth(3)
      g.ellipse("line", sx, sy, 13, 6)
      g.circle("fill", sx, sy, 4)
      text("VOCÊ", sx - textW("VOCÊ", 15) * 0.5, sy + 8, 15, 0.6, 0.9, 1, 0.95)
    end
  end

  ----------------------------------------------------------------- the beacon
  if tp then
    local sx, sy = project(tp.cx - R.gw * 0.5, 0.6, tp.cy - R.gh * 0.5)
    if sx then drawBeacon(sx, sy, t, 1, 0.84, 0.32) end
  end

  ------------------------------------------------------------------ the panel
  local PW = math.min(560, math.max(360, w * 0.30))
  local x, y = 28, 26
  local pad = 16
  local titleLines = wrap(quest.step.title, 25, PW - pad * 2)
  local detailLines = wrap(quest.step.detail or "", 16, PW - pad * 2)
  local PH = pad * 2 + 22 + #titleLines * 30 + #detailLines * 21 + 26
             + (#quest.upcoming > 0 and (14 + #quest.upcoming * 19) or 0)

  g.setColor(0.04, 0.06, 0.10, 0.82)
  g.rectangle("fill", x, y, PW, PH, 8, 8)
  g.setColor(1, 0.86, 0.35, 0.75)
  g.setLineWidth(2)
  g.rectangle("line", x, y, PW, PH, 8, 8)
  -- the gold spine down the left edge, so the panel reads as a quest and not
  -- as another name plate
  g.setColor(1, 0.86, 0.35, 0.95)
  g.rectangle("fill", x, y + 8, 4, PH - 16, 2, 2)

  local ty = y + pad
  text("OBJETIVO", x + pad, ty, 15, 1, 0.86, 0.35, 1)
  local prog = quest.badges .. "/" .. quest.badgeTotal .. " INSÍGNIAS"
  text(prog, x + PW - pad - textW(prog, 15), ty, 15, 0.65, 0.72, 0.82, 1)
  ty = ty + 22

  for _, ln in ipairs(titleLines) do
    text(ln, x + pad, ty, 25, 1, 1, 1, 1)
    ty = ty + 30
  end
  for _, ln in ipairs(detailLines) do
    text(ln, x + pad, ty, 16, 0.72, 0.78, 0.88, 1)
    ty = ty + 21
  end

  ty = ty + 6
  if tp then
    local locName = (screen.byMap and screen.byMap[tp.id]
                     and screen.byMap[tp.id].name) or tp.label
    -- plain ASCII: BattleHudXY SKIPS a glyph its alphabet does not carry
    -- rather than substituting one, so a decorative arrow is a silent gap
    text("> " .. tostring(locName), x + pad, ty, 19, 1, 0.86, 0.35, 1)
  end
  ty = ty + 24

  if #quest.upcoming > 0 then
    ty = ty + 8
    text("A SEGUIR", x + pad, ty, 13, 0.55, 0.62, 0.74, 1)
    ty = ty + 16
    for _, s in ipairs(quest.upcoming) do
      local one = wrap(s.title, 15, PW - pad * 2 - 14)[1] or s.title
      text("- " .. one, x + pad, ty, 15, 0.60, 0.66, 0.76, 1)
      ty = ty + 19
    end
  end
end

local function drawProgress(w, h)
  local g = love.graphics
  g.push("all")
  g.setColor(0.05, 0.09, 0.14, 1)
  g.rectangle("fill", 0, 0, w, h)
  local phase = build and build.phase or "?"
  local frac = 0
  if build and build.total and build.total > 0 then
    frac = (build.done or 0) / build.total
  end
  if phase ~= "reading" then frac = math.max(frac, 0.9) end
  local bw = w * 0.42
  local bx, by = (w - bw) * 0.5, h * 0.5
  g.setColor(1, 1, 1, 0.14)
  g.rectangle("fill", bx, by, bw, 6, 3, 3)
  g.setColor(0.55, 0.82, 1, 0.95)
  g.rectangle("fill", bx, by, bw * math.min(1, frac), 6, 3, 3)
  text("KANTO", bx, by - 54, 40, 0.95, 0.97, 1, 1)
  text(phase, bx, by + 18, 16, 0.6, 0.7, 0.85, 0.9)
  g.pop()
end

-- ============================================================================
-- 6. THE SCREEN
-- ============================================================================

local townMapClass = nil
local function isTownMap(scr)
  if not scr then return false end
  if not townMapClass then
    local ok, T = pcall(require, "src.ui.TownMap")
    townMapClass = (ok and T) or false
  end
  if not townMapClass then return false end
  return getmetatable(scr) == townMapClass
end

local lastSel, lastTime = nil, nil

-- Which of our places a location name belongs to. The town map's `byMap` is
-- map id -> location, so the way back is over our own placed maps: the first
-- one whose location is the one the cursor is on. Routes made of several
-- maps therefore fly to the first segment, which is the one the name is on.
local function placeForName(screen, name)
  if not name then return nil end
  for _, p in ipairs(R.places) do
    local loc = screen.byMap and screen.byMap[p.id]
    if loc and loc.name == name then return p end
  end
  return nil
end

local heldA, heldSel = false, false
local grace = 0

local function pollInput(game, dt)
  local input = game and game.input
  if not (input and input.isDown) then return end
  -- A GRACE PERIOD, because the button that opened this screen is A: the
  -- player presses A on the MAP row, the map opens on the next frame with A
  -- still held, and a zoom toggle fires that nobody asked for. Half a second
  -- of not listening costs nothing and is the difference between a camera
  -- that obeys and one that jumps on the way in.
  if grace > 0 then
    grace = grace - dt
    heldA = true
    return
  end
  local function down(b)
    local ok, yes = pcall(input.isDown, input, b)
    return ok and yes
  end
  -- left/right orbit. Measured to be free on this screen: the engine's own
  -- update moves the cursor on up/down and ignores these (probe 4).
  if down("left") then cam.tyaw = cam.tyaw + dt * 1.6 end
  if down("right") then cam.tyaw = cam.tyaw - dt * 1.6 end

  local a = down("a")
  if a and not heldA then WorldMap3D.toggleZoom() end
  heldA = a

  local s = down("select")
  if s and not heldSel then WorldMap3D.toggleTopDown() end
  heldSel = s
end

-- The two camera actions, as functions rather than as bodies inside the
-- input poll, because a probe cannot press a key: the pressQueue a driver
-- writes into is a press EVENT, and `input:isDown` reads the physical key,
-- which nothing in a headless run is holding. A test that cannot reach the
-- zoom is a test that never checks it.
function WorldMap3D.toggleZoom()
  if not R then return end
  if cam.wide then
    local p = R.lastPlace
    if p then frameOn(p.cx, p.cy) else frameWholeRegion() end
  else
    frameWholeRegion()
  end
end

function WorldMap3D.toggleTopDown()
  if not R then return end
  cam.tpitch = (cam.tpitch > 1.3) and (cam.wide and 0.86 or 0.70) or 1.50
end

function WorldMap3D.available()
  if not WorldMap3D.ENABLED then return false end
  if failed then return false end
  return (love.graphics and love.graphics.newCanvas ~= nil) and true or false
end

-- Called once per rendered frame, from Renderer.endFrame, with the window
-- bound. Does nothing at all unless the town map is the screen on top.
function WorldMap3D.frame()
  if not WorldMap3D.available() then return end
  local game = activeGame
  local stack = game and game.stack
  local top = stack and stack.top and stack:top()
  if not isTownMap(top) then
    lastTime = nil
    return
  end

  local now = love.timer and love.timer.getTime and love.timer.getTime() or 0
  local firstFrame = (lastTime == nil)
  local dt = lastTime and math.min(0.1, now - lastTime) or 0.016
  lastTime = now
  clock = clock + dt
  if firstFrame then
    grace = 0.45
    heldA, heldSel = true, true
    lastSel = nil
    -- the objective is read once per opening. The map is modal, so nothing
    -- can change the save while it is up, and re-reading it every frame
    -- would walk the whole chain sixty times a second for an answer that
    -- cannot have moved.
    quest, questTargetPlace = nil, nil
    if R then
      -- a reopened map opens on the region again, facing north, wherever the
      -- camera was left the last time
      cam.yaw, cam.tyaw = 0, 0
      cam.dist = fitDistance(R.gw, R.gh, 0.86) * 1.35
      frameWholeRegion()
    end
  end

  local w, h = love.graphics.getDimensions()

  ------------------------------------------------------------------- building
  if not R then
    if not build then
      build = { phase = "starting", done = 0, total = 1 }
      build.co = buildCoroutine()
    end
    local ok, err = coroutine.resume(build.co)
    if not ok then
      failed = true
      log("build failed: " .. tostring(err))
      build = nil
      return
    end
    if R then
      -- the region is read; the meshes are one more slice
      local okM, errM = pcall(buildMeshes)
      if not okM then
        failed = true; log("mesh failed: " .. tostring(errM)); R = nil; build = nil
        return
      end
      ensureShaders()
      log(("region built: %d places, %d land verts, %d water verts, "
           .. "%d seam fixes, %d blobs (%d buildings), %.0f ms")
          :format(#R.places, R.landVerts or 0, R.waterVerts or 0,
                  R.seamFixes, R.blobs, R.buildings, R.ms))
      build = nil
      -- open high and settle, so the region arrives rather than appears
      cam.fx, cam.fz = 0, 0
      cam.yaw, cam.tyaw = 0, 0
      cam.pitch = 1.20
      cam.dist = fitDistance(R.gw, R.gh, 0.86) * 1.55
      frameWholeRegion()
      grace, heldA, heldSel = 0.45, true, true
      lastSel = nil
    else
      drawProgress(w, h)
      return
    end
  end

  ---------------------------------------------------------------- the cursor
  local sel = top.sel
  if sel ~= lastSel then
    lastSel = sel
    local loc = top.locs and top.locs[sel]
    local p = loc and placeForName(top, loc.name)
    if p then
      R.lastPlace = p
      if not cam.wide then frameOn(p.cx, p.cy)
      else
        -- in the wide view the camera does not chase, it leans: the whole
        -- region stays framed and the selection drifts toward the middle
        cam.tfx = (p.cx - R.gw * 0.5) * 0.28
        cam.tfz = (p.cy - R.gh * 0.5) * 0.28
      end
    end
  end

  -- the objective, once the region exists to point at
  if quest == nil then
    quest = WorldMapQuest.current(game.save) or false
    if quest then
      local _, p = placeIndex(quest.step.target)
      if not p and quest.step.fallback then
        _, p = placeIndex(quest.step.fallback)
      end
      questTargetPlace = p
      -- open looking at the objective rather than at the middle of the sea:
      -- the whole region still frames, it just leans toward the marker the
      -- same way the cursor makes it lean
      if p then
        cam.tfx = (p.cx - R.gw * 0.5) * 0.28
        cam.tfz = (p.cy - R.gh * 0.5) * 0.28
      end
    end
  end

  pollInput(game, dt)
  updateCamera(dt)

  if drawRegion(w, h) then
    drawQuest(top, w, h)
    drawPins(top, w, h)
  end
end

-- For probes: every placed map, where it sits in the grid, how much of it
-- actually carries land, and where its pin lands on screen. A pin drawn over
-- open sea is either a map that never got read or a pin projected with a
-- different origin than the mesh, and these two numbers side by side say
-- which.
function WorldMap3D.debugPlaces()
  local out = {}
  if not R then return out end
  for _, p in ipairs(R.places) do
    local solid, sea = 0, 0
    for cy = 0, p.h - 1 do
      for cx = 0, p.w - 1 do
        local gx, gy = p.x + cx, p.y + cy
        if gx >= 0 and gx < R.gw and gy >= 0 and gy < R.gh then
          local c = R.cls[gy * R.gw + gx + 1]
          if c == OCEAN or c == WATER then sea = sea + 1 else solid = solid + 1 end
        end
      end
    end
    local sx, sy = project(p.cx - R.gw * 0.5, 3.2, p.cy - R.gh * 0.5)
    out[#out + 1] = {
      id = p.id, gx = p.x, gy = p.y, w = p.w, h = p.h,
      solid = solid, sea = sea,
      sx = sx and math.floor(sx) or -9999,
      sy = sy and math.floor(sy) or -9999,
    }
  end
  return out
end

function WorldMap3D.debugFocus(mapId)
  if not R then return false end
  for _, p in ipairs(R.places) do
    if p.id == mapId then
      R.lastPlace = p
      frameOn(p.cx, p.cy)
      return true
    end
  end
  return false
end

-- For probes: what the objective reader decided, and whether the map could
-- put it anywhere. A step with no target place is the failure worth catching
-- -- the panel would still read correctly while the beacon stood nowhere.
function WorldMap3D.questReport()
  local save = activeGame and activeGame.save
  local q = quest or nil
  return {
    has = (q and q.step) and true or false,
    id = q and q.step and q.step.id or "-",
    title = q and q.step and q.step.title or "-",
    target = q and q.step and q.step.target or "-",
    placed = questTargetPlace and questTargetPlace.id or "NONE",
    doneCount = q and q.doneCount or -1,
    total = q and q.total or -1,
    badges = q and q.badges or -1,
    playerMap = save and WorldMapQuest.playerMap(save) or "-",
    routeHops = (function()
      if not (R and questTargetPlace and save) then return -1 end
      local c = routeBetween(WorldMapQuest.playerMap(save), questTargetPlace.id)
      return c and #c or -1
    end)(),
  }
end

function WorldMap3D.report()
  return {
    enabled = WorldMap3D.ENABLED,
    built = R ~= nil,
    failed = failed,
    places = R and #R.places or 0,
    gw = R and R.gw or 0, gh = R and R.gh or 0,
    landVerts = R and R.landVerts or 0,
    waterVerts = R and R.waterVerts or 0,
    seamFixes = R and R.seamFixes or 0,
    inland = R and R.inland or 0,
    buildings = R and R.buildings or 0,
    ms = R and R.ms or 0,
    rampLo = R and R.rampLo or 0,
    rampHi = R and R.rampHi or 0,
    wide = cam.wide,
    dist = math.floor(cam.dist),
    pitch = math.floor(cam.pitch * 100) / 100,
  }
end

-- Drop the built region. A save that changes which maps exist (a Gen 2
-- cartridge swap) has a different Kanto, and the mesh in hand is the old
-- one's.
function WorldMap3D.invalidate()
  if R then
    if R.landMesh and R.landMesh.release then pcall(R.landMesh.release, R.landMesh) end
    if R.waterMesh and R.waterMesh.release then pcall(R.waterMesh.release, R.waterMesh) end
  end
  R, build, failed = nil, nil, false
  lastSel = nil
end

-- The install, in two wraps, and both halves are needed or the frame carries
-- two maps.
--
--   TownMap.new     captures the game and silences the engine's own draw on
--                   the INSTANCE. Silenced by ASKING each frame rather than
--                   by blanking once: if this renderer ever gives up
--                   mid-session (a shader that will not compile on some
--                   driver, a build that threw), the Game Boy map comes back
--                   on the next frame instead of leaving an empty screen.
--                   Same shape as lib/StartMenuXY.lua's install, for the
--                   same reason.
--   Renderer.endFrame  paints. It is the only hook that runs at all while an
--                   opaque screen is up -- measured, see the header.
--
-- Guarded against a double install because a hot reload would otherwise nest
-- the wrappers and paint the region twice.
local installed = false
function WorldMap3D.install()
  if installed then return true end

  local okT, TownMap = pcall(require, "src.ui.TownMap")
  if not (okT and TownMap and TownMap.new) then
    log("no src.ui.TownMap -- world map stays flat")
    return false
  end
  local okR, Renderer = pcall(require, "src.render.Renderer")
  if not (okR and Renderer and Renderer.endFrame) then
    log("no Renderer.endFrame -- world map stays flat")
    return false
  end

  local newInner = TownMap.new
  TownMap.new = function(game, ...)
    local screen = newInner(game, ...)
    if type(screen) == "table" then
      activeGame = game
      local engineDraw = screen.draw
      screen.draw = function(self, ...)
        -- asked per frame, not per screen: `failed` can flip under it
        if WorldMap3D.available() then return end
        if engineDraw then return engineDraw(self, ...) end
        local mt = getmetatable(self)
        local classDraw = mt and (mt.draw or (mt.__index and mt.__index.draw))
        if classDraw then return classDraw(self, ...) end
      end
    end
    return screen
  end

  local origEnd = Renderer.endFrame
  Renderer.endFrame = function(...)
    local a, b, c = origEnd(...)
    local okF, err = pcall(WorldMap3D.frame)
    if not okF then
      failed = true
      log("frame failed, falling back to the engine's map: " .. tostring(err))
    end
    return a, b, c
  end

  installed = true
  return true
end

return WorldMap3D
