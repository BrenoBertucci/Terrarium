-- Water spray emitter (T12): wind over water tears mist off the shore.
--
-- The third content emitter, on VegFX's mould: sites scanned once per
-- map, emission SAMPLED a few times per pulse, gust bursts, and the
-- motes live in WindFX's field through WindFX.emit -- spray without wind
-- is not a thing, so the clear-below-FLOOR contract fits here exactly as
-- it fit the vegetation.
--
-- ------- WHAT MAKES THIS ONE DIFFERENT: THE WATER KNOWS ITS SIZE
--
-- WaterBody.sizeAt answers "how big is the water under this pixel"
-- (1 open sea .. 0 the smallest puddle) -- the field built precisely so
-- a pond stops inheriting the ocean's swell. Here it is the emission
-- probability itself: Vermilion's harbour whips spray in a gale, the
-- fountain pond in a town does not, and no per-map tuning exists
-- anywhere. Queried live per attempt, because the bake refreshes with
-- the neighbourhood and a cached size would survive a map change.
--
-- ------- SITES ARE THE SHORE BAND
--
-- A water cell with at least one land 4-neighbour. That is where the
-- player looks (beaches, banks) and where the size field transitions;
-- open-water whitecaps beyond the band are left to the day the wind
-- fetch sweep exists (see WaterBody's own header). Each site keeps the
-- mean direction toward its land neighbours -- not as an emission gate
-- (spray tears off a crest whatever the bearing and the AIR decides
-- where it goes) but so a probe can step inland from a site it found.
--
-- ------- CACHOEIRA: DESCOPADA, COM MOTIVO
--
-- The plan said "cachoeira/margem". No tile class, no map flag and no
-- module in this mod knows what a waterfall is (grep: zero hits), Gen 1
-- has a handful of waterfall tiles in places this camera barely visits,
-- and mist in dead calm would need its own field besides. The shore is
-- the everyday feature; the waterfall waits for a reason to exist.

local V = ...

local Wind = V.require("Wind")
local WindFX = V.require("WindFX")
local Water = V.require("Water")
local WaterBody = V.require("WaterBody")
local Quality = V.require("Quality")

local Map = require("src.world.Map")

local SprayFX = {}

local rand = math.random

SprayFX.EMIT_EVERY = 0.35
SprayFX.BURST_AT = 0.70
SprayFX.BURST_WAIT = 2.5
SprayFX.RANGE = 200
SprayFX.SCAN = 64

-- Shore sites for the current map; public for probes.
SprayFX.sites = { mapId = nil, shore = {} }

local pulse = 0
local burstCool = 0

SprayFX.ticks = 0
SprayFX.ticksLive = 0
SprayFX.lastGate = "never ran"
SprayFX.emitted = 0
SprayFX.lastError = nil
SprayFX.errorCount = 0

local function game()
  return require("src.core.Game")
end

local function scan(map)
  local S = SprayFX.sites
  for i = #S.shore, 1, -1 do S.shore[i] = nil end
  S.mapId = map.id
  local function water(cx, cy)
    local ok, w = pcall(map.isWaterCell, map, cx, cy)
    return ok and w or false
  end
  for cy = 0, SprayFX.SCAN - 1 do
    for cx = 0, SprayFX.SCAN - 1 do
      if map:inBounds(cx, cy) and water(cx, cy) then
        local nx, nz = 0, 0
        if not water(cx + 1, cy) then nx = nx + 1 end
        if not water(cx - 1, cy) then nx = nx - 1 end
        if not water(cx, cy + 1) then nz = nz + 1 end
        if not water(cx, cy - 1) then nz = nz - 1 end
        if nx ~= 0 or nz ~= 0 then
          local l = math.sqrt(nx * nx + nz * nz)
          S.shore[#S.shore + 1] = {
            x = cx * 16 + 8, z = cy * 16 + 8,
            nx = nx / l, nz = nz / l,
          }
        end
      end
    end
  end
end

local function surfaceAt(x, z)
  local ok, y = pcall(Water.surfaceAt, x, z)
  if ok and tonumber(y) then return y end
  return 0
end

-- The size that matters is OFFSHORE, not at the site: WaterBody's fetch
-- dies into every shoreline by design ("a big lake still calms at its
-- edges"), so sampled AT the band, Pallet's sea sliver and a town pond
-- read the same 0.1 -- measured, and the size law flattened out. And
-- not a step offshore either: fetch01 is CELLS/10, so at 1.5 cells out
-- every body on the game reads ~0.15-0.23 alike -- also measured. Four
-- cells is where the bodies part: open sea has that much fetch and
-- climbs toward 0.5, while a town pond does not have four cells of
-- water in it ANYWHERE -- the sample lands past its far bank on calm
-- land, which is the honest physics: no fetch, no whitecaps.
SprayFX.OFFSHORE = 64

-- The sites near the player, rebuilt per pulse. Sampling the whole map's
-- list and range-checking after LOOKED equivalent and was not: on Route
-- 19 five of every eight picks landed on far shores and died, and the
-- sea emitted like a pond -- the rate near the player depended on how
-- much shore existed AWAY from them. A few hundred cheap checks per
-- pulse buy a rate that is about the shore in front of you.
local near = {}
local function buildNear(px, pz)
  local list = SprayFX.sites.shore
  local c = 0
  for i = 1, #list do
    local s = list[i]
    if math.abs(s.x - px) <= SprayFX.RANGE
       and math.abs(s.z - pz) <= SprayFX.RANGE then
      c = c + 1
      near[c] = s
    end
  end
  for i = #near, c + 1, -1 do near[i] = nil end
  return c
end

-- one sampled attempt against the near list, weighted by how big the
-- water FEEDING the site is. Returns the site or nil.
local function pick()
  local n = #near
  if n == 0 then return nil end
  local s = near[rand(1, n)]
  local size = WaterBody.sizeAt(s.x - s.nx * SprayFX.OFFSHORE,
                                s.z - s.nz * SprayFX.OFFSHORE)
  if rand() >= size then return nil end     -- a pond never gets this far
  return s
end

local function whip(s)
  if WindFX.emit("spray",
                 s.x + (rand() * 2 - 1) * 4,
                 surfaceAt(s.x, s.z) + 0.5 + rand() * 1.5,
                 s.z + (rand() * 2 - 1) * 4,
                 { ttl = 0.7 + rand() * 0.9,
                   size = 0.40 + rand() * 0.45,
                   lift = 3 + rand() * 6,
                   tint = WindFX.SPRAY, src = "water" }) then
    SprayFX.emitted = SprayFX.emitted + 1
  end
end

local function updateBody(dt, voxelOn)
  SprayFX.ticks = SprayFX.ticks + 1
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
    SprayFX.lastGate =
      (not voxelOn and "voxelOn=false")
      or (not (ow and ow.map and ow.player) and "no overworld/map/player")
      or (not Map.isOutdoor(ow.map.def) and "indoors")
      or (not (Game.stack and Game.stack:top() == ow) and "overworld not on top")
      or (ow.transitioning and "map transitioning")
      or (amount <= WindFX.FLOOR and "wind below FLOOR")
      or "unknown"
    return
  end
  SprayFX.lastGate = "live"
  SprayFX.ticksLive = SprayFX.ticksLive + 1

  if SprayFX.sites.mapId ~= ow.map.id then scan(ow.map) end
  if #SprayFX.sites.shore == 0 then return end
  local p = ow.player
  local px, pz = (p.px or 0) + 8, (p.py or 0) + 8

  -- a gust whips the crests: several sprays at once, still weighted by
  -- each site's own water size, so a gale over a pond stays a gale over
  -- a pond
  if Wind.gust() >= SprayFX.BURST_AT and burstCool <= 0 then
    burstCool = SprayFX.BURST_WAIT
    if buildNear(px, pz) > 0 then
      for _ = 1, 4 + rand(0, 2) do
        local s = pick()
        if s then whip(s) end
      end
    end
  end

  pulse = pulse + dt
  if pulse < SprayFX.EMIT_EVERY then return end
  pulse = pulse - SprayFX.EMIT_EVERY

  if buildNear(px, pz) == 0 then return end
  local wind01 = (amount - WindFX.FLOOR) / 1.8
  if wind01 < 0 then wind01 = 0 elseif wind01 > 1 then wind01 = 1 end
  local mul = Quality.particles()
  if mul > 2 then mul = 2 end
  for _ = 1, 3 do
    if rand() < 0.60 * wind01 * mul then
      local s = pick()
      if s then whip(s) end
    end
  end
end

function SprayFX.update(dt, voxelOn)
  local ok, err = pcall(updateBody, dt, voxelOn)
  if ok then return end
  SprayFX.errorCount = SprayFX.errorCount + 1
  SprayFX.lastError = tostring(err)
end

return SprayFX
