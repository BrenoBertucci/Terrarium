# kit_headless -- look at a kit's voxel geometry in seconds

Runs a **real** kit module out of `lib/` against a **real** map, with no
game around it: no window, no GPU, no mesher, no screenshot probe. It
loads the shipped `lua51.dll` (LuaJIT 2.1) with `ctypes`, fakes just
enough of LOVE and of the mod's `V` namespace for the kit to load, walks
every voxel of every model exactly the way `Buildings.emit` walks it, and
draws the assembled floor isometrically with PIL.

A game round costs about a minute and needs a probe to see anything. This
costs about three seconds and catches the class of bug that is *logic*: a
signature that never matches, a model that returns `nil`, a wall that
emits its own seam, a face count that quietly doubled.

## The two commands

```
python tools/kit_headless.py --kit CryptKit --map POKEMON_TOWER_1F
python tools/kit_headless.py --kit CryptKit --map POKEMON_TOWER_4F
```

Python is `C:\Users\breno\AppData\Local\Programs\Python\Python311\python.exe`
(PIL + numpy). Output lands in `tools/_kit_out/` -- the render, the raw
face dump, and the JSON report. **That directory is not in `.gitignore`**;
add `tools/_kit_out/` if you want it kept out of commits.

Useful flags:

| flag | what it does |
|---|---|
| `--template crypt_wall` | model only that template; the others are still *scanned*, so first-claim-wins order holds |
| `--set cryptfx=off` | force a `ModSetting` row for the run (repeatable), keyed by the setting KEY, not its label |
| `--png <path>` | where the render goes (default `tools/_kit_out/<kit>_<map>.png`) |
| `--json <path>` | write the full report, including every placement |
| `--placements 10` | print the ten slowest placements |
| `--no-render` | numbers only -- about 0.5 s faster |
| `--no-cull` | draw back faces too. They should never show; if they do, a model is inside-out |
| `--width 2400` | render width in pixels |

## Reading the output

```
CryptKit on POKEMON_TOWER_4F (tileset CEMETERY)
  settings   {'crypt': 'new', 'cryptfx': 'on'}
  lib/Buildings.lua loaded=True PHANTOM=-1   kit row on=True
  placements 230 scanned, 230 modelled by the kit
  models     50 built   49 distinct signatures
  faces      55885 emitted into the floor (55885 rows in the dump)
  lua        2.96 s (2.94 s of it modelling)
  templates:
    crypt_wall       kit  placements  76  models  45  faces   40600    2833 ms
    crypt_grave      kit  placements  50  models   4  faces   12789     100 ms
    crypt_mass       kit  placements 104  models   1  faces    2496       1 ms
```

* **placements scanned** -- how many times a template's tile grid matched
  the map, after `where`, `maps`, first-claim-wins and the full grid
  match. **modelled** is how many of those this kit owns.
* **models built** -- one build per distinct `(template, signature)`, the
  same caching `Buildings.build` does. This is the number that decides
  build cost: 66 placements over 47 models means 47 builds, not 66.
* **distinct signatures** can be one lower than models built when two
  templates answer the same string (`CryptKit.signature` returns `"m"`
  both for the mass template and for a ring cell that touches no room).
* **faces** -- quads after hidden-face culling and the greedy merge,
  summed over every placement. A **proxy for cost, not the cost**: it
  says nothing about texture bandwidth, overdraw, the shader, or the
  mesher's chunk upload.
* **voxels / shell** in the per-model lines are `emit`'s own counters --
  the numbers `tools/building_voxels.py` checks the algorithm against.
* **kit row on** -- the kit's own `enabled()`. Off, nothing is modelled
  and nothing is claimed, exactly as `Buildings.build` behaves.
* Per-placement `ms` includes the model build for the **first** placement
  of each signature; the rest are a table lookup plus a replay of the
  cached faces.
* Anything the kit refused shows as `ERROR ...` lines, and the process
  exits 1.

The measured crypt figures, against the shipped notes:

| | shipped note | measured here |
|---|---|---|
| 1F `crypt_wall` | 47 models over 66 placements | **47 models over 66 placements** |
| 4F total faces | order of 50k | **55 885** |

