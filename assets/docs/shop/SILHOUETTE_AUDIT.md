# Shop interior — silhouette & material audit

Measured, not opined. Every number below comes from a script run over the PNGs the shop probe
wrote; nothing was rendered, no `lib/` file was read or touched.

**Source frames.** `probe_out_shop/` is overwritten on every probe run, and a run landed at
09:13 while this audit was in progress. Everything below was therefore measured on a frozen
copy of the **2026-09-08 09:13** set (`shop_room.png` md5 `f20445b3…`, `shop_aisle.png` md5
`3a46da96…`). The 08:44 set gave the same numbers to within 1–2 % on every measure, so the
findings are not an artefact of one run.

Primary: `shop_room.png`, `shop_aisle.png`. Confirmation: `shop_wall.png`, `shop_counter.png`,
`shop_room_day/dusk/night.png`. Frame is 1536×864 = 1 327 104 px.

Two masks underpin everything: a flood fill from the frame border over dark near-neutral pixels
isolates the **background void**, and pure-black-outlined blobs inside the room isolate the
**2D character sprites**. Sprites are excluded from every geometry measure — they are billboards
and would otherwise pollute the edge and silhouette statistics.

Diagnostic images are in `assets/docs/shop/audit/`.

---

## 0. What the frame is made of

| | px | % of frame | % of room |
|---|---|---|---|
| background void | 812 168 | **61.20 %** | — |
| room (all lit geometry) | 514 936 | 38.80 % | 100 % |
| white fixture material | 88 331 | 6.66 % | 17.15 % |
| floor material | 108 526 | 8.18 % | 21.08 % |
| product material | 12 561 | 0.95 % | 2.44 % |
| 2D character sprites | 28 527 | 2.15 % | 5.54 % |

The room is 38.8 % of the frame. Six pixels in ten are empty void. That is the framing the shot
was authored with, and it is worth stating up front because it caps how much any material fix
can buy.

---

## 1. Edge-orientation histogram — the boxiness index

Sobel over luminance; gradient angle rotated 90° into edge direction, folded to [0°,180°);
background dilated 3 px and sprites removed.

**The three peaks are 0.5° (horizontal), 90.5° (vertical) and 116.5° (the receding ground axis).**
A real isometric scene would show a fourth at 63.5° for the second ground axis — it exists, but at
a quarter of the strength of the horizontal.

| measure | shop_room | shop_aisle | healthy | verdict |
|---|---|---|---|---|
| isotropic baseline (3 peaks × ±4° = 24° of 180°) | 13.3 % | 13.3 % | — | reference |
| edges within ±4° of the 3 peaks, **by count** (mag>24) | 30.2 % | 29.2 % | 20–30 % | ok-looking, but misleading |
| edges within ±4° of the 3 peaks, **by energy** | **50.4 %** | 48.3 % | 30–45 % | high |
| same, strong edges only (mag>180) | 61.3 % | 59.0 % | 35–50 % | high |
| the horizontal peak **alone**, ±4° (a 4.4 % slice of angle space) | **44.6 %** of all edge energy | 42.5 % | ≤15 % | 10× over-represented |
| **coherent contours on-axis** — of edges whose 4 neighbours along their own direction agree within 10° | **82.3 %** | 80.4 % | 45–60 % | **this is the boxiness index** |

The count-weighted number understates the problem. 70 % of edge pixels are "off-axis", but their
mean contour coherence is **0.95 of 4** — they are isolated noise pixels, not shapes. On-axis edges
score **2.53 of 4**. Filter to edges that actually form a continuous line (4/4 neighbours agree) and
**82.3 % of every real contour in the frame lies on exactly three angles.** Those coherent contours
are only 2.21 % of the frame, but they are the entire drawing; everything else is grain.

So: **the boxiness index is 82.3 %.** Nothing in the room draws a line that is not a cube edge.

`audit/01_edge_orientation_map.png` (blue = on-axis, orange = off-axis) and
`audit/02_edge_angle_histogram.png`.

---

## 2. Colour count and flatness

Regions are hand-cut boxes with a material filter inside them, so a stray product pixel inside the
"white" box cannot pollute the statistic. Overlay proof: `audit/03_regions_shop_room.png`
(green = white, blue = floor, red = product).

| | unique colours | % of frame |
|---|---|---|
| whole frame | 40 164 | — |
| room only | 39 089 | 38.8 % |
| **pure `#FFFFFF`** | — | **5.43 % of frame / 14.0 % of the room** |
| **any channel at 255** | — | **11.20 % of frame / 28.9 % of the room** |

