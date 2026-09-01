-- Probe: does one row really hold the whole costume?
--
-- Four measurable claims:
--   1. DINAMICA (the default): every module's gate is open and the
--      capsules hang in the WORLD (fresh world debug).
--   2. Flipping to CLASSICA mid-battle closes every gate, clears the
--      world placement and sends the capsules to the window corners.
--   3. A whole round fought under CLASSICA never re-enters the world
--      path -- the corner record stays the live one throughout.
--   4. Flipping back mid-battle reopens everything and the world
--      placement returns fresh.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/battledynamic_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/battledynamic.log", "w"))
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
  local Dyn = lib.require("BattleDynamic")
  local Capsule = lib.require("BattleCapsule")
  local OverworldBattle = lib.require("OverworldBattle")
  local DayNight = lib.require("DayNight")
  DayNight.setting:sync("day")

  local MODS = {
    { "BattleShot", "enabled" },
    { "BattleFanXY", "ENABLED" },
    { "BattlePanelsXY", "ENABLED" },
    { "BattleGlassFX", "ENABLED" },
    { "BattleRibbon", "ENABLED" },
    { "BattleHitFX", "ENABLED" },
  }
  local function gates()
    local open, closed = 0, 0
    for _, m in ipairs(MODS) do
      local M = lib.require(m[1])
      if M[m[2]] then open = open + 1 else closed = closed + 1 end
    end
    local Cap = lib.require("BattleCapsule")
    if Cap.WORLD then open = open + 1 else closed = closed + 1 end
    return open, closed
  end

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
    log((okv and "PASS: " or "FAIL: ") .. name .. "  " .. detail)
  end

  if not press("a", "menu") then
    log("FAIL: never reached the command menu (phase="
        .. tostring(battle.phase) .. ")")
    logf:close(); love.event.quit(); return
  end
  battle.menuIndex = 1
  wait(40)

  -- ------- claim 1: the default is the full costume
  local row = Dyn.setting:row()
  verdict(row and row.label == "COMBAT" and row.value() == "DINAMICA",
          "the COMBAT row exists and reads DINAMICA",
          ("label=%s value=%s"):format(tostring(row and row.label),
                                       tostring(row and row.value())))
  local open, closed = gates()
  local d = Capsule.debug()
  verdict(open == 7 and closed == 0, "every gate is open under DINAMICA",
          ("open=%d closed=%d"):format(open, closed))
  verdict(d and d.player ~= nil, "the capsules hang in the world", "")

  -- ------- claim 2: CLASSICA mid-battle
  Dyn.setting:sync("classic")
  Dyn.apply()
  wait(20)
  open, closed = gates()
  d = Capsule.debug()
  local corner = OverworldBattle._lastXY and OverworldBattle._lastXY.player
  verdict(open == 0 and closed == 7, "every gate closed under CLASSICA",
          ("open=%d closed=%d"):format(open, closed))
  verdict(not (d and d.player), "the world placement cleared", "")
  verdict(corner and corner.world ~= true and corner.x ~= nil,
          "the capsules fell back to the window corners",
          ("world=%s x=%s"):format(tostring(corner and corner.world),
                                   tostring(corner and corner.x)))
  shot("dyn_classic.png")

  -- ------- claim 3: a whole round under CLASSICA stays classic
  battle.menuIndex = 1
  if press("a", "moveSelect") then wait(8); tap("a") end
  local sawWorld = false
  local menuRun = 0
  for i = 1, 2400 do
    local rec = OverworldBattle._lastXY and OverworldBattle._lastXY.player
    if rec and rec.world then sawWorld = true end
    if battle.dead then log("battle ended at frame " .. i); break end
    menuRun = (battle.phase == "menu") and (menuRun + 1) or 0
    if menuRun >= 12 then
      log(("round resolved at frame %d"):format(i))
      break
    end
    coroutine.yield()
  end
  verdict(not sawWorld, "the round never re-entered the world path", "")

  -- ------- claim 4: and back, mid-battle
  Dyn.setting:sync("dynamic")
  Dyn.apply()
  wait(30)
  open, closed = gates()
  d = Capsule.debug()
  local rec = OverworldBattle._lastXY and OverworldBattle._lastXY.player
  verdict(open == 7 and closed == 0, "every gate reopened under DINAMICA",
          ("open=%d closed=%d"):format(open, closed))
  verdict(d and d.player ~= nil and rec and rec.world == true,
          "the world placement returned fresh", "")
  shot("dyn_back.png")

  logf:close()
  love.event.quit()
end
