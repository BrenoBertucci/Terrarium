# Cut the artist's snowflake sheet into the strip the WEATHER row draws.
#
# In: a sheet of N flakes side by side on a flat dark ground (Breno's
# snowsprite.png: 1536x1024, four flakes, ~10 px per drawn pixel). Out:
# assets/weather/snowflake.png, one 32x32 RGBA frame per flake, the paper
# keyed to alpha softly enough that the thin arms survive the shrink. The
# 1.2 MB sheet becomes an 8 KB strip.
#
#   python tools/cut_snowflakes.py <sheet.png> [frames] [frame_px]
import os, sys
from PIL import Image
import numpy as np

src = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\breno\Downloads\snowsprite.png"
N = int(sys.argv[2]) if len(sys.argv) > 2 else 4
F = int(sys.argv[3]) if len(sys.argv) > 3 else 32
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "weather", "snowflake.png")

im = Image.open(src).convert("RGB")
a = np.asarray(im).astype(float)
# the paper is whatever the corner is
bg = np.median(a[:40, :40].reshape(-1, 3), axis=0)
d = np.abs(a - bg).sum(axis=2)
out = Image.new("RGBA", (F * N, F), (0, 0, 0, 0))
W = im.width // N
for i in range(N):
    x0 = i * W
    ys, xs = np.where(d[:, x0:x0 + W] > 40)
    bx0, bx1, by0, by1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    side = max(bx1 - bx0, by1 - by0)
    cx, cy = (bx0 + bx1) // 2, (by0 + by1) // 2
    crop = im.crop((x0 + cx - side // 2, cy - side // 2,
                    x0 + cx + side // 2, cy + side // 2))
    ca = np.asarray(crop).astype(float)
    alpha = np.clip((np.abs(ca - bg).sum(axis=2) - 25) / 110.0, 0, 1)
    rgba = np.dstack([ca, alpha * 255]).astype(np.uint8)
    fr = Image.fromarray(rgba, "RGBA").resize((F - 2, F - 2), Image.BOX)
    out.paste(fr, (i * F + 1, 1), fr)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
out.save(OUT, optimize=True)
print("wrote", OUT, out.size, os.path.getsize(OUT), "bytes")
