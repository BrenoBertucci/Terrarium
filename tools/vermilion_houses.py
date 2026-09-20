"""Vermilion's six houses: the swatch sheet, a check, and previews.

  python tools/vermilion_houses.py --write   (re)author assets/buildings/vermilion_houses.png
  python tools/vermilion_houses.py           check the REAL kit under lupa, count quads the
                                             way Buildings.emit merges them, render
                                             tools/_kit_out/vermhouse_*.png (SE, SW, south)

Same bench as tools/lavender_civic.py, whose renderers this borrows: a game
round costs ninety seconds, this costs a few and shows the massing. Geometry
and flat colour only. Needs Pillow + numpy + lupa. No game process is touched.
"""
import sys
from pathlib import Path

import numpy as np
from lupa import LuaRuntime
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lavender_civic import count_quads, elevation, iso  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SHEET = ROOT / "assets/buildings/vermilion_houses.png"
OUT = ROOT / "tools/_kit_out"
# One row per material, eight shades each, in lib/VermilionHouseKit.lua's order.
# Bright on purpose: the scene's light takes a fifth back (measured on the ground).
COLORS = [
    (226, 220, 206), (168, 158, 148), (250, 248, 240), (250, 236, 204),   # quay stone, mortar, limewash, cream
    (252, 222, 130), (150, 176, 196), (204, 108, 84), (92, 60, 44),       # butter, grey-blue boards, brick, dark timber
    (170, 116, 70), (238, 118, 70), (190, 84, 52), (148, 132, 118),       # wood, terracotta, its shade, grey shingle
    (230, 72, 52), (56, 56, 68), (150, 196, 214), (255, 214, 120),        # vermilion, iron, glass, lamp
    (70, 120, 190), (76, 150, 100), (214, 60, 56), (214, 190, 140),       # shutter blue, shutter green, red, rope
    (96, 160, 90), (255, 150, 60), (255, 170, 190), (236, 228, 212),      # leaf, marigold, pink, the quay's slab
    (158, 146, 136), (72, 156, 104), (240, 196, 84), (44, 62, 110),       # its joint, awning green, brass, navy
    (44, 40, 52), (150, 156, 168),                                        # recess, lead
]
PLACES = {"rod": (12, 0), "captain": (28, 0), "light": (40, 0),
          "club": (16, 20), "trade": (28, 20), "pidgey": (44, 32)}
DOORS = {"rod", "club", "trade", "pidgey"}


def write():
    img = Image.new("RGBA", (8, len(COLORS)))
    for row, rgb in enumerate(COLORS):
        for col in range(8):
            f = 0.86 + col * 0.03
            img.putpixel((col, row), tuple(min(255, round(c * f)) for c in rgb) + (255,))
    img.save(SHEET)
    print("wrote", SHEET)


def voxels(model):
    ny, nz, nx = int(model.ytop) + 1, int(model.zmax) + 1, int(model.xmax) + 1
    grid = np.full((ny, nz, nx), -1, np.int32)
    at = model.at
    for y in range(ny):
        for z in range(nz):
            for x in range(nx):
                v = at(x, y, z)
                if v is not None:
                    assert v == int(v) and 0 <= v < 8 * len(COLORS), (x, y, z, v)
                    grid[y, z, x] = int(v)
    return grid


def check(only=None):
    png = Image.open(SHEET).convert("RGB")
    assert png.size == (8, len(COLORS)), png.size
    sheet = [png.getpixel((i % 8, i // 8)) for i in range(8 * len(COLORS))]
    lua = LuaRuntime(unpack_returned_tuples=True)
    kit = lua.eval("function(p) return assert(loadfile(p))() end")((ROOT / "lib/VermilionHouseKit.lua").as_posix())
    assert kit.SHEET_H == len(COLORS)
    sp = lua.table(W=8, H=len(COLORS))
    plot = lua.eval("function() local t = {} for r = 1, 8 do t[r] = {1,1,1,1,1,1,1,1} end return t end")()
    OUT.mkdir(exist_ok=True)
    total = 0
    for name, (tx, ty) in PLACES.items():
        if only and name not in only:
            continue
        model = kit.model(sp, lua.table(id="flat_commercial", tiles=plot), tx, ty)
        assert model is not None and not isinstance(model, tuple), (name, model)
        grid = voxels(model)
        solid = grid >= 0
        assert solid[0].all(), f"{name}: the plot's paving has a hole in it"
        if name in DOORS:
            lane = solid[1:18, 56:64, 18:30]
            assert not lane.any(), f"{name}: {int(lane.sum())} voxels stand in the door's lane"
            assert not solid[1:16, 51:56, 19:29].any(), f"{name}: the alcove is not open"
            assert model.lights is not None, f"{name}: no lantern by the door"
        ch = model.chimney
        if ch:
            assert not solid[min(int(ch.y), grid.shape[0] - 1), int(ch.z), int(ch.x)], f"{name}: the flue is blocked"
        quads = count_quads(grid)
        total += quads
        print(f"{name}: {int(solid.sum())} voxels, top {int(np.nonzero(solid)[0].max())}, ~{quads} quads before AO splits")
        assert quads < 16000, f"{name}: over budget"
        iso(grid, sheet, False, 4).save(OUT / f"vermhouse_{name}_se.png")
        iso(grid, sheet, True, 4).save(OUT / f"vermhouse_{name}_sw.png")
        elevation(grid, sheet, 6).save(OUT / f"vermhouse_{name}_south.png")
    bad = kit.model(sp, lua.table(id="flat_commercial", tiles=plot), 2, 2)
    assert isinstance(bad, tuple) and bad[0] is None, "a placement that is not a house of Vermilion's must be refused"
    print(f"{total} quads in all\nPASS ->", OUT / "vermhouse_*.png")


if __name__ == "__main__":
    if "--write" in sys.argv:
        write()
    check([a for a in sys.argv[1:] if not a.startswith("--")] or None)
