-- Probe: does GRASS = 3D actually build a meadow, or throw into the mesh?
--
-- The earlier grass_row_probe held 240 frames with the row on 3D and
-- reported "survived". It did, because nothing REMESHED: Structures.buildGrass
-- only runs when a chunk is built, and the maps were already cached. The
-- throw lives in that build, so a probe that does not invalidate cannot see
-- it. This one invalidates and then waits for the rebuild.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/grass3d_repro_probe.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
    logf:write(table.concat(p, " ") .. "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL no ow"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then log("FAIL no lib"); logf:close(); love.event.quit(); return end
  log("version", exports.TERRARIUM.version)

  local Grass3D = lib.require("Grass3D")
  local ChunkMesher = lib.require("ChunkMesher")
  local Structures = lib.require("Structures")
  local stored = Grass3D.setting:get()
  log("stored GRASS row:", tostring(stored))
  log("MAX_TRIS =", tostring(Grass3D.MAX_TRIS),
      " MAX_TUFTS =", tostring(Grass3D.MAX_TUFTS))
  log("")

  local function report(tag)
    log(tag)
    local ok, res = pcall(Grass3D.available)
    log("  available() -> ok=" .. tostring(ok) .. " result=" .. tostring(res))
    local okm, m = pcall(Grass3D.meta)
    log("  meta()      -> ok=" .. tostring(okm) .. " result=" .. tostring(
        okm and m and (tostring(m.verts) .. " verts / "
                       .. tostring(math.floor((m.indices or 0) / 3)) .. " tris")
        or m))
    return ok, res
  end

  -- ------- the state the player is in when it breaks
  Grass3D.setting:sync("mesh")
  local ok = report("row = mesh (GRASS = 3D)")
  log("")

  if not ok then
    log("available() STILL THROWS -- the fix did not take. Stopping here.")
    Grass3D.setting:sync(stored)
    logf:close(); love.event.quit(); return
  end

  -- ------- MEADOWS, not a city. The first run of this probe measured
  -- CELADON_CITY and found zero grass instances, which is a true number
  -- about the wrong map: the whole feature only exists where tall grass
  -- does. These are the densest grass in Kanto.
  local MAPS = {
    { "ROUTE_1", 5, 10 },
    { "ROUTE_2", 5, 20 },
    { "VIRIDIAN_FOREST", 16, 30 },
    { "ROUTE_22", 12, 8 },
  }

  local okm, m = pcall(Grass3D.meta)
  local vpt = (okm and m and m.verts) or 0

  for _, entry in ipairs(MAPS) do
    local id, x, y = entry[1], entry[2], entry[3]
    log("")
    log("=== " .. id)
    local okM = pcall(function() game.overworld:setMap(id, x, y, "up") end)
    if not okM then
      log("  setMap failed -- skipping")
    else
      -- drop every cached mesh so buildGrass genuinely re-runs here. The
      -- earlier probe never did this, which is why it saw nothing.
      local okI, errI = pcall(ChunkMesher.invalidate)
      log("  invalidate() -> ok=" .. tostring(okI) .. " " .. tostring(errI or ""))

      local t0 = love.timer.getTime()
      local last, worst, frames = t0, 0, 0
      for _ = 1, 420 do
        coroutine.yield()
        frames = frames + 1
        local now = love.timer.getTime()
        local d = now - last
        if d > worst then worst = d end
        last = now
      end
      local t1 = love.timer.getTime()

      local map = game.overworld and game.overworld.map
      local okS, S = pcall(Structures.forMap, map)
      local ni = (okS and S and S.grassInstances and #S.grassInstances) or 0
      local nq = (okS and S and S.grassQuads and #S.grassQuads) or 0
      log(("  %d grass instances, %d slab quads"):format(ni, nq))
      if ni > 0 and vpt > 0 then
        log(("  -> %d tufts x %d verts = %d vertices in one mesh")
            :format(ni, vpt, ni * vpt))
        log(("  -> the shipped 1800-tri bake would have been %d vertices")
            :format(ni * 1719))
      end
      log(("  %d frames in %.2fs, WORST FRAME %.0f ms")
          :format(frames, t1 - t0, worst * 1000))
    end
  end

  log("")
  log("restoring GRASS row to " .. tostring(stored))
  Grass3D.setting:sync(stored)
  pcall(ChunkMesher.invalidate)
  wait(60)
  log("done")
  logf:close()
  love.event.quit()
end
