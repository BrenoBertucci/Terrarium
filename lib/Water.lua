-- Voxel world mode: the water surface.
--
-- Water in this mode has been a flat quad with a scrolling texture: the
-- tileset's own animated tile, recessed two world pixels so the shoreline
-- shows a lip. That is the 2D game's water standing on its side -- the
-- picture moves and the surface does not.
--
-- Out here the surface is geometry, so it can move for real:
--
--   SWELL     Y = f(XZ) only -- watertight unindexed mesh, two crossing
--             trains + body-size field + crest steepening under energy.
--   SIZE      how big the water under a point actually is, measured off the
--             map rather than guessed from a sine (lib/WaterBody.lua). Both
--             the amplitude and the WAVELENGTH ride it, so a fountain gets
--             short shallow ripples and a sea gets a long swell, out of the
--             same two trains and the same row setting.
--   SPARKLE   analytic normal (two cosines), cel-quantized glint rings.
--   BODY      rain / snow / freeze / wind / thermal inertia / chop energy
--             that lags the weather, so the surface has mass.
--
-- Still a four-colour diorama: hard steps, checker dither, three varyings
-- (vWater, vWave, vSwellH), identity only `y < -1`. No mesh attribute, no
-- second RT, no normal map, no soft airbrush.
--
-- SURFACE ART (optional drop-in): put a PNG at `assets/water/water.png` and
-- lakes / rivers sample it in world XZ instead of the tileset's water tile.
-- Same contract as assets/ground/: replace the file and it is used; delete
-- it and the tileset art comes back. No constant, no rebuild.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
-- How big the water under a point is (lib/WaterBody.lua). Required here
-- rather than pushed in, and safe to: WaterBody knows about maps and cells
-- and nothing about waves, so there is no way back to this file.
local WaterBody = V.require("WaterBody")

local Water = {}

Water.setting = ModSetting.new("swell", "WATER",
                               { 0.8, 1.4, 0 },
                               { "CALM", "SWELL", "FLAT" })

-- World pixels one full cycle of water.png covers. 64 = four map cells.
Water.ART_SCALE = 64

-- How far the surface art is allowed to take over the albedo, 0..1.
--
-- This was 1.0 and not a knob -- the mix factor was `clamp(vWaterSurf)`,
-- which is exactly 1 on every water face -- so the PNG did not decorate the
-- water, it BECAME the water. The shipped sheet is a cel caustic whose white
-- shapes are large and round, tiled every 64 world pixels, and at the sizes
-- this camera draws a pond at those shapes read as clouds lying in the lake.
--
-- A third is enough to keep the sheet's detail and not enough for any one of
-- its shapes to become a silhouette the eye names.
Water.ART_MIX = 0.35
Water.ASSET_DIR = "assets/water/"
Water.ASSET_FILE = "water.png"

-- ------- THE SPECTRUM: three trains of FIXED length, and nothing else
--
-- The size of a body of water used to shorten the wave by scaling the wave
-- VECTOR: `a = (k . x) * bf(x) - phase`. That reads like the obvious thing to
-- do and it is not, because the gradient of that argument is
--
--   grad a = bf * k  +  (k . x) * grad bf
--
-- and the second term is a product of WORLD POSITION -- unbounded, thousands
-- of pixels across a route -- with the shoreline ramp, which is nonzero at
-- every bank in the game. Measured at the bank of a test lake
-- (tests/water_disperse_glint_offline.lua): the local wavenumber is 1.14x the
-- one the wave should have at the world origin, 7.80x a thousand pixels out
-- and 28.03x four thousand out. Past about a thousand pixels the perturbation
-- is larger than the wave it perturbs, which is not a shorter wave -- it is
-- noise with a period, drawn along every shoreline far from the origin.
-- Watertightness never caught it: Y = f(XZ) stays perfectly continuous while
-- the pattern underneath it comes apart.
--
-- So no wave vector is a function of position any more. There are three
-- trains, their lengths are constants, and WHAT THE SIZE OF THE WATER MOVES
-- IS HOW LOUD EACH ONE IS. A weight multiplies a sine; it does not live
-- inside one. grad a is exactly k, everywhere, forever.
--
-- LONG and MID are the old pair at the open-water end of the old ramp
-- (WAVE_A0 * SIZE_FREQ_BIG and WAVE_B0 * SIZE_FREQ_BIG), so open water comes
-- out of this bit-identical in space to what it was. SHORT is new and is what
-- a puddle actually gets: a third direction at 2.3x the wavenumber, which is
-- the short end the old ramp was reaching for.
Water.WAVE_L0 = { 0.05040, 0.02736 }   -- long swell   |k| 0.05735
Water.WAVE_M0 = { -0.02232, 0.04176 }  -- mid cross    |k| 0.04735
Water.WAVE_S0 = { 0.10763, -0.14825 }  -- short chop   |k| 0.18319

-- Live vectors, stretched as one by wind/energy/freeze in refreshLive.
-- WAVE_A / WAVE_B are the long and mid trains under their old names, because
-- lib/RayFX.lua sends them straight through to its own screen-space ripple
-- normal and has never known about body size at all.
Water.WAVE_A = { Water.WAVE_L0[1], Water.WAVE_L0[2] }
Water.WAVE_B = { Water.WAVE_M0[1], Water.WAVE_M0[2] }
Water.WAVE_C = { Water.WAVE_S0[1], Water.WAVE_S0[2] }

