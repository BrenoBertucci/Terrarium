-- What the forest actually looks like, and whether the canopy moves.
--
-- Runs before and after a re-bake so the two can be diffed. It reports the
-- template the bake produced (tris, verts, the canopy-weight field) and then
-- ends in pictures, because every count here can be right while the forest
-- on screen is still the hulls -- see trees_probe.lua's three ways to pass
-- and be wrong.
--
-- The sway number is a pixel difference between two frames GAP apart, and it
-- has three known traps (see the canopy-wind note): it saturates at a large
-- GAP, it INVERTS at large amplitude because the crowns blur into each
-- other, and the camera drifts on its own. So: GAP is small, every sample is
-- fenced by the player's cell, and the A/B is run DOWNWARD (half share, then
-- off) rather than upward.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local TAG = os.getenv("DS_PROBE_TAG") or "vox"
  local logf = assert(io.open(OUT .. "/treevox_" .. TAG .. ".log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring((select(i, ...))) end
    logf:write(table.concat(p, " ") .. "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b
    coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: never booted"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end

  local lib = game.mods.exports.TERRARIUM.lib
  local Voxel3D  = lib.require("Voxel3D")
  local Trees3D  = lib.require("Trees3D")
  local Wind     = lib.require("Wind")

  -- ---- WHAT THE BAKE ACTUALLY IS
  local names = Trees3D.loaded()
  log("species loaded: " .. #names .. " [" .. table.concat(names, ", ") .. "]")
  log("available()=" .. tostring(Trees3D.available())
      .. " MAX_TRIS=" .. tostring(Trees3D.MAX_TRIS)
      .. " WIND_SHARE=" .. tostring(Trees3D.WIND_SHARE))
  for _, nm in ipairs(names) do
    local t = Trees3D.templates[nm]
    if t then
      local wmin, wmax, wsum = 1e9, -1e9, 0
      for i = 1, #t.weights do
        local w = t.weights[i]
        if w < wmin then wmin = w end
        if w > wmax then wmax = w end
        wsum = wsum + w
      end
      log(string.format("  %s: verts=%d tris=%d solidTris=%d h=%.2f r=%.2f "
                        .. "canopyY=%.2f canopyR=%.2f | weight min=%.3f "
                        .. "max=%.3f mean=%.3f",
                        nm, #t.verts, #t.indices / 3, #t.solidIndices / 3,
                        t.height, t.radius, t.canopyY, t.canopyR,
                        wmin, wmax, wsum / math.max(1, #t.weights)))
    end
  end

  local function meshQueue()
    local ok, q = pcall(function()
      local CM = lib.require("ChunkMesher")
      return CM.pending and CM.pending() or 0
    end)
    return (ok and tonumber(q)) or 0
  end

  local function settle(label, maxTicks)
    maxTicks = maxTicks or 4000
    local ticks, live = 0, false
    while true do
      if Voxel3D.lampLights ~= nil then live = true end
      local map = game.overworld and game.overworld.map
      local done, state = Trees3D.ready(map)
      if live and (done or state == "hulls") then break end
      if ticks >= maxTicks then
        log("FAIL: settle " .. label .. " never came up after " .. ticks); break
      end
      coroutine.yield(); ticks = ticks + 1
    end
    local owed, queued = select(2, Trees3D.buildsInFlight()), meshQueue()
    local waited = 0
    while (owed > 0 or queued > 0) and waited < 900 do
      coroutine.yield(); ticks, waited = ticks + 1, waited + 1
      owed, queued = select(2, Trees3D.buildsInFlight()), meshQueue()
    end
    log(string.format("settled %s in %d ticks (owed=%d queued=%d)",
                      label, ticks, owed, queued))
  end

  -- Shots wait on the CALLBACK, not on a frame count -- a scheduled capture
  -- plus N yields photographs the state AFTER the one being asked for.
  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(d)
      local f = io.open(OUT .. "/" .. name .. ".png", "wb")
      if f then f:write(d:encode("png"):getString()); f:close() end
      done = true
    end)
    local guard = 0
    while not done and guard < 240 do coroutine.yield(); guard = guard + 1 end
    if not done then log("WARN: shot " .. name .. " never landed") end
  end

  -- ---- SWAY, MEASURED
  --
  -- PAIRED, NOT SEQUENTIAL, and the first run is why. Reading the three
  -- shares one after another gave 0.83 / 18.98 / 40.87 -- monotonically
  -- rising in the order they were taken, with the LEAST wind scoring the
  -- most. Nothing about the forest explains that shape; the rest of the
  -- scene explains all of it. Clouds thicken, the hour turns, the ambient
  -- life wanders, and any of those moves more pixels between two frames
  -- than a canopy does. A block of samples an hour of game-time apart is
  -- comparing weather, not wind.
  --
  -- So each round measures OFF and ON within a handful of frames of each
  -- other and keeps the difference. Whatever the sky is doing, it is doing
  -- the same thing to both halves of a pair.
  local GAP, ROUNDS = 3, 6

  local function frameDiff()
    local px, py = 0, 0
    pcall(function()
      px, py = game.overworld.player.cellX, game.overworld.player.cellY
    end)
    local a, b, got = nil, nil, 0
    love.graphics.captureScreenshot(function(d) a = d; got = got + 1 end)
    local g = 0
    while got < 1 and g < 240 do coroutine.yield(); g = g + 1 end
    wait(GAP)
    love.graphics.captureScreenshot(function(d) b = d; got = got + 1 end)
    g = 0
    while got < 2 and g < 240 do coroutine.yield(); g = g + 1 end
    local qx, qy = 0, 0
    pcall(function()
      qx, qy = game.overworld.player.cellX, game.overworld.player.cellY
    end)
    -- The camera walks on its own after setMap. A sample it moved through
    -- is not a quiet sample, it is a pan.
    if not (a and b) or px ~= qx or py ~= qy then return nil end
    local w, h = a:getDimensions()
    local acc, cnt = 0, 0
    for y = math.floor(h * 0.15), math.floor(h * 0.60), 3 do
      for x = 0, w - 1, 3 do
        local r1, g1, b1 = a:getPixel(x, y)
        local r2, g2, b2 = b:getPixel(x, y)
        acc = acc + math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2)
        cnt = cnt + 1
      end
    end
    return (acc / math.max(1, cnt)) * 255
  end

  local function median(t)
    table.sort(t)
    if #t == 0 then return -1 end
    return t[math.ceil(#t / 2)]
  end

  local function pairedSway(share)
    local keep = Trees3D.WIND_SHARE
    local on, off, delta = {}, {}, {}
    for _ = 1, ROUNDS do
      Trees3D.WIND_SHARE = 0
      wait(6)
      local a = frameDiff()
      Trees3D.WIND_SHARE = share
      wait(6)
      local b = frameDiff()
      if a and b then
        off[#off + 1] = a
        on[#on + 1] = b
        delta[#delta + 1] = b - a
      end
    end
    Trees3D.WIND_SHARE = keep
    local mOn, mOff, mD = median(on), median(off), median(delta)
    local won = 0
    for _, d in ipairs(delta) do if d > 0 then won = won + 1 end end
    log(string.format("sway share=%.2f: on=%.3f off=%.3f delta=%.3f "
                      .. "| %d/%d rounds moved more with wind",
                      share, mOn, mOff, mD, won, #delta))
    return mD, won, #delta
  end

  -- ---- LOOK
  --
  -- PIN THE HOUR FIRST. The clock runs while a probe settles a forest, and
  -- settling ROUTE_2 takes a thousand ticks -- long enough to walk the shot
  -- into night. The first run's pictures came out deep blue, which is not a
  -- judgement of a canopy, it is a judgement of a night filter.
  -- NOT forceSync. That function's job is the opposite of this one's: it
  -- drags DAYTIME back to SYNC so the diorama preset can own the sky, and
  -- calling it after the pin undid the pin on the same frame. Under SYNC the
  -- hour is the WALL CLOCK, so a probe run after midnight photographs a
  -- forest at midnight and the pictures say nothing about a canopy.
  local DayNight = lib.require("DayNight")
  pcall(function() DayNight.setting:sync("day") end)
  wait(30)
  log(string.format("clock pinned: mode=%s t=%.0f (T.day=%.0f)",
                    tostring(DayNight.setting:get()),
                    tonumber(DayNight.time()) or -1, DayNight.T.day))

  pcall(function() game.overworld:setMap("VIRIDIAN_CITY", 10, 10, "up") end)
  settle("VIRIDIAN_CITY")
  wait(20)
  shot("treevox_" .. TAG .. "_viridian")

  pcall(function() game.overworld:setMap("ROUTE_2", 10, 10, "up") end)
  settle("ROUTE_2")
  wait(20)
  shot("treevox_" .. TAG .. "_route2")

  -- ---- DOES IT MOVE
  pcall(function() Wind.setting:sync("gale") end)
  wait(400)                      -- Wind.amount is smoothed; it takes seconds
  shot("treevox_" .. TAG .. "_wind")

  local keep = Trees3D.WIND_SHARE
  -- HALF, not double. At full amplitude neighbouring crowns overlap each
  -- other between frames and the pixel difference FALLS -- the measurement
  -- inverts exactly where the feature is working hardest. Testing downward
  -- stays inside the range where more motion means a bigger number.
  local dFull, wFull, nFull = pairedSway(keep)
  local dHalf, wHalf, nHalf = pairedSway(keep * 0.5)

  if nFull >= 4 and wFull >= math.ceil(nFull * 0.75) and dFull > 0
     and dHalf > 0 and dFull > dHalf then
    log(string.format("PASS: the canopy moves and the amount tracks the wind "
                      .. "-- delta full %.3f > half %.3f, %d/%d rounds agree",
                      dFull, dHalf, wFull, nFull))
  elseif nFull >= 4 and wFull >= math.ceil(nFull * 0.75) and dFull > 0 then
    log(string.format("PASS(weak): the canopy moves (delta %.3f, %d/%d rounds) "
                      .. "but half-share read %.3f, so amplitude did not "
                      .. "separate", dFull, wFull, nFull, dHalf))
  else
    log(string.format("FAIL: canopy sway not separable -- full %.3f (%d/%d) "
                      .. "half %.3f (%d/%d)", dFull, wFull, nFull,
                      dHalf, wHalf, nHalf))
  end

  log("done")
  logf:close()
  love.event.quit()
end
