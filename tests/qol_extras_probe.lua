-- Probe: the three QoL additions, each exercised through the engine rather
-- than asserted about.
--
--   RUN      movement.speed with B held vs not, on foot and on the bike
--   POISON   a poisoned mon at 1 HP walked past the damage step
--   TRADE    Evolution.pendingFor on a level-37 HAUNTER
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/qol_extras_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/qol_extras.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b
    coroutine.yield()
  end
  local fails = 0
  local function check(ok, what)
    log((ok and "  OK   " or "  FAIL ") .. what)
    if not ok then fails = fails + 1 end
  end

  local f = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); f = f + 1; if f > 900 then break end
  end
  f = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); f = f + 11; if f > 1500 then break end
  end

  local lib = game.mods.exports.TERRARIUM.lib
  local QoL = lib.require("QoL")
  QoL.setting:sync("on")

  -- ------- 1. RUN
  log("")
  log("== hold B to run ==")
  local input = game.input
  local function speed(bHeld, onBike, surfing)
    input.state = input.state or {}
    input.state.b = bHeld or nil
    return QoL.runSpeed(16, { input = input, onBike = onBike,
                              surfing = surfing })
  end
  local walk = speed(false, false, false)
  local run = speed(true, false, false)
  local bike = speed(true, true, false)
  local surf = speed(true, false, true)
  input.state.b = nil
  log(("  walking (B up)      %d frames/step"):format(walk))
  log(("  running (B held)    %d frames/step"):format(run))
  log(("  on the bike, B held %d frames/step"):format(bike))
  log(("  surfing, B held     %d frames/step"):format(surf))
  check(walk == 16, "B up leaves the walk alone")
  check(run == QoL.RUN_FRAMES and run < walk, "B held is faster than walking")
  check(bike == 16, "the bike is not slowed by this")
  check(surf == 16, "surfing keeps its own pace")

  QoL.setting:sync("off")
  local offRun = speed(true, false, false)
  input.state.b = nil
  QoL.setting:sync("on")
  log(("  QOL row OFF, B held %d frames/step"):format(offRun))
  check(offRun == 16, "the row switches running off")

  -- ------- 2. POISON
  log("")
  log("== field poison stops at 1 HP ==")
  local Pokemon = require("src.pokemon.Pokemon")
  local a = Pokemon.new(game.data, "RATTATA", 10)
  local b = Pokemon.new(game.data, "PIDGEY", 10)
  game.save.party = { a, b }
  a.status, a.hp = "PSN", 1        -- would die on the next tick
  b.status, b.hp = "PSN", 20       -- should still take its damage
  game.save.poisonSteps = 3        -- next step is the fourth
  local ow = game.overworld
  ow:applyFieldPoison()
  log(("  1 HP mon: hp=%d status=%s"):format(a.hp, tostring(a.status)))
  log(("  20 HP mon: hp=%d status=%s"):format(b.hp, tostring(b.status)))
  check(a.hp == 1, "the 1 HP mon survived")
  check(a.status == "PSN", "and is still poisoned (an Antidote is still owed)")
  check(b.hp == 19, "the healthy mon still took its damage")

  QoL.setting:sync("off")
  a.hp, a.status = 1, "PSN"
  game.save.poisonSteps = 3
  ow:applyFieldPoison()
  log(("  row OFF, 1 HP mon: hp=%d"):format(a.hp))
  check(a.hp == 0, "with the row OFF the 1996 rule is back")
  QoL.setting:sync("on")
  -- leave nothing fainted behind
  a.hp, a.status, b.status = 20, nil, nil

  -- ------- 3. TRADE EVOLUTIONS
  log("")
  log("== trade evolutions without a trade ==")
  local Evolution = require("src.pokemon.Evolution")
  local cases = { "HAUNTER", "KADABRA", "MACHOKE", "GRAVELER" }
  for _, species in ipairs(cases) do
    if game.data.pokemon[species] then
      local low = Pokemon.new(game.data, species, 20)
      local high = Pokemon.new(game.data, species, 37)
      local sLow = Evolution.pendingFor(game, low, { kind = "levelup" })
      local sHigh = Evolution.pendingFor(game, high, { kind = "levelup" })
      local sTrade = Evolution.pendingFor(game, low, { kind = "trade" })
      log(("  %-9s lv20=%-10s lv37=%-10s trade@20=%s"):format(
        species, tostring(sLow), tostring(sHigh), tostring(sTrade)))
      check(sHigh ~= nil, species .. " evolves at level 37")
      check(sLow == nil, species .. " does NOT evolve below 37")
      check(sTrade ~= nil, species .. " still evolves on a real trade")
    end
  end

  QoL.setting:sync("off")
  local off = Evolution.pendingFor(game,
    Pokemon.new(game.data, "HAUNTER", 40), { kind = "levelup" })
  log(("  row OFF, HAUNTER lv40 = %s"):format(tostring(off)))
  check(off == nil, "the row switches trade evolutions off")
  QoL.setting:sync("on")

  log("")
  log(fails == 0 and "ALL CHECKS PASSED" or (fails .. " CHECK(S) FAILED"))
  logf:close()
  love.event.quit()
end
