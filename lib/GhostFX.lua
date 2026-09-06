-- Voxel world mode: what the tower of graves breathes out (the HAUNT row).
--
-- Lavender's Pokemon Tower stands as a tower now (lib/TowerKit.lua), and
-- its glass burns cold after dark (the HAUNTED GLASS block in Voxel3D).
-- This module is the third part of the same idea, and the only one that
-- moves: pale wisps that slip out of the lantern storey's windows, the
-- portal's mouth and the spire, climb a little, drift on whatever air
-- there is and thin into the violet haze. Only after dark -- the same
-- curve that lights the town's windows (DayNight.windowLight) is how
-- restless the tower is -- and only within reach of the player, like
-- every field in the mod.
--
-- ------- WHERE THEY COME FROM
--
-- Buildings.stamp records a TowerKit model's `haunt` on the map's
-- structure cache (S.haunts): the box its cold glass burns in and a list
-- of `wisps` sources in world space, each tagged lantern / portal / spire.
-- The lantern storey is most of the breath, the portal a little, the
-- spire a rare one. Nothing here knows a tower from any other haunted
-- thing: a second model that reports a `haunt` breathes the same way.
--
-- ------- ITS OWN FIELD, LIKE THE SMOKE
--
-- Same shape as lib/HearthFX.lua and for the same reasons: a small pool of
-- the shared solver (lib/Particles.lua), the shared air (Wind.flowAt /
-- turbAt through the same ctx StepFX hands in), the same scene-pass draw
-- (ParticleMesh + Voxel3D.drawParticles), and the climb this module's own
-- -- the solver deliberately does no vertical physics. A wisp is light: it
-- takes eddies readily (mass 0.05) but only a third of the wind's speed,
-- because a thing that is barely there should hang rather than blow away.
--
-- ------- THE WISP
--
-- Generated at load, not shipped: a 12x12 teardrop in three tones (a hot
-- core, a body, the one-texel rim every cel thing in this mod wears), hard
-- silhouette, alpha 1 inside and 0 out -- the scene shader discards under
-- half alpha, so a soft edge would be cut hard anyway. Two cards per wisp,
-- the firefly's own trick (lib/AmbientLife.lua): the teardrop itself, and
-- a HALO -- the same card two and a half times the size at a quarter of
-- the alpha -- which is what makes a small thing read as a light rather
-- than a speck. The card is taller than wide and grows a little as it
-- ages, its alpha pulsing on its own phase so a cluster does not glow in
-- step. Drawn flattened toward GLOW (Voxel3D.flatten) so the night's tint
-- cannot put it out, alpha-blended with depth WRITES off after the cutout
-- particles, like the smoke: a wisp is translucent and must not file a
-- depth that hides the roof behind it.

local V = ...

local Particles = V.require("Particles")
local ParticleMesh = V.require("ParticleMesh")
local ModSetting = V.require("ModSetting")
local Wind = V.require("Wind")
local WindFX = V.require("WindFX")
local DayNight = V.require("DayNight")
local Quality = V.require("Quality")
local Voxel3D = V.require("Voxel3D")
local Structures = V.require("Structures")

local Map = require("src.world.Map")

local GhostFX = {}

local rand = math.random
local floor = math.floor
local sin = math.sin

GhostFX.setting = ModSetting.new("haunt", "HAUNT",
                                 { "on", "off" }, { "ON", "OFF" })

function GhostFX.enabled()
  local ok, v = pcall(GhostFX.setting.get, GhostFX.setting)
  if not ok then return true end
  return v ~= "off"
end

-- A wisp hangs: a third of the wind's speed, eddies taken in full (the
-- lightest mass in the mod), a wide slow wander. Clamps are relative to
-- the ground under it and never bite -- it lives up a tower.
GhostFX.KINDS = {
  wisp = { speed = 0.16, bob = 2.4, lowClamp = 0, highClamp = 900,
           curlA = 0.55, curlB = 0.30, mass = 0.05, area = 1.0 },
}

