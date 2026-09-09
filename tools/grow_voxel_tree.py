#!/usr/bin/env python3
"""Grow the VOXEL trees of the TREES row -- blocky Kanto trees, from nothing.

This is the baker for the VOXEL option (lib/Trees3D.lua, set "voxel").  It
is NOT the 3D bake: that one (tools/bake_tree.py) hides its voxels under
photo leaf cards and ships its own colours.  This one is proud of its cubes
and ships NO colours at all -- every leaf face points at a slot of a small
palette strip that the game paints at map load with the greens the map's
own tree tile got from its palette (TerrainAtlas.tileShades).  A tree on
Route 2 wears Route 2's greens; the same tree in Viridian Forest wears the
forest's.  That is the one property of the old hull worth keeping, and the
only one.

WHAT A VOXEL TREE HAS TO BE, SEEN FROM HERE
-------------------------------------------
The overworld camera looks down at ~52 degrees from a few cells away.  Every
Gen 1 tree site is ONE 16 px cell (site.r = 8 on all 2325 sites the probes
counted), so a bake's file height IS its world height.  A voxel here is
VOX = 2.5 world px = ~14 screen px on a 1536-wide frame: big enough to
read as a cube, small enough that a 17-voxel tree still has a silhouette.
(2.0 was tried: finer, and 35% more triangles -- over the loader's budget
on two species.  A voxel tree should be proud of its cubes anyway.)

  * THE TRUNK SHOWS.  A crown that starts at ~40% of the height with a
    tapered, slightly leaning bole under it and two root nubs at the foot.
    A tree whose trunk is buried is a bush -- the old hull was a bush.
  * THE CROWN IS A FEW MASSES, NOT A SPHERE.  A core plus lobes hanging off
    it, rims eaten by low-frequency noise, a couple of NOTCHES bitten out of
    the upper rim so the sky shows through and the silhouette steps.
  * TUFTS.  Single leaf voxels stuck to the upper shell, sticking out one
    cube.  They are what makes the crown read as "many leaves" instead of
    "one green ball" at this size, and the shader gives them the most wind.
  * COLOUR IS DITHERED, NEVER FLAT.  Each leaf voxel picks a tone from the
    map's ramp by its height in the crown, then a third of them shift one
    tone up or down.  The Gen 1 tile itself is a dither; a voxel tree in
    that palette wants the same texture at cube scale.
  * LIGHT COMES FROM ABOVE.  Faces carry Voxel3D.FACE_SHADE times crevice
    AO times a top-to-bottom band, quantised so faces still merge.

THE WIND NEEDS A NUMBER PER VERTEX, baked as the 7th float exactly as the
3D bake does: zero at the foot, a little at the top of the bole, more on
branches, 0.55..0.85 across the leaf mass rising outward, 0.92 on the
tufts.  No card ever reaches 0.985, so Voxel3D's card tier stays off and
the crown rolls, the twigs swing and the tufts shiver -- cubes do not
turn on a stalk.

MAGICAVOXEL IN: `--vox <file>` imports a .vox (CC0 references live in
tools/_tree_src/vox/, see NOTES.md there) through the same pipeline: its
colours are classified into leaf tones by luminance and bark by hue, so a
tree authored in MagicaVoxel lands in the map's palette like a grown one.

Usage:
    python tools/grow_voxel_tree.py                    # all species
    python tools/grow_voxel_tree.py --only round       # one
    python tools/grow_voxel_tree.py --report           # counts only
    python tools/grow_voxel_tree.py --preview          # + probe_out_voxeltree/
    python tools/grow_voxel_tree.py --vox tools/_tree_src/vox/mmmm_obj_tree1.vox --name vox1 --preview
"""
from __future__ import annotations

import argparse
import colorsys
import json
import math
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "ground" / "tree" / "voxel"
PREVIEW_DIR = ROOT / "probe_out_voxeltree"

MAGIC = b"TTR2"
VOX = 2.5                 # world px per voxel (species are authored at 2, see scaled())
TEX = 64                  # palette strip: 8x8 slots, everything under v = 0.375
TILE = 8
MAX_TRIS = 1200           # Trees3D.MAX_TRIS -- the loader refuses past it
BUDGET = MAX_TRIS         # --budget lifts it for a preview experiment only

# Voxel3D.FACE_SHADE in this file's direction order:
#   0 +X east  1 -X west  2 +Y up  3 -Y down  4 +Z south  5 -Z north
FACE_SHADE = [0.84, 0.72, 1.00, 0.55, 0.90, 0.68]
NEIGHBOUR = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]

# ---- the palette strip.  MUST MATCH Trees3D.VOXEL_PALETTE in lib/Trees3D.lua.
# Row 0 (y 0..7): leaf tones, painted at runtime from the map's tree tile.
# Row 1 (y 8..15): bark tones, fixed -- Gen 1 has no brown in a tree tile.
LEAF_TONES = ["hi", "lit", "mid", "dark", "deep", "outline"]
BARK_TONES = ["bark_dark", "bark_mid", "bark_lit", "root"]
M_HI, M_LIT, M_MID, M_DARK, M_DEEP, M_OUTLINE = range(6)
M_BARK_DARK, M_BARK_MID, M_BARK_LIT, M_ROOT = range(6, 10)

# Defaults = what the tree tile got on Route 2 (sampled off a probe shot);
# the game overwrites row 0 per map, so these are the fallback and the
# offline preview, nothing more.
DEFAULT_RGB = {
    "hi": (136, 224, 96), "lit": (72, 196, 16), "mid": (40, 150, 8),
    "dark": (16, 96, 0), "deep": (8, 60, 0), "outline": (28, 32, 36),
    "bark_dark": (74, 48, 28), "bark_mid": (104, 70, 40), "bark_lit": (134, 94, 54),
    "root": (60, 40, 24),
}


def slot_of(mat: int) -> tuple[int, int]:
    """(row, col) of a material's 8x8 slot in the strip."""
    return (0, mat) if mat < 6 else (1, mat - 6)


def slot_uv(mat: int) -> tuple[float, float]:
    """Centre of the slot: one texel, constant over the face (nearest)."""
    row, col = slot_of(mat)
    return ((col * TILE + TILE / 2) / TEX, (row * TILE + TILE / 2) / TEX)


