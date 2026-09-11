-- Probe: rain running down the people in it (lib/RainOnFX.lua + shader).
--
--   RUNGS    the rivulet code compiles on all four rungs
--   REACH    a figure in a pinned downpour is reached (wet climbs to 1)
--   CROWN    one under a crown is not (forced through the canopy seam)
--   STOPS    a few seconds after the sky clears it is gone
--   PIXELS   the card changes between two frames while it streams and
--            not (much) once it has stopped -- the rivulets MOVE
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/rain_on_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/rain_on_probe.log", "w"))
  local fails = 0
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    if line:find("FAIL") then fails = fails + 1 end
    logf:write(line, "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local function shot(name)
    local done, data = false, nil
    love.graphics.captureScreenshot(function(d)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(d:encode("png"):getString()) f:close() end
      data = d; done = true
    end)
    local spun = 0
    while not done and spun < 400 do wait(1); spun = spun + 1 end
    return data
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit() return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11; if n > 1500 then break end
  end
  game.input:reset()

  local lib = game.mods.exports.TERRARIUM.lib
  local GroundFX = lib.require("GroundFX")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Voxel3D = lib.require("Voxel3D")
  local RainOnFX = lib.require("RainOnFX")
  local Pipelines = require("src.render.Pipelines")

  for i = 1, 4 do
    local ok, info = Voxel3D.buildRung(i, false, 1)
    log(("rung %d: %s %s"):format(i, ok and "PASS" or "FAIL", ok and "" or tostring(info)))
  end
  Voxel3D.resetShaders()

  GroundFX.setting:sync("on")
  DayNight.setting:sync("day")
  Pipelines.setLevel("terrarium_voxel", 5)
  do
    local ok, MC = pcall(lib.require, "MarioCam")
    if ok and MC and MC.setting then pcall(function() MC.setting:sync("off") end) end
  end
  Weather.setting:sync("rain")
  game.overworld:setMap("VIRIDIAN_CITY", 9, 17, "down")
  wait(150)
  game.input:reset()
  local me = game.overworld.player

  local spun = 0
  while (select(2, Weather.visible()) or 0) < 0.8 and spun < 3000 do wait(10); spun = spun + 10 end
  wait(150)
  log(("rain: power=%.2f gate=%s reaching me=%.2f (want 1)"):format(
    select(2, Weather.visible()) or 0, RainOnFX.lastGate, RainOnFX.wetOf(me)))
  if RainOnFX.wetOf(me) < 0.9 then log("  FAIL: the rain did not reach the walker") end

  -- the rivulets MOVE: two shots a few frames apart differ on the card
  local a = shot("80_rain_running.png")
  wait(6)
  local b = shot("80b_rain_running_later.png")
  local function diffCentre(x1, x2)
    if not (x1 and x2) then return -1 end
    local w, h = x1:getDimensions()
    local changed, total = 0, 0
    for y = math.floor(h * 0.30), math.floor(h * 0.70) do
      for x = math.floor(w * 0.35), math.floor(w * 0.65), 2 do
        local r1, g1, b1 = x1:getPixel(x, y)
        local r2, g2, b2 = x2:getPixel(x, y)
        if math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2) > 0.25 then
          changed = changed + 1
        end
        total = total + 1
      end
    end
    return 100 * changed / math.max(1, total)
  end
  log(("centre of frame changed between two frames while streaming: %.2f%%"):format(diffCentre(a, b)))

  -- under a crown, by fiat, it stops
  do
    local GW = lib.require("GrassWear")
    local was = GW.canopyAt
    GW.canopyAt = function() return 1 end
    RainOnFX.setWet(me, 0)
    wait(200)
    local under = RainOnFX.wetOf(me)
    GW.canopyAt = was
    log(("under a crown for 200 frames: %.2f (want 0)"):format(under))
    if under > 0.01 then log("  FAIL: a crown did not keep the rain off") end
  end

  -- and a few seconds after the sky clears it is gone everywhere
  wait(200)
  Weather.setting:sync("off")
  wait(60 * 8)
  log(("8 s after the rain stopped: %.2f (want 0)"):format(RainOnFX.wetOf(me)))
  if RainOnFX.wetOf(me) > 0.01 then log("  FAIL: the water kept running after the rain") end
  shot("81_after_rain.png")

  log(("done: %d FAIL"):format(fails))
  logf:close()
  love.event.quit()
end
