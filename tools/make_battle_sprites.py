"""Author hard-pixel additive battle HitFX sheets for assets/vfx/.

    python tools/make_battle_sprites.py

Needs Pillow + numpy. Same pixel language as tools/make_rain_sprites.py:
hard alpha, four-step posterise, nearest-filter friendly, no soft photo
falloff. WHITE / pale cores on black so Vfx.draw can tint per type.

Each animation is a SEQUENCE of events, not a fade of one blob -- the
rain tool's lesson. Frame 64x64, 8 columns x 2 rows = 16 frames, ~20 fps.
"""

from __future__ import annotations

import pathlib

import numpy as np
from PIL import Image

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "vfx"

CELL = 64
FRAMES = 16
COLS = 8
ROWS = 2


# ---------------------------------------------------------------------------
# canvas helpers -- every one of these plots HARD pixels
# ---------------------------------------------------------------------------

def blank() -> np.ndarray:
    return np.zeros((CELL, CELL), dtype=np.float64)


def put(a: np.ndarray, x: float, y: float, v: float) -> None:
    xi, yi = int(round(x)), int(round(y))
    if 0 <= xi < CELL and 0 <= yi < CELL:
        if v > a[yi, xi]:
            a[yi, xi] = v


def disc(a: np.ndarray, cx: float, cy: float, r: float, v: float) -> None:
    """A filled hard disc. r under 1 is a single pixel."""
    if r <= 0.75:
        put(a, cx, cy, v)
        return
    ri = int(r) + 1
    for dy in range(-ri, ri + 1):
        for dx in range(-ri, ri + 1):
            if dx * dx + dy * dy <= r * r:
                put(a, cx + dx, cy + dy, v)


def ring(a: np.ndarray, cx: float, cy: float, rx: float, ry: float,
         thick: float, v: float) -> None:
    """An elliptical outline, hard-edged (distance field, not a sweep)."""
    if rx <= 0 or ry <= 0:
        return
    x0, x1 = max(0, int(cx - rx - 2)), min(CELL - 1, int(cx + rx + 2))
    y0, y1 = max(0, int(cy - ry - 2)), min(CELL - 1, int(cy + ry + 2))
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            nx = (x - cx) / rx
            ny = (y - cy) / ry
            d = np.hypot(nx, ny)
            if abs(d - 1.0) * rx <= thick:
                if v > a[y, x]:
                    a[y, x] = v


def stroke(a: np.ndarray, x0: float, y0: float, x1: float, y1: float,
           w0: float, w1: float, v0: float, v1: float) -> None:
    """A tapered line: width and value both interpolate end to end."""
    n = max(2, int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 2)
    for i in range(n + 1):
        t = i / n
        x = x0 + (x1 - x0) * t
        y = y0 + (y1 - y0) * t
        w = w0 + (w1 - w0) * t
        v = v0 + (v1 - v0) * t
        disc(a, x, y, w, v)


def diamond(a: np.ndarray, cx: float, cy: float, rx: float, ry: float,
            ang: float, v: float) -> None:
    """Filled diamond, rotated. Hard leaf / shard vocabulary."""
    if rx <= 0 or ry <= 0:
        return
    ca, sa = np.cos(ang), np.sin(ang)
    reach = int(max(rx, ry) * 1.6) + 2
    for dy in range(-reach, reach + 1):
        for dx in range(-reach, reach + 1):
            u = dx * ca + dy * sa
            w = -dx * sa + dy * ca
            if abs(u) / rx + abs(w) / ry <= 1.0:
                put(a, cx + dx, cy + dy, v)


def rect(a: np.ndarray, cx: float, cy: float, w: float, h: float,
         ang: float, v: float) -> None:
    """Filled rectangle, rotated. Debris / ember."""
    if w <= 0 or h <= 0:
        return
    ca, sa = np.cos(ang), np.sin(ang)
    hw, hh = w * 0.5, h * 0.5
    reach = int(max(w, h) * 0.85) + 2
    for dy in range(-reach, reach + 1):
        for dx in range(-reach, reach + 1):
            u = dx * ca + dy * sa
            wv = -dx * sa + dy * ca
            if abs(u) <= hw and abs(wv) <= hh:
                put(a, cx + dx, cy + dy, v)


