# Shop interior — silhouette & material audit, round 2 (ANTES → DEPOIS)

Measured, not opined. Nothing was rendered, no `lib/` file was read or touched.

## How this comparison was made

The round-1 scripts survived in the session scratchpad, and so did the **frozen 09:13 frame
set** they were run on (`shop_room.png` md5 `f20445b3…`, `shop_aisle.png` md5 `3a46da96…` —
the same md5s the round-1 doc records). So this is not a comparison of a new script against
an old number: **both sets were pushed through the same code**, parameterised only by which
directory it reads.

* **ANTES** = the frozen **2026-09-08 09:13** set (`snap/`).
* **DEPOIS** = the frozen **2026-09-08 09:36** set (`snap2/`), copied out of `probe_out_shop/`
  before the 09:40 run overwrote it. `shop_room.png` md5 `187764b2…`, `shop_aisle.png`
  md5 `daf5183e…`.

Re-running the round-1 code on `snap/` reproduces the published numbers to the decimal —
61.20 % void, 82.3 % boxiness, 40 164 unique colours, patch grain 2.50, cardboard box −16.6,
hour swing 0.38865 / 0.1524 %, 240-px flat run, 91.5 % roofline. The ANTES column below is
therefore my own re-measurement, not a transcription, and it agrees with the round-1 doc.

**Two things are NOT comparable, and are marked ✕ wherever they appear.**

1. **Hand-cut region boxes.** The camera moved (fov 38 → 33, focY 10 → 4), so the round-1
   boxes point at empty space now. They were re-cut on the new frames (overlay proof:
   `audit2/03_regions_*.png`). Same materials, same filters, different rectangles.
2. **The material's brightness gate.** Round 1 defined "white" as `sat < 0.12 & val ≥ 200`.
   The shell is now 35 levels darker, so that gate selects a *different population* than it
   used to. Every per-material row is therefore given twice: under an **exposure-free gate**
   (`val ≥ 120`, primary) and under the **strict round-1 gate** (`val ≥ 200`).

Diagnostic images: `assets/docs/shop/audit2/`. Round-1 images are untouched in `audit/`.
Side-by-side: `audit2/00_before_after.png`.

---

## 0. What the frame is made of — `shop_room.png`

| | ANTES | DEPOIS | ALVO | verdict |
|---|---|---|---|---|
| background void | **61.20 %** | **48.47 %** | as low as the shot allows | **−12.73 pp** |
| room (all lit geometry) | 38.80 % | **51.53 %** | — | **+12.73 pp** |
| 2D character sprites | 2.15 % | 2.73 % | — | — |
| silhouette columns cut by the frame edge | 0 px | **806 px at y = 0** | 0 | **new** |

The camera pull is the single largest change on the sheet: the room went from three pixels in
eight to more than half the frame. It came with a cost — in `shop_room.png` the ceiling now
runs off the **top** of the viewport for 806 of 1 346 silhouette columns (59.9 %). See §6.

`shop_wall.png` also cuts 476 px at the bottom + 183 px on the left (was 210 px bottom), and
`shop_counter.png` cuts 171 px on the right (was 0).

---

## 1. Edge-orientation histogram — the boxiness index

Sobel over luminance, gradient angle rotated 90° and folded to [0°,180°); background dilated
3 px, sprites removed. The three peaks are **0.5° / 90.5° / 116.5° in both sets** — the fov
change did not rotate the ground axis.

| measure | ANTES | DEPOIS | ALVO | verdict |
|---|---|---|---|---|
| edge pixels (mag > 24) as % of frame | 14.42 % | **27.48 %** | — | 1.9× more edge |
| on-axis ±4°, **by count** | 30.2 % | 23.7 % | 20–30 % | in band |
| on-axis ±4°, **by energy** | 50.3 % | **39.7 %** | 30–45 % | **in band** |
| on-axis, strong edges only (mag > 180), by count | 61.3 % | 55.2 % | 35–50 % | still high |
| the horizontal peak alone, ±4° (a 4.4 % slice of angle space) | 44.6 % of energy | **36.3 %** | ≤ 15 % | 8× over |
| the second ground axis (63.5°), as a share of the horizontal | 8.8 % | 10.3 % | ~100 % | still absent |
| **BOXINESS INDEX** — coherent contours (4/4) on-axis | **82.3 %** | **81.7 %** | 45–60 % | **unchanged** |
| same, `shop_aisle` | 80.4 % | 80.9 % | 45–60 % | unchanged |
| coherent contours as % of frame | 2.21 % | 2.49 % | — | — |
| coherent contours as % of the **room** | 5.70 % | 4.83 % | — | — |

