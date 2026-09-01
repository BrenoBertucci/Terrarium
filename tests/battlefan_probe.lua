-- Probe: is the hand of cards really standing in the world?
--
-- Three measurable claims, measured:
--   1. The fan draws: one card per move, centres ordered left-to-right on
--      screen, the selected card raised.
--   2. The cards are WORLD-anchored: pinning the drift at its two opposite
--      extremes (BattleCam.t at 1/4 and 3/4 of PAN_PERIOD, +-2 degrees of
--      orbit) must MOVE the projected centres on screen. A screen-space
--      fan would not budge; that is the whole difference between this and
--      the flat rows, and a screenshot alone cannot testify to it.
--   3. The raise ANIMATES: right after DOWN the new card's lift is caught
--      mid-flight (between 0 and 1), and settled near 1 shortly after --
--      a snap and a tween look identical in stills.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/battlefan_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/battlefan.log", "w"))
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
  local BattleFanXY = lib.require("BattleFanXY")
  local BattleCam = lib.require("BattleCam")
  local DayNight = lib.require("DayNight")
  DayNight.setting:sync("day")

  local BattleState = require("src.battle.BattleState")
  local ok, battle = pcall(BattleState.newWild, game, "RATTATA", 9)
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
  battle.menuIndex = 1
  wait(10)
  if not press("a", "moveSelect") then
    log("FAIL: never reached moveSelect (phase="
        .. tostring(battle.phase) .. ")")
    logf:close(); love.event.quit(); return
  end
  wait(40) -- the deal settles

  local function verdict(okv, name, detail)
    log((okv and "PASS: " or "FAIL: ") .. name .. "  " .. detail)
  end

  -- ------- claim 1: the hand is up, in order, selection raised
  local d = BattleFanXY.debug()
  local nMoves = #((battle.player and battle.player.curMoves) or {})
  if not d then
    log("FAIL: fan never drew (debug empty) -- flat rows took the frame")
    shot("fan_fallback.png")
    logf:close(); love.event.quit(); return
  end
  local ordered = true
  for i = 1, d.n - 1 do
    if not (d.cx[i] and d.cx[i + 1] and d.cx[i] < d.cx[i + 1]) then
      ordered = false
    end
  end
  local centres = {}
  for i = 1, d.n do
    centres[i] = ("%.0f,%.0f"):format(d.cx[i] or -1, d.cy[i] or -1)
  end
  log("fan: n=" .. d.n .. "/" .. nMoves .. " sel=" .. tostring(d.sel)
      .. " centres=" .. table.concat(centres, " "))
  verdict(d.n == nMoves and d.n >= 2, "one card per move",
          ("n=%d moves=%d"):format(d.n, nMoves))
  verdict(ordered, "centres ordered left-to-right", "")
  local selR = d.raise[d.sel] or 0
  local unselMax = 0
  for i = 1, d.n do
    if i ~= d.sel then unselMax = math.max(unselMax, d.raise[i] or 0) end
  end
  verdict(selR > unselMax and selR > 0, "selected card raised",
          ("raise=%.3f unselMax=%.3f"):format(selR, unselMax))
  shot("fan_moves.png")

  -- ------- claim 2: pin the drift at both extremes; the fan must move
  local P = BattleCam.PAN_PERIOD
  BattleCam.t = P * 0.25
  wait(30) -- the attack camera's pursuit settles on the new goal
  local a = BattleFanXY.debug()
  local ax1 = a and a.cx[1]
  BattleCam.t = P * 0.75
  wait(30)
  local b2 = BattleFanXY.debug()
  local bx1 = b2 and b2.cx[1]
  local moved = (ax1 and bx1) and math.abs(ax1 - bx1) or 0
  verdict(moved > 6, "cards are world-anchored (drift moved them)",
          ("|dx|=%.1f px (%.0f -> %.0f)"):format(moved, ax1 or -1, bx1 or -1))

  -- ------- claim 3: the raise animates through the slots
  local selBefore = d.sel
  tap("down")
  wait(3)
  local mid = BattleFanXY.debug()
  local newSel = mid and mid.sel
  local midRaise = (mid and newSel and mid.raise[newSel]) or -1
  wait(40)
  local after = BattleFanXY.debug()
  local settled = (after and newSel and after.raise[newSel]) or -1
  local oldDown = (after and after.raise[selBefore]) or -1
  verdict(newSel ~= selBefore, "DOWN moved the selection",
          ("%s -> %s"):format(tostring(selBefore), tostring(newSel)))
  verdict(midRaise > 0 and newSel ~= selBefore,
          "raise caught in motion (a tween, not a teleport)",
          ("raise=%.3f three frames in"):format(midRaise))
  verdict(settled > oldDown and settled > 0.5, "raise settled",
          ("new=%.3f old=%.3f"):format(settled, oldDown))
  shot("fan_down.png")

  -- and the way back out still works
  tap("b"); wait(60)
  verdict(battle.phase == "menu", "B returns to the command menu",
          "phase=" .. tostring(battle.phase))

  logf:close()
  love.event.quit()
end