def cel(a: np.ndarray) -> np.ndarray:
    """Posterise to four steps -- drawn, not rendered."""
    out = np.zeros_like(a)
    out[a >= 0.16] = 0.34
    out[a >= 0.38] = 0.62
    out[a >= 0.66] = 0.86
    out[a >= 0.88] = 1.00
    return out


def kof(f: int) -> float:
    return f / (FRAMES - 1)


# ---------------------------------------------------------------------------
# the animations -- each is a sequence of events
# ---------------------------------------------------------------------------

def bt_charge(f: int) -> np.ndarray:
    """Inward gather: specks fall in, a ring shrinks, a core brightens."""
    a = blank()
    cx = cy = CELL / 2
    k = kof(f)

    # specks born on an outer circle, fall in
    rng = np.random.RandomState(13)
    n_speck = 14
    for i in range(n_speck):
        ang = i * (2 * np.pi / n_speck) + rng.rand() * 0.4
        delay = rng.rand() * 0.18
        t = (k - delay) / 0.72
        if t <= 0 or t > 1:
            continue
        r0 = 26.0 + rng.rand() * 4.0
        r = r0 * (1.0 - t)
        x = cx + np.cos(ang) * r
        y = cy + np.sin(ang) * r
        v = 0.7 + 0.3 * t
        disc(a, x, y, 0.8 if i % 3 else 1.3, v)

    # ring shrinks
    if 0.08 < k < 0.78:
        rk = (k - 0.08) / 0.70
        r = 22.0 * (1.0 - rk) + 3.5
        v = 0.55 + 0.45 * rk
        ring(a, cx, cy, r, r, 1.0, v)

    # core brightens late, then a flash
    if k > 0.42:
        ck = (k - 0.42) / 0.58
        disc(a, cx, cy, 1.2 + ck * 4.5, 0.5 + ck * 0.5)
        if k > 0.82:
            flash = (k - 0.82) / 0.18
            ring(a, cx, cy, 5.0 + flash * 10.0, 5.0 + flash * 10.0,
                 1.0, 1.0 - flash * 0.7)
            disc(a, cx, cy, 3.0 + flash * 2.0, 1.0)
    return cel(a)


def bt_slash(f: int) -> np.ndarray:
    """Crescent blade that grows, cuts across, shreds into sparks."""
    a = blank()
    k = kof(f)
    cx, cy = CELL / 2, CELL / 2

    if k < 0.58:
        # grow, then cut: the crescent's centre slides left -> right
        gk = k / 0.58
        r = 8.0 + gk * 16.0
        thick = 1.0 + gk * 1.6
        ox = cx - 16.0 + gk * 32.0
        oy = cy + 2.0
        # crescent = outer disc minus inner disc offset
        n = int(r * 3.2) + 8
        a0, a1 = -0.95, 0.95
        for i in range(n + 1):
            t = i / n
            ang = a0 + (a1 - a0) * t - 0.35
            x = ox + np.cos(ang) * r
            y = oy + np.sin(ang) * r * 0.72
            v = 1.0 if 0.2 < t < 0.8 else 0.7
            disc(a, x, y, thick if 0.15 < t < 0.85 else 0.7, v)
        # bright leading edge
        ang = a1 - 0.35
        disc(a, ox + np.cos(ang) * r, oy + np.sin(ang) * r * 0.72, 1.8, 1.0)

    if k > 0.42:
        # shreds: sparks along the cut, flying out
        sk = (k - 0.42) / 0.58
        rng = np.random.RandomState(31)
        for i in range(12):
            t = rng.rand()
            ang = -0.7 + t * 1.6
            sp = 8.0 + rng.rand() * 22.0
            x = cx - 10.0 + t * 28.0 + np.cos(ang) * sp * sk
            y = cy + np.sin(ang) * sp * sk * 0.7 - 6.0 * sk * sk
            v = max(0.0, 1.0 - sk * 0.85)
            disc(a, x, y, 1.4 if i % 4 == 0 else 0.8, v)
    return cel(a)


