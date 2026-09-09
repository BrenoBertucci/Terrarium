# Dressing the Poke Mart

What to PUT IN the room, once `ART_DIRECTION.md` has decided how big it is
and where the camera stands. That file is the law on scale, camera and cut;
this one only chooses objects and colours and argues for an order to build
them in.

Nothing here re-derives a measured number. `1 voxel = 10 cm`, a person is
16 voxels, the shot is `fixed` at pitch 27.1 deg, `k = tan 27.1 = 0.511`,
and **nothing hangs**. Every real dimension below is given in cm and in
voxels (cm / 10, rounded), and every item is checked against the cut band
of the cell row it would stand in.

Anything not measured or not sourced is marked `GUESS` or `UNVERIFIED`.

---

## 0. The two measurements this document argues from

### 0.1 What the room looks like today, counted

`probe_out_shop/shop_room.png`, VIRIDIAN_MART, the shipped `fixed` shot.
The background was flood-filled away from the frame border and the room's
own 510,492 px (38.5% of a 1536x864 frame) counted:

| measure | today |
| --- | --- |
| room pixels with saturation < 0.10 | **75.0 %** |
| room pixels with saturation < 0.20 | 82.1 % |
| room pixels with saturation >= 0.30 | 9.7 % |
| room pixels with value >= 0.70 | **80.7 %** |
| room pixels in the TOP value decile (0.90-1.00) | **52.6 %** |
| room pixels with value < 0.30 | 8.0 % |
| single largest swatch, `#F8F8F8` | **25.2 %** of the room |
| next five swatches, all hue 60 +- 5, sat 0.06-0.09 | 20.8 % of the room |

So a quarter of the room is flat white and another fifth is five values of
one yellow-grey. **46 % of the room is one non-colour.** Half of it sits in
the top tenth of the value range; there is no midtone and no dark.

Per surface, mean colour over a sampled patch of the same frame:

| surface | measured mean | hue | sat | val |
| --- | --- | --- | --- | --- |
| north wall, above the fixtures | `#FCFAF4` | 44 | 0.03 | 0.99 |
| floor, open south-east | `#DDD8D0` | 36 | 0.06 | 0.87 |
| floor, centre aisle | `#BFB7AF` | 30 | 0.08 | 0.75 |
| floor, entrance apron | `#B9B5AF` | 36 | 0.05 | 0.73 |
| wall, inner face east | `#D1CEC7` | 42 | 0.05 | 0.82 |
| counter laminate top | `#C4C6BE` | 74 | 0.04 | 0.78 |
| gondola top tier | `#D4D5CA` | 65 | 0.05 | 0.84 |
| SALE case, right | `#D6DACE` | 79 | 0.06 | 0.86 |
| cooler glass | `#AAC0C8` | 195 | 0.15 | 0.78 |
| entrance mat | `#343943` | 219 | 0.22 | 0.26 |

Eight of the ten sit in hue 30-80 at saturation under 0.09. The only two
that break out are the cooler glass and the mat. That is the "flat beige",
quantified: not one beige, but **nine surfaces sharing one hue family, one
saturation, and a 0.25-wide value band.**

Of the 22.7 % of the room that is saturated at all (sat >= 0.15), the hue
budget is: orange 30-60 deg **7.4 %**, blue 210-240 deg **7.7 %**, cyan
180-210 deg 4.2 %, red 0-30 deg 1.6 %. Most of the blue is the entrance mat
and the character sprites, not the Mart's own blue.

### 0.2 Which faces the camera actually pays for

Eye `(64, 104, 248)`, focus `(64, 10, 64)`. View direction
`(0, -94, -184) / 206.6 = (0, -0.455, -0.891)`. Projected area of a face is
its true area times `|n . v|`:

| face | normal | `abs(n . v)` | note |
| --- | --- | --- | --- |
| **top** (up) | `(0, 1, 0)` | **0.455** | |
| **south** (toward the camera) | `(0, 0, 1)` | **0.891** | |
| east / west, at the frame's centre column `x = 64` | `(±1, 0, 0)` | **0.000** | exactly zero |
| east / west, at `x = 32` | | 0.153 | |
| east / west, at the frame's edge `x = 0` or `127` | | 0.296 | |
| north | `(0, 0, -1)` | 0 | never drawn |

Three consequences, and one correction to the intuition that "detail on a
tall vertical face is nearly invisible":

1. **A side face is worth nothing.** At the room's centre column it
   projects to exactly zero area, and even at the extreme edge it is a
   third of a south face. Never spend a voxel of detail on the east or
   west flank of a fixture. (`ShopKit`'s gondola already does this right:
   the depth jitter goes on the BACK of a facing, never the front.)
2. **A south face is the best pixel in the room** -- 1.96x a top face --
   *if it is the frontmost thing in its column.* The eye sits at y = 104
   against a 26-voxel ceiling, so it clears every fixture: in the shipped
   frame the coolers, both SALE cases, both gondolas, the counter, the
   register and the back wall above them are ALL simultaneously visible.
   Nothing in this room occludes anything except **floor**.
