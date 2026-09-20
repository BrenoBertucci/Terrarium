"""Lavender's Centre and Mart: the swatch sheet, a check, and previews.

  python tools/lavender_civic.py --write   (re)author assets/buildings/lavender_civic.png
  python tools/lavender_civic.py           check the REAL kit under lupa, count
                                           quads the way Buildings.emit merges
                                           them, render tools/_kit_out/civic_*.png

A game round costs ninety seconds and a probe; this costs five and shows the
massing from the south-east, the south-west and square on. Geometry and flat
colour only -- light, AO, the sun's shadow and the smoke exist in game.
Needs Pillow + numpy + lupa. No game process or save is touched.
"""
import sys
from pathlib import Path

import numpy as np
from lupa import LuaRuntime
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SHEET = ROOT / "assets/buildings/lavender_civic.png"
OUT = ROOT / "tools/_kit_out"
# One row per material, eight shades each, in lib/LavenderCivicKit.lua's
# order. The first sixteen are tools/check_lavender_houses.py's, colour for
# colour: the Centre's stone is the cottages' stone.
COLORS = [
    (133, 130, 143), (86, 82, 96), (179, 168, 178), (205, 195, 190),     # limestone, mortar, limewash, trim
    (87, 69, 112), (59, 51, 76), (82, 62, 66), (52, 42, 49),             # violet slate, flashing, walnut, grain
    (57, 58, 69), (110, 151, 162), (235, 181, 103), (75, 89, 77),        # iron, glass, amber, moss
    (75, 99, 86), (145, 115, 178), (114, 88, 96), (36, 33, 48),          # leaves, lavender, clay, recess
    (172, 60, 64), (124, 46, 56), (238, 234, 240), (62, 104, 170),       # red tile, its shade, enamel white, shop blue
    (42, 70, 124), (230, 218, 190), (208, 168, 86), (150, 108, 76),      # deep blue, cream, brass, oak
    (178, 70, 66), (104, 156, 108), (226, 192, 98), (196, 186, 166),     # goods: red, green, yellow; canvas
    (214, 210, 232), (136, 128, 148),                                    # the town's flags and their joints
    (150, 222, 212), (98, 96, 112),                                      # the Tower's: a cold light, damp stone
]


def write():
    img = Image.new("RGBA", (8, len(COLORS)))
    for row, rgb in enumerate(COLORS):
        for col in range(8):
            f = 0.90 + col * 0.025
            img.putpixel((col, row), tuple(min(255, round(c * f)) for c in rgb) + (255,))
    img.save(SHEET)
    print("wrote", SHEET)


def voxels(model):
    """The model as an int array [y, z, x]; -1 is air."""
    x0, z0 = int(model.xmin or 0), int(model.zmin or 0)
    ny, nz, nx = int(model.ytop) + 1, int(model.zmax) + 1 - z0, int(model.xmax) + 1 - x0
    grid = np.full((ny, nz, nx), -1, np.int32)
    at = model.at
    for y in range(ny):
        for z in range(nz):
            for x in range(nx):
                v = at(x + x0, y, z + z0)
                if v is not None:
                    assert v == int(v) and 0 <= v < 8 * len(COLORS), (x, y, z, v)
                    grid[y, z, x] = int(v)
    return grid


def count_quads(grid):
    """Buildings.emit's merge (flat runs of ONE texel: a swatch sheet has no strips)."""
    solid = grid >= 0
    pad = np.pad(solid, 1)
    n = 0
    # faces along +-z and +-y merge along x; faces along +-x merge along z
    for axis_shift, run_axis in (((0, 1, 0), 2), ((0, -1, 0), 2), ((1, 0, 0), 2),
                                 ((-1, 0, 0), 2), ((0, 0, 1), 1), ((0, 0, -1), 1)):
        dy, dz, dx = axis_shift
        nb = pad[1 + dy:pad.shape[0] - 1 + dy, 1 + dz:pad.shape[1] - 1 + dz,
                 1 + dx:pad.shape[2] - 1 + dx]
        face = solid & ~nb
        if dy == -1:
            face[0] = False                     # the underside of the bottom layer
        key = np.where(face, grid, -1)
        prev = np.roll(key, 1, axis=run_axis)
        if run_axis == 2:
            prev[:, :, 0] = -2
        else:
            prev[:, 0, :] = -2
        n += int((face & (key != prev)).sum())
    return n


def shade(rgb, f):
    return tuple(min(255, int(c * f)) for c in rgb)


def iso(grid, sheet, mirror, scale=5):
    if mirror:
        grid = grid[:, :, ::-1]
    ny, nz, nx = grid.shape
    solid = grid >= 0
    pad = np.pad(solid, 1)
    w = (nx + nz) * scale + 8
    h = (nx + nz) * scale // 2 + ny * scale + 8
    img = Image.new("RGB", (w, h), (28, 26, 36))
    draw = ImageDraw.Draw(img)
    ox, oy = nz * scale + 4, ny * scale + 4

    def P(x, y, z):
        return (ox + (x - z) * scale, oy + (x + z) * scale / 2 - y * scale)

    seen = solid & ~(pad[2:, 1:-1, 1:-1] & pad[1:-1, 2:, 1:-1] & pad[1:-1, 1:-1, 2:])
    order = sorted(zip(*np.nonzero(seen)), key=lambda v: (v[2] + v[1], v[0]))
    for y, z, x in order:
        r, g, b = sheet[grid[y, z, x]]
        if not pad[y + 2, z + 1, x + 1]:
            draw.polygon([P(x, y + 1, z), P(x + 1, y + 1, z), P(x + 1, y + 1, z + 1),
                          P(x, y + 1, z + 1)], fill=(r, g, b))
        if not pad[y + 1, z + 2, x + 1]:
            draw.polygon([P(x, y, z + 1), P(x + 1, y, z + 1), P(x + 1, y + 1, z + 1),
                          P(x, y + 1, z + 1)], fill=shade((r, g, b), 0.80))
        if not pad[y + 1, z + 1, x + 2]:
            draw.polygon([P(x + 1, y, z), P(x + 1, y, z + 1), P(x + 1, y + 1, z + 1),
                          P(x + 1, y + 1, z)], fill=shade((r, g, b), 0.62))
    return img


