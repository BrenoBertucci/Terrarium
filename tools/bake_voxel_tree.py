#!/usr/bin/env python3
"""Grow a voxel tree from nothing and bake the TTR2 that Trees3D stamps.

WHY THIS EXISTS NEXT TO optimize_tree_glb.py
--------------------------------------------
That tool takes a photogrammetry-grade GLB and decimates it to 420 triangles.
420 triangles is not a budget a scanned tree degrades into gracefully -- it is
two orders of magnitude below what the model was authored at, so what survives
is a lumpy silhouette with the branches collapsed out of it.  At the size a
tree actually occupies on screen (~50 px) that reads as a green blob on a
stick: no leaves, no structure, and nothing for the wind to move that the eye
can follow.

A voxel tree spends the same triangles completely differently.  Every quad it
emits is a face the silhouette needs, because the mesh IS the silhouette --
there is no interior to waste budget on and no decimator guessing which edge
matters.  So the same ~1100 vertices buy a trunk you can see, branches that
fork, and a canopy made of separable clumps instead of one shell.

THE BUDGET IS IN VERTICES, NOT TRIANGLES
----------------------------------------
Trees3D.MAX_TRIS reads like the constraint, but the thing that costs on this
hardware is the vertex stage: the whole forest is ONE mesh (862 sites on
ROUTE_2) and every vertex runs the sway branch.  The shipped GLB bake is
1091 verts / 420 tris -- barely indexed, because a decimator's output shares
almost nothing.

Greedy-meshed voxel quads are 4 verts / 2 tris each, so:

    1091 verts / 4  =  272 quads  =  544 triangles

...at the SAME vertex cost as what ships today.  That is the target this file
aims at, and why Trees3D.MAX_TRIS moves to 560 rather than staying at 450:
450 would refuse a mesh that is cheaper to draw than the one it replaces.

TWO LATTICES, ON PURPOSE
------------------------
Wood is voxelised at full resolution and leaves at half (LEAF_SCALE), which is
an art decision before it is a budget one.  Foliage at wood resolution reads as
gravel -- individual leaf voxels are ~1.5 screen px and just dither the
silhouette.  Doubled, a leaf voxel is a CLUMP: it holds a colour long enough to
be seen, it catches the ambient-occlusion gradient, and the canopy gets a
blocky read that says "mass of leaves" instead of "noise".  It also cuts leaf
faces 4x, which is what pays for the trunk and branches.

Usage:
    python tools/bake_voxel_tree.py                 # all species
    python tools/bake_voxel_tree.py --only vox_oak  # one
    python tools/bake_voxel_tree.py --report        # counts, no files written
"""

from __future__ import annotations

import argparse
import json
import math
import struct
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image

OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "ground" / "tree"

MAGIC = b"TTR2"

# Must match Trees3D.CARD_UV_CUT (0.75) on the other side.  Cards live in the
# BOTTOM strip of the atlas and the solid mesh is squeezed above it.
CARD_STRIP = 0.25
CARD_UV_CUT = 1.0 - CARD_STRIP

# 256 so the photo leaf-card strip (tools/make_leaf_cards.py's _x2, 256x64)
# drops in 1:1.  Solids still land one texel per voxel -- the extra resolution
# is spent on the cards, which is the only place a leaf SHAPE can read.
TEX_SIZE = 256

# Leaves are voxelised on a lattice this many wood-voxels across.
LEAF_SCALE = 2

# Ambient occlusion floor.  A fully enclosed face keeps this fraction of its
# directional shade.  Baked, not computed at runtime: the renderer has no
# normals and no AO pass, so this is the only thing giving a voxel canopy
# interior depth -- without it a crown is one flat green plate with a rim.
AO_MIN = 0.52

# Occlusion bands on the canopy.  Every band is a place two neighbouring
# faces stop being mergeable, so this is a budget knob as much as a shading
# one -- see the note beside its use in bake().
AO_CANOPY_LEVELS = 3

# Directional face shade, mirroring Voxel3D.FACE_SHADE exactly.  The sun hangs
# in the SOUTHEAST, so +X (east) and +Z (south) are the lit flanks.  A tree
# lit by a different table than the terrain beside it reads as a sticker.
FACE_SHADE = {
    0: 0.84,   # +X east, toward the sun
    1: 0.72,   # -X west, away
    2: 1.00,   # +Y up
    3: 0.55,   # -Y down
    4: 0.90,   # +Z south, toward the camera and the sun
    5: 0.68,   # -Z north, away
}

# Materials.  The index is into ATLAS_FIELDS below.
M_BARK, M_BARK_LIT, M_LEAF_A, M_LEAF_B, M_LEAF_C = range(5)

# Atlas layout in texels: (x, y, w, h).  Every solid field must end at or
# before y = TEX_SIZE * CARD_UV_CUT = 96, and in practice well before it --
# a quad's UV spans texel EDGES, so a field ending exactly on the cut would
# produce v == CARD_UV_CUT, which is the one value the card test cannot
# discriminate on (see the long note in Trees3D.loadTemplate).
# Texel windows, doubled with TEX_SIZE.  Solids must end well before
# y = TEX_SIZE * CARD_UV_CUT = 192 -- a quad's UV spans texel EDGES, so a
# field ending on the cut would produce v == CARD_UV_CUT and the card test
# could not tell it from a card (see Trees3D.loadTemplate).
ATLAS_FIELDS = {
    M_BARK:     (0,    0, 128, 64),
    M_BARK_LIT: (128,  0, 128, 64),
    M_LEAF_A:   (0,   64, 128, 56),
    M_LEAF_B:   (128, 64, 128, 56),
    M_LEAF_C:   (0,  120, 128, 56),
}
CARD_SLOTS = 4                      # 64x64 sprites along the bottom strip

SRC = Path(__file__).resolve().parent / "_tree_src"

# Per-species CC0 photos already sitting in tools/_tree_src (ambientCG leaves,
# Poly Haven bark).  Luminance only for the solid fields; the card strip is
# the actual leaf photograph, hue-shifted by make_leaf_cards.py.
SPECIES_PHOTOS = {
    "vox_oak": {
        "bark": SRC / "ph_jolcham_oak_bark_01_1k.jpg",
        "leaf": SRC / "LeafSet010" / "LeafSet010_1K-JPG_Color.jpg",
        "cards": SRC / "leaf_cards_vox_oak_x2.png",
    },
    "vox_pine": {
        "bark": SRC / "ph_pine_bark_1k.jpg",
        "leaf": SRC / "LeafSet019" / "LeafSet019_1K-JPG_Color.jpg",
        "cards": SRC / "leaf_cards_vox_pine_x2.png",
    },
    "vox_birch": {
        "bark": SRC / "ph_bark_bluegum_1k.jpg",
        "leaf": SRC / "LeafSet024" / "LeafSet024_1K-JPG_Color.jpg",
        "cards": SRC / "leaf_cards_vox_birch_x2.png",
    },
    "vox_willow": {
        "bark": SRC / "ph_bark_willow_1k.jpg",
        "leaf": SRC / "LeafSet022" / "LeafSet022_1K-JPG_Color.jpg",
        "cards": SRC / "leaf_cards_vox_willow_x2.png",
    },
}


# --------------------------------------------------------------------------
# deterministic noise
#
# No numpy RNG in the shape functions: a species has to bake byte-identical
# every time or a re-bake silently reshuffles every forest in the game, and
# "the trees moved" is not a diff anyone can read.
# --------------------------------------------------------------------------

def _h3(i: int, j: int, k: int, seed: int) -> float:
    n = (i * 374761393 + j * 668265263 + k * 2147483647 + seed * 1274126177) & 0x7FFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0x7FFFFFFF
    return ((n ^ (n >> 16)) % 100000) / 100000.0


