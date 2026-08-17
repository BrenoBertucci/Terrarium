-- The interior CEILING and RISERS: the room's missing upper storey.
-- payload-version: 23
--
-- v1/v2 proved the concept: a flat lid at wall height (16) closed the
-- room in first person.  v3 is the liveable version:
--
--   HEADROOM   the ceiling rides at 32 by default (AIRY; MID 24 and SNUG
--              16 are options), so the eye at 13 stands in a room rather
--              than a crawlspace.
--
--   RISERS     walls rise to meet it.  Every wall-height cell grows side
--              faces from its own top up to the ceiling, textured with
--              the cell's OWN tile art repeated per 16px course -- so a
--              cave's risers are rock, a Mart's are Mart wall, a house's
--              are wallpaper, with nobody authoring anything: the map's
--              art answers for its own materials.
--
--   MATERIALS  the ceiling itself is textured with the room's dominant
--              wall tile, darkened -- rock overhead in caves, plaster in
--              houses -- with a subtle checker in the shade so the
--              surface reads as a surface.
--
--   CUTAWAY    in the DIORAMA rungs (third person), a Sims-style cut:
--              walls whose south side faces open floor -- the ones
--              between the camera and the room -- keep their low 16px
--              stubs, walls behind the room rise, and the ceiling opens
--              in a wide hole that follows the player.  The shipped
--              open-dollhouse look is one options toggle away.
--
-- Geometry is textured straight from the map's terrain atlas (the same
-- palette-baked image the mesher draws with), handed in by the scene as
-- `atlasFor`; without it (an old splice, a headless run) everything falls
-- back to shaded white and still stands.
--
-- Configuration comes from the companion mod (ds_fp_ceiling) through its
-- exports when it is installed, and from this module's own ModSettings
-- when it is not.  Purely presentational throughout: no collision, no
-- movement, no scripts.

local V = ...

local Voxel3D = V.require("Voxel3D")
local TileShape = V.require("TileShape")
-- The first-person rig, if this build has one.  absol89's battle-art fork
-- is based on Dramatic Shape 1.3.0, which predates the rig entirely --
-- and an unguarded require there would fail at load and take this whole
-- module with it.  Without a rig the blend reads as zero, which means the
-- diorama's cutaway view: exactly right for a build that has no first
-- person to be inside of.
local okFP, FirstPerson = pcall(V.require, "FirstPerson")
if not (okFP and type(FirstPerson) == "table") then
  FirstPerson = { yaw = 0, blendEased = function() return 0 end }
end
local ModSetting = V.require("ModSetting")
-- Dramatic Shape's own answer for maps under leaves rather than a roof
local okDN, DayNight = pcall(V.require, "DayNight")

-- telemetry for the companion's on-screen panel; absence of the global
-- means this module never loaded this session
local function status(s) _G.__ds_ceiling_status = s end

local Ceiling = {}

-- fallback rows, governing only when the companion mod is absent
Ceiling.setting = ModSetting.new("fpceiling", "FP CEILING",
                                 { true, false }, { "ON", "OFF" })
Ceiling.headroom = ModSetting.new("fpheadroom", "HEADROOM",
                                  { 32, 24, 16 }, { "AIRY", "MID", "SNUG" })
Ceiling.cutaway = ModSetting.new("fpcutaway", "CUTAWAY",
                                 { true, false }, { "ON", "OFF" })

local WALL_H = 16          -- "wall is 16px for every interior in the game"
local HOLE_RADIUS = 4      -- cutaway ceiling hole, in cells around the player
local BLEND_GATE = 0.5

-- shade language: lit vs shaded riser flanks (matching the mesher's south/
-- east-lit sun), and the ceiling's checker pair
local RISER_SHADE = { pz = 0.85, nz = 0.62, px = 0.80, nx = 0.66 }
local CEIL_SHADE = { 0.42, 0.48 }

local cache = nil  -- { map, key, mesh, note }

status("loaded (v3); awaiting the first frame indoors")

-- ------- configuration: the companion's exports first, own rows second
local function config()
  -- The companion mod (ds_fp_ceiling) publishes a config reader on the
  -- shared Lua state.  Dramatic Shape's namespace has no mod-lookup of
  -- its own, and _G is demonstrably shared -- the debug HUD reads this
  -- module's status the same way -- so this is the channel that works.
  local pub = rawget(_G, "__ds_ceiling_config")
  if type(pub) == "function" then
    local okP, cfg = pcall(pub)
    if okP and type(cfg) == "table" then return cfg end
  end
  return {
    ceiling = Ceiling.setting:get() == true,
    headroom = Ceiling.headroom:get() or 32,
    cutaway = Ceiling.cutaway:get() == true,
  }
end

-- ------- indoors, by the engine's own answer where it has one
-- Open-air tilesets: warp-only maps that are nonetheless SKY.  Viridian
-- Forest, the Safari Zone areas, Route gatehouse yards and the Plateau
-- grounds all have no connections, so "warp-only" alone would roof them.
-- A ceiling over the forest is the one thing worse than no ceiling at all.
local OPEN_AIR_TILESETS = {
  OVERWORLD = true, FOREST = true, PLATEAU = true, SHIP_PORT = true,
}

-- Dramatic Shape 1.5.5 added a 3RD rung: the same first-person rig with
-- the eye boomed back behind the shoulder.  The blend reads as engaged
-- there, so a sealed ceiling would slam shut in front of a camera that
-- is now OUTSIDE the room -- the lid problem, again.
--
-- We check the actual voxel level to determine if we're in 3rd person
-- mode, rather than relying on the boom extension. This ensures the
-- ceiling respects the 3RD CEILING setting even when the camera is
-- backed against a wall and the boom collapses.
local okTP, ThirdPerson = pcall(V.require, "ThirdPerson")
local okVoxel, Voxel = pcall(V.require, "VoxelState")
local function boomedOut()
  -- Check if we're actually in 3rd person mode
  if okVoxel and Voxel and Voxel.isThirdPerson then
    local ok, isTP = pcall(Voxel.isThirdPerson, Voxel.level)
    if ok and isTP then return true end
  end
  -- Fallback to the old method for compatibility
  if not (okTP and ThirdPerson and ThirdPerson.showsPlayer) then
    return false
  end
  local ok, out = pcall(ThirdPerson.showsPlayer)
  return (ok and out) and true or false
end

local function isInterior(map)
  local def = map and map.def
  if not def then return false end

  -- 1. under leaves, not under a roof: Dramatic Shape's own classification
  if okDN and DayNight and DayNight.isCanopy then
    local okC, canopy = pcall(DayNight.isCanopy, map)
    if okC and canopy then return false end
  end

  -- 2. an open-air tileset is open air whatever its connections say
  local tid = def.tileset or (map.tileset and map.tileset.id)
  if tid and OPEN_AIR_TILESETS[tid] then return false end

  -- 3. the engine's own outdoor test where it has one
  local ok, outdoor = pcall(function()
    local Map = require("src.world.Map")
    return Map.isOutdoor and Map.isOutdoor(def)
  end)
  if ok and outdoor ~= nil then return not outdoor end

  -- 4. last resort: a map with neighbours is a map with sky
  local conns = def.connections
  return not (conns and next(conns) ~= nil)
end

-- ------- per-cell facts, by the same shapes the mesher used:
--   h      extrusion height (max of the four tiles)
--   wall   true when any tile classifies as wall/cliff -- furniture at
--          16px (props, plants, cutouts) is NOT a wall and gets no riser
--   void   true when every tile is border-block filler: the black beyond
--          a room's drawn area, which is "outside" for wall purposes
local RISER_CLASSES = { wall = true, cliff = true }

local function borderTiles(map)
  local set = {}
  local def = map.def
  local block = def and def.borderBlock
  local blocks = map.tileset and map.tileset.blocks
  local row = block and blocks and blocks[block + 1]
  for _, t in ipairs(row or {}) do set[t] = true end
  return set
end

local function cellFacts(map, shapes, border, cx, cy)
  local h, wall, voidTiles = 0, false, 0
  for dy = 0, 1 do
    for dx = 0, 1 do
      local tx, ty = cx * 2 + dx, cy * 2 + dy
      local tile = map:tileAt(tx, ty)
      if tile then
        if border[tile] then voidTiles = voidTiles + 1 end
        local s = TileShape.at(map, shapes, tile, tx, ty)
        local sh = s and s.h or 0
        if sh > h then h = sh end
        if s and RISER_CLASSES[s.class] then wall = true end
      end
    end
  end
  return h, wall, voidTiles == 4
