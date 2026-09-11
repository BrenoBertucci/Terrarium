-- Probe: swimmers drag the water.
--
-- Counted at the Route 25 lake:
--   the water roamers the lake spawns are seen as SWIMMERS (WakeFX.swimmers)
--   and reach the sheet (Voxel3D.wake carries them);
--   they lay FOAM (StepFX motes of kind "foam" alive; WakeFX.foamEmitted);
--   the player, put on the water surfing and walked, gets a wake of their
--   own, SPLASHES going in and is left DRIPPING coming out.
-- And a shot of the lake with a swimmer on it.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/wake_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/wake_probe.log", "w"))
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
    local guard = 0
    while not done and guard < 240 do coroutine.yield(); guard = guard + 1 end
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
  game.input:reset()

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return end
  log("version:", exports.TERRARIUM.version)

  local WakeFX = lib.require("WakeFX")
  local StepFX = lib.require("StepFX")
  local Voxel3D = lib.require("Voxel3D")
  local WaterMap = lib.require("WaterMap")
  local RainOnFX = lib.require("RainOnFX")
  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local Pipelines = require("src.render.Pipelines")

  DayNight.setting:sync("day")
  Weather.setting:sync("none")
  Pipelines.setLevel("terrarium_voxel", 4)
  local okR, WR = pcall(lib.require, "WildRoamers")
  if okR and WR and WR.setting then pcall(WR.setting.sync, WR.setting, "on") end
  game.overworld:setMap("ROUTE_25", 37, 12, "down")
  wait(240)
  game.input:reset()
  log("gate:", WakeFX.lastGate, " error:", tostring(WakeFX.lastError))

  local function foamAlive()
    local c = 0
    for i = 1, StepFX.count() do
      local m = StepFX.get(i)
      if m and m.kind == "foam" then c = c + 1 end
    end
    return c
  end

  -- ------- 1. the lake's own swimmers
  local peakSw, peakWake, peakFoam, shotDone = 0, 0, 0, false
  for f = 1, 900 do
    coroutine.yield()
    local sw = WakeFX.swimmers
    local wk = Voxel3D.wake and #Voxel3D.wake or 0
    local fm = foamAlive()
    if sw > peakSw then peakSw = sw end
    if wk > peakWake then peakWake = wk end
    if fm > peakFoam then peakFoam = fm end
    if not shotDone and wk >= 1 and fm >= 4 then
      -- only a swimmer near the middle of the frame is worth a picture
      local pl = game.overworld.player
      local near = false
      for _, e in ipairs(Voxel3D.wake) do
        if math.abs(e[1] - (pl.px + 8)) < 70 and math.abs(e[2] - (pl.py + 8)) < 50 then near = true end
      end
      if near then shot("wake_roamer.png"); shotDone = true end
    end
  end
  log(("roamers: swimmers peak %d  wake entries peak %d  foam alive peak %d  foam emitted %d")
      :format(peakSw, peakWake, peakFoam, WakeFX.foamEmitted))
  if peakSw == 0 then log("  note: no water roamer showed up in 900 frames") end
  if peakSw > 0 and peakWake == 0 then log("  FAIL: swimmers seen but none reached the sheet") end
  if peakSw > 0 and WakeFX.foamEmitted == 0 then log("  FAIL: swimmers moved and laid no foam") end

  -- ------- 2. the player, surfing
  --
  -- Off Pallet Town: the sea south of it is open water with nothing
  -- between the camera and the swimmer (the Route 25 lake is fringed with
  -- trees on the side the camera stands on).
  game.overworld:setMap("PALLET_TOWN", 3, 17, "down")
  wait(200)
  game.input:reset()
  local p = game.overworld.player
  local map = game.overworld.map
  local wx, wy, best
  -- open water, nearest first: two cells of surface on every side, so the
  -- camera looks at the lake and not through a bank of trees
  for cy = p.cellY - 14, p.cellY + 14 do
    for cx = p.cellX - 14, p.cellX + 14 do
      if map:inBounds(cx, cy) then
        local clear, open = true, 0
        for dy = -2, 2 do
          for dx = -2, 2 do
            local w = map:inBounds(cx + dx, cy + dy) and WaterMap.surfaceCell(map, cx + dx, cy + dy)
            if w then open = open + 1 end
            if math.abs(dx) <= 1 and math.abs(dy) <= 1 and not w then clear = false end
          end
        end
        if clear then
          -- the most open water first, the nearest among equals
          local dd = (cx - p.cellX) ^ 2 + (cy - p.cellY) ^ 2
          local score = open * 1000 - dd
          if not best or score > best then best, wx, wy = score, cx, cy end
        end
      end
    end
  end
  if wx then
    local splashes0, exits0 = WakeFX.splashes, WakeFX.exits
    p.surfing = true
    game.overworld:setMap(map.id, wx, wy, "up")
    wait(120)
    p.surfing = true
    local peakP, peakF = 0, 0
    local dirs = { "down", "up", "left", "right" }
    for k = 1, 4 do
      local dir = dirs[k]
      for f = 1, 45 do
        game.input.state[dir] = true; coroutine.yield()
        local wk = Voxel3D.wake and #Voxel3D.wake or 0
        local fm = foamAlive()
        if wk > peakP then peakP = wk end
        if fm > peakF then peakF = fm end
        -- going north, the wake trails toward the camera: shoot mid-stride
        if k == 2 and f == 34 then shot("wake_player.png") end
      end
      game.input.state[dir] = false
    end
    game.input:reset()
    log(("player surfing at %d,%d (now %d,%d surfing=%s): wake entries peak %d  foam peak %d  splashes %d  exits %d  wet(player)=%.2f")
        :format(wx, wy, p.cellX, p.cellY, tostring(p.surfing), peakP, peakF,
                WakeFX.splashes - splashes0, WakeFX.exits - exits0, RainOnFX.wetOf(p)))
    if peakP == 0 then log("  note: the surfing player did not reach the sheet (did they move?)") end
    -- out of the water: put back on the bank (the flag alone is not
    -- leaving -- standing on a water cell keeps you surfing), and the
    -- figure should drip
    p.surfing = false
    game.overworld:setMap(map.id, 3, 17, "down")
    wait(20)
    p.surfing = false            -- the landing cell may have switched it back
    wait(45)
    log(("after leaving: exits %d  wet(player)=%.2f  surfing=%s cell=%d,%d gate=%s")
        :format(WakeFX.exits - exits0, RainOnFX.wetOf(p), tostring(p.surfing),
                p.cellX, p.cellY, tostring(WakeFX.lastGate)))
    if WakeFX.exits - exits0 < 1 then log("  FAIL: leaving the water was not seen") end
    if RainOnFX.wetOf(p) <= 0 then log("  FAIL: the player is not dripping after the water") end
  else
    log("no water cell in a straight line within 8 cells; player test skipped")
  end
  if WakeFX.lastError then log("  WakeFX error:", WakeFX.lastError) end
  if StepFX.lastError then log("  StepFX error:", StepFX.lastError) end
  log("done")
  logf:close()
  love.event.quit()
end
