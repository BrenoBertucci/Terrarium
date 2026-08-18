-- Probe: F0 perf baseline for the premium building kit (see
-- assets/docs/buidling_to_voxel/premium_kit_plan.md). The ~10% frame
-- budget the kit's dynamic effects may spend is measured AGAINST THESE
-- NUMBERS, on this machine (i3-1115G4 / Intel UHD).
--
-- Frame time standing still in the 4 reference cities, vsync OFF --
-- with vsync on both sides of any comparison read 16.7ms and the probe
-- measures the monitor (memory: terrarium-underpass-visibility).
--
-- Variance between the first and last phase of one run is enormous on
-- this engine (an unchanged build measured 134 vs 98 frames for the same
-- walk), so cities run FORWARD then REVERSE in the same process and each
-- city's number is the mean of its two halves -- the palindrome shape,
-- which cancels monotonic drift (memory: gen1recomp-probe-measurement).
--
-- Config is pinned and logged so a future run measures the same world:
-- day, weather off, RES rung 2, pipeline level 4. Wind is READ, not set.
--
-- POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
-- POKEPORT_DRIVER=mods/TERRARIUM/tests/buildings_perf_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/buildings_perf_probe.log", "w"))
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
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit()
      return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit()
    return
  end
  log("version:", exports.TERRARIUM.version)

  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local Voxel3D = lib.require("Voxel3D")
  local Quality = lib.require("Quality")
  local Wind = lib.require("Wind")
  local Pipelines = require("src.render.Pipelines")

  DayNight.setting:sync("day")
  Weather.setting:sync("off")
  Quality.setting:sync(2)
  Pipelines.setLevel("terrarium_voxel", 4)
  love.window.setVSync(0)
  local ww, wh = love.graphics.getDimensions()
  log(("window: %dx%d  vsync off"):format(ww, wh))
  log("wind setting (read, not pinned):",
      tostring(Wind.setting and Wind.setting.value))

  local function voxelUp(guard)
    for _ = 1, guard or 900 do
      if Voxel3D.lampLights ~= nil then return true end
      coroutine.yield()
    end
    return false
  end

  local function lockCell(guard)
    local last, stable = nil, 0
    for _ = 1, guard or 1200 do
      local p = game.overworld.player
      local cur = p and (tostring(p.cellX) .. "," .. tostring(p.cellY)) or "?"
      if cur == last then stable = stable + 1 else stable, last = 0, cur end
      if stable >= 45 then return true end
      coroutine.yield()
    end
    return false
  end

  local FRAMES = 600
  local clock = love.timer.getTime

  -- One yield is one whole frame (update + draw + present), so the gap
  -- between yields is the honest frame time.
  local function measure()
    local dts, prev = {}, clock()
    for i = 1, FRAMES do
      coroutine.yield()
      local now = clock()
      dts[i] = now - prev
      prev = now
    end
    table.sort(dts)
    local sum = 0
    for _, d in ipairs(dts) do sum = sum + d end
    local function pct(p)
      return dts[math.max(1, math.min(FRAMES, math.ceil(FRAMES * p)))]
    end
    return { mean = sum / FRAMES, p50 = pct(0.50), p95 = pct(0.95),
             p99 = pct(0.99), max = dts[FRAMES] }
  end

  local CITIES = {
    { id = "PALLET_TOWN", x = 10, y = 11 },
    { id = "LAVENDER_TOWN", x = 10, y = 10 },
    { id = "VERMILION_CITY", x = 10, y = 10 },
    { id = "CELADON_CITY", x = 10, y = 10 },
  }
  local halves = {}          -- id -> { pass1 stats, pass2 stats }

  local function visit(c)
    local ok = pcall(function()
      game.overworld:setMap(c.id, c.x, c.y, "down")
    end)
    if not ok then log(c.id, "FAIL: setMap error") return end
    wait(60)
    if game.overworld.map.id ~= c.id then
      log(("%s FAIL: landed on %s"):format(c.id,
          tostring(game.overworld.map.id)))
      return
    end
    if not voxelUp() then log(c.id, "FAIL: voxel pass never up") return end
    lockCell()
    wait(120)
    local m = measure()
    halves[c.id] = halves[c.id] or {}
    local h = halves[c.id]
    h[#h + 1] = m
    log(("%-16s half=%d mean=%.2fms p50=%.2f p95=%.2f p99=%.2f max=%.2f")
        :format(c.id, #h, m.mean * 1000, m.p50 * 1000, m.p95 * 1000,
                m.p99 * 1000, m.max * 1000))
  end

  for i = 1, #CITIES do visit(CITIES[i]) end
  for i = #CITIES, 1, -1 do visit(CITIES[i]) end

  log("")
  log("combined (mean of both halves -- the F0 baseline):")
  for _, c in ipairs(CITIES) do
    local h = halves[c.id]
    if h and #h == 2 then
      log(("%-16s mean=%.2fms p95=%.2fms p99=%.2fms")
          :format(c.id, (h[1].mean + h[2].mean) * 500,
                  (h[1].p95 + h[2].p95) * 500,
                  (h[1].p99 + h[2].p99) * 500))
    else
      log(c.id, "INCOMPLETE")
    end
  end

  love.window.setVSync(1)
  log("done -- " .. OUT)
  logf:close()
  love.event.quit()
end
