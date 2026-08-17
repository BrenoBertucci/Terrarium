"""Author cel-hard wind & leaf particles for assets/vfx/.

Pixel-art only (nearest, hard alpha). Soft Kenney circles read as "photo dust"
over a Game-Boy diorama; these are grit, seeds, dashes and tumbling leaves.

    python tools/make_wind_sprites.py

Needs Pillow + numpy.
"""

from __future__ import annotations

import pathlib

import numpy as np
from PIL import Image

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "vfx"


def write_rgba(name: str, rgba: np.ndarray) -> None:
    path = OUT / name
    Image.fromarray(rgba.astype(np.uint8), "RGBA").save(path, optimize=True)
    ink = (rgba[..., 3] > 8).mean() * 100
    print(f"{name:<18} {rgba.shape[1]}x{rgba.shape[0]}  "
          f"{path.stat().st_size} bytes  ink {ink:.0f}%")


def write_white_alpha(name: str, alpha: np.ndarray) -> None:
    """White RGB, shape in alpha — WindFX tints at draw time."""
    a = np.clip(alpha, 0.0, 1.0)
    h, w = a.shape
    rgba = np.zeros((h, w, 4), dtype=np.uint8)
    rgba[..., 0:3] = 255
    rgba[..., 3] = (a * 255).round().astype(np.uint8)
    write_rgba(name, rgba)


def hard(a: np.ndarray, lo: float = 0.35) -> np.ndarray:
    """Posterise soft falloff into cel steps (0 / mid / full)."""
    out = np.zeros_like(a)
    out[a >= lo] = 0.55
    out[a >= 0.72] = 1.0
    return out


# ---------------------------------------------------------------------------
# dust / grit / seed / streak / swirl — white-alpha
# ---------------------------------------------------------------------------

def dust_speck(size: int = 8) -> np.ndarray:
    """A few hard grit pixels — airborne dirt, not a soft ball."""
    a = np.zeros((size, size), dtype=np.float64)
    # 2×2 core + one offset pixel (asymmetric = not a circle)
    cx, cy = size // 2 - 1, size // 2 - 1
    for dy, dx, v in ((0, 0, 1), (0, 1, 1), (1, 0, 0.85), (1, 1, 0.7),
                      (-1, 0, 0.55), (0, -1, 0.5), (2, 1, 0.4)):
        y, x = cy + dy, cx + dx
        if 0 <= y < size and 0 <= x < size:
            a[y, x] = max(a[y, x], v)
    return a


def mote_seed(size: int = 10) -> np.ndarray:
    """Elongated seed / pollen — thin diamond, not a circle."""
    a = np.zeros((size, size), dtype=np.float64)
    cx = cy = (size - 1) / 2.0
    for y in range(size):
        for x in range(size):
            # diamond stretched on X
            d = abs(x - cx) / 3.6 + abs(y - cy) / 1.6
            if d < 1.0:
                a[y, x] = 1.0 if d < 0.55 else 0.55
    return a


def puff_cel(size: int = 12) -> np.ndarray:
    """Tiny cel cloud of grit — 3 hard blobs, not Kenney smoke."""
    a = np.zeros((size, size), dtype=np.float64)
    blobs = ((4, 5, 2.0), (7, 4, 1.6), (6, 7, 1.4), (3, 7, 1.1))
    for cy, cx, r in blobs:
        for y in range(size):
            for x in range(size):
                d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
                if d <= r:
                    a[y, x] = max(a[y, x], 1.0 if d <= r * 0.55 else 0.5)
    return a


def streak_cel(w: int = 24, h: int = 7) -> np.ndarray:
    """Tapered hard dash: nose bright, tail thin. Cel, not soft airbrush."""
    a = np.zeros((h, w), dtype=np.float64)
    mid = h // 2
    for x in range(w):
        u = x / max(1, w - 1)
        # thickness: fat near 30%, points at ends
        thick = (min(u / 0.28, 1.0) ** 0.6) * ((1.0 - u) ** 1.1)
        half = max(0.4, thick * (h * 0.45))
        bright = 1.0 if u < 0.45 else (0.55 if u < 0.75 else 0.35)
        for y in range(h):
            # slight bow
            bow = 0.35 * np.sin(np.pi * u) * (h * 0.35)
            if abs(y - mid - bow) <= half:
                a[y, x] = max(a[y, x], bright)
    return a


