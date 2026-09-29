-- Probe: what the ANIME sheet and the ripple field COST, frame time with
-- VSYNC OFF (a cost probe that leaves it on measures 16.7 ms for everything,
-- see the note in tests/mali_cost_probe.lua).
--
-- Surfing in the Route 21 channel -- the water roamers there keep the field
-- awake on their own, which is the realistic case -- at RES 1/2, SCREEN FX
-- rt, weather off, hour pinned. Three conditions, walked as a palindrome so
-- warm-up and heat land on both ends:
--   OFF      CLASSIC sheet, the field switched off (the build before this)
--   ANIME    ANIME sheet + the field
--   CLASSIC  CLASSIC sheet + the field
-- order OFF ANIME CLASSIC CLASSIC ANIME OFF; median and p95 per block.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> POKEPORT_SPEED=1 \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/ripple_cost_probe.lua ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/ripple_cost_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local function finish(msg)
    if msg then log(msg) end
    logf:close()
    love.event.quit()
  end
  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then return finish("FAIL: no overworld") end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end
  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then return finish("FAIL: TERRARIUM not loaded") end

  local Water = lib.require("Water")
  local RayFX = lib.require("RayFX")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Wind = lib.require("Wind")
  local Quality = lib.require("Quality")
  local Voxel3D = lib.require("Voxel3D")
  local Ripples = lib.require("Ripples")
  local Pipelines = require("src.render.Pipelines")
  local function sync(setting, v) if setting then pcall(setting.sync, setting, v) end end
  sync(Weather.setting, "off")
  sync(DayNight.setting, "day")
  sync(Wind.setting, 2)
  sync(Quality.setting, 2)
  sync(RayFX.setting, "rt")
  sync(Water.setting, 0.8)
  pcall(Pipelines.setLevel, "terrarium_voxel", 4)
  pcall(love.window.setVSync, 0)
  log("vsync:", tostring(love.window.getVSync and love.window.getVSync()))

  local p = game.overworld.player
  p.surfing = true
  pcall(function() game.overworld:setMap("ROUTE_21", 8, 14, "down") end)
  p.surfing = true
  Voxel3D.lampLights = nil
  for _ = 1, 900 do if Voxel3D.lampLights ~= nil then break end coroutine.yield() end
  -- the neighbours' chunk meshes keep building for seconds after a setMap
  -- (p95 of 470-730 ms in the first run's opening cycles): wait them out
  wait(1200)

  local realUpdate, realLive = Ripples.update, Ripples.live
  local function set(cond)
    if cond == "OFF" then
      Ripples.update = function() end
      Ripples.live = function() return false end
      sync(Water.style, "classic")
    else
      Ripples.update, Ripples.live = realUpdate, realLive
      sync(Water.style, cond == "ANIME" and "anime" or "classic")
    end
  end
  local function block(cond, frames)
    set(cond)
    wait(45)                      -- variant compiled, field awake again
    local t = {}
    local last = love.timer.getTime()
    for i = 1, frames do
      coroutine.yield()
      local now = love.timer.getTime()
      t[i] = (now - last) * 1000
      last = now
    end
    table.sort(t)
    return t[math.floor(frames / 2)], t[math.floor(frames * 0.95)]
  end
  -- Six cycles, the order rotated each time, each condition's median read
  -- against the OFF median OF THE SAME CYCLE: the machine drifts by more than
  -- the effect over a minute, and a paired difference cancels the drift.
  local ORDERS = { { "OFF", "ANIME", "CLASSIC" }, { "ANIME", "CLASSIC", "OFF" },
                   { "CLASSIC", "OFF", "ANIME" } }
  local dA, dC, med = {}, {}, { OFF = {}, ANIME = {}, CLASSIC = {} }
  for cyc = 1, 9 do
    local m = {}
    for _, c in ipairs(ORDERS[(cyc - 1) % 3 + 1]) do
      local md, p95 = block(c, 150)
      m[c] = md
      med[c][#med[c] + 1] = md
      log(("cycle %d %-8s median %.2f  p95 %.2f"):format(cyc, c, md, p95))
    end
    dA[#dA + 1] = m.ANIME - m.OFF
    dC[#dC + 1] = m.CLASSIC - m.OFF
  end
  local function stats(t)
    local sum = 0
    for _, v in ipairs(t) do sum = sum + v end
    local mean = sum / #t
    local var = 0
    for _, v in ipairs(t) do var = var + (v - mean) ^ 2 end
    return mean, math.sqrt(var / (#t - 1)) / math.sqrt(#t)
  end
  local ma, sa = stats(dA)
  local mc, sc = stats(dC)
  local mo = stats(med.OFF)
  log(("OFF median mean %.2f ms"):format(mo))
  log(("ANIME   - OFF: %+.2f ms +- %.2f (s.e., 9 paired cycles)"):format(ma, sa))
  log(("CLASSIC - OFF: %+.2f ms +- %.2f (the field alone)"):format(mc, sc))
  set("ANIME")
  finish("done")
end
