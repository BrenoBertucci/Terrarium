-- The ground of Saffron, Fuchsia (and Routes 15, 18) and Cinnabar
-- (tools/saffron_ground.py, fuchsia_ground.py, cinnabar_ground.py): each
-- builds, walkers stand ON the paving, and what each looks like from the
-- player's own camera, by day and by night. Settings are synced in memory.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/south_ground_probe.log", "w"))
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

  local function town(mapId, cx, cy, tag, prefix)
    enter(mapId, cx, cy)
    local n = count(prefix)
    log(tag .. " ground quads=" .. n)
    check(n > 3000, tag .. ": the ground was laid: " .. n)
    check(not Buildings.lastError, tag .. ": building error=" .. tostring(Buildings.lastError))
    local h = Scene.groundAt and Scene.groundAt(game.overworld.map, cx, cy)
    check(h and h >= 1, tag .. ": a walker stands on the stones: groundAt=" .. tostring(h))
    shot(tag .. "_player")
  end
  town("SAFFRON_CITY", 20, 7, "saffron", "saffground_")
  shot("saffron_player_night", nil, nil, "night")
  shot("saffron_overview", { 330, 320, 700 }, { 320, 20, 300 })
  enter("SAFFRON_CITY", 18, 22)
  shot("saffron_silph_player")
  town("FUCHSIA_CITY", 19, 28, "fuchsia", "fuchground_")
  shot("fuchsia_player_night", nil, nil, "night")
  shot("fuchsia_overview", { 330, 320, 700 }, { 320, 20, 300 })
  enter("FUCHSIA_CITY", 18, 5)
  shot("fuchsia_safari_player")
  enter("FUCHSIA_CITY", 26, 12)
  shot("fuchsia_north_player")
  enter("ROUTE_15", 20, 6)
  shot("route15_player")
  town("CINNABAR_ISLAND", 11, 12, "cinnabar", "cinnground_")
  shot("cinnabar_player_night", nil, nil, "night")
  shot("cinnabar_overview", { 170, 240, 420 }, { 160, 10, 150 })
  enter("CINNABAR_ISLAND", 17, 5)
  shot("cinnabar_gym_player")
  file:close()
  love.event.quit()
end
