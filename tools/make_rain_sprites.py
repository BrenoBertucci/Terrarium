"""Author the rain impact / ripple / droplet / mist sheets for assets/vfx/.

    python tools/make_rain_sprites.py

Needs Pillow + numpy. Same rules as tools/make_wind_sprites.py: hard alpha,
nearest filter, no soft photo smoke. WHITE RGB with the shape in alpha --
Weather tints every sheet by the hour's own light at draw time, the same
value the diorama and the flat world are tinted by, so a dusk splash is warm
and a midnight one is not a white sticker.

------- why these are authored and not downloaded

Looked, first. The one genuinely good pixel-art water splash on OpenGameArt
is CC-BY-SA 3.0, and this directory's licence file records a hard CC0 rule
for exactly the reason share-alike would break: none of it may be covered by
whatever licence the mod ships under. The CC0 water on OGA is either a
seamless 512-square heightmap texture (not an impact), photographed river
tiles, or a 10x10 five-frame toy. And the same licence file already records
that Kenney's soft circles were pulled from this mod for reading as photo
dust over a Game Boy diorama -- which is the failure mode of nearly every
downloadable VFX pack here.

------- what a raindrop landing actually does, which is why there are stages

The animation is not a fade of one shape. It is four events in sequence, and
the sheet has to carry all four or the eye reads a decal blinking:

    CROWN     the surface caves and the wall of the cavity climbs, briefly,
              as a ring with points on it
    EJECTA    the crown is unstable -- that is why it throws drops -- so the
              points break off and fly out on arcs
    JET       the cavity collapses, the walls meet, and the water has
              nowhere to go but up: a thin column taller than the crown was
              wide. This is the shape in every photograph of a drop landing
              and the one nobody draws.
    RINGS     plural and staggered, leaving the centre a beat apart, each
              expanding and thinning at its own rate

Ground gets crown + ejecta + a single ring: paving has no cavity to collapse,
so it has no jet. Water gets all four.
"""

from __future__ import annotations

import pathlib

import numpy as np
from PIL import Image

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "vfx"

CELL = 64
FRAMES = 16
COLS = 8

# How flat a ring lying on the ground looks from the diorama's camera. Must
# match Weather.RING_SQUASH or a sheet ring and a drawn one disagree.
SQUASH = 0.42


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
    """A filled hard disc. r under 1 is a single pixel, which is the point:
    a droplet is one pixel and must not be allowed to become a soft blob."""
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
    """An elliptical outline, hard-edged.

    Walked as a distance field rather than as a parametric sweep on purpose:
    a sweep at small radii lands several samples on the same pixel and leaves
    gaps between them, which reads as a dotted ring rather than a thin one.
    """
    if rx <= 0 or ry <= 0:
        return
    x0, x1 = max(0, int(cx - rx - 2)), min(CELL - 1, int(cx + rx + 2))
    y0, y1 = max(0, int(cy - ry - 2)), min(CELL - 1, int(cy + ry + 2))
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            nx = (x - cx) / rx
            ny = (y - cy) / ry
            d = np.hypot(nx, ny)
            # thickness measured along the radius, so a wide ellipse does not
            # come out thicker on its long axis than on its short one
            if abs(d - 1.0) * rx <= thick:
                if v > a[y, x]:
                    a[y, x] = v


def stroke(a: np.ndarray, x0: float, y0: float, x1: float, y1: float,
           w0: float, w1: float, v0: float, v1: float) -> None:
    """A tapered line: width and value both interpolate end to end. This is
    the crown spoke and the jet, and both of them are thick and bright where
    the water is and thin and gone where it was."""
    n = max(2, int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 2)
    for i in range(n + 1):
        t = i / n
        x = x0 + (x1 - x0) * t
        y = y0 + (y1 - y0) * t
        w = w0 + (w1 - w0) * t
        v = v0 + (v1 - v0) * t
        disc(a, x, y, w, v)


