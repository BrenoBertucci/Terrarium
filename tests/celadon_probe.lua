-- Celadon's ground (tools/celadon_ground.py, stood by LavenderGroundKit)
-- and its fences (lib/FenceKit.lua): they build, walkers stand ON the paving,
-- and what it looks like. Settings are synced in memory, never saved.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/celadon_probe.log", "w"))
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
    for _ = 1, 2400 do
      if Structures.peek(game.overworld.map) and Voxel.lampLights then break end
      settle(1)
    end
    settle(300)
  end

  enter(37, 12)
  local map = game.overworld.map
  local S = Structures.forMap(map)
  local n = 0
  for _, q in ipairs(S.spriteQuads or {}) do
    if type(q.tex) == "string" and q.tex:find("celground_", 1, true) then n = n + 1 end
  end
  log("ground quads=" .. n)
  check(not Buildings.lastError, "building error=" .. tostring(Buildings.lastError))
  check(n > 8000 and n < 40000, "the ground is laid, within budget: " .. n)
  check(Voxel.shader() ~= nil and not Voxel.shaderError, "voxel shader compiled")
  check(Scene.groundAt(map, 37, 12) == 1, "a walker stands ON the rose: " .. tostring(Scene.groundAt(map, 37, 12)))
  shot("rose_player")
  shot("rose_high", { 592, 150, 330 }, { 592, 0, 192 })
  shot("boulevard", { 300, 80, 300 }, { 420, 0, 190 })
  enter(9, 15)
  shot("store_player")
  enter(22, 23)
  shot("pond_player")
  shot("pond_close", { 368, 60, 430 }, { 368, 0, 330 })
  shot("pond_night", { 368, 60, 430 }, { 368, 0, 330 }, "night")
  enter(30, 20)
  shot("promenade_player")
  enter(10, 2)
  shot("lawn_player")
  shot("overview", { 400, 380, 640 }, { 400, 0, 250 })
  file:close()
  love.event.quit()
end
