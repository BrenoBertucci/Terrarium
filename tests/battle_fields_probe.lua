-- Probe: what does a battle actually carry, at draw time?
--
-- The XY HUD has to print a name, a level, HP now and HP max, a gender and
-- an EXP bar. Every one of those is a field on somebody's table, and the
-- engine ships inside the executable rather than beside it -- there is no
-- source tree to read them off. So they get read off the LIVE battle
-- instead, which is the only account of them that cannot be out of date.
--
-- Dumps the shape rather than the values: key names, Lua types, and a short
-- rendering of scalars. A field that turns out to be a table gets one level
-- of its own keys, because `mon.stats.hp` is exactly the sort of place the
-- maximum hides.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/battle_fields_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/battle_fields.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
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

  -- Short, sorted, and one level deep. Sorted because an unordered dump of
  -- forty keys is not something anybody reads twice and the point of this is
  -- to be read against the next run.
  local function brief(v)
    local t = type(v)
    if t == "string" then return ("%q"):format(#v > 40 and v:sub(1, 40) or v) end
    if t == "number" or t == "boolean" then return tostring(v) end
    return t
  end
  local function dump(label, tbl, depth)
    if type(tbl) ~= "table" then
      log(("%s = %s"):format(label, brief(tbl))); return
    end
    local keys = {}
    for k in pairs(tbl) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    log(("%s: %d keys"):format(label, #keys))
    for _, k in ipairs(keys) do
      local v = tbl[k] ~= nil and tbl[k] or tbl[tonumber(k) or k]
      if type(v) == "table" and (depth or 0) < 1 then
        dump("  " .. label .. "." .. k, v, (depth or 0) + 1)
      else
        log(("  %s.%s = %s"):format(label, k, brief(v)))
      end
    end
  end

  local BattleState = require("src.battle.BattleState")
  local ok, battle = pcall(BattleState.newWild, game, "PIKACHU", 17)
  if not ok or not battle or battle.dead then
    -- species ids are the data file's own; if PIKACHU is not one of them the
    -- party's own lead is still a mon and still answers every question here
    log("newWild(PIKACHU) failed: " .. tostring(battle))
    local party = game.player and game.player.party
    if party and party[1] then dump("party[1]", party[1]) end
    logf:close(); love.event.quit(); return
  end
  game.overworld:pushBattle(battle)
  wait(240)

  local top = game.stack and game.stack:top()
  log("stack top is battle: " .. tostring(top == battle))
  log("battle.phase = " .. tostring(battle.phase))
  log("")

  dump("battle", battle)
  log("")
  for _, side in ipairs({ "player", "enemy" }) do
    local s = battle[side]
    if s then
      dump("battle." .. side, s)
      if s.mon then
        log("")
        dump("battle." .. side .. ".mon", s.mon)
      end
    else
      log("battle." .. side .. " = nil")
    end
    log("")
  end

  -- and the species record the name would come from
  local mon = battle.enemy and battle.enemy.mon
  if mon and mon.species and game.data and game.data.pokemon then
    dump("data.pokemon[" .. tostring(mon.species) .. "]",
         game.data.pokemon[mon.species])
  end

  logf:close()
  love.event.quit()
end
