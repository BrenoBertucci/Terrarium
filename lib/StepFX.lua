-- Footstep dust (T10): the first content emitter on the finished physics.
--
-- A walker's footfall kicks a pinch of dust: a dense grain thrown
-- backward off the boot, and a lighter puff that hangs, takes whatever
-- wind there is, rides its eddies (T7) with the reluctance its mass
-- gives it (T8), and fades. The kick is nothing but an initial velocity
-- on the particle -- the solver's drag relaxes it away at the grain's
-- own tau, which is the whole reason T8 ran before this task.
--
-- ------- ITS OWN FIELD, NOT WINDFX'S
--
-- WindFX clears its field the moment the wind drops under FLOOR -- the
-- right contract for AMBIENT motes, whose only reason to exist is the
-- wind. A footstep makes dust in dead calm. So this module owns a small
-- field of the shared solver (which is what the solver was unified FOR)
-- and shares everything else: the same air (Wind.flowAt / turbAt through
-- the same ctx shape), the same sprites (WindFX.pack), the same scene
-- pass draw (ParticleMesh + Voxel3D.drawParticles).
--
-- ------- WHEN A FOOT FALLS
--
-- No animation seam: a stride is DISTANCE. Every 8 world px a walker
-- covers (half a cell -- one footfall of a 16px step cycle), one
-- emission at their current position. Faster movement (the bike) emits
-- more per second by construction, with no speed detection anywhere. A
-- jump over 24px in one frame is a warp, not a sprint: the accumulator
-- resets and nothing is emitted.
--
-- ------- WHAT GATES IT
--
-- Outdoors, voxel mode, overworld on top -- WindFX's own gates minus the
-- wind. Then per footfall: GroundFX.wetness() kills dust as the ground
-- soaks (mud does not puff) and GroundFX.cover() as snow muffles it.
-- Rate rides the PFX row's multiplier like every other particle budget.

local V = ...

local Particles = V.require("Particles")
local ParticleMesh = V.require("ParticleMesh")
local Wind = V.require("Wind")
local WindFX = V.require("WindFX")
local GroundFX = V.require("GroundFX")
local Quality = V.require("Quality")
local Voxel3D = V.require("Voxel3D")

local Map = require("src.world.Map")

local StepFX = {}

local rand = math.random
local sqrt = math.sqrt

-- Both kinds reuse the shipping palette's physics language: the kick is
-- a dense grain (tau ~0.19s, so the backward toss survives long enough
-- to read), the dust a light puff (tau ~0.02s, takes the air almost at
-- once). Clamps keep step dust LOW -- it is off a boot, not off a roof.
StepFX.KINDS = {
  kick = { speed = 0.50, bob = 1.2, lowClamp = 0.4, highClamp = 9,
           curlA = 0.10, curlB = 0.06, mass = 0.45, area = 0.35 },
  dust = { speed = 0.72, bob = 2.2, lowClamp = 0.4, highClamp = 14,
           curlA = 0.20, curlB = 0.10, mass = 0.16, area = 1.10 },
}

StepFX.MAX = 64            -- hard field cap; PFX scales the RATE, not this
StepFX.STRIDE = 8          -- world px per footfall
StepFX.WET_KILL = 0.45     -- wetness at which the ground stops puffing
StepFX.SNOW_KILL = 0.35    -- settled cover at which snow muffles the step
StepFX.REACH = 12          -- cells from the player before a mote is culled
StepFX.KICK = 12           -- world px/s of backward toss per footfall

local field = Particles.newField(StepFX.KINDS, StepFX.MAX)
-- last seen position + stride accumulator per walker. Weak keys: an NPC
-- that despawns takes its entry with it.
local trail = setmetatable({}, { __mode = "k" })
local stepCtx = {}
local builder = nil

-- The instruments, same contract as every module in the chain (see
-- armadilha 1): a throw in update or draw is caught, counted and named,
-- never allowed to take the pipeline down.
StepFX.ticks = 0
StepFX.ticksLive = 0
StepFX.lastGate = "never ran"
StepFX.emitted = 0
StepFX.lastBatches = -1
StepFX.lastError = nil
StepFX.errorCount = 0
StepFX.drawError = nil
StepFX.drawErrors = 0

