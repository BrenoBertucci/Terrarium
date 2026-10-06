-- Probe: does the terrain atlas get re-baked as the hour runs? Stands on
-- Route 1 (daytime as the save has it -- SYNC follows the wall clock) and
-- every 5 s logs how many atlases are held, how many bakes and animated
-- copies were built since the last line, the last palette key baked, and
-- the frame rate. Then pins DAY and does the same, for contrast.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/perf_atlas.log", "w"))
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
  local TA, DayNight = lib.require("TerrainAtlas"), lib.require("DayNight")
  local clock = love.timer.getTime
  log("daytime row:", tostring(DayNight.setting:get()), "time:", tostring(DayNight.time and DayNight.time()))
  pcall(function() ow:setMap("ROUTE_1", 9, 24, "up") end)
  local function run(tag, secs)
    local b0, a0 = TA.bakes, TA.animBuilds
    for s = 5, secs, 5 do
      local frames, t0 = 0, clock()
      while clock() - t0 < 5 do
        coroutine.yield(); frames = frames + 1
        if game.stack:top() ~= ow then pcall(function() game.stack:pop() end) end
      end
      local c, a = TA.stats()
      log(("[%s] t=%3d  %5.1f fps | held: %d atlases, %d animated | +%d bakes, +%d animated builds | last key %s"):format(
        tag, s, frames / (clock() - t0), c, a, TA.bakes - b0, TA.animBuilds - a0, tostring(TA.lastBakeKey)))
      b0, a0 = TA.bakes, TA.animBuilds
    end
  end
  run("as saved", 90)
  pcall(DayNight.setting.sync, DayNight.setting, "day")
  run("DAY", 30)
  end)
  if not okAll then log("ERROR", tostring(err)) end
  logf:close()
  love.event.quit()
end
