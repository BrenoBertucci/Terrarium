-- Voxel world mode: the 3D pass -- shader, depth buffer and camera.
--
-- World space is world PIXELS, so every coordinate the 2D paths already
-- compute drops straight in with no unit conversion:
--
--   +X  map east   (world-pixel x)
--   +Y  up         (0 is the ground plane)
--   +Z  map south  (world-pixel y)
--
-- A character at rest faces +Z, i.e. toward a camera parked to the south,
-- which is what "facing down" means in the 2D game -- and a character card
-- is drawn in exactly that pose, leaning back rather than yawing.
--
-- The camera orbits the view centre at Voxel.angle: 0 is straight down
-- (what the flat 2D view already is) and 50 degrees leans toward the
-- horizon. Distance and field of view are tied to Voxel.FOCAL, which is the
-- same constant Tilt projects with, so a given angle frames the world
-- identically in both modes -- switching between them changes the geometry,
-- not the framing.
--
-- Every GPU object is pcall-guarded and `available()` reports the result:
-- headless test runs and any driver without depth-canvas support fall back
-- to the existing tilt/flat paths rather than erroring.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local Voxel = V.require("VoxelState")
local ShadowMap = V.require("ShadowMap")
local VoxelGrid = V.require("VoxelGrid")
local WorldCurve = V.require("WorldCurve")
local Aerial = V.require("Aerial")
local Sky = V.require("Sky")
local DayNight = V.require("DayNight")
local GlassMask = V.require("GlassMask")
local Quality = V.require("Quality")
-- Safe anywhere in this list: Anime requires ModSetting and nothing else,
-- precisely so that this file and RayFX can both hold it without either
-- one reaching back through it.
local Anime = V.require("Anime")
local Wind = V.require("Wind")
local Water = V.require("Water")
local Light = V.require("Light")
-- Last, and it has to be: RayFX pulls in Sky and DayNight, and DayNight
-- reaches back here for the shadow rig. Everything it wants is already
-- memoised by the time this line runs, so the cycle is never entered.
local RayFX = V.require("RayFX")

local Voxel3D = {}

-- Vertex format shared by terrain chunks and character models: a position,
-- the map-canvas / sprite-sheet pixel it samples, and a per-vertex darken
-- factor that gives a face its angle to the sun without a normal or a
-- light uniform. Cast shadows are a separate thing entirely -- see
-- ShadowMap, which the pixel shader below samples on top of this.
Voxel3D.FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexTexCoord", "float", 2 },
  { "VertexShade", "float", 1 },
}

-- Face shading by direction id: top faces stay
-- full brightness, sides step down so an extruded block reads as solid
-- instead of a flat sticker, and the faces turned away from the sun are
-- darkest. The sun hangs in the SOUTHEAST (see ShadowMap), so south and
-- east are the lit flanks and north and west the shaded ones -- east and
-- west used to share one value back when the sun sat due northwest and the
-- two were symmetric about it.
--
-- This is still worth baking even now that the shadow pass throws real
-- shadows: a face turned away from the sun is dark because of its ANGLE,
-- which no shadow map measures, and the two compound the way they should
-- -- an away-facing wall that is also occluded goes darker still.
Voxel3D.FACE_SHADE = {
  [1] = 0.84,   -- +X east (toward the sun)
  [2] = 0.72,   -- -X west (away)
  [3] = 1.00,   -- +Y up
  [4] = 0.55,   -- -Y down
  [5] = 0.90,   -- +Z south (toward the camera, and toward the sun)
  [6] = 0.68,   -- -Z north (away)
}

