-- Probe: under BACK SPRITES, is the player's mon IN the shot -- behind the
-- move fan, standing on its tile, and bigger than the foe's own scale?
--
-- The bug this guards: the back pic used to be the GB's own flat pic on
-- the UI canvas, which composites ABOVE the world canvas the fan is drawn
-- into -- so the mon sat on top of its own move cards, and was tucked to
-- half size to get out of their way. Three measurable claims, measured:
--   1. STAGED: with BACK SPRITES on, OverworldBattle.textures hands the
--      scene a player texture marked back + hero, monCards stands TWO
--      cards, and the shot says playerStaged.
--   2. NOT PINNED: the wrapped drawPicsLayer draws nothing for the player
--      while playerStaged (picImage is never asked for anything) -- and
--      DOES once the flag is cleared, so the counter is known to work.
--   3. HERO: the player's card projects BACK_HERO times wider on screen
--      than the same card at hero 1, and the fan is still up over it (one
--      card per move).
-- Plus screenshots at three hero sizes and with BACK SPRITES off, for
-- the eye. The BACK SPRITES row is moved through ModSetting:sync, which
-- only moves the cached index -- the player's own options are not written.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/backhero_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/backhero.log", "w"))
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
  local function quit()
    logf:close(); love.event.quit()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") quit() return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then log("FAIL: TERRARIUM not loaded") quit() return end
  local OverworldBattle = lib.require("OverworldBattle")
  local BattleScene = lib.require("BattleScene")
  local BattleFanXY = lib.require("BattleFanXY")
  local DayNight = lib.require("DayNight")
  DayNight.setting:sync("day")
  local wasBack = OverworldBattle.backSetting:get()
  local heroDefault = OverworldBattle.BACK_HERO
  OverworldBattle.backSetting:sync(true)

  local BattleState = require("src.battle.BattleState")
  local ok, battle = pcall(BattleState.newWild, game, "RATTATA", 9)
  if not (ok and battle) or battle.dead then
    log("FAIL: no battle"); quit(); return
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

  if not press("a", "menu") then
    log("FAIL: never reached the command menu (phase="
        .. tostring(battle.phase) .. ")")
    quit(); return
  end
  wait(30)
  shot("hero_menu.png")
  battle.menuIndex = 1
  wait(10)
  if not press("a", "moveSelect") then
    log("FAIL: never reached moveSelect (phase="
        .. tostring(battle.phase) .. ")")
    quit(); return
  end
  wait(40) -- the deal settles

  -- ------- claim 1: staged
  local s = OverworldBattle.shot()
  if not s then
    log("FAIL: no shot -- the battle is not staged on the map")
    shot("hero_noshot.png")
    OverworldBattle.backSetting:sync(wasBack)
    quit(); return
  end
  verdict(s.playerStaged == true, "the shot says the player is staged",
          "playerStaged=" .. tostring(s.playerStaged))
  local okT, tex = pcall(OverworldBattle.textures, battle)
  local player = okT and tex and tex.player
  verdict(player and player.back == true
          and player.hero == OverworldBattle.BACK_HERO,
          "the player's texture is marked back + hero",
          ("ok=%s back=%s hero=%s want=%s"):format(tostring(okT),
            tostring(player and player.back), tostring(player and player.hero),
            tostring(OverworldBattle.BACK_HERO)))
  local arena = OverworldBattle.arena()
  local cards = (player and arena)
                and BattleScene.monCards(arena, s.groundY, tex) or {}
  verdict(#cards == 2, "two cards stand on the field",
          "cards=" .. tostring(#cards))
  log(("marks: player=%.1f,%.1f enemy=%.1f,%.1f spanP=%.1f spanE=%.1f "
       .. "scale=%.2f lx=%.0f ly=%.0f pw=%d ph=%d"):format(
      s.player[1], s.player[2], s.enemy[1], s.enemy[2],
      s.playerSpan or -1, s.enemySpan or -1, s.scale or -1, s.lx or -1,
      s.ly or -1, s.pw or -1, s.ph or -1))

  -- ------- claim 3 (measured now, while the textures are fresh): the
  -- projected width of the player's card, at the hero and at 1
  local function xform(m, x, y, z)
    return m[1] * x + m[2] * y + m[3] * z + m[4],
           m[5] * x + m[6] * y + m[7] * z + m[8],
           m[9] * x + m[10] * y + m[11] * z + m[12]
  end
  local function extentGB(model)
    -- the unit card: x in -0.5..0.5, y in 0..1 (BattleBillboard)
    local ax, ay, az = xform(model, -0.5, 0.5, 0)
    local bx, by, bz = xform(model, 0.5, 0.5, 0)
    local fx, fy, fz = xform(model, 0, 0, 0)
    local tx, ty, tz = xform(model, 0, 1, 0)
    local x1 = BattleScene.toGB(s.vp, ax, ay, az, s.lx, s.ly, s.scale,
                                s.pw, s.ph)
    local x2 = BattleScene.toGB(s.vp, bx, by, bz, s.lx, s.ly, s.scale,
                                s.pw, s.ph)
    local _, y1 = BattleScene.toGB(s.vp, fx, fy, fz, s.lx, s.ly, s.scale,
                                   s.pw, s.ph)
    local _, y2 = BattleScene.toGB(s.vp, tx, ty, tz, s.lx, s.ly, s.scale,
                                   s.pw, s.ph)
    if not (x1 and x2 and y1 and y2) then return nil end
    return math.abs(x2 - x1), math.abs(y2 - y1), y1
  end
  local function playerCard(list)
    for _, c in ipairs(list) do
      if player and c.tex == player.canvas then return c end
    end
    return nil
  end
  local pc = playerCard(cards)
  local wHero, hHero, feetHero
  if pc then wHero, hHero, feetHero = extentGB(pc.model) end
  local wOne, hOne
  if player then
    local hero = player.hero
    player.hero = 1
    local one = playerCard(BattleScene.monCards(arena, s.groundY, tex))
    if one then wOne, hOne = extentGB(one.model) end
    player.hero = hero
  end
  local ratio = (wHero and wOne and wOne > 0) and (wHero / wOne) or -1
  local picH = OverworldBattle.backPicHeight() or 0
  local wantHero = math.min(OverworldBattle.BACK_HERO,
                            (picH > 0) and (OverworldBattle.BACK_MAX_PIC / picH)
                            or OverworldBattle.BACK_HERO)
  verdict(wHero and math.abs(ratio - wantHero) < 0.03,
          "the player's card projects the capped hero times wider",
          ("hero=%.1fx%.1f GBpx at1=%.1fx%.1f ratio=%.3f want=%.3f "
           .. "picH=%.1f cap=%.1f feetY=%.1f")
          :format(wHero or -1, hHero or -1, wOne or -1, hOne or -1, ratio,
                  wantHero, picH, OverworldBattle.BACK_MAX_PIC,
                  feetHero or -1))
  -- the head stays on screen: the pic's box top, GB rows from the top
  local topRow = (feetHero and hHero) and (feetHero - hHero * picH / 144)
                 or -1
  verdict(topRow >= 4, "the pic's box top stays inside the frame",
          ("topRow=%.1f (feet %.1f, box %.1f tall for %.1f px of pic)")
          :format(topRow, feetHero or -1, hHero or -1, picH))
  local d = BattleFanXY.debug()
  local nMoves = #((battle.player and battle.player.curMoves) or {})
  local centres = {}
  if d then
    for i = 1, d.n do
      centres[i] = ("%.0f,%.0f"):format(d.cx[i] or -1, d.cy[i] or -1)
    end
  end
  verdict(d and d.n == nMoves and d.n >= 2, "the fan is up over it",
          ("n=%s moves=%d centres=%s"):format(tostring(d and d.n), nMoves,
                                              table.concat(centres, " ")))
  -- ...and clears the hero: the pic's box (the middle 64 of the card's 160
  -- texture columns, centred on TEX_AX) ends left of the raised card's
  -- own left edge, in window pixels
  do
    local cxw, boxRight, cardLeft = -1, -1, -1
    if pc then
      local mx, my, mz = xform(pc.model, 0, 0.5, 0)
      local gx = BattleScene.toGB(s.vp, mx, my, mz, s.lx, s.ly, s.scale,
                                  s.pw, s.ph)
      if gx and wHero then
        cxw = s.lx + gx * s.scale
        boxRight = s.lx + (gx + wHero * 0.2) * s.scale
      end
    end
    if d and d.x0 and d.sel then cardLeft = d.x0[d.sel] or -1 end
    verdict(boxRight > 0 and cardLeft > 0 and cardLeft >= boxRight - 8,
            "the raised card clears the hero's pic box",
            ("cardLeft=%.0f boxRight=%.0f centre=%.0f (window px)")
            :format(cardLeft, boxRight, cxw))
  end

  -- ------- claim 2: not pinned
  do
    local calls = 0
    local innerPic = battle.picImage
    battle.picImage = function(self, img)
      calls = calls + 1
      return innerPic(self, img)
    end
    local ds = battle.dramaticShapeShot
    local okD, errD = pcall(battle.drawPicsLayer, battle, 0, 0, 0, "player",
                            true)
    local staged = calls
    local unstaged = -1
    if ds then
      local was = ds.playerStaged
      ds.playerStaged = false
      calls = 0
      local okU = pcall(battle.drawPicsLayer, battle, 0, 0, 0, "player", true)
      unstaged = okU and calls or -1
      ds.playerStaged = was
    end
    battle.picImage = nil
    love.graphics.setColor(1, 1, 1, 1)
    verdict(okD and ds and ds.playerStaged and staged == 0 and unstaged > 0,
            "the pics layer leaves the player alone while staged",
            ("ok=%s err=%s pinnedCalls=%d fallbackCalls=%d")
            :format(tostring(okD), tostring(errD), staged, unstaged))
  end

  -- ------- the eye: the hero at three sizes, then BACK SPRITES off
  shot("hero_moves.png")
  for _, h in ipairs({ 1.0, 1.25, 1.75 }) do
    OverworldBattle.BACK_HERO = h
    wait(14)
    shot(("hero_%.2f.png"):format(h))
  end
  OverworldBattle.BACK_HERO = heroDefault
  wait(14)
  -- the deal again, so the raised card reads in the still
  tap("down"); wait(30)
  shot("hero_moves_down.png")
  OverworldBattle.backSetting:sync(false)
  wait(14)
  shot("hero_backoff.png")
  OverworldBattle.backSetting:sync(true)
  wait(6)
  -- and the message phase: the mon behind the message panel
  tap("b"); wait(20)
  shot("hero_menu_back.png")

  OverworldBattle.backSetting:sync(wasBack)
  log("done")
  quit()
end
