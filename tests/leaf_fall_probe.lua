-- Leaves that fall, lie where they land and scatter underfoot, measured.
--
-- The laws behind these are proved offline (tests/leaf_fall_offline.lua);
-- this is the same module on a real route, each claim as a number:
--
--   SEED     Route 1 binds with its ground already seeded: every lying leaf
--            on a surveyed open cell at floor + RAISE, no crown cell open,
--            no cell over PER_CELL
--   FALL     at GALE, leaves let go from real crowns and lie down on open
--            ground; the ground's count moves by exactly
--            landed - kicked - evicted
--   CALM     wind row OFF: leaves still fall, seeds and petals do not
--   KICK     walking a straight run through a pile lifts it off the path,
--            and every kicked leaf lies down again or is counted lost
--   KEEP     a trip to Viridian and back finds the same ground; a forgotten
--            route is seeded identically
--   PIXELS   the ground draws: one pose with the litter on, off, on
--   COST     a still ground rewrites no vertex; update allocation per frame;
--            update and draw milliseconds (reported only -- armadilha 5)
--   FOREST   Viridian Forest, whose sky is not open, grows leaves too
--   CLEAN    no errors, canaries alive
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/leaf_fall_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/leaf_fall.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  -- the capture runs on the next PRESENT, not the next update: wait for the
  -- callback, never for a number of yields (armadilha 7)
  local function shotData(name)
    local done, keep = false, nil
    love.graphics.captureScreenshot(function(data)
      keep = data
      -- an error thrown in here surfaces from present() and closes the game
      local ok, err = pcall(function()
        local f = io.open(OUT .. "/" .. name, "wb")
        if f then f:write(data:encode("png"):getString()) f:close() end
      end)
      if not ok then log("capture " .. name .. " failed: " .. tostring(err)) end
      done = true
    end)
    local guard = 0
    while not done and guard < 240 do coroutine.yield(); guard = guard + 1 end
    return keep
  end
  local function verdict(ok) return ok and "PASS" or "FAIL" end
  -- A Lua error anywhere in the frame goes to the engine's handler, which
  -- closes the game without a word in this log: write it down first.
  local prevHandler = love.errorhandler or love.errhand
  love.errorhandler = function(msg)
    local tb = (debug and debug.traceback) and debug.traceback(tostring(msg), 2)
               or tostring(msg)
    log("ERROR HANDLER: " .. tb)
    if prevHandler then return prevHandler(msg) end
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit() return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end
  -- A scripted press has no source to release it: Input:step() sets
  -- state[btn] = true for a pressQueue inject and nothing ever clears it.
  -- The "a" above would stay held all run, and the kick's walk "right"
  -- walked the player into the tree line after every later setMap.
  -- Release everything whenever a scripted stretch of input is done.
  local function releaseAll()
    local input = game.input
    if input.reset then
      input:reset()
    else
      for i = #input.pressQueue, 1, -1 do input.pressQueue[i] = nil end
      for k in pairs(input.state) do input.state[k] = false end
    end
  end
  releaseAll()

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end
  log("version:", exports.TERRARIUM.version)

  local Weather  = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Wind     = lib.require("Wind")
  local WindFX   = lib.require("WindFX")
  local StepFX   = lib.require("StepFX")
  local VegFX    = lib.require("VegFX")
  local LeafFallFX = lib.require("LeafFallFX")
  local LeafLitter = lib.require("LeafLitter")
  local AmbientLife = lib.require("AmbientLife")
  local Quality  = lib.require("Quality")
  local Voxel3D  = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")

  -- a still stage: no weather, no critters or townsfolk wandering through
  -- the shots, and FULL resolution so the canvas and the screenshot share
  -- their pixels
  Weather.setting:sync("off")
  AmbientLife.setting:sync("off")
  for _, name in ipairs({ "WildRoamers", "CityLife", "Routines" }) do
    local ok, M = pcall(lib.require, name)
    if ok and type(M) == "table" and M.setting then
      pcall(M.setting.sync, M.setting, "off")
    end
  end
  Quality.particleSetting:sync(1)
  pcall(Quality.setting.sync, Quality.setting, 1)
  Pipelines.setLevel("terrarium_voxel", 4)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  DayNight.setting:sync("day")
  Wind.setting:sync(4)                 -- GALE
  local ow = game.overworld
  local RAISE, PER_CELL = LeafFallFX.RAISE, LeafLitter.PER_CELL
  local function repel()
    if game.save then game.save.repelSteps = 9999 end
  end

  -- The first frame a map is bound, before anything lands on it or is
  -- kicked off it: bind clears the air, and every walker's trail is stale
  -- across a setMap, so that frame's ground is exactly the seed (or the
  -- memory).
  local function awaitBind(key, limit)
    for _ = 1, limit or 900 do
      coroutine.yield()
      local st = LeafFallFX.state()
      if st and st.key == key and LeafFallFX.lastGate == "live" then
        return st, st.store:checksum(), st.store.count
      end
    end
    return nil
  end

  local function validate(st)
    local s = st.store
    local off, height = 0, 0
    for i = 1, s.high do
      if s.used[i] then
        local c = s:cellOf(s.x[i], s.z[i])
        if not (c and st.ok[c]) then
          off = off + 1
        elseif math.abs(s.y[i] - (st.floor[c] + RAISE)) > 1e-6 then
          height = height + 1
        end
      end
    end
    return off, height
  end

  -- ------- SEED
  ow:setMap("ROUTE_1", 10, 20, "up")
  repel()
  local key = tostring(ow.map.id)
  local st, seedSum, seedCount = awaitBind(key, 1200)
  if not st then
    log(("FAIL: the leaves never bound %s (gate [%s], error %s)")
        :format(key, tostring(LeafFallFX.lastGate), tostring(LeafFallFX.lastError)))
    logf:close(); love.event.quit(); return
  end
  local s = st.store
  local trees = VegFX.sitesFor(ow.map).trees
  do
    local off, height = validate(st)
    local crownOpen = 0
    for i = 1, #trees do
      local c = s:cellOf(trees[i].x, trees[i].z)
      if c and st.ok[c] then crownOpen = crownOpen + 1 end
    end
    log(("seed: map %s  %dx%d cells, %d open  %d crowns  seeded %d of cap %d  checksum %d")
        :format(key, s.cols, s.rows, st.open, st.trees, st.seeded, s.cap, seedSum))
    log(("seed verdict: count %d  off-cell %d  wrong height %d  per-cell max %d/%d"
         .. "  crowns marked open %d  %s")
        :format(seedCount, off, height, s:perCellMax(), PER_CELL, crownOpen,
                verdict(seedCount >= 100 and seedCount == st.seeded and off == 0
                        and height == 0 and s:perCellMax() <= PER_CELL
                        and crownOpen == 0)))
  end
  -- a capture before anything else happens: if capturing itself is broken
  -- on this build, it shows here and not in the middle of the kick
  do
    local img = shotData("seed.png")
    log(("capture: seed.png %s"):format(img and "taken" or "MISSING"))
  end

  -- ------- FALL, at GALE
  wait(60)
  repel()
  do
    local a0 = { shed = LeafFallFX.shedCount, veg = VegFX.emittedLeaf,
                 landed = LeafFallFX.landed, lost = LeafFallFX.lost,
                 kicked = LeafFallFX.kicked, evicted = s.evicted,
                 replaced = LeafFallFX.replaced,
                 count = s.count, air = LeafFallFX.count() }
    local young, far, worst, maxAir = 0, 0, 0, 0
    for i = 1, 600 do
      coroutine.yield()
      local up = LeafFallFX.count()
      if up > maxAir then maxAir = up end
      if i % 5 == 0 then
        for j = 1, up do
          local m = LeafFallFX.get(j)
          -- where it let go, not where the gale has carried it since
          if m and m.kind == "fall" and m.bornX and m.t < 0.15 then
            local best = 1e9
            for k = 1, #trees do
              local t = trees[k]
              local dx, dz = m.bornX - t.x, m.bornZ - t.z
              local d = math.sqrt(dx * dx + dz * dz)
              if d < best then best = d end
            end
            young = young + 1
            if best > worst then worst = best end
            if best > LeafFallFX.SHED_R + 0.01 then far = far + 1 end
          end
        end
      end
    end
    local dShed = LeafFallFX.shedCount - a0.shed
    local dVeg = VegFX.emittedLeaf - a0.veg
    local dLand = LeafFallFX.landed - a0.landed
    local dLost = LeafFallFX.lost - a0.lost
    local dKick = LeafFallFX.kicked - a0.kicked
    local dEvict = s.evicted - a0.evicted
    local dRepl = LeafFallFX.replaced - a0.replaced
    local up = LeafFallFX.count()
    -- whatever let go and neither lay down, was lost nor is still up ran
    -- out of reach or ttl in the air
    local expired = (dShed + dKick) - (dLand + dLost) - (up - a0.air)
    local identity = (s.count - a0.count) == (dLand - dKick - dEvict - dRepl)
    local off, height = validate(st)
    log(("fall: amount %.2f  shed %d (VegFX says %d)  landed %d  lost %d  still up %d"
         .. "  expired %d  max in the air %d")
        :format(Wind.amount(), dShed, dVeg, dLand, dLost, up, expired, maxAir))
    log(("fall: ground %d -> %d  (landed %d - kicked %d - evicted %d - replaced %d = %d)")
        :format(a0.count, s.count, dLand, dKick, dEvict, dRepl,
                dLand - dKick - dEvict - dRepl))
    log(("fall verdict: shed %d  landed %d  identity %s  off %d  height %d  %s")
        :format(dShed, dLand, tostring(identity), off, height,
                verdict(dShed >= 10 and dShed == dVeg and dLand >= 3 and identity
                        and off == 0 and height == 0)))
    log(("origin: %d young falling leaves, worst distance from a crown at birth"
         .. " %.1f px (SHED_R %d), beyond it %d  %s")
        :format(young, worst, LeafFallFX.SHED_R, far, verdict(young >= 5 and far == 0)))
  end

  -- ------- CALM
  do
    Wind.setting:sync(0)
    wait(420)                         -- the smoothed amount has to sink first
    local l1, s1, f1 = VegFX.emittedLeaf, VegFX.emittedSeed, VegFX.emittedPetal
    wait(600)
    local leaves = VegFX.emittedLeaf - l1
    local other = (VegFX.emittedSeed - s1) + (VegFX.emittedPetal - f1)
    log(("calm: amount %.2f  leaves %d  seeds+petals %d  gates [%s] / [%s]  %s")
        :format(Wind.amount(), leaves, other, tostring(VegFX.lastGate),
                tostring(VegFX.windGate),
                verdict(leaves > 0 and other == 0
                        and VegFX.windGate == "wind below FLOOR")))
  end

  -- ------- KICK
  local keepShed = LeafFallFX.shed
  LeafFallFX.shed = function() return false end
  -- whatever is still up lands first, so the ledger starts empty
  for _ = 1, 900 do
    if LeafFallFX.count() == 0 then break end
    coroutine.yield()
  end
  -- a straight east-west run of open cells, open beside it where possible
  local function findRun(state, len)
    local sto = state.store
    local cols, rows = sto.cols, sto.rows
    local pcx, pcz = ow.player.cellX, ow.player.cellY
    local best, bestScore = nil, -1e9
    for cz = 1, rows - 2 do
      local run = 0
      for cx = 0, cols - 1 do
        local c = cz * cols + cx + 1
        if state.ok[c] then run = run + 1 else run = 0 end
        if run >= len then
          local sx = cx - len + 1
          local sides = 0
          for k = sx, cx do
            local ck = c - (cx - k)
            if state.ok[ck - cols] then sides = sides + 1 end
            if state.ok[ck + cols] then sides = sides + 1 end
          end
          local score = sides * 4 - (math.abs(sx - pcx) + math.abs(cz - pcz))
          if score > bestScore then
            best, bestScore = { cx = sx, cz = cz, sides = sides }, score
          end
        end
      end
    end
    return best
  end
  do
    local LEN = 8
    local run = findRun(st, LEN)
    if not run then
      log(("kick: FAIL no straight run of %d open cells on %s"):format(LEN, key))
    else
      ow:setMap(key, run.cx, run.cz, "right")
      repel()
      -- the player keeps moving a moment after setMap: wait for a still cell
      local still, lastX, lastZ = 0, nil, nil
      for _ = 1, 600 do
        coroutine.yield()
        local pl = ow.player
        if pl.px == lastX and pl.py == lastZ then still = still + 1 else still = 0 end
        lastX, lastZ = pl.px, pl.py
        if still >= 30 then break end
      end
      st = LeafFallFX.state()
      s = st.store
      -- setMap does not always leave the player on the cell it was handed
      -- (the first run of this probe asked for 5,15 and stood on 5,16):
      -- walk the row the player actually stands on, if it is open
      local function openRun(cx, cz)
        for k = 0, LEN - 1 do
          local c = s:cellOf((cx + k) * 16 + 8, cz * 16 + 8)
          if not (c and st.ok[c]) then return false end
        end
        return true
      end
      local pl = ow.player
      if pl.cellX ~= run.cx or pl.cellY ~= run.cz then
        log(("kick: asked for %d,%d, standing on %d,%d  row open %s")
            :format(run.cx, run.cz, pl.cellX, pl.cellY,
                    tostring(openRun(pl.cellX, pl.cellY))))
        if openRun(pl.cellX, pl.cellY) then
          run.cx, run.cz = pl.cellX, pl.cellY
        end
      end
      local zc = run.cz * 16 + 8
      local out = {}
      for cx = run.cx, run.cx + LEN - 1 do
        local got = s:collect(cx * 16 + 8, zc, 12, LeafFallFX.clock() + 1e6, 0, out)
        for k = 1, got do s:remove(out[k]) end
      end
      local laid = 0
      for cx = run.cx + 2, run.cx + 6 do
        for k = 0, 3 do
          local z = zc + ((k % 2 == 0) and -3 or 3)
          if LeafFallFX.deposit(cx * 16 + 2 + k * 4, z,
                                LeafFallFX.lyingFrame(k % 2, 0.3), k * 1.3) then
            laid = laid + 1
          end
        end
      end
      local xa, xb = (run.cx + 1) * 16, (run.cx + LEN) * 16
      local function band(lo, hi)
        local c = 0
        for i = 1, s.high do
          if s.used[i] and s.x[i] >= xa and s.x[i] < xb then
            local dz = math.abs(s.z[i] - zc)
            if dz > lo and dz <= hi then c = c + 1 end
          end
        end
        return c
      end
      wait(20)
      local N0, side0 = band(-1, 7), band(7, 40)
      local c0 = { count = s.count, kicked = LeafFallFX.kicked,
                   landed = LeafFallFX.landed, lost = LeafFallFX.lost,
                   evicted = s.evicted, replaced = LeafFallFX.replaced }
      log(("kick: run of %d open cells from %d,%d (open beside it %d)  player at %d,%d"
           .. "  laid %d  on the path %d  beside it %d")
          :format(LEN, run.cx, run.cz, run.sides, ow.player.cellX, ow.player.cellY,
                  laid, N0, side0))
      shotData("kick_before.png")
      local startCell = ow.player.cellX
      local queue = game.input.pressQueue
      for _ = 1, 300 do
        -- one press at a time, released when the walk is done: the press
        -- latches state.right (see releaseAll), so the walk would go on
        -- long after the probe stopped asking for it
        if #queue == 0 then queue[1] = "right" end
        coroutine.yield()
        if ow.player.cellX >= run.cx + LEN - 1 then break end
      end
      releaseAll()
      local walked = ow.player.cellX - startCell
      for _ = 1, 600 do
        if LeafFallFX.count() == 0 then break end
        coroutine.yield()
      end
      wait(10)
      shotData("kick_after.png")
      local N1, side1 = band(-1, 7), band(7, 40)
      local dk = LeafFallFX.kicked - c0.kicked
      local dl = LeafFallFX.landed - c0.landed
      local dx = LeafFallFX.lost - c0.lost
      local de = s.evicted - c0.evicted
      local dr = LeafFallFX.replaced - c0.replaced
      local accounted = LeafFallFX.count() == 0 and dk == dl + dx
      local identity = (s.count - c0.count) == (dl - dk - de - dr)
      log(("kick: walked %d cells  kicked %d  lay down again %d  lost %d  still up %d"
           .. "  evicted %d  replaced %d")
          :format(walked, dk, dl, dx, LeafFallFX.count(), de, dr))
      log(("kick: on the path %d -> %d   beside it %d -> %d   ground %d -> %d")
          :format(N0, N1, side0, side1, c0.count, s.count))
      log(("kick verdict: walked %s  kicked>=80%% %s  path<=25%% %s  accounted %s"
           .. "  identity %s  to the sides %s  %s")
          :format(tostring(walked >= LEN - 2), tostring(dk >= 0.8 * N0),
                  tostring(N1 <= 0.25 * N0), tostring(accounted), tostring(identity),
                  tostring(side1 - side0 >= 0.4 * dl),
                  verdict(N0 >= 15 and walked >= LEN - 2 and dk >= 0.8 * N0
                          and N1 <= 0.25 * N0 and accounted and identity
                          and side1 - side0 >= 0.4 * dl)))
    end
  end

  -- ------- KEEP
  do
    releaseAll()
    st = LeafFallFX.state()
    s = st.store
    local sumAway, countAway = s:checksum(), s.count
    ow:setMap("VIRIDIAN_CITY", 20, 30, "down")
    repel()
    local vkey = tostring(ow.map.id)
    for _ = 1, 900 do
      coroutine.yield()
      local cur = LeafFallFX.state()
      if (cur and cur.key == vkey) or LeafFallFX.lastGate == "no trees here" then break end
    end
    log(("keep: away on %s  gate [%s]  bound %s")
        :format(vkey, tostring(LeafFallFX.lastGate),
                tostring(LeafFallFX.state() and LeafFallFX.state().key)))
    wait(60)
    ow:setMap(key, 10, 20, "up")
    repel()
    local back, sumBack, countBack = awaitBind(key, 1200)
    log(("keep: back on %s  checksum %d -> %s  count %d -> %s  same state %s  %s")
        :format(key, sumAway, tostring(sumBack), countAway, tostring(countBack),
                tostring(back == st),
                verdict(back == st and sumBack == sumAway and countBack == countAway)))
    LeafFallFX.forget()
    local fresh, sumFresh, countFresh = awaitBind(key, 300)
    log(("keep: forgotten and bound again  checksum %s (first seed %d)  count %s (%d)  %s")
        :format(tostring(sumFresh), seedSum, tostring(countFresh), seedCount,
                verdict(fresh ~= nil and sumFresh == seedSum and countFresh == seedCount)))
    st = fresh or LeafFallFX.state()
    s = st and st.store
  end

  -- ------- PIXELS
  if st then
    local keepShadow = Quality.shadowSetting:get()
    pcall(Quality.shadowSetting.sync, Quality.shadowSetting, "off")
    local keepAmount = Wind.amount
    Wind.amount = function() return 0 end        -- everything that sways, still
    -- Where the pile goes decides what this gate measures. One run had its
    -- box reach under a crown, where the depth test hides a lying leaf --
    -- correctly. This gate is about the draw on OPEN ground: no flower bed
    -- in or beside the cell (they animate, and they are red), and no crown
    -- in the cell or in the three rows between it and the camera, which
    -- looks from the south.
    local sites = VegFX.sitesFor(ow.map)
    local flowerAt, treeAt = {}, {}
    for _, f in ipairs(sites.flowers) do
      local c = s:cellOf(f.x, f.z)
      if c then flowerAt[c] = true end
    end
    for _, t in ipairs(sites.trees) do
      local c = s:cellOf(t.x, t.z)
      if c then treeAt[c] = true end
    end
    local function clear(cx, cz)
      for dz = -1, 3 do
        for dx = -1, 1 do
          local c = s:cellOf((cx + dx) * 16 + 8, (cz + dz) * 16 + 8)
          if c and treeAt[c] then return false end
          if c and dz <= 1 and flowerAt[c] then return false end
        end
      end
      return true
    end
    local function pileCells(pcx, pcz)
      local found = {}
      for dz = -5, -2 do
        for dx = -3, 3 do
          local cx, cz = pcx + dx, pcz + dz
          local c = s:cellOf(cx * 16 + 8, cz * 16 + 8)
          if c and st.ok[c] and clear(cx, cz) then
            found[#found + 1] = { cx = cx, cz = cz, c = c }
          end
        end
      end
      return found
    end
    -- and somewhere to stand with the most of that ground ahead: two runs
    -- found none around the cell a latched press had walked the player to
    local stand, most = nil, 0
    for cz = 0, s.rows - 1 do
      for cx = 0, s.cols - 1 do
        if st.ok[cz * s.cols + cx + 1] then
          local count = #pileCells(cx, cz)
          if count > most then stand, most = { cx = cx, cz = cz }, count end
        end
      end
    end
    if stand then
      releaseAll()
      ow:setMap(key, stand.cx, stand.cz, "up")
      repel()
      local still, lastX, lastZ = 0, nil, nil
      for _ = 1, 600 do
        coroutine.yield()
        local p = ow.player
        if p.px == lastX and p.py == lastZ then still = still + 1 else still = 0 end
        lastX, lastZ = p.px, p.py
        if still >= 60 then break end
      end
      st = LeafFallFX.state()
      s = st.store
      log(("pixels: standing on %d,%d (asked %d,%d with %d clear cells ahead)")
          :format(ow.player.cellX, ow.player.cellY, stand.cx, stand.cz, most))
    end
    wait(90)
    -- The first run of this gate compared frames the SM64 camera had
    -- drifted between (the steps at the bottom moved 20 px): two ON frames
    -- differed more than ON and OFF. VoxelScene installs MarioCam.camera()
    -- every frame, so the camera is frozen by handing it one snapshot.
    local MarioCam = lib.require("MarioCam")
    local keepCamera = MarioCam.camera
    local frozen = keepCamera()
    if not frozen and Voxel3D.eye and Voxel3D.focus then
      local VoxelState = lib.require("VoxelState")
      frozen = { eye = { Voxel3D.eye[1], Voxel3D.eye[2], Voxel3D.eye[3] },
                 focus = { Voxel3D.focus[1], Voxel3D.focus[2], Voxel3D.focus[3] },
                 fov = 2 * math.atan(1 / (2 * (VoxelState.FOCAL or 1))) }
    end
    MarioCam.camera = function() return frozen end
    wait(30)
    local pl = ow.player
    local cells = pileCells(pl.cellX, pl.cellY)
    log(("pixels: %d open, clear cells ahead of the player at %d,%d")
        :format(#cells, pl.cellX, pl.cellY))
    local pile = {}
    for k = 1, math.min(3, #cells) do
      local cell = cells[k]
      for j = 0, 5 do
        local x = cell.cx * 16 + 3 + (j % 3) * 5
        local z = cell.cz * 16 + 4 + math.floor(j / 3) * 8
        -- the fall colourway only: orange is a colour nothing else on a
        -- route's ground has, which is what the test below keys on
        if LeafFallFX.deposit(x, z, LeafFallFX.lyingFrame(0, (j % 3) / 3), j * 1.1) then
          pile[#pile + 1] = { x = x, y = st.floor[cell.c] + RAISE, z = z }
        end
      end
    end
    wait(30)
    if #pile == 0 then
      log("pixels: FAIL no open, flowerless cell ahead of the player to lay a pile on")
    else
      -- the pile's own screen box, projected in the resume the first capture
      -- is scheduled in (the camera is frozen, but that is still the rule)
      local bx0, by0, bx1, by1 = 1e9, 1e9, -1e9, -1e9
      for _, l in ipairs(pile) do
        local px, py = Voxel3D.project(l.x, l.y, l.z)
        if px and py then
          l.sx, l.sy = px, py
          bx0, by0 = math.min(bx0, px), math.min(by0, py)
          bx1, by1 = math.max(bx1, px), math.max(by1, py)
        end
      end
      local sx, sy = (bx0 + bx1) * 0.5, (by0 + by1) * 0.5
      local A = shotData("leaf_on.png")
      LeafFallFX.DRAW_LITTER = false
      local B = shotData("leaf_off.png")
      LeafFallFX.DRAW_LITTER = true
      local A2 = shotData("leaf_on2.png")
      if not (A and B and A2 and bx1 >= bx0) then
        log("pixels: FAIL a capture or the projection is missing")
      else
        local W, H = A:getDimensions()
        local x0 = math.max(0, math.floor(bx0 - 16))
        local y0 = math.max(0, math.floor(by0 - 16))
        local x1 = math.min(W - 1, math.floor(bx1 + 16))
        local y1 = math.min(H - 1, math.floor(by1 + 16))
        local function lum(r, g, b) return 0.299 * r + 0.587 * g + 0.114 * b end
        -- dAB: pixels the two ON frames agree on and OFF does not -- what
        -- the toggle alone explains. dAA: pixels the two ON frames disagree
        -- on -- whatever else moved.
        local dAB, dAA = 0, 0
        for y = y0, y1 do
          for x = x0, x1 do
            local r1, g1, b1 = A:getPixel(x, y)
            local r2, g2, b2 = B:getPixel(x, y)
            local r3, g3, b3 = A2:getPixel(x, y)
            local l1, l2, l3 = lum(r1, g1, b1), lum(r2, g2, b2), lum(r3, g3, b3)
            if math.abs(l1 - l3) > 0.03 then
              dAA = dAA + 1
            elseif math.abs(l1 - l2) > 0.03 then
              dAB = dAB + 1
            end
          end
        end
        local function crop(img, name)
          local w, h = x1 - x0 + 1, y1 - y0 + 1
          local c = love.image.newImageData(w, h)
          c:paste(img, 0, 0, x0, y0, w, h)
          local f = io.open(OUT .. "/" .. name, "wb")
          if f then f:write(c:encode("png"):getString()) f:close() end
        end
        crop(A, "leaf_on_crop.png")
        crop(B, "leaf_off_crop.png")
        log(("pixels: pile of %d, screen box %d,%d-%d,%d around %d,%d  window %dx%d  RES %s")
            :format(#pile, x0, y0, x1, y1, math.floor(sx), math.floor(sy), W, H,
                    tostring(Quality.scale and Quality.scale())))
        -- Not judged: the second run of this gate froze the camera and still
        -- saw 22% of the whole frame change between two ON captures -- the
        -- scene's own temporal dither and grain. A luminance diff measures
        -- that; it cannot measure a leaf.
        log(("pixels: (box, luminance: toggle-stable %d px, frame-to-frame noise %d px)")
            :format(dAB, dAA))
        -- Judged: every orange leaf of the pile shows orange where it was
        -- projected, in both ON frames, and none shows with the litter off.
        -- Grass, paving and bark are never that hue; the pile keeps off the
        -- flower beds, which are.
        local function orangeNear(img, px, py)
          for y = math.max(0, math.floor(py) - 6), math.min(H - 1, math.floor(py) + 6) do
            for x = math.max(0, math.floor(px) - 6), math.min(W - 1, math.floor(px) + 6) do
              local r, g, b = img:getPixel(x, y)
              if r > 0.5 and r - g > 0.18 and r - b > 0.3 then return true end
            end
          end
          return false
        end
        local projected, inA, inB, inA2 = 0, 0, 0, 0
        for k, l in ipairs(pile) do
          if l.sx then
            projected = projected + 1
            local a, b, a2 = orangeNear(A, l.sx, l.sy), orangeNear(B, l.sx, l.sy),
                             orangeNear(A2, l.sx, l.sy)
            if a then inA = inA + 1 end
            if b then inB = inB + 1 end
            if a2 then inA2 = inA2 + 1 end
            log(("pixels: LEAF %d world %d,%d -> screen %d %d  on %s off %s on2 %s")
                :format(k, l.x, l.z, math.floor(l.sx), math.floor(l.sy),
                        tostring(a), tostring(b), tostring(a2)))
          end
        end
        log(("pixels: orange at the leaf with the litter on %d/%d and %d/%d,"
             .. " off %d/%d  %s")
            :format(inA, projected, inA2, projected, inB, projected,
                    verdict(projected >= 6 and inA >= 0.7 * projected
                            and inA2 >= 0.7 * projected and inB <= 0.1 * projected)))
      end
    end
    MarioCam.camera = keepCamera
    Wind.amount = keepAmount
    pcall(Quality.shadowSetting.sync, Quality.shadowSetting, keepShadow)
  end

  -- ------- COST
  if st then
    LeafFallFX.shed = keepShed
    Wind.setting:sync(1)                 -- AUTO
    wait(300)
    local upd, drw = LeafFallFX.update, LeafFallFX.drawWorld
    local timer = love.timer.getTime
    local tU, kU, nU, tD, kD, nD = 0, 0, 0, 0, 0, 0
    -- split by whether leaves were up: the idle frame and the frame that
    -- runs the solver are different code, and whatever allocates lives in one
    local kAir, nAir, kIdle, nIdle = 0, 0, 0, 0
    LeafFallFX.update = function(dt, v)
      local up = LeafFallFX.count()
      collectgarbage("stop")
      local k0, t0 = collectgarbage("count"), timer()
      upd(dt, v)
      local dk = collectgarbage("count") - k0
      tU = tU + (timer() - t0)
      kU = kU + dk
      nU = nU + 1
      if up > 0 then
        kAir, nAir = kAir + dk, nAir + 1
      else
        kIdle, nIdle = kIdle + dk, nIdle + 1
      end
      collectgarbage("restart")
    end
    LeafFallFX.drawWorld = function()
      collectgarbage("stop")
      local k0, t0 = collectgarbage("count"), timer()
      local r = drw()
      tD = tD + (timer() - t0)
      kD = kD + (collectgarbage("count") - k0)
      nD = nD + 1
      collectgarbage("restart")
      return r
    end
    local w0 = { full = LeafFallFX.fullWrites, slot = LeafFallFX.slotWrites,
                 landed = LeafFallFX.landed, kicked = LeafFallFX.kicked }
    local maxAir = 0
    for _ = 1, 600 do
      coroutine.yield()
      if LeafFallFX.count() > maxAir then maxAir = LeafFallFX.count() end
    end
    local dFull = LeafFallFX.fullWrites - w0.full
    local dSlot = LeafFallFX.slotWrites - w0.slot
    local dChanges = (LeafFallFX.landed - w0.landed) + (LeafFallFX.kicked - w0.kicked)
    log(("cost: update %.4f ms %.4f KB per frame (%d frames)   draw %.4f ms %.4f KB"
         .. " (%d draws)   max %d in the air, %d on the ground")
        :format(nU > 0 and tU / nU * 1000 or -1, nU > 0 and kU / nU or -1, nU,
                nD > 0 and tD / nD * 1000 or -1, nD > 0 and kD / nD or -1, nD,
                maxAir, LeafFallFX.state().store.count))
    log(("cost: ground writes over the window: %d full, %d slots for %d landings + kicks  %s")
        :format(dFull, dSlot, dChanges, verdict(dFull == 0 and dSlot <= dChanges)))
    -- LuaJIT's own trace objects are counted by collectgarbage("count") too,
    -- so a window of fresh traces reads as allocation. The same work with
    -- the compiler off tells a trace being built from a table being made.
    if type(jit) == "table" and type(jit.off) == "function" then
      -- off AND flushed: traces already compiled keep running under off
      -- alone, and a trace exit can materialise what the trace had sunk
      jit.off()
      jit.flush()
      tU, kU, nU, tD, kD, nD = 0, 0, 0, 0, 0, 0
      kAir, nAir, kIdle, nIdle = 0, 0, 0, 0
      local l1, k1, w1 = LeafFallFX.landed, LeafFallFX.kicked, LeafFallFX.walkersSeen
      wait(400)
      jit.on()
      -- a walker met for the first time costs one small trail table: an
      -- engine that re-creates entity tables shows up here, not as a leak
      log(("cost: JIT off, %d frames, %d landings + kicks, %d walkers first met:"
           .. " update %.4f KB/frame  draw %.4f KB/draw  %s")
          :format(nU, (LeafFallFX.landed - l1) + (LeafFallFX.kicked - k1),
                  LeafFallFX.walkersSeen - w1,
                  nU > 0 and kU / nU or -1, nD > 0 and kD / nD or -1,
                  verdict(nU > 0 and kU / nU <= 0.02)))
      log(("cost: JIT off, split: %d idle frames at %.4f KB, %d frames with leaves up"
           .. " at %.4f KB")
          :format(nIdle, nIdle > 0 and kIdle / nIdle or -1,
                  nAir, nAir > 0 and kAir / nAir or -1))
    else
      log(("cost: no JIT here; update allocation %s")
          :format(verdict(nU > 0 and kU / nU <= 0.02)))
    end
    LeafFallFX.update, LeafFallFX.drawWorld = upd, drw

    LeafFallFX.shed = function() return false end
    Wind.setting:sync(0)
    for _ = 1, 900 do
      if LeafFallFX.count() == 0 then break end
      coroutine.yield()
    end
    wait(30)
    local q0 = { full = LeafFallFX.fullWrites, slot = LeafFallFX.slotWrites,
                 kicked = LeafFallFX.kicked, landed = LeafFallFX.landed }
    wait(240)
    local qFull = LeafFallFX.fullWrites - q0.full
    local qSlot = LeafFallFX.slotWrites - q0.slot
    local qChanges = (LeafFallFX.kicked - q0.kicked) + (LeafFallFX.landed - q0.landed)
    log(("cost: a still ground over 240 frames: %d full, %d slot writes"
         .. " (changes by walkers %d)  %s")
        :format(qFull, qSlot, qChanges, verdict(qFull == 0 and qSlot <= qChanges)))
    LeafFallFX.shed = keepShed
  end

  -- ------- FOREST, and a picture of it
  do
    Wind.setting:sync(2)                 -- BREEZE
    pcall(function() ow:setMap("VIRIDIAN_FOREST", 16, 40, "up") end)
    repel()
    local fkey = tostring(ow.map and ow.map.id)
    local fst = awaitBind(fkey, 900)
    log(("forest: %s  gate [%s]  bound %s  crowns %s  seeded %s  %s")
        :format(fkey, tostring(LeafFallFX.lastGate), tostring(fst and fst.key),
                tostring(fst and fst.trees), tostring(fst and fst.seeded),
                verdict(fst ~= nil and fst.seeded > 0)))
    if fst then
      -- somewhere to stand for the picture: open ground with crowns around
      -- it (the fixed cell of the first run put the camera inside a crown)
      local fs = fst.store
      local treeAt = {}
      for _, t in ipairs(VegFX.sitesFor(ow.map).trees) do
        local c = fs:cellOf(t.x, t.z)
        if c then treeAt[c] = true end
      end
      local best, bestScore = nil, -1
      for cz = 3, fs.rows - 4 do
        for cx = 3, fs.cols - 4 do
          if fst.ok[cz * fs.cols + cx + 1] then
            local open, crowns = 0, 0
            for dz = -3, 3 do
              for dx = -3, 3 do
                local c = (cz + dz) * fs.cols + (cx + dx) + 1
                if fst.ok[c] then open = open + 1 end
                if treeAt[c] then crowns = crowns + 1 end
              end
            end
            local score = math.min(open, 30) + math.min(crowns, 12)
            if score > bestScore then best, bestScore = { cx = cx, cz = cz }, score end
          end
        end
      end
      if best then
        pcall(function() ow:setMap(fkey, best.cx, best.cz, "up") end)
        repel()
        log(("forest: picture from %d,%d (score %d)"):format(best.cx, best.cz, bestScore))
      end
    end
    wait(400)
    shotData("leaf_forest.png")
    pcall(function() ow:setMap(key, 10, 20, "up") end)
    repel()
    wait(400)
    shotData("leaf_route.png")
  end

  -- ------- CLEAN
  log(("errors: update %s (%d)  draw %s (%d)  veg %s (%d)  %s")
      :format(tostring(LeafFallFX.lastError), LeafFallFX.errorCount,
              tostring(LeafFallFX.drawError), LeafFallFX.drawErrors,
              tostring(VegFX.lastError), VegFX.errorCount,
              verdict(LeafFallFX.errorCount == 0 and LeafFallFX.drawErrors == 0
                      and VegFX.errorCount == 0)))
  log(("canaries: LeafFallFX.ticks %d live %d batches %d  VegFX.ticks %d"
       .. "  WindFX.ticks %d  StepFX.ticks %d  Weather.ticks %s ok %s")
      :format(LeafFallFX.ticks, LeafFallFX.ticksLive, LeafFallFX.lastBatches,
              VegFX.ticks, WindFX.ticks, StepFX.ticks,
              tostring(Weather.ticks), tostring(Weather.ticksOk)))

  log("done")
  logf:close()
  love.event.quit()
end
