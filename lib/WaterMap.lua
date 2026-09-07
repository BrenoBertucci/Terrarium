-- Voxel world mode: WHERE THE WATER IS.
--
-- One question, asked in one place: may a water SURFACE be drawn on this
-- cell of this map? Every renderer that used to ask `map:isWaterCell`
-- directly asks this instead, and gameplay (surf, collision, encounters)
-- goes on asking the engine, unchanged.
--
-- WHY THE ENGINE'S ANSWER IS NOT THE ANSWER. Map.new (src/world/Map.lua)
-- builds its water set from a STALE-CACHE FALLBACK, because no Gen 1
-- tileset record stamps waterTiles/shoreTiles:
--
--   self.waterTiles = hashSet(tilesetDef.waterTiles or { 0x14 }, {})
--   shore = tilesetDef.shoreTiles
--   if shore == nil and def.tileset ~= "SHIP_PORT" then shore = { 0x32, 0x48 } end
--   hashSet(shore, self.waterTiles)
--
-- so tiles $14, $32 and $48 read as water on EVERY tileset in the game.
-- The engine knows this and gates it at the caller -- Map:isWaterCell's own
-- comment says "Tileset membership in water_tilesets.asm is checked by the
-- caller", and OverworldController does check it
-- (OverworldState:tilesetHasWater, and the boot heuristic beside it spells
-- the failure out: "tile $14 -- a walkable floor in
-- HOUSE/GATE/LOBBY/MANSION/MUSEUM -- reads as water").
--
-- This mod was the caller that never checked. Measured over every Red map,
-- that put a pond in the Indigo Plateau Pokemon Center (tileset MART, 9
-- cells: the healing machines and the lobby plants) and under the dragon
-- statues of Lance's room and the Fighting Dojo (tileset DOJO, 18 cells),
-- and it is the reason a shoreline read as a slab -- see the three rules.
--
-- THE THREE RULES, and each one is a bug that was reported:
--
--   1. THE TILESET. Only a tileset in data.field.waterTilesets
--      (OVERWORLD, FOREST, DOJO, GYM, SHIP, SHIP_PORT, CAVERN, FACILITY,
--      PLATEAU in Gen 1) can hold water at all. Kills every interior.
--      A ROM with no such table -- Gold, a stub map in a probe -- ALLOWS
--      everything rather than refusing it: an unknown gate must not blank
--      the water of a game this list was never written for.
--
--   2. SHORE IS NOT SURFACE. $32/$48 are the shore tiles of
--      IsNextTileShoreOrWater: land you may mount Surf FROM. On the
--      overworld they are drawn as the water's own diagonal edge and must
--      stay wet; in the Dojo the same id is a statue's plinth. What tells
--      them apart is not the id, it is whether real water is NEXT TO IT --
--      a shore with no water beside it is not a shore. So a shore tile is
--      a surface only when a 4-neighbour cell carries the tileset's TRUE
--      water tile.
--
--   3. THE ART IS PER TILE, THE COLLISION IS PER CELL. The engine judges a
--      16x16 cell by its bottom-left 8x8 tile alone, which is right for
--      walking and wrong for drawing: Gen 1's shore cells are drawn with
--      the BANK in the top half and the water in the bottom ($33 over $14
--      all along Cerulean's channel, $54 and $31 elsewhere). Painting the
--      whole cell water sank the bank to the water plane, which is why a
--      shoreline read as a flat block with a hard edge instead of a lip.
--      WaterMap.isSurfaceTile answers per tile so the bank keeps its own
--      class and its own height.
--
-- What this file does NOT do is decide what water LOOKS like. It says
-- where. See lib/Water.lua for the surface and lib/WaterBody.lua for how
-- big the body under a point is.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local WaterMap = {}

-- Same fallbacks Map.new carries, and they have to be the same: this file
-- decides which of the engine's water tiles are DRAWN, so it must start
-- from exactly the set the engine built.
local FALLBACK_WATER = { 0x14 }
local FALLBACK_SHORE = { 0x32, 0x48 }
local NO_SHORE_TILESETS = { SHIP_PORT = true }

-- tileset id -> { water = set, shore = set }. Depends only on the tileset
-- record, which is constant for an id, so it is cached like TileShape's.
local sets = {}

local function setsFor(map)
  local ts = map and map.tileset
  local id = ts and ts.id
  if id and sets[id] then return sets[id] end
  local water, shore = {}, {}
  local list = (ts and ts.waterTiles) or FALLBACK_WATER
  for _, t in ipairs(list) do water[t] = true end
  local sh = ts and ts.shoreTiles
  if sh == nil then
    local name = map and map.def and map.def.tileset
    if not (name and NO_SHORE_TILESETS[name]) then sh = FALLBACK_SHORE end
  end
  for _, t in ipairs(sh or {}) do shore[t] = true end
  local out = { water = water, shore = shore }
  if id then sets[id] = out end
  return out
end

-- data.field.waterTilesets as a set, resolved once. `false` means the game
-- does not ship the table (Gold, a stub), and false is ALLOW -- see rule 1.
local allowed = nil

local function allowedSet()
  if allowed ~= nil then return allowed end
  local ok, Game = pcall(require, "src.core.Game")
  local list = ok and Game and Game.data and Game.data.field
                  and Game.data.field.waterTilesets
  if type(list) ~= "table" or #list == 0 then
    allowed = false
    return allowed
  end
  local set = {}
  for _, name in ipairs(list) do set[name] = true end
  allowed = set
  return allowed
end

-- Dropped on a ROM swap: Red and Gold do not share a water-tileset table,
-- and a cached `false` from one would allow the other's interiors.
function WaterMap.invalidate()
  allowed = nil
  sets = {}
end

-- May this map's tileset hold water at all? (rule 1)
function WaterMap.drawsWater(map)
  local name = map and map.def and map.def.tileset
  if not name then return true end
  local set = allowedSet()
  if not set then return true end
  return set[name] == true
end

-- The tile's own art is the tileset's TRUE water (rule 2's "real water").
function WaterMap.isDeepTile(map, tile)
  if tile == nil then return false end
  return setsFor(map).water[tile] == true
end

-- The tile's own art is water OR the shore edge drawn as part of it.
-- This is the per-TILE question rule 3 needs: inside a water cell, only a
-- tile that answers true here is painted as surface; the bank is not.
function WaterMap.isSurfaceTile(map, tile)
  if tile == nil then return false end
  local s = setsFor(map)
  return s.water[tile] == true or s.shore[tile] == true
end

local function trueWaterCell(map, s, cx, cy)
  local ok, tile = pcall(map.cellTile, map, cx, cy)
  return ok and tile ~= nil and s.water[tile] == true
end

-- Is this CELL a water surface? (rules 1 and 2)
--
-- Deliberately NOT gated on `inBounds`: a body that runs off the edge of
-- the map is answered by the border block the same way the engine answers
-- it, so a sea keeps going under the seam instead of ending in a wall.
function WaterMap.surfaceCell(map, cx, cy)
  if not (map and map.cellTile) then return false end
  if not WaterMap.drawsWater(map) then return false end
  local s = setsFor(map)
  local ok, tile = pcall(map.cellTile, map, cx, cy)
  if not ok or tile == nil then return false end
  if s.water[tile] then return true end
  if not s.shore[tile] then return false end
  -- a shore with no water beside it is not a shore
  return trueWaterCell(map, s, cx + 1, cy)
      or trueWaterCell(map, s, cx - 1, cy)
      or trueWaterCell(map, s, cx, cy + 1)
      or trueWaterCell(map, s, cx, cy - 1)
end

-- The convenience the ambient systems want: the cell the player/NPC/critter
-- stands on is open water. Same answer as surfaceCell, named for the
-- callers that used to say `map:isWaterCell` and meant "is there water
-- here to swim in / splash / listen to".
function WaterMap.openWater(map, cx, cy)
  return WaterMap.surfaceCell(map, cx, cy)
end

return WaterMap
