// TERRARIUM CRT -- one source, four passes, chosen by a #define that
// lib/CRT.lua (and tools/crt_lab, which runs this same file in WebGL 1)
// puts in front of it:
//
//   PASS_SIGNAL  the electronics. One texel per sample of one SCANLINE: the
//                frame is read along each line the beam will draw, the way a
//                television receives it -- RGB through a bandwidth limit, or
//                encoded onto an NTSC subcarrier and decoded again (COMPOSITE),
//                with the snow, ghost, hum and jitter of an aerial (RF) and
//                the phosphor still glowing from the frame before (persistence).
//   PASS_GLOW    the light inside the glass: the scanline image, small and
//                blurred, for halation and for the screen lighting the bezel.
//   PASS_TUBE    the tube. Curvature, the beam's spot (wider when it is
//                brighter), convergence, the phosphor mask, halation, the
//                vignette, the room reflected in the glass, and the power-on,
//                power-off and degauss moments.
//   PASS_BEZEL   the cabinet around the tube, drawn once per size and style.
//
// Written from the physics and from looking at macro photographs, not from
// anybody's shader code. The ideas owe a lot to crt-royale, guest-advanced,
// koko-aio, Mega Bezel, NTSC-adaptive, Blargg's NTSC filters and
// cool-retro-term, all of them GPL/LGPL and NONE of them copied here; the
// barrel-warp formula and the three mask layouts are the ones Timothy Lottes
// put in the public domain with crt-lottes. Full credits: assets/crt/LICENSE.md.
//
// GLSL ES 1.00 throughout (tools/essl1_check.py checks this file too):
// constant loop bounds, no array initialisers, no integer arithmetic, no
// derivatives, and every number that can reach the thousands (a pixel
// coordinate, a subcarrier phase) carries CRTHP -- because LOVE compiles the
// fragment stage at mediump, which is fp16 on a phone, and a phosphor mask
// computed at fp16 is not a mask, it is television interference of its own.
// `highp` is only legal on GLES when the driver says so, and on desktop LOVE
// defines it to nothing, so the macro below asks both questions.

#if defined(GL_ES) && defined(GL_FRAGMENT_PRECISION_HIGH)
#define CRTHP highp
#else
#define CRTHP
#endif

// NTSC's own matrix. The signal is gamma-encoded on the wire, so this works
// on gamma values, exactly like the encoder in a console's video chip.
vec3 toYIQ(vec3 c) {
  return vec3(dot(c, vec3(0.299, 0.587, 0.114)),
              dot(c, vec3(0.596, -0.274, -0.322)),
              dot(c, vec3(0.211, -0.523, 0.312)));
}
vec3 toRGB(vec3 y) {
  return vec3(dot(y, vec3(1.0, 0.956, 0.621)),
              dot(y, vec3(1.0, -0.272, -0.647)),
              dot(y, vec3(1.0, -1.106, 1.703)));
}

// =========================================================================
#ifdef PASS_SIGNAL

uniform CRTHP vec4 srcSize;   // source W, H in pixels, then 1/W, 1/H
uniform CRTHP vec4 raster;    // px per line, first line's top (px), rows, 1/rows
uniform CRTHP vec4 carrier;   // px per subcarrier cycle, line phase, frame phase, tap step px
uniform vec4 decode;          // melt, artifact colour, dot crawl, chroma saturation
uniform vec4 band;            // RGB blur px, luma soften, chroma shift px, sharpen
uniform vec4 air;             // snow, ghost strength, ghost delay px, jitter px
uniform vec4 hum;             // bar depth, bar position, line wobble px, frame seed
uniform vec3 decay;           // what survives of the last frame, per channel (gamma)
uniform Image prevTex;        // this pass's own output, one frame ago
uniform Image noiseTex;       // 256x256 of uniform noise, wrapped

// The line's own height, averaged: two taps a quarter-line either side of
// its centre, each already the blend of two rows. For the Game Boy's world
// every row of a line is the same row of the same Game Boy pixel and this is
// exact; for the 3D world and the high-resolution UI it is the vertical
// resolution a scanline actually has.
vec3 lineAt(Image tex, CRTHP float x, CRTHP float y0, CRTHP float y1) {
  CRTHP float u = x * srcSize.z;
  return 0.5 * (Texel(tex, vec2(u, y0)).rgb + Texel(tex, vec2(u, y1)).rgb);
}

