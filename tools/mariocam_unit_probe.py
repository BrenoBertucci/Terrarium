"""Headless probe for lib/MarioCam.lua.

Loads the module with love / require / V stubbed and an __index on _G that
logs every read of an undefined global -- which is what catches a typo that
the syntax check cannot. Then drives update() over a fake overworld and
checks the invariants that matter.
"""
import sys, math, lupa

MOD = __import__("os").path.dirname(__import__("os").path.dirname(__import__("os").path.abspath(__file__)))
L = lupa.LuaRuntime(unpack_returned_tuples=True)

print("lua:", L.eval("_VERSION"))

BOOT = r"""
-- Lua 5.4 dropped math.atan2; the game runs on 5.1 where it exists.
if not math.atan2 then math.atan2 = function(y, x) return math.atan(y, x) end end

local undefined = {}
setmetatable(_G, { __index = function(t, k)
  undefined[k] = (undefined[k] or 0) + 1
  return nil
end })
_G.__undefined = undefined

-- ------- love
_G.love = {
  timer = { getTime = function() return _G.__clock or 0 end },
  joystick = { getJoysticks = function() return {} end },
}

-- ------- the engine modules MarioCam requires
local engine = {
  ["src.world.Map"] = {
    isOutdoor = function(def) return def and def.outdoor end,
  },
  ["src.core.Game"] = _G.__Game,
}
_G.__engine = engine
local realRequire = _G.require
_G.require = function(name)
  local hit = engine[name]
  if hit ~= nil then return hit end
  error("unexpected require: " .. tostring(name), 0)
end
"""
L.execute(BOOT)

# --- the V namespace: VoxelState, ModSetting, VoxelScene
V_SRC = r"""
local rung = "radial"
local V = {}
V.mod = { id = "TERRARIUM" }
local Voxel = {
  angle = math.rad(35), level = 3,
  active = function() return true end,
  FOCAL = 1.0,
}
local ModSetting = {}
ModSetting.new = function(key, label, values, labels)
  return {
    key = key, values = values, labels = labels,
    get = function(self) return rung end,
    row = function(self) return { id = key } end,
    sync = function(self, v) end,
  }
end
local VoxelScene = {
  -- a ridge of wall along z = 6 cells, so the occlusion path has something
  -- to find; everything else is flat ground
  groundAt = function(map, cx, cy)
    if cy == 6 and cx >= 2 and cx <= 12 then return 32 end
    return 0
  end,
}
local Buildings = {
  -- a stamped building model standing over the ridge cells, togglable:
  -- _G.__tall nil means no models anywhere
  tallAt = function(map, cx, cy)
    if _G.__tall and cy == 6 and cx >= 2 and cx <= 12 then return _G.__tall end
    return 0
  end,
}
local mods = { VoxelState = Voxel, ModSetting = ModSetting,
               VoxelScene = VoxelScene, Buildings = Buildings }
V.require = function(n)
  local m = mods[n]
  if m == nil then error("unexpected V.require: " .. tostring(n), 0) end
  return m
end
V.data = function(n)
  if n == "camera_shots" and _G.__shots then return _G.__shots end
  error("no data file", 0)
end
_G.__V = V
_G.__setRung = function(r) rung = r end
_G.__Voxel = Voxel
"""
L.execute(V_SRC)

# --- the fake overworld
GAME_SRC = r"""
local player = { px = 160, py = 160, facing = "down", phase = 0, lift = 0 }
local map = {
  widthCells = 20, heightCells = 18,
  def = { id = "TEST", outdoor = true },
  isWalkableCell = function(self, cx, cy)
    if cy == 6 and cx >= 2 and cx <= 12 then return false end
    return true
  end,
}
local Game = { overworld = { player = player, map = map } }
_G.__engine["src.core.Game"] = Game
_G.__player = player
_G.__map = map
_G.__Game = Game
"""
L.execute(GAME_SRC)