def vnoise(x: float, y: float, z: float, freq: float, seed: int) -> float:
    """Value noise on a lattice, trilinear, smoothstepped.  0..1."""
    x, y, z = x * freq, y * freq, z * freq
    i, j, k = math.floor(x), math.floor(y), math.floor(z)
    fx, fy, fz = x - i, y - j, z - k
    sx = fx * fx * (3 - 2 * fx)
    sy = fy * fy * (3 - 2 * fy)
    sz = fz * fz * (3 - 2 * fz)
    out = 0.0
    for dk in (0, 1):
        for dj in (0, 1):
            for di in (0, 1):
                w = ((sx if di else 1 - sx)
                     * (sy if dj else 1 - sy)
                     * (sz if dk else 1 - sz))
                out += w * _h3(i + di, j + dj, k + dk, seed)
    return out


def fbm(x: float, y: float, z: float, freq: float, seed: int, oct_: int = 3) -> float:
    tot, amp, norm = 0.0, 1.0, 0.0
    for o in range(oct_):
        tot += amp * vnoise(x, y, z, freq * (2 ** o), seed + o * 7919)
        norm += amp
        amp *= 0.5
    return tot / norm


class Rng:
    """Tiny LCG.  Deterministic across Python versions, unlike hash()."""

    def __init__(self, seed: int):
        self.s = (seed * 2654435761 + 1) & 0xFFFFFFFF

    def next(self) -> float:
        self.s = (self.s * 1103515245 + 12345) & 0x7FFFFFFF
        return self.s / 0x7FFFFFFF

    def range(self, a: float, b: float) -> float:
        return a + (b - a) * self.next()


# --------------------------------------------------------------------------
# species
# --------------------------------------------------------------------------

@dataclass
class Species:
    name: str
    seed: int

    # skeleton, in wood voxels
    trunk_h: float = 15.0            # bole before the first fork
    trunk_r: float = 2.6
    # Radius lost between the foot and the top of the bole, as a fraction.
    # A bole that keeps its gauge all the way up reads as a post; one that
    # narrows reads as a stem that had to carry less the higher it went.
    trunk_taper: float = 0.30
    lean: float = 0.6                # how far the bole wanders off vertical
    levels: int = 3                  # fork depth below the trunk
    children: tuple = (3, 3, 2)      # forks per level
    len_decay: float = 0.66
    rad_decay: float = 0.55
    spread: float = 0.85             # radians off the parent's axis
    droop: float = 0.0               # downward bias added per level (willow)
    first_len: float = 9.0

    # WHORLS -- rings of branches spaced down the bole, instead of one fork at
    # the top.  Without these every species came out the same shape: a stub of
    # trunk with a ball balanced on it, which is a bush.  A tree has limbs at
    # several heights, and a conifer is nothing BUT that -- its silhouette is
    # long branches low and short ones high, which is `whorl_taper`, not any
    # amount of tweaking a single crown.
    whorls: int = 1                  # 1 = fork at the top only
    whorl_span: float = 0.0          # fraction of the bole the rings cover
    whorl_taper: float = 0.0         # extra length for the lowest ring

    # canopy
    clump_r: float = 5.2             # leaf clump radius, in wood voxels
    clump_r_decay: float = 0.82
    clump_levels: int = 2            # branch levels that carry leaf clumps
    clump_noise: float = 0.42        # how ragged the clump surface is
    clump_freq: float = 0.30
    clump_squash: float = 1.45       # >1 flattens the clump; 1 is a sphere
    canopy_lift: float = 0.0         # push clumps up the branch axis
    tier: float = 0.0                # conifer: clump radius falls with height

    # CONIFER TIERS.  When `tier` is set the whorls stop carrying branch-tip
    # clumps and instead each ring becomes one flattened disc centred ON THE
    # BOLE, its radius shrinking with height by `tier`.  Branch-tip clumps
    # never made a cone: three lobes at 120 degrees on every ring, stacked
    # at random phases, sum to a lumpy column no matter how the taper is
    # set, because the eye reads the OUTLINE of the stack and lobes have no
    # outline in common.  A disc has one -- a circle -- and a stack of
    # circles that shrink upward is the conifer glyph everyone knows.
    disc_squash: float = 3.0         # flattening of a tier disc (>1 = flatter)
    leader: float = 0.0              # voxels of spike above the top whorl

    # THE TOP CLUMP.  One clump sat on the bole's tip, `top_r` times
    # clump_r, lifted `top_lift` voxels.  Branch-tip clumps alone build a
    # crown whose highest point is wherever the steepest limb happened to
    # end, which on average is the rim -- so the crown came out a slab with
    # a dished middle.  A tree's crown is highest over its trunk; this is
    # the clump that puts it there and turns the slab into a dome.
    top_r: float = 0.0
    top_lift: float = 0.0

    # look
    bark: tuple = (86, 62, 44)
    bark_lit: tuple = (112, 84, 58)
    leaf: tuple = ((64, 128, 56), (86, 154, 64), (44, 96, 44))
    grain: float = 0.34              # bark contrast
    mottle: float = 0.30             # leaf contrast

    cards: int = 34
    card_size: float = 0.70          # fraction of the local clump radius
    # Tilt range of the crown cards, 0 = vertical, 1 = flat.  The camera is
    # pitched 52 degrees so both extremes disappear edge-on; the default
    # band keeps them all readable.
    card_tilt: tuple = (0.25, 0.75)

    # FRONDS -- vertical alpha cards hung from the crown's lower rim.  The
    # willow's whole identity is the curtain that hangs below the cap, and
    # a curtain built from leaf cells costs four side faces per cell that
    # merge with nothing; a hanging card is four vertices, sways at full
    # weight for free, and is drawn as strands rather than as blocks, which
    # at this size is the right read for something one voxel wide anyway.
    fronds: int = 0
    frond_len: float = 0.0           # wood voxels, top to tip
    frond_w: float = 0.0             # wood voxels across

    # World height in pixels this tree bakes to.  DERIVED into a voxel scale
    # after growth rather than set as one, because the thing that has to be
    # right is how tall a tree stands next to a 16 px cell -- and the voxel
    # count that produces changes with every shape parameter above it.
    #
    # 52 against the last bake's 43.  Trees3D stamps at ~1.5-2.1x, so this
    # is a tree the player looks UP at (5-7 cells) instead of a bush they
    # look level into.
    target_h: float = 52.0


