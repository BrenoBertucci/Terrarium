# The leaves the wind carries: assets/vfx/wind_leaves.png.
#
# One sheet, one ROW per leaf (a shape in a colour), six FRAMES of it
# tumbling. Every frame is the same flat leaf turned in 3D and projected --
# rolled about its own midrib (so it narrows to an edge and comes back showing
# its paler underside) while it spins slowly in its own plane -- then cut to
# pixels in the house style: a hard silhouette, four tones (lit, base, shade,
# outline), the midrib and the stem drawn in.
#
# Shapes: maple, oval (beech), willow, birch, oak, and a twig -- the reference
# sheet's "variação de formas, cores e tamanhos". Colours are autumn's plus two
# greens, so a summer gale tears off green leaves and an autumn one gold.
#
# Deterministic, no inputs. WindFX.SHEETS.leaf reads it: fw = fh = FRAME,
# cols = FRAMES, n = FRAMES, variants = len(VARIANTS).
#
#   py tools/make_wind_leaves.py
import math
import os

import numpy as np
from PIL import Image, ImageDraw

FRAME = 24          # px, each frame
FRAMES = 6
SS = 8              # supersampling for the silhouette
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "vfx", "wind_leaves.png")


def outline(shape, n=96):
    """The flat leaf as a polygon: x across (-1..1), y along (0 stem .. 1 tip)."""
    pts = []
    if shape in ("pebble", "chip"):
        # a gale's debris: an irregular stone, or a flat chip of bark --
        # fixed jitter per shape so the rows are stable build to build
        k = 7 if shape == "pebble" else 6
        jit = [1.0, 0.82, 0.95, 0.74, 0.9, 0.86, 0.97]
        for i in range(k):
            a = i / k * 2 * math.pi
            rx = 0.5 * jit[i % len(jit)]
            ry = rx * (1.0 if shape == "pebble" else 0.45)
            pts.append((rx * math.cos(a), 0.5 + ry * math.sin(a) * 1.9))
        return pts
    if shape == "maple":
        # five lobes, drawn point by point up the right side and mirrored:
        # a notch at the stem, a lower lobe pointing down and out, a side
        # lobe, a shoulder, and the top lobe -- a formula star came out as a
        # twisted squiggle at 24 px
        right = [(0.00, 0.10), (0.12, 0.16), (0.36, 0.06), (0.30, 0.24),
                 (0.52, 0.30), (0.40, 0.42), (0.54, 0.60), (0.30, 0.56),
                 (0.28, 0.74), (0.14, 0.66), (0.10, 0.88), (0.00, 1.00)]
        left = [(-x, y) for (x, y) in reversed(right[1:-1])]
        return right + left
    for i in range(n + 1):
        t = i / n
        y = t
        if shape == "oval":
            w = 0.55 * math.sin(math.pi * t) ** 0.75
        elif shape == "willow":
            w = 0.24 * math.sin(math.pi * t) ** 0.7
        elif shape == "birch":
            w = 0.60 * math.sin(math.pi * (t ** 0.75)) ** 0.9
            w *= 1 + 0.06 * math.sin(t * 40)          # the fine teeth
        elif shape == "oak":
            w = 0.46 * math.sin(math.pi * t) ** 0.7
            w *= 1 + 0.32 * math.sin(t * 5 * 2 * math.pi) * math.sin(math.pi * t)
        else:
            w = 0.06
        pts.append((w, y))
    back = [(-x, y) for (x, y) in reversed(pts)]
    return pts + back


def project(pts, roll, spin, pitch=0.35):
    """Roll about the midrib (y axis), pitch a little toward the camera, then
    spin in the picture. Orthographic. Returns 2D points and the facing."""
    out = []
    for x, y in pts:
        y = y - 0.5
        x3, z3 = x * math.cos(roll), x * math.sin(roll)
        y3 = y * math.cos(pitch) - z3 * math.sin(pitch)
        z3 = y * math.sin(pitch) + z3 * math.cos(pitch)
        sx = x3 * math.cos(spin) - y3 * math.sin(spin)
        sy = x3 * math.sin(spin) + y3 * math.cos(spin)
        out.append((sx, sy))
    # the plane's normal after the roll: +z when the top face shows
    facing = math.cos(roll) if abs(roll) < 1.2 else -abs(math.cos(roll))
    return out, facing


def raster(poly2d, scale):
    big = FRAME * SS
    im = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(im)
    c = big / 2
    d.polygon([(c + x * scale * big / 2, c - y * scale * big / 2) for x, y in poly2d], fill=255)
    return np.asarray(im.resize((FRAME, FRAME), Image.BOX), dtype=np.float32) / 255.0


def line_mask(p0, p1, width, scale):
    big = FRAME * SS
    im = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(im)
    c = big / 2
    d.line([(c + p0[0] * scale * big / 2, c - p0[1] * scale * big / 2),
            (c + p1[0] * scale * big / 2, c - p1[1] * scale * big / 2)],
           fill=255, width=max(1, int(width * SS)))
    return np.asarray(im.resize((FRAME, FRAME), Image.BOX), dtype=np.float32) / 255.0