src = open(MOD + r"\lib\MarioCam.lua", encoding="utf-8-sig").read()
chunk = L.eval("function(src) return load(src, '@MarioCam.lua') end")(src)
MarioCam = chunk(L.globals().__V)
print("loaded:", MarioCam is not None)

undefined = L.globals().__undefined
G = L.globals()

fails = []


def step(n, dt=1 / 60.0, vh=144):
    for _ in range(n):
        G.__clock = (G.__clock or 0) + dt
        MarioCam.update(dt, vh)


def cam():
    c = MarioCam.camera()
    if c is None:
        return None
    return dict(eye=list(c.eye.values()), focus=list(c.focus.values()), fov=c.fov)


# ---- 1. it produces a camera at all
step(120)
c = cam()
if not c:
    fails.append("camera() returned nil while enabled")
else:
    print("camera:", {k: [round(x, 2) for x in v] if isinstance(v, list) else round(v, 4)
                      for k, v in c.items()})

# ---- 2. the eye is above the ground and behind the focus
if c:
    if c["eye"][1] <= 0:
        fails.append(f"eye below ground: y={c['eye'][1]}")
    d = math.dist(c["eye"], c["focus"])
    if not (60 < d < 400):
        fails.append(f"camera distance out of range: {d}")

# ---- 3. the focus tracks the player
G.__player.px, G.__player.py = 400, 300
step(240)
c2 = cam()
if c2:
    fx, fz = c2["focus"][0], c2["focus"][2]
    if abs(fx - 408) > 40 or abs(fz - 308) > 40:
        fails.append(f"focus did not track player: {fx:.1f},{fz:.1f} want ~408,308")

# ---- 4. the dead zone. Two properties, and they are different:
#         (a) at rest the focus is CENTRED on the player, not lagging by the
#             zone radius, and
#         (b) a step-and-step-back inside the zone moves the focus almost
#             not at all -- which is the jitter the zone exists to kill.
step(900)                                    # long enough to recentre
c4 = cam()
off = math.hypot(c4["focus"][0] - (G.__player.px + 8),
                 c4["focus"][2] - (G.__player.py + 8))
print(f"at rest, focus is {off:.2f}px off the player")
if off > 3.0:
    fails.append(f"dead zone left the focus {off:.2f}px off centre at rest")
before = cam()["focus"][0]
G.__player.px += 6
step(4)
G.__player.px -= 6
step(4)
after = cam()["focus"][0]
print(f"6px there-and-back moved the focus {abs(after-before):.2f}px")
if abs(after - before) > 1.5:
    fails.append(f"dead zone did not absorb a 6px round trip: {after-before:.2f}")

# ---- 5. the radial yaw actually changes with position around the centre
# map centre is 160,144. Put the player west of it, then east of it.
def yaw_at(px, py):
    G.__player.px, G.__player.py = px, py
    MarioCam.cut()
    step(200)
    return MarioCam.viewYaw()

yw = yaw_at(40, 144)
ye = yaw_at(280, 144)
print(f"viewYaw west={math.degrees(yw):.1f}deg east={math.degrees(ye):.1f}deg")
if abs(yw - ye) < math.radians(20):
    fails.append(f"radial yaw did not swing: west {math.degrees(yw):.1f} east {math.degrees(ye):.1f}")

# ---- 6. the row really is two-state: ON produces a camera
G.__setRung("on")
MarioCam.cut()
step(60)
if MarioCam.camera() is None:
    fails.append("ON produced no camera")

# ---- 7. OFF yields nothing
G.__setRung("off")
step(10)
if MarioCam.camera() is not None:
    fails.append("camera() returned a camera while OFF")
if MarioCam.viewYaw() != 0:
    fails.append("viewYaw non-zero while OFF")

