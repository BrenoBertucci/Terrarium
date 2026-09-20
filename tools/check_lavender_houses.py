"""Author the tiny material sheet and check the real Lua building path.

python tools/check_lavender_houses.py [--write-palette]
Requires the existing Pillow/lupa tools; no game process or save is touched.
"""
import sys
from pathlib import Path

from lupa import LuaRuntime
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PALETTE = ROOT / "assets/buildings/lavender_materials.png"
# Limestone, mortar, limewash, trim, violet slate, flashing, walnut,
# grain, wrought iron, glass, amber, moss, leaves, lavender, clay, recess.
COLORS = [
    (133, 130, 143), (86, 82, 96), (179, 168, 178), (205, 195, 190),
    (87, 69, 112), (59, 51, 76), (82, 62, 66), (52, 42, 49),
    (57, 58, 69), (110, 151, 162), (235, 181, 103), (75, 89, 77),
    (75, 99, 86), (145, 115, 178), (114, 88, 96), (36, 33, 48),
]


def main():
    if "--write-palette" in sys.argv:
        image = Image.new("RGBA", (8, 16))
        for row, rgb in enumerate(COLORS):
            for col in range(8):
                factor = 0.90 + col * 0.025
                image.putpixel((col, row), tuple(round(c * factor) for c in rgb) + (255,))
        image.save(PALETTE)
        print(f"Wrote {PALETTE}")

    image = Image.open(PALETTE).convert("RGBA")
    assert image.size == (8, 16)
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().root = ROOT.as_posix()
    lua.globals().palettePixel = lambda x, y: tuple(c / 255 for c in image.getpixel((int(x), int(y))))
    lua.execute(r'''
local Kit = assert(loadfile(root .. "/lib/LavenderHouseKit.lua"))()
local profile = assert(loadfile(root .. "/data/voxel_heights.lua"))()
local cottage
for _, t in ipairs(profile.buildings.OVERWORLD) do
  if t.id == "gabled_cottage" then cottage = t end
end
assert(cottage)
local fingerprints = {}
for _, p in ipairs({{12,16}, {4,24}, {12,24}}) do
  local m = assert(Kit.model({W=8,H=16}, cottage, p[1], p[2]))
  local count, signature = 0, 0
  for y=0,m.ytop do
    for z=m.zmin,m.zmax do for x=m.xmin,m.xmax do
      local i = m.at(x,y,z)
      if i then
        assert(i >= 0 and i < 128 and i == math.floor(i), "invalid material")
        count = count + 1
        signature = (signature + (i+1)*(x+7*y+31*z)) % 2147483647
      end
    end end
  end
  assert(count > 45000 and count < 120000, "empty or oversized cottage")
  assert(not fingerprints[signature], "homes must have individual details")
  fingerprints[signature] = true
  for x=19,28 do for y=2,20 do for z=26,33 do
    assert(m.at(x,y,z) == nil, "front entrance must stay recessed")
  end end end
  assert(m.at(24,12,25), "door panel missing")
  assert(m.at(46,19,28) == nil and m.at(46,19,26), "window must have depth")
  assert(m.at(4,19,13) == nil and m.at(5,19,13), "side window must have depth")
  assert(m.at(-1,0,0) == nil and m.at(64,0,0) == nil)
  assert(m.at(2,3,2) == nil and m.at(8,3,2), "foundation corners must be rounded")
  assert(m.at(32,48,15) and m.at(2,48,15) == nil, "roof must taper on all four sides")
  assert(m.at(m.chimney.x, m.ytop, m.chimney.z) == nil, "flue sealed")
  print(string.format("geometry %d,%d: %d voxels; height %d", p[1],p[2],count,m.ytop+1))
end

-- Exercise the actual selector/cache/stamp using the unmodified cottage
-- grid, with a numeric runtime map id (the name lives in map.def.id).
local image = {getWidth=function() return 8 end, getHeight=function() return 16 end,
               getDimensions=function() return 8,16 end,
               getPixel=function(_,x,y) return palettePixel(x,y) end}
love = {graphics={newImage=function() return {setFilter=function() end} end}}
local V = {path=root}
function V.data() return {buildings={OVERWORLD={cottage}}} end
function V.require(name)
  if name == "ImageCache" then return {get=function() return image end} end
  if name == "LavenderHouseKit" then return Kit end
  if name == "BuildBudget" then return {tick=function() end} end
  error("unexpected require " .. name)
end
local Buildings = assert(loadfile(root .. "/lib/Buildings.lua"))(V)
local function build(id)
  local S = {tileAt={},shapeAt={},skip={},ground={},objectQuads={}}
  for _,p in ipairs({{12,16}, {4,24}, {12,24}}) do
    for r,row in ipairs(cottage.tiles) do for c,tile in ipairs(row) do
      S.tileAt[(p[2]+r-1+64)*4096+p[1]+c-1+64] = tile
    end end
  end
  local map = {id=4,def={id=id,width=10,height=9},
               tileset={id="OVERWORLD",imageWidth=128,imageHeight=128}}
  local atlas = {getPixel=function(_,x,y)
    local v = ((x%8 == 0 or y%8 == 0) and 0 or 0.7)
    return v,v,v,1
  end}
  Buildings.build(S,map,atlas,16)
  return S,map
end
-- Visit another city first, then Lavender, then that city again: no cache
-- pollution in either order, even though all three reuse one template.
local before = build("FUCHSIA_CITY")
assert(not before.spriteQuads, "other city's houses changed")
local S,map = build("LAVENDER_TOWN")
assert(not Buildings.lastError, tostring(Buildings.lastError))
assert(S.spriteQuads and #S.spriteQuads > 1000, "new exteriors were not stamped")
for _, q in ipairs(S.spriteQuads) do assert(q.tex == Kit.SHEET) end
assert(#S.chimneys == 3)
assert(Buildings.tallAt(map,6,8) >= 55)
local count=0
for k,v in pairs(Buildings.stats()) do
  if k:find("@lavender:",1,true) then
    count=count+1
    assert(v.quads < 15000, "excessive exterior geometry")
    print(k .. ": " .. v.quads .. " quads")
  end
end
assert(count==3, "expected three placement-local models")
local after=build("FUCHSIA_CITY")
assert(not after.spriteQuads and #after.objectQuads == #before.objectQuads)
print("PASS: three distinct homes, recessed doors/windows, smoke, map isolation and cache order")
''')


if __name__ == "__main__":
    main()
