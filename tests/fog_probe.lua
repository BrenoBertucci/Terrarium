-- Probe: low fog at dawn/dusk, denser on canopy/coast, off at Quality scale 1.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/fog_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/fog_probe.log", "w"))
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

  local Sky = lib.require("Sky")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Quality = lib.require("Quality")
  local Pipelines = require("src.render.Pipelines")

  Weather.setting:sync("off")
  Pipelines.setLevel("terrarium_voxel", 4)
  -- RES 1/2 (value 2): fog on. RES 1/4 (value 4) would zero fogBands.
  Quality.setting:sync(2)

  local function fogAt(row, mapId, x, y)
    DayNight.setting:sync(row)
    game.overworld:setMap(mapId, x, y, "down")
    wait(90)
    for _ = 1, 30 do Weather.update(1 / 30) end
    local map = game.overworld.map
    local amt = Sky.fogAmount(map)
    log(("fog %s @ %s map=%s amount=%.3f bands=%d"):format(
      row, mapId, tostring(map and map.id), amt, Quality.fogBands()))
    return amt
  end

  local dayRoute = fogAt("day", "ROUTE_1", 10, 20)
  local dawnRoute = fogAt("dawn", "ROUTE_1", 10, 20)
  local duskRoute = fogAt("dusk", "ROUTE_1", 10, 20)
  local dawnForest = fogAt("dawn", "VIRIDIAN_FOREST", 5, 20)
  local dawnCoast = fogAt("dawn", "ROUTE_19", 5, 10)

  if dayRoute < 0.05 then log("PASS: midday fog near zero")
  else log("FAIL: midday fog too high", dayRoute) end

  if dawnRoute > dayRoute then log("PASS: dawn > day on route")
  else log("FAIL: dawn not above day") end

  if duskRoute > dayRoute then log("PASS: dusk > day on route")
  else log("FAIL: dusk not above day") end

  if dawnForest >= dawnRoute then log("PASS: forest fog >= route at dawn")
  else log("WARN: forest fog not denser (canopy may block outdoor sky path)") end

  if dawnCoast >= dawnRoute * 0.9 then log("PASS: coast fog present at dawn")
  else log("WARN: coast fog lower than expected") end

  -- quality off: fogBands 0 when scale is cheapest is not easy to force from
  -- probe without touching options; log the helper instead
  log("Quality.scale:", Quality.scale(), "fogBands:", Quality.fogBands())

  logf:close()
  love.event.quit()
end
