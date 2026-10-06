-- Cerulean's ground (tools/cerulean_ground.py, stood by LavenderGroundKit) and
-- the four roads out of it: it builds, walkers stand ON the paving, and what
-- it looks like from the player's own camera, by day and by night, and at
-- each of the four joins. Settings are synced in memory, never saved.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/cerulean_ground_probe.log", "w"))
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

  enter("CERULEAN_CITY", 20, 19)
  local n = count("cerground_")
  log("cerulean ground quads=" .. n)
  check(n > 10000, "the ground was laid: " .. n)
  check(not Buildings.lastError, "building error=" .. tostring(Buildings.lastError))
  -- a walker stands on the paving (lift), not on the drawn tile
  local groundAt = Scene.groundAt
  if groundAt then
    local h = groundAt(game.overworld.map, 20, 18)
    check(h and h >= 1, "a walker stands on the stones: groundAt=" .. tostring(h))
  end
  shot("centre_player")
  shot("centre_player_night", nil, nil, "night")
  shot("overview", { 330, 300, 640 }, { 330, 20, 300 })
  shot("gym_plaza", { 500, 110, 420 }, { 488, 4, 330 })
  shot("streets_close", { 260, 90, 380 }, { 250, 2, 300 })
  enter("CERULEAN_CITY", 12, 13)
  shot("north_player")
  enter("CERULEAN_CITY", 13, 27)
  shot("bike_player")
  enter("CERULEAN_CITY", 13, 32)
  shot("lanes_player")
  enter("CERULEAN_CITY", 21, 6)
  shot("bridge_path_player")
  enter("CERULEAN_CITY", 36, 17)
  shot("east_player")
  -- the joins: each road, from its side of the edge
  enter("ROUTE_5", 3, 3)
  shot("route5_join_player")
  enter("ROUTE_24", 11, 32)
  shot("route24_join_player")
  enter("ROUTE_4", 86, 10)
  shot("route4_join_player")
  enter("ROUTE_9", 4, 8)
  shot("route9_join_player")
  file:close()
  love.event.quit()
end
