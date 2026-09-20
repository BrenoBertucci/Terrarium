-- Lavender's Centre and Mart, outside (lib/LavenderCivicKit.lua): both build,
-- only here, their chimneys smoke, and the doors still take a walker in and
-- let them out again. Settings are synced in memory, never saved.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/lavender_civic_probe.log", "w"))
  local function log(s) file:write(s, "\n"); file:flush() end
  local failures = 0
  local function check(ok, message)
    log((ok and "PASS " or "FAIL ") .. message)
    if not ok then failures = failures + 1 end
  end
  for _ = 1, 1200 do
    if game.overworld and game.stack and game.stack:top() == game.overworld then break end
    if game.input then game.input.pressQueue[#game.input.pressQueue + 1] = "a" end
    coroutine.yield()
  end
  if not game.overworld then log("FAIL no overworld"); file:close(); love.event.quit(); return end
  local lib = game.mods.exports.TERRARIUM.lib
  local Buildings, Structures = lib.require("Buildings"), lib.require("Structures")
  local Kit = lib.require("LavenderCivicKit")
  local Cam, Voxel, Day = lib.require("MarioCam"), lib.require("Voxel3D"), lib.require("DayNight")
  require("src.render.Pipelines").setLevel("terrarium_voxel", 4)
  require("src.render.Pipelines").setLevel("terrarium_tiltshift", 0)
  lib.require("AutoFarm").setting:sync("off")
  lib.require("Weather").setting:sync("off")
  Day.setting:sync("day")
  Cam.setting:sync("on")
  local camera, originalCamera = nil, Cam.camera
  Cam.camera = function() return camera or originalCamera() end
  local function release()
    for _, d in ipairs({ "up", "down", "left", "right" }) do
      game.input.state[d] = false
      if game.input.sources then game.input.sources[d] = nil end
    end
    game.input.pressQueue = {}
  end
  local function settle(n) for _ = 1, n do release(); coroutine.yield() end end
  local function civicQuads(map)
    local n = 0
    for _, q in ipairs(Structures.forMap(map).spriteQuads or {}) do
      if q.tex == Kit.SHEET then n = n + 1 end
    end
    return n
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

  game.overworld:setMap("LAVENDER_TOWN", 5, 7, "up")
  for _ = 1, 1800 do
    if Voxel.lampLights then break end
    settle(1)
  end
  settle(240)
  local map = game.overworld.map
  local built = 0
  for key, st in pairs(Buildings.stats()) do
    if key:find("@lavender-civic", 1, true) then
      built = built + 1
      log(key .. " voxels=" .. st.voxels .. " quads=" .. st.quads)
    end
  end
  check(built == 3, "the Centre, the Mart and the Tower built: " .. built)
  local haunts = Structures.forMap(map).haunts or {}
  check(#haunts == 1 and #(haunts[1].wisps or {}) >= 8,
        "the Tower still hands its wisps to the scene: " .. #haunts)
  check(not Buildings.lastError, "building error=" .. tostring(Buildings.lastError))
  check(Voxel.shader() ~= nil and not Voxel.shaderError, "voxel shader compiled")
  check(civicQuads(map) > 10000, "authored quads stamped: " .. civicQuads(map))
  local mouths = 0
  for _, c in ipairs(Structures.forMap(map).chimneys or {}) do
    if (c.tx == 4 and c.ty == 4) or (c.tx == 28 and c.ty == 20) then mouths = mouths + 1 end
  end
  check(mouths == 2, "both chimneys were handed to the hearths: " .. mouths)
  check(Buildings.tallAt(map, 3, 3) >= 60, "the camera knows how tall the Centre stands")

  shot("centre_player")
  shot("centre_front", { 66, 46, 196 }, { 62, 26, 80 })
  shot("centre_se", { 168, 96, 196 }, { 64, 24, 70 })
  shot("centre_sw", { -34, 84, 176 }, { 64, 24, 70 })
  shot("mart_front", { 254, 44, 326 }, { 254, 22, 212 })
  shot("mart_se", { 352, 92, 318 }, { 256, 20, 196 })
  shot("mart_sw", { 170, 84, 312 }, { 256, 20, 196 })
  shot("town_overview", { 256, 193, 364 }, { 150, 10, 190 })
  shot("tower_front", { 236, 40, 250 }, { 240, 96, 40 })
  shot("tower_sw", { 60, 150, 330 }, { 240, 110, 32 })
  shot("tower_se", { 420, 170, 330 }, { 240, 110, 32 })
  shot("tower_night", { 60, 150, 330 }, { 240, 110, 32 }, "night")
  shot("centre_dusk", { 168, 96, 196 }, { 64, 24, 70 }, "dusk")
  shot("mart_night", { 170, 84, 312 }, { 256, 20, 196 }, "night")
  shot("centre_night", { 66, 46, 196 }, { 62, 26, 80 }, "night")
  -- after dark the two lanterns are LIGHTS, taken with the street lamps
  local lit = 0
  for _, l in ipairs(lib.require("StreetLamps").lights(map, 150, 150, 8)) do
    if (math.abs(l.x - 56) < 2 and math.abs(l.z - 93) < 2)
       or (math.abs(l.x - 257) < 2 and math.abs(l.z - 218) < 2) then lit = lit + 1 end
  end
  check(lit == 2, "the porch and the shop lantern burn after dark: " .. lit)
  Day.setting:sync("day")

  -- in through each real door and out again, on compass input
  Cam.setting:sync("off")
  local function walk(key, from)
    for _ = 1, 360 do
      if game.overworld.map.def.id ~= from then break end
      game.input.pressQueue[#game.input.pressQueue + 1] = key
      coroutine.yield()
    end
    settle(60)
  end
  for _, door in ipairs({ { 3, 6, "LAVENDER_POKECENTER" }, { 15, 14, "LAVENDER_MART" } }) do
    game.overworld:setMap("LAVENDER_TOWN", door[1], door[2], "up")
    settle(100)
    walk("up", "LAVENDER_TOWN")
    check(game.overworld.map.def.id == door[3], "in through the door: " .. door[3])
    walk("down", door[3])
    check(game.overworld.map.def.id == "LAVENDER_TOWN",
          "and out again: " .. tostring(game.overworld.map.def.id))
  end

  game.overworld:setMap("VIRIDIAN_CITY", 23, 26, "up")
  settle(400)
  check(civicQuads(game.overworld.map) == 0, "Viridian keeps its own Centre and Mart")
  Cam.camera = originalCamera
  log("RESULT " .. (failures == 0 and "PASS" or (failures .. " failures")))
  file:close()
  love.event.quit()
end
