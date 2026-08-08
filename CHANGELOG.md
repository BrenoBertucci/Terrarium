# Changelog

## Versioning

Releases use **semver** plus an optional channel:

```
MAJOR.MINOR.PATCH[-CHANNEL]
```

| Part | Meaning |
| --- | --- |
| `MAJOR` | Breaking / large rework of the diorama contract |
| `MINOR` | New features (still installable over the prior minor) |
| `PATCH` | Fixes and small polish only |
| `CHANNEL` | Build flavour only — today `mobile` (cheap RES/SHADOWS defaults). **Not** a feature name. |

**Do not** encode features in the version string (no `.water`, `.rain`, `.grass`, …). Feature names live in this changelog and in release notes.

Tags and packages:

- Git tag: `v1.19.0-mobile`
- Zip asset: `TERRARIUM-1.19.0-mobile.zip`
- `manifest.json` / catalog `version` field: `1.19.0-mobile`

## 1.19.0-mobile

### Added

- **Rain you can see coming.** A far curtain: the shower standing on the
  horizon as vertical shafts, drawn in the sky pass under the cloud deck and
  over the haze band. It is not a forecast -- nothing in this mod knows the
  future -- it is the same shower that is about to be on top of you, drawn
  where a shower is the only place it is ever visible *as* a shower, from a
  distance. It reads as *coming* because it LEADS the near field: the curtain
  is full at a power where the streaks are still a drop here and there. That
  ordering is the whole effect.
- **God rays after the rain.** Sunlight through a deck that is breaking up,
  for the length of the post-rain spell. They are drawn where the deck is
  THIN, because that is what rays are -- light through a gap -- and the cloud
  raymarch has already computed how thick the deck is at each pixel, so the
  entire effect costs one `atan` and one `sin` on top of work already done.
  Hard rungs and the same checker dither as the bands, never a soft ramp: a
  smooth falloff here would be bloom. A moon throws none.
- **A storm sky.** `DayNight.STORM_SKY` is a second register above the
  stratus, not a replacement for it. The neutral grey was right for an
  ordinary shower and it still is -- what says "raining" is the loss of blue,
  not the loss of light -- but it is wrong for the shower that throws
  lightning, which is *bruised*. The violet only leaves zero above the same
  power threshold that arms the strike, so a drizzle stays exactly the grey
  it was and a sky that has gone purple is by definition a sky that can
  flash. Blended after the stratus, on the same hour weight, so clear ->
  overcast -> storm is one continuous move and not a switch. The world tint
  goes with it.
- **Stars go out one at a time.** Each star now has its own point of
  disappearing, so the field EMPTIES as cloud comes over instead of dimming
  as one sheet -- which is what it did, and a sheet fade reads as a layer
  because it is one. The threshold is mostly the star's own magnitude, so the
  faint ones go first the way they actually do, with a scatter off its twinkle
  phase so the order is not a clean sweep down the tiers. A clear deep night
  is unchanged: at full darkness every star still resolves to full brightness.
- **ANIME row** (OFF / CEL / FULL): cel-banded light, rim light and an ink
  line. No new pass at any rung -- CEL is arithmetic inside the scene shader
  between the light being summed and the material being multiplied by it, so
  it works even with RTX switched off entirely.
- **IMPACT row** (OFF / ON): hand-drawn sprite-sheet effects in the overlay
  pass, beside the butterflies and the rain. The sheets are CC0 packs from
  OpenGameArt, not generated art -- see `assets/vfx/LICENSE.md`.
- **V-HAZE row** (OFF / 1 / 2 / 3), hotkey `h`: aerial perspective. Far ground
  goes paler, flatter and bluer, mixed toward the sky's own palest band rather
  than toward a colour of its own choosing. Equal contrast reads as equal
  distance, which is most of why a small map read small.
- **HORIZON row** (OFF / NEAR / FAR / ALL), hotkey `k`: the rest of Kanto
  standing on the skyline. The probe found the drawn world ending about 145
  pixels short of its own vanishing line with a fifth of the frame empty above
  it, while the connection graph from the same spot already places eight to
  twenty-one further maps spanning some thirty view-heights. None of it was
  missing; all of it was unplaced. `lib/WorldAtlas.lua` answers where each map
  stands relative to the one under your feet, reusing the engine's own BFS
  over `def.connections` rather than walking it again.

### Changed

- **Clouds travel over Kanto instead of over the monitor**, and they change
  shape while they do. The deck was already drifting -- what it was not doing
  was reading the CAMERA (every sample was a function of the pixel alone, so
  the sky slid along as you walked) or changing while it drifted (a rigid
  noise pattern towed past, which the eye reads as a painted backdrop however
  fast you tow it). Parallax is deliberately small: cloud is the farthest
  thing in the frame and must therefore shift LEAST, and that difference *is*
  the distance cue. The shape change comes from giving the erosion noise its
  own drift rate against the wind that carries the mass -- two constants and
  no extra work.
- **`Weather.BUILD` 7s -> 20s.** Seven seconds was fine while the only thing
  it governed was how fast the streaks thickened. It is far too fast for a
  front you are meant to WATCH ARRIVE, and the length of this number is
  literally how long you get to stand there and see grey close in. Still lands
  well inside the sixty-second floor on a wet spell.
- **Grass physics comes in tiers now** (`Quality.grassDetail`), riding the
  same RES rung everything else does. The grass pass is the heaviest vertex
  work in the mod and, unlike every other cost, it does not shrink with RES:
  the canvas gets smaller, the tuft count does not. The cheap rungs keep the
  travelling wave, the planted base and the parting underfoot, and drop
  everything that is texture rather than motion.

### Measured

- The five sky changes were each isolated and measured rather than eyeballed
  (`tests/sky_weather_probe.lua`), since they all landed in one fragment
  shader where a screenshot cannot say which of them moved. Parallax: 59.7% of
  sky pixels change between two cameras at the same instant, against 0.0% with
  the constant zeroed. Shape change: 22.4% with the wind zeroed so drift is
  zero by construction, against 0.0% with the constant zeroed. Curtain: 38.9%
  in the lower sky and 0.0% in the upper. Rays: 30.3% near the disc, 8.2%
  away from it, 0.0% with a moon. Cost, as an off/on/on/off palindrome, is
  +4.6% per sky paint with the curtain and the rays both forced on at once --
  a state the game never reaches, since a curtain means it is raining and rays
  mean it stopped.

## 1.18.0-mobile

### Added

- **WIND / AUTO**, and it is now the default rung. BREEZE and GALE are two
  fixed windows onto the same climate, so keeping a storm feeling like a
  storm meant walking back to the options menu every time the sky changed.
  AUTO spans both windows on one continuous curve — bent low so a clear
  afternoon stays calm, pushed the rest of the way by a front so a downpour
  reaches gale on its own. Stored values for the three old rungs are
  unchanged, so an existing save still reads back as whatever it was set to.
- **Grass reacts to the weather.** Falling rain is weight: it damps the sway
  (a wet meadow moves *less*), bows the blades, and adds a fast tick on each
  tuft's own phase as drops land. Settled snow — read off the accumulated
  cover, not the snowfall — bows the tufts over on their own bearings and
  stiffens what is left, so a meadow stays loaded after the sky clears.
- **Wind VFX**: flat comet-tail streaks of what the air is carrying (dust,
  spray under a shower, blown white under a fall), plus a **gust front** — a
  rank thrown abreast off the same squall envelope the grass is bending to,
  so the gust crosses the frame as a line. Drawn only outdoors, above a wind
  floor, and never under WIND OFF. New `lib/WindFX.lua`.
- **Snow settles ON the grass.** Every other surface takes its snow from
  its face normal, and by that rule a blade is a *side* along its whole
  length — correct about the normal, wrong about the winter, and the reason
  a meadow stood green beside ground that had gone white. Tufts now carry a
  snow **cap**, weighted by how far up the blade you are and how much has
  settled, fed through the same snow path a roof ridge uses (threshold,
  drift, grain, sun glitter). White on top, green underneath.
- **A walk leaves a trail.** A moving foot drops crumbs every ten world
  pixels — weaker, narrower crushes at the places it just left, spaced
  closer than their own reach so they join into one laid line — fading on
  a squared curve over four seconds with no spring, because grass walked
  flat and left recovers rather than snapping back. Stop, and the way you
  came is still there for about two seconds.

### Changed

- **Grass physics**, now that the tufts are real geometry:
  - the bend normalises over the mesh's **own** height (the bake hands it
    over) instead of a hardcoded ten pixels, so a taller or shorter bake is
    no longer bent on a stretched curve;
  - the tip **drops** as it goes over (arc length held, `lean² / 2H`) rather
    than sliding sideways for free, which was the stretch that made grass
    read as a rug being pulled;
  - **per-tuft identity** from a hash of the cell it stands in — stiffness,
    phase and slump bearing — so a meadow is many plants rather than one
    animated surface, with no per-instance attribute added;
  - a **squall front** modulates the amplitude itself, so wind arrives in
    bands instead of blowing everywhere at one strength.
- **Foot-crush springs back.** The crush list is kept between frames with a
  strength and a velocity per foot: fast chase down, underdamped spring up.
  A tuft passes upright about a third of a second after the foot lifts,
  stands a quarter proud at the top of the kick, and settles inside two
  seconds. It used to snap flat and snap upright.
- **A crushed blade lies DOWN** instead of getting shorter: the tip travels
  outward by most of its own height and drops by nearly all of it, so it
  ends up along the ground pointing where the walker went. Shortening it
  read as the meadow deflating.
- Crush slots **4 → 8**, and now one `vec4[8]` array uniform instead of
  four scalars — one send for the lot. Three slots are live feet, five are
  trail, split fixed so a crowd cannot crowd out the trail and a long walk
  cannot crowd out the foot standing in the grass.
- Flowers take the crush too. A boot that lays the grass flat and steps
  over a flower bed untouched is the seam showing.
- The grass springs and trail integrate on **time since the last grass
  pass** rather than `love.timer.getDelta()`, so a frame that renders the
  scene twice (a staged battle over the overworld) no longer runs the
  meadow at double speed.
- `Wind.leanAt` gained the front and the load terms, so roamers standing in
  a meadow stay on exactly the shader's clock.

### Probes

- `tests/grass_physics_probe.lua`: the AUTO span, the rain/snow load
  reaching the grass and damping it, the crush spring's overshoot, WindFX
  under gale and under OFF, and three screenshots with mean brightness —
  because a shader that fails to compile fails silently and every other
  number still passes.

## 1.17.0-mobile

### Added

- **Volumetric clouds** in the sky pass (cel density, wind-advected). New
  **CLOUDS** options row: ON / THICK / OFF. Step count follows RES so 1/4
  turns clouds off with the other ornaments.
- **3D tall grass** from an authored tuft bake under `assets/ground/grass/`
  (`grass.mesh.bin` + `grass.png`). Stamped per grass tile with random yaw
  and scale. Falls back to the classic tileset slab if the bake is missing.
- **Grass foot-crush**: player and walkers part the meadow (radial push +
  height flatten) while wind leans the tips.
- **Low fog bands** near the horizon at dawn/dusk (coast/canopy denser),
  quality-gated; **post-rain rainbow** ornament.
- Weather / overcast polish that feeds sky, clouds, and light together.

### Changed

- Wind: stronger outdoor range, three-harmonic wave shared by grass, roamers
  and the vertex shader so the meadow stays on one clock.
- Version **naming**: dropped feature suffixes (see Versioning above). This
  release supersedes the interim `1.16.1-mobile.water` tag style.

### Assets

- `assets/ground/grass/grass.mesh.bin`, `grass.png`, `grass.meta.json`
  (optimized from a source GLB; the GLB itself is authoring-only).
- Source GLB stays out of the package; rebuild with
  `tools/optimize_grass_glb.py`.

## 1.16.1-mobile.water

### Added

- **Custom water surface art for lakes and rivers.** Drop a PNG at
  `assets/water/water.png` and the diorama samples it in world XZ on every
  recessed water face (the same geometry identity as the swell surface,
  `y < -1`), replacing the tileset's 8×8 water tile albedo. Delete the file
  and the tileset art comes back — same drop-in contract as `assets/ground/`.
  Cel swell / freeze / foam paint still multiplies on top when WATER is not
  FLAT. Hot-reload drops the GPU object with the rest of the invalidate path
  (`Water.dropGPU`).

### Assets

- Shipped `assets/water/water.png` (1024×1024) as the default lake/river
  surface texture.

## 1.16.0-mobile.rain

### Added

- **BAG and STACK: how much you can carry.** Gen 1 holds twenty distinct
  items and ninety-nine of each, and both numbers are what fit in the Game
  Boy's save RAM rather than anything anybody would design twice. Twenty is
  the one that bites: the HMs, the TMs, the fossils and the key items are
  most of it before a Potion goes in.

  Two rows, because the two limits live in different places. SLOTS goes
  through the engine's own constants registry -- `Bag.capacity` reads
  `Data.constants.bagSize` and its header says in as many words that a mod
  may replace it -- so nothing is patched and uninstalling gives twenty back
  with no migration. STACK is not exposed (`Bag.add` tests `> 99` inline) so
  it takes a wrap, built the way CityLife's `talkTo` hook is: the engine is
  asked first, its yes is final, and only a NO gets a second look -- and only
  when the reason was the stack cap rather than a full bag.

  MAX is a number, not infinity: 999 slots against a game with about a
  hundred and ten distinct items, and a pile of 9999. A single PURCHASE is
  still ninety-nine, because that cap is in the shop's quantity box and this
  mod has no business rewriting a UI.

  Covered by `tests/carry_headless_test.lua`, which runs the wrap against the
  engine's real `Bag.lua` with no game: seventeen assertions, including that
  vanilla behaviour survives the wrap at the 20/99 rungs and that a full bag
  still refuses a new item with the stack raised.

### Fixed

- **A puddle is a puddle, and the player is not.** Everything below about the
  reflection was written, measured and then shipped SWITCHED OFF, because the
  screen-space pass could not tell one surface from another. It had the
  colour buffer and the depth buffer and nothing else, so it identified
  standing water by the FRACTION of its height: a pool floats 0.7 world
  pixels above its cell and no class in the shape profile stands at a
  fraction. A character is a card leaned back by exactly the camera's pitch,
  so its height climbs its own face and crosses point-seven a dozen times on
  the way up, and its normal points at the camera by construction. The
  player, every NPC, every wild and street Pokemon and the carved rim of
  every hedge were classified as standing water. At the tenth of a pixel the
  pond's curve gave them nobody could see it; at the strength a puddle should
  have, the player mirrors the sky in horizontal stripes. Two further gates
  were tried against the probe and both failed -- flatness has no
  discriminating power at render resolution, and a strict normal rejects the
  character cards and the puddles together.

  It is a MASK now, and it cost no render target, no vertex attribute, no
  remesh and no extra texture fetch. The scene buffer already has an alpha
  channel: the void uses it, and no drawn pixel does, because the alpha blend
  equation saturates every opaque pixel to exactly 1.0 no matter what alpha
  it was drawn with. So the ground row draws its puddle decals a second time
  with the colour write masked down to alpha alone and the blend set to
  replace, stamping 254/255 into those pixels and only those; the reflection
  pass tests the byte it was already reading for the pixel's colour. Nothing
  can land on the mark by accident, which is what makes this a mask rather
  than a fourth guess at geometry.

  `RayFX.PUDDLE_Y`, `PUDDLE_WINDOW` and `PUDDLE_FLAT` are gone with the gates
  that needed them, and so are the four depth taps the flatness test cost.
  The decals' float heights (`GroundFX.PUDDLE`, `DRIFT`, `PRINT`) now mean
  only what they say -- which layer wins the depth test.

  `tests/puddle_rtx_probe.lua` paints the classification instead of
  reflecting with it (`RayFX.DEBUG_MASK`) and counts the pixels, because the
  failure this row spent two releases on is invisible in an ordinary
  screenshot and an OFF/ON pair of a rain shower is two different frames of
  an animation. On a DRY street the correct count is zero with the player,
  the NPCs and the hedges all still standing there: 0 of 331,776 sampled, at
  two camera rungs. In the rain it is the pools at all four rungs -- the
  fraction test had never matched one at 35 or 75 degrees.

- **Puddles reflect.** The RTX row found them, marched a ray off them, hit
  something and mixed it in -- at about a tenth of the pixel, underneath a
  decal drawn at ninety percent alpha. So every stage of the feature worked
  and the result was a puddle you could not tell from one with the row
  switched off, which is the worst shape a bug can have: it costs the
  milliseconds and shows nothing.

  The cause was one Fresnel curve doing two jobs. `mix(0.10, 1.0, (1-cos)^3)`
  is honest for a POND -- a pond has a body, there is water under the surface
  and looking down into it you see the water rather than the sky, so a tenth
  from above is right. A puddle has no body. It is a film over dark paving
  with nothing underneath it to look into, and what a wet street shows you IS
  the reflection, at every angle a person can stand at. Run through the
  pond's curve it landed at 0.080 of the pixel at the 15-degree camera rung,
  0.084 at 35 and 0.113 at 50 -- and 0.373 at 75, which is the one rung
  nobody plays at and the reason this survived a release.

  Puddles have their own floor and their own amount now (`PUDDLE_FRESNEL`,
  `PUDDLE_AMOUNT`), so the same four rungs land at 0.595, 0.597, 0.612 and
  0.744 -- nearly flat across the ladder, because the reflection is what the
  surface IS and should not appear as the player tips the camera. The pond's
  curve is untouched.

- **Puddles ripple, and it is the RAIN doing it.** The ripple was the sea's
  swell taken at a third, which is the wrong shape twice. Wrong in SCALE: the
  swell's trains run about eighty world pixels between crests, five cells, so
  a pool a cell and a half across sat inside a fraction of one wave and
  tilted as a single slab -- the reflection slid about instead of breaking
  up. Wrong in CAUSE: `Water.swell()` is the WATER row, whose first rung is
  FLAT, so a player who did not want the sea to heave was also switching off
  every ripple in every puddle in Kanto, in a downpour; and in a town, which
  has no water in it at all, the swell had nothing to do with the shower
  overhead in the first place.

  A puddle now has its own surface, off the shower rather than the swell: a
  five-pixel chop that turns a mirror into a wet mirror, and one impact ring
  per cell on its own clock, expanding out of a hashed point and dying. Both
  fade to nothing as the rain does, so a pool in the ten minutes of aftermath
  the GROUND row keeps it around for is a still mirror -- which is the shot
  that dry-out exists to give.

- **The rim of a pool reflects.** A puddle is a decal, so the four-tap normal
  at its outermost pixel straddles the 0.7 step down to the road and reports
  a near-vertical face -- which failed the "is this facing up" test. That is
  the one ring the art draws BRIGHT, so a pool came out as a dry lit outline
  around a dark middle. A marked pixel is a puddle whatever a normal
  reconstructed across its rim says about it, so the test does not apply to
  pools at all any more -- it is left exactly where it was for the shoreline
  lip it was written for.

- **Rain lands in the puddles.** Splashes were placed on "walkable or water",
  which in a wet street means the dry paving BESIDE every pool and never in
  one -- so the two effects read as unrelated things bolted together. They
  prefer standing water now, and open a good deal wider when they land in it.

- **Splashes are on the ground they land on.** A splash was pinned at world
  zero whatever it burst on, which is right on a route's dirt and sixteen
  pixels underground on a town's raised paving. So in exactly the places
  worth standing in a downpour, every ring drew sunk into the street.

### Added

- **SHELTER: the town goes in out of the rain.** The mod grew a sky that
  clouds over, rain that falls, ground that soaks and pools that gather in
  it, and underneath all of it the street carried on exactly as it had in the
  sun. When a shower comes down hard, wandering civilians now walk to the
  nearest door and stand in it until it passes, and the street Pokemon go
  inside and are gone until the sky clears.

  What it does NOT do is take anybody out of `ow.npcs`, and that is the
  design rather than a shortcut. The engine's scripts find people by walking
  that list -- Pallet's Oak is index 1, Pewter's youngster is 5 -- and an NPC
  that is not in it is a story that breaks on a rainy Tuesday. So the map's
  own people go as far as the DOORWAY, where they are still addressable,
  still findable and still worth walking up to; the street Pokemon do vanish,
  because this mod made them and no script has ever heard of one.

  Trainers, STAY objects and anybody mid-script are never touched. Somebody
  standing in a doorway wears the engine's own `passable` flag while they are
  there, so a shower never shuts a shop.

- **ROUTINE: the people have something to do.** A Gen 1 NPC faces one way
  forever or takes a random step every few seconds, which is why a town reads
  as a set of bookmarks holding places open until the player arrives. They
  look around now, turn toward the sign or the door they are standing beside,
  and stand in pairs facing each other having a conversation -- with a shuffle
  on the spot, through the engine's own turn-in-place animation -- and then go
  back to the facing the map authored.

  Nobody moves off their cell. Where an NPC stands is in the map record and
  half of Kanto's scripts are a line attached to a person in a particular
  doorway; a facing is one string nothing reads, and it is the strongest
  signal a 16-pixel sprite has.

### Probes

- `tests/puddle_rtx_probe.lua` prints the reflection's share of the pixel per
  camera rung and shoots RTX OFF against RTX RT at each one -- because "it
  does not reflect" and "it reflects at a twelfth of the pixel" are the same
  screenshot and are not the same bug.
- `tests/town_rain_probe.lua` counts the street dry, wet and dry again. The
  third reading is the one that matters: an empty street and a street whose
  people were permanently deleted look identical, and only one of them is the
  feature.

## 1.15.0-mobile.snow.5

### Fixed

