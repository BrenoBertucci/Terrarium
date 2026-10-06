-- Probe: the frame's garbage by place, in steady state (Pallet). The engine
-- runs a collector step every 4 frames itself, so the collector cannot be
-- held; instead every measured span keeps only the samples where the heap
-- went UP (a span that caught a collector step is dropped), and reports the
-- mean over the samples it kept. VoxelScene.render's sections, and every
-- function on the listed module tables.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/perf_alloc2.log", "w"))
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
  local VS, CM = lib.require("VoxelScene"), lib.require("ChunkMesher")
  pcall(function() ow:setMap(os.getenv("DS_MAP") or "PALLET_TOWN", 4, 13, "down") end)
  local clock = love.timer.getTime
  local t0 = clock()
  while clock() - t0 < 40 do coroutine.yield(); if game.stack:top() ~= ow then pcall(function() game.stack:pop() end) end end
  log("mesher jobs pending:", CM.pending())
  local acc, kept, calls, on = {}, {}, {}, false
  for name in (os.getenv("DS_MODULES") or ""):gmatch("[^,]+") do
    local ok, M = pcall(lib.require, name)
    if ok and type(M) == "table" then
      for k, f in pairs(M) do
        if type(f) == "function" then
          local tag = name .. "." .. k
          M[k] = function(...)
            if not on then return f(...) end
            local c = collectgarbage("count")
            local a, b, cc, d, e = f(...)
            local dd = collectgarbage("count") - c
            calls[tag] = (calls[tag] or 0) + 1
            if dd >= 0 then acc[tag] = (acc[tag] or 0) + dd; kept[tag] = (kept[tag] or 0) + 1 end
            return a, b, cc, d, e
          end
        end
      end
    end
  end
  -- the whole frame, same rule
  local frameKB, frameKept = 0, 0
  VS.PROFILE = { _mem = true }
  on = true
  local f, s0 = 0, clock()
  local last = collectgarbage("count")
  while clock() - s0 < 4 do
    coroutine.yield(); f = f + 1
    local now = collectgarbage("count")
    if now >= last then frameKB = frameKB + (now - last); frameKept = frameKept + 1 end
    last = now
  end
  on = false
  local P = VS.PROFILE
  VS.PROFILE = nil
  log(("whole frame: %.0f KB per frame (mean of %d of %d frames that caught no collector step)"):format(
    frameKB / math.max(1, frameKept), frameKept, f))
  local arr = {}
  for k, v in pairs(P) do
    if k:sub(1, 1) ~= "#" and k ~= "_t" and k ~= "_mem" then
      local kk = P["#" .. k] or 1
      arr[#arr + 1] = { k, v / kk, kk }
    end
  end
  table.sort(arr, function(a, b) return a[2] > b[2] end)
  for _, a in ipairs(arr) do log(("   render.%-14s %7.1f KB per frame (%d samples)"):format(a[1], a[2], a[3])) end
  local fa = {}
  for k, v in pairs(acc) do fa[#fa + 1] = { k, v / math.max(1, kept[k]) * (calls[k] / f), calls[k] / f } end
  table.sort(fa, function(a, b) return a[2] > b[2] end)
  log("functions, KB per frame (mean per call x calls per frame):")
  for i = 1, math.min(40, #fa) do log(("  %8.1f KB  %8.1f calls  %s"):format(fa[i][2], fa[i][3], fa[i][1])) end
  end)
  if not okAll then log("ERROR", tostring(err)) end
  logf:close()
  love.event.quit()
end
