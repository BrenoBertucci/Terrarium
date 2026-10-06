-- Probe: walking north from Pallet, as played, WITHOUT wrapping anything --
-- per second: fps, worst frame, Lua heap, texture memory, draw calls, and
-- the live counts of every system that accumulates (motes, litter, rings,
-- strokes, mesher jobs). What grows while the frame rate falls is the leak.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local SECS = tonumber(os.getenv("DS_SECS") or "90")
  local logf = assert(io.open(OUT .. "/perf_walk_mem.log", "w"))
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
  local function req(x) local ok, m = pcall(lib.require, x) return ok and m or nil end
  local WindFX, WindLines, Ripples, CM = req("WindFX"), req("WindLines"), req("Ripples"), req("ChunkMesher")
  local LeafFallFX, GroundFX, StepFX, Weather, AmbientLife = req("LeafFallFX"), req("GroundFX"), req("StepFX"),
    req("Weather"), req("AmbientLife")
  local clock = love.timer.getTime
  local function cnt(M, f)
    if not (M and M[f]) then return -1 end
    local ok, v = pcall(M[f])
    return ok and tonumber(v) or -1
  end
  pcall(function() ow:setMap("PALLET_TOWN", 10, 6, "up") end)
  local t0 = clock()
  while clock() - t0 < 30 do coroutine.yield() end
  local KEYS = { "up", "down", "left", "right" }
  local north
  for _, k in ipairs(KEYS) do
    pcall(function() ow:setMap("PALLET_TOWN", 10, 6, "up") end)
    wait(60)
    local y0 = ow.player.cellY
    for _ = 1, 30 do game.input.state[k] = true; coroutine.yield() end
    for _, kk in ipairs(KEYS) do game.input.state[kk] = false end
    wait(30)
    if ow.player.cellY < y0 then north = k break end
  end
  pcall(function() ow:setMap("PALLET_TOWN", 10, 6, "up") end)
  t0 = clock()
  while clock() - t0 < 20 do coroutine.yield() end
  log("walking with", tostring(north))
  local lastY, stuck = ow.player.cellY, 0
  for s = 1, SECS do
    local ft, last = {}, clock()
    local secEnd = last + 1
    while clock() < secEnd do
      if north then game.input.state[north] = true end
      coroutine.yield()
      local now = clock()
      ft[#ft + 1] = (now - last) * 1000
      last = now
      if game.stack:top() ~= ow then pcall(function() game.stack:pop() end) end
    end
    table.sort(ft)
    local st = love.graphics.getStats()
    log(("t=%2d %-12s cell %2d,%3d %3d fr worst %6.1f | lua %6.1f MB  tex %6.1f MB  draws %4d imgs %4d canv %3d | motes %d lines %d litter %d groundfx %d stepfx %d weather %d amb %d jobs %d ripple %s"):format(
      s, tostring(ow.map and ow.map.id), ow.player.cellX, ow.player.cellY, #ft, ft[#ft] or 0,
      collectgarbage("count") / 1024, (st.texturememory or 0) / 1048576, st.drawcalls or 0,
      st.images or -1, st.canvases or -1,
      cnt(WindFX, "count"), cnt(WindLines, "count"), cnt(LeafFallFX, "count"), cnt(GroundFX, "count"),
      cnt(StepFX, "count"), cnt(Weather, "count"), cnt(AmbientLife, "count"), cnt(CM, "pending"),
      tostring(Ripples and Ripples.live())))
    -- sidestep when stuck
    if ow.player.cellY == lastY then stuck = stuck + 1 else stuck = 0 end
    lastY = ow.player.cellY
    if stuck >= 2 then
      local side = (s % 4 < 2) and "left" or "right"
      for _ = 1, 20 do game.input.state[side] = true; coroutine.yield() end
      game.input.state[side] = false
    end
  end
  for _, k in ipairs(KEYS) do game.input.state[k] = false end
  end)
  if not okAll then log("ERROR", tostring(err)) end
  logf:close()
  love.event.quit()
end