-- How loud each train is at the two ends of the size ramp. The long train is
-- the one that dies on a puddle and the short one is the one that dies at
-- sea; the mid train never dies, and that is the point of it -- a single
-- surviving train is corduroy, and the smallest puddle has to keep at least
-- two directions crossing or it stops reading as water.
--
-- At size 1 these are 0.55 / 0.45 / 0, which is exactly the old open-water
-- mix. The end of the ramp nobody could see is the end that changed.
Water.MIX_LONG = 0.55
Water.MIX_MID = 0.45
Water.MIX_SHORT = 0.55
-- The floors are DELIBERATELY ASYMMETRIC. A puddle keeps a tenth of the long
-- swell -- a long wave at a tenth of its height is a slow tilt, it costs
-- nothing and it is the second crossing direction the smallest water needs.
-- The open sea keeps NONE of the short chop: at |k| 0.183 that train is a
-- fifth of a display pixel per cycle at this camera, which under a nearest
-- upscale is not detail, it is the frame-to-frame churn the shimmer probe was
-- built to hunt. So the sea comes out of this bit-identical to what it was.
Water.MIX_FLOOR_LONG = 0.10
Water.MIX_FLOOR_SHORT = 0.0
Water.MIX_KNEE = 1.40    -- how fast the crossfade runs across the size ramp

-- DISPERSION. 1 = a wave's tempo follows its own length, 0 = the old single
-- clock. Kept as a knob because it is the one change in this file that moves
-- every body of water at once and an ablation is the only honest way to rank
-- it (tests/water_physics_probe.lua flips it).
--
-- The wave VECTOR is scaled by bodyFreq (see below) and the phase never was,
-- so the crest of a short wave travelled at `rate / (k * bf)` -- inversely
-- with bf. A puddle, whose bf is 2.3, crawled at less than half the speed of
-- the open sea, which is why small water read as an ocean filmed in slow
-- motion rather than as a puddle. Deep-water gravity waves disperse as
-- `omega = sqrt(g * k)`, so the speed falls as `1 / sqrt(k)` and not as
-- `1 / k`: multiply the phase by sqrt(bf) and the ratio is right.
--
-- ADVECTION IS DEDUCTED FROM THIS DELIBERATELY -- it is scaled by nothing.
-- The advection term grows without bound with world position (0.045 * energy
-- * dot(xz, current) is ~84 rad four thousand pixels out), so multiplying it
-- by a quantity that varies across the map would put tens of radians between
-- one bank and the other and tear the surface apart. The current drags the
-- whole ocean at one speed; only the wave's own tempo knows how long it is.
--
-- IT IS SAFE ONLY BECAUSE THE WAVE VECTORS ARE CONSTANTS. The first attempt
-- at this scaled the phase by sqrt(bf(x)) with bf still a field, and that put
-- `phase * grad sqrt(bf)` into the gradient -- a spatially varying quantity
-- multiplied by a clock that does not stop growing. Measured at a lake bank:
-- 1.01x the wave's own wavenumber at twelve seconds and 42.9x at one hour.
-- With fixed vectors each train's tempo is a CONSTANT SCALAR, the same number
-- everywhere on the map, and it contributes nothing to any gradient at all.
--
-- The ratios are taken from the REST vectors and never from the live ones.
-- refreshLive stretches all three together with wind and energy, and a tempo
-- ratio that moved with it would make `time * rate` jump by `time * d rate`
-- every time the weather turned -- an hour into a session that is a large
-- number of radians. The stretch is common to all three, so leaving the
-- ratios on the rest lengths costs nothing and removes the failure.
Water.DISPERSE = 1.0

-- Tempo of each train relative to the LONG one: omega ~ sqrt(k), so a short
-- wave oscillates faster while its crest travels slower -- which is the whole
-- of the effect and the reason a pond does not look like a filmed ocean.
-- Reference is the long train rather than the mid so open water keeps the
-- tempo it was tuned at (see Water.RATE and the shimmer measurement).
Water.RATE_LONG = 1.0
Water.RATE_MID = 0.90867    -- sqrt(0.04735 / 0.05735)
Water.RATE_SHORT = 1.78730  -- sqrt(0.18319 / 0.05735)

-- Base phase rate (rad/s) before wet/freeze/wind/energy scales in phase().
-- R0 water_shimmer_probe (VERMILION, CALM, weather off, RES 1/2): continuous
-- background ~5.9% of the water mask was almost all swell+paint (tile/glint/
-- SSR each <5%). Lower base rate slows hard step() crawl under nearest
-- upscale; chop still accelerates via energy (phase() * (1+0.20*e)).
-- Was 0.9. With 0.55 + calm-gated mid foam: bg ~2.2–2.7% of water mask
-- (≈55% less than R0 5.9%). Palindrome at low counts is noisier; C_flat
-- still clean (0 continuous + tile impulses only).
Water.RATE = 0.55
Water.SPARKLE = 0.55
-- The specular window, as a FRACTION of the slope this water can actually
-- reach -- not as an absolute one, which is what it was and why the glint
-- did not exist.
--
-- The shader measures the window from the flat plane's own alignment with
-- the sun (`flat + LO`, `flat + HI`), so both numbers are a DEVIATION. But
-- the deviation a swell can produce is `amp * |grad h| * |sunRay.xz|`, and
-- amp is the row's swell times how much of it this body carries -- it is not
-- a constant, it is the smallest number in the whole system. Measured at the
-- default rung (CALM 0.8, sun at 44.6 deg): the largest deviation anywhere on
-- the water was 0.0269 against a LO of 0.020, so `s` reached 0.029 of 1.0 and
-- `floor(s * 4 + 0.5)` was 0 on every fragment of every lake. The rings were
-- not rare, they were unreachable; the effect had never once been visible
-- outside dawn and dusk, where a low sun stretches |sunRay.xz| enough to
-- limp into the first ring.
--
-- As fractions the window rides the amplitude by construction: 0.34 means
-- "the top two thirds of the slope this particular water can make", which is
-- a crest on an ocean and a crest on a puddle, and both of them glint.
Water.GLINT_LO = 0.34
Water.GLINT_HI = 1.00

