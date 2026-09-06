-- Probe: WHAT DOES THE WATER LOOK LIKE. Pure screenshots, no numbers.
--
-- Pins weather / hour / rungs, stands on the bank that faces the most water
-- each map has, waits for the 3D pass (Voxel3D.lampLights poll, never a
-- frame count), lets the tint ramp settle, and shoots. The lake gets the
-- full ladder: RES 1/2 and FULL, WATER FLAT / CALM / SWELL, RTX rt / off,
-- day / dusk / night. Every shot waits for the capture callback (the
-- scheduled-shot race, see tests/ambient_occlusion_probe.lua).
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/water_look_probe.lua ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/water_look_probe.log", "w"))
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
    log("shot", name, done and "ok" or "TIMEOUT")
  end
  local function finish(msg)
    if msg then log(msg) end
    logf:close()
    love.event.quit()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then return finish("FAIL: no overworld") end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then return finish("FAIL: TERRARIUM not loaded") end
  log("version:", exports.TERRARIUM.version)

  local function tryRequire(name)
    local ok, m = pcall(lib.require, name)
    return ok and m or nil
  end
  local Water     = lib.require("Water")
  local RayFX     = lib.require("RayFX")
  local Weather   = lib.require("Weather")
  local DayNight  = lib.require("DayNight")
  local Wind      = lib.require("Wind")
  local Quality   = lib.require("Quality")
  local Voxel3D   = lib.require("Voxel3D")
  local MarioCam  = tryRequire("MarioCam")
  local Pipelines = require("src.render.Pipelines")

  local function sync(setting, v)
    if setting then pcall(setting.sync, setting, v) end
  end
  sync(Weather.setting, "off")
  sync(DayNight.setting, "day")
  sync(Wind.setting, 2)          -- BREEZE
  sync(Quality.setting, 2)       -- RES 1/2, the default rung
  sync(RayFX.setting, "rt")
  sync(Water.setting, 0.8)       -- CALM, the default rung
  pcall(Pipelines.setLevel, "terrarium_voxel", 5)
  log("cam:", MarioCam and MarioCam.setting and tostring(MarioCam.setting:get()) or "n/a")
  log("window:", love.graphics.getWidth(), love.graphics.getHeight())

  local function wait3D(cap)
    for i = 1, (cap or 900) do
      if Voxel3D.lampLights ~= nil then return i end
      coroutine.yield()
    end
    return -1
  end

  -- the player walks on his own after setMap: wait for the cell to hold
  local function holdStill(frames)
    local p = game.overworld.player
    local lx, ly, same = nil, nil, 0
    for _ = 1, 600 do
      local x, y = p and p.cellX, p and p.cellY
      if x == lx and y == ly then same = same + 1 else same = 0 end
      lx, ly = x, y
      if same >= frames then return true end
      coroutine.yield()
    end
    return false
  end

  -- the bank cell with the most water IN FRAME. The camera looks north and
  -- down but the player sits in the upper third of the frame, so what the
  -- shot mostly shows is the ground SOUTH of them (the dumps below made
  -- that plain: a bank facing 429 cells of water north shot a street). So
  -- the window runs three rows north to nine rows south, and the bank has
  -- to touch water within two cells in any direction.
  local function bestBank(m)
    local best, bestN = nil, 0
    local W, H = m.width or 40, m.height or 40
    for cy = 3, H - 3 do
      for cx = 3, W - 3 do
        local near = false
        for dy = -2, 2 do
          for dx = -2, 2 do
            if m:inBounds(cx + dx, cy + dy) and m:isWaterCell(cx + dx, cy + dy) then
              near = true
            end
          end
        end
        if near and m:inBounds(cx, cy) and m:isWalkableCell(cx, cy)
           and not m:isWaterCell(cx, cy) then
          local cnt = 0
          for dy = -3, 9 do
            for dx = -8, 8 do
              local x, y = cx + dx, cy + dy
              if m:inBounds(x, y) and m:isWaterCell(x, y) then
                cnt = cnt + 1
              end
            end
          end
          if cnt > bestN then best, bestN = { cx, cy }, cnt end
        end
      end
    end
    return best, bestN
  end

  local MAPS = {
    { id = "ROUTE_25",       tag = "lake", extra = true },
    { id = "ROUTE_24",       tag = "river" },
    { id = "CERULEAN_CITY",  tag = "cerulean" },
    { id = "ROUTE_21",       tag = "sea" },
    { id = "PALLET_TOWN",    tag = "pond", extra = true },
    { id = "VERMILION_CITY", tag = "port" },
  }

  for _, m in ipairs(MAPS) do
    local ok = pcall(function() game.overworld:setMap(m.id, 5, 5, "up") end)
    if not ok then
      log(("[%s] SKIP: setMap failed"):format(m.id))
    else
      wait(30)
      local map = game.overworld.map
      local okB, at, cnt = pcall(bestBank, map)
      if not (okB and at) then
        log(("[%s] SKIP: no bank (%s)"):format(m.id, tostring(at)))
      else
        log(("[%s] bank %d,%d faces %d water cells"):format(m.id, at[1], at[2], cnt))
        -- the neighbourhood as the map sees it: W water, . walkable, # not,
        -- @ the bank chosen. Written because a bank the map swears faces a
        -- lake shot a street twice in a row.
        for y = at[2] - 4, at[2] + 10 do
          local row = {}
          for x = at[1] - 12, at[1] + 12 do
            local c = " "
            if map:inBounds(x, y) then
              if x == at[1] and y == at[2] then c = "@"
              elseif map:isWaterCell(x, y) then c = "W"
              elseif map:isWalkableCell(x, y) then c = "."
              else c = "#" end
            end
            row[#row + 1] = c
          end
          log(("  %3d %s"):format(y, table.concat(row)))
        end
        pcall(function() game.overworld:setMap(m.id, at[1], at[2], "up") end)
        Voxel3D.lampLights = nil
        local up = wait3D(900)
        holdStill(45)
        wait(200)
        local pl = game.overworld.player
        log(("[%s] 3D up after %s frames; shader=%s err=%s player=%s,%s"):format(
          m.id, tostring(up), tostring(Voxel3D.shader() ~= nil),
          tostring(Voxel3D.shaderError),
          tostring(pl and pl.cellX), tostring(pl and pl.cellY)))
        shot(m.tag .. "_day_calm_res2.png")
        sync(Quality.setting, 1); wait(150)
        shot(m.tag .. "_day_calm_full.png")
        do
          local t0, f0 = love.timer.getTime(), 0
          for _ = 1, 120 do coroutine.yield(); f0 = f0 + 1 end
          local dt = love.timer.getTime() - t0
          log(('[%s] FULL: %d updates in %.2fs, fps=%.1f'):format(
            m.id, f0, dt, love.timer.getFPS()))
        end
        if m.extra then
          sync(Water.setting, 0); wait(90)
          shot(m.tag .. "_day_flat_full.png")
          sync(Water.setting, 1.4); wait(90)
          shot(m.tag .. "_day_swell_full.png")
          sync(Water.setting, 0.8)
          sync(RayFX.setting, "off"); wait(200)
          shot(m.tag .. "_day_calm_full_nortx.png")
          sync(RayFX.setting, "rt"); wait(200)
          sync(DayNight.setting, "dusk"); wait(300)
          shot(m.tag .. "_dusk_calm_full.png")
          sync(DayNight.setting, "night"); wait(300)
          shot(m.tag .. "_night_calm_full.png")
          sync(DayNight.setting, "day"); wait(200)
        end
        sync(Quality.setting, 2); wait(60)
      end
    end
  end
  finish("done")
end
