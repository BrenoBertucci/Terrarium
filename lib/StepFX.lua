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
-- soaks (mud does not puff) and GroundFX.cover() turns it white: a boot in
-- a drift throws powder the way it throws dust off a dry road.
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
  -- ------- a DROP of water thrown out of a puddle
  --
  -- The solver has no gravity (its motes float and bob, which is right for
  -- dust and wrong for water), so a drop is the one kind this file drives
  -- itself: `lift` is its vertical speed, and the pass after field:step
  -- takes DROP_G off it every frame and kills it where it meets the ground.
  -- Heavy and small, so the air barely moves it -- a splash goes where the
  -- boot sent it, not where the wind is blowing.
  drop = { speed = 0.05, bob = 0, lowClamp = 0.1, highClamp = 40,
           curlA = 0, curlB = 0, mass = 3.0, area = 0.30 },
  -- ------- FOAM a swimmer leaves on the water (lib/WakeFX.lua)
  --
  -- Lies where it was laid: no wind, no lift, no bob -- foam is on the
  -- surface and the surface is what moves. Fades out in about a second.
  foam = { speed = 0.0, bob = 0, lowClamp = 0.1, highClamp = 60,
           curlA = 0, curlB = 0, mass = 4.0, area = 0.5 },
}

StepFX.MAX = 64            -- hard field cap; PFX scales the RATE, not this
StepFX.STRIDE = 8          -- world px per footfall
StepFX.WET_KILL = 0.45     -- wetness at which the ground stops puffing
StepFX.SNOW_KILL = 0.35    -- settled cover at which the step throws snow
-- What that snow is tinted: the fall's own white (Weather.SNOW), a hair
-- cooler, so a kicked pinch of it reads as powder and not as dust.
-- ...and it was WHITE, which is the trap: near-white powder at 0.62 alpha
-- over a field of near-white snow is no contrast at all, and the effect
-- fired all along (45 motes alive at the peak, measured) without being
-- visible in a single frame. What you actually see of snow thrown into the
-- air is its SHADED side against the flat lit ground it came out of, so
-- the powder is cooler and darker than the ground rather than brighter.
StepFX.SNOW = { 0.80, 0.86, 0.99 }
StepFX.SNOW_SIZE = 2.9     -- powder flies bigger than dust
-- Thrown HIGHER and WIDER than dust, and that is the other half of why it
-- could not be seen: a mote at the same height as a boot print, on a
-- camera looking down over the walker's shoulder, is behind the walker.
-- Powder off a drift goes up and out, into the air beside them.
StepFX.SNOW_LIFT = 2.4
StepFX.SNOW_SPREAD = 2.2
StepFX.SNOW_RATE = 1.7     -- and there is more of it than there is dust
-- ------- and the BURST, which is the thing you actually see
--
-- Two authored stamps -- a grit speck and a soft puff -- are what dust off a
-- dry road is, and tinting them white is not what powder off a drift is: at
-- a footstep's scale they read as a couple of commas by the boots. So a
-- snowy footfall also throws ONE clip -- a clump at ground level that blooms
-- outward into a cloud of separate specks and thins out, which is what a
-- boot going through a drift does to it.
--
-- Pimen's Smoke n Dust 03 VFX 4, cut by tools/cut_snow_burst.py and carried
-- in the shared pack (WindFX.pack().snowburst). It does not spin and it does
-- not fly: the clip animates the rise, and the mote only drifts the way the
-- boot pushed it.
StepFX.SNOW_BURST = { fw = 64, fh = 64, n = 7, fps = 15, hw = 7.2 }
StepFX.BURST_CHANCE = 0.85    -- per snowy footfall
StepFX.BURST_ALPHA = 0.85
StepFX.WATER = { 0.74, 0.85, 1.00 }   -- and a splash off a soaked road
-- ------- and a real SPLASH, out of standing water
--
-- Damp ground spatters (above). A POOL -- a cell the ground row says holds
-- water right now -- throws water: a handful of drops in an arc off the
-- boot, up and outward, falling under their own weight and dying where
-- they land, more of them the deeper the pool, with a splash to hear. It
-- is the footstep that makes a puddle a thing you stepped IN rather than
-- a picture you walked across, and everybody gets it -- the player, the
-- follower, the townspeople crossing the square in the rain.
StepFX.DROP = { 0.86, 0.94, 1.00 }
StepFX.DROPS_MIN = 4        -- drops per footfall in the shallowest pool
StepFX.DROPS_DEPTH = 6      -- and how many more a full-depth one adds
StepFX.DROP_UP = 68         -- vertical speed at the boot (solver units)
StepFX.DROP_UP_VAR = 42
StepFX.DROP_OUT = 9         -- horizontal speed, world px/s, plus a share
StepFX.DROP_OUT_VAR = 16
StepFX.DROP_G = 230         -- what it loses per second
StepFX.splashes = 0         -- footfalls that splashed, for the probe
StepFX.lastSplashDepth = 0
StepFX.REACH = 12          -- cells from the player before a mote is culled
StepFX.KICK = 12           -- world px/s of backward toss per footfall

