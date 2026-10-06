"""The ground of Celadon City: a plan, its data, a check.

  python tools/celadon_ground.py --write   paint assets/buildings/celground_<MAP>.png,
                                           write data/celground_<MAP>.lua + the index
  python tools/celadon_ground.py           check the REAL kit against the REAL map

The third painted world (Lavender's, Vermilion's, this), stood by the same kit
(lib/LavenderGroundKit.lua) and written and checked by tools/vermilion_ground.py's
own write() and check(). Another town again.

Celadon's floor is the sett tile $5B, and nothing else. That tile is a running
bond of little blocks -- three voxels of stone, a one-voxel joint, the next
course staggered -- which is a parallelepiped once each block stands a voxel
proud of its mortar. The kit's AO does the shaded side a flat drawing cannot.
Each pixel of the tile is a two-by-two of voxels, so a block is big enough to
read as a stone and the bond is still the tile's own. The lawns stay lawns.
The roads out of town stay a plain slab: the sett is the city's.

Nothing here is extracted from the ROM. The block is this mod's stone, in
Celadon's pale glaze. The tile only decided the bond.
"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vermilion_ground as vg  # noqa: E402
from lavender_ground import h01, vnoise  # noqa: E402

TOWN = "CELADON_CITY"
PAVED_T = {91, 57, 35, 16, 32, 33}
LAWN_T = {44, 48}
COURT = (48, 57, 57, 48)
TOWN_W, TOWN_H = 800, 576
# map id, world cell origin, off the connections: Route 7 joins the east edge four
# blocks down, and Celadon joins Route 16's east edge four blocks UP
MAPS = [(TOWN, 0, 0), ("ROUTE_7", 50, 8), ("ROUTE_16", -40, 8)]

SLAB = [(240, 236, 226), (230, 228, 218), (246, 242, 232), (234, 230, 224)]
SLAB_GREEN = [(192, 226, 206), (180, 216, 196)]
JOINT = (170, 172, 166)
# tile $5B's two values, in Celadon's glaze: the block, and the mortar under it
SETT = [(236, 244, 230), (224, 236, 216), (214, 228, 204), (206, 222, 196)]
MORTAR = (88, 116, 96)
GRANITE = [(104, 112, 118), (120, 128, 132), (92, 100, 108)]
INSET = (140, 214, 178)
MARBLE = [(252, 248, 238), (244, 240, 230)]
CELADON = [(168, 214, 190), (156, 204, 180)]
RAINBOW = [(238, 84, 84), (246, 152, 70), (250, 216, 92), (110, 198, 112),
           (90, 152, 232), (104, 98, 204), (178, 112, 212)]
COPING = [(250, 250, 252), (238, 240, 246)]
IRON = [(64, 66, 76), (84, 86, 98)]
SOIL = [(122, 96, 78), (108, 84, 70)]
G_D, G_A, G_B, G_T = (70, 128, 80), (116, 186, 106), (126, 196, 112), (176, 226, 140)
GROWS = {
    "g": {"top": [G_B, G_T], "stem": [G_A]},
    "k": {"top": COPING, "stem": [(214, 216, 226)]},                       # the pond's coping
    "r": {"top": [RAINBOW[0]], "stem": [(84, 150, 88)]},                   # tulips, a colour a letter
    "o": {"top": [RAINBOW[1]], "stem": [(84, 150, 88)]},
    "y": {"top": [RAINBOW[2]], "stem": [(84, 150, 88)]},
    "b": {"top": [RAINBOW[4]], "stem": [(84, 150, 88)]},
    "v": {"top": [RAINBOW[6]], "stem": [(84, 150, 88)]},
    "w": {"top": [(252, 252, 250)], "stem": [(84, 150, 88)]},
}
TULIPS = "roywbv"

# World voxels: x east, z south. The crossroads, the store's doors, the pond.
ROSE = (592, 192, 31)
FAN = (152, 224, 30)
# a lawn cell flagged as a doorstep: the Gym's. (Its yard is only reached over the
# south lawn and a Cut bush, so it is not in REACH.)
PATHS = [(12, 28)]
REACH = {"Route 7": (872, 216), "Route 16": (-40, 296), "Dept. Store": (152, 232), "Mansion": (392, 168),
         "Centre": (664, 168), "Game Corner": (456, 328), "Prize Room": (536, 328),
         "Diner": (504, 456), "Hotel": (696, 456), "the crossroads": (592, 192)}


def kind_of(p, town, cx, cy):
    s = set(p)
    if p == vg.SIGN:
        return "S"
    if p == vg.FENCE:
        return "N"
    if p in vg.TREES:
        return "W"
    if s <= LAWN_T:
        return "L"
    if s <= PAVED_T:
        return "V" if town else "P"
    if not town and p == COURT:
        return "P"                       # a road's checker: a court the grass has half taken back
    if not town and s == {82}:
        return "G"
    if not town and s <= LAWN_T | {3}:
        return "F"
    if s <= vg.SHORE_T | {vg.SEA_T} and s & vg.SHORE_T:
        return "Q"
    return "."


def paint(world):
    H, W = world.ch * 16, world.cw * 16
    X, Z = np.meshgrid(np.arange(W) + 0.5 + world.cx0 * 16, np.arange(H) + 0.5 + world.cy0 * 16)
    XI, ZI = np.floor(X).astype(np.int64), np.floor(Z).astype(np.int64)
    ground = world.px("VLSNWPGF") | world.land
    claimed = world.px("VLP")
    # out on a road the dressing falls away with every step from the last building
    away = np.hypot(np.maximum(0, np.maximum(-X, X - TOWN_W)), np.maximum(0, np.maximum(-Z, Z - TOWN_H)))
    town = away == 0
    origin = {mid: (gx - world.cx0, gy - world.cy0) for mid, gx, gy, *_ in world.maps}
    court = np.zeros((H, W), bool)
    for (mid, cx, cy), p in world.tiles.items():
        if p == COURT:
            r, c = origin[mid][1] + cy, origin[mid][0] + cx
            court[r * 16:r * 16 + 16, c * 16:c * 16 + 16] = True
    taken = court & (vnoise(X, Z, 11, 71) > 0.52)                  # what the grass took
    ragged = world.px("P") & ~court & (vg.reach_of(world.px("LGFSNW"), 3) <= 2) & (vnoise(X, Z, 5, 72) > 0.5)
    paved_c = world.px("VP") & ~taken & ~ragged
    lawn_c = world.px("LSNGF") | taken | ragged
    ds = vg.reach_of(world.sea, 40)                     # voxels to the pond
    dpave = vg.reach_of(paved_c | world.land, 24)       # voxels to the paving
    r1, r2, r3 = h01(XI, ZI, 21), h01(XI, ZI, 22), h01(XI, ZI, 23)

    tex = np.zeros((H, W, 3), np.uint8)

    def put(mask, rgb):
        tex[mask] = rgb

    def tones(mask, palette, pick):
        idx = np.floor(pick * len(palette)).astype(int) % len(palette)
        for k, rgb in enumerate(palette):
            put(mask & (idx == k), rgb)

    # ---- a street tree: paving round it, within a cell of the paving; the rest are woods
    tree = world.px("W")
    street_tree = tree & (dpave <= 16) & town                  # a road's trees are a wood
    path = np.zeros((H, W), bool)
    for cx, cy in PATHS:
        r, c = cy - world.cy0, cx - world.cx0
        path[r * 16:r * 16 + 16, c * 16:c * 16 + 16] = True
    stone = paved_c | world.land | street_tree | path
    lawn = (lawn_c | (tree & ~street_tree)) & ~path

    # ---- the roads out of town: a plain slab. The sett is the city's.
    road = stone & ~town
    tones(road, SLAB, h01(XI // 16, ZI // 16, 31))
    put(road & ((XI % 16 == 0) | (ZI % 16 == 0)), JOINT)

    # ---- tile $5B, one pixel a voxel. A block stands proud; the joint lies flat,
    # so each stone is a parallelepiped and the mortar is the lane between them.
    # Courses are four voxels: a joint, three of stone. The upper course breaks
    # after three pixels, the lower after seven -- the tile's own stagger.
    pave = (stone & town) | street_tree
    sx, sz = XI // 2, ZI // 2
    u, v = np.mod(sx, 8), np.mod(sz, 8)
    upper = v < 4
    joint = (v == 0) | (v == 4) | (upper & (u == 3)) | (~upper & (u == 7))
    face = pave & ~joint
    bx = np.where(upper, (sx // 8) * 2 + (u >= 4), sx // 8)
    tone = h01(bx, sz // 4, 37)
    tones(face, SETT, tone)
    put(pave & joint, MORTAR)

    # ---- the lawns: mown in stripes, a dark edge where they meet the paving
    stripe = (((XI + ZI) // 10) % 2 == 0) & town
    put(lawn, G_A)
    put(lawn & stripe, G_B)
    put(lawn & (r2 < 0.07), G_T)
    put(lawn & (r3 < 0.05), G_D)
    put(lawn & (dpave <= 1), G_D)
    put(world.flower, SOIL[0])
    put(world.flower & (r1 < 0.45), SOIL[1])

    # ---- what grows: only out on the roads. The city's floor is the sett.
    grows = np.full((H, W), ".", dtype="<U1")
    free = claimed & ground

    def grow(mask, letter):
        grows[mask & (grows == ".") & free] = letter

    crown = lawn & ~town & (h01(XI, ZI, 51) < 0.010)
    grow(crown & (h01(XI, ZI, 56) < 0.2), "W")
    grow(crown & (h01(XI, ZI, 56) < 0.35), "Y")
    grow(crown, "G")
    for n, (dzz, dxx) in enumerate(((0, 1), (0, -1), (1, 0), (-1, 0))):
        grow(np.roll(crown, (dzz, dxx), (0, 1)) & lawn & (h01(XI, ZI, 52 + n) < 0.5), "g")
    turf = face | lawn                               # the blocks, and the grass, stand proud
    return ground, claimed, tex, turf, grows


vg.MAPS = MAPS
vg.TOWN, vg.PREFIX, vg.START, vg.BUDGET = TOWN, "celground", "the crossroads", 90000
vg.GROWS, vg.REACH, vg.kind_of, vg.paint = GROWS, REACH, kind_of, paint

if __name__ == "__main__":
    if "--write" in sys.argv:
        vg.write()
    vg.check()
