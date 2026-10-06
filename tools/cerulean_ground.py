"""The ground of Cerulean City and the four roads out of it: a plan, its data, a check.

  python tools/cerulean_ground.py --write   paint assets/buildings/cerground_<MAP>.png,
                                            write data/cerground_<MAP>.lua + the index
  python tools/cerulean_ground.py           check the REAL kit against the REAL maps,
                                            count quads, render tools/_kit_out/cerground_world.png

The fourth painted world (Lavender's, Vermilion's, Celadon's, this), stood by the
same kit (lib/LavenderGroundKit.lua) and written and checked by
tools/vermilion_ground.py's own write() and check().

Cerulean is the WATER town -- the river under Nugget Bridge, the cape, the Gym's
pool, "a mysterious blue aura" -- and a town of flowers and lawns. The drawing
decides WHERE everything is, cell for cell: its paths ($23 plain, $39 dotted:
a checker nobody should see, so it is one surface) are paved, its lawns ($2C)
are lawn -- the green is grass -- its flower beds keep their flowers, the brick
yards ($5B) behind the north houses stay yards. What each of them IS:

  the streets  a mosaic of white river pebbles, and down the middle of every
               street a RIVER in blue pebbles: a deep channel meandering
               between paler banks, a glint on it here and there; a border of
               slate-blue pebbles along each edge. Corners rounded, not cut.
  the squares  ripples: rings of blue pebble spreading out from the Gym's door,
               the Centre's and the Mart's, like a stone dropped in the pool
  the yards    glazed tiles, white and cerulean (a flower in each, a ring where
               four meet), a chipped one here and there, moss in the joints,
               potted plants in the corners
  the lawns    lush turf a voxel proud of the stone, clover, daisies,
               forget-me-nots; at the water a stone kerb, reeds and blue iris
  the lanes    the bike lanes out to Route 5: blue-grey asphalt, a dashed
               white line, a raised white kerb, bollards
  foot-worn    where the drawing makes you cross grass -- off Nugget Bridge,
               to the burgled house, to Melanie's, out to Route 9 -- a trodden
               earth path
  the routes   the same pebbles loose as gravel, the edges eaten by grass, a
               wilder meadow, drier up the mountain roads (4 and 9)

Nothing here is extracted from the ROM. The tiles only decided where.
Kinds: V town paving (claimed), L lawn (claimed), P a route's road (claimed),
F flowers / G tall grass / S sign / N fence / W tree / Q shore: laid, NOT claimed.
"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vermilion_ground as vg  # noqa: E402
from lavender_ground import box_blur, h01, vnoise  # noqa: E402

TOWN = "CERULEAN_CITY"
# world cell origins, off the connections (in BLOCKS, two cells each): Route 24
# joins the north edge and Route 5 the south five blocks in, Route 4 the west
# and Route 9 the east four blocks down
MAPS = [(TOWN, 0, 0), ("ROUTE_24", 10, -36), ("ROUTE_5", 10, 36), ("ROUTE_4", -90, 8), ("ROUTE_9", 40, 8)]
TOWN_W, TOWN_H = 640, 576
PATH_T = {35, 57}
MARK_T = {16, 32, 33}
BRICK_T = {91}
LAWN_T = {44, 48}

# ------------------------------------------------------------- the palette --
# (lifted for what the light takes away: stone shows at about x0.69, turf x0.85)
PEBBLE = [(248, 246, 238), (240, 238, 230), (252, 250, 244), (234, 232, 226), (244, 240, 228), (236, 238, 238)]
PEB_JOINT = (204, 208, 214)
WAVE_DEEP = [(52, 100, 184), (60, 110, 196), (46, 90, 172)]
WAVE_MID = [(98, 150, 222), (110, 160, 230), (90, 140, 214)]
RIM = [(120, 140, 170), (132, 152, 182), (112, 130, 160)]
RIPPLE = [(70, 128, 210), (132, 184, 240), (206, 230, 252)]
GLAZE_W = [(250, 252, 254), (244, 248, 252), (252, 252, 248)]
GLAZE_B = (40, 92, 190)
GLAZE_L = (122, 172, 236)
GROUT = (196, 202, 210)
LANE = [(96, 112, 140), (104, 120, 148), (90, 106, 134)]
LANE_LINE = (240, 244, 250)
EARTH = [(190, 158, 118), (178, 146, 108), (200, 170, 130)]
GRAVEL = [(226, 220, 206), (216, 210, 198), (232, 228, 216), (208, 204, 196)]
COPING = [(176, 184, 196), (164, 172, 186), (186, 192, 202)]
G_D, G_M, G_L = (58, 118, 70), (92, 164, 86), (128, 194, 102)
G_SUN, G_SHADE, CLOVER = (150, 206, 112), (74, 142, 80), (66, 136, 96)
G_DRY = (170, 186, 104)
SOIL = [(104, 84, 64), (92, 74, 58), (116, 92, 70)]
LITTER = [(154, 112, 62), (172, 124, 60), (126, 98, 56), (110, 132, 70)]

GROWS = {
    "g": {"top": [G_SUN, G_L], "stem": [G_M, G_SHADE]},
    "d": {"top": [(252, 252, 246)], "stem": [G_M]},                                    # daisy
    "b": {"top": [(100, 146, 240), (122, 166, 248), (86, 120, 226)], "stem": [G_M]},  # forget-me-not, cornflower
    "y": {"top": [(250, 220, 84)], "stem": [G_M]},                                    # buttercup
    "i": {"top": [(108, 96, 222), (130, 118, 238)], "stem": [(84, 146, 84)]},          # blue iris
    "r": {"top": [(116, 84, 52), (130, 94, 58)], "stem": [(122, 150, 72), (106, 138, 66)]},  # reed, its cattail
    "f": {"top": [(112, 172, 82), (96, 160, 74)], "stem": [(66, 118, 60)]},            # fern
    "k": {"top": [(246, 248, 250)], "stem": [(214, 218, 226)]},                        # the lane's kerb
    "p": {"top": [(96, 170, 80), (124, 192, 92), (240, 150, 180)], "stem": [(196, 112, 78), (180, 100, 70)]},  # a pot
    "s": {"top": [(204, 208, 214), (190, 194, 202)], "stem": [(172, 176, 184)]},       # a stone
}

# --------------------------------------------------------- the town's plan --
# World voxels, x east, z south (Cerulean's own corner at 0, 0).
# Ripples: the squares before the Gym, the Centre, the Mart and the Bike Shop,
# and where the road off Nugget Bridge comes into town.
RIPPLES = [(488, 336, 15), (312, 304, 14), (408, 432, 13), (216, 432, 13), (344, 176, 14)]
# the ways worn across grass the drawing makes you walk: (width, points)
FOOT = [
    (7, [(344, 58), (340, 100), (346, 140), (344, 170)]),          # off Nugget Bridge, down to the street
    (6, [(440, 200), (424, 204), (408, 202)]),                     # to the burgled house's door
    (6, [(216, 262), (212, 280), (216, 296)]),                     # to Melanie's door
    (7, [(598, 276), (630, 266), (680, 263), (716, 264)]),       # out east, to the bush Route 9 is shut by
]
REACH = {"Route 4": (6, 296), "Route 9 (the cut bush)": (714, 264), "Nugget Bridge": (344, 60),
         "Route 5": (216, 600), "Badge house": (152, 200),
         "burgled house": (440, 200), "Melanie's": (216, 264), "Centre": (312, 296),
         "Gym": (488, 328), "Bike Shop": (216, 424), "Mart": (408, 424)}
START = "Route 4"


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
    if s <= PATH_T | MARK_T | BRICK_T | LAWN_T and s & (PATH_T | MARK_T | BRICK_T):
        return "V" if town else "P"
    if s == {82}:
        return "G"
    if s <= LAWN_T | {3} and 3 in s:
        return "F"
    if s <= vg.SHORE_T | {vg.SEA_T} and s & vg.SHORE_T:
        return "Q"
    return "."


def seg_d(X, Z, pts):
    d = np.full(X.shape, 1e9)
    for (ax, az), (bx, bz) in zip(pts, pts[1:]):
        dx, dz = bx - ax, bz - az
        t = np.clip(((X - ax) * dx + (Z - az) * dz) / (dx * dx + dz * dz), 0, 1)
        d = np.minimum(d, np.hypot(X - (ax + t * dx), Z - (az + t * dz)))
    return d


def pebbles(X, Z, size, seed):
    """A mosaic of stones: each voxel's stone (its id and centre) and whether it is a joint."""
    gx, gz = np.floor(X / size).astype(np.int64), np.floor(Z / size).astype(np.int64)
    d1 = np.full(X.shape, 1e9)
    d2 = np.full(X.shape, 1e9)
    cx = np.zeros(X.shape)
    cz = np.zeros(X.shape)
    sid = np.zeros(X.shape, np.int64)
    for oz in (-1, 0, 1):
        for ox in (-1, 0, 1):
            ix, iz = gx + ox, gz + oz
            sx = (ix + 0.18 + 0.64 * h01(ix, iz, seed)) * size
            sz = (iz + 0.18 + 0.64 * h01(ix, iz, seed + 1)) * size
            d = (X - sx) ** 2 + (Z - sz) ** 2
            nearer = d < d1
            d2 = np.where(nearer, d1, np.minimum(d2, d))
            d1 = np.where(nearer, d, d1)
            cx = np.where(nearer, sx, cx)
            cz = np.where(nearer, sz, cz)
            sid = np.where(nearer, ix * 7919 + iz * 104729, sid)
    joint = np.sqrt(d2) - np.sqrt(d1) < 0.62
    return sid, cx, cz, joint


