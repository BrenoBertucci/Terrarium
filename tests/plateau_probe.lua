-- Probe: F5 of the premium building kit -- the PLATEAU templates.
--
-- Two models that never shipped before:
--   - indigo_plateau (B19): the retaining wall + League lobby, the first
--     `parts` template (two structures in one drawing);
--   - victory_road_gate (B23): ported from tools/building_voxels.py,
--     which always had it while the Lua data never did.
--
-- Asserts the models BUILD and STAMP (objectQuads own > 0, cells claimed
-- as "building"), dumps Buildings.stats() for the Stage 5 parity check
-- against tools/building_voxels.py, and shoots day + night screenshots
-- of both maps.
--
-- POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
-- POKEPORT_DRIVER=mods/TERRARIUM/tests/plateau_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/plateau_probe.log", "w"))
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

  Weather.setting:sync("off")
  DayNight.darkSetting:sync("deep")

  local function shot(name)
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
    wait(10)
  end

  local function voxelUp(guard)
    for _ = 1, guard or 900 do
      if Voxel3D.lampLights ~= nil then return true end
      coroutine.yield()
    end
    return false
  end

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

  local SPOTS = {
    -- B19 stands at (0,1); the doors are (9,5)/(10,5), so anchor south
    { id = "INDIGO_PLATEAU", x = 10, y = 8, claim = { 3, 2 } },
    -- B23 stands at (0,58) on ROUTE_23; anchor on the road below it
    { id = "ROUTE_23", x = 10, y = 61, claim = { 3, 59 } },
  }

  for _, c in ipairs(SPOTS) do
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
        log(("[%s] anchor (%d,%d)"):format(c.id, c.x, c.y))
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
        log(("  objectQuads=%d (building own=%d) %s")
            :format(#S.objectQuads, own,
                    own > 0 and "PASS" or "FAIL: nothing stamped"))

        -- the claim: a cell under the drawing must be class "building"
        local k = (c.claim[2] + 64) * 4096 + (c.claim[1] + 64)
        local sh = S.shapeAt[k]
        log(("  claim at (%d,%d): %s"):format(c.claim[1], c.claim[2],
            (sh and sh.class == "building") and "PASS"
            or ("FAIL: " .. tostring(sh and sh.class))))

        DayNight.setting:sync("day")
        wait(120)
        shot(c.id .. "_day.png")
        DayNight.setting:sync("night")
        wait(120)
        shot(c.id .. "_night.png")
      end
    end
  end

  log("")
  log("Buildings.stats():")
  local stats = Buildings.stats()
  local keys = {}
  for k in pairs(stats) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local s = stats[k]
    if s.voxels then
      log(("  %-24s voxels=%-8d shell=%-7d quads=%d")
          :format(k, s.voxels, s.shell, s.quads))
    else
      log(("  %-24s claimOnly"):format(k))
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
