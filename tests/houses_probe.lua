-- The houses of Cerulean and Celadon (lib/CeruleanHouseKit.lua,
-- lib/CeladonHouseKit.lua): they build, every door's cell stays walkable,
-- and what each one looks like -- from the player's own camera and from a
-- close eye per house. Settings are synced in memory, never saved.
-- DS_PROBE_ONLY=cerulean|celadon limits the run to one town.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local only = os.getenv("DS_PROBE_ONLY")
  local file = assert(io.open(out .. "/houses_probe.log", "w"))
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
  local Cam = lib.require("MarioCam")
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
    settle(300)
  end
  local function count(tex)
    local n = 0
    for _, q in ipairs(Structures.forMap(game.overworld.map).spriteQuads or {}) do
      if q.tex == tex then n = n + 1 end
    end
    return n
  end
  -- a close eye on a plot: from the south and above, the way the game's
  -- camera leans, near enough that one house fills the frame.
  -- tx, ty, tw, th: the plot in tiles
  -- The player is moved beside the plot first: sprite chunks are culled to
  -- the box round the PLAYER's view, and a far plot would come out empty.
  local here = nil
  local function plot(name, tx, ty, tw, th, hour)
    local mapId = game.overworld.map.def.id or game.overworld.map.def.name
    local cell = math.floor((tx + tw / 2) / 2) .. ":" .. math.floor((ty + th) / 2 + 1)
    if here ~= mapId .. cell then
      enter(mapId, math.floor((tx + tw / 2) / 2), math.floor((ty + th) / 2 + 1))
      here = mapId .. cell
    end
    local cx, cz = (tx + tw / 2) * 8, (ty + th / 2) * 8
    local r = math.max(tw, th) * 8
    shot(name, { cx + r * 0.35, r * 1.05 + 30, cz + r * 1.25 + 40 }, { cx, 14, cz + 4 }, hour)
  end

  if only ~= "celadon" then
    enter("CERULEAN_CITY", 13, 26)
    log("cerulean house quads=" .. count("assets/buildings/town_houses.png")
        .. " vermilion-sheet quads=" .. count("assets/buildings/vermilion_houses.png")
        .. " celadon-sheet quads=" .. count("assets/buildings/celadon_towers.png"))
    check(not Buildings.lastError, "building error=" .. tostring(Buildings.lastError))
    local map = game.overworld.map
    for name, c in pairs({ badge = { 9, 11 }, trashed = { 27, 11 }, melanie = { 13, 15 }, bike = { 13, 25 },
                           badge_back = { 9, 9 }, trashed_back = { 27, 9 } }) do
      check(map:isWalkableCell(c[1], c[2]), "cerulean " .. name .. ": the door's cell is still walkable")
    end
    shot("cer_bike_player")
    enter("CERULEAN_CITY", 12, 13)
    shot("cer_north_player")
    enter("CERULEAN_CITY", 30, 13)
    shot("cer_northeast_player")
    enter("CERULEAN_CITY", 23, 26)
    shot("cer_south_player")
    shot("cer_south_player_night", nil, nil, "night")
    plot("cer_badge", 16, 20, 12, 4)
    plot("cer_row_w", 28, 20, 12, 4)
    plot("cer_trashed", 52, 20, 12, 4)
    plot("cer_row_e", 68, 20, 12, 4)
    plot("cer_melanie", 24, 28, 12, 4)
    plot("cer_bike", 24, 44, 8, 8)
    plot("cer_bike_night", 24, 44, 8, 8, "night")
    plot("cer_south_w", 36, 48, 12, 4)
    plot("cer_south_e", 56, 48, 12, 4)
    shot("cer_overview", { 330, 300, 620 }, { 330, 20, 300 })
  end

  if only ~= "cerulean" then
    enter("CELADON_CITY", 30, 22)
    log("celadon house quads=" .. count("assets/buildings/town_houses.png")
        .. " tower-sheet quads=" .. count("assets/buildings/celadon_towers.png"))
    check(not Buildings.lastError, "building error=" .. tostring(Buildings.lastError))
    local map = game.overworld.map
    for name, c in pairs({ prize = { 33, 19 }, diner = { 31, 27 }, chief = { 35, 27 }, hotel = { 43, 27 },
                           casino = { 28, 19 } }) do
      check(map:isWalkableCell(c[1], c[2]), "celadon " .. name .. ": the door's cell is still walkable")
    end
    shot("cel_street_player")
    shot("cel_street_player_night", nil, nil, "night")
    enter("CELADON_CITY", 33, 10)
    shot("cel_north_player")
    enter("CELADON_CITY", 34, 20)
    shot("cel_prize_player")
    enter("CELADON_CITY", 16, 28)
    shot("cel_southwest_player")
    enter("CELADON_CITY", 33, 28)
    shot("cel_diner_player")
    for _, p in ipairs({
      { "office", 4, 8, 8, 12 }, { "deco", 28, 8, 12, 12 }, { "flats", 56, 12, 8, 8 },
      { "clock", 64, 12, 8, 8 }, { "garden", 72, 12, 8, 8 }, { "conservatory", 40, 28, 12, 4 },
      { "prize", 64, 32, 8, 8 }, { "slab", 76, 32, 8, 8 }, { "deco2", 84, 32, 8, 8 },
      { "flats2", 4, 48, 8, 8 }, { "slate", 28, 48, 8, 8 }, { "bronze", 36, 48, 8, 8 },
      { "terrace", 36, 56, 8, 8 }, { "jade", 52, 48, 8, 8 }, { "diner", 60, 48, 8, 8 },
      { "chief", 68, 48, 8, 8 }, { "flats3", 76, 48, 8, 8 } }) do
      plot("cel_" .. p[1], p[2], p[3], p[4], p[5])
    end
    plot("cel_diner_night", 60, 48, 8, 8, "night")
    shot("cel_south_row", { 560, 220, 700 }, { 520, 20, 420 })
    shot("cel_north_row", { 560, 200, 420 }, { 540, 20, 130 })
  end
  file:close()
  love.event.quit()
end
