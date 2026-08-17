-- Probe: the grass PHYSICS pass -- 3D tuft bend, weather load, foot springs,
-- the AUTO wind row, and the wind's own VFX.
--
-- Five questions, each answered with a number rather than an impression:
--
--   1  AUTO spans      does the AUTO row actually travel from near-still on
--                      a clear day to gale under a front, without anybody
--                      touching the menu?
--   2  load reaches    do rain (falling) and snow (settled) arrive at the
--                      grass as Wind.grassWet / Wind.grassSnow, and do they
--                      DAMP the lean rather than merely coexist with it?
--   3  springs         does a foot leaving a tuft let it stand back up over
--                      time, and does it overshoot past upright on the way?
--   4  air is visible  does WindFX carry streaks once the air is over its
--                      floor, and does a gust throw a front?
--   5  it still draws  screenshots, because a shader that fails to compile
--                      fails silently and every number above still passes
--                      (the battle-HUD ink lesson).
--
--   POKEPORT_VERSION=yellow \
--   DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/grass_physics_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/grass_physics_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n")
    logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

  -- A shot AND its mean brightness: a black frame is what a dead shader
  -- looks like, and it is the one failure every other number here misses.
  local function shot(name)
    local path = OUT .. "/" .. name
    love.graphics.captureScreenshot(function(data)
      local f = io.open(path, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      local ok, w, h = pcall(function()
        return data:getWidth(), data:getHeight()
      end)
      if not ok then return end
      local sum, n, lo, hi = 0, 0, 1, 0
      for gy = 0, 15 do
        for gx = 0, 15 do
          local px = math.floor(gx * (w - 1) / 15)
          local py = math.floor(gy * (h - 1) / 15)
          local okp, r, g, b = pcall(data.getPixel, data, px, py)
          if okp then
            local l = (r + g + b) / 3
            sum, n = sum + l, n + 1
            if l < lo then lo = l end
            if l > hi then hi = l end
          end
        end
      end
      if n > 0 then
        log(("shot %s mean=%.3f min=%.3f max=%.3f"):format(
              name, sum / n, lo, hi))
      end
    end)
    wait(4)
  end

  love.math.setRandomSeed(20260806)

  local frames = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); frames = frames + 1
    if frames > 900 then log("FAIL: no overworld") logf:close()
      love.event.quit() return end
  end
  frames = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); frames = frames + 11
    if frames > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end
  log("version:", exports.TERRARIUM.version)

  local Wind = lib.require("Wind")
  local WindFX = lib.require("WindFX")
  local Grass3D = lib.require("Grass3D")
  local Weather = lib.require("Weather")
  local GroundFX = lib.require("GroundFX")
  local DayNight = lib.require("DayNight")
  local Voxel3D = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")

  local pass, fail = 0, 0
  local function check(ok, msg)
    if ok then pass = pass + 1; log("PASS: " .. msg)
    else fail = fail + 1; log("FAIL: " .. msg) end
  end

  DayNight.setting:sync("day")
  Pipelines.setLevel("terrarium_voxel", 4)
  game.overworld:setMap("ROUTE_1", 10, 28, "down")
  wait(180)

  -- ================= 1. the AUTO row ==================================
  log("--- 1. AUTO row")
  local labels = table.concat(Wind.setting.labels, "/")
  log("wind ladder:", labels, "values[1]=", tostring(Wind.setting.values[1]))
  check(Wind.setting.labels[1] == "AUTO" and Wind.setting.values[1] == 1,
        "AUTO is the first row, so it is the default")

  Wind.setting:sync(1)
  Weather.setting:sync("off")
  for _ = 1, 400 do Weather.update(1 / 30) end
  -- sample the calm floor over a few seconds: the gust envelope moves, and
  -- one instant of it is not the day
  local calmLo, calmHi = 99, 0
  for _ = 1, 40 do
    for _ = 1, 6 do Weather.update(1 / 30) end
    local a = Wind.amount()
    if a < calmLo then calmLo = a end
    if a > calmHi then calmHi = a end
    wait(1)
  end
  log(("AUTO clear day: %.2f .. %.2f px"):format(calmLo, calmHi))

  Weather.setting:sync("rain")
  for _ = 1, 900 do Weather.update(1 / 30) end
  local stormLo, stormHi = 99, 0
  for _ = 1, 40 do
    for _ = 1, 6 do Weather.update(1 / 30) end
    local a = Wind.amount()
    if a < stormLo then stormLo = a end
    if a > stormHi then stormHi = a end
    wait(1)
  end
  log(("AUTO downpour:  %.2f .. %.2f px  (drive=%.2f front=%.2f)"):format(
        stormLo, stormHi, Wind.drive, Wind.weatherDrive))
  check(stormHi > calmHi * 1.6,
        "AUTO climbs on its own under a front (no menu visit)")
  check(stormHi >= 3.0, "AUTO reaches gale territory under a downpour")
  check(calmLo <= 1.6, "AUTO still lets a clear day be calm")

  -- ================= 2. what is lying on the blades ===================
  log("--- 2. weather load")
  local wet, snow, gust = Wind.load()
  log(("under rain: wet=%.2f snow=%.2f gust=%.2f"):format(wet, snow, gust))
  check(wet > 0.15, "falling rain reaches the grass as Wind.grassWet")

  -- ------- the damping, measured across SPACE rather than across time
  --
  -- The obvious test -- sample the lean at one spot for a while, wet, then
  -- dry, and compare -- does not work, and it is worth writing down why,
  -- because it looks like it should and it passes and fails at random.
  -- The wave's period out here is about four seconds and the squall
  -- front's is nearly twelve, the frame rate is not fixed, and the wet and
  -- dry windows land on different parts of both. So the number that comes
  -- back is whichever bit of the sine the sampling happened to sit on, and
  -- two runs of an unchanged build measured 5.26/6.51 and 5.69/3.84.
  --
  -- But the wave's phase is `dot(worldXZ, FREQ) - phase`, so WALKING THE X
  -- AXIS sweeps it exactly as time does: 4000 world pixels at FREQ.x is
  -- about forty full cycles. Sampled that way the whole average happens
  -- inside ONE frame -- both wet and dry on one clock reading, one
  -- `amount`, one front, nothing drifting underneath -- and the mean is
  -- over dozens of periods instead of a fraction of one.
  --
  -- Normalised by Wind.amount() as well, so the snow sample twenty seconds
  -- later is comparable: dividing out the reach leaves exactly what is
  -- under test, which is how much of that reach the load lets through.
  local function meanLean()
    local amt = Wind.amount()
    if amt <= 0 then return 0 end
    local sum, n = 0, 0
    for i = 0, 399 do
      local wx = i * 10          -- 4000 px of X, ~40 cycles of the wave
      local wz = 448 + i * 3     -- and a diagonal, so FREQ.z is swept too
      local dx, dz = Wind.leanAt(wx, wz, 1.0)
      sum, n = sum + math.sqrt(dx * dx + dz * dz), n + 1
    end
    return (sum / n) / amt
  end
  local heldAmount = Wind.amount()
  local heldWet = Wind.grassWet
  local leanWet = meanLean()
  Wind.grassWet = 0
  local leanDry = meanLean()
  Wind.grassWet = heldWet
  log(("mean lean wet=%.3f dry=%.3f (amount~%.2f, wet=%.2f)"):format(
        leanWet, leanDry, heldAmount, heldWet))
  check(leanWet < leanDry,
        "a wet blade is heavier: rain DAMPS the lean instead of adding to it")

  -- snow settles, and settled snow is what bows a tuft over
  Weather.setting:sync("snow")
  for _ = 1, 1200 do
    Weather.update(1 / 30)
    GroundFX.update(1 / 30)
  end
  local _, snowLoad = Wind.load()
  log(("after a snowfall: cover=%.2f grassSnow=%.2f"):format(
        GroundFX.cover(), snowLoad))
  check(snowLoad > 0.05, "settled snow reaches the grass as Wind.grassSnow")
  -- and the snow's own damping, held against the dry number above with the
  -- rain taken back off so the two differ in one thing only
  Wind.grassWet = 0
  local leanSnow = meanLean()
  log(("mean lean under snow=%.3f (dry was %.3f, snow=%.2f)"):format(
        leanSnow, leanDry, snowLoad))
  check(leanSnow < leanDry, "snow stiffens what it is sitting on")

  -- ================= 3. foot springs ==================================
  log("--- 3. crush springs")
  Weather.setting:sync("off")
  for _ = 1, 300 do Weather.update(1 / 30); GroundFX.update(1 / 30) end
  Grass3D.clearTracks()
  local foot = { { 200, 200, 12, 1.0 } }
  local downCurve = {}
  for i = 1, 12 do
    local c = Grass3D.crushFrame(foot, 1 / 30)
    downCurve[i] = (c.n > 0) and c.p[1][4] or 0
  end
  log(("crush ramp: %.2f %.2f %.2f -> %.2f"):format(
        downCurve[1], downCurve[2], downCurve[4], downCurve[12]))
  check(downCurve[12] > 0.85, "a foot standing in it flattens the tuft")
  check(downCurve[1] < downCurve[4],
        "and it goes down over frames rather than snapping flat")

  local upCurve, minS = {}, 99
  for i = 1, 60 do
    local c = Grass3D.crushFrame({}, 1 / 30)
    local s = (c.n > 0) and c.p[1][4] or 0
    upCurve[i] = s
    if s < minS then minS = s end
  end
  log(("release: %.2f %.2f %.2f %.2f ... min=%.3f end=%.3f"):format(
        upCurve[1], upCurve[5], upCurve[15], upCurve[30], minS, upCurve[60]))
  check(upCurve[5] < downCurve[12] and upCurve[5] > 0.2,
        "it stands back up over the better part of a second, not instantly")
  check(minS < -0.005, "and it overshoots past upright -- it springs, not fades")
  check(math.abs(upCurve[60]) < 0.05, "and it settles")

  -- ================= 4. the wind's own VFX ============================
  log("--- 4. wind vfx")
  Wind.setting:sync(4)              -- GALE: well over the VFX floor
  for _ = 1, 300 do Weather.update(1 / 30) end
  local seen, peakN = 0, 0
  for _ = 1, 120 do
    WindFX.update(1 / 30, true)
    local n = WindFX.count()
    if n > 0 then seen = seen + 1 end
    if n > peakN then peakN = n end
    wait(1)
  end
  log(("windfx: frames with streaks %d/120, peak %d, amount=%.2f gust=%.2f")
        :format(seen, peakN, Wind.amount(), Wind.gust()))
  check(peakN > 0, "the air carries visible streaks under a gale")

  Wind.setting:sync(0)              -- OFF: silence means silence
  for _ = 1, 60 do Weather.update(1 / 30) end
  for _ = 1, 10 do WindFX.update(1 / 30, true); wait(1) end
  log("windfx under WIND OFF:", WindFX.count())
  check(WindFX.count() == 0, "WIND OFF draws no air at all")

  -- ================= 5. it still draws ================================
  log("--- 5. it still draws")
  Wind.setting:sync(1)
  Weather.setting:sync("off")
  for _ = 1, 300 do Weather.update(1 / 30); GroundFX.update(1 / 30) end
  wait(30)
  -- `grassH` is a per-PASS channel like snowTop and crush: VoxelScene sets
  -- it for the grass draws and clears it again before the flowers, so it
  -- reads nil from out here by design. What is worth logging is whether
  -- there is a bake to take a height FROM -- with no bake the classic slab
  -- draws and the default height is the right one.
  local bake = Grass3D.available() and Grass3D.meta()
  log(("grass bake: %s  height=%s  default=%s"):format(
        tostring(Grass3D.available()),
        tostring(bake and bake.height), tostring(Voxel3D.GRASS_H)))
  check((bake and bake.height or Voxel3D.GRASS_H) > 0,
        "the bend curve has a real tuft height to normalise over")
  shot("grass_auto_clear.png")

  -- and the streaks themselves, ON SCREEN. AUTO on a clear day sits under
  -- the VFX floor by design, so the shots above cannot show them and a
  -- WindFX that drew nothing at all would pass every count above (the
  -- battle-HUD ink lesson: a marker that draws nothing draws nothing
  -- silently). The real frame loop drives WindFX.update from main.lua, so
  -- this only has to set the row and let frames pass.
  Wind.setting:sync(4)
  for _ = 1, 400 do Weather.update(1 / 30) end
  wait(150)
  log(("gale: amount=%.2f streaks=%d"):format(Wind.amount(), WindFX.count()))
  check(WindFX.count() > 0, "streaks are alive in the real frame loop")
  shot("grass_gale_vfx.png")
  Wind.setting:sync(1)

  -- ================= 6. the walked trail =============================
  --
  -- BEFORE the rain and the snow, deliberately. A saturated snowfield is
  -- the last thing a trail shot wants: cover reaches 1.0, the meadow goes
  -- white, and laid grass against snowed grass is a distinction nobody can
  -- make in a screenshot. Green grass on a clear day is where a parted
  -- path is legible -- and melting a full cover back off would take seven
  -- minutes of GroundFX.MELT to undo.
  log("--- 6. trail")
  check(Voxel3D.crushSendOk ~= false,
        "the crush array reaches the shader (an 8-slot array send)")

  -- Walked through the INPUT STATE, not by assignment: the trail is built
  -- from a foot that moved, and an assignment is not a step. The direction
  -- is tried rather than chosen -- a probe that walks into a wall and then
  -- reports no trail has measured the wall.
  -- Put the player back on a known tile with grass around it. The phases
  -- above ran thousands of synchronous weather ticks and took three
  -- screenshots; starting the walk from wherever that left things is how a
  -- probe ends up measuring a doorway.
  -- ------- start IN the grass, and ask the map where that is
  --
  -- Two runs of this were placed by hand and both were wrong in a way the
  -- numbers could not see. (10,28) is four cells from Viridian's gate, so
  -- a long held "down" walks off the route entirely -- the trail was laid
  -- correctly on a map the camera had already left, every count passed,
  -- and the screenshot came back a picture of a town square. (10,18) put
  -- the player on the PATH: crumbs dropped on bare paving, where there is
  -- no grass to lay and nothing to photograph.
  --
  -- The map knows. `map:isGrassCell` is the same question WildRoamers,
  -- AmbientLife and the mesher all ask, so the probe asks it too: find a
  -- run of grass cells with room to walk south through them, and stand at
  -- the top of it.
  game.overworld:setMap("ROUTE_1", 10, 24, "down")
  wait(60)
  do
    local map = game.overworld.map
    local bx, by, bn = nil, nil, 0
    if map and map.isGrassCell and map.inBounds then
      for cx = 2, 18 do
        local run, top = 0, nil
        for cy = 2, 34 do
          local ok = map:inBounds(cx, cy) and map:isGrassCell(cx, cy)
          if ok then
            if run == 0 then top = cy end
            run = run + 1
            if run > bn then bn, bx, by = run, cx, top end
          else
            run = 0
          end
        end
      end
    end
    log(("grass run: %s cells at (%s,%s)"):format(
          tostring(bn), tostring(bx), tostring(by)))
    if bx and bn >= 3 then
      game.overworld:setMap("ROUTE_1", bx, by, "down")
    end
  end
  wait(120)
  Grass3D.clearTracks()
  local pl = game.overworld.player
  local home = game.overworld.map.id
  log(("before walk: top==overworld=%s cell=(%d,%d) map=%s"):format(
        tostring(game.stack:top() == game.overworld),
        pl.cellX or -1, pl.cellY or -1, tostring(home)))
  -- ------- holding a direction means holding it EVERY FRAME
  --
  -- The engine rebuilds `input.state` from the real keyboard on its own
  -- tick, so a flag set once and left alone is true for about one frame
  -- and gone. Setting it before a `wait(9)` therefore buys nine frames of
  -- nothing and one lucky step: a run of this measured a single cell out
  -- of seventy-two frames of "held" input, and a trail of one crumb --
  -- which reads exactly like a trail feature that does not work.
  local bestTrail, bestSlots = 0, 0
  local function hold(dir, frames)
    for _ = 1, frames do
      game.input.state[dir] = true
      coroutine.yield()
      local n = Grass3D.trailCount()
      if n > bestTrail then bestTrail = n end
      local c = Grass3D.crushFrame({}, 0)   -- read-only peek, dt = 0
      if c.n > bestSlots then bestSlots = c.n end
      if game.overworld.map.id ~= home then break end
    end
    game.input.state[dir] = false
  end

  local went = "-"
  for _, dir in ipairs({ "down", "up", "left", "right" }) do
    local x0, y0 = pl.cellX, pl.cellY
    hold(dir, 55)
    wait(6)
    local moved = (pl.cellX ~= x0 or pl.cellY ~= y0)
    log(("  %s: (%d,%d) -> (%d,%d) moved=%s trail=%d"):format(
          dir, x0 or -1, y0 or -1, pl.cellX or -1, pl.cellY or -1,
          tostring(moved), Grass3D.trailCount()))
    if moved then went = dir break end
    if game.overworld.map.id ~= home then break end
  end
  log(("walked %s: peak trail crumbs=%d, peak crush slots=%d, span=%s"):format(
        went, bestTrail, bestSlots,
        tostring(Grass3D.trailSpan and Grass3D.trailSpan())))
  check(went ~= "-", "the player actually moved (otherwise this measures a wall)")
  -- Four crumbs was the old uniform budget. The map path keeps many more;
  -- four is still the floor so a walk that laid nothing still fails.
  check(bestTrail >= 4, "walking leaves a line of laid grass behind")
  if Grass3D.trailSpan then
    check(Grass3D.trailSpan() >= 24,
          "the trail is longer than the old 24 px uniform plank")
  else
    check(bestSlots > 1, "and foot plus trail reach the shader together")
  end

  -- and the same walk, seen. Walked south -- the camera looks north, so
  -- the path is BEHIND the player and therefore up the frame, where it can
  -- be looked at -- then stopped, and the shot taken a moment later while
  -- the player stands still. That is the honest picture of the feature: it
  -- is not "grass is bent under a walker", which any per-frame crush does,
  -- it is "you can stop, and the way you came is still there".
  local dir = (went ~= "-") and went or "down"
  for _ = 1, 45 do
    game.input.state[dir] = true
    coroutine.yield()
    if game.overworld.map.id ~= home then break end
  end
  game.input.state[dir] = false
  wait(14)
  log(("trail at shot: %d crumbs, cell=(%d,%d) map=%s"):format(
        Grass3D.trailCount(), pl.cellX or -1, pl.cellY or -1,
        tostring(game.overworld.map.id)))
  check(Grass3D.trailCount() > 0,
        "the path is still there after the walker has stopped")
  shot("grass_trail_walk.png")

  -- ================= 7. and the same meadow under weather =============
  log("--- 7. weather shots")
  Weather.setting:sync("rain")
  for _ = 1, 600 do Weather.update(1 / 30); GroundFX.update(1 / 30) end
  wait(30)
  shot("grass_auto_rain.png")

  -- A deep fall, not a dusting: GroundFX.SETTLE is 100 seconds of snowfall
  -- at full power to a saturated cover, and the shot is about what the
  -- grass CARRIES, so it has to be worked most of the way there. At 50
  -- seconds the earlier cut of this reached 0.34 and the caps on the tufts
  -- were real but nearly invisible, which is a screenshot that proves
  -- nothing.
  Weather.setting:sync("snow")
  for _ = 1, 4200 do Weather.update(1 / 30); GroundFX.update(1 / 30) end
  wait(30)
  local _, capLoad = Wind.load()
  log(("deep snow: cover=%.2f grassSnow=%.2f"):format(
        GroundFX.cover(), capLoad))
  check(capLoad > 0.5, "a long snowfall piles up on the blades, not a dusting")
  shot("grass_auto_snow.png")

  wait(10)
  log(("done: %d pass, %d fail"):format(pass, fail))
  logf:close()
  love.event.quit()
end
