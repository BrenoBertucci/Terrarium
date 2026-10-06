-- Probe: every CRT set on every kind of screen, as screenshots.
--
-- The title (or whatever the boot is showing), the 2D map, the 3D map, the
-- OPTIONS menu with the CRT row under the cursor, a 3D battle with the move
-- cards up, and the cabinet (CRT FRAME) by day and by night with GLOW on.
-- Each set is FORCED on (CRT.force: no power-on moment, so the shot is the
-- set at rest) and given a few frames for the phosphor's persistence and the
-- room's light to settle. Screenshots wait for their own callback (see
-- tests/ambient_occlusion_probe.lua for why a fixed number of yields lies).
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/crt_probe.lua ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/crt_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
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
  local function quit(msg)
    if msg then log(msg) end
    for _, s in ipairs(shots) do
      local f = io.open(OUT .. "/" .. s[1], "wb")
      if f then f:write(s[2]:encode("png"):getString()) f:close() end
    end
    logf:close(); love.event.quit()
  end

  local W, H = tonumber(os.getenv("DS_W") or "1920"), tonumber(os.getenv("DS_H") or "1080")
  pcall(love.window.setMode, W, H, { resizable = true, vsync = 1 })
  wait(10)
  log("window", love.graphics.getPixelDimensions())

  -- the mod is loaded before the driver runs; the boot screen first
  local lib
  for _ = 1, 600 do
    local ex = game.mods and game.mods.exports
    lib = ex and ex.TERRARIUM and ex.TERRARIUM.lib
    if lib and game.stack and game.stack:top() then break end
    coroutine.yield()
  end
  if not lib then return quit("FAIL: TERRARIUM not loaded") end
  local CRT = lib.require("CRT")
  local Pipelines = require("src.render.Pipelines")
  local SETS = { "pvm", "trinitron", "home", "rf" }

  local function set(key, frameOn)
    CRT.setting:sync(key)
    CRT.frameSetting:sync(frameOn and "on" or "off")
    CRT.force(key ~= "off" and key or nil, false, nil)
    wait(12)
  end
  local function round(tag)
    for _, k in ipairs(SETS) do
      set(k, false)
      shot(("%s_%s.png"):format(tag, k))
    end
    set("off")
    shot(tag .. "_off.png")
  end

  wait(60)
  log("boot top", tostring(game.stack:top() and (game.stack:top().screenId or "?")))
  round("boot")
  log("refused", #CRT.refused, table.concat(CRT.refused, " | "))

  -- ------- into the world
  local n = 0
  while not (game.overworld and game.stack:top() == game.overworld) do
    tap("a"); wait(10); n = n + 11
    if n > 2500 then return quit("FAIL: never reached free roam") end
  end
  local ow = game.overworld
  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local Glow = lib.require("Glow")
  local ChunkMesher = lib.require("ChunkMesher")
  pcall(function() DayNight.setting:sync("day") end)
  pcall(function() Weather.setting:sync("off") end)
  local MAP, X, Y = os.getenv("DS_MAP") or "ROUTE_1", tonumber(os.getenv("DS_X") or "10"),
                    tonumber(os.getenv("DS_Y") or "18")
  local function settle()
    local quiet = 0
    for _ = 1, 1200 do
      if ChunkMesher.pending() == 0 then quiet = quiet + 1 else quiet = 0 end
      if quiet >= 45 then return end
      coroutine.yield()
    end
  end

  -- 2D
  Pipelines.setLevel("terrarium_voxel", 0)
  pcall(function() ow:setMap(MAP, X, Y, "down") end)
  game.input:reset()
  wait(90)
  round("map2d")

  -- 3D
  Pipelines.setLevel("terrarium_voxel", 4)
  pcall(function() ow:setMap(MAP, X, Y, "down") end)
  game.input:reset()
  wait(30); settle(); wait(30)
  round("map3d")

  -- the cabinet, by day and by night (GLOW on: the lamp is lit)
  for _, k in ipairs(SETS) do
    set(k, true)
    wait(60)        -- the room's light eases in
    shot(("frame_day_%s.png"):format(k))
  end
  pcall(function() DayNight.setting:sync("night") end)
  pcall(function() Glow.setting:sync(true) end)
  for _, k in ipairs({ "home", "trinitron" }) do
    set(k, true)
    wait(150)
    shot(("frame_night_%s.png"):format(k))
    set(k, false)
    wait(20)
    shot(("night_%s.png"):format(k))
  end
  pcall(function() DayNight.setting:sync("day") end)
  set("off")

  -- the OPTIONS menu, cursor on the CRT row
  local okM, OptionsMenu = pcall(require, "src.ui.OptionsMenu")
  if okM then
    local okN, menu = pcall(OptionsMenu.new, game)
    if okN and menu then
      game.stack:push(menu)
      wait(10)
      pcall(menu.focusRow, menu, "TERRARIUM:crt")
      wait(20)
      round("menu")
      game.stack:pop()
      wait(10)
    else
      log("WARN: OptionsMenu.new", tostring(menu))
    end
  end

  -- a 3D battle with the move cards up
  local BattleState = require("src.battle.BattleState")
  local okB, battle = pcall(BattleState.newWild, game, "PIDGEY", 22)
  if okB and battle and not battle.dead then
    ow:pushBattle(battle)
    local function waitPhase(want, cap)
      for _ = 1, (cap or 400) do
        if battle.phase == want then return true end
        coroutine.yield()
      end
      return false
    end
    local function press(b, want)
      for _ = 1, 30 do
        if battle.phase == want then return true end
        tap(b); wait(12)
        if waitPhase(want, 60) then return true end
      end
      return battle.phase == want
    end
    if press("a", "menu") then
      wait(60)
      round("battle_menu")
      battle.menuIndex = 1
      if press("a", "moveSelect") then
        wait(70)
        round("battle_cards")
      else
        log("WARN: no moveSelect", tostring(battle.phase))
      end
    else
      log("WARN: no battle menu", tostring(battle.phase))
    end
  else
    log("WARN: no battle", tostring(battle))
  end
  log("refused at end", #CRT.refused)
  quit("done")
end
