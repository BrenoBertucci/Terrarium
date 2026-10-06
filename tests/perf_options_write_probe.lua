-- Probe: how long one options.lua write freezes the game (Game:writeOptions,
-- what every row change, the V key and a save all call). Writes the same
-- options back, so the file's content is unchanged.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/perf_options_write.log", "w"))
  local ok, err = pcall(function()
    for _ = 1, 120 do coroutine.yield() end
    local clock = love.timer.getTime
    local lib = game.mods.exports.TERRARIUM.lib
    local function g(m, f) local ok, M = pcall(lib.require, m) if not ok then return "?" end local ok2, v = pcall(M[f].get, M[f]) return tostring(ok2 and v) end
    logf:write(("loaded: RES=%s FX=%s ANIME=%s WATER=%s STYLE=%s SHADOWS=%s\n"):format(
      g("Quality", "setting"), g("RayFX", "setting"), g("Anime", "setting"), g("Water", "setting"),
      g("Water", "style"), g("Quality", "shadowSetting")))
    for i = 1, 3 do
      local t0 = clock()
      game:writeOptions()
      logf:write(("writeOptions #%d: %.0f ms\n"):format(i, (clock() - t0) * 1000))
      for _ = 1, 30 do coroutine.yield() end
    end
  end)
  if not ok then logf:write("ERROR " .. tostring(err) .. "\n") end
  logf:close()
  love.event.quit()
end
