-- How the forest MOVES, as a burst of consecutive frames.
--
-- A single "wind" screenshot cannot say whether the motion reads as wind
-- or as a machine; the sway score in treevox_probe.lua says only that
-- pixels changed. This probe photographs FRAMES consecutive presents on
-- ROUTE_2 under the default wind, then again under a gale, and writes each
-- as a PNG so tools/motion_sheet.py can lay them out as a strip, a GIF and
-- a per-frame difference curve. The curve is the honest read: a constant
-- flutter is a flat line, intermittent leaves are a ragged one.
--
-- Every shot waits on its capture CALLBACK, never on a yield count -- a
-- capture scheduled and abandoned photographs the state after the one
-- asked for (see the screenshot-race note in the memory).
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local FRAMES = tonumber(os.getenv("DS_FRAMES") or "") or 40
  local logf = assert(io.open(OUT .. "/motion.log", "w"))
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
  local DayNight = lib.require("DayNight")
  pcall(function() DayNight.setting:sync("day") end)

  log("shader=" .. tostring(Voxel3D.shader() ~= nil)
      .. " err=" .. tostring(Voxel3D.shaderError)
      .. " species=" .. table.concat(Trees3D.loaded(), ","))

  local function settle(label, maxTicks)
    local ticks, live = 0, false
    while true do
      if Voxel3D.lampLights ~= nil then live = true end
      local done, state = Trees3D.ready(game.overworld and game.overworld.map)
      if live and (done or state == "hulls") then break end
      if ticks >= (maxTicks or 4000) then log("FAIL: settle " .. label); break end
      coroutine.yield(); ticks = ticks + 1
    end
    local owed = select(2, Trees3D.buildsInFlight())
    local waited = 0
    while owed > 0 and waited < 900 do
      coroutine.yield(); waited = waited + 1
      owed = select(2, Trees3D.buildsInFlight())
    end
    log(string.format("settled %s in %d ticks", label, ticks + waited))
  end

  -- The player walks on their own for ~300 frames after setMap (see the
  -- underpass note in the memory), so a burst is only valid once they have
  -- HELD a cell for a while -- a count of ticks lands mid-stride.
  local function holdStill(label)
    local held, lx, ly, ticks = 0, nil, nil, 0
    while held < 45 and ticks < 2400 do
      local x, y = game.overworld.player.cellX, game.overworld.player.cellY
      if x == lx and y == ly then held = held + 1 else held = 0 end
      lx, ly = x, y
      coroutine.yield(); ticks = ticks + 1
    end
    log(string.format("%s: player held cell %s,%s for %d ticks after %d",
                      label, tostring(lx), tostring(ly), held, ticks))
  end

  local function burstOnce(tag)
    local px, py = game.overworld.player.cellX, game.overworld.player.cellY
    for i = 1, FRAMES do
      local done = false
      love.graphics.captureScreenshot(function(d)
        local f = io.open(string.format("%s/%s_%02d.png", OUT, tag, i), "wb")
        if f then f:write(d:encode("png"):getString()); f:close() end
        done = true
      end)
      local guard = 0
      while not done and guard < 240 do coroutine.yield(); guard = guard + 1 end
    end
    local qx, qy = game.overworld.player.cellX, game.overworld.player.cellY
    local still = (px == qx and py == qy)
    log(string.format("burst %s: %d frames, player %d,%d -> %d,%d%s, wind amount=%.2f gust=%.2f",
                      tag, FRAMES, px, py, qx, qy,
                      still and "" or " (MOVED -- retry)",
                      Wind.amount(), Wind.gust()))
    return still
  end

  local function burst(tag)
    for attempt = 1, 3 do
      holdStill(tag .. " attempt " .. attempt)
      if burstOnce(tag) then return true end
    end
    log("FAIL: " .. tag .. " never held still")
    return false
  end

  pcall(function() game.overworld:setMap("ROUTE_2", 10, 10, "up") end)
  settle("ROUTE_2")
  wait(300)                      -- let the wind's smoothing land
  burst("calm")
  -- the WIND row is numeric: 1 AUTO, 2 BREEZE, 4 GALE, 0 OFF
  pcall(function() Wind.setting:sync(4) end)
  wait(400)
  burst("gale")
  log("done")
  logf:close()
  love.event.quit()
end
