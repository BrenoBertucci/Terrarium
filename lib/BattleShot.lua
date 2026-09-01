-- Overworld battles: the attack camera.
--
-- BattleCam answers "where should the camera be for this arena, this
-- instant" -- pure geometry, no history. This module is the OTHER half of
-- that sentence, the half SM64's camera taught everyone to separate: a
-- pursuer with inertia that chases whatever the geometry asks for, and a
-- director that asks for something different while a move is being thrown.
-- Mixing the two layers is what produces cameras stuck in feedback loops;
-- they are kept apart here on purpose (see camera-super-mario-64.md, the
-- doc this module's constants are lifted from).
--
-- The director watches three engine seams, all read-only:
--
--     battle.animPlaying / animAttackerIsPlayer   a move is being thrown,
--                                                 and by whom
--     battle.fx.flash / fx.shake                  the hit landed
--     battler.shownHP > battler.mon.hp            the bar is draining
--                                                 (the hit landed with
--                                                 animations switched off)
--
-- While a move plays, the goal swings around the arena's vertical axis
-- toward the attacker's end, stoops lower, punches the eye in and pulls the
-- aim toward the DEFENDER -- the impact is where the eye wants to be. When
-- the hit lands, a damped-cosine shake is added AFTER the smoothing, as an
-- angular offset on the finished frame: when it decays everything is back
-- exactly where it was, with no drift to clean up. When the move ends the
-- goal simply becomes the base rig again and the pursuer walks home, a
-- little slower than it left.
--
-- The pursuit is asymmetric, and the asymmetry is the feel: the focus
-- closes 80% of its horizontal error per 30fps frame while the eye closes
-- 30%, so the camera LOOKS at the action almost four times faster than it
-- travels there -- the mons never leave frame even when the framing is
-- still arriving. Vertical focus is 0.3 like the eye: a jolt in aim height
-- must not bounce the horizon. The eye is pursued in SPHERICAL coordinates
-- about the focus (distance, yaw, elevation), not in XYZ: interpolating
-- cartesian eye positions cuts the corner through the arena, spherical
-- interpolation arcs around it, which is what a camera operator would do.
--
-- The pins survive all of it for the same reason they survive the drift:
-- the mons are re-projected every frame (BattleScene.toGB), so wherever
-- this camera puts the frame, the pics follow. The swing and punch are
-- sized so both mons stay comfortably in front of the lens; toGB failing
-- (a mon BEHIND the camera) would retire the shot for the frame, so the
-- envelope below is deliberately conservative.
--
-- Purely presentational, like everything else in this mod: nothing here
-- reaches damage, timing or scripts, and a battle with the module confused
-- is a battle shot from the ordinary rig.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local BattleShot = {}

-- ------- the pursuit, per 30fps frame (SM64's own numbers)
--
-- Converted to real dt below with  k' = 1 - (1-k)^(dt*30)  -- the correct
-- frame-rate conversion for an exponential approach; dividing by two is not.
BattleShot.FOC_H = 0.8   -- focus, horizontal: the fast one
BattleShot.FOC_V = 0.3   -- focus, vertical: a jolt must not bounce the frame
BattleShot.EYE_K = 0.3   -- eye distance / yaw / elevation
BattleShot.FOV_K = 0.3

-- ------- the attack shot's envelope
--
-- Sized against the tele rig's long lens: nine degrees of orbit moves a mon
-- about half a cell laterally on screen, which crowds the frame toward the
-- action without pushing either pic out of it.
BattleShot.SWING = math.rad(9)   -- orbit toward the attacker's end
BattleShot.PUNCH = 0.85          -- eye-to-focus distance factor
BattleShot.STOOP = 0.86          -- eye height factor: lower stance, more drama
BattleShot.FOCUS_PULL = 0.30     -- aim, toward the defender's cell
BattleShot.RECOVER_K = 0.55      -- pursuit scale on the way home: leaving is
                                 -- urgent, returning is contemplative
BattleShot.HOLD = 0.30           -- seconds the shot lingers after the anim,
                                 -- which is when the bar is draining

-- ------- the shake: a damped cosine per axis, applied POST-smoothing
--
-- Two frequencies that share no period, so the jolt reads as organic rather
-- than as a spring. Decay is per 30fps frame, converted like the pursuit.
BattleShot.HIT_AMP = math.rad(0.7)    -- a landed hit
BattleShot.QUAKE_AMP = math.rad(1.5)  -- fx.shake moves (EARTHQUAKE and kin)
BattleShot.DRAIN_AMP = math.rad(0.45) -- bar starts draining, anims off
BattleShot.SHAKE_KEEP = 0.78          -- amplitude kept per 30fps frame
BattleShot.YAW_HZ = 11
BattleShot.ELEV_HZ = 8.3
BattleShot.FOV_PUNCH = 0.05           -- lens kicked briefly wider on impact
BattleShot.FOV_KEEP = 0.80

-- One flag, so a probe (or a future settings row) can hold the base rig.
BattleShot.enabled = true

-- ------- state
--
-- `cur = nil` means "cut": the first frame after a reset snaps to the goal
-- instead of flying there -- SM64's smooth-movement flag, off for exactly
-- one frame. A battle must open on its composed shot, not on a camera
-- arriving from wherever the last fight left it.
local S = {
  cur = nil,           -- { focus = {x,y,z}, dist, yaw, elev, fov }
  mode = "idle",       -- idle | attack | hold | recover
  attackerIsPlayer = false,
  holdT = 0,
  dt = 0,
  shk = { ampY = 0, phY = 0, ampE = 0, phE = 0 },
  fovPunch = 0,
  prev = {},           -- last frame's engine reads, for edge detection
  last = nil,          -- the numbers a probe measures (see frame)
}

function BattleShot.reset()
  S.cur = nil
  S.mode = "idle"
  S.attackerIsPlayer = false
  S.holdT = 0
  S.dt = 0
  S.shk.ampY, S.shk.phY, S.shk.ampE, S.shk.phE = 0, 0, 0, 0
  S.fovPunch = 0
  S.prev = {}
  S.last = nil
end

-- The measured truth of the last frame, for probes: mode, how far the shot
-- is from the base rig, and what the shake is doing. Numbers, not opinions.
function BattleShot.debug()
  return S.last
end

-- ------- edge detection against the engine
--
-- Every read is guarded: a battle object from another generation (Gold's
-- gen2 screen) simply answers nil to all of it and the camera stays on the
-- base rig. That is the correct degradation, not an error.
local function draining(b)
  if not (b and b.mon and b.shownHP) then return false end
  return b.shownHP > b.mon.hp
end

local function kick(amp)
  -- cos starts at its peak, so the impact is an instant jolt outward, not a
  -- wind-up; a second hit inside the first one's decay keeps the larger
  S.shk.ampY = math.max(S.shk.ampY, amp)
  S.shk.ampE = math.max(S.shk.ampE, amp * 0.6)
  S.shk.phY, S.shk.phE = 0, 0
  S.fovPunch = math.max(S.fovPunch, BattleShot.FOV_PUNCH)
end

-- Called once per update from OverworldBattle, WITH the battle and the real
-- frame dt -- real, because a fast-forwarded battle must not spin the
-- camera any more than it spins BattleCam's drift.
function BattleShot.observe(battle, dt)
  S.dt = dt or 0
  if not BattleShot.enabled then return end
  local prev = S.prev
  if not battle then
    S.mode = "idle"
    S.prev = {}
    return
  end

  local playing = battle.animPlaying and true or false
  local fx = battle.fx
  local flash = (fx and (fx.flash or 0) > 0) and true or false
  local quake = (fx and (fx.shake or 0) > 0) and true or false
  local drain = draining(battle.player) or draining(battle.enemy)

  -- a move starts: swing toward whoever is throwing it
  if playing and not prev.playing then
    S.mode = "attack"
    S.attackerIsPlayer = battle.animAttackerIsPlayer and true or false
    S.holdT = 0
  end
  -- ...and ends: linger through the aftermath, then walk home
  if not playing and prev.playing and S.mode == "attack" then
    S.mode = "hold"
    S.holdT = 0
  end
  if S.mode == "hold" then
    S.holdT = S.holdT + S.dt
    if S.holdT >= BattleShot.HOLD then S.mode = "recover" end
  end

  -- the hit landing, in any mode: the flash and the screen-shake counter
  -- fire with animations on OR off (BattleState sets them either way), and
  -- the bar starting to drain is the landed hit's one guaranteed symptom
  if flash and not prev.flash then kick(BattleShot.HIT_AMP) end
  if quake and not prev.quake then kick(BattleShot.QUAKE_AMP) end
  if drain and not prev.drain and not (flash or quake) then
    kick(BattleShot.DRAIN_AMP)
  end

  prev.playing, prev.flash, prev.quake, prev.drain =
    playing, flash, quake, drain
end

-- ------- geometry helpers

local function wrapAngle(a)
  while a > math.pi do a = a - 2 * math.pi end
  while a < -math.pi do a = a + 2 * math.pi end
  return a
end

-- eye relative to focus, as (dist, yaw, elevation)
local function toSpherical(eye, focus)
  local rx = eye[1] - focus[1]
  local ry = eye[2] - focus[2]
  local rz = eye[3] - focus[3]
  local dist = math.max(1e-3, math.sqrt(rx * rx + ry * ry + rz * rz))
  return dist, math.atan2(rz, rx), math.asin(math.max(-1, math.min(1, ry / dist)))
end

local function fromSpherical(focus, dist, yaw, elev)
  local h = dist * math.cos(elev)
  return { focus[1] + h * math.cos(yaw),
           focus[2] + dist * math.sin(elev),
           focus[3] + h * math.sin(yaw) }
end

-- ------- the goal: what the director asks for this frame
--
-- `cam` is BattleCam.rig's answer, drift included -- the drift stays part of
-- the goal, so the shot keeps breathing under everything this module adds.
local function attackGoal(cam, arena, groundY)
  local mx, mz = arena.mid[1], arena.mid[2]
  local att = S.attackerIsPlayer and arena.player or arena.enemy
  local def = S.attackerIsPlayer and arena.enemy or arena.player

  -- swing about the arena's vertical axis, in the direction that carries
  -- the eye toward the ATTACKER's end. Computed from the cells rather than
  -- assumed from the compass, so an arena of any orientation gets the same
  -- shot.
  local ox = cam.eye[1] - mx
  local oz = cam.eye[3] - mz
  local toward = wrapAngle(math.atan2(att[2] - mz, att[1] - mx)
                           - math.atan2(oz, ox))
  local swing = (toward < 0) and -BattleShot.SWING or BattleShot.SWING
  local c, s = math.cos(swing), math.sin(swing)

  local focus = {
    -- the aim leans toward the defender: the impact is the subject
    cam.focus[1] + (def[1] - mx) * BattleShot.FOCUS_PULL,
    cam.focus[2],
    cam.focus[3] + (def[2] - mz) * BattleShot.FOCUS_PULL,
  }
  local eye = {
    mx + ox * c - oz * s,
    -- stoop measured from the arena floor, so a fight on a ledge stoops
    -- over THAT floor rather than toward sea level
    groundY + (cam.eye[2] - groundY) * BattleShot.STOOP,
    mz + ox * s + oz * c,
  }
  -- the punch is the last word: pull the eye in along its own line to the
  -- new aim, so the stoop and the swing keep their proportions
  for i = 1, 3 do
    eye[i] = focus[i] + (eye[i] - focus[i]) * BattleShot.PUNCH
  end
  return { eye = eye, focus = focus, fov = cam.fov }
end

-- ------- per frame: pursue the goal, add the shake, hand the camera back
--
-- Slotted between BattleCam.rig and the render (see BattleScene). Returns
-- the same shape rig() does -- a camera record and the pitch-from-vertical
-- the grass pull and the sun frustum read.
function BattleShot.frame(cam, pitch, arena, groundY)
  if not (BattleShot.enabled and cam and arena) then return cam, pitch end
  local dt = S.dt or 0
  S.dt = 0 -- consumed: a second render this update holds still

  -- layer one: the geometry asked for this frame
  local goal = cam
  if S.mode == "attack" or S.mode == "hold" then
    goal = attackGoal(cam, arena, groundY or 0)
  end
  local gd, gyaw, gelev = toSpherical(goal.eye, goal.focus)

  -- the cut: first frame after reset opens ON the shot
  if not S.cur then
    S.cur = { focus = { goal.focus[1], goal.focus[2], goal.focus[3] },
              dist = gd, yaw = gyaw, elev = gelev, fov = goal.fov }
  end
  local cur = S.cur

  -- layer two: the pursuit. approach() is SM64's asymptotic lerp with the
  -- per-frame coefficient converted to this dt.
  local scale = (S.mode == "recover") and BattleShot.RECOVER_K or 1
  local function approach(k)
    return 1 - (1 - math.min(1, k * scale)) ^ (dt * 30)
  end
  cur.focus[1] = cur.focus[1] + (goal.focus[1] - cur.focus[1])
                                * approach(BattleShot.FOC_H)
  cur.focus[3] = cur.focus[3] + (goal.focus[3] - cur.focus[3])
                                * approach(BattleShot.FOC_H)
  cur.focus[2] = cur.focus[2] + (goal.focus[2] - cur.focus[2])
                                * approach(BattleShot.FOC_V)
  local ke = approach(BattleShot.EYE_K)
  cur.dist = cur.dist + (gd - cur.dist) * ke
  cur.yaw = cur.yaw + wrapAngle(gyaw - cur.yaw) * ke
  cur.elev = cur.elev + (gelev - cur.elev) * ke
  cur.fov = cur.fov + (goal.fov - cur.fov) * approach(BattleShot.FOV_K)

  -- home again: close enough to the base rig reads as arrived
  if S.mode == "recover"
     and math.abs(wrapAngle(cur.yaw - gyaw)) < math.rad(0.3)
     and math.abs(cur.dist - gd) < 0.5 then
    S.mode = "idle"
  end

  -- layer three: the shake, an angular offset on the FINISHED frame. The
  -- stored state above never sees it, so when the amplitude dies the camera
  -- is exactly where the pursuit put it -- no drift to walk off.
  local shk = S.shk
  local shYaw, shElev = 0, 0
  if shk.ampY > 1e-4 then
    shYaw = shk.ampY * math.cos(shk.phY)
    shElev = shk.ampE * math.cos(shk.phE)
    shk.phY = shk.phY + 2 * math.pi * BattleShot.YAW_HZ * dt
    shk.phE = shk.phE + 2 * math.pi * BattleShot.ELEV_HZ * dt
    local keep = BattleShot.SHAKE_KEEP ^ (dt * 30)
    shk.ampY, shk.ampE = shk.ampY * keep, shk.ampE * keep
    if shk.ampY <= 1e-4 then shk.ampY, shk.ampE = 0, 0 end
  end
  local fov = cur.fov * (1 + S.fovPunch)
  if S.fovPunch > 0 then
    S.fovPunch = S.fovPunch * (BattleShot.FOV_KEEP ^ (dt * 30))
    if S.fovPunch < 1e-4 then S.fovPunch = 0 end
  end

  local eye = fromSpherical(cur.focus, cur.dist,
                            cur.yaw + shYaw, cur.elev + shElev)
  local out = { eye = eye,
                focus = { cur.focus[1], cur.focus[2], cur.focus[3] },
                fov = fov,
                -- no world curve on a staged shot, same as the base rig
                curve = 0 }

  local ex = eye[1] - out.focus[1]
  local ey = eye[2] - out.focus[2]
  local ez = eye[3] - out.focus[3]
  local horiz = math.sqrt(ex * ex + ez * ez)
  local outPitch = math.atan2(horiz, math.max(1e-3, ey))

  -- what a probe measures: distance from the BASE rig, not from the goal,
  -- because "the camera moved for the attack and came back" is the claim
  local bd, byaw = toSpherical(cam.eye, cam.focus)
  S.last = { mode = S.mode,
             attacker = S.attackerIsPlayer,
             dYaw = wrapAngle(cur.yaw - byaw),
             dDist = cur.dist - bd,
             shake = shk.ampY,
             fovPunch = S.fovPunch }

  return out, outPitch
end

return BattleShot