## The per-kit config table

Everything crypt-specific lives in one entry of `KITS` at the top of
`tools/kit_headless.py`. A new kit is one dict:

```python
"ShopKit": dict(
    module="ShopKit",       # lib/<module>.lua, and the name --kit takes
    mark="shop",            # the key on a voxel_heights template that
                            # says "this kit owns it" (t.crypt / t.shop).
                            # Templates without it are still scanned so
                            # the claim order stays honest. None means
                            # "every template of this tileset is mine".
    tileset="MART",         # which buildings.<TILESET> list to walk
    map="VIRIDIAN_MART",    # the default --map
    settings={"shop": "new", "shopfx": "on"},
                            # ModSetting rows forced for the run, keyed
                            # by setting KEY (ModSetting.new's first
                            # argument), not by its label. Unnamed rows
                            # fall back to values[1] -- the shipped
                            # default.
    stubs=["Voxel3D"],      # lib/ modules replaced by a no-op table
                            # because they reach for a GPU at load time.
                            # Keep this list short: every stub is a piece
                            # of the real thing not being tested.
    preload=[],             # mod-relative images the kit reads through
                            # V.mod.read + love.image.newImageData.
                            # Decoded by PIL and handed over as raw
                            # channel dumps (the crypt's
                            # assets/stone/crypt_wall_h.png is the case).
    sheet="assets/shop/shop_sheet.png",
                            # OPTIONAL. The kit is read from an authored
                            # PNG (Buildings' `spriteBand` path) instead
                            # of composited out of the four-grey tileset.
                            # Omit it and `sp` comes from the tileset,
                            # the way the crypt's does. `sheets=[...]`
                            # takes several when templates name their
                            # own with `t.sprite`.
),
```

The contract the kit must satisfy is the one `Buildings.build` already
uses, unchanged:

```lua
Kit.signature(t, tileAt, tx, ty, map) -> string | nil    (optional)
Kit.model(sp, t, sig)                 -> model  | nil, reason
Kit.enabled()                         -> boolean         (optional)
```

`sp` is `{ W, H, col, ax, ay, inside }` -- plus `role` and `path` when it
came from a sheet. `model` is `{ at(x,y,z) -> texel index | nil |
PHANTOM, W, ytop, xmin, xmax, zmin, zmax }` with optional
`tint(y, i, dir, shade)` and `claimMask`. `map` is a stand-in carrying
`map.def.id`, `map.def.width/height` and `map.tileset`. `tileAt(x, y)`
reads the map in TILE coordinates and returns `nil` off the grid.

**`signature` is optional.** A kit that decides its model per PLACEMENT
(CryptKit: which sides face the room, how tall the row stands, whether a
lantern hangs on it) has one, and the harness builds one model per
distinct string. A kit whose model depends only on the TEMPLATE
(ShopKit: one band per template, cut out of one room function) does not;
the harness then uses the template's `id` as the signature, so it builds
one model per template -- which is what `Buildings.build`'s plain branch
caches anyway. `model` is still called with three arguments; Lua ignores
the extra one.

Verified against both shapes:

```
ShopKit on VIRIDIAN_MART (tileset MART)
  placements 3 scanned, 3 modelled by the kit
  models     3 built   3 distinct signatures
  faces      50203 emitted into the floor
    shop_band_north  kit  placements 1  models 1  faces  25374   208 ms
    shop_band_mid    kit  placements 1  models 1  faces  15299   545 ms
    shop_band_south  kit  placements 1  models 1  faces   9530   737 ms
```

## Known limits

**It is geometry only.** No game shader, no lanterns, no point lights,
no bloom, no fog, no SGB palette, no day tint, no chunk mesher. The
render paints each face with the flat atlas texel its run starts on,
times the mean of its four corner shades. It tells you what the
silhouette and the shading *ratios* are; it cannot tell you what the
floor looks like lit.

