-- Probe: is the X/Y battle HUD on the screen, and is it the X/Y one?
--
-- Two questions, and the second is the one that catches the failure this kind
-- of change actually has: the block draws, but the art did not load and what
-- is up there is the Game Boy's block on a frosted panel exactly as before.
-- A screenshot with "a HUD in it" cannot tell those apart, so the A/B is
-- against BattleHudXY.ENABLED and the reading is by colour:
--
--   the X/Y bar is a SATURATED green (0.44, 0.87, 0.41) at full health; the
--   Game Boy's HP bar is the 4-shade palette's own mid-grey, which has no
--   channel separation at all. So "green pixels where the block is" is
--   present-and-correct, and its absence is decisive whichever way the block
--   failed.
--
-- Anchoring: a battle, unlike a corridor, holds still on its own -- but the
-- intro slides the blocks in and the text types itself out a character at a
-- time, so the shot has to wait for the phase to settle rather than for a
-- frame count. The control pair proves it did.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/hudxy_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/hudxy_probe.log", "w"))
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
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
    wait(4)
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

  local BattleHudXY = lib.require("BattleHudXY")
  local OverworldBattle = lib.require("OverworldBattle")
  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")

  Weather.setting:sync("off")
  DayNight.setting:sync("day")     -- day, so a dark panel cannot be mistaken
                                   -- for a block that failed to draw

  -- Does the art exist at all? Asked before any picture is taken, because a
  -- false here explains every zero below and a probe that makes you infer it
  -- from a screenshot has wasted a run.
  log("available: " .. tostring(BattleHudXY.available()))
  for _, name in ipairs({ "frame_player", "frame_enemy", "hp_fill",
                          "font", "digits" }) do
    log("  art " .. name .. ": " ..
        tostring(BattleHudXY.available() and "loaded" or "?"))
  end

  local BattleState = require("src.battle.BattleState")
  local ok, battle = pcall(BattleState.newWild, game, "NIDORINO", 23)
  if not (ok and battle) or battle.dead then
    log("FAIL: could not make a wild battle: " .. tostring(battle))
    logf:close(); love.event.quit(); return
  end
  game.overworld:pushBattle(battle)

  -- Settle on the battle rather than on a count: the intro slides the blocks
  -- in from off-frame and a shot taken during it measures the slide.
  local settled = false
  for _ = 1, 900 do
    coroutine.yield()
    if game.stack:top() == battle and (battle.introSlide or 0) == 0
       and battle.phase then
      settled = true
      break
    end
  end
  wait(120)
  log("settled: " .. tostring(settled) .. "  phase=" .. tostring(battle.phase))

  local e, p = OverworldBattle.hudLive(battle, 0)
  log(("hudLive: enemy=%s player=%s"):format(tostring(e), tostring(p)))
  local pi = BattleHudXY.read(battle.player)
  local ei = BattleHudXY.read(battle.enemy)
  if pi then
    log(("player: %s Lv%d %d/%d"):format(pi.name, pi.level, pi.hp, pi.maxHP))
  end
  if ei then
    log(("enemy:  %s Lv%d %d/%d"):format(ei.name, ei.level, ei.hp, ei.maxHP))
  end
  log("exp frac: " ..
      tostring(BattleHudXY.expFraction(battle.player, battle.data)))

  -- Why the EXP slot came back empty, if it did. growth_rates is the engine's
  -- own table and this file does not get to assume its shape -- so print it.
  local gr = battle.data and battle.data.growth_rates
  log("growth_rates: " .. type(gr))
  if type(gr) == "table" then
    local keys = {}
    for k in pairs(gr) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    log("  rates: " .. table.concat(keys, ", "))
    local one = gr[battle.player and battle.player.def
                   and battle.player.def.growthRate] or gr[keys[1]]
    log("  entry type: " .. type(one))
    if type(one) == "table" then
      local n, sample = 0, {}
      for k, v in pairs(one) do
        n = n + 1
        if n <= 6 then sample[#sample + 1] = tostring(k) .. "=" .. tostring(v) end
      end
      log(("  entry has %d keys; sample %s"):format(n, table.concat(sample, " ")))
    end
  end

  -- control pair, then the A/B
  shot("hudxy_control_a.png")
  shot("hudxy_control_b.png")
  BattleHudXY.ENABLED = false; wait(30); shot("hudxy_off.png")
  BattleHudXY.ENABLED = true;  wait(30); shot("hudxy_on.png")

  -- Get to the command menu, which is where BOTH blocks are live -- the
  -- player's is not up during the intro messages, so a shot taken there
  -- measures the foe's block twice and says nothing about the player's.
  local reached = false
  for _ = 1, 400 do
    if battle.phase == "menu" then reached = true break end
    tap("a"); wait(6)
  end
  wait(60)
  local e2, p2 = OverworldBattle.hudLive(battle, 0)
  log(("at menu: reached=%s phase=%s hudLive enemy=%s player=%s")
      :format(tostring(reached), tostring(battle.phase),
              tostring(e2), tostring(p2)))
  shot("hudxy_both.png")

  -- The numbers the draw used, so a screenshot measurement can be converted
  -- into the block's own space instead of guessed at.
  for _, key in ipairs({ "enemy", "player" }) do
    local b = OverworldBattle._lastXY and OverworldBattle._lastXY[key]
    if b then
      log(("%s block: x=%.1f y=%.1f w=%.1f h=%.1f s=%.4f  canvas pw=%s ph=%s ly=%s gbScale=%s exp=%s")
          :format(key, b.x, b.y, b.w, b.h, b.s, tostring(b.pw), tostring(b.ph),
                  tostring(b.ly), tostring(b.scale), tostring(b.exp)))
    else
      log(key .. " block: not drawn")
    end
  end
  log("screen: " .. tostring(love.graphics.getWidth()) .. "x"
      .. tostring(love.graphics.getHeight()))

  -- Which branch each side took, over a clean window of frames. Reset first,
  -- so the intro's own frames (where the player's block is legitimately not
  -- live) do not get counted against the steady state.
  -- The shot is taken INSIDE the counted window, which the first version of
  -- this got wrong: the counters were switched on after the pictures were
  -- taken, so a clean count was reported for frames nobody had photographed
  -- while the photograph showed the Game Boy's bar. A count and an image that
  -- do not cover the same frames cannot contradict each other, which makes
  -- the pair worthless exactly when it matters.
  OverworldBattle._xyStats = {}
  wait(45)
  shot("hudxy_counted.png")
  wait(45)
  local st = OverworldBattle._xyStats
  local keys = {}
  for k in pairs(st) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do log(("branch %-14s %d"):format(k, st[k])) end

  -- A stray blue rectangle sits above the EXP slot whenever the player's
  -- block draws, in a blue that is NOT EXP_COLOR. Paint each element in turn
  -- with a colour nothing else in the frame wears: whichever repaint moves
  -- the rectangle is the draw that owns it. Cheaper than reading the maths
  -- again, and it cannot be argued with.
  local keep = {
    exp = BattleHudXY.EXP_COLOR,
    hi = BattleHudXY.HP_HIGH,
  }
  BattleHudXY.EXP_COLOR = { 1, 0, 1 }        -- magenta
  wait(30); shot("hudxy_tint_exp.png")
  BattleHudXY.EXP_COLOR = keep.exp
  BattleHudXY.HP_HIGH = { 1, 0, 1 }
  wait(30); shot("hudxy_tint_hp.png")
  BattleHudXY.HP_HIGH = keep.hi
  wait(30)

  -- Alive, or stuck? The rectangle came back at exactly 1100 pixels in six
  -- different frames, including ones where the HP bar had moved -- which is
  -- what a stale composite looks like and not what a draw looks like. So:
  -- switch the block off WHILE THE PLAYER'S SIDE IS LIVE (the earlier off-shot
  -- was taken during the intro, when the side is not live and the test proves
  -- nothing), and see whether it clears.
  BattleHudXY.ENABLED = false; wait(45); shot("hudxy_menu_off.png")
  BattleHudXY.ENABLED = true;  wait(45); shot("hudxy_menu_on.png")

  -- Order test: paint the band magenta immediately before the block draws.
  -- Magenta covering the stray bar means the bar was already on the canvas
  -- and clearing the band fixes it; the bar surviving on top means it is
  -- drawn later and this is the wrong place to fix it.
  OverworldBattle.XY_DEBUG_WIPE = true
  wait(45); shot("hudxy_wipe.png")
  OverworldBattle.XY_DEBUG_WIPE = false
  wait(45); shot("hudxy_unwipe.png")

  -- The stray bar is drawn AFTER snapHUDs by something the mod does not
  -- wrap -- painting the band immediately before the block did not stop it.
  -- `drawHUDs` is wrapped and skipped when snapped, so the bar is coming out
  -- of a different method. List them: the engine ships inside the executable
  -- and this is the only way to read its surface.
  local BS = require("src.battle.BattleState")
  local names = {}
  for k, v in pairs(BS) do
    if type(v) == "function" then names[#names + 1] = k end
  end
  local mt = getmetatable(BS)
  if mt and mt.__index and type(mt.__index) == "table" then
    for k, v in pairs(mt.__index) do
      if type(v) == "function" then names[#names + 1] = "mt:" .. k end
    end
  end
  table.sort(names)
  -- Silence each candidate draw in turn and photograph the result. The stray
  -- bar is blue and the Game Boy's HUD is four greys, so a COLOURING pass is
  -- the obvious suspect -- but suspicion is not a measurement, and each of
  -- these is one shot.
  for _, m in ipairs({ "drawZonePass", "drawClassic", "drawBallRow" }) do
    local inner = battle[m] or BS[m]
    if type(inner) == "function" then
      battle[m] = function() end
      wait(30); shot(("hudxy_no_%s.png"):format(m))
      battle[m] = nil
      wait(30)
      log("silenced " .. m)
    else
      log("no such method on the battle: " .. m)
    end
  end

  log("BattleState functions (" .. #names .. "):")
  for _, k in ipairs(names) do
    if k:lower():find("draw") or k:lower():find("exp") or k:lower():find("hud")
       or k:lower():find("bar") then
      log("  * " .. k)
    end
  end

  -- and the bar's colour, which is the one thing here that is a FUNCTION
  -- rather than a picture. Both sides, because they are drawn from different
  -- frames and only the player's carries the numbers.
  for _, t in ipairs({ { tag = "mid", f = 0.35 }, { tag = "low", f = 0.12 } }) do
    for _, key in ipairs({ "player", "enemy" }) do
      local s = battle[key]
      if s then
        local maxHP = (s.curStats and s.curStats.hp) or 1
        s.shownHP = math.max(1, math.floor(maxHP * t.f))
        if s.mon then s.mon.hp = s.shownHP end
      end
    end
    wait(30); shot(("hudxy_%s.png"):format(t.tag))
    log(("shot %s: player shownHP=%s enemy shownHP=%s"):format(
        t.tag, tostring(battle.player and battle.player.shownHP),
        tostring(battle.enemy and battle.enemy.shownHP)))
  end

  logf:close()
  love.event.quit()
end