local SHADER = [[
  varying float vShade;       // how dark this face draws, always positive
  // 1 on a face that points at the sky, 0 on every other one. It rides in
  // the SIGN of VertexShade rather than in an attribute of its own: the
  // meshers negate the shade of an up-facing quad and this splits the two
  // apart again, so an honest face normal costs no extra float per vertex on
  // a route that uploads twenty megabytes of them. Every corner of a quad
  // carries the same sign, so this interpolates flat across the face.
  varying float vUp;
  // World pixels, for patterns that must sit STILL on a surface while the
  // camera moves. Same precision note as vGrid below, and for the same
  // reason: what reads this wants the whole-number part of a coordinate that
  // runs to a few thousand across a route, which a mediump varying would
  // quantise away into bands.
  varying LOVE_HIGHP_OR_MEDIUMP vec3 vWorld;
  varying vec3 vSun;          // this fragment's place in the sun's view
  // Snow SETTLED on a grass blade, 0..1, weighted by how far up the tuft
  // this fragment sits. Grass is the one thing in the world whose snow the
  // face normal cannot answer for: a blade is a SIDE by every honest
  // measure of its geometry, so `vUp` is correctly zero on all of it and
  // the snow block below correctly gives the whole meadow the flank's
  // share and no more -- a tuft tinted a third pale, in a world where the
  // ground beside it has gone white. But snow does not care that a blade
  // is vertical; it lands from above and RESTS ON THE CROWN, which is why
  // real winter grass is white on top and green underneath. This carries
  // that, and it is a separate channel from vUp rather than a fudge of it
  // precisely because it is a different fact: not "which way does this
  // face point" but "how much has piled on this blade".
  varying float vGrassCap;
  varying float vWater;       // 1 when swell/ice paint runs, 0 otherwise
  varying float vWaterSurf;   // 1 on recessed water geometry always (y < -1)
  varying vec3 vWave;         // and the normal of the swell under it
  varying float vSwellH;      // the swell's own height here, -1 .. 1
  // Wave trains live in BOTH stages: the vertex displaces continuously so
  // the mesh stays watertight, and the fragment re-evaluates height on a
  // quantized world-XZ cell so cel band edges do not crawl (see the water
  // block in effect()). Declared outside #ifdef VERTEX on purpose.
  uniform vec2 swellA;        // two crossing wave trains, as phase per pixel
  uniform vec2 swellB;
  uniform float swellPhase;
  // Spatial body-size knobs (Water.BODY_KX/KZ) -- vertex height AND fragment
  // bands must share them so paint and feet stay on one field.
  uniform float bodyKx;
  uniform float bodyKz;
  uniform float waterSteep;   // crest steepening (energy * STEEP), heightField twin
  uniform vec2  waterCurrent; // unit XZ wind/current for advection + foam streaks
  uniform float waterAdvect;  // phase drag along current
  uniform float waterEnergy;  // lagged chop energy 0..1
  uniform float waterTherm;   // 0 cold .. 1 warm
#ifdef VOXEL_GRID
  // model space, one unit per voxel -- see VoxelGrid. Precision matters
  // here in a way it does not for a colour: the seam is the FRACTIONAL
  // part of a coordinate that runs to a few thousand across a big route,
  // so a mediump varying would quantise the fraction away entirely.
  varying LOVE_HIGHP_OR_MEDIUMP vec3 vGrid;
#endif
#ifdef VERTEX
  uniform mat4 vp;
  uniform mat4 model;
  uniform mat4 sunModel;      // where the SUN sees this vertex (see below)
  uniform mat4 sunVP;         // world -> the shadow map's unit cube
  uniform vec3 eye;
  uniform float pull;
  uniform vec4 curve;         // xy = the focus in world XZ, z = k; 0 = off
                              // w = the deepest the bend may go (see below)
  uniform float sway;         // wind reach at the tip, world px; 0 = planted
  // Foot-crush on grass (packed vec4: xz pos, radius, strength). crushN is
  // how many are live this draw. Zero when not the grass pass so terrain
  // never folds under a walker.
  //
  // EIGHT, and an array rather than the four separate uniforms this used
  // to be, because half of them are no longer feet: the first few are the
  // walkers standing in the meadow right now and the rest are the TRAIL
  // they left -- crumbs dropped along the path behind them, fading over
  // seconds rather than springing back in one. Four slots could hold the
  // feet or the trail and not both. An array also means one send for the
  // lot instead of eight, which is what makes the extra slots free.
  uniform vec4 crush[8];
  uniform float crushN;
  uniform vec2 windDir;       // its bearing in world XZ, unit length
  uniform vec2 windFreq;      // phase gained per world pixel, per axis
  uniform float windPhase;    // advanced by the clock
  uniform float grassH;       // tuft height in world px -- the bend normaliser
  // How much of the physics this device is paying for (Quality.grassDetail):
  // 0 = the travelling wave alone, 1 = + per-tuft stiffness and the squall
  // front, 2 = + flutter, cross-axis drift, tip bob and the rain's tick.
  // A uniform, so every branch on it is coherent across the whole draw --
  // this costs a compare per vertex and saves six sines at the bottom rung.
  uniform float grassDetail;
  // What the blades are CARRYING and what is passing over them:
  //   x  rain on them now       weight + damping + the tick of drops landing
  //   y  settled snow on them   weight that stays, and stiffens what is left
  //   z  gust envelope 0..1     how far into a squall this instant is
  uniform vec3 grassLoad;
  uniform float swell;        // water's rise at the crest, world px; 0 = flat
  uniform float iceLift;      // freeze raises the surface a little (still y<-1 id)
  attribute float VertexShade;
  // One number per TUFT, from the 8x8 cell it stands in. The grass mesh is
  // one buffer for a whole map and carries no per-instance attribute, so
  // the only thing a vertex knows about which tuft it belongs to is where
  // it is -- and a tuft is exactly one cell wide, so the floor of the world
  // position over 8 is that tuft's name. Everything a blade should not
  // share with its neighbour (stiffness, phase, which way snow slumps it)
  // comes off this, which is what stops a meadow reading as one object
  // being shaken.
  float tuftHash(vec2 cell) {
    return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
  }
  vec4 position(mat4 transform_projection, vec4 vertex_position) {
    // magnitude is the shading, sign is the face normal's Y (see vUp). A
    // shade is a product of positive factors with a floor well above zero,
    // so zero is not a value any mesher can emit and the split is exact.
    vShade = abs(VertexShade);
    vUp = step(VertexShade, 0.0);
#ifdef VOXEL_GRID
    // MODEL space, deliberately: every mesh here is built a unit per
    // voxel in its own frame, so the seams ride the model however it is
    // posed rather than the world's grid sliding across a leaning sprite
    vGrid = vertex_position.xyz;
#endif
    vec4 w = model * vertex_position;
    // Taken here, before the wind, the swell, the curve and the camera-ward
    // pull: those are all things done to where a vertex is DRAWN, and this is
    // for where the surface is. A dither anchored to a bending grass blade
    // would swim with it.
    vWorld = w.xyz;
    // WIND, and only on what is asked to take it (see Voxel3D.draw's
    // `sway`; everything else passes zero and this costs one compare).
    //
    // The bend factor is the vertex's OWN y, which for a grass tuft is its
    // height above the base of that tuft -- Structures builds the template
    // at y = 0 and ChunkMesher offsets only X and Z when it stamps one into
    // the world. So the base is planted and the tip gives, out of a number
    // the mesh already carries, with no attribute added and nothing to look
    // up. Squared, because a stem does not bend linearly: it holds near the
    // root and folds near the top.
    //
    // The phase comes from the vertex's own WORLD position, which is the
    // thing that makes this weather rather than a metronome -- every tuft
    // on a route reaches its crest at a different moment, so the gust
    // arrives at one edge of a meadow, crosses it, and leaves. A tile
    // animation cannot do that at any price: it is one picture, shared by
    // every cell drawing that tile, so they can only ever move as one.
    //
    // Two harmonics rather than one so the crest is not a clean sine
    // rolling past -- real gusts have a shove in them.
    // Zero for everything that is not the grass pass, and set inside the
    // block below when it is -- the same discipline `vWater` keeps, and
    // for the same reason: a varying left over from the previous draw is
    // a snowed hedge on a bare wall.
    vGrassCap = 0.0;
    if (sway > 0.0) {
      // Height fraction. `grassH` is what the mesh in front of the shader
      // actually stands (the bake's own height for a 3D tuft, the slab's
      // for the classic path) rather than the flat 0.1 that used to stand
      // in for both -- a bake taller or shorter than ten pixels was having
      // its bend curve stretched or clipped, which is why a tall tuft went
      // stiff at the top and a short one bent from the root.
      float H = max(grassH, 1.0);
      float hN = clamp(vertex_position.y / H, 0.0, 1.0);
      float bend = hN * hN;

      // ------- which tuft this is
      //
      // Taken off vWorld, which is the position BEFORE any of this moves
      // it: a name that changed as the blade bent would make the blade's
      // own stiffness flicker.
      // Per-tuft identity and the squall front are TIER 1 and up. At tier 0
      // every tuft shares one stiffness and one phase: the meadow still
      // bends and the gust still travels (the phase comes from world
      // position either way), it just does not scatter. That is two sines
      // and a hash saved on every vertex of the mesh.
      float id = 0.5;
      float stiff = 1.0;
      float ph = 0.0;
      float front = 1.0;
      if (grassDetail >= 1.0) {
        id = tuftHash(floor(vWorld.xz * 0.125));
        // Stiffness scatter. A real meadow is not one plant: some tufts are
        // young and whippy, some are woody and barely give, and it is the
        // DISAGREEMENT that reads as many plants rather than one animated
        // surface. Divided into the amplitude, so a stiff tuft leans less.
        stiff = 0.78 + id * 0.55;
        ph = id * 6.2831;
        // ------- the squall front
        //
        // A second wave on the same bearing at a fifth of the frequency
        // and a third of the clock -- so the amplitude ITSELF travels. The
        // wave below says which way a blade is leaning this instant; this
        // says whether the air is on it at all. Without it a meadow is
        // uniformly windy forever, which is the tell that separates an
        // animation from weather no matter how good the wave is.
        front = 0.72 + 0.28 * sin(dot(w.xz, windFreq * 0.21)
                                  - windPhase * 0.37);
      }

      float wet  = clamp(grassLoad.x, 0.0, 1.0);
      float snow = clamp(grassLoad.y, 0.0, 1.0);
      float gust = clamp(grassLoad.z, 0.0, 1.0);

      float p = dot(w.xz, windFreq) - windPhase + ph * 0.35;
      float amp = sway * (0.55 + 0.45 * front) * (1.0 + 0.55 * gust) / stiff;
      // Rain is water on a blade: heavier, so it damps -- a wet meadow
      // moves less, not more. Settled snow is worse, and it also freezes
      // the stems it is sitting on, so it takes most of the give away.
      amp *= (1.0 - 0.28 * wet) * (1.0 - 0.62 * snow);

      // The travelling gust and the shove in it. Two sines, every tier:
      // this is the motion itself and there is no cheaper version of it.
      float wave = sin(p) + 0.38 * sin(p * 2.25 + 1.7);
      vec2 lean = windDir * (amp * bend * wave);

      // TIER 2 -- the texture on top of the motion. Flutter so a meadow
      // shimmers rather than waving like a flag, a cross-axis drift so
      // blades do not all lean on one line, and the rain's own fast note
      // as drops land. Three more sines, and on a device that chose FULL
      // they are what the choice was for.
      if (grassDetail >= 2.0) {
        wave += 0.14 * sin(p * 5.3 + hN * 2.1 + 0.4)
              + wet * 0.22 * sin(p * 9.1 + ph * 3.0);
        vec2 crossDir = vec2(-windDir.y, windDir.x);
        float cross = 0.18 * sin(p * 1.6 + 0.9) * bend;
        // recomputed rather than added to, because `wave` moved under it
        lean = windDir * (amp * bend * wave) + crossDir * (amp * cross);
      }
      w.xz += lean;
      // ------- and the tip comes DOWN as it goes over
      //
      // A stem is not a rubber band: bending it does not make it longer.
      // Displacing XZ alone silently stretches every blade as it leans,
      // which is exactly the look of grass sliding rather than bending.
      // Holding the arc length instead, the tip drops by about lean^2/2H
      // -- the second-order term of the circular arc, which at these
      // amplitudes is the whole of it. Capped at half the vertex's own
      // height so a gale folds a tuft over rather than through the floor.
      //
      // dot(lean, lean) IS L squared, so the square root this used to take
      // was computed only to be squared again on the next line. Same
      // number, one fewer sqrt per vertex of every grass mesh in the world.
      w.y -= min(dot(lean, lean) / (2.0 * H), vertex_position.y * 0.5);
      // tip bob: a little vertical give under the same gust (tier 2)
      if (grassDetail >= 2.0) {
        w.y += amp * bend * 0.07 * sin(p * 1.85 + 0.6);
      }

      // ------- WEIGHT: what is lying on the blade, which is not the wind
      //
      // Rain and snow do not push a tuft downwind, they pull it DOWN --
      // and snow keeps pulling after the fall stops, which is why it reads
      // off the settled cover rather than off the snowfall. The bearing is
      // the tuft's own (`ph`), so a snowed-under meadow slumps in every
      // direction like something loaded, instead of leaning as one.
      float load = wet * 0.16 + snow * 0.46;
      if (load > 0.0) {
        vec2 slump = vec2(cos(ph), sin(ph));
        w.xz += slump * (load * bend * H * 0.22);
        w.y -= load * bend * H * 0.30;
      }

      // ------- FOOT CRUSH, and the TRAIL behind it
      //
      // A blade somebody walks through does not get shorter, it LIES DOWN:
      // it folds away from the foot and ends up along the ground pointing
      // where the walker went. Shrinking its height was the first version
      // of this and it reads as the meadow deflating -- the tuft stays
      // upright and merely becomes a smaller upright tuft. So there are
      // three parts, and the first two are the ones that matter:
      //
      //   LAY OVER   the tip travels outward by most of the blade's own
      //              height, which is what folding a stem flat actually
      //              looks like from above
      //   DROP       and comes down by nearly all of it, so the fold ends
      //              near the ground rather than sticking out sideways
      //   SQUASH     a little residual shortening, because a folded blade
      //              is foreshortened as well as bent
      //
      // Slots past the live feet are TRAIL: same maths, weaker and much
      // wider-lived, so the path somebody walked stays parted behind them.
      // Nothing here needs to know which is which -- a crumb is a foot
      // that is fading.
      if (crushN > 0.5) {
        for (int ci = 0; ci < 8; ci++) {
          if (float(ci) >= crushN) break;
          vec4 cr = crush[ci];
          vec2 d = w.xz - cr.xy;
          float rad = max(cr.z, 0.5);
          // Reject on the SQUARED distance. Almost every vertex of a
          // route's meadow is outside almost every crush disc, so this
          // loop is a rejection loop that happened to be paying for a
          // square root on each miss -- eight per vertex while walking.
          // The sqrt now runs only on the handful of vertices that are
          // actually inside a disc.
          float d2 = dot(d, d);
          if (d2 < rad * rad) {
            float dist = sqrt(d2);
            float t = 1.0 - dist / rad;
            t = t * t * cr.w;
            vec2 dir = (dist > 0.05) ? (d / dist) : windDir;
            // outward part + a little with the wind so a step reads as a wake
            w.xz += dir * (t * bend * H * 0.62)
                  + windDir * (t * bend * H * 0.16);
            // and DOWN with it: this is the difference between a blade that
            // has been folded over and one that has been made shorter
            w.y -= t * bend * vertex_position.y * 0.78;
            // A NEGATIVE strength is Grass3D's spring-back overshoot -- the
            // blade passing upright on its way back -- so the flatten runs
            // the other way and the tuft stands a shade proud for a moment.
            // Clamped both ends: a full crush may not fold a blade through
            // its own root, and a kick may not shoot it into the sky.
            w.y *= clamp(1.0 - t * (0.10 + 0.22 * hN), 0.72, 1.08);
          }
        }
      }

      // ------- and what has piled on this blade (see vGrassCap)
      //
      // Weighted toward the top of the tuft, because that is where snow
      // that fell out of the sky ends up: a crown catches it, the stem
      // under the crown does not. smoothstep rather than a linear ramp so
      // there is a green base rather than a gradient from root to tip.
      // Gated on `snow` because the whole of winter is a uniform: on every
      // frame that is not a snowfall this is one compare, not a smoothstep
      // per vertex of every meadow in the world.
      if (snow > 0.0) {
        vGrassCap = snow * smoothstep(0.30, 0.95, hN);
      }
    }
    // THE WATER SURFACE, which is the only geometry in this world that
    // stands below zero -- it is recessed to -2 so the shoreline shows a
    // lip, and every other class sits at zero or above (see Water.lua).
    // So the test is a compare on a number the mesh already carries, and
    // costs no attribute and no memory.
    //
    // Identity is the height test ALONE. Motion (swell) is a separate
    // axis: freeze damps swell to zero on the CPU, and ice still needs
    // vWater set so the fragment can paint frozen bands. FLAT with no
    // freeze leaves both zero and the still plane untouched.
    //
    // The displacement is a function of world XZ ALONE (Y = f(XZ)), which
    // is what keeps the surface watertight: two quads meeting at a shared
    // corner are moved by the same amount, so the mesh never opens a seam
    // even though it is unindexed and they do not share a vertex.
    //
    // The normal comes free with it. The height is two sines, so its
    // gradient is two cosines -- the exact analytic slope, not a
    // difference of samples, and it is what the sparkle below reflects
    // the sun off.
    vWater = 0.0;
    // Always mark recessed water geometry so optional surface art
    // (assets/water/water.png) can replace the tileset tile even under FLAT.
    vWaterSurf = (vertex_position.y < -1.0) ? 1.0 : 0.0;
    vWave = vec3(0.0, 1.0, 0.0);
    vSwellH = 0.0;
    if (vertex_position.y < -1.0 && (swell > 0.0 || iceLift > 0.0)) {
      vWater = 1.0;
      // Body size + wind advection + crest steepening -- byte for byte with
      // Water.heightField / phaseAt (feet and mesh share one ocean).
      float bf = 0.90 + 0.35 * sin(w.x * bodyKx) * cos(w.z * bodyKz);
      float adv = waterAdvect * waterEnergy * dot(w.xz, waterCurrent);
      float ph = swellPhase + adv;
      float a = dot(w.xz, swellA) * bf - ph;
      float b = dot(w.xz, swellB) * bf + ph * 0.7;
      float h = sin(a) * 0.55 + sin(b) * 0.45;
      // Gerstner-ish Y steepening: sharpens crests under chop energy
      float ah = abs(h);
      h = h + waterSteep * h * ah;
      w.y += swell * h + iceLift;
      vSwellH = h;
      if (swell > 0.001) {
        // d/dx of sin(k·x*bf - p) and of steep term ≈ (1+2*steep*|h|)*cos chain
        float chain = 1.0 + 2.0 * waterSteep * ah;
        vec2 g = swellA * (bf * cos(a) * 0.55) + swellB * (bf * cos(b) * 0.45);
        g *= chain;
        vWave = normalize(vec3(-g.x * swell, 1.0, -g.y * swell));
      }
    }
    // The shadow lookup runs off `sunModel`, not `model`. For terrain the
    // two are the same matrix, but a character is drawn as a slab LEANING
    // back by the camera's pitch -- a trick played on the viewer, which
    // the sun never saw: it lit the upright card. Looking up with the
    // leaned position asks whether the sun reached a place the figure is
    // not, and since the lean tips the body north and shadows now fall
    // north, every sprite's own card fell across its front. Looking up
    // with the card's position asks the question the sun actually
    // answered. (The pull below is excluded for the same reason: it is a
    // depth trick aimed at the camera's own buffer.)
    vSun = (sunVP * (sunModel * vertex_position)).xyz;
    // The curved world (see WorldCurve): drop every vertex by the square
    // of how far its column stands from the camera's focus. Applied AFTER
    // the shadow lookup above and clear of the wireframe's model space, so
    // both are worked out on the flat world and the bend carries them
    // along -- which is why neither has to know this exists. Along Y only,
    // so a column moves as one piece: the world tips away and the
    // buildings standing on it stay upright.
    // CLAMPED, which matters to exactly one thing: the far skyline. The
    // drop goes as the SQUARE of the distance, so land ten view-heights
    // out falls a hundred times what land one view-height out does -- with
    // the bend on, every silhouette lib/Skyline.lua stands up would be
    // kilometres under the map before it was ever drawn. Past the cap the
    // world stops rolling and simply lies flat, which is also what a real
    // horizon does: curvature near, plateau far. Nothing that existed
    // before this line can reach the cap -- the drawn world ends around
    // half a view-height out and the bend there is a rounding error -- so
    // the near roll is exactly the roll it always was.
    if (curve.z > 0.0) {
      vec2 cd = w.xz - curve.xy;
      w.y -= min(dot(cd, cd) * curve.z, curve.w);
    }
    // camera-ward pull: move the vertex along ITS OWN ray to the eye.
    // This is a pure depth bias -- the projection of a point moved along
    // its eye ray is bit-identical, so there is no screen drift at all.
    // (An earlier CPU version translated along the central view axis,
    // which preserved only the screen centre and made off-centre sprites
    // and grass swim against the ground while the camera scrolled.)
    if (pull > 0.0) {
      w.xyz += normalize(eye - w.xyz) * pull;
    }
    return vp * w;
  }
#endif
#ifdef PIXEL
  uniform Image sunMap;
  uniform float sunDark;      // >0 = there is a map to sample; see Light.lua
  uniform float sunBias;
  uniform vec2 sunTexel;

#ifdef SUN_SOFT
  // How wide the blocker search looks, in shadow-map texels. It doubles as
  // the ceiling on the filter, so it is also the widest any shadow edge can
  // get -- past about eight texels the eight taps below start showing as
  // eight, and the honest fix for that is more taps rather than a wider
  // reach.
#define SUN_SEARCH 7.0
  // Texels of half-shadow per unit of stored depth between blocker and
  // receiver. ShadowMap works it out per frame from the sun's apparent size,
  // the frustum's own depth and the rung's texel -- none of which this
  // shader can see -- so what arrives is one number that turns a depth gap
  // straight into a filter width. See ShadowMap.softness.
  uniform float sunSoft;
#endif

  // the two-channel pack ShadowMap writes: high byte, then low
  float sunDepth(vec2 uv) {
    vec4 c = Texel(sunMap, uv);
    return c.r + c.g * (1.0 / 255.0);
  }

#ifdef SUN_SOFT
  // One tap of the blocker search: (that texel's depth, 1) when something
  // stands between this fragment and the sun there, and (0, 0) when nothing
  // does -- so four of them sum straight into a total and a count.
  //
  // A function rather than a macro because the shading language here is the
  // ES dialect, which does not take a backslash line continuation: a
  // multi-line macro will not compile at all.
  vec2 blockerTap(vec2 base, vec2 off, float z) {
    float t = sunDepth(base + off);
    return t < z ? vec2(t, 1.0) : vec2(0.0);
  }
#endif

  // The LIT FRACTION: 1.0 in full sun, 0.0 in full shadow. Four taps half a texel
  // out on the diagonals: a 2x2 box filter, which is what turns the
  // shadow map's texel staircase into a one-pixel soft edge.
  float sunlight(vec3 p) {
    if (sunDark <= 0.0) return 1.0;
    // outside the sun's frustum nothing was recorded, so nothing occludes
    if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0 || p.z > 1.0) {
      return 1.0;
    }
    // Ease the shadows off at the frustum's rim. The map covers the ground
    // the camera can see out to a cap, and past the low rungs -- 75 degrees
    // especially -- the horizon is further than any box worth paying for.
    // Without this the covered region simply ENDS, drawing a hard line
    // across the middle distance where every shadow stops at once; with it
    // the far field just loses them, which reads as distance.
    vec2 e = min(p.xy, 1.0 - p.xy);
    float edge = smoothstep(0.0, 0.06, min(e.x, e.y));
    if (edge <= 0.0) return 1.0;
    float z = p.z - sunBias;
#ifdef SUN_ONE_TAP
    // SHADOWS LOW: one tap, so the shadow wears the map's own texel
    // staircase instead of a filtered edge. Four dependent texture fetches
    // per fragment is the single most expensive line in this shader on a
    // mobile part, and the edge they buy is landing inside one display
    // pixel once the render scale is anything but FULL.
    float lit = step(z, sunDepth(p.xy)) * 4.0;
#elif defined(SUN_SOFT)
    // SHADOWS SOFT: the shadow's edge SOFTENS WITH DISTANCE from whatever
    // throws it. A sun is a disc rather than a point, so the further a
    // receiver stands from its blocker the wider the band that can see
    // part of the disc and not the rest -- which is why a lamp post has a
    // crisp shadow at its foot and a woolly one at its far end, and why a
    // shadow map's one fixed edge width never quite reads as sunlight.
    //
    // This is the cheap standard approximation of that, and it is a RAY
    // MARCH in the same family as everything in RayFX: the sun's own depth
    // record is a heightfield, and the question "how far away is what is
    // blocking me" is answered by reading it rather than by knowing
    // anything about the scene.
    //
    //   1. BLOCKER SEARCH. Four taps over a wide ring, keeping the depths
    //      that are nearer the sun than this fragment -- those are the
    //      things standing between it and the light. Their average is how
    //      far up the ray the blocker sits.
    //   2. PENUMBRA. The gap between blocker and receiver, over the
    //      blocker's own distance: the similar-triangles estimate of how
    //      wide the half-shadow is.
    //   3. FILTER at that width. Eight taps on a disc, so a wide penumbra
    //      is genuinely soft rather than a wide staircase.
    //
    // Twelve fetches against the four above. It is the top rung of the
    // SHADOWS row and it is meant to be.
    vec2 s = sunTexel * SUN_SEARCH;
    vec2 found = blockerTap(p.xy, s * vec2( 1.0,  0.4), z)
               + blockerTap(p.xy, s * vec2(-0.4,  1.0), z)
               + blockerTap(p.xy, s * vec2(-1.0, -0.4), z)
               + blockerTap(p.xy, s * vec2( 0.4, -1.0), z);
    float blocker = found.x, hits = found.y;
    float lit;
    if (hits < 0.5) {
      // nothing between this fragment and the sun anywhere in the search
      // ring, which is most of a sunlit map
      lit = 4.0;
    } else {
      blocker /= hits;
      // A DIRECTIONAL light's penumbra grows with the GAP between blocker
      // and receiver and with nothing else -- the sun's rays are parallel,
      // so there is no distance-to-the-light in the geometry to divide by
      // (that ratio is the spot-light form of this formula, and using it
      // here would widen every shadow near the frustum's near plane and
      // narrow it at the far one, for no reason a viewer could name).
      // Clamped at one texel below, so a blocker sitting right on the
      // surface -- a contact point -- keeps a crisp edge.
      float w = clamp((z - blocker) * sunSoft, 1.0, SUN_SEARCH);
      vec2 f = sunTexel * w;
      // eight on a disc -- four out at the rim and four halfway in, so a
      // wide penumbra fills rather than ringing. Halved at the end to put
      // eight taps back onto the four-tap scale the caller reads.
      lit = (step(z, sunDepth(p.xy + f * vec2( 0.92,  0.38)))
           + step(z, sunDepth(p.xy + f * vec2( 0.38, -0.92)))
           + step(z, sunDepth(p.xy + f * vec2(-0.92, -0.38)))
           + step(z, sunDepth(p.xy + f * vec2(-0.38,  0.92)))
           + step(z, sunDepth(p.xy + f * vec2( 0.50,  0.50)))
           + step(z, sunDepth(p.xy + f * vec2( 0.50, -0.50)))
           + step(z, sunDepth(p.xy + f * vec2(-0.50,  0.50)))
           + step(z, sunDepth(p.xy + f * vec2(-0.50, -0.50)))) * 0.5;
    }
#else
    float lit = step(z, sunDepth(p.xy + sunTexel * vec2(-0.5, -0.5)))
              + step(z, sunDepth(p.xy + sunTexel * vec2( 0.5, -0.5)))
              + step(z, sunDepth(p.xy + sunTexel * vec2(-0.5,  0.5)))
              + step(z, sunDepth(p.xy + sunTexel * vec2( 0.5,  0.5)));
#endif
    // The LIT FRACTION now, not the darkening: 1 in full sun, 0 in full
    // shadow. What a shadow costs is no longer decided here -- it is the
    // difference between the two lights the caller split (see Light.lua),
    // and sunDark survives only as the gate above that says whether there
    // is a map worth sampling at all.
    return 1.0 - edge * (1.0 - lit * 0.25);
  }

  // A stable 0..1 value per VOXEL of world space. Everything the snow varies
  // by is cut from this, so a drift is a property of the place it lies in:
  // it does not crawl when the camera pans, it does not swim when a mesh is
  // rebuilt, and two maps meeting at a seam agree about it because they
  // agree about where they are.
  //
  // Sin-free on purpose. The usual `fract(sin(dot(p, k)) * 43758.5)` costs a
  // transcendental per call and mobile parts disagree about sin's precision
  // at large arguments -- exactly where world coordinates live by the far
  // side of a route -- so the same rock would hash differently on two
  // drivers. This is multiply-and-fract throughout.
  float voxelHash(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.x + p.y) * p.z);
  }

#ifdef VOXEL_GRID
  uniform float gridDark;     // how far toward black a seam pulls; 0 = off
  uniform float gridWidth;    // seam width, in display pixels

  // How much of this fragment a voxel seam covers, 0 to 1.
  float voxelSeam(vec3 p) {
    // how much of `p` this fragment spans on screen, per axis: the
    // conversion from model units to display pixels, measured rather than
    // derived, so it holds under any camera pitch or zoom
    vec3 w = fwidth(p);
    vec3 d = abs(fract(p + 0.5) - 0.5);      // distance to the nearest plane
    // The axis a face does not vary along is that face's own normal, and
    // its distance is a constant zero -- take it at face value and every
    // face floods solid. Push those axes out of reach instead of dividing
    // by their zero.
    vec3 live = step(1e-4, w);
    vec3 px = d / max(w, vec3(1e-6)) + (1.0 - live) * 1e6;
    float near = min(min(px.x, px.y), px.z);
    // Fade out where a voxel is too small to hold a line. Survey zoom
    // draws a world pixel at about a display pixel, and a wall seen nearly
    // edge-on squashes one to nothing at any zoom -- either way the seams
    // land closer together than they are wide, and drawn anyway they stop
    // being a wireframe and become a flat 45% dimming of the whole scene.
    // The tightest axis decides, which is the honest test of whether the
    // grid can be resolved at all.
    float span = 1.0 / max(max(w.x, max(w.y, w.z)), 1e-6);
    float fade = clamp((span - 2.0) * 0.5, 0.0, 1.0);
    // the textbook antialiased line: solid within the half-width, fading
    // over the one pixel outside it
    return fade * clamp(gridWidth * 0.5 + 0.5 - near, 0.0, 1.0);
  }
