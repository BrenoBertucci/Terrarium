-- One-shot: dump VoxelScene.groundAt over a PALLET_TOWN cell grid, so the
-- sun-shadow probe's building search can be aimed with real numbers
-- instead of guessed thresholds.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/ground_grid.log", "w"))
  local function log(s) logf:write(s, "\n"); logf:flush() end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit() return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  local VoxelScene = lib.require("VoxelScene")
  local DayNight = lib.require("DayNight")

  DayNight.setting:sync("day")
  local ow = game.overworld
  ow:setMap("PALLET_TOWN", 12, 12, "up")
  wait(300)
  local map = ow.map
  log("map " .. tostring(map.id) .. "  player "
      .. ow.player.cellX .. "," .. ow.player.cellY)

  -- heights, hex-coded /2 (so 'B' = 22+), '.' for 0
  for cy = 0, 20 do
    local row = {}
    for cx = 0, 24 do
      local ok, h = pcall(VoxelScene.groundAt, map, cx, cy)
      h = (ok and tonumber(h)) or 0
      local code
      if h <= 0 then code = "."
      else
        local v = math.floor(h / 2)
        if v > 35 then v = 35 end
        code = string.sub("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ", v + 1, v + 1)
      end
      row[#row + 1] = code
    end
    log(string.format("cy=%02d  %s", cy, table.concat(row)))
  end
  log("done")
  logf:close()
  love.event.quit()
end
