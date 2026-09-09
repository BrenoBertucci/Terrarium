# The Poke Mart, rebuilt

Art direction for the MART interior (`VIRIDIAN_MART` and its seven twins), to
replace `lib/RoomKit.lua`'s `case` / `rack` / `booth` / `counter` / `worktop`.
The quality bar is `lib/CryptKit.lua`, and the vocabulary is its: one model
per PLACEMENT chosen by a signature string, phantom voxels so a run of cells
reads as one object, a dollhouse height cut authored per cell row, lamps at
the point the shader burns its light, and the light doing the colouring
because the atlas has no colour to give.

This file is a spec, not a plan. Everything in it is either a measured
number, a number derived from one, or marked `GUESS`.

---

## 0. What the room actually is

`python tools/interior_plan.py VIRIDIAN_MART`, against the shipped data:

```
tileset=MART   4x4 blocks = 16x16 tiles = 8x8 cells = 128x128 world px
image=assets/generated/tilesets/pokecenter.png  128x48  perRow=16
walkable=[17, 26, 28, 60, 94]   warpTiles=[94]
warp -> LAST_MAP x=3 y=7        warp -> LAST_MAP x=4 y=7
objects: CLERK (0,5)  YOUNGSTER (5,5)  COOLTRAINER_M (3,3)
```

| cell row `cy` | tile rows | cell cols | what stands there |
| --- | --- | --- | --- |
| 0-1 | 0-3 | 0-1, 6-7 | SALE display cases (`40 / 78,79 / 76,77 / 23,29`) |
| 0-1 | 0-3 | 2-5 | glass drink coolers (`90,91 / 44,45 / 46,47 / 62,63`) |
| 2 | 4-5 | 0-1 | low display counter, north-west |
| 3-4 | 6-9 | 0-1 | clerk's booth: back panel + bottle shelf + counter NE corner |
| 3-4 | 6-9 | 4-5, 6-7 | two free-standing shelf racks (gondolas) |
| 5 | 10-11 | 1 | the cash register (a sprite since the `figures` pass) |
| 6 | 12-13 | 0-1 | the counter's south arm |
| 7 | 14-15 | 3-4 | the door out (mat tiles `12 / 28`) |
| everything else | | | floor checker (`1, 11, 17, 26, 27, 54`) |

Three facts that shape every decision below.

1. **The atlas has four colours and no more.** `pokecenter.png` is
   128x48 and its only pixel values are `#000000`, `#555555`, `#AAAAAA`,
   `#FFFFFF` (measured; 2250 / 1306 / 1203 / 1385 pixels respectively).
   Colour arrives at draw time from the SGB palette.
2. **Three of the four palette entries never change.** From
   `data/generated/palettes.lua` (measured):

   | palette | shade 0 | shade 1 | shade 2 | shade 3 |
   | --- | --- | --- | --- | --- |
   | VIRIDIAN | `#FFFFF7` | `#D6FFAD` | `#BDDEFF` | `#313131` |
   | PALLET | `#FFFFF7` | `#E6DEFF` | `#BDDEFF` | `#313131` |
   | CELADON | `#FFFFF7` | `#B5FFB5` | `#BDDEFF` | `#313131` |
   | LAVENDER | `#FFFFF7` | `#DEBDEF` | `#BDDEFF` | `#313131` |
   | CINNABAR | `#FFFFF7` | `#FF7B73` | `#BDDEFF` | `#313131` |
   | VERMILION | `#FFFFF7` | `#FFCE84` | `#BDDEFF` | `#313131` |

   Shade 1 is the TOWN, and the Mart inherits it. A product colour picked
   out of shade 1 is pale green in Viridian and salmon red in Cinnabar.
   Only `#FFFFF7`, `#BDDEFF` and `#313131` are stable across the eight
   Marts.
3. **There are no side walls, no south wall and no ceiling in the data.**
   The floor checker runs to the map edge on the east, west and south. The
   ring has to be invented, exactly as `lib/CryptKit.lua` invented the
   crypt's octagon out of a wall-panel drawing. See section 2.4.

---

## 1. Reference survey

### 1.1 What later generations kept

Poke Mart interiors were redrawn four times and three things survive every
redraw. These are the shape of the room, not decoration, and the rebuild
should not lose any of them.

