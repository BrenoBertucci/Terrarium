-- Three of Vermilion's homes INSIDE (lib/VermilionHomeKit.lua): each builds
-- its own room, no two alike, and Lavender's still build theirs. Settings are
-- synced in memory, never saved by this probe.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/vermilion_homes_probe.log", "w"))
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
  local Kit = lib.require("VermilionHomeKit")
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
  for _, mapId in ipairs({ "VERMILION_OLD_ROD_HOUSE", "VERMILION_TRADE_HOUSE", "VERMILION_PIDGEY_HOUSE", "POKEMON_FAN_CLUB" }) do
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
  game.overworld:setMap("MR_FUJIS_HOUSE", 3, 6, "up")
  settle(600)
  check(homeQuads() == 0 and homeModels("MR_FUJIS_HOUSE") == 3, "Mr. Fuji's is still Lavender's kit")
  check(not Buildings.lastError, "building error=" .. tostring(Buildings.lastError))
  -- the club's couches are seats: whoever is on one stands at the seat's height
  game.overworld:setMap("POKEMON_FAN_CLUB", 3, 6, "up")
  settle(600)
  local Scene = lib.require("VoxelScene")
  check(Scene.groundAt(game.overworld.map, 1, 3) == Kit.SEAT_H, "a fan sits ON the couch: " .. tostring(Scene.groundAt(game.overworld.map, 1, 3)))
  check(Scene.groundAt(game.overworld.map, 3, 1) == 0, "the chairman stands on the floor: " .. tostring(Scene.groundAt(game.overworld.map, 3, 1)))
  settle(900)   -- (Pikachu's greeting bubble covered the first frame of this room)
  do
    local pending = true
    love.graphics.captureScreenshot(function(data)
      local f = assert(io.open(out .. "/POKEMON_FAN_CLUB_clear.png", "wb"))
      f:write(data:encode("png"):getString()); f:close(); pending = false
    end)
    for _ = 1, 120 do if not pending then break end; settle(1) end
  end
  check(Scene.groundAt(game.overworld.map, 3, 5) == 0, "and so does whoever walks round the table: " .. tostring(Scene.groundAt(game.overworld.map, 3, 5)))
  file:close()
  love.event.quit()
end