**Read the energy row and the boxiness row together, or the energy row will lie to you.**
Edge pixels nearly doubled (14.4 % → 27.5 % of the frame) because the surfaces now carry real
texture. That new grain is off-axis by nature, so it *dilutes* the on-axis energy fraction
without a single box edge going away. Filter to edges that form a continuous contour and the
answer is flat: **82.3 % → 81.7 %.**

Nothing in the room draws a line that is not a cube edge. That has not changed.

`audit2/01_edge_orientation_map.png`, `audit2/02_edge_angle_histogram.png`.

---

## 2. Palette and clipping

Whole frame, `shop_room.png`:

| measure | ANTES | DEPOIS | ALVO | verdict |
|---|---|---|---|---|
| unique colours | 40 164 | 46 396 | — | +15.5 % |
| **pure `#FFFFFF`** | **5.43 % of frame** | **0.00 %** | 0 | **eliminated** |
| any channel at 255 | 11.20 % | **3.17 %** | < 2 % | −8.03 pp |
| any-255 **inside the room** | 28.88 % | **6.16 %** | < 2 % | −22.7 pp |
| room's modal colour, and its share | `#FFFFFF`, 14.58 % | `#FFFFFA`, **0.42 %** | ≤ 5 % | **fixed** |
| room pixels within ±3 of the modal colour | 17.10 % | **2.24 %** | ≤ 10 % | **fixed** |
| crushed the other way (room L < 16) | 0.00 % | 0.00 % | 0 | no new crush |
| room L < 40 | 0.45 % | 3.26 % | — | shadows opened, not crushed |

Per material — ✕ re-cut boxes, **exposure-free gate** (`val ≥ 120`):

| region | measure | ANTES | DEPOIS | ALVO |
|---|---|---|---|---|
| white shell | modal colour share | 29.22 % | **0.66 %** | ≤ 5 % |
| | within ±3 of modal | 34.6 % | **5.2 %** | ≤ 10 % |
| | pure `#FFFFFF` | 29.2 % | **0.0 %** | 0 |
| | **local 5×5 std** | 3.32 | **8.92** | 4–10 |
| | Lmean | 236.8 | 201.6 | — |
| floor | modal colour | `#FFFFFF` 12.60 % | `#FFFFFA` **1.45 %** | ≤ 5 % |
| | within ±3 | 14.1 % | **7.4 %** | ≤ 10 % |
| | local 5×5 std | 5.51 | 5.93 | 4–10 |
| | Lmean | 202.5 | 181.9 | — |
| products | local 5×5 std | 14.12 | 11.88 | 4–10 |
| | Lmean | 177.7 | **128.0** | — |
| | product ÷ shell luminance | 0.751 | **0.635** | ≈ 0.85 if the intent was "15 % darker" |

Same rows under the **strict round-1 gate** (`val ≥ 200`), for continuity — note the gate now
selects only 4.28 % of the frame instead of 6.66 %, because the shell fell below it:

| white shell | ANTES | DEPOIS |
|---|---|---|
| within ±3 of modal | 37.7 % | **9.0 %** |
| pure `#FFFFFF` | 31.9 % | **0.0 %** |
| local 5×5 std | 2.92 | **8.24** |
| Lstd | 16.34 | 17.82 |

Both gates say the same thing. **The clipping is gone and the shell's texture is now on
screen.** The one number that overshot is the products: they are 37 % darker than the shell,
not the ~15 % the palette split was aiming at, and 74 luminance levels below the wall they
sit against.

`audit2/04_clipping_map.png`, `audit2/09_dead_surface_map_*.png`.

---

## 3. Flatness inside a face

**The round-1 test no longer has a solution, and that is the result.** It looked for 40×40
windows lying wholly inside one material with **at most 2 pixels over Sobel 45**:

| clean 40×40 windows | ANTES | DEPOIS |
|---|---|---|
| white, hard-edge threshold 45 | **449** | **0** |
| floor, threshold 45 | 43 | 0 |
| `shop_aisle` white, threshold 45 | 2 442 | 0 |
| white — first threshold with any clean window | 45 | **130** (6 windows) |

The material grain itself now exceeds Sobel 45 everywhere. This is not a regression; it is the
same fact as §2 seen from another side. Round 1 said the grain arrived as ±2 levels of dither;
it now arrives at roughly 3× the gradient strength that used to mark a *face boundary*.

Relaxed to the **cleanest five windows available** (same rule both sides, so it is comparable):

