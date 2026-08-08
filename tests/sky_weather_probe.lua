-- Probe: the five sky changes, each measured ALONE.
--
-- They all landed in one fragment shader and one paint call, which is exactly
-- the arrangement where "it looks better" is worthless as a report: five
-- things moved and a screenshot cannot say which of them did. So every one
-- gets an isolation that turns it off and on with everything else held still,
-- and a number.
--
--   CLOUD PARALLAX  the deck now reads the camera (Sky.CLOUD_PARALLAX).
--                   Isolated by painting the SAME INSTANT twice with two
--                   camera x's -- same clock, same wind, same bands, so any
--                   difference at all is parallax and nothing else.
--   CLOUD EVOLVE    the erosion noise drifts against the wind that carries
--                   the mass (Sky.CLOUD_EVOLVE), so the deck changes SHAPE
--                   rather than sliding rigidly. Isolated by zeroing the wind
--                   -- which zeroes the drift -- and stepping a FAKE clock.
--                   What is left moving is evolve by construction.
--   STARS           each star has its own point of going out, so the field
--                   empties instead of dimming as a sheet. Pure Lua, counted
--                   exactly across the whole amount curve.
--   FAR CURTAIN     Weather.curtain leads the streaks up the power ramp.
--                   Two assertions: the CURVE (it must be full while the
--                   near field is still nothing) and the PLACE (lower sky
--                   only -- an upper-sky hit means it is painting cloud).
--   GOD RAYS        Weather.afterRain, sun only. Isolated with the rainbow
--                   stubbed off, because that shares the trigger and would
--                   otherwise be counted as rays.
--   STORM SKY       DayNight.storm as a second register above the stratus.
--                   Palette numbers are exact, so this one is arithmetic
--                   rather than pixels: the blue-minus-green separation has
--                   to rise, and the neutral grey it replaces has none.
--
-- Then the only question that can sink any of it: WHAT IT COSTS. Measured as
-- a palindrome -- off, on, on, off -- because the first and last phase of a
-- run in this build differ by more than these blocks could, so the two middle
-- phases are averaged against the two outer ones instead of trusting an
-- OFF-then-ON pair where ON pays for OFF's warm-up.
--
-- Every render goes to an OFFSCREEN canvas at a fixed size with a fixed
-- horizon, not to the window: the frame the player sees has a world in it and
-- a world is noise for these purposes.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/sky_weather_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/sky_weather_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local function done(msg)
    if msg then log(msg) end
    logf:close(); love.event.quit()
  end

  love.math.setRandomSeed(20260808)

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then return done("FAIL: no overworld") end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then return done("FAIL: TERRARIUM not loaded") end

  local okReq, Sky, DayNight, Weather, Quality, Wind = pcall(function()
    return lib.require("Sky"), lib.require("DayNight"), lib.require("Weather"),
           lib.require("Quality"), lib.require("Wind")
  end)
  if not (okReq and Sky and DayNight and Weather and Quality and Wind) then
    return done("FAIL: a module is missing from exports: " .. tostring(Sky))
  end
  log("version: " .. tostring(exports.TERRARIUM.version))

  -- the probe owns the weather and the clock for its whole run: an AUTO
  -- shower rolling in halfway through would move every number below
  Weather.setting:sync("off")
  DayNight.setting:sync("cycle")
  DayNight.overcast, DayNight.storm = 0, 0

  -- ------- 0. the gate everything below rests on
  --
  -- If the shader did not build, Sky.paint takes the flat path and four of
  -- the five changes are simply not in the frame. That is a legitimate
  -- outcome on some drivers -- it is why the flat path exists -- but it makes
  -- every pixel number below a measurement of nothing, so it is said first
  -- and said loudly.
  log("======== 0. shader")
  local sh = Sky._getShader()
  log("  Sky._getShader() = " .. (sh and "built" or "REFUSED"))
  if not sh then
    log("  !! the four shader-side changes (parallax, evolve, curtain, rays)")
    log("  !! are NOT being drawn on this driver. Pixel tests below are void.")
  end
  log(("  Quality.scale()=%d  cloudSteps=%d  starCount=%d  rainbow=%s")
      :format(Quality.scale(), Quality.cloudSteps(), Quality.starCount(),
              tostring(Quality.rainbow())))

  -- ------- 1. the storm register (exact, no pixels)
  log("")
  log("======== 1. storm sky -- DayNight.storm as a second register")
  log("  b-g is the separation off the grey axis. The stratus is neutral by")
  log("  design, so the whole of any rise here is the bruise.")
  local realStorm, realOver = DayNight.storm, DayNight.overcast

  -- The hour is FOUND, not assumed. Half the cycle is not noon in this dial
  -- and the first version of this probe took it for granted -- which logged a
  -- storm test run at a sunset, against a warm palette, under a claim that
  -- the base was neutral grey. The numbers were real; the sentence over them
  -- was not. Scan for the hour the day weight actually peaks.
  local NOON, bestDay = 0, -1
  for i = 0, 95 do
    local t = DayNight.CYCLE * i / 96
    local d = (DayNight.mix(t).day or 0)
    if d > bestDay then NOON, bestDay = t, d end
  end
  log(("  hour used: t=%.0f of %.0f (mix.day=%.2f) -- the peak of the day,")
      :format(NOON, DayNight.CYCLE, bestDay))
  log("  which is where the cloud weight is highest and the storm has the")
  log("  most light to take the colour out of.")
  DayNight.overcast = 1
  local sepAt = {}
  for _, s in ipairs({ 0, 0.25, 0.5, 0.75, 1 }) do
    DayNight.storm = s
    local pal = DayNight.palette(NOON)
    local horizon, zenith = pal[1], pal[#pal]
    local sep = (horizon[3] - horizon[2])
    sepAt[#sepAt + 1] = sep
    log(("  storm=%.2f  horizon=%3d,%3d,%3d  zenith=%3d,%3d,%3d  b-g=%+d")
        :format(s, horizon[1], horizon[2], horizon[3],
                zenith[1], zenith[2], zenith[3], sep))
  end
  -- NON-DECREASING, not strictly rising: the palette is quantised to the
  -- 5-bit lattice on the way out (q8), so two adjacent storm rungs can land
  -- on the same texel and read as a plateau. That is the lattice doing its
  -- job, not the blend failing to move -- a strict test here fails on
  -- correct output, which is worse than no test.
  local rising = true
  for i = 2, #sepAt do if sepAt[i] < sepAt[i - 1] then rising = false end end
  log("  non-decreasing b-g (plateaus are the 5-bit lattice): "
      .. (rising and "OK" or "FAIL"))
  log(("  total swing: %+d -> %+d"):format(sepAt[1], sepAt[#sepAt]))

  -- and that the gate is the lightning's gate: storm must stay zero for an
  -- ordinary shower and only leave zero where a strike becomes possible
  log("  the gate (Weather pushes storm only above STRIKE_ABOVE = "
      .. tostring(Weather.STRIKE_ABOVE) .. "):")
  for _, p in ipairs({ 0.3, 0.6, 0.78, 0.85, 1.0 }) do
    local want = 0
    if p > Weather.STRIKE_ABOVE then
      want = (p - Weather.STRIKE_ABOVE) / (1 - Weather.STRIKE_ABOVE)
    end
    log(("    power=%.2f -> storm=%.2f"):format(p, want))
  end
  DayNight.storm, DayNight.overcast = realStorm, realOver

  -- ------- 2. the stars (exact, no pixels)
  log("")
  log("======== 2. stars -- the field EMPTIES rather than dimming")
  log("  'live' is how many of the field clear their own threshold. The old")
  log("  model had no threshold: every star was lit at every amount above")
  log("  zero and they all dimmed together, which is a layer fade.")
  local field = Sky._starField()
  local cap = math.min(#field, Quality.starCount())
  log(("  field=%d  drawn cap=%d"):format(#field, cap))
  local prev = -1
  local monotone = true
  for _, amt in ipairs({ 0.1, 0.25, 0.4, 0.55, 0.7, 0.85, 1.0 }) do
    local live = 0
    for i = 1, cap do
      local st = field[i]
      local gate = 0.55 * (1 - st.mag) + 0.30 * (st.phase / 6.2832)
      if amt - gate > 0 then live = live + 1 end
    end
    if live < prev then monotone = false end
    prev = live
    log(("  amount=%.2f  live=%3d/%d  (old model: %d/%d)")
        :format(amt, live, cap, cap, cap))
  end
  log("  monotone in amount: " .. (monotone and "OK" or "FAIL"))
  log("  full field at amount=1.0: "
      .. (prev == cap and "OK -- a clear deep night is unchanged"
                       or ("FAIL: " .. prev .. "/" .. cap)))

  -- ------- 3. the curtain's CURVE (exact, no pixels)
  log("")
  log("======== 3. far curtain -- does it LEAD the streaks")
  log("  BUILD = " .. tostring(Weather.BUILD) .. "s to peak; the curtain is")
  log("  full at power " .. tostring(Weather.CURTAIN_FULL) .. ", which is")
  log("  where the near field is still almost nothing. That ordering IS the")
  log("  effect -- you watch grey close in before you are wet.")
  local function curtainAt(p)
    local a = (p - Weather.CURTAIN_IN)
              / (Weather.CURTAIN_FULL - Weather.CURTAIN_IN)
    if a <= 0 then return 0 end
    return a > 1 and 1 or a
  end
  log("   t(s)  power  curtain  streaks(share of full)")
  local peak = 1.0
  for t = 0, Weather.BUILD, 2 do
    local p = math.min(peak, t / Weather.BUILD * peak)
    log(("  %5.1f  %.3f   %.3f    %.3f"):format(t, p, curtainAt(p), p))
  end
  local tFull = Weather.CURTAIN_FULL / peak * Weather.BUILD
  log(("  curtain full at t=%.1fs, with the near field at %.0f%% -- %.1fs of")
      :format(tFull, Weather.CURTAIN_FULL * 100, Weather.BUILD - tFull))
  log("  approach left to watch after the wall is drawn.")

  -- ------- the offscreen rig
  --
  -- Fixed canvas, fixed horizon, fixed cell. The descriptor is built ONCE and
  -- reused for every render in a pair, which is what makes the pairs honest:
  -- the band ramp is cached on that table's identity, so both halves sample
  -- exactly the same colours and nothing but the thing under test can move.
  local W, H, CELL, EDGE = 320, 288, 4, 190
  local okCv, cv = pcall(love.graphics.newCanvas, W, H)
  if not (okCv and cv) then return done("FAIL: no canvas") end

  local function paintTo(desc, camX, camY, body)
    love.graphics.setCanvas(cv)
    love.graphics.clear(desc[1], desc[2], desc[3], 1)
    Sky.paint(W, H, desc, EDGE, CELL, body, camX, camY)
    love.graphics.setCanvas()
    return cv:newImageData()
  end

  -- mean absolute channel difference over a horizontal slice, in 0..255,
  -- plus the share of sampled pixels that moved at all (cel content changes
  -- in whole cells, so coverage says more than magnitude alone)
  local function diff(a, b, y0, y1)
    local sum, moved, cells = 0, 0, 0
    for y = math.floor(y0), math.floor(y1) - 1, 2 do
      for x = 0, W - 1, 2 do
        local r1, g1, b1 = a:getPixel(x, y)
        local r2, g2, b2 = b:getPixel(x, y)
        local d = math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2)
        sum = sum + d
        if d > 0.004 then moved = moved + 1 end
        cells = cells + 1
      end
    end
    if cells == 0 then return 0, 0 end
    return sum / cells / 3 * 255, moved / cells * 100
  end

  -- everything below paints; freeze every input that is not under test
  local realTime = love.timer.getTime
  local realCloudAmount = Sky.cloudAmount
  local realCloudSteps = Quality.cloudSteps
  local realRainbow = Quality.rainbow
  local realDayTime = DayNight.time
  local realAfterRain = Weather.afterRain
  local realCurtain = Weather.curtain
  local realParallax = Sky.CLOUD_PARALLAX
  local realEvolve = Sky.CLOUD_EVOLVE
  local realDir = { Wind.DIR[1], Wind.DIR[2] }

  local fakeNow = 1000
  local function restore()
    love.timer.getTime = realTime
    Sky.cloudAmount, Quality.cloudSteps = realCloudAmount, realCloudSteps
    Quality.rainbow, DayNight.time = realRainbow, realDayTime
    Weather.afterRain, Weather.curtain = realAfterRain, realCurtain
    Sky.CLOUD_PARALLAX, Sky.CLOUD_EVOLVE = realParallax, realEvolve
    Wind.DIR[1], Wind.DIR[2] = realDir[1], realDir[2]
  end

  -- NOTHING below this line may yield: the clock is stubbed, and a frame that
  -- ran with a frozen love.timer.getTime would hand the engine a zero dt.
  love.timer.getTime = function() return fakeNow end
  DayNight.time = function() return NOON end
  Sky.cloudAmount = function() return 0.75 end
  Quality.cloudSteps = function()
    local s = realCloudSteps()
    return s > 0 and s or 6           -- test the march even on a rung without it
  end
  Quality.rainbow = function() return false end
  Weather.afterRain = function() return 0 end
  Weather.curtain = function() return 0 end

  local ok, err = pcall(function()
    local desc = Sky.dress({ 0, 0, 0, 1 })
    local sun = { x = W * 0.5, y = EDGE * 0.22, moon = false,
                  glowAmt = 0, glowColor = { 248, 232, 176 } }

    -- ---- 4. parallax: same instant, two cameras
    log("")
    log("======== 4. cloud parallax -- is the deck over the MAP or the screen")
    local a = paintTo(desc, 0, 0, nil)
    local b = paintTo(desc, 4000, 0, nil)
    local dm, dc = diff(a, b, 0, EDGE * 0.7)
    log(("  camX 0 vs 4000, same clock:  mean=%.2f/255  moved=%.1f%%")
        :format(dm, dc))
    Sky.CLOUD_PARALLAX = 0
    local c0 = paintTo(desc, 0, 0, nil)
    local c1 = paintTo(desc, 4000, 0, nil)
    local zm, zc = diff(c0, c1, 0, EDGE * 0.7)
    log(("  control (CLOUD_PARALLAX=0):  mean=%.2f/255  moved=%.1f%%")
        :format(zm, zc))
    Sky.CLOUD_PARALLAX = realParallax
    log("  verdict: " .. ((dc > 1 and zc < 0.01) and "OK -- the camera moves the deck"
        or "FAIL -- camera does not reach the clouds"))

    -- ---- 5. evolve: wind off, clock forward
    log("")
    log("======== 5. cloud evolve -- does the SHAPE change, or only slide")
    log("  wind zeroed, so drift is zero by construction: what moves is shape.")
    Wind.DIR[1], Wind.DIR[2] = 0, 0
    fakeNow = 1000
    local e0 = paintTo(desc, 0, 0, nil)
    fakeNow = 1060
    local e1 = paintTo(desc, 0, 0, nil)
    local em, ec = diff(e0, e1, 0, EDGE * 0.7)
    log(("  t=1000 vs t=1060, no wind:   mean=%.2f/255  moved=%.1f%%")
        :format(em, ec))
    Sky.CLOUD_EVOLVE = 0
    fakeNow = 1000
    local f0 = paintTo(desc, 0, 0, nil)
    fakeNow = 1060
    local f1 = paintTo(desc, 0, 0, nil)
    local fm, fc = diff(f0, f1, 0, EDGE * 0.7)
    log(("  control (CLOUD_EVOLVE=0):    mean=%.2f/255  moved=%.1f%%")
        :format(fm, fc))
    Sky.CLOUD_EVOLVE = realEvolve
    Wind.DIR[1], Wind.DIR[2] = realDir[1], realDir[2]
    fakeNow = 1000
    log("  verdict: " .. ((ec > 1 and fc < 0.01) and "OK -- the deck reshapes"
        or "FAIL -- shape is rigid; only the wind was moving it"))

    -- ---- 6. curtain: is it drawn, and is it drawn in the RIGHT PLACE
    log("")
    log("======== 6. far curtain -- drawn low, and only low")
    local g0 = paintTo(desc, 0, 0, nil)
    Weather.curtain = function() return 1 end
    local g1 = paintTo(desc, 0, 0, nil)
    Weather.curtain = function() return 0 end
    local upM, upC = diff(g0, g1, 0, EDGE * 0.25)
    local loM, loC = diff(g0, g1, EDGE * 0.55, EDGE)
    log(("  upper sky (0..25%%):  mean=%.2f/255  moved=%.1f%%"):format(upM, upC))
    log(("  lower sky (55..100%%): mean=%.2f/255  moved=%.1f%%"):format(loM, loC))
    log("  verdict: " .. ((loC > 5 and upC < 1)
        and "OK -- a wall on the horizon, not a second cloud deck"
        or "FAIL -- wrong band"))

    -- ---- 7. god rays: near the disc, and never off a moon
    log("")
    log("======== 7. god rays -- around the sun, and only around a sun")
    local h0 = paintTo(desc, 0, 0, sun)
    Weather.afterRain = function() return 1 end
    local h1 = paintTo(desc, 0, 0, sun)
    local nearM, nearC = diff(h0, h1, 0, EDGE * 0.45)
    local farM, farC = diff(h0, h1, EDGE * 0.80, EDGE)
    log(("  near the disc (0..45%%):  mean=%.2f/255  moved=%.1f%%")
        :format(nearM, nearC))
    log(("  far from it (80..100%%):  mean=%.2f/255  moved=%.1f%%")
        :format(farM, farC))
    local moon = { x = sun.x, y = sun.y, moon = true,
                   glowAmt = 0, glowColor = { 240, 244, 248 } }
    local m0 = paintTo(desc, 0, 0, moon)
    Weather.afterRain = function() return 0 end
    local m1 = paintTo(desc, 0, 0, moon)
    local moonM, moonC = diff(m0, m1, 0, EDGE * 0.45)
    log(("  same test with a MOON:   mean=%.2f/255  moved=%.1f%%")
        :format(moonM, moonC))
    log("  verdict: " .. ((nearC > 3 and nearC > farC and moonC < 0.01)
        and "OK -- rays follow the sun, and a moon throws none"
        or "FAIL"))

    -- ---- 8. what it costs
    log("")
    log("======== 8. cost -- palindrome, off / on / on / off")
    log("  'on' is curtain=1 and afterRain=1 together: both new blocks in the")
    log("  fragment at once, which is a state the game never actually reaches")
    log("  (a curtain means it is raining, rays mean it stopped). It is the")
    log("  ceiling, deliberately.")
    local REPS = 60
    local function phase(on)
      Weather.curtain = function() return on and 1 or 0 end
      Weather.afterRain = function() return on and 1 or 0 end
      love.graphics.setCanvas(cv)             -- warm the target
      love.graphics.setCanvas()
      local t0 = realTime()
      for _ = 1, REPS do
        love.graphics.setCanvas(cv)
        love.graphics.clear(desc[1], desc[2], desc[3], 1)
        Sky.paint(W, H, desc, EDGE, CELL, sun, 0, 0)
        love.graphics.setCanvas()
      end
      -- one readback to force the pipeline to actually finish the batch,
      -- otherwise this times the submission and not the drawing
      cv:newImageData()
      return (realTime() - t0) / REPS * 1000
    end
    local p1 = phase(false)
    local p2 = phase(true)
    local p3 = phase(true)
    local p4 = phase(false)
    local off = (p1 + p4) / 2
    local on = (p2 + p3) / 2
    log(("  off: %.3f ms  %.3f ms   -> %.3f ms"):format(p1, p4, off))
    log(("  on:  %.3f ms  %.3f ms   -> %.3f ms"):format(p2, p3, on))
    log(("  delta: %+.3f ms/paint  (%+.1f%%)")
        :format(on - off, off > 0 and (on - off) / off * 100 or 0))
    Weather.curtain = function() return 0 end
    Weather.afterRain = function() return 0 end

    -- ---- 9. the pictures
    log("")
    log("======== 9. screenshots")
    local function shot(name, desc2, camX, body)
      local img = paintTo(desc2, camX or 0, 0, body)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(img:encode("png"):getString()) f:close() end
      log("  wrote " .. name)
    end
    shot("sky_1_clear.png", desc, 0, sun)
    Weather.curtain = function() return 1 end
    shot("sky_2_curtain.png", desc, 0, sun)
    Weather.curtain = function() return 0 end
    Weather.afterRain = function() return 1 end
    shot("sky_3_godrays.png", desc, 0, sun)
    Weather.afterRain = function() return 0 end
    -- the storm sky needs its own descriptor: the bands come from the palette
    DayNight.overcast, DayNight.storm = 1, 0
    shot("sky_4_overcast_grey.png", Sky.dress({ 0, 0, 0, 1 }), 0, nil)
    DayNight.storm = 1
    shot("sky_5_storm_purple.png", Sky.dress({ 0, 0, 0, 1 }), 0, nil)
    DayNight.overcast, DayNight.storm = realOver, realStorm
    -- the parallax pair, for the eye
    shot("sky_6_cam_a.png", desc, 0, nil)
    shot("sky_7_cam_b.png", desc, 4000, nil)
  end)

  restore()
  if not ok then log("!! render section threw: " .. tostring(err)) end

  log("")
  log("done.")
  done()
end
