"""The ground of Pallet Town, Viridian City and Pewter City, and the roads between.

  python tools/west_ground.py --write   paint assets/buildings/westground_<MAP>.png,
                                        write data/westground_<MAP>.lua + the index
  python tools/west_ground.py           check the REAL kit against the REAL maps,
                                        count quads, render tools/_kit_out/westground_world.png

The fifth painted world, stood by the same kit (lib/LavenderGroundKit.lua) and
written and checked by tools/vermilion_ground.py's write() and check(). Three
towns on one canvas with the four roads that join them -- Route 1 from Pallet
up to Viridian, Route 2 on to Pewter, Route 22 west to the League's gate,
Route 3 east toward Mt. Moon -- so no edge shows between any of them. The
drawings decide WHERE (their paths are paved, their lawns are lawn -- the green
is grass --, their flowers keep standing); each town decides WHAT:

  PALLET    "a fresh and pure white": a country village. Lanes of pale packed
            earth with two wheel ruts, a border of little white stones, lawns
            thick with daisies and white clover, and in front of the lab a
            COMPASS ROSE in pale stone -- where every journey starts.
  VIRIDIAN  "the eternally green paradise": the green gets into everything.
            Irregular flagstones with moss in every joint and grass pushing
            through, moss on the older flags, the deepest lawns in Kanto, clipped
            box hedges along the walks, ferns in the shade, and a LEAF laid in
            green stone where the town's roads meet.
  PEWTER    "a stone gray city": granite setts in running bond, dark joints,
            long kerb stones along each edge; lawns gone dry and olive with
            pebbles, rocks and heather in them; before the Museum an AMMONITE
            spiralling out in dark and pale stone.
  the roads each takes its town's ground out with it, and lets it go: Route 1
            an earth track with ruts, Routes 2 and 22 mossy forest gravel,
            Route 3 rocky mountain gravel. Where two meet they blend.

Nothing here is extracted from the ROM. The tiles only decided where.
"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vermilion_ground as vg  # noqa: E402
from cerulean_ground import seg_d, side_dist, spans  # noqa: E402
from lavender_ground import box_blur, h01, vnoise  # noqa: E402

TOWN = "VIRIDIAN_CITY"
# world cell origins (Viridian's corner at 0, 0), off the connections: Route 1
# joins Viridian's south edge and Route 2 its north five blocks in, Pallet
# hangs straight under Route 1, Pewter over Route 2 (whose own offset is -5);
# Route 22 joins Viridian's west edge and Route 3 Pewter's east four blocks down
MAPS = [("VIRIDIAN_CITY", 0, 0), ("ROUTE_1", 10, 36), ("PALLET_TOWN", 10, 72), ("ROUTE_2", 10, -72),
        ("PEWTER_CITY", 0, -108), ("ROUTE_22", -40, 8), ("ROUTE_3", 40, -100)]
PALLET, VIRIDIAN, PEWTER = 0, 1, 2
STYLE_OF = {"PALLET_TOWN": PALLET, "ROUTE_1": PALLET, "VIRIDIAN_CITY": VIRIDIAN, "ROUTE_22": VIRIDIAN,
            "ROUTE_2": VIRIDIAN, "PEWTER_CITY": PEWTER, "ROUTE_3": PEWTER}
TOWNS = {"PALLET_TOWN", "VIRIDIAN_CITY", "PEWTER_CITY"}
PATH_T = {35, 57, 91}
MARK_T = {16, 32, 33}
LAWN_T = {44, 48}

# ------------------------------------------------------------- the palettes --
# (lifted for what the light takes away: stone shows at about x0.69, turf x0.85)
# Pallet: pale earth, white stone
EARTH = [(236, 222, 192), (228, 212, 180), (240, 228, 200), (224, 208, 176)]
RUT = [(206, 188, 152), (198, 180, 146)]
WHITE_STONE = [(252, 252, 248), (244, 244, 240)]
ROSE_A, ROSE_B, ROSE_C = (250, 248, 240), (206, 196, 176), (150, 170, 196)      # pale, sand, a blue-grey point
P_GRASS = [(116, 190, 96), (100, 176, 88), (138, 204, 108), (86, 160, 82)]
# Viridian: flags and moss
FLAG = [(206, 204, 184), (196, 196, 178), (214, 212, 192), (188, 190, 172), (200, 206, 186)]
FLAG_MOSS = [(160, 182, 132), (148, 172, 122)]
MOSS = [(94, 146, 76), (82, 132, 68), (106, 158, 82)]
LEAF_G = [(76, 150, 82), (104, 176, 94), (60, 124, 70)]
V_GRASS = [(74, 150, 72), (62, 136, 66), (92, 166, 80), (52, 120, 60)]
# Pewter: granite
SETT = [(170, 172, 178), (160, 162, 170), (180, 180, 184), (152, 156, 166), (176, 170, 166), (164, 168, 176)]
SETT_JOINT = (104, 106, 114)
KERB = [(196, 196, 200), (188, 188, 194)]
AMMO_D, AMMO_L, AMMO_R = (118, 110, 104), (218, 206, 184), (178, 160, 136)
W_GRASS = [(142, 160, 94), (128, 148, 86), (158, 170, 104), (116, 136, 82)]
GRAVEL = [(190, 188, 184), (176, 174, 172), (202, 198, 192), (166, 164, 164)]
# a wood's floor, anywhere
SOIL = [(104, 84, 64), (92, 74, 58), (116, 92, 70)]
LITTER = [(154, 112, 62), (172, 124, 60), (126, 98, 56), (110, 132, 70)]
EDGE_D = (58, 110, 64)

GROWS = {
    "g": {"top": [(146, 206, 110), (126, 194, 100)], "stem": [(92, 164, 86), (74, 142, 80)]},  # a tuft
    "o": {"top": [(176, 186, 110), (160, 174, 100)], "stem": [(130, 148, 88)]},                # a dry tuft
    "d": {"top": [(252, 252, 246)], "stem": [(96, 166, 86)]},                                   # daisy
    "c": {"top": [(250, 240, 244), (244, 228, 236)], "stem": [(90, 160, 84)]},                  # white clover
    "y": {"top": [(250, 220, 84)], "stem": [(96, 166, 86)]},                                    # buttercup, dandelion
    "e": {"top": [(170, 110, 196), (150, 96, 180)], "stem": [(110, 120, 80)]},                  # heather
    "f": {"top": [(104, 176, 80), (86, 160, 70)], "stem": [(56, 110, 56)]},                     # fern
    "h": {"top": [(58, 124, 64), (66, 136, 70), (52, 114, 58)], "stem": [(46, 100, 52)]},       # clipped box
    "s": {"top": [(252, 252, 248), (240, 240, 236)], "stem": [(226, 226, 222)]},                # a white stone
    "r": {"top": [(150, 150, 156), (136, 138, 146), (164, 162, 164)], "stem": [(122, 124, 132)]},  # a rock
}

# --------------------------------------------------------- the towns' plans --
# World voxels (Viridian's corner at 0, 0).
ROSE = (320, 1264, 13)                   # in the lane between the two houses: where it starts
LEAF = (296, 304, 15)                    # where Viridian's roads cross
AMMONITE = (232, -1576, 15)              # before the Museum
REACH = {"Viridian": (312, 200), "Pallet": (248, 1272), "Pewter": (216, -1440),
         "Viridian Centre": (376, 424), "Viridian Mart": (472, 328), "school": (344, 264),
         "nickname house": (344, 168), "Viridian Gym": (520, 136),
         "Red's house": (248, 1256), "Blue's house": (376, 1256), "Oak's lab": (360, 1352),
         "Museum": (232, -1592), "Pewter Gym": (264, -1432), "Nidoran house": (472, -1496),
         "Pewter Mart": (376, -1432), "speech house": (120, -1240), "Pewter Centre": (216, -1304)}
START = ["Viridian", "Pallet", "Pewter"]


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
    r1, r2, r3 = h01(XI, ZI, 121), h01(XI, ZI, 122), h01(XI, ZI, 123)

    # ---- which town each voxel belongs to, blended where two meet
    origin = {mid: (gx - world.cx0, gy - world.cy0) for mid, gx, gy, *_ in world.maps}
    onehot = np.zeros((3, H, W))
    townish = np.zeros((H, W))
    for mid, gx, gy, w, h, _ in world.maps:
        c0, r0 = origin[mid][0] * 16, origin[mid][1] * 16
        onehot[STYLE_OF[mid], r0:r0 + h * 16, c0:c0 + w * 16] = 1
        if mid in TOWNS:
            townish[r0:r0 + h * 16, c0:c0 + w * 16] = 1
    wob = (vnoise(X, Z, 9, 124) - 0.5)
    for k in range(3):
        onehot[k] = box_blur(box_blur(onehot[k], 10), 10) + wob * 0.4 * (k - 1)
    style = np.argmax(onehot, axis=0)
    townness = box_blur(box_blur(townish, 12), 12) + wob * 0.5
    town = townness > 0.5

    # ---- what each quarter of a paved cell was drawn as
    qlawn = np.zeros((H, W), bool)
    qpath = np.zeros((H, W), bool)
    street_c = np.zeros((world.ch, world.cw), bool)
    for (mid, cx, cy), p in world.tiles.items():
        r, c = origin[mid][1] + cy, origin[mid][0] + cx
        if world.kind[r, c] != "V":
            continue
        street_c[r, c] = True
        for q, (oz, ox) in enumerate(((0, 0), (0, 8), (8, 0), (8, 8))):
            sl = (slice(r * 16 + oz, r * 16 + oz + 8), slice(c * 16 + ox, c * 16 + ox + 8))
            (qlawn if p[q] in LAWN_T else qpath)[sl] = True

    # ---- the paving, corners rounded; out on a road its edge is let go
    lawnish = world.px("L") | qlawn | world.px("SNWGF")
    pav0 = qpath & claimed
    field = box_blur(box_blur(pav0.astype(float), 3), 3)
    room = box_blur(box_blur((pav0 | (lawnish & claimed)).astype(float), 3), 3)
    frac = field / np.maximum(room, 1e-6)
    frac = frac + np.where(town, 0, (vnoise(X, Z, 6, 125) - 0.5) * 0.6)
    paved = claimed & (frac > 0.5)
    paved |= pav0 & ~lawnish & (town | (vnoise(X, Z, 6, 125) > 0.3))
    lawn = claimed & ~paved
    wood = world.px("W")
    turf = lawn | world.px("SNGF") | wood

    # the street's own axis (for the ruts and the kerbs)
    r0_, rl, c0_, cl = spans(street_c)
    ext = lambda a: np.kron(a, np.ones((16, 16), int))      # noqa: E731
    ew = ext((cl >= rl).astype(int)).astype(bool)
    zc = ext(r0_) * 16 + ext(rl) * 8 + world.cy0 * 16
    xc = ext(c0_) * 16 + ext(cl) * 8 + world.cx0 * 16
    half = np.where(ew, ext(rl), ext(cl)) * 8
    cross = np.where(ew, Z - zc, X - xc)
    along = np.where(ew, X, Z)
    ds_pave = vg.reach_of(~paved, 4)                          # voxels in from the paving's edge

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

    # ================================================================ PALLET
    p_pave = paved & (style == PALLET)
    tones(p_pave, EARTH, vnoise(X, Z, 3.5, 131) * 0.6 + r1 * 0.4)
    lane_off = cross + (vnoise(X, Z, 20, 132) - 0.5) * 2
    wheel = p_pave & (half >= 12) & (np.abs(np.abs(lane_off) - 5.5) < 1.1)
    tones(wheel, RUT, r2)
    # the crown between the ruts: grass, the way a cart lane grows it
    long_lane = np.where(ew, ext(cl), ext(rl)) >= 6                   # only down a lane that goes somewhere
    crown_strip = p_pave & (half >= 12) & long_lane & (np.abs(lane_off) < 2.4 + (vnoise(X, Z, 3, 134) - 0.5) * 1.4)
    put(p_pave & (r3 < 0.04), (214, 200, 170))
    edge_p = p_pave & town & (ds_pave <= 1)
    tones(edge_p, WHITE_STONE, r1)                              # the little white stones along a lane
    grow(p_pave & town & (ds_pave == 2) & (h01(XI // 3, ZI // 3, 133) < 0.18) & (r2 < 0.5), "s")
    # the compass rose before the lab: eight points, a ring, a blue north
    rx, rz, rr = ROSE
    dx, dz = X - rx, Z - rz
    rad = np.hypot(dx, dz)
    ang = np.arctan2(dx, -dz)                                   # 0 = north
    k8 = np.round(ang / (np.pi / 4))
    dev = np.abs(ang - k8 * np.pi / 4)
    long_pt = (np.abs(k8) % 2 == 0)
    reach = np.where(long_pt, rr, rr * 0.62)
    point = dev * rad < (1 - rad / reach) * reach * 0.34
    rose = p_pave & (rad < rr + 3)
    crown_strip &= ~(rad < rr + 8)
    put(rose, ROSE_A)
    put(rose & (np.abs(rad - (rr + 1)) < 1.1), ROSE_B)
    put(rose & (rad < reach) & point, ROSE_B)
    put(rose & (rad < reach) & point & (np.sign(np.sin(ang * 4 + 0.01)) > 0), (184, 172, 150))  # a shaded side
    put(rose & (rad < reach) & point & (k8 == 0), ROSE_C)                                        # north, in blue
    put(rose & (rad < 2.2), ROSE_C)

    # ============================================================== VIRIDIAN
    v_pave = paved & (style == VIRIDIAN)
    # flags: a RANDOM ASHLAR. A sixteen-voxel block is halved one way or the
    # other (or not), and each half halved again across -- slabs of 16, 8x16,
    # 8x8, 8x4, 4x16 lying every which way. (Courses of one height read as a
    # brick wall from this camera: tools/celadon_ground.py learnt it first.)
    bz = ZI // 16
    bx = (XI + (bz % 2) * 8) // 16
    lx_, lz_ = (XI + (bz % 2) * 8) % 16, ZI % 16
    s1 = h01(bx, bz, 141)
    vert, horz = s1 < 0.42, (s1 >= 0.42) & (s1 < 0.84)
    piece = np.where(vert, lx_ >= 8, np.where(horz, lz_ >= 8, 0)).astype(int)
    s2 = h01(bx * 3 + piece, bz, 142)
    cut2 = s2 < 0.6
    at2 = np.where(s2 < 0.3, 4, 8) + np.where(h01(bx, bz * 5 + piece, 143) < 0.5, 0, 4 * (s2 < 0.3))
    sub = np.where(vert, lz_ >= at2, np.where(horz, lx_ >= at2, lx_ >= 8)).astype(int) * cut2
    joint = ((lx_ == 0) | (lz_ == 0) | (vert & (lx_ == 8)) | (horz & (lz_ == 8))
             | (cut2 & vert & (lz_ == at2)) | (cut2 & horz & (lx_ == at2)) | (cut2 & ~vert & ~horz & (lx_ == 8)))
    fid = (bx * 7 + piece) * 131 + bz * 17 + sub
    tone = h01(fid, 0, 144)
    tones(v_pave, FLAG, tone)
    mossy = v_pave & (h01(fid, 1, 145) < 0.3) & (vnoise(X, Z, 3, 146) > 0.45)
    tones(mossy, FLAG_MOSS, r1)
    tones(v_pave & joint, MOSS, r2)
    # out on a road: forest gravel, fallen leaves in it
    v_road = v_pave & ~town
    tones(v_road, GRAVEL[:2] + [(170, 164, 140), (158, 156, 132)], vnoise(X, Z, 3, 147) * 0.5 + r1 * 0.5)
    put(v_road & (r2 < 0.05), LITTER[0])
    put(v_road & (r3 < 0.035), MOSS[0])
    grow(v_pave & town & joint & (r3 < 0.018), "g")                                    # grass through the joints
    # the leaf, where the roads cross
    lx, lz, lr = LEAF
    u = (X - lx) * 0.7071 + (Z - lz) * 0.7071                   # along the leaf, laid on the diagonal
    v = -(X - lx) * 0.7071 + (Z - lz) * 0.7071
    blade = np.abs(v) < (1 - (u / lr) ** 2) * lr * 0.42
    in_leaf = v_pave & (np.abs(u) < lr) & blade
    put(v_pave & (np.abs(u) < lr + 1.5) & ~blade & (np.abs(v) < (1 - (u / (lr + 1.5)) ** 2) * (lr + 1.5) * 0.42 + 1.2), FLAG[2])
    tones(in_leaf, LEAF_G[:2], h01(XI // 2, ZI // 2, 148))
    vein = in_leaf & ((np.abs(v) < 0.8) | (np.abs(np.abs(v) - (u + lr) * 0.35 % 4) < 0.6))
    put(in_leaf & (np.abs(v) < 0.8), LEAF_G[2])
    put(in_leaf & ~vein & (np.abs(v) > 0.8) & ((np.floor((u + np.abs(v) * 1.4) / 4) % 2) == 0), LEAF_G[1])
    put(v_pave & (np.abs(v) < 0.8) & (u < -lr) & (u > -lr - 5), LEAF_G[2])            # the stalk

    # ================================================================ PEWTER
    w_pave = paved & (style == PEWTER)
    # setts laid in FANS, the old stone-city way: each fan a disc of rings of
    # setts, the row to the south lapping over the one behind it -- scales,
    # nothing a brick wall could be mistaken for
    PF, SF, RF = 24, 12, 17.0
    j0 = ZI // SF
    got = np.zeros((H, W), bool)
    fcx = np.zeros((H, W))
    fcz = np.zeros((H, W))
    fj = np.zeros((H, W), np.int64)
    for dj in (2, 1, 0):
        j = j0 + dj
        shift = (j % 2) * (PF / 2)
        i = np.floor((X - shift) / PF + 0.5)
        cxj = i * PF + shift
        czj = j * SF
        inside = ~got & (czj >= Z) & (np.hypot(X - cxj, Z - czj) <= RF)
        fcx = np.where(inside, cxj, fcx)
        fcz = np.where(inside, czj, fcz)
        fj = np.where(inside, j * 1000 + i.astype(np.int64), fj)
        got |= inside
    fr = np.hypot(X - fcx, Z - fcz)
    fth = np.arctan2(Z - fcz, X - fcx)
    ringw = 3.4
    ring = np.floor(fr / ringw)
    arcu = fth * np.maximum(fr, 1) / ringw
    sid = fj * 97 + ring.astype(np.int64) * 13 + np.floor(arcu).astype(np.int64)
    sjoint = got & (((fr / ringw) % 1 < 0.28) | ((arcu % 1) < 0.28))
    tones(w_pave, SETT, h01(sid, 0, 151))
    put(w_pave & sjoint, SETT_JOINT)
    put(w_pave & got & (fr > RF - 1.2), SETT_JOINT)
    # the kerb: long stones along a street's edges
    kerb = w_pave & town & (ds_pave <= 2)
    kid = np.where(ew, XI // 12, ZI // 12)
    tones(kerb, KERB, h01(kid, 3, 152))
    put(kerb & ((np.where(ew, XI, ZI) % 12) == 0), SETT_JOINT)
    put(kerb & (ds_pave == 0), (150, 150, 156))
    # out on the mountain road: loose rocky gravel
    w_road = w_pave & ~town
    tones(w_road, GRAVEL, vnoise(X, Z, 2.5, 153) * 0.5 + r2 * 0.5)
    put(w_road & (r3 < 0.06), SETT[3])
    grow(w_road & (h01(XI, ZI, 154) < 0.004), "r")
    # the ammonite: a spiral of dark stone opening out, its chambers ribbed
    ax, az, ar = AMMONITE
    rad = np.hypot(X - ax, Z - az)
    th = np.arctan2(Z - az, X - ax)
    turn = (np.log(np.maximum(rad, 0.8) / 0.8) / 0.33 - th) / (2 * np.pi)
    whorl = np.abs(turn - np.round(turn)) < 0.17
    ammo = w_pave & (rad < ar)
    put(ammo, AMMO_L)
    rib = ammo & ((np.floor(th * 10 / np.pi + rad * 0.15) % 2) == 0)
    put(rib, AMMO_R)
    put(ammo & whorl, AMMO_D)
    put(w_pave & (np.abs(rad - ar - 0.5) < 1.0), AMMO_D)

    # ================================================================ lawns
    f = vnoise(X, Z, 7, 161) * 0.6 + vnoise(X, Z, 2.6, 162) * 0.4 + (r1 - 0.5) * 0.14
    for k, pal in ((PALLET, P_GRASS), (VIRIDIAN, V_GRASS), (PEWTER, W_GRASS)):
        m = turf & (style == k)
        put(m, pal[0])
        put(m & (f < 0.40), pal[3])
        put(m & (f > 0.58), pal[2])
        put(m & (r2 < 0.09), pal[1])
    put(turf & (style == VIRIDIAN) & (vnoise(X, Z, 4, 163) > 0.70), MOSS[1])          # moss pads
    put(turf & (style == PEWTER) & (vnoise(X, Z, 5, 164) > 0.68) & (r1 < 0.7), GRAVEL[1])  # bare stony ground
    beside = np.zeros((H, W), bool)
    for dzz, dxx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        beside |= np.roll(turf, (dzz, dxx), (0, 1)) != turf
    edge = turf & beside
    put(edge, EDGE_D)
    # a wood's floor
    tones(wood, SOIL, vnoise(X, Z, 3, 165) * 0.5 + r1 * 0.5)
    put(wood & (vnoise(X, Z, 4, 166) > 0.55) & (r2 < 0.55), LITTER[0])
    put(wood & (r2 < 0.10), LITTER[1])
    put(wood & (vnoise(X, Z, 6, 167) > 0.66), LITTER[3])
    # the water's edge
    ds = vg.reach_of(world.sea, 6)
    bank = turf & ~wood & (ds <= 2)
    tones(bank, KERB + [(176, 180, 186)], h01((XI + ZI) // 5, 0, 168))
    tones(world.land, KERB, h01((XI * 3 + ZI) // 7, 1, 169))

    tones(crown_strip, P_GRASS, f)
    base = turf | bank | world.land | crown_strip

    # ================================================================ growing
    meadow = turf & ~wood & ~bank & ~edge
    near_pave = np.zeros((H, W), bool)
    for dzz, dxx in ((0, 2), (0, -2), (2, 0), (-2, 0)):
        near_pave |= np.roll(paved, (dzz, dxx), (0, 1))
    bloom = h01(XI, ZI, 171)
    # Viridian's box hedges: along the town's walks, clipped, two voxels tall
    hedge_line = turf & town & (style == VIRIDIAN) & ~wood & near_pave & edge
    hedge_run = vnoise(X, Z, 14, 172) > 0.55
    grow(np.roll(hedge_line, 0, 0) & hedge_run & world.px("L"), "H")
    # flowers, clumps: a crown two up, shoulders round it
    pal_m, vir_m, pew_m = meadow & (style == PALLET), meadow & (style == VIRIDIAN), meadow & (style == PEWTER)
    grow(pal_m & (bloom < np.where(town, 0.006, 0.0025)), "D")
    grow(pal_m & (bloom > 1 - np.where(town, 0.007, 0.002)), "C")
    grow(pal_m & (bloom > 0.4995) & (bloom < 0.5025), "Y")
    grow(vir_m & (bloom < 0.004), "F")
    grow(vir_m & (bloom > 0.997), "Y")
    grow(pew_m & (bloom < 0.004), "E")
    grow(pew_m & (bloom > 0.996), "R")
    grow(pew_m & (bloom > 0.990) & (bloom <= 0.996), "r")
    for n, (dzz, dxx) in enumerate(((0, 1), (0, -1), (1, 0), (-1, 0))):
        nb = np.roll(grows, (dzz, dxx), (0, 1))
        for up, low in (("D", "d"), ("C", "c"), ("Y", "y"), ("F", "f"), ("E", "e")):
            grow((nb == up) & meadow & (h01(XI, ZI, 173 + n) < 0.6), low)
    # tufts: thick along a town's edges, thin elsewhere; dry ones in Pewter
    tuft = h01(XI, ZI, 181)
    crown = meadow & ((near_pave & town & (tuft < 0.018)) | (near_pave & ~town & (tuft < 0.005)) | (tuft < 0.0025))
    grow(crown & (style == PEWTER) & (h01(XI, ZI, 182) < 0.5), "O")
    grow(crown & (style == PEWTER), "o")
    grow(crown & (h01(XI, ZI, 182) < 0.5), "G")
    grow(crown, "g")
    for n, (dzz, dxx) in enumerate(((0, 1), (0, -1), (1, 0), (-1, 0))):
        sh = np.roll(crown, (dzz, dxx), (0, 1)) & meadow & (h01(XI, ZI, 183 + n) < 0.45)
        grow(sh & (style == PEWTER), "o")
        grow(sh, "g")
    grow(wood & (h01(XI, ZI, 187) < 0.0045) & (style == VIRIDIAN), "F")
    grow(wood & (h01(XI, ZI, 188) < 0.003), "r")
    return ground, claimed, tex, base, grows


vg.MAPS = MAPS
vg.TOWN, vg.PREFIX, vg.START, vg.BUDGET, vg.WALK = TOWN, "westground", START, 220000, 1
vg.GROWS, vg.REACH, vg.kind_of, vg.paint = GROWS, REACH, kind_of, paint

if __name__ == "__main__":
    if "--write" in sys.argv:
        vg.write()
    vg.check()