3. **So the thing "tall detail" loses to is not occlusion -- it is the
   cut.** Rows 3-7 are sliced at 22 / 17 / 12 / 10 / 5. Detail above those
   heights is not hidden, it is deleted. And the slice makes a **new top
   face** every time, which is why the wall coping and the south sill are
   large bright bands in every frame.

The practical ordering, then:

> **top faces are guaranteed** (nothing hangs, so nothing is ever above
> them) -- **south faces are the richest** -- **side faces are free to leave
> blank** -- **anything above its row's cap does not exist.**

And one area check that sets the whole priority list.

- Geometrically: unoccluded, the floor plane projects to
  `128 * 128 * 0.455 = 7,455` world-px^2. The north wall's visible band
  above the fixtures (4 voxels over the 64-px cooler bay, 6 over the two
  32-px SALE cases) projects to about `640 * 0.891 = 570`. Thirteen to one.
- Measured on the frame, by tone-matching the floor's own hue window
  (18-44 deg, sat 0.02-0.14) inside the room mask: **the visible bare
  floor is 22.3 % of the room under a strict value window and 29.4 % under
  a wide one** -- the light pools blow parts of it past value 0.93.

Call it a quarter to a third of everything the player sees. **No other
single surface in the room comes close, and it is empty.**

---

## 1. What a real konbini has on the floor that we do not

Cell rows and their caps, for the "fits?" column
(`ShopKit.BANDS`, `lib/ShopKit.lua:237`):

| `cy` | 0-2 | 3 | 4 | 5 | 6 | 7 |
| --- | --- | --- | --- | --- | --- | --- |
| z range | 0-47 | 48-63 | 64-79 | 80-95 | 96-111 | 112-127 |
| cap (voxels) | 26 | 22 | 17 | 12 | **10** | **5** |

> `ART_DIRECTION.md` 2.4 prints `[6] = 8`; `lib/ShopKit.lua:237` ships
> `[6] = 10`. The code is the one the frames were rendered from and the one
> used here. Reconcile the two files.

### 1.1 The elements that fit

Ordered by how much "real shop" they carry per voxel spent.

| # | element | real (cm) | voxels | key face | where it goes | cap there | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | **floor decal / floor graphic** | 30x30 / 61x61 / 61x91 | **3x3 / 6x6 / 6x9**, height **0** | top | entrance apron `cy 7`, aisle mouth `cy 6` | any | **BUILD.** Height 0 means zero occlusion cost anywhere in the room. Nothing else on this page is free. |
| 2 | **dump bin / promotional bin** | 91x91x76 (36x36x30 in); small 46x46x76 | **9x9x8**; **5x5x8** | **open top** | aisle head `cy 5` or `cy 4` | 12 / 17 | **BUILD.** Open-topped, so the camera looks straight into a box of product. Best top-face-per-voxel on the page. |
| 3 | **ice-cream chest freezer** (top-opening) | 79-91 tall, 66-127 wide, 69 deep | **8-9 tall, 7-13 wide, 7 deep** | **glass top** | west aisle `cy 4`, or against the counter's north arm | 17 | **BUILD.** A real konbini fixture whose defining surface is the one this camera is best at. Add it even though it is not on the shipped plan. |
| 4 | **restock carton** (RSC) | 30x30x30 (12x12x12 in, the commonest); 46x36x30 | **3x3x3**; **5x4x3** | top, and the open flaps | aisle end `cy 5-6` | 12 / 10 | **BUILD, and shrink.** The one carton in the room today is `10x10x8` = 100x100x80 cm, which is a pallet box, not a carton. Three real ones, one with its flaps open, beat it. |
| 5 | **pallet, JIS T11** | 110x110x14.4 | **11x11x1.4** | top | anywhere, incl. the sill row | 5 | **BUILD.** The only object here that fits under `cy 7`'s cap of 5 with three voxels of carton on top. All top face, ~130 voxels. |
| 6 | **shopping basket** | 43x30x23 | **4x3x2** | top (the open mouth) | at the door, `cy 6` | 10 | **BUILD / MOVE.** See 1.3. |
| 7 | **nested basket stack** (6 baskets, no stand) | ~68 tall `GUESS` on the nest pitch | **7** | top | `cy 6` (fits), `cy 7` (cut) | 10 / 5 | **BUILD at `cy 6`.** Four baskets (~50 cm, 5 vx) is the tallest stack that survives the sill row. |
| 8 | **basket stand** (holds 12) | 44.5x32x96.5 | **4x3x10** | side | `cy 6` exactly fills the cap | 10 | **allowed but pointless**: the stand is a 1-voxel wire frame, invisible at this distance. Stack them on the floor instead. |
| 9 | **low endcap** (3-tier promo, not the full unit) | 91-122 wide, ~90 tall, 41-56 deep | **9-12 x 9 x 4-6** | **top of each tier** | gondola's south end, `cy 5` | 12 | **BUILD at 9 tall.** A stepped 3-tier reads as an endcap and shows three top faces. |
| 10 | **entrance mat** | 91x152 (3x5 ft) / 122x183 (4x6 ft) / 91x305 runner | **9x15 / 12x18 / 9x30**, height 0 | top | door, `cy 7` | any | **EXISTS** at `x 42-85, z 112-126` = 440x150 cm -- a 4x15 ft apron, generous but defensible. Give it a border and a logo (1.3). |
| 11 | **trash bin** (Slim Jim 23 gal) | 56x28x76 (22x11x30 in) | **6x3x8** | side, and the dark mass | counter's south end, `cy 6` | 10 | **BUILD, one.** Its value is that it is DARK in a room that is 80 % above value 0.70, not that it is a bin. |
| 12 | **wet-floor / A-frame sign** | ~63 tall | **6** | south | aisle, `cy 5-6` | 12 / 10 | optional. Yellow, which the room lacks. Cheap. |
| 13 | **fire extinguisher**, portable ABC | ~48-55 tall, 15-18 dia `UNVERIFIED` for the JIS 10-type specifically | **5 x 2** | south | against the west wall, `cy 4-5` | 17 / 12 | **BUILD, low priority.** 2 voxels wide is about 2 screen px. It pays for the RED and nothing else. |
| 14 | **security camera**, dome | 17.4 dia x 9.3 | **2x2x1** | south | **wall face only** -- the ceiling is forbidden | 26 at `cy 0-2` | **BUILD LAST.** ~2 screen px. Costs nothing, buys nothing, but it is the kind of thing whose absence is felt only in aggregate. |
| 15 | **shelf-edge price rail** | 3-4 tall strip | **1 proud** | south | on the fixture it labels | -- | **EXISTS** on the gondola (`ShopKit.lua:482`). Extend to the cooler and the SALE cases. |

