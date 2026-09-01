-- Probe: does the glass really live in the arena?
--
-- Four measurable claims:
--   1. THE BOB: at an idle menu the player capsule's projected centre
--      breathes -- a few pixels of travel, never zero, never wild.
--   2. THE WEATHER: throwing the electric move puts the "spark" effect
--      up while its animation plays.
--   3. THE WAVE: when the hit lands, the capsule is SHOVED -- its centre
--      deviates from the pre-impact baseline by far more than the bob.
--   4. STATUS: paralysing the foe bursts sparks onto the dialog box, and
--      its capsule reports (and wears) the status -- the orb's first
--      in-game validation.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/battleglassfx_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/battleglassfx.log", "w"))
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
  local FX = lib.require("BattleGlassFX")
  local Capsule = lib.require("BattleCapsule")
  local BattleHudXY = lib.require("BattleHudXY")
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

  -- ------- claim 1: the bob (and a baseline for the wave)
  local ymin, ymax, xsum, ysum, count = 1e9, -1e9, 0, 0, 0
  for _ = 1, 80 do
    local d = Capsule.debug()
    local p = d and d.player
    if p then
      ymin = math.min(ymin, p[2]); ymax = math.max(ymax, p[2])
      xsum = xsum + p[1]; ysum = ysum + p[2]; count = count + 1
    end
    coroutine.yield()
  end
  local baseX = count > 0 and (xsum / count) or 0
  local baseY = count > 0 and (ysum / count) or 0
  local bobRange = (count > 0) and (ymax - ymin) or -1
  verdict(bobRange > 1.5 and bobRange < 24, "the panels breathe (bob)",
          ("y range %.1f px over 80 idle frames"):format(bobRange))

  -- ------- pick the ELECTRIC move, so the weather has a known flavour
  local Box = lib.require("BattleBoxXY")
  local moves = (battle.player and battle.player.curMoves) or {}
  local data = (battle.data and battle.data.moves) or {}
  local elecIdx = nil
  for i, mv in ipairs(moves) do
    local def = data[mv.id]
    local tn = def and Box.typeName(def.type)
    if tn == "ELECTRIC" and def.power and def.power > 0 then
      elecIdx = i
    end
  end
  if not elecIdx then
    log("NOTE: no damaging ELECTRIC move on the lead; using slot 1")
    elecIdx = 1
  end
  if press("a", "moveSelect") then
    battle.moveIndex = elecIdx
    wait(8)
    tap("a")
  end

  -- ------- claims 2 and 3: the weather is up, then the wave shoves
  local sawSpark = false
  local waveSeen = false
  local peakDev = 0
  local shotSpark, shotImpact = false, false
  local menuRun = 0
  for i = 1, 2400 do
    local fd = FX.debug()
    if fd and fd.elem == "spark" and battle.animPlaying then
      sawSpark = true
      if not shotSpark then
        wait(8)
        shot("fx_spark.png"); shotSpark = true
      end
    end
    if fd and fd.wave then
      waveSeen = true
      local d = Capsule.debug()
      local p = d and d.player
      if p then
        local dev = math.sqrt((p[1] - baseX) ^ 2 + (p[2] - baseY) ^ 2)
        if dev > peakDev then peakDev = dev end
      end
      if not shotImpact and fd.wave.t > 0.05 then
        shot("fx_impact.png"); shotImpact = true
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
  verdict(sawSpark, "the electric move rained sparks on the box", "")
  verdict(waveSeen, "a hit dropped the wave", "")
  verdict(peakDev > 8, "the wave SHOVED the capsule",
          ("peak deviation %.1f px (bob baseline %.1f)")
          :format(peakDev, bobRange))

  -- ------- claim 4: paralysis, straight onto the foe
  wait(30)
  if battle.enemy and battle.enemy.mon then
    battle.enemy.mon.status = "PAR"
  end
  local burstSeen = false
  for _ = 1, 30 do
    local fd = FX.debug()
    if fd and fd.burst == "spark" then burstSeen = true break end
    coroutine.yield()
  end
  wait(20)
  local info = BattleHudXY.read(battle.enemy)
  verdict(burstSeen, "paralysis burst onto the dialog box", "")
  verdict(info and info.status == "PAR", "the capsule carries the status",
          ("status=%s"):format(tostring(info and info.status)))
  shot("fx_status.png")

  logf:close()
  love.event.quit()
end
