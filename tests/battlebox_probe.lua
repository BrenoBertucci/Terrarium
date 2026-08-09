-- Probe: is the X/Y text box on screen, are the buttons following the cursor,
-- and is the Game Boy's box gone?
--
-- Three claims, and the third is the one that fails silently: a box that draws
-- correctly on top of the engine's box looks fine in a screenshot and is two
-- boxes. The engine's is an opaque WHITE slab with a black border across the
-- bottom third of the frame, so near-white pixels down there are the tell and
-- they have to fall to roughly nothing.
--
-- The buttons are checked by MOVING the cursor and watching the highlight
-- move with it: the selected one is drawn at full colour and the other three
-- at BattleBoxXY.DIM, so the count of saturated red rises when LUTAR is
-- selected and falls when it is not. A button that is drawn but not wired to
-- menuIndex passes every other test there is.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/battlebox_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/battlebox.log", "w"))
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
  local BattleBoxXY = lib.require("BattleBoxXY")
  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  Weather.setting:sync("off")
  DayNight.setting:sync("day")
  log("install: " .. tostring(BattleBoxXY.install()))
  log("available: " .. tostring(BattleBoxXY.available()))

  -- the UTF-8 backstop, checked without a battle: charIndex counts bytes and
  -- cutting mid-character is the bug this guards
  local acc = "POK\195\169MON"
  for i = 4, 7 do
    log(("revealed(%q, %d) = %q"):format(acc, i, BattleBoxXY._revealed(acc, i)))
  end

  -- Who owns drawTextArea, and does the battle shadow it on the instance?
  -- The wrapper was installed and never called, and those are the only two
  -- ways that happens: something replaced it afterwards, or the call never
  -- reaches the class at all.
  local BattleState = require("src.battle.BattleState")
  local classDraw = BattleState.drawTextArea
  log("BattleState.drawTextArea = " .. tostring(classDraw))
  local ok, battle = pcall(BattleState.newWild, game, "RATTATA", 9)
  if not (ok and battle) or battle.dead then
    log("FAIL: no battle"); logf:close(); love.event.quit(); return
  end
  game.overworld:pushBattle(battle)

  local reached = false
  for _ = 1, 500 do
    if battle.phase == "menu" then reached = true break end
    tap("a"); wait(6)
  end
  wait(45)
  log("class drawTextArea now  = " .. tostring(BattleState.drawTextArea)
      .. (BattleState.drawTextArea == classDraw and "  (unchanged)"
          or "  (REPLACED since install)"))
  log("battle's own drawTextArea = " .. tostring(rawget(battle, "drawTextArea")))
  local mt = getmetatable(battle)
  log("battle metatable __index is BattleState: "
      .. tostring(mt and mt.__index == BattleState))
  if mt and type(mt.__index) == "table" and mt.__index ~= BattleState then
    log("  __index.drawTextArea = " .. tostring(mt.__index.drawTextArea))
  end
  log(("phase=%s menuIndex=%s reached=%s")
      :format(tostring(battle.phase), tostring(battle.menuIndex),
              tostring(reached)))
  if not reached then
    log("FAIL: never reached the command menu")
    logf:close(); love.event.quit(); return
  end

  BattleBoxXY._stats = {}
  wait(60)
  shot("box_control_a.png")
  shot("box_control_b.png")
  shot("box_on.png")
  BattleBoxXY.ENABLED = false; wait(40); shot("box_off.png")
  BattleBoxXY.ENABLED = true;  wait(40)

  -- and the highlight, driven. 1 = LUTAR (red), 3 = ITENS (amber): the two
  -- are different hues, so "the right one is lit" is a colour count rather
  -- than a guess about where a rectangle is.
  for _, want in ipairs({ 1, 3, 4, 2 }) do
    local guard = 0
    while battle.menuIndex ~= want and guard < 12 do
      if battle.menuIndex == 1 and want >= 3 then tap("down")
      elseif battle.menuIndex == 3 and want == 4 then tap("right")
      elseif battle.menuIndex == 4 and want == 2 then tap("up")
      elseif battle.menuIndex > want then tap("up")
      else tap("down") end
      wait(10); guard = guard + 1
    end
    wait(20)
    log(("menuIndex now %s (wanted %d, %d presses)")
        :format(tostring(battle.menuIndex), want, guard))
    shot(("box_sel%d.png"):format(want))
  end

  local st = BattleBoxXY._stats or {}
  local keys = {}
  for k in pairs(st) do keys[#keys + 1] = k end
  table.sort(keys)
  log("branch counters:")
  for _, k in ipairs(keys) do log(("  %-22s %d"):format(k, st[k])) end
  if #keys == 0 then log("  (none -- neither seam was reached at all)") end

  logf:close()
  love.event.quit()
end
