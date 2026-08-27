-- Probe: is the rain a shower, or a picket fence?
--
-- Five numbers, and every one of them is invisible in a screenshot of
-- falling water. A still frame of rain looks like rain whether or not any
-- of this is true, which is exactly why it has to be counted.
--
--   ANGLE SPREAD.  The standard deviation, in degrees, of the direction
--   each streak is DRAWN at. Real rain has spread: a fine drop reaches the
--   air's own sideways speed and a fat one barely leans, so a shower is a
--   fan of angles, not a comb. Zero here means every drop in the world is
--   parallel to every other -- the picket fence.
--
--   ANGLE ERROR.  The mean absolute difference, in degrees, between where
--   a streak POINTS and where its drop is actually GOING. A streak is
--   supposed to be the path the water just took; if it is drawn on a fixed
--   lean while the drop travels on another, every drop in the frame is
--   sliding sideways inside its own trail. This is the one that cannot be
--   seen and cannot be argued with.
--
--   GUST COHERENCE.  Horizontal-velocity agreement between shafts that are
--   CLOSE together, measured against the same for shafts that are FAR
--   apart. Wind arrives in bands: two drops a cell apart ride the same band
--   and two drops six cells apart usually do not. A uniform field scores 0
--   (near and far agree equally -- there is no structure); a field of pure
--   noise scores 0 too (nothing agrees with anything). Only a field with
--   real spatial structure scores high.
--
--   SPEED SPREAD.  Coefficient of variation of fall speed. Drop size is the
--   reason rain has texture at all -- one distribution of sizes gives the
--   near/far reading that a per-layer constant cannot.
--
--   MID-AIR POPS.  Shafts that vanished between two adjacent frames while
--   still well inside the draw reach and well above the ground. Every one of
--   those is a raindrop that blinked out in front of the player.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> DS_PROBE_TAG=base
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/rain_physics_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local TAG = os.getenv("DS_PROBE_TAG") or "base"
  local logf = assert(io.open(OUT .. "/rain_physics_" .. TAG .. ".log", "w"))
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
    wait(4)
  end

  love.math.setRandomSeed(20260819)

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit() return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11; if n > 1500 then break end
  end

  local lib = game.mods.exports.TERRARIUM.lib
  local Weather = lib.require("Weather")
  local Wind = lib.require("Wind")
  local DayNight = lib.require("DayNight")
  local Voxel3D = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")

  -- ------- the pass has to actually be UP
  --
  -- Setting the pipeline level asks for the diorama; it does not deliver
  -- it, and there is no frame on which it is guaranteed. The first run of
  -- this probe shot every picture of the FLAT 2D world -- rain drawn in the
  -- one register that has no camera, no splashes and no shafts in it -- and
  -- the numbers were fine while the images showed a different feature
  -- entirely.
  --
  -- lampLights is the tell: VoxelScene fills it every outdoor 3D frame and
  -- nothing else writes it, so nil-then-not-nil is the pass coming up.
  -- Cleared before every setMap, because a stale one from the last map is
  -- an instant pass.
  -- ------- the wind is the free variable, so it gets nailed down
  --
  -- Everything measured here is a claim about rain IN WIND, and the wind
  -- this world makes for itself runs on a multi-scale gust envelope driven
  -- by the wall clock. Two runs of this probe therefore meet different
  -- weather, and a twenty per cent difference in the shower is a twenty
  -- per cent difference in the wind before it is anything else.
  --
  -- So the climate is pinned to one number and the gust to another. The
  -- bearing still meanders -- that lives inside Wind.step and pinning it
  -- from out here would desync it from the flow field the step builds in
  -- the same pass -- which is the remaining wobble between runs, and the
  -- reason the ink below is averaged over eight frames rather than trusted
  -- from one.
  Wind.climateTarget = function()
    Wind.gustNow = 0.35
    return 0.42
  end

  Pipelines.setLevel("terrarium_voxel", 5)
  local function wait3D(cap)
    for i = 1, (cap or 900) do
      if Voxel3D.lampLights ~= nil then return i end
      coroutine.yield()
    end
    return -1
  end
  local function goTo(id, x, y, face)
    Voxel3D.lampLights = nil
    game.overworld:setMap(id, x, y, face)
    local up = wait3D(900)
    log(("[%s] 3D pass up after %s frames"):format(id, tostring(up)))
    return up > 0
  end
  DayNight.setting:sync("day")
  Wind.setting:sync(4)                    -- GALE, so the lean is signal not noise
  Weather.setting:sync("rain")

  goTo("VIRIDIAN_CITY", 10, 10, "up")
  wait(90)

  if not Weather.shaftDump then
    log("FAIL: no Weather.shaftDump seam")
    logf:close(); love.event.quit(); return
  end

  -- A shower BUILDS, over the better part of a minute, and the first run of
  -- this probe measured a drizzle at a sixth of its power while believing it
  -- was looking at a downpour. Pin it. Everything below is a claim about the
  -- rain at full, and the ramp is a different feature with its own probe.
  local function pin(kind)
    if Weather.pin then Weather.pin(kind, 1.0) end
  end
  pin("rain")
  wait(40)

  -- ------- collect
  --
  -- Several frames, because one frame of 150 shafts is one draw under one
  -- gust, and the spread of a single band is not the spread of the field.
  local ANG = {}          -- drawn direction, radians from straight down
  local ERR = {}          -- |drawn - travelled|, radians
  local SPD = {}          -- fall speed
  local FRAMES = {}       -- per-frame shaft lists, for the coherence pass
  local kind, power = Weather.visible()
  log(("weather=%s power=%.2f wind=%.2f gust=%.2f dir=%.2f,%.2f"):format(
      tostring(kind), power or 0, Wind.amount(), Wind.gust(),
      Wind.DIR[1], Wind.DIR[2]))

  local LEAN = Weather.LEAN or 0.20
  for f = 1, 12 do
    local list = {}
    Weather.shaftDump(list)
    FRAMES[#FRAMES + 1] = list
    local wAmt = Wind.amount()
    local wdx, wdz = Wind.DIR[1] or 1, Wind.DIR[2] or 0
    for i = 1, #list do
      local s = list[i]
      -- The streak AS DRAWN. When the file offers the tail vector it built
      -- (drawx/y/z) that is the honest answer; otherwise reconstruct the
      -- old fixed lean exactly as drawShafts computed it.
      local dvx, dvy, dvz
      if s.drawx then
        dvx, dvy, dvz = s.drawx, s.drawy, s.drawz
      else
        local lean = LEAN * math.min(wAmt, 3) * (s.len or 16)
        dvx, dvy, dvz = wdx * lean, -(s.len or 16), wdz * lean
      end
      local dh = math.sqrt(dvx * dvx + dvz * dvz)
      local drawn = math.atan2(dh, math.abs(dvy))
      -- the way the drop is actually travelling this frame
      local th = math.sqrt((s.vx or 0) ^ 2 + (s.vz or 0) ^ 2)
      local truev = math.atan2(th, math.abs(s.vy or 1))
      ANG[#ANG + 1] = drawn
      ERR[#ERR + 1] = math.abs(drawn - truev)
      SPD[#SPD + 1] = math.abs(s.vy or 0)
    end
    wait(2)
  end

  local function mean(t)
    local s = 0; for i = 1, #t do s = s + t[i] end
    return #t > 0 and s / #t or 0
  end
  local function sd(t)
    local m, s = mean(t), 0
    for i = 1, #t do s = s + (t[i] - m) ^ 2 end
    return #t > 1 and math.sqrt(s / (#t - 1)) or 0
  end
  local DEG = 180 / math.pi

  -- ------- gust coherence
  --
  -- Pairs of shafts inside one frame. NEAR is within two cells, FAR is
  -- beyond six. For each bucket, the mean absolute difference of the
  -- horizontal velocity vector, normalised by the field's own mean
  -- horizontal speed. Coherence is how much smaller the near number is.
  local nearD, farD = {}, {}
  local hmag = {}
  for f = 1, #FRAMES do
    local L = FRAMES[f]
    local step = math.max(1, math.floor(#L / 60))
    for i = 1, #L, step do
      local a = L[i]
      hmag[#hmag + 1] = math.sqrt((a.vx or 0) ^ 2 + (a.vz or 0) ^ 2)
      for j = i + step, #L, step do
        local b = L[j]
        local dx, dz = a.x - b.x, a.z - b.z
        local d = math.sqrt(dx * dx + dz * dz)
        local dv = math.sqrt(((a.vx or 0) - (b.vx or 0)) ^ 2
                           + ((a.vz or 0) - (b.vz or 0)) ^ 2)
        if d < 32 then nearD[#nearD + 1] = dv
        elseif d > 96 then farD[#farD + 1] = dv end
      end
    end
  end
  local base = math.max(1e-3, mean(hmag))
  local nearN, farN = mean(nearD) / base, mean(farD) / base
  local coh = (farN > 1e-4) and (1 - nearN / farN) or 0

  -- ------- mid-air pops
  --
  -- Two consecutive dumps. A shaft present in the first and gone from the
  -- second, while it was still well above whatever it was going to land on
  -- AND still being drawn at some real brightness, did not land -- it
  -- blinked out in front of the player.
  --
  -- Matched by ID, and that is not a detail: a drop moves every frame,
  -- which is the entire point of it, so matching by position counts the
  -- whole field as having vanished and reappeared. The first version of
  -- this probe did exactly that and reported a third of the rain popping
  -- every frame, which was the metric popping, not the rain.
  --
  -- The visibility gate matters just as much. A shaft that fades out at
  -- the rim and is then recycled has not popped -- nobody could see it --
  -- so only shafts still drawn above a real alpha are counted.
  local A, B = {}, {}
  Weather.shaftDump(A); wait(1); Weather.shaftDump(B)
  local seen = {}
  for i = 1, #B do seen[B[i].id or -i] = true end
  local pop, checked, byId = 0, 0, 0
  for i = 1, #A do
    local s = A[i]
    if s.id then byId = byId + 1 end
    if (s.vis or 1) > 0.25 and s.y > 28 then
      checked = checked + 1
      if s.id and not seen[s.id] then pop = pop + 1 end
    end
  end
  if byId == 0 then
    log("NOTE: no shaft ids -- pop count is not measurable on this build")
  end

  log("")
  log("=== RAIN PHYSICS [" .. TAG .. "] ===")
  log(("shafts sampled     %d over %d frames"):format(#ANG, #FRAMES))
  log(("angle spread       %.2f deg   (0 = every streak parallel)"):format(sd(ANG) * DEG))
  log(("angle mean         %.2f deg"):format(mean(ANG) * DEG))
  log(("angle error        %.2f deg   (drawn vs travelled)"):format(mean(ERR) * DEG))
  log(("speed spread       %.3f cv    (fall-speed variation)"):format(
      sd(SPD) / math.max(1e-3, mean(SPD))))
  log(("gust coherence     %.3f       (near-pair agreement over far)"):format(coh))
  log(("   near dv %.3f  far dv %.3f  base |v| %.1f"):format(nearN, farN, base))
  log(("mid-air pops       %d of %d visible shafts, one frame"):format(pop, checked))
  if Weather.lightNow then
    local r, g, b = Weather.lightNow()
    log(("hour light on rain %.3f %.3f %.3f  (1,1,1 = painted at noon-white)")
        :format(r, g, b))
  end
  if Weather.refractState then
    log(("streak path        %s"):format(Weather.refractState()))
    if Weather.refractState() ~= "refract" then
      log("  WARN: the lens shader is not running; this is the additive fallback")
    end
  end
  if Weather.sheetState then
    local state, n = Weather.sheetState()
    log(("impact path        %s (%s sheets loaded)"):format(state, tostring(n)))
    if state ~= "sheets" then
      log("  WARN: the sheets did not decode; this is the drawn fallback")
    end
  end
  log("")

  -- ------- and the pictures
  --
  -- Same seed, same map, same hour, same wind, same moments -- so the before
  -- and after can be laid side by side and the change is the only difference
  -- between them.
  -- Eight, spread out, because the ink on any ONE frame swings by a third
  -- with where the gust happens to be -- which is the field working, and
  -- also the reason a single screenshot cannot answer "is there as much
  -- rain as there was".
  for k = 1, 8 do
    log(("ink frame %d: wind=%.2f gust=%.2f dir=%.2f,%.2f"):format(
        k, Wind.amount(), Wind.gust(), Wind.DIR[1], Wind.DIR[2]))
    shot(("9%d_rain_%s_k.png"):format(k - 1, TAG))
    wait(20)
  end

  -- ------- THE FOUR RAINS
  --
  -- Drizzle, moderate, heavy, cloudburst -- the four the concept sheet
  -- asks for -- and the claim is that they are not one rain at four
  -- densities. The drop roll moves with the power, so a drizzle should be
  -- made of fine slow drops leaning a long way and a cloudburst of fat
  -- fast ones going nearly straight down. Which means the numbers that
  -- separate them are the ANGLE and the SPEED, not just the count, and
  -- those are what get logged beside each picture.
  for _, tier in ipairs({ { 0.15, "fina" }, { 0.40, "media" },
                          { 0.70, "forte" }, { 1.00, "torrencial" } }) do
    Weather.pin("rain", tier[1])
    wait(120)
    local L = {}
    Weather.shaftDump(L)
    local sd, sa, n = 0, 0, #L
    for i = 1, n do
      local s = L[i]
      sd = sd + math.abs(s.vy or 0)
      sa = sa + math.atan2(math.sqrt((s.vx or 0) ^ 2 + (s.vz or 0) ^ 2),
                           math.abs(s.vy or 1))
    end
    if n > 0 then
      log(("tier %-11s power %.2f  shafts %4d  fall %5.1f px/s  lean %5.2f deg")
          :format(tier[2], tier[1], n, sd / n, sa / n * 180 / math.pi))
    end
    shot(("8%d_tier_%s_%s.png"):format(
        ({ fina = 0, media = 1, forte = 2, torrencial = 3 })[tier[2]],
        TAG, tier[2]))
  end
  Weather.pin("rain", 1.0)
  wait(60)

  -- ------- and the meadow emptying out
  --
  -- Counted dry, then wet, then dry again, and the third reading is the one
  -- that matters: an empty meadow and a meadow whose butterflies this
  -- change has permanently deleted look exactly the same in a screenshot,
  -- and only one of them is the feature.
  local AmbientLife = lib.require("AmbientLife")
  -- ------- ON A ROUTE, NOT IN A TOWN
  --
  -- The first run of this asked the question in Viridian City and got
  -- "dry 1 -> wet 1 -> dry 2". A town has almost nothing in the air, so the
  -- reading was one butterfly wide and could not have told an emptied
  -- meadow from an untouched one either way. The claim is about a MEADOW;
  -- it has to be measured over grass.
  goTo("ROUTE_1", 10, 20, "down")
  wait(120)
  local function wings()
    local n = 0
    for _, k in ipairs({ "butterfly", "dragonfly", "sparrow" }) do
      n = n + (AmbientLife.count and AmbientLife.count(k) or 0)
    end
    return n
  end
  Weather.pin(nil, 0)
  wait(300)
  local dryA = wings()
  Weather.pin("rain", 1.0)
  wait(300)
  local wetN = wings()
  Weather.pin(nil, 0)
  wait(420)
  local dryB = wings()
  log(("wings in the air    dry %d -> wet %d -> dry %d"):format(dryA, wetN, dryB))
  if wetN >= dryA and dryA > 0 then
    log("  FAIL: the shower did not empty the air")
  end
  if dryA > 0 and dryB == 0 then
    log("  FAIL: they did not come back -- the shower deleted them")
  end
  Weather.pin("rain", 1.0)
  wait(90)

  -- ------- what a frame of this costs
  --
  -- The counts went up by a factor of three and the impacts became sprite
  -- batches, and both of those are claims about cost as much as about
  -- looks. Measured as the wall time of a run of frames with the shower on
  -- and the same run with it off -- the DIFFERENCE is the weather, which
  -- is the only part this work is answerable for.
  local function timeFrames(n)
    local t0 = love.timer.getTime()
    for _ = 1, n do coroutine.yield() end
    return (love.timer.getTime() - t0) / n * 1000
  end
  wait(30)
  local wet = timeFrames(120)
  Weather.pin(nil, 0)
  wait(90)
  local dry = timeFrames(120)
  Weather.pin("rain", 1.0)
  wait(60)
  log(("frame cost         %.2f ms wet, %.2f ms dry -> weather %.2f ms")
      :format(wet, dry, wet - dry))

  -- night, where rain that does not take the light reads as white scratches
  -- ruled over a dark picture. Vermilion rather than Viridian: the lamps
  -- are the whole claim after dark, and a street with no posts on it cannot
  -- show whether the drops brighten under one.
  DayNight.setting:sync("night")
  goTo("VERMILION_CITY", 15, 12, "up")
  wait(120)
  pin("rain")
  wait(40)
  shot(("74_rain_%s_night.png"):format(TAG))
  if Weather.lightNow then
    local r, g, b = Weather.lightNow()
    log(("night light on rain %.3f %.3f %.3f, lamps found %s"):format(
        r, g, b, tostring(Weather.lampCount and Weather.lampCount() or "?")))
  end
  DayNight.setting:sync("day")
  wait(60)

  -- a pond, where the splash crowns land
  local water = nil
  do
    local m = game.overworld.map
    for cy = 2, (m.height or 20) - 3 do
      for cx = 2, (m.width or 20) - 3 do
        if m:isWaterCell(cx, cy) then
          -- stand BESIDE it, not in it
          for _, o in ipairs({ { 0, -2 }, { 0, 2 }, { -2, 0 }, { 2, 0 } }) do
            local sx, sy = cx + o[1], cy + o[2]
            if m:inBounds(sx, sy) and m:isWalkableCell(sx, sy)
               and not m:isWaterCell(sx, sy) then
              water = water or { sx, sy }
            end
          end
        end
      end
    end
  end
  if water then
    goTo("VERMILION_CITY", water[1], water[2], "down")
    log(("standing by water at %d,%d"):format(water[1], water[2]))
  end
  wait(120)
  pin("rain")
  wait(60)
  local sp, ej = 0, 0
  for _ = 1, 20 do
    sp = math.max(sp, Weather.moteCount("splash"))
    ej = math.max(ej, Weather.moteCount("eject"))
    wait(3)
  end
  log(("splashes alive     %d (peak over 20 samples)"):format(sp))
  log(("ejecta alive       %d (peak over 20 samples)"):format(ej))
  shot(("72_rain_%s_water.png"):format(TAG))

  -- ------- the surface, with the sky taken away
  --
  -- What a drop does when it LANDS is drawn at two or three pixels a
  -- ring, in a frame that also has two hundred streaks falling through
  -- it. Asking a screenshot of a downpour whether the crowns are right is
  -- asking it to answer about the one thing it is least able to show.
  --
  -- So the falling half is switched off and the landing half is left
  -- running. The rings and the drops thrown off them are then the only
  -- thing on the water, which is the only way to see either.
  local sh, shm, st = Weather.SHAFTS, Weather.SHAFTS_MAX, Weather.STREAKS
  Weather.SHAFTS, Weather.SHAFTS_MAX, Weather.STREAKS = 0, 0, 0
  wait(30)
  -- and keep the rings coming, since the shafts that used to spawn them
  -- are gone: the ambient floor is what is left, so raise it
  local fl = Weather.SPLASH_FLOOR
  Weather.SPLASH_FLOOR = Weather.SPLASHES
  wait(45)
  log(("surface only: splashes %d  ejecta %d"):format(
      Weather.moteCount("splash"), Weather.moteCount("eject")))
  shot(("75_rain_%s_surface.png"):format(TAG))
  Weather.SHAFTS, Weather.SHAFTS_MAX, Weather.STREAKS = sh, shm, st
  Weather.SPLASH_FLOOR = fl
  wait(30)

  -- and the snow, on the same rig
  Weather.setting:sync("snow")
  wait(60)
  pin("snow")
  wait(200)
  log(("snow flakes alive  %d"):format(Weather.moteCount("flake")))
  shot(("73_snow_%s.png"):format(TAG))

  log("done")
  logf:close()
  love.event.quit()
end
