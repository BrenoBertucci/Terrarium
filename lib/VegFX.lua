-- Vegetation emitter (T11): the wind's debris comes FROM somewhere.
--
-- WindFX already fills a gale with leaves and seeds, but they spawn from
-- a box of air around the player -- causally anonymous. This module makes
-- the vegetation the SOURCE: a leaf lets go from a tree's crown, a seed
-- from a grass tuft, a petal from a flower bed, each at the plant's own
-- cell, so the gust that crosses a tree line visibly strips IT.
--
-- ------- WINDFX'S FIELD, NOT ITS OWN -- THE FLOOR DECIDED
--
-- StepFX took its own field because a footstep makes dust in dead calm
-- and WindFX clears below FLOOR. Vegetation is the opposite case: nothing
-- tears off a plant in still air, so the clear-below-FLOOR contract is
-- not a problem, it is the CORRECT behaviour -- and sharing the field
-- buys the budget, the climate handling, the draw paths and the world
-- pass for free. Emission goes through WindFX.emit (T11's API), marked
-- `veg` so a probe can tell a located leaf from pickKind's generic one.
-- The generic storm leaves STAY: in a gale the air legitimately carries
-- foliage from beyond the screen; this module adds the ones you can see
-- let go.
--
-- ------- WHERE THE PLANTS ARE
--
-- One scan per map change over TileShape's art classes -- the same
-- authored answer the mesher builds geometry from, so a cell reads as a
-- tree exactly when it LOOKS like one: `cylinder`/`canopy` crowns (with
-- their class height, so the leaf starts at the crown and not the roots),
-- `grass` tufts, `flower` beds. Emission then SAMPLES the site lists a
-- few times per pulse instead of iterating them -- a forest map holds
-- hundreds of tree cells and O(attempts) does not care.

local V = ...

local Wind = V.require("Wind")
local WindFX = V.require("WindFX")
local TileShape = V.require("TileShape")
local Quality = V.require("Quality")

local Map = require("src.world.Map")

local VegFX = {}

local rand = math.random

VegFX.EMIT_EVERY = 0.35     -- seconds between emission pulses
VegFX.BURST_AT = 0.70       -- Wind.gust() that strips the trees
VegFX.BURST_WAIT = 3.0      -- seconds between bursts
VegFX.RANGE = 200           -- world px from the player a site may emit
VegFX.SCAN = 64             -- cells scanned per axis from origin

-- petals are the one tint the wind palette does not carry
VegFX.PETAL = { { 0.98, 0.52, 0.55 }, { 0.97, 0.88, 0.90 } }

-- Site lists for the CURRENT map, rebuilt on map change. Public so a
-- probe can check a young leaf against the tree it claims to come from.
VegFX.sites = { mapId = nil, trees = {}, grass = {}, flowers = {} }

local pulse = 0
local burstCool = 0

VegFX.ticks = 0
VegFX.ticksLive = 0
VegFX.lastGate = "never ran"
VegFX.emittedLeaf = 0
VegFX.emittedSeed = 0
VegFX.emittedPetal = 0
VegFX.lastError = nil
VegFX.errorCount = 0

local function game()
  return require("src.core.Game")
end

local function wipe(t)
  for i = #t, 1, -1 do t[i] = nil end
end

local function scan(map)
  local S = VegFX.sites
  wipe(S.trees); wipe(S.grass); wipe(S.flowers)
  S.mapId = map.id
  local ok, shapes = pcall(TileShape.forMap, map)
  if not ok or not shapes then return end
  for cy = 0, VegFX.SCAN - 1 do
    for cx = 0, VegFX.SCAN - 1 do
      if map:inBounds(cx, cy) then
        -- trees and grass answer on the bottom-left collision tile, the
        -- same one every height reader uses
        local tx, ty = cx * 2, cy * 2 + 1
        local okS, s = pcall(TileShape.at, map, shapes,
                             map:tileAt(tx, ty), tx, ty)
        if okS and s and s.art then
          local x, z = cx * 16 + 8, cy * 16 + 8
          if s.art == "cylinder" or s.art == "canopy" then
            S.trees[#S.trees + 1] = { x = x, z = z, h = (s.h and s.h > 4) and s.h or 16 }
          elseif s.art == "grass" then
            S.grass[#S.grass + 1] = { x = x, z = z }
          end
        end
        -- flowers are TILE things, not cell things: Structures places a
        -- bed at tx*8 on whichever of the cell's four 8px tiles carries
        -- the art (Route 1's beds sit off the collision tile, and a
        -- collision-tile scan found zero of them). So ask all four, and
        -- keep the site at the bed's own tile centre.
        for dy = 0, 1 do
          for dx = 0, 1 do
            local ftx, fty = cx * 2 + dx, cy * 2 + dy
            local okF, f = pcall(TileShape.at, map, shapes,
                                 map:tileAt(ftx, fty), ftx, fty)
            if okF and f and f.art == "flower" then
              S.flowers[#S.flowers + 1] = { x = ftx * 8 + 4, z = fty * 8 + 4 }
            end
          end
        end
      end
    end
  end
end

-- one sampled attempt against one site list; returns the site when it is
-- in range of the player, or nil
local function pick(list, px, pz)
  local n = #list
  if n == 0 then return nil end
  local s = list[rand(1, n)]
  if math.abs(s.x - px) > VegFX.RANGE then return nil end
  if math.abs(s.z - pz) > VegFX.RANGE then return nil end
  return s
end

local function shedLeaf(s)
  local tint = WindFX.LEAF[rand(1, #WindFX.LEAF)]
  if WindFX.emit("leaf",
                 s.x + (rand() * 2 - 1) * 6,
                 s.h - 1 - rand() * 4,
                 s.z + (rand() * 2 - 1) * 6,
                 { ttl = 2.2 + rand() * 2.8,
                   size = 0.60 + rand() * 0.80,
                   -- a torn leaf sinks while the wind carries it; the
                   -- ground clamp catches it long before the fade does
                   lift = -(1 + rand() * 4),
                   tint = tint, veg = true }) then
    VegFX.emittedLeaf = VegFX.emittedLeaf + 1
  end
end

local function shedSeed(s)
  local tint = rand() < 0.5 and WindFX.SEED or WindFX.SEED_B
  if WindFX.emit("seed",
                 s.x + (rand() * 2 - 1) * 5,
                 2 + rand() * 3,
                 s.z + (rand() * 2 - 1) * 5,
                 { ttl = 1.8 + rand() * 1.6,
                   size = 0.45 + rand() * 0.55,
                   lift = 1 + rand() * 4,
                   tint = tint, veg = true }) then
    VegFX.emittedSeed = VegFX.emittedSeed + 1
  end
end

local function shedPetal(s)
  local tint = VegFX.PETAL[rand(1, #VegFX.PETAL)]
  if WindFX.emit("seed",
                 s.x + (rand() * 2 - 1) * 5,
                 2 + rand() * 2,
                 s.z + (rand() * 2 - 1) * 5,
                 { ttl = 1.5 + rand() * 1.4,
                   size = 0.40 + rand() * 0.45,
                   lift = 0.5 + rand() * 3,
                   spin = (rand() * 2 - 1) * 5,
                   tint = tint, veg = true }) then
    VegFX.emittedPetal = VegFX.emittedPetal + 1
  end
end

local function updateBody(dt, voxelOn)
  VegFX.ticks = VegFX.ticks + 1
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
  burstCool = burstCool - dt

  local Game = game()
  local ow = Game and Game.overworld
  local amount = Wind.amount()
  local live = voxelOn and ow and ow.map and ow.player
               and Map.isOutdoor(ow.map.def)
               and Game.stack and Game.stack:top() == ow
               and not ow.transitioning
               and amount > WindFX.FLOOR
  if not live then
    VegFX.lastGate =
      (not voxelOn and "voxelOn=false")
      or (not (ow and ow.map and ow.player) and "no overworld/map/player")
      or (not Map.isOutdoor(ow.map.def) and "indoors")
      or (not (Game.stack and Game.stack:top() == ow) and "overworld not on top")
      or (ow.transitioning and "map transitioning")
      or (amount <= WindFX.FLOOR and "wind below FLOOR")
      or "unknown"
    return
  end
  VegFX.lastGate = "live"
  VegFX.ticksLive = VegFX.ticksLive + 1

  if VegFX.sites.mapId ~= ow.map.id then scan(ow.map) end
  local S = VegFX.sites
  local p = ow.player
  local px, pz = (p.px or 0) + 8, (p.py or 0) + 8

  -- the gust that strips the tree line: a handful of leaves let go at
  -- once, from real crowns, on the same envelope the WindFX front rides
  if Wind.gust() >= VegFX.BURST_AT and burstCool <= 0 and #S.trees > 0 then
    burstCool = VegFX.BURST_WAIT
    for _ = 1, 5 + rand(0, 3) do
      local s = pick(S.trees, px, pz)
      if s then shedLeaf(s) end
    end
  end

  pulse = pulse + dt
  if pulse < VegFX.EMIT_EVERY then return end
  pulse = pulse - VegFX.EMIT_EVERY

  -- chance climbs with how hard the air pulls; the PFX row scales it the
  -- way it scales every other particle budget
  local wind01 = (amount - WindFX.FLOOR) / 1.8
  if wind01 < 0 then wind01 = 0 elseif wind01 > 1 then wind01 = 1 end
  local mul = Quality.particles()
  if mul > 2 then mul = 2 end     -- MAX doubles the shed, not x4 -- a
                                  -- gale is already a gale
  for _ = 1, 2 do
    if rand() < 0.55 * wind01 * mul then
      local s = pick(S.trees, px, pz)
      if s then shedLeaf(s) end
    end
    if rand() < 0.45 * wind01 * mul then
      local s = pick(S.grass, px, pz)
      if s then shedSeed(s) end
    end
  end
  if rand() < 0.30 * wind01 * mul then
    local s = pick(S.flowers, px, pz)
    if s then shedPetal(s) end
  end
end

function VegFX.update(dt, voxelOn)
  local ok, err = pcall(updateBody, dt, voxelOn)
  if ok then return end
  VegFX.errorCount = VegFX.errorCount + 1
  VegFX.lastError = tostring(err)
end

return VegFX
