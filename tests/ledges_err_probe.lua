-- Probe: capture the error the mesher swallows when a city's structures
-- build under the ledge banks. Calls Structures.forMap synchronously from
-- the driver coroutine (Budget.tick only yields inside the build coroutine)
-- under xpcall with a traceback, for one map, in the LEDGES mode named by
-- LEDGES_MODE (bank / classic).
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/ledges_err_probe.log", "w"))
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
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit() return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end
  local lib = game.mods.exports.TERRARIUM.lib
  local Structures = lib.require("Structures")
  local Buildings = lib.require("Buildings")
  local LedgeKit = lib.require("LedgeKit")
  local mode = os.getenv("LEDGES_MODE") or "bank"
  LedgeKit.setting:sync(mode)
  log("LEDGES mode:", mode)

  for _, site in ipairs({ { "CERULEAN_CITY", 7, 5 }, { "PEWTER_CITY", 6, 9 } }) do
    log("")
    log("[" .. site[1] .. "]")
    game.overworld:setMap(site[1], site[2], site[3], "down")
    wait(90)
    local map = game.overworld.map
    log("  map id:", tostring(map and map.id), "cached:", tostring(Structures.peek(map) ~= nil))
    -- drop any half-built entry so the synchronous call runs the build
    pcall(Structures.invalidate, map.id)
    local t0 = love.timer.getTime()
    local ok, err = xpcall(function() return Structures.forMap(map) end,
                           function(e) return tostring(e) .. "\n" .. debug.traceback("", 2) end)
    log(("  forMap: %s in %.2fs"):format(ok and "OK" or "ERROR", love.timer.getTime() - t0))
    if not ok then
      log(err)
    else
      local S = err
      log("  objectQuads:", S and #S.objectQuads or -1)
      local bp = Buildings.progress or {}
      log("  last progress:", tostring(bp.id), tostring(bp.phase), tostring(bp.tx), tostring(bp.ty), tostring(bp.step))
    end
  end
  logf:close()
  love.event.quit()
end
