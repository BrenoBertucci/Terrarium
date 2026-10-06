-- The ground of Pallet, Viridian and Pewter (tools/west_ground.py, stood by
-- LavenderGroundKit) and the four roads between them: it builds, walkers stand
-- ON the paving, and what each town looks like from the player's own camera,
-- by day and by night, and at the joins. Settings are synced in memory.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/west_ground_probe.log", "w"))
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
  local Mesher = lib.require("ChunkMesher")
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
    camera = eye and { eye = eye, focus = focus, fov = math.rad(40), curve = 0 } or nil
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
  local function enter(mapId, cx, cy)
    Voxel.lampLights = nil
    game.overworld:setMap(mapId, cx, cy, "down")
    for _ = 1, 20000 do
      if Structures.peek(game.overworld.map) and Voxel.lampLights then break end
      settle(1)
    end
    local waited = 0
    while Mesher.pending() > 0 and waited < 20000 do settle(1); waited = waited + 1 end
    settle(200)
  end
  local function count(prefix)
    local n = 0
    for _, q in ipairs(Structures.forMap(game.overworld.map).spriteQuads or {}) do
      if q.tex and q.tex:find(prefix, 1, true) then n = n + 1 end
    end
    return n
  end

  local function town(mapId, cx, cy, tag)
    enter(mapId, cx, cy)
    local n = count("westground_")
    log(tag .. " ground quads=" .. n)
    check(n > 3000, tag .. ": the ground was laid: " .. n)
    check(not Buildings.lastError, tag .. ": building error=" .. tostring(Buildings.lastError))
    local h = Scene.groundAt and Scene.groundAt(game.overworld.map, cx, cy)
    check(h and h >= 1, tag .. ": a walker stands on the stones: groundAt=" .. tostring(h))
    shot(tag .. "_player")
  end
  town("VIRIDIAN_CITY", 19, 12, "viridian")
  shot("viridian_player_night", nil, nil, "night")
  shot("viridian_overview", { 330, 300, 640 }, { 320, 20, 300 })
  shot("viridian_leaf", { 300, 100, 390 }, { 296, 2, 304 })
  enter("VIRIDIAN_CITY", 23, 27)
  shot("viridian_centre_player")
  town("PALLET_TOWN", 5, 7, "pallet")
  shot("pallet_player_night", nil, nil, "night")
  shot("pallet_overview", { 160, 240, 400 }, { 160, 10, 150 })
  town("PEWTER_CITY", 13, 18, "pewter")
  shot("pewter_player_night", nil, nil, "night")
  shot("pewter_overview", { 330, 300, 640 }, { 320, 20, 300 })
  shot("pewter_ammonite", { 236, 90, 230 }, { 232, 2, 152 })
  enter("PEWTER_CITY", 14, 9)
  shot("pewter_museum_player")
  -- the joins
  enter("ROUTE_1", 11, 2)
  shot("route1_north_player")
  enter("ROUTE_1", 11, 33)
  shot("route1_south_player")
  enter("ROUTE_2", 18, 68)
  shot("route2_south_player")
  enter("ROUTE_22", 36, 9)
  shot("route22_player")
  enter("ROUTE_3", 2, 9)
  shot("route3_player")
  file:close()
  love.event.quit()
end
