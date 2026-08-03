-- Probe: how long the loading is VISIBLE when the area changes, in frames.
--
-- "The loading shows" is two different pictures, out of two different lines
-- of code, and only one of them is sky:
--
--   NO TERRAIN.  VoxelScene.render returns nil when prefetch could not hand
--   it a mesh for the CURRENT map, and main.lua draws the frame through the
--   ordinary 2D path instead. Not a blank screen -- the game flipping out
--   of 3D and back.
--
--   A HOLE.  The 3D pass ran, but nbMesh[i] was nil for a neighbour, so
--   nothing was drawn at that offset and the full-screen sky clear shows
--   through. THIS is the flat sky.
--
-- A hole only counts when the CAMERA CAN SEE IT. Most connections are on
-- the side of a map you are not looking at (VoxelScene's own note on
-- bounds), and counting those makes a queue that is merely busy look like a
-- world that is broken -- which is how an earlier run of this probe
-- reported two seconds of "sky" for gaps that were off screen the whole
-- time. Visibility is tested with VoxelScene.bounds, the same box the draw
-- culls against, so a hole counted here is a hole that was drawn.
--
-- Nothing is read off a screenshot: the measurement hooks
-- VoxelScene.prefetch and records the two values the draw itself was
-- handed. Screenshots are taken at the first offending frame of each phase,
-- to confirm WHICH picture the number describes, never to be the evidence.
--
-- ------- how the before and after are kept honest
--
-- Both are measured in ONE run, by wrapping ChunkMesher so the OLD
-- behaviour can be put back at will:
--
--   the HOLE priority tier is stripped back to idle, and
--   `covered` is recomputed with the old stack-only test, which could
--   never be true during a warp.
--
-- Run separately, the second phase would inherit whatever queue the first
-- one left behind -- which is exactly how a previous round of this probe
-- produced a "warp got worse" that was really "the warp started dirtier".
-- So every phase invalidates the whole cache first and then settles to a
-- known state, and OLD and NEW run the same phase from the same start.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/DRAMATIC_SHAPE/tests/seam_stream_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/seam_stream_probe.log", "w"))
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
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
  end

  love.math.setRandomSeed(20260802)

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld"); logf:close(); love.event.quit()
      return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam"); break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.DRAMATIC_SHAPE and exports.DRAMATIC_SHAPE.lib
  if not lib then
    log("FAIL: DRAMATIC_SHAPE not loaded"); logf:close(); love.event.quit()
    return
  end
  log("version:", exports.DRAMATIC_SHAPE.version)

  local ChunkMesher = lib.require("ChunkMesher")
  local VoxelScene  = lib.require("VoxelScene")
  local WildRoamers = lib.require("WildRoamers")
  local DayNight    = lib.require("DayNight")
  local Pipelines   = require("src.render.Pipelines")

  WildRoamers.setting:sync("roam")
  DayNight.setting:sync("day")
  Pipelines.setLevel("voxel", 4)

  -- ------- putting the old behaviour back
  local OLD = false
  local realRequest, realPump = ChunkMesher.request, ChunkMesher.pump
  ChunkMesher.request = function(map, bodyOnly, masks, urgent)
    if OLD then
      local ow = game.overworld
      local isCurrent = ow and ow.map and map and map.id == ow.map.id
      -- the cold stand-in did not exist: the current map only ever asked
      -- for its full mesh, and the body-only fallback had nothing to find
      if bodyOnly and isCurrent then return ChunkMesher.peek(map, true) end
      -- the tier between "current map" and "idle" did not exist either.
      -- Which of the two it collapses to depends on WHO is asking: the
      -- current map's own mesh was always top priority, a neighbour's was
      -- always the bottom one.
      if type(urgent) == "number" then urgent = isCurrent and true or false end
    end
    return realRequest(map, bodyOnly, masks, urgent)
  end
  ChunkMesher.pump = function(covered)
    -- the old test, verbatim: only another scene on top of the stack ever
    -- counted as covered, never a warp
    if OLD then
      local ow = game.overworld
      covered = (game.stack and game.stack:top() ~= ow) or false
    end
    return realPump(covered)
  end

  -- ------- the measurement
  local function viewSize()
    local r = game.renderer
    if r and r.worldViewSize then
      local ok, w, h = pcall(r.worldViewSize, r)
      if ok and (w or 0) > 0 and (h or 0) > 0 then return w, h end
    end
    return 160, 144
  end

  local seen = nil
  local realPrefetch = VoxelScene.prefetch
  VoxelScene.prefetch = function(state)
    local terrain, nbMesh = realPrefetch(state)
    local nbn = #(state.neighbors or {})
    local holes, seenHoles = 0, 0
    local cam = state.camera
    local box = nil
    if cam then
      local vw, vh = viewSize()
      local okB, b = pcall(VoxelScene.bounds,
                           cam.x + vw / 2, cam.y + vh / 2, vw, vh, false)
      if okB then box = b end
    end
    for i = 1, nbn do
      if not (nbMesh and nbMesh[i]) then
        holes = holes + 1
        local nb = state.neighbors[i]
        local d = nb.map and nb.map.def
        if box and d then
          -- the neighbour's body in world coordinates, against the same
          -- box the draw culls chunks with
          local x0, y0 = nb.ox, nb.oy
          local x1, y1 = x0 + (d.width or 0) * 32, y0 + (d.height or 0) * 32
          if x1 > box[1] and x0 < box[3] and y1 > box[2] and y0 < box[4] then
            seenHoles = seenHoles + 1
          end
        end
      end
    end
    seen = {
      terrain = terrain ~= nil, holes = holes, seenHoles = seenHoles,
      nbn = nbn, ghosts = #(state.ghosts or {}),
      mapId = state.map and state.map.id,
    }
    return terrain, nbMesh
  end

  local function roamersOf(ow)
    local out = {}
    for _, e in ipairs(ow.entities or {}) do
      if e.roamer then out[#out + 1] = e end
    end
    return out
  end

  local function ghostsFrom(ow, mapId)
    local k = 0
    for _, g in ipairs(ow.ghosts or {}) do
      if g.map and g.map.id == mapId then k = k + 1 end
    end
    return k
  end

  -- whole = a 3D frame with nothing visibly missing from it
  local function whole() return seen and seen.terrain and seen.seenHoles == 0 end

  local function settle(cap)
    for i = 1, cap do
      wait(1)
      if whole() then return i end
    end
    return -1
  end

  -- Watch until the world is whole, counting what was wrong on the way.
  -- Returns frames-to-whole (-1 if it never got there) and the two counts.
  local function watch(cap, shotName)
    local no2D, sky, worst, toWhole = 0, 0, 0, -1
    local shotTaken = false
    for i = 1, cap do
      coroutine.yield()
      local s = seen
      if s then
        if not s.terrain then
          no2D = no2D + 1
        elseif s.seenHoles > 0 then
          sky = sky + 1
          worst = math.max(worst, s.seenHoles)
        elseif toWhole < 0 then
          toWhole = i
          break
        end
        if shotName and not shotTaken and (not s.terrain or s.seenHoles > 0) then
          shot(shotName); shotTaken = true
        end
      end
    end
    return toWhole, no2D, sky, worst
  end

  -- ------- one phase, run identically in both modes
  --
  -- Viridian's south edge into Route 1, walked south: the one crossing
  -- known to be script-free and to actually go through. Route 1's north
  -- edge is ledged and cannot be walked back up.
  local function seamPhase(tag, shotName)
    ChunkMesher.invalidate()
    game.overworld:setMap("VIRIDIAN_CITY", 20, 30, "down")
    wait(60)
    local s = settle(900)
    local ow = game.overworld
    local before = #roamersOf(ow)
    local startMap = ow.map.id

    local walked, crossed = 0, false
    for _ = 1, 240 do
      game.input.pressQueue[#game.input.pressQueue + 1] = "down"
      game.input.state.down = true
      coroutine.yield()
      game.input.state.down = false
      walked = walked + 1
      if seen and seen.mapId ~= startMap then crossed = true; break end
    end

    local toWhole, no2D, sky, worst = watch(600, shotName)
    local ow2 = game.overworld
    log("")
    log(("[seam %s] %s -> %s  crossed=%s (%d frames walking, settled at %d)")
        :format(tag, startMap, ow2.map.id, tostring(crossed), walked, s))
    if not crossed then log("  FAIL: never left the starting map") end
    log(("  frames until the world was whole: %d   (-1 = never within 600)")
        :format(toWhole))
    log(("  NO TERRAIN %d frames | VISIBLE SKY %d frames (worst %d neighbours)")
        :format(no2D, sky, worst))
    log(("  roamers %d before -> %d after | ghosts %d, of them %d on %s")
        :format(before, #roamersOf(ow2), #(ow2.ghosts or {}),
                ghostsFrom(ow2, startMap), startMap))
    return toWhole, no2D, sky
  end

  -- What a door does: straight onto a map nothing was holding warm, with no
  -- fade over it, so the cost is the cost rather than what is left of it
  -- after the cover.
  local function warpPhase(tag, shotName)
    ChunkMesher.invalidate()
    game.overworld:setMap("PEWTER_CITY", 14, 24, "down")
    local toWhole, no2D, sky, worst = watch(600, shotName)
    log("")
    log(("[warp %s] -> PEWTER_CITY"):format(tag))
    log(("  frames until the world was whole: %d   (-1 = never within 600)")
        :format(toWhole))
    log(("  NO TERRAIN %d frames | VISIBLE SKY %d frames (worst %d neighbours)")
        :format(no2D, sky, worst))
    return toWhole, no2D, sky
  end

  OLD = true
  local oSeam, oSeam2D, oSeamSky = seamPhase("OLD", "seam_old.png")
  OLD = false
  local nSeam, nSeam2D, nSeamSky = seamPhase("NEW", "seam_new.png")

  -- The warps run as a PALINDROME. A run gets slower as it goes -- more
  -- garbage, a warmer machine, a fuller atlas -- so measuring OLD then NEW
  -- once each charges the second one for the first one's wear, and a
  -- previous round of this probe read exactly that as a regression.
  -- OLD-NEW-NEW-OLD brackets each mode inside the other: a difference that
  -- survives the mirror is a difference in the code, and one that does not
  -- was the clock.
  OLD = true;  local w1 = warpPhase("OLD 1", "warp_old.png")
  OLD = false; local w2 = warpPhase("NEW 1", "warp_new.png")
  OLD = false; local w3 = warpPhase("NEW 2", nil)
  OLD = true;  local w4 = warpPhase("OLD 2", nil)

  log("")
  log("------- frames of VISIBLE loading, same start, same run")
  log(("  seam crossing   OLD %4d frames to whole (%d 2D, %d sky)")
      :format(oSeam, oSeam2D, oSeamSky))
  log(("                  NEW %4d frames to whole (%d 2D, %d sky)")
      :format(nSeam, nSeam2D, nSeamSky))
  log(("  cold warp       OLD %4d and %4d frames to whole"):format(w1, w4))
  log(("                  NEW %4d and %4d frames to whole"):format(w2, w3))

  VoxelScene.prefetch = realPrefetch
  ChunkMesher.request, ChunkMesher.pump = realRequest, realPump
  wait(40)          -- long enough for the screenshots to land
  log("")
  log("done")
  logf:close()
  love.event.quit()
end
