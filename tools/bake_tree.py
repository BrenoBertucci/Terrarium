#!/usr/bin/env python3
"""Grow a voxel tree from nothing and bake the TTR2 that Trees3D stamps.

A second baker, written from scratch after the first voxel pass came out as
a heap of two-voxel cubes with white slashes through it.  Same output format
(TTR2, see lib/Trees3D.lua), different idea of what a tree is at this
camera.

WHAT A TREE HAS TO BE, SEEN FROM HERE
-------------------------------------
The overworld camera looks down at ~52 degrees from a few cells away.  Every
Gen 1 tree site is ONE CELL (site.r = 8 on all 2325 sites the probe counted
over four maps; the 2x2 r=16 branch never fires), so Trees3D.placement
scales a bake by only 0.78..1.05 and the file height IS the world height.
Trees stand 16 px apart, so the crown must be NARROW -- radius under ~14
px -- while the tree is tall, 40-50 px = 2.5-3 cells; a voxel at the
default lattice is ~2 world px = ~12 screen px on a 1536-wide frame.  That is enough
room for a real silhouette, and it means every shortcut shows:

  * ONE LATTICE.  Leaves on a doubled lattice are 12-screen-px cubes.  They
    do not read as clumps of foliage, they read as a pile of crates painted
    green.  Leaves here sit on the same unit grid as the wood; the greedy
    mesher merges the flat runs anyway, so the vertex cost is in the RIM,
    not in the resolution.
  * A CROWN IS A FEW ROUNDED MASSES, NOT ONE.  Real broadleaf crowns are
    cumulus: a core with lobes hanging off it.  Each lobe is an ellipsoid
    (flatter than it is wide), lobes overlap, and the rim of each is eaten
    by low-frequency noise so no outline is a circle.
  * THE TRUNK SHOWS.  The crown starts at roughly 40% of the height; below
    it a dark, slightly tapered column with a flared foot stands on the
    tile.  A tree whose trunk is buried is a bush.
  * LIGHT COMES FROM ABOVE.  Faces carry the renderer's own directional
    table (Voxel3D.FACE_SHADE) times two things a voxel canopy needs to
    read as a mass: crevice AO, and a top-to-bottom gradient so the
    underside of a lobe is darker than its cap.  Both are quantised to a
    few bands so faces still merge.
  * LEAVES ARE PICTURES OF LEAVES.  Alpha cards on the outer shell carry
    cutouts composed from CC0 photographs (tools/make_leaf_cards.py), tinted
    into the species' own greens.  A drawn lobe reads as a blob; a real
    leaf silhouette reads as a leaf, at 36 screen px.

Colour follows the Gen 1 rule the earlier texture work measured: foliage is
a yellow-green ramp with no blue.  Every palette below keeps B under 60.

THE WIND NEEDS A NUMBER PER VERTEX, and it is baked here as the 7th float:
zero at the foot, a little at the top of the bole (so the crown does not
slide off the trunk), more on branches, 0.55..0.85 across the leaf mass
rising outward, 0.999 on the cards.  Voxel3D's vertex stage rolls the crown
by it and, at the FULL tier, flutters the leaves by smoothstep(0.6, 0.98)
of it -- so a card dances, a rim leaf shivers, and the trunk stands.

Usage:
    python tools/bake_tree.py                  # all species
    python tools/bake_tree.py --only oak       # one
    python tools/bake_tree.py --report         # counts only
    python tools/bake_tree.py --preview        # also render probe_out_treefable/
"""
from __future__ import annotations

import argparse
import json
import math
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "ground" / "tree"
SRC_DIR = ROOT / "tools" / "_tree_src"          # CC0 photos, gitignored
PREVIEW_DIR = ROOT / "probe_out_treefable"

MAGIC = b"TTR2"
TEX_SIZE = 128
CARD_STRIP = 0.25                 # must match Trees3D.CARD_UV_CUT = 0.75
CARD_UV_CUT = 1.0 - CARD_STRIP
CARD_SLOTS = 4

# Voxel3D.FACE_SHADE, in this file's direction order:
#   0 +X east  1 -X west  2 +Y up  3 -Y down  4 +Z south  5 -Z north
FACE_SHADE = [0.84, 0.72, 1.00, 0.55, 0.90, 0.68]
NEIGHBOUR = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]

# Materials -> atlas fields (x, y, w, h).  Everything solid ends by y = 94,
# two rows short of the card cut at 96 (a quad's UV spans texel EDGES, and
# v == CARD_UV_CUT is the one value Trees3D's card test cannot classify).
M_BARK, M_BARK_LIT, M_LEAF_A, M_LEAF_B, M_LEAF_C, M_LEAF_D = range(6)
ATLAS = {
    M_BARK:     (0,  0,  64, 40),
    M_BARK_LIT: (64, 0,  64, 40),
    M_LEAF_A:   (0,  40, 64, 27),
    M_LEAF_B:   (64, 40, 64, 27),
    M_LEAF_C:   (0,  67, 64, 27),
    M_LEAF_D:   (64, 67, 64, 27),
}

# Leaf voxel flex range.  Kept BELOW the shader's 0.98 card line so the
# solid canopy shivers while only the cards do the full dance.
LEAF_FLEX_LO, LEAF_FLEX_HI = 0.55, 0.85
CARD_FLEX = 0.999


# --------------------------------------------------------------------------
# deterministic noise -- a species must bake byte-identical every run
# --------------------------------------------------------------------------