def _bolt_tree():
    rng = np.random.RandomState(42)
    trunk = [(CELL * 0.50, 4.0)]
    x, y = trunk[0]
    while y < CELL - 6:
        x += rng.uniform(-5.2, 5.2)
        y += rng.uniform(5.5, 8.5)
        x = float(np.clip(x, 10, CELL - 10))
        trunk.append((x, y))
    forks = []
    rng2 = np.random.RandomState(99)
    for i in range(2, len(trunk) - 2):
        if rng2.rand() > 0.55:
            continue
        bx, by = trunk[i]
        side = 1.0 if rng2.rand() > 0.5 else -1.0
        pts = [(bx, by)]
        fx, fy = bx, by
        ang = side * rng2.uniform(0.5, 1.15)
        for _ in range(3):
            fx += np.sin(ang) * rng2.uniform(5.5, 9.5)
            fy += np.cos(ang) * rng2.uniform(3.5, 6.5)
            pts.append((fx, fy))
            ang += rng2.uniform(-0.45, 0.45)
        forks.append(pts)
    return trunk, forks


_TRUNK, _FORKS = _bolt_tree()


def bt_bolt(f: int) -> np.ndarray:
    """Jagged branching lightning: trunk, forks, afterimage, snap off."""
    a = blank()
    k = kof(f)

    def draw_poly(pts, w0, w1, v, offx=0.0, offy=0.0):
        for i in range(len(pts) - 1):
            t = i / max(1, len(pts) - 2)
            stroke(a,
                   pts[i][0] + offx, pts[i][1] + offy,
                   pts[i + 1][0] + offx, pts[i + 1][1] + offy,
                   w0 + (w1 - w0) * t, w1,
                   v, v * 0.7)

    if k < 0.10:
        # precursor: a few pixels along the trunk
        for i, (x, y) in enumerate(_TRUNK):
            if i % 2 == 0:
                put(a, x, y, 0.5)
        return cel(a)

    if k < 0.88:
        # trunk draws in from the top
        grow = min(1.0, (k - 0.10) / 0.28)
        n = max(2, int(round((len(_TRUNK) - 1) * grow)) + 1)
        draw_poly(_TRUNK[:n], 1.8, 0.7, 1.0)
        # forks after the trunk is mostly there
        if k > 0.32:
            fk = min(1.0, (k - 0.32) / 0.22)
            nf = max(1, int(round(len(_FORKS) * fk)))
            for pts in _FORKS[:nf]:
                draw_poly(pts, 1.2, 0.5, 0.9)
        # peak flash
        if 0.50 < k < 0.68:
            disc(a, _TRUNK[0][0], _TRUNK[0][1], 2.2, 1.0)
            mid = _TRUNK[len(_TRUNK) // 2]
            disc(a, mid[0], mid[1], 1.6, 1.0)
        # afterimage, offset
        if k > 0.62:
            draw_poly(_TRUNK, 1.0, 0.5, 0.45, offx=2.0, offy=1.0)
            for pts in _FORKS:
                draw_poly(pts, 0.7, 0.4, 0.35, offx=2.0, offy=1.0)
        return cel(a)

    # snap off: residual tips only
    sk = (k - 0.88) / 0.12
    for i, (x, y) in enumerate(_TRUNK):
        if i % 3 == 0:
            disc(a, x, y, 0.8, 0.55 * (1 - sk))
    return cel(a)


def bt_beam(f: int) -> np.ndarray:
    """Thick core + two side rays that thicken then collapse."""
    a = blank()
    k = kof(f)
    cy = CELL / 2
    # thicken then collapse
    if k < 0.18:
        tk = k / 0.18
        thick = 0.6 + tk * 1.2
        v = 0.55 + tk * 0.45
        reach = 8.0 + tk * 22.0
        stroke(a, CELL / 2 - reach, cy, CELL / 2 + reach, cy, thick, thick, v, v)
    elif k < 0.72:
        tk = (k - 0.18) / 0.54
        core = 1.6 + tk * 2.4
        side = 0.6 + tk * 1.4
        v = 1.0
        stroke(a, 4, cy, CELL - 5, cy, core, core, v, v)
        # two side rays, delayed a beat
        if tk > 0.18:
            gap = 5.0 + tk * 3.0
            sv = 0.7 + 0.2 * min(1.0, (tk - 0.18) / 0.3)
            stroke(a, 8, cy - gap, CELL - 9, cy - gap, side, side, sv, sv)
            stroke(a, 8, cy + gap, CELL - 9, cy + gap, side, side, sv, sv)
        # pale core overlay
        stroke(a, 10, cy, CELL - 11, cy, max(0.6, core * 0.35), max(0.6, core * 0.35),
               1.0, 1.0)
    else:
        ck = (k - 0.72) / 0.28
        thick = 3.8 * (1 - ck)
        reach = (CELL / 2 - 4) * (1 - ck * 0.4)
        if thick > 0.4:
            stroke(a, CELL / 2 - reach, cy, CELL / 2 + reach, cy,
                   thick, thick, 1.0 - ck * 0.5, 1.0 - ck * 0.5)
        # collapsing side sparks
        for s in (-1, 1):
            disc(a, CELL / 2 + s * (18 - ck * 10), cy + s * (8 - ck * 4),
                 1.2, 0.7 * (1 - ck))
    return cel(a)


def bt_burst(f: int) -> np.ndarray:
    """Radial star + ember motes flying out."""
    a = blank()
    cx = cy = CELL / 2
    k = kof(f)

    if f == 0:
        disc(a, cx, cy, 2.0, 1.0)
        return cel(a)

    # 8-point star grows then fades
    if k < 0.55:
        sk = k / 0.55
        span = 6.0 + sk * 16.0
        v = 1.0 - sk * 0.35
        for i in range(8):
            ang = i * (np.pi / 4) + 0.2
            long = span if i % 2 == 0 else span * 0.55
            stroke(a, cx, cy,
                   cx + np.cos(ang) * long,
                   cy + np.sin(ang) * long,
                   2.2, 0.5, v, v * 0.3)
        disc(a, cx, cy, 3.0 - sk * 1.4, 1.0)
    else:
        disc(a, cx, cy, 1.4, max(0.0, 0.8 - (k - 0.55) * 2.0))

    # ember motes on rays, born after the star
    rng = np.random.RandomState(17)
    for i in range(16):
        ang = i * (2 * np.pi / 16) + rng.rand() * 0.3
        delay = 0.08 + rng.rand() * 0.12
        t = (k - delay) / 0.85
        if t <= 0:
            continue
        sp = 10.0 + rng.rand() * 18.0
        x = cx + np.cos(ang) * sp * t
        y = cy + np.sin(ang) * sp * t - 8.0 * t * t   # slight lift
        v = max(0.0, 1.0 - t * 0.9)
        disc(a, x, y, 1.3 if i % 3 == 0 else 0.8, v)
    return cel(a)


def bt_spray(f: int) -> np.ndarray:
    """Crown of droplets + arcs -- rain vocabulary as a BURST, not a puddle."""
    a = blank()
    cx, cy = CELL / 2, CELL * 0.62
    k = kof(f)

    if f == 0:
        disc(a, cx, cy, 1.8, 1.0)
        return cel(a)

    # crown: seven irregular spokes, out and up, then gone -- no ring left
    if k < 0.40:
        ck = k / 0.40
        out = 5.0 + ck * 14.0
        up = 9.0 * (1 - ck * 0.4)
        rng = np.random.RandomState(5)
        for i in range(8):
            ang = i * (2 * np.pi / 8) + 0.15
            lk = 0.62 + 0.70 * rng.rand()
            ex = cx + np.cos(ang) * out * lk
            ey = cy + np.sin(ang) * out * lk * 0.55 - up * lk
            stroke(a, cx, cy, ex, ey, 1.6, 0.5, 1.0 - ck * 0.3, 0.25)
        disc(a, cx, cy, 2.4 - ck * 1.4, 1.0)

    # droplets on ballistic arcs -- they fly off the sheet, no puddle
    rng = np.random.RandomState(101)
    for i in range(16):
        ang = -0.2 + i * (np.pi + 0.4) / 15
        sp = 10.0 + rng.rand() * 16.0
        up0 = 18.0 + rng.rand() * 16.0
        delay = rng.rand() * 0.10
        t = k - delay
        if t <= 0:
            continue
        ex = cx + np.cos(ang) * sp * t
        ey = cy - (up0 * t - 28.0 * t * t) + np.sin(ang) * sp * t * 0.35
        v = max(0.0, 1.0 - t * 0.85)
        if v > 0.05:
            disc(a, ex, ey, 1.4 if i % 4 == 0 else 0.8, v)
    return cel(a)


def bt_shards(f: int) -> np.ndarray:
    """Angular ice/rock fragments spinning out, then fall."""
    a = blank()
    cx = cy = CELL / 2
    k = kof(f)

    if k < 0.16:
        # crack lines
        rng = np.random.RandomState(3)
        for i in range(5):
            ang = i * (2 * np.pi / 5) + 0.4
            L = 4.0 + k / 0.16 * (6.0 + rng.rand() * 6.0)
            stroke(a, cx, cy, cx + np.cos(ang) * L, cy + np.sin(ang) * L,
                   1.0, 0.5, 1.0, 0.4)
        disc(a, cx, cy, 1.6, 1.0)
        return cel(a)

    rng = np.random.RandomState(44)
    n = 9
    for i in range(n):
        ang0 = i * (2 * np.pi / n) + rng.rand() * 0.4
        sp = 8.0 + rng.rand() * 16.0
        spin = (0.8 + rng.rand() * 2.4) * (1 if i % 2 == 0 else -1)
        # fly out, then gravity
        t = (k - 0.10) / 0.90
        if t <= 0:
            continue
        x = cx + np.cos(ang0) * sp * t
        y = cy + np.sin(ang0) * sp * t * 0.85 + 18.0 * t * t
        ang = ang0 + spin * t * 6.0
        v = max(0.0, 1.0 - t * 0.7)
        w = 3.2 + (i % 3) * 1.1
        h = 1.6 + (i % 2) * 0.8
        rect(a, x, y, w, h, ang, v)
        # a brighter chip on the leading corner
        put(a, x + np.cos(ang) * w * 0.4, y + np.sin(ang) * h * 0.4, 1.0)
    return cel(a)


def bt_spiral(f: int) -> np.ndarray:
    """Two counter-rotating pixel rings + center flash."""
    a = blank()
    cx = cy = CELL / 2
    k = kof(f)
    turn = k * 2.2 * np.pi

    def dotted_ring(r, n, phase, v, skip=0):
        for i in range(n):
            if skip and i % skip == 0:
                continue
            ang = phase + i * (2 * np.pi / n)
            disc(a, cx + np.cos(ang) * r, cy + np.sin(ang) * r * 0.92,
                 1.2 if i % 4 == 0 else 0.8, v)

    # inner ring clockwise, outer counter, both grow then hold then expand
    if k < 0.55:
        r_in = 6.0 + k / 0.55 * 8.0
        r_out = 12.0 + k / 0.55 * 10.0
    else:
        r_in = 14.0 + (k - 0.55) * 10.0
        r_out = 22.0 + (k - 0.55) * 12.0
    vin = 1.0 if k < 0.75 else 1.0 - (k - 0.75) / 0.25
    vout = 0.75 if k < 0.80 else 0.75 * (1 - (k - 0.80) / 0.20)
    dotted_ring(r_in, 12, turn, max(0.0, vin))
    dotted_ring(r_out, 16, -turn * 0.85 + 0.4, max(0.0, vout), skip=5)

    # center flash around the middle of the strip
    if 0.28 < k < 0.72:
        fk = 1.0 - abs(k - 0.50) / 0.22
        disc(a, cx, cy, 2.0 + fk * 4.0, fk)
        ring(a, cx, cy, 5.0 + fk * 3.0, 5.0 + fk * 3.0, 1.0, fk * 0.8)
    return cel(a)


def bt_leaves(f: int) -> np.ndarray:
    """4-6 hard leaf diamonds tumbling outward."""
    a = blank()
    cx, cy = CELL / 2, CELL / 2
    k = kof(f)
    rng = np.random.RandomState(8)
    n = 6
    for i in range(n):
        ang0 = i * (2 * np.pi / n) + 0.3
        delay = i * 0.03
        t = (k - delay) / 0.92
        if t <= 0:
            continue
        sp = 7.0 + rng.rand() * 14.0
        x = cx + np.cos(ang0) * sp * t
        y = cy + np.sin(ang0) * sp * t * 0.9 - 4.0 * t + 10.0 * t * t
        spin = ang0 + t * (4.5 if i % 2 == 0 else -3.6)
        v = max(0.0, 1.0 - t * 0.65)
        rx = 4.2 + (i % 3) * 0.8
        ry = 1.7 + (i % 2) * 0.4
        diamond(a, x, y, rx, ry, spin, v)
        # midrib: a darker (here: dimmer, so tint still reads) line
        ca, sa = np.cos(spin), np.sin(spin)
        stroke(a, x - ca * rx * 0.7, y - sa * rx * 0.7,
               x + ca * rx * 0.7, y + sa * rx * 0.7,
               0.5, 0.5, v * 0.45, v * 0.45)
    if k < 0.18:
        disc(a, cx, cy, 1.6, 1.0)
    return cel(a)


def bt_fist(f: int) -> np.ndarray:
    """Expanding concentric rings + a 4-point hit star."""
    a = blank()
    cx = cy = CELL / 2
    k = kof(f)

    # 4-point star first, holds, fades
    if k < 0.55:
        sk = min(1.0, k / 0.18)
        span = 5.0 + sk * 11.0
        v = 1.0 if k < 0.32 else 1.0 - (k - 0.32) / 0.23
        for i in range(4):
            ang = i * (np.pi / 2) + 0.0
            stroke(a, cx, cy,
                   cx + np.cos(ang) * span,
                   cy + np.sin(ang) * span,
                   2.4, 0.6, v, v * 0.25)
        # diagonals shorter
        for i in range(4):
            ang = i * (np.pi / 2) + np.pi / 4
            stroke(a, cx, cy,
                   cx + np.cos(ang) * span * 0.45,
                   cy + np.sin(ang) * span * 0.45,
                   1.4, 0.5, v * 0.85, 0.2)
        disc(a, cx, cy, 2.2, 1.0)

    # concentric rings, staggered
    for n, born, span, thick in (
        (0, 0.08, 26.0, 1.4),
        (1, 0.22, 22.0, 1.0),
        (2, 0.38, 18.0, 0.8),
    ):
        kk = (k - born) / (1.0 - born)
        if 0 < kk < 1:
            r = 3.5 + kk * span
            v = ((1 - kk) ** 1.35) / (1 + n * 0.4)
            ring(a, cx, cy, r, r * 0.92, thick, v)
    return cel(a)


def bt_wisp(f: int) -> np.ndarray:
    """Rising irregular blobs that split."""
    a = blank()
    k = kof(f)
    rng = np.random.RandomState(21)
    # three parent blobs
    parents = []
    for i in range(3):
        px = CELL * (0.32 + 0.18 * i) + rng.rand() * 3
        py0 = CELL * 0.72
        delay = i * 0.08
        t = (k - delay) / 0.85
        if t <= 0:
            continue
        py = py0 - t * 36.0
        wob = np.sin(t * 6.0 + i) * 3.5
        r = 3.4 - t * 1.2
        v = max(0.0, 1.0 - t * 0.45)
        # irregular: 3 overlapping discs, not a circle
        ox = rng.rand() * 2.0 - 1.0
        oy = rng.rand() * 2.0 - 1.0
        disc(a, px + wob, py, r, v)
        disc(a, px + wob + ox * 2.2, py + oy * 1.6, r * 0.7, v * 0.8)
        disc(a, px + wob - ox * 1.8, py - oy * 1.2, r * 0.55, v * 0.7)
        parents.append((px + wob, py, t, i))

        # split after rising a bit
        if t > 0.38:
            st = (t - 0.38) / 0.62
            for s, side in enumerate((-1.0, 1.0)):
                sx = px + wob + side * (5.0 + st * 10.0)
                sy = py - st * 8.0 - s * 3.0
                disc(a, sx, sy, 1.8 - st * 0.8, v * (1 - st * 0.5))
                disc(a, sx + side, sy - 2, 1.1, v * (1 - st * 0.6))
    return cel(a)


def bt_arc(f: int) -> np.ndarray:
    """A traveling chevron / streak (projectile frame, also a hit accent)."""
    a = blank()
    k = kof(f)
    cy = CELL / 2
    # head travels left -> right, ease out
    u = 1.0 - (1.0 - k) * (1.0 - k)
    hx = 6.0 + u * 50.0
    hy = cy + np.sin(k * 3.2) * 3.0
    # chevron pointing along travel
    arm = 7.0 + (1 - u) * 3.0
    thick = 1.8 if k < 0.85 else 1.8 * (1 - (k - 0.85) / 0.15)
    v = 1.0 if k < 0.80 else 1.0 - (k - 0.80) / 0.20
    ang = 0.0
    # two arms of the chevron
    stroke(a, hx, hy,
           hx - arm * np.cos(ang - 0.7), hy - arm * np.sin(ang - 0.7),
           thick, 0.5, v, v * 0.2)
    stroke(a, hx, hy,
           hx - arm * np.cos(ang + 0.7), hy - arm * np.sin(ang + 0.7),
           thick, 0.5, v, v * 0.2)
    disc(a, hx, hy, 1.8, v)
    # afterimage ticks behind the head
    for i in range(4):
        t = k - (i + 1) * 0.06
        if t <= 0:
            continue
        uu = 1.0 - (1.0 - max(0.0, t)) ** 2
        ax = 6.0 + uu * 50.0
        ay = cy + np.sin(max(0.0, t) * 3.2) * 3.0
        disc(a, ax, ay, 1.1, v * (0.55 - i * 0.1))
    return cel(a)


# ---------------------------------------------------------------------------
# sheets -- bright RGB on black, opaque ink, empty stays (0,0,0,0)
# ---------------------------------------------------------------------------

SHEETS = (
    ("bt_charge.png", bt_charge),
    ("bt_slash.png",  bt_slash),
    ("bt_bolt.png",   bt_bolt),
    ("bt_beam.png",   bt_beam),
    ("bt_burst.png",  bt_burst),
    ("bt_spray.png",  bt_spray),
    ("bt_shards.png", bt_shards),
    ("bt_spiral.png", bt_spiral),
    ("bt_leaves.png", bt_leaves),
    ("bt_fist.png",   bt_fist),
    ("bt_wisp.png",   bt_wisp),
    ("bt_arc.png",    bt_arc),
)


def sheet_additive(name: str, fn) -> None:
    grid = np.zeros((ROWS * CELL, COLS * CELL), dtype=np.float64)
    for f in range(FRAMES):
        r, c = divmod(f, COLS)
        grid[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL] = fn(f)
    rgba = np.zeros((grid.shape[0], grid.shape[1], 4), dtype=np.uint8)
    lum = (np.clip(grid, 0, 1) * 255).round().astype(np.uint8)
    rgba[..., 0] = lum
    rgba[..., 1] = lum
    rgba[..., 2] = lum
    rgba[..., 3] = np.where(lum > 0, 255, 0)
    path = OUT / name
    Image.fromarray(rgba, "RGBA").save(path, optimize=True)
    ink = (rgba[..., 3] > 8).mean() * 100
    print(f"{name:<18} {rgba.shape[1]}x{rgba.shape[0]}  "
          f"{path.stat().st_size:>6} bytes  {FRAMES} frames  ink {ink:.1f}%")


def main() -> None:
    if not OUT.is_dir():
        raise SystemExit(f"no such directory: {OUT}")
    for name, fn in SHEETS:
        sheet_additive(name, fn)
    print("done.")


if __name__ == "__main__":
    main()
