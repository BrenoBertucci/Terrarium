"""Paint assets/buildings/fence_kit.png, the timber lib/FenceKit.lua wears.

    python tools/fence_sheet.py

32x16, one texel a voxel, drawn from nothing (no ROM art). FenceKit.R names
the regions:
  (0..15, 0..3)    a RAIL's four courses, grain running along x: the top rail's
                   sunlit top and its underside, the low rail's two
  (0..15, 4..5)    the two arms of the cross-brace
  (16..19, 0..15)  a POST's face, grain running up it; row 15 is its foot
                   (tarred), row 2 its iron collar
  (20..23, 0..3)   the post's END GRAIN, rings and all, under its cap
  (24..25, 0)      iron, and iron catching the light
"""
from pathlib import Path
import random

from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "assets/buildings/fence_kit.png"
WOOD = [(176, 104, 54), (160, 90, 46), (192, 120, 64), (146, 80, 42)]
GRAIN = (112, 62, 34)
KNOT = (78, 44, 28)
BLEACHED = [(214, 168, 110), (200, 152, 96)]
TAR = [(74, 54, 44), (62, 46, 40)]
IRON, IRON_HI = (48, 46, 56), (96, 94, 108)
HEART = (196, 138, 84)


def main():
    rng = random.Random(7)
    img = Image.new("RGBA", (32, 16), (0, 0, 0, 255))

    def put(x, y, c):
        img.putpixel((x, y), c + (255,))

    # rails: long grain streaks that carry on for a few texels, a knot, nail heads by the post
    for row in range(6):
        streak = 0
        for x in range(16):
            base = WOOD[(row * 2 + 1) % 4] if row not in (0, 2) else BLEACHED[row // 2 % 2]
            if row in (4, 5):                   # the brace: plain, so its line reads
                put(x, row, WOOD[2 if row == 4 else 1])
                continue
            if streak == 0 and rng.random() < 0.22:
                streak = rng.choice([2, 3, 4])
            c = base
            if streak:
                c = GRAIN if row not in (0, 2) else tuple(v - 40 for v in base)
                streak -= 1
            put(x, row, c)
        if row < 4:
            put(rng.choice([3, 4, 11, 12]), row, KNOT)
    for row in (1, 3):
        put(0, row, IRON), put(15, row, IRON)
    # a post: grain up it, darker down its edges, tarred where it meets the ground
    for y in range(16):
        for x in range(4):
            c = WOOD[(x * 3 + y // 5) % 4]
            if x in (0, 3):
                c = tuple(int(v * 0.86) for v in c)
            if rng.random() < 0.14:
                c = GRAIN
            if y >= 12:
                c = TAR[(x + y) % 2]
            if y == 11:
                c = tuple(int(v * 0.7) for v in WOOD[3])
            if y == 2:
                c = IRON_HI if x in (1, 2) else IRON
            put(16 + x, y, c)
    put(17, 7, KNOT)
    # end grain: rings round a pale heart
    for y in range(4):
        for x in range(4):
            ring = max(abs(x - 1.5), abs(y - 1.5))
            put(20 + x, y, HEART if ring < 1 else (BLEACHED[1] if (x + y) % 2 else WOOD[2]))
    put(24, 0, IRON), put(25, 0, IRON_HI)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
