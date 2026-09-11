-- Probe: the town map rebuilt from the classic picture.
--
-- Counted:
--   it BUILDS on this build (report().built, the three shaders, the count of
--   places -- 47, the classic map's own list), and how long it took;
--   the OBJECTIVE resolves and its route is walked along the picture's own
--   roads (path length > 2 means the search found the roads, 2 means it
--   fell back to a straight line);
--   every string a player can read is US English -- no Portuguese words
--   left in the module's table or in the quest chain;
--   FLY and AREA screens are honoured (the screen's own fields survive);
--   CLASSIC hands the screen back: the engine's own 160x144 picture is on
--   the window, measured by its palette's light blue.
-- And the pictures: the region, the zoom, the top-down view, fly, area,
-- classic, and the region at night.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/worldmap_new_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/worldmap_new_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local function shot(name)
    local done, keep = false, nil
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      keep = data; done = true
    end)
    local guard = 0
    while not done and guard < 240 do coroutine.yield(); guard = guard + 1 end
    return keep
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit() return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end
  game.input:reset()

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return end
  log("version:", exports.TERRARIUM.version)

  local WorldMap3D = lib.require("WorldMap3D")
  local WorldMapQuest = lib.require("WorldMapQuest")
  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local TownMap = require("src.ui.TownMap")

  DayNight.setting:sync("day")
  Weather.setting:sync("none")
  WorldMap3D.setting:sync("3d")
  game.overworld:setMap("ROUTE_12", 10, 20, "down")
  wait(120)

  -- ------- 1. the strings, before a pixel
  local pt = { "ç", "ã", "õ", "INSÍGNIA", "Derrote", "Recupere", "Ginásio", "OBJETIVO", "VOCÊ", "SAIR", "GIRAR" }
  local function scan(tag, s)
    for _, w in ipairs(pt) do
      if s:find(w, 1, true) then log(("  FAIL: %s still carries %q"):format(tag, w)) return false end
    end
    return true
  end
  local okS = true
  for k, v in pairs(WorldMap3D.strings()) do
    if type(v) == "string" then okS = scan("strings." .. k, v) and okS
    elseif type(v) == "table" then for k2, v2 in pairs(v) do okS = scan("strings." .. k .. "." .. k2, v2) and okS end end
  end
  for _, st in ipairs(WorldMapQuest.CHAIN) do
    okS = scan("quest " .. st.id, st.title .. " " .. (st.detail or "")) and okS
  end
  log("english strings:", okS and "PASS" or "FAIL")

  -- ------- 2. the build, through the real screen
  local function openMap(opts)
    local screen = TownMap.new(game, opts)
    game.stack:push(screen)
    local guard = 0
    while guard < 1200 do
      wait(1); guard = guard + 1
      local rep = WorldMap3D.report()
      if rep.built or rep.failed then break end
    end
    return screen
  end
  local screen = openMap()
  wait(90)
  local rep = WorldMap3D.report()
  log(("built=%s failed=%s places=%d landVerts=%d propVerts=%d waterVerts=%d peaks=%d shaders=%s ms=%.0f")
      :format(tostring(rep.built), tostring(rep.failed), rep.places, rep.landVerts, rep.propVerts,
              rep.waterVerts, rep.peaks, tostring(rep.shaders), rep.ms))
  if not rep.built then log("  FAIL: the map did not build") end
  local plainCount = #TownMap.new(game).locs
  if rep.places ~= plainCount then
    log(("  FAIL: %d places against the screen's own %d"):format(rep.places, plainCount))
  end
  if not rep.shaders then log("  FAIL: a shader did not compile") end
  log(("screen: mode=%s sel=%s player=%s  quest=%s target=%s path=%d")
      :format(tostring(screen.mode), tostring(screen.sel),
              tostring(screen.playerLoc and screen.playerLoc.name),
              tostring(rep.quest), tostring(rep.target), rep.path))
  if rep.quest and rep.path <= 2 then log("  note: the objective route fell back to a straight line") end
  -- where every pin landed
  local places = WorldMap3D.debugPlaces()
  local off = 0
  local w, h = love.graphics.getDimensions()
  for _, p in ipairs(places) do
    if p.sx < 0 or p.sx > w or p.sy < 0 or p.sy > h then off = off + 1 end
  end
  log(("pins on screen: %d of %d"):format(#places - off, #places))
  if off > 0 then log("  FAIL: pins off screen in the wide view") end
  shot("wm_region.png")

  -- the cursor: a few d-pad taps, the banner follows
  tap("right"); wait(30); tap("up"); wait(30)
  log("after right, up: sel=" .. tostring(screen.sel) .. " " .. tostring(screen.locs[screen.sel] and screen.locs[screen.sel].name))
  shot("wm_moved.png")
  WorldMap3D.toggleZoom(); wait(80)
  shot("wm_zoom.png")
  WorldMap3D.toggleTopDown(); wait(80)
  shot("wm_zoom_top.png")
  WorldMap3D.toggleZoom(); wait(80)
  shot("wm_top.png")
  WorldMap3D.toggleTopDown(); wait(40)
  -- night
  DayNight.setting:sync("night"); wait(60)
  shot("wm_night.png")
  DayNight.setting:sync("day"); wait(20)
  tap("b"); wait(20)

  -- ------- 3. fly
  local flew = nil
  local fly = openMap({ fly = true, onFly = function(id) flew = id end })
  wait(60)
  log(("fly screen: fly=%s locs=%d sel=%s"):format(tostring(fly.fly), #fly.locs, tostring(fly.sel)))
  shot("wm_fly.png")
  tap("down"); wait(30)
  log("fly after down: " .. tostring(fly.locs[fly.sel] and fly.locs[fly.sel].name))
  tap("a"); wait(30)
  log("A on the fly screen flew to: " .. tostring(flew) .. "  top is overworld: " .. tostring(game.stack:top() == game.overworld))
  if not flew then log("  FAIL: A did not fly") end
  wait(200)

  -- ------- 4. the Pokedex area
  local nest = openMap({ nestSpecies = "PIDGEY" })
  wait(60)
  log(("area screen: nests=%d"):format(nest.nests and #nest.nests or -1))
  shot("wm_area.png")
  tap("a"); wait(30)

  -- ------- 5. classic
  WorldMap3D.setting:sync("classic")
  local cls = openMap()
  wait(60)
  local img = shot("wm_classic.png")
  if img then
    local hit, seen = 0, 0
    for y = 0, img:getHeight() - 1, 4 do
      for x = 0, img:getWidth() - 1, 4 do
        local r, g, b = img:getPixel(x, y)
        seen = seen + 1
        -- the engine's TOWNMAP palette on this build: sky blue {0,173,255}
        -- and grass green {82,230,0}, measured off its own screen
        if (r < 0.1 and math.abs(g - 0.678) < 0.08 and b > 0.9)
           or (math.abs(r - 0.322) < 0.08 and g > 0.85 and b < 0.1) then hit = hit + 1 end
      end
    end
    log(("classic: palette pixels %d of %d sampled (%.1f%%)"):format(hit, seen, 100 * hit / seen))
    if hit < seen * 0.10 then log("  FAIL: the classic picture is not on the window") end
  end
  log("classic report: built=" .. tostring(WorldMap3D.report().built) .. " classic=" .. tostring(WorldMap3D.report().classic))
  tap("b"); wait(20)
  WorldMap3D.setting:sync("3d")

  log("done")
  logf:close()
  love.event.quit()
end
