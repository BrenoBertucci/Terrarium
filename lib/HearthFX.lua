-- Chimney smoke: the houses breathe (the HEARTH row).
--
-- Every house in Kanto has had a stove going since 1996 and not one of
-- them has ever shown it. The premium building kit already stands a
-- chimney on a roof when a template asks for one (lib/Buildings.lua, F1)
-- -- until now only the Center's rooftop ball ever asked. The house
-- family asks now (data/voxel_heights.lua), and this module puts smoke
-- on it: a chain of cel puffs that climbs off the stack, slows as it
-- cools, takes whatever wind there is and thins into nothing.
--
-- ------- WHO HAS A FIRE GOING
--
-- Not every house, and not all day. Each chimney holds a stable number
-- from a hash of the house's own place (map, tile) -- the same trick the
-- INDOOR row picks its sleepers by, so the same houses always light
-- first. Against it stands one figure, HearthFX.hearth(): how many of the
-- town's hearths are lit RIGHT NOW. It rises with the meals of the day
-- (dusk highest, dawn next, a little through the night, almost none at
-- noon) and with the cold (winter on the SYNC calendar, snow falling or
-- lying, a wet evening). A chimney smokes while its number is under that
-- figure -- so as the evening comes on, the town lights up house by
-- house, always in the same order.
--
-- ------- ITS OWN FIELD, LIKE THE FOOTSTEP DUST
--
-- WindFX clears its field the moment the wind drops under FLOOR, and a
-- chimney smokes hardest in a dead calm. So this owns a small field of
-- the shared solver (lib/Particles.lua) and shares everything else: the
-- same air (Wind.flowAt / turbAt through the same ctx shape StepFX
-- hands in), the same scene-pass draw (ParticleMesh + Voxel3D
-- .drawParticles). What the solver does not do -- and deliberately, see
-- its header -- is vertical physics, so the climb is this module's: a
-- lift that dies with the puff's age, squared, the way a warm plume
-- loses its heat.
--
-- ------- THE PUFF
--
-- Generated at load, not shipped: a 16x16 cloud in the two tones the
-- Pimen wet puff already speaks (a body, and a darker underside), with a
-- hard silhouette and no gradient -- the grey stamps the wind used to
-- throw about were rejected by name, and a chimney is not the air, it is
-- a THING standing on a house. The card grows with age (a puff spreads as
-- it cools) and is drawn with depth WRITES off, after the cutout
-- particles, because smoke is translucent and must not file a depth that
-- hides the roof it is drifting past. The scene shader still lights it,
-- tints it by the hour and casts the sun's shadow on it like everything
-- else in the pass.

local V = ...

local Particles = V.require("Particles")
local ParticleMesh = V.require("ParticleMesh")
local ModSetting = V.require("ModSetting")
local Wind = V.require("Wind")
local WindFX = V.require("WindFX")
local Weather = V.require("Weather")
local DayNight = V.require("DayNight")
local GroundFX = V.require("GroundFX")
local Quality = V.require("Quality")
local Voxel3D = V.require("Voxel3D")
local Structures = V.require("Structures")

local Map = require("src.world.Map")

local HearthFX = {}

local rand = math.random
local floor = math.floor

HearthFX.setting = ModSetting.new("hearth", "HEARTH",
                                  { "on", "off" }, { "ON", "OFF" })

function HearthFX.enabled()
  local ok, v = pcall(HearthFX.setting.get, HearthFX.setting)
  if not ok then return true end
  return v ~= "off"
end

-- Smoke is light and takes the air readily (tau ~0.03s), but not as a
-- leaf does: it is a volume, not a sail, and reads as sliding rather than
-- dancing. Clamps are relative to the ground under the puff and are set
-- so they never bite -- a puff lives above a roof and climbs on its own.
HearthFX.KINDS = {
  smoke = { speed = 0.45, bob = 1.4, lowClamp = 0, highClamp = 600,
            curlA = 0.16, curlB = 0.08, mass = 0.22, area = 1.30 },
}

HearthFX.MAX = 128           -- hard field cap; PFX scales the RATE, not this
HearthFX.REACH = 14          -- cells from the player a chimney may smoke within
HearthFX.PUFF_EVERY = 0.7    -- seconds between puffs off one stack, at PFX ON
HearthFX.LIFE = 5.2          -- seconds a puff lasts, before its own +-20%
HearthFX.LIFT = 24           -- initial climb; the solver applies its 0.55
HearthFX.SIZE0 = 2.2         -- card half-extent at birth, world px
HearthFX.SIZE1 = 6.0         -- and at death: a puff spreads as it cools
HearthFX.ALPHA = 0.84
-- Body tints, multiplied by the two tones baked into the cloud. Dry air
-- gets a warm grey; snow and the winter calendar a near-white (cold air,
-- and a whiter fire); rain a heavier grey, because wet smoke hangs.
HearthFX.TINT = {
  dry  = { 0.86, 0.86, 0.88 },
  snow = { 0.94, 0.95, 0.97 },
  rain = { 0.72, 0.74, 0.78 },
}