SPECIES = [
    # The workhorse.  Everything about it is "a tree": one bole, a fork at
    # eye height, a crown a little wider than it is deep.
    #
    # THE BOLE SHOWS FOR ITS BOTTOM THIRD, and that is the number every
    # other number here serves.  The first cut forked at 70% of a 15-voxel
    # bole with a 2.4 radius, and what came out was a stump wearing a hat:
    # the crown swallowed the trunk two voxels above the ground and the
    # trunk was as wide as it was tall.  Whorls now sit in the top fifth,
    # the radius is a 3-wide column, and the dome is built from two rings
    # of clumps -- the inner ring higher and larger, the outer lower and
    # smaller -- which is what makes it a dome and not a ball.
    Species(
        name="vox_oak", seed=1,
        trunk_h=16.0, trunk_r=1.7, trunk_taper=0.25, lean=0.5,
        levels=2, children=(3, 2),
        whorls=2, whorl_span=0.18, whorl_taper=0.5,
        first_len=4.5, len_decay=0.60, rad_decay=0.50, spread=0.78,
        clump_r=4.0, clump_r_decay=0.85, clump_levels=2,
        clump_noise=0.50, clump_freq=0.36, canopy_lift=-0.05,
        clump_squash=1.40,
        bark=(84, 60, 42), bark_lit=(116, 88, 60),
        leaf=((62, 126, 54), (88, 158, 66), (40, 92, 42)),
        cards=42, card_size=1.05, target_h=52.0,
    ),
    # Conifer.  Tall, narrow, tiered.  No branches at all: the tiers are
    # discs on the bole (see `disc_squash`), seven of them over the top
    # two-thirds, shrinking to a spike.  Bluer and darker than the
    # broadleaves so a mixed stand reads as two kinds of tree at a glance.
    Species(
        name="vox_pine", seed=2,
        trunk_h=26.0, trunk_r=1.5, trunk_taper=0.45, lean=0.15,
        levels=1, children=(0,),
        whorls=7, whorl_span=0.52,
        clump_r=5.2, tier=0.82, disc_squash=3.2, leader=2.5,
        clump_noise=0.40, clump_freq=0.45,
        bark=(70, 50, 40), bark_lit=(96, 70, 52),
        leaf=((40, 98, 58), (58, 124, 70), (26, 70, 46)),
        cards=28, card_size=0.55, card_tilt=(0.55, 0.90), target_h=56.0,
    ),
    # Slim and open.  Pale bark, high crown, fewer and smaller clumps so the
    # branches stay visible through it -- the one species where the
    # structure shows.  The crown is a tall oval, not a dome: narrow spread
    # and near-spherical clumps stack upward instead of outward.
    Species(
        name="vox_birch", seed=3,
        trunk_h=19.0, trunk_r=1.25, trunk_taper=0.30, lean=0.9,
        levels=2, children=(2, 2),
        whorls=3, whorl_span=0.32, whorl_taper=0.2,
        first_len=3.6, len_decay=0.70, rad_decay=0.55, spread=0.50,
        clump_r=3.6, clump_r_decay=0.90, clump_levels=2,
        clump_noise=0.50, clump_freq=0.45, canopy_lift=-0.10,
        clump_squash=1.15,
        bark=(176, 172, 160), bark_lit=(206, 204, 192),
        leaf=((104, 166, 72), (132, 190, 88), (72, 128, 56)),
        grain=0.22, cards=38, card_size=1.00, target_h=50.0,
    ),
    # Weeping.  A wide flat cap on a short bole, `droop` bending the limbs
    # so the cap hangs, and then the fronds: vertical cards hung from the
    # cap's rim, which is the curtain that makes it a willow and not a
    # squat oak.  Strongest sway in the set -- the fronds ride at full
    # weight and the limbs are the thinnest here.
    Species(
        name="vox_willow", seed=4,
        trunk_h=13.0, trunk_r=1.8, trunk_taper=0.30, lean=0.7,
        levels=2, children=(3, 2),
        whorls=2, whorl_span=0.20, whorl_taper=0.4,
        first_len=4.6, len_decay=0.60, rad_decay=0.50, spread=1.00,
        droop=0.35,
        clump_r=4.4, clump_r_decay=0.90, clump_levels=2,
        clump_noise=0.44, clump_freq=0.40, canopy_lift=-0.25,
        clump_squash=1.70,
        bark=(78, 66, 48), bark_lit=(104, 90, 66),
        leaf=((92, 148, 70), (118, 176, 86), (58, 108, 52)),
        cards=22, card_size=0.75,
        fronds=28, frond_len=10.0, frond_w=4.5, target_h=50.0,
    ),
]


# --------------------------------------------------------------------------
# skeleton
# --------------------------------------------------------------------------

@dataclass
class Node:
    a: np.ndarray          # start, wood voxels
    b: np.ndarray          # end
    r0: float              # radius at a
    r1: float              # radius at b
    level: int
    path: float            # cumulative length from the root
    leaf_r: float = 0.0    # clump radius at b; 0 = no clump here
    squash: float = 0.0    # per-clump override of Species.clump_squash; 0 = species
    # A tier disc is a node with NO WOOD.  It has to sit on the bole to be
    # centred there, and a node that sits on the bole and writes wood at
    # radius zero writes the flex of a twig into the trunk -- voxelise keeps
    # the highest flex it sees per voxel, so the whole bole would sway at
    # whorl height and the tree would slide off its tile.
    wood: bool = True
    kids: list = field(default_factory=list)


def _unit(v: np.ndarray) -> np.ndarray:
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-9 else np.array([0.0, 1.0, 0.0])


