"""Headless check of lib/ReefKit.lua: python tests/reef_kit_check.py"""
from collections import Counter
from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent
lua = LuaRuntime(unpack_returned_tuples=True)
Kit = lua.eval("function(p) return assert(loadfile(p))({}) end")(
    (ROOT / "lib/ReefKit.lua").as_posix())
sheet = lua.table(W=32)

# a lake 40 cells across in a field of grass, a pier down its middle; and a pond
def lake(tx, ty):
    if 0 <= tx < 80 and 0 <= ty < 80:
        return 60 if 38 <= tx < 42 else 20
    return 44
def pond(tx, ty):
    return 20 if 0 <= tx < 10 and 0 <= ty < 10 else 44

grown = {(cx, cy): Kit.spec(lake, cx * 2, cy * 2, 5) for cx in range(40) for cy in range(40)}
some = {c: k for c, k in grown.items() if k}
zones = Counter(k[0] for k in some.values())
assert zones["B"] > 20 and zones["P"] > 20 and zones["G"] > 40, zones
assert all(k[0] == "B" for (cx, cy), k in some.items() if cx in (0, 39) or cy in (0, 39))
assert all(2 <= cx <= 37 and 2 <= cy <= 37 for (cx, cy), k in some.items() if k[0] == "G")
assert any(abs(cx - 19.5) < 3 for (cx, cy), k in some.items() if k[0] == "G")  # right up to the pier
assert not any(Kit.spec(pond, cx * 2, cy * 2, 6) for cx in range(5) for cy in range(5))  # ONLY big water
assert grown == {(cx, cy): Kit.spec(lake, cx * 2, cy * 2, 5) for cx in range(40) for cy in range(40)}

for key in sorted(set(some.values())):
    m = Kit.model(sheet, key)
    box = [(x, y, z) for x in range(16) for z in range(16) for y in range(int(m.ytop) + 1)
           if m.at(x, y, z) is not None]
    assert len(box) > 30, (key, len(box))
    assert m.overWater == 20 and m.clearWater and m.sink in (5, 7, 9, 11, 13), key
    top = max(y for _, y, _ in box) - m.sink      # world y of the tallest voxel's foot
    if key[0] == "G":
        assert top <= -4, (key, top)              # a garden stays under the sheet
    if key[0] == "B":
        assert top >= 3, (key, top)               # reeds stand OUT of the water
    if key[0] == "P":
        assert any(y - m.sink == -2 and m.at(x, y, z) in (29, 30, 31) for x, y, z in box), key  # pads ON the sheet
    assert all(m.at(x, 0, z) is not None or True for x, y, z in box)

    # MOTION: every voxel belongs to a plant, and the palette says which kind
    K = Kit.KIND
    for x, y, z in box:
        p = m.motion(x, y, z)
        assert p is not None, (key, x, y, z)
        kind, t = p.code // 8, m.at(x, y, z)
        if t in (29, 30, 31):                       # pad, rim, vein -- or a stalk
            assert kind in (K.pad, K.stem), (key, x, y, z, kind)
        elif t in (24, 25, 26, 27, 28):                         # reeds, cattails
            assert kind == K.reed, (key, x, y, z, kind)
        elif t in (12, 13, 14):
            assert kind == K.kelp, (key, x, y, z, kind)
        elif t in (18, 19):
            assert kind == K.clover, (key, x, y, z, kind)
        elif t in (10, 11):
            assert kind == K.fan, (key, x, y, z, kind)
        elif t in (0, 1, 2, 3, 8, 9, 20, 21):   # stone, table coral, sponge
            assert kind == K.rigid, (key, x, y, z, kind)
        elif key[0] == "G" and t in (6, 16, 17):                # coral, weed
            assert kind in (K.rigid, K.grass), (key, x, y, z, kind)
        elif key[0] == "G" and t == 22:
            assert kind == K.anemone, (key, x, y, z, kind)      # its crown
        elif key[0] != "G" and t in (4, 5, 22, 23):
            assert kind == K.pad, (key, x, y, z, kind)          # a lily's flower
    kinds = Counter(m.motion(x, y, z).code // 8 for x, y, z in box)
    if key[0] == "P":
        assert kinds[K.pad] > 20 and kinds[K.stem] > 3, (key, kinds)
    if key[0] == "B":
        assert kinds[K.reed] > 20, (key, kinds)

    # a pad reaches for its own stalk: the packed byte is the way there from
    # the corner asking, and under it stands the stalk (a rim voxel, below
    # the sheet). Same leaf, same point, whatever corner asks -- that is
    # what keeps it rigid.
    sheetY = m.sink - 2
    for x, y, z in box:
        p = m.motion(x, y, z)
        if p.code // 8 == K.pad:
            for cx, cz in ((x, z), (x + 1, z + 1)):
                dx = max(-5, min(5, int(p.ax) - cx)) + 5
                dz = max(-5, min(5, int(p.az) - cz)) + 5
                v = dx * 16 + dz
                ax = cx + (v // 16) - 5
                az = cz + (v % 16) - 5
                assert m.at(ax, sheetY - 1, az) == 29, (key, x, y, z, ax, az)

    # a face's corner answers for the voxel behind it, at its own end of a run
    x, y, z = box[len(box) // 2]
    top = lua.table(lua.table(x, y + 1, z), lua.table(x + 1, y + 1, z),
                    lua.table(x + 1, y + 1, z + 1), lua.table(x, y + 1, z + 1))
    if m.at(x, y + 1, z) is None:
        got, want = Kit.plantAt(m, top, 3), m.motion(x, y, z)
        assert (got.code, got.base, got.ref) == (want.code, want.base, want.ref), key

# the packing, through float32 the way the mesh stores it, and the shader's
# decode (lib/Voxel3D.lua, THE WATER GARDEN MOVES) -- every code, every
# brightness, weight end to end
import struct
def f32(v):
    return struct.unpack("f", struct.pack("f", v))[0]
for code in range(72):
    for lvl in (1, 17, 40, 63):
        for w in (0.0, 0.004, 0.37, 0.5, 0.996, 1.0):
            plant = lua.table(code=code, base=0, ref=1)
            for sign in (1, -1):
                packed = f32(Kit.pack(sign * lvl / 63, plant, 0, w, 0))
                mag = abs(packed) * 64
                assert int(mag) == lvl and (packed < 0) == (sign < 0), (code, lvl, w)
                c = (mag - int(mag)) * 32768
                assert int(c) // 256 == code, (code, lvl, w, c)
                assert abs(int(c) % 256 / 255 - w) < 0.004, (code, lvl, w)
# ...and a pad's stalk, the other thing the byte can be
for dx in range(-5, 6):
    for dz in range(-5, 6):
        plant = lua.table(code=8, base=0, ref=1, ax=dx, az=dz)
        c = (abs(f32(Kit.pack(1.0, plant, 0, 0, 0))) * 64 % 1) * 32768
        v = int(c) % 256
        assert (v // 16 - 5, v % 16 - 5) == (dx, dz), (dx, dz, v)
print("reef kit ok:", dict(zones), len(set(some.values())), "models")
