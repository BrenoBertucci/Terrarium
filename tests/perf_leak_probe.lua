-- Probe: WHO HOLDS the heap that grows with every map visited. Inflates the
-- heap by walking a chain of maps, then calls each system's own drop /
-- invalidate, one at a time, collecting fully between, and logs how much
-- each one gave back. Whatever releases hundreds of MB is the leak.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/perf_leak.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local okAll, err = pcall(function()
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b) game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield() end
  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do wait(1); n = n + 1; if n > 900 then break end end
  n = 0
  while game.stack:top() ~= game.overworld do tap("a"); wait(10); n = n + 11; if n > 1500 then break end end
  local ow = game.overworld
  ow.rollEncounter = function() return nil end
  local lib = game.mods.exports.TERRARIUM.lib
  local clock = love.timer.getTime
  local function live()
    collectgarbage("collect"); collectgarbage("collect")
    return collectgarbage("count") / 1024
  end
  for _, id in ipairs({ "PALLET_TOWN", "ROUTE_1", "VIRIDIAN_CITY", "ROUTE_2", "PEWTER_CITY",
                        "ROUTE_22", "ROUTE_1", "PALLET_TOWN" }) do
    pcall(function() ow:setMap(id, 8, 8, "down") end)
    local t0 = clock()
    while clock() - t0 < 20 do coroutine.yield(); if game.stack:top() ~= ow then pcall(function() game.stack:pop() end) end end
    log(("visited %-14s live %.1f MB"):format(id, live()))
  end
  -- freeze the world so nothing rebuilds between drops
  local Pipelines = require("src.render.Pipelines")
  local level = Pipelines.level("terrarium_voxel")
  pcall(Pipelines.setLevel, "terrarium_voxel", 0)
  wait(10)
  local base = live()
  log(("3D off: live %.1f MB"):format(base))
  local DROPS = {
    { "Buildings", "invalidate" }, { "Structures", "invalidate" }, { "ChunkMesher", "invalidate" },
    { "Trees3D", "invalidate" }, { "Grass3D", "invalidate" }, { "GrassWear", "reset" },
    { "TerrainAtlas", "invalidate" }, { "WorldAtlas", "invalidate" }, { "GroundFX", "invalidate" },
    { "PuddleFX", "invalidate" }, { "SnowField", "invalidate" }, { "ReefKit", "forget" },
    { "LeafFallFX", "forget" }, { "SpriteBillboards", "invalidate" }, { "ImageCache", "invalidate" },
    { "RoamerArt", "invalidate" }, { "Shelter", "invalidate" }, { "WaterBody", "invalidate" },
    { "ShadowMap", "invalidate" }, { "Glow", "invalidate" }, { "Sky", "invalidate" },
    { "GlassMask", "invalidate" }, { "MiniMap", "invalidate" }, { "Ripples", "reset" },
  }
  local prev = base
  for _, d in ipairs(DROPS) do
    local ok, M = pcall(lib.require, d[1])
    local okC, e = false, "no module"
    if ok and M and M[d[2]] then okC, e = pcall(M[d[2]]) end
    local now = live()
    log(("  %-18s %-11s %s  freed %7.1f MB  (live %.1f)"):format(d[1], d[2], okC and "ok " or "ERR", prev - now, now))
    if not okC then log("     ", tostring(e)) end
    prev = now
  end
  log(("total freed by the drops: %.1f MB; left %.1f MB"):format(base - prev, prev))
  pcall(Pipelines.setLevel, "terrarium_voxel", level)
  end)
  if not okAll then log("ERROR", tostring(err)) end
  logf:close()
  love.event.quit()
end
