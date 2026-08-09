-- Probe: can you still choose an attack?
--
-- This exists because of a regression it would have caught. `drawTextArea`
-- draws the message box, the command menu AND the move list; the X/Y box
-- silenced that method wholesale, and the move list -- which has no X/Y
-- replacement -- simply stopped being drawn. Pressing FIGHT led to an empty
-- panel with no way to pick a move, and every screenshot of the command menu
-- looked perfect.
--
-- So the test is not "does the box look right". It is: get to the move list
-- and check that something is ON it. The move list is the engine's own box --
-- an opaque white slab with black glyphs -- so near-white pixels in the lower
-- third are exactly the right measurement, and their ABSENCE is the bug.
--
-- Also checks the way back out (B returns to the command menu) so a move list
-- that draws but traps the player still fails.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/moveselect_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/moveselect.log", "w"))
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
  DayNight.setting:sync("day")

  local BattleState = require("src.battle.BattleState")
  local ok, battle = pcall(BattleState.newWild, game, "RATTATA", 9)
  if not (ok and battle) or battle.dead then
    log("FAIL: no battle"); logf:close(); love.event.quit(); return
  end
  game.overworld:pushBattle(battle)

  -- to the command menu, waiting on the PHASE rather than tapping blind: the
  -- earlier probe pressed A on a timer, and one of those presses went through
  -- the menu and out the other side into `messages`, which is why it reported
  -- that it could not reach the move list
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
    log("FAIL: never reached the command menu (phase=" .. tostring(battle.phase) .. ")")
    logf:close(); love.event.quit(); return
  end
  wait(30)
  -- SET the cursor rather than steering it. Driving it with taps is what a
  -- player does and is the right test for the cursor -- but this probe is
  -- testing the MOVE LIST, and the previous run steered onto ITENS, opened
  -- the bag, and reported that as "the move list is missing". A test that can
  -- fail for a reason it is not testing is worse than no test.
  battle.menuIndex = 1
  wait(10)
  log("on FIGHT: menuIndex=" .. tostring(battle.menuIndex))
  log("covers(menu): " .. tostring(BattleBoxXY.covers(battle)))
  shot("ms_menu.png")

  -- into the move list
  tap("a"); wait(60)
  log("phase after A on FIGHT: " .. tostring(battle.phase))
  log("covers(this phase): " .. tostring(BattleBoxXY.covers(battle)))
  shot("ms_moves.png")

  -- and what the cursor is, now that we are actually in there
  local function snap()
    local t = {}
    for k, v in pairs(battle) do
      local ty = type(v)
      if ty == "number" or ty == "string" or ty == "boolean" then t[k] = v end
    end
    return t
  end
  local before = snap()
  tap("down"); wait(30)
  local after = snap()
  local keys = {}
  for k in pairs(after) do
    if before[k] ~= after[k] and k ~= "frame" then keys[#keys + 1] = k end
  end
  table.sort(keys)
  if #keys == 0 then
    log("cursor field: none changed on DOWN")
  else
    for _, k in ipairs(keys) do
      log(("cursor candidate: %s  %s -> %s")
          :format(k, tostring(before[k]), tostring(after[k])))
    end
  end
  shot("ms_moves_down.png")

  -- and back out again, so a list that draws but traps the player still fails
  tap("b"); wait(60)
  log("phase after B: " .. tostring(battle.phase))
  shot("ms_back.png")

  logf:close()
  love.event.quit()
end