GhostFX.MAX = 40             -- hard field cap; PFX scales the RATE, not this
GhostFX.REACH = 22           -- cells from the player a haunt may breathe within
GhostFX.EVERY = 0.45         -- seconds between wisps off one haunt, at PFX ON
GhostFX.LIFE = 8.0           -- seconds a wisp lasts, before its own +-20%
GhostFX.LIFT = 10            -- initial climb; the solver applies its 0.55
GhostFX.HOVER = 1.4          -- the climb it keeps once the first is spent
GhostFX.SIZE0 = 3.0          -- card half-width at birth, world px
GhostFX.SIZE1 = 6.5          -- and once grown
GhostFX.ALPHA = 1.0
GhostFX.HALO = 2.5           -- the halo card, as a multiple of the core's size
GhostFX.HALO_ALPHA = 0.28    -- and its share of the core's alpha
GhostFX.TINT = { 0.92, 0.94, 1.0 }
-- A wisp GLOWS: it is drawn flattened most of the way toward this colour
-- (Voxel3D.flatten), which is what keeps the night's tint -- the thing
-- every other card in the scene rightly wears -- from putting it out. The
-- remainder keeps the card's own three tones showing through.
GhostFX.GLOW = { 0.86, 0.96, 1.0 }
GhostFX.FLAT = 0.92
GhostFX.NIGHT_MIN = 0.20     -- windowLight under which the tower is quiet
-- how the breath is shared between a haunt's sources, by kind
GhostFX.WEIGHT = { lantern = 1.0, portal = 0.35, spire = 0.15 }

local field = Particles.newField(GhostFX.KINDS, GhostFX.MAX)
local ctx = {}
local builder = nil
local img = nil

-- The instruments, same contract as every module in the chain: a throw in
-- update or draw is caught, counted and named, never allowed to take the
-- pipeline down.
GhostFX.ticks = 0
GhostFX.ticksLive = 0
GhostFX.lastGate = "never ran"
GhostFX.emitted = 0
GhostFX.lastBatches = -1
GhostFX.lastHaunts = 0       -- haunts the map's structure cache holds
GhostFX.lastNight = 0        -- the window-light figure they breathed against
GhostFX.clock = 0
GhostFX.lastError = nil
GhostFX.errorCount = 0
GhostFX.drawError = nil
GhostFX.drawErrors = 0

-- Probes: breathe whatever the hour.
GhostFX.force = nil

function GhostFX.count() return field:count() end
function GhostFX.get(i) return field:get(i) end

local function game()
  return require("src.core.Game")
end

-- The haunts the current map's structure cache stands, or nil before the
-- scene has built it (Structures.peek never builds).
function GhostFX.haunts()
  local Game = game()
  local ow = Game and Game.overworld
  local map = ow and ow.map
  local S = map and Structures.peek and Structures.peek(map)
  return S and S.haunts or nil
end

