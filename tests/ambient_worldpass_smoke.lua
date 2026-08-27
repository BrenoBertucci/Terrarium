-- Smoke: AmbientLife.WORLD_PASS on BY DEFAULT, with a natural population.
--
-- The occlusion probe proves five pinned fixtures translate correctly; it
-- says nothing about the flag being on for real play -- dozens of live
-- critters, spawns and deaths mid-frame, fireflies at night with the
-- additive glow batch alongside the core one. The one failure mode that
-- matters here is the project's own armadilha #1: a throw inside a draw
-- takes the whole particle pipeline down silently. So this drives a real
-- route through day and night and reads the canaries:
--
--   AmbientLife.lastError / drawError   the module's own catches
--   AmbientLife.worldTrace              batches per scene render, live
--   WindFX.ticks / Weather.ticks        the modules BELOW ambient in the
--                                       pipeline hook -- still ticking
--                                       means no throw escaped upstream
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/ambient_worldpass_smoke.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/ambient_smoke.log", "w"))
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
    local done = false
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      done = true
    end)
    local guard = 0
    while not done and guard < 240 do coroutine.yield(); guard = guard + 1 end
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

  local AmbientLife = lib.require("AmbientLife")
  local Weather  = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Wind     = lib.require("Wind")
  local WindFX   = lib.require("WindFX")
  local Pipelines = require("src.render.Pipelines")

  log("WORLD_PASS default:", tostring(AmbientLife.WORLD_PASS))
  Weather.setting:sync("off")
  Wind.setting:sync(2)
  AmbientLife.setting:sync("on")
  Pipelines.setLevel("terrarium_voxel", 4)

  local ow = game.overworld
  local function report(tag)
    log(("%s: critters(count-able) %d  worldCalls %d  trace [%s]")
        :format(tag, AmbientLife.count() or -1,
                AmbientLife.worldCalls or -1,
                tostring(AmbientLife.worldTrace)))
    log(("%s: batches %s  emit %s push %s dropped %s")
        :format(tag, tostring(AmbientLife.lastBatches),
                tostring(AmbientLife.lastEmit), tostring(AmbientLife.lastPush),
                tostring(AmbientLife.lastDropped)))
    log(("%s: lastError %s  drawError %s  drawErrors %d  errorCount %d")
        :format(tag, tostring(AmbientLife.lastError),
                tostring(AmbientLife.drawError),
                AmbientLife.drawErrors or 0, AmbientLife.errorCount or 0))
    log(("%s: canaries WindFX.ticks %s live %s  Weather.ticks %s ok %s")
        :format(tag, tostring(WindFX.ticks), tostring(WindFX.ticksLive),
                tostring(Weather.ticks), tostring(Weather.ticksOk)))
  end

  DayNight.setting:sync("day")
  ow:setMap("ROUTE_1", 10, 20, "up")
  wait(900)                      -- let the population fill in and churn
  report("day")
  shot("smoke_day.png")

  -- and the fireflies, which are the two-builder path (core + glow)
  DayNight.setting:sync("night")
  wait(900)
  report("night")
  shot("smoke_night.png")

  -- verdict line, so a cold read of this log needs nothing else
  local dead = (AmbientLife.drawErrors or 0) > 0
            or (AmbientLife.errorCount or 0) > 0
  local wt = tostring(WindFX.ticks or 0)
  log(dead and "SMOKE FAIL: ambient threw (see errors above)"
      or ("SMOKE PASS: no throws, pipeline alive (WindFX.ticks " .. wt .. ")"))
  logf:close()
  love.event.quit()
end
