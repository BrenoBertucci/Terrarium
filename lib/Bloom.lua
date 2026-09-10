-- Voxel world mode: BLOOM, RAYS and the GRADE -- what a bright thing does
-- to the frame around it, and what the frame is finished with.
--
-- A flame drawn as a card is a yellow drawing; a flame with its light
-- spilling into the frame around it is a light. The scene shader cannot do
-- that (a fragment knows nothing of its neighbours), so this is a pass over
-- the finished diorama canvas, in three parts:
--
--   BLOOM   the bright part of the picture, pulled out and shrunk in one
--           draw, blurred with the tilt-shift's own gaussian.
--   RAYS    from each lantern's place on the canvas (the caller projects
--           them), every pixel marches TOWARD the light across the bright
--           image and sums what it crosses with a decay -- the sun-shaft
--           march, pointed at a candle. Where the bright image is a flame,
--           the room around it gets spokes of light; in the mist, that
--           reads as the air carrying it.
--   GRADE   the finish: the bloom and the rays added over the frame, a
--           filmic tone curve (the ACES fit) so a lantern's core rolls off
--           to white instead of clipping, a vignette, and a breath of
--           grain. Written back onto the canvas that came in, so whatever
--           draws on it next (the 2D overlay, the radar) is unaffected.
--
-- Threshold and strength are the caller's, because what counts as a light
-- is a fact about the room: in the crypt (lib/Crypt.lua, the CRYPT-FX row)
-- the flames, the lantern glass and the wisps are the only things over the
-- line, and the stone under a pool stays under it.
--
-- Cost: the bright pass and the rays at a quarter of the panel each way,
-- the two blurs at that size, and two full-panel draws (the grade and the
-- copy back) -- about the tilt-shift's price.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local RenderTarget = V.require("RenderTarget")

local Bloom = {}

local BRIGHT = [[
  uniform float threshold;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 c = Texel(tex, tc);
    float lum = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
    // a soft knee rather than a cut: a light does not switch on at a
    // luminance, it comes up through one
    float k = smoothstep(threshold, threshold + 0.28, lum);
    return vec4(c.rgb * k, 1.0) * color;
  }
]]

-- the march: SAMPLES steps from the pixel toward each light, the weight
-- decaying along the way, the lights summed
local RAYS = [[
  #define SAMPLES 14
  uniform vec2 light0;
  uniform vec2 light1;
  uniform vec2 light2;
  uniform vec2 light3;
  uniform float nLights;
  uniform float decay;
  uniform float weight;
  vec3 march(Image tex, vec2 tc, vec2 light) {
    vec2 d = (light - tc) / float(SAMPLES);
    vec3 sum = vec3(0.0);
    float illum = 1.0;
    vec2 p = tc;
    for (int i = 0; i < SAMPLES; i++) {
      p += d;
      sum += Texel(tex, p).rgb * illum;
      illum *= decay;
    }
    return sum;
  }
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec3 sum = vec3(0.0);
    if (nLights > 0.5) sum += march(tex, tc, light0);
    if (nLights > 1.5) sum += march(tex, tc, light1);
    if (nLights > 2.5) sum += march(tex, tc, light2);
    if (nLights > 3.5) sum += march(tex, tc, light3);
    return vec4(sum * (weight / float(SAMPLES)), 1.0) * color;
  }
]]

-- the tilt-shift's 9-tap gaussian in five fetches (see lib/TiltShift.lua
-- for why the taps sit where they do)
local BLUR = [[
  uniform vec2 dir;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 sum = Texel(tex, tc) * 0.2270270270;
    sum += (Texel(tex, tc + 1.3846153846 * dir)
            + Texel(tex, tc - 1.3846153846 * dir)) * 0.3162162162;
    sum += (Texel(tex, tc + 3.2307692308 * dir)
            + Texel(tex, tc - 3.2307692308 * dir)) * 0.0702702703;
    return sum * color;
  }
]]

