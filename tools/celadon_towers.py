"""Celadon's skyline: the facade sheet, a check, and previews.

  python tools/celadon_towers.py --write        (re)paint assets/buildings/celadon_towers.png
  python tools/celadon_towers.py [name ...]     check the REAL kit under lupa and render
                                                tools/_kit_out/celtower_<name>_{se,south}.png

A tower two hundred voxels tall cannot be a swatch model: one quad a voxel a
face is a quarter of a million quads a building. So the sheet is FACADE STRIPS,
128 texels wide -- one row per kind of course (plinth, shopfront, spandrel,
three window courses, cornice, roof), eight rows a style -- and the kit answers
`row * 128 + u`, u running along the wall. Buildings.emit merges a run whose
texels march along the sheet, so a whole course of a whole face is ONE quad,
windows and all (`stripSides` gives the flanks the same).

Glass is marked in the ALPHA channel, which the scene shader reads after dark
(Voxel3D `emissiveOn`): 254 = a window, lit or not by a hash of its room;
253 = a sign, a beacon, neon -- always lit.
Needs Pillow + numpy + lupa. No game process is touched.
"""
import sys
from pathlib import Path

import numpy as np
from lupa import LuaRuntime
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lavender_civic import elevation, iso  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SHEET = ROOT / "assets/buildings/celadon_towers.png"
OUT = ROOT / "tools/_kit_out"
W = 128
WINDOW, ALWAYS = 254, 253

# style: wall, pier (darker wall), glass, glass hi, spandrel, trim, plinth, roof, period, pier width, sill?
STYLES = [
    ("deco",      (236, 226, 204), (212, 200, 176), (92, 132, 168), (150, 190, 214), (120, 96, 70),   (250, 244, 228), (150, 140, 128), (110, 108, 112), 6, 2),
    ("glass",     (150, 176, 200), (96, 116, 140),  (84, 150, 214), (160, 210, 240), (70, 96, 130),   (220, 230, 240), (78, 86, 100),   (70, 76, 88),    4, 1),
    ("brick",     (196, 104, 80),  (176, 90, 70),   (110, 150, 176), (170, 204, 220), (196, 104, 80), (244, 236, 220), (120, 78, 66),   (96, 92, 96),    8, 4),
    ("celadon",   (176, 220, 198), (120, 170, 148), (96, 190, 160), (176, 236, 214), (88, 140, 120),  (244, 250, 244), (84, 110, 100),  (74, 92, 88),    4, 1),
    ("hotel",     (250, 248, 242), (226, 222, 214), (120, 150, 190), (255, 224, 160), (70, 76, 92),   (255, 255, 255), (168, 160, 150), (120, 116, 118), 8, 3),
    ("casino",    (54, 44, 78),    (40, 32, 60),    (150, 90, 200), (240, 190, 90),  (230, 180, 70),  (250, 214, 110), (30, 26, 44),    (36, 32, 48),    6, 2),
    ("mansion",   (230, 204, 160), (206, 180, 138), (104, 132, 150), (176, 200, 210), (190, 160, 118), (250, 240, 214), (150, 130, 104), (120, 150, 132), 12, 5),
    ("concrete",  (176, 178, 184), (150, 152, 160), (70, 96, 120),  (130, 160, 184), (160, 162, 170), (208, 210, 216), (110, 112, 120), (96, 98, 106),   10, 7),
    ("centre",    (250, 250, 250), (230, 232, 236), (130, 170, 210), (190, 220, 240), (214, 70, 70),  (255, 255, 255), (190, 60, 64),   (200, 204, 210), 6, 2),
    ("terracotta", (230, 140, 90), (208, 120, 76),  (110, 140, 150), (180, 204, 204), (250, 232, 200), (252, 240, 214), (150, 90, 66),   (130, 100, 90),  8, 3),
    ("bronze",    (84, 70, 58),    (64, 54, 46),    (150, 120, 70), (230, 190, 110), (60, 50, 44),    (214, 170, 90),  (44, 38, 34),    (50, 46, 44),    4, 1),
    ("slate",     (136, 150, 170), (112, 126, 146), (70, 100, 140), (140, 176, 210), (100, 112, 132), (226, 232, 240), (84, 94, 110),   (80, 88, 100),   8, 3),
]
# after the styles: rows of ONE colour (crowns, signs, paving), in lib/CeladonTowerKit.lua's order
FLAT = [
    ("pave", (240, 236, 226), 255), ("pavejoint", (170, 172, 166), 255), ("gold", (244, 200, 96), 255),
    ("copper", (110, 178, 150), 255), ("red", (220, 64, 64), 255), ("white", (252, 252, 252), 255),
    ("iron", (56, 58, 68), 255), ("neon_pink", (255, 96, 200), ALWAYS), ("neon_cyan", (96, 236, 255), ALWAYS),
    ("beacon", (255, 70, 60), ALWAYS), ("sign_lit", (255, 236, 160), ALWAYS), ("leaf", (96, 170, 96), 255),
    ("leaf_dk", (70, 136, 78), 255), ("wood", (150, 104, 70), 255), ("navy", (44, 60, 110), 255),
    ("glass_roof", (150, 220, 210), WINDOW),
]


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)


