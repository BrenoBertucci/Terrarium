-- Probe: the party and the bag, over the diorama.
--
-- Opens each of the two battle screens lib/BattleScreenXY.lua covers and
-- photographs them. What the log settles that the pictures cannot: whether
-- the engine's own screen was actually HIDDEN (render_visible seam) or the
-- X/Y draw is sitting on top of a white Game Boy page nobody can see behind
-- it -- both look identical in a screenshot.
--
-- The save's party is one Pikachu, which exercises one card and no colour
-- band. So the probe pads the party with shallow clones at staged HP levels
-- -- half, red-band, fainted-with-poison -- and RESTORES the real party
-- before quitting: clones share the save's tables and must not outlive the
-- shot. Nothing fights this battle; the clones are furniture.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/battlescreen_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/battlescreen.log", "w"))
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
  local BattleScreenXY = lib.require("BattleScreenXY")
  local OverworldBattle = lib.require("OverworldBattle")
  local DayNight = lib.require("DayNight")
  DayNight.setting:sync("day")

  -- pad the party: clones at staged HP so every colour band and the status
  -- chip are in the one picture
  local party = game.save.party
  local realCount = #party
  local base = party[1]
  if base and realCount == 1 then
    local function clone(hpFrac, status)
      local c = {}
      for k, v in pairs(base) do c[k] = v end
      c.stats = {}
      for k, v in pairs(base.stats) do c.stats[k] = v end
      c.moves = {}
      for i, mv in ipairs(base.moves or {}) do
        local m = {}
        for k, v in pairs(mv) do m[k] = v end
        c.moves[i] = m
      end
      c.hp = math.floor(c.stats.hp * hpFrac)
      c.status = status
      return c
    end
    party[2] = clone(0.45)
    party[3] = clone(0.12)
    party[4] = clone(0, "PSN")
    log("party padded to 4")
  end
  local function restoreParty()
    for i = #party, realCount + 1, -1 do party[i] = nil end
    log("party restored to " .. tostring(#party))
  end

  local BattleState = require("src.battle.BattleState")
  local ok, battle = pcall(BattleState.newWild, game, "RATTATA", 9)
  if not (ok and battle) or battle.dead then
    restoreParty()
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
    restoreParty()
    log("FAIL: never reached the command menu (phase=" ..
        tostring(battle.phase) .. ")")
    logf:close(); love.event.quit(); return
  end
  wait(30)

  -- ------- the party
  battle.menuIndex = 2
  wait(10)
  tap("a"); wait(70)
  local top = game.stack:top()
  log("party: top.screenId=" .. tostring(top and top.screenId))
  log("party: hides(top)=" .. tostring(BattleScreenXY.hides(top)))
  log("party: screensLive=" .. tostring(OverworldBattle.screensLive()))
  local scr, kind = BattleScreenXY.of(game)
  log("party: of() kind=" .. tostring(kind))
  -- The measurement hides() alone cannot make: what the STACK decided. If
  -- the hook is live the visible base falls through to the battle; if it is
  -- not, the base is the opaque party screen and the X/Y cards are sitting
  -- on a white Game Boy page.
  log("party: visibleBase=" .. tostring(game.stack:visibleBase())
      .. " of " .. tostring(#game.stack.states)
      .. " baseIsBattle=" ..
      tostring(game.stack.states[game.stack:visibleBase()] == battle))
  shot("bs_party.png")

  tap("down"); wait(20)
  log("party: index after DOWN=" .. tostring(top and top.index))
  shot("bs_party_down.png")

  -- the submenu (SWITCH / STATS / CANCEL on a voluntary battle party)
  tap("a"); wait(30)
  log("party: submenu=" .. tostring(top and top.submenu ~= nil)
      .. " items=" .. tostring(top and top.subItems and #top.subItems))
  shot("bs_party_sub.png")
  tap("b"); wait(20)   -- close the submenu
  tap("b"); wait(60)   -- close the party
  log("after party: phase=" .. tostring(battle.phase)
      .. " top==battle " .. tostring(game.stack:top() == battle))

  -- ------- the bag
  if not press("a", "menu") then
    restoreParty()
    log("FAIL: no command menu back (phase=" .. tostring(battle.phase) .. ")")
    logf:close(); love.event.quit(); return
  end
  wait(20)
  battle.menuIndex = 3
  wait(10)
  tap("a"); wait(70)
  top = game.stack:top()
  log("bag: top has items=" .. tostring(top and type(top.items) == "table")
      .. " n=" .. tostring(top and top.items and #top.items))
  log("bag: hides(top)=" .. tostring(BattleScreenXY.hides(top)))
  local _, bkind = BattleScreenXY.of(game)
  log("bag: of() kind=" .. tostring(bkind))
  log("bag: visibleBase=" .. tostring(game.stack:visibleBase())
      .. " baseIsBattle=" ..
      tostring(game.stack.states[game.stack:visibleBase()] == battle))
  shot("bs_bag.png")

  tap("down"); wait(20)
  log("bag: index after DOWN=" .. tostring(top and top.index))
  shot("bs_bag_down.png")
  tap("b"); wait(60)
  log("after bag: phase=" .. tostring(battle.phase)
      .. " top==battle " .. tostring(game.stack:top() == battle))

  restoreParty()
  logf:close()
  love.event.quit()
end
