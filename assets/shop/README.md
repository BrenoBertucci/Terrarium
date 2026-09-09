# The Mart's surfaces

The inside of the Poke Mart (`lib/ShopKit.lua`, `tools/shop_sheet.py`) is a
modern convenience store seen from a fixed diorama camera to the south, looking
down. These nine photo surfaces are what stops it being a grey box: albedo and a
DirectX-convention tangent-space normal map each, plus the floor's height.

| file | source | use |
| --- | --- | --- |
| `floor_tile.jpg`, `floor_tile_n.jpg` | Poly Haven **floor_tiles_08** (1k) | **the floor** (`FloorArt`'s `shop` profile). Grouted square tiles, 5x5 per cycle, at `scale = 32` so one tile is 64 cm |
| `floor_tile_h.png` | same, its Displacement (1k, 8-bit) | the grout, for a kit that wants to carve it into geometry |
| `shop_vinyl.jpg`, `shop_vinyl_n.jpg` | Poly Haven **linoleum_brown** (1k) | flecked sheet vinyl, no seams and no pattern. Graded and NOT adopted: with no grout the floor loses the one grid that tells the eye how big the room is, and at this camera that reading matters more than the material does. One line in `FloorArt`'s `shop` profile if that judgement changes |
| `wall_paint.jpg`, `wall_paint_n.jpg` | Poly Haven **white_stucco** (1k) | the first wall, kept for comparison. Superseded: its relative sd is **0.014**, which is plus or minus three levels and invisible on screen |
| `ceiling_tile.jpg`, `ceiling_tile_n.jpg` | Poly Haven **ceiling_interior** (1k) | **the walls and the ceiling** (`Shop.MATS.wall`, sheet bands 0 and 1). An even roller stipple; rolled emulsion is the same surface at the same scale. Shader reciprocal **1.668** |
| `metal_shelf.jpg`, `metal_shelf_n.jpg` | Poly Haven **blue_metal_plate** (1k) | dark painted steel: cooler frames, kick plates, the door track |
| `steel_brushed.jpg`, `steel_brushed_n.jpg` | Poly Haven **corrugated_iron** (1k) | **every hard surface** (`Shop.MATS.hard`, sheet band 2): gondola uprights, posts, shelf boards, cabinets. Shader reciprocal **1.666** |
| `counter_wood.jpg`, `counter_wood_n.jpg` | Poly Haven **okoume_veneer** (1k) | the first counter laminate, kept for comparison |
| `wood_light.jpg`, `wood_light_n.jpg` | Poly Haven **white_maple_veneer** (1k) | **the counter.** Pale laminate with visible figure |
| `plastic_scuff.jpg`, `plastic_scuff_n.jpg` | Poly Haven **polystyrene** (1k) | white plastic with use marks. Graded and not yet bound to a band -- the sheet's five bands are spent, so this is here for the next fixture class that needs one |

All nine are **CC0** (public domain) from https://polyhaven.com -- no attribution
required, given anyway. The API payload still carries no per-asset `license` key;
the site licence covers the whole library and was re-read before this batch was
downloaded: "All assets ... on this site ... are all licensed as CC0"
(https://polyhaven.com/license).

`shop_sheet.png` in this directory is not one of these; it is the authored texel
sheet, and `tools/shop_sheet.py` writes it using the albedos below as grain --
its `GRAIN` dict names the files, one line per band.

## The number that decides whether a surface reads

The scene shader brings each albedo's mean back to unity, so the photo is the
DETAIL and the geometry's own light is the TONE. That has a consequence the first
four surfaces were graded without: **the mean is normalised away, so the only
thing a photograph contributes is its spread relative to its own mean.**

    relative sd = sd(luma) / mean(luma)

Two files stored at mean 0.58 and 0.78 are the same picture once the shader is
done with them. Measure the shipped set against `probe_out_shop/shop_room.png`
and the room's complaint explains itself:

| file | albedo mean | shader multiplier | **relative sd** | cast |
| --- | --- | --- | --- | --- |
| `floor_tile.jpg` | 0.620 | **1.613** | 0.105 | neutral (R-B +0.026), sat 0.041 |
| `shop_vinyl.jpg` | 0.619 | **1.616** | 0.087 | neutral (R-B +0.012), sat 0.019 |
| `ceiling_tile.jpg` | 0.600 | **1.668** | 0.079 | neutral (R-B -0.001), sat 0.002 |
| `steel_brushed.jpg` | 0.600 | **1.666** | 0.088 | COOL (R-B -0.027), sat 0.045 |
| `plastic_scuff.jpg` | 0.599 | **1.671** | 0.087 | faint warm (R-B +0.009), sat 0.015 |
| `wood_light.jpg` | 0.599 | **1.668** | 0.075 | WARM (R-B +0.025), sat 0.041 |
| `metal_shelf.jpg` | 0.580 | **1.725** | 0.056 | faint COOL (R-B -0.032), sat 0.054 |
| `counter_wood.jpg` | 0.600 | **1.667** | 0.033 | faint WARM (R-B +0.035), sat 0.057 |
| `wall_paint.jpg` | 0.749 | **1.335** | 0.014 | neutral (R-B +0.012), sat 0.016 |

`floor_tile` is the only surface whose texture is visible in a shipped frame, and
it has the largest relative sd by a factor of two. `wall_paint` modulates by
1.4%; sampling the back wall in `shop_room.png` gives mean 250/255 with sd 7.8,
so those 1.4% are plus or minus three levels under a surface that is already
clipping. That is the whole of "the room reads as flat white plastic" -- it is an
exposure problem first and a texture problem second, and no albedo can fix a
surface whose lit value is 250. **The five new files target 0.07-0.10** so that
something survives; `python tools/surface_pick.py depth "assets/shop/*.jpg"`
prints the column and a verdict, and `... frame <png>` prints the exposure.

Means are the plain mean of all RGB samples in stored 0..1 space, measured back
off the shipped file -- the same convention `assets/stone/README.md` used when it
recorded 1.94 and 2.2. No albedo has a single texel at 0 or at 255.

## The exact commands

Re-running these reproduces the shipped bytes exactly (verified: identical md5 on
a second run into a clean directory, for all ten new files).

The first four use `tools/prep_polyhaven.py`, unchanged. The five below use
`tools/surface_pick.py grade`, which is the same arithmetic with **the mean
normalisation moved in front of the contrast flatten** -- see "Why a second
grader" below. Where nothing clips the two produce byte-identical output
(checked on `ceiling_interior`).

```
python tools/prep_polyhaven.py grade floor_tiles_08 --out assets/shop/floor_tile.jpg \
    --res 1k --size 1024 --desaturate 0.88 --contrast 0.80 --target-mean 0.62 \
    --normal-recenter --height
python tools/prep_polyhaven.py grade white_stucco --out assets/shop/wall_paint.jpg \
    --res 1k --size 512 --desaturate 0.70 --contrast 1.40 --target-mean 0.75
python tools/prep_polyhaven.py grade blue_metal_plate --out assets/shop/metal_shelf.jpg \
    --res 1k --size 512 --desaturate 0.95 --tint -0.012 --contrast 0.45 --target-mean 0.58
python tools/prep_polyhaven.py grade okoume_veneer --out assets/shop/counter_wood.jpg \
    --res 1k --size 512 --desaturate 0.92 --tint 0.010 --contrast 2.00 --target-mean 0.60

python tools/surface_pick.py grade linoleum_brown --out assets/shop/shop_vinyl.jpg \
    --res 1k --size 1024 --normal-size 512 --desaturate 0.93 --tint -0.006 \
    --contrast 2.60 --target-mean 0.62
python tools/surface_pick.py grade ceiling_interior --out assets/shop/ceiling_tile.jpg \
    --res 1k --size 512 --desaturate 0.92 --tint -0.012 --contrast 1.80 \
    --target-mean 0.60 --normal-strength 0.50 --normal-quality 88
python tools/surface_pick.py grade corrugated_iron --out assets/shop/steel_brushed.jpg \
    --res 1k --size 512 --desaturate 0.90 --tint -0.020 --contrast 1.80 \
    --target-mean 0.60 --normal-strength 0.35
python tools/surface_pick.py grade white_maple_veneer --out assets/shop/wood_light.jpg \
    --res 1k --size 512 --desaturate 0.92 --tint 0.010 --contrast 5.00 --target-mean 0.60
python tools/surface_pick.py grade polystyrene --out assets/shop/plastic_scuff.jpg \
    --res 1k --size 512 --desaturate 0.90 --tint 0.008 --contrast 5.00 \
    --target-mean 0.60 --ceil 0.965 --normal-strength 0.60
```

Knobs that are doing more than their names suggest:

- **`--contrast 5.00`** on the maple and the polystyrene is a boost of the same
  kind `--contrast 2.00` was on the okoume, only larger because both photographs
  are of near-white materials with almost no luma spread to begin with (source
  relative sd 0.016 and 0.026). Below about 4.0 they ship at `wall_paint`'s
  depth, which is to say invisible. Polystyrene stops gaining at 5.0 (5.0 and 6.0
  both land on 0.090); the maple would keep climbing to 0.090 at 6.0, and 5.0 was
  chosen to stop short of turning a wood grain into a zebra.
- **`--ceil 0.965`** on the polystyrene only. At the default 0.98 the buffer is
  clean but JPEG ringing around the scratches pushes two texels to 255, and no
  albedo here is allowed a texel at 255.
- **`--normal-strength 0.35`** on the steel is what turns roofing into shelving.
  The source is real corrugation, not a texture of one: 15 flutes across a
  1120 mm tile (75 mm pitch) and a displacement map spanning 95% of its range, so
  at full strength the uprights would be ribbed. The albedo keeps the flutes as a
  directional grain, which is the whole reason this asset works as brushed metal.
- **`--normal-size 512`** on the vinyl, against a 1024 albedo. Sheet vinyl has no
  relief -- its normal's blue channel means 0.9983, i.e. flat to a fifth of a
  degree -- so the full-size map cost 161 KB to say nothing. The albedo stays at
  1024 because it is the floor.

Sizes are the crypt's budget: 1k downloads, 1024 px for the two floors because
the camera looks at them, 512 px for everything else. Albedos are JPEG q90 and
normals q92 (the ceiling's stipple is high-frequency enough to want q88), both
4:4:4, matching `assets/stone/`. **1,957,870 bytes (1.87 MB) for the nineteen
files**, of which the new ten are 1,004,493.

`shop_vinyl.jpg` is 393 KB of that, because fleck compresses badly. Grading it at
`--size 512` instead costs 7% of its depth (0.087 -> 0.081) and saves 296 KB; it
was left at 1024 to match `floor_tile`, but that is a one-word edit if the budget
matters more than the match.

## Why a second grader

`prep_polyhaven.py` flattens contrast BEFORE it normalises the mean, and its
anti-clip guard is symmetric about the current mean. A photograph of a white
material arrives with a mean near the ceiling -- polystyrene at 0.868, white
maple at 0.835 -- so there are 0.11-0.15 of headroom above it and 0.85 below.
The guard shrinks the whole image to fit the side with none, and `--contrast`
saturates:

| polystyrene, shipped order | `--contrast 3` | `--contrast 5` | `--contrast 8` |
| --- | --- | --- | --- |
| relative sd | 0.0158 | 0.0159 | 0.0160 |

Widening `--floor` does not help: the binding side is the ceiling. The cap is a
property of the source's brightness, not of the knob, and 0.016 is the wall's
number -- the surface would have shipped reading as flat white plastic.

`tools/surface_pick.py grade` normalises the mean to the target first, so the
guard's headroom is symmetric, and only then flattens:

    resize -> desaturate -> tint -> MEAN NORMALISE -> flatten -> anti-clip guard

`flatten` scales each channel about its own mean and the guard pivots on the
target, so the mean still lands on the target exactly and the multiplier is still
1/mean. Same functions, imported from `prep_polyhaven.py`; one step moved. Under
that order polystyrene reaches 0.0588 at `--contrast 3` and is still climbing.

`prep_polyhaven.py` remains the reference for anything darker than about 0.7 --
all four of its shipped surfaces are below that, and it is the only one that
writes height maps.

## Normals

`nor_dx` for all nine, green down -- nothing was flipped. Verified rather than
assumed, on each of the five new assets: the green channel's correlation with the
displacement map's row gradient is negative in every case (corrugated_iron -0.64,
ceiling_interior -0.87, linoleum_brown -0.73, white_maple_veneer -0.69,
polystyrene -0.84), and negative means green-down, which is DirectX.

All five new bakes are level -- mean normals lean 0.1 to 0.7 degrees -- so none
needed `--normal-recenter`. `floor_tiles_08` did: its bake carries the tilt of
the panel it was shot off, every texel of a flat tile leaning 16.7 degrees the
same way (R=0.603 G=0.399) in `nor_dx` and `nor_gl` alike while its own
displacement map is level. On a floor that reads as the whole room being on a
slope, so `--normal-recenter` pulls the mean tangent vector back to straight up;
the shipped map leans 0.2 degrees. Check the channel means on anything new: flat
is R=G=0.5.

## What the library does not have

Two of the five surfaces asked for do not exist in Poly Haven. The whole texture
index is 857 assets; `python tools/surface_pick.py cats` lists its own taxonomy,
which is how this was settled rather than guessed:

- **No acoustic ceiling tile.** No mineral fibre, no suspended ceiling, no
  fissured board, no popcorn or artex -- the strings return nothing across every
  description, tag and category, and there is no ceiling leaf in the tree.
  `ceiling_interior` is the library's only ceiling of any kind, and it is a
  painted ceiling with a fine even orange-peel stipple. Graded flat it reads as a
  textured ceiling, which is what the room needed; it does not read as a 600 mm
  grid of mineral fibre, and it never will. If the Mart wants a lay-in grid, the
  grid is geometry or a sheet band, not a photograph.
- **No brushed, stainless or anodised metal.** Zero hits for brushed metal,
  stainless, aluminium, chrome or satin metal. `Metal/Sheet & Corrugated/Flat
  Sheet` holds nine assets and eight are rust; the ninth is `blue_metal_plate`,
  already spent on `metal_shelf`. What is available is galvanised roofing, and
  `corrugated_iron` is a light cool sheet whose 25 mm flutes, with the normal
  flattened to 0.35, read at gondola scale as exactly the fine directional grain
  brushed steel has. It is a substitution and it is named as one, but it is a
  substitution of an appearance, not a bad match: light, cool, directional, and
  two full stops brighter than `metal_shelf`.

## `wood_light` against `counter_wood`

`wood_light` is better for the checkout counter, on both the measurement and the
brief. `counter_wood` (okoume) modulates by 3.3% and carries a +0.035 warm cast,
so on screen it is a warm flat plane -- in the shipped frames the counter is the
one large surface with no readable material at all. `wood_light` (white maple)
modulates by 7.5%, twice as much, at a lighter and slightly cooler +0.025, and
its cathedral figure is coarse enough to survive the room's exposure. Okoume is
1970s plywood; maple is the pale laminate a convenience-store counter is faced
with. Both are kept so the swap is a one-line edit in `tools/shop_sheet.py`'s
`GRAIN` and revertible.

The same holds for the floor. `floor_tile` is a grouted square tile that reads as
a bathroom under this camera; `shop_vinyl` is flecked sheet with no seam and no
repeat, at 0.087 relative sd against the tile's 0.105 -- slightly less depth, but
the depth it has is grain rather than a grid.

## Rejected

From this batch:

- **old_linoleum_flooring_01** -- the right material, but its pattern is a dense
  field of tan octagons. Flattened to `--contrast 0.30` the octagons are still
  legible and it reads as decorative vintage lino; the same objection as
  `floor_tiles_06` below, and it cost more contrast to get there.
- **rubber_tiles** -- a dark matte gym floor, and tiled.
- **white_plaster_02**, **painted_plaster_wall**, **concrete_wall_00x** -- offered
  for the ceiling; all mottled with dirt and stains. A ceiling has to be grain.
- **ash_veneer**, **angli_veneer**, **cherry_veneer** -- light hardwood veneers
  that are all a shade browner than the maple; nearest miss is `ash_veneer`.
- **laminate_floor**, **laminate_floor_02**, **laminate_floor_03** -- light oak
  and correctly named, but every one carries plank seams, which under a counter
  read as a floor laid on the worktop.
- **painted_metal_shutter**, **worn_shutter** -- light grey and directional, but
  the horizontal ribs read unmistakably as a roller shutter.
- **metal_plate**, **metal_plate_02**, **green_metal_rust**, and the rest of
  `Metal/` -- rust, every one.

From the first batch:

- **floor_tiles_06** (checkerboard) -- reads as decoration rather than surface,
  and its two-tone means half the floor sits far off whatever mean the shader
  normalises to.
- **long_white_tiles** -- right colour, but it is a wall tile: 33 tiles across a
  cycle turn to noise under a camera this far up.
- **terrazzo_tiles**, **marble_01** -- no grout to speak of.
- **tiled_floor_001**, **floor_tiles_04**, **patio_tiles** -- terracotta warmth
  that survives desaturation as a stain.
- **beige_wall_001** -- flat enough, but a 32 KB source with no grain at all; it
  would have been a flat colour with a normal map attached.
- **kitchen_wood**, **plywood** -- too dark, too orange, or carrying plank seams.

## Contract

Drop-in like the rest of `assets/`: replace a file and it is used, delete one and
the surface falls back to flat colour (`tools/shop_sheet.py` reports which grain
is missing and still writes a valid sheet). Replace an albedo without re-recording
its mean in the table above and the shader will light that surface at the wrong
tone -- the number, not the picture, is the part the code depends on. Replace one
without re-checking its **relative sd** and the surface may be lit correctly and
still be invisible, which is the failure this batch was written to fix.