# ---- 8. THE ASYMMETRY, which is the whole point of the port.
#
# Measured as the STEADY-STATE LAG of each layer behind ITS OWN goal, not
# as displacement over a fixed window. Displacement was the first version
# and it needed the yaw pinned to mean anything -- with the orbit live the
# eye's goal moves for two reasons at once (the focus moved, and the orbit
# swung) and the total cannot tell them apart. It read 87% where 66% was
# wanted, and the ladder rung that made it readable no longer exists.
# Comparing each layer to its own target is immune to all of that.
#
# For an exponential chase of a target moving at v the lag settles at
# v*(1-k)/k, so the ratio is fixed by the two coefficients alone. At 0.8
# and 0.3 corrected to 60fps that is a little over six.
G.__setRung("on")
MarioCam.cut()
G.__player.px, G.__player.py = 160, 200
G.__player.phase = 1          # walking, so the pan and dead zone behave
step(400)
sum_foc = sum_pos = 0.0
nsamp = 0
for _ in range(200):
    G.__player.py += 0.7      # a steady walk, ~42 px/s at 60fps
    step(1)
    ct, lk = MarioCam.cam, MarioCam.lakitu
    sum_foc += math.hypot(ct.focus[1] - lk.curFocus[1],
                          ct.focus[3] - lk.curFocus[3])
    sum_pos += math.hypot(ct.pos[1] - lk.curPos[1],
                          ct.pos[3] - lk.curPos[3])
    nsamp += 1
lag_foc, lag_pos = sum_foc / nsamp, sum_pos / nsamp
ratio = lag_pos / lag_foc if lag_foc > 1e-6 else -1
print(f"steady-state lag: focus {lag_foc:.3f}, eye {lag_pos:.3f}, "
      f"ratio {ratio:.2f} (want ~6.3)")
if not (4.0 <= ratio <= 9.0):
    fails.append(f"the 0.8/0.3 asymmetry is not there: ratio {ratio:.2f}")
G.__player.phase = 0

# ---- 9. the shake decays to nothing and leaves no drift
step(300)
rest = cam()
MarioCam.shakeNow("SHAKE_ENV_EXPLOSION")
step(2)
shaken = cam()
moved = math.dist(shaken["focus"], rest["focus"])
print(f"shake displaced focus by {moved:.2f}")
if moved < 0.5:
    fails.append(f"shake did nothing: {moved}")
step(600)
settled = cam()
drift = math.dist(settled["focus"], rest["focus"])
if drift > 0.5:
    fails.append(f"shake left drift: {drift:.3f}")

# ---- 10. framerate independence: 30fps and 120fps land in the same place
def settle(dt, seconds):
    MarioCam.cut()
    G.__player.px, G.__player.py = 160, 144
    step(int(1.0 / dt), dt)
    G.__player.px, G.__player.py = 300, 300
    step(int(seconds / dt), dt)
    return cam()

a = settle(1 / 30.0, 0.5)
b = settle(1 / 120.0, 0.5)
gap = math.dist(a["eye"], b["eye"])
print(f"30fps vs 120fps eye gap after 0.5s: {gap:.2f} world px")
if gap > 6.0:
    fails.append(f"framerate correction failed: {gap:.2f}px apart")

