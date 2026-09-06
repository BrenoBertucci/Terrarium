-- Probe: what the Pokemon Center INTERIOR looks like in the 3D pass.
-- Walks into VIRIDIAN_POKECENTER, pins day, waits for the voxel pass and
-- the player's cell, shoots from three anchors (door, counter, PC) and
-- dumps the map's shape table (class/h per cell) so the authored table
-- in data/voxel_heights.lua can be judged against what it produced.
--
-- POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
-- POKEPORT_DRIVER=mods/TERRARIUM/tests/pokecenter_interior_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local MAP = os.getenv("DS_PROBE_MAP") or "VIRIDIAN_POKECENTER"
  local logf = assert(io.open(OUT .. "/pokecenter_interior_probe.log", "w"))
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
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit()
    return
  end
  log("version:", exports.TERRARIUM.version)

  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local Voxel3D = lib.require("Voxel3D")
  local Structures = lib.require("Structures")
  local VoxelScene = lib.require("VoxelScene")

  Weather.setting:sync("off")
  DayNight.setting:sync("day")
  local ww, wh = love.graphics.getDimensions()
  log(("window: %dx%d"):format(ww, wh))

  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      done = true
    end)
    for _ = 1, 600 do
      if done then return true end
      coroutine.yield()
    end
    return false
  end

  -- indoors there are no lamps, so lampLights is a false negative: poll
  -- objectQuads + a settle instead
  local function lockCell(guard)
    local last, stable = nil, 0
    for _ = 1, guard or 1200 do
      local p = game.overworld.player
      local cur = p and (tostring(p.cellX) .. "," .. tostring(p.cellY)) or "?"
      if cur == last then stable = stable + 1 else stable, last = 0, cur end
      if stable >= 45 then return true, cur end
      coroutine.yield()
    end
    return false, last
  end

  local ANCHORS = {
    { name = "door", x = 3, y = 6, dir = "up" },
    { name = "counter", x = 3, y = 3, dir = "up" },
    { name = "pc", x = 12, y = 3, dir = "right" },
  }
  -- the Marts are a 4x4-cell room: door bottom-right, clerk top-left
  if MAP:find("MART", 1, true) then
    ANCHORS = {
      { name = "door", x = 3, y = 3, dir = "up" },
      { name = "clerk", x = 1, y = 2, dir = "up" },
      { name = "shelf", x = 3, y = 1, dir = "left" },
    }
  end

  for _, a in ipairs(ANCHORS) do
    local ok, err = pcall(function()
      game.overworld:setMap(MAP, a.x, a.y, a.dir)
    end)
    if not ok then
      log(a.name, "FAIL: setMap error", tostring(err))
    else
      wait(60)
      local map = game.overworld.map
      log("")
      log(("[%s] map=%s tileset=%s size=%sx%s"):format(a.name,
          tostring(map.id), tostring(map.tileset and map.tileset.id),
          tostring(map.def and map.def.width),
          tostring(map.def and map.def.height)))
      local locked, cell = lockCell()
      log(("  player cell locked: %s at (%s)"):format(
          locked and "PASS" or "FAIL", tostring(cell)))
      wait(240)
      local S = Structures.forMap(map)
      log(("  objectQuads=%d figures=%d outdoor=%s"):format(
          #S.objectQuads, S.figures and #S.figures or 0, tostring(S.outdoor)))
      local okSh, sh = pcall(Voxel3D.shader)
      log(("  shader ok=%s %s err=%s"):format(tostring(okSh), tostring(sh),
          tostring(Voxel3D.shaderError)))
      log("  shot:", shot(MAP .. "_" .. a.name .. ".png") and "PASS" or "FAIL")

      if a.name == "door" then
        local tw, th = map.def.width * 4, map.def.height * 4
        -- the RAW map tiles, before the figure pass repaints the ones a
        -- standee was lifted off (Buildings.build matches these)
        log("  raw map tiles (map:tileAt):")
        for ty = 0, th - 1 do
          local row = {}
          for tx = 0, tw - 1 do
            local ok, t = pcall(map.tileAt, map, tx, ty)
            row[#row + 1] = ("%3s"):format(ok and tostring(t) or "?")
          end
          log("   " .. ("%2d"):format(ty) .. " | " .. table.concat(row, " "))
        end
        -- the shape table: one line per 8px tile row, class letter + height
        log("  tile grid (8px tiles), class/h per tile:")
        for ty = 0, th - 1 do
          local row = {}
          for tx = 0, tw - 1 do
            local k = (ty + 64) * 4096 + (tx + 64)   -- Structures.keyOf
            local s = S.shapeAt[k]
            local t = S.tileAt[k]
            row[#row + 1] = ("%3s:%-6s%3s"):format(tostring(t),
                s and tostring(s.class):sub(1, 6) or "-",
                s and tostring(s.h) or "")
          end
          log("   " .. ("%2d"):format(ty) .. " | " .. table.concat(row, " "))
        end
      end
    end
  end

  log("")
  log("DONE")
  logf:close()
  love.event.quit()
end
