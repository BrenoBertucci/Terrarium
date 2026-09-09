# Rebuilding an interior — the pipeline

How the Poke Mart's inside was rebuilt (`lib/ShopKit.lua`, `lib/Shop.lua`),
written down as a procedure because the next room — a gym, a house, the
Game Corner — is the same seven steps. The Pokemon Tower's crypt was built
ad hoc and cost a session rediscovering half of this; this is that session's
interest.

Each step names the tool that does it and the failure it exists to prevent.
Steps 1, 2, 3 and 7 have a reusable agent under `.claude/agents/`.

---

## 0. The rule that shapes everything

**Measure the FRAME before you touch the model.** This is step 0 because a
whole session was spent chamfering, re-cutting and re-stocking a room whose
real problem was that it was over-exposed: 27.8 % of its pixels had a
channel pinned at 255, 14.0 % were pure `#FFFFFF`, and the correlation
between "this patch is clipped" and "this patch has no shading ramp left"
was **-0.944**. An unclipped patch carried 30.9 levels of shading; a clipped
one carried 4.7. The engine was computing all of it and the exposure was
erasing it.

Everything aimed at the models -- the chamfers, the per-SKU statures, the
corner AO, the contact field, the sun pass -- was landing inside a white
that could not get whiter. So, before any of the seven steps below:

```
python tools/surface_pick.py frame probe_out_shop/shop_room.png
```

If clipping is over about 5 %, **stop**. Nothing else you do can be judged.

**Then measure before modelling.** Every number in `lib/ShopKit.lua` came from
somewhere: the plan from the shipped ROM data, the scale from the engine's
own character quad, the camera pitch from the shot, the cut from the pitch.
The one time this build guessed — the first pass picked 40, 48 and 56 for
fixture heights because they looked right — it produced a cathedral with
shelves in it and had to be redone.

## 1. Dump the real floor plan

```
python tools/interior_plan.py VIRIDIAN_MART --atlas atlas.png --render room.png
```

`tools/interior_plan.py` reads the BUILD's `maps.lua` + `tilesets.lua`,
expands the map's blocks into the 16x16 TILE grid the mod actually matches
against, and can render it with the tile ids drawn on.

**Why:** the coordinates in `assets/docs/buildings/` are AUTHORING
coordinates, not the overworld's. `tests/mart_probe.lua`'s header records
three runs lost to standing in an alley because of that.

**Then hash the plan across every map on the tileset.** All eight town
Marts came back byte-identical, which is what let the room be authored as
one function instead of a vocabulary of parts. Do this before designing
anything — it decides the whole partition.

## 2. Get the surfaces

```
python tools/prep_polyhaven.py list --search tile
python tools/prep_polyhaven.py grade floor_tiles_08 --out assets/shop/floor_tile
```

CC0 photographs from Poly Haven, graded: desaturated toward the room's own
cast, mean normalised, contrast flattened so nothing crushes. **Record each
albedo's mean and the multiplier the shader needs** — `assets/shop/README.md`
and `assets/stone/README.md` both carry that table, and the shader quotes
the number in a comment. **Re-derive that reciprocal whenever a material is
re-pointed:** the photograph is multiplied in as grain, so a stale one
darkens or blows the whole surface instead of changing its texture.

**PICK ON RELATIVE SD, NOT ON SUBJECT.** The shader normalises each albedo's
mean away, so the only thing deciding whether a surface reads on screen is
`sd/mean` — how deep its own modulation is. The shop shipped with
`wall_paint` at **0.014**: plus or minus three levels, invisible, and the
reason its walls read as moulded plastic however well the models were cut.
Measured over the first set: wall_paint 0.014, counter_wood 0.033,
metal_shelf 0.056, floor_tile 0.105 — and floor_tile was the only one
visible in any frame. **Target 0.07-0.10.**

```
python tools/surface_pick.py depth "assets/shop/*.jpg"
```

The API needs a browser `User-Agent` or it answers 403. The tool's docstring
says so; that trap has now been rediscovered twice.

## 3. Write the art direction down, with arithmetic

`assets/docs/shop/ART_DIRECTION.md` is the model. It fixed:

- **the scale** — `Voxel3D.casterMatrix` makes a character a 16x16 quad, so
  a person is 16 voxels and **one voxel is 10 cm**. Every fixture height is
  a real dimension over that.
- **the camera** — author the `data/camera_shots.lua` entry FIRST. A
  dollhouse cut under a player-driven orbit is a sawn-off wall the moment
  the camera swings behind it.
- **the cut** — from the shot's pitch. At 27 degrees `k = tan 27.1 = 0.511`,
  so one voxel of height hides 1.96 world px of floor behind it. Every
  height cap and the rule that **nothing may hang from the ceiling** are
  that one line applied.

## 4. Build the texel sheet

```
python tools/shop_sheet.py --preview preview.png
```

The tileset is four greys under one flat palette, so a room read off it can
only ever be a grey box — that is what the old `lib/RoomKit.lua` Mart was.
The room is built against an authored RGBA sheet instead, one texel per
voxel, the same path the Mart's facade has used since `spriteBand`.

**Band the sheet by MATERIAL**, sixteen rows to a band. The fragment stage
then picks which photograph to modulate from the texel's `v` alone — one
`floor()`, no branching on `u`, and no new sampler.

## 5. Model the room as one function

`lib/ShopKit.lua`: one `room(x, y, z)` in world coordinates, and the
templates are WINDOWS into it — each answers with the room's voxel inside
its band and with `Buildings.PHANTOM` outside it. The bands then cull each
other's faces at the seam and the room emits as one piece.

Iterate headless, not in game:

```
python tools/kit_headless.py --kit ShopKit --width 4200
```

