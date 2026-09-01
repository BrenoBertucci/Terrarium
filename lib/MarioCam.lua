-- The Super Mario 64 camera, on a Pokemon overworld.
--
-- A port of the system described in `camera-super-mario-64.md`, which is a
-- reading of `n64decomp/sm64`'s src/game/camera.c. The names here are the
-- decomp's names on purpose: someone holding that file open should be able
-- to find every piece of it below, and the places where this DIVERGES are
-- called out where they happen rather than left to be discovered.
--
-- ------- what this is, and what the existing camera is
--
-- Voxel3D's free-roam camera is an ORBIT described by one number -- the
-- pitch on the VOXEL ladder -- looking north at the engine's own 2D scroll
-- centre. It has no yaw, no inertia, no memory, and its height comes from
-- the view rather than from the ground. That is a perfectly good camera for
-- a map you read top-down, and it is what OFF leaves in place.
--
-- This is the other thing: a camera with a CAMERA OPERATOR behind it. The
-- whole of SM64's camera is two ideas and this file is mostly those two:
--
--   1. THE TARGET AND THE REAL ARE DIFFERENT OBJECTS.  One function says
--      where the camera OUGHT to be this frame -- pure geometry, no
--      history, no inertia.  A second layer CHASES that answer.  Mixing
--      them is what produces cameras that lock into feedback loops, and
--      the decomp keeps them in two structs for exactly this reason
--      (`struct Camera` and `struct LakituState`).
--
--   2. THE FOCUS AND THE BODY MOVE AT DIFFERENT SPEEDS.  0.8 horizontal
--      for the focus, 0.3 for everything else.  The camera TURNS to look
--      at you almost four times faster than it FLIES to where it wants to
--      stand.  That asymmetry is most of what SM64's camera feels like,
--      and it costs two constants.
--
-- Everything else -- the modes, the wall avoidance, the shake, the FOV
-- functions -- is detail hung off those two.
--
-- ------- the scale
--
-- SM64's constants are in SM64 units, where Mario is about 160 tall. This
-- world is in WORLD PIXELS, where a map cell is 16 and a block is 32. The
-- decomp's numbers are kept literal below and divided by U at the point of
-- use, so a value here can be checked against camera.c without arithmetic.
--
-- U falls out of one requirement: at the default zoom and a 45-degree lens
-- (SM64's own, see CAM_FOV_SET_45) the frame should hold the same 144
-- world pixels the existing orbit holds, so switching the row on does not
-- silently rescale the world. 1400 SM64 units is SM64's default radial
-- distance; 144 / (2 * tan(22.5 degrees)) is 173.8 world pixels; 1400 /
-- 173.8 is 8.05. U = 8, and a 16-pixel cell comes out 128 SM64 units --
-- a Pokemon tile a little shorter than Mario, which is about right.
--
-- ------- what it does, and the one thing it changes
--
-- Almost all of this is presentational, like the rest of the mod: it
-- changes what the world LOOKS like and nothing about what it IS.
-- Collision, ledges, warps and scripts all still speak compass directions
-- and are untouched.
--
-- The exception is deliberate and it is SM64's own: MOVEMENT IS
-- CAMERA-RELATIVE. There, one line does it --
--
--     m->intendedYaw = atan2s(-stickY, stickX) + m->area->camera->yaw;
--
-- -- and push away from yourself and Mario runs away from you, whatever
-- the camera is doing. An orbiting camera without it is not a camera, it
-- is a puzzle: the world turns under you while Up keeps meaning north.
-- This port refused to do it at first, and hid behind a four-rung ladder
-- that let the player choose how much of that puzzle to accept. The
-- refusal was wrong and the ladder was a symptom; both are gone.
--
-- What that costs, precisely: pressing Up walks the player in whichever
-- world direction currently reads as "away from the camera". The walk
-- itself is an ordinary walk through ordinary collision. See
-- MarioCam.buttonFor.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Voxel = V.require("VoxelState")
local ModSetting = V.require("ModSetting")

local Map = require("src.world.Map")

local MarioCam = {}

-- SM64 units per world pixel. See the header for where 8 comes from.
local U = 8

-- ---------------------------------------------------------------- s16 --
--
-- SM64 angles are 16-bit integers with wrap-around: 0x10000 is a full
-- turn, so 0x4000 is 90 degrees. This is not nostalgia -- adding two
-- angles never needs normalising, because the integer overflow IS the
-- wrap, and every "shortest way round" question answers itself. Written
-- out in Lua because the alternative is radians plus a normalise() that
-- somebody eventually forgets to call at the one seam where it mattered.

local S16 = 0x10000
local S16_HALF = 0x8000

local function s16(a)
  return a % S16
end

-- The signed reading of an s16, in [-32768, 32767]. This is the "shortest
-- way round" the wrap gives for free.
local function signed(a)
  a = a % S16
  if a >= S16_HALF then a = a - S16 end
  return a
end

local function degrees(d)
  return s16(d * S16 / 360)
end

local function radiansOf(a)
  return signed(a) * (2 * math.pi) / S16
end

local function sins(a) return math.sin(radiansOf(a)) end
local function coss(a) return math.cos(radiansOf(a)) end

-- The decomp's atan2s(y, x), which is atan2 in s16. Every yaw in this file
-- comes out of one of these.
local function atan2s(y, x)
  if y == 0 and x == 0 then return 0 end
  return s16(math.atan2(y, x) * S16 / (2 * math.pi))
end

-- ------- the two approach functions
--
-- approach_f32_asymptotic: close `multiplier` of the remaining distance,
-- this frame. A lerp toward a moving target, which is an exponential
-- decay, which is why nothing here ever quite arrives -- and why it never
-- overshoots either.
local function approachF32(current, target, multiplier)
  if multiplier > 1 then multiplier = 1 end
  if multiplier < 0 then multiplier = 0 end
  return current + (target - current) * multiplier
end

-- approach_s16_asymptotic: the same thing for angles, and the decomp
-- writes it with a DIVISOR rather than a multiplier -- divisor 4 means
-- "close a quarter of the angle this frame". Kept in that form so a value
-- from camera.c can be pasted in. The subtraction is the signed one, so it
-- always turns the short way.
local function approachS16(current, target, divisor)
  if divisor == 0 then return target end
  return s16(current + signed(target - current) / divisor)
end

-- ------- THE FRAMERATE CORRECTION, and why it is not a division
--
-- Every constant above is per frame AT 30 FPS, because that is what the
-- N64 ran at. This runs at whatever the machine gives it. The naive fix --
-- halving the coefficient for 60 FPS -- is wrong, because closing 80% of a
-- gap twice does not close 160% of it, it closes 96%.
--
-- The right conversion is the one the source doc spells out:
--
--     k' = 1 - (1 - k) ^ (dt * 30)
--
-- which is the same exponential sampled at a different rate, and is exact
-- rather than approximate. dt is clamped because a long frame -- a warp's
-- first frame, a mesh build, a breakpoint -- must not teleport the camera:
-- past about a fifth of a second the answer is so near 1 that the chase
-- becomes a cut, and a cut is what CAM_FLAG_SMOOTH_MOVEMENT is for.
local function rate(k, dt)
  if dt <= 0 then return 0 end
  if dt > 0.2 then dt = 0.2 end
  if k <= 0 then return 0 end
  if k >= 1 then return 1 end
  return 1 - (1 - k) ^ (dt * 30)
end

-- The same correction for a DIVISOR-shaped constant, returned as a
-- divisor so approachS16 can take it unchanged.
local function rateDiv(divisor, dt)
  if divisor <= 1 then return 1 end
  local k = rate(1 / divisor, dt)
  if k <= 0 then return math.huge end
  return 1 / k
end

-- ------------------------------------------------------------- the rig --

-- ------- LAYER 1: struct Camera, the TARGET
--
-- What the mode functions write. Pure geometry: given this frame's
-- situation, the ideal place to stand is here. No inertia lives in this
-- table and nothing may put any in it -- the moment a mode starts reading
-- its own previous answer, the two layers have collapsed into one and the
-- feedback loops are back.
local cam = {
  mode = "RADIAL",
  defMode = "RADIAL",
  -- The decomp's warning, which is worth repeating because it bites: this
  -- is the angle from the FOCUS TO THE POSITION, not the direction the
  -- camera looks. It is the opposite of the real yaw. The decomp calls it
  -- a bug that became API; it is kept because every formula below is
  -- written against it, and half-converting would be worse than either.
  yaw = 0,
  focus = { 0, 0, 0 },
  pos = { 0, 0, 0 },
  -- the eye of the radial orbit: the point the camera goes AROUND, which
  -- is not the player (see the radial mode)
  areaCenX = 0,
  areaCenZ = 0,
  dist = 175,
  pitch = degrees(30),
}

-- ------- LAYER 2: struct LakituState, the REAL
--
-- What actually gets rendered. It chases the table above instead of being
-- it. The four speeds are the decomp's defaults verbatim, and the
-- asymmetry between the first and the rest is the single most important
-- number in this file:
--
--   focHSpeed 0.8   the camera TURNS to look at you, fast
--   focVSpeed 0.3   but not vertically -- a jump must not tilt the frame
--   posHSpeed 0.3   and it FLIES to where it wants to stand, slowly
--   posVSpeed 0.3
--
-- Set all four equal and the result is a competent camera that feels
-- nothing like SM64. The gap is the feel: run away and the operator is
-- already looking at you while still catching up.
local lakitu = {
  curFocus = { 0, 0, 0 },
  curPos = { 0, 0, 0 },
  goalFocus = { 0, 0, 0 },
  goalPos = { 0, 0, 0 },
  focHSpeed = 0.8,
  focVSpeed = 0.3,
  posHSpeed = 0.3,
  posVSpeed = 0.3,
  -- post-smoothing offsets: see the shake section. Kept OUT of cur* so a
  -- finished shake leaves no drift behind.
  shakePitch = 0, shakeYaw = 0, shakeRoll = 0,
  fov = 45,
  fovOffset = 0,
  -- CAM_FLAG_SMOOTH_MOVEMENT. Off means the next update CUTS instead of
  -- chasing: warps, map changes, the first frame of the mode. Without it
  -- the operator flies through the scenery on every teleport.
  smooth = false,
}

MarioCam.cam = cam
MarioCam.lakitu = lakitu

-- ------- focus_on_mario
--
-- Place `pos` at (dist, pitch, yaw) from `focus`, with the two Y offsets
-- the decomp carries separately -- one lifts the camera, the other lifts
-- what it looks at, and they are not the same number.
--
-- +Z is SOUTH in this world (a resting character faces +Z, toward a camera
-- parked to the south -- see the note at the top of Voxel3D). So yaw 0
-- puts the camera due south of its focus, which is exactly where the
-- existing orbit stands, and the port starts from the pose the mod
-- already has rather than from a rotated one.
local function focusOnPlayer(focus, pos, posYOff, focYOff, dist, pitch, yaw)
  local flat = dist * coss(pitch)
  pos[1] = focus[1] + flat * sins(yaw)
  pos[2] = focus[2] + dist * sins(pitch) + posYOff
  pos[3] = focus[3] + flat * coss(yaw)
  focus[2] = focus[2] + focYOff
end

-- vec3f_get_dist_and_angle: the inverse, which the mode transitions need
-- because they interpolate in SPHERICAL coordinates (see setMode).
local function distAndAngle(from, to)
  local dx = to[1] - from[1]
  local dy = to[2] - from[2]
  local dz = to[3] - from[3]
  local flat = math.sqrt(dx * dx + dz * dz)
  local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
  local pitch = atan2s(dy, flat)
  local yaw = atan2s(dx, dz)
  return dist, pitch, yaw
end

-- clamp_pitch: an explicit clamp, not an emergent one. Stops a mode from
-- looking straight down or straight up where that would destroy the
-- framing, and the decomp does it as its own step rather than hoping the
-- geometry never gets there.
local function clampPitch(pitch, maxPitch, minPitch)
  local p = signed(pitch)
  if p > maxPitch then p = maxPitch end
  if p < minPitch then p = minPitch end
  return s16(p)
end

-- ------------------------------------------------- struct PlayerGeometry --
--
-- The ground under the player, and the ground under them LAST frame.
--
-- Keeping the previous value is not bookkeeping, it is what lets the rest
-- of the file detect TRANSITIONS instead of states. "The player just
-- stepped onto this" and "the player has been standing here for ten
-- seconds" are different questions, and only one of them should move a
-- camera. SM64 uses exactly this to fire its rotate-surface triggers, and
-- the door and water handling below uses it for the same reason.
local geo = {
  currFloorHeight = 0, prevFloorHeight = 0,
  currCell = nil, prevCell = nil,
  currWalkable = true,
  moving = false,
  facing = "down",
  px = 0, pz = 0,          -- player centre, world pixels
  map = nil,
  indoors = false,
  onWater = false,
}

MarioCam.geo = geo

local function game()
  local ok, G = pcall(require, "src.core.Game")
  return ok and G or nil
end

-- Ground height under a CELL, through the same query every other module in
-- this mod uses -- so the camera stands on the terrain the mesher actually
-- built rather than on a second opinion about it.
local ghCache, ghStamp = {}, -1
local function groundAt(map, cx, cy)
  if not map then return 0 end
  local t = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
  if t ~= ghStamp then
    for k in pairs(ghCache) do ghCache[k] = nil end
    ghStamp = t
  end
  local key = cx * 4096 + cy
  local hit = ghCache[key]
  if hit then return hit end
  local ok, h = pcall(V.require("VoxelScene").groundAt, map, cx, cy)
  h = (ok and tonumber(h)) or 0
  ghCache[key] = h
  return h
end

MarioCam.groundAt = groundAt

local function walkable(map, cx, cy)
  if not map then return true end
  local ok, w = pcall(map.isWalkableCell, map, cx, cy)
  if not ok then return true end
  return w and true or false
end

-- The REAL height standing over a cell, for line-of-sight: the mesher's
-- extruded ground, or the stamped building model above it -- whichever is
-- taller. groundAt alone reports a building's footprint as ankle height
-- (the mesher paints flat ground under models), which parked the camera
-- behind five storeys of roof with a clear conscience. Buildings is
-- fetched lazily and through pcall for the same reason game() is: this
-- must degrade to the old answer, never error, on a build without it.
local BuildingsMod
local function occluderHeight(map, cx, cy)
  local h = groundAt(map, cx, cy)
  if BuildingsMod == nil then
    local ok, B = pcall(V.require, "Buildings")
    BuildingsMod = (ok and B) or false
  end
  if BuildingsMod then
    local ok, t = pcall(BuildingsMod.tallAt, map, cx, cy)
    if ok and t and t > h then h = t end
  end
  return h
end

-- Refresh the geometry from the live overworld. Returns false when there
-- is no player to stand behind, which is every frame of a menu, a battle
-- screen or a warp -- and the camera simply holds its last pose through
-- those rather than chasing a nil.
local function findPlayerFloor()
  local G = game()
  local ow = G and G.overworld
  local p = ow and ow.player
  local map = ow and ow.map
  if not (p and map) then return false end

  geo.prevFloorHeight = geo.currFloorHeight
  geo.prevCell = geo.currCell

  local px = (p.px or 0) + 8
  local pz = (p.py or 0) + 8
  geo.px, geo.pz = px, pz
  geo.map = map
  geo.facing = p.facing or "down"
  -- the walk cycle or a ledge hop's lift: "actively stepping", which is
  -- the same test the ground effects use for the same reason
  geo.moving = (math.abs(p.lift or 0) > 0.15) or p.phase == 1

  local cx = math.floor(px / 16)
  local cy = math.floor(pz / 16)
  geo.currCell = cx * 4096 + cy
  geo.currFloorHeight = groundAt(map, cx, cy)
  geo.currWalkable = walkable(map, cx, cy)

  local okOut, out = pcall(Map.isOutdoor, map.def)
  geo.indoors = not (okOut and out)
  -- surfing: the engine's own flag if it has one, else the tile. Kept
  -- tolerant because it decides a MODE, and being wrong about it should
  -- cost a framing rather than an error.
  local okW, w = pcall(function() return ow.surfing or p.surfing end)
  geo.onWater = (okW and w) and true or false

  -- first sighting: no previous frame to ease from
  if geo.prevCell == nil then
    geo.prevCell = geo.currCell
    geo.prevFloorHeight = geo.currFloorHeight
  end
  return true
end

-- ------- calc_y_to_curr_floor, and why the camera ignores a jump
--
-- The camera's height comes from THE HEIGHT OF THE FLOOR UNDER THE PLAYER,
-- never from the player's own Y. Jump 500 units in SM64 and the floor has
-- not moved, so the camera barely does. Walk off a cliff and the floor
-- under you has changed, so it descends -- slowly, because the vertical
-- speed is 0.3.
--
-- On this world the player does not jump, but the terrain is extruded and
-- they walk up onto walls, ledges, bridges and building steps constantly.
-- Feeding the camera the raw height of every step would bob the whole
-- frame once per cell walked. Feeding it the FLOOR, through a vertical
-- chase at 0.3, gives the ride SM64 gives.
local function floorY()
  return geo.currFloorHeight
end

-- ------------------------------------------------ pan, and the dead zone --

-- pan_ahead_of_player: push the focus a little the way the player is
-- going, so the frame shows where they are HEADED rather than where they
-- have been. Small, and one of the things that is only noticeable when it
-- is missing.
--
-- Kept as its own accumulated value (the decomp's `panDist`) rather than
-- recomputed from the facing every frame, because facing flips instantly
-- on this world -- turn round on the spot and a directly-computed pan
-- would snap the focus across the player in one frame.
MarioCam.PAN_MAX = 220 / U        -- SM64 units of lead, at a walk
MarioCam.PAN_IN = 0.09            -- gained per moving frame, at 30fps
MarioCam.PAN_OUT = 0.06           -- and lost per resting frame

local pan = { x = 0, z = 0 }

local FACE_VEC = {
  up    = { 0, -1 },
  down  = { 0,  1 },
  left  = { -1, 0 },
  right = {  1, 0 },
}

local function panAheadOfPlayer(dt)
  local v = FACE_VEC[geo.facing] or FACE_VEC.down
  local want = geo.moving and MarioCam.PAN_MAX or 0
  local k = rate(geo.moving and MarioCam.PAN_IN or MarioCam.PAN_OUT, dt)
  pan.x = approachF32(pan.x, v[1] * want, k)
  pan.z = approachF32(pan.z, v[2] * want, k)
  return pan.x, pan.z
end

-- ------- the dead zone
--
-- The cheapest and most effective trick against micro-tremor, and the one
-- SM64 uses in several places (`distThresh` on the parallel-tracking rail
-- is the clearest). The camera does not react at all until the thing it
-- follows has moved past a threshold.
--
-- It earns more here than it does in SM64. This player moves in 16-pixel
-- grid steps at a fixed cadence, so a camera that tracks continuously is
-- being driven by a staircase; a dead zone a little under one cell turns
-- that staircase back into standing still between steps.
MarioCam.DEAD_ZONE = 90 / U       -- SM64 units, a bit over half a cell
-- how fast the zone recentres once the player stops, per frame at 30fps
MarioCam.DEAD_RECENTER = 0.06

local anchor = { x = nil, z = nil }

local function deadZoned(x, z, dt)
  if anchor.x == nil then
    anchor.x, anchor.z = x, z
    return x, z
  end
  local dx, dz = x - anchor.x, z - anchor.z
  local d = math.sqrt(dx * dx + dz * dz)
  local r = MarioCam.DEAD_ZONE
  if d > r then
    -- drag the anchor along behind the rim rather than snapping it to the
    -- player: the camera leaves the zone at the speed the player left it,
    -- with no step at the boundary
    local k = (d - r) / d
    anchor.x = anchor.x + dx * k
    anchor.z = anchor.z + dz * k
  elseif not geo.moving then
    -- AND IT RECENTRES AT REST, which a plain leash does not.
    --
    -- A zone that only ever trails leaves the frame permanently off centre
    -- by its own radius, in whichever direction the player last walked --
    -- so standing still would look different depending on how you arrived,
    -- and it would half-cancel the forward lead pan_ahead is there to give.
    -- Walking is when the grid staircase needs suppressing; standing still
    -- is when being centred matters. So the zone does both.
    local k = rate(MarioCam.DEAD_RECENTER, dt or 0)
    anchor.x = approachF32(anchor.x, x, k)
    anchor.z = approachF32(anchor.z, z, k)
  end
  return anchor.x, anchor.z
end

-- ------------------------------------------------------ player controls --
--
-- SM64 gives the player C-left/C-right to rotate, C-up/C-down to zoom, and
-- R to swap to an alternate mode -- and the design note behind all of it
-- is that the player is a CO-DIRECTOR: rather than try to predict every
-- bad framing, give them the tools to leave one.
--
-- The N64 pad's C buttons are four discrete presses, which is why SM64
-- rotates in 60-degree jumps. This machine has a right stick and a
-- keyboard, so the discrete steps are kept AND a continuous axis is added
-- -- the source doc lists that under "where to diverge" for the plain
-- reason that the hardware reason for the steps is gone.
--
-- The Game Boy buttons are untouched: every one of them is spoken for by
-- the game, and a camera that ate one would be a camera that broke it.

MarioCam.ZOOMS = { 800 / U, 1400 / U, 2000 / U }   -- close, default, far
MarioCam.ZOOM_DEFAULT = 2

-- SM64's first C press swings 60 degrees; a second press in the same
-- direction runs on to the area's limit. Kept, with the limit being the
-- yaw clamp of the current rung rather than an area's authored bound.
MarioCam.C_STEP = degrees(60)
MarioCam.EIGHT_STEP = degrees(45)

local ctl = {
  zoom = MarioCam.ZOOM_DEFAULT,
  offsetYaw = 0,          -- sModeOffsetYaw: the player's deflection
  goalOffsetYaw = 0,
  lastCDir = 0,           -- which way the last C press went, for the run-on
  alt = false,            -- the R button: alternate mode engaged
  buzz = false,           -- a refused input this frame, for the feedback
}

MarioCam.ctl = ctl

-- The stick, read straight from LOVE rather than through the engine's
-- Input: the engine maps a pad to Game Boy buttons and has no concept of a
-- second stick, so there is nothing there to ask. Nothing is bound that
-- the game uses.
local function rightStick()
  if not (love.joystick and love.joystick.getJoysticks) then return 0, 0 end
  local ok, sticks = pcall(love.joystick.getJoysticks)
  if not (ok and sticks and sticks[1]) then return 0, 0 end
  local js = sticks[1]
  if not (js.isGamepad and js:isGamepad()) then return 0, 0 end
  local okx, x = pcall(js.getGamepadAxis, js, "rightx")
  local oky, y = pcall(js.getGamepadAxis, js, "righty")
  x = (okx and tonumber(x)) or 0
  y = (oky and tonumber(y)) or 0
  -- the same deadzone shape the engine uses on the left stick, so a worn
  -- pad does not creep the camera round while nobody is touching it
  if math.abs(x) < 0.25 then x = 0 end
  if math.abs(y) < 0.25 then y = 0 end
  return x, y
end

-- ------------------------------------------------------------ the rungs --
--
-- ON or OFF, and nothing in between.
--
-- This was a four-rung ladder -- OFF / SOFT / RADIAL / FREE -- and every
-- rung above OFF existed for ONE reason: the D-pad did not turn with the
-- camera, so every degree the camera swung was a degree of disagreement
-- between the button and the screen, and the ladder was how much of that
-- disagreement a player was willing to put up with.
--
-- Camera-relative movement removed the reason. Up now means "away from the
-- camera" at every angle (see MarioCam.buttonFor), so there is no
-- disagreement left to ration, and a ladder that rations nothing is three
-- extra things to explain. What is left is the camera: on, or not.
--
-- ON is the whole of it -- the orbit around the area centre, unclamped,
-- the two-layer chase, the floor-derived height, the pan, the dead zone,
-- the wall avoidance, the shake, camera-relative movement, and the sprite
-- chosen by the angle the camera sees. OFF is the free-roam orbit exactly
-- as it was before any of this existed.
--
-- SHOULDER is the third answer, and it is a STYLE rather than a ration:
-- the same rig as ON -- same chase, same avoidance, same relative input,
-- same authored shots -- but the default mode everywhere is BEHIND, the
-- over-the-shoulder follow modern RPGs park on. The camera stays at the
-- player's back at every step, closer and lower than the orbit, so the
-- frame is always "me, and where I am going".
MarioCam.MODES = { "off", "on", "shoulder" }
MarioCam.MODE_LABELS = { "OFF", "ON", "SHOULDER" }

MarioCam.setting = ModSetting.new("mariocam", "SM64CAM",
                                  MarioCam.MODES, MarioCam.MODE_LABELS)

function MarioCam.rung()
  local ok, v = pcall(MarioCam.setting.get, MarioCam.setting)
  return (ok and v) or "off"
end

function MarioCam.enabled()
  return MarioCam.rung() ~= "off" and Voxel.active()
end

function MarioCam.row()
  return MarioCam.setting:row()
end

function MarioCam.sync(value)
  MarioCam.setting:sync(value)
end

-- ------- HOW FAR THE CAMERA MAY TURN: all the way.
--
-- These two used to answer a rung -- a quarter turn on RADIAL, pinned on
-- SOFT -- and now they answer "no limit", because the clamp only ever
-- protected the player from a D-pad that no longer needs protecting. They
-- are kept as functions rather than deleted because they are the seam
-- where a limit would go back if one were ever wanted (an authored shot
-- that must not be spun out of frame, say), and because every caller reads
-- better asking a question than testing a constant.
--
-- nil means no clamp.
local function yawLimit()
  return nil
end

local function avoidLimit()
  return nil
end

-- ------------------------------------------------------------ the modes --
--
-- Fifteen in SM64. Five here, and the count is the honest one: a mode
-- exists in SM64 because a LEVEL needed it, and this world has five kinds
-- of place -- open outdoors, a room, a run of authored framing, deep
-- water, and a staged shot. Porting SPIRAL_STAIRS to a game with no
-- spiral stairs would be a table entry that never fires.
--
-- Dispatch is a table of functions, as it is there (sModeTransitions), so
-- a mode change at runtime is a table lookup and nothing more.

local modes = {}

-- ------- what a shot may PIN, and what that costs the player
--
-- A shot that pins the orbit's scalars -- or stands somewhere fixed -- has
-- taken framing decisions away from the player, and the player's framing
-- keys must say so OUT LOUD rather than silently doing nothing: a key that
-- goes quiet reads as a broken key, which is the exact failure the buzz
-- exists for (play_camera_buzz_if_cbutton). A shot that only names a MODE
-- (an "eight" corridor, a "behind" jetty) pins nothing, and the keys keep
-- working inside it.
local function shotRefusesFraming()
  local s = cam.shot
  if not s then return false end
  return (s.mode or "fixed") == "fixed"
         or s.zoom ~= nil or s.pitch ~= nil
end

-- The two pins. Zoom is a DISTANCE in world pixels at the 144-line frame
-- (the same scale ZOOMS speaks); pitch is DEGREES above the horizon, the
-- convention the source doc uses for SM64's own numbers. Both clamp the
-- same way the things they replace clamp, so a typo in a data file costs a
-- framing rather than a matrix full of NaN.
local function shotDist(vh, base)
  local s = cam.shot
  local z = s and tonumber(s.zoom)
  if not z then return base end
  if z < 40 then z = 40 elseif z > 400 then z = 400 end
  return z * (vh / 144)
end

local function shotPitch(base)
  local s = cam.shot
  local p = s and tonumber(s.pitch)
  if not p then return base end
  return clampPitch(degrees(p), degrees(87), degrees(4))
end

-- The pitch every ground mode starts from.
--
-- It comes from the VOXEL ladder rather than from a constant of our own,
-- because that ladder is the row the player already set and a camera mode
-- that ignored it would be overriding a stated preference. Voxel.angle is
-- measured from straight down and SM64's pitch from the horizon, so the
-- two are complements.
local function ladderPitch()
  local base = math.pi / 2 - (Voxel.angle or 0)
  return clampPitch(s16(base * S16 / (2 * math.pi)),
                    degrees(87), degrees(4))
end

-- ------- CAMERA_MODE_RADIAL, and the thing everyone gets wrong
--
-- THE RADIAL CAMERA DOES NOT ORBIT THE PLAYER. It orbits a fixed point of
-- the AREA. That one sentence is the whole mode, and it is why Bob-omb
-- Battlefield feels the way it does: run round the mountain and the camera
-- slides along the mountain's edge keeping the mountain between you and
-- it, because the level was built around an axis and the camera respects
-- the axis rather than your back.
--
--     yaw = atan2s(playerZ - areaCenZ, playerX - areaCenX) + offsetYaw
--
-- The area centre here is THE MAP'S OWN CENTRE. That is not a stand-in: a
-- Gen 1 map is a hand-drawn rectangle with its business in the middle --
-- a town's buildings ring its square, a route runs up its spine, a gym is
-- one room about its own axis -- and orbiting that centre gives exactly
-- the behaviour the mode is for. Walk the west edge of Pallet and the
-- camera looks east across the town; walk the east edge and it looks west.
--
-- offsetYaw is the player's deflection ADDED ON TOP, which is why the C
-- buttons do not "take control" of the radial camera and break it: you are
-- sliding the orbit round, not seizing it.
function modes.radial(dt, vh)
  local dx = geo.px - cam.areaCenX
  local dz = geo.pz - cam.areaCenZ
  -- Dead centre has no direction, and the atan2 there is not merely
  -- undefined, it SPINS: a player crossing the exact middle of a map would
  -- whip the camera through half a turn in one frame. Inside the deadzone
  -- the last good yaw is held, which is what standing on the axis should
  -- look like.
  --
  -- AND THE APPROACH TO THE CENTRE IS SLEWED, because the deadzone alone
  -- only fixes the point and not the neighbourhood: atan2's derivative
  -- grows without bound as the radius shrinks, so a walk PAST the middle
  -- at thirty pixels' clearance still spun the camera through most of a
  -- half turn in under a second -- SM64 never meets this because its area
  -- centres are mountains you cannot stand on, and a Gen 1 town square is
  -- exactly the middle of the map. Inside six cells the yaw eases toward
  -- the true bearing at a rate that falls with the radius; past that the
  -- bearing is taken as read, which is the behaviour this mode always had.
  local auto = cam.autoYaw or 0
  local d2 = dx * dx + dz * dz
  if d2 > (24 * 24) then
    local target = atan2s(dx, dz)
    local d = math.sqrt(d2)
    if d >= 96 or cam.autoYaw == nil then
      auto = target
    else
      auto = approachS16(auto, target, rateDiv(4 + (96 - d) * 0.5, dt))
    end
    cam.autoYaw = auto
  end

  -- the automatic orbit plus the player's own deflection, which is why the
  -- C buttons do not "take control" of the radial camera and break it: you
  -- are sliding the orbit round, not seizing it
  local limit = yawLimit()
  local yaw = s16(auto + ctl.offsetYaw)
  if limit then
    local d = signed(yaw)
    if d > limit then yaw = s16(limit) end
    if d < -limit then yaw = s16(-limit) end
  end
  cam.yaw = yaw
  cam.pitch = shotPitch(ladderPitch())
  cam.dist = shotDist(vh, MarioCam.ZOOMS[ctl.zoom] * (vh / 144))

  local px, pz = deadZoned(geo.px, geo.pz, dt)
  local ax, az = panAheadOfPlayer(dt)
  cam.focus[1] = px + ax
  cam.focus[2] = floorY()
  cam.focus[3] = pz + az
  focusOnPlayer(cam.focus, cam.pos, 0, 0, cam.dist, cam.pitch, cam.yaw)
end

-- ------- CAMERA_MODE_CLOSE
--
-- The radial geometry at a shorter distance, which is what SM64 uses
-- indoors (the castle's rooms, Big Boo's Haunt). It shares
-- update_mario_camera with WATER_SURFACE there for the same reason it
-- shares code with the radial here: the behaviour differs by a PARAMETER,
-- not by an algorithm, and giving it its own function would be two copies
-- of one idea drifting apart.
--
-- A Pokemon interior is small enough that the outdoor distance puts the
-- eye through the back wall, so this is not a stylistic close-up, it is
-- the room being four cells deep.
function modes.close(dt, vh)
  local savedZoom, savedDead = ctl.zoom, MarioCam.DEAD_ZONE
  ctl.zoom = 1
  -- a room is small and the steps within it are the whole picture, so the
  -- zone that suppresses them has to shrink with the shot
  MarioCam.DEAD_ZONE = savedDead * 0.5
  modes.radial(dt, vh)
  ctl.zoom, MarioCam.DEAD_ZONE = savedZoom, savedDead
end

-- ------- CAMERA_MODE_8_DIRECTIONS
--
-- Yaw locked to 45-degree detents, and it does NOT track anything: the
-- camera holds its bearing until the player changes it. SM64 uses it in
-- the Bowser stages and Rainbow Ride, both places where an orbiting
-- camera would make a jump between two platforms unreadable.
--
-- The Pokemon case for it is the same case: a corridor, a bridge, a cave
-- passage -- anywhere the automatic yaw would swing while the player is
-- trying to judge a line. Reached with R (see the alternate mode).
function modes.eight(dt, vh)
  local step = MarioCam.EIGHT_STEP
  local detent = s16(math.floor((signed(ctl.offsetYaw) / step) + 0.5) * step)
  local limit = yawLimit()
  if limit then
    local d = signed(detent)
    if d > limit then detent = s16(math.floor(limit / step) * step) end
    if d < -limit then detent = s16(-math.floor(limit / step) * step) end
  end
  cam.yaw = detent
  cam.pitch = shotPitch(ladderPitch())
  cam.dist = shotDist(vh, MarioCam.ZOOMS[ctl.zoom] * (vh / 144))

  local px, pz = deadZoned(geo.px, geo.pz, dt)
  local ax, az = panAheadOfPlayer(dt)
  cam.focus[1] = px + ax
  cam.focus[2] = floorY()
  cam.focus[3] = pz + az
  focusOnPlayer(cam.focus, cam.pos, 0, 0, cam.dist, cam.pitch, cam.yaw)
end

-- ------- CAMERA_MODE_BEHIND_MARIO
--
-- Sits behind and follows the facing. SM64 switches to it underwater,
-- because swimming lets Mario control his own pitch and a camera in orbit
-- around a swimmer shows the swimmer's side instead of where they are
-- going.
--
-- Surfing is this world's swimming: the player crosses open water with no
-- landmarks, and the orbit -- keyed off the MAP's centre -- has nothing
-- useful to say out there. Behind the player it is, which also puts the
-- water they are heading into in frame.
-- Two tunings of the same follow: the WATER one (swimming has no
-- landmarks, the camera just keeps the heading readable) and the SHOULDER
-- rung's (an over-the-shoulder that lives closer, sits lower, turns a
-- touch quicker, and leads the walk with the pan -- the frame modern RPGs
-- park on). One function, because they are one idea at two distances.
MarioCam.SHOULDER_DIST = 0.7          -- of the zoom rung's distance
MarioCam.SHOULDER_DROP = 18           -- degrees below the VOXEL ladder

-- ------- THE FOLLOW COMMITS, IT DOES NOT TWITCH
--
-- The first cut of this mode aimed the camera at the FACING, and on a
-- grid game that is a washing machine: Pokemon movement is up, right,
-- up, right, a re-aim of the entire world on every tap, and the player
-- called it exactly what it was -- dizzying, "changing out of nowhere".
-- A modern follow camera on a grid holds its heading and lets the
-- character turn WITHIN the frame; it only re-aims when the player has
-- COMMITTED to a direction -- walked it, continuously, for long enough
-- to mean it. Turning in place moves nothing. A one-cell side-step moves
-- nothing. A held walk swings the world once, to the new back, and
-- holds again.
MarioCam.FOLLOW_COMMIT = 0.6          -- seconds of sustained walk to re-aim

local follow = { heading = nil, facing = nil, commit = 0, lull = 0 }

function modes.behind(dt, vh)
  local shoulder = MarioCam.rung() == "shoulder"
  local v = FACE_VEC[geo.facing] or FACE_VEC.down
  -- the camera stands OPPOSITE the facing, and cam.yaw is focus-to-pos, so
  -- it is the facing negated
  local faceGoal = atan2s(-v[1], -v[2])

  -- the commitment clock: same facing, actually walking, long enough.
  -- geo.moving flickers between grid steps (a lesson the walk-clock bug
  -- taught), so a short lull is forgiven rather than resetting the count.
  if geo.facing ~= follow.facing then
    follow.facing = geo.facing
    follow.commit = 0
  end
  if geo.moving then
    follow.commit = follow.commit + dt
    follow.lull = 0
  else
    follow.lull = follow.lull + dt
    if follow.lull > 0.2 then follow.commit = 0 end
  end
  if follow.heading == nil or follow.commit >= MarioCam.FOLLOW_COMMIT then
    follow.heading = faceGoal
  end
  local goal = follow.heading
  -- a slow swing, because the facing here snaps between four values and a
  -- fast one would whip the world round on every turn; the shoulder rung
  -- takes it slightly quicker, since turning is its whole steering wheel.
  --
  -- EXCEPT THE ABOUT-FACE. Walking back toward the lens flips the goal a
  -- half turn, and at the polite divisor the camera ambles through an
  -- entire side view before it finds the new back -- which reads as the
  -- operator being lost, not smooth. A reversal is the one turn the
  -- follow answers URGENTLY (divisor 3, at the player's back again in a
  -- third of a second); the quarter turns keep the amble.
  -- ...and the urgency LATCHES for the whole turn: gating on the raw gap
  -- re-slows the swing the moment it gets going (the gap falls under the
  -- threshold after three frames and the amble was back -- the unit probe
  -- measured the fast path never engaging). Armed past 120, released
  -- under 25, so one reversal is answered start to finish.
  local gap = math.abs(signed(goal - cam.yaw))
  if shoulder and gap > degrees(120) then cam.reversing = true end
  if cam.reversing and gap < degrees(25) then cam.reversing = nil end
  local div = shoulder and 6 or 8
  if shoulder and cam.reversing then div = 3 end
  cam.yaw = approachS16(cam.yaw, goal, rateDiv(div, dt))
  -- lower than the orbit: looking ALONG the world rather than down at it
  local drop = degrees(shoulder and MarioCam.SHOULDER_DROP or 10)
  cam.pitch = shotPitch(clampPitch(ladderPitch() - drop,
                                   degrees(70), degrees(3)))
  local factor = shoulder and MarioCam.SHOULDER_DIST or 0.85
  cam.dist = shotDist(vh, MarioCam.ZOOMS[ctl.zoom] * (vh / 144) * factor)

  local px, pz = deadZoned(geo.px, geo.pz, dt)
  local ax, az = 0, 0
  if shoulder then
    -- the walk leads the frame: over a shoulder, "where I am going" is
    -- the whole point of the composition
    ax, az = panAheadOfPlayer(dt)
  end
  cam.focus[1] = px + ax
  cam.focus[2] = floorY()
  cam.focus[3] = pz + az
  focusOnPlayer(cam.focus, cam.pos, 0, 0, cam.dist, cam.pitch, cam.yaw)
end

-- ------- CAMERA_MODE_FIXED
--
-- A point in the world the camera stands at and does not leave; it only
-- turns to keep the player in frame. SM64's castle rooms and BBH are made
-- of these, placed by hand.
--
-- Placed here by data/camera_shots.lua, which is this port's answer to
-- section 10 of the source document: its most repeated lesson is that no
-- generic algorithm beats an AUTHORED camera in the ten percent of hard
-- cases, and that those are the cases players remember. Without a table to
-- put one in, that lesson is unimplementable.
function modes.fixed(dt, vh)
  local shot = cam.shot
  -- camX/camY/camZ, NOT x/z: a trigger's x and z are where the BOX is, and
  -- a fixed shot needs a second point entirely -- where the camera stands.
  -- Reading the box's own centre would park the eye on top of the player
  -- every time, which is a fixed camera that is not fixed to anything.
  -- An entry that forgets them falls back to the orbit rather than to a
  -- camera at the world origin.
  if not (shot and shot.camX) then return modes.radial(dt, vh) end
  cam.pos[1] = shot.camX
  cam.pos[2] = shot.camY or 64
  cam.pos[3] = shot.camZ
  local px, pz = deadZoned(geo.px, geo.pz, dt)
  cam.focus[1] = px
  cam.focus[2] = floorY() + (shot.focY or 0)
  cam.focus[3] = pz
  local dist, pitch, yaw = distAndAngle(cam.pos, cam.focus)
  -- cam.* describe the shot FROM the focus (the inverted convention at the
  -- top of this file), so both angles come back reversed
  cam.dist = dist
  cam.pitch = s16(-signed(pitch))
  cam.yaw = s16(yaw + S16_HALF)
end

MarioCam.modes = modes

-- ------------------------------------------------ collision and occlusion --
--
-- Three mechanisms in SM64, and it is worth being clear that they are
-- three DIFFERENT problems rather than three attempts at one:
--
--   rotate_camera_around_walls    a wall is between the camera and the
--                                 player. ROTATE around it.
--   collide_with_walls            the camera is inside geometry. Push out.
--   resolve_geometry_collisions   the camera is under the floor. Lift.
--
-- The first is the important one and the one everybody reimplements
-- wrongly. The naive fix for "a wall is in the way" is to pull the camera
-- toward the player until it clears -- which produces a camera that zooms
-- in and out every time you walk past a doorway, and that is nauseating.
-- SM64 instead computes a direction PARALLEL TO THE WALL and eases the yaw
-- toward it, so the camera slides round the corner. The distance never
-- changes, so nothing pumps.

-- The arc, in yaw steps, that is swept looking for a blocker, and how
-- coarse the sweep is. Coarse on purpose: the answer only has to be good
-- enough to pick a side, and the easing does the rest.
MarioCam.WALL_ARC = degrees(80)
MarioCam.WALL_STEPS = 8
-- how much of the way to the parallel direction is closed per frame at
-- 30fps -- the decomp's divisor form, deliberately unhurried so the slide
-- reads as the operator stepping sideways rather than as a snap
MarioCam.WALL_DIV = 12

-- Is the straight line from the eye to the focus blocked, and if so which
-- way round is shorter? Samples the walkability grid along the ray: an
-- unwalkable cell in this world is extruded into a wall by the mesher, so
-- the collision the game already has IS the geometry the camera sees.
--
-- IN THREE DIMENSIONS, and the third one is the one that was missing. The
-- eye rides high -- at the default pitch it stands a hundred-odd pixels up
-- -- and its sightline DESCENDS toward the player, so a wall only hides
-- them where the line has already dropped below the wall's top, which is
-- the last stretch before the focus. The first version of this test was
-- flat: any tall-enough wall anywhere under the line counted, so the
-- camera steered around buildings it was plainly looking over the top of
-- -- a swing with no visible cause, and every spurious swing dragged the
-- input quadrant with it. The height of the ray at the sample is the whole
-- fix.
--
-- Reading collision rather than writing it -- the mod's invariant holds.
local function rayBlocked(map, ex, ey, ez, fx, fy, fz)
  if not map then return false end
  local dx, dz = fx - ex, fz - ez
  local len = math.sqrt(dx * dx + dz * dz)
  if len < 1 then return false end
  -- one sample per half cell: fine enough that a one-cell pillar cannot
  -- slip between two samples, coarse enough to stay cheap
  local n = math.min(48, math.floor(len / 8))
  if n < 2 then return false end
  local hit = 0
  for i = 1, n - 1 do
    local t = i / n
    local x = ex + dx * t
    local z = ez + dz * t
    local cx, cy = math.floor(x / 16), math.floor(z / 16)
    if not walkable(map, cx, cy) then
      -- A LOW WALL IS NOT AN OCCLUDER. SM64 checks that a wall is tall
      -- enough to actually hide Mario before it will steer around one, and
      -- without that test every fence, counter and flower bed on this
      -- world would swing the camera. The mesher's own height for the cell
      -- is the honest answer to "how tall is that".
      --
      -- AND A WALL BELOW THE SIGHTLINE IS NOT ONE EITHER: the ray's own
      -- height here, against the top of whatever stands there -- ground
      -- extrusion or a stamped building model, whichever is taller --
      -- with a little margin so a graze does not read as a block.
      local h = occluderHeight(map, cx, cy)
      if h > 12 and h > ey + (fy - ey) * t + 2 then
        hit = hit + 1
      end
    end
  end
  -- a single sample is a corner clipped in passing; two is a wall
  return hit >= 2
end

-- Can an eye at (dist, pitch, yaw) from this focus see the player? The one
-- question both the steering and its release ask, in one place so the two
-- cannot drift apart. The ray aims at the player's MIDDLE, not their feet:
-- what has to stay visible is the character, and the ground under them is
-- below every fence on the map.
local function eyeClear(map, focus, dist, pitch, yaw)
  local flat = dist * coss(pitch)
  local ex = focus[1] + flat * sins(yaw)
  local ey = focus[2] + dist * sins(pitch)
  local ez = focus[3] + flat * coss(yaw)
  return not rayBlocked(map, ex, ey, ez, focus[1], focus[2] + 8, focus[3])
end

-- probe seams: the unit probe drives these directly, with a stub map, to
-- pin the geometry without a game running
MarioCam.rayBlocked = function(...) return rayBlocked(...) end
MarioCam.eyeClear = function(...) return eyeClear(...) end

-- rotate_camera_around_walls: returns the yaw to ease toward, or nil when
-- nothing is in the way. Sweeps both directions from the current yaw and
-- takes the nearer clear one, which is the cheap stand-in for the decomp's
-- is_range_behind_surface -- and it has the property that matters, that
-- the answer is always PARALLEL to the obstruction rather than through it.
--
-- `tryYaw` is where the camera is actually standing (mode plus its current
-- deflection); `centerYaw` is where the MODE alone wants it. The block
-- test runs on the first and the sweep runs around the SECOND, and that
-- split is load-bearing: a sweep centred on the deflected yaw measures
-- "clear" relative to wherever the deflection has got to, so the goal
-- moves every time the offset does and the camera ratchets round chasing
-- its own tail -- the unit probe caught it pinned at the cap, a hundred
-- and ten degrees round, still blocked. Centred on the mode's yaw the
-- answer is absolute, the goal cannot exceed the arc, and a deflection
-- that cannot fit inside the arc is honestly reported as boxed in.
--
-- `bias` is which way the camera is ALREADY deflected. A sweep that always
-- tried clockwise first would, on a wall with clear air both sides, flip a
-- half-deflected camera across to the other side the moment the distances
-- tied. Trying the current side first makes the choice sticky, and a
-- sticky choice is what a person stepping sideways round a corner does:
-- they keep going the way they started.
local function avoidYaw(map, focus, dist, pitch, tryYaw, centerYaw, bias)
  if eyeClear(map, focus, dist, pitch, tryYaw) then return nil end
  local step = MarioCam.WALL_ARC / MarioCam.WALL_STEPS
  local first = (bias and bias < 0) and -1 or 1
  -- i = 0 is the mode's own yaw: a deflection whose reason has gone home
  -- should be told "home is clear" rather than handed a fresh detour
  for i = 0, MarioCam.WALL_STEPS do
    local d = step * i
    if eyeClear(map, focus, dist, pitch, s16(centerYaw + first * d)) then
      return s16(centerYaw + first * d)
    end
    if i > 0 and eyeClear(map, focus, dist, pitch, s16(centerYaw - first * d)) then
      return s16(centerYaw - first * d)
    end
  end
  -- boxed in on every side: a cupboard, a one-cell alcove, the inside of a
  -- cave mouth. Nothing to rotate toward, so say so and let the caller
  -- fall back on the one thing that always works (see resolveGeometry).
  return false
end

-- ------- THE DEFLECTION IS A THING THAT PERSISTS, and this is the bug it
-- fixes: the mode recomputes its yaw FROM SCRATCH every frame -- layer 1
-- holds no history, by design -- so an avoidance that eased "the current
-- yaw" toward the clear one was easing from the same starting point every
-- frame and applying a constant few percent of the swing, forever. The
-- camera never actually went round anything; it leant four degrees toward
-- the corner and stayed buried.
--
-- So the deflection lives HERE, as its own accumulated offset ON TOP of
-- whatever the mode says, growing toward the clear direction while the
-- view is blocked and easing home once the mode's own yaw is clear again.
-- The mode stays stateless; the steering owns its state; the two-layer
-- rule holds.
local avoid = { offset = 0 }
MarioCam.avoidState = avoid

-- how much of the way home is closed per frame at 30fps once nothing is in
-- the way -- slower than WALL_DIV, because leaving a corner is a relax and
-- arriving at one is a dodge
MarioCam.WALL_RELAX = 20
-- how long a block must STAND before the steering answers it at all: a
-- passing occlusion resolves itself and the camera must not have moved
MarioCam.WALL_DELAY = 0.25

-- resolve_geometry_collisions: the last line, and the only one allowed to
-- move the camera IN. Two jobs -- keep the eye above the ground it is
-- standing over, and pull it in when there is genuinely nowhere to stand.
-- The pull is the ugly answer and that is why it is here rather than in
-- the mode: it fires when rotating has already failed.
MarioCam.EYE_CLEARANCE = 90 / U     -- SM64 units above the floor it crosses

local function resolveGeometry(map, focus, pos, boxedIn)
  if boxedIn then
    -- walk in along the eye ray until the line is clear, and no further.
    -- Distinct from a zoom: this is a recovery, it lasts as long as the
    -- obstruction does, and the chase at 0.3 hides its edges.
    local dx, dz = pos[1] - focus[1], pos[3] - focus[3]
    local dy = pos[2] - focus[2]
    -- the deep rungs are the player hugging a tall wall with the orbit
    -- pinned behind it: an over-the-shoulder frame from twenty pixels out
    -- is tight, but visible-and-tight beats composed-and-blind, and the
    -- probe found real cells that needed them
    for _, t in ipairs({ 0.75, 0.55, 0.4, 0.28, 0.18, 0.12 }) do
      local ex, ez = focus[1] + dx * t, focus[3] + dz * t
      local ey = focus[2] + dy * t
      if not rayBlocked(map, ex, ey, ez, focus[1], focus[2] + 8, focus[3]) then
        pos[1], pos[3] = ex, ez
        pos[2] = ey
        break
      end
    end
  end
  -- and never below the terrain -- or inside the ROOF -- it is passing
  -- over: the stamped models count, or an eye at chest height over a
  -- building cell would sit inside five storeys of attic
  local cx = math.floor(pos[1] / 16)
  local cz = math.floor(pos[3] / 16)
  local floor = occluderHeight(map, cx, cz)
  local min = floor + MarioCam.EYE_CLEARANCE
  if pos[2] < min then pos[2] = min end
end

-- ---------------------------------------------------- mode transitions --
--
-- A cut between two modes would be horrible, so SM64 interpolates -- and
-- it interpolates in SPHERICAL coordinates about the focus, not in XYZ.
--
-- That is the whole trick and it is one line of difference. Lerping the
-- POSITIONS drives the camera through whatever stands between the two,
-- which is usually the building the mode changed because of. Lerping
-- dist, pitch and yaw makes it ARC around the player instead -- which is
-- what a camera operator walking from one spot to another would do.

local trans = { frame = 0, max = 0, dist = 0, pitch = 0, yaw = 0 }

function MarioCam.setMode(mode, frames)
  if mode == cam.mode then return end
  if not modes[mode] then return end
  -- the shot we are leaving, in spherical terms about the current focus
  local d, p, y = distAndAngle(lakitu.curFocus, lakitu.curPos)
  trans.dist, trans.pitch, trans.yaw = d, p, y
  trans.max = math.max(1, frames or 30)
  trans.frame = 0
  cam.mode = mode
end

-- Blend this frame's freshly computed target back toward the shot we came
-- from, by however much of the transition is left. Eases with the same
-- smoothstep the mod's own camera tween uses, so a mode change and a rung
-- change do not move at visibly different rates.
local function transitionNextState(dt)
  if trans.frame >= trans.max then return end
  trans.frame = trans.frame + dt * 30
  local t = math.min(1, trans.frame / trans.max)
  t = t * t * (3 - 2 * t)
  local d, p, y = distAndAngle(cam.focus, cam.pos)
  local dist = trans.dist + (d - trans.dist) * t
  -- the two angles blend the SHORT way, which is what signed() is for and
  -- what interpolating raw radians across the seam would get wrong
  local pitch = s16(trans.pitch + signed(p - trans.pitch) * t)
  local yaw = s16(trans.yaw + signed(y - trans.yaw) * t)
  local flat = dist * coss(pitch)
  cam.pos[1] = cam.focus[1] + flat * sins(yaw)
  cam.pos[2] = cam.focus[2] + dist * sins(pitch)
  cam.pos[3] = cam.focus[3] + flat * coss(yaw)
end

-- --------------------------------------------------- course processing --
--
-- camera_course_processing: what the WORLD gets to say about the camera,
-- before the mode runs. In SM64 this is two things -- the type of surface
-- under Mario, and the trigger volumes the level designer placed.
--
-- Both exist here. The surface type has a natural analogue (a Gen 1 map
-- knows whether it is outdoors, whether the player is surfing, and where
-- its doors are) and the volumes are the authored table, which is the
-- point of section 10 of the source document: the generic algorithm is
-- for the easy ninety percent, and the ten percent it cannot do is the
-- part players remember.

-- What this map wants by default, from what the map IS -- unless the
-- player chose the SHOULDER rung, which is one answer everywhere: the
-- rung is a promise about where the camera stands, and a promise that
-- broke at every door would not be one.
local function defaultModeFor()
  if MarioCam.rung() == "shoulder" then return "behind" end
  if geo.onWater then return "behind" end
  if geo.indoors then return "close" end
  return "radial"
end

-- Authored shots, keyed by map id. Optional: a mod without the data file
-- gets the generic camera everywhere, which is the same thing SM64 has in
-- the parts of a level nobody placed a trigger in.
local shots = nil
local function shotsFor(map)
  if shots == nil then
    local ok, t = pcall(V.data, "camera_shots")
    shots = (ok and type(t) == "table") and t or false
  end
  if not shots or not (map and map.def) then return nil end
  return shots[map.def.id] or shots[map.def.name]
end

-- Drop the cached table so the next frame re-reads the data file. The shot
-- editor's reload key (see main.lua) calls this after busting V.data's own
-- cache, which is what turns authoring from minutes per attempt into
-- seconds: edit the file, press the key, look.
function MarioCam.reloadShots()
  shots = nil
  -- and the loader's own cache, or the re-read reads the same table back
  pcall(V.uncacheData, "camera_shots")
end

-- ------- the shot editor's dump (see main.lua's TERRARIUM_SHOT_EDITOR)
--
-- The current pose, spoken in camera_shots.lua's OWN vocabulary and ready
-- to paste -- both spellings of it, because a spot does not know yet
-- whether it wants a parked camera or a pinned orbit. Authoring becomes:
-- walk there, frame it with the keys that already exist (q/e/f and the
-- VOXEL ladder), press the key, paste the one you meant.
function MarioCam.editorDump(vh)
  if not MarioCam.enabled() then return nil end
  vh = tonumber(vh) or 144
  local map = geo.map
  local id = map and map.def and (map.def.id or map.def.name) or "?"
  local cx, cy = math.floor(geo.px / 16), math.floor(geo.pz / 16)
  local e = lakitu.curPos
  local f = lakitu.curFocus
  local floor = groundAt(map, cx, cy)
  local d, p = distAndAngle(f, e)          -- pitch positive: eye above focus
  local pitchDeg = signed(p) * 360 / S16
  local zoom = d / (vh / 144)
  return string.format(
    "-- %s cell (%d,%d)  viewYaw %.1f  mode %s\n"
    .. "{ x = %d, z = %d, bx = 32, bz = 32, mode = \"fixed\",\n"
    .. "  camX = %d, camY = %d, camZ = %d, focY = %d },\n"
    .. "-- ...or the same spot as a pinned orbit:\n"
    .. "{ x = %d, z = %d, bx = 32, bz = 32, mode = \"radial\","
    .. " zoom = %d, pitch = %d },",
    id, cx, cy, math.deg(MarioCam.viewYaw()), cam.mode,
    math.floor(geo.px + 0.5), math.floor(geo.pz + 0.5),
    math.floor(e[1] + 0.5), math.floor(e[2] + 0.5), math.floor(e[3] + 0.5),
    math.floor(f[2] - floor + 0.5),
    math.floor(geo.px + 0.5), math.floor(geo.pz + 0.5),
    math.floor(zoom + 0.5), math.floor(pitchDeg + 0.5))
