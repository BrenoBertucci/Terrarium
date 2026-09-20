-- The three Lavender homes INSIDE: each builds its own room, no two alike,
-- and a house in another town keeps the classic interior. Settings are
-- synced in memory, never saved by this probe.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/lavender_homes_probe.log", "w"))
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
  local Kit = lib.require("LavenderHomeKit")
  require("src.render.Pipelines").setLevel("terrarium_voxel", 4)
  require("src.render.Pipelines").setLevel("terrarium_tiltshift", 0)
  lib.require("AutoFarm").setting:sync("off")
  lib.require("MarioCam").setting:sync("on")
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
  local function homeModels(mapId)
    local n, voxels = 0, 0
    for key, st in pairs(Buildings.stats()) do
      if key:find("@home:" .. mapId, 1, true) then n = n + 1; voxels = voxels + st.voxels end
    end
    return n, voxels
  end
  local function homeQuads()
    local S = Structures.forMap(game.overworld.map)
    local n = 0
    for _, q in ipairs(S.spriteQuads or {}) do if q.tex == Kit.SHEET then n = n + 1 end end
    return n
  end
  local seen = {}
  for _, mapId in ipairs({ "MR_FUJIS_HOUSE", "LAVENDER_CUBONE_HOUSE", "NAME_RATERS_HOUSE" }) do
    Buildings.lastError = nil
    game.overworld:setMap(mapId, 3, 6, "up")
    for _ = 1, 1200 do
      if homeModels(mapId) == 3 then break end
      settle(1)
    end
    settle(240)
    local n, voxels = homeModels(mapId)
    check(n == 3, mapId .. ": room + both seat pairs built (" .. n .. "), voxels=" .. voxels)
    check(not Buildings.lastError, mapId .. ": building error=" .. tostring(Buildings.lastError))
    check(homeQuads() > 5000, mapId .. ": authored quads stamped: " .. homeQuads())
    check(not seen[voxels], mapId .. ": differs from the other homes")
    seen[voxels] = true
    local pending = true
    love.graphics.captureScreenshot(function(data)
      local f = assert(io.open(out .. "/" .. mapId .. ".png", "wb"))
      f:write(data:encode("png"):getString()); f:close(); pending = false
    end)
    for _ = 1, 120 do if not pending then break end; settle(1) end
    check(not pending, "captured " .. mapId)
  end
  game.overworld:setMap("BLUES_HOUSE", 3, 6, "up")
  settle(300)
  check(homeQuads() == 0, "Blue's house keeps the classic interior")
  -- In through the real door, then back out over the mat: the warp cells
  -- sit under the kit's floor (and, in the Cubone house, under its own mat).
  lib.require("MarioCam").setting:sync("off") -- compass input
  local function walk(key, from)
    for _ = 1, 360 do
      if game.overworld.map.def.id ~= from then break end
      game.input.pressQueue[#game.input.pressQueue + 1] = key
      coroutine.yield()
    end
    settle(60)
  end
  for _, door in ipairs({ { 7, 10, "MR_FUJIS_HOUSE" }, { 3, 14, "LAVENDER_CUBONE_HOUSE" },
                          { 7, 14, "NAME_RATERS_HOUSE" } }) do
    game.overworld:setMap("LAVENDER_TOWN", door[1], door[2], "up")
    settle(100)
    walk("up", "LAVENDER_TOWN")
    check(game.overworld.map.def.id == door[3], "in through the door: " .. door[3])
    walk("down", door[3])
    local o = game.overworld
    check(o.map.def.id == "LAVENDER_TOWN", "out over the mat: " .. door[3]
          .. " -> " .. tostring(o.map.def.id))
  end
  log("RESULT " .. (failures == 0 and "PASS" or (failures .. " failures")))
  file:close()
  love.event.quit()
end
