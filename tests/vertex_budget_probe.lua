-- WHERE the frame's vertices come from.
--
-- tests/mali_cost_probe.lua answers what the frame COSTS and found the
-- answer is not pixels: sixteen times fewer of them (RES FULL against 1/4)
-- moves the frame about three milliseconds, and eighty-eight fewer draw
-- calls move it two tenths.  What it also found is that the 3D pass hands
-- the driver about 1.9 MILLION vertices every frame, and that every options
-- row in the mod put together accounts for barely a sixth of them.  On an
-- iGPU that is the whole story, and the rest of this file exists because
-- "1.9 million from somewhere" is not something anyone can act on.
--
-- So: attribute every vertex to the LINE that drew it.
--
-- No per-module wrapping and no bookkeeping to keep in step with the code:
-- love.graphics.draw is wrapped once and asks debug.getinfo who called it.
-- A probe runs outside the mod sandbox, so `debug` is there.  The bucket key
-- is source:line, which means the report names the exact draw site and stays
-- correct when a module is renamed, split or given a new pass.
--
-- Two things that would otherwise make the count a lie:
--
--   * A mesh drawn with a DRAW RANGE submits its range, not its buffer.
--     Voxel3D.drawParticles and Weather both do this, and counting
--     getVertexCount() there would charge a field of eight rain cards the
--     whole rain buffer.  getDrawRange() first, always.
--   * The SUN PASS draws much of the same geometry a second time.  It is
--     charged separately (its draw sites are in ShadowMap) rather than
--     folded in, because halving the scene's geometry and halving what
--     casts are two different jobs with two different risks.
--
--   POKEPORT_VERSION=yellow \
--   DS_PROBE_DIR=<dir> \
--   DS_PROBE_SPOT=ROUTE_1|ROUTE_2|VIRIDIAN \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/vertex_budget_probe.lua gen1recomp