| region | px | % screen | unique | most common colour | its share | within ±3 | Lstd | local 5×5 std |
|---|---|---|---|---|---|---|---|---|
| white wall/gondola | 88 331 | 6.66 % | 5 057 | `#FFFFFF` | 31.9 % | **37.7 %** | 16.34 | **2.92** |
| floor | 108 526 | 8.18 % | 7 920 | `#FFFFFF` | 12.8 % | 14.3 % | 35.49 | 5.48 |
| products | 12 561 | 0.95 % | 7 375 | `#FFD936` | 0.38 % | 2.2 % | 35.61 | 14.12 |

Healthy for a lit interior: no single colour above ~5 % of a material, ±3 share under ~10 %,
local 5×5 std of 4–10 on a textured surface.

The finding is **not** "the surfaces are flat-shaded". They carry grain — 39 089 unique colours
in 38.8 % of the frame is a lot. The finding is that **the white is clipped**: 31.9 % of the white
material is exactly `#FFFFFF`, one dead value, and 37.7 % is within ±3 of it. Clipping, not flat
shading, is what makes it read chapado.

The floor is worse than it looks. **Its single most common colour is also `#FFFFFF`** — 12.8 % of
floor pixels. The floor is blown out across the whole band nearest the north wall
(`audit/04_clipping_map.png`; red = pure white, yellow = one channel at 255).

Products are the *noisiest* surface in the frame (local std 14.12) and are never clipped. Their
low ±3 score is simply because the region spans many hues, not because they are well shaded.

---

## 3. Gradient inside a face

Five 40×40 rects placed automatically where all 1 600 pixels are the white material **and** no
hard edge (Sobel > 45) falls inside. Rects drawn in `audit/05_face_patches_shop_room.png`.
`Lstd` is the raw answer to the question; `ramp` is a least-squares plane fit (the shading
gradient) and `grain` is the residual after removing it (the texture).

| # | x,y | Lmean | **Lstd** | shading ramp (p2p) | **grain residual** | % `#FFFFFF` |
|---|---|---|---|---|---|---|
| 1 | 765, 95 | 254.5 | **1.42** | 1.96 | 1.30 | 66.9 % |
| 2 | 475, 95 | 242.1 | 9.82 | 36.56 | 2.69 | 1.8 % |
| 3 | 630, 95 | 253.3 | 3.24 | 8.60 | 2.32 | 46.6 % |
| 4 | 540, 95 | 248.9 | 7.09 | 23.98 | 3.17 | 11.3 % |
| 5 | 585, 95 | 251.7 | 5.00 | 15.40 | 3.01 | 31.2 % |
| | **mean** | | **5.31** | 17.30 | **2.50** | |

Healthy: Lstd 4–6 with a grain residual of 3–6. Below ~2 the texture is not reaching the screen.

Two separate readings, and they point in opposite directions:

- **The shading is fine where it survives.** Patch 2 has a 36.6-level ramp across 40 px. The
  renderer does compute per-face gradient.
- **The texture is not.** The grain residual is **2.50 mean, 1.30 at worst** — at or below the
  "not reaching the screen" line on every patch. Whatever texture the material carries arrives as
  ±2 levels of dither.

The two are linked, and the correlation is not subtle. Across all 11 patches measured:

| | shading ramp p2p | Lstd | grain |
|---|---|---|---|
| correlation with % clipped | **−0.944** | −0.957 | −0.753 |
| patches under 20 % clipped (n=4) | 30.9 | 8.54 | 2.77 |
| patches over 50 % clipped (n=4) | **4.7** | 2.11 | 1.72 |

**Clipping destroys the shading with r = −0.94.** A face that is 60 % blown has a 4.7-level ramp
where an unblown one has 30.9. The form is being computed and then thrown away by exposure.

One more number: in `shop_room.png` only **43 of 1 232 704** possible 40×40 window positions sit
inside the floor without crossing a grout line — and in `shop_aisle.png`, **zero**. The floor tile
grid is finer than 40 px everywhere on screen.

---

## 4. Contact shadow

For every floor pixel, the vertical distance up to the nearest fixture pixel. `audit/06_contact_shadow_shop_room.png`
marks the detected bases (magenta), +4 px (cyan) and +32 px (yellow).

Whole-screen profile, all fixture/floor junctions, referenced to the 25–32 px band:

