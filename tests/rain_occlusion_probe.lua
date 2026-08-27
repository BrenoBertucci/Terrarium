-- Probe: does the rain stop falling inside the house?
--
-- The wind field solved this by becoming geometry. The weather cannot: its
-- shafts, crowns, jets and rings are procedural SCREEN-SPACE quads pushed
-- through their own shader, and that shader reads the frame behind them to
-- refract it. Handing them to the depth test as geometry would mean
-- rewriting all of it and losing the lens.
--
-- So instead every rain vertex now carries the DEVICE depth of the world
-- point it stands for (RAIN_FMT's RainDepth, from Voxel3D.projectDepth),
-- and both draw paths -- the refractive one and the cheap additive one --
-- discard a fragment that is deeper than the frame's own depth buffer at
-- that pixel.
--
-- ------- WHAT IS MEASURED
--
-- Weather.DEPTH_BIAS is set enormous to disable the test (everything
-- passes) and back to its real value to enable it, in ONE build, from ONE
-- pinned camera, with the shower pinned to a fixed power. So the two
-- frames differ by the test and by nothing else -- not by a reroll of the
-- field, not by the wind, not by the hour.
--
--   BRIGHT PIXELS ON THE ROOF   a box over the tallest building. The rain
--                               is added light on a dark roof, so pixels
--                               that got brighter are rain that landed in
--                               front of it. This has to fall.
--
--   BRIGHT PIXELS IN THE SKY    a box above the skyline, where there is
--                               nothing to be behind. This must NOT fall,
--                               or the test is not occluding, it is just
--                               deleting rain.
--
-- The second box is the control, and it is the only thing that stops a
-- broken shader from reading as a triumph.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/rain_occlusion_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/rain_occlusion.log", "w"))
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
    coroutine.yield(); coroutine.yield()
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

  local Weather  = lib.require("Weather")
  local Wind     = lib.require("Wind")
  local DayNight = lib.require("DayNight")
  local Quality  = lib.require("Quality")
  local GroundFX = lib.require("GroundFX")
  local Pipelines = require("src.render.Pipelines")

  DayNight.setting:sync("day")
  GroundFX.setting:sync("on")
  Wind.setting:sync(2)
  Quality.setting:sync(1)
  Weather.setting:sync("rain")
  Pipelines.setLevel("terrarium_voxel", 4)

  local CELL_X, CELL_Y = 12, 12
  local ow = game.overworld
  ow:setMap("PALLET_TOWN", CELL_X, CELL_Y, "up")
  wait(600)
  local p = ow.player
  log(("map %s  player %d,%d"):format(ow.map.id, p.cellX, p.cellY))

  Weather.pin("rain", 0.95)
  wait(300)

  local usable, hasTex = Weather.depthTestState()
  log(("depth test: surface usable=%s  buffer present=%s")
      :format(tostring(usable), tostring(hasTex)))
  if not hasTex then
    log("FAIL: no readable depth buffer -- the test cannot run and the")
    log("      rain cannot be occluded. Check Voxel3D.wantDepth.")
  end
  log(("shafts %d  splashes %d"):format(
      Weather.shaftDump(), Weather.moteCount("splash")))

  -- ------- OFF: a bias so large that nothing is ever behind anything
  local realBias = Weather.DEPTH_BIAS
  Weather.DEPTH_BIAS = 10
  wait(120)
  shot("rain_occl_off.png")
  wait(90)
  shot("rain_occl_off_ctl.png")

  -- ------- ALL: a bias so negative that EVERYTHING counts as behind
  --
  -- This is the wiring check, and it has to come before any argument about
  -- how much the real bias removes. If the plumbing is right this frame has
  -- no rain in it at all -- every fragment fails the compare and is
  -- discarded. If rain still falls here, the test is not running and every
  -- other number in this log is noise being read as a result.
  Weather.DEPTH_BIAS = -10
  wait(120)
  shot("rain_occl_all.png")
  wait(90)
  shot("rain_occl_all_ctl.png")

  -- ------- ON
  Weather.DEPTH_BIAS = realBias
  wait(120)
  log(("bias back to %.5f"):format(Weather.DEPTH_BIAS))
  shot("rain_occl_on.png")
  wait(90)
  shot("rain_occl_on_ctl.png")

  Weather.pin(nil, 0)
  log("done")
  logf:close()
  love.event.quit()
end
