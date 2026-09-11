-- The town map, as Kanto the way the games draw it.
--
-- WHAT THIS REPLACES, and what it replaced before. `src.ui.TownMap` draws
-- the Game Boy's town map: the classic 20x18-tile picture of Kanto in four
-- shades, a square per town, a white corridor per route, a wave pattern for
-- the sea, and a blinking box for where you are. The first cut of this file
-- threw that picture away and rebuilt the region out of every outdoor map's
-- own cells, stood where the connection graph said. It was honest and it was
-- wrong: the connection graph does not reach Mt. Moon, Rock Tunnel, Viridian
-- Forest, Victory Road, the Indigo Plateau, the Seafoam Islands, the Power
-- Plant, the Safari Zone or the Pokemon Tower -- none of them is an outdoor
-- map -- so the thing on screen was a green shape with the landmarks missing,
-- and nobody who has held a Game Boy recognised it as Kanto.
--
-- THIS ONE IS BUILT FROM THE CLASSIC MAP ITSELF. The engine ships the
-- original town map data: 47 locations with their positions on the 16x16
-- grid (`field.townMap.locations`, from data/maps/town_map_entries.asm) and
-- the 20x18 tilemap of the picture (`field.townMap.background.map`). Every
-- tile of that picture is one of a dozen ids and each id means one thing --
-- sea, land, route corridor, town square, cave mark, a coast diagonal, a sea
-- route dash -- so the picture IS a map of what is where, at the resolution
-- the game's own artists chose. This file reads it, upsamples it eight times,
-- smooths the coast, raises the land, piles the mountains where the cave
-- marks are, plants the forest, lays the roads white as the corridors, and
-- builds each town out of little houses in the colour the town is named
-- after. The result is the Kanto everyone knows, as a diorama.
--
-- WHAT THE ENGINE STILL OWNS. The screen's behaviour: the cursor (d-pad
-- snaps between locations in grid mode), which locations exist, B to close,
-- and the two special modes -- FLY (A departs for the selected town) and the
-- Pokedex AREA (nests blink). This file reads `screen.sel`, `screen.locs`,
-- `screen.playerLoc`, `screen.fly` and `screen.nests` every frame and draws
-- what they say. It never consumes A while the screen is a fly picker.
--
-- THE ORIGINAL IS ONE ROW AWAY. `WorldMap3D.setting` (MAP: 3D / CLASSIC)
-- lets the player have the Game Boy picture back: on CLASSIC this file draws
-- nothing and stops silencing the engine's own draw, so the screen is exactly
-- what it was before this mod existed. The classic picture is also drawn as
-- an inset in the 3D view, because it is the map everyone has in their head
-- and a glance at it settles where the camera is looking.
--
-- WHERE IT DRAWS FROM. `Renderer.endFrame`, and only from there: the town map
-- is an opaque screen, the world stage does not run behind it, and the
-- engine composites its own 160x144 canvas over the window after the
-- screen's draw. endFrame is the first seam after that composite (measured
-- across tests/worldmap_probe4-6.lua by the first cut, and unchanged).
--
-- ENGLISH, because the screen it replaces speaks it and the game's own
-- strings are ROM strings. Everything a player reads here is in one place
-- (the STRINGS table) for the day somebody wants another language.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local RenderTarget = V.require("RenderTarget")
local BattleHudXY = V.require("BattleHudXY")
local WorldMapQuest = V.require("WorldMapQuest")
local ModSetting = V.require("ModSetting")
local DayNight = V.require("DayNight")

local WorldMap3D = {}

WorldMap3D.ENABLED = true

-- The row. CLASSIC hands the screen back to the engine untouched.
WorldMap3D.setting = ModSetting.new("worldmap", "MAP",
                                    { "3d", "classic" }, { "3D", "CLASSIC" })

function WorldMap3D.classic()
  local ok, v = pcall(WorldMap3D.setting.get, WorldMap3D.setting)
  return ok and v == "classic"
end

-- ---------------------------------------------------------------- the grid
--
-- The picture is 20 tiles by 18; the location grid is 16 by 16 and sits two
-- tiles in and one tile down on it (TownMapCoordsToOAMCoords). Each tile
-- becomes SUB x SUB cells of one world unit, so the island is 160 x 144
-- units -- the picture's own pixel size, which is no accident: a world unit
-- is a Game Boy pixel of the original.
local COLS, ROWS = 20, 18
local SUB = 8
local GW, GH = COLS * SUB, ROWS * SUB
local GRID_DX, GRID_DY = 2, 1

-- The tile ids of the classic picture, read off the sheet the engine ships
-- (assets/generated/townmap/tiles.png, 16 tiles of 8x8; decoded in the
-- session that wrote this and checked against every town's square).
local T_SEA, T_TOWN, T_LAND, T_ROAD = 0x4, 0x5, 0x6, 0x7
local T_COAST_BL, T_COAST_BR, T_COAST_TR, T_COAST_TL = 0x8, 0x9, 0xA, 0xB
local T_CAVE = 0xC
local T_SEAROUTE_END, T_SEAROUTE_H, T_SEAROUTE_V = 0xD, 0xE, 0xF

-- Cell kinds, after upsampling.
local K_SEA, K_LAND, K_ROAD, K_TOWN, K_CAVE = 0, 1, 2, 3, 4

-- ---------------------------------------------------------------- the look
--
-- Heights in world units. The sea surface is the reference: land stands a
-- little above it, the seabed a little below, and only the mountains climb.
WorldMap3D.SEA_Y = -0.55
local SEABED_Y = -2.2
local LAND_Y = 0.0
local HILL_AMP = 1.1
local PEAK_H = 9.5
local PEAK_R = 9.0
local KNOLL_H = 2.4

local SKY_TOP = { 0.16, 0.36, 0.70 }
local SKY_LOW = { 0.62, 0.78, 0.90 }
local FOG = { 0.60, 0.74, 0.86 }
local SUN_RAY = { -0.4507, -0.7724, -0.4507 }   -- as lib/ShadowMap.lua hangs it

local C_GRASS = { 0.36, 0.66, 0.30 }
local C_GRASS2 = { 0.30, 0.58, 0.26 }
local C_ROAD = { 0.96, 0.94, 0.86 }
local C_PLATE = { 0.84, 0.82, 0.76 }
local C_SAND = { 0.90, 0.84, 0.62 }
local C_SEABED = { 0.52, 0.66, 0.60 }
local C_ROCK = { 0.72, 0.64, 0.54 }
local C_ROCK2 = { 0.56, 0.49, 0.42 }
local C_SNOW = { 0.96, 0.97, 1.00 }
local C_FOREST = { 0.16, 0.40, 0.20 }
local C_TRUNK = { 0.40, 0.28, 0.18 }
local C_CRATER = { 0.86, 0.30, 0.16 }
local C_WALL = { 0.93, 0.91, 0.86 }
local C_WINDOW = { 1.00, 0.90, 0.55 }

-- A town is named after its colour, and the diorama takes the game at its
-- word: the roofs of each town are the colour on the sign.
local TOWN_COLOR = {
  ["PALLET TOWN"] = { 0.94, 0.94, 0.92 },
  ["VIRIDIAN CITY"] = { 0.34, 0.68, 0.36 },
  ["PEWTER CITY"] = { 0.56, 0.58, 0.60 },
  ["CERULEAN CITY"] = { 0.30, 0.56, 0.92 },
  ["VERMILION CITY"] = { 0.92, 0.42, 0.20 },
  ["LAVENDER TOWN"] = { 0.70, 0.56, 0.86 },
  ["CELADON CITY"] = { 0.58, 0.82, 0.62 },
  ["SAFFRON CITY"] = { 0.96, 0.78, 0.22 },
  ["FUCHSIA CITY"] = { 0.92, 0.36, 0.66 },
  ["CINNABAR ISLAND"] = { 0.86, 0.22, 0.20 },
  ["INDIGO PLATEAU"] = { 0.32, 0.30, 0.62 },
}

-- The gyms, and what they hand over. The badge ids are the inventory's own
-- (see lib/WorldMapQuest.lua for why a badge is an item).
local GYMS = {
  ["PEWTER CITY"] = { leader = "BROCK", badge = "BOULDERBADGE", name = "BOULDER BADGE" },
  ["CERULEAN CITY"] = { leader = "MISTY", badge = "CASCADEBADGE", name = "CASCADE BADGE" },
  ["VERMILION CITY"] = { leader = "LT. SURGE", badge = "THUNDERBADGE", name = "THUNDER BADGE" },
  ["CELADON CITY"] = { leader = "ERIKA", badge = "RAINBOWBADGE", name = "RAINBOW BADGE" },
  ["FUCHSIA CITY"] = { leader = "KOGA", badge = "SOULBADGE", name = "SOUL BADGE" },
  ["SAFFRON CITY"] = { leader = "SABRINA", badge = "MARSHBADGE", name = "MARSH BADGE" },
  ["CINNABAR ISLAND"] = { leader = "BLAINE", badge = "VOLCANOBADGE", name = "VOLCANO BADGE" },
  ["VIRIDIAN CITY"] = { leader = "GIOVANNI", badge = "EARTHBADGE", name = "EARTH BADGE" },
}

-- What a location IS, for the card, keyed on the name the engine gives it.
local KIND = {
  ["MT.MOON"] = "cave", ["ROCK TUNNEL"] = "cave", ["VICTORY ROAD"] = "cave",
  ["DIGLETT's CAVE"] = "cave", ["SEAFOAM ISLANDS"] = "cave",
  ["VIRIDIAN FOREST"] = "forest", ["SAFARI ZONE"] = "park",
  ["POWER PLANT"] = "building", ["POKéMON TOWER"] = "building",
  ["S.S.ANNE"] = "ship", ["SEA COTTAGE"] = "building",
  ["INDIGO PLATEAU"] = "league",
}

-- ---------------------------------------------------------------- strings
local STRINGS = {
  objective = "OBJECTIVE",
  next = "NEXT",
  badges = "BADGES",
  you = "YOU",
  target = "GO HERE",
  visited = "VISITED",
  unvisited = "NOT YET VISITED",
  flyOk = "FLY: AVAILABLE",
  flyNo = "FLY: NOT YET",
  gym = "GYM",
  beaten = "BADGE EARNED",
  unbeaten = "BADGE NOT EARNED",
  center = "POKéMON CENTER",
  mart = "POKé MART",
  hintView = "D-PAD  MOVE     A  ZOOM     SELECT  VIEW     B  CLOSE",
  hintFly = "UP/DOWN  DESTINATION     A  FLY     B  CANCEL",
  hintNest = "A / B  CLOSE",
  nest = "'s NEST",
  noNest = " AREA UNKNOWN",
  to = "To ",
  building = "BUILDING KANTO...",
  classic = "CLASSIC MAP",
  north = "N",
  kinds = {
    town = "TOWN", city = "CITY", route = "ROUTE", sea = "SEA ROUTE",
    cave = "CAVE", forest = "FOREST", park = "SAFARI ZONE",
    building = "LANDMARK", ship = "SHIP", league = "POKéMON LEAGUE",
  },
}

-- ---------------------------------------------------------------- state
local R = nil          -- the built region, or nil
local build = nil      -- the in-progress build
local failed = false
local activeGame = nil
local quest, questTarget, questPath = nil, nil, nil
local clock = 0
local lastSel, lastTime, lastScreen = nil, nil, nil

local function log(msg)
  if V.mod and V.mod.log then V.mod.log:info("worldmap: " .. tostring(msg)) end
end

-- ---------------------------------------------------------------- helpers
local function hash2(ix, iy)
  local s = math.sin(ix * 12.9898 + iy * 78.233) * 43758.5453
  return s - math.floor(s)
end

-- value noise, 0..1, lattice spacing `cell`
local function noise2(x, y, cell)
  local fx, fy = x / cell, y / cell
  local ix, iy = math.floor(fx), math.floor(fy)
  local tx, ty = fx - ix, fy - iy
  tx = tx * tx * (3 - 2 * tx)
  ty = ty * ty * (3 - 2 * ty)
  local a, b = hash2(ix, iy), hash2(ix + 1, iy)
  local c, d = hash2(ix, iy + 1), hash2(ix + 1, iy + 1)
  local top = a + (b - a) * tx
  local bot = c + (d - c) * tx
  return top + (bot - top) * ty
end

local function fbm(x, y)
  return noise2(x, y, 9) * 0.55 + noise2(x + 41, y + 17, 4.5) * 0.30
         + noise2(x + 7, y + 91, 2.2) * 0.15
end

local function clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

local function lerp3(a, b, t)
  return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t,
           a[3] + (b[3] - a[3]) * t }
