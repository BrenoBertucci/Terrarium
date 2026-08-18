-- Probe: WHY the voxel pass falls back to 2D on Gold.
--
--   POKEPORT_VERSION=gold DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/gold_mesh_probe.lua gen1recomp
--
-- The mesh builder reports failures through print(), which a windowed run
-- swallows -- so first thing, print is teed into the log.  Then the build
-- is driven synchronously (ChunkMesher.build under pcall) so the REAL
-- error surfaces with a stack instead of a silent flat frame.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/gold_mesh.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local rawprint = print
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write("[print] ", table.concat(parts, "\t"), "\n"); logf:flush()
    rawprint(...)
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end

  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      pcall(function()
        local fd = data:encode("png")
        local f = assert(io.open(OUT .. "/" .. name, "wb"))
        f:write(fd:getString()); f:close()
      end)
      done = true
    end)
    local n = 0
    while not done and n < 120 do wait(1); n = n + 1 end
    log("shot", name, done and "ok" or "TIMEOUT")
  end

  local n = 0
  while not (game.world and game.world.map) do
    wait(1); n = n + 1
    if n > 3600 then log("FAIL: no world"); logf:close(); love.event.quit(); return end
  end

  pcall(function() game.world:setMap("NEW_BARK_TOWN", 8, 8, "down") end)
  wait(60)

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then log("FAIL: no TERRARIUM lib"); logf:close(); love.event.quit(); return end

  local Pipelines = require("src.render.Pipelines")
  Pipelines.setLevel("terrarium_voxel", 5)
  wait(30)

  local Voxel = lib.require("VoxelState")
  local Voxel3D = lib.require("Voxel3D")
  local VoxelScene = lib.require("VoxelScene")
  local ChunkMesher = lib.require("ChunkMesher")
  log("Voxel.level =", tostring(Voxel.level),
      "active =", tostring(Voxel.active and Voxel.active()))
  log("Voxel3D.available =", tostring(Voxel3D.available and Voxel3D.available()))
  log("worldPipeline =", tostring(Pipelines.worldPipeline
      and Pipelines.worldPipeline()))

  local world = game.world
  log("map =", tostring(world.map.id),
      "neighbors =", tostring(#(world.neighbors or {})))
  for _, nb in ipairs(world.neighbors or {}) do
    log("  nb", tostring(nb.id), "map inst =", tostring(nb.map ~= nil))
  end

  -- prefetch: what render() calls first
  local okP, terrain, nbMesh = pcall(VoxelScene.prefetch, world)
  log("prefetch ok =", tostring(okP),
      "terrain =", tostring(terrain), "nb =", tostring(nbMesh))

  -- pump a lot, then look again
  for _ = 1, 600 do
    pcall(ChunkMesher.pump, false)
    coroutine.yield()
  end
  local okP2, terrain2 = pcall(VoxelScene.prefetch, world)
  log("after pump: prefetch ok =", tostring(okP2),
      "terrain =", tostring(terrain2))

  -- the synchronous build, so a failure arrives with its message
  local okB, meshOrErr = pcall(ChunkMesher.build, world.map, false, {})
  log("direct build ok =", tostring(okB), "->", tostring(meshOrErr))

  -- and the render itself
  local okR, canvasOrErr = pcall(VoxelScene.render, world, 1024, 768,
    world.viewW or 512, world.viewH or 384, function() return nil end)
  log("render ok =", tostring(okR), "->", tostring(canvasOrErr))

  wait(60)
  shot("mesh_after.png")
  log("done")
  logf:close()
  _G.print = rawprint
  love.event.quit()
end
