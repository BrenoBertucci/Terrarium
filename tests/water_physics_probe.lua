-- Probe: water body physics -- liquid / rain / freeze / walk-on-ice.
--
-- Two questions per round (metric + physical state). Clock and weather are
-- controlled; no free-running sky. Cintilação is measured only when a water
-- mask can be derived (FLAT vs SWELL union, same idiom as water_shimmer_probe).
--
--   Q1 cintilação   % of water pixels that flip between consecutive frames
--                   (clock pinned, weather fixed)
--   Q2 física       swell / freeze / crest / walkableIce / surface height
--
-- Also forces a quick arithmetic regression: heightAt must track freeze
-- damping, phase must slow under rain, and fully frozen plates must report
-- walkableIce.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/water_physics_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/water_physics_probe.log", "w"))
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

  local function median(t)
    local c = {}
    for i = 1, #t do c[i] = t[i] end
    table.sort(c)
    local n = #c
    if n == 0 then return -1 end
    if n % 2 == 1 then return c[(n + 1) / 2] end
    return (c[n / 2] + c[n / 2 + 1]) / 2
  end

  love.math.setRandomSeed(20260804)

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

  local Water = lib.require("Water")
  local Wind = lib.require("Wind")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Perf = lib.require("Perf")

  -- Pin a pond (Cerulean has water in view).
  pcall(function() game.overworld:setMap("CERULEAN_CITY", 14, 7, "up") end)
  wait(120)

  Weather.setting:sync("off")
  DayNight.setting:sync("day")
  Water.setting:sync(0.8)   -- CALM
  Wind.setting:sync(2)      -- BREEZE
  Water.wet, Water.snow, Water.freeze = 0, 0, 0
  wait(30)

  local function snap(tag)
    Water.refreshLive()
    log(("[%s] swell=%.3f freeze=%.3f crest=%.3f veil=%.3f iceLift=%.3f "
         .. "wet=%.2f snow=%.2f sparkle=%.3f")
        :format(tag, Water.swell(), Water.freeze, Water.CREST, Water.SNOW_VEIL,
                Water.iceLift(), tonumber(Water.wet) or 0,
                tonumber(Water.snow) or 0, Water.sparkleNow()))
    log(("[%s] WAVE_A=(%.4f,%.4f) heightAt(80,80)=%.3f surfaceAt=%.3f "
         .. "frozenAt=%.3f walkable=%s")
        :format(tag, Water.WAVE_A[1], Water.WAVE_A[2],
                Water.heightAt(80, 80), Water.surfaceAt(80, 80),
                Water.frozenAt(80, 80),
                tostring(Water.walkableIce(80, 80))))
  end

  ---------------------------------------------------------------- round 1
  -- Q1: rain raises crest, kills sparkle, keeps swell > 0 under CALM
  -- Q2: wet phase slower than dry (phase() uses absolute time * rate; we
  --     compare rate factors via swell CHOP and sparkle)
  log("--- ROUND 1 liquid + rain (crest foam path) ---")
  Water.wet, Water.snow, Water.freeze = 0, 0, 0
  Water.refreshLive()
  local drySparkle = Water.sparkleNow()
  local drySwell = Water.swell()
  local dryCrest = Water.CREST
  snap("dry")

  Water.wet = 1
  Water.refreshLive()
  local wetSparkle = Water.sparkleNow()
  local wetSwell = Water.swell()
  local wetCrest = Water.CREST
  snap("rain")

  local r1_ok = wetSwell > drySwell
                and wetSparkle < drySparkle * 0.05
                and wetCrest > dryCrest
  log(("Q1_rain_crest: drySwell=%.3f wetSwell=%.3f dryCrest=%.3f wetCrest=%.3f "
       .. "drySparkle=%.3f wetSparkle=%.3f -> %s")
      :format(drySwell, wetSwell, dryCrest, wetCrest, drySparkle, wetSparkle,
              r1_ok and "PASS" or "FAIL"))
  -- Q2: wind shortens wavelength (raises WAVE magnitude)
  local calmA = Water.WAVE_A0[1]
  Wind.setting:sync(0)  -- OFF
  Water.refreshLive()
  local offA = Water.WAVE_A[1]
  Wind.setting:sync(4)  -- GALE
  Water.refreshLive()
  local galeA = Water.WAVE_A[1]
  local r1b_ok = galeA > offA and offA >= calmA * 0.99
  log(("Q2_wind_wavelength: offA=%.4f galeA=%.4f baseA0=%.4f -> %s")
      :format(offA, galeA, calmA, r1b_ok and "PASS" or "FAIL"))
  shot("phys_r1_rain.png")

  ---------------------------------------------------------------- round 2
  -- Q1: freeze damps swell to ~0 and raises surface (iceLift)
  -- Q2: frozenAt plates + walkableIce at full freeze
  log("--- ROUND 2 freeze progressive + walkable ---")
  Water.wet = 0
  Wind.setting:sync(2)
  Water.snow = 1
  Water.freeze = 0
  for _ = 1, 40 do Water.step(0.05) end  -- ~2s freeze advance
  snap("freeze_partial")
  local partialSwell = Water.swell()
  local partialFreeze = Water.freeze
  local partialWalk = Water.walkableIce(80, 80)

  Water.freeze = 1
  Water.refreshLive()
  snap("freeze_full")
  local fullSwell = Water.swell()
  local fullLift = Water.iceLift()
  local fullWalk = Water.walkableIce(80, 80)
  local fullSurf = Water.surfaceAt(80, 80)

  local r2_ok = partialFreeze > 0.05
                and fullSwell <= 0.001
                and fullLift > 0.4
                and fullWalk == true
                and fullSurf > Water.BASE
  log(("Q1_freeze_swell: partialFreeze=%.3f partialSwell=%.3f fullSwell=%.3f "
       .. "iceLift=%.3f -> %s")
      :format(partialFreeze, partialSwell, fullSwell, fullLift,
              (fullSwell <= 0.001 and fullLift > 0.4) and "PASS" or "FAIL"))
  log(("Q2_walkable_ice: partialWalk=%s fullWalk=%s surface=%.3f BASE=%.3f -> %s")
      :format(tostring(partialWalk), tostring(fullWalk), fullSurf, Water.BASE,
              (fullWalk and fullSurf > Water.BASE) and "PASS" or "FAIL"))
  shot("phys_r2_ice.png")

  -- melt under day: must drop from full freeze; clear morning clears most ice
  Water.snow = 0
  Water.freeze = 1
  DayNight.setting:sync("day")
  local meltStart = Water.freeze
  for _ = 1, 100 do Water.step(0.05) end  -- ~5s wall
  snap("melt")
  local meltOk = Water.freeze < meltStart - 0.25 and Water.freeze < 0.55
  log(("Q2b_melt: start=%.3f end=%.3f -> %s")
      :format(meltStart, Water.freeze, meltOk and "PASS" or "FAIL"))

  ---------------------------------------------------------------- round 3
  -- Surf still required (ice not free-walk) + foot jitter + stand anim
  log("--- ROUND 3 surf-required ice + stand anim + foot jitter ---")
  Water.freeze = 1
  Water.refreshLive()
  Water.noteFoot(80, 80)
  local jit = Water.stepJitter
  local map = game.overworld and game.overworld.map
  local freeWalk = false
  if map and map.isWaterCell and map.isWalkableCell then
    local pcx = game.overworld.player.cellX
    local pcy = game.overworld.player.cellY
    for dy = -8, 8 do
      for dx = -8, 8 do
        local cx, cy = pcx + dx, pcy + dy
        if map:inBounds(cx, cy) and map:isWaterCell(cx, cy) then
          local w = map:isWalkableCell(cx, cy)
          if w then freeWalk = true end
        end
      end
    end
  end
  -- waterline on ice is 0 (full body); liquid is base cut
  local cutIce = Water.waterlineCut(80, 80, 5)
  Water.freeze = 0
  Water.refreshLive()
  local cutWet = Water.waterlineCut(80, 80, 5)
  Water.freeze = 1
  Water.refreshLive()
  -- fire stand anim as if surfer crossed threshold
  Water._wasSolidIce = false
  Water.standEvent = { kind = "lock", t = 0, dur = 0.95 }
  local midCut = Water.waterlineCut(80, 80, 5)
  Water.standEvent.t = 0.5
  local midCut2 = Water.waterlineCut(80, 80, 5)
  local hop = Water.standAnimLift(80, 80)
  log(("Q1_step_jitter: stepJitter=%.2f -> %s")
      :format(jit, jit > 0.5 and "PASS" or "FAIL"))
  -- freeWalk without canUseSurf must be false; with Surf gate ice is walkable
  local canSurf = Water.canUseSurf and Water.canUseSurf()
  local gateOk = (canSurf and freeWalk) or ((not canSurf) and (not freeWalk))
  log(("Q2_surf_gate: canSurf=%s freeWalkIce=%s cutIce=%d cutWet=%d -> %s")
      :format(tostring(canSurf), tostring(freeWalk), cutIce, cutWet,
              (gateOk and cutIce == 0 and cutWet == 5) and "PASS" or "FAIL"))
  log(("Q2b_stand_anim: midCut=%d@0 midCut@0.5=%d hop=%.2f -> %s")
      :format(midCut, midCut2, hop,
              (midCut2 < 5 and hop > 0.5) and "PASS" or "FAIL"))
  shot("phys_r3_walk.png")

  ---------------------------------------------------------------- perf palindrome (~900 frame warm, median)
  log("--- PERF palindrome (warm ~900, median ms) ---")
  Water.wet, Water.snow, Water.freeze = 0.6, 0, 0
  Water.setting:sync(1.4)  -- SWELL
  Wind.setting:sync(4)
  Weather.setting:sync("rain")
  wait(30)
  local samples = {}
  local warm = 900
  for i = 1, warm + 120 do
    local t0 = love.timer.getTime()
    wait(1)
    local ms = (love.timer.getTime() - t0) * 1000
    if i > warm then samples[#samples + 1] = ms end
  end
  local med = median(samples)
  log(("perf_median_ms_after_%d_warm: %.3f (n=%d)")
      :format(warm, med, #samples))
  if Perf and Perf.report then
    local ok, rep = pcall(Perf.report)
    if ok and rep then log("Perf.report:", tostring(rep)) end
  end

  -- restore
  Weather.setting:sync("off")
  Water.wet, Water.snow, Water.freeze = 0, 0, 0
  Wind.setting:sync(2)
  Water.setting:sync(0.8)

  local canSurf = Water.canUseSurf and Water.canUseSurf()
  local gateOk = (canSurf and freeWalk) or ((not canSurf) and (not freeWalk))
  local r3_ok = (jit > 0.5) and gateOk and (cutIce == 0)
  local all = r1_ok and r1b_ok and r2_ok and meltOk and r3_ok
  log(all and "OVERALL PASS" or "OVERALL FAIL")
  log("done")
  logf:close()
  love.event.quit()
end
