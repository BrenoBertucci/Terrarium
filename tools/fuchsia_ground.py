"""The ground of Fuchsia City and Routes 15 and 18: a plan, its data, a check.

  python tools/fuchsia_ground.py --write   paint assets/buildings/fuchground_<MAP>.png,
                                           write data/fuchground_<MAP>.lua + the index
  python tools/fuchsia_ground.py           check the REAL kit against the REAL maps

The seventh painted world: Fuchsia City with the road east (Route 15) and the
road west (Route 18) on one canvas. Stood by lib/LavenderGroundKit.lua,
written and checked by tools/vermilion_ground.py.

"Behold! It's Passion Pink!" -- the town of the ninja Gym and the Safari Zone.
The drawing decides where (its paths are paved, its lawns -- the green-and-
white checker, which is grass -- are lawn, its flowers stand); the town decides
what, as a garden would:

  the paths     raked gravel, faintly pink, the rake's lines running along each
                path, and STEPPING STONES set in it the way a garden sets them
  the lawns     deep green with fallen blossom in it, azaleas along the walks,
                and under every tree a carpet of PINK PETALS
  the Safari    the brick way down from the Safari Zone's gate is a timber
  way           BOARDWALK, planks across, nail heads, the gaps between
  the ponds     smooth river stones along the edge
  the routes    their brick roads in pink granite setts, their paths the same
                gravel, raked loose

Nothing here is extracted from the ROM. The tiles only decided where.
"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vermilion_ground as vg  # noqa: E402
from cerulean_ground import spans  # noqa: E402
from lavender_ground import box_blur, h01, vnoise  # noqa: E402

TOWN = "FUCHSIA_CITY"
# Route 15 joins the east edge four blocks down, Route 18 the west
MAPS = [(TOWN, 0, 0), ("ROUTE_15", 40, 8), ("ROUTE_18", -50, 8)]
TOWN_W, TOWN_H = 640, 576
PATH_T = {35, 57}
BRICK_T = {91}
MARK_T = {16, 32, 33}
LAWN_T = {44, 48}

GRAVEL = [(236, 222, 216), (228, 214, 208), (242, 230, 224), (222, 208, 204)]
RAKE = (212, 196, 192)
STONE = [(170, 164, 168), (158, 152, 158), (182, 174, 176)]
STONE_RIM = (128, 122, 130)
PLANK = [(150, 104, 72), (140, 96, 66), (160, 112, 78)]
PLANK_GAP = (78, 56, 44)
NAIL = (200, 196, 190)
SETT = [(214, 172, 176), (204, 162, 168), (222, 182, 184), (196, 156, 164)]
SETT_JOINT = (150, 118, 126)
PEBBLE = [(196, 194, 196), (178, 176, 182), (210, 206, 206)]
F_GRASS = [(84, 158, 82), (72, 146, 76), (100, 172, 90), (62, 134, 70)]
PETAL = [(250, 190, 214), (244, 170, 200), (252, 212, 226)]
SOIL = [(106, 84, 72), (94, 76, 66)]
EDGE_D = (52, 112, 62)

GROWS = {
    "g": {"top": [(132, 198, 104), (116, 186, 98)], "stem": [(84, 158, 82)]},
    "a": {"top": [(240, 110, 170), (250, 140, 190), (226, 90, 150)], "stem": [(70, 130, 70)]},   # azalea
    "w": {"top": [(252, 250, 250)], "stem": [(84, 158, 82)]},                                    # a white one among them
    "p": {"top": [(208, 204, 206), (190, 188, 192)], "stem": [(170, 168, 174)]},                 # a pebble
}

REACH = {"Fuchsia": (312, 456), "Fuchsia north": (296, 72), "Mart": (88, 232), "Bill's grandpa": (184, 456), "Centre": (312, 456),
         "Warden": (440, 456), "Safari Zone": (296, 72), "Gym": (88, 456), "meeting room": (360, 232),
         "Good Rod house": (504, 456)}
START = ["Fuchsia", "Fuchsia north"]           # the south terrace is walled by ledges: one start each side


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
    if s <= PATH_T | BRICK_T | MARK_T | LAWN_T and s & (PATH_T | BRICK_T | MARK_T):
        return "V"
    if s == {82}:
        return "G"
    if s <= LAWN_T | {3} and 3 in s:
        return "F"
    if s <= vg.SHORE_T | {vg.SEA_T} and s & vg.SHORE_T:
        return "Q"
    return "."


def paint(world):
    H, W = world.ch * 16, world.cw * 16
    X, Z = np.meshgrid(np.arange(W) + 0.5 + world.cx0 * 16, np.arange(H) + 0.5 + world.cy0 * 16)
    XI, ZI = np.floor(X).astype(np.int64), np.floor(Z).astype(np.int64)
    ground = world.px("VLSNWGF") | world.land
    claimed = world.px("VL")
    away = np.hypot(np.maximum(0, np.maximum(-X, X - TOWN_W)), np.maximum(0, np.maximum(-Z, Z - TOWN_H)))
    town = away == 0
    r1, r2, r3 = h01(XI, ZI, 301), h01(XI, ZI, 302), h01(XI, ZI, 303)

    origin = {mid: (gx - world.cx0, gy - world.cy0) for mid, gx, gy, *_ in world.maps}
    qlawn = np.zeros((H, W), bool)
    qbrick = np.zeros((H, W), bool)
    qpath = np.zeros((H, W), bool)
    street_c = np.zeros((world.ch, world.cw), bool)
    for (mid, cx, cy), p in world.tiles.items():
        r, c = origin[mid][1] + cy, origin[mid][0] + cx
        if world.kind[r, c] != "V":
            continue
        street_c[r, c] = True
        for q, (oz, ox) in enumerate(((0, 0), (0, 8), (8, 0), (8, 8))):
            sl = (slice(r * 16 + oz, r * 16 + oz + 8), slice(c * 16 + ox, c * 16 + ox + 8))
            t = p[q]
            (qlawn if t in LAWN_T else qbrick if t in BRICK_T else qpath)[sl] = True

    lawnish = world.px("L") | qlawn | world.px("SNWGF")
    pav0 = (qpath | qbrick) & claimed
    field = box_blur(box_blur(pav0.astype(float), 3), 3)
    room = box_blur(box_blur((pav0 | (lawnish & claimed)).astype(float), 3), 3)
    paved = claimed & ((field / np.maximum(room, 1e-6)) > 0.5)
    paved |= pav0 & ~lawnish
    board = paved & qbrick & town                             # the Safari way
    setts = paved & qbrick & ~town                            # a route's brick road
    gravel = paved & ~qbrick
    lawn = claimed & ~paved
    wood = world.px("W")
    turf = lawn | world.px("SNGF") | wood

    r0_, rl, c0_, cl = spans(street_c)
    ext = lambda a: np.kron(a, np.ones((16, 16), int))      # noqa: E731
    ew = ext((cl >= rl).astype(int)).astype(bool)

    tex = np.zeros((H, W, 3), np.uint8)

    def put(mask, rgb):
        tex[mask] = rgb

    def tones(mask, palette, pick):
        idx = np.floor(np.asarray(pick) * len(palette)).astype(int) % len(palette)
        for k, rgb in enumerate(palette):
            put(mask & (idx == k), rgb)

    grows = np.full((H, W), ".", dtype="<U1")
    free = ground & ~world.flower & ~world.px("SNG")

    def grow(mask, letter):
        grows[mask & (grows == ".") & free] = letter

    # ---- raked gravel, the lines running along the path
    tones(gravel, GRAVEL, vnoise(X, Z, 3, 311) * 0.5 + r1 * 0.5)
    across = np.where(ew, ZI, XI)
    wav = (vnoise(X, Z, 14, 312) - 0.5) * 3
    rake = gravel & (((across + np.floor(wav).astype(int)) % 3) == 0)
    put(rake & (r2 < 0.85), RAKE)
    put(gravel & (r3 < 0.02), PEBBLE[1])
    # stepping stones: a stone in each cell of a jittered grid, flat and wide
    SP = 9
    gi, gj = np.floor(X / SP), np.floor(Z / SP)
    scx = (gi + 0.5 + (h01(gi.astype(np.int64), gj.astype(np.int64), 313) - 0.5) * 0.3) * SP
    scz = (gj + 0.5 + (h01(gi.astype(np.int64), gj.astype(np.int64), 314) - 0.5) * 0.3) * SP
    srx = 2.6 + h01(gi.astype(np.int64), gj.astype(np.int64), 315) * 0.9
    sd = np.hypot((X - scx) / srx, (Z - scz) / (srx * 0.85))
    keep = h01(gi.astype(np.int64), gj.astype(np.int64), 316) < np.where(town, 0.75, 0.35)
    stone = gravel & keep & (sd < 1)
    tones(stone, STONE, h01(gi.astype(np.int64), gj.astype(np.int64), 317))
    put(stone & (sd > 0.78), STONE_RIM)

    # ---- the boardwalk: planks across the way, the gaps between, nail heads
    along = np.where(ew, XI, ZI)
    cross = np.where(ew, ZI, XI)
    pk = along // 3
    tones(board, PLANK, h01(pk, cross // 16, 318))
    put(board & ((along % 3) == 0), PLANK_GAP)
    put(board & ((along % 3) == 1) & ((cross % 8) == 2), NAIL)
    put(board & (h01(pk, cross // 16, 319) < 0.08) & ((along % 3) != 0), PLANK[1])
    # ---- a route's brick road: pink granite setts in running bond
    srow = ZI // 4
    sx = XI + (srow % 2) * 2
    tones(setts, SETT, h01(sx // 4, srow, 320))
    put(setts & (((ZI % 4) == 0) | ((sx % 4) == 0)), SETT_JOINT)

    # ---- the lawns, blossom in them; a carpet of petals under the trees
    f = vnoise(X, Z, 7, 321) * 0.6 + (r1 - 0.5) * 0.2
    put(turf, F_GRASS[0])
    put(turf & (f < 0.38), F_GRASS[3])
    put(turf & (f > 0.58), F_GRASS[2])
    put(turf & (r2 < 0.08), F_GRASS[1])
    beside = np.zeros((H, W), bool)
    for dz, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        beside |= np.roll(turf, (dz, dx), (0, 1)) != turf
    put(turf & beside, EDGE_D)
    # petals: thick under a tree and thinning out from it, a scatter on the lawns
    under = box_blur(box_blur(wood.astype(float), 6), 6)
    petal = turf & (r3 < 0.025 + under * 0.45 * (vnoise(X, Z, 4, 322) + 0.4))
    tones(petal, PETAL, r1)
    tones(wood & (r2 < 0.12), SOIL, r1)
    # the pond's edge: smooth stones
    ds = vg.reach_of(world.sea, 6)
    bank = turf & ~wood & (ds <= 2)
    tones(bank, PEBBLE, h01(XI // 2, ZI // 2, 323))
    tones(world.land, PEBBLE, h01(XI // 2, ZI // 2, 324))

    base = turf | bank | world.land

    # ---- what grows: azaleas along the walks, tufts
    meadow = turf & ~wood & ~bank & ~beside
    near_pave = np.zeros((H, W), bool)
    for dz, dx in ((0, 2), (0, -2), (2, 0), (-2, 0)):
        near_pave |= np.roll(paved, (dz, dx), (0, 1))
    bloom = h01(XI, ZI, 331)
    grow(meadow & near_pave & town & (bloom < 0.016), "A")
    grow(meadow & near_pave & town & (bloom > 0.997), "W")
    for n, (dz, dx) in enumerate(((0, 1), (0, -1), (1, 0), (-1, 0))):
        nb = np.roll(grows, (dz, dx), (0, 1))
        grow((nb == "A") & meadow & (h01(XI, ZI, 332 + n) < 0.65), "a")
    tuft = h01(XI, ZI, 341)
    crown = meadow & ((near_pave & (tuft < np.where(town, 0.012, 0.005))) | (tuft < 0.0022))
    grow(crown & (h01(XI, ZI, 342) < 0.5), "G")
    grow(crown, "g")
    for n, (dz, dx) in enumerate(((0, 1), (0, -1), (1, 0), (-1, 0))):
        grow(np.roll(crown, (dz, dx), (0, 1)) & meadow & (h01(XI, ZI, 343 + n) < 0.45), "g")
    grow(bank & (h01(XI, ZI, 347) < 0.04), "p")
    return ground, claimed, tex, base, grows


vg.MAPS = MAPS
vg.TOWN, vg.PREFIX, vg.START, vg.BUDGET, vg.WALK = TOWN, "fuchground", START, 140000, 1
vg.GROWS, vg.REACH, vg.kind_of, vg.paint = GROWS, REACH, kind_of, paint

if __name__ == "__main__":
    if "--write" in sys.argv:
        vg.write()
    vg.check()
