-- Probe: THE CAVE STAIRS THAT WEAR WATER.
--
-- The class dump says a cave has NO tile of class `water` (CAVERN pins the
-- water tile $14 to `ground`), so whatever the player saw on the stairs is
-- not the water SURFACE pass. This stands the player two cells north of
-- every stair cell in the game that has the water tile immediately to its
-- SOUTH, and photographs it, with the neighbourhood printed as classes and
-- as raw tile ids so a photo can be read.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/cave_stairs_probe.lua ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/cave_stairs.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
    logf:write(table.concat(p, " "), "\n"); logf:flush()
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
    local g = 0
    while not done and g < 240 do coroutine.yield(); g = g + 1 end
    log("shot", name, done and "ok" or "TIMEOUT")
  end
  local function finish(m) if m then log(m) end logf:close() love.event.quit() end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then return finish("FAIL: no overworld") end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then return finish("FAIL: TERRARIUM not loaded") end
  log("version:", exports.TERRARIUM.version)

  local TileShape = lib.require("TileShape")
  local Voxel3D   = lib.require("Voxel3D")
  local Quality   = lib.require("Quality")
  local DayNight  = lib.require("DayNight")
  local Weather   = lib.require("Weather")
  local RayFX     = lib.require("RayFX")
  local function sync(s, v) if s then pcall(s.sync, s, v) end end
  sync(Weather.setting, "off"); sync(DayNight.setting, "day")
  sync(Quality.setting, 2);     sync(RayFX.setting, "rt")

  local function holdStill(f)
    local p = game.overworld.player
    local lx, ly, same = nil, nil, 0
    for _ = 1, 600 do
      local x, y = p and p.cellX, p and p.cellY
      if x == lx and y == ly then same = same + 1 else same = 0 end
      lx, ly = x, y
      if same >= f then return true end
      coroutine.yield()
    end
    return false
  end

  -- stair cells ($15/$16 pinned `ledge`) with the water tile $14 due SOUTH
  local SPOTS = {
    { "SEAFOAM_ISLANDS_B4F", 7, 11 },
    { "SEAFOAM_ISLANDS_B4F", 7, 3 },
    { "SEAFOAM_ISLANDS_B4F", 23, 5 },
    { "SEAFOAM_ISLANDS_B3F", 15, 7 },
    { "CERULEAN_CAVE_1F", 15, 3 },
    { "CERULEAN_CAVE_1F", 25, 9 },
    { "CERULEAN_CAVE_B1F", 19, 11 },
  }

  local SYM = { water = "W", ground = ".", wall = "#", ledge = "l",
                stair_e = "E", stair_w = "e", stair_down_e = "D",
                stair_down_w = "u", relief = "r", cliff = "C", void = " " }

  local function dump(map, cx, cy)
    local shapes = TileShape.forMap(map)
    for ty = (cy - 4) * 2, (cy + 4) * 2 + 1 do
      local row, ids = {}, {}
      for tx = (cx - 6) * 2, (cx + 6) * 2 + 1 do
        local tile = map:tileAt(tx, ty)
        local s = tile and TileShape.at(map, shapes, tile, tx, ty)
        row[#row + 1] = SYM[s and s.class] or "?"
        ids[#ids + 1] = ("%02X"):format(tile or 0)
      end
      log(("   %3d %s   h=%s"):format(ty, table.concat(row),
          table.concat(ids, " ")))
    end
  end

  for i, sp in ipairs(SPOTS) do
    local id, cx, cy = sp[1], sp[2], sp[3]
    local ok = pcall(function()
      -- stand two cells NORTH of the stair, facing down the flight
      game.overworld:setMap(id, cx, cy - 2, "down")
    end)
    if not ok then
      log(("[%s %d,%d] SKIP setMap"):format(id, cx, cy))
    else
      wait(20)
      local map = game.overworld.map
      log(("[%s] stair cell %d,%d  (player parked at %d,%d)")
          :format(id, cx, cy, cx, cy - 2))
      local okd, err = pcall(dump, map, cx, cy)
      if not okd then log("   dump failed: " .. tostring(err)) end
      Voxel3D.lampLights = nil
      for _ = 1, 240 do
        if Voxel3D.lampLights ~= nil then break end
        coroutine.yield()
      end
      holdStill(40)
      wait(120)
      local p = game.overworld.player
      log(("   player now %s,%s"):format(tostring(p and p.cellX),
                                         tostring(p and p.cellY)))
      shot(("cavestair_%02d_%s_%d_%d.png"):format(i, id, cx, cy))
    end
    log("---")
  end
  finish("done")
end