def cel(a: np.ndarray) -> np.ndarray:
    """Posterise to four steps. The whole reason these read as drawn rather
    than rendered: an antialiased edge over a diorama of hard voxels is the
    single thing that says 'this was composited on afterwards'."""
    out = np.zeros_like(a)
    out[a >= 0.16] = 0.34
    out[a >= 0.38] = 0.62
    out[a >= 0.66] = 0.86
    out[a >= 0.88] = 1.00
    return out


# ---------------------------------------------------------------------------
# the animations
# ---------------------------------------------------------------------------

def impact_ground(f: int) -> np.ndarray:
    """Crown, ejecta, one ring. Paving: no cavity, so no jet."""
    a = blank()
    cx, cy = CELL / 2, CELL * 0.62
    k = f / (FRAMES - 1)

    # ------- the strike itself, one bright frame
    if f == 0:
        disc(a, cx, cy, 1.4, 1.0)
        return cel(a)

    # ------- the crown: seven spokes, out and up, over the first third
    if k < 0.42:
        ck = k / 0.42
        out = 4.0 + ck * 12.0
        up = 7.5 * (1 - ck * 0.35)
        v = 1.0 - ck * 0.45
        rng = np.random.RandomState(11)
        for i in range(7):
            ang = i * (2 * np.pi / 7) + 0.4
            # spokes are NOT the same length: a crown is unstable, and a set
            # of identical spikes reads as a compass rose stamped on the road
            lk = 0.62 + 0.66 * rng.rand()
            ex = cx + np.cos(ang) * out * lk
            ey = cy + np.sin(ang) * out * lk * SQUASH - up * lk
            stroke(a, cx, cy, ex, ey, 1.5, 0.5, v, v * 0.25)
        disc(a, cx, cy, 2.2 - ck * 1.2, 1.0)

    # ------- ejecta: the crown coming apart, on arcs
    if 0.16 < k < 0.86:
        ek = (k - 0.16) / 0.70
        rng = np.random.RandomState(29)
        for i in range(9):
            ang = i * (2 * np.pi / 9) + 0.9
            sp = 13.0 + rng.rand() * 11.0
            up0 = 15.0 + rng.rand() * 12.0
            t = ek * 1.15
            ex = cx + np.cos(ang) * sp * t
            ey = cy + np.sin(ang) * sp * t * SQUASH - (up0 * t - 26.0 * t * t)
            v = 1.0 - ek * 0.55
            disc(a, ex, ey, 0.9 if i % 3 else 1.4, v)

    # ------- and the ring it leaves on the road
    rk = k
    r = 3.0 + rk * 24.0
    v = max(0.0, (1 - rk) ** 1.6)
    ring(a, cx, cy, r, r * SQUASH, 1.0, v * 0.95)
    return cel(a)


def impact_water(f: int) -> np.ndarray:
    """Crown, jet, ejecta off the jet's tip, and three staggered rings."""
    a = blank()
    cx, cy = CELL / 2, CELL * 0.66
    k = f / (FRAMES - 1)

    if f == 0:
        disc(a, cx, cy, 1.6, 1.0)
        ring(a, cx, cy, 3.0, 3.0 * SQUASH, 1.0, 0.7)
        return cel(a)

    # ------- crown, briefly
    if k < 0.34:
        ck = k / 0.34
        out = 4.5 + ck * 9.0
        up = 6.0 * (1 - ck * 0.4)
        rng = np.random.RandomState(5)
        for i in range(8):
            ang = i * (2 * np.pi / 8) + 0.2
            lk = 0.66 + 0.6 * rng.rand()
            ex = cx + np.cos(ang) * out * lk
            ey = cy + np.sin(ang) * out * lk * SQUASH - up * lk
            stroke(a, cx, cy, ex, ey, 1.4, 0.5, 0.95, 0.2)

    # ------- THE JET
    #
    # Rises fast, hangs near the top, falls back. sin() alone is symmetric
    # and reads as a bounce, so the phase is bent to hold at the peak the way
    # the real column does.
    if k < 0.68:
        jk = k / 0.68
        hh = np.sin((jk ** 0.68) * np.pi)
        if hh > 0.02:
            h = 30.0 * hh
            v = 1.0 - jk * 0.30
            stroke(a, cx, cy, cx, cy - h, 2.1, 0.75, v, v * 0.65)
            # the bead standing on the tip just before it comes apart
            if 0.32 < jk < 0.92:
                disc(a, cx, cy - h - 1.5, 1.5, 1.0)

    # ------- what the jet throws when it does come apart
    if 0.46 < k:
        ek = (k - 0.46) / 0.54
        rng = np.random.RandomState(77)
        for i in range(6):
            ang = i * (2 * np.pi / 6) + 0.5
            sp = 7.0 + rng.rand() * 9.0
            t = ek
            ex = cx + np.cos(ang) * sp * t
            ey = cy - 22.0 + np.sin(ang) * sp * t * SQUASH + 34.0 * t * t
            if ey < cy:
                disc(a, ex, ey, 1.0, 1.0 - ek * 0.5)

    # ------- three rings, staggered, each on its own clock
    for n in range(3):
        born = n * 0.17
        kk = (k - born) / (1 - born)
        if 0 < kk < 1:
            r = 2.5 + kk * (23.0 + n * 5.0)
            v = ((1 - kk) ** 1.5) / (1 + n * 0.55)
            ring(a, cx, cy, r, r * SQUASH, 1.0 if n == 0 else 0.8, v)
    return cel(a)