- **The service counter is the first thing you meet and the clerk is
  behind it, facing you.** Every generation puts the transaction at a
  counter with a standing clerk. Gen IV split it into two clerks at one
  counter -- "the one on the right sells standard adventure items and is
  the same in any town, while the one on the left sells goods unique to
  that location" -- which changed the count, not the fixture
  ([Bulbapedia](https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9_Mart),
  [Pokemon Wiki](https://pokemon.fandom.com/wiki/Pok%C3%A9_Mart)).
- **Stock is on the wall behind the clerk and on free-standing racks in
  front of him.** The player never touches the stock; it is scenery whose
  entire job is to say "shop". This is why the racks can be dense: nothing
  in them is interactive.
- **The room is small, bright, and one look wide.** From Gen V on the Mart
  is folded into the Pokemon Center, "to the right of the entrance", which
  shrank it to a counter and a wall of shelving -- and the shrink did not
  cost it its identity, which tells you the identity is the counter plus
  the stocked wall, not the floor area
  ([Bulbapedia, Pokemon Center](https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9mon_Center)).

What changed: the standalone blue-roofed building disappears after Gen IV
(the roof is the exterior identifier through
RSE/FRLG/DPPt); the clerk count goes 1 -> 2 -> 1; from Gen VI the room
gains real depth and real light fixtures because the renderer gained them.
Alola's Thrifty Megamart is the one late-generation *standalone* shop and it
is drawn as a supermarket, not a konbini.

Honest limit: none of the wiki sources describe fixtures per generation in
enough detail to model from. Everything below the fixture level is taken
from real convenience-store references, not from screenshots I could verify.

### 1.2 What a konbini actually looks like

The shipped floor plan is already a konbini planogram, which is the single
most useful finding here -- the 1996 artist drew a Japanese convenience
store and the rebuild should lean into it rather than invent a Western
pharmacy.

- **Cold drinks are in glass-door reach-in cabinets along the BACK wall,
  restocked from behind.** The plan puts the coolers at cell row 0-1,
  columns 2-5 -- the back wall, dead centre, the widest single run in the
  room. That is the konbini rule exactly
  ([Voyapon](https://voyapon.com/the-konbini-japan/),
  [byFood](https://www.byfood.com/blog/culture/guide-to-konbini-japanese-convenience-stores)).
- **Print, small goods and the register cluster near the entrance.** The
  plan puts the register at cell (1,5) and the counter's south arm at cell
  row 6 -- both within two cells of the door.
- **The lighting is uniform, cool and bright, and it is the dominant
  visual.** "Bright fluorescent lights illuminate rows of meticulously
  stocked shelves". A konbini has no pools of light and no dark corners;
  it is the exact inverse of the crypt, and the lighting plan in section 5
  inverts the crypt's numbers deliberately
  ([Konbini UX, Bootcamp](https://medium.com/design-bootcamp/konbini-ux-why-japanese-convenience-stores-are-a-design-masterpiece-90bc60c1f64a)).
- **Gondolas are low enough to see across.** This is why a konbini reads
  as open despite being tiny, and it is the single most important number in
  section 2.

### 1.3 Real fixture dimensions (the source of every number in section 2)

| fixture | real | source |
| --- | --- | --- |
| gondola, convenience store | 54 in = 1.37 m tall | [Rack Leaders](https://rackleaders.com/gondola-shelving-dimensions-guide/) |
| gondola, supermarket | 72 in = 1.83 m tall | same |
| gondola base deck | 16 / 19 / 22 / 24 in deep | [Value Vault](https://www.gondola-shelving.com/blogs/blogs/gondola-shelving-size-guide-heights-depths-backs-more) |
| gondola upper shelves | 10-19 in, 2-4 in shallower than the base ("waterfall") | same |
| gondola upright pitch | pre-drilled at 1 in | same |
| full-height glass merchandiser | 78-84 in tall, 24-79 in wide | [ProCool](https://procoolmfg.com/commercial-fridge-dimensions/) |
| one reach-in glass door | 27-29 in wide | [Restaurant Warehouse](https://therestaurantwarehouse.com/blogs/restaurant-equipment/commercial-refrigerator-dimensions-guide) |
| cooler total depth | 27 in shelving + 15 in coils = 42 in | same |
| sales counter, max | 38 in = 0.965 m | [US Access Board, ch. 9](https://www.access-board.gov/ada/chapter/ch09/) |
| accessible counter portion | 30 in long min, 36 in high max, with knee/toe space | [UpCodes 904](https://up.codes/s/check-out-aisles-and-sales-and-service-counters) |

---

## 2. The voxel scale spec

### 2.1 The scale, fixed

`Voxel3D.casterMatrix` builds a character as a 16x16 quad with its feet at
`y = 0`. So:

> **A person is 16 voxels tall. One cell is 16 voxels is 16 world px.
> One voxel is therefore about 10 cm** (a 1.60 m person; the mod's
> characters are children and adults alike, so 10 cm is the round number
> to build against).

Every dimension below is (real metres / 0.10), rounded to a voxel, then
sanity-checked against the 16-voxel person.

### 2.2 The table

| element | voxels | derivation | notes |
| --- | --- | --- | --- |
| **ceiling** (implied plane) | **26** | 2.6 m konbini sales floor `GUESS` | never drawn -- see 2.5 |
| wall cornice | **2** courses at y 24-25 | matches `RoomKit`'s existing two-course cornice | the only thing that says "ceiling" |
| back wall total height | **26** | to the implied plane | |
| **gondola unit** | **14** | 54 in = 1.37 m | shorter than a person, deliberately: this is what makes a konbini read as open |
| gondola kick | y 0-1 | | |
| gondola base deck, top at | y **2** | | deck 6 voxels deep (22 in) |
| gondola shelf boards, tops at | y **6**, y **10** | 40 cm pitch | 5 voxels deep (18 in, the waterfall) |
| gondola top cap / price rail | y **13-14** | | 1 voxel proud on both faces |
| gondola board thickness | **1** | | |
| gondola product tiers | 3 (y 2-6, 6-10, 10-13) | | |
| gondola depth, total | **12** (6 per rank, back to back) | 2 x 22 in = 1.12 m | its 32 px footprint is 3.2 m; do NOT fill it -- centre the 12 and read the rest as aisle |
| **cooler cabinet** | **22** | 84 in = 2.13 m | incl. a 1-voxel header |
| cooler depth | **12** | 42 in = 1.07 m | leaves 20 px of back wall behind it |
| cooler kick / base | y 0-2 | | |
| cooler glass pane | y **3-18** (16 tall), **1 voxel thick** | | set back 2 voxels inside a 2-voxel frame |
| cooler door mullion | 1 voxel wide, every **8** voxels | 29 in door = 7.4 vx | 8 doors across the 64-px cooler bay |
| cooler interior shelves | 4, at y 4, 8, 12, 16 | | 8 voxels back from the glass |
| cooler header fascia | y **22-25**, 2 voxels proud | | the only signage in the room -- see 2.5 |
| **checkout counter top** | **10** (slab at y 8-9) | 0.965 m ADA max = 9.6 vx | overhangs the front by 1 |
| **counter toe kick** | **2** tall x **2** deep | real 4 in x 3 in = 1 x 1 | doubled for readability at 27 deg; say so rather than pretend |
| counter body | y 2-7 | | |
| SALE display case | **20** | shorter than the coolers so the back wall has a silhouette | |
| clerk's booth back panel | **20** | | |
| booth bottle shelf | y 20-25 | | above the panel, against the wall |
| **door frame jambs** | **21** tall, 2 wide | 2.0 m door | **no lintel** -- see 2.5 |
| **hanging aisle sign** | does not exist | | see 2.5; the fascia replaces it |
| the south sill | **5** | | the dollhouse lip the camera looks over |

Conflict to resolve at build time: `data/voxel_heights.lua` pins
`standH = 12` on every MART counter template and `lib/RoomKit.lua`'s
`counter` returns `ytop = 11`. This spec puts the counter at 10. The model
declares its own `standH` (`Buildings.lua:1653`), so change both together
or the register sprite floats two voxels.

### 2.3 The camera, and the one number the cut comes from

The dollhouse cut only means anything under an authored `fixed` shot. The
Mart has no entry in `data/camera_shots.lua` today, so it gets
`MarioCam.modes.close` -- a player-driven orbit -- and a cut wall seen from
the north is a sawn-off wall. **Author the shot first.** Following the
`POKEMON_TOWER_1F` family:

```lua
VIRIDIAN_MART = {
  { x = 64, z = 64, bx = 64, bz = 64, mode = "fixed",
    camX = 64, camY = 104, camZ = 248, focY = 10,
    fov = 38, frames = 12, flat = true },
},
```

Derivation: the room is 128x128 world px, centre (64, 64). To frame 8 cells
plus a margin in a 38-degree lens needs `72 / tan(19 deg) = 209 px` of
distance; held at the Tower's pitch that puts the eye at
`z = 64 + 209*cos(27) = 248`, `y = 10 + 209*sin(27) = 104`.

Eye to focus: `dy = 94`, `dz = 184`. Pitch above horizontal
`atan(94/184) = 27.1 deg`, the same family as the Tower's floors.

> **k = tan(27.1 deg) = 0.511.**
>
> A thing of height `H` whose south face is at `z_s` hides the floor from
> `z_s` back to `z_s - H/k`. **One voxel of height eats 1.96 world px of
> floor behind it -- one eighth of a cell per voxel.**

Everything in 2.4 and 2.5 is that one line applied.

### 2.4 The dollhouse cut

`lib/Crypt.lua` shape, exactly (`Crypt.heightFor`: a tall band, a ramp, a
floor value):

```lua
Shop.CEIL  = 26                 -- the implied ceiling; the tall band
Shop.SILL  = 5                  -- the south lip the camera looks over
Shop.BANDS = { [3] = 22, [4] = 17, [5] = 12, [6] = 10, [7] = 5 }

function Shop.heightFor(id, cy)
  cy = tonumber(cy) or 0
  if cy <= 2 then return Shop.CEIL end
  return Shop.BANDS[cy] or Shop.SILL
end
```

It caps EVERYTHING in the row -- the invented perimeter wall and the
furniture alike -- so a piece of stock that outgrows its row gets cut, the
way a crypt wall does. Checked against `k = 0.511`:

| `cy` | cap | hides floor back to | what that costs |
| --- | --- | --- | --- |
| 0-2 | 26 | z = -3 | nothing: the back wall has nothing behind it, and the side walls at these rows only clip the back wall's far bottom corners (1.5 voxels) |
| 3 | 22 | z = 21 | the side walls clip the back wall's bottom 5.6 voxels at the frame's two edges |
| 4 | 17 | z = 47 | 33 px, inside the gondola's own north cell |
| 5 | 12 | z = 72 | 24 px; touches the gondola's kick to y = 3.8 at the frame's edges |
| 6 | 8 | z = 96 | exactly one cell -- the counter's own |
| 7 | 5 | z = 118 | 10 px, less than a cell |

Two named exceptions, both single props at the frame's left edge:

- the **register** (6 voxels on a 10-voxel counter = 16) breaks the cap of
  12 at `cy = 5`. Allowed: it is one cell wide and what it hides is the
  counter behind it, which is its own object.
- the **door jambs** (21) break the cap of 5 at `cy = 7`. Allowed because
  they are 2 voxels wide; see the next section for why the LINTEL is not.

Rows the cut does not reach: the north wall (`cy` 0-1) is full 26 because
nothing stands behind it. The east and west walls take the ramp for the
same reason the crypt's do -- their near ends would otherwise rise into the
bottom corners of the frame and box the shot in.

The ramp between cells, the coping course and the rag are all
`lib/CryptKit.lua`'s and should be lifted unchanged: a cell's top ramps to
the mean of its neighbours' heights so the cut is continuous across the
seam, and the top course stays whole through the wall's thickness.

### 2.5 The rule that surprised me: hang nothing

Apply `k = 0.511` to anything suspended from the implied ceiling. A sign
whose bottom edge is at height `y_b` and whose south face is at `z_s` hides
the floor from `z_s` back to `z_s - y_b/k`, and hides everything standing
in that band below the descending ray.

| sign at | bottom `y_b` | hides the floor back to | verdict |
| --- | --- | --- | --- |
| `cy` 6 (z 96-112) | 20 | z = 73 | swallows the whole aisle mouth |
| `cy` 5 (z 80-96) | 20 | z = 57 | swallows the gondola's front rank |
| `cy` 2 (z 32-48) | 22 | z = -5 | swallows the back wall below y = 8.9 |

**There is no height at which a suspended element is free at this pitch.**
So:

- **no hanging aisle signs.** The signage moves onto the back wall as the
  **cooler header fascia** (y 22-25, 2 voxels proud of the wall face,
  running the full 4-cell cooler bay). This is a real konbini fixture --
  the lit strip above the reach-in doors -- and it costs zero occlusion
  because it is in the wall's own plane.
- **no door lintel.** Two jambs, 2 wide and 21 tall, and the mat. A 2-voxel
  lintel at y 19-21 across a 32-px bay would hide `21/0.511 = 41 px` --
  two and a half cells -- of the room's entry aisle.
- **no ceiling plane.** The camera sits at y = 104, above a 26-voxel
  ceiling, so it would see the ceiling's TOP: an opaque lid over the whole
  room. The ceiling is implied by the cornice, the fixtures hanging in air,
  and the fall-off of light -- the same answer `RoomKit.kinds.pillar`
  already gives ("the ceiling it holds up is implied, not drawn").
- a **second price rail** is allowed on the gondola's own top cap (y 13-14,
  1 voxel proud) because it stands ON the object it labels.

---

## 3. The palette

### 3.1 How colour gets into the room at all

The atlas is four greys and the SGB palette is out of the kit's hands. So,
as in the crypt: every template composites a **palette row** above its
drawing (`topRows = { { 0, 71 } }` -- tile `$00` all white, tile `$47` all
black, the two texels every recolour leaves alone) and the model picks
texels out of that row, one per material class. The colours below are the
**target on-screen values under the Viridian palette**; the geometry
reaches them through a per-class shade factor and, for the floor, through a
`FloorArt` photo material.

Two hard limits on the class table, both from `lib/CryptKit.lua`:

- one palette row is 8 sprite rows x 16 columns; columns 0-7 are white,
  8-15 black. So there are at most 64 white classes and 64 black classes.
- **any two classes that meet along a face-run must sit at least two atlas
  columns apart**, or the greedy merge (which folds *consecutive* atlas
  texels into one strip) fuses them. CryptKit uses columns 0, 2, 4, 7 in
  row 0 and 0, 2, 4, 6 in row 1: four per row. Thirteen classes is two
  rows and a bit -- fine.

### 3.2 The classes

| class | target hex | shade factor | emissive | notes |
| --- | --- | --- | --- | --- |
| `floorTile` | `#E9E5DB` | -- | no | not a model texel; `FloorArt` profile, see 3.4 |
| `floorGrout` | `#C4BFB4` | -- | no | the joint; comes from the photo, NOT from the tileset checker |
| `wallPaint` | `#F1EDE3` | 0.92 | no | |
| `ceilPanel` | `#DAD5CA` | 0.78 | no | the cornice's underside band |
| `diffuser` | `#FFF8E3` | **1.30** | **yes** | the fluorescent panel's face |
| `steelUpright` | `#98A0A8` | 0.66 | no | gondola posts, cooler frame ribs |
| `shelfBoard` | `#D9D5CB` | 0.86 | no | |
| `counterTop` | `#E2DAC7` | 0.90 | no | warm laminate |
| `counterKick` | `#45423E` | 0.22 | no | black class |
| `coolerFrame` | `#8A9197` | 0.70 | no | anodised aluminium |
| `coolerGlass` | `#BDDEFF` | **1.05** | **yes** | the palette's own shade 2, used literally -- it is `#BDDEFF` in every town |
| `coolerGlow` | `#D2E9FF` | **1.18** | **yes** | the cabinet interior behind the glass |
| `fasciaSign` | `#F5F2E8` | **1.02** | **yes** | lettering in `#2C4CA8` |

Product labels (six, tinted on the model rather than picked out of the
drawing -- see the ugliness list, item 7):

| product | hex |
| --- | --- |
| Potion | `#F2603F` |
| Super Potion | `#F08A3C` |
| Poke Ball | `#E5372E` over `#F4F4F2` |
| Antidote | `#6FBF73` |
| Repel | `#F0C33C` |
| TM box | `#6873C9` |

### 3.3 The light-per-class block, in CryptKit's terms

```lua
Shop.SHADE = { wallPaint = 0.92, ceilPanel = 0.78, diffuser = 1.30,
               steelUpright = 0.66, shelfBoard = 0.86, counterTop = 0.90,
               counterKick = 0.22, coolerFrame = 0.70, coolerGlass = 1.05,
               coolerGlow = 1.18, fasciaSign = 1.02, label = 1.00 }
Shop.SIDE = 0.94            -- flatter than CryptKit.SIDE (0.90): bounce-lit
Shop.FOOT = 1.04            -- INVERTED from CryptKit.FOOT (0.84)
Shop.FADE_FROM, Shop.FADE_TO = nil, nil   -- no vertical fade
```

The two inversions are the whole difference in tone between the crypt and
the shop and they should be written down as such:

- `CryptKit.FOOT = 0.84` darkens the lowest course because a crypt's floor
  is stone and eats light. A konbini's floor is pale and polished and
  bounces it, so the shop's foot **lifts**.
- `CryptKit.FADE_FROM = 28 / FADE_TO = 0.05` climbs the far walls out of
  the light so no ceiling is needed. A shop is brightest at the ceiling.
  There is no fade; the cornice band is the top of the light, not the
  bottom.

### 3.4 The floor

A third entry in `FloorArt.PROFILES`, beside `passage` and `crypt`:

```lua
{ name = "shop", tilesets = { "mart" }, file = "shop.jpg",
  normal = "shop_n.jpg", wrap = "repeat",
  scale = 192, mix = 0.88, yMax = 1.5,
  keys = { { { 0.30, 0.30, 0.30 }, { 1, 1, 1 } },
           { { 0.30, 0.30, 0.30 }, { 1, 1, 1 } } } }
```

- `tilesets = { "mart" }` -- the tileset **id** is `MART` even though the
  image is `pokecenter.png`. Matching on the image name would also catch
  every Pokemon Center. (This is the gate the water pass got wrong; see
  memory `terrarium-water-placement`.)
- `scale = 192` rather than the crypt's 256: a 60 cm terrazzo tile at
  10 cm/voxel is 6 world px, and 192 px per cycle over a 32-tile photo
  puts the tile grid at the right size for a 128-px room.
- `yMax = 1.5` matters more here than in the crypt. The shader's floor
  branch is gated `vUp > 0.5 && vWorld.y < floorYMax`, and the counter top
  (y = 8-9) and the gondola boards (y = 2, 6, 10) are all up-facing and all
  white-ish. Without the cap they take the terrazzo.
- source: a CC0 polished-terrazzo or pale vinyl from Poly Haven, prepped by
  `tools/prep_polyhaven.py` to the same mean the shader normalises against.
  Follow `assets/stone/README.md`: albedo, a DirectX tangent-space normal,
  and the drop-in contract (delete the file and the room falls back to the
  geometry's own tone).

---

## 4. Shelf content

`lib/RoomKit.lua`'s `rack` sinks the goods **3 voxels** behind the board
(`t.shelfDepth or 3`) and calls the shelf stocked. At 27 degrees and 250 px
back, a flat drawing sunk 3 voxels is a striped board. Stock has to be
boxes.

### 4.1 Gondola, per tier

Each gondola face is 2 cells = 32 voxels wide. Per tier:

- **box footprint 3 wide x 3 deep**, height by tier: 4 voxels in the bottom
  and middle tiers, 2 in the top tier (short goods above eye level is the
  konbini habit and it opens the sightline over the unit).
- **1 voxel of gap** between facings -> `32 / 4 = 8 facings per tier`.
- **runs of 3 identical facings**, then a change: 3 + 3 + 2 across the
  eight. Real planograms repeat a SKU 2-4 times before changing; one facing
  per SKU reads as confetti and eight of one reads as a wall.
- **depth jitter 0-2 voxels** per facing off a cell hash. A shelf where
  every box is flush with the board front is a printed board with a bevel.
  This is the single cheapest thing that makes the rack read as stocked.
- **the box's front face is the label class**; its two flanks and top are
  `shelfBoard` held down. A box coloured on all six faces reads as a
  plastic brick.

Per gondola: 3 tiers x 8 facings x 2 faces (it is double-sided) = 48 boxes,
about 48 x 36 = 1.7k voxels before culling. Two gondolas is affordable.

### 4.2 Coolers

96 individual bottles behind glass is not worth its voxels, and the glass
blurs them anyway. So:

- **only the shelf nearest eye height (y 8-12) carries real bottles**:
  2 wide x 3 tall x 2 deep, 3 columns per 8-voxel door, 1 voxel of gap.
  That is 24 bottles across the eight doors.
- **the other three shelves are colour BANDS**: a 1-voxel-deep card per
  shelf tier, painted in runs of 4-6 voxels in the six label colours plus
  `coolerGlow`. Behind glass at 8 voxels' depth this is indistinguishable
  from stock and costs a fortieth of the voxels.
- **the cabinet interior is `coolerGlow`, not black.** A reach-in is lit
  from inside; that is what makes the drinks wall the brightest object in
  the room, which is what makes it read as a konbini.

### 4.3 SALE cases and the booth

- SALE case (cells 0-1 and 6-7 of the back wall): the drawing already has a
  black display niche (tiles `76/77`). Sink it **4 voxels** (`RoomKit`
  already does `sink = { { 17, 22, 4 } }`), stand **6 boxes** in it at
  3x4x3 with 2 voxels of gap, and light the niche's back face at
  `coolerGlow * 0.8`. A lit recess in a wall is worth more than any amount
  of stock in front of it.
- Booth bottle shelf (y 20-25, above the panel): **10 bottles**, 2x4x2,
  1 voxel apart, alternating two label colours. This is the one shelf the
  player reads at eye height and it should be the most varied thing in the
  room.

---

## 5. Lighting

Same parameter names as `lib/Crypt.lua`, so the two rooms can be compared
line for line. The shop is the crypt's inverse in every one of them.

```lua
Shop.RADIUS = 84              -- vs Crypt.RADIUS 136: pools MUST overlap
Shop.POWER  = 1.5             -- vs Crypt.POWER 2.6: flat, not hot
Shop.HEIGHT = 24              -- world y of a diffuser
Shop.COLOR  = { 0.94, 0.97, 1.00 }   -- 5000 K at the rim of a pool
Shop.CORE   = { 1.00, 1.00, 0.98 }   -- near-white under the panel
Shop.LIMIT  = 8                      -- the shader's lamp slots. Hard.
Shop.COOL   = { 0.98, 1.00, 1.02 }   -- vs Crypt.COOL { 0.90, 0.93, 1.10 }
ambient     = 0.86                   -- vs Crypt 0.35-0.62
```

`Shop.RADIUS = 84` against a 128-px room is deliberate: two adjacent
fixtures 32 px apart both reach every point between them, so the shader's
saturating sum `x/(1+1.6x)` lands the whole floor near its ceiling and the
room is evenly lit. **A konbini has no dark between the lights, and that is
the one thing the crypt's numbers must not be reused for.**

### 5.1 The fixtures, in cell coordinates on the 8x8 grid

Seven ceiling panels plus one case light -- exactly the eight slots, so
nothing pops as the shot pans.

| # | cell (cx, cy) | y | kind | radius | power | colour |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | (2, 1) | 24 | ceiling panel | 84 | 1.5 | `COLOR` |
| 2 | (5, 1) | 24 | ceiling panel | 84 | 1.5 | `COLOR` |
| 3 | (1, 3) | 24 | ceiling panel | 84 | 1.5 | `COLOR` |
| 4 | (6, 3) | 24 | ceiling panel | 84 | 1.5 | `COLOR` |
| 5 | (3, 5) | 24 | ceiling panel | 84 | 1.5 | `COLOR` |
| 6 | (6, 5) | 24 | ceiling panel | 84 | 1.5 | `COLOR` |
| 7 | (1, 6) | 24 | ceiling panel, over the checkout | 84 | 1.6 | `COLOR` |
| 8 | (4, 0) | 12 | the cooler interior | 40 | 0.9 | `#D2E9FF` |

1 and 2 sit over the drinks wall on purpose: the brightest thing in a
konbini is the cold case, and the fixture over it is what sells that.

Like `Crypt.MAPS`, the site list is authored per map and read **twice** --
once by the scene for the shader's point lights, once by the kit to stand
the fixture geometry at exactly the point the light burns. A pool of light
without a fixture over it is the failure mode `lib/Crypt.lua` names in its
own header.

### 5.2 The fixture, as geometry

A 4-voxel-wide, 12-voxel-long, 2-voxel-deep box hanging at y 23-24: a
`steelUpright` rim one voxel wide all round, the underside `diffuser`, two
short stems up to the implied ceiling at y 26. Long axis east-west, along
the aisles, which is both the real convention and what section 6 needs.

### 5.3 The rest of the air

```lua
Shop.SPEC   = 0.72                 -- vs Crypt.SPEC 0.55: the floor is polished
Shop.MIST   = { amount = 0 }       -- no. A shop with haze in it is a fire.
Shop.AO     = { power = 1.30, range = 10 }   -- vs Crypt { 1.75, 12 }
Shop.SHADOW_SCALE = 0              -- no sun indoors, same as the crypt
Shop.BLOOM  = { threshold = 0.90, strength = 0.30, div = 4, passes = 1 }
Shop.GRADE  = { exposure = 1.0, vignette = 0.22, grain = 0.008,
                tone = 0.30, split = 0.30 }
Shop.RAYS   = nil                  -- no god rays off a ceiling panel
```

`threshold = 0.90` rather than the crypt's 0.82 is not a taste call. At
`ambient = 0.86` a threshold of 0.82 puts the walls, the floor and every
shelf board over the bloom line and the frame goes to milk. The only things
that should bloom are the four emissive classes.

`AO power 1.30` rather than 1.75: `lib/Crypt.lua` records walking that
number down from 2.9 to 2.0 to 1.75 as the wall's stones stood proud,
because harder AO "turned every joint into a black stain". The shop has far
more 1-voxel edges than the crypt -- every shelf board, every mullion,
every box gap -- so it needs to start lower still, and a bright bounce-lit
room genuinely has softer corners.

---

## 6. The glossy floor

A polished floor is the strongest "this is not a 2D room" cue available
here, and it is worth getting right. Constraints: OpenGL ES 2 / GLSL 1.20,
no dynamic loops with non-constant bounds (GLSL ES 1.00 requires the loop
bound to be a constant expression --
[Khronos, public_webgl](https://www.khronos.org/webgl/public-mailing-list/public_webgl/1012/msg00063.php);
[GLSL ES 1.0.17 spec, Appendix A](https://docs.nvidia.com/drive/active/5.0.10.3L/nvvib_docs/NVIDIA%20DRIVE%20Linux%20SDK%20Development%20Guide/baggage/GLSL_ES_Specification_1.0.17.pdf)),
no MRT, no vertex texture fetch without a unit, and -- the binding one here
-- **the fragment stage is already at ten samplers where GLES2 guarantees
eight**, which is why `lib/Voxel3D.lua` has a compatibility LADDER whose
`no-crypt` rung drops `CRYPT_MATS` entirely.

### What is already in the tree

- `derivativesOK()` (`Voxel3D.lua:2583`) gates `#define LAMP_NORMALS`, and
  `faceNormal()` builds a real per-pixel face normal from
  `cross(dFdx(vWorld), dFdy(vWorld))`, turned toward the eye. Exact on
  voxel geometry, since every face is a plane.
- under `CRYPT_MATS`, the floor branch
  (`floorArtOn > 0.5 && vUp > 0.5 && vWorld.y < floorYMax`) already reads
  `floorNorm` into `N` and sets `gloss = 26.0; specK = lampSpec * 1.1;
  matHit = 1.0`.
- `localLamp()` already computes a Blinn-Phong lobe off that `N` with a
  Fresnel lift (`0.30 + 0.70 * pow(1 - dot(N,V), 3)`), **per lamp, eight
  lamps unrolled by hand, no loop**.
- `RayFX` already has a real SSR march and a classification channel:
  `Voxel3D.beginAlphaStamp` writes `PUDDLE_TAG = 254/255` into the scene
  buffer's alpha with the colour write masked off, and `RayFX` reads it
  back at a tolerance of `PUDDLE_TAG_W = 0.002` (half an 8-bit step).

So the question is not "how do we build a reflection", it is "which of
three things already in the tree do we point at the floor".

### T1 -- mirrored geometry (planar reflection by re-drawing)

Draw the room's meshes a second time through `Mat4.scale(1, -1, 1)` before
the floor, then draw the floor over them at alpha < 1.
`Voxel3D.draw(mesh, tex, model)` already takes a model matrix and `Mat4`
already has `scale`, so this needs **no shader change at all**.

*Cost*: doubles the interior's draw calls and vertex work. An 8x8-cell room
is the cheapest thing in the game, so it is affordable here -- and nowhere
else, which makes it a technique that cannot generalise.

*Failure modes*:
1. **Nothing clips it.** GLES2 has no user clip planes. The mirrored copy
   extends below the room's footprint, so a reflected gondola appears
   hanging under the map edge where there is no floor to be in. The fix is
   a `discard` on `vWorld.y > 0` in the fragment stage, which defeats
   early-Z on every tiler this ships to.
2. **The winding flips.** A negative-determinant matrix inverts the face
   winding; back-face culling then drops the whole mirrored copy. The cull
   has to be inverted for that one draw and restored after, which is
   exactly the kind of state that leaks (see `Crypt.drawWorldBody`'s
   save/restore of blend mode and `Voxel3D.flatten`).
3. **The payoff is small.** A mirror at 27 degrees shows what is 27 degrees
   above the floor on the far side of it -- which in this room is mostly
   dark air, because there is no ceiling. You would pay double the geometry
   for a reflection of the underside of the gondolas.

### T2 -- SSR through the existing `RayFX` tag

Stamp the shop floor into the alpha channel with a second tag beside
`PUDDLE_TAG` (253/255 is the next value clear of the 0.002 tolerance) and
give the shop its own pair beside `RayFX.PUDDLE_AMOUNT = 0.96` /
`PUDDLE_FRESNEL = 0.62`.

*Cost*: one extra draw of the floor meshes with the colour write masked to
alpha. The march itself already runs.

*Failure modes*:
1. **It is a graphics row, and a room's identity must not be.** The pass
   only exists at RTX `RT` and `MAX`; at `OFF` the readable depth buffer is
   not even allocated, and `beginAlphaStamp` correctly returns false. A
   player at OFF would get a matte floor and a different room.
2. **The rays leave the screen.** SSR can only reflect what is rasterised.
   Looking north and down, the reflection of the back wall lands in floor
   the camera can see -- that part works -- but the reflection of anything
   near the bottom of frame marches straight off the screen edge within a
   few steps and falls back to the sky, which indoors is nothing.
3. **Flat mirrors skip.** `RayFX`'s own notes record this: a coarse march
   at a grazing angle "landed on whichever step overshot it, so a reflected
   tree came back as a column of slabs", and it took four bisections to
   fix. A dead-flat shop floor is the worst case for that, worse than the
   pond it was tuned on.

### T3 -- analytic emitter reflection (the light bars in the floor)

Reflect only the things whose positions are already known: the seven
ceiling panels and the cooler. A specular highlight from a lamp **is** its
reflection; the only reason the crypt's floor does not read as polished is
that its lobe is broad (`gloss = 26.0`) and round.

The change, in full:

1. give the shop's floor branch a **tight lobe** (`gloss` ~180 instead of
   26) so the highlight is a reflection rather than a sheen;
2. make it **anisotropic**, because a fluorescent fixture is a bar and not
   a point: scale the half-vector's component along the fixture's long axis
   (east-west, fixed by section 5.2) before the `pow`. Two extra ALU ops;
3. raise `lampSpec` via `Shop.SPEC = 0.72`.

*Cost*: a handful of ALU on floor fragments only. **No new sampler** --
which is the decisive constraint, because the shader is already at ten and
the `no-crypt` rung exists to survive drivers that refuse it. No new pass,
no new render target, no loop, nothing that can fail to link.

*Failure modes*:
1. **It reflects lights and nothing else.** A shopper standing on the floor
   has no reflection. The floor reads "waxed", not "mirror". This is the
   real cost and it should be accepted rather than papered over.
2. **It dies where derivatives do.** `Voxel3D.lua:3223` sends
   `(Voxel3D.normalsOK and Voxel3D.lampNormals) or 0` and the same for
   `lampSpec`, so on a driver where `derivativesOK()` is false both are
   zero and the floor is flat-shaded. The fallback must be a **baked sheen
   in the floor albedo**, never a black floor.
3. **Too tight and it is spotlights.** Without the anisotropic stretch, a
   `gloss` of 180 turns each panel into a hard dot and the floor looks like
   it has downlights in it. The stretch is not polish, it is the feature.

### Recommendation: T3

Because it is the only one of the three that survives the ladder. It
degrades in two named steps and never degrades to wrong:

| rung | what the floor does |
| --- | --- |
| `full` / `no-vtf`, derivatives OK | relief from `floorNorm` into `N`, tight anisotropic lobe off the real face normal -- a polished floor with the light bars stretched into it |
| `no-crypt` (no `floorNorm`) | `localLamp`, `gloss` and `specK` all live **outside** `#ifdef CRYPT_MATS`; the lobe still runs, off the flat `vUp` normal. A clean unrelieved gloss |
| no derivatives | `lampSpec` is held at 0. Baked sheen in the albedo, matte geometry |

T2 stays where it is -- it belongs to rain, and pointing it at an interior
buys a room that changes identity with a graphics row. T1 is worth exactly
one thing: the **cooler's glass**, which is a small, vertical, single-plane
reflector where a mirrored copy of the two nearest gondolas would be cheap,
correctly clipped by the pane's own quad, and actually visible. Consider it
separately, after the floor ships.

---

## 7. What would make this ugly

Every item is a failure this codebase has already had once.

1. **White seams down the cooler run.** `lib/CryptKit.lua`'s founding
   problem: "the ring used to be sixteen-pixel crates: each cell emitted
   its four sides in full and every seam where a neighbour was shorter, or
   carved differently, showed as a lit strip with a black core behind it."
   The fix is `Buildings.PHANTOM` -- the neighbour's voxels answered to the
   hidden-face test and never drawn, **computed by the same formula on both
   sides**. The shop makes this worse than the crypt did: a seam between
   two cooler cells falls exactly where a mullion belongs, so it looks
   deliberate until the light moves across it and it lights differently
   from the mullions either side. The back wall is 8 cells of one run; the
   cooler bay is 4; each gondola is 2. All three must phantom.
2. **A phantom that disagrees by a voxel.** Related and nastier. If the
   phantom is computed from the template's own tile instead of from the
   signature, two adjacent cells with different signatures disagree at the
   boundary and you get a hairline that no amount of AO tuning removes.
   The neighbour's masonry must come out of the same function.
3. **The striped board.** `RoomKit.kinds.rack` sinks a flat drawing 3
   voxels and calls it stock. At 27 degrees that is corduroy. Section 4 is
   the answer and its load-bearing part is the **depth jitter**, not the
   box count.
4. **The checker read as a pattern before it is read as a floor.**
   `CryptKit.graveModel`: "a checker of white and grey on a 16px stone is a
   pattern the eye reads before it reads the stone." The Mart's floor tiles
   (`1/11/17/26/27/54`) are a checker at 16 px, and at 250 px back with a
   38-degree lens that is a moire. The floor's tone comes from the photo;
   the checker survives only as a faint grout line, if at all.
5. **Two grids over one photograph.** `CryptKit`'s `ashlar` steps aside
   entirely when the photo is on, because "the picture is not ruled over
   with a second grid". Same rule: if the floor gets terrazzo art, it does
   not also get the tileset's lattice, and if the wall gets a paint
   material it does not also get drawn panel joints.
6. **A sun in a room with no windows.** `Crypt.SHADOW_SCALE = 0` and
   `CryptKit.SIDE = 0.90` exist because the emitter's own shading is "a sun
   standing to the south; there is no sun in here". Leave the sun pass on
   and every gondola gets a hard bright south face and a dark north face
   from a light that does not exist, and no amount of lamp work will
   recover it.
7. **Product colour picked out of the drawing.** The Mart's grey shade 1 is
   the TOWN: `#D6FFAD` in Viridian, `#FF7B73` in Cinnabar, `#FFCE84` in
   Vermilion. A Potion box coloured by picking a drawing texel is green in
   one town and red in another. Labels must come out of the all-white
   palette-row column and be tinted by the model.
8. **Two classes fused by the greedy merge.** Classes that meet along a
   face-run must be at least two atlas columns apart. Put `shelfBoard`
   next to `steelUpright` in the palette row and every gondola's post
   merges into its board.
9. **Bloom at the crypt's threshold.** 0.82 against `ambient = 0.86` blooms
   the whole room. This is a one-line mistake with a total effect.
10. **AO staining every shelf underside.** The crypt walked AO down twice
    for exactly this. A shop is thirty times as many 1-voxel edges.
11. **Anything hanging.** Section 2.5. If a hanging sign appears in a mock
    and looks fine, check it against `k = 0.511` before believing it -- it
    will look fine in a three-quarter authoring view and swallow the aisle
    in the shipped shot.
12. **The shot not authored.** Without a `fixed` entry in
    `data/camera_shots.lua` the room gets `MarioCam.modes.close`, a
    player-driven orbit, and the dollhouse cut becomes a sawn-off wall the
    moment the bearing swings north. Author the camera before the geometry;
    every number in section 2 is derived from it.
13. **An options row that appears to do nothing.** `CryptKit.setting:row()`
    calls `remesh()` (`ChunkMesher.invalidate()`) on every step because the
    geometry is decided at build time. A SHOP row that changes the kit
    without dropping the cached mesh is a row the player toggles and
    nothing happens.

---

## Sources

Poke Mart / Pokemon Center across generations:
[Bulbapedia, Poke Mart](https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9_Mart) *
[Bulbapedia, Pokemon Center](https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9mon_Center) *
[Pokemon Wiki, Poke Mart](https://pokemon.fandom.com/wiki/Pok%C3%A9_Mart) *
[Pokemon Wiki, Pokemon Center](https://pokemon.fandom.com/wiki/Pok%C3%A9mon_Center)

Konbini layout and lighting:
[Voyapon](https://voyapon.com/the-konbini-japan/) *
[byFood](https://www.byfood.com/blog/culture/guide-to-konbini-japanese-convenience-stores) *
[Konbini UX, Bootcamp](https://medium.com/design-bootcamp/konbini-ux-why-japanese-convenience-stores-are-a-design-masterpiece-90bc60c1f64a) *
[Immersive Branding](https://www.linkedin.com/pulse/immersive-branding-how-japanese-convenience-stores-d-oria-di-cirie)

Fixture dimensions:
[Rack Leaders, gondola guide](https://rackleaders.com/gondola-shelving-dimensions-guide/) *
[Value Vault, gondola sizes](https://www.gondola-shelving.com/blogs/blogs/gondola-shelving-size-guide-heights-depths-backs-more) *
[ProCool, commercial fridge dimensions](https://procoolmfg.com/commercial-fridge-dimensions/) *
[Restaurant Warehouse, reach-in dimensions](https://therestaurantwarehouse.com/blogs/restaurant-equipment/commercial-refrigerator-dimensions-guide) *
[US Access Board ch. 9](https://www.access-board.gov/ada/chapter/ch09/) *
[UpCodes 904](https://up.codes/s/check-out-aisles-and-sales-and-service-counters)

Reflection techniques and GLES2 limits:
[OpenGL archives, planar reflections with the stencil buffer](https://www.opengl.org/archives/resources/code/samples/advanced/advanced98/notes/node125.html) *
[Kilgard, reflections and shadows with stencil buffers (PDF)](https://courses.cs.duke.edu/spring15/cps124/classwork/14_buffers/stencil.pdf) *
[Vulkan tutorial, planar reflections](https://docs.vulkan.org/tutorial/latest/Building_a_Simple_Engine/Advanced_Topics/Planar_Reflections.html) *
[WillP GFX, screen space glossy reflections](https://willpgfx.com/2015/07/screen-space-glossy-reflections/) *
[Khronos public_webgl, GLSL loops and constant expressions](https://www.khronos.org/webgl/public-mailing-list/public_webgl/1012/msg00063.php) *
[GLSL ES 1.0.17 specification (PDF)](https://docs.nvidia.com/drive/active/5.0.10.3L/nvvib_docs/NVIDIA%20DRIVE%20Linux%20SDK%20Development%20Guide/baggage/GLSL_ES_Specification_1.0.17.pdf)

In-tree, read for this document: `lib/CryptKit.lua`, `lib/Crypt.lua`,
`lib/RoomKit.lua`, `lib/Voxel3D.lua` (`CRYPT_MATS`, `faceNormal`,
`stoneHemi`, `localLamp`, `derivativesOK`, the LADDER, `beginAlphaStamp`),
`lib/Buildings.lua` (`PHANTOM`, `emit`), `lib/RayFX.lua`,
`lib/FloorArt.lua`, `lib/MarioCam.lua`, `data/voxel_heights.lua` (`MART`),
`data/camera_shots.lua`, `data/generated/palettes.lua`,
`assets/generated/tilesets/pokecenter.png`, `assets/stone/README.md`.