def frame(shape, base, roll, spin, scale):
    pts = outline(shape)
    poly, facing = project(pts, roll, spin)
    cov = raster(poly, scale)
    mask = cov > 0.45
    # the stem and the midrib, through the same projection
    (s0,), _ = project([(0.0, -0.10)], roll, spin)
    (s1,), _ = project([(0.0, 0.02)], roll, spin)
    (r1,), _ = project([(0.0, 0.92 if shape != "maple" else 0.72)], roll, spin)
    stem = line_mask(s0, s1, 1.2, scale) > 0.35
    rib = line_mask(s1, r1, 0.9, scale) > 0.45
    if shape in ("pebble", "chip"):
        stem = np.zeros_like(stem)
        rib = np.zeros_like(rib)
    base = np.array(base, dtype=np.float32) / 255.0
    # the underside is paler and a touch greyer; the lit face is the colour
    under = facing < 0
    light = 0.62 + 0.38 * abs(facing)
    col = base * light
    if under:
        col = col * 0.82 + np.array([0.18, 0.16, 0.10]) * 0.9
    rgba = np.zeros((FRAME, FRAME, 4), dtype=np.float32)
    ys, xs = np.mgrid[0:FRAME, 0:FRAME]
    # light from the upper left: a lit tone on that side of the silhouette
    lit = ((xs - FRAME / 2) + (ys - FRAME / 2)) < -2
    shade = ((xs - FRAME / 2) + (ys - FRAME / 2)) > 4
    body = np.where(lit[..., None], np.minimum(col * 1.18, 1.0),
                    np.where(shade[..., None], col * 0.80, col))
    rgba[..., :3] = body
    rgba[..., 3] = mask.astype(np.float32)
    # outline: silhouette pixels with a transparent 4-neighbour
    m = mask
    edge = m & ~(np.roll(m, 1, 0) & np.roll(m, -1, 0) & np.roll(m, 1, 1) & np.roll(m, -1, 1))
    rgba[edge, :3] = col * 0.52
    ribc = col * 0.68
    rib_on = rib & m & ~edge
    rgba[rib_on, :3] = ribc
    stem_on = stem & ~m
    rgba[stem_on, :3] = np.array([0.36, 0.24, 0.12])
    rgba[stem_on, 3] = 1.0
    return rgba


def twig(base, roll, spin, scale):
    rgba = np.zeros((FRAME, FRAME, 4), dtype=np.float32)
    base = np.array(base, dtype=np.float32) / 255.0
    parts = [((0, -0.45), (0, 0.45), 1.6), ((0, 0.05), (0.28, 0.32), 1.1),
             ((0, -0.15), (-0.22, 0.10), 1.0)]
    for p0, p1, w in parts:
        (a,), _ = project([(p0[0], p0[1] + 0.5)], roll * 0.3, spin, 0.2)
        (b,), _ = project([(p1[0], p1[1] + 0.5)], roll * 0.3, spin, 0.2)
        mk = line_mask(a, b, w, scale) > 0.4
        rgba[mk, :3] = base
        rgba[mk, 3] = 1.0
    return rgba


# (shape, colour, scale) -- scale is how much of the frame the leaf fills
VARIANTS = [
    ("maple", (227, 130, 47), 1.75),
    ("maple", (200, 72, 42), 1.75),
    ("maple", (233, 196, 64), 1.75),
    ("oval", (236, 190, 60), 1.60),
    ("oval", (118, 170, 58), 1.60),
    ("willow", (150, 184, 70), 1.80),
    ("birch", (240, 206, 72), 1.55),
    ("oak", (160, 104, 50), 1.70),
    ("oak", (214, 110, 44), 1.70),
    ("oval", (212, 98, 42), 1.50),
    ("willow", (186, 196, 72), 1.80),
    ("twig", (120, 82, 44), 1.60),
    # rows 12..14: a gale's debris (WindFX.SHEETS.debris, row0 = 12)
    ("pebble", (126, 96, 66), 1.55),
    ("chip", (108, 72, 44), 1.65),
    ("pebble", (156, 134, 104), 1.55),
]


def main():
    sheet = np.zeros((FRAME * len(VARIANTS), FRAME * FRAMES, 4), dtype=np.float32)
    for row, (shape, colour, scale) in enumerate(VARIANTS):
        for f in range(FRAMES):
            # a tumble that never goes fully edge-on (two frames of a bare
            # line out of six read as the leaf blinking out): the roll swings
            # +-74 degrees, so the underside shows on the back half, while the
            # leaf turns slowly in its own plane
            roll = 1.3 * math.sin(2 * math.pi * f / FRAMES + 0.3)
            spin = 0.55 + f / FRAMES * 1.2 + row * 0.4
            img = twig(colour, roll, spin, scale) if shape == "twig" \
                else frame(shape, colour, roll, spin, scale)
            sheet[row * FRAME:(row + 1) * FRAME, f * FRAME:(f + 1) * FRAME] = img
    out = Image.fromarray((np.clip(sheet, 0, 1) * 255).astype(np.uint8), "RGBA")
    out.save(OUT)
    print("wrote", OUT, out.size, "variants", len(VARIANTS), "frames", FRAMES)


if __name__ == "__main__":
    main()
