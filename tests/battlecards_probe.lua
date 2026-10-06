-- Probe: the arena floor and the move cards (voxel slabs, pixel-art life),
-- in one fight.
--
--   1. The arena's ground is really there: the painted ground worlds
--      (LavenderGroundKit) claim their cells away from the mesher and stand
--      as sprite groups, so a battle that skipped those groups showed the
--      sky through the floor. Logged: how many groups the arena map has,
--      and the shot `arena_menu.png`.
--   2. The hand draws as voxel slabs (BattleCardVoxel) with the type's
--      pixel-art aura on the raised card: `cards_<i>.png` walking the hand,
--      `type_<T>.png` for every type, the throw in `launch_*.png`, and the
--      cost with the dressing on and off.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/battlecards_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/battlecards.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  -- ImageData kept, encoded at the very end: an encode inside the callback
  -- stalls the game and every live effect ages through the stall
  local shots = {}
  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      shots[#shots + 1] = { name, data }
      done = true
    end)
    for _ = 1, 90 do
      if done then return end
      coroutine.yield()
    end
    log("WARN: screenshot " .. name .. " never called back")
  end
  local function quit()
    for _, s in ipairs(shots) do
      local f = io.open(OUT .. "/" .. s[1], "wb")
      if f then f:write(s[2]:encode("png"):getString()) f:close() end
    end
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
  if not lib then log("FAIL: TERRARIUM not loaded"); quit(); return end
  local ChunkMesher = lib.require("ChunkMesher")
  local DayNight = lib.require("DayNight")
  local want = os.getenv("DS_PROBE_HOUR") or "day"
  pcall(function() DayNight.setting:sync(want) end)

  local ow = game.overworld
  local map = ow and ow.map
  log("map=" .. tostring(map and map.def and (map.def.id or map.def.name)))
  wait(120)  -- the ground and the neighbours finish building
  shot("overworld.png")

  local BattleState = require("src.battle.BattleState")
  local ok, battle = pcall(BattleState.newWild, game,
                           os.getenv("DS_PROBE_FOE") or "PIDGEY", 22)
  if not (ok and battle) or battle.dead then
    log("FAIL: no battle " .. tostring(battle)); quit(); return
  end
  game.overworld:pushBattle(battle)

  local function waitPhase(wantPhase, cap)
    for _ = 1, (cap or 400) do
      if battle.phase == wantPhase then return true end
      coroutine.yield()
    end
    return false
  end
  local function press(b, wantPhase, cap)
    for _ = 1, 30 do
      if battle.phase == wantPhase then return true end
      tap(b); wait(12)
      if waitPhase(wantPhase, cap or 60) then return true end
    end
    return battle.phase == wantPhase
  end

  if not press("a", "menu") then
    log("FAIL: never reached the command menu (phase="
        .. tostring(battle.phase) .. ")")
    quit(); return
  end
  wait(60)
  local groups = ChunkMesher.spriteGroups(map) or {}
  log("arena spriteGroups=" .. #groups)
  shot("arena_menu.png")

  battle.menuIndex = 1
  wait(10)
  if not press("a", "moveSelect") then
    log("FAIL: never reached moveSelect (phase="
        .. tostring(battle.phase) .. ")")
    quit(); return
  end
  wait(12)
  shot("cards_deal.png")    -- mid-deal: the cards in flight
  wait(40)
  local okV, Vox = pcall(lib.require, "BattleCardVoxel")
  do
    local OB = lib.require("OverworldBattle")
    local okO, err = pcall(Vox.observe, battle, 0.016, OB.arena())
    log("observe direct: " .. tostring(okO) .. " " .. tostring(err))
  end
  local nMoves = #((battle.player and battle.player.curMoves) or {})
  for i = 1, nMoves do
    wait(30)
    local d = okV and Vox and Vox.debug and Vox.debug() or nil
    log(("card %d: slabs=%s fxverts=%s ribbons=%s parts=%s err=%s"):format(i,
        tostring(d and d.slabs), tostring(d and d.fxverts),
        tostring(d and d.ribbons), tostring(d and d.parts), tostring(d and d.err)))
    shot(("cards_%d.png"):format(i))
    tap("right"); wait(8)
    shot(("cards_%d_swap.png"):format(i))
  end
  -- ------- the cost, measured here on the machine it has to run on:
  -- mean frame time over the same stretch of the hand, voxels on then off
  local function meanDt(frames)
    local t0 = love.timer.getTime()
    wait(frames)
    return (love.timer.getTime() - t0) / frames * 1000
  end
  if okV and Vox then
    wait(20)
    local on = meanDt(120)
    Vox.ENABLED = false
    wait(20)
    local off = meanDt(120)
    Vox.ENABLED = true
    log(("cost: voxels on %.2f ms/frame, off %.2f ms/frame, delta %.2f"):format(
        on, off, on - off))
  end

  -- ------- the states: normal, selected, no PP, disabled
  do
    local moves = battle.player.curMoves
    local saved = {}
    for i, mv in ipairs(moves) do saved[i] = mv.pp end
    local savedDis = battle.player.disabledSlot
    if #moves >= 4 then
      moves[3].pp = 0
      battle.player.disabledSlot = 4
      wait(30)
      shot("states.png")
      for i, mv in ipairs(moves) do mv.pp = saved[i] end
      battle.player.disabledSlot = savedDis
      wait(10)
    end
  end

  -- ------- every type's crown, frame and matter on the raised card: the
  -- card's type is swapped under the fan (Box.typeName), the face text
  -- keeps its own -- this is a check on the voxels, not the faces
  local Box = lib.require("BattleBoxXY")
  local origType = Box.typeName
  local TYPES = { "NORMAL", "FIRE", "WATER", "GRASS", "ELECTRIC", "ICE",
                  "FIGHTING", "POISON", "GROUND", "FLYING", "PSYCHIC", "BUG",
                  "ROCK", "GHOST", "DRAGON" }
  for _, T in ipairs(TYPES) do
    Box.typeName = function() return T end
    wait(48)
    local d = okV and Vox and Vox.debug and Vox.debug() or {}
    log(("type %s: ribbons=%s fxverts=%s parts=%s err=%s"):format(T,
        tostring(d.ribbons), tostring(d.fxverts), tostring(d.parts), tostring(d.err)))
    shot(("type_%s.png"):format(T))
  end
  Box.typeName = function() return os.getenv("DS_PROBE_THROW") or "FIRE" end
  wait(40)

  -- confirm the move: the card leaves the hand toward the foe
  tap("a")
  wait(3); shot("launch_a.png")
  do
    local d = okV and Vox and Vox.debug and Vox.debug() or {}
    log(("after confirm: phase=%s launches=%s folds=%s flights=%s parts=%s"):format(
        tostring(battle.phase), tostring(d.launches), tostring(d.folds),
        tostring(d.flights), tostring(d.parts)))
  end
  wait(4); shot("launch_b.png")
  wait(4); shot("launch_c.png")
  wait(4); shot("launch_d.png")
  wait(4); shot("launch_e.png")
  wait(60); shot("after.png")
  Box.typeName = origType
  log("DONE")
  quit()
end
