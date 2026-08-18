-- Probe: F0 baseline for the premium building kit (see
-- assets/docs/buidling_to_voxel/premium_kit_plan.md).
--
-- Captures the BEFORE state every later phase is judged against:
--   1. Reference screenshots: 4 cities x 3 pinned hours (dawn/day/night),
--      anchored to a logged player cell so future A/Bs can reuse the frame.
--   2. Buildings.stats() -- voxels/shell/quads per built model, the Lua half
--      of the parity check tools/building_voxels.py restates in Python.
--   3. Per-city objectQuads totals from Structures.forMap.
--   4. Voxel shader status (the silent-2D-fallback trap: a broken shader
--      keeps every assert green while the screenshots show the old world).
--
-- Traps this probe respects (memory: terrarium-ambientlife-probe,
-- terrarium-prop-bake-and-probe, terrarium-underpass-visibility):
--   - hour is pinned with DayNight.setting:sync(mode), never .clock;
--   - the 3D pass is polled up via Voxel3D.lampLights, never frame-counted;
--   - the player walks on his own after setMap, so shots wait for the cell
--     to hold still 45 consecutive frames;
--   - ~200 frames of settle before shooting so the tint ramp is done.
--
-- POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
-- POKEPORT_DRIVER=mods/TERRARIUM/tests/buildings_baseline_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/buildings_baseline_probe.log", "w"))
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

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit()
    return
  end
  log("version:", exports.TERRARIUM.version)

  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local Voxel3D = lib.require("Voxel3D")
  local Structures = lib.require("Structures")
  local Buildings = lib.require("Buildings")
  local StreetLamps = lib.require("StreetLamps")

  -- Pin everything that would make two runs of this probe disagree.
  Weather.setting:sync("off")
  DayNight.darkSetting:sync("deep")
  StreetLamps.setting:sync(true)
  local ww, wh = love.graphics.getDimensions()
  log(("window: %dx%d"):format(ww, wh))

  local function shot(name)
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
    wait(10)
  end

  -- The 3D pass is not up when setMap returns; lampLights is only filled
  -- by VoxelScene.render, so poll it instead of counting frames.
  local function voxelUp(guard)
    for _ = 1, guard or 900 do
      if Voxel3D.lampLights ~= nil then return true end
      coroutine.yield()
    end
    return false
  end

  -- The player drifts for ~300 frames after setMap. Wait by CONDITION:
  -- 45 consecutive frames in one cell, or the shot anchors to nothing.
  local function lockCell(guard)
    local last, stable = nil, 0
    for _ = 1, guard or 1200 do
      local p = game.overworld.player
      local cur = p and (tostring(p.cellX) .. "," .. tostring(p.cellY)) or "?"
      if cur == last then stable = stable + 1 else stable, last = 0, cur end
      if stable >= 45 then return true, cur end
      coroutine.yield()
    end
    return false, last
  end

  local CITIES = {
    { id = "PALLET_TOWN", x = 10, y = 11 },
    { id = "LAVENDER_TOWN", x = 10, y = 10 },
    { id = "VERMILION_CITY", x = 10, y = 10 },
    { id = "CELADON_CITY", x = 10, y = 10 },
  }
  local HOURS = { "dawn", "day", "night" }

  for _, c in ipairs(CITIES) do
    -- always arrive in daylight so every city runs the same ramp
    DayNight.setting:sync("day")
    local ok = pcall(function()
      game.overworld:setMap(c.id, c.x, c.y, "down")
    end)
    if not ok then
      log(c.id, "FAIL: setMap error")
    else
      wait(60)
      local map = game.overworld.map
      if map.id ~= c.id then
        log(("%s FAIL: landed on %s"):format(c.id, tostring(map.id)))
      else
        log("")
        log(("[%s] anchor asked (%d,%d)"):format(c.id, c.x, c.y))
        log("  voxel pass up:", voxelUp() and "PASS" or "FAIL")
        local locked, cell = lockCell()
        log(("  player cell locked: %s at (%s)")
            :format(locked and "PASS" or "FAIL", tostring(cell)))
        wait(200)

        local S = Structures.forMap(map)
        local own = 0
        for _, q in ipairs(S.objectQuads) do
          if q.own then own = own + 1 end
        end
        log(("  objectQuads=%d (building own=%d)")
            :format(#S.objectQuads, own))

        for _, h in ipairs(HOURS) do
          DayNight.setting:sync(h)
          wait(120)
          local okTod, tod = pcall(DayNight.tod)
          log(("  hour=%s tod=%s"):format(h, okTod and tostring(tod) or "?"))
          shot(("%s_%s.png"):format(c.id, h))
        end
      end
    end
  end

  -- The Lua half of the Stage 5 parity check, accumulated over every
  -- tileset the four cities loaded. Keys are "<tileset>:<index>".
  log("")
  log("Buildings.stats():")
  local stats = Buildings.stats()
  local keys = {}
  for k in pairs(stats) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local s = stats[k]
    if s.voxels then
      log(("  %-28s voxels=%-8d shell=%-7d quads=%d")
          :format(k, s.voxels, s.shell, s.quads))
    else
      -- claimOnly templates (the tower's ROUTE_10 roof half) cache an
      -- empty model: cells claimed, nothing stamped, no counts to print
      log(("  %-28s claimOnly"):format(k))
    end
  end

  local shader = Voxel3D.shader()
  log("")
  log("voxel shader:", shader and "PASS" or "FAIL",
      tostring(Voxel3D.shaderError))
  log("done -- " .. OUT)
  logf:close()
  love.event.quit()
end
