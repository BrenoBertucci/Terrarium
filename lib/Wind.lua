-- Voxel world mode: wind.
--
-- The grass in this mode is GEOMETRY -- Structures builds a per-pixel tuft
-- template and ChunkMesher stamps it across every cell the engine calls
-- tall grass. That is why nothing done to the tileset's animation data can
-- make it move: a tile animation rewrites ART, and out here the art has
-- already been turned into shape. Rolling the atlas slot slides a texture
-- across prisms that do not themselves go anywhere.
--
-- So move the shape. The scene's vertex shader displaces each grass vertex
-- along the wind, by an amount that grows with how high up the tuft it
-- sits -- so the base stays planted in the ground and the tip gives. That
-- is a bend rather than a slide, which is the whole difference between
-- grass in wind and a rug being pulled.
--
-- ------- why this can do what a tile animation cannot
--
-- A tile animation is one picture, shared by every cell drawing that tile.
-- Every tuft on a route therefore moves in perfect unison, which reads as
-- machinery -- and there is no way around it, because there is only one
-- tile.
--
-- A vertex shader knows WHERE each vertex is. Taking the wave's phase from
-- the vertex's own world position makes the gust TRAVEL: it arrives at the
-- near edge of a meadow, crosses it, and leaves. Nothing in this file is
-- clever; it is just the thing that becomes possible once the grass is
-- geometry, and it is the reason to do it here instead of there.
--
-- ------- the height it bends about
--
-- Structures builds a tuft's template at y = 0 and ChunkMesher offsets only
-- X and Z into the world (buildGrass: `{ q[1][1] + wx, q[1][2], q[1][3] +
-- wz }` -- the middle component is untouched). So a grass vertex's own y IS
-- its height above the base of the tuft it belongs to, and the bend factor
-- falls straight out of it with nothing to look up and no vertex attribute
-- to add.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local DayNight = V.require("DayNight")

local Wind = {}

-- The row is a PLAYER PREFERENCE on top of natural wind, not a manual
-- weather switch:
--   AUTO    hands the row itself to the climate. BREEZE and GALE are two
--           fixed windows onto the same drive, and a player who wants the
--           storm to actually feel like a storm ends up walking to the menu
--           every time the sky changes -- which is the row doing the
--           climate's job by hand. AUTO spans BOTH windows on one
--           continuous curve: near-still on a calm night, breeze by day,
--           and it reaches gale on its own under a front. Default.
--   BREEZE  living outdoor air -- strength and bearing follow climate
--           (showers, snow fronts, hour, season), but inside a fixed band.
--   GALE    same climate, amplified (stormy coast feel).
--   OFF     silence -- accessibility / screenshots / quiet sessions.
--
-- Stored values are numeric and UNCHANGED for the three old rows (2/4/0),
-- so a save from before AUTO existed still reads back as what it was.
Wind.setting = ModSetting.new("wind", "WIND",
                              { 1, 2, 4, 0 },
                              { "AUTO", "BREEZE", "GALE", "OFF" })

-- How tall a tuft is taken to be, for the bend. Over-estimating only makes
-- the lean gentler, so this errs high on purpose.
Wind.TUFT = 16

-- Flowers are shorter and stiffer than grass, and they are also the one
-- thing in a meadow a player looks straight at, so they take a share of
-- the reach rather than all of it.
Wind.FLOWER_SHARE = 0.55

-- Radians per second. Slow: a gust that crosses a screen in a beat is a
-- flag, not weather. Live rate scales a little with strength so a storm
-- clocks slightly faster than a calm day. A touch slower than the old
-- 1.35 so the 3D tufts (more geometry, more read) roll rather than buzz.
Wind.RATE = 1.15
Wind.RATE_LIVE = 1.15

-- Rest bearing (east-southeast). Live DIR meanders from climate + time.
Wind.DIR0 = { 0.94, 0.34 }
Wind.DIR = { 0.94, 0.34 }

-- Wavelength, as the phase gained per world pixel along each axis. The two
-- differ so the crests run diagonally rather than in screen-aligned bars,
-- and both are small: about ninety world pixels to a full wave, which is
-- three cells -- long enough that a tuft and its neighbour lean together
-- and a meadow still has several crests in it at once.
Wind.FREQ = { 0.062, 0.047 }

