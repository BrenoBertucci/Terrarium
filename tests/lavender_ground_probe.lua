-- Lavender's ground (lib/LavenderGroundKit.lua): it builds, it stays in
-- Lavender, walkers and puddles stand ON it, and what it costs a frame --
-- measured against the same town with the kit switched off in the module,
-- because the render rewrites everything a probe could zero from outside.
-- Settings are synced in memory, never saved by this probe.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/lavender_ground_probe.log", "w"))
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
  local Kit, Scene = lib.require("LavenderGroundKit"), lib.require("VoxelScene")
  local Cam, Voxel, Day = lib.require("MarioCam"), lib.require("Voxel3D"), lib.require("DayNight")
  local Weather, Mesher = lib.require("Weather"), lib.require("ChunkMesher")
  require("src.render.Pipelines").setLevel("terrarium_voxel", 4)
  require("src.render.Pipelines").setLevel("terrarium_tiltshift", 0)
  lib.require("AutoFarm").setting:sync("off")
  Weather.setting:sync("off")
  Day.setting:sync("day")
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
  local function stamped()
    local S = Structures.forMap(game.overworld.map)
    local n = 0
    for _, q in ipairs(S.spriteQuads or {}) do
      if type(q.tex) == "string" and q.tex:find("lavground_", 1, true) then n = n + 1 end
    end
    return n
  end
  local function enter()
    game.overworld:setMap("LAVENDER_TOWN", 13, 14, "down")
    for _ = 1, 1800 do
      if Voxel.lampLights then break end
      settle(1)
    end
    settle(240)
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
  local function frameCost(label)
    love.window.setVSync(0)
    settle(120)
    local t = {}
    for _ = 1, 400 do
      local a = love.timer.getTime()
      settle(1)
      t[#t + 1] = love.timer.getTime() - a
    end
    love.window.setVSync(1)
    -- the MEAN, not the median: at POKEPORT_SPEED 4 three updates in four
    -- draw nothing, so the median is an update and says nothing of a frame
    local sum = 0
    for _, v in ipairs(t) do sum = sum + v end
    table.sort(t)
    log(("%s  mean %.2f ms a step  (median %.2f, p90 %.2f)")
          :format(label, sum / #t * 1000, t[200] * 1000, t[360] * 1000))
    return sum / #t * 1000
  end

  enter()
  local map = game.overworld.map
  log(("stamped quads=%d"):format(stamped()))
  check(not Buildings.lastError, "building error=" .. tostring(Buildings.lastError))
  check(stamped() > 8000 and stamped() < 30000, "stamped within budget (the Tower alone is 24.5k): " .. stamped())
  check(Voxel.shader() ~= nil and not Voxel.shaderError, "voxel shader compiled")
  check(Scene.groundAt(map, 13, 14) == 1, "a walker stands ON the ground: " .. tostring(Scene.groundAt(map, 13, 14)))
  check(Scene.groundAt(map, 8, 2) == 1, "and up the north road: " .. tostring(Scene.groundAt(map, 8, 2)))
  check(Structures.liftAt(map, 18, 6) == nil, "a sign's own cell is not lifted")
  shot("player_day")
  shot("close_day", { 222, 46, 292 }, { 214, 0, 232 })
  shot("houses_day", { 150, 70, 300 }, { 110, 4, 215 })
  shot("meadow_day", { 176, 64, 214 }, { 246, 0, 142 })
  shot("west_gate_day", { 10, 66, 236 }, { 44, 0, 140 })
  shot("north_road_day", { 128, 70, 150 }, { 128, 0, 60 })
  -- the three joins, looked at from inside the town: if a map's edge showed
  -- anywhere it would be across the middle of these
  shot("join_west", { 70, 60, 200 }, { -20, 0, 136 })
  shot("join_north", { 150, 70, 90 }, { 140, 0, -30 })
  shot("join_south", { 150, 80, 200 }, { 144, 0, 310 })
  shot("overview_day", { 256, 193, 364 }, { 150, 10, 190 })
  shot("player_dusk", nil, nil, "dusk")
  shot("player_night", nil, nil, "night")
  Day.setting:sync("day")
  -- a minute of downpour and two of snowfall, in a second each: the ground
  -- has to be SOAKED and COVERED for there to be anything to look at
  local Ground = lib.require("GroundFX")
  local soak, cover = Ground.SOAK, Ground.SETTLE
  Ground.SOAK, Ground.SETTLE = 1, 1
  Weather.setting:sync("rain")
  settle(900)
  shot("player_rain")
  shot("close_rain", { 222, 46, 292 }, { 214, 0, 232 })
  Weather.setting:sync("snow")
  settle(900)
  shot("player_snow")
  shot("close_snow", { 222, 46, 292 }, { 214, 0, 232 })
  -- and dry it all off again just as fast, or every shot after this one is
  -- a photograph of snow
  local dry, melt = Ground.DRY, Ground.MELT
  Ground.DRY, Ground.MELT = 1, 1
  Weather.setting:sync("off")
  settle(600)
  Ground.SOAK, Ground.SETTLE, Ground.DRY, Ground.MELT = soak, cover, dry, melt

  -- The same town with the kit switched off where the build reads it, and
  -- back, twice: both sides measured after the SAME rebuild and the same
  -- settle, because a town that was just re-meshed runs slower for a while
  -- and the first cut of this probe charged that to whichever came second.
  local function measure(enabled, label)
    Kit.ENABLED = enabled
    Mesher.invalidate()
    enter()
    settle(1500)
    return frameCost(label)
  end
  local diffs = {}
  for pair = 1, 3 do
    local off = measure(false, "kit OFF")
    if pair == 1 then
      check(stamped() == 0, "off in the module: the drawn checker is back")
      check(Scene.groundAt(game.overworld.map, 13, 14) == 0, "and the lift with it")
      shot("player_day_classic")
    end
    diffs[pair] = measure(true, "kit ON ") - off
  end
  table.sort(diffs)
  log(("cost of the ground, three pairs: %+.2f  %+.2f  %+.2f ms a step (median %+.2f)")
        :format(diffs[1], diffs[2], diffs[3], diffs[2]))

  -- and from the road, looking back: the route is floored, walkers stand
  -- at the town's level on it, and the town is there across the edge
  for _, r in ipairs({ { "ROUTE_8", 56, 8, { 830, 60, 200 }, { 960, 0, 136 } },
                       { "ROUTE_12", 9, 4, { 100, 70, 150 }, { 144, 0, 0 } },
                       { "ROUTE_10", 9, 70, { 200, 70, 1060 }, { 144, 0, 1152 } } }) do
    game.overworld:setMap(r[1], r[2], r[3], "down")
    settle(500)
    check(stamped() > 3000, r[1] .. " is floored: " .. stamped())
    check(Scene.groundAt(game.overworld.map, r[2], r[3]) == 1,
          r[1] .. ": the road stands at the town's level: "
          .. tostring(Scene.groundAt(game.overworld.map, r[2], r[3])))
    check(not Buildings.lastError, r[1] .. " building error=" .. tostring(Buildings.lastError))
    shot("from_" .. r[1], r[4], r[5])
    shot("walk_" .. r[1])
  end
  game.overworld:setMap("PEWTER_CITY", 18, 20, "down")
  settle(400)
  check(stamped() == 0, "Pewter keeps its drawn ground")
  check(next(Structures.forMap(game.overworld.map).lift or {}) == nil, "and nothing there is lifted")
  Cam.camera = originalCamera
  log("RESULT " .. (failures == 0 and "PASS" or (failures .. " failures")))
  file:close()
  love.event.quit()
end
