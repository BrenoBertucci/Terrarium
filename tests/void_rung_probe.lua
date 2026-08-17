-- Measurement-only: how much of the ROUTE_1 void closes when the settings
-- the player already has (HORIZON / V-HAZE) are turned on, rung by rung.
-- Does not write options.lua -- only ModSetting:sync, never :setIndex.
--
--   POKEPORT_VERSION=yellow \
--   DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/void_rung_probe.lua gen1recomp
--
-- What it asks, with a number:
--
--   GAP     drawn-world top edge vs Voxel3D.horizonY, in px and % of frame
--   PLACED  how many WorldAtlas.beyond maps sit inside this rung's reach
--   CACHED  how many silhouette meshes Skyline actually built
--   D-TEST  bottom-left mean luma, shadows HIGH vs OFF (class D vs C)
--
-- Climate matches the player's stored row: rain, cycle clock pinned at
-- noon only so the four rungs are the same hour. Spot is the same
-- ROUTE_1 (8,12) facing up that aerial_probe and skyline_probe use.

return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  do
    local boot = io.open("void_rung_BOOT.txt", "w")
    if boot then boot:write("driver entered OUT=", tostring(OUT), "\n"); boot:close() end
  end
  local logf = io.open(OUT .. "/void_rung_probe.log", "w")
  if not logf then
    OUT = "."
    logf = assert(io.open(OUT .. "/void_rung_probe.log", "w"))
  end
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
    if n > 900 then log("FAIL: no overworld") logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end
  log("version:", exports.TERRARIUM.version)
  log("NOTE: this driver uses setting:sync only. It does not call")
  log("      setIndex / writeOptions. Player options.lua is not the save.")

  local Skyline = lib.require("Skyline")
  local Aerial = lib.require("Aerial")
  local Voxel3D = lib.require("Voxel3D")
  local WorldAtlas = lib.require("WorldAtlas")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local MiniMap = lib.require("MiniMap")
  local Quality = lib.require("Quality")
  local Grass3D = lib.require("Grass3D")
  local AutoFarm = lib.require("AutoFarm")
  local Pipelines = require("src.render.Pipelines")

  -- Remember what the live rows were so we can put them back in RAM.
  local saved = {
    skyline = Skyline.setting:get(),
    haze = Aerial.setting:get(),
    weather = Weather.setting:get(),
    daytime = DayNight.setting:get(),
    shadows = Quality.shadowSetting:get(),
    grass = Grass3D.setting:get(),
  }
  log(("stored: HORIZON=%s  V-HAZE=%s  weather=%s  daytime=%s  shadows=%s  grass3d=%s")
        :format(tostring(saved.skyline), tostring(saved.haze),
                tostring(saved.weather), tostring(saved.daytime),
                tostring(saved.shadows), tostring(saved.grass)))

  Pipelines.setLevel("terrarium_voxel", 5)     -- 75deg: horizon in frame
  Pipelines.setLevel("terrarium_tiltshift", 0)
  MiniMap.setting:sync("off")
  AutoFarm.setting:sync("off")
  Weather.setting:sync("rain")
  DayNight.setting:sync("cycle")

  local CLOCK = 300
  local function hold(frames)
    for _ = 1, frames do
      DayNight.clock = CLOCK
      coroutine.yield()
    end
    DayNight.clock = CLOCK
  end

  game.overworld:setMap("ROUTE_1", 8, 12, "up")
  hold(300)

  local vw, vh = game.renderer:worldViewSize()
  log(("view: %dx%d world px"):format(vw, vh))
  log(("REACHES: OFF=%d NEAR=%d FAR=%d ALL=%d  (view-heights)")
        :format(Skyline.REACHES[1], Skyline.REACHES[2],
                Skyline.REACHES[3], Skyline.REACHES[4]))

  local bake = Grass3D.meta()
  log(("grass bake on disk: mesh=%s png=%s  wantsMesh=%s available=%s  height=%s")
        :format(tostring(love.filesystem.getInfo("assets/ground/grass/grass.mesh.bin")
                         ~= nil or true),
                tostring(love.filesystem.getInfo("assets/ground/grass/grass.png")
                         ~= nil or true),
                tostring(Grass3D.wantsMesh()),
                tostring(Grass3D.available()),
                tostring(bake and bake.height)))

  local function skyish(r, g, b)
    return b > g + 0.02 and b > r + 0.02
  end

  local function findEdge(data, W, H)
    local x0, x1 = math.floor(W * 0.10), math.floor(W * 0.90)
    local sum, nE = 0, 0
    for x = x0, x1, 2 do
      for y = 2, H - 24 do
        local r, g, b, a = data:getPixel(x, y)
        if a > 0.01 and not skyish(r, g, b) then
          sum, nE = sum + y, nE + 1
          break
        end
      end
    end
    return nE > 0 and (sum / nE) or nil
  end

  local function lumaRect(data, W, H, x0, y0, x1, y1)
    local sum, nL = 0, 0
    for y = y0, y1 do
      for x = x0, x1 do
        local r, g, b, a = data:getPixel(x, y)
        if a > 0.01 then
          sum, nL = sum + (r * 0.30 + g * 0.59 + b * 0.11), nL + 1
        end
      end
    end
    return nL > 0 and (sum / nL) or 0, nL
  end

  local function shot(name)
    local pending, rec = true, nil
    love.graphics.captureScreenshot(function(data)
      local W, H = data:getDimensions()
      local hy = Voxel3D.horizonY(H)
      local edgeY = findEdge(data, W, H)
      local gap = (edgeY and hy) and (edgeY - hy) or nil
      rec = { W = W, H = H, hy = hy, edgeY = edgeY, gap = gap }
      rec.bl, rec.blN = lumaRect(data, W, H,
                                 0, math.floor(H * 0.70),
                                 math.floor(W * 0.28), H - 1)
      local f = io.open(OUT .. "/" .. name .. ".png", "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      pending = false
    end)
    local g = 0
    while pending and g < 240 do hold(1); g = g + 1 end
    return rec
  end

  local function mapsInReach(reachVH)
    local state = game.overworld
    WorldAtlas.invalidate()
    local beyond = WorldAtlas.beyond(state)
    local cam = state.camera
    local cx = (cam and cam.x or 0) + vw / 2
    local cy = (cam and cam.y or 0) + vh / 2
    local reach = (reachVH or 0) * vh
    local nIn, farthest, farId = 0, 0, nil
    for _, e in ipairs(beyond) do
      local w2 = e.def.width * 16
      local h2 = e.def.height * 16
      local dx = (e.ox + w2) - cx
      local dz = (e.oy + h2) - cy
      local d = math.sqrt(dx * dx + dz * dz)
      if d > farthest then farthest, farId = d, e.id end
      if d <= reach then nIn = nIn + 1 end
    end
    return #beyond, nIn, farthest / vh, farId
  end

  local function cached()
    local c = 0
    for _ in pairs(Skyline._meshes or {}) do c = c + 1 end
    return c
  end

  local LABELS = { [0] = "OFF", [1] = "NEAR", [2] = "FAR", [3] = "ALL" }

  -- ------- player's stored pair first: the BEFORE
  log("")
  log("=== BEFORE: player's stored rungs (HORIZON OFF, V-HAZE OFF, rain) ===")
  Skyline.setting:sync(0)
  Aerial.setting:sync(0)
  hold(90)
  local before = shot("void_before_player")
  local allBeyond, inR, farVH, farId = mapsInReach(0)
  log(("  shot %dx%d  horizonY=%.1f  worldEdgeY=%s  gap=%s px (%.1f%% of H)")
        :format(before.W, before.H, before.hy or -1,
                tostring(before.edgeY),
                tostring(before.gap),
                (before.gap and before.H) and (before.gap / before.H * 100) or -1))
  log(("  atlas beyond=%d  inside reach 0 vh=%d  farthest=%s at %.1f vh")
        :format(allBeyond, inR, tostring(farId), farVH or -1))
  log(("  impostors cached=%d  bl-luma=%.3f")
        :format(cached(), before.bl or -1))

  -- ------- HORIZON ladder, V-HAZE held at 2 (the coupled pair)
  log("")
  log("=== HORIZON ladder at V-HAZE=2, rain, clock=300 ===")
  Aerial.setting:sync(2)
  local rows = {}
  for level = 0, 3 do
    Skyline.setting:sync(level)
    -- one impostor per frame; give ALL time to fill
    hold(200)
    local rec = shot(("void_h%d_%s_haze2"):format(level, LABELS[level]))
    local reach = Skyline.REACHES[level + 1]
    local beyond, inside, far, fid = mapsInReach(reach)
    local nMesh = cached()
    log(("  HORIZON=%-4s reach=%2d vh  beyond=%2d  in-reach=%2d  cached=%2d  "
         .. "gap=%s px (%.1f%%)  farthest=%s @ %.1f vh")
          :format(LABELS[level], reach, beyond, inside, nMesh,
                  tostring(rec.gap),
                  (rec.gap and rec.H) and (rec.gap / rec.H * 100) or -1,
                  tostring(fid), far or -1))
    log(("           horizonY=%.1f  edgeY=%s  bl-luma=%.3f")
          :format(rec.hy or -1, tostring(rec.edgeY), rec.bl or -1))
    rows[#rows + 1] = {
      level = level, label = LABELS[level], reach = reach,
      beyond = beyond, inside = inside, cached = nMesh,
      gap = rec.gap, hy = rec.hy, edgeY = rec.edgeY, H = rec.H,
    }
  end

  -- ------- the cardboard case: HORIZON on, haze off
  log("")
  log("=== cardboard check: HORIZON=NEAR, V-HAZE=OFF ===")
  Skyline.setting:sync(1)
  Aerial.setting:sync(0)
  hold(120)
  local card = shot("void_near_hazeOFF")
  log(("  gap=%s px  bl-luma=%.3f  (silhouettes at full ink, no crush)")
        :format(tostring(card.gap), card.bl or -1))

  -- ------- recommended pair from the brief
  log("")
  log("=== recommended start: HORIZON=NEAR, V-HAZE=2 ===")
  Skyline.setting:sync(1)
  Aerial.setting:sync(2)
  hold(90)
  local rec = shot("void_near_haze2")
  log(("  gap=%s px (%.1f%%)  cached=%d")
        :format(tostring(rec.gap),
                (rec.gap and rec.H) and (rec.gap / rec.H * 100) or -1,
                cached()))

  -- ------- class D: shadows HIGH vs OFF, same pose
  log("")
  log("=== class D: bottom-left luma, shadows HIGH vs OFF ===")
  Skyline.setting:sync(0)
  Aerial.setting:sync(0)
  Quality.shadowSetting:sync("high")
  hold(90)
  local shOn = shot("void_shadows_high")
  Quality.shadowSetting:sync("off")
  hold(90)
  local shOff = shot("void_shadows_off")
  local dL = (shOff.bl or 0) - (shOn.bl or 0)
  log(("  HIGH bl-luma=%.4f  OFF bl-luma=%.4f  delta=%+.4f")
        :format(shOn.bl or -1, shOff.bl or -1, dL))
  if math.abs(dL) > 0.03 then
    log("  READ: the dark corner MOVES when shadows drop -- class D, not a mesh hole")
  else
    log("  READ: the dark corner does not move with shadows -- not (only) class D")
  end

  -- put RAM rows back where we found them
  Skyline.setting:sync(saved.skyline)
  Aerial.setting:sync(saved.haze)
  Weather.setting:sync(saved.weather)
  DayNight.setting:sync(saved.daytime)
  Quality.shadowSetting:sync(saved.shadows)
  Grass3D.setting:sync(saved.grass)

  log("")
  log("=== summary ===")
  if before.gap then
    log(("  BEFORE gap (player rungs): %.0f px"):format(before.gap))
  end
  for _, r in ipairs(rows) do
    log(("  HORIZON=%-4s  in-reach=%d/%d  gap=%s")
          :format(r.label, r.inside, r.beyond, tostring(r.gap)))
  end
  log("done -- " .. OUT)
  logf:close()
  love.event.quit()
end
