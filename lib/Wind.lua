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