vec4 effect(vec4 vcolor, Image tex, vec2 tcIn, vec2 scIn) {
  CRTHP vec2 uv = VaryingTexCoord.xy;
  CRTHP float row = floor(uv.y * raster.z);
  CRTHP float line = row - 1.0;                 // row 0 is the partial line above
  CRTHP float yc = raster.y + (line + 0.5) * raster.x;
  CRTHP float y0 = (yc - 0.25 * raster.x) * srcSize.w;
  CRTHP float y1 = (yc + 0.25 * raster.x) * srcSize.w;
  CRTHP float x = uv.x * srcSize.x;

  // A line's own noise: one texel of the noise texture per line, read at a
  // column that moves every frame.
  CRTHP vec2 lineNoiseUV = vec2(hum.w, (line + 0.5) / 256.0);
  vec4 ln = Texel(noiseTex, lineNoiseUV);
  // Horizontal hold that is not quite holding: every line lands a little
  // early or late, and a slow wave runs down the picture.
  x += (ln.r - 0.5) * 2.0 * air.w
     + hum.z * sin(6.2831853 * (line * 0.013 + hum.y * 3.0));

  vec3 col;
#ifdef COMPOSITE
  // ------- the NTSC round trip
  //
  // Thirteen samples a quarter of a subcarrier cycle apart, so the carrier's
  // cos/sin at each one is the last one turned by 90 degrees: no trig in the
  // loop at all. Encode each to the one-wire signal Y + I cos + Q sin, then
  // decode the way a set does: demodulate I and Q against the carrier and
  // low-pass them, and take luma as the signal with that chroma removed.
  //
  // What makes this a television and not a blur is what goes WRONG, and the
  // three ways are kept apart so each has its own knob:
  //   melt   luma detail that sat near the carrier frequency was taken for
  //          colour and removed from luma -- a 1-pixel dither, which on this
  //          raster sits right under the carrier, dissolves into its average.
  //          This is the waterfall on a Mega Drive, done on purpose.
  //   art    ...and reappears as colour: the rainbow those patterns wore.
  //   crawl  real colour the low-pass could not follow at an edge is left in
  //          luma as a fine checker that walks with the carrier: dot crawl.
  CRTHP float cyc = carrier.x;
  CRTHP float ph = 6.2831853 * fract(x / cyc + carrier.y * line + carrier.z);
  float c0 = cos(ph), s0 = sin(ph);
  float cr = c0, sr = s0;
  // start the walk at k = -6: turning back six quarter turns is turning
  // forward two, i.e. a half turn
  cr = -c0; sr = -s0;
  vec3 yiq0 = vec3(0.0);
  vec3 iqDec = vec3(0.0);        // x = I, y = Q, demodulated from the wire
  vec3 iqTrue = vec3(0.0);       // x = I, y = Q, the colour actually sent
  float yLow = 0.0;
  float wsum = 0.0;
  float sig = 0.0;
  float split = 0.0;             // how much the line's two halves disagree
  for (int i = 0; i < 13; i++) {
    float k = float(i) - 6.0;
    // the chroma low-pass, shifted for the colour delay a cheap set has
    float kc = k - band.z;
    float w = exp(-kc * kc * 0.105);
    CRTHP float u = (x + k * carrier.w) * srcSize.z;
    vec3 ta = Texel(tex, vec2(u, y0)).rgb;
    vec3 tb = Texel(tex, vec2(u, y1)).rgb;
    split = max(split, abs(dot(ta - tb, vec3(0.299, 0.587, 0.114))) * step(abs(k), 3.0));
    vec3 yiq = toYIQ(0.5 * (ta + tb));
    float s = yiq.x + yiq.y * cr + yiq.z * sr;
    iqDec.xy += w * s * vec2(cr, sr);
    iqTrue.xy += w * yiq.yz;
    float wl = exp(-k * k * 0.5);
    yLow += wl * yiq.x;
    sig += wl;
    wsum += w;
    if (i == 6) yiq0 = yiq;
    // the next sample is a quarter cycle on: (cos, sin) turns by 90 degrees
    float t = cr; cr = -sr; sr = t;
  }
  iqDec.xy *= 2.0 / wsum;
  iqTrue.xy /= wsum;
  yLow /= sig;
  float chromaTrue0 = iqTrue.x * c0 + iqTrue.y * s0;
  float art0 = (iqDec.x - iqTrue.x) * c0 + (iqDec.y - iqTrue.y) * s0;
  float crawl0 = yiq0.y * c0 + yiq0.z * s0 - chromaTrue0;
  // ------- the Game Boy's picture, or something finer drawn over it
  //
  // A row of the Game Boy's world is one row of pixels, so the two halves of
  // its scanline are the same picture. The battle cards, the start menu and
  // the 3D world are drawn at the panel's own resolution, and there the two
  // halves differ. The NTSC failures are kept for the first kind: a dither
  // made of Game Boy pixels melts; a card's lettering, which a real 240-line
  // set could never have carried, stays readable. (`split` is the largest
  // disagreement near the centre of the line.)
  float native = 1.0 - smoothstep(0.025, 0.10, split);
  float Y = yiq0.x + decode.z * native * crawl0 - decode.x * native * art0;
  // the set's own luma bandwidth (RF has less of it than a jack does)
  Y = mix(Y, yLow, band.y * (0.35 + 0.65 * native));
  vec2 IQ = (iqTrue.xy + decode.y * native * (iqDec.xy - iqTrue.xy)) * decode.w;
  col = toRGB(vec3(Y, IQ));
#else
  // ------- RGB, or as near as a jack gets: only the bandwidth
  CRTHP float h = band.x;
  vec3 a = lineAt(tex, x - 2.0 * h, y0, y1);
  vec3 b = lineAt(tex, x - h, y0, y1);
  vec3 c = lineAt(tex, x, y0, y1);
  vec3 d = lineAt(tex, x + h, y0, y1);
  vec3 e = lineAt(tex, x + 2.0 * h, y0, y1);
  col = c * 0.40 + (b + d) * 0.24 + (a + e) * 0.06;
  // a little overshoot on edges: the ringing every analogue path has, and
  // the reason a PVM's pixels look cut rather than smeared
  col += band.w * (c - (b + d) * 0.5);
#endif

#ifdef GHOST
  // A second, later copy of the picture off a reflection the aerial also
  // caught: luma only, which is how a ghost looks -- a grey echo, not a
  // second coloured picture.
  float g = dot(lineAt(tex, x - air.z, y0, y1), vec3(0.299, 0.587, 0.114));
  col = (col + air.y * vec3(g)) / (1.0 + air.y);
#endif

#ifdef NOISE
  // Snow: the picture's own noise floor. Per sample, so it streaks along the
  // line the way real snow does; a frame-moving offset so it boils.
  CRTHP vec2 nuv = vec2(uv.x * srcSize.x / 512.0 + hum.w * 7.0,
                        (line + 0.5) / 256.0 + hum.w * 3.0);
  vec4 n = Texel(noiseTex, nuv);
  float sn = (n.g - 0.5) * 2.0;
  col += air.x * vec3(sn) + air.x * 0.35 * (n.ba - 0.5) .xyx * vec3(1.0, -0.6, 1.0);
  // the hum bar: a slow dark band rolling up the picture
  float hb = fract(uv.y - hum.y);
  col *= 1.0 - hum.x * smoothstep(0.0, 0.35, hb) * smoothstep(0.7, 0.35, hb);
#endif

  col = clamp(col, 0.0, 1.0);
#ifdef PERSIST
  // The phosphor is still lit from the frame before: whatever was brighter
  // then fades rather than vanishing, so a moving light leaves a short tail.
  vec3 prev = Texel(prevTex, uv).rgb;
  col = max(col, prev * decay);
#endif
  return vec4(col, 1.0);
}
#endif

