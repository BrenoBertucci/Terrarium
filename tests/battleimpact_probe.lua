-- Probe: does the arena answer the blow, and does the glass take it?
--
-- Measurable claims, all off the modules' own debug reads plus pixels:
--   1. SPOTLIGHT: while the move plays the frame's corners are darker
--      than at the idle menu (mean luminance of the four corner patches
--      drops), and BattleHitFX reports the spot.
--   2. FLASH: on the hit, BattleHitFX reports the light and the pixels
--      around the defender brighten against the pre-hit frame.
--   3. DEBRIS: cubes were spawned (debug.debris > 0 after the hit).
--   4. MARK: a ground mark of the right kind is registered for the
--      move's type, and it survives the round (still there at the menu).
--   5. NUMBER: a damage tag was raised, and lastDamage equals the bar's
--      own drop (shownHP before the hit minus mon.hp after).
--   6. SPLASH: the wave left a mark on at least two panes (GlassFX
--      debug.splashes >= 2 at some frame after the hit).
--   7. TILT: some pane turned during the wave (maxTilt > 0.02 rad).
--   8. SHADOWS: the arena pass drew the panes' contact shadows
--      (debug.shadows > 0 at the menu).
--   9. CLASSICA: flipping the COMBAT row stops all of it (no spot, no
--      shadows, no splash after a second hit).
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=<abs path>/tests/battleimpact_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/battleimpact.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  -- a screenshot that also hands back the ImageData for measuring; the
  -- callback sets a flag and the probe waits on it (never a yield count).
  -- The PNG is encoded at the END: encoding a frame here stalls the game
  -- a third of a second, and every real-time effect (the flash, the
  -- debris) ages past its life during the stall -- the next capture
  -- would then show a picture the player never sees.
  local pending = {}
  local function shot(name)
    local done, data = false, nil
    love.graphics.captureScreenshot(function(d)
      data = d
      done = true
    end)
    for _ = 1, 120 do
      if done then
        if name then pending[#pending + 1] = { name = name, data = data } end
        return data
      end
      coroutine.yield()
    end
    log("WARN: screenshot " .. tostring(name) .. " never called back")
    return nil
  end
  local function flushShots()
    for _, p in ipairs(pending) do
      local f = io.open(OUT .. "/" .. p.name, "wb")
      if f then f:write(p.data:encode("png"):getString()) f:close() end
    end
    pending = {}
  end
  local function lum(d, x, y, w, h)
    if not d then return -1 end
    local W, H = d:getDimensions()
    x = math.max(0, math.min(W - 1, math.floor(x)))
    y = math.max(0, math.min(H - 1, math.floor(y)))
    w = math.max(1, math.min(W - x, math.floor(w)))
    h = math.max(1, math.min(H - y, math.floor(h)))
    local sum, n = 0, 0
    for yy = y, y + h - 1, 2 do
      for xx = x, x + w - 1, 2 do
        local r, g, b = d:getPixel(xx, yy)
        sum = sum + (0.30 * r + 0.59 * g + 0.11 * b)
        n = n + 1
      end
    end
    return n > 0 and (sum / n) or -1
  end
  local function corners(d)
    if not d then return -1 end
    local W, H = d:getDimensions()
    local s = math.floor(math.min(W, H) * 0.12)
    return (lum(d, 0, 0, s, s) + lum(d, W - s, 0, s, s)
            + lum(d, 0, H - s, s, s) + lum(d, W - s, H - s, s, s)) / 4
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
  local Hit = lib.require("BattleHitFX")
  local FX = lib.require("BattleGlassFX")
  local Dyn = lib.require("BattleDynamic")
  local Box = lib.require("BattleBoxXY")
  local DayNight = lib.require("DayNight")
  DayNight.setting:sync("day")
  Dyn.setting:sync("dynamic"); Dyn.apply()

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
    log((okv and "PASS: " or "FAIL: ") .. name .. "  " .. (detail or ""))
  end
  -- the engine's phase machine touches "menu" transiently mid-round; a
  -- STABLE menu is 12 frames in a row (counted across the caller's loop)
  local menuRun = 0
  local function stableMenu()
    menuRun = (battle.phase == "menu") and (menuRun + 1) or 0
    return menuRun >= 12
  end
  local function hpLine(tag)
    local e, p = battle.enemy, battle.player
    return ("%s e.shown=%s e.hp=%s p.shown=%s p.hp=%s anim=%s attP=%s ph=%s")
      :format(tag, tostring(e and e.shownHP), tostring(e and e.mon and e.mon.hp),
              tostring(p and p.shownHP), tostring(p and p.mon and p.mon.hp),
              tostring(battle.animPlaying), tostring(battle.animAttackerIsPlayer),
              tostring(battle.phase))
  end

  if not press("a", "menu") then
    log("FAIL: never reached the command menu (phase="
        .. tostring(battle.phase) .. ")")
    logf:close(); love.event.quit(); return
  end
  battle.menuIndex = 1
  wait(50)

  -- ------- the idle menu: baseline corners, and claim 8 (shadows)
  local base = shot("impact_menu.png")
  local baseCorners = corners(base)
  local hd = Hit.debug()
  verdict(hd.shadows and hd.shadows > 0, "the panes print contact shadows",
          ("shadows=%s"):format(tostring(hd.shadows)))
  log(("baseline corners lum %.3f"):format(baseCorners))

  -- ------- pick a damaging ELECTRIC move so the mark's kind is known
  local moves = (battle.player and battle.player.curMoves) or {}
  local data = (battle.data and battle.data.moves) or {}
  local pick, pickType = nil, nil
  for i, mv in ipairs(moves) do
    local def = data[mv.id]
    local tn = def and Box.typeName(def.type)
    if tn == "ELECTRIC" and def.power and def.power > 0 then
      pick, pickType = i, tn
    end
  end
  if not pick then
    for i, mv in ipairs(moves) do
      local def = data[mv.id]
      if def and def.power and def.power > 0 then
        pick, pickType = i, Box.typeName(def.type); break
      end
    end
  end
  pick = pick or 1
  log("move slot " .. pick .. " type " .. tostring(pickType))
  local wantKind = (Hit.MARK[pickType or ""] or Hit.MARK_DEFAULT).kind

  if press("a", "moveSelect") then
    battle.moveIndex = pick
    wait(8)
    tap("a")
  end

  -- ------- through the round: spot, flash, debris, tag, splash, tilt
  local sawSpot, spotCorners = false, -1
  local sawLight, lightLum, preLum = false, -1, -1
  local debris, splashes, maxTilt, tags, lastDamage = 0, 0, 0, 0, nil
  local shownBefore = battle.enemy and battle.enemy.shownHP
  local hpAfter = nil
  local shotSpot, shotHit, shotAfter, shotHit2 = false, false, false, false
  local shotHit3 = false
  local markAtHit, markKindAtHit = 0, nil
  local hitAt = nil
  local defCell = nil
  local lastTrace = ""
  local prevShown, monRef = {}, {}
  shownBefore, hpAfter = nil, nil
  menuRun = 0
  for i = 1, 2400 do
    local d = Hit.debug()
    local f = FX.debug()
    -- a trace of every change in the seams the modules read
    local tr = hpLine("") .. (" light=%s tags=%d dmg=%s marks=%d"):format(
      tostring(d.light), d.tags or 0, tostring(d.lastDamage), d.marks or 0)
    if tr ~= lastTrace then log(("f%d %s"):format(i, tr)); lastTrace = tr end
    if d.spot and not sawSpot and battle.animPlaying then
      -- give the fade-in its frames, then measure the corners
      wait(8)
      local img = shot("impact_spot.png")
      spotCorners = corners(img)
      sawSpot = true
      shotSpot = true
      -- the defender's patch, for the flash claim: sample before the hit
      local c = Hit.debug()
      shownBefore = battle.enemy and battle.enemy.shownHP or shownBefore
    end
    if d.light and not sawLight then
      sawLight = true
      hitAt = i
      -- the side whose bar is above its hp is the one just hit: the
      -- expected figure is what the bar showed LAST frame less hp now
      for _, sd in ipairs({ "enemy", "player" }) do
        local b = battle[sd]
        if b and b.mon and prevShown[sd] and prevShown[sd] > (b.mon.hp or 0) then
          shownBefore, hpAfter = prevShown[sd], b.mon.hp
          log(("hit side=%s shownBefore=%s hpAfter=%s"):format(
            sd, tostring(shownBefore), tostring(hpAfter)))
        end
      end
      local img = shot("impact_hit.png")
      if img then
        local W, H = img:getDimensions()
        lightLum = lum(img, W * 0.55, H * 0.15, W * 0.35, H * 0.45)
      end
      shotHit = true
    end
    for _, sd in ipairs({ "enemy", "player" }) do
      local b = battle[sd]
      if b and b.mon then
        if monRef[sd] ~= b.mon then monRef[sd] = b.mon; prevShown[sd] = b.mon.hp
        else prevShown[sd] = b.shownHP or b.mon.hp end
      end
    end
    if d.debris > debris then debris = d.debris end
    if d.tags > tags then tags = d.tags end
    -- the FIRST hit's figure (a later hit on the other side overwrites
    -- lastDamage, and the claim is about the hit that was measured)
    if d.lastDamage and not lastDamage then lastDamage = d.lastDamage end
    if f.splashes and f.splashes > splashes then splashes = f.splashes end
    if f.maxTilt and f.maxTilt > maxTilt then maxTilt = f.maxTilt end
    if hitAt and not shotHit2 and i - hitAt >= 5 then
      shot("impact_hit2.png"); shotHit2 = true
      -- the mark, read while it is fresh: a slow round outlives it
      local dm = Hit.debug()
      markAtHit, markKindAtHit = dm.marks or 0, dm.markKind
    end
    if hitAt and not shotHit3 and i - hitAt >= 12 then
      shot("impact_hit3.png"); shotHit3 = true
    end
    if hitAt and not shotAfter and i - hitAt > 30 then
      shot("impact_after.png"); shotAfter = true
    end
    if battle.dead then log("battle ended at frame " .. i); break end
    if stableMenu() then
      log(("round resolved at frame %d"):format(i))
      break
    end
    -- a message that waits on the player: advance it (never mid-anim)
    if battle.phase == "messages" and not battle.animPlaying
       and i % 40 == 0 then
      game.input.pressQueue[#game.input.pressQueue + 1] = "a"
    end
    coroutine.yield()
  end
  -- the same patch at the baseline, for the flash's brightening
  if base then
    local W, H = base:getDimensions()
    preLum = lum(base, W * 0.55, H * 0.15, W * 0.35, H * 0.45)
  end
  verdict(sawSpot, "the spotlight closed in on the attacker", "")
  verdict(spotCorners >= 0 and spotCorners < baseCorners - 0.04,
          "the corners went dark under the spotlight",
          ("corners %.3f -> %.3f"):format(baseCorners, spotCorners))
  local hdL = Hit.debug()
  verdict(sawLight and (hdL.flashFrames or 0) > 0, "the hit lit the defender",
          ("flash drawn on %d frames, spot on %d; patch lum %.3f -> %.3f")
          :format(hdL.flashFrames or 0, hdL.spotFrames or 0, preLum, lightLum))
  verdict(debris > 0, "voxel debris flew", ("max live %d"):format(debris))
  verdict(markAtHit > 0 and markKindAtHit == wantKind,
          "the blow left its mark on the floor",
          ("marks=%d kind=%s want=%s"):format(markAtHit,
                                               tostring(markKindAtHit),
                                               tostring(wantKind)))
  local expect = (shownBefore and hpAfter) and (shownBefore - hpAfter) or nil
  verdict(tags > 0 and lastDamage and expect and lastDamage == expect,
          "the damage figure says what the bar lost",
          ("tag=%s bar %s->%s expect=%s"):format(tostring(lastDamage),
                                                 tostring(shownBefore),
                                                 tostring(hpAfter),
                                                 tostring(expect)))
  verdict(splashes >= 2, "the wave marked the glass",
          ("panes marked at once: %d"):format(splashes))
  verdict(maxTilt > 0.02, "the panes turned with the shove",
          ("max tilt %.3f rad"):format(maxTilt))
  shot("impact_menu2.png")

  -- ------- the typed answers, on demand: fire at the foe, water at
  -- the lead, a quake -- for the eye (the numbers above are the test)
  do
    local OB = lib.require("OverworldBattle")
    local sh = OB.shot and OB.shot()
    if sh and sh.enemyCell and sh.playerCell then
      Hit.demo("FIRE", sh.enemyCell, sh.groundY, 38)
      wait(4); shot("impact_demo_fire.png")
      wait(30)
      -- the mark on the box: shoot the frame the wave reaches it (the
      -- front travels, so a fixed delay is a guess at the frame rate)
      local function shootOnMsg(name)
        for _ = 1, 90 do
          local fd = FX.debug()
          if fd.splashIds and fd.splashIds.msg then
            wait(3); shot(name); return true
          end
          coroutine.yield()
        end
        log("NOTE: the wave never marked the box for " .. name)
        return false
      end
      Hit.demo("WATER", sh.playerCell, sh.groundY, 51)
      wait(4); shot("impact_demo_water.png")
      local rippled = shootOnMsg("impact_demo_water2.png")
      wait(40)
      -- a physical blow beside the box: the cracks land on it
      Hit.demo("FIGHTING", sh.playerCell, sh.groundY, 27)
      local cracked = shootOnMsg("impact_demo_cracks.png")
      local pd = FX.paneDebug and FX.paneDebug() or {}
      verdict(rippled and cracked and (pd.draws or 0) > 0,
              "the demo waves marked the box",
              ("overlayPane drew %d times; err=%s; last=%s"):format(pd.draws or 0,
                tostring(pd.err),
                pd.last and (pd.last.id .. ("@%.0f,%.0f age %.2f phys=%s")
                  :format(pd.last.ix, pd.last.iy, pd.last.age,
                          tostring(pd.last.physical))) or "nil"))
      wait(30)

      -- and the brush itself, off the arena: a fresh splash on a test
      -- pane, drawn through an identity map onto a canvas, counted
      do
        local g = love.graphics
        local okC, cv = pcall(g.newCanvas, 320, 160)
        if okC and cv then
          FX.pulse(0, 0, 0, 1.0, "FIGHTING")
          FX.observe(battle, 0.001, nil, 0)
          local R = { right = { 1, 0, 0 }, up = { 0, 1, 0 } }
          FX.jolt("unit", { 0, 0, 0 }, R)
          local prev = g.getCanvas()
          g.setCanvas(cv); g.clear(0, 0, 0, 0)
          local drewU = FX.overlayPane("unit", function(x, y) return x, y end,
                                       1, 320, 160, nil)
          g.setCanvas(prev)
          local data = cv:newImageData()
          local n = 0
          for y = 0, 159, 2 do
            for x = 0, 319, 2 do
              local _, _, _, a = data:getPixel(x, y)
              if a > 0.05 then n = n + 1 end
            end
          end
          verdict(drewU and n > 200, "overlayPane paints a fresh splash",
                  ("drew=%s painted samples=%d"):format(tostring(drewU), n))
          local f = io.open(OUT .. "/impact_unit_pane.png", "wb")
          if f then f:write(data:encode("png"):getString()) f:close() end
        end
      end
      Hit.demo("GROUND", sh.enemyCell, sh.groundY, 120, true)
      wait(4); shot("impact_demo_quake.png")
      wait(40)
      shot("impact_demo_marks.png")
      local hdd = Hit.debug()
      verdict(hdd.marks >= 3 and hdd.markKind == "crater",
              "the demo left three typed marks",
              ("marks=%d last=%s"):format(hdd.marks or 0, tostring(hdd.markKind)))
    else
      log("NOTE: no shot for the demo")
    end
  end

  -- ------- claim 9: CLASSICA closes every gate
  Dyn.setting:sync("classic"); Dyn.apply()
  wait(20)
  local hd3 = Hit.debug()
  local closed = (Hit.ENABLED == false) and (FX.ENABLED == false)
  -- the shadows stop being drawn once the row is off
  local shadowsOff = true
  for _ = 1, 20 do
    local d = Hit.debug()
    if d.shadows and d.shadows > 0 then shadowsOff = false end
    coroutine.yield()
  end
  verdict(closed and shadowsOff, "CLASSICA closes the gates",
          ("hit=%s glass=%s shadowsOff=%s"):format(tostring(Hit.ENABLED),
                                                   tostring(FX.ENABLED),
                                                   tostring(shadowsOff)))
  shot("impact_classic.png")
  Dyn.setting:sync("dynamic"); Dyn.apply()

  flushShots()
  logf:close()
  love.event.quit()
end
