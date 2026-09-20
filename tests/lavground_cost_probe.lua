-- Why does a step cost more with the routes floored: work still going, or the collector?
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/lavground_cost.log", "w"))
  local function log(s) file:write(s, "\n"); file:flush() end
  for _ = 1, 1200 do
    if game.overworld and game.stack and game.stack:top() == game.overworld then break end
    if game.input then game.input.pressQueue[#game.input.pressQueue + 1] = "a" end
    coroutine.yield()
  end
  local lib = game.mods.exports.TERRARIUM.lib
  require("src.render.Pipelines").setLevel("terrarium_voxel", 4)
  lib.require("Weather").setting:sync("off")
  lib.require("AutoFarm").setting:sync("off")
  local function settle(n)
    for _ = 1, n do
      for _, d in ipairs({ "up", "down", "left", "right" }) do game.input.state[d] = false end
      game.input.pressQueue = {}
      coroutine.yield()
    end
  end
  game.overworld:setMap("LAVENDER_TOWN", 13, 14, "down")
  love.window.setVSync(0)
  for round = 1, 2 do
    settle(600)
    local t, sum = {}, 0
    for i = 1, 300 do
      local a = love.timer.getTime(); settle(1); t[i] = love.timer.getTime() - a; sum = sum + t[i]
    end
    table.sort(t)
    local a = love.timer.getTime(); collectgarbage(); local gc = love.timer.getTime() - a
    log(("round %d: mean %.2f median %.2f ms | heap %.0f MB, a full collect takes %.0f ms | step %s")
      :format(round, sum / 300 * 1000, t[150] * 1000, collectgarbage("count") / 1024, gc * 1000,
              tostring(lib.require("Buildings").progress and lib.require("Buildings").progress.step)))
  end
  lib.require("LavenderGroundKit").ENABLED = false
  lib.require("ChunkMesher").invalidate()
  game.overworld:setMap("LAVENDER_TOWN", 13, 14, "down")
  settle(2400)
  collectgarbage(); collectgarbage()
  log(("kit OFF: heap %.0f MB"):format(collectgarbage("count") / 1024))
  file:close(); love.event.quit()
end
