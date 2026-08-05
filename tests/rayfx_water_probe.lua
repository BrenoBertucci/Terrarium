-- Probe: the RTX row's water test, with the world CURVED.
--
-- The bug this exists for: the pass identifies water geometrically -- the one
-- class that stands below zero -- and read that height straight out of the
-- depth buffer, which records the world after the V-CURVE has bent it down
-- over the horizon. Past a certain radius every pixel in the frame stood
-- below the water ceiling, so the whole distant world was classified as a
-- pond and reflected the sky.
--
-- It is a screen-space effect on a curved world, so there is nothing to
-- count: the claim is about what the frame LOOKS like, and the only honest
-- test is a picture of a route with no water in it at the curve rung the bug
-- needs. Shot at both V-CURVE OFF and V-CURVE 3, on a map with water and a
-- map without, so the four together say which variable moved.
--
--   POKEPORT_VERSION=yellow \
--   DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/rayfx_water_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/rayfx_water_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n")
    logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(btn)
    game.input.pressQueue[#game.input.pressQueue + 1] = btn
    coroutine.yield()
  end
  local function shot(name)
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
    wait(3)
  end

  love.math.setRandomSeed(20260801)

  local frames = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); frames = frames + 1
    if frames > 900 then log("FAIL: no overworld") logf:close()
      love.event.quit() return end
  end
  frames = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); frames = frames + 11
    if frames > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit()
    return
  end
  log("version:", exports.TERRARIUM.version)

  local RayFX = lib.require("RayFX")
  local WorldCurve = lib.require("WorldCurve")
  local Water = lib.require("Water")
  local Voxel3D = lib.require("Voxel3D")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Pipelines = require("src.render.Pipelines")

  -- every rung has its own compilation behind a define; a rung that will not
  -- build fails silently by design, so ask each one
  for _, rung in ipairs({ "ao", "rt", "max" }) do
    log(("compile %-3s -> %s%s"):format(rung, tostring(RayFX.compile(rung)),
        RayFX.shaderError and (" [" .. tostring(RayFX.shaderError) .. "]") or ""))
  end
  if RayFX.shaderError then log("  FAIL: a rung did not build") end

  Weather.setting:sync("off")
  DayNight.setting:sync("day")
  RayFX.setting:sync("max")
  Pipelines.setLevel("terrarium_voxel", 5)

  local function frame(map, x, y, curve, tag)
    WorldCurve.setting:sync(curve)
    game.overworld:setMap(map, x, y, "up")
    wait(200)
    log(("%-28s curve=%s k=%.5f swell=%.2f"):format(
      tag, tostring(WorldCurve.setting:get()),
      Voxel3D.curveK or 0, Water.swell() or 0))
    shot(tag .. ".png")
  end

  -- ROUTE_1 has no water on it at all, so ANY reflection in these two is the
  -- bug. The pair is the test: same map, same hour, one variable.
  frame("ROUTE_1", 8, 12, 0, "40_route1_nowater_curveOFF")
  frame("ROUTE_1", 8, 12, 3, "41_route1_nowater_curve3")

  -- and a map that does have a pond, so the fix is not "the reflections are
  -- gone" -- the water still has to reflect at both rungs. The bank is FOUND
  -- rather than written down: a coordinate typed into a probe is a
  -- coordinate that is wrong on the next dataset, and a shot of the wrong
  -- corner of a town looks exactly like a reflection that stopped working.
  local function bankOf(mapId)
    game.overworld:setMap(mapId, 5, 5, "up")
    wait(60)
    local m = game.overworld.map
    for cy = 2, (m.height or 40) - 3 do
      for cx = 2, (m.width or 40) - 3 do
        if m:inBounds(cx, cy) and m:isWaterCell(cx, cy) then
          -- stand a couple of cells SOUTH of it, facing north, so the pond
          -- is between the camera and everything it could reflect
          for dy = 2, 5 do
            if m:isWalkableCell(cx, cy + dy) then return cx, cy + dy end
          end
        end
      end
    end
    return nil
  end

  local wx, wy = bankOf("VIRIDIAN_CITY")
  log(("VIRIDIAN_CITY bank: %s,%s"):format(tostring(wx), tostring(wy)))
  if wx then
    frame("VIRIDIAN_CITY", wx, wy, 0, "42_viridian_water_curveOFF")
    frame("VIRIDIAN_CITY", wx, wy, 3, "43_viridian_water_curve3")
  else
    log("FAIL: no water found on VIRIDIAN_CITY")
  end

  log("")
  log("done -- " .. OUT)
  logf:close()
  love.event.quit()
end
