# The VOXEL trees: how to iterate on them

The loop that built the set, in the order that catches mistakes cheapest.
Every step has a way to pass and be wrong; the later steps exist for the
ones the earlier steps cannot see.

```
grow_voxel_tree.py --preview      seconds     shape, tones, budget (offline)
trees_ready_offline.lua           seconds     the loader and the build state machine
tools/deploy.cmd                  seconds     copy to the PC build
tests/run_voxeltree.cmd <tag>     ~7 min      the game: row, paint, wind, A/B, pictures
tests/run_voxeltree.cmd <tag> q   ~2 min      the same up to ROUTE_2, plus the atlas dump
```

## 1. Grow (offline)

```
py tools/grow_voxel_tree.py --preview                 # all four species
py tools/grow_voxel_tree.py --only round --preview    # one
py tools/grow_voxel_tree.py --report                  # counts, no files
```

Writes `assets/ground/tree/voxel/<species>.mesh.bin|.png|.meta.json` and
renders `probe_out_voxeltree/preview_<species>.png` (game camera),
`preview_<species>_wind.png` (leaning: the trunk must stay put),
`preview_sheet.png` and `preview_wood.png` (a 6x4 stand at 16 px spacing
with `Trees3D.placement`'s scale and yaw -- the picture that says whether
the crowns close into a wood or stay parasols).

The bake refuses past `MAX_TRIS` (1200), a foot that flexes, a crown that
does not, any vertex at the card tier, any uv above the card cut. What
costs triangles is TONE PER VOXEL: a face only merges with a neighbour of
the same tone, so dither in patches (blotches), not per cube. `--budget N`
lifts the ceiling for a preview experiment only; `--vox-size` changes the
cube (species are authored at 2 and scaled).

The species live in `SPECIES` (round, tiered, broad, tall): trunk height
and radius, crown centre, lobes (dx, dy, dz, r, ry), rim noise, notches,
tufts, tone shift. Sizes are voxels at VOX = 2; world px = voxels x 2.5.

MagicaVoxel: `--vox tools/_tree_src/vox/<file>.vox --name <n> --height 17
--preview`. Sources and licences in `tools/_tree_src/vox/NOTES.md`.

## 2. Load (offline)

```
py -c "import lupa.lua51 as L, os; os.chdir('.'); L.LuaRuntime().execute(open('tests/trees_ready_offline.lua', encoding='utf-8-sig').read())"
```

Loads the real bakes through the real `Trees3D.lua` with stubs, checks
the sliced build, the sun pass not advancing it, the terminal states, the
caster, the canopy cover. Fails loudly on a bake the game would silently
refuse.

## 3. Deploy and probe (the game)

```
tools\deploy.cmd
tests\run_voxeltree.cmd vt6
```

The probe (`tests/voxeltree_probe.lua`) checks, in order: the row's
values and save migration; that each value loads ITS four species; the
templates (no cards, no uv past the cut, a shadow proxy); the paint on
Pallet, Viridian, Route 2 and Viridian Forest (`Trees3D.lastPaint`: a
palette key, or `shipped (reason)`); the paired sway under a gale with the
weather pinned off; the row flip to 3D and back. Pictures land in
`probe_out_voxeltree/voxeltree_<tag>_*.png`; the log is
`voxeltree_<tag>.log` and ends in `ALL PASS` or `FAILS: n`.

`run_voxeltree.cmd <tag> quick` stops after Route 2 and dumps the atlas
the paint read (`atlas_<tag>_route2.png`) with the tree tile's texels raw
against baked -- the evidence when the paint says `shipped (grey)`.

Rules that cost a round each: the window must be visible (a minimised
game screenshots black); one `gen1recomp.exe` at a time; Viridian (10,10)
is inside the border wood, use (24,22); the wind number inverts when
crowns overlap, so read the rounds won, not the amplitude; pin the weather
off or a shower reads as wind.

## 4. Where things live

| | |
| --- | --- |
| the row | `Trees3D.setting` -- `{ voxel, 3d }`, `Trees3D.SETS` |
| the bakes | `assets/ground/tree/voxel/` (VOXEL), `assets/ground/tree/` (3D) |
| the paint | `Trees3D.finishBuild` -> `paletteTexture` -> `TerrainAtlas.tileShades` |
| the strip layout | `Trees3D.VOXEL_PALETTE` and `grow_voxel_tree.py`'s `slot_of` -- keep in step |
| which maps get trees | `Trees3D.wantsMap` + `authored_trees` in `data/voxel_heights.lua` |
| the wind | `Trees3D.SETS[..].windShare`, Voxel3D's `sway > 0 && packedShade > 0.5` block |
