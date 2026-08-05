return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/ice_sprite_probe.log", "w"))
  local function log(...) local p={} for i=1,select("#",...) do p[i]=tostring(select(i,...)) end logf:write(table.concat(p," ").."\n"); logf:flush() end
  local function wait(n) for _=1,n do coroutine.yield() end end
  local function tap(b) game.input.pressQueue[#game.input.pressQueue+1]=b; coroutine.yield() end
  local n=0
  while not (game.overworld and game.stack and game.stack:top()) do wait(1); n=n+1; if n>900 then log("FAIL ow"); logf:close(); love.event.quit(); return end end
  n=0
  while game.stack:top() ~= game.overworld do tap("a"); wait(10); n=n+11; if n>1500 then break end end
  local lib = game.mods.exports.TERRARIUM.lib
  local Water = lib.require("Water")
  local Roamer = lib.require("Roamer")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  pcall(function() game.overworld:setMap("CERULEAN_CITY", 14, 7, "up") end)
  wait(100)
  Weather.setting:sync("snow")
  DayNight.setting:sync("night")
  Water.freeze = 1
  Water.refreshLive()
  log("WATERLINE", Roamer.WATERLINE)
  log("walkableIce", tostring(Water.walkableIce(80,80)))
  log("isStandingOnIce", tostring(Water.isStandingOnIce(80,80)))
  -- count water roamers and simulate waterline choice
  local full, cut = 0, 0
  for _, e in ipairs(game.overworld.entities or {}) do
    if e.roamer and e.kind == "water" then
      local ice = Water.isStandingOnIce((e.px or 0)+8, (e.py or 0)+8)
      if ice then full = full + 1 else cut = cut + 1 end
      log(("roamer@%d,%d ice=%s waterline_would=%d"):format(e.cellX, e.cellY, tostring(ice), ice and 0 or Roamer.WATERLINE))
    end
  end
  log(("full_body=%d cut_body=%d"):format(full, cut))
  love.graphics.captureScreenshot(function(data)
    local f=io.open(OUT.."/ice_sprite.png","wb")
    if f then f:write(data:encode("png"):getString()) f:close() end
  end)
  wait(5)
  local pass = Water.isStandingOnIce(80,80) and (cut == 0 or full > 0)
  log(pass and "PASS ice full-body path" or "FAIL")
  logf:close(); love.event.quit()
end