function StepFX.count() return field:count() end
function StepFX.get(i) return field:get(i) end

-- Overridable for probes: soaking the map for real takes 70 seconds of
-- rain (armadilha 6), and the gate under test is a comparison, not the
-- weather.
StepFX.wetness = function() return GroundFX.wetness() end
StepFX.snow = function() return GroundFX.cover() end

local function game()
  return require("src.core.Game")
end

local function footfall(x, z, mx, mz)
  local wet = StepFX.wetness() or 0
  if wet >= StepFX.WET_KILL then return end
  if (StepFX.snow() or 0) >= StepFX.SNOW_KILL then return end
  -- dry ground puffs fully, damp ground less, mud not at all
  local dry = 1 - wet / StepFX.WET_KILL
  local mul = Quality.particles()
  local ground = WindFX.groundAt(x, z)
  local tint = WindFX.DUST

  -- the grain, thrown backward off the boot
  if rand() < math.min(1, 0.85 * dry * mul) and not field:full() then
    local m = field:claim()
    if m then
      m.kind = "kick"
      m.x = x + (rand() * 2 - 1) * 2
      m.z = z + (rand() * 2 - 1) * 2
      m.y = ground + 1.2
      m.t, m.ttl = 0, 0.5 + rand() * 0.4
      m.seed = rand() * 6.2831
      m.fast = 0.5 + rand() * 0.7
      m.lift = 3 + rand() * 4
      m.spin = (rand() * 2 - 1) * 1.5
      m.frame, m.flip, m.front = 0, 1, false
      m.size = 0.40 + rand() * 0.50
      m.tint = tint
      m.ang = 0
      -- the kick itself: initial velocity the drag will spend
      local k = StepFX.KICK * (0.75 + rand() * 0.5)
      m.vx = -mx * k + (rand() * 2 - 1) * 4
      m.vz = -mz * k + (rand() * 2 - 1) * 4
      StepFX.emitted = StepFX.emitted + 1
    end
  end

  -- the puff, which just hangs and takes the air
  if rand() < math.min(1, 0.70 * dry * mul) and not field:full() then
    local m = field:claim()
    if m then
      m.kind = "dust"
      m.x = x + (rand() * 2 - 1) * 3
      m.z = z + (rand() * 2 - 1) * 3
      m.y = ground + 1.6
      m.t, m.ttl = 0, 0.9 + rand() * 0.7
      m.seed = rand() * 6.2831
      m.fast = 0.5 + rand() * 0.6
      m.lift = 2 + rand() * 3
      m.spin = (rand() * 2 - 1) * 3.0
      m.frame, m.flip, m.front = 0, 1, false
      m.size = 0.55 + rand() * 0.55
      m.tint = tint
      m.ang = 0
      StepFX.emitted = StepFX.emitted + 1
    end
  end
end

-- `nearX/nearZ` is the player's own centre: a walker outside the reach
-- cull emits motes the very next step would kill -- claim/kill churn
-- that pads every counter and draws nothing. The trail still advances
-- while out of range, so an NPC entering range does not dump a whole
-- corridor of banked strides at once.
local function emitFor(e, nearX, nearZ)
  if not e then return end
  local x = (e.px or 0) + 8
  local z = (e.py or 0) + 8
  local tr = trail[e]
  if not tr then
    trail[e] = { x = x, z = z, acc = 0 }
    return
  end
  local dx, dz = x - tr.x, z - tr.z
  tr.x, tr.z = x, z
  local d = sqrt(dx * dx + dz * dz)
  if d <= 0.01 then return end
  if d > 24 then tr.acc = 0 return end     -- a warp, not a sprint
  local range = StepFX.REACH * 16
  if math.abs(x - nearX) > range or math.abs(z - nearZ) > range then
    tr.acc = 0
    return
  end
  tr.acc = tr.acc + d
  local mx, mz = dx / d, dz / d
  while tr.acc >= StepFX.STRIDE do
    tr.acc = tr.acc - StepFX.STRIDE
    footfall(x, z, mx, mz)
  end
