-- Probe: WHERE THE CPU GOES, by instrumentation. jit.profile is not open to
-- mods (the sandbox refuses it), so every function on every module table in
-- lib/ is wrapped with a timer: inclusive ms per frame and calls per frame,
-- for a steady stretch of a spot, as played, encounters off. Nested calls
-- each carry their callees, so read it as a tree: a parent's time includes
-- its children's.
--   DS_MAP / DS_X / DS_Y / DS_SURF / DS_SECS
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/perf_profile.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local okAll, errAll = pcall(function()
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
  local names = {}
  for line in (os.getenv("DS_MODULES") or ""):gmatch("[^,]+") do names[#names + 1] = line end

  local mapId = os.getenv("DS_MAP") or "ROUTE_21"
  local x, y = tonumber(os.getenv("DS_X") or "8"), tonumber(os.getenv("DS_Y") or "14")
  local surf = (os.getenv("DS_SURF") or "1") == "1"
  local SECS = tonumber(os.getenv("DS_SECS") or "15")
  ow.player.surfing = surf
  pcall(function() ow:setMap(mapId, x, y, "down") end)
  ow.player.surfing = surf
  local t0 = love.timer.getTime()
  while love.timer.getTime() - t0 < 40 do
    coroutine.yield()
    if game.stack:top() ~= ow then pcall(function() game.stack:pop() end) end
  end

  -- wrap
  local acc, calls, on = {}, {}, false
  local clock = love.timer.getTime
  local wrapped = 0
  for _, name in ipairs(names) do
    local ok, M = pcall(lib.require, name)
    if ok and type(M) == "table" then
      for k, f in pairs(M) do
        if type(f) == "function" then
          local tag = name .. "." .. k
          M[k] = function(...)
            if not on then return f(...) end
            local s = clock()
            local r = { f(...) }
            acc[tag] = (acc[tag] or 0) + (clock() - s)
            calls[tag] = (calls[tag] or 0) + 1
            return unpack(r, 1, table.maxn(r))
          end
          wrapped = wrapped + 1
        end
      end
    end
  end
  -- and the frame itself, around the world pipeline's own draw
  log("wrapped", wrapped, "functions in", #names, "modules")
  local frames = 0
  on = true
  local tS = clock()
  while clock() - tS < SECS do
    coroutine.yield()
    frames = frames + 1
    if game.stack:top() ~= ow then pcall(function() game.stack:pop() end) end
  end
  on = false
  local secs = clock() - tS
  log(("spot %s %d,%d surf=%s: %d frames in %.1f s = %.1f fps (%.1f ms/frame)"):format(
    mapId, x, y, tostring(surf), frames, secs, frames / secs, secs * 1000 / frames))
  local arr = {}
  for k, v in pairs(acc) do arr[#arr + 1] = { k, v * 1000 / frames, calls[k] / frames } end
  table.sort(arr, function(a, b) return a[2] > b[2] end)
  log("inclusive ms/frame   calls/frame   function")
  for i = 1, math.min(70, #arr) do
    log(("  %8.3f  %10.1f   %s"):format(arr[i][2], arr[i][3], arr[i][1]))
  end
  end)
  if not okAll then log("ERROR", tostring(errAll)) end
  logf:close()
  love.event.quit()
end
