# assets/ground/

The art the **GROUND** row wears — what the weather leaves on the floor.
Replace a file and it is used instead; nothing else changes, no code, no
constant, no rebuild. Delete one and the mod falls back to a shape it
generates for that layer (except the caps, which have no fallback — see
below).

| file | what it is | when it is drawn |
| --- | --- | --- |
| `puddle.png` | pools of standing water | while the ground is wet, at three sizes |
| `print.png` | one pair of footprints, pointing **north** (the mod turns it) | behind every walker in the snow |
| `snow-ground-1.png` | a dusting caught in the seams | first step of a snowfall |
| `snow-ground-2.png` | patches | second step |
| `snow-ground-3.png` | lying, with the ground showing through | third step |
| `snow-cap.png` | a hedge or a tree under snow | on everything you cannot stand on, at three sizes |

Each file is a strip of 16×16 frames laid left to right. **How many** is read
off the image, so a four-frame sheet and a nine-frame one are both fine — the
mod picks one per cell by hash.

The snow has three ground drawings rather than one at three sizes because
that is the difference between snow and water: a pool is the same pool
getting wider, and a snowfall is a different picture at each depth. Scaling
one drawing up could only ever make bigger specks.

## Two rules, and they are the shader's rather than this feature's

**The alpha is the shape.** The scene shader **discards** any texel under
half alpha rather than blending it — that is how a sprite cuts its own
silhouette out of its quad in this mode. A soft airbrushed edge does not fade
out, it vanishes at the halfway line. Draw hard edges; dither
(checkerboard) if you want a fringe that dissolves.

**The RGB is a tone, not a colour.** Every texel is multiplied by the colour
the mod picks — the sky's own hue for a puddle, white for snow, a cold grey
for a footprint — and then again by the hour's light. So draw in **greys**:
they land in the right colour at every hour of the day. A strip drawn in blue
comes out blue times blue at dusk.

## Geometry

Each frame is laid on the ground as a flat quad centred on a map cell, at its
own height above that cell: puddles float 0.7 world pixels, snow 1.0, caps 5
(clear of a hedge's rounded crown) and prints 1.35. These are depth-test
numbers — enough separation that each layer wins against the ground and
against the layers under it, and nothing more. (Through v0.1.x the puddle's
0.7 was also its *identity*: the RTX row recognised standing water by the
fraction of its height, having only a depth buffer to look at. It does not
any more — the ground row stamps a mark into the frame's alpha channel
instead, so these heights are free. See `RayFX.PUDDLE_TAG`.)

Sizes, at their three steps: puddles 14→28 world pixels, snow 13→28, caps
11→19. Snow ends **wider than the 16-pixel cell** so neighbouring drifts
overlap into one field; puddles stay near their own cell so a pool reads as a
pool. Draw each frame centred in its 16×16 box with a pixel or two of margin.

## `source/`

The generator's own contact sheets, kept so the art can be recut and left out
of the packaged mod (`.modkitignore`) so nobody downloads nine megabytes of
paper. Cut them with:

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

Two of the five snow sheets (`snowlevearvore`, `snowpesadoarvore`) have not
been cut successfully yet — their art and their paper are the same tone and
the flood fill walks straight through the outline. `snow-cap.png` is the
medium one, used at all three steps, until those two are recut.
