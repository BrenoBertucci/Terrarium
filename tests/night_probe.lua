-- Probe: the night -- how dark it got, what is lit, what is out, and what
-- the new sky costs.
--
-- Four things changed together and they have to be separable, so each gets
-- its own number rather than sharing a screenshot:
--
--   the DARK      DayNight.TINTS.night dropped, so the world multiplies by
--                 less. That is a table diff (see also daynight_dial_probe).
--   the LAMPS     DayNight.lampColor is new: a curve where the shader had a
--                 constant. Logged across the cycle.
--   the STARS     DayNight.starAmount drives a field painted by lib/Sky.lua.
--                 Logged as a curve, and the field itself is counted.
--   the FIREFLIES their cap rides starAmount now instead of being flat 12.
--
-- And then the only question that can actually sink any of it: WHAT DOES IT
-- COST. Measured as a PALINDROME in one process -- no-stars, stars, stars,
-- no-stars -- because the first and last phase of a run in this build differ
-- by more than any of these changes could, and running OLD then NEW once
-- charges NEW for the warm-up OLD did. The two middle phases and the two
-- outer phases are averaged against each other instead.
--
-- The stars are switched by stubbing Quality.starCount to 0, which is the
-- real gate Sky.paintStars reads -- and it sits before the meteor too, so
-- OFF is genuinely the whole of the new drawing and not part of it.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/night_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/night_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

  love.math.setRandomSeed(20260802)

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit()
      return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit()
    return
  end
  log("version:", exports.TERRARIUM.version)

  local DayNight = lib.require("DayNight")
  local Sky = lib.require("Sky")
  local Quality = lib.require("Quality")
  local Voxel3D = lib.require("Voxel3D")
  local Weather = lib.require("Weather")
  local Pipelines = require("src.render.Pipelines")

  Weather.setting:sync("off")
  DayNight.setting:sync("cycle")
  DayNight.overcast = 0
  wait(30)
  DayNight.overcast = 0

  local C = DayNight.CYCLE

  -- ------- the field itself
  log("")
  log("=== the star field (built once, deterministic) ===")
  local field = Sky._starField()
  local tiers = { 0, 0, 0, 0 }
  for i = 1, #field do tiers[field[i].tier] = tiers[field[i].tier] + 1 end
  log(("  STAR_MAX=%d  built=%d  seed=%d"):format(Sky.STAR_MAX, #field,
      Sky.STAR_SEED))
  log(("  by tier (brightest first): %d %d %d %d")
      :format(tiers[1], tiers[2], tiers[3], tiers[4]))
  log(("  Quality.starCount() = %d at render scale %d")
      :format(Quality.starCount(), Quality.scale()))
  -- The field must be sorted brightest first, or drawing a prefix at a cheap
  -- rung throws away the stars the player would have noticed and keeps the
  -- ones they would not.
  local sorted = true
  for i = 2, #field do
    if field[i].mag > field[i - 1].mag + 1e-9 then sorted = false end
  end
  log("  sorted brightest-first: " .. (sorted and "OK" or "FAIL"))
  -- Two calls must return the same table, or the sky boils.
  log("  stable across calls: "
      .. (Sky._starField() == field and "OK" or "FAIL: field is rebuilt"))

  -- ------- the curves
  log("")
  log("=== the night's curves, every 50s ===")
  log("  fireflyCap = round(3 + 15 * starAmount)  (AmbientLife)")
  log("  t      stars  window  lampColor(0..1)        tint(0..1)"
      .. "              fcap")
  for t = 0, C - 1, 50 do
    DayNight.clock = t
    local st = DayNight.starAmount(t)
    local lc = DayNight.lampColor(t)
    local ti = DayNight.tint(true, t)
    log(("  %-5d  %.3f  %.3f   %.3f %.3f %.3f    %.3f %.3f %.3f    %2d")
        :format(t, st, DayNight.windowLight(t), lc[1], lc[2], lc[3],
                ti[1], ti[2], ti[3], math.floor(3 + 15 * st + 0.5)))
  end

  -- The dark must be dark and the day must be untouched: this change is
  -- allowed to move the night and nothing else.
  log("")
  local noon = DayNight.tint(true, 300)
  local mid = DayNight.tint(true, 900)
  log(("  noon  tint %.4f %.4f %.4f  (must stay 1,1,1)")
      :format(noon[1], noon[2], noon[3]))
  if math.abs(noon[1] - 1) > 1e-6 or math.abs(noon[2] - 1) > 1e-6
     or math.abs(noon[3] - 1) > 1e-6 then
    log("  FAIL: noon is no longer neutral -- the day was collateral")
  end
  log(("  night tint %.4f %.4f %.4f  (was 0.4706 0.5333 0.7529)")
      :format(mid[1], mid[2], mid[3]))
  log(("  the night now passes %.1f%% of the light the old one did")
      :format((mid[1] + mid[2] + mid[3]) / (0.4706 + 0.5333 + 0.7529) * 100))
  -- Stars at noon would be the whole thing broken, and stars under a
  -- downpour were the one rule they were given.
  if DayNight.starAmount(300) > 0 then
    log("  FAIL: there are stars out at noon")
  else
    log("  stars at noon: none  OK")
  end
  DayNight.overcast = 1
  local wet = DayNight.starAmount(900)
  DayNight.overcast = 0
  log(("  stars at midnight under full overcast: %.3f  %s")
      :format(wet, wet < 0.001 and "OK" or "FAIL: a rain front has stars"))

  -- ------- what it costs
  --
  -- Locked clock, one map, one rung, no weather. Each phase is the same
  -- number of frames; what is measured is how long they took.
  Pipelines.setLevel("terrarium_voxel", 4)
  wait(120)

  local realCount = Quality.starCount
  local function starsOff() Quality.starCount = function() return 0 end end
  local function starsOn() Quality.starCount = realCount end

  local FRAMES = 240

  -- PER-FRAME SAMPLES AND A MEDIAN, not a block average. The first two
  -- attempts at this measured the block mean and were both thrown out: the
  -- run has multi-hundred-millisecond stalls landing at arbitrary points,
  -- and one of them inside a four-second phase moves its mean by a quarter.
  -- That is not the sky, and averaging cannot tell the difference. The
  -- median is untouched by a handful of stalls, which is the whole reason
  -- lib/Perf.lua reports percentiles rather than an average -- so p95 is
  -- carried alongside, because if the stars DID cost something it would
  -- show up in the tail and not only in the middle.
  local function phase(label, on)
    if on then starsOn() else starsOff() end
    -- re-pin every frame: DayNight.update advances a running cycle and a
    -- drifting clock would fade the stars out mid-measurement
    for _ = 1, 40 do DayNight.clock = 900; coroutine.yield() end
    local s = {}
    local prev = love.timer.getTime()
    for i = 1, FRAMES do
      DayNight.clock = 900
      coroutine.yield()
      local now2 = love.timer.getTime()
      s[i] = (now2 - prev) * 1000
      prev = now2
    end
    local sum = 0
    for i = 1, FRAMES do sum = sum + s[i] end
    table.sort(s)
    local p50 = s[math.floor(FRAMES * 0.50)]
    local p95 = s[math.floor(FRAMES * 0.95)]
    log(("  %-12s p50 %6.3f  p95 %6.3f  mean %6.3f  worst %7.3f ms")
        :format(label, p50, p95, sum / FRAMES, s[FRAMES]))
    return p50, p95
  end

  log("")
  log("=== cost: palindrome OFF-ON-ON-OFF, midnight, rung 4 ===")
  -- A DISCARDED phase first. The palindrome cancels a LINEAR drift between
  -- its two halves; it cannot cancel a warm-up that lands entirely inside
  -- phase 1. The first attempt at this measured 21.8ms for phase 1 and
  -- 16.7ms for phase 4 -- the same code, 23% apart -- which dragged the OFF
  -- average up above both ON phases and read as the stars making the frame
  -- FASTER. So the warm-up is spent here, on a result nobody looks at, and
  -- the four phases that count all start from a hot process.
  -- HOW LONG THE WARM-UP HAS TO BE, measured rather than guessed. Across
  -- three runs the phase medians came out 23.7, 22.3, 17.2, 16.7, 16.7 --
  -- a monotone settle of about twenty seconds, not a spike. A 240-frame
  -- warm-up left phase 1 still on the slope and the palindrome unreadable
  -- twice. So the process is spun for roughly that whole settle here, on
  -- frames nobody measures, and only then are the four phases taken.
  starsOn()
  for _ = 1, 900 do DayNight.clock = 900; coroutine.yield() end
  phase("0 warm-up  ", true)
  log("  (discarded -- see above)")
  local a, a95 = phase("1 stars OFF", false)
  local b, b95 = phase("2 stars ON", true)
  local c, c95 = phase("3 stars ON", true)
  local d, d95 = phase("4 stars OFF", false)
  local off, on = (a + d) / 2, (b + c) / 2
  local off95, on95 = (a95 + d95) / 2, (b95 + c95) / 2
  log("")
  log(("  p50: OFF %.3f  ON %.3f  delta %+.3f ms (%+.1f%%)")
      :format(off, on, on - off, (on / off - 1) * 100))
  log(("  p95: OFF %.3f  ON %.3f  delta %+.3f ms (%+.1f%%)")
      :format(off95, on95, on95 - off95, (on95 / off95 - 1) * 100))
  -- The palindrome is only readable if its two OFF halves agree: a large
  -- spread between them means the run's own drift is still bigger than the
  -- thing being measured, and the delta above is noise wearing a number.
  local spread = math.abs(d - a) / math.min(a, d) * 100
  log(("  OFF-to-OFF p50 spread %.1f%% -- the delta above is %s")
      :format(spread, spread < 5 and "READABLE"
              or "NOT READABLE, drift still dominates"))
  if spread < 5 and on - off > 1.0 then
    log("  FAIL: the sky costs more than a millisecond at the median")
  end
  if on - off > 1.5 then
    log("  FAIL: the sky costs more than a millisecond and a half")
  end
  starsOn()

  -- ------- the pair, which is the only honest look at "is it visible"
  local function shot(name)
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
    wait(3)
  end
  local function hold(t, frames)
    for _ = 1, frames do DayNight.clock = t; coroutine.yield() end
    DayNight.clock = t
  end

  log("")
  log("=== shots: same clock, same rung, stars off then on ===")
  for _, t in ipairs({ 660, 900, 1120 }) do
    hold(t, 40)
    starsOff(); hold(t, 6); shot(("%04d_a_nostars.png"):format(t))
    starsOn();  hold(t, 6); shot(("%04d_b_stars.png"):format(t))
    log(("  t=%d  starAmount=%.3f  glassNight=%.3f  lamp=%.2f %.2f %.2f")
        :format(t, DayNight.starAmount(t), Voxel3D.glassNight or 0,
                (Voxel3D.lampColor or {})[1] or 0,
                (Voxel3D.lampColor or {})[2] or 0,
                (Voxel3D.lampColor or {})[3] or 0))
  end

  log("")
  log("done -- " .. OUT)
  logf:close()
  love.event.quit()
end