- **Trees collect snow.** A snowfall that buried the ground and whitened the
  roofs left every canopy standing green with a few grey specks on its crown,
  and the reason is the one case where reading a face normal off the geometry
  gives the wrong answer. A hull's front face is a flat plane in the mesh and
  a CURVED surface in the drawing -- it is the canopy seen face-on, per pixel
  -- so the mesher called the whole front of a tree upright and handed it a
  flank's share. Which is the same complaint the flanks rule was written for
  in the first place: from this camera, almost every voxel of a blob you can
  see is a side.

  So the hull says so itself now, for the rows where it is true. Snow lands on
  the upper part of a rounded crown and not on its underside, so the top 45%
  of the mask's height is marked sky-facing and everything below it is still
  left to the geometry -- a green tree with a white cap, rather than either a
  green tree or a white blob. It is a fraction of the drawing rather than a
  pixel count so the same rule serves a 16px shrub and a 32px forest canopy.

  The boundary does not read as a line across a row of trees even though they
  all share one carved template: the drift noise is cut from world position,
  so each canopy breaks its own snow edge differently depending on where it
  stands. Hedges get the same treatment, being the same primitive.

  `ChunkMesher.faceSign` takes an override for this and Structures' round
  hulls are its only caller. Nothing else may claim it -- a builder that wants
  a bright sideways face still has to be told apart from a roof by its shape,
  which is the whole point of that function.

## 1.15.0-mobile.snow.4

### Changed

- **The snow stands in the world's own light instead of being painted over
  it.** This was the whole of why a covered roof read as a white rectangle:
  `snowColor` went on as a flat constant AFTER the shading, so a snowed roof
  was the same colour at noon, inside a building's shadow, and at midnight.
  Nothing else in the frame behaves that way, and an eye reads a surface that
  ignores the light as a surface that has been *painted* rather than covered.
  Multiplied through the hour's light it goes blue where only the sky reaches
  it, warm under a low sun and dark after dusk -- and a shadow thrown across a
  white field is finally visible, because there is something for it to fall
  on. The lit fraction is worked out once and shared with the main shading, so
  the shadow map is still sampled exactly once per fragment.

- **Snow lies in patches that grow, not as one tone that fades up.** Two
  voxel-quantized noises cut from world space now drive it -- a coarse DRIFT
  at about five world pixels for where the fall heaped and where the wind
  scoured it, and a per-pixel GRAIN that does the dithering. The drift moves
  the THRESHOLD rather than the amount, so a hollow needs a deeper fall before
  it takes any and a heap takes it early: as the weather works, patches appear
  and grow into each other across a roof instead of the whole surface going
  evenly paler at once. Both are anchored to world position, so a drift
  belongs to the place it lies in -- it does not crawl when the camera pans,
  and two maps meeting at a seam agree about it.

- **A drift has form.** Its crests catch more of the sky and its hollows sit
  back from them, in two hard steps rather than a gradient. This is what stops
  a fully covered roof reading as one flat tone even when the cover really is
  total.

- **And it glitters where the sun reaches a crest.** A few per cent of the
  covered pixels, on up-faces, once the fall is deep enough to have a surface
  of its own. Gated on the sun actually reaching the fragment, which makes it
  dynamic with no clock driving it: walk a shadow across a snowed roof and the
  glitter goes out under it and comes back on the far side. The highlight is
  half again the *local* snow rather than a fixed white -- the sun rig hangs
  the moon on the same lamp, so a constant white would have scattered
  noon-bright specks across a midnight-blue field.

- **A roof keeps its own art at every depth.** The cover tops out at 0.86
  rather than 1. `GroundFX.SNOW_TINT` stopped short of 1 for exactly this
  reason and quantizing up to the last rung had been quietly undoing it, which
  is why full snowfall turned the town into white blocks. That ceiling now
  lives in the shader where the rounding happens; `SNOW_TINT` sets how fast
  the drifts get there.

## 1.15.0-mobile.snow.3

### Fixed

- **A snowed town is white ROOFS over its own walls, not white boxes.** Every
  building went pale all over, and the reason is that the shader had no idea
  which way a face pointed. It guessed from the shade, on the theory that 1.0
  meant up -- but a shade is BRIGHTNESS, and both meshers have good reasons to
  hand a sideways face a bright one. A building's south face is the artwork
  itself, so it is emitted at full energy and tested as sky-facing; that same
  building's roof carries `VOLUME_TOP_SHADE`, which is *darker* than its
  walls, so the one surface the snow actually lands on took less of it than
  the wall underneath. White boxes with grey lids -- the exact inverse of a
  snowfall.

  The meshers work out each quad's real face normal from its own geometry now
  (`ChunkMesher.faceSign`) and carry it in the SIGN of the shade, which the
  scene shader splits back apart. No fourth vertex attribute, so a route still
  uploads the same twenty megabytes it always did. A roof, a ledge, the ground
  and the crown of a tree take all of the snow; a wall, a facade and a tree's
  front take `SNOW_SIDE`, whatever brightness any of them happen to draw at.

  The test asks whether a face is VERTICAL rather than which way it points.
  Winding is unenforced here -- nothing sets a cull mode -- and the emitters
  genuinely disagree on it, so reading the sign would have called `topQuad`
  or the gable segment a wall depending which way you picked. It also means a
  gabled roof counts however steep it is, which a 45-degree cone would have
  failed on exactly the small buildings whose roofs read most as roofs.

- **The snow lies in dithered steps instead of washing over the art.** A flat
  fraction of white blended across a surface is an airbrush, and at a third
  covered a roof simply came out evenly pale -- a roof painted a lighter
  colour, not a roof with snow on it. The cover is snapped to four levels now
  with a checkerboard breaking each threshold, so a surface goes white a pixel
  at a time as the fall deepens, the way the sky's ramp and the swell's bands
  already do it. The checker is cut from WORLD pixels rather than screen ones:
  anchored to the screen it would stand still and let the world slide through
  it, and every roof in the frame would crawl as the camera panned.

### Changed

- **Trees are back to their original brightness.** `snow.2` dropped
  `ROUND_SHADE.front` to 0.90 to stop a canopy testing as an up-face, which
  cost every tree a tenth of its south face all year round. With the meshers
  reading real normals that workaround is gone and the value is 1.0 again --
  the hull's front IS the drawing and draws at full energy, and it is only a
  brightness again.

## 1.15.0-mobile.snow.2

### Fixed

- **The snow on a tree stops floating over it.** The cap decal is one
  horizontal quad, and it was being handed to the tree canopies -- which are
  not lids. A canopy is a voxel hull carved from its own drawing, so the
  height the shape profile gives it is where its HIGHEST voxel lands and the
  crown falls away from that by half a cell before it reaches the rim. A flat
  16px tile at that height touches the crown at one point and hangs in the air
  everywhere else. No lift value ever fixed it, which is the tell: the mistake
  was never how high the quad sat, it was that a flat quad is the wrong
  primitive for a round thing.

  `crustCell` asks for a flat top now (`VoxelScene.flatTop`), so the decal
  lands on the roofs, walls, ledges and fences it is flush on and nowhere
  else. The trees are not left bare -- their snow is the crown's own
  up-facing voxels going white in the scene shader, which is real geometry
  and follows every curve of it. Geometry cannot float above itself.

- **A snowed tree whitens on its crown instead of washing out whole.** The
  scene shader reads a vertex's shade as the only thing it carries that knows
  which way its face points -- 1.0 is up, and snow lies on up. The round hulls
  handed their FRONT a 1.0 as well, for art brightness, so a canopy's south
  face -- the one this camera ever looks at -- tested as sky-facing and took
  the full snow tint. In a snowfall a tree went to a flat white blob and its
  crown said nothing about the shape underneath. `ROUND_SHADE.front` is
  `FACE_SHADE`'s own south now (0.90, the value the rest of that table already
  mirrors), so a hull's front takes `SNOW_SIDE` like the flanks it belongs
  with. Trees draw a tenth darker on the south face year-round, which is where
  every other shaded flank in the world already sits.

- **A cap never hangs off the edge of what it is sitting on.** It carried the
  drifts' jitter and size variation -- up to two and a half pixels off centre
  and a seventh wider than its cell. That is right for snow on open ground,
  where there is always more ground under it, and wrong for snow on a thing
  that ends at its cell: at the end of a wall or the rim of a roof it put
  white past the edge with nothing beneath it. Caps are centred and exactly
  16px now (`CRUST_SIZE`), so a run of them still tiles with no seam and none
  of them leaves the lid it is lying on. The variation is the strip -- a
  different drawing per cell -- which is where it belongs.

## 1.15.0-mobile.snow.1

### Changed

- **The puddles are drawn art now, and there are far fewer of them.** They
  shipped stippled -- one cell in six, small, and landing in twos and threes
  -- which is not what rain does. Rain collects: the low spot next to a low
  spot is one low spot.

  Placed on a BLOCK GRID, and it is the third rule this has had. The first
  two were both attempts to thin a per-cell die into something spaced, and
  both were unpredictable in the same way: a local-minimum-of-the-hash rule
  is a Poisson-disc thinning and reads beautifully on paper, and what it
  actually produced was one pool per a hundred and forty-four cells where
  the arithmetic promised one per forty-nine -- because the estimate assumes
  every neighbour is eligible and most of a town is buildings. Tightening
  the radius moved it from four pools to five.

  So the map is cut into three-cell blocks, each holding at most one pool,
  on the first of its cells that can actually hold water. One pool per nine
  cells of ground, never two in a block, and a count that can be stated
  rather than discovered. `tests/puddle_debug.lua` prints the coordinates
  and the closest pair, which is how the last two rules were caught.

  They are also bigger (up to nearly two cells across) and much darker,
  because standing water reads by being a hole in the road: at the sky's own
  brightness a pool on pale paving was a slightly different pale, visible in
  the draw count and invisible on the screen.

- **A puddle may lie on any walkable cell**, not only one at height zero.
  That rule was there because water runs downhill, which is true, and it
  quietly deleted the puddles from most of the game: a town's paving, a
  Center's forecourt and half of Route 1's path all carry a height from the
  shape profile, so the streets stayed dry in a downpour. Every walkable
  cell is flat whatever its height, which is all the rule was after.

- **Snow falls in three DRAWINGS rather than one at three sizes** -- a
  dusting caught in the seams, then patches, then lying with the ground
  showing through in dithered holes. That is the difference between snow and
  water: a pool is the same pool getting wider, and a snowfall is a
  different picture at each depth. Scaling one drawing up could only ever
  make bigger specks.

- **And it settles on the hedges, the trees and the roofs.** Snow used to
  land only on ground you could walk on, which left every bush in a white
  field standing green -- a field of snow with green bushes in it reads as
  paint. A cap cell is now one you cannot stand on that stands above the
  ground, which is the shape profile's own description of a tree or a roof
  and needs no list of tile ids; the cap floats five pixels clear so it sits
  on a rounded crown instead of inside it.

### Fixed

- **The puddles stopped reflecting the moment they were worth looking at.**
  Two separate causes, both found by the probe rather than by eye.

  The reflection pass recognises a puddle by the height it floats at, and it
  was testing the ABSOLUTE height -- so it found the pools on Route 1's dirt
  at 0.7 and missed every one in Viridian, whose paving puts them at 16.7.
  It tests the FRACTION now: every class in the shape profile is a whole
  number, so something-point-seven is a puddle at any height. (The
  footprints moved from 1.7 to 1.35 to stay out of that signature -- at 1.7
  they would have been mirrored.)

  And at their fullest the far edge of a pool is far enough away that the
  depth buffer resolves its height a little loosely, and a fraction that
  wandered past a tenth fell out of the window. The window is 0.22 now and
  the largest step is smaller.

### Notes

- The ground art is generated art no longer: `assets/ground/` carries six
  drawn strips, and `assets/ground/source/` the generator sheets they were
  cut from (`tools/sheet2strip.ps1`, extended with a per-sheet background
  window and an inset for sheets whose border cannot be found -- the five
  snow sheets came back on three different backgrounds between them). Both
  the sources and the converter stay out of the packaged mod.

- Two of the five snow sheets have not been cut successfully yet: their art
  and their paper are the same tone and the flood fill walks through the
  outline. `snow-cap.png` is the medium one, used at all three steps, until
  they are recut. See `assets/ground/README.md`.

## 1.14.0-mobile.comforts.1

### Added

- **The puddles reflect.** The RTX row's screen-space reflection now finds
  them, so a pool on a wet street carries the sky, the trees beside it and
  whatever is standing on the far side of it -- the same march off the same
  depth buffer the ponds already got.

  Finding them at all is the interesting part. That pass has the colour
  buffer and the depth buffer and no third thing -- no mask, no stencil, no
  water channel -- and a puddle is a decal the GROUND row lays on the floor
  rather than a class in the shape profile, so every test it had ruled one
  out. So the HEIGHT is the identification: puddles float at exactly 0.7
  world pixels, which is a height nothing else in this world has (every
  class in the profile is an integer). Snow floats at 1.0 and footprints at
  1.7, which is also how the snow stays out of it -- a mirror-finish
  snowfield would be ice.

  It cost one thing: the puddle layer now WRITES depth where the other
  decals do not, because a decal that is not in the depth buffer is a decal
  the reflection pass cannot see. Safe because everything drawn after it --
  characters, tall grass, flowers -- is pulled camera-ward by six world
  pixels or more against a puddle's seven tenths of one.

  A puddle takes a third of the swell's tilt rather than all of it: enough
  that the reflection breathes with the rain landing in it, not enough to
  look like surf in a pothole.

- **Puddles and snow GROW, a voxel at a time.** Three baked sizes per layer,
  of which exactly one is ever drawn, stepping up as the ground soaks or the
  snow settles and back down as it dries or melts. Steps rather than a
  smooth swell because a pool that grew continuously would want its mesh
  rebuilt every frame -- and because on a world made of voxels the right way
  for a puddle to grow is a pixel at a time anyway.

  Which also replaced the drifts' old two density ranks with one axis: at
  step one the snow is separate patches, at step three the quads are wider
  than their cells and overlap into a single sheet. Same read, half the
  meshes.

- **Experience for the whole team -- the EXP row.** Gen 1 pays the Pokemon
  that fought and nothing else, which is why a Gen 1 party is one Pokemon
  and five passengers: the only way to bring a second one up is to send it
  out, let it take a hit and switch back, every battle, for the whole game.
  Nobody enjoys that; it is not difficulty, it is bookkeeping, and the
  series deleted it itself by Gen 6.

  TEAM gives every Pokemon still standing what the fighters got. SPLIT
  divides that same total among them, so the party still moves together but
  the pace is the one the game was balanced on. OFF is the original's rule,
  byte for byte. Fainted Pokemon are paid nothing at every rung.

  Through `battle.exp_award`, whose own comment in the engine names this
  exact case -- so nothing here computes experience, reads a growth rate or
  touches a level: `ctx.applyShare` is the helper vanilla uses, and the only
  decision made is who it is called for. Which is why the level-up jingle,
  the stat box, the move learned on the way up and the evolution check after
  the battle all still happen by themselves.

  Only the Pokemon that FOUGHT gets the text box. Vanilla's EXP.ALL
  announces for every one, which on a full party is six presses after every
  fight -- and a row that exists to remove friction must not trade a swap
  for a swap's worth of button presses.

  Its own row rather than a tenth mercy on QOL, because everything on that
  row removes friction without touching the game's numbers and this one
  changes the difficulty curve.

Three more mercies on the existing **QOL** row:

- **The box that fills up.** The engine already overflows a full box into
  the next one with room, so a catch does not fail here until all two
  hundred and forty slots are taken. What was missing is that nothing
  followed it: the Pokemon landed in box 4 and the PC still opened on box 1.
  Now the current box follows the catch, and the PC's own DEPOSIT rolls
  forward instead of printing "BOX n is full!" and stopping.

  Done by moving `save.currentBox` before the menu is built, which is the
  whole fix -- no reimplementation of the deposit and no second copy of the
  capacity rule. A box that has room is left alone: that is the box the
  player chose to be on.

- **The bag, in pockets.** Gen 1's bag is twenty slots in pickup order with
  no pockets -- those arrive in Gen 2 -- and the only tool for it is SELECT
  to swap two entries at a time. The list is now sorted into balls,
  medicine, TMs and HMs, key items and everything else, each group
  alphabetical, rewritten into the save's own `Bag.order` so every screen
  that reads the bag sees the same list. Plus wrap, page jump and
  hold-to-scroll through the engine's `ui.list_menu` hook -- and only for
  the bag, because a shop asking for hold-to-scroll is a different decision.

  The trade: the original's manual SELECT ordering does not survive the next
  time the bag is opened. It is a sort.

- **Rename, whenever you like.** Kanto has no NAME RATER -- he is a Gen 2
  building -- so a nickname typed in a hurry at level 5 is that Pokemon's
  name for the rest of the game. RENAME now sits on the party submenu beside
  STATS and SWITCH, through `ui.party.submenu` and the `onSelect` its
  dispatcher documents for exactly this. Clearing the name puts the species
  back, because `nil` is not a missing nickname, it is the answer. Not
  offered mid-battle.

### Notes

- `tests/comforts_probe.lua` runs all of it on a live game: the award asked
  of its own decision with a recording `applyShare` (who is paid, with what
  divisor, who gets the text box), boxes filled to capacity on purpose, a
  deliberately scrambled inventory sorted and checked for contiguous
  pockets, the naming screen actually driven to a new name and then cleared,
  and the puddles photographed at each of their three size steps with an
  RTX OFF/MAX pair at the end.

## 1.13.0-mobile.ecology.1

### Added

- **Who is out right now — the ECOLOGY row.** Gen 1 has one encounter table
  per map and it is the same table at every hour of every day. Gen 2 answered
  that with three tables per map, and it is the single change that did the
  most to make Johto feel like a place rather than a set of rooms with
  monsters in them. This is that, built out of what Gen 1 already ships.

  Nothing is added to a route and nothing is taken away. What moves is the
  ODDS: the ten-slot table is drawn from with its own cumulative buckets --
  exactly as `Encounter.roll` does -- and each slot's share of the 256 is
  then multiplied by what the hour and the sky think of that species. A Zubat
  is still on Route 4's table at noon; it is simply the least likely thing on
  it instead of being as likely as it was at midnight.

  Deliberately weaker than Gen 2, which made its night species night-ONLY.
  Deleting half a route's table for half the clock would break the promise
  the WILD row rests on ("the species, the levels and the slot odds are the
  ROM's") and would turn a half-finished dex into a waiting game. Tilting the
  odds says the same thing about the world and takes nothing from anybody.

  Who keeps what hours is Gen 2's OWN answer wherever Gen 2 had one: every
  name on the nocturnal list is a Gen 1 species that Johto or Kanto put on a
  night table, so this is the series' later reading of its own creatures
  carried back a generation rather than an invention. Anything in neither
  list falls back to its types -- a Ghost or a Poison leans nocturnal, a
  Flying or a Fire leans diurnal -- at half the weight, because it is half a
  guess.

  Indoors none of it applies, which is the rule this mod already holds
  everywhere else: a cave at midnight is exactly as dark as a cave at noon.

- **Rain brings the water Pokemon out, and up onto the bank.** Two levers.
  The reweighting above, with WATER up and FIRE down on the shower's own
  `power` -- and, because most Kanto grass tables have no water type on them
  at all and that lever alone would do nothing, a second one: in a heavy
  shower a spawn on land within three cells of real water may be drawn from
  the map's OWN water roster instead. `encounters[map].water` where the map
  has one, and `field.superRod[map]` otherwise -- the ROM's own answer to
  "what lives in this map's water" for thirty-three maps that have no surf
  table at all.

  Its LEVEL is clamped into the band the map's own grass table uses, and that
  is the one number in the feature that is neither the ROM's nor derivable:
  the fish rosters are levelled for a Super Rod you get late, and a level 23
  Kingler on Route 6 would not be atmosphere, it would be a difficulty spike
  wearing a raincoat.

  Both reach the blind roll as well as the visible Pokemon, through the
  engine's own `encounter.species` seam -- which runs on a roll that already
  happened and BEFORE the repel filter, so repel, the ghost rule, the Safari
  menu and the battle all go on reading the answer rather than the question.

- **What the weather leaves behind — the GROUND row.** The WEATHER row draws
  what is falling; this draws what has fallen, and the difference is time. A
  shower is over in two minutes and the ground it soaked is wet for ten,
  which is most of the time anybody spends walking around in the aftermath of
  one. Without this the sky clears and Kanto is instantly, impossibly dry --
  the effect switching off rather than the weather ending.

  Puddles gather through a shower and drain over four minutes; snow settles
  in two ranks of drift and melts over seven. Where a puddle goes is a HASH,
  not a die, for the reason the sleeping Meowth's house is one: water that
  appeared somewhere else every time a map streamed back in would be a
  particle system rather than weather.

  They wear the SKY's own colour -- the horizon band, normalised so only the
  hue carries -- because a puddle is a piece of the sky lying on the ground,
  and one that stayed grey through a sunset would be the only thing on screen
  not taking part in the evening.

  And footprints behind everybody walking on the snow: you, the NPCs, the
  wild Pokemon in the grass. Dropped on the cell somebody LEFT rather than
  the one they arrived at, and filled back in over half a minute -- faster
  while it is still coming down. When the ring is full the oldest print
  SOMEBODY ELSE left goes first, which is not politeness: a route with ten
  wild Pokemon wandering it fills the list in seconds, and a plain
  oldest-first eviction spent the whole of it on their trails, so the player
  would turn round to look at where they had walked and find nothing there.

  All of it is drawn as GEOMETRY between the ground and the people standing
  on it rather than in the overlay pass every other drawing in this mod uses,
  and that is the load-bearing choice: a butterfly IS in front of the world,
  and a puddle is underneath the person standing in it. So it is
  depth-tested (a puddle behind the Mart stays behind it), never
  depth-writing (the tall grass still wins its feet-overdraw fights), and it
  takes the hour's light and the sun's shadows for free. The price is the
  same one the steam off a mug pays: it wants the VOXEL camera.

  The shapes are generated, but only as the fallback -- a strip of 16x16
  frames at `assets/ground/puddle.png`, `drift.png` or `print.png` is used
  as-is, however many frames wide it is. Two rules any replacement keeps, and
  both are the scene shader's rather than this feature's: the ALPHA is the
  shape (under half alpha is discarded rather than blended, so hard edges and
  a dithered fringe), and the RGB is a TONE rather than a colour (every texel
  is multiplied by the colour the feature picks, so grey in, weather out).

### Fixed

- **The RTX row reflected the whole world once the V-CURVE row was on.**
  The pass identifies water geometrically -- it is the one class in the
  shape profile that stands below zero -- and read that height straight out
  of the depth buffer. The depth buffer records the world after the curve
  has bent it down over the horizon, so past a certain radius every pixel in
  the frame stood below the water ceiling: a route's whole middle distance
  was classified as a pond and mirrored the sky, which is what "fake ray
  tracing treats everything as water" looked like from the outside.

  The bend is taken back off before the question is asked, so the
  classification is about the FLAT world -- the one the shape profile's
  heights are written in. Two more things came with it. The test had no
  floor, so anything below the ceiling qualified however far below it was;
  water lives in a BAND (recessed to -2, lifted and dropped by the swell)
  and the band is what is tested now. And the reflection's surface normal
  now folds the curve's own slope in with the swell's, because a pond lying
  on a tilted plane was reflecting off a flat one and pointing its
  reflections at the wrong part of the frame.

  `tests/rayfx_water_probe.lua` shoots a route with no water on it at
  V-CURVE OFF and at V-CURVE 3, and a pond at both, because this is a
  screen-space effect and there is nothing to count: the claim is about what
  the frame looks like.

- Ground decals came back MOTTLED at the drop shadows' own quarter-pixel
  float -- half of every quad winning the depth test against the very surface
  it lies on and half losing it, which reads as a dirty wash rather than as
  snow lying. A whole pixel settles it and is invisible at every pitch this
  camera has.

- Drifts drawn at cell size read as an even field of white dots. They are
  drawn WIDER than their cell now, so neighbours overlap into one surface
  with a ragged edge, which is what a snowfield is.

### Notes

- The ground decals now ship as **drawn art** rather than generated shapes:
  `assets/ground/puddle.png`, `drift.png` and `print.png`, six frames each
  for the first two. The generated ellipses and blobs are still in the file
  and still the fallback -- an install with that folder stripped looks
  slightly plainer and nothing else -- but a drawn snowdrift beats a
  described one, which is the whole reason the override existed before
  there was anything in it.

- `tools/sheet2strip.ps1` turns a generator's contact sheet into the strip
  the mod wants: it finds the outer border, divides the grid, floods the
  paper out from each cell's edge (a fill rather than a threshold, because
  a footprint's interior is darker than the paper it sits on and only its
  outline separates the two), crops to the art's own bounding box across
  the whole sheet -- one box, so the drawings keep their relative sizes --
  and renormalises the tones so the brightest pixel is white. Three sheets
  came back on three different backgrounds and none of them was the one
  that was asked for, which is why this exists.

