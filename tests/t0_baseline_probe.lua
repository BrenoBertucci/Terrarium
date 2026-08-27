-- Probe T0: the measured baseline every particle task will be compared to.
--
-- Two things the existing pair does not settle:
--
--   1. rain_cost_probe measures at whatever RES the saved options hold --
--      which here is FULL, not the 1/2 the mod defaults to. The agreed
--      failure line is 30 FPS AT THE DEFAULT RUNG, so the floor has to be
--      read at both rungs or it is not read at all.
--
--   2. Nothing proves the after-rain drips put PIXELS on screen. The mote
--      count says they live; a count is not a pixel (the lesson THE INK
--      already taught once). So: three captures from ONE camera -- dry,
--      downpour, after-rain -- and a straight per-pixel difference.
--
-- The camera trap this walks around: the player keeps walking after
-- setMap, so an A/B taken across a few hundred frames is two different
-- cameras. Every capture re-pins the cell and logs it, and any shot whose
-- cell moved is called out rather than quietly averaged in.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/t0_baseline_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/t0_baseline.log", "w"))
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
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
    coroutine.yield(); coroutine.yield()
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
  -- `lib` is a require shim, not a table of modules -- lib.Weather is nil
  -- and every call through it dies on the first frame. Same accessor the
  -- rain probes next door use.
  local Weather   = lib.require("Weather")
  local Quality   = lib.require("Quality")
  local WindFX    = lib.require("WindFX")
  local GroundFX  = lib.require("GroundFX")
  local DayNight  = lib.require("DayNight")
  local Pipelines = require("src.render.Pipelines")
  local ow = game.overworld

  -- Same rig as rain_interact_probe: without the voxel pipeline actually
  -- on, the milliseconds below would be the flat 2D world's and would
  -- price nothing this project is about.
  GroundFX.setting:sync("on")
  DayNight.setting:sync("day")
  Weather.setting:sync("rain")
  Pipelines.setLevel("terrarium_voxel", 4)

  -- ============ PART 1: the frame cost at BOTH rungs ============
  --
  -- One map, one hour, one wind; the only thing that moves between
  -- readings is RES and whether the shower is pinned.
  local function ms(frames)
    local t0 = love.timer.getTime()
    for _ = 1, frames do coroutine.yield() end
    return (love.timer.getTime() - t0) * 1000 / frames
  end

  if SKIP_COST then log("(cost half skipped: T0_SKIP_COST set)") end
  ow:setMap("ROUTE_1", 10, 20, "down")
  -- The first run read two dry frames 6 ms apart at RES 1/2: the chunk
  -- meshes were still being built under the measurement. The build walks
  -- twice a frame, so it wants hundreds of frames, not a hundred.
  wait(600)

  -- the ladder is { 2, 1, 3, 4 } / { "1/2", "FULL", "1/3", "1/4" }, and
  -- sync takes the VALUE, not the index (see after_rain_probe.lua)
  local SKIP_COST = (os.getenv("T0_SKIP_COST") or "") ~= ""
  local RES_LABEL = { "1/2 (default)", "FULL" }
  local RES_VALUE = { 2, 1 }
  local results = {}
  for idx = 1, (SKIP_COST and 0 or 2) do
    Quality.setting:sync(RES_VALUE[idx])
    wait(300)                      -- let the pass rebuild its canvases
    local scale = Quality.scale()
    Weather.pin(nil, 0); wait(150)
    local dry = ms(240)
    Weather.pin("rain", 1.0); wait(180)
    local wet = ms(240)
    local sh = Weather.shaftDump()
    local sp = Weather.moteCount("splash")
    local wf = (WindFX and WindFX.count and WindFX.count()) or -1
    Weather.pin(nil, 0); wait(90)
    local dry2 = ms(180)
    results[idx] = { scale = scale, dry = dry, wet = wet, dry2 = dry2,
                     sh = sh, sp = sp, wf = wf }
    log(("RES %-14s scale=%d  dry %6.2f ms (%.1f fps) | storm %6.2f ms (%.1f fps)"
         .. "  | dry again %6.2f ms  | shafts %d splashes %d windfx %d")
        :format(RES_LABEL[idx], scale, dry, 1000 / dry, wet, 1000 / wet,
                dry2, sh, sp, wf))
    local drift = math.abs(dry2 - dry)
    if drift > 1.5 then
      log(("  WARNING: the two dry readings differ by %.2f ms -- scene still"
           .. " settling, this row is suspect"):format(drift))
    end
  end

  log("")
  for idx = 1, (SKIP_COST and 0 or 2) do
    local r = results[idx]
    log(("VERDICT RES %-14s storm %.1f fps  -> %s"):format(
      RES_LABEL[idx], 1000 / r.wet,
      (1000 / r.wet >= 30) and "ABOVE the 30 fps floor"
                            or "BELOW the 30 fps floor"))
  end

  -- back to the default rung for the visual half
  Quality.setting:sync(2)
  wait(90)

  -- ============ PART 2: does the after-rain put pixels on screen? ============
  --
  -- Pallet Town, because it has the roofs the eave drips come off and the
  -- water the columns come out of. Same cell re-pinned before each shot.
  local CELL_X, CELL_Y = 12, 12
  local function repin(tag)
    ow:setMap("PALLET_TOWN", CELL_X, CELL_Y, "down")
    wait(60)
    local p = ow.player
    log(("  %s camera at cell %d,%d"):format(tag, p.cellX, p.cellY))
    return p.cellX == CELL_X and p.cellY == CELL_Y
  end

  log("")
  log("=== PIXELS: dry vs downpour vs after-rain, one camera ===")

  Weather.setting:sync("off")
  Weather.pin(nil, 0)
  local ok1 = repin("dry     ")
  wait(120)
  log(("  dry: wet=%.3f cover=%.3f"):format(GroundFX.wetness(), GroundFX.cover()))
  shot("t0_dry.png")

  -- ------- A REAL SOAK, NOT FOUR SECONDS OF IT
  --
  -- GroundFX.SOAK is 55 SECONDS of downpour to a saturated ground. The
  -- first pass here ran the shower for 240 frames -- four seconds, wet
  -- 0.065 -- and then asked why the after-rain left nothing behind. It
  -- left nothing behind because it never rained. 4200 frames is seventy
  -- seconds: past saturation, with margin.
  Weather.setting:sync("rain")
  Weather.pin("rain", 0.9)
  local ok2 = repin("downpour")
  wait(4200)
  log(("  downpour: shafts %d splashes %d drips %d  wet=%.3f cover=%.3f"):format(
      Weather.shaftDump(), Weather.moteCount("splash"),
      Weather.moteCount("drip"), GroundFX.wetness(), GroundFX.cover()))
  shot("t0_rain.png")

  -- ------- ARM AFTER THE REPIN, NOT BEFORE
  --
  -- setMap clears the after-rain window (a pin survives it; this timer does
  -- not). Arming first and moving second read afterRain=0.000 and captured
  -- an ordinary dry frame with a few drips still dying in it.
  local ok3 = repin("after   ")
  -- ------- THE ROW HAS TO LET GO, NOT JUST THE PIN
  --
  -- The setup pins the WEATHER row to RAIN. With the row still saying RAIN,
  -- tick() drives state.kind back to "rain" every frame, and the branch at
  -- Weather.lua:1977 clears after.untilAbs whenever kind is set and power is
  -- over 0.08 -- so the after-rain window is wiped the tick after it is
  -- armed. Every "after-rain" reading taken this way (including
  -- rain_interact_probe's) was rain still falling, not rain that stopped.
  Weather.setting:sync("off")
  Weather.pin(nil, 0)
  wait(30)
  Weather.armAfterRain(180)
  wait(180)
  local dr = Weather.moteCount("drip")
  local spl = Weather.moteCount("splash")
  log(("  after-rain: drips %d splashes %d afterRain=%.3f wet=%.3f cover=%.3f"):format(
      dr, spl, Weather.afterRain() or -1, GroundFX.wetness(), GroundFX.cover()))
  shot("t0_after.png")

  -- ------- THE CONTROL
  --
  -- Pallet Town's civilians keep walking, and the first diff credited their
  -- motion to the weather. A second dry capture, taken the same distance in
  -- time from the first as the after-rain one is, gives the noise floor
  -- that a real difference has to clear.
  Weather.setting:sync("off")
  Weather.pin(nil, 0)
  local ok4 = repin("dry ctl ")
  wait(180)
  log(("  dry control: drips %d splashes %d afterRain=%.3f wet=%.3f"):format(
      Weather.moteCount("drip"), Weather.moteCount("splash"),
      Weather.afterRain() or -1, GroundFX.wetness()))
  shot("t0_dry_control.png")

  if not (ok1 and ok2 and ok3 and ok4) then
    log("  WARNING: a capture drifted off the pinned cell -- the pixel diff"
        .. " below compares two different cameras and is NOT evidence")
  else
    log("  all three captures on the same cell")
  end

  log("done")
  logf:close()
  love.event.quit()
end