def paint():
    img = Image.new("RGBA", (W, len(STYLES) * 8 + len(FLAT)), (0, 0, 0, 255))
    px = img.load()
    for s, (name, wall, pier, glass, glass_hi, spandrel, trim, plinth, roof, period, pw) in enumerate(STYLES):
        rng = np.random.default_rng(100 + s)
        for u in range(W):
            k = u % period
            is_pier = k < pw
            n = float(rng.random())
            r = s * 8
            # 0 plinth: big dressed blocks
            px[u, r + 0] = shade(plinth, 0.9 if u % 12 == 0 else 1.0 + (n - 0.5) * 0.06) + (255,)
            # 1 shopfront: tall glass between slim frames
            px[u, r + 1] = (shade(trim, 0.8) + (255,)) if u % 8 == 0 else (shade(glass_hi, 0.94 + (u % 8) * 0.012) + (WINDOW,))
            # 2 spandrel / wall course
            px[u, r + 2] = shade(pier if is_pier else spandrel, 1.0 + (n - 0.5) * 0.05) + (255,)
            # 3..5 window courses: head (bright reflection), middle, sill
            for j, (g, f) in enumerate(((glass_hi, 1.0), (glass, 1.0), (glass, 0.86))):
                if is_pier:
                    px[u, r + 3 + j] = shade(pier if period <= 4 else wall, 1.0 + (n - 0.5) * 0.05) + (255,)
                else:
                    edge = (k == pw or k == period - 1) and period > 4
                    px[u, r + 3 + j] = (shade(trim, 0.92) + (255,)) if edge and j == 2 else (shade(g, f) + (WINDOW,))
            # 6 cornice: trim with dentils
            px[u, r + 6] = shade(trim, 0.84 if u % 4 == 0 else 1.0) + (255,)
            # 7 roof
            px[u, r + 7] = shade(roof, 1.0 + (n - 0.5) * 0.12) + (255,)
    for i, (name, rgb, a) in enumerate(FLAT):
        for u in range(W):
            px[u, len(STYLES) * 8 + i] = rgb + (a,)
    img.save(SHEET)
    print("wrote", SHEET, img.size)


def voxels(model):
    ny, nz, nx = int(model.ytop) + 1, int(model.zmax) + 1, int(model.xmax) + 1
    grid = np.full((ny, nz, nx), -1, np.int32)
    at = model.at
    for y in range(ny):
        for z in range(nz):
            for x in range(nx):
                v = at(x, y, z)
                if v is not None:
                    grid[y, z, x] = int(v)
    return grid


def check(only):
    png = Image.open(SHEET).convert("RGB")
    rows = len(STYLES) * 8 + len(FLAT)
    assert png.size == (W, rows), png.size
    sheet = [png.getpixel((i % W, i // W)) for i in range(W * rows)]
    lua = LuaRuntime(unpack_returned_tuples=True)
    kit = lua.eval("function(p) return assert(loadfile(p))() end")((ROOT / "lib/CeladonTowerKit.lua").as_posix())
    assert int(kit.SHEET_H) == rows, (kit.SHEET_H, rows)
    sp = lua.table(W=W, H=rows)
    OUT.mkdir(exist_ok=True)
    names = dict(kit.NAMES.items())
    for key, name in sorted(names.items(), key=lambda kv: kv[1]):
        if only and name not in only:
            continue
        tx, ty = map(int, key.split(":"))
        tw, th = int(kit.PLOTS[key][2]), int(kit.PLOTS[key][3])
        tiles = lua.eval("function(w, h) local t = {} for r = 1, h do t[r] = {} for c = 1, w do t[r][c] = 1 end end return t end")(tw, th)
        model = kit.model(sp, lua.table(id="x", tiles=tiles), tx, ty)
        assert model is not None and not isinstance(model, tuple), (name, model)
        assert int(model.ytop) <= 238, (name, "ShadowMap.HEIGHT is 240")
        assert int(model.xmax) == tw * 8 - 1 and int(model.zmax) == th * 8 - 1, name
        grid = voxels(model)
        solid = grid >= 0
        assert (grid < W * rows).all(), name
        D = th * 8
        assert solid[0].all(), f"{name}: the plot's paving has a hole in it"
        # nothing below head height stands on the plot's last cell row: every door's lane
        assert not solid[1:18, D - 8:, :].any(), f"{name}: something stands in the door lane"
        print(f"{name}: {tw * 8}x{D} plot, top {int(np.nonzero(solid)[0].max())}, {int(solid.sum())} voxels")
        iso(grid, sheet, False, 2).save(OUT / f"celtower_{name}_se.png")
        elevation(grid, sheet, 3).save(OUT / f"celtower_{name}_south.png")
    print("PASS ->", OUT / "celtower_*.png")


if __name__ == "__main__":
    if "--write" in sys.argv:
        paint()
    check([a for a in sys.argv[1:] if not a.startswith("--")] or None)