- `tests/ecology_ground_probe.lua` runs all three on a live game: the same
  route's table drawn four thousand times at noon and at midnight with the
  two distributions printed side by side, the come-ashore roll counted
  against a real cell next to real water, and the decals counted through a
  real frame with A/B screenshots of the row on and off. Two of the tuning
  numbers above are in the changelog only because that probe measured them.

## 1.12.0-mobile.glint.1

### Added

- **Hidden items glint on the ground.** Gen 1 buries about eighty items --
  in bins, under trees, in corners of caves -- and gives you exactly one
  way to know: the Itemfinder, which says "there is one within a few tiles"
  and nothing about where. What follows is walking every tile pressing A.
  That is not a puzzle, it is a search with no information in it.

  So the ground says so. A small cel-shaded catch of light over the cell,
  in the same overlay pass the ambient life composites through, on the
  cells the game's own `field.hiddenItems` names -- and out the moment the
  item is taken, because `save.hiddenTaken` is the same record the pickup
  writes, re-checked per frame rather than per map.

  Deliberately not the item handed over: it does not name what is buried
  and it does not pick it up. You still have to notice it, walk there and
  press A. It is the Itemfinder made honest.

  Pale gold rather than white, because this mod's snow, steam and rain are
  already white and a fourth white thing on the floor would read as one of
  them lying there. The pulse spends most of its cycle dark: a glint lit
  half the time is a lamp, and what is wanted is something you catch out of
  the corner of your eye.

  On the **QOL** row with the other mercies, not AMBIENT -- a buried Rare
  Candy is not alive, it is friction being lifted.

  `tests/hidden_glint_probe.lua` checks the glints against
  `field.hiddenItems` with a stub projection rather than by eye, because at
  this camera angle a glint on the right cell and one a cell over look
  identical, and "it drew something" is not the claim.

## 1.11.0-mobile.qol.2

### Added

Three more mercies on the existing **QOL** row, all three through engine
hooks the engine had already put there rather than through wraps.

- **Hold B to run.** Ten frames a step against the walk's sixteen, on the
  overworld only. Through `movement.speed`, whose own comment in the engine
  names "running shoes, dash" as the reason it exists.

  Not the same thing as the engine's GAME SPEED row, and the difference is
  the point: that runs the whole game faster -- battles, text, animations --
  and this is the walk and nothing else, so what is paced on purpose stays
  paced. It stands down on the bicycle, which is still faster at eight
  frames: a mod that made walking match the bike would have quietly deleted
  an item you go and get. B because on the overworld B is the button that
  does nothing; it is cancel in menus and run-away in battles, and neither
  reaches this hook.

- **Field poison stops at 1 HP instead of killing.** It still needs an
  Antidote -- the Pokemon stays poisoned -- it just cannot walk one into a
  black-out and the money it costs. Gen 4 made this change and nobody has
  ever asked for it back.

  Done without touching the damage loop, which also owns the faint
  messages, the Pikachu happiness penalty and the black-out: a mon that
  would die simply is not poisoned as far as that loop can see, its status
  lifted for the length of the call and put straight back. The wrap only
  ever removes damage, so nothing downstream can be surprised by it.

- **Trade evolutions happen at level 37 without a second machine.** Kadabra,
  Machoke, Graveler and Haunter evolve by trade and by nothing else, which
  on one console means they do not evolve at all -- Alakazam, Machamp, Golem
  and Gengar are simply absent from a solo game. That is not difficulty, it
  is a hardware assumption from 1996 that stopped being true.

  Through `evolution.check`, which exists to "cancel or force any evolution"
  in as many words. The original check is asked FIRST and its yes is final,
  so a real link trade still evolves them the instant it completes; this
  only ever adds a second way in. `QoL.TRADE_LEVEL` moves all four.

All three answer to the QOL row, so OFF is still the full 1996 friction --
verified in both directions by `tests/qol_extras_probe.lua`, which exercises
each through the engine (a real `applyFieldPoison` step, a real
`Evolution.pendingFor`) rather than asserting about it.

## 1.10.1-mobile.weather.2

### Fixed

- **Rain and snow fell indoors.** Walk into a house in a shower and the
  streaks kept coming down through the ceiling. The tick DID drop every
  splash and every streak the moment the sky closed over -- but the DRAW
  refilled the streak field from scratch on the very next frame, because
  that is what it does when the list is short, and it had no idea it was
  indoors. Clearing the list was never going to be enough while the thing
  that refills it did not know.

  The real fault was one function answering two different questions.
  `Weather.falling` means "what is the weather doing in Kanto", and indoors
  that answer is still *raining* -- which is right for the SOUND, because
  you can hear it on the roof. It is wrong for the picture. So there is now
  a `Weather.visible` beside it, gated on the same open-sky test the sky,
  the sun and the hour's tint already rest on, and every draw path asks
  that one instead. Nothing is drawn indoors or under Viridian Forest's
  canopy: no streaks, no splashes, no flakes, no lightning.

### Changed

- **The ambience is recorded now, not synthesized.** The chip programs were
  a good argument and a bad result. A square-wave blip is a convincing menu
  beep and an unconvincing cricket, and at the level ambience has to sit --
  under the map's own looping song -- a thin blip is not quiet, it is
  inaudible. The synth reproduces a Game Boy's sound effects perfectly,
  because that is what they are; it cannot do a field at dusk, because a
  field at dusk is a hundred overlapping sources and the hardware has four.

  Five recordings in `assets/audio/`, every one of them **CC0** -- no
  attribution required and no share-alike, so nothing here sets terms on
  the mod or on a fork of it. `assets/audio/CREDITS.md` names each
  recordist anyway and says why several otherwise-good CC-BY-SA nature
  recordings were passed over.

  The channel programs stay, registered under the same ids, and finally do
  the job they are actually right for: the FALLBACK when a file is missing,
  an assets folder is stripped from a build, or a driver will not decode
  Vorbis. The ambience gets worse rather than disappearing.

- **And they are beds, not blips.** The deeper half of the same mistake.
  Crickets were scheduled as discrete chirps on a countdown -- which is
  what the synth could manage -- but a real cricket field is one continuous
  thing whose LEVEL moves. Four of the five now loop and are crossfaded by
  what the world wants: nightfall brings the crickets up rather than
  switching them on, walking away from a river takes the river down, a
  shower brings the rain up over ten seconds alongside the sky going grey.
  Dusk is one bed rising as another falls, not a handover. Only thunder is
  a one-shot, because a thunderclap is one.

  The overall gain went from 0.34 to 0.85, and each bed carries its own on
  top: the number that made a square blip merely quiet made a real cricket
  field silent.

- **Dead air is trimmed off every recording before it loops**, measured
  rather than assumed -- a looping source repeats its buffer with no gap,
  so a beat of silence at the tail is a hole you hear every time round.
  Two of the Oggs carry most of a second of it.

## 1.10.0-mobile.weather.1

### Added

- **WEATHER, a new row: the sky does something.** AUTO gives Kanto
  occasional showers -- a minute or two of rain every few, arriving and
  clearing on their own, about one minute in eight.

  What makes it read as weather rather than as an effect being switched on
  is that **five things move on one number**. A single `power`, eased from
  zero to its peak over seven seconds, drives every one of them: the sky
  loses its blue toward a flat stratus grey *band by band* (so the gradient
  survives -- an overcast horizon is still paler than an overcast zenith),
  the light drops and goes cool on the diorama **and** on the flat 2D world
  through the same one-tint-two-worlds seam the clock already solved, a
  sunset behind the front loses its gold halo, and the water loses its
  glint and gains chop -- rain breaks every crest that was catching the sun
  into a thousand small ones pointing everywhere, so the toon highlight is
  *gone* rather than dimmed. The world darkens at exactly the rate the rain
  thickens because they are the same ramp.

  Rain is drawn **twice**, and it has to be. Streaks are screen-space --
  flat pale lines across the whole frame, leaning on the WIND row's own
  bearing -- because rain between the camera and the world has no world
  position, and giving it one puts it behind the trees. Splashes are
  world-space: cel-shaded rings that open on the ground around you,
  projected through the same camera the field FX and the ambient life
  anchor through, so they say the rain is landing on *this world* rather
  than on the lens. The heaviest of it brings lightning, and the thunder
  arrives after the flash by however far away the strike was.

  **Snow** drifts *in* the diorama rather than across the lens -- a flake
  has a position in the world, wanders down through it on the wind and
  lands -- and AUTO chooses it on its own through the winter of the same
  wall clock the DAYTIME row's SYNC rung follows. Which hemisphere that
  winter belongs to is the one thing that cannot be derived, so it is a
  constant at the top of `lib/Weather.lua`, shipped as `"south"` and one
  word from Kanto's own December.

  None of it happens indoors or under Viridian Forest's canopy. The sound
  does.

- **SOUNDS, a new row: the place has one.** Crickets after dark, birdsong
  through the morning and the day, water moving whenever there is water
  within a few cells of you, rain when it rains, thunder after the flash.

  **Not one audio file ships with this.** Every sound is a Game Boy channel
  program -- a Lua table of notes -- assembled by the engine's own
  authoring path (`src/audio/ChipAsm`, one of the three `src` modules the
  loader names as a supported require) and rendered to PCM by the engine's
  own synth. A cricket is a 12.5%-duty square at 4.2 kHz, three blips and
  out; a blackbird is a rising pair of tones and a falling one; water is
  the noise channel at shift 5, swelling in and ebbing out; thunder is that
  same noise at shift 8, which is the bottom of what the hardware can make.
  So it is exactly as authentic as the game's own effects, because it is
  made by the same synth from the same kind of program -- and the whole
  feature is about nine kilobytes of Lua and nothing at all on disk.

  The rain bed shifts its noise parameter on every note, which is
  load-bearing rather than decorative: the synth reseeds the LFSR at each
  event, so a bed of identical notes replays the identical 267ms over and
  over -- a 3.7 Hz flutter you cannot stop hearing once you have heard it.

  Registered under real ids, so a sound pack can override `DS_AMB_CRICKET`
  with an `.ogg` and be played instead. Obeys the SFX volume row. Works
  with the diorama off, because a sound needs no camera. Rain keeps playing
  indoors, quieter and pitched down, because that is what a roof is for.

  Rendered once per session and lazily, at a measured 2.3ms (the chirp) to
  22.6ms (the two-second rain bed) -- one dropped frame on the first shower
  of a session and nothing after it, which is why none of it is pre-warmed.

- **INDOOR, a new row: houses somebody lives in.** About two in five have a
  Pokemon asleep on the floor, usually the family Meowth -- a real map
  object wearing its own baked art, so the engine y-sorts it, the sun
  throws its shadow and the diorama cuts its card. Press A and it stirs,
  yawns its own cry a little slow, and goes back to sleep. It never
  wanders and never wants a fight.

  Which house has one is decided by the house's own **name** -- a hash, not
  a die. A random roll would put a cat in a different house every time you
  walked in, and a cat that teleports between houses is not a pet, it is a
  spawner. Hashed, it is always the same Pokemon asleep in the same corner.
  Placed against a wall and clear of every door, because a real object
  blocks and the answer to that is to put it where nobody was walking.

  And mugs left on the tables, still steaming, found through the mod's own
  shape profile: every interior tileset here already names its `table` and
  `counter` tiles for the unrelated purpose of extruding them to the right
  height, and that list answers "is there a tabletop here" for free. So a
  mug lands on a table in a house nobody wrote a line of code about.

  Gen 1 draws no sleeping pose for anything, so the sleeper stands in its
  ordinary art and the Zs over its head are what say it is asleep -- three
  bars in a Z rather than a font glyph, because the font's own characters
  are black-with-alpha and a pale mark on a dark floor is not something
  `setColor` can make out of one. The sleeper is a real object and stands
  in the room in both modes; the steam and the Zs are drawn into the
  diorama's overlay, so those two want the VOXEL camera on.

  On Gen 1's own twenty-six houses this lands ten sleepers -- 38%, which is
  the number `tests/weather_life_probe.lua` reports and the number the odds
  constant was tuned against rather than assumed from.

### Changed

- **`Water.SPARKLE` is now `Water.sparkleNow()`** at the one place the
  scene shader reads it, so the weather can take the glint out of the pond
  on the tick a shower starts. `Water.wet` and `DayNight.overcast` are
  plain fields the weather pushes into rather than values those files pull,
  which is what keeps the dependency pointing one way: Weather asks them
  what the hour and the water are doing, and neither has to know Weather
  exists.

- **The WEATHER row starts a fresh spell whenever it changes.** A pin holds
  its shower open with no clock at all, so arriving back on AUTO with that
  spell still in place left rain whose timer could not run out and whose
  target nothing would lower -- permanent rain, from a row saying AUTO.
  Choosing AUTO now means "you decide from here", which is also what a
  player expects it to mean.

- **`DayTint` claims the frame for a neutral hour when it is raining.** A
  clear midday multiplies by white and is skipped entirely, which is why a
  game with the clock at DAY issues not one extra call -- but rain at noon
  wants that same instant between the world blit and the UI blit, so the
  frame is now claimed at a tint of white (a multiply that changes no
  pixel) whenever there is something falling.

## 1.9.0-mobile.qol.1

### Added

- **QOL, a new row: three mercies in one switch.**

  **Effectiveness markers on the move menu.** Every damaging move on the
  FIGHT list carries a one-character verdict against the Pokemon actually
  standing there: a green `+` where it hits super effective, a grey `-`
  where it is resisted, a red `x` where it cannot touch. Computed from the
  same TypeChart the damage formula reads, so the hint can never disagree
  with the number; drawn flush after each name, and the longest Gen 1 move
  name lands its marker exactly on the box's last interior column, so
  nothing can ever touch the border. The unnamed ghost in the Pokemon
  Tower keeps its mystery -- hinting "your Normal moves cannot touch it"
  is the Silph Scope's reveal, and it is not answered early. The official
  games took until 2019 to ship this.

  **Auto-repel.** When a Repel is one step from wearing off and the bag
  holds another, it is used -- weakest first, so the cheap ones are burned
  before the MAX the player is saving -- through the engine's own
  ItemEffects and Bag, so the step counter and the slot bookkeeping are
  exactly a player's. A text box says so; while the auto-farm bot owns the
  controls the fact goes to the log instead, because a box would stop the
  bot dead waiting for an A press.

  **HMs on the A button.** Press A at a cuttable tree and CUT happens;
  press A facing water and SURF mounts; press A at a boulder and STRENGTH
  wakes up -- no menu, no party list, no submenu. Every gate the party
  menu applies still applies: the badge, the move in the party, and the
  engine's own side-effect-free checks (useCutFieldMove /
  useSurfFieldMove), so nothing can happen here that the menu would have
  refused -- only the walk through it is skipped. Deliberately
  conservative about what an A press MEANS: anything standing at the
  facing cell always wins, tall grass is excluded from auto-CUT (A in a
  meadow is for talking to what this mod stands in it), and while already
  surfing the button keeps its vanilla meaning entirely.

  OFF is the full 1996 friction, and the row exists because a purist
  should get to keep it.

- **The auto-farm drinks from the bag.** Below half health the bot uses a
  potion -- weakest first, one sip per beat, through the engine's own
  ItemEffects so the heal cap, the sound and the Pikachu-happiness bump
  are a player's own -- until the trained Pokemon is topped back up. It
  stops (and switches its row OFF) only when HP is critical AND the bag
  has nothing left to give, which makes the farm genuinely AFK: buy a
  stack of potions, pick a slot, walk away.

## 1.8.0-mobile.water.1

### Changed

- **The water is cel-shaded.** It was geometry that moved and art that did
  not say so: the swell displaced the surface and a soft sparkle brushed
  the crests, and between the two the pond still read as the flat tile
  gently breathing. Three additions, all analytic, all keyed off varyings
  the mesh already carried, and all FLAT-SHADED on purpose -- this is a
  four-colour world on a pixel grid, and a smooth gradient over it reads
  as an airbrush. Every boundary is a hard step, softened only by the
  checkerboard dither the 8-bit sky already established as this mod's
  idiom for "between two colours".

  **Bands.** The surface is cut into flat bands of brightness by the
  swell's own height: a crest is a shade lighter, a trough a shade deeper,
  and both thresholds are dithered on the checker -- so the bands breathe
  with the interference pattern of the two wave trains and read as
  cel-shaded water rather than as three painted stripes. Multiplies only:
  the tile's own art, the hour's tint and every palette mode keep their
  colours, just banded.

  **A toon glint.** The crest-catches-the-sun sparkle was a smoothstep --
  a sheen. It is now snapped to three hard rings, because a cel highlight
  is a SHAPE. Same analytic normal, same glint window, same travel with
  the wave that carries it; it just has edges now.

  **Foam.** A white line breaks against every bank, lapping back and forth
  on the tide's own clock, its edge dissolving through the checker so it
  reads as drawn pixels rather than a painted rim. The trick is that it
  costs no new data at all: on a shoreline lip face the vWater varying
  interpolates from 1 at the bottom edge -- which is attached to the water
  and moves with the swell -- to 0 at the bank, so the band of high values
  IS the waterline contact, and the foam rides the tide for free.

  FLAT on the WATER row still means the old still plane, untouched -- the
  whole block gates on the swell being live, exactly as the sparkle did.
  Staged battles beside a pond get all of it unasked, because the arena
  renders through the same shader.

## 1.7.1-mobile.color.1

### Fixed

