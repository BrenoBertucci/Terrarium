-- Probe: do the HP capsules really hang beside their own mons?
--
-- Three measurable claims:
--   1. Both capsules hang in the WORLD (stage two), each near its own
--      mon: the player's panel below-left of the enemy's on this arena's
--      geometry (player south-west, enemy north-east).
--   2. World anchoring: pinning the drift at opposite extremes moves the
--      player capsule on screen.
--   3. The bar is LIVE: after a round the enemy capsule's fraction has
--      dropped, and both capsules were still hanging when it ended.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/battlecapsule_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/battlecapsule.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
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
  local Capsule = lib.require("BattleCapsule")
  local BattleShot = lib.require("BattleShot")
  local BattleCam = lib.require("BattleCam")
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

  local function verdict(okv, name, detail)
    log((okv and "PASS: " or "FAIL: ") .. name .. "  " .. detail)
  end

  if not press("a", "menu") then
    log("FAIL: never reached the command menu (phase="
        .. tostring(battle.phase) .. ")")
    logf:close(); love.event.quit(); return
  end
  battle.menuIndex = 1
  wait(40)

  -- ------- claim 1: both hang, each near its own mon
  local d = Capsule.debug()
  local p = d and d.player
  local e = d and d.enemy
  if not (p and e) then
    log("FAIL: capsules not hanging in the world (player="
        .. tostring(p ~= nil) .. " enemy=" .. tostring(e ~= nil)
        .. ") -- corner placement took the frame")
    shot("caps_fallback.png")
    logf:close(); love.event.quit(); return
  end
  log(("capsules: player=(%.0f,%.0f frac=%.2f) enemy=(%.0f,%.0f frac=%.2f)")
      :format(p[1], p[2], p.frac, e[1], e[2], e.frac))
  verdict(p[1] < e[1] and p[2] > e[2],
          "each capsule sits by its own mon",
          ("player left-below of enemy: dx=%.0f dy=%.0f")
          :format(e[1] - p[1], p[2] - e[2]))
  verdict(e.frac > 0.99, "enemy opens at full health",
          ("frac=%.3f"):format(e.frac))
  shot("caps_menu.png")

  -- ------- claim 2: pin the drift; the capsule must move
  local P = BattleCam.PAN_PERIOD
  BattleCam.t = P * 0.25
  wait(30)
  local a = Capsule.debug()
  local ax1 = a and a.player and a.player[1]
  BattleCam.t = P * 0.75
  wait(30)
  local b2 = Capsule.debug()
  local bx1 = b2 and b2.player and b2.player[1]
  local moved = (ax1 and bx1) and math.abs(ax1 - bx1) or 0
  verdict(moved > 6, "capsules are world-anchored (drift moved them)",
          ("|dx|=%.1f px"):format(moved))

  -- ------- claim 3: a round lands, the bar answers
  battle.menuIndex = 1
  if press("a", "moveSelect") then wait(8); tap("a") end
  local shotAttack = false
  local menuRun = 0
  for i = 1, 2400 do
    local sd = BattleShot.debug()
    if not shotAttack and sd and sd.mode == "attack"
       and math.abs(sd.dYaw or 0) > math.rad(4) then
      shot("caps_attack.png"); shotAttack = true
    end
    if battle.dead then log("battle ended at frame " .. i); break end
    menuRun = (battle.phase == "menu") and (menuRun + 1) or 0
    if menuRun >= 12 then
      log(("round resolved at frame %d"):format(i))
      break
    end
    coroutine.yield()
  end
  wait(30)
  local after = Capsule.debug()
  local pe = after and after.enemy
  local pp = after and after.player
  verdict(pe ~= nil and pp ~= nil, "capsules survived the round", "")
  verdict(pe and pe.frac < 0.99, "the enemy bar drained where it was hit",
          ("frac %.3f -> %.3f"):format(e.frac, pe and pe.frac or -1))
  shot("caps_after.png")

  logf:close()
  love.event.quit()
end
