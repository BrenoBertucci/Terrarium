-- Vermilion's ground (tools/vermilion_ground.py, stood by LavenderGroundKit)
-- and its fences (lib/FenceKit.lua): they build, walkers stand ON the paving,
-- and what it looks like. Settings are synced in memory, never saved.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/vermilion_probe.log", "w"))
  local function log(s) file:write(s, "\n"); file:flush() end
  local function check(ok, message) log((ok and "PASS " or "FAIL ") .. message) end
  for _ = 1, 1200 do
    if game.overworld and game.stack and game.stack:top() == game.overworld then break end
    if game.input then game.input.pressQueue[#game.input.pressQueue + 1] = "a" end
    coroutine.yield()
  end
  if not game.overworld then log("FAIL no overworld"); file:close(); love.event.quit(); return end
  local lib = game.mods.exports.TERRARIUM.lib
  local Buildings, Structures = lib.require("Buildings"), lib.require("Structures")
  local Scene, Cam = lib.require("VoxelScene"), lib.require("MarioCam")
  local Voxel, Day = lib.require("Voxel3D"), lib.require("DayNight")
  require("src.render.Pipelines").setLevel("terrarium_voxel", 4)
  require("src.render.Pipelines").setLevel("terrarium_tiltshift", 0)
  lib.require("AutoFarm").setting:sync("off")
  lib.require("Weather").setting:sync("off")
  Cam.setting:sync("on")
  local camera, originalCamera = nil, Cam.camera
  Cam.camera = function() return camera or originalCamera() end
  local function settle(n)
    for _ = 1, n do
      for _, d in ipairs({ "up", "down", "left", "right" }) do
        game.input.state[d] = false
        if game.input.sources then game.input.sources[d] = nil end
      end
      game.input.pressQueue = {}
      coroutine.yield()
    end
  end
  local function shot(name, eye, focus, hour)
    Day.setting:sync(hour or "day")
    camera = eye and { eye = eye, focus = focus, fov = math.rad(45), curve = 0 } or nil
    settle(150)
    local pending = true
    love.graphics.captureScreenshot(function(data)
      local f = assert(io.open(out .. "/" .. name .. ".png", "wb"))
      f:write(data:encode("png"):getString()); f:close(); pending = false
    end)
    for _ = 1, 120 do if not pending then break end; settle(1) end
    check(not pending, "captured " .. name)
    camera = nil
  end
  local function enter(cx, cy)
    Voxel.lampLights = nil
    game.overworld:setMap("VERMILION_CITY", cx, cy, "down")
    for _ = 1, 2400 do
      if Structures.peek(game.overworld.map) and Voxel.lampLights then break end
      settle(1)
    end
    settle(300)
  end

  enter(19, 7)
  local map = game.overworld.map
  local S = Structures.forMap(map)
  local ground, fence = 0, 0
  for _, q in ipairs(S.spriteQuads or {}) do
    if type(q.tex) == "string" and q.tex:find("vermground_", 1, true) then ground = ground + 1 end
    if q.tex == "assets/buildings/fence_kit.png" then fence = fence + 1 end
  end
  log(("ground quads=%d fence quads=%d"):format(ground, fence))
  check(not Buildings.lastError, "building error=" .. tostring(Buildings.lastError))
  check(ground > 10000 and ground < 60000, "the ground is laid, within budget: " .. ground)
  check(fence > 1000, "the fences stand: " .. fence)
  check(Voxel.shader() ~= nil and not Voxel.shaderError, "voxel shader compiled")
  check(Scene.groundAt(map, 19, 7) == 1, "a walker stands ON the sun: " .. tostring(Scene.groundAt(map, 19, 7)))
  check(Scene.groundAt(map, 30, 15) == 1, "and on the quay: " .. tostring(Scene.groundAt(map, 30, 15)))
  shot("sun_player")
  shot("sun_high", { 304, 150, 250 }, { 304, 0, 112 })
  shot("avenue", { 200, 70, 190 }, { 200, 0, 80 })
  shot("fence_park", { 470, 50, 130 }, { 470, 6, 56 })
  shot("fence_close", { 450, 26, 100 }, { 462, 8, 56 })
  shot("fence_lot", { 590, 60, 230 }, { 552, 6, 130 })
  enter(28, 15)
  shot("quay_player")
  shot("quay_low", { 400, 40, 320 }, { 470, 0, 236 })
  shot("quay_dusk", { 400, 40, 320 }, { 470, 0, 236 }, "dusk")
  enter(7, 15)
  shot("west_quay_player")
  shot("gym_yard", { 170, 90, 440 }, { 170, 0, 345 })
  shot("overview", { 330, 330, 560 }, { 320, 0, 180 })
  -- the two joins, from inside the town: a map's edge would show across these
  enter(18, 2)
  settle(1200)
  shot("join_north", { 304, 90, 120 }, { 304, 0, -60 })
  enter(37, 14)
  settle(1200)
  shot("join_east_player")
  shot("join_east", { 560, 110, 380 }, { 680, 0, 220 })
  game.overworld:setMap("ROUTE_11", 20, 9, "down")
  settle(1500)
  shot("route11_player")
  game.overworld:setMap("ROUTE_6", 9, 24, "down")
  settle(1500)
  shot("route6_player")
  check(not Buildings.lastError, "building error after the routes=" .. tostring(Buildings.lastError))
  file:close()
  love.event.quit()
end