- **Roamers and street Pokemon were black-and-white under the RED++ colour
  pack.** RED++ assigns object palettes by a sprite's own ROM table index
  (PaletteFX.spriteObp reads it out of the def's `source`), and a sheet the
  ROM never had has no honest index to claim -- so the resolver answered
  nil and the one colour mode whose whole point is that nothing on screen
  stays grey drew every wild roamer and every town stray in raw DMG shades.

  The honest answer was never the index, it was the SPECIES: the ROM
  assigns every Pokemon a mon palette of its own, the RED++ pack carries
  that table (it is what colours the battle pics), and a baked overworld
  sheet knows exactly which species it is. So the def carries the species
  now, and a wrap on PaletteFX.spriteObp -- answering only after the
  engine's own resolution declined, only for this mod's own sheets --
  resolves the mode from PaletteFX.monPal: the same species -> palette
  lookup the battle screen uses, through the same darkObp dark-cave
  permutation every other OBJ palette gets. A Pikachu in the grass is
  YELLOWMON for exactly the reason its battle pic is; a Zubat in Rock
  Tunnel is BLUEMON, and darkened until Flash like everything around it.
  Every other colour mode is untouched: the zone shader was already
  colouring these sheets correctly there, and those paths read neither
  field.

## 1.7.0-mobile.city.1

### Added

- **TOWN, a new row: Pokemon in the streets.** A town in Gen 1 is the
  emptiest place in the game -- no encounter table, no grass, a handful of
  scripted NPCs walking two-cell beats. This puts trainers' Pokemon out in
  it: strays and companions loose in the streets, wearing their own baked
  overworld art (the WILD row's sheets), wandering the same walk every NPC
  walks, culled by battles and frozen by dialogue like any cast member.

  Two kinds, told apart by how they act when you come close. **Pacifists**
  -- most of them -- are just out for a stroll: press A and one turns,
  cries its own cry, and a line of flavour text says what it is doing out
  here. You cannot fight what does not want to fight. **Challengers** --
  about one in three -- STARE: walk within a few cells and one stops dead
  and turns to face you, and keeps facing you, the trainer-sight stare
  worn by the Pokemon instead. Press A and it asks for the match; accept
  and it is the engine's own wild battle at your own lead's level (worth
  the stop, never a wall -- winnable XP on maps that never had any),
  refuse and it goes back to its stroll.

  Where this runs is decided by one test rather than a list: outdoors,
  and the encounter records roll no grass here -- which is exactly the
  towns and cities. A route keeps its wild grass and gets nothing;
  Viridian Forest is a dungeon; indoors is indoors. The companion species
  pools are filtered against the loaded dataset at spawn time, so a total
  conversion without a MEOWTH simply rolls fewer names.

- **Civilian NPCs glance at you.** Walk within a couple of cells of
  someone and they turn to look, the way anyone would; walk on and a
  standing NPC turns back to the facing their map def gave them -- a
  shopkeeper glances up from the counter, then goes back to minding it.
  The guard is the point: an NPC with a `trainerClass` is NEVER touched,
  because a trainer's facing IS their line of sight and turning one would
  start (or dodge) fights the map never rolled. Wanderers keep whatever
  facing their next step picks; scripts freeze NPCs and frozen NPCs are
  left alone. Works on the flat 2D world too -- a turned head is a
  facing, and facings draw in every mode.

- **Two more kinds of ambient life, and one of them reacts to you.**
  SPARROWS hop about the open ground by day, pecking at nothing -- until
  the player comes within a couple of cells, when they startle and fly
  off. The startle is the whole point: ambience that reacts to you is the
  difference between a diorama and a terrarium. DRAGONFLIES dart over the
  water -- a hover, a dash to a new spot, another hover, with wings that
  shimmer rather than flap, because real ones beat too fast to see and a
  flicker of alpha is the truth. Butterfly and firefly caps raised a
  notch (6 and 12) now that the population spreads across more kinds.

## 1.6.0-mobile.farm.1

### Added

- **A-FARM, a new row: pick a Pokemon and a bot trains it.** The row names a
  party slot; while it is set, a bot drives the game the way a very patient
  player would. On the map it walks the wild ground -- tall grass on a route,
  the whole floor of a cave -- and with the WILD row on it HUNTS: the nearest
  roamer standing in the grass is walked into, which is the same bump that
  starts the fight for a player. In a fight it always picks the strongest
  move against what it is actually facing (power, STAB, the type chart,
  accuracy -- with Explosion, Dream Eater on something awake and the
  charge-turn moves discounted for what they are), and runs from a wild
  fight it is losing.

  **The learn-a-move prompt is answered by VALUE.** When a fifth move
  arrives, the new move and the four known ones are scored -- damage output
  for attacks, a curated worth for status moves, redundant same-type
  coverage discounted -- and the lowest-value move is the one forgotten,
  unless that would be the new move itself, in which case it is declined.
  So Thundershock is forgotten for Thunder, Growl is forgotten for Agility,
  Tail Whip is declined outright, and Thunderbolt is never lost to anything.
  HM moves are never forgotten, exactly as the engine forbids. The verdict
  lands through MoveLearnMenu's own finish, so the "1, 2 and... Poof!"
  text, the onDone chain and the stack are exactly as a player's answer
  leaves them.

  The chosen Pokemon is swapped to the front of the party first -- Gen 1
  gives its experience to the Pokemon that fought, and the lead is the one
  sent out -- and the row follows the swap, so the menu never lies about
  which slot is being trained. The bot stops ITSELF, and sets its own row
  OFF, rather than grind a party into the ground: when the trained
  Pokemon's HP falls low, when it faints, when its damaging moves run out
  of PP, when the map has nothing to farm, or when the local wild Pokemon
  are immune to everything it knows. It never throws a ball, never uses an
  item, and a Safari fight is immediately run from.

  Every button it presses goes through the engine's own front door: the
  `input.step` hook Game:step runs for exactly this class of mod, with
  synthetic presses on the same Input queue the engine's tests and drivers
  write -- promoted to real one-step edges, consumed by the same wasPressed
  every menu reads. Riding the logic step also means the bot farms
  correctly under fast-forward.

- **AMBIENT, a new row: the diorama is inhabited.** Butterflies wander the
  tall grass by day, a few cells from where they hatched, on a sine-bob
  flutter. Fireflies drift over the same grass through dusk and the night,
  BLINKING -- drawn additive, points of light the night actually receives.
  A small flock of birds crosses the sky every half minute, high over the
  roofs, gone off the far edge -- and not under Viridian Forest's canopy,
  because there is no sky there to cross. And while the WIND row blows,
  leaves are torn loose and carried on the same gust the grass is bending
  under, drifting harder the harder it blows. None of it is a game object:
  nothing stands in a cell, joins the cast or can be bumped -- a critter is
  a dot with a clock, simulated in world coordinates and projected through
  the same camera the terrain is, with its height honest, so a bird
  crossing at forty world pixels is projected AT forty world pixels.

### Fixed

- **The RTX row's AO collapsed into spokes on mobile.** The AO ring is
  turned by a per-pixel hash, and the hash was the classic
  `fract(sin(dot(uv, ...)) * 43758.5453)` -- which is broken at mediump,
  the fragment-shader default on GLSL ES: the big multiply amplifies a
  10-bit mantissa's rounding into bands, so neighbouring pixels got the
  SAME turn and the ring degenerated back into the eight fixed spokes it
  exists to hide. Replaced with interleaved gradient noise over the pixel
  grid, whose constants survive mediump -- and whose blue-noise-ish
  spectrum is the better dither anyway. Same fix, same reasoning, same
  driver class as 1.2.1's sky bands.

- **The light shafts read past the edge of the frame.** The march toward
  the sun sampled the depth texture beyond [0,1], where a clamped texture
  repeats its edge texel forever -- so a building against the frame's rim
  threw its blockage across every beam that marched past it, and a sun
  just off the top of the frame (exactly when the beams reach furthest,
  which is why the disc is allowed off frame at all) was shaded by
  whatever happened to sit on the top row. Off the frame nothing is
  recorded, and toward the sun the honest guess for nothing is open sky.

- **The shafts banded in rings around the disc.** Fourteen fixed steps land
  every pixel's samples on the same fourteen rings. The march now starts a
  random fraction of one step in (the same IGN hash), trading the rings for
  noise the pixel grid absorbs.

- **AO's falloff never actually let go.** The stated rule -- "the wall you
  are standing against shades you, the building across the street does
  not" -- was only half true: the falloff forgave with distance but never
  reached zero, so a wall three ranges out still kept a quarter of its
  weight, which read as a grey wash between buildings that face each
  other. A hard cutoff at twice AO_RANGE makes the sentence true.

### Changed

- **Water reflections land where they should.** The SSR march's quadratic
  spacing is what buys its 900-pixel reach, and it is also a staircase:
  out where steps are fifty pixels apart, every reflected edge landed on
  whichever step overshot it, so a reflected tree came back as a column of
  slabs. On a hit, four bisections between the last miss and the hit walk
  the overshoot back in -- sixteen times the contact precision for four
  extra fetches, spent only on pixels that actually reflect something.

## 1.5.0-mobile.wild.1

### Added

- **WILD, a new row: wild Pokemon you can SEE.** Gen 1's wild encounter is a
  dice roll on a step -- every completed step in tall grass draws
  `rand(0..255)` against the map's encounter rate, and when it comes up the
  screen wipes and something you never saw is suddenly in front of you.
  Nothing about that is a decision. You cannot pick a fight, avoid one, choose
  which one, or know there was one to choose: the grass is a slot machine you
  pull by walking.

  This makes the roll VISIBLE. The same encounter table, rolled the same way
  against the same ten cumulative buckets, decides who is standing in the
  grass RIGHT NOW -- as ordinary map objects, wearing their own art, wandering
  their own patch -- and the fight starts when you walk into one, or press A
  at one. So the grass becomes a place with things in it: go round the Zubat,
  go after the Abra, or cross the route without fighting anything at all.

  Three rungs. **ROAM** stands them in the grass and switches the blind roll
  off, so what you fight is what you walked into. **MIX** stands them in the
  grass and leaves the roll on as well, so the grass can still surprise you.
  **OFF** is the dice alone, exactly as the game has always rolled them.

  Where they stand is the same three cases OverworldState:onStepComplete rolls
  for, read off the same records so nothing gets a wild Pokemon that could not
  produce one by walking: grass on a route, the whole floor of a cave or a
  tower, and the water -- the last only while surfing, because a Tentacool
  bobbing across a pond that cannot be reached is set dressing with a sprite
  card's price on it.

  What is deliberately NOT changed is anything that decides WHAT a wild
  Pokemon is. The species, the levels and the slot odds are the ROM's, read
  through the same data the roll reads. REPEL still works, and reads better
  for being seen: nothing weaker than the lead appears at all, so the grass is
  visibly empty of the small stuff while it lasts. And a battle that starts
  here is the engine's own wild battle, pushed down the engine's own
  pushBattle -- so the transition, the Safari menu, the catch, the experience
  and this mod's own staged arena all happen without knowing where the fight
  came from.

  Two places keep their dice on purpose. The POKEMON TOWER without the Silph
  Scope, because a ghost battle is a wild battle the game refuses to NAME
  until the player holds the Scope, and a Gastly wandering about in plain
  sight with its own art answers the question that whole floor exists to ask;
  pick the Scope up and it populates like anywhere else. And any map this
  cannot cover at all -- no encounter table, no room to stand anything on, or
  art that would not bake. The suppression is answered per TERRAIN and only
  ever for ground something has actually been stood on, so the blind roll
  stays switched on exactly where nothing has replaced it. The one thing worse
  than a blind encounter is no encounter.

- **W-COUNT**, how many stand within reach at once: SOME, FEW or MANY. Each is
  one more sprite card in the frame, which is why FEW exists. Only on the
  OPTIONS menu while WILD is on -- the number of them is zero either way with
  the feature off, and a row that no longer decides anything is worse than no
  row.

- **An overworld sheet per species, baked from the art the game already
  ships.** Gen 1 draws no Pokemon on the map: eleven species have an overworld
  sheet because a script stands one somewhere, and the other hundred and forty
  have exactly one drawing each, which is the battle front pic. So that is
  what a roamer wears -- resampled to the 16x16 cell every other character on
  the map occupies, folded onto the three shades a Game Boy OBJ can actually
  show (colour 0 is transparent in hardware, which is why every overworld
  sheet in this game is drawn in 170/85/0 and nothing lighter), and with the
  outline given a low bar in the vote because at this size the outline is most
  of what makes a mon recognisable. A species' own pic buffer decides how big
  it stands, so a Caterpie is smaller than a Snorlax on the map for the same
  reason it is in a battle.

  Baked to a real file at a real path, under the engine's own derived-asset
  root, and that is the whole reason it is a file rather than a canvas: a
  sheet at a PATH is a sprite the ENGINE understands. SpriteRenderer loads it,
  the OBP bake recolours it, the SGB zone shader colours it out of the map's
  own palette, tall grass overdraws its feet, the voxel pass cuts its card
  from it and the sun pass throws its silhouette -- every one of those keyed
  on the image path, and not one of them needing to be taught about this. The
  filename carries a revision, so a change to the generator supersedes an
  older bake rather than being mistaken for it.

  The one mode that does not reach it is the RED++ colour pack, which assigns
  object palettes by a sprite's own ROM table index; there is no honest index
  to claim for a sheet the ROM never had, so under that one mode a roamer
  stays in DMG shades while its neighbours are recoloured. Every other mode,
  the default included, colours it like any NPC.

  Better art wins outright: a 16x96 sheet shipped at
  `assets/roamers/<SPECIES>.png` is used as-is and nothing is generated.

### Changed

- The mod now declares the `filesystem` permission, because it writes those
  sheets.

## 1.4.0-mobile.rtx.1

### Added

- **RTX, a new row: fake ray tracing over the depth buffer the 3D pass already
  filled.** Nothing here traces the world -- there is no acceleration
  structure, no second scene and no extra geometry. There is one image of the
  diorama and one record of how far away each of its pixels is, and every
  effect on the row is a question answered by walking a straight line across
  that record and reading what it hits. Which is why it costs texture fetches
  rather than triangles: the world is drawn exactly once either way.

  Three rungs, because the three questions cost very different amounts.

  **AO** asks how much of the sky a point can actually see. Eight neighbours
  in a ring, each asked whether it stands on the positive side of that point's
  own surface plane -- which is to say, in the way of the hemisphere it would
  otherwise see. Where many do, the point is in a corner: the inside of a
  doorway, the foot of a wall, the gap between two trees. It is the cheapest
  thing on the row and the one that does most per millisecond, because it is
  what makes a diorama read as built out of solid objects rather than
  assembled out of stickers.

  **RT** adds a real reflection on the water. The ray leaves the surface along
  the swell's OWN analytic normal -- recomputed here from the same two
  crossing wave trains the vertex shader displaced the geometry by, so it
  agrees with the surface to the last bit -- and is marched across the depth
  buffer until it lands on something, which is then read straight out of the
  colour buffer. So a pond reflects the tree standing beside it, what it
  reflects is whatever is actually there rather than a painted-in guess, and
  the reflection TRAVELS with the crest carrying it. A Fresnel term decides how
  much of it shows, which lines up with the camera ladder for free: 15 degrees
  is a pond seen from above and mostly its own water, 75 is a pond seen along
  the surface and mostly the far bank.

  **MAX** adds light shafts. Every pixel marches toward the sun's own disc --
  the same one the sky already hangs, projected through the same camera -- and
  counts how much of that line is open air. A clear run gets the whole beam, a
  roof in the way gets none, and the boundary between them is a god ray.

  Two limits come with the technique rather than with this implementation of
  it, and both are worth knowing rather than being surprised by. It can only
  reflect or shade WHAT IS ON SCREEN: a reflected ray that leaves the frame
  fills in with the sky rather than with the bank it would have hit. And it
  needs a driver that can hand back a readable depth canvas -- where one
  cannot, the row still cycles and nothing happens, exactly like every other
  capability this mod asks for.

  **OFF** allocates nothing. The scene pass attaches the plain write-only
  depth buffer it always attached, no second texture is ever made, and the
  frame is byte-for-byte the one it was.

  The pass runs INSIDE the scene's own begin/end pair, at the resolution the
  scene was rasterised at rather than the one it is presented at. Both of
  those are deliberate. The depth buffer stops existing the moment that pair
  hands the colour canvas back, so a worldPresent pipeline could not be given
  one; and at RES 1/2 what leaves is an upscale, so marching a ray across it
  would be paying four times over to walk through detail that was never
  rendered. It also means the overworld battle gets the whole row for nothing:
  the arena renders through the same pair into a slot of its own, and the pass
  follows the slot.

- **SHADOWS SOFT, a fourth rung above HIGH: shadow edges that widen with
  distance from what throws them.** A sun is a disc rather than a point, so the
  further a receiver stands from its blocker the wider the band that can see
  part of that disc and not the rest -- which is why a lamp post has a crisp
  shadow at its foot and a woolly one at its far end, and why one fixed edge
  width never quite reads as sunlight.

  Same family as the row above, and the same trick: the sun's depth record is
  a heightfield, so "how far away is what is blocking me" is answered by
  reading it rather than by knowing anything about the scene. Four taps over a
  wide ring find the blocker, the gap between blocker and receiver sizes the
  penumbra, and eight taps on a disc filter at that width. Twelve fetches
  against HIGH's four.

  The conversion from a depth gap to a filter width is worked out in
  `ShadowMap.softness` rather than in the shader, because all three terms in it
  -- the frustum's own depth, the rung's texel size and the sun's apparent
  size -- live there and none of them is visible from inside a fragment.

- `Mat4.invert`, which is what lets a canvas pixel and its stored depth become
  the world point that wrote them. Gauss-Jordan with partial pivoting rather
  than a closed-form adjugate: it runs once per frame, so the elimination's
  cost buys nothing, and sixteen transcribed cofactor expressions are exactly
  the sort of thing that comes out silently transposed in a file whose layout
  convention is row-major.

### Changed

- The RES ladder now reads 1/2 -> FULL -> 1/3 -> 1/4. Same rungs and the same
  default; FULL is simply one press away rather than three, which is where
  most desktop players are going.

### Fixed

- Nothing here was broken before, but one thing is worth writing down for
  whoever writes the next shader in this mod: **the shading language this
  engine compiles for does not take a backslash line continuation.** A
  multi-line preprocessor macro will not build at all, and it fails with
  `'line continuation' : not supported` followed by a spurious
  `missing #endif`. Every tap loop added in this release is a function for
  that reason.

## 1.3.0

### Added

- **BACK SPRITES, a new row under 3D-BTL: your own Pokémon stays on the battle menu.**
  The staged shot stands both mons on the map, which is the mode's whole claim
  -- and it costs the framing Gen 1 is most recognisable by: your own Pokémon,
  seen from behind, sitting on top of the battle menu with its feet on the box.

  With BACK SPRITES on the foe is still geometry standing on its own tile at the far
  end of the arena, and the player's side goes back to being the GB's own flat
  back pic in the GB's own slot: same art, same 2x, same feet on row 96. It is
  the engine's own pics layer that draws it, through the `onlySide` argument
  that layer already takes, so every pic effect -- the grow-out-of-the-ball,
  the faint slide, the damage blink, the send-out trainer pic -- comes along
  unchanged and none of it is reimplemented.

  Nothing else about the shot moves. The arena, the camera and the drift are
  solved exactly as they were, so the foe stands where it always stood and the
  player's cell is simply empty ground in the foreground. Two things follow the
  setting: the `pokemon.sprite` hook stops asking for the front pic on the
  player's side (it is a back view again, and the front art would be that mon
  turned round to face the player it belongs to), and the move-animation offset
  drops that side's contribution, because a pic that has not moved cannot have
  moved the pair's centre.

  OFF by default -- what the mode advertises is the two of them out there --
  and only on the OPTIONS menu while 3D-BTL is on, since with staged battles
  off the engine already draws exactly this.

### Fixed

- **Battle pics were see-through, and it took a back sprite on a tiled floor
  to make it obvious.** Gen 1 pics are two-bit art whose lightest shade is
  white, and the decoded PNGs key that shade to alpha 0 -- which cost nothing
  when the field behind them was white too. Over a route, every belly, every
  eye white and every highlight is a hole with the world showing through, and
  the mon reads as a stencil.

  `BattlePics` exists to put that paper back and, as written, put none of it
  back. It flood-filled the outside from the border and filled what the flood
  could not reach, which is exact and, on this game's art, empty: a Gen 1
  figure is an open drawing, and its belly walks out to the border through the
  gap between its legs. Read across all 305 of the game's battle pics, that
  rule finds an enclosed hole in exactly none of them.

  The fix is to start the flood somewhere else: at the edges of the ARTWORK'S
  OWN BOUNDING BOX, and at three of them -- left, right and top. The bottom is
  closed, because it is not a side the background is behind, it is where the
  drawing was CUT. A pic is bottom-aligned in its slot with all the margin at
  the top, so a mon's lowest row is the last row it was given and everything
  below the belly simply stops. Treat that cut as open and the background
  pours up inside the figure, which is the channel of world that used to show
  through a Clefairy.

  That is exact rather than a heuristic: nothing is filled because of what
  surrounds it, only because the background provably cannot reach it. Which is
  why it needs no idea whether it is holding a front pic or a back one -- the
  sky between a pair of ears reaches the top edge and stays sky, the gap
  between a body and a raised tail reaches the side and stays gap, the belly
  reaches neither and is paper. The silhouette is untouched, so the mon still
  cuts cleanly against the world.

  It replaces the border flood outright rather than sitting beside it, since
  anything the border could not reach the box edges cannot reach either.

  The bottom edge needs one more distinction, because two different things
  meet the underside of a figure. A DRAIN is where the drawing ran out -- a
  belly whose white carries on down until the artist stopped, leaking out
  through the inch between a body and a leg -- and is sealed. A MOUTH is the
  space between two legs, background that happens to be enclosed on three
  sides, and is left open so the world shows through a trainer's stride.

  Width tells them apart, and on this game's art it is not a close call.
  Measured along the bottom of every battle pic, the drains run 3 and 4 pixels
  (Clefairy's back, Wartortle's back, Red's back) and the mouths run 10, 12, 14
  and 17 (a Rattata's underbelly, Blue's stride, Brock's, a Pikachu's back).
  Nothing lands between 4 and 10, so the cut is taken at 6 with room either
  side rather than tuned to one sprite. Apart from that number the rule stays
  exact.

  Front pics come back untouched, and not by being special-cased: they are
  near-solid silhouettes with almost nothing inside them to fill, so their own
  shape is what says so.

  Both mons were affected -- the cards in the arena as much as anything -- so
  this lands wherever a battle pic is drawn over the world, not just under
  BACK SPRITES.

- **The pinned back pic was lit at noon while the world behind it was not.**
  Everything standing in the arena goes through the voxel shader, and that
  shader multiplies by the hour's tint, so at dusk the diorama warms and at
  night it goes blue -- the two mons' cards included, because they are drawn
  in the same pass as the ground they stand on. A back pic pinned to the menu
  is not in that pass; it is a flat blit over the finished shot, and it stayed
  bright over a midnight route.

  The same tint is now applied to that one draw, by multiplying every colour
  the pics layer sets on its way past -- so the alpha, the faint slide's fade
  and the damage blink all compose with it instead of being overwritten. What
  it does not get is the sun: the cards are shadow-mapped and a pic pinned to
  the menu has no position in the scene to be shadowed at, so it carries the
  hour and not the weather.

### Added

- **The hour reaches the FLAT world too, not just the diorama.** DAYTIME drove
  the 3D pass through the voxel shader's own tint uniform -- a uniform the 2D
  tile path never runs -- so with VOXEL off, the same evening that fell on the
  diorama left the flat world at permanent noon. One clock, two worlds, one of
  them ignoring it. Outdoor maps now get the same multiply, painted as one
  rectangle over the composited world.

  The whole difficulty is WHERE, and it is worth writing down. Not on the world
  canvas: in a colorized mode that canvas is grayscale art and the blit that
  puts it on screen runs it through the palette shader, which classifies each
  pixel into a shade BY ITS RED CHANNEL -- multiply a night blue over it first
  and every pixel lands in the wrong bucket, so the world does not darken, it
  changes colour. Not over the finished frame either, or the dialog boxes and
  menus darken along with the world they are held up in front of, which is the
  same reason the tilt-shift blur is a `worldPresent` and not a `present`.

  Which leaves the instant between the world blit and the UI blit, and the
  engine has no seam there -- `worldPresent` only runs when a PIPELINE produced
  the world, which in flat mode is precisely what did not happen. So
  `Renderer:endFrame` is wrapped and the UI canvas's own draw is watched for:
  `blit` passes the canvas it is compositing as the first argument, so the
  first draw of `Renderer.canvas` IS the boundary, by identity rather than by
  counting. The shader and scissor that call arrives under belong to the UI
  blit already in progress, so both are put aside for the rectangle and handed
  straight back.

  Skipped entirely when a pipeline drew the frame (it tinted itself, and twice
  is wrong), indoors (a room has no sky to take its light from), and at midday
  (a multiply by white) -- so a game with the clock at DAY issues not one extra
  call.

### Changed

- **FULL no longer takes the two battle rows off the menu.** It still owns the
  rows that describe the LOOK -- the wireframe, the horizon bend, the blur, the
  hour -- because it is a preset for the diorama and a row that no longer
  decides anything is worse than no row. 3D-BTL and BACK SPRITES are not that:
  one decides what a fight is drawn OVER and the other how it is framed.
  FULL still SETS both on arrival; it does not hold them, and leaving them
  reachable is the difference between a preset and a lock.

  This makes `stagedBattles()` honest as a side effect. It used to answer yes
  under FULL as well, on the grounds that FULL owned the 3D-BTL row and
  switched it on -- safe only while the row was hidden. With the row reachable
  from inside FULL, that clause would have claimed staged battles for a preset
  the player had just switched them off inside, pinning BATTLE LAYOUT to OG for
  a fight that never gets staged. The row is the only thing that decides now,
  which is what `OverworldBattle.begin` and `wantsFront` already believed.

- **TILT and GBC FX are off the OPTIONS menu entirely while this mod is
  installed.** Both fight the diorama and both were already half-taken: the
  mode's own key forces them off on every press, and the registry switches
  TILT off whenever a world pipeline takes the pass. What was left was two
  rows a player could set and watch get reverted -- TILT being the flat fake
  of what this mode does for real, and GBC FX a full-screen present pass over
  the top of the whole thing.

  Dropped AND held at zero, which is the part that matters: hiding a live
  setting is a trap, because a save written before the mod was installed can
  carry TILT 3 and a row that is not there cannot turn it back off. Pinned
  wherever the value could arrive from -- the menu opening, a save being
  loaded or begun -- so there is no route by which either is on and
  unreachable. Uninstalling the mod puts both rows back, at whatever they were
  last set to.

- **The battle's text box and menus are frosted glass, like the HUDs.** The
  HUD blocks got panels because black glyphs on grass are not readable. The box
  at the bottom had the opposite problem and the same cause: it is drawn as an
  opaque white slab with a black border, which was the field's own colour back
  when the field was white and is a sheet of paper laid over the bottom third
  of the diorama now that it is not.

  It gets exactly what the HUDs get -- the world behind it, blurred to frosted
  glass and laid back down translucent, at the same frost and the same tint --
  and it is measured into the same brightness verdict, so the ink over the menu
  flips white with the ink over the HUDs rather than against it. Only the FILL
  is taken away: the border, the text, the cursor and the down arrow are the
  engine's own glyphs in their own places. The move menu's TYPE/PP box and
  Mimic's copy menu get their own panels, trimmed to the rows above the box
  below them so no pixel is frosted twice.

## 1.2.1

### Fixed

- **On Android the sky went black below its first couple of bands.** A hard-edged
  band of black ran from partway down the gradient to the horizon point, with the
  moon still hanging correctly inside it. Desktop was unaffected.

  What gave it away is that the same colour reached the screen by two routes and
  only one of them was wrong. The haze filling the void UNDER the horizon is the
  sky's palest band, and it is delivered by `love.graphics.clear` -- it landed
  correctly. The bottom of the sky above it is that same band delivered by the
  shader, and it was black. So the palette was not reaching the fragment shader,
  and nothing was wrong with the palette, the layout or the camera.

  The bands went in as `uniform vec3 bands[8]`, filled from Lua and read through
  a loop counter, and on Android's GLSL ES the tail of that array arrived as
  zero -- which is black. The likeliest reason is the fragment uniform budget:
  ES 2.0 only guarantees sixteen uniform VECTORS, and eight band slots plus the
  twilight glow plus LOVE's own built-ins is over it. A driver that truncates a
  partly-filled array, or one that reflects `bands[0]` and nothing after it,
  fails identically -- so the fix removes the whole class rather than the one
  cause.

  The bands are a one-texel-per-band TEXTURE now, sampled nearest, with the
  band index clamped against the ramp's width. One texture unit replaces eight
  uniform vectors, there is no array to index and no budget to overrun, and a
  sample past the last band lands on the last band instead of on nothing. It is
  still a palette and not a picture -- one texel per band on a single row -- so
  the sky is still computed per pixel at the size it is displayed at, with
  nothing resampled and nothing baked.

  Also gone with it: `clamp(x, 0.0, 0.999999)`, which rounds its bound to 1.0 at
  mediump -- the fragment default on GLSL ES -- and would have indexed one past
  the last band on the sky's bottom row for the same black result.

## 1.1.1

### Fixed

- A move that shakes the screen no longer whites out the frame. The zone pass
  fills each zone with its blank colour before drawing the shifted copy -- the
  hardware showing empty BG in the strip the shake vacated -- and a shake
  program alternates offset and no-offset frames, so over the map that read as
  the whole battle screen, menu box included, flashing white a few times a
  second. The fill is dropped while a battle is staged on the map; the shake
  itself still moves the HUD.

## 1.2.0

### Added

- **A gradient sky behind the diorama, on every `VOXEL` rung.** The void behind
  the world used to be a black plate at every rung but the top, where it became
  one flat blue -- enough while that void was a sliver, and a wall of paint once
  the horizon came into frame.

  It is the 8-bit skybox recipe now: four blues painted as flat horizontal bands,
  deepest overhead and palest at the bottom, with a CHECKERBOARD of the next band
  dithered into the bottom 40% of each one. Alternating two colours on a pixel
  grid is how a machine with four to a palette got a fifth, sixth and seventh out
  of them, and it is what keeps four bands reading as a gradient rather than as
  four stripes. Every channel of the palette is a multiple of 8 -- where a
  five-bit GBC channel lands -- so no colour in it is one the hardware could not
  have shown. No clouds, nothing moving.

  Where the bands END is the camera's own answer. At `75` the ground plane's
  vanishing line is genuinely in frame -- projected through the same matrix the
  geometry is drawn with -- and the pale end meets it. At the steeper rungs that
  line is above the top edge, and what shows up there is the ground running OUT
  past the map edge instead, so the bands take a fixed slice of the frame and the
  haze fills the rest. One sky across the whole ladder either way.

  **Nothing is resampled**, which is why it is drawn the way it is: no baked
  160x144 image scaled up to the window, no downsized buffer blown back up, no
  texture at all. One rectangle through a shader answers every pixel from its own
  canvas coordinate, so a pixel of sky is computed at the size it is displayed
  at and there is nothing for a filter to soften. The band edges and the dither
  cells are measured in the pass's own pixels-per-world-pixel, handed in fresh
  every frame -- so a `ZOOM` keypress is reflected in the frame that follows it,
  with nothing cached at the old scale, and the sky's grid is the same grid the
  world's own texels sit on.

  The palette goes through the display-mode transform like every other palette in
  this mod, so GRAY gets four greys and CLASSIC four greens. Below the bands the
  void is filled with the palest of them -- which is also what the bottom band
  ends on -- so the join has no seam, and a driver that cannot compile the shader
  gets flat bands and a logged line rather than a wrong sky.

  The overworld only. A battle is a staged shot whose placed camera has the
  horizon above the frame, so the arena keeps exactly the flat sky it had.

- **A day/night cycle**, on a new **DAYTIME** options row: `DAY`, `NIGHT`,
  `DUSK`, `DAWN`, `SYNC`, `CYCLE`. One twenty-minute clock underneath all of
  them -- ten minutes of sun, ten of moon -- where the four named settings
  are PINS on that dial (noon, mid-night, sunset, sunrise), `CYCLE` lets it
  run, picking up from whichever pin or SYNC sky the player was just looking
  at, and `SYNC` -- the DEFAULT -- lays the machine's own clock onto the
  dial: local noon is the DAY pin, midnight is NIGHT, six and eighteen the
  twilights, an hour of the real day is fifty seconds of dial. Everything is
  a pure function of the clock, so the pinned DUSK is exactly the running
  cycle stopped at sunset. While **VOXEL** sits on `FULL` the DAYTIME row is
  HELD at `SYNC` and taken off the menu with the other rows the preset owns
  (DayNight.forceSync, enforced from the preset, the rows hook and the
  manager's options_changed -- the same three places BATTLE LAYOUT's pin
  lives): the full diorama runs on the real sky.

  **The sun and the moon are in the sky**, and their positions are honest:
  the disc is the light's own direction projected through the same matrix the
  geometry is drawn with, so it stands over the point on the horizon its
  shadows point away from, at every pitch, window shape and zoom. The sun's
  noon is this mod's existing sun to the digit -- southeast, 45 degrees up,
  overhead behind the north-facing camera and correctly out of frame -- and
  its arc swings north at both ends, so the disc stands IN frame through dawn
  and dusk, rising half-set on the horizon. The moon arcs the northern sky
  all night, due north (screen centre) at mid-night, with scaled crater
  cells. Both are cell art on the sky's own dither grid, sized by the frame
  (a celestial body's apparent size is an angle, so zooming the ground does
  not swell it), and both are SCISSORED to the sky's region: the horizon
  point is where a setting body disappears -- it never hangs under the map.

  **The sky follows the clock.** Phase palettes -- the daytime blues,
  gold-to-violet dawn, a hotter gold-to-indigo dusk, moonlit navy -- six
  bands each now, blended along the dial and re-quantised onto the 5-bit
  lattice, so every mixed frame is still a colour the hardware could show.
  The blends bend through designed WAYPOINTS rather than straight across --
  a golden hour on the way into dusk, a violet civil twilight either side of
  the night -- because day's blue and dusk's gold are near-complements, and
  a straight lerp between complements bottoms out in dishwater grey. Through the twilights a posterised, checker-dithered GLOW
  warms the bands around the low sun -- painted light, not an airbrush. The
  blends are 75 seconds wide either side of each twilight and the pins land
  on their phase palette unmixed.

  **The shadows follow the sun and the moon.** The shear every shadow is
  thrown by (direction opposite the body's bearing, length its elevation's
  cotangent, clamped at twice the caster's height) comes off the clock, the
  shadow map's signature carries it, and the light's press fades out over the
  last twelve degrees before the horizon -- so sunset hands off to moonrise
  through a soft shadowless gap, and moonlight presses at about two-thirds
  the sun's weight. The scene shader also multiplies every surface by the
  hour's tint: neutral at noon, warm at the twilights, dim blue at night.

  **Outdoors only**, by the same `Map.isOutdoor` test the sky already rests
  on: indoors keeps the noon rig, the neutral tint and no sky -- a cave at
  midnight is exactly as dark as a cave at noon. Viridian Forest is the case
  between, a CANOPY map (DayNight.CANOPY): there is no sky to paint and no
  sun to see, so the shadow rig stays the mod's fixed noon light -- all that
  ever filtered through the leaves -- but night still FALLS in a forest, so
  of everything the clock does, exactly one thing reaches it: the hour's
  tint, in free-roam and staged battles alike. A battle staged on an
  outdoor map fights under the hour: the night sky behind the arena, the
  tint on the mons, the sunset taking the arena's shadows with it; an indoor
  arena is untouched. The engine's own `world.tod` hook is answered
  (`MORNING`/`DAY`/`EVENING`/`NIGHT`), so palette or music packs keyed to the
  period ride this clock for free.

  **The clock rides the save slot.** On the engine's `save.writing` event the
  cycle's time is written into the mod's own save-file bucket
  (`save.modData.DRAMATIC_SHAPE`), and read back when a save is opened. A
  save with no clock in it starts at day.

- **Window glass.** The panes in the overworld art -- the framed squares on
  building fronts, the small lights in doors -- are found by SHAPE in the
  tileset image (a black border row, four or five black-flanked glass rows,
  a closing border), at pixel granularity because the door's pane straddles
  a 2x2 tile block. No tile ids are hardcoded: a conversion that draws its
  own windows in the same idiom gets glass for free. The scan yields a mask
  texture aligned to the tileset atlas, which the scene shader samples with
  the same coordinates the terrain does -- so the effect lands on any wall,
  at any angle, in free-roam and staged battles alike, with no geometry
  work.

  By day a thin glint crosses the panes WHILE THE VIEW MOVES: the sweep's
  phase is fed by the camera's own travel and its strength fades out within
  a beat of standing still -- a reflection is something the viewpoint does,
  so still camera means still glass. The sweep pattern lives in the pane's
  OWN texels, not the screen's: a screen-anchored pattern has the world
  sliding through it at zoom speed whenever the camera pans, which strobed
  (worst walking against the sweep); anchored to the glass, panning moves
  nothing and a step advances the glint a fraction of a texel, the same in
  every direction. It lifts the texels toward sky-white and leaves the
  shine art visible through it. The mask is consulted only by meshes
  textured from the tileset atlas (Voxel3D.glass), never by sprite sheets,
  whose coordinates would land on the panes' atlas positions by accident.
  After dark the panes are LIT: the texel's own pattern carried into a warm
  lamp colour, replacing the shaded answer entirely -- a lit window ignores
  the sun, every shadow and the hour's tint, exactly as a window with a lamp
  behind it does. The lamps follow the clock (DayNight.windowLight): on
  through dusk, full all night, mostly out by dawn, and never lit indoors.

- **A fade out of a battle, where there used to be a hard cut.** The engine
  wipes INTO a fight with one of the original's eight transitions and cuts
  straight out of it: `BattleState:finish` pops itself and the map is simply
  there on the next frame. Between a white field and a tile map the original got
  away with that; between a placed camera looking across an arena and a diorama
  looking down on a walking player it reads as a glitch. The battle now fades to
  black, closes behind it, and the map fades up out of it -- twelve frames each
  way, registered as a `voxel_battle_exit` transitions record so the timing is
  retunable in data like the wipes it answers.

  Only while voxel mode is on, and then for EVERY battle, including one that
  found no arena and drew on the flat battle screen: what is being smoothed over
  is the return to the map, and the map is a diorama either way. With the mode
  off, the vanilla cut is untouched.

  One black rectangle over the FINISHED composite does the fading, so the world,
  the letterbox bars and the battle's own text box all darken by the same amount
  -- the renderer's existing warp-fade overlay is painted between the world and
  the UI, which would have left the text box bright over the black. A blackout's
  own warp fade or an evolution prompt still owns the way out when it takes the
  screen: the fade stops at the cut rather than fading in over the top of it.

- **A `FULL` rung on the VOXEL row**, directly after `OFF`. One choice that
  puts the whole mode in its intended state -- the 35-degree camera, the
  miniature blur at maximum, the horizon flat, the view fitted, and battles
  on the map -- rather than making a player assemble it from four rows.

  While it is selected, every row it owns comes OFF the menu: V-GRID,
  V-CURVE, 3D-BTL and T-SHIFT. A row that no longer decides anything is
  worse than no row. Stepping onto or off `FULL` rebuilds the open menu in
  place, so the rows leave and return under the cursor instead of waiting
  for the menu to be reopened.

  It applies its settings when the row ARRIVES at `FULL`, not every frame:
  holding them would make the zoom keys and the wheel dead while it was on.
  Leaving it deliberately undoes nothing -- reverting would discard whatever
  had been changed since.

### Fixed

- **The hit flash whited out the whole screen.** The engine draws it as a
  full-screen white rectangle, which is a flash on a white battle field and
  a whiteout of the map, the HUD and the text box over a world. It is now
  dropped on the way past and put back where it was ever about: the two
  Pokemon go solid white for those frames, silhouette and all, and nothing
  else in the frame moves.

- **A scripted battle cut straight in with no transition** (an ENGINE seam,
  fixed in `src/script/Commands.lua` rather than in this mod): the rival in
  Oak's lab, and every `start_battle` script, pushed the BattleState bare --
  no flash, no wipe, the theme starting late -- where the original wipes
  into scripted fights like any other. `start_battle` now routes through the
  overworld's own `pushBattle`, which is also the path this mod wraps, so a
  scripted fight gets its arena staged and the cast culled BEFORE the wipe
  instead of catching up behind it. A battle scripted with no overworld
  under it still starts bare, and no music plays twice (BattleState's own
  start is a same-song no-op).

- **A standing figure's shadow detached from its feet under a low sun.** The
  shadow compare forgives `slack` world pixels so lit ground does not acne
  against its own texels, and that same forgiveness lit the first `slack` of
  every cast shadow -- so the shadow started a bias-width away from the feet,
  further the lower the sun reached (the classic peter-panning, invisible at
  the old fixed 45 degrees and plain at a day/night golden hour or under the
  moon). Sprite cards -- characters, authored figures, flowers, battle mons
  -- are now drawn into the shadow map snugged TOWARD the sun along their
  own ray (`ShadowMap.snug`): moving along the ray changes nothing about
  where a shadow falls, but storing the card shallower takes three quarters
  of the forgiveness back for the shadow it throws -- and for nothing else:
  no terrain moved, so the acne margin is untouched where it matters. The
  obligation that comes with it: every snugged caster's LIT draw hands the
  same snugged transform to its own shadow lookup (Voxel3D.draw's
  `sunModel`), so stored and lookup agree exactly and the compare keeps its
  full margin -- read un-snugged, the missing nine tenths showed up as
  diagonal moire bands crawling across every sprite. The shadow root lands
  back under the feet at every hour.

### Changed

- **Under `VOID FILL: TREES` the border wall is modelled trees or nothing.**
  Only the first block past the map body gets carved into round trunks and
  canopies; the two blocks past that were too far out to be worth the quads,
  so they fell through to the mesher's plain box and came out as a flat-topped
  slab of tree ART sitting beside the modelled forest -- a painted-on plateau,
  and the more obvious the lower the camera got. Rather than pay to carve
  hulls nobody walks near, the wall now simply STOPS where the carving does:
  `Structures` does not build the ring past that distance (the same "nothing
  out there" `BLACK` already produces), and the mesher drops any cell inside
  it the 2x2 canopy grouping could not claim, so no strip of boxes survives at
  a corner. `WATER` and every indoor border are untouched -- a flat sheet of
  water is what water looks like from above anyway.

- **The two HP boxes snap to the window's edges during a staged battle.** The
  battle screen is 160x144 in the middle of the window and the world is the
  whole of it, which left both HUD blocks huddled together in the middle of the
  frame with map showing on either side of them -- a Game Boy screenshot pasted
  over a diorama rather than the diorama's own furniture. The foe's block now
  sits against the left edge and the player's against the right, on the same
  frosted glass, with the same tiles at the same size on the same rows. The
  pokeball rows and the safari ball count travel with the block whose rows they
  share. On a window shaped like the GB screen there is nowhere to go and
  nothing moves.

  The engine draws them into the 160x144 canvas, which clips at its own edges,
  so the layer is rendered to a texture and composited into the world image --
  the one surface here that covers the whole window. A driver that cannot do
  that falls back to the HUD in the frame rather than to no HUD.

- **`BATTLE LAYOUT` is pinned to `OG` while battles are staged on the map**, and
  the row comes off the OPTIONS menu with the rows `FULL` owns. The staged shot
  is composed in the GB's own frame -- the arena camera is solved to put a cell
  under each pic's feet, and the HUD rects and the intercepted background fill
  are measured there too -- and `WIDE` re-lays that screen out on a 304x144
  surface, moving every one of them. Set rather than worked around, on every
  route in: the options row, hotkey `8`, the mod manager's page, `FULL`'s
  preset, and a save that arrived with `WIDE` already on. Switching `3D-BTL`
  off hands the row back with `WIDE` selectable again.

- **Hotkey `3` walks the angle rungs only and steps over `FULL`.** The key is
  a display-mode cycler -- it should change the camera and nothing else --
  and `FULL` reaches in and rewrites four other settings. Landing on it
  mid-walk would silently push the blur to maximum and flatten the horizon
  with nothing on screen saying a keypress had done it. `FULL` stays on the
  OPTIONS row, where a preset that changes other rows belongs.

  A press FROM `FULL` goes to `50`. `FULL` is already the 35-degree camera,
  so stepping to the rung of that name would look like the key had done
  nothing. Matched by angle, so it follows `FULL` if that is ever retuned.

- **The mode's four options are one block in the menu.** The engine splices
  a pipeline row in beside TILT and lands a mod's own rows at the end of the
  list, which had these four in two places with unrelated engine rows
  between them. The settings now follow the pipeline rows directly.

## 1.1.0

### Added

- **Battles happen on the map you were standing on.** The battle screen's
  white field is replaced by the world: the mod finds the nearest patch of
  open ground, points a placed over-the-shoulder camera at it, and draws the
  fight over that. New **3D-BTL** row and hotkey `8`, on by default.

  The arena is a 3x6 clearing of cells the player could walk on, with the
  two mons three cells apart down the middle column and a one-cell apron all
  round so the camera looks across floor rather than into a wall. Where no
  map has room for that -- a corridor, a cave, a shop -- the search relaxes
  to a 1x4 corridor with the apron given up, and where even that will not
  fit the battle draws exactly as it always did.

  Everything else in the frame is the engine's own. The mon pics, HUDs, HP
  bars, move animations, faint slides and text box are drawn by BattleState,
  in its order, at its coordinates -- the GB's own layout, with the player's
  mon low and left and the enemy's high and right, which is why the camera
  is placed east of the arena axis rather than the layout being moved to
  suit the camera. What changes is what is behind them.

  Three things carry the shot. The overworld's cast is culled before the
  wipe, so it plays over an empty map and no bystander is standing in the
  arena. The camera drifts on a slow orbit about a point between the two
  mons, which moves the near ground and the far ground by different amounts
  -- parallax, not a sliding backdrop. And a depth-of-field pass holds the
  band of frame the two mons stand in sharp and softens the middle distance
  and the foreground; both mons are in focus by construction, because they
  are drawn as the battle screen's own pics after the pass has run.

  **Nobody moves.** The arena is where the CAMERA goes. Nothing here writes
  a cell, a facing, a flag or a warp, so a trainer's post-battle dialogue is
  still talking to someone standing in front of them, and the blackout path,
  sight lines and every script find the player exactly where they left them.

  The two HUD blocks gain the backing the white field used to be. Gen 1
  draws them as black glyphs straight onto the background with no box round
  them, and black-on-grass is not readable; the backing is painted inside
  `drawHUDs`, so it lands in the same target and takes the same zone colour
  as the HUD it sits under, in both the colorized and flat pipelines.

  Declines cleanly at every step it cannot take: no depth support, no open
  ground, the row switched off, or a terrain mesh still building all end at
  the battle screen the engine has always drawn.

### Changed

- **Characters are flat sprite billboards, and nothing about a sprite is
  voxelized any more.** Every figure -- the player, NPCs, the ghosts
  standing on a neighbour map -- is now its current 2D frame on a single
  flat quad, with the shader's alpha discard cutting the exact silhouette
  out of it. It still faces south and leans back by the camera's pitch,
  so it reads face-on at every tilt exactly as before.

  Two things went away with that. The contoured slab, which gave each row
  a thickness measured from the sheet's own side view; and the carved
  visual-hull models (`lib/VoxelModels.lua`, `tools/build_voxels.py`, and
  ~70 generated files under `assets/voxels/`, 2 MB), which reconstructed
  a figure from its three drawn views.

  A sprite is a DRAWING, not an object seen from one side. Gen 1's
  overworld figures are 16x16 icons with a fixed front-on reading, and
  turning one into a solid invents a body the artist never drew and the
  game never implied. The shipped models were also the one place this mod
  carried a description of the ROM art -- a carve is a faithful record of
  a sprite's silhouette, pixel for pixel -- which sat badly against a mod
  that otherwise ships no game data at all.

  The flat card is cheaper on every axis: no pixel access (only the
  sheet's dimensions), one quad instead of hundreds of faces, and one
  mesh shared by the solid draw, the sun pass and the player's occlusion
  silhouette. That sharing is load-bearing rather than tidy -- the
  silhouette draws with the depth test inverted, and any self-overlap in
  the mesh would read as "behind something" and repaint the figure on
  open ground.

  A mod can still ship `overrides/voxels/<name>.lua`; that path is
  unchanged and still wins where it exists.

## 1.0.6

### Added

- **Conditional pins.** A profile entry may now carry `when_above`:
  tile id -> rules keyed on the tile drawn directly north of it,
  resolved per POSITION in `TileShape.at`. A pin is per tile id and one
  graphic can mean two things -- the route gates' `$32` is both the
  wall's dark base course and every service counter's front, and it is
  the bottom row of its cell either way. Pinned `wall` the counters
  stood a full 16px; pinned `counter` the deep wall banks corrugated
  16/8 for sixteen rows and the room read as crates. What separates the
  two uses is what sits on top, so that is what the rule reads. The
  gates now have half-height counters AND level walls.

- **The Pokemon Tower has an exterior.** It is the one catalogued
  building drawing the map edge cuts off (no roof band is on the map at
  all), and it had no `buildings` entry, so it fell to the volume path
  -- which tops a run by repeating its first two rows, laying window
  courses flat across the plateau. Sealing the silhouette on the north
  alone closes it (88% fill, one piece, against 37% and 126 pieces
  unsealed), and one row of roof band spent on the drawing's top margin
  costs no window course. It stands as a real tower, panes recessed,
  door on the ground.

- **The Indigo Plateau statues stand up**, built exactly like the gym
  statues: plinth a solid 16px block, figure a per-pixel cutout riding
  it. On the avenue the statues stack with no gap, so the flood joined
  six of them into one 24-row region and the volume builder raised
  ridges of boxes with the statue art folded on the front. The same
  bird is drawn at the foot of every badge-check pillar, so those are
  crowned too.

### Fixed

- **Tall grass: one clump per tile.** Each 8x8 tile is a whole clump,
  but the template split every tile AGAIN into its top and bottom four
  art rows and stood those at two different depths -- so any blade
  running down a tile was cut in half, into two 4px stubs 4px apart.
  One tile is now one full-height standing slab at its own depth; a
  cell's 2x2 tiles still stand independently, so the player walks
  between the north and south rows.

- **Ledge lines are continuous.** `$34` is the cliff slope's foot and
  also the pillar between hop-down segments; pinned `wall` with the
  rest of the slope chain (the Diglett's Cave fix) it stood those
  pillars 16px beside a 6px lip. At ledge height the run reads as one
  lip, and the mound is unchanged -- its foot row reads as the talus it
  is drawn as.

- **A prop only stands on furniture when its own cell is blocked.**
  "Is something drawn above me" is not "am I standing on it": a chair
  drawn against the north side of a table is above the table's trim row
  too, and was being lifted onto the tabletop, with its claimed cells
  re-tiled as tabletop so the table marched two rows north. Three
  chairs in Cinnabar's trade room and Fuchsia's meeting room, and the
  Celadon diner's stools. The world already knows the difference: a
  thing that sits ON furniture occupies a blocked cell, a seat you walk
  up to is in a walkable one.

- **Caves: nothing below sea level, and the water is water.** Two tiles
  were identified backwards in the first pass. `$14` -- the tile the
  engine animates, that `Map.WATER_TILES` names and that Surf runs on
  -- was pinned `wall`, so Cerulean Cave's lake and the Seafoam sea
  stood up as rock slabs. And the pale dithered rock fill was pinned
  `water`, cutting 612 tiles of two-cell-wide trench through four maps.
  Both corrected; a sweep of all 19 cave maps now reports zero tiles
  below the datum. The elevation scheme is documented in the entry and
  derived from the game's own `tilePairs`: dark floor, water and drop
  holes at 0, the lit shelf a 6px step above, rock at 16.

- **Cave ladders climb.** Which ladder graphic goes up and which goes
  down is unanimous in the warp table -- 37 cells of one always warp
  down, 40 of the other always up -- so they are real stepped flights
  now, not painted plates.

- **Poke Mart's register stands on the counter.** The pin was on the
  wrong tile: `$08` is the counter's own top band, not the register, so
  the standee flood ate everything but two black lines. The register is
  the keypad-and-receipt drawing one row up.

- **Celadon's televisions**, which were solid 16px boxes wearing the TV
  art on one face, and the **Pokemon Tower reception desk** and the
  **gate counters**, which stood at wall height, are all their drawn
  heights now. The **Fan Club and Silph boardroom statues** were read
  as seated chairmen and painted onto the tabletop; they are cutouts
  standing on their pedestals, and the tables are cut to a true
  octagonal footprint.

## 1.0.5

### Added

- **Every remaining interior is furnished.** The profile covered ten
  tilesets; it now covers twenty-three -- 1,190 pinned tiles across
  `GATE`, `FOREST_GATE`, `LOBBY`, `MUSEUM`, `LAB`, `MANSION`,
  `INTERIOR`, `CLUB`, `SHIP`, `SHIP_PORT`, `FACILITY`, `CEMETERY` and
  `UNDERGROUND`, plus full entries for `CAVERN` and `GYM` which had only
  stubs. Roughly 130 maps, surveyed against the standard the finished
  interiors already set: one 16px wall band carrying whatever is drawn
  built into it, half-cell counters so the drawn front folds up and the
  top stays on top, `bookcase` collapse for free-standing shelves,
  thin-pool standees for plants, and small objects riding the furniture
  they are drawn above.

  What the detector was doing before, by way of what changed:

  - **Rooms with no walls.** Three tile ids (`$14`, `$32`, `$48`) are
    claimed by the engine's water set in EVERY tileset, and collision is
    per CELL, so one of them in a cell's bottom-left corner sank the
    whole cell. `$32` draws both the route gates' wall base course and
    every counter front, so all 25 gate maps were a checkered floor in a
    moat; the same trap put ponds through two thirds of Seafoam B4F,
    under every museum vitrine, along the S.S. Anne's wall corners and
    across Silph Co 1F's lobby island. The set is wider than three ids
    in practice -- `LAB`, `MANSION` and `INTERIOR` each hit six to nine
    -- because the test is per cell, so an innocent tile sharing a cell
    with a trapped one sinks with it and has to be pinned too.
  - **Towers and fused monoliths.** Counters raised to 48px dragging
    their wall band with them, merchandise racks fused sideways into
    32px blocks four tiles deep, cave shelf edges standing as 48px fins
    beside a 16px band, the Vermilion liner folded upright into a lumpy
    48px slab.
  - **Furniture that was not there at all.** Anything whose cell is
    walkable resolved to flat ground: 59 department-store stools, every
    gate lounge table and pair of binoculars, both museum staircases,
    the gym-lounge chairs, and -- via the void rule -- the black
    partition walls every gym is divided by, which left their white rim
    columns standing as hollow 48px fins.
  - **314 gravestones** in Pokemon Tower were 8px stubs, because the
    volume path measured only their bottom row and dropped the arch.

  Notable readings: the S.S. Anne's hull is `roof` (a drawing seen from
  above, so the art belongs on the top face); the Warden's specimens and
  Celadon Gym's shrubs are `cylinder` voxel balls, the first indoor use
  of that class; the Fan Club's octagonal boardroom table is `counter`
  rather than `table`, because only a counter rides its upper rows onto
  the top face in drawn order -- which is what draws the seated chairman
  exactly once, the Pokemon Center couch case verbatim.

  Fuchsia Gym's invisible maze is deliberately left flat. Raising it
  would read better as a room, and would also hand the player the
  solution; a shape is purely presentational, so the drawn answer wins
  and the gym plays as the flat game does.

### Fixed

- **A profile pin now outranks the door fold.** `Structures.forMap`
  folds a door cell into its facade so the doorway does not punch a hole
  in the wall -- but it overwrote the resolved shape unconditionally,
  including for AUTHORED tiles, which contradicts rule 1 of the
  documented resolution order. Any pin on a tile its tileset also lists
  in `doorTiles` was dead on arrival: all four Celadon Mansion
  staircases and Pokemon Mansion 3F's descent are door tiles, so
  `stair_*` pins there silently did nothing and the flights stayed
  painted flat on the floor. The fold now skips authored tiles.

## 1.0.4

### Added

- **Viridian Forest grows real trees.** Nearly everything drawn in the
  forest is ROUND, and the detector was boxing all of it: the big trees
  came out as ragged mixed-height volumes (their sparse canopy-rim
  tiles read 0px against 32px bodies, leaving gap-toothed hedge walls),
  the stump rows merged into 16px crate walls wearing folded stump art,
  and the trail signs were broken piles -- their $32 tile is the
  water-fallback trap and recessed into a pond lip in the middle of the
  woods. All of it is now profile-pinned to the treatments the rest of
  the world already uses: every tile of the tree drawing (ball, rim
  wisps, feet) and the stumps take the per-cell voxel HULL the overworld
  border forest wears -- a tree spans 2x2 cells, so its four
  quarter-hulls tile into one big lumpy canopy, and each stump becomes a
  round bollard; the signs take the standing thin-slab `signpost`
  treatment every town sign gets; and the white sparkle filler inside
  the tree masses is flat ground instead of an invisible zero-height
  box. The whole map now resolves to hulls, signs, ledges and ground --
  a detector sweep finds no stray boxed column anywhere.

  Two refinements over the first cut, both new hull-builder abilities.
  A tree's drawing spans 2x2 CELLS, and per-cell hulls unfolded it onto
  the ground -- the ball's top half sat one cell north of its bottom
  half at the same elevation, reading as a tree cut in half. The new
  `canopy` class pins the drawing's corner tile as a group anchor and
  the whole 2x2-cell drawing carves as ONE 32px hull, so every tree is
  a single tall round canopy (the carver is now parametric over its
  canvas size, and hull stamps carry their footprint radius). And the
  stumps' drawn tops are a CUT FACE -- an ellipse of growth rings seen
  at an angle, not body: the new `stump` class builds the hull from the
  bark rows alone and projects the ellipse across the round flat top,
  near arc to the south (`stump_cap` names the ellipse's drawn height),
  so the rings ride the round part in perspective.

- **Flowers stand up, and keep swaying.** The animated meadow tile
  ($03, the one tile the overworld animates by frame rewrite) now
  renders as a billboard one voxel deep: the drawing's darkest tones
  plus everything they enclose are cut out per pixel, and the ground
  beneath is synthesized from the commonest flat neighbour, exactly
  like the ground under a detected prop.

  The interesting part is that the cutout still animates. A mesh is
  static, so the geometry spans the UNION of the mask over the base art
  and all three animation frames, and the animation lives entirely in
  the texture: TerrainAtlas already rewrites the flower's slot in the
  private animated atlas each step, and for this tile it now writes
  only the current frame's mask opaque with everything else keyed to
  alpha 0 -- which the voxel shader discards, and the shadow pass with
  it. The standing silhouette trims itself frame by frame in texture
  space, off the same engine clock as the flat path, without a vertex
  moving. The class is derived, not authored: any frames-animated tile
  resolves to the new `flower` class with no profile entry, the same
  way tall grass derives from `grassTile` (hand-authoring still wins).

- **The cuttable bush is a standing cutout.** The four tiles Cut
  deletes ($2D/$2E/$3D/$3E -- across the whole tileset they appear only
  in the five cut-tree blocks) are pinned to the thin `prop` pool: a
  per-pixel standee 5 voxels deep, black-outline segmented with its
  enclosed pixels kept, the drawn grass dither flooding away. It
  stands on plain grass ($2C) -- the very tile Cut leaves behind per
  field.cutTreeSwaps -- via the profile's new `prop_ground` key, which
  names the tile painted under a pinned prop instead of whatever flat
  tile its neighbours vote in.

- **Gym statues: a solid plinth, a standing bird.** The statue pair
  flanking every badge gym's aisle (and Bruno's room) is one cell of
  figure over one cell of plinth. The plinth ($22/$23/$32/$33) is
  pinned `wall`: a solid 16px block. The figure ($02/$38/$12/$13) is
  pinned `prop`: a 5-voxel cutout that stands ON the plinth through the
  authored-box support rule, its checkered background flooded away and
  the pixels its outline encloses kept.

  The whole statue keeps ONE cell of footprint. The support rule used
  to extend the box under the claimed cell (the monitor-on-desk path),
  which marched the plinth a second block backwards; a figure whose
  support is a FULL-HEIGHT block now collapses instead -- the drawn
  figure cell becomes synthesized floor, since the block below already
  carries the whole base. Furniture supports keep the extension: their
  drawn cell is the furniture's own upper rows, and floor there would
  amputate the desk. The round boulder drawn beside some statues is
  deliberately NOT pinned -- it also tiles wall-to-wall as Pewter's
  rock rows, which are scenery for the detector.

- **Lt. Surge's trash cans stand up.** The can ($0B/$0C/$1B/$1C, the
  lone graphic of blocks 38/39) takes the same treatment as the
  cuttable bush: a 5-voxel `prop` cutout, black-outline segmented with
  its enclosed pixels kept, standing on the gyms' main floor tile
  ($11) via `prop_ground`.

- **The Poke Marts furnished to the Center's standard.** The MART
  tileset shares the Center's atlas image but is its own id, so none
  of the Center's pins applied, and every mart was raw detector
  output: a 32px double-height display band for a back wall, the two
  shelf racks fused into one four-tile-deep monolith, and the clerk's
  booth towered into a 48px slab wearing the juice poster. Pinned the
  way the finished interiors are -- the back wall's SALE cases and
  drink fridges one 16px face like the Center's healing consoles, the
  racks collapsed to one-cell-deep shelves at drawn height like Red's
  bookcases, the counter half a cell with the poster riding its top
  like the nurse's tray, and the cash register standing ON the counter
  through the authored-box support rule. One 4x4 layout serves every
  city, so this covers all eight marts.

### Fixed

- **Cut trees now vanish in voxel mode -- and grow back.** The
  engine's Cut path swapped the block with a raw `setBlock` + renderer
  rebuild, never emitting `world.block_replaced` -- so this mod's
  listener (which rebuilds the map's mesh exactly for this) never
  heard about it, and the diorama kept showing the tree. The engine
  now routes Cut through `replaceBlock`
  (src/world/OverworldController.lua), whose whole purpose -- per its
  own comment, "Victory Road barriers, Cut trees" -- is that same swap
  plus the event. The regrowth path had the same hole one door away:
  cut trees are restored block by block when the map is re-entered,
  and the card-key doors are stamped closed on floor load, both
  through the same silent `setBlock` -- with the mesh cache staying
  warm across a round trip (that is what prevLive is for), the world
  kept showing the stump you left. Both paths now announce each block.

- **A block edit no longer blinks the world down to 2D.** The
  listener used to drop the edited map's mesh outright, and mesh
  builds are asynchronous -- so cutting a tree (or stepping out of a
  door onto a map whose trees just regrew) flashed the flat 2D world
  for the frames the rebuild took. `ChunkMesher.refresh` rebuilds in
  place instead: the stale mesh keeps drawing, the replacement cooks
  in the background, and each slot swaps as its build lands -- the
  tree pops out (or back in) with the scene never leaving 3D.

- **Flowers cull the player correctly from every angle.** The flower
  billboards were baked into the terrain mesh, which draws without
  the characters' camera-ward pull -- so a walker standing among
  flowers won the depth test against ALL of them, including the
  flower south of their feet that should overdraw them. The flower
  quads now ride their own mesh, drawn after the characters with
  exactly the characters' pull (the tall-grass trick): the flower in
  front of a walker occludes their feet, the one behind them hides,
  at every camera angle. Unlike grass the flower mesh still casts
  shadows -- it is a handful of cutouts per meadow, not thousands of
  tufts.

- The `voxel_anim_probe` driver crashed on engine builds without the
  optional `TileRenderer.animFrame` seam, and again on tilesets whose
  animation list carries a "toggle" entry (spinner rooms), which claims
  a tile LIST rather than one slot. It now reads the clock through the
  mod's own fallback chain and skips toggle entries in the placement
  census.

- **The shoreline no longer opens into the sky beside buildings and
  signs.** Water recesses 2px below the ground, and the ground tile beside
  it closes the step with a small below-ground side band -- but a tile
  CLAIMED by a standing object (a building footprint, a sign standee, the
  bushes ringing Fuchsia's ponds) only painted its synthesized flat ground
  and never emitted sides. Along every stretch where such a tile met
  water, the two-pixel step was an open slit straight through to the sky
  behind the mesh. The skip branch now emits the same below-ground bands
  ordinary ground does, cut from the synthesized ground's own art, so the
  shoreline lip is continuous whatever stands on the bank.

- **Edge-row buildings keep their facades.** The south wall of Saffron's
  row houses -- profiled buildings whose front row is the map's last tile
  row -- lies exactly on the boundary plane shared with Route 6, and the
  prebuilt-quad keep rules dropped it: the strict body test excludes the
  plane, and the closed neighbour mask (which exists to kill ring scraps
  whose rects sit exactly on that line) swallowed what was left, so from
  Route 6 the houses stood hollow. The two cases are geometrically
  identical degenerate rects, but they FACE opposite ways: a face pointing
  away from the body is this map's own facade and nothing in the
  neighbour will ever draw that plane, while a face pointing into the
  body is the scrap the mask is for. The mesher now reads the winding and
  keeps outward faces on the body's boundary planes, on all four edges.

  The roof RIM had the same problem one step further out: an edge-row
  house's eave overhangs `frontEave` voxels PAST the boundary plane into
  the neighbour's airspace, and those quads are neither on the plane
  (the winding rescue) nor over the body -- the neighbour-body mask ate
  them as ring scraps, so from across the seam the roof edge was open
  sky at low camera angles. Building placements only ever scan the map
  BODY, so every building quad is this map's own structure by
  construction: they now carry an `own` flag the edge keep-rules never
  touch.

- **Diglett's Cave mounds (and cliffs everywhere) stop sprouting
  towers.** Two detector misreadings stacked up on the cave-entrance
  mound. The dark east slope of the cliff drawing ($02/$24/$34) is one
  texture repeated over the mound's whole height, but its corner tiles
  break the repeat scan, so those columns rose to 32px -- the rock
  pillar beside the entrance. And a folded doorway column reads its own
  drawn extent (the door plus everything above it), which is a house's
  real height when the door is a house's, but a 32px tower over a 16px
  plateau when the door is a cave mouth -- the entrance jumped a block
  above the mound around it. The slope chain is now profile-pinned to
  one 16px course, and a doorway column answers to its REGION entirely:
  height from the region's dominant column, top flat when those columns
  are flat repeats (the mound) and roofed when they are drawn facades
  (a house). Both cave entrances -- and every cliff built from the same
  slope tiles -- now read as one level mesa with the cave mouth at
  ground level. A new `voxel_mound_probe` driver prints the detector's
  per-column class and height over any rectangle, which is how this was
  diagnosed.

  Routes 3 and 4 had a third variant of the same misreading: the repeat
  scan anchors at a column's FRONT tile, and a plateau column that ends
  in a one-off rounded corner tile ($13/$35) never matched -- it read
  its whole capped extent and shot up as a 48px fin (several together
  made a tent). When the two rows directly above the front are
  identical, the column is now read as that repeat wearing a trim foot:
  its unit is one course plus the trim. Doorway columns still answer to
  their region first, so houses are untouched.

## 1.0.3

### Added

- **The player shows through whatever hides them.** Occlusion in this mode is
  the real thing -- walk north of Red's house and the roof is genuinely in
  front of you -- but a player who cannot see their own character has lost
  track of where they are standing, which the flat game never allowed. The
  figure now draws a second time as a translucent silhouette wherever the
  world is in front of it.

  No code anywhere asks whether the player is occluded: the depth buffer
  already knows, and the test is the question. The silhouette is drawn with
  the depth compare INVERTED -- `greater` where the scene uses `lequal` --
  so it appears exactly where the ordinary draw would have lost, and nothing
  at all is drawn when nothing is in the way. LOVE hands the compare straight
  to `glDepthFunc`, so the two are true complements with no seam between
  them.

  It goes down BEFORE the characters, so the only thing it can meet in the
  depth buffer is the world -- terrain, buildings, trees. Drawn after the
  solid pass it would meet the player's own card instead, and every fragment
  of a figure sits behind the one that just wrote it, so it would paint over
  the player permanently. Characters then draw on top as usual.

  It uses the FLAT card (`SpriteBillboards.shadowQuad`), not the relief slab
  the solid pass draws. The slab carries front and back faces and the mode
  culls neither, so with the test inverted its own back faces -- a few voxels
  deeper than the front ones that just won -- read as "behind something", and
  the figure repaints itself on open ground whether or not anything is in
  front of it. One quad has no self-overlap, which is exactly why the shadow
  pass already uses this mesh, and it cannot double-blend into a mottled
  patch either. A silhouette is an outline, so the outline is the right mesh.

  Depth writes are off: the pass is behind the scenery by definition, and
  writing would file the hidden figure in front of the building hiding it,
  which the grass pass at the end of the frame reads. The card carries the
  same transform and the same camera-ward pull as the solid draw (both now
  come from one shared `billboardMatrix`/`billboardPull`, so they cannot
  drift), which is what keeps the leaning-over-a-near-wall case out of it:
  pull already won that fight for the solid draw, so a character merely
  standing close to a wall does not shimmer a silhouette over it.

  It is drawn as ONE flat translucent grey, not as a dimmed copy of the
  sprite. Tinting through the vertex colour could only MULTIPLY the sprite's
  own pixels, which darkens each one by its own amount and keeps all the
  character's internal detail -- a murky picture of Red rather than a shape.
  So the fragment shader carries a `ghost` / `ghostColor` pair and replaces
  the colour outright, last in the chain so neither the sun nor a voxel seam
  can mottle it. Staying translucent is what keeps it reading as "behind
  that wall" rather than as a hole punched through it.

  `Voxel3D.GHOST_COLOR` and `GHOST_ALPHA` (0.5) are the knobs. Only the
  player gets this -- NPCs and the ghosts standing on a neighbouring map are
  left to honest occlusion, because it is only your own character you cannot
  afford to lose behind a roof.

## 1.0.2

### Fixed

- On Android the diorama drew into the top-left corner at a fraction of the
  screen -- about a third of the width and height on a 420dpi panel -- with
  the field effects (dust, emotes, the cut-tree shudder) correspondingly
  oversized against the world they sat on. Desktop was unaffected.

  The pipeline ctx hands over `width`/`height` measured in LOVE UNITS
  (`love.graphics.getDimensions`), but the engine composites a pipeline's
  returned canvas with `draw(canvas, 0, 0, 0, 1/dpiX, 1/dpiY)` -- a scale
  that only covers the window if the canvas is at PIXEL resolution. Sizing
  the scene canvas from the ctx therefore paid the DPI scale twice: the
  canvas came out that much smaller, and was then drawn that much smaller
  again. On desktop the two units are the same number and nothing shows;
  Android's DPI scale is the display density (2.625 at 420dpi), so that is
  where it surfaced.

  The scene canvas is now sized from `love.graphics.getPixelDimensions`
  directly rather than from the ctx. That is the number a fixed engine would
  hand over, so this does not double-correct if the ctx is ever changed to
  agree with the compositor. It also squares the FX pass for free:
  `ctx.scale` was ALREADY in pixels per world pixel (`Zoom.scale` over
  `Renderer:fitScale`, which measures the drawable), so the closures were
  being scaled for a canvas 2.6x bigger than the one they were drawing into
  -- one wrong number, not two.

## 1.0.1

### Fixed

- The RED++ texture-readback fallback in `TerrainAtlas` never worked on real
  drivers: LOVE refuses `Canvas:newImageData` while that canvas is currently
  active, and `readback()` read the pixels back before restoring the previous
  render target, so the call threw on every driver rather than only on
  stubborn ones. The previous target is now put back BEFORE the read. The
  headless suite could not see this -- its stub canvas does not enforce the
  rule -- so it survived until a live probe ran the chain unguarded.

  Harmless for vanilla tilesets, where the CPU rebuild (`gbcPixels`) answers
  first and the fallback is never consulted; it was the last-resort route for
  a map the palette pack does not know, which until now had no working route
  at all.

## 1.0.0

First release, ported from the engine-internal voxel branch onto the
`render_pipelines` mod API.

Interior furniture gets the shapes it depicts
(mods/DRAMATIC_SHAPE/tools/voxel-survey.md is the procedure that found and
verified these).

Buildings stop being boxes wearing their own elevation. A profiled
building is voxelized from its own sprite, band by band -- the pipeline
written up in `assets/docs/buidling_to_voxel/`.

Terrain meshing goes asynchronous, instanced and bounded. The first voxel
frame used to build every neighbourhood map synchronously (a ~2.4s
freeze), retain every map's analysis forever (gigabytes over a
cross-region trek), and string stray pixels along map seams.

Real shadows. The sun moves to the southeast and drops to 45 degrees, so
shadows fall northwest -- up and to the left on screen -- and run about as
long as the thing throwing them is tall.

### Added

- `voxel` render pipeline: 3D diorama overworld with extruded terrain,
  depth-buffered occlusion, leaning sprite billboards, drop shadows and
  contact AO. VOXEL options row and hotkey `3` (OFF / 15 / 35 / 50 / 75).
- `tiltshift` render pipeline: a `worldPresent` post-process giving the
  miniature-photo look. T-SHIFT options row and hotkey `6` (OFF / 1 / 2 / 3).
- Carved voxel models for 67 overworld sprites, plus the
  `tools/build_voxels.py` that produced them.
- `data/voxel_heights.lua`, the hand-authored tile shape profile.

- Furniture shape classes in the profile: `bed` (a low slab wearing its
  top-down art), `table` and `desk` (boxes at their drawn height whose
  faces fold the artwork up), `relief` (a prop drawn from above -- a
  game console -- lying flat and extruding a few voxels inside its
  outline), the standee pools `billboard` (10px) / `prop` (5px) /
  `stool` (5px, and characters standing on its walkable cell sit at
  seat height) / `cutout` (one voxel: pure profile, for the vase on the
  table), and the stair archetypes `stair_e`/`stair_w` (a rising flight
  of real steps) and `stair_down_e`/`stair_down_w` (a sunken stairwell
  descending below the floor -- stairs that lead down).  Separate pools
  cluster separately, so touching drawings never merge into one cutout.
- Standee clusters split into per-pixel connected components, each
  standing on its own feet in the depth band of the row it is drawn in:
  two stools stacked in adjacent cells become two stools, and no
  fragment of a drawing ever floats at its bounding-box height.  A
  `cutout` keeps only its largest component -- a cast shadow's drawn
  edge is background, not a floating scrap.
- `bookcase` class: free-standing shelf drawings collapse in ranks onto
  one-cell-deep boxes at their full drawn height, back rows becoming
  hidden floor; the trim row above a rank -- undetected structure or a
  row pinned `table`, since the same trim tiles cap other furniture --
  is adopted as its cap.  Pinned for Oak's Lab (`DOJO`).
- Oak's Lab tables pinned `table`: the starter-ball display and the
  north tables stand at real table height, the display frame's black
  corner brackets no longer auto-extract into standing prisms, and the
  Poke Ball / Pokedex sprites ride the authored height onto the
  tabletops.
- Pinned props drawn directly above a pinned box stand ON it: the PC
  monitor on its desk, the flower pot on the dining table.
- Profile pins for `REDS_HOUSE_1` / `REDS_HOUSE_2` (Red's house and the
  Copycat's, both floors): bed, stools, tables, PC desk with its
  standing monitor, bookcases, TV standing on the floor behind the game
  console's relief, potted plant, flower pot, both staircases, and the
  wall/window band.
- `mods/DRAMATIC_SHAPE/tests/voxel_survey.lua`: screenshot-survey driver
  behind the repeatable inspection procedure (SURVEY_MAP / SURVEY_SPOTS /
  SURVEY_LEVELS / SHOT_DIR), documented in
  mods/DRAMATIC_SHAPE/tools/voxel-survey.md.

- `lib/Buildings.lua`: a building archetype. Where the volume path folds a
  whole drawing upright (roof, facade and sloped ends alike) into one box,
  this classifies each BAND of the drawing by the 3D surface it depicts and
  applies the matching operation: top-facing rows lay flat over the
  footprint, the facade extrudes straight back, an awning band juts past
  the walls, and the drawn taper at the ends becomes a stepped slope in
  elevation. Every visible voxel carries a real texel of the drawing, so
  the model recolours with the atlas.
- A `buildings` section in `data/voxel_heights.lua`. A building is matched
  by its exact tile grid (the drawings are catalogued in `assets/docs/buildings/`),
  so one entry covers every map that places the same art -- Red's house,
  Blue's house, Bill's, the Copycat's and the two Fuchsia houses are one
  seven-placement entry, and Oak's lab is a second. Only the band table is
  authored; the silhouette, the taper rate, the eave height and every
  window and doorway are measured off the pixels.
- The flat-roofed civic block and its sixteen relatives -- every Pokemon
  Center and every Poke Mart, Fuchsia Gym, the museum, the Game Corner,
  Celadon Mansion and its department store, the Power Plant, the Route 5
  and Route 22 gates, Silph Co and five anonymous scenery blocks. They are
  one architecture drawn at eleven different footprints, from 4x4 cells up
  to Silph Co's 8x12, and they share one band table: their lattice is drawn
  from straight above, so the measured taper comes out flat and the whole
  band is depth under one level roof. No new roof mode was needed -- the
  drawn profile was always the shape, and a drawing with no taper simply
  yields a level one.
- Pewter's museum hall (`assets/docs/buildings/B24`). It is the one
  sloped-roof building in this pass, and the only one so far whose roof
  texture is not a plain repeat: the drawing states its own period by
  repeating the whole lattice-and-course motif, rows 8..31 again at 32..55,
  so the cycle is 24 rows and the roof carries its drawn courses across the
  depth instead of a bare lattice. The band below them is the roof's
  fascia, wider than the wall it covers, so it belongs to the roof and
  lands on the south rim. Note the museum is TWO drawings: this hall and
  the east entrance beside it, which is B18 and shares its drawing with the
  Route 2 gate.
- The rest of the 2:1 sloped-roof buildings: both gym drawings (the
  standard one at Cinnabar, Pewter, Vermilion and Viridian plus the
  Fighting Dojo, and the wider Celadon / Cerulean / Saffron one), the 4x2
  cottage that houses Mr Fuji, the Cubone house, Bill's grandpa, the Name
  Rater and the Viridian school, Cerulean's three wide houses, the day
  care, and three scenery blocks -- among them B01, which at 19 placements
  is the commonest drawing in the game. Each one's roof band is pixel for
  pixel one of the three already authored, so they take that sibling's band
  table unchanged: 16 rows for Red's house's, 32 for Oak's lab's, 64 for
  the museum's.
- The Safari Zone rest houses and the Victory Road entrance, the first
  buildings outside the `OVERWORLD` tileset -- `buildings` is keyed by
  tileset and until now only had the one section. The rest house's
  corrugated roof repeats every 5 rows rather than the overworld lattice's
  8, which is the point of `roofCycle` being authored per building.
- Route 10's scenery block, via a new `seal` field. Its drawing has no
  black base course -- it ends on a row of light brick -- so the silhouette
  flood climbed in from the south border through the mortar and hollowed
  the wall out, leaving 72% of the sprite in 65 pieces. `seal` names the
  sides a drawing runs off rather than closing, and the flood does not seed
  there: sealed, it is 95% in one piece, and the model is its twin the
  museum's. No other building sets it, and none changes by a voxel.
- Together these take the mod to 31 of the catalogue's 34 drawings and 144
  of its 147 placements. The last three, and why each resists, are written
  up in `assets/docs/buildings/REMAINING.md`.
- A roof no longer runs past the drawing's own silhouette. These sprites
  are inset from their boxes, and the columns outside the inset carry no
  roof: they now get none, and the fascia belongs to the outermost columns
  the drawing actually paints. Before, they raised a four-voxel slab of
  black kerb the full depth of the building, flanking its walls at ground
  level. Nothing shipped hit this -- Red's house and Oak's lab are drawn
  edge to edge -- so no existing model changes by a single voxel.
- Windows and doorways sink a voxel behind their frames, found rather than
  listed: a pane is a non-black region the drawing seals off behind its own
  black outline. A nested frame (the door's own little window) layers for
  free.
- `tools/building_voxels.py`: the reference implementation of the same
  algorithm, with the geometric asserts and isometric previews Stage 5 of
  the methodology calls for. It and the runtime agree exactly on voxel and
  shell counts for all 19 templates -- 96,617 / 12,866 for Red's house up
  to 3,715,963 / 146,762 for Silph Co, which ship as 3,410 and 13,994
  quads. Its slope asserts read the drawn columns only and stand down for a
  roof with no taper, where the check is that the roof is level instead;
  its previews fit the projection to the model rather than to a fixed
  camera, so a building taller or deeper than the first two still lands on
  the canvas.

- A sky at the 75-degree rung. Pitched that far over, the horizon comes
  into frame and a good part of the picture is void, so the void gets
  filled instead of reading as the black plate it does at every rung below.
  No skybox and no geometry -- it is the colour the scene canvas clears to.

  **Outdoor maps only.** A house, a cave or a gym is a room with a ceiling,
  and the void past its walls is the outside of a box rather than open air.
  The test is `Map.isOutdoor`, the same one the engine uses for door SFX
  and the town map, and the same one `Structures` already asks to decide
  whether a map rings with trees.

  The colour is a four-shade ramp shaped like a world palette and run
  through `PaletteFX.effectiveColors`, so it answers to the display mode
  exactly as the baked terrain does: blue in the colour modes, grey under
  GRAY, green under CLASSIC, dark under GBC INV. A hardcoded blue would sit
  wrong in every mode that is not a colour mode. It fades across the
  approach to the top rung rather than switching at the keypress, so it
  arrives with the camera tween.

- The mod's four controls sit on adjacent keys, and the two that never had
  one now have a hotkey at all:

  | key | control |
  | --- | --- |
  | 3 | VOXEL, the camera ladder |
  | 5 | V-GRID, the wireframe |
  | 6 | T-SHIFT, the blur ladder |
  | 7 | V-CURVE, the horizon bend |

  Only 6 arrives by the documented route. `Game:keypressed` answers the
  engine's own display keys first and returns -- 2 COLORS, 3 TILT, 4 ZOOM,
  5 GBC FX -- and only then offers the key to `Pipelines.hotkey`, expressly
  so that "a pipeline can never shadow one". Two of the four wanted keys are
  in that set, and V-GRID and V-CURVE own no render pass, so they have no
  registry to claim a key from in the first place. The mod wraps
  `Game:keypressed` to take the four. Polling the keyboard in `update`
  would not do: it fires alongside the engine's handler rather than instead
  of it, so 3 would cycle this mode AND the engine's TILT on one press.

  **TILT (3) and GBC FX (5) are no longer reachable by key while this mod
  is enabled.** Both are still on the OPTIONS menu. Key 9 is now free.

  So the VOXEL key turns both off itself, on every press. Both fight the
  diorama -- TILT is the flat fake of what this mode does for real, GBC FX
  a full-screen present pass laid over the top -- and with 3 the only key
  that now reaches either, it also has to be the way back from having left
  one on. Every press, not just the one that switches the mode on: the
  registry's own tilt exclusion covers switching ON, but the press that
  cycles the ladder round to OFF would otherwise leave both running with
  no key left to clear them.

  The wrapper delegates rather than reimplements: `Pipelines.hotkey` still
  applies its own gate and ladder, the settings borrow the same free-roam
  gate the voxel pipeline uses, and a screen with its own key handler keeps
  the keyboard -- so typing a nickname cannot cycle a render mode behind
  the text box.

- `lib/ShadowMap.lua`: the scene rendered once from the sun into an
  orthographic depth map, which the main pass then samples per fragment.
  What the sun cannot see is in shadow, whatever surface it is, so a
  shadow climbs a wall, drapes over a roof and slides across a passing
  NPC with no case in the code -- and every caster is simply whatever the
  pass draws. The terrain mesh goes in, which means buildings, trees,
  ledges, signs and every prop cast, where before only characters did.
- Depth is packed into two 8-bit channels of an ordinary color canvas
  (~16 bits over a ~700px frustum, a hundredth of a world pixel).
  Readable depth textures are the least portable corner of the graphics
  API, and the mod's contract is that an unsupported driver falls back
  rather than errors: `available()` reports, and VoxelScene keeps the old
  flat decals when it says no.
- The map resolution is picked per frame from a 1024/1536/2048 ladder
  against a 0.45 world-pixels-per-texel target, because the light frustum
  is fitted to the world view and that swings 3x between the closest zoom
  and a maximised window at the widest. The frustum is snapped to whole
  texels, without which every shadow edge in the world crawls as you walk.
- Ambient occlusion, the genuine article: each vertex counts the
  neighbours crowding it and steps down once per neighbour, on top faces
  (four corners, three neighbours each) and now on upright faces too --
  the crease a wall rises out of, and the inside corners where flanking
  columns box it in. It is the complement of the shadow pass rather than
  a duplicate: the map draws the long directional shadow, this draws the
  dark seam in every corner the sky cannot see into, at scales finer than
  a shadow map texel.
- Plus a ground-contact term for the prebuilt prop quads -- per-pixel
  plants, signs and lone trees, and the round-tree stamps. Those arrive
  from Structures already finished, so the neighbour counting has no
  columns to count; what it can still say is that the floor blocks half
  the sky, so a voxel's first 6px of rise ramps back to full light. It is
  what stops a prop reading as pasted over the ground rather than
  standing on it, and outdoors it is most of what AO does at all, since
  trees and posts are nearly all prop geometry.
- One knob for the lot: `AO_STRENGTH` in `ChunkMesher` scales every term
  (they are written as darkening amounts, not multipliers), against a
  floor that keeps a crank from punching holes of pure black.
- The **V-CURVE** row in OPTIONS: the curved world, the Animal Crossing
  horizon. Every vertex is pushed down by the square of its horizontal
  distance from the camera's focus, and that is the whole effect -- a
  quadratic is nearly zero near its vertex, so the ground being played on
  stays flat, and the falloff accelerates, so the far edge rolls away over
  a near horizon and the town reads as sitting on a small sphere.
- It is deliberately NOT a fisheye. A fisheye is a LENS -- a screen-space
  warp -- which bends straight lines everywhere including right in front of
  the player, resamples every pixel to do it, and would leave this mode's
  art blurred and crawling. Bending the WORLD is one line in the vertex
  shader: lines near the camera stay straight and not a pixel is resampled.
- Displacing along Y only is what keeps it readable rather than
  nauseating: the drop depends on where a column stands, not how tall it
  is, so the world tips away and the buildings on it stay upright.
- Shadows and the wireframe ride along for free. Both are already worked
  out before the bend -- the shadow map in flat world space, the grid in
  model space -- so the bend carries them exactly as if they had been
  painted on, and neither the light frustum nor the grid needs to know the
  curve exists. `Voxel3D.project` applies the same drop on the CPU, which
  is what keeps the overworld's 2D field FX on their ground points.
- The strength scales with the view height, so a rung reads the same at
  every zoom, and the ladder is calibrated against the far edge of the
  visible ground rather than against nothing.
- `lib/ModSetting.lua`: the ladder/store/rows a setting of this mod's own
  needs, now that there are two of them. V-GRID's copy of it moved here.
- A **75 degree** rung on the VOXEL ladder, below the 15/35/50 it shared
  with the engine's TILT: low enough to read as a diorama shot from table
  height. Tilt could not have it -- its flat plane degenerates into a
  horizon line down there -- but geometry only gets more of itself to show.
- The **V-GRID** row in OPTIONS: a one-display-pixel wireframe along every
  voxel edge, 3D Dot Game Heroes style. Every mesh here is built one unit
  per voxel in its OWN model space, so the seams are that space's integer
  planes, and reading them in model space rather than world space is what
  keeps them glued to a thing however it is posed -- a character's slab
  leans back by the camera's pitch and its seams lean with it.
- The seams fade out where a voxel shrinks under about 3 display pixels.
  Survey zoom draws a world pixel at roughly a display pixel, and a wall
  seen nearly edge-on squashes one to nothing at any zoom; drawn anyway,
  the lines land closer together than they are wide and the wireframe
  stops being a wireframe and becomes a flat 45% dimming of the scene.
- `lib/VoxelGrid.lua` owns the toggle. It is NOT a pipeline: it owns no
  pass of the frame, it parameterises the voxel one, so it has nothing to
  put in `drawWorld` or `present` and the registry rightly rejects it. A
  plain mod setting instead -- `options:define` for the store and the mod
  manager's page, `ui.options.rows` for the row in OPTIONS next to VOXEL
  and T-SHIFT. Both rows read and write the one stored value.
- The wireframe is a SECOND COMPILATION of the scene shader rather than a
  branch inside it, because it needs shader derivatives (`fwidth`) -- the
  one part of the mode a driver can refuse. A refusal costs the grid and
  nothing else.
- `mods/DRAMATIC_SHAPE/tests/voxel_shadow_probe.lua`: reports the fitted
  frustum and the resolution rung, dumps the map itself, and shoots a
  stand point at every pitch. `SHADOW_SUN="kx,kz"` retunes the bearing for
  one run, `SHADOW_GRID=1` forces the wireframe on, and `SHADOW_ZOOM` pins
  the zoom, without which two runs are not comparable -- a driver inherits
  whatever the player left in `options.lua`, and the world view size (which
  the light frustum is fitted to) swings 3x across that range.

- A `counter` class (8px, upright): half-cell furniture. One 8px band,
  so exactly the drawing's bottom row stands up as the front and every
  row above it rides the top face in drawn order. `table`'s 12px could
  not be retuned for it; the houses share that class.

- `tilesets.POKECENTER` in `data/voxel_heights.lua`. Before it, the
  detector merged the wall-touching counters and healing machines into
  the wall band and towered them 3-6 blocks, flattened the machines'
  near-black screens to void, read the pillar bases, plant pots and
  machine bodies as ponds (the $14/$32/$48 stale-cache water fallback),
  boxed each plant pair into one hedge cube, and extruded the lounge
  seat -- a PERSON is drawn into its tile art -- into a monolith wearing
  his face.
- The pins, by shape: the wall band, windows, poster, pillars and the
  16px machine bodies are `wall`; the counters (with the nurse's tray)
  are `counter` and the PC's desk is `table`; the machine screens and
  the PC are `billboard`, standing on the pinned boxes below them; the
  potted plants are `prop` standees like every other interior plant.
- The lounge couch with the man sitting on it is a `counter` box: its
  bottom row stands up as the couch's front and the cushion and the man
  ride the top face, each drawn exactly once.
  He cannot be stood upright, and the reason is structural rather than a
  tuning question. His skin pixels span two tile rows and stop dead at
  the row 9/10 seam; folding two rows upright requires both to share a
  class, which makes the box two tiles deep, and a fully folded box
  repeats its north row across its whole top face. So every upright
  arrangement puts his head on screen two or three times -- as a 16px
  seat-back, on the front and twice more on the top; as a 32px bookcase,
  a cabinet taller than the room's own walls. Dropping the seat in front
  of him to floor level only changes which copy you see. Nor can he be a
  standee: the drawing has no floor margin, so all three non-black
  shades touch the cluster rim and the mask drains 307 of its 420
  interior pixels -- 46% of him even segmented alone, because his skin
  is the same light shade as the couch behind him.
- Survey evidence: full before/after passes of VIRIDIAN_POKECENTER at
  15/35/50 degrees, plus spot-checks of CELADON_POKECENTER and
  CELADON_HOTEL (shared tileset, both inherit correctly) and of
  REDS_HOUSE_1F, OAKS_LAB and VIRIDIAN_CITY (unchanged -- the new class
  is additive and no other tileset lists it).

### Changed

- Pinned props are segmented the way the art is authored: objects wear a
  black outline, so background is the shades touching the cluster's edge
  (white floor around a TV, grey tabletop around a vase) flooded in from
  the aprons; the outline, its interior, paint whites and anything they
  enclose survive -- pixel-perfect cutouts on any surface.
- Indoor structure analysis floods background from all four aprons and
  accepts ground contact on any side (outdoors keeps the south-only rule
  that protects roofs), so face-on furniture drawings voxelize per pixel
  instead of rising as wall-height volumes.
- Profile-pinned standees are 10px deep (detected props stay 6px), so a
  deliberate object like a TV keeps a body at shallow camera angles.
- Authored upright boxes fold their artwork up every face (flanks and
  back wear the front stack darkened) and top faces keep the drawn
  tabletop: face-on rows wear the row above the fold instead of
  repeating their front art lying flat, and a run that folded entirely
  tops with the furniture row drawn above it (a bookcase's shelf trim).
- Characters no longer ride a pinned stair tile's class height: stairs
  are walked through at floor level, fixing the step-up onto thin air in
  front of stairwells.

- A voxelized building is as tall as its facade plus its roof slab rather
  than as tall as its drawing: the roof rows are DEPTH now, not height, so
  Red's house is 36px over a 4x3-cell plot instead of a 48px cube.
- Round trees (the `cylinder` pin: lone canopies and the border tree
  wall) stop being lathes -- the sprite wrapped around a 12-segment
  column read as exactly that, art smeared on a barrel. Each cell is now
  a real voxel hull: the canopy is segmented out of its cell as the
  darkest-pixel outline plus everything it encloses (which also drops
  the background grass that used to inflate every row to full width, and
  the cast shadow under the ball), and each mask row runs its own span's
  circular chord in depth -- the front view is the sprite pixel for
  pixel, the plan view is the sprite's width profile turned in depth.
  Dithered art with no closed outline (the tree wall) falls back to
  light-shades-only flooding, per the methodology doc's boundary rule.
  Sides de-outline like building extrusions so flanks read as canopy
  rather than solid black, and dome caps keep their outline on the rim
  while the interior samples the canopy a couple of rows deeper.
- A `post` standee pool, pinned for the overworld's vertical fence-post
  cell (tiles 14/85 -- across every map the pair appears only as this
  cell). The detector already turns HORIZONTAL fence runs (tile 57) into
  per-post standees, but a vertical run of repeated cells trips its
  scenery-repetition guard and fell to the volume path as a
  fence-textured tower (Viridian's west line, Route 25).
  `post` extracts every CELL as its own cluster -- pooled clustering
  would stand the whole line up as one drawing-tall slab at one depth --
  and classifies pixels the way the detector does (non-white is body)
  rather than by the pinned-prop outline rule, which would strip the
  posts to black skeletons; at the detector's own 6px depth, pinned and
  detected fences look alike.
- Town signs move from the `billboard` pool to a new `signpost` pool: the
  same per-pixel standing slab, but 2 voxels thin instead of 10. A sign
  is a plate on a stick, and the standee body that keeps a TV from
  vanishing at shallow angles read as a solid block of furniture here.
- The ground under a round tree matches the tree's own drawn background
  instead of the map's commonest ground tile. The hull's segmentation
  already knows which pixels are NOT the tree; those pixels are scored
  against every flat ground tile the map places and the closest art
  wins, per template -- so border trees drawn over checker grass stand
  on checker grass even on a map that is mostly pale path (the old
  fallback painted path under every mid-forest tree, which has no flat
  neighbour to vote with). The drawn cast shadow stays out of the score:
  no ground tile carries a shadow, and its darks would drag every match.

- Mesh builds stream in the background. `ChunkMesher` queues per-map
  build jobs and `pump()` -- driven from the pipeline's update -- runs
  them inside a few-millisecond frame budget (`lib/BuildBudget.lua`
  suspends the build coroutine mid-loop when the slice is spent). The
  camera tween holds at flat until the current map's terrain exists, so
  toggling voxel mode shows a handful of flat frames instead of a frozen
  one; neighbours pop in as they finish. Warp fades prefetch the
  destination (the pipeline update ticks while the Transition covers the
  screen, with a wider pump slice), so a door exit lands on terrain that
  is already built.
- Vertex packing goes through FFI into one native buffer
  (`Mesh:setVertices(ByteData)`) instead of a Lua table per vertex --
  the headless table path remains for the pure `geometry()` API and its
  suite.
- Round-tree hulls are carved once per (tileset, art, ground set) and
  kept as stamps -- template plus cell offset, expanded during vertex
  packing -- instead of materialized per-cell quad tables. A route's
  border forest was ~500 quads x hundreds of cells of retained heap.
- Mesh and analysis caches evict down to the live neighbourhood (current
  map + rendered neighbours, plus one set of history so a house
  round-trip keeps the town warm). Evicted meshes are released
  explicitly. Memory over Pallet -> Mt Moon: was ~2.9GB and monotonic,
  now oscillates between ~90 and 200MB.

- `Voxel3D.SHADOW_KX/KZ` are -0.85 / -0.55, from +0.30 / +0.45: the sun
  crosses to the southeast and drops from 62 degrees to 45. The bearing
  leans WEST of northwest on purpose -- a character is drawn as a slab
  leaning away from the camera, which covers the ground due north of its
  feet, so a shadow thrown straight up-screen lands entirely underneath
  the figure casting it and is never seen.
- `Voxel3D.SHADOW_ALPHA` 0.32 -> 0.40, a quarter darker.
- `FACE_SHADE` east 0.78 -> 0.84 and west 0.78 -> 0.72. The two were equal
  because the old sun sat due northwest and they were symmetric about it;
  under a southeastern sun east is a lit flank and west a shaded one.
- A character's shadow lookup runs off the UPRIGHT card the sun saw, not
  the leaning slab the camera sees (`Voxel3D.draw`'s `sunModel`). Casting
  the leaning slab instead would shrink every shadow to nothing as the
  camera flattened toward top-down; looking up with the leaned position
  put each sprite's own card across its front.
- The contact-shadow term in `ChunkMesher` was a one-directional stripe
  keyed to a northwestern sun -- two neighbours, one corner, top faces
  only. It is now the ambient occlusion above.
- The light frustum is fitted to the ground the CAMERA CAN SEE rather than
  to a view-sized box around the focus, and both of its margins are now
  asymmetric -- for opposite reasons. The camera sits south of its focus
  and looks north, so the ground it sees runs far north and barely south;
  the sun sits southeast, so the casters for that ground stand south and
  east of it. Paying for a view-sized box plus caster margin on all four
  sides covered about a third of what was on screen at 75 degrees, and
  overpaid at 15.
- Shadows ease off at the frustum's rim instead of ending on it. Past the
  low rungs the horizon is further out than any box worth paying for, and
  a covered region that simply stops draws a hard line across the middle
  distance where every shadow ends at once.

The Pokemon Center interiors. One `POKECENTER` group in
`data/voxel_heights.lua` plus one new class, and because
VIRIDIAN_POKECENTER places every tile the tileset's other maps use, the
one pin set covers all eleven Centers and the Celadon Hotel.

### Fixed

- The generic town-house tileset (`HOUSE` -- Blue's house, Daisy at her
  table, and eighteen more homes, the schoolhouse and the trashed house
  among them) is now pinned in `data/voxel_heights.lua` the way Red's
  rooms already were: the dining table stops towering as a wall-height
  volume and sits at table height with its front folded upright, stools
  become seat-high boxes that characters sit on, the corner potted
  plants become per-pixel standees instead of texture-smeared box
  stacks, the bookcases get clean capped tops, and the wall band (with
  its window, picture and the schoolhouse blackboard) stays one 16px
  face.  The schoolhouse's open book stands on the pinned tabletop as a
  cutout, and the trashed house's ransacked table corner keeps table
  height.
- Interior door mats lie flat again in Red's and the generic houses.
  Their collision tile is $14, which the engine's stale-cache fallback
  counts as water in every tileset, so the rug recessed into a pond lip;
  a `ground` pin now overrides the water read.

- Stray pixels along map seams: ring props (border-tree hulls) whose
  quad CENTER sat exactly on a neighbour body's edge line escaped the
  strict point-in-rect mask and survived as fragments of otherwise
  dropped trees. Object quads now keep/drop by their full extent,
  boundary inclusive; props straddling the body edge also stay whole
  instead of shedding their outer half.
- The one-step "ledge hop" when crossing a connection into a tree-ringed
  map: the seam step stands the player one cell off the new map, where
  `Map:cellTile` border-extends into the borderBlock -- a raised tile on
  maps ringed with trees. Off-map ground now reads as height 0 (the
  departed neighbour's flat walkway, which is what is actually rendered
  there).

- Cycling palette modes with voxel mode on eventually killed the pipeline
  outright: `attempt to call field 'atlasImageData' (a nil value) --
  disabled for this session`. Nothing brought it back short of a restart.

  `TerrainAtlas` reads three engine seams to animate water and flowers in
  the terrain texture, and this build ships only one of them
  (`defaultAnimatedTiles`). The tile clock, `animFrame`, was already read
  guarded and simply degrades. `atlasImageData` was called straight -- but
  only down the branch where the mod had NOT baked the atlas itself, which
  is why it looked stable until a palette changed. Every mode with no world
  palette for the map (`PaletteFX.pal` answering nil), plus RED++ and any
  trueColor tileset, takes that branch, so the first map with animated
  tiles entered under one of them threw out of `drawWorld` and the engine
  disabled the pass for the session, exactly as it should.

  The seam is now read guarded like its sibling, and when it is absent the
  pixels are recovered rather than given up on. An atlas neither we nor
  RED++ replaced is the tileset art itself, so animation carries on from
  the art on disk. RED++'s per-map bake exists only as a texture --
  `getGbcAtlas` throws its `ImageData` away -- so that one comes back off
  the GPU: the atlas is drawn 1:1 into a canvas and read back, once per map,
  with the pass's own render target captured and restored around it (the
  usual `setCanvas()` would drop the rest of the frame). A driver that
  refuses the readback declines to animate and keeps the static atlas.
  Worst case now costs one animation, never the pipeline.

- Water and flowers did not animate in voxel mode at all, and had not since
  the mode shipped -- a silent one, since the terrain was otherwise correct.

  The tile clock is the third seam, and this build does not export it
  either. Being read guarded, it answered 0 forever instead of throwing,
  which pinned every animated tile at step 0. `animFrame` is a plain local
  in `TileRenderer`, but an upvalue of the exported `tick()`, so the mod now
  reads the real counter through it. That it is the ENGINE's counter is the
  point: the flat tile layer draws from the same number, so toggling voxel
  mode mid-cycle continues the animation rather than restarting it. A build
  that exports `animFrame()` outright is preferred; a build that hides the
  local falls back to wall time in 60Hz steps, which free-runs against the
  2D path but still moves the water.

- Toggling palettes in voxel mode flashed the flat 2D world for a moment on
  every switch.

  `PaletteFX.setMode` reloads the live map to rebuild its atlas, and this
  mod dropped that map's terrain mesh on any `map.reloaded` at all. Mesh
  builds are asynchronous, so the frames between the drop and the first
  rebuilt mesh had no terrain to draw -- and a voxel `drawWorld` with no
  terrain returns nil, which is exactly how the pipeline asks for the 2D
  fallback. The flash was the mod correctly reporting that it had nothing
  to show.

  The geometry was never stale: the mesher reads block layout and tile ids
  and never reads colour, and the palette lives entirely in the texture
  `TerrainAtlas` hands back per frame, keyed by palette and so already
  rebuilt by the next frame. A reload whose reason is `colors` now keeps
  the mesh, and the new palette lands on the diorama already on screen in
  one frame. Every other reload -- warps re-entering a map, hot reload, a
  replaced block -- still drops it.

- Every non-colour palette mode rendered as SGB in voxel mode: GRAY and
  both INVERTED modes came through as the map's blue.

  `paletteFor` hands a pipeline the map's RAW SGB zone palette. The flat
  path runs that through `PaletteFX.effectiveColors` on its way to the
  shade-remap shader, and that call is where the non-colour modes actually
  happen -- OG and OG INV swap in the DMG greys (reversed for the latter),
  CLASSIC swaps in the green set, GBC INV permutes the zone's own shades,
  and only GBC and RED++ pass through. This pass bakes colour into the
  atlas and the sprite sheets ahead of the draw rather than shading at blit
  time, so it never reached that call and painted the raw zone palette in
  every mode.

  Both bakes now run the same transform the shader would have. Terrain and
  characters go through one resolve, so they cannot disagree about what
  mode is on.

- VOID FILL did nothing in voxel mode, in two separate ways.

  **BLACK crashed the build.** The mode is not a block at all --
  `TileRenderer.borderBlockFor` answers `false` for it -- and `Structures`
  added 1 to that `false`. The arithmetic threw, which failed the mesh
  build for every map in the neighbourhood, which left the mode with no
  terrain and dropped it to the flat 2D path entirely. It now builds no
  ring: `tileLookup` answers nil past the body and those keys are never
  written, which the rest of the file already copes with -- every
  neighbour query in it reaches one step outside the analysed range and
  reads nil for its trouble, so an absent cell is the shape "nothing" has
  always had here.

  **WATER changed nothing on screen.** The ring is BAKED INTO THE MESH in
  this mode rather than drawn each frame, and nothing dropped the cache
  when the option moved, so the old ring simply stayed until the meshes
  were invalidated for some other reason. The pipeline's update hook now
  polls `TileRenderer.voidFill` and invalidates on a change -- polled
  rather than hooked because the engine changes it from three places (the
  options row, `applyOptions` on load, `setVoidFill`) and none of them
  announces it, and checked ahead of the active() gate so switching it
  while voxel mode is off still drops what is cached.

  `mods/DRAMATIC_SHAPE/tests/voxel_void_probe.lua` walks the three modes
  and reports the border block, whether the mesh built and whether the
  scene took the 3D path. It deliberately does NOT invalidate the cache
  itself, since doing so would hide the second half of this.

- Water and flowers did not animate. The 2D path animates them by
  OVERDRAWING the animated cells on top of the static tile layer each
  frame, which a single static mesh has no equivalent of -- the geometry
  samples one texture and that is that. So `TerrainAtlas` animates the
  texture instead: a private copy of the atlas whose animated tile slots
  are rewritten when the step advances, which moves every instance of that
  tile across the whole mesh at once. Which is what the Game Boy does in
  the first place (`home/vcopy.asm` rewrites the tile's VRAM bytes); the
  overdraw is the port's workaround for a tile layer, not the original.
  ~130 pixels of work three times a second, on the same
  `TileRenderer.animFrame` clock the 2D path uses, so the two can never
  disagree about which frame they are on.
- The frame files (`flower1..3.png`) are raw grayscale and have to land on
  the colours of the tile they replace, but the two recolour paths do not
  share a rule -- SGB bakes one world palette over everything, RED++ picks
  a palette group per tile graphic. So the shade mapping is LEARNED from
  the atlas: read the static tile's slot in the raw art and in the finished
  atlas side by side and ask what each shade became. Right under both
  without this file knowing which one ran.
- Terrain art was off the pixel grid by up to half a pixel, with one art
  pixel per tile sampled twice and another never at all. A tile is 8
  texels across 8 world pixels -- one texel per pixel exactly -- and
  `ChunkMesher`'s uv inset squeezed that art into a 7-texel sample range
  while the quad still covered 8 world pixels, so it advanced 7/8 of a
  texel per pixel and drifted. The inset exists to stop the rasteriser
  reaching a neighbouring tile along a shared edge, but half a texel was
  fifty times more than that needs: 0.02 is as safe (interpolation error
  is nowhere near it) and drifts 0.25% of a pixel across a whole tile.
  Nothing showed the fault until the voxel wireframe drew the grid those
  pixels were supposed to be sitting on.

### Changed from the pre-mod version

- The level is no longer the mod's to keep. The engine owns the ladder, the
  options rows, the hotkeys, persistence and the TILT exclusion; the mod
  keeps only the camera-angle tween.
- Persistence moved from `save.options.voxel` / `save.options.tiltshift` to
  `save.options.pipelines.voxel` / `.tiltshift`.
- Hotkeys moved from `4`/`9` to `3`/`6`: the fork already uses `4` for
  survey zoom.
- The tilt-shift pass is a declared `worldPresent` stage rather than a call
  spliced into the world draw, so it composes with any world pipeline
  instead of only this one.
- The cut-tree animation now draws in voxel mode; the pre-mod version
  omitted it from the 3D field-effect list.