end


-- struct CameraTrigger: a box in world pixels that names a mode while the
-- player is inside it. boundsYaw is deliberately kept from the decomp --
-- it rotates the player's offset before the test, so a corridor that runs
-- diagonally does not need its trigger axis-aligned.
local function triggerAt(map, px, pz)
  local list = shotsFor(map)
  if not list then return nil end
  for i = 1, #list do
    local t = list[i]
    local dx, dz = px - t.x, pz - t.z
    if t.yaw and t.yaw ~= 0 then
      local c, s = coss(t.yaw), sins(t.yaw)
      dx, dz = dx * c - dz * s, dx * s + dz * c
    end
    if math.abs(dx) <= (t.bx or 32) and math.abs(dz) <= (t.bz or 32) then
      return t
    end
  end
  return nil
end

local function courseProcessing()
  -- THE MAP CHANGED. Not a mode change -- a CUT. The camera must not fly
  -- from the last map's coordinates to this one's, and the flag that says
  -- so is exactly CAM_FLAG_SMOOTH_MOVEMENT being cleared. Without this,
  -- every door in the game is a second of the operator swimming through
  -- the scenery.
  local map = geo.map
  if map ~= cam.lastMap then
    cam.lastMap = map
    lakitu.smooth = false
    anchor.x, anchor.z = nil, nil
    pan.x, pan.z = 0, 0
    cam.autoYaw = nil
    avoid.offset = 0
    avoid.blocked = 0
    follow.heading, follow.facing = nil, nil
    follow.commit, follow.lull = 0, 0
    cam.shot = nil
    -- a map change is a cut, and the lens cuts with it: easing a leftover
    -- shot's 30-degree lens back to 45 across a door would be the one
    -- gradual thing in a frame where everything else snapped
    MarioCam.setFov("SET", MarioCam.FOV_DEFAULT)
    ctl.offsetYaw, ctl.goalOffsetYaw = 0, 0
    ctl.alt = false
    -- the area centre, which is the whole of the radial mode's behaviour
    local w = (map and map.widthCells or 20) * 16
    local h = (map and map.heightCells or 18) * 16
    cam.areaCenX, cam.areaCenZ = w / 2, h / 2
    cam.defMode = defaultModeFor()
    cam.mode = cam.defMode
    trans.frame, trans.max = 0, 0
    return
  end

  local want = defaultModeFor()
  local prevShot = cam.shot
  local shot = triggerAt(map, geo.px, geo.pz)
  cam.shot = shot
  if shot then
    want = shot.mode or "fixed"
  end
  -- R: the alternate mode, exactly SM64's R button. The alternate is the
  -- eight-direction camera, because that is the one that answers the
  -- complaint the automatic camera generates -- "it keeps turning while I
  -- am trying to line something up".
  if ctl.alt and not shot then want = "eight" end
  cam.defMode = want

  -- ------- the lens rides the shot, gradually both ways
  --
  -- A shot's `fov` is APPROACHED on the way in and RELEASED back to the
  -- default on the way out, over the shot's own transition length -- the
  -- SET/APP lesson: an instant lens change is a cut, and walking over a
  -- painted box on the floor is not a cut. The clamp is the safety net for
  -- a typo in the data file: 20 is already tight and 60 already wide, and
  -- past either the world stops reading as the same world.
  if shot ~= prevShot then
    local fovDeg = shot and tonumber(shot.fov) or nil
    if fovDeg then
      if fovDeg < 20 then fovDeg = 20 elseif fovDeg > 60 then fovDeg = 60 end
      MarioCam.setFov("APP", fovDeg, shot.frames or 30)
    elseif prevShot and prevShot.fov then
      MarioCam.setFov("APP", MarioCam.FOV_DEFAULT, prevShot.frames or 30)
    end
  end

  if want ~= cam.mode then
    -- the door and warp case gets a short transition and the rest a
    -- longer one, for the reason set_camera_mode takes a frame count at
    -- all: an urgent change should look urgent -- and an authored shot
    -- gets to say how urgent it is
    local frames = (shot and tonumber(shot.frames))
                   or ((want == "close" or cam.mode == "close") and 12 or 30)
    MarioCam.setMode(want, frames)
  end