// =========================================================================
#ifdef PASS_GLOW
uniform CRTHP vec2 dir;   // one texel along the axis being blurred, in uv

vec4 effect(vec4 vcolor, Image tex, vec2 tcIn, vec2 scIn) {
  CRTHP vec2 uv = VaryingTexCoord.xy;
  // the same 9-tap gaussian TiltShift gathers in 5 linear fetches
  vec3 s = Texel(tex, uv).rgb * 0.2270270270;
  s += (Texel(tex, uv + dir * 1.3846153846).rgb
      + Texel(tex, uv - dir * 1.3846153846).rgb) * 0.3162162162;
  s += (Texel(tex, uv + dir * 3.2307692308).rgb
      + Texel(tex, uv - dir * 3.2307692308).rgb) * 0.0702702703;
  return vec4(s, 1.0);
}
#endif

// =========================================================================
#ifdef PASS_TUBE
uniform CRTHP vec4 outSize;   // W, H px, 1/W, 1/H
uniform CRTHP vec4 tube;      // the picture's rectangle in px: x, y, w, h
uniform CRTHP vec4 raster;    // px per line, first line's top (px), rows, 1/rows
uniform vec4 geom;            // warp x, warp y, corner radius, edge softness (tube units)
uniform vec4 beam;            // spot sigma dark, spot sigma bright, brightness, gamma in
uniform vec4 conv;            // red dx, blue dx at the centre; red, blue extra at the edge (px)
uniform vec4 convY;           // red dy, blue dy (lines), damper wires depth, wire px
uniform vec4 mask;            // kind (0 grille, 1 slot, 2 dots, 3 none), period px, dark, boost
uniform vec4 glowK;           // halation, gap fill, gamma out, saturation
uniform vec4 shade;           // vignette, shoulder knee, white R/G scale (packed below)
uniform vec3 white;           // the set's white point, multiplied in
uniform vec4 room;            // the room's light reflected in the glass: rgb, lift
uniform vec4 spec;            // highlight x, y, size, strength (tube units)
uniform vec4 anim;            // vertical size, horizontal size, flare, degauss
uniform vec4 anim2;           // degauss clock, static, vertical roll, flash (lightning)
uniform vec4 spot;            // the power line / dot's glow: radius x, radius y, strength
uniform vec4 detail;          // how much finer-than-a-line detail comes back, and in the gaps
uniform Image glowTex;
uniform Image srcTex;         // the frame as it arrived (nearest-filtered here)
uniform Image noiseTex;
#ifdef FRAME
uniform Image bezelTex;
uniform vec4 spill;           // how far the screen's light reaches onto the bezel, strength
#endif

