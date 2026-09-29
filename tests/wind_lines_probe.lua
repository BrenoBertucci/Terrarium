-- Probe: the wind you can see, after the sheets that read as gas were taken
-- out (lib/WindFX.lua header, lib/WindLines.lua). In the real game, a Route 1
-- meadow, camera rung 4.
--
--   G1 NO GAS     the wind's own motes are leaves (and a gale's debris), in every
--                 frame, in breeze, gale and rain
--   G2 DRAWN      lines are up and actually reach the canvas in a gale
--   G3 FRONTS     gust fronts fire and each one sends its rank of lines
--   G4 MORE       a gale keeps more lines up than a breeze
-- and the shots a person judges: wind_breeze / wind_gale / wind_front /
-- wind_rain / wind_dusk.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> POKEPORT_SPEED=1 \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/wind_lines_probe.lua ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local MAP = os.getenv("DS_MAP") or "ROUTE_1"
  local AT_X = tonumber(os.getenv("DS_X") or "9")
  local AT_Y = tonumber(os.getenv("DS_Y") or "24")
  local logf = assert(io.open(OUT .. "/wind_lines_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local fails = 0
  local function check(ok, what)
    log((ok and "PASS  " or "FAIL  ") .. what)
    if not ok then fails = fails + 1 end
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
    log("shot", name, done and "ok" or "TIMEOUT")
  end
  local function finish()
    log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
    logf:close()
    love.event.quit()
  end
  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") return finish() end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end
  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then log("FAIL: TERRARIUM not loaded") return finish() end

  local WindFX = lib.require("WindFX")
  local WindLines = lib.require("WindLines")
  local Wind = lib.require("Wind")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Voxel3D = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")
  local function sync(s, v) if s then pcall(s.sync, s, v) end end
  sync(Weather.setting, "off")
  sync(DayNight.setting, "day")
  pcall(Pipelines.setLevel, "terrarium_voxel", 4)
  pcall(function() game.overworld:setMap(MAP, AT_X, AT_Y, "up") end)
  Voxel3D.lampLights = nil
  for _ = 1, 900 do if Voxel3D.lampLights ~= nil then break end coroutine.yield() end
  wait(120)

  -- what the strokes cost: update + scene-pass draw, per call
  local cost = { u = 0, d = 0, nu = 0, nd = 0, du = 0, dd = 0 }
  do
    local up, dw = WindLines.update, WindLines.drawWorld
    WindLines.update = function(...)
      local t0 = love.timer.getTime(); up(...)
      local dt = love.timer.getTime() - t0
      cost.u = cost.u + dt; cost.nu = cost.nu + 1; if dt > cost.du then cost.du = dt end
    end
    WindLines.drawWorld = function(...)
      local t0 = love.timer.getTime(); local r = dw(...)
      local dt = love.timer.getTime() - t0
      cost.d = cost.d + dt; cost.nd = cost.nd + 1; if dt > cost.dd then cost.dd = dt end
      return r
    end
  end
  local gas = {}
  -- watch `frames` frames: the field's own kinds, the lines up, and whether
  -- any of them reached the canvas
  local function watch(tag, frames)
    local sum, drawnFrames, maxLines = 0, 0, 0
    for _ = 1, frames do
      coroutine.yield()
      for i = 1, WindFX.count() do
        local m = WindFX.get(i)
        if m and not m.veg and not m.src and m.kind ~= "leaf" and m.kind ~= "debris" then
          gas[m.kind] = (gas[m.kind] or 0) + 1
        end
      end
      local c = WindLines.count()
      sum = sum + c
      if c > maxLines then maxLines = c end
      if WindLines.drawn > 0 then drawnFrames = drawnFrames + 1 end
    end
    local mean = sum / frames
    local sky = select(1, Weather.visible())
    log(("%-6s lines mean %.1f max %d, drawn in %d of %d frames, fronts %d, gate %s, sky %s, amount %.2f"):format(
      tag, mean, maxLines, drawnFrames, frames, WindLines.fronts, tostring(WindFX.lastGate),
      tostring(sky), tonumber(Wind.amount()) or -1))
    return mean, drawnFrames
  end

  sync(Wind.setting, 2)                  -- BREEZE
  wait(420)
  local breeze = watch("breeze", 600)
  shot("wind_breeze.png")

  sync(Wind.setting, 4)                  -- GALE
  wait(420)
  local f0 = WindLines.fronts
  local gale, galeDrawn = watch("gale", 900)
  shot("wind_gale.png")
  for i = 1, 3 do wait(50); shot(("wind_gale_%d.png"):format(i)) end
  -- a swirl round a crown, shot as it winds
  local sw0 = WindLines.swirls or 0
  for _ = 1, 1200 do
    coroutine.yield()
    if (WindLines.swirls or 0) > sw0 then break end
  end
  wait(40)
  shot("wind_swirl.png")
  log("swirls so far:", tostring(WindLines.swirls))
  log(("cost in the gale: update %.3f ms avg (%.3f max), draw %.3f ms avg (%.3f max)"):format(
    cost.u / math.max(1, cost.nu) * 1000, cost.du * 1000,
    cost.d / math.max(1, cost.nd) * 1000, cost.dd * 1000))
  -- a strip of film for the motion: a frame every 3 updates
  if os.getenv("DS_FILM") then
    for i = 1, 40 do wait(3); shot(("film_%02d.png"):format(i)) end
  end
  -- a front, shot as it crosses
  local fStart = WindLines.fronts
  for _ = 1, 900 do
    coroutine.yield()
    if WindLines.fronts > fStart then break end
  end
  wait(35)
  shot("wind_front.png")
  local fronts = WindLines.fronts - f0

  sync(Weather.setting, "rain")
  wait(600)
  watch("rain", 600)
  shot("wind_rain.png")
  sync(Weather.setting, "off")

  sync(DayNight.setting, "dusk")
  wait(420)
  shot("wind_dusk.png")
  sync(DayNight.setting, "day")

  local gasList = {}
  for k, c in pairs(gas) do gasList[#gasList + 1] = k .. "=" .. c end
  check(#gasList == 0, "G1 NO GAS: the wind's own motes are leaves only"
        .. (#gasList > 0 and (" (" .. table.concat(gasList, " ") .. ")") or ""))
  check(galeDrawn > 300, "G2 DRAWN: lines reach the canvas in a gale")
  check(fronts > 0, "G3 FRONTS: gust fronts send their rank (" .. fronts .. ")")
  check(gale > breeze * 1.5, ("G4 MORE: gale %.1f lines against breeze %.1f"):format(gale, breeze))
  check(WindLines.lastError == nil, "G5 NO THROW: " .. tostring(WindLines.lastError))
  check((WindFX.carried or 0) > 0, "G6 CARRY: strokes caught leaves (" .. tostring(WindFX.carried) .. ")")
  finish()
end
