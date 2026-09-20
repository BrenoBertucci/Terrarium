-- Probe: the grass pass's AAA round -- each new piece switched off and on
-- against a pinned scene, so every verdict is one knob's worth of pixels.
--
--   Q1  WIND OFF keeps the feet   sway 0 used to draw the meadow as terrain
--   Q2  the comb                  drag lays the meadow downwind, not both ways
--   Q3  gust patches              the squall front is patches, not a band
--   Q4  sheen                     a bent blade reads lighter
--   Q5  low-sun glow              tips burn at dusk, and ONLY at dusk
--   Q6  per-column flutter        the tuft stops fluttering as one card
--
-- Every GPU question is an A/B of one knob (Voxel3D.SWAY_FLOOR, GRASS_TUNE,
-- GRASS_FX) with the wind FROZEN (constant amount and phase), the clock
-- pinned, shadows and cloud shade off, and nothing else in the world
-- allowed to move -- and it is judged against a control pair taken the same
-- way, because a scene that is "still" still shimmers.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/grass_aaa_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/grass_aaa_probe.log", "w"))
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
  local function quit()
    log(("done: %d pass, %d fail"):format(pass, fail))
    logf:close(); love.event.quit()
  end

  local frames = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); frames = frames + 1
    if frames > 900 then log("FAIL: no overworld"); return quit() end
  end
  frames = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); frames = frames + 11
    if frames > 1500 then log("FAIL: never reached free roam"); break end
  end
  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then log("FAIL: TERRARIUM not loaded"); return quit() end
  log("version:", exports.TERRARIUM.version)

  local Wind = lib.require("Wind")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Quality = lib.require("Quality")
  local Voxel3D = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")
  for _, name in ipairs({ "WildRoamers", "AmbientLife", "CityLife",
                          "Routines", "Vfx", "CloudShade", "GroundFX" }) do
    local ok, M = pcall(lib.require, name)
    if ok and M and M.setting then M.setting:sync("off") end
  end
  DayNight.setting:sync("day")
  Weather.setting:sync("off")
  Pipelines.setLevel("terrarium_voxel", 4)
  Quality.setting:sync(1)                 -- FULL -> grassDetail 2
  Quality.shadowSetting:sync("off")
  -- ------- no wild encounters while standing in tall grass
  --
  -- The first run of this probe was wiped out by one: the player drifts
  -- for a while after setMap (a known engine habit, see the anchor below),
  -- a step in tall grass rolled a battle, and every A/B after Q1 compared
  -- a black transition frame with a white one. The engine asks main.lua's
  -- encounter.roll hook, which asks WildRoamers.covers -- the same seam the
  -- ROAM row uses to take the blind roll off -- so answering yes there
  -- takes the dice away without touching the encounter code.
  local WildRoamers = lib.require("WildRoamers")
  WildRoamers.covers = function() return true end
  -- ------- and nothing airborne moving on the real clock
  --
  -- A gale is exactly when the streaks, seeds and falling leaves are out,
  -- and they run on real time, not on the pinned wind: the second run's
  -- controls read 3.6k and 21k changed pixels with nothing switched. None
  -- of them has an OFF row (PFX bottoms out at LOW), so their tick is
  -- stubbed -- what is already in the air hangs where it is, and holds
  -- still between the A and the B.
  for _, name in ipairs({ "WindFX", "VegFX", "LeafFallFX", "LeafLitter" }) do
    local ok, M = pcall(lib.require, name)
    if ok and type(M) == "table" and M.update then
      M.update = function() end
    end
  end
  local okSky, Sky = pcall(lib.require, "Sky")
  if okSky and Sky and Sky.cloudSetting then Sky.cloudSetting:sync("off") end

  -- ------- stand in the BIGGEST meadow on offer, found by asking the maps
  --
  -- Scored by how much tall grass lies in a window mostly NORTH of the
  -- cell, because the camera looks north: that is the grass in frame.
  -- Route 1's patches are four cells long, which puts a meadow the size of
  -- a rug in the middle of a frame of trees.
  local gmap, gx, gy, gscore = nil, nil, nil, -1
  for _, id in ipairs({ "ROUTE_22", "ROUTE_2", "ROUTE_12", "ROUTE_25",
                        "ROUTE_1" }) do
    local ok = pcall(game.overworld.setMap, game.overworld, id, 10, 10, "down")
    wait(60)
    local map = game.overworld.map
    if ok and map and map.id == id and map.isGrassCell then
      local W, H = map.width or 40, map.height or 40
      for cy = 3, H - 3 do
        for cx = 3, W - 3 do
          if map:isGrassCell(cx, cy) then
            local s = 0
            for dy = -5, 1 do
              for dx = -4, 4 do
                if map:inBounds(cx + dx, cy + dy)
                   and map:isGrassCell(cx + dx, cy + dy) then s = s + 1 end
              end
            end
            if s > gscore then gmap, gx, gy, gscore = id, cx, cy, s end
          end
        end
      end
      log(("meadow scan %s: best so far %s (%s,%s) score %d"):format(id,
            tostring(gmap), tostring(gx), tostring(gy), gscore))
    else
      log("meadow scan: could not load " .. id)
    end
  end
  -- ------- and STAY there: the player walks on their own for a while
  -- after setMap (cells 20 -> 22 -> 25 -> 24 -> 29 -> 23 in one measured
  -- run), so the wait is a condition -- the same cell for 45 frames in a
  -- row, inputs held false -- and a landing outside the grass is retried.
  local DIRS0 = { "up", "down", "left", "right" }
  local function anchored()
    local p = game.overworld.player
    local stay, cx, cy = 0, p.cellX, p.cellY
    for _ = 1, 900 do
      for i = 1, #DIRS0 do game.input.state[DIRS0[i]] = false end
      coroutine.yield()
      p = game.overworld.player
      if p.cellX == cx and p.cellY == cy then stay = stay + 1
      else stay, cx, cy = 0, p.cellX, p.cellY end
      if stay >= 45 then return true end
    end
    return false
  end
  for attempt = 1, 4 do
    if gx then game.overworld:setMap(gmap, gx, gy, "down") end
    local ok = anchored()
    local p = game.overworld.player
    log(("anchor attempt %d: settled=%s cell=(%d,%d)"):format(attempt,
          tostring(ok), p.cellX or -1, p.cellY or -1))
    if ok and game.overworld.map:isGrassCell(p.cellX, p.cellY) then break end
  end
  for _ = 1, 300 do Weather.update(1 / 30) end

  -- ------- the wind FROZEN (a constant amount and phase), never OFF
  local realAmount, realPhase, realLoad = Wind.amount, Wind.phase, Wind.load
  local PIN = { amount = 4.0, phase = 7.0, gust = 0.5 }
  Wind.amount = function() return PIN.amount end
  Wind.phase = function() return PIN.phase end
  Wind.load = function() return 0, 0, PIN.gust end
  local PIN_CLOCK = DayNight.clock

  local pl = game.overworld.player
  local hx, hy = pl.cellX, pl.cellY
  log(("standing at (%d,%d) grass=%s"):format(hx or -1, hy or -1,
        tostring(game.overworld.map:isGrassCell(hx, hy))))
  check(game.overworld.map:isGrassCell(hx, hy),
        "the player stands in tall grass (Q1 needs a foot in it)")

  local DIRS = { "up", "down", "left", "right" }
  local drifted = false
  local function tick()
    for i = 1, #DIRS do game.input.state[DIRS[i]] = false end
    DayNight.clock = PIN_CLOCK
    coroutine.yield()
    if pl.cellX ~= hx or pl.cellY ~= hy then drifted = true end
  end
  local function still(n) for _ = 1, n do tick() end end
  still(30)

  local function grab()
    local out, pending = nil, true
    love.graphics.captureScreenshot(function(d) out = d; pending = false end)
    tick()
    local guard = 0
    while pending and guard < 240 do tick(); guard = guard + 1 end
    return out
  end
  local function save(img, name)
    if not img then return end
    local f = io.open(OUT .. "/" .. name, "wb")
    if f then f:write(img:encode("png"):getString()); f:close() end
  end

  -- changed pixels (max channel delta > 0.02) and the signed luminance
  -- shift over ALL sampled pixels -- a fraction-of-sample world, see
  -- grass_wear_shot's note on why absolute counts do not travel
  -- Only the MEADOW's part of the frame: the middle band around the
  -- player, not the sky (its clouds run on the real clock) and not the
  -- tilt-shift's blurred rims.
  --
  -- Three answers: changed samples, the signed mean luminance shift, and
  -- HOT BLOCKS -- 16x16 screen blocks more than a quarter changed. The
  -- engine keeps a scattered per-frame shimmer of 1-4k changed samples in
  -- a scene that is standing still (dither parity; see the underpass
  -- note), which swamps a raw count for anything local like one dent in
  -- the grass. Shimmer is scattered, a dent is DENSE: blocks separate them.
  local sampled = 0
  local function diff(a, b)
    if not (a and b) then return -1, 0, 0 end
    local w = math.min(a:getWidth(), b:getWidth())
    local h = math.min(a:getHeight(), b:getHeight())
    local n, lum, all, hot = 0, 0, 0, 0
    local x0, x1 = math.floor(w * 0.20), math.floor(w * 0.80) - 16
    local y0, y1 = math.floor(h * 0.30), math.floor(h * 0.80) - 16
    for by = y0, y1, 16 do
      for bx = x0, x1, 16 do
        local bn, ball = 0, 0
        for y = by, by + 15, 2 do
          for x = bx, bx + 15, 2 do
            local r1, g1, b1 = a:getPixel(x, y)
            local r2, g2, b2 = b:getPixel(x, y)
            ball = ball + 1
            if math.max(math.abs(r1 - r2), math.abs(g1 - g2),
                        math.abs(b1 - b2)) > 0.02 then
              bn = bn + 1
            end
            lum = lum + (0.299 * (r2 - r1) + 0.587 * (g2 - g1)
                         + 0.114 * (b2 - b1))
          end
        end
        n, all = n + bn, all + ball
        if bn * 4 > ball then hot = hot + 1 end
      end
    end
    sampled = all
    return n, lum / math.max(all, 1), hot
  end
  local function frac(f) return math.max(1, math.floor(sampled * f)) end

  local function settle()
    local prev = grab()
    for i = 1, 40 do
      local cur = grab()
      local d = diff(prev, cur)
      if sampled > 0 and d < frac(0.01) then return cur, d, i end
      prev = cur
    end
    return prev, -1, 40
  end

  -- One knob, INTERLEAVED and quick: B, then A, then B again, a couple of
  -- frames apart, after one settle. The first cut settled A and B
  -- separately, ~80 frames apart, and the camera was still easing in from
  -- the setMap the whole time -- every edge in the frame moved, the check
  -- passed on the camera, and it would have passed with the knob unwired.
  -- Every knob here is a per-frame uniform, so it bites on the next frame.
  -- The verdict is A->B2 against B1->B2, which spans MORE time than it.
  --
  -- Three A/B pairs, alternating, a grab every 2 frames. EVEN spacing on
  -- purpose: the engine's shimmer flips with frame parity, and an odd
  -- spacing lands every A on one parity and every B on the other -- the
  -- knob then "changes" what parity changes. The effect is the mean of the
  -- three A->B diffs; the control the mean of the A->A and B->B ones, which
  -- span the same frames with no knob moving.
  local function ab(label, setA, setB, nameA, nameB)
    setB()
    local _, _, tries = settle()
    local As, Bs = {}, {}
    for i = 1, 3 do
      setA(); still(1); As[i] = grab()
      setB(); still(1); Bs[i] = grab()
    end
    local n, lum, hot, fl, flum, fhot = 0, 0, 0, 0, 0, 0
    for i = 1, 3 do
      local a, b, c = diff(As[i], Bs[i])
      n, lum, hot = n + a / 3, lum + b / 3, hot + c / 3
    end
    for i = 1, 2 do
      local a, b, c = diff(Bs[i], Bs[i + 1])
      local d, e, f = diff(As[i], As[i + 1])
      fl, flum, fhot = fl + (a + d) / 4, flum + (math.abs(b) + math.abs(e)) / 4,
                       fhot + (c + f) / 4
    end
    log(("%s: A->B changed=%d (%.2f%%) lum=%+.4f hot=%d | control=%d |lum|=%.4f hot=%d | settle=%d")
          :format(label, n, 100 * n / math.max(sampled, 1), lum, hot,
                  fl, flum, fhot, tries))
    if nameA then save(As[3], nameA) end
    if nameB then save(Bs[3], nameB) end
    return n, lum, fl, hot, fhot, flum
  end

  -- NOT `table.unpack and table.unpack(t) or unpack(t)`: an and/or
  -- truncates to one value, and TUNE would hold only the first knob.
  local unpackf = table.unpack or unpack
  local TUNE = { unpackf(Voxel3D.GRASS_TUNE) }
  local FX = { unpackf(Voxel3D.GRASS_FX) }
  local function tune(i, v) Voxel3D.GRASS_TUNE[i] = v end
  local function restore()
    for i = 1, 4 do Voxel3D.GRASS_TUNE[i] = TUNE[i] end
    for i = 1, #FX do Voxel3D.GRASS_FX[i] = FX[i] end
    Voxel3D.SWAY_FLOOR = 0.001
  end

  -- ================= Q1 WIND OFF keeps the feet =======================
  log("--- Q1 WIND OFF keeps the feet")
  -- The player's own idle pocket is hidden behind the player's own card,
  -- so the crush under test is a SPLAT (the dent a battle hit leaves) two
  -- cells north of them, in open meadow in front of the camera. It fades
  -- over Grass3D.TRAIL_TTL, so it is laid AFTER the settle and the three
  -- grabs are a few frames apart.
  PIN.amount, PIN.gust = 0, 0             -- what the OFF row hands over
  -- the frame's brightness is still landing right after the set-up (one
  -- run's control moved 5.9% in luminance here): wait it out
  still(150)
  local Grass3D = lib.require("Grass3D")
  local n1, _, f1, hot1, fhot1 = ab("wind off + splat, floor 0 -> 0.001",
    function() Voxel3D.SWAY_FLOOR = 0 end,
    function()
      Voxel3D.SWAY_FLOOR = 0.001
      -- re-laid each time: a splat fades on its own clock (and not
      -- clearTracks, which would restart the player's own pocket spring)
      Grass3D.splat(pl.px + 8, pl.py + 8 - 32, 24, 1.4)
    end,
    "q1_windoff_before.png", "q1_windoff_after.png")
  check(n1 > 2 * f1 and hot1 > 2 * fhot1 + 4,
        "under WIND OFF a crush still lays the grass down (a dense dent)")
  restore()

  -- ================= Q2 the comb (numbers, then pixels) ================
  log("--- Q2 the comb")
  -- The shader's own formula, run on the CPU: this is the SPEC for the
  -- look, not a test of the GPU. Tip = hN 0.8 -> bend 0.64.
  local function comb(amp)
    local k, mx = TUNE[1], math.max(TUNE[2], 0.001)
    local x = k * amp * amp / mx
    local c = mx * x / (1 + x)
    return c, amp * (1 - 0.5 * c / mx)
  end
  local BEND_TIP = 0.64
  local cCalm = comb(0.6)
  local cGale, oGale = comb(4.0)
  local cPeak, oPeak = comb(7.3)
  log(("tip comb: calm %.2f px, gale %.2f px (osc %.2f), peak %.2f px (osc %.2f)")
        :format(cCalm * BEND_TIP, cGale * BEND_TIP, oGale * BEND_TIP,
                cPeak * BEND_TIP, oPeak * BEND_TIP))
  check(cCalm * BEND_TIP < 0.2, "a calm day is barely combed (< 0.2 px)")
  check(cGale * BEND_TIP > 2.0, "a gale combs the tips over (> 2 px)")
  check(cPeak <= TUNE[2] + 1e-6, "the comb saturates at its ceiling")
  -- the deepest a gale tip swings back: comb + osc * (the wave's minimum)
  check((cGale - 1.38 * oGale) * BEND_TIP > -1.0,
        "in a gale the meadow barely swings upwind of upright (> -1 px)")
  check((cPeak - 1.38 * oPeak) * BEND_TIP > -0.5,
        "and at a gust's peak it does not swing upwind at all")

  PIN.amount, PIN.gust = 4.0, 0.5
  local n2, _, f2 = ab("gale, comb 0 -> on",
    function() tune(1, 0) end, function() tune(1, TUNE[1]) end,
    "q2_gale_nocomb.png", "q2_gale_comb.png")
  check(n2 > math.max(3 * f2, frac(0.01)),
        "the comb moves the meadow (the whole field, not a patch)")
  restore()

  -- ================= Q3 gust patches (CPU field) =======================
  log("--- Q3 gust patches")
  -- Along the old band's crest (perpendicular to the ripple's bearing)
  -- a single wave is constant; patches must vary along it.
  local fx, fz = Wind.FREQ[1], Wind.FREQ[2]
  local fl = math.sqrt(fx * fx + fz * fz)
  local px, pz = -fz / fl, fx / fl
  local sum, sq, lo, hi = 0, 0, 9, -9
  for i = 0, 63 do
    local v = Wind.patchAt(300 + px * i * 32, 300 + pz * i * 32, 11.0)
    sum, sq = sum + v, sq + v * v
    if v < lo then lo = v end
    if v > hi then hi = v end
  end
  local mean = sum / 64
  local sd = math.sqrt(math.max(0, sq / 64 - mean * mean))
  log(("along the crest: sd=%.3f range %.2f..%.2f"):format(sd, lo, hi))
  check(sd > 0.2, "the front varies ALONG its crest: patches, not a band")
  check(lo >= -1.0001 and hi <= 1.0001, "and stays inside -1..1")
  local tsum, tsq = 0, 0
  for i = 0, 63 do
    local v = Wind.patchAt(500, 700, i * 0.9)
    tsum, tsq = tsum + v, tsq + v * v
  end
  local tsd = math.sqrt(math.max(0, tsq / 64 - (tsum / 64) ^ 2))
  check(tsd > 0.3, "and it travels: one spot sees the patches pass")
  -- the air the rain rides reads the same field
  Wind.amount, Wind.phase, Wind.load = realAmount, realPhase, realLoad
  Wind.setting:sync(4)
  for _ = 1, 200 do Weather.update(1 / 30) end
  local flo, fhi = 99, -99
  for i = 0, 99 do
    local _, _, band = Wind.flowAt(i * 37, i * 23)
    if band < flo then flo = band end
    if band > fhi then fhi = band end
  end
  log(("flowAt band under GALE: %.2f .. %.2f"):format(flo, fhi))
  check(fhi > flo + 0.3 and flo >= 0, "the air's band still breathes and never reverses")
  Wind.setting:sync(1)
  Wind.amount = function() return PIN.amount end
  Wind.phase = function() return PIN.phase end
  Wind.load = function() return 0, 0, PIN.gust end

  -- ================= Q4 sheen ==========================================
  log("--- Q4 sheen")
  local _, lum4, _, _, _, flum4 = ab("gale, sheen 0 -> on",
    function() tune(3, 0) end, function() tune(3, TUNE[3]) end,
    "q4_gale_nosheen.png", "q4_gale_sheen.png")
  -- a luminance shift spread thin over every tip: judged by the mean, not
  -- by a count of pixels past a threshold most tips do not cross
  check(lum4 > math.max(5 * math.abs(flum4), 0.001),
        "a combed meadow reads LIGHTER: its blades show the lit side")
  -- and the band of light the gust makes: the same frozen gale half a
  -- ripple later is a different pattern of light, not the same one
  save((settle()), "look_gale_phase0.png")
  PIN.phase = PIN.phase + math.pi
  save((settle()), "look_gale_phase180.png")
  PIN.phase = 7.0
  restore()

  -- ================= Q5 low-sun glow ===================================
  log("--- Q5 glow")
  PIN.amount, PIN.gust = 1.2, 0.2
  -- the frame's brightness drifts for a while after the wind drops from a
  -- gale (one run's control moved 4% in luminance): let it land first
  still(150)
  local _, lum5d, _, hot5d, fhot5d, flum5d = ab("noon, glow 0 -> on",
    function() tune(4, 0) end, function() tune(4, TUNE[4]) end)
  check(math.abs(lum5d) <= math.max(3 * math.abs(flum5d), 0.0002)
        and hot5d <= fhot5d + 2,
        "at noon the glow knob does nothing (it is gated on the hour)")
  DayNight.setting:sync("dusk")
  still(20)
  PIN_CLOCK = DayNight.clock
  local _, lum5, _, _, _, flum5 = ab("dusk, glow 0 -> on",
    function() tune(4, 0) end, function() tune(4, TUNE[4]) end,
    "q5_dusk_noglow.png", "q5_dusk_glow.png")
  check(lum5 > math.max(5 * math.abs(flum5), 0.0005),
        "at dusk the tips take the glow (the meadow brightens)")
  DayNight.setting:sync("day")
  still(20)
  PIN_CLOCK = DayNight.clock
  restore()

  -- ================= Q6 per-column flutter =============================
  log("--- Q6 per-column flutter")
  PIN.amount, PIN.gust = 4.0, 0.5
  local n6, _, f6 = ab("gale, columns 0 -> 1",
    function() Voxel3D.GRASS_FX[1] = 0 end,
    function() Voxel3D.GRASS_FX[1] = 1 end)
  check(n6 > math.max(2 * f6, frac(0.001)),
        "each pixel column flutters on its own phase (tier 2)")
  restore()

  -- ================= Q11 depth, clumps, base ===========================
  log("--- Q11 depth, clumps, base")
  PIN.amount, PIN.gust = 1.2, 0.2
  still(150)
  local _, rootLum, _, _, _, rootControlLum = ab("roots, shade 0 -> on",
    function() Voxel3D.GRASS_FX[3] = 0 end,
    function() Voxel3D.GRASS_FX[3] = FX[3] end,
    "q11_roots_off.png", "q11_roots_on.png")
  check(rootLum < -math.max(5 * rootControlLum, 0.0005),
        "the meadow darkens where its roots crowd together")
  local clumpN, clumpLum, clumpControl = ab("clumps, variation 0 -> on",
    function() Voxel3D.GRASS_FX[4] = 0 end,
    function() Voxel3D.GRASS_FX[4] = FX[4] end,
    "q11_clumps_off.png", "q11_clumps_on.png")
  check(clumpN > math.max(3 * clumpControl, frac(0.01))
        and math.abs(clumpLum) < 0.004,
        "clumps vary the meadow without shifting its brightness")
  local ChunkMesher = lib.require("ChunkMesher")
  local baseShade = ChunkMesher.GRASS_BASE_SHADE
  ChunkMesher.GRASS_BASE_SHADE = 1.0
  ChunkMesher.invalidate()
  still(240)
  local baseA = settle()
  ChunkMesher.GRASS_BASE_SHADE = baseShade
  ChunkMesher.invalidate()
  still(240)
  local baseB = settle()
  local _, baseLum = diff(baseA, baseB)
  log(("base, shade 1 -> %.2f: lum=%+.4f"):format(baseShade, baseLum))
  check(baseLum < -0.0005,
        "the ground under tall grass darkens with the meadow")
  save(baseB, "q11_base_shade.png")
  restore()

  -- ================= Q7 the path stays (the LAID field) ===============
  log("--- Q7 laid path")
  local GrassWear = lib.require("GrassWear")
  local okCM, ChunkMesher = pcall(lib.require, "ChunkMesher")
  if okCM and ChunkMesher and ChunkMesher.grass then
    local okV, m = pcall(ChunkMesher.grass, game.overworld.map)
    if okV and m and m.getVertexCount then
      log("grass mesh vertices on this map:", m:getVertexCount())
    end
  end
  PIN.amount, PIN.gust = 0.8, 0.1
  -- walk NORTH out of the anchor through the meadow: the camera looks
  -- north, so the path is left between the player and the lens
  local x0, y0 = pl.cellX, pl.cellY
  for _ = 1, 70 do
    game.input.state.up = true
    DayNight.clock = PIN_CLOCK
    coroutine.yield()
  end
  game.input.state.up = false
  anchored()                    -- let the last step land before anchoring
  hx, hy = pl.cellX, pl.cellY
  log(("walked (%d,%d) -> (%d,%d); laid cells=%d"):format(x0, y0, hx, hy,
        GrassWear.laidCount()))
  check(y0 - hy >= 2, "the player walked at least two cells through the grass")
  check(GrassWear.laidCount() >= 2, "walking lays the cells walked through")
  still(60)
  local realLaid = GrassWear.laidState
  local function laidAB(label, shot)
    return ab(label,
      function() GrassWear.laidState = function() return nil end end,
      function() GrassWear.laidState = realLaid end,
      nil, shot)
  end
  local n7, _, f7, h7, fh7 = laidAB("path ~3 s on, laid off -> on",
                                   "q7_path_3s.png")
  check(h7 > 2 * fh7 + 4, "seconds after, the path is still parted")
  GrassWear.advance(30)
  local n7b, _, f7b, h7b, fh7b = laidAB("path 33 s on, laid off -> on",
                                       "q7_path_33s.png")
  check(h7b > 2 * fh7b + 4, "half a minute later the path is still there")
  GrassWear.advance(80)
  still(30)
  -- Asked of the cell the walk STARTED in: the cells the player and the
  -- Yellow follower stand in are pressed every frame and stay down.
  local startLaid = GrassWear.laidAt(x0 * 16 + 8, y0 * 16 + 8)
  log(("after 113 s: laid cells=%d, start cell %.3f"):format(
        GrassWear.laidCount(), startLaid))
  check(startLaid == 0, "and after LAID_TTL the path has stood back up")
  GrassWear.laidState = realLaid
  restore()

  -- ================= Q8 dew, and the path that knocks it off ==========
  log("--- Q8 dew")
  check(Wind.dew() < 0.05, "no dew at noon")
  DayNight.setting:sync("dawn")
  still(20)
  PIN_CLOCK = DayNight.clock
  local dawnDew = Wind.dew()
  log(("dew at dawn: %.2f"):format(dawnDew))
  check(dawnDew > 0.8, "a meadow at dawn wears its dew")
  still(150)                    -- the frame's brightness lands on the hour
  local _, lum8, _, _, _, flum8 = ab("dawn, dew 0 -> on",
    function() Voxel3D.GRASS_FX[2] = 0 end,
    function() Voxel3D.GRASS_FX[2] = 1 end,
    nil, "q8_dawn_dew.png")
  check(lum8 > math.max(5 * math.abs(flum8), 0.0005),
        "dew lifts the tips toward silver")
  -- walk back SOUTH through the meadow: the path is left up the frame
  local RainOnFX = lib.require("RainOnFX")
  local drips0 = RainOnFX.drips or 0
  local sx, sy = pl.cellX, pl.cellY
  local soaked = 0
  for _ = 1, 70 do
    game.input.state.down = true
    DayNight.clock = PIN_CLOCK
    coroutine.yield()
    local w = RainOnFX.wetOf(pl)
    if w > soaked then soaked = w end
  end
  game.input.state.down = false
  anchored()
  hx, hy = pl.cellX, pl.cellY
  log(("dawn walk (%d,%d) -> (%d,%d)"):format(sx, sy, hx, hy))
  local mid = math.floor((sy + hy) / 2)
  check(GrassWear.laidKnocked(sx * 16 + 8, mid * 16 + 8),
        "a path walked at dawn has its dew knocked off")
  still(30)
  save((settle()), "q8_dawn_path.png")

  -- ================= Q9 wet legs =======================================
  log("--- Q9 wet legs")
  still(90)
  log(("peak wetness while wading: %.2f, drips shed: %d"):format(
        soaked, (RainOnFX.drips or 0) - drips0))
  check(soaked > 0.3, "wading through dew soaks the legs")
  check((RainOnFX.drips or 0) > drips0, "and they drip")
  DayNight.setting:sync("day")
  still(20)
  PIN_CLOCK = DayNight.clock

  -- ================= Q10 the meadow's sound ============================
  -- Amount frozen, PHASE LIVE: the only thing left moving the wind bed is
  -- the gust patch crossing the listener.
  log("--- Q10 sound")
  local Amb = lib.require("AmbientSound")
  Amb.setting:sync("on")
  Wind.phase = realPhase
  PIN.amount, PIN.gust = 4.0, 0.5
  local g0 = Amb.gustGrains or 0
  still(120)
  local lo, hi = 9, -9
  for _ = 1, 900 do
    tick()
    local l = Amb.bedLevel("wind")
    if l < lo then lo = l end
    if l > hi then hi = l end
  end
  local grains = (Amb.gustGrains or 0) - g0
  log(("wind bed under a steady gale: %.2f .. %.2f; gust grains: %d")
        :format(lo, hi, grains))
  check(hi - lo > 0.06, "the wind bed swells and falls as the gust patches pass")
  check(grains > 0, "the meadow itself rustles on the crest of a gust")
  PIN.amount = 0
  local g1 = Amb.gustGrains or 0
  still(300)
  check((Amb.gustGrains or 0) == g1, "and not a grain with the wind off")
  Wind.phase = function() return PIN.phase end

  -- ================= the look, for a person to judge ==================
  PIN.amount, PIN.gust = 0.6, 0.0
  save((settle()), "look_calm.png")
  PIN.amount, PIN.gust = 3.4, 0.4
  save((settle()), "look_shower_air.png")
  PIN.amount, PIN.gust = 5.5, 1.0
  save((settle()), "look_gale_peak.png")

  log(("player drifted during the run: %s"):format(tostring(drifted)))
  check(not drifted, "the player never moved (every A/B saw one scene)")
  Wind.amount, Wind.phase, Wind.load = realAmount, realPhase, realLoad
  quit()
end