| `shop_room` / white | ANTES | DEPOIS | ALVO |
|---|---|---|---|
| mean Lstd | 4.58 | 15.83 | 4–6 |
| mean shading ramp (plane p2p) | 14.19 | **39.16** | — (higher is more form) |
| **mean grain residual** | **2.31** | **12.28** | 3–6 |
| mean clipped | 36.7 % | **0.0 %** | 0 |
| | | | |
| **`shop_room` / floor** | | | |
| mean Lstd | 4.84 | 9.47 | 4–6 |
| mean shading ramp | 9.41 | 23.63 | — |
| mean grain residual | 3.74 | 6.91 | 3–6 |
| mean clipped | 67.3 % | **0.0 %** | 0 |

Dead surface, per material (local 5×5 std < 2 — "the texture is not reaching the screen"):

| | ANTES | DEPOIS | ALVO |
|---|---|---|---|
| of all white-shell pixels | **36.57 %** | **6.87 %** | ≤ 10 % |
| of all floor pixels | 16.64 % | 8.52 % | ≤ 10 % |
| of the whole room | 26.54 % | **10.46 %** | ≤ 10 % |

Two caveats on the 5-patch table. First, no window is clean any more, so its Lstd and ramp
carry real face-boundary contrast and are **inflated** — the honest grain figure is the local
5×5 std in §2 (2.92 → 8.24), which sits inside the healthy band. Second, at 12.28 the patch
grain is roughly **2× the round-1 healthy ceiling**; the surfaces are not under-textured any
more, and the next risk on this axis is over-texturing, not flatness.

**The correlation that drove round 1 — clipping destroying shading at r = −0.944 — is no
longer computable, because no patch is clipped.** The mechanism it described has been removed:
the mean shading ramp went from 14.19 to 39.16 levels across 40 px on the white shell.

`audit2/05b_face_patches_*.png`.

---

## 4. Contact shadow

Whole-screen, floor luminance by distance **below** the nearest fixture base (`shop_room`):

| band | ANTES L | ANTES clipped | DEPOIS L | DEPOIS clipped |
|---|---|---|---|---|
| 0–4 px | 201.6 | 19.1 % | **169.2** | **1.2 %** |
| 4–8 px | 217.0 | 36.6 % | 176.6 | 1.7 % |
| 8–16 px | 213.6 | 27.5 % | 192.0 | 6.6 % |
| 16–32 px | 215.5 | 38.6 % | 204.9 | 28.9 % |
| shape | non-monotonic, noise | | **monotonic rise of +35.7 L** | |

Direction-free control — floor luminance vs **isotropic** distance to the nearest fixture
pixel, referenced to the 32–64 px ring (the sun has a shear, so a cast shadow need not sit
directly below its caster; and floor near a sprite is excluded, since sprites cast nothing):

| band | room ANTES | room DEPOIS | aisle ANTES | aisle DEPOIS | ALVO |
|---|---|---|---|---|---|
| 0–4 px | −14.98 | **−23.89** | −7.82 | **−18.89** | −40 … −80 |
| 4–8 px | −4.96 | **−15.61** | −6.97 | −8.20 | decaying |
| 8–16 px | −5.02 | **−15.45** | −8.21 | −15.01 | decaying |
| 16–32 px | −5.98 | −2.98 | −4.26 | −8.92 | → 0 |

Per fixture, ramp-corrected against each fixture's own floor gradient:

| fixture | frame | ANTES 0–4 px | DEPOIS 0–4 px | ANTES clipped at contact |
|---|---|---|---|---|
| cardboard box | room | −16.6 | ✕ too little clean floor | 0 % |
| gondola shelf | room | −1.9 (then +22.1) | **−11.5** (then −9.5, −6.3, +1.0) | 38.6 → 98.9 % |
| checkout counter | room | +26.3 | ✕ too little clean floor | 0 % |
| gondola shelf | aisle | +66.2 | +20.0 | **100 %** |
| checkout counter | aisle | +11.5 | +10.6 | 0 % |

**What improved is real, and smaller than it looks.** The darkened zone is now four times
wider (−15 L still at 16 px, where round 1 was back to −5 by 4 px), it is monotonic, and the
contact band is no longer 19–100 % clipped to 255 — round 1 could not have *represented* a
shadow there. At −23.9 L the contact is at **60 % of the shallow end** of the healthy −40…−80.

**But the sun pass is not what produced it, on this evidence.** Three checks:

