"""Headless check of lib/FenceKit.lua: python tests/fence_kit_check.py"""
from pathlib import Path
from lupa import LuaRuntime
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
lua = LuaRuntime(unpack_returned_tuples=True)
Kit = lua.eval("function(p) return assert(loadfile(p))({}) end")((ROOT / "lib/FenceKit.lua").as_posix())
sheet = Image.open(ROOT / "assets/buildings/fence_kit.png")
assert sheet.size == (32, 16)

# an east-west run of three cells, a sign after it
def tiles(tx, ty):
    if 0 <= tx < 6 and 0 <= ty < 2:
        return (14, 14, 85, 85)[(ty % 2) * 2 + tx % 2]
    return 57
assert [Kit.signature(tiles, x, 0) for x in (0, 2, 4)] == ["0100", "0101", "0001"]
mid = Kit.model(lua.table(W=32), "0101")
box = [(x, y, z) for x in range(16) for y in range(int(mid.ytop) + 1) for z in range(16) if mid.at(x, y, z) is not None]
assert all(0 <= mid.at(*v) < 32 * 16 for v in box)                 # every voxel wears a texel of the sheet
assert all(sheet.getpixel((mid.at(*v) % 32, mid.at(*v) // 32))[:3] != (0, 0, 0) for v in box), "a black texel"
assert mid.at(0, Kit.TOP, 7) is not None and mid.at(15, Kit.TOP, 8) is not None   # rails reach both edges
assert mid.at(7, Kit.TOP, 0) is None                               # and none runs north
# the brace's two arms meet in the middle of the gap, at the cell's edge
# the brace is an X, a voxel a column and two thick: it fills the gap between the rails at the post
col = [y for y in range(16) if mid.at(10, y, 8) is not None]
assert Kit.TOP - 1 in col and Kit.LOW + 2 in col, col
assert Kit.signature(tiles, 0, 0, lambda x, y: x < 0) == "0101"          # ...unless a map is joined there
end = Kit.model(lua.table(W=32), "0100")
assert end.at(2, Kit.TOP, 7) is None and end.at(12, Kit.TOP, 7) is not None  # a run ends in a post
print("fence kit ok:", len(box), "voxels in a run cell")
