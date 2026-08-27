-- Probe: WHY the rain looks soft.
--
-- "It looks bad" is a real finding and a useless one to act on, because
-- there are three separate things in this pipeline that could be softening
-- the streaks and they are all invisible from inside Weather.lua:
--
--   THE RESOLUTION. Quality.scale() defaults to 2, so the diorama is
--   rasterised at half the window's pixels. If the overlay is inside that,
--   a one-pixel streak arrives on screen two pixels wide and interpolated.
--
--   THE TILT-SHIFT. Weather.draw runs inside drawWorld, and worldPresent
--   blurs that whole canvas afterwards. The radar and the start menu are
--   already re-painted after the blur for exactly this reason -- nobody
--   ever asked whether the rain should be too.
--
--   THE RAIN ITSELF, i.e. streaks genuinely drawn too thick and too bright.
--
-- Four frames of the SAME shower, same map, same wind, same hour, with the
-- first two switched independently. Then the streak widths are measured off
-- the four PNGs, and whichever pair differs is the answer.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/rain_look_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/rain_look.log", "w"))
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
    wait(5)
  end

  love.math.setRandomSeed(20260819)

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit() return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11; if n > 1500 then break end
  end

  local lib = game.mods.exports.TERRARIUM.lib
  local Weather = lib.require("Weather")
  local Wind = lib.require("Wind")
  local DayNight = lib.require("DayNight")
  local Quality = lib.require("Quality")
  local Voxel3D = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")

  Wind.climateTarget = function()
    Wind.gustNow = 0.35
    return 0.42
  end
  DayNight.setting:sync("day")
  Weather.setting:sync("rain")
  Pipelines.setLevel("terrarium_voxel", 5)

  local function wait3D(cap)
    for i = 1, (cap or 900) do
      if Voxel3D.lampLights ~= nil then return i end
      coroutine.yield()
    end
    return -1
  end
  Voxel3D.lampLights = nil
  game.overworld:setMap("VIRIDIAN_CITY", 10, 10, "up")
  log("3D up after " .. tostring(wait3D(900)) .. " frames")
  wait(90)
  Weather.pin("rain", 1.0)
  wait(90)

  log(("RES default = %d   (1 = full window pixels)"):format(Quality.scale()))

  -- Four combinations. RES is a mod row and T-SHIFT is a pipeline level, so
  -- each is set through the thing that owns it rather than poked directly.
  local combos = {
    { res = 2, tilt = 2, tag = "res2_tilt2" },   -- what ships
    { res = 2, tilt = 0, tag = "res2_tilt0" },
    { res = 1, tilt = 2, tag = "res1_tilt2" },
    { res = 1, tilt = 0, tag = "res1_tilt0" },
  }
  for _, c in ipairs(combos) do
    Quality.setting:sync(c.res)
    pcall(Pipelines.setLevel, "terrarium_tiltshift", c.tilt)
    -- the scene canvas is re-slotted when RES changes, so let it rebuild
    Voxel3D.invalidate()
    Voxel3D.lampLights = nil
    wait(30)
    wait3D(600)
    wait(90)
    Weather.pin("rain", 1.0)
    wait(45)
    log(("%s: RES=%d tilt=%s shafts=%d"):format(
        c.tag, Quality.scale(), tostring(c.tilt), Weather.shaftDump()))
    shot(("L_%s.png"):format(c.tag))
  end

  log("done")
  logf:close()
  love.event.quit()
end
