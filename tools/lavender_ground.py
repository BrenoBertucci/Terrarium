"""The ground of Lavender Town and of the routes into it: plans, data, a check.

  python tools/lavender_ground.py --write   paint assets/buildings/lavground_<MAP>.png,
                                            write data/lavground_<MAP>.lua + the index
  python tools/lavender_ground.py           check the REAL kit against the REAL
                                            maps, count quads the way
                                            Buildings.emit merges them, and
                                            render tools/_kit_out/lavground_*.png

ALL the maps are painted on ONE canvas in WORLD coordinates (one texel a
voxel), then cut into a sheet per map. Every noise, stone and street is a
function of world position, so nothing can show at a map's edge: there is no
edge in the picture, only in the files. Nothing of the drawn ground is kept
but the answer to "what kind of ground is this cell":

  town checker  Lavender: paths where feet go (STREETS), lawn, lavender
  P  road       a route's own road, flagged, its edges let go ragged
  L  grass      lawn          C  checker on a route: an overgrown court
  G  tall grass / F flowers / S sign: laid, NOT claimed (they still stand)
  D  pier       planks        B  brick yard: setts
  W  under the trees: a forest floor -- loam, leaf litter, moss, ferns and the
     odd mushroom -- spilling a little way out on to the lawn. Laid, not
     claimed: the trees stand in it.

lib/LavenderGroundKit.lua only stands it up. Per ground cell the data says `t`
(the four tiles it was painted for), `b` (which texels are turf: a voxel proud
of the stones; one digit = the whole cell), `g` (what grows: a letter of GROWS,
upper case two tall; absent = nothing) and `claim = false` for G/F/S.

To floor another map: add it to MAPS with its world cell origin.
Needs Pillow + numpy + lupa, and the build (tools/interior_plan.py reads the
maps). No game process or save is touched.
"""
import sys
from pathlib import Path

import numpy as np
from lupa import LuaRuntime
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from interior_plan import plan  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tools/_kit_out"
# map id, world cell origin. Read off the connections: all three join
# Lavender at offset 0 (Route 8 west, Route 10 north, Route 12 south).
MAPS = [("LAVENDER_TOWN", 0, 0), ("ROUTE_8", -60, 0), ("ROUTE_10", 0, -72), ("ROUTE_12", 0, 18)]
TOWN = "LAVENDER_TOWN"
LAWN_T, ROAD_T = {44, 48}, {57, 35, 32, 16, 33}
# The road's MARKINGS are kept, and stood up: $10 a kerb running north-south,
# $20 one running east-west, $21 a bollard. They rule the lane a bicycle
# keeps to, so they are the one part of the drawn road that is information.
KERB_NS, KERB_EW, BOLLARD = 16, 32, 33
SIGN = (70, 71, 86, 87)
TREES = ((42, 43, 58, 59), (64, 65, 80, 81))     # the lone tree, the border wood

# ------------------------------------------------------------- the palette --
# MEASURED, not chosen by eye: the first in-game frames put a (178,174,192)
# stone on screen at (121,120,141) and a (92,140,92) turf at (77,120,85) --
# the texels are lifted by what the light takes away.
STONE = [(214, 210, 232), (204, 200, 224), (222, 218, 238), (208, 206, 222)]
STONE_RIM = (172, 168, 192)
STONE_DK = (150, 146, 172)
STONE_HI = (236, 232, 246)
JOINT = [(136, 128, 148), (124, 118, 138)]
JOINT_MOSS = (118, 148, 112)
MOSS = [(140, 168, 128), (116, 146, 114)]
G_D, G_M, G_L, G_T = (78, 124, 88), (108, 158, 104), (132, 180, 112), (156, 198, 124)
G_SHADE, G_SUN = (94, 142, 98), (120, 170, 108)
CLOVER = (88, 138, 104)
SOIL = [(176, 158, 150), (162, 146, 142), (186, 168, 158)]
BED = [(128, 110, 116), (116, 100, 108)]
LEAF = (190, 140, 92)
PETAL = (196, 166, 230)
DAISY = (244, 242, 250)
PLANK = [(176, 148, 122), (164, 136, 112), (188, 160, 132), (154, 130, 110)]
PLANK_GAP = (104, 84, 76)
SETT = [(196, 176, 176), (184, 164, 168), (206, 188, 184)]
SETT_JOINT = (132, 118, 126)
GROWS = {
    "g": {"top": [G_SUN, G_L, G_M], "stem": [G_M, G_SHADE]},
    "l": {"top": [(170, 132, 214), (198, 166, 234), (148, 112, 196)],
          "stem": [(100, 146, 104), (88, 132, 96)]},
    "w": {"top": [(242, 240, 248), (250, 244, 230)], "stem": [G_M]},
    "y": {"top": [(238, 208, 108)], "stem": [G_M]},
    "m": {"top": MOSS, "stem": MOSS},
    "p": {"top": [(186, 182, 200), (164, 160, 182)], "stem": [(164, 160, 182)]},
    "k": {"top": [(240, 236, 248), (230, 226, 242)], "stem": [(186, 182, 204)]},   # dressed kerb stone
    "f": {"top": [(74, 124, 88), (90, 140, 96), (62, 108, 80)], "stem": [(58, 98, 74)]},   # fern
    "u": {"top": [(184, 88, 74), (204, 112, 84)], "stem": [(226, 214, 196)]},              # mushroom
}
LOAM = [(112, 98, 94), (100, 88, 88), (124, 108, 98)]
LITTER = [(186, 134, 86), (164, 108, 76), (204, 160, 96), (146, 96, 72)]
TWIG = (78, 64, 64)
WOOD_MOSS = (104, 142, 106)

