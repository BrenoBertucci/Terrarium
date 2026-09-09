-- Probe: what does a voxel world map have to work with?
--
-- Five questions, none of which can be answered by reading the mod:
--
--   1. THE SCREEN. `src.ui.TownMap` is what the MAP row opens. What does the
--      instance actually carry -- how many locations, in what coordinate
--      space, keyed how? A diorama that wants to put a pin on Pewter has to
--      know where the engine thinks Pewter is.
--   2. THE DEFS. 223 map defs are resident. Do they carry TILES, or only
--      width/height/connections/tileset? If tiles are on the def, the whole
--      of Kanto is free; if not, it costs a MapLoader.load per map.
--   3. THE WALK. WorldAtlas stops at 6 hops. How far does Kanto go? How many
--      outdoor maps does the connection graph reach from Pallet, and what is
--      the bounding box in world pixels?
--   4. THE PRICE. Loading every outdoor map to read its cells: how many ms,
--      how many cells, how many of them water? This decides whether the map
--      is built at runtime or baked into data/.
--   5. THE GPU. Is there a depth canvas to render a 3D scene into from the
--      present hook, and what does this build's LOVE support?
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/worldmap_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/worldmap.log", "w"))
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
    if n > 1500 then log("FAIL: never reached free roam"); break end
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

  ------------------------------------------------------------------ 1. SCREEN
  log("=== 1. TownMap screen ===")
  local okT, TownMap = pcall(require, "src.ui.TownMap")
  if okT and TownMap and TownMap.new then
    local made, screen = pcall(TownMap.new, game)
    if made and screen then
      log("screen fields: " .. keysOf(screen, 40))
      local locs = screen.locs
      if type(locs) == "table" then
        log("locs count: " .. #locs)
        for i = 1, math.min(#locs, 6) do
          log("  loc[" .. i .. "] " .. keysOf(locs[i], 20))
          local L = locs[i]
          log("    name=" .. tostring(L.name or L.label or L.id)
              .. " x=" .. tostring(L.x) .. " y=" .. tostring(L.y))
        end
      end
      log("playerLoc: " .. keysOf(screen.playerLoc, 20))
      if type(screen.byMap) == "table" then
        local c = 0
        for _ in pairs(screen.byMap) do c = c + 1 end
        log("byMap entries: " .. c)
        local shown = 0
        for k, v in pairs(screen.byMap) do
          log("  byMap[" .. tostring(k) .. "] = " .. tostring(v)
              .. " (" .. type(v) .. ")")
          shown = shown + 1
          if shown >= 5 then break end
        end
      end
      if screen.bg then
        local okD, w, h = pcall(function()
          return screen.bg:getWidth(), screen.bg:getHeight() end)
        log("bg: " .. tostring(screen.bg) .. " dims="
            .. (okD and (tostring(w) .. "x" .. tostring(h)) or "?"))
      else
        log("bg: nil")
      end
    else
      log("TownMap.new FAILED: " .. tostring(screen))
    end
  else
    log("no src.ui.TownMap")
  end

  --------------------------------------------------------------------- 2. DEFS
  log("")
  log("=== 2. Map defs ===")
  local Game = require("src.core.Game")
  local Map = require("src.world.Map")
  local maps = Game.data and Game.data.maps
  if type(maps) ~= "table" then
    log("FAIL: no Game.data.maps"); logf:close(); love.event.quit(); return
  end
  local total, outdoor = 0, 0
  local sample
  for id, def in pairs(maps) do
    total = total + 1
    local okO, yes = pcall(Map.isOutdoor, def)
    if okO and yes then
      outdoor = outdoor + 1
      if not sample and def.width and def.width > 8 then sample = id end
    end
  end
  log("maps total=" .. total .. " outdoor=" .. outdoor)
  log("sample outdoor def id: " .. tostring(sample))
  if sample then
    log("def fields: " .. keysOf(maps[sample], 40))
    local d = maps[sample]
    log("  width=" .. tostring(d.width) .. " height=" .. tostring(d.height)
        .. " tileset=" .. tostring(d.tileset))
    for _, k in ipairs({ "blocks", "tiles", "layout", "blockdata", "data",
                         "map", "cells" }) do
      local v = d[k]
      if v ~= nil then
        log("  HAS " .. k .. " : " .. type(v)
            .. (type(v) == "table" and (" #" .. #v) or ""))
      end
    end
  end
  log("Game.data fields: " .. keysOf(Game.data, 40))

  --------------------------------------------------------------------- 3. WALK
  log("")
  log("=== 3. The walk ===")
  local OverworldState = require("src.world.OverworldController")
  local root = maps.PALLET_TOWN and "PALLET_TOWN" or (game.overworld
    and game.overworld.state and game.overworld.state.map
    and game.overworld.state.map.id)
  log("root: " .. tostring(root))
  local reached
  for _, hops in ipairs({ 6, 12, 25, 40, 60 }) do
    local t0 = os.clock()
    local ok, raw = pcall(OverworldState.computeNeighbors, maps, root, hops)
    local ms = (os.clock() - t0) * 1000
    if ok and type(raw) == "table" then
      local out, minx, miny, maxx, maxy = 0, 1e9, 1e9, -1e9, -1e9
      local list = {}
      for _, nb in ipairs(raw) do
        local def = maps[nb.id]
        local okO, yes = def and pcall(Map.isOutdoor, def)
        if okO and yes then
          out = out + 1
          list[#list + 1] = { id = nb.id, ox = nb.ox, oy = nb.oy, def = def }
          local w = (def.width or 0) * 32
          local h = (def.height or 0) * 32
          if nb.ox < minx then minx = nb.ox end
          if nb.oy < miny then miny = nb.oy end
          if nb.ox + w > maxx then maxx = nb.ox + w end
          if nb.oy + h > maxy then maxy = nb.oy + h end
        end
      end
      log(("hops=%d raw=%d outdoor=%d bbox=(%d,%d)-(%d,%d) %dx%d px  %.1f ms")
          :format(hops, #raw, out, minx, miny, maxx, maxy,
                  maxx - minx, maxy - miny, ms))
      reached = list
    else
      log("hops=" .. hops .. " FAILED: " .. tostring(raw))
    end
    coroutine.yield()
  end

  -------------------------------------------------------------------- 4. PRICE
  log("")
  log("=== 4. The price of tiles ===")
  local okML, MapLoader = pcall(require, "src.world.MapLoader")
  log("MapLoader: " .. tostring(okML and MapLoader ~= nil))
  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  local WaterMap = lib and lib.require("WaterMap")
  log("WaterMap: " .. tostring(WaterMap ~= nil))

  if okML and MapLoader and reached then
    local t0 = os.clock()
    local loaded, failed, cells, water, walk = 0, 0, 0, 0, 0
    local biggest, biggestN = nil, 0
    for i, nb in ipairs(reached) do
      local ok, m = pcall(MapLoader.load, Game.data, nb.id)
      if ok and m then
        loaded = loaded + 1
        local mw = m.widthCells or ((m.def and m.def.width or 0) * 2)
        local mh = m.heightCells or ((m.def and m.def.height or 0) * 2)
        cells = cells + mw * mh
        if mw * mh > biggestN then biggestN = mw * mh; biggest = nb.id end
        -- sample a fifth of the cells so the timing is the LOAD, not this loop
        for cy = 0, mh - 1, 2 do
          for cx = 0, mw - 1, 2 do
            if WaterMap and WaterMap.surfaceCell(m, cx, cy) then
              water = water + 1
            elseif m.isWalkableCell then
              local okW, yes = pcall(m.isWalkableCell, m, cx, cy)
              if okW and yes then walk = walk + 1 end
            end
          end
        end
      else
        failed = failed + 1
        if failed <= 3 then log("  load failed: " .. nb.id) end
      end
      if i % 10 == 0 then coroutine.yield() end
    end
    local ms = (os.clock() - t0) * 1000
    log(("loaded=%d failed=%d cells=%d (quarter-sampled: water=%d walk=%d)")
        :format(loaded, failed, cells, water, walk))
    log(("total time %.0f ms  (%.1f ms per map)"):format(ms, ms / math.max(1, loaded)))
    log("biggest map: " .. tostring(biggest) .. " = " .. biggestN .. " cells")
  end

  ---------------------------------------------------------------------- 5. GPU
  log("")
  log("=== 5. GPU ===")
  log("LOVE " .. table.concat({ love.getVersion() }, "."))
  local okS, sup = pcall(love.graphics.getSupported)
  if okS and sup then log("supported: " .. keysOf(sup, 30)) end
  local okF, fmts = pcall(love.graphics.getCanvasFormats)
  if okF and fmts then
    local want = { "depth16", "depth24", "depth32f", "depth24stencil8",
                   "rgba8", "rgba16f" }
    local out = {}
    for _, f in ipairs(want) do out[#out + 1] = f .. "=" .. tostring(fmts[f]) end
    log("canvas formats: " .. table.concat(out, " "))
  end
  local okC, canvas = pcall(love.graphics.newCanvas, 640, 360,
                            { format = "depth24", readable = false })
  log("depth24 canvas: " .. tostring(okC and canvas ~= nil))
  if okC and canvas and canvas.release then pcall(canvas.release, canvas) end
  local w, h = love.graphics.getDimensions()
  log("window: " .. w .. "x" .. h)

  log("")
  log("DONE")
  logf:close()
  wait(2)
  love.event.quit()
end