### 1.2 The elements that do NOT fit, and the number that rejects them

| element | real (cm) | voxels | rejected by |
| --- | --- | --- | --- |
| **hanging category sign** | any | any | `ART_DIRECTION` 2.5. There is no height at which a suspended element is free at pitch 27.1: a sign whose bottom is at y = 20 over `cy 6` hides the floor back to z = 73, the whole aisle mouth. **Forbidden, permanently.** |
| **floor spinner rack** | 152-183 tall, 41-66 dia | **15-18 x 4-7** | breaks every cap south of `cy 3` (22). Would have to stand in the cooler bay. |
| **countertop spinner** | 66-71 tall, 41-66 dia | **7 x 4-7** | stands on a 10-voxel counter = 17 total; the cap is 12 at `cy 5` and 10 at `cy 6`. Would need to be a third named exception beside the register and the jambs. Not worth it. |
| **full endcap unit** | 91-122 wide, 137-183 tall | **9-12 x 14-18** | 14 clears `cy 3` (22) and `cy 4` (17) but not `cy 5` (12), and the gondola's south end IS `cy 5`. Use the 9-voxel promo version. |
| **queue stanchion + belt** | 102 tall, 36 base, ~5 post | **10 x 4 base x 1 post** | fits `cy 6` exactly -- and should still be rejected. A konbini has no queue rail; it is a Western supermarket and bank fixture, and the shipped floor plan is a konbini planogram. Wrong shop. |
| **open-front chilled multideck** (bento) | 180-190 tall | **18-19** | fits only at `cy 0-2` (26), which is already the cooler bay and the two SALE cases. Only viable as a REPLACEMENT for one SALE case. |
| **konbini copy machine / MFP** | ~60x70x115 `GUESS` | **6x7x12** | fits `cy 3` (22) and `cy 4` (17) geometrically, and it is the single most iconic konbini fixture the Mart lacks -- but it is not a Poke Mart. Flagged, not recommended. |

### 1.3 The three that already exist and are placed wrong

| thing | today | why it is wrong | fix |
| --- | --- | --- | --- |
| **basket stack** | `x 4-13, z 34-43` -- `cy 2`, on the counter's north cap, **behind the counter** | in every konbini and every retail plan, baskets are in the customer's path at the entrance. Behind the counter they are the clerk's, not the shopper's, and the frame reads them as a red blob on the till | move to `cy 6`, on the door side of the counter's south arm; 6-7 voxels tall |
| **restock carton** | `x 34-43, z 98-107`, 10x10x8 voxels | 100x100x80 cm is not a carton, it is a pallet box | three cartons at 3x3x3 and 5x4x3, one with flaps open, on a T11 pallet |
| **`sign_shop` swatch** | declared in `ShopKit.SW` at `(0, 128, 64, 16)`; **never referenced** | the room contains no brand mark of any kind | see 2.4 and 4.9. `ART_DIRECTION` 2.5 already blesses a wall-plane fascia over the cooler bay at zero occlusion cost |

Also unreferenced in `ShopKit.SW` and worth either using or deleting:
`ceiling`, `vent`, `board_lip`, `glass_case`, `aisle_sign`, `tread`,
`shadow`. `aisle_sign` should stay dead -- it is the fixture 2.5 forbids.