def strip_image(rgb: dict | None = None) -> Image.Image:
    rgb = rgb or DEFAULT_RGB
    im = Image.new("RGBA", (TEX, TEX), (0, 0, 0, 0))
    px = im.load()
    for mat in range(10):
        name = (LEAF_TONES + BARK_TONES)[mat]
        row, col = slot_of(mat)
        c = tuple(rgb[name]) + (255,)
        for y in range(TILE):
            for x in range(TILE):
                px[col * TILE + x, row * TILE + y] = c
    return im


# --------------------------------------------------------------------------
# deterministic noise -- a species must bake byte-identical every run
# --------------------------------------------------------------------------

def _h3(i: int, j: int, k: int, seed: int) -> float:
    n = (i * 374761393 + j * 668265263 + k * 1274126177 + seed * 2246822519) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    n = (n ^ (n >> 16)) & 0xFFFFFFFF
    return n / 4294967296.0


def vnoise(x: float, y: float, z: float, seed: int) -> float:
    i, j, k = math.floor(x), math.floor(y), math.floor(z)
    fx, fy, fz = x - i, y - j, z - k
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    fz = fz * fz * (3 - 2 * fz)
    def c(a, b, d):
        return _h3(i + a, j + b, k + d, seed)
    x00 = c(0, 0, 0) + (c(1, 0, 0) - c(0, 0, 0)) * fx
    x10 = c(0, 1, 0) + (c(1, 1, 0) - c(0, 1, 0)) * fx
    x01 = c(0, 0, 1) + (c(1, 0, 1) - c(0, 0, 1)) * fx
    x11 = c(0, 1, 1) + (c(1, 1, 1) - c(0, 1, 1)) * fx
    y0 = x00 + (x10 - x00) * fy
    y1 = x01 + (x11 - x01) * fy
    return y0 + (y1 - y0) * fz


def fbm(x, y, z, freq, seed, octaves=3):
    s, a, tot = 0.0, 1.0, 0.0
    for o in range(octaves):
        s += a * vnoise(x * freq, y * freq, z * freq, seed + o * 31)
        tot += a
        a *= 0.5
        freq *= 2.0
    return s / tot


class Rng:
    def __init__(self, seed: int):
        self.s = (seed * 2654435761 + 12345) & 0xFFFFFFFF

    def next(self) -> float:
        self.s = (self.s * 1103515245 + 12345) & 0x7FFFFFFF
        return (self.s >> 8) / float(1 << 23)

    def range(self, a: float, b: float) -> float:
        return a + (b - a) * self.next()


# --------------------------------------------------------------------------
# species
# --------------------------------------------------------------------------

@dataclass
class Lobe:
    dx: float
    dy: float
    dz: float
    r: float
    ry: float


@dataclass
class Species:
    name: str
    seed: int
    trunk_h: float              # voxels, ground to where the crown takes over
    trunk_r: float              # voxels, radius at the foot (tapers to 65%)
    lean: float                 # voxels the bole wanders sideways
    crown_y: float              # voxels, centre of the crown
    lobes: list                 # Lobe, relative to (0, crown_y, 0)
    rim_noise: float = 0.12     # fraction of radius the noise may eat
    rim_freq: float = 0.30
    notches: int = 3            # bites out of the upper rim
    notch_r: float = 1.7
    tufts: int = 12             # single leaf cubes stuck on the upper shell
    branches: int = 3
    branch_len: float = 4.5
    foot_flare: float = 0.6
    roots: int = 2
    tone_shift: int = 0         # +1 = a paler species, -1 = a darker one
    dither: float = 0.32        # share of leaf voxels that shift one tone
    crown_xz: float = 1.0       # horizontal squeeze: trees stand 16 px apart


def _round() -> Species:
    # the Kanto tree: one round crown on a short bole, a little top-heavy
    return Species(
        name="round", seed=11, trunk_h=8.0, trunk_r=1.15, lean=0.8, crown_y=14.5,
        lobes=[Lobe(0, 0, 0, 6.6, 6.0), Lobe(2.6, 2.2, 1.4, 3.4, 3.0),
               Lobe(-2.8, 1.6, -1.8, 3.2, 2.8), Lobe(0.6, -1.4, 3.0, 3.0, 2.4),
               Lobe(-1.4, 3.4, -0.4, 2.8, 2.4)],
        rim_noise=0.13, rim_freq=0.28, notches=3, tufts=14, branches=3,
    )


def _tiered() -> Species:
    # two masses stacked, the upper one narrower and off-axis
    return Species(
        name="tiered", seed=23, trunk_h=7.0, trunk_r=1.2, lean=1.0, crown_y=13.0,
        lobes=[Lobe(0, -0.6, 0, 6.8, 4.2), Lobe(1.2, 5.2, -0.8, 4.6, 3.8),
               Lobe(-2.2, 2.4, 2.0, 3.2, 2.6), Lobe(2.6, 1.0, 2.4, 2.8, 2.2)],
        rim_noise=0.11, rim_freq=0.32, notches=2, tufts=12, branches=3,
        branch_len=4.0, tone_shift=0,
    )


def _broad() -> Species:
    # low and wide: three lobes side by side on a stubby bole
    return Species(
        name="broad", seed=37, trunk_h=6.0, trunk_r=1.3, lean=0.6, crown_y=11.5,
        lobes=[Lobe(0, 0.4, 0, 5.4, 4.6), Lobe(4.2, -0.6, 1.0, 4.2, 3.6),
               Lobe(-4.0, -0.2, -1.4, 4.0, 3.4), Lobe(0.8, 3.2, -2.4, 3.2, 2.6),
               Lobe(-1.2, 2.2, 3.0, 2.8, 2.4)],
        rim_noise=0.12, rim_freq=0.30, notches=3, tufts=14, branches=4,
        branch_len=5.0, tone_shift=-1, crown_xz=0.92,
    )