-- Live |k| of each train, long / mid / short. Recomputed in refreshLive
-- because the vectors are stretched there. The glint window needs it: the
-- largest |grad h| at a point is the weighted sum of these -- every cosine
-- allowed to peak at once, which is the bound and not the average -- and the
-- weights are what the size of the water moves, so the ceiling is per-point
-- and the shader works it out from the same three numbers.
Water.WAVE_K = { 0.05735, 0.04735, 0.18319 }

-- Fragment-only phase snap (radians). Geometry always uses continuous phase.
-- Tried 0.20: converted crawl into ~32% water-mask IMPULSES and made the
-- shimmer palindrome unreadable (A vs A2 drift 69%). Left at 0.
Water.PAINT_PHASE_STEP = 0

-- World-XZ cell size (px) for fragment height re-eval / band / noise paint.
-- Geometry continuous; paint snaps to this grid (sky floor idiom).
-- Tried liquid 4.0: palindrome drift 22% (bursty cell flips). Back to 2 / 5.5
-- matching the pre-knob hardcodes that gave a readable R0.
Water.PAINT_WCELL = 2.0
Water.PAINT_WCELL_ICE = 5.5

-- Climate inputs (pushed by Weather -- never require Weather back).
Water.wet = 0
Water.snow = 0

-- Amplitude physics
Water.CHOP = 0.70
Water.WIND_CHOP = 0.48
Water.WIND_FREQ = 0.58
Water.WET_RATE = 0.38
Water.STEEP = 0.22          -- crest sharpening at full energy (Gerstner-ish Y)

-- Freeze / mass
Water.freeze = 0
Water.freezeVel = 0         -- thermal inertia (df/dt lag)
Water.ICE_LIFT = 0.75
Water.FREEZE_RATE = 0.10
Water.MELT_RATE = 0.26
Water.WALK_FREEZE = 0.66
Water.THERMAL_INERTIA = 0.55  -- 0 = snap to target, 1 = very laggy

-- Freeze/thaw stand-up animation when the player is already ON the water
-- (surfing or standing on ice). event = { kind="lock"|"thaw", t, dur }.
-- Walking onto ice from land is allowed ONLY if the party can Surf (same
-- Soul Badge + SURF mon gate as mounting Surf) -- ice is not a free path.
Water.standEvent = nil
Water._wasSolidIce = false

-- Chop energy: lags wet+wind so the pond has momentum (not a switch).
Water.energy = 0
Water.ENERGY_ATTACK = 1.8   -- per second toward high chop
Water.ENERGY_RELEASE = 0.55 -- per second decay when weather calms

-- Live shader feeds
Water.CREST = 0
Water.SNOW_VEIL = 0
Water.ICE_SPARKLE = 0
Water.stepJitter = 0
Water.BODY = 1
Water.STEEP_NOW = 0         -- live steep sent to shader / used in heightField
Water.CURRENT = { 0.94, 0.34 }  -- unit XZ drift (from Wind.DIR)
Water.THERM = 0.5           -- 0 cold .. 1 warm (DayNight elevation proxy)

-- Spatial body-size field: the STAND-IN, kept as the fallback. A sine in
-- world space that varies with where you are and not with what you are in
-- (see the note at the top of lib/WaterBody.lua). Used when there is no
-- baked field -- headless, a probe, a bake that threw -- so those paths get
-- exactly the behaviour they had before the field existed.
Water.BODY_KX = 0.0039
Water.BODY_KZ = 0.0045

-- ------- and what the real field does with a wave
--
-- Two numbers move with the size of the body, and moving only one of them
-- was the first version of this and it was wrong. Amplitude alone gives a
-- puddle a full-length ocean swell at a tenth of the height, which does not
-- read as a calm puddle -- it reads as the whole pond tilting. Length is
-- what says "small": a pond carries short ripples, a sea carries long ones,
-- and the height follows from that rather than the other way round.
--
-- FREQ is a scale on the wave VECTOR, so bigger is shorter. The stand-in's
-- range was 0.55 .. 1.25 around a mean of 0.90 and meant nothing; these are
-- picked so the mean lands near the old one and the ends actually separate:
-- a fountain gets ripples about a third the length of the open sea's swell.
Water.SIZE_FREQ_SMALL = 2.30   -- the smallest puddle
Water.SIZE_FREQ_BIG = 0.72     -- fully open water
-- The share of the row's amplitude the smallest puddle keeps. Not zero: a
-- puddle with a dead-flat surface loses its glint, its bands and its foam
-- in one go, and a still pond is a different thing from a small one.
Water.SIZE_AMP_MIN = 0.16
-- Curve on the amplitude ramp. Above 1 holds small water calm for longer
-- before it starts growing, which is the shape a fetch-limited sea actually
-- has -- it takes a lot of open water before the waves are worth anything.
Water.SIZE_AMP_GAMMA = 1.35

