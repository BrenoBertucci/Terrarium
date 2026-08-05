-- Probe: HOW MUCH does the water shimmer, and WHICH of its clocks does it.
--
-- "The water sparkles too much" is not a thing a screenshot can settle, and
-- it is not a thing a colour can settle either. A single frame of water is
-- as pretty or as ugly as you please; the complaint is about what happens
-- BETWEEN two frames. So the measurement is a difference, not a picture:
-- with the clock pinned, the map fixed, the camera still, the weather off
-- and every other moving thing in the world switched off, capture frames
-- BACK TO BACK and count how many water pixels changed from one to the
-- next. That integer is the shimmer. Nothing else in the frame can move, so
-- nothing else can be in the count.
--
-- Four clocks run on that one surface and none of them knows about the
-- others:
--
--   1. the TILESET'S OWN ANIMATION -- the asm's rrca/rlca water roll, which
--      shifts the tile's pixels sideways by a WHOLE texel every ~20 engine
--      frames (TerrainAtlas.patch, kind == "hshift"). A hard jump, three
--      times a second, under everything else.
--   2. the SWELL, displacing the geometry at Water.RATE.
--   3. the CEL BANDS and the GLINT RINGS, which are hard step()s over that
--      continuously moving field -- and a hard edge over a moving field
--      crawls.
--   4. the SSR, re-marching a reflection off a normal it recomputes from
--      the same swell (RayFX.waveNormal).
--
-- So this probe ABLATES them one at a time and prints the integer for each.
-- Subtracting a source and watching the number not move is the only honest
-- way to learn that the source was never the problem.
--
-- ------- the region
--
-- There is no water mask to sample -- RayFX.DEBUG_MASK paints PUDDLES only
-- (RayFX.lua:849 gates it on `pool`), so it is no use for a pond. The mask
-- is DERIVED instead, and derived from the water system's own footprint:
-- freeze the tileset animation, shoot the scene with the WATER row at FLAT,
-- shoot it again at SWELL, and every pixel that differs is a pixel the
-- water system draws -- the surface, the shoreline lip, and whatever the
-- reflection puts on them. Nothing else in the frame can differ, because
-- FLAT vs SWELL is the only thing that changed. Several SWELL frames are
-- unioned in, because a crest passing through zero at the instant of one
-- shot would leave its own pixels out of the mask.
--
-- ------- what it does NOT do
--
-- No timing. Nothing is being changed this round, so there is nothing whose
-- cost could have moved; a Perf palindrome here would burn four minutes to
-- measure the noise floor. The baseline config is measured FIRST and LAST
-- instead, which is the palindrome that matters for a pixel count: if the
-- two disagree by more than 5% the run is declared unreadable rather than
-- reported.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/water_shimmer_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/water_shimmer_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local function shot(name)
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
    wait(3)
  end

  -- ------- capture N frames with exactly one frame between them
  --
  -- The whole measurement rests on these being CONSECUTIVE. captureScreenshot
  -- hands its data back at the end of the frame it was asked on, so one
  -- yield per request is one frame per shot -- and the shimmer being counted
  -- is then the real per-frame delta rather than a delta across whatever gap
  -- a wait() left.
  local function grabSeries(n)
    local frames, pending = {}, 0
    for i = 1, n do
      pending = pending + 1
      love.graphics.captureScreenshot(function(data)
        frames[i] = data; pending = pending - 1
      end)
      coroutine.yield()
    end
    local guard = 0
    while pending > 0 and guard < 240 do coroutine.yield(); guard = guard + 1 end
    return frames
  end

  local function release(frames)
    for i = 1, #frames do pcall(function() frames[i]:release() end) end
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

  -- ------- the count itself
  --
  -- Max absolute channel delta, against two thresholds rather than one: 0.02
  -- is about five levels out of 255 and is roughly where a moving pixel
  -- starts to be seen at all, and 0.08 is where it stops being deniable. A
  -- change that only ever clears the low bar is a surface that is BREATHING;
  -- one that clears the high bar in quantity is one that is FLASHING, and
  -- the complaint is about the second.
  local function diffCount(a, b, mask)
    local lo, hi = 0, 0
    for i = 1, #mask, 2 do
      local x, y = mask[i], mask[i + 1]
      local r1, g1, b1 = a:getPixel(x, y)
      local r2, g2, b2 = b:getPixel(x, y)
      local d = math.abs(r1 - r2)
      local t = math.abs(g1 - g2); if t > d then d = t end
      t = math.abs(b1 - b2); if t > d then d = t end
      if d > 0.02 then
        lo = lo + 1
        if d > 0.08 then hi = hi + 1 end
      end
    end
    return lo, hi
  end

  love.math.setRandomSeed(20260803)

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

  local Water        = lib.require("Water")
  local RayFX        = lib.require("RayFX")
  local Weather      = lib.require("Weather")
  local DayNight     = lib.require("DayNight")
  local Wind         = lib.require("Wind")
  local Quality      = lib.require("Quality")
  local TerrainAtlas = lib.require("TerrainAtlas")
  local ShadowMap    = lib.require("ShadowMap")
  local Pipelines    = require("src.render.Pipelines")

  local function tryRequire(name)
    local ok, m = pcall(lib.require, name)
    return ok and m or nil
  end
  local AmbientLife = tryRequire("AmbientLife")
  local CityLife    = tryRequire("CityLife")
  local WildRoamers = tryRequire("WildRoamers")
  local Routines    = tryRequire("Routines")
  local WorldCurve  = tryRequire("WorldCurve")
  local GroundFX    = tryRequire("GroundFX")

  -- ------- FREEZE EVERYTHING THAT IS NOT THE WATER
  --
  -- Every one of these is in the frame for a reason: an NPC walking the bank
  -- does not stand in the water, but its REFLECTION does, and a reflection
  -- moving inside the mask is counted as shimmer the water did not cause.
  -- Same for a grass tuft leaning in the wind. The clock is PINNED rather
  -- than merely slowed -- DayNight "day" returns a constant (DayNight.T.day,
  -- see DayNight.time), so the sun does not crawl and no tint drifts under
  -- the count.
  local function freeze()
    Weather.setting:sync("off")
    DayNight.setting:sync("day")
    Wind.setting:sync(0)                      -- OFF
    if AmbientLife then AmbientLife.setting:sync("off") end
    if CityLife    then CityLife.setting:sync("off") end
    if WildRoamers then WildRoamers.setting:sync("off") end
    if Routines    then Routines.setting:sync("off") end
    if GroundFX    then pcall(function() GroundFX.setting:sync("off") end) end
    if WorldCurve  then pcall(function() WorldCurve.setting:sync(0) end) end
    Quality.setting:sync(2)                   -- RES 1/2, the default rung
    RayFX.setting:sync("rt")
    Water.setting:sync(0.8)                   -- CALM, the default rung
    Pipelines.setLevel("terrarium_voxel", 5)
  end
  freeze()

  log("")
  log("frozen: weather=" .. tostring(Weather.setting:get())
      .. " time=" .. tostring(DayNight.setting:get())
      .. " wind=" .. tostring(Wind.setting:get())
      .. " res=" .. tostring(Quality.setting:get())
      .. " rtx=" .. tostring(RayFX.setting:get())
      .. " water=" .. tostring(Water.setting:get()))

  -- ------- find the most water in the game, rather than trusting a coordinate
  --
  -- A cell typed into a probe is a cell that is wrong on the next dataset,
  -- and this measurement wants AREA: a pond twelve pixels across gives an
  -- integer too small to tell two configs apart. So several candidate maps
  -- are counted and the wettest one wins, with the count written down so a
  -- thin run is visible as a thin run rather than as a null result.
  local CANDIDATES = {
    "ROUTE_12", "ROUTE_13", "ROUTE_21", "CERULEAN_CITY",
    "VERMILION_CITY", "ROUTE_6", "VIRIDIAN_CITY",
  }

  local function surveyMap(mapId)
    local ok = pcall(function() game.overworld:setMap(mapId, 5, 5, "up") end)
    if not ok then return nil end
    wait(60)
    local m = game.overworld.map
    if not (m and m.isWaterCell) then return nil end
    local cells, best = 0, nil
    for cy = 2, (m.height or 40) - 3 do
      for cx = 2, (m.width or 40) - 3 do
        if m:inBounds(cx, cy) and m:isWaterCell(cx, cy) then
          cells = cells + 1
          if not best then
            -- stand a couple of cells SOUTH of it facing north, so the water
            -- lies between the camera and everything that could reflect in it
            for dy = 2, 5 do
              if m:isWalkableCell(cx, cy + dy) then best = { cx, cy + dy } end
              if best then break end
            end
          end
        end
      end
    end
    return cells, best
  end

  log("")
  log("water survey:")
  local bestMap, bestCells, bestAt = nil, 0, nil
  for _, mapId in ipairs(CANDIDATES) do
    local cells, at = surveyMap(mapId)
    log(("  %-16s %s water cells%s"):format(mapId, tostring(cells or "n/a"),
        at and (" bank " .. at[1] .. "," .. at[2]) or " (no bank found)"))
    if cells and at and cells > bestCells then
      bestMap, bestCells, bestAt = mapId, cells, at
    end
  end
  if not bestMap then
    log("FAIL: no map with reachable water"); logf:close(); love.event.quit()
    return
  end
  log(("  -> using %s at %d,%d (%d water cells)")
      :format(bestMap, bestAt[1], bestAt[2], bestCells))

  game.overworld:setMap(bestMap, bestAt[1], bestAt[2], "up")
  -- long settle: the atlas bakes, the chunk meshes build, the shadow rig
  -- draws, and none of that is the steady state being measured
  wait(300)
  shot("00_scene.png")

  -- ------- the mask
  local realAnimate = TerrainAtlas.animate
  local function tileFreeze(on)
    TerrainAtlas.animate = on and function() return nil end or realAnimate
  end

  local mask = {}
  do
    tileFreeze(true)
    Water.setting:sync(0)                     -- FLAT
    wait(90)
    local flat = grabSeries(1)
    Water.setting:sync(1.4)                   -- SWELL, the widest footprint
    wait(90)
    -- four shots spread across the wave so a crest sitting at zero in one of
    -- them does not drop its own pixels out of the mask
    local swells = {}
    for i = 1, 4 do
      local s = grabSeries(1)
      swells[i] = s[1]
      wait(25)
    end
    tileFreeze(false)
    Water.setting:sync(0.8)                   -- back to CALM

    local f0 = flat[1]
    if not f0 then
      log("FAIL: mask capture returned no frame")
      logf:close(); love.event.quit(); return
    end
    local w, h = f0:getWidth(), f0:getHeight()
    log("")
    log(("frame: %dx%d, sampling every 2px on both axes"):format(w, h))
    local seen = 0
    for y = 0, h - 1, 2 do
      for x = 0, w - 1, 2 do
        seen = seen + 1
        local r0, g0, b0 = f0:getPixel(x, y)
        local hit = false
        for i = 1, 4 do
          local s = swells[i]
          if s then
            local r1, g1, b1 = s:getPixel(x, y)
            local d = math.abs(r1 - r0)
            local t = math.abs(g1 - g0); if t > d then d = t end
            t = math.abs(b1 - b0); if t > d then d = t end
            if d > 0.01 then hit = true break end
          end
        end
        if hit then
          mask[#mask + 1] = x
          mask[#mask + 1] = y
        end
      end
    end
    release(flat); release(swells)
    local px = #mask / 2
    log(("water mask: %d sampled pixels of %d (%.1f%% of the frame)")
        :format(px, seen, 100 * px / math.max(seen, 1)))
    if px < 400 then
      log("  FAIL: mask too small to measure -- every number below is noise")
    end
  end

  -- ------- the configurations
  --
  -- One clock removed at a time, and the baseline run FIRST AND LAST. The
  -- glint is silenced by moving its WINDOW out of reach rather than by
  -- zeroing SPARKLE: sparkle 0 skips the whole cel block (Voxel3D.lua:488
  -- gates on it) and would take the bands and the shoreline foam with it,
  -- which measures three things at once and answers none of them.
  local savedLo, savedHi = Water.GLINT_LO, Water.GLINT_HI

  local CONFIGS = {
    { "A_baseline",  "everything on -- the water as it ships" },
    { "B_no_tile",   "tileset's own rrca/rlca roll frozen" },
    { "C_flat",      "WATER row at FLAT -- geometry does not move" },
    { "D_no_glint",  "glint window moved out of reach; bands and foam stay" },
    { "E_no_ssr",    "RTX off -- no screen-space reflection in the water" },
    { "A2_baseline", "baseline again -- the palindrome" },
  }

  local function apply(name)
    -- always back to the known state first, so a config is what it says it
    -- is rather than whatever the previous one left behind
    tileFreeze(false)
    Water.setting:sync(0.8)
    Water.GLINT_LO, Water.GLINT_HI = savedLo, savedHi
    RayFX.setting:sync("rt")
    if name == "B_no_tile" then tileFreeze(true)
    elseif name == "C_flat" then Water.setting:sync(0)
    elseif name == "D_no_glint" then
      Water.GLINT_LO, Water.GLINT_HI = 9.0, 9.1
    elseif name == "E_no_ssr" then RayFX.setting:sync("off")
    end
  end

  local FRAMES, BATCHES = 9, 5
  local results = {}

  log("")
  log("shimmer: water pixels that changed from one frame to the NEXT")
  log("  (of " .. tostring(#mask / 2) .. " sampled water pixels)")
  log("  BACKGROUND = the churn on an ordinary pair; IMPULSE = the periodic"
      .. " jump and how many pairs caught one")
  log("")
  log("  config         background   %water    impulse   %water   impulses")

  for ci, cfg in ipairs(CONFIGS) do
    local name = cfg[1]
    apply(name)
    -- 300 rather than 150: switching the RTX row rebuilds a shader, and a
    -- config measured while it is still settling is not that config
    wait(300)
    local los, his = {}, {}
    -- FIVE batches spread across seconds rather than one burst. The two wave
    -- trains run at 0.9 and -0.63 rad/s, so they BEAT with a period of about
    -- four seconds -- and a single 9-frame burst samples 0.15s of that beat,
    -- which is a different surface depending on where in the beat it lands.
    -- That is very likely what made the first run's palindrome disagree by
    -- 30% with nothing changed between the two.
    for batch = 1, BATCHES do
      local frames = grabSeries(FRAMES)
      for i = 1, FRAMES - 1 do
        if frames[i] and frames[i + 1] then
          local lo, hi = diffCount(frames[i], frames[i + 1], mask)
          los[#los + 1] = lo
          his[#his + 1] = hi
        end
      end
      release(frames)
      if batch < BATCHES then wait(55) end
    end

    -- ------- the signal is BIMODAL and one number cannot hold it
    --
    -- The first run showed it plainly: with the geometry frozen the count is
    -- EXACTLY zero on most pairs and about 25,000 on a few. That is not
    -- noise around a mean, it is a quiet surface with a periodic IMPULSE on
    -- top -- the tileset's own roll, which rewrites every water texel at
    -- once every ~20 engine frames. A median over eight pairs reports the
    -- quiet part or the loud part depending on how many impulses the window
    -- happened to catch, which is why identical configs disagreed by 30%.
    --
    -- So they are separated and reported as what they are: a BACKGROUND (how
    -- much the surface churns every single frame) and an IMPULSE (how big
    -- the jump is, and how often it lands). They are different complaints
    -- and they have different fixes.
    local base = median(los)
    local cut = math.max(base * 3, 200)
    local quiet, loud = {}, {}
    for i = 1, #los do
      if los[i] > cut then loud[#loud + 1] = los[i]
      else quiet[#quiet + 1] = los[i] end
    end
    local bg, imp = median(quiet), (#loud > 0 and median(loud) or 0)
    local rate = 100 * #loud / math.max(#los, 1)
    results[name] = { bg = bg, imp = imp, rate = rate,
                      hi = median(his), n = #los }
    local px = #mask / 2
    log(("  %-12s  %8.1f  %5.1f%%   %8.1f  %5.1f%%   %3d/%d pairs")
        :format(name, bg, 100 * bg / math.max(px, 1),
                imp, 100 * imp / math.max(px, 1), #loud, #los))
    shot(("1%d_%s.png"):format(ci, name))
  end

  apply("A_baseline")

  -- ------- is the run readable at all
  local a1, a2 = results["A_baseline"], results["A2_baseline"]
  local readable = false
  log("")
  if a1 and a2 and a1.bg > 0 then
    local drift = math.abs(a2.bg - a1.bg) / a1.bg
    readable = drift <= 0.05
    log(("palindrome (background): A=%.1f  A2=%.1f  drift=%.1f%%  [%d pairs each]")
        :format(a1.bg, a2.bg, 100 * drift, a1.n))
    if not readable then
      log("  NOT READABLE: the two identical configs disagree by more than 5%."
          .. " Every delta below the drift is noise -- do not act on it.")
    else
      log("  readable: identical configs agree, so a delta bigger than "
          .. ("%.1f"):format(a1.bg * 0.05) .. " pixels is real")
    end
    log(("palindrome (impulse):    A=%.1f  A2=%.1f  rate %.0f%% vs %.0f%%")
        :format(a1.imp, a2.imp, a1.rate, a2.rate))
  else
    log("palindrome: FAIL -- baseline produced no number")
  end

  log("")
  log("contribution of each clock (baseline minus the ablation):")
  log("  a NEGATIVE background delta means removing that clock made the water"
      .. " churn MORE, which is a result about the render path, not the water")
  for _, cfg in ipairs(CONFIGS) do
    local name = cfg[1]
    local r = results[name]
    if name ~= "A_baseline" and name ~= "A2_baseline" and a1 and r then
      local db = a1.bg - r.bg
      local di = a1.imp - r.imp
      log(("  %-12s  bg %+8.1f (%+6.1f%%)   impulse %+9.1f  rate %3.0f%%->%3.0f%%   %s")
          :format(name, db, 100 * db / math.max(a1.bg, 1), di,
                  a1.rate, r.rate, cfg[2]))
      if not readable and math.abs(db) < a1.bg * 0.30 then
        log("      (background delta is inside the drift -- not a finding)")
      end
    end
  end

  -- ------- SECOND QUESTION: is the glint sitting on the floor()'s tipping point
  --
  -- Arithmetic, not pixels. `s = smoothstep(GLINT_LO, GLINT_HI, dot)` then
  -- `floor(s*3 + 0.5)/3`, and floor() of a number that hovers around an
  -- integer is a SWITCH: the ring turns fully on and fully off with the
  -- wave instead of sliding. The suspicion is that at the default rung the
  -- swell's whole slope range is barely wider than the glint window, so
  -- s*3+0.5 spends its life near 1.0 -- which would make the sparkle a
  -- blink rather than a highlight, and would be a calibration bug rather
  -- than a matter of taste.
  --
  -- So: sweep the two wave trains through a full period, work out the exact
  -- normal the vertex shader would build, take the same dot against the same
  -- sun, and report where `s` actually lands and how much of the time it sits
  -- within a hair of a ring boundary.
  local A, B = Water.WAVE_A, Water.WAVE_B
  local ray = ShadowMap.sunDir()
  log("")
  log(("sun ray (pinned DAY): %.4f %.4f %.4f -> flat dot = %.4f")
      :format(ray[1], ray[2], ray[3], -ray[2]))
  log(("glint window: %.4f .. %.4f  (width %.4f)")
      :format(Water.GLINT_LO, Water.GLINT_HI, Water.GLINT_HI - Water.GLINT_LO))
  log("")
  log("  swell   maxdev   s_min   s_max   ring histogram 0 / 1/3 / 2/3 / 1"
      .. "   near-boundary")

  local function smoothstep(e0, e1, x)
    local t = (x - e0) / (e1 - e0)
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return t * t * (3 - 2 * t)
  end

  local function sweep(swell, lo, hi)
    local flat = -ray[2]
    local hist = { 0, 0, 0, 0 }
    local sMin, sMax, devMax = 1e9, -1e9, 0
    local near, total = 0, 0
    local STEPS = 96
    for i = 0, STEPS - 1 do
      for j = 0, STEPS - 1 do
        local a = (i / STEPS) * 2 * math.pi
        local b = (j / STEPS) * 2 * math.pi
        local gx = A[1] * math.cos(a) * 0.55 + B[1] * math.cos(b) * 0.45
        local gy = A[2] * math.cos(a) * 0.55 + B[2] * math.cos(b) * 0.45
        local nx, ny, nz = -gx * swell, 1, -gy * swell
        local len = math.sqrt(nx * nx + ny * ny + nz * nz)
        nx, ny, nz = nx / len, ny / len, nz / len
        local dot = -(nx * ray[1] + ny * ray[2] + nz * ray[3])
        local dev = dot - flat
        if math.abs(dev) > devMax then devMax = math.abs(dev) end
            -- the window is measured FROM the flat surface's own alignment with
        -- the light: the uniform is {flat + GLINT_LO, flat + GLINT_HI} (see
        -- Voxel3D.lua:1223). Comparing the raw dot against the bare
        -- constants asks whether the sun is up, not whether a crest is
        -- turned into it, and answers "ring 3" for every sample.
        local s = smoothstep(flat + lo, flat + hi, dot)
        if s < sMin then sMin = s end
        if s > sMax then sMax = s end
        local q = s * 3 + 0.5
        local ring = math.floor(q)
        if ring < 0 then ring = 0 elseif ring > 3 then ring = 3 end
        hist[ring + 1] = hist[ring + 1] + 1
        -- within 0.12 of a tipping point: close enough that the wave's own
        -- travel flips it back and forth every few frames
        local frac = q - math.floor(q)
        if frac < 0.12 or frac > 0.88 then near = near + 1 end
        total = total + 1
      end
    end
    return devMax, sMin, sMax, hist, 100 * near / total
  end

  for _, sw in ipairs({ { 0.8, "CALM" }, { 1.4, "SWELL" }, { 1.9, "SWELL+rain" } }) do
    local devMax, sMin, sMax, hist, near =
      sweep(sw[1], Water.GLINT_LO, Water.GLINT_HI)
    local t = hist[1] + hist[2] + hist[3] + hist[4]
    log(("  %-5s   %.4f   %.3f   %.3f   %5.1f%% %5.1f%% %5.1f%% %5.1f%%   %5.1f%%")
        :format(sw[2], devMax, sMin, sMax,
                100 * hist[1] / t, 100 * hist[2] / t,
                100 * hist[3] / t, 100 * hist[4] / t, near))
  end

  log("")
  log("  read: a histogram piled into ONE ring with a high near-boundary %"
      .. " is a glint that blinks.")
  log("  A healthy one spreads across rings and sits away from the tipping"
      .. " points.")

  -- and the same sweep against sun ELEVATION, because the window is measured
  -- from `flat` but its WIDTH is a constant, and how much slope a crest turns
  -- into the light depends entirely on how low the sun is
  log("")
  log("  the same, at CALM, against sun elevation (deg above horizon):")
  log("     elev   maxdev   s_max   ring reached   near-boundary")
  local savedRay = { ray[1], ray[2], ray[3] }
  for _, elev in ipairs({ 10, 20, 30, 45, 60, 75 }) do
    local e = math.rad(elev)
    ray = { math.cos(e) * 0.94, -math.sin(e), math.cos(e) * 0.34 }
    local m = math.sqrt(ray[1] * ray[1] + ray[3] * ray[3])
    if m > 0 then
      ray[1] = ray[1] / m * math.cos(e)
      ray[3] = ray[3] / m * math.cos(e)
    end
    local devMax, _, sMax, hist, near =
      sweep(0.8, Water.GLINT_LO, Water.GLINT_HI)
    local reached = 0
    for k = 4, 1, -1 do if hist[k] > 0 then reached = k - 1 break end end
    log(("     %3d    %.4f   %.3f   %d of 3        %5.1f%%")
        :format(elev, devMax, sMax, reached, near))
  end
  ray = savedRay

  log("")
  log("done -- " .. OUT)
  logf:close()
  love.event.quit()
end
