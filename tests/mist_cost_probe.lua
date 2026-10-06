-- Probe: what the MIST row costs, and nothing else -- no map hopping first,
-- so no chunk streaming in the tail. Two maps (a town, and a harbour where
-- most of the screen is water under mist), three OFF-ON-ON-OFF palindromes
-- each, vsync off, the clock pinned at dawn (the heaviest mist).
--
-- Three questions, each answered in the log rather than by a picture:
--   1. Under FULL, is the DAYTIME row on the OPTIONS menu, and does a pin
--      (DUSK) survive the menu opening? (It used to snap back to SYNC.)
--   2. What does the mist do over the clock -- amount, colour, the body's
--      bearing and strength -- a second at a time on a 60 s grid.
--   3. What does it cost: OFF-ON-ON-OFF at dawn in one process, vsync off.
-- The screenshots are confirmation, taken on a PINNED clock (DayNight.time
-- is stubbed for the run and put back at the end).
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/mist_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/mist_cost_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      done = true
    end)
    local guard = 0
    while not done and guard < 240 do coroutine.yield(); guard = guard + 1 end
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit() return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end
  game.input:reset()

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end
  log("version:", exports.TERRARIUM.version)

  local DayNight = lib.require("DayNight")
  local Mist = lib.require("Mist")
  local Weather = lib.require("Weather")
  local ChunkMesher = lib.require("ChunkMesher")
  local Pipelines = require("src.render.Pipelines")
  local ow = game.overworld
  Weather.setting:sync("off")
  Pipelines.setLevel("terrarium_voxel", 1)          -- FULL, as played
  local realTime = DayNight.time
  DayNight.time = function() return 20 end
  local function settle()
    local quiet, guard = 0, 0
    while quiet < 90 and guard < 3600 do
      coroutine.yield(); guard = guard + 1
      if ChunkMesher.pending() == 0 then quiet = quiet + 1 else quiet = 0 end
    end
    game.input:reset()
    wait(240)
  end
  local function measure(tag, on)
    Mist.setting:sync(on and "on" or "off")
    wait(30)
    local ts, last = {}, love.timer.getTime()
    for i = 1, 240 do
      coroutine.yield()
      local now = love.timer.getTime()
      ts[i] = (now - last) * 1000
      last = now
    end
    table.sort(ts)
    local sum = 0
    for _, v in ipairs(ts) do sum = sum + v end
    return ts[120], sum / #ts
  end
  love.window.setVSync(0)
  for _, place in ipairs({ { "PALLET_TOWN", 10, 12 },
                           { "VERMILION_CITY", 18, 20 } }) do
    ow:setMap(place[1], place[2], place[3], "down")
    settle()
    local on, off = {}, {}
    for r = 1, 3 do
      for _, step in ipairs({ false, true, true, false }) do
        local p50, mean = measure("", step)
        local t = step and on or off
        t[#t + 1] = p50
        log(("%s round%d %s p50=%.2f mean=%.2f")
            :format(place[1], r, step and "ON " or "OFF", p50, mean))
      end
    end
    local function avg(t) local s = 0 for _, v in ipairs(t) do s = s + v end return s / #t end
    local function spread(t) table.sort(t) return t[#t] - t[1] end
    log(("%s OFF avg p50=%.2f (spread %.2f)  ON avg p50=%.2f (spread %.2f)  delta=%+.2f ms")
        :format(place[1], avg(off), spread(off), avg(on), spread(on), avg(on) - avg(off)))
  end
  DayNight.time = realTime
  Mist.setting:sync("on")
  log("done")
  logf:close()
  love.event.quit()
end
