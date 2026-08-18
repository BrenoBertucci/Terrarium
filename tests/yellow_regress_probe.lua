-- Probe: Yellow regression sweep after the Gold seams.  The Gen 2 work
-- touched shared files (VoxelScene groundAt/flatTop, TileShape.at,
-- TerrainAtlas, Structures doors, BattleScene palette, OverworldBattle);
-- this walks the same ground the Gold probes walked, on Yellow, and
-- screenshots the voxel pass plus a staged battle.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/yellow_regress_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/yellow_regress.log", "w"))
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
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

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
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 3600 then log("FAIL: no overworld"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end
  log("free roam on", tostring(game.overworld.map and game.overworld.map.id))

  local Pipelines = require("src.render.Pipelines")
  game.overworld:setMap("PALLET_TOWN", 12, 12, "down")
  wait(60)
  Pipelines.setLevel("terrarium_voxel", 5)
  wait(600)
  shot("yellow_voxel.png")

  -- a staged wild battle, the way the mod stages it on Yellow
  local okB, errB = pcall(function()
    local BattleState = require("src.battle.BattleState")
    local battle = BattleState.newWild(game, "PIDGEY", 5)
    game.overworld:pushBattle(battle)
  end)
  log("pushBattle:", okB and "ok" or ("FAIL " .. tostring(errB)))
  wait(240)
  shot("yellow_battle.png")
  for _ = 1, 4 do
    game.input.pressQueue[#game.input.pressQueue + 1] = "a"
    wait(40)
  end
  shot("yellow_battle2.png")

  log("done")
  logf:close()
  _G.print = rawprint
  love.event.quit()
end
