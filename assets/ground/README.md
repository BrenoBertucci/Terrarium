# assets/ground/

The art the **GROUND** row wears — what the weather leaves on the floor.
Replace a file and it is used instead; nothing else changes, no code, no
constant, no rebuild. Delete one and the mod falls back to a shape it
generates for that layer.

| file | what it is | when it is drawn |
| --- | --- | --- |
| `puddle.png` | pools of standing water | while the ground is wet, at three sizes |
| `print.png` | one pair of footprints, pointing **north** (the mod turns it) | the wet mark a boot leaves stepping out of a puddle |

**The snow is not art any more.** It used to be three strips of drift and
three of crust laid on the ground and the hedges, with `print.png` pressed
into them; all of it read as a white floor with mould on it. The cover, the
drifts, the trench everybody leaves and the footprints along it are drawn by
the scene shader now, out of a deformation field the walkers write
(`lib/SnowField.lua`), and there is no file to replace for them.

Each file is a strip of 16×16 frames laid left to right. **How many** is read
off the image, so a four-frame sheet and a nine-frame one are both fine — the
mod picks one per cell by hash.

## Two rules, and they are the shader's rather than this feature's

**The alpha is the shape.** The scene shader **discards** any texel under
half alpha rather than blending it — that is how a sprite cuts its own
silhouette out of its quad in this mode. A soft airbrushed edge does not fade
out, it vanishes at the halfway line. Draw hard edges; dither
(checkerboard) if you want a fringe that dissolves.

**The RGB is a tone, not a colour.** Every texel is multiplied by the colour
the mod picks — the sky's own hue for a puddle, a cold grey for a wet
footprint — and then again by the hour's light. So draw in **greys**:
they land in the right colour at every hour of the day. A strip drawn in blue
comes out blue times blue at dusk.

## Geometry

Each frame is laid on the ground as a flat quad centred on a map cell, at its
own height above that cell: puddles float 0.7 world pixels and wet prints
1.35. These are depth-test numbers — enough separation that each layer wins
against the ground and against the layers under it, and nothing more. (Through v0.1.x the puddle's
0.7 was also its *identity*: the RTX row recognised standing water by the
fraction of its height, having only a depth buffer to look at. It does not
any more — the ground row stamps a mark into the frame's alpha channel
instead, so these heights are free. See `RayFX.PUDDLE_TAG`.)

Sizes, at their three steps: puddles 13→28 world pixels (basins 18→38).
A pool stays near its own cell so it reads as a pool. Draw each frame centred
in its 16×16 box with a pixel or two of margin.

## `source/`

The contact sheets the old snow strips were cut from, kept for the record
(the strips themselves are gone -- see above) and left out of the packaged
mod (`.modkitignore`) so nobody downloads nine megabytes of paper. The
cutter still works on any sheet:

```bash
powershell -File tools/sheet2strip.ps1 -In assets/ground/source/snowpesado.png -Out assets/ground/snow-ground-3.png -Cols 3 -Rows 2 -BgLo 195 -BgHi 255 -Inset 60
```

It finds the grid, floods the paper out from each cell's edge, crops to the
art's own bounding box across the whole sheet (**one** box, so the drawings
keep their relative sizes), downsamples each cell to 16×16 and renormalises
the tones so the brightest pixel is white.

`-BgLo` / `-BgHi` are the luminance window that counts as paper, and they are
per sheet because every sheet came back on a different background: `0`/`170`
for a dark field, `195`/`255` for a white one, `158`/`222` for a mid grey. A
file with real alpha ignores both. `-Inset` (per mille) skips the drawn
border where one exists; it must not be so large that it cuts into the art,
which is what made two of these come back empty.

