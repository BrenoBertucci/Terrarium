-- Probe: do attacks actually hit the costume?
--
-- Four measurable claims:
--   1. DINAMICA (the default): BattleHitFX.ENABLED is open.
--   2. THROWING A MOVE: while animPlaying, debug reports playing (or a
--      tagged battle Vfx is live / lastKey is set). lastKey is a bt_*
--      authored sheet, not an OGA impact/smallhit.
--   3. THE HIT: on flash / shake / HP drain, a battle Vfx or lastKey is
--      set, and GlassFX is carrying a wave (telegraph or hit).
--   4. CLASSICA: flipping the COMBAT row closes the gate.
--
-- Screenshots are taken at the anim and the hit, but a screenshot that
-- races must never fail the boot -- the numbers are the test.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/battlehitfx_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/battlehitfx.log", "w"))
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
  local HitFX = lib.require("BattleHitFX")
  local GlassFX = lib.require("BattleGlassFX")
  local Dyn = lib.require("BattleDynamic")
  local Vfx = lib.require("Vfx")
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

  -- ------- claim 1: DINAMICA leaves the gate open
  local row = Dyn.setting:row()
  if row and row.value and row.value() ~= "DINAMICA" then
    Dyn.setting:sync("dynamic")
    Dyn.apply()
    wait(8)
  end
  verdict(HitFX.ENABLED == true, "DINAMICA: BattleHitFX.ENABLED is open",
          ("ENABLED=%s COMBAT=%s"):format(tostring(HitFX.ENABLED),
            tostring(row and row.value and row.value())))

  -- ------- throw a move and sample every frame
  battle.menuIndex = 1
  if press("a", "moveSelect") then wait(8); tap("a") end

  local sawPlaying, sawLive, sawKey = false, false, false
  local sawHit, sawWave = false, false
  local shotAnim, shotHit = false, false
  local menuRun = 0
  local lastDbg = nil
  for i = 1, 2400 do
    local d = HitFX.debug()
    lastDbg = d
    local live = (d and d.live) or 0
    if Vfx.battleCount then live = math.max(live, Vfx.battleCount()) end
    if battle.animPlaying then
      if d and d.playing then sawPlaying = true end
      if live > 0 then sawLive = true end
      if d and d.lastKey then sawKey = true end
      if not shotAnim and (d and (d.playing or d.lastKey) or live > 0) then
        shot("hitfx_anim.png"); shotAnim = true
      end
    end
    local fx = battle.fx
    local flash = (fx and (fx.flash or 0) > 0) and true or false
    local quake = (fx and (fx.shake or 0) > 0) and true or false
    local function draining(b)
      if not (b and b.mon and b.shownHP) then return false end
      return b.shownHP > b.mon.hp
    end
    local drain = draining(battle.player) or draining(battle.enemy)
    if flash or quake or drain then
      if live > 0 or (d and d.lastKey) then sawHit = true end
      local gd = GlassFX.debug()
      if gd and gd.wave then sawWave = true end
      if not shotHit then
        shot("hitfx_hit.png"); shotHit = true
      end
    end
    local gd = GlassFX.debug()
    if gd and gd.wave then sawWave = true end
    if battle.dead then log("battle ended at frame " .. i); break end
    menuRun = (battle.phase == "menu") and (menuRun + 1) or 0
    if menuRun >= 12 then
      log(("round resolved at frame %d"):format(i))
      break
    end
    coroutine.yield()
  end
  log(("debug playing=%s live=%s lastKey=%s lastSide=%s chargeKey=%s hitKey=%s projectile=%s")
      :format(tostring(lastDbg and lastDbg.playing),
              tostring(lastDbg and lastDbg.live),
              tostring(lastDbg and lastDbg.lastKey),
              tostring(lastDbg and lastDbg.lastSide),
              tostring(lastDbg and lastDbg.chargeKey),
              tostring(lastDbg and lastDbg.hitKey),
              tostring(lastDbg and lastDbg.projectile)))

  local lastKey = lastDbg and lastDbg.lastKey
  local isBt = type(lastKey) == "string" and lastKey:sub(1, 3) == "bt_"
  verdict(sawPlaying or sawLive or sawKey,
          "during animPlaying the hit FX is live",
          ("playing=%s live=%s lastKey=%s")
          :format(tostring(sawPlaying), tostring(sawLive), tostring(sawKey)))
  verdict(sawHit, "on hit a battle Vfx or lastKey is set", "")
  verdict(isBt, "lastKey is a bt_* authored sheet after throwing a move",
          ("lastKey=%s chargeKey=%s hitKey=%s")
          :format(tostring(lastKey),
                  tostring(lastDbg and lastDbg.chargeKey),
                  tostring(lastDbg and lastDbg.hitKey)))
  verdict(sawWave, "GlassFX is carrying a wave (telegraph or hit)", "")

  -- ------- claim 4: CLASSICA closes the gate
  Dyn.setting:sync("classic")
  Dyn.apply()
  wait(12)
  verdict(HitFX.ENABLED == false, "CLASSICA: BattleHitFX.ENABLED is closed",
          ("ENABLED=%s"):format(tostring(HitFX.ENABLED)))

  logf:close()
  love.event.quit()
end