def _tall() -> Species:
    # narrow and tall: an egg of a crown with a small cap, longer bole
    return Species(
        name="tall", seed=53, trunk_h=9.5, trunk_r=1.1, lean=1.2, crown_y=16.0,
        lobes=[Lobe(0, 0, 0, 5.4, 6.8), Lobe(0.8, 4.6, 0.6, 3.4, 3.2),
               Lobe(-2.6, -1.2, 1.6, 3.0, 2.8), Lobe(2.4, 1.6, -2.0, 2.8, 2.6)],
        rim_noise=0.12, rim_freq=0.30, notches=2, tufts=11, branches=2,
        branch_len=4.0, tone_shift=1,
    )


SPECIES = [_round(), _tiered(), _broad(), _tall()]


def scaled(sp: Species, k: float) -> Species:
    """The species authored at VOX = 2; every length in voxels scales by k
    so the tree keeps its world size when the cube gets bigger or smaller."""
    if abs(k - 1.0) < 1e-6:
        return sp
    return Species(
        name=sp.name, seed=sp.seed, trunk_h=sp.trunk_h * k, trunk_r=max(0.7, sp.trunk_r * k),
        lean=sp.lean * k, crown_y=sp.crown_y * k,
        lobes=[Lobe(l.dx * k, l.dy * k, l.dz * k, l.r * k, l.ry * k) for l in sp.lobes],
        rim_noise=sp.rim_noise, rim_freq=sp.rim_freq / k, notches=sp.notches,
        notch_r=sp.notch_r * k, tufts=max(4, int(round(sp.tufts * k * k))),
        branches=sp.branches, branch_len=sp.branch_len * k, foot_flare=sp.foot_flare * k,
        roots=sp.roots, tone_shift=sp.tone_shift, dither=sp.dither, crown_xz=sp.crown_xz,
    )


# --------------------------------------------------------------------------
# growing
# --------------------------------------------------------------------------

def _unit(v):
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-9 else v


def _fill_segment(cells: dict, a, b, r0: float, r1: float, f0: float, f1: float):
    """Fill the voxels within a tapering radius of segment a->b; value = flex."""
    L = float(np.linalg.norm(b - a))
    n = max(1, int(L / 0.35))
    for i in range(n + 1):
        t = i / n
        p = a + (b - a) * t
        r = r0 + (r1 - r0) * t
        fl = f0 + (f1 - f0) * t
        R = int(math.ceil(r + 0.5))
        for x in range(int(math.floor(p[0])) - R, int(math.floor(p[0])) + R + 1):
            for y in range(int(math.floor(p[1])) - R, int(math.floor(p[1])) + R + 1):
                for z in range(int(math.floor(p[2])) - R, int(math.floor(p[2])) + R + 1):
                    d = math.sqrt((x + 0.5 - p[0]) ** 2 + (y + 0.5 - p[1]) ** 2
                                  + (z + 0.5 - p[2]) ** 2)
                    if d <= r:
                        k = (x, y, z)
                        if y >= 0 and (k not in cells or cells[k] < fl):
                            cells[k] = fl