def _perp(v: np.ndarray) -> np.ndarray:
    """Any unit vector perpendicular to v."""
    ref = np.array([0.0, 0.0, 1.0]) if abs(v[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    return _unit(np.cross(v, ref))


def grow(sp: Species) -> list[Node]:
    """Trunk plus recursive forks.  Returns every segment, flat."""
    rng = Rng(sp.seed * 7919 + 13)
    nodes: list[Node] = []

    # ---- the bole, in three segments so it can wander.  A perfectly
    # straight column is the single loudest "this is a generator" tell in a
    # voxel tree, and it costs nothing to bend.
    SEGS = 3
    # The foot sits on a voxel CENTRE, not a corner.  Voxelise tests voxel
    # centres against the radius, so an axis on a corner makes every gauge
    # an even width (2, 4, 6...) and an axis on a centre makes it odd; a
    # 3-wide bole is the one that reads as a trunk at this size, and it only
    # exists on the odd ladder.
    p = np.array([0.5, 0.0, 0.5])
    axis = np.array([0.0, 1.0, 0.0])
    seg_h = sp.trunk_h / SEGS
    for i in range(SEGS):
        t0, t1 = i / SEGS, (i + 1) / SEGS
        drift = np.array([rng.range(-1, 1), 0.0, rng.range(-1, 1)]) * sp.lean
        nxt = p + axis * seg_h + drift
        nodes.append(Node(
            a=p.copy(), b=nxt.copy(),
            r0=sp.trunk_r * (1.0 - sp.trunk_taper * t0),
            r1=sp.trunk_r * (1.0 - sp.trunk_taper * t1),
            level=0, path=sp.trunk_h * t0,
        ))
        axis = _unit(nxt - p)
        p = nxt

    # ---- forks
    def branch(origin, axis_in, length, radius, level, path):
        n_kids = sp.children[min(level, len(sp.children) - 1)]
        base = _perp(axis_in)
        side = _unit(np.cross(axis_in, base))
        phase = rng.range(0.0, math.tau)
        for k in range(n_kids):
            ang = phase + math.tau * k / n_kids + rng.range(-0.35, 0.35)
            out = base * math.cos(ang) + side * math.sin(ang)
            tilt = sp.spread * rng.range(0.75, 1.25)
            d = _unit(axis_in * math.cos(tilt) + out * math.sin(tilt))
            # Droop is applied AFTER the tilt so it bends the branch that
            # already exists rather than steering where it points -- a willow
            # is an oak whose branches gave way, not an oak aimed downward.
            if sp.droop > 0:
                d = _unit(d + np.array([0.0, -sp.droop * rng.range(0.7, 1.3), 0.0]))
            ln = length * rng.range(0.80, 1.20)
            end = origin + d * ln
            r1 = radius * sp.rad_decay
            leaf_r = 0.0
            if level >= sp.levels - sp.clump_levels:
                lr = sp.clump_r * (sp.clump_r_decay ** level)
                if sp.tier > 0:
                    # Conifer: the higher the clump, the smaller it is -- this
                    # ratio IS the cone.  Normalised against the tree's own
                    # height, not twice it: the first cut divided by
                    # trunk_h * 2.4, so hN never got past 0.5 and the taper
                    # only ever spent half its range.  The pine came out a
                    # column and read as "tier is too weak" rather than as a
                    # scale that could not reach.
                    hN = max(0.0, min(1.0, end[1] / (sp.trunk_h * 1.15)))
                    lr *= (1.0 - sp.tier * hN)
                leaf_r = lr * rng.range(0.82, 1.18)
            node = Node(a=origin.copy(), b=end.copy(), r0=radius, r1=r1,
                        level=level + 1, path=path + ln, leaf_r=leaf_r)
            nodes.append(node)
            if level + 1 < sp.levels:
                branch(end, d, ln * sp.len_decay, r1, level + 1, path + ln)

    # Where the bole is, and which way it points, at a fraction of its height.
    trunk_nodes = nodes[:SEGS]

    def on_bole(t: float):
        t = max(0.0, min(1.0, t))
        f = t * SEGS
        i = min(SEGS - 1, int(f))
        local = f - i
        n = trunk_nodes[i]
        return n.a + (n.b - n.a) * local, _unit(n.b - n.a)

    W = max(1, sp.whorls)
    for w in range(W):
        t = 1.0 - (sp.whorl_span * (w / (W - 1)) if W > 1 else 0.0)
        origin, ax = on_bole(t)
        if sp.tier > 0:
            # Conifer: the ring is a disc, not a set of limbs.  hN runs 0 at
            # the lowest ring to 1 at the top one, so `tier` is read directly
            # as "how much smaller the top disc is than the bottom disc".
            hN = (1.0 - t) / sp.whorl_span if sp.whorl_span > 0 else 1.0
            hN = 1.0 - max(0.0, min(1.0, hN))
            R = sp.clump_r * (1.0 - sp.tier * hN) * rng.range(0.92, 1.08)
            nodes.append(Node(a=origin - ax * 0.5, b=origin.copy(), r0=0.0, r1=0.0,
                              level=1, path=sp.trunk_h * t, leaf_r=R,
                              squash=sp.disc_squash, wood=False))
            continue
        # Lower rings are longer.  For a conifer that ratio IS the cone; for a
        # broadleaf it is just a lower limb reaching further out.
        ln = sp.first_len * (1.0 + sp.whorl_taper * (1.0 - t))
        rad = sp.trunk_r * sp.rad_decay * (0.65 + 0.35 * t)
        branch(origin, ax, ln, rad, 0, sp.trunk_h * t)

    if sp.top_r > 0:
        top, ax = on_bole(1.0)
        c = top + ax * sp.top_lift
        nodes.append(Node(a=top.copy(), b=c.copy(), r0=0.0, r1=0.0,
                          level=1, path=sp.trunk_h + sp.top_lift,
                          leaf_r=sp.clump_r * sp.top_r, wood=False))

    if sp.leader > 0:
        # The spike above the last whorl.  Wood first, so the tip has a stem
        # the wind can read the flex off, then a clump stretched along it --
        # squash BELOW one on purpose here, the one place a tall thin clump
        # is the shape wanted.
        top, ax = on_bole(1.0)
        tip = top + ax * sp.leader
        nodes.append(Node(a=top.copy(), b=tip.copy(), r0=sp.trunk_r * 0.5, r1=0.4,
                          level=1, path=sp.trunk_h + sp.leader))
        mid = top + ax * (sp.leader * 0.5)
        nodes.append(Node(a=top.copy(), b=mid.copy(), r0=0.0, r1=0.0,
                          level=2, path=sp.trunk_h + sp.leader,
                          leaf_r=1.3, squash=2.6 / sp.leader, wood=False))
    return nodes


# --------------------------------------------------------------------------
# voxelisation
# --------------------------------------------------------------------------

def voxelise(sp: Species, nodes: list[Node]):
    """Returns (wood: {(x,y,z): flex}, leaf: {(cx,cy,cz): flex}, leaf_mat).

    `flex` is the canopy weight the shader bends by -- see the note on it in
    Voxel3D's vertex stage.  It is NOT height: it follows how THIN the wood
    is, so a low branch tip gives and the trunk beside it at the same height
    does not.

    `leaf_mat` is the leaf field each coarse cell samples, decided PER CLUMP
    and not per cell.  Per cell it was a random pick, and a random pick is
    the worst possible key for a greedy mesher: two neighbouring faces
    agreed on a material one time in three, so the canopy was emitted one
    face per quad -- 207 cells became 251 quads on the oak, which is the
    whole leaf budget spent on not merging.  Per clump, a lobe is one
    colour and its faces merge into plates; the crown reads as a patchwork
    of clumps, which is what it is.
    """
    wood: dict[tuple[int, int, int], float] = {}
    leaf: dict[tuple[int, int, int], float] = {}
    leaf_mat: dict[tuple[int, int, int], int] = {}
    r_root = max(sp.trunk_r, 1e-6)
    max_path = max((n.path for n in nodes), default=1.0)

    for n in nodes:
        if not n.wood:
            continue
        seg = n.b - n.a
        ln = float(np.linalg.norm(seg))
        steps = max(2, int(ln * 2.0))
        for s in range(steps + 1):
            t = s / steps
            c = n.a + seg * t
            r = n.r0 + (n.r1 - n.r0) * t
            pathf = (n.path - ln + ln * t) / max(max_path, 1e-6)
            # Thin wood bends, thick wood does not; the path fraction only
            # tips the balance so a long droopy strand outruns a short stub
            # of the same gauge.
            flex = 0.62 * max(0.0, 1.0 - r / r_root) + 0.38 * pathf
            flex = min(0.999, max(0.0, flex) ** 1.15)
            ri = max(0.5, r)
            lo = np.floor(c - ri).astype(int)
            hi = np.ceil(c + ri).astype(int)
            for x in range(lo[0], hi[0] + 1):
                for y in range(lo[1], hi[1] + 1):
                    for z in range(lo[2], hi[2] + 1):
                        d = math.dist((x + 0.5, y + 0.5, z + 0.5), tuple(c))
                        if d <= ri:
                            key = (x, y, z)
                            if wood.get(key, -1.0) < flex:
                                wood[key] = flex

    # ---- leaf clumps, on the coarse lattice
    clump_i = 0
    for n in nodes:
        if n.leaf_r <= 0.5:
            continue
        clump_i += 1
        centre = n.b + _unit(n.b - n.a) * (n.leaf_r * sp.canopy_lift)
        R = n.leaf_r
        squash = n.squash if n.squash > 0 else sp.clump_squash
        mat = int(_h3(clump_i, 0, 0, sp.seed * 13) * 3) % 3
        # Leaves are always near the top of what a branch can give, but they
        # keep a little of the host so a low clump on a stout branch moves
        # less than a high one on a whip.
        host = wood.get((int(n.b[0]), int(n.b[1]), int(n.b[2])), 0.6)
        lcore = 0.42 + 0.58 * max(host, 0.35)

        cR = R / LEAF_SCALE
        cc = centre / LEAF_SCALE
        lo = np.floor(cc - cR - 1).astype(int)
        hi = np.ceil(cc + cR + 1).astype(int)
        for cx in range(lo[0], hi[0] + 1):
            for cy in range(lo[1], hi[1] + 1):
                for cz in range(lo[2], hi[2] + 1):
                    px, py, pz = cx + 0.5, cy + 0.5, cz + 0.5
                    # A clump flattened vertically reads as foliage; a sphere
                    # reads as fruit.
                    #
                    # THE FACTOR MULTIPLIES THE DISTANCE, SO ABOVE ONE IS
                    # FLATTER.  The first cut used 0.35 meaning to squash and
                    # got the opposite: dividing the y reach by 0.35 stretched
                    # every clump to 2.9x its radius vertically, which is 14
                    # voxels on a 28-voxel tree.  Every species came out as the
                    # same column of leaves with the trunk buried inside it,
                    # and it read as "the crown is too low" rather than as an
                    # inverted constant -- four rounds of moving the whorls up
                    # the bole chasing a symptom.
                    dy = (py - cc[1]) * squash
                    d = math.sqrt((px - cc[0]) ** 2 + dy ** 2 + (pz - cc[2]) ** 2)
                    if d > cR:
                        continue
                    # Ragged surface: noise eats the rim hardest and leaves
                    # the core alone, so the clump keeps its mass while its
                    # outline stops being a circle.
                    rim = d / max(cR, 1e-6)
                    nz = fbm(px, py, pz, sp.clump_freq, sp.seed * 31 + 5)
                    if rim > 0.45 and nz < sp.clump_noise * rim:
                        continue
                    # The rim of a clump gives more than its core: the wind
                    # reaches the outside of a crown first.  Matters most on
                    # the conifer, whose discs sit on a bole with no flex at
                    # all -- without this the whole tier would be as stiff as
                    # the trunk and the pine would stand in the wind like a
                    # lamp post.
                    lflex = min(0.999, lcore + 0.30 * rim)
                    key = (cx, cy, cz)
                    if key not in leaf:
                        leaf_mat[key] = mat
                    if leaf.get(key, -1.0) < lflex:
                        leaf[key] = lflex

    # ---- prune floaters.  A leaf voxel with one neighbour is a speck at
    # this scale, and specks are what make a generated canopy look noisy
    # rather than dense.
    #
    # A cell with wood inside it is never a floater, whatever its neighbour
    # count: it is a leaf on a stem.  Without the exemption the conifer's
    # leader -- a column one cell wide -- lost a cell per pass from the top
    # down and the pine came out with a bare brown stub for a tip.
    def anchored(k):
        for dx in range(LEAF_SCALE):
            for dy in range(LEAF_SCALE):
                for dz in range(LEAF_SCALE):
                    if (k[0] * LEAF_SCALE + dx, k[1] * LEAF_SCALE + dy,
                            k[2] * LEAF_SCALE + dz) in wood:
                        return True
        return False

    for _ in range(2):
        drop = [k for k in leaf
                if sum(1 for d in NEIGHBOURS if (k[0] + d[0], k[1] + d[1], k[2] + d[2]) in leaf) < 2
                and not anchored(k)]
        for k in drop:
            del leaf[k]
            leaf_mat.pop(k, None)

    return wood, leaf, leaf_mat


NEIGHBOURS = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]


# --------------------------------------------------------------------------
# faces, ambient occlusion, greedy meshing
# --------------------------------------------------------------------------

# dir -> (axis, sign).  Matches FACE_SHADE's ids minus one.
DIRS = [(0, 1), (0, -1), (1, 1), (1, -1), (2, 1), (2, -1)]


def face_ao(solid, v, axis, sign) -> float:
    """Classic voxel AO, averaged over the face's four corners.

    Averaged rather than kept per corner because a merged quad has exactly
    four vertices for however many voxels it covers, so per-corner AO would
    forbid merging almost everywhere.  The average still separates "inside
    the crown" from "on the rim", which is the gradient that gives a voxel
    canopy depth; it just does it per face instead of per corner.
    """
    u = (axis + 1) % 3
    w = (axis + 2) % 3
    n = list(v)
    n[axis] += sign
    tot = 0
    for du in (-1, 1):
        for dw in (-1, 1):
            s1 = list(n); s1[u] += du
            s2 = list(n); s2[w] += dw
            cn = list(n); cn[u] += du; cn[w] += dw
            a = solid(tuple(s1))
            b = solid(tuple(s2))
            c = solid(tuple(cn))
            tot += 0 if (a and b) else 3 - (a + b + c)
    return tot / 12.0                       # 0 = buried, 1 = open


def greedy(cells: dict, solid, key_of):
    """Merge coplanar same-key faces into rectangles.

    Yields (dirn, origin(3), du, dv, w, h, key).  `origin` is the quad's
    corner in lattice coordinates, `du`/`dv` the in-plane unit axes.
    """
    out = []
    for dirn, (axis, sign) in enumerate(DIRS):
        u = (axis + 1) % 3
        w = (axis + 2) % 3
        # Bucket the exposed faces by slice so each slice is a small 2D grid.
        slices: dict[int, dict[tuple[int, int], object]] = {}
        for v in cells:
            n = list(v)
            n[axis] += sign
            if solid(tuple(n)):
                continue
            k = key_of(v, axis, sign, dirn)
            if k is None:
                continue
            slices.setdefault(v[axis], {})[(v[u], v[w])] = k

        for s, plane in slices.items():
            done: set = set()
            for (pu, pw) in sorted(plane):
                if (pu, pw) in done:
                    continue
                k = plane[(pu, pw)]
                # grow along u
                ww = 1
                while plane.get((pu + ww, pw)) == k and (pu + ww, pw) not in done:
                    ww += 1
                # grow along w, whole rows only
                hh = 1
                while True:
                    row = [(pu + i, pw + hh) for i in range(ww)]
                    if all(plane.get(c) == k and c not in done for c in row):
                        hh += 1
                    else:
                        break
                for i in range(ww):
                    for j in range(hh):
                        done.add((pu + i, pw + j))
                origin = [0, 0, 0]
                origin[axis] = s + (1 if sign > 0 else 0)
                origin[u] = pu
                origin[w] = pw
                du = [0, 0, 0]; du[u] = 1
                dv = [0, 0, 0]; dv[w] = 1
                out.append((dirn, origin, du, dv, ww, hh, k))
    return out


# --------------------------------------------------------------------------
# atlas
# --------------------------------------------------------------------------

def _fill_cutout(img: Image.Image) -> Image.Image:
    """Leaf atlases sit on a black cutout.  Sampling that as luminance punches
    holes in every voxel that lands on the gap.  Fill the cutout with the
    mean of the opaque blade so the field keeps vein grain, not the void."""
    arr = np.asarray(img.convert("RGB"), dtype=np.float32)
    lum = arr.mean(axis=2)
    mask = lum > 40.0
    if int(mask.sum()) < 64:
        return img
    mean = arr[mask].mean(axis=0)
    arr[~mask] = mean
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")


def _field(w: int, h: int, base, contrast: float, seed: int,
           vertical_grain: float = 0.0, source: Image.Image | None = None):
    """A block of texels the mesh samples ONE PER VOXEL.

    This is the whole texturing idea and it is worth being explicit about,
    because it looks like a mistake next to a normal UV unwrap: a greedy quad
    covering w x h voxels is given a w x h TEXEL window of this field.  With
    nearest filtering that lands exactly one texel on each voxel of the quad,
    so the field is not a surface texture at all -- it is a colour field, and
    what it buys is per-voxel variation on a mesh whose faces are otherwise
    flat-shaded constants.

    At this scale that is the only kind of texture detail that survives.  A
    tree is ~50-80 px on screen and a voxel is ~2-3 of them, so anything
    finer than one colour per voxel is sub-pixel and shows up as shimmer when
    the camera moves.  Grain, bark photos, normal maps: all of it averages
    back to the mean colour before it reaches a pixel.  Per-voxel scatter
    does not, because the voxel IS the pixel.

    `source`, when given, is a real photograph: it is downsampled to this
    field and used for its LUMINANCE ONLY, normalised to zero mean, then
    applied to `base`.  That takes the statistics of real bark -- which way
    the values clump, how long a run of dark stays dark -- without taking its
    colour, which is the half that made the last photo-texture experiment
    read as somebody else's game.
    """
    rng = np.random.RandomState(seed)
    if source is not None:
        # CROP, then resize.  Resizing a 1024px photograph straight down to a
        # 64x32 field box-averages ~500 source pixels into each texel, which
        # is a low-pass filter that deletes exactly the thing being borrowed:
        # the run length of the light and dark patches.  What comes out is
        # flat noise with the photograph's histogram, which is no better than
        # the generator's.  Cropping first keeps the sample at the spatial
        # frequency the field is going to be read at -- one texel per voxel.
        sw, sh = source.size
        cw, ch = min(sw, w * 3), min(sh, h * 3)
        ox = int(rng.randint(0, max(1, sw - cw + 1)))
        oy = int(rng.randint(0, max(1, sh - ch + 1)))
        s = source.convert("L").crop((ox, oy, ox + cw, oy + ch))
        s = s.resize((w, h), Image.BOX)
        lum = np.asarray(s, dtype=np.float32) / 255.0
        lum = lum - lum.mean()
        sd = float(lum.std()) or 1.0
        n = lum / sd * 0.5
    else:
        n = rng.normal(0.0, 0.5, (h, w)).astype(np.float32)
        # one smoothing pass so the scatter clusters instead of dithering
        n = (n + np.roll(n, 1, 0) + np.roll(n, 1, 1)) / 2.2

    if vertical_grain > 0:
        cols = rng.normal(0.0, 1.0, (1, w)).astype(np.float32)
        n = n * (1.0 - vertical_grain) + cols * vertical_grain

    n = np.clip(n, -1.6, 1.6)
    base = np.asarray(base, dtype=np.float32)
    img = base[None, None, :] * (1.0 + n[:, :, None] * contrast)
    return np.clip(img, 0, 255).astype(np.uint8)


def leaf_card(size: int, base, seed: int) -> Image.Image:
    """One leaf-cluster sprite, alpha cut.

    Drawn rather than sampled off anything: what a card has to do at this
    scale is break the crown's outline, so it needs a few large lobes with
    hard alpha edges, not a photograph of foliage.  Soft alpha is worse than
    useless here -- the shader discards below 0.5, so a gradient edge just
    vanishes and the card comes out smaller than it was drawn.
    """
    rng = Rng(seed)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    lobes = []
    for _ in range(7):
        lobes.append((rng.range(0.18, 0.82) * size,
                      rng.range(0.18, 0.82) * size,
                      rng.range(0.14, 0.27) * size))
    for y in range(size):
        for x in range(size):
            hit = False
            for (cx, cy, r) in lobes:
                dx, dy = x + 0.5 - cx, (y + 0.5 - cy) * 1.25
                if dx * dx + dy * dy <= r * r:
                    hit = True
                    break
            if not hit:
                continue
            # cheap per-texel shade so a card is not one flat green stamp
            t = fbm(x * 0.9, y * 0.9, 0.0, 0.35, seed) - 0.5
            c = [min(255, max(0, int(base[i] * (1.0 + t * 0.55)))) for i in range(3)]
            px[x, y] = (c[0], c[1], c[2], 255)
    return img


def frond_card(size: int, base, seed: int) -> Image.Image:
    """A curtain of hanging strands, alpha cut, hung from the sprite's top.

    Four strands and not more: the card is ~5 voxels wide on the tree, so
    a strand is a voxel and a bit, and more of them would fuse into a
    plate.  Each wanders sideways as it falls and carries a leaf every few
    texels, which is what keeps it from reading as a dripping line.
    """
    rng = Rng(seed)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    strands = []
    for i in range(4):
        x0 = (i + 0.5) / 4 * size + rng.range(-1.5, 1.5)
        strands.append((x0, rng.range(0.66, 1.0) * size,
                        rng.range(1.5, 2.6), rng.range(0.0, math.tau),
                        rng.range(0.10, 0.22)))
    for (x0, ln, w, ph, wob) in strands:
        for y in range(size):
            if y >= ln:
                break
            # taper toward the tip, wobble grows with the fall
            ww = w * (1.0 - 0.45 * y / ln)
            xc = x0 + math.sin(y * wob + ph) * (1.0 + 2.5 * y / size)
            leaf_here = (y % 5 == 2)
            for x in range(size):
                dx = abs(x + 0.5 - xc)
                if dx <= ww or (leaf_here and dx <= ww + 1.6):
                    t = fbm(x * 0.9, y * 0.9, 0.0, 0.35, seed) - 0.5
                    c = [min(255, max(0, int(base[i] * (1.0 + t * 0.55)))) for i in range(3)]
                    px[x, y] = (c[0], c[1], c[2], 255)
    return img


def build_atlas(sp: Species, photos: dict) -> Image.Image:
    img = Image.new("RGBA", (TEX_SIZE, TEX_SIZE), (0, 0, 0, 0))
    spec = {
        M_BARK:     (sp.bark,     sp.grain, 0.55, photos.get("bark")),
        M_BARK_LIT: (sp.bark_lit, sp.grain, 0.55, photos.get("bark")),
        M_LEAF_A:   (sp.leaf[0],  sp.mottle, 0.0, photos.get("leaf_fill")),
        M_LEAF_B:   (sp.leaf[1],  sp.mottle, 0.0, photos.get("leaf_fill")),
        M_LEAF_C:   (sp.leaf[2],  sp.mottle, 0.0, photos.get("leaf_fill")),
    }
    for mat, (x, y, w, h) in ATLAS_FIELDS.items():
        base, contrast, grain, src = spec[mat]
        arr = _field(w, h, base, contrast, sp.seed * 101 + mat, grain, src)
        block = Image.fromarray(arr, "RGB").convert("RGBA")
        img.paste(block, (x, y))

    # Photo leaf cards occupy the bottom strip.  Drawn lobes are the
    # fallback; a photographed cluster is what makes a crown read as
    # LEAVES instead of a green blob with a fringe.  The willow keeps
    # slot 3 as a generated frond -- that curtain has no photograph.
    strip_y = int(TEX_SIZE * CARD_UV_CUT)
    slot = TEX_SIZE // CARD_SLOTS
    photo = photos.get("cards")
    n_photo = CARD_SLOTS - (1 if sp.fronds > 0 else 0)
    photo_slots = None
    if photo is not None:
        p = photo.convert("RGBA")
        if p.size != (TEX_SIZE, slot):
            p = p.resize((TEX_SIZE, slot), Image.NEAREST)
        photo_slots = p
    for i in range(CARD_SLOTS):
        base = sp.leaf[i % len(sp.leaf)]
        if sp.fronds > 0 and i == CARD_SLOTS - 1:
            card = frond_card(slot, sp.leaf[1], sp.seed * 977 + i)
            img.paste(card, (i * slot, strip_y))
        elif photo_slots is not None and i < n_photo:
            crop = photo_slots.crop((i * slot, 0, (i + 1) * slot, slot))
            img.paste(crop, (i * slot, strip_y), crop)
        else:
            card = leaf_card(slot, base, sp.seed * 977 + i)
            img.paste(card, (i * slot, strip_y))
    return img


# --------------------------------------------------------------------------
# bake
# --------------------------------------------------------------------------

def bake(sp: Species, photos: dict, report_only: bool = False) -> dict:
    nodes = grow(sp)
    wood, leaf, leaf_mat = voxelise(sp, nodes)
    if not wood or not leaf:
        raise SystemExit(f"{sp.name}: grew nothing (wood={len(wood)} leaf={len(leaf)})")

    def wood_solid(p):
        if p in wood:
            return True
        return (p[0] // LEAF_SCALE, p[1] // LEAF_SCALE, p[2] // LEAF_SCALE) in leaf

    # A coarse cell counts as blocking for leaf faces when it is leaf, or when
    # the wood inside it fills it -- otherwise every clump the trunk passes
    # through emits a wall of faces nobody can see.
    def coarse_solid(c):
        if c in leaf:
            return True
        n = 0
        for dx in range(LEAF_SCALE):
            for dy in range(LEAF_SCALE):
                for dz in range(LEAF_SCALE):
                    if (c[0] * LEAF_SCALE + dx, c[1] * LEAF_SCALE + dy,
                            c[2] * LEAF_SCALE + dz) in wood:
                        n += 1
        return n >= (LEAF_SCALE ** 3) - 1

    # THREE levels, and the number is a merge constraint before it is a
    # shading one.  AO is part of the greedy key, so every extra level is a
    # place two neighbouring faces stop being mergeable: at four levels the
    # first oak came out with 1312 leaf quads against a budget of ~180,
    # because the canopy's occlusion gradient is smooth and four bands chop
    # it into stripes one face wide.  Three still separates rim from
    # interior, which is the whole reason it is baked.
    AO_LEVELS = AO_CANOPY_LEVELS

    # WOOD GETS TWO, THE CANOPY GETS THREE, and the asymmetry is the point.
    # A bole is a convex column: its occlusion gradient is nearly flat, so a
    # third band buys no visible depth and costs the merge -- 139 wood quads
    # at three levels against 88 at two, on the same trunk, for a difference
    # nobody can see under a canopy.  The crown is the opposite: it is all
    # crevices, and the rim/interior split IS the shape.
    AO_WOOD = 2

    def wood_key(v, axis, sign, dirn):
        ao = face_ao(wood_solid, v, axis, sign)
        lvl = int(round(ao * (AO_WOOD - 1))) * (AO_LEVELS - 1) // (AO_WOOD - 1)
        # East and south flanks get the lighter bark field, so the lit side
        # of a bole is a different colour and not merely a brighter one.
        mat = M_BARK_LIT if dirn in (0, 4) else M_BARK
        return (mat, lvl)

    def leaf_key(c, axis, sign, dirn):
        ao = face_ao(coarse_solid, c, axis, sign)
        lvl = int(round(ao * (AO_LEVELS - 1)))
        # Three leaf fields, one per clump (see voxelise), so a crown is not
        # one green and its faces still merge.
        mat = (M_LEAF_A, M_LEAF_B, M_LEAF_C)[leaf_mat.get(c, 0)]
        return (mat, lvl)

    wood_quads = greedy(wood, wood_solid, wood_key)
    leaf_quads = greedy(leaf, coarse_solid, leaf_key)

    # ---- emit
    verts: list[list[float]] = []
    weights: list[float] = []
    wood_idx: list[int] = []
    leaf_idx: list[int] = []

    def emit(origin, du, dv, w, h, mat, shade, flex, scale, into):
        fx, fy, fw, fh = ATLAS_FIELDS[mat]
        # UV window: w x h texels, so one texel lands on each voxel of the
        # quad.  Offset by the quad's own position so two identical quads on
        # the same tree do not wear the same patch of field.
        ow = min(w, fw)
        oh = min(h, fh)
        hx = int(_h3(origin[0], origin[1], origin[2], 7) * (fw - ow + 1))
        hy = int(_h3(origin[2], origin[0], origin[1], 11) * (fh - oh + 1))
        u0 = (fx + hx) / TEX_SIZE
        u1 = (fx + hx + ow) / TEX_SIZE
        v0 = (fy + hy) / TEX_SIZE
        v1 = (fy + hy + oh) / TEX_SIZE

        base = len(verts)
        corners = [
            (0, 0, u0, v0),
            (w, 0, u1, v0),
            (w, h, u1, v1),
            (0, h, u0, v1),
        ]
        for (a, b, uu, vv) in corners:
            p = [(origin[i] + du[i] * a + dv[i] * b) * scale for i in range(3)]
            verts.append([p[0], p[1], p[2], uu, vv, shade])
            weights.append(flex)
        into.extend([base, base + 1, base + 2, base, base + 2, base + 3])

    def ao_factor(lvl):
        return AO_MIN + (1.0 - AO_MIN) * (lvl / (AO_LEVELS - 1))

    # Everything is emitted in VOXEL units and scaled once at the end, so
    # target_h can be a height in world pixels instead of a scale factor
    # nobody can picture.
    VOX = 1.0

    for (dirn, origin, du, dv, w, h, k) in wood_quads:
        mat, lvl = k
        shade = FACE_SHADE[dirn] * ao_factor(lvl)
        # The SIGN is the renderer's "this face points at the sky" flag, which
        # is what lets snow settle.  Only +Y carries it.
        if dirn == 2:
            shade = -shade
        # flex of the voxel behind this face
        vx = origin[0] - (1 if dirn == 0 else 0)
        vy = origin[1] - (1 if dirn == 2 else 0)
        vz = origin[2] - (1 if dirn == 4 else 0)
        flex = wood.get((vx, vy, vz), 0.0)
        emit(origin, du, dv, w, h, mat, shade, flex, VOX, wood_idx)

    # SKY LIGHT DOWN THE CROWN.  Applied per quad AFTER merging, so it is
    # free: it is not in the greedy key, a quad just takes the factor for
    # its own mean height.  What it buys is the one gradient AO cannot: a
    # rim face low on the crown is as "open" as one high on it, so AO lights
    # them the same, and a crown lit the same top to bottom is a slab.  Real
    # canopies are darkest underneath because the foliage above them is in
    # the way, and a 22% falloff is enough to turn the slab into a dome.
    leaf_ys = [c[1] for c in leaf] or [0]
    cy_lo, cy_hi = min(leaf_ys), max(leaf_ys) + 1
    SKY_FLOOR = 0.78

    def sky(y_cells: float) -> float:
        t = (y_cells - cy_lo) / max(1.0, cy_hi - cy_lo)
        return SKY_FLOOR + (1.0 - SKY_FLOOR) * max(0.0, min(1.0, t))

    for (dirn, origin, du, dv, w, h, k) in leaf_quads:
        mat, lvl = k
        mid_y = origin[1] + (du[1] * w + dv[1] * h) * 0.5
        shade = FACE_SHADE[dirn] * ao_factor(lvl) * sky(mid_y)
        if dirn == 2:
            shade = -shade
        cx = origin[0] - (1 if dirn == 0 else 0)
        cy = origin[1] - (1 if dirn == 2 else 0)
        cz = origin[2] - (1 if dirn == 4 else 0)
        flex = leaf.get((cx, cy, cz), 0.9)
        emit([o * LEAF_SCALE for o in origin],
             du, dv, w * LEAF_SCALE, h * LEAF_SCALE,
             mat, shade, flex, VOX, leaf_idx)

    # ---- cards.  Scattered over the crown's OUTER shell, tilted toward
    # horizontal, which is the orientation that reads as a leaf mass seen
    # from a camera looking down at it.
    leaf_cells = list(leaf.keys())
    cx = sum(c[0] for c in leaf_cells) / len(leaf_cells)
    cz = sum(c[2] for c in leaf_cells) / len(leaf_cells)
    shell = sorted(leaf_cells,
                   key=lambda c: -((c[0] - cx) ** 2 + (c[2] - cz) ** 2 + (c[1] * 0.4) ** 2))
    rng = Rng(sp.seed * 4177)
    picked = shell[:max(1, len(shell) // 2)]
    card_idx: list[int] = []
    slot_u = 1.0 / CARD_SLOTS
    v_lo, v_hi = CARD_UV_CUT, 1.0
    for i in range(sp.cards):
        if not picked:
            break
        c = picked[int(rng.next() * len(picked)) % len(picked)]
        centre = np.array([(c[0] + 0.5) * LEAF_SCALE,
                           (c[1] + 0.5) * LEAF_SCALE,
                           (c[2] + 0.5) * LEAF_SCALE]) * VOX
        # Sit the card just outside the voxel it was picked from, so a
        # photographed lobe breaks the cube silhouette instead of lying
        # on it.
        outward = np.array([c[0] + 0.5 - cx, 0.15, c[2] + 0.5 - cz])
        on = float(np.linalg.norm(outward))
        if on > 1e-6:
            centre = centre + (outward / on) * LEAF_SCALE * 0.85 * VOX
        # Card size is NOT a fraction of clump_r: smaller clumps (so the
        # bole shows) must not shrink the leaves off the screen.  A card
        # is the only place a leaf SHAPE can read, so it stays ~3 wood
        # voxels across regardless of how the crown was grown.
        size = max(3.2, sp.clump_r * 0.60) * LEAF_SCALE * 0.5 * sp.card_size * rng.range(0.85, 1.30)
        yaw = rng.range(0.0, math.tau)
        # tilted, not flat: a horizontal card disappears edge-on from a low
        # camera and a vertical one disappears from a high one
        tilt = rng.range(*sp.card_tilt)
        ax = np.array([math.cos(yaw), 0.0, math.sin(yaw)]) * size
        az = np.array([-math.sin(yaw) * tilt, math.sqrt(max(0.0, 1 - tilt * tilt)),
                       math.cos(yaw) * tilt]) * size
        # The frond sprite lives in the last slot; crown cards stay off it.
        n_slots = CARD_SLOTS - 1 if sp.fronds > 0 else CARD_SLOTS
        slot = int(rng.next() * n_slots) % n_slots
        u0, u1 = slot * slot_u, (slot + 1) * slot_u
        base = len(verts)
        for (a, b, uu, vv) in ((-1, -1, u0, v_hi), (1, -1, u1, v_hi),
                               (1, 1, u1, v_lo), (-1, 1, u0, v_lo)):
            p = centre + ax * a + az * b
            # Cards carry no AO and no direction; they are a fringe, and a
            # fringe that self-shades reads as dirt.
            verts.append([float(p[0]), float(p[1]), float(p[2]), uu, vv, 0.88])
            weights.append(0.999)
        card_idx.extend([base, base + 1, base + 2, base, base + 2, base + 3])

    # ---- fronds.  Hung from the cells on the crown's outer rim in its
    # lower half, pushed one voxel outward so they fall past the cap's edge
    # instead of inside it, and yawed to face outward with some jitter: a
    # card tangent to the rim is seen face-on from outside the tree, and
    # the camera is always outside the tree.
    if sp.fronds > 0 and leaf_cells:
        y_lo = min(c[1] for c in leaf_cells)
        y_hi = max(c[1] for c in leaf_cells)
        y_cut = y_lo + (y_hi - y_lo) * 0.55
        lower = [c for c in leaf_cells if c[1] <= y_cut]
        rim = sorted(lower, key=lambda c: -((c[0] + 0.5 - cx) ** 2 + (c[2] + 0.5 - cz) ** 2))
        rim = rim[:max(1, len(rim) // 2)]
        frng = Rng(sp.seed * 6011 + 3)
        u0, u1 = (CARD_SLOTS - 1) * slot_u, 1.0
        half_w = sp.frond_w * 0.5
        for i in range(sp.fronds):
            c = rim[int(frng.next() * len(rim)) % len(rim)]
            ox, oz = c[0] + 0.5 - cx, c[2] + 0.5 - cz
            ang = math.atan2(oz, ox)
            out = np.array([math.cos(ang), 0.0, math.sin(ang)])
            top = np.array([(c[0] + 0.5) * LEAF_SCALE,
                            (c[1] + 0.35) * LEAF_SCALE,
                            (c[2] + 0.5) * LEAF_SCALE]) + out * 1.2
            ln = sp.frond_len * frng.range(0.7, 1.15)
            yaw = ang + math.pi * 0.5 + frng.range(-0.6, 0.6)
            axw = np.array([math.cos(yaw), 0.0, math.sin(yaw)]) * half_w
            base = len(verts)
            # v runs top-to-bottom down the sprite, so the strands hang.
            for (a, hang, uu, vv) in ((-1, 0.0, u0, v_lo), (1, 0.0, u1, v_lo),
                                      (1, 1.0, u1, v_hi), (-1, 1.0, u0, v_hi)):
                p = top + axw * a - np.array([0.0, ln * hang, 0.0])
                verts.append([float(p[0]), float(p[1]), float(p[2]), uu, vv, 0.80])
                # The top of a frond is pinned to the cap it hangs from; the
                # tip swings.  Same weight gradient as a branch, per card.
                weights.append(0.999 if hang > 0.5 else min(0.999, leaf.get(c, 0.8)))
            card_idx.extend([base, base + 1, base + 2, base, base + 2, base + 3])

    # ---- header numbers, measured off what was actually emitted
    arr = np.array([[v[0], v[1], v[2]] for v in verts], dtype=np.float32)

    # CENTRED ON THE BOLE, not on the bounding box.  A crown that leans --
    # and every one of these does, because the trunk wanders and the forks
    # are seeded at a random phase -- would drag the bounding-box centre off
    # the trunk, and Trees3D stamps the origin on the site's cell.  So a
    # box-centred bake plants the tree beside its own tile: the shadow, the
    # canopy-cover field and the collision the hull used to provide all
    # agree with each other and disagree with the picture.
    foot = [(k, f) for k, f in wood.items() if k[1] <= 2]
    if foot:
        cx = sum(k[0] for k, _ in foot) / len(foot) + 0.5
        cz = sum(k[2] for k, _ in foot) / len(foot) + 0.5
    else:
        cx = (arr[:, 0].min() + arr[:, 0].max()) * 0.5
        cz = (arr[:, 2].min() + arr[:, 2].max()) * 0.5
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

    # THE BASE NUMBER IS ABOUT THE BOLE, so it is measured over wood only.
    #
    # Measured over every vertex it is not a check, it is a species test: a
    # willow's fronds hang into the bottom eighth of the tree and they are
    # SUPPOSED to swing there, so an all-vertex average read 0.770 and
    # refused a correct bake.  What must be pinned is the trunk -- if that
    # moves, the whole tree slides off the tile it stands on.
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
        "woodVoxels": len(wood), "leafCells": len(leaf),
    }

    print(f"{sp.name}: verts={nv} tris={ni // 3} "
          f"(wood {len(wood_quads)}q + leaf {len(leaf_quads)}q + {len(card_idx) // 6} cards) "
          f"h={height:.1f} r={radius:.1f} canopyR={canopy_r:.1f} "
          f"cells={len(wood)}w/{len(leaf)}l "
          f"flex base={base_w:.3f} crown={crown_w:.3f}")

    if report_only:
        return stats

    # ---- checks that would otherwise fail silently in the game
    if nv > 65535:
        raise SystemExit(f"{sp.name}: {nv} verts will not fit a uint16 index buffer")
    if base_w > 0.12:
        raise SystemExit(
            f"{sp.name}: canopy weight at the base is {base_w:.3f} -- this tree "
            "would sway from its roots.")
    if crown_w < 0.55:
        raise SystemExit(
            f"{sp.name}: canopy weight in the crown is only {crown_w:.3f} -- "
            "the wind would barely reach it.")
    solid_v = max(v[4] for v in verts[:n_wood_v + len(leaf_quads) * 4])
    if solid_v > CARD_UV_CUT:
        raise SystemExit(
            f"{sp.name}: a solid vertex samples v={solid_v:.4f}, above the card "
            f"cut {CARD_UV_CUT} -- it would be classified as a card and dropped "
            "from the shadow mesh.")
    if card_idx:
        card_v = min(verts[i][4] for i in card_idx)
        if card_v < CARD_UV_CUT:
            raise SystemExit(f"{sp.name}: a card vertex samples v={card_v:.4f}, "
                             f"below the cut {CARD_UV_CUT}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tex = build_atlas(sp, photos)
    tex_path = OUT_DIR / f"{sp.name}.png"
    tex.save(tex_path)

    bin_path = OUT_DIR / f"{sp.name}.mesh.bin"
    with open(bin_path, "wb") as f:
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
        "format": "terrarium-tree-v2",
        "kind": sp.name,
        "bin": bin_path.name,
        "texture": tex_path.name,
        "indices": ni,
        "trunkTris": n_trunk // 3,
        "canopyTris": (ni - n_trunk) // 3,
        "source": "tools/bake_voxel_tree.py (procedural voxel)",
        "voxelScale": scale,
        "targetHeight": sp.target_h,
        "leafScale": LEAF_SCALE,
    })
    (OUT_DIR / f"{sp.name}.meta.json").write_text(json.dumps(meta, indent=2))
    return stats


def photos_for(sp: Species, args) -> dict:
    """Per-species CC0 photos, with --bark/--leaf as a global override."""
    spec = SPECIES_PHOTOS.get(sp.name, {})
    out = {}
    bark = Path(args.bark) if args.bark else spec.get("bark")
    leaf = Path(args.leaf) if args.leaf else spec.get("leaf")
    cards = spec.get("cards")
    for key, path in (("bark", bark), ("leaf", leaf), ("cards", cards)):
        if not path:
            continue
        p = Path(path)
        if p.exists():
            im = Image.open(p)
            out[key] = im
            if key == "leaf":
                out["leaf_fill"] = _fill_cutout(im)
            print(f"{sp.name}: {key} from {p.name}")
        else:
            print(f"WARN: {sp.name} {key} {p} not found -- procedural fallback")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", action="append", default=None)
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--bark", default=None, help="photo for bark luminance (all species)")
    ap.add_argument("--leaf", default=None, help="photo for foliage luminance (all species)")
    args = ap.parse_args()

    for sp in SPECIES:
        if args.only and sp.name not in args.only:
            continue
        bake(sp, photos_for(sp, args), report_only=args.report)


if __name__ == "__main__":
    main()