end

-- ------------------------------------------------------------- the shake --
--
-- Applied AFTER the smoothing, as an angular offset on the finished
-- result, and that placement is the design: the shake never enters the
-- camera's own state, so when it decays there is nothing to unwind and no
-- drift left behind. A shake written into cur* would be a shake the chase
-- then has to chase back out.
--
-- One damped cosine per axis: Vel is the angular frequency, Decay eats the
-- magnitude per frame, Phase is where in the cycle it is.

local shake = {
  pitchMag = 0, pitchPhase = 0, pitchVel = 0, pitchDecay = 0,
  yawMag = 0, yawPhase = 0, yawVel = 0, yawDecay = 0,
  rollMag = 0, rollPhase = 0, rollVel = 0, rollDecay = 0,
  fovMag = 0, fovPhase = 0, fovVel = 0, fovDecay = 0,
}

-- The decomp's presets, in the same shape and with the same names, so a
-- caller can ask for SHAKE_ATTACK rather than for three numbers.
-- { magnitude (s16), velocity (s16 per frame), decay (s16 per frame) }
MarioCam.SHAKES = {
  SHAKE_ATTACK            = { degrees(0.6), degrees(60), degrees(0.05) },
  SHAKE_GROUND_POUND      = { degrees(1.4), degrees(70), degrees(0.10) },
  SHAKE_SMALL_DAMAGE      = { degrees(0.8), degrees(66), degrees(0.06) },
  SHAKE_MED_DAMAGE        = { degrees(1.3), degrees(66), degrees(0.09) },
  SHAKE_LARGE_DAMAGE      = { degrees(2.0), degrees(66), degrees(0.13) },
  SHAKE_HIT_FROM_BELOW    = { degrees(1.1), degrees(80), degrees(0.09) },
  SHAKE_FALL_DAMAGE       = { degrees(1.6), degrees(58), degrees(0.11) },
  SHAKE_SHOCK             = { degrees(0.9), degrees(120), degrees(0.08) },
  SHAKE_ENV_EXPLOSION     = { degrees(2.4), degrees(74), degrees(0.14) },
}