-- One source of a haunt, drawn by kind weight.
local function pickSource(h)
  local list = h.wisps
  if not list or #list == 0 then return nil end
  if h.weightSum == nil then
    local sum = 0
    for i = 1, #list do
      sum = sum + (GhostFX.WEIGHT[list[i].kind] or 0.5)
    end
    h.weightSum = sum
  end
  local r = rand() * h.weightSum
  for i = 1, #list do
    r = r - (GhostFX.WEIGHT[list[i].kind] or 0.5)
    if r <= 0 then return list[i] end
  end
  return list[#list]
end

-- ------- ONE WISP OUT OF A SOURCE
local function wisp(src)
  if field:full() then return end
  local m = field:claim()
  if not m then return end
  m.kind = "wisp"
  m.x = src.x + (rand() * 2 - 1) * 1.5
  m.z = src.z + (rand() * 2 - 1) * 1.5
  m.y = src.y + (rand() * 2 - 1) * 1.0
  m.t = 0
  m.ttl = GhostFX.LIFE * (0.8 + rand() * 0.4)
  m.seed = rand() * 6.2831
  m.fast = 0.7 + rand() * 0.5
  -- the portal's breath crawls out low and slow; the spire's leaps
  local k = src.kind
  local lift = GhostFX.LIFT * (0.85 + rand() * 0.3)
  if k == "portal" then lift = lift * 0.6 end
  if k == "spire" then lift = lift * 1.4 end
  m.lift0 = lift
  m.lift = lift
  m.spin = (rand() * 2 - 1) * 0.3
  m.ang = (rand() - 0.5) * 0.3
  m.size = 0.8 + rand() * 0.45
  GhostFX.emitted = GhostFX.emitted + 1
end

local function updateBody(dt, voxelOn)
  GhostFX.ticks = GhostFX.ticks + 1
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end

  local Game = game()
  local ow = Game and Game.overworld
  local live = voxelOn and GhostFX.enabled() and ow and ow.map and ow.player
               and Map.isOutdoor(ow.map.def)
               and Game.stack and Game.stack:top() == ow
               and not ow.transitioning
  if not live then
    GhostFX.lastGate =
      (not voxelOn and "voxelOn=false")
      or (not GhostFX.enabled() and "HAUNT off")
      or (not (ow and ow.map and ow.player) and "no overworld/map/player")
      or (not Map.isOutdoor(ow.map.def) and "indoors")
      or (not (Game.stack and Game.stack:top() == ow) and "overworld not on top")
      or (ow.transitioning and "map transitioning")
      or "unknown"
    field:clear()
    return
  end
  GhostFX.lastGate = "live"
  GhostFX.ticksLive = GhostFX.ticksLive + 1
  GhostFX.clock = GhostFX.clock + dt

  local list = GhostFX.haunts()
  GhostFX.lastHaunts = list and #list or 0

  local p = ow.player
  local px, pz = (p.px or 0) + 8, (p.py or 0) + 8

  -- how restless the tower is: the town's window light, which is one
  -- through the night, comes up through dusk and is mostly gone by dawn
  local okN, night = pcall(DayNight.windowLight)
  night = (okN and tonumber(night)) or 0
  if GhostFX.force then night = 1 end
  GhostFX.lastNight = night

  if list and night >= GhostFX.NIGHT_MIN then
    -- PFX scales the rate like every other budget in the mod, capped at
    -- twice ON: a tower that fogged the plaza would read as a fire
    local mul = Quality.particles()
    if mul > 2 then mul = 2 end
    if mul <= 0 then mul = 0.4 end
    local every = GhostFX.EVERY / (mul * night)
    local range = GhostFX.REACH * 16
    for i = 1, #list do
      local h = list[i]
      local hx = (h.x0 + h.x1) / 2
      local hz = (h.z0 + h.z1) / 2
      local dx, dz = hx - px, hz - pz
      if dx < 0 then dx = -dx end
      if dz < 0 then dz = -dz end
      if dx <= range and dz <= range then
        -- the first wisp comes at a random point of the period
        h.next = (h.next or (rand() * every)) - dt
        if h.next <= 0 then
          h.next = every * (0.6 + rand() * 0.8)
          local src = pickSource(h)
          if src then wisp(src) end
        end
      else
        h.next = nil
      end
    end
  end

  local n = field:count()
  if n > 0 then
    -- the climb dies with age, squared, down to a hover that never quite
    -- stops: a wisp rises out of its window and then hangs there
    for i = 1, n do
      local m = field:get(i)
      local k = m.t / (m.ttl or 1)
      if k > 1 then k = 1 end
      m.lift = (m.lift0 or 0) * (1 - k) * (1 - k) + GhostFX.HOVER
    end
    local amount = Wind.amount()
    ctx.dirX = Wind.DIR[1] or 1
    ctx.dirZ = Wind.DIR[2] or 0
    ctx.speed = amount * WindFX.SPEED
    ctx.turbulence = amount * WindFX.SPEED * WindFX.TURB * 0.8
    ctx.floorAt = WindFX.groundAt
    ctx.originX = px
    ctx.originZ = pz
    ctx.reach = (GhostFX.REACH + 4) * 16
    field:step(dt, ctx)
  end
end

function GhostFX.update(dt, voxelOn)
  local ok, err = pcall(updateBody, dt, voxelOn)
  if ok then return end
  GhostFX.errorCount = GhostFX.errorCount + 1
  GhostFX.lastError = tostring(err)
end

-- ------- THE WISP, DRAWN ONCE AT LOAD
--
-- A teardrop: a body disc over a smaller tail disc, in three tones -- 1.0
-- at the core, 0.84 across the body, 0.58 on the one-texel rim -- alpha 1
-- inside and 0 out.
GhostFX.CARD = 12
GhostFX.BODY = 0.84
GhostFX.RIM = 0.58

local DISCS = { { 6.0, 5.0, 4.0 }, { 6.0, 8.6, 2.5 } }

local function makeWisp()
  local W = GhostFX.CARD
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
      for i = 1, #DISCS do
        local c = DISCS[i]
        local dx, dy = x + 0.5 - c[1], y + 0.5 - c[2]
        if dx * dx + dy * dy <= c[3] * c[3] then hit = true break end
      end
      inside[y * W + x] = hit
    end
  end
  for y = 0, W - 1 do
    for x = 0, W - 1 do
      if inside[y * W + x] then
        local dx, dy = x + 0.5 - DISCS[1][1], y + 0.5 - DISCS[1][2]
        local tone = (dx * dx + dy * dy <= 4.0) and 1.0 or GhostFX.BODY
        if not (within(x - 1, y) and within(x + 1, y)
                and within(x, y - 1) and within(x, y + 1)) then
          tone = GhostFX.RIM
        end
        data:setPixel(x, y, tone, tone, tone, 1)
      end
    end
  end
  local okI, image = pcall(love.graphics.newImage, data)
  if not okI then return nil end
  pcall(image.setFilter, image, "nearest", "nearest")
  return image
end

local function loadImg()
  if img ~= nil then return img or nil end
  img = makeWisp() or false
  return img or nil
end

-- Exposed for the probe: the card as the draw sees it.
function GhostFX.card() return loadImg() end

-- The two cards of one wisp: the teardrop, and its halo behind it.
local function emitWisp(m, push)
  local image = img
  if not image then return end
  local k = m.t / (m.ttl or 1)
  -- in over a third of a second, a long thin-out
  local fade = math.min(1, m.t * 3, (1 - k) / 0.35)
  local pulse = 0.75 + 0.25 * sin(m.t * 5.1 + (m.seed or 0))
  local a = GhostFX.ALPHA * fade * pulse
  if a <= 0.03 then return end
  local grow = k * 1.6
  if grow > 1 then grow = 1 end
  local hw = (GhostFX.SIZE0 + (GhostFX.SIZE1 - GhostFX.SIZE0) * grow)
             * (m.size or 1)
  local hh = hw * 1.25
  local t = GhostFX.TINT
  local ang = m.ang or 0
  -- the halo first, so the core draws over it
  push(image, 0, 0, 1, 1, hw * GhostFX.HALO, hh * GhostFX.HALO, ang,
       t[1], t[2], t[3], a * GhostFX.HALO_ALPHA)
  push(image, 0, 0, 1, 1, hw, hh, ang, t[1], t[2], t[3], a)
end

local function drawWorldBody()
  local live = field:count()
  if live == 0 then GhostFX.lastBatches = 0 return 0 end
  if not loadImg() then GhostFX.lastBatches = 0 return 0 end
  -- two cards a wisp, so the builder is sized for both
  builder = builder or ParticleMesh.newBuilder(GhostFX.MAX * 2)
  local mesh, batches = builder:buildCards(live,
                                           function(i) return field:get(i) end,
                                           emitWisp)
  if not mesh then GhostFX.lastBatches = 0 return 0 end
  -- translucent: alpha blend, depth TEST on, depth WRITE off -- and lit
  -- by nothing: flattened toward GLOW for this draw only, put back after
  local g = love.graphics
  local pm, pa = g.getBlendMode()
  g.setBlendMode("alpha")
  pcall(Voxel3D.flatten, GhostFX.GLOW, GhostFX.FLAT)
  local drew = Voxel3D.drawParticles(mesh, nil, batches, false)
  pcall(Voxel3D.flatten, nil)
  g.setBlendMode(pm, pa)
  GhostFX.lastBatches = drew
  return drew
end

function GhostFX.drawWorld()
  local ok, err = pcall(drawWorldBody)
  if ok then return err or 0 end
  GhostFX.drawErrors = GhostFX.drawErrors + 1
  GhostFX.drawError = "drawWorld: " .. tostring(err)
  return 0
end

return GhostFX
