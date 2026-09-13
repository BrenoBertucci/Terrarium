-- Probe: Porygonal drives Terrarium, and Terrarium loses nothing doing it.
--
-- Porygonal ("Porygonal - Overworld Characters") swaps character cards for
-- 3D models through the active renderer's OWN draw calls, so every claim
-- here is measured at the seam it wraps rather than read off a log line.
-- The adapter's wrapper is the outer function; Terrarium's real one is the
-- upvalue it captured.  Instrumenting BOTH ends of that pair in one run is
-- what makes this an A/B rather than a vibe:
--
--   SENT     what Terrarium passes into Voxel3D.draw / SpriteBillboards.*
--   ARRIVED  what actually reaches the original after the adapter forwards
--
-- Any argument the adapter truncates shows up as SENT > ARRIVED.  The two
-- that matter:
--
--   sway  Voxel3D.draw's 6th.  Voxel3D sends the shader uniform on EVERY
--         draw, from `sway or 0`, so that a swaying pass cannot leak into
--         the terrain drawn after it.  A 5-parameter wrapper therefore does
--         not merely miss the grass pass: every draw in the frame reads nil
--         and the whole world stops moving, with nothing logged anywhere.
--   cut   SpriteBillboards.mesh/shadowQuad's 3rd.  How many pixels of the
--         feet are hidden: the waterline for a swimmer, the cut tall grass
--         and settled snow make for anybody standing in them.
--
-- And the point of the exercise: with the adapter bound, a solid character
-- draw should stop being a CARD (a mesh SpriteBillboards built) and become
-- a MODEL.  Run this probe twice -- once with the adapter installed and
-- once without (compat/porygonal/install.py --uninstall) -- and the drop in
-- "solid from a card" is the replacement, counted.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=<build>/tests/porygonal_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/porygonal_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  -- the screenshot is handed over on a LATER frame, so waiting a fixed
  -- number of yields photographs whatever the game moved on to.  Wait for
  -- the callback.
  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      done = true
    end)
    local guard = 0
    while not done and guard < 240 do coroutine.yield(); guard = guard + 1 end
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
  game.input:reset()

  -- ------- 1. who is loaded
  local loader = game.mods
  local exports = loader and loader.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end
  log("terrarium :", exports.TERRARIUM.version)

  local PORYG = "PORYGONAL_OVERWORLD_CHARACTERS"
  local pmod = loader.mods and loader.mods[PORYG]
  if not pmod then
    log("porygonal : NOT INSTALLED")
  else
    log(("porygonal : %s  enabled=%s failed=%s loaded=%s")
        :format(tostring(pmod.manifest and pmod.manifest.version),
                tostring(pmod.enabled), tostring(pmod.failed),
                tostring(exports[PORYG] ~= nil)))
  end

  local Voxel3D = lib.require("Voxel3D")
  local SpriteBillboards = lib.require("SpriteBillboards")
  local VoxelScene = lib.require("VoxelScene")
  local ShadowMap = lib.require("ShadowMap")
  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local Wind = lib.require("Wind")
  local MarioCam = lib.require("MarioCam")
  local Pipelines = require("src.render.Pipelines")

  -- ------- 2. is the adapter actually on the seams
  --
  -- Terrarium assigns shadowQuad = mesh, ONE function under two names.  An
  -- adapter wraps them separately, so two distinct values is the cheapest
  -- proof something took the seam -- and it needs no debug library.
  log("seam      : mesh~=shadowQuad =",
      SpriteBillboards.mesh ~= SpriteBillboards.shadowQuad,
      " (true once an adapter wraps them)")

  local function nparams(fn)
    if not (debug and debug.getinfo) then return "?" end
    local ok, info = pcall(debug.getinfo, fn, "u")
    if not ok or not info or info.nparams == nil then return "?" end
    return info.nparams
  end
  log(("arity     : Voxel3D.draw=%s (want 6)  mesh=%s shadowQuad=%s (want 3)"
       .. "  VoxelScene.render=%s (want 6 or 7)  ShadowMap.draw=%s (want 3)")
      :format(tostring(nparams(Voxel3D.draw)), tostring(nparams(SpriteBillboards.mesh)),
              tostring(nparams(SpriteBillboards.shadowQuad)),
              tostring(nparams(VoxelScene.render)), tostring(nparams(ShadowMap.draw))))

  local function findUp(fn, name)
    if not (debug and debug.getupvalue) then return nil end
    for i = 1, 250 do
      local key, value = debug.getupvalue(fn, i)
      if not key then return nil end
      if key == name then return i, value end
    end
    return nil
  end

  -- ------- 3. instrument both ends of each wrapped pair
  local sent, got
  local function zero()
    return { draws = 0, swayArg = 0, swayPos = 0, maxSway = 0,
             solidCards = 0, solidOther = 0,
             mesh = 0, meshCutArg = 0, meshCutPos = 0, maxMeshCut = 0,
             quad = 0, quadCutArg = 0, quadCutPos = 0, maxQuadCut = 0 }
  end
  sent, got = zero(), zero()

  -- every mesh SpriteBillboards handed back: a solid draw of one of these
  -- is a CARD.  Weak keys so a cache flush does not pin them.
  local cards = setmetatable({}, { __mode = "k" })

  local function countDraw(t, sunModel, sway, mesh)
    t.draws = t.draws + 1
    if sway ~= nil then t.swayArg = t.swayArg + 1 end
    local s = tonumber(sway) or 0
    if s > 0 then t.swayPos = t.swayPos + 1 end
    if s > t.maxSway then t.maxSway = s end
    if sunModel ~= nil then
      if cards[mesh] then t.solidCards = t.solidCards + 1
      else t.solidOther = t.solidOther + 1 end
    end
  end

  local bound = false
  local drawIndex, innerDraw = findUp(Voxel3D.draw, "originalVoxelDraw")
  if drawIndex and type(innerDraw) == "function" then
    bound = true
    debug.setupvalue(Voxel3D.draw, drawIndex,
      function(mesh, texture, model, pull, sunModel, sway, ...)
        countDraw(got, sunModel, sway, mesh)
        return innerDraw(mesh, texture, model, pull, sunModel, sway, ...)
      end)
  end

  local meshIndex, innerMesh = findUp(SpriteBillboards.mesh, "originalBillboardMesh")
  if meshIndex and type(innerMesh) == "function" then
    debug.setupvalue(SpriteBillboards.mesh, meshIndex,
      function(def, frame, cut, ...)
        got.mesh = got.mesh + 1
        if cut ~= nil then got.meshCutArg = got.meshCutArg + 1 end
        local c = tonumber(cut) or 0
        if c > 0 then got.meshCutPos = got.meshCutPos + 1 end
        if c > got.maxMeshCut then got.maxMeshCut = c end
        return innerMesh(def, frame, cut, ...)
      end)
  end

  local quadIndex, innerQuad = findUp(SpriteBillboards.shadowQuad, "originalShadowQuad")
  if quadIndex and type(innerQuad) == "function" then
    debug.setupvalue(SpriteBillboards.shadowQuad, quadIndex,
      function(def, frame, cut, ...)
        got.quad = got.quad + 1
        if cut ~= nil then got.quadCutArg = got.quadCutArg + 1 end
        local c = tonumber(cut) or 0
        if c > 0 then got.quadCutPos = got.quadCutPos + 1 end
        if c > got.maxQuadCut then got.maxQuadCut = c end
        return innerQuad(def, frame, cut, ...)
      end)
  end

  log("adapter   : bound =", bound,
      bound and "(Porygonal is driving Terrarium)"
            or "(nothing wrapped Voxel3D.draw -- BASELINE run)")

  -- The OUTER wrappers see what Terrarium sends.  Installed after the inner
  -- ones so a bound run measures the pair end to end; on a baseline run they
  -- are the only instrument and `got` honestly stays at zero.
  local outerDraw = Voxel3D.draw
  Voxel3D.draw = function(mesh, texture, model, pull, sunModel, sway, ...)
    countDraw(sent, sunModel, sway, mesh)
    return outerDraw(mesh, texture, model, pull, sunModel, sway, ...)
  end

  local outerMesh = SpriteBillboards.mesh
  SpriteBillboards.mesh = function(def, frame, cut, ...)
    sent.mesh = sent.mesh + 1
    if cut ~= nil then sent.meshCutArg = sent.meshCutArg + 1 end
    local c = tonumber(cut) or 0
    if c > 0 then sent.meshCutPos = sent.meshCutPos + 1 end
    if c > sent.maxMeshCut then sent.maxMeshCut = c end
    local mesh = outerMesh(def, frame, cut, ...)
    if mesh then cards[mesh] = true end
    return mesh
  end

  local outerQuad = SpriteBillboards.shadowQuad
  SpriteBillboards.shadowQuad = function(def, frame, cut, ...)
    sent.quad = sent.quad + 1
    if cut ~= nil then sent.quadCutArg = sent.quadCutArg + 1 end
    local c = tonumber(cut) or 0
    if c > 0 then sent.quadCutPos = sent.quadCutPos + 1 end
    if c > sent.maxQuadCut then sent.maxQuadCut = c end
    local mesh = outerQuad(def, frame, cut, ...)
    if mesh then cards[mesh] = true end
    return mesh
  end

  -- ------- 4. a frame worth measuring
  --
  -- SM64CAM off: the diorama's own camera is the same shot in both runs,
  -- which is what makes the two screenshots comparable.
  DayNight.setting:sync("day")
  Weather.setting:sync("none")
  Wind.setting:sync(4)                 -- GALE: the strongest sway on offer
  pcall(MarioCam.setting.sync, MarioCam.setting, "off")

  -- The voxel pass has to be ON and BUILT before anything is counted: the
  -- pipeline falls back to the flat 2D blit while the terrain mesh is still
  -- being meshed, and a frame of that is a frame with no draws in it at all.
  local function voxelUp(label, limit)
    Pipelines.setLevel("terrarium_voxel", 4)
    local before = sent.draws
    for f = 1, (limit or 600) do
      coroutine.yield()
      if f % 60 == 0 then Pipelines.setLevel("terrarium_voxel", 4) end
      if sent.draws > before + 200 then
        log(("%s: voxel pass up after %d frames (level %s)")
            :format(label, f, tostring(Pipelines.level("terrarium_voxel"))))
        return true
      end
    end
    log(("%s: FAIL voxel pass never drew (level %s)")
        :format(label, tostring(Pipelines.level("terrarium_voxel"))))
    return false
  end

  local function report(tag)
    log(tag)
    log(("  SENT     draws %d  sway: arg %d, >0 %d, max %.2f   solid: card %d other %d")
        :format(sent.draws, sent.swayArg, sent.swayPos, sent.maxSway,
                sent.solidCards, sent.solidOther))
    log(("           mesh %d (cut arg %d, >0 %d, max %d)   shadowQuad %d (cut arg %d, >0 %d, max %d)")
        :format(sent.mesh, sent.meshCutArg, sent.meshCutPos, sent.maxMeshCut,
                sent.quad, sent.quadCutArg, sent.quadCutPos, sent.maxQuadCut))
    if bound then
      log(("  ARRIVED  draws %d  sway: arg %d, >0 %d, max %.2f   solid: card %d other %d")
          :format(got.draws, got.swayArg, got.swayPos, got.maxSway,
                  got.solidCards, got.solidOther))
      log(("           mesh %d (cut arg %d, >0 %d, max %d)   shadowQuad %d (cut arg %d, >0 %d, max %d)")
          :format(got.mesh, got.meshCutArg, got.meshCutPos, got.maxMeshCut,
                  got.quad, got.quadCutArg, got.quadCutPos, got.maxQuadCut))
    end
  end

  -- Viridian City: civilians standing and walking in the open, seen from
  -- the front, and a Pokemon Center door for the authored seated figure.
  game.overworld:setMap("VIRIDIAN_CITY", 17, 20, "down")
  wait(120)
  game.input:reset()
  sent, got = zero(), zero()
  voxelUp("viridian")
  sent, got = zero(), zero()
  wait(180)
  shot("poryg_1_town.png")
  report("viridian city (people in the open)")
  local town = { sentCards = sent.solidCards, gotCards = got.solidCards }

  -- Route 1: tall grass, so somebody is standing IN something and the card
  -- is cut at the boots -- the argument a 2-parameter wrapper drops -- and
  -- a meadow full of tufts for the wind to move.
  game.overworld:setMap("ROUTE_1", 8, 20, "down")
  wait(120)
  sent, got = zero(), zero()
  voxelUp("route 1")
  sent, got = zero(), zero()
  for _ = 1, 3 do
    for _ = 1, 30 do game.input.state.down = true; coroutine.yield() end
    game.input.state.down = false
    for _ = 1, 30 do game.input.state.up = true; coroutine.yield() end
    game.input.state.up = false
  end
  game.input:reset()
  wait(30)
  shot("poryg_2_grass.png")
  report("route 1 (walked through tall grass, WIND=GALE)")

  -- ------- 5. the verdict
  log("")
  if not bound then
    log(("BASELINE: nothing wrapped the seams. Terrarium alone drew %d solid"
         .. " cards on route 1 and %d in town.")
        :format(sent.solidCards, town.sentCards))
    log("Run again with the adapter installed: those card counts should collapse.")
  else
    local function verdict(ok, good, bad)
      log((ok and "PASS: " or "FAIL: ") .. (ok and good or bad))
    end

    if sent.maxSway <= 0 then
      log("INCONCLUSIVE: nothing swayed this run (WIND off, or no grass in frame?)")
    else
      verdict(math.abs(got.maxSway - sent.maxSway) <= 0.001
                and got.swayPos == sent.swayPos,
              ("sway survives the adapter (max %.3f both ends, %d swaying draws)")
                :format(sent.maxSway, sent.swayPos),
              ("sway is TRUNCATED -- sent max %.3f on %d draws, arrived max %.3f"
               .. " on %d. Grass and trees stand still.")
                :format(sent.maxSway, sent.swayPos, got.maxSway, got.swayPos))
    end

    local sentCut = math.max(sent.maxMeshCut, sent.maxQuadCut)
    local gotCut = math.max(got.maxMeshCut, got.maxQuadCut)
    if sentCut <= 0 then
      log("INCONCLUSIVE: nothing was cut this run")
    else
      verdict(gotCut == sentCut,
              ("cut survives the adapter (max %d both ends)"):format(sentCut),
              ("cut is TRUNCATED -- sent max %d, arrived max %d. Swimmers stand"
               .. " on the water and anybody in tall grass is full height.")
                :format(sentCut, gotCut))
    end

    log(("REPLACEMENT: solid card draws -- town %d, route 1 %d."
         .. " Compare with a baseline run: a bound adapter drives these toward"
         .. " zero for every character it has a model for.")
        :format(town.gotCards, got.solidCards))
  end

  log("done")
  logf:close()
  love.event.quit()
end
