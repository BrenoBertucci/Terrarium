"""Vermilion's three homes: the material sheet, a check, and a quick preview.

  python tools/vermilion_home.py --write     (re)author the 8x32 sheet
  python tools/vermilion_home.py             check the kit + render previews

The same bench as tools/lavender_home.py (whose plan this borrows: every town
house in Kanto is that one 16x16 room). Runs the REAL lib/VermilionHomeKit.lua
under lupa; no game, no save. The preview (tools/_kit_out/vermilion_home_<MAP>.png)
is geometry and flat colour from the dollhouse pitch.
"""
import sys
from pathlib import Path

from lupa import LuaRuntime
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from interior_plan import plan  # noqa: E402
from lavender_home import TILES  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SHEET = ROOT / "assets/buildings/vermilion_home.png"
OUT = ROOT / "tools/_kit_out"
# one row per material, in lib/VermilionHomeKit.lua's order
COLORS = [
    (240, 236, 224), (226, 186, 120), (250, 226, 150), (142, 168, 190),   # whitewash, ochre, butter, grey-blue boards
    (74, 122, 92), (84, 132, 196), (176, 160, 140), (196, 144, 88),       # green panel, blue dado, driftwood, oak
    (98, 64, 48), (52, 40, 40), (246, 242, 234), (190, 220, 242),         # walnut, dark, trim, sky
    (214, 204, 176), (196, 166, 110), (50, 50, 60), (214, 172, 84),       # net, rope, iron, brass
    (204, 58, 54), (242, 132, 56), (44, 62, 116), (72, 170, 170),         # red, orange, navy, teal
    (246, 206, 84), (244, 238, 222), (196, 204, 212), (84, 128, 172),     # yellow, paper, fish silver, fish blue
    (84, 146, 84), (206, 176, 118), (56, 118, 84), (170, 52, 56),         # leaf, straw, baize, carpet red
    (236, 222, 190), (236, 150, 168), (170, 214, 210), (255, 210, 124),   # cream, pink, glass jar, lamp
]
MAPS = ("VERMILION_OLD_ROD_HOUSE", "VERMILION_TRADE_HOUSE", "VERMILION_PIDGEY_HOUSE", "POKEMON_FAN_CLUB")
# per plan: the room template's name, the two seat templates (name, tile column), the
# seats' x in the room, and the tiles that are open floor
PLANS = {"house": ("room", (("stoolsW", 4), ("stoolsE", 10)), (32, 80), (1, 4, 20), (2, 3, 18, 19)),
         "club": ("club", (("couchW", 2), ("couchE", 12)), (16, 96), (31, 70, 71), (59, 60, 61, 62))}


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
    kit = lua.eval("function(p) return assert(loadfile(p))() end")((ROOT / "lib/VermilionHomeKit.lua").as_posix())
    house_grid = [[int(n) for n in ln.split()] for ln in TILES.splitlines()]
    club_grid = plan("POKEMON_FAN_CLUB")[1]
    to_lua = lua.eval("function(rows) local t = {} for r in python.iter(rows) do "
                      "local o = {} for c in python.iter(r) do o[#o+1] = c end "
                      "t[#t+1] = o end return t end")
    sp = lua.table(W=8, H=32)
    OUT.mkdir(exist_ok=True)
    seen = set()
    for map_id in MAPS:
        grid = club_grid if map_id == "POKEMON_FAN_CLUB" else house_grid
        room_name, seat_names, seat_x, FLOOR, SEAT = PLANS["club" if grid is club_grid else "house"]
        room_t = lua.table(home=room_name, tiles=to_lua(grid))
        stool_t = {"WE"[k]: lua.table(home=n, tiles=to_lua([r[c:c + 2] for r in grid[6:10]]))
                   for k, (n, c) in enumerate(seat_names)}
        room = kit.model(sp, room_t, map_id)
        seats = {w: kit.model(sp, st, map_id) for w, st in stool_t.items()}
        assert room and all(seats.values()), map_id
        assert all(sum(1 for v in s.claimMask.values() if v) == 8 for s in seats.values())
        assert not any(room.claimMask[r * 16 + c + 1] and grid[r][c] in FLOOR + SEAT
                       for r in range(16) for c in range(16))
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
                    if i is None and 48 <= z < 80 and y <= 15:
                        if seat_x[0] <= x < seat_x[0] + 16:
                            i = seats["W"].at(x - seat_x[0], y, z - 48)
                        elif seat_x[1] <= x < seat_x[1] + 16:
                            i = seats["E"].at(x - seat_x[1], y, z - 48)
                    if i is None:
                        continue
                    assert 0 <= i < 256 and i == int(i), (map_id, x, y, z, i)
                    # nothing walkable carries furniture: open floor, the mat, the way round the table
                    if y > 0 and 0 <= x < 128:
                        tile = grid[z // 8][x // 8]
                        assert tile not in FLOOR or z <= 11, (map_id, "stands on open floor", x, y, z)
                    i = int(i)
                    count += 1
                    sig = (sig + (i + 1) * (x + 7 * y + 31 * z)) % 2147483647
                    put(x, y, z, i, False)
                    put(x, y, z, i, True)
        assert all(s.at(x, kit.SEAT_H, z) is None for s in seats.values()
                   for x in (7, 8) for z in (7, 8, 23, 24)), "seat above standH at its centre"
        # the pigeon post keeps the table's north-east quarter bare: the LETTER lies there
        if map_id == "VERMILION_PIDGEY_HOUSE":
            assert all(room.at(x, 10, z) is None for x in range(64, 80) for z in range(48, 64))
        assert sig not in seen, "two homes came out identical"
        seen.add(sig)
        name = OUT / f"vermilion_home_{map_id}.png"
        img.save(name)
        print(f"{map_id}: {count} voxels  -> {name}")
    assert kit.model(sp, room_t, "MR_FUJIS_HOUSE")[0] is None
    assert kit.model(sp, room_t, "VERMILION_TRADE_HOUSE")[0] is None      # the club's template, a house's map
    print("PASS: four distinct homes, nothing on the open floor, seats at standH, other maps refused")


if __name__ == "__main__":
    main()
