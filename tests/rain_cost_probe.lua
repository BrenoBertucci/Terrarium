-- Probe: what each half of the rain actually costs, on one map.
--
-- The last reading was 168 ms with the shower and 108 ms without, and it
-- was worthless as an attribution: it changed the MAP and the FEATURE at
-- the same time (the wildlife check had walked the probe out to Route 1,
-- which is a far heavier scene than the town the earlier reading was
-- taken in). A difference measured across two variables is a difference
-- that belongs to neither.
--
-- So: one map, one hour, one wind, one pinned shower, and the only thing
-- that moves between readings is the thing being priced.
--
--   DRY        the scene with no weather at all -- the floor everything
--              else is measured against
--   STREAKS    the falling rain, drawn the old way (added light)
--   LENS       the same rain through the refraction shader, which costs a
--              full-screen copy plus a texture fetch per rain fragment
--              with heavy overdraw
--   IMPACTS    the splash sheets on top
--
-- Reported as milliseconds per frame over a long run, because a short one
-- on a vsync-locked driver measures the vsync.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/rain_cost_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/rain_cost.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit() return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11; if n > 1500 then break end
  end

  local lib = game.mods.exports.TERRARIUM.lib
  local Weather = lib.require("Weather")
  local Wind = lib.require("Wind")
  local DayNight = lib.require("DayNight")
  local Voxel3D = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")

  Wind.climateTarget = function() Wind.gustNow = 0.35 return 0.42 end
  DayNight.setting:sync("day")
  Weather.setting:sync("rain")
  Pipelines.setLevel("terrarium_voxel", 5)

  local function wait3D(cap)
    for i = 1, (cap or 900) do
      if Voxel3D.lampLights ~= nil then return i end
      coroutine.yield()
    end
    return -1
  end
  Voxel3D.lampLights = nil
  -- ROUTE_1: open sky, grass, trees. The heavy scene on purpose -- pricing
  -- an effect on the cheapest map in the game is how a cost gets missed.
  game.overworld:setMap("ROUTE_1", 10, 20, "down")
  wait3D(900)
  -- ------- WARM UP, AND IT IS NOT OPTIONAL
  --
  -- The first run of this reported a DRY frame at 75 ms and the same frame
  -- with four hundred raindrops in it at 56 -- which is not a measurement,
  -- it is the map still building. Chunk meshes, the shadow atlas and the
  -- ray pass all come up over the first seconds on a route, and whichever
  -- condition is measured first eats all of it.
  --
  -- So: a long idle before anything is timed, and the dry floor is read
  -- again at the END. If the two dry readings disagree the run drifted and
  -- every number between them is suspect, which the log says out loud
  -- rather than leaving to be noticed.
  wait(600)

  local function ms(frames)
    local t0 = love.timer.getTime()
    for _ = 1, frames do coroutine.yield() end
    return (love.timer.getTime() - t0) / frames * 1000
  end

  local N = 180
  local function measure(label, setup)
    setup()
    wait(90)                      -- let the field refill / drain first
    local v = ms(N)
    log(("%-10s %7.2f ms/frame"):format(label, v))
    return v
  end

  local SH, SHM = Weather.SHAFTS, Weather.SHAFTS_MAX
  local ST, SP = Weather.STREAKS, Weather.SPLASHES
  local FL = Weather.SPLASH_FLOOR

  local dry = measure("dry", function()
    Weather.pin(nil, 0)
  end)
  local streaks = measure("streaks", function()
    Weather.lens = false
    Weather.SPLASHES, Weather.SPLASH_FLOOR = 0, 0
    Weather.SHAFTS, Weather.SHAFTS_MAX = SH, SHM
    Weather.STREAKS = ST
    Weather.pin("rain", 1.0)
  end)
  local lens = measure("lens", function()
    Weather.lens = true
    Weather.pin("rain", 1.0)
  end)
  local full = measure("impacts", function()
    Weather.SPLASHES, Weather.SPLASH_FLOOR = SP, FL
    Weather.pin("rain", 1.0)
  end)
  local dry2 = measure("dry again", function()
    Weather.pin(nil, 0)
  end)
  Weather.pin("rain", 1.0)

  -- ------- and WHAT is landing, by surface
  --
  -- The claim the impacts make is that no two surfaces behave alike. That
  -- is not a thing a screenshot of a downpour settles -- the drawings are
  -- twenty pixels across and there are a hundred of them -- so it is
  -- counted: a scene with grass, stone and open sky in it has to be
  -- producing more than one kind at once, or the surface split is not
  -- reaching the draw.
  wait(60)
  if Weather.impactMix then
    local mix = Weather.impactMix()
    local kinds, total = 0, 0
    local parts = {}
    for k, v in pairs(mix) do
      kinds = kinds + 1; total = total + v
      parts[#parts + 1] = ("%s=%d"):format(k, v)
    end
    table.sort(parts)
    log(("impact mix         %s  (%d kinds, %d live)"):format(
        table.concat(parts, " "), kinds, total))
    if kinds < 2 then
      log("  FAIL: every impact on this map is the same kind")
    end
  end

  log("")
  log("=== WHAT EACH HALF COSTS (ROUTE_1, pinned downpour) ===")
  local drift = math.abs(dry2 - dry)
  local floor = (dry + dry2) * 0.5
  log(("dry floor          %7.2f ms  (%.2f first, %.2f last)"):format(
      floor, dry, dry2))
  if drift > floor * 0.10 then
    log(("  WARNING: the two dry readings differ by %.2f ms -- the scene was")
        :format(drift))
    log("  still settling and every figure below is suspect")
  end
  log(("streaks (additive) %+7.2f ms  (%d shafts)"):format(streaks - floor, SH))
  log(("the lens shader    %+7.2f ms"):format(lens - streaks))
  log(("the impacts        %+7.2f ms  (%d splashes)"):format(full - lens, SP))
  log(("weather, all in    %+7.2f ms"):format(full - floor))
  log("")
  log("done")
  logf:close()
  love.event.quit()
end