local GRADE = [[
  uniform Image glow;        // the blurred bright image, with the rays in it
  uniform float glowK;
  uniform float exposure;
  uniform float vignette;
  uniform float grain;
  uniform float time;
  uniform float tone;        // the S-curve's strength, 0 = leave the curve alone
  uniform float split;       // split tone: darks cool, lights warm; 0 = none
  // Contrast that keeps black black: a smoothstep S-curve mixed in by
  // `tone`, plus a soft shoulder over 1.0 so a flame's core rolls off to
  // white instead of clipping. (The ACES fit was tried here and lifted the
  // whole crypt to grey: it gains the darks by half again, and a crypt is
  // made of darks.)
  vec3 curve(vec3 x) {
    vec3 s = x * x * (3.0 - 2.0 * x);
    vec3 lo = clamp(x, 0.0, 1.0);
    vec3 c = mix(lo, s, tone);
    vec3 over = max(x - 1.0, 0.0);
    return c + over / (1.0 + over);
  }
  // ------- WHY THIS IS NOT `fract(sin(dot(p, k)) * 43758)`
  //
  // It was, and on a Mali-G615 it turned every interior BLACK while the
  // overworld stayed perfect.  This shader is the only one in the file that
  // touches `sc` -- BRIGHT, RAYS and BLUR all work in normalised `tc` -- and
  // `sc` here is a pixel of the PRESENT canvas, which is the whole panel.
  //
  // LOVE emits `precision mediump float;` at the top of every GLES pixel
  // shader, and mediump on this part is fp16, whose largest finite value is
  // 65504.  On the reporter's 1220x2712 panel:
  //
  //     dot(sc, vec2(12.9898, 78.233)) = 1220*12.9898 + 2712*78.233
  //                                    = 15848 + 212168 = 228016
  //
  // -- three and a half times the ceiling before the `time` offset is even
  // added.  The argument saturates to +inf, `sin(+inf)` is NaN, and the NaN
  // walks straight out through `rgb +=` into the frame.  `grain` cannot save
  // it either: NaN * 0.0 is still NaN.
  //
  // The desktop never sees it -- there the shader is `#version 330`, `float`
  // is fp32, and 228016 is an unremarkable number.  That is the whole of why
  // these rooms are perfect on the PC and black on the phone.
  //
  // The replacement is the interleaved gradient noise from lib/RayFX.lua,
  // which was written for this exact driver class and whose comment already
  // spells out the same hazard -- the fix simply never reached this file.
  // Its constants are small by construction: the same panel corner reaches
  // 1220*0.06711 + 2712*0.00584 = 98, and every step after it is inside a
  // fract().  Its blue-noise-ish spectrum is the better grain anyway.
  //
  // NOT fixed by raising the precision: `precision highp float;` in a LOVE
  // pixel shader re-declares effect()'s parameters against the mediump
  // forward declaration LOVE concatenates ahead of this source, and that is
  // what took the 3D mode off the air in 1.34.0.  The arithmetic is what has
  // to be safe.
  float hash(vec2 p) {
    p = floor(p);
    return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
  }
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 c = Texel(tex, tc);
    vec3 rgb = c.rgb + Texel(glow, tc).rgb * glowK;
    rgb *= exposure;
    rgb = curve(rgb);
    // the split tone: what is dark leans to the crypt's cool violet,
    // what is lit leans to the flame -- the room's two lights, agreed on
    // by the whole frame rather than met surface by surface
    float l = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 lean = mix(vec3(0.90, 0.92, 1.10), vec3(1.08, 1.00, 0.90),
                    smoothstep(0.12, 0.70, l));
    rgb *= mix(vec3(1.0), lean, split);
    // the vignette: the corners fall away, the middle untouched
    vec2 q = tc - 0.5;
    float d = dot(q, q) * 2.4;
    rgb *= 1.0 - vignette * smoothstep(0.25, 1.15, d);
    // grain: a breath of it, anchored to the screen, alive
    rgb += (hash(sc + vec2(time * 17.0, time * 31.0)) - 0.5) * grain;
    return vec4(rgb, c.a) * color;
  }
]]

local sBright, sRays, sBlur, sGrade = nil, nil, nil, nil
local ping, pong, cw, ch = nil, nil, 0, 0
local full, fw, fh = nil, 0, 0

Bloom.lastPasses = 0
Bloom.lastRays = 0
Bloom.lastError = nil

local function make(src, name)
  local ok, sh = pcall(love.graphics.newShader, src)
  if not ok then
    Bloom.lastError = name .. ": " .. tostring(sh)
    return false
  end
  return sh
end

local function shaders()
  if sBright == nil then sBright = make(BRIGHT, "bright") end
  if sRays == nil then sRays = make(RAYS, "rays") end
  if sBlur == nil then sBlur = make(BLUR, "blur") end
  if sGrade == nil then sGrade = make(GRADE, "grade") end
  return sBright or nil, sRays or nil, sBlur or nil, sGrade or nil
end

local function canvases(w, h)
  if not ping or cw ~= w or ch ~= h then
    local a = RenderTarget.new(w, h)
    if not a then return nil end
    local b = RenderTarget.new(w, h)
    if not b then return nil end
    a:setFilter("linear", "linear")
    b:setFilter("linear", "linear")
    a:setWrap("clamp", "clamp")
    b:setWrap("clamp", "clamp")
    ping, pong, cw, ch = a, b, w, h
  end
  return ping, pong
end

local function fullCanvas(w, h)
  if full and fw == w and fh == h then return full end
  local c = RenderTarget.new(w, h)
  if not c then return nil end
  c:setFilter("nearest", "nearest")
  full, fw, fh = c, w, h
  return c
end