#endif

  uniform vec3 ghostColor;    // the flat silhouette colour
  uniform float ghost;        // 0 = shade normally, 1 = flatten to it
  // Aerial perspective (see lib/Aerial.lua). Packed rather than four
  // uniforms because every one of them is a property of the same ramp.
  uniform vec4 fog;           // x = near, y = 1/span, z = top strength, w = rungs
  uniform vec3 fogColor;      // the hour's haze -- the sky's own palest band
  uniform vec3 fogEye;        // the camera itself: haze is path length to IT
  // The hour's light, split in two (see Light.lua). A surface always gets
  // `skyTint`; `sunTint` is what the sun adds on top where it reaches. In
  // FLAT the whole hour goes in skyTint and sunTint is zero, which is the
  // single multiply this shader used to do.
  uniform vec3 skyTint;
  uniform vec3 sunTint;
  uniform vec3 sunRay;        // the direction the light TRAVELS, normalized
  uniform float sparkle;      // how far toward white a lit crest lifts
  uniform vec2 glint;         // the slope window that catches it
  uniform float foamPhase;    // the tide's clock, for the foam's lapping
  // Fragment paint phase snap (rad). 0 = continuous. Vertex geometry ignores
  // this -- only the cel block's re-evaluated height / noise / lip use it.
  uniform float paintPhaseStep;
  // World-XZ paint cell (liquid / ice). Spatial snap for band/noise edges.
  uniform float paintWCell;
  uniform float paintWCellIce;
  uniform float freeze;       // 0..1 progressive ice (CPU climate state)
  uniform float crest;        // 0..1 mid-water crest foam (rain/wind chop)
  uniform float snowVeil;     // 0..1 soft white veil while snow hits liquid
  uniform float iceSparkle;   // cold silver glint on frozen plates
  uniform float stepJitter;   // 0..1 footstep crack on ice (visual only)
  uniform float waterWet;     // 0..1 rain on water (micro-ripples + heavy foam)
  // Optional world-XZ surface art (assets/water/water.png). Sampler always
  // bound (blank when the file is missing); waterArtOn gates the replace.
  uniform Image waterArt;
  uniform float waterArtOn;   // 0 = tileset tile, 1 = sample waterArt
  uniform float waterArtScale;// world pixels per one full UV cycle
  // iceLift / bodyKx / bodyKz live with the vertex swell uniforms
  uniform Image glassMask;    // opaque where the atlas texel is window glass
  uniform vec2 glassSize;     // the mask's dimensions: tc -> atlas texels
  uniform float glassNight;   // 0 = daylight .. 1 = the lamps are on
  uniform vec3 lampColor;     // what the lamps BURN (DayNight.lampColor)
  uniform float glassPhase;   // the glint's phase: advances with TRAVEL
  uniform float glassGlint;   // and its strength: 0 while standing still
  uniform float glassOn;      // 0 for sprite-sheet draws (see Voxel3D.glass)
  // Up to eight nearby street lamps. xy = world XZ, z = radius and w =
  // intensity.  They are individual warm pools, not a global yellow tint.
  //
  // The flame is a POINT at (lamp.xy, lampHeight), not a disc painted on the
  // floor: a lamp that only knows its ground position lights a wall beside it
  // exactly as hard as the road beneath it, which is the single thing that
  // makes fake lighting look fake. See localLamp.
  uniform vec4 lamp0;
  uniform vec4 lamp1;
  uniform vec4 lamp2;
  uniform vec4 lamp3;
  uniform vec4 lamp4;
  uniform vec4 lamp5;
  uniform vec4 lamp6;
  uniform vec4 lamp7;
  uniform float lampGlow;

#ifdef ANIME_CEL
  // The cel rung's three numbers (see lib/Anime.lua). Declared inside the
  // define so a build without the rung carries no unused uniform and the
  // send below is free to fail silently against it.
  uniform float animeBands;   // flat steps per unit of luminance
  uniform float animeCell;    // the render-buffer cell the step snaps to
  uniform float animeDither;  // checkerboard jitter, in band units
#endif
  uniform float lampHeight;   // world y of the flame (from the post's bake)
  uniform float lampFlicker;  // the gas clock; 0 holds every lamp perfectly still
  uniform vec3 lampCore;      // the hot near-white at the centre of a pool
  // SNOW ON THE GEOMETRY ITSELF. 0..1, and it lands on the faces that point
  // at the sky -- vUp, which is a real face normal rather than a guess read
  // off how bright the face draws (see the `lie` line below for what that
  // guess cost). Which is why this can lie on a tree, a stone wall, a roof
  // and a ledge alike without knowing what any of them are: an up-facing
  // surface is an up-facing surface.
  //
  // Sent per DRAW and defaulting to zero, like `sway` and `glassOn`, so the
  // terrain wears it and the characters standing on the terrain do not.
  uniform float snowTop;
  uniform vec3 snowColor;
  uniform float snowSide;     // how much of it a flank takes; 1 on the top

  // One lamp's contribution here. Returns the energy in .x and how near the
  // flame this fragment is in .y, which the caller uses to run the pool from
  // amber at the rim to near-white at the core -- a real flame is not one
  // colour, and a pool that IS one colour reads as a painted circle.
  vec2 localLamp(vec4 lamp) {
    if (lamp.w <= 0.0 || lamp.z <= 0.0) return vec2(0.0);
    // How far the pool REACHES is a ground measurement, and how bright it is
    // at a point is a 3D one. Keeping them apart matters: run the cutoff off
    // the 3D distance instead and the lantern's own height eats most of the
    // radius before the light ever touches the road, so raising LIGHT_RADIUS
    // to widen a pool also dims it, and the two can never be tuned at once.
    // `ground`, not `flat`: flat is a GLSL interpolation qualifier, and using
    // it as a name compiles nowhere -- the whole scene shader fails and the
    // engine drops to the 2D renderer without a word.
    vec2 ground = vWorld.xz - lamp.xy;
    float rad2 = dot(ground, ground);
    float r2 = lamp.z * lamp.z;
    if (rad2 >= r2) return vec2(0.0);         // early out: most fragments

    vec3 d = vec3(lamp.x, lampHeight, lamp.y) - vWorld;
    float dist2 = dot(d, d);

    // The window falls to zero WITH a zero derivative at the rim. An
    // unwindowed inverse square has to be cut off somewhere, and the eye finds
    // that ring before it finds anything else in the frame.
    float nd2 = rad2 / r2;
    float win = 1.0 - nd2 * nd2;
    // Inverse square softened by the flame's own height, so the fragment
    // directly under the lantern sits at half strength and there is somewhere
    // left to climb as you walk in under it.
    float k = max(lampHeight * lampHeight, 1.0);
    float atten = win * win * k / (dist2 + k);

    // Lambert against the only normal this renderer carries. vUp is the
    // mesher's own face normal (see the sign of VertexShade), so an up-facing
    // surface takes the light from directly overhead and a flank takes the
    // horizontal share instead. Which way a flank FACES is unknowable here,
    // so it gets the horizontal magnitude -- correct for the walls turned
    // toward the post, generous for the ones turned away, and both are better
    // than the flat wash that ignores the question.
    float invd = inversesqrt(max(dist2, 1.0));
    vec3 L = d * invd;
    float ndl = mix(length(L.xz), max(0.0, L.y), vUp);
    // Bounce: a street is not a vacuum, and a face the flame cannot see is
    // dim rather than black.
    ndl = 0.20 + 0.80 * ndl;

    // A gas flame is never quite still. Two octaves, phased off the post's own
    // world position so a row of lamps breathes out of step instead of
    // blinking as one, and only +-6% so it reads as life, not as a fault.
    float ph = lamp.x * 0.017 + lamp.y * 0.011;
    float flick = 1.0 + 0.06 * sin(lampFlicker + ph)
                            * (0.6 + 0.4 * sin(lampFlicker * 2.7 + ph * 3.1));

    return vec2(atten * ndl * lamp.w * flick, atten);
  }

  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 p = Texel(tex, tc);
    // sprite sheets key GB OBJ color 0 to alpha 0; discarding rather than
    // blending keeps those texels out of the depth buffer, so a model never
    // carves a transparent hole out of whatever stands behind it
    if (p.a < 0.5) discard;
    // Two lights, not one. A shadow is not an absence of light, it is a
    // place lit by a DIFFERENT light -- the sky, which is cool and comes
    // from everywhere, rather than the sun, which is warm and comes from
    // one direction. So the sky's share is unconditional and the sun's is
    // gated on whether it reached this fragment, and a shadow ends up
    // cooler rather than merely darker. In full sun the two sum back to
    // the tint this line used to multiply by, so lit surfaces are where
    // they always were and only the shadows moved.
    // Held in a variable rather than inlined, and it is not tidiness: the
    // snow below stands in this same light, and calling sunlight() a second
    // time for it would pay the shadow map's four-to-twelve texture fetches
    // twice per fragment -- the most expensive line in this shader, doubled,
    // on every frame of a snowfall.
    float lit = sunlight(vSun);
    vec3 light = skyTint + sunTint * lit;
    vec2 lamps = localLamp(lamp0) + localLamp(lamp1)
               + localLamp(lamp2) + localLamp(lamp3)
               + localLamp(lamp4) + localLamp(lamp5)
               + localLamp(lamp6) + localLamp(lamp7);
    // The lamp adds light BEFORE the material is shaded, so paving, walls and
    // foliage keep their own colour under the warm spill instead of becoming
    // a flat yellow overlay.
    //
    // Saturating rather than clamping. min() puts a hard edge wherever two
    // pools overlap -- a visible seam down the middle of a street, exactly
    // where the light should be strongest -- while x/(1+kx) keeps climbing,
    // just ever more slowly, so an overlap is brighter than either lamp and
    // still never blows the four-colour look out to white.
    //
    // The 1.6 is the ceiling, and it is the difference between a lit street
    // and a lit AFTERNOON: a city block puts eight pools inside one phone
    // screen, and with a loose ceiling they summed until the whole frame was
    // brighter than the sky above it and the night was simply gone. This
    // asymptote holds the total at ~0.6 however many posts overlap, so the
    // dark BETWEEN the pools survives -- which is the only thing that makes
    // the pools read as light at all.
    float energy = lamps.x / (1.0 + lamps.x * 1.6);
    // Amber at the rim, hot near the flame. Scaled because a single pool's
    // attenuation peaks near a half, and the core should still reach white.
    vec3 warm = mix(lampColor, lampCore, clamp(lamps.y * 1.6, 0.0, 1.0));
    light += warm * energy * lampGlow;
#ifdef ANIME_CEL
    // THE CEL STEP. Everything above has finished summing light and nothing
    // below has spent it yet, which is the one instant where a single
    // quantisation catches the sky, the sun AND the lamps -- the whole
    // light, which is what this rung was asked for.
    //
    // Banded by LUMINANCE and rescaled, not per channel. Per channel is the
    // obvious spelling and it is wrong here: R, G and B cross their own
    // thresholds at different values, so every boundary becomes a coloured
    // fringe -- and this shader deliberately carries two differently
    // COLOURED lights (a cool sky, a warm sun, see the note over `lit`) plus
    // an amber lamp on top, so those fringes would land on every shadow edge
    // and every pool of lamplight in the mod. One luminance step keeps the
    // hue the two-light split built and moves only how bright it is.
    float lum = dot(light, vec3(0.2126, 0.7152, 0.0722));
    if (lum > 0.0001) {
      // The dither grid, on a CELL of the render buffer -- the cel water's
      // floor(sc / cell) idiom, and here for the same failure: the sun moves
      // all day, so every boundary sweeps, and an undithered hard step
      // sweeping at a fraction of a pixel per frame crawls. Snapping the
      // checker to whole cells is what stops the dither itself from
      // swimming underneath the boundary it is meant to soften.
      vec2 gc = floor(sc / max(animeCell, 1.0));
      float check = mod(gc.x + gc.y, 2.0);
      float steps = max(animeBands, 1.0);
      // Threshold jittered rather than the value: the checker has to move
      // WHERE the step happens, so that two neighbouring cells fall on
      // opposite sides of it and the boundary reads as a two-tone weave.
      float t = lum * steps + (check - 0.5) * animeDither;
      // Rounded to the NEAREST step, not floored to the band below it.
      // Floor alone hands every fragment the dimmest light in its band and
      // the world goes dark by half a step everywhere; rounding is unbiased,
      // so the diorama keeps the average brightness it had and only the
      // distribution changes -- which is the whole intent.
      //
      // Not band CENTRES either, which is the other obvious spelling and is
      // a trap: a centre can never return less than half a band, so every
      // fragment darker than that gets LIFTED to it. Luminance 0.01 in an
      // unlit cave would come back as 0.125 -- twelve times brighter -- and
      // the darkest rooms in the game would glow. Rounding sends them to
      // zero instead, which is what the darkest cel shade is.
      //
      // No clamp at the top: a lamp core sits above 1.0 (see the x/(1+kx)
      // ceiling above) and goes on climbing in steps of the same size
      // rather than flattening into a brightest band.
      float q = max(floor(t + 0.5), 0.0) / steps;
      // And the ratio is bounded on the way UP. Rounding moves luminance by
      // at most half a step in absolute terms, but as a RATIO that is
      // unbounded as the fragment gets darker -- near black, half a step is
      // a multiplication. Capping at one step's worth keeps a dim corner
      // dim while leaving every fragment bright enough to have a band land
      // exactly where the quantisation put it.
      light *= clamp(q / lum, 0.0, 1.0 + 1.0 / steps);
    }