-- Advection: wind drags phase along CURRENT (group velocity feel).
Water.ADVECT = 0.045

local function clamp01(n)
  n = tonumber(n) or 0
  if n < 0 then return 0 end
  if n > 1 then return 1 end
  return n
end

local function wetness()
  return clamp01(Water.wet)
end

local function snowness()
  return clamp01(Water.snow)
end

function Water.windNorm()
  local ok, Wind = pcall(V.require, "Wind")
  if not ok or not Wind or not Wind.amount then return 0 end
  local n = tonumber(Wind.amount()) or 0
  if n < 0 then n = 0 end
  if n > 4 then n = 4 end
  return n / 4
end

function Water.windDir()
  local ok, Wind = pcall(V.require, "Wind")
  if ok and Wind and Wind.DIR then
    local x, z = tonumber(Wind.DIR[1]) or 0.94, tonumber(Wind.DIR[2]) or 0.34
    local len = math.sqrt(x * x + z * z)
    if len > 1e-4 then return x / len, z / len end
  end
  return Water.CURRENT[1], Water.CURRENT[2]
end

function Water.qualityMul()
  local ok, Quality = pcall(V.require, "Quality")
  if not ok or not Quality or not Quality.scale then return 1 end
  if Quality.scale() >= 4 then return 0.75 end
  return 1
end

-- 1 open water .. 0 the smallest puddle, at a world XZ. 1 whenever there is
-- no baked field, which is what puts the fallback path back on the old
-- single-amplitude ocean rather than on a world of puddles.
function Water.sizeAt(wx, wz)
  if not WaterBody.on() then return 1 end
  return WaterBody.sizeAt(wx, wz)
end

-- Body-size frequency scale at world XZ -- a multiplier on the wave vector,
-- so BIGGER IS SHORTER.
--
-- NO LONGER IN THE HEIGHT FIELD. This is what used to scale the wave vector,
-- and scaling a wave vector by a field is the defect the spectrum at the top
-- of this file exists to remove -- see the note there for the measurement.
-- It is kept because it is still the honest answer to "how short is the water
-- under this point", which is a question the size probes ask and one that no
-- longer has a single wave to read it off. Nothing in the render path calls
-- it, and nothing new should.
function Water.bodyFreq(wx, wz)
  if not WaterBody.on() then
    wx = tonumber(wx) or 0
    wz = tonumber(wz) or 0
    local n = math.sin(wx * Water.BODY_KX) * math.cos(wz * Water.BODY_KZ)
    return 0.90 + 0.35 * n
  end
  local s = WaterBody.sizeAt(wx, wz)
  return Water.SIZE_FREQ_SMALL
       + (Water.SIZE_FREQ_BIG - Water.SIZE_FREQ_SMALL) * s
end

-- The share of the row's swell this point is allowed, 0..1.
--
-- A function of XZ ALONE, like the height it scales, which is what keeps
-- the surface watertight: two quads meeting at a corner are damped by the
-- same amount and the mesh never opens a seam.
--
-- The gradient of the damped height is amp*grad(h) + h*grad(amp), and only
-- the first term is carried into the analytic normal (here and in the
-- shader). The second is worth about a tenth of the first at the steepest
-- part of the ramp -- the field runs 0 to 1 over ten cells -- and buying it
-- back costs two more field taps per water VERTEX and per water FRAGMENT.
-- On the machine this mod is tuned for that is not a trade worth making for
-- a tenth of a normal on the two cells nearest a bank, where breaking foam
-- is painted over the shading anyway.
function Water.bodyAmp(wx, wz)
  if not WaterBody.on() then return 1 end
  local s = WaterBody.sizeAt(wx, wz)
  local lo = Water.SIZE_AMP_MIN
  return lo + (1 - lo) * (s ^ Water.SIZE_AMP_GAMMA)
end

-- How loud each of the three trains is here: long, mid, short, summing to 1.
--
-- THIS is what the size of the water moves now, and the reason it is a weight
-- on a sine rather than a scale on a wave vector is the whole of the note at
-- the top of this file: a weight contributes `h * grad w` to the gradient,
-- which is bounded by the ramp itself, while a vector scale contributes
-- `(k . x) * grad bf`, which is bounded by nothing at all.
--
-- Shader twin: waterShape() in Voxel3D's SHADER, which must return these same
-- three numbers from the same field tap or the paint stops agreeing with the
-- mesh it is painted on.
function Water.bodyWeights(wx, wz)
  local s = 1
  if WaterBody.on() then s = WaterBody.sizeAt(wx, wz) end
  local knee = Water.MIX_KNEE
  local hi = clamp01(knee * s - (knee - 1))   -- open-water fade-in
  local lo = clamp01(1 - knee * s)            -- puddle fade-in
  local fL, fS = Water.MIX_FLOOR_LONG, Water.MIX_FLOOR_SHORT
  local wL = Water.MIX_LONG * (fL + (1 - fL) * hi)
  local wM = Water.MIX_MID
  local wS = Water.MIX_SHORT * (fS + (1 - fS) * lo)
  -- Normalised so the row's swell means the same height at every size. How
  -- much a small body is allowed to move is bodyAmp's job and only its job;
  -- if the partition were left un-normalised a mid-sized lake would come out
  -- a fifth calmer than either end of the ramp for no stated reason.
  local sum = wL + wM + wS
  if sum <= 1e-6 then return 0, 1, 0 end
  return wL / sum, wM / sum, wS / sum
