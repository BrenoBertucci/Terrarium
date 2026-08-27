-- Capture driver: silent footage of the battle HUD and the bag's pockets.
--
-- Not a probe -- it asserts nothing. It drives the game through the two
-- screens worth showing and writes one PNG per captured frame, for ffmpeg
-- to assemble afterwards.
--
-- WHY THE TIMING COMES OUT RIGHT even though this runs far slower than real
-- time: the driver is a coroutine that advances the game exactly one frame
-- per yield, so game time is counted in yields, not in wall clock. Encoding
-- a PNG between two yields stretches the wall clock and not the footage.
-- Capturing every SECOND frame and assembling at 30 fps therefore produces
-- an accurate 30 fps record of a 60 fps game, however long it takes to
-- write.
--
-- The party is padded with staged clones so the HUD shows every colour band
-- and the status chip in one shot, and it is restored before quitting --
-- the clones share the save's tables and must not outlive the capture.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/showcase_capture.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/showcase.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n")
    logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b
    coroutine.yield()
  end

  local frame = 0
  local function rec(n)
    for _ = 1, (n or 1) do
      frame = frame + 1
      local path = ("%s/f%05d.png"):format(OUT, frame)
      love.graphics.captureScreenshot(function(data)
        local f = io.open(path, "wb")
        if f then f:write(data:encode("png"):getString()) f:close() end
      end)
      wait(2)                      -- one captured frame per two game frames
    end
  end
  -- tap a button and keep filming through it
  local function tapRec(b, n)
    game.input.pressQueue[#game.input.pressQueue + 1] = b
    rec(n or 8)
  end
  local function bail(msg)
    log(msg); logf:close(); love.event.quit()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    coroutine.yield(); n = n + 1
    if n > 900 then return bail("FAIL: no overworld") end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end

  -- ------- a party that shows every band
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
  end
  local function restoreParty()
    for i = #party, realCount + 1, -1 do party[i] = nil end
  end

  local BattleState = require("src.battle.BattleState")
  local ok, battle = pcall(BattleState.newWild, game, "RATTATA", 9)
  if not (ok and battle) or battle.dead then
    restoreParty(); return bail("FAIL: no battle")
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

  -- ------- the battle HUD
  --
  -- Filmed through the intro rather than after it: the slide-in is part of
  -- what changed and a still frame of the finished layout does not show it.
  rec(90)
  if not press("a", "menu") then
    restoreParty()
    return bail("FAIL: no command menu (phase=" .. tostring(battle.phase) .. ")")
  end
  rec(45)
  log("battle HUD filmed, frames so far: " .. frame)

  -- walk the command cursor so the HUD is visibly live, not a screenshot
  for _, dir in ipairs({ "down", "right", "up", "left" }) do
    tapRec(dir, 14)
  end
  rec(20)

  -- ------- the bag, and its pockets
  battle.menuIndex = 3
  rec(12)
  tapRec("a", 45)
  local bag = game.stack:top()
  if not (bag and type(bag.items) == "table") then
    restoreParty(); return bail("FAIL: no bag on top")
  end
  log("bag open, frames so far: " .. frame)
  rec(30)

  -- RIGHT walks the pockets; UP/DOWN moves inside one. Two passes so the
  -- tab strip is seen changing more than once.
  for _ = 1, 2 do
    for _ = 1, 4 do
      tapRec("right", 26)
    end
    tapRec("down", 16)
    tapRec("down", 16)
    tapRec("up", 16)
  end
  rec(30)
  log("pockets filmed, total frames: " .. frame)

  restoreParty()
  log("done, frames=" .. frame)
  logf:close()
  wait(20)                          -- let the last encodes land
  love.event.quit()
end