-- Pushed by Weather each tick (0..1): how hard the current shower/snow is
-- driving the air. Wind never requires Weather (cycle), so this is written
-- in -- the same contract as Water.wet.
Wind.weatherDrive = 0

-- What is LYING ON the grass, as opposed to what is pushing it. Both are
-- pushed in from outside for the same cycle reason as `weatherDrive`:
--   grassWet   rain falling on the blades right now (Weather.tick). Water
--              is weight and damping -- a wet tuft is heavier, leans over
--              further and stops sooner -- plus the fast tick of drops
--              landing on it.
--   grassSnow  snow already SETTLED (GroundFX.tick, the accumulated cover
--              rather than the fall). Snow is weight that stays: it bows a
--              tuft over and holds it there, and it stiffens what is left.
-- Kept here rather than read from those modules so the shader uniforms and
-- the CPU lean helper take one number each with nothing to look up.
Wind.grassWet = 0
Wind.grassSnow = 0

-- Smoothed climate 0..1 and live tip-reach in world px (what amount() returns).
Wind.drive = 0.15
Wind.liveAmount = 1.2

-- The squall envelope, 0..1: how far into a GUST this instant is, separate
-- from how strong the air is on average. The shader widens the wave with it
-- and the VFX spawn off it, so a gust is a thing that arrives and passes
-- rather than a slider that happens to be high.
Wind.gustNow = 0

-- ------- TURBULENCE: THE AIR'S OWN EDDIES, AS A PRECOMPUTED FIELD
--
-- The band above is LAMINAR: every point on a crest moves the same way,
-- and what breaks that up today is a per-particle pair of sines -- a
-- wander in TIME, not in SPACE, so two motes a cell apart still march in
-- step and the field reads as a parade. Real air has structure: eddies a
-- couple of cells wide that neighbouring particles fall into differently.
--
-- The structure is PRECOMPUTED, per the task's own decision: two small
-- lattices of 2D vectors built once at first step, sampled bilinearly.
-- Analytic noise per particle per frame is the alternative, and at a
-- couple of thousand flowAt calls a frame on two cores it is the
-- expensive way to buy the same picture.
--
-- ------- WHY THE FIELD IS A CURL, AND WHY THE WAVENUMBERS ARE INTEGERS
--
-- Each lattice is the CURL of a scalar stream function: u = dPSI/dz,
-- w = -dPSI/dx. A curl field has zero divergence by construction, and
-- that is not a nicety -- a field with sources and sinks HERDS particles:
-- dust drains out of one patch of air and piles up in another, and after
-- ten seconds the field is a texture of clumps. Divergence-free eddies
-- stir without herding.
--
-- PSI itself is a sum of sines with INTEGER wavenumbers on the lattice
-- period, which makes the tile seamless by construction -- no lattice
-- interpolation at the wrap, no seam to blend. (The water spectrum
-- taught the adjacent lesson: fields sampled by ACCUMULATED phase decay
-- into noise far from the origin. This one is sampled by WRAPPED
-- position -- world coords modulo the tile -- so there is no distance
-- from the origin to decay with.)
--
-- ------- HOW IT MOVES
--
-- Two independent lattices, blended half and half, ADVECTED with the wind
-- at two different fractions of its speed. The differential slip is what
-- keeps the composite from ever repeating -- the classic two-layer trick
-- -- and it is also true to the thing modelled: turbulence rides the mean
-- flow and lags it. The travel accumulates in Wind.step (bearing meanders,
-- so it has to be integrated, not derived from absolute time) and wraps
-- modulo the tile so the accumulator never grows.
Wind.TURB_MUL = 1        -- master knob; probes flip it to 0 for an A/B
Wind.TURB_FLOW = 0.35    -- share of the mean flow flowAt's own callers get
local TURB_N = 64        -- lattice edge, in cells
local TURB_CELL = 8      -- world px per cell: tile = 512 px
local TURB_TILE = TURB_N * TURB_CELL
local TURB_INV_CELL = 1 / TURB_CELL
local turbA, turbB = nil, nil

