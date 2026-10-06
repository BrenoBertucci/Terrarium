"""Celadon's rooms: the swatch sheet, and a check of the kit under lupa.

  python tools/celadon_rooms.py --write    (re)author assets/buildings/celadon_rooms.png
  python tools/celadon_rooms.py            build one cell of every theme and check it

lib/CeladonRoomKit.lua reads each room from the classes Structures gives its tiles
at RUN time, so there is no plan to preview here: the look is checked in game
(tests/run_celadon_rooms.cmd). This only proves every theme builds, every texel is
on the sheet, and a model claims exactly its solid tiles.
"""
import sys
from pathlib import Path

from lupa import LuaRuntime
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SHEET = ROOT / "assets/buildings/celadon_rooms.png"
# one row per material, in lib/CeladonRoomKit.lua's order
COLORS = [
    (244, 236, 214), (250, 250, 250), (168, 214, 190), (96, 150, 128), (84, 132, 204), (196, 220, 244), (44, 60, 116), (132, 84, 190),
    (74, 50, 110), (44, 42, 52), (236, 192, 88), (214, 62, 62), (130, 40, 56), (244, 160, 186), (176, 232, 208), (96, 170, 96),
    (56, 110, 70), (196, 146, 90), (112, 74, 52), (68, 46, 40), (170, 174, 184), (98, 102, 114), (190, 190, 186), (214, 124, 84),
    (244, 150, 60), (248, 214, 90), (96, 226, 240), (206, 212, 222), (196, 204, 140), (110, 156, 96), (176, 176, 170), (240, 90, 200),
]


def main():
    if "--write" in sys.argv:
        img = Image.new("RGBA", (8, len(COLORS)))
        for row, rgb in enumerate(COLORS):
            for col in range(8):
                f = 0.84 + col * 0.035
                img.putpixel((col, row), tuple(min(255, round(c * f)) for c in rgb) + (255,))
        img.save(SHEET)
        print("wrote", SHEET)
    assert Image.open(SHEET).size == (8, 32)
    lua = LuaRuntime(unpack_returned_tuples=True)
    kit = lua.eval("function(p) return assert(loadfile(p))() end")((ROOT / "lib/CeladonRoomKit.lua").as_posix())
    sp = lua.table(W=8, H=32)
    # a cell with a back wall over a counter beside a case, floor south of it, a table to the east
    plan = {(0, 0): ("wall", 16), (1, 0): ("wall", 16), (0, 1): ("counter", 8), (1, 1): ("bookcase", 32),
            (2, 0): ("table", 12), (2, 1): ("table", 12), (0, 2): ("ground", 0), (1, 2): ("stool", 8),
            (0, -1): ("wall", 16), (1, -1): ("wall", 16), (-1, 0): ("wall", 16), (-1, 1): ("ground", 0)}
    # (a Python tuple reaches Lua as ONE value: the reader has to be a Lua function)
    mk = lua.eval("function(t) return function(x, y) local e = t[x .. ':' .. y] if e then return e[1], e[2] end end end")
    class_at = mk(lua.table_from({f"{x}:{y}": lua.table_from(list(v)) for (x, y), v in plan.items()}))
    const = lambda c: lua.eval("function(c) return function() return c, 0 end end")(c)  # noqa: E731
    n = 0
    for map_id, theme in kit.MAPS.items():
        key = kit.spec(map_id, class_at, 0, 0)
        low = theme in ("roof", "terrace")                       # open to the sky: parapets, not walls
        wall = "W14" if low else "W28"
        assert key and key.startswith(f"{theme}|{wall},{wall},C8,B32,"), key
        m = kit.model(sp, key)
        assert m is not None and not isinstance(m, tuple), (map_id, m)
        assert [m.claimMask[i] for i in range(1, 5)] == [True, True, True, True]
        for x in range(-1, 17):
            for z in range(-1, 17):
                for y in range(int(m.ytop) + 1):
                    v = m.at(x, y, z)
                    assert v is None or v == -1 or 0 <= v < 256, (map_id, x, y, z, v)
        assert (m.at(4, 27, 4) is not None) == (not low) and m.at(4, 8, 12) is None and m.at(4, 7, 12) is not None
        assert m.at(16, 3, 4) == -1                               # the table next door is a phantom
        floor_key = kit.spec(map_id, const("ground"), 2, 4)
        f = kit.model(sp, floor_key)
        assert f.at(3, 0, 3) is not None and f.at(3, 1, 3) is None and not any(f.claimMask[i] for i in range(1, 5))
        n += 1
    assert kit.spec("PALLET_TOWN", class_at, 0, 0) is None
    assert kit.spec("CELADON_DINER", const("void"), 0, 0) is None
    print(f"PASS: {n} rooms build, claim their solids, lay their floors, and leave other maps alone")


if __name__ == "__main__":
    main()
