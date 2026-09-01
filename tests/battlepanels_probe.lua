-- Probe: is the menu really furniture in the arena?
--
-- Four measurable claims:
--   1. The menu hangs: four chips plus the message panel, FIGHT above the
--      row, selection tracking the engine's menuIndex.
--   2. WORLD anchoring: pinning the drift at opposite extremes moves the
--      chips on screen (a screen-space menu would not).
--   3. The pop still works on the chips (the selected one swells).
--   4. The PARALLAX PAYOFF: while a move plays and the attack camera
--      swings, the message panel's projected centre travels across the
--      screen. This is the one thing the flat panel could never do, so
--      its absence is the fallback having silently taken the frame.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/battlepanels_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/battlepanels.log", "w"))
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
  local Panels = lib.require("BattlePanelsXY")
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

  -- ------- claim 1: the menu hangs
  local d = Panels.debug()
  if not (d and d.phase == "menu") then
    log("FAIL: menu never hung (debug=" .. tostring(d and d.phase)
        .. ") -- flat panels took the frame")
    shot("panels_fallback.png")
    logf:close(); love.event.quit(); return
  end
  local chips = 0
  for i = 1, 4 do if d.cx[i] and d.cy[i] then chips = chips + 1 end end
  local rowTop = math.min(d.cy[2] or 1e9, d.cy[3] or 1e9, d.cy[4] or 1e9)
  log(("menu: chips=%d sel=%s fight=(%.0f,%.0f) msg=(%.0f,%.0f)")
      :format(chips, tostring(d.sel), d.cx[1] or -1, d.cy[1] or -1,
              d.msg[1] or -1, d.msg[2] or -1))
  verdict(chips == 4, "four chips hung", ("chips=%d"):format(chips))
  verdict(d.msg and d.msg[1] ~= nil, "message panel hung", "")
  verdict(chips == 4 and (d.cy[1] or 0) < rowTop, "FIGHT floats above the row",
          ("fightY=%.0f rowTop=%.0f chips=%d"):format(d.cy[1] or -1, rowTop, chips))
  verdict(d.sel == battle.menuIndex, "selection tracks menuIndex",
          ("sel=%s menuIndex=%s"):format(tostring(d.sel),
                                         tostring(battle.menuIndex)))
  shot("panels_menu.png")

  -- ------- claim 2: pin the drift at both extremes; the chips must move
  local P = BattleCam.PAN_PERIOD
  BattleCam.t = P * 0.25
  wait(30)
  local a = Panels.debug()
  local ax1 = a and a.cx and a.cx[1]
  BattleCam.t = P * 0.75
  wait(30)
  local b2 = Panels.debug()
  local bx1 = b2 and b2.cx and b2.cx[1]
  local moved = (ax1 and bx1) and math.abs(ax1 - bx1) or 0
  verdict(moved > 6, "chips are world-anchored (drift moved them)",
          ("|dx|=%.1f px"):format(moved))

  -- ------- claim 3: the cursor still pops chips. Driven by a REAL tap:
  -- writing menuIndex raced the engine's own cursor bookkeeping and lost
  -- one run in five.
  tap("down")
  wait(12)
  local m3 = Panels.debug()
  verdict(m3 and m3.sel == battle.menuIndex and battle.menuIndex ~= 1,
          "cursor moved off FIGHT and the chips followed",
          ("sel=%s menuIndex=%s"):format(tostring(m3 and m3.sel),
                                         tostring(battle.menuIndex)))
  tap("up")
  wait(20)

  -- ------- claim 4: the round -- the panel rides the attack camera
  battle.menuIndex = 1
  if press("a", "moveSelect") then wait(8); tap("a") end

  local sawMessage = false
  local msgMin, msgMax = 1e9, -1e9
  local shotAttack = false
  local menuRun = 0
  for i = 1, 2400 do
    local dd = Panels.debug()
    local sd = BattleShot.debug()
    if dd and dd.phase == "message" and battle.phase == "messages" then
      sawMessage = true
      if sd and (sd.mode == "attack" or sd.mode == "hold") then
        local mx = dd.msg and dd.msg[1]
        if mx then
          if mx < msgMin then msgMin = mx end
          if mx > msgMax then msgMax = mx end
        end
        if not shotAttack and math.abs(sd.dYaw or 0) > math.rad(4) then
          shot("panels_attack.png"); shotAttack = true
        end
      end
    end
    if battle.dead then log("battle ended at frame " .. i); break end
    menuRun = (battle.phase == "menu") and (menuRun + 1) or 0
    if menuRun >= 12 then
      log(("round resolved at frame %d"):format(i))
      break
    end
    coroutine.yield()
  end
  local range = (msgMax > msgMin) and (msgMax - msgMin) or 0
  verdict(sawMessage, "message panel hung through the round", "")
  verdict(range > 15, "panel rode the attack camera (parallax)",
          ("msg x range=%.1f px during the swing"):format(range))

  logf:close()
  love.event.quit()
end
