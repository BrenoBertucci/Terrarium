#!/usr/bin/env python3
"""Lay a burst of probe frames out so motion can be READ.

For each tag (calm, gale) in probe_out_treefable/motion/:
  <tag>_strip.png   six frames of a crop, side by side
  <tag>.gif         the whole burst, half size, looping
  prints the per-frame mean absolute difference inside the crop -- the
  curve that separates a machine (flat) from wind (ragged, bursty)

Usage: python tools/motion_sheet.py [--crop x0 y0 x1 y1]
"""
from __future__ import annotations

import argparse
import glob
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DIR = ROOT / "probe_out_treefable" / "motion"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--crop", type=int, nargs=4, default=(120, 150, 900, 560))
    args = ap.parse_args()
    x0, y0, x1, y1 = args.crop
    for tag in ("calm", "gale"):
        # only the numbered burst frames: the strip/heat/close sheets this
        # tool writes also match the glob and would poison the tail of the curve
        files = sorted(f for f in glob.glob(str(DIR / f"{tag}_*.png"))
                       if Path(f).stem[len(tag) + 1:].isdigit())
        if not files:
            print(tag, "no frames")
            continue
        frames = [Image.open(f).convert("RGB") for f in files]
        crops = [f.crop((x0, y0, x1, y1)) for f in frames]
        arrs = [np.asarray(c, dtype=np.float32) for c in crops]
        diffs = [float(np.abs(arrs[i] - arrs[i - 1]).mean()) for i in range(1, len(arrs))]
        print(f"{tag}: {len(frames)} frames, crop {x1 - x0}x{y1 - y0}")
        print("  diff/frame: " + " ".join(f"{d:.2f}" for d in diffs))
        d = np.array(diffs)
        print(f"  mean {d.mean():.2f}  sd {d.std():.2f}  cv {d.std() / max(d.mean(), 1e-6):.2f}")
        pick = [crops[int(i)] for i in np.linspace(0, len(crops) - 1, 6)]
        w, h = pick[0].size
        strip = Image.new("RGB", (w * 6 + 5 * 4, h), (30, 30, 30))
        for i, c in enumerate(pick):
            strip.paste(c, (i * (w + 4), 0))
        strip.save(DIR / f"{tag}_strip.png")
        small = [f.resize((f.width // 2, f.height // 2), Image.BILINEAR) for f in frames]
        small[0].save(DIR / f"{tag}.gif", save_all=True, append_images=small[1:],
                      duration=33, loop=0)
        # a motion heat map: where did the picture change over the burst?
        heat = np.zeros_like(arrs[0][..., 0])
        for i in range(1, len(arrs)):
            heat += np.abs(arrs[i] - arrs[i - 1]).mean(axis=2)
        heat = np.clip(heat / max(float(heat.max()), 1e-6) * 255, 0, 255).astype(np.uint8)
        Image.fromarray(heat, "L").save(DIR / f"{tag}_heat.png")
    print("wrote strips, gifs and heat maps to", DIR)


if __name__ == "__main__":
    main()
