-- Probe: does the solver extraction change how the air moves?
--
-- lib/Particles.lua takes the integration out of WindFX. That is a port,
-- not a rewrite, and the whole claim of a port is that nothing moved. This
-- is what turns that claim into a number.
--
-- Individual motes are seeded from love.math.random and will never line up
-- between two runs, so this samples the STATISTICS of a steady field over
-- hundreds of frames of a pinned wind: how many are alive, what mix of
-- kinds, how fast they travel, how high above the ground they sit, how far
-- through their life they are on average. A faithful port moves all of
-- those by less than the run-to-run noise; a port that changed the physics
-- moves at least one of them well past it.
--
-- Run it TWICE with the same rig -- once before the port, once after --
-- and compare the two logs. The noise floor comes free: the probe samples
-- two independent windows in the same run and prints the drift between
-- them, which is what any real difference has to beat.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/particles_parity_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local TAG = os.getenv("PARITY_TAG") or "run"
  local logf = assert(io.open(OUT .. "/particles_parity_" .. TAG .. ".log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit() return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end
  log("tag:", TAG, " version:", exports.TERRARIUM.version)

  local WindFX   = lib.require("WindFX")
  local Wind     = lib.require("Wind")
  local Weather  = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Quality  = lib.require("Quality")
  local Pipelines = require("src.render.Pipelines")

  -- ------- ONE AIR, PINNED
  --
  -- Wind.setting's values are numbers: 1 AUTO / 2 BREEZE / 4 GALE / 0 OFF.
  -- GALE, because the density curve is quadratic in wind and a breeze puts
  -- a handful of motes on screen -- too few for a mean to mean anything.
  -- Weather OFF so the climate cannot switch the kind mix underneath the
  -- sample, and DAY so nothing about the hour moves either.
  Weather.setting:sync("off")
  DayNight.setting:sync("day")
  Wind.setting:sync(4)
  Quality.setting:sync(1)            -- FULL: the biggest field there is
  Pipelines.setLevel("terrarium_voxel", 4)

  game.overworld:setMap("ROUTE_1", 10, 20, "down")
  -- long, because the chunk meshes build twice a frame and a field
  -- sampled while the ground under it is still arriving is a field whose
  -- floor clamp is measuring the wrong floor
  wait(900)

  local ow = game.overworld
  log("map:", ow.map.id, " wind amount:", string.format("%.3f", Wind.amount()),
      " quality.scale:", Quality.scale())

  -- ------- SAMPLE
  --
  -- Two independent windows of the same length. The difference between
  -- them is this rig's own noise, and it is printed so the before/after
  -- comparison has something to be judged against.
  local FIELDS = { "n", "meanSpeed", "meanY", "meanAboveGround",
                   "meanSize", "meanAge", "meanSpin", "minY", "maxY" }

  local function window(samples, gap)
    local acc = {}
    for _, f in ipairs(FIELDS) do acc[f] = 0 end
    local kinds = {}
    local st = {}
    for _ = 1, samples do
      wait(gap)
      WindFX.stats(st)
      for _, f in ipairs(FIELDS) do acc[f] = acc[f] + (st[f] or 0) end
      for k, v in pairs(st.kinds or {}) do kinds[k] = (kinds[k] or 0) + v end
    end
    for _, f in ipairs(FIELDS) do acc[f] = acc[f] / samples end
    acc.kinds = kinds
    return acc
  end

  local a = window(80, 6)
  local b = window(80, 6)

  local function report(label, w)
    log("")
    log("[" .. label .. "]")
    for _, f in ipairs(FIELDS) do
      log(("  %-16s %10.4f"):format(f, w[f]))
    end
    local keys = {}
    for k in pairs(w.kinds) do keys[#keys + 1] = k end
    table.sort(keys)
    local total = 0
    for _, k in ipairs(keys) do total = total + w.kinds[k] end
    for _, k in ipairs(keys) do
      log(("  kind %-8s %6.2f%%"):format(k, w.kinds[k] * 100 / math.max(1, total)))
    end
  end

  report("window A", a)
  report("window B", b)

  -- ------- AND WHAT THE FIELD ALLOCATES
  --
  -- Frame time on this machine is not repeatable -- two runs of the same
  -- cost probe disagreed by five to seven fps, and every row came back
  -- flagged as still settling. Garbage IS repeatable: it does not care
  -- about thermals or about which canvas was rebuilt first.
  --
  -- And it is the honest metric for this change anyway. The old field
  -- built a fresh table for every mote it spawned and threw the whole
  -- array away on every clear; the pool claims a wiped table off its own
  -- freelist and never lets go. If that is true, the bytes allocated per
  -- frame by a field in steady state fall to about nothing.
  --
  -- Measured with the collector stopped, so what is counted is what was
  -- ALLOCATED rather than what happened to survive a sweep.
  do
    collectgarbage("collect")
    collectgarbage("stop")
    local k0 = collectgarbage("count")
    local FRAMES = 600
    wait(FRAMES)
    local k1 = collectgarbage("count")
    collectgarbage("restart")
    log("")
    log("[allocation, collector stopped]")
    log(("  %d frames of a live field at %d motes"):format(FRAMES, WindFX.count()))
    log(("  total    %10.1f KB"):format(k1 - k0))
    log(("  per frame %9.3f KB"):format((k1 - k0) / FRAMES))
  end

  log("")
  log("[noise floor -- A against B, same build, same rig]")
  for _, f in ipairs(FIELDS) do
    local av, bv = a[f], b[f]
    local base = math.max(math.abs(av), math.abs(bv), 1e-6)
    log(("  %-16s A %9.4f  B %9.4f  drift %6.2f%%")
        :format(f, av, bv, math.abs(av - bv) * 100 / base))
  end

  log("")
  log("done")
  logf:close()
  love.event.quit()
end
