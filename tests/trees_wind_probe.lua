-- Does the canopy actually MOVE, and does rain change how?
--
-- The thing being tested is a displacement in the vertex stage gated on
-- `sway` and multiplied by vCanopy. Three ways it can be wrong and still
-- look finished, which is why this measures pixels rather than asserting
-- uniforms:
--
--   1. THE SHADER DID NOT COMPILE. Voxel3D fails SILENTLY -- the engine
--      keeps the flat 2D renderer, every assert below still passes, and
--      the screenshots look like the feature was never written. So the
--      first thing logged is shader() + shaderError, every time.
--   2. `sway` reached the draw but the branch never ran. packedShade
--      gates the tree path, and it is set per draw; miss it and the
--      forest takes the GRASS curve off vertex_position.y instead --
--      which also moves, so a screenshot showing motion proves nothing
--      on its own.
--   3. grassLoad was inherited as zero. VoxelScene clears it before this
--      pass, so a tree draw that does not re-send it gets wet=0 and the
--      rain tick is silently absent while the wind still rolls.
--
-- HOW MOTION IS MEASURED. Two frames some ticks apart, differenced over
-- the canopy region, and the score is the mean absolute channel delta. A
-- still forest scores ~0. That number alone is not enough -- the clock,
-- the weather fade and the player walking all move pixels too -- so every
-- reading is taken against WIND OFF at the same map, same camera, same
-- hour, and it is the RATIO that is the result.
--
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/trees_wind_probe.lua
--   DS_PROBE_DIR=<absolute scratch dir>
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/trees_wind_probe.log", "w"))
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
  local Voxel3D  = lib.require("Voxel3D")
  local Trees3D  = lib.require("Trees3D")
  local DayNight = lib.require("DayNight")
  local Weather  = lib.require("Weather")
  local Wind     = lib.require("Wind")

  local sh = Voxel3D.shader()
  log("voxel shader:", sh and "PASS" or "FAIL", tostring(Voxel3D.shaderError))
  if not sh then
    log("FAIL: no shader -- everything below is the 2D renderer")
  end
  log("bake:", Trees3D.available() and "PASS" or "FAIL",
      "| WIND_SHARE =", Trees3D.WIND_SHARE)

  -- Poll the build rather than counting frames at it (see trees_probe).
  local function settle(label)
    local ticks = 0
    while ticks < 4000 do
      local map = game.overworld and game.overworld.map
      local done, state = Trees3D.ready(map)
      if Voxel3D.lampLights ~= nil and (done or state == "hulls") then
        local owed = select(2, Trees3D.buildsInFlight())
        if owed == 0 or ticks > 1200 then
          log(string.format("settle %s: %s in %d ticks", label, state, ticks))
          return
        end
      end
      coroutine.yield(); ticks = ticks + 1
    end
    log("FAIL: settle " .. label .. " timed out")
  end

  -- ---- capture a frame into a table of bytes
  local function grab()
    local shot = nil
    love.graphics.captureScreenshot(function(d) shot = d end)
    wait(3)
    return shot
  end

  -- Mean absolute per-channel difference over a window, on the two shots.
  -- The window is the upper-middle of the frame: canopy rather than the
  -- HUD strip at the bottom or the sky at the very top.
  local function motion(a, b)
    if not (a and b) then return -1 end
    local w, h = a:getWidth(), a:getHeight()
    local x0, x1 = math.floor(w * 0.10), math.floor(w * 0.90)
    local y0, y1 = math.floor(h * 0.12), math.floor(h * 0.62)
    local sum, cnt = 0, 0
    -- every 3rd pixel: 40k samples is plenty for a mean and keeps the
    -- probe from spending a minute per reading in interpreted Lua
    for y = y0, y1, 3 do
      for x = x0, x1, 3 do
        local r1, g1, b1 = a:getPixel(x, y)
        local r2, g2, b2 = b:getPixel(x, y)
        sum = sum + math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2)
        cnt = cnt + 3
      end
    end
    if cnt == 0 then return -1 end
    return sum / cnt * 255
  end

  -- One reading: two frames GAP ticks apart, differenced.
  --
  -- GAP IS SMALL ON PURPOSE, AND THE FIRST RUN LEARNED WHY. At 14 ticks
  -- the canopy has moved further than the leaf texture's own correlation
  -- length, so the two frames are simply UNRELATED over the crowns and the
  -- score pins at whatever fraction of the window is canopy. Measured:
  -- rain 9.94 and gale+rain 9.82, with the amplitude behind them nearly
  -- doubled (Wind.amount 1.82 -> 3.23). The metric was saturated and read
  -- as "the amplitude does nothing", which is the most expensive kind of
  -- wrong -- a FAIL line pointing at working code.
  --
  -- A few ticks keeps the difference in its linear range, where twice the
  -- displacement really does move twice the pixels.
  local GAP = 3

  -- THE PLAYER WALKS ON ITS OWN AFTER setMap, and a walking camera moves
  -- every pixel in the frame. The WIND OFF floor came back
  -- [1.05 .. 26.19] across three samples of what was supposed to be a
  -- still forest -- one sample with the camera parked, two with it
  -- sliding -- and the median landed on the sliding pair and declared the
  -- feature dead. The reading was not noisy, it was measuring the camera.
  --
  -- So every sample is fenced: note where the player stands, take the
  -- pair, and throw the sample away if it moved. A rejected sample is not
  -- a failure to report around -- it is a sample of the wrong thing.
  local function playerAt()
    local p = game.overworld and game.overworld.player
    if not p then return "?" end
    return tostring(p.cellX) .. "," .. tostring(p.cellY)
  end

  -- And take the MEDIAN of several. The gust envelope is a slow swell in
  -- its own right (the first run caught rain at gust 0.271 and the gale at
  -- 0.005, purely from when each sample landed), so a single reading of
  -- any state is a reading of that state at one arbitrary moment of the
  -- squall.
  local function reading()
    local out, tries = {}, 0
    while #out < 3 and tries < 12 do
      tries = tries + 1
      local where = playerAt()
      local a = grab()
      wait(GAP)
      local b = grab()
      if playerAt() == where then
        out[#out + 1] = motion(a, b)
      end
      wait(9)                     -- decorrelate the samples from each other
    end
    if #out == 0 then return -1, { -1 }, tries end
    table.sort(out)
    return out[math.ceil(#out / 2)], out, tries
  end

  -- ---- the stage: a forested route, a fixed hour, no weather
  DayNight.setting:sync("day")
  pcall(function() game.overworld:setMap("ROUTE_2", 10, 10, "up") end)
  settle("ROUTE_2")
  Weather.setting:sync("off")
  wait(900)                       -- CLEAR_FADE is 14s; do not sample into it
  log("weather =", tostring(Weather.setting:get()))

  local function shot(name)
    love.graphics.captureScreenshot(function(d)
      local f = io.open(OUT .. "/" .. name .. ".png", "wb")
      if f then f:write(d:encode("png"):getString()); f:close() end
    end)
    wait(8)
  end

  -- Wind.setting's VALUES are numbers (1 AUTO / 2 BREEZE / 4 GALE / 0 OFF);
  -- the words are only labels, and ModSetting.indexOf falls back to index 1
  -- for anything it does not find -- so sync("BREEZE") silently selects
  -- AUTO and the probe reports on a setting it never set.
  local WIND_OFF, WIND_BREEZE, WIND_GALE = 0, 2, 4

  -- ---- 1. WIND OFF: the floor. Whatever this reads is what moves in this
  -- frame for reasons that are not the canopy (the clock, the player, the
  -- sky), and every number below has to clear it to mean anything.
  Wind.setting:sync(WIND_OFF)
  wait(120)
  log("wind setting =", tostring(Wind.setting:get()),
      "| amount =", string.format("%.3f", Wind.amount()))
  log(Wind.amount() == 0 and "PASS: WIND OFF really is zero at the source"
                          or "FAIL: WIND OFF still reports a nonzero amount")
  local off, offAll = reading()
  shot("wind_off")

  -- ---- 2. BREEZE, dry
  Wind.setting:sync(WIND_BREEZE)
  wait(240)
  local dryAmount = Wind.amount()
  local dry, dryAll = reading()
  shot("wind_breeze")

  -- ---- 3. RAIN. Weather.BUILD is 20 SECONDS to peak -- sampling a few
  -- frames in would shoot a drizzle and conclude the feature is subtle.
  Weather.setting:sync("rain")
  wait(1500)
  local wet, snow, gust = Wind.load()
  local rainAmount = Wind.amount()
  log(string.format("rain: kind=%s wet=%.3f snow=%.3f gust=%.3f amount=%.3f",
                    tostring(Weather.setting:get()), wet, snow, gust,
                    rainAmount))
  -- THE RAIN TICK IS ONLY IN THE SHADER IF wet REACHED IT. VoxelScene
  -- clears grassLoad before the tree pass, so a zero here means the tree
  -- draw never re-sent it and the whole rain half of this is absent.
  log(wet > 0.05 and "PASS: rain is on the load channel"
                  or "FAIL: wet=0 at the draw -- grassLoad was not re-sent")
  local rain, rainAll = reading()
  shot("wind_rain")

  -- ---- 4. STORM.
  --
  -- There is no "storm" weather kind to select, and that is the point
  -- rather than an obstacle: Weather.storming() is RAIN whose power is
  -- over STRIKE_ABOVE. A storm in this world is already the same weather
  -- with more in it, so the tree response gets to be the same curve with
  -- more in it for free -- no second system, nothing to keep in step.
  --
  -- Driving that through the WIND ROW tested the wrong module, and slowly.
  -- Wind.amount() returns the SMOOTHED climate (Wind.liveAmount), so the
  -- row's amplification arrives over seconds, not on the frame the setting
  -- changes: two runs sampled 400 ticks after switching to GALE and read
  -- 2.475 and 2.689 against BREEZE's 2.662 and 2.210 -- once lower, once
  -- barely higher, and neither a fact about the canopy. Left long enough
  -- it does amplify properly (3.897 against 1.767 in the same shower).
  --
  -- Either way that is Wind's settling time, not this feature's response.
  --
  -- What belongs HERE is narrower, and it is exactly what a storm does to
  -- this code: more amplitude arriving at the same curve. WIND_SHARE moves
  -- that one number -- same wave, same bearing, same clock, same rain,
  -- twice the reach -- so if the motion does not follow it, the amplitude
  -- is not riding `sway` and a storm never will either.
  -- SCALED DOWN, NOT UP, and the first attempt is why. Doubling the share
  -- to 4.4 put ~15 px of reach on a crown of radius ~15: the canopies smear
  -- into each other and stop being individual trees (see wind_storm.png
  -- from that run -- the foreground is a green blob). Two things came out
  -- of it, and neither was the thing being tested. The look breaks well
  -- before that, which is the ceiling WIND_SHARE's comment claims. And the
  -- METRIC INVERTS: overlapping smeared crowns differ LESS between frames
  -- than crisp separated ones, so more amplitude scored lower and the
  -- probe printed FAIL at a feature that was working too hard.
  --
  -- Halving cannot leave the sane range, and monotonic-down proves exactly
  -- the same thing monotonic-up would.
  local keepShare = Trees3D.WIND_SHARE
  Trees3D.WIND_SHARE = keepShare * 0.5
  wait(120)
  local swet, ssnow, sgust = Wind.load()
  local stormAmount = Wind.amount()
  log(string.format("rain at HALF share: wet=%.3f gust=%.3f amount=%.3f "
                    .. "share=%.2f storming=%s",
                    swet, sgust, stormAmount, Trees3D.WIND_SHARE,
                    tostring(Weather.storming())))
  local storm, stormAll = reading()
  shot("wind_halfshare")
  Trees3D.WIND_SHARE = keepShare

  -- and what the wind row did, logged as information rather than a verdict
  Wind.setting:sync(WIND_GALE)
  wait(400)
  log(string.format("for the record: WIND=GALE under the same rain reports "
                    .. "amount=%.3f (BREEZE reported %.3f)",
                    Wind.amount(), rainAmount))

  Weather.setting:sync("off")
  Wind.setting:sync(1)            -- AUTO

  -- ---- the verdicts, each against the floor
  -- n is the number of samples that SURVIVED the still-camera fence. A low
  -- n on a state means the player was walking through most of it and that
  -- state's number rests on very little.
  local function spread(t)
    return string.format("%.2f..%.2f n=%d", t[1], t[#t], #t)
  end
  log(string.format("MOTION (GAP=%d, still-camera samples only)", GAP))
  log(string.format("  wind off    %7.3f  [%s]", off, spread(offAll)))
  log(string.format("  breeze      %7.3f  [%s]", dry, spread(dryAll)))
  log(string.format("  + rain      %7.3f  [%s]", rain, spread(rainAll)))
  log(string.format("  rain, half  %7.3f  [%s]", storm, spread(stormAll)))
  log(string.format("wind amount: breeze %.3f | rain %.3f",
                    dryAmount, rainAmount))

  log(dry > off * 1.5 + 0.05
      and "PASS: the canopy moves under wind (breeze clears the still floor)"
      or "FAIL: breeze is indistinguishable from WIND OFF -- the vertex "
         .. "branch is not running")
  log(rain > dry
      and "PASS: rain moves the canopy more than dry breeze"
      or "FAIL: rain did not add motion over a dry breeze")
  log(storm < rain
      and "PASS: half the reach moves half as much canopy -- the amplitude "
          .. "rides sway, so a storm is this curve with more in it rather "
          .. "than a second curve"
      or "FAIL: halving the reach changed nothing -- the amplitude is not "
         .. "riding sway")
  log(rainAmount > dryAmount
      and "PASS: the shower's drive reaches the canopy through Wind.amount "
          .. "(one system, and Weather already folds the storm into it)"
      or "WARN: Wind.amount did not rise under rain")

  -- ---- WHAT THE CANOPY WIND COSTS
  --
  -- One harmonic (two under rain) on ~940k vertices, in a scene pass
  -- already measured at 22 ms. That is a claim about a frame, so price it.
  --
  -- WIND_SHARE = 0 is the clean isolation and the reason the share exists
  -- as a number rather than a constant in the shader: it makes `sway` zero
  -- for the TREE draw only, so the branch is skipped while the grass, the
  -- weather, the clock and every other pass stay exactly as they were.
  -- Turning WIND off instead would stop the meadow too and price the wrong
  -- thing.
  Weather.setting:sync("off")
  Wind.setting:sync(WIND_BREEZE)
  wait(900)

  local SAMPLES, FRAMES, SETTLE = 3, 100, 40
  local function medianCost()
    local ms = {}
    for i = 1, SAMPLES do
      wait(SETTLE)
      local t0 = love.timer.getTime()
      for _ = 1, FRAMES do coroutine.yield() end
      ms[i] = (love.timer.getTime() - t0) / FRAMES * 1000
    end
    table.sort(ms)
    return ms[math.ceil(SAMPLES / 2)], ms
  end
  local function priced(label)
    local med, ms = medianCost()
    log(string.format("  %-14s %6.2f ms (min %6.2f, max %6.2f, spread %3.0f%%)",
                      label, med, ms[1], ms[SAMPLES],
                      (ms[SAMPLES] / math.max(ms[1], 1e-6) - 1) * 100))
    return med, (ms[SAMPLES] / math.max(ms[1], 1e-6) - 1) * 100
  end

  local keepShare = Trees3D.WIND_SHARE
  log("canopy wind cost, ROUTE_2 clear sky:")
  Trees3D.WIND_SHARE = 0
  local msStill, spStill = priced("branch off")
  Trees3D.WIND_SHARE = keepShare
  local msWind, spWind = priced("canopy wind")
  Trees3D.WIND_SHARE = 0
  local msStill2 = priced("branch off (2)")
  Trees3D.WIND_SHARE = keepShare

  local drift = math.abs(msStill2 - msStill)
  local cost = msWind - (msStill + msStill2) * 0.5
  log(string.format("  canopy wind costs %+.2f ms, drift %.2f ms, "
                    .. "worst spread %.0f%%", cost, drift,
                    math.max(spStill, spWind)))
  -- Same rule the shadow-card reading had to learn: a delta out of a run
  -- whose spread is wider than the delta is not a small measurement.
  if math.max(spStill, spWind) > 15 then
    log("INCONCLUSIVE: this run is too noisy to price the branch -- rerun")
  elseif cost > drift then
    log(string.format("MEASURED: the canopy wind costs %+.2f ms/frame", cost))
  else
    log("PASS: the canopy wind is inside the run's drift -- free at this size")
  end

  log("done")
  logf:close()
  wait(10)
  love.event.quit()
end
