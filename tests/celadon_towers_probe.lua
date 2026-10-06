-- Celadon's ground (tools/celadon_ground.py, stood by LavenderGroundKit)
-- and its fences (lib/FenceKit.lua): they build, walkers stand ON the paving,
-- and what it looks like. Settings are synced in memory, never saved.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/celadon_towers_probe.log", "w"))
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

  local t0 = love.timer.getTime()
  enter(37, 12)
  log(("entered and built in %.1f s"):format(love.timer.getTime() - t0))
  local map = game.overworld.map
  local S = Structures.forMap(map)
  local n = 0
  for _, q in ipairs(S.spriteQuads or {}) do
    if q.tex == "assets/buildings/celadon_towers.png" then n = n + 1 end
  end
  log("tower quads=" .. n)
  check(not Buildings.lastError, "building error=" .. tostring(Buildings.lastError))
  -- Houses are short shells (a roof and a wall), so the floor only catches a
  -- kit that failed to build. The ceiling is still the per-voxel blow-up.
  check(n > 4000 and n < 160000, "the skyline stands, within budget: " .. n)
  check(Voxel.shader() ~= nil and not Voxel.shaderError, "voxel shader compiled: " .. tostring(Voxel.shaderError))
  for name, c in pairs({ store = { 8, 13 }, mansion = { 24, 9 }, centre = { 41, 9 }, gym = { 12, 27 },
                         casino = { 28, 19 }, hotel = { 43, 27 }, diner = { 31, 27 } }) do
    check(map:isWalkableCell(c[1], c[2]), name .. ": the door's cell is still walkable")
  end
  shot("plaza_player")
  shot("skyline", { 400, 260, 900 }, { 400, 60, 250 })
  shot("skyline_night", { 400, 260, 900 }, { 400, 60, 250 }, "night")
  shot("north_row", { 420, 130, 330 }, { 380, 70, 110 })
  shot("store", { 170, 120, 420 }, { 150, 70, 180 })
  enter(9, 15)
  shot("store_player")
  enter(30, 22)
  shot("street_player")
  shot("street_player_night", nil, nil, "night")
  enter(43, 28)
  shot("hotel_player")
  file:close()
  love.event.quit()
end
