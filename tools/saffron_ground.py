"""The ground of Saffron City: a plan, its data, a check.

  python tools/saffron_ground.py --write   paint assets/buildings/saffground_SAFFRON_CITY.png,
                                           write data/saffground_SAFFRON_CITY.lua + the index
  python tools/saffron_ground.py           check the REAL kit against the REAL map

The sixth painted world, one map: Saffron is walled in by its four gatehouses,
so there is no road to paint it into (the gates stand at every edge). Stood by
lib/LavenderGroundKit.lua, written and checked by tools/vermilion_ground.py.

Saffron is "the shining, golden land of commerce", and the only town in Kanto
the drawing gives real STREETS: a ring of carriageway inside kerb lines ($20
across, $10 down, $21 the corners), sidewalks outside them, two wide plazas of
brick ($5B). The drawing decides where; the city decides what:

  the carriageway  dark asphalt, a dashed SAFFRON-GOLD line down its middle,
                   white bars where a way out of town crosses it
  the kerbs        pale granite, a raised edge along each line, gold-capped
                   bollards on the corners
  the sidewalks    big cream terrazzo slabs with brass strips in their joints
  the plazas       Art Deco: panels of cream terrazzo, a saffron diamond in
                   each, charcoal borders, brass inlay -- and before Silph Co.
                   a DECO MEDALLION of nested diamonds
  the lawns        clipped, marigolds along them; the street trees in iron
                   grates with a gold rim

Nothing here is extracted from the ROM. The tiles only decided where.
"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vermilion_ground as vg  # noqa: E402
from cerulean_ground import side_dist  # noqa: E402
from lavender_ground import h01, vnoise  # noqa: E402

TOWN = "SAFFRON_CITY"
MAPS = [(TOWN, 0, 0)]
PATH_T = {35, 57, 91}
MARK_T = {16, 32, 33}
LAWN_T = {44, 48}

ASPHALT = [(78, 80, 88), (72, 74, 82), (84, 86, 94), (68, 70, 78)]
GOLD_LINE = (250, 196, 64)
ZEBRA = (240, 240, 236)
GRANITE = [(206, 206, 210), (196, 196, 202), (214, 214, 216)]
TERRAZZO = [(244, 234, 206), (238, 228, 198), (248, 240, 214), (234, 224, 196)]
TERR_SPECK = [(200, 180, 140), (170, 170, 170), (226, 196, 120)]
BRASS = (216, 176, 84)
SAFFRON = [(244, 178, 52), (236, 166, 44)]
CHARCOAL = [(70, 66, 70), (62, 58, 64)]
CREAM = (250, 242, 222)
IRON = [(58, 60, 68), (48, 50, 58)]
S_GRASS = [(86, 160, 80), (74, 148, 74), (100, 172, 88), (66, 136, 68)]
EDGE_D = (52, 110, 60)

GROWS = {
    "g": {"top": [(130, 196, 104), (116, 186, 98)], "stem": [(86, 160, 80)]},
    "m": {"top": [(250, 170, 40), (244, 196, 60), (236, 140, 40)], "stem": [(80, 140, 72)]},   # marigold
    "k": {"top": [(236, 236, 238)], "stem": [(210, 210, 214)]},                                # the kerb's edge
    "b": {"top": [(236, 190, 80)], "stem": [(64, 66, 76), (56, 58, 68)]},                      # bollard, gold cap
}

# World voxels. Where the ways out of town cross the ring road; before Silph Co.
MEDALLION = (296, 400, 15)
REACH = {"Saffron": (320, 104), "Copycat's": (120, 104), "Dojo": (424, 72), "Gym": (552, 72),
         "Pidgey house": (216, 200), "Mart": (408, 200), "Silph Co.": (296, 360),
         "Centre": (152, 488), "Mr. Psychic's": (472, 488)}
START = "Saffron"


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
    if s <= PATH_T | MARK_T | LAWN_T and s & (PATH_T | MARK_T):
        return "V"
    if s <= LAWN_T | {3} and 3 in s:
        return "F"
    return "."


def paint(world):
    H, W = world.ch * 16, world.cw * 16
    X, Z = np.meshgrid(np.arange(W) + 0.5, np.arange(H) + 0.5)
    XI, ZI = np.floor(X).astype(np.int64), np.floor(Z).astype(np.int64)
    ground = world.px("VLSNWF")
    claimed = world.px("VL")
    r1, r2, r3 = h01(XI, ZI, 201), h01(XI, ZI, 202), h01(XI, ZI, 203)

    # ---- the drawing, a quarter (one tile) at a time
    qh, qw = world.ch * 2, world.cw * 2
    qt = np.full((qh, qw), -1)
    for (mid, cx, cy), p in world.tiles.items():
        if world.kind[cy, cx] not in "VL":
            continue
        for q, (oz, ox) in enumerate(((0, 0), (0, 1), (1, 0), (1, 1))):
            qt[cy * 2 + oz, cx * 2 + ox] = p[q]
    # the carriageway: the plain quarters reached from the ring without
    # crossing a kerb line
    walk = qt == 35
    road_q = np.zeros((qh, qw), bool)
    todo = [(13, 20)]
    road_q[13, 20] = True
    while todo:
        r, c = todo.pop()
        for nr, nc in ((r + 1, c), (r - 1, c), (r, c + 1), (r, c - 1)):
            if 0 <= nr < qh and 0 <= nc < qw and walk[nr, nc] and not road_q[nr, nc]:
                road_q[nr, nc] = True
                todo.append((nr, nc))
    up8 = lambda a: np.kron(a, np.ones((8, 8), bool))       # noqa: E731
    road = up8(road_q) & claimed
    kerb_q = np.isin(qt, [16, 32, 33])
    plaza = up8(qt == 91) & claimed
    lawn = up8(np.isin(qt, [44, 48])) & claimed
    kerb = up8(kerb_q) & claimed
    walkway = claimed & ~road & ~plaza & ~lawn & ~kerb

    tex = np.zeros((H, W, 3), np.uint8)

    def put(mask, rgb):
        tex[mask] = rgb

    def tones(mask, palette, pick):
        idx = np.floor(np.asarray(pick) * len(palette)).astype(int) % len(palette)
        for k, rgb in enumerate(palette):
            put(mask & (idx == k), rgb)

    grows = np.full((H, W), ".", dtype="<U1")
    free = ground & ~world.px("SN")

    def grow(mask, letter):
        grows[mask & (grows == ".") & free] = letter

    # ---- the carriageway: asphalt, the gold line down its middle
    tones(road, ASPHALT, vnoise(X, Z, 3, 211) * 0.4 + r1 * 0.6)
    put(road & (r2 < 0.03), (98, 100, 108))
    kmask = kerb
    dl, dr = side_dist(kmask, False), side_dist(kmask, True)
    du, dd = side_dist(kmask.T, False).T, side_dist(kmask.T, True).T
    span_x, span_z = dl + dr, du + dd
    ew = span_z <= span_x                                    # the road runs along x where it is narrow in z
    centre = road & np.where(ew, np.abs(du - dd) <= 1, np.abs(dl - dr) <= 1) & (np.minimum(span_x, span_z) <= 22)
    dash = np.where(ew, (XI // 6) % 2 == 0, (ZI // 6) % 2 == 0)
    put(centre & dash, GOLD_LINE)
    # white bars where a way out crosses: road within reach of an unkerbed walkway
    open_edge = np.zeros((H, W), bool)
    for dz, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        open_edge |= np.roll(walkway, (dz, dx), (0, 1))
    seeds = road & open_edge                                  # asphalt a walkway meets with no kerb between
    near = np.zeros((H, W), bool)
    for dz in range(-10, 11):
        near |= np.roll(seeds, dz, 0)
    near2 = np.zeros((H, W), bool)
    for dx in range(-10, 11):
        near2 |= np.roll(near, dx, 1)
    crossing = road & near2
    bars = np.where(ew, (XI // 2) % 2 == 0, (ZI // 2) % 2 == 0)
    put(crossing & bars & ~centre, ZEBRA)

    # ---- the kerbs: granite, a raised edge along the drawn line, bollards
    tones(kerb, GRANITE, h01(XI // 6, ZI // 6, 212))
    lx, lz = XI % 8, ZI % 8
    m16, m32, m33 = up8(qt == 16), up8(qt == 32), up8(qt == 33)
    edge_up = (m16 & ((lx == 3) | (lx == 4))) | (m32 & ((lz == 3) | (lz == 4)))
    post = m33 & ((lx - 3.5) ** 2 + (lz - 3.5) ** 2 <= 5)
    grow(edge_up, "k")
    grow(post, "B")
    put(post, IRON[0])

    # ---- the sidewalks: cream terrazzo slabs, brass in the joints
    sx, sz = XI % 16, ZI % 16
    tones(walkway, TERRAZZO, h01(XI // 16, ZI // 16, 213))
    put(walkway & (r2 < 0.12), TERR_SPECK[0])
    put(walkway & (r3 < 0.05), TERR_SPECK[1])
    put(walkway & ((sx == 0) | (sz == 0)), BRASS)

    # ---- the plazas: Deco panels -- a saffron diamond in each, charcoal rim
    px_, pz_ = XI % 32 - 15.5, ZI % 32 - 15.5
    dia = np.abs(px_) + np.abs(pz_)
    tones(plaza, TERRAZZO, h01(XI // 32, ZI // 32, 214))
    put(plaza & (r2 < 0.10), TERR_SPECK[2])
    put(plaza & (dia < 11), SAFFRON[0])
    put(plaza & (dia < 7), CREAM)
    put(plaza & (dia < 3), SAFFRON[1])
    put(plaza & (np.abs(dia - 11) < 0.8), BRASS)
    put(plaza & ((XI % 32 == 0) | (ZI % 32 == 0)), CHARCOAL[0])
    put(plaza & ((XI % 32 == 1) | (ZI % 32 == 1)), BRASS)
    # the medallion before Silph Co.: nested diamonds, gold on charcoal
    mx, mz, mr = MEDALLION
    md = np.abs(X - mx) + np.abs(Z - mz)
    med = (walkway | plaza | road) & (md < mr + 2)
    ring_i = np.floor(md / 3).astype(int)
    put(med, CHARCOAL[1])
    put(med & (ring_i % 2 == 1), SAFFRON[0])
    put(med & (ring_i == 0), CREAM)
    put(med & (np.abs(md - (mr + 1.2)) < 0.8), BRASS)

    # ---- the lawns: clipped, marigolds along the walks
    turf = lawn | world.px("SNF")
    f = vnoise(X, Z, 7, 221) * 0.6 + (r1 - 0.5) * 0.2
    put(turf, S_GRASS[0])
    put(turf & (f < 0.38), S_GRASS[3])
    put(turf & (f > 0.58), S_GRASS[2])
    put(turf & (((XI + ZI) // 8) % 2 == 0) & (f > 0.3), S_GRASS[1])     # mown in stripes
    beside = np.zeros((H, W), bool)
    for dz, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        beside |= np.roll(turf, (dz, dx), (0, 1)) != turf
    put(turf & beside, EDGE_D)
    band = turf & ~beside
    near_walk = np.zeros((H, W), bool)
    for dz, dx in ((0, 2), (0, -2), (2, 0), (-2, 0)):
        near_walk |= np.roll(walkway | kerb | plaza, (dz, dx), (0, 1))
    bloom = h01(XI, ZI, 222)
    grow(band & near_walk & (bloom < 0.06), "M")
    grow(band & near_walk & (bloom < 0.10), "m")
    grow(band & (bloom > 0.996), "g")
    # the street trees: an iron grate with a gold rim round each trunk
    # (only a tree that stands in the paving: the town's wall of trees keeps its grass)
    wood = world.px("W")
    paving = walkway | plaza | kerb | road
    near_pav = np.zeros((H, W), bool)
    for dz, dx in ((0, 16), (0, -16), (16, 0), (-16, 0)):
        near_pav |= np.roll(paving, (dz, dx), (0, 1))
    street_tree = wood & np.kron(np.array([[np.any(near_pav[r * 16:r * 16 + 16, c * 16:c * 16 + 16])
                                             for c in range(world.cw)] for r in range(world.ch)]),
                                 np.ones((16, 16), bool))
    wild_tree = wood & ~street_tree
    put(wild_tree, S_GRASS[3])
    put(wild_tree & (r1 < 0.3), (96, 84, 62))
    wood = street_tree
    gx, gz = XI % 16, ZI % 16
    grate = wood & (gx >= 1) & (gx <= 14) & (gz >= 1) & (gz <= 14)
    put(wood, TERRAZZO[1])
    put(grate, IRON[1])
    put(grate & (((gx + gz) % 3) != 0), IRON[0])
    put(wood & ((gx == 1) | (gx == 14) | (gz == 1) | (gz == 14)) & grate, BRASS)

    base = turf | wild_tree
    return ground, claimed, tex, base, grows


vg.MAPS = MAPS
vg.TOWN, vg.PREFIX, vg.START, vg.BUDGET, vg.WALK = TOWN, "saffground", START, 90000, 1
vg.GROWS, vg.REACH, vg.kind_of, vg.paint = GROWS, REACH, kind_of, paint

if __name__ == "__main__":
    if "--write" in sys.argv:
        vg.write()
    vg.check()