-- set_camera_shake_from_point: the same shake, ATTENUATED BY DISTANCE from
-- where it happened. This is the detail almost nobody implements and it is
-- the one that answers "why did the screen shake when that went off on the
-- other side of the map". maxDist is in world pixels.
function MarioCam.shakeFromPoint(preset, x, z, maxDist)
  local p = MarioCam.SHAKES[preset] or MarioCam.SHAKES.SHAKE_ATTACK
  local k = 1
  if x and z then
    local dx, dz = x - geo.px, z - geo.pz
    local d = math.sqrt(dx * dx + dz * dz)
    local far = maxDist or (1600 / U)
    if d >= far then return end
    k = 1 - (d / far)
    k = k * k                     -- inverse-square-ish: near is loud
  end
  local mag = p[1] * k
  if mag <= shake.pitchMag and mag <= shake.yawMag then return end
  shake.pitchMag = math.max(shake.pitchMag, mag)
  shake.pitchVel, shake.pitchDecay = p[2], p[3]
  shake.yawMag = math.max(shake.yawMag, mag * 0.6)
  shake.yawVel, shake.yawDecay = p[2] * 0.8, p[3]
  shake.rollMag = math.max(shake.rollMag, mag * 0.35)
  shake.rollVel, shake.rollDecay = p[2] * 1.2, p[3]
