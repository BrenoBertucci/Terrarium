-- THE TREES STANDING IN THE DOORWAY.
--
-- A map's border ring is a wall of trees, and where two maps connect the
-- ring of one runs straight across the walkable strip of the other. The
-- 2D path never showed it (neighbour bodies were painted OVER the ring)
-- and the 3D path already knows about it: VoxelScene hands ChunkMesher a
-- list of neighbour-body rects and every ring quad inside one is dropped
-- -- ground, hull and prop alike.
--
-- Authored trees are the hole in that. Structures records a site instead
-- of a hull (buildCylinders), Trees3D builds its mesh straight off
-- S.treeSites, and that list has never been near a mask. So the ring's
-- MODELLED trees survive exactly where its hulls were deleted, and they
-- stand in the gate.
--
-- What this measures, per seam, is that census: how many of a map's sites
-- sit under a connected neighbour's body. The fix drives it to zero. The
-- pictures are taken standing IN the gate cell -- found by scanning the
-- edge row for a walkable cell, not hardcoded -- because that is the spot
-- the complaint is about and the orbit camera frames the player wherever
-- it happens to be pointing.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local TAG = os.getenv("DS_PROBE_TAG") or "tp"
  local logf = assert(io.open(OUT .. "/treepath_" .. TAG .. ".log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring((select(i, ...))) end
    logf:write(table.concat(p, " ") .. "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local fails = 0
  local function check(ok, msg)
    log((ok and "PASS " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: never booted"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    game.input.pressQueue[#game.input.pressQueue + 1] = "a"
    wait(10); n = n + 11
    if n > 1500 then break end
  end

  local lib = game.mods.exports.TERRARIUM.lib
  local Voxel3D  = lib.require("Voxel3D")
  local Trees3D  = lib.require("Trees3D")
  local DayNight = lib.require("DayNight")
  local Structures = lib.require("Structures")

  pcall(function() Trees3D.setting:sync("voxel") end)
  pcall(function() Trees3D.onOptionsChanged("voxel") end)
  pcall(function() DayNight.setting:sync("day") end)
  pcall(function() lib.require("Weather").setting:sync("off") end)
  wait(30)
  log(string.format("row=%s clock=%s t=%.0f", tostring(Trees3D.setting:get()),
                    tostring(DayNight.setting:get()), tonumber(DayNight.time()) or -1))

  local function meshQueue()
    local ok, q = pcall(function()
      local CM = lib.require("ChunkMesher")
      return CM.pending and CM.pending() or 0
    end)
    return (ok and tonumber(q)) or 0
  end

  -- poll for "ready", never a fixed count (voxeltree_probe's shape)
  local function settle(label, maxTicks)
    maxTicks = maxTicks or 4000
    local ticks, live, state = 0, false, "?"
    while true do
      if Voxel3D.lampLights ~= nil then live = true end
      local done
      done, state = Trees3D.ready(game.overworld and game.overworld.map)
      if live and (done or state == "hulls") then break end
      if ticks >= maxTicks then log("WARN: settle " .. label .. " stuck at " .. ticks); break end
      coroutine.yield(); ticks = ticks + 1
    end
    local owed, queued = select(2, Trees3D.buildsInFlight()), meshQueue()
    local waited = 0
    while (owed > 0 or queued > 0) and waited < 900 do
      coroutine.yield(); ticks, waited = ticks + 1, waited + 1
      owed, queued = select(2, Trees3D.buildsInFlight()), meshQueue()
    end
    log(string.format("  settled %s in %d ticks (state=%s)", label, ticks, tostring(state)))
    return state
  end

  -- wait on the CALLBACK, never on a frame count
  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(d)
      local f = io.open(OUT .. "/" .. name .. ".png", "wb")
      if f then f:write(d:encode("png"):getString()); f:close() end
      done = true
    end)
    local guard = 0
    while not done and guard < 240 do coroutine.yield(); guard = guard + 1 end
    if not done then log("WARN: shot " .. name .. " never landed") end
  end

  -- Where the directly connected maps SIT, in this map's world pixels.
  -- The engine's own walk, at one hop: same arithmetic the scene places
  -- neighbours with, so a rect here and a mask there cannot disagree.
  local function neighbourRects(map)
    local out = {}
    local ok = pcall(function()
      local Game = require("src.core.Game")
      local OC = require("src.world.OverworldController")
      for _, nb in ipairs(OC.computeNeighbors(Game.data.maps, map.id, 1) or {}) do
        local d = Game.data.maps[nb.id]
        if d then
          out[#out + 1] = { nb.ox, nb.oy, nb.ox + d.width * 32, nb.oy + d.height * 32, id = nb.id }
        end
      end
    end)
    if not ok then log("  WARN: neighbourRects failed") end
    return out
  end

  -- THE CENSUS. A site's { mx, mz, r } is its own cell footprint (r is the
  -- half-cell, 8 or 16), so the same strict-overlap test ChunkMesher's
  -- `masked` runs on a ring TILE answers for a site.
  local function census(map)
    local S = Structures.forMap(map)
    local sites = (S and S.treeSites) or {}
    local rects = neighbourRects(map)
    local bw, bh = map.def.width * 32, map.def.height * 32
    local ring, invading, per = 0, 0, {}
    for _, s in ipairs(sites) do
      local x0, z0, x1, z1 = s.mx - s.r, s.mz - s.r, s.mx + s.r, s.mz + s.r
      local inBody = x1 > 0 and x0 < bw and z1 > 0 and z0 < bh
      if not inBody then ring = ring + 1 end
      for _, mk in ipairs(rects) do
        if x1 > mk[1] and x0 < mk[3] and z1 > mk[2] and z0 < mk[4] then
          invading = invading + 1
          per[mk.id] = (per[mk.id] or 0) + 1
          break
        end
      end
    end
    local parts = {}
    for id, c in pairs(per) do parts[#parts + 1] = id .. "=" .. c end
    table.sort(parts)
    log(string.format("  CENSUS %s: sites=%d ring=%d INVADING=%d  [%s]",
                      map.id, #sites, ring, invading, table.concat(parts, " ")))
    for _, mk in ipairs(rects) do
      log(string.format("    neighbour %s at (%d,%d)..(%d,%d)", mk.id, mk[1], mk[2], mk[3], mk[4]))
    end
    return invading, #sites
  end

  -- The gate is wherever the edge row is WALKABLE -- found, not hardcoded,
  -- because a hardcoded column that drifts one cell photographs a wall.
  local function gateOn(map, dir)
    local w = map.widthCells or (map.def.width * 2)
    local h = map.heightCells or (map.def.height * 2)
    local function walk(cx, cy)
      local ok, yes = pcall(map.isWalkableCell, map, cx, cy)
      return ok and yes
    end
    local run, best = {}, nil
    local function flush()
      if #run > 0 and (not best or #run > #best) then best = run end
      run = {}
    end
    if dir == "south" or dir == "north" then
      local cy = (dir == "south") and (h - 1) or 0
      for cx = 0, w - 1 do
        if walk(cx, cy) then run[#run + 1] = cx else flush() end
      end
      flush()
      if not best then return nil end
      local cx = best[math.ceil(#best / 2)]
      return cx, cy, #best
    else
      local cx = (dir == "east") and (w - 1) or 0
      for cy = 0, h - 1 do
        if walk(cx, cy) then run[#run + 1] = cy else flush() end
      end
      flush()
      if not best then return nil end
      local cy = best[math.ceil(#best / 2)]
      return cx, cy, #best
    end
  end

  -- Face INTO the seam so the orbit camera has the doorway in front of the
  -- player rather than behind the lens.
  local FACE = { north = "up", south = "down", west = "left", east = "right" }

  local SEAMS = {
    { "VIRIDIAN_CITY", "south" },   -- -> ROUTE_1
    { "ROUTE_1",       "north" },   -- -> VIRIDIAN_CITY
    { "ROUTE_1",       "south" },   -- -> PALLET_TOWN
    { "PALLET_TOWN",   "north" },   -- -> ROUTE_1
    { "VIRIDIAN_CITY", "north" },   -- -> ROUTE_2 (the gate)
    { "ROUTE_2",       "south" },   -- -> VIRIDIAN_CITY
  }

  local totalInvading = 0
  for _, seam in ipairs(SEAMS) do
    local mapId, dir = seam[1], seam[2]
    log("---- " .. mapId .. " " .. dir)
    -- land somewhere legal first so the map object exists to be scanned
    local ok = pcall(function() game.overworld:setMap(mapId, 5, 5, "up") end)
    if not ok then
      log("  WARN: setMap " .. mapId .. " refused")
    else
      local map = game.overworld.map
      local conn = map.def.connections and map.def.connections[dir]
      log(string.format("  %s is %dx%d cells; %s -> %s offset %s", mapId,
                        map.widthCells or -1, map.heightCells or -1, dir,
                        tostring(conn and conn.map), tostring(conn and conn.offset)))
      local inv = census(map)
      totalInvading = totalInvading + inv
      local gx, gy, wide = gateOn(map, dir)
      if not gx then
        log("  WARN: no walkable cell on the " .. dir .. " edge -- no picture")
      else
        log(string.format("  gate at cell (%d,%d), %d cells wide", gx, gy, wide))
        pcall(function() game.overworld:setMap(mapId, gx, gy, FACE[dir] or "up") end)
        settle(mapId .. "/" .. dir)
        -- the player walks on his own after setMap; let him stop
        wait(45)
        local px, py = -1, -1
        pcall(function() px, py = game.overworld.player.cellX, game.overworld.player.cellY end)
        log(string.format("  shooting from (%d,%d)", px, py))
        shot(string.format("treepath_%s_%s_%s", TAG, mapId:lower(), dir))
      end
    end
  end

  check(totalInvading == 0,
        "no site stands under a connected neighbour's body (total " .. totalInvading .. ")")

  log(fails == 0 and "ALL PASS" or ("FAILS: " .. fails))
  log("done")
  logf:close()
  love.event.quit()
end
