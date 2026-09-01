"""Re-slice the Pimen wind and dust packs, and EdgeLoopRepeat's leaves, into
the strips WindFX plays.

Sources (tools/_vfx_dl/pimen, downloaded 2026-09-01, see assets/vfx/LICENSE.md):
  Wind Effect 01 / Wind Breath.png      576x32   12 frames of 48x32
  Wind Effect 01 / Wind Projectile.png   96x64    3x2 of 32x32, 6 frames
  Wind Effect 02 / Pull in.png          144x144   3x3 of 48x48, 7 used
  Smoke N Dust 03 / VFX 1.png           720x64    9 frames of 80x64
  Smoke N Dust 03 / VFX 5.png           256x32    8 frames of 32x32
  ELR-WindyLeafs / *Leaf.png (x3)        80x16    5 frames of 16x16 each;
                                                  fall, spring, winter go
                                                  into ONE strip, 15 frames,
                                                  as 3 variants of 5

Each output is ONE ROW of frames (cols == n), so WindFX.SHEETS can read a
strip with fw, fh and n alone. Blank frames are dropped, and the
frame count that survives is printed -- that number goes in WindFX.SHEETS.
Pixels are copied as they are: nearest filter in the engine, no resampling,
no recolour.

    python tools/install_pimen_wind.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "_vfx_dl" / "pimen"
ELR = ROOT / "tools" / "_vfx_dl" / "elr_leaves" / "ELR-WindyLeafs"
OUT = ROOT / "assets" / "vfx"

# out name, source, frame w, frame h, grid cols, grid rows
STRIPS = [
    ("wind_breath.png",  SRC / "Wind_Effect_01" / "Wind Effect 01" / "Wind Breath.png",     48, 32, 12, 1),
    ("wind_curl.png",    SRC / "Wind_Effect_01" / "Wind Effect 01" / "Wind Projectile.png",  32, 32, 3, 2),
    ("wind_whirl.png",   SRC / "Wind_Effect_02" / "Wind Effect 02" / "Pull in.png",          48, 48, 3, 3),
    ("wind_kick.png",    SRC / "Smoke_N_Dust_03" / "SmokeNDust P03 VFX 1.png",               80, 64, 9, 1),
    ("wind_wetpuff.png", SRC / "Smoke_N_Dust_03" / "SmokeNDust P03 VFX 5.png",               32, 32, 8, 1),
]


def frames_of(img, fw, fh, cols, rows):
    a = np.array(img)
    out = []
    for r in range(rows):
        for c in range(cols):
            f = a[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw]
            if f.shape[0] != fh or f.shape[1] != fw:
                continue
            out.append(f)
    # drop every blank frame: the grids pad their last row with empties,
    # and Pull in has one in the middle that would flicker in a loop
    return [f for f in out if f[..., 3].any()]


# one strip, three variants side by side: WindFX.SHEETS.leaf reads it as
# cols = 15, n = 5, variants = 3
LEAF_VARIANTS = ["ELR_FallLeaf.png", "ELR_SpringlLeaf.png", "ELR_WinterlLeaf.png"]


def leaves():
    frames = []
    for v in LEAF_VARIANTS:
        img = Image.open(ELR / v).convert("RGBA")
        assert img.size == (80, 16), (v, img.size)
        fs = frames_of(img, 16, 16, 5, 1)
        assert len(fs) == 5, (v, len(fs))
        frames += fs
    strip = np.zeros((16, 16 * len(frames), 4), dtype=np.uint8)
    for i, f in enumerate(frames):
        strip[:, i * 16:(i + 1) * 16] = f
    out = OUT / "wind_leaf.png"
    Image.fromarray(strip, "RGBA").save(out, optimize=True)
    print(f"{'wind_leaf.png':18s} 16x16 x {len(frames)} frames (3 variants of 5), {out.stat().st_size} bytes")


def main():
    leaves()
    for name, src, fw, fh, cols, rows in STRIPS:
        img = Image.open(src).convert("RGBA")
        assert img.size == (fw * cols, fh * rows), (name, img.size, fw * cols, fh * rows)
        frames = frames_of(img, fw, fh, cols, rows)
        strip = np.zeros((fh, fw * len(frames), 4), dtype=np.uint8)
        for i, f in enumerate(frames):
            strip[:, i * fw:(i + 1) * fw] = f
        Image.fromarray(strip, "RGBA").save(OUT / name, optimize=True)
        print(f"{name:18s} {fw}x{fh} x {len(frames)} frames, {(OUT / name).stat().st_size} bytes")


if __name__ == "__main__":
    main()