end

-- Largest |grad h| available here before crest steepening: every cosine
-- allowed to peak at once. The bound, not the average -- see Water.GLINT_LO
-- for what happens to a specular window sized against anything smaller.
function Water.gradMaxAt(wx, wz)
  local wL, wM, wS = Water.bodyWeights(wx, wz)
  local k = Water.WAVE_K
  return wL * k[1] + wM * k[2] + wS * k[3]
end

-- Thermal proxy from sun elevation: high noon melts, night freezes.
function Water.thermNow()
  local ok, DayNight = pcall(V.require, "DayNight")
  if not (ok and DayNight and DayNight.time and DayNight.bodyAt) then
    return Water.THERM
  end
  local _, el, moon = DayNight.bodyAt(DayNight.time())
  el = tonumber(el) or 45
  if moon then return 0.12 end
  -- 0 at horizon, ~1 at high sun
  local t = el / 50
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  return t
end

function Water.refreshLive()
  local w = Water.windNorm()
  local f = clamp01(Water.freeze)
  local e = clamp01(Water.energy)
  local scale = 1 + w * Water.WIND_FREQ + e * 0.22 - f * 0.65
  if scale < 0.28 then scale = 0.28 end
  if scale > 1.95 then scale = 1.95 end
  -- One stretch for all three trains. Common to the whole map, so it moves
  -- no gradient and it leaves the tempo ratios (RATE_LONG/MID/SHORT) alone.
  Water.WAVE_A[1] = Water.WAVE_L0[1] * scale
  Water.WAVE_A[2] = Water.WAVE_L0[2] * scale
  Water.WAVE_B[1] = Water.WAVE_M0[1] * scale
  Water.WAVE_B[2] = Water.WAVE_M0[2] * scale
  Water.WAVE_C[1] = Water.WAVE_S0[1] * scale
  Water.WAVE_C[2] = Water.WAVE_S0[2] * scale
  Water.BODY = scale
  Water.STEEP_NOW = Water.STEEP * e * (1 - f)

  Water.WAVE_K[1] = math.sqrt(Water.WAVE_A[1] ^ 2 + Water.WAVE_A[2] ^ 2)
  Water.WAVE_K[2] = math.sqrt(Water.WAVE_B[1] ^ 2 + Water.WAVE_B[2] ^ 2)
  Water.WAVE_K[3] = math.sqrt(Water.WAVE_C[1] ^ 2 + Water.WAVE_C[2] ^ 2)

  local dx, dz = Water.windDir()
  Water.CURRENT[1], Water.CURRENT[2] = dx, dz

  local q = Water.qualityMul()
  local crest = e * 0.55 + wetness() * 0.90 + w * 0.70 + wetness() * w * 0.40
  if f > 0.30 then crest = crest * (1 - f) end
  Water.CREST = clamp01(crest) * q
  Water.SNOW_VEIL = snowness() * (1 - f * 0.35) * q
  Water.ICE_SPARKLE = f * 0.60 * (1 - wetness() * 0.45) * q
  Water.THERM = Water.thermNow()
end

function Water.swell()
  Water.refreshLive()
  local ok, v = pcall(Water.setting.get, Water.setting)
  local n = (ok and tonumber(v)) or 0
  if n < 0 then n = 0 end
  if n > 4 then n = 4 end
  local f = clamp01(Water.freeze)
  local e = clamp01(Water.energy)
  if n > 0 then
    n = n + Water.CHOP * wetness()
    n = n + Water.WIND_CHOP * Water.windNorm() * (1 - f)
    n = n + 0.30 * e * (1 - f)                 -- stored chop energy
    n = n + 0.25 * wetness() * Water.windNorm() * (1 - f)
    local sn = snowness()
    if sn > 0 then n = n * (1 - 0.45 * sn * (1 - f)) end
  end
  n = n * (1 - f)
  return n
end

function Water.tileRoll()
  if clamp01(Water.freeze) > 0.05 then return false end
  return Water.swell() <= 0
end

function Water.sparkleNow()
  local f = clamp01(Water.freeze)
  -- energy scatters specular; rain kills it
  local scatter = 1 - clamp01(Water.energy) * 0.35
  return Water.SPARKLE * (1 - wetness()) * (1 - f * 0.92) * scatter
end

function Water.rain()
  return wetness()
end

function Water.iceLift()
  -- mass conservation feel: as freeze rises, free surface lifts a little
  return Water.ICE_LIFT * clamp01(Water.freeze)
end

