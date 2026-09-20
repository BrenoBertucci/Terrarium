-- One look at Route 8's marked lane: kerbs and bollards standing on it.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  for _ = 1, 1200 do
    if game.overworld and game.stack and game.stack:top() == game.overworld then break end
    if game.input then game.input.pressQueue[#game.input.pressQueue + 1] = "a" end
    coroutine.yield()
  end
  local lib = game.mods.exports.TERRARIUM.lib
  local Cam = lib.require("MarioCam")
  require("src.render.Pipelines").setLevel("terrarium_voxel", 4)
  require("src.render.Pipelines").setLevel("terrarium_tiltshift", 0)
  lib.require("Weather").setting:sync("off")
  lib.require("AutoFarm").setting:sync("off")
  lib.require("DayNight").setting:sync("day")
  Cam.setting:sync("on")
  local camera, original = nil, Cam.camera
  Cam.camera = function() return camera or original() end
  local function settle(n)
    for _ = 1, n do
      for _, d in ipairs({ "up", "down", "left", "right" }) do game.input.state[d] = false end
      game.input.pressQueue = {}
      coroutine.yield()
    end
  end
  game.overworld:setMap("ROUTE_8", 27, 5, "down")
  settle(900)
  for name, c in pairs({ lane_close = { { 430, 40, 150 }, { 420, 0, 76 } },
                         lane_wide = { { 470, 110, 260 }, { 470, 0, 100 } } }) do
    camera = { eye = c[1], focus = c[2], fov = math.rad(45), curve = 0 }
    settle(150)
    local pending = true
    love.graphics.captureScreenshot(function(data)
      local f = assert(io.open(out .. "/" .. name .. ".png", "wb"))
      f:write(data:encode("png"):getString()); f:close(); pending = false
    end)
    for _ = 1, 120 do if not pending then break end; settle(1) end
  end
  Cam.camera = original
  love.event.quit()
end
