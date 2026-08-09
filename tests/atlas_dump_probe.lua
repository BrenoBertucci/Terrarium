-- Probe: dump the atlas the terrain actually samples.
--
-- Terrain in this mode is textured from the tileset atlas, and WHICH atlas
-- depends on the colour path (see TerrainAtlas): RED++ hands over a fully
-- recoloured per-map bake, a true-colour mod hands over its own art, and the
-- SGB modes get a grey sheet this mod recolours itself. Anything that wants
-- to recognise a tile BY ITS COLOUR has to know which of those it is looking
-- at -- a matcher tuned against a screenshot is tuned against the atlas
-- times the shade times the hour's light, which is three unknowns.
--
-- So: read it back and look at it.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/atlas_dump_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/atlas_dump_probe.log", "w"))
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

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end
  local TerrainAtlas = lib.require("TerrainAtlas")
  local DayNight = lib.require("DayNight")
  DayNight.setting:sync("day")

  local function dump(mapId, x, y)
    local ok = pcall(function() game.overworld:setMap(mapId, x, y, "down") end)
    if not ok then log("SKIP " .. mapId) return end
    wait(120)
    local map = game.overworld and game.overworld.map
    if not map then log("no map " .. mapId) return end
    local r = map.renderer
    log(("[%s] tileset=%s trueColor=%s gbcAtlas=%s")
        :format(mapId, tostring(map.tileset and map.tileset.image),
                tostring(map.tileset and map.tileset.trueColor),
                tostring(r and r.gbcAtlas ~= nil)))
    -- The image the MESH samples, not the file on disk: forFrame is what
    -- ChunkMesher's uv rects are cut against.
    local img = nil
    local okA, a = pcall(TerrainAtlas.forMap, map, nil)
    if okA then img = a end
    if not img then img = r and r.image end
    if not img then log("  no atlas image") return end
    local w, h = img:getDimensions()
    log(("  atlas %dx%d"):format(w, h))
    local okC = pcall(function()
      local c = love.graphics.newCanvas(w, h)
      love.graphics.setCanvas(c)
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.setShader()
      love.graphics.setBlendMode("alpha", "premultiplied")
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, 0, 0)
      love.graphics.setBlendMode("alpha")
      love.graphics.setCanvas()
      local d = c:newImageData()
      local f = io.open(OUT .. "/atlas_" .. mapId .. ".png", "wb")
      if f then f:write(d:encode("png"):getString()) f:close() end
    end)
    log("  dumped=" .. tostring(okC))
  end

  dump("FUCHSIA_CITY", 18, 20)
  logf:close()
  love.event.quit()
end