def grow(sp: Species):
    """-> wood {cell: flex}, leaf {cell: (flex, hgt, rad)}, crown metrics."""
    rng = Rng(sp.seed * 7919 + 13)
    wood: dict = {}
    leaf: dict = {}

    # ---- the bole: three wandering segments, a flared foot, taper to 65%
    H = sp.trunk_h
    pts = [np.array([0.0, 0.0, 0.0])]
    drift = _unit(np.array([rng.range(-1, 1), 0.0, rng.range(-1, 1)])) * sp.lean
    for i in (1, 2, 3):
        t = i / 3.0
        wob = np.array([rng.range(-0.4, 0.4), 0.0, rng.range(-0.4, 0.4)])
        pts.append(np.array([drift[0] * t + wob[0], H * t, drift[2] * t + wob[2]]))
    top = pts[-1]
    for i in range(3):
        t0, t1 = i / 3.0, (i + 1) / 3.0
        r0 = sp.trunk_r * (1.0 - 0.35 * t0)
        r1 = sp.trunk_r * (1.0 - 0.35 * t1)
        _fill_segment(wood, pts[i], pts[i + 1], r0, r1, 0.16 * t0 * t0, 0.16 * t1 * t1)
    # the foot: a flare over the bottom voxel, plus root nubs
    _fill_segment(wood, pts[0] + np.array([0, -0.5, 0]), pts[0] + np.array([0, 1.2, 0]),
                  sp.trunk_r + sp.foot_flare, sp.trunk_r, 0.0, 0.0)
    for _ in range(sp.roots):
        ang = rng.range(0, math.tau)
        d = np.array([math.cos(ang), 0.0, math.sin(ang)])
        _fill_segment(wood, pts[0] + np.array([0, 0.4, 0]),
                      pts[0] + d * (sp.trunk_r + 1.5) + np.array([0, 0.2, 0]),
                      sp.trunk_r * 0.6, sp.trunk_r * 0.35, 0.0, 0.0)

    # ---- branches from the bole's top into the crown (mostly buried; a notch
    # or a thin spot shows wood, which is what says "tree" and not "lollipop")
    axis_x, axis_z = float(top[0]), float(top[2])
    for i in range(sp.branches):
        ang = (i / sp.branches) * math.tau + rng.range(-0.5, 0.5)
        d = _unit(np.array([math.cos(ang), rng.range(0.5, 1.0), math.sin(ang)]))
        a = top - np.array([0, rng.range(0.3, 1.5), 0])
        b = a + d * sp.branch_len * rng.range(0.85, 1.15)
        _fill_segment(wood, a, b, sp.trunk_r * 0.55, sp.trunk_r * 0.32, 0.18, 0.42)

    # ---- the leaf masses
    crown_R = max(math.hypot(l.dx, l.dz) * sp.crown_xz + l.r * sp.crown_xz for l in sp.lobes)
    crown_lo = min(l.dy - l.ry for l in sp.lobes) + sp.crown_y
    crown_hi = max(l.dy + l.ry for l in sp.lobes) + sp.crown_y

    def add_leaf(k, fl, hgt, rad):
        if k in wood or k[1] < 1:
            return
        cur = leaf.get(k)
        if cur is None or cur[0] < fl:
            leaf[k] = (fl, hgt, rad)

    for li, l in enumerate(sp.lobes):
        cx = axis_x + l.dx * sp.crown_xz
        cy = sp.crown_y + l.dy
        cz = axis_z + l.dz * sp.crown_xz
        R = l.r * sp.crown_xz
        ry = l.ry
        for x in range(int(math.floor(cx - R - 1)), int(math.ceil(cx + R + 1)) + 1):
            for y in range(int(math.floor(cy - ry - 1)), int(math.ceil(cy + ry + 1)) + 1):
                for z in range(int(math.floor(cz - R - 1)), int(math.ceil(cz + R + 1)) + 1):
                    px, py, pz = x + 0.5, y + 0.5, z + 0.5
                    d = math.sqrt(((px - cx) / R) ** 2 + ((py - cy) / ry) ** 2 + ((pz - cz) / R) ** 2)
                    if d > 1.3:
                        continue
                    n = fbm(px, py, pz, sp.rim_freq, sp.seed * 17 + li * 7) - 0.5
                    if d > 1.0 + sp.rim_noise * 2.0 * n * d:
                        continue
                    rad = math.hypot(px - axis_x, pz - axis_z) / max(crown_R, 1.0)
                    hgt = (py - crown_lo) / max(crown_hi - crown_lo, 1.0)
                    fl = 0.55 + 0.30 * min(1.0, 0.75 * rad + 0.35 * hgt)
                    add_leaf((x, y, z), fl, hgt, rad)

    # ---- notches: bites out of the upper rim, so the sky shows through and
    # the outline steps instead of curving
    for i in range(sp.notches):
        ang = (i / max(1, sp.notches)) * math.tau + rng.range(-0.6, 0.6)
        R = crown_R * rng.range(0.75, 0.95)
        nx = axis_x + math.cos(ang) * R
        nz = axis_z + math.sin(ang) * R
        ny = crown_lo + (crown_hi - crown_lo) * rng.range(0.55, 0.9)
        nr = sp.notch_r * rng.range(0.85, 1.2)
        for k in list(leaf.keys()):
            if math.sqrt((k[0] + 0.5 - nx) ** 2 + (k[1] + 0.5 - ny) ** 2 + (k[2] + 0.5 - nz) ** 2) < nr:
                del leaf[k]

    # ---- tufts: single cubes stuck to the upper shell, sticking out by one
    def solid(k):
        return k in wood or k in leaf
    shell = []
    for k, (fl, hgt, rad) in leaf.items():
        if hgt < 0.45:
            continue
        for i_dir, (dx, dy, dz) in enumerate(NEIGHBOUR):
            if i_dir == 3:                 # never hang a tuft under the crown
                continue
            nb = (k[0] + dx, k[1] + dy, k[2] + dz)
            if not solid(nb):
                shell.append((k, nb))
    tufts_added = 0
    guard = 0
    while tufts_added < sp.tufts and shell and guard < 400:
        guard += 1
        k, nb = shell[int(rng.next() * len(shell)) % len(shell)]
        if solid(nb) or nb[1] < 1:
            continue
        # a tuft must not touch anything but its parent: it is a single cube
        crowded = sum(1 for (dx, dy, dz) in NEIGHBOUR if solid((nb[0] + dx, nb[1] + dy, nb[2] + dz)))
        if crowded > 1:
            continue
        fl, hgt, rad = leaf[k]
        leaf[nb] = (0.92, min(1.0, hgt + 0.05), min(1.2, rad + 0.1))
        tufts_added += 1

    crown_R = max([math.hypot(k[0] + 0.5 - axis_x, k[2] + 0.5 - axis_z) for k in leaf] + [1.0])
    crown_lo = min(k[1] for k in leaf) if leaf else sp.crown_y
    crown_hi = (max(k[1] for k in leaf) + 1) if leaf else sp.crown_y

    return wood, leaf, dict(crown_R=crown_R, crown_lo=crown_lo, crown_hi=crown_hi,
                            axis=(axis_x, axis_z), tufts=tufts_added)


# --------------------------------------------------------------------------
# tones per voxel
# --------------------------------------------------------------------------

def leaf_tones(leaf: dict, sp_seed: int, tone_shift: int, dither: float) -> dict:
    """cell -> leaf material.  Height band first, then BLOTCHES, then sparkle.

    The first cut shifted tones per voxel off a hash, and it cost the whole
    budget: a face only merges with a neighbour of the same tone, so a
    one-in-three per-voxel dither left every leaf face on its own (1568
    tris on the round, over the 1200 the loader admits).  Blotches of
    low-frequency noise shift tones in patches of two or three cubes --
    which is what a clump of leaves in shade looks like anyway -- and the
    faces inside a patch still merge.  A few single-voxel highlights ride
    on top: those are the leaves catching the light, and five faces each
    is a price worth paying for ~6% of the crown.
    """
    out = {}
    ramp = [M_DEEP, M_DARK, M_MID, M_LIT, M_HI]
    for k, (fl, hgt, rad) in leaf.items():
        # 0..4 up the crown; the outer shell reads a touch lighter (it is lit)
        # the bands stop at LIT: `hi` is for the sparkle and the blotches
        # only, or a pale species wears a white cap (it did)
        t = hgt * 0.85 + rad * 0.25
        i = 1 if t < 0.32 else (2 if t < 0.62 else 3)
        i += tone_shift
        i = max(1, min(3, i))
        n = (fbm(k[0] + 0.5, k[1] + 0.5, k[2] + 0.5, 0.42, sp_seed + 303, 2) - 0.5) * 2.0
        if n < -dither:
            i -= 1
        elif n > dither:
            i += 1
        h = _h3(k[0], k[1], k[2], sp_seed + 101)
        if h < 0.06 and hgt > 0.5:
            i += 1
        i = max(0, min(4, i))
        out[k] = ramp[i]
    return out


def wood_tones(wood: dict, sp_seed: int) -> dict:
    out = {}
    for k in wood:
        h = _h3(k[0], k[1], k[2], sp_seed + 202)
        if k[1] <= 0:
            out[k] = M_ROOT if h < 0.5 else M_BARK_DARK
        else:
            out[k] = M_BARK_DARK if h < 0.45 else (M_BARK_MID if h < 0.85 else M_BARK_LIT)
    return out


# --------------------------------------------------------------------------
# faces: AO, greedy merge, emit
# --------------------------------------------------------------------------

