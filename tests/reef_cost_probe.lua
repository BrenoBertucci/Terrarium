-- What the bridges (lib/BridgeKit.lua) cost a frame on Route 12, the longest
-- pier there is: kit off, on, on, off -- a palindrome, so warm-up and heat
-- charge both sides alike.
-- Settings are synced in memory, never saved by this probe.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/reef_cost_probe.log", "w"))
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
    log(("[%s] bridge quads=%d"):format(mapId, n))
    check(n > 0, mapId .. " has a bridge")
    check(not Buildings.lastError, "building error=" .. tostring(Buildings.lastError))
    check(Scene.groundAt(game.overworld.map, cx, cy) == lib.require("BridgeKit").DECK,
          "a walker stands ON the deck: " .. tostring(Scene.groundAt(game.overworld.map, cx, cy)))
  end

  local Kit, Mesher = lib.require("ReefKit"), lib.require("ChunkMesher")
  local function measure(enabled)
    Kit.ENABLED = enabled
    Mesher.invalidate()
    enter("ROUTE_12", 10, 64)
    settle(900)
    love.window.setVSync(0)
    local sum, n = 0, 400
    for _ = 1, n do
      local a = love.timer.getTime()
      settle(1)
      sum = sum + (love.timer.getTime() - a)
    end
    love.window.setVSync(1)
    local groups = Mesher.spriteGroups(game.overworld.map) or {}
    local boxed, draws, real = 0, 0, Voxel.draw
    for _, g in ipairs(groups) do if g.box then boxed = boxed + 1 end end
    Voxel.draw = function(...) draws = draws + 1; return real(...) end
    settle(8)
    Voxel.draw = real
    log(("  sprite groups=%d boxed=%d, Voxel.draw calls a step=%.1f"):format(#groups, boxed, draws / 8))
    log(("reef %s  mean %.2f ms a step"):format(enabled and "ON " or "OFF", sum / n * 1000))
  end
  measure(false) measure(true) measure(true) measure(false)
  Kit.ENABLED = nil
  file:close()
  love.event.quit()
end
