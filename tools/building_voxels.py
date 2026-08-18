"""Reference implementation of the building voxelizer -- the Python half of
the dual-implementation parity check demanded by
assets/docs/buidling_to_voxel/sprite_to_voxel_methodology.md (Stage 5).

It composites a building out of the tileset atlas exactly the way the map
does, extracts palette + silhouette (light-only flood fill), builds the
voxel model with the same rules lib/Buildings.lua ships, asserts the
geometric intent, and renders isometric previews.

    python mods/DRAMATIC_SHAPE/tools/building_voxels.py [outdir]

Keep the TEMPLATES table below in sync with the `buildings` section of
data/voxel_heights.lua: the two implementations are meant to be
independent restatements of the same algorithm, and the voxel/shell
counts they print must match.
"""
import os
import sys
from collections import deque, Counter
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))
TILESETS = os.path.join(ROOT, "assets/generated/tilesets")
PER_ROW = 16

WHITE, GREY, DARK, BLACK = 0, 1, 2, 3          # by luminance, light first

# --- the shape profile, mirroring data/voxel_heights.lua's `buildings` ------
TEMPLATES = {
    # B07: Red's house / Blue's house / Bill's / the Copycat's -- 7 placements
    "gabled_house": dict(
        tiles=[
            [5, 6, 7, 7, 7, 7, 8, 9],
            [21, 22, 23, 23, 23, 23, 24, 25],
            [37, 38, 10, 34, 10, 10, 40, 41],
            [92, 23, 23, 23, 23, 23, 23, 93],
            [15, 34, 11, 12, 10, 10, 34, 31],
            [78, 26, 27, 28, 26, 26, 26, 79],
        ],
        roof_rows=16, roof_back=7, roof_front=9, roof_cycle=(5, 8),
        slab=4, front_eave=4, ledge=(24, 31),
    ),
    # B31: Oak's lab -- the same architecture with a roof band twice as deep
    "lab": dict(
        tiles=[
            [5, 6, 83, 83, 83, 83, 83, 83, 83, 83, 8, 9],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25],
            [37, 38, 10, 10, 10, 75, 75, 10, 10, 10, 40, 41],
            [15, 34, 34, 34, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 11, 12, 10, 10, 10, 10, 10, 31],
            [78, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B03: the flat-roofed commercial block -- 15 placements, the most of
    # any voxelized drawing. The lattice is drawn from straight above, so
    # the measured taper is flat; the eave course is the roof's own south
    # rim, lab-style. Its sprite is inset from its box: the outer columns
    # carry no roof.
    "flat_commercial": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 11, 12, 75, 75, 75, 31],
            [78, 26, 27, 28, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B05: every Pokemon Center in the game (Celadon, Cerulean,
    # Cinnabar, Fuchsia, Lavender, Pewter, Saffron, Vermilion, Viridian,
    # Mt Moon, Rock Tunnel). B03's block with the POKe sign hung beside
    # the door; the sign is too wide to be a pane, so it stays flush.
    "pokecenter": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 11, 12, 66, 67, 75, 31],
            [78, 26, 27, 28, 74, 74, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B06: every Poke Mart (Cerulean, Cinnabar, Fuchsia, Lavender,
    # Pewter, Saffron, Vermilion, Viridian). The Center's twin, MART on
    # the sign.
    "pokemart": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 11, 12, 68, 69, 75, 31],
            [78, 26, 27, 28, 74, 74, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B02: the plain 4x4 block: one window course over blank brick and
    # no door. 15 placements, scenery in every city bar the Celadon Mart
    # roof stair.
    "flat_block_4x4": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 75, 75, 75, 31],
            [78, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B08: the same block two cells deeper, 6 placements, all scenery.
    "flat_block_4x6": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 75, 75, 75, 31],
            [78, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B13: the 6x4 scenery block, 4 placements.
    "flat_block_6x4": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B14: the 6x6 scenery block, 3 placements.
    "flat_block_6x6": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B27: the 8x4 scenery block, one placement on Route 11.
    "flat_block_8x4": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B09: the wide storefront: Celadon's Game Corner, the Pokemon
    # Mansion, Cinnabar Lab, the Safari Zone gate and Fuchsia's meeting
    # room.
    "game_corner": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 31],
            [78, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B15: Celadon Mansion and the Route 6 and Route 12 gates.
    "celadon_mansion": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 31],
            [78, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B18: the Route 2 gate, and the museum's east entrance beside it in
    # Pewter. The museum hall itself is B24 below -- a sloped roof.
    "route_2_gate": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 11, 12, 75, 75, 75, 75, 75, 75, 75, 31],
            [78, 26, 27, 28, 26, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B29: Fuchsia Gym, the block with GYM on the sign.
    "fuchsia_gym": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 34, 47, 63, 34, 10, 10, 10, 31],
            [15, 75, 75, 75, 34, 34, 34, 34, 75, 75, 75, 31],
            [15, 75, 11, 12, 10, 10, 10, 10, 75, 75, 75, 31],
            [78, 26, 27, 28, 26, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B28: the Route 5 underground-path gate.
    "route_5_gate": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 31],
            [78, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B21: the Route 22 league gate, the widest of the family at 12
    # cells.
    "route_22_gate": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 75, 75, 75, 75, 31],
            [78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B25: the Power Plant.
    "power_plant": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 31],
            [78, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B22: Celadon's department store: six window courses over the MART
    # sign.
    "celadon_mart": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 75, 75, 10, 10, 75, 75, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 11, 12, 10, 10, 11, 12, 10, 10, 68, 69, 75, 31],
            [78, 26, 26, 26, 27, 28, 26, 26, 27, 28, 26, 26, 74, 74, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B20: Silph Co. Twelve cells of plot and ten courses of windows
    # under the same roof band, so it stands as the tallest thing in
    # Kanto.
    "silph_co": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 75, 75, 75, 75, 31],
            [78, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B24: the Pewter museum's hall, and the only building in the family
    # with a SLOPED roof: the same 2:1 taper the lab and Red's house are
    # drawn with, over a roof band twice the lab's depth. The drawing
    # repeats its whole lattice-and-course motif -- rows 8..31 again at
    # 32..55 -- which is what fixes the cycle at 24 rather than the bare
    # lattice's 8: the drawing proves the period. The last band (rows
    # 56..63) is the roof's fascia, wider than the wall it covers, so it
    # stays in the roof band and lands on the south rim.
    "museum": dict(
        tiles=[
            [ 5,  6, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25],
            [37, 38, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 40, 41],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 31],
            [78, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=64, roof_back=8, roof_front=8, roof_cycle=(8, 31),
        slab=4, front_eave=4, ledge=None,
    ),
    # B10: the gym. Cinnabar, Pewter, Vermilion and Viridian wear this
    # drawing, and so does the Fighting Dojo next door to Saffron's.
    # Oak's lab's roof band exactly, tile for tile, over a facade with
    # GYM on the sign.
    "gym": dict(
        tiles=[
            [ 5,  6, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25],
            [37, 38, 10, 10, 34, 47, 63, 34, 10, 10, 40, 41],
            [15, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 11, 12, 10, 31],
            [78, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B16: the big-city gym: Celadon, Cerulean and Saffron. Two cells
    # wider than the standard gym, and it carries the GYM sign twice.
    "gym_large": dict(
        tiles=[
            [ 5,  6, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25],
            [37, 38, 10, 10, 34, 47, 63, 34, 34, 47, 63, 34, 10, 10, 40, 41],
            [15, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 11, 12, 10, 31],
            [78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B01: the commonest drawing in the game at 19 placements, and every
    # one of them scenery: a gabled block with two window courses and no
    # door. Red's house's roof band, tile for tile, but no awning under
    # it.
    "gabled_block_4x3": dict(
        tiles=[
            [ 5,  6,  7,  7,  7,  7,  8,  9],
            [21, 22, 23, 23, 23, 23, 24, 25],
            [37, 38, 10, 10, 10, 10, 40, 41],
            [15, 34, 34, 34, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 31],
            [78, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=16, roof_back=7, roof_front=9, roof_cycle=(5, 8),
        slab=4, front_eave=4, ledge=None,
    ),
    # B04: the little 4x2 cottage, 12 placements and nearly all of them
    # somebody's home: Mr Fuji's, the Cubone house, Bill's grandpa's,
    # the Name Rater's, the Viridian school house, the Route 8
    # underground path.
    "gabled_cottage": dict(
        tiles=[
            [ 5,  6,  7,  7,  7,  7,  8,  9],
            [21, 22, 23, 23, 23, 23, 24, 25],
            [37, 38, 11, 12, 10, 10, 40, 41],
            [78, 26, 27, 28, 26, 26, 26, 79],
        ],
        roof_rows=16, roof_back=7, roof_front=9, roof_cycle=(5, 8),
        slab=4, front_eave=4, ledge=None,
    ),
    # B17: the wide 6x2 house: Cerulean's badge, trade and trashed
    # houses.
    "gabled_house_wide": dict(
        tiles=[
            [ 5,  6,  7,  7,  7,  7,  7,  7,  7,  7,  8,  9],
            [21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25],
            [37, 38, 11, 12, 35, 10, 10, 35, 10, 10, 40, 41],
            [78, 26, 27, 28, 26, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=16, roof_back=7, roof_front=9, roof_cycle=(5, 8),
        slab=4, front_eave=4, ledge=None,
    ),
    # B11: the 6x2 scenery block, 5 placements, no door.
    "gabled_block_6x2": dict(
        tiles=[
            [ 5,  6,  7,  7,  7,  7,  7,  7,  7,  7,  8,  9],
            [21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25],
            [37, 38, 10, 34, 35, 10, 10, 35, 10, 10, 40, 41],
            [78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=16, roof_back=7, roof_front=9, roof_cycle=(5, 8),
        slab=4, front_eave=4, ledge=None,
    ),
    # B34: the 4x2 scenery block, one placement in Fuchsia.
    "gabled_block_4x2": dict(
        tiles=[
            [ 5,  6,  7,  7,  7,  7,  8,  9],
            [21, 22, 23, 23, 23, 23, 24, 25],
            [37, 38, 10, 34, 10, 10, 40, 41],
            [78, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=16, roof_back=7, roof_front=9, roof_cycle=(5, 8),
        slab=4, front_eave=4, ledge=None,
    ),
    # B33: the Route 5 day care.
    "daycare": dict(
        tiles=[
            [ 5,  6, 83, 83, 83, 83,  8,  9],
            [21, 56, 18, 18, 18, 18, 56, 25],
            [21, 56, 18, 18, 18, 18, 56, 25],
            [21, 22, 23, 23, 23, 23, 24, 25],
            [37, 38, 10, 10, 10, 10, 40, 41],
            [15, 34, 34, 34, 34, 34, 34, 31],
            [15, 10, 10, 10, 11, 12, 10, 31],
            [78, 26, 26, 26, 27, 28, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B26: the Route 10 scenery block, structurally the museum's twin.
    # Needs `seal`: its drawing has no black base course, so unsealed
    # the flood climbs in from the south border and hollows the wall out
    # (72% surviving in 65 pieces, against 95% in one).
    "gabled_block_6x6": dict(
        tiles=[
            [ 5,  6, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25],
            [37, 38, 34, 34, 34, 34, 34, 34, 34, 34, 40, 41],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
        ],
        roof_rows=64, roof_back=8, roof_front=8, roof_cycle=(8, 31),
        slab=4, front_eave=4, ledge=None, seal="s",
    ),
    # B12: the Safari Zone rest houses. A corrugated roof over a plank
    # facade; the stripe repeats every 5 rows, not the OVERWORLD
    # lattice's 8.
    "safari_rest_house": dict(
        tiles=[
            [ 8,  9,  9,  9,  9,  9,  9, 12],
            [24, 25, 25, 25, 25, 25, 25, 28],
            [40, 41, 42, 43,  1,  1, 41, 44],
            [56, 41, 58, 59, 41, 41, 41, 60],
        ],
        roof_rows=17, roof_back=5, roof_front=3, roof_cycle=(5, 9),
        slab=4, front_eave=4, ledge=None, tileset="forest",
    ),
    # B23: the Victory Road entrance on Route 23: a rock face with two
    # barred doors. The roof band is the pale cliff top seen from above.
    "victory_road_gate": dict(
        tiles=[
            [37, 38,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3, 37, 38],
            [40, 41, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 40, 41],
            [21, 22, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 46, 47,  3,  3,  3,  3,  3,  3,  3,  3, 46, 47, 15, 15, 15, 15, 15, 15, 21, 22],
            [ 5,  6, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 46, 47,  3,  3,  3,  3,  3,  3,  3,  3, 46, 47, 15, 15, 15, 15, 15, 15,  5,  6],
            [ 5,  6, 15, 15, 15, 15, 15, 15, 11, 12, 15, 15, 15, 15, 15, 15, 46, 47,  3,  3,  3,  3,  3,  3,  3,  3, 46, 47, 11, 12, 15, 15, 15, 15,  5,  6],
            [21, 22, 14, 14, 14, 14, 14, 14, 27, 28, 14, 14, 14, 14, 14, 14, 46, 47,  3,  3,  3,  3,  3,  3,  3,  3, 46, 47, 27, 28, 14, 14, 14, 14, 21, 22],
        ],
        roof_rows=16, roof_back=7, roof_front=8, roof_cycle=(9, 12),
        slab=4, front_eave=4, ledge=None, tileset="plateau",
        # a rock face, not a building: the cliff top gets no carpentry
        eave_out=0, recess_depth=1, sill=False,
    ),
    # B19: the Indigo Plateau -- TWO structures in one drawing, which is
    # what defeated the single band table (see REMAINING.md). `parts`
    # splits the drawing into stacked footprints, each with its own band
    # table and its own z span of the template's footprint:
    #   - the plateau's retaining wall, full width, standing at the back
    #     (rows r1-r6: the rim band, the terrace paving seen from above,
    #     and the 32px rock face);
    #   - the League lobby punching through it, 8 cells wide, standing in
    #     front (its flat roof is drawn r1-r5, fascia r6, facade r7-r10).
    # `trim` drops the top 4px of ground above the drawn rim so each
    # part's profile starts at its own first drawn row.
    "indigo_plateau": dict(
        tiles=[
            [37, 38,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3, 37, 38],
            [40, 41, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 32, 33,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3, 32, 33, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 40, 41],
            [21, 22, 15, 15, 15, 15, 15, 15, 21, 22, 15, 15, 46, 47,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3, 46, 47, 15, 15, 21, 22, 15, 15, 15, 15, 15, 15, 21, 22],
            [ 5,  6, 15, 15, 15, 15, 15, 15,  5,  6, 15, 15, 46, 47,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3, 46, 47, 15, 15,  5,  6, 15, 15, 15, 15, 15, 15,  5,  6],
            [ 5,  6, 15, 15, 15, 15, 15, 15,  5,  6, 15, 15, 37, 38,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3, 37, 38, 15, 15,  5,  6, 15, 15, 15, 15, 15, 15,  5,  6],
            [21, 22, 14, 14, 14, 14, 14, 14, 21, 22, 14, 14, 40, 41, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 40, 41, 14, 14, 21, 22, 14, 14, 14, 14, 14, 14, 21, 22],
            [35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 21, 22, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 21, 22, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35],
            [45, 35, 35, 35, 45, 35, 35, 35, 45, 35, 35, 35,  5,  6, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,  5,  6, 45, 35, 35, 35, 45, 35, 35, 35, 45, 35, 35, 35],
            [35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35,  5,  6, 15, 15, 15, 15, 11, 12, 11, 12, 15, 15, 15, 15,  5,  6, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35, 35],
            [35, 35, 45, 35, 35, 35, 45, 35, 35, 35, 45, 35, 21, 22, 14, 14, 14, 14, 27, 28, 27, 28, 14, 14, 14, 14, 21, 22, 35, 35, 45, 35, 35, 35, 45, 35, 35, 35, 45, 35],
        ],
        tileset="plateau", slab=4,
        parts=[
            # the retaining wall: rim (r1) as the roof's north band, the
            # terrace paving (r2) as its field and front, the rock face
            # (r3-r6) as the facade
            dict(rows=(1, 6), z=(0, 48),
                 roof_rows=16, roof_back=8, roof_front=4, roof_cycle=(8, 11),
                 front_eave=0, eave_out=0, recess_depth=1, sill=False),
            # the lobby: flat roof drawn r1-r5, fascia r6, facade r7-r10.
            # The crop's own borders cut through the pale roof field, so
            # every side but the ground line is sealed.
            dict(rows=(1, 10), cols=(13, 28), z=(48, 80), seal="new",
                 roof_rows=48, roof_back=8, roof_front=8, roof_cycle=(8, 15),
                 front_eave=4, eave_out=0, recess_depth=1, sill=False),
        ],
    ),
}

# a recess is a window or a doorway: a non-black region the art seals off
# behind its own black frame. Anything wider or taller than this is a band
# of the facade itself (siding courses, the awning's grey field).
RECESS_MAX = 24


# --------------------------------------------------------------- stage 1 --
def sprite(tiles, seal="", tileset="overworld"):
    """Composite the building and read it the way Structures reads the map:
    palette index per pixel plus the light-only silhouette flood.

    `seal` names the sides the drawing runs off (a string of n/s/e/w). The
    flood does not seed there: a drawing trimmed flush to its art, whose
    base course is brick rather than the black threshold every other
    building stands on, would otherwise be hollowed out through its own
    mortar."""
    atlas = Image.open(os.path.join(TILESETS, tileset + ".png")).convert("RGB")
    h, w = len(tiles), len(tiles[0])
    W, H = w * 8, h * 8
    im = Image.new("RGB", (W, H))
    for r, row in enumerate(tiles):
        for c, t in enumerate(row):
            ax, ay = (t % PER_ROW) * 8, (t // PER_ROW) * 8
            im.paste(atlas.crop((ax, ay, ax + 8, ay + 8)), (c * 8, r * 8))
    px = im.load()

    counts = Counter(px[x, y] for y in range(H) for x in range(W))
    lum = lambda c: 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
    pal = sorted(counts, key=lambda c: -lum(c))      # white, grey, dark, black
    assert len(pal) == 4, pal
    idx = {c: i for i, c in enumerate(pal)}
    col = [[idx[px[x, y]] for x in range(W)] for y in range(H)]

    # The flood spreads only through LIGHT pixels: the black outline and the
    # #555 shading together are the boundary. A "not black" threshold lets it
    # eat the shaded flanks and the silhouette collapses.
    out = [[False] * W for _ in range(H)]
    q = deque()

    def seed(x, y):
        if not out[y][x] and col[y][x] <= GREY:
            out[y][x] = True
            q.append((x, y))

    for x in range(W):
        if "n" not in seal:
            seed(x, 0)
        if "s" not in seal:
            seed(x, H - 1)
    for y in range(H):
        if "w" not in seal:
            seed(0, y)
        if "e" not in seal:
            seed(W - 1, y)
    while q:
        x, y = q.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < W and 0 <= ny < H:
                seed(nx, ny)

    # source texel per pixel, so every voxel can name where its colour came from
    src = [[((tiles[y // 8][x // 8] % PER_ROW) * 8 + x % 8,
             (tiles[y // 8][x // 8] // PER_ROW) * 8 + y % 8)
            for x in range(W)] for y in range(H)]
    return dict(W=W, H=H, col=col, out=out, src=src, pal=pal)


# --------------------------------------------------------------- stage 2 --
def profile(sp, t):
    """Everything the band table implies, measured off the mask."""
    W, H = sp["W"], sp["H"]
    inside = lambda x, y: 0 <= x < W and 0 <= y < H and not sp["out"][y][x]

    # the taper IS the slope: the topmost drawn row of each column
    top = []
    for x in range(W):
        r = next((y for y in range(H) if inside(x, y)), t["roof_rows"])
        top.append(min(r, t["roof_rows"]))

    wall_h = H - t["roof_rows"]
    ytop = wall_h - 1 + t["slab"]

    # Recesses: the panes the art seals behind a black frame. Non-black
    # pixels of the facade split into components across the black outline;
    # a component small enough to be a window or a doorway sinks. A pane
    # whose bottom reaches the base course is a DOORWAY (keeps the classic
    # one-voxel recess); the rest are windows (sink recess_depth, and feed
    # the sill mask -- one proud voxel on the frame row under each pane,
    # except a pane nested inside a doorway).
    wall_y0 = t["roof_rows"]
    comp = {}
    recess = set()
    door = set()
    door_boxes, win_boxes = [], []
    for sy in range(wall_y0, H):
        for sx in range(W):
            if (sx, sy) in comp or not inside(sx, sy) or sp["col"][sy][sx] == BLACK:
                continue
            cells, stack = [], [(sx, sy)]
            comp[(sx, sy)] = True
            x0 = x1 = sx
            y0 = y1 = sy
            while stack:
                cx, cy = stack.pop()
                cells.append((cx, cy))
                x0, x1 = min(x0, cx), max(x1, cx)
                y0, y1 = min(y0, cy), max(y1, cy)
                for nx, ny in ((cx + 1, cy), (cx - 1, cy),
                               (cx, cy + 1), (cx, cy - 1)):
                    if (ny >= wall_y0 and (nx, ny) not in comp
                            and inside(nx, ny)
                            and sp["col"][ny][nx] != BLACK):
                        comp[(nx, ny)] = True
                        stack.append((nx, ny))
            if x1 - x0 + 1 <= RECESS_MAX and y1 - y0 + 1 <= RECESS_MAX:
                recess.update(cells)
                if y1 >= H - 4:
                    door.update(cells)
                    door_boxes.append((x0, x1, y0, y1))
                else:
                    win_boxes.append((x0, x1, y0, y1))

    sill = set()
    if t.get("sill", True):
        for (x0, x1, y0, y1) in win_boxes:
            nested = any(x0 >= dx0 - 1 and x1 <= dx1 + 1
                         and y0 >= dy0 - 1 and y1 <= dy1 + 1
                         for (dx0, dx1, dy0, dy1) in door_boxes)
            sy = y1 + 1
            if not nested and sy < H:
                sill.update((x, sy) for x in range(x0, x1 + 1)
                            if inside(x, sy))

    return dict(top=top, wall_h=wall_h, ytop=ytop, recess=recess,
                door=door, sill=sill, inside=inside, D=H, W=W, H=H)


# --------------------------------------------------------------- stage 3 --
def build(sp, pr, t):
    """The voxel model. Order is load-bearing: walls, ledge, recesses, then
    the roof solid overwrites what it intersects and the walls are trimmed
    to the roof's underside."""
    W, H, D = pr["W"], pr["H"], pr["D"]
    inside, top, ytop = pr["inside"], pr["top"], pr["ytop"]
    col, src = sp["col"], sp["src"]
    slab = t["slab"]

    def T(x):
        return ytop - top[max(0, min(W - 1, x))]

    def interior(sx, sy):
        """Side faces must not be slabs of outline black: walk inward for the
        first painted colour, the way the drawing's own shading does."""
        if col[sy][sx] != BLACK:
            return sx
        step = 1 if sx < W // 2 else -1
        for d in range(1, 4):
            nx = sx + step * d
            if inside(nx, sy) and col[sy][nx] != BLACK:
                return nx
        return sx

    # the roof's drawn span: a sprite inset from its box leaves outer
    # columns undrawn in the roof band, and they carry no roof at all
    roofed = [x for x in range(W) if top[x] < t["roof_rows"]]
    x0d, x1d = (roofed[0], roofed[-1]) if roofed else (0, W - 1)

    def trimmed(x, y):
        """Under the roof's underside -- a column with no roof over it has
        no underside, and must not be cut by a profile never drawn."""
        return top[max(0, min(W - 1, x))] < t["roof_rows"] and y > T(x) - slab

    vox = {}

    def put(x, y, z, sx, sy):
        vox[(x, y, z)] = (col[sy][sx], src[sy][sx])

    # ---- walls: the facade rows extruded straight back, trimmed under the roof
    for sy in range(t["roof_rows"], H):
        y = H - 1 - sy
        for sx in range(W):
            if not inside(sx, sy) or trimmed(sx, y):
                continue
            ix = interior(sx, sy)
            for z in range(D):
                if z == 0 or z == D - 1:
                    put(sx, y, z, sx, sy)
                else:
                    put(sx, y, z, ix, sy)

    # a base course: the drawing's last row is the ground the house stands
    # on, so without this the wall floats one voxel over its own plot
    for x in range(W):
        for z in range(D):
            if (x, 0, z) not in vox and (x, 1, z) in vox:
                vox[(x, 0, z)] = vox[(x, 1, z)]

    # ---- ledge: the awning slab juts two voxels past the walls
    if t["ledge"]:
        l0, l1 = t["ledge"]
        for sy in range(l0, l1 + 1):
            y = H - 1 - sy
            for sx in range(W):
                if inside(sx, sy) and not trimmed(sx, y):
                    for z in (-2, -1, D, D + 1):
                        put(sx, y, z, sx, sy)

    shade_px = {}
    for sy in range(H):
        for sx in range(W):
            if inside(sx, sy):
                shade_px.setdefault(col[sy][sx], (sx, sy))

    # ---- recesses: a window pane sinks recess_depth voxels, a doorway the
    # classic one (the walk-in sprite reads against it); frames stay proud
    rdepth = min(t.get("recess_depth", 2), D - 2)
    for sx, sy in pr["recess"]:
        depth = 1 if (sx, sy) in pr["door"] else rdepth
        for z in range(D - depth, D):
            vox.pop((sx, H - 1 - sy, z), None)

    # ---- sills: the frame row under a window juts one voxel proud of the
    # facade, in the drawing's own dark shade
    for sx, sy in pr["sill"]:
        y = H - 1 - sy
        if not trimmed(sx, y):
            px = shade_px.get(DARK) or shade_px[BLACK]
            put(sx, y, D, px[0], px[1])

    # ---- roof: flat top over the plateau, stepped diagonal ends -- and the
    # eave: the drawn span pushed `eave_out` voxels past its sides and back
    # (the front already carries front_eave), overhang columns clamped into
    # the span so they continue the edge column's texture and height
    z0, z1 = 0, D - 1 + t["front_eave"]
    back, front = t["roof_back"], t["roof_front"]
    c0, c1 = t["roof_cycle"]
    eave = t.get("eave_out", 2)
    ex0, ex1 = x0d - eave, x1d + eave
    z0e = z0 - eave

    def roof_sy(z):
        df, db = max(0, z - z0), z1 - z     # from the north / the south edge
        if df < back:
            return df                       # north rim: the drawing's top rows
        if db < front:
            return t["roof_rows"] - 1 - db  # south rim: fascia and eave course
        return c0 + (df - c0) % (c1 - c0 + 1)

    for x in range(ex0, ex1 + 1):
        cx = min(max(x, x0d), x1d)
        if top[cx] >= t["roof_rows"]:
            continue
        tt = T(cx)
        for z in range(z0e, z1 + 1):
            outer = x == ex0 or x == ex1 or z == z0e or z == z1
            # the slope's texture is the drawing's own: clamping into the
            # column's first drawn row keeps flank battens running down the
            # slope instead of falling off the silhouette
            sy = max(roof_sy(z), pr["top"][cx])
            for y in range(tt - slab + 1, tt + 1):
                if y == tt and not outer:
                    put(x, y, z, cx, sy)
                else:
                    # the rim: the drawing's own eave -- a black outline
                    # over a shaded fascia, closed by the outline again
                    if not outer:
                        shade = DARK
                    elif y == tt or y == tt - slab + 1:
                        shade = BLACK
                    else:
                        shade = DARK
                    px = shade_px.get(shade) or shade_px[BLACK]
                    put(x, y, z, px[0], px[1])

    # ---- chimney: an optional box standing on the roof surface (per-flag
    # only, never a default), worn in the drawing's own palette
    ch = t.get("chimney")
    if ch:
        for x in range(ch["x"], ch["x"] + ch["w"]):
            cx = min(max(x, x0d), x1d)
            if top[cx] >= t["roof_rows"]:
                continue
            base = T(cx)
            for z in range(ch["z"], ch["z"] + ch["w"]):
                for y in range(base + 1, base + ch["h"] + 1):
                    shade = (BLACK if y == base + ch["h"] or y == base + 1
                             else DARK)
                    px = shade_px.get(shade) or shade_px[BLACK]
                    put(x, y, z, px[0], px[1])
    return vox


# --------------------------------------------------------------- stage 5 --
def verify(vox, sp, pr, t):
    W, H, D = pr["W"], pr["H"], pr["D"]
    ytop, top, slab = pr["ytop"], pr["top"], t["slab"]
    T = lambda x: ytop - top[max(0, min(W - 1, x))]

    # The roof surface reads over the columns the drawing actually paints:
    # a sprite inset from its box says nothing about the rest.
    roofed = [x for x in range(W) if top[x] < t["roof_rows"]]
    assert roofed, "no roof band is drawn"
    x0d, x1d = roofed[0], roofed[-1]
    # an overhang column reads the height of the drawn column it clamps to
    Tc = lambda x: ytop - top[max(x0d, min(x1d, x))]
    ch = t.get("chimney")

    def cap(x, z):
        """The highest voxel a column may legally carry: the roof surface,
        or the chimney's top inside its footprint."""
        if (ch and ch["x"] <= x < ch["x"] + ch["w"]
                and ch["z"] <= z < ch["z"] + ch["w"]):
            return Tc(x) + ch["h"]
        return Tc(x)

    for (x, y, z), _ in vox.items():
        assert y <= cap(x, z), f"voxel pokes through the roof at {x},{y},{z}"

    prof = [T(x) for x in roofed]
    assert prof == prof[::-1], "the roof is not symmetric"
    plateau = [i for i, v in enumerate(prof) if v == ytop]
    assert plateau, "no flat top"

    if max(top[x] for x in roofed) > 1:
        # a slope: eave tip, one step per N columns, flat plateau
        for i in range(1, plateau[0]):
            assert 0 <= prof[i] - prof[i - 1] <= 1, "the taper is not monotonic"
        # the taper rate the drawing sets is the slope: one step per N
        # columns, the same N the whole way down to the eave tip
        steps = [i for i in range(1, plateau[0] + 1) if prof[i] != prof[i - 1]]
        # a rate needs two steps to be a rate. One step is a lip, not a
        # slope, and there is nothing to hold it to.
        if len(steps) >= 2:
            rate = steps[1] - steps[0]
            assert all(b - a == rate for a, b in zip(steps, steps[1:])), \
                f"the slope is not a constant {rate}:1"
            assert prof[0] == ytop - (plateau[0] + rate - 1) // rate, \
                "the eave tip does not land where the drawn taper ends"
    else:
        # flat: one level roof the whole drawn span, give or take the
        # drawing's own corner rounding
        assert all(ytop - v <= 1 for v in prof), "the flat roof is not level"

    # every wall column carries roof over it -- and a column the roof never
    # reaches carries nothing but the eave overhang, rather than being
    # silently trimmed away
    over = set(roofed)
    for x in range(W):
        for z in range(D):
            if x not in over:
                for y in range(ytop + 1):
                    assert (x, y, z) not in vox or y > Tc(x) - slab, \
                        f"wall stands where no roof reaches at {x},{z}"
            elif any((x, y, z) in vox for y in range(0, T(x) - slab + 1)):
                assert (x, T(x), z) in vox, f"wall uncovered at {x},{z}"

    shell = [k for k in vox if not all(
        (k[0] + d[0], k[1] + d[1], k[2] + d[2]) in vox
        for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0),
                  (0, -1, 0), (0, 0, 1), (0, 0, -1)))]
    return shell


def preview(shell, vox, sp, name, out, flip, canvas=(1700, 900), pad=20):
    # Mirroring depth swings the camera round to the other side. Mirror
    # about the model's own depth range, not a fixed one, or a building
    # deeper or shallower than the first two walks off the canvas.
    zs = [z for _, _, z in shell]
    zlo, zhi = min(zs), max(zs)
    pts = [(x, y, (zlo + zhi - z) if flip else z, vox[(x, y, z)][0])
           for (x, y, z) in shell]
    pts.sort(key=lambda p: (p[0] + p[2], p[1]))

    # Fit the projection to the model: Silph Co is four times the height of
    # Red's house and would otherwise render off the edge.
    px = lambda x, z: 2 * (x - z)
    py = lambda x, y, z: (x + z) - 2 * y
    xs = [px(x, z) for x, _, z, _ in pts] + [px(x + 1, z + 1) for x, _, z, _ in pts]
    ys = [py(x, y, z) for x, y, z, _ in pts] + [py(x + 1, y + 1, z + 1)
                                                for x, y, z, _ in pts]
    W, H = canvas
    S = max(1, min((W - 2 * pad) // max(1, max(xs) - min(xs)),
                   (H - 2 * pad) // max(1, max(ys) - min(ys))))
    ox = pad - min(xs) * S + (W - 2 * pad - (max(xs) - min(xs)) * S) // 2
    oy = pad - min(ys) * S + (H - 2 * pad - (max(ys) - min(ys)) * S) // 2
    P = lambda x, y, z: (px(x, z) * S + ox, py(x, y, z) * S + oy)
    img = Image.new("RGB", canvas, (0xca, 0xdc, 0x9f))
    dr = ImageDraw.Draw(img)
    has = {(x, y, z) for x, y, z, _ in pts}
    sh = lambda c, f: tuple(int(v * f) for v in sp["pal"][c])
    for x, y, z, c in pts:
        if (x, y + 1, z) not in has:
            dr.polygon([P(x, y + 1, z), P(x + 1, y + 1, z),
                        P(x + 1, y + 1, z + 1), P(x, y + 1, z + 1)], fill=sh(c, 1.0))
        if (x + 1, y, z) not in has:
            dr.polygon([P(x + 1, y, z), P(x + 1, y + 1, z),
                        P(x + 1, y + 1, z + 1), P(x + 1, y, z + 1)], fill=sh(c, 0.62))
        if (x, y, z + 1) not in has:
            dr.polygon([P(x, y, z + 1), P(x + 1, y, z + 1),
                        P(x + 1, y + 1, z + 1), P(x, y + 1, z + 1)], fill=sh(c, 0.82))
    img.save(os.path.join(out, name))


def build_parts(t):
    """A `parts` template: each part is a stacked footprint with its own
    band table -- a tile-rect crop of the drawing (rows/cols, plus a pixel
    `trim` off the top), standing over its own z span of the template's
    footprint. Each part runs the ordinary pipeline and verify; the model
    is the union, so touching faces between parts cull each other."""
    merged, pal = {}, None
    for p in t["parts"]:
        r0, r1 = p["rows"]
        c0, c1 = p.get("cols", (1, len(t["tiles"][0])))
        sub = [row[c0 - 1:c1] for row in t["tiles"][r0 - 1:r1]]
        pt = dict(t)
        pt.pop("parts", None)
        pt.update(tiles=sub, seal=p.get("seal", ""),
                  roof_rows=p["roof_rows"], roof_back=p["roof_back"],
                  roof_front=p["roof_front"], roof_cycle=p["roof_cycle"],
                  front_eave=p.get("front_eave", 0),
                  eave_out=p.get("eave_out", 0),
                  recess_depth=p.get("recess_depth", 2),
                  sill=p.get("sill", True), ledge=None)
        sp = sprite(sub, pt["seal"], pt["tileset"])
        trim = p.get("trim", 0)
        if trim:
            sp = dict(W=sp["W"], H=sp["H"] - trim, pal=sp["pal"],
                      col=sp["col"][trim:], out=sp["out"][trim:],
                      src=sp["src"][trim:])
        pr = profile(sp, pt)
        pr["D"] = p["z"][1] - p["z"][0]
        vox = build(sp, pr, pt)
        verify(vox, sp, pr, pt)
        px0, pz0 = (c0 - 1) * 8, p["z"][0]
        for (x, y, z), v in vox.items():
            merged[(x + px0, y, z + pz0)] = v
        pal = sp["pal"]
    shell = [k for k in merged if not all(
        (k[0] + d[0], k[1] + d[1], k[2] + d[2]) in merged
        for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0),
                  (0, -1, 0), (0, 0, 1), (0, 0, -1)))]
    return merged, shell, pal


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    for name, t in TEMPLATES.items():
        if "parts" in t:
            vox, shell, pal = build_parts(t)
            print(f"{name}: parts={len(t['parts'])}  ->  voxels {len(vox)}  "
                  f"shell {len(shell)}")
            preview(shell, vox, {"pal": pal}, f"{name}_front.png", out, True)
            preview(shell, vox, {"pal": pal}, f"{name}_back.png", out, False)
            continue
        sp = sprite(t["tiles"], t.get("seal", ""), t.get("tileset", "overworld"))
        pr = profile(sp, t)
        vox = build(sp, pr, t)
        shell = verify(vox, sp, pr, t)
        print(f"{name}: {sp['W']}x{sp['H']} sprite, depth {pr['D']}, "
              f"height {pr['ytop'] + 1}  ->  voxels {len(vox)}  "
              f"shell {len(shell)}  recessed {len(pr['recess'])}")
        preview(shell, vox, sp, f"{name}_front.png", out, True)
        preview(shell, vox, sp, f"{name}_back.png", out, False)


if __name__ == "__main__":
    main()