| control | ANTES | DEPOIS | reading |
|---|---|---|---|
| directional anisotropy at 4 px (worst side − best side) | 27.8 L | **19.8 L** | *smaller*, not larger |
| same, `shop_aisle` | 22.5 L | 17.6 L | *smaller* |
| dark-floor fraction at 0–4 px vs 32–64 px | 42.2 % vs 19.0 % | **30.8 % vs 34.5 %** | no longer clustered at bases |
| detrended floor residual map | no caster-shaped blob | no caster-shaped blob | `audit2/10_floor_residual_*.png` |

The probe reports the pass is live (`sun pass: alpha=0.240  shear=(-0.52,-0.34)  LIGHT=true`,
both shears agreeing). What the pixels show is a **deeper, wider ambient/contact darkening**,
not a directional cast shadow with a consistent side. The floor's own detrended residual std
also rose 25.8 → 32.1 — the FloorArt rescale (96 → 32) put more large-scale mottling on
screen, which is what dominates that map in both sets.

---

## 5. Response to the hour

| measure | ANTES | DEPOIS | ALVO | verdict |
|---|---|---|---|---|
| tint the probe reports at day / dusk / night | 0.882 / 0.900 / 0.918 | **0.725 / 0.740 / 0.755 — the same triple three times** | must vary | **unchanged** |
| probe's own verdict | `max tint spread 0.000` | `max tint spread 0.000` | > 0 | unchanged |
| day→night L swing, static geometry (hand box ✕) | 0.389 of 255 = **0.152 %** | 0.940 of 255 = **0.369 %** | 25–45 % | **still ~100× short** |
| same, automatic static mask (comparable) | 0.388 = 0.152 % | 0.503 = 0.197 % | 25–45 % | still ~100× short |
| direction of the change | night **+0.39 brighter** | night **+0.94 brighter** | night darker | **still backwards** |
| static px that differ at all, day→night | 62.3 % | 90.0 % | — | more dither |
| …of those, differing by only 1–2 levels | 88.5 % | 69.9 % | — | still dither |
| effect of applying the hour tint at all (hand box ✕) | 18.66 L (7.7 %) | 7.28 L (3.7 %) | — | path still live |

The wiring is alive — switching the tint on still moves the room, by 7.3 levels. It is being
handed **the same constant at all three hours**. Note the three numbers in the triple
(0.725 / 0.740 / 0.755) are the R, G and B of one tint, not day, dusk and night.

`audit2/07_hour_diff_map.png`.

---

## 6. Height variety in the silhouette

Topmost non-background pixel per column. `shop_room.png` needs a correction this round:
**806 of its 1 346 columns (59.9 %) top out at y = 0**, i.e. the room is cut by the viewport,
so there is no silhouette to measure there. Both the raw and the corrected numbers:

| `shop_room` | ANTES | DEPOIS raw | DEPOIS, frame-cut columns removed |
|---|---|---|---|
| silhouette width | 1 163 px | 1 346 px | 540 px of free skyline |
| **longest perfectly horizontal run** | **240 px (20.6 %)** | 806 px @ y = 0 — *the window* | **1 px (0.2 %)** |
| skyline inside runs ≥ 32 px | 53.7 % | 59.9 % — *the window* | 0.0 % |
| roofline within ±2 px of one height | **91.5 %** | — | 10.0 % (of a 60-px stub) |

`shop_aisle.png` is uncut in both rounds, so it is the honest comparison:

| measure | ANTES | DEPOIS | ALVO | verdict |
|---|---|---|---|---|
| longest perfectly horizontal run | 75 px | **74 px** | ≤ 40 px | unchanged |
| …as % of silhouette width | 6.4 % | 5.4 % | ≤ 5 % | width grew, run did not |
| skyline inside runs ≥ 32 px | 50.3 % | **52.6 %** | ≤ 20 % | slightly worse |
| roofline within ±2 px of one height | 52.9 % | **45.0 %** | ≤ 30 % | −7.9 pp |
| distinct height levels | 384 | 459 | — | — |

| longest run, other views | ANTES | DEPOIS |
|---|---|---|
| `shop_wall.png` | 30 px | **30 px** |
| `shop_counter.png` | 30 px | **30 px** |

**The flat roofline was not modelled away — in `shop_room` it was framed away.** Every view
that still shows the roof reports the same run length as round 1, to within a pixel.

`audit2/08b_skyline_free_*.png` (red ticks = columns cut by the frame).

---

## Ranking DEPOIS — by how much of the screen each defect touches

`shop_room.png`, 1 536 × 864 = 1 327 104 px.