local field = Particles.newField(StepFX.KINDS, StepFX.MAX)
-- last seen position + stride accumulator per walker. Weak keys: an NPC
-- that despawns takes its entry with it.
local trail = setmetatable({}, { __mode = "k" })
local stepCtx = {}
local builder = nil
local softBuilder = nil

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

-- Standing water under this footfall, 0..1 deep, or 0. Asked of the ground
-- row rather than of the wetness: a soaked map is damp everywhere and a
-- pool is somewhere in particular.
local function poolUnder(x, z)
  local Game = game()
  local ow = Game and Game.overworld
  if not (ow and ow.map) then return 0 end
  local ok, d = pcall(GroundFX.poolDepth, ow.map,
                      math.floor(x / 16), math.floor(z / 16))
  return (ok and tonumber(d)) or 0
end

local function splash(x, z, mx, mz, depth, quiet)
  local mul = Quality.particles()
  local ground = WindFX.groundAt(x, z)
  local n = StepFX.DROPS_MIN + math.floor(depth * StepFX.DROPS_DEPTH + 0.5)
  for _ = 1, n do
    if rand() < math.min(1, mul) and not field:full() then
      local m = field:claim()
      if not m then break end
      m.kind = "drop"
      m.x = x + (rand() * 2 - 1) * 2.5
      m.z = z + (rand() * 2 - 1) * 2.5
      m.y = ground + 1.0
      m.t, m.ttl = 0, 1.6
      m.seed = rand() * 6.2831
      m.fast = 1
      m.lift = StepFX.DROP_UP + rand() * StepFX.DROP_UP_VAR
      m.spin = (rand() * 2 - 1) * 2.0
      m.frame, m.flip, m.front = 0, 1, false
      m.size = (0.90 + rand() * 0.70) * (0.8 + 0.4 * depth)
      m.tint = StepFX.DROP
      m.ang = 0
      -- outward in a random direction, plus a little of the stride's own
      local a = rand() * 6.2831
      local s = (StepFX.DROP_OUT + rand() * StepFX.DROP_OUT_VAR) * (0.7 + 0.5 * depth)
      m.vx = math.cos(a) * s + mx * 5
      m.vz = math.sin(a) * s + mz * 5
      StepFX.emitted = StepFX.emitted + 1
    end
  end
  StepFX.splashes = StepFX.splashes + 1
  StepFX.lastSplashDepth = depth
  if quiet then return end
  local okS, AmbientSound = pcall(V.require, "AmbientSound")
  if okS and AmbientSound and AmbientSound.playSplash then
    pcall(AmbientSound.playSplash, x, z, depth)
  end
end

-- A splash asked for from outside: a body going into deep water
-- (lib/WakeFX.lua). Full depth, no stride.
function StepFX.splashAt(x, z, depth, quiet)
  splash(x, z, 0, 0, math.max(0, math.min(1, depth or 1)), quiet)
end

-- A foam puff on the water surface, for the wake trail.
StepFX.foamCount = 0
function StepFX.foam(x, z, size)
  if field:full() then return false end
  local m = field:claim()
  if not m then return false end
  local y = nil
  local okW, Water = pcall(V.require, "Water")
  if okW and Water and Water.surfaceAt then
    local okS, s = pcall(Water.surfaceAt, x, z)
    if okS and tonumber(s) then y = s + 0.45 end
  end
  m.kind = "foam"
  m.x, m.z = x, z
  m.y = y or (WindFX.groundAt(x, z) + 0.4)
  m.t, m.ttl = 0, 1.2 + rand() * 0.6
  m.seed = rand() * 6.2831
  m.fast = 1
  m.lift = 0
  m.spin = (rand() * 2 - 1) * 0.6
  m.frame, m.flip, m.front = 0, 1, false
  m.size = size or 1
  m.tint = { 0.95, 0.98, 1.0 }
  m.ang = 0
  m.vx = (rand() * 2 - 1) * 2
  m.vz = (rand() * 2 - 1) * 2
  StepFX.foamCount = StepFX.foamCount + 1
  StepFX.emitted = StepFX.emitted + 1
  return true
end