end

function MarioCam.shakeNow(preset)
  MarioCam.shakeFromPoint(preset, nil, nil, nil)
end

local function stepShake(dt)
  local f = dt * 30
  local function axis(mag, phase, vel, decay)
    if mag <= 0 then return 0, 0, 0 end
    phase = s16(phase + vel * f)
    mag = mag - decay * f
    if mag < 0 then mag = 0 end
    return mag, phase, mag * coss(phase)
  end
  local o
  shake.pitchMag, shake.pitchPhase, o =
    axis(shake.pitchMag, shake.pitchPhase, shake.pitchVel, shake.pitchDecay)
  lakitu.shakePitch = o
  shake.yawMag, shake.yawPhase, o =
    axis(shake.yawMag, shake.yawPhase, shake.yawVel, shake.yawDecay)
  lakitu.shakeYaw = o
  shake.rollMag, shake.rollPhase, o =
    axis(shake.rollMag, shake.rollPhase, shake.rollVel, shake.rollDecay)
  lakitu.shakeRoll = o
  shake.fovMag, shake.fovPhase, o =
    axis(shake.fovMag, shake.fovPhase, shake.fovVel, shake.fovDecay)
  lakitu.fovOffset = o * 360 / S16
end

-- ------------------------------------------------------------ the lens --
--
-- struct CameraFOVStatus. The lesson worth porting is the distinction
-- between CAM_FOV_SET_* and CAM_FOV_APP_*: an instant FOV change is a CUT
-- and a gradual one is an EXPRESSION, and the game has both tools and
-- picks between them on purpose. So does this.

