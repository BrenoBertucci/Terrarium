-- Probe: does the parry actually defer the turn, and actually cut the blow?
--
-- The arithmetic is checked without a game (tests/battleparry_offline.lua, via
-- tools/run_battleparry_offline.py). What only a live fight can answer is the
-- part that touches the engine:
--
--   1. DEFERRED. When the foe swings, its turn does NOT resolve that frame --
--      a window opens and the queue holds with frames still on the clock.
--   2. NAMED. The window knows which move is coming, which is only true
--      because the trainer-AI swap is resolved before the deferral rather
--      than inside it.
--   3. CHEAPER. The same fight, same seed, same move: a perfect press takes
--      less HP off the player than no press at all.
--   4. HONEST. The parry changes the PLAYER's loss and nothing else -- the
--      foe's HP is untouched by it.
--
-- The A/B is two battles in one run with the same stubbed RNG, so the only
-- difference between them is the press. A fixed generator and not a pinned
-- return value: the engine asks the same rng for the crit roll, the accuracy
-- roll and the damage spread, and a stub that answers one extreme makes every
-- move a critical or every move a miss.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/battleparry_probe.lua \
--   ./gen1recomp.exe --console
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/battleparry.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  -- callback-waited, never yield-counted: a shot scheduled and then yielded
  -- past photographs the state AFTER the one being measured (this repo has
  -- paid for that lesson more than once)
  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      done = true
    end)
    for _ = 1, 90 do
      if done then return end
      coroutine.yield()
    end
    log("WARN: screenshot " .. name .. " never called back")
  end

  local fails, checks = 0, 0
  local function verdict(okv, name, detail)
    checks = checks + 1
    if not okv then fails = fails + 1 end
    log((okv and "PASS: " or "FAIL: ") .. name .. "  " .. (detail or ""))
  end
  local function bail(why)
    log("FAIL: " .. why)
    logf:close(); love.event.quit()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then return bail("no overworld") end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("WARN: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then return bail("TERRARIUM not loaded") end
  local Parry = lib.require("BattleParry")
  local Charge = lib.require("BattleCharge")
  local Dyn = lib.require("BattleDynamic")
  Dyn.setting:sync("dynamic"); Dyn.apply()
  Parry.setting:sync("on")
  -- CHARGE ON, as it is played: the parried round's press has to be PAID for
  -- (a fresh fight starts at START, which covers one PARRY_COST), so this also
  -- proves the fuel path live and not just in tests/battleparry_offline.lua
  Charge.setting:sync("on")

  local BattleState = require("src.battle.BattleState")

  -- ------- one round, with or without the press
  --
  -- Returns what the foe's swing cost, plus what the window reported while it
  -- was open. nil means the round never got as far as a swing.
  -- SNORLAX for the reason the other battle probes pick it -- bulky enough to
  -- survive the player's move and answer with its own -- but at a LOW level.
  -- At 45 its BODY SLAM took the starter's whole bar, and applyDamage clamps
  -- the blow at the victim's remaining HP: a measurement that reads "108"
  -- because the mon only had 108 cannot then be compared against a quarter of
  -- itself. The reduction is only measurable on a hit the player survives.
  local FOE, FOE_LV = "SNORLAX", 12

  local function round(doPress, tag)
    local seed = 20260917
    local ok, battle = pcall(BattleState.newWild, game, FOE, FOE_LV)
    if not (ok and battle) or battle.dead then return nil, "no battle" end
    -- Both rounds start from the same health. battle.player.mon IS the party
    -- mon, so round A's damage would otherwise still be on it in round B and
    -- the A/B would be comparing two different fights.
    local full = (battle.player.curStats and battle.player.curStats.hp)
                 or (battle.player.mon.stats and battle.player.mon.stats.hp)
    if full then
      battle.player.mon.hp = full
      battle.player.shownHP = full
    end
    -- the same dice in both rounds: an LCG, not a pinned extreme
    battle.rng = function(a, b)
      seed = (seed * 1103515245 + 12345) % 2147483648
      if not a then return seed / 2147483648 end
      if not b then b, a = a, 1 end
      if b <= a then return a end
      return a + seed % (b - a + 1)
    end
    -- PIN THE FOE'S SWING. Left to its own brain a SNORLAX spends most turns
    -- on AMNESIA / REST / HARDEN, and a status move opens no window -- rightly,
    -- there is nothing to parry. An unpinned probe therefore measures "the AI
    -- felt like buffing today" and reports it as a broken parry. The instance
    -- field shadows BattleState:enemyAction for this battle only.
    local swing
    for i, mv in ipairs(battle.enemy.curMoves or {}) do
      local def = mv.id and battle.data.moves[mv.id]
      if def and (def.power or 0) > 0 and def.category ~= "status"
         and (mv.pp or 0) > 0 then
        swing = i; break
      end
    end
    if not swing then return nil, "the foe has no damaging move" end
    battle.enemyAction = function(self) return self.enemy.curMoves[swing] end
    game.overworld:pushBattle(battle)

    local function waitPhase(want, cap)
      for _ = 1, (cap or 400) do
        if battle.phase == want then return true end
        if battle.dead then return false end
        coroutine.yield()
      end
      return false
    end
    if not waitPhase("menu", 1200) then
      for _ = 1, 30 do
        if battle.phase == "menu" then break end
        tap("a"); wait(12)
      end
    end
    if battle.phase ~= "menu" then return nil, "never reached the menu" end

    battle.menuIndex = 1              -- FIGHT
    tap("a"); wait(10)
    if battle.phase ~= "moveSelect" then
      -- BattleNav remaps the cluster; drive the engine's own door instead of
      -- guessing which chip the cursor is on
      pcall(battle.chooseMenu, battle, "fight"); wait(10)
    end
    if battle.phase == "moveSelect" then
      pcall(battle.chooseMove, battle, 1)
    end

    -- ------- watch for the window
    local opened, moveName, grade, left0 = false, nil, nil, nil
    local hpBefore, hpAfter, foeBefore, foeAfter
    -- A trail, printed only when it changes. Without it a round that never
    -- swings is indistinguishable from a window that never opened, and those
    -- are two different bugs in two different files.
    local lastTrail, acted = nil, {}
    do
      local moves = battle.enemy and battle.enemy.curMoves or {}
      local names = {}
      for i, mv in ipairs(moves) do
        local def = battle.data.moves[mv.id]
        names[i] = ("%s(pow=%s,cat=%s,pp=%s)"):format(tostring(mv.id),
          tostring(def and def.power), tostring(def and def.category),
          tostring(mv.pp))
      end
      log("  foe moves: " .. table.concat(names, " "))
      log("  parry enabled=" .. tostring(Parry.enabled())
          .. " hook=" .. tostring(BattleState.terrariumParryHook))
    end
    for _ = 1, 3000 do
      local d = Parry.debug()
      local trail = ("phase=%s q=%d wait=%s anim=%s atkIsPlayer=%s php=%s ehp=%s")
        :format(tostring(battle.phase), #(battle.queue or {}),
                tostring(battle.waitFrames), tostring(battle.animPlaying),
                tostring(battle.animAttackerIsPlayer),
                tostring(battle.player.mon.hp), tostring(battle.enemy.mon.hp))
      if trail ~= lastTrail then log("  " .. trail); lastTrail = trail end
      if battle.animPlaying and battle.animAttackerIsPlayer == false then
        acted.enemy = true
      end
      if d and not opened then
        opened = true
        moveName, left0 = d.move, d.left
        hpBefore = battle.player.mon.hp
        foeBefore = battle.enemy.mon.hp
        shot("parry_" .. tag .. "_window.png")
      end
      if d and doPress and not d.grade
         and (d.left or 0) <= Parry.PERFECT_AT then
        Parry.press()
        grade = (Parry.debug() or {}).grade
      end
      if opened and not d then
        -- the window closed: the foe's turn has resolved this very frame
        hpAfter = battle.player.mon.hp
        foeAfter = battle.enemy.mon.hp
        grade = grade or (Parry.last and Parry.last.grade)
        break
      end
      if battle.dead then break end
      coroutine.yield()
    end
    -- leave the fight so the next round starts clean
    for _ = 1, 400 do
      if battle.dead or game.stack:top() == game.overworld then break end
      pcall(function() battle.result = battle.result or "won"; battle:finish() end)
      coroutine.yield()
    end
    wait(20)
    if not opened then
      return nil, ("the window never opened (foe acted=%s, phase=%s)")
        :format(tostring(acted.enemy), tostring(battle.phase))
    end
    if not hpAfter then return nil, "the window never closed" end
    return { move = moveName, left0 = left0, grade = grade,
             hpBefore = hpBefore, ko = hpAfter <= 0,
             dmg = hpBefore - hpAfter, foeDelta = (foeBefore or 0) - (foeAfter or 0) }
  end

  local raw, whyA = round(false, "raw")
  if not raw then return bail("round A: " .. tostring(whyA)) end
  log(("round A (no press): move=%s left0=%d dmg=%d foeDelta=%d")
      :format(tostring(raw.move), raw.left0 or -1, raw.dmg, raw.foeDelta))

  verdict((raw.left0 or 0) > 0,
          "the foe's turn is DEFERRED, not resolved on the spot",
          ("frames on the clock when the window opened: %d")
            :format(raw.left0 or 0))
  verdict((raw.left0 or 0) <= Parry.WINDOW,
          "the window is no longer than WINDOW",
          ("%d <= %d"):format(raw.left0 or 0, Parry.WINDOW))
  verdict(raw.move ~= nil and raw.move ~= "",
          "the window NAMES the incoming move", tostring(raw.move))
  verdict(raw.grade == nil, "no press means no grade", tostring(raw.grade))
  verdict(raw.dmg > 0, "the unparried blow lands",
          ("%d HP"):format(raw.dmg))
  -- applyDamage clamps at the victim's remaining HP, so a KO makes the raw
  -- figure a floor rather than a number and the multiplier below unmeasurable
  verdict(not raw.ko,
          "the unparried blow is SURVIVED, so its size is a real number",
          ("%d of %d HP"):format(raw.dmg, raw.hpBefore or -1))

  local par, whyB = round(true, "parried")
  if not par then return bail("round B: " .. tostring(whyB)) end
  log(("round B (perfect press): move=%s grade=%s dmg=%d foeDelta=%d")
      :format(tostring(par.move), tostring(par.grade), par.dmg, par.foeDelta))

  verdict(par.grade == "perfect", "the press inside the band reads PERFECT",
          tostring(par.grade))
  verdict(par.move == raw.move,
          "the same seed threw the same move in both rounds",
          ("%s vs %s"):format(tostring(raw.move), tostring(par.move)))
  verdict(par.dmg < raw.dmg, "a perfect parry costs the player less HP",
          ("%d parried vs %d raw"):format(par.dmg, raw.dmg))
  -- the multiplier, allowing one point either way for the engine's own floors
  local want = math.max(1, math.floor(raw.dmg * Parry.PERFECT_MULT))
  verdict(math.abs(par.dmg - want) <= 1,
          "the reduction is the PERFECT multiplier and not merely 'less'",
          ("got %d, want ~%d (raw %d x %.2f)")
            :format(par.dmg, want, raw.dmg, Parry.PERFECT_MULT))
  verdict(par.foeDelta == raw.foeDelta,
          "the parry changes the player's loss and nothing else",
          ("foe delta %d vs %d"):format(par.foeDelta, raw.foeDelta))

  -- ------- the LOOK pass
  --
  -- The measurements above say the rule is right; they say nothing about
  -- whether the boards' picture is on screen. So one last fight is entered
  -- with the charge economy ON, and the two screens the concept draws are
  -- photographed: the command row and the hand of cards. Nothing is asserted
  -- here -- a layout is read, not measured -- but a run that produces these
  -- two files is a run somebody can check the design against.
  do
    Charge.setting:sync("on")
    Charge.reset()
    local ok, battle = pcall(BattleState.newWild, game, FOE, FOE_LV)
    if ok and battle and not battle.dead then
      game.overworld:pushBattle(battle)
      -- the same A-taps the measured rounds use: the intro queues "Wild X
      -- appeared!" and the menu is behind it, so yielding alone never arrives
      for _ = 1, 60 do
        if battle.phase == "menu" or battle.dead then break end
        tap("a"); wait(14)
      end
      if battle.phase == "menu" then
        battle.menuIndex = 1
        wait(40)
        shot("look_command_row.png")
        pcall(battle.chooseMenu, battle, "fight")
        wait(60)                       -- the hand deals in
        battle.moveIndex = 1
        wait(30)
        shot("look_move_cards.png")
        battle.moveIndex = math.min(2, #(battle.player.curMoves or { 1 }))
        wait(30)
        shot("look_move_cards_2.png")
        log("look pass: charge=" .. tostring(select(1, Charge.read()))
            .. "/" .. tostring(select(2, Charge.read())))
      else
        log("WARN: look pass never reached the menu")
      end
      for _ = 1, 200 do
        if battle.dead then break end
        pcall(function() battle.result = battle.result or "won"; battle:finish() end)
        coroutine.yield()
      end
    end
  end

  log(("battleparry_probe: %d checks, %d fail"):format(checks, fails))
  log(fails == 0 and "PASS" or "FAIL")
  logf:close()
  love.event.quit()
end