Three seconds against about ninety for a game round. It catches geometry:
proportions, a model that returns nil, a face count that doubled. It does
NOT catch lighting, materials or the wireframe — everything in step 6 was
invisible to it.

## 6. Wire the air

`lib/Shop.lua`, mirroring `lib/Crypt.lua` line for line so the two rooms can
be compared: the row, the FX row, the ambient, the lamp sites (**read twice**
— once by the scene for the point lights, once by the kit for the fixtures,
so a pool always has a fixture over it), the materials, the bloom.

Then in `lib/VoxelScene.lua`: ambient, the sun held off, the lamp arm, the
per-draw material switch on the room's own sprite group, and the bloom.

**Hold the wireframe and the cel step off** while the materials are on, the
way the crypt does. The Mart's first in-game frames were a room made of
graph paper.

## 7. Photograph it, and read the pixels

```
tests\run_shop_interior.cmd
```

Named frames, an A/B with the row forced off, a cost budget and a
machine-greppable verdict. Then **look at the frames and, when something is
wrong, measure it rather than reading the code for it**. This build's four
worst bugs were each found by measurement after a wrong guess:

| symptom | wrong guess | how it was actually found |
| --- | --- | --- |
| the whole room looked square | "the models are boxy" | the wireframe row was on; the models were only half of it |
| the floor was green, then black | "the floor art is broken" | the SGB palette recolours shade 1 to the TOWN's colour, and `groundVote` had no vote at the map's edge |
| a dark fixture in front of the gondolas | "the bottom shelf is unlit" | sampling its pixels: neutral greys and pure black, which exist on the TILESET and not on the shop's sheet — a class pin standing the old drawing in a tile the claim mask had left free |
| the bottom tier read black | "corner AO" | `AO_STEP` is 0.09 with a floor of 0.25, so AO cannot do that; it was the same class pin |

Two habits are worth keeping from that table. **Crop and zoom the actual
frame** — `PIL` on the probe's PNG, three lines. And **count the colours**:
a surface's palette says which atlas it came from, which is a fact no amount
of reading the model will give you.

---

## 8. Judge it with numbers, not with your eyes

`.claude/agents/voxel-silhouette-critic` measures six things on the frames
step 7 produced, and the ORDER of its ranking is by share of screen, not by
how bad each looks. Run it before touching a model.

| measured | shop, first pass | healthy |
| --- | --- | --- |
| clipped pixels | **27.8 %** | under 5 % |
| pure `#FFFFFF` | **14.0 %** | ~0 |
| shading ramp, unclipped patch | 30.9 levels | — |
| shading ramp, clipped patch | **4.7 levels** | — |
| surface texture depth on screen | **2.50** (worst 1.30) | over 2, ideally 6+ |
| longest horizontal skyline run | **240 px = 20.6 % of width** | under 5 % |
| largest single swatch | **25.2 %** | under 15 % |
| pixels with sat < 0.10 | **75 %** | under 60 % |

That table is the whole lesson of the rebuild. Two of those rows are art
problems. The rest are **bugs wearing an art problem's clothes**, and no
amount of modelling touches them.

## The indoor shadow has FOUR gates in series

Written out because three of the four were found the expensive way, and
each one fails the same way: the sun pass still renders, every Lua-side
check is still green, and the room comes back with **no shadow at all** --
which on screen is indistinguishable from the feature being switched off.

| gate | where | what it looks like when wrong |
| --- | --- | --- |
| `Shop.SHADOW_SCALE` | `lib/Shop.lua` | 0 was the shipped value: "there is no sun in a shop" is true and is also why nothing in the room touched the floor. The eight tubes are POINT lights, and a point light in this shader lights a surface without occluding one. The sun pass is the room's only occluder, and its cost is already paid whether the number is 0 or not. |
| the two SHEARS | `DayNight.applyRig` sets `ShadowMap.KX/KZ` (what the depth map is DRAWN with) **and** `Voxel3D.SHADOW_KX/KZ` (what the shader LOOKS IT UP with) | set one and every lookup lands off its own texel |
| the `LIGHT` row | `lib/Light.lua` | on FLAT, `Light.split` puts everything in the ambient term and nothing directional. `sunDark` is only a GATE saying a map is worth sampling; **what a shadow costs lives in the split.** |
| the exposure | `Shop.AMBIENT` | a shadow that takes 14 levels off a surface already pinned at 255 is invisible. Step 0. |

The probe asserts the first three now (`sun pass:` in the log) and step 0
measures the fourth.

## The harness TRANSCRIBES the emit — it does not call it

`tools/kit_headless.lua` re-implements `Buildings.emit` (both are locals in
their file). So **any hook added to one must be added to the other**, or the
harness reports a working feature as a no-op. The contact field was added to
`Buildings.emit` and the harness went on drawing the room without it.

Its renderer had the same trap in a second form: it averaged each quad's
four corner shades into one colour, which is exactly the gradient the corner
AO and the contact field exist to produce. `--shade-only` and the Gouraud
split were added for this; use them to look at LIGHT with the texel thrown
away.

---

## The reusable agents

Under `.claude/agents/`, so the next room does not re-derive them:

| agent | does |
| --- | --- |
| `voxel-room-recon` | step 1 — plan, atlas, cross-map hash |
| `cc0-texture-fetcher` | step 2 — Poly Haven download, grading, README |
| `voxel-art-director` | step 3 — the measured spec |
| `voxel-probe-author` | step 7 — the in-game probe and its launcher |
| `voxel-silhouette-critic` | step 8 — the measured verdict, ranked by share of screen |

Steps 4, 5 and 6 are not delegated on purpose: they are one authored
artefact each, and three agents editing `lib/` in parallel is a merge
problem, not a speedup.