MarioCam.FOV_DEFAULT = 45          -- CAM_FOV_SET_45, SM64's own
local fov = { func = "SET_45", goal = 45, k = 0.15 }

MarioCam.fovState = fov            -- probe seam

-- `frames` shapes the approach: close ~90% of the lens gap in that many
-- frames at 30fps, so a shot's transition and its lens move at the same
-- pace and arrive together rather than as two separate events.
function MarioCam.setFov(func, value, frames)
  fov.func = func
  fov.goal = value or MarioCam.FOV_DEFAULT
  local n = tonumber(frames)
  fov.k = (n and n >= 1) and (1 - 0.1 ^ (1 / n)) or 0.15
end

local function stepFov(dt)
  if fov.func == "SET" then
    lakitu.fov = fov.goal
  else
    -- CAM_FOV_APP_*: approach. Slow enough to read as a lens move.
    lakitu.fov = approachF32(lakitu.fov, fov.goal, rate(fov.k, dt))
  end
end

-- -------------------------------------------------------- update_lakitu --
--
-- The chase. Everything above decided where the camera OUGHT to be; this
-- is the only thing that decides where it IS.
local function updateLakitu(dt)
  lakitu.goalPos[1] = cam.pos[1]
  lakitu.goalPos[2] = cam.pos[2]
  lakitu.goalPos[3] = cam.pos[3]
  lakitu.goalFocus[1] = cam.focus[1]
  lakitu.goalFocus[2] = cam.focus[2]
  lakitu.goalFocus[3] = cam.focus[3]

  if not lakitu.smooth then
    -- CAM_FLAG_SMOOTH_MOVEMENT cleared: a CUT. Warps, map changes, the
    -- first frame of the mode. This is the line that stops the camera
    -- flying through a wall on every teleport.
    for i = 1, 3 do
      lakitu.curPos[i] = lakitu.goalPos[i]
      lakitu.curFocus[i] = lakitu.goalFocus[i]
    end
    lakitu.smooth = true
    return
  end

  local fh = rate(lakitu.focHSpeed, dt)
  local fv = rate(lakitu.focVSpeed, dt)
  local ph = rate(lakitu.posHSpeed, dt)
  local pv = rate(lakitu.posVSpeed, dt)

  lakitu.curFocus[1] = approachF32(lakitu.curFocus[1], lakitu.goalFocus[1], fh)
  lakitu.curFocus[3] = approachF32(lakitu.curFocus[3], lakitu.goalFocus[3], fh)
  lakitu.curFocus[2] = approachF32(lakitu.curFocus[2], lakitu.goalFocus[2], fv)

  lakitu.curPos[1] = approachF32(lakitu.curPos[1], lakitu.goalPos[1], ph)
  lakitu.curPos[3] = approachF32(lakitu.curPos[3], lakitu.goalPos[3], ph)
  lakitu.curPos[2] = approachF32(lakitu.curPos[2], lakitu.goalPos[2], pv)
