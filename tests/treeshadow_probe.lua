-- What does the sun's depth pass actually pay for?
--
-- Trees3D.SHADOW_PROXY casts from a measured hull (a six-sided barrel whose
-- ring radii come off the bake's own crown, plus a prism for the bole)
-- instead of from the tree's ~700 solid triangles. The claim is that eleven
-- milliseconds a frame were being spent on detail that cannot survive into a
-- soft grey patch on the grass.
--
-- That is an argument. This is the measurement, and it has to be an A/B
-- rather than a before-and-after, because the absolute numbers on this
-- machine move several milliseconds between runs -- only the deltas WITHIN
-- one run mean anything (see the note on SHADOW_SOLID_ONLY in Trees3D, where
-- believing a cross-run delta cost an hour).
--
-- It ends in two pictures of the same trees at the same hour, because a
-- shadow pass that got cheaper by casting nothing at all would post a
-- magnificent number here.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/treeshadow.log", "w"))
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
  local Voxel3D = lib.require("Voxel3D")
  local Trees3D = lib.require("Trees3D")
  local DayNight = lib.require("DayNight")

  -- Not forceSync: that drags DAYTIME back to SYNC, which is the wall clock.
  pcall(function() DayNight.setting:sync("day") end)
  wait(20)

  local names = Trees3D.loaded()
  log("species: " .. table.concat(names, ", "))
  local fullTris, proxyTris, fullVerts, proxyVerts = 0, 0, 0, 0
  for _, nm in ipairs(names) do
    local t = Trees3D.templates[nm]
    if t then
      local ft, pt = #t.solidIndices / 3, (t.shadowIndices and #t.shadowIndices / 3) or 0
      local fv, pv = #t.verts, (t.shadowVerts and #t.shadowVerts) or 0
      fullTris = fullTris + ft; proxyTris = proxyTris + pt
      fullVerts = fullVerts + fv; proxyVerts = proxyVerts + pv
      log(string.format("  %-12s caster: solid %d tris / %d verts -> proxy "
                        .. "%d tris / %d verts", nm, ft, fv, pt, pv))
      if pt == 0 then
        log("  FAIL: " .. nm .. " built no proxy -- it will fall back to the "
            .. "solid mesh and this run measures nothing for it")
      end
    end
  end
  log(string.format("caster totals: %d -> %d tris (%.1fx), %d -> %d verts (%.1fx)",
                    fullTris, proxyTris, fullTris / math.max(proxyTris, 1),
                    fullVerts, proxyVerts, fullVerts / math.max(proxyVerts, 1)))

  local function meshQueue()
    local ok, q = pcall(function()
      local CM = lib.require("ChunkMesher")
      return CM.pending and CM.pending() or 0
    end)
    return (ok and tonumber(q)) or 0
  end

  local function settle(label, maxTicks)
    maxTicks = maxTicks or 6000
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
    while (owed > 0 or queued > 0) and waited < 1200 do
      coroutine.yield(); ticks, waited = ticks + 1, waited + 1
      owed, queued = select(2, Trees3D.buildsInFlight()), meshQueue()
    end
    log(string.format("settled %s in %d ticks (owed=%d queued=%d)%s",
                      label, ticks, owed, queued,
                      (owed > 0 or queued > 0)
                        and "  -- NOT CLEAN, the sample below is suspect" or ""))
  end

  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(d)
      local f = io.open(OUT .. "/" .. name .. ".png", "wb")
      if f then f:write(d:encode("png"):getString()); f:close() end
      done = true
    end)
    local g = 0
    while not done and g < 240 do coroutine.yield(); g = g + 1 end
  end

  -- Count only the map underfoot: VoxelScene draws every neighbour too, and
  -- a count of all of them is useless as the frame counter this doubles as.
  local realDraw = Trees3D.draw
  local draws = 0
  Trees3D.draw = function(map, ...)
    if map and game.overworld and game.overworld.map == map then
      draws = draws + 1
    end
    return realDraw(map, ...)
  end

  local SAMPLES, FRAMES, SETTLE_T = 3, 100, 40
  local function medianCost()
    local perTick, perFrame = {}, {}
    for i = 1, SAMPLES do
      wait(SETTLE_T)
      local d0, t0 = draws, love.timer.getTime()
      for _ = 1, FRAMES do coroutine.yield() end
      local el = love.timer.getTime() - t0
      perTick[i] = el / FRAMES * 1000
      perFrame[i] = el / math.max(draws - d0, 1) * 1000
    end
    table.sort(perTick); table.sort(perFrame)
    local mid = math.ceil(SAMPLES / 2)
    local spread = (perTick[SAMPLES] / math.max(perTick[1], 1e-9) - 1) * 100
    return perTick[mid], perFrame[mid], spread, perTick[1], perTick[SAMPLES]
  end

  local function run(label)
    local ms, msF, spread, lo, hi = medianCost()
    log(string.format("  %-22s %6.2f ms/tick  %7.2f ms/frame  "
                      .. "(min %6.2f, max %6.2f, spread %3.0f%%)",
                      label, ms, msF, lo, hi, spread))
    return msF, spread
  end

  local function rebuild(label)
    pcall(function() Trees3D.invalidate() end)
    pcall(function() game.overworld:setMap("VIRIDIAN_CITY", 10, 10, "up") end)
    wait(30)
    pcall(function() game.overworld:setMap("ROUTE_2", 10, 10, "up") end)
    settle(label)
  end

  -- ---- A, then B, then A again. The repeat is the drift check: if the two
  -- readings of the same state differ by more than the effect, the effect
  -- was not measured.
  log("ROUTE_2, " .. SAMPLES .. " samples of " .. FRAMES .. " frames each:")

  Trees3D.SHADOW_PROXY = true
  rebuild("ROUTE_2 proxy")
  local proxyMs, proxySpread = run("hull caster")

  Trees3D.SHADOW_PROXY = false
  rebuild("ROUTE_2 full caster")
  local fullMs, fullSpread = run("full solid caster")
  shot("treeshadow_full")

  Trees3D.SHADOW_PROXY = true
  rebuild("ROUTE_2 proxy again")
  local proxyMs2 = run("hull caster (repeat)")
  shot("treeshadow_proxy")

  local delta = fullMs - proxyMs
  local drift = math.abs(proxyMs2 - proxyMs)
  log(string.format("SUN PASS: hull caster saves %+.2f ms/frame against a "
                    .. "drift of %.2f ms", delta, drift))

  if math.max(proxySpread, fullSpread) > 15 then
    log(string.format("REFUSED: spreads were %.0f%% and %.0f%%. A delta from a "
                      .. "run whose spread is wider than the effect is not a "
                      .. "small measurement, it is not a measurement.",
                      proxySpread, fullSpread))
  elseif drift >= math.abs(delta) then
    log("REFUSED: the drift between two readings of the SAME state is as big "
        .. "as the difference between the two states. Nothing was measured.")
  elseif delta > 0 then
    log(string.format("PASS: the hull caster is cheaper by %.2f ms/frame "
                      .. "(%.0f%% of the whole frame). Compare "
                      .. "treeshadow_proxy.png against treeshadow_full.png "
                      .. "before believing it -- a caster that vanished "
                      .. "would post a better number than this.", delta,
                      delta / math.max(fullMs, 1e-6) * 100))
  else
    log(string.format("FAIL: the hull caster is NOT cheaper (%+.2f ms). The "
                      .. "detail was not what the pass was paying for; put "
                      .. "SHADOW_PROXY back to false.", delta))
  end

  log("done")
  logf:close()
  love.event.quit()
end
