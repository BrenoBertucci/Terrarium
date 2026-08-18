-- Gen 2 (Pokemon Gold) bridge: the one place this mod knows which
-- generation it is running on, and the shims that make Gold's world wear
-- the shape the rest of the mod already reads.
--
-- The engine's own Gen2Compat facade answers every require of a Gen 1
-- module (src.core.Game, src.world.Map, ...) with a Gold-backed adapter,
-- so most of this mod runs unedited. What the facade cannot cover is
-- STRUCTURE the mod walks directly:
--
--   neighbors  Gen 1 rows are { map = <Map instance>, ox, oy }; Gold's
--              World bakes whole-map images and its rows are
--              { id, ox, oy, image } -- no instance, because nothing in
--              Gold's own renderer needs one. Everything here (mesher,
--              atlas, water, lamps, arena picking) reads nb.map, so the
--              bridge hangs a real src/world/gen2/Map.lua instance on
--              each row at the source -- World:rebuildNeighbors -- and
--              every consumer sees Gen 1's shape with zero per-site
--              guards. Map.new(def, tileset) is pure Lua over static
--              tables, so one instance per map id for the boot is free.
--
-- Everything is pcall-guarded and generation-gated: on a Gen 1 boot (or
-- an engine old enough to have no GameVersion.generation) install() is a
-- no-op, so Yellow keeps the exact code path it always had.

local V = ...

local Bridge = {}

local gen = nil

-- 1 or 2, resolved once. Old engines (< 0.2.x) have no generation() and
-- no Gen 2 games, so they answer 1.
function Bridge.generation()
  if gen then return gen end
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  local g = ok and GameVersion and GameVersion.generation
  gen = g and GameVersion.generation() or 1
  return gen
end

function Bridge.isGen2()
  return Bridge.generation() == 2
end

-- map id -> gen2 Map instance (or false when it cannot be built).  Defs
-- and tilesets are static for the boot, so the cache never invalidates.
local instances = {}

local function adopt(world, Map)
  for _, nb in ipairs(world.neighbors or {}) do
    if nb.map == nil and nb.id then
      local inst = instances[nb.id]
      if inst == nil then
        local def = world.maps and world.maps[nb.id]
        local tileset = def and world.tilesets and world.tilesets[def.tileset]
        inst = (def and tileset) and Map.new(def, tileset) or false
        instances[nb.id] = inst
      end
      if inst then nb.map = inst end
    end
  end
end

-- Wrap World:rebuildNeighbors so every rebuilt row carries nb.map before
-- any consumer sees it.  Installed once, at mod load; the first world is
-- built after mods load, so no build escapes the wrap.
function Bridge.install()
  if not Bridge.isGen2() then return end
  local okW, World = pcall(require, "src.world.gen2.World")
  local okM, Map = pcall(require, "src.world.gen2.Map")
  if not (okW and okM and World and Map and World.rebuildNeighbors) then
    return
  end
  if World.__terrariumNeighborShim then return end
  World.__terrariumNeighborShim = true
  local original = World.rebuildNeighbors
  World.rebuildNeighbors = function(world, ...)
    local r = original(world, ...)
    pcall(adopt, world, Map)
    return r
  end

  -- Gold's NPCs carry Gen 1's seven-value pose() (the engine added it for
  -- gen2compat, src/world/gen2/Npc.lua), but its Player does not -- and
  -- the billboard pass poses every entity through the same call.  Mirror
  -- the NPC recipe onto the Player class.
  local okP, Player = pcall(require, "src.world.gen2.Player")
  if okP and Player and not Player.pose then
    function Player:pose()
      return self.sprite, self.px, self.py + (self.spriteYOffset or 0),
             self.facing, self:walkPhase(), self.stepFlip, false
    end
  end
end

return Bridge
