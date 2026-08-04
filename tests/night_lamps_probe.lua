return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/night_lamps_probe.log", "w"))
  local function log(...) local p={} for i=1,select("#",...) do p[i]=tostring(select(i,...)) end logf:write(table.concat(p," ").."\n") logf:flush() end
  local function wait(n) for _=1,n do coroutine.yield() end end
  local function tap(b) game.input.pressQueue[#game.input.pressQueue+1]=b; coroutine.yield() end
  local n=0
  while not (game.overworld and game.stack and game.stack:top()) do wait(1); n=n+1; if n>900 then log("FAIL"); logf:close(); love.event.quit(); return end end
  n=0
  while game.stack:top() ~= game.overworld do tap("a"); wait(10); n=n+11; if n>1500 then break end end
  local lib = game.mods.exports.DRAMATIC_SHAPE.lib
  local DayNight = lib.require("DayNight")
  local StreetLamps = lib.require("StreetLamps")
  DayNight.setting:sync("night")
  DayNight.darkSetting:sync("deep")
  StreetLamps.setting:sync(true)
  wait(20)
  local t = DayNight.tint(true)
  log(string.format("DEEP night tint: %.3f %.3f %.3f", t[1], t[2], t[3]))
  DayNight.darkSetting:sync("soft"); wait(2)
  local t2 = DayNight.tint(true)
  log(string.format("SOFT night tint: %.3f %.3f %.3f", t2[1], t2[2], t2[3]))
  DayNight.darkSetting:sync("deep")
  local maps = {"VIRIDIAN_CITY","PEWTER_CITY","CERULEAN_CITY","VERMILION_CITY","LAVENDER_TOWN","CELADON_CITY","SAFFRON_CITY","FUCHSIA_CITY","CINNABAR_ISLAND"}
  for _,id in ipairs(maps) do
    local ok = pcall(function() game.overworld:setMap(id, 10, 10, "up") end)
    if not ok then log(id, "setMap fail"); goto cont end
    wait(80)
    StreetLamps.invalidate()
    local c = StreetLamps.count(game.overworld.map)
    log(string.format("%-18s lamps=%d w=%s h=%s", id, c, tostring(game.overworld.map.widthCells), tostring(game.overworld.map.heightCells)))
    ::cont::
  end
  pcall(function() game.overworld:setMap("ROUTE_1", 10, 10, "up") end)
  wait(50); StreetLamps.invalidate()
  log(string.format("ROUTE_1 lamps=%d (want 0)", StreetLamps.count(game.overworld.map)))
  log("done"); logf:close(); love.event.quit()
end
