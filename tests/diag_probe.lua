-- Does the DIAG panel render, and does it say anything worth sending?
--
-- The panel exists so a bug report from a phone can be a screenshot instead
-- of a guess, which means the only thing that matters about it is that it
-- comes up and is legible.  So this turns the row on, stands in three places
-- (a town with a kit on it, a shop interior, a route) and photographs it.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/diag_probe.lua gen1recomp

return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/diag_probe.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
    logf:write(table.concat(p, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end

  local Diag        = lib.require("Diag")
  local DayNight    = lib.require("DayNight")
  local Weather     = lib.require("Weather")
  local ChunkMesher = lib.require("ChunkMesher")
  local Pipelines   = require("src.render.Pipelines")

  Pipelines.setLevel("terrarium_voxel", 3)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  Weather.setting:sync("off")
  DayNight.setting:sync("day")
  Diag.setting:sync("on")

  local function hold(f) for _ = 1, f do DayNight.clock = 300; coroutine.yield() end end

  -- the panel's own text, before anything is drawn: if a line here is "?" or
  -- "LOAD FAILED" the panel is doing its job and the mod is not
  log("== what the panel would say, on this machine ==")
  for _, l in ipairs(Diag.lines()) do log("  " .. l) end
  log("")

  for _, s in ipairs({
    { "lavender", "LAVENDER_TOWN", 10, 10, "down" },
    { "mart",     "VIRIDIAN_MART",  4,  6, "up" },
    { "route",    "ROUTE_1",        8, 12, "up" },
  }) do
    if pcall(function() game.overworld:setMap(s[2], s[3], s[4], s[5]) end) then
      local quiet, guard = 0, 0
      while quiet < 30 and guard < 1800 do
        hold(1); guard = guard + 1
        local okP, p = pcall(ChunkMesher.pending)
        if okP and (tonumber(p) or 1) == 0 then quiet = quiet + 1 else quiet = 0 end
      end
      pcall(function() game.overworld:setMap(s[2], s[3], s[4], s[5]) end)
      hold(60)
      local shot, got = nil, false
      love.graphics.captureScreenshot(function(img) shot = img; got = true end)
      local g2 = 0
      while not got and g2 < 240 do hold(1); g2 = g2 + 1 end
      if shot then
        shot:encode("png", "diag_" .. s[1] .. ".png")
        log("SHOT " .. s[1])
      else
        log("FAIL " .. s[1] .. " no screenshot")
      end
      log("  " .. (Diag.lines()[#Diag.lines()] or "?"))
    end
  end

  Diag.setting:sync("off")
  log("done")
  logf:close()
  love.event.quit()
end