end

-- ------- PLAINNESS.
-- Repeating a wall cell's own art up a riser stacks whatever that cell
-- was carrying: in a Pokemon Centre every course grows another blue
-- cross, in a bedroom another poster.  Real walls are mostly blank with
-- occasional features, so the upper courses want the room's PLAINEST
-- wall tile, and the featured ones want sprinkling instead.
--
-- Plainness is measured, not guessed: read the atlas back once per map
-- and score each candidate 8x8 tile by how much is going on in it --
-- distinct colours, plus how often neighbouring pixels differ.  A blank
-- wall scores near zero; a cross emblem scores high.  Where the readback
-- is unavailable (some drivers, headless), frequency stands in: the
-- commonest wall tile is usually the plain one.
local function scoreTiles(map, tex, candidates)
  local data
  local ok = pcall(function()
    if tex.newImageData then data = tex:newImageData()      -- canvas
    elseif tex.getData then data = tex:getData() end        -- image
  end)
  if not (ok and data) then return nil end
  local dw, dh = data:getWidth(), data:getHeight()
  local ts = map.tileset or {}
  local perRow = ts.tilesPerRow or 16
  local scores = {}
  for _, t in ipairs(candidates) do
    local ax = (t % perRow) * 8
    local ay = math.floor(t / perRow) * 8
    if ax + 8 <= dw and ay + 8 <= dh then
      local seen, distinct, edges = {}, 0, 0
      local prevRow = {}
      for y = 0, 7 do
        local prev = nil
        for x = 0, 7 do
          local okP, r, g, b = pcall(function()
            local rr, gg, bb = data:getPixel(ax + x, ay + y)
            return rr, gg, bb
          end)
          local key = okP and
            (math.floor((r or 0) * 15) .. "," .. math.floor((g or 0) * 15)
             .. "," .. math.floor((b or 0) * 15)) or "0"
          if not seen[key] then seen[key] = true; distinct = distinct + 1 end
          if prev and prev ~= key then edges = edges + 1 end
          if prevRow[x] and prevRow[x] ~= key then edges = edges + 1 end
          prev, prevRow[x] = key, key
        end
      end
      scores[t] = distinct * 3 + edges
    end
  end
  pcall(function() data:release() end)
  return scores
end