-- Absolute time phase with advection along wind current + dual tempo:
-- gravity swell (base RATE) + capillary hitch from rain energy.
function Water.phase()
  local rate = Water.RATE
  local f = clamp01(Water.freeze)
  local e = clamp01(Water.energy)
  rate = rate * (1 - Water.WET_RATE * wetness())
  rate = rate * (1 - 0.93 * f)
  rate = rate * (1 + 0.32 * Water.windNorm() * (1 - f))
  rate = rate * (1 + 0.20 * e * (1 - f))       -- choppy water clocks faster
  if rate < 0.012 then rate = 0.012 end
  if love and love.timer and love.timer.getTime then
    return (love.timer.getTime() * rate) % (math.pi * 2048)
  end
  return 0
end

-- The wind's drag on the phase at a point, ALONE. Split out from phaseAt
-- because dispersion scales the wave's own tempo and must not touch this one
-- (see Water.DISPERSE): this term grows with world position without bound, so
-- anything that varies across the map cannot be allowed to multiply it.
function Water.advectAt(wx, wz)
  local e = clamp01(Water.energy) * (1 - clamp01(Water.freeze))
  local dx, dz = Water.CURRENT[1], Water.CURRENT[2]
  return Water.ADVECT * e * ((wx or 0) * dx + (wz or 0) * dz)
end

-- Advected phase sample at a point: base phase + wind drag on XZ. Kept for
-- callers that want the one number; the height field takes the two apart.
function Water.phaseAt(wx, wz)
  return Water.phase() + Water.advectAt(wx, wz)
end

-- ------- climate integration with thermal inertia + energy lag
function Water.step(dt)
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end

  local sn = snowness()
  local w = Water.windNorm()
  local therm = Water.thermNow()
  Water.THERM = therm

  -- freeze target from snow + cold therm + night
  local target = 0
  if sn > 0.04 then
    target = 0.38 + 0.62 * sn
  end
  if therm < 0.20 and (sn > 0.02 or Water.freeze > 0.06) then
    target = math.max(target, 0.55 + (0.20 - therm))
  end
  if therm < 0.12 and sn > 0.01 then
    target = math.max(target, 0.80)
  end
  if therm > 0.45 and sn < 0.08 then
    target = math.min(target, 0.15)
  end
  if therm > 0.62 and sn < 0.04 then
    target = 0
  end

  -- critically-damped-ish inertia toward target
  local f = clamp01(Water.freeze)
  local err = target - f
  local rate = err > 0
    and Water.FREEZE_RATE * (0.40 + 0.60 * sn)
    or  Water.MELT_RATE * (0.70 + 0.55 * therm)
  local inert = Water.THERMAL_INERTIA
  local vel = Water.freezeVel or 0
  vel = vel * (1 - (1 - inert) * 6 * dt) + err * rate * (1.4 - inert) * dt * 8
  if vel > 0.5 then vel = 0.5 elseif vel < -0.5 then vel = -0.5 end
  f = f + vel * dt
  if (err > 0 and f > target) or (err < 0 and f < target) then
    f = target
    vel = vel * 0.3
  end
  Water.freeze = clamp01(f)
  Water.freezeVel = vel

  -- chop energy lag (mass of the surface agitation)
  local wantE = clamp01(wetness() * 0.85 + w * 0.70 + wetness() * w * 0.45)
  wantE = wantE * (1 - clamp01(Water.freeze))
  local e = clamp01(Water.energy)
  if wantE > e then
    e = e + Water.ENERGY_ATTACK * (wantE - e) * dt
  else
    e = e - Water.ENERGY_RELEASE * (e - wantE) * dt
  end
  Water.energy = clamp01(e)

  -- Stand animation: lake freezes/thaws under a body already out there.
  -- Crossing the solid-ice threshold kicks a short hop + waterline blend
  -- so the mon rises onto the ice (or sinks back into a swim).
  local solid = Water.freeze >= Water.WALK_FREEZE
  if solid ~= Water._wasSolidIce then
    local onSurface, px, pz, p = Water._playerOnWaterSurface()
    if onSurface then
      if solid then
        Water.standEvent = { kind = "lock", t = 0, dur = 0.95 }
        Water.stepJitter = 1
        Water.noteFoot(px, pz)
      else
        Water.standEvent = { kind = "thaw", t = 0, dur = 0.75 }
        Water.stepJitter = 0.7
        -- Ice went liquid under a walker who is not surfing: keep them
        -- afloat if they still know Surf (same skill that let them on ice).
        if p and not p.surfing and Water.canUseSurf() then
          p.surfing = true
        end
      end
    end
    Water._wasSolidIce = solid
  end
  if Water.standEvent then
    local ev = Water.standEvent
    ev.t = (ev.t or 0) + dt
    if ev.t >= (ev.dur or 0.8) then
      Water.standEvent = nil
    end
  end

  if Water.stepJitter > 0 then
    Water.stepJitter = Water.stepJitter - dt * 6.5
    if Water.stepJitter < 0 then Water.stepJitter = 0 end
  end

  Water.refreshLive()
end

-- True when the party may use Surf (Soul Badge + a mon that knows SURF).
-- Same gate as mounting Surf from the shore -- ice walk reuses it so the
-- HM is still required, just not a free pass for a party without Surf.
function Water.canUseSurf()
  local ok, Game = pcall(require, "src.core.Game")
  if not ok or not Game or not Game.save then return false end
  local inv = Game.save.inventory
  if not inv or not inv.SOULBADGE then return false end
  local ow = Game.overworld
  if not ow then return false end
  if type(ow.partyKnows) == "function" then
    local pok, mon = pcall(ow.partyKnows, ow, "SURF")
    if pok and mon then return true end
  end
  -- Fallback: some builds only expose the field-move probe
  if type(ow.useSurfFieldMove) == "function" then
    local uok, res = pcall(ow.useSurfFieldMove, ow)
    if uok and res == "ok" then return true end
  end
  return false