def elevation(grid, sheet, scale=8):
    """Square on from the south: the first voxel a ray going north meets."""
    ny, nz, nx = grid.shape
    img = Image.new("RGB", (nx * scale, ny * scale), (28, 26, 36))
    px = img.load()
    for y in range(ny):
        for x in range(nx):
            col = grid[y, ::-1, x]
            hit = np.nonzero(col >= 0)[0]
            if len(hit):
                depth = hit[0]
                rgb = shade(sheet[col[depth]], max(0.45, 1 - depth * 0.035))
                for dy in range(scale):
                    for dx in range(scale):
                        px[x * scale + dx, (ny - 1 - y) * scale + dy] = rgb
    return img


def check():
    png = Image.open(SHEET).convert("RGB")
    assert png.size == (8, len(COLORS)), png.size
    sheet = [png.getpixel((i % 8, i // 8)) for i in range(8 * len(COLORS))]
    lua = LuaRuntime(unpack_returned_tuples=True)
    kit = lua.eval("function(p) return assert(loadfile(p))() end")(
        (ROOT / "lib/LavenderCivicKit.lua").as_posix())
    sp = lua.table(W=8, H=len(COLORS))
    plot = lua.eval("function() local t = {} for r = 1, 8 do t[r] = {1,1,1,1,1,1,1,1} end return t end")()
    OUT.mkdir(exist_ok=True)
    for tid in ("pokecenter", "pokemart"):
        model = kit.model(sp, lua.table(id=tid, tiles=plot))
        assert model is not None and not isinstance(model, tuple), model
        grid = voxels(model)
        solid = grid >= 0
        # the warp lane: nothing below head height stands in the door's cell
        lane = solid[1:18, 56:64, 18:30]
        assert not lane.any(), f"{tid}: {int(lane.sum())} voxels stand in the door's lane"
        assert solid[0, 56:64, 18:30].all(), f"{tid}: the threshold has a hole in it"
        # nothing reaches past the plot except overhead, to the south
        assert not solid[:18, 64:, :].any(), f"{tid}: something stands on the street"
        ch = model.chimney
        assert ch and not solid[min(int(ch.y), grid.shape[0] - 1), int(ch.z), int(ch.x)], \
            f"{tid}: the chimney's mouth is blocked"
        quads = count_quads(grid)
        print(f"{tid}: {int(solid.sum())} voxels, top {int(np.nonzero(solid)[0].max())}, "
              f"~{quads} quads before AO splits")
        assert quads < 16000, f"{tid}: over budget (a cottage is 6k)"
        iso(grid, sheet, False).save(OUT / f"civic_{tid}_se.png")
        iso(grid, sheet, True).save(OUT / f"civic_{tid}_sw.png")
        elevation(grid, sheet).save(OUT / f"civic_{tid}_south.png")
    tower = lua.eval("function(p) return assert(loadfile(p))() end")(
        (ROOT / "lib/LavenderTowerKit.lua").as_posix())
    wide = lua.eval("function() local t = {} for r = 1, 8 do t[r] = {1,1,1,1,1,1,1,1,1,1,1,1} end return t end")()
    model = tower.model(sp, lua.table(id="pokemon_tower", tiles=wide))
    assert model is not None and not isinstance(model, tuple), model
    grid = voxels(model)
    solid = grid >= 0
    assert int(model.ytop) <= 238, "ShadowMap.HEIGHT is 240"
    assert model.haunt and len(list(model.haunt.wisps.values())) >= 8, "the wisps' sources"
    assert not solid[5:30, 54:, 45:59].any(), "the portal is walled up"   # grid is offset by xmin/zmin = -4
    quads = count_quads(grid)
    print(f"pokemon_tower: {int(solid.sum())} voxels, top {int(np.nonzero(solid)[0].max())}, "
          f"~{quads} quads before AO splits")
    assert quads < 40000, "over budget (lib/TowerKit.lua's is 24.5k)"
    iso(grid, sheet, False, 4).save(OUT / "civic_tower_se.png")
    iso(grid, sheet, True, 4).save(OUT / "civic_tower_sw.png")
    elevation(grid, sheet, 5).save(OUT / "civic_tower_south.png")
    bad = kit.model(sp, lua.table(id="gabled_cottage", tiles=plot))
    assert isinstance(bad, tuple) and bad[0] is None, "another template must be refused"
    print("PASS ->", OUT / "civic_*.png")


if __name__ == "__main__":
    if "--write" in sys.argv:
        write()
    check()
