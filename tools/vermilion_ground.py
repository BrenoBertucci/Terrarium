"""The ground of Vermilion City: a plan, its data, a check.

  python tools/vermilion_ground.py --write   paint assets/buildings/vermground_<MAP>.png,
                                             write data/vermground_<MAP>.lua + the index
  python tools/vermilion_ground.py           check the REAL kit against the REAL map,
                                             count quads the way Buildings.emit merges
                                             them, render tools/_kit_out/vermground_*.png

Same pipeline as tools/lavender_ground.py (whose helpers this borrows) and the
same kit stands it up (lib/LavenderGroundKit.lua, through a second index). A
different town. Lavender is a village: crazy paving wandering through lawn.
Vermilion is a PORT, "the port of exquisite sunsets", and its ground is built:

  brick      the streets, in herringbone terracotta with a cream soldier
             course down each edge. Ruled edges -- this is a city.
  the sun    the square where the road from Route 6 meets the avenue: a
             sunburst mosaic, sixteen rays in vermilion and gold
  the quay   every edge that meets the sea: big pale slabs behind a granite
             coping, an iron mooring bollard every few paces
  the green  coastal turf a voxel proud of the paving, sun-bleached, going to
             sand toward the water, dune grass and poppies in it; planters of
             marigold and poppy under the housefronts
  the lot    the kerbed building plot: rammed earth inside its kerb
  the mole   rough stone under the trees that stand in the harbour

The drawn floor (the white brick cobble, $39) is only the answer to "is this
cell ground"; nothing of it is kept. Nothing here is extracted from the ROM.

Kinds: V paved ground (claimed) / L the two grass cells by the Gym (claimed)
       Q a shore cell: the quay is laid over its LAND quarters only (the drawn
         quay wall, $31-$33/$54), the sea's are void (`b` = "-"); NOT claimed
       S sign, N fence, W tree: laid, NOT claimed -- what stands there stands
On ROUTES 6 and 11 (and the town's east end, which is Route 11's road already)
the pattern is the route's own, as Lavender's roads keep theirs: P its road, in
the same brick with its edges let go and its cream course broken; L grass;
G tall grass / F flowers, laid and NOT claimed; the shore a beach, not a quay.
All three maps are painted on ONE canvas in world coordinates and then cut, so
there is no edge in the picture -- only in the files.
"""
import sys
from pathlib import Path

import numpy as np
from lupa import LuaRuntime
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from interior_plan import plan  # noqa: E402
from lavender_ground import box_blur, count_quads, h01, vnoise  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tools/_kit_out"
# map id, world cell origin. Read off the connections: Route 6 joins the north
# edge five blocks in, Route 11 the east edge four blocks down.
MAPS = [("VERMILION_CITY", 0, 0), ("ROUTE_6", 10, -36), ("ROUTE_11", 40, 8)]
TOWN = "VERMILION_CITY"
TOWN_W, TOWN_H = 640, 576               # its plan, in voxels
EAST_ROAD = 36                          # from this cell column on, the town's ground is Route 11's road
PAVED_T = {57, 35, 16, 32, 33}           # the cobble, the plain ground, and the lot's kerb marks
KERB_NS, KERB_EW, BOLLARD = 16, 32, 33
LAWN_T = {44, 48}
SIGN = (70, 71, 86, 87)
FENCE = (14, 14, 85, 85)
TREES = ((42, 43, 58, 59), (64, 65, 80, 81))
SEA_T, DOCK_T = 20, 60
SHORE_T = {49, 50, 51, 84}              # the drawn quay wall: the LAND's quarter of a shore cell

