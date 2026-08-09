-- Probe: find the gate houses' floor.
--
-- The paving being asked for is the checked floor inside the little
-- transition houses between a city and a route. Those are INTERIORS, on
-- their own tileset -- nothing measured off an overworld atlas applies to
-- them, which is why the first cut of FloorArt landed on a Fuchsia roof
-- instead: same two pinks, different building, wrong sheet entirely.
--
-- So this reads the gates themselves: which maps they are, what atlas they
-- sample, the colours in it, and how high the floor stands.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/gate_floor_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/gate_floor_probe.log", "w"))
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
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
    wait(4)
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
  local Voxel3D = lib.require("Voxel3D")
  local DayNight = lib.require("DayNight")
  local Pipelines = require("src.render.Pipelines")
  DayNight.setting:sync("day")
  pcall(Pipelines.setLevel, "terrarium_voxel", 4)

  -- ------- which maps are gates
  local maps = game.data and game.data.maps or {}
  local gates = {}
  for id, def in pairs(maps) do
    if type(id) == "string"
       and (id:find("UNDERGROUND") or id:find("GATE")) then
      gates[#gates + 1] = { id = id, def = def }
    end
  end
  table.sort(gates, function(a, b) return a.id < b.id end)
  log(("gate maps: %d"):format(#gates))
  for i = 1, math.min(#gates, 40) do
    local d = gates[i].def
    log(("  %-28s %sx%s tileset=%s")
        :format(gates[i].id, tostring(d and d.width), tostring(d and d.height),
                tostring(d and d.tileset)))
  end
  if #gates == 0 then
    log("no gate maps found -- dumping every tileset name instead")
    local seen = {}
    for id, def in pairs(maps) do
      local t = def and def.tileset
      if t and not seen[t] then seen[t] = id end
    end
    for t, id in pairs(seen) do log(("  tileset %s (e.g. %s)"):format(t, id)) end
    logf:close(); love.event.quit(); return
  end

  local function wait3D(cap)
    for i = 1, (cap or 600) do
      if Voxel3D.lampLights ~= nil then return i end
      coroutine.yield()
    end
    return -1
  end

  -- ------- walk into the first few and read them
  local shown = 0
  for _, g in ipairs(gates) do
    if shown >= 3 then break end
    if not g.id:find("UNDERGROUND") then goto continue end
    local ok = pcall(function()
      game.overworld:setMap(g.id, 2, 4, "down")
    end)
    if ok then
      Voxel3D.lampLights = nil
      wait3D(600)
      wait(90)
      local map = game.overworld and game.overworld.map
      if map then
        shown = shown + 1
        local r = map.renderer
        log(("[%s] tileset=%s gbcAtlas=%s")
            :format(g.id, tostring(map.tileset and map.tileset.image),
                    tostring(r and r.gbcAtlas ~= nil)))
        local img = nil
        local okA, a = pcall(TerrainAtlas.forMap, map, nil)
        if okA then img = a end
        if not img then img = r and r.image end
        if img then
          local w, h = img:getDimensions()
          log(("  atlas %dx%d"):format(w, h))
          pcall(function()
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
            local f = io.open(OUT .. "/atlas_" .. g.id .. ".png", "wb")
            if f then f:write(d:encode("png"):getString()) f:close() end
            -- the reddest texels in the sheet, which is the floor if this is
            -- the right sheet at all -- logged so the colour box can be set
            -- from a reading rather than from a look at a screenshot
            local best = {}
            for y = 0, h - 1 do
              for x = 0, w - 1 do
                local rr, gg, bb, aa = d:getPixel(x, y)
                if aa > 0.5 and rr > 0.55 and rr - gg > 0.20 then
                  local k = ("%.3f,%.3f,%.3f"):format(rr, gg, bb)
                  best[k] = (best[k] or 0) + 1
                end
              end
            end
            local list = {}
            for k, v in pairs(best) do list[#list + 1] = { k = k, v = v } end
            table.sort(list, function(p, q) return p.v > q.v end)
            for i = 1, math.min(#list, 10) do
              log(("  red %-22s x%d"):format(list[i].k, list[i].v))
            end
          end)
        end
        -- how high the floor under the player stands, pre-curve: the height
        -- gate needs this and guessing it is what cost the last round
        local p = game.overworld.player
        if p then
          local okH, gh = pcall(function()
            local VoxelScene = lib.require("VoxelScene")
            return VoxelScene.groundAt and VoxelScene.groundAt(map, p.cellX, p.cellY)
          end)
          log(("  player cell=(%s,%s) groundAt=%s")
              :format(tostring(p.cellX), tostring(p.cellY),
                      okH and tostring(gh) or "n/a"))
        end
        shot(("gate_%s.png"):format(g.id))
      end
    end
    ::continue::
  end

  logf:close()
  love.event.quit()
end