return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/vertex_budget_probe.log", "w"))
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
    if n > 900 then log("FAIL: no overworld"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end

  local Quality     = lib.require("Quality")
  local Weather     = lib.require("Weather")
  local DayNight    = lib.require("DayNight")
  local Wind        = lib.require("Wind")
  local MiniMap     = lib.require("MiniMap")
  local AutoFarm    = lib.require("AutoFarm")
  local Trees3D     = lib.require("Trees3D")
  local ChunkMesher = lib.require("ChunkMesher")
  local Structures  = lib.require("Structures")
  local Pipelines   = require("src.render.Pipelines")

  love.window.setVSync(0)

  -- The still scene: anything that moves on its own would change the
  -- geometry between two frames and the medians below would be of two
  -- different worlds.
  Pipelines.setLevel("terrarium_voxel", 3)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  MiniMap.setting:sync("off")
  AutoFarm.setting:sync("off")
  Weather.setting:sync("off")
  DayNight.setting:sync("day")
  Wind.setting:sync(0)
  -- Pinned rather than left on AUTO: the governor walks the RES ladder while
  -- a probe runs and the vertex load would be measured at whatever rung it
  -- happened to land on.  RES does not change vertex counts, but it changes
  -- the frame time printed beside them.  The player's own rung is put back
  -- at the end -- this probe runs inside their install, not a fixture.
  local KEEP_RES = Quality.setting:get()
  Quality.setting:sync(2)

  local CLOCK = 300
  local function hold(f)
    for _ = 1, f do DayNight.clock = CLOCK; coroutine.yield() end
    DayNight.clock = CLOCK
  end

  local SPOTS = {
    ROUTE_1  = { "ROUTE_1", 8, 12, "up" },
    ROUTE_2  = { "ROUTE_2", 10, 10, "up" },
    VIRIDIAN = { "VIRIDIAN_CITY", 24, 22, "up" },
  }

  -- ------- the meter
  local BUCKET, CALLS = {}, {}
  local ARMED = false

  local function vertsOf(a)
    if type(a) ~= "userdata" then return 0 end
    -- A draw range means the buffer is not what was submitted.
    local okR, first, count = pcall(function() return a:getDrawRange() end)
    if okR and type(count) == "number" and count > 0 then return count end
    local okV, v = pcall(function() return a:getVertexCount() end)
    if okV and type(v) == "number" then return v end
    return 0
  end

  do
    local g = love.graphics
    local rawDraw = g.draw
    local rawInst = g.drawInstanced
    -- TWO frames of the stack, not one.  The first pass of this probe put
    -- 86% of the world on a single line -- Voxel3D.draw -- which is true and
    -- useless: that is the one-mesh draw helper and every pass in the mod
    -- goes through it.  The caller is the module, and the module is the
    -- thing that can be culled, batched or turned off.
    local function siteOf(level)
      local info = debug.getinfo(level, "Sl")
      if not info then return "?" end
      local src = tostring(info.short_src):gsub("^mods/TERRARIUM/", "")
      return src .. ":" .. tostring(info.currentline)
    end
    local function charge(level, a, mult)
      if not ARMED then return end
      local key = siteOf(level) .. "  <- " .. siteOf(level + 1)
      BUCKET[key] = (BUCKET[key] or 0) + vertsOf(a) * (mult or 1)
      CALLS[key] = (CALLS[key] or 0) + 1
    end
    g.draw = function(a, ...) charge(4, a, 1) return rawDraw(a, ...) end
    if rawInst then
      g.drawInstanced = function(a, count, ...)
        charge(4, a, tonumber(count) or 1)
        return rawInst(a, count, ...)
      end
    end
  end

  -- ------- the cull box, taken live
  --
  -- VoxelScene computes it once a frame and hands it to the terrain, which
  -- is the only reason the terrain is cheap.  It is a local there, so rather
  -- than rebuild it from the camera (and get a box that is ALMOST the real
  -- one, which is the worst kind) the group draw is wrapped and the real
  -- argument kept.  The trees would use this same box.
  local Voxel3D = lib.require("Voxel3D")
  local LAST_BOX = nil
  do
    local rawGroup = Voxel3D.drawGroup
    Voxel3D.drawGroup = function(group, texture, model, pull, sunModel, b)
      -- ONLY the current map's call.  Neighbours are drawn with a model
      -- translate and a box shifted into THEIR space, and keeping the last
      -- box seen therefore kept a neighbour's -- which is why the first run
      -- of this section reported that none of the forest was ever in frame.
      -- model == nil is the current map, and its box is in the same map
      -- coordinates Structures records tree sites in.
      if b and model == nil then LAST_BOX = b end
      return rawGroup(group, texture, model, pull, sunModel, b)
    end
  end

  -- What a spatial cull on the forest could actually win.
  --
  -- The forest is one mesh per species covering the WHOLE map (Trees3D.draw),
  -- so every tree runs the vertex stage whether or not the camera can see it.
  -- This asks the only question that decides whether splitting that mesh is
  -- worth doing: what fraction of the map's trees is inside the box the
  -- terrain is already culled with?  Reported two ways -- per site, which is
  -- the ceiling, and per 128px band, which is what a chunked mesh would
  -- actually achieve (a band survives if ANY of it is in frame).
  local BAND = 128
  local function cullPotential(sites, box)
    if not (sites and box) then return nil end
    local inBox, bands, liveBands = 0, {}, 0
    for i = 1, #sites do
      local sx, sz = sites[i].mx, sites[i].mz
      if sx >= box[1] and sx <= box[3] and sz >= box[2] and sz <= box[4] then
        inBox = inBox + 1
      end
      local key = math.floor(sx / BAND) .. "," .. math.floor(sz / BAND)
      local band = bands[key]
      if not band then
        band = { x0 = math.floor(sx / BAND) * BAND,
                 z0 = math.floor(sz / BAND) * BAND, n = 0 }
        bands[key] = band
      end
      band.n = band.n + 1
    end
    local banded = 0
    local nBands = 0
    for _, band in pairs(bands) do
      nBands = nBands + 1
      if band.x0 + BAND >= box[1] and band.x0 <= box[3]
         and band.z0 + BAND >= box[2] and band.z0 <= box[4] then
        liveBands = liveBands + 1
        banded = banded + band.n
      end
    end
    return { inBox = inBox, total = #sites, bands = nBands,
             liveBands = liveBands, banded = banded }
  end

  -- ------- settling
  --
  -- Counting frames photographs a half-built map, and a half-built map has
  -- fewer vertices in it than the one the player stands in.  That error
  -- points the wrong way: it would make the world look cheap.
  local function settle(maxTicks)
    local quiet = 0
    for _ = 1, (maxTicks or 2400) do
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

  local N = 60
  local function measure(name, spot)
    local SPOT = SPOTS[spot]
    game.overworld:setMap(SPOT[1], SPOT[2], SPOT[3], SPOT[4])
    local ok = settle(3000)
    -- re-assert the cell: the player walks on its own for a few ticks after
    -- a setMap, and a camera two cells along sees a different set of chunks
    for _ = 1, 6 do
      game.overworld:setMap(SPOT[1], SPOT[2], SPOT[3], SPOT[4])
      hold(6)
    end
    hold(30)

    BUCKET, CALLS = {}, {}
    local dts = {}
    local prev = love.timer.getTime()
    ARMED = true
    for _ = 1, N do
      DayNight.clock = CLOCK
      coroutine.yield()
      local t = love.timer.getTime()
      dts[#dts + 1] = (t - prev) * 1000
      prev = t
    end
    ARMED = false

    local st = Structures.forMap(game.overworld.map)
    local rows, total, totalCalls = {}, 0, 0
    for k, v in pairs(BUCKET) do
      rows[#rows + 1] = { key = k, verts = v / N, calls = CALLS[k] / N }
      total = total + v / N
      totalCalls = totalCalls + CALLS[k] / N
    end
    table.sort(rows, function(a, b) return a.verts > b.verts end)

    log("")
    log(("== %s (%s) -- settled=%s  tree sites=%d  hull stamps=%d ==")
          :format(name, spot, tostring(ok),
                  st and #(st.treeSites or {}) or -1,
                  st and #(st.roundStamps or {}) or -1))
    log(("   frame %.2f ms (p50 of %d)   %.0f vertices/frame in %.0f draws")
          :format(median(dts), N, total, totalCalls))
    log("")
    log("   vertices/frame  share   draws  draw site  <- caller")
    for i = 1, #rows do
      local r = rows[i]
      if r.verts >= 1 or i <= 30 then
        log(("   %14.0f  %5.1f%%  %6.1f  %s")
              :format(r.verts, total > 0 and r.verts / total * 100 or 0,
                      r.calls, r.key))
      end
    end
    local cp = cullPotential(st and st.treeSites, LAST_BOX)
    if cp then
      log("")
      if LAST_BOX then
        log(("   cull box  x %.0f..%.0f   z %.0f..%.0f   (%.0f x %.0f world px)")
              :format(LAST_BOX[1], LAST_BOX[3], LAST_BOX[2], LAST_BOX[4],
                      LAST_BOX[3] - LAST_BOX[1], LAST_BOX[4] - LAST_BOX[2]))
      end
      log(("   trees in the box: %d of %d (%.1f%%)  -- the ceiling for a cull")
            :format(cp.inBox, cp.total,
                    cp.total > 0 and cp.inBox / cp.total * 100 or 0))
      log(("   at %dpx bands:    %d of %d bands live, carrying %d of %d trees (%.1f%%)")
            :format(BAND, cp.liveBands, cp.bands, cp.banded, cp.total,
                    cp.total > 0 and cp.banded / cp.total * 100 or 0))
      log(("   so a banded mesh would submit about %.0f%% of the forest it does now")
            :format(cp.total > 0 and cp.banded / cp.total * 100 or 100))
    end
    return total
  end

  log("== where the frame's vertices come from ==")
  local ww, wh = love.graphics.getDimensions()
  log(("window %dx%d   RES 1/2 pinned"):format(ww, wh))
  local vw, vh = game.renderer:worldViewSize()
  log(("world view %dx%d world px = %.1f x %.1f cells of 16 px")
        :format(vw or 0, vh or 0, (vw or 0) / 16, (vh or 0) / 16))

  for _, spot in ipairs({ "ROUTE_1", "ROUTE_2", "VIRIDIAN" }) do
    local okM, err = pcall(measure, spot, spot)
    if not okM then log(("   FAIL %s: %s"):format(spot, tostring(err))) end
  end

  Quality.setting:sync(KEEP_RES)
  love.window.setVSync(1)
  log("")
  log("done")
  logf:close()
  love.event.quit()
end