# ------------------------------------------------------------- the palette --
# Lifted by what the light takes away (paving shows at x0.69, turf at x0.85:
# measured in Lavender's first frames).
BRICK = [(236, 128, 88), (222, 112, 78), (246, 148, 100), (208, 100, 74), (230, 138, 104)]
BRICK_DK = (172, 84, 66)
CREAM = [(250, 238, 210), (242, 228, 198), (252, 244, 222)]
CREAM_JOINT = (196, 176, 150)
SLAB = [(236, 228, 212), (226, 218, 204), (244, 236, 220), (230, 224, 214)]
SLAB_JOINT = (158, 146, 136)
COPING = [(186, 184, 194), (170, 168, 180), (198, 196, 204)]
COPING_EDGE = (132, 130, 144)
SAND = [(248, 230, 178), (240, 218, 162), (252, 238, 194)]
SHELL = (255, 250, 240)
EARTH = [(206, 170, 128), (192, 156, 118), (216, 182, 140)]
G_D, G_M, G_L, G_T = (84, 130, 84), (120, 172, 96), (156, 202, 108), (192, 224, 128)
G_SHADE, G_SUN = (102, 152, 92), (142, 190, 102)
STRAW = [(226, 214, 140), (208, 196, 124)]
SUN_GOLD, SUN_RED, SUN_DARK = (255, 206, 96), (226, 78, 58), (150, 72, 62)
BED = [(132, 100, 84), (118, 88, 78)]
MOLE = [(176, 168, 162), (160, 152, 150), (190, 182, 172), (150, 144, 146)]
MOLE_JOINT = (112, 106, 112)
GROWS = {
    "g": {"top": [G_SUN, G_L, G_M], "stem": [G_M, G_SHADE]},
    "d": {"top": STRAW + [(240, 230, 160)], "stem": [(170, 176, 104), (150, 160, 96)]},   # dune grass
    "o": {"top": [(255, 106, 60), (255, 140, 64), (244, 84, 66)], "stem": [(96, 150, 88)]},  # poppy, marigold
    "y": {"top": [(255, 214, 90)], "stem": [G_M]},
    "w": {"top": [(250, 248, 240)], "stem": [G_M]},
    "k": {"top": [(252, 244, 224), (244, 234, 210)], "stem": [(214, 200, 176)]},          # the lot's kerb
    "b": {"top": [(74, 72, 84)], "stem": [(52, 50, 60), (62, 60, 72)]},                   # mooring bollard, iron
    "p": {"top": [(210, 204, 196), (188, 182, 178)], "stem": [(188, 182, 178)]},          # pebble
}

# --------------------------------------------------------- the city's plan --
# World voxels, x east, z south. Route 6 comes in on cell columns 18..19,
# Route 11 on cell rows 14..15 (and, north of the cave house, 8..9).
SUN = (304, 112, 44)
STREETS = [
    (34, [(304, -8), (304, 70)]),                                   # down from Route 6
    (44, [(96, 80), (516, 80)]),                                    # the avenue, under the housefronts
    (34, [(304, 112), (320, 168), (320, 232)]),                     # the way down to the water
    (48, [(90, 240), (660, 240)]),                                  # the waterfront, out to Route 11
    (44, [(112, 190), (112, 306)]),                                 # the west quay
    (26, [(336, 240), (336, 326), (378, 330)]),                     # the lane to the house by the dock
    # the north-east is only reached from Route 11 (the fences shut it off
    # from the avenue): a park, with one narrow walk through it
    (12, [(396, 30), (470, 22), (540, 30), (590, 56)]),
    (9, [(250, 286), (246, 318), (226, 336), (200, 330)]),          # stepping stones: the cut bush to the Gym
]
ROUNDS = [(SUN[0], SUN[1], SUN[2] + 2, SUN[2] + 2), (496, 246, 26, 14), (376, 330, 16, 9),
          (200, 328, 14, 8)]
BEDS = [
    (98, 64, 110, 66), (130, 64, 158, 66), (162, 64, 174, 66), (194, 64, 222, 66),
    (226, 64, 286, 66), (322, 64, 382, 66),
    (130, 224, 142, 226), (162, 224, 190, 226), (226, 224, 238, 226), (258, 224, 286, 226),
    (354, 224, 366, 226), (386, 224, 414, 226),
    (130, 320, 190, 322), (210, 320, 222, 322), (354, 320, 366, 322), (386, 320, 414, 322),
]
REACH = {"Route 6": (304, 3), "Route 11": (636, 240),
         "Centre": (184, 70), "house NW": (120, 70), "Fan Club": (152, 230), "house": (248, 230),
         "Mart": (376, 230), "house by the dock": (376, 326), "the dock": (496, 252)}


def kind_of(p, town, cx, cy):
    s = set(p)
    if p == SIGN:
        return "S"
    if p == FENCE:
        return "N"
    if p in TREES:
        return "W"
    if s <= LAWN_T or (not town and s <= LAWN_T | {DOCK_T}):
        return "L"
    if s <= PAVED_T:
        return "V" if town and (cx < EAST_ROAD or cy < 4) else "P"
    if s <= SHORE_T | {SEA_T} and s & SHORE_T:
        return "Q"
    if not town and s == {82}:
        return "G"
    if not town and s <= LAWN_T | {3}:
        return "F"
    return "."


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


