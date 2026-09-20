"""Paint assets/buildings/reef_kit.png, the palette lib/ReefKit.lua wears.

    python tools/reef_sheet.py

32x4, one texel per material, drawn from nothing (no ROM art). The order is
ReefKit.T's. Brighter than life on purpose: the water takes most of the red
back out (Voxel3D's reefOn absorbs what stands under the sheet like the bed).
"""
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "assets/buildings/reef_kit.png"
PALETTE = [
    (104, 100, 114), (158, 156, 170), (96, 156, 84), (206, 196, 158),   # 0 rock, 1 rock lit, 2 moss, 3 pebble
    (255, 96, 150), (255, 150, 190), (232, 56, 140), (255, 80, 80),    # 4 pink, 5 pink tip, 6 magenta, 7 red
    (255, 140, 50), (255, 190, 100), (170, 100, 255), (204, 152, 255),  # 8 orange, 9 orange tip, 10 fan, 11 fan rim
    (14, 118, 56), (36, 168, 66), (92, 206, 86),                     # 12 kelp, 13 kelp leaf, 14 kelp tip
    (20, 138, 64), (44, 184, 80), (108, 222, 96),                     # 15 seagrass dark, 16 seagrass, 17 its tips
    (96, 196, 60), (160, 232, 90),                                    # 18 clover, 19 clover lit
    (255, 232, 96), (120, 90, 30), (250, 250, 255), (255, 214, 70),     # 20 tube sponge, 21 its mouth, 22 white, 23 yellow
    (58, 128, 50), (108, 180, 70), (172, 218, 102),                     # 24 reed dark, 25 reed, 26 reed tip
    (134, 76, 38), (98, 54, 28),                                        # 27 cattail, 28 cattail dark
    (40, 122, 60), (72, 168, 82), (124, 204, 112),                      # 29 pad rim, 30 pad, 31 pad vein
]


def main():
    assert len(PALETTE) == 32
    img = Image.new("RGBA", (32, 4), (0, 0, 0, 255))
    for i, c in enumerate(PALETTE):
        for y in range(4):
            img.putpixel((i, y), c + (255,))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