**`read`, `readSprite` and `emit` are transcribed, not called.** All
three are `local` functions inside `lib/Buildings.lua` and cannot be
reached from outside it, so `tools/kit_headless.lua` carries a copy.
This is the one place the harness can drift from the game. What is
copied faithfully: the tile compositing (`paint`, `topRows`), the
four-shade classification, the border flood and `seal`, the sheet path's
alpha flood and `classify`/`role` table, the cell walk, the voxel/shell
counters, the PHANTOM rule (`v >= 0` is the whole of it -- any negative
index occludes and is never drawn), `runX`'s greedy merge, the
post-merge corner AO (`AO_STEP` 0.09, `AO_FLOOR` 0.25), the `tint` hook,
and the per-direction `SHADE` table. `Buildings.PHANTOM` is read off the
**real** module, so a `lib/Buildings.lua` that stops loading fails here
loudly; `SHADE` is a local and had to be copied.

Approximated on purpose:

1. **No uv.** `uvOf` is not reproduced. The dump records the run's first
   texel's atlas coordinate instead of a uv rectangle. Merge decisions
   are unaffected -- they live entirely in `runX`, which is exact -- so
   face counts match; only the texturing of a merged strip is lost, and
   a face is painted with one flat texel.
2. **`stamp` only does what geometry needs**: the world offset
   `(tx * 8, ty * 8)`, `claimRows`, `claimMask`, and "an empty model
   claims nothing". Not reproduced: `groundVote` / `S.ground`,
   `S.shapeAt`, `tallByMap`, chimneys, haunts, and the `tex` /
   `spriteQuads` split.
3. **`read` runs once per template**, not once per model key. Identical
   for any template whose `tiles`/`topRows` do not vary per placement --
   which is every crypt template. `LedgeKit`'s per-ground `topRows`
   override is therefore **not supported**, and neither is any kit that
   needs `groundVote`.
4. **Corner shades are averaged in the render.** All four survive in the
   binary dump (columns 12..15); the painter just fills flat.
5. **Painter's algorithm on the face centroid**, after culling the three
   directions the camera cannot see. Coplanar interleaved runs can
   misorder; it shows as speckle, never as a wrong wall. There is no
   z-buffer.
6. **`os.clock()` granularity** on Windows is coarse (single-digit ms).
   Treat per-placement times as a ranking, not a measurement.

**The stubs are a liability, not a feature.** `Voxel3D` is replaced by a
table that answers every key with a no-op, because it opens shaders and
canvases at load time and `Crypt` holds it only for drawing. If a kit
ever needs a real answer out of a stubbed module, the harness will give
it `nil` and the kit will look broken when it is not. Shorten the list
before blaming the kit.

**`love.image.newImageData` only serves preloaded files.** `V.mod.read`
hands back a sentinel string for a path in `preload`, and
`newImageData` recognises it; anything else raises. A kit that decodes
an image the config does not list will see its own `pcall` fail and take
its fallback path -- which is the honest outcome, but it means a missing
`preload` entry silently changes what is being measured. For the crypt,
`assets/stone/crypt_wall_h.png` is what turns `CRYPT-FX` from a
signature suffix into real carved relief: with it, 4F builds 45 wall
models and 40 600 wall faces; without it, the phase still splits the
signatures but every model comes out the same shape.

## Files

| | |
|---|---|
| `tools/kit_headless.py` | the driver: ctypes, the `KITS` table, the CLI, the isometric render |
| `tools/kit_headless.lua` | the stubs (`love`, `V`, `ModSetting`), the `read`/`emit` transcription, the placement scan |
| `tools/interior_plan.py` | imported, not duplicated: the maps.lua + tilesets.lua walk that expands a map into a tile grid |
| `tools/_kit_out/` | the job file, the atlas dump, the face dump, the JSON report and the render |

The face dump is `20 x uint16` big-endian per face: four corners
`x y z` (biased by +1024), four corner shades (x1000), the run's first
texel `ax, ay`, a direction code (1 s, 2 n, 3 up, 4 down, 5 e, 6 w) and
a texture id (0 the map's tileset, 1.. the authored sheets in config
order). `numpy.frombuffer(..., dtype=">u2").reshape(-1, 20)` is the
whole reader.
