-- Celadon's eighteen rooms (lib/CeladonRoomKit.lua): each builds without an
-- error, lays its floor and claims its furniture; a photograph of each. Settings are
-- synced in memory, never saved by this probe.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/celadon_rooms_probe.log", "w"))
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
  local Kit = lib.require("CeladonRoomKit")
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
  local function roomQuads()
    local S = Structures.forMap(game.overworld.map)
    local n = 0
    for _, q in ipairs(S.spriteQuads or {}) do if q.tex == Kit.SHEET then n = n + 1 end end
    return n
  end
  local ROOMS = {
    { "CELADON_MART_1F", 2, 6 },
    { "CELADON_MART_2F", 12, 2 },
    { "CELADON_MART_3F", 12, 2 },
    { "CELADON_MART_4F", 12, 2 },
    { "CELADON_MART_5F", 12, 2 },
    { "CELADON_MART_ROOF", 15, 3 },
    { "CELADON_MART_ELEVATOR", 1, 2 },
    { "CELADON_MANSION_1F", 4, 10 },
    { "CELADON_MANSION_2F", 6, 2 },
    { "CELADON_MANSION_3F", 6, 2 },
    { "CELADON_MANSION_ROOF", 6, 2 },
    { "CELADON_MANSION_ROOF_HOUSE", 2, 6 },
    { "CELADON_CHIEF_HOUSE", 2, 6 },
    { "CELADON_DINER", 3, 6 },
    { "CELADON_HOTEL", 3, 6 },
    { "CELADON_GYM", 4, 16 },
    { "GAME_CORNER", 15, 16 },
    { "GAME_CORNER_PRIZE_ROOM", 4, 6 },
  }
  for _, r in ipairs(ROOMS) do
    Buildings.lastError = nil
    game.overworld:setMap(r[1], r[2], r[3], "up")
    for _ = 1, 3000 do
      if Structures.peek(game.overworld.map) then break end
      settle(1)
    end
    settle(700)      -- (Pikachu's greeting bubble covers the first frames of a room)
    check(not Buildings.lastError, r[1] .. ": building error=" .. tostring(Buildings.lastError))
    check(roomQuads() > 300, r[1] .. ": dressed, quads=" .. roomQuads())
    local pending = true
    love.graphics.captureScreenshot(function(data)
      local f = assert(io.open(out .. "/" .. r[1] .. ".png", "wb"))
      f:write(data:encode("png"):getString()); f:close(); pending = false
    end)
    for _ = 1, 120 do if not pending then break end; settle(1) end
  end
  game.overworld:setMap("VERMILION_MART", 3, 6, "up")
  settle(400)
  check(roomQuads() == 0, "another town's shop is left alone")
  file:close()
  love.event.quit()
end