# ------------------------------------------------------- the town's plan --
# Where feet go in LAVENDER, in world voxels (x east, z south). On a route the
# road is the map's own; these only have to meet it: Route 8's road comes in
# on cell row 8, Route 10's and Route 12's on cell columns 8..9.
STREETS = [
    (17, [(0, 137), (20, 136), (44, 122), (70, 113), (100, 111), (128, 114),
          (160, 110), (196, 113), (232, 111), (262, 114)]),     # west gate -> Centre -> Tower gate
    (16, [(144, 0), (140, 22), (129, 46), (131, 68), (126, 90), (128, 114)]),   # Route 10 down to the green
    (14, [(196, 113), (201, 140), (191, 166), (195, 200), (190, 226), (193, 242)]),  # the lane by the Mart
    (14, [(20, 136), (26, 158), (52, 176), (90, 173), (120, 177), (158, 174), (191, 172)]),  # past Mr. Fuji's
    (15, [(28, 242), (56, 240), (92, 244), (120, 240), (144, 244), (193, 242),
          (230, 240), (248, 243), (274, 241)]),                 # the south street: every other door
    (16, [(144, 244), (141, 266), (144, 288)]),                 # out to Route 12
    (12, [(20, 136), (13, 172), (17, 210), (28, 242)]),         # the west lane
    (12, [(56, 101), (62, 113)]),                               # the Centre's step
    (13, [(232, 101), (232, 111)]),                             # the Tower gate's
    (7, [(152, 68), (138, 64)]),                                # stepping stones to the signs
    (7, [(280, 132), (270, 121), (262, 114)]),
]
ROUNDS = [
    (56, 101, 15, 7), (232, 101, 18, 7), (120, 165, 15, 7), (56, 229, 15, 7),
    (120, 229, 15, 7), (248, 229, 17, 7),
    (152, 68, 7, 5), (280, 132, 7, 5), (88, 165, 7, 5), (184, 165, 7, 5),
    (128, 113, 14, 13), (196, 113, 11, 11),
]
BEDS = [
    (34, 96, 40, 98), (72, 96, 93, 98), (98, 160, 104, 162), (136, 160, 157, 162),
    (34, 224, 40, 226), (72, 224, 93, 226), (98, 224, 104, 226), (136, 224, 157, 226),
    (164, 96, 212, 98), (252, 96, 285, 98),
]
MEADOWS = [(2, 36, 30, 94), (40, 126, 92, 156), (212, 130, 286, 158), (164, 196, 184, 222)]
REACH = {"north road": (144, 2), "south road": (144, 285), "Centre": (56, 99),
         "Tower gate": (232, 99), "Mr. Fuji": (120, 163), "Cubone house": (56, 227),
         "Name Rater": (120, 227), "Mart": (248, 227)}
ROUTE_GROWTH = 0.4          # a route's verges are thinner than the town's


def h01(ix, iz, seed):
    ix = np.asarray(ix, dtype=np.int64)
    iz = np.asarray(iz, dtype=np.int64)
    n = (ix * 374761393 + iz * 668265263 + seed * 982451653) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    n = n ^ (n >> 16)
    return n.astype(np.float64) / 4294967296.0


def vnoise(x, z, scale, seed):
    fx, fz = x / scale, z / scale
    ix, iz = np.floor(fx).astype(np.int64), np.floor(fz).astype(np.int64)
    tx, tz = fx - ix, fz - iz
    tx, tz = tx * tx * (3 - 2 * tx), tz * tz * (3 - 2 * tz)
    top = h01(ix, iz, seed) * (1 - tx) + h01(ix + 1, iz, seed) * tx
    bot = h01(ix, iz + 1, seed) * (1 - tx) + h01(ix + 1, iz + 1, seed) * tx
    return top * (1 - tz) + bot * tz


def street_d(x, z):
    d = np.full(np.shape(x), 1e9)
    for width, pts in STREETS:
        for (ax, az), (bx, bz) in zip(pts, pts[1:]):
            dx, dz = bx - ax, bz - az
            t = np.clip(((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz), 0, 1)
            d = np.minimum(d, np.hypot(x - (ax + t * dx), z - (az + t * dz)) - width / 2)
    for cx, cz, rx, rz in ROUNDS:
        d = np.minimum(d, (np.hypot((x - cx) / rx, (z - cz) / rz) - 1) * min(rx, rz))
    return d


def box_blur(a, r):
    for axis in (0, 1):
        pad = [(0, 0), (0, 0)]
        pad[axis] = (r + 1, r)
        c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis)
        n = a.shape[axis]
        hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
        lo = np.take(c, np.arange(0, n), axis=axis)
        a = (hi - lo) / (2 * r + 1)
    return a


