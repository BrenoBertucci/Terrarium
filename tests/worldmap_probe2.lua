-- Probe 2: the geometry of Kanto, and what it costs to hold it.
--
-- Probe 1 answered the cheap questions and got one wrong: `def and pcall(f, x)`
-- truncates pcall's second return, so every outdoor test read nil and the walk
-- reported zero maps. Fixed here, and the questions it was really asking are
-- still open:
--
--   * How many outdoor maps does the walk from Pallet reach, and what is the
--     bounding box of Kanto in world pixels?
--   * `blocks` is on the def, resident and free. What is a block -- and does
--     the tileset table turn one into tiles without a MapLoader?
--   * What does MapLoader.load cost for the whole region, and what does a
--     loaded Map expose per cell?
--   * How many cells is Kanto, and how many of them are water?
--   * What is `screen.bg`, and how does a town-map grid cell relate to a
--     world pixel? (A pin has to land on the right map.)
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/worldmap2.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld"); logf:close(); love.event.quit()
      return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    game.input.pressQueue[#game.input.pressQueue + 1] = "a"
    wait(10); n = n + 11
    if n > 1500 then break end
  end
  wait(45)

  local function keysOf(t, limit)
    if type(t) ~= "table" then return tostring(t) end
    local ks = {}
    for k, v in pairs(t) do
      ks[#ks + 1] = tostring(k) .. "=" .. type(v)
        .. (type(v) == "table" and ("[" .. tostring(#v) .. "]") or "")
    end
    table.sort(ks)
    if limit and #ks > limit then
      local cut = {}
      for i = 1, limit do cut[i] = ks[i] end
      cut[limit + 1] = "...(" .. (#ks - limit) .. " more)"
      ks = cut
    end
    return table.concat(ks, " ")
  end
  local function isOutdoor(Map, def)
    if not def then return false end
    local ok, yes = pcall(Map.isOutdoor, def)
    return ok and yes and true or false
  end

  local Game = require("src.core.Game")
  local Map = require("src.world.Map")
  local maps = Game.data.maps
  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  local WaterMap = lib and lib.require("WaterMap")

  ------------------------------------------------------------------- THE WALK
  log("=== the walk (fixed) ===")
  local OverworldState = require("src.world.OverworldController")
  local reached
  for _, hops in ipairs({ 6, 12, 40 }) do
    local ok, raw = pcall(OverworldState.computeNeighbors, maps, "PALLET_TOWN", hops)
    if ok and type(raw) == "table" then
      local list, minx, miny, maxx, maxy = {}, 1e9, 1e9, -1e9, -1e9
      for _, nb in ipairs(raw) do
        local def = maps[nb.id]
        if isOutdoor(Map, def) then
          list[#list + 1] = { id = nb.id, ox = nb.ox, oy = nb.oy, def = def }
          local w, h = (def.width or 0) * 32, (def.height or 0) * 32
          if nb.ox < minx then minx = nb.ox end
          if nb.oy < miny then miny = nb.oy end
          if nb.ox + w > maxx then maxx = nb.ox + w end
          if nb.oy + h > maxy then maxy = nb.oy + h end
        end
      end
      log(("hops=%d raw=%d outdoor=%d bbox=(%d,%d)-(%d,%d) = %dx%d px = %dx%d cells")
          :format(hops, #raw, #list, minx, miny, maxx, maxy,
                  maxx - minx, maxy - miny, (maxx - minx) / 16, (maxy - miny) / 16))
      reached = list
    end
    coroutine.yield()
  end
  -- the root itself is not in the neighbour list
  log("root PALLET_TOWN in list? " .. tostring((function()
    for _, e in ipairs(reached or {}) do if e.id == "PALLET_TOWN" then return true end end
    return false end)()))

  log("")
  log("=== every outdoor map placed ===")
  for _, e in ipairs(reached or {}) do
    log(("  %-22s ox=%6d oy=%6d  %2dx%-2d blocks  tileset=%s")
        :format(e.id, e.ox, e.oy, e.def.width or 0, e.def.height or 0,
                tostring(e.def.tileset)))
  end

  ------------------------------------------------------------------ THE BLOCKS
  log("")
  log("=== blocks and tilesets ===")
  local ts = Game.data.tilesets
  log("tilesets: " .. keysOf(ts, 20))
  local ov = ts and ts.OVERWORLD
  if ov then
    log("OVERWORLD fields: " .. keysOf(ov, 30))
    for _, k in ipairs({ "blocks", "blockset", "tiles", "collision", "counters",
                         "grassTile", "waterTiles", "shoreTiles" }) do
      local v = ov[k]
      if v ~= nil then
        log("  " .. k .. " = " .. type(v)
            .. (type(v) == "table" and (" #" .. #v) or (" " .. tostring(v))))
        if type(v) == "table" and #v > 0 and type(v[1]) == "table" then
          log("    [1] = " .. type(v[1]) .. " #" .. #v[1] .. " : "
              .. table.concat(v[1], ",", 1, math.min(#v[1], 16)))
        elseif type(v) == "table" and #v > 0 then
          local s = {}
          for i = 1, math.min(#v, 16) do s[i] = tostring(v[i]) end
          log("    [1..] = " .. table.concat(s, ","))
        end
      end
    end
  end
  local r16 = maps.ROUTE_16
  if r16 and r16.blocks then
    local s = {}
    for i = 1, math.min(#r16.blocks, 24) do s[i] = tostring(r16.blocks[i]) end
    log("ROUTE_16.blocks[1..24] = " .. table.concat(s, ","))
  end

  ------------------------------------------------------------------- THE PRICE
  log("")
  log("=== the price ===")
  local MapLoader = require("src.world.MapLoader")
  local t0 = os.clock()
  local loaded, cells, water, walk, blocked = 0, 0, 0, 0, 0
  local sampleMap
  local perMap = {}
  for i, nb in ipairs(reached or {}) do
    local tm = os.clock()
    local ok, m = pcall(MapLoader.load, Game.data, nb.id)
    local ms = (os.clock() - tm) * 1000
    if ok and m then
      loaded = loaded + 1
      if not sampleMap then sampleMap = m end
      local mw = m.widthCells or 0
      local mh = m.heightCells or 0
      local w2, k2, b2 = 0, 0, 0
      for cy = 0, mh - 1 do
        for cx = 0, mw - 1 do
          if WaterMap and WaterMap.surfaceCell(m, cx, cy) then
            w2 = w2 + 1
          else
            local okW, yes = pcall(m.isWalkableCell, m, cx, cy)
            if okW and yes then k2 = k2 + 1 else b2 = b2 + 1 end
          end
        end
      end
      cells = cells + mw * mh; water = water + w2; walk = walk + k2
      blocked = blocked + b2
      perMap[#perMap + 1] = ("  %-22s %3dx%-3d cells  water=%-5d walk=%-5d blocked=%-5d  load %.1f ms")
        :format(nb.id, mw, mh, w2, k2, b2, ms)
    end
    if i % 5 == 0 then coroutine.yield() end
  end
  local ms = (os.clock() - t0) * 1000
  for _, line in ipairs(perMap) do log(line) end
  log(("TOTAL loaded=%d cells=%d water=%d walk=%d blocked=%d")
      :format(loaded, cells, water, walk, blocked))
  log(("TOTAL time %.0f ms for the whole region"):format(ms))

  if sampleMap then
    log("")
    log("loaded Map fields: " .. keysOf(sampleMap, 40))
    log("  id=" .. tostring(sampleMap.id)
        .. " widthCells=" .. tostring(sampleMap.widthCells)
        .. " heightCells=" .. tostring(sampleMap.heightCells))
    for _, k in ipairs({ "tileAt", "cellTile", "isWaterCell", "isWalkableCell",
                         "inBounds", "blockAt", "tiles" }) do
      log("  has " .. k .. ": " .. type(sampleMap[k]))
    end
  end

  -------------------------------------------------------------------- THE PINS
  log("")
  log("=== town-map grid vs world pixels ===")
  local TownMap = require("src.ui.TownMap")
  local made, screen = pcall(TownMap.new, game)
  if made and screen then
    log("mode=" .. tostring(screen.mode) .. " sel=" .. tostring(screen.sel))
    log("bg fields: " .. keysOf(screen.bg, 20))
    if type(screen.bg) == "table" then
      for k, v in pairs(screen.bg) do
        log("  bg." .. tostring(k) .. " = " .. type(v)
            .. (type(v) == "table" and (" #" .. #v) or ""))
      end
    end
    log("allLocs=" .. tostring(#(screen.allLocs or {}))
        .. " locs=" .. tostring(#(screen.locs or {})))
    log("playerLoc name=" .. tostring(screen.playerLoc and screen.playerLoc.name))
    log("--- placed maps and their town-map cell ---")
    for _, e in ipairs(reached or {}) do
      local loc = screen.byMap and screen.byMap[e.id]
      log(("  %-22s ox=%6d oy=%6d  ->  %-22s x=%s y=%s")
          :format(e.id, e.ox, e.oy, tostring(loc and loc.name),
                  tostring(loc and loc.x), tostring(loc and loc.y)))
    end
    log("--- all locations the map knows ---")
    for i, L in ipairs(screen.allLocs or {}) do
      log(("  [%2d] %-24s x=%-3s y=%-3s %s"):format(i, tostring(L.name),
          tostring(L.x), tostring(L.y), keysOf(L, 12)))
    end
  end

  log("")
  log("DONE")
  logf:close()
  wait(2)
  love.event.quit()
end
