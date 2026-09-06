-- Probe: the mon pack serves the newer sprites into the staged battle.
--
--   1. PACK: assets/mons has front and back art for the two battlers
--      (MonPack.has answers true for both).
--   2. SERVED: once the fight is at the command menu, MonPack has served
--      sprites (debug.served > 0) and the last key is the foe's.
--   3. TEXTURE: the side textures are DENSITY x the GB frame.
--   4. COLOUR: the enemy's texture holds more than four distinct opaque
--      colours -- a two-bit pic through a palette never can, a Gen 5
--      sprite always does. (The proof that no palette remap touched it.)
--   Shots: monpack_menu.png, monpack_attack.png.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=<abs path>/tests/monpack_probe.lua ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/monpack.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local pending = {}
  local function shot(name)
    local done, data = false, nil
    love.graphics.captureScreenshot(function(d) data = d; done = true end)
    for _ = 1, 120 do
      if done then pending[#pending + 1] = { name = name, data = data } return data end
      coroutine.yield()
    end
    log("WARN: screenshot " .. name .. " never called back")
  end
  local function flushShots()
    for _, p in ipairs(pending) do
      local f = io.open(OUT .. "/" .. p.name, "wb")
      if f then f:write(p.data:encode("png"):getString()) f:close() end
    end
  end
  local function verdict(okv, name, detail)
    log((okv and "PASS: " or "FAIL: ") .. name .. "  " .. (detail or ""))
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit() return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end
  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return end
  local MonPack = lib.require("MonPack")
  local OB = lib.require("OverworldBattle")
  local DayNight = lib.require("DayNight")
  DayNight.setting:sync("day")

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
  if not press("a", "menu") then
    log("FAIL: never reached the command menu"); logf:close(); love.event.quit(); return
  end
  battle.menuIndex = 1
  wait(40)

  local eSp = battle.enemy and battle.enemy.mon and battle.enemy.mon.species
  local pSp = battle.player and battle.player.mon and battle.player.mon.species
  verdict(MonPack.has(eSp, false) and MonPack.has(pSp, true),
          "the pack has both battlers",
          ("enemy=%s back=%s"):format(tostring(eSp), tostring(pSp)))
  local d = MonPack.debug()
  verdict((d.served or 0) > 0, "the pack served sprites into the fight",
          ("served=%d missed=%d last=%s"):format(d.served or 0, d.missed or 0,
                                                 tostring(d.lastKey)))
  local tex = OB.textures(battle)
  local cw, ch = 0, 0
  if tex and tex.enemy and tex.enemy.canvas then
    cw, ch = tex.enemy.canvas:getDimensions()
  end
  verdict(cw == 160 * (MonPack.DENSITY or 1), "the texture is DENSITY x the GB frame",
          ("%dx%d"):format(cw, ch))
  -- the colour count
  local distinct = 0
  if tex and tex.enemy and tex.enemy.canvas then
    local okD, data = pcall(tex.enemy.canvas.newImageData, tex.enemy.canvas)
    if okD and data then
      local seen = {}
      for y = 0, ch - 1, 2 do
        for x = 0, cw - 1, 2 do
          local r, g, b, a = data:getPixel(x, y)
          if a > 0.5 then
            local k = math.floor(r * 31) * 1024 + math.floor(g * 31) * 32 + math.floor(b * 31)
            if not seen[k] then seen[k] = true; distinct = distinct + 1 end
          end
        end
      end
    end
  end
  verdict(distinct > 6, "the foe's texture is full colour (no palette remap)",
          ("distinct opaque colours: %d"):format(distinct))
  shot("monpack_menu.png")

  -- the animation: the foe's frame index moves over a second, and the
  -- texture's pixels change between two shots a beat apart
  local f0 = MonPack.frameOf(eSp, false)
  local d0 = MonPack.debug()
  wait(30)
  local f1 = MonPack.frameOf(eSp, false)
  local d1 = MonPack.debug()
  verdict((d1.live or 0) >= 2 and f1 ~= f0 and (d1.frames or 0) > (d0.frames or 0),
          "the mons are animated (frames advance)",
          ("live=%d frame %d -> %d painted %d -> %d"):format(d1.live or 0, f0, f1,
                                                            d0.frames or 0, d1.frames or 0))
  shot("monpack_frame2.png")

  -- through a move, for the attack shot
  if press("a", "moveSelect") then battle.moveIndex = 1; wait(8); tap("a") end
  local shotAtk = false
  local menuRun = 0
  for i = 1, 1200 do
    if battle.animPlaying and not shotAtk then wait(10); shot("monpack_attack.png"); shotAtk = true end
    if battle.dead then break end
    menuRun = (battle.phase == "menu") and (menuRun + 1) or 0
    if menuRun >= 12 then break end
    if battle.phase == "messages" and not battle.animPlaying and i % 40 == 0 then
      game.input.pressQueue[#game.input.pressQueue + 1] = "a"
    end
    coroutine.yield()
  end
  if not shotAtk then shot("monpack_attack.png") end
  flushShots()
  logf:close()
  love.event.quit()
end