### 1.4 What the plan already gets right, from the konbini literature

Not everything is missing. Worth writing down so it does not get "fixed":

- **Cold drinks along the back wall in glass reach-ins, widest run in the
  room** -- the plan's cell row 0-1, columns 2-5. That is the konbini rule
  exactly.
- **Register within two cells of the door.** The plan puts it at `cy 5`.
- **Gondolas short enough to see across** (14 voxels = 1.37 m, under a
  16-voxel person). This is the single reason a konbini reads as open.
- **The entrance is left clear.** Retail calls the first 1.5-4.5 m inside
  the door the *decompression zone* or *landing strip*; in a small store it
  is 2-3 ft, and the advice is to put nothing you want seen in it. Our
  `cy 7` has a cap of 5 voxels anyway, which enforces the same thing
  geometrically. The mat and a floor decal are the correct dressing for it;
  a dump bin is not.
- **Uniform bright cool light, no pools, no dark corners.** `Shop.RADIUS
  = 84` against a 128-px room, `ambient = 0.86`, `Shop.COLOR` at 5000 K.
  Retail practice is 300-750 lux at 3500-5000 K with CRI 80+; the room is
  at the cool, bright end of that, which is right for a konbini.

---

## 2. The game's own reference

### 2.0 The honest limit, first

`ART_DIRECTION` 1.1 already records it and this survey confirms it:
**the wiki sources do not describe Poke Mart fixtures in enough detail to
model from.** Bulbapedia's Poke Mart article carries an interior screenshot
per generation and captions them with nothing but the game's title; its
prose covers who sells what, not what anything looks like. The Pokemon Wiki
is the same.

So the canon below splits in three, and the split should be respected when
someone later asks "is this right?":

| tier | how it was established | how to treat it |
| --- | --- | --- |
| **shape** -- counter first, clerk behind it, stock on the back wall and on racks, small bright room | documented prose, multiple sources | binding |
| **plan** -- the 16x16 tile grid, the cell assignments, the three NPCs | dumped from the shipped ROM data by `tools/interior_plan.py`, hashed identical across all eight town Marts | binding, and the strongest evidence in the document |
| **fixture colour and material** | **not documented anywhere prose-side** | ours to invent, and it must be labelled as invention |

