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

If these files are present the mesher uses real 3D tufts with wind + foot-crush.
If missing, the classic tileset slab grass returns automatically.
