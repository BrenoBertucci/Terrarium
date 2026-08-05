-- Probe: how many quads the body-only (neighbour) build drops now that
-- small-silhouette props (buildObject's q.lod-tagged prisms) and round-tree
-- stamps are skipped for bodyOnly builds -- ChunkMesher.lua's objectQuads
-- and roundStamps loops.
--
-- Structures.forMap never filters by bodyOnly -- it always computes the
-- full, untagged set. ChunkMesher's runGeometry is what drops q.lod quads
-- and skips roundStamps when bodyOnly is true. So the "before" count for
-- this change is exactly:
--   before = after + (lod-tagged objectQuads) + (all roundStamps quads)
-- measured on the SAME running process, no code revert needed.
--
-- Three numbers, not guessed:
--   1. quad/vertex counts, before vs after, per map (this is the mesh-byte
--      claim: vertices * 24 bytes, unindexed FFI sink format).
--   2. collectgarbage("count") after a full GC, before and after building.
--   3. Perf.texturememory, untouched by this change -- reported anyway so
--      a regression there would not hide behind "this wasn't touched".
--
-- POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
-- POKEPORT_DRIVER=mods/TERRARIUM/tests/mesh_lod_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/mesh_lod_probe.log", "w"))
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

  local Structures = lib.require("Structures")
  local ChunkMesher = lib.require("ChunkMesher")
  local Perf = lib.require("Perf")

  local function gc()
    collectgarbage("collect"); collectgarbage("collect")
    return collectgarbage("count")
  end

  local function measureMap(id, x, y, dir)
    game.overworld:setMap(id, x, y, dir)
    wait(240)
    local map = game.overworld.map
    if map.id ~= id then
      log(("  FAIL: asked for %s, landed on %s"):format(id, tostring(map.id)))
      return
    end

    local S = Structures.forMap(map)
    local lodQuads, totalObj = 0, #S.objectQuads
    for _, q in ipairs(S.objectQuads) do
      if q.lod then lodQuads = lodQuads + 1 end
    end
    local stampQuads, stampCount = 0, #(S.roundStamps or {})
    for _, st in ipairs(S.roundStamps or {}) do
      stampQuads = stampQuads + #st.quads
    end

    local heapBefore = gc()
    local verts, _, quads = ChunkMesher.geometry(map, true, nil)
    local heapAfter = gc()
    local afterVerts, afterQuads = #verts, quads
    local droppedQuads = lodQuads + stampQuads
    local beforeQuads = afterQuads + droppedQuads
    local beforeVerts = beforeQuads * 4    -- table-sink shape: 4 verts/quad
    -- bytes as the FFI sink actually uploads it: 6 unindexed verts/quad,
    -- 24 bytes/vertex (Voxel3D.FORMAT)
    local beforeBytes = beforeQuads * 6 * 24
    local afterBytes = afterQuads * 6 * 24

    log("")
    log(("[%s] objectQuads=%d (lod-tagged=%d)  roundStamps=%d stamps, "
         .. "%d quads"):format(id, totalObj, lodQuads, stampCount, stampQuads))
    log(("  body quads:  before=%d  after=%d  dropped=%d (%.1f%%)")
        :format(beforeQuads, afterQuads, droppedQuads,
                100 * droppedQuads / math.max(1, beforeQuads)))
    log(("  body verts:  before=%d  after=%d"):format(beforeVerts, afterVerts))
    log(("  body mesh bytes (unindexed, FFI sink): before=%d after=%d "
         .. "saved=%d"):format(beforeBytes, afterBytes,
                               beforeBytes - afterBytes))
    log(("  lua heap: before-gc=%.0fKB after-gc=%.0fKB")
        :format(heapBefore, heapAfter))
    log(("  Perf.texturememory=%s"):format(tostring(Perf.texturememory)))
  end

  measureMap("PALLET_TOWN", 5, 5, "down")
  measureMap("ROUTE_1", 10, 18, "down")
  measureMap("ROUTE_2", 10, 30, "down")
  measureMap("VIRIDIAN_CITY", 20, 30, "down")

  log("")
  log("done -- " .. OUT)
  logf:close()
  love.event.quit()
end