The one artefact that could settle the colour tier is the ripped tileset,
not an article: The Spriters Resource carries a
[Pokemon Center / Mart sheet for FireRed / LeafGreen](https://www.spriters-resource.com/game_boy_advance/pokemonfireredleafgreen/asset/3724/)
and separate FRLG tileset sheets. **Anyone who wants the counter's canonical
colour should pull that PNG and count its pixels** -- the same habit
`WORKFLOW.md` 7 prescribes for our own frames -- rather than argue from
memory of a screenshot.

### 2.1 What is canonical across every redraw

Three things survive four redraws and are the room's identity, not its
decoration (`ART_DIRECTION` 1.1, sourced to Bulbapedia and Pokemon Wiki):

1. **The service counter is the first thing you meet, with a standing
   clerk behind it facing you.** Gen IV briefly made it two clerks at one
   counter -- the right one selling standard items, the left one selling
   goods unique to that town -- which changed the count, not the fixture.
2. **Stock is on the wall behind the clerk and on free-standing racks in
   front of him,** and the player never touches any of it. It is scenery
   whose whole job is to say "shop", which is exactly why it can be dense.
3. **The room is small, bright and one look wide.** From Gen V the Mart is
   folded into the Pokemon Center "to the right of the entrance" and
   survives the shrink to a counter plus a wall of shelving -- which tells
   you the identity is *the counter plus the stocked wall*, not the floor
   area.

### 2.1a Generation by generation, what is actually established

| gen | games | what the sources establish | what they do NOT |
| --- | --- | --- | --- |
| I | RGBY | the standalone shop with the **blue roof**; one clerk at a counter; four-shade tiles recoloured by the SGB/GBC palette, so the interior's colour is the TOWN's, not the shop's | any fixture colour of its own -- there isn't one to have. Shade 1 is the town |
| III | FRLG | the same nine Kanto Marts, "the only functional difference" being the Mystery Gift form on the left of the counter -- i.e. **the room was redrawn in colour but not re-planned** | the counter's colour, the floor's pattern, whether the racks are free-standing. Settle from the ripped sheet, not from prose |
| IV | DPPt / HGSS | **two cashiers at one counter**: "the one on the right sells standard adventure items and is the same in any town, while the one on the left sells goods unique to that location" | fixtures again |
| V+ | BW onward | the Mart **stops being a building**: "not its own separate store, but instead located inside the Pokemon Center, to the right of the entrance" -- and survives the shrink | -- |

The load-bearing reading of that table is the last row. The Mart lost its
building, its floor area, its roof and most of its fixtures, and it was
still a Poke Mart. **What it kept was a counter with a clerk behind it and
a stocked wall.** Anything we add is dressing on top of those two; anything
we do that weakens either of them is a net loss however good it looks.

### 2.2 The blue

Blue is the Mart's brand colour, and through Gens I-IV it is carried by the
**exterior**: the blue roof is the standalone building's identifier right up
to its disappearance after Gen IV. That the *interior* counter is also blue
is **our invention, not established canon** -- see 2.0. It should be kept
anyway, for three reasons that do not depend on canon:

1. it is the only saturated mass in a room measured at 75 % desaturated;
2. it is the shop's own colour rather than the town's, so it is one of the
   very few things that reads the same in Viridian and in Cinnabar (3.3);
3. the brand-band pattern it follows is what every real konbini does --
   neutral shell, saturated band (7-Eleven `#F4811F` / `#ED2525` /
   `#008062`; FamilyMart `#0296E6` / `#00AB4E`).

`ShopKit` paints the counter front `#2E5FA3` today (`counter_fr`,
`tools/shop_sheet.py:72`, commented "the Mart's blue") and it is the best
thing in the frame. The proposal in section 3 is to make it a mass instead
of a stripe -- 9 % of the room against today's ~2 %.

### 2.3 What the shipped Gen I data says about our room

From `python tools/interior_plan.py VIRIDIAN_MART` (`ART_DIRECTION` 0):

- tileset `MART`, 16x16 tiles, identical byte-for-byte across all eight
  town Marts.
- objects: **`CLERK (0,5)`, `YOUNGSTER (5,5)`, `COOLTRAINER_M (3,3)`.**
  The room canonically contains **two customers** besides the clerk.
- the door mat is tiles `12 / 28` at `cy 7`, cells 3-4.
- the back wall run at `cy 0-1`, cols 2-5 is tiles
  `90,91 / 44,45 / 46,47 / 62,63`.

### 2.4 What we are contradicting today

| # | canon | what we ship | severity |
| --- | --- | --- | --- |
| 1 | the Mart is a **branded** shop; every generation puts its name or its blue somewhere the player reads | the interior carries **no brand mark at all**. `sign_shop` exists in the sheet and is never placed. The only blue is one counter face, ~2 % of the room | **high** -- this is the identity, not decoration |
| 2 | stock is dense and legible, "scenery whose entire job is to say shop" | the **cooler bay reads as empty glass** (measured `#AAC0C8`, sat 0.15 -- glass with nothing behind it). `ART_DIRECTION` 4.2 specifies 24 bottles at eye height plus colour bands on three tiers plus a lit interior; none of it is landing | **high** -- the widest run in the room is the emptiest |
| 3 | the room holds **three people**: a clerk and two customers | the dressing acknowledges none of them. No basket in use, no goods on the counter, no trace of a transaction. The one basket stack is behind the counter where a customer cannot reach it | medium |
| 4 | the back wall at `cy 0-1` cols 2-5 is drawn as **shelving**, not as a refrigerated cabinet | we read it as glass-door reach-ins. This is an interpretation (a defensible one -- the plan is a konbini planogram) and should be stated as one, not as canon | low, but say so |
| 5 | the counter is the first thing you meet | ours is, and it is right. But its **top is bare** -- the largest empty top face in the room, and the surface a shopper's eye lands on first | medium |
| 6 | the Mart's identity is "the counter plus the stocked wall" | we have both, and both are under-dressed relative to the SALE cases, which are the only fixtures in the frame that currently read as a shop | -- |

---

## 3. The palette

A konbini is not white. It is a white-grey **shell** with a small,
saturated **brand band**, and all of its remaining colour comes from
**product and price signage**. The three big chains make the point: 7-Eleven
is orange `#F4811F`, red `#ED2525` and green `#008062`; FamilyMart is
cerulean `#0296E6`, green `#00AB4E` and white. In each case the brand colour
is a *band* -- a fascia, a door frame, a counter face, an awning stripe --
against a neutral shell, never the shell itself.

Our room fails at the shell, not at the accents. Section 0.1: 46 % of the
room is one non-colour, and 52.6 % sits in the top value decile.

### 3.1 The eight

| name | hex | what carries it | target % of room | today |
| --- | --- | --- | --- | --- |
| `shellWhite` | `#F4F2EC` | wall paint, ceiling band, cornice, the coping course | **14 %** | merged into the 46 % beige mass |
| `floorPale` | `#DED9CF` | the floor photo's target mean | **21 %** | `#DDD8D0` -- already right, and the only measured surface that is |
| `floorGrout` | `#B7B1A5` | the joint, and the tile inset motif | **5 %** | present but at too low a contrast to read as a joint |
| `steelCool` | `#A6AEB6` | **all** fixture metal: gondola uprights, cooler frame and mullions, cabinet, door jambs, the till body | **13 %** | `#CDD2D8` -- too pale and only 0.06 of value away from the wall, which is why fixture and shell read as one mass |
| `martBlue` | `#2E5FA3` | counter front, the shop fascia, the price rails' field, the mat border, the door threshold | **9 %** | one face, ~2 % |
| `martBlueLight` | `#7FB2E0` | the fascia's field behind the lettering, the counter's edge light, floor-decal arrows | **3 %** | absent |
| `signalRed` | `#D23B33` | baskets, the SALE flash, the extinguisher, Poke Ball facings, the endcap header | **5 %** | in the sheet as `sign_red`, on screen only as the basket stack |
| `warmAmber` | `#E39B3C` | price cards, cardboard, the paper-bag stack, the hot/bento zone if one is built | **6 %** | only as `laminate` `#D8C3A0`, desaturated to sat 0.04 on screen |
| `graphite` | `#2B2F35` | kicks, grout shadow, the mat field, every board underside, the till bezel, every fixture's toe | **8 %** | the mat only, ~2 % |
| *(product labels -- the existing 24-swatch grid)* | -- | facings | **16 %** | ~12 %, and the best thing in the frame. Do not touch it |

Sums to 100 %. The percentages are **targets to measure against with the
same flood-fill histogram in 0.1**, not derived values -- treat them as
`GUESS` until a frame is counted against them.

### 3.2 The three rules that matter more than the hexes

1. **Split the neutrals in two.** Shell (wall, ceiling, floor) stays WARM:
   hue 40-50, sat 0.05. Every fixture goes COOL and darker: hue 205-215,
   sat 0.06-0.09, value 0.15-0.20 below the wall. Today wall, floor,
   counter top, gondola board and SALE case all sit at hue 42-79, sat
   0.04-0.06, value 0.75-0.87 -- five different objects at one colour.
   **This is a shade-table change with no new geometry and it un-merges
   nearly half the room.**
2. **Give the room a dark.** 8 % of the room below value 0.20. Today it is
   2 %, and all of it is the mat. Everything pale reads as pale only
   against something that is not; a room whose darkest object is its
   doormat has no anchor. Kicks, board undersides, grout, the counter toe.
3. **The blue must be a MASS, not a stripe.** 9 % against today's 2 %. A
   brand colour on one vertical face of one fixture is a paint job; the
   same colour on the counter front AND the fascia AND the mat border AND
   the price rails is a brand.

### 3.3 The trap, restated

`ART_DIRECTION` 7.7: shade 1 of the SGB palette is the TOWN --
`#D6FFAD` in Viridian, `#FF7B73` in Cinnabar, `#FFCE84` in Vermilion. Every
colour in 3.1 must be picked out of the **all-white column** of the palette
row and tinted by the model, or the shop is a different colour in every
town. Only `#FFFFF7`, `#BDDEFF` and `#313131` are stable across the eight
Marts, which is also why `coolerGlass` uses `#BDDEFF` literally.

This is why the blue is safe: `#2E5FA3` is a model tint, not a drawing
texel, so it survives the town recolour. It is also why "just pick the
counter colour off the tileset" is never the answer.

---

## 4. The ten details that most sell realism, in order

The ordering is `visible area x how much "shop" it says / (voxels + code)`,
and it is biased by 0.2: **top faces are guaranteed, south faces are
richest, side faces are free to leave blank, and anything above its row's
cap does not exist.**

| # | detail | why it is here | cost |
| --- | --- | --- | --- |
| **1** | **Dress the floor.** Two or three floor decals (3x3 and 6x9 voxels), a real grout contrast, a scuffed traffic path from the mat to the counter, and a border on the mat. | Measured, bare floor is **22-29 % of every pixel of the room** -- more than any other surface, and thirteen times the back wall's visible band. In all three shipped frames the south-east quadrant, the entrance apron and the whole centre aisle are empty. Height 0 means **zero occlusion cost in any cell row**, so it is the only item on this list that no cap can veto. | tiny: sheet swatches plus one `y == 0` branch |
| **2** | **Stock the cooler bay.** Execute `ART_DIRECTION` 4.2 as written: 24 real bottles on the eye-height shelf, 1-voxel colour bands on the other three, and `coolerGlow` behind all of it. | The widest single run in the room, fully unoccluded, and it measures `#AAC0C8` at sat 0.15 -- glass with nothing behind it. A konbini's drinks wall is meant to be the brightest and busiest object in the store; ours is the emptiest. | medium: ~120 voxels of bottle plus three band rows |
| **3** | **Put something on the counter top.** A cash tray, a flyer stack, a pen cup, a bag rack, a receipt spike. | The largest empty **top** face in the room. **But check the cap first:** `CTOP = 10` (`ShopKit.lua:412`) and the cap at `cy 6` is also **10**, so the counter's south cap (`z 96-111`) is sliced flush with its own worktop and *nothing can stand on it there at all*. Headroom over the counter, by row: `cy 2` **16 voxels**, `cy 3` 12, `cy 4` 7, `cy 5` **2** (and the register already spends them as a named exception), `cy 6` **0**. So clutter goes on the **north cap, `x 0-31, z 32-47`** -- which is also where the plan puts `CLERK (0,5)`. The right dressing and the canonical dressing are the same cells. | small, once the z-range is respected |
| **4** | **A dump bin (9x9x8) or a low 3-tier endcap (9 tall) at the gondolas' south end.** | An open-topped box of product standing in the middle of the biggest bare floor, showing the camera the one face it is best at. This is what a promotional aisle head looks like in every convenience store, and it is the cheapest way to break up the empty centre. | small: one chamfered prism plus facings |
| **5** | **Split the neutrals -- fixtures cool and darker, shell warm.** | Section 3.2 rule 1. It is a `Shop.SHADE` and swatch-hex change with **no new geometry** and it separates nine surfaces that currently read as one 46 % mass. Highest ratio on the page. | one table |
| **6** | **Give the cut's top faces a coping.** A tone-separated top course on the perimeter wall and the south sill, with a nosing line. | The cut manufactures a 5-voxel-wide top face on three walls, and in both frames those bands are large and flat white. `CryptKit` already has the coping-course idiom; lift it. | small |
| **7** | **A T11 pallet with three real cartons on it, replacing the one oversized box.** | 11x11x1.4 plus 3 voxels of carton fits under **every** cap in the room including `cy 7`'s 5, is all top face, and says "someone restocks this place" in about 130 voxels. Today's single 100x100x80 cm carton says nothing. | small |
| **8** | **Move the baskets to the door and make them a red mass.** | Canon and konbini agree that baskets sit in the customer's path; ours is behind the counter. Moving it is nearly free, and 5 % `signalRed` at `cy 6` is one of only two places the room can get saturated red at floor level. | trivial (a z-range) |
| **9** | **Put the brand in the room:** a POKE MART fascia in the wall's own plane over the cooler bay, y 22-25, 2 voxels proud. | The interior has no brand mark at all, and `sign_shop` is already drawn in the sheet and never placed. `ART_DIRECTION` 2.5 explicitly blesses this fixture -- it is a real konbini header and it costs **zero occlusion** because it lives in the wall's plane. This is the highest-value item that is not already half-built, which is the only reason it is not higher. | small |
| **10** | **The small dark and red things:** a trash bin (6x3x8), the extinguisher (5x2), a wall dome camera (2x2x1), the wet-floor sign (6). | Two to six screen pixels each. They pay only in aggregate, and they pay for exactly two things the room does not have: **something dark** (8 % of the room below value 0.20 is the target; today it is 2 %) and **something red at floor level**. Build them last and judge them together, not one at a time. | trivial each |

### 4.1 What NOT to build, restated so it does not come back

- Anything hanging. `ART_DIRECTION` 2.5, `k = 0.511`. There is no free
  height. If a mock looks fine, the mock is in a three-quarter authoring
  view, not the shipped shot.
- A floor spinner (15-18 voxels) or a full endcap unit (14-18): both break
  the caps at `cy 4-5`, which is the only place they would go.
- A queue stanchion. It fits, and it is the wrong shop.
- Detail on any east or west face. `|n . v| = 0.000` at the frame's centre
  column.
- A second grid over a photograph (`ART_DIRECTION` 7.5): if the floor keeps
  its terrazzo material, the floor decals must be **art on the sheet**, not
  a second tiling.

### 4.2 How to know any of this worked

Re-run the flood-fill histogram in 0.1 against the new frame and check
four numbers, in this order:

| number | today | target |
| --- | --- | --- |
| room pixels with sat < 0.10 | 75.0 % | **< 60 %** |
| room pixels in the top value decile | 52.6 % | **< 35 %** |
| room pixels with value < 0.30 | 8.0 % | **>= 8 %**, and spread, not one mat |
| largest single swatch | 25.2 % (`#F8F8F8`) | **< 15 %** |

`WORKFLOW.md` 7 is the standing rule and it applies here more than
anywhere: **look at the frame, and when something is wrong, measure it
rather than reading the code for it.** Every number in section 0 came from
`PIL` on the probe's PNG in about ten lines.

---

## Sources

Konbini layout, lighting and retail practice:
[Voyapon, the konbini](https://voyapon.com/the-konbini-japan/) *
[byFood, guide to konbini](https://www.byfood.com/blog/culture/guide-to-konbini-japanese-convenience-stores) *
[Konbini UX, Bootcamp](https://medium.com/design-bootcamp/konbini-ux-why-japanese-convenience-stores-are-a-design-masterpiece-90bc60c1f64a) *
[The Standard Japan, konbini guide](https://thestandardjapan.com/culture/japanese-convenience-store-culture) *
[LEAFIO, convenience store planogram guide](https://www.leafio.ai/blog/mapping-out-a-convenience-store-planogram-the-ultimate-guide/) *
[Convenience Store, the decompression zone](https://www.conveniencestore.co.uk/your-business/store-design-enter-the-decompression-zone/593764.article) *
[Pivotal Retail, decompression zone](https://pivotal-retail.com/what-is-the-decompression-zone-in-retail-and-why-does-it-matter/) *
[NRS, convenience store layout and impulse](https://nrsplus.com/blog/how-to-lay-out-your-convenience-store/)

Fixture dimensions:
[Store Supply Warehouse, 18x18x30 wire dump bin](https://www.storesupply.com/pc-12776-581-18-x-18-x-30h-wire-dump-bin-60310.aspx) *
[The Global Display Solution, dump bin 36W x 32H](https://www.theglobaldisplaysolution.com/premium-wire-merchandising-dump-bin-with-casters-36w-x-32h-black/) *
[DGS Retail, gondola end cap units](https://www.dgsretail.com/P372S-EC/lozier-shelving-end-cap-unit-black-36w-72h-22d) *
[wzrack, end cap display dimensions](https://wzrack.com/end-cap-display-dimensions-maximizing-checkout-aisle-impact/) *
[VEVOR, shopping basket 42.8x30x22 cm](https://www.amazon.com/VEVOR-Shopping-Baskets/dp/B0BTB35YNY) *
[Regency, basket stand 17.5 x 12.5 x 38 in](https://www.webstaurantstore.com/regency-grocery-market-shopping-basket-stand-17-1-2-x-12-1-2-x-38/176MSBSTD.html) *
[Greatmats, commercial entrance mats](https://www.greatmats.com/entrance-mats.php) *
[Mats4U, sizing entry mats](https://www.mats4u.com/blogs/news/how-to-size-entry-mats-for-commercial-entrances) *
[Rubbermaid Slim Jim 23 gal, 22x11x30 in](https://www.uline.com/Product/Detail/H-2894GR/Plastic-Indoor-Trash-Cans/Rubbermaid-Slim-Jim-Trash-Can-23-Gallon-Gray) *
[Anchor Box, standard shipping box sizes](https://anchorbox.com/standard-shipping-box-sizes/) *
[Fantastapack, regular slotted container](https://www.fantastapack.com/products/regular-slotted-container-rsc) *
[Sino Shipping, JIS 1100x1100 T11 pallet](https://www.sino-shipping.com/jis-pallets-japan/) *
[Pallet Standards, Asia](https://www.palletstandards.com/pallet-standards-asia) *
[The Restaurant Warehouse, commercial freezer sizes](https://therestaurantwarehouse.com/blogs/restaurant-equipment/the-perfect-fit-a-guide-to-commercial-freezer-sizes-and-energy-savings) *
[Koolmore, 50 in ice cream chest freezer](https://koolmore.com/products/commercial-ice-cream-freezer-display-case-glass-top-chest-freezer-with-4-storage-baskets-and-clear-sliding-lid-large-12-cu-ft-capacity-white) *
[Store Supply Warehouse, 2-tier counter spinner](https://www.storesupply.com/pc-12735-840-2-tier-spinner-rack-26-dia-60190.aspx) *
[Wikipedia, spinner rack](https://en.wikipedia.org/wiki/Spinner_rack) *
[Crowd Control Store, retractable belt stanchions](https://www.crowdcontrolstore.com/product-category/retractable-belt-stanchions/) *
[Lavi, stanchions and barriers](https://www.lavi.com/en/crowd-control/stanchions-barriers) *
[PrintPlace, floor graphics sizes](https://www.printplace.com/products/floor-graphics) *
[SquareSigns, custom floor decals](https://www.squaresigns.com/product/floor-decals/) *
[CCTV Camera World, dome camera mounts](https://www.cctvcameraworld.com/dome-security-cameras.html)

Lighting practice:
[PacLights, retail lighting standards](https://www.paclights.com/explore/lights-for-store-lighting-standards-what-engineers-should-know/) *
[Westgate, LED lighting for retail](https://www.westgatemfg.com/blog/solutions/best-led-lighting-for-retail-stores)

Brand colour:
[BrandPalettes, 7-Eleven](https://brandpalettes.com/7-eleven-colors/) *
[BrandColorCode, FamilyMart](https://www.brandcolorcode.com/familymart) *
[Encycolorpedia, Lawson](https://encycolorpedia.com/companies/japan/lawson)

Poke Mart across generations:
[Bulbapedia, Poke Mart](https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9_Mart) *
[Bulbapedia, Pokemon Center](https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9mon_Center) *
[Pokemon Wiki, Poke Mart](https://pokemon.fandom.com/wiki/Pok%C3%A9_Mart)

In-tree, read for this document and measured against:
`assets/docs/shop/ART_DIRECTION.md`, `assets/docs/shop/WORKFLOW.md`,
`lib/ShopKit.lua` (`SW`, `BANDS`, `CTOP`, `BOARDS`, `fittings`, `poster`,
`room`), `lib/Shop.lua` (`SITES`, `RADIUS`, `POWER`, `COLOR`, `BLOOM`),
`tools/shop_sheet.py` (`SWATCHES`, the product grid),
`data/camera_shots.lua` (the eight MART entries),
`probe_out_shop/shop_room.png` and `probe_out_shop/shop_counter.png`.