#endif
    vec3 rgb = p.rgb * vShade * light;
    // Optional water surface art: replace the tileset water tile's albedo
    // on every recessed water face (lakes / rivers). Cel paint below still
    // multiplies on top when swell / freeze is active. Scrolls gently with
    // the same phase + current the foam uses so the picture moves with the
    // pond rather than sitting like a decal.
    if (waterArtOn > 0.5 && vWaterSurf > 0.01) {
      float scale = waterArtScale;
      if (scale < 8.0) scale = 64.0;
      vec2 scroll = waterCurrent * foamPhase * 0.04;
      vec2 uv = fract(vWorld.xz / scale + scroll);
      vec3 art = Texel(waterArt, uv).rgb;
      rgb = mix(rgb, art * vShade * light, clamp(vWaterSurf, 0.0, 1.0));
    }
    // THE CEL WATER. Three effects, all analytic, all keyed off varyings
    // the mesh already carries -- and all of them FLAT-shaded on purpose:
    // this is a four-colour world drawn on a pixel grid, and a smooth
    // gradient over it reads as an airbrush. Every boundary here is a hard
    // step, softened only by the checkerboard dither the 8-bit sky already
    // established as this mod's idiom for "between two colours".
    //
    // vWater tells the three zones apart with no new data: exactly 1 on
    // the surface (every plane vertex is water), interpolating 1 -> 0 up a
    // shoreline lip face (bottom edge attached to the water, top edge to
    // the bank), 0 everywhere else. FLAT with no freeze never sets it, so
    // the old still plane is untouched. Gated on vWater alone (not
    // sparkle): rain kills the glint but must KEEP bands, lip foam and
    // crest foam -- a dull wet pond is still a painted pond.
    if (vWater > 0.0) {
      // Band / foam decisions snap to a CELL of the render buffer -- the
      // same idiom the sky uses for its dither grid (Sky.lua: floor(sc/cell)).
      // Without this, hard step()s ride a continuously moving swell field
      // and crawl one fragment at a time: the "ants" on the pond, made
      // worse at RES 1/2 where nearest upscale freezes every crawl step
      // onto a display pixel. cell=2 is one display pixel at the default
      // rung and still reads as the pixel grid at FULL.
      float cell = 2.0;
      vec2 gc = floor(sc / cell);
      float check = mod(gc.x + gc.y, 2.0);
      if (vWater > 0.98) {
        // ON THE SURFACE -- advanced cel ocean, still only hard steps +
        // checker dither. Height re-evaluated on a world-XZ cell so edges
        // cannot crawl (sky floor(sc/cell) idiom). Geometry is Y=f(XZ);
        // paint snaps.
        // Spatial paint grid (sky floor idiom). Larger cell = thicker band
        // edges, fewer fragments on a hard step as continuous phase slides.
        // paintPhaseStep is optional temporal snap (default 0 -- see Water.lua).
        float wcell = mix(paintWCell, paintWCellIce, freeze);
        if (wcell < 1.0) wcell = 1.0;
        vec2 wz = floor(vWorld.xz / wcell) * wcell;
        float bf = 0.90 + 0.35 * sin(wz.x * bodyKx) * cos(wz.y * bodyKz);
        float adv = waterAdvect * waterEnergy * dot(wz, waterCurrent);
        float ph = swellPhase + adv;
        if (paintPhaseStep > 0.001) {
          ph = floor(ph / paintPhaseStep + 0.5) * paintPhaseStep;
        }
        float wa = dot(wz, swellA) * bf - ph;
        float wb = dot(wz, swellB) * bf + ph * 0.7;
        float hQ = sin(wa) * 0.55 + sin(wb) * 0.45;
        float ahQ = abs(hQ);
        hQ = hQ + waterSteep * hQ * ahQ;
        // Capillary micro-ripples (paint): harmonics of the SAME two trains.
        float micro = waterWet * (1.0 - freeze)
                    * (sin(wa * 2.15 + wb * 0.5) * 0.14
                     + sin(wa * 3.1 - wb * 0.8) * 0.07 * waterEnergy);
        float jit = (check - 0.5) * 0.16 + stepJitter * (check - 0.5) * 0.45;
        float h = hQ + micro + jit;
        // ---- DEPTH COLOUR (Roystan toon-water, free tutorial; adapted to
        // cel without a depth buffer). Shallow vs deep is the swell height
        // itself: troughs = deep, crests = shallow. Hard mixes only -- no
        // smooth gradient airbrush. Source techniques:
        // https://roystan.net/articles/toon-water/ (MIT-friendly tutorial)
        float depth01 = clamp(0.5 - 0.5 * h, 0.0, 1.0); // 0 crest .. 1 trough
        float depthRung = floor(depth01 * 3.0 + 0.001) / 3.0; // 4 hard rungs
        // shallow (0.325, 0.807, 0.971) / deep (0.086, 0.407, 1.0) -- Roystan defaults
        vec3 shallowCol = vec3(0.325, 0.807, 0.971);
        vec3 deepCol    = vec3(0.086, 0.407, 1.000);
        vec3 depthTint  = mix(shallowCol, deepCol, depthRung);
        // multiply-tint so the tileset art stays legible; freeze kills it
        rgb = mix(rgb, rgb * depthTint * 1.15, (1.0 - freeze) * 0.42);
        // ---- 4-rung height cel (value mass): deep trough / trough / mid / crest
        float d0 = mix(-0.55, -0.28, freeze);
        float d1 = mix(-0.22, -0.08, freeze);
        float d2 = mix( 0.18 - waterWet * 0.04, 0.10, freeze);
        float d3 = mix( 0.42 - waterWet * 0.05, 0.22, freeze);
        float band =
            - step(h, d0) * (0.20 + waterWet * 0.05)
            - step(h, d1) * (0.10 + waterWet * 0.03)
            + step(d2, h) * 0.10
            + step(d3, h) * (0.12 + waterEnergy * 0.04);
        rgb *= 1.0 + band;
        // ---- SURFACE NOISE FOAM (Roystan): binary cutoff on analytic
        // "noise" built from the two trains + a cell hash -- no texture.
        // Scrolls with foamPhase the way his noise scrolls with _Time.
        // Gated on chop/rain: a CALM clear pond keeps bands+depth only --
        // floating mid-pond foam was free frame-to-frame flip under nearest
        // upscale (shimmer probe R0/R3: continuous churn is swell+paint).
        float chopPaint = clamp(crest + waterEnergy + waterWet, 0.0, 1.0);
        float nScroll = foamPhase * 0.22;
        float noiseSamp = 0.5 + 0.5 * sin(wa * 1.7 + nScroll)
                               * cos(wb * 1.3 - nScroll * 0.7);
        // cheap hash on the band cell for irregularity (no Perlin tex)
        float nHash = fract(sin(dot(wz, vec2(12.9898, 78.233))) * 43758.5453);
        noiseSamp = clamp(noiseSamp * 0.65 + nHash * 0.35, 0.0, 1.0);
        // cutoff rises in troughs (less foam mid-pond), drops near crests
        // and under chop -- shoreline-like density without a depth buffer
        float noiseCut = mix(0.78, 0.48, clamp(crest + waterEnergy * 0.4, 0.0, 1.0));
        noiseCut = mix(noiseCut, 0.88, depthRung); // deep = less floating foam
        float surfaceNoise = step(noiseCut, noiseSamp + (check - 0.5) * 0.08)
                           * (1.0 - freeze) * step(0.04, chopPaint);
        rgb = mix(rgb, vec3(0.93, 0.97, 1.0), surfaceNoise * 0.55);
        // Interference "caustics": hard spots where trains constructively
        // peak -- cel diamonds, not a soft caustic texture. Same calm gate.
        float inter = sin(wa) * sin(wb);
        float caust = step(0.55, inter + (check - 0.5) * 0.20)
                    * (1.0 - freeze) * (0.10 + 0.08 * waterEnergy)
                    * step(0.04, chopPaint);
        rgb *= 1.0 + caust;
        // Cel fresnel: facing-camera water is darker (looking into mass),
        // glancing is brighter. vWave.y is the up component of the analytic
        // normal -- hard steps only.
        float face = vWave.y;
        float fres = step(face, 0.88) * 0.08 + step(face, 0.78) * 0.07;
        fres *= (1.0 - freeze * 0.7);
        rgb *= 1.0 - fres;
        // Wind streaks: foam filaments along current (hard dashed dither).
        // Same paint-phase snap as bands -- continuous foamPhase would
        // rattle the dashes every frame under the nearest upscale.
        float fpPaint = foamPhase;
        if (paintPhaseStep > 0.001) {
          fpPaint = floor(fpPaint / paintPhaseStep + 0.5) * paintPhaseStep;
        }
        float streak = dot(wz, waterCurrent) * 0.11 + fpPaint * 1.7;
        float streakFoam = step(0.72, sin(streak) + check * 0.25)
                         * waterEnergy * (1.0 - freeze) * 0.35;
        // Ice: multi-rung silver plate + crystal diagonals from world cell.
        float iceBand = step(0.45, freeze + (check - 0.5) * 0.22);
        float iceHi = step(0.70, freeze + (1.0 - check) * 0.18);
        float iceXtal = step(0.55, sin((wz.x + wz.y) * 0.08)
                         + (check - 0.5) * 0.30) * freeze;
        rgb = mix(rgb, vec3(0.70, 0.84, 0.98), iceBand * freeze * 0.58);
        rgb = mix(rgb, vec3(0.86, 0.93, 1.0), iceHi * freeze * 0.40);
        rgb = mix(rgb, vec3(0.92, 0.96, 1.0), iceXtal * 0.28);
        // Cold therm deepens the blue of liquid water; warm therm leaves
        // the tile palette alone (hard mix, not a gradient ramp).
        float coldWash = step(waterTherm, 0.35) * (1.0 - freeze) * 0.12;
        rgb = mix(rgb, rgb * vec3(0.85, 0.92, 1.05), coldWash);
        // Melt cracks: dual lattice leads.
        float meltCrack = step(0.10, freeze) * step(freeze, 0.90);
        float crack = step(0.5, check) * meltCrack * 0.32;
        float crack2 = step(0.5, mod(gc.x + floor(gc.y * 0.5), 2.0))
                     * meltCrack * 0.20;
        float crack3 = step(0.5, mod(floor(gc.x * 0.5) + gc.y, 2.0))
                     * meltCrack * stepJitter * 0.25;
        rgb = mix(rgb, rgb * 0.68, crack + crack2 + crack3);
        // Specular rings: analytic normal · sun, quantized. Ice silver
        // lives beside rain-killed sparkle.
        float s = smoothstep(glint.x, glint.y, dot(vWave, -sunRay));
        s = floor(s * 4.0 + 0.5) / 4.0;
        float glintAmt = sparkle + iceSparkle;
        rgb = mix(rgb, vec3(0.93, 0.97, 1.0), s * glintAmt);
        // Breaking crest foam + tip whitewater + wind streaks.
        float breakT = mix(0.66, 0.46, clamp(crest + waterEnergy * 0.35, 0.0, 1.0));
        float crestFoam = step(breakT, h) * crest * (1.0 - freeze);
        float tipFoam = step(0.78, h) * crest * (waterWet + waterEnergy)
                      * (1.0 - freeze);
        // Steepness foam: where |slope| is high (from vWave tilt).
        float slope = 1.0 - vWave.y;
        float steepFoam = step(0.12, slope) * waterEnergy * (1.0 - freeze)
                        * (0.25 + 0.35 * check);
        rgb = mix(rgb, vec3(0.93, 0.97, 1.0),
                  crestFoam * (0.58 + 0.38 * check)
                + tipFoam * 0.60
                + steepFoam * 0.40
                + streakFoam);
        // Snow veil on liquid.
        float veil = snowVeil * (0.42 + 0.22 * check) * (1.0 - freeze * 0.50);
        rgb = mix(rgb, vec3(0.95, 0.97, 1.0), veil);
      } else if (vWater > 0.45) {
        // Shore lip foam -- rides the waterline; chop multiplies reach.
        // Lap clock snapped with paintPhaseStep so the foam edge does not
        // crawl along the bank one fragment at a time (Roystan foam spirit,
        // cel tempo).
        float fpLip = foamPhase;
        if (paintPhaseStep > 0.001) {
          fpLip = floor(fpLip / paintPhaseStep + 0.5) * paintPhaseStep;
        }
        float lap = 0.14 * sin(fpLip * 2.0 + gc.x * cell * 0.23
                                         + gc.y * cell * 0.17);
        float foamEdge = 0.66 + lap - check * 0.11
                       - crest * 0.12 - waterWet * 0.09
                       - waterEnergy * 0.06;
        float foam = step(foamEdge, vWater);
        // Spray flecks above the lip under high energy (still lip band).
        float spray = step(0.55, vWater) * step(foamEdge - 0.08, vWater)
                    * waterEnergy * check * 0.35;
        rgb = mix(rgb, vec3(0.93, 0.97, 1.0), foam * 0.90 + spray);
      }
    }
#ifdef VOXEL_GRID
    // darken what is there rather than painting a colour, so a seam across
    // dark grass and one across a white roof each stay in their own palette
    rgb *= 1.0 - gridDark * voxelSeam(vGrid);
#endif
    // WINDOW GLASS, marked per atlas texel by the mask (see GlassMask).
    // By day a thin diagonal glint crosses the panes WHILE THE VIEW MOVES
    // -- the phase is fed by the camera's own travel and the strength dies
    // within a beat of standing still, because a reflection is something
    // the viewpoint does: still camera, still glass. It lifts the texel
    // toward sky-white and leaves the art visible through it. After dark
    // the pane is LIT: the texel's own shine pattern carried into a warm
    // lamp colour, replacing the shaded answer above -- so a lit window
    // ignores the sun, every shadow and the hour's tint, exactly as a
    // window with a lamp behind it does.
    // glassOn gates the whole thing per DRAW: the mask is shaped like the
    // tileset atlas, and only meshes textured FROM that atlas may consult
    // it -- a character samples its own sprite sheet, whose coordinates
    // land on the mask's pane rectangles by accident and would stripe the
    // cast with lamplight at night.
    float glass = Texel(glassMask, tc).a * glassOn;
    if (glass > 0.0) {
      // the sweep lives in the PANE's own space (atlas texels), not the
      // screen's: a pattern anchored to the screen has the world sliding
      // through it at zoom speed whenever the camera pans, which strobed --
      // worst where the pan and the phase ran opposite ways. Anchored to
      // the glass, panning moves nothing; only the phase does, a fraction
      // of a texel per step, the same in every walking direction.
      float sweep = sin(tc.x * glassSize.x * 0.8 - glassPhase);
      float glint = pow(max(sweep, 0.0), 20.0) * 0.55 * glassGlint;
      vec3 pane = mix(rgb, vec3(0.93, 0.97, 1.0), glint * glass);
      float shine = dot(p.rgb, vec3(0.299, 0.587, 0.114));
      // NOT EVERY WINDOW IS THE SAME LAMP. A hash on the pane's own block in
      // the atlas -- six texels across, the width the mask scans for -- gives
      // each pane a fixed offset in brightness, so a wall of windows reads as
      // a wall of rooms rather than as one light stamped out repeatedly. The
      // hash is deliberately allowed to be imprecise: sin() of a large
      // argument at the fragment default of mediump returns something close
      // to noise, which is all a hash is asked for here, and it returns the
      // SAME noise for the same pane on every driver and every frame -- which
      // is the only property that matters.
      vec2 paneId = floor(tc * glassSize / 6.0);
      float jit = fract(sin(dot(paneId, vec2(12.9898, 78.233))) * 4375.85);
      vec3 lamp = lampColor * (0.5 + 0.55 * shine) * (0.86 + 0.28 * jit);
      rgb = mix(pane, lamp, glassNight * glass);
    }
    // The snow lying ON this surface, if it is one snow can lie on. A hard
    // step rather than a smooth falloff: this is a four-colour world and the
    // boundary between a snowed top and a bare side is a voxel edge, which
    // is exactly where the step is. No geometry, no decal, no float -- the
    // face the camera is already looking at simply goes white.
    if (snowTop > 0.0) {
      // The UP faces take all of it and the flanks take a share, which is
      // the difference between a snowed world and a world with white lids on
      // it. A bush is a rounded blob: from this camera almost every voxel of
      // it you can see is a SIDE, so a top-face-only rule left every hedge in
      // a white town standing green while the ground and the wall tops went
      // pale -- correct about which face points up, wrong about what a
      // snowfall looks like.
      //
      // A STEP on the face's own normal, not a ramp on its brightness.
      //
      // This used to read `smoothstep(0.60, 1.0, vShade)`, on the theory that
      // a shade of 1.0 meant up and the darker a face drew the more it must
      // be turned away. Two things were wrong with it and both showed. A
      // BUILDING's facade is emitted at 1.0 because the south face IS the
      // artwork, so a house tested as sky-facing and took the whole tint --
      // every wall in a snowed town went white. And that same house's ROOF
      // carries VOLUME_TOP_SHADE, which is darker than its walls, so the one
      // surface the snow actually lands on took less of it than the wall
      // underneath. A town in a snowfall came out as white boxes with grey
      // lids, which is the exact inverse of a snowfall.
      //
      // vUp is the real answer: the meshers work each quad's own face normal
      // out of its geometry and hand it over in the sign of the shade. So a
      // roof, a ledge, the ground and the crown of a tree take all of it; a
      // wall, a facade and a tree's front take SNOW_SIDE, whatever brightness
      // any of them happen to draw at.
      // ------- and the one surface a face normal cannot answer for
      //
      // A grass blade is a SIDE. Every honest reading of its geometry says
      // so, vUp is correctly zero along the whole tuft, and the rule above
      // therefore hands a meadow the flank's third and stops -- which is
      // right about the normal and wrong about the winter. Snow lands from
      // above and RESTS ON THE CROWN: winter grass is white on top with
      // green showing underneath, and the boundary between the two is a
      // height on the blade, not a face.
      //
      // `vGrassCap` is that height, already weighted by how much snow has
      // settled (see the vertex stage), and it goes in through the same
      // `lie` the normal does -- so a capped tip takes the full depth and
      // runs through every layer below it (threshold, drift, grain,
      // sparkle) exactly as a roof ridge does. No second snow path, no
      // decal floating over the meadow, and the base of the tuft stays
      // green because its cap is zero.
      float lie = mix(snowSide, 1.0, max(vUp, vGrassCap));
      float depth = snowTop * lie;      // how deep it lies on this face

      // ------- the two noises every layer below is cut from
      //
      // Both are voxel-quantized samples of WORLD space, so neither is a
      // gradient and neither moves: a drift belongs to the place it lies in.
      // It does not crawl when the camera pans, does not swim when a mesh is
      // rebuilt, and two maps meeting at a seam agree about it because they
      // agree about where they are. (A screen-space dither -- which is where
      // the swell's checker lives, because a swell is already moving -- would
      // stand still and let the world slide through it, and every roof in the
      // frame would crawl as you walked.)
      //
      // All three axes go into the hash, which is what lets one line serve
      // every face in the world: on a roof y barely moves and the pattern
      // falls out of x and z, on a wall z is fixed and it falls out of x and
      // y. Two axes would have given one of those a set of stripes.
      //
      // DRIFT is the shape of the fall at about five world pixels -- where it
      // heaped, where the wind scoured it. GRAIN is per world pixel, and it
      // does the dithering a four-colour machine would have done.
      float drift = voxelHash(floor(vWorld * 0.2));
      float grain = voxelHash(floor(vWorld));

      // ------- LAYER 1: where it lies at all
      //
      // The drift moves the THRESHOLD rather than the amount, and that is the
      // difference between snow arriving and snow fading in. A hollow needs a
      // deeper fall before it takes any and a heap takes it early -- so as the
      // weather works, patches appear and then GROW into each other across a
      // roof, instead of the whole surface going evenly paler all at once.
      // The grain breaks each rung, so the edge of a patch is dithered rather
      // than a clean curve, which is the only edge this world knows how to
      // draw. It is one rung wide on purpose: the levels sit a third apart, so
      // a smaller wobble would round both halves of the dither into the same
      // level and do nothing at all.
      float cover = depth * (0.72 + drift * 0.56) + (grain - 0.5) * 0.34;
      // Four rungs, and the top one is 0.86 rather than 1. At a full 1 a
      // covered roof loses its own art entirely and the town turns to white
      // blocks -- which is exactly why GroundFX.SNOW_TINT stops short of 1,
      // and exactly what rounding up to the last rung had been quietly
      // undoing. The tiles read through the snow at every depth now.
      float lay = floor(clamp(cover, 0.0, 1.0) * 3.0 + 0.5) / 3.0 * 0.86;

      if (lay > 0.0) {
        // ------- LAYER 2: snow standing in the world's own light
        //
        // This is what separates snow from white paint, and it was the whole
        // of the old look's problem: snowColor went on as a flat constant
        // AFTER the shading, so a covered roof was the same colour at noon, in
        // a building's shadow and at midnight. Nothing else in the frame
        // behaves that way, and the eye reads a surface that ignores the light
        // as a surface that has been painted rather than covered. Through the
        // hour's light it goes blue where only the sky reaches it, warm under
        // a low sun, dark after dusk -- and a shadow thrown across a white
        // field is finally visible, because there is something for it to fall
        // on.
        vec3 snow = snowColor * light;

        // ------- LAYER 3: the drift has FORM
        //
        // A crest catches more of the sky and a hollow sits back from it. Two
        // hard steps rather than a gradient, because this is relief and not a
        // sheen -- and it is what stops a fully covered roof reading as one
        // flat tone even when the cover really is total.
        snow *= 0.88 + 0.10 * step(0.45, drift) + 0.14 * step(0.78, drift);

        // ------- LAYER 4: and where the sun lands on a crest, it GLITTERS
        //
        // A few per cent of the covered pixels, gated on the sun actually
        // reaching this fragment -- which is what makes it dynamic with no
        // clock to drive it: walk a shadow across a snowed roof and the
        // glitter goes out under it and comes back on the far side, and the
        // whole field lights up and dies as the day turns. Up-faces only, and
        // only once the fall is deep enough to have a surface of its own: a
        // dusting does not sparkle.
        //
        // Brighter than the snow AROUND it rather than a fixed white, and
        // that distinction is the whole of whether this works after dark. The
        // sun rig hangs the moon on the same lamp, so `lit` is high at
        // midnight wherever the moon reaches -- and a constant white here
        // would have put noon-bright specks across a field that is otherwise
        // deep blue. Half again the local snow keeps a highlight proportional
        // to whatever is lighting it, and clamps out at the top end by day,
        // which is what a highlight does anyway.
        // A capped grass tip is an up-surface for this purpose too -- it is
        // the same snow catching the same sun, and leaving it out would put
        // a glittering field behind a dull white meadow.
        float spark = step(0.93, grain) * step(0.62, drift)
                      * step(0.55, lit) * max(vUp, step(0.5, vGrassCap))
                      * step(0.5, depth);
        snow = mix(snow, snowColor * light * 1.5, spark);

        rgb = mix(rgb, snow, lay);
      }
    }
    // ------- AERIAL PERSPECTIVE: the far ground goes to haze
    //
    // Last of the shading, so everything above -- the hour's light, the
    // shadow, the water's own paint, the snow -- has already happened and
    // the haze covers all of it, exactly as air does. (Fog folded in
    // earlier would have been re-lit by whatever came after and gone dark
    // in the shade of a building, which is the one thing distance haze
    // never does.)
    //
    // SQUARED, and that is the shape of the whole effect rather than a
    // taste. A physical haze is exponential -- it climbs fastest right in
    // front of you -- and that is the wrong curve here, because the near
    // ground is where the game is played and it has to stay legible. The
    // square is nearly nothing across the playable screen and then piles
    // up over the last half of the range, so the cost of the cue is paid
    // entirely by ground that exists to be looked at.
    if (fog.z > 0.0) {
      float fd = length(vWorld - fogEye);
      float ft = clamp((fd - fog.x) * fog.y, 0.0, 1.0);
      ft *= ft;
      // Hard rungs, dithered one rung wide with the same per-world-pixel
      // grain the snow uses: anchored in world space, so the boundary
      // between two rungs is a stipple that sits still while the camera
      // pans rather than a band sliding over the ground.
      float fg = voxelHash(floor(vWorld));
      ft = clamp(ft + (fg - 0.5) / fog.w, 0.0, 1.0);
      ft = floor(ft * fog.w + 0.5) / fog.w;
      rgb = mix(rgb, fogColor, ft * fog.z);
    }
    // The hidden player is a SHAPE, not a dimmed picture of itself. Tinting
    // through `color` could only multiply the sprite's own pixels, which
    // darkens each one by its own amount and keeps the character's internal
    // detail; replacing the colour outright is what makes it read as one
    // solid silhouette. Last in the chain, so neither the sun nor a voxel
    // seam can mottle it.
    rgb = mix(rgb, ghostColor, ghost);
    return vec4(rgb, 1.0) * color;
  }
