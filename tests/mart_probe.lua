-- Probe: the Poke Mart (B06) rebuild -- the A/B rig for the shop voxel.
--
-- Parks the diorama camera in front of a Mart in three towns and shoots it
-- at three hours, plus a Pokemon Center frame as the quality bar to match
-- (B05 has been on the custom-PNG path since 2026-09-01; B06 was still the
-- generic tile extrusion, which the four-grey atlas can only ever render as
-- a grey box).
--
-- THE DOOR IS FOUND, NOT GUESSED. Standing on a cell copied out of
-- assets/docs/buildings/B06-unnamed-building.md put the camera in an alley
-- three runs running -- those tables are authoring coordinates, not the
-- overworld's. `map.def.warps` is what the game itself uses, so the probe
-- reads the warp whose destination names MART (the same test
-- lib/MiniMap.lua's landmarkKind makes) and stands `back` cells south of
-- it, facing up. Whatever the numbering is, the shop is in frame.
--
-- Traps this probe respects (memory: terrarium-probe-screenshot-race,
-- terrarium-underpass-visibility, terrarium-ambientlife-probe):
--   - the player DRIFTS on his own after setMap, so every shot waits for
--     the cell to hold still, never a frame count;
--   - A-FARM pushes directions into the press queue between frames, which
--     walks him back out again -- it is turned off;
--   - the 3D pass is polled up via Voxel3D.lampLights, never frame-counted;
--   - captureScreenshot is a CALLBACK: shooting and yielding N frames
--     photographs the NEXT state, so the shot waits on the callback's flag.
--
-- POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> MART_TAG=<tag> \
-- MART_LEVEL=<0..5> MART_BACK=<cells> \
-- POKEPORT_DRIVER=mods/TERRARIUM/tests/mart_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local TAG = os.getenv("MART_TAG") or "mart"
  local LEVEL = tonumber(os.getenv("MART_LEVEL") or "") or 3
  local BACK = tonumber(os.getenv("MART_BACK") or "") or 4
  local logf = assert(io.open(OUT .. "/" .. TAG .. "_probe.log", "w"))
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
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end
  log("version:", exports.TERRARIUM.version)

  local DayNight   = lib.require("DayNight")
  local Weather    = lib.require("Weather")
  local Voxel3D    = lib.require("Voxel3D")
  local Structures = lib.require("Structures")
  local Buildings  = lib.require("Buildings")
  local MiniMap    = lib.require("MiniMap")
  local AutoFarm   = lib.require("AutoFarm")
  local Pipelines  = require("src.render.Pipelines")

  Weather.setting:sync("off")
  DayNight.darkSetting:sync("deep")
  Pipelines.setLevel("terrarium_voxel", LEVEL)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  pcall(function() MiniMap.setting:setIndex(3, game) end)      -- OFF
  pcall(function() AutoFarm.setting:setIndex(1, game) end)     -- OFF
  local ww, wh = love.graphics.getDimensions()
  log(("window: %dx%d  voxelLevel=%d  back=%d"):format(ww, wh, LEVEL, BACK))

  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      done = true
    end)
    for _ = 1, 240 do
      if done then return true end
      coroutine.yield()
    end
    log("    WARN: screenshot callback never fired for " .. name)
    return false
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

  -- setMap DOES NOT GUARANTEE THE CELL. Ask for one the map will not stand
  -- a player on -- a wall, water, the shop's own footprint -- and the engine
  -- drops him on its fallback instead, silently: three runs of this probe
  -- shot the wrong building from (3,4) while every assert stayed green.
  -- So a placement is only accepted when the player is STILL THERE after
  -- the drift settles, and the vantage is searched for rather than assumed.
  local function place(id, x, y)
    pcall(function() game.overworld:setMap(id, x, y, "up") end)
    wait(40)
    if game.overworld.map.id ~= id then return false, "wrong map" end
    local ok, cell = lockCell(600)
    return ok and cell == (x .. "," .. y), cell
  end

  -- Walk out from the door until a cell holds: straight south first (the
  -- facade head-on), then one step to either side, which is what a corner
  -- lot leaves free.
  local function vantage(id, wx, wy, back)
    for _, d in ipairs({ 0, -1, 1, -2, 2 }) do
      for b = back, back + 3 do
        local ok, cell = place(id, wx + d, wy + b)
        if ok then return wx + d, wy + b end
        log(("    (%d,%d) refused -> %s"):format(wx + d, wy + b, tostring(cell)))
      end
    end
    return nil
  end

  -- WHERE THE BUILDING ACTUALLY IS. The warp table and the docs both gave
  -- coordinates that put the camera on the wrong building, so neither is
  -- trusted: `stamp` writes every quad of a `.tex` model into
  -- S.spriteQuads in WORLD pixels, and the model's own footprint is the
  -- one number that cannot be out of step with what got drawn. Cells are
  -- 16 world px (two 8px tiles either axis, lib/Buildings.lua's stamp).
  local function texBox(S, tex)
    if not (S and S.spriteQuads) then return nil end
    local x0, x1, z0, z1, n = 1e9, -1e9, 1e9, -1e9, 0
    for _, q in ipairs(S.spriteQuads) do
      if q.tex == tex then
        n = n + 1
        for i = 1, 4 do
          local c = q[i]
          if c[1] < x0 then x0 = c[1] end
          if c[1] > x1 then x1 = c[1] end
          if c[3] < z0 then z0 = c[3] end
          if c[3] > z1 then z1 = c[3] end
        end
      end
    end
    if n == 0 then return nil end
    return x0, x1, z0, z1, n
  end

  local MART_TEX = "assets/buildings/mart_facade.png"
  local CENTER_TEX = "assets/buildings/ulithium_poke_center_mart.png"

  -- The warp the shop is behind, by destination name -- lib/MiniMap.lua's
  -- landmarkKind test, minus the icon. Kept as a fallback for a model that
  -- did not stamp (which is itself worth seeing in the log).
  local function findWarp(map, want)
    local warps = (map.def and map.def.warps) or {}
    for _, w in ipairs(warps) do
      local d = w.destMap
      if type(d) == "string" and d:upper():find(want, 1, true)
          and w.x and w.y then
        return w.x, w.y, d
      end
    end
    return nil
  end

  local SITES = {
    { id = "LAVENDER_TOWN", want = "MART",       what = "mart"   },
    { id = "PEWTER_CITY",   want = "MART",       what = "mart"   },
    { id = "VIRIDIAN_CITY", want = "MART",       what = "mart"   },
    { id = "CERULEAN_CITY", want = "MART",       what = "mart"   },
    -- the bar to match: B05, already on a custom PNG
    { id = "PEWTER_CITY",   want = "POKECENTER", what = "center" },
  }
  local HOURS = { "day", "dawn", "night" }

  -- MART_SWEEP=1: one town, every rung x every stand-back, so the framing
  -- is chosen from evidence instead of guessed a fourth time.
  if os.getenv("MART_SWEEP") == "1" then
    local s = { id = os.getenv("MART_MAP") or "CERULEAN_CITY",
                want = "MART", what = "mart" }
    pcall(function() game.overworld:setMap(s.id, 5, 5, "down") end)
    wait(40)
    local okS0, S0 = pcall(Structures.forMap, game.overworld.map)
    local bx0, bx1, _, bz1 = nil, nil, nil, nil
    if okS0 and S0 then bx0, bx1, _, bz1 = texBox(S0, MART_TEX) end
    local wx, wy
    if bx0 then
      wx, wy = math.floor((bx0 + bx1) / 2 / 16), math.floor(bz1 / 16)
    else
      wx, wy = findWarp(game.overworld.map, s.want)
    end
    log(("sweep %s door cell (%s,%s)"):format(s.id, tostring(wx), tostring(wy)))
    for _, lvl in ipairs({ 3, 4, 5 }) do
      Pipelines.setLevel("terrarium_voxel", lvl)
      for _, bk in ipairs({ 3, 5, 7 }) do
        local px, py = vantage(s.id, wx, wy, bk)
        log(("  rung=%d back=%d -> stand (%s,%s)")
            :format(lvl, bk, tostring(px), tostring(py)))
        if px then
          voxelUp()
          game.input.pressQueue[#game.input.pressQueue + 1] = "up"
          wait(150)
          shot(("%s_r%d_b%d.png"):format(TAG, lvl, bk))
        end
      end
    end
    log("sweep done -- " .. OUT)
    logf:close(); love.event.quit(); return
  end

  for _, s in ipairs(SITES) do
    DayNight.setting:sync("day")
    -- Land anywhere on the map first: the warp table lives on map.def, and
    -- map.def is only loaded once the map is.
    local ok = pcall(function() game.overworld:setMap(s.id, 5, 5, "down") end)
    if not ok then
      log(s.id, s.what, "FAIL: setMap error")
    else
      wait(40)
      local map = game.overworld.map
      local okS0, S0 = pcall(Structures.forMap, map)
      local tex = s.what == "mart" and MART_TEX or CENTER_TEX
      local bx0, bx1, bz0, bz1, bn = nil, nil, nil, nil, 0
      if okS0 and S0 then bx0, bx1, bz0, bz1, bn = texBox(S0, tex) end
      local wx, wy, dest = findWarp(map, s.want)
      log("")
      if bx0 then
        -- centre of the footprint in x, its SOUTH edge in z: the camera
        -- is parked south of the player and looks north, so the facade is
        -- what ends up in frame.
        wx = math.floor((bx0 + bx1) / 2 / 16)
        wy = math.floor(bz1 / 16)
        log(("[%s/%s] %d quads, world x %d..%d z %d..%d -> door cell (%d,%d)")
            :format(s.id, s.what, bn, bx0, bx1, bz0, bz1, wx, wy))
      elseif wx then
        log(("[%s/%s] NOT STAMPED -- falling back to warp %s at (%d,%d)")
            :format(s.id, s.what, tostring(dest), wx, wy))
      end
      if not wx then
        log(("[%s/%s] FAIL: neither a stamped model nor a %s warp")
            :format(s.id, s.what, s.want))
      else
        local px, py = vantage(s.id, wx, wy, BACK)
        if not px then
          log("  FAIL: no standable vantage near the door")
          goto continue
        end
        log(("  stand (%d,%d)"):format(px, py))
        log("  voxel pass up:", voxelUp() and "PASS" or "FAIL")
        game.input.pressQueue[#game.input.pressQueue + 1] = "up"
        wait(180)

        local okS, S = pcall(Structures.forMap, map)
        if okS and S then
          log(("  objectQuads=%d spriteQuads=%d")
              :format(#S.objectQuads, S.spriteQuads and #S.spriteQuads or 0))
        end

        for _, h in ipairs(HOURS) do
          pcall(function() DayNight.setting:sync(h) end)
          wait(120)
          shot(("%s_%s_%s_%s.png"):format(TAG, s.what, s.id, h))
        end
      end
    end
    ::continue::
  end

  log("")
  log("Buildings.stats():")
  local okSt, stats = pcall(Buildings.stats)
  if okSt and stats then
    local keys = {}
    for k in pairs(stats) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local st = stats[k]
      -- OVERWORLD:6 is the Center, OVERWORLD:7 the Mart: the two numbers
      -- tools/mart_preview.py must reproduce for the parity check to mean
      -- anything.
      if st.voxels and (k == "OVERWORLD:6" or k == "OVERWORLD:7") then
        log(("  %-16s voxels=%-8d shell=%-7d quads=%d")
            :format(k, st.voxels, st.shell, st.quads))
      end
    end
  else
    log("  FAIL:", tostring(stats))
  end

  local shader = Voxel3D.shader()
  log("")
  log("voxel shader:", shader and "PASS" or "FAIL", tostring(Voxel3D.shaderError))
  log("lastError:", tostring(Buildings.lastError))
  log("done -- " .. OUT)
  logf:close()
  love.event.quit()
end
