-- Probe 7: is the tileset atlas COLOURED, or four shades of grey?
--
-- The world map colours a cell from its own tile, and which signal to read
-- depends entirely on this. If Assets.imageData hands back the recoloured
-- GBC atlas, the honest answer is the tile's own RGB and there is nothing to
-- decide. If it is the raw four-shade drawing, colour has to be invented per
-- class and lightness is the only thing separating a route's path from the
-- grass beside it -- which is the ramp the first cut guessed wrong.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/worldmap7.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    game.input.pressQueue[#game.input.pressQueue + 1] = "a"
    wait(10); n = n + 11
    if n > 1500 then break end
  end
  wait(45)

  local Game = require("src.core.Game")
  local MapLoader = require("src.world.MapLoader")
  local Assets = require("src.render.Assets")
  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  local WaterMap = lib.require("WaterMap")
  local TileShape = lib.require("TileShape")

  local m = select(2, pcall(MapLoader.load, Game.data, "VERMILION_CITY"))
  local ts = m.tileset
  log("tileset id=" .. tostring(ts.id) .. " image=" .. tostring(ts.image)
      .. " perRow=" .. tostring(ts.tilesPerRow)
      .. " " .. tostring(ts.imageWidth) .. "x" .. tostring(ts.imageHeight))

  local raw = Assets.imageData(ts.image)
  local iw, ih = raw:getDimensions()
  local perRow = ts.tilesPerRow or 16
  log("imageData: " .. iw .. "x" .. ih)

  local function tileRGB(t)
    local sx, sy = (t % perRow) * 8, math.floor(t / perRow) * 8
    if sx + 8 > iw or sy + 8 > ih then return nil end
    local r, g, b = 0, 0, 0
    for py = 0, 7 do
      for px = 0, 7 do
        local pr, pg, pb = raw:getPixel(sx + px, sy + py)
        r = r + pr; g = g + pg; b = b + pb
      end
    end
    return r / 64, g / 64, b / 64
  end

  -- Which tiles actually carry the ground of Kanto, and how often
  local counts, classOf = {}, {}
  for _, id in ipairs({ "VERMILION_CITY", "ROUTE_1", "ROUTE_11", "PEWTER_CITY" }) do
    local ok, mm = pcall(MapLoader.load, Game.data, id)
    if ok and mm then
      local shapes = TileShape.forMap(mm)
      for cy = 0, (mm.heightCells or 0) - 1 do
        for cx = 0, (mm.widthCells or 0) - 1 do
          local tx, ty = cx * 2, cy * 2 + 1
          local t = mm:tileAt(tx, ty)
          if t then
            local cls = "?"
            if WaterMap.surfaceCell(mm, cx, cy) then cls = "water"
            else
              local s = TileShape.at(mm, shapes, t, tx, ty)
              cls = (type(s) == "table" and s.class) or "?"
            end
            counts[t] = (counts[t] or 0) + 1
            classOf[t] = classOf[t] or cls
          end
        end
      end
    end
    coroutine.yield()
  end

  local ids = {}
  for t in pairs(counts) do ids[#ids + 1] = t end
  table.sort(ids, function(a, b) return counts[a] > counts[b] end)
  log("")
  log("the 30 commonest bottom-left tiles, with the atlas colour they carry:")
  log("  tile  count  class      R     G     B    grey?")
  for i = 1, math.min(30, #ids) do
    local t = ids[i]
    local r, g, b = tileRGB(t)
    if r then
      local mx = math.max(r, g, b)
      local mn = math.min(r, g, b)
      log(("  %4d %6d  %-9s %.3f %.3f %.3f  %s"):format(
          t, counts[t], classOf[t] or "?", r, g, b,
          (mx - mn) < 0.04 and "GREY" or "colour"))
    end
  end

  log("")
  log("grassTile=" .. tostring(ts.grassTile))
  local r, g, b = tileRGB(ts.grassTile or 82)
  if r then log(("  grass tile RGB %.3f %.3f %.3f"):format(r, g, b)) end

  -- and what the LIVE renderer has, which is the recoloured one if anything is
  log("")
  log("renderer fields: " .. (function()
    local ks = {}
    for k, v in pairs(m.renderer or {}) do
      ks[#ks + 1] = tostring(k) .. ":" .. type(v)
    end
    table.sort(ks); return table.concat(ks, " ") end)())

  log("")
  log("DONE")
  logf:close()
  wait(2)
  love.event.quit()
end