// The three masks, in the screen's own pixels so they never beat against
// the panel. Layouts after crt-lottes (public domain): an aperture grille is
// unbroken vertical stripes; a slot mask is the same stripes cut into
// bricks, every other column offset by half a brick; a dot (shadow) mask
// staggers the triads row by row.
vec3 phosphor(CRTHP vec2 p) {
  CRTHP float T = mask.y;
  vec3 m = vec3(mask.z);
  if (mask.x > 2.5) return vec3(1.0);
  CRTHP float px = p.x;
  if (mask.x > 1.5) {
    // dots: each row of triads sits a third of a triad over
    px += floor(p.y / max(1.0, floor(T * 0.67 + 0.5))) * T / 3.0;
  }
  CRTHP float u = fract(px / T);
  if (T < 2.5) {
    // two pixels cannot hold three stripes: magenta and green, which still
    // integrates to white and still reads as a grille at arm's length
    if (u < 0.5) { m.rb = vec2(1.0); } else { m.g = 1.0; }
  } else {
    if (u < 0.3333) m.r = 1.0; else if (u < 0.6667) m.g = 1.0; else m.b = 1.0;
  }
  if (mask.x > 0.5 && mask.x < 1.5) {
    // slot: a brick every 4 rows (3 lit, 1 bridge), columns alternate by 2
    CRTHP float col = floor(px / T);
    CRTHP float v = fract((p.y + 2.0 * mod(col, 2.0)) / 4.0);
    if (v > 0.74) m *= mask.z;
  }
  return m;
}

