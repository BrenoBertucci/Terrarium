"""Paint assets/buildings/bridge_kit.png, the sheet lib/BridgeKit.lua wears.

    python tools/bridge_sheet.py

One texel a voxel, drawn from nothing (no ROM art). 32x32:
  (0..15, 0..15)   the deck seen from above, boards lying east-west
  (16..31, 0..15)  the same deck, boards lying north-south
  row 16           one texel per material -- BridgeKit.T names the columns
The deck rows are read along x, which is the axis Buildings.emit merges
runs on, so a cell's whole top costs sixteen quads either way.
"""
from pathlib import Path
import random

from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "assets/buildings/bridge_kit.png"

BANDS = 4
BOARD = [(176, 124, 72), (164, 112, 64), (186, 134, 80), (156, 106, 60)]
JOINT = (96, 62, 36)
NAIL = (70, 48, 32)
# row 16, left to right: keep in step with BridgeKit.T
MATERIALS = [
    (158, 106, 60),   # 0 post
    (104, 66, 38),    # 1 post, its dark foot and collar
    (112, 72, 40),    # 2 beam under the deck
    (120, 84, 52),    # 3 pile, dry
    (78, 66, 52),     # 4 pile, wet
    (74, 96, 70),     # 5 pile, weeded
    (206, 206, 214),  # 6 stone cap, lit
    (168, 168, 180),  # 7 stone cap, shade
    (52, 50, 58),     # 8 lantern iron
    (255, 214, 120),  # 9 lantern glass
    (255, 244, 190),  # 10 lantern glass, the flame's row (9..10 = BridgeKit.GLASS_UV)
    (190, 138, 84),   # 11 rail, top
    (160, 110, 62),   # 12 rail, side
    (132, 134, 146),  # 13 stone footing at the waterline
]


def deck(rng):
    """16x16, boards four voxels wide lying along x."""
    px = [[None] * 16 for _ in range(16)]
    for b in range(4):
        tone = BOARD[(b * 3 + 1) % 4]
        butt = rng.choice([3, 7, 11])          # where this board is two boards
        for dz in range(4):
            z = b * 4 + dz
            for x in range(16):
                c = tone
                if dz == 3:
                    c = JOINT
                elif x == butt:
                    c = JOINT
                elif dz == 1 and x in (butt - 1, (butt + 1) % 16, 0, 15):
                    c = NAIL
                elif rng.random() < 0.10:       # grain
                    c = tuple(max(0, v - 14) for v in tone)
                px[z][x] = c
    return px


def main():
    rng = random.Random(12)
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 255))
    d = deck(rng)
    for z in range(16):
        for x in range(16):
            img.putpixel((x, z), d[z][x] + (255,))
            img.putpixel((16 + z, x), d[z][x] + (255,))     # transposed
    for i, c in enumerate(MATERIALS):
        img.putpixel((i, 16), c + (255,))
    # BANDS identical copies down the sheet: which one a voxel wears is how
    # much lantern light reaches it (BridgeKit.GLOW, Voxel3D's lanternGlow)
    sheet = Image.new("RGBA", (32, 32 * BANDS))
    for b in range(BANDS):
        sheet.paste(img, (0, 32 * b))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
