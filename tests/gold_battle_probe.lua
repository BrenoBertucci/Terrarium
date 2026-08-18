-- Probe: TERRARIUM's overworld battle on Gold -- does a wild fight stage
-- on the map (the mod's flagship), fall back to the vanilla screen, or
-- error?
--
--   POKEPORT_VERSION=gold DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/gold_battle_probe.lua gen1recomp
--
-- The save has no starter yet, so the probe hands the party a Cyndaquil
-- (in memory only -- the driver never saves), warps to Route 29 grass,
-- and starts a wild battle through the world's own front door.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/gold_battle.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local rawprint = print
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write("[print] ", table.concat(parts, "\t"), "\n"); logf:flush()
    rawprint(...)
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end

  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      pcall(function()
        local fd = data:encode("png")
        local f = assert(io.open(OUT .. "/" .. name, "wb"))
        f:write(fd:getString()); f:close()
      end)
      done = true
    end)
    local n = 0
    while not done and n < 120 do wait(1); n = n + 1 end
    log("shot", name, done and "ok" or "TIMEOUT")
  end

  local n = 0
  while not (game.world and game.world.map) do
    wait(1); n = n + 1
    if n > 3600 then log("FAIL: no world"); logf:close(); love.event.quit(); return end
  end

  -- a party, so the fight has a send-out
  local okM, err = pcall(function()
    local Mon = require("src.battle.gen2.Mon")
    local mon = assert(Mon.new(game.data, "CYNDAQUIL", 12), "Mon.new nil")
    game.save.party = { mon }
  end)
  log("party:", okM and "ok" or ("FAIL " .. tostring(err)))

  pcall(function() game.world:setMap("ROUTE_29", 10, 10, "down") end)
  wait(60)

  local Pipelines = require("src.render.Pipelines")
  Pipelines.setLevel("terrarium_voxel", 5)
  -- let the meshes build so the arena has ground to stage on
  wait(600)
  shot("route29_voxel.png")

  -- the world's own wild-battle front door
  local okB, errB = pcall(function()
    local Mon = require("src.battle.gen2.Mon")
    local wild = assert(Mon.new(game.data, "PIDGEY", 3), "wild nil")
    game.world:startBattle({ wild = wild })
  end)
  log("startBattle:", okB and "ok" or ("FAIL " .. tostring(errB)))

  -- watch the fight arrive: shots along the way
  wait(120); shot("battle_1.png")
  wait(240); shot("battle_2.png")

  -- press through a few prompts so the intro settles
  local input = game.input
  if input and input.pressQueue then
    for _ = 1, 6 do
      input.pressQueue[#input.pressQueue + 1] = "a"
      wait(40)
    end
  end
  shot("battle_3.png")

  log("done")
  logf:close()
  _G.print = rawprint
  love.event.quit()
end
