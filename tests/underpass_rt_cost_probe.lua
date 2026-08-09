-- Probe: what does RT_SSR cost in the underground passage, on this machine?
--
-- The reference has the corridor's floor reflecting the fittings. RayFX's
-- SSR pass would do that, but it is compiled behind `#define RT_SSR`, which
-- only the "rt" and "max" rungs emit -- and the setting on this machine is
-- "ao". So the question is not whether SSR looks better. It is whether the
-- rung that carries it is affordable on an i3-1115G4 with Intel UHD
-- graphics, and that is a number, not an opinion.
--
-- Measured as FRAME TIME, not as the FPS counter. love.timer.getFPS is a
-- smoothed average over a window the probe does not control, so it lags a
-- rung change by an unknown amount and reads the wrong rung's cost. Frame
-- time is summed here directly over a fixed count of frames, after a settle
-- long enough for the new shader to have compiled and for the first-frame
-- cost of that compilation to be behind us.
--
-- Every rung is measured on the SAME anchored frame -- same map, same cell,
-- same hour -- because the corridor is the whole point: an SSR cost measured
-- on an open route says nothing about a place with two lit walls in it.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/underpass_rt_cost_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/underpass_rt_cost.log", "w"))
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
    wait(4)
  end

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
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end

  local RayFX = lib.require("RayFX")
  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local Quality = lib.require("Quality")
  local Pipelines = require("src.render.Pipelines")

  Weather.setting:sync("off")
  DayNight.setting:sync("night")
  pcall(Pipelines.setLevel, "terrarium_voxel", 4)

  local MAP, MX, MY = "UNDERGROUND_PATH_NORTH_SOUTH", 3, 20
  local HOLD = 45
  local function anchor()
    pcall(function() game.overworld:setMap(MAP, MX, MY, "down") end)
    local still = 0
    for _ = 1, 1200 do
      coroutine.yield()
      local p = game.overworld and game.overworld.player
      if p and p.cellX == MX and p.cellY == MY then
        still = still + 1
        if still >= HOLD then return true end
      else
        still = 0
      end
    end
    return false
  end

  -- Sum love.timer.getDelta over N frames. The first frames after a rung
  -- change include a shader COMPILE, which is a one-off of tens of
  -- milliseconds and would swamp a short window -- hence the warm-up, which
  -- is thrown away, before the window that counts.
  -- VSYNC OFF, or this measures the monitor.
  --
  -- The first run of this came back 16.89 ms for ao and 16.72 ms for rt --
  -- both of them one 60Hz frame, to within noise, and both of them therefore
  -- the refresh rate rather than the renderer. A rung that fits inside the
  -- frame budget and a rung that fits inside it with room to spare are the
  -- same number under vsync, and telling them apart is the entire question
  -- being asked here.
  pcall(love.window.setVSync, 0)
  log("vsync: " .. tostring(pcall(love.window.getVSync) and
                            select(2, pcall(love.window.getVSync))))

  local WARM, WINDOW = 120, 300
  local function timeRung(rung)
    RayFX.setting:sync(rung)
    anchor()
    wait(WARM)
    local total, worst = 0, 0
    for _ = 1, WINDOW do
      coroutine.yield()
      local dt = love.timer.getDelta() or 0
      total = total + dt
      if dt > worst then worst = dt end
    end
    local mean = total / WINDOW
    log(("%-4s  mean %6.2f ms (%5.1f fps)   worst %6.2f ms   res=%s")
        :format(rung, mean * 1000, mean > 0 and 1 / mean or 0, worst * 1000,
                tostring(Quality.setting and Quality.setting:get())))
    shot(("rt_cost_%s.png"):format(rung))
    return mean
  end

  log("window: " .. WINDOW .. " frames after " .. WARM .. " warm-up, at "
      .. MAP .. " (" .. MX .. "," .. MY .. "), night, weather off")
  -- ao twice, first and last: the pair brackets the whole run, so thermal
  -- drift on a laptop shows up as the two ao readings disagreeing rather
  -- than as rt looking cheaper or dearer than it is.
  local ao1 = timeRung("ao")
  local rt = timeRung("rt")
  local ao2 = timeRung("ao")

  local base = (ao1 + ao2) * 0.5
  log(("\nao drift over the run: %+.2f ms (%.1f%%)")
      :format((ao2 - ao1) * 1000, base > 0 and (ao2 - ao1) / base * 100 or 0))
  log(("rt over ao: %+.2f ms per frame (%+.1f%%)")
      :format((rt - base) * 1000, base > 0 and (rt - base) / base * 100 or 0))

  logf:close()
  love.event.quit()
end
