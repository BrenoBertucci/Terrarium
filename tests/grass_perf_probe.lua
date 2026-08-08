-- Probe: what the grass physics actually COSTS, and whether the tiers help.
--
-- The grass pass is the heaviest vertex work in the mod and it is the one
-- cost on the Quality page that does NOT shrink with RES: the canvas gets
-- smaller, the tuft count does not. So this measures frame time with the
-- physics forced to each tier, at a fixed RES, on a real meadow.
--
-- ------- the shape of the measurement, and why it is not A-then-B
--
-- Variance between the first and last phase of one run is enormous on this
-- engine -- an unchanged build has measured 134 and 98 frames for the same
-- walk. Running HIGH then LOW charges the second phase for the first one's
-- warm-up and invents an improvement that is not there. So the phases are a
-- PALINDROME -- HIGH, LOW, LOW, HIGH -- and each tier's number is the mean
-- of its two halves, which cancels any monotonic drift across the run.
--
-- The tier is forced by replacing Quality.grassDetail and Quality.crushSlots
-- rather than by moving the RES row: moving RES would change the canvas
-- size, and then the thing measured is the canvas and not the physics.
--
--   POKEPORT_VERSION=yellow \
--   DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/grass_perf_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/grass_perf_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

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

  local Quality = lib.require("Quality")
  local Wind = lib.require("Wind")
  local WindFX = lib.require("WindFX")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Grass3D = lib.require("Grass3D")
  local Pipelines = require("src.render.Pipelines")

  DayNight.setting:sync("day")
  Weather.setting:sync("off")
  Wind.setting:sync(4)                 -- GALE: worst case for both systems
  Pipelines.setLevel("terrarium_voxel", 4)
  -- RES held at the rung this is about. Everything below changes the
  -- physics tier and nothing else.
  Quality.setting:sync(2)              -- 1/2, the default rung

  -- Stand in a real meadow: find the longest run of grass cells the same
  -- way the physics probe does, so this is measured over tufts and not
  -- over paving.
  game.overworld:setMap("ROUTE_1", 10, 24, "down")
  wait(60)
  do
    local map = game.overworld.map
    local bx, by, bn = nil, nil, 0
    if map and map.isGrassCell and map.inBounds then
      for cx = 2, 18 do
        local run, top = 0, nil
        for cy = 2, 34 do
          if map:inBounds(cx, cy) and map:isGrassCell(cx, cy) then
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
    if bx and bn >= 3 then game.overworld:setMap("ROUTE_1", bx, by, "down") end
  end
  wait(120)

  -- ------- forcing a tier
  local realDetail, realSlots = Quality.grassDetail, Quality.crushSlots
  local forced = 2
  Quality.grassDetail = function() return forced end
  Quality.crushSlots = function()
    if forced <= 0 then return 3 end
    if forced == 1 then return 5 end
    return 8
  end

  -- One phase: walk south through the meadow for `n` frames with the wind
  -- at gale, and report the mean frame time. Walking matters -- it is what
  -- fills the crush slots and lays the trail, which is the state the loop
  -- is expensive in.
  -- ------- MEDIAN, not mean, and the first run is why
  --
  -- The first cut of this reported means and came back with 54.88 ms
  -- against 24.47 ms for the SAME tier -- a thirty-millisecond spread
  -- around a two-millisecond effect. The cause is in the same log: single
  -- frames of 437 ms and 396 ms. Those are the engine meshing chunks and
  -- redrawing the sun's map, not the grass shader, and one of them drags a
  -- 150-frame mean by three milliseconds all on its own.
  --
  -- A median cannot be moved by an outlier at all, which is exactly the
  -- property wanted: the question is what a TYPICAL frame costs, and a
  -- hitch is a different question with a different answer. p90 is reported
  -- beside it so the hitches are still visible rather than hidden.
  local function stats(t)
    table.sort(t)
    local n = #t
    if n == 0 then return 0, 0, 0 end
    local med = t[math.floor(n / 2) + 1]
    local p90 = t[math.max(1, math.floor(n * 0.9))]
    return med * 1000, p90 * 1000, t[n] * 1000
  end

  -- `windOff` is the honest baseline: no sway uniform, no WindFX at all.
  -- Comparing tiers only ever answers "is tier 2 dearer than tier 0"; this
  -- answers the question actually asked, which is what the whole feature
  -- costs against not having it.
  local function phase(tier, windRow, n)
    forced = tier
    Wind.setting:sync(windRow)
    Grass3D.clearTracks()
    -- Settle hard. A tier change swaps a uniform, a wind row change empties
    -- the streak field, and walking into unmeshed ground is the 400 ms
    -- frame. Two hundred frames of the same walk first, all discarded.
    for _ = 1, 200 do
      game.input.state.down = true
      coroutine.yield()
    end
    local samples = {}
    for _ = 1, n do
      game.input.state.down = true
      local a = love.timer.getTime()
      coroutine.yield()
      samples[#samples + 1] = love.timer.getTime() - a
    end
    game.input.state.down = false
    local med, p90, worst = stats(samples)
    return med, p90, worst, WindFX.count()
  end

  local N = 200
  log(("--- palindrome: FULL, OFF, OFF, FULL (%d frames each, after 200 "
       .. "discarded)"):format(N))
  local a2, a2p, a2w, a2s = phase(2, 4, N)   -- tier 2, WIND GALE
  local a0, a0p, a0w, a0s = phase(0, 0, N)   -- physics off, WIND OFF
  local b0, b0p, b0w = phase(0, 0, N)
  local b2, b2p, b2w = phase(2, 4, N)

  local hi = (a2 + b2) / 2
  local lo = (a0 + b0) / 2
  log(("FULL physics + gale : median %.2f / %.2f ms  p90 %.1f / %.1f  worst %.0f / %.0f  streaks %d")
        :format(a2, b2, a2p, b2p, a2w, b2w, a2s))
  log(("WIND OFF (baseline) : median %.2f / %.2f ms  p90 %.1f / %.1f  worst %.0f / %.0f  streaks %d")
        :format(a0, b0, a0p, b0p, a0w, b0w, a0s))
  log(("median FULL=%.2f ms  OFF=%.2f ms  delta=%.2f ms (%.1f%%)")
        :format(hi, lo, hi - lo, (hi - lo) / math.max(hi, 0.001) * 100))
  -- The two halves of ONE condition are the noise floor. A delta smaller
  -- than that is not a measurement, and saying so is the whole point of
  -- running the phases as a palindrome.
  local noise = math.max(math.abs(a2 - b2), math.abs(a0 - b0))
  log(("noise floor (within-condition spread): %.2f ms"):format(noise))
  if hi - lo > noise then
    log(("MEASURED: the wind and grass cost %.2f ms of a %.2f ms frame")
          :format(hi - lo, hi))
  else
    log("INCONCLUSIVE: the whole feature is inside the noise at this rung. "
        .. "Whatever is making frames heavy, it is not this -- look at the "
        .. "p90 and worst columns, which are chunk meshing and the sun pass.")
  end

  Quality.grassDetail, Quality.crushSlots = realDetail, realSlots
  wait(10)
  logf:close()
  love.event.quit()
end