def face_ao(solid, v, axis, sign) -> float:
    """1 open, 0 buried: how many of the 8 cells around this face are solid."""
    n = 0
    off = [0, 0, 0]
    off[axis] = sign
    base = (v[0] + off[0], v[1] + off[1], v[2] + off[2])
    u, w = [(1, 2), (0, 2), (0, 1)][axis]
    for du in (-1, 0, 1):
        for dw in (-1, 0, 1):
            if du == 0 and dw == 0:
                continue
            p = list(base)
            p[u] += du
            p[w] += dw
            if solid(tuple(p)):
                n += 1
    return 1.0 - n / 8.0


def greedy(cells, solid, key_of, max_run: int = 0):
    """Greedy rectangle merge of exposed faces sharing a key.

    -> (dirn, origin, du, dv, w, h, key) with origin at the face's min corner
    in voxel units.  max_run caps a rectangle's side (0 = unlimited).
    """
    out = []
    for dirn, (nx, ny, nz) in enumerate(NEIGHBOUR):
        axis = dirn // 2
        sign = 1 if dirn % 2 == 0 else -1
        u, w = [(1, 2), (0, 2), (0, 1)][axis]
        slices: dict = {}
        for c in cells:
            nb = (c[0] + nx, c[1] + ny, c[2] + nz)
            if solid(nb):
                continue
            k = key_of(c, axis, sign, dirn)
            layer = c[axis] + (1 if sign > 0 else 0)
            slices.setdefault(layer, {})[(c[u], c[w])] = k
        for layer, faces in slices.items():
            done = set()
            for (cu, cw) in sorted(faces):
                if (cu, cw) in done:
                    continue
                k = faces[(cu, cw)]
                ww = 1
                while (cu + ww, cw) in faces and (cu + ww, cw) not in done \
                        and faces[(cu + ww, cw)] == k and (not max_run or ww < max_run):
                    ww += 1
                hh = 1
                grow_ok = True
                while grow_ok and (not max_run or hh < max_run):
                    for i in range(ww):
                        p = (cu + i, cw + hh)
                        if p not in faces or p in done or faces[p] != k:
                            grow_ok = False
                            break
                    if grow_ok:
                        hh += 1
                for i in range(ww):
                    for j in range(hh):
                        done.add((cu + i, cw + j))
                origin = [0, 0, 0]
                origin[axis] = layer
                origin[u] = cu
                origin[w] = cw
                du = [0, 0, 0]
                du[u] = 1
                dv = [0, 0, 0]
                dv[w] = 1
                out.append((dirn, origin, du, dv, ww, hh, k))
    return out


AO_FLOOR = 0.60
BAND_SHADE = (0.80, 0.90, 1.00)     # low, middle, top of the crown
SHADE_STEPS = 32                    # quantised so neighbouring faces still merge


def q(x: float) -> float:
    return max(1.0 / SHADE_STEPS, round(x * SHADE_STEPS) / SHADE_STEPS)


def mesh_from_voxels(wood: dict, leaf: dict, wtone: dict, ltone: dict, crown: dict):
    """-> verts [[x,y,z,u,v,shade]], weights [flex], wood_idx, leaf_idx (voxel units)."""
    def solid(k):
        return k in wood or k in leaf

    # The keys decide what merges, so every term here is a budget decision:
    # flex is quantised coarsely (the vertex still carries the exact value
    # of the cell behind it, the key only has to keep a twig off a trunk
    # face), and leaf AO is two levels, not three -- crevice versus open is
    # what the eye reads on a crown; the third level bought nothing visible
    # and split every rim face.
    def wood_key(c, axis, sign, dirn):
        ao = face_ao(solid, c, axis, sign)
        lvl = 0 if ao < 0.5 else (1 if ao < 0.8 else 2)
        return ("w", wtone[c], lvl, round(wood[c] * 8))

    def leaf_key(c, axis, sign, dirn):
        ao = face_ao(solid, c, axis, sign)
        lvl = 0 if ao < 0.62 else 2
        fl, hgt, rad = leaf[c]
        band = 0 if hgt < 0.36 else (1 if hgt < 0.72 else 2)
        return ("l", ltone[c], band, lvl, round(fl * 6))

    wood_quads = greedy(wood, solid, wood_key)
    leaf_quads = greedy(leaf, solid, leaf_key)

    verts, weights, wood_idx, leaf_idx = [], [], [], []

    def emit(origin, du, dv, w, h, mat, shade, flex, into, dirn):
        uu, vv = slot_uv(mat)
        base = len(verts)
        corners = [(0, 0), (w, 0), (w, h), (0, h)]
        for (a, b) in corners:
            p = [origin[i] + du[i] * a + dv[i] * b for i in range(3)]
            verts.append([p[0], p[1], p[2], uu, vv, shade])
            weights.append(flex)
        # outward winding: flip for the negative faces
        if dirn % 2 == 0:
            into.extend([base, base + 1, base + 2, base, base + 2, base + 3])
        else:
            into.extend([base, base + 2, base + 1, base, base + 3, base + 2])

    def cell_behind(origin, dirn):
        return (origin[0] - (1 if dirn == 0 else 0),
                origin[1] - (1 if dirn == 2 else 0),
                origin[2] - (1 if dirn == 4 else 0))

    for (dirn, origin, du, dv, w, h, k) in wood_quads:
        _, mat, lvl, _ = k
        shade = q(FACE_SHADE[dirn] * (AO_FLOOR + (1 - AO_FLOOR) * lvl / 2.0))
        if dirn == 2:
            shade = -shade                 # sky-facing: the sign snow reads
        emit(origin, du, dv, w, h, mat, shade, wood.get(cell_behind(origin, dirn), 0.0),
             wood_idx, dirn)

    for (dirn, origin, du, dv, w, h, k) in leaf_quads:
        _, mat, band, lvl, _ = k
        shade = q(FACE_SHADE[dirn] * (AO_FLOOR + (1 - AO_FLOOR) * lvl / 2.0) * BAND_SHADE[band])
        if dirn == 2:
            shade = -shade
        cb = cell_behind(origin, dirn)
        fl = leaf[cb][0] if cb in leaf else 0.55
        emit(origin, du, dv, w, h, mat, shade, fl, leaf_idx, dirn)

    return verts, weights, wood_idx, leaf_idx


