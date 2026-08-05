-- Probe: what K_MAX costs, and what it is throwing away.
--
-- DayNight.K_MAX clamps a shadow at twice the height of the thing casting
-- it. Measured over the cycle, that clamp is ACTIVE for 520 of 1200 seconds
-- -- t=479..738 and t=1062..121 -- which is the entire golden hour, the
-- whole of dusk and both edges of the night. For all of it the shadow is
-- exactly 2.00 long and stops growing, while the sun keeps sinking. A long
-- raking shadow is most of what an evening looks like and the mod is
-- currently declining to draw one.
--
-- Raising it is not free, and this probe exists to find out what the price
-- actually is, because it is NOT the price it looks like. Longer shadows do
-- not add draw calls: the caster set is decided by Quality (neighbourShadows)
-- and not by the frustum. What they do is widen the light frustum --
--
--     reach = ShadowMap.HEIGHT * max(|KX|, |KZ|) + 24        (ShadowMap.fit)
--
-- -- on two of its four sides, and that box is then fitted onto a fixed
-- texel budget off Quality.shadowSizes(). So the cost of a longer shadow is
-- paid in SHARPNESS, and possibly in one step up the size ladder, and in
-- ShadowMap.slack -- the depth bias, which scales with the box and which
-- detaches a shadow from its caster's feet when it grows.
--
-- So question one is a sweep: at a fixed low-sun hour and a fixed camera,
-- what does each candidate K_MAX do to ShadowMap.res, ShadowMap.extent, the
-- world pixels each shadow texel has to cover, and the slack. Those are all
-- read back live from the fit rather than re-derived here.
--
-- Question two is whether the clamp is doing anything USEFUL where it
-- binds. DayNight.strengthAt already fades a shadow out over the last
-- FADE_DEG degrees of a rise or set. Where the clamp binds while the
-- strength is still 1, it is cutting a shadow that is at full weight and
-- fully visible -- that is the part being thrown away. Where it binds on a
-- shadow that is already fading, it is holding an absurd length off the
-- screen and doing its job.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> [DS_KMAX=4.7] \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/shadow_length_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local CAND = tonumber(os.getenv("DS_KMAX") or "") or 4.7
  local logf = assert(io.open(OUT .. "/shadow_length_probe.log", "w"))
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
  log("version:", exports.TERRARIUM.version, " candidate K_MAX:", CAND)

  local DayNight = lib.require("DayNight")
  local ShadowMap = lib.require("ShadowMap")
  local Quality = lib.require("Quality")
  local Weather = lib.require("Weather")
  local Pipelines = require("src.render.Pipelines")

  Weather.setting:sync("off")
  DayNight.setting:sync("cycle")
  DayNight.overcast = 0
  Pipelines.setLevel("terrarium_voxel", 4)
  wait(120)
  DayNight.overcast = 0

  local C = DayNight.CYCLE
  local K0 = DayNight.K_MAX
  log(("baseline K_MAX=%.2f  FADE_DEG=%d  HEIGHT=%d  ALPHA_SUN=%.2f "
       .. "ALPHA_MOON=%.2f"):format(K0, DayNight.FADE_DEG, ShadowMap.HEIGHT,
                                    DayNight.ALPHA_SUN, DayNight.ALPHA_MOON))

  -- ------- Q1: the sweep
  --
  -- t=525 is the golden-hour waypoint: elevation about 17 degrees, which is
  -- where 1/tan wants 3.25 and the clamp is handing back 2.00. The most
  -- expensive honest place to measure, because it is exactly where a raised
  -- clamp would actually be used.
  -- TWO hours, because one is not the worst case and the first run of this
  -- probe only measured the first. t=525 is the golden-hour waypoint (about
  -- 17 degrees up), where 1/tan wants 3.25 -- so every candidate at or above
  -- that is UNCLAMPED there and they all measure identically. The frustum
  -- keeps growing below it: at t=570 the sun is 7 degrees up, 1/tan wants
  -- 8.16, and a raised clamp is actually being held AT its new value --
  -- which is where reach, and therefore the cost, is largest.
  local SWEEP_TS = { 525, 570 }
  local SWEEP_T = 570                     -- the palindrome runs at the worst
  local KS = { 2.0, 2.5, 3.0, 3.5, 4.0, 4.7, 5.5 }

  local function sample(k, at)
    DayNight.K_MAX = k
    SWEEP_T = at or SWEEP_T
    -- the rig is repointed from the clock every frame by the pipeline, so
    -- pinning the clock and waiting is what actually drives a refit
    for _ = 1, 45 do DayNight.clock = SWEEP_T; coroutine.yield() end
    local ex = ShadowMap.extent or { 0, 0, 0 }
    local res = ShadowMap.res or 1
    local kx, kz = ShadowMap.KX or 0, ShadowMap.KZ or 0
    return {
      k = k, res = res, ex = ex[1], ey = ex[2],
      px = math.max(ex[1], ex[2]) / res,
      slack = ShadowMap.slack or 0,
      reach = ShadowMap.HEIGHT * math.max(math.abs(kx), math.abs(kz)) + 24,
      len = math.sqrt(kx * kx + kz * kz),
    }
  end

  for _, rung in ipairs({ "low", "high" }) do
    Quality.shadowSetting:sync(rung)
    wait(60)
    for _, at in ipairs(SWEEP_TS) do
      local _, el = DayNight.bodyAt(at)
      log("")
      log(("=== Q1: sweep t=%d (sun %.1f deg, 1/tan=%.2f, strength %.2f), "
           .. "SHADOWS=%s, sizes={%s} target=%.2f ===")
          :format(at, el, 1 / math.tan(math.rad(el)), DayNight.strengthAt(at),
                  rung, table.concat(Quality.shadowSizes(), ","),
                  Quality.shadowTarget()))
      log("  K_MAX  shadowLen  reach   res   extent(w x h)      px/texel  slack")
      local base
      for _, k in ipairs(KS) do
        local s = sample(k, at)
        base = base or s.px
        log(("  %4.1f   %6.2f    %5.0f  %4d  %7.0f x %7.0f  %7.3f  %6.3f  %s")
            :format(s.k, s.len, s.reach, s.res, s.ex, s.ey, s.px, s.slack,
                    s.px > base * 1.0001
                    and ("(%+.0f%% coarser)"):format((s.px / base - 1) * 100)
                    or ""))
      end
    end
  end
  SWEEP_T = 570

  Quality.shadowSetting:sync("low")
  DayNight.K_MAX = K0
  wait(60)

  -- ------- Q2: what the clamp is cutting, and whether it is cutting art
  --
  -- Walked a second at a time. For each candidate the interesting number is
  -- not "how long is the clamp on" but "how long is it on while the shadow
  -- is at FULL STRENGTH" -- because a clamp that only ever bites a shadow
  -- that is already fading out is holding back a length nobody would have
  -- seen anyway, and one that bites at full strength is deleting a shadow
  -- the player is looking at.
  log("")
  log("=== Q2: where the clamp binds, and at what strength ===")
  log(("  1/tan(FADE_DEG=%d) = %.2f -- at this K_MAX the clamp can only ever")
      :format(DayNight.FADE_DEG, 1 / math.tan(math.rad(DayNight.FADE_DEG))))
  log("  bite a shadow that has already begun to fade")
  log("  K_MAX  clamped(s)  of which at FULL strength(s)   max length seen")
  for _, k in ipairs(KS) do
    DayNight.K_MAX = k
    local clamped, atFull, longest = 0, 0, 0
    for t = 0, C - 1 do
      local _, el = DayNight.bodyAt(t)
      local want = el > 0.5 and (1 / math.tan(math.rad(el))) or math.huge
      local kx, kz = DayNight.shearAt(t)
      local got = math.sqrt(kx * kx + kz * kz)
      if got > longest then longest = got end
      if want > k + 1e-9 then
        clamped = clamped + 1
        if DayNight.strengthAt(t) >= 0.999 then atFull = atFull + 1 end
      end
    end
    log(("  %4.1f   %5ds      %5ds  %s                %.2f")
        :format(k, clamped, atFull,
                atFull == 0 and "<- cuts nothing visible" or "", longest))
  end
  DayNight.K_MAX = K0

  -- ------- the cost, as a palindrome
  --
  -- Same discipline the night probe had to learn: a long warm-up first
  -- (this build settles over about twenty seconds), per-frame samples, and
  -- a MEDIAN rather than a block mean, because stray stalls of a few
  -- hundred milliseconds land at arbitrary points and destroy an average.
  local FRAMES = 240
  local function phase(label, k)
    DayNight.K_MAX = k
    for _ = 1, 45 do DayNight.clock = SWEEP_T; coroutine.yield() end
    local s = {}
    local prev = love.timer.getTime()
    for i = 1, FRAMES do
      DayNight.clock = SWEEP_T
      coroutine.yield()
      local now2 = love.timer.getTime()
      s[i] = (now2 - prev) * 1000
      prev = now2
    end
    local sum = 0
    for i = 1, FRAMES do sum = sum + s[i] end
    table.sort(s)
    local p50, p95 = s[math.floor(FRAMES * 0.50)], s[math.floor(FRAMES * 0.95)]
    log(("  %-14s p50 %6.3f  p95 %6.3f  mean %6.3f  worst %7.3f ms")
        :format(label, p50, p95, sum / FRAMES, s[FRAMES]))
    return p50, p95
  end

  log("")
  log(("=== cost: palindrome K=%.1f / K=%.1f, t=%d, rung 4, SHADOWS=low ===")
      :format(K0, CAND, SWEEP_T))
  for _ = 1, 900 do DayNight.clock = SWEEP_T; coroutine.yield() end
  phase("0 warm-up", K0)
  log("  (discarded)")
  local a = phase(("1 K=%.1f"):format(K0), K0)
  local b = phase(("2 K=%.1f"):format(CAND), CAND)
  local c = phase(("3 K=%.1f"):format(CAND), CAND)
  local d = phase(("4 K=%.1f"):format(K0), K0)
  local old, new = (a + d) / 2, (b + c) / 2
  log("")
  log(("  p50: K=%.1f %.3f   K=%.1f %.3f   delta %+.3f ms (%+.1f%%)")
      :format(K0, old, CAND, new, new - old, (new / old - 1) * 100))
  local spread = math.abs(d - a) / math.min(a, d) * 100
  log(("  same-K spread %.1f%% -- the delta above is %s")
      :format(spread, spread < 5 and "READABLE"
              or "NOT READABLE, drift still dominates"))
  DayNight.K_MAX = K0

  -- ------- the pair
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
  log("=== shots: same clock, same rung, K_MAX old then candidate ===")
  for _, t in ipairs({ 470, 525, 570 }) do
    hold(t, 40)
    DayNight.K_MAX = K0;   hold(t, 40); shot(("%04d_a_K%.0f.png"):format(t, K0 * 10))
    DayNight.K_MAX = CAND; hold(t, 40); shot(("%04d_b_K%.0f.png"):format(t, CAND * 10))
    local _, el = DayNight.bodyAt(t)
    log(("  t=%d elev=%.1f deg strength=%.3f  1/tan=%.2f")
        :format(t, el, DayNight.strengthAt(t),
                el > 0.5 and 1 / math.tan(math.rad(el)) or 99))
  end
  DayNight.K_MAX = K0

  log("")
  log("done -- " .. OUT)
  logf:close()
  love.event.quit()
end
