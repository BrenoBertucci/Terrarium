-- Probe: water roamers visible on foot + swell surface + waterline/wind APIs.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/water_roam_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/water_roam_probe.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
    logf:write(table.concat(p, " ") .. "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL no ow"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end
  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then log("FAIL no lib"); logf:close(); love.event.quit(); return end
  log("version", exports.TERRARIUM.version)

  local Water = lib.require("Water")
  local Wind = lib.require("Wind")
  local Roamer = lib.require("Roamer")
  local WildRoamers = lib.require("WildRoamers")
  WildRoamers.setting:sync("roam")
  Wind.setting:sync(2)   -- BREEZE so leanAt is non-zero
  if game.overworld.player then game.overworld.player.surfing = false end

  log(("WATERLINE=%s  WIND_HEIGHT=%s  Wind.amount=%s")
      :format(tostring(Roamer.WATERLINE), tostring(Roamer.WIND_HEIGHT),
              tostring(Wind.amount())))
  local lx, lz = Wind.leanAt(80, 80, Roamer.WIND_HEIGHT)
  log(("Wind.leanAt(80,80,%.2f) = %.3f, %.3f"):format(Roamer.WIND_HEIGHT, lx, lz))
  log(("Water.surfaceAt(80,80) = %.3f  heightAt = %.3f")
      :format(Water.surfaceAt(80, 80), Water.heightAt(80, 80)))

  local maps = {
    { "VERMILION_CITY", 6, 12 },
    { "ROUTE_12", 4, 10 },
    { "ROUTE_21", 4, 24 },
    { "CERULEAN_CITY", 14, 7 },
    { "ROUTE_6", 2, 29 },
  }
  for _, m in ipairs(maps) do
    local id, x, y = m[1], m[2], m[3]
    local ok = pcall(function() game.overworld:setMap(id, x, y, "up") end)
    if not ok then log(id, "setMap fail"); goto cont end
    if game.overworld.player then game.overworld.player.surfing = false end
    wait(200)
    local grass, water, other = 0, 0, 0
    for _, e in ipairs(game.overworld.entities or {}) do
      if e.roamer then
        if e.kind == "water" then water = water + 1
        elseif e.kind == "grass" then grass = grass + 1
        else other = other + 1 end
      end
    end
    log(("%-16s @%d,%d grass=%d water=%d other=%d surfing=%s")
        :format(id, x, y, grass, water, other,
                tostring(game.overworld.player.surfing)))
    ::cont::
  end
  log("done")
  logf:close()
  love.event.quit()
end
