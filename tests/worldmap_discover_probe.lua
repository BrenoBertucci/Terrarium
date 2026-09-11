-- Probe: what the engine's town map actually carries on THIS build.
--
-- Everything the rewrite of lib/WorldMap3D.lua stands on is a fact about
-- src.ui.TownMap at runtime -- whether the grid coordinates and the
-- original background art shipped with these assets, what the fly picker
-- looks like, which maps the classic grid knows. Asked, not assumed.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/worldmap_discover_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/worldmap_discover_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit()
      return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end
  game.input:reset()

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  log("version:", exports and exports.TERRARIUM and exports.TERRARIUM.version)

  -- ------- the data behind the screen
  local field = game.data.field or {}
  local tm = field.townMap
  log("field.townMap type:", type(tm))
  if type(tm) == "table" then
    local keys = {}
    for k in pairs(tm) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    log("  keys:", table.concat(keys, ", "))
    local locs = tm.locations or tm
    local cnt = 0
    local sample = {}
    for mapId, e in pairs(locs) do
      if type(e) == "table" then
        cnt = cnt + 1
        if #sample < 8 then
          local c = e.coords or e
          sample[#sample + 1] = ("%s{name=%s x=%s y=%s}"):format(mapId,
            tostring(e.name or e.label), tostring(c.x or c.col), tostring(c.y or c.row))
        end
      end
    end
    log("  entries:", cnt, " sample:", table.concat(sample, " "))
    local bg = tm.background
    if type(bg) == "table" then
      log("  background: tiles=" .. tostring(bg.tiles and bg.tiles.path)
          .. " cursor=" .. tostring(bg.cursor and bg.cursor.path)
          .. " map len=" .. tostring(bg.map and #bg.map))
      if bg.map then
        -- the 20x18 tilemap, one row per line, tile ids in hex
        for row = 0, 17 do
          local s = {}
          for col = 0, 19 do
            s[#s + 1] = ("%2x"):format(bg.map[row * 20 + col + 1] or 0)
          end
          log("    " .. table.concat(s, " "))
        end
      end
    else
      log("  background: none")
    end
    if tm.nest then log("  nest icon:", tostring(tm.nest.path)) end
  end
  log("flyOrder:", field.flyOrder and table.concat(field.flyOrder, ",") or "nil")
  local fw = {}
  for k in pairs(field.flyWarps or {}) do fw[#fw + 1] = k end
  table.sort(fw)
  log("flyWarps:", table.concat(fw, ","))
  local vis = {}
  for k, v in pairs(game.save.visited or {}) do if v then vis[#vis + 1] = k end end
  table.sort(vis)
  log("visited (" .. #vis .. "):", table.concat(vis, ","))
  log("badges:", tostring(game.save.badges), " type", type(game.save.badges))

  -- ------- the screen itself, both ways it is built
  local okT, TownMap = pcall(require, "src.ui.TownMap")
  if not okT then log("FAIL: no TownMap"); logf:close(); love.event.quit(); return end
  local WorldMap3D = lib and lib.require("WorldMap3D")
  local okS, s = pcall(TownMap.new, game)
  if okS and s then
    log(("view screen: mode=%s locs=%d sel=%s player=%s bg=%s fly=%s")
        :format(tostring(s.mode), #s.locs, tostring(s.sel),
                tostring(s.playerLoc and s.playerLoc.name), tostring(s.bg ~= nil),
                tostring(s.fly)))
    for i, loc in ipairs(s.locs) do
      log(("  loc %2d  %-22s x=%s y=%s"):format(i, loc.name, tostring(loc.x), tostring(loc.y)))
    end
    local by = {}
    for mapId, loc in pairs(s.byMap) do by[#by + 1] = mapId .. "->" .. loc.name end
    table.sort(by)
    log("byMap (" .. #by .. "): " .. table.concat(by, " "))
  else
    log("view screen failed:", tostring(s))
  end
  local okF, f = pcall(TownMap.new, game, { fly = true, onFly = function() end })
  if okF and f then
    log(("fly screen: fly=%s mode=%s locs=%d ids=%s"):format(tostring(f.fly),
        tostring(f.mode), #f.locs,
        f.flyMapIds and table.concat(f.flyMapIds, ",") or "nil"))
  else
    log("fly screen failed:", tostring(f))
  end
  local okN, nest = pcall(TownMap.new, game, { nestSpecies = "PIDGEY" })
  if okN and nest then
    log(("nest screen: species=%s nests=%d icon=%s"):format(tostring(nest.nestSpecies),
        nest.nests and #nest.nests or -1, tostring(nest.nestIcon ~= nil)))
  end

  -- ------- and what the mod's placement says (map ids and cell rects)
  if WorldMap3D and WorldMap3D.debugPlaces then
    -- open the real screen so the region builds
    game.stack:push(TownMap.new(game))
    local guard = 0
    while guard < 900 do
      wait(1); guard = guard + 1
      local rep = WorldMap3D.report and WorldMap3D.report()
      if rep and rep.built then break end
    end
    local okP, places = pcall(WorldMap3D.debugPlaces)
    if okP and type(places) == "table" then
      log("placed maps: " .. #places)
      for _, p in ipairs(places) do
        log(("  %-22s x=%4d y=%4d w=%3d h=%3d land=%s"):format(
          tostring(p.id), p.gx or p.x or -1, p.gy or p.y or -1, p.w or -1, p.h or -1,
          tostring(p.solid) .. "/" .. tostring(p.sea)))
      end
    else
      log("debugPlaces:", tostring(places))
    end
    tap("b"); wait(10)
  end

  log("done")
  logf:close()
  love.event.quit()
end
