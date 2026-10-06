-- Probe: VoxelScene.render's own sections (VoxelScene.PROFILE), plus the
-- mesher pump, per frame, at a few spots, as played, encounters off, after
-- the spot has settled. What is not in "render" or "pump" is the rest of the
-- frame: the engine, the mod's update ticks, and the GPU wait at present.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/perf_sections.log", "w"))
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
  pcall(love.window.setVSync, 0)
  local lib = game.mods.exports.TERRARIUM.lib
  local VoxelScene, CM = lib.require("VoxelScene"), lib.require("ChunkMesher")
  local clock = love.timer.getTime
  local pumpT, renderT = 0, 0
  do
    local inner = CM.pump
    CM.pump = function(...) local t0 = clock(); inner(...); pumpT = pumpT + clock() - t0 end
    local r = VoxelScene.render
    VoxelScene.render = function(...) local t0 = clock(); local c = r(...); renderT = renderT + clock() - t0; return c end
  end
  local SETTLE = tonumber(os.getenv("DS_SETTLE") or "40")
  local function spot(tag, mapId, x, y, surf)
    ow.player.surfing = surf
    pcall(function() ow:setMap(mapId, x, y, "down") end)
    ow.player.surfing = surf
    local t0 = clock()
    while clock() - t0 < SETTLE do
      coroutine.yield()
      if game.stack:top() ~= ow then pcall(function() game.stack:pop() end) end
    end
    VoxelScene.PROFILE = {}
    pumpT, renderT = 0, 0
    local frames, ft = 0, {}
    local last = clock()
    local tS = last
    while clock() - tS < 10 do
      coroutine.yield()
      local now = clock()
      frames = frames + 1
      ft[frames] = (now - last) * 1000
      last = now
      if game.stack:top() ~= ow then pcall(function() game.stack:pop() end) end
    end
    local P = VoxelScene.PROFILE
    VoxelScene.PROFILE = nil
    table.sort(ft)
    local total = (clock() - tS) * 1000 / frames
    log(("[%s] %.1f fps, frame %.1f ms (median %.1f, p95 %.1f); render %.1f, pump %.1f, rest %.1f ms; mesher jobs %d"):format(
      tag, 1000 / total, total, ft[math.floor(frames / 2)], ft[math.floor(frames * 0.95)],
      renderT * 1000 / frames, pumpT * 1000 / frames, total - (renderT + pumpT) * 1000 / frames, CM.pending()))
    local arr = {}
    for k, v in pairs(P) do if k ~= "_t" then arr[#arr + 1] = { k, v * 1000 / frames } end end
    table.sort(arr, function(a, b) return a[2] > b[2] end)
    local parts = {}
    for _, a in ipairs(arr) do parts[#parts + 1] = ("%s %.2f"):format(a[1], a[2]) end
    log("   render sections ms/frame: " .. table.concat(parts, ", "))
  end
  spot("route21-surf", "ROUTE_21", 8, 14, true)
  spot("pallet", "PALLET_TOWN", 4, 13, false)
  spot("route1", "ROUTE_1", 9, 24, false)
  end)
  if not okAll then log("ERROR", tostring(err)) end
  logf:close()
  love.event.quit()
end