end

-- ------------------------------------------------------------- controls --

-- SM64 plays a sound for every accepted camera input and a BUZZ for every
-- refused one, so the player is never left wondering whether the press
-- registered. Cheap to add and expensive to notice missing -- so the
-- refusal is recorded here and surfaced as a flag the caller can act on
-- (see MarioCam.consumeBuzz), rather than silently dropped.
local function rotate(dir)
  -- an authored shot that has taken the framing refuses the wheel, out
  -- loud -- the buzz the caller surfaces as the Denied voice
  if shotRefusesFraming() then
    ctl.buzz = true
    return false
  end
  local limit = yawLimit()
  -- SM64's first C press swings 60 degrees; a second in the same direction
  -- runs on to the area's limit rather than adding another 60.
  local step = MarioCam.C_STEP
  if ctl.lastCDir == dir and limit then
    ctl.goalOffsetYaw = dir * limit
  else
    ctl.goalOffsetYaw = s16(ctl.goalOffsetYaw + dir * step)
  end
  ctl.lastCDir = dir
  if limit then
    local d = signed(ctl.goalOffsetYaw)
    if d > limit then ctl.goalOffsetYaw = s16(limit) end
    if d < -limit then ctl.goalOffsetYaw = s16(-limit) end
  end
  return true
end

function MarioCam.rotateLeft()  return rotate(-1) end
function MarioCam.rotateRight() return rotate(1) end

-- C-down / C-up: three zoom rungs. Wraps, so one key walks the ladder.
function MarioCam.cycleZoom()
  if shotRefusesFraming() then
    ctl.buzz = true
    return nil
  end
  ctl.zoom = ctl.zoom % #MarioCam.ZOOMS + 1
  return MarioCam.ZOOMS[ctl.zoom]
end

-- The R button.
function MarioCam.toggleAlt()
  ctl.alt = not ctl.alt
  if not ctl.alt then ctl.lastCDir = 0 end
  return ctl.alt
end

function MarioCam.recenter()
  ctl.goalOffsetYaw, ctl.lastCDir = 0, 0
end

-- Kept, and currently never raised: with the ladder down to ON/OFF there
-- is no rung that refuses a turn. The mechanism stays because the sound
-- feedback it drives is the cheap half of the source document's point
-- about never leaving a press unanswered, and an authored shot that
-- declines to be spun is the obvious next thing to raise it.
function MarioCam.consumeBuzz()
  local b = ctl.buzz
  ctl.buzz = false
  return b
end

-- The right stick, folded into the same offset the keys move, so the two
-- ways of asking for a yaw cannot disagree about what the answer is.
local function stickYaw(dt)
  local x = rightStick()
  if x == 0 then return end
  -- the stick has no buzz to give, so inside a framing shot it is simply
  -- inert -- same refusal as the keys, minus the voice it cannot carry
  if shotRefusesFraming() then return end
  local limit = yawLimit()
  -- 120 degrees a second at full deflection: fast enough to be useful,
  -- slow enough that a flick does not lose the player
  ctl.goalOffsetYaw = s16(ctl.goalOffsetYaw + x * degrees(120) * dt)
  if limit then
    local d = signed(ctl.goalOffsetYaw)
    if d > limit then ctl.goalOffsetYaw = s16(limit) end
    if d < -limit then ctl.goalOffsetYaw = s16(-limit) end
  end
  ctl.lastCDir = 0
end

-- ---------------------------------------------------------- update_camera --
--
-- The per-frame order, and it is the decomp's order because the order is
-- load-bearing: the geometry has to be read before the triggers can test
-- it, the triggers have to run before the mode does, the mode has to write
-- a target before anything can collide it, and the chase has to be last
-- because it is the only step that produces the answer.
function MarioCam.update(dt, vh)
  dt = tonumber(dt) or 0
  if dt <= 0 then return end
  if not MarioCam.enabled() then
    -- Leaving the mode is a cut back to whatever the orbit is doing, so
    -- the next frame that turns it on does not ease in from a stale pose.
    lakitu.smooth = false
    return
  end
  vh = tonumber(vh) or 144

  -- 1. the player and the ground under them
  if not findPlayerFloor() then return end
  -- 2. what the world says about the camera
  courseProcessing()
  -- 3. the player's own inputs
  stickYaw(dt)
  ctl.offsetYaw = approachS16(ctl.offsetYaw, ctl.goalOffsetYaw, rateDiv(6, dt))
  -- 4. the mode: writes cam.pos and cam.focus, and nothing else does
  local fn = modes[cam.mode] or modes.radial
  fn(dt, vh)
  -- 5. occlusion, by ROTATING rather than by pulling in -- and the
  -- rotation ACCUMULATES (see the avoid table): the mode's yaw is fresh
  -- every frame, so the deflection has to carry its own history or it
  -- never gets anywhere.
  -- ...except in FIXED: an authored shot was placed by someone who could
  -- see the map, and a steering that swung it would be the algorithm
  -- overruling the author -- backwards from the whole point of section 10.
  local modeYaw = cam.yaw
  local boxedIn = false
  if cam.mode ~= "fixed" then
    local tryYaw = s16(modeYaw + avoid.offset)
    local av = avoidYaw(geo.map, cam.focus, cam.dist, cam.pitch,
                        tryYaw, modeYaw, signed(avoid.offset))
    -- ------- THE ENGAGE DELAY: passing occlusions move nothing
    --
    -- Walking past a house corner hides the player for a couple of cells,
    -- and a steering that answered the FIRST blocked frame swung the
    -- camera for every one of them -- and swung it back after -- which
    -- from the player's chair is the camera "changing out of nowhere".
    -- So the block has to STAND for a quarter second before any steering
    -- or pull-in answers it; a block that resolves itself by walking was
    -- never the camera's problem.
    if av ~= nil then
      avoid.blocked = (avoid.blocked or 0) + dt
    else
      avoid.blocked = 0
    end
    local engaged = (avoid.blocked or 0) >= MarioCam.WALL_DELAY
    if av == false and engaged then
      -- boxed in: hold the deflection where it is and let resolveGeometry
      -- pull the eye in, which is the one thing that always works
      boxedIn = true
    elseif av and engaged then
      -- a clear bearing exists: grow the deflection toward it. The goal is
      -- measured from where the MODE wanted to stand rather than from due
      -- south: on RADIAL the orbit has already used up its own allowance
      -- and the steering is a further nudge on top of it, so clamping both
      -- against the same origin would silently forbid the steering
      -- wherever the orbit happened to be at its limit. It is within the
      -- sweep's own arc by construction; the limit seam still gets a say.
      local goal = signed(av - modeYaw)
      local cap = avoidLimit()
      if cap then
        if goal > cap then goal = cap end
        if goal < -cap then goal = -cap end
      end
      avoid.offset = signed(approachS16(s16(avoid.offset), s16(goal),
                                        rateDiv(MarioCam.WALL_DIV, dt)))
    elseif av == nil and avoid.offset ~= 0 then
      -- the deflected view is clear. Ease home -- but only if home is
      -- clear too, because relaxing back INTO the wall that caused the
      -- deflection is a camera that saws against a corner forever.
      if eyeClear(geo.map, cam.focus, cam.dist, cam.pitch, modeYaw) then
        avoid.offset = signed(approachS16(s16(avoid.offset), 0,
                                          rateDiv(MarioCam.WALL_RELAX, dt)))
        if math.abs(avoid.offset) < degrees(1) then avoid.offset = 0 end
      end
    end
    if avoid.offset ~= 0 then
      cam.yaw = s16(modeYaw + avoid.offset)
      focusOnPlayer(cam.focus, cam.pos, 0, 0, cam.dist, cam.pitch, cam.yaw)
    end
  end
  resolveGeometry(geo.map, cam.focus, cam.pos, boxedIn)
  -- 6. the mode transition, if one is running
  transitionNextState(dt)
  -- 7. the chase
  updateLakitu(dt)
  -- 8. the shake and the lens, on top of the finished result
  stepShake(dt)
  stepFov(dt)
end

-- ---------------------------------------------------------------- output --
--
-- The camera Voxel3D takes, in the shape it already accepts from BattleCam
-- -- so nothing downstream of this file changes at all. The shader
-- uniforms, project(), horizonY, the sky and the overlay all read
-- Voxel3D.vp and Voxel3D.eye, and those are set the same way either way.
--
-- The shake lands HERE, as an angular offset on the finished pose rather
-- than as a change to it: the focus is swung around the eye by the two
-- shake angles, which tilts the frame without moving the camera and
-- leaves nothing behind when the shake ends.
-- ------- the air (data/atmosphere.lua)
--
-- A placed camera declines the hourly haze wholesale (Voxel3D's own rule,
-- written for staged battle framings) -- which left the SM64 camera with
-- no air at all. This is the way back in: a map that wants its own air
-- names it in the data file, and the entry rides the camera into the same
-- shader uniforms. OUTDOOR ONLY -- an interior never inherits the town's
-- weather -- and absent everywhere the data file is silent, which is the
-- no-fog state the placed contract already had.
local atmoData
local function atmoFor()
  if geo.indoors then return nil end
  if atmoData == nil then
    local ok, t = pcall(V.data, "atmosphere")
    atmoData = (ok and type(t) == "table") and t or false
  end
  if not atmoData then return nil end
  local def = geo.map and geo.map.def
  if not def then return nil end
  local a = atmoData[def.id] or atmoData[def.name]
  if not a then return nil end
  if not a._built then
    a._built = {
      color = a.color or { 0.6, 0.6, 0.7 },
      near = a.near or 90,
      inv = 1 / math.max(1, a.span or 260),
      strength = a.strength or 0.5,
    }
  end
  return a._built
end

function MarioCam.camera()
  if not MarioCam.enabled() then return nil end
  local eye = { lakitu.curPos[1], lakitu.curPos[2], lakitu.curPos[3] }
  local focus = { lakitu.curFocus[1], lakitu.curFocus[2], lakitu.curFocus[3] }

  if lakitu.shakePitch ~= 0 or lakitu.shakeYaw ~= 0 then
    local dx = focus[1] - eye[1]
    local dy = focus[2] - eye[2]
    local dz = focus[3] - eye[3]
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist > 1 then
      local flat = math.sqrt(dx * dx + dz * dz)
      local pitch = s16(atan2s(dy, flat) + lakitu.shakePitch)
      local yaw = s16(atan2s(dx, dz) + lakitu.shakeYaw)
      local f = dist * coss(pitch)
      focus[1] = eye[1] + f * sins(yaw)
      focus[2] = eye[2] + dist * sins(pitch)
      focus[3] = eye[3] + f * coss(yaw)
    end
  end

  return {
    eye = eye,
    focus = focus,
    fov = math.rad(lakitu.fov + lakitu.fovOffset),
    -- the world curve is the mod's own horizon bend and it belongs to the
    -- free-roam look; a placed camera may decline it (BattleCam does, with
    -- this same field). An authored shot declines it with `flat = true`:
    -- indoors the bend turns a room into the deck of a planet, and every
    -- interior shot is entered through a map change -- a cut -- so the
    -- flat/curved seam never plays on screen. The generic camera keeps
    -- the bend: it is the world the player chose.
    curve = (cam.shot and cam.shot.flat) and 0 or nil,
    atmo = atmoFor(),
  }