#endif
]]

-- Compilations of SHADER, keyed by the defines they were built with: the
-- voxel wireframe, and the one-tap sun. The wireframe needs shader
-- derivatives (fwidth), the one piece of this a driver can refuse, so it
-- is a separate build rather than a branch -- a refusal costs the grid and
-- nothing else. The sun tap count is a define for a different reason: a
-- uniform branch would still cost the four fetches on any driver that
-- schedules both sides, which is most of them.
-- Each entry is nil = untried, false = unavailable.
local shaders = {}
local activeShader = nil      -- the variant this pass bound

-- Scene canvases, one per NAMED SLOT. There are exactly two callers and
-- they want different sizes -- the free-roam pass renders at the window's
-- pixel dimensions, the overworld battle at the GB's 160x144 -- and a
-- single cached canvas made every battle entry and exit reallocate one.
-- A slot reallocates only when its OWN size changes, which is a window
-- resize, so the pair is stable for a session.
local slots = {}
local canvas, canvasW, canvasH = nil, 0, 0   -- the slot this pass bound
local active = false

-- ------- rendering under the panel's resolution
--
-- The engine composites a pipeline's canvas with draw(canvas, 0, 0, 0,
-- 1/dpiX, 1/dpiY), which only covers the window when the canvas is at the
-- panel's PIXEL resolution -- so what a caller asks for is not negotiable,
-- and handing back a smaller one would land the diorama in the corner at a
-- fraction of the screen (the bug main.lua's sceneSize exists to have
-- fixed).
--
-- So the reduction happens INSIDE the pass and is undone on the way out:
-- the 3D scene draws into a canvas `RES` times smaller on each axis, and
-- endScene scales that back up into a full-size one that the rest of the
-- frame -- the FX overlay, the tilt-shift pass, the engine's own composite
-- -- sees exactly as it always did. Nothing downstream learns about this,
-- which is the point: project() keeps reporting full-size coordinates and
-- the overlay keeps drawing at ctx.scale.
--
-- Nearest on the way up, deliberately. The world under it is pixel art at
-- a fixed grid and the mode's whole argument is that the grid stays crisp;
-- a bilinear stretch would turn a half-resolution diorama into a smeared
-- one, where nearest turns it into a chunkier one. Chunkier is the right
-- failure for this art.
--
-- At RES FULL the two sizes are equal, no present slot is ever allocated,
-- and the extra blit does not happen at all -- so the desktop path is the
-- one it always was rather than the same one plus a copy.
local renderW, renderH = 0, 0
local presentName = nil

-- ------- the depth buffer, kept where something can read it
--
-- The pass has always attached a depth buffer, because occlusion in this
-- mode is a depth test rather than a y-sort. What it has never done is keep
-- one anything could SAMPLE: `{ canvas, depth = true }` asks LOVE for an
-- internal attachment, which the GPU may store however it likes and no
-- shader can bind.
--
-- The screen-space pass (lib/RayFX.lua) is entirely a set of questions
-- asked of that buffer, so it needs the readable kind: a real depth canvas,
-- attached as `depthstencil`. Everything else about the pass is unchanged --
-- same test, same write, same clear.
--
-- Three things are guarded here, all the usual way. The FORMAT is tried
-- down a ladder, stencil-bearing first so the clear below can go on asking
-- for a stencil clear exactly as it always has. The ALLOCATION can fail, in
-- which case the pass falls back to the internal buffer and RayFX quietly
-- finds nothing to read. And the whole thing is skipped when nothing wants
-- it: with RTX at OFF this allocates nothing and the frame is the one it
-- always was.
local DEPTH_FORMATS = { "depth24stencil8", "depth24", "depth32f", "depth16" }
local depthOK = nil            -- nil = untried, false = this driver will not
local sceneDepth = nil         -- the buffer this pass bound, if readable
local sceneName = nil          -- and which slot it belongs to

local function depthCanvas(name, w, h)
  if depthOK == false then return nil end
  local key = name .. "#depth"
  local held = slots[key]
  if held and held.w == w and held.h == h then return held.canvas end
  local made = nil
  for _, fmt in ipairs(DEPTH_FORMATS) do
    local ok, c = pcall(love.graphics.newCanvas, w, h,
                        { format = fmt, readable = true })
    if ok and c then made = c; break end
  end
  if not made then
    depthOK = false
    return nil
  end
  depthOK = true
  -- nearest, and it is not a preference: a linearly blended depth is the
  -- average of two distances, which is a distance to nothing. Every march
  -- in RayFX wants the texel as it was stored.
  pcall(made.setFilter, made, "nearest", "nearest")
  pcall(made.setWrap, made, "clamp", "clamp")
  -- and read as a plain number rather than through a hardware compare,
  -- which is the other thing a depth texture can be bound as
  pcall(made.setDepthSampleMode, made)
  if held and held.canvas and held.canvas.release then
    pcall(held.canvas.release, held.canvas)
  end
  slots[key] = { canvas = made, w = w, h = h }
  return made
end

local function slotCanvas(name, w, h)
  local held = slots[name]
  if held and held.w == w and held.h == h then return held.canvas end
  local ok, c = pcall(love.graphics.newCanvas, w, h)
  if not ok then return nil end
  c:setFilter("nearest", "nearest")
  if held and held.canvas and held.canvas.release then
    pcall(held.canvas.release, held.canvas)
  end
  slots[name] = { canvas = c, w = w, h = h }
  return c
end

local IDENTITY = Mat4.identity()

-- ------- the crush array
--
-- `crush` is a vec4[8] in the shader (feet, then the trail behind them),
-- and LOVE sends an array uniform as one call with one value per element.
-- The scratch table is reused rather than built per draw: this runs on
-- every grass and flower draw of every frame, and eight fresh tables a
-- draw is garbage for no reason. The whole array is always sent, zeros
-- included, for the same reason `sway` is: a slot left behind by the last
-- draw is a dent in the grass where nobody is standing.
Voxel3D.CRUSH_SLOTS = 8
local crushScratch = {}
for i = 1, 8 do crushScratch[i] = { 0, 0, 0, 0 } end

local function sendCrush(sh, c)
  local n = 0
  if c and c.n then
    n = c.n
    -- The loop is per VERTEX, so a slot nobody is standing in is still
    -- paid for by the whole meadow. The rung decides how many the device
    -- can carry (Quality.crushSlots); the extras are simply not sent, and
    -- because Grass3D emits live feet before trail crumbs, what gets cut
    -- is always the far end of the trail rather than the foot in front of
    -- the player.
    local cap = 8
    local okq, q = pcall(Quality.crushSlots)
    if okq and tonumber(q) then cap = math.floor(q) end
    if cap < 0 then cap = 0 elseif cap > 8 then cap = 8 end
    if n > cap then n = cap end
    if n < 0 then n = 0 end
  end
  for i = 1, 8 do
    local s = crushScratch[i]
    local p = (i <= n) and c.p and c.p[i] or nil
    if p then
      s[1], s[2], s[3], s[4] = p[1] or 0, p[2] or 0, p[3] or 0, p[4] or 0
    else
      s[1], s[2], s[3], s[4] = 0, 0, 0, 0
    end
  end
  -- An array uniform is one send with one value per element, and it either
  -- takes the whole array or none of it. Recorded rather than swallowed:
  -- a driver that refused this would leave the meadow with no crush and no
  -- trail at all, and every count on the CPU side would still be perfect
  -- -- exactly the silent-visual-failure shape a probe cannot otherwise
  -- see. `Voxel3D.crushSendOk` is what a probe asks.
  local ok = pcall(sh.send, sh, "crush",
                   crushScratch[1], crushScratch[2],
                   crushScratch[3], crushScratch[4],
                   crushScratch[5], crushScratch[6],
                   crushScratch[7], crushScratch[8])
  Voxel3D.crushSendOk = ok
  return n
end

-- Whether the driver admits to supporting derivatives. Only a hint --
-- the compile below is the real test -- but it saves building a shader
-- that was never going to work, and it is how LOVE reports the ES2
-- extension the grid rides on.
local function derivativesOK()
  if not (love.graphics and love.graphics.getSupported) then return false end
  local ok, caps = pcall(love.graphics.getSupported)
  return ok and caps and caps.shaderderivatives == true
end

-- The scene shader. `grid` asks for the wireframe variant, and nil comes
-- back when that one will not build -- callers then fall back to the plain
-- one rather than losing the whole 3D pass.
function Voxel3D.shader(grid)
  grid = grid and true or false
  local oneTap = not Quality.softShadows()
  local soft = Quality.pcss()
  -- The cel rung is a compile-time branch like the shadow ladder above it,
  -- not a uniform: an `if` around the quantisation would be paid by every
  -- fragment on the OFF rung too, which is the rung most people are on.
  local cel = Anime.cel()
  local key = (grid and "g" or "-")
              .. (oneTap and "1" or (soft and "p" or "4"))
              .. (cel and "c" or "-")
  if shaders[key] == nil then
    if grid and not derivativesOK() then
      shaders[key] = false
    else
      local src = (grid and "#define VOXEL_GRID 1\n" or "")
                  .. (oneTap and "#define SUN_ONE_TAP 1\n" or "")
                  .. ((soft and not oneTap) and "#define SUN_SOFT 1\n" or "")
                  .. (cel and "#define ANIME_CEL 1\n" or "")
                  .. SHADER
      local ok, sh = pcall(love.graphics.newShader, src)
      shaders[key] = ok and sh or false
      -- A variant that will not build falls back silently, which is the
      -- contract -- but silently is also how a typo in a define-gated branch
      -- stays hidden for a release. The driver's own log is the only thing
      -- that ever says why, so it is kept where a probe can read it.
      if not ok then Voxel3D.shaderError = tostring(sh) end
    end
  end
  return shaders[key] or nil
end

-- Whether the 3D path can run at all. False on a headless test run (no
-- love.graphics), without shader support, or where a depth canvas cannot be
-- created -- every caller treats that as "stay on the 2D path".
function Voxel3D.available()
  if not (love.graphics and love.graphics.newCanvas
          and love.graphics.setDepthMode) then
    return false
  end
  return Voxel3D.shader() ~= nil
end

-- Build a mesh in the shared format. `verts` is the LOVE vertex list and
-- `map` the triangle index list. Returns nil when meshes are unavailable,
-- which the callers treat the same way they treat a missing model.
function Voxel3D.newMesh(verts, map)
  if #verts == 0 then return nil end
  local ok, mesh = pcall(love.graphics.newMesh, Voxel3D.FORMAT, verts,
                         "triangles", "static")
  if not ok then return nil end
  if map and #map > 0 then pcall(mesh.setVertexMap, mesh, map) end
  return mesh
end

-- The quad corner offsets and UV corners for one face direction, in the
-- order the vertex map below stitches into two triangles. Corners are unit
-- offsets from the voxel's (x, y, z) minimum corner.
Voxel3D.FACE_CORNERS = {
  [1] = { { 1, 0, 0 }, { 1, 0, 1 }, { 1, 1, 1 }, { 1, 1, 0 } },  -- +X
  [2] = { { 0, 0, 1 }, { 0, 0, 0 }, { 0, 1, 0 }, { 0, 1, 1 } },  -- -X
  [3] = { { 0, 1, 0 }, { 1, 1, 0 }, { 1, 1, 1 }, { 0, 1, 1 } },  -- +Y
  [4] = { { 0, 0, 1 }, { 1, 0, 1 }, { 1, 0, 0 }, { 0, 0, 0 } },  -- -Y
  [5] = { { 0, 0, 1 }, { 1, 0, 1 }, { 1, 1, 1 }, { 0, 1, 1 } },  -- +Z
  [6] = { { 1, 0, 0 }, { 0, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 } },  -- -Z
}