local function buildTurbGrid(seed)
  -- a private LCG: deterministic across runs, and the global RNG stays
  -- exactly where the game left it
  local s = seed
  local function rnd()
    s = (s * 1103515245 + 12345) % 2147483648
    return s / 2147483648
  end
  -- The spectrum: fourteen waves, wavenumbers 1..10, amplitude ~ k^-0.5.
  -- The first cut used 1..6 at 1/k and put nearly all the energy in
  -- 300-500px eddies -- which a mote crosses at ~0.25Hz, slow enough
  -- that even the heaviest kind follows them at 95% and the mass task
  -- had nothing to bite on (its accel ratio read x1.38 against a x1.5
  -- gate). Flatter and wider moves real energy into 50-100px eddies:
  -- forcing at 1-2Hz at mote speed, where a leaf still answers in full
  -- and a dense grain's first-order filter visibly does not. The RMS
  -- normalisation below absorbs the reshape, so every envelope number
  -- downstream keeps its meaning.
  local waves = {}
  while #waves < 14 do
    local a = math.floor(rnd() * 21) - 10
    local b = math.floor(rnd() * 21) - 10
    local k2 = a * a + b * b
    if k2 > 0 and k2 <= 104 then
      waves[#waves + 1] = { a = a, b = b,
                            amp = k2 ^ -0.25,
                            ph = rnd() * 6.2831853 }
    end
  end
  local TAU_N = (2 * math.pi) / TURB_N
  local psi = {}
  for j = 0, TURB_N - 1 do
    for i = 0, TURB_N - 1 do
      local v = 0
      for k = 1, #waves do
        local w = waves[k]
        v = v + w.amp * math.sin((w.a * i + w.b * j) * TAU_N + w.ph)
      end
      psi[j * TURB_N + i + 1] = v
    end
  end
  -- central differences with wrap: discretely divergence-free
  local ux, uz = {}, {}
  local sum2 = 0
  for j = 0, TURB_N - 1 do
    local jm, jp = (j - 1) % TURB_N, (j + 1) % TURB_N
    for i = 0, TURB_N - 1 do
      local im, ip = (i - 1) % TURB_N, (i + 1) % TURB_N
      local n = j * TURB_N + i + 1
      local du = (psi[jp * TURB_N + i + 1] - psi[jm * TURB_N + i + 1]) * 0.5
      local dw = -(psi[j * TURB_N + ip + 1] - psi[j * TURB_N + im + 1]) * 0.5
      ux[n], uz[n] = du, dw
      sum2 = sum2 + du * du + dw * dw
    end
  end
  -- normalised to RMS 1: every amplitude decision lives in the per-frame
  -- envelope, not in the lattice
  local rms = math.sqrt(sum2 / (TURB_N * TURB_N))
  local inv = (rms > 0) and (1 / rms) or 0
  for n = 1, TURB_N * TURB_N do
    ux[n] = ux[n] * inv
    uz[n] = uz[n] * inv
  end
  return { ux = ux, uz = uz }
end

-- bilinear with wrap; x,z in CELL units. Allocates nothing.
local function turbSample(g, x, z)
  local i0 = math.floor(x)
  local j0 = math.floor(z)
  local fx = x - i0
  local fz = z - j0
  i0 = i0 % TURB_N
  j0 = j0 % TURB_N
  local i1 = (i0 + 1) % TURB_N
  local j1 = (j0 + 1) % TURB_N
  local n00 = j0 * TURB_N + i0 + 1
  local n10 = j0 * TURB_N + i1 + 1
  local n01 = j1 * TURB_N + i0 + 1
  local n11 = j1 * TURB_N + i1 + 1
  local ux, uz = g.ux, g.uz
  local a = ux[n00] + (ux[n10] - ux[n00]) * fx
  local b = ux[n01] + (ux[n11] - ux[n01]) * fx
  local sx = a + (b - a) * fz
  a = uz[n00] + (uz[n10] - uz[n00]) * fx
  b = uz[n01] + (uz[n11] - uz[n01]) * fx
  return sx, a + (b - a) * fz
end

