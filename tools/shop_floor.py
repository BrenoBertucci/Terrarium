"""Build the Mart's floor surface: sheet vinyl with a grouted tile grid.

Neither graded photograph in `assets/shop/` is the floor a convenience
store has:

* `floor_tile` (Poly Haven floor_tiles_08) has the grid, and every tile in
  it is a different tone. At the room's `scale = 32` that per-tile
  variation reads as staining, and the floor came out looking like a
  weathered pavement rather than a shop.
* `shop_vinyl` (linoleum_brown, graded) is the right SURFACE -- an even
  fine fleck, relative sd 0.087 -- and has no seam anywhere in it, so the
  floor loses the one grid that tells the eye how big the room is.

So: the vinyl for the material, a drawn grid for the joint. Nothing is
invented about the geometry -- the joint pitch matches what `floor_tile`
carried (five tiles per cycle) so `FloorArt`'s `scale = 32` keeps meaning
one tile is 64 cm.

    python tools/shop_floor.py

Writes `assets/shop/shop_floor.jpg` and `shop_floor_n.jpg`.
"""

import numpy as np
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SHOP = ROOT / "assets" / "shop"

TILES = 5           # per cycle, matching floor_tiles_08's own pitch
JOINT = 3           # joint width in source pixels at 1024
JOINT_DARK = 0.80   # how far the joint drops. Grout is a shade, not a line
TILE_VARY = 0.012   # per-tile tone spread. floor_tile's is about 0.09, and
                    # that is the whole difference between "shop" and
                    # "pavement" -- keep it just above invisible.


def build():
    src = Image.open(SHOP / "shop_vinyl.jpg").convert("RGB")
    a = np.asarray(src, dtype=np.float64) / 255.0
    h, w = a.shape[:2]

    # the joint mask: a soft-edged line at every tile boundary, in both
    # axes, on the source's own pixel grid
    def axis_mask(n):
        i = np.arange(n)
        p = n / TILES
        d = np.minimum(i % p, p - (i % p))      # distance to nearest joint
        return np.clip(1.0 - d / JOINT, 0.0, 1.0)

    mx = axis_mask(w)[None, :]
    my = axis_mask(h)[:, None]
    joint = np.maximum(mx, my)                  # (h, w) in 0..1

    # per-tile tone, held to a whisper
    rng = np.random.default_rng(7)
    tone = rng.normal(1.0, TILE_VARY, (TILES, TILES))
    ty = (np.arange(h) * TILES // h).clip(0, TILES - 1)
    tx = (np.arange(w) * TILES // w).clip(0, TILES - 1)
    tone_map = tone[np.ix_(ty, tx)][:, :, None]

    out = a * tone_map
    out = out * (1.0 - joint[:, :, None] * (1.0 - JOINT_DARK))
    # hold the mean where the grader left it, so the shader's reciprocal
    # (assets/shop/README.md) still applies
    out *= a.mean() / max(out.mean(), 1e-6)
    out = np.clip(out, 0.0, 1.0)

    Image.fromarray((out * 255).round().astype(np.uint8)).save(
        SHOP / "shop_floor.jpg", quality=92)

    # the normal: the vinyl's own, with the joint pressed into it. A groove
    # tilts its two flanks toward each other, which is the gradient of the
    # joint mask -- so the mask IS the height field.
    nrm = np.asarray(Image.open(SHOP / "shop_vinyl_n.jpg").convert("RGB"),
                     dtype=np.float64) / 255.0 * 2.0 - 1.0
    # the graded normal is not always the albedo's resolution (the vinyl's
    # is 512 against a 1024 albedo), so the joint field is resampled onto
    # IT rather than the other way round -- upsampling a normal map softens
    # every fleck in it.
    nh, nw = nrm.shape[:2]
    jm = np.asarray(Image.fromarray((joint * 255).astype(np.uint8))
                    .resize((nw, nh), Image.BILINEAR), dtype=np.float64) / 255.0
    gy, gx = np.gradient(jm)
    STRENGTH = 6.0
    nrm[:, :, 0] -= gx * STRENGTH
    nrm[:, :, 1] += gy * STRENGTH               # DirectX green-up, as graded
    n = np.linalg.norm(nrm, axis=2, keepdims=True)
    nrm /= np.maximum(n, 1e-6)
    Image.fromarray((((nrm + 1.0) * 0.5) * 255).round().astype(np.uint8)
                    ).save(SHOP / "shop_floor_n.jpg", quality=95)

    lum = out @ [0.299, 0.587, 0.114]
    print("shop_floor.jpg  %dx%d  mean %.3f  rel sd %.3f  -> multiplier %.3f"
          % (w, h, lum.mean(), lum.std() / lum.mean(), 1.0 / lum.mean()))


if __name__ == "__main__":
    build()
