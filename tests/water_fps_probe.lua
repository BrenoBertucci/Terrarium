-- Probe: WHAT THE WATER COSTS. Frame timing on the two wettest shots, at the
-- rungs the player actually runs (FULL, RTX MAX, ANIME FULL, V-CURVE 3 --
-- options.lua at the build root), weather off and the hour pinned so the
-- two halves of an A/B see the same frame. Palindrome (lake, sea, lake): the
-- first spot pays the warm-up, and the two lake readings bracket it.
--
-- Run it twice -- once with the committed lib/ in the build, once with the
-- working tree -- and compare the logs. Run nothing else on the GPU meanwhile.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/water_fps_probe.lua ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local TAG = os.getenv("DS_PROBE_TAG") or "run"
  local logf = assert(io.open(OUT .. "/water_fps_" .. TAG .. ".log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local function finish(msg)
    if msg then log(msg) end
    logf:close()
    love.event.quit()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then return finish("FAIL: no overworld") end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then return finish("FAIL: TERRARIUM not loaded") end
  log("version:", exports.TERRARIUM.version, "tag:", TAG)

  local Weather   = lib.require("Weather")
  local DayNight  = lib.require("DayNight")
  local Quality   = lib.require("Quality")
  local RayFX     = lib.require("RayFX")
  local Voxel3D   = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")
  local function sync(setting, v)
    if setting then pcall(setting.sync, setting, v) end
  end
  sync(Weather.setting, "off")
  sync(DayNight.setting, "day")
  sync(Quality.setting, 1)          -- FULL
  sync(RayFX.setting, "max")
  pcall(Pipelines.setLevel, "terrarium_voxel", 5)
  log("rtx:", tostring(RayFX.setting:get()), "res:", tostring(Quality.setting:get()))

  local function wait3D(cap)
    for i = 1, (cap or 900) do
      if Voxel3D.lampLights ~= nil then return i end
      coroutine.yield()
    end
    return -1
  end

  local SPOTS = {
    { id = "ROUTE_25", x = 37, y = 12 },
    { id = "ROUTE_21", x = 7,  y = 24 },
    { id = "ROUTE_25", x = 37, y = 12 },
  }
  for i, sp in ipairs(SPOTS) do
    local ok = pcall(function() game.overworld:setMap(sp.id, sp.x, sp.y, "up") end)
    if not ok then
      log(("[%d %s] SKIP: setMap failed"):format(i, sp.id))
    else
      Voxel3D.lampLights = nil
      local up = wait3D(900)
      wait(240)
      -- 600 updates; at POKEPORT_SPEED=4 that is ~150 presents, and the
      -- wall clock over them is what the player feels
      local t0 = love.timer.getTime()
      for _ = 1, 600 do coroutine.yield() end
      local dt = love.timer.getTime() - t0
      log(("[%d %s] 3D up after %d; 600 updates in %.2fs = %.1f updates/s; getFPS=%.1f")
          :format(i, sp.id, up, dt, 600 / dt, love.timer.getFPS()))
    end
  end
  finish("done")
end
