"""The Lavender homes' material sheet, a check, and a 3-second preview.

  python tools/lavender_home.py --write     (re)author the 8x32 sheet
  python tools/lavender_home.py             check the kit + render previews

Runs the REAL lib/LavenderHomeKit.lua under lupa; no game, no save. The
preview (tools/_kit_out/lavender_home_<n>.png) is geometry and flat colour
from the Mart's camera pitch -- light, AO and exposure only exist in game.
"""
import sys
from pathlib import Path

from lupa import LuaRuntime
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SHEET = ROOT / "assets/buildings/lavender_home.png"
OUT = ROOT / "tools/_kit_out"
# one row per material, in lib/LavenderHomeKit.lua's order
COLORS = [
    (226, 212, 200), (168, 164, 180), (214, 200, 170), (176, 156, 196),  # plasters, parchment, wainscot
    (176, 128, 84), (96, 66, 56), (58, 42, 44), (236, 228, 214),         # oak, walnut, dark, trim
    (196, 214, 236), (150, 118, 186), (62, 52, 84), (158, 58, 62),       # sky, curtains, book red
    (66, 112, 84), (62, 84, 142), (196, 150, 70), (240, 234, 216),       # books, paper
    (170, 98, 76), (74, 124, 82), (140, 122, 84), (164, 124, 204),       # clay, leaf, dry, lavender
    (244, 240, 248), (255, 206, 120), (226, 218, 196), (52, 104, 78),    # white, light, bone, felt
    (198, 160, 84), (46, 46, 56), (120, 88, 160), (142, 48, 58),         # brass, iron, rugs
    (222, 206, 176), (226, 140, 160), (84, 164, 168), (236, 200, 92),    # cream, pink, teal, yellow
]
TILES = """38 41 38 41 0 0 45 46 0 0 36 36 0 0 38 41
14 15 14 15 0 0 61 62 0 0 52 52 0 0 48 49
14 15 14 15 1 1 1 1 1 1 1 1 1 1 48 49
30 31 30 31 1 1 1 1 1 1 1 1 1 1 30 31
1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
1 1 1 1 2 3 38 39 39 41 2 3 1 1 1 1
1 1 1 1 18 19 54 47 47 57 18 19 1 1 1 1
1 1 1 1 2 3 54 47 47 57 2 3 1 1 1 1
1 1 1 1 18 19 60 58 58 59 18 19 1 1 1 1
1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
10 11 1 1 1 1 1 1 1 1 1 1 1 1 10 11
8 9 1 1 1 1 1 1 1 1 1 1 1 1 8 9
26 27 1 1 4 4 4 4 1 1 1 1 1 1 26 27
24 25 1 1 20 20 20 20 1 1 1 1 1 1 24 25"""


def main():
    if "--write" in sys.argv:
        img = Image.new("RGBA", (8, len(COLORS)))
        for row, rgb in enumerate(COLORS):
            for col in range(8):
                f = 0.86 + col * 0.03
                img.putpixel((col, row), tuple(min(255, round(c * f)) for c in rgb) + (255,))
        img.save(SHEET)
        print("wrote", SHEET)

    sheet = Image.open(SHEET).convert("RGB")
    assert sheet.size == (8, 32), sheet.size
    lua = LuaRuntime(unpack_returned_tuples=True)
    kit = lua.eval("function(p) return assert(loadfile(p))() end")(
        (ROOT / "lib/LavenderHomeKit.lua").as_posix())
    grid = [[int(n) for n in ln.split()] for ln in TILES.splitlines()]
    to_lua = lua.eval("function(rows) local t = {} for r in python.iter(rows) do "
                      "local o = {} for c in python.iter(r) do o[#o+1] = c end "
                      "t[#t+1] = o end return t end")
    room_t = lua.table(home="room", tiles=to_lua(grid))
    stool_t = {w: lua.table(home="stools" + w, tiles=to_lua([r[c:c + 2] for r in grid[6:10]]))
               for w, c in (("W", 4), ("E", 10))}
    sp = lua.table(W=8, H=32)
    OUT.mkdir(exist_ok=True)
    seen = set()
    for map_id in ("MR_FUJIS_HOUSE", "LAVENDER_CUBONE_HOUSE", "NAME_RATERS_HOUSE"):
        room = kit.model(sp, room_t, map_id)
        seats = {w: kit.model(sp, st, map_id) for w, st in stool_t.items()}
        assert room and all(seats.values()), map_id
        assert all(sum(1 for v in s.claimMask.values() if v) == 8 for s in seats.values())
        assert not any(room.claimMask[r * 16 + c + 1] and grid[r][c] in (1, 4, 20, 2, 3, 18, 19)
                       for r in range(16) for c in range(16))
        # oblique painter: back to front, low to high; top face + south face
        S, H = 6, 30
        img = Image.new("RGB", (138 * S, (128 + H) * S // 2 + H * S), (16, 14, 22))
        px = img.load()
        count, sig = 0, 0

        def put(x, y, z, i, top):
            r, g, b = sheet.getpixel((i % 8, i // 8))
            if not top:
                r, g, b = int(r * .72), int(g * .72), int(b * .72)
            x0 = (x + 5) * S
            y0 = (z * S) // 2 + (H - y) * S - (S if top else 0)
            for dy in range(S // 2 if top else S):
                for dx in range(S):
                    if 0 <= y0 + dy < img.height:
                        px[x0 + dx, y0 + dy] = (r, g, b)

        for z in range(0, 128):
            for y in range(0, H):
                for x in range(-5, 133):
                    i = room.at(x, y, z)
                    if i is None and 48 <= z < 80 and y <= 13:
                        if 32 <= x < 48:
                            i = seats["W"].at(x - 32, y, z - 48)
                        elif 80 <= x < 96:
                            i = seats["E"].at(x - 80, y, z - 48)
                    if i is None:
                        continue
                    assert 0 <= i < 256 and i == int(i), (x, y, z, i)
                    i = int(i)
                    count += 1
                    sig = (sig + (i + 1) * (x + 7 * y + 31 * z)) % 2147483647
                    put(x, y, z, i, False)
                    put(x, y, z, i, True)
        # nothing stands above standH where the player's feet go
        assert all(s.at(x, kit.SEAT_H, z) is None for s in seats.values()
                   for x in (7, 8) for z in (7, 8, 23, 24)), "seat above standH at its centre"
        assert sig not in seen, "two homes came out identical"
        seen.add(sig)
        name = OUT / f"lavender_home_{map_id}.png"
        img.save(name)
        print(f"{map_id}: {count} voxels  -> {name}")
    assert kit.model(sp, room_t, "PALLET_HOUSE")[0] is None
    print("PASS: three distinct homes, claims off the floor, seats at standH, other maps refused")


if __name__ == "__main__":
    main()
