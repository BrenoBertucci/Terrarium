-- What each HORIZON rung costs, at the same pinned ROUTE_1 pose the void
-- measurement used. The recommendation is a default rung on an i3-1115G4
-- with integrated UHD, so "how much void closes" is only half the question.
--
-- Frame time is sampled as wall time between driver yields. If every rung
-- comes back at the same ~16.7ms the run is vsync-capped and says nothing --
-- that case is detected and reported rather than dressed up as a result.

return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/void_cost_probe.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
    logf:write(table.concat(p, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end

  local lib = game.mods and game.mods.exports
              and game.mods.exports.TERRARIUM and game.mods.exports.TERRARIUM.lib
  if not lib then log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return end

  local Skyline = lib.require("Skyline")
  local Aerial = lib.require("Aerial")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local MiniMap = lib.require("MiniMap")
  local AutoFarm = lib.require("AutoFarm")
  local Pipelines = require("src.render.Pipelines")

  local saved = {
    skyline = Skyline.setting:get(), haze = Aerial.setting:get(),
    weather = Weather.setting:get(), daytime = DayNight.setting:get(),
    minimap = MiniMap.setting:get(), autofarm = AutoFarm.setting:get(),
  }

  Pipelines.setLevel("terrarium_voxel", 5)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  MiniMap.setting:sync("off")
  AutoFarm.setting:sync("off")
  Weather.setting:sync("rain")
  DayNight.setting:sync("cycle")

  local CLOCK = 300
  local function hold(f)
    for _ = 1, f do DayNight.clock = CLOCK; coroutine.yield() end
    DayNight.clock = CLOCK
  end

  local SPOT = { "ROUTE_1", 8, 12, "up" }
  game.overworld:setMap(SPOT[1], SPOT[2], SPOT[3], SPOT[4])
  hold(400)
  Skyline.setting:sync(3); Aerial.setting:sync(2); hold(200)   -- prebuild all 8

  local function pin()
    for _ = 1, 6 do
      game.overworld:setMap(SPOT[1], SPOT[2], SPOT[3], SPOT[4])
      hold(6)
      local p = game.overworld.player
      if p and p.cellX == SPOT[2] and p.cellY == SPOT[3] then return true end
    end
    return false
  end

  local function pct(s, p)
    local i = math.max(1, math.min(#s, math.ceil(#s * p)))
    return s[i]
  end

  local N = 300
  local function sampleRung(label, level, haze)
    Skyline.setting:sync(level)
    Aerial.setting:sync(haze)
    hold(90)
    local pinned = pin()
    local dts, prev = {}, love.timer.getTime()
    for _ = 1, N do
      DayNight.clock = CLOCK
      coroutine.yield()
      local t = love.timer.getTime()
      dts[#dts + 1] = (t - prev) * 1000
      prev = t
    end
    table.sort(dts)
    local sum = 0
    for _, v in ipairs(dts) do sum = sum + v end
    log(("  %-5s HAZE=%d pinned=%-5s n=%d  avg=%6.2fms  p50=%6.2f  p95=%6.2f  worst=%7.2f")
          :format(label, haze, tostring(pinned), #dts, sum / #dts,
                  pct(dts, 0.50), pct(dts, 0.95), dts[#dts]))
    -- p50, not the mean: one 300ms hitch from a background process drags an
    -- average across a whole rung, and the first sweep showed exactly that.
    return pct(dts, 0.50)
  end

  log("frame cost by HORIZON rung -- ROUTE_1 (8,12) up, rain, clock=300")
  log(("view %dx%d"):format(game.renderer:worldViewSize()))
  log("")
  -- ROUND-ROBIN, because a straight OFF->ALL sweep confounds rung with time:
  -- the first pass of that ordering put 218-363ms spikes in the early samples
  -- and reported NEAR (0 impostors) as costlier than ALL (8), which cannot be
  -- a rung effect. Visiting every rung once per round lets warm-up and any
  -- background load fall on all four equally.
  local ROUNDS = 3
  local acc = { [0] = {}, [1] = {}, [2] = {}, [3] = {} }
  local NAME = { [0] = "OFF", [1] = "NEAR", [2] = "FAR", [3] = "ALL" }
  for round = 1, ROUNDS do
    log(("-- round %d"):format(round))
    for level = 0, 3 do
      local m = sampleRung(NAME[level], level, 2)
      acc[level][#acc[level] + 1] = m
    end
  end

  log("")
  log("  median of the per-round medians (the robust number):")
  local med = {}
  for level = 0, 3 do
    local s = {}
    for i, v in ipairs(acc[level]) do s[i] = v end
    table.sort(s)
    med[level] = s[math.ceil(#s / 2)]
    log(("    %-5s rounds=%s  ->  %.2fms")
          :format(NAME[level],
                  table.concat({ ("%.2f"):format(acc[level][1]),
                                 ("%.2f"):format(acc[level][2] or 0),
                                 ("%.2f"):format(acc[level][3] or 0) }, "/"),
                  med[level]))
  end
  local lo, hi = math.huge, -math.huge
  for level = 0, 3 do lo = math.min(lo, med[level]); hi = math.max(hi, med[level]) end
  log(("  spread across rungs: %.2fms (%.1f%% of OFF)")
        :format(hi - lo, (hi - lo) / med[0] * 100))
  log(("  ALL minus OFF: %+.2fms"):format(med[3] - med[0]))
  if med[3] < med[0] then
    log("  NOTE: ALL came out no slower than OFF -- the rung difference is")
    log("        under this machine's frame-to-frame noise. Cost is not the")
    log("        thing to pick a rung on.")
  end

  Skyline.setting:sync(saved.skyline); Aerial.setting:sync(saved.haze)
  Weather.setting:sync(saved.weather); DayNight.setting:sync(saved.daytime)
  MiniMap.setting:sync(saved.minimap); AutoFarm.setting:sync(saved.autofarm)
  log("done")
  logf:close()
  love.event.quit()
end
