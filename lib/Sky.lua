-- The sky, generated rather than shipped.
--
-- The overworld's, on every VOXEL rung. Wherever the diorama is drawn the void
-- behind it is sky rather than a black plate: at 75 degrees the horizon is
-- genuinely in frame and the bands run down to meet it, and at the steeper rungs
-- the void that shows is the ground running out past the map edge, which gets
-- the same sky above the same haze. A battle's placed camera keeps the flat fill
-- it has always had -- its horizon is above the frame and its look is not this
-- rung's to change.
--
-- THE RECIPE is the 8-bit skybox one: a short palette of blues painted as flat
-- horizontal bands, deepest overhead, with a CHECKERBOARD of the next band
-- dithered into the bottom of each one. Alternating two colours on a pixel grid
-- is how a machine with four colours to a palette got a fifth, sixth and seventh
-- out of them, and it is what keeps four bands reading as a gradient rather than
-- as four stripes. CLOUDS are optional volumetric puffs raymarched inside
-- the same sky pass (cel density steps + checker dither, wind-advected),
-- not a second target -- see the cloud block in SHADER_SRC.
--
-- NOTHING IS RESAMPLED, which is the whole of why it is drawn this way. There is
-- no baked 160x144 picture scaled up to the window and no downsized buffer blown
-- back up: one full-region rectangle through a shader that answers every pixel
-- from its own canvas coordinate. A pixel of sky is computed at the size it is
-- displayed at, so there is nothing for a filter to soften and nothing to go
-- stale when the window or the zoom changes. The shader does bind one texture,
-- but it is a palette rather than an image -- the bands, one texel each, sampled
-- nearest (see rampFor, and why it is not a uniform array).
--
-- THE PIXEL GRID follows the zoom for the same reason. Bands and dither cells
-- are measured in DIORAMA pixels -- the pass's own pixels-per-world-pixel, handed
-- in fresh every frame -- so a chunky sky at 4x is a chunky sky at 12x, band
-- edges land on the same grid the world's own texels do, and a ZOOM keypress is
-- reflected in the frame that follows it rather than whenever something else
-- happened to rebuild.
--
-- PALETTE ORDER, which is easy to get wrong. Stored LIGHTEST FIRST, because that
-- is shade order: a display mode transforms a four-colour palette by replacing it
-- outright (PaletteFX.effectiveColors hands back GRAYS or CLASSIC), and those are
-- written light to dark. So the sky reads the list backwards -- deepest shade
-- overhead, shade 1 at the horizon -- and GRAY gets greys the right way up for
-- nothing.
--
-- WHAT TIME IT IS decides the colours. The palette itself lives in DayNight
-- (four phase palettes, blended along the clock and re-quantised to the
-- lattice), and this file paints whatever the clock says: blue at noon, gold
-- and violet through the twilights -- warmed further around the low sun by a
-- dithered GLOW -- and deep navy under the moon. The sun and moon themselves
-- hang here too: cell-art discs on the same grid as the dither, scissored to
-- the sky's own region so a setting body slips below the horizon point and is
-- gone, never wandering under the map.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local DayNight = V.require("DayNight")
local Quality = V.require("Quality")
local Weather = V.require("Weather")
local Wind = V.require("Wind")
local ModSetting = V.require("ModSetting")
local PaletteFX = require("src.render.PaletteFX")

local Sky = {}

-- CLOUDS row: painted volume in the sky pass (not a particle layer).
--   ON     fair-weather puffs that thicken with DayNight.overcast
--   THICK  heavier deck even on a clear hour (showcase / screenshots)
--   OFF    bands only -- the sky this file started as
Sky.cloudSetting = ModSetting.new("clouds", "CLOUDS",
                                  { 1, 2, 0 },
                                  { "ON", "THICK", "OFF" })

-- ------- what makes a deck read as WEATHER rather than as wallpaper
--
-- Two numbers, and between them they are the whole of the "clouds actually
-- move" fix -- because the deck was already travelling. `cloudWind * cloudTime`
-- has been pushing the sample point downwind since this shader was written,
-- fast enough to cross the frame in about half a minute. Motion was never
-- what was missing. What was missing is that the thing being moved was RIGID
-- and NAILED TO THE SCREEN, and the eye reads either of those as a painted
-- backdrop no matter how fast you tow it past.
--
-- PARALLAX fixes the second: the deck's sample origin picks up the camera, so
-- cloud sits over Kanto instead of over the monitor. The number is small on
-- purpose -- cloud is the farthest thing in the frame and therefore the thing
-- that must shift LEAST as you walk. That difference IS the distance cue;
-- make it large and the sky turns into a low ceiling sliding overhead.
--
-- EVOLVE fixes the first: it drives the erosion noise inside cloudDensity at
-- its own rate, against the wind that carries the mass. Puffs open, thin and
-- close as the deck crosses, so it is never the same shape twice. Slower than
-- the drift by design -- cloud that boils reads as steam.
Sky.CLOUD_PARALLAX = 0.0016   -- noise units per world pixel of camera
Sky.CLOUD_EVOLVE = 0.035      -- shape change per second, independent of wind

-- Coastal outdoor maps: denser low fog at dawn/dusk (cheap id table, not
-- a tile scan). Extends the same idea as DayNight.CANOPY for forests.
Sky.COAST = {
  ROUTE_11 = true, ROUTE_12 = true, ROUTE_13 = true,
  ROUTE_17 = true, ROUTE_18 = true, ROUTE_19 = true,
  ROUTE_20 = true, ROUTE_21 = true, ROUTE_24 = true, ROUTE_25 = true,
  PALLET_TOWN = true, VERMILION_CITY = true, FUCHSIA_CITY = true,
  CINNABAR_ISLAND = true, CERULEAN_CITY = true,
}

-- The most bands a phase palette may paint with. Eight leaves headroom over
-- DayNight's six-band ones without paying for more; the ramp the shader reads
-- them from is built at the width actually used, so the cap costs nothing.
Sky.MAX_BANDS = 8

-- The checkerboard between bands. DITHER_START is how far down a band it begins,
-- as a fraction of that band: lower is a wider blend, and 1 switches it off. 0.6
-- leaves the top of each band flat -- a band dithered all the way through reads
-- as one averaged colour instead of as a step with a soft bottom edge.
Sky.DITHER = true
Sky.DITHER_START = 0.6

-- How much of the frame the bands cover when the horizon is NOT in it, as a
-- fraction of the canvas height.
--
-- At the steeper rungs the camera looks down far enough that the ground plane's
-- vanishing line is above the top edge -- there is no horizon to hang the pale
-- end on, but there is still void up there where the map runs out, and it should
-- read as sky. So the bands take the same slice of the frame the top rung's own
-- horizon gives them, which keeps the sky looking like one sky across the whole
-- ladder instead of changing character rung by rung.
Sky.SPAN = 0.23

-- ------- the bands
--
-- Top first, each a { r, g, b } in 0..1, as the display mode has them.
--
-- Memoised, because this runs once a frame and the answer only moves when the
-- mode does.
local cache = { bands = nil, key = {}, ramp = nil }

-- Post-rain saturation amount 0..1 (hard steps for cel). 0 when idle.
local function afterRainAmt()
  local ok, v = pcall(Weather.afterRain)
  if not ok then return 0 end
  local n = tonumber(v) or 0
  if n <= 0 then return 0 end
  -- three plateaus so the sky does not airbrush back to normal
  if n > 0.66 then return 1 end
  if n > 0.33 then return 0.5 end
  return 0.25
end

