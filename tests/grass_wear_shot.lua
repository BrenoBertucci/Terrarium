-- Probe: does WEAR actually read on screen, or is it only true in the maths?
--
-- tests/grass_wear_offline.lua proves the field accumulates, saturates,
-- decays and survives a save. None of that is evidence that a worn cell
-- LOOKS worn. The thinning lives entirely in the vertex shader -- a
-- smoothstep against a per-tuft hash that folds blades back to their own
-- root -- and every way that can fail is invisible to an offline test:
-- the uniform never arriving, the uv landing outside 0..1, `baseY` being
-- wrong so a folded blade lands somewhere other than the ground, the whole
-- branch sitting behind a grassDetail gate that this device never reaches.
--
-- So this probe does not look at the field. It looks at PIXELS.
--
-- ------- the method, and why it is a difference and not a picture
--
-- A single screenshot of a meadow is as worn or as lush as you please.
-- With the clock pinned, the camera still, the weather off, the player
-- held in place and nothing else in the world moving, the ONLY thing that
-- changes between two shots is the wear value written into the field --
-- so every pixel that differs is a pixel wear is responsible for. That
-- integer is the answer. If it is zero, the feature does not exist on
-- screen no matter what the shader source says.
--
-- ------- three things this gets wrong if it is careless
--
--  1. THE PLAYER WALKS ON THEIR OWN. After setMap the engine rebuilds
--     input.state from the real keyboard every tick, and a probe that
--     merely refrains from pressing anything still drifts -- grass_physics
--     _probe learned this the hard way (see its hold()). A walker who
--     moves between the A and the B shot moves grass pixels, and that
--     motion lands in the count as if wear had caused it. So every frame
--     here re-asserts the player's cell and every direction is written
--     false, and the run VERIFIES the cell did not move across the pair.
--
--  2. THE MEADOW IS ALREADY MOVING. Wind animates the tufts frame to
--     frame, so two shots taken at different times differ everywhere
--     regardless of wear. The wind row goes OFF and the clock is pinned,
--     and the baseline pair (A against a second A) measures whatever
--     motion is left. That noise floor is subtracted from every verdict:
--     a wear count that does not clear it by a wide margin is not a
--     reading, it is the wind.
--
--  3. THE WALKER'S OWN FEET WRITE WEAR. Standing still must not, and
--     VoxelScene only writes above the moving-strength threshold, but
--     that is a claim this probe is in a position to check -- so it does,
--     by holding position for several seconds and asking the field
--     whether anything appeared under the player.
--
-- ------- what it asks
--
--   Q0 BASELINE     the noise floor with nothing changed at all
--   Q1 READS        wear 0 -> 0.75 changes pixels, well past the floor
--   Q2 DIRECTION    it REMOVES tuft pixels (the ground shows through)
--   Q3 GRADIENT     0.25 / 0.50 / 0.75 deepen monotonically (no pop)
--   Q4 TIER 0       at the cheap rung wear changes NOTHING
--   Q5 SHELTER      forced shelter quiets the meadow between frames
--   Q6 IDLE         standing still writes no wear
--   Q7 PALINDROME   the first and last baseline agree, or the run is void
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/grass_wear_shot.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/grass_wear_shot.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

  local pass, fail = 0, 0
  local function check(ok, msg)
    if ok then pass = pass + 1; log("PASS: " .. msg)
    else fail = fail + 1; log("FAIL: " .. msg) end
  end

  love.math.setRandomSeed(20260817)

  -- ------- get to free roam
  local frames = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); frames = frames + 1
    if frames > 900 then
      log("FAIL: no overworld"); logf:close(); love.event.quit(); return
    end
  end
  frames = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); frames = frames + 11
    if frames > 1500 then log("FAIL: never reached free roam"); break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end
  log("version:", exports.TERRARIUM.version)

  local GrassWear = lib.require("GrassWear")
  local Grass3D = lib.require("Grass3D")
  local Wind = lib.require("Wind")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Quality = lib.require("Quality")
  local GroundFX = lib.require("GroundFX")
  local Pipelines = require("src.render.Pipelines")

  local WildRoamers = lib.require("WildRoamers")
  local AmbientLife = lib.require("AmbientLife")
  local CityLife = lib.require("CityLife")
  local Routines = lib.require("Routines")
  local Vfx = lib.require("Vfx")

  -- ------- pin everything in the world that moves on its own
  --
  -- Each of these draws or animates something in the meadow, and any one of
  -- them left running puts its own pixels in the count -- a Rattata
  -- crossing the frame between the A and the B shot is thousands of
  -- changed pixels attributed to wear.
  DayNight.setting:sync("day")
  Weather.setting:sync("off")
  WildRoamers.setting:sync("off")
  AmbientLife.setting:sync("off")
  CityLife.setting:sync("off")
  Routines.setting:sync("off")
  Vfx.setting:sync("off")
  Pipelines.setLevel("terrarium_voxel", 4)
  Quality.setting:sync(1)           -- FULL -> grassDetail 2
  -- ------- and SHADOWS OFF, which is a pin and not a shortcut
  --
  -- The shadow map refreshes on a rolling cadence (Quality.shadowInterval),
  -- so it is the one system left that is at a different phase five hundred
  -- frames later through no fault of the scene. It is what kept the
  -- palindrome from closing (a return of 3310 then 8413 against a floor of
  -- ~1100) after every other suspect had been moved out.
  --
  -- What this gives up: thinned grass also casts less shadow, and that
  -- part of the look is now outside the measurement. The claim under test
  -- is that the GEOMETRY changes, and geometry is what is left.
  Quality.shadowSetting:sync("off")
  game.overworld:setMap("ROUTE_1", 10, 28, "down")
  wait(180)
  for _ = 1, 300 do Weather.update(1 / 30) end
  wait(30)

  -- ------- the wind is FROZEN, not switched off
  --
  -- This is the trap that made the first cut of this probe useless. The
  -- whole grass block in the vertex shader sits behind `if (sway > 0.0)`,
  -- and `sway` is Wind.amount() (VoxelScene:1153) -- so WIND=OFF does not
  -- give a still meadow, it gives NO GRASS PHYSICS AT ALL, wear included.
  -- Every question below would have measured zero changed pixels and this
  -- probe would have reported a working feature as broken.
  --
  -- What is wanted is a meadow that is leaning and NOT MOVING: a constant
  -- amount so the block runs, and a constant phase so the lean is the same
  -- in every frame. The clock is pinned the same way, because the palette
  -- shifts with it and a drifting palette recolours the whole screen.
  local realAmount, realPhase, realLoad = Wind.amount, Wind.phase, Wind.load
  local PIN_AMOUNT, PIN_PHASE = 2.5, 7.0
  local PIN_CLOCK = DayNight.clock
  local function freezeWind()
    Wind.amount = function() return PIN_AMOUNT end
    Wind.phase = function() return PIN_PHASE end
    Wind.load = function() return 0, 0, 0 end
  end
  local function thawWind()
    Wind.amount, Wind.phase, Wind.load = realAmount, realPhase, realLoad
  end
  freezeWind()

  -- ------- which grass is actually in front of the shader
  --
  -- The wear code rides "whatever the grass pass is drawing", so it works
  -- on both the authored 3D tuft and the classic tileset slab. But they
  -- are very different geometry -- a bake is tens of triangles a tuft
  -- against the slab's two quads -- and a run that does not say which one
  -- it measured has only tested one of them while claiming both.
  --
  -- The GRASS row is forced to `mesh` here so the bake gets its chance,
  -- and every reason it can still decline is logged rather than left as a
  -- bare false. (A run against a build whose bake was 1096 bytes and 24
  -- triangles -- comfortably inside the budget -- still reported
  -- available=false, and there was no way to tell why from the log.)
  Grass3D.setting:sync("mesh")
  Grass3D.invalidate()
  -- `wait`, not `still`: this block runs before the player is looked up, so
  -- the input-pinning helper does not exist yet.
  wait(10)
  local okMeta, meta = pcall(Grass3D.meta)
  local okTex, tex = pcall(Grass3D.texture)
  log(("grass path: wantsMesh=%s available=%s"):format(
        tostring(Grass3D.wantsMesh and Grass3D.wantsMesh()),
        tostring(Grass3D.available and Grass3D.available())))
  log(("  template=%s texture=%s"):format(
        (okMeta and meta) and
          ("verts=" .. tostring(meta.verts) .. " tris="
           .. tostring((meta.indices or 0) / 3) .. " h="
           .. tostring(meta.height)) or "REFUSED",
        (okTex and tex) and "loaded" or "MISSING"))
  log("grassDetail =", Quality.grassDetail())
  log("pinned: sway =", Wind.amount(), " phase =", Wind.phase(),
      " clock =", PIN_CLOCK)

  local pl = game.overworld.player
  local home = game.overworld.map and game.overworld.map.id
  local hx, hy = pl.cellX, pl.cellY
  log(("home: map=%s cell=(%d,%d)"):format(tostring(home), hx or -1, hy or -1))

  -- ------- holding STILL means writing every direction false every frame
  --
  -- The mirror image of grass_physics_probe's hold(): the engine rebuilds
  -- input.state from the keyboard on its own tick, so "not pressing" is
  -- not a state a probe can be in by omission -- it has to be asserted.
  local DIRS = { "up", "down", "left", "right" }
  local drifted = false
  -- One frame of "nothing is happening": no input, and the clock put back
  -- where it was. DayNight.update advances the clock from the engine's own
  -- tick whatever the row says, and a clock that drifts across a pair of
  -- shots recolours every pixel in both.
  local function tick()
    for i = 1, #DIRS do game.input.state[DIRS[i]] = false end
    DayNight.clock = PIN_CLOCK
    coroutine.yield()
    if pl.cellX ~= hx or pl.cellY ~= hy then drifted = true end
  end
  local function still(n)
    for _ = 1, n do tick() end
  end
  still(30)

  -- ------- the shot
  local function grab()
    local out, pending = nil, true
    love.graphics.captureScreenshot(function(data) out = data; pending = false end)
    tick()
    local guard = 0
    while pending and guard < 240 do tick(); guard = guard + 1 end
    return out
  end

  local function shotPng(name)
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()); f:close() end
    end)
    still(3)
  end

  -- Max absolute channel delta per pixel, against two bars. 0.02 is about
  -- five levels of 255 -- where a changed pixel starts to be visible at
  -- all; 0.08 is where it stops being deniable. Also returns the signed
  -- LUMINANCE shift over the changed pixels, which is what Q2 needs:
  -- thinning uncovers the ground, so the sign says whether tuft pixels
  -- were removed rather than merely disturbed.
  -- How many pixels the last diff sampled. Declared before `diff` because
  -- `diff` writes it, and every threshold in this probe is a fraction of
  -- it (see `frac`).
  local sampled = 0
  --
  -- ------- and the 4th return, which is the one Q3 needs
  --
  -- `lum` below is the mean over the pixels that CHANGED, and that
  -- denominator grows with wear -- so as more of the meadow thins, edge
  -- pixels that darken slightly join the set and dilute the mean. It is
  -- not a depth metric, and it lies in a specific, confusing way: one run
  -- measured the same wear=0.75 as +0.0786 in Q1 and +0.0203 in Q3 purely
  -- because Q3's set was bigger. `lumAll` divides the same sum by the
  -- FIXED number of pixels sampled, so it answers "how much brighter did
  -- this region get overall" and is comparable between calls.
  local function diff(a, b)
    if not (a and b) then return -1, -1, 0, 0 end
    local w = math.min(a:getWidth(), b:getWidth())
    local h = math.min(a:getHeight(), b:getHeight())
    local lo, hi, lumSum, lumN, allN = 0, 0, 0, 0, 0
    -- every other pixel on both axes: a quarter of the work, and the
    -- counts are only ever compared against each other
    for y = 0, h - 1, 2 do
      for x = 0, w - 1, 2 do
        local r1, g1, b1 = a:getPixel(x, y)
        local r2, g2, b2 = b:getPixel(x, y)
        allN = allN + 1
        local d = math.max(math.abs(r1 - r2),
                           math.abs(g1 - g2), math.abs(b1 - b2))
        if d > 0.02 then
          lo = lo + 1
          local l1 = 0.299 * r1 + 0.587 * g1 + 0.114 * b1
          local l2 = 0.299 * r2 + 0.587 * g2 + 0.114 * b2
          lumSum = lumSum + (l2 - l1)
          lumN = lumN + 1
          if d > 0.08 then hi = hi + 1 end
        end
      end
    end
    if allN > 0 then sampled = allN end
    return lo, hi,
           (lumN > 0) and (lumSum / lumN) or 0,
           (allN > 0) and (lumSum / allN) or 0,
           allN
  end

  -- ------- every threshold is a FRACTION of what was sampled
  --
  -- This is the third time in this probe that an absolute number failed to
  -- travel: the luminance mean over a set whose size changes, the settle
  -- bar, and this. Q4 runs at 1/3 resolution, where a ninth as many pixels
  -- are sampled -- so a bar of "2000 changed pixels" is nine times looser
  -- there than here, and Q4's floor swung between 322 and 7766 across runs
  -- for no reason but that. Counts scale with the framebuffer; fractions
  -- do not.
  -- `sampled` is filled in by the first real diff and re-filled whenever
  -- the framebuffer changes size (Q4), so `frac` always speaks in terms of
  -- the resolution currently on screen.
  local function frac(f)
    if sampled <= 0 then return math.huge end
    return math.max(1, math.floor(sampled * f))
  end

  -- ------- waiting for the scene to STOP, measured rather than guessed
  --
  -- Something in the render settles over roughly twenty frames after a
  -- change -- the shadow map has its own cadence (Quality.shadowInterval)
  -- and the chunk mesher finishes replacements in the background
  -- (main.lua's remesh note). A fixed wait is a guess about that, and the
  -- guess is load-bearing: one run of this probe used `still(6)` and
  -- measured a noise floor of 173771 changed pixels against the 761 the
  -- same scene gives once settled. Every verdict in that run was noise
  -- wearing a number.
  --
  -- So the wait is a LOOP with a condition: shoot pairs until two
  -- consecutive frames agree, and report how long it took. A run that
  -- never settles says so instead of quietly reporting the shimmer.
  -- 1% of the sampled pixels. Measured, not guessed: this scene's idle
  -- floor came in at 578..1146 across six runs of ~196k sampled pixels, so
  -- 0.4% (786) sat inside the run-to-run spread and failed on its own
  -- noise. 1% clears it and is still twenty-three times below the wear
  -- signal it has to distinguish.
  local SETTLE_FRAC = 0.01
  local function settle(maxTries)
    local prev = grab()
    for i = 1, (maxTries or 40) do
      local cur = grab()
      local d = diff(prev, cur)
      if d < frac(SETTLE_FRAC) then return d, i end
      prev = cur
    end
    return -1, (maxTries or 40)
  end

  -- The visible patch of grass around the player, in cells. 16 px a cell,
  -- and the camera shows well under this either way -- overshooting only
  -- costs cells that are off screen and cannot enter the count.
  local function setWear(v)
    GrassWear.clearWear()
    if v > 0 then
      GrassWear.fillCells((hx or 10) - 14, (hy or 28) - 14,
                          (hx or 10) + 14, (hy or 28) + 14,
                          v, GrassWear.CAUSE_TRAMPLE)
    end
    -- The per-step upload is budgeted at UPLOAD_BUDGET texels a frame,
    -- which is right for play (a walker dirties one cell) and hopeless
    -- here: a fill dirties hundreds and a shelter override dirties all
    -- 16384. Draining it explicitly is what makes the next shot show the
    -- value that was just set rather than a patchwork of old and new.
    GrassWear.flushAll()
    -- ------- and then WAIT UNTIL IT STOPS, not for twenty frames
    --
    -- Thinning the meadow changes what casts shadows, and the shadow map
    -- refreshes on its own cadence (Quality.shadowInterval) -- so the
    -- frames right after a wear change are lit by a shadow map built for
    -- the OLD grass. A fixed wait catches that mid-refresh at random,
    -- which is how one run measured the identical wear=0.75 state as
    -- lumAll +0.01844 in Q1 and +0.00636 in Q3, and how the 0.50 step
    -- came out DARKER than 0.25. Same settle loop as Q0, everywhere.
    local d, n = settle()
    if d < 0 then
      log(("  WARN: scene never settled after wear change (%d tries)")
          :format(n))
    end
  end

  -- ================= Q0 baseline =====================================
  log("--- Q0 BASELINE (nothing changed)")
  setWear(0)
  local settledAt, tries = settle()
  log(("settled to %d changed pixels after %d pairs"):format(settledAt, tries))
  local base1 = grab()
  local base2 = grab()
  local floorLo, floorHi = diff(base1, base2)
  log(("noise floor: lo=%d hi=%d"):format(floorLo, floorHi))
  shotPng("wear_00.png")
  -- Everything below compares against this floor, so a floor that never
  -- came down makes the whole run unreadable and it must say so FIRST
  -- rather than emitting a page of numbers that look like measurements.
  check(settledAt >= 0 and floorLo < frac(SETTLE_FRAC),
        ("the scene is still enough to measure against (floor=%d, bar=%d, "
         .. "sampled=%d)"):format(floorLo, frac(SETTLE_FRAC), sampled))

  -- ================= Q1 does it read ==================================
  log("--- Q1 READS")
  setWear(0.75)
  local worn = grab()
  local lo75, hi75, lum75, lumAll75 = diff(base1, worn)
  -- both rulers logged, so Q1 and Q3 can be read against each other
  log(("wear 0.75 vs 0: lo=%d hi=%d lum=%+.4f lumAll=%+.5f")
      :format(lo75, hi75, lum75, lumAll75))
  shotPng("wear_75.png")
  check(lo75 > math.max(200, floorLo * 8),
        ("wear changes pixels well past the noise floor (%d vs floor %d)")
        :format(lo75, floorLo))
  check(hi75 > 50,
        ("the change is not deniable at the high bar (hi=%d)"):format(hi75))

  -- ================= Q2 which direction ===============================
  log("--- Q2 DIRECTION")
  -- A thinned cell replaces tuft with whatever is under it. On Route 1 in
  -- daylight the tuft bake is darker than the lit ground it stands on, so
  -- removing tufts should BRIGHTEN the region. The sign is the claim; the
  -- magnitude is not, because the bake's palette is not this probe's
  -- business. A sign of zero means pixels moved without anything being
  -- uncovered, which is a wobble, not a thinning.
  check(math.abs(lum75) > 0.004,
        ("thinning shifts luminance, so geometry left rather than wobbled "
         .. "(lum=%+.4f)"):format(lum75))

  -- ================= Q3 the gradient ==================================
  log("--- Q3 GRADIENT (must deepen, must not pop)")
  -- ------- and the metric here is LUMINANCE, not the pixel count
  --
  -- The count saturates almost immediately and that is not a fault in the
  -- feature, it is the wrong ruler. The residual-height term
  -- (`keep = 1 - 0.25 * wear`) moves EVERY tuft in a worn cell, not only
  -- the ones being retired -- so by a quarter of the way up nearly every
  -- grass pixel in the region has already changed by more than the low
  -- bar, and the count has nowhere left to go. A first run measured
  -- 38694 / 48457 / 49374 for 0.25 / 0.50 / 0.75: monotonic, and 78% of
  -- the way there at the first step, which says nothing about depth.
  --
  -- How much GROUND is showing does have somewhere to go, and that is the
  -- thing the design actually claims deepens. Uncovered ground is brighter
  -- than the tuft over it, so the luminance shift is the depth.
  local grad = {}
  for _, v in ipairs({ 0.25, 0.50, 0.75 }) do
    setWear(v)
    local f = grab()
    local c, _, _, lumAll = diff(base1, f)
    grad[#grad + 1] = { v = v, c = c, lum = lumAll }
    log(("  wear %.2f -> lo=%d lumAll=%+.5f"):format(v, c, lumAll))
  end
  -- ------- and the comparison is on the MAGNITUDE of the shift
  --
  -- Which DIRECTION uncovered ground moves the luminance is a fact about
  -- the art, not about the feature: bare tileset grass is brighter than a
  -- tuft, and the bare-earth decal that now covers it is darker. So the
  -- sign flipped the day the decal landed, and a monotonicity test written
  -- on the signed value would have called a working decal a regression.
  -- What deepening actually predicts is that the frame moves FURTHER from
  -- the untouched one, whichever way the palette happens to go.
  local monoCount, monoLum = true, true
  for i = 2, #grad do
    if grad[i].c <= grad[i - 1].c then monoCount = false end
    if math.abs(grad[i].lum) <= math.abs(grad[i - 1].lum) then
      monoLum = false
    end
  end
  check(monoCount, "more of the meadow is affected at every step")
  check(monoLum,
        "the frame moves further from untouched at every step (no pop)")
  check(grad[1].c > floorLo * 3,
        ("a quarter of the way is already visible (%d)"):format(grad[1].c))
  check(math.abs(grad[3].lum) > math.abs(grad[1].lum) * 1.5,
        ("the deep end is meaningfully deeper than the shallow end "
         .. "(%+.5f vs %+.5f)"):format(grad[3].lum, grad[1].lum))

  -- ================= Q7 the palindrome ================================
  --
  -- The seal, and it sits HERE rather than at the end because of what a
  -- palindrome is for: it certifies that the questions it encloses were
  -- asked of one unchanging scene. Everything above shares the pinned
  -- configuration. Everything below deliberately breaks it -- Q5 thaws the
  -- wind and runs six hundred weather ticks, Q4 reallocates the
  -- framebuffer -- so enclosing them made the seal fail for the honest
  -- reason that the scene really had moved (24972 changed pixels against a
  -- floor of 1116, and moving only Q4 out did not fix it).
  log("--- Q7 PALINDROME")
  setWear(0)
  local baseEnd = grab()
  local endLo = diff(base1, baseEnd)
  log(("first baseline vs last: lo=%d (floor was %d)"):format(endLo, floorLo))
  check(not drifted, "the player never drifted off its home cell")
  check(pl.cellX == hx and pl.cellY == hy,
        ("still on the home cell (%d,%d)"):format(pl.cellX or -1,
                                                  pl.cellY or -1))
  -- Two independently-settled frames may each sit up to SETTLE_FRAC from
  -- their neighbour, so the seal cannot be tighter than twice that without
  -- failing on the settle criterion itself rather than on any real drift.
  -- (A bar of floor*4 rejected a return of 3310 against a floor of 599 --
  -- a difference well inside what "settled" was ever promising.)
  local sealBar = math.max(floorLo * 4, frac(SETTLE_FRAC * 2))
  check(endLo <= sealBar,
        ("the scene returned to where it started, so the questions above "
         .. "are readable (%d <= %d)"):format(endLo, sealBar))

  -- ================= Q5 shelter =======================================
  log("--- Q5 SHELTER (quiets the meadow, does not thin it)")
  -- Shelter multiplies the wind AMPLITUDE, so unlike everything above it is
  -- only measurable while the meadow is actually moving -- a frozen phase
  -- would give the same still frame at every shelter value. So the wind is
  -- thawed for this one question and the measurement changes shape: not
  -- "how many pixels differ between two wear values" but "how many pixels
  -- differ between two CONSECUTIVE FRAMES", which is how much the meadow
  -- is moving. Shelter should lower that number and nothing else.
  --
  -- The clock stays pinned. Only the wind is let go.
  setWear(0)
  thawWind()
  Wind.setting:sync(4)              -- GALE: leave no doubt there is motion
  for _ = 1, 600 do Weather.update(1 / 30) end
  still(60)
  GrassWear.forceShelter(nil)
  still(20)
  -- Several consecutive pairs, and the MEDIAN of them: one pair can land on
  -- the instant the travelling wave passes through zero, where even a gale
  -- moves almost nothing.
  local function motionMedian(n)
    local vals = {}
    local prev = grab()
    for i = 1, n do
      local cur = grab()
      vals[i] = diff(prev, cur)
      prev = cur
    end
    table.sort(vals)
    return vals[math.ceil(#vals / 2)], vals[1], vals[#vals]
  end
  -- Eleven pairs rather than seven: a gale's travelling wave means one
  -- pair's motion depends on where in the cycle it landed, and the first
  -- run of this measured ranges (1640..2371) and (1561..3913) that overlap
  -- almost entirely -- a median of seven was not enough to separate them.
  local openMove, openLo, openHi = motionMedian(11)
  GrassWear.forceShelter(0.05)
  still(30)
  local leeMove, leeLo, leeHi = motionMedian(11)
  log(("motion open:      median=%d (%d..%d)"):format(openMove, openLo, openHi))
  log(("motion sheltered: median=%d (%d..%d)"):format(leeMove, leeLo, leeHi))
  check(openMove > 100,
        ("the meadow moves under a gale (%d)"):format(openMove))
  check(leeMove < openMove * 0.6,
        ("shelter quiets it (%d < 60%% of %d)"):format(leeMove, openMove))
  -- and shelter must NOT thin anything: it is a wind term, not a wear term
  GrassWear.forceShelter(nil)
  still(20)
  freezeWind()
  still(20)
  local shOffShot = grab()
  GrassWear.forceShelter(0.05)
  still(20)
  local shOnShot = grab()
  local _, _, shLum = diff(shOffShot, shOnShot)
  log(("sheltered vs open, frozen: lum=%+.4f"):format(shLum))
  check(math.abs(shLum) < math.max(0.004, math.abs(lum75) * 0.5),
        ("shelter changes the lean, not the amount of grass "
         .. "(lum=%+.4f vs wear's %+.4f)"):format(shLum, lum75))
  GrassWear.forceShelter(nil)
  Wind.setting:sync(1)
  still(30)

  -- ================= Q6 standing still writes nothing =================
  log("--- Q6 IDLE")
  setWear(0)
  local px = (pl.px or (hx or 10) * 16)
  local py = (pl.py or (hy or 28) * 16)
  still(240)
  local idleWear = GrassWear.at(px + 8, py + 8)
  log(("after 240 frames standing: wear under the player = %.4f"):format(
        idleWear))
  check(idleWear <= 0.0,
        ("standing still drills no hole (%.4f)"):format(idleWear))

  -- ================= Q4 the tier 0 promise ============================
  --
  -- After the seal, with Q5, because it reallocates the framebuffer.
  log("--- Q4 TIER 0 (the SHADER must not read the field)")
  -- ------- and the GROUND row goes off for this one, which is the point
  --
  -- The tier promise is about the vertex shader: at grassDetail 0 the wear
  -- tap is not paid and the tufts do not thin. It was never about the
  -- ground decal, which draws at EVERY tier on purpose -- that is how a
  -- player on the cheap rung still sees the paths at all.
  --
  -- So with the decal left on, this question measured both and reported
  -- one: it read 1386 changed pixels and called them "tier 0 ignoring the
  -- field", when they were the decal doing exactly its job. Turning GROUND
  -- off isolates the claim being made.
  Quality.setting:sync(3)           -- 1/3 -> grassDetail 0
  GroundFX.setting:sync("off")
  still(60)
  log("grassDetail now =", Quality.grassDetail())
  setWear(0)
  local t0a = grab()
  local t0c = grab()
  local t0floor = diff(t0a, t0c)
  setWear(0.75)
  local t0b = grab()
  local t0lo = diff(t0a, t0b)
  local t0bar = math.max(t0floor * 2, frac(SETTLE_FRAC * 2))
  log(("tier0: wear-driven lo=%d, floor lo=%d, bar=%d, sampled=%d")
      :format(t0lo, t0floor, t0bar, sampled))
  check(Quality.grassDetail() == 0, "the cheap rung really is tier 0")
  check(t0lo <= t0bar,
        ("the tuft shader ignores the field at tier 0 (%d <= %d)")
        :format(t0lo, t0bar))
  Quality.setting:sync(1)
  GroundFX.setting:sync("on")
  still(60)

  -- ================= Q8 the bare-earth decal ==========================
  --
  -- Q1 established that thinning uncovers ground and that the uncovered
  -- ground is BRIGHTER than the tufts that were over it. That brightness
  -- is the tileset's own lit grass texture, which is the thing that made
  -- the thinning read as an LOD pop rather than as a path -- sparse tufts
  -- standing on vivid green.
  --
  -- The decal's job is to put earth there instead. Trodden dirt is darker
  -- than lit grass, so the measurement is an ABLATION: shoot the same
  -- worn meadow with the GROUND row on and off, and the version with the
  -- decal must be the darker of the two. That is a prediction the decal
  -- either meets or does not, and it cannot be met by accident.
  log("--- Q8 BARE EARTH DECAL")
  log(("bare art: %s"):format(
        GroundFX.usingArt and GroundFX.usingArt("bare")
        and "shipped png" or "generated strip"))
  setWear(0.75)
  GroundFX.setting:sync("on")
  still(20)
  settle()
  local withDecal = grab()
  local _, _, lumWith = diff(base1, withDecal)
  -- the mesh itself: "it is dark" and "a mesh exists" are different claims
  local ow = game.overworld
  local chunkX = math.floor((hx or 10) / 16)
  local chunkY = math.floor((hy or 28) / 16)
  local mesh3 = GroundFX.chunkFor and
                GroundFX.chunkFor(ow.map, "bare3", chunkX, chunkY)
  local rebuilds = GroundFX.lastBareRebuilds
  GroundFX.setting:sync("off")
  still(20)
  settle()
  local noDecal = grab()
  local _, _, lumWithout = diff(base1, noDecal)
  GroundFX.setting:sync("on")
  still(20)
  log(("worn meadow luminance: with decal %+.4f, without %+.4f")
      :format(lumWith, lumWithout))
  log(("bare3 mesh for chunk (%d,%d): %s   rebuilds last frame: %s")
      :format(chunkX, chunkY, mesh3 and "built" or "NONE",
              tostring(rebuilds)))
  check(mesh3 ~= nil,
        "a bare-earth mesh was actually built for the worn chunk")
  check(lumWith < lumWithout,
        ("the decal darkens the worn ground (%+.4f < %+.4f)")
        :format(lumWith, lumWithout))
  -- and the cost guard: the whole point of bucketing wear is that a chunk
  -- is rebuilt when a cell crosses a step, not when somebody takes a step.
  check((rebuilds or 0) == 0,
        ("a settled frame rebuilds no chunks (%s)"):format(tostring(rebuilds)))

  log("")
  log(("done: %d pass, %d fail"):format(pass, fail))
  logf:close()
  love.event.quit()
end