def _h3(i: int, j: int, k: int, seed: int) -> float:
    n = (i * 374761393 + j * 668265263 + k * 2147483647 + seed * 1274126177) & 0x7FFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0x7FFFFFFF
    return ((n ^ (n >> 16)) % 100000) / 100000.0


def vnoise(x: float, y: float, z: float, seed: int) -> float:
    xi, yi, zi = math.floor(x), math.floor(y), math.floor(z)
    fx, fy, fz = x - xi, y - yi, z - zi
    fx, fy, fz = (fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz))

    def c(dx, dy, dz):
        return _h3(xi + dx, yi + dy, zi + dz, seed)
    x00 = c(0, 0, 0) + (c(1, 0, 0) - c(0, 0, 0)) * fx
    x10 = c(0, 1, 0) + (c(1, 1, 0) - c(0, 1, 0)) * fx
    x01 = c(0, 0, 1) + (c(1, 0, 1) - c(0, 0, 1)) * fx
    x11 = c(0, 1, 1) + (c(1, 1, 1) - c(0, 1, 1)) * fx
    y0 = x00 + (x10 - x00) * fy
    y1 = x01 + (x11 - x01) * fy
    return y0 + (y1 - y0) * fz


def fbm(x: float, y: float, z: float, freq: float, seed: int, octaves: int = 3) -> float:
    """0..1, three octaves of value noise."""
    s, a, tot = 0.0, 1.0, 0.0
    for o in range(octaves):
        s += a * vnoise(x * freq, y * freq, z * freq, seed + o * 31)
        tot += a
        freq *= 2.1
        a *= 0.5
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
    """One rounded mass of leaves: centre (relative to the crown centre),
    radii (xz, y), and which leaf field its faces prefer."""
    dx: float
    dy: float
    dz: float
    r: float
    ry: float
    mat: int = M_LEAF_A


@dataclass
class Species:
    name: str
    seed: int
    target_h: float                  # world px, top of the crown
    trunk_h: float                   # voxels, ground to where the crown takes over
    trunk_r: float                   # voxels, at the foot (tapers to 60%)
    lean: float                      # how far the bole wanders, voxels
    crown_y: float                   # voxels, centre of the crown
    lobes: list                      # Lobe, relative to (0, crown_y, 0)
    rim_noise: float                 # fraction of radius the noise may eat
    rim_freq: float
    branches: int                    # wood branches from the bole into the crown
    branch_len: float
    bark: tuple
    bark_lit: tuple
    leaf: tuple                      # A base, B light, C dark, D highlight
    bark_photo: str | None
    cards: int
    card_half: float                 # voxels, half-width of a card
    card_tilt: tuple = (0.55, 0.95)  # 0 = vertical, 1 = flat; the camera looks down
    fronds: int = 0                  # willow: hanging strands from the rim
    frond_len: tuple = (7.0, 12.0)
    tiers: list = field(default_factory=list)   # pine: (y, r, ry) stacked discs
    foot_flare: float = 0.7
    crown_xz: float = 1.0            # horizontal squeeze of every lobe/tier: trees stand 16 px apart


def _oak() -> Species:
    return Species(
        name="oak", seed=11, target_h=44.0, crown_xz=0.80,
        trunk_h=9.5, trunk_r=1.7, lean=1.2, crown_y=19.5,
        lobes=[
            Lobe(0, 0, 0, 8.8, 7.6, M_LEAF_A),          # core
            Lobe(6.0, -1.5, 2.5, 6.0, 5.2, M_LEAF_B),
            Lobe(-6.2, -0.8, -1.5, 5.8, 5.0, M_LEAF_C),
            Lobe(1.5, -2.0, -6.4, 5.6, 4.8, M_LEAF_B),
            Lobe(-2.0, -1.2, 6.2, 5.8, 5.0, M_LEAF_A),
            Lobe(3.5, 4.6, -1.0, 5.6, 4.8, M_LEAF_B),   # top lobes
            Lobe(-3.0, 5.2, 2.0, 5.0, 4.4, M_LEAF_D),
        ],
        rim_noise=0.07, rim_freq=0.19, branches=5, branch_len=7.5,
        bark=(74, 52, 36), bark_lit=(104, 78, 54),
        leaf=((60, 122, 44), (92, 160, 58), (38, 88, 34), (118, 178, 70)),
        bark_photo="ph_jolcham_oak_bark_01_1k.jpg",
        cards=76, card_half=2.6,
    )


def _pine() -> Species:
    # Stacked discs with a GAP between them, so the bole shows between
    # tiers and each tier's lit top and dark underside read on their own
    # -- tiers that touch merge into one dark cone.
    tiers = []
    y, r = 7.0, 9.4
    while y < 33.0:
        tiers.append((y, r, 2.7))
        y += 5.4
        r *= 0.78
    return Species(
        name="pine", seed=23, target_h=48.0, crown_xz=0.92,
        trunk_h=32.0, trunk_r=1.35, lean=0.5, crown_y=20.0,
        lobes=[], tiers=tiers,
        rim_noise=0.14, rim_freq=0.26, branches=0, branch_len=0.0,
        bark=(66, 46, 34), bark_lit=(94, 68, 48),
        leaf=((44, 106, 52), (66, 136, 64), (28, 74, 42), (88, 156, 76)),
        bark_photo="ph_pine_bark_1k.jpg",
        cards=64, card_half=3.4, card_tilt=(0.40, 0.85),
    )


