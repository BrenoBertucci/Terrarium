-- Probe: WHAT THE DIAL ACTUALLY SPENDS ITS TIME ON, and what colour comes
-- out at a locked clock.
--
-- The mod owns six phase palettes and six tints. Reading DayNight.PALETTES
-- you would think the cycle wears six colours. It does not: four of the six
-- are WAYPOINTS the blends pass through, and the dial holds them for about a
-- second each. A screenshot cannot show that -- every frame you shoot is a
-- legitimate blend of two real palettes, so every frame looks defensible and
-- the fact that `dusk` is never actually painted is invisible.
--
-- So this probe answers two questions, both as integers:
--
--   1. DWELL. For each phase, how many of the 1200 seconds does it hold at
--      full weight, and how many does it lead (weight >= 0.5)? That is a
--      pure function of DayNight.mix and needs no frame drawn at all. A dial
--      change is a diff of this table.
--
--   2. RAMP. At a locked clock, on a fixed 50-second grid, what do
--      DayNight.palette / tint / glow / windowLight / shearAt / strengthAt
--      and Light.split actually return? Colour is a number here, not a
--      photograph: a palette change is a table diff, and that is the proof.
--      Sky.bands is read too, because it is the only one of these that can
--      silently shorten the list (PaletteFX replaces the palette outright in
--      the DMG display modes) -- so the band COUNT is logged, not assumed.
--
-- The screenshots at the end are confirmation, never evidence: same map,
-- same camera rung, same weather, and the clock pinned frame by frame so a
-- shot is of an hour rather than of an animation.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/DRAMATIC_SHAPE/tests/daynight_dial_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/daynight_dial_probe.log", "w"))
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
  local lib = exports and exports.DRAMATIC_SHAPE and exports.DRAMATIC_SHAPE.lib
  if not lib then
    log("FAIL: DRAMATIC_SHAPE not loaded"); logf:close(); love.event.quit()
    return
  end
  log("version:", exports.DRAMATIC_SHAPE.version)

  local DayNight = lib.require("DayNight")
  local Sky = lib.require("Sky")
  local Light = lib.require("Light")
  local Weather = lib.require("Weather")
  local Pipelines = require("src.render.Pipelines")

  -- A dry, unclouded world: overcast folds into the same per-second memo the
  -- hour uses, so a shower left running would make every number below a
  -- blend of the hour AND the weather, and the diff would not be readable.
  Weather.setting:sync("off")
  Light.setting:sync(true)
  DayNight.setting:sync("cycle")
  DayNight.overcast = 0
  wait(30)
  DayNight.overcast = 0
  log("light enabled:", tostring(Light.enabled()),
      " overcast:", tostring(DayNight.overcast))

  local PHASES = { "dawn", "golden", "day", "dusk", "violet", "night" }
  local C = DayNight.CYCLE

  -- ------- QUESTION 1: dwell
  --
  -- Walked at one-second resolution over the whole cycle. `full` is the
  -- second held at weight 1 (the phase is being painted as itself); `lead`
  -- is the second it is the largest weight in the mix (the phase is what the
  -- player would name the sky). A waypoint scores near zero on `full` no
  -- matter how good its palette is.
  log("")
  log("=== Q1: DWELL over " .. C .. "s (1s resolution) ===")
  local full, lead = {}, {}
  for _, p in ipairs(PHASES) do full[p], lead[p] = 0, 0 end
  for t = 0, C - 1 do
    local mix = DayNight.mix(t)
    local best, bestW = nil, -1
    for name, w in pairs(mix) do
      if w >= 0.999 then full[name] = (full[name] or 0) + 1 end
      if w > bestW then best, bestW = name, w end
    end
    if best then lead[best] = (lead[best] or 0) + 1 end
  end
  log("  phase     full(w=1)      lead(w=max)")
  local fullSum = 0
  for _, p in ipairs(PHASES) do
    fullSum = fullSum + (full[p] or 0)
    log(("  %-8s %5ds %5.1f%%   %5ds %5.1f%%")
        :format(p, full[p] or 0, (full[p] or 0) / C * 100,
                lead[p] or 0, (lead[p] or 0) / C * 100))
  end
  log(("  -- %d of %d seconds (%.1f%%) are a flat, unblended colour")
      :format(fullSum, C, fullSum / C * 100))
  for _, p in ipairs(PHASES) do
    if (full[p] or 0) < 10 then
      log(("  WAYPOINT: %s holds full weight for %ds -- its palette is never "
           .. "painted as itself"):format(p, full[p] or 0))
    end
  end

  -- Every pin the DAYTIME menu offers must land on a phase that is actually
  -- being held, or choosing DUSK hands the player a blend of two other
  -- things. This is the invariant the dial may not break.
  log("")
  log("  pins (DayNight.T) -- each must sit at full weight on its own phase:")
  for _, name in ipairs({ "dawn", "day", "dusk", "night" }) do
    local t = DayNight.T[name]
    local mix = DayNight.mix(t)
    local parts = {}
    for k, w in pairs(mix) do parts[#parts + 1] = ("%s=%.3f"):format(k, w) end
    table.sort(parts)
    local ok = (mix[name] or 0) >= 0.999
    log(("    %-6s t=%-5d %s  %s"):format(name, t, table.concat(parts, " "),
        ok and "OK" or "FAIL: pin is a blend, not this phase"))
  end

  -- ------- QUESTION 2: the ramp at a locked clock
  --
  -- Fixed 50-second grid so the sample points do not move with the dial and
  -- the two runs are comparable line by line.
  log("")
  log("=== Q2: RAMP on a locked clock, every 50s ===")
  log("  bands are DayNight.palette(t), horizon end FIRST, 0..255 on the "
      .. "5-bit lattice")
  for t = 0, C - 1, 50 do
    DayNight.clock = t
    local mix = DayNight.mix(t)
    local parts = {}
    for k, w in pairs(mix) do
      if w > 0.0005 then parts[#parts + 1] = ("%s=%.3f"):format(k, w) end
    end
    table.sort(parts)
    local pal = DayNight.palette(t)
    local cols = {}
    for i = 1, #pal do
      cols[i] = ("%3d,%3d,%3d"):format(pal[i][1], pal[i][2], pal[i][3])
    end
    local tint = DayNight.tint(true, t)
    local amt, gc = DayNight.glow(t)
    local kx, kz, moon = DayNight.shearAt(t)
    local str = DayNight.strengthAt(t)
    -- the same product applyRig sends to the shader, off the per-phase
    -- curve rather than the flat sun/moon pick this used to mirror
    local direct = DayNight.alphaAt(t) * str
    local skyT, sunT = Light.split(tint, direct, 1)
    local bands = Sky.bands()

    log("")
    log(("t=%-5d %-6s %s"):format(t, moon and "MOON" or "SUN",
        table.concat(parts, " ")))
    log("  pal   " .. table.concat(cols, " | "))
    log(("  tint  %.4f %.4f %.4f   window=%.3f")
        :format(tint[1], tint[2], tint[3], DayNight.windowLight(t)))
    log(("  glow  amt=%.3f %s"):format(amt or 0,
        gc and ("colour=" .. gc[1] .. "," .. gc[2] .. "," .. gc[3]) or "-"))
    log(("  shade shear=%.2f,%.2f len=%.2f strength=%.3f alpha=%.3f")
        :format(kx, kz, math.sqrt(kx * kx + kz * kz), str, direct))
    log(("  light sky=%.4f %.4f %.4f  sun=%.4f %.4f %.4f  sum=%.4f %.4f %.4f")
        :format(skyT[1], skyT[2], skyT[3], sunT[1], sunT[2], sunT[3],
                skyT[1] + sunT[1], skyT[2] + sunT[2], skyT[3] + sunT[3]))
    log(("  bands count=%d (Sky.MAX_BANDS=%d, palette rungs=%d)")
        :format(bands and #bands or -1, Sky.MAX_BANDS, #pal))
  end

  -- THE BRIGHTNESS INVARIANT. lib/Light.lua's header promises that splitting
  -- the hour's tint into a sky term and a sun term "cannot make the world
  -- darker by accident": the two biases are inverse, so their weighted sum
  -- comes back to about the tint it started from. Moving ALPHAS off a single
  -- flat number is exactly the change that could break that promise, since
  -- the weight is what the two are summed WITH. So it is checked rather than
  -- asserted, at every hour, against the tint the same hour asked for.
  log("")
  log("=== Light.split brightness invariant: OLD alpha vs NEW, per hour ===")
  -- MEASURED AGAINST THE OLD FORMULA, not against a threshold I picked.
  -- The first cut of this check used a flat 8% and failed at 12.6% -- and
  -- the 12.6% turned out to be neither new nor a bug: as the sun sets,
  -- strengthAt goes to (very nearly) zero, `direct` goes with it, and the
  -- whole tint lands in the sky term. The sum is then tint * blend(SKY),
  -- and blend(SKY).b is 1.126 -- so a 12.6% blue lift at the moment of
  -- sunset is what "a shadow is lit by the sky" costs, at every value of
  -- ALPHA including the old one. Light.lua's header says the two biases
  -- "cancel in the sum"; they cancel AROUND THE DESIGN POINT and not at the
  -- ends, which is worth knowing and is not worth changing.
  --
  -- So the question is not "how far from 1" but "did moving ALPHA off a
  -- flat number make it worse", and that is a difference of two numbers
  -- computed the same way.
  local worstOld, worstNew, worstT, worstGap = 0, 0, 0, 0
  for t = 0, C - 1, 5 do
    local tint = DayNight.tint(true, t)
    local str = DayNight.strengthAt(t)
    local _, _, moon = DayNight.bodyAt(t)
    local old = (moon and DayNight.ALPHA_MOON or DayNight.ALPHA_SUN) * str
    local new = DayNight.alphaAt(t) * str
    local so, uo = Light.split(tint, old, 1)
    local sn, un = Light.split(tint, new, 1)
    local devO, devN = 0, 0
    for i = 1, 3 do
      if tint[i] > 1e-6 then
        devO = math.max(devO, math.abs((so[i] + uo[i]) / tint[i] - 1))
        devN = math.max(devN, math.abs((sn[i] + un[i]) / tint[i] - 1))
      end
    end
    if devO > worstOld then worstOld = devO end
    if devN > worstNew then worstNew = devN end
    if devN - devO > worstGap then worstGap, worstT = devN - devO, t end
  end
  log(("  worst deviation from the tint: OLD %.2f%%   NEW %.2f%%")
      :format(worstOld * 100, worstNew * 100))
  log(("  worst hour-for-hour REGRESSION: %+.2f points at t=%d")
      :format(worstGap * 100, worstT))
  if worstGap > 0.02 then
    log("  FAIL: the per-phase alpha moved the world's brightness at some "
        .. "hour by more than 2 points beyond what the flat one did")
  else
    log("  OK -- the curve is no further from the tint than the constant was")
  end

  -- The shear clamp is the one number in here that silently throws art away:
  -- K_MAX caps a shadow at twice its height, and once the sun is low enough
  -- that 1/tan(elev) passes it, every remaining minute of the evening has a
  -- shadow of exactly the same length. Written down so the size of what is
  -- being discarded is a number rather than an impression.
  log("")
  log("=== shear clamp: where K_MAX stops the shadow growing ===")
  log(("  K_MAX=%.2f  ALPHA_SUN=%.2f  ALPHA_MOON=%.2f  FADE_DEG=%d")
      :format(DayNight.K_MAX, DayNight.ALPHA_SUN, DayNight.ALPHA_MOON,
              DayNight.FADE_DEG))
  local clampFrom
  for t = 0, C - 1 do
    local _, el = DayNight.bodyAt(t)
    local want = el > 0.5 and (1 / math.tan(math.rad(el))) or math.huge
    if want > DayNight.K_MAX then
      if not clampFrom then clampFrom = t end
    elseif clampFrom then
      log(("  clamped from t=%d to t=%d (%ds, %.1f%% of the cycle)")
          :format(clampFrom, t - 1, t - clampFrom,
                  (t - clampFrom) / C * 100))
      clampFrom = nil
    end
  end
  if clampFrom then
    log(("  clamped from t=%d to end of cycle"):format(clampFrom))
  end

  -- ------- confirmation shots: locked clock, one rung, one map, no weather
  Pipelines.setLevel("voxel", 4)
  wait(90)

  local function shot(name)
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
    wait(3)
  end

  -- DayNight.update runs from the pipeline every frame and would advance a
  -- running cycle out from under the shot, so the clock is re-pinned each
  -- frame rather than once before the wait.
  local function hold(t, frames)
    for _ = 1, frames do DayNight.clock = t; coroutine.yield() end
    DayNight.clock = t
  end

  log("")
  log("=== shots (locked clock, voxel rung 4, weather off) ===")
  local SHOTS = { 0, 150, 300, 500, 600, 660, 900, 1150 }
  for i, t in ipairs(SHOTS) do
    hold(t, 40)
    local mix = DayNight.mix(t)
    local best, bestW = "?", -1
    for k, w in pairs(mix) do if w > bestW then best, bestW = k, w end end
    local name = ("%02d_t%04d_%s.png"):format(i, t, best)
    hold(t, 4)
    shot(name)
    log(("  %s  lead=%s w=%.3f"):format(name, best, bestW))
  end

  log("")
  log("done -- " .. OUT)
  logf:close()
  love.event.quit()
end
