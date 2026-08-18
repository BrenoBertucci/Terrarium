# Buildings not yet voxelized

Status of the 34 catalogued drawings against the `buildings` list in
`data/voxel_heights.lua`. Coverage is **33 of 34 drawings, 146 of 147
placements**. One is left, and it is out of scope by decision, not by
accident.

(Counting note: the catalogue's per-building tables list one row per DOOR,
so B19, B22 and B23 each appear twice for a single placement. 150 rows,
147 placements. This page counts placements.)

| id | tileset | cells | px | used | status |
| --- | --- | --- | --- | --- | --- |
| [B19](B19-unnamed-building.md) | `PLATEAU` | 20 x 5 | 320x80 | 1x | **done** -- the first `parts` template (premium kit F5) |
| [B23](B23-unnamed-building.md) | `PLATEAU` | 18 x 3 | 288x48 | 1x | **done** -- ported from the reference tool, which always had it while the Lua data never did |
| [B30](B30-unnamed-building.md) | `OVERWORLD` | 6 x 4 | 96x64 | 1x | **done** -- `topRows` composites the ROUTE_10 half (`pokemon_tower` + its `claimOnly` twin) |
| [B32](B32-unnamed-building.md) | `SHIP_PORT` | 8 x 3 | 128x48 | 1x | **out of scope** -- not a building |

## How each blocker fell

**B30 — the Pokemon Tower.** The catalogue read it as "truncated by the
map edge; no roof drawn" — but the roof IS drawn, on the neighbouring
map: the drawing straddles the LAVENDER_TOWN / ROUTE_10 boundary, and
its 64px purple roof band stands in the route's last rows. `topRows`
composites those rows above the matched grid so the model is built from
the complete twenty-row drawing, and a `claimOnly` twin claims the
ROUTE_10 cells so the roof half does not also stand as its own building.
No `synthOutline`, no `roofCap`: the "missing" roof was a missing half
of the drawing, not missing art.

**B19 — the Indigo Plateau.** Two structures in one drawing: the
plateau's full-width retaining wall, and the League lobby punching
through it. The band table cannot say "and the wall stops here", so the
premium kit's F5 added `parts`: each part is a tile-rect crop of the
drawing with its own band table, standing over its own z span of the
footprint; the model is the union, and faces where the parts touch cull
each other. Both facades are drawn 32px, so the wall top and the lobby
roof come out flush — which is what the drawing meant.

**B23 — the Victory Road entrance.** Was voxelized "without trouble" in
`tools/building_voxels.py` — and then never ported: the Lua data had a
comment pointing at an entry "at the bottom of this file" that was not
there. It is now, under `buildings.PLATEAU`, with the kit's carpentry
switched off (`eaveOut = 0`, `sill = false`: a rock face grows no eaves).

## B32 - the S.S. Anne

`VERMILION_DOCK` (10,3). A ship in three-quarter perspective, with a hull,
deck, funnels and gangway.

It is the **only asymmetric drawing in the catalogue** (`top[x]` does not
mirror), which by itself fails the reference tool's symmetry assert. Its
silhouette is largely fine, but the band table does not describe it at any
setting: there is no roof-from-above band, no face-on facade, and no taper
that means elevation. Voxelizing the S.S. Anne means a different archetype,
not a band table — and the premium kit plan (2026-08-17) ruled it out of
scope on purpose.
