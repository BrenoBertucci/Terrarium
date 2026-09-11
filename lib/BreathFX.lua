-- Breath you can see: everybody out in the cold puffs vapour.
--
-- The smallest tell of a cold day and the one every winter scene has: a
-- puff from the mouth every few seconds, quicker on the move, that rises,
-- takes the wind and is gone inside a second. The player, the NPCs and
-- the Pokemon loose in the streets all do it -- a Rattata in the snow
-- breathes too.
--
-- Its own small field of the shared solver (lib/Particles.lua), like the
-- footstep dust, drawn in the scene pass with the wind's puff sprite: a
-- breath in front of a wall is in front of the wall, and one behind the
-- Mart is behind the Mart.
--
-- COLD is the gate, not snow: winter on the SYNC calendar, snow lying on
-- the ground, or snow coming down. Outdoors, in the voxel world, with the
-- overworld on top -- WindFX's own gates minus the wind.

local V = ...

local Particles = V.require("Particles")
local ParticleMesh = V.require("ParticleMesh")
local Wind = V.require("Wind")
local WindFX = V.require("WindFX")
local GroundFX = V.require("GroundFX")
local Weather = V.require("Weather")
local Quality = V.require("Quality")
local Voxel3D = V.require("Voxel3D")

local Map = require("src.world.Map")

local BreathFX = {}

local rand = math.random

BreathFX.KINDS = {
  breath = { speed = 0.45, bob = 1.0, lowClamp = 4, highClamp = 40,
             curlA = 0.18, curlB = 0.08, mass = 0.15, area = 1.30 },
}

BreathFX.MAX = 48
BreathFX.REACH = 10            -- cells from the player anyone breathes in
BreathFX.EVERY = 3.2           -- seconds between puffs, standing
BreathFX.EVERY_MOVING = 1.7    -- and walking
BreathFX.MOUTH = 11            -- world px up from the feet
BreathFX.TTL = 0.9
BreathFX.ALPHA = 0.30
BreathFX.TINT = { 0.96, 0.97, 1.00 }
-- how much settled cover counts as cold on its own
BreathFX.COLD_COVER = 0.12

local field = Particles.newField(BreathFX.KINDS, BreathFX.MAX)
local ctx = {}
local builder = nil
-- per breather: seconds to the next puff, and where they were. Weak keys.
local breathers = setmetatable({}, { __mode = "k" })

BreathFX.puffs = 0
BreathFX.lastGate = "never ran"
BreathFX.lastBatches = -1
BreathFX.lastError = nil
BreathFX.errorCount = 0
BreathFX.drawError = nil
BreathFX.drawErrors = 0

function BreathFX.count() return field:count() end

local function game()
  return require("src.core.Game")
end

-- Is it cold out? Winter, or snow lying, or snow falling.
function BreathFX.cold()
  local okW, winter = pcall(Weather.isWinter)
  if okW and winter then return true end
  if (GroundFX.cover() or 0) >= BreathFX.COLD_COVER then return true end
  local okF, kind = pcall(Weather.falling)
  return okF and kind == "snow"
end

-- Where the mouth is: a little toward the facing so a puff in front of a
-- walker facing the camera comes off their face and not their chest.
local FACE = { down = { 0, 2.5 }, up = { 0, -1.5 }, left = { -3, 0.5 },
               right = { 3, 0.5 } }

local function puff(e, mul)
  if field:full() then return end
  local x, z = (e.px or 0) + 8, (e.py or 0) + 8
  local f = FACE[e.facing] or FACE.down
  local m = field:claim()
  if not m then return end
  m.kind = "breath"
  m.x = x + f[1] + (rand() * 2 - 1) * 1.0
  m.z = z + f[2] + (rand() * 2 - 1) * 1.0
  m.y = WindFX.groundAt(x, z) + BreathFX.MOUTH + (rand() * 2 - 1) * 0.8
  m.t, m.ttl = 0, BreathFX.TTL * (0.85 + rand() * 0.4)
  m.seed = rand() * 6.2831
  m.fast = 0.4 + rand() * 0.5
  -- rises gently, and the solver's bob does the rest
  m.lift = 5 + rand() * 3
  m.spin = (rand() * 2 - 1) * 1.2
  m.frame, m.flip, m.front = 0, 1, false
  m.size = (0.55 + rand() * 0.35) * mul
  m.ang = rand() * 6.2831
  -- a puff drifts a hair the way its breather faces, then the wind has it
  m.vx, m.vz = f[1] * 2.0, f[2] * 2.0
  BreathFX.puffs = BreathFX.puffs + 1
