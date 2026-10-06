-- The mesh cache: does it save the seconds, and is the warm world the same
-- world?
--
-- Entering a map runs the whole geometry pass, and `tests/sink_probe.lua`
-- measures that at six to eleven SECONDS per map -- every visit, every
-- launch. `lib/MeshCache.lua` keeps the answer. This asks the only two
-- questions that matter about it:
--
--   1. COLD against WARM. Wipe, build, measure; drop the meshes but not the
--      cache, build again, measure. The second number is the one a player
--      gets on every visit after the first.
--   2. IS IT THE SAME WORLD. Not by screenshot -- this session learned the
--      hard way that rebuilding a map twice leaves the camera at two
--      different points of its own ease, and on a frame this full of dither
--      two pixels of pan differ in half their pixels, which reads as a
--      broken cache and is not. Compare the things a wrong payload actually
--      changes: how many chunks came back, how many vertices they carry, and
--      how many draws the frame makes. A cache that dropped, duplicated,
--      truncated or misordered a chunk moves at least one of those.
--
-- Plus `MeshCache.selfCheck()`, which proves the byte LAYOUT round-trips and
-- that a stale identity, a truncated payload and a bad magic are all refused.
--
--   POKEPORT_VERSION=yellow \
--   DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/cache_probe.lua gen1recomp

