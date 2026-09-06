-- Probe: the inside of the Pokemon Tower stands as a crypt (lib/CryptKit.lua
-- under the CRYPT row, lit and filled by lib/Crypt.lua).
--
--   BUILD   on every floor the kit builds (models keyed "CEMETERY:<i>@<sig>"
--           in Buildings.stats, no fallback recorded in Buildings.lastError),
--           the scene carries the lanterns' point lights, the crypt floor
--           art is on, the haunted floors carry their authored air and
--           breathe wisps out of the graves, the flames are drawn.
--   LAW     the fixed camera still sees the player over the cut walls
--           (MarioCam.rayBlocked through Buildings.tallAt), on every floor.
--   LOOK    a screenshot per floor from the authored shot, plus 4F with the
--           tilt-shift on and 1F under CLASSIC for the A/B.
--   COST    frame time on a haunted floor, vsync off.
--
-- Traps respected (memory: terrarium-probe-screenshot-race,
-- terrarium-ambientlife-probe): a screenshot waits on its own callback; the
-- 3D pass is polled up through Voxel3D.lampLights (the crypt sets them
-- indoors, so the poll is honest here); the player drifts after setMap, so
-- the directions are released before and after every settle.
--
-- POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
-- POKEPORT_DRIVER=mods/TERRARIUM/tests/tower_interior_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/tower_interior_probe.log", "w"))
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
  local MarioCam = lib.require("MarioCam")
  local MiniMap = lib.require("MiniMap")
  local AutoFarm = lib.require("AutoFarm")
  local GhostFX = lib.require("GhostFX")
  local CryptKit = lib.require("CryptKit")
  local Crypt = lib.require("Crypt")
  local ChunkMesher = lib.require("ChunkMesher")
  local FloorArt = lib.require("FloorArt")
  local Bloom = lib.require("Bloom")
  local Pipelines = require("src.render.Pipelines")
  Pipelines.setLevel("terrarium_voxel", 4)
  Pipelines.setLevel("terrarium_tiltshift", 0)

  -- Pin everything that would make two runs disagree.
  CryptKit.setting:sync("new")
  Crypt.fxSetting:sync("on")
  GhostFX.setting:sync("on")
  Weather.setting:sync("off")
  DayNight.setting:sync("day")
  MiniMap.setting:setIndex(3, game)
  AutoFarm.setting:setIndex(1, game)
  MarioCam.setting:setIndex(2, game)
  local ww, wh = love.graphics.getDimensions()
  log(("window: %dx%d"):format(ww, wh))

  local fails = {}
  local function check(ok, msg)
    if not ok then fails[#fails + 1] = msg end
    log((ok and "  ok   " or "  FAIL ") .. msg)
  end

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

  local function arrive(mapId, cx, cy)
    game.overworld:setMap(mapId, cx, cy, "down")
    wait(60)
    releaseDirs()
    local up = voxelUp()
    local locked, cell = lockCell()
    releaseDirs()
    wait(200)
    releaseDirs()
    return up, locked, cell
  end

  -- the kit's models, keyed "CEMETERY:<index>@<signature>"
  local function cryptStats()
    local ok, st = pcall(Buildings.stats)
    if not (ok and st) then return 0, 0, 0 end
    local walls, graves, quads = 0, 0, 0
    for key, v in pairs(st) do
      if key:find("^CEMETERY:%d+@") then
        quads = quads + (v.quads or 0)
        if key:find("@w") then walls = walls + 1 end
        if key:find("@g") then graves = graves + 1 end
      end
    end
    return walls, graves, quads
  end

  local function sightClear()
    local e = MarioCam.lakitu.curPos
    local f = MarioCam.lakitu.curFocus
    local map = game.overworld.map
    return not MarioCam.rayBlocked(map, e[1], e[2], e[3],
                                   f[1], f[2] + 8, f[3])
  end

  local function playerOnScreen()
    local p = game.overworld.player
    local px, py = Voxel3D.project((p.px or 0) + 8, 8, (p.py or 0) + 8)
    if not px then return false end
    local w, h = love.graphics.getDimensions()
    return px >= 0 and px <= w and py >= 0 and py <= h
  end

  local FLOORS = {
    { "t1f", "POKEMON_TOWER_1F", 10, 8 },
    { "t2f", "POKEMON_TOWER_2F", 5, 7 },
    { "t3f", "POKEMON_TOWER_3F", 5, 6 },
    { "t4f", "POKEMON_TOWER_4F", 4, 8 },
    { "t5f", "POKEMON_TOWER_5F", 6, 6 },
    { "t6f", "POKEMON_TOWER_6F", 5, 7 },
    { "t7f", "POKEMON_TOWER_7F", 11, 8 },
  }

  for _, fl in ipairs(FLOORS) do
    local name, mapId, cx, cy = fl[1], fl[2], fl[3], fl[4]
    log("")
    log("[" .. mapId .. "]")
    local up, locked, cell = arrive(mapId, cx, cy)
    log(("  voxel up: %s  player cell locked: %s at (%s)"):format(
        tostring(up), locked and "PASS" or "FAIL", tostring(cell)))
    local map = game.overworld.map
    local S = Structures.peek(map)
    check(S ~= nil, name .. ": the structure cache is built")
    local walls, graves, quads = cryptStats()
    log(("  crypt models so far: walls=%d graves=%d quads=%d  objectQuads=%d")
        :format(walls, graves, quads, S and #S.objectQuads or -1))
    check(walls > 0, name .. ": crypt wall models built")
    log("  Buildings.lastError:", tostring(Buildings.lastError))
    check(not (Buildings.lastError and Buildings.lastError:find("crypt", 1, true)),
          name .. ": the kit built without falling back")
    local lamps = Voxel3D.lampLights
    log(("  lamps=%d lampHeight=%s lampColor=%s"):format(
        lamps and #lamps or -1, tostring(Voxel3D.lampHeight),
        lamps and lamps[1] and ("%.0f,%.0f r%.0f p%.2f"):format(
          lamps[1].x, lamps[1].z, lamps[1].radius, lamps[1].power) or "-"))
    check(lamps ~= nil and #lamps >= 4, name .. ": the lanterns light the scene")
    log(("  tint=%.2f,%.2f,%.2f"):format(Voxel3D.tint[1], Voxel3D.tint[2],
                                         Voxel3D.tint[3]))
    check(Voxel3D.tint[1] < 0.75, name .. ": the ambient is held down")
    local fog = Voxel3D.lastFog
    local col = Voxel3D.lastFogColor
    log(("  fog=%s color=%s"):format(
        fog and ("near %.0f inv %.4f amt %.2f"):format(fog[1], fog[2], fog[3]) or "nil",
        col and ("%.2f,%.2f,%.2f"):format(col[1], col[2], col[3]) or "nil"))
    check(fog ~= nil and fog[3] > 0.3, name .. ": the floor carries its authored air")
    if Crypt.haunted(map) then
      check(col ~= nil and col[3] > 0.4, name .. ": the haunted air is violet")
    end
    log(("  floor art: on=%d profile=%s mix=%.2f"):format(
        FloorArt.on(), tostring(FloorArt.profile() and FloorArt.profile().name),
        FloorArt.mix()))
    check(FloorArt.on() == 1 and FloorArt.profile()
          and FloorArt.profile().name == "crypt",
          name .. ": the crypt flagstones are laid")
    check(MarioCam.cam.shot ~= nil and MarioCam.cam.mode == "fixed",
          name .. ": the authored fixed shot is on")
    check(playerOnScreen(), name .. ": the player projects on screen")
    check(sightClear(), name .. ": nothing stands between the eye and the player")
    log(("  Crypt flames: batches=%d err=%s  GhostFX gate=%s live=%d haunts=%d")
        :format(Crypt.lastBatches, tostring(Crypt.drawError), GhostFX.lastGate,
                GhostFX.count(), GhostFX.lastHaunts))
    check(Crypt.lastBatches > 0 and Crypt.drawError == nil,
          name .. ": the flames are drawn")
    if Crypt.haunted(map) then
      wait(240)
      log(("  after 240 frames: wisps live=%d emitted=%d gate=%s err=%s")
          :format(GhostFX.count(), GhostFX.emitted, GhostFX.lastGate,
                  tostring(GhostFX.lastError)))
      check(GhostFX.lastGate == "live" and GhostFX.count() > 0,
            name .. ": wisps breathe out of the graves")
    end
    log("  shader:", Voxel3D.shader() and "built" or "NIL (2D fallback!)",
        "error:", tostring(Voxel3D.shaderError))
    check(Voxel3D.shader() ~= nil and Voxel3D.shaderError == nil,
          name .. ": the scene shader is live")
    -- the CRYPT-FX row: the uniforms are set, the build carries the
    -- normals, the bloom ran over the frame
    log(("  fx: normalsOK=%s lampNormals=%s lampSpec=%s mist=%s bloomPasses=%d err=%s")
        :format(tostring(Voxel3D.normalsOK), tostring(Voxel3D.lampNormals),
                tostring(Voxel3D.lampSpec),
                Voxel3D.mist and ("%.2f/%d/%.3f"):format(Voxel3D.mist[1],
                  Voxel3D.mist[2], Voxel3D.mist[3]) or "nil",
                Bloom.lastPasses, tostring(Bloom.lastError)))
    check(Voxel3D.normalsOK == true, name .. ": the shader carries the face normals")
    check(Voxel3D.lampNormals == 1 and (Voxel3D.lampSpec or 0) > 0,
          name .. ": the lanterns light by face and lay a sheen")
    check(Voxel3D.mist ~= nil and Voxel3D.mist[1] > 0, name .. ": the mist is on")
    check(Bloom.lastPasses > 0 and Bloom.lastError == nil,
          name .. ": the bloom ran over the frame")
    log(("  stone: %s"):format(Voxel3D.stone and ("scale %d mix %.2f bump %.1f")
        :format(Voxel3D.stone.scale, Voxel3D.stone.mix, Voxel3D.stone.bump) or "nil"))
    check(Voxel3D.stone ~= nil and Voxel3D.stone.art ~= nil,
          name .. ": the stone materials are bound")
    check(Voxel3D.stone ~= nil and Voxel3D.stone.norm ~= nil
          and Voxel3D.stone.graniteNorm ~= nil and FloorArt.normal() ~= nil,
          name .. ": the relief maps are bound (wall, granite, floor)")
    local RayFX = lib.require("RayFX")
    log(("  rayfx: level=%s floor=%s aoPower=%s rays=%d bloomErr=%s"):format(
        RayFX.level(), tostring(RayFX.floor), tostring(Voxel3D.aoPower),
        Bloom.lastRays, tostring(Bloom.lastError)))
    check(RayFX.level() ~= "off" and (Voxel3D.aoPower or 0) > RayFX.AO_POWER,
          name .. ": the occlusion runs, harder than the streets'")
    check(Bloom.lastRays > 0, name .. ": the rays march from the lanterns")
    releaseDirs()
    check(shot(name), name .. ": screenshot")
  end

  -- ------- HERO frames: close, low cameras injected for this run only
  -- (never shipped), to look at the materials at the size they are
  -- played at
  log("")
  log("[HERO]")
  MarioCam.reloadShots()
  local shots = lib.data("camera_shots")
  local function hero(mapId, cx, cy, cam, name)
    local list = shots[mapId]
    if not list then return end
    table.insert(list, 1, cam)
    arrive(mapId, cx, cy)
    local e = MarioCam.lakitu.curPos
    log(("  %s: eye (%.0f, %.0f, %.0f) fov %.1f acquired=%s"):format(
        name, e[1], e[2], e[3], MarioCam.lakitu.fov,
        tostring(MarioCam.cam.shot == cam)))
    shot(name)
    table.remove(list, 1)
  end
  hero("POKEMON_TOWER_1F", 4, 8,
       { x = 160, z = 144, bx = 160, bz = 144, mode = "fixed",
         camX = 138, camY = 40, camZ = 214, focY = 14,
         fov = 50, frames = 8, flat = true }, "t1f_hero")
  hero("POKEMON_TOWER_4F", 9, 10,
       { x = 160, z = 144, bx = 160, bz = 144, mode = "fixed",
         camX = 214, camY = 34, camZ = 246, focY = 10,
         fov = 50, frames = 8, flat = true }, "t4f_hero")
  MarioCam.reloadShots()

  -- ------- the A/B: CRYPT-FX off, the crypt lit as the streets are
  log("")
  log("[NOFX]")
  Crypt.fxSetting:sync("off")
  arrive("POKEMON_TOWER_1F", 10, 8)
  check(Voxel3D.lampNormals == 0 and Voxel3D.mist == nil,
        "CRYPT-FX off clears the uniforms")
  shot("t1f_nofx")
  arrive("POKEMON_TOWER_4F", 4, 8)
  shot("t4f_nofx")
  Crypt.fxSetting:sync("on")

  -- ------- the tilt-shift on, the way the player sees it
  log("")
  log("[TILT]")
  Pipelines.setLevel("terrarium_tiltshift", 2)
  arrive("POKEMON_TOWER_4F", 4, 8)
  shot("t4f_tilt")
  arrive("POKEMON_TOWER_1F", 10, 8)
  shot("t1f_tilt")
  Pipelines.setLevel("terrarium_tiltshift", 0)

  -- ------- the A/B: CLASSIC stands the profile's pins as before
  log("")
  log("[CLASSIC]")
  CryptKit.setting:sync("classic")
  ChunkMesher.invalidate()
  arrive("POKEMON_TOWER_1F", 10, 8)
  local walls = cryptStats()
  log(("  crypt wall models under CLASSIC: %d"):format(walls))
  check(walls == 0, "CLASSIC builds no crypt models")
  shot("t1f_classic")
  CryptKit.setting:sync("new")
  ChunkMesher.invalidate()

  -- ------- COST: a haunted floor, vsync off
  log("")
  log("[COST]")
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
  arrive("POKEMON_TOWER_4F", 4, 8)
  wait(60)
  local m, p50, p95 = measure(150)
  log(("  4F: mean=%.2fms p50=%.2fms p95=%.2fms (wisps live=%d, objectQuads=%d)")
      :format(m * 1000, p50 * 1000, p95 * 1000, GhostFX.count(),
              #Structures.peek(game.overworld.map).objectQuads))
  love.window.setVSync(1)

  log("")
  if #fails == 0 then log("ALL CHECKS PASSED")
  else
    log("FAILURES (" .. #fails .. "):")
    for _, f in ipairs(fails) do log("  - " .. f) end
  end
  logf:close()
  love.event.quit()
end