-- ------- the atlas UV of one 8px tile (ChunkMesher's uvRect, inset half
-- a texel so the sampler never bleeds a neighbour's art)
local INSET = 0.5
-- The atlas geometry, taken the way the chunk mesher takes it: the row
-- stride is tileset.tilesPerRow, NOT imageWidth/8.  Outdoor atlases carry
-- animation frames beyond the tile grid, so the two disagree there -- and
-- when they do, every tile index lands in the wrong place and quads
-- sample wide ribbons of the whole tileset.  That was the sky-ribbon
-- glitch: the maths, not the geometry.
local function uvFor(map, tile)
  local ts = map.tileset or {}
  local perRow = ts.tilesPerRow or 16
  local aw = ts.imageWidth or (perRow * 8)
  local ah = ts.imageHeight or 48
  -- and clamp into the grid: a tile index the atlas has no room for
  -- would otherwise sample off the end of the texture, which is how a
  -- quad ends up wearing a ribbon of the whole tileset
  local rows = math.max(1, math.floor(ah / 8))
  tile = math.max(0, math.floor(tile or 0)) % (perRow * rows)
  local ax = (tile % perRow) * 8
  local ay = math.floor(tile / perRow) * 8
  return (ax + INSET) / aw, (ax + 8 - INSET) / aw,
         (ay + INSET) / ah, (ay + 8 - INSET) / ah
end

-- A position hash, well spread in every bit (the fract-of-sine mixer).
-- Used to decide which walls get a picture and which picture they get,
-- so a room hangs the same art on every visit.
local function hash01(a, b, c)
  local x = a * 127.1 + b * 311.7 + (c or 0) * 74.7
  local s = math.sin(x) * 43758.5453123
  return s - math.floor(s)
end

-- ------- THE DOOR ITSELF.
-- Using the map's own tile assumed the art under a doorway IS a door.
-- Often it is not -- it is whatever the wall happens to be -- so the
-- doorway came out looking like more wall. This draws one: a frame, two
-- panels, a step and a handle, in the four shades the game's own art
-- uses. Opaque throughout, since the renderer has no soft alpha.
local doorImg = nil
local function doorArt()
  if doorImg ~= nil then return doorImg or nil end
  local ok, img = pcall(function()
    local S = 16
    local data = love.image.newImageData(S, S)
    local DARK = { 0.16, 0.13, 0.11 }   -- the frame and the shadow lines
    local WOOD = { 0.60, 0.38, 0.20 }   -- the leaf
    local LITE = { 0.76, 0.53, 0.30 }   -- its lit edge
    local BRASS = { 0.88, 0.76, 0.32 }  -- the handle
    local function put(x, y, c)
      if x >= 0 and y >= 0 and x < S and y < S then
        data:setPixel(x, y, c[1], c[2], c[3], 1)
      end
    end
    for y = 0, S - 1 do
      for x = 0, S - 1 do put(x, y, DARK) end
    end
    -- the leaf, inset by the frame
    for y = 1, S - 2 do
      for x = 2, S - 3 do put(x, y, WOOD) end
    end
    -- lit edge down the hinge side and along the head
    for y = 1, S - 2 do put(2, y, LITE) end
    for x = 2, S - 3 do put(x, 1, LITE) end
    -- two panels, marked by their shadow lines
    for _, panel in ipairs({ { 3, 7 }, { 9, 13 } }) do
      for x = 4, S - 5 do
        put(x, panel[1], DARK)
        put(x, panel[2], DARK)
      end
      for y = panel[1], panel[2] do
        put(4, y, DARK)
        put(S - 5, y, DARK)
      end
    end
    -- the handle, and the step at the threshold
    put(S - 6, 8, BRASS)
    put(S - 6, 9, BRASS)
    for x = 1, S - 2 do put(x, S - 1, LITE) end
    local i = love.graphics.newImage(data)
    i:setFilter("nearest", "nearest")
    return i
  end)
  doorImg = (ok and img) or false
  return doorImg or nil
end

-- ------- POSTERS.
-- The old wall "accents" sprinkled the room's own featured tiles across
-- the upper courses, which produced shapeless smears -- a fragment of a
-- window or a sign, stretched somewhere it never belonged.  They are
-- gone.  In their place: real pictures, hung.
--
-- The sheet is a horizontal strip of 16x16 frames (posters.png, shipped
-- by this mod), and one is chosen per eligible wall by position hash, so
-- a room hangs the same pictures every visit.  Frames are drawn a hair
-- proud of the wall so they read as ON it rather than in it.
local POSTER_SIZE = 16
local POSTER_EVERY = 6        -- one eligible wall face in this many
local POSTER_HEIGHT = 20      -- centre height: about eye level

-- Which sheet a room hangs.  A Centre gets clinical signage, a Mart gets
-- shop signage, and everywhere else gets the general set.
local SHEET_FOR = {
  POKECENTER = "posters-pokecenter.png",
  LOBBY = "posters-pokecenter.png",
  MART = "posters-pokemart.png",
}

-- ORGANIC INTERIORS HANG NOTHING.  A cave has no walls to speak of, only
-- rock; a wood has leaves.  Nobody has been in either with a hammer, and
-- a framed picture on a cave wall is the sort of detail that makes a
-- whole scene read as a mistake.  These tilesets are skipped outright.
local NO_POSTERS = {
  CAVERN = true,       -- Mt Moon, Rock Tunnel, Seafoam, Victory Road
  FOREST = true,       -- Viridian Forest and its like
  FOREST_GATE = true,
  CEMETERY = true,     -- the Tower: bare stone, and it would be crass
  UNDERGROUND = true,  -- the route tunnels: tiled, but nobody decorates
  PLATEAU = true,
  OVERWORLD = true,
  SHIP_PORT = true,
}

-- one loaded sheet per file, so switching rooms does not reload
local posterSheets = {}

local function posters(map)
  local tid = (map and map.def and map.def.tileset)
              or (map and map.tileset and map.tileset.id)
  if tid and NO_POSTERS[tid] then return nil, 0 end
  local file = (tid and SHEET_FOR[tid]) or "posters.png"
  local cached = posterSheets[file]
  if cached ~= nil then
    if cached == false then return nil, 0 end
    return cached.img, cached.frames
  end
  local base = rawget(_G, "__ds_posters_dir")
             or ((rawget(_G, "__ds_patch_base") or "") .. "/lib/")
  local ok, img = pcall(function()
    local i = love.graphics.newImage(base .. file)
    i:setFilter("nearest", "nearest")
    return i
  end)
  if not (ok and img) then
    -- a missing set falls back to the general one rather than to nothing
    if file ~= "posters.png" then
      posterSheets[file] = false
      return posters({ def = { tileset = "HOUSE" } })
    end
    posterSheets[file] = false
    return nil, 0
  end
  local w = img.getWidth and img:getWidth() or POSTER_SIZE
  local frames = math.max(1, math.floor(w / POSTER_SIZE))
  posterSheets[file] = { img = img, frames = frames }
  return img, frames
end

-- ------- mesh assembly helpers: push one textured quad
local function pushQuad(verts, indexMap, quads, c1, c2, c3, c4, uv, shade)
  local u0, u1, v0, v1 = uv[1], uv[2], uv[3], uv[4]
  verts[#verts + 1] = { c1[1], c1[2], c1[3], u0, v0, shade }
  verts[#verts + 1] = { c2[1], c2[2], c2[3], u1, v0, shade }
  verts[#verts + 1] = { c3[1], c3[2], c3[3], u1, v1, shade }
  verts[#verts + 1] = { c4[1], c4[2], c4[3], u0, v1, shade }
  Voxel3D.pushQuad(indexMap, quads)
  return quads + 1
end

-- A riser face on one side of cell (cx, cy), from y0 up to y1, split into
-- 8px sub-quads so each carries its own tile's art.  `dir` is which
-- neighbour the face looks at: "px", "nx", "pz", "nz".
local function pushRiserFace(verts, indexMap, quads, map, cx, cy, y0, y1, dir,
                             fieldTile, accentAt)
  local shade = RISER_SHADE[dir]
  local x0, z0 = cx * 16, cy * 16
  for course = y0, y1 - 8, 8 do
    for half = 0, 1 do
      -- the cell's own art, top tile row on the upper course of each
      -- 16px band, repeated up the riser
      -- risers stand ABOVE the drawn wall, so they wear the room's plain
      -- field tile with the occasional accent -- never a repeat of
      -- whatever feature this particular cell happened to carry
      local tile = fieldTile
      if accentAt then
        tile = accentAt(cx, cy, course, half) or fieldTile
      end
      local uv = { uvFor(map, tile) }
      local yA, yB = course + 8, course
      local h0, h1 = half * 8, half * 8 + 8
      local c1, c2, c3, c4
      if dir == "pz" then
        local z = z0 + 16
        c1 = { x0 + h0, yA, z }; c2 = { x0 + h1, yA, z }
        c3 = { x0 + h1, yB, z }; c4 = { x0 + h0, yB, z }
      elseif dir == "nz" then
        c1 = { x0 + h1, yA, z0 }; c2 = { x0 + h0, yA, z0 }
        c3 = { x0 + h0, yB, z0 }; c4 = { x0 + h1, yB, z0 }
      elseif dir == "px" then
        local x = x0 + 16
        c1 = { x, yA, z0 + h1 }; c2 = { x, yA, z0 + h0 }
        c3 = { x, yB, z0 + h0 }; c4 = { x, yB, z0 + h1 }
      else -- nx
        c1 = { x0, yA, z0 + h0 }; c2 = { x0, yA, z0 + h1 }
        c3 = { x0, yB, z0 + h1 }; c4 = { x0, yB, z0 + h0 }
      end
      quads = pushQuad(verts, indexMap, quads, c1, c2, c3, c4, uv, shade)
    end
  end
  return quads
end

-- ------- the build.  `mode` is "fp" (full lid and risers) or "cutaway"
-- (Sims: south-facing walls stay stubs, the lid opens around the player).
local function build(map, H, mode, pcx, pcy, tex)
  -- the room's own settings: build() is called from the draw, but it is
  -- a module-level function and does not inherit its locals
  local cfg = config()
  -- A CAVE is not a room. Rock has no picture rail and no skirting
  -- board, and it should not have a flat plastered lid either; the same
  -- list that keeps pictures out of caves now governs both.
  local tilesetId = (map.def and map.def.tileset)
                    or (map.tileset and map.tileset.id)
  local organic = (tilesetId and NO_POSTERS[tilesetId]) and true or false
  -- Rock is for actual caves. The Tower and the route tunnels are
  -- "organic" for the purpose of keeping pictures off their walls, but
  -- nobody wants stalactites over Lavender's floorboards.
  local ROCKY = { CAVERN = true, UNDERGROUND = true }
  local rocky = (tilesetId and ROCKY[tilesetId]) and true or false
  local okShapes, shapes = pcall(TileShape.forMap, map)
  if not (okShapes and shapes) then return nil, "TileShape refused" end
  local wc, hc = map.widthCells or 0, map.heightCells or 0
  if wc == 0 or hc == 0 then return nil, "map has no cells" end

  -- one pass of facts; everything below reads these
  local border = borderTiles(map)
  local h, isWall, isVoid = {}, {}, {}
  local walls = 0
  for cy = 0, hc - 1 do
    h[cy], isWall[cy], isVoid[cy] = {}, {}, {}
    for cx = 0, wc - 1 do
      local okF, hh, w, v = pcall(cellFacts, map, shapes, border, cx, cy)
      h[cy][cx] = okF and hh or 0
      isWall[cy][cx] = okF and w or false
      isVoid[cy][cx] = okF and v or false
      if isWall[cy][cx] then walls = walls + 1 end
    end
  end
  -- outside the map body counts as void: that is where the synthesized
  -- boundary walls stand
  local function outside(cx, cy)
    if cx < 0 or cy < 0 or cx >= wc or cy >= hc then return true end
    return isVoid[cy][cx]
  end
  local function heightAt(cx, cy)
    if outside(cx, cy) then return H end
    return h[cy][cx]
  end
  local function openAt(cx, cy)
    return not outside(cx, cy) and not isWall[cy][cx]
           and h[cy][cx] < WALL_H
  end

  -- Door cells: the engine's own collision answer where it has one
  -- (Map:isDoorTileCell, the pokered IsPlayerStandingOnDoorTile test),
  -- with the map's warp list as the fallback.  Gen 1 doors are commonly
  -- TWO cells wide -- a Mart's entrance, a Centre's double doors -- so
  -- these are grouped into runs below rather than treated one at a time.
  local warpAt = {}
  for _, wpt in ipairs((map.def and map.def.warps) or {}) do
    if wpt.x and wpt.y then warpAt[wpt.y * wc + wpt.x] = true end
  end
  local function isDoor(cx, cy)
    if cx < 0 or cy < 0 or cx >= wc or cy >= hc then return false end
    local ok, d = pcall(function() return map:isDoorTileCell(cx, cy) end)
    if ok and d then return true end
    return warpAt[cy * wc + cx] == true
  end

  -- The room's dominant wall tile -- what the ceiling and the synthesized
  -- boundary walls wear.  Border filler is disenfranchised: in a Mart the
  -- most common "wall" tile is the black beyond the shelves, and a black
  -- ceiling is not a material, it is a mistake.
  local tally, commonest = {}, nil
  for cy = 0, hc - 1 do
    for cx = 0, wc - 1 do
      if isWall[cy][cx] and not isVoid[cy][cx] then
        for dy = 0, 1 do
          for dx = 0, 1 do
            local t = map:tileAt(cx * 2 + dx, cy * 2 + dy)
            if t and not border[t] then
              tally[t] = (tally[t] or 0) + 1
              if not commonest or tally[t] > tally[commonest] then
                commonest = t
              end
            end
          end
        end
      end
    end
  end

  -- the field tile: plainest by measurement, commonest as the fallback
  local candidates = {}
  for t in pairs(tally) do candidates[#candidates + 1] = t end
  table.sort(candidates)
  local ceilTile = commonest
  local plainScore = nil
  local scores = tex and scoreTiles(map, tex, candidates) or nil
  if scores then
    for _, t in ipairs(candidates) do
      local s = scores[t]
      if s and (plainScore == nil or s < plainScore
                or (s == plainScore and (tally[t] or 0)
                    > (tally[ceilTile] or 0))) then
        plainScore, ceilTile = s, t
      end
    end
  end

  -- the accent pool: the room's MINORITY wall tiles (windows, pictures,
  -- clocks -- whatever the drawn wall carries besides its main tile),
  -- sprinkled through the synthesized walls so they read as decorated
  -- rather than extruded
  -- accents are the room's FEATURED tiles -- the emblem, the window, the
  -- picture -- sprinkled sparingly so a wall has incident without the
  -- feature becoming the wallpaper
  -- No tile sprinkle any more: a fragment of somebody else's window
  -- stretched across a wall was never decoration, it was noise.  Walls
  -- are a plain field, and posters go on top of them.
  local accents = {}
  -- deterministic sparkle: stable per position, roughly one course-half
  -- in eight, so the pattern never shimmers between rebuilds
  local function accentFor(cx, cy, course, half)
    if #accents == 0 then return nil end
    local hsh = (cx * 73856093 + cy * 19349663
                 + course * 83492791 + half * 2654435761) % 8
    if hsh ~= 0 then return nil end
    local pick = (cx * 2654435761 + cy * 40503 + course * 65599) % #accents
    return accents[pick + 1]
  end

  local verts, indexMap, quads = {}, {}, 0


  local boundary = 0

  -- the melt: in cutaway, anything on the player's row or south of it
  -- drops to its stub so the camera sees in -- the cross-section follows
  -- the player around the room
  local function melted(cy)
    return mode == "cutaway" and pcy and cy >= pcy
  end

  -- One synthesized boundary face, floor to lid, wearing the far wall's
  -- art with the accent pool sprinkled through it.  The plane stands half
  -- a pixel BEYOND the cell edge so furniture parked against the map edge
  -- (a plant, a bookcase) can never z-fight its own backdrop.  A warp
  -- column fills to full height too, in a darker shade: a recessed
  -- doorway rather than a hole into the dark.
  local EPS = 0.5

  -- doors go on their own list, drawn with the door texture
  local dVerts, dIdx, dQuads = {}, {}, 0
  local function doorFace(cx, cy, dir, height)
    local x0, z0 = cx * 16, cy * 16
    local o = EPS + 0.05
    local c1, c2, c3, c4
    if dir == "pz" then
      local z = z0 + 16 + o
      c1 = { x0, height, z }; c2 = { x0 + 16, height, z }
      c3 = { x0 + 16, 0, z }; c4 = { x0, 0, z }
    elseif dir == "nz" then
      local z = z0 - o
      c1 = { x0 + 16, height, z }; c2 = { x0, height, z }
      c3 = { x0, 0, z }; c4 = { x0 + 16, 0, z }
    elseif dir == "px" then
      local x = x0 + 16 + o
      c1 = { x, height, z0 + 16 }; c2 = { x, height, z0 }
      c3 = { x, 0, z0 }; c4 = { x, 0, z0 + 16 }
    else
      local x = x0 - o
      c1 = { x, height, z0 }; c2 = { x, height, z0 + 16 }
      c3 = { x, 0, z0 + 16 }; c4 = { x, 0, z0 }
    end
    dVerts[#dVerts + 1] = { c1[1], c1[2], c1[3], 0, 0, 1 }
    dVerts[#dVerts + 1] = { c2[1], c2[2], c2[3], 1, 0, 1 }
    dVerts[#dVerts + 1] = { c3[1], c3[2], c3[3], 1, 1, 1 }
    dVerts[#dVerts + 1] = { c4[1], c4[2], c4[3], 0, 1, 1 }
    Voxel3D.pushQuad(dIdx, dQuads)
    dQuads = dQuads + 1
  end

  local DOOR_H = math.min(24, H)   -- a door is taller than a wall course

  -- Which way the run of doors extends from this cell, so a double door
  -- gets one frame around the pair with a seam up the middle instead of
  -- two single doors jammed together.  Returns the cell's index in its
  -- run and the run's length.
  local function doorRun(cx, cy, dir)
    local ax, ay = (dir == "pz" or dir == "nz") and 1 or 0,
                   (dir == "px" or dir == "nx") and 1 or 0
    local before = 0
    while isDoor(cx - ax * (before + 1), cy - ay * (before + 1)) do
      before = before + 1
    end
    local after = 0
    while isDoor(cx + ax * (after + 1), cy + ay * (after + 1)) do
      after = after + 1
    end
    return before, before + after + 1
  end

  -- One face of the door assembly at (cx, cy): the leaf itself, its
  -- panelling, the jambs at the run's ends and the lintel above.  The
  -- leaf wears the doorway's OWN art -- the mat, the sill, whatever the
  -- map draws there -- so each tileset's doors look like its doors.
  local function pushDoorFace(cx, cy, dir)
    local idx, runLen = doorRun(cx, cy, dir)
    local shade = RISER_SHADE[dir]
    local x0, z0 = cx * 16, cy * 16
    local leafTile = map:tileAt(cx * 2, cy * 2 + 1) or ceilTile

    -- plane placement helper: a quad on this cell's boundary face,
    -- spanning [u0, u1] across the cell and [y0, y1] up it, pushed out
    -- by `out` so panelling sits proud of the leaf
    local function face(u0, u1, y0, y1, tile, sh, out)
      local uv = { uvFor(map, tile) }
      local o = EPS + (out or 0)
      local c1, c2, c3, c4
      if dir == "pz" then
        local z = z0 + 16 + o
        c1 = { x0 + u0, y1, z }; c2 = { x0 + u1, y1, z }
        c3 = { x0 + u1, y0, z }; c4 = { x0 + u0, y0, z }
      elseif dir == "nz" then
        local z = z0 - o
        c1 = { x0 + u1, y1, z }; c2 = { x0 + u0, y1, z }
        c3 = { x0 + u0, y0, z }; c4 = { x0 + u1, y0, z }
      elseif dir == "px" then
        local x = x0 + 16 + o
        c1 = { x, y1, z0 + u1 }; c2 = { x, y1, z0 + u0 }
        c3 = { x, y0, z0 + u0 }; c4 = { x, y0, z0 + u1 }
      else
        local x = x0 - o
        c1 = { x, y1, z0 + u0 }; c2 = { x, y1, z0 + u1 }
        c3 = { x, y0, z0 + u1 }; c4 = { x, y0, z0 + u0 }
      end
      quads = pushQuad(verts, indexMap, quads, c1, c2, c3, c4, uv, sh)
      boundary = boundary + 1
    end

    -- jambs: a 2px frame only at the ENDS of the run, so a double door
    -- reads as one opening rather than two
    -- THE GAME'S OWN DOOR, whole.
    -- This used to build a door: jambs cut in from the sides, a recessed
    -- leaf, two panels proud of it. It was carpentry over the top of art
    -- that already exists -- the map draws a door on that tile, and a
    -- double doorway is simply two of those tiles side by side, which is
    -- what the original does. So: the tile, across the full width of its
    -- own cell, with plain wall above. Neighbouring door cells each draw
    -- their own, and the pair reads as the double door it is.
    -- the doorway: our own door art if it built, the map's tile if not
    if doorArt() then
      doorFace(cx, cy, dir, DOOR_H)
    else
      face(0, 16, 0, DOOR_H, leafTile, shade)
    end

    -- the lintel: wall art from the door head up to the ceiling
    if H > DOOR_H then
      for course = DOOR_H, H - 8, 8 do
        local top = math.min(course + 8, H)
        face(0, 8, course, top, ceilTile, shade)
        face(8, 16, course, top, ceilTile, shade)
      end
    end
  end

  local function pushBoundary(cx, cy, dir)
    if not ceilTile then return end
    if melted(cy) then return end
    if isDoor(cx, cy) then return pushDoorFace(cx, cy, dir) end
    local shade = RISER_SHADE[dir]
    local x0, z0 = cx * 16, cy * 16
    for course = 0, H - 8, 8 do
      for half = 0, 1 do
        local uv = { uvFor(map, accentFor(cx, cy, course, half) or ceilTile) }
        local yA, yB = course + 8, course
        local h0, h1 = half * 8, half * 8 + 8
        local c1, c2, c3, c4
        if dir == "pz" then
          local z = z0 + 16 + EPS
          c1 = { x0 + h0, yA, z }; c2 = { x0 + h1, yA, z }
          c3 = { x0 + h1, yB, z }; c4 = { x0 + h0, yB, z }
        elseif dir == "nz" then
          local z = z0 - EPS
          c1 = { x0 + h1, yA, z }; c2 = { x0 + h0, yA, z }
          c3 = { x0 + h0, yB, z }; c4 = { x0 + h1, yB, z }
        elseif dir == "px" then
          local x = x0 + 16 + EPS
          c1 = { x, yA, z0 + h1 }; c2 = { x, yA, z0 + h0 }
          c3 = { x, yB, z0 + h0 }; c4 = { x, yB, z0 + h1 }
        else
          local x = x0 - EPS
          c1 = { x, yA, z0 + h0 }; c2 = { x, yA, z0 + h1 }
          c3 = { x, yB, z0 + h1 }; c4 = { x, yB, z0 + h0 }
        end
        quads = pushQuad(verts, indexMap, quads, c1, c2, c3, c4, uv, shade)
        boundary = boundary + 1
      end
    end
  end

  for cy = 0, hc - 1 do
    for cx = 0, wc - 1 do
      local ch = h[cy][cx]

      -- The synthesized walls: EVERY non-void cell that touches the void
      -- gets a full-height backdrop on that side -- open floor, and also
      -- furniture parked against the map edge (the plant, the bookcase),
      -- whose own bodies otherwise stand in front of naked dark.  Gen 1
      -- draws only the north wall; the other three "walls" are the map
      -- edge, so in 3D they have to be stood up here.
      if not isVoid[cy][cx] then
        if outside(cx, cy + 1) then pushBoundary(cx, cy, "pz") end
        if outside(cx, cy - 1) then pushBoundary(cx, cy, "nz") end
        if outside(cx + 1, cy) then pushBoundary(cx, cy, "px") end
        if outside(cx - 1, cy) then pushBoundary(cx, cy, "nx") end
      end

      -- the lid: over every non-void cell whose own column stops short,
      -- minus the cutaway's hole around the player
      local lid = ch < H and not isVoid[cy][cx]
      if lid and mode == "cutaway" and pcx then
        local d = math.max(math.abs(cx - pcx), math.abs(cy - pcy))
        if d <= HOLE_RADIUS then lid = false end
      end
      if lid then
        local x0, z0 = cx * 16, cy * 16
        local shade = CEIL_SHADE[(cx + cy) % 2 + 1]
        local uv = ceilTile and { uvFor(map, ceilTile) } or { 0, 0, 0, 0 }
        quads = pushQuad(verts, indexMap, quads,
                         { x0, H, z0 + 16 }, { x0 + 16, H, z0 + 16 },
                         { x0 + 16, H, z0 }, { x0, H, z0 }, uv, shade)
      end

      -- the risers: WALL-classed cells grow to the lid, one face per
      -- side that looks at open room.  Furniture that happens to stand
      -- 16px tall (props, plants, cutouts) is furniture, not wall, and
      -- keeps its own silhouette.  The cutaway melts these by row.
      if isWall[cy][cx] and not isVoid[cy][cx]
         and ch >= WALL_H and ch < H and not melted(cy) then
        do
          if heightAt(cx, cy + 1) < WALL_H then
            quads = pushRiserFace(verts, indexMap, quads, map,
                                  cx, cy, ch, H, "pz", ceilTile, accentFor)
          end
          if heightAt(cx, cy - 1) < WALL_H then
            quads = pushRiserFace(verts, indexMap, quads, map,
                                  cx, cy, ch, H, "nz", ceilTile, accentFor)
          end
          if heightAt(cx + 1, cy) < WALL_H then
            quads = pushRiserFace(verts, indexMap, quads, map,
                                  cx, cy, ch, H, "px", ceilTile, accentFor)
          end
          if heightAt(cx - 1, cy) < WALL_H then
            quads = pushRiserFace(verts, indexMap, quads, map,
                                  cx, cy, ch, H, "nx", ceilTile, accentFor)
          end
        end
      end
    end
  end

  -- ---- ROCK: what a cave gets instead of a plastered lid.
  -- The structural lid stays where it is -- walls still meet something
  -- -- and a second, UNEVEN surface hangs beneath it: a panel per cell
  -- at a hashed height, with a skirt wherever it drops below its
  -- neighbour, exactly as the forest canopy is built.  Rock sags.
  --
  -- Then the spikes.  A stalactite is a tapering spike from the rock
  -- above; a stalagmite is the same shape stood on its head, growing
  -- from the floor to meet it.  Both wear the cave's own tile art, and
  -- both are hashed per cell so Mt Moon looks the same every visit.
  local ROCK_DROP_MIN, ROCK_DROP_MAX = 2, 11    -- how far the rock sags
  local SPIKE_EVERY = 5                         -- one cell in this many
  local STAL_MIN, STAL_MAX = 5, 15
  local GROUND_ODDS = 0.45                      -- of those, from below
  local rocks, spikes = 0, 0

  local function rockAt(cx, cy)
    return H - (ROCK_DROP_MIN
                + hash01(cx, cy, 241) * (ROCK_DROP_MAX - ROCK_DROP_MIN))
  end

  -- a four-sided spike between two heights, tapering to a point
  local function spike(cx, cy, fromY, toY, tile, wide)
    local uv = { uvFor(map, tile) }
    local px2, pz2 = cx * 16 + 4 + hash01(cx, cy, 251) * 8,
                     cy * 16 + 4 + hash01(cy, cx, 257) * 8
    local w = wide
    local shade = { 0.86, 0.58, 0.74, 0.66 }
    local corners = {
      { px2 - w, pz2 + w, px2 + w, pz2 + w },
      { px2 + w, pz2 - w, px2 - w, pz2 - w },
      { px2 + w, pz2 + w, px2 + w, pz2 - w },
      { px2 - w, pz2 - w, px2 - w, pz2 + w },
    }
    for i, c in ipairs(corners) do
      quads = pushQuad(verts, indexMap, quads,
                       { c[1], fromY, c[2] }, { c[3], fromY, c[4] },
                       { px2, toY, pz2 }, { px2, toY, pz2 },
                       uv, shade[i])
    end
    spikes = spikes + 1
  end

  if rocky and cfg.rock ~= false then
    local rockTile = ceilTile
    for cy = 0, hc - 1 do
      for cx = 0, wc - 1 do
        local roofed = heightAt(cx, cy) < H and not isVoid[cy][cx]
        if roofed and not melted(cy)
           and not (mode == "cutaway" and pcx
                    and math.max(math.abs(cx - pcx), math.abs(cy - pcy))
                        <= HOLE_RADIUS) then
          local x0, z0 = cx * 16, cy * 16
          local y = rockAt(cx, cy)
          local uv = rockTile and { uvFor(map, rockTile) } or { 0, 0, 0, 0 }
          -- the underside, seen from below
          quads = pushQuad(verts, indexMap, quads,
                           { x0, y, z0 + 16 }, { x0 + 16, y, z0 + 16 },
                           { x0 + 16, y, z0 }, { x0, y, z0 }, uv,
                           0.52 + hash01(cx, cy, 263) * 0.22)
          rocks = rocks + 1
          -- a skirt where this panel hangs below its neighbour, so the
          -- rock has thickness rather than being a floating sheet
          local sides = {
            { rockAt(cx, cy + 1), { x0, z0 + 16 }, { x0 + 16, z0 + 16 } },
            { rockAt(cx, cy - 1), { x0 + 16, z0 }, { x0, z0 } },
            { rockAt(cx + 1, cy), { x0 + 16, z0 + 16 }, { x0 + 16, z0 } },
            { rockAt(cx - 1, cy), { x0, z0 }, { x0, z0 + 16 } },
          }
          for _, sd in ipairs(sides) do
            local drop = (sd[1] or y) - y
            if drop > 0.4 then
              local a, b = sd[2], sd[3]
              quads = pushQuad(verts, indexMap, quads,
                               { a[1], y + drop, a[2] }, { b[1], y + drop, b[2] },
                               { b[1], y, b[2] }, { a[1], y, a[2] }, uv, 0.44)
            end
          end

          -- and the spikes
          if rockTile
             and math.floor(hash01(cx, cy, 269) * SPIKE_EVERY) == 0 then
            local len = STAL_MIN + hash01(cx, cy, 271) * (STAL_MAX - STAL_MIN)
            if hash01(cx, cy, 277) < GROUND_ODDS then
              spike(cx, cy, 0, math.min(len, y - 2), rockTile, 2.6)
            else
              spike(cx, cy, y, math.max(1, y - len), rockTile, 2.2)
            end
          end
        end
      end
    end
  end

  -- ---- LIGHT SPILL, and the FITTINGS that hang from the ceiling.
  -- Both live on their own mesh drawn with a plain white pixel, because
  -- they are LIGHT rather than surface: a slab of daylight lying on the
  -- floor inside a doorway, and a lamp under the ceiling with its pool
  -- beneath it.  The vines taught the trick of hanging something from a
  -- roof; a pendant is the same shape with a shade on the end.
  local SPILL_REACH = 30       -- how far daylight lies into the room
  local SPILL_SHADE = 0.9
  local LAMP_DROP = 6          -- flex length below the ceiling
  local LAMP_R = 5             -- the shade's half-width
  local gVerts, gIdx, gQuads = {}, {}, 0
  local spills, lamps = 0, 0

  local function glowQuad(c1, c2, c3, c4, shade)
    gVerts[#gVerts + 1] = { c1[1], c1[2], c1[3], 0.5, 0.5, shade }
    gVerts[#gVerts + 1] = { c2[1], c2[2], c2[3], 0.5, 0.5, shade }
    gVerts[#gVerts + 1] = { c3[1], c3[2], c3[3], 0.5, 0.5, shade }
    gVerts[#gVerts + 1] = { c4[1], c4[2], c4[3], 0.5, 0.5, shade }
    Voxel3D.pushQuad(gIdx, gQuads)
    gQuads = gQuads + 1
  end

  -- daylight through a doorway: a wedge on the floor, narrowing as it
  -- reaches in, because a door is a slot and not a window wall
  local function lightSpill(cx, cy, dir)
    local x0, z0 = cx * 16, cy * 16
    local y = 0.9
    local far = SPILL_REACH
    local c1, c2, c3, c4
    if dir == "pz" then          -- opening to the south, light comes north
      c1 = { x0 + 1, y, z0 + 16 }; c2 = { x0 + 15, y, z0 + 16 }
      c3 = { x0 + 13, y, z0 + 16 - far }; c4 = { x0 + 3, y, z0 + 16 - far }
    elseif dir == "nz" then
      c1 = { x0 + 15, y, z0 }; c2 = { x0 + 1, y, z0 }
      c3 = { x0 + 3, y, z0 + far }; c4 = { x0 + 13, y, z0 + far }
    elseif dir == "px" then
      c1 = { x0 + 16, y, z0 + 15 }; c2 = { x0 + 16, y, z0 + 1 }
      c3 = { x0 + 16 - far, y, z0 + 3 }; c4 = { x0 + 16 - far, y, z0 + 13 }
    else
      c1 = { x0, y, z0 + 1 }; c2 = { x0, y, z0 + 15 }
      c3 = { x0 + far, y, z0 + 13 }; c4 = { x0 + far, y, z0 + 3 }
    end
    glowQuad(c1, c2, c3, c4, SPILL_SHADE)
    spills = spills + 1
  end

  -- a pendant: a flex down from the ceiling, a shade, and the pool it
  -- throws on the floor below
  local function fitting(cx, cy, ceilY)
    local x, z = cx * 16 + 8, cy * 16 + 8
    local top = ceilY - 0.6
    local bulb = top - LAMP_DROP
    -- the flex, thin and dark enough to read as a cord
    glowQuad({ x - 0.6, top, z }, { x + 0.6, top, z },
             { x + 0.6, bulb, z }, { x - 0.6, bulb, z }, 0.30)
    glowQuad({ x, top, z - 0.6 }, { x, top, z + 0.6 },
             { x, bulb, z + 0.6 }, { x, bulb, z - 0.6 }, 0.30)
    -- the shade: a cone read as two crossed trapezia
    glowQuad({ x - LAMP_R, bulb - 3.5, z }, { x + LAMP_R, bulb - 3.5, z },
             { x + 1.4, bulb, z }, { x - 1.4, bulb, z }, 1.0)
    glowQuad({ x, bulb - 3.5, z - LAMP_R }, { x, bulb - 3.5, z + LAMP_R },
             { x, bulb, z + 1.4 }, { x, bulb, z - 1.4 }, 1.0)
    -- and the light it lays on the floor
    local pool = 22
    glowQuad({ x - pool, 0.8, z + pool }, { x + pool, 0.8, z + pool },
             { x + pool, 0.8, z - pool }, { x - pool, 0.8, z - pool }, 0.5)
    lamps = lamps + 1
  end

  -- ---- CONTACT SHADOW.
  -- A dark band where the floor meets a wall.  It is the cheapest trick
  -- in real-time rendering and it does more than it costs: without it,
  -- everything looks placed ON the floor rather than standing IN the
  -- room, because nothing grounds it.  The band is the floor's own art
  -- at a fraction of its brightness, so it darkens rather than paints.
  local SHADOW_W = 3.2
  local SHADOW_SHADE = 0.44
  local shadows = 0
  local function contactShadow(cx, cy, dir)
    local okT, tile = pcall(function() return map:tileAt(cx * 2, cy * 2) end)
    local uv = { uvFor(map, (okT and tile) or 0) }
    local x0, z0 = cx * 16, cy * 16
    local y = 0.45
    local w = SHADOW_W
    local c1, c2, c3, c4
    if dir == "pz" then
      c1 = { x0, y, z0 + 16 }; c2 = { x0 + 16, y, z0 + 16 }
      c3 = { x0 + 16, y, z0 + 16 - w }; c4 = { x0, y, z0 + 16 - w }
    elseif dir == "nz" then
      c1 = { x0, y, z0 + w }; c2 = { x0 + 16, y, z0 + w }
      c3 = { x0 + 16, y, z0 }; c4 = { x0, y, z0 }
    elseif dir == "px" then
      c1 = { x0 + 16 - w, y, z0 + 16 }; c2 = { x0 + 16, y, z0 + 16 }
      c3 = { x0 + 16, y, z0 }; c4 = { x0 + 16 - w, y, z0 }
    else
      c1 = { x0, y, z0 + 16 }; c2 = { x0 + w, y, z0 + 16 }
      c3 = { x0 + w, y, z0 }; c4 = { x0, y, z0 }
    end
    quads = pushQuad(verts, indexMap, quads, c1, c2, c3, c4, uv,
                     SHADOW_SHADE)
    shadows = shadows + 1
  end

  -- ---- RAIL AND SKIRTING.
  -- One course of a contrasting tile near the ceiling and another at the
  -- floor.  Besides looking like a room, this is what makes taller
  -- ceilings possible: the wall field above the drawn row is one tile
  -- repeated, and the higher the wall the more obviously it bands.  A
  -- rail breaks the run.
  local RAIL_H = 2.6
  local rails = 0
  local railTile = nil
  do
    -- the BUSIEST tile, by the same measure that picks the plainest for
    -- the field: whatever the room uses for detail
    local best = nil
    for _, t in ipairs(candidates or {}) do
      if scores and (not best or (scores[t] or 0) > (scores[best] or 0)) then
        best = t
      end
    end
    railTile = best
  end

  local function railBand(cx, cy, dir, y0, y1, shade)
    if not railTile then return end
    local uv = { uvFor(map, railTile) }
    local x0, z0 = cx * 16, cy * 16
    local o = EPS + 0.2
    local c1, c2, c3, c4
    if dir == "pz" then
      local z = z0 + 16 - o
      c1 = { x0 + 16, y1, z }; c2 = { x0, y1, z }
      c3 = { x0, y0, z }; c4 = { x0 + 16, y0, z }
    elseif dir == "nz" then
      local z = z0 + o
      c1 = { x0, y1, z }; c2 = { x0 + 16, y1, z }
      c3 = { x0 + 16, y0, z }; c4 = { x0, y0, z }
    elseif dir == "px" then
      local x = x0 + 16 - o
      c1 = { x, y1, z0 }; c2 = { x, y1, z0 + 16 }
      c3 = { x, y0, z0 + 16 }; c4 = { x, y0, z0 }
    else
      local x = x0 + o
      c1 = { x, y1, z0 + 16 }; c2 = { x, y1, z0 }
      c3 = { x, y0, z0 }; c4 = { x, y0, z0 + 16 }
    end
    quads = pushQuad(verts, indexMap, quads, c1, c2, c3, c4, uv, shade)
    rails = rails + 1
  end

  -- ---- posters: a decal on the odd wall face, hung proud of it
  local pVerts, pIdx, pQuads = {}, {}, 0
  local posterImg, posterFrames = posters(map)
  local frames = math.max(1, posterFrames or 0)

  -- Where a picture has already gone, and where one must never go.  Two
  -- pictures side by side read as wallpaper rather than as things
  -- somebody hung, and one over a doorway is plainly wrong -- doors are
  -- how you leave, and a poster across one looks like a mistake because
  -- it is.
  local hung = {}
  -- the module's own door test, which counts warps as well as door
  -- tiles; the poster code used to ask a weaker question and hung
  -- pictures over doorways the warp list knew about
  local doorish = isDoor

  local function hangPoster(cx, cy, dir)
    if not posterImg or (posterFrames or 0) < 1 then return end
    if math.floor(hash01(cx, cy, 131) * POSTER_EVERY) ~= 0 then return end

    -- not on a door, and not on the wall a door passes through
    if doorish(cx, cy) then return end
    local ax, ay = cx, cy
    if dir == "pz" then ay = cy + 1
    elseif dir == "nz" then ay = cy - 1
    elseif dir == "px" then ax = cx + 1
    else ax = cx - 1 end
    if doorish(ax, ay) then return end

    -- not beside another picture, in any direction
    for dy = -1, 1 do
      for dx = -1, 1 do
        if hung[(cy + dy) .. ":" .. (cx + dx)] then return end
      end
    end
    hung[cy .. ":" .. cx] = true
    local frame = math.floor(hash01(cx, cy, 137) * frames) % frames
    local fu0 = frame / frames
    local fu1 = (frame + 1) / frames
    local half = POSTER_SIZE * 0.5 * 0.62      -- a picture, not a mural
    local y0, y1 = POSTER_HEIGHT - half, POSTER_HEIGHT + half
    local x0, z0 = cx * 16, cy * 16
    -- INSIDE the wall, facing into the room.  These were hung a fraction
    -- OUTSIDE it, facing the void: every picture in Kanto was on the
    -- back of a building where nobody could see it.  `dir` names the
    -- side of the cell the void is on, so the room is always the other
    -- way, and the offset has to come inward.
    local o = EPS + 0.35
    local c1, c2, c3, c4
    if dir == "pz" then                      -- void to the south
      local z = z0 + 16 - o
      c1 = { x0 + 8 + half, y1, z }; c2 = { x0 + 8 - half, y1, z }
      c3 = { x0 + 8 - half, y0, z }; c4 = { x0 + 8 + half, y0, z }
    elseif dir == "nz" then                  -- void to the north
      local z = z0 + o
      c1 = { x0 + 8 - half, y1, z }; c2 = { x0 + 8 + half, y1, z }
      c3 = { x0 + 8 + half, y0, z }; c4 = { x0 + 8 - half, y0, z }
    elseif dir == "px" then                  -- void to the east
      local x = x0 + 16 - o
      c1 = { x, y1, z0 + 8 - half }; c2 = { x, y1, z0 + 8 + half }
      c3 = { x, y0, z0 + 8 + half }; c4 = { x, y0, z0 + 8 - half }
    else                                     -- void to the west
      local x = x0 + o
      c1 = { x, y1, z0 + 8 + half }; c2 = { x, y1, z0 + 8 - half }
      c3 = { x, y0, z0 + 8 - half }; c4 = { x, y0, z0 + 8 + half }
    end
    local shade = 1.0
    pVerts[#pVerts + 1] = { c1[1], c1[2], c1[3], fu0, 0, shade }
    pVerts[#pVerts + 1] = { c2[1], c2[2], c2[3], fu1, 0, shade }
    pVerts[#pVerts + 1] = { c3[1], c3[2], c3[3], fu1, 1, shade }
    pVerts[#pVerts + 1] = { c4[1], c4[2], c4[3], fu0, 1, shade }
    Voxel3D.pushQuad(pIdx, pQuads)
    pQuads = pQuads + 1
  end

  for cy = 0, hc - 1 do
    for cx = 0, wc - 1 do
      if not isVoid[cy][cx] then
        local sides = {
          { "pz", outside(cx, cy + 1) }, { "nz", outside(cx, cy - 1) },
          { "px", outside(cx + 1, cy) }, { "nx", outside(cx - 1, cy) },
        }
        -- a melted wall has nothing to hang a rail or a picture on; the
        -- floor shadow stays, since the floor is still there
        local gone = melted(cy)
        for _, sd in ipairs(sides) do
          if sd[2] then
            if posterImg and not gone then hangPoster(cx, cy, sd[1]) end
            if cfg.shadows ~= false then contactShadow(cx, cy, sd[1]) end
            if cfg.rails ~= false and not gone and not organic then
              -- a picture rail up near the lid. There was a skirting
              -- course too; it read as a stripe of somebody else's tile
              -- along the floor rather than as a moulding, so it is gone.
              railBand(cx, cy, sd[1], H - 5.4, H - 5.4 + RAIL_H, 0.78)
            end
          end
        end
        -- daylight lies in through a doorway
        if cfg.spill ~= false and not organic and isDoor(cx, cy) then
          for _, sd in ipairs(sides) do
            if sd[2] then lightSpill(cx, cy, sd[1]) end
          end
        end
      end
    end
  end

  -- fittings on a loose grid, so a big room gets several and a cupboard
  -- gets none: hung where there is floor beneath and lid above
  if cfg.fittings ~= false and not organic then
    local placed = {}
    local function tryFit(cx, cy)
      if cx < 0 or cy < 0 or cx >= wc or cy >= hc then return end
      if isVoid[cy][cx] or doorish(cx, cy) then return end
      if placed[cy .. ":" .. cx] then return end
      placed[cy .. ":" .. cx] = true
      fitting(cx, cy, H)
    end
    -- a loose grid for big rooms...
    for cy = 2, hc - 3, 5 do
      for cx = 2, wc - 3, 5 do tryFit(cx, cy) end
    end
    -- ...and the middle of the room regardless, so a small room still
    -- gets its light rather than falling through the grid
    if next(placed) == nil then
      tryFit(math.floor(wc / 2), math.floor(hc / 2))
    end
  end

  local note = ("%d quads (%d boundary), %d wall cells of %dx%d, "
    .. "lid at %d, %s"):format(quads, boundary, walls, wc, hc, H, mode)
  -- accents belong in the note so a monotonous room can be diagnosed
  note = note .. (", %d accents, field %s"):format(#accents,
    scores and ("plain#" .. tostring(ceilTile)) or "by frequency")
  if quads == 0 then return nil, note .. " -- nothing to build" end
  local mesh = Voxel3D.newMesh(verts, indexMap)
  if not mesh then return nil, note .. " -- driver refused the mesh" end
  local pMesh = nil
  if pQuads > 0 then pMesh = Voxel3D.newMesh(pVerts, pIdx) end
  local gMesh = nil
  if gQuads > 0 then gMesh = Voxel3D.newMesh(gVerts, gIdx) end
  local dMesh = nil
  if dQuads > 0 then dMesh = Voxel3D.newMesh(dVerts, dIdx) end
  note = note .. ((dQuads > 0) and (", %d doors"):format(dQuads) or "")
  note = note .. ((pQuads > 0) and (", %d posters"):format(pQuads) or "")
  note = note .. ((shadows > 0) and (", %d shadows"):format(shadows) or "")
  note = note .. ((rails > 0) and (", %d rails"):format(rails) or "")
  note = note .. ((spills > 0) and (", %d spills"):format(spills) or "")
  note = note .. ((lamps > 0) and (", %d fittings"):format(lamps) or "")
  note = note .. ((rocks > 0) and (", %d rock, %d spikes")
                                  :format(rocks, spikes) or "")
  return mesh, note, pMesh, posterImg, gMesh, dMesh
end

-- ------- SELF-UNINSTALL.
-- The patch lives in Dramatic Shape's own folder, so deleting this mod
-- leaves it behind: the shadow copies keep loading, and the option that
-- would have removed them went with the mod.  People have got stuck.
--
-- These modules therefore check, once, whether the companion is still
-- there.  It publishes a config bridge as it loads, always BEFORE
-- Dramatic Shape.  No bridge means no mod -- and in that case this code
-- takes itself out: originals are restored where they were backed up,
-- shadow copies are deleted where they were not, and everything here
-- goes quiet for the rest of the session.  Next boot, Dramatic Shape is
-- stock again with nothing left to clean.
local orphaned = nil

-- FIND Dramatic Shape the way the patcher does: by its manifest id, not
-- by a folder name. The folder is commonly `DramaticShapeVoxelMod`, and
-- this hardcoded `mods/DRAMATIC_SHAPE`, so for most installs the
-- self-uninstall deleted NOTHING -- which is exactly the pile of
-- lingering files people found in their save directory, and why the head
-- bob was still there after they removed the mod.
local function findDS(fs)
  local ok, names = pcall(fs.getDirectoryItems, "mods")
  if not (ok and names) then return nil end
  for _, name in ipairs(names) do
    local okM, manifest = pcall(fs.read, "mods/" .. name .. "/manifest.json")
    if okM and manifest
       and manifest:find('"id"%s*:%s*"DRAMATIC_SHAPE"') then
      return "mods/" .. name
    end
  end
  -- last resort: any mod folder carrying OUR payload is one we patched
  for _, name in ipairs(names) do
    local okC = pcall(fs.read, "mods/" .. name .. "/lib/Ceiling.lua")
    if okC then return "mods/" .. name end
  end
  return nil
end

local function selfRemove()
  local fs = love and love.filesystem
  if not fs then return end

  -- THE LEDGER FIRST: the patcher records every path it writes, so
  -- removal can restore exactly what was done without knowing anything
  -- else about this or any other version of the mod.
  local okL, led = pcall(fs.read, "ds_fp_ceiling_written.txt")
  if okL and led then
    for path in led:gmatch("[^\n]+") do
      local okP, orig = pcall(fs.read, path .. ".pre-ceiling")
      if okP and orig then
        pcall(fs.write, path, orig)
        pcall(fs.remove, path .. ".pre-ceiling")
      else
        pcall(fs.remove, path)
      end
    end
    pcall(fs.remove, "ds_fp_ceiling_written.txt")
    pcall(fs.write, "ds_fp_ceiling_log.txt",
          "the companion mod was gone; the patch restored everything it "
          .. "had written (from the ledger) and removed itself.\n")
    return
  end

  -- no ledger (an install patched by an older version): fall back to
  -- finding the folder and removing the known files
  local base = findDS(fs)
  if not base then return end
  -- originals first: a save-directory install was patched in place
  for _, rel in ipairs({ "/lib/VoxelScene.lua", "/lib/FirstPerson.lua",
                         "/main.lua" }) do
    local pre = base .. rel .. ".pre-ceiling"
    local okR, orig = pcall(fs.read, pre)
    if okR and orig then
      pcall(fs.write, base .. rel, orig)
      pcall(fs.remove, pre)
    end
  end
  -- then the shadows and the payload modules themselves
  for _, rel in ipairs({ "/lib/Ceiling.lua", "/lib/Backdrop.lua",
                         "/lib/SkyLayer.lua", "/lib/Flora.lua",
                         "/lib/Jump.lua", "/lib/backdrop.png",
                         "/lib/backdrop2.png", "/lib/backdrop3.png",
                         "/lib/backdrop4.png", "/lib/posters.png",
                         "/lib/posters-pokecenter.png",
                         "/lib/posters-pokemart.png",
                         "/lib/VoxelScene.lua", "/lib/FirstPerson.lua",
                         "/main.lua" }) do
    -- only remove what WE shadowed: a file the game folder also provides
    -- comes back on its own, and one it does not was ours to begin with
    pcall(fs.remove, base .. rel)
  end
  pcall(fs.write, "ds_fp_ceiling_log.txt",
        "the companion mod was gone, so the patch removed itself.\n"
        .. "Dramatic Shape is stock again from the next boot.\n")
end

local function abandoned()
  if orphaned == nil then
    orphaned = (rawget(_G, "__ds_ceiling_config") == nil)
    if orphaned then pcall(selfRemove) end
  end
  return orphaned
end

-- A plain white pixel for any surface with no art: passing nil as the
-- texture keeps whatever was last bound (the map atlas), which paints a
-- ribbon of the tileset across the surface instead of leaving it plain.
local whiteImg = nil
local function white()
  if whiteImg then return whiteImg end
  local ok, img = pcall(function()
    local data = love.image.newImageData(2, 2)
    for y = 0, 1 do
      for x = 0, 1 do data:setPixel(x, y, 1, 1, 1, 1) end
    end
    local i = love.graphics.newImage(data)
    i:setFilter("nearest", "nearest")
    return i
  end)
  if ok then whiteImg = img end
  return whiteImg
end

-- Draw blocks run inside this: a throw midway through one would leave
-- graphics state set for the rest of the frame, and everything drawn
-- after us would inherit it -- including other mods' sprites.
local function guarded(fn)
  -- headless, or a driver without a graphics stack: just run it
  local g = love and love.graphics
  if not (g and g.push and g.pop) then return pcall(fn) end
  local pushed = pcall(g.push, "all")
  pcall(fn)
  if pushed then pcall(g.pop) end
end

-- ------- the draw, from inside the scene pass (depth live, camera placed)
function Ceiling.draw(state, atlasFor)
  if abandoned() then return end
  local cfg = config()
  if not cfg.ceiling then
    status("ceiling switched off")
    return
  end
  local map = state and state.map
  if not map then
    status("scene ran with no map")
    return
  end
  local mapId = tostring((map.def and map.def.id)
                or (map.tileset and map.tileset.id) or "?")
  if not isInterior(map) then
    status(mapId .. ": outdoors -- untouched by design")
    return
  end
  local okBlend, blend = pcall(FirstPerson.blendEased)
  blend = okBlend and blend or 0
  -- Three separate questions, three separate answers:
  --   inside the head (1ST)        -> the whole room, sealed
  --   boomed out in 3RD          -> whatever 3RD CEILING says
  --   the diorama rungs          -> whatever SIMS CUTAWAY says
  -- They used to share one toggle, which meant you could not have a
  -- cutaway in the diorama and nothing at all in 3RD.
  local mode
  local is3rd = boomedOut()
  if blend > BLEND_GATE and not is3rd then
    mode = "fp"
  elseif blend > BLEND_GATE then
    local want = cfg.third or "CUTAWAY"
    if want == "FULL" then
      mode = "fp"
    elseif want == "CUTAWAY" then
      mode = "cutaway"
    else
      status(mapId .. ": 3RD person, ceiling off by choice")
      return
    end
  elseif cfg.cutaway then
    mode = "cutaway"
  else
    status(mapId .. ": diorama, CUTAWAY off -- open dollhouse as shipped")
    return
  end

  local H = cfg.headroom or 32
  local pcx, pcy
  if mode == "cutaway" then
    local p = state.player
    pcx = p and p.cellX or 0
    pcy = p and p.cellY or 0
  end
  -- the atlas is needed BEFORE the build: plainness is measured from it
  local tex = nil
  if atlasFor then
    local okT, t = pcall(atlasFor, map)
    if okT then tex = t end
  end

  local key = table.concat({ mode, H, pcx or "-", pcy or "-" }, ":")
  if not cache or cache.map ~= map or cache.key ~= key then
    if cache and cache.mesh then pcall(cache.mesh.release, cache.mesh) end
    local mesh, note, pMesh, pImg, gMesh, dMesh =
      build(map, H, mode, pcx, pcy, tex)
    cache = { map = map, key = key, mesh = mesh, note = tostring(note),
              posters = pMesh, sheet = pImg, glow = gMesh, doors = dMesh }
  end
  if cache.mesh then
    status(mapId .. ": DRAWING " .. cache.note
           .. (tex and ", textured" or ", untextured"))
    guarded(function()
      Voxel3D.draw(cache.mesh, tex or white(), nil)
      -- the pictures, on their own sheet
      if cache.doors and doorArt() then
        Voxel3D.draw(cache.doors, doorArt(), nil)
      end
      if cache.posters and cache.sheet then
        Voxel3D.draw(cache.posters, cache.sheet, nil)
      end
      -- light: spill and fittings, warm and translucent, over the room
      if cache.glow then
        love.graphics.setDepthMode("lequal", false)
        -- ADDITIVE. Alpha-blending a warm quad over a pale floor makes
        -- the floor darker, which is why the lamps were dimming the
        -- rooms they were meant to light.
        local okB = pcall(love.graphics.setBlendMode, "add")
        love.graphics.setColor(0.42, 0.36, 0.22, 1.0)
        Voxel3D.draw(cache.glow, white(), nil)
        if okB then pcall(love.graphics.setBlendMode, "alpha") end
      end
    end)
  else
    status(mapId .. ": no mesh (" .. cache.note .. ")")
  end
end

function Ceiling.invalidate()
  if cache and cache.mesh then pcall(cache.mesh.release, cache.mesh) end
  if cache and cache.posters then pcall(cache.posters.release, cache.posters) end
  if cache and cache.glow then pcall(cache.glow.release, cache.glow) end
  if cache and cache.doors then pcall(cache.doors.release, cache.doors) end
  cache = nil
end

return Ceiling