def reach_of(mask, n):
    """Octagonal distance (in voxels, up to n) from `mask`, the map's edge carried outward."""
    cur = np.pad(mask, n, mode="edge")
    d = np.where(cur, 0.0, 1e9)
    for k in range(1, n + 1):
        nb = cur.copy()
        for dz, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)) + (((1, 1), (1, -1), (-1, 1), (-1, -1)) if k % 2 == 0 else ()):
            nb |= np.roll(cur, (dz, dx), (0, 1))
        d[nb & ~cur] = k
        cur = nb
    return d[n:-n, n:-n]


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
        H, W = self.ch * 16, self.cw * 16
        self.kind = np.full((self.ch, self.cw), ".", dtype="<U1")
        self.tiles = {}
        self.sea = np.zeros((H, W), bool)
        self.mark = {t: np.zeros((H, W), bool) for t in (KERB_NS, KERB_EW, BOLLARD)}
        self.plot = np.zeros((H, W), bool)
        self.land = np.zeros((H, W), bool)             # a shore cell's land quarters
        self.flower = np.zeros((H, W), bool)
        for mid, gx, gy, w, h, grid in self.maps:
            for cy in range(h):
                for cx in range(w):
                    p = (grid[cy * 2][cx * 2], grid[cy * 2][cx * 2 + 1],
                         grid[cy * 2 + 1][cx * 2], grid[cy * 2 + 1][cx * 2 + 1])
                    r, c = gy + cy - self.cy0, gx + cx - self.cx0
                    k = kind_of(p, mid == TOWN, cx, cy)
                    self.kind[r, c] = k
                    self.tiles[(mid, cx, cy)] = p
                    whole = (slice(r * 16, r * 16 + 16), slice(c * 16, c * 16 + 16))
                    if p == (DOCK_T,) * 4 or (SEA_T in p and k != "Q"):
                        self.sea[whole] = True
                    if k == "V" and set(p) & set(self.mark):
                        self.plot[whole] = True
                    for q, (oz, ox) in enumerate(((0, 0), (0, 8), (8, 0), (8, 8))):
                        if k == "Q":
                            quarter = (slice(r * 16 + oz, r * 16 + oz + 8), slice(c * 16 + ox, c * 16 + ox + 8))
                            (self.sea if p[q] == SEA_T else self.land)[quarter] = True
                        if k == "F" and p[q] == 3:
                            self.flower[r * 16 + oz:r * 16 + oz + 8, c * 16 + ox:c * 16 + ox + 8] = True
                        if k in "VP" and p[q] in self.mark:
                            self.mark[p[q]][r * 16 + oz:r * 16 + oz + 8, c * 16 + ox:c * 16 + ox + 8] = True

    def px(self, letters):
        return np.kron(np.isin(self.kind, list(letters)), np.ones((16, 16), bool))


(LAWN_M, BRICK_M, KERB_M, SLAB_M, COPING_M, SAND_M, BED_M, SUN_M, EARTH_M, MOLE_M,
 LANE_M) = range(11)