local function footfall(x, z, mx, mz)
  -- standing water first: a pool splashes, whatever the map's wetness
  local depth = poolUnder(x, z)
  if depth > 0 then
    splash(x, z, mx, mz, depth)
    return
  end
  local wet = StepFX.wetness() or 0
  -- ------- snow does not muffle the step, it CHANGES it
  --
  -- A boot in a drift throws a pinch of snow the way it throws dust off a
  -- dry road: the same grain and puff, white, and a little more of it --
  -- powder flies. Mud is the one ground that puffs nothing, and settled
  -- snow on it is snow.
  local snowy = (StepFX.snow() or 0) >= StepFX.SNOW_KILL
  -- ------- and a SOAKED road does not puff either -- it splashes
  --
  -- The step that used to be nothing (mud) is a spatter of water off the
  -- boot: the same grain, thrown a little harder and higher, in the
  -- rain's own pale blue, and a smaller puff of spray.
  local soaked = wet >= StepFX.WET_KILL and not snowy
  -- dry ground puffs fully, damp ground less; snow and water fully
  local dry = (snowy or soaked) and 1 or (1 - wet / StepFX.WET_KILL)
  local mul = Quality.particles()
  local ground = WindFX.groundAt(x, z)
  local tint = snowy and StepFX.SNOW or (soaked and StepFX.WATER) or WindFX.DUST
  local big = snowy and StepFX.SNOW_SIZE or (soaked and 0.75) or 1

  local snowRate = snowy and StepFX.SNOW_RATE or 1
  local snowLift = snowy and StepFX.SNOW_LIFT or 1
  local snowWide = snowy and StepFX.SNOW_SPREAD or 1

  -- ------- the powder burst, on snow only
  local burst = StepFX.SNOW_BURST
  if snowy and rand() < math.min(1, StepFX.BURST_CHANCE * mul)
      and not field:full() then
    local m = field:claim()
    if m then
      m.kind = "burst"
      m.snow = true
      m.x = x + (rand() * 2 - 1) * 2
      m.z = z + (rand() * 2 - 1) * 2
      m.y = ground + 1.0
      m.t, m.ttl = 0, burst.n / burst.fps
      m.seed = rand() * 6.2831
      -- no fast, no lift, no spin: the clip IS the animation, and a card
      -- that turns in its own plane while a drawn puff blooms inside it
      -- reads as the drawing sliding rather than as snow rising
      m.fast, m.lift, m.spin = 0, 0, 0
      m.frame, m.flip, m.front = 0, 1, false
      m.size = 0.85 + rand() * 0.35
      m.tint = tint
      m.ang = 0
      -- only what the boot pushed: a burst stays where the foot was
      m.vx = -mx * 5 + (rand() * 2 - 1) * 2
      m.vz = -mz * 5 + (rand() * 2 - 1) * 2
      StepFX.emitted = StepFX.emitted + 1
    end
  end

  -- the grain, thrown backward off the boot
  if rand() < math.min(1, 0.85 * dry * mul * snowRate) and not field:full() then
    local m = field:claim()
    if m then
      m.kind = "kick"
      m.snow = snowy
      m.x = x + (rand() * 2 - 1) * 2 * snowWide
      m.z = z + (rand() * 2 - 1) * 2 * snowWide
      m.y = ground + 1.2
      m.t, m.ttl = 0, 0.5 + rand() * 0.4
      m.seed = rand() * 6.2831
      m.fast = 0.5 + rand() * 0.7
      m.lift = (3 + rand() * 4) * snowLift
      m.spin = (rand() * 2 - 1) * 1.5
      m.frame, m.flip, m.front = 0, 1, false
      m.size = (0.40 + rand() * 0.50) * big
      m.tint = tint
      m.ang = 0
      -- the kick itself: initial velocity the drag will spend
      local k = StepFX.KICK * (0.75 + rand() * 0.5) * (soaked and 1.4 or 1)
      if soaked then m.lift = m.lift * 1.6 end
      m.vx = -mx * k + (rand() * 2 - 1) * 4
      m.vz = -mz * k + (rand() * 2 - 1) * 4
      StepFX.emitted = StepFX.emitted + 1
    end
  end

  -- the puff, which just hangs and takes the air
  if rand() < math.min(1, 0.70 * dry * mul * snowRate) and not field:full() then
    local m = field:claim()
    if m then
      m.kind = "dust"
      m.snow = snowy
      m.x = x + (rand() * 2 - 1) * 3 * snowWide
      m.z = z + (rand() * 2 - 1) * 3 * snowWide
      m.y = ground + 1.6
      m.t, m.ttl = 0, 0.9 + rand() * 0.7
      m.seed = rand() * 6.2831
      m.fast = 0.5 + rand() * 0.6
      m.lift = (2 + rand() * 3) * snowLift
      m.spin = (rand() * 2 - 1) * 3.0
      m.frame, m.flip, m.front = 0, 1, false
      m.size = (0.55 + rand() * 0.55) * big
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
    -- ------- the drops fall
    --
    -- The solver moved everything by its lift; this takes the lift down
    -- (gravity) and ends a drop that has come back to the ground -- it
    -- lands, it does not hover in a ring at ankle height.
    local G = StepFX.DROP_G
    local i = 1
    while i <= field:count() do
      local m = field:get(i)
      if m and m.kind == "drop" then
        m.lift = (m.lift or 0) - G * dt
        local g = WindFX.groundAt(m.x, m.z)
        if m.lift < 0 and m.y <= g + 0.6 then
          field:kill(i)
        else
          i = i + 1
        end
      else
        i = i + 1
      end
    end
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
  drop = { 0.95, 0.8, 1.35 },   -- taller than wide: a drop, not a grain
  foam = { 1.9, 1.3, 0.75 },    -- a flat patch on the water
}

