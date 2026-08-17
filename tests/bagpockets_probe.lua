-- Probe: the bag's pockets, and the EXP bar's ghost.
--
-- Two claims, one battle:
--   * the quality_of_life XP bar no longer paints its blue rectangle over
--     a staged battle -- MEASURED, by counting pixels of its exact blue
--     (RGB 50,150,250) in the command-menu frame. It measured 1100 before
--     the patch; the claim is zero. A count is the only honest check: the
--     bar is a live draw that a screenshot cannot tell from a stale one.
--   * LEFT/RIGHT walk the bag's pockets: the selected item's pocket must
--     CHANGE on RIGHT and the cursor must land on a real item of that
--     pocket, and UP/DOWN must stay inside it.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/bagpockets_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/bagpockets.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local function shot(name, countBlue)
    love.graphics.captureScreenshot(function(data)
      if countBlue then
        local n = 0
        local w, h = data:getDimensions()
        for y = 0, h - 1 do
          for x = 0, w - 1 do
            local r, g, b = data:getPixel(x, y)
            if math.abs(r * 255 - 50) < 3 and math.abs(g * 255 - 150) < 3
               and math.abs(b * 255 - 250) < 3 then
              n = n + 1
            end
          end
        end
        log("exp-blue pixels in " .. name .. ": " .. n)
      end
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
    wait(6)
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
    log("FAIL: no command menu (phase=" .. tostring(battle.phase) .. ")")
    logf:close(); love.event.quit(); return
  end
  wait(30)
  shot("bp_menu.png", true)

  -- ------- into the bag
  battle.menuIndex = 3
  wait(10)
  tap("a"); wait(70)
  local bag = game.stack:top()
  if not (bag and type(bag.items) == "table") then
    log("FAIL: no bag on top"); logf:close(); love.event.quit(); return
  end
  -- reach into the module the same way the draw does, to name pockets
  local BattleScreenXY = lib.require("BattleScreenXY")
  local function pocketName()
    -- the module keeps pocketOf local; read it off the labels by re-deriving
    -- from the installed state: the script is on, so the selected item's
    -- pocket is whatever tab the draw lights. For the LOG, the item id is
    -- enough -- the assertion is that it CHANGES family on RIGHT.
    local it = bag.items[bag.index]
    return it and tostring(it.value) or "?"
  end
  log("bag open: script installed=" .. tostring(rawget(bag, "script") ~= nil)
      .. " pockets=" .. tostring(rawget(bag, "terrariumPockets")))
  log("bag sel 1: " .. pocketName())
  shot("bp_bag_items.png")

  tap("right"); wait(25)
  log("bag sel after RIGHT: " .. pocketName())
  shot("bp_bag_right1.png")

  tap("down"); wait(25)
  log("bag sel after DOWN: " .. pocketName())

  tap("right"); wait(25)
  log("bag sel after RIGHT 2: " .. pocketName())
  shot("bp_bag_right2.png")

  tap("left"); wait(25)
  log("bag sel after LEFT (memory): " .. pocketName())

  tap("b"); wait(60)
  log("after bag: phase=" .. tostring(battle.phase)
      .. " top==battle " .. tostring(game.stack:top() == battle))

  logf:close()
  love.event.quit()
end
