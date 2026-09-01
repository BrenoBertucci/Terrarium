-- Probe: battle-menu dpad walks the costume, not the Game Boy grid.
--
-- Graphs first (no fight needed): command cluster, move fan, party 2x3.
-- Then a live wild battle, if one will start, to confirm Down from FIGHT
-- lands on RUN (4) rather than BAG (3) -- the bug BattleBoxXY measured.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/battle_nav_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/battle_nav.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

  local fail = 0
  local function expect(got, want, tag)
    if got == want then
      log("PASS", tag, got)
    else
      fail = fail + 1
      log("FAIL", tag, "got=" .. tostring(got), "want=" .. tostring(want))
    end
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit()
      return end
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
  local Nav = lib.require("BattleNav")
  if not Nav then
    log("FAIL: BattleNav missing"); logf:close(); love.event.quit(); return
  end

  -- ------- command cluster (FIGHT above BAG RUN PKMN)
  -- 1 FIGHT: down/up -> 4 RUN, left -> 3 BAG, right -> 2 PKMN
  expect(Nav.commandNext(1, "down"), 4, "cmd 1 down")
  expect(Nav.commandNext(1, "up"), 4, "cmd 1 up")
  expect(Nav.commandNext(1, "left"), 3, "cmd 1 left")
  expect(Nav.commandNext(1, "right"), 2, "cmd 1 right")
  -- 3 BAG: left wraps to PKMN, right to RUN, up/down to FIGHT
  expect(Nav.commandNext(3, "left"), 2, "cmd 3 left wrap")
  expect(Nav.commandNext(3, "right"), 4, "cmd 3 right")
  expect(Nav.commandNext(3, "up"), 1, "cmd 3 up")
  expect(Nav.commandNext(3, "down"), 1, "cmd 3 down")
  -- 4 RUN
  expect(Nav.commandNext(4, "left"), 3, "cmd 4 left")
  expect(Nav.commandNext(4, "right"), 2, "cmd 4 right")
  expect(Nav.commandNext(4, "up"), 1, "cmd 4 up")
  expect(Nav.commandNext(4, "down"), 1, "cmd 4 down")
  -- 2 PKMN: right wraps to BAG
  expect(Nav.commandNext(2, "left"), 4, "cmd 2 left")
  expect(Nav.commandNext(2, "right"), 3, "cmd 2 right wrap")
  expect(Nav.commandNext(2, "up"), 1, "cmd 2 up")
  expect(Nav.commandNext(2, "down"), 1, "cmd 2 down")

  -- engine 2x2 (the bug): down from FIGHT used to be 3
  if Nav.commandNext(1, "down") == 3 then
    fail = fail + 1
    log("FAIL cmd still GB 2x2 (1 down -> 3)")
  end

  -- ------- move fan: wrap, skip disabled
  expect(Nav.moveNext(1, "right", 4), 2, "move 1 right")
  expect(Nav.moveNext(4, "right", 4), 1, "move 4 right wrap")
  expect(Nav.moveNext(1, "left", 4), 4, "move 1 left wrap")
  expect(Nav.moveNext(2, "up", 4), 1, "move 2 up")
  expect(Nav.moveNext(1, "down", 4), 2, "move 1 down")
  expect(Nav.moveNext(1, "right", 4, 2), 3, "move skip disabled 2")
  expect(Nav.moveNext(3, "left", 4, 2), 1, "move skip disabled 2 left")
  expect(Nav.moveNext(4, "right", 1), 1, "move n=1 stays")

  -- ------- party 2x3
  -- 1 2
  -- 3 4
  -- 5 6
  expect(Nav.partyNext(1, "right", 6), 2, "party 1 right")
  expect(Nav.partyNext(1, "left", 6), 2, "party 1 left wrap-row")
  expect(Nav.partyNext(2, "left", 6), 1, "party 2 left")
  expect(Nav.partyNext(2, "right", 6), 1, "party 2 right wrap-row")
  expect(Nav.partyNext(1, "down", 6), 3, "party 1 down")
  expect(Nav.partyNext(3, "down", 6), 5, "party 3 down")
  expect(Nav.partyNext(5, "down", 6), 6, "party 5 down clamp to n")
  -- 5 down is +2 = 7 clamp to 6 (user: clamp to n)
  expect(Nav.partyNext(2, "down", 6), 4, "party 2 down")
  expect(Nav.partyNext(4, "down", 6), 6, "party 4 down")
  expect(Nav.partyNext(1, "up", 6), 1, "party 1 up clamp")
  expect(Nav.partyNext(5, "up", 6), 3, "party 5 up")
  -- n=5: slot 5 is alone on row 3; left/right stay
  expect(Nav.partyNext(5, "right", 5), 5, "party 5 right n=5 stay")
  expect(Nav.partyNext(5, "left", 5), 5, "party 5 left n=5 stay")
  expect(Nav.partyNext(4, "down", 5), 5, "party 4 down n=5 clamp")
  expect(Nav.partyNext(1, "right", 1), 1, "party n=1 stay")

  if type(Nav.pin) ~= "function" then
    fail = fail + 1
    log("FAIL BattleNav.pin missing")
  else
    log("PASS BattleNav.pin present")
  end
  local hopTime = tonumber(Nav.HOP_TIME) or 0
  if hopTime < 0.18 or hopTime > 0.30 then
    fail = fail + 1
    log("FAIL HOP_TIME", hopTime)
  else
    log("PASS HOP_TIME", hopTime)
  end

  log("graph fails:", fail)

  -- ------- live: Down from FIGHT must land on RUN
  local BattleState = require("src.battle.BattleState")
  local ok, battle = pcall(BattleState.newWild, game, "RATTATA", 9)
  if not (ok and battle) or battle.dead then
    log("SKIP live: no battle", tostring(battle))
    log(fail == 0 and "PASS graphs only" or "FAIL graphs")
    logf:close(); love.event.quit(); return
  end
  game.overworld:pushBattle(battle)

  local function waitPhase(want, cap)
    for _ = 1, (cap or 400) do
      if battle.phase == want then return true end
      coroutine.yield()
    end
    return false
  end
  local function press(b, want, cap)
    for _ = 1, 30 do
      if battle.phase == want then return true end
      tap(b); wait(12)
      if waitPhase(want, cap or 60) then return true end
    end
    return battle.phase == want
  end

  if not press("a", "menu") then
    log("SKIP live: no command menu phase=" .. tostring(battle.phase))
    log(fail == 0 and "PASS graphs only" or "FAIL graphs")
    logf:close(); love.event.quit(); return
  end
  wait(20)
  battle.menuIndex = 1
  wait(8)
  log("live menuIndex before down:", battle.menuIndex)
  tap("down"); wait(18)
  log("live menuIndex after down:", battle.menuIndex)
  expect(battle.menuIndex, 4, "live FIGHT down -> RUN")
  -- engine clobber: BattleState assigns menuIndex from the OLD col/row
  -- after swallowing the dpad. pin must put RUN back.
  if type(Nav.pin) == "function" then
    battle.menuIndex = 1
    Nav.pin()
    expect(battle.menuIndex, 4, "pin restores RUN after clobber")
    local dbg = Nav.debug and Nav.debug()
    log("held", dbg and dbg.held and dbg.held.kind, dbg and dbg.held and dbg.held.index)
  end
  tap("right"); wait(18)
  expect(battle.menuIndex, 2, "live RUN right -> PKMN")
  tap("right"); wait(18)
  expect(battle.menuIndex, 3, "live PKMN right wrap -> BAG")

  -- hop should have been recorded at some point (Poke Ball arc, not a laser)
  local hop = Nav.hop
  log("hop kind=", hop and hop.kind or "nil",
      "from=", hop and hop.from, "to=", hop and hop.to)
  if hop and (hop.laser or hop.sparkles) then
    fail = fail + 1
    log("FAIL hop still looks like a laser")
  end

  if fail == 0 then log("PASS") else log("FAIL count=" .. fail) end
  logf:close()
  love.event.quit()
end