-- Push a 0..1 RGB toward higher chroma without leaving the 5-bit lattice
-- neighbours too far: sat 0 = unchanged, 1 = hard pop after rain.
local function satBoost(r, g, b, sat)
  if sat <= 0 then return r, g, b end
  local avg = (r + g + b) / 3
  local nr = avg + (r - avg) * (1 + 0.55 * sat)
  local ng = avg + (g - avg) * (1 + 0.55 * sat)
  local nb = avg + (b - avg) * (1 + 0.55 * sat)
  if nr < 0 then nr = 0 elseif nr > 1 then nr = 1 end
  if ng < 0 then ng = 0 elseif ng > 1 then ng = 1 end
  if nb < 0 then nb = 0 elseif nb > 1 then nb = 1 end
  return nr, ng, nb
end

function Sky.bands()
  local pal = DayNight.palette()
  local shades = PaletteFX.effectiveColors(pal) or pal
  local n = math.min(#shades, #pal, Sky.MAX_BANDS)
  local sat = afterRainAmt()
  local key, k = cache.key, 0
  local same = cache.bands ~= nil and #cache.bands == n
               and cache.sat == sat
  for i = 1, n do
    local c = shades[i]
    for ch = 1, 3 do
      k = k + 1
      if key[k] ~= c[ch] then same = false end
      key[k] = c[ch]
    end
  end
  if same then return cache.bands end

  -- the ramp is these bands as a texture (see rampFor); a new list is a new
  -- ramp, and the old one is nothing's to keep
  if cache.ramp and cache.ramp.release then pcall(cache.ramp.release, cache.ramp) end
  cache.ramp, cache.rampFor = nil, nil

  local bands = {}
  for i = 1, n do
    -- backwards: the palette's darkest rung is the top band
    local c = shades[n - i + 1]
    local r, g, b = c[1] / 255, c[2] / 255, c[3] / 255
    r, g, b = satBoost(r, g, b, sat)
    bands[i] = { r, g, b }
  end
  cache.bands = bands
  cache.sat = sat
  return bands
end

-- Low fog density 0..1 for the current hour + map. Dawn/dusk (and a share
-- of golden hour) only; denser under canopy and on coast; zero under heavy
-- rain (the shower owns the air) and at Quality.fogBands() == 0.
function Sky.fogAmount(map)
  local nBands = 0
  if Quality.fogBands then
    local ok, n = pcall(Quality.fogBands)
    if ok then nBands = n or 0 end
  end
  if nBands <= 0 then return 0 end

  local mix = DayNight.mix(DayNight.time())
  local hour = (mix.dawn or 0) + (mix.dusk or 0)
             + 0.40 * (mix.golden or 0)
  if hour < 0.04 then return 0 end

  -- rain owns the air; post-rain may keep a thin veil (half strength)
  local wet = 0
  local okv, kind, power = pcall(Weather.visible)
  if okv and kind and power then wet = power end
  if wet > 0.25 then
    hour = hour * (1 - math.min(1, wet))
  end
  local ar = afterRainAmt()
  if ar > 0 and wet <= 0 then
    hour = math.max(hour, 0.22 * ar)
  end
  if hour < 0.04 then return 0 end

  local dens = hour
  if map and DayNight.isCanopy(map) then dens = dens * 1.55 end
  if map and map.id and Sky.COAST[map.id] then dens = dens * 1.40 end
  if dens > 1 then dens = 1 end
  return dens
end

-- Cloud coverage 0..1 for the sky pass. Fair weather still carries a few
-- puffs so the sky is not a bare ramp; overcast (Weather -> DayNight.overcast)
-- and heavy rain fill the deck. CLOUDS row can pin OFF or force THICK.
function Sky.cloudAmount()
  local steps = 0
  if Quality.cloudSteps then
    local ok, n = pcall(Quality.cloudSteps)
    if ok then steps = n or 0 end
  end
  if steps <= 0 then return 0 end

  local mode = 1
  do
    local ok, v = pcall(Sky.cloudSetting.get, Sky.cloudSetting)
    if ok and tonumber(v) then mode = tonumber(v) end
  end
  if mode <= 0 then return 0 end

  local overcast = tonumber(DayNight.overcast) or 0
  if overcast < 0 then overcast = 0 elseif overcast > 1 then overcast = 1 end

  -- rain/snow visible power pulls a deck over even before overcast ramps
  local wet = 0
  local okv, kind, power = pcall(Weather.visible)
  if okv and kind and power then wet = tonumber(power) or 0 end
  if wet < 0 then wet = 0 elseif wet > 1 then wet = 1 end

  local amt
  if mode >= 2 then
    -- THICK: showcase deck; weather can only make it heavier
    amt = 0.62 + 0.38 * math.max(overcast, wet)
  else
    -- ON: sparse fair-weather puffs that thicken with the front
    amt = 0.18 + 0.82 * math.max(overcast, wet * 0.95)
  end

  -- night still has clouds, but fewer of them (stars need room)
  local mix = DayNight.mix(DayNight.time())
  local night = (mix.night or 0)
  if night > 0 then
    amt = amt * (1.0 - 0.35 * night)
  end

  if amt < 0 then amt = 0 elseif amt > 1 then amt = 1 end
  return amt
end

-- 0..1 how deep into night the cloud paint should cool (shader cloudNight).
function Sky.cloudNight()
  local mix = DayNight.mix(DayNight.time())
  local n = (mix.night or 0) + 0.35 * (mix.dusk or 0)
  if n < 0 then n = 0 elseif n > 1 then n = 1 end
  return n
end

-- The hour's haze -- the palest band, in 0..1 -- which is both the sky's
-- bottom edge and the right flat fill for any outdoor void that wants to
-- match the clock without painting bands (the battle arena's backdrop).
function Sky.haze()
  local bands = Sky.bands()
  return bands and bands[#bands] or nil
end

-- Put the sky onto a flat descriptor: the bands to paint, plus the flat fill
-- replaced by the palest of them. That fill is what the caller CLEARS to, so
-- making it the bottom band's own colour means the haze below the sky and the
-- bottom of the sky are one colour -- the join has no seam, and a frame that
-- cannot paint the bands is a hazy sky rather than a wrong one.
--
-- Mutates the descriptor, which is a fresh table per frame from its caller.
function Sky.dress(sky)
  local bands = Sky.bands()
  local haze = bands and bands[#bands]
  if not (sky and haze) then return sky end
  -- map id rides the descriptor so fog density can see canopy/coast without
  -- Sky requiring the overworld (cycle risk). Caller may overwrite.
  sky[1], sky[2], sky[3] = haze[1], haze[2], haze[3]
  sky.bands = bands
  return sky
end

-- Where the sky's bottom edge goes, in canvas pixels: the camera's own horizon
-- when that is in frame, and SPAN of the frame when it is not (see SPAN). nil
-- when there is no room for any of it.
function Sky.region(h, horizonY)
  if not (h and h > 0) then return nil end
  local edge = horizonY
  if not (edge and edge > 0) then edge = h * Sky.SPAN end
  edge = math.min(edge, h)
  if edge < 1 then return nil end
  return edge
end

-- ------- the pass
--
-- One rectangle, one shader. Every pixel answers for itself from its canvas
-- coordinate, so the sky is drawn at exactly the resolution it is displayed at
-- -- there is no image being scaled and so nothing to be soft. The one texture
-- bound is the band ramp, which is a PALETTE and not a picture: n texels wide,
-- sampled nearest, one lookup per pixel (see rampFor).
--
-- `cell` quantises BOTH the band edges and the dither: the y a pixel is judged
-- by is the top of its own cell row, so a whole cell row is one colour and every
-- edge in the sky lands on the diorama's pixel grid.
local SHADER_SRC = [[
uniform Image ramp;     // the bands, one texel each, top of the sky first
uniform float count;    // how many texels wide that ramp is
uniform float edge;     // the sky's bottom, in canvas pixels
uniform float cell;     // the diorama's pixel size, in canvas pixels
uniform float start;    // where the checker begins inside a band
uniform float alpha;
uniform float glowAmt;  // twilight warmth around the low sun; 0 = none
uniform vec2 glowPos;   // the sun disc, in canvas pixels
uniform float glowInvR; // 1 / the glow's reach
uniform vec3 glowColor;
// Volumetric clouds (cel density + wind advection). steps==0 skips the
// march so a phone rung never pays for it.
uniform float cloudAmt;    // coverage 0..1
uniform float cloudTime;   // seconds * rate
uniform vec2  cloudWind;   // unit XZ bearing
uniform float cloudSteps;  // 0 / 4 / 6 / 8
uniform vec3  cloudLit;    // sunlit face
uniform vec3  cloudShade;  // self-shadow face
uniform float cloudNight;  // 0 day .. 1 deep night dim
uniform float frameW;      // canvas width for aspect-correct UVs
uniform float cloudEvolve; // seconds * a slower rate: shape change, not drift
uniform vec2  camOff;      // the camera in noise units -- the deck's parallax
// Distant rain: a wall of shafts standing on the horizon, under the deck and
// over the haze band. Leads the near streaks (Weather.curtain).
uniform float curtainAmt;  // 0..1; 0.01 and under is the whole block off
uniform vec3  curtainCol;
// God rays: sunlight through a deck that is breaking up after a shower.
uniform float rayAmt;      // 0..1 (Weather.afterRain, sun only -- not a moon)
uniform vec2  rayPos;      // the disc, in canvas pixels
uniform float rayInvR;     // 1 / the fan's reach
uniform vec3  rayColor;

// Band `i`, read from its own texel centre. The index is clamped rather than
// trusted: `pos` below can land exactly on `count` when the arithmetic is
// carried at mediump -- which is the fragment default on GLSL ES -- and a
// sample past the last band must be the last band, not whatever is off the
// end of the image.
vec3 bandAt(float i) {
  return Texel(ramp, vec2((clamp(i, 0.0, count - 1.0) + 0.5) / count, 0.5)).rgb;
}

// Cheap value noise -- two hashes, bilinear. Good enough for puffy
// density and free of any texture unit (the ramp already occupies one).
float cloudHash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float cloudNoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = cloudHash(i);
  float b = cloudHash(i + vec2(1.0, 0.0));
  float c = cloudHash(i + vec2(0.0, 1.0));
  float d = cloudHash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float cloudFbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  // fixed 4 octaves: unrolled by the compiler, safe on ES mediump
  v += a * cloudNoise(p); p = p * 2.03 + vec2(17.0, 9.0); a *= 0.5;
  v += a * cloudNoise(p); p = p * 2.03 + vec2(17.0, 9.0); a *= 0.5;
  v += a * cloudNoise(p); p = p * 2.03 + vec2(17.0, 9.0); a *= 0.5;
  v += a * cloudNoise(p);
  return v;
}

// Density at a sample point inside the cloud slab. `h` is altitude in the
// slab 0..1 (low = cloud base, high = tops), `xz` is world-ish UV advected
// by wind so the deck TRAVELS rather than crawling in screen space.
float cloudDensity(vec2 xz, float h, float thr, float ev) {
  // slightly lower frequency with height so tops are softer than the base
  float n = cloudFbm(xz * mix(1.35, 0.85, h) + vec2(0.0, h * 1.7));
  // vertical envelope: flat base, puffy mid, thin tops (the "volume" read)
  float envelope = smoothstep(0.02, 0.18, h) * (1.0 - smoothstep(0.62, 0.98, h));
  // Erode by a second noise -- and SLIDE THAT NOISE AGAINST THE FIRST. `ev`
  // is the only new thing here and it is the difference between cloud that
  // travels and cloud that lives: the mass drifts downwind, the erosion
  // drifts at its own rate and its own angle, and what survives between them
  // is never the same shape twice. Two constants, zero extra work -- it is
  // the same texture-free noise call, sampled somewhere else.
  float carve = cloudNoise(xz * 2.4 + vec2(h * 3.1 + ev * 2.3, 11.0 - ev * 1.7));
  n = n - carve * 0.18;
  return max(n - thr, 0.0) * envelope;
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  float row = floor(sc.y / cell) * cell;              // top of this cell row
  float pos = min(row / max(edge, 1.0), 1.0) * count;
  float base = min(floor(pos), count - 1.0);
  vec3 c = bandAt(base);
  float parity = mod(floor(sc.x / cell) + floor(sc.y / cell), 2.0);
  if (base < count - 1.0 && (pos - base) > start) {
    if (parity < 0.5) { c = bandAt(base + 1.0); }
  }
  // The sunset's warmth, radiating from the disc: posterised to a few rungs
  // and checker-dithered between them -- the same 8-bit move as the bands,
  // so the glow reads as painted light rather than as a smooth airbrush --
  // and measured cell-to-cell, so its rings ride the diorama's own grid.
  if (glowAmt > 0.0) {
    vec2 cc = (floor(sc / cell) + 0.5) * cell;
    float d = length(cc - glowPos) * glowInvR;
    float g = glowAmt * pow(clamp(1.0 - d, 0.0, 1.0), 2.0);
    float lvl = floor(g * 4.0);
    if (g * 4.0 - lvl > 0.5 && parity < 0.5) { lvl += 1.0; }
    c = mix(c, glowColor, min(lvl / 3.0, 1.0) * 0.65);
  }
  // ------- volumetric clouds
  //
  // A short front-to-back ray through a slab of density, sampled on the
  // diorama's cell grid so the mass is painted rather than filtered. The
  // steps uniform caps cost (Quality.cloudSteps); OFF / 1/4 RES sends 0
  // and this whole block is one compare. Coverage from Sky.cloudAmount
  // (fair weather + overcast + CLOUDS row). Not true 3D lighting -- the
  // shade gradient is height in the slab, which is enough for a cel
  // volume and costs no secondary ray.
  //
  // Kept OUTSIDE the block because the god rays below read it: how thick the
  // deck came out at this pixel is exactly the question "can light get
  // through here", and the march has already paid for the answer. At a rung
  // with no march this stays zero, which the rays correctly read as open sky.
  float cloudDens = 0.0;
  if (cloudSteps > 0.5 && cloudAmt > 0.01) {
    vec2 cc = (floor(sc / cell) + 0.5) * cell;
    float y01 = clamp(cc.y / max(edge, 1.0), 0.0, 1.0);
    float x01 = cc.x / max(frameW, 1.0);
    // stay out of the very top cells (sun/moon disc room) and thin out
    // hard against the horizon so the haze band still reads
    float skyWindow = smoothstep(0.02, 0.14, y01) * (1.0 - smoothstep(0.72, 0.98, y01));
    if (skyWindow > 0.01) {
      // threshold drops as coverage rises: more of the noise becomes cloud
      float thr = mix(0.58, 0.22, clamp(cloudAmt, 0.0, 1.0));
      // view ray into the slab: y01 is "looking down the sky", so deeper
      // steps also slide in X with perspective-ish foreshortening
      // camOff is what nails the deck to the WORLD instead of to the screen:
      // without it every sample point is a function of the pixel alone, so
      // walking across a route slid the whole sky along with the camera
      vec2 origin = vec2((x01 - 0.5) * 4.2, y01 * 2.6) + camOff;
      vec2 adv = cloudWind * cloudTime;
      float accum = 0.0;
      float lightAcc = 0.0;
      // fixed 8-iteration loop; early steps ignored when cloudSteps is lower
      for (int i = 0; i < 8; i++) {
        if (float(i) >= cloudSteps) break;
        float t = (float(i) + 0.5) / max(cloudSteps, 1.0);
        // altitude through the slab (base -> top)
        float h = t;
        // parallax: farther samples shift with view angle
        vec2 xz = origin * mix(1.0, 1.55, t) + adv * mix(0.55, 1.15, t)
                + vec2(0.0, t * 0.85);
        float d = cloudDensity(xz, h, thr, cloudEvolve);
        // front-to-back over: later samples only fill remaining air
        float contribute = d * (1.0 - accum) * 0.72;
        accum += contribute;
        // lit weight favors samples high in the slab (sun hits the tops)
        lightAcc += contribute * mix(0.35, 1.0, h);
        if (accum > 0.92) break;
      }
      accum = clamp(accum * skyWindow * (0.55 + 0.70 * cloudAmt), 0.0, 1.0);
      // cel quantize + checker between rungs (the sky's own idiom)
      float lvl = floor(accum * 3.0 + 0.001);
      if (accum * 3.0 - lvl > 0.45 && parity < 0.5) lvl += 1.0;
      float dens = min(lvl / 3.0, 1.0);
      cloudDens = dens;
      float shade = 0.0;
      if (accum > 1e-4) shade = clamp(lightAcc / accum, 0.0, 1.0);
      vec3 cld = mix(cloudShade, cloudLit, shade);
      // twilight: borrow a share of the sun glow so a sunset deck warms
      if (glowAmt > 0.05) {
        cld = mix(cld, glowColor, glowAmt * 0.35 * shade);
      }
      // night: cool and dim, never pure black (still a mass against stars)
      vec3 nightCld = cld * 0.28 + vec3(0.04, 0.05, 0.10);
      cld = mix(cld, nightCld, cloudNight);
      c = mix(c, cld, dens);
    }
  }
  // ------- the far curtain
  //
  // Rain seen from outside it: a wall of shafts standing where the ground
  // runs out. This is the same shower that is about to be on top of you --
  // Weather.curtain leads the streaks on the power ramp, so this fills in
  // while the near field is still a drop here and there, and you get to watch
  // it come.
  //
  // Two noise calls rather than an fbm, and that is a shape decision before
  // it is a cost one: the thing wanted here is TALL AND THIN, and four
  // octaves of isotropic noise gives clouds again. One octave stretched hard
  // in Y, plus a finer one across it, gives columns. It being cheap is why it
  // can also run at the rung where the raymarch is switched off entirely --
  // the bottom rung loses its cloud deck but it does not lose the weather.
  if (curtainAmt > 0.01) {
    vec2 cc = (floor(sc / cell) + 0.5) * cell;
    float y01 = clamp(cc.y / max(edge, 1.0), 0.0, 1.0);
    // Starts mid-sky and thickens all the way down. Deliberately NOT thinned
    // at the horizon the way the deck is: distant rain reaches the ground,
    // and a curtain that faded out just before it got there would read as a
    // smudge hanging in the air.
    float wall = smoothstep(0.34, 0.78, y01);
    if (wall > 0.01) {
      float x01 = cc.x / max(frameW, 1.0);
      // The frequency here is the whole difference between a curtain and a
      // SLAB, and the first pass got it wrong: at 3.4 there are three noise
      // features across a 320-wide frame, which is a hundred pixels per
      // feature -- far too wide to read as anything but a grey band lying on
      // the horizon. Thirteen puts a shaft every twenty-odd pixels, which at
      // this diorama's cell size is a column you can count.
      //
      // The Y coefficients stay small on purpose. That asymmetry IS the
      // shape: sampling fast across X and slowly down Y stretches every
      // noise feature into a vertical streak, which is what falling water
      // looks like from a distance and what no isotropic noise will give you
      // however you threshold it.
      float sx = x01 * 13.0 + camOff.x * 0.5 + cloudEvolve * 0.9;
      float shaft = cloudNoise(vec2(sx, y01 * 0.30 + cloudEvolve * 0.5)) * 0.66
                  + cloudNoise(vec2(sx * 2.7 + 5.0, y01 * 0.55)) * 0.34;
      shaft = smoothstep(0.38, 0.74, shaft);
      float a = shaft * wall * curtainAmt;
      float lvl = floor(a * 3.0);
      if (a * 3.0 - lvl > 0.5 && parity < 0.5) lvl += 1.0;
      c = mix(c, curtainCol, min(lvl / 3.0, 1.0) * 0.82);
    }
  }
  // ------- god rays
  //
  // The light that comes back after the rain, and the reason it comes back in
  // SHAFTS rather than as a wash: rays are what a BROKEN deck does to
  // sunlight. So they are drawn where the deck is thin -- `cloudDens` is
  // already that answer at this pixel, the march paid for it, this reads it.
  // Which is why the whole effect is one atan and one sin, and only during
  // the three minutes after a shower (rayAmt is Weather.afterRain).
  //
  // Where there is no march, cloudDens is zero, the gap term is one, and this
  // degrades to a plain fan off the disc. That is the floor and it is the
  // right floor: fewer rays, still rays.
  //
  // Hard rungs and the same checker as everything else in this file. A smooth
  // ramp here is bloom, and bloom is the one thing this sky may not become.
  if (rayAmt > 0.01 && rayInvR > 0.0) {
    vec2 cc = (floor(sc / cell) + 0.5) * cell;
    vec2 d = cc - rayPos;
    float reach = clamp(1.0 - length(d) * rayInvR, 0.0, 1.0);
    if (reach > 0.01) {
      // wedges around the disc, turning very slowly on the same clock the
      // cloud shape uses -- a fan welded to the sky reads as a decal
      float fan = 0.5 + 0.5 * sin(atan(d.y, d.x) * 9.0 + cloudEvolve * 0.7);
      fan = smoothstep(0.30, 0.92, fan);
      float a = rayAmt * reach * reach * fan * (1.0 - cloudDens);
      float lvl = floor(a * 3.0);
      if (a * 3.0 - lvl > 0.5 && parity < 0.5) lvl += 1.0;
      c = mix(c, rayColor, min(lvl / 3.0, 1.0) * 0.5);
    }
  }
  return vec4(c, alpha);
}
]]

-- ------- the ramp
--
-- The bands as a one-texel-per-band TEXTURE rather than as a uniform array,
-- which is what they used to be: `uniform vec3 bands[8]`, filled from Lua and
-- read through a loop counter. On desktop GL that is as portable as it looks.
-- On Android it was not. The sky's lower bands came back BLACK -- a hard-edged
-- strip running from partway down the gradient to the horizon point, with the
-- moon still drawn correctly over it, and with the haze BELOW the sky (the
-- palest band again, but delivered by love.graphics.clear instead of by the
-- array) landing in exactly the right colour. Same colour, two routes, one of
-- them black: the fault was the array, not the palette.
--
-- Which of the ES failure modes it was hardly matters -- a driver that
-- truncates a partially-filled array, a fragment uniform budget the guaranteed
-- floor of which is sixteen vectors (eight bands plus the glow plus LOVE's own
-- built-ins is over it), a reflection that finds bands[0] and nothing after --
-- because they all have the same shape: slots past the first few read as zero,
-- and zero is black.
--
-- A sampler has none of them. One texture unit replaces eight uniform vectors,
-- there is no array to index and no budget to overrun, and a texel that does
-- not exist cannot read as black because the image is built at exactly the
-- width the shader divides by. Nearest and clamped, so a sample lands on one
-- band's own colour and an out-of-range one lands on the end band rather than
-- on nothing.
--
-- Rebuilt only when the bands move, which is when the clock or the display
-- mode does; Sky.bands drops it as it rebuilds the list it is made from.
local function rampFor(bands)
  if cache.ramp and cache.rampFor == bands then return cache.ramp end
  if not (love.image and love.image.newImageData
          and love.graphics and love.graphics.newImage) then return nil end
  local n = #bands
  if n < 1 then return nil end
  local ok, data = pcall(love.image.newImageData, n, 1)
  if not (ok and data) then return nil end
  for i = 1, n do
    local c = bands[i]
    pcall(data.setPixel, data, i - 1, 0, c[1], c[2], c[3], 1)
  end
  local built, img = pcall(love.graphics.newImage, data)
  if not (built and img) then return nil end
  -- nearest: a band is a flat colour, not something to interpolate between.
  -- clamp: the shader clamps its index too, so this is the second of two
  -- guards against ever sampling off the end -- and it returns the edge band.
  pcall(img.setFilter, img, "nearest", "nearest")
  pcall(img.setWrap, img, "clamp", "clamp")
  cache.ramp, cache.rampFor = img, bands
  return img
end

Sky._rampFor = rampFor            -- named for the suite

local shader = nil            -- nil = untried, false = unavailable

local function getShader()
  if shader == nil then
    shader = false
    if love.graphics and love.graphics.newShader then
      local ok, sh = pcall(love.graphics.newShader, SHADER_SRC)
      if ok and sh then
        shader = sh
      elseif V and V.mod and V.mod.log then
        -- once, and only where it can be read: the fallback below is a sky
        -- without its dither, which is easy to look at and impossible to
        -- diagnose without this line
        V.mod.log:warn("sky shader did not compile: %s -- the bands draw flat, "
                       .. "with no dither between them", tostring(sh))
      end
    end
  end
  return shader or nil
end

Sky._getShader = getShader        -- named for the suite

-- The flat fallback: the same bands as solid rectangles, no checker, on the same
-- quantised edges. For a driver that could not compile the shader -- which is
-- also every headless run.
local function paintFlat(w, h, bands, edge, alpha, cell)
  local g = love.graphics
  local n = #bands
  local prev = 0
  for i = 1, n do
    local cut = (i == n) and math.min(h, math.ceil(edge))
                         or math.floor(i / n * edge / cell + 0.5) * cell
    cut = math.max(prev, math.min(cut, math.min(h, math.ceil(edge))))
    if cut > prev then
      local c = bands[i]
      g.setColor(c[1], c[2], c[3], alpha)
      g.rectangle("fill", 0, prev, w, cut - prev)
    end
    prev = cut
  end
end

-- ------- the discs
--
-- The sun and moon, as cell art: a circle of whole diorama cells with a
-- lighter core, a dithered rim, and -- for the moon -- a few fixed crater
-- cells. Drawn as plain rectangles on the same grid as the sky's own dither,
-- through the same display-mode transform as every palette here, and
-- SCISSORED to the sky's region: the horizon point is where a setting body
-- disappears, so it can never hang under the map at a high pitch.
--
-- SIZED BY THE FRAME, not by the world: a celestial body's apparent size is
-- an angle, so zooming the ground in and out must not swell and shrink the
-- sun with it. The radius is a fraction of the frame height, converted to
-- whole cells so the disc still sits on the diorama's grid -- chunky cells
-- up close, fine ones at survey zoom, the same size body either way.
Sky.DISC_FRAC = 0.030     -- disc radius, as a fraction of the frame height
Sky.DISC_MIN = 3          -- but never fewer cells than this across a radius

-- crater centres as fractions of the radius, so they ride any disc size
local MOON_CRATERS = { { -0.4, -0.2 }, { 0.2, 0.45 }, { 0.5, -0.4 },
                       { -0.15, 0.7 }, { 0.05, 0.05 } }

local function paintDisc(body, edge, cell, w, h)
  local g = love.graphics
  if not (body and body.y and g.setScissor) then return end
  local src = body.moon and DayNight.MOON_COLORS or DayNight.SUN_COLORS
  local shades = PaletteFX.effectiveColors(src) or src
  local twilight = (body.glowAmt or 0) > 0.25 and not body.moon
  local r = math.max(Sky.DISC_MIN,
                     math.floor(h * Sky.DISC_FRAC / cell + 0.5))
  -- the low sun looms: the classic sunset exaggeration, and it reads
  if twilight then r = r + math.max(1, math.floor(r * 0.4)) end
  -- snap the centre to the cell grid, like everything else in this sky
  local bx = math.floor(body.x / cell) * cell + cell / 2
  local by = math.floor(body.y / cell) * cell + cell / 2
  if by - r * cell > edge then return end     -- wholly below the horizon point
  local core = shades[1]
  local main = shades[twilight and 3 or 2]
  local sx, sy, sw, sh = g.getScissor()
  g.setScissor(0, 0, math.ceil(w), math.floor(edge))
  local craterR = math.max(1, math.floor(r / 5))
  for dy = -r, r do
    for dx = -r, r do
      local d = math.sqrt(dx * dx + dy * dy)
      if d <= r + 0.1 then
        local c = d <= r * 0.5 and core or main
        -- dithered rim: the outer ring keeps only one parity of its cells
        local keep = d <= r - 0.9 or (dx + dy) % 2 == 0
        if body.moon then
          for _, cr in ipairs(MOON_CRATERS) do
            local cdx = dx - math.floor(cr[1] * r + 0.5)
            local cdy = dy - math.floor(cr[2] * r + 0.5)
            if cdx * cdx + cdy * cdy <= craterR * craterR then
              c = shades[3]
            end
          end
        end
        if keep then
          g.setColor(c[1] / 255, c[2] / 255, c[3] / 255, 1)
          g.rectangle("fill", bx + dx * cell - cell / 2,
                      by + dy * cell - cell / 2, cell, cell)
        end
      end
    end
  end
  if sx then g.setScissor(sx, sy, sw, sh) else g.setScissor() end
  g.setColor(1, 1, 1, 1)
end

-- ------- the stars
--
-- The one thing the night sky did not have. Six palettes, a moon with
-- craters, a glow, a dither -- and above all of it, nothing. A clear night
-- with an empty sky reads as a dark day, which is the same complaint the
-- shadows answered on the ground.
--
-- They are built the way everything else here is: WHOLE DIORAMA CELLS, on
-- the sky's own grid, through the display mode's palette, scissored to the
-- sky's region. One rectangle each, drawn in the pass that is already open
-- -- there is no second target, no additive buffer and no bloom, because a
-- point of light on a four-colour lattice is a bright texel next to a dark
-- one and nothing else.
--
-- THE FIELD IS FIXED, generated once. A star that moved between frames
-- would be a firefly, and one re-rolled per frame would boil. It is drawn
-- from its own little Park-Miller generator rather than from love.math,
-- deliberately: the game's RNG stream decides encounters, and a cosmetic
-- sky must not advance it -- the same reason nothing else in this file
-- rolls dice.
--
-- BRIGHTNESS IS POSTERISED to four rungs, like the glow. A star fading
-- smoothly in and out is an airbrush; a star that snaps between two
-- brightnesses is what a night sky looks like when it is drawn rather than
-- rendered, and it also means most of the field is skipped outright at the
-- edges of the night instead of drawn at an alpha nobody can see.
Sky.STAR_COLORS = { { 248, 248, 248 }, { 216, 224, 248 },
                    { 184, 192, 232 }, { 144, 160, 208 } }
Sky.STAR_MAX = 96         -- the field's size; Quality.starCount draws a prefix
Sky.STAR_SEED = 20260802
Sky.STAR_TWINKLE = 0.35   -- how much of a star's brightness the twinkle moves
Sky.STAR_HORIZON = 2.2    -- how hard the field fades into the haze at the bottom

-- And one thing that HAPPENS. A star field is scenery; a meteor is an
-- event, and an event is what makes a player stop walking and look up. It
-- carries no state at all -- where it is, and whether there is one, are
-- both answered from the clock, the same way every pixel of the sky shader
-- answers from its own coordinate. So there is nothing to update, nothing
-- to reset on a map change, and nothing to get out of step.
Sky.METEOR_EVERY = 17     -- seconds from one crossing to the next
Sky.METEOR_LEN = 0.055    -- the fraction of that gap a crossing lasts (~0.9s)

-- ------- why the first one did not look like a meteor
--
-- Seven cells, all the same size, all the brightest star colour, stepped
-- 0.035 of the flight apart. That spacing is about six screen pixels and a
-- cell is two to four, so what actually drew was a DOTTED LINE of identical
-- white squares -- and a dotted line of identical squares is the one thing
-- a meteor is not. It reads as a row of stars that happen to be moving.
--
-- Three things separate a streak from a row of dots, and none of them costs
-- anything worth counting (this is at most twenty-odd rectangles, under a
-- second, once every seventeen -- the star field beside it draws ninety-six
-- every frame of the night):
--
--   CONTINUOUS  the samples have to overlap, not sit beside each other. So
--               the step is a third of what it was and there are three
--               times as many.
--   TAPERED     the head is the object and the tail is what it left. A
--               constant width down the whole length is a stick. The cell
--               shrinks along the trail and the head draws a size up.
--   COOLING     a meteor is white at the front and dies out reddish-grey.
--               The palette already carries four star shades ordered
--               brightest-first; walking them down the tail is the whole
--               effect, and it stays inside the mod's own colour dialect.
Sky.METEOR_TAIL = 18      -- samples of trail behind the head
Sky.METEOR_STEP = 0.012   -- flight fraction between samples (they overlap)

-- base brightness per tier, brightest first
local STAR_MAG = { 1.0, 0.85, 0.62, 0.42 }

local starCache = nil

local function starField()
  if starCache then return starCache end
  -- Park-Miller: 16807 * s stays inside a double's exact-integer range,
  -- which the textbook 1103515245 multiplier does not
  local s = Sky.STAR_SEED
  local function rnd()
    s = (16807 * s) % 2147483647
    return s / 2147483647
  end
  local field = {}
  for i = 1, Sky.STAR_MAX do
    local r = rnd()
    local tier = (r < 0.06 and 1) or (r < 0.20 and 2) or (r < 0.50 and 3) or 4
    -- y biased toward the TOP of the sky region: the zenith is where stars
    -- are, and the horizon end is where the haze eats them
    local y = rnd() ^ 1.6
    local fade = (1 - y) * Sky.STAR_HORIZON
    if fade > 1 then fade = 1 end
    field[i] = {
      x = rnd(),
      y = y,
      tier = tier,
      mag = STAR_MAG[tier] * fade,
      phase = rnd() * 6.2832,
      speed = 0.6 + rnd() * 1.7,
    }
  end
  -- brightest first, so drawing a prefix at a cheap rung keeps the sky the
  -- player would actually notice rather than a random half of it
  table.sort(field, function(a, b) return a.mag > b.mag end)
  starCache = field
  return field
end

Sky._starField = starField        -- named for the suite

-- The crossing, if one is happening. Deep night only -- a meteor against a
-- sky with any daylight left in it is a bright dot nobody reads as falling
-- -- and about seven cells while it lasts, which is under a second in every
-- seventeen. The rest of the time this is a modulo and a compare.
local function paintMeteor(w, edge, cell, amount, now)
  if not (amount > 0.5) then return end
  local u = (now % Sky.METEOR_EVERY) / (Sky.METEOR_EVERY * Sky.METEOR_LEN)
  if u > 1 then return end
  -- one seed per crossing index, so a given meteor keeps its own line for
  -- the whole of its flight instead of being re-rolled every frame
  local s = ((math.floor(now / Sky.METEOR_EVERY) * 7919 + Sky.STAR_SEED)
             % 2147483646) + 1
  s = (16807 * s) % 2147483647; local r1 = s / 2147483647
  s = (16807 * s) % 2147483647; local r2 = s / 2147483647
  s = (16807 * s) % 2147483647
  local dir = (s / 2147483647) < 0.5 and -1 or 1
  local x0 = 0.15 + r1 * 0.7 - dir * 0.25
  local y0 = 0.05 + r2 * 0.25
  local g = love.graphics
  local shades = PaletteFX.effectiveColors(Sky.STAR_COLORS) or Sky.STAR_COLORS
  local fade = math.sin(u * math.pi)       -- in and out, never a hard start
  local tail = Sky.METEOR_TAIL
  -- Back to front, so the head is drawn LAST and sits on top of its own
  -- trail rather than under it.
  for k = tail, 0, -1 do
    local uu = u - k * Sky.METEOR_STEP
    if uu > 0 then
      local f = k / tail                    -- 0 at the head, 1 at the end
      -- Brightness falls off fast rather than evenly: a meteor is mostly
      -- head. Squared keeps the front hot and lets the last third of the
      -- trail be the faint smudge it should be.
      local drop = (1 - f) * (1 - f)
      local a = math.floor(fade * drop * amount * 4 + 0.5) / 4
      if a > 0 then
        -- COOLING: brightest shade at the head, walking down the ladder
        -- toward the dim blue-grey at the end.
        local ci = 1 + math.floor(f * 3.99)
        if ci > #shades then ci = #shades end
        local c = shades[ci] or shades[1]
        -- TAPER: the head is a cell and a half, the far end is half of
        -- one. Rounded to whole cells so it stays on the sky's own grid --
        -- a smooth taper here would be the one soft edge in a hard-edged
        -- sky.
        local sizeCells = 1
        if k == 0 then
          sizeCells = 2                     -- the head is the object
        elseif f > 0.62 then
          sizeCells = 1                     -- still a cell; alpha carries it
        end
        local sz = sizeCells * cell
        local sx = math.floor((x0 + dir * uu * 0.5) * w / cell) * cell
        local sy = math.floor((y0 + uu * 0.45) * edge / cell) * cell
        if sx >= 0 and sx + sz <= w and sy >= 0 and sy + sz <= edge then
          g.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a)
          g.rectangle("fill", sx, sy, sz, sz)
        end
      end
    end
  end
end

Sky._paintMeteor = paintMeteor    -- named for the suite

-- `amount` is DayNight.starAmount: how far into the night, already with the
-- weather taken out of it. Zero is the daytime path and costs one compare.
local function paintStars(w, h, edge, cell, amount)
  if not (amount and amount > 0) then return end
  local g = love.graphics
  if not (g and g.rectangle) then return end
  local field = starField()
  local n = math.min(#field, Quality.starCount())
  if n < 1 then return end
  local shades = PaletteFX.effectiveColors(Sky.STAR_COLORS) or Sky.STAR_COLORS
  local now = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
  local tw = Sky.STAR_TWINKLE
  for i = 1, n do
    local st = field[i]
    -- Each star has its OWN point of going out, so the field EMPTIES instead
    -- of dimming as one sheet. `amount` used to be a flat multiplier, which
    -- meant a deck coming over took ninety-six stars down together at exactly
    -- the same rate -- readable as a fade on a layer, which is what it was.
    --
    -- The threshold is mostly the star's own brightness, so the faint ones go
    -- first the way they actually do, with a scatter off its twinkle phase so
    -- the order is not a clean sweep down the tiers. Phase and not a fresh
    -- draw on purpose: it is already uniform on 0..1 and uncorrelated with
    -- magnitude, and taking another number out of starField's generator would
    -- have moved every star in the sky.
    --
    -- At amount = 1 the largest threshold any star can reach is 0.85 and it
    -- still resolves to full brightness, so a clear deep night is the same
    -- sky it has always been. Everything below that is where the drama went.
    local gate = 0.55 * (1 - st.mag) + 0.30 * (st.phase / 6.2832)
    local live = amount - gate
    if live > 0 then
      live = live / math.max(0.05, 1 - gate)
      if live > 1 then live = 1 end
      -- the twinkle rides its own phase and speed, so the field shimmers
      -- rather than pulsing as one thing
      local a = live * st.mag
                  * (1 - tw + tw * (0.5 + 0.5 * math.sin(now * st.speed
                                                         + st.phase)))
      -- four rungs, like the glow: this is also what skips most of the field
      -- at the ends of the night instead of drawing it invisible
      a = math.floor(a * 4 + 0.5) / 4
      if a > 0 then
        local sy = math.floor(st.y * edge / cell) * cell
        if sy < edge then
          local c = shades[st.tier] or shades[#shades]
          g.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a)
          g.rectangle("fill", math.floor(st.x * w / cell) * cell, sy,
                      cell, cell)
        end
      end
    end
  end
  paintMeteor(w, edge, cell, amount, now)
end

Sky._paintStars = paintStars      -- named for the suite

-- ------- low fog (cel bands + checker dither near the horizon)
--
-- Not a depth fog and not particles: a short stack of flat pale bands at
-- the BOTTOM of the sky region, with the same xadrez dither the sky uses
-- between its own bands. Dawn/dusk density from Sky.fogAmount; band count
-- from Quality.fogBands so the phone rung can turn it off entirely.

local FOG_COL = { 0.78, 0.82, 0.90 }

local function paintFog(w, edge, cell, amount, nBands)
  if amount <= 0 or nBands <= 0 then return end
  local g = love.graphics
  local fogH = math.floor(edge * (0.18 + 0.32 * amount))
  if fogH < cell * 2 then fogH = cell * 2 end
  local y0 = math.max(0, math.floor(edge - fogH))
  local bandH = math.max(cell, math.floor(fogH / nBands))
  local aBase = 0.18 + 0.42 * amount
  -- one solid rect per band + a sparse checker second pass (cell*2 stride)
  -- so the phone rung never pays a per-pixel loop over the sky region
  for i = 0, nBands - 1 do
    local y = y0 + i * bandH
    local h = (i == nBands - 1) and (edge - y) or bandH
    if h <= 0 then break end
    local a = aBase * (0.45 + 0.55 * ((i + 1) / nBands))
    g.setColor(FOG_COL[1], FOG_COL[2], FOG_COL[3], a * 0.50)
    g.rectangle("fill", 0, y, w, h)
    g.setColor(FOG_COL[1], FOG_COL[2], FOG_COL[3], a)
    local step = cell * 2
    for yy = y, y + h - 1, step do
      local x0 = ((math.floor(yy / cell) + i) % 2) * cell
      for xx = x0, w - 1, step do
        g.rectangle("fill", xx, yy, cell, cell)
      end
    end
  end
  g.setColor(1, 1, 1, 1)
end

-- ------- rainbow (post-rain, temporary, painted as hard colour arcs)
--
-- Four flat spectral steps, no gradient, no bloom. Geometry is a set of
-- concentric arc strips in the upper-right of the sky region so it reads
-- as a rainbow without a mesh or a second render target.

local RAINBOW = {
  { 0.90, 0.22, 0.22 },
  { 0.95, 0.55, 0.12 },
  { 0.95, 0.90, 0.18 },
  { 0.22, 0.72, 0.28 },
  { 0.22, 0.42, 0.90 },
  { 0.55, 0.22, 0.75 },
}

local function paintRainbow(w, edge, cell, amount)
  if amount <= 0 then return end
  if Quality.rainbow and not Quality.rainbow() then return end
  local g = love.graphics
  -- centre below the horizon so only the upper arc shows
  local cx = math.floor(w * 0.55)
  local cy = math.floor(edge + edge * 0.15)
  local rOuter = math.floor(edge * 0.95)
  local ring = math.max(cell * 2, math.floor(edge * 0.045))
  local a = amount >= 0.5 and 0.55 or 0.30
  -- stride cell*2: rainbow is a short-lived ornament, not a full-sky fill
  local step = cell * 2
  for i, col in ipairs(RAINBOW) do
    local r1 = rOuter - (i - 1) * ring
    local r0 = r1 - ring
    if r0 < cell then break end
    g.setColor(col[1], col[2], col[3], a)
    for y = 0, edge - 1, step do
      for x = 0, w - 1, step do
        local dx = x + cell - cx
        local dy = y + cell - cy
        local d2 = dx * dx + dy * dy
        if d2 >= r0 * r0 and d2 < r1 * r1 then
          if ((x / cell) + (y / cell) + i) % 2 < 1 then
            g.rectangle("fill", x, y, cell, cell)
          end
        end
      end
    end
  end
  g.setColor(1, 1, 1, 1)
end

Sky._paintFog = paintFog
Sky._paintRainbow = paintRainbow

-- Shaderless cloud stand-in: a handful of cel puffs on the cell grid so a
-- driver that refused the sky shader still shows volume rather than a bare
-- ramp. Not the raymarch -- just enough mass to read as "there are clouds".
local function paintCloudsCPU(w, edge, cell, amount)
  if amount <= 0 or edge < cell * 4 then return end
  local g = love.graphics
  local t = 0
  if love.timer and love.timer.getTime then t = love.timer.getTime() end
  local wx, wz = 0.94, 0.34
  if Wind and Wind.DIR then
    wx = tonumber(Wind.DIR[1]) or wx
    wz = tonumber(Wind.DIR[2]) or wz
  end
  local drift = t * 12
  local n = 5 + math.floor(amount * 7)
  local litA = 0.35 + 0.40 * amount
  for i = 1, n do
    local seed = i * 97.13
    local cx = ((seed * 13.7 + drift * wx) % (w + 80)) - 40
    local cy = edge * (0.18 + (seed * 0.017) % 0.45)
    local rx = cell * (4 + (seed * 0.03) % 6) * (0.7 + amount)
    local ry = cell * (2 + (seed * 0.02) % 3) * (0.7 + amount)
    -- two rungs: body + lighter top (fake volume)
    g.setColor(0.55, 0.58, 0.68, litA * 0.85)
    g.rectangle("fill",
      math.floor((cx - rx) / cell) * cell,
      math.floor((cy - ry * 0.4) / cell) * cell,
      math.floor(rx * 2 / cell) * cell,
      math.floor(ry * 1.2 / cell) * cell)
    g.setColor(0.94, 0.96, 0.99, litA)
    g.rectangle("fill",
      math.floor((cx - rx * 0.7) / cell) * cell,
      math.floor((cy - ry) / cell) * cell,
      math.floor(rx * 1.4 / cell) * cell,
      math.floor(ry * 0.85 / cell) * cell)
  end
  g.setColor(1, 1, 1, 1)
end

Sky._paintCloudsCPU = paintCloudsCPU

-- Paint the sky into the bound canvas, filling it from the top edge down to
-- `horizonY` (or to SPAN of the frame when the horizon is out of it).
--
-- `cell` is the diorama's pixel size in canvas pixels -- the pass's own
-- pixels-per-world-pixel, handed in every frame so a zoom lands immediately.
--
-- `body` is the sun or moon to hang, already projected to canvas pixels by
-- the caller's own camera (Voxel3D.skyBody), with the twilight glow riding
-- along; nil hangs nothing and warms nothing.
--
-- Returns false when there is nothing to paint, in which case the caller's flat
-- fill is the whole sky. That fill is the palest band, so a frame that declines
-- this looks like a hazy day rather than like a bug.
-- `camX`/`camY` are the camera in world pixels, and they are optional: the
-- cloud deck uses them for parallax (Sky.CLOUD_PARALLAX), and nil is the old
-- behaviour of a deck pinned to the screen rather than to the map.
function Sky.paint(w, h, sky, horizonY, cell, body, camX, camY)
  local bands = sky and sky.bands
  if not (bands and bands[1]) then return false end
  if not (w and h and w > 0 and h > 0) then return false end
  local g = love.graphics
  if not (g and g.rectangle) then return false end
  local edge = Sky.region(h, horizonY)
  if not edge then return false end
  local alpha = sky[4] or 1
  cell = math.max(1, math.floor((cell or 1) + 0.5))

  -- State to put aside. The scene's shader is one, and the blend mode another --
  -- a pass that left "replace" behind would make the fade-in strength meaningless
  -- -- but the DEPTH MODE is the one that would break the frame: a rectangle
  -- drawn under the pass's own ("lequal", true) stamps itself across the depth
  -- buffer at the near plane and hides the entire world behind the sky.
  local prevShader = g.getShader and g.getShader() or nil
  local cmp, write
  if g.getDepthMode then cmp, write = g.getDepthMode() end
  if g.setDepthMode then g.setDepthMode("always", false) end
  local blend, blendAlpha
  if g.getBlendMode then blend, blendAlpha = g.getBlendMode() end
  if g.setBlendMode then g.setBlendMode("alpha") end

  local glowAmt = body and not body.moon and (body.glowAmt or 0) or 0
  local cloudAmt = Sky.cloudAmount()
  local cloudSteps = 0
  if Quality.cloudSteps then
    local okS, ns = pcall(Quality.cloudSteps)
    if okS then cloudSteps = ns or 0 end
  end
  if cloudAmt <= 0 then cloudSteps = 0 end
  local sh = getShader()
  local ramp = sh and rampFor(bands)
  if not ramp then sh = nil end       -- no ramp, no gradient: paint it flat
  if sh then
    local sent = pcall(function()
      -- the bands arrive as a texture, one texel each, and `count` is that
      -- texture's width -- see rampFor for why they are not a uniform array
      sh:send("ramp", ramp)
      sh:send("count", #bands)
      sh:send("edge", edge)
      sh:send("cell", cell)
      sh:send("start", Sky.DITHER and Sky.DITHER_START or 2)
      sh:send("alpha", alpha)
      sh:send("glowAmt", glowAmt)
      if glowAmt > 0 then
        local gc = body.glowColor or { 248, 224, 168 }
        sh:send("glowPos", { body.x, body.y })
        sh:send("glowInvR", 1 / math.max(1, w * 0.55))
        sh:send("glowColor", { gc[1] / 255, gc[2] / 255, gc[3] / 255 })
      else
        -- still bind so the uniform is never stale from a prior frame
        sh:send("glowPos", { 0, 0 })
        sh:send("glowInvR", 0)
        sh:send("glowColor", { 1, 1, 1 })
      end
      -- volumetric clouds: always send (steps 0 is the off switch)
      sh:send("cloudAmt", cloudAmt)
      sh:send("cloudSteps", cloudSteps)
      sh:send("cloudNight", Sky.cloudNight())
      sh:send("frameW", w)
      local t = 0
      if love.timer and love.timer.getTime then t = love.timer.getTime() end
      sh:send("cloudTime", t * 0.12)
      local wx, wz = 0.94, 0.34
      if Wind and Wind.DIR then
        wx = tonumber(Wind.DIR[1]) or wx
        wz = tonumber(Wind.DIR[2]) or wz
      end
      local len = math.sqrt(wx * wx + wz * wz)
      if len > 1e-4 then wx, wz = wx / len, wz / len end
      sh:send("cloudWind", { wx, wz })
      -- overcast cools the deck toward DayNight's grey; clear day is white
      local over = tonumber(DayNight.overcast) or 0
      if over < 0 then over = 0 elseif over > 1 then over = 1 end
      local lit = {
        0.96 - 0.18 * over,
        0.97 - 0.16 * over,
        0.99 - 0.10 * over,
      }
      local shade = {
        0.55 - 0.08 * over,
        0.58 - 0.06 * over,
        0.68 - 0.02 * over,
      }
      sh:send("cloudLit", lit)
      sh:send("cloudShade", shade)
      -- the deck's own two clocks: one carries it, one changes it
      sh:send("cloudEvolve", t * Sky.CLOUD_EVOLVE)
      local px = Sky.CLOUD_PARALLAX
      -- y at a fraction of x: in this camera the vertical axis is depth, and
      -- walking INTO the scene should shift the sky less than walking across
      sh:send("camOff", { (tonumber(camX) or 0) * px,
                          (tonumber(camY) or 0) * px * 0.6 })

      -- the far curtain, and its colour: the haze band pulled down toward the
      -- deck's shade rather than a new colour introduced to the frame -- a
      -- wall of rain is the same air, thicker
      local curtain = 0
      local okc, ca = pcall(Weather.curtain)
      if okc then curtain = tonumber(ca) or 0 end
      if curtain < 0 then curtain = 0 elseif curtain > 1 then curtain = 1 end
      sh:send("curtainAmt", curtain)
      local hz = bands[#bands]
      sh:send("curtainCol", { hz[1] * 0.45 + 0.16,
                              hz[2] * 0.45 + 0.17,
                              hz[3] * 0.45 + 0.21 })

      -- god rays: the post-rain spell, gated on there being a SUN up to throw
      -- them. A moon does not, and afterRain alone would have lit a fan off
      -- the moon disc at two in the morning -- which is the exact mistake the
      -- glow already made once (see DayNight.glow).
      local rayAmt = 0
      if body and not body.moon and body.x and body.y then
        rayAmt = afterRainAmt()
      end
      sh:send("rayAmt", rayAmt)
      if rayAmt > 0 then
        local rc = body.glowColor or { 248, 232, 176 }
        sh:send("rayPos", { body.x, body.y })
        sh:send("rayInvR", 1 / math.max(1, w * 0.85))
        sh:send("rayColor", { rc[1] / 255, rc[2] / 255, rc[3] / 255 })
      else
        -- bind anyway: a stale rayPos from the frame the sun set on would
        -- hang a fan in the dark
        sh:send("rayPos", { 0, 0 })
        sh:send("rayInvR", 0)
        sh:send("rayColor", { 1, 1, 1 })
      end
    end)
    if sent then
      g.setShader(sh)
      g.setColor(1, 1, 1, 1)
      g.rectangle("fill", 0, 0, w, math.min(h, math.ceil(edge)))
      g.setShader()
    else
      sh = nil
    end
  end
  if not sh then
    paintFlat(w, h, bands, edge, alpha, cell)
    -- shaderless path still gets a cheap cel puff field so OFF is the only
    -- way to a bare sky, not a driver refusal
    if cloudAmt > 0.05 and cloudSteps > 0 then
      paintCloudsCPU(w, math.min(h, edge), cell, cloudAmt)
    end
  end

  -- fog and rainbow sit ON the bands, UNDER stars/disc: atmosphere of the
  -- day, not night ornaments. Map is optional (density still works without).
  local map = sky and sky.map
  local fogAmt = Sky.fogAmount(map)
  local nFog = 0
  if Quality.fogBands then
    local okf, nf = pcall(Quality.fogBands)
    if okf then nFog = nf or 0 end
  end
  if fogAmt > 0 and nFog > 0 then
    paintFog(w, math.min(h, edge), cell, fogAmt, nFog)
  end
  local ar = afterRainAmt()
  if ar > 0 then
    paintRainbow(w, math.min(h, edge), cell, ar)
  end

  -- the stars go over the bands and UNDER the moon -- a body that crossed
  -- one would be behind it, which is the one thing a sky may not do -- and
  -- like the disc they are plain rectangles, so they survive a frame the
  -- shader could not build
  paintStars(w, math.min(h, edge), math.min(h, edge), cell,
             DayNight.starAmount())
  -- the disc goes over the glow, under nothing: plain rectangles, so it is
  -- there whether or not the shader built
  paintDisc(body, math.min(h, edge), cell, w, h)
  g.setColor(1, 1, 1, 1)

  if g.setBlendMode and blend then g.setBlendMode(blend, blendAlpha) end
  if g.setDepthMode then g.setDepthMode(cmp or "always", write or false) end
  if prevShader and g.setShader then g.setShader(prevShader) end
  return true
end

-- Drop the compiled shader (window resize, hot reload), so a re-created graphics
-- context builds a new one instead of drawing with a handle from the old. The
-- ramp is a GPU object on the same context and goes with it.
function Sky.invalidate()
  shader = nil
  if cache.ramp and cache.ramp.release then pcall(cache.ramp.release, cache.ramp) end
  cache.ramp, cache.rampFor = nil, nil
end

return Sky
