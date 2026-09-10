-- Probe 4: how much of the terrain the culling box actually rejects, and
-- how much CHUNK_MARGIN and the ymax north-extension cost.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/geom_cull_probe.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
    logf:write(table.concat(p, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end
  local lib = game.mods.exports.TERRARIUM.lib
  local VoxelScene = lib.require("VoxelScene")
  local ChunkMesher = lib.require("ChunkMesher")
  local Pipelines = require("src.render.Pipelines")
  pcall(Pipelines.setLevel, "terrarium_voxel", 4)
  pcall(Pipelines.setLevel, "terrarium_tiltshift", 0)

  local M = 96   -- ChunkMesher.CHUNK_MARGIN
  local function verts(ch)
    local ok, v = pcall(ch.mesh.getVertexCount, ch.mesh)
    return (ok and v) or 0
  end
  local function count(group, b, shrink, useY)
    local nn, vv = 0, 0
    for _, ch in ipairs(group.chunks) do
      local x0, z0, x1, z1 = ch.x0, ch.z0, ch.x1, ch.z1
      if shrink then x0 = x0 + M; z0 = z0 + M; x1 = x1 - M; z1 = z1 - M end
      local top = useY and (ch.ymax or 0) or 0
      if x1 >= b[1] and x0 <= b[3] and z1 + top >= b[2] and z0 <= b[4] then
        nn = nn + 1; vv = vv + verts(ch)
      end
    end
    return nn, vv
  end

  local ow = game.overworld
  local MAPS = {
    { "ROUTE_1", 5, 18 }, { "ROUTE_2", 5, 25 }, { "ROUTE_17", 9, 60 },
    { "VIRIDIAN_CITY", 15, 15 }, { "PALLET_TOWN", 5, 6 }, { "ROUTE_22", 5, 5 },
  }
  for _, m in ipairs(MAPS) do
    pcall(function() ow:setMap(m[1], m[2], m[3], "down") end)
    local terrain
    for i = 1, 900 do
      coroutine.yield()
      terrain = ChunkMesher.peek(ow.map, false)
      if terrain and i > 120 then break end
    end
    wait(40)
    terrain = ChunkMesher.peek(ow.map, false) or ChunkMesher.peek(ow.map, true)
    log("")
    log("======== " .. m[1] .. " ========")
    if not terrain then log("  no mesh") else
      local lv = VoxelScene.lastView
      local tot, tv, maxv, sizes = 0, 0, 0, {}
      for _, ch in ipairs(terrain.chunks) do
        local v = verts(ch)
        tot = tot + 1; tv = tv + v; sizes[#sizes + 1] = v
        if v > maxv then maxv = v end
      end
      table.sort(sizes)
      log(("  view vw %.0f vh %.0f ; %d chunks, %d verts total, biggest %d, median %d")
          :format(lv[3], lv[4], tot, tv, maxv, sizes[math.ceil(#sizes / 2)] or 0))
      for _, forSun in ipairs({ false, true }) do
        local b = VoxelScene.bounds(lv[1], lv[2], lv[3], lv[4], forSun)
        local label = forSun and "SUN " or "SCENE"
        local a1, b1 = count(terrain, b, false, true)
        local a2, b2 = count(terrain, b, true, true)
        local a3, b3 = count(terrain, b, false, false)
        local a4, b4 = count(terrain, b, true, false)
        log(("  %s box %.0f x %.0f px"):format(label, b[3] - b[1], b[4] - b[2]))
        log(("    as shipped        kept %4d chunks / %8d verts (%.0f%% of map)")
            :format(a1, b1, 100 * b1 / math.max(tv, 1)))
        log(("    margin 96 removed kept %4d chunks / %8d verts (%.0f%%)")
            :format(a2, b2, 100 * b2 / math.max(tv, 1)))
        log(("    ymax reach off    kept %4d chunks / %8d verts (%.0f%%)")
            :format(a3, b3, 100 * b3 / math.max(tv, 1)))
        log(("    both              kept %4d chunks / %8d verts (%.0f%%)")
            :format(a4, b4, 100 * b4 / math.max(tv, 1)))
      end
    end
  end
  log("")
  log("DONE")
  logf:close()
  love.event.quit()
end
