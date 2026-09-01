-- Probe: does the ribbon tell the truth about the turn?
--
-- Four measurable claims:
--   1. FORECAST: at the menu, the crest belongs to the faster mon -- and
--      the probe checks that against the battle's own Speed stats, not
--      against an assumption about who is faster.
--   2. ANCHORED: pinning the drift at opposite extremes moves the crest
--      medallion on screen.
--   3. TRUTH DURING THE ROUND: while a move plays the crest follows the
--      ACTUAL attacker, gold; over a full round both sides hold it.
--   4. GLIDE: when the crest changes hands the incoming medallion is
--      caught mid-arc -- a tween, not a teleport.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/battleribbon_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/battleribbon.log", "w"))
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
  local Ribbon = lib.require("BattleRibbon")
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
  wait(50) -- the glide settles

  -- ------- claim 1: the forecast matches the battle's own Speed
  local d = Ribbon.debug()
  if not (d and d.player and d.enemy) then
    log("FAIL: ribbon never drew (debug=" .. tostring(d ~= nil) .. ")")
    shot("ribbon_missing.png")
    logf:close(); love.event.quit(); return
  end
  local ps = battle.player.curStats and battle.player.curStats.speed or -1
  local es = battle.enemy.curStats and battle.enemy.curStats.speed or -1
  local faster = (es > ps) and "enemy" or "player"
  log(("speeds: player=%d enemy=%d -> faster=%s crest=%s golden=%s")
      :format(ps, es, faster, tostring(d.crest), tostring(d.golden)))
  verdict(d.crest == faster, "the forecast crest is the faster mon",
          ("crest=%s faster=%s"):format(tostring(d.crest), faster))
  verdict(not d.golden, "a forecast is pale, not gold", "")
  verdict(math.abs(d.t[faster] - 0.5) < 0.06,
          "the forecast medallion sits at the crest",
          ("t=%.3f"):format(d.t[faster]))
  verdict(d.on and d.on.player and d.on.enemy,
          "both medallions are ON SCREEN, not merely projectable",
          ("player=%s enemy=%s"):format(tostring(d.on and d.on.player),
                                        tostring(d.on and d.on.enemy)))
  shot("ribbon_menu.png")

  -- ------- claim 2: pin the drift; the WAITING medallion must move.
  -- Not the crest one: the crest sits over the arena's mid, which is the
  -- drift's own orbit axis -- a point there projects nearly fixed, which
  -- is correct physics and a useless measurement. The medallion resting
  -- by its mon is well off-axis and shows the parallax.
  local waiting = (faster == "player") and "enemy" or "player"
  local P = BattleCam.PAN_PERIOD
  BattleCam.t = P * 0.25
  wait(30)
  local a = Ribbon.debug()
  local ax1 = a and a[waiting] and a[waiting][1]
  BattleCam.t = P * 0.75
  wait(30)
  local b2 = Ribbon.debug()
  local bx1 = b2 and b2[waiting] and b2[waiting][1]
  local moved = (ax1 and bx1) and math.abs(ax1 - bx1) or 0
  verdict(moved > 6, "the ribbon is world-anchored (drift moved it)",
          ("|dx|=%.1f px on the waiting medallion"):format(moved))

  -- ------- claims 3 and 4: the round -- truth at the crest, glide on
  -- the handover
  battle.menuIndex = 1
  if press("a", "moveSelect") then wait(8); tap("a") end
  local sawGold = { player = false, enemy = false }
  local sawGlide = false
  local shotSwap = false
  local menuRun = 0
  for i = 1, 2400 do
    local dd = Ribbon.debug()
    if dd and dd.golden and dd.crest then
      sawGold[dd.crest] = true
      -- the handover caught mid-arc: the golden side's medallion is
      -- neither at its rest nor yet at the crest
      local t = dd.t[dd.crest]
      local rest = (dd.crest == "player") and 0.13 or 0.87
      if math.abs(t - 0.5) > 0.08 and math.abs(t - rest) > 0.08 then
        sawGlide = true
      end
      if not shotSwap and dd.crest == "enemy"
         and math.abs(dd.t.enemy - 0.5) < 0.06 then
        shot("ribbon_swap.png"); shotSwap = true
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
  verdict(sawGold.player and sawGold.enemy,
          "both mons held a golden crest across the round",
          ("player=%s enemy=%s"):format(tostring(sawGold.player),
                                        tostring(sawGold.enemy)))
  verdict(sawGlide, "the handover glides along the arc", "")

  logf:close()
  love.event.quit()
end
