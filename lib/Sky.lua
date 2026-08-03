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
-- as four stripes. No clouds, nothing moving.
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
local PaletteFX = require("src.render.PaletteFX")

local Sky = {}

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

function Sky.bands()
  local pal = DayNight.palette()
  local shades = PaletteFX.effectiveColors(pal) or pal
  local n = math.min(#shades, #pal, Sky.MAX_BANDS)
  local key, k = cache.key, 0
  local same = cache.bands ~= nil and #cache.bands == n
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
    bands[i] = { c[1] / 255, c[2] / 255, c[3] / 255 }
  end
  cache.bands = bands
  return bands
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

// Band `i`, read from its own texel centre. The index is clamped rather than
// trusted: `pos` below can land exactly on `count` when the arithmetic is
// carried at mediump -- which is the fragment default on GLSL ES -- and a
// sample past the last band must be the last band, not whatever is off the
// end of the image.
vec3 bandAt(float i) {
  return Texel(ramp, vec2((clamp(i, 0.0, count - 1.0) + 0.5) / count, 0.5)).rgb;
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
Sky.METEOR_TAIL = 6       -- cells of trail behind the head

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
  local c = shades[1]
  local fade = math.sin(u * math.pi)       -- in and out, never a hard start
  for k = 0, Sky.METEOR_TAIL do
    local uu = u - k * 0.035
    if uu > 0 then
      local a = math.floor(fade * (1 - k / (Sky.METEOR_TAIL + 1)) * amount
                           * 4 + 0.5) / 4
      if a > 0 then
        local sx = math.floor((x0 + dir * uu * 0.5) * w / cell) * cell
        local sy = math.floor((y0 + uu * 0.45) * edge / cell) * cell
        if sx >= 0 and sx < w and sy >= 0 and sy < edge then
          g.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a)
          g.rectangle("fill", sx, sy, cell, cell)
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
    -- the twinkle rides its own phase and speed, so the field shimmers
    -- rather than pulsing as one thing
    local a = amount * st.mag
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
  paintMeteor(w, edge, cell, amount, now)
end

Sky._paintStars = paintStars      -- named for the suite

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
function Sky.paint(w, h, sky, horizonY, cell, body)
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
  if not sh then paintFlat(w, h, bands, edge, alpha, cell) end
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