-- The eddy vector at a world point: both lattices, half and half, each
-- under its own accumulated travel, scaled by the frame's envelope.
-- (0, 0) when the air is calm, the row is OFF, or the knob is zero --
-- callers add it blind. RMS of the return is about turbEnv.
function Wind.turbAt(wx, wz)
  local f = Wind.flow
  local env = f.turbEnv or 0
  if env <= 0 or not turbA then return 0, 0 end
  wx, wz = wx or 0, wz or 0
  local ax, az = turbSample(turbA, (wx - f.tax) * TURB_INV_CELL,
                                   (wz - f.taz) * TURB_INV_CELL)
  local bx, bz = turbSample(turbB, (wx - f.tbx) * TURB_INV_CELL,
                                   (wz - f.tbz) * TURB_INV_CELL)
  -- 1/sqrt(2), not 1/2: the layers are independent RMS-1 fields, and the
  -- factor that keeps the BLEND at RMS 1 is the root of the count -- so
  -- "RMS of the return is about turbEnv" stays a true sentence
  return (ax + bx) * 0.7071068 * env, (az + bz) * 0.7071068 * env
end

local function clamp01(n)
  n = tonumber(n) or 0
  if n < 0 then return 0 end
  if n > 1 then return 1 end
  return n
end

-- Instant climate target: always a little air outdoors, more under a front,
-- quieter at night, a touch livelier in winter afternoons.
function Wind.climateTarget()
  local d = 0.14
  d = d + clamp01(Wind.weatherDrive) * 0.78

  if DayNight.time and DayNight.bodyAt then
    local ok, body = pcall(function()
      local _, e, m = DayNight.bodyAt(DayNight.time())
      return { el = e, moon = m }
    end)
    if ok and body then
      local el = tonumber(body.el) or 45
      if body.moon then
        d = d * 0.50 + 0.06
      else
        -- midday carries a steady breeze; low sun (front hour) gusts more
        local elev = el / 55
        if elev < 0 then elev = 0 elseif elev > 1 then elev = 1 end
        d = d + 0.18 * elev
        if el > 4 and el < 28 then d = d + 0.14 end
      end
    end
  end

  -- multi-scale gust envelope (real wind is never a flat slider)
  local t = 0
  if love and love.timer and love.timer.getTime then
    t = love.timer.getTime()
  end
  -- winter months (south-hemisphere default, same as Weather): a colder bite
  if DayNight.month then
    local okm, month = pcall(DayNight.month)
    if okm and (month == 6 or month == 7 or month == 8) then
      d = d + 0.10
    end
  end
  local gust = 0.52
             + 0.28 * math.sin(t * 0.19)
             + 0.20 * math.sin(t * 0.47 + 1.1)
             + 0.12 * math.sin(t * 1.13 + 0.4)
  if gust < 0.25 then gust = 0.25 end
  if gust > 1.35 then gust = 1.35 end
  -- the same envelope, normalised onto 0..1 for everything that wants to
  -- know whether a gust is passing rather than how hard the air is
  Wind.gustNow = clamp01((gust - 0.25) / 1.10)
  d = d * gust
  if d > 1 then d = 1 end
  return d
end