def _birch() -> Species:
    return Species(
        name="birch", seed=37, target_h=42.0, crown_xz=0.82,
        trunk_h=12.0, trunk_r=1.15, lean=1.6, crown_y=21.5,
        lobes=[
            Lobe(0, 0.5, 0, 6.8, 8.0, M_LEAF_A),
            Lobe(4.8, -2.0, 1.8, 5.0, 4.8, M_LEAF_B),
            Lobe(-4.6, -1.0, -2.2, 4.8, 4.6, M_LEAF_C),
            Lobe(0.8, -2.6, -5.0, 4.4, 4.2, M_LEAF_B),
            Lobe(-1.5, 4.8, 1.5, 4.6, 4.0, M_LEAF_D),
        ],
        rim_noise=0.12, rim_freq=0.24, branches=4, branch_len=6.0,
        bark=(178, 172, 158), bark_lit=(214, 210, 198),
        leaf=((98, 160, 62), (128, 190, 80), (66, 122, 48), (150, 204, 96)),
        bark_photo="ph_bark_bluegum_1k.jpg",
        cards=72, card_half=2.2, foot_flare=0.4,
    )


def _willow() -> Species:
    return Species(
        name="willow", seed=41, target_h=40.0, crown_xz=0.76,
        trunk_h=8.0, trunk_r=1.6, lean=1.4, crown_y=17.5,
        lobes=[
            Lobe(0, 0, 0, 9.4, 6.2, M_LEAF_A),
            Lobe(5.6, 1.0, 2.6, 5.4, 3.6, M_LEAF_B),
            Lobe(-5.9, 0.5, -2.2, 5.2, 3.4, M_LEAF_C),
            Lobe(1.8, 1.2, -6.1, 5.0, 3.4, M_LEAF_B),
            Lobe(-2.4, 3.6, 5.0, 5.0, 3.4, M_LEAF_D),
        ],
        rim_noise=0.08, rim_freq=0.20, branches=4, branch_len=8.0,
        bark=(84, 70, 50), bark_lit=(112, 96, 70),
        leaf=((90, 146, 66), (118, 176, 84), (58, 106, 50), (140, 192, 100)),
        bark_photo="ph_bark_willow_1k.jpg",
        cards=70, card_half=2.4, card_tilt=(0.45, 0.9),
        fronds=16, frond_len=(7.0, 12.0),
    )


SPECIES = [_oak(), _pine(), _birch(), _willow()]

# Lattice resolution.  Species are authored at RES = 1 (a ~33-voxel tree);
# the bake scales every length by this before growing, so RES = 0.7 grows
# the same silhouette from ~23 voxels and a voxel lands at ~2 world px.
# This is THE budget knob: the vertex count of a greedy-meshed crown goes
# with the voxel count of its rim, roughly RES squared.
RES = 0.55
LEAF_AO = True
LEAF_BAND = True


def scaled(sp: Species, res: float) -> Species:
    import copy
    s = copy.deepcopy(sp)
    for f in ("trunk_h", "trunk_r", "lean", "crown_y", "branch_len", "card_half", "foot_flare"):
        setattr(s, f, getattr(s, f) * res)
    s.frond_len = (sp.frond_len[0] * res, sp.frond_len[1] * res)
    s.lobes = [Lobe(l.dx * res, l.dy * res, l.dz * res, l.r * res, l.ry * res, l.mat)
               for l in sp.lobes]
    s.tiers = [(y * res, r * res, ry * res) for (y, r, ry) in sp.tiers]
    s.rim_freq = sp.rim_freq / res
    q = sp.crown_xz
    s.lobes = [Lobe(l.dx * q, l.dy, l.dz * q, l.r * q, l.ry, l.mat) for l in s.lobes]
    s.tiers = [(y, r * q, ry) for (y, r, ry) in s.tiers]
    s.branch_len *= q
    s.card_half *= (0.7 + 0.3 * q)
    return s


# --------------------------------------------------------------------------
# growing: wood and leaf cells on one lattice
#   wood: {(x,y,z): (flex, lit)}   leaf: {(x,y,z): (flex, mat, band)}
# --------------------------------------------------------------------------

def _unit(v):
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-9 else np.array([0.0, 1.0, 0.0])


def _perp(v, rng: Rng):
    ref = np.array([math.cos(rng.range(0, math.tau)), 0.0, math.sin(rng.range(0, math.tau))])
    p = np.cross(v, ref)
    return _unit(p) if np.linalg.norm(p) > 1e-6 else np.array([1.0, 0.0, 0.0])


def _fill_segment(wood: dict, a, b, r0: float, r1: float, flex0: float, flex1: float):
    seg = b - a
    ln = float(np.linalg.norm(seg))
    steps = max(2, int(ln * 2.5))
    for s in range(steps + 1):
        t = s / steps
        c = a + seg * t
        r = r0 + (r1 - r0) * t
        fl = flex0 + (flex1 - flex0) * t
        ri = max(0.5, r)
        lo = np.floor(c - ri).astype(int)
        hi = np.ceil(c + ri).astype(int)
        for x in range(lo[0], hi[0] + 1):
            for y in range(lo[1], hi[1] + 1):
                for z in range(lo[2], hi[2] + 1):
                    if math.dist((x + 0.5, y + 0.5, z + 0.5), tuple(c)) <= ri:
                        k = (x, y, z)
                        if k not in wood or wood[k] < fl:
                            wood[k] = fl


