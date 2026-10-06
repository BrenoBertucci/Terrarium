-- Probe: the MIST row, and FULL letting go of DAYTIME.
--
-- Three questions, each answered in the log rather than by a picture:
--   1. Under FULL, is the DAYTIME row on the OPTIONS menu, and does a pin
--      (DUSK) survive the menu opening? (It used to snap back to SYNC.)
--   2. What does the mist do over the clock -- amount, colour, the body's
--      bearing and strength -- a second at a time on a 60 s grid.
--   3. (What it costs lives in tests/mist_cost_probe.lua.)
-- The screenshots are confirmation, taken on a PINNED clock (DayNight.time
-- is stubbed for the run and put back at the end).
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/mist_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/mist_probe.log", "w"))
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
  local Voxel3D = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")
  local ow = game.overworld

  local savedDaytime = DayNight.setting:get()
  local savedMist = Mist.setting:get()
  local savedLevel = Pipelines.level("terrarium_voxel")
  Weather.setting:sync("off")

  -- ------- 1. FULL and DAYTIME
  Pipelines.setLevel("terrarium_voxel", 1)          -- FULL
  DayNight.setting:sync("dusk")
  local okM, OptionsMenu = pcall(require, "src.ui.OptionsMenu")
  if okM then
    local menu = OptionsMenu.new(game)
    game.stack:push(menu)
    wait(4)
    local rows, have = menu.rows or {}, {}
    for _, r in ipairs(rows) do
      if type(r) == "table" and r.id then have[r.id] = r end
    end
    local dt, mi = have["TERRARIUM:daytime"], have["TERRARIUM:mist"]
    log(("FULL: rows=%d daytimeRow=%s value=%s mistRow=%s mistValue=%s "
         .. "pin=%s time=%.0f")
        :format(#rows, tostring(dt ~= nil),
                dt and tostring(dt.value()) or "-",
                tostring(mi ~= nil), mi and tostring(mi.value()) or "-",
                tostring(DayNight.setting:get()), DayNight.time()))
    log(DayNight.setting:get() == "dusk" and "PASS: FULL keeps DUSK"
        or "FAIL: FULL moved the pin")
    log(dt and "PASS: DAYTIME offered under FULL"
        or "FAIL: DAYTIME missing under FULL")
    pcall(game.stack.pop, game.stack)
    wait(4)
  else
    log("SKIP: no OptionsMenu module")
  end
  -- the new pin
  DayNight.setting:sync("afternoon")
  local mixA = DayNight.mix(DayNight.time())
  log(("AFTERNOON: time=%.0f golden=%.2f day=%.2f dusk=%.2f")
      :format(DayNight.time(), mixA.golden or 0, mixA.day or 0, mixA.dusk or 0))

  -- ------- 2. the curve, as numbers
  Mist.setting:sync("on")
  local realTime = DayNight.time
  local T = 0
  DayNight.time = function() return T end
  for t = 0, 1140, 60 do
    T = t
    local a = Mist.frame(true)
    if a then
      log(("curve t=%4d amount=%.3f color=%.2f,%.2f,%.2f sun=%.2f,%.2f str=%.3f "
           .. "tone=%.2f,%.2f,%.2f")
          :format(t, a.mist[1], a.color[1], a.color[2], a.color[3],
                  a.sun[1], a.sun[2], a.sun[3],
                  a.sunColor[1], a.sunColor[2], a.sunColor[3]))
    else
      log(("curve t=%4d amount=0 (clear)"):format(t))
    end
  end
  Mist.setting:sync("off")
  log("off at dawn gives nil:", tostring(Mist.frame(true) == nil and T >= 0))
  Mist.setting:sync("on")
  T = 0
  log("indoors at dawn gives nil:", tostring(Mist.frame(false) == nil))

  -- ------- 3. the pictures, on a pinned clock
  local function settle()
    local quiet, guard = 0, 0
    while quiet < 45 and guard < 2400 do
      coroutine.yield(); guard = guard + 1
      if ChunkMesher.pending() == 0 then quiet = quiet + 1 else quiet = 0 end
    end
    game.input:reset()
    wait(30)
  end
  local function walk(dir, frames)
    for _ = 1, frames do game.input.state[dir] = true; coroutine.yield() end
    game.input.state[dir] = false
    game.input:reset()
  end
  local function state(tag)
    local m = Voxel3D.mist
    log(("%s map=%s t=%.0f mist=%s wake=%d sunStr=%s")
        :format(tag, ow.map.id, T, m and ("%.3f"):format(m[1]) or "nil",
                Voxel3D.mistWake and #Voxel3D.mistWake or 0,
                Voxel3D.mistSun and ("%.3f"):format(Voxel3D.mistSun[3]) or "nil"))
  end
  local function pose(mapId, cx, cy, facing)
    ow:setMap(mapId, cx, cy, facing or "down")
    settle()
  end

  pose("PALLET_TOWN", 10, 12, "down")
  for _, t in ipairs({ 20, 150, 300, 580, 680, 900, 1170 }) do
    T = t
    wait(6)
    state("pallet")
    shot(("mist_pallet_%04d.png"):format(t))
  end
  T = 20
  Mist.setting:sync("off")
  wait(6)
  state("pallet-off")
  shot("mist_pallet_0020_off.png")
  Mist.setting:sync("on")

  -- the wake: walk through it at dawn, shoot on the move
  T = 20
  pose("PALLET_TOWN", 6, 9, "down")
  walk("down", 40)
  state("pallet-walk")
  shot("mist_pallet_wake.png")
  wait(150)
  state("pallet-closed")
  shot("mist_pallet_wake_closed.png")

  pose("VIRIDIAN_CITY", 20, 24, "down")
  T = 900
  wait(6)
  state("viridian-night")
  shot("mist_viridian_0900.png")
  Mist.setting:sync("off")
  wait(6)
  shot("mist_viridian_0900_off.png")
  Mist.setting:sync("on")

  pose("VERMILION_CITY", 18, 20, "down")
  for _, t in ipairs({ 10, 660, 960 }) do
    T = t
    wait(6)
    state("vermilion")
    shot(("mist_vermilion_%04d.png"):format(t))
  end

  -- put everything back, in memory, before quitting
  DayNight.time = realTime
  DayNight.setting:sync(savedDaytime)
  Mist.setting:sync(savedMist)
  Pipelines.setLevel("terrarium_voxel", savedLevel)
  log("done")
  logf:close()
  love.event.quit()
end