end

local function scale3(c, k) return { c[1] * k, c[2] * k, c[3] * k } end

-- ============================================================================
-- 1. READING THE CLASSIC MAP
-- ============================================================================

local function townMapData()
  local Game = require("src.core.Game")
  local field = Game.data and Game.data.field
  local tm = field and field.townMap
  if type(tm) ~= "table" then return nil end
  local bg = tm.background
  local map = bg and bg.map
  if type(map) ~= "table" or #map < COLS * ROWS then return nil end
  local locs = tm.locations or tm
  return map, locs, bg
end

-- What a location is, once it has a name: the card's kind, the town's
-- colour, its gym, and whether the maps that share its square include a
-- Center or a Mart.
local function classify(out)
  for _, L in ipairs(out) do
    table.sort(L.maps)
    local n = L.name
    if KIND[n] then L.kind = KIND[n]
    elseif n:find("SEA ROUTE", 1, true) then L.kind = "sea"
    elseif n:find("ROUTE", 1, true) then L.kind = "route"
    elseif n:find("CITY", 1, true) then L.kind = "city"
    elseif n:find("TOWN", 1, true) then L.kind = "town"
    else L.kind = "building" end
    L.color = TOWN_COLOR[n]
    L.gym = GYMS[n]
    for _, id in ipairs(L.maps) do
      if id:find("POKECENTER", 1, true) then L.hasCenter = true end
      if id:find("_MART", 1, true) then L.hasMart = true end
    end
  end
  return out
end

