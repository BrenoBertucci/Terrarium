# assets/ground/grass/

Authored **3D grass tuft** for the voxel overworld.

| file | role |
| --- | --- |
| `grass-texture.glb` | source model (authoring only; not shipped in the mod zip) |
| `grass.mesh.bin` | optimized triangle mesh (stamped per tall-grass tile) |
| `grass.png` | 128×128 basecolor for the mesh |
| `grass.meta.json` | bake stats |

Rebuild after replacing the GLB:

```bash
python tools/optimize_grass_glb.py
```

If these files are present **and** the OPTIONS row **GRASS** is on **3D**,
the mesher uses real 3D tufts with wind + foot-crush. Set **GRASS** to
**VOXEL** for the classic tileset slab even when the bake is installed.
If the bake is missing, the slab is used either way.