# --------------------------------------------------------------------------
# MagicaVoxel import
# --------------------------------------------------------------------------

def read_vox(path: Path):
    """-> list of (x, y, z, colour_index), list of 256 RGBA (index 1..255)."""
    blob = path.read_bytes()
    assert blob[:4] == b"VOX ", path
    pos = 8
    voxels, palette = [], None
    sizes = []
    while pos + 12 <= len(blob):
        cid = blob[pos:pos + 4]
        n, _children = struct.unpack_from("<II", blob, pos + 4)
        body = blob[pos + 12:pos + 12 + n]
        if cid == b"SIZE":
            sizes.append(struct.unpack_from("<III", body, 0))
        elif cid == b"XYZI" and not voxels:        # first model only
            cnt = struct.unpack_from("<I", body, 0)[0]
            for i in range(cnt):
                x, y, z, ci = struct.unpack_from("<BBBB", body, 4 + i * 4)
                voxels.append((x, y, z, ci))
        elif cid == b"RGBA":
            palette = [(0, 0, 0, 0)] + [struct.unpack_from("<BBBB", body, i * 4) for i in range(255)]
        pos += 12 + n
    if palette is None:
        palette = [(0, 0, 0, 0)] + [((i * 37) % 256, (i * 91) % 256, (i * 53) % 256, 255) for i in range(255)]
    return voxels, palette, sizes


def import_vox(path: Path, name: str, target_h: int, seed: int = 7):
    """A .vox as wood/leaf/tone dicts, Y up, scaled to target_h voxels."""
    voxels, palette, sizes = read_vox(path)
    if not voxels:
        raise SystemExit(f"{path}: no XYZI voxels")
    # MagicaVoxel is Z-up; the world is Y-up
    pts = [(x, z, y, ci) for (x, y, z, ci) in voxels]
    zmin = min(p[1] for p in pts)
    hmax = max(p[1] for p in pts) - zmin + 1
    s = target_h / hmax if target_h else 1.0
    xs = [p[0] for p in pts]
    zs = [p[2] for p in pts]
    cxm, czm = (min(xs) + max(xs) + 1) / 2.0, (min(zs) + max(zs) + 1) / 2.0

    # classify colours: green hue -> leaf (value rank -> tone), else bark
    def classify(rgba):
        r, g, b = [c / 255.0 for c in rgba[:3]]
        h, sat, v = colorsys.rgb_to_hsv(r, g, b)
        hd = h * 360
        return ("leaf" if (66 <= hd <= 170 and sat > 0.38) else "bark"), v

    seen = {}
    for (_x, _y, _z, ci) in pts:
        seen[ci] = seen.get(ci, 0) + 1
    for ci, n in sorted(seen.items(), key=lambda kv: -kv[1])[:8]:
        kind, v = classify(palette[ci])
        print(f"  vox colour {ci}: rgb={palette[ci][:3]} n={n} -> {kind} v={v:.2f}")

    cells: dict = {}
    for (x, y, z, ci) in pts:
        k = (int(math.floor((x - cxm) * s)), int(math.floor((y - zmin) * s)),
             int(math.floor((z - czm) * s)))
        kind, v = classify(palette[ci])
        cur = cells.get(k)
        if cur is None or (cur[0] == "bark" and kind == "leaf"):
            cells[k] = (kind, v)
    leaf_v = sorted(set(v for (kind, v) in cells.values() if kind == "leaf"))
    wood, leaf, wtone, ltone = {}, {}, {}, {}
    ys = [k[1] for k in cells]
    ymax = max(ys) + 1
    leafy = [k for k, (kind, v) in cells.items() if kind == "leaf"]
    crown_lo = min([k[1] for k in leafy] + [ymax])
    shift = {}
    for k, (kind, v) in cells.items():
        if kind == "leaf":
            hgt = (k[1] - crown_lo) / max(1, ymax - crown_lo)
            rad = math.hypot(k[0] + 0.5, k[2] + 0.5) / max(1.0, max(abs(kk[0]) for kk in leafy) + 1)
            leaf[k] = (0.55 + 0.30 * min(1.0, 0.75 * rad + 0.35 * hgt), hgt, rad)
            # the model's own light/dark leaf colours become a +-1 shift on
            # top of the height bands -- a one-colour model gets the bands
            # alone rather than every cube in the darkest tone
            if len(leaf_v) >= 3:
                r = leaf_v.index(v) / (len(leaf_v) - 1)
                shift[k] = -1 if r < 0.34 else (1 if r > 0.66 else 0)
        else:
            t = k[1] / max(1.0, crown_lo)
            wood[k] = 0.16 * min(1.0, t) ** 2 if k[1] < crown_lo else 0.35
            wtone[k] = M_BARK_DARK if v < 0.35 else (M_BARK_MID if v < 0.6 else M_BARK_LIT)
    crown_R = max([math.hypot(k[0] + 0.5, k[2] + 0.5) for k in leaf] + [1.0])
    crown = dict(crown_R=crown_R, crown_lo=crown_lo, crown_hi=ymax, axis=(0.0, 0.0), tufts=0)
    ltone = leaf_tones(leaf, seed, 0, 0.32)
    ramp = [M_DEEP, M_DARK, M_MID, M_LIT, M_HI]
    for k, d in shift.items():
        ltone[k] = ramp[max(0, min(4, ramp.index(ltone[k]) + d))]
    return wood, leaf, wtone, ltone, crown


# --------------------------------------------------------------------------
# bake
# --------------------------------------------------------------------------

