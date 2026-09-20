-- Vermilion's six houses (lib/VermilionHouseKit.lua): all six build, their
-- doors' cells stay walkable, and what each looks like, by day and after dark.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/vermilion_houses_probe.log", "w"))
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

  enter(19, 5)
  local map = game.overworld.map
  local S = Structures.forMap(map)
  local n = 0
  for _, q in ipairs(S.spriteQuads or {}) do
    if q.tex == "assets/buildings/vermilion_houses.png" then n = n + 1 end
  end
  log("house quads=" .. n)
  check(not Buildings.lastError, "building error=" .. tostring(Buildings.lastError))
  check(n > 40000 and n < 110000, "six houses stand, within budget: " .. n)
  check(Voxel.shader() ~= nil and not Voxel.shaderError, "voxel shader compiled")
  for name, c in pairs({ rod = { 7, 3 }, club = { 9, 13 }, trade = { 15, 13 }, pidgey = { 23, 19 } }) do
    check(map:isWalkableCell(c[1], c[2]), name .. ": the door's cell is still walkable")
  end
  local HOUSES = { { "rod", 96, 0 }, { "captain", 224, 0 }, { "light", 320, 0 },
                   { "club", 128, 160 }, { "trade", 224, 160 }, { "pidgey", 352, 256 } }
  for _, h in ipairs(HOUSES) do
    shot("house_" .. h[1], { h[2] + 60, 86, h[3] + 170 }, { h[2] + 32, 22, h[3] + 40 })
  end
  shot("row_north", { 250, 120, 250 }, { 250, 20, 30 })
  shot("row_north_night", { 250, 120, 250 }, { 250, 20, 30 }, "night")
  shot("player_avenue")
  enter(19, 14)
  shot("player_waterfront")
  shot("player_waterfront_night", nil, nil, "night")
  shot("overview", { 330, 330, 560 }, { 320, 0, 180 })
  file:close()
  love.event.quit()
end