return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/cache_probe.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
    logf:write(table.concat(p, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    game.input.pressQueue[#game.input.pressQueue + 1] = "a"
    wait(10); n = n + 11
    if n > 1500 then break end
  end

  local lib = game.mods and game.mods.exports
              and game.mods.exports.TERRARIUM and game.mods.exports.TERRARIUM.lib
  if not lib then log("FAIL: not loaded"); logf:close(); love.event.quit(); return end

  local Quality     = lib.require("Quality")
  local Weather     = lib.require("Weather")
  local DayNight    = lib.require("DayNight")
  local Wind        = lib.require("Wind")
  local MiniMap     = lib.require("MiniMap")
  local AutoFarm    = lib.require("AutoFarm")
  local AmbientLife = lib.require("AmbientLife")
  local CityLife    = lib.require("CityLife")
  local WildRoamers = lib.require("WildRoamers")
  local Trees3D     = lib.require("Trees3D")
  local ChunkMesher = lib.require("ChunkMesher")
  local MeshCache   = lib.require("MeshCache")
  local Pipelines   = require("src.render.Pipelines")

  love.window.setVSync(0)
  Pipelines.setLevel("terrarium_voxel", 3)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  MiniMap.setting:sync("off")
  AutoFarm.setting:sync("off")
  Weather.setting:sync("off")
  DayNight.setting:sync("day")
  Wind.setting:sync(0)
  AmbientLife.setting:sync("off")
  CityLife.setting:sync("off")
  WildRoamers.setting:sync("off")
  local KEEP_RES = Quality.setting:get()
  Quality.setting:sync(2)

  local CLOCK = 300
  local function hold(f)
    for _ = 1, f do DayNight.clock = CLOCK; coroutine.yield() end
    DayNight.clock = CLOCK
  end

  -- vertices and draws submitted per frame: what a wrong payload moves
  local COUNT = { draw = 0, verts = 0 }
  do
    local g = love.graphics
    local rawDraw = g.draw
    g.draw = function(a, ...)
      COUNT.draw = COUNT.draw + 1
      if type(a) == "userdata" then
        local okR, _, c = pcall(function() return a:getDrawRange() end)
        if okR and type(c) == "number" and c > 0 then
          COUNT.verts = COUNT.verts + c
        else
          local okV, v = pcall(function() return a:getVertexCount() end)
          if okV and type(v) == "number" then COUNT.verts = COUNT.verts + v end
        end
      end
      return rawDraw(a, ...)
    end
  end

  local function settle(maxTicks)
    local quiet = 0
    for _ = 1, (maxTicks or 6000) do
      DayNight.clock = CLOCK
      coroutine.yield()
      local map = game.overworld and game.overworld.map
      local done, state = Trees3D.ready(map)
      if ChunkMesher.pending() == 0 and (done or state == "hulls") then
        quiet = quiet + 1
        if quiet >= 45 then return true end
      else
        quiet = 0
      end
    end
    return false
  end

  local function median(t)
    local s = {}
    for i, v in ipairs(t) do s[i] = v end
    table.sort(s)
    if #s == 0 then return 0 end
    return s[math.ceil(#s / 2)]
  end

  -- The group the cache round-tripped, measured DIRECTLY off its meshes.
  --
  -- The first version of this compared the per-frame vertex counter, and it
  -- reported Viridian differing by six vertices out of 1.42 million -- which
  -- is not a chunk, not a quad, and not geometry. It is the median of sixty
  -- frames of a counter that also sees whatever else is animating. Counting
  -- the group's own meshes has no frames in it at all: it is the same number
  -- every time it is asked, so a difference is a difference.
  local function groupShape(map)
    local g = ChunkMesher.peek(map, false) or ChunkMesher.peek(map, true)
    if not (g and g.chunks) then return -1, 0, 0, 0 end
    local verts, boxes = 0, 0
    for _, ch in ipairs(g.chunks) do
      local okV, v = pcall(function() return ch.mesh:getVertexCount() end)
      if okV and v then verts = verts + v end
      -- the culling boxes too: a chunk that came back with the wrong box is
      -- invisible from the wrong angle and identical in every other count
      boxes = boxes + (ch.x0 or 0) + (ch.z0 or 0) + (ch.x1 or 0)
                    + (ch.z1 or 0) + (ch.ymax or 0)
    end
    local water, wverts = 0, 0
    if g.water and g.water.chunks then
      water = #g.water.chunks
      for _, ch in ipairs(g.water.chunks) do
        local okV, v = pcall(function() return ch.mesh:getVertexCount() end)
        if okV and v then wverts = wverts + v end
      end
    end
    return #g.chunks, water, verts + wverts, boxes
  end

  -- TWO stopwatches, because two different things are being waited for and
  -- only ONE of them is cached: the chunk mesher's queue (terrain, water,
  -- grass, flowers, sprites, figures) and Trees3D's own sliced forest build.
  -- A single number hides which half the cache actually moved.
  -- WHERE the wait goes. ChunkMesher.stage names the pass a job is in, so
  -- sampling it once a frame is a histogram of the build with no
  -- instrumentation in the mesher at all. This is the number that says
  -- whether a cache can help at all: it can only ever remove the geometry
  -- pass, and if the wait is uploads and aux meshes then that is the
  -- ceiling, whatever the cache does.
  local STAGE = {}
  local function settleSplit(maxTicks)
    local t0 = love.timer.getTime()
    local meshMs, treeMs = nil, nil
    local quiet = 0
    STAGE = {}
    for _ = 1, (maxTicks or 8000) do
      DayNight.clock = CLOCK
      coroutine.yield()
      -- ONLY while a job is actually queued. ChunkMesher.stage is never
      -- cleared, so between jobs it still names whichever pass ran last --
      -- and the first version of this therefore charged every idle frame
      -- (waiting on Trees3D, counting out the quiet frames) to that pass,
      -- which made a pass look like it had grown when all that happened was
      -- that it finished last.
      if ChunkMesher.pending() > 0 then
        local st = ChunkMesher.stage
        local pass = (st and st.pass) or "queued"
        STAGE[pass] = (STAGE[pass] or 0) + 1
      else
        STAGE["idle(trees/settle)"] = (STAGE["idle(trees/settle)"] or 0) + 1
      end
      local map = game.overworld and game.overworld.map
      local done, state = Trees3D.ready(map)
      if meshMs == nil and ChunkMesher.pending() == 0 then
        meshMs = (love.timer.getTime() - t0) * 1000
      end
      if treeMs == nil and (done or state == "hulls") then
        treeMs = (love.timer.getTime() - t0) * 1000
      end
      if ChunkMesher.pending() == 0 and (done or state == "hulls") then
        quiet = quiet + 1
        if quiet >= 45 then return true, meshMs or 0, treeMs or 0 end
      else
        quiet = 0
      end
    end
    return false, meshMs or -1, treeMs or -1
  end

  local function visit(spot)
    local t0 = love.timer.getTime()
    game.overworld:setMap(spot[1], spot[2], spot[3], spot[4])
    local ok, meshMs, treeMs = settleSplit(8000)
    local buildMs = (love.timer.getTime() - t0) * 1000
    for _ = 1, 4 do
      game.overworld:setMap(spot[1], spot[2], spot[3], spot[4])
      hold(6)
    end
    hold(20)
    local dts, draws, verts = {}, {}, {}
    local prev = love.timer.getTime()
    for _ = 1, 60 do
      DayNight.clock = CLOCK
      COUNT.draw, COUNT.verts = 0, 0
      coroutine.yield()
      local t = love.timer.getTime()
      dts[#dts + 1] = (t - prev) * 1000
      prev = t
      draws[#draws + 1] = COUNT.draw
      verts[#verts + 1] = COUNT.verts
    end
    local stage = {}
    for k, v in pairs(STAGE) do stage[#stage + 1] = { k, v } end
    table.sort(stage, function(a, b) return a[2] > b[2] end)
    local nc, nw, gverts, boxes = groupShape(game.overworld.map)
    return { build = buildMs, settled = ok, ms = median(dts),
             draws = median(draws), verts = median(verts),
             chunks = nc, water = nw, gverts = gverts, boxes = boxes,
             meshMs = meshMs, treeMs = treeMs, stage = stage }
  end

  log("== the mesh cache ==")
  local okSelf, detail = MeshCache.selfCheck()
  log(("format self-check: %s -- %s"):format(tostring(okSelf), tostring(detail)))
  log(("available: %s"):format(tostring(MeshCache.available())))
  local okS, sWhy = MeshCache.storageCheck(game)
  log(("storage round-trip: %s -- %s"):format(tostring(okS), tostring(sWhy)))
  log(("identity:  %s"):format(tostring(MeshCache.identity())))
  -- A COLD ARM THAT IS ACTUALLY COLD.
  --
  -- The first four runs of this probe compared a warm build against a warm
  -- build and reported the difference as noise, because wipe() could not
  -- delete anything: the engine's storage backend here has no directory
  -- listing, so Storage.list answers "storage_unavailable" and wipe had
  -- nothing to enumerate. Salting the identity makes every existing entry a
  -- miss without needing to find one.
  MeshCache.SALT = ("run%d"):format(math.floor(love.timer.getTime() * 1000) % 1000000)
  log(("salt: %s  (every pre-existing entry is now a miss)"):format(MeshCache.SALT))
  local wiped, listed, wipeWhy = MeshCache.wipe(game)
  log(("wiped %d of %d listed entries%s"):format(wiped, listed,
        wipeWhy and (" -- " .. wipeWhy) or ""))
  if listed == 0 and not wipeWhy then
    log("   (nothing was cached, so the cold arm really is cold)")
  elseif wiped < listed then
    log("   *** WARNING: the cold arm below is NOT cold")
  end
  log("")

  local SPOTS = {
    { "ROUTE_2", 10, 10, "up" },
    { "VIRIDIAN_CITY", 24, 22, "up" },
    { "PALLET_TOWN", 10, 8, "up" },
  }

  local fails = 0
  for _, spot in ipairs(SPOTS) do
    log(("== %s =="):format(spot[1]))
    -- NO CACHE AT ALL: the build exactly as it shipped before any of this.
    -- Without this arm the cold arm below cannot be read -- it also WRITES,
    -- and a cache that pays for itself on the second visit by making the
    -- first one worse is not obviously a win on the machine this is for.
    ChunkMesher.CACHE = false
    ChunkMesher.invalidate()
    Trees3D.invalidate()
    local off = visit(spot)
    ChunkMesher.CACHE = true

    -- COLD: nothing on disk for this map yet, so this build also writes it
    MeshCache.resetStats()
    ChunkMesher.invalidate()
    Trees3D.invalidate()
    local cold = visit(spot)
    local wrote, wroteMB = MeshCache.stats.writes, MeshCache.stats.bytes / 1048576
    -- WARM: drop the meshes in memory, keep the ones on disk.
    -- Stats reset HERE, not before the cold arm: the reason buffer fills
    -- with the cold arm's legitimate refusals of pre-salt orphans and the
    -- warm arm's -- the only ones that matter -- never get recorded.
    MeshCache.resetStats()
    ChunkMesher.invalidate()
    Trees3D.invalidate()
    local warm = visit(spot)

    log(("   nocache mesher %7.1f ms   trees %7.1f ms   settle %8.1f ms  settled=%s")
          :format(off.meshMs, off.treeMs, off.build, tostring(off.settled)))
    log(("   cold  mesher %7.1f ms   trees %7.1f ms   settle %8.1f ms  settled=%s")
          :format(cold.meshMs, cold.treeMs, cold.build, tostring(cold.settled)))
    log(("   warm  mesher %7.1f ms   trees %7.1f ms   settle %8.1f ms  settled=%s")
          :format(warm.meshMs, warm.treeMs, warm.build, tostring(warm.settled)))
    log(("   cold  chunks=%d(+%d water)  group verts=%d  frame %5.2f ms")
          :format(cold.chunks, cold.water, cold.gverts, cold.ms))
    log(("   warm  chunks=%d(+%d water)  group verts=%d  frame %5.2f ms")
          :format(warm.chunks, warm.water, warm.gverts, warm.ms))
    local function stageLine(tag, r)
      local parts = {}
      for i = 1, math.min(#r.stage, 6) do
        parts[#parts + 1] = ("%s=%d"):format(r.stage[i][1], r.stage[i][2])
      end
      log(("   %s frames by pass: %s"):format(tag, table.concat(parts, "  ")))
    end
    stageLine("cold", cold)
    stageLine("warm", warm)
    for _, w in ipairs(MeshCache.stats.why or {}) do
      log("      " .. tostring(w))
    end
    log(("   cold wrote %d entries, %.2f MB;  WARM ONLY hits=%d misses=%d refused=%d rewrites=%d")
          :format(wrote, wroteMB, MeshCache.stats.hits, MeshCache.stats.misses,
                  MeshCache.stats.refused, MeshCache.stats.writes))
    log(("   FIRST VISIT COST OF CACHING: %+.1f ms (cold with cache vs no cache at all)")
          :format(cold.meshMs - off.meshMs))
    local saved = cold.meshMs - warm.meshMs
    log(("   SAVED %+.1f ms on the mesher (%.0f%% of its cold time)")
          :format(saved, cold.meshMs > 0 and saved / cold.meshMs * 100 or 0))

    -- the equality test, on numbers that have no frames in them
    -- compared against the NO-CACHE build, which is the reference world:
    -- cold and warm agreeing with each other but both differing from what
    -- the mod produced before would be a consistent lie
    local same = off.chunks == warm.chunks and off.water == warm.water
                 and off.gverts == warm.gverts
                 and math.abs(off.boxes - warm.boxes) < 0.5
                 and off.gverts == cold.gverts
    if same then
      log("   SAME WORLD: chunk count, group vertices and every cull box identical")
    else
      fails = fails + 1
      log(("   *** DIFFERENT: chunks %d vs %d, water %d vs %d, group verts %d vs %d, boxes %.1f vs %.1f")
            :format(cold.chunks, warm.chunks, cold.water, warm.water,
                    cold.gverts, warm.gverts, cold.boxes, warm.boxes))
    end
    log("")
  end

  log(fails == 0 and "PASS -- every map came back identical"
                 or ("FAIL -- %d map(s) differed"):format(fails))
  Quality.setting:sync(KEEP_RES)
  AmbientLife.setting:sync("auto")
  love.window.setVSync(1)
  log("done")
  logf:close()
  love.event.quit()
end