def paint(world):
    H, W = world.ch * 16, world.cw * 16
    X, Z = np.meshgrid(np.arange(W) + 0.5 + world.cx0 * 16, np.arange(H) + 0.5 + world.cy0 * 16)
    XI, ZI = np.floor(X).astype(np.int64), np.floor(Z).astype(np.int64)
    ground = world.px("VLPSNWGF") | world.land    # a shore cell is laid only where it is land
    claimed = world.px("VLP")
    ds = reach_of(world.sea, 72)                       # voxels to the sea
    wild = vnoise(X, Z, 46, 7)
    # How far outside the town's plan: 0 in it. A route lets its edges go
    # ragged, a little more with every step from the last house.
    away = np.hypot(np.maximum(0, np.maximum(-X, X - TOWN_W)), np.maximum(0, np.maximum(-Z, Z - TOWN_H)))
    rough = np.clip(away / 48, 0, 1)
    # the streets, and a route's own road: its cell mask blurred into a field
    # (so a corner is a curve) and normalised by the ground there is
    road = box_blur(box_blur(world.px("P").astype(float), 5), 5)
    open_ = box_blur(box_blur(ground.astype(float), 5), 5)
    sd_road = (0.5 - road / np.maximum(open_, 1e-6)) * 14
    dp = np.minimum(street_d(X, Z), sd_road)           # < 0: paved
    dp = dp + (vnoise(X, Z, 9, 3) - 0.5) * 3.2 * rough
    # the quay is the town's, and the inlet's it shares with Route 11
    quay = (away == 0) | ((X < 776) & (Z >= 240) & (Z < 368))

    mat = np.full((H, W), LAWN_M)
    beach = (ds < 56) & (vnoise(X, Z, 13, 5) + (56 - np.minimum(ds, 56)) / 90 > 0.80)
    mat[beach] = SAND_M
    mat[dp < 0] = BRICK_M
    # the cream course: whole in town, broken up along a route
    mat[(dp < 0) & (dp >= -2) & (vnoise(X, Z, 12, 9) > 0.62 * rough)] = KERB_M
    mat[(ds < 14) & quay] = SLAB_M
    mat[(ds < 4) & quay] = COPING_M
    mat[(ds < 9) & ~quay] = SAND_M                     # a route's shore is a beach
    sr = np.hypot(X - SUN[0], Z - SUN[1])
    mat[sr < SUN[2]] = SUN_M
    bed = np.zeros((H, W), bool)
    for x0, z0, x1, z1 in BEDS:
        bed |= (XI >= x0) & (XI <= x1) & (ZI >= z0) & (ZI <= z1)
    mat[bed & (ds >= 4)] = BED_M
    # the building plot: the ring its kerb marks make, and the earth inside it
    lane = world.mark[KERB_NS] | world.mark[KERB_EW] | world.mark[BOLLARD]
    rows, cols = np.nonzero(world.plot)
    inside = np.zeros((H, W), bool)
    if len(rows):
        inside[rows.min():rows.max() + 1, cols.min():cols.max() + 1] = True
    mat[inside] = EARTH_M
    mat[lane] = LANE_M
    mat[world.px("W") & (ds < 40) & quay] = MOLE_M      # a tree on land stands in turf
    mat[world.px("W") & ~((ds < 40) & quay)] = LAWN_M
    # poppies run wild in drifts across the open green
    drift = ((mat == LAWN_M) & (dp > 5) & (ds > 20) & (vnoise(X, Z, 19, 17) > 0.66)
             & (vnoise(X, Z, 5, 18) > 0.45) & claimed)
    mat[world.px("L")] = LAWN_M
    # turf under whatever must keep standing: tall grass, a sign, the grass
    # round a flower (whose own quarter is soil)
    keep = world.px("GS") | (world.px("F") & ~world.flower)
    mat[keep] = LAWN_M
    mat[world.flower] = BED_M

    # ---- colour
    tex = np.zeros((H, W, 3), np.uint8)

    def put(mask, rgb):
        tex[mask] = rgb

    def tones(mask, palette, pick):
        idx = np.floor(pick * len(palette)).astype(int) % len(palette)
        for k, rgb in enumerate(palette):
            put(mask & (idx == k), rgb)

    r1, r2, r3 = h01(XI, ZI, 21), h01(XI, ZI, 22), h01(XI, ZI, 23)

    # brick, in herringbone: bricks 4 x 2, a unit 2 x 2
    i, j = XI // 2, ZI // 2
    k = (i - j) % 4
    bi, bj = np.where(k == 1, i - 1, i), np.where(k == 3, j + 1, j)
    brick = mat == BRICK_M
    tones(brick, BRICK, h01(bi, bj * 2 + (k >= 2), 41))
    put(brick & (h01(bi, bj * 2 + (k >= 2), 42) < 0.07), BRICK_DK)          # a fired-dark brick
    dust = brick & (r1 < 0.05)
    tex[dust] = np.clip(tex[dust] * 1.06 + 6, 0, 255).astype(np.uint8)
    worn = brick & (vnoise(X, Z, 17, 43) > 0.72) & (r2 < 0.35)
    tex[worn] = np.clip(tex[worn] * 0.94, 0, 255).astype(np.uint8)

    kerb = mat == KERB_M
    tones(kerb, CREAM, h01((XI + ZI) // 5, (XI - ZI) // 5, 44))
    put(kerb & ((XI + ZI) % 5 == 0), CREAM_JOINT)

    slab = mat == SLAB_M
    tones(slab, SLAB, h01(XI // 8, ZI // 8, 45))
    put(slab & ((XI % 8 == 0) | (ZI % 8 == 0)), SLAB_JOINT)
    put(slab & (r3 < 0.02), SLAB[2])
    put(slab & ((XI % 8 == 0) | (ZI % 8 == 0)) & (ds < 9) & (r1 < 0.25), (150, 170, 140))   # weed in a joint

    cope = mat == COPING_M
    tones(cope, COPING, h01((XI + ZI * 3) // 7, 0, 46))
    put(cope & (ds < 2), COPING_EDGE)
    put(cope & ((XI + ZI * 3) % 7 == 0) & (ds >= 2), COPING_EDGE)

    sand = mat == SAND_M
    tones(sand, SAND, vnoise(X, Z, 4.5, 47) * 0.7 + r1 * 0.3)
    put(sand & (r2 > 0.994), SHELL)
    put(sand & (np.sin(X * 0.55 + vnoise(X, Z, 9, 48) * 5) > 0.93), SAND[1])     # wind ripple

    earth = mat == EARTH_M
    tones(earth, EARTH, vnoise(X, Z, 5, 49) * 0.6 + r1 * 0.4)
    put(earth & ((ZI + (XI // 9)) % 11 == 0) & (r2 < 0.7), (176, 142, 108))      # a rake's line
    put(earth & (r3 > 0.985), (226, 214, 196))

    lawn = mat == LAWN_M
    f = vnoise(X, Z, 6.5, 31) * 0.6 + vnoise(X, Z, 2.6, 32) * 0.4 + (r1 - 0.5) * 0.16
    put(lawn, G_M)
    put(lawn & (f < 0.40), G_SHADE)
    put(lawn & (f > 0.58), G_SUN)
    put(lawn & (vnoise(X, Z, 11, 33) > 0.70) & (r2 < 0.5), STRAW[1])             # sun-bleached
    blade = lawn & (r2 < 0.10)
    put(blade, G_L)
    put(blade & (r3 < 0.22), G_T)
    under = np.zeros((H, W), bool)
    under[1:] = blade[:-1]
    put(under & lawn & ~blade, G_D)
    edge = np.zeros((H, W), bool)
    for dz, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        edge |= lawn & (np.roll(mat, (dz, dx), (0, 1)) != LAWN_M)
    put(edge, G_D)

    beds = mat == BED_M
    put(beds, BED[0])
    put(beds & (r1 < 0.45), BED[1])

    # the sun: a gold disc, sixteen rays (eight long in vermilion, eight short
    # in gold) on cream, a dark band, a ring of radial brick, a cream kerb
    sun = mat == SUN_M
    ang = (np.arctan2(Z - SUN[1], X - SUN[0]) / (2 * np.pi)) % 1
    wedge = np.floor(ang * 16).astype(int)
    off = np.abs((ang * 16) % 1 - 0.5) * 2                     # 0 down a ray's middle, 1 between rays
    tones(sun, CREAM, h01(XI // 3, ZI // 3, 50))
    long_ray = (wedge % 2 == 0) & (off < 1.0 - (sr - 9) / 25)
    short_ray = (wedge % 2 == 1) & (off < 0.8 - (sr - 9) / 14)
    put(sun & short_ray & (sr < 34), SUN_GOLD)
    put(sun & long_ray & (sr < 34), SUN_RED)
    put(sun & long_ray & (sr < 34) & (off < 0.12), (244, 112, 78))
    put(sun & (sr < 9), SUN_DARK)
    put(sun & (sr < 7.5), SUN_GOLD)
    put(sun & (sr < 3), SUN_RED)
    put(sun & (sr >= 34) & (sr < 36), SUN_DARK)
    ring = sun & (sr >= 36) & (sr < 42)
    tones(ring, BRICK, h01(np.floor(ang * 72).astype(int), 0, 51))
    put(ring & (np.floor(ang * 72) % 9 == 0), SUN_GOLD)
    put(sun & (sr >= 42), CREAM[0])

    mole = mat == MOLE_M
    course = ZI // 5
    u = XI + course % 2 * 4
    tones(mole, MOLE, h01(u // 8, course, 52))
    put(mole & ((ZI % 5 == 0) | (u % 8 == 0)), MOLE_JOINT)
    put(mole & ((ZI % 5 == 0) | (u % 8 == 0)) & (r1 < 0.3), (128, 150, 118))
    put(mole & (r2 > 0.97), SAND[0])

    # the plot's kerb: dressed slabs, flush; the kerb itself and the bollards stand
    lx, lz = XI % 8, ZI % 8
    put(mat == LANE_M, CREAM[1])
    put((mat == LANE_M) & ((lx == 0) | (lz == 0)), CREAM_JOINT)
    kerb_up = (world.mark[KERB_NS] & ((lx == 3) | (lx == 4))) | (world.mark[KERB_EW] & ((lz == 3) | (lz == 4)))
    q = (lx - 3.5) ** 2 + (lz - 3.5) ** 2
    post = world.mark[BOLLARD] & (q <= 5)
    put(kerb_up | post, CREAM[2])

    # ---- what grows
    grows = np.full((H, W), ".", dtype="<U1")
    free = claimed & ground

    def grow(mask, letter):
        grows[mask & (grows == ".") & free] = letter

    grow(kerb_up, "k")
    grow(post, "K")
    # mooring bollards: two by two on the slabs behind the coping, every 24 along
    ew = np.zeros((H, W), bool)
    for dz in (-7, 7):
        ew |= np.roll(world.sea, dz, 0)
    along = np.where(ew, XI, ZI)
    across = np.where(ew, ZI, XI)
    moor = slab & (ds >= 5) & (ds < 7) & (along % 24 < 2) & (h01(along // 24, across // 16, 53) < 0.8)
    grow(moor, "B")
    planted = beds & (h01(XI, ZI, 54) < 0.9)
    grow(drift & (h01(XI, ZI, 59) < 0.16) & (h01(XI // 2, ZI // 2, 66) < 0.5), "O")
    grow(drift & (h01(XI, ZI, 59) < 0.16), "o")
    grow(planted & (h01(XI // 2, ZI, 55) < 0.5), "O")
    grow(planted, "o")
    # tufts are CLUMPS (a crown two up and its shoulders): thick along the
    # verges, thin across the open green; dune grass where the turf meets sand
    near_sand = np.zeros((H, W), bool)
    for dz, dx in ((0, 3), (0, -3), (3, 0), (-3, 0)):
        near_sand |= np.roll(sand, (dz, dx), (0, 1))
    crown = lawn & ~edge & (((dp < 6) & (r3 < 0.020 + 0.02 * wild)) | (r3 < 0.004 + 0.008 * wild))
    dune = (lawn | sand) & (near_sand | sand) & (h01(XI, ZI, 56) < 0.012) & (ds >= 14)
    bloom = h01(XI, ZI, 57)
    grow(dune, "D")
    grow(crown & (bloom < 0.10), "O")
    grow(crown & (bloom < 0.15), "Y")
    grow(crown & (bloom < 0.19), "W")
    grow(crown & (r1 < 0.68), "G")
    grow(crown, "g")
    for n, (dz, dx) in enumerate(((0, 1), (0, -1), (1, 0), (-1, 0))):
        beside = h01(XI, ZI, 60 + n) < 0.55
        grow(np.roll(dune, (dz, dx), (0, 1)) & (lawn | sand) & beside, "d")
        grow(np.roll(crown, (dz, dx), (0, 1)) & lawn & beside, "g")
    grow(mole & (r3 > 0.992), "p")
    grow(sand & (h01(XI, ZI, 58) < 0.004), "p")
    return ground, claimed, tex, lawn | post, grows     # turf, and a bollard's drum, stand a voxel proud



# ------------------------------------------------------------------ writing --

def sheet_path(mid):
    return ROOT / f"assets/buildings/vermground_{mid}.png"


def write():
    world = World()
    ground, claimed, tex, turf, grows = paint(world)
    index = ["-- WRITTEN BY tools/vermilion_ground.py -- do not edit by hand.",
             "-- Where each floored map lies in ITS world (cells), its data and its sheet.",
             "return { maps = {"]
    for mid, gx, gy, w, h, _ in world.maps:
        r0, c0 = (gy - world.cy0) * 16, (gx - world.cx0) * 16
        win = (slice(r0, r0 + h * 16), slice(c0, c0 + w * 16))
        px = np.zeros((h * 16, w * 16, 3), np.uint8)
        px[:] = (40, 38, 50)
        px[ground[win]] = tex[win][ground[win]]
        # the swatches: one texel each, parked in a cell that is never ground
        spare = [(cy, cx) for cy in range(h) for cx in range(w)
                 if world.kind[gy + cy - world.cy0, gx + cx - world.cx0] == "."]
        sy, sx = spare[len(spare) // 2]
        lines = ["-- WRITTEN BY tools/vermilion_ground.py -- do not edit by hand.",
                 f"-- The voxel half of assets/buildings/vermground_{mid}.png (the map's plan, one",
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
                b = "".join("-" if not gr else ("1" if v else "0")
                            for v, gr in zip(turf[cell].flat, ground[cell].flat))
                if len(set(b)) == 1:
                    b = b[0]
                g = "".join(grows[cell].flat)
                t = ", ".join(map(str, world.tiles[(mid, cx, cy)]))
                extra = (f', g = "{g}"' if set(g) != {"."} else "") + \
                        (", claim = false" if kind in "SNWQGF" else "")
                lines.append(f'    ["{cx}:{cy}"] = {{ t = {{ {t} }}, b = "{b}"{extra} }},')
                n += 1
        lines += ["  },", "}", ""]
        Image.fromarray(px).save(sheet_path(mid))
        data = ROOT / f"data/vermground_{mid}.lua"
        data.write_text("\n".join(lines), encoding="utf-8", newline="\n")
        index.append(f'  {mid} = {{ gx = {gx}, gy = {gy}, w = {w}, h = {h}, '
                     f'data = "vermground_{mid}", sheet = "assets/buildings/vermground_{mid}.png" }},')
        print(f"{mid}: {n} cells, {data.stat().st_size // 1024} KB of data, sheet {w * 16}x{h * 16}")
    index += ["} }", ""]
    (ROOT / "data/vermground_index.lua").write_text("\n".join(index), encoding="utf-8", newline="\n")


# ----------------------------------------------------------------- checking --

def check():
    lua = LuaRuntime(unpack_returned_tuples=True)
    kit = lua.eval("""function(root)
      local V = { data = function(name) return dofile(root .. "/data/" .. name .. ".lua") end }
      return assert(loadfile(root .. "/lib/LavenderGroundKit.lua"))(V)
    end""")(ROOT.as_posix())
    world = World()
    H, W = world.ch * 16, world.cw * 16
    top = np.zeros((H, W, 3), np.uint8)
    top[:] = (58, 96, 150)
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
                assert bool(model.lift) == (kind in "VLP"), (mid, cx, cy)
                cells += 1
                quads += count_quads(model.at, SW)
                r0, c0 = (gy + cy - world.cy0) * 16, (gx + cx - world.cx0) * 16
                for z in range(16):
                    for x in range(16):
                        if model.at(x, 0, z) is None:
                            assert kind == "Q", (mid, cx, cy)      # void: the sea's half of a shore cell
                            continue
                        hi = max(y for y in range(4) if model.at(x, y, z) is not None)
                        i = int(model.at(x, hi, z))
                        lit = (0.86, 1.0, 1.1, 1.18)[hi]
                        top[r0 + z, c0 + x] = np.minimum(255, sheet[i // SW, i % SW] * lit)
                        flush[r0 + z, c0 + x] = hi == 0
        total += quads
        print(f"{mid}: {cells} cells, {quads} quads ({quads / cells:.0f} a cell)")
    Image.fromarray(top).resize((W * 2, H * 2), Image.NEAREST).save(OUT / "vermground_world.png")
    # every door and both roads can be walked to over flush paving
    ox, oz = -world.cx0 * 16, -world.cy0 * 16
    seen = np.zeros((H, W), bool)
    start = (oz + REACH["Route 6"][1], ox + REACH["Route 6"][0])
    assert flush[start], "the road from Route 6 is not paved"
    seen[start] = True
    todo = [start]
    while todo:
        z, x = todo.pop()
        for nz, nx in ((z + 1, x), (z - 1, x), (z, x + 1), (z, x - 1)):
            if 0 <= nz < H and 0 <= nx < W and flush[nz, nx] and not seen[nz, nx]:
                seen[nz, nx] = True
                todo.append((nz, nx))
    for name, (x, z) in REACH.items():
        assert seen[max(0, oz + z - 4):oz + z + 5, max(0, ox + x - 4):ox + x + 5].any(), f"no paving reaches {name}"
    print(f"{total} quads in all")
    assert total < 110000, "over budget"
    print("PASS ->", OUT / "vermground_world.png")


if __name__ == "__main__":
    if "--write" in sys.argv:
        write()
    check()
