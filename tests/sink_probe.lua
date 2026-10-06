-- The vertex sink: what the heap costs, and whether the world still looks
-- like itself.
--
-- The mesher has had a fast path since before this probe existed and it has
-- never run in the game. `ffi` is in the engine sandbox's DENIED table
-- (src/mods/Sandbox.lua, beside io/os/debug/package), so the
-- `pcall(require, "ffi")` at the top of lib/ChunkMesher.lua always fails and
-- newSink has always fallen through to the TABLE sink -- one six-field Lua
-- table per vertex, four per quad, millions per route.
--
-- That is a heap story, not a frame story, and this repo already has the
-- heap numbers: 699-700 MB live with a full collect taking 900-992 ms
-- (probe_out_lavground/lavground_cost.log), against p99 frame times of
-- 111-195 ms and maxima of 805-986 ms
-- (probe_out_f5_perf/buildings_perf_probe.log). A 900 ms collect and a
-- 986 ms frame are the same event written down twice.
--
-- So this measures the thing that should move -- BYTES, not milliseconds --
-- and then checks the world still renders identically, because a sink that
-- packs the wrong floats is fast and silent and wrong. The screenshot is the
-- real test here; the heap is the reason for the change.
--
--   POKEPORT_VERSION=yellow \
--   DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/sink_probe.lua gen1recomp

return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/sink_probe.log", "w"))
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

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end

  local Quality     = lib.require("Quality")
  local Weather     = lib.require("Weather")
  local DayNight    = lib.require("DayNight")
  local Wind        = lib.require("Wind")
  local MiniMap     = lib.require("MiniMap")
  local AutoFarm    = lib.require("AutoFarm")
  local AmbientLife = lib.require("AmbientLife")
  local CityLife    = lib.require("CityLife")
  local WildRoamers = lib.require("WildRoamers")
  local Trees3D     = lib.require("Trees3D")
  local ChunkMesher = lib.require("ChunkMesher")
  local Pipelines   = require("src.render.Pipelines")

  love.window.setVSync(0)
  Pipelines.setLevel("terrarium_voxel", 3)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  MiniMap.setting:sync("off")
  AutoFarm.setting:sync("off")
  Weather.setting:sync("off")
  DayNight.setting:sync("day")
  Wind.setting:sync(0)
  AmbientLife.setting:sync("off")
  CityLife.setting:sync("off")
  WildRoamers.setting:sync("off")
  local KEEP_RES = Quality.setting:get()
  Quality.setting:sync(2)

  local CLOCK = 300
  local function hold(f)
    for _ = 1, f do DayNight.clock = CLOCK; coroutine.yield() end
    DayNight.clock = CLOCK
  end

  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(d)
      local f = io.open(OUT .. "/" .. name .. ".png", "wb")
      if f then f:write(d:encode("png"):getString()); f:close() end
      done = true
    end)
    local k = 0
    while not done and k < 300 do DayNight.clock = CLOCK; coroutine.yield(); k = k + 1 end
  end

  local function settle(maxTicks)
    local quiet = 0
    for _ = 1, (maxTicks or 4000) do
      DayNight.clock = CLOCK
      coroutine.yield()
      local map = game.overworld and game.overworld.map
      local done, state = Trees3D.ready(map)
      if ChunkMesher.pending() == 0 and (done or state == "hulls") then
        quiet = quiet + 1
        if quiet >= 45 then return true end
      else
        quiet = 0
      end
    end
    return false
  end

  local SPOTS = {
    { "ROUTE_2", 10, 10, "up" },
    { "VIRIDIAN_CITY", 24, 22, "up" },
    { "PALLET_TOWN", 10, 8, "up" },
  }

  -- Heap in megabytes, after a full collect so the number is LIVE data and
  -- not whatever the incremental collector had not reached yet. The collect
  -- is also the thing being measured: its duration is the frame spike.
  local function heapMB()
    local t0 = love.timer.getTime()
    collectgarbage("collect")
    local ms = (love.timer.getTime() - t0) * 1000
    return collectgarbage("count") / 1024, ms
  end

  log("== the vertex sink: heap, build time, and whether the bytes agree ==")
  -- NOT `pcall(require, "ffi")` from here: a probe is loaded through
  -- POKEPORT_DRIVER and runs OUTSIDE the mod sandbox, so it would answer
  -- for itself and say true. Ask the module that actually lives inside it.
  local sawFFI = "no hasFFI()"
  if ChunkMesher.hasFFI then sawFFI = tostring(ChunkMesher.hasFFI()) end
  log(("ChunkMesher sees ffi: %s   (the sandbox denies it to mod code, so"
       .. " false here is the fallback that has always run)"):format(sawFFI))
  local okSelf, detail = ChunkMesher.sinkSelfCheck()
  log(("sink self-check: %s -- %s"):format(tostring(okSelf), tostring(detail)))
  log("")

  for _, spot in ipairs(SPOTS) do
    log(("== %s =="):format(spot[1]))
    for _, which in ipairs({ "table", "pack" }) do
      ChunkMesher.SINK = which
      ChunkMesher.invalidate()
      Trees3D.invalidate()
      collectgarbage("collect")
      local before = collectgarbage("count") / 1024
      local t0 = love.timer.getTime()
      game.overworld:setMap(spot[1], spot[2], spot[3], spot[4])
      local ok = settle(6000)
      local buildMs = (love.timer.getTime() - t0) * 1000
      for _ = 1, 4 do
        game.overworld:setMap(spot[1], spot[2], spot[3], spot[4])
        hold(6)
      end
      hold(30)
      -- THE PICTURE COMES FIRST.  The player walks on its own for a few
      -- ticks after a setMap, so a shot taken at the END of this block is
      -- taken from a camera a few pixels along from where the other
      -- condition's was -- and on an image this full of dither, two pixels
      -- of pan flips half the frame and reads as a broken sink.
      game.overworld:setMap(spot[1], spot[2], spot[3], spot[4])
      hold(4)
      shot("sink_" .. spot[1] .. "_" .. which)
      local peak = collectgarbage("count") / 1024
      local live, collectMs = heapMB()
      -- frame time after everything has settled, so the collect above is
      -- not inside the sample
      hold(30)
      local dts = {}
      local prev = love.timer.getTime()
      for _ = 1, 90 do
        DayNight.clock = CLOCK
        coroutine.yield()
        local t = love.timer.getTime()
        dts[#dts + 1] = (t - prev) * 1000
        prev = t
      end
      table.sort(dts)
      log(("   %-5s build %7.1f ms  heap before %6.1f -> peak %6.1f -> live %6.1f MB"
           .. "  collect %6.1f ms  frame p50 %5.2f p95 %6.2f max %7.2f  settled=%s")
            :format(which, buildMs, before, peak, live, collectMs,
                    dts[math.ceil(#dts * 0.5)], dts[math.ceil(#dts * 0.95)],
                    dts[#dts], tostring(ok)))
    end
    log("")
  end

  ChunkMesher.SINK = "auto"
  ChunkMesher.invalidate()
  Trees3D.invalidate()
  Quality.setting:sync(KEEP_RES)
  AmbientLife.setting:sync("auto")
  love.window.setVSync(1)
  log("done")
  logf:close()
  love.event.quit()
end