-- Finish `canvas` in place. `opts`:
--   threshold, strength   the bloom (luminance a light starts at, share)
--   div, passes           the reduction the blur runs at, blur rounds
--   lights                { {u, v}, ... } lantern places on the canvas, 0..1
--   rays                  { decay, weight } for the march; nil = no rays
--   grade                 { exposure, vignette, grain, tone } ; nil = add only
-- Returns the number of passes drawn, 0 when nothing could run.
function Bloom.apply(canvas, opts)
  Bloom.lastPasses = 0
  Bloom.lastRays = 0
  if not canvas then return 0 end
  opts = opts or {}
  local sb, sr, sl, sg = shaders()
  if not (sb and sl) then return 0 end
  local w, h = canvas:getDimensions()
  local div = math.max(1, tonumber(opts.div) or 4)
  local bw = math.max(1, math.floor(w / div))
  local bh = math.max(1, math.floor(h / div))
  local a, b = canvases(bw, bh)
  if not a then return 0 end
  local strength = tonumber(opts.strength) or 0.8
  local rounds = math.max(1, math.floor(tonumber(opts.passes) or 1))
  local lights = opts.lights or {}
  local rays = opts.rays
  local grade = opts.grade
  local out = (grade and sg) and fullCanvas(w, h) or nil

  local g = love.graphics
  local prevBlend, prevAlpha = g.getBlendMode()
  local prevCanvas = g.getCanvas()
  local prevShader = g.getShader()
  local r, gg, bb, al = g.getColor()
  local passes = 0
  canvas:setFilter("linear", "linear")
  local ok, err = pcall(function()
    g.setColor(1, 1, 1, 1)
    -- the bright pass, shrinking on the way in
    g.setCanvas(a)
    g.clear(0, 0, 0, 0)
    g.setBlendMode("replace", "premultiplied")
    g.setShader(sb)
    pcall(sb.send, sb, "threshold", tonumber(opts.threshold) or 0.75)
    g.draw(canvas, 0, 0, 0, bw / w, bh / h)
    passes = passes + 1
    -- the rays, off the bright image, added back into it
    if sr and rays and #lights > 0 then
      g.setCanvas(b)
      g.clear(0, 0, 0, 0)
      g.setShader(sr)
      for i = 1, 4 do
        local l = lights[i]
        pcall(sr.send, sr, "light" .. (i - 1), { l and l[1] or 0, l and l[2] or 0 })
      end
      pcall(sr.send, sr, "nLights", math.min(#lights, 4))
      pcall(sr.send, sr, "decay", tonumber(rays.decay) or 0.9)
      pcall(sr.send, sr, "weight", tonumber(rays.weight) or 0.5)
      g.draw(a)
      g.setCanvas(a)
      g.setShader()
      g.setBlendMode("add", "alphamultiply")
      g.draw(b)
      g.setBlendMode("replace", "premultiplied")
      passes = passes + 2
      Bloom.lastRays = math.min(#lights, 4)
    end
    -- the blur, horizontal then vertical, on the small canvases
    g.setShader(sl)
    for _ = 1, rounds do
      g.setCanvas(b)
      pcall(sl.send, sl, "dir", { 1 / bw, 0 })
      g.draw(a)
      g.setCanvas(a)
      pcall(sl.send, sl, "dir", { 0, 1 / bh })
      g.draw(b)
      passes = passes + 2
    end
    if out then
      -- the grade: the frame and its glow through the tone curve, into
      -- the spare full canvas, then back over the original as a copy
      g.setCanvas(out)
      g.setShader(sg)
      pcall(sg.send, sg, "glow", a)
      pcall(sg.send, sg, "glowK", strength)
      pcall(sg.send, sg, "exposure", tonumber(grade.exposure) or 1)
      pcall(sg.send, sg, "vignette", tonumber(grade.vignette) or 0)
      pcall(sg.send, sg, "grain", tonumber(grade.grain) or 0)
      pcall(sg.send, sg, "tone", tonumber(grade.tone) or 0.35)
      pcall(sg.send, sg, "split", tonumber(grade.split) or 0)
      pcall(sg.send, sg, "time",
            ((love.timer and love.timer.getTime and love.timer.getTime()) or 0) % 100)
      g.draw(canvas)
      g.setCanvas(canvas)
      g.setShader()
      g.draw(out)
      passes = passes + 2
    else
      -- no grade: the glow added over the frame, as it was
      g.setCanvas(canvas)
      g.setShader()
      g.setBlendMode("add", "alphamultiply")
      g.setColor(strength, strength, strength, 1)
      g.draw(a, 0, 0, 0, w / bw, h / bh)
      passes = passes + 1
    end
  end)
  g.setShader(prevShader)
  g.setCanvas(prevCanvas)
  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  g.setColor(r, gg, bb, al)
  canvas:setFilter("nearest", "nearest")
  if not ok then
    Bloom.lastError = tostring(err)
    return 0
  end
  Bloom.lastPasses = passes
  return passes
end

-- Drop the GPU objects (window resize, hot reload).
function Bloom.invalidate()
  for _, c in ipairs({ ping, pong, full }) do
    if c and c.release then pcall(c.release, c) end
  end
  ping, pong, cw, ch = nil, nil, 0, 0
  full, fw, fh = nil, 0, 0
end

return Bloom
