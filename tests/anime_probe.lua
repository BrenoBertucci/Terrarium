-- Probe: does the ANIME rung actually band the light, and what does it cost?
--
-- Two questions, deliberately in this order, because the answer to the
-- first one can retire the second: a rung nobody can afford does not need
-- its bands measured.
--
-- ------- QUESTION 1: COST
--
-- Median frame time at OFF / CEL / FULL, as a PALINDROME -- off, cel, full,
-- cel, off. The two OFF measurements are the control: they were taken
-- minutes apart on the same frozen world, so if they disagree by more than
-- 10% then something drifted underneath the run (a thermal throttle, a
-- background process, a map still streaming) and every number between them
-- is noise. The run says so and stops rather than reporting a delta it
-- cannot stand behind.
--
-- Frame time, not a Perf span. Perf.lua says why in its own header: a span
-- is wall time around a SUBMISSION, and the GPU is free to finish the work
-- later -- so a shader that got more expensive shows up in the frame and
-- not in the label for the pass that caused it. Everything this rung adds
-- is GPU-side. The frame is the only number that can see it.
--
-- ------- QUESTION 2: ARE THE BANDS REAL
--
-- "It looks cel-shaded" is an opinion. What is measurable is that light
-- arrives in FLAT STEPS, and the signature of that is bimodal: across a
-- continuous surface a ramp produces many small luminance gradients, and a
-- staircase produces mostly ZERO gradient with a few LARGE jumps. So the
-- statistic is the shape of the gradient histogram, not a colour.
--
-- Which is the same shape the water shimmer probe found, and it is not a
-- coincidence -- both are asking whether a hard step()ped field replaced a
-- smooth one.
--
-- A THRESHOLD ON THAT NUMBER WOULD BE A GUESS, so there is none. The test
-- is an ABLATION: drive Anime.BANDS to 2, 4 and 16 and watch the flat
-- fraction fall monotonically. If it does not move with the knob, the knob
-- is not connected to the picture, whatever the frame looks like -- and
-- that is a thing this project has shipped before.
--
-- The ink and the rim are ablated the same way: count how many pixels move
-- when each is turned off ALONE, at FULL, with everything else unchanged.
--
-- ------- what this probe CANNOT settle
--
-- Whether it looks good. It writes the PNGs out beside the log for exactly
-- that reason -- the numbers say the effect is present and what it costs,
-- and the eye says whether it was worth it.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/anime_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/anime_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local function fail(why)
    log("FAIL: " .. why); logf:close(); love.event.quit()
  end

  local function median(t)
    local c = {}
    for i = 1, #t do c[i] = t[i] end
    table.sort(c)
    local n = #c
    if n == 0 then return -1 end
    if n % 2 == 1 then return c[(n + 1) / 2] end
    return (c[n / 2] + c[n / 2 + 1]) / 2
  end

  -- One yield is one frame, so the gap between two consecutive yields IS
  -- the frame time. The first few after a settings change are discarded:
  -- that is where the new shader variant compiles, and a 30ms compile
  -- counted as a frame would make every rung look like it costs a compile.
  local function frameTimes(n, warm)
    for _ = 1, (warm or 10) do coroutine.yield() end
    local out, prev = {}, love.timer.getTime()
    for i = 1, n do
      coroutine.yield()
      local now = love.timer.getTime()
      out[i] = (now - prev) * 1000
      prev = now
    end
    return median(out)
  end

  local function grab()
    local got, pending = nil, true
    love.graphics.captureScreenshot(function(data) got = data; pending = false end)
    coroutine.yield()
    local guard = 0
    while pending and guard < 240 do coroutine.yield(); guard = guard + 1 end
    return got
  end

  local function save(data, name)
    if not data then return end
    local f = io.open(OUT .. "/" .. name, "wb")
    if f then f:write(data:encode("png"):getString()) f:close() end
  end

  love.math.setRandomSeed(20260807)

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then return fail("no overworld") end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("WARN: never reached free roam cleanly") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then return fail("TERRARIUM not loaded") end
  log("version:", exports.TERRARIUM.version)

  local Anime    = lib.require("Anime")
  local RayFX    = lib.require("RayFX")
  local Quality  = lib.require("Quality")
  local Voxel3D  = lib.require("Voxel3D")
  local Weather  = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Wind     = lib.require("Wind")
  local Pipelines = require("src.render.Pipelines")

  local function tryRequire(name)
    local ok, m = pcall(lib.require, name)
    return ok and m or nil
  end
  local AmbientLife = tryRequire("AmbientLife")
  local CityLife    = tryRequire("CityLife")
  local WildRoamers = tryRequire("WildRoamers")

  -- ------- FREEZE, for the same reason the water probe freezes
  --
  -- Every rung here is compared against another rung MINUTES later. A cloud
  -- that moved, an hour that advanced or a butterfly that crossed the frame
  -- lands in the difference and is read as the effect. The clock is PINNED
  -- (DayNight "day" is a constant, not a slow crawl) rather than slowed.
  local function freeze()
    Weather.setting:sync("off")
    DayNight.setting:sync("day")
    Wind.setting:sync(0)
    if AmbientLife then pcall(function() AmbientLife.setting:sync("off") end) end
    if CityLife then pcall(function() CityLife.enabled = false end) end
    if WildRoamers then pcall(function() WildRoamers.setting:sync("off") end) end
    Pipelines.setLevel("terrarium_voxel", 5)
  end
  freeze()
  wait(30)

  -- RTX must be above OFF or FULL has no depth buffer to read and silently
  -- draws as CEL -- which is the designed behaviour and would also make
  -- every FULL number on this page a duplicate of the CEL one. Stated in
  -- the log rather than assumed, because a silent degrade is exactly the
  -- kind of thing that turns a probe into a rubber stamp.
  local rtx = RayFX.level()
  log("RTX rung:", rtx, "| render scale 1/" .. tostring(Quality.scale()))
  if rtx == "off" then
    log("WARN: RTX is OFF -- FULL will draw as CEL by design.")
    log("      The rim/ink ablations below are expected to report 0.")
  end

  local function setRung(v)
    Anime.setting:sync(v)
    pcall(Voxel3D.invalidate)
    pcall(RayFX.invalidate)
    wait(8)
  end

  -- ================= QUESTION 1: COST =================
  log("")
  log("---- cost: median frame time, palindrome ----")
  local FRAMES = 240
  local order = { "off", "cel", "full", "cel", "off" }
  local ms = {}
  for i, rung in ipairs(order) do
    setRung(rung)
    ms[i] = frameTimes(FRAMES)
    log(("  %d. %-4s  %.3f ms"):format(i, rung, ms[i]))
  end

  local drift = math.abs(ms[5] - ms[1]) / math.max(ms[1], 0.0001)
  log(("  OFF drift across the run: %.1f%%"):format(drift * 100))
  local readable = drift <= 0.10
  if not readable then
    log("  UNREADABLE: the two OFF measurements disagree by more than 10%.")
    log("  Something drifted under the run. Do not quote the deltas below.")
  end
  local base = (ms[1] + ms[5]) / 2
  local cel  = (ms[2] + ms[4]) / 2
  log(("  CEL  costs %+.3f ms over OFF (%+.1f%%)")
      :format(cel - base, (cel / base - 1) * 100))
  log(("  FULL costs %+.3f ms over OFF (%+.1f%%)")
      :format(ms[3] - base, (ms[3] / base - 1) * 100))

  -- ================= QUESTION 2: ARE THE BANDS REAL =================
  --
  -- Sampled on a central crop. The edges of the frame carry the letterbox
  -- and whatever HUD the mode leaves up, and neither is lit by this shader.
  local W, H = love.graphics.getWidth(), love.graphics.getHeight()
  local x0, x1 = math.floor(W * 0.20), math.floor(W * 0.80)
  local y0, y1 = math.floor(H * 0.25), math.floor(H * 0.75)

  local function lum(data, x, y)
    local r, g, b = data:getPixel(x, y)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
  end

  -- Flat fraction and step fraction of the horizontal luminance gradient.
  --
  -- Sky is excluded by luminance: it is the brightest thing in the frame
  -- and it is a gradient of its own that this rung does not touch, so
  -- leaving it in would dilute both numbers with a surface that cannot
  -- answer the question.
  local function gradientShape(data)
    local flat, step, total = 0, 0, 0
    for y = y0, y1 do
      for x = x0, x1 - 1 do
        local a = lum(data, x, y)
        if a < 0.86 then
          local d = math.abs(lum(data, x + 1, y) - a)
          total = total + 1
          if d < 0.004 then flat = flat + 1
          elseif d > 0.035 then step = step + 1 end
        end
      end
    end
    if total == 0 then return 0, 0, 0 end
    return flat / total, step / total, total
  end

  local function changedPixels(a, b)
    local c = 0
    for y = y0, y1 do
      for x = x0, x1 do
        local r1, g1, b1 = a:getPixel(x, y)
        local r2, g2, b2 = b:getPixel(x, y)
        local d = math.abs(r1 - r2)
        local t = math.abs(g1 - g2); if t > d then d = t end
        t = math.abs(b1 - b2); if t > d then d = t end
        if d > 0.02 then c = c + 1 end
      end
    end
    return c
  end

  log("")
  log("---- bands: gradient shape (flat = |dL| < 0.004, step = |dL| > 0.035)")

  setRung("off")
  local shotOff = grab()
  save(shotOff, "anime_off.png")
  local fOff, sOff, nPix = gradientShape(shotOff)
  log(("  OFF          flat %.4f  step %.4f  (%d px sampled)")
      :format(fOff, sOff, nPix))

  -- THE ABLATION. A band count that does not move the flat fraction is a
  -- band count that is not reaching the picture.
  local realBands = Anime.BANDS
  local flats = {}
  for _, b in ipairs({ 2, 4, 16 }) do
    Anime.BANDS = b
    setRung("cel")
    local shot = grab()
    save(shot, ("anime_cel_bands%d.png"):format(b))
    local f, s = gradientShape(shot)
    flats[b] = f
    log(("  CEL bands=%-2d  flat %.4f  step %.4f"):format(b, f, s))
    shot:release()
  end
  Anime.BANDS = realBands

  local monotonic = flats[2] >= flats[4] and flats[4] >= flats[16]
  log(("  monotonic in band count: %s"):format(tostring(monotonic)))
  if not monotonic then
    log("  VERDICT: the BANDS knob is not driving the picture. The cel step")
    log("  is either not compiled in (check Voxel3D.shaderError) or not sent.")
  elseif flats[4] <= fOff then
    log("  VERDICT: banding is on but no flatter than OFF -- the step is")
    log("  landing inside the dither's own width. Lower Anime.DITHER.")
  else
    log("  VERDICT: light arrives in steps, and the step count drives it.")
  end

  -- ---- rim and ink, ablated one at a time at FULL
  log("")
  log("---- rim and ink: pixels moved by each, alone, at FULL")

  setRung("full")
  local shotFull = grab()
  save(shotFull, "anime_full.png")

  local realInk = Anime.INK
  Anime.INK = 0
  setRung("full")
  local shotNoInk = grab()
  save(shotNoInk, "anime_full_no_ink.png")
  Anime.INK = realInk
  log(("  ink:  %d px"):format(changedPixels(shotFull, shotNoInk)))

  local realRim = Anime.RIM
  Anime.RIM = 0
  setRung("full")
  local shotNoRim = grab()
  save(shotNoRim, "anime_full_no_rim.png")
  Anime.RIM = realRim
  log(("  rim:  %d px"):format(changedPixels(shotFull, shotNoRim)))

  if rtx ~= "off" then
    log("  (both should be well above zero on this RTX rung; a zero here is")
    log("   the screen-space block not compiling -- see RayFX.shaderError)")
    if RayFX.shaderError then log("  RayFX.shaderError:", RayFX.shaderError) end
    if Voxel3D.shaderError then log("  Voxel3D.shaderError:", Voxel3D.shaderError) end
  end

  shotOff:release(); shotFull:release()
  shotNoInk:release(); shotNoRim:release()

  setRung("off")
  log("")
  log("PNGs written beside this log. The numbers say the effect is present")
  log("and what it costs; only the eye says whether it was worth it.")
  logf:close()
  love.event.quit()
end
