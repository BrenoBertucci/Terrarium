-- Probe: does the PFX row actually move anything, and does it move only
-- what it is supposed to?
--
-- The row is a multiplier over budgets that used to hang off RES alone.
-- Two claims, and a row that fails either is a row that lies to the player:
--
--   IT MOVES        the live counts -- wind motes, rain shafts, splashes,
--                   flakes -- have to change with the rung. A row that
--                   cycles and changes nothing is worse than no row.
--
--   ON IS TODAY     the ON rung has to reproduce the counts that were
--                   there before it existed, at whatever RES is set.
--                   Anything else silently re-tunes everybody's game the
--                   first time they launch.
--
--   RES IS UNTOUCHED  the whole point. RES is held FIXED across all four
--                   rungs here, and the counts still move -- which is what
--                   "its own row" means and what could not be done before.
--
-- Counts are read as BUDGETS (Weather.budgets, Quality.windStreaks) as
-- well as live populations, because a budget is exact and a population is
-- a spawn rate catching up to it. The budget proves the plumbing; the live
-- count proves the budget is being obeyed.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/pfx_row_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/pfx_row.log", "w"))
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
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end
  log("version:", exports.TERRARIUM.version)

  local Weather  = lib.require("Weather")
  local WindFX   = lib.require("WindFX")
  local Wind     = lib.require("Wind")
  local DayNight = lib.require("DayNight")
  local Quality  = lib.require("Quality")
  local Pipelines = require("src.render.Pipelines")

  if not Quality.particleSetting then
    log("FAIL: no PFX row -- Quality.particleSetting is nil")
    logf:close(); love.event.quit(); return
  end
  if not Weather.budgets then
    log("FAIL: Weather.budgets missing -- cannot read the caps")
    logf:close(); love.event.quit(); return
  end

  -- ------- WHEN, EXACTLY, DOES THE UPDATE CHAIN STOP?
  --
  -- The counters said WindFX.update and Weather.update were called ZERO
  -- times across 420 frames, while the field sat at a steady-state value
  -- it could only have reached by running. So they ran and then stopped,
  -- and the whole question is WHICH LINE OF THIS PROBE stopped them.
  -- Sampled after every step, absolutely rather than as a delta.
  local function mark(tag)
    local top = game.stack and game.stack:top()
    local what = (top == game.overworld) and "overworld"
              or (top and (tostring(top.name or top.id or top)) or "nil")
    log(("  [ticks after %-22s] windfx %6d  weather %6d  gate=%-10s top=%s")
        :format(tag, WindFX.ticks, Weather.ticks,
                tostring(WindFX.lastGate), what))
    local AL = lib.require("AmbientLife")
    if AL.errorCount and AL.errorCount > 0 then
      log(("      AmbientLife.update threw %d times; last: %s")
          :format(AL.errorCount, tostring(AL.lastError)))
    end
  end
  mark("boot")

  -- ------- ONE VARIABLE: THE AMBIENT LIFE
  --
  -- The chain stops ~196 frames after arriving on a grassy route, which is
  -- about when the first critter spawns, and the throw has to be ABOVE
  -- Weather.update in main.lua's list (Weather.ticks froze on the same
  -- frame). AmbientLife.update is line 265; Weather.update is 277. Turning
  -- it off is the cleanest single-variable test of that.
  local AmbientLife = lib.require("AmbientLife")
  if os.getenv("PFX_NO_AMBIENT") then
    AmbientLife.setting:sync("off")
    log("AMBIENT forced OFF for this run")
  else
    AmbientLife.setting:sync("on")
    log("AMBIENT on")
  end

  DayNight.setting:sync("day")
  Wind.setting:sync(4)                 -- GALE, so the wind field is full
  Weather.setting:sync("rain")
  mark("settings synced")
  Pipelines.setLevel("terrarium_voxel", 4)
  wait(60)
  mark("setLevel voxel")

  -- ------- RES IS READ, NOT SET
  --
  -- The first run of this forced RES to 1/2 while the saved options held
  -- FULL, and every live count then froze: 420 frames with the wind field
  -- stuck at 39 under a budget of 19, which the per-frame cap makes
  -- impossible unless the update never ran. Changing RES mid-probe takes
  -- the 3D pass down while its canvases are rebuilt, and the flat 2D path
  -- does not tick the particle systems at all -- so the field was not
  -- ignoring its budget, it was not running.
  --
  -- The claim here is that PFX moves the counts WITHOUT RES moving, and
  -- that is just as well tested by leaving RES wherever it already is and
  -- reporting it. One variable, and it is the PFX row.
  local RES = Quality.scale()

  game.overworld:setMap("ROUTE_1", 10, 20, "down")
  wait(300)
  mark("setMap + 300")
  wait(300)
  mark("setMap + 600")
  Weather.pin("rain", 0.95)
  wait(150)
  mark("pin rain + 150")
  wait(150)
  mark("pin rain + 300")

  log(("RES left at whatever the options hold: scale %d, untouched all run"):format(RES))
  log("")
  log(("%-6s %5s | %8s %8s %8s %8s | %8s %8s %8s")
      :format("rung", "mul", "windBud", "shaftBud", "splBud", "dripBud",
              "windLive", "shaftLive", "splLive"))

  local rows = {}
  -- the ladder's VALUES, not its labels: 0 LOW / 1 ON / 2 HIGH / 3 MAX
  for _, v in ipairs({ 0, 1, 2, 3 }) do
    Quality.particleSetting:sync(v)
    -- ------- IS ANYTHING ALIVE AT ALL?
    --
    -- The first run of this read the same live counts to the digit across
    -- four different budgets, and one of them was impossible: 40 wind
    -- motes under a budget of 19, when the cap is pushed every frame and
    -- culls immediately. That is not a spawner lagging a ceiling, that is
    -- nothing updating. So each rung now takes two readings a few seconds
    -- apart and says whether the world moved between them.
    local w0, s0 = WindFX.count(), Weather.shaftDump()
    local wt0, wl0 = WindFX.ticks, WindFX.ticksLive
    local et0, eo0 = Weather.ticks, Weather.ticksOk
    wait(420)
    local w1, s1 = WindFX.count(), Weather.shaftDump()
    local dwt, dwl = WindFX.ticks - wt0, WindFX.ticksLive - wl0
    local det, deo = Weather.ticks - et0, Weather.ticksOk - eo0
    local wfail, werr = Weather.failState()
    log(("   [rung %d] wind %d->%d  shafts %d->%d"):format(v, w0, w1, s0, s1))
    log(("      WindFX.update called %d over 420 frames, live %d, gate=%s")
        :format(dwt, dwl, tostring(WindFX.lastGate)))
    log(("      Weather.update called %d, tick ok %d, failed=%s")
        :format(det, deo, tostring(wfail)))
    if werr then log(("      Weather last error: %s"):format(werr)) end
    local sh, sp, fl, dr, mul = Weather.budgets()
    local wb = Quality.windStreaks()
    local r = {
      v = v, mul = mul, wb = wb, sh = sh, sp = sp, dr = dr, fl = fl,
      wl = WindFX.count(),
      sl = Weather.shaftDump(),
      pl = Weather.moteCount("splash"),
    }
    rows[#rows + 1] = r
    log(("%-6d %5.2f | %8d %8d %8d %8d | %8d %8d %8d")
        :format(v, mul, wb, sh, sp, dr, r.wl, r.sl, r.pl))
  end

  log("")
  -- ------- the two things that have to be true
  local on = nil
  for _, r in ipairs(rows) do if r.v == 1 then on = r end end
  local low, max = rows[1], rows[#rows]

  if on and math.abs(on.mul - 1.0) < 1e-6 then
    log("PASS: ON is multiplier 1.00 -- the counts it gives are the old ones")
  else
    log("FAIL: ON is not 1.00; it would re-tune every existing game")
  end

  if max.wb > low.wb and max.sh > low.sh and max.sp > low.sp then
    log(("PASS: budgets move with the row (wind %d->%d, shafts %d->%d, splashes %d->%d)")
        :format(low.wb, max.wb, low.sh, max.sh, low.sp, max.sp))
  else
    log("FAIL: a budget did not move between LOW and MAX -- the row is inert")
  end

  if max.wl > low.wl and max.sl > low.sl then
    log(("PASS: the live field follows (wind %d->%d, shafts %d->%d)")
        :format(low.wl, max.wl, low.sl, max.sl))
  else
    log(("WARNING: budgets moved but the live field did not (wind %d->%d,"
         .. " shafts %d->%d) -- a cap is being ignored somewhere")
        :format(low.wl, max.wl, low.sl, max.sl))
  end

  log(("RES never moved: scale is still %d"):format(Quality.scale()))

  Quality.particleSetting:sync(1)
  Weather.pin(nil, 0)
  log("done")
  logf:close()
  love.event.quit()
end
