-- Probe: does the battle tell anyone which command is highlighted?
--
-- The X/Y command menu is four buttons, and drawing them means knowing which
-- one the cursor is on. The Game Boy draws its own arrow into the text box, so
-- the answer may not exist as a field at all -- it may only exist as pixels.
-- That is the difference between replacing the menu and merely framing it, so
-- it gets asked before anything is written.
--
-- Watches the battle across the menu phase and reports every field that
-- CHANGES when the cursor moves. A cursor index cannot hide from that: press
-- down, and whatever number went with it is the field.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/battlemenu_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/battlemenu.log", "w"))
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

  local BattleState = require("src.battle.BattleState")
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
  wait(40)
  log("phase: " .. tostring(battle.phase) .. "  reached=" .. tostring(reached))
  if not reached then
    log("FAIL: never got to the command menu")
    logf:close(); love.event.quit(); return
  end

  -- snapshot every scalar on the battle, move the cursor, snapshot again
  local function snap()
    local t = {}
    for k, v in pairs(battle) do
      local ty = type(v)
      if ty == "number" or ty == "string" or ty == "boolean" then
        t[k] = v
      end
    end
    return t
  end

  local function diff(a, b, tag)
    local keys = {}
    for k in pairs(b) do
      if a[k] ~= b[k] then keys[#keys + 1] = k end
    end
    table.sort(keys)
    if #keys == 0 then
      log(tag .. ": nothing changed")
    else
      for _, k in ipairs(keys) do
        log(("%s: %s  %s -> %s"):format(tag, k, tostring(a[k]), tostring(b[k])))
      end
    end
  end

  shot("bm_menu_0.png")
  local a = snap()
  tap("down"); wait(25)
  local b = snap()
  diff(a, b, "after DOWN")
  shot("bm_menu_down.png")
  tap("right"); wait(25)
  local c = snap()
  diff(b, c, "after RIGHT")
  shot("bm_menu_right.png")
  tap("up"); wait(25)
  diff(c, snap(), "after UP")

  -- and the same for the move list, which is the other half of the job.
  -- Getting there means being ON Fight first: the earlier run pressed A from
  -- wherever the cursor had ended up and landed in `messages`, which is why
  -- it reported that nothing changed.
  local guard = 0
  while battle.menuIndex ~= 1 and guard < 12 do tap("up"); wait(8); guard = guard + 1 end
  wait(15)
  log("on FIGHT: menuIndex=" .. tostring(battle.menuIndex))
  tap("a"); wait(50)
  log("phase after A: " .. tostring(battle.phase))
  shot("bm_moves.png")
  local d = snap()
  tap("down"); wait(30)
  diff(d, snap(), "moves after DOWN")
  local e = snap()
  tap("right"); wait(30)
  diff(e, snap(), "moves after RIGHT")

  -- what a move record carries, for the name/type/PP on each capsule
  local mv = battle.data and battle.data.moves
  local first = battle.player and battle.player.curMoves
                and battle.player.curMoves[1]
  if mv and first and first.id and mv[first.id] then
    local ks = {}
    for k, v in pairs(mv[first.id]) do
      if type(v) ~= "table" then ks[#ks + 1] = k .. "=" .. tostring(v) end
    end
    table.sort(ks)
    log("moves[" .. tostring(first.id) .. "]: " .. table.concat(ks, "  "))
  end

  -- the move rows themselves, for the capsule buttons
  local moves = battle.player and battle.player.curMoves
  if type(moves) == "table" then
    for i = 1, #moves do
      local m = moves[i]
      local ks = {}
      if type(m) == "table" then
        for k, v in pairs(m) do
          if type(v) ~= "table" then ks[#ks + 1] = k .. "=" .. tostring(v) end
        end
        table.sort(ks)
      end
      log(("  curMoves[%d]: %s"):format(i, table.concat(ks, " ")))
    end
  end

  logf:close()
  love.event.quit()
end