def kind_of(p, town):
    s = set(p)
    if p == SIGN:
        return "S"
    if p in TREES:
        return "W"
    if p == (48, 57, 57, 48):
        return "T" if town else "C"
    if s <= LAWN_T:
        return "T" if town else "L"
    if town:
        return "."
    if s <= ROAD_T:
        return "P"
    if s == {82}:
        return "G"
    if s <= LAWN_T | {3}:
        return "F"
    if s == {60}:
        return "D"
    if s <= LAWN_T | {60}:
        return "L"                               # a lawn with the pier's end let into it
    if s == {91}:
        return "B"
    return "."


class World:
    def __init__(self):
        self.maps = []
        for mid, gx, gy in MAPS:
            _, grid = plan(mid)
            self.maps.append((mid, gx, gy, len(grid[0]) // 2, len(grid) // 2, grid))
        self.cx0 = min(m[1] for m in self.maps)
        self.cy0 = min(m[2] for m in self.maps)
        self.cw = max(m[1] + m[3] for m in self.maps) - self.cx0
        self.ch = max(m[2] + m[4] for m in self.maps) - self.cy0
        self.kind = np.full((self.ch, self.cw), ".", dtype="<U1")
        self.tiles = {}
        self.flower = np.zeros((self.ch * 16, self.cw * 16), bool)
        self.plank = np.zeros((self.ch * 16, self.cw * 16), bool)
        self.mark = {t: np.zeros((self.ch * 16, self.cw * 16), bool) for t in (KERB_NS, KERB_EW, BOLLARD)}
        for mid, gx, gy, w, h, grid in self.maps:
            for cy in range(h):
                for cx in range(w):
                    p = (grid[cy * 2][cx * 2], grid[cy * 2][cx * 2 + 1],
                         grid[cy * 2 + 1][cx * 2], grid[cy * 2 + 1][cx * 2 + 1])
                    k = kind_of(p, mid == TOWN)
                    r, c = gy + cy - self.cy0, gx + cx - self.cx0
                    self.kind[r, c] = k
                    self.tiles[(mid, cx, cy)] = p
                    for q, (oz, ox) in enumerate(((0, 0), (0, 8), (8, 0), (8, 8))):
                        quarter = (slice(r * 16 + oz, r * 16 + oz + 8), slice(c * 16 + ox, c * 16 + ox + 8))
                        if k == "F" and p[q] == 3:
                            self.flower[quarter] = True
                        if k == "L" and p[q] == 60:
                            self.plank[quarter] = True
                        if k == "P" and p[q] in self.mark:
                            self.mark[p[q]][quarter] = True

    def px(self, letters):
        return np.kron(np.isin(self.kind, list(letters)), np.ones((16, 16), bool))


LAWN_M, STONE_M, JOINT_M, DIRT_M, BED_M, DECK_M, SETT_M, WOOD_M = range(8)


def paint(world):
    H, W = world.ch * 16, world.cw * 16
    X, Z = np.meshgrid(np.arange(W) + 0.5 + world.cx0 * 16, np.arange(H) + 0.5 + world.cy0 * 16)
    XI, ZI = np.floor(X).astype(np.int64), np.floor(Z).astype(np.int64)
    ground = world.px("TLCPGFSDBW")
    claimed = world.px("TLCPDB")
    town = (X >= 0) & (X < 320) & (Z >= 0) & (Z < 288)
    dens = np.where(town, 1.0, ROUTE_GROWTH)
    wild = vnoise(X, Z, 46, 7)

    # ---- where the paving is: the town's streets, the routes' own roads
    # (their cell mask blurred into a field, so a corner is a curve), and a
    # route's checker let go into patches
    road = box_blur(box_blur(world.px("P").astype(float), 5), 5)
    open_ = box_blur(box_blur(ground.astype(float), 5), 5)
    shade = box_blur(box_blur(world.px("W").astype(float), 4), 4) / np.maximum(open_, 1e-6)
    sd_road = (0.5 - road / np.maximum(open_, 1e-6)) * 14
    sd_court = np.where(world.px("C"), (0.47 - vnoise(X, Z, 15, 19)) * 16, 1e9)
    dp = np.minimum(np.minimum(street_d(X, Z), sd_road), sd_court)
    dp = dp + (vnoise(X, Z, 9, 3) - 0.5) * 3.2                 # no edge is ruled

    # ---- crazy paving: a jittered grid of seeds, a stone per seed
    P, JITTER = 7.0, 0.9
    gx0, gz0 = np.floor(X / P).astype(np.int64), np.floor(Z / P).astype(np.int64)
    f1 = np.full((H, W), 1e9)
    f2 = np.full((H, W), 1e9)
    own_x, own_z = np.zeros((H, W), np.int64), np.zeros((H, W), np.int64)
    oth_x, oth_z = np.zeros((H, W), np.int64), np.zeros((H, W), np.int64)
    for oz in (-1, 0, 1):
        for ox in (-1, 0, 1):
            sx_i, sz_i = gx0 + ox, gz0 + oz
            sx = (sx_i + 0.5 + (h01(sx_i, sz_i, 11) - 0.5) * JITTER) * P
            sz = (sz_i + 0.5 + (h01(sx_i, sz_i, 12) - 0.5) * JITTER) * P
            d = np.hypot(X - sx, Z - sz)
            nearer = d < f1
            second = ~nearer & (d < f2)
            f2 = np.where(nearer, f1, np.where(second, d, f2))
            oth_x = np.where(nearer, own_x, np.where(second, sx_i, oth_x))
            oth_z = np.where(nearer, own_z, np.where(second, sz_i, oth_z))
            f1 = np.where(nearer, d, f1)
            own_x, own_z = np.where(nearer, sx_i, own_x), np.where(nearer, sz_i, own_z)

    def seed_state(ix, iz):
        sx = (ix + 0.5 + (h01(ix, iz, 11) - 0.5) * JITTER) * P
        sz = (iz + 0.5 + (h01(ix, iz, 12) - 0.5) * JITTER) * P
        col = np.clip(np.floor(sx).astype(np.int64) - world.cx0 * 16, 0, W - 1)
        row = np.clip(np.floor(sz).astype(np.int64) - world.cy0 * 16, 0, H - 1)
        d = dp[row, col]
        paved = d < -0.5
        loose = ~paved & (d < 7.5) & (h01(ix, iz, 13) < 0.15)   # the edge breaks up
        return paved, loose

    own_paved, own_loose = seed_state(own_x, own_z)
    oth_paved, _ = seed_state(oth_x, oth_z)
    gap = (f2 - f1) < 1.05
    mat = np.full((H, W), LAWN_M)
    mat[own_paved & ~gap] = STONE_M
    mat[own_paved & gap & oth_paved] = JOINT_M
    mat[own_loose & (f1 < 2.9) & ~gap] = STONE_M
    mat[(mat == LAWN_M) & (dp > -1) & (dp < 5.5) & (vnoise(X, Z, 8, 5) > 0.74)] = DIRT_M

    bed = np.zeros((H, W), bool)
    for x0, z0, x1, z1 in BEDS:
        bed |= (XI >= x0) & (XI <= x1) & (ZI >= z0) & (ZI <= z1)
    drift = np.zeros((H, W), bool)
    for x0, z0, x1, z1 in MEADOWS:
        drift |= (XI >= x0) & (XI <= x1) & (ZI >= z0) & (ZI <= z1)
    drift &= (mat == LAWN_M) & (dp > 3.5) & (vnoise(X, Z, 8.5, 17) > 0.64)
    mat[bed | drift] = BED_M
    # what the map makes of a cell outright: planks, setts, a flower's soil,
    # and turf under anything that must keep standing
    keep = world.px("GS") | (world.px("F") & ~world.flower)
    mat[keep & (mat != BED_M)] = LAWN_M
    mat[world.flower] = DIRT_M
    # under the trees, and a ragged step out from under them: a forest floor
    woods = (shade + (vnoise(X, Z, 7, 23) - 0.5) * 0.5 > 0.42) & np.isin(mat, (LAWN_M, DIRT_M))
    mat[(woods | world.px("W")) & ~world.flower] = WOOD_M
    # the marked lane: dressed slabs, flush, whatever the field said
    lane = world.mark[KERB_NS] | world.mark[KERB_EW] | world.mark[BOLLARD]
    mat[lane] = STONE_M
    deck, sett = world.px("D") | world.plank, world.px("B")
    mat[deck] = DECK_M
    mat[sett] = SETT_M

    # ---- colour
    tex = np.zeros((H, W, 3), np.uint8)

    def put(mask, rgb):
        tex[mask] = rgb

    r1, r2, r3 = h01(XI, ZI, 21), h01(XI, ZI, 22), h01(XI, ZI, 23)
    lawn = mat == LAWN_M
    f = vnoise(X, Z, 6.5, 31) * 0.6 + vnoise(X, Z, 2.6, 32) * 0.4 + (r1 - 0.5) * 0.16
    put(lawn, G_M)
    put(lawn & (f < 0.42), G_SHADE)
    put(lawn & (f > 0.60), G_SUN)
    put(lawn & (vnoise(X, Z, 4.2, 33) > 0.80), CLOVER)
    put(lawn & (dp > 0) & (dp < 1.3), G_D)
    blade = lawn & (r2 < 0.10)
    put(blade, G_L)
    put(blade & (r3 < 0.22), G_T)
    under = np.zeros((H, W), bool)
    under[1:] = blade[:-1]
    put(under & lawn & ~blade, G_D)
    put(lawn & (r3 > 0.9965), LEAF)
    put(lawn & (r1 > 0.9955), DAISY)

    stone = mat == STONE_M
    sh = h01(own_x, own_z, 41)
    for k, rgb in enumerate(STONE):
        put(stone & (np.floor(sh * len(STONE)) == k), rgb)
    lighter, darker = stone & (r1 < 0.10), stone & (r1 > 0.86)
    tex[lighter] = np.clip(tex[lighter] * 1.04, 0, 255).astype(np.uint8)
    tex[darker] = np.clip(tex[darker] * 0.95, 0, 255).astype(np.uint8)
    edge = np.zeros((H, W), bool)
    verge = np.zeros((H, W), bool)
    for dz, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        nb = np.roll(mat, (dz, dx), (0, 1))
        edge |= stone & (nb != STONE_M)
        verge |= stone & (nb == LAWN_M)
    put(edge & (r2 < 0.82), STONE_RIM)
    put(stone & ~edge & (r3 < 0.035), STONE_HI)
    seam = np.abs((X - (own_x + 0.5) * P) - (Z - (own_z + 0.5) * P) * (sh * 3 - 1.5))
    put(stone & ~edge & (h01(own_x, own_z, 42) < 0.07) & (seam < 0.55), STONE_DK)
    put(verge & (r1 < 0.10 + 0.30 * wild), MOSS[0])
    put(verge & (r1 < 0.04 + 0.10 * wild), MOSS[1])

    joint = mat == JOINT_M
    put(joint, JOINT[0])
    put(joint & (r1 < 0.4), JOINT[1])
    put(joint & (dp > -3.5) & (r2 < 0.55), JOINT_MOSS)

    dirt = mat == DIRT_M
    for k, rgb in enumerate(SOIL):
        put(dirt & (np.floor(r1 * len(SOIL)) == k), rgb)
    put(world.flower, BED[0])
    put(world.flower & (r1 < 0.45), BED[1])
    beds = mat == BED_M
    put(beds, BED[0])
    put(beds & (r1 < 0.45), BED[1])

    wood = mat == WOOD_M
    for k, rgb in enumerate(LOAM):
        put(wood & (np.floor(vnoise(X, Z, 3.1, 61) * 2.999) == k), rgb)
    put(wood & (vnoise(X, Z, 5.5, 62) > 0.66), WOOD_MOSS)
    fallen = wood & (r2 < 0.30)
    for k, rgb in enumerate(LITTER):
        put(fallen & (np.floor(r3 * len(LITTER)) == k), rgb)
    put(wood & (h01(XI // 5, ZI, 63) < 0.05) & (XI % 5 < 4), TWIG)
    put(wood & (r1 > 0.992), (226, 214, 196))

    # the marked lane: one dressed slab a quarter-cell, a kerb two voxels wide
    # along it with its drain beside, a round bollard on a dark collar
    lx, lz = XI % 8, ZI % 8
    put(lane, (218, 216, 232))
    put(lane & (h01(XI // 8, ZI // 8, 91) < 0.5), (208, 206, 224))
    put(lane & ((lx == 0) | (lz == 0)), JOINT[0])
    kerb = (world.mark[KERB_NS] & ((lx == 2) | (lx == 3))) | (world.mark[KERB_EW] & ((lz == 2) | (lz == 3)))
    put((world.mark[KERB_NS] & (lx == 5)) | (world.mark[KERB_EW] & (lz == 5)), JOINT[1])
    r2 = (lx - 3.5) ** 2 + (lz - 3.5) ** 2
    post = world.mark[BOLLARD] & (r2 <= 5)
    put(world.mark[BOLLARD] & (r2 > 5) & (r2 <= 11), JOINT[1])
    put(kerb | post, (226, 222, 240))

    # the pier: boards four wide running east-west, butt joints staggered
    board = ZI // 4
    along = XI + board * 7
    tone = np.floor(h01(board, along // 23, 81) * len(PLANK)).astype(int)
    for k, rgb in enumerate(PLANK):
        put(deck & (tone == k), rgb)
    grain = deck & (h01(XI // 3, ZI, 82) < 0.16)
    tex[grain] = np.clip(tex[grain] * 0.93, 0, 255).astype(np.uint8)
    put(deck & ((ZI % 4 == 0) | (along % 23 == 0)), PLANK_GAP)
    put(deck & (ZI % 4 == 2) & (along % 23 == 2), (92, 92, 104))            # a nail
    # setts: small squared stone, laid in bond
    course = ZI // 4
    u = XI + course % 2 * 3
    tone = np.floor(h01(u // 6, course, 83) * len(SETT)).astype(int)
    for k, rgb in enumerate(SETT):
        put(sett & (tone == k), rgb)
    put(sett & ((ZI % 4 == 0) | (u % 6 == 0)), SETT_JOINT)
    put(sett & ((ZI % 4 == 0) | (u % 6 == 0)) & (r1 < 0.12), JOINT_MOSS)

    # ---- what grows
    grows = np.full((H, W), ".", dtype="<U1")
    free = (claimed | world.px("W")) & ground    # nothing is planted in tall grass or flowers

    def grow(mask, letter):
        grows[mask & (grows == ".") & free] = letter

    grow(kerb, "k")
    fern = wood & (h01(XI, ZI, 64) < 0.0028)   # every clump cuts three rows of sheet into runs
    grow(fern & (r1 < 0.5), "F")
    grow(fern, "f")
    for k, (dz, dx) in enumerate(((0, 1), (0, -1), (1, 0), (-1, 0))):
        grow(np.roll(fern, (dz, dx), (0, 1)) & wood & (h01(XI, ZI, 65 + k) < 0.6), "f")
    grow(wood & (h01(XI, ZI, 69) < 0.0006), "u")
    grow(post, "K")
    tall = h01(XI, ZI // 3, 51) < 0.55
    planted = beds & (h01(XI, ZI, 52) < np.where(drift, 0.50, 0.88))
    grow(planted & tall, "L")
    grow(planted & ~tall, "l")
    petals = np.zeros((H, W), bool)
    for dz, dx in ((1, 0), (2, 0), (1, 1), (1, -1), (0, 2), (0, -2)):
        petals |= np.roll(beds, (dz, dx), (0, 1))
    put(petals & ~beds & np.isin(mat, (LAWN_M, STONE_M, JOINT_M)) & (r2 > 0.80), PETAL)
    for r, c in zip(*np.nonzero(world.kind == "S")):                         # a sprig at each end of a sign
        for x0 in (0, 1, 14, 15):
            for z0 in range(9, 15):
                grows[r * 16 + z0, c * 16 + x0] = "L" if (x0 + z0) % 3 else "l"
    # Tufts are CLUMPS -- a crown two up and its shoulders -- thick along the
    # verges, thin across the open lawn; a flower is the crown of one. A lone
    # cube on a lawn reads as a stud on a brick.
    crown = lawn & (((dp > 0.4) & (dp < 5) & (r3 < (0.022 + 0.020 * wild) * dens))
                    | ((dp >= 5) & (r3 < (0.003 + 0.007 * wild) * dens)))
    bloom = h01(XI, ZI, 75)
    # lavender strays out along the roads and thins with every step from town
    away = np.hypot(np.maximum(0, np.maximum(-X, X - 320)), np.maximum(0, np.maximum(-Z, Z - 288)))
    sprig = crown & (bloom >= 0.13) & (bloom < 0.13 + 0.08 * np.where(town, 1, 2.5 * np.exp(-away / 110)))
    grow(crown & (bloom < 0.08), "W")
    grow(crown & (bloom < 0.13), "Y")
    grow(sprig, "L")
    grow(crown & (r1 < 0.68), "G")
    grow(crown, "g")
    for k, (dz, dx) in enumerate(((0, 1), (0, -1), (1, 0), (-1, 0))):
        beside = lawn & (h01(XI, ZI, 60 + k) < 0.55)
        grow(np.roll(sprig, (dz, dx), (0, 1)) & beside, "l")
        grow(np.roll(crown, (dz, dx), (0, 1)) & beside, "g")
    grow(dirt & ~world.flower & (h01(XI, ZI, 73) < 0.020 * dens), "p")
    grow(verge & (h01(XI, ZI, 74) < (0.012 + 0.03 * wild) * dens), "m")
    return ground, claimed, tex, lawn | post | wood, grows     # a bollard stands on a drum


# ------------------------------------------------------------------ writing --

def sheet_path(mid):
    return ROOT / f"assets/buildings/lavground_{mid}.png"


def write():
    world = World()
    ground, claimed, tex, turf, grows = paint(world)
    index = ["-- WRITTEN BY tools/lavender_ground.py -- do not edit by hand.",
             "-- Where each floored map lies in the world (cells), its data and its sheet.",
             "return { maps = {"]
    for mid, gx, gy, w, h, _ in world.maps:
        r0, c0 = (gy - world.cy0) * 16, (gx - world.cx0) * 16
        win = (slice(r0, r0 + h * 16), slice(c0, c0 + w * 16))
        g_here = ground[win]
        px = np.zeros((h * 16, w * 16, 3), np.uint8)
        px[:] = (40, 38, 50)
        px[g_here] = tex[win][g_here]
        # the swatches: one texel each, parked in a cell that is never ground
        spare = [(cy, cx) for cy in range(h) for cx in range(w)
                 if world.kind[gy + cy - world.cy0, gx + cx - world.cx0] == "."]
        assert spare, mid
        sy, sx = spare[len(spare) // 2]
        lines = ["-- WRITTEN BY tools/lavender_ground.py -- do not edit by hand.",
                 f"-- The voxel half of assets/buildings/lavground_{mid}.png (the map's plan, one",
                 "-- texel a voxel): t = the tiles a cell was painted for, b = which texels are",
                 "-- turf, g = what grows (upper case stands two tall), claim = false: laid only.",
                 "return {", f"  sheet = {{ w = {w * 16}, h = {h * 16} }},", "  grows = {"]
        k = 0
        for name, g in GROWS.items():
            idx = {}
            for part in ("top", "stem"):
                idx[part] = []
                for rgb in g[part]:
                    x, z = sx * 16 + (k % 8) * 2, sy * 16 + (k // 8) * 2
                    px[z, x] = rgb
                    idx[part].append(z * w * 16 + x)
                    k += 1
            lines.append(f"    {name} = {{ top = {{ {', '.join(map(str, idx['top']))} }}, "
                         f"stem = {{ {', '.join(map(str, idx['stem']))} }} }},")
        lines += ["  },", "  cells = {"]
        n = 0
        for cy in range(h):
            for cx in range(w):
                kind = world.kind[gy + cy - world.cy0, gx + cx - world.cx0]
                if kind == ".":
                    continue
                cell = (slice(r0 + cy * 16, r0 + cy * 16 + 16), slice(c0 + cx * 16, c0 + cx * 16 + 16))
                b = "".join("1" if v else "0" for v in turf[cell].flat)
                if len(set(b)) == 1:
                    b = b[0]
                g = "".join(grows[cell].flat)
                t = ", ".join(map(str, world.tiles[(mid, cx, cy)]))
                extra = (f', g = "{g}"' if set(g) != {"."} else "") + \
                        (", claim = false" if kind in "GFSW" else "")
                lines.append(f'    ["{cx}:{cy}"] = {{ t = {{ {t} }}, b = "{b}"{extra} }},')
                n += 1
        lines += ["  },", "}", ""]
        Image.fromarray(px).save(sheet_path(mid))
        data = ROOT / f"data/lavground_{mid}.lua"
        data.write_text("\n".join(lines), encoding="utf-8", newline="\n")
        index.append(f'  {mid} = {{ gx = {gx}, gy = {gy}, w = {w}, h = {h}, '
                     f'data = "lavground_{mid}", sheet = "assets/buildings/lavground_{mid}.png" }},')
        print(f"{mid}: {n} cells, {data.stat().st_size // 1024} KB of data, "
              f"sheet {w * 16}x{h * 16} {sheet_path(mid).stat().st_size // 1024} KB")
    index += ["} }", ""]
    (ROOT / "data/lavground_index.lua").write_text("\n".join(index), encoding="utf-8", newline="\n")
    for old in (ROOT / "data/lavender_ground.lua", ROOT / "assets/buildings/lavender_ground.png"):
        if old.exists():
            old.unlink()                         # the one-map files this replaces


# ----------------------------------------------------------------- checking --

def count_quads(at, SW):
    """Buildings.emit's merge, face for face, over one model's box."""
    cell = {}
    for y in range(4):
        for z in range(-1, 17):
            for x in range(-1, 17):
                v = at(x, y, z)
                if v is not None:
                    cell[(x, y, z)] = int(v)
    ci = cell.get
    n = 0

    def ring(x, yo, z):
        return tuple(ci((x + ox, yo, z + oz)) is not None
                     for oz in (-1, 0, 1) for ox in (-1, 0, 1) if ox or oz)

    def run_x(x, y, z, dx, dy, dz):
        k, strip = 1, None
        first = ring(x, y + 1, z) if dy == 1 else None         # the model is `crispTops`
        while True:
            i = ci((x + k, y, z))
            if i is None or i < 0 or ci((x + k + dx, y + dy, z + dz)) is not None:
                return k, first
            if dy == 1 and ring(x + k, y + 1, z) != first:
                return k, first
            p = ci((x + k - 1, y, z))
            if i // SW != p // SW:
                return k, first
            d = i % SW - p % SW
            if d == 1 and strip is not False:
                strip = True
            elif d == 0 and strip is not True:
                strip = False
            else:
                return k, first
            k += 1

    for dx, dy, dz in ((0, 0, 1), (0, 0, -1), (0, 1, 0), (0, -1, 0)):
        for y in range(4):
            if dy == -1 and y == 0:
                continue
            open_ = {}
            for z in range(-1, 17):
                x = -1
                while x <= 16:
                    v = ci((x, y, z))
                    if v is not None and v >= 0 and ci((x + dx, y + dy, z + dz)) is None:
                        k, first = run_x(x, y, z, dx, dy, dz)
                        if dy == 1 and not any(first):
                            if open_.get(x) == (k, z, v - SW):     # the row above takes it in
                                open_[x] = (k, z + 1, v)
                            else:
                                open_[x] = (k, z + 1, v)
                                n += 1
                        else:
                            open_.pop(x, None)
                            n += 1
                        x += k
                    else:
                        x += 1
    for d in (1, -1):
        for y in range(4):
            for x in range(-1, 17):
                z = -1
                while z <= 16:
                    i = ci((x, y, z))
                    if i is not None and i >= 0 and ci((x + d, y, z)) is None:
                        k = 1
                        while (ci((x, y, z + k)) or -1) >= 0 and ci((x + d, y, z + k)) is None:
                            k += 1
                        z += k
                        n += 1
                    else:
                        z += 1
    return n


def check():
    lua = LuaRuntime(unpack_returned_tuples=True)
    kit = lua.eval("""function(root)
      local V = { data = function(name) return dofile(root .. "/data/" .. name .. ".lua") end }
      return assert(loadfile(root .. "/lib/LavenderGroundKit.lua"))(V)
    end""")(ROOT.as_posix())
    world = World()
    H, W = world.ch * 16, world.cw * 16
    top = np.zeros((H, W, 3), np.uint8)
    top[:] = (30, 28, 38)
    flush = np.zeros((H, W), bool)
    total = 0
    OUT.mkdir(exist_ok=True)
    for mid, gx, gy, w, h, grid in world.maps:
        sheet = np.array(Image.open(sheet_path(mid)).convert("RGB"))
        assert sheet.shape[:2] == (h * 16, w * 16), sheet.shape
        SW = w * 16
        tile_at = lambda x, y, g=grid: g[int(y)][int(x)] if 0 <= y < len(g) and 0 <= x < len(g[0]) else None  # noqa: E731
        quads = cells = 0
        for cy in range(h):
            for cx in range(w):
                kind = world.kind[gy + cy - world.cy0, gx + cx - world.cx0]
                spec = kit.spec(tile_at, cx * 2, cy * 2, mid)
                assert (spec is not None) == (kind != "."), (mid, cx, cy, kind)
                if spec is None:
                    continue
                model = kit.model(spec)
                assert model is not None and not isinstance(model, tuple), model
                assert bool(model.lift) == (kind not in "GFSW"), (mid, cx, cy)
                cells += 1
                quads += count_quads(model.at, SW)
                r0, c0 = (gy + cy - world.cy0) * 16, (gx + cx - world.cx0) * 16
                for z in range(16):
                    for x in range(16):
                        hi = max(y for y in range(4) if model.at(x, y, z) is not None)
                        i = int(model.at(x, hi, z))
                        assert 0 <= i < sheet.shape[0] * SW, (mid, cx, cy, i)
                        lit = (0.86, 1.0, 1.1, 1.18)[hi]
                        top[r0 + z, c0 + x] = np.minimum(255, sheet[i // SW, i % SW] * lit)
                        flush[r0 + z, c0 + x] = hi == 0
        total += quads
        print(f"{mid}: {cells} cells, {quads} quads ({quads / cells:.0f} a cell)")
        r0, c0 = (gy - world.cy0) * 16, (gx - world.cx0) * 16
        Image.fromarray(top[r0:r0 + h * 16, c0:c0 + w * 16]).save(OUT / f"lavground_{mid}.png")
    Image.fromarray(top).save(OUT / "lavground_world.png")
    # the three joins, enlarged: if there were a seam it would be in these
    ox, oz = -world.cx0 * 16, -world.cy0 * 16
    for name, (x0, z0, x1, z1) in {"west": (-96, 64, 96, 224), "north": (48, -96, 240, 96),
                                   "south": (48, 192, 240, 384)}.items():
        crop = Image.fromarray(top[oz + z0:oz + z1, ox + x0:ox + x1])
        crop.resize((crop.width * 4, crop.height * 4), Image.NEAREST).save(OUT / f"lavground_join_{name}.png")

    # a cell at the town's edge sees its neighbour ACROSS the map's edge
    grid = world.maps[0][5]
    spec = kit.spec(lambda x, y: grid[int(y)][int(x)], 0, 16, TOWN)
    assert spec is not None and kit.model(spec).at(-1, 0, 5) == -1, "Route 8 is not there for Lavender's AO"
    # every door and every road can be walked to over flush ground
    seen = np.zeros((H, W), bool)
    start = (oz + 137, ox + 1)
    assert flush[start], "the west gate is not flagged"
    seen[start] = True
    todo = [start]
    while todo:
        z, x = todo.pop()
        for nz, nx in ((z + 1, x), (z - 1, x), (z, x + 1), (z, x - 1)):
            if 0 <= nz < H and 0 <= nx < W and flush[nz, nx] and not seen[nz, nx]:
                seen[nz, nx] = True
                todo.append((nz, nx))
    for name, (x, z) in REACH.items():
        assert seen[oz + z - 3:oz + z + 4, ox + x - 3:ox + x + 4].any(), f"no path reaches {name}"
    for name, (x, z) in {"Route 8": (-40, 136), "Route 10": (144, -12), "Route 12": (144, 300)}.items():
        assert seen[oz + z - 6:oz + z + 7, ox + x - 6:ox + x + 7].any(), f"the road does not carry on into {name}"
    print(f"{total} quads in all")
    assert total < 120000, "over budget"
    print("PASS ->", OUT / "lavground_world.png")


if __name__ == "__main__":
    if "--write" in sys.argv:
        write()
    check()