def grow(sp: Species):
    rng = Rng(sp.seed * 7919 + 13)
    wood: dict = {}
    leaf: dict = {}

    # ---- the bole: three segments that wander, a flared foot, taper to 60%
    H = sp.trunk_h
    pts = [np.array([0.0, 0.0, 0.0])]
    drift = np.array([rng.range(-1, 1), 0.0, rng.range(-1, 1)])
    drift = _unit(drift) * sp.lean
    for i in (1, 2, 3):
        t = i / 3.0
        wobble = np.array([rng.range(-0.6, 0.6), 0.0, rng.range(-0.6, 0.6)])
        pts.append(np.array([drift[0] * t + wobble[0], H * t, drift[2] * t + wobble[2]]))
    top = pts[-1]
    for i in range(3):
        t0, t1 = i / 3.0, (i + 1) / 3.0
        r0 = sp.trunk_r * (1.0 - 0.4 * t0)
        r1 = sp.trunk_r * (1.0 - 0.4 * t1)
        # a little of the crown's roll reaches the top of the bole, so the
        # crown never slides off it; squared so the foot stays planted
        _fill_segment(wood, pts[i], pts[i + 1], r0, r1, 0.18 * t0 * t0, 0.18 * t1 * t1)
    # the foot: a flare over the bottom two voxels, and two root nubs
    _fill_segment(wood, pts[0] + np.array([0, -0.5, 0]), pts[0] + np.array([0, 1.5, 0]),
                  sp.trunk_r + sp.foot_flare, sp.trunk_r, 0.0, 0.0)
    for _ in range(2):
        ang = rng.range(0, math.tau)
        d = np.array([math.cos(ang), 0.0, math.sin(ang)])
        _fill_segment(wood, pts[0] + np.array([0, 0.5, 0]),
                      pts[0] + d * (sp.trunk_r + 1.6) + np.array([0, 0.3, 0]),
                      sp.trunk_r * 0.55, sp.trunk_r * 0.3, 0.0, 0.0)

    # ---- pine: the bole runs through the crown; broadleaf: branches into it
    crown_c = np.array([top[0], sp.crown_y, top[2]])
    axis_x, axis_z = top[0], top[2]
    for i in range(sp.branches):
        ang = (i / sp.branches) * math.tau + rng.range(-0.4, 0.4)
        d = np.array([math.cos(ang), rng.range(0.55, 1.1), math.sin(ang)])
        d = _unit(d)
        a = top - np.array([0, rng.range(0.5, 2.5), 0])
        b = a + d * sp.branch_len * rng.range(0.85, 1.15)
        _fill_segment(wood, a, b, sp.trunk_r * 0.55, sp.trunk_r * 0.30, 0.16, 0.42)
        # one fork per branch, thinner, reaching toward the shell so a bare
        # twig or two pokes out of the crown
        d2 = _unit(d + _perp(d, rng) * 0.7 + np.array([0, 0.3, 0]))
        c = b + d2 * sp.branch_len * 0.55
        _fill_segment(wood, b, c, sp.trunk_r * 0.32, sp.trunk_r * 0.22, 0.42, 0.62)

    # ---- leaf masses
    def add_leaf(k, fl, mat, band):
        if k in wood:
            return
        cur = leaf.get(k)
        if cur is None or cur[0] < fl:
            leaf[k] = (fl, mat, band)

    def lobe_fill(cx, cy, cz, r, ry, mat, seed_off):
        R = r
        lo = (int(math.floor(cx - R - 1)), int(math.floor(cy - ry - 1)), int(math.floor(cz - R - 1)))
        hi = (int(math.ceil(cx + R + 1)), int(math.ceil(cy + ry + 1)), int(math.ceil(cz + R + 1)))
        for x in range(lo[0], hi[0] + 1):
            for y in range(lo[1], hi[1] + 1):
                for z in range(lo[2], hi[2] + 1):
                    px, py, pz = x + 0.5, y + 0.5, z + 0.5
                    dxn = (px - cx) / R
                    dyn = (py - cy) / ry
                    dzn = (pz - cz) / R
                    d = math.sqrt(dxn * dxn + dyn * dyn + dzn * dzn)
                    if d > 1.35:
                        continue
                    n = fbm(px, py, pz, sp.rim_freq, sp.seed * 17 + seed_off) - 0.5
                    # the rim only: noise scales with d so the core is solid
                    limit = 1.0 + sp.rim_noise * 2.0 * n * d
                    if d > limit:
                        continue
                    # flex: rises outward from the tree's axis, a touch with height
                    rad = math.sqrt((px - axis_x) ** 2 + (pz - axis_z) ** 2) / max(crown_R, 1.0)
                    hgt = (py - crown_lo) / max(crown_hi - crown_lo, 1.0)
                    fl = LEAF_FLEX_LO + (LEAF_FLEX_HI - LEAF_FLEX_LO) * min(1.0, 0.75 * rad + 0.35 * hgt)
                    # band: where in the crown's height this cell sits, 0 low .. 2 high
                    band = 0 if hgt < 0.36 else (1 if hgt < 0.72 else 2)
                    add_leaf((x, y, z), fl, mat, band)

    if sp.tiers:
        crown_R = max(t[1] for t in sp.tiers)
        crown_lo = min(t[0] - t[2] for t in sp.tiers)
        crown_hi = max(t[0] + t[2] for t in sp.tiers) + 2.0
        for i, (ty, tr, tyr) in enumerate(sp.tiers):
            # each tier is a disc slightly off-axis and a little squashed
            # underneath: the branches droop, so the lit face is the top
            ox = rng.range(-0.8, 0.8)
            oz = rng.range(-0.8, 0.8)
            mat = (M_LEAF_A, M_LEAF_B, M_LEAF_C)[i % 3]
            lobe_fill(axis_x + ox, ty, axis_z + oz, tr, tyr, mat, i * 7)
        # the tip
        lobe_fill(axis_x, crown_hi - 1.0, axis_z, 1.6, 2.2, M_LEAF_B, 99)
    else:
        crown_R = max(math.hypot(l.dx, l.dz) + l.r for l in sp.lobes)
        crown_lo = min(l.dy - l.ry for l in sp.lobes) + sp.crown_y
        crown_hi = max(l.dy + l.ry for l in sp.lobes) + sp.crown_y
        for i, l in enumerate(sp.lobes):
            lobe_fill(crown_c[0] + l.dx, crown_c[1] + l.dy, crown_c[2] + l.dz,
                      l.r, l.ry, l.mat, i * 7)

    # ---- willow fronds: hanging strands off the dome's rim.
    #
    # CARDS, NOT VOXELS.  A strand of leaf voxels is the most expensive
    # geometry a voxel mesh can hold -- every cell is isolated, so it emits
    # five or six faces and merges with nothing: 16 fronds cost ~1600 faces,
    # more than the whole crown.  A vertical alpha quad carrying a strand
    # sprite (slot 3 of the willow's card strip, see make_leaf_cards.py)
    # costs four vertices and hangs the same.
    fronds = []
    for i in range(sp.fronds):
        ang = (i / max(1, sp.fronds)) * math.tau + rng.range(-0.25, 0.25)
        R = crown_R * rng.range(0.80, 0.98)
        sx = axis_x + math.cos(ang) * R
        sz = axis_z + math.sin(ang) * R
        sy = sp.crown_y + rng.range(-1.0, 1.5)
        L = rng.range(*sp.frond_len)
        fronds.append((sx, sy, sz, ang, L))

    return wood, leaf, dict(crown_R=crown_R, crown_lo=crown_lo, crown_hi=crown_hi,
                            axis=(axis_x, axis_z), fronds=fronds)


