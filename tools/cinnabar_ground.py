"""The ground of Cinnabar Island: a plan, its data, a check.

  python tools/cinnabar_ground.py --write   paint assets/buildings/cinnground_CINNABAR_ISLAND.png,
                                            write data/cinnground_CINNABAR_ISLAND.lua + the index
  python tools/cinnabar_ground.py           check the REAL kit against the REAL map

The eighth painted world, one map: Cinnabar's two roads (Routes 20 and 21) are
open sea. Stood by lib/LavenderGroundKit.lua, written and checked by
tools/vermilion_ground.py.

"The fiery town of burning desire" -- a volcano's island. Its drawing lays all
its open ground as a checker of grass ($30) and pale stone ($39): half green,
half stone. The green is grass and stays grass; the checker does not (a
checkerboard is the drawing's, not an island's). So the island's ground is
built from what a volcano leaves:

  the walks     BASALT: the tops of hexagonal columns, black and grey, a rusty
                one here and there, running between the doors
  the rest      red scoria gravel, and tough grass in drifts across it -- as
                much green as the drawing asked for, where grass would take
  before the    a FLAME laid in red and orange stone in the basalt
  Gym
  the shore     black volcanic sand
  what grows    wiry tufts, red fire-lilies, a pumice stone here and there

Nothing here is extracted from the ROM. The tiles only decided where.
"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vermilion_ground as vg  # noqa: E402
from cerulean_ground import seg_d  # noqa: E402
from lavender_ground import box_blur, h01, vnoise  # noqa: E402

TOWN = "CINNABAR_ISLAND"
MAPS = [(TOWN, 0, 0)]
OPEN_T = {48, 57, 44, 35}

BASALT = [(84, 82, 88), (74, 72, 78), (94, 92, 96), (66, 64, 70), (104, 100, 102)]
BASALT_RUST = (132, 84, 66)
BASALT_JOINT = (150, 146, 144)
SCORIA = [(150, 72, 58), (132, 62, 52), (164, 86, 66), (118, 58, 50)]
ASH = (176, 164, 156)
SAND_BLACK = [(70, 66, 70), (60, 58, 62), (82, 78, 80)]
FLAME = [(236, 72, 40), (250, 140, 44), (252, 212, 90)]
C_GRASS = [(110, 158, 82), (96, 146, 76), (128, 170, 90), (84, 132, 70)]
EDGE_D = (62, 100, 58)

GROWS = {
    "g": {"top": [(150, 186, 96), (130, 174, 88)], "stem": [(96, 146, 76)]},                   # a wiry tuft
    "l": {"top": [(240, 70, 48), (250, 110, 50)], "stem": [(84, 130, 70)]},                   # fire-lily
    "p": {"top": [(210, 202, 196), (196, 188, 184)], "stem": [(170, 164, 160)]},              # pumice
}

# the walks between the doors (world voxels), and the flame before the Gym
WALKS = [(12, [(104, 72), (104, 120), (104, 168), (150, 190), (184, 200), (248, 200), (290, 150), (296, 88)]),
         (10, [(184, 200), (184, 150), (200, 100), (296, 88)]),
         (30, [(286, 96), (290, 104)])]                                  # a little square before the Gym
FLAME_AT = (288, 100, 12)
REACH = {"Cinnabar": (184, 200), "Mansion": (104, 72), "Gym": (296, 72), "Lab": (104, 168),
         "Centre": (184, 200), "Mart": (248, 200)}
START = "Cinnabar"


def kind_of(p, town, cx, cy):
    s = set(p)
    if p == vg.SIGN:
        return "S"
    if p == vg.FENCE:
        return "N"
    if p in vg.TREES:
        return "W"
    if s <= OPEN_T:
        return "V"
    if s <= vg.SHORE_T | {vg.SEA_T} and s & vg.SHORE_T:
        return "Q"
    return "."


def hexes(X, Z, s, seed):
    """Hexagonal column tops of size s: each voxel's column id, and whether it is a joint."""
    w, h = s * np.sqrt(3), s * 1.5
    row = np.floor(Z / h).astype(np.int64)
    d1 = np.full(X.shape, 1e9)
    d2 = np.full(X.shape, 1e9)
    cid = np.zeros(X.shape, np.int64)
    for dr in (-1, 0, 1):
        r = row + dr
        off = (r % 2) * (w / 2)
        col = np.floor((X - off) / w).astype(np.int64)
        for dc in (-1, 0, 1):
            c = col + dc
            cx = c * w + off + w / 2
            cz = r * h + h / 2
            d = (X - cx) ** 2 + (Z - cz) ** 2
            nearer = d < d1
            d2 = np.where(nearer, d1, np.minimum(d2, d))
            d1 = np.where(nearer, d, d1)
            cid = np.where(nearer, c * 7919 + r * 104729, cid)
    return cid, np.sqrt(d2) - np.sqrt(d1) < 0.7