def bake_mesh(name: str, wood, leaf, wtone, ltone, crown, report_only=False, source="grown"):
    verts, weights, wood_idx, leaf_idx = mesh_from_voxels(wood, leaf, wtone, ltone, crown)
    ax, az = crown["axis"]
    arr = np.asarray(verts, dtype=np.float64)
    arr[:, 0] = (arr[:, 0] - ax) * VOX
    arr[:, 1] = arr[:, 1] * VOX
    arr[:, 2] = (arr[:, 2] - az) * VOX
    nv = len(verts)
    indices = wood_idx + leaf_idx
    ni = len(indices)
    n_trunk = len(wood_idx)
    height = float(arr[:, 1].max())
    radius = float(np.sqrt(arr[:, 0] ** 2 + arr[:, 2] ** 2).max())
    canopy_y = float(crown["crown_lo"] * VOX)
    canopy_r = float(crown["crown_R"] * VOX)
    base_w = float(np.mean([weights[i] for i in range(nv) if arr[i, 1] < VOX * 1.5])) if nv else 0
    crown_w = float(np.mean([weights[i] for i in range(nv) if arr[i, 1] > height * 0.75])) if nv else 0
    stats = {
        "name": name, "verts": nv, "tris": ni // 3, "woodTris": n_trunk // 3,
        "leafTris": (ni - n_trunk) // 3, "height": height, "radius": radius,
        "canopyY": canopy_y, "canopyR": canopy_r, "weightBase": base_w,
        "weightCrown": crown_w, "woodVoxels": len(wood), "leafVoxels": len(leaf),
        "tufts": crown.get("tufts", 0), "vox": VOX,
    }
    print(f"{name}: verts={nv} tris={ni // 3} (wood {n_trunk // 3} + leaf {(ni - n_trunk) // 3}) "
          f"h={height:.0f}px r={radius:.0f}px canopyY={canopy_y:.0f} canopyR={canopy_r:.0f} "
          f"vox={len(wood)}w/{len(leaf)}l tufts={crown.get('tufts', 0)} "
          f"flex foot={base_w:.3f} crown={crown_w:.3f}")
    if report_only:
        return stats

    # ---- checks that would otherwise fail silently in the game
    if nv > 65535:
        raise SystemExit(f"{name}: {nv} verts do not fit a uint16 index buffer")
    if ni // 3 > BUDGET:
        raise SystemExit(f"{name}: {ni // 3} tris over the budget of {BUDGET} "
                         f"(Trees3D.MAX_TRIS={MAX_TRIS}); shrink the species")
    if base_w > 0.10:
        raise SystemExit(f"{name}: foot flex {base_w:.3f} -- it would sway from the roots")
    if crown_w < 0.55:
        raise SystemExit(f"{name}: crown flex {crown_w:.3f} -- the wind would not reach it")
    if max(weights) > 0.985:
        raise SystemExit(f"{name}: a solid vertex at flex {max(weights):.3f} would take the card tier")
    if arr[:, 4].max() > 0.75:
        raise SystemExit(f"{name}: a uv above the card cut")
    if not (height > 0):
        raise SystemExit(f"{name}: empty tree")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    strip_image().save(OUT_DIR / f"{name}.png")
    with open(OUT_DIR / f"{name}.mesh.bin", "wb") as f:
        f.write(MAGIC)
        f.write(struct.pack("<III", nv, ni, n_trunk))
        f.write(struct.pack("<ffff", height, radius, canopy_y, canopy_r))
        buf = np.empty((nv, 7), dtype=np.float32)
        buf[:, 0:6] = arr
        buf[:, 6] = np.asarray(weights, dtype=np.float32)
        f.write(buf.tobytes())
        f.write(np.asarray(indices, dtype=np.uint16).tobytes())
    meta = dict(stats)
    meta.update({
        "format": "terrarium-tree-v2", "kind": name, "set": "voxel",
        "bin": f"{name}.mesh.bin", "texture": f"{name}.png",
        "indices": ni, "trunkTris": n_trunk // 3, "canopyTris": (ni - n_trunk) // 3,
        "source": f"tools/grow_voxel_tree.py ({source})",
        "palette": "strip: row 0 leaf tones painted per map by Trees3D, row 1 bark fixed",
    })
    (OUT_DIR / f"{name}.meta.json").write_text(json.dumps(meta, indent=2))
    return stats


def bake_species(sp: Species, report_only=False):
    wood, leaf, crown = grow(sp)
    wtone = wood_tones(wood, sp.seed)
    ltone = leaf_tones(leaf, sp.seed, sp.tone_shift, sp.dither)
    return bake_mesh(sp.name, wood, leaf, wtone, ltone, crown, report_only)


# --------------------------------------------------------------------------
# offline preview: the game's camera, one tree and a wood
# --------------------------------------------------------------------------

PITCH = math.radians(52.0)
YAW = math.radians(28.0)


def load_bake(name: str):
    blob = (OUT_DIR / f"{name}.mesh.bin").read_bytes()
    nv, ni, ntrunk = struct.unpack_from("<III", blob, 4)
    height, radius, cy, cr = struct.unpack_from("<ffff", blob, 16)
    v = np.frombuffer(blob, dtype=np.float32, count=nv * 7, offset=32).reshape(nv, 7).copy()
    idx = np.frombuffer(blob, dtype=np.uint16, count=ni, offset=32 + nv * 28).astype(np.int32)
    return v, idx, dict(height=height, radius=radius, canopyY=cy, canopyR=cr)


def raster(v, idx, tex, size, span, sway=0.0, ground=(96, 132, 92), origin_y=0.80, yaw=YAW):
    """Vectorised per-triangle rasteriser, VertexShade x texel like Voxel3D."""
    th, tw = tex.shape[:2]
    pos = v[:, 0:3].astype(np.float64).copy()
    if sway:
        pos[:, 0] += sway * v[:, 6]
        pos[:, 2] += sway * v[:, 6] * 0.3
    cy, sy = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(PITCH), math.sin(PITCH)
    x = pos[:, 0] * cy - pos[:, 2] * sy
    z = pos[:, 0] * sy + pos[:, 2] * cy
    sx = x
    syy = -pos[:, 1] * cp + z * sp
    depth = pos[:, 1] * sp + z * cp
    scale = size / span
    px = sx * scale + size * 0.5
    py = syy * scale + size * origin_y
    img = np.zeros((size, size, 3), dtype=np.float32)
    img[:, :] = ground
    zbuf = np.full((size, size), 1e9, dtype=np.float64)
    tu = np.clip((v[:, 3] * tw).astype(int), 0, tw - 1)
    tv = np.clip((v[:, 4] * th).astype(int), 0, th - 1)
    for t in range(0, len(idx) - 2, 3):
        a, b, c = idx[t], idx[t + 1], idx[t + 2]
        ax, ay, bx, by, cx, cyy = px[a], py[a], px[b], py[b], px[c], py[c]
        den = (by - cyy) * (ax - cx) + (cx - bx) * (ay - cyy)
        if abs(den) < 1e-9:
            continue
        x0, x1 = int(max(0, min(ax, bx, cx))), int(min(size - 1, max(ax, bx, cx)) + 1)
        y0, y1 = int(max(0, min(ay, by, cyy))), int(min(size - 1, max(ay, by, cyy)) + 1)
        if x1 <= x0 or y1 <= y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
        w0 = ((by - cyy) * (xs - cx) + (cx - bx) * (ys - cyy)) / den
        w1 = ((cyy - ay) * (xs - cx) + (ax - cx) * (ys - cyy)) / den
        w2 = 1 - w0 - w1
        inside = (w0 >= -1e-4) & (w1 >= -1e-4) & (w2 >= -1e-4)
        if not inside.any():
            continue
        d = w0 * depth[a] + w1 * depth[b] + w2 * depth[c]
        zsub = zbuf[y0:y1, x0:x1]
        win = inside & (d < zsub)
        if not win.any():
            continue
        # flat per face: nearest texel of the first vertex, shade interpolated
        texel = tex[tv[a], tu[a]]
        if texel[3] < 128:
            continue
        sh = np.abs(w0 * v[a, 5] + w1 * v[b, 5] + w2 * v[c, 5])
        zsub[win] = d[win]
        sub = img[y0:y1, x0:x1]
        col = np.clip(texel[:3][None, None, :] * sh[..., None], 0, 255)
        sub[win] = col[win]
    return Image.fromarray(img.astype(np.uint8))


