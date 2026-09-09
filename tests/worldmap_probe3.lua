-- Probe 3: can the mod's own tile classifier describe the whole region?
--
-- The voxel overworld already answers "what shape is this tile" for the map
-- the player stands on (lib/TileShape.lua, over data/voxel_heights.lua). A
-- world map wants the same answer for all 34 outdoor maps at once, at CELL
-- granularity. Three things have to hold and none is obvious:
--
--   * TileShape.forMap works on a map the player is NOT standing on.
--   * The classes that come back are few enough to hand a palette to, and
--     they describe Kanto rather than degenerating to wall/ground.
--   * The whole pass -- load, classify, 40k cells -- fits in a budget that
--     can be spread over frames.
--
-- It also asks the screen what its own methods are called, because drawing
-- over it means shadowing one of them on the INSTANCE (lib/StartMenuXY.lua).
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/worldmap3.log", "w"))
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

  local Game = require("src.core.Game")
  local Map = require("src.world.Map")
  local MapLoader = require("src.world.MapLoader")
  local maps = Game.data.maps
  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  local TileShape = lib.require("TileShape")
  local WaterMap = lib.require("WaterMap")

  ------------------------------------------------------------- SCREEN METHODS
  log("=== the screen's own methods ===")
  local TownMap = require("src.ui.TownMap")
  local made, screen = pcall(TownMap.new, game)
  if made and screen then
    local mt = getmetatable(screen)
    local seen = {}
    local function dump(where, t, depth)
      if type(t) ~= "table" or depth > 3 or seen[t] then return end
      seen[t] = true
      local fns, fields = {}, {}
      for k, v in pairs(t) do
        if type(v) == "function" then fns[#fns + 1] = tostring(k)
        else fields[#fields + 1] = tostring(k) .. ":" .. type(v) end
      end
      table.sort(fns); table.sort(fields)
      log(where .. " functions: " .. table.concat(fns, " "))
      if #fields > 0 then
        log(where .. " fields: " .. table.concat(fields, " "))
      end
      local idx = rawget(t, "__index")
      if type(idx) == "table" and idx ~= t then dump(where .. ".__index", idx, depth + 1) end
      local m2 = getmetatable(t)
      if type(m2) == "table" then dump(where .. "<mt>", m2, depth + 1) end
    end
    dump("TownMap(class)", TownMap, 1)
    dump("instance<mt>", mt, 1)
    log("TownMap == getmetatable(screen)? " .. tostring(mt == TownMap))
    log("TownMap.__index == TownMap? " .. tostring(rawget(TownMap, "__index") == TownMap))
  end

  --------------------------------------------------------------- CLASSIFY ALL
  log("")
  log("=== classifying the region ===")
  local OverworldState = require("src.world.OverworldController")
  local ok, raw = pcall(OverworldState.computeNeighbors, maps, "PALLET_TOWN", 40)
  local list = { { id = "PALLET_TOWN", ox = 0, oy = 0 } }
  for _, nb in ipairs(ok and raw or {}) do
    local def = maps[nb.id]
    local okO, yes = pcall(Map.isOutdoor, def)
    if okO and yes then list[#list + 1] = { id = nb.id, ox = nb.ox, oy = nb.oy } end
  end
  log("maps to classify: " .. #list)

  local hist, cells = {}, 0
  local tLoad, tClass = 0, 0
  local grids = {}
  for i, e in ipairs(list) do
    local t0 = os.clock()
    local okL, m = pcall(MapLoader.load, Game.data, e.id)
    tLoad = tLoad + (os.clock() - t0)
    if okL and m then
      local t1 = os.clock()
      local okS, shapes = pcall(TileShape.forMap, m)
      if not okS then
        log("  TileShape.forMap FAILED on " .. e.id .. ": " .. tostring(shapes))
      else
        local mw, mh = m.widthCells or 0, m.heightCells or 0
        local grid = { id = e.id, w = mw, h = mh, ox = e.ox, oy = e.oy, c = {} }
        for cy = 0, mh - 1 do
          for cx = 0, mw - 1 do
            -- collision granularity: the cell is judged by its bottom-left
            -- 8x8 tile (see lib/WaterMap.lua rule 3)
            local tx, ty = cx * 2, cy * 2 + 1
            local tile = m:tileAt(tx, ty)
            local cls = "?"
            if WaterMap.surfaceCell(m, cx, cy) then
              cls = "water"
            else
              local shp = tile and TileShape.at(m, shapes, tile, tx, ty)
              if type(shp) == "table" then
                cls = tostring(shp.class or shp.name or shp.art or "table")
              elseif shp ~= nil then
                cls = tostring(shp)
              end
            end
            hist[cls] = (hist[cls] or 0) + 1
            cells = cells + 1
            grid.c[cy * mw + cx + 1] = cls
          end
        end
        grids[#grids + 1] = grid
      end
      tClass = tClass + (os.clock() - t1)
    else
      log("  load failed: " .. e.id)
    end
    if i % 4 == 0 then coroutine.yield() end
  end

  log(("cells=%d  load=%.0f ms  classify=%.0f ms  total=%.0f ms")
      :format(cells, tLoad * 1000, tClass * 1000, (tLoad + tClass) * 1000))
  log("class histogram:")
  local names = {}
  for k in pairs(hist) do names[#names + 1] = k end
  table.sort(names, function(a, b) return hist[a] > hist[b] end)
  for _, k in ipairs(names) do
    log(("  %-12s %6d  %5.1f%%"):format(k, hist[k], 100 * hist[k] / cells))
  end

  ------------------------------------------------------------- WHAT A SHAPE IS
  log("")
  log("=== one shape object ===")
  local okL, m = pcall(MapLoader.load, Game.data, "VERMILION_CITY")
  if okL and m then
    local shapes = TileShape.forMap(m)
    local t = m:tileAt(0, 1)
    local s = TileShape.at(m, shapes, t, 0, 1)
    if type(s) == "table" then
      local ks = {}
      for k, v in pairs(s) do ks[#ks + 1] = tostring(k) .. "=" .. tostring(v) end
      table.sort(ks)
      log("shape fields: " .. table.concat(ks, " "))
    else
      log("shape is " .. type(s) .. ": " .. tostring(s))
    end
  end

  ------------------------------------------------------------------ EYEBALL IT
  local GLYPH = { water = "~", ground = ".", wall = "#", tree = "T",
                  fence = "=", sign = "i", ledge = "_", roof = "^",
                  void = " ", ["?"] = "?" }
  for _, want in ipairs({ "VERMILION_CITY", "ROUTE_21", "CERULEAN_CITY" }) do
    for _, g in ipairs(grids) do
      if g.id == want then
        log("")
        log("=== " .. g.id .. " " .. g.w .. "x" .. g.h .. " ===")
        for cy = 0, math.min(g.h, 40) - 1 do
          local row = {}
          for cx = 0, g.w - 1 do
            local c = g.c[cy * g.w + cx + 1]
            row[#row + 1] = GLYPH[c] or (c and c:sub(1, 1)) or "?"
          end
          log("  " .. table.concat(row))
        end
      end
    end
  end

  ------------------------------------------------------------------- DAY/NIGHT
  log("")
  local DayNight = lib.require("DayNight")
  local fns = {}
  for k, v in pairs(DayNight) do
    if type(v) == "function" then fns[#fns + 1] = tostring(k) end
  end
  table.sort(fns)
  log("DayNight functions: " .. table.concat(fns, " "))

  log("")
  log("DONE")
  logf:close()
  wait(2)
  love.event.quit()
end
