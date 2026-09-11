-- Probe: the snow, rebuilt -- cover, trail, sink, coat, melt.
--
-- The old snow_shot pinned the cover and took three pictures of the
-- decals. There are no decals now: the snow is the scene shader's, fed by
-- the deformation field (lib/SnowField.lua), so what this has to catch is
--
--   RUNGS     the new shader code compiles on all four compatibility rungs
--             -- a GLSL error inside a fallback #ifdef ships undetected on
--             every desktop in the room (see tests/gpu_compat_probe.lua)
--   FIELD     a walk in deep snow writes the field: stamps, trodden texels,
--             and a pressed value under the path; and the image reaches
--             the shader (SnowField.state() is not nil)
--   SINK      the walkers' cards are cut by the depth (SnowField.sink)
--   COAT      the figures took the coat while it was coming down
--   FILL      a trail fills back in under fresh snow
--   MELT      the thaw clears the field and the tint
--   OFF       the GROUND row switches every bit of it off
--
-- and the pictures: deep cover standing still, the same spot after a walk
-- (the trail beside the player), and the thaw.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/snow_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/snow_probe.log", "w"))
  local fails = 0
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    if line:find("FAIL") then fails = fails + 1 end
    logf:write(line, "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  -- The shot waits for its own callback, never a frame count (see
  -- tests/ambient_occlusion_probe.lua for why).
  local function shot(name)
    local done, data = false, nil
    love.graphics.captureScreenshot(function(d)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(d:encode("png"):getString()) f:close() end
      data = d
      done = true
    end)
    local spun = 0
    while not done and spun < 400 do wait(1); spun = spun + 1 end
    if not done then log("  FAIL: screenshot " .. name .. " never arrived") end
    return data
  end
  -- Hold a direction for `frames` UPDATES, reasserted every tick (the
  -- engine rebuilds input.state from the keyboard each tick).
  local function hold(dir, frames)
    for _ = 1, frames do
      game.input.state[dir] = true
      coroutine.yield()
    end
    game.input.state[dir] = false
    coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit() return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11; if n > 1500 then break end
  end
  game.input:reset()

  local lib = game.mods.exports.TERRARIUM.lib
  local GroundFX = lib.require("GroundFX")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Voxel3D = lib.require("Voxel3D")
  local SnowField = lib.require("SnowField")
  local Pipelines = require("src.render.Pipelines")

  -- ------- RUNGS
  for i = 1, 4 do
    local ok, info = Voxel3D.buildRung(i, false, 1)
    log(("rung %d: %s %s"):format(i, ok and "PASS" or "FAIL",
                                  ok and "" or tostring(info)))
  end
  Voxel3D.resetShaders()

  GroundFX.setting:sync("on")
  DayNight.setting:sync("day")
  Pipelines.setLevel("terrarium_voxel", 5)
  -- the classic camera if the SM64 one is on: a trail is a thing on the
  -- ground and wants to be looked down at
  do
    local ok, MC = pcall(lib.require, "MarioCam")
    if ok and MC and MC.setting then
      pcall(function() MC.setting:sync("off") end)
      log("mariocam: " .. tostring(MC.setting:get()))
    end
  end
  do
    local ok, TS = pcall(lib.require, "TiltShift")
    if ok and TS and TS.setLevel then
      pcall(TS.setLevel, 0)
      log("tiltshift: level " .. tostring(TS.level))
    end
  end
  -- fast enough that a full fall is a short wait rather than a coffee break
  GroundFX.SETTLE, GroundFX.MELT = 6, 4
  Weather.setting:sync("snow")

  -- a spot with buildings, hedges and open ground in one frame, and room
  -- to walk four cells either way -- found, not written down
  game.overworld:setMap("VIRIDIAN_CITY", 5, 5, "down")
  wait(60)
  local m = game.overworld.map
  local bx, by, best = 10, 10, -1
  for cy = 2, (m.height or 20) - 3 do
    for cx = 2, (m.width or 20) - 3 do
      if m:isWalkableCell(cx, cy) and not m:isWaterCell(cx, cy) then
        local open, raised, row = 0, 0, 0
        for dy = -3, 3 do for dx = -3, 3 do
          if m:inBounds(cx + dx, cy + dy) then
            if m:isWalkableCell(cx + dx, cy + dy) then open = open + 1
            else raised = raised + 1 end
          end
        end end
        for dx = -4, 4 do
          if m:inBounds(cx + dx, cy) and m:isWalkableCell(cx + dx, cy)
             and not m:isGrassCell(cx + dx, cy) then row = row + 1 end
        end
        local score = math.min(open, raised * 2) + row * 2
        if row == 9 and score > best then bx, by, best = cx, cy, score end
      end
    end
  end
  game.overworld:setMap("VIRIDIAN_CITY", bx, by, "down")
  wait(150)
  game.input:reset()
  log(("standing at %d,%d"):format(bx, by))

  -- ------- deep cover
  local spun = 0
  while GroundFX.cover() < 0.80 and spun < 4000 do wait(10); spun = spun + 10 end
  wait(40)
  local depth = GroundFX.snowDepth(game.overworld.map)
  log(("deep: cover=%.2f depth=%.2f tint=%.2f sink=%d px"):format(
    GroundFX.cover(), depth, GroundFX.snowTint(game.overworld.map),
    SnowField.sink(depth)))
  if SnowField.sink(depth) < 3 then log("  FAIL: a full fall does not sink the walker") end
  local st = SnowField.state()
  local fw, fh = SnowField.size()
  log(("field: %s  %dx%d texels of %d px  key=%s"):format(
    st and "bound" or "NIL", fw, fh, SnowField.texel(),
    tostring(SnowField.boundKey())))
  if not st then log("  FAIL: the field has no image for the shader") end
  local sheet = Voxel3D.coatSheet
  log(("coat: sheet=%s top=%.4f (a sheet = the figures took the coat)"):format(
    sheet and (sheet[1] .. "x" .. sheet[2]) or "NONE", Voxel3D.coatTop or 0))
  if not sheet then log("  FAIL: no coat reached the character pass") end
  log(("flakes: sprite batches drawn last frame = %d (want > 0)"):format(
    Weather.lastFlakeBatches or -1))
  if (Weather.lastFlakeBatches or 0) <= 0 then log("  FAIL: the flake sprites never reached the scene pass") end
  local before = shot("70_snow_deep.png")

  -- ------- the walk: four cells west and back, then two south and back
  local pl = game.overworld.player
  local stamps0, mine0 = SnowField.stamps, SnowField.myStamps
  local x0, y0 = pl.cellX, pl.cellY
  -- every position the walker passed through, so the field is sampled
  -- where the boots actually went and not where the probe guessed
  local path = {}
  local function holdRec(dir, frames)
    for _ = 1, frames do
      game.input.state[dir] = true
      coroutine.yield()
      path[#path + 1] = { (pl.px or 0) + 8, (pl.py or 0) + 8 }
    end
    game.input.state[dir] = false
    coroutine.yield()
  end
  holdRec("left", 3 * 16 + 4)
  holdRec("right", 3 * 16 + 4)
  holdRec("down", 2 * 16 + 4)
  holdRec("up", 2 * 16 + 4)
  game.input:reset()
  wait(10)
  log(("walked: from %d,%d to %d,%d over %d recorded positions"):format(
    x0, y0, pl.cellX, pl.cellY, #path))
  local walked = math.abs(pl.cellX - x0) + math.abs(pl.cellY - y0)
  SnowField.flushAll()
  wait(30)
  -- the deepest pressing along the recorded path, and the heap beside it
  local pressed, rim, px, pz = 0, 0, 0, 0
  for i = 1, #path do
    local p, r = SnowField.at(path[i][1], path[i][2])
    if p > pressed then pressed, px, pz = p, path[i][1], path[i][2] end
    if r > rim then rim = r end
  end
  log(("deepest pressing along the path: %.2f at %.0f,%.0f"):format(pressed, px, pz))
  log(("trail: stamps %d -> %d (mine %d -> %d), trodden texels=%d, under the path pressed=%.2f rim=%.2f"):format(
    stamps0, SnowField.stamps, mine0, SnowField.myStamps,
    SnowField.count(), pressed, rim))
  if SnowField.myStamps <= mine0 then log("  FAIL: walking left no footprints in the field") end
  if SnowField.count() < 20 then log("  FAIL: the walk pressed almost nothing") end
  if pressed < 0.3 then log("  FAIL: the path is not pressed under where the walker went") end
  -- a rim somewhere beside the groove: out from the deepest point
  local rimBest = rim
  for dz = -8, 8 do
    for dx = -8, 8 do
      local _, r = SnowField.at(px + dx, pz + dz)
      if r > rimBest then rimBest = r end
    end
  end
  log(("uploads: last frame pushed %d blocks of %d"):format(
    SnowField.lastBlocks, SnowField.BLOCK))
  log(("rim beside the groove: %.2f"):format(rimBest))
  if rimBest <= 0.05 then log("  FAIL: no displaced snow heaped beside the groove") end
  local after = shot("71_snow_trail.png")

  -- ------- what changed on screen between the two
  --
  -- Same cell, same camera, same hour: the flakes and the sun clock move a
  -- little, the trail moves a lot. Sampled every third pixel; the count is
  -- reported as a share of the samples, never as a raw number.
  if before and after then
    local w, h = before:getDimensions()
    local changed, total = 0, 0
    for y = 0, h - 1, 3 do
      for x = 0, w - 1, 3 do
        local r1, g1, b1 = before:getPixel(x, y)
        local r2, g2, b2 = after:getPixel(x, y)
        local l1 = 0.2126 * r1 + 0.7152 * g1 + 0.0722 * b1
        local l2 = 0.2126 * r2 + 0.7152 * g2 + 0.0722 * b2
        if math.abs(l1 - l2) > 0.08 then changed = changed + 1 end
        total = total + 1
      end
    end
    log(("screen: %.2f%% of samples changed by more than 0.08 luminance"):format(
      100 * changed / math.max(1, total)))
  end

  -- ------- ROOFS and TREES let go (lib/SnowFallFX.lua)
  do
    local SnowFallFX = lib.require("SnowFallFX")
    local map = game.overworld.map
    local sites = SnowFallFX.sitesFor(map)
    log(("shed sites: %d eaves, %d trees on %s"):format(
      #sites.roofs, #sites.trees, tostring(map.id)))
    -- what the profile calls the built cells near the walker, so a zero
    -- above is a fact about the rule and not a guess about the classes
    do
      local TileShape = lib.require("TileShape")
      local okSh, shapes = pcall(TileShape.forMap, map)
      local seen, order = {}, {}
      local pl0 = game.overworld.player
      for dy = -6, 6 do
        for dx = -6, 6 do
          local cx, cy = pl0.cellX + dx, pl0.cellY + dy
          if okSh and shapes and map:inBounds(cx, cy) and not map:isWalkableCell(cx, cy) then
            local tx, ty = cx * 2, cy * 2 + 1
            local okS, s = pcall(TileShape.at, map, shapes, map:tileAt(tx, ty), tx, ty)
            if okS and s then
              local key = ("%s/%s/h%d"):format(tostring(s.class), tostring(s.art), s.h or 0)
              if not seen[key] then seen[key] = 0; order[#order + 1] = key end
              seen[key] = seen[key] + 1
            end
          end
        end
      end
      for _, k in ipairs(order) do log(("  built cells near me: %s x%d"):format(k, seen[k])) end
    end
    if #sites.roofs == 0 then log("  FAIL: no eaves found on a town map") end
    if #sites.trees == 0 then log("  FAIL: no trees found on a town map") end
    -- the nearest eave to the walker, forced to let go
    local pl = game.overworld.player
    local ppx, ppz = (pl.px or 0) + 8, (pl.py or 0) + 8
    local best, bd = nil, 1e9
    for _, r in ipairs(sites.roofs) do
      local d = (r.x - ppx) ^ 2 + (r.z - ppz) ^ 2
      if d < bd then best, bd = r, d end
    end
    if best then
      local landed0 = SnowFallFX.landed
      local rim0 = select(2, SnowField.at(best.x, best.z + 4))
      SnowFallFX.slide(best, GroundFX.snowDepth(map))
      wait(6)
      local alive = SnowFallFX.count()
      log(("slide from eave %d,%d (roof %d px): %d motes in the air after 6 frames"):format(
        best.cx, best.cy, best.y, alive))
      if alive == 0 then log("  FAIL: a forced slide spawned nothing") end
      shot("74_roof_slide.png")
      wait(120)
      SnowField.flushAll()
      local rimBest = 0
      for dz = 0, 12 do
        for dx = -8, 8 do
          local _, r = SnowField.at(best.x + dx, best.z + dz)
          if r > rimBest then rimBest = r end
        end
      end
      log(("landed %d clumps; heap under the eave: %.2f (was %.2f); errors=%d %s"):format(
        SnowFallFX.landed - landed0, rimBest, rim0, SnowFallFX.errorCount,
        tostring(SnowFallFX.lastError or "")))
      if SnowFallFX.landed <= landed0 then log("  FAIL: no clump ever landed") end
      -- a heap EXISTS, not "grew": the roofs let go on their own while the
      -- cover built, so this eave may already be heaped to the cap
      if rimBest <= 0.05 then log("  FAIL: the landing heaped nothing") end
    end
    -- a tree beside a walkable cell, bumped into
    local m2 = game.overworld.map
    local tree, stand, face = nil, nil, nil
    local DIRS = { { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" } }
    for _, t in ipairs(sites.trees) do
      for _, d in ipairs(DIRS) do
        local sx, sy = t.cx + d[1], t.cy + d[2]
        if m2:inBounds(sx, sy) and m2:isWalkableCell(sx, sy)
           and not m2:isWaterCell(sx, sy) then
          local dd = (sx - pl.cellX) ^ 2 + (sy - pl.cellY) ^ 2
          if not tree or dd < tree.dd then
            tree, stand, face = { t = t, dd = dd }, { sx, sy }, d[3]
          end
        end
      end
    end
    if tree then
      game.overworld:setMap(m2.id, stand[1], stand[2], face)
      wait(90)
      game.input:reset()
      local bumps0, shakes0 = SnowFallFX.bumps, SnowFallFX.shakes
      hold(face, 30)
      game.input:reset()
      wait(4)
      log(("bumped the tree at %d,%d facing %s: bumps %d -> %d, shakes %d -> %d, motes=%d, coat on me=%.2f"):format(
        tree.t.cx, tree.t.cy, face, bumps0, SnowFallFX.bumps, shakes0,
        SnowFallFX.shakes, SnowFallFX.count(),
        SnowField.coatOf(game.overworld.player)))
      if SnowFallFX.bumps <= bumps0 then log("  FAIL: the bump was never noticed") end
      if SnowFallFX.shakes <= shakes0 then log("  FAIL: the tree did not let go") end
      if SnowField.coatOf(game.overworld.player) <= 0 then log("  FAIL: nothing landed on the walker's hat") end
      shot("75_tree_dump.png")
      wait(80)
      shot("75b_tree_dumped.png")
    else
      log("  FAIL: no tree with a walkable neighbour to bump")
    end
  end

  -- ------- BREATH, SHEDDING, FROST
  do
    local BreathFX = lib.require("BreathFX")
    local SnowFallFX = lib.require("SnowFallFX")
    local puffs0 = BreathFX.puffs
    wait(240)
    log(("breath: cold=%s gate=%s puffs %d -> %d, alive=%d, errors=%d %s"):format(
      tostring(BreathFX.cold()), BreathFX.lastGate, puffs0, BreathFX.puffs,
      BreathFX.count(), BreathFX.errorCount, tostring(BreathFX.lastError or "")))
    if BreathFX.puffs <= puffs0 then log("  FAIL: nobody breathed in the cold") end
    log(("frost on the panes: %.2f"):format(Voxel3D.frost or 0))
    if (Voxel3D.frost or 0) <= 0 then log("  FAIL: no frost with snow on the ground") end
    -- the coat sheds on the move: the tree just dumped on us
    local me = game.overworld.player
    local coat0 = SnowField.coatOf(me)
    hold("down", 40)
    hold("up", 40)
    game.input:reset()
    wait(4)
    log(("shedding: coat %.2f -> %.2f after a walk (want lower)"):format(
      coat0, SnowField.coatOf(me)))
    if coat0 > 0.35 and SnowField.coatOf(me) >= coat0 then log("  FAIL: the coat did not shed on the move") end
    shot("76_breath_shed.png")
    -- and the eaves drip once the thaw starts
    Weather.setting:sync("off")
    GroundFX.MELT = 60
    local drips = 0
    for _ = 1, 240 do
      coroutine.yield()
      for i = 1, SnowFallFX.count() do
        local m = SnowFallFX.get(i)
        if m and m.kind == "drip" and m.t < 0.05 then drips = drips + 1 end
      end
    end
    log(("thaw: %d drips seen in 240 frames (cover now %.2f)"):format(drips, GroundFX.cover()))
    if drips == 0 then log("  FAIL: the eaves never dripped in the thaw") end
    shot("77_thaw_drips.png")
    Weather.setting:sync("snow")
    GroundFX.MELT = 4
    wait(60)
  end

  -- ------- PERMANENCE: the trail stays put in still air
  do
    local peak = SnowField.count()
    Weather.setting:sync("off")
    GroundFX.MELT = 100000
    wait(400)
    log(("still air: trodden texels %d -> %d (want no loss)"):format(peak, SnowField.count()))
    if SnowField.count() < peak then log("  FAIL: the trail faded with nothing falling on it") end
    shot("71b_snow_trail_still.png")
    Weather.setting:sync("snow")
    GroundFX.MELT = 4
  end
  -- ------- FILL: fresh snow buries the trail, slowly -- forced fast here
  do
    local peak = SnowField.count()
    local was = SnowField.FILL_SNOWING
    SnowField.FILL_SNOWING = 1.5
    wait(300)
    SnowField.FILL_SNOWING = was
    log(("fill: trodden texels %d -> %d under fresh snow"):format(peak, SnowField.count()))
    if peak > 0 and SnowField.count() >= peak then log("  FAIL: the trail never filled in") end
  end

  -- ------- MELT
  Weather.setting:sync("off")
  spun = 0
  while GroundFX.cover() > 0.01 and spun < 4000 do wait(20); spun = spun + 20 end
  wait(40)
  log(("melt: cover=%.2f tint=%.2f trodden=%d"):format(
    GroundFX.cover(), GroundFX.snowTint(game.overworld.map), SnowField.count()))
  if SnowField.count() > 0 then log("  FAIL: the thaw left trails in the field") end
  shot("72_snow_melted.png")

  -- ------- OFF
  Weather.setting:sync("snow")
  spun = 0
  while GroundFX.cover() < 0.5 and spun < 4000 do wait(10); spun = spun + 10 end
  GroundFX.setting:sync("off")
  wait(30)
  log(("GROUND off: tint=%.2f depth=%.2f sink=%d (want 0 / 0 / 0)"):format(
    GroundFX.snowTint(game.overworld.map), GroundFX.snowDepth(game.overworld.map),
    SnowField.sink(GroundFX.snowDepth(game.overworld.map))))
  if GroundFX.snowTint(game.overworld.map) > 0 then log("  FAIL: the row does not switch the snow off") end
  shot("73_snow_ground_OFF.png")
  GroundFX.setting:sync("on")

  log(("done: %d FAIL"):format(fails))
  logf:close()
  love.event.quit()
end
