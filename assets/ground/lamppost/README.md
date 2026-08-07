# assets/ground/lamppost/

Authored **3D street lamp** for town nights (StreetLamps).

| file | role |
| --- | --- |
| `lamppost_texture.glb` | source model (authoring only; not shipped) |
| `lamppost.mesh.bin` | optimized mesh, `TPR2` format |
| `lamppost.png` | 256×256 basecolor, emissive burnt in |
| `lamppost.meta.json` | bake stats |

Rebuild after replacing the GLB:

```bash
python tools/optimize_lamppost_glb.py
```

If the bake is present, every town lamp uses this model. If missing, the
classic box pole/lantern templates return automatically.

## The bake format

`TPR2` is a header, a vertex block and a `uint16` index block:

```
 0  "TPR2"        8  index count      16  height   24  flame y
 4  vertex count  12  body indices     20  radius   28  flame radius
```

Vertices are `x y z u v shade` as `float32`, the renderer's own format. The
**sign** of `shade` is the face normal's Y (see `vUp` in Voxel3D's shader), so
snow settles on the lamp's shoulders like it does on everything else.

Body indices come first and the lantern's follow. That split is read from the
GLB's own **emissive** map — the panes the author marked as glowing — and it is
what lets `StreetLamps.draw` burn the lantern full-bright after dusk while the
ironwork stays under the hour's tint. `flame y` is where the renderer hangs the
point light that throws the pool on the street.

A bake without a magic word is read as the older headerless layout: all body,
no lantern, flame guessed at four fifths of the height.

## Why the optimizer decimates the way it does

Earlier versions reduced triangles by snapping vertices to a grid and dropping
whatever collapsed. **This deletes the post.** A grid cell wide enough to span
the lantern is far wider than the shaft (~1 world px radius against a 28 px
model), so every vertex in a slice of the shaft merged to a single point, every
triangle in it went degenerate, and what shipped was a lantern floating over a
base plate — with the whole middle of the model simply gone.

`tools/optimize_lamppost_glb.py` now decimates by **quadric edge collapse**,
which only ever merges two vertices that already share an edge. A connected
surface therefore stays connected however hard the budget is pushed: a thin
shaft becomes a coarser thin shaft, it cannot evaporate. UV seams are kept as
boundaries so the atlas does not smear across them.

The tool **verifies** the result and exits non-zero if any height band of the
source lost its triangles or its radius, so a bad bake stops the build instead
of reaching a screen.