-- Append the six indices of quad `n` (0-based) to a triangle index list.
function Voxel3D.pushQuad(map, n)
  local b = n * 4
  map[#map + 1] = b + 1
  map[#map + 1] = b + 2
  map[#map + 1] = b + 3
  map[#map + 1] = b + 1
  map[#map + 1] = b + 3
  map[#map + 1] = b + 4
end

-- ---------------------------------------------------------------- camera --

-- An explicit camera, replacing the orbit below for as long as it is set:
-- { eye = {x,y,z}, focus = {x,y,z}, fov = radians, curve = k or nil }.
--
-- The orbit is the free-roam camera and it is described entirely by ONE
-- number, the pitch, because that is all a camera following the player over
-- their own map ever needs. A staged shot -- the overworld battle's
-- over-the-shoulder rig (see BattleCam) -- is a placed camera: it has a yaw,
-- it does not sit above its focus, and its framing comes from the arena
-- rather than from the view size. Rather than widen the orbit into
-- something that could express both and be the wrong shape for each, a
-- caller with a camera of its own simply hands it over.
--
-- Everything downstream is unchanged by this: the shader uniforms, project()
-- and the overlay all read Voxel3D.vp / Voxel3D.eye, which are set the same
-- way either way.
Voxel3D.camera = nil

-- View and projection for a `vw` x `vh` world-pixel view centred on
-- (cx, cy) in world pixels. Returns the combined matrix.
function Voxel3D.viewProjection(cx, cy, vw, vh)
  local cam = Voxel3D.camera
  if cam then
    local eye, focus = cam.eye, cam.focus
    Voxel3D.eye = eye
    -- kept beside the eye for horizonY: where the sky's pale end goes is a
    -- question about which way this camera looks, and only these two answer it
    Voxel3D.focus = focus
    local dx = eye[1] - focus[1]
    local dy = eye[2] - focus[2]
    local dz = eye[3] - focus[3]
    local dist = math.max(1, math.sqrt(dx * dx + dy * dy + dz * dz))
    local proj = Mat4.perspective(cam.fov, vw / vh,
                                  math.max(1, dist * 0.05), dist * 4 + 4096)
    -- the same clip-space Y flip the orbit needs, for the same reason: we
    -- bypass LOVE's transform_projection and canvas coordinates run Y down
    proj = Mat4.mul(Mat4.scale(1, -1, 1), proj)
    -- world up, so the horizon stays level -- a placed camera that rolled
    -- with its own pitch would tip the whole arena
    return Mat4.mul(proj, Mat4.lookAt(eye, focus, { 0, 1, 0 }))
  end

  local a = Voxel.angle
  local focal = Voxel.FOCAL
  local dist = focal * vh
  -- the FOV that makes a straight-down camera at `dist` frame exactly `vh`
  -- world pixels, which is the framing the flat view already has
  local fov = 2 * math.atan(1 / (2 * focal))

  local focus = { cx, 0, cy }
  local eye = { cx, dist * math.cos(a), cy + dist * math.sin(a) }
  -- exposed for camera-facing billboards (VoxelScene yaws sprites at it)
  Voxel3D.eye = eye
  Voxel3D.focus = focus
  -- perpendicular to the view direction in the YZ plane: north is screen-up
  -- when looking straight down, +Y is screen-up when looking level. Never
  -- parallel to the view direction, so there is no degenerate a = 0 case.
  local up = { 0, math.sin(a), -math.cos(a) }

  local proj = Mat4.perspective(fov, vw / vh,
                                math.max(1, dist * 0.05), dist * 4 + 4096)
  -- Flip clip-space Y. Mat4.perspective emits textbook GL clip space with
  -- +Y up, but we bypass LOVE's own transform_projection, and LOVE's canvas
  -- coordinates run Y DOWN -- so without this the entire scene composites
  -- vertically mirrored: north at the bottom and buildings extruding
  -- downward. Winding flips with it, which is free here because the pass
  -- draws with culling off.
  proj = Mat4.mul(Mat4.scale(1, -1, 1), proj)
  return Mat4.mul(proj, Mat4.lookAt(eye, focus, up))
end

-- ------- the horizon
--
-- Where the ground plane's vanishing line lands, in canvas pixels down from the
-- top edge, or nil when this camera has no horizon to find.
--
-- Not a fraction picked by eye. A direction ALONG the ground is a point at
-- infinity, and putting one through the same matrix the geometry is drawn with
-- gives the line every ground plane in the scene converges on -- so the sky's
-- pale end meets the horizon at any pitch, fov, window shape or zoom, and rides
-- the camera tween instead of having to be retuned against it.
--
-- The world CURVE is not in it, and cannot be: it bends distant ground down in
-- the vertex shader, so the ground's apparent edge sits BELOW this line by
-- however much the bend took. What shows in between is the haze the sky's fill
-- already is, which is what a curved-away horizon should look like.
--
-- nil in two cases, both meaning "no horizon in this frame": a camera looking
-- straight down, whose forward direction has no horizontal part to send to
-- infinity, and one whose vanishing line is behind it.
function Voxel3D.horizonY(h)
  local m, eye, focus = Voxel3D.vp, Voxel3D.eye, Voxel3D.focus
  if not (m and eye and focus and h and h > 0) then return nil end
  local dx = focus[1] - eye[1]
  local dz = focus[3] - eye[3]
  local len = math.sqrt(dx * dx + dz * dz)
  if len < 1e-6 then return nil end
  dx, dz = dx / len, dz / len
  -- a DIRECTION, so its w is zero and the matrix's translation column drops
  -- out; the clip-space Y flip is already baked into m, so this comes out in
  -- canvas coordinates rather than needing one
  local y = m[5] * dx + m[7] * dz
  local w = m[13] * dx + m[15] * dz
  if w <= 1e-6 then return nil end
  return (y / w * 0.5 + 0.5) * h
end

-- ------- the hour's light
--
-- What the scene shader multiplies every surface by (see dayTint in the
-- shader). Set per pass by whoever knows what map is being drawn --
-- VoxelScene for free-roam, BattleScene for the arena -- because "is this
-- outdoors" is the map's question, not this pass's. Neutral until somebody
-- answers it, so a caller that never does draws exactly what it always drew.
Voxel3D.tint = { 1, 1, 1 }

-- The window-glass pass, set the same way and for the same reason: the
-- MASK belongs to the map's tileset (GlassMask.texture) and how lit the
-- panes are belongs to the hour and to being outdoors at all
-- (DayNight.windowLight). nil / 0 -- the defaults -- draw no glass effect.
Voxel3D.glassMask = nil
Voxel3D.glassNight = 0

-- What the lamps behind that glass burn, in 0..1 -- pushed in from outside
-- exactly like glassNight, and for the same reason: the hour is the
-- caller's to know (DayNight.lampColor). The default is the constant this
-- used to be hardcoded to, so a caller that never sets it draws precisely
-- what it drew before.
Voxel3D.lampColor = { 1.0, 0.84, 0.5 }

-- ------- the street lamps' own pools of light
--
-- lampColor above is what a lamp burns; these three are what its light DOES
-- to the street it stands on, and they are separate because a pane of window
-- glass and a pool on the paving are lit by the same flame to different ends.
--
-- The core is the flame's centre, not its colour: every real light source
-- desaturates toward white where it is brightest, and a pool that stays one
-- flat amber all the way to the middle is the tell that says "decal". The
-- shader ramps lampColor -> lampCore with nearness (see localLamp).
Voxel3D.LAMP_CORE = { 1.0, 0.95, 0.82 }
Voxel3D.lampCore = nil               -- override; nil uses the constant

-- Where the flame hangs, in world pixels above the post's feet. The authored
-- bake measures its own lantern and pushes the real number in through
-- Voxel3D.lampHeight; this default matches the box models' lantern.
Voxel3D.LAMP_HEIGHT = 19.0
Voxel3D.lampHeight = nil

-- How much of the pool actually lands. Held well below 1 on purpose: the
-- hour's own tint is still the scene's light, and a lamp that overpowers it
-- does not make a lit street, it makes a badly tinted afternoon.
Voxel3D.LAMP_GLOW = 0.85

-- The gas clock, advanced by whoever runs the frame (VoxelScene). Left at 0
-- the flicker term is constant and folds out of the shader entirely.
Voxel3D.lampFlicker = 0

-- the glint, fed by the camera's TRAVEL rather than by a clock (see
-- VoxelScene.glintStep): the phase is radians already wrapped to 2pi, and
-- the strength is 0 whenever the view has been still for a beat
Voxel3D.glassPhase = 0
Voxel3D.glassGlint = 0

-- The sun or moon disc's place on this camera's canvas, or nil when the
-- body is set, on the southern half of the sky, or behind the camera.
--
-- The direction comes from DayNight (true bearing, squashed elevation) and
-- goes through the SAME matrix the geometry is drawn with, as a point at
-- infinity -- exactly how horizonY finds the vanishing line. So the disc's
-- azimuth is honest: it stands over the point on the horizon its shadows
-- point away from, at every pitch, fov, window shape and zoom.
--
-- Must run after beginScene has set Voxel3D.vp for this frame's camera.
function Voxel3D.skyBody(w, h)
  local m = Voxel3D.vp
  local b = m and DayNight.body()
  if not b then return nil end
  local x = m[1] * b.dx + m[2] * b.dy + m[3] * b.dz
  local y = m[5] * b.dx + m[6] * b.dy + m[7] * b.dz
  local ww = m[13] * b.dx + m[14] * b.dy + m[15] * b.dz
  if ww <= 1e-6 then return nil end
  local amt, color = DayNight.glow()
  return {
    x = (x / ww * 0.5 + 0.5) * w,
    y = (y / ww * 0.5 + 0.5) * h,
    moon = b.moon,
    glowAmt = amt,
    glowColor = color,
  }
end

-- ----------------------------------------------------------------- scene --

-- Begin the 3D pass into a `w` x `h` pixel canvas centred on world
-- (cx, cy), covering `vw` x `vh` world pixels. Returns false when the pass
-- could not start, in which case the caller must not call endScene.
-- `sky` is an optional {r, g, b, a} in 0..1 to clear the void to, for the
-- pitch where the horizon is in frame (VoxelScene.skyFor). nil leaves the
-- void transparent, which is what every rung below it wants.
-- `slot` names which cached canvas to render into (see `slots` above);
-- omitted is the free-roam world pass.
function Voxel3D.beginScene(w, h, cx, cy, vw, vh, sky, slot)
  -- the wireframe variant when the player has it on AND it built; either
  -- answer falls through to the plain scene rather than to no scene
  local grid = VoxelGrid.enabled()
  local sh = grid and Voxel3D.shader(true) or nil
  if not sh then
    grid, sh = false, Voxel3D.shader()
  end
  if not sh then return false end
  local name = slot or "world"
  -- the size the scene is RASTERISED at, against the size the caller (and
  -- the engine's composite behind it) is owed. See the slot block above.
  local div = Quality.scale()
  local rw = math.max(1, math.floor(w / div))
  local rh = math.max(1, math.floor(h / div))
  local c = slotCanvas(name, rw, rh)
  if not c then return false end
  canvas = c
  renderW, renderH = rw, rh
  -- Full size, not rw/rh: this pair is read by project(), which anchors the
  -- overworld's 2D FX closures, and those draw into the canvas endScene
  -- hands back -- the full-size one.
  canvasW, canvasH = w, h
  presentName = (rw ~= w or rh ~= h) and (name .. "#present") or nil
  sceneName = name
  -- kept for the screen-space pass, which needs to know what a reflected
  -- ray that left the frame was looking at. Captured HERE rather than read
  -- back later because `sky` is shadowed further down by the light split.
  Voxel3D.skyFill = sky
  -- a depth buffer is what makes occlusion real: walk behind a building and
  -- the building wins, with no y-sorting anywhere. Readable when something
  -- downstream is going to ask it questions (see depthCanvas above), and
  -- the plain internal one otherwise -- including whenever the readable
  -- kind could not be bound, which is a driver fact rather than a frame's.
  local depth = RayFX.wanted() and depthCanvas(name, rw, rh) or nil
  local ok = false
  if depth then
    ok = pcall(love.graphics.setCanvas, { canvas, depthstencil = depth })
    if not ok then
      depthOK = false
      depth = nil
    end
  end
  if not ok then
    ok = pcall(love.graphics.setCanvas, { canvas, depth = true })
  end
  if not ok then
    pcall(love.graphics.setCanvas)
    return false
  end
  sceneDepth = depth
  -- Ahead of the clear, because the sky's bands are placed off the ground
  -- plane's vanishing line and that is a property of this matrix.
  Voxel3D.vp = Voxel3D.viewProjection(cx, cy, vw, vh)
  if sky then
    love.graphics.clear(sky[1], sky[2], sky[3], sky[4] or 1, true, true)
    -- The sky goes down here, in the one window in this function where a
    -- rectangle is just a rectangle: the depth mode and the scene shader are
    -- both set below. Sky.paint puts them aside anyway -- beginScene is not the
    -- only thing that has ever left a shader bound.
    --
    -- w / vw is this frame's pixels per WORLD pixel, which is the size a diorama
    -- pixel is on screen: the sky's dither grid is cut to that, so its squares
    -- are the same size as the world's own and follow every resize and zoom.
    -- The banded sky also hangs the hour's sun or moon (skyBody projects it
    -- through this very camera); a flat sky has no bands and hangs nothing.
    -- rw/rh, not w/h: the sky is painted INTO the scene canvas, so its
    -- horizon row, its dither cell and the sun disc's place on it are all
    -- questions about that canvas rather than about the panel. Passing the
    -- panel's size here would put the horizon off the bottom of a
    -- half-resolution frame and size the dither grid to squares the canvas
    -- cannot hold.
    -- cx/cy ride along so the cloud deck can park itself over the MAP rather
    -- than over the monitor: without them every sample the raymarch takes is
    -- a function of the pixel alone, and the sky slides with the camera.
    Sky.paint(rw, rh, sky, Voxel3D.horizonY(rh), rw / math.max(1, vw or rw),
              sky.bands and Voxel3D.skyBody(rw, rh) or nil, cx, cy)
  else
    love.graphics.clear(0, 0, 0, 0, true, true)
  end
  love.graphics.setDepthMode("lequal", true)
  -- models mirror on X for right-facing and alternate walk steps, which
  -- flips winding; hidden faces are already culled at build time, so there
  -- is nothing to gain from backface culling and a real bug to avoid
  love.graphics.setMeshCullMode("none")
  love.graphics.setShader(sh)
  love.graphics.setColor(1, 1, 1, 1)
  pcall(sh.send, sh, "vp", "row", Voxel3D.vp)
  pcall(sh.send, sh, "eye", Voxel3D.eye)
  -- the sun's frame, filled by ShadowMap just before this pass opened.
  -- Sent unconditionally: the sampler is declared either way, and leaving
  -- one unbound is a driver-dependent crash rather than a fallback.
  local map = ShadowMap.active()
  pcall(sh.send, sh, "sunVP", "row", map and ShadowMap.uvVP or IDENTITY)
  local tex = ShadowMap.texture()
  if tex then pcall(sh.send, sh, "sunMap", tex) end
  pcall(sh.send, sh, "sunDark", map and Voxel3D.SHADOW_ALPHA or 0)
  pcall(sh.send, sh, "sunBias", ShadowMap.bias)
  local texel = 1 / ShadowMap.res
  pcall(sh.send, sh, "sunTexel", { texel, texel })
  -- only the SOFT variant declares this one, so on every other rung the
  -- send simply does not take -- which is right: a shader with one fixed
  -- edge width has nothing to size
  pcall(sh.send, sh, "sunSoft", ShadowMap.softness())
  if grid then
    pcall(sh.send, sh, "gridDark", VoxelGrid.DARK)
    pcall(sh.send, sh, "gridWidth", VoxelGrid.WIDTH)
  end
  -- ordinary shading until the silhouette pass asks for otherwise. Sent
  -- every frame rather than once, because a scene that opened mid-ghost --
  -- a driver hiccup between beginGhost and endGhost -- would otherwise
  -- start out flattening everything it drew.
  pcall(sh.send, sh, "ghost", 0)
  pcall(sh.send, sh, "ghostColor", Voxel3D.GHOST_COLOR)
  -- The hour's light, split into the sky's fill and the sun's own share.
  -- `map` above already says whether there is a shadow map to gate the
  -- directional term on -- with none, the whole tint goes into the fill
  -- and the split collapses to the multiply it used to be.
  local sky, sun = Light.split(Voxel3D.tint or { 1, 1, 1 },
                               map and Voxel3D.SHADOW_ALPHA or 0,
                               Voxel3D.skyAmount or 0)
  pcall(sh.send, sh, "skyTint", sky)
  pcall(sh.send, sh, "sunTint", sun)
  -- The cel rung's numbers. Sent unconditionally and through pcall like
  -- everything else on this page: on a shader built without ANIME_CEL the
  -- uniforms do not exist, the send fails, and the pcall is what makes that
  -- the intended outcome rather than a lost frame.
  pcall(sh.send, sh, "animeBands", Anime.BANDS)
  pcall(sh.send, sh, "animeCell", Anime.CELL)
  pcall(sh.send, sh, "animeDither", Anime.DITHER)
  -- Local night lights. Every uniform is sent every scene so a day frame (or
  -- a map change) cannot retain a lamp from the previous city.
  local lamps = Voxel3D.lampLights or {}
  for i = 1, 8 do
    local lamp = lamps[i]
    pcall(sh.send, sh, "lamp" .. (i - 1), {
      lamp and lamp.x or 0,
      lamp and lamp.z or 0,
      lamp and lamp.radius or 0,
      lamp and lamp.power or 0,
    })
  end
  pcall(sh.send, sh, "lampGlow", #lamps > 0 and Voxel3D.LAMP_GLOW or 0)
  pcall(sh.send, sh, "lampHeight", Voxel3D.lampHeight or Voxel3D.LAMP_HEIGHT)
  pcall(sh.send, sh, "lampCore", Voxel3D.lampCore or Voxel3D.LAMP_CORE)
  -- Zero rather than the clock when the flicker is off, so the uniform is a
  -- constant and the sin() folds away instead of costing a frame's worth of
  -- wobble nobody asked for.
  pcall(sh.send, sh, "lampFlicker", Voxel3D.lampFlicker or 0)
  -- and the water: the swell, its two wave trains, and the slope window a
  -- crest has to reach to catch the sun. The window is measured FROM the
  -- flat surface's own alignment with the light (-ray.y is what a level
  -- pond scores), so it stays a window on the crests at any sun angle
  -- rather than drifting off them as the hour moves.
  local ray = ShadowMap.sunDir()
  pcall(sh.send, sh, "sunRay", ray)
  pcall(sh.send, sh, "swell", Water.swell())
  pcall(sh.send, sh, "swellA", Water.WAVE_A)
  pcall(sh.send, sh, "swellB", Water.WAVE_B)
  pcall(sh.send, sh, "swellPhase", Water.phase())
  pcall(sh.send, sh, "iceLift", Water.iceLift())
  pcall(sh.send, sh, "bodyKx", Water.BODY_KX or 0.0039)
  pcall(sh.send, sh, "bodyKz", Water.BODY_KZ or 0.0045)
  pcall(sh.send, sh, "waterSteep", tonumber(Water.STEEP_NOW) or 0)
  pcall(sh.send, sh, "waterCurrent", Water.CURRENT or { 0.94, 0.34 })
  pcall(sh.send, sh, "waterAdvect", tonumber(Water.ADVECT) or 0.045)
  pcall(sh.send, sh, "waterEnergy", tonumber(Water.energy) or 0)
  pcall(sh.send, sh, "waterTherm", tonumber(Water.THERM) or 0.5)
  -- climate paint: freeze / crest foam / snow veil / ice glint / foot crack
  pcall(sh.send, sh, "freeze", tonumber(Water.freeze) or 0)
  pcall(sh.send, sh, "crest", tonumber(Water.CREST) or 0)
  pcall(sh.send, sh, "snowVeil", tonumber(Water.SNOW_VEIL) or 0)
  pcall(sh.send, sh, "iceSparkle", tonumber(Water.ICE_SPARKLE) or 0)
  pcall(sh.send, sh, "stepJitter", tonumber(Water.stepJitter) or 0)
  pcall(sh.send, sh, "waterWet", tonumber(Water.wet) or 0)
  -- the same clock again, under the name the FRAGMENT declares: the foam's
  -- lapping edge rides the tide that moves the waterline it sits on
  pcall(sh.send, sh, "foamPhase", Water.phase())
  -- paint phase snap: fragment cel only (see Water.PAINT_PHASE_STEP). 0 keeps
  -- continuous paint; geometry always uses the unsnapped swellPhase above.
  pcall(sh.send, sh, "paintPhaseStep", tonumber(Water.PAINT_PHASE_STEP) or 0)
  pcall(sh.send, sh, "paintWCell", tonumber(Water.PAINT_WCELL) or 4)
  pcall(sh.send, sh, "paintWCellIce", tonumber(Water.PAINT_WCELL_ICE) or 6)
  -- optional surface art (assets/water/water.png). Sampler always bound.
  do
    local art = nil
    local on = 0
    local okA, a = pcall(Water.art)
    if okA and a then art, on = a, 1 end
    if not art then
      local okB, blank = pcall(Water.artBlank)
      art = (okB and blank) or nil
      on = 0
    end
    if art then pcall(sh.send, sh, "waterArt", art) end
    pcall(sh.send, sh, "waterArtOn", on)
    local scale = 64
    local okS, s = pcall(Water.artScale)
    if okS and tonumber(s) then scale = tonumber(s) end
    pcall(sh.send, sh, "waterArtScale", scale)
  end
  -- sparkleNow, not SPARKLE: the row's strength with the rain taken out of it
  -- (Water.wet), so a shower dulls the pond's glint on the same tick it starts
  pcall(sh.send, sh, "sparkle", Water.sparkleNow())
  local flat = -ray[2]
  pcall(sh.send, sh, "glint", { flat + Water.GLINT_LO, flat + Water.GLINT_HI })
  -- the window glass: the tileset's mask (or the blank -- the sampler is
  -- declared either way, and unbound is a driver-dependent crash), how lit
  -- the panes are, and the movement-fed glint as the caller last set it
  local mask = Voxel3D.glassMask or GlassMask.blank()
  if mask then
    pcall(sh.send, sh, "glassMask", mask)
    local ok, mw, mh = pcall(mask.getDimensions, mask)
    pcall(sh.send, sh, "glassSize", { ok and mw or 1, ok and mh or 1 })
  end
  pcall(sh.send, sh, "glassNight", Voxel3D.glassNight or 0)
  pcall(sh.send, sh, "lampColor", Voxel3D.lampColor or { 1.0, 0.84, 0.5 })
  pcall(sh.send, sh, "glassPhase", Voxel3D.glassPhase or 0)
  pcall(sh.send, sh, "glassGlint", Voxel3D.glassGlint or 0)
  -- on until a sprite pass says otherwise, reset per frame like `ghost`
  pcall(sh.send, sh, "glassOn", 1)
  -- the wind's bearing, wavelength and phase. Constant across the frame --
  -- only `sway` varies per draw, and it is what decides whether a mesh
  -- takes any of this at all
  pcall(sh.send, sh, "windDir", Wind.DIR)
  pcall(sh.send, sh, "windFreq", Wind.FREQ)
  pcall(sh.send, sh, "windPhase", Wind.phase())
  pcall(sh.send, sh, "sway", 0)
  -- the grass load and the tuft height, reset per frame like `sway` is and
  -- for the same reason: the grass pass fills them and nothing else may
  -- inherit them (see Voxel3D.draw)
  Voxel3D.grassH = nil
  Voxel3D.grassLoad = nil
  pcall(sh.send, sh, "grassH", Voxel3D.GRASS_H)
  pcall(sh.send, sh, "grassLoad", { 0, 0, 0 })
  -- Sent once per frame rather than per draw: it is a device capability,
  -- not a property of the mesh in front of the shader.
  do
    local d = 1
    local okd, v = pcall(Quality.grassDetail)
    if okd and tonumber(v) then d = v end
    pcall(sh.send, sh, "grassDetail", d)
  end
  -- crush off until the grass pass fills Voxel3D.crush
  Voxel3D.crush = nil
  pcall(sh.send, sh, "crushN", 0)
  sendCrush(sh, nil)
  -- the curved world bends about the camera's focus, so the horizon keeps
  -- a fixed distance ahead of the player rather than sitting on the map.
  -- A placed camera may decline it outright (Voxel3D.camera.curve = 0).
  local placed = Voxel3D.camera
  Voxel3D.curveK = (placed and placed.curve) or WorldCurve.k(vh)
  Voxel3D.curveX, Voxel3D.curveZ = cx, cy
  Voxel3D.curveCap = WorldCurve.cap(vh)
  pcall(sh.send, sh, "curve", { cx, cy, Voxel3D.curveK, Voxel3D.curveCap })
  -- The haze (see lib/Aerial.lua). Sent every scene, and sent as a zero when
  -- there is nothing to draw, because a uniform left over from the last frame
  -- is a frame of fog on a map that has none -- walk into a house and the sky
  -- descriptor goes nil, which is exactly the case that has to clear.
  --
  -- MEASURED FROM THE EYE, and the near plane is pushed out by the eye's own
  -- distance to the player so that Aerial.NEAR / FAR keep meaning "this far
  -- PAST the player". Both halves of that were learned from the probe rather
  -- than reasoned out. The first cut measured from the FOCUS, on the argument
  -- that it holds still while the camera orbits -- and at the 75-degree rung
  -- it hazed the bottom of the frame HARDER than the tree line, because the
  -- ground at the bottom of the screen is a long way SOUTH of the player even
  -- though it is the nearest thing in the picture. Distance to the camera is
  -- the only measure that agrees with what the frame looks like, and it is
  -- what air actually does. The subtraction is then forced: every visible
  -- point is already at least eye-to-focus away, so a range that did not
  -- start there would spend its whole first view-height underground.
  --
  -- A PLACED camera declines it, the way it may decline the curve. The range
  -- is in view-heights, and a staged shot's framing comes from its arena
  -- rather than from `vh` -- so the numbers that put the haze on the horizon
  -- out here would put it across the middle of a battle.
  local haze = (not placed) and Aerial.color(Voxel3D.skyFill) or nil
  local fogNear, fogInv = nil, nil
  if haze then fogNear, fogInv = Aerial.range(vh) end
  if haze and fogNear then
    local eye, focus = Voxel3D.eye, Voxel3D.focus
    local ex = eye[1] - focus[1]
    local ey = eye[2] - focus[2]
    local ez = eye[3] - focus[3]
    local eyeDist = math.sqrt(ex * ex + ey * ey + ez * ez)
    pcall(sh.send, sh, "fog",
          { eyeDist + fogNear, fogInv, Aerial.amount(), Aerial.RUNGS })
    pcall(sh.send, sh, "fogColor", haze)
    pcall(sh.send, sh, "fogEye", eye)
  else
    pcall(sh.send, sh, "fog", { 0, 0, 0, Aerial.RUNGS })
  end
  -- clip w at the focus point, the reference depth project() reports scale
  -- against (so scale == 1 for anything standing at the view centre)
  local m = Voxel3D.vp
  Voxel3D.focusW = m[13] * cx + m[14] * 0 + m[15] * cy + m[16]
  activeShader = sh
  active = true
  return true
end

-- Depth handling for the character pass. Gen 1 draws sprites over the
-- background unconditionally, so characters render with the depth test
-- forced to pass (still writing depth: the grass mesh drawn after them
-- tests against it to overdraw feet). "test" restores normal occlusion.
function Voxel3D.depth(mode)
  if not active then return end
  pcall(love.graphics.setDepthMode, mode == "always" and "always" or "lequal",
        true)
end

-- ------------------------------------------------ the player's own ghost --

-- The silhouette's colour, and how solid it is.
--
-- ONE flat grey rather than a dimmed copy of the sprite, so the shape reads
-- at a glance instead of competing with whatever is showing through it --
-- and translucent rather than opaque, so it stays a hint of where the
-- player is rather than a hole punched in the building. The wall it is
-- seen through still shows, which is what keeps it reading as "behind
-- that" instead of "in front of it".
Voxel3D.GHOST_COLOR = { 0.26, 0.26, 0.28 }
Voxel3D.GHOST_ALPHA = 0.5

-- Draw a character AGAIN wherever the ordinary draw LOST the depth test.
--
-- Honest occlusion is the point of this mode -- walk behind the Mart and the
-- Mart is genuinely in front of you -- but a player who cannot see their own
-- character has lost track of where they are standing, which the flat game
-- never allowed. So the figure is drawn a second time with the test
-- INVERTED: "greater" passes exactly where "lequal" failed, and LOVE hands
-- the compare straight to glDepthFunc, so the two are true complements.
-- Every texel of the sprite is therefore drawn once and once only -- solid
-- where it is visible, translucent where it is not -- with no seam where
-- they meet and no double-blending anywhere.
--
-- Nothing is drawn at all when nothing is in the way, and no code here ever
-- asks whether the player is occluded: the depth buffer already knows, and
-- the test is the question.
--
-- Depth WRITES are off. This pass is behind the scenery by definition, and
-- writing would file the hidden figure's depth in front of the building
-- hiding it -- the grass pass at the end of the frame reads that buffer.
--
-- The caller redraws through the ordinary character path, so the ghost keeps
-- the same mesh, matrix and camera-ward PULL as the real draw. The pull
-- matching is what keeps the leaning-over-a-near-wall case out of here: pull
-- already won that fight for the solid draw, so this pass finds nothing left
-- to paint and a character merely standing close to a wall does not shimmer
-- a ghost over it.
function Voxel3D.beginGhost()
  if not active then return end
  pcall(love.graphics.setDepthMode, "greater", false)
  love.graphics.setColor(1, 1, 1, Voxel3D.GHOST_ALPHA)
  if activeShader then
    pcall(activeShader.send, activeShader, "ghostColor", Voxel3D.GHOST_COLOR)
    pcall(activeShader.send, activeShader, "ghost", 1)
  end
end

-- Flatten whatever is drawn next to one solid colour, or nil to stop.
--
-- The same `ghost` path the silhouette uses, WITHOUT beginGhost's inverted
-- depth test and half alpha -- this is for something drawn normally that
-- simply wants to come out one colour, which is what a hit flash on a sprite
-- is. beginScene resets the uniform every frame, so a pass that forgets to
-- clear it cannot leak into the next one.
-- `amount` is how far toward that colour, 0..1; omitted is all the way.
-- Anything short of 1 leaves the sprite's own shading showing through, which
-- is the difference between a hit flash and a white cut-out.
function Voxel3D.flatten(color, amount)
  if not (active and activeShader) then return end
  local sh = activeShader
  if color then
    pcall(sh.send, sh, "ghostColor", color)
    pcall(sh.send, sh, "ghost", math.max(0, math.min(1, amount or 1)))
  else
    pcall(sh.send, sh, "ghost", 0)
  end
end

-- Whether what is drawn next carries the voxel wireframe. false for the
-- length of a draw, true to put it back.
--
-- The wireframe reads a mesh's OWN model space and darkens its integer
-- planes (see VoxelGrid), which is only a wireframe because every mesh in
-- this mode is built ONE UNIT PER VOXEL: terrain in world pixels, a
-- character card in the sprite's own pixels. A mesh whose model space does
-- not mean that gets no wireframe out of the same shader -- it gets
-- whichever of its integer planes happen to fall inside it, which is a
-- stray line rather than a seam.
--
-- So this is not a style switch. It is how a mesh that is not on the voxel
-- grid says so, and the alternative -- rescaling such a mesh until its
-- units happen to be voxels -- would change what it IS to satisfy a
-- shading pass.
--
-- Sent rather than branched because the plain scene shader has no such
-- uniform, and the send simply does not take there -- which is right: with
-- no wireframe compiled in there is nothing to suppress.
function Voxel3D.seams(on)
  if not (active and activeShader) then return end
  pcall(activeShader.send, activeShader, "gridDark",
        on and VoxelGrid.DARK or 0)
end

-- Whether what is drawn next may consult the glass mask. false for the
-- length of a sprite-sheet pass, true to put it back.
--
-- Same shape as seams(), for the same reason: the mask means "this ATLAS
-- texel is window glass", so it is only an answer for meshes textured from
-- the tileset atlas. A sprite sheet's coordinates land wherever they land
-- on it, and at night that painted lamplight stripes down whoever was
-- standing in the wrong part of their own sheet.
function Voxel3D.glass(on)
  if not (active and activeShader) then return end
  pcall(activeShader.send, activeShader, "glassOn", on and 1 or 0)
end

function Voxel3D.endGhost()
  if not active then return end
  pcall(love.graphics.setDepthMode, "lequal", true)
  love.graphics.setColor(1, 1, 1, 1)
  -- back to ordinary shading before anything else draws; leaving it set
  -- would flatten the grass pass that follows into one grey sheet
  if activeShader then
    pcall(activeShader.send, activeShader, "ghost", 0)
  end
end

-- -------------------------------------------------------------- shadows --

-- The sun. One direction, shared by everything that needs to know where
-- the light comes from: the shadow map, the flat fallback below, and the
-- baked contact shading in ChunkMesher. Both shears are negative, which
-- hangs it in the SOUTHEAST and throws every shadow northwest -- up and to
-- the left on screen.
Voxel3D.SHADOW_KX = ShadowMap.KX   -- west drift per pixel of height
Voxel3D.SHADOW_KZ = ShadowMap.KZ   -- north drift per pixel of height
-- Snow lying on the world's own up-faces: how much, set per PASS by whoever
-- is drawing (VoxelScene, from GroundFX's cover), and what colour. Zero by
-- default so a caller that never heard of it draws exactly what it always
-- did. Slightly blue rather than white: snow under an overcast sky is lit by
-- the sky, and pure white here would be the one thing in the frame not
-- standing in the same light as everything else.
Voxel3D.snowTop = 0
Voxel3D.SNOW_COLOR = { 0.93, 0.95, 0.99 }
-- What a face that does NOT point up still takes. A third: enough that a
-- hedge reads as snowed rather than as green with a lid, little enough that
-- a wall keeps its own art down its flank.
Voxel3D.SNOW_SIDE = 0.34

-- How tall a leaning thing stands, in world pixels, when the caller does
-- not say. Ten is the classic extruded slab plus a little: it is only the
-- normaliser the bend curve runs over, so an over-estimate makes a tuft
-- gentler rather than wrong -- but a 3D bake knows its own height and
-- should hand it over (VoxelScene reads Grass3D.meta().height).
Voxel3D.GRASS_H = 10
-- Set by the grass pass right before its draws (nil = the default above),
-- exactly like `snowTop` and `crush`: one value for a whole pass.
Voxel3D.grassH = nil
-- { rain on the blades, settled snow on them, gust envelope }, each 0..1.
Voxel3D.grassLoad = nil

Voxel3D.SHADOW_EPS = 0.25     -- float above the ground to dodge z-fighting
Voxel3D.SHADOW_ALPHA = 0.40   -- how far into black a shadowed surface goes

-- Whether real shadows are running this frame. False headless and on any
-- driver the sun pass could not start on, which is when VoxelScene falls
-- back to the flat decals below.
function Voxel3D.shadowsActive()
  return ShadowMap.active()
end

-- The upright card a character presents to the sun: its 16x16 sprite quad
-- (corners (0,0,0)..(16,16,0), feet at y = 0) standing on the middle of
-- the cell whose top-left is world (px, py), feet at height `y`.
--
-- This is the caster the shadow pass draws -- deliberately NOT the leaning
-- slab the camera sees. The slab tips back by the camera's pitch to read
-- face-on, which is a trick played on the viewer; letting the sun see it
-- too would shrink every shadow to nothing as the camera flattened toward
-- top-down. The sun sees the figure standing up, at every tilt.
--
-- The z-flatten matters when this is used the other way round, as the
-- lookup transform a lit slab reads its own shadowing with (Voxel3D.draw's
-- `sunModel`): it collapses the slab's side relief onto the card plane, so
-- every vertex asks about the exact surface the sun recorded rather than
-- one a few pixels behind it, and a figure cannot fringe itself. On the
-- caster itself it is a no-op -- that quad is already flat.
function Voxel3D.casterMatrix(px, py, y, mirror)
  local m = Mat4.translate(px + 8, y, py + 8)
  if mirror then m = Mat4.mul(m, Mat4.scale(-1, 1, 1)) end
  return Mat4.mul(Mat4.mul(m, Mat4.translate(-8, 0, 0)),
                  Mat4.scale(1, 1, 0))
end

-- FALLBACK ONLY (no shadow map: headless, or a driver that cannot make the
-- canvas). Character drop shadows as decals -- the sprite frame squashed
-- flat onto its ground plane and drawn translucent black. It can only ever
-- paint the floor, which is the whole reason ShadowMap exists.
--
-- Flattening is measured from the ground plane, so a hop slides the whole
-- shadow along the sun line while it stays glued to the ground -- the
-- classic jump-shadow tell.
function Voxel3D.shadowMatrix(px, py, gh, lift, mirror)
  local card = Voxel3D.casterMatrix(px, py, gh + (lift or 0), mirror)
  -- flatten about the ground plane: y' = 0, x/z shear by height above it
  local squash = { 1, Voxel3D.SHADOW_KX, 0, 0,
                   0, 0,                 0, 0,
                   0, Voxel3D.SHADOW_KZ, 1, 0,
                   0, 0,                 0, 1 }
  local m = Mat4.mul(squash, Mat4.mul(Mat4.translate(0, -gh, 0), card))
  return Mat4.mul(Mat4.translate(0, gh + Voxel3D.SHADOW_EPS, 0), m)
end

-- The decal pass draws between terrain and characters: depth-tested so a
-- building still hides a shadow behind it, but NOT depth-writing -- the
-- grass tufts drawn at the end of the frame must keep beating the ground
-- plane, and one quad per entity has no self-overlap to guard against.
function Voxel3D.beginShadows()
  if not active then return end
  pcall(love.graphics.setDepthMode, "lequal", false)
  love.graphics.setColor(0, 0, 0, Voxel3D.SHADOW_ALPHA)
end

function Voxel3D.endShadows()
  if not active then return end
  pcall(love.graphics.setDepthMode, "lequal", true)
  love.graphics.setColor(1, 1, 1, 1)
end

-- The same footing, for a caller that brings its OWN colour: the puddles
-- and the snow the weather leaves on the ground (lib/GroundFX.lua). Split
-- from the pair above rather than shared with it, because the one thing
-- those two lines exist to do -- set the shadow's flat black -- is the one
-- thing a coloured decal must not inherit; a sky-blue puddle drawn through
-- beginShadows would come out black and read as a hole in the road.
-- `write` asks for depth WRITES as well as the test, and exactly one caller
-- wants them: the puddles. The screen-space pass downstream needs a puddle
-- pixel's own POSITION -- the plane it reflects off is reconstructed out of
-- the depth buffer -- and a decal that does not write is not in that buffer:
-- the pixel still reports the road underneath it, so a puddle drawn this way
-- would reflect off the road's plane rather than its own. (WHICH pixels are
-- puddle is a separate question, and no longer a question about depth at
-- all -- see the alpha tag below.)
--
-- Safe for the same reason the shadow decals could not afford it: everything
-- drawn after a decal that matters -- the characters, the tall grass, the
-- flowers -- is pulled camera-ward by six world pixels or more, and a puddle
-- floats seven tenths of one. The pull wins by an order of magnitude, so the
-- grass still overdraws feet and a walker still stands in front of the water
-- they are standing in.
function Voxel3D.beginDecals(write)
  if not active then return end
  pcall(love.graphics.setDepthMode, "lequal", write and true or false)
end

function Voxel3D.endDecals()
  if not active then return end
  pcall(love.graphics.setDepthMode, "lequal", true)
  love.graphics.setColor(1, 1, 1, 1)
end

-- ------- THE ALPHA TAG: how a decal tells the screen pass what it IS
--
-- The screen pass has one image and one depth buffer to work from, so for as
-- long as this row has existed a surface's CLASS has had to be guessed out of
-- its geometry. For the sea that guess is sound -- it is the only thing in
-- the world standing in a band below zero. For a puddle it never was: the
-- guess was the fraction of its height (0.7, the float below), and a
-- character is a card leaned back by the camera's pitch whose height climbs
-- its own face and crosses point-seven a dozen times. The probe took that
-- apart, and two further guesses at geometry -- flatness, a strict normal --
-- failed with it. The answer is not a third guess. It is to stop guessing.
--
-- The channel it goes in is the scene canvas's own ALPHA, and it is free for
-- two reasons that hold together:
--
--   NOTHING ELSE IS USING IT for geometry. The canvas is rgba8 and its alpha
--   is meaningful -- the void is transparent, which is why the composite in
--   endScene copies rather than blends -- but every drawn pixel in it is at
--   exactly 1.0 and cannot be at anything else.
--
--   AND NOTHING ELSE CAN LAND ON IT BY ACCIDENT, which is the part that
--   makes this a mask rather than a fourth guess. The alpha blend equation
--   is dst.a = src.a + dst.a * (1 - src.a), so a decal painted at 0.90 over
--   ground at 1.0 still resolves to exactly 1.0, and so does one at 0.78,
--   and so does an additive spark. Every ordinary draw SATURATES this
--   channel. A value that is neither 1.0 nor 0.0 can only have been put
--   there deliberately, outside the blend.
--
-- Which is the whole of the pair below: mask the colour write down to the
-- alpha channel alone, set the blend to replace so dst.a IS src.a, and draw
-- the decal a second time. The first draw's composited colour is untouched
-- -- the mask blocks RGB -- and the only thing that changes in the finished
-- frame is the byte RayFX reads.
--
-- 254 of 255 rather than something further from 1.0, and the cost is worth
-- naming: this value survives the pass (RayFX hands src.a back out) and ends
-- up as the pixel's own opacity at the engine's composite, so a tagged pixel
-- is 0.4% see-through. That is under half a step of the 8-bit art it is
-- drawn over. The reader tests for it exactly rather than for "less than
-- one" -- see RayFX.PUDDLE_TAG, which is this same number written down in
-- the file that reads it, the same way PUDDLE and the decal's float height
-- are written down twice.
Voxel3D.PUDDLE_TAG = 254 / 255

local stampBlend, stampAlphaMode = nil, nil

-- Open the stamp. Returns false when the mark would go nowhere, and the
-- caller should then skip the extra draw entirely rather than paint an
-- untagged copy of its layer.
--
-- Gated on the readable depth buffer, which is exactly the frame's answer to
-- "will a screen pass run at all" (see endScene): at RTX OFF nothing is
-- allocated, nobody reads alpha, and the tag is a draw call spent on a byte
-- no one looks at. It is also the honest guard for a driver that refused the
-- depth format -- there, too, RayFX finds nothing to read.
--
-- A caller that sets its own colour per draw (GroundFX does, one setColor
-- per layer) must pass `tag` as that colour's ALPHA. The colour set here is
-- only the default for a caller that does not.
function Voxel3D.beginAlphaStamp(tag)
  if not active then return false end
  if not sceneDepth then return false end
  local g = love.graphics
  -- Not in the shipped LOVE of every host this mod runs on, and a missing
  -- colour mask is not worth a crash: no mask, no tag, no reflection.
  if not (g.setColorMask and g.getColorMask) then return false end
  if not pcall(g.setColorMask, false, false, false, true) then return false end
  stampBlend, stampAlphaMode = g.getBlendMode()
  -- replace, so the channel takes src.a rather than the blend's saturating
  -- sum -- the whole point. premultiplied to match: with RGB masked off
  -- there is nothing for an alphamultiply to multiply, and every other
  -- replace in this codebase is written this way.
  pcall(g.setBlendMode, "replace", "premultiplied")
  -- The test stays, the WRITE goes off. The layer being stamped has already
  -- laid its own depth down, so this second draw meets itself at exactly
  -- equal depth -- lequal passes it, and writing again would be re-writing
  -- the same numbers.
  pcall(g.setDepthMode, "lequal", false)
  g.setColor(0, 0, 0, tag or Voxel3D.PUDDLE_TAG)
  return true
end

function Voxel3D.endAlphaStamp()
  local g = love.graphics
  pcall(g.setColorMask, true, true, true, true)
  pcall(g.setBlendMode, stampBlend or "alpha", stampAlphaMode or "alphamultiply")
  stampBlend, stampAlphaMode = nil, nil
  pcall(g.setDepthMode, "lequal", true)
  g.setColor(1, 1, 1, 1)
end

-- Draw one mesh with `model` (a Mat4) applied. Texture may be nil to keep
-- whatever the mesh already carries. `pull` moves every vertex toward the
-- eye along its own ray (see the shader) -- the artifact-free depth bias
-- the character and grass passes ride in front of the terrain.
--
-- `sunModel` is where the SHADOW PASS put this same geometry, and defaults
-- to `model` because for everything but a character the two are one matrix.
-- A character is drawn leaning and cast upright, so it must hand over the
-- upright transform or it reads its own shadow as falling on itself.
-- `sway` is the wind's reach at the top of whatever this mesh is, in world
-- pixels, and it defaults to ZERO -- sent on every draw rather than only on
-- the ones that want it, so a swaying pass can never leak into the terrain
-- that follows it.
function Voxel3D.draw(mesh, texture, model, pull, sunModel, sway)
  if not (active and mesh) then return end
  -- the variant beginScene actually bound, not whichever one is default:
  -- sending a uniform to the other shader would go nowhere
  local sh = activeShader
  if not sh then return end
  if texture then mesh:setTexture(texture) end
  -- LOVE defaults matrix uniforms to column-major; Mat4 is row-major
  pcall(sh.send, sh, "model", "row", model or IDENTITY)
  pcall(sh.send, sh, "sunModel", "row", sunModel or model or IDENTITY)
  pcall(sh.send, sh, "pull", pull or 0)
  pcall(sh.send, sh, "sway", sway or 0)
  -- How tall the thing that is about to lean stands, and what is lying on
  -- it. Both ride the same field-set-by-the-caller contract `snowTop` and
  -- `crush` do -- one value for a whole pass, and no new parameter on the
  -- dozen call sites that will never set either. Sent unconditionally, so
  -- a pass that leaves them nil cannot inherit the grass pass's load.
  do
    local sw = sway or 0
    if sw > 0 then
      pcall(sh.send, sh, "grassH", Voxel3D.grassH or Voxel3D.GRASS_H)
      local l = Voxel3D.grassLoad
      pcall(sh.send, sh, "grassLoad",
            l and { l[1] or 0, l[2] or 0, l[3] or 0 } or { 0, 0, 0 })
    else
      pcall(sh.send, sh, "grassH", Voxel3D.GRASS_H)
      pcall(sh.send, sh, "grassLoad", { 0, 0, 0 })
    end
  end
  -- Foot-crush only on the grass (and flower) pass: the caller fills
  -- Voxel3D.crush via Grass3D before drawing, and anything else leaves n=0
  -- so terrain never folds under a walker.
  do
    local c = Voxel3D.crush
    local live = (sway and sway > 0 and c and c.n and c.n > 0) and c or nil
    pcall(sh.send, sh, "crushN", sendCrush(sh, live))
  end
  -- the snow lying on this mesh's up-faces, read from the field the caller
  -- set rather than passed as an argument: every existing call site would
  -- have needed a new parameter for a value that is the same for a whole
  -- pass, and `sway` is the cautionary tale for what happens when one of
  -- them forgets (it is sent on every draw for exactly that reason)
  pcall(sh.send, sh, "snowTop", Voxel3D.snowTop or 0)
  pcall(sh.send, sh, "snowColor", Voxel3D.SNOW_COLOR)
  pcall(sh.send, sh, "snowSide", Voxel3D.SNOW_SIDE)
  love.graphics.draw(mesh)
end

-- Draw one terrain GROUP -- a map's chunked mesh (see ChunkMesher) --
-- submitting only the cells that meet `b`, a world XZ box {x0, z0, x1, z1}
-- in the group's own space. nil draws every cell, which is what a caller
-- that cannot work out a box should pass: over-drawing is slow, and
-- under-drawing is a hole in the world.
--
-- Same three uniforms Voxel3D.draw sends, sent ONCE for the whole group.
-- Every cell of a map shares its model, its sun transform and its pull --
-- they are one mesh cut up, not several objects -- and a send per chunk
-- would hand a good part of the chunking's saving straight back.
function Voxel3D.drawGroup(group, texture, model, pull, sunModel, b)
  if not (active and group and group.chunks) then return end
  local sh = activeShader
  if not sh then return end
  pcall(sh.send, sh, "model", "row", model or IDENTITY)
  pcall(sh.send, sh, "sunModel", "row", sunModel or model or IDENTITY)
  pcall(sh.send, sh, "pull", pull or 0)
  -- terrain is planted by definition: buildings do not lean
  pcall(sh.send, sh, "sway", 0)
  local chunks = group.chunks
  for i = 1, #chunks do
    local ch = chunks[i]
    -- `+ ch.ymax` on the north edge: the box is drawn on the GROUND, and a
    -- cell whose ground is past it can still be in frame if something tall
    -- stands on it -- see the note where ymax is measured
    if not b or (ch.x1 >= b[1] and ch.x0 <= b[3]
                 and ch.z1 + ch.ymax >= b[2] and ch.z0 <= b[4]) then
      if texture then ch.mesh:setTexture(texture) end
      love.graphics.draw(ch.mesh)
    end
  end
end

-- Project a world point to canvas pixels: returns (x, y, scale), or nil
-- when the point is behind the camera. `scale` is how much bigger a thing
-- at that depth appears than one at the focus point, so a caller can size
-- with it -- or ignore it and draw unscaled, which is what tilt mode's
-- billboards do.
--
-- This is what lets the overworld's FX closures (the "!" bubble, the heal
-- machine, the Fly bird, the fishing rod) draw in voxel mode completely
-- unchanged: they stay ordinary 2D draws, anchored to wherever their ground
-- point lands under the same camera the 3D pass used.
function Voxel3D.project(wx, wy, wz)
  local m = Voxel3D.vp
  if not m then return nil end
  -- the same drop the vertex shader applies, or every FX anchored to a
  -- ground point floats off its own feet the moment that ground bends
  wy = wy - WorldCurve.drop(Voxel3D.curveK or 0, Voxel3D.curveX or 0,
                            Voxel3D.curveZ or 0, wx, wz, Voxel3D.curveCap)
  local cx = m[1] * wx + m[2] * wy + m[3] * wz + m[4]
  local cy = m[5] * wx + m[6] * wy + m[7] * wz + m[8]
  local cw = m[13] * wx + m[14] * wy + m[15] * wz + m[16]
  if cw <= 1e-6 then return nil end
  -- viewProjection already flipped clip-space Y into LOVE's Y-down canvas
  -- convention, so both axes map the same way here -- no second flip
  local x = (cx / cw * 0.5 + 0.5) * canvasW
  local y = (cy / cw * 0.5 + 0.5) * canvasH
  return x, y, (Voxel3D.focusW or cw) / cw
end

-- Re-bind the scene canvas for ordinary 2D drawing (no depth test), so
-- screen-space overlays can be composited into the same image the 3D pass
-- just filled. Pairs with endScene, which unbinds it.
function Voxel3D.beginOverlay()
  if not canvas then return false end
  love.graphics.setShader()
  love.graphics.setDepthMode()
  local ok = pcall(love.graphics.setCanvas, canvas)
  if not ok then return false end
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

-- Close the overlay begun by beginOverlay.
function Voxel3D.endOverlay()
  love.graphics.setCanvas()
  active, activeShader = false, nil
end

-- End the pass and hand back the rendered canvas, at the size the caller
-- asked beginScene for -- which is the size the engine's composite needs,
-- whatever resolution the scene was actually rasterised at (see the slot
-- block above).
function Voxel3D.endScene()
  if not active then return nil end
  love.graphics.setShader()
  love.graphics.setDepthMode()
  love.graphics.setMeshCullMode("none")
  love.graphics.setCanvas()
  active, activeShader = false, nil
  local small = canvas
  if not small then return small end

  -- ------- fake ray tracing, at the resolution the scene was rasterised at
  --
  -- Here rather than as a worldPresent pipeline, for two reasons that both
  -- come down to what the pass needs to see.
  --
  -- It needs the DEPTH BUFFER, which stops existing the moment this
  -- function hands the colour canvas back -- nothing downstream of here has
  -- ever been given one, and giving one to the pipeline registry would mean
  -- inventing a way to carry it.
  --
  -- And it needs the SMALL image. At RES 1/2 what leaves this function is
  -- an upscale; marching a ray across it is paying four times over to walk
  -- through detail that was never rendered, and the depth buffer it would
  -- be marching against is the small one anyway.
  --
  -- Both callers get it for free by being callers: the battle arena renders
  -- through this same pair into a slot of its own, and the pass follows the
  -- slot. nil back means the rung is OFF or the effect could not run, and
  -- the scene carries on exactly as it is.
  if sceneDepth then
    local lit = RayFX.apply({
      canvas = small,
      depth = sceneDepth,
      vp = Voxel3D.vp,
      eye = Voxel3D.eye,
      slot = sceneName,
      w = renderW,
      h = renderH,
      sky = Voxel3D.skyFill,
      -- the sun's own place on THIS canvas, for the shafts to march at --
      -- the same projection the sky hung its disc with, asked again at
      -- render resolution
      body = Voxel3D.skyBody(renderW, renderH),
      -- the bend this frame was drawn with. The depth buffer records the
      -- BENT world, so the pass has to be told how to take the bend back
      -- off before it asks what class a surface is -- see RayFX.WATER_Y.
      curve = { Voxel3D.curveX or 0, Voxel3D.curveZ or 0,
                Voxel3D.curveK or 0 },
    })
    if lit then small = lit end
  end

  -- whatever came out of that is what the overlay draws into and what a
  -- caller with no present step is handed
  canvas = small
  if not presentName then return small end
  local out = slotCanvas(presentName, canvasW, canvasH)
  -- A present canvas that could not be made is not worth losing the frame
  -- over: hand back the small one and let it composite wrong for a frame
  -- rather than dropping to the flat 2D path on a transient allocation
  -- failure. The next frame retries.
  if not out then return small end
  local prevBlend, prevAlpha = love.graphics.getBlendMode()
  local ok = pcall(function()
    love.graphics.setCanvas(out)
    -- replace, not alpha blend: this is a copy, and the scene's own alpha
    -- is meaningful -- the void is transparent at every rung below the one
    -- that paints a sky, and blending would premultiply it away
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(small, 0, 0, 0,
                       canvasW / renderW, canvasH / renderH)
  end)
  love.graphics.setCanvas()
  love.graphics.setBlendMode(prevBlend or "alpha", prevAlpha)
  if not ok then return small end
  -- the overlay draws into what we just handed back, not into the small one
  canvas = out
  return out
end

function Voxel3D.canvas()
  return canvas
end

-- Drop the GPU objects (window resize, hot reload).
function Voxel3D.invalidate()
  for name, held in pairs(slots) do
    if held.canvas and held.canvas.release then
      pcall(held.canvas.release, held.canvas)
    end
    slots[name] = nil
  end
  canvas, canvasW, canvasH = nil, 0, 0
  renderW, renderH, presentName = 0, 0, nil
  -- the depth buffers went out with the slots above; `depthOK` deliberately
  -- does NOT reset, because whether this driver can make a readable one is
  -- a fact about the driver rather than about the window that just resized
  sceneDepth, sceneName = nil, nil
  ShadowMap.invalidate()
  -- the sky is part of this pass and holds a shader of its own
  Sky.invalidate()
  -- and the glass masks are textures of this context too
  GlassMask.invalidate()
  -- and the screen-space pass keeps a canvas per slot of its own
  RayFX.invalidate()
end

return Voxel3D