local field = Particles.newField(HearthFX.KINDS, HearthFX.MAX)
local ctx = {}
local builder = nil
local imgs = nil

-- The instruments, same contract as every module in the chain: a throw in
-- update or draw is caught, counted and named, never allowed to take the
-- pipeline down.
HearthFX.ticks = 0
HearthFX.ticksLive = 0
HearthFX.lastGate = "never ran"
HearthFX.emitted = 0
HearthFX.lastBatches = -1
HearthFX.lastChimneys = 0    -- chimneys the map's structure cache holds
HearthFX.lastLit = 0         -- of which have a fire going this tick
HearthFX.lastHearth = 0      -- the figure they were held against
HearthFX.clock = 0           -- seconds of live ticks, on the hook's own dt:
                             -- the denominator every rate here is against
HearthFX.lastError = nil
HearthFX.errorCount = 0
HearthFX.drawError = nil
HearthFX.drawErrors = 0

-- Probes: light every chimney regardless of the hour and the hash.
HearthFX.force = nil

function HearthFX.count() return field:count() end
function HearthFX.get(i) return field:get(i) end

local function game()
  return require("src.core.Game")
end

local function clamp01(v)
  if v < 0 then return 0 elseif v > 1 then return 1 end
  return v
end

-- ------- the hash (lib/Interiors.lua's, for the same reason it is there:
-- stable across sessions and machines, exact in a double, no bit library)
local function hash(text)
  local h = 5381
  for i = 1, #text do
    h = (h * 33 + text:byte(i)) % 2147483647
  end
  return h
end

local function unit(h) return (floor(h / 977) % 100000) / 100000 end

-- ------- HOW MANY OF THE TOWN'S HEARTHS ARE LIT RIGHT NOW, 0..1
--
-- Overridable, so a probe can hold the town at "everyone" or "no one"
-- without pinning the clock, the calendar and the weather all at once.
HearthFX.hearth = function()
  local okM, mix = pcall(DayNight.mix, DayNight.time())
  if not okM or type(mix) ~= "table" then mix = { day = 1 } end
  -- the meals: supper lights nearly everyone, breakfast about half,
  -- the night keeps the banked fires going, noon almost nobody
  local meal = (mix.dawn or 0) * 0.55 + (mix.day or 0) * 0.10
             + (mix.dusk or 0) * 0.90 + (mix.night or 0) * 0.65
  -- and the cold, which lights the rest whatever the hour
  local cold = 0
  local okW, winter = pcall(Weather.isWinter)
  if okW and winter then cold = 0.75 end
  local okF, kind, power = pcall(Weather.falling)
  if okF and kind == "snow" then
    cold = math.max(cold, 0.65 + 0.35 * (tonumber(power) or 0))
  elseif okF and kind == "rain" then
    cold = math.max(cold, 0.40 * (tonumber(power) or 0))
  end
  local okC, cover = pcall(GroundFX.cover)
  if okC and tonumber(cover) then cold = math.max(cold, cover * 0.9) end
  return clamp01(math.max(meal, cold))
end

-- The chimneys the current map's structure cache stands, or nil before
-- the scene has built it (Structures.peek never builds).
function HearthFX.chimneys()
  local Game = game()
  local ow = Game and Game.overworld
  local map = ow and ow.map
  local S = map and Structures.peek and Structures.peek(map)
  return S and S.chimneys or nil
end

local function tintFor()
  local okV, kind = pcall(Weather.visible)
  if okV and kind == "snow" then return HearthFX.TINT.snow end
  if okV and kind == "rain" then return HearthFX.TINT.rain end
  local okW, winter = pcall(Weather.isWinter)
  if okW and winter then return HearthFX.TINT.snow end
  return HearthFX.TINT.dry
end

