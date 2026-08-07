-- Probe: post-rain timer, sky saturation amount, rainbow quality gate.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/after_rain_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/after_rain_probe.log", "w"))
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
  log("version:", exports.TERRARIUM.version)

  local Weather = lib.require("Weather")
  local Sky = lib.require("Sky")
  local Quality = lib.require("Quality")
  local DayNight = lib.require("DayNight")
  local Pipelines = require("src.render.Pipelines")

  DayNight.setting:sync("day")
  Pipelines.setLevel("terrarium_voxel", 4)
  game.overworld:setMap("ROUTE_1", 10, 20, "down")
  wait(120)

  -- dry baseline
  Weather.setting:sync("off")
  for _ = 1, 200 do Weather.update(1 / 30) end
  local a0 = Weather.afterRain()
  log(("afterRain dry=%.3f"):format(a0))
  if a0 ~= 0 then log("FAIL: residual afterRain while dry") else log("PASS: dry is zero") end

  -- arm window explicitly (probe path). afterRain = left/AFTER_RAIN, so
  -- arming 30s of a 180s window yields ~0.167, not 1.0.
  Weather.armAfterRain(30)
  local a1 = Weather.afterRain()
  log(("afterRain armed=%.3f (expect ~0.167 for 30s/180s)"):format(a1))
  if a1 > 0.10 and a1 < 0.30 then log("PASS: armAfterRain sets window")
  else log("FAIL: armAfterRain did not set window") end

  -- bands rebuild with sat (cache.sat path) — just call
  local b1 = Sky.bands()
  log("bands after arm:", b1 and #b1 or 0)

  -- natural arm: rain pin then off, wait for fade
  Weather.setting:sync("rain")
  for _ = 1, 400 do Weather.update(1 / 30) end
  log(("wet power=%.3f"):format(Weather.power() or -1))
  Weather.setting:sync("off")
  local armed = false
  for _ = 1, 900 do
    Weather.update(1 / 30)
    if Weather.afterRain() > 0 then armed = true; break end
  end
  log(armed and "PASS: clearing rain arms afterRain"
            or "FAIL: clearing rain did not arm afterRain")
  log(("afterRain after clear=%.3f"):format(Weather.afterRain()))

  -- residual gone: arm a tiny window and wait on wall-clock (afterRain uses
  -- absolute time, not dt from Weather.update)
  Weather.armAfterRain(0.2)
  wait(30)
  local aEnd = Weather.afterRain()
  log(("afterRain expired=%.4f"):format(aEnd))
  if aEnd < 0.01 then log("PASS: afterRain expires cleanly")
  else log("FAIL: residual afterRain") end

  Quality.setting:sync(2)
  log("Quality.scale:", Quality.scale(),
      "rainbow:", tostring(Quality.rainbow()),
      "fogBands:", tostring(Quality.fogBands()))
  if Quality.rainbow() and Quality.fogBands() > 0 then
    log("PASS: quality helpers on at RES 1/2")
  else
    log("FAIL: quality helpers off at RES 1/2")
  end

  logf:close()
  love.event.quit()
end
