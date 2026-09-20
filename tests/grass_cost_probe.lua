-- Probe: what one BUILD's grass costs, standing in a big meadow in a gale.
--
-- Not an A/B inside a run -- a shader change cannot be switched off without
-- compiling the other shader -- so it is run once per build, old and new
-- alternated (old, new, new, old), and the builds compared on the median.
-- Standing still, so chunk meshing is not in the sample; VSync off, so the
-- number is the frame and not the monitor.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/grass_cost_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/grass_cost_probe.log", "a"))
  local function log(s) logf:write(s, "\n"); logf:flush() end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local frames = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); frames = frames + 1
    if frames > 900 then log("FAIL: no overworld"); logf:close(); love.event.quit(); return end
  end
  while game.stack:top() ~= game.overworld do
    game.input.pressQueue[#game.input.pressQueue + 1] = "a"; wait(11)
  end
  local lib = game.mods.exports.TERRARIUM.lib
  local Quality = lib.require("Quality")
  local Wind = lib.require("Wind")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Pipelines = require("src.render.Pipelines")
  lib.require("WildRoamers").covers = function() return true end
  DayNight.setting:sync("day")
  Weather.setting:sync("off")
  Wind.setting:sync(4)
  Pipelines.setLevel("terrarium_voxel", 4)
  Quality.setting:sync(1)                 -- FULL -> grassDetail 2
  game.overworld:setMap("ROUTE_2", 3, 6, "down")
  local p, stay, cx, cy = nil, 0, -1, -1
  for _ = 1, 900 do
    for _, d in ipairs({ "up", "down", "left", "right" }) do
      game.input.state[d] = false
    end
    coroutine.yield()
    p = game.overworld.player
    if p.cellX == cx and p.cellY == cy then stay = stay + 1
    else stay, cx, cy = 0, p.cellX, p.cellY end
    if stay >= 45 then break end
  end
  love.window.setVSync(0)
  wait(200)
  local t = {}
  for _ = 1, 600 do
    local a = love.timer.getTime()
    coroutine.yield()
    t[#t + 1] = love.timer.getTime() - a
  end
  love.window.setVSync(1)
  table.sort(t)
  log(("%s  median %.3f ms  p90 %.3f ms  cell (%d,%d) grassDetail %s")
        :format(os.getenv("GRASS_BUILD") or "?", t[301] * 1000,
                t[540] * 1000, cx, cy, tostring(Quality.grassDetail())))
  logf:close()
  love.event.quit()
end