| # | defect | ANTES % of frame | DEPOIS % of frame | DEPOIS % of room | movement |
|---|---|---|---|---|---|
| **1** | **Zero response to the hour** | 38.80 % | **51.53 %** | 100 % | **worse in area** — the room grew, the bug did not shrink |
| **2** | **Empty background void** | 61.20 % | **48.47 %** | — | **−12.73 pp** |
| **3** | **Blown-out / dead surface (union)** | **14.73 %** \* | **6.79 %** | 13.17 % | **−7.94 pp** |
| 3a | — clipped (any channel 255) | 11.20 % | 3.17 % | 6.16 % | −8.03 pp |
| 3b | — dead surface (5×5 std < 2) | 10.30 % | 5.39 % | 10.46 % | −4.91 pp |
| **4** | **Boxy contour set** | 2.21 % | **2.49 %** | 4.83 % | index 82.3 → 81.7 % |
| **5** | **Contact shadow shortfall** | 2.04 % | 2.04 % | 3.96 % | −15 L → −24 L of −40 needed |
| 6 | Flat roofline | ~0.02 % | ~0.01 % | — | cropped in `shop_room`, unchanged in `shop_aisle` |
| — | *(new)* room silhouette cut by the frame | 0 px | 806 px | — | new |

\* The round-1 doc prints **14.31 %** for this union row. Re-running its own code on its own
frames gives 14.73 % for `shop_room` and **14.33 %** for `shop_aisle` — the published figure
is the aisle's. Both columns above are `shop_room`, measured the same way.

Rows 1 and 2 swapped places, and not because the hour bug got worse: the camera pull moved
12.7 pp of screen from void into room, and every one of those new pixels is a pixel that does
not respond to the hour.

**The three that remain, in the order the area says to fix them:**

1. **Zero hour response — 51.53 % of the frame.** The largest defect on the sheet by a factor
   of seven, unchanged in magnitude since round 1, and the only one that is a wiring bug
   rather than an art problem.
2. **The void — 48.47 % of the frame.** Down 12.7 pp and still the second largest thing on
   screen. Nothing but framing touches it.
3. **The boxy contour set — 2.49 % of the frame, 4.83 % of the room.** Small in area and
   100 % of the line work: 81.7 % of every coherent contour still lies on exactly three
   angles. It did not move, and no exposure or camera change will move it.

---

## Is anything here a bug rather than an art problem?

**Yes, one — and it is the same one round 1 found.**

> **The hour tint is a constant.** The probe reports `tint = 0.725, 0.740, 0.755` at day, at
> dusk and at night — one triple, three times, `max tint spread 0.000`. The rendered swing on
> static geometry is **0.37 % against a 25–45 % target**, and night comes out **0.94 levels
> brighter** than day, which is the wrong direction. The tint path itself is live: switching
> it on moves the room by 7.28 levels. It is being handed the same value at every hour.

Two things that *were* bugs in round 1 are now measurably fixed:

* **The white material's texture was not reaching the screen** (grain 2.31, local 5×5 std 2.92,
  under the "binding bug" line of 2.0). It now measures 8.24 and no 40×40 window on any
  material is free of a Sobel-45 edge.
* **Clipping was deleting shading at r = −0.944.** Pure `#FFFFFF` is 0.00 % of the frame; the
  correlation is no longer computable because no patch is clipped, and the shading ramp on the
  white shell rose from 14.2 to 39.2 levels across 40 px.

One new thing to watch, not yet a defect: `shop_room.png` now cuts the room's silhouette
against the top of the viewport for 806 columns, which is what removed its 240-px flat
roofline from the measurement. The geometry that produced that run is unchanged.

---

## Diagnostic images (`assets/docs/shop/audit2/`)

| file | what it shows |
|---|---|
| `00_before_after.png` | the two frame sets side by side |
| `01_edge_orientation_map.png` | blue = edge within ±4° of a voxel axis, orange = off-axis |
| `02_edge_angle_histogram.png` | edge-energy histogram over 0–180°, peaks marked |
| `03_regions_shop_room.png`, `…_aisle.png` | the **re-cut** region boxes, as measured |
| `04_clipping_map.png` | red = pure `#FFFFFF`, yellow = one channel at 255 |
| `05b_face_patches_*.png` | the relaxed 5-patch rects with their std and grain |
| `06_contact_shadow_*.png` | detected fixture bases and the +4 / +32 px sample lines |
| `07_hour_diff_map.png` | day vs night; magenta = differs by more than 8 levels |
| `08_skyline_*.png` | every flat run in the raw silhouette |
| `08b_skyline_free_*.png` | the same with frame-cut columns marked in red and excluded |
| `09_dead_surface_map_*.png` | magenta = local 5×5 std below 2 |
| `10_floor_residual_*.png` | floor detrended by a fitted 2nd-order surface; magenta = darker |
