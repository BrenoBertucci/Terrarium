-- Probe: WALKING BETWEEN MAPS, as played. The player walks north from Pallet
-- (a held key, found by asking which one moves north -- the SM64 camera turns
-- the controls) through Route 1 into Viridian, encounters off. Per second:
-- frames, median and worst frame, which map, and the module functions whose
-- single longest call that second was the longest (every function on every
-- module table is wrapped; inclusive time; calls that yield inside the mesher
-- coroutine are excluded by tracking only calls that return in the same
-- frame they started).
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local SECS = tonumber(os.getenv("DS_SECS") or "70")
  local logf = assert(io.open(OUT .. "/perf_walk.log", "w"))
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
  local clock = love.timer.getTime
  local frameNo = 0

  -- every module function: the longest single call this second
  local maxCall, names = {}, {}
  for line in (os.getenv("DS_MODULES") or ""):gmatch("[^,]+") do names[#names + 1] = line end
  for _, name in ipairs(names) do
    local ok, M = pcall(lib.require, name)
    if ok and type(M) == "table" then
      for k, f in pairs(M) do
        if type(f) == "function" then
          local tag = name .. "." .. k
          M[k] = function(...)
            local s, fr = clock(), frameNo
            local r = { f(...) }
            if frameNo == fr then
              local d = clock() - s
              if d > (maxCall[tag] or 0) then maxCall[tag] = d end
            end
            return unpack(r, 1, table.maxn(r))
          end
        end
      end
    end
  end
  local writes, writeT = 0, 0
  do
    local w = game.writeOptions
    game.writeOptions = function(...)
      local t0 = clock(); w(...); writes = writes + 1; writeT = writeT + clock() - t0
    end
  end

  -- start at Pallet's north edge and find the key that walks north
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
    log(("key %s: cellY %d -> %d"):format(k, y0, ow.player.cellY))
    if ow.player.cellY < y0 then north = k break end
  end
  if not north then log("no key walks north"); return end
  pcall(function() ow:setMap("PALLET_TOWN", 10, 6, "up") end)
  t0 = clock()
  while clock() - t0 < 25 do coroutine.yield() end
  log("walking with", north)

  local lastMap = ow.map and ow.map.id
  for s = 1, SECS do
    for k in pairs(maxCall) do maxCall[k] = nil end
    local ft, last = {}, clock()
    local secEnd = last + 1
    local changes = {}
    while clock() < secEnd do
      game.input.state[north] = true
      -- sidestep a wall: if the player has not moved for a while, wiggle
      coroutine.yield()
      frameNo = frameNo + 1
      local now = clock()
      ft[#ft + 1] = (now - last) * 1000
      last = now
      if game.stack:top() ~= ow then pcall(function() game.stack:pop() end) end
      local id = ow.map and ow.map.id
      if id ~= lastMap then changes[#changes + 1] = tostring(id); lastMap = id end
    end
    table.sort(ft)
    local arr = {}
    for k, v in pairs(maxCall) do arr[#arr + 1] = { k, v * 1000 } end
    table.sort(arr, function(a, b) return a[2] > b[2] end)
    local parts = {}
    for i = 1, math.min(4, #arr) do parts[#parts + 1] = ("%s %.0f"):format(arr[i][1], arr[i][2]) end
    log(("t=%2d %-14s %3d fr  med %5.1f  worst %6.1f  %s| %s"):format(s, tostring(lastMap), #ft,
      ft[math.max(1, math.floor(#ft / 2))] or 0, ft[#ft] or 0,
      (#changes > 0) and ("ENTER " .. table.concat(changes, ",") .. " ") or "",
      table.concat(parts, ", ")))
    -- every 6 s, a little sideways so a tree in the way does not hold the walk
    if s % 6 == 0 then
      local side = (s % 12 == 0) and "left" or "right"
      for _ = 1, 8 do game.input.state[side] = true; coroutine.yield() end
      game.input.state[side] = false
    end
  end
  for _, k in ipairs(KEYS) do game.input.state[k] = false end
  log(("options writes during the walk: %d (%.0f ms total)"):format(writes, writeT * 1000))
  end)
  if not okAll then log("ERROR", tostring(err)) end
  logf:close()
  love.event.quit()
end