end

-- Force the next frame to CUT rather than chase. The engine's own reasons
-- for wanting this are warps, map loads and the end of a staged battle,
-- and every one of them is a frame where the operator must not be seen to
-- travel.
function MarioCam.cut()
  lakitu.smooth = false
  anchor.x, anchor.z = nil, nil
  avoid.offset = 0
  avoid.blocked = 0
  follow.heading, follow.facing = nil, nil
  follow.commit, follow.lull = 0, 0
end

-- The yaw the world is being seen from, in radians, for anything that has
-- to agree with the camera about which way is which -- the culling box
-- (VoxelScene.bounds) and the shadow frustum both do. Zero is due south,
-- which is where the free-roam orbit stands, so a caller that gets zero
-- gets the behaviour it had before this file existed.
function MarioCam.viewYaw()
  if not MarioCam.enabled() then return 0 end
  local dx = lakitu.curFocus[1] - lakitu.curPos[1]
  local dz = lakitu.curFocus[3] - lakitu.curPos[3]
  if (dx * dx + dz * dz) < 1 then return 0 end
  -- the direction the camera LOOKS, measured from due north (-Z), which is
  -- the direction the pre-existing culling box was built around
  return math.atan2(dx, -dz)
end

-- Where the camera is looking, for the passes that were centring their
-- work on the engine's 2D scroll instead. Nil when the mode is off.
function MarioCam.focusXZ()
  if not MarioCam.enabled() then return nil end
  return lakitu.curFocus[1], lakitu.curFocus[3]
end

-- This camera's pitch expressed the way the ORBIT expresses one -- as an
-- angle from straight down, which is what Voxel.angle is and what
-- ShadowMap.groundReach does its trigonometry in.
--
-- It is not always the ladder's own angle: the water mode drops ten
-- degrees below it (a camera looking ALONG the water rather than down at
-- it), and a lower camera sees FURTHER. Handing groundReach the ladder
-- value there would underestimate the reach and cull ground that is
-- plainly on screen -- which is a hole in the world, the one failure the
-- culling box is written to be generous about.
function MarioCam.orbitAngle()
  if not MarioCam.enabled() then return nil end
  local dx = lakitu.curFocus[1] - lakitu.curPos[1]
  local dy = lakitu.curFocus[2] - lakitu.curPos[2]
  local dz = lakitu.curFocus[3] - lakitu.curPos[3]
  local flat = math.sqrt(dx * dx + dz * dz)
  if flat < 1e-6 then return 0 end
  -- the angle between the view ray and straight down
  return math.pi / 2 - math.atan2(-dy, flat)
end

-- ------------------------------------------------ the world, in quadrants --
--
-- SM64 makes the stick camera-relative in one line:
--
--     m->intendedYaw = atan2s(-stickY, stickX) + m->area->camera->yaw;
--
-- Push away from yourself and Mario runs away from you, whatever the
-- camera is doing. It is not a convenience -- it is the reason an orbiting
-- camera is playable at all, and the header of this file used to explain
-- at length why this port would NOT do it. That was the wrong call and
-- this is the correction.
--
-- What makes it different here is that this world has FOUR directions, not
-- an analog circle. A Pokemon character walks on a grid, and every system
-- under them -- collision, ledges, warps, scripts, the sprite sheet -- is
-- written in world compass directions. So the rotation cannot be
-- continuous. It quantises to a QUARTER TURN, and everything below is that
-- quarter turn: which of the four world directions currently reads as
-- "away from the camera".
--
-- Clockwise from north, matching the compass and matching the order the
-- overworld's own movement loop walks.
local DIRS = { "up", "right", "down", "left" }
local DIR_INDEX = { up = 0, right = 1, down = 2, left = 3 }

MarioCam.DIRS = DIRS
MarioCam.DIR_INDEX = DIR_INDEX

-- Hysteresis on the quadrant boundary, in degrees past the midpoint.
--
-- Without it the mapping flips every frame while the camera hovers near 45
-- degrees, and a flip means the button under the player's thumb silently
-- becomes a different direction -- so a player walking a diagonal path
-- would have the controls swap back and forth under them, which is far
-- worse than either mapping. 8 degrees of overlap costs nothing and makes
-- the boundary a place you cross rather than a place you sit on.
MarioCam.QUADRANT_HYST = 8

local quad = 0

-- ------- THE MAPPING NEVER CHANGES UNDER THE PLAYER'S THUMB.
--
-- The hysteresis stops the boundary flickering; it does not stop the
-- boundary being CROSSED, and the radial orbit crosses it on its own --
-- walk east along a route and the automatic yaw swings until, mid-stride,
-- the held button silently becomes a different world direction. "I was
-- going right and right turned into up" is that exact frame, and no width
-- of hysteresis fixes it, because the problem is not noise at the
-- boundary, it is a remap while the button is DOWN.
--
-- SM64 does not have the problem to solve: the stick is an angle, so a
-- turning camera bends the walk gradually. A D-pad is four discrete
-- meanings, so the only correct time to change what a button means is
-- while no button is held and no step is in flight. The quadrant LATCHES
-- during both, and re-reads the camera the moment the player lets go --
-- which is also the moment they can see what the buttons now mean.
--
-- main.lua supplies the "is a direction physically held" answer, because
-- only it holds the unwrapped Input (asking the wrapped one would recurse
-- straight back through buttonFor).
local steering = function() return false end

function MarioCam.setSteeringProbe(fn)
  steering = fn or function() return false end
end

-- Which quarter turn the world is under, 0..3. Zero means "no rotation",
-- which is what the free-roam orbit answers with the row off, so
-- every caller below is an identity for them.
function MarioCam.quadrant()
  if not MarioCam.enabled() then return 0 end
  if geo.moving then return quad end
  local okS, held = pcall(steering)
  if okS and held then return quad end
  local deg = math.deg(MarioCam.viewYaw())
  -- distance, in degrees, from the quadrant currently held
  local away = ((deg - quad * 90 + 180) % 360) - 180
  if math.abs(away) > 45 + MarioCam.QUADRANT_HYST then
    quad = math.floor((deg % 360) / 90 + 0.5) % 4
  end
  return quad
end

-- ------- WHICH BUTTON THE GAME SHOULD BE ASKING ABOUT
--
-- The overworld's movement loop asks "is UP held?" when it is considering
-- moving the player north. With the world under a quarter turn, the answer
-- it wants is whether the button that currently MEANS north is held -- and
-- that is the physical button a quarter turn the other way.
--
-- Note the inverse: pressing physical up moves the player along
-- (p + k), so a query about world direction w has to look at (w - k).
-- Getting that backwards produces controls that are wrong by a half turn
-- at 180 degrees and feel almost right everywhere else, which is the worst
-- possible failure because it survives casual testing.
function MarioCam.buttonFor(worldDir)
  local w = DIR_INDEX[worldDir]
  if not w then return worldDir end
  local k = MarioCam.quadrant()
  if k == 0 then return worldDir end
  return DIRS[(w - k) % 4 + 1]
end

-- ------- AND WHICH WAY A CHARACTER IS FACING, AS THE CAMERA SEES IT
--
-- The other half of the same rotation, and the fix for the walk that reads
-- as a moonwalk.
--
-- A sprite sheet here holds three drawings -- front, back, and a profile
-- that mirrors for the other side -- indexed by the character's compass
-- facing. That is exactly right for a camera that cannot move: north is
-- always away from you, so the north drawing is always the back.
--
-- Turn the camera and it is nonsense. Stand north of someone walking north
-- and the game hands you their BACK while they walk toward you: they
-- advance across the screen while facing the other way, which is a
-- moonwalk, and it is the single most-noticed artefact of the orbit.
--
-- So the frame is chosen by the facing RELATIVE TO THE CAMERA. The
-- character still walks north in the world -- collision, ledges, warps and
-- scripts are untouched and still speak compass -- but the drawing picked
-- for them is the one that shows what a viewer standing where the camera
-- stands would actually see.
function MarioCam.relativeFacing(worldFacing)
  local w = DIR_INDEX[worldFacing]
  if not w then return worldFacing end
  local k = MarioCam.quadrant()
  if k == 0 then return worldFacing end
  return DIRS[(w - k) % 4 + 1]
end

-- ------- THE PRESENTATION YAW: the card shows its best side
--
-- A drawing has one angle it was made for -- the cardinal the latched
-- quadrant picked it by. When the camera sits between two cardinals, the
-- billboard used to face it dead-on anyway, flashing art made for 0
-- degrees at a 45-degree eye. The fighting-game trick (the user named
-- Sparking Zero and FighterZ) is that the character never quite faces the
-- lens: it UNDER-ROTATES toward the angle its look was built for, so the
-- lens always catches it slightly turned -- the flattering three-quarter.
--
-- Here that is one number: pull the card back toward the shown drawing's
-- cardinal by 40% of the camera's divergence from it, capped at 18
-- degrees. Continuous, so there is no octant boundary to pop at; zero at
-- every cardinal, so the mode everyone plays is untouched; and read
-- THROUGH MarioCam.quadrant() -- the same latch-gated accessor the frame
-- chooser uses -- so the turn always agrees with the drawing on screen.
-- (A first cut read the raw latched variable and disagreed with the art
-- by a whole stale quadrant; the unit probe caught it at the cap.)
MarioCam.PRESENT_FRACTION = 0.4
MarioCam.PRESENT_CAP = 18                -- degrees

function MarioCam.presentYaw()
  if not MarioCam.enabled() then return 0 end
  local deg = math.deg(MarioCam.viewYaw())
  local off = ((deg - MarioCam.quadrant() * 90 + 180) % 360) - 180
  local a = -off * MarioCam.PRESENT_FRACTION
  local cap = MarioCam.PRESENT_CAP
  if a > cap then a = cap elseif a < -cap then a = -cap end
  return math.rad(a)
end

-- Camera-relative movement is a REAL GAMEPLAY CHANGE and the only thing in
-- this mod that is, so it says so out loud rather than hiding inside
-- enabled(). It rides the rung that can turn the camera, because those are
-- the same question: a camera that turns without this is a camera you
-- cannot walk under.
function MarioCam.rotatesInput()
  return MarioCam.enabled()
end

-- The other two things ShadowMap.groundReach has to know about a camera
-- that is not the orbit: HALF ITS LENS and HOW FAR BACK IT STANDS.
--
-- Both are needed because both differ from the orbit's: this camera stands
-- at its own distance and shoots SM64's 45-degree lens rather than the
-- orbit's 53. Which way that cuts is worth stating, because the guess is
-- backwards -- a WIDER lens sees FURTHER, since the frustum's top ray sits
-- half the FOV above the view direction and opening it tips that ray
-- toward horizontal. So this camera's own reach comes out SHORTER, and the
-- callers take the larger of the two rather than trusting it (see the note
-- in VoxelScene.bounds).
function MarioCam.lens()
  if not MarioCam.enabled() then return nil, nil end
  local dx = lakitu.curFocus[1] - lakitu.curPos[1]
  local dy = lakitu.curFocus[2] - lakitu.curPos[2]
  local dz = lakitu.curFocus[3] - lakitu.curPos[3]
  local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
  return math.rad(lakitu.fov + lakitu.fovOffset) / 2, math.max(1, dist)
end

return MarioCam