| distance below the base | n | mean floor L | vs 25–32 px |
|---|---|---|---|
| 1–2 px | 3 205 | 180.2 | **−27.5** |
| 3–4 px | 2 947 | 201.1 | −6.6 |
| 5–8 px | 5 338 | 208.2 | +0.5 |
| 9–16 px | 8 976 | 204.6 | −3.1 |
| 17–24 px | 8 015 | 207.7 | 0.0 |
| 25–32 px | 7 242 | 207.7 | 0.0 |
| 33–48 px | 11 712 | 215.0 | +7.3 |

The only darkening is **1–2 px wide**. That is the anti-aliased edge fringe where the fixture
silhouette blends into the floor, not a shadow. By 5 px the floor is back to its own average and
stays within ±4 levels all the way out.

Three fixtures individually, corrected against each fixture's own local floor ramp (fitted on
d = 14…44 px and extrapolated back, so the floor's global brightness gradient cannot fake a result):

| fixture | frame | 0–4 px | 4–8 px | 8–16 px | 16–32 px | clipped at contact |
|---|---|---|---|---|---|---|
| cardboard box | room | **−16.6** | −5.2 | −2.2 | +2.1 | 0 % |
| gondola shelf | room | −1.9 | +22.1 | −16.8 | +2.6 | 38.6 % |
| checkout counter | room | **+26.3** | +24.2 | +9.2 | — | 0 % |
| cardboard box | aisle | +0.3 | +0.7 | −4.4 | +1.4 | 0 % |
| gondola shelf | aisle | **+66.2** | +48.9 | −23.1 | +2.7 | **100 %** |
| checkout counter | aisle | +11.5 | +10.2 | — | — | 0 % |
| | **mean** | **+14.3** | | | | |

Healthy: −40 to −80 levels at contact, decaying smoothly over 15–30 px.

**There is no contact shadow.** On average the floor at a fixture's base is **14 levels brighter**
than that fixture's own floor ramp predicts. The single exception is the cardboard box in
`shop_room` (−16.6, gone by 8 px) — one prop, at roughly a third of the depth a real contact
shadow would have. At the gondola in `shop_aisle` the contact band is **100 % clipped to 255**, so
no shadow could be represented there even if one were computed.

---

## 5. Response to the hour

The probe log already reports `max tint spread 0.000`. Confirmed, and worth stating precisely.

A naive frame diff is misleading: 73 % of pixels differ between `day` and `night`. That is the NPCs
walking between shots plus per-frame dither. Measured instead on **static geometry only** (the north
fixture rim and the right exterior wall, where no character can walk):

| | R | G | B | L |
|---|---|---|---|---|
| `shop_room_day` | 223.430 | 223.657 | 220.653 | 223.392 |
| `shop_room_dusk` | 223.573 | 223.822 | 220.825 | 223.553 |
| `shop_room_night` | 223.785 | 224.048 | 221.119 | 223.781 |

| measure | value | healthy |
|---|---|---|
| day→night luminance swing on static geometry | **0.389 of 255 = 0.15 %** | 25–45 % |
| mean absolute difference per channel, day↔night | 0.65 | — |
| static pixels that differ at all | 62.3 % | — |
| …of those, differing by only 1–2 levels | **88.5 %** | — |
| tint reported by the probe at all three hours | 0.882, 0.900, 0.918 | should vary |

So: **pixels do change, and it is all dither.** Night is 0.39 levels *brighter* than day — the
wrong direction, and 64× smaller than the noise floor of the products' own grain.

The wiring itself is live. The plain `[room]` shot runs untinted at L = 242.05 on the same static
geometry; the `[hours]` shots run at 223.39. Applying the hour tint moves the room by **18.7 levels
(7.7 %)**. The tint path works — it is being handed the same constant three times.

`audit/07_hour_diff_map.png` (magenta = differs by more than 8, cyan = 1–8).

---

## 6. Height variety in the silhouette

Topmost non-background pixel per column. `audit/08_skyline_shop_room.png` draws every flat run
(magenta ≥ 32 px, green shorter) with the longest highlighted.

| measure | shop_room | shop_aisle | shop_wall | shop_counter | healthy |
|---|---|---|---|---|---|
| silhouette width | 1 163 px | 1 180 px | 1 212 px | 1 175 px | — |
| **longest perfectly horizontal run** | **240 px (20.6 % of width)** | 75 px (6.4 %) | 30 px (2.5 %) | 30 px (2.6 %) | ≤ 40 px / ≤ 5 % |
| skyline sitting in runs ≥ 32 px | **53.7 %** | 50.3 % | 0 % | 0 % | ≤ 20 % |
| distinct height levels | 346 | 384 | 433 | 403 | — |
| plateaus (maximal flat runs) | 484 | 519 | 570 | 512 | — |
| median plateau length | 1 px | 1 px | 1 px | 1 px | — |