end

-- Player is on a water cell (surfing, or standing on solid ice).
-- Returns onSurface, wx, wz, player.
function Water._playerOnWaterSurface()
  local ok, Game = pcall(require, "src.core.Game")
  if not ok or not Game or not Game.overworld then return false end
  local ow = Game.overworld
  local p = ow.player
  if not p then return false end
  local px = (p.px or ((p.cellX or 0) * 16)) + 8
  local pz = (p.py or ((p.cellY or 0) * 16)) + 8
  local onWaterCell = false
  if ow.map and ow.map.isWaterCell then
    local wok, water = pcall(ow.map.isWaterCell, ow.map, p.cellX, p.cellY)
    onWaterCell = wok and water
  end
  if not onWaterCell then return false end
  if p.surfing then return true, px, pz, p end
  if Water.walkableIce(px, pz) then return true, px, pz, p end
  return false
end

function Water._playerSurfingOnWater()
  local on, px, pz, p = Water._playerOnWaterSurface()
  if not on or not p or not p.surfing then return false end
  return true, px, pz
end

-- Multi-octave plate mask for partial freeze (leads of open water).
function Water.frozenAt(wx, wz)
  local f = clamp01(Water.freeze)
  if f <= 0 then return 0 end
  if f >= 0.999 then return 1 end
  local cx = math.floor((tonumber(wx) or 0) / 16)
  local cz = math.floor((tonumber(wz) or 0) / 16)
  local h1 = math.sin(cx * 12.9898 + cz * 78.233) * 43758.5453
  h1 = h1 - math.floor(h1)
  local h2 = math.sin(cx * 39.346 + cz * 11.135) * 23421.631
  h2 = h2 - math.floor(h2)
  local h3 = math.sin(cx * 7.1 + cz * 93.7) * 9123.17
  h3 = h3 - math.floor(h3)
  local h = h1 * 0.50 + h2 * 0.30 + h3 * 0.20
  local plate = f * 1.42 - 0.32 * h - 0.10
  return clamp01(plate)
end

function Water.walkableIce(wx, wz)
  return Water.frozenAt(wx, wz) >= Water.WALK_FREEZE
end

-- True when a character at world XZ is standing ON ice (not swimming).
-- Used to drop the waterline cut so the full sprite shows. Does NOT make
-- the cell freely walkable from land -- Surf is still how you get out there.
function Water.isStandingOnIce(wx, wz)
  return Water.walkableIce(wx, wz)
end

-- Waterline cut in pixels for a swimming body at (wx,wz).
-- Liquid: full swim cut. Ice: 0 (standing). During lock/thaw anim: blends
-- so the mon visibly rises out of / sinks into the surface.
function Water.waterlineCut(wx, wz, baseCut)
  baseCut = tonumber(baseCut) or 5
  local onIce = Water.isStandingOnIce(wx, wz)
  local ev = Water.standEvent
  if ev and ev.dur and ev.dur > 0 then
    local u = (ev.t or 0) / ev.dur
    if u < 0 then u = 0 elseif u > 1 then u = 1 end
    -- ease: smoothstep-ish without being a soft airbrush on the sprite
    local e = u * u * (3 - 2 * u)
    if ev.kind == "lock" then
      -- swimming cut -> standing (0)
      return math.floor(baseCut * (1 - e) + 0.5)
    elseif ev.kind == "thaw" then
      -- standing -> swimming cut
      return math.floor(baseCut * e + 0.5)
    end
  end
  if onIce then return 0 end
  return baseCut
end

-- Extra Y lift during freeze/thaw hop (world px). Sin pulse: up then settle.
function Water.standAnimLift(wx, wz)
  local ev = Water.standEvent
  if not ev or not ev.dur or ev.dur <= 0 then return 0 end
  local u = (ev.t or 0) / ev.dur
  if u < 0 or u > 1 then return 0 end
  local amp = ev.kind == "lock" and 2.6 or 1.4
  return math.sin(math.pi * u) * amp
end

local footCX, footCZ = nil, nil
function Water.noteFoot(wx, wz)
  local cx = math.floor((tonumber(wx) or 0) / 16)
  local cz = math.floor((tonumber(wz) or 0) / 16)
  if footCX == cx and footCZ == cz then return end
  footCX, footCZ = cx, cz
  if Water.walkableIce(wx, wz) then
    Water.stepJitter = 1
  end
end

Water.BASE = -2