def droplets(f: int) -> np.ndarray:
    """Respingos: a burst of small drops on ballistic arcs, no ring at all.

    Its own strip because it is spent separately -- thrown off a hard surface
    a heavy drop bursts on, where there is spray but nothing to ripple.
    """
    a = blank()
    cx, cy = CELL / 2, CELL * 0.70
    k = f / (FRAMES - 1)
    rng = np.random.RandomState(101)
    for i in range(14):
        ang = i * (2 * np.pi / 14) + 0.3
        sp = 9.0 + rng.rand() * 16.0
        up0 = 20.0 + rng.rand() * 18.0
        delay = rng.rand() * 0.12
        t = k - delay
        if t <= 0:
            continue
        ex = cx + np.cos(ang) * sp * t
        ey = cy + np.sin(ang) * sp * t * SQUASH - (up0 * t - 30.0 * t * t)
        if ey > cy + 2:
            continue
        v = max(0.0, 1.0 - t * 0.75)
        disc(a, ex, ey, 1.3 if i % 4 == 0 else 0.8, v)
    if k < 0.30:
        stroke(a, cx, cy, cx, cy - 12.0 * (1 - k / 0.30), 1.6, 0.6,
               1.0, 0.3)
    return cel(a)


def mist(f: int) -> np.ndarray:
    """Neblina / distant rain: a tile of faint vertical streaks that scrolls.

    LOOPS, and the first cut of it did not -- streaks scrolled off the bottom
    and nothing came back on at the top, so the strip visibly emptied out
    over sixteen frames and then snapped full again. A scrolling tile has to
    be drawn THREE times, one cell above and one below, and the copies
    clipped: that way whatever leaves the bottom edge is already entering
    the top, and frame fifteen runs into frame zero with no seam.
    """
    a = blank()
    k = f / FRAMES
    off = k * CELL
    rng = np.random.RandomState(7)
    for _ in range(30):
        x = rng.rand() * CELL
        y0 = rng.rand() * CELL
        ln = 6.0 + rng.rand() * 18.0
        v = 0.18 + rng.rand() * 0.42
        for rep in (-1, 0, 1):
            y = y0 + off + rep * CELL
            stroke(a, x, y, x - 1.5, y + ln, 0.6, 0.4, v, v * 0.15)
    return cel(a)


