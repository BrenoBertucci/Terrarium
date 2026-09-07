#!/usr/bin/env python3
"""Cut real leaves out of CC0 photo atlases and compose the card sprites.

The tree baker (tools/bake_voxel_tree.py) scatters alpha CARDS over a
crown's outer shell.  Each card samples one 32x32 slot of the bottom strip
of the species atlas, and what that slot holds is the whole difference
between "a green blob with a fringe" and "a tree with leaves": at ~70
screen px a card is big enough for a leaf SHAPE to read, and a drawn lobe
does not have one.

Sources (all CC0, downloaded by hand into tools/_tree_src/, gitignored):

    ambientCG LeafSet024   broad oval leaves        -> vox_birch
    ambientCG LeafSet010   lobed (maple-type)       -> vox_oak
    ambientCG LeafSet022   narrow, long             -> vox_willow
    ambientCG LeafSet019   conifer sprays           -> vox_pine

Each atlas ships a Color and an Opacity map.  Leaves are separated by
connected components of the opacity mask, then a slot is composed from
several of them, rotated and scaled, so a card reads as a CLUSTER rather
than one leaf on a stick.

COLOUR IS NOT KEPT.  The photograph supplies the silhouette and the
luminance structure (veins, the lighter blade, the darker overlap); the hue
comes from the species' own leaf palette, because Gen 1 foliage is a
yellow-green ramp with no blue in it and a photographed leaf is bluer and
duller than anything on that route.  The earlier texture experiment failed
on exactly that -- assets that kept their own colour read as imported.

ALPHA IS HARD.  The scene shader discards below 0.5, so a soft edge does
not fade, it moves the cut inward.  Every sprite here is thresholded once,
at composition, and the threshold is what the game will see.

Outputs, per species, in tools/_tree_src/:

    leaf_cards_<species>.png        128x32 RGBA, four 32x32 slots -- drop-in
                                    for the bottom strip of the bake atlas
    leaf_cards_<species>_x2.png     256x64, same slots at 64x64
    leaf_cards_sheet.png            preview of everything over dark grey

Usage:  python tools/make_leaf_cards.py [--slot 32] [--seed 1]
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "tools" / "_tree_src"

# Species palette, mirrored from bake_voxel_tree.SPECIES (leaf A, B, C).
# Kept as a copy on purpose: this tool runs BEFORE the bake and must not
# import the baker just to read four tuples.
SPECIES = {
    "vox_oak":    dict(atlas="LeafSet010", leaf=((62, 126, 54), (88, 158, 66), (40, 92, 42)),
                       per_slot=(5, 7), scale=(0.42, 0.62)),
    "vox_birch":  dict(atlas="LeafSet024", leaf=((104, 166, 72), (132, 190, 88), (72, 128, 56)),
                       per_slot=(6, 9), scale=(0.34, 0.50)),
    "vox_willow": dict(atlas="LeafSet022", leaf=((92, 148, 70), (118, 176, 86), (58, 108, 52)),
                       per_slot=(7, 10), scale=(0.45, 0.70)),
    "vox_pine":   dict(atlas="LeafSet019", leaf=((40, 98, 58), (58, 124, 70), (26, 70, 46)),
                       per_slot=(4, 6), scale=(0.60, 0.95)),
}
SLOTS = 4

# The Game Boy's greens have no blue; the ramp the baker snaps to keeps B at
# zero or sixteen.  A photographed leaf carries 30-60 of blue.  Anything the
# tint leaves above this is pulled down so the card sits in the same ramp as
# the voxel faces around it.
MAX_BLUE = 60


class Rng:
    """Tiny LCG so a re-run composes byte-identical sprites."""

    def __init__(self, seed: int):
        self.s = (seed * 2654435761 + 12345) & 0xFFFFFFFF

    def next(self) -> float:
        self.s = (self.s * 1103515245 + 12345) & 0x7FFFFFFF
        return (self.s >> 8) / float(1 << 23)

    def range(self, a: float, b: float) -> float:
        return a + (b - a) * self.next()

    def pick(self, seq):
        return seq[int(self.next() * len(seq)) % len(seq)]


def components(mask: np.ndarray, min_area: int = 400):
    """Connected components of a boolean mask, 4-connected, no scipy.

    Returns a list of (y0, y1, x0, x1, submask) sorted by area, largest
    first.  Iterative flood fill on a 1K mask is fast enough (a few hundred
    ms) and keeps this tool dependency-free beyond numpy/PIL.
    """
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    out = []
    ys, xs = np.nonzero(mask)
    for sy, sx in zip(ys, xs):
        if seen[sy, sx]:
            continue
        stack = [(sy, sx)]
        seen[sy, sx] = True
        pts = []
        while stack:
            y, x = stack.pop()
            pts.append((y, x))
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        if len(pts) < min_area:
            continue
        py = np.array([p[0] for p in pts])
        px = np.array([p[1] for p in pts])
        y0, y1, x0, x1 = py.min(), py.max() + 1, px.min(), px.max() + 1
        sub = np.zeros((y1 - y0, x1 - x0), dtype=bool)
        sub[py - y0, px - x0] = True
        out.append((y0, y1, x0, x1, sub))
    out.sort(key=lambda c: -int(c[4].sum()))
    return out


def load_leaves(atlas: str):
    color = np.asarray(Image.open(SRC / atlas / f"{atlas}_1K-JPG_Color.jpg").convert("RGB"),
                       dtype=np.float32)
    opac = np.asarray(Image.open(SRC / atlas / f"{atlas}_1K-JPG_Opacity.jpg").convert("L"))
    mask = opac > 127
    leaves = []
    for (y0, y1, x0, x1, sub) in components(mask):
        rgb = color[y0:y1, x0:x1]
        # luminance of the blade, normalised over the leaf's own pixels so a
        # pale leaf and a dark one contribute the same STRUCTURE
        lum = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
        inside = lum[sub]
        mean = float(inside.mean()) or 1.0
        rel = np.where(sub, lum / mean, 1.0)
        img = Image.fromarray((np.clip(rel, 0.4, 1.8) * 100.0).astype(np.uint8), "L")
        alpha = Image.fromarray((sub * 255).astype(np.uint8), "L")
        leaves.append((img, alpha))
    return leaves


def tint(rel: np.ndarray, base) -> np.ndarray:
    """Species colour, modulated by the photograph's relative luminance.

    Contrast is pulled in (0.75 power) because a card is a fringe: a fully
    contrasty leaf next to flat-shaded voxel faces reads as a sticker, a
    slightly flattened one reads as the same material seen closer.
    """
    b = np.asarray(base, dtype=np.float32)
    f = np.power(np.clip(rel, 0.4, 1.8), 0.75)[..., None]
    rgb = b[None, None, :] * f
    rgb[..., 2] = np.minimum(rgb[..., 2], MAX_BLUE)
    return np.clip(rgb, 0, 255)


def compose_slot(leaves, spec, size: int, rng: Rng) -> Image.Image:
    """One cluster: several leaves fanned around the slot centre.

    Leaves are placed from the back forward so the front ones overlap the
    back ones and the darker `leaf C` sits behind the lighter `leaf B` --
    the depth cue a clump has and a single leaf does not.
    """
    n = int(rng.range(*spec["per_slot"]) + 0.5)
    canvas = np.zeros((size, size, 3), dtype=np.float32)
    alpha = np.zeros((size, size), dtype=np.float32)
    palette = spec["leaf"]
    for i in range(n):
        img, a = rng.pick(leaves)
        # back leaves darker, front leaves lighter, middle the base tone
        t = i / max(1, n - 1)
        base = palette[2] if t < 0.34 else (palette[0] if t < 0.67 else palette[1])
        lw, lh = img.size
        longest = max(lw, lh)
        target = size * rng.range(*spec["scale"])
        s = target / longest
        w, h = max(2, int(lw * s)), max(2, int(lh * s))
        img_s = img.resize((w, h), Image.BILINEAR)
        a_s = a.resize((w, h), Image.BILINEAR)
        ang = rng.range(0.0, 360.0)
        # expand=True so nothing is clipped off the rotated leaf
        img_r = img_s.rotate(ang, resample=Image.BILINEAR, expand=True)
        a_r = a_s.rotate(ang, resample=Image.BILINEAR, expand=True)
        rw, rh = img_r.size
        # around the centre, never fully outside: the shell of a crown, not
        # a leaf flying off it
        cx = size * 0.5 + (rng.next() - 0.5) * size * 0.45
        cy = size * 0.5 + (rng.next() - 0.5) * size * 0.45
        x0, y0 = int(cx - rw * 0.5), int(cy - rh * 0.5)
        rel = np.asarray(img_r, dtype=np.float32) / 100.0
        am = np.asarray(a_r, dtype=np.float32) / 255.0
        rgb = tint(rel, base)
        for yy in range(rh):
            ty = y0 + yy
            if ty < 0 or ty >= size:
                continue
            for xx in range(rw):
                tx = x0 + xx
                if tx < 0 or tx >= size:
                    continue
                av = am[yy, xx]
                if av < 0.5:
                    continue
                # hard replace: a leaf in front hides the one behind
                canvas[ty, tx] = rgb[yy, xx]
                alpha[ty, tx] = 1.0
    out = np.zeros((size, size, 4), dtype=np.uint8)
    out[..., :3] = canvas.astype(np.uint8)
    out[..., 3] = (alpha >= 0.5).astype(np.uint8) * 255
    return Image.fromarray(out, "RGBA")


def coverage(img: Image.Image) -> float:
    a = np.asarray(img)[..., 3]
    return float((a > 127).mean())


STRAND_ASPECT = 4.5


def compose_strand(leaves, spec, size: int, rng: Rng) -> Image.Image:
    """A hanging strand for the willow: leaves along a vertical line.

    The bake maps this square slot onto a quad ~4.5x taller than it is
    wide, so the strand is composed at that aspect and squashed back into
    the square -- the game stretches it out again. Composed on a tall
    canvas first so the leaves keep their proportions after the round trip.
    """
    tall = int(size * STRAND_ASPECT)
    canvas = np.zeros((tall, size, 3), dtype=np.float32)
    alpha = np.zeros((tall, size), dtype=np.float32)
    palette = spec["leaf"]
    n = int(rng.range(9, 13))
    drift = rng.range(-0.18, 0.18)
    for i in range(n):
        img, a = rng.pick(leaves)
        t = i / max(1, n - 1)
        base = palette[0] if i % 3 == 0 else (palette[1] if i % 3 == 1 else palette[2])
        lw, lh = img.size
        s = (size * 0.62) / max(lw, lh)
        w, h = max(2, int(lw * s)), max(2, int(lh * s))
        img_s = img.resize((w, h), Image.BILINEAR)
        a_s = a.resize((w, h), Image.BILINEAR)
        # leaves hang: long axis near vertical, alternating sides
        ang = 90.0 + rng.range(-28.0, 28.0) + (180.0 if i % 2 else 0.0)
        img_r = img_s.rotate(ang, resample=Image.BILINEAR, expand=True)
        a_r = a_s.rotate(ang, resample=Image.BILINEAR, expand=True)
        rw, rh = img_r.size
        cx = size * (0.5 + drift * (t - 0.5) * 2.0) + (rng.next() - 0.5) * size * 0.25
        cy = tall * (0.06 + 0.88 * t)
        x0, y0 = int(cx - rw * 0.5), int(cy - rh * 0.5)
        rel = np.asarray(img_r, dtype=np.float32) / 100.0
        am = np.asarray(a_r, dtype=np.float32) / 255.0
        rgb = tint(rel, base)
        for yy in range(rh):
            ty = y0 + yy
            if ty < 0 or ty >= tall:
                continue
            for xx in range(rw):
                tx = x0 + xx
                if tx < 0 or tx >= size or am[yy, xx] < 0.5:
                    continue
                canvas[ty, tx] = rgb[yy, xx]
                alpha[ty, tx] = 1.0
    out = np.zeros((tall, size, 4), dtype=np.uint8)
    out[..., :3] = canvas.astype(np.uint8)
    out[..., 3] = (alpha >= 0.5).astype(np.uint8) * 255
    sq = Image.fromarray(out, "RGBA").resize((size, size), Image.BOX)
    arr = np.asarray(sq).copy()
    arr[..., 3] = np.where(arr[..., 3] > 100, 255, 0)
    return Image.fromarray(arr, "RGBA")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--slot", type=int, default=32)
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()

    sheet_rows = []
    for name, spec in SPECIES.items():
        leaves = load_leaves(spec["atlas"])
        print(f"{name}: {len(leaves)} leaves cut from {spec['atlas']}")
        for size, suffix in ((args.slot, ""), (args.slot * 2, "_x2")):
            strip = Image.new("RGBA", (size * SLOTS, size), (0, 0, 0, 0))
            covs = []
            for s in range(SLOTS):
                rng = Rng(args.seed * 1000 + s * 17 + sum(ord(ch) for ch in name) % 97)
                # a slot must hold enough leaf to be worth a card: retry a
                # thin composition rather than ship a card that is mostly
                # discard
                if name == "vox_willow" and s == SLOTS - 1:
                    # the last willow slot is the hanging strand the bake
                    # drapes off the crown's rim
                    slot = compose_strand(leaves, spec, size, rng)
                    c = coverage(slot)
                else:
                    for attempt in range(6):
                        slot = compose_slot(leaves, spec, size, rng)
                        c = coverage(slot)
                        if c >= 0.30:
                            break
                covs.append(c)
                strip.paste(slot, (s * size, 0))
            out = SRC / f"leaf_cards_{name}{suffix}.png"
            strip.save(out)
            print(f"  {out.name}: coverage " + " ".join(f"{c:.2f}" for c in covs))
            if suffix == "_x2":
                sheet_rows.append(strip)

    # preview sheet: the x2 strips stacked over dark grey, 3x
    if sheet_rows:
        w = max(r.width for r in sheet_rows)
        h = sum(r.height for r in sheet_rows) + 8 * (len(sheet_rows) - 1)
        sheet = Image.new("RGBA", (w, h), (40, 40, 40, 255))
        y = 0
        for r in sheet_rows:
            sheet.alpha_composite(r, (0, y))
            y += r.height + 8
        sheet = sheet.resize((w * 3, h * 3), Image.NEAREST)
        sheet.convert("RGB").save(SRC / "leaf_cards_sheet.png")
        print("preview:", SRC / "leaf_cards_sheet.png")


if __name__ == "__main__":
    main()
