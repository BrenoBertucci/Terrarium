-- Celadon's ground (tools/celadon_ground.py, stood by LavenderGroundKit)
-- and its fences (lib/FenceKit.lua): they build, walkers stand ON the paving,
-- and what it looks like. Settings are synced in memory, never saved.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/celadon_routes_probe.log", "w"))
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
    game.overworld:setMap("CELADON_CITY", cx, cy, "down")
    for _ = 1, 20000 do
      if Structures.peek(game.overworld.map) and Voxel.lampLights then break end
      settle(1)
    end
    settle(300)
  end

  enter(30, 20)
  local map = game.overworld.map
  local S = Structures.forMap(map)
  local iron, ground = 0, 0
  for _, q in ipairs(S.spriteQuads or {}) do
    if q.tex == "assets/buildings/fence_iron.png" then iron = iron + 1 end
    if type(q.tex) == "string" and q.tex:find("celground_", 1, true) then ground = ground + 1 end
  end
  log(("iron fence quads=%d ground quads=%d"):format(iron, ground))
  check(not Buildings.lastError, "building error=" .. tostring(Buildings.lastError))
  check(iron > 1500, "the railings stand: " .. iron)
  shot("railing_player")
  shot("railing_close", { 470, 26, 372 }, { 480, 8, 338 })
  enter(47, 10)
  settle(1200)
  shot("join_east_player")
  enter(3, 18)
  settle(1200)
  shot("join_west_player")
  game.overworld:setMap("ROUTE_7", 5, 5, "down")
  settle(2500)
  shot("route7_player")
  game.overworld:setMap("ROUTE_16", 30, 10, "down")
  settle(2500)
  shot("route16_player")
  check(not Buildings.lastError, "building error after the routes=" .. tostring(Buildings.lastError))
  file:close()
  love.event.quit()
end