def leaf_on_water(f: int) -> np.ndarray:
    """A leaf touching down on water: the leaf, and the ring it makes.

    Full colour rather than white-alpha -- a leaf has a colour of its own and
    tinting a white one green at draw time would make every leaf the same
    green, which is the thing the flying-leaf sheet already avoids.
    """
    a = blank()
    leaf = blank()
    cx, cy = CELL / 2, CELL * 0.56
    k = f / (FRAMES - 1)
    # the leaf drifts down, touches at k=0.25, then settles and rocks
    if k < 0.25:
        ly = cy - 16.0 * (1 - k / 0.25)
        tilt = 0.9
    else:
        ly = cy
        tilt = 0.35 * np.sin((k - 0.25) * 14.0) * max(0.0, 1 - (k - 0.25) * 1.6)
    # A hard little leaf: a lens shape with a midrib cut through it. The
    # first cut wrote the rib with `put`, which only ever RAISES a value --
    # so the darker rib could not be drawn over the brighter blade and the
    # leaf came out as a featureless bean. It is written directly.
    for dy in range(-4, 5):
        for dx in range(-7, 8):
            u = dx / 7.0
            v = dy / 4.0
            if u * u + (v - tilt * u) ** 2 * 1.9 <= 1.0:
                put(leaf, cx + dx, ly + dy, 1.0)
    for dx in range(-6, 7):
        xi = int(round(cx + dx))
        yi = int(round(ly + tilt * dx))
        if 0 <= xi < CELL and 0 <= yi < CELL and leaf[yi, xi] > 0:
            leaf[yi, xi] = 0.5
    # and the ring it puts on the water when it lands
    if k >= 0.25:
        rk = (k - 0.25) / 0.75
        r = 5.0 + rk * 17.0
        ring(a, cx, cy + 2, r, r * SQUASH, 1.0, (1 - rk) ** 1.6)
    return cel(a), cel(leaf)


# ---------------------------------------------------------------------------
# sheets
# ---------------------------------------------------------------------------

def sheet_white(name: str, fn) -> None:
    rows = (FRAMES + COLS - 1) // COLS
    grid = np.zeros((rows * CELL, COLS * CELL), dtype=np.float64)
    for f in range(FRAMES):
        r, c = divmod(f, COLS)
        grid[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL] = fn(f)
    rgba = np.zeros((grid.shape[0], grid.shape[1], 4), dtype=np.uint8)
    rgba[..., 0:3] = 255
    rgba[..., 3] = (np.clip(grid, 0, 1) * 255).round().astype(np.uint8)
    path = OUT / name
    Image.fromarray(rgba, "RGBA").save(path, optimize=True)
    ink = (rgba[..., 3] > 8).mean() * 100
    print(f"{name:<20} {rgba.shape[1]}x{rgba.shape[0]}  "
          f"{path.stat().st_size:>6} bytes  {FRAMES} frames  ink {ink:.1f}%")


LEAF_GREEN = (118, 156, 62)
LEAF_DARK = (74, 104, 44)


def sheet_leaf_water(name: str) -> None:
    rows = (FRAMES + COLS - 1) // COLS
    rgba = np.zeros((rows * CELL, COLS * CELL, 4), dtype=np.uint8)
    for f in range(FRAMES):
        r, c = divmod(f, COLS)
        water, leaf = leaf_on_water(f)
        sub = rgba[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL]
        # water ring: white, tinted at draw time like every other sheet here
        m = water > 0
        sub[..., 0:3][m] = 255
        sub[..., 3][m] = (water[m] * 255).round().astype(np.uint8)
        # the leaf on top, in its own colour
        lm = leaf > 0
        sub[..., 0][lm] = np.where(leaf[lm] > 0.8, LEAF_GREEN[0], LEAF_DARK[0])
        sub[..., 1][lm] = np.where(leaf[lm] > 0.8, LEAF_GREEN[1], LEAF_DARK[1])
        sub[..., 2][lm] = np.where(leaf[lm] > 0.8, LEAF_GREEN[2], LEAF_DARK[2])
        sub[..., 3][lm] = 255
    path = OUT / name
    Image.fromarray(rgba, "RGBA").save(path, optimize=True)
    print(f"{name:<20} {rgba.shape[1]}x{rgba.shape[0]}  "
          f"{path.stat().st_size:>6} bytes  {FRAMES} frames")


def main() -> None:
    sheet_white("rain_impact.png", impact_ground)
    sheet_white("rain_ripple.png", impact_water)
    sheet_white("rain_droplets.png", droplets)
    sheet_white("rain_mist.png", mist)
    sheet_leaf_water("leaf_water.png")


if __name__ == "__main__":
    main()