vec4 effect(vec4 vcolor, Image tex, vec2 tcIn, vec2 scIn) {
  CRTHP vec2 p = VaryingTexCoord.xy * outSize.xy;
  CRTHP vec2 c = ((p - tube.xy) / tube.zw) * 2.0 - 1.0;

  // ------- degauss: the picture shaken by a decaying field, colour knocked
  // off true by the magnetised mask; both swirl and settle
  float dg = anim.w;
  CRTHP float tg = anim2.x;
  vec2 swirl = vec2(sin(c.y * 3.1 + tg * 9.0 + c.x * 1.7),
                    cos(c.x * 2.7 - tg * 7.0 + c.y * 2.3));
  c += dg * 0.018 * swirl * vec2(1.0, 0.6);
  // vertical roll while the set is finding sync again
  c.y += anim2.z;

  // ------- the glass is curved
  CRTHP vec2 w = c * vec2(1.0 + c.y * c.y * geom.x, 1.0 + c.x * c.x * geom.y);
  // the tube's own edge: a rounded rectangle, soft by a pixel or two
  vec2 aspect = vec2(tube.z / tube.w, 1.0);
  vec2 q = (abs(w) - 1.0 + geom.z) * aspect;
  float edge = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - geom.z;
  float inside = 1.0 - smoothstep(-geom.w, 0.0, edge);

  // ------- power: the raster collapses to a line, then to a point
  CRTHP vec2 s = w * 0.5 + 0.5;
  CRTHP vec2 sc = (s - 0.5) / max(anim.yx, vec2(0.0005)) + 0.5;
  float onRaster = step(abs(sc.x - 0.5), 0.5) * step(abs(sc.y - 0.5), 0.5);
  sc = clamp(sc, 0.0, 1.0);

  // ------- which two scanlines this pixel sits between
  CRTHP float ly = (sc.y * outSize.y - raster.y) / raster.x - 0.5;
  CRTHP float la = floor(ly);
  float f = float(ly - la);
  CRTHP float ta = (la + 1.5) * raster.w;
  CRTHP float tb = ta + raster.w;

  // ------- three beams that do not quite land together
  float edgeX = float(s.x) * 2.0 - 1.0;
  CRTHP float xr = sc.x + (conv.x + conv.z * edgeX) * outSize.z;
  CRTHP float xb = sc.x + (conv.y + conv.w * edgeX) * outSize.z;
  vec3 A, B;
#ifdef CONVERGE
  A = vec3(Texel(tex, vec2(xr, ta)).r, Texel(tex, vec2(sc.x, ta)).g, Texel(tex, vec2(xb, ta)).b);
  B = vec3(Texel(tex, vec2(xr, tb)).r, Texel(tex, vec2(sc.x, tb)).g, Texel(tex, vec2(xb, tb)).b);
#else
  A = Texel(tex, vec2(sc.x, ta)).rgb;
  B = Texel(tex, vec2(sc.x, tb)).rgb;
#endif
  A = pow(A, vec3(beam.w));
  B = pow(B, vec3(beam.w));

  // ------- the spot: a gaussian whose width follows the beam current, so a
  // bright line fattens until it nearly meets its neighbours and a dark one
  // thins to a thread with black between. Normalised by its own width, so
  // the light a line puts out is what the signal asked for either way.
  vec3 da = f + vec3(convY.x, 0.0, convY.y);
  vec3 db = 1.0 - da;
  vec3 sa = mix(vec3(beam.x), vec3(beam.y), sqrt(A));
  vec3 sb = mix(vec3(beam.x), vec3(beam.y), sqrt(B));
  vec3 col = A * exp(-(da * da) / (sa * sa)) / sa
           + B * exp(-(db * db) / (sb * sb)) / sb;
  col *= 0.5641896 * beam.z;     // 1/sqrt(pi): a full field integrates to 1

  // ------- what is finer than a scanline
  //
  // The frame itself, read at this pixel and at the centre of the nearest
  // line (with nearest filtering, so a Game Boy row reads as one flat value
  // and this adds exactly nothing to the Game Boy's own picture). What is
  // left is the detail the line averaged away -- the battle cards' lettering,
  // the 3D world's edges -- put back inside the lit part of the line, fading
  // toward the dark between lines like the beam does, but not all the way:
  // a scanline TV could not have shown these, and they still have to read.
  float near = step(0.5, f);
  CRTHP float yn = raster.y + (la + near + 0.5) * raster.x;
  CRTHP float dq = 0.25 * raster.x * outSize.w;
  vec3 sHere = Texel(srcTex, sc).rgb;
  vec3 sLine = 0.5 * (Texel(srcTex, vec2(sc.x, yn * outSize.w - dq)).rgb
                    + Texel(srcTex, vec2(sc.x, yn * outSize.w + dq)).rgb);
  vec3 dl = pow(sHere, vec3(beam.w)) - pow(sLine, vec3(beam.w));
  float dn = min(f, 1.0 - f);
  vec3 sNear = mix(sa, sb, near);
  vec3 en = exp(-(dn * dn) / (sNear * sNear));
  col += detail.x * dl * mix(en, vec3(1.0), detail.y) * beam.z * onRaster;

  // ------- the light inside the glass
  vec3 gRaw = pow(Texel(glowTex, sc).rgb, vec3(beam.w));
  vec3 g = gRaw * onRaster;
  col += g * glowK.x;
  // the halo also fills the black between lines, a little, near light
  col += g * glowK.y * (1.0 - min(col, vec3(1.0)));

  // ------- the phosphor
  vec3 m = phosphor(p);
  col *= mix(vec3(1.0), m * mask.w, step(mask.x, 2.5));
  // Trinitron's damper wires: two hairlines across the whole tube
  CRTHP float wy = (p.y - tube.y) / tube.w;
  float wire = max(1.0 - abs(wy - 0.3333) * tube.w / convY.w,
                   1.0 - abs(wy - 0.6667) * tube.w / convY.w);
  col *= 1.0 - convY.z * clamp(wire, 0.0, 1.0);

  // ------- the set's colour, and its corners
  col *= white;
  float lum = dot(col, vec3(0.299, 0.587, 0.114));
  col = max(mix(vec3(lum), col, glowK.w), 0.0);
  vec2 vg = w * w;
  col *= clamp(1.0 - shade.x * (vg.x * 0.55 + vg.y * 0.45 + vg.x * vg.y * 0.8), 0.0, 1.0);

  // the power-off point is brighter than anything the picture ever was
  col *= (1.0 + anim.z) * onRaster;
  vec2 sr = w / spot.xy;
  col += spot.z * vec3(0.86, 0.92, 1.0) * exp(-dot(sr, sr));

  // ------- static between channels
  CRTHP vec2 nuv = p / 256.0 + vec2(anim2.x * 13.7, anim2.x * 5.3);
  float sn = Texel(noiseTex, nuv).r;
  col = mix(col, vec3(sn * sn * 1.4), anim2.y);

  // ------- degauss colour: the mask magnetised, purity swirling off
  col *= 1.0 + dg * 0.6 * vec3(swirl.x, -swirl.y * swirl.x, swirl.y);

  // ------- the knee: what the phosphor cannot show any brighter
  float kn = shade.y;
  vec3 over = max(col - kn, 0.0);
  col = min(col, vec3(kn)) + (1.0 - kn) * (1.0 - exp(-over / (1.0 - kn)));

  // ------- the room, in the glass: a lift that keeps black from being black,
  // and one soft highlight where the lamp (or the window) is
  CRTHP vec2 hp = (w - spec.xy) * vec2(tube.z / tube.w, 1.0);
  float hl = exp(-dot(hp, hp) / (spec.z * spec.z)) * spec.w;
  float sheen = 0.35 + 0.65 * (1.0 - 0.5 * (w.y + 1.0) * 0.5);
  vec3 glass = room.rgb * (room.a * sheen + hl) + anim2.w * vec3(0.55, 0.62, 0.8) * (0.35 + hl * 2.0);
  col += glass;

  col *= inside;
#ifdef FRAME
  vec4 bz = Texel(bezelTex, VaryingTexCoord.xy);
  // the screen lights its own surround: the nearest edge of the picture,
  // blurred, fading with distance from the glass
  float away = max(edge, 0.0);
  vec3 lit = gRaw * spill.y * exp(-away / max(spill.x, 0.001)) * bz.a
           * clamp(anim.x * anim.y * 4.0, 0.0, 1.0);
  vec3 cab = bz.rgb * (0.55 + room.rgb * 0.6 + anim2.w * 0.6) + lit;
  col += cab * (1.0 - inside);
#endif
  col = pow(max(col, 0.0), vec3(glowK.z));
  return vec4(col, 1.0);
}
#endif