The 346 "levels" and 484 "plateaus" look like variety and are not. Their median length is 1 px —
that is the diagonal descent of the dollhouse side walls, one step per column. The real structure
is at the top:

> **In `shop_room.png`, three runs at y = 88, 89 and 90 (240 + 200 + 184 = 624 px) account for
> 53.7 % of the entire 1 163-px skyline.**

Isolating the roofline (columns within 40 px of the highest point):

| | shop_room | shop_aisle |
|---|---|---|
| roofline width | 732 px (62.9 % of the silhouette) | 718 px (60.8 %) |
| within ±2 px of one single height | **91.5 %** | 52.9 % |
| mean absolute slope | 0.134 px per column | 0.134 px per column |

**91.5 % of the roofline is one height.** That is the single feature that reads as "caixa" — a
240-pixel dead-straight top edge with nothing breaking it. `shop_wall` and `shop_counter` score far
better (30 px longest run) only because their camera tilts the same rim off the horizontal; the
geometry is identical, so this is a shot-selection sensitivity, not a fix.

---

## Ranking — by how much of the screen each defect touches

Overlap is accounted for: clipping and dead surface share 6.77 % of the frame, so they are also
given as a union rather than summed.

| # | defect | % of frame | % of the room | what it is |
|---|---|---|---|---|
| 1 | **Empty background void** | **61.20 %** | — | the room occupies 38.8 % of a 1536×864 frame; six pixels in ten are black |
| 2 | **Zero response to the hour** | **38.80 %** | 100 % | every room pixel is identical at day, dusk and night to within 0.15 % |
| 3 | **Blown-out / dead surface (union)** | **14.31 %** | **36.9 %** | 27.3 % of it is the white material, 13.0 % the floor |
| 3a | — clipped (any channel at 255) | 10.78 % | 27.8 % | destroys shading with r = −0.94 |
| | *(11.20 % / 28.9 % if the sprites' own white pixels are counted, as in §2)* | | | |
| 3b | — dead surface (local 5×5 std < 2) | 10.30 % | 26.5 % | 39.7 % of all white, 16.9 % of all floor |
| 4 | **No contact shadow** | 2.69 % | 6.9 % | the floor within 32 px of a fixture base |
| 5 | **Boxy contour set** | 2.21 % | 5.7 % | small in area, but it is 100 % of the line work: 82.3 % of coherent contours on 3 angles |
| 6 | **Flat roofline** | ~0.02 % | — | 240 px of dead-straight edge; 53.7 % of the skyline, 91.5 % of the roofline at one height |

Area is not importance, and rows 5 and 6 are the clearest case. The coherent contours are 2.21 % of
the pixels and are the entire drawing — every other edge pixel is grain. A 240-px straight line is
~0.02 % of the frame and is the thing the eye names when it says "box".

Read the table as two separate problems:

- **Rows 1, 2, 3 are exposure and framing.** They are large, cheap to verify, and row 3 is
  actively deleting shading the renderer already computes (r = −0.94). Pulling exposure down is the
  highest-yield single change measured here: it recovers a 30-level ramp on 27.8 % of the room.
- **Rows 4, 5, 6 are form.** They are small in area and are what actually makes the room read as a
  stack of boxes. No exposure change touches them.

---

## Diagnostic images

| file | what it shows |
|---|---|
| `audit/01_edge_orientation_map.png` | blue = edge within ±4° of a voxel axis, orange = off-axis |
| `audit/02_edge_angle_histogram.png` | edge-energy histogram over 0–180°, peaks marked |
| `audit/03_regions_shop_room.png`, `…_aisle.png` | the hand-cut regions, as measured |
| `audit/04_clipping_map.png` | red = pure `#FFFFFF`, yellow = one channel at 255 |
| `audit/05_face_patches_shop_room.png`, `…_aisle.png` | the 40×40 in-face rects with their std and grain |
| `audit/06_contact_shadow_shop_room.png`, `…_aisle.png` | detected fixture bases and the +4 / +32 px sample lines |
| `audit/07_hour_diff_map.png` | day vs night; magenta = differs by more than 8 levels |
| `audit/08_skyline_shop_room.png`, `…_aisle.png` | every flat run in the silhouette, longest highlighted |
| `audit/09_dead_surface_map_shop_room.png`, `…_aisle.png` | magenta = local 5×5 std below 2 |