def swirl_cel(frames: int = 8, size: int = 14) -> np.ndarray:
    """Hard-pixel comma curl that opens over `frames` (horizontal strip)."""
    out = np.zeros((size, frames * size), dtype=np.float64)
    cy = cx = (size - 1) / 2.0
    for f in range(frames):
        u = f / max(1, frames - 1)
        turns = 0.95 - 0.55 * u
        r0 = 2.8 + 3.0 * u
        n = 48
        a = np.zeros((size, size))
        for i in range(n):
            t = i / max(1, n - 1)
            ang = t * turns * 2 * np.pi + 0.4
            r = r0 * (0.35 + 0.65 * t)
            px = cx + np.cos(ang) * r
            py = cy + np.sin(ang) * r * 0.7
            amp = 1.0 if t < 0.55 else 0.55
            # stamp 1–2 hard pixels
            for oy in (0,):
                for ox in (0,):
                    ix = int(round(px + ox))
                    iy = int(round(py + oy))
                    if 0 <= ix < size and 0 <= iy < size:
                        a[iy, ix] = max(a[iy, ix], amp * (1.0 - 0.5 * t))
            # thickness early in the stroke
            if t < 0.5:
                ix2 = int(round(px + np.cos(ang + 0.5)))
                iy2 = int(round(py + np.sin(ang + 0.5) * 0.7))
                if 0 <= ix2 < size and 0 <= iy2 < size:
                    a[iy2, ix2] = max(a[iy2, ix2], amp * 0.7)
        out[:, f * size:(f + 1) * size] = a
    return out


# ---------------------------------------------------------------------------
# flying leaves — full colour (not white-alpha)
# ---------------------------------------------------------------------------

# palette: greens + autumn browns, GB-ish
LEAF_PAL = [
    ((74, 122, 48), (48, 88, 32), (32, 58, 20)),      # fresh green
    ((96, 140, 52), (64, 100, 36), (40, 68, 24)),
    ((120, 148, 44), (88, 112, 32), (56, 72, 20)),    # yellow-green
    ((148, 120, 40), (112, 88, 28), (72, 56, 16)),    # olive / early fall
    ((160, 96, 40), (120, 68, 28), (80, 44, 16)),     # brown-orange
    ((132, 72, 48), (96, 48, 32), (64, 32, 20)),      # dry brown
    ((68, 112, 56), (44, 80, 40), (28, 52, 28)),
    ((108, 132, 40), (76, 96, 28), (48, 64, 18)),
    ((140, 108, 52), (100, 76, 36), (64, 48, 22)),
    ((88, 128, 44), (56, 92, 30), (36, 60, 18)),
]


