-- Probe: a per-second TIMELINE of one spot, as played, to see what a slow
-- second is made of: frames, worst frame, mesher queue and pump time, field
-- sizes, invalidations. Encounters off; nothing else touched.
--   DS_MAP / DS_X / DS_Y / DS_SURF pick the spot (default Route 21 surfing).
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local SECS = tonumber(os.getenv("DS_SECS") or "60")
  local logf = assert(io.open(OUT .. "/perf_timeline.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b) game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield() end
  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do wait(1); n = n + 1; if n > 900 then break end end
  n = 0
  while game.stack:top() ~= game.overworld do tap("a"); wait(10); n = n + 11; if n > 1500 then break end end
  local ow = game.overworld
  ow.rollEncounter = function() return nil end
  local lib = game.mods.exports.TERRARIUM.lib
  local CM, WindFX, WindLines, Ripples, VoxelScene = lib.require("ChunkMesher"), lib.require("WindFX"),
    lib.require("WindLines"), lib.require("Ripples"), lib.require("VoxelScene")
  local Wind = lib.require("Wind")
  pcall(love.window.setVSync, 0)

  local pumpT, pumpMax, renderT, invals, jobsDone = 0, 0, 0, 0, 0
  do
    local inner = CM.pump
    CM.pump = function(...)
      local t0 = love.timer.getTime(); inner(...); local d = love.timer.getTime() - t0
      pumpT = pumpT + d; if d > pumpMax then pumpMax = d end
    end
    local inv = CM.invalidate
    CM.invalidate = function(id, ...)
      invals = invals + 1
      log(("  invalidate(%s) at %.1f s"):format(tostring(id), love.timer.getTime()))
      return inv(id, ...)
    end
    local r = VoxelScene.render
    VoxelScene.render = function(...)
      local t0 = love.timer.getTime(); local c = r(...)
      renderT = renderT + (love.timer.getTime() - t0)
      return c
    end
  end

  local mapId = os.getenv("DS_MAP") or "ROUTE_21"
  local x, y = tonumber(os.getenv("DS_X") or "8"), tonumber(os.getenv("DS_Y") or "14")
  local surf = (os.getenv("DS_SURF") or "1") == "1"
  ow.player.surfing = surf
  pcall(function() ow:setMap(mapId, x, y, "down") end)
  ow.player.surfing = surf
  local t0 = love.timer.getTime()
  log(("spot %s %d,%d surf=%s; per second: frames, median/worst ms, pump total/worst ms, render ms, jobs pending, leaves+, lines, ripple, wind"):format(
    mapId, x, y, tostring(surf)))
  for s = 1, SECS do
    local ft, last = {}, love.timer.getTime()
    pumpT, pumpMax, renderT = 0, 0, 0
    local secEnd = last + 1
    while love.timer.getTime() < secEnd do
      coroutine.yield()
      local now = love.timer.getTime()
      ft[#ft + 1] = (now - last) * 1000
      last = now
      if game.stack:top() ~= ow then log("  stack changed; popping"); pcall(function() game.stack:pop() end) end
    end
    table.sort(ft)
    log(("t=%3d  %3d fr  med %6.1f  worst %6.1f | pump %6.1f / %5.1f | render %6.1f | jobs %d | motes %d lines %d ripple %s wind %.2f"):format(
      s, #ft, ft[math.max(1, math.floor(#ft / 2))] or 0, ft[#ft] or 0, pumpT * 1000, pumpMax * 1000,
      renderT * 1000, CM.pending(), WindFX.count(), WindLines.count(), tostring(Ripples.live()),
      tonumber(Wind.amount()) or -1))
  end
  log("invalidations:", invals)
  logf:close()
  love.event.quit()
end
