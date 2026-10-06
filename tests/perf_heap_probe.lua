-- Probe: does the LIVE heap grow with every map visited? Teleports along a
-- chain of outdoor maps and back to the start; after each, waits for the 3D
-- and the builds, runs a full collection, and logs the live heap, texture
-- memory, and the size of the module caches it can see. A heap that keeps
-- climbing on the way BACK is a leak, not a working set.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/perf_heap.log", "w"))
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
  local CM = lib.require("ChunkMesher")
  local clock = love.timer.getTime
  if os.getenv("DS_NO3D") then
    pcall(require("src.render.Pipelines").setLevel, "terrarium_voxel", 0)
    log("3D OFF for this run")
  end
  local CHAIN = { "PALLET_TOWN", "ROUTE_1", "VIRIDIAN_CITY", "ROUTE_2", "PEWTER_CITY", "ROUTE_3",
                  "ROUTE_22", "VIRIDIAN_CITY", "ROUTE_1", "PALLET_TOWN" }
  for i, id in ipairs(CHAIN) do
    pcall(function() ow:setMap(id, 8, 8, "down") end)
    local t0 = clock()
    while clock() - t0 < (tonumber(os.getenv("DS_WAIT") or "25")) do
      coroutine.yield()
      if game.stack:top() ~= ow then pcall(function() game.stack:pop() end) end
    end
    local before = collectgarbage("count") / 1024
    collectgarbage("collect"); collectgarbage("collect")
    local liveMB = collectgarbage("count") / 1024
    local st = love.graphics.getStats()
    log(("%2d %-16s live %6.1f MB (was %6.1f before collect) | tex %6.1f MB  images %d  canvases %d | jobs %d"):format(
      i, id, liveMB, before, (st.texturememory or 0) / 1048576, st.images or -1, st.canvases or -1, CM.pending()))
  end
  end)
  if not okAll then log("ERROR", tostring(err)) end
  logf:close()
  love.event.quit()
end