def spans(cells):
    """For each True cell: the run it belongs to along each axis -- (start, length)."""
    h, w = cells.shape
    r0 = np.zeros((h, w), int)
    rl = np.zeros((h, w), int)
    c0 = np.zeros((h, w), int)
    cl = np.zeros((h, w), int)
    for r in range(h):
        c = 0
        while c < w:
            if cells[r, c]:
                e = c
                while e < w and cells[r, e]:
                    e += 1
                c0[r, c:e], cl[r, c:e] = c, e - c
                c = e
            else:
                c += 1
    for c in range(w):
        r = 0
        while r < h:
            if cells[r, c]:
                e = r
                while e < h and cells[e, c]:
                    e += 1
                r0[r:e, c], rl[r:e, c] = r, e - r
                r = e
            else:
                r += 1
    return r0, rl, c0, cl


def side_dist(mask, reverse):
    """Along x: voxels since the last True of `mask` (to the left, or right if reverse)."""
    H, W = mask.shape
    idx = np.arange(W)[None, :].repeat(H, 0)
    m = mask[:, ::-1] if reverse else mask
    last = np.where(m, idx, -10 ** 6)
    last = np.maximum.accumulate(last, axis=1)
    d = idx - last
    return d[:, ::-1] if reverse else d


def paint(world):
    H, W = world.ch * 16, world.cw * 16
    X, Z = np.meshgrid(np.arange(W) + 0.5 + world.cx0 * 16, np.arange(H) + 0.5 + world.cy0 * 16)
    XI, ZI = np.floor(X).astype(np.int64), np.floor(Z).astype(np.int64)
    ground = world.px("VLPSNWGF") | world.land
    claimed = world.px("VLP")
    away = np.hypot(np.maximum(0, np.maximum(-X, X - TOWN_W)), np.maximum(0, np.maximum(-Z, Z - TOWN_H)))
    town = away == 0
    rough = np.clip(away / 64, 0, 1)
    r1, r2, r3 = h01(XI, ZI, 21), h01(XI, ZI, 22), h01(XI, ZI, 23)

    # ---- what each quarter of a paved cell was drawn as
    origin = {mid: (gx - world.cx0, gy - world.cy0) for mid, gx, gy, *_ in world.maps}
    qlawn = np.zeros((H, W), bool)
    qbrick = np.zeros((H, W), bool)
    qpath = np.zeros((H, W), bool)
    street_c = np.zeros((world.ch, world.cw), bool)       # cells of plain path, for the waves
    for (mid, cx, cy), p in world.tiles.items():
        r, c = origin[mid][1] + cy, origin[mid][0] + cx
        if world.kind[r, c] not in "VP":
            continue
        if set(p) <= PATH_T:
            street_c[r, c] = True
        for q, (oz, ox) in enumerate(((0, 0), (0, 8), (8, 0), (8, 8))):
            sl = (slice(r * 16 + oz, r * 16 + oz + 8), slice(c * 16 + ox, c * 16 + ox + 8))
            t = p[q]
            (qlawn if t in LAWN_T else qbrick if t in BRICK_T else qpath)[sl] = True

    # ---- the paving, its corners rounded: the drawn path mask, blurred and
    # normalised by the ground there is (a building's foot does not eat it)
    marks = world.mark[16] | world.mark[32] | world.mark[33]
    lawnish = world.px("L") | qlawn | world.px("SNWGF")
    pav0 = (qpath | qbrick) & claimed
    field = box_blur(box_blur(pav0.astype(float), 3), 3)
    room = box_blur(box_blur((pav0 | (lawnish & claimed)).astype(float), 3), 3)
    paved = claimed & ((field / np.maximum(room, 1e-6)) > 0.5)
    paved |= pav0 & ~(lawnish)                              # never lose drawn paving to the blur
    brick = paved & qbrick
    near_marks_x = (side_dist(marks, False) <= 17) & (side_dist(marks, True) <= 17)
    zmark = np.zeros((H, W), bool)
    for dz in range(-2, 3):
        zmark |= np.roll(marks, dz, 0)
    lane = paved & ~brick & ((marks | (near_marks_x & zmark)))
    street = paved & ~brick & ~lane

    # ---- trodden paths across the grass (the town's only)
    foot = np.zeros((H, W), bool)
    for width, pts in FOOT:
        d = seg_d(X, Z, pts) - width / 2 + (vnoise(X, Z, 5, 81) - 0.5) * 2.4
        foot |= d < 0
    foot &= claimed & ~paved
    lawn = claimed & ~paved & ~foot                          # every other claimed voxel is grass
    ds = vg.reach_of(world.sea, 12)                          # voxels to the water
    tex = np.zeros((H, W, 3), np.uint8)

    def put(mask, rgb):
        tex[mask] = rgb

    def tones(mask, palette, pick):
        idx = np.floor(np.asarray(pick) * len(palette)).astype(int) % len(palette)
        for k, rgb in enumerate(palette):
            put(mask & (idx == k), rgb)

    # ---- the pebbles, under everything paved
    sid, pcx, pcz, joint = pebbles(X, Z, 2.7, 91)
    tone = h01(sid, 0, 92)
    in_town = street & town
    tones(in_town, PEBBLE, tone)
    # the wave: the street's own axis, off its run of cells
    r0, rl, c0, cl = spans(street_c)
    ew_c = cl >= rl
    ext = lambda a: np.kron(a, np.ones((16, 16), int))      # noqa: E731
    ew = ext(ew_c.astype(int)).astype(bool)
    zc = (ext(r0) * 16 + ext(rl) * 8) + world.cy0 * 16
    xc = (ext(c0) * 16 + ext(cl) * 8) + world.cx0 * 16
    half = np.where(ew, ext(rl), ext(cl)) * 8
    along = np.where(ew, pcx, pcz)
    cross = np.where(ew, pcz - zc, pcx - xc)
    # a river down the middle of every street: a deep-blue channel meandering
    # between paler banks, a glint of light on it now and then. (A braid of two
    # thin lines was tried first: at the game's distance it read as scribble.)
    amp, lam = 6.0, 72.0
    w = amp * np.sin(2 * np.pi * along / lam)
    wide = half >= 14
    off = np.abs(cross - w)
    channel = wide & (off < 1.7)
    banks = wide & (off < 3.1) & ~channel
    line = channel | banks
    rim = np.abs(cross) > half - 3.2
    tones(in_town & banks, WAVE_MID, tone)
    tones(in_town & channel, WAVE_DEEP, tone)
    put(in_town & channel & (h01(sid, 2, 93) < 0.08), RIPPLE[2])        # a glint
    tones(in_town & rim & ~line, RIM, tone)
    # the ripples: three rings spreading from each door, deep to pale
    for x0, z0, R in RIPPLES:
        rr = np.hypot(pcx - x0, pcz - z0)
        m = in_town & (rr < R)
        band = np.floor(rr / 4.4).astype(int)
        for b in range(4):
            put(m & (band == b) & (b % 2 == 0), RIPPLE[b // 2])
            put(m & (band == b) & (b % 2 == 1), PEBBLE[2])
        put(m & (rr < 2.0), RIPPLE[0])
    put(in_town & joint, PEB_JOINT)

    # a route's road: the same stones, loose, and fewer
    road = street & ~town
    tones(road, GRAVEL, vnoise(X, Z, 3, 83) * 0.5 + r1 * 0.5)
    stone = road & ~joint & (h01(sid, 1, 84) < 0.30)
    tones(stone, PEBBLE[:4] + [RIM[1]], tone)
    put(road & joint & (r2 < 0.4), GRAVEL[3])

    # ---- the yards: glazed tiles, a flower in each and a ring where four meet
    u, v = XI % 8, ZI % 8
    tile_joint = (u == 0) | (v == 0)
    du, dv = u - 4, v - 4
    corner = np.minimum(np.minimum(u, 8 - u) ** 2 + np.minimum(v, 8 - v) ** 2, 99) <= 5.2
    centre = np.abs(du) + np.abs(dv) <= 1
    petal = ((np.abs(du) <= 1) & (np.abs(dv) >= 2) & (np.abs(dv) <= 3)) | ((np.abs(dv) <= 1) & (np.abs(du) >= 2) & (np.abs(du) <= 3))
    tid = h01(XI // 8, ZI // 8, 85)
    tones(brick, GLAZE_W, tid)
    put(brick & petal, GLAZE_L)
    put(brick & (corner | centre), GLAZE_B)
    chipped = brick & (tid < 0.035) & (u + v > 7)
    put(chipped, GROUT)
    put(brick & tile_joint, GROUT)
    put(brick & tile_joint & (vnoise(X, Z, 6, 86) > 0.62), (130, 160, 108))       # moss in the joints

    # ---- the lanes: asphalt, a dashed line down the middle, a kerb, bollards
    tones(lane, LANE, r1)
    dl, dr = side_dist(marks, False), side_dist(marks, True)
    mid = lane & (np.abs(dl - dr) <= 1) & ~marks & ((ZI // 5) % 2 == 0)
    put(mid, LANE_LINE)
    lx, lz = XI % 8, ZI % 8
    kerb_up = (world.mark[16] & ((lx == 3) | (lx == 4))) | (world.mark[32] & ((lz == 3) | (lz == 4)))
    post = world.mark[33] & ((lx - 3.5) ** 2 + (lz - 3.5) ** 2 <= 5)
    put(marks & lane, LANE[2])
    put(kerb_up | post, (244, 246, 250))

    # ---- trodden earth
    tones(foot, EARTH, vnoise(X, Z, 4, 87) * 0.6 + r1 * 0.4)
    put(foot & (r2 < 0.05), PEBBLE[3])
    put(foot & (r3 < 0.03), (160, 130, 96))

    # ---- the grass, and whatever lies in it
    turf = lawn | world.px("SNGF") | (world.px("W"))
    f = vnoise(X, Z, 7, 31) * 0.6 + vnoise(X, Z, 2.8, 32) * 0.4 + (r1 - 0.5) * 0.14
    put(turf, G_M)
    put(turf & (f < 0.40), G_SHADE)
    put(turf & (f > 0.58), G_SUN)
    clover = turf & (vnoise(X, Z, 3.2, 33) > 0.74) & (r2 < 0.8)
    put(clover, CLOVER)
    dry = turf & (rough > 0.5) & (vnoise(X, Z, 13, 34) > 0.64) & (r3 < 0.6)
    put(dry, G_DRY)
    blade = turf & (r2 < 0.09)
    put(blade, G_L)
    put(blade & (r3 < 0.2), G_SUN)
    beside = np.zeros((H, W), bool)
    for dz, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        beside |= np.roll(turf, (dz, dx), (0, 1)) != turf
    edge = turf & beside
    put(edge, G_D)
    # the tree's floor: dark earth, last year's leaves, moss
    wood = world.px("W")
    tones(wood, SOIL, vnoise(X, Z, 3, 35) * 0.5 + r1 * 0.5)
    put(wood & (vnoise(X, Z, 4, 36) > 0.55) & (r2 < 0.55), LITTER[0])
    put(wood & (r2 < 0.10), LITTER[1])
    put(wood & (r3 < 0.08), LITTER[2])
    put(wood & (vnoise(X, Z, 6, 37) > 0.66), LITTER[3])
    # under a drawn flower the lawn simply goes on: a soil square (or even a
    # darker one) under each read as the drawing's checkerboard, not a garden
    # the water's edge: a stone kerb where the lawn meets it
    bank = turf & ~wood & (ds <= 2)
    tones(bank, COPING, h01((XI + ZI) // 5, 0, 38))
    put(bank & ((XI + ZI) % 5 == 0), (126, 134, 150))
    shore = world.land
    tones(shore, COPING, h01((XI * 3 + ZI) // 7, 1, 39))

    # ---- what stands a voxel up: the turf, the bank, the kerbs
    base = turf | bank | shore | post

    # ---- what grows. Every letter breaks the floor's merged runs round it, so
    # the town is dressed and the routes only touched.
    grows = np.full((H, W), ".", dtype="<U1")
    free = ground & ~world.flower & ~world.px("SNG")     # a sign, a fence, tall grass: nothing grows into them

    def grow(mask, letter):
        grows[mask & (grows == ".") & free] = letter

    grow(kerb_up, "k")
    grow(post, "K")
    meadow = turf & ~wood & ~bank & ~edge
    near_pave = np.zeros((H, W), bool)
    for dz, dx in ((0, 2), (0, -2), (2, 0), (-2, 0)):
        near_pave |= np.roll(paved | foot, (dz, dx), (0, 1))
    wet = meadow & (ds > 2) & (ds <= 7)
    bloom = h01(XI, ZI, 57)
    grow(wet & (bloom < 0.030), "R")
    grow(wet & (bloom < 0.050), "I")
    grow(wet & (bloom < 0.070), "r")
    # potted plants in the yards' corners, against a wall
    yard_corner = brick & (u >= 2) & (u <= 3) & (v >= 2) & (v <= 3) & (h01(XI // 8, ZI // 8, 58) < 0.06)
    grow(yard_corner & ((u == 2) & (v == 2)), "P")
    # flowers are CLUMPS (a crown two up, its shoulders round it), never a
    # loose voxel: forget-me-nots in drifts through the town's lawns and round
    # the drawn flowers, daisies and buttercups here and there, wild ones
    # sparse along the roads
    flowery = world.px("F") & town
    drift = meadow & town & ((vnoise(X, Z, 9, 59) > 0.68) | flowery)
    bcrown = drift & (bloom < np.where(flowery, 0.012, 0.006))
    grow(bcrown & (h01(XI, ZI, 71) < 0.8), "B")
    grow(meadow & town & (bloom > 0.9965), "D")
    grow(meadow & ~town & (bloom > 0.9975), "D")
    grow(meadow & ~town & (bloom < 0.0020), "Y")
    grow(meadow & ~town & (bloom > 0.9955) & (bloom <= 0.9975), "B")
    blossom = np.isin(grows, list("BDY"))
    for n, (dz, dx) in enumerate(((0, 1), (0, -1), (1, 0), (-1, 0))):
        nb = np.roll(grows, (dz, dx), (0, 1))
        for up, low in (("B", "b"), ("D", "d"), ("Y", "y")):
            grow((nb == up) & meadow & (h01(XI, ZI, 72 + n) < 0.6), low)
    # tufts: thick along the town's edges, thin across the open lawn and the roads
    tuft = h01(XI, ZI, 61)
    crown = meadow & ~blossom & ((near_pave & town & (tuft < 0.022)) | (near_pave & ~town & (tuft < 0.006))
                                 | (tuft < 0.0025 + 0.0020 * rough))
    grow(crown & (h01(XI, ZI, 62) < 0.55), "G")
    grow(crown, "g")
    for n, (dz, dx) in enumerate(((0, 1), (0, -1), (1, 0), (-1, 0))):
        grow(np.roll(crown, (dz, dx), (0, 1)) & meadow & (h01(XI, ZI, 63 + n) < 0.45), "g")
    # the wood's floor: a fern now and then, a stone
    grow(wood & (h01(XI, ZI, 68) < 0.0045), "F")
    grow(wood & (h01(XI, ZI, 69) < 0.003), "s")
    grow(foot & (h01(XI, ZI, 70) < 0.006), "s")
    return ground, claimed, tex, base, grows


vg.MAPS = MAPS
vg.TOWN, vg.PREFIX, vg.START, vg.BUDGET, vg.WALK = TOWN, "cerground", START, 200000, 1
vg.GROWS, vg.REACH, vg.kind_of, vg.paint = GROWS, REACH, kind_of, paint

if __name__ == "__main__":
    if "--write" in sys.argv:
        vg.write()
    vg.check()
