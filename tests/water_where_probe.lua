-- Probe: WHERE DOES THE MOD THINK WATER IS.
--
-- Diagnostic for three reported bugs: water inside the Indigo Plateau
-- Pokemon Center, water reading as a block at the Cerulean seams, and
-- water on top of stairs in a cave.
--
-- It does not guess from the data files: it asks the LIVE TileShape the
-- class of every tile of every map listed, counts the "water" ones, and
-- prints the neighbourhood as the mesher sees it. Screenshots come second,
-- because a class dump says WHICH tile is wrong and a photo only says that
-- something is.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/water_where_probe.lua ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/water_where.log", "w"))
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
    local done = false
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      done = true
    end)
    local guard = 0
    while not done and guard < 240 do coroutine.yield(); guard = guard + 1 end
    log("shot", name, done and "ok" or "TIMEOUT")
  end
  local function finish(msg)
    if msg then log(msg) end
    logf:close()
    love.event.quit()
  end

  -- An error inside the GAME's own update (a mesh build, say) kills the
  -- driver coroutine without ever reaching this file's xpcall, and LOVE's
  -- blue screen is not on stdout under --console. Catch it here so a
  -- broken frame leaves a traceback in the probe directory instead of a
  -- log that simply stops.
  local prevHandler = love.errorhandler or love.errhand
  love.errorhandler = function(err)
    local f = io.open(OUT .. "/CRASH.txt", "w")
    if f then
      f:write(tostring(err), "\n\n", debug.traceback("", 2), "\n")
      f:close()
    end
    pcall(function() logf:write("CRASH: ", tostring(err), "\n"); logf:flush() end)
    love.event.quit()
    return function() return 1 end
  end
  love.errhand = love.errorhandler
  local _ = prevHandler

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then return finish("FAIL: no overworld") end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then return finish("FAIL: TERRARIUM not loaded") end
  log("version:", exports.TERRARIUM.version)

  local TileShape = lib.require("TileShape")
  local Voxel3D   = lib.require("Voxel3D")
  local Quality   = lib.require("Quality")
  local Weather   = lib.require("Weather")
  local DayNight  = lib.require("DayNight")
  local RayFX     = lib.require("RayFX")
  local Water     = lib.require("Water")
  local function sync(s, v) if s then pcall(s.sync, s, v) end end
  sync(Weather.setting, "off")
  sync(DayNight.setting, "day")
  sync(Quality.setting, 2)
  sync(RayFX.setting, "rt")
  sync(Water.setting, 0.8)

  local function wait3D(cap)
    for i = 1, (cap or 900) do
      if Voxel3D.lampLights ~= nil then return i end
      coroutine.yield()
    end
    return -1
  end
  local function holdStill(frames)
    local p = game.overworld.player
    local lx, ly, same = nil, nil, 0
    for _ = 1, 600 do
      local x, y = p and p.cellX, p and p.cellY
      if x == lx and y == ly then same = same + 1 else same = 0 end
      lx, ly = x, y
      if same >= frames then return true end
      coroutine.yield()
    end
    return false
  end

  -- ---- the class dump: what TileShape actually answers, per TILE
  local function classGrid(map)
    local shapes = TileShape.forMap(map)
    local TW = (map.widthCells or 0) * 2
    local TH = (map.heightCells or 0) * 2
    local grid, counts = {}, {}
    for ty = 0, TH - 1 do
      grid[ty] = {}
      for tx = 0, TW - 1 do
        local tile = map:tileAt(tx, ty)
        local s = tile and TileShape.at(map, shapes, tile, tx, ty)
        local c = s and s.class or "?"
        grid[ty][tx] = c
        counts[c] = (counts[c] or 0) + 1
      end
    end
    return grid, counts, TW, TH
  end

  local SYM = { water = "W", ground = ".", wall = "#", grass = "\"",
                ledge = "l", cliff = "C", tree = "T", counter = "c",
                table = "t", desk = "d", bed = "b", prop = "p",
                bookcase = "B", stair_e = "E", stair_w = "e",
                stair_down_e = "D", stair_down_w = "u", void = " ",
                relief = "r", cylinder = "o", canopy = "O", fence = "f",
                sign = "s", roof = "^", cutout = "x", stool = "S" }
  local function sym(c) return SYM[c] or "?" end

  -- Every water TILE, with the tile id under it -- so a false water can be
  -- named by the id that caused it, not just pointed at.
  local function waterTiles(map, grid, TW, TH)
    local byTile, cells = {}, {}
    for ty = 0, TH - 1 do
      for tx = 0, TW - 1 do
        if grid[ty][tx] == "water" then
          local id = map:tileAt(tx, ty)
          byTile[id] = (byTile[id] or 0) + 1
          local key = math.floor(tx / 2) .. "," .. math.floor(ty / 2)
          cells[key] = true
        end
      end
    end
    local nCells = 0
    for _ in pairs(cells) do nCells = nCells + 1 end
    return byTile, nCells
  end

  local MAPS = {
    -- bug A: the interior that showed water
    { id = "INDIGO_PLATEAU_LOBBY", at = { 8, 6 },  shotd = true },
    { id = "LORELEIS_ROOM",        at = { 4, 8 },  shotd = true },
    { id = "LANCES_ROOM",          at = { 5, 10 }, shotd = true },
    { id = "FIGHTING_DOJO",        at = { 4, 8 } },
    { id = "CELADON_MART_1F",      at = { 8, 6 } },
    { id = "VIRIDIAN_FOREST_SOUTH_GATE", at = { 4, 5 } },
    -- bug C: caves with stairs
    { id = "SEAFOAM_ISLANDS_B4F",  at = { 8, 8 },  shotd = true },
    { id = "SEAFOAM_ISLANDS_B3F",  at = { 8, 8 } },
    { id = "CERULEAN_CAVE_1F",     at = { 12, 12 }, shotd = true },
    { id = "VICTORY_ROAD_1F",      at = { 8, 8 },  shotd = true },
    { id = "VICTORY_ROAD_2F",      at = { 8, 8 } },
    { id = "VICTORY_ROAD_3F",      at = { 8, 8 } },
    { id = "ROCK_TUNNEL_1F",       at = { 8, 8 } },
    { id = "MT_MOON_B2F",          at = { 8, 8 } },
    -- bug B: the seam
    { id = "CERULEAN_CITY",        at = { 8, 15 }, shotd = true },
    { id = "ROUTE_4",              at = { 85, 7 }, shotd = true },
    { id = "ROUTE_23",             at = { 8, 92 }, shotd = true },
  }

  -- one map's whole pass, so an error names the map instead of ending the
  -- run in silence (the first cut died on map 1 and wrote nothing)
  local function doMap(m)
    local ok = pcall(function()
      game.overworld:setMap(m.id, m.at[1], m.at[2], "up")
    end)
    if not ok then
      log(("[%s] SKIP: setMap failed"):format(m.id))
    else
      wait(20)
      local map = game.overworld.map
      local okG, grid, counts, TW, TH = pcall(classGrid, map)
      if not okG then
        log(("[%s] class dump FAILED: %s"):format(m.id, tostring(grid)))
      else
        local byTile, nCells = waterTiles(map, grid, TW, TH)
        local parts = {}
        for id, c in pairs(byTile) do
          parts[#parts + 1] = ("$%02X x%d"):format(id, c)
        end
        table.sort(parts)
        log(("[%s] tileset=%s  %dx%d tiles  waterTiles=%d in %d cells  [%s]")
            :format(m.id, tostring(map.tileset and map.tileset.id),
                    TW, TH, counts.water or 0, nCells,
                    table.concat(parts, ", ")))
        -- the class map, but only rows that carry water (a 144-row route
        -- prints nothing useful otherwise)
        local shown = 0
        for ty = 0, TH - 1 do
          local any = false
          for tx = 0, TW - 1 do
            if grid[ty][tx] == "water" then any = true break end
          end
          if any and shown < 40 then
            local row = {}
            for tx = 0, math.min(TW, 120) - 1 do
              row[#row + 1] = sym(grid[ty][tx])
            end
            log(("   %3d %s"):format(ty, table.concat(row)))
            shown = shown + 1
          end
        end
        if shown >= 40 then log("   ... (more water rows not printed)") end
      end
      if m.shotd then
        Voxel3D.lampLights = nil
        local up = wait3D(900)
        holdStill(40)
        wait(150)
        local pl = game.overworld.player
        log(("[%s] 3D up after %s; player=%s,%s"):format(
            m.id, tostring(up), tostring(pl and pl.cellX), tostring(pl and pl.cellY)))
        shot(("where_%s.png"):format(m.id))
      end
    end
    log("---")
  end

  for _, m in ipairs(MAPS) do
    local ok, err = xpcall(doMap, debug.traceback, m)
    if not ok then log(("[%s] ERROR %s"):format(m.id, tostring(err))) end
  end

  finish("done")
end
