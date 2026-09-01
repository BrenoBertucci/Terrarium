-- Probe: does the camera actually move for a move?
--
-- The claim BattleShot makes is measurable, so measure it: during a move
-- animation the shot's yaw offset from the base rig grows toward SWING and
-- the eye punches in; on the hit the shake amplitude rises from zero; and
-- after the round the camera is back within a degree of the rig it left.
-- Screenshots are taken at the same moments, but the numbers are the test
-- -- a screenshot of a camera that did not move looks exactly like a
-- screenshot of one that did, one frame later (see
-- terrarium-probe-screenshot-race).
--
-- A SNORLAX is the sparring partner: bulky enough to survive the player's
-- move and answer with its own, which is what gets BOTH attack directions
-- measured -- the swing must flip sign when the other side throws.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/battleshot_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/battleshot.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  -- wait for the CALLBACK, not a frame count: a scheduled shot plus a guess
  -- photographs whatever frame the guess lands on
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
  local BattleShot = lib.require("BattleShot")
  local DayNight = lib.require("DayNight")
  DayNight.setting:sync("day")

  local BattleState = require("src.battle.BattleState")
  local ok, battle = pcall(BattleState.newWild, game, "SNORLAX", 45)
  if not (ok and battle) or battle.dead then
    log("FAIL: no battle"); logf:close(); love.event.quit(); return
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
    log("FAIL: never reached the command menu (phase="
        .. tostring(battle.phase) .. ")")
    logf:close(); love.event.quit(); return
  end
  wait(30)

  -- ------- idle: the pursuer should be sitting on the rig
  local idleMax = 0
  for _ = 1, 60 do
    local d = BattleShot.debug()
    if d then idleMax = math.max(idleMax, math.abs(d.dYaw)) end
    coroutine.yield()
  end
  log(("idle: mode=%s maxAbsDYaw=%.4f rad")
      :format(tostring(BattleShot.debug() and BattleShot.debug().mode),
              idleMax))
  shot("as_menu.png")

  -- ------- throw moves and sample every frame, up to three rounds
  --
  -- The break is on a STABLE menu -- twelve consecutive frames -- because
  -- the phase machine touches "menu" transiently mid-round, and the first
  -- version of this probe walked out through that crack before the enemy
  -- had its turn (its swing, and the sign flip, went unmeasured).
  local function throwMove()
    battle.menuIndex = 1
    if press("a", "moveSelect") then wait(8); tap("a") end
  end
  throwMove()

  local sawAttack = { [true] = false, [false] = false }
  local maxYaw = { [true] = 0, [false] = 0 }
  local yawSign = { [true] = 0, [false] = 0 }
  local maxShake, maxPunch, minDDist = 0, 0, 0
  local shotAttack, shotImpact, shotEnemy = false, false, false
  local lastMode = "idle"
  local menuRun, rounds = 0, 0
  for i = 1, 3600 do
    local d = BattleShot.debug()
    if d then
      if d.mode ~= lastMode then
        log(("frame %d: mode %s -> %s (attacker=%s dYaw=%.4f dDist=%.2f)")
            :format(i, lastMode, d.mode, tostring(d.attacker), d.dYaw,
                    d.dDist))
        lastMode = d.mode
      end
      if d.mode == "attack" or d.mode == "hold" then
        sawAttack[d.attacker] = true
        local a = math.abs(d.dYaw)
        if a > maxYaw[d.attacker] then
          maxYaw[d.attacker] = a
          yawSign[d.attacker] = d.dYaw >= 0 and 1 or -1
        end
        minDDist = math.min(minDDist, d.dDist)
        if not shotAttack and a > math.rad(4) then
          shot("as_attack.png"); shotAttack = true
        end
        if not shotEnemy and d.attacker == false and a > math.rad(4) then
          shot("as_enemy_attack.png"); shotEnemy = true
        end
      end
      if d.shake > maxShake then maxShake = d.shake end
      if d.fovPunch > maxPunch then maxPunch = d.fovPunch end
      if not shotImpact and d.shake > 0.004 then
        shot("as_impact.png"); shotImpact = true
      end
    end
    if battle.dead then log("battle ended at frame " .. i); break end
    menuRun = (battle.phase == "menu") and (menuRun + 1) or 0
    if menuRun >= 12 then
      rounds = rounds + 1
      log(("round %d resolved at frame %d"):format(rounds, i))
      if rounds >= 3 or (sawAttack[true] and sawAttack[false]) then break end
      menuRun = 0
      throwMove()
    end
    coroutine.yield()
  end

  -- ------- the round is over: the camera must find its way home
  wait(90)
  local d = BattleShot.debug()
  local homeYaw = d and math.abs(d.dYaw) or 999
  local homeMode = d and d.mode or "?"
  shot("as_recovered.png")

  -- ------- verdicts, one measurable claim per line
  local function verdict(okv, name, detail)
    log((okv and "PASS: " or "FAIL: ") .. name .. "  " .. detail)
  end
  verdict(idleMax < math.rad(1.5), "idle holds the rig",
          ("maxAbsDYaw=%.4f rad"):format(idleMax))
  verdict(sawAttack[true], "player attack entered the shot", "")
  verdict(maxYaw[true] > math.rad(4), "player swing reached",
          ("%.4f rad (goal %.4f)"):format(maxYaw[true], BattleShot.SWING))
  verdict(minDDist < -4, "eye punched in",
          ("minDDist=%.2f world px"):format(minDDist))
  verdict(maxShake > 0.004, "impact shook the frame",
          ("maxShake=%.4f rad maxFovPunch=%.4f"):format(maxShake, maxPunch))
  if sawAttack[false] then
    verdict(yawSign[true] ~= 0 and yawSign[false] ~= 0
            and yawSign[true] ~= yawSign[false],
            "enemy swing flipped sign",
            ("player=%+d enemy=%+d"):format(yawSign[true], yawSign[false]))
  else
    log("NOTE: enemy never attacked this round (fainted or status-locked); "
        .. "sign flip not measured")
  end
  verdict(homeMode == "idle" and homeYaw < math.rad(1.2),
          "camera came home",
          ("mode=%s absDYaw=%.4f rad"):format(homeMode, homeYaw))

  logf:close()
  love.event.quit()
end