end

local function breathe(e, dt, nearX, nearZ)
  if not e then return end
  local x, z = (e.px or 0) + 8, (e.py or 0) + 8
  local range = BreathFX.REACH * 16
  if math.abs(x - nearX) > range or math.abs(z - nearZ) > range then return end
  local b = breathers[e]
  if not b then
    breathers[e] = { t = rand() * BreathFX.EVERY, x = x, z = z }
    return
  end
  local moving = (x ~= b.x) or (z ~= b.z)
  b.x, b.z = x, z
  b.t = b.t - dt
  if b.t <= 0 then
    puff(e, moving and 1.15 or 1.0)
    local every = moving and BreathFX.EVERY_MOVING or BreathFX.EVERY
    b.t = every * (0.8 + rand() * 0.5)
  end
end

local function updateBody(dt, voxelOn)
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
  local Game = game()
  local ow = Game and Game.overworld
  local live = voxelOn and ow and ow.map and ow.player
               and Map.isOutdoor(ow.map.def)
               and Game.stack and Game.stack:top() == ow
               and not ow.transitioning
  if not live then
    BreathFX.lastGate = (not voxelOn and "voxelOn=false")
      or (not (ow and ow.map and ow.player) and "no overworld/map/player")
      or (not Map.isOutdoor(ow.map.def) and "indoors")
      or (not (Game.stack and Game.stack:top() == ow) and "overworld not on top")
      or (ow.transitioning and "map transitioning") or "unknown"
    field:clear()
    return
  end
  if not BreathFX.cold() then
    BreathFX.lastGate = "not cold"
    if field:count() > 0 then field:clear() end
    return
  end
  BreathFX.lastGate = "live"
  local p = ow.player
  local px, pz = (p.px or 0) + 8, (p.py or 0) + 8
  if rand() < Quality.particles() then
    breathe(p, dt, px, pz)
    local npcs = ow.npcs
    if npcs then
      for i = 1, #npcs do
        local e = npcs[i]
        if e ~= p then breathe(e, dt, px, pz) end
      end
    end
  end
  if field:count() > 0 then
    local amount = Wind.amount()
    ctx.dirX = Wind.DIR[1] or 1
    ctx.dirZ = Wind.DIR[2] or 0
    ctx.speed = amount * WindFX.SPEED * 0.6
    ctx.turbulence = amount * WindFX.SPEED * WindFX.TURB
    ctx.floorAt = WindFX.groundAt
    ctx.originX = px
    ctx.originZ = pz
    ctx.reach = BreathFX.REACH * 16
    field:step(dt, ctx)
  end
end

function BreathFX.update(dt, voxelOn)
  local ok, err = pcall(updateBody, dt, voxelOn)
  if ok then return end
  BreathFX.errorCount = BreathFX.errorCount + 1
  BreathFX.lastError = tostring(err)
end

local function drawWorldBody()
  if field:count() == 0 then BreathFX.lastBatches = 0 return 0 end
  local pack = WindFX.pack()
  if not pack then BreathFX.lastBatches = 0 return 0 end
  builder = builder or ParticleMesh.newBuilder(BreathFX.MAX)
  local tint = BreathFX.TINT
  local describe = function(m)
    local img = pack.puff or pack.grit
    if not img then return nil end
    local k = m.t / m.ttl
    -- swells as it goes and thins as it swells
    local grow = 1 + k * 1.6
    local a = BreathFX.ALPHA * math.min(1, m.t * 10) * (1 - k) * (1 - k)
    if a <= 0.02 then return nil end
    local base = 1.6 * (m.size or 1) * grow
    return img, 0, 0, 1, 1, base * 0.5, base * 0.42, m.ang or 0,
           tint[1], tint[2], tint[3], a
  end
  local mesh, batches = builder:build(field, describe)
  if not mesh then BreathFX.lastBatches = 0 return 0 end
  local drew = Voxel3D.drawParticles(mesh, nil, batches, false)
  BreathFX.lastBatches = drew
  return drew
end

function BreathFX.drawWorld()
  local ok, err = pcall(drawWorldBody)
  if ok then return err or 0 end
  BreathFX.drawErrors = BreathFX.drawErrors + 1
  BreathFX.drawError = "drawWorld: " .. tostring(err)
  return 0
end

return BreathFX
