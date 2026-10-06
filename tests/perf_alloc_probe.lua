-- Probe: WHO ALLOCATES. The Lua heap climbs ~35-40 MB a second in free roam
-- and the collector drops ~300 MB every ten seconds; this attributes the
-- garbage. Every function on every module table is wrapped to add up the
-- heap growth across its own calls (inclusive), with the collector STOPPED
-- for the measured stretch so a collection step cannot land inside a call
-- and read as negative. Also the heap held by each module's big caches.
--   DS_MAP / DS_X / DS_Y / DS_SURF, DS_MODULES (comma list)
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/perf_alloc.log", "w"))
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
  local mapId = os.getenv("DS_MAP") or "ROUTE_1"
  local x, y = tonumber(os.getenv("DS_X") or "9"), tonumber(os.getenv("DS_Y") or "24")
  local surf = (os.getenv("DS_SURF") or "0") == "1"
  ow.player.surfing = surf
  pcall(function() ow:setMap(mapId, x, y, "up") end)
  ow.player.surfing = surf
  local clock = love.timer.getTime
  local t0 = clock()
  while clock() - t0 < 30 do coroutine.yield(); if game.stack:top() ~= ow then pcall(function() game.stack:pop() end) end end

  collectgarbage("collect")
  local live = collectgarbage("count") / 1024
  log(("live heap after a full collect: %.1f MB"):format(live))

  -- the frame's own allocation, nothing wrapped
  local function rate(secs)
    collectgarbage("stop")
    local c0, f, s0 = collectgarbage("count"), 0, clock()
    while clock() - s0 < secs do coroutine.yield(); f = f + 1 end
    local kb = collectgarbage("count") - c0
    collectgarbage("restart")
    return kb / f, f / (clock() - s0)
  end
  local kbpf, fps = rate(3)
  log(("garbage per frame, nothing wrapped: %.0f KB  (%.1f fps -> %.1f MB/s)"):format(kbpf, fps, kbpf * fps / 1024))

  -- wrap
  local acc, calls, on = {}, {}, false
  local names = {}
  for name in (os.getenv("DS_MODULES") or ""):gmatch("[^,]+") do names[#names + 1] = name end
  for _, name in ipairs(names) do
    local ok, M = pcall(lib.require, name)
    if ok and type(M) == "table" then
      for k, f in pairs(M) do
        if type(f) == "function" then
          local tag = name .. "." .. k
          M[k] = function(...)
            if not on then return f(...) end
            local c = collectgarbage("count")
            local a, b, cc, d, e = f(...)
            acc[tag] = (acc[tag] or 0) + (collectgarbage("count") - c)
            calls[tag] = (calls[tag] or 0) + 1
            return a, b, cc, d, e
          end
        end
      end
    end
  end
  collectgarbage("stop")
  on = true
  local f, s0 = 0, clock()
  while clock() - s0 < 3 do coroutine.yield(); f = f + 1 end
  on = false
  collectgarbage("restart")
  local arr = {}
  for k, v in pairs(acc) do arr[#arr + 1] = { k, v / f, calls[k] / f } end
  table.sort(arr, function(a, b) return a[2] > b[2] end)
  log("KB allocated per frame (inclusive)   calls/frame   function")
  for i = 1, math.min(45, #arr) do
    log(("  %9.1f  %8.1f   %s"):format(arr[i][2], arr[i][3], arr[i][1]))
  end
  end)
  if not okAll then log("ERROR", tostring(err)) end
  pcall(collectgarbage, "restart")
  logf:close()
  love.event.quit()
end