end

local function updateBody(dt, voxelOn)
  StepFX.ticks = StepFX.ticks + 1
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end

  local Game = game()
  local ow = Game and Game.overworld
  local live = voxelOn and ow and ow.map and ow.player
               and Map.isOutdoor(ow.map.def)
               and Game.stack and Game.stack:top() == ow
               and not ow.transitioning
  if not live then
    StepFX.lastGate =
      (not voxelOn and "voxelOn=false")
      or (not (ow and ow.map and ow.player) and "no overworld/map/player")
      or (not Map.isOutdoor(ow.map.def) and "indoors")
      or (not (Game.stack and Game.stack:top() == ow) and "overworld not on top")
      or (ow.transitioning and "map transitioning")
      or "unknown"
    field:clear()
    return
  end
  StepFX.lastGate = "live"
  StepFX.ticksLive = StepFX.ticksLive + 1

  local p = ow.player
  local px8, pz8 = (p.px or 0) + 8, (p.py or 0) + 8
  emitFor(p, px8, pz8)
  local npcs = ow.npcs
  if npcs then
    for i = 1, #npcs do
      local e = npcs[i]
      if e ~= p then emitFor(e, px8, pz8) end
    end
  end

  if field:count() > 0 then
    local amount = Wind.amount()
    stepCtx.dirX = Wind.DIR[1] or 1
    stepCtx.dirZ = Wind.DIR[2] or 0
    -- the same air, at the same conversion WindFX uses; a dead calm gives
    -- speed 0 and the dust just rises on its lift and fades
    stepCtx.speed = amount * WindFX.SPEED
    stepCtx.turbulence = amount * WindFX.SPEED * WindFX.TURB
    stepCtx.floorAt = WindFX.groundAt
    stepCtx.originX = (p.px or 0) + 8
    stepCtx.originZ = (p.py or 0) + 8
    stepCtx.reach = StepFX.REACH * 16
    field:step(dt, stepCtx)
  end
end

function StepFX.update(dt, voxelOn)
  local ok, err = pcall(updateBody, dt, voxelOn)
  if ok then return end
  StepFX.errorCount = StepFX.errorCount + 1
  StepFX.lastError = tostring(err)
end

-- Card sizes per kind, the same language WindFX's ladder speaks.
local CARD = {
  kick = { 1.05, 1.0, 1.0 },
  dust = { 1.80, 1.2, 1.1 },
}

local function drawWorldBody()
  local live = field:count()
  if live == 0 then StepFX.lastBatches = 0 return 0 end
  local pack = WindFX.pack()
  if not pack then StepFX.lastBatches = 0 return 0 end
  builder = builder or ParticleMesh.newBuilder(StepFX.MAX)

  local describe = function(m)
    local img = (m.kind == "dust") and (pack.puff or pack.grit) or pack.grit
    if not img then return nil end
    -- fast in (a step is sudden), long settle-out (dust dies by fading)
    local fade = math.min(1, m.t * 6, (m.ttl - m.t) * 1.6)
    local a = 0.62 * fade
    if a <= 0.02 then return nil end
    local c = CARD[m.kind] or CARD.kick
    local base = c[1] * (m.size or 1)
    local hw = base * c[2] * 0.5
    local hh = base * c[3] * 0.5
    if hw < 0.5 then hw = 0.5 end
    if hh < 0.5 then hh = 0.5 end
    local col = m.tint or WindFX.DUST
    return img, 0, 0, 1, 1, hw, hh, m.ang or 0, col[1], col[2], col[3], a
  end

  local mesh, batches = builder:build(field, describe)
  if not mesh then StepFX.lastBatches = 0 return 0 end
  local drew = Voxel3D.drawParticles(mesh, nil, batches, true)
  StepFX.lastBatches = drew
  return drew
end

function StepFX.drawWorld()
  local ok, err = pcall(drawWorldBody)
  if ok then return err or 0 end
  StepFX.drawErrors = StepFX.drawErrors + 1
  StepFX.drawError = "drawWorld: " .. tostring(err)
  return 0
end

return StepFX