def stamp_copy(v, idx, ox, oz, yaw, scale, yscale, into_v, into_i):
    c, s = math.cos(yaw), math.sin(yaw)
    base = sum(len(a) for a in into_v)
    out = v.copy()
    x, y, z = v[:, 0] * scale, v[:, 1] * yscale, v[:, 2] * scale
    out[:, 0] = ox + x * c - z * s
    out[:, 1] = y
    out[:, 2] = oz + x * s + z * c
    into_v.append(out)
    into_i.append(idx + base)


def preview(names: list[str], size: int = 320):
    PREVIEW_DIR.mkdir(exist_ok=True, parents=True)
    tex = np.asarray(strip_image().convert("RGBA"), dtype=np.float32)
    span = 0.0
    loaded = {}
    for n in names:
        v, idx, m = load_bake(n)
        loaded[n] = (v, idx, m)
        span = max(span, m["height"] * 1.18, m["radius"] * 2.3)
    tiles = []
    for n in names:
        v, idx, m = loaded[n]
        im = raster(v, idx, tex, size, span)
        im.save(PREVIEW_DIR / f"preview_{n}.png")
        tiles.append(im)
        # the same tree leaning in a gale, to see the trunk stay put
        raster(v, idx, tex, size, span, sway=6.0).save(PREVIEW_DIR / f"preview_{n}_wind.png")
    if len(tiles) > 1:
        sheet = Image.new("RGB", (size * len(tiles), size))
        for i, t in enumerate(tiles):
            sheet.paste(t, (i * size, 0))
        sheet.save(PREVIEW_DIR / "preview_sheet.png")
        print(f"sheet: {PREVIEW_DIR / 'preview_sheet.png'}")

    # ---- a wood: sites 16 px apart, species/yaw/scale like Trees3D.placement
    def unit(x, z, salt):
        n = (x * 374761393 + z * 668265263 + salt * 1274126177) % 2147483647
        n = (n * 1103515245 + 12345) % 2147483647
        return (n % 100000) / 100000.0
    vs, iss = [], []
    cols, rows = 6, 4
    for r in range(rows):
        for c in range(cols):
            mx, mz = c * 16 + 8, r * 16 + 8
            pick = names[min(len(names) - 1, int(unit(mx, mz, 3) * len(names)))]
            v, idx, m = loaded[pick]
            sc = 0.5 * (1.55 + unit(mx, mz, 2) * 0.55)
            ysc = 0.5 * (1.50 + unit(mx, mz, 4) * 0.55)
            stamp_copy(v, idx, mx - cols * 8 + (unit(mx, mz, 5) - 0.5) * 6,
                       mz - rows * 8 + (unit(mx, mz, 6) - 0.5) * 6,
                       unit(mx, mz, 1) * math.tau, sc, ysc, vs, iss)
    V = np.concatenate(vs)
    I = np.concatenate(iss)
    # depth-sort by row so the nearer trees win ties cleanly (zbuf does the rest)
    im = raster(V, I, tex, 640, cols * 16 * 1.25, ground=(88, 176, 40), origin_y=0.62)
    im.save(PREVIEW_DIR / "preview_wood.png")
    print(f"wood: {PREVIEW_DIR / 'preview_wood.png'} ({len(V)} verts)")


# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", action="append", default=None)
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--vox", type=str, default=None, help="import a MagicaVoxel .vox instead of growing")
    ap.add_argument("--name", type=str, default=None, help="species name for --vox")
    ap.add_argument("--height", type=int, default=22, help="target height in voxels for --vox")
    ap.add_argument("--vox-size", type=float, default=None, help="world px per voxel (default 2)")
    ap.add_argument("--budget", type=int, default=None, help="preview experiments only: tris allowed")
    ap.add_argument("--preview-tag", type=str, default=None, help="subfolder of probe_out_voxeltree/")
    args = ap.parse_args()

    global VOX, BUDGET, PREVIEW_DIR
    if args.vox_size:
        VOX = float(args.vox_size)
    if args.budget:
        BUDGET = int(args.budget)
    if args.preview_tag:
        PREVIEW_DIR = PREVIEW_DIR / args.preview_tag

    names = []
    if args.vox:
        p = Path(args.vox)
        name = args.name or p.stem.lower().replace("-", "_")
        wood, leaf, wtone, ltone, crown = import_vox(p, name, args.height)
        bake_mesh(name, wood, leaf, wtone, ltone, crown, args.report, source=f"vox:{p.name}")
        names.append(name)
    else:
        for sp in SPECIES:
            if args.only and sp.name not in args.only:
                continue
            bake_species(scaled(sp, 2.0 / VOX), args.report)
            names.append(sp.name)

    if args.preview and not args.report:
        preview(names)


if __name__ == "__main__":
    main()
