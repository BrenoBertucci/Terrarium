"""Headless check of lib/BridgeKit.lua: python tests/bridge_kit_check.py"""
from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent
lua = LuaRuntime(unpack_returned_tuples=True)
Kit = lua.eval("function(p) return assert(loadfile(p))({}) end")(
    (ROOT / "lib/BridgeKit.lua").as_posix())
G, D, C = Kit.SINK, Kit.DECK, 16
sheet = lua.table(W=32)

# a pier two cells wide running north-south through water, land to the north
def pier(tx, ty):
    if ty < 0:
        return 44
    return 60 if 0 <= tx < 4 else 20

sig = Kit.signature(pier, 0, 0)
assert sig == "lbbwlbwzWL", sig              # N E S W, NE SE SW, axis, wet, lamp
assert Kit.signature(pier, 2, 2) == "bwbbwwbzW"
m = Kit.model(sheet, sig)
assert m.at(8, G + D - 1, 8) % 1024 == 8 * 32 + 8   # boards wear the deck drawing
assert m.at(0, G + D - 1, 6) // 1024 > m.at(15, G + D - 1, 15) // 1024  # and more lamplight by the lantern
assert m.at(8, G + D, 8) is None             # and nothing stands on the way
assert m.at(8, G + D - 1, 0) is None and m.at(8, G, 0) is not None  # steps down to the land
assert all(m.at(x, y, z) is None             # THE WHOLE DECK IS WALKABLE: nothing
           for x in range(C) for z in range(C)   # stands in the cell, up to the caps
           for y in range(G + D, G + D + Kit.RAIL_H))
assert m.at(-2, 0, 1) is not None            # a pile reaches the bottom, outside the cell
assert m.at(-2, G + D + 8, 8) is not None    # a rail on the water side
assert m.at(C + 1, G + D + 8, 8) is None     # none on the bridge side
assert m.at(8, G + D - 1, C) == -1           # the next cell's boards are a phantom
assert m.at(-1, G + D - 1, 8) != -1          # the water's side has none
assert m.overWater == 20 and m.sink == G and m.lift == D
assert len(m.lights) == 1, len(m.lights)     # one post here, one lantern
assert abs(m.lights[1].x - -2) < 1e-9 and abs(m.lights[1].z - 2) < 1e-9

# a way off onto walkable land beside the pier is NEVER railed; trees are
def side_land(walk):
    tiles = lambda tx, ty: 60 if 0 <= tx < 2 else 44
    return Kit.signature(tiles, 0, 2, (lambda cx, cy: walk))
assert side_land(True)[:4] == "blbl" and side_land(False)[:4] == "btbt"
n = Kit.model(sheet, side_land(True))
assert all(n.at(x, G + D + 8, 8) is None for x in range(-5, C + 5))
assert n.at(0, G + D - 1, 8) is None and n.at(0, G, 8) is not None   # and it steps down to it
t = Kit.model(sheet, side_land(False))       # Nugget Bridge: railed, dry, claims no water
assert t.overWater is None and t.at(-2, G + D + 8, 8) is not None

# a pier head: two rails meet in ONE corner post, and both lanterns are counted once
head = Kit.model(sheet, "bwwwwwwzWL")
assert head.at(-2, G + D + 5, C + 1) is not None
assert len(head.lights) == 4, len(head.lights)   # 2 low posts + 2 shared corners, not 6
print("bridge kit ok:", sig)
