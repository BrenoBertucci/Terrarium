-- Probe: orientation radar (lib/MiniMap.lua).
--
-- Two questions only (each round costs ~3 min):
--
--   1. ORIENTATION  does the radar's reported player cell match the engine,
--                   and do known landmarks land on the right side of the
--                   plate relative to the player?
--   2. COST         palindrome OFF-ON-ON-OFF, median frame ms, memory delta.
--                   If the two OFF halves diverge >5%, declare NOT READABLE.
--
-- Screenshot confirms the plate is on screen; numbers decide pass/fail.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/minimap_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/minimap_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b
    coroutine.yield()
  end
  local function shot(name)
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
    wait(3)
  end
  local function median(t)
    if #t == 0 then return 0 end
    local s = {}
    for i = 1, #t do s[i] = t[i] end
    table.sort(s)
    return s[math.floor((#s + 1) / 2)]
  end

  love.math.setRandomSeed(20260804)

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

  local MiniMap = lib.require("MiniMap")
  local Quality = lib.require("Quality")
  local DayNight = lib.require("DayNight")
  local Pipelines = require("src.render.Pipelines")

  -- Pin a known hour so screenshots are comparable.
  DayNight.setting:sync("day")
  DayNight.clock = DayNight.T and DayNight.T.day or DayNight.clock
  Pipelines.setLevel("terrarium_voxel", 4)
  Quality.setting:sync(2)   -- RES 1/2, the default rung that must stay cheap

  -- ------- Q1: orientation on Viridian City
  log("=== Q1: orientation (Viridian City) ===")
  MiniMap.forceMode("full")
  game.overworld:setMap("VIRIDIAN_CITY", 23, 26, "up")
  wait(180)

  local ow = game.overworld
  local p = ow.player
  local map = ow.map
  log(("map %s  player cell (%s,%s) facing %s  size %sx%s")
      :format(tostring(map and map.id), tostring(p and p.cellX),
              tostring(p and p.cellY), tostring(p and p.facing),
              tostring(map and map.widthCells),
              tostring(map and map.heightCells)))

  -- Force a present so MiniMap.report has a last-draw sample.
  wait(30)
  local r = MiniMap.report()
  log(("report: drawn=%s mode=%s res=%s size=%s grid=%s %sx%s")
      :format(tostring(r.drawn), tostring(r.mode), tostring(r.res),
              tostring(r.size), tostring(r.hasGrid),
              tostring(r.gridW), tostring(r.gridH)))
  log(("  engine cell (%s,%s)  report cell (%s,%s)  match=%s")
      :format(tostring(r.engineCellX), tostring(r.engineCellY),
              tostring(r.reportCellX), tostring(r.reportCellY),
              tostring(r.cellMatch)))
  log(("  uv=(%.3f,%.3f)  landmarks=%d  connections=%d")
      :format(r.u or -1, r.v or -1, r.nLandmarks or 0, r.nConnections or 0))

  if not r.drawn then
    log("  FAIL: radar did not draw -- " .. tostring(r.reason))
  end
  if not r.cellMatch then
    log("  FAIL: report cell does not match engine cell")
  else
    log("  PASS: player cell matches")
  end

  -- Landmarks: look for a pokecenter / gym dest among warps and check they
  -- sit on a sensible side of the player on the map.
  local centers, gyms = 0, 0
  for _, lm in ipairs(r.landmarks or {}) do
    log(("  landmark %s @ (%d,%d) -> %s")
        :format(lm.kind, lm.cx, lm.cy, tostring(lm.dest)))
    if lm.kind == "center" then centers = centers + 1 end
    if lm.kind == "gym" then gyms = gyms + 1 end
    if p and r.mapW and r.mapW > 0 then
      local relX = lm.cx - p.cellX
      local relY = lm.cy - p.cellY
      log(("    relative to player: dx=%d dy=%d")
          :format(relX, relY))
    end
  end
  if centers == 0 then
    log("  WARN: no POKECENTER warp landmark on this map "
        .. "(name pattern may differ; not a hard fail)")
  else
    log("  PASS: " .. centers .. " center landmark(s)")
  end

  shot("minimap_viridian_full.png")

  -- Warp to Pewter and confirm the radar updates map id + cell without
  -- leaking (grid image released / rebuilt).
  log("")
  log("=== warp update (Pewter City) ===")
  local memBefore = collectgarbage("count")
  game.overworld:setMap("PEWTER_CITY", 16, 26, "up")
  wait(180)
  local r2 = MiniMap.report()
  local memAfter = collectgarbage("count")
  log(("map now %s  drawn=%s  cellMatch=%s  landmarks=%d")
      :format(tostring(r2.mapId), tostring(r2.drawn),
              tostring(r2.cellMatch), r2.nLandmarks or 0))
  log(("  mem kb before=%.1f after=%.1f delta=%+.1f")
      :format(memBefore, memAfter, memAfter - memBefore))
  if r2.mapId ~= "PEWTER_CITY" then
    log("  FAIL: map id did not update after warp")
  elseif not r2.cellMatch then
    log("  FAIL: cell mismatch after warp")
  else
    log("  PASS: radar followed the warp")
  end
  for _, lm in ipairs(r2.landmarks or {}) do
    if lm.kind == "gym" or lm.kind == "center" then
      log(("  landmark %s @ (%d,%d) -> %s")
          :format(lm.kind, lm.cx, lm.cy, tostring(lm.dest)))
    end
  end
  shot("minimap_pewter_full.png")

  -- Mini (ON) mode screenshot for the always-on look.
  MiniMap.forceMode("on")
  wait(20)
  shot("minimap_pewter_on.png")
  local rOn = MiniMap.report()
  log(("ON mode: drawn=%s hasGrid=%s size=%s")
      :format(tostring(rOn.drawn), tostring(rOn.hasGrid), tostring(rOn.size)))

  -- ------- Q2: cost palindrome OFF-ON-ON-OFF
  log("")
  log("=== Q2: cost palindrome OFF-ON-ON-OFF (RES=1/2, voxel rung 4) ===")
  -- Stay on Pewter, freeze daytime.
  DayNight.setting:sync("day")

  local FRAMES = 120
  local function phase(label, mode)
    MiniMap.forceMode(mode)
    -- settle a few frames after the mode flip (grid rebuild is one-shot)
    for _ = 1, 30 do coroutine.yield() end
    local s = {}
    local prev = love.timer.getTime()
    for i = 1, FRAMES do
      coroutine.yield()
      local now = love.timer.getTime()
      s[i] = (now - prev) * 1000
      prev = now
    end
    local p50 = median(s)
    table.sort(s)
    local p95 = s[math.floor(FRAMES * 0.95)]
    log(("  %-14s p50 %6.3f  p95 %6.3f  worst %7.3f ms")
        :format(label, p50, p95, s[FRAMES]))
    return p50, p95
  end

  -- Memory sample helper (Lua heap + GPU stats if available)
  local function memSnap(tag)
    collectgarbage("collect")
    local luaKb = collectgarbage("count")
    local stats = {}
    if love.graphics.getStats then
      local ok, st = pcall(love.graphics.getStats)
      if ok and type(st) == "table" then stats = st end
    end
    log(("  mem[%s] lua=%.1f kb  texturememory=%s  images=%s  canvases=%s")
        :format(tag, luaKb,
                tostring(stats.texturememory or "?"),
                tostring(stats.images or "?"),
                tostring(stats.canvases or "?")))
    return luaKb, stats
  end

  -- Warm ~900 frames ON, discarded (same settle story as night_probe).
  MiniMap.forceMode("on")
  log("  warming ~900 frames (discarded)...")
  for _ = 1, 900 do coroutine.yield() end
  phase("0 warm-up", "on")
  log("  (discarded)")

  local a = phase("1 MAP OFF", "off")
  local mOff1 = memSnap("off1")
  local b = phase("2 MAP ON", "on")
  local mOn1 = memSnap("on1")
  local c = phase("3 MAP ON", "on")
  local mOn2 = memSnap("on2")
  local d = phase("4 MAP OFF", "off")
  local mOff2 = memSnap("off2")

  local off, on = (a + d) / 2, (b + c) / 2
  local spreadOff = math.abs(d - a) / math.max(0.001, math.min(a, d)) * 100
  local spreadOn = math.abs(c - b) / math.max(0.001, math.min(b, c)) * 100
  log("")
  log(("  p50: OFF %.3f  ON %.3f  delta %+.3f ms (%+.2f%%)")
      :format(off, on, on - off, (on / off - 1) * 100))
  log(("  OFF-to-OFF spread %.1f%%  ON-to-ON spread %.1f%%")
      :format(spreadOff, spreadOn))
  if spreadOff > 5 or spreadOn > 5 then
    log("  NOT READABLE -- same-config halves diverge >5%, delta is noise")
  else
    log("  READABLE")
    if on - off > 0.5 then
      log("  FAIL: always-on radar costs more than 0.5 ms median (target ~0.1)")
    else
      log("  PASS: always-on cost within budget")
    end
  end

  local onMem = (mOn1 + mOn2) / 2
  local offMem = (mOff1 + mOff2) / 2
  log(("  lua heap OFF %.1f  ON %.1f  delta %+.1f kb")
      :format(offMem, onMem, onMem - offMem))
  -- Continuous growth ON1→ON2 would be a leak.
  if mOn2 - mOn1 > 64 then
    log(("  FAIL: ON heap grew %.1f kb between identical phases (leak?)")
        :format(mOn2 - mOn1))
  else
    log("  PASS: no ON-phase heap ramp")
  end

  -- Restore a sensible default for anyone reading the last shot.
  MiniMap.forceMode("on")
  wait(10)
  shot("minimap_final_on.png")

  log("")
  log("=== done ===")
  logf:close()
  love.event.quit()
end
