-- Voxel world mode: where every map STANDS, out past the ones being drawn.
--
-- The diorama draws the map you are on and the maps connected to it, and
-- then it stops: a border ring of trees, and sky. The probe measures the
-- consequence -- the drawn world ends about 140 pixels short of its own
-- horizon row, with a fifth of the frame above it empty. There is nothing
-- out there to look at because nothing out there is placed.
--
-- This file is the placing. It answers, for a map you are standing on,
-- WHERE the rest of Kanto is relative to you, in world pixels, as far out
-- as you care to ask.
--
-- IT DOES NOT DO THE WALK ITSELF, and that is the whole point of it being
-- this short. The engine already has the walk -- a BFS over
-- `def.connections` composing each connection's strip offset, deduped by
-- map id, exposed as a pure function precisely so something other than the
-- overworld can call it (OverworldState.computeNeighbors). It is what the
-- engine builds `state.neighbors` from, at two hops. Asking it for more
-- hops is the entire trick: the same walk, the same offsets, the same
-- rounding, just further -- so a map this file places and a map the engine
-- places can never disagree about where they are, which they certainly
-- would if this had grown its own copy of the arithmetic.
--
-- IT LOADS NOTHING. Every field it touches -- width, height, connections,
-- tileset -- lives on the map DEF, which is generated data that is already
-- resident for all 223 maps. No MapLoader, no tile batches, no atlas, no
-- GPU object. Placing the whole region costs a table.
--
-- WHAT IT IS FOR is the far skyline: geometry so distant it is a
-- silhouette and a colour, which needs to know exactly one thing about a
-- map -- where it is. What that geometry looks like is lib/Skyline.lua's
-- question.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Map = require("src.world.Map")

local WorldAtlas = {}

-- How far the walk goes. Two is what the engine renders (its own
-- NEIGHBOR_HOPS), so anything at or below that is already real geometry
-- and this file has nothing to add there -- the interesting range starts
-- at three. Six reaches most of the way across Kanto from anywhere in it
-- without ever being an unbounded walk of the whole connection graph.
WorldAtlas.HOPS = 6

-- One cached answer, keyed by the map it was rooted at. A crossing
-- re-roots and rebuilds; standing still costs nothing. There is no reason
-- to keep more than one -- the previous root's table describes offsets
-- from a map you are no longer on.
local cache = { root = nil, list = nil }

local function data()
  local ok, Game = pcall(require, "src.core.Game")
  return ok and Game and Game.data or nil
end

-- Everything the connection graph reaches from `rootId` within HOPS, as
-- { id = , ox = , oy = , def = , hops = } in world pixels relative to the
-- root map's own origin. Outdoor maps only: a house interior has a
-- position in the graph the same way a route does, and standing one up on
-- the horizon would put a bedroom floor in the landscape.
function WorldAtlas.around(rootId)
  if not rootId then return {} end
  if cache.root == rootId and cache.list then return cache.list end

  local d = data()
  local maps = d and d.maps
  local root = maps and maps[rootId]
  if not root then return {} end

  local OverworldState = require("src.world.OverworldController")
  local ok, raw = pcall(OverworldState.computeNeighbors, maps, rootId,
                        WorldAtlas.HOPS)
  if not ok or type(raw) ~= "table" then return {} end

  local list = {}
  for _, n in ipairs(raw) do
    local def = maps[n.id]
    if def and Map.isOutdoor(def) then
      list[#list + 1] = { id = n.id, ox = n.ox, oy = n.oy, def = def }
    end
  end

  cache.root, cache.list = rootId, list
  return list
end

-- The same list with everything the scene is ALREADY drawing removed --
-- the current map and its rendered neighbours, whose ids ride on
-- `state.neighbors`. What is left is exactly what may be drawn as a
-- silhouette without ever double-drawing a map that has real geometry.
--
-- Read off the live scene rather than off a hop count, deliberately. The
-- engine widens its own neighbour set with the VIEW SIZE (rebuildNeighbors
-- passes the view half-extents as `reach`), so at a full zoom-out it draws
-- maps well past two hops -- and a skyline that decided what to skip by
-- counting hops would quietly stack a flat silhouette on top of a real
-- town every time the player zoomed out.
function WorldAtlas.beyond(state)
  if not (state and state.map) then return {} end
  local live = { [state.map.id] = true }
  for _, nb in ipairs(state.neighbors or {}) do
    if nb.map and nb.map.id then live[nb.map.id] = true end
  end
  local out = {}
  for _, e in ipairs(WorldAtlas.around(state.map.id)) do
    if not live[e.id] then out[#out + 1] = e end
  end
  return out
end

-- Dropped whenever the maps registry could have changed under it (a mod
-- patching a map record, the dev hot reload).
function WorldAtlas.invalidate()
  cache.root, cache.list = nil, nil
end

return WorldAtlas