-- Advance natural wind. Called from Weather's tick (and safe if missed).
function Wind.step(dt)
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end

  local ok, v = pcall(Wind.setting.get, Wind.setting)
  local row = (ok and tonumber(v)) or 1
  if row == 0 then
    Wind.drive = 0
    Wind.liveAmount = 0
    Wind.gustNow = 0
    Wind.RATE_LIVE = Wind.RATE
    -- still air has no eddies; the rest of the flow packet keeps its
    -- pre-OFF values, which is the shipping behaviour left untouched
    Wind.flow.turbEnv = 0
    Wind.flow.turbV = 0
    return
  end

  local target = Wind.climateTarget()
  -- lag so fronts swell the air rather than snapping it
  local k = target > Wind.drive and 1.6 or 0.7
  Wind.drive = Wind.drive + (target - Wind.drive) * math.min(1, k * dt)

  local drive = clamp01(Wind.drive)
  if row == 1 then
    -- ------- AUTO
    --
    -- One curve across the WHOLE range the other two rows split between
    -- them: BREEZE's floor at the bottom, GALE's ceiling at the top, and
    -- the climate deciding where on it this minute sits. Bent by an
    -- exponent above 1 so calm stays genuinely calm -- a linear ramp over
    -- that span leaves an idle afternoon already halfway to a storm, which
    -- is what makes a fixed row feel like it needs turning up.
    --
    -- The front gets its own term on top: a shower's drive already lifts
    -- `drive`, but the point of AUTO is that a downpour reads as a
    -- downpour without anybody walking to the menu, so it is pushed the
    -- last of the way rather than merely allowed to drift up.
    local shaped = drive * drive * (3 - 2 * drive)   -- smoothstep, S-curved
    shaped = shaped * 0.55 + drive * drive * 0.45    -- and biased low
    local front = clamp01(Wind.weatherDrive)
    Wind.liveAmount = 0.30 + shaped * 4.30 + front * front * 0.90
  elseif row == 2 then
    -- BREEZE: natural outdoor range ~0.45..3.2 tip px (3D tufts read more
    -- lean than the old slab, so the floor is a little higher)
    Wind.liveAmount = 0.45 + drive * 2.75
  else
    -- GALE: climate, fiercer ~1.4..5.0
    Wind.liveAmount = 1.4 + drive * 3.6
  end

  -- storm clocks a bit faster. AUTO leans on this harder than a fixed row
  -- does: half of what tells a storm from a breeze is the RATE, not the
  -- reach, and AUTO is the row that has to make that difference on its own.
  local rateK = (row == 1) and 0.62 or 0.45
  Wind.RATE_LIVE = Wind.RATE * (0.85 + rateK * drive)

  -- bearing meanders; weather fronts bias a little more south-east
  local t = 0
  if love and love.timer and love.timer.getTime then
    t = love.timer.getTime()
  end
  local base = math.atan2(Wind.DIR0[2], Wind.DIR0[1])
  local meander = math.sin(t * 0.031) * 0.55
                + math.sin(t * 0.013 + 2.0) * 0.35
  local front = clamp01(Wind.weatherDrive) * 0.25
  local ang = base + meander + front
  Wind.DIR[1] = math.cos(ang)
  Wind.DIR[2] = math.sin(ang)

  -- ------- and the field everything airborne reads (Wind.flowAt)
  --
  -- The per-frame half of it. The band travels along the bearing at the
  -- same rate the grass ripple does -- one phase, one clock -- so the gust
  -- that bends the meadow is the gust that slants the rain over it rather
  -- than a second gust on its own schedule.
  local amount = Wind.liveAmount or 0
  local v = amount * Wind.FLOW
  local gust = clamp01(Wind.gustNow)
  local f = Wind.flow
  f.vx, f.vz = Wind.DIR[1] * v, Wind.DIR[2] * v
  f.fx, f.fz = Wind.FREQ[1] * Wind.BAND, Wind.FREQ[2] * Wind.BAND
  f.p0 = -Wind.phase() * 0.37
  -- A squall does not merely blow harder, it blows harder IN PLACES: the
  -- envelope lifts the mean and deepens the trough at the same time, so a
  -- gale is a field of fast air with slow holes in it and not a uniformly
  -- faster calm.
  f.base = 0.74 + 0.55 * gust
  f.amp = 0.26 + 0.34 * gust

  -- ------- and the eddies' frame half (see the turbulence block up top)
  --
  -- Built here, lazily, so a session that never turns the wind on never
  -- pays the one-time lattice build.
  if not turbA then
    turbA = buildTurbGrid(7)
    turbB = buildTurbGrid(9241)
  end
  -- Advected with the wind at two different fractions of its speed: the
  -- slip between the layers is what keeps the composite from repeating.
  -- Integrated, not derived from time -- the bearing meanders -- and
  -- wrapped so the accumulator never grows past a tile.
  local adv = amount * Wind.FLOW * dt
  f.tax = (f.tax + Wind.DIR[1] * adv * 0.55) % TURB_TILE
  f.taz = (f.taz + Wind.DIR[2] * adv * 0.55) % TURB_TILE
  f.tbx = (f.tbx + Wind.DIR[1] * adv * 0.78) % TURB_TILE
  f.tbz = (f.tbz + Wind.DIR[2] * adv * 0.78) % TURB_TILE
  -- The envelope: calm air still has a little texture, a squall churns.
  -- Kept here so every consumer -- the solver's motes, the rain's slant,
  -- the weather's own world motes -- breathes on the one clock.
  f.turbEnv = Wind.TURB_MUL * (0.55 + 0.75 * gust)
  f.turbV = amount * Wind.FLOW * Wind.TURB_FLOW
