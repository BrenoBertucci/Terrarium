-- Probe: the Pokemon Tower stands as a tower (lib/TowerKit.lua), its glass
-- burns cold after dark (Voxel3D's HAUNTED GLASS) and it breathes wisps
-- (lib/GhostFX.lua).
--
--   BUILD   the TowerKit model builds (no fallback to the band fold), the
--           stamp records its haunt, and the camera's occluder height over
--           the tower's cells is the model's real top.
--   LOOK    screenshots, because a tower is a thing you look at: the F0
--           baseline frame (orbit camera, (10,10), day and night) for the
--           A/B against tests/baseline/f0/LAVENDER_TOWN_*.png; a HERO
--           frame from the plaza's south-west, low and wide, at dawn / day
--           / night; the authored door and west shots (tests/lavender_shots
--           _probe.lua re-verifies those; here they are only looked at).
--   HAUNT   at night the scene carries the haunt box, the shader is live
--           (the silent-2D-fallback trap), and the wisps are in the air.
--   COST    frame time at the hero frame, vsync off, day and night.
--
-- Traps respected (memory: terrarium-prop-bake-and-probe,
-- terrarium-probe-screenshot-race, terrarium-ambientlife-probe):
--   - the hour is pinned with DayNight.setting:sync(mode);
--   - the 3D pass is polled up via Voxel3D.lampLights, never frame-counted;
--   - a screenshot waits on its callback, never on a count of yields;
--   - the player walks on his own after setMap, so frames wait for the
--     cell to hold still, then ~200 frames for the tint ramp.
--
-- POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
-- POKEPORT_DRIVER=mods/TERRARIUM/tests/lavender_tower_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/lavender_tower_probe.log", "w"))
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

  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local Voxel3D = lib.require("Voxel3D")
  local Structures = lib.require("Structures")
  local Buildings = lib.require("Buildings")
  local StreetLamps = lib.require("StreetLamps")
  local MarioCam = lib.require("MarioCam")
  local MiniMap = lib.require("MiniMap")
  local AutoFarm = lib.require("AutoFarm")
  local GhostFX = lib.require("GhostFX")
  local TowerKit = lib.require("TowerKit")
  local ChunkMesher = lib.require("ChunkMesher")
  -- the row this probe is about, pinned to NEW whatever the player left
  TowerKit.setting:sync("new")
  local Pipelines = require("src.render.Pipelines")
  Pipelines.setLevel("terrarium_voxel", 4)
  Pipelines.setLevel("terrarium_tiltshift", 0)

  -- Pin everything that would make two runs disagree.
  Weather.setting:sync("off")
  DayNight.darkSetting:sync("deep")
  StreetLamps.setting:sync(true)
  MiniMap.setting:setIndex(3, game)
  AutoFarm.setting:setIndex(1, game)
  local ww, wh = love.graphics.getDimensions()
  log(("window: %dx%d"):format(ww, wh))

  local fails = {}
  local function check(ok, msg)
    if not ok then fails[#fails + 1] = msg end
    log((ok and "  ok   " or "  FAIL ") .. msg)
  end

  -- a screenshot waits on its own callback (memory: the yield-count race)
  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name .. ".png", "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      done = true
    end)
    local guard = 0
    while not done and guard < 600 do coroutine.yield() guard = guard + 1 end
    return done
  end

  local function voxelUp(guard)
    for _ = 1, guard or 900 do
      if Voxel3D.lampLights ~= nil then return true end
      coroutine.yield()
    end
    return false
  end

  local function lockCell(guard)
    local last, stable = nil, 0
    for _ = 1, guard or 1200 do
      local p = game.overworld.player
      local cur = p and (tostring(p.cellX) .. "," .. tostring(p.cellY)) or "?"
      if cur == last then stable = stable + 1 else stable, last = 0, cur end
      if stable >= 45 then return true, cur end
      coroutine.yield()
    end
    return false, last
  end

  local function releaseDirs()
    local st = game.input.state
    for _, d in ipairs({ "up", "down", "left", "right" }) do
      st[d] = false
      if game.input.sources then game.input.sources[d] = nil end
    end
    game.input.pressQueue = {}
  end

  -- arrive somewhere in a pinned hour, settled
  local function arrive(mapId, cx, cy, hour)
    DayNight.setting:sync(hour or "day")
    game.overworld:setMap(mapId, cx, cy, "down")
    wait(60)
    releaseDirs()
    voxelUp()
    local locked, cell = lockCell()
    releaseDirs()
    wait(200)
    return locked, cell
  end

  -- the player walks on his own long after setMap (memory: the drift), so
  -- the pin re-releases the directions: a shot taken from a box the player
  -- has drifted out of is a shot of the wrong camera
  local function hour(mode, settle)
    DayNight.setting:sync(mode)
    releaseDirs()
    wait(settle or 220)
    releaseDirs()
  end

  local function towerStats()
    local ok, st = pcall(Buildings.stats)
    return ok and st and st["OVERWORLD:1"] or nil
  end

  -- ------- 1. BUILD
  log("")
  log("[BUILD]")
  MarioCam.setting:setIndex(1, game)         -- the orbit camera, F0's frame
  local locked, cell = arrive("LAVENDER_TOWN", 10, 10, "day")
  log(("  player cell locked: %s at (%s)"):format(locked and "PASS" or "FAIL",
                                                tostring(cell)))
  -- the tower is the first template of the OVERWORLD list, key "OVERWORLD:1"
  local st = nil
  for _ = 1, 1500 do
    st = towerStats()
    if st and st.quads and st.quads > 0 then break end
    coroutine.yield()
  end
  check(st ~= nil and (st.quads or 0) > 0, "the tower model built")
  if st then
    log(("  tower model: voxels=%d shell=%d quads=%d")
        :format(st.voxels or -1, st.shell or -1, st.quads or -1))
  end
  log("  Buildings.lastError:", tostring(Buildings.lastError))
  check(Buildings.lastError == nil, "TowerKit built without falling back")
  local map = game.overworld.map
  local S = Structures.peek(map)
  local haunts = S and S.haunts
  check(haunts ~= nil and #haunts >= 1, "the stamp recorded the haunt")
  if haunts and haunts[1] then
    local h = haunts[1]
    log(("  haunt box x %d..%d z %d..%d top %d, %d wisp sources")
        :format(h.x0, h.z0 and h.x1 or -1, h.z0, h.z1, h.top or -1,
                #(h.wisps or {})))
    log(("  haunt box: x0=%s z0=%s x1=%s z1=%s"):format(
        tostring(h.x0), tostring(h.z0), tostring(h.x1), tostring(h.z1)))
    check(h.x0 == 190 and h.z0 == -2 and h.x1 == 290 and h.z1 == 66,
          "the haunt box is the tower's footprint plus its eaves (190..290 x -2..66)")
  end
  local tall = Buildings.tallAt(map, 14, 1)
  log("  Buildings.tallAt(14,1) =", tall)
  check(tall >= 200, "the camera's occluder height over the tower is the model's top")
  log("  shader:", Voxel3D.shader() and "built" or "NIL (2D fallback!)",
      "error:", tostring(Voxel3D.shaderError))
  check(Voxel3D.shader() ~= nil and Voxel3D.shaderError == nil,
        "the scene shader compiles with the haunted glass block")
  local own = 0
  for _, q in ipairs(S.objectQuads) do if q.own then own = own + 1 end end
  log(("  objectQuads=%d (building own=%d)"):format(#S.objectQuads, own))
  -- the terrace wall (TowerKit.precinct) standing on the ledge tiles: the
  -- model's real top over each kind of cell, through the same tallAt
  local function tallAt(cx, cy) return Buildings.tallAt(map, cx, cy) end
  log(("  terrace tallAt: ew(12,5)=%d gate(14,5)=%d ns(10,3)=%d ne(18,5)=%d "
       .. "nw(10,5)=%d west(2,1)=%d westEnd(5,1)=%d endS(18,15)=%d exit(10,17)=%d")
      :format(tallAt(12, 5), tallAt(14, 5), tallAt(10, 3), tallAt(18, 5),
              tallAt(10, 5), tallAt(2, 1), tallAt(5, 1), tallAt(18, 15),
              tallAt(10, 17)))
  check(tallAt(12, 5) >= 10 and tallAt(12, 5) <= 12,
        "terrace: the east-west wall stands, coping at 10")
  check(tallAt(14, 5) >= 16, "terrace: the gate piers stand")
  check(tallAt(10, 3) >= 10, "terrace: the north-south wall stands")
  check(tallAt(18, 5) >= 16 and tallAt(10, 5) >= 16,
        "terrace: both corners carry a pier")
  check(tallAt(2, 1) == 0 and tallAt(5, 1) == 0,
        "terrace: the west ledge line stays the profile's ledge (Route 8's carries on)")
  check(tallAt(18, 15) >= 16, "terrace: the east run's south end has its pier")
  check(tallAt(10, 17) == 0, "terrace: the south exit's ledge is left to the profile (where)")
  log(("  paving tallAt: yard(12,4)=%d west(11,2)=%d east(19,10)=%d plaza(12,7)=%d farWest(2,0)=%d")
      :format(tallAt(12, 4), tallAt(11, 2), tallAt(19, 10), tallAt(12, 7), tallAt(2, 0)))
  check(tallAt(12, 4) == 1 and tallAt(11, 2) == 1 and tallAt(19, 10) == 1,
        "paving: the yard and the east strip are flagged one voxel high")
  check(tallAt(12, 7) == 0 and tallAt(2, 0) == 0,
        "paving: the plaza and the north-west edge keep their own ground")

  -- ------- 2. LOOK: the F0 frame, day and night
  log("")
  log("[LOOK]")
  shot("orbit_day")
  hour("night")
  check(Voxel3D.haunt ~= nil, "the scene carries the haunt box at night")
  if Voxel3D.haunt then
    log(("  Voxel3D.haunt x %s..%s z %s..%s"):format(
        tostring(Voxel3D.haunt.x0), tostring(Voxel3D.haunt.x1),
        tostring(Voxel3D.haunt.z0), tostring(Voxel3D.haunt.z1)))
  end
  log("  glassNight:", Voxel3D.glassNight, "lampFlicker:", Voxel3D.lampFlicker)
  check((Voxel3D.glassNight or 0) > 0.9, "the windows are lit at night")
  check((Voxel3D.lampFlicker or 0) ~= 0, "the breathing clock runs")
  shot("orbit_night")
  -- the terrace from the plaza, orbit camera, the gate ahead
  arrive("LAVENDER_TOWN", 14, 7, "day")
  shot("terrace_day")
  hour("night")
  shot("terrace_night")

  -- ------- the HERO frame: a fixed camera low in the plaza's south-west,
  -- injected into the authored shots for this run only (never shipped)
  MarioCam.setting:setIndex(2, game)
  MarioCam.reloadShots()
  local shots = lib.data("camera_shots")
  local HERO = { x = 200, z = 120, bx = 14, bz = 14, mode = "fixed",
                 camX = 168, camY = 40, camZ = 250, focY = 70,
                 fov = 64, frames = 8, flat = true }
  shots.LAVENDER_TOWN = shots.LAVENDER_TOWN or {}
  table.insert(shots.LAVENDER_TOWN, 1, HERO)

  for _, h in ipairs({ "dawn", "day", "night" }) do
    arrive("LAVENDER_TOWN", 12, 7, h)
    local acquired = MarioCam.cam.shot == HERO
    check(acquired, "hero: the injected box acquires the shot (" .. h .. ")")
    local e = MarioCam.lakitu.curPos
    log(("  hero %s: eye (%.0f, %.0f, %.0f) fov %.1f mode %s"):format(
        h, e[1], e[2], e[3], MarioCam.lakitu.fov, tostring(MarioCam.cam.mode)))
    shot("hero_" .. h)
    if h == "night" then
      -- ------- 3. HAUNT: the wisps, after the tower has had time to breathe
      log("")
      log("[HAUNT]")
      wait(420)
      log("  GhostFX gate:", GhostFX.lastGate, "haunts:", GhostFX.lastHaunts,
          "night:", GhostFX.lastNight, "emitted:", GhostFX.emitted,
          "live:", GhostFX.count(), "batches:", GhostFX.lastBatches)
      log("  GhostFX errors:", GhostFX.errorCount, tostring(GhostFX.lastError),
          GhostFX.drawErrors, tostring(GhostFX.drawError))
      check(GhostFX.lastGate == "live", "GhostFX runs live in Lavender at night")
      check(GhostFX.emitted > 0, "the tower breathed at least one wisp")
      check(GhostFX.count() > 0, "wisps are in the air")
      check(GhostFX.errorCount == 0 and GhostFX.drawErrors == 0,
            "GhostFX threw nothing")
      shot("hero_night_wisps")
      local c = GhostFX.card()
      check(c ~= nil, "the wisp card exists")
    end
  end

  -- ------- 3b. TOGGLE: the TOWER row on CLASSIC brings the plain fold
  -- back -- and its own occluder height, no haunt, no wisps -- and NEW
  -- brings the kit back. The row's own step is the remesh; here the value
  -- is moved without persisting the player's choice, then the same
  -- rebuild the step would do.
  log("")
  log("[TOGGLE]")
  MarioCam.setting:setIndex(1, game)
  TowerKit.setting:sync("classic")
  ChunkMesher.invalidate()
  arrive("LAVENDER_TOWN", 10, 10, "day")
  local stC = nil
  for _ = 1, 1500 do
    stC = towerStats()
    if stC and stC.quads and stC.quads > 0 then break end
    coroutine.yield()
  end
  wait(120)
  local mapC = game.overworld.map
  local SC = Structures.peek(mapC)
  log(("  classic model: voxels=%s shell=%s quads=%s")
      :format(tostring(stC and stC.voxels), tostring(stC and stC.shell),
              tostring(stC and stC.quads)))
  log("  classic tallAt(14,1) =", Buildings.tallAt(mapC, 14, 1),
      "haunts:", tostring(SC and SC.haunts and #SC.haunts or 0))
  check(stC ~= nil and (stC.quads or 0) > 0, "CLASSIC: the fold builds")
  check(stC ~= nil and (stC.voxels or 0) < 700000,
        "CLASSIC: it is the old fold (under 700k voxels), not the kit")
  check(Buildings.tallAt(mapC, 14, 1) < 150,
        "CLASSIC: the camera's occluder height is the fold's own top")
  check(not (SC and SC.haunts and #SC.haunts > 0), "CLASSIC: no haunt recorded")
  check(Buildings.tallAt(mapC, 12, 5) == 0 and Buildings.tallAt(mapC, 14, 5) == 0
        and Buildings.tallAt(mapC, 12, 4) == 0,
        "CLASSIC: the terrace is the profile's ledge and ground again (nothing stamped)")
  hour("night")
  check(Voxel3D.haunt == nil, "CLASSIC: the scene carries no haunt box")
  wait(200)
  check(GhostFX.lastHaunts == 0, "CLASSIC: GhostFX sees no haunt")
  shot("classic_orbit_night")
  hour("day")
  shot("classic_orbit_day")
  TowerKit.setting:sync("new")
  ChunkMesher.invalidate()
  arrive("LAVENDER_TOWN", 10, 10, "day")
  local stN = nil
  for _ = 1, 1500 do
    stN = towerStats()
    if stN and stN.voxels and stN.voxels > 700000 then break end
    coroutine.yield()
  end
  wait(120)
  local mapN = game.overworld.map
  log(("  back to NEW: voxels=%s quads=%s tallAt=%d")
      :format(tostring(stN and stN.voxels), tostring(stN and stN.quads),
              Buildings.tallAt(mapN, 14, 1)))
  check(stN ~= nil and (stN.voxels or 0) > 700000, "NEW again: the kit is back")
  check(Buildings.tallAt(mapN, 14, 1) >= 200, "NEW again: the kit's own height")
  local SN = Structures.peek(mapN)
  check(SN and SN.haunts and #SN.haunts >= 1, "NEW again: the haunt is back")

  -- ------- 4. the authored shots, looked at with the new tower
  arrive("LAVENDER_TOWN", 14, 6, "day")
  log("  door shot:", tostring(MarioCam.cam.shot ~= nil), MarioCam.cam.mode)
  shot("door_day")
  hour("night")
  shot("door_night")
  arrive("LAVENDER_TOWN", 1, 7, "day")
  shot("west_day")
  -- and the tower from the north-west corner of the plaza, orbit camera
  MarioCam.setting:setIndex(1, game)
  arrive("LAVENDER_TOWN", 11, 4, "day")
  shot("orbit_northwest_day")
  hour("night")
  shot("orbit_northwest_night")

  -- ------- 5. COST: frame time at the hero frame, vsync off
  log("")
  log("[COST]")
  MarioCam.setting:setIndex(2, game)
  love.window.setVSync(0)
  local clock = love.timer.getTime
  local function measure(frames)
    local dts, prev = {}, clock()
    for i = 1, frames do
      coroutine.yield()
      local now = clock()
      dts[i] = now - prev
      prev = now
    end
    table.sort(dts)
    local sum = 0
    for _, d in ipairs(dts) do sum = sum + d end
    local function pct(p)
      return dts[math.max(1, math.min(frames, math.ceil(frames * p)))]
    end
    return sum / frames, pct(0.5), pct(0.95)
  end
  arrive("LAVENDER_TOWN", 12, 7, "day")
  wait(60)
  local m, p50, p95 = measure(150)
  log(("  hero day:   mean=%.2fms p50=%.2fms p95=%.2fms")
      :format(m * 1000, p50 * 1000, p95 * 1000))
  hour("night", 260)
  m, p50, p95 = measure(150)
  log(("  hero night: mean=%.2fms p50=%.2fms p95=%.2fms (wisps live=%d)")
      :format(m * 1000, p50 * 1000, p95 * 1000, GhostFX.count()))
  love.window.setVSync(1)
  DayNight.setting:sync("day")

  log("")
  if #fails == 0 then log("ALL CHECKS PASSED")
  else
    log("FAILURES (" .. #fails .. "):")
    for _, f in ipairs(fails) do log("  - " .. f) end
  end
  logf:close()
  love.event.quit()
end