-- The locations as the SCREEN lists them. A plain viewer is built and read,
-- because the engine's own dedupe is the authority on what counts as a
-- place -- reading the raw entries gave 65 where the screen shows 47, and
-- three "ROUTE 12" plates stacked on one square. The constructor is the one
-- this file wraps, which is harmless: it re-captures the same game.
local function screenLocations()
  local okT, TownMap = pcall(require, "src.ui.TownMap")
  if not (okT and TownMap and TownMap.new and activeGame) then return nil end
  local okN, scr = pcall(TownMap.new, activeGame)
  if not (okN and type(scr) == "table" and scr.mode == "grid"
          and type(scr.locs) == "table" and #scr.locs > 0) then return nil end
  local out, byObj = {}, {}
  for _, loc in ipairs(scr.locs) do
    if loc.x and loc.y then
      local L = { name = loc.name, gx = loc.x, gy = loc.y, maps = {},
                  tx = loc.x + GRID_DX, ty = loc.y + GRID_DY }
      L.wx = (L.tx + 0.5) * SUB
      L.wz = (L.ty + 0.5) * SUB
      out[#out + 1] = L
      byObj[loc] = L
    end
  end
  for mapId, loc in pairs(scr.byMap or {}) do
    local L = byObj[loc]
    if L then L.maps[#L.maps + 1] = tostring(mapId) end
  end
  return classify(out)
end

-- The fallback: the raw entries, deduped by name and square.
local function readLocations(locs)
  local out, seen = {}, {}
  for mapId, e in pairs(locs) do
    if type(e) == "table" then
      local c = e.coords or e
      local x, y = tonumber(c.x or c.col), tonumber(c.y or c.row)
      local name = e.name or e.label or tostring(mapId):gsub("_", " ")
      if x and y then
        local key = name .. ":" .. x .. ":" .. y
        local L = seen[key]
        if not L then
          L = { name = name, gx = x, gy = y, maps = {},
                tx = x + GRID_DX, ty = y + GRID_DY }
          L.wx = (L.tx + 0.5) * SUB
          L.wz = (L.ty + 0.5) * SUB
          seen[key] = L
          out[#out + 1] = L
        end
        L.maps[#L.maps + 1] = tostring(mapId)
      end
    end
  end
  table.sort(out, function(a, b)
    if a.gy ~= b.gy then return a.gy < b.gy end
    if a.gx ~= b.gx then return a.gx < b.gx end
    return a.name < b.name
  end)
  return classify(out)
end

-- ============================================================================
-- 2. THE BUILD
-- ============================================================================
--
-- A coroutine, resumed once a frame until it is done, behind a progress
-- bar. The whole thing is a few hundred milliseconds; sliced so the frame
-- it lands on is not a hitch.
WorldMap3D.BUILD_MS = 8

local function tileAt(map, tx, ty)
  if tx < 0 or ty < 0 or tx >= COLS or ty >= ROWS then return T_SEA end
  if ty == 0 then return T_SEA end        -- row 0 is under the name banner
  return map[ty * COLS + tx + 1] or T_SEA
end

-- is this sub-cell of a tile land? Coast tiles are split on the diagonal,
-- with the land on the side the sheet paints grey.
local function landIn(t, sx, sy)
  if t == T_SEA or t == T_SEAROUTE_END or t == T_SEAROUTE_H
     or t == T_SEAROUTE_V then return false end
  if t == T_COAST_BL then return sy >= sx end        -- land bottom-left
  if t == T_COAST_BR then return sx + sy >= SUB - 1 end
  if t == T_COAST_TR then return sx >= sy end        -- land top-right
  if t == T_COAST_TL then return sx + sy <= SUB - 1 end
  return true
end

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

    build.phase = STRINGS.building
    local map, locsRaw = townMapData()
    if not map then error("no classic town map data on this build", 0) end
    local locs = screenLocations() or readLocations(locsRaw)
    if #locs == 0 then error("no town map locations", 0) end
    local byName = {}
    for _, L in ipairs(locs) do byName[L.name] = L end

    ---------------------------------------------------------- the cells
    -- kind, land mask and the tile each cell came from, at SUB resolution
    local n = GW * GH
    local kind, land = {}, {}
    for gz = 0, GH - 1 do
      local ty, sy = math.floor(gz / SUB), gz % SUB
      for gx = 0, GW - 1 do
        local tx, sx = math.floor(gx / SUB), gx % SUB
        local t = tileAt(map, tx, ty)
        local i = gz * GW + gx + 1
        local isLand = landIn(t, sx, sy)
        -- the picture's frame is a coast: where the artists ran the land to
        -- the edge (west of the Plateau, the north) the diorama has to end
        -- in water, not in a wall
        if gx == 0 or gz == 0 or gx == GW - 1 or gz == GH - 1 then isLand = false end
        land[i] = isLand
        if not isLand then kind[i] = K_SEA
        elseif t == T_ROAD then kind[i] = K_ROAD
        elseif t == T_TOWN then kind[i] = K_TOWN
        elseif t == T_CAVE then kind[i] = K_CAVE
        else kind[i] = K_LAND end
      end
      breathe()
    end
    build.done = 1

    ------------------------------------------------- the coast, softened
    -- Signed distance to the coast, in cells: two chamfer passes over the
    -- land mask, once for the land and once for the sea. Everything about
    -- the shore -- the beach ring, the slope into the water, how far out the
    -- foam and the shallows reach -- is a function of this one field.
    local INF = 1e9
    local function chamfer(inside)
      local d = {}
      for i = 1, n do d[i] = inside(i) and INF or 0 end
      for gz = 0, GH - 1 do
        for gx = 0, GW - 1 do
          local i = gz * GW + gx + 1
          if d[i] > 0 then
            local best = d[i]
            if gx > 0 then best = math.min(best, d[i - 1] + 1) end
            if gz > 0 then
              best = math.min(best, d[i - GW] + 1)
              if gx > 0 then best = math.min(best, d[i - GW - 1] + 1.414) end
              if gx < GW - 1 then best = math.min(best, d[i - GW + 1] + 1.414) end
            end
            d[i] = best
          end
        end
      end
      for gz = GH - 1, 0, -1 do
        for gx = GW - 1, 0, -1 do
          local i = gz * GW + gx + 1
          if d[i] > 0 then
            local best = d[i]
            if gx < GW - 1 then best = math.min(best, d[i + 1] + 1) end
            if gz < GH - 1 then
              best = math.min(best, d[i + GW] + 1)
              if gx < GW - 1 then best = math.min(best, d[i + GW + 1] + 1.414) end
              if gx > 0 then best = math.min(best, d[i + GW - 1] + 1.414) end
            end
            d[i] = best
          end
        end
      end
      return d
    end
    local dLand = chamfer(function(i) return land[i] end)
    breathe()
    local dSea = chamfer(function(i) return not land[i] end)
    breathe()
    -- signed: positive inland, negative at sea
    local sdf = {}
    for i = 1, n do sdf[i] = land[i] and dLand[i] or -dSea[i] end
    -- and the coast wanders a little, so a tile edge is not a ruler line:
    -- the distance field shifts by a slow noise, which moves the zero
    -- crossing by up to ~1.4 cells without ever moving a town off its land
    for gz = 0, GH - 1 do
      for gx = 0, GW - 1 do
        local i = gz * GW + gx + 1
        sdf[i] = sdf[i] + (noise2(gx, gz, 6.5) - 0.5) * 2.8
      end
    end
    breathe()
    build.done = 2

    ------------------------------------------------- landmarks and peaks
    -- What stands where, by the location's own square. The cave marks in
    -- the picture are mountains except where the name says otherwise.
    local peaks, forests, knolls, volcano = {}, {}, {}, nil
    for _, L in ipairs(locs) do
      local nm = L.name
      if nm == "MT.MOON" or nm == "ROCK TUNNEL" or nm == "VICTORY ROAD" then
        peaks[#peaks + 1] = { x = L.wx, z = L.wz, h = PEAK_H, r = PEAK_R, L = L }
      elseif nm == "VIRIDIAN FOREST" then
        forests[#forests + 1] = { x = L.wx, z = L.wz, r = 7.5, L = L }
      elseif nm == "SAFARI ZONE" then
        forests[#forests + 1] = { x = L.wx, z = L.wz, r = 5.5, L = L, sparse = true }
      elseif nm == "DIGLETT's CAVE" then
        knolls[#knolls + 1] = { x = L.wx, z = L.wz, h = KNOLL_H, r = 4.0 }
      elseif nm == "SEAFOAM ISLANDS" then
        knolls[#knolls + 1] = { x = L.wx - 2, z = L.wz + 1, h = 2.2, r = 3.0 }
        knolls[#knolls + 1] = { x = L.wx + 2.5, z = L.wz - 1.5, h = 1.6, r = 2.4 }
      elseif nm == "CINNABAR ISLAND" then
        -- the volcano stands on the land tile west of the town square
        volcano = { x = L.wx - SUB, z = L.wz, h = 6.5, r = 6.0 }
      elseif nm == "INDIGO PLATEAU" then
        knolls[#knolls + 1] = { x = L.wx, z = L.wz, h = 1.6, r = 6.5, flat = true }
      end
    end

    local function peakAt(px, pz)
      local h, rock = 0, 0
      for _, p in ipairs(peaks) do
        local dx, dz = px - p.x, pz - p.z
        local d = math.sqrt(dx * dx + dz * dz)
        if d < p.r then
          local t = 1 - d / p.r
          -- ridged: two cones offset, so the mass has a saddle and a summit
          local ridge = 1 - math.abs(noise2(px * 0.7, pz * 0.7, 5) - 0.5) * 2
          local v = p.h * (t * t * (0.72 + 0.28 * ridge))
          if v > h then h = v end
          -- rock from a third of the way up; the foot stays grass
          rock = math.max(rock, clamp((t - 0.30) * 2.2, 0, 1))
        end
      end
      if volcano then
        local dx, dz = px - volcano.x, pz - volcano.z
        local d = math.sqrt(dx * dx + dz * dz)
        if d < volcano.r then
          local t = 1 - d / volcano.r
          local v = volcano.h * t * t
          if d < 1.6 then v = v - (1.6 - d) * 1.4 end   -- the crater
          if v > h then h = v end
          rock = math.max(rock, clamp((t - 0.25) * 2.4, 0, 1))
        end
      end
      for _, k in ipairs(knolls) do
        local dx, dz = px - k.x, pz - k.z
        local d = math.sqrt(dx * dx + dz * dz)
        if d < k.r then
          local t = 1 - d / k.r
          local v = k.flat and (k.h * clamp(t * 2.2, 0, 1)) or (k.h * t * t)
          if v > h then h = v end
          if not k.flat then rock = math.max(rock, t * 0.9) end
        end
      end
      return h, rock
    end

    ----------------------------------------------------- heights and colour
    local H, C = {}, {}
    -- distance to the nearest road/town cell, for the road ribbon's soft
    -- edge and to keep hills and trees off the streets
    local dRoad = chamfer(function(i)
      return kind[i] ~= K_ROAD and kind[i] ~= K_TOWN and kind[i] ~= K_CAVE
    end)
    breathe()
    local townCol = {}
    for _, L in ipairs(locs) do
      if L.color then townCol[L.ty * COLS + L.tx] = L.color end
    end
    for gz = 0, GH - 1 do
      for gx = 0, GW - 1 do
        local i = gz * GW + gx + 1
        local s = sdf[i]
        local px, pz = gx + 0.5, gz + 0.5
        local col, y
        if s <= 0 then
          -- the seabed: a beach slope for the first cells out, then the
          -- terraced floor lib/Water.lua's own bed has
          local shelf = clamp(-s / 6.0, 0, 1)
          y = (LAND_Y - 0.9) + shelf * (SEABED_Y - (LAND_Y - 0.9))
          col = lerp3(C_SAND, C_SEABED, shelf)
        else
          local inland = clamp(s / 4.0, 0, 1)
          -- gentle relief away from roads and towns
          local road = clamp(1 - dRoad[i] / 3.0, 0, 1)
          local relief = (fbm(px, pz) - 0.5) * HILL_AMP * inland * (1 - road)
          y = LAND_Y + math.max(0, relief) + relief * 0.3
          local ph, rock = peakAt(px, pz)
          y = y + ph
          -- colour: grass with its own mottle, sand at the water, the road
          -- corridors white, town squares paved, rock and snow up high
          local g = lerp3(C_GRASS2, C_GRASS, noise2(px + 3, pz + 5, 7))
          col = lerp3(C_SAND, g, clamp(inland * 1.4, 0, 1))
          local k = kind[i]
          if k == K_ROAD or k == K_CAVE then
            col = lerp3(col, C_ROAD, 0.92)
          elseif k == K_TOWN then
            local tc = townCol[math.floor(gz / SUB) * COLS + math.floor(gx / SUB)]
            col = lerp3(C_PLATE, tc or C_PLATE, 0.22)
          elseif road > 0 then
            col = lerp3(col, C_ROAD, road * 0.35)
          end
          if rock > 0 then
            local rc = lerp3(C_ROCK, C_ROCK2, noise2(px * 1.3, pz * 1.3, 3))
            col = lerp3(col, rc, clamp(rock * 1.2, 0, 1))
            if ph > PEAK_H * 0.60 then
              col = lerp3(col, C_SNOW, clamp((ph - PEAK_H * 0.60) / (PEAK_H * 0.22), 0, 1))
            end
          end
          if volcano then
            local dx, dz = px - volcano.x, pz - volcano.z
            if dx * dx + dz * dz < 1.6 * 1.6 then col = C_CRATER end
          end
        end
        H[i] = y
        C[i] = col
      end
      breathe()
    end
    build.done = 3

    ------------------------------------------------------ the land mesh
    -- A quad per cell, flat-shaded from the cell's own corners: the light is
    -- baked into the colour from the slope, which is what makes a mountain
    -- read as a mass and a plain as a plain at a distance where a normal
    -- would be a rounding error.
    local function hAt(gx, gz)
      gx = clamp(gx, 0, GW - 1); gz = clamp(gz, 0, GH - 1)
      return H[gz * GW + gx + 1]
    end
    local verts, idx = {}, {}
    local q = 0
    local L1x, L1y, L1z = -SUN_RAY[1], -SUN_RAY[2], -SUN_RAY[3]
    for gz = 0, GH - 1 do
      for gx = 0, GW - 1 do
        local i = gz * GW + gx + 1
        -- corner heights, averaged from the four cells meeting there so the
        -- surface is continuous rather than a field of pillars
        local function corner(cx, cz)
          return (hAt(cx - 1, cz - 1) + hAt(cx, cz - 1) + hAt(cx - 1, cz) + hAt(cx, cz)) * 0.25
        end
        local y00, y10 = corner(gx, gz), corner(gx + 1, gz)
        local y01, y11 = corner(gx, gz + 1), corner(gx + 1, gz + 1)
        -- the cell's normal from its two diagonals
        local nx = (y00 - y10 + y01 - y11) * 0.5
        local nz = (y00 - y01 + y10 - y11) * 0.5
        local ny = 1.0
        local nl = math.sqrt(nx * nx + ny * ny + nz * nz)
        nx, ny, nz = nx / nl, ny / nl, nz / nl
        local ndl = nx * L1x + ny * L1y + nz * L1z
        local light = 0.70 + 0.40 * clamp(ndl, 0, 1)
        local c = C[i]
        local r, g, b = c[1] * light, c[2] * light, c[3] * light
        verts[#verts + 1] = { gx, y00, gz, r, g, b, 1 }
        verts[#verts + 1] = { gx + 1, y10, gz, r, g, b, 1 }
        verts[#verts + 1] = { gx + 1, y11, gz + 1, r, g, b, 1 }
        verts[#verts + 1] = { gx, y01, gz + 1, r, g, b, 1 }
        local b0 = q * 4
        idx[#idx + 1] = b0 + 1; idx[#idx + 1] = b0 + 2; idx[#idx + 1] = b0 + 3
        idx[#idx + 1] = b0 + 1; idx[#idx + 1] = b0 + 3; idx[#idx + 1] = b0 + 4
        q = q + 1
      end
      breathe()
    end
    build.done = 4

    ------------------------------------------------------ the water mesh
    -- One quad per tile over the whole picture, at the sea level, with the
    -- distance to the coast in the vertex alpha for the shader's shallows
    -- and foam. Land tiles get it too: the sheet is under the land and the
    -- depth test sorts it, which is what makes an inlet or a wandering coast
    -- read as water lapping in rather than a hole.
    local wverts, widx = {}, {}
    local wq = 0
    local function shoreN(gx, gz)
      -- past the picture's edge the sea only gets deeper: the distance to
      -- the frame is added to the edge cell's own, or the shallows of a
      -- coast that runs to the frame would stripe out to the horizon
      local ox = (gx < 0 and -gx) or (gx > GW - 1 and gx - (GW - 1)) or 0
      local oz = (gz < 0 and -gz) or (gz > GH - 1 and gz - (GH - 1)) or 0
      gx = clamp(gx, 0, GW - 1); gz = clamp(gz, 0, GH - 1)
      local s = sdf[gz * GW + gx + 1]
      return clamp((-s + math.sqrt(ox * ox + oz * oz)) / 14.0, 0, 1)
    end
    local M = 160  -- units of open sea past the picture's edge, out past the haze
    local x0, x1, z0, z1 = -M, GW + M, -M, GH + M
    local step = 8
    for z = z0, z1 - step, step do
      for x = x0, x1 - step, step do
        local a00, a10 = shoreN(x, z), shoreN(x + step, z)
        local a01, a11 = shoreN(x, z + step), shoreN(x + step, z + step)
        wverts[#wverts + 1] = { x, WorldMap3D.SEA_Y, z, 1, 1, 1, a00 }
        wverts[#wverts + 1] = { x + step, WorldMap3D.SEA_Y, z, 1, 1, 1, a10 }
        wverts[#wverts + 1] = { x + step, WorldMap3D.SEA_Y, z + step, 1, 1, 1, a11 }
        wverts[#wverts + 1] = { x, WorldMap3D.SEA_Y, z + step, 1, 1, 1, a01 }
        local b0 = wq * 4
        widx[#widx + 1] = b0 + 1; widx[#widx + 1] = b0 + 2; widx[#widx + 1] = b0 + 3
        widx[#widx + 1] = b0 + 1; widx[#widx + 1] = b0 + 3; widx[#widx + 1] = b0 + 4
        wq = wq + 1
      end
    end
    breathe()
    build.done = 5

    ---------------------------------------------------------- the props
    -- Boxes, all of them, lit by face like the voxel world is. A town is a
    -- paved square with a ring of houses in the town's colour, its Center
    -- with the red roof, its Mart with the blue one and, where there is a
    -- gym, the gym. The forest is trees; the landmarks are what they are.
    local pverts, pidx = {}, {}
    local pq = 0
    local glow = {}    -- night windows: { x, y, z, face }
    local SH = { top = 1.0, s = 0.86, e = 0.78, n = 0.62, w = 0.66 }
    local function pushQuad(list, ilist, a, b, c, d, col, k)
      local r, g, bb = col[1] * k, col[2] * k, col[3] * k
      list[#list + 1] = { a[1], a[2], a[3], r, g, bb, 1 }
      list[#list + 1] = { b[1], b[2], b[3], r, g, bb, 1 }
      list[#list + 1] = { c[1], c[2], c[3], r, g, bb, 1 }
      list[#list + 1] = { d[1], d[2], d[3], r, g, bb, 1 }
      local b0 = (#list - 4)
      ilist[#ilist + 1] = b0 + 1; ilist[#ilist + 1] = b0 + 2; ilist[#ilist + 1] = b0 + 3
      ilist[#ilist + 1] = b0 + 1; ilist[#ilist + 1] = b0 + 3; ilist[#ilist + 1] = b0 + 4
    end
    local function box(x0, y0, z0, x1, y1, z1, col, topCol)
      topCol = topCol or col
      pushQuad(pverts, pidx, { x0, y1, z0 }, { x1, y1, z0 }, { x1, y1, z1 }, { x0, y1, z1 }, topCol, SH.top)
      pushQuad(pverts, pidx, { x0, y0, z1 }, { x1, y0, z1 }, { x1, y1, z1 }, { x0, y1, z1 }, col, SH.s)
      pushQuad(pverts, pidx, { x1, y0, z0 }, { x0, y0, z0 }, { x0, y1, z0 }, { x1, y1, z0 }, col, SH.n)
      pushQuad(pverts, pidx, { x1, y0, z1 }, { x1, y0, z0 }, { x1, y1, z0 }, { x1, y1, z1 }, col, SH.e)
      pushQuad(pverts, pidx, { x0, y0, z0 }, { x0, y0, z1 }, { x0, y1, z1 }, { x0, y1, z0 }, col, SH.w)
      pq = pq + 5
    end
    local function groundY(x, z)
      return hAt(math.floor(x), math.floor(z))
    end
    local function house(x, z, w, d, hgt, roof, windows)
      local y = groundY(x, z)
      box(x - w / 2, y, z - d / 2, x + w / 2, y + hgt, z + d / 2, C_WALL)
      -- the roof: a slab a little wider than the walls, in the town's colour
      box(x - w / 2 - 0.25, y + hgt, z - d / 2 - 0.25, x + w / 2 + 0.25,
          y + hgt + 0.55, z + d / 2 + 0.25, roof, roof)
      if windows ~= false then
        glow[#glow + 1] = { x, y + hgt * 0.55, z + d / 2 + 0.02, w * 0.5 }
      end
    end
    local function tree(x, z, s)
      local y = groundY(x, z)
      s = s or 1
      box(x - 0.22 * s, y, z - 0.22 * s, x + 0.22 * s, y + 0.9 * s, z + 0.22 * s, C_TRUNK)
      local c = lerp3(C_FOREST, C_GRASS, hash2(math.floor(x * 7), math.floor(z * 3)) * 0.35)
      box(x - 0.75 * s, y + 0.8 * s, z - 0.75 * s, x + 0.75 * s, y + 1.9 * s, z + 0.75 * s, c)
      box(x - 0.45 * s, y + 1.9 * s, z - 0.45 * s, x + 0.45 * s, y + 2.5 * s, z + 0.45 * s, c)
    end
    local CENTER_ROOF = { 0.90, 0.24, 0.22 }
    local MART_ROOF = { 0.24, 0.42, 0.88 }
    local GYM_ROOF = { 0.62, 0.42, 0.20 }
    for _, L in ipairs(locs) do
      local k = L.kind
      if k == "city" or k == "town" or k == "league" then
        local cx, cz = L.wx, L.wz
        local col = L.color or C_WALL
        if k == "league" then
          -- the Plateau: one wide hall with a long roof, and two pillars
          box(cx - 3.2, groundY(cx, cz), cz - 1.6, cx + 3.2, groundY(cx, cz) + 2.6, cz + 1.6, C_WALL)
          box(cx - 3.6, groundY(cx, cz) + 2.6, cz - 2.0, cx + 3.6, groundY(cx, cz) + 3.3, cz + 2.0, col, col)
          box(cx - 3.0, groundY(cx, cz), cz + 1.8, cx - 2.4, groundY(cx, cz) + 3.0, cz + 2.4, C_WALL)
          box(cx + 2.4, groundY(cx, cz), cz + 1.8, cx + 3.0, groundY(cx, cz) + 3.0, cz + 2.4, C_WALL)
        else
          -- houses round the square, the Center and the Mart at the front
          local big = (k == "city")
          local ring = big and 6 or 4
          for i = 0, ring - 1 do
            local a = (i / ring) * math.pi * 2 + hash2(L.gx, L.gy + i) * 0.5
            local rad = big and 2.7 or 2.2
            local hx, hz = cx + math.cos(a) * rad, cz + math.sin(a) * rad * 0.8
            local hs = 0.9 + hash2(L.gx + i, L.gy) * 0.5
            house(hx, hz, 1.3 * hs, 1.2 * hs, 1.0 + hash2(i, L.gx) * 0.6, col)
          end
          if L.hasCenter then house(cx - 1.1, cz + 0.2, 1.7, 1.4, 1.3, CENTER_ROOF) end
          if L.hasMart then house(cx + 1.2, cz + 0.2, 1.5, 1.3, 1.2, MART_ROOF) end
          if L.gym then
            house(cx, cz - 1.4, 2.0, 1.5, 1.5, GYM_ROOF)
          end
          if L.name == "SAFFRON CITY" then
            -- Silph Co.: the one tower in Kanto, with a beacon on top
            local y = groundY(cx, cz)
            box(cx - 0.9, y, cz - 0.9, cx + 0.9, y + 6.0, cz + 0.9, { 0.78, 0.80, 0.86 }, { 0.62, 0.66, 0.74 })
            L.beacon = { cx, y + 6.2, cz }
            for f = 1, 5 do glow[#glow + 1] = { cx, y + f * 1.05, cz + 0.92, 1.2 } end
          end
          if L.name == "PALLET TOWN" then
            house(cx + 0.2, cz - 1.5, 2.2, 1.4, 1.2, { 0.70, 0.72, 0.76 }) -- the lab
          end
        end
      elseif L.name == "POKéMON TOWER" then
        -- the tower stands on the Lavender shore: the square it is given is
        -- a sea tile, so it goes up on the nearest land to the west
        local cx, cz = L.wx - 4.5, L.wz
        local y = groundY(cx, cz)
        for f = 0, 4 do
          local s = 1.1 - f * 0.12
          box(cx - s, y + f * 1.6, cz - s, cx + s, y + f * 1.6 + 1.3, cz + s, { 0.72, 0.62, 0.84 })
          box(cx - s - 0.2, y + f * 1.6 + 1.3, cz - s - 0.2, cx + s + 0.2, y + f * 1.6 + 1.6, cz + s + 0.2, { 0.46, 0.36, 0.60 }, { 0.46, 0.36, 0.60 })
        end
        L.pin = { cx, cz }
      elseif L.name == "POWER PLANT" then
        local cx, cz = L.wx - 2.5, L.wz - 1.5
        local y = groundY(cx, cz)
        box(cx - 2.0, y, cz - 1.2, cx + 2.0, y + 1.8, cz + 1.2, { 0.66, 0.68, 0.70 }, { 0.52, 0.56, 0.60 })
        box(cx - 1.2, y + 1.8, cz - 0.4, cx - 0.6, y + 3.6, cz + 0.2, { 0.50, 0.52, 0.55 })
        box(cx + 0.6, y + 1.8, cz - 0.4, cx + 1.2, y + 3.6, cz + 0.2, { 0.50, 0.52, 0.55 })
        L.pin = { cx, cz }
      elseif L.name == "SEA COTTAGE" then
        house(L.wx, L.wz, 1.6, 1.3, 1.1, { 0.40, 0.60, 0.90 })
      elseif L.name == "S.S.ANNE" then
        -- on the water side of its coast tile: the boat is its own mesh,
        -- drawn with a bob (see drawRegion)
        L.ship = { L.wx - 1.5, L.wz + 2.0 }
      elseif L.name == "DIGLETT's CAVE" then
        local y = groundY(L.wx, L.wz) + KNOLL_H * 0.55
        box(L.wx - 0.8, y - 0.6, L.wz + 1.0, L.wx + 0.8, y + 0.4, L.wz + 2.2, { 0.12, 0.10, 0.10 })
      elseif k == "cave" and L.name ~= "SEAFOAM ISLANDS" then
        -- a mouth on the south face of the mountain
        local cx, cz = L.wx, L.wz + PEAK_R * 0.62
        local y = groundY(cx, cz)
        box(cx - 0.8, y - 0.2, cz - 0.5, cx + 0.8, y + 1.0, cz + 0.5, { 0.22, 0.16, 0.13 })
      end
      breathe()
    end
    -- the forests: dense at Viridian, thinner and fenced at the Safari Zone
    for _, f in ipairs(forests) do
      local count = f.sparse and 22 or 46
      for i = 1, count do
        local a = hash2(i, f.L.gx) * math.pi * 2
        local rr = f.r * math.sqrt(hash2(i + 100, f.L.gy))
        local tx, tz = f.x + math.cos(a) * rr, f.z + math.sin(a) * rr * 0.85
        local ci = math.floor(tz) * GW + math.floor(tx) + 1
        if kind[ci] ~= K_SEA and kind[ci] ~= K_ROAD and kind[ci] ~= K_TOWN then
          tree(tx, tz, 0.75 + hash2(i, 9) * 0.5)
        end
      end
      if f.sparse then
        -- the Safari fence, four low rails
        local y = groundY(f.x, f.z)
        local hw, hd = f.r + 0.8, f.r * 0.85 + 0.8
        box(f.x - hw, y, f.z - hd, f.x + hw, y + 0.35, f.z - hd + 0.25, { 0.80, 0.70, 0.46 })
        box(f.x - hw, y, f.z + hd - 0.25, f.x + hw, y + 0.35, f.z + hd, { 0.80, 0.70, 0.46 })
        box(f.x - hw, y, f.z - hd, f.x - hw + 0.25, y + 0.35, f.z + hd, { 0.80, 0.70, 0.46 })
        box(f.x + hw - 0.25, y, f.z - hd, f.x + hw, y + 0.35, f.z + hd, { 0.80, 0.70, 0.46 })
      end
      breathe()
    end
    -- and scattered trees over the open land, off the roads and the towns
    -- and away from the shore, hashed so they never move
    for gz = 4, GH - 4, 3 do
      for gx = 4, GW - 4, 3 do
        local i = gz * GW + gx + 1
        if kind[i] == K_LAND and sdf[i] > 3.5 and dRoad[i] > 3.0
           and hash2(gx, gz) < 0.30 then
          local ph = peakAt(gx + 0.5, gz + 0.5)
          if ph < 0.6 then
            tree(gx + hash2(gx + 1, gz) * 2.0, gz + hash2(gx, gz + 1) * 2.0,
                 0.55 + hash2(gx + 3, gz + 3) * 0.5)
          end
        end
      end
      breathe()
    end
    build.done = 6

    ------------------------------------------------------ the sea routes
    -- The dashes the picture draws over the water, as thin decals just above
    -- the sea: a boat's line, and the only thing that says where Surf goes.
    local dverts, didx = {}, {}
    local yd = WorldMap3D.SEA_Y + 0.12
    local function dash(x0, z0, x1, z1)
      local dx, dz = x1 - x0, z1 - z0
      local len = math.sqrt(dx * dx + dz * dz)
      if len < 0.01 then return end
      local nx, nz = -dz / len * 0.45, dx / len * 0.45
      pushQuad(dverts, didx, { x0 + nx, yd, z0 + nz }, { x1 + nx, yd, z1 + nz },
               { x1 - nx, yd, z1 - nz }, { x0 - nx, yd, z0 - nz }, { 0.97, 0.98, 1.0 }, 1)
    end
    for ty = 1, ROWS - 1 do
      for tx = 0, COLS - 1 do
        local t = tileAt(map, tx, ty)
        if t == T_SEAROUTE_H or t == T_SEAROUTE_V or t == T_SEAROUTE_END then
          local cx, cz = (tx + 0.5) * SUB, (ty + 0.5) * SUB
          local horiz = (t == T_SEAROUTE_H)
            or (t == T_SEAROUTE_END and (tileAt(map, tx - 1, ty) == T_SEAROUTE_H
                or tileAt(map, tx + 1, ty) == T_SEAROUTE_H))
          for s = -1, 1 do
            if horiz then dash(cx + s * 2.7 - 0.9, cz, cx + s * 2.7 + 0.9, cz)
            else dash(cx, cz + s * 2.7 - 0.9, cx, cz + s * 2.7 + 0.9) end
          end
        end
      end
    end

    ------------------------------------------------------------ the ship
    local sverts, sidx = {}, {}
    local function sbox(x0, y0, z0, x1, y1, z1, col)
      pushQuad(sverts, sidx, { x0, y1, z0 }, { x1, y1, z0 }, { x1, y1, z1 }, { x0, y1, z1 }, col, SH.top)
      pushQuad(sverts, sidx, { x0, y0, z1 }, { x1, y0, z1 }, { x1, y1, z1 }, { x0, y1, z1 }, col, SH.s)
      pushQuad(sverts, sidx, { x1, y0, z0 }, { x0, y0, z0 }, { x0, y1, z0 }, { x1, y1, z0 }, col, SH.n)
      pushQuad(sverts, sidx, { x1, y0, z1 }, { x1, y0, z0 }, { x1, y1, z0 }, { x1, y1, z1 }, col, SH.e)
      pushQuad(sverts, sidx, { x0, y0, z0 }, { x0, y0, z1 }, { x0, y1, z1 }, { x0, y1, z0 }, col, SH.w)
    end
    -- built about the origin; placed at draw time
    sbox(-2.4, -0.3, -0.8, 2.4, 0.5, 0.8, { 0.94, 0.94, 0.96 })
    sbox(-1.4, 0.5, -0.5, 1.2, 1.2, 0.5, { 0.98, 0.98, 1.0 })
    sbox(-0.2, 1.2, -0.25, 0.5, 2.0, 0.25, { 0.90, 0.30, 0.24 })
    sbox(0.0, 1.9, -0.18, 0.4, 2.2, 0.18, { 0.20, 0.20, 0.22 })

    ----------------------------------------------------------- the meshes
    local function mesh(vs, is, usage)
      if #vs == 0 then return nil end
      local ok, m = pcall(love.graphics.newMesh,
        { { "VertexPosition", "float", 3 }, { "VertexColor", "float", 4 } },
        vs, "triangles", usage or "static")
      if not ok then error("mesh: " .. tostring(m), 0) end
      if #is > 0 then m:setVertexMap(is) end
      return m
    end
    local landMesh = mesh(verts, idx)
    breathe()
    local water = mesh(wverts, widx)
    local props = mesh(pverts, pidx)
    local dashes = mesh(dverts, didx)
    local ship = mesh(sverts, sidx)
    breathe()

    -- the night windows, as a mesh of small squares facing south
    local gverts, gidx = {}, {}
    for _, g in ipairs(glow) do
      local x, y, z, w = g[1], g[2], g[3], g[4]
      local hw = math.min(0.40, w * 0.42)
      pushQuad(gverts, gidx, { x - hw, y - 0.22, z }, { x + hw, y - 0.22, z },
               { x + hw, y + 0.22, z }, { x - hw, y + 0.22, z }, C_WINDOW, 1)
    end
    local windows = mesh(gverts, gidx)

    -- the road graph, for the objective's route: a tile is walkable if the
    -- picture drew a road, a town, a cave mark or a sea route on it
    local walk = {}
    for ty = 1, ROWS - 1 do
      for tx = 0, COLS - 1 do
        local t = tileAt(map, tx, ty)
        walk[ty * COLS + tx] = (t == T_ROAD or t == T_TOWN or t == T_CAVE
          or t == T_SEAROUTE_H or t == T_SEAROUTE_V or t == T_SEAROUTE_END)
      end
    end

    R = {
      locs = locs, byName = byName, map = map, walk = walk,
      landMesh = landMesh, waterMesh = water, propsMesh = props,
      dashMesh = dashes, shipMesh = ship, windowMesh = windows,
      H = H, sdf = sdf, hAt = hAt,
      landVerts = #verts, propVerts = #pverts, waterVerts = #wverts,
      ms = (os.clock() - t0) * 1000,
      peaks = #peaks,
    }
    for _, L in ipairs(locs) do
      -- where a pin stands: on the ground of its square (or where the prop
      -- was put), plus the prop's own height for the landmarks
      local px, pz = L.wx, L.wz
      if L.pin then px, pz = L.pin[1], L.pin[2] end
      if L.ship then px, pz = L.ship[1], L.ship[2] end
      L.px, L.pz = px, pz
      local gy = hAt(math.floor(px), math.floor(pz))
      if L.kind == "cave" and L.name ~= "SEAFOAM ISLANDS" and L.name ~= "DIGLETT's CAVE" then
        gy = gy + PEAK_H * 0.9
      end
      L.py = math.max(gy, WorldMap3D.SEA_Y) + 0.4
    end
  end)
end

-- ============================================================================
-- 3. THE SHADERS
-- ============================================================================

local LAND_VS = [[
extern mat4 mvp;
varying vec3 vWorldPos;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vWorldPos = vertex_position.xyz;
  return mvp * vec4(vertex_position.xyz, 1.0);
}
]]

-- Fog by distance, the hour's tint, and CLOUD SHADOWS: a tiling noise
-- sheet (built in Lua, see cloudTexture) scrolled over the ground, which is
-- what makes a still diorama read as a place with weather over it.
local LAND_FS = [[
extern vec3 camPos;
extern vec2 fogRange;
extern vec3 fogColor;
extern vec3 sunTint;
extern Image clouds;
extern vec2 cloudDrift;
extern float cloudAmt;
extern float night;
varying vec3 vWorldPos;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  float d = distance(vWorldPos, camPos);
  float f = clamp((d - fogRange.x) / max(0.001, fogRange.y - fogRange.x), 0.0, 1.0);
  vec3 c = color.rgb;
  float cl = Texel(clouds, vWorldPos.xz * 0.011 + cloudDrift).r;
  float shade = 1.0 - cloudAmt * smoothstep(0.52, 0.80, cl);
  c *= shade;
  c *= sunTint;
  // the night is blue, not black: what moonlight does to a diorama
  c = mix(c, c * vec3(0.55, 0.62, 0.95), night * 0.7);
  c = mix(c, fogColor, f * f * 0.70);
  return vec4(c, 1.0);
}
]]

-- lib/Water.lua's surface, ported by the first cut and kept: three wave
-- trains, the analytic normal, Beer-Lambert shallows, Fresnel sky, the
-- quantised glint and a lapping foam ring at the coast. Its units are world
-- PIXELS; a world unit here is a Game Boy pixel of the picture, so a unit is
-- scaled by 8 to give the trains a wavelength that reads at this zoom.
local WATER_VS = [[
extern mat4 mvp;
extern float time;
extern float swellAmp;
varying vec3 vWorldPos;
varying vec2 vPx;
varying float vShoreN;
varying float vH;
varying vec3 vN;
const vec2 KA = vec2(0.05040, 0.02736);
const vec2 KB = vec2(-0.02232, 0.04176);
const vec2 KC = vec2(0.10763, -0.14825);
const vec3 RATE = vec3(1.0, 0.90867, 1.78730);
const float STEEP = 0.22;
vec3 waveMix(float size) {
  float hi = clamp(size, 0.0, 1.0);
  vec3 w = vec3(0.55 * (0.10 + 0.90 * hi), 0.45, 0.55 * (1.0 - hi));
  return w / max(w.x + w.y + w.z, 1e-6);
}
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vec3 w = vertex_position.xyz;
  vPx = w.xz * 8.0;
  vShoreN = VertexColor.a;
  float size = clamp(vShoreN * 1.6, 0.0, 1.0);
  vec3 wmix = waveMix(size);
  vec3 ph = time * 0.55 * RATE;
  vec3 ang = vec3(dot(vPx, KA) - ph.x, dot(vPx, KB) + ph.y, dot(vPx, KC) - ph.z);
  float h = sin(ang.x) * wmix.x + sin(ang.y) * wmix.y + sin(ang.z) * wmix.z;
  float ah = abs(h);
  h = h + STEEP * h * ah;
  vH = h;
  float sc = 1.0 + 2.0 * STEEP * ah;
  vec2 g = (cos(ang.x) * wmix.x * KA + cos(ang.y) * wmix.y * KB + cos(ang.z) * wmix.z * KC) * sc;
  vN = normalize(vec3(-g.x * swellAmp, 1.0, -g.y * swellAmp));
  w.y += swellAmp * h / 8.0;
  vWorldPos = w;
  return mvp * vec4(w, 1.0);
}
]]

local WATER_FS = [[
extern vec3 camPos;
extern vec2 fogRange;
extern vec3 fogColor;
extern vec3 sunTint;
extern vec3 skyColor;
extern vec3 sunRay;
extern float time;
extern float swellAmp;
extern float near;
extern float night;
varying vec3 vWorldPos;
varying vec2 vPx;
varying float vShoreN;
varying float vH;
varying vec3 vN;
const vec3 SAND      = vec3(0.92, 0.86, 0.66);
const vec3 ABSORB    = vec3(0.220, 0.090, 0.030);
const vec3 DEEP_TINT = vec3(0.42, 0.58, 0.92);
const vec3 FOAM      = vec3(0.93, 0.97, 1.00);
const vec3 TILE_BLUE = vec3(0.26, 0.52, 0.86);
const float STEEP = 0.22;
const vec3 WAVE_K = vec3(0.05735, 0.04735, 0.18319);
vec3 waveMix(float size) {
  float hi = clamp(size, 0.0, 1.0);
  vec3 w = vec3(0.55 * (0.10 + 0.90 * hi), 0.45, 0.55 * (1.0 - hi));
  return w / max(w.x + w.y + w.z, 1e-6);
}
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  float d = distance(vWorldPos, camPos);
  float fog = clamp((d - fogRange.x) / max(0.001, fogRange.y - fogRange.x), 0.0, 1.0);
  vec2 gc = floor(sc / 2.0);
  float check = mod(gc.x + gc.y, 2.0);
  float dfar = 1.0 - fog;
  float detail = near * dfar * dfar;
  float shore = vShoreN * 14.0;              // cells from the coast
  float deep = clamp(shore / 7.0, 0.0, 1.0);
  float size = clamp(vShoreN * 1.6, 0.0, 1.0);
  float terrace = clamp(floor(shore / 2.0), 0.0, 4.0);
  float depthPx = 5.0 + terrace * 2.0;
  vec3 through = SAND * exp(-ABSORB * depthPx);
  vec3 body = mix(TILE_BLUE, TILE_BLUE * DEEP_TINT, deep);
  float alpha = mix(0.18, 0.66, deep);
  vec3 c = mix(through, body, alpha);
  vec3 V = normalize(camPos - vWorldPos);
  float f1 = 1.0 - clamp(dot(vN, V), 0.0, 1.0);
  float f2 = f1 * f1;
  float reflW = clamp((0.04 + 0.96 * f2 * f2) * 0.85, 0.0, 1.0);
  c = mix(c, skyColor, reflW);
  float h = vH + (check - 0.5) * 0.16;
  float band = -step(h, -0.35) * 0.06 + step(0.30, h) * 0.05 + step(0.60, h) * 0.05;
  c *= 1.0 + band * detail;
  vec3 wmix = waveMix(size);
  float ah = abs(vH);
  float gradMax = dot(wmix, WAVE_K) * (1.0 + 2.0 * STEEP * ah);
  float devMax = max(swellAmp * gradMax * length(sunRay.xz), 1e-5);
  float flatDot = -sunRay.y;
  float sg = smoothstep(flatDot + 0.34 * devMax, flatDot + 1.0 * devMax, dot(vN, -sunRay));
  sg = floor(sg * 4.0 + 0.5) / 4.0;
  c = mix(c, FOAM, sg * 0.55 * detail * (1.0 - night * 0.8));
  // the foam ring at the coast, lapping on its own clock
  float lap = 0.55 * sin(time * 1.8 + vPx.x * 0.021 + vPx.y * 0.016);
  float ring = step(shore, 1.25 + lap + (check - 0.5) * 0.4);
  c = mix(c, FOAM, ring * 0.7);
  c *= sunTint;
  c = mix(c, c * vec3(0.45, 0.55, 0.95), night * 0.75);
  c = mix(c, fogColor, fog * fog * 0.70);
  return vec4(c, 1.0);
}
]]

local FLAT_VS = [[
extern mat4 mvp;
extern vec3 offset;
varying vec3 vWorldPos;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vec3 w = vertex_position.xyz + offset;
  vWorldPos = w;
  return mvp * vec4(w, 1.0);
}
]]

local FLAT_FS = [[
extern vec3 camPos;
extern vec2 fogRange;
extern vec3 fogColor;
extern vec3 sunTint;
extern float night;
extern float alpha;
extern float unlit;
varying vec3 vWorldPos;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  float d = distance(vWorldPos, camPos);
  float f = clamp((d - fogRange.x) / max(0.001, fogRange.y - fogRange.x), 0.0, 1.0);
  vec3 c = color.rgb;
  if (unlit < 0.5) {
    c *= sunTint;
    c = mix(c, c * vec3(0.55, 0.62, 0.95), night * 0.7);
  }
  c = mix(c, fogColor, f * f * 0.70 * (1.0 - unlit));
  return vec4(c, color.a * alpha);
}
]]

-- The classic picture's four shades, mapped to the Super Game Boy's TOWNMAP
-- palette the way the engine's own PaletteFX does it -- measured off the
-- engine's screen: white, the sky blue, the grass green, the ink.
local INSET_FS = [[
extern vec3 c0; extern vec3 c1; extern vec3 c2; extern vec3 c3;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 t = Texel(tex, tc);
  float l = t.r;
  vec3 c = (l > 0.85) ? c0 : ((l > 0.55) ? c1 : ((l > 0.25) ? c2 : c3));
  return vec4(c, t.a) * color;
}
]]
local INSET_PAL = {
  { 1.0, 1.0, 1.0 }, { 0.0, 0.678, 1.0 }, { 0.322, 0.902, 0.0 }, { 0.03, 0.03, 0.03 },
}

local shaders = { tried = false }
local function ensureShaders()
  if shaders.tried then return shaders.land ~= nil end
  shaders.tried = true
  local ok1, s1 = pcall(love.graphics.newShader, LAND_FS, LAND_VS)
  local ok2, s2 = pcall(love.graphics.newShader, WATER_FS, WATER_VS)
  local ok3, s3 = pcall(love.graphics.newShader, FLAT_FS, FLAT_VS)
  local ok4, s4 = pcall(love.graphics.newShader, INSET_FS)
  if not ok1 then log("land shader: " .. tostring(s1)) end
  if not ok2 then log("water shader: " .. tostring(s2)) end
  if not ok3 then log("flat shader: " .. tostring(s3)) end
  if not ok4 then log("inset shader: " .. tostring(s4)) end
  shaders.land = ok1 and s1 or nil
  shaders.water = ok2 and s2 or nil
  shaders.flat = ok3 and s3 or nil
  shaders.inset = ok4 and s4 or nil
  return shaders.land ~= nil
end

-- the cloud sheet: tiling value noise, 64x64, built once
local cloudImg = nil
local function cloudTexture()
  if cloudImg ~= nil then return cloudImg or nil end
  local S = 64
  local ok, data = pcall(love.image.newImageData, S, S)
  if not ok or not data then cloudImg = false return nil end
  local function tn(x, y, L, salt)
    local fx, fy = x / L, y / L
    local ix, iy = math.floor(fx), math.floor(fy)
    local tx, ty = fx - ix, fy - iy
    tx = tx * tx * (3 - 2 * tx); ty = ty * ty * (3 - 2 * ty)
    local P = S / L
    local function h(a, b) return hash2((a % P) + salt, (b % P) + salt * 3) end
    local a, b = h(ix, iy), h(ix + 1, iy)
    local c, d = h(ix, iy + 1), h(ix + 1, iy + 1)
    local top = a + (b - a) * tx
    local bot = c + (d - c) * tx
    return top + (bot - top) * ty
  end
  pcall(data.mapPixel, data, function(x, y)
    local v = tn(x, y, 32, 1) * 0.5 + tn(x, y, 16, 2) * 0.3 + tn(x, y, 8, 3) * 0.2
    return v, v, v, 1
  end)
  local okI, img = pcall(love.graphics.newImage, data)
  if not (okI and img) then cloudImg = false return nil end
  pcall(img.setWrap, img, "repeat", "repeat")
  pcall(img.setFilter, img, "linear", "linear")
  cloudImg = img
  return img
end

-- ============================================================================
-- 4. THE CAMERA
-- ============================================================================
--
-- North is up; the region is tilted toward the viewer and never rotated off
-- north on its own. Two framings: the whole of Kanto, and a place.
local FOV = 0.62
local cam = {
  fx = GW * 0.5, fz = GH * 0.5, dist = 260, pitch = 0.95,
  tfx = GW * 0.5, tfz = GH * 0.5, tdist = 260, tpitch = 0.95,
  yaw = 0, wide = true, top = false, drift = 0, eye = { 0, 0, 0 }, mvp = nil,
  near = 300, far = 900,
}

local function approach(a, b, rate, dt)
  local k = 1 - math.exp(-rate * dt)
  return a + (b - a) * k
end

local function fitDistance(pitch)
  local w, h = love.graphics.getDimensions()
  local aspect = w / math.max(1, h)
  local half = math.tan(FOV * 0.5)
  local dw = (GW * 0.56) / (half * aspect)
  local dh = (GH * 0.62 * (0.55 + 0.45 * math.sin(pitch))) / half
  return math.max(dw, dh)
end

local function frameWhole()
  cam.wide = true
  cam.tfx, cam.tfz = GW * 0.46, GH * 0.46
  cam.tpitch = cam.top and 1.45 or 0.95
  cam.tdist = fitDistance(cam.tpitch) * (cam.top and 0.92 or 1.04)
end

local function frameOn(x, z)
  cam.wide = false
  cam.tfx, cam.tfz = x, z + 4
  cam.tpitch = cam.top and 1.40 or 0.72
  cam.tdist = 62
end

local function eyeFor(cx, cz, dist, pitch, yaw)
  local ch = math.cos(pitch)
  return { cx + math.sin(yaw) * ch * dist, math.sin(pitch) * dist,
           cz + math.cos(yaw) * ch * dist }
end

local function viewProjection(cx, cz, dist, pitch, yaw)
  local w, h = love.graphics.getDimensions()
  local proj = Mat4.perspective(FOV, w / math.max(1, h), 1.0, math.max(dist * 6, 2000))
  -- clip-space Y is flipped for LOVE's Y-down canvas; see lib/Voxel3D.lua
  proj = Mat4.mul(Mat4.scale(1, -1, 1), proj)
  local view = Mat4.lookAt(eyeFor(cx, cz, dist, pitch, yaw), { cx, 0, cz }, { 0, 1, 0 })
  return Mat4.mul(proj, view)
end

local function updateCamera(dt)
  cam.drift = cam.drift + dt
  local rate = 3.0
  cam.fx = approach(cam.fx, cam.tfx, rate, dt)
  cam.fz = approach(cam.fz, cam.tfz, rate, dt)
  cam.dist = approach(cam.dist, cam.tdist, rate * 0.8, dt)
  cam.pitch = approach(cam.pitch, cam.tpitch, rate, dt)
  -- the idle: a slow breath on the distance and a hair of sway when close
  local sway = cam.wide and 0 or math.sin(cam.drift * 0.6) * 0.06
  local breathe = 1 + math.sin(cam.drift * 0.45) * 0.012
  cam.yaw = sway
  local dist = cam.dist * breathe
  cam.eye = eyeFor(cam.fx, cam.fz, dist, cam.pitch, cam.yaw)
  cam.mvp = viewProjection(cam.fx, cam.fz, dist, cam.pitch, cam.yaw)
  cam.near = dist * 1.3
  cam.far = dist * 3.6
end

local function project(x, y, z)
  local m = cam.mvp
  if not m then return nil end
  local cx = m[1] * x + m[2] * y + m[3] * z + m[4]
  local cy = m[5] * x + m[6] * y + m[7] * z + m[8]
  local cw = m[13] * x + m[14] * y + m[15] * z + m[16]
  if cw <= 0.001 then return nil end
  local w, h = love.graphics.getDimensions()
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
  local c = RenderTarget.new(w, h)
  local d = RenderTarget.new(w, h, { format = "depth24", readable = false })
  if not (c and d) then canvases.color, canvases.depth = nil, nil return false end
  canvases.color, canvases.depth, canvases.w, canvases.h = c, d, w, h
  return true
end

-- The hour: the sky bands and the tint come from lib/DayNight.lua, so the
-- map is lit like the world the player just left. `night` is how far into
-- the night the clock is, 0..1.
local function hourNow()
  local okP, pal = pcall(DayNight.palette)
  local okT, tint = pcall(DayNight.tint, true)
  local top, low, tn = SKY_TOP, SKY_LOW, { 1, 1, 1 }
  if okP and type(pal) == "table" and pal[1] and pal[5] then
    low = { pal[1][1] / 255, pal[1][2] / 255, pal[1][3] / 255 }
    top = { pal[5][1] / 255, pal[5][2] / 255, pal[5][3] / 255 }
  end
  if okT and type(tint) == "table" then tn = { tint[1] or 1, tint[2] or 1, tint[3] or 1 } end
  local lum = (tn[1] + tn[2] + tn[3]) / 3
  local night = clamp((0.62 - lum) / 0.42, 0, 1)
  -- the diorama is never as dark as the world: half the night, so the map
  -- stays readable, with the windows and the beacon doing the rest
  local sun = { 0.55 + tn[1] * 0.5, 0.55 + tn[2] * 0.5, 0.55 + tn[3] * 0.5 }
  local fog = lerp3(low, { 0.12, 0.14, 0.26 }, night * 0.6)
  return { top = top, low = low, sun = sun, night = night, fog = fog }
end

local function drawSky(w, h, hour)
  local t, l = hour.top, hour.low
  local ok, mesh = pcall(love.graphics.newMesh, {
    { 0, 0, 0, 0, t[1], t[2], t[3], 1 }, { w, 0, 1, 0, t[1], t[2], t[3], 1 },
    { w, h, 1, 1, l[1], l[2], l[3], 1 }, { 0, h, 0, 1, l[1], l[2], l[3], 1 },
  }, "fan", "stream")
  if ok and mesh then love.graphics.draw(mesh) end
end

local function sendCommon(s, hour)
  pcall(s.send, s, "mvp", "row", cam.mvp)
  pcall(s.send, s, "camPos", cam.eye)
  pcall(s.send, s, "fogRange", { cam.near, cam.far })
  pcall(s.send, s, "fogColor", hour.fog)
  pcall(s.send, s, "sunTint", hour.sun)
  pcall(s.send, s, "night", hour.night)
end

local function drawRegion(w, h, hour)
  if not ensureCanvases(w, h) then return false end
  local g = love.graphics
  g.push("all")
  g.setCanvas({ canvases.color, depthstencil = canvases.depth })
  g.clear(0, 0, 0, 1, true, true)
  g.setBlendMode("alpha")
  g.setDepthMode("always", false)
  g.setColor(1, 1, 1, 1)
  drawSky(w, h, hour)
  g.setDepthMode("lequal", true)
  g.setMeshCullMode("none")

  if R.landMesh and shaders.land then
    local s = shaders.land
    g.setShader(s)
    sendCommon(s, hour)
    local cl = cloudTexture()
    if cl then pcall(s.send, s, "clouds", cl) end
    pcall(s.send, s, "cloudDrift", { clock * 0.006, clock * 0.0035 })
    pcall(s.send, s, "cloudAmt", cl and 0.22 or 0)
    g.draw(R.landMesh)
  end
  if shaders.flat then
    local s = shaders.flat
    g.setShader(s)
    sendCommon(s, hour)
    pcall(s.send, s, "offset", { 0, 0, 0 })
    pcall(s.send, s, "alpha", 1)
    pcall(s.send, s, "unlit", 0)
    if R.propsMesh then g.draw(R.propsMesh) end
    if R.shipMesh then
      local ship = R.byName["S.S.ANNE"] and R.byName["S.S.ANNE"].ship
      if ship then
        pcall(s.send, s, "offset", { ship[1], WorldMap3D.SEA_Y + 0.15 + math.sin(clock * 1.1) * 0.12, ship[2] })
        g.draw(R.shipMesh)
        pcall(s.send, s, "offset", { 0, 0, 0 })
      end
    end
  end
  if R.waterMesh and shaders.water then
    local s = shaders.water
    g.setShader(s)
    sendCommon(s, hour)
    pcall(s.send, s, "skyColor", hour.low)
    pcall(s.send, s, "sunRay", SUN_RAY)
    pcall(s.send, s, "time", clock)
    pcall(s.send, s, "swellAmp", 0.9)
    pcall(s.send, s, "near", clamp((200 - cam.dist) / 120, 0, 1))
    g.draw(R.waterMesh)
  end
  if shaders.flat then
    local s = shaders.flat
    g.setShader(s)
    g.setDepthMode("lequal", false)
    if R.dashMesh then
      pcall(s.send, s, "unlit", 1)
      pcall(s.send, s, "alpha", 0.55 + 0.25 * math.sin(clock * 2.0))
      g.draw(R.dashMesh)
    end
    if R.windowMesh and hour.night > 0.05 then
      pcall(s.send, s, "unlit", 1)
      pcall(s.send, s, "alpha", hour.night)
      g.draw(R.windowMesh)
    end
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

-- ---------------------------------------------------------------- text
--
-- Every size below is written for a 720-line window and scaled from there:
-- a phone panel is three times the lines and the same distance from the
-- eye is not how it is held.
local UI = 1
local function S(px) return math.floor(px * UI + 0.5) end

local function text(s, x, y, size, r, g, b, a)
  size = S(size)
  if BattleHudXY.available() then
    local ok = pcall(BattleHudXY.text, s, x, y, size, { r, g, b, a })
    if ok then return end
  end
  love.graphics.setColor(r, g, b, a)
  love.graphics.print(s, x, y)
end

local fontRatio = nil
local function textW(s, size)
  size = S(size)
  if BattleHudXY.available() then
    if not fontRatio then
      local okA, drawn = pcall(BattleHudXY.text, "A", -9000, -9000, 64, { 0, 0, 0, 0 })
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

local function panel(x, y, w, h, a)
  local g = love.graphics
  g.setColor(0.04, 0.06, 0.10, (a or 0.78))
  g.rectangle("fill", x, y, w, h, 6, 6)
  g.setColor(1, 0.86, 0.35, 0.55)
  g.setLineWidth(1)
  g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 6, 6)
end

local function wrap(s, size, maxW)
  local lines, cur = {}, ""
  for word in s:gmatch("%S+") do
    local try = (cur == "") and word or (cur .. " " .. word)
    if textW(try, size) > maxW and cur ~= "" then
      lines[#lines + 1] = cur
      cur = word
    else
      cur = try
    end
  end
  if cur ~= "" then lines[#lines + 1] = cur end
  return lines
end

-- ---------------------------------------------------------------- pins
local function beacon(sx, sy, t, r, g, b)
  local gr = love.graphics
  for k = 0, 2 do
    local ph = (t * 0.8 + k / 3) % 1
    gr.setColor(r, g, b, (1 - ph) * 0.55)
    gr.setLineWidth(2)
    gr.ellipse("line", sx, sy, 10 + ph * 26, (10 + ph * 26) * 0.45)
  end
  gr.setColor(r, g, b, 0.95)
  gr.ellipse("fill", sx, sy, 5, 2.4)
  gr.setColor(r, g, b, 0.85)
  gr.setLineWidth(3)
  gr.line(sx, sy, sx, sy - 22)
  gr.circle("fill", sx, sy - 24, 4.5)
end

local function plate(name, sx, sy, size, hi, col)
  local w = textW(name, size) + S(14)
  local h = S(size) + S(8)
  local x, y = sx - w * 0.5, sy - h - S(10)
  local g = love.graphics
  g.setColor(0.03, 0.05, 0.09, hi and 0.90 or 0.66)
  g.rectangle("fill", x, y, w, h, 4, 4)
  if hi then
    g.setColor(1, 0.86, 0.35, 0.95)
    g.setLineWidth(1.5)
    g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4, 4)
  end
  col = col or { 1, 1, 1 }
  text(name, x + S(7), y + S(4), size, col[1], col[2], col[3], 1)
  g.setColor(1, 1, 1, hi and 0.8 or 0.35)
  g.setLineWidth(1)
  g.line(sx, y + h, sx, sy - 2)
end

local function drawPins(screen, w, h, hour)
  local sel = screen.locs and screen.sel and screen.locs[screen.sel]
  local selName = sel and sel.name
  local playerName = screen.playerLoc and screen.playerLoc.name
  local flySet = nil
  if screen.fly then
    flySet = {}
    for _, loc in ipairs(screen.locs) do flySet[loc.name] = true end
  end
  local nestSet = nil
  if screen.nests then
    nestSet = {}
    for _, loc in ipairs(screen.nests) do nestSet[loc.name] = true end
  end
  local list = {}
  for _, L in ipairs(R.locs) do
    local sx, sy, cw = project(L.px, L.py, L.pz)
    if sx then list[#list + 1] = { L = L, sx = sx, sy = sy, cw = cw } end
  end
  table.sort(list, function(a, b) return a.cw > b.cw end)
  local g = love.graphics
  local t = clock
  for _, e in ipairs(list) do
    local L, sx, sy = e.L, e.sx, e.sy
    local isSel = (L.name == selName)
    local isYou = (L.name == playerName)
    local isTarget = questTarget and (L.name == questTarget.name)
    local isTown = (L.kind == "city" or L.kind == "town" or L.kind == "league")
    local showName = isSel or isYou or isTarget or isTown
      or (not cam.wide and L.kind ~= "route" and L.kind ~= "sea")
      or (flySet and flySet[L.name])
    -- nests (Pokedex AREA): a pulsing green mark
    if nestSet and nestSet[L.name] then
      local p = 0.5 + 0.5 * math.sin(t * 5 + L.gx)
      g.setColor(0.35, 0.95, 0.45, 0.35 + 0.5 * p)
      g.circle("fill", sx, sy, 7 + p * 4)
      g.setColor(0.10, 0.45, 0.20, 0.9)
      g.circle("line", sx, sy, 7 + p * 4)
    end
    if isTarget and not isYou then
      beacon(sx, sy, t, 1.0, 0.82, 0.30)
    end
    if isYou then
      beacon(sx, sy, t + 0.3, 0.45, 0.85, 1.0)
    end
    if isSel then
      local p = 0.5 + 0.5 * math.sin(t * 4)
      g.setColor(1, 0.86, 0.35, 0.9)
      g.setLineWidth(2)
      g.ellipse("line", sx, sy, 14 + p * 3, (14 + p * 3) * 0.45)
    end
    if showName then
      local size = isSel and 18 or (isTown and 15 or 13)
      local col = isYou and { 0.65, 0.92, 1 } or (isTarget and { 1, 0.9, 0.5 } or nil)
      if flySet and not flySet[L.name] and not isYou then col = { 0.6, 0.6, 0.66 } end
      plate(L.name, sx, sy - (isYou and S(26) or 0), size, isSel, col)
      if isYou then
        text(STRINGS.you, sx - textW(STRINGS.you, 13) * 0.5, sy + S(6), 13, 0.65, 0.92, 1, 0.95)
      end
    end
  end
  -- Silph Co.'s beacon: a slow blink on the roof, brighter after dark
  local saffron = R.byName["SAFFRON CITY"]
  if saffron and saffron.beacon then
    local bx, by = project(saffron.beacon[1], saffron.beacon[2], saffron.beacon[3])
    if bx then
      local p = 0.5 + 0.5 * math.sin(t * 2.2)
      g.setColor(1, 0.35, 0.3, (0.35 + 0.65 * p) * (0.5 + 0.5 * (hour and hour.night or 0)))
      g.circle("fill", bx, by, S(3) + p * S(2))
    end
  end
end

-- ---------------------------------------------------------------- the route
--
-- The objective's route, walked over the picture's own roads: a breadth
-- first search over the tiles the artists drew as road, town, cave or sea
-- route, from the player's square to the target's. What comes back is the
-- path the game itself expects you to take; a straight line stands in only
-- when the roads do not connect (Route 23 sits behind a gate).
local function tileWalkable(tx, ty)
  if tx < 0 or ty < 1 or tx >= COLS or ty >= ROWS then return false end
  return R.walk[ty * COLS + tx] == true
end

local function findPath(a, b)
  if not (a and b) then return nil end
  local start = { a.tx, a.ty }
  local goal = { b.tx, b.ty }
  if not (tileWalkable(start[1], start[2]) and tileWalkable(goal[1], goal[2])) then
    return { { a.px, a.pz }, { b.px, b.pz } }, false
  end
  local key = function(x, y) return y * COLS + x end
  local prev = { [key(start[1], start[2])] = false }
  local queue, qi = { start }, 1
  local found = false
  while qi <= #queue do
    local c = queue[qi]; qi = qi + 1
    if c[1] == goal[1] and c[2] == goal[2] then found = true break end
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, ny = c[1] + d[1], c[2] + d[2]
      local k = key(nx, ny)
      if prev[k] == nil and tileWalkable(nx, ny) then
        prev[k] = c
        queue[#queue + 1] = { nx, ny }
      end
    end
  end
  if not found then return { { a.px, a.pz }, { b.px, b.pz } }, false end
  local pts = {}
  local c = goal
  while c do
    pts[#pts + 1] = { (c[1] + 0.5) * SUB, (c[2] + 0.5) * SUB }
    c = prev[key(c[1], c[2])]
  end
  -- start to goal
  local out = {}
  for i = #pts, 1, -1 do out[#out + 1] = pts[i] end
  out[1] = { a.px, a.pz }
  out[#out] = { b.px, b.pz }
  return out, true
end

local function drawTrail(pts, t)
  if not pts or #pts < 2 then return end
  local g = love.graphics
  -- marching dashes, projected point by point along the ground
  local screenPts = {}
  for i, p in ipairs(pts) do
    local y = R.hAt(math.floor(p[1]), math.floor(p[2]))
    local sx, sy = project(p[1], math.max(y, WorldMap3D.SEA_Y) + 0.35, p[2])
    if not sx then return end
    screenPts[i] = { sx, sy }
  end
  -- the dash pattern runs continuously along the polyline and advances
  -- with time, so the route marches from the player toward the target
  local off = (-t * 28) % 16
  g.setLineWidth(3)
  for i = 1, #screenPts - 1 do
    local a, b = screenPts[i], screenPts[i + 1]
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 0.5 then
      local ux, uy = dx / len, dy / len
      local s = -off
      while s < len do
        local s0, s1 = math.max(0, s), math.min(len, s + 9)
        if s1 > s0 then
          g.setColor(0, 0, 0, 0.45)
          g.line(a[1] + ux * s0 + 1, a[2] + uy * s0 + 1, a[1] + ux * s1 + 1, a[2] + uy * s1 + 1)
          g.setColor(1, 0.86, 0.35, 0.95)
          g.line(a[1] + ux * s0, a[2] + uy * s0, a[1] + ux * s1, a[2] + uy * s1)
        end
        s = s + 16
      end
      off = (off + len) % 16
    end
  end
end

-- ---------------------------------------------------------------- panels
local function drawObjective(w, h)
  if not quest then return end
  local pad, x, y = S(12), S(18), S(18)
  local pw = math.min(S(470), w * 0.36)
  local size = 16
  local lines = wrap(quest.step.title, size, pw - pad * 2)
  local dlines = wrap(quest.step.detail or "", 13, pw - pad * 2)
  local ph = pad + S(18) + #lines * S(size + 5) + S(6) + #dlines * S(17) + S(6)
  local where = questTarget and questTarget.name or ""
  if where ~= "" then ph = ph + S(24) end
  if #quest.upcoming > 0 then ph = ph + S(20) + #quest.upcoming * S(17) end
  ph = ph + pad - S(4)
  panel(x, y, pw, ph, 0.80)
  local ty = y + pad - S(2)
  text(STRINGS.objective, x + pad, ty, 11, 1, 0.86, 0.35, 1)
  local bw = S(9)
  local bx = x + pw - pad - 8 * (bw + S(3))
  for i = 1, 8 do
    local got = i <= (quest.badges or 0)
    love.graphics.setColor(got and 1 or 0.35, got and 0.86 or 0.38, got and 0.35 or 0.42, got and 1 or 0.7)
    love.graphics.circle(got and "fill" or "line", bx + (i - 1) * (bw + S(3)) + bw * 0.5, ty + S(5), bw * 0.45)
  end
  text(STRINGS.badges, bx - textW(STRINGS.badges, 9) - S(8), ty + S(1), 9, 0.7, 0.72, 0.78, 1)
  ty = ty + S(20)
  for _, ln in ipairs(lines) do
    text(ln, x + pad, ty, size, 1, 1, 1, 1); ty = ty + S(size + 5)
  end
  ty = ty + S(4)
  for _, ln in ipairs(dlines) do
    text(ln, x + pad, ty, 13, 0.78, 0.82, 0.90, 1); ty = ty + S(17)
  end
  if where ~= "" then
    ty = ty + S(6)
    love.graphics.setColor(1, 0.86, 0.35, 0.95)
    love.graphics.circle("fill", x + pad + S(5), ty + S(8), S(4))
    text(where, x + pad + S(16), ty, 14, 1, 0.9, 0.5, 1)
    ty = ty + S(22)
  end
  if #quest.upcoming > 0 then
    ty = ty + S(8)
    text(STRINGS.next, x + pad, ty, 10, 0.55, 0.62, 0.74, 1)
    ty = ty + S(15)
    for _, st in ipairs(quest.upcoming) do
      text("- " .. st.title, x + pad, ty, 12, 0.62, 0.68, 0.78, 1); ty = ty + S(17)
    end
  end
end

-- What the selected place is and what it has -- the card at the bottom.
local function drawCard(screen, w, h, game)
  local loc = screen.locs and screen.sel and screen.locs[screen.sel]
  if not loc then return end
  local L = R.byName[loc.name]
  local pad = S(12)
  local pw = math.min(S(440), w * 0.34)
  local x, y = S(18), h - S(18)
  local rows = {}
  local kind = L and (STRINGS.kinds[L.kind] or "") or ""
  local visited = false
  if L and game and game.save and game.save.visited then
    for _, id in ipairs(L.maps) do
      if game.save.visited[id] then visited = true break end
    end
  end
  rows[#rows + 1] = { visited and STRINGS.visited or STRINGS.unvisited,
                      visited and { 0.55, 0.9, 0.6 } or { 0.7, 0.72, 0.78 } }
  if L and (L.kind == "city" or L.kind == "town" or L.kind == "league") then
    local field = game and game.data and game.data.field
    local canFly = false
    if field and field.flyWarps then
      for _, id in ipairs(L.maps) do
        if field.flyWarps[id] and game.save.visited and game.save.visited[id] then canFly = true end
      end
    end
    rows[#rows + 1] = { canFly and STRINGS.flyOk or STRINGS.flyNo,
                        canFly and { 0.65, 0.92, 1 } or { 0.6, 0.62, 0.7 } }
    if L.hasCenter then rows[#rows + 1] = { STRINGS.center, { 1, 0.55, 0.55 } } end
    if L.hasMart then rows[#rows + 1] = { STRINGS.mart, { 0.6, 0.72, 1 } } end
    if L.gym then
      local got = false
      if game and game.save and game.save.inventory then
        local n = game.save.inventory[L.gym.badge]
        got = type(n) == "number" and n > 0
      end
      rows[#rows + 1] = { STRINGS.gym .. ": " .. L.gym.leader .. "  -  " .. L.gym.name,
                          { 1, 0.86, 0.5 } }
      rows[#rows + 1] = { got and STRINGS.beaten or STRINGS.unbeaten,
                          got and { 0.55, 0.9, 0.6 } or { 0.85, 0.6, 0.5 } }
    end
  end
  local ph = pad * 2 + S(26) + #rows * S(17)
  y = y - ph
  panel(x, y, pw, ph, 0.80)
  local ty = y + pad - S(2)
  local col = (L and L.color) or { 1, 1, 1 }
  text(loc.name, x + pad, ty, 18, 1, 1, 1, 1)
  local kw = textW(kind, 11)
  text(kind, x + pw - pad - kw, ty + S(4), 11, col[1] * 0.8 + 0.2, col[2] * 0.8 + 0.2, col[3] * 0.8 + 0.2, 1)
  ty = ty + S(26)
  for _, r in ipairs(rows) do
    text(r[1], x + pad, ty, 12, r[2][1], r[2][2], r[2][3], 1); ty = ty + S(17)
  end
end

-- The classic picture, in the corner: the map everyone has in their head,
-- with the cursor and the player on it, so a glance settles where the
-- camera is looking. Drawn from the engine's own tiles and the engine's own
-- arithmetic for where a square lands (markerXY).
local function drawInset(screen, w, h)
  local bg = screen.bg
  if not (bg and bg.img and bg.quads and bg.map) then return end
  local g = love.graphics
  local scale = math.max(1, math.floor(h / 400))
  local iw, ih = 160 * scale, 144 * scale
  local x, y = w - iw - S(18), h - ih - S(48)
  panel(x - 6, y - 6, iw + 12, ih + 12, 0.85)
  if shaders.inset then
    g.setShader(shaders.inset)
    pcall(shaders.inset.send, shaders.inset, "c0", INSET_PAL[1])
    pcall(shaders.inset.send, shaders.inset, "c1", INSET_PAL[2])
    pcall(shaders.inset.send, shaders.inset, "c2", INSET_PAL[3])
    pcall(shaders.inset.send, shaders.inset, "c3", INSET_PAL[4])
  end
  g.setColor(1, 1, 1, 1)
  for i, t in ipairs(bg.map) do
    local col, row = (i - 1) % 20, math.floor((i - 1) / 20)
    if row > 0 and bg.quads[t] then
      g.draw(bg.img, bg.quads[t], x + col * 8 * scale, y + row * 8 * scale, 0, scale, scale)
    end
  end
  g.setShader()
  local function mark(loc, r, gg, b, a, ring)
    if not (loc and loc.x and loc.y) then return end
    local mx = x + (loc.x * 8 + 16) * scale
    local my = y + (loc.y * 8 + 8) * scale
    g.setColor(r, gg, b, a)
    if ring then
      g.setLineWidth(2)
      g.rectangle("line", mx - 2 * scale, my - 2 * scale, 12 * scale, 12 * scale)
    else
      g.rectangle("fill", mx + 2 * scale, my + 2 * scale, 4 * scale, 4 * scale)
    end
  end
  if questTarget then mark({ x = questTarget.gx, y = questTarget.gy }, 1, 0.6, 0.1, 0.95) end
  if screen.playerLoc then mark(screen.playerLoc, 0.85, 0.1, 0.1, 0.55 + 0.45 * math.abs(math.sin(clock * 3))) end
  local sel = screen.locs and screen.sel and screen.locs[screen.sel]
  if sel then mark(sel, 0.05, 0.05, 0.05, 0.95, true) end
  text(STRINGS.classic, x, y - S(20), 10, 0.7, 0.72, 0.78, 0.9)
end

local function drawBanner(screen, w, h)
  local sel = screen.locs and screen.sel and screen.locs[screen.sel]
  local label
  if screen.nestSpecies then
    local def = activeGame and activeGame.data and activeGame.data.pokemon
                and activeGame.data.pokemon[screen.nestSpecies]
    local nm = def and def.name or tostring(screen.nestSpecies)
    label = (#(screen.nests or {}) > 0) and (nm .. STRINGS.nest) or (nm .. STRINGS.noNest)
  elseif sel then
    label = (screen.fly and STRINGS.to or "") .. sel.name
  else
    label = "KANTO"
  end
  local size = 24
  local tw = textW(label, size)
  local x, y = (w - tw) * 0.5, S(16)
  panel(x - S(16), y - S(6), tw + S(32), S(size) + S(14), 0.75)
  text(label, x, y, size, 1, 1, 1, 1)
end

local function drawCompass(w, h)
  local g = love.graphics
  local rad = S(22)
  local cx, cy = w - rad - S(24), rad + S(24)
  g.setColor(0.04, 0.06, 0.10, 0.7)
  g.circle("fill", cx, cy, rad)
  g.setColor(1, 0.86, 0.35, 0.8)
  g.setLineWidth(1)
  g.circle("line", cx, cy, rad)
  -- north is up the screen, less the idle sway of the camera
  local a = -cam.yaw
  local tipX, tipY = cx + math.sin(a) * rad * 0.62, cy - math.cos(a) * rad * 0.62
  local lx, ly = cx + math.sin(a + math.pi * 0.5) * rad * 0.22, cy - math.cos(a + math.pi * 0.5) * rad * 0.22
  local rx, ry = cx + math.sin(a - math.pi * 0.5) * rad * 0.22, cy - math.cos(a - math.pi * 0.5) * rad * 0.22
  g.setColor(1, 0.35, 0.3, 1)
  g.polygon("fill", tipX, tipY, lx, ly, rx, ry)
  g.setColor(0.85, 0.87, 0.92, 0.9)
  g.polygon("fill", cx - math.sin(a) * rad * 0.62, cy + math.cos(a) * rad * 0.62, lx, ly, rx, ry)
  text(STRINGS.north, cx - textW(STRINGS.north, 11) * 0.5, cy - rad - S(16), 11, 1, 1, 1, 0.95)
end

local function drawHints(screen, w, h)
  local hint = screen.fly and STRINGS.hintFly
               or (screen.nestSpecies and STRINGS.hintNest or STRINGS.hintView)
  local size = 12
  local tw = textW(hint, size)
  local x, y = (w - tw) * 0.5, h - S(28)
  love.graphics.setColor(0.04, 0.06, 0.10, 0.6)
  love.graphics.rectangle("fill", x - S(12), y - S(5), tw + S(24), S(size) + S(10), 4, 4)
  text(hint, x, y, size, 0.82, 0.85, 0.9, 1)
end

local function drawProgress(w, h)
  local g = love.graphics
  g.setColor(0.05, 0.08, 0.14, 1)
  g.rectangle("fill", 0, 0, w, h)
  local msg = STRINGS.building
  local tw = textW(msg, 18)
  text(msg, (w - tw) * 0.5, h * 0.5 - 30, 18, 1, 0.86, 0.35, 1)
  local frac = (build and build.done or 0) / 6
  g.setColor(0.2, 0.24, 0.32, 1)
  g.rectangle("fill", w * 0.3, h * 0.5 + 6, w * 0.4, 8, 4, 4)
  g.setColor(1, 0.86, 0.35, 1)
  g.rectangle("fill", w * 0.3, h * 0.5 + 6, w * 0.4 * clamp(frac, 0, 1), 8, 4, 4)
end

-- ---------------------------------------------------------------- input
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

local heldA, heldSel, grace = false, false, 0

function WorldMap3D.toggleZoom()
  if not R then return end
  if cam.wide then
    local L = R.lastSel or (questTarget)
    if L then frameOn(L.px, L.pz) else frameWhole() end
  else
    frameWhole()
  end
end

function WorldMap3D.toggleTopDown()
  if not R then return end
  cam.top = not cam.top
  if cam.wide then frameWhole() else
    local L = R.lastSel
    if L then frameOn(L.px, L.pz) else frameWhole() end
  end
end

local function pollInput(game, screen, dt)
  local input = game and game.input
  if not (input and input.isDown) then return end
  if grace > 0 then grace = grace - dt; heldA = true; return end
  local function down(b)
    local ok, yes = pcall(input.isDown, input, b)
    return ok and yes
  end
  -- A belongs to the engine on the fly picker (it departs) and on the
  -- Pokedex area (it closes); the zoom is only ours on the plain viewer
  local a = down("a")
  if not screen.fly and not screen.nestSpecies then
    if a and not heldA then WorldMap3D.toggleZoom() end
  end
  heldA = a
  local s = down("select")
  if s and not heldSel then WorldMap3D.toggleTopDown() end
  heldSel = s
end

function WorldMap3D.available()
  if not WorldMap3D.ENABLED then return false end
  if WorldMap3D.classic() then return false end
  if failed then return false end
  return (love.graphics and love.graphics.newCanvas ~= nil) and true or false
end

-- ---------------------------------------------------------------- frame
function WorldMap3D.frame()
  if not WorldMap3D.available() then return end
  local game = activeGame
  local stack = game and game.stack
  local top = stack and stack.top and stack:top()
  if not isTownMap(top) then
    lastTime = nil
    lastScreen = nil
    return
  end
  local now = love.timer and love.timer.getTime and love.timer.getTime() or 0
  local opened = (lastScreen ~= top)
  local dt = lastTime and math.min(0.1, now - lastTime) or 0.016
  lastTime = now
  lastScreen = top
  clock = clock + dt
  if opened then
    grace = 0.4
    heldA, heldSel = true, true
    lastSel = nil
    quest, questTarget, questPath = nil, nil, nil
    if R then
      R.lastSel = nil
      cam.top = false
      cam.pitch = 1.25
      cam.dist = fitDistance(0.95) * 1.5
      frameWhole()
    end
  end
  local w, h = love.graphics.getDimensions()
  UI = clamp(h / 720, 0.9, 2.2)

  if not R then
    if not build then
      build = { phase = "", done = 0, total = 6 }
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
      ensureShaders()
      log(("kanto built: %d places, %d land verts, %d prop verts, %.0f ms")
          :format(#R.locs, R.landVerts, R.propVerts, R.ms))
      build = nil
      cam.fx, cam.fz = GW * 0.5, GH * 0.5
      cam.pitch = 1.25
      cam.dist = fitDistance(0.95) * 1.6
      frameWhole()
      grace, heldA, heldSel = 0.4, true, true
    else
      drawProgress(w, h)
      return
    end
  end

  -- the cursor
  local sel = top.sel
  if sel ~= lastSel then
    lastSel = sel
    local loc = top.locs and top.locs[sel]
    local L = loc and R.byName[loc.name]
    if L then
      R.lastSel = L
      if not cam.wide then frameOn(L.px, L.pz)
      else
        cam.tfx = GW * 0.46 + (L.px - GW * 0.5) * 0.18
        cam.tfz = GH * 0.46 + (L.pz - GH * 0.5) * 0.18
      end
    end
  end

  -- the objective, once per opening
  if quest == nil then
    quest = WorldMapQuest.current(game.save) or false
    if quest then
      local tgt = top.byMap and (top.byMap[quest.step.target]
                  or (quest.step.fallback and top.byMap[quest.step.fallback]))
      questTarget = tgt and R.byName[tgt.name] or nil
      local here = top.playerLoc and R.byName[top.playerLoc.name]
      if questTarget and here and here ~= questTarget then
        questPath = findPath(here, questTarget)
      end
    end
  end

  pollInput(game, top, dt)
  updateCamera(dt)
  local hour = hourNow()
  if drawRegion(w, h, hour) then
    if questPath and not top.fly and not top.nestSpecies then drawTrail(questPath, clock) end
    drawPins(top, w, h, hour)
    drawBanner(top, w, h)
    if not top.fly and not top.nestSpecies then drawObjective(w, h) end
    drawCard(top, w, h, game)
    drawInset(top, w, h)
    drawCompass(w, h)
    drawHints(top, w, h)
  end
end

-- ---------------------------------------------------------------- probes
function WorldMap3D.report()
  return {
    enabled = WorldMap3D.ENABLED, classic = WorldMap3D.classic(),
    built = R ~= nil, failed = failed,
    places = R and #R.locs or 0,
    landVerts = R and R.landVerts or 0, propVerts = R and R.propVerts or 0,
    waterVerts = R and R.waterVerts or 0, ms = R and R.ms or 0,
    peaks = R and R.peaks or 0,
    shaders = shaders.land ~= nil and shaders.water ~= nil and shaders.flat ~= nil,
    quest = quest and quest.step.id or nil,
    target = questTarget and questTarget.name or nil,
    path = questPath and #questPath or 0,
    wide = cam.wide, top = cam.top,
  }
end

function WorldMap3D.debugPlaces()
  if not R then return {} end
  local out = {}
  for _, L in ipairs(R.locs) do
    local sx, sy = project(L.px, L.py, L.pz)
    out[#out + 1] = { id = L.name, gx = L.gx, gy = L.gy, kind = L.kind,
                      x = L.px, z = L.pz, y = L.py,
                      sx = sx and math.floor(sx) or -9999,
                      sy = sy and math.floor(sy) or -9999 }
  end
  return out
end

function WorldMap3D.strings() return STRINGS end

function WorldMap3D.invalidate()
  if R then
    for _, k in ipairs({ "landMesh", "waterMesh", "propsMesh", "dashMesh", "shipMesh", "windowMesh" }) do
      local m = R[k]
      if m and m.release then pcall(m.release, m) end
    end
  end
  R, build, failed = nil, nil, false
  lastSel = nil
end

-- ---------------------------------------------------------------- install
--
-- Two wraps, and both are needed or the frame carries two maps: the
-- screen's constructor captures the game and silences the engine's draw on
-- the INSTANCE (asked per frame, so CLASSIC and a failed build both hand
-- the picture straight back), and Renderer.endFrame paints.
local installed = false
function WorldMap3D.install()
  if installed then return true end
  local okT, TownMap = pcall(require, "src.ui.TownMap")
  if not (okT and TownMap and TownMap.new) then
    log("no src.ui.TownMap -- world map stays classic")
    return false
  end
  local okR, Renderer = pcall(require, "src.render.Renderer")
  if not (okR and Renderer and Renderer.endFrame) then
    log("no Renderer.endFrame -- world map stays classic")
    return false
  end
  local newInner = TownMap.new
  TownMap.new = function(game, ...)
    local screen = newInner(game, ...)
    if type(screen) == "table" then
      activeGame = game
      local engineDraw = screen.draw
      screen.draw = function(self, ...)
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
      log("frame failed, falling back to the classic map: " .. tostring(err))
    end
    return a, b, c
  end
  installed = true
  return true
end

return WorldMap3D