def stamp_leaf(rgba: np.ndarray, ox: int, kind: int, pal_i: int) -> None:
    """Draw one 16×16 flying leaf silhouette into strip at ox."""
    light, mid, dark = LEAF_PAL[pal_i % len(LEAF_PAL)]
    # shapes as relative pixel sets (x,y) mid = body, light = highlight, dark = edge/vein
    # All small (not plant-growth stages).
    shapes = [
        # pointed oval
        [(3, 7), (4, 5), (4, 6), (4, 7), (4, 8), (4, 9),
         (5, 4), (5, 5), (5, 6), (5, 7), (5, 8), (5, 9), (5, 10),
         (6, 4), (6, 5), (6, 6), (6, 7), (6, 8), (6, 9), (6, 10),
         (7, 5), (7, 6), (7, 7), (7, 8), (7, 9),
         (8, 6), (8, 7), (8, 8)],
        # teardrop
        [(4, 6), (4, 7), (4, 8),
         (5, 4), (5, 5), (5, 6), (5, 7), (5, 8), (5, 9),
         (6, 3), (6, 4), (6, 5), (6, 6), (6, 7), (6, 8), (6, 9), (6, 10),
         (7, 4), (7, 5), (7, 6), (7, 7), (7, 8), (7, 9),
         (8, 6), (8, 7)],
        # maple-ish (simple 3 lobes)
        [(3, 7), (4, 5), (4, 6), (4, 7), (4, 8),
         (5, 3), (5, 4), (5, 5), (5, 6), (5, 7), (5, 8), (5, 9),
         (6, 2), (6, 3), (6, 4), (6, 5), (6, 6), (6, 7), (6, 8), (6, 9), (6, 10),
         (7, 3), (7, 4), (7, 5), (7, 6), (7, 7), (7, 8), (7, 9),
         (8, 5), (8, 6), (8, 7), (8, 8),
         (9, 6), (9, 7)],
        # narrow willow
        [(5, 3), (5, 4), (5, 5), (5, 6), (5, 7), (5, 8), (5, 9), (5, 10), (5, 11),
         (6, 2), (6, 3), (6, 4), (6, 5), (6, 6), (6, 7), (6, 8), (6, 9), (6, 10), (6, 11), (6, 12),
         (7, 3), (7, 4), (7, 5), (7, 6), (7, 7), (7, 8), (7, 9), (7, 10), (7, 11)],
        # round
        [(4, 6), (4, 7), (4, 8),
         (5, 5), (5, 6), (5, 7), (5, 8), (5, 9),
         (6, 4), (6, 5), (6, 6), (6, 7), (6, 8), (6, 9), (6, 10),
         (7, 5), (7, 6), (7, 7), (7, 8), (7, 9),
         (8, 6), (8, 7), (8, 8)],
        # heart-ish
        [(3, 6), (3, 7),
         (4, 5), (4, 6), (4, 7), (4, 8),
         (5, 4), (5, 5), (5, 6), (5, 7), (5, 8), (5, 9),
         (6, 5), (6, 6), (6, 7), (6, 8), (6, 9), (6, 10),
         (7, 4), (7, 5), (7, 6), (7, 7), (7, 8), (7, 9),
         (8, 5), (8, 6), (8, 7), (8, 8),
         (9, 6), (9, 7)],
        # tiny chip (far leaf)
        [(5, 6), (5, 7), (6, 5), (6, 6), (6, 7), (6, 8), (7, 6), (7, 7)],
        # side-on thin
        [(4, 7), (5, 5), (5, 6), (5, 7), (5, 8), (5, 9),
         (6, 4), (6, 5), (6, 6), (6, 7), (6, 8), (6, 9), (6, 10),
         (7, 6), (7, 7), (7, 8)],
        # torn fragment
        [(4, 6), (4, 7), (5, 5), (5, 6), (5, 7), (5, 8),
         (6, 5), (6, 6), (6, 7), (6, 8), (6, 9),
         (7, 6), (7, 7), (7, 8), (8, 7)],
        # curled C
        [(4, 5), (4, 6), (4, 7), (5, 4), (5, 5), (5, 8),
         (6, 4), (6, 8), (6, 9), (7, 5), (7, 6), (7, 7), (7, 8)],
    ]
    body = shapes[kind % len(shapes)]
    # fill body mid, edge dark, a couple light pixels
    for x, y in body:
        rgba[y, ox + x, 0:3] = mid
        rgba[y, ox + x, 3] = 255
    # dark rim: neighbours empty
    for x, y in body:
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if not (0 <= nx < 16 and 0 <= ny < 16):
                continue
            if rgba[ny, ox + nx, 3] == 0:
                rgba[ny, ox + nx, 0:3] = dark
                rgba[ny, ox + nx, 3] = 255
    # 2–3 highlight pixels on upper-left of body
    for x, y in body[:3]:
        if 0 <= y - 1 < 16:
            rgba[y, ox + x, 0:3] = light


def leaves_strip(n: int = 10, fw: int = 16) -> np.ndarray:
    rgba = np.zeros((fw, n * fw, 4), dtype=np.uint8)
    for i in range(n):
        stamp_leaf(rgba, i * fw, i, i)
    return rgba


if __name__ == "__main__":
    if not OUT.is_dir():
        raise SystemExit(f"no such directory: {OUT}")
    write_white_alpha("wind_dust.png", dust_speck(8))
    write_white_alpha("wind_mote.png", mote_seed(10))
    write_white_alpha("wind_puff.png", puff_cel(12))
    write_white_alpha("wind_streak.png", streak_cel(24, 7))
    write_white_alpha("wind_swirl.png", swirl_cel(8, 14))
    write_rgba("leaves.png", leaves_strip(10, 16))
    print("done.")
