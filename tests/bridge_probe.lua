-- Bridges and piers (lib/BridgeKit.lua): they build without an error, a
-- walker stands ON the deck, the water runs under it, and what it looks like.
-- Settings are synced in memory, never saved by this probe.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/bridge_probe.log", "w"))
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
  local reefAt = nil
  local function enter(mapId, cx, cy)
    Voxel.lampLights = nil
    game.overworld:setMap(mapId, cx, cy, "down")
    for _ = 1, 2400 do
      if Structures.peek(game.overworld.map) and Voxel.lampLights then break end
      settle(1)
    end
    settle(240)
    local S = Structures.forMap(game.overworld.map)
    local n = 0
    for _, q in ipairs(S.spriteQuads or {}) do
      if q.tex == "assets/buildings/bridge_kit.png" then n = n + 1 end
    end
    local reef = 0
    for _, q in ipairs(S.spriteQuads or {}) do
      if q.tex == "assets/buildings/reef_kit.png" then reef = reef + 1 end
    end
    log(("[%s] bridge quads=%d reef quads=%d"):format(mapId, n, reef))
    -- the reef cell nearest the player, for the shots to look at
    local px, pz, best = cx * 16 + 8, cy * 16 + 8, nil
    for _, q in ipairs(S.spriteQuads or {}) do
      if q.tex == "assets/buildings/reef_kit.png" then
        local d = (q[1][1] - px) ^ 2 + (q[1][3] - pz) ^ 2
        if not best or d < best.d then best = { d = d, x = q[1][1], z = q[1][3] } end
      end
    end
    reefAt = best
    if best then log(("  nearest reef at %d,%d"):format(best.x, best.z)) end
    check(n > 0, mapId .. " has a bridge")
    check(not Buildings.lastError, "building error=" .. tostring(Buildings.lastError))
    check(Voxel.shader() ~= nil and not Voxel.shaderError, "voxel shader compiled: " .. tostring(Voxel.shaderError))
    check(Scene.groundAt(game.overworld.map, cx, cy) == lib.require("BridgeKit").DECK,
          "a walker stands ON the deck: " .. tostring(Scene.groundAt(game.overworld.map, cx, cy)))
  end

  enter("ROUTE_12", 10, 12)
  shot("r12_player")
  shot("r12_low", { 60, 40, 330 }, { 150, 0, 200 })
  shot("r12_close", { 40, 30, 300 }, { 110, 4, 215 })
  shot("r12_close_night", { 40, 30, 300 }, { 110, 4, 215 }, "night")
  shot("r12_night", { 60, 40, 330 }, { 150, 0, 200 }, "night")
  enter("ROUTE_12", 10, 64)
  shot("r12_reef_player")
  shot("r12_bank_close", { 110, 22, 1075 }, { 60, -2, 1040 })
  shot("r12_garden_wide", { 250, 70, 1130 }, { 215, -6, 1040 })
  shot("r12_garden_close", { 235, 30, 1085 }, { 225, -8, 1040 })
  shot("r12_garden_night", { 250, 70, 1130 }, { 215, -6, 1040 }, "night")
  if reefAt then
    local x, z = reefAt.x, reefAt.z
    shot("r12_reef", { x, 50, z + 45 }, { x, -8, z })
    shot("r12_reef_top", { x, 90, z + 12 }, { x, -8, z })
  end
  enter("ROUTE_24", 10, 20)
  shot("r24_player")
  shot("r24_low", { 60, 36, 470 }, { 176, 0, 330 })
  enter("ROUTE_13", 50, 6)
  shot("r13_player")
  file:close()
  love.event.quit()
end