-- ------- ONE PUFF OFF A STACK
local function puff(c, gust, kind, power)
  if field:full() then return end
  local m = field:claim()
  if not m then return end
  local wet = (kind == "rain") and (tonumber(power) or 0) or 0
  m.kind = "smoke"
  m.x = c.x + (rand() * 2 - 1) * 0.8
  m.z = c.z + (rand() * 2 - 1) * 0.8
  m.y = c.y + 0.5
  m.t = 0
  -- rain shortens a plume (wet smoke falls back), a gale tears it flat
  m.ttl = HearthFX.LIFE * (0.8 + rand() * 0.4) * (1 - 0.3 * wet)
  m.seed = rand() * 6.2831
  m.fast = 0.8 + rand() * 0.4
  m.lift0 = HearthFX.LIFT * (0.85 + rand() * 0.3) * (1 - 0.4 * wet)
            / (1 + 0.8 * (gust or 0))
  m.lift = m.lift0
  m.spin = (rand() * 2 - 1) * 0.25
  m.ang = (rand() - 0.5) * 0.4
  m.size = 0.85 + rand() * 0.3
  m.variant = (rand() < 0.5) and 1 or 2
  HearthFX.emitted = HearthFX.emitted + 1
end

local function updateBody(dt, voxelOn)
  HearthFX.ticks = HearthFX.ticks + 1
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end

  local Game = game()
  local ow = Game and Game.overworld
  local live = voxelOn and HearthFX.enabled() and ow and ow.map and ow.player
               and Map.isOutdoor(ow.map.def)
               and Game.stack and Game.stack:top() == ow
               and not ow.transitioning
  if not live then
    HearthFX.lastGate =
      (not voxelOn and "voxelOn=false")
      or (not HearthFX.enabled() and "HEARTH off")
      or (not (ow and ow.map and ow.player) and "no overworld/map/player")
      or (not Map.isOutdoor(ow.map.def) and "indoors")
      or (not (Game.stack and Game.stack:top() == ow) and "overworld not on top")
      or (ow.transitioning and "map transitioning")
      or "unknown"
    field:clear()
    return
  end
  HearthFX.lastGate = "live"
  HearthFX.ticksLive = HearthFX.ticksLive + 1
  HearthFX.clock = HearthFX.clock + dt

  local map = ow.map
  local list = HearthFX.chimneys()
  HearthFX.lastChimneys = list and #list or 0

  local p = ow.player
  local px, pz = (p.px or 0) + 8, (p.py or 0) + 8
  local lit = HearthFX.hearth()
  HearthFX.lastHearth = lit

  -- PFX scales the rate like every other budget in the mod; MAX is
  -- capped at twice ON here, because a chimney that fogged the street
  -- would read as a fire, not a stove
  local mul = Quality.particles()
  if mul > 2 then mul = 2 end
  if mul <= 0 then mul = 0.4 end
  local every = HearthFX.PUFF_EVERY / mul

  local gust = Wind.gust()
  local kind, power = Weather.falling()
  local range = HearthFX.REACH * 16
  local litN = 0
  if list then
    for i = 1, #list do
      local c = list[i]
      if c.u == nil then
        c.u = unit(hash(tostring(map.id) .. ":" .. c.tx .. "," .. c.ty))
      end
      local on = HearthFX.force or (c.u < lit)
      c.lit = on or false
      if on then
        litN = litN + 1
        local dx, dz = c.x - px, c.z - pz
        if dx < 0 then dx = -dx end
        if dz < 0 then dz = -dz end
        if dx <= range and dz <= range then
          -- the first puff comes at a random point of the period, so a
          -- street of stacks does not breathe in step
          c.next = (c.next or (rand() * every)) - dt
          if c.next <= 0 then
            c.next = every * (0.75 + rand() * 0.5)
            puff(c, gust, kind, power)
          end
        else
          c.next = nil
        end
      end
    end
  end
  HearthFX.lastLit = litN

  local n = field:count()
  if n > 0 then
    -- the climb dies with age, squared: hot at the mouth, adrift by the end
    for i = 1, n do
      local m = field:get(i)
      local k = m.t / (m.ttl or 1)
      if k > 1 then k = 1 end
      m.lift = (m.lift0 or 0) * (1 - k) * (1 - k)
    end
    local amount = Wind.amount()
    ctx.dirX = Wind.DIR[1] or 1
    ctx.dirZ = Wind.DIR[2] or 0
    -- the same air at the same conversion WindFX uses; dead calm gives
    -- speed 0 and the column stands straight up
    ctx.speed = amount * WindFX.SPEED
    ctx.turbulence = amount * WindFX.SPEED * WindFX.TURB * 0.7
    ctx.floorAt = WindFX.groundAt
    ctx.originX = px
    ctx.originZ = pz
    ctx.reach = (HearthFX.REACH + 3) * 16
    field:step(dt, ctx)
  end
end

function HearthFX.update(dt, voxelOn)
  local ok, err = pcall(updateBody, dt, voxelOn)
  if ok then return end
  HearthFX.errorCount = HearthFX.errorCount + 1
  HearthFX.lastError = tostring(err)
end