end

-- ------- THE AIR ITSELF, AND WHY THE RAIN HAS TO ASK FOR IT
--
-- `leanAt` answers how far something ROOTED is pushed at a point. That is a
-- displacement, and it is the right answer for a blade of grass. Anything
-- actually CARRIED by the air -- a raindrop, a flake, a seed, a scrap of
-- grit -- needs the other half of the same field: how fast the air at that
-- point is moving, and which way.
--
-- It has to be the SAME field, and that is the whole reason this lives
-- here rather than as a private sine in each caller. Wind arrives in
-- BANDS: a gust is a wave travelling along the bearing, and the meadow
-- already rides that wave (the `front` term in leanAt, and its twin in
-- Voxel3D's vertex sway). A rain system that rolls its own noise instead
-- produces a frame where a visible gust crosses the grass while the rain
-- above it goes on falling at one flat angle -- two effects in one
-- picture. Sharing the field is what makes a squall read as ONE thing
-- arriving, and it is the same rule the roamers already follow.
--
-- Returns (vx, vz, band): the air's horizontal velocity in world pixels
-- per second, and the band factor that produced it -- around 0.4 in a lull
-- and 1.6 in the crest -- for a caller that wants to size or brighten by
-- it. Zero on both under WIND OFF.
--
-- CHEAP ON PURPOSE. This is called once per raindrop per frame, a couple
-- of hundred times, on a machine with two cores. Everything that does not
-- depend on the POSITION is computed once in Wind.step (which already runs
-- once per frame, from Weather's tick) and only the two sines are paid per
-- call. Reading the setting through a pcall two hundred times a frame,
-- which is what the obvious version of this does, is most of a millisecond.
Wind.FLOW = 17          -- world px/s of air per unit of Wind.amount
-- How much longer the gust band's wave is than the grass ripple it rides
-- on. A band has to be many cells across or the rain sorts itself into
-- stripes you can count; this is the number that makes it weather rather
-- than a barcode.
Wind.BAND = 0.21

-- Filled by Wind.step. The fallback values are the ones a caller gets if
-- it asks before the first step ever ran, and they are deliberately a dead
-- calm rather than a guess. tax..tbz are the two lattices' accumulated
-- travels; turbEnv is the eddies' strength this frame and turbV the world
-- px/s flowAt's own callers convert them at.
Wind.flow = { vx = 0, vz = 0, fx = 0, fz = 0, p0 = 0, amp = 0, base = 0,
              tax = 0, taz = 0, tbx = 0, tbz = 0,
              turbEnv = 0, turbV = 0 }

function Wind.flowAt(wx, wz)
  local f = Wind.flow
  if f.amp <= 0 then return f.vx, f.vz, 0 end
  local p = (wx or 0) * f.fx + (wz or 0) * f.fz + f.p0
  local band = f.base + f.amp * (math.sin(p) + 0.58 * math.sin(p * 2.7 + 1.1))
  if band < 0 then band = 0 end
  local vx, vz = f.vx * band, f.vz * band
  -- the eddies, on top of the band: same field for the rain that slants
  -- through them and the weather's world motes that ride them. The share
  -- is deliberately below the solver's own -- a raindrop crosses an eddy
  -- in a frame and only its angle should shiver, not its lane.
  local tv = f.turbV or 0
  if tv > 0 then
    local ux, uz = Wind.turbAt(wx, wz)
    vx = vx + ux * tv
    vz = vz + uz * tv
  end
  return vx, vz, band
end

function Wind.amount()
  local ok, v = pcall(Wind.setting.get, Wind.setting)
  local row = (ok and tonumber(v)) or 1
  if row == 0 then return 0 end
  local n = tonumber(Wind.liveAmount) or 1.2
  if n < 0 then n = 0 end
  if n > 8 then n = 8 end
  return n
end

function Wind.enabled()
  return Wind.amount() > 0
end

function Wind.isAuto()
  local ok, v = pcall(Wind.setting.get, Wind.setting)
  return ((ok and tonumber(v)) or 1) == 1
end

-- The squall envelope this instant, 0..1. Zero under WIND OFF so nothing
-- downstream has to ask twice.
function Wind.gust()
  if Wind.amount() <= 0 then return 0 end
  return clamp01(Wind.gustNow)
end

-- What the grass is carrying and what is passing over it, as the one
-- three-number packet the scene shader takes (Voxel3D `grassLoad`):
-- rain on the blades, settled snow on them, and the gust.
function Wind.load()
  return clamp01(Wind.grassWet), clamp01(Wind.grassSnow), Wind.gust()
end

-- The phase, from absolute time rather than an accumulator: this is read
-- once per frame by the scene and once more by a staged battle, and an
-- accumulator advanced per read would run at whatever rate it happened to
-- be called at.
function Wind.phase()
  local rate = Wind.RATE_LIVE or Wind.RATE
  if love and love.timer and love.timer.getTime then
    return (love.timer.getTime() * rate) % (math.pi * 2048)
  end
  return 0
end

-- How far a point at world XZ leans with the wind, in world pixels on each
-- axis.  The same travelling wave the grass vertex shader rides
-- (Voxel3D.lua: sway * bend * (sin p + 0.35 sin 2.3p)), so a mon standing
-- in the meadow and the tuft next to it lean together rather than on two
-- clocks.  `heightFrac` is 0 at the ground and 1 at the tip -- squared the
-- same way the shader does, so the feet stay planted and the body gives.
--
-- Returns (dx, dz).  Zero under WIND OFF or a zero amount.
function Wind.leanAt(wx, wz, heightFrac)
  local sway = Wind.amount()
  if sway <= 0 then return 0, 0 end
  local h = tonumber(heightFrac) or 0.5
  if h < 0 then h = 0 elseif h > 1 then h = 1 end
  local bend = h * h
  local phase = Wind.phase()
  local p = wx * Wind.FREQ[1] + wz * Wind.FREQ[2] - phase
  -- The SQUALL FRONT, the shader's twin: a second, much longer wave riding
  -- the same bearing, so the air arrives in bands rather than at one flat
  -- amplitude everywhere. A body standing in a meadow has to be inside the
  -- same band as the tufts around it or it reads as leaning on its own.
  local front = 0.72 + 0.28 * math.sin(wx * Wind.FREQ[1] * 0.21
                                       + wz * Wind.FREQ[2] * 0.21
                                       - phase * 0.37)
  -- Rain and snow are load, and load is the same on a person as on a blade:
  -- water damps, settled snow stiffens. No per-tuft stiffness here -- that
  -- one is the meadow's own scatter and a walker has no tuft.
  local wet, snow, gust = Wind.load()
  local amp = sway * (0.55 + 0.45 * front) * (1 + 0.55 * gust)
                   * (1 - 0.28 * wet) * (1 - 0.62 * snow)
  -- Match the vertex shader's three-harmonic wave so roamers in grass and
  -- the tufts next to them lean on one clock (Voxel3D sway block).
  local wave = math.sin(p)
             + 0.38 * math.sin(p * 2.25 + 1.7)
             + 0.14 * math.sin(p * 5.3 + h * 2.1 + 0.4)
             + wet * 0.22 * math.sin(p * 9.1)
  local a = amp * bend * wave
  local dx = Wind.DIR[1] * a
  local dz = Wind.DIR[2] * a
  -- mild cross-axis (shader twin)
  local cross = 0.18 * math.sin(p * 1.6 + 0.9) * bend * amp
  dx = dx + (-Wind.DIR[2]) * cross
  dz = dz + (Wind.DIR[1]) * cross
  return dx, dz
end

return Wind
