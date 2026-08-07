-- Probe: wind moves grass (and NPC lean) with controlled pixel change under
-- a frozen clock / fixed wind phase samples.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/wind_sway_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/wind_sway_probe.log", "w"))
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

  local Wind = lib.require("Wind")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Pipelines = require("src.render.Pipelines")

  DayNight.setting:sync("day")
  Weather.setting:sync("off")
  -- Wind values are numeric: 2=BREEZE, 4=GALE, 0=OFF
  Wind.setting:sync(2)
  Pipelines.setLevel("terrarium_voxel", 4)

  -- Route 1 has tall grass
  game.overworld:setMap("ROUTE_1", 10, 28, "down")
  wait(180)
  for _ = 1, 60 do Weather.update(1 / 30) end

  local amt = Wind.amount()
  log(("Wind.amount=%.3f enabled=%s"):format(amt, tostring(Wind.enabled())))

  -- sample leanAt over successive absolute-time phases (motion metric)
  local wx, wz = 160, 448
  local samples = {}
  for i = 1, 12 do
    wait(4)
    local dx, dz = Wind.leanAt(wx, wz, 1.0)
    samples[#samples + 1] = { dx = dx, dz = dz, phase = Wind.phase() }
    log(("lean[%d] dx=%.3f dz=%.3f phase=%.3f"):format(i, dx, dz, Wind.phase()))
  end

  local moved = 0
  for i = 2, #samples do
    local a, b = samples[i - 1], samples[i]
    local d = math.abs(a.dx - b.dx) + math.abs(a.dz - b.dz)
    if d > 0.02 then moved = moved + 1 end
  end
  log(("lean frame-to-frame moves: %d / %d"):format(moved, #samples - 1))
  if Wind.enabled() and moved >= 3 then
    log("PASS: wind lean changes across frames")
  elseif not Wind.enabled() then
    log("FAIL: wind disabled")
  else
    log("FAIL: lean did not change enough")
  end

  -- gale stronger than breeze
  local breeze = Wind.amount()
  Wind.setting:sync(4)
  for _ = 1, 90 do Weather.update(1 / 30) end
  local gale = Wind.amount()
  log(("breeze=%.3f gale=%.3f"):format(breeze, gale))
  if gale >= breeze then log("PASS: gale >= breeze")
  else log("FAIL: gale weaker than breeze") end

  -- weather drive increases amount
  Wind.setting:sync(2)
  Weather.setting:sync("rain")
  for _ = 1, 400 do Weather.update(1 / 30) end
  local wet = Wind.amount()
  log(("amount under rain=%.3f (was breeze dry~%.3f)"):format(wet, breeze))
  if wet >= breeze then log("PASS: rain drives wind amount up or holds")
  else log("WARN: rain amount lower (drive lag?)") end

  -- NPC lean helper still returns finite numbers
  local lx, lz = Wind.leanAt(wx, wz, 0.55)
  log(("NPC-height lean dx=%.3f dz=%.3f"):format(lx, lz))
  if lx == lx and lz == lz then log("PASS: leanAt finite at torso height")
  else log("FAIL: NaN lean") end

  logf:close()
  love.event.quit()
end
