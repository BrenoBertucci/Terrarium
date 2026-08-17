-- Does the wood keep raining after the sky stops, and does the rain look
-- like rain?
--
-- Two things at once, because they need the same three-minute setup.
--
-- THE DRIP is unmeasurable by screenshot: a handful of 2px specks falling
-- for a second and a half, minutes after a shower. A picture of a wood
-- agrees with itself whether or not anything is dripping. So this counts
-- the motes, and checks WHERE they are -- near the player, and on cells
-- the canopy field says are under a crown. A drip raining in open ground
-- is the same count and the wrong feature.
--
-- THE LOOK is the opposite: it is only judgeable as pixels, so the run
-- ends in shots taken at a fixed hour with the weather at a known power.
-- What changed is that a streak is now a tapered needle instead of a
-- square-ended bar, and a splash is a ring instead of a plus sign.
--
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/trees_drip_probe.lua
--   DS_PROBE_DIR=<absolute scratch dir>
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/trees_drip_probe.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring((select(i, ...))) end
    logf:write(table.concat(p, " ") .. "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b
    coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: never booted"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end

  local lib = game.mods.exports.TERRARIUM.lib
  local Voxel3D   = lib.require("Voxel3D")
  local Trees3D   = lib.require("Trees3D")
  local Weather   = lib.require("Weather")
  local Wind      = lib.require("Wind")
  local GrassWear = lib.require("GrassWear")
  local DayNight  = lib.require("DayNight")

  log("voxel shader:", Voxel3D.shader() and "PASS" or "FAIL",
      tostring(Voxel3D.shaderError))
  log("bake:", Trees3D.available() and "PASS" or "FAIL")
  log(string.format("drip knobs: reach=%d cover=%.2f max=%d rate=%.1f h=%d",
                    Weather.DRIP_REACH, Weather.DRIP_COVER, Weather.DRIP_MAX,
                    Weather.DRIP_RATE, Weather.DRIP_HEIGHT))

  local function settle(label)
    local ticks = 0
    while ticks < 4000 do
      local map = game.overworld and game.overworld.map
      local done, state = Trees3D.ready(map)
      if Voxel3D.lampLights ~= nil and (done or state == "hulls") then
        if select(2, Trees3D.buildsInFlight()) == 0 or ticks > 1200 then
          log(string.format("settle %s: %s in %d ticks", label, state, ticks))
          return
        end
      end
      coroutine.yield(); ticks = ticks + 1
    end
    log("FAIL: settle " .. label .. " timed out")
  end

  local function shot(name)
    love.graphics.captureScreenshot(function(d)
      local f = io.open(OUT .. "/" .. name .. ".png", "wb")
      if f then f:write(d:encode("png"):getString()); f:close() end
    end)
    wait(8)
  end

  DayNight.setting:sync("day")
  Weather.setting:sync("off")
  pcall(function() game.overworld:setMap("ROUTE_2", 10, 10, "up") end)
  settle("ROUTE_2")
  wait(600)

  -- ---- 1. THE SHOWER, and what it looks like now.
  --
  -- Weather.BUILD is 20 s to peak; shooting earlier photographs a drizzle
  -- and judges the streak shape on four drops.
  Weather.setting:sync("rain")
  wait(1500)
  log(string.format("rain: power %.2f | visible %s | wind %.2f",
                    Weather.power(), tostring(Weather.visible()),
                    Wind.amount()))
  log("shafts+drops alive =", Weather.moteCount())
  shot("drip_rain")

  -- and a gale, where the LEAN is the thing to look at: the old shafts
  -- stood upright in any wind because the slant was half a pixel.
  Wind.setting:sync(4)                      -- GALE
  wait(900)
  log(string.format("gale: wind %.2f", Wind.amount()))
  shot("drip_rain_gale")
  Wind.setting:sync(2)                      -- BREEZE
  wait(300)

  -- ---- 2. STOP THE RAIN AND WATCH THE WOOD.
  --
  -- afterRain is armed when the shower ends and decays over AFTER_RAIN
  -- (180 s). The drips ride that, so the count should be healthy right
  -- after the stop and thinning much later.
  -- POLL THE WINDOW OPEN, do not count frames at it. The first run waited
  -- a flat 240 ticks here and sampled a dead field: `afterRain` is armed
  -- only once the shower has finished FADING (CLEAR_FADE is 14 seconds and
  -- the arm fires when power reaches zero), so four seconds after the
  -- switch there is nothing to see yet -- and the whole 40-sample window
  -- ran and closed before the feature had started. It reported
  -- "FAIL: nothing dripped" about working code.
  Weather.setting:sync("off")
  local opened = 0
  while opened < 2400 do
    if Weather.afterRain() > 0 then break end
    coroutine.yield(); opened = opened + 1
  end
  log(string.format("after the stop: afterRain %.2f | visible %s | "
                    .. "window opened after %d ticks",
                    Weather.afterRain(), tostring(Weather.visible()), opened))
  log(Weather.afterRain() > 0
      and "PASS: the after-rain window armed"
      or "FAIL: afterRain never armed -- nothing below can be measured")

  -- sample the live drip count over a while, and where they are
  local peak, samples, offCanopy, far, seen = 0, 0, 0, 0, 0
  local p = game.overworld.player
  for s = 1, 40 do
    local list = {}
    local live = Weather.moteCount("drip", list)
    if live > peak then peak = live end
    samples = samples + live
    for i = 1, #list do
      seen = seen + 1
      local cx = math.floor(list[i].x / 16)
      local cy = math.floor(list[i].z / 16)
      if GrassWear.canopyAt(cx, cy) < Weather.DRIP_COVER then
        offCanopy = offCanopy + 1
      end
      local dx = math.abs(cx - p.cellX)
      local dy = math.abs(cy - p.cellY)
      if dx > Weather.DRIP_REACH or dy > Weather.DRIP_REACH then
        far = far + 1
      end
    end
    wait(12)
  end
  log(string.format("drips: peak %d | mean %.1f | sampled %d positions",
                    peak, samples / 40, seen))
  -- "More than zero" is not the bar. A drip lives about a quarter of a
  -- second (it falls DRIP_HEIGHT and lands), so a peak of three means a
  -- wood with three drops in it -- true, passing, and invisible. The
  -- feature is a wood that reads as dripping.
  log(peak >= 6
      and "PASS: the wood reads as dripping (peak " .. peak .. " at once)"
      or (peak > 0
          and "FAIL: only " .. peak .. " drips alive at once -- correct but "
              .. "too sparse to see; DRIP_RATE is attempts, not drips"
          or "FAIL: nothing dripped in the after-rain window"))
  log(peak <= Weather.DRIP_MAX
      and "PASS: the live count stayed inside DRIP_MAX"
      or "FAIL: the budget leaked -- " .. peak .. " alive")
  -- These two are checks on WHERE the drips were, so with no drips they
  -- have nothing to say -- and the first run printed both as PASS over an
  -- empty set, next to the FAIL saying there were none. A check that
  -- passes when the thing it checks does not exist is worse than no check.
  if seen == 0 then
    log("SKIP: no drips seen, so their placement is unmeasured")
  else
    log(offCanopy == 0
        and "PASS: every drip fell from a cell under a crown"
        or "FAIL: " .. offCanopy .. " of " .. seen
           .. " drips fell in the open -- it is not reading the canopy field")
    log(far == 0
        and "PASS: every drip was inside DRIP_REACH of the player"
        or "FAIL: " .. far .. " drips spawned outside the reach")
  end
  shot("drip_after")

  -- ---- 3. AND IT HAS TO STOP.
  --
  -- A drip that outlives its window is worse than one that never starts:
  -- it is a wood raining on a clear afternoon, forever, and nothing on
  -- screen explains it.
  Weather.armAfterRain(0.01)
  wait(240)
  local late = Weather.moteCount("drip")
  log(string.format("after the window closes: afterRain %.3f | drips %d",
                    Weather.afterRain(), late))
  log(late == 0 and "PASS: the dripping stops with its window"
                 or "FAIL: " .. late .. " drips outlived afterRain")

  -- ---- 4. WHAT THE NEW RAIN COSTS
  --
  -- The shaft count went up 70% when the field became one mesh instead of
  -- a draw call per drop, on the argument that the draw calls were what
  -- had been rationing it. That is an argument until it is a number, and
  -- this hardware has already produced one run where the noise was wider
  -- than the effect -- so: medians, with the spread quoted, and a repeat
  -- of the first state at the end to catch drift.
  Weather.setting:sync("off")
  local off1 = 0
  while off1 < 2400 and Weather.power() > 0.01 do
    coroutine.yield(); off1 = off1 + 1
  end
  wait(300)

  local SAMPLES, FRAMES = 3, 100
  local function medianCost()
    local ms = {}
    for i = 1, SAMPLES do
      wait(40)
      local t0 = love.timer.getTime()
      for _ = 1, FRAMES do coroutine.yield() end
      ms[i] = (love.timer.getTime() - t0) / FRAMES * 1000
    end
    table.sort(ms)
    return ms[math.ceil(SAMPLES / 2)], ms
  end
  local function priced(label)
    local med, ms = medianCost()
    local spread = (ms[SAMPLES] / math.max(ms[1], 1e-6) - 1) * 100
    log(string.format("  %-12s %6.2f ms (min %6.2f, max %6.2f, spread %3.0f%%)",
                      label, med, ms[1], ms[SAMPLES], spread))
    return med, spread
  end

  log("rain cost, ROUTE_2:")
  local dry, sDry = priced("no weather")
  Weather.setting:sync("rain")
  wait(1500)
  log(string.format("  (rain power %.2f, %d shafts+motes alive)",
                    Weather.power(), Weather.moteCount()))
  local wet, sWet = priced("raining")
  Weather.setting:sync("off")
  while Weather.power() > 0.01 do coroutine.yield() end
  wait(300)
  local dry2 = priced("no weather (2)")
  local drift = math.abs(dry2 - dry)
  log(string.format("  the shower costs %+.2f ms/frame, drift %.2f ms, "
                    .. "worst spread %.0f%%",
                    wet - (dry + dry2) * 0.5, drift, math.max(sDry, sWet)))
  log(math.max(sDry, sWet) > 15
      and "INCONCLUSIVE: too noisy a run to price the rain -- rerun"
      or "PASS: priced above the run's own noise")

  Wind.setting:sync(1)
  log("done")
  logf:close()
  wait(10)
  love.event.quit()
end
