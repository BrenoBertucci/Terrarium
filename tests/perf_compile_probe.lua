-- Probe: how long the scene shader takes to COMPILE on this driver, with and
-- without the ANIME water variant, and the RayFX rungs. The first 3D frame
-- after a map entry stalled 7.6 s in the build with ANIME_WATER against 1.9 s
-- without it; this times the compiles alone (Voxel3D.buildRung builds past
-- the cache, so each one is a real driver compile).
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/perf_compile.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local okAll, err = pcall(function()
    local function wait(n) for _ = 1, n do coroutine.yield() end end
    wait(120)
    local lib = game.mods.exports.TERRARIUM.lib
    local Voxel3D, Water, Glow = lib.require("Voxel3D"), lib.require("Water"), lib.require("Glow")
    local clock = love.timer.getTime
    local function time(tag, fn)
      local best = 1e9
      for i = 1, 3 do
        local t0 = clock()
        local ok, r = fn()
        local d = clock() - t0
        if d < best then best = d end
        if i == 1 then log(("%-28s %s"):format(tag, ok and "ok" or ("FAIL " .. tostring(r)))) end
      end
      log(("%-28s best of 3: %.0f ms"):format(tag, best * 1000))
    end
    for _, style in ipairs({ "classic", "anime" }) do
      pcall(Water.style.sync, Water.style, style)
      time("scene " .. style .. " (no glow)", function() return Voxel3D.buildRung(1, false, 1, false) end)
      time("scene " .. style .. " (glow)", function() return Voxel3D.buildRung(1, false, 1, true) end)
    end
  end)
  if not okAll then log("ERROR", tostring(err)) end
  logf:close()
  love.event.quit()
end
