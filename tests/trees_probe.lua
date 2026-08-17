-- Do the authored trees reach the screen, and did the hulls get out of the way?
--
-- Three ways this can pass every count and still be wrong, which is why it
-- ends in a picture:
--
--   1. Bake refused. Trees3D.MAX_TRIS turns a fat bake into "keep the
--      hulls", quietly and on purpose. available() says so; the forest
--      looks untouched either way.
--   2. Hull AND model on the same cell. Structures skips the hull only
--      when Trees3D.available() was true AT BUILD TIME, so a bake that
--      loads late leaves both in the scene, and a count of either one
--      alone still looks right.
--   3. Trunks decimated away. A canopy hovering over grass is what a
--      collapsed trunk looks like, and no triangle count reports it.
--
-- Shots land in DS_PROBE_DIR: trees_day, trees_close.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/trees_probe.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring((select(i, ...))) end
    logf:write(table.concat(p, " ") .. "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b
    coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: never booted"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end

  local lib = game.mods.exports.TERRARIUM.lib
  local DayNight = lib.require("DayNight")
  local Voxel3D = lib.require("Voxel3D")
  local Trees3D = lib.require("Trees3D")
  local Structures = lib.require("Structures")
  local V = lib

  -- ---- WAIT FOR THE FOREST, DO NOT COUNT FRAMES AT IT.
  --
  -- The forest is built in slices from the DRAW path (Trees3D.SLICE_SITES
  -- sites per call), so "entering a map" and "the map showing its trees"
  -- are hundreds of frames apart on a route: ROUTE_2 is 862 sites at 6 a
  -- slice. The previous cost run sampled after a fixed wait(150) and the
  -- tail of that build landed inside the sample -- which is the entire
  -- reason it reported 73 ms where the run before it reported 42.
  --
  -- So poll the signals instead:
  --   Voxel3D.lampLights ~= nil  the 3D pass has run at least once (it is
  --                              only ever assigned by VoxelScene.render,
  --                              and a map with no lamps still gets {})
  --   Trees3D.ready(map)         this map's sliced build finished
  --   Trees3D.buildsInFlight()   ...and so did every neighbour's, which
  --                              are drawn by the same path in the same
  --                              frames and would otherwise be sampled
  --   ChunkMesher.pending()      and the TERRAIN is meshed. Trees cache
  --                              per map id, so walking back onto a map
  --                              already visited reports ready on the
  --                              first tick while the chunk mesher is
  --                              still working through its queue -- the
  --                              same contamination, wearing the fix.
  --
  -- NOTHING HERE ADVANCES THE BUILD. ready() is a state read; the draw
  -- path owns the stamping. A poller that "helped" would be timing its
  -- own work.
  --
  -- The build also doubles as a TACHOMETER, and that is not a bonus -- it
  -- is the calibration the whole cost section rests on. This driver is
  -- resumed POKEPORT_SPEED times per rendered frame (main.lua: the
  -- scripted act+step loop), while the draw that advances a slice happens
  -- once per rendered frame. So a coroutine.yield() is only a frame at
  -- speed 1, and every ms-per-frame number below is wrong by exactly that
  -- factor if it is not. Sites per tick says which world we are in:
  -- SLICE_SITES per tick is one draw per tick, twice that is the sun pass
  -- advancing a second slice, a quarter of it is POKEPORT_SPEED=4.
  local okCM, ChunkMesher = pcall(lib.require, "ChunkMesher")
  local function meshQueue()
    if not (okCM and ChunkMesher and ChunkMesher.pending) then return 0 end
    local ok, n = pcall(ChunkMesher.pending)
    return (ok and tonumber(n)) or 0
  end

  -- TWO PHASES, because the two things being waited on fail differently.
  --
  -- Phase 1 is this map: the 3D pass live and its own build finished. That
  -- is bounded by the site count and always completes.
  --
  -- Phase 2 is everyone ELSE -- neighbours, which VoxelScene draws through
  -- the same path in the same frames and which therefore land in the
  -- sample. It gets a GRACE rather than the same patience, because a build
  -- only advances while its map is drawn: walk off a map mid-build and its
  -- slice state freezes, and before Trees3D.RETIRE_AFTER existed this loop
  -- sat 6000 ticks (four minutes) waiting for 316 sites owed by a route
  -- nobody was standing near any more. A bounded grace that SAYS what it
  -- gave up on cannot turn into that again.
  local GRACE = 400
  local function settle(label, maxTicks)
    maxTicks = maxTicks or 4000
    local t0 = love.timer.getTime()
    local ticks, live = 0, false
    local tStart, doneStart, total = nil, 0, 0
    local tEnd = nil
    local done, state, sd = false, "cold", 0

    -- phase 1 -- this map
    while true do
      if Voxel3D.lampLights ~= nil then live = true end
      local map = game.overworld and game.overworld.map
      local stot
      done, state, sd, stot = Trees3D.ready(map)
      if state == "building" and not tStart then
        tStart, doneStart, total = ticks, sd, stot
      end
      if live and (done or state == "hulls") then tEnd = ticks; break end
      if ticks >= maxTicks then
        log(string.format("FAIL: settle %s never came up -- %d ticks, "
                          .. "3D live=%s, state=%s", label, ticks,
                          tostring(live), state))
        tEnd = ticks
        break
      end
      coroutine.yield()
      ticks = ticks + 1
    end

    -- phase 2 -- the neighbours and the terrain queue
    local owed, queued = select(2, Trees3D.buildsInFlight()), meshQueue()
    local waited = 0
    while (owed > 0 or queued > 0) and waited < GRACE do
      coroutine.yield()
      ticks, waited = ticks + 1, waited + 1
      owed, queued = select(2, Trees3D.buildsInFlight()), meshQueue()
    end

    local ms = (love.timer.getTime() - t0) * 1000
    -- The tachometer spans phase 1 ONLY. Running it to the end of phase 2
    -- divided this map's sites by the neighbours' wait as well and reported
    -- 1.17 sites/tick where the truth was a whole slice per draw.
    local tach = ""
    if tStart and done and tEnd and tEnd > tStart then
      local span = tEnd - tStart
      local stamped = total - doneStart
      tach = string.format(" | built %d sites over %d ticks = %.2f sites/tick"
                           .. " = %.2f draws/tick (SLICE_SITES=%d)",
                           stamped, span, stamped / span,
                           stamped / span / Trees3D.SLICE_SITES,
                           Trees3D.SLICE_SITES)
    elseif ticks == 0 then
      tach = " (prebuilt -- this map was a neighbour of the last one)"
    end
    local rest = ""
    if owed > 0 or queued > 0 then
      rest = string.format(" | GAVE UP after %d grace ticks with %d sites "
                           .. "owed and %d mesh jobs queued -- the sample "
                           .. "below is NOT clean", waited, owed, queued)
    elseif waited > 0 then
      rest = string.format(" | neighbours took %d more ticks", waited)
    end
    log(string.format("settle %s: %s in %d ticks (%.0f ms)%s%s",
                      label, state, ticks, ms, tach, rest))
    return ticks, state
  end

  -- A shader that fails to compile does not crash and does not warn: the
  -- engine keeps the flat 2D renderer, every assert below still passes, and
  -- the screenshots look like the feature was never written.
  local sh = Voxel3D.shader()
  log("voxel shader:", sh and "PASS" or "FAIL", tostring(Voxel3D.shaderError))

  -- ---- the bake loaded, and was not refused for being too fat
  local avail = Trees3D.available()
  log(avail and "PASS: authored tree bake in use"
             or "FAIL: no tree bake loaded (refused, missing or unreadable)")
  local species = Trees3D.loaded()
  log("species loaded =", #species, table.concat(species, ","))
  local m = Trees3D.meta()
  if m then
    log(string.format("template: %d tris (%d trunk), h=%.1f r=%.2f "
                      .. "canopyY=%.1f canopyR=%.2f",
                      m.tris, m.trunkTris, m.height, m.radius,
                      m.canopyY, m.canopyR))
    -- A trunk that decimated to nothing is the failure that looks fine in
    -- every count but leaves a ball floating over the grass.
    log(m.trunkTris >= 8 and "PASS: trunk survived the bake"
                          or "FAIL: trunk is " .. m.trunkTris .. " tris")
  else
    log("FAIL: no template metadata")
  end

  -- ---- DOES THE PACKED CHANNEL SURVIVE THE TRIP?
  --
  -- VertexShade now carries three facts at once: brightness in a 0..63
  -- level, canopy weight in the fraction, and sky-facing in the sign. The
  -- encode is in Trees3D and the decode is GLSL in Voxel3D's vertex stage,
  -- and they are only correct as a PAIR -- change one and the trees are lit
  -- by garbage, silently.
  --
  -- "The shader compiled and the picture looks the same" is the evidence
  -- that has been wrong before in this renderer, so measure the round trip
  -- over the real template rather than trusting it.
  do
    local tplName = Trees3D.SPECIES[1]
    local tpl = Trees3D.templates and Trees3D.templates[tplName]
    local n, eB, eW, badSign = 0, 0, 0, 0
    local probe = tpl and tpl.verts
    if probe then
      for i = 1, #probe do
        local sh = probe[i][6] or 0.8
        local w = (tpl.weights and tpl.weights[i]) or 0
        if w > 0.999 then w = 0.999 end
        local packed = Trees3D.packShade(sh, w)
        local B, W, up = Trees3D.unpackShade(packed)
        local wantB = math.min(math.abs(sh), 1)
        if math.abs(B - wantB) > eB then eB = math.abs(B - wantB) end
        if math.abs(W - w) > eW then eW = math.abs(W - w) end
        if up ~= (sh < 0) then badSign = badSign + 1 end
        n = n + 1
      end
      log(string.format("packed channel: %d verts, max brightness err %.4f "
                        .. "(budget %.4f), max weight err %.5f, sign flips %d",
                        n, eB, 1 / 63, eW, badSign))
      -- Brightness is quantised to 64 levels on purpose, so one level of
      -- error is the contract, not a failure. A sign flip is not: it would
      -- make snow settle on flanks and skip crowns.
      log((eB <= 1 / 63 + 1e-6 and eW < 0.002 and badSign == 0)
          and "PASS: brightness, canopy weight and sky flag all survive packing"
          or "FAIL: the packed channel is lossy beyond its contract")
    else
      log("FAIL: no template to measure the packed channel on")
    end
  end

  DayNight.setting:sync("day")
  game.overworld:setMap("VIRIDIAN_CITY", 10, 10, "up")
  settle("VIRIDIAN_CITY")

  local map = game.overworld.map
  local S = Structures.forMap(map)
  local nSites = #(S.treeSites or {})
  local nHulls = #(S.roundStamps or {})
  log("tree sites =", nSites, "| hull stamps left =", nHulls)
  -- Sites come in two sizes and the template is authored against the big
  -- one; if the small ones dominate, a template stamped at full scale eats
  -- the map. Counting them rather than inferring it from the picture.
  do
    local byR = {}
    for _, st in ipairs(S.treeSites or {}) do
      local r = st.r or 8
      byR[r] = (byR[r] or 0) + 1
    end
    local parts = {}
    for r, c in pairs(byR) do parts[#parts + 1] = string.format("r=%d:%d", r, c) end
    table.sort(parts)
    log("sites by radius:", table.concat(parts, " "))
  end
  -- The exclusive-or IS the test. Both populated means every round cell is
  -- carrying a model and a ball at once, which reads as a fat blurry tree
  -- rather than as an obvious bug.
  if avail then
    log((nSites > 0 and nHulls == 0)
        and "PASS: hulls stood down, sites recorded"
        or "FAIL: hulls and sites disagree (both, or neither)")
  end

  -- settle() already waited on the 3D pass; report what it settled into
  -- rather than re-polling it. A "cold" here means the pass never came up
  -- and every shot below is a 2D screenshot of a feature that did not run.
  local live = Voxel3D.lampLights ~= nil
  log(live and "PASS: 3D pass live" or "FAIL: 3D pass never came up (2D shot)")
  local built, state = Trees3D.ready(map)
  log("forest state =", state, "| trees counted for this map =",
      Trees3D.count(map))
  log((built or not avail) and "PASS: forest settled before the shots"
                            or "FAIL: shooting a half-built forest")

  local function shot(name)
    love.graphics.captureScreenshot(function(d)
      local f = io.open(OUT .. "/" .. name .. ".png", "wb")
      if f then f:write(d:encode("png"):getString()); f:close() end
    end)
    wait(10)
  end

  shot("trees_day")

  -- And once from close in, where a hovering canopy or a seam between the
  -- authored tree and whatever is behind it would actually be visible.
  pcall(function() game.overworld:setMap("VIRIDIAN_CITY", 14, 20, "up") end)
  settle("VIRIDIAN_CITY close")
  shot("trees_close")

  -- ---- and a route with REAL trees.
  --
  -- Viridian is 660 sites and every one is r=8 (single 16px cell, the
  -- shrubbery the player walks over). Nothing there ever exercises the
  -- 2x2 site, so the tree at TREE proportions has never actually been
  -- drawn. A forested route is where that gets judged.
  for _, id in ipairs({ "ROUTE_2", "ROUTE_1", "ROUTE_25" }) do
    local okm = pcall(function() game.overworld:setMap(id, 10, 10, "up") end)
    if okm and game.overworld.map and game.overworld.map.id == id then
      settle(id)
      local RS = Structures.forMap(game.overworld.map)
      local byR = {}
      for _, st in ipairs(RS.treeSites or {}) do
        local r = st.r or 8
        byR[r] = (byR[r] or 0) + 1
      end
      local parts = {}
      for r, c in pairs(byR) do parts[#parts + 1] = string.format("r=%d:%d", r, c) end
      table.sort(parts)
      log(id, "sites =", #(RS.treeSites or {}),
          "| hulls =", #(RS.roundStamps or {}),
          "| by radius:", table.concat(parts, " "))
      shot("trees_" .. string.lower(id))
    else
      log("skip", id, "(no such map)")
    end
  end

  -- ---- WINTER: does snow actually settle on the canopy?
  --
  -- The shader change gives a crown the TOP share of snow instead of the
  -- flank's (canopyCap in Voxel3D). That is a claim about pixels, so shoot
  -- it: same camera, same map, weather off then snow, and measure the
  -- difference rather than admire the picture.
  --
  -- Weather.BUILD is 20 SECONDS to peak. Counting a few frames would shoot
  -- a flurry and conclude the feature does nothing.
  local Weather = lib.require("Weather")
  pcall(function() game.overworld:setMap("ROUTE_2", 10, 10, "up") end)
  settle("ROUTE_2 winter")
  Weather.setting:sync("off")
  wait(240)
  shot("trees_winter_off")
  Weather.setting:sync("snow")
  -- 20s at 60fps is 1200 frames to peak; give it that plus settle. The
  -- lamps probe learned this the hard way with the night tint: two shots
  -- either side of a ramp differ across the whole frame and bury the local
  -- change being measured.
  wait(1500)
  log("weather kind =", tostring(Weather.setting:get()),
      "| winter =", tostring(Weather.isWinter()))
  shot("trees_winter_snow")
  Weather.setting:sync("auto")

  -- ---- WHAT THE FOREST COSTS.
  --
  -- 862 trees x 420 tris is ~362k triangles in one mesh on an integrated
  -- GPU, and the module's own header admits the combined mesh is built on
  -- the first frame it is drawn rather than inside the chunk builder's
  -- pump. Both of those are claims, so measure them instead of asserting
  -- they are fine. Three numbers, because they answer different questions:
  --
  --   draw    trees drawn vs not drawn, same mesh built -- the per-frame
  --           GPU cost of the forest.
  --   cards   the sun pass with the card-less shadow mesh vs with the full
  --           one, which is the only way to know what dropping the 120
  --           alpha cards from the depth pass actually bought.
  --   vs hull authored trees vs the hulls they REPLACED -- the honest
  --           baseline, since "off" is not an option a player has.
  --   build   how long the one-time combined-mesh build actually stalls.
  --
  -- EVERY NUMBER HERE IS SAMPLED AFTER settle(), NOT AFTER A WAIT. The
  -- previous run put the tail of an 862-site build inside its own sample
  -- and billed the forest 73 ms for it.
  --
  -- And each state is sampled several times and reported as a median with
  -- its spread. A single sample on this hardware is not a cost, it is a
  -- draw from a distribution wide enough to swallow the effects being
  -- measured -- the run before last differed from the last by more than
  -- the sun pass it was trying to price.

  pcall(function() game.overworld:setMap("ROUTE_2", 10, 10, "up") end)
  settle("ROUTE_2 cost run")

  -- CLEAR THE SKY FIRST. The previous run measured +64% with a snowstorm
  -- still fading out of frame -- weather is full-screen per-fragment work,
  -- so it lands entirely inside the number and gets attributed to the
  -- trees. Weather.CLEAR_FADE is 14 seconds; give it that and more.
  local Weather = lib.require("Weather")
  Weather.setting:sync("off")
  wait(1000)
  log("weather at measure time =", tostring(Weather.setting:get()))
  -- Cheap insurance: the fade is long enough for a neighbour to have gone
  -- cold and started its own build.
  settle("ROUTE_2 after clearing")

  -- ONE WRAPPER FOR THE WHOLE A/B, so the counters survive every state
  -- change. The old probe swapped Trees3D.castShadows for a no-op, which
  -- also swapped away the only evidence that the sun pass ran at all --
  -- and it does not always run: VoxelScene gates it behind
  -- ShadowMap.stale(), so a world standing perfectly still skips the depth
  -- pass entirely and "the sun pass costs +0.0 ms" would be a true
  -- statement about a pass that never executed.
  --
  -- COUNT THE INVOCATION BEFORE THE SWITCH, not after. Counting only the
  -- calls that do work makes "the sun pass never ran" and "the sun pass
  -- ran and we skipped the trees" produce the identical 0.00/tick, which
  -- is precisely the pair the counter exists to tell apart.
  --
  -- And count only the map UNDERFOOT. VoxelScene calls both of these once
  -- per neighbour as well, so counting every call would report five draws
  -- a frame on a route and be useless as the frame counter this doubles
  -- as: ticks are driver resumptions, and only a count of the map's own
  -- draw says how many of them actually rendered the world.
  local realDraw, realCast = Trees3D.draw, Trees3D.castShadows
  local drawOn, castOn = true, true
  local draws, casts = 0, 0
  local function isHere(map)
    return map and game.overworld and game.overworld.map == map
  end
  Trees3D.draw = function(map, ...)
    if isHere(map) then draws = draws + 1 end
    if not drawOn then return end
    return realDraw(map, ...)
  end
  Trees3D.castShadows = function(map, ...)
    if isHere(map) then casts = casts + 1 end
    if not castOn then return end
    return realCast(map, ...)
  end

  local SAMPLES, FRAMES = 3, 100
  -- Median of several samples, never one. Sorted so the caller can quote
  -- the spread alongside it -- a median without its spread is a single
  -- sample with better manners.
  -- Per TICK and per RENDERED FRAME both, because they are only the same
  -- number if the driver is resumed once per frame. main.lua resumes it
  -- POKEPORT_SPEED times per frame, and a frame that renders nothing (an
  -- inactive window) still ticks -- so the per-frame column is the one
  -- that stays true when the assumption does not.
  local SETTLE = 40
  local function medianCost(n, frames)
    local perTick, perFrame = {}, {}
    for i = 1, n do
      wait(SETTLE)                   -- let the state change take effect
      local d0 = draws
      local t0 = love.timer.getTime()
      for _ = 1, frames do coroutine.yield() end
      local el = love.timer.getTime() - t0
      perTick[i] = el / frames * 1000
      perFrame[i] = el / math.max(draws - d0, 1) * 1000
    end
    table.sort(perTick)
    table.sort(perFrame)
    local mid = math.ceil(n / 2)
    return perTick[mid], perTick, perFrame[mid]
  end

  local function measure(label)
    local d0, c0 = draws, casts
    local med, ms, medFrame = medianCost(SAMPLES, FRAMES)
    -- EVERY tick the window spent, settle waits included. Dividing the
    -- counter by the sampled ticks alone reported 1.40 draws/tick for a
    -- world that was drawing exactly once per tick -- 420 ticks of counting
    -- over a 300-tick denominator, an artefact of the report and not a
    -- fact about the engine.
    local ticks = SAMPLES * (FRAMES + SETTLE)
    log(string.format("  %-18s %6.2f ms/tick (min %6.2f, max %6.2f, "
                      .. "spread %3.0f%%) | %6.2f ms/frame | scene %.2f/tick "
                      .. "sun %.2f/tick",
                      label, med, ms[1], ms[SAMPLES],
                      (ms[SAMPLES] / math.max(ms[1], 1e-6) - 1) * 100,
                      medFrame, (draws - d0) / ticks, (casts - c0) / ticks))
    return med, (casts - c0) / ticks, (draws - d0) / ticks
  end

  log("ROUTE_2 clear sky, " .. SAMPLES .. " samples of " .. FRAMES
      .. " frames per state:")
  drawOn, castOn, Trees3D.SHADOW_SOLID_ONLY = true, true, true
  local msFull, sunRate, frameRate = measure("full (shipped)")
  -- If a tick is not a frame, every ms/tick number here is scaled by
  -- whatever the ratio is and the deltas are not comparable to any earlier
  -- run. Say so rather than letting the numbers pass as per-frame costs.
  log(string.format("  the world rendered %.2f times per driver tick", frameRate))
  log(frameRate > 0.95
      and "PASS: one tick is one rendered frame, ms/tick IS ms/frame"
      or "WARN: ticks and frames are not 1:1 -- read the ms/frame column")

  -- The sun pass fed the FULL mesh -- cards and all. This is the state the
  -- shadow mesh was introduced to replace, and the only honest way to
  -- price it.
  Trees3D.SHADOW_SOLID_ONLY = false
  local msCards = measure("+ shadow cards")
  Trees3D.SHADOW_SOLID_ONLY = true

  castOn = false
  local msNoShadow = measure("draw only")

  drawOn = false
  local msNeither = measure("neither")

  -- Back to the shipped state and measure it AGAIN. If this drifts from
  -- the first reading by more than the effects above, the run was thermal
  -- or GC noise wearing a measurement's clothes and nothing below it can
  -- be trusted. On a fanless i3 that is not a hypothetical.
  drawOn, castOn = true, true
  local msFull2 = measure("full (drift check)")

  Trees3D.draw, Trees3D.castShadows = realDraw, realCast
  wait(40)

  local drift = math.abs(msFull2 - msFull)
  log(string.format("  scene draw costs   %+.2f ms (%+.0f%%)",
                    msNoShadow - msNeither,
                    (msNoShadow / math.max(msNeither, 1e-6) - 1) * 100))
  log(string.format("  SUN PASS costs     %+.2f ms (%+.0f%% on top)",
                    msFull - msNoShadow,
                    (msFull / math.max(msNoShadow, 1e-6) - 1) * 100))
  log(string.format("  ...with the cards  %+.2f ms", msCards - msNoShadow))
  log(string.format("  CARD-LESS SHADOW MESH SAVES %+.2f ms "
                    .. "(%.0f%% of the sun pass)",
                    msCards - msFull,
                    (msCards - msFull) / math.max(msCards - msNoShadow, 1e-6)
                      * 100))
  log(string.format("  drift on the repeat: %.2f ms", drift))
  -- THE SIGN IS PART OF THE CLAIM. An earlier version of this line asked
  -- only whether the difference was bigger than the drift, which a saving
  -- of MINUS one and a half milliseconds passes with a PASS next to it.
  -- The optimization is only real if it is positive AND clears the noise.
  local saved = msCards - msFull
  local noise = math.max(drift, (msFull2 - msFull) * 0 + drift)
  if saved > noise then
    log("PASS: dropping the cards from the depth pass really is cheaper")
  elseif math.abs(saved) <= noise then
    log("INCONCLUSIVE: the card difference is inside this run's own drift "
        .. "-- the depth pass is not triangle-bound at this size")
  else
    log("FAIL: the card-less shadow mesh measured SLOWER than the full one "
        .. "by " .. string.format("%.2f ms", -saved)
        .. " -- it is not buying what its comment claims")
  end
  -- The sun pass is gated by ShadowMap.stale(): if the world held still
  -- the depth pass never ran, and every shadow number above is a true
  -- statement about work that did not happen.
  log(string.format("  sun pass ran %.2f times per frame during the sample",
                    sunRate))
  log(sunRate > 0.5
      and "PASS: the sun pass was actually re-rendering while it was priced"
      or "FAIL: the depth pass was cached (ShadowMap.stale) -- the shadow "
         .. "numbers above price nothing")
  local msOn, msOff = msFull, msNeither

  -- The one-time build, timed on a cold cache, three times: the last two
  -- runs reported 760.8 ms and 2185.7 ms for the same 862 sites, and
  -- SLICE_SITES is calibrated off this number, so one sample of it is not
  -- a calibration.
  local buildRuns = {}
  for i = 1, 3 do
    Trees3D.invalidate()
    wait(20)
    local tb = love.timer.getTime()
    local built = Trees3D.meshesFromSites(
      Structures.forMap(game.overworld.map).treeSites)
    buildRuns[i] = (love.timer.getTime() - tb) * 1000
    if not built then log("FAIL: synchronous build returned nothing") end
  end
  table.sort(buildRuns)
  local nTrees = Trees3D.count(game.overworld.map)
  log(string.format("combined-mesh build: %.1f ms median (%.1f .. %.1f) for "
                    .. "%d trees = %.2f ms/site, so a %d-site slice is %.1f ms",
                    buildRuns[2], buildRuns[1], buildRuns[3], nTrees,
                    buildRuns[2] / math.max(nTrees, 1),
                    Trees3D.SLICE_SITES,
                    buildRuns[2] / math.max(nTrees, 1) * Trees3D.SLICE_SITES))
  Trees3D.invalidate()

  -- And against the hulls. Emptying SPECIES makes available() false, so
  -- Structures goes back to emitting hull quads on the next build -- which
  -- is the thing a player would actually be looking at instead.
  local keep = Trees3D.SPECIES
  Trees3D.SPECIES = {}
  Trees3D.reload()
  pcall(function() V.require("ChunkMesher").invalidate() end)
  pcall(function() game.overworld:setMap("VIRIDIAN_CITY", 10, 10, "up") end)
  settle("VIRIDIAN_CITY hull rebuild")
  pcall(function() game.overworld:setMap("ROUTE_2", 10, 10, "up") end)
  settle("ROUTE_2 hull baseline")
  local RS = Structures.forMap(game.overworld.map)
  log("hull baseline: sites =", #(RS.treeSites or {}),
      "hulls =", #(RS.roundStamps or {}))
  -- Same rig as every state above: median of SAMPLES, not one reading.
  local msHull, hullMs = medianCost(SAMPLES, FRAMES)
  log(string.format("  %-18s %6.2f ms  (min %6.2f, max %6.2f)",
                    "hulls", msHull, hullMs[1], hullMs[SAMPLES]))
  log(string.format("frame cost ROUTE_2: authored %.2f ms vs hulls %.2f ms, "
                    .. "delta %+.2f ms (%+.0f%%)",
                    msOn, msHull, msOn - msHull,
                    (msOn / math.max(msHull, 1e-6) - 1) * 100))
  shot("trees_hull_baseline")
  -- Restoring SPECIES is not restoring the WORLD: the chunk mesh for this
  -- map was rebuilt with hull quads and Structures still caches them, so a
  -- later section measuring "trees" would be measuring hulls. That is
  -- exactly how the first winter shot came out showing snow on hulls.
  Trees3D.SPECIES = keep
  Trees3D.reload()
  pcall(function() V.require("ChunkMesher").invalidate() end)
  pcall(function() game.overworld:setMap("VIRIDIAN_CITY", 10, 10, "up") end)
  settle("VIRIDIAN_CITY restored")

  log("done")
  logf:close()
  wait(10)
  love.event.quit()
end