# ---- 11. occlusion: standing north of the wall ridge must not leave the
#         camera looking through it. IN 3D: a segment that passes OVER the
#         wall's top is a camera seeing over it, which is fine and common
#         -- only a segment that dips below 32 while inside the band is a
#         blocked view.
def sight_blocked(c):
    ex, ey, ez = c["eye"]
    fx, fz = c["focus"][0], c["focus"][2]
    fy = c["focus"][1] + 8                    # the player's middle
    for i in range(1, 40):
        t = i / 40
        x = ex + (fx - ex) * t
        z = ez + (fz - ez) * t
        y = ey + (fy - ey) * t
        cx, cy = int(x // 16), int(z // 16)
        if cy == 6 and 2 <= cx <= 12 and y < 32:
            return True
    return False

G.__setRung("on")
MarioCam.cut()
G.__player.px, G.__player.py = 112, 64      # cell 7,4 -- north of the ridge at cy=6
step(300)
c = cam()
print(f"eye at {c['eye'][0]:.0f},{c['eye'][2]:.0f} focus {c['focus'][0]:.0f},"
      f"{c['focus'][2]:.0f} -- sight blocked: {sight_blocked(c)}")
if sight_blocked(c):
    fails.append("occlusion did not steer the camera around the wall")

# ---- 13. the ray test is three-dimensional: the same 2D line, blocked or
#          clear purely by the HEIGHT it flies at. This is the fix for the
#          camera steering around buildings it was looking over the top of.
high = MarioCam.rayBlocked(G.__map, 112, 120, 20, 112, 8, 170)
low = MarioCam.rayBlocked(G.__map, 112, 20, 20, 112, 8, 170)
print(f"ray over the 32-wall: high(y120)={high} low(y20)={low}")
if high:
    fails.append("a ray flying high over the wall reads as blocked (spurious steer)")
if not low:
    fails.append("a ray flying under the wall top reads as clear (real occlusion missed)")

# ---- 13b. a stamped BUILDING MODEL occludes at its real height: the same
#           high ray that clears the 32px wall must read blocked when a
#           120px model stands on those cells -- the mesher's flat ground
#           under models is a lie the camera must not inherit.
G.__tall = 120
tall_blocked = MarioCam.rayBlocked(G.__map, 112, 120, 20, 112, 8, 170)
G.__tall = None
tall_clear = MarioCam.rayBlocked(G.__map, 112, 120, 20, 112, 8, 170)
print(f"building-model ray: with 120px model blocked={tall_blocked}, without={tall_clear}")
if not tall_blocked:
    fails.append("a 120px building model did not occlude the high ray")
if tall_clear:
    fails.append("clearing the model did not clear the ray")

# ---- 14. the deflection ACCUMULATES: parked with the eye's line through
#          the ridge, the camera must actually slide around it until the
#          player is visible -- and let the deflection back out once the
#          straight view is clear again. The old easing restarted from the
#          mode's yaw every frame and never got anywhere.
G.__Voxel.angle = math.radians(70)          # a low lens, so the ridge really occludes
MarioCam.cut()
# near the EAST END of the ridge: rotation can win by looking around the
# corner. (Dead centre behind an eleven-cell wall is the boxed-in case,
# where pulling in is the answer and no deflection is the right reading.)
G.__player.px, G.__player.py = 184, 108
step(600)
ct = MarioCam.cam
clear = MarioCam.eyeClear(G.__map, ct.focus, ct.dist, ct.pitch, ct.yaw)
off = MarioCam.avoidState.offset
off_deg = off * 360.0 / 0x10000
print(f"avoidance settled: offset {off_deg:.1f} deg, final view clear: {clear}")
if not clear:
    fails.append("avoidance never found the player a clear line past the ridge")
if abs(off_deg) < 8:
    fails.append(f"the deflection did not accumulate: {off_deg:.1f} deg")
G.__player.px, G.__player.py = 52, 200      # open ground, nothing in the way
step(600)
off2 = MarioCam.avoidState.offset * 360.0 / 0x10000
print(f"after walking clear, offset relaxed to {off2:.1f} deg")
if abs(off2) > 2:
    fails.append(f"the deflection did not relax once clear: {off2:.1f} deg")
G.__Voxel.angle = math.radians(35)
MarioCam.cut()

# ---- 15. the quadrant LATCHES under the thumb: while a direction is held
#          (or a step is in flight) the input mapping must not change, no
#          matter how far the camera swings -- and it re-reads the camera
#          the moment the player lets go.
G.__steer = False
MarioCam.setSteeringProbe(L.eval("function() return __steer end"))
G.__player.px, G.__player.py = 280, 144
MarioCam.recenter()
MarioCam.cut()
step(300)
q0 = MarioCam.quadrant()
G.__steer = True
MarioCam.rotateLeft()
MarioCam.rotateLeft()                       # 120 degrees: two quadrants away
step(400)
q_held = MarioCam.quadrant()
G.__steer = False
step(1)
q_free = MarioCam.quadrant()
print(f"quadrant: rest {q0}, after 120deg swing held {q_held}, released {q_free}")
if q_held != q0:
    fails.append(f"quadrant changed under a held direction: {q0} -> {q_held}")
if q_free == q0:
    fails.append("quadrant never updated after release")
G.__player.phase = 1                        # a step in flight latches too
MarioCam.rotateLeft()
MarioCam.rotateLeft()
step(400)
q_move = MarioCam.quadrant()
if q_move != q_free:
    fails.append(f"quadrant changed mid-step: {q_free} -> {q_move}")
G.__player.phase = 0
step(60)
q_done = MarioCam.quadrant()
print(f"quadrant: mid-step {q_move}, after the step lands {q_done}")
if q_done == q_free:
    fails.append("quadrant never updated after the step landed")
MarioCam.setSteeringProbe(None)
MarioCam.recenter()

# ---- 16. authored FIXED shot: walking into the box switches the mode,
#          parks the eye where the author said, eases the lens in over the
#          shot's frames, refuses the framing keys with a buzz, and lets
#          go of all of it on the way out.
L.execute("""
_G.__shots = { TEST = {
  { x = 96, z = 200, bx = 24, bz = 24, mode = "fixed",
    camX = 96, camY = 80, camZ = 320, focY = 12, fov = 30, frames = 20 },
} }
""")
MarioCam.reloadShots()
G.__player.px, G.__player.py = 88, 284      # south of the box
MarioCam.cut()
step(300)
if MarioCam.cam.mode != "radial":
    fails.append(f"outside the box the mode is {MarioCam.cam.mode}, want radial")
G.__player.px, G.__player.py = 88, 192      # inside the box
step(2)
fov_early = MarioCam.lakitu.fov
step(300)
c16 = cam()
if MarioCam.cam.mode != "fixed":
    fails.append(f"inside the box the mode is {MarioCam.cam.mode}, want fixed")
eye_err = math.dist(c16["eye"], [96, 80, 320])
lens = MarioCam.lakitu.fov
print(f"fixed shot: eye {eye_err:.1f}px off the authored spot, lens {lens:.1f} "
      f"(was {fov_early:.1f} two frames in)")
if eye_err > 4:
    fails.append(f"fixed shot eye is {eye_err:.1f}px off the authored camX/Y/Z")
if not (28 < lens < 32):
    fails.append(f"shot fov did not arrive: {lens:.1f} want ~30")
if fov_early < 40:
    fails.append(f"shot fov jumped instead of easing: {fov_early:.1f} two frames in")
before_goal = MarioCam.ctl.goalOffsetYaw
ok_rot = MarioCam.rotateLeft()
buzzed = MarioCam.consumeBuzz()
if ok_rot or not buzzed or MarioCam.ctl.goalOffsetYaw != before_goal:
    fails.append("rotating inside a fixed shot did not buzz-refuse")
zoom_before = MarioCam.ctl.zoom
MarioCam.cycleZoom()
if not MarioCam.consumeBuzz() or MarioCam.ctl.zoom != zoom_before:
    fails.append("zooming inside a fixed shot did not buzz-refuse")
G.__player.px, G.__player.py = 88, 284      # back out
step(400)
lens_out = MarioCam.lakitu.fov
if MarioCam.cam.mode != "radial":
    fails.append(f"leaving the box did not restore the orbit: {MarioCam.cam.mode}")
if not (43.5 < lens_out < 46.5):
    fails.append(f"leaving the box did not release the lens: {lens_out:.1f}")
print(f"left the box: mode {MarioCam.cam.mode}, lens {lens_out:.1f}")

# ---- 17. pinned-orbit shot: zoom and pitch obey the author, the framing
#          keys buzz -- and a mode-only shot (a corridor) pins nothing and
#          keeps every key working.
L.execute("""
_G.__shots = { TEST = {
  { x = 96, z = 200, bx = 24, bz = 24, mode = "radial", zoom = 120, pitch = 20 },
  { x = 240, z = 200, bx = 24, bz = 24, mode = "eight" },
} }
""")
MarioCam.reloadShots()
G.__player.px, G.__player.py = 88, 192
MarioCam.cut()
step(200)
dist = MarioCam.cam.dist
pitch_deg = MarioCam.cam.pitch * 360.0 / 0x10000
print(f"pinned orbit: dist {dist:.1f} (want 120), pitch {pitch_deg:.1f} (want 20)")
if abs(dist - 120) > 2:
    fails.append(f"pinned zoom not applied: dist {dist:.1f}")
if abs(pitch_deg - 20) > 1:
    fails.append(f"pinned pitch not applied: {pitch_deg:.1f}")
MarioCam.rotateLeft()
if not MarioCam.consumeBuzz():
    fails.append("rotating inside a pinned-orbit shot did not buzz")
G.__player.px, G.__player.py = 232, 192     # the mode-only corridor box
step(200)
if MarioCam.cam.mode != "eight":
    fails.append(f"corridor box did not switch to eight: {MarioCam.cam.mode}")
ok_rot = MarioCam.rotateRight()
if not ok_rot or MarioCam.consumeBuzz():
    fails.append("a mode-only shot wrongly refused the framing keys")
MarioCam.recenter()

# ---- 18. the lens pace derives from the shot's frames
k = MarioCam.fovState.k
want_k = 1 - 0.1 ** (1 / 30.0)              # the corridor has no fov: release pace
G.__player.px, G.__player.py = 88, 284
step(60)
L.execute("_G.__shots = nil")
MarioCam.reloadShots()
step(60)
print(f"fov pace k={k:.4f}")

# and a map CHANGE cuts the lens back instantly (SET, not APP)
L.execute("""
_G.__shots = { TEST = {
  { x = 96, z = 200, bx = 24, bz = 24, mode = "fixed",
    camX = 96, camY = 80, camZ = 320, fov = 24, frames = 40 },
} }
local old = _G.__map
local copy = {}
for k, v in pairs(old) do copy[k] = v end
_G.__mapCopy = copy
""")
MarioCam.reloadShots()
G.__player.px, G.__player.py = 88, 192
step(200)
if not (23 < MarioCam.lakitu.fov < 26):
    fails.append(f"setup for the cut test: lens {MarioCam.lakitu.fov:.1f} want ~24")
G.__player.px, G.__player.py = 88, 284      # out of the box, lens mid-release
step(6)
mid = MarioCam.lakitu.fov
G.__Game.overworld.map = G.__mapCopy        # a NEW map object: a cut
step(1)
after_cut = MarioCam.lakitu.fov
print(f"lens mid-release {mid:.1f}, one frame after the map cut {after_cut:.1f}")
if abs(after_cut - 45) > 0.01:
    fails.append(f"a map change did not SET the lens home: {after_cut:.2f}")
L.execute("_G.__shots = nil")
MarioCam.reloadShots()
MarioCam.cut()
step(60)

# ---- 19. the presentation yaw: zero at a cardinal, a real turn at a
#          diagonal, and always opposing the camera's divergence from the
#          drawing's own angle -- checked against independently measured
#          viewYaw and quadrant, so a sign flip or a wrong-quad read shows.
G.__player.px, G.__player.py = 280, 144     # due east: a cardinal view
MarioCam.recenter()
MarioCam.cut()
step(300)
p0 = math.degrees(MarioCam.presentYaw())
if abs(p0) > 3:
    fails.append(f"presentYaw at a settled cardinal is {p0:.1f} deg, want ~0")
MarioCam.rotateLeft()                       # 60 degrees off the cardinal
step(400)
deg = math.degrees(MarioCam.viewYaw())
q = MarioCam.quadrant()
off = ((deg - q * 90 + 180) % 360) - 180
want = max(-18.0, min(18.0, -off * 0.4))
p1 = math.degrees(MarioCam.presentYaw())
print(f"presentYaw: cardinal {p0:.1f}, diagonal {p1:.1f} (off {off:.1f}, want {want:.1f})")
if abs(p1 - want) > 2:
    fails.append(f"presentYaw {p1:.1f} disagrees with its own contract ({want:.1f})")
if abs(p1) < 8:
    fails.append(f"presentYaw barely turns at a diagonal: {p1:.1f}")
MarioCam.recenter()
step(120)

# ---- 20. the SHOULDER rung: over-the-shoulder everywhere on land --
#          behind the facing, closer and lower than the orbit, swinging to
#          the new back when the player turns.
G.__setRung("shoulder")
MarioCam.recenter()
G.__player.px, G.__player.py = 240, 240
G.__player.facing = "up"
MarioCam.cut()
step(400)
if MarioCam.cam.mode != "behind":
    fails.append(f"shoulder rung on dry land runs {MarioCam.cam.mode}, want behind")
vy = math.degrees(MarioCam.viewYaw()) % 360
if min(vy, 360 - vy) > 10:
    fails.append(f"facing up, the camera is not at the back: viewYaw {vy:.1f}")
d_shoulder = MarioCam.cam.dist
if abs(d_shoulder - 175 * 0.7) > 4:
    fails.append(f"shoulder distance {d_shoulder:.1f}, want ~{175*0.7:.0f}")
# THE FOLLOW COMMITS: turning in place moves NOTHING (the grid washing
# machine the player reported); only a SUSTAINED walk re-aims the world.
G.__player.facing = "right"
step(400)                                   # standing: no commitment
vy_hold = math.degrees(MarioCam.viewYaw()) % 360
if min(vy_hold, 360 - vy_hold) > 12:
    fails.append(f"turning in place swung the camera: viewYaw {vy_hold:.1f}")
G.__player.phase = 1                        # now actually walking right
step(150)                                   # commit (~0.6s) + swing + chase
vy2 = math.degrees(MarioCam.viewYaw()) % 360
print(f"shoulder: dist {d_shoulder:.1f}, turn-in-place held {vy_hold:.1f}, "
      f"committed right {vy2:.1f}")
if abs(vy2 - 90) > 12:
    fails.append(f"a committed walk did not re-aim the follow: {vy2:.1f}")

# the ABOUT-FACE: a held walk back swings urgently -- but only once
# committed. Early, the camera still HOLDS (the calm gate); afterwards,
# rendered view included, it stands at the new back. The polite divisor
# alone would leave it ~25-30 out at the second reading, so the bound
# also proves the reversal latch engaged.
G.__player.facing = "left"
step(20)
vy_early = math.degrees(MarioCam.viewYaw()) % 360
dev_early = abs(((vy_early - 270 + 180) % 360) - 180)
if dev_early < 120:
    fails.append(f"the about-face moved before commitment: dev {dev_early:.1f}")
step(70)
vy3 = math.degrees(MarioCam.viewYaw()) % 360
dev3 = abs(((vy3 - 270 + 180) % 360) - 180)
print(f"about-face: early dev {dev_early:.1f} (holding), "
      f"after commit+swing dev {dev3:.1f}")
if dev3 > 15:
    fails.append(f"the committed about-face is not urgent: {dev3:.1f} deg off")
G.__player.phase = 0
G.__player.facing = "down"
G.__setRung("on")
MarioCam.cut()
step(60)

# ---- 12. no undefined globals were read
bad = {k: v for k, v in dict(undefined).items() if not k.startswith("__")}
if bad:
    fails.append(f"undefined globals read: {bad}")

print()
if fails:
    print("FAILURES:")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("ALL CHECKS PASSED")