-- Shared height field -- byte for byte with the vertex shader.
-- Two trains * bodyFreq * advection, then crest steepening under energy:
--   h' = h + steep * h * |h|   (sharpens crests, deepens troughs a touch)
--
-- `phase` is the wave's OWN clock and `adv` the current's drag, and they
-- arrive apart rather than pre-added because only the first disperses. Called
-- with the drag left out (adv nil) the field is the still-water one, which is
-- what a probe asking "what shape is this" wants.
function Water.heightField(wx, wz, phase, adv)
  wx = tonumber(wx) or 0
  wz = tonumber(wz) or 0
  adv = tonumber(adv) or 0
  local A, B, C = Water.WAVE_A, Water.WAVE_B, Water.WAVE_C
  local wL, wM, wS = Water.bodyWeights(wx, wz)
  -- Three constant tempos. Each is a scalar with the same value at every
  -- point on the map, so none of them appears in grad(a) -- which is what
  -- makes dispersion expressible here at all (see Water.DISPERSE).
  local d = Water.DISPERSE
  local pL = phase * (1 + (Water.RATE_LONG - 1) * d) + adv
  local pM = phase * (1 + (Water.RATE_MID - 1) * d) + adv
  local pS = phase * (1 + (Water.RATE_SHORT - 1) * d) + adv
  -- Opposite phase signs, so the long and short trains run against the mid
  -- one and the interference pattern travels rather than standing still.
  local aL = (wx * A[1] + wz * A[2]) - pL
  local aM = (wx * B[1] + wz * B[2]) + pM
  local aS = (wx * C[1] + wz * C[2]) - pS
  local h = math.sin(aL) * wL + math.sin(aM) * wM + math.sin(aS) * wS
  local steep = Water.STEEP_NOW or 0
  if steep > 0 then
    local ah = h < 0 and -h or h
    h = h + steep * h * ah
  end
  return h, aL, aM, aS
end

function Water.heightAt(wx, wz)
  local swell = Water.swell()
  if swell <= 0 then return 0 end
  local h = Water.heightField(wx, wz, Water.phase(), Water.advectAt(wx, wz))
  -- the row's amplitude is what the WEATHER asked for; bodyAmp is how much
  -- of it this particular piece of water is big enough to carry
  return swell * Water.bodyAmp(wx, wz) * h
end

function Water.surfaceAt(wx, wz)
  return Water.BASE + Water.heightAt(wx, wz) + Water.iceLift()
end

function Water.paints()
  if clamp01(Water.freeze) > 0.02 then return true end
  local ok, v = pcall(Water.setting.get, Water.setting)
  local n = (ok and tonumber(v)) or 0
  return n > 0
end

-- ------- optional surface art (assets/water/water.png)
--
-- Cached Image or false ("there is none"). nil = not tried yet. A 1x1 blank
-- is always available for the scene sampler so an unbound Image is never
-- sent (driver-dependent crash, same pattern as GlassMask.blank).

local artImage = nil   -- Image | false
local artBlank = nil   -- Image | false

local function loadArt()
  if artImage ~= nil then return artImage or nil end
  local okA, Assets = pcall(require, "src.render.Assets")
  if not okA or not Assets then
    artImage = false
    return nil
  end
  local path = V.path .. "/" .. Water.ASSET_DIR .. Water.ASSET_FILE
  local okE, exists = pcall(Assets.exists, path)
  if not (okE and exists) then
    artImage = false
    return nil
  end
  local ok, img = pcall(Assets.image, path)
  if not (ok and img) then
    artImage = false
    return nil
  end
  pcall(img.setFilter, img, "linear", "linear")
  pcall(img.setWrap, img, "repeat", "repeat")
  artImage = img
  return img
end

-- The shipped water surface texture, or nil when the file is missing.
function Water.art()
  return loadArt()
end

-- 1 when art() is a real file, 0 when the tileset tile should stay.
function Water.artOn()
  return loadArt() and 1 or 0
end

function Water.artScale()
  local n = tonumber(Water.ART_SCALE) or 64
  if n < 8 then n = 8 end
  return n
end

-- Always-bound stand-in for the scene shader's waterArt sampler.
function Water.artBlank()
  if artBlank == nil then
    local ok, img = pcall(function()
      local data = love.image.newImageData(1, 1)
      data:setPixel(0, 0, 0.1, 0.35, 0.75, 1)
      local i = love.graphics.newImage(data)
      pcall(i.setFilter, i, "nearest", "nearest")
      pcall(i.setWrap, i, "repeat", "repeat")
      return i
    end)
    artBlank = (ok and img) or false
  end
  return artBlank or nil
end

-- Hot reload / window resize: drop GPU objects so the next frame reloads
-- assets/water/water.png if it appeared or changed on disk.
function Water.dropGPU()
  if artImage and artImage ~= false and artImage.release then
    pcall(artImage.release, artImage)
  end
  artImage = nil
  if artBlank and artBlank ~= false and artBlank.release then
    pcall(artBlank.release, artBlank)
  end
  artBlank = nil
end

-- Walk-on-ice: frozen water cells count as ground IF the party can Surf
-- (Soul Badge + SURF). Liquid water stays blocked without mounting Surf.
-- So ice is walkable and immersive, but the HM is still required.
function Water.installWalk()
  local ok, Map = pcall(require, "src.world.Map")
  if not ok or not Map or Map._dsIceWalk then return end
  local walk = Map.isWalkableCell
  if type(walk) ~= "function" then return end
  function Map:isWalkableCell(cx, cy)
    if walk(self, cx, cy) then return true end
    if type(self.isWaterCell) == "function" then
      local wok, water = pcall(self.isWaterCell, self, cx, cy)
      if wok and water and Water.canUseSurf() then
        local wx, wz = (cx or 0) * 16 + 8, (cy or 0) * 16 + 8
        if Water.walkableIce(wx, wz) then return true end
      end
    end
    return false
  end
  Map._dsIceWalk = true
end

return Water