// =========================================================================
#ifdef PASS_BEZEL
uniform CRTHP vec4 outSize;
uniform CRTHP vec4 tube;
uniform vec4 geom;
uniform vec3 plastic;         // the cabinet's colour
uniform vec4 finish;          // grain, gloss, bevel width (px), wood (0/1)
uniform Image noiseTex;

// The cabinet, as a relief lit from the room: a flat front, and a bevel
// that slopes down from it into the tube on every side. The light comes from
// above and a little in front, so the bottom of the bevel faces it and
// catches a highlight while the top of the bevel faces the floor and sits in
// its own shadow -- which is most of what makes a hole read as a hole. The
// alpha channel says how much each pixel faces the screen, so the tube pass
// can light the bevel with the picture.
vec4 effect(vec4 vcolor, Image tex, vec2 tcIn, vec2 scIn) {
  CRTHP vec2 p = VaryingTexCoord.xy * outSize.xy;
  CRTHP vec2 c = ((p - tube.xy) / tube.zw) * 2.0 - 1.0;
  vec2 aspect = vec2(tube.z / tube.w, 1.0);
  vec2 q = (abs(c) - 1.0 + geom.z) * aspect;
  float edge = (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - geom.z) * tube.w * 0.5;
  // which way is "out of the hole" here
  vec2 outward = (q.x > 0.0 && q.y > 0.0) ? normalize(q) : (q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
  outward *= sign(c + 0.0001);
  float bev = finish.z;
  float lip = 1.0 - smoothstep(0.0, bev, edge);
  // the bevel tilts toward the tube: its normal leans inward
  vec3 n = normalize(vec3(-outward * 0.9 * lip, 1.0));
  vec3 L = normalize(vec3(-0.25, -0.75, 0.6));
  float lit = clamp(dot(n, L), 0.0, 1.0);
  // the front: brighter toward the ceiling light, falling off to the floor
  float fall = 1.0 - (p.y / outSize.y) * 0.35;
  // the noise is linear-filtered for this pass: soft variation, not speckle
  CRTHP vec2 nuv = p / 256.0;
  float n1 = Texel(noiseTex, nuv * 0.5).r * 0.6 + Texel(noiseTex, nuv * 2.0).g * 0.4;
  float n2 = Texel(noiseTex, nuv * 0.06 + 0.37).b;
  vec3 base = plastic;
  if (finish.w > 0.5) {
    // wood veneer: long grain across the cabinet, wavering, with the odd knot
    CRTHP float gy = p.y / outSize.y * 46.0 + n2 * 4.0
                   + 1.5 * sin(p.x / outSize.x * 5.0 + n2 * 3.0)
                   + Texel(noiseTex, vec2(p.x / 4096.0, p.y / 64.0)).r * 0.8;
    float grain = 0.5 + 0.5 * sin(gy * 3.1416);
    grain = grain * grain;
    base = mix(plastic * 1.12, plastic * 0.58, grain * 0.8 + (n1 - 0.5) * 0.15);
  } else {
    base *= 1.0 + finish.x * (n1 - 0.5) + finish.x * 0.6 * (n2 - 0.5);
  }
  vec3 col = base * (0.30 + 0.85 * lit) * fall;
  // gloss: a sharp sheen where the bevel turns toward the light
  col += finish.y * pow(lit, 24.0) * 0.35 * lip;
  // a hairline of dark where the bezel meets the glass
  col *= smoothstep(0.0, 1.5, edge);
  return vec4(col, lip * 0.85 + 0.15);
}
#endif