-- ------- THE CLOUD, DRAWN ONCE AT LOAD
--
-- A union of discs on a 16x16 grid, filled in three tones: 1.0 for the
-- body, 0.80 under the waist (the shadow a lit cloud keeps on its
-- underside) and 0.55 along the rim, the one-voxel outline everything
-- cel in this mod wears so it reads against any sky. Alpha is 1 inside
-- and 0 out -- the scene shader discards under half alpha, so a soft edge
-- would be cut to a hard one anyway, and this way the silhouette is
-- authored rather than an accident.
local CLOUDS = {
  { { 8.0, 8.5, 5.2 }, { 4.5, 10.0, 3.2 }, { 11.5, 10.0, 3.2 }, { 7.5, 5.0, 3.0 } },
  { { 7.0, 9.0, 4.6 }, { 11.0, 8.0, 3.4 }, { 3.5, 10.5, 2.8 }, { 9.0, 4.5, 2.6 },
    { 12.5, 11.5, 2.2 } },
}
HearthFX.CLOUD_SIZE = 16
HearthFX.UNDERSIDE = 0.80
HearthFX.RIM = 0.55

local function makeCloud(spec)
  local W = HearthFX.CLOUD_SIZE
  if not (love.image and love.graphics) then return nil end
  local ok, data = pcall(love.image.newImageData, W, W)
  if not ok then return nil end
  local inside = {}
  local function within(x, y)
    if x < 0 or y < 0 or x >= W or y >= W then return false end
    return inside[y * W + x] or false
  end
  for y = 0, W - 1 do
    for x = 0, W - 1 do
      local hit = false
      for i = 1, #spec do
        local c = spec[i]
        local dx, dy = x + 0.5 - c[1], y + 0.5 - c[2]
        if dx * dx + dy * dy <= c[3] * c[3] then hit = true break end
      end
      inside[y * W + x] = hit
    end
  end
  for y = 0, W - 1 do
    for x = 0, W - 1 do
      if inside[y * W + x] then
        local tone = (y >= 10) and HearthFX.UNDERSIDE or 1.0
        -- the rim: a filled texel with open air on any side
        if not (within(x - 1, y) and within(x + 1, y)
                and within(x, y - 1) and within(x, y + 1)) then
          tone = HearthFX.RIM
        end
        data:setPixel(x, y, tone, tone, tone, 1)
      end
    end
  end
  local okI, img = pcall(love.graphics.newImage, data)
  if not okI then return nil end
  pcall(img.setFilter, img, "nearest", "nearest")
  return img
end

local function loadImgs()
  if imgs ~= nil then return imgs or nil end
  local a = makeCloud(CLOUDS[1])
  local b = makeCloud(CLOUDS[2])
  if not (a or b) then imgs = false return nil end
  imgs = { a or b, b or a }
  return imgs
end

-- Exposed for the probe: the cloud image of a variant, as the draw sees it.
function HearthFX.cloud(variant)
  local set = loadImgs()
  return set and set[variant or 1] or nil
end

local tint = HearthFX.TINT.dry

local function describe(m)
  local set = imgs
  local img = set and (set[m.variant or 1] or set[1]) or nil
  if not img then return nil end
  local k = m.t / (m.ttl or 1)
  -- fast in (it is already smoke when it leaves the flue), long thin-out
  local fade = math.min(1, m.t * 4, (1 - k) / 0.45)
  local a = HearthFX.ALPHA * fade
  if a <= 0.03 then return nil end
  local hw = (HearthFX.SIZE0 + (HearthFX.SIZE1 - HearthFX.SIZE0) * k)
             * (m.size or 1)
  local hh = hw * 0.85
  return img, 0, 0, 1, 1, hw, hh, m.ang or 0, tint[1], tint[2], tint[3], a
end

local function drawWorldBody()
  local live = field:count()
  if live == 0 then HearthFX.lastBatches = 0 return 0 end
  if not loadImgs() then HearthFX.lastBatches = 0 return 0 end
  builder = builder or ParticleMesh.newBuilder(HearthFX.MAX)
  tint = tintFor()
  local mesh, batches = builder:build(field, describe)
  if not mesh then HearthFX.lastBatches = 0 return 0 end
  -- translucent: alpha blend, depth TEST on, depth WRITE off
  local g = love.graphics
  local pm, pa = g.getBlendMode()
  g.setBlendMode("alpha")
  local drew = Voxel3D.drawParticles(mesh, nil, batches, false)
  g.setBlendMode(pm, pa)
  HearthFX.lastBatches = drew
  return drew
end

function HearthFX.drawWorld()
  local ok, err = pcall(drawWorldBody)
  if ok then return err or 0 end
  HearthFX.drawErrors = HearthFX.drawErrors + 1
  HearthFX.drawError = "drawWorld: " .. tostring(err)
  return 0
end

return HearthFX