# --------------------------------------------------------------------------
# faces: AO, greedy merge
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


def greedy(cells: dict, solid, key_of):
    """Greedy rectangle merge of exposed faces sharing a key.

    Returns (dirn, origin, du, dv, w, h, key) with origin at the face's
    min corner in voxel units, du/dv unit vectors along the face.
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
                # extend along u
                ww = 1
                while (cu + ww, cw) in faces and (cu + ww, cw) not in done \
                        and faces[(cu + ww, cw)] == k:
                    ww += 1
                # extend along w
                hh = 1
                grow_ok = True
                while grow_ok:
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


# --------------------------------------------------------------------------
# atlas
# --------------------------------------------------------------------------

def _field(w: int, h: int, base, contrast: float, seed: int,
           grain: float = 0.0, photo: Image.Image | None = None,
           clamp_blue: bool = True):
    """w x h texels the mesh samples ONE PER VOXEL (nearest filtering).

    A photograph, when given, supplies luminance statistics only -- cropped
    at ~3 source px per texel BEFORE resizing, so the run length of light
    and dark survives the downsample instead of averaging to flat noise.
    """
    rng = np.random.RandomState(seed)
    if photo is not None:
        sw, sh = photo.size
        cw, ch = min(sw, w * 3), min(sh, h * 3)
        ox = int(rng.randint(0, max(1, sw - cw + 1)))
        oy = int(rng.randint(0, max(1, sh - ch + 1)))
        s = photo.convert("L").crop((ox, oy, ox + cw, oy + ch)).resize((w, h), Image.BOX)
        lum = np.asarray(s, dtype=np.float32) / 255.0
        lum -= lum.mean()
        n = lum / (float(lum.std()) or 1.0) * 0.5
    else:
        n = rng.normal(0.0, 0.5, (h, w)).astype(np.float32)
        n = (n + np.roll(n, 1, 0) + np.roll(n, 1, 1)) / 2.2
    if grain > 0:
        cols = rng.normal(0.0, 1.0, (1, w)).astype(np.float32)
        n = n * (1.0 - grain) + cols * grain
    n = np.clip(n, -1.6, 1.6)
    b = np.asarray(base, dtype=np.float32)
    img = b[None, None, :] * (1.0 + n[:, :, None] * contrast)
    if clamp_blue:
        img[..., 2] = np.minimum(img[..., 2], 64)  # the no-blue rule, foliage only
    return np.clip(img, 0, 255).astype(np.uint8)


def _lobe_card(size: int, base, seed: int) -> Image.Image:
    """Fallback card when no photo cutout is on disk: a few hard lobes."""
    rng = Rng(seed)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    lobes = [(rng.range(0.2, 0.8) * size, rng.range(0.2, 0.8) * size, rng.range(0.14, 0.26) * size)
             for _ in range(6)]
    for y in range(size):
        for x in range(size):
            for (cx, cy, r) in lobes:
                if (x + 0.5 - cx) ** 2 + ((y + 0.5 - cy) * 1.2) ** 2 <= r * r:
                    t = fbm(x * 0.9, y * 0.9, 0.0, 0.35, seed) - 0.5
                    c = [min(255, max(0, int(base[i] * (1.0 + t * 0.5)))) for i in range(3)]
                    px[x, y] = (c[0], c[1], c[2], 255)
                    break
    return img


def build_atlas(sp: Species) -> Image.Image:
    img = Image.new("RGBA", (TEX_SIZE, TEX_SIZE), (0, 0, 0, 0))
    photo = None
    if sp.bark_photo and (SRC_DIR / sp.bark_photo).exists():
        photo = Image.open(SRC_DIR / sp.bark_photo)
    spec = {
        M_BARK:     (sp.bark,     0.34, 0.45, photo),
        M_BARK_LIT: (sp.bark_lit, 0.30, 0.45, photo),
        M_LEAF_A:   (sp.leaf[0],  0.30, 0.0, None),
        M_LEAF_B:   (sp.leaf[1],  0.27, 0.0, None),
        M_LEAF_C:   (sp.leaf[2],  0.32, 0.0, None),
        M_LEAF_D:   (sp.leaf[3],  0.24, 0.0, None),
    }
    for mat, (x, y, w, h) in ATLAS.items():
        base, contrast, grain, ph = spec[mat]
        arr = _field(w, h, base, contrast, sp.seed * 101 + mat, grain, ph,
                     clamp_blue=mat not in (M_BARK, M_BARK_LIT))
        img.paste(Image.fromarray(arr, "RGB").convert("RGBA"), (x, y))

    # the card strip: real leaf cutouts from tools/make_leaf_cards.py when
    # they exist, drawn lobes otherwise
    strip_y = int(TEX_SIZE * CARD_UV_CUT)
    slot = TEX_SIZE // CARD_SLOTS
    cards = SRC_DIR / f"leaf_cards_vox_{sp.name}.png"
    if cards.exists():
        strip = Image.open(cards).convert("RGBA")
        if strip.size != (TEX_SIZE, slot):
            strip = strip.resize((TEX_SIZE, slot), Image.NEAREST)
        # hard alpha again after any resize
        a = np.asarray(strip)
        a = a.copy()
        a[..., 3] = np.where(a[..., 3] > 127, 255, 0)
        img.paste(Image.fromarray(a, "RGBA"), (0, strip_y))
        used = "photo cutouts"
    else:
        for s in range(CARD_SLOTS):
            img.paste(_lobe_card(slot, sp.leaf[s % 3], sp.seed * 53 + s), (s * slot, strip_y))
        used = "drawn lobes"
    return img, used


# --------------------------------------------------------------------------
# bake
# --------------------------------------------------------------------------

def bake(sp: Species, report_only: bool = False) -> dict:
    wood, leaf, crown = grow(sp)
    if not wood or not leaf:
        raise SystemExit(f"{sp.name}: grew nothing (wood={len(wood)} leaf={len(leaf)})")

    def solid(p):
        return p in wood or p in leaf

    # ---- keys: what makes two neighbouring faces mergeable
    #
    # Wood: lit flank or not, two AO bands.  Leaves: material (per lobe),
    # height band, two AO bands.  Every extra key value is a merge boundary,
    # so the canopy carries exactly the three facts it needs to read as a
    # lit mass and nothing per voxel -- per-voxel variation comes from the
    # texel window in emit(), which costs no vertices.
    def wood_key(v, axis, sign, dirn):
        ao = face_ao(solid, v, axis, sign)
        lvl = 1 if ao > 0.55 else 0
        mat = M_BARK_LIT if dirn in (0, 4) else M_BARK
        return ("w", mat, lvl)

    def leaf_key(v, axis, sign, dirn):
        lvl = 1
        if LEAF_AO:
            ao = face_ao(solid, v, axis, sign)
            lvl = 1 if ao > 0.5 else 0
        _, mat, band = leaf[v]
        if not LEAF_BAND:
            band = 1
        # the lit side of the crown leans lighter, the far side darker --
        # the directional table does the brightness, this moves the HUE
        if dirn == 2 and mat == M_LEAF_C:
            mat = M_LEAF_A
        # a conifer's tiers are lit on top and nowhere else: the cap of
        # every tier takes the light field, so the stack reads as tiers
        if dirn == 2 and sp.tiers:
            mat = M_LEAF_B
        if dirn == 3:
            mat = M_LEAF_C
        return ("l", mat, band, lvl)

    wood_quads = greedy(wood, solid, wood_key)
    leaf_quads = greedy(leaf, solid, leaf_key)

    verts: list = []
    weights: list = []
    wood_idx: list = []
    leaf_idx: list = []

    def emit(origin, du, dv, w, h, mat, shade, flex, into, dirn):
        fx, fy, fw, fh = ATLAS[mat]
        ow, oh = min(w, fw), min(h, fh)
        hx = int(_h3(origin[0], origin[1], origin[2], 7 + dirn) * (fw - ow + 1))
        hy = int(_h3(origin[2], origin[0], origin[1], 11 + dirn) * (fh - oh + 1))
        u0, u1 = (fx + hx) / TEX_SIZE, (fx + hx + ow) / TEX_SIZE
        v0, v1 = (fy + hy) / TEX_SIZE, (fy + hy + oh) / TEX_SIZE
        base = len(verts)
        corners = [(0, 0, u0, v0), (w, 0, u1, v0), (w, h, u1, v1), (0, h, u0, v1)]
        for (a, b, uu, vv) in corners:
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

    AO_FLOOR = 0.58
    for (dirn, origin, du, dv, w, h, k) in wood_quads:
        _, mat, lvl = k
        shade = FACE_SHADE[dirn] * (AO_FLOOR + (1 - AO_FLOOR) * lvl)
        if dirn == 2:
            shade = -shade
        emit(origin, du, dv, w, h, mat, shade, wood.get(cell_behind(origin, dirn), 0.0),
             wood_idx, dirn)

    BAND_SHADE = (0.80, 0.92, 1.00)     # low, middle, top of the crown
    for (dirn, origin, du, dv, w, h, k) in leaf_quads:
        _, mat, band, lvl = k
        shade = FACE_SHADE[dirn] * (AO_FLOOR + (1 - AO_FLOOR) * lvl) * BAND_SHADE[band]
        if dirn == 2:
            shade = -shade
        cb = cell_behind(origin, dirn)
        fl = leaf[cb][0] if cb in leaf else LEAF_FLEX_LO
        emit(origin, du, dv, w, h, mat, shade, fl, leaf_idx, dirn)

    # ---- cards on the outer shell, weighted to the upper half (the camera
    # looks down), each tilted toward the sky and yawed at random
    ax, az = crown["axis"]
    shell = []
    for c, (fl, mat, band) in leaf.items():
        exposed = sum(1 for (nx, ny, nz) in NEIGHBOUR
                      if not solid((c[0] + nx, c[1] + ny, c[2] + nz)))
        if exposed >= 2:
            shell.append(c)
    shell.sort(key=lambda c: -(c[1] * 1.6 + math.hypot(c[0] + 0.5 - ax, c[2] + 0.5 - az)))
    picked = shell[:max(1, int(len(shell) * 0.80))]
    rng = Rng(sp.seed * 4177)
    card_idx: list = []
    slot_u = 1.0 / CARD_SLOTS
    for i in range(sp.cards):
        c = picked[int(rng.next() * len(picked)) % len(picked)]
        centre = np.array([c[0] + 0.5, c[1] + 0.5, c[2] + 0.5])
        # push out along the local radial so the card sits ON the shell
        radial = _unit(np.array([centre[0] - ax, (centre[1] - crown["crown_lo"]) * 0.5, centre[2] - az]))
        centre = centre + radial * 0.6
        half = sp.card_half * rng.range(0.8, 1.2)
        yaw = rng.range(0.0, math.tau)
        tilt = rng.range(*sp.card_tilt)            # 0 vertical .. 1 flat
        axu = np.array([math.cos(yaw), 0.0, math.sin(yaw)]) * half
        up = np.array([-math.sin(yaw) * tilt, math.sqrt(max(0.0, 1 - tilt * tilt)), math.cos(yaw) * tilt])
        axv = up * half
        slot = int(rng.next() * CARD_SLOTS) % CARD_SLOTS
        u0, u1 = slot * slot_u, (slot + 1) * slot_u
        if rng.next() < 0.5:
            u0, u1 = u1, u0            # mirrored: eight looks out of four slots
        hgt = (centre[1] - crown["crown_lo"]) / max(crown["crown_hi"] - crown["crown_lo"], 1.0)
        shade = (0.66 + 0.24 * min(1.0, max(0.0, hgt))) * rng.range(0.9, 1.08)
        base = len(verts)
        for (a, b, uu, vv) in ((-1, -1, u0, 1.0), (1, -1, u1, 1.0),
                               (1, 1, u1, CARD_UV_CUT), (-1, 1, u0, CARD_UV_CUT)):
            p = centre + axu * a + axv * b
            verts.append([float(p[0]), float(p[1]), float(p[2]), uu, vv, shade])
            weights.append(CARD_FLEX)
        card_idx.extend([base, base + 1, base + 2, base, base + 2, base + 3])

    # ---- fronds: one vertical quad each, the strand sprite in the last
    # slot, hung from the rim and facing outward with a little yaw so no
    # camera sees a whole ring of them edge-on.
    #
    # CARD FLEX, on purpose. The shader's leaf tier hinges a card on its
    # v = 0.75 edge and lets the v = 1.0 edge swing -- and a frond is hung
    # from its top edge, so that tier IS the pendulum a hanging strand
    # wants. The first cut gave fronds 0.80..0.97 to keep them under the
    # card line, and the probe on the other session counted 16 of 86
    # willow cards missing the leaf tier: those fronds swung like twigs
    # and read as stiffer than their neighbours.
    frond_half_w = 1.15
    fu0, fu1 = (CARD_SLOTS - 1) * slot_u, 1.0
    for (sx, sy, sz, ang, L) in crown.get("fronds", []):
        yaw = ang + math.pi * 0.5 + rng.range(-0.5, 0.5)
        axu = np.array([math.cos(yaw), 0.0, math.sin(yaw)]) * frond_half_w
        top = np.array([sx, sy, sz])
        # drifts outward a touch as it falls
        bot = top + np.array([math.cos(ang) * 0.8, -L, math.sin(ang) * 0.8])
        shade = 0.74 * rng.range(0.92, 1.04)
        base = len(verts)
        for (p, uu, vv, fl) in ((top - axu, fu0, CARD_UV_CUT, CARD_FLEX),
                                (top + axu, fu1, CARD_UV_CUT, CARD_FLEX),
                                (bot + axu, fu1, 1.0, CARD_FLEX),
                                (bot - axu, fu0, 1.0, CARD_FLEX)):
            verts.append([float(p[0]), float(p[1]), float(p[2]), uu, vv, shade])
            weights.append(fl)
        card_idx.extend([base, base + 1, base + 2, base, base + 2, base + 3])

    # ---- centre on the foot, scale to target height
    arr = np.array([[v[0], v[1], v[2]] for v in verts], dtype=np.float32)
    foot = [k for k in wood if k[1] <= 1]
    cx = sum(k[0] for k in foot) / len(foot) + 0.5
    cz = sum(k[2] for k in foot) / len(foot) + 0.5
    arr[:, 0] -= cx
    arr[:, 2] -= cz
    arr[:, 1] -= arr[:, 1].min()
    scale = sp.target_h / max(float(arr[:, 1].max()), 1e-6)
    arr *= scale
    for i, v in enumerate(verts):
        v[0], v[1], v[2] = float(arr[i, 0]), float(arr[i, 1]), float(arr[i, 2])

    height = float(arr[:, 1].max())
    radius = float(max(abs(arr[:, 0]).max(), abs(arr[:, 2]).max()))
    n_wood_v = len(wood_quads) * 4
    canopy = arr[n_wood_v:]
    canopy_y = float(canopy[:, 1].min())
    canopy_r = float(np.sqrt(canopy[:, 0] ** 2 + canopy[:, 2] ** 2).max())

    indices = wood_idx + leaf_idx + card_idx
    n_trunk = len(wood_idx)
    nv, ni = len(verts), len(indices)

    foot_w = [weights[i] for i in range(n_wood_v) if arr[i, 1] < height * 0.12]
    base_w = float(np.mean(foot_w)) if foot_w else 0.0
    crown_w = float(np.mean([weights[i] for i in range(nv) if arr[i, 1] > height * 0.75]))

    stats = {
        "name": sp.name, "verts": nv, "tris": ni // 3,
        "woodQuads": len(wood_quads), "leafQuads": len(leaf_quads),
        "cards": len(card_idx) // 6,
        "height": height, "radius": radius,
        "canopyY": canopy_y, "canopyR": canopy_r,
        "weightBase": base_w, "weightCrown": crown_w,
        "woodVoxels": len(wood), "leafVoxels": len(leaf),
        "voxelScale": scale,
    }
    print(f"{sp.name}: verts={nv} tris={ni // 3} "
          f"(wood {len(wood_quads)}q + leaf {len(leaf_quads)}q + {len(card_idx) // 6} cards) "
          f"h={height:.1f} r={radius:.1f} canopyY={canopy_y:.1f} canopyR={canopy_r:.1f} "
          f"vox={len(wood)}w/{len(leaf)}l scale={scale:.2f} "
          f"flex foot={base_w:.3f} crown={crown_w:.3f}")
    if report_only:
        return stats

    # ---- checks that would otherwise fail silently in the game
    if nv > 65535:
        raise SystemExit(f"{sp.name}: {nv} verts do not fit a uint16 index buffer")
    if base_w > 0.10:
        raise SystemExit(f"{sp.name}: foot flex {base_w:.3f} -- it would sway from the roots")
    if crown_w < 0.55:
        raise SystemExit(f"{sp.name}: crown flex {crown_w:.3f} -- the wind would not reach it")
    solid_v = max(v[4] for v in verts[:n_wood_v + len(leaf_quads) * 4])
    if solid_v > CARD_UV_CUT:
        raise SystemExit(f"{sp.name}: solid vertex at v={solid_v:.4f} above the card cut")
    if card_idx and min(verts[i][4] for i in card_idx) < CARD_UV_CUT:
        raise SystemExit(f"{sp.name}: card vertex below the card cut")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tex, cards_used = build_atlas(sp)
    tex.save(OUT_DIR / f"{sp.name}.png")
    with open(OUT_DIR / f"{sp.name}.mesh.bin", "wb") as f:
        f.write(MAGIC)
        f.write(struct.pack("<III", nv, ni, n_trunk))
        f.write(struct.pack("<ffff", height, radius, canopy_y, canopy_r))
        buf = np.empty((nv, 7), dtype=np.float32)
        for i, v in enumerate(verts):
            buf[i, 0:6] = v
            buf[i, 6] = weights[i]
        f.write(buf.tobytes())
        f.write(np.asarray(indices, dtype=np.uint16).tobytes())
    meta = dict(stats)
    meta.update({
        "format": "terrarium-tree-v2", "kind": sp.name,
        "bin": f"{sp.name}.mesh.bin", "texture": f"{sp.name}.png",
        "indices": ni, "trunkTris": n_trunk // 3, "canopyTris": (ni - n_trunk) // 3,
        "source": "tools/bake_tree.py (procedural voxel, one lattice)",
        "cards": cards_used, "targetHeight": sp.target_h,
    })
    (OUT_DIR / f"{sp.name}.meta.json").write_text(json.dumps(meta, indent=2))
    return stats


def preview(names):
    sys.path.insert(0, str(ROOT / "tools"))
    from preview_tree_bake import render, load, SIZE  # noqa: E402
    PREVIEW_DIR.mkdir(exist_ok=True)
    common = 0.0
    for n in names:
        _, _, m = load(n)
        common = max(common, m["height"] * 1.18, m["radius"] * 2.3)
    tiles = []
    for n in names:
        out = PREVIEW_DIR / f"preview_{n}.png"
        render(n, out, span=common)
        tiles.append(Image.open(out))
    sheet = Image.new("RGB", (SIZE * len(tiles), SIZE))
    for i, t in enumerate(tiles):
        sheet.paste(t, (i * SIZE, 0))
    sheet.save(PREVIEW_DIR / "preview_sheet.png")
    print("sheet:", PREVIEW_DIR / "preview_sheet.png")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", action="append", default=None)
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--res", type=float, default=None)
    ap.add_argument("--no-leaf-ao", action="store_true")
    ap.add_argument("--no-band", action="store_true")
    args = ap.parse_args()
    global LEAF_AO, LEAF_BAND
    if args.no_band:
        LEAF_BAND = False
    if args.no_leaf_ao:
        LEAF_AO = False
    res = args.res if args.res is not None else RES
    done = []
    for sp in SPECIES:
        if args.only and sp.name not in args.only:
            continue
        bake(scaled(sp, res), report_only=args.report)
        done.append(sp.name)
    if args.preview and not args.report:
        preview(done)


if __name__ == "__main__":
    main()