local function drawWorldBody()
  local live = field:count()
  if live == 0 then StepFX.lastBatches = 0 return 0 end
  local pack = WindFX.pack()
  if not pack then StepFX.lastBatches = 0 return 0 end
  builder = builder or ParticleMesh.newBuilder(StepFX.MAX)

  local describe = function(m)
    -- ------- the burst: one card of the clip's current frame
    if m.kind == "burst" then
      local img = pack.snowburst
      if not img then return nil end
      local s = StepFX.SNOW_BURST
      local iw, ih = img:getDimensions()
      if iw < 1 or ih < 1 then return nil end
      local f = math.floor(m.t * s.fps)
      if f < 0 then f = 0 elseif f >= s.n then return nil end
      local u0 = (f * s.fw) / iw
      local u1 = u0 + s.fw / iw
      -- the clip thins out on its own, so this only guards the last frame
      -- against a pop, the way WindFX.SHEET_OUT does
      local a = StepFX.BURST_ALPHA * math.min(1, (m.ttl - m.t) * 5)
      if a <= 0.02 then return nil end
      local col = m.tint or StepFX.SNOW
      local hw = s.hw * (m.size or 1)
      return img, u0, 0, u1, 1, hw, hw * (s.fh / s.fw), 0,
             col[1], col[2], col[3], a
    end

    -- Snow takes the PUFF for its grain too, not the grit. Grit is a hard
    -- speck, which is what a stone road throws; powder off a drift is a
    -- soft cloud, and at this magnification the difference between the two
    -- is the difference between grey commas by the boots and snow being
    -- kicked up.
    local soft = m.kind == "dust" or m.kind == "foam" or m.snow
    local img = soft and (pack.puff or pack.grit) or pack.grit
    if not img then return nil end
    -- fast in (a step is sudden), long settle-out (dust dies by fading)
    local fade = math.min(1, m.t * 6, (m.ttl - m.t) * 1.6)
    -- water is bright and hard-edged; it does not fade the way dust does.
    -- Powder carries more than dust: it is the thing being looked at here,
    -- and it is competing with a field of the same colour.
    local a = (m.kind == "drop" and 0.92
               or (m.kind == "foam" and 0.78)
               or (m.snow and 0.82) or 0.62) * fade
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

  -- ------- two passes, and the difference is the DEPTH WRITE
  --
  -- The grain, the spray and the foam write depth, as they always have.
  -- The powder burst must not, and that is not a detail: a fragment that
  -- writes depth is a silhouette, and the screen-space pass draws an ink
  -- line round every silhouette (lib/Anime.lua). Written, each puff came
  -- out as a white blob with a hard black rim -- a cut-out sticker lying
  -- on the snow rather than powder in the air. It is the same reason the
  -- breath, the hearth's smoke and the falling flakes all pass false.
  --
  -- The depth TEST stays either way, so a burst is still hidden by
  -- whatever stands in front of it.
  local function only(want)
    return function(m)
      if ((m.kind == "burst") and true or false) ~= want then return nil end
      return describe(m)
    end
  end

  local drew = 0
  local mesh, batches = builder:build(field, only(false))
  if mesh then drew = drew + Voxel3D.drawParticles(mesh, nil, batches, true) end
  softBuilder = softBuilder or ParticleMesh.newBuilder(StepFX.MAX)
  local sMesh, sBatches = softBuilder:build(field, only(true))
  if sMesh then
    drew = drew + Voxel3D.drawParticles(sMesh, nil, sBatches, false)
  end
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