def paint(world):
    H, W = world.ch * 16, world.cw * 16
    X, Z = np.meshgrid(np.arange(W) + 0.5, np.arange(H) + 0.5)
    XI, ZI = np.floor(X).astype(np.int64), np.floor(Z).astype(np.int64)
    ground = world.px("VSNW") | world.land
    claimed = world.px("V")
    r1, r2, r3 = h01(XI, ZI, 401), h01(XI, ZI, 402), h01(XI, ZI, 403)

    # the walks, and the grass: drifts, about as much of it as the drawing had
    wd = np.full((H, W), 1e9)
    for width, pts in WALKS:
        wd = np.minimum(wd, seg_d(X, Z, pts) - width / 2)
    wd = wd + (vnoise(X, Z, 5, 404) - 0.5) * 3
    walk = claimed & (wd < 0)
    grassy = vnoise(X, Z, 11, 405) * 0.7 + vnoise(X, Z, 3.5, 406) * 0.3
    grass = claimed & ~walk & (grassy > 0.46 - np.clip(wd / 60, 0, 0.12))
    ds = vg.reach_of(world.sea, 10)
    sand = claimed & ~walk & (ds <= 5)
    grass &= ~sand
    scoria = claimed & ~walk & ~grass & ~sand

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

    # ---- basalt: hexagonal column tops
    cid, joint = hexes(X, Z, 3.6, 407)
    tone = h01(cid, 0, 408)
    tones(walk, BASALT, tone)
    put(walk & (h01(cid, 1, 409) < 0.07), BASALT_RUST)
    put(walk & joint, BASALT_JOINT)
    # the flame before the Gym: a tongue of red, orange, a yellow heart
    fx, fz, fr = FLAME_AT
    u, v = (X - fx) / fr, (Z - fz) / fr                          # v up the flame is -z
    y = -v
    lick = 0.55 * (1 - np.clip((y + 1) / 2, 0, 1)) + 0.12 * np.sin(y * 7 + 1.2)
    outer = (np.abs(u) < lick * 1.25) & (y > -0.95) & (y < 1.0) & (u * u + (y + 0.35) ** 2 < 1.1)
    mid = (np.abs(u) < lick * 0.8) & (y > -0.8) & (y < 0.55)
    core = (np.abs(u) < lick * 0.42) & (y > -0.7) & (y < 0.15)
    put(walk & outer, FLAME[0])
    put(walk & mid, FLAME[1])
    put(walk & core, FLAME[2])
    put(walk & outer & joint, (120, 54, 40))
    # ---- scoria, grass, black sand
    tones(scoria, SCORIA, vnoise(X, Z, 2.5, 410) * 0.5 + r1 * 0.5)
    put(scoria & (r2 < 0.05), ASH)
    f = vnoise(X, Z, 6, 411) * 0.6 + (r1 - 0.5) * 0.3
    put(grass, C_GRASS[0])
    put(grass & (f < 0.4), C_GRASS[3])
    put(grass & (f > 0.58), C_GRASS[2])
    put(grass & (r2 < 0.08), C_GRASS[1])
    put(grass & (r3 < 0.05), SCORIA[3])                         # red grit between the blades
    turf = grass | world.px("SNW")
    put(world.px("SNW"), C_GRASS[3])
    beside = np.zeros((H, W), bool)
    for dz, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        beside |= np.roll(turf, (dz, dx), (0, 1)) != turf
    put(turf & beside, EDGE_D)
    tones(sand | world.land, SAND_BLACK, vnoise(X, Z, 3, 412) * 0.5 + r1 * 0.5)
    put((sand | world.land) & (r2 < 0.02), ASH)

    base = turf

    tuft = h01(XI, ZI, 421)
    open_g = grass & ~beside
    crown = open_g & (tuft < 0.010)
    grow(crown & (h01(XI, ZI, 422) < 0.5), "G")
    grow(crown, "g")
    for n, (dz, dx) in enumerate(((0, 1), (0, -1), (1, 0), (-1, 0))):
        grow(np.roll(crown, (dz, dx), (0, 1)) & open_g & (h01(XI, ZI, 423 + n) < 0.45), "g")
    grow(open_g & (tuft > 0.9975), "L")
    grow((scoria | sand) & (h01(XI, ZI, 427) < 0.004), "p")
    return ground, claimed, tex, base, grows


vg.MAPS = MAPS
vg.TOWN, vg.PREFIX, vg.START, vg.BUDGET, vg.WALK = TOWN, "cinnground", START, 40000, 1
vg.GROWS, vg.REACH, vg.kind_of, vg.paint = GROWS, REACH, kind_of, paint

if __name__ == "__main__":
    if "--write" in sys.argv:
        vg.write()
    vg.check()
