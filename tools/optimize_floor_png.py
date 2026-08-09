"""Shrink a tiling floor texture to something a diorama can afford.

The art arrives as a 1024x1024 RGB render (2.1 MB). Nothing in this mod reads
it at that density: the surface is sampled in world XZ over a cycle of
FloorArt.ART_SCALE world pixels, and one world pixel is one or two screen
pixels at the rungs anybody plays at. 1024 texels over a 64-pixel cycle is
sixteen texels per world pixel -- fifteen of which the sampler averages away.

So: downsample, then quantise. Quantising is what actually pays here. The
render is a photographic surface with noise in it, and PNG is a lossless
codec -- it cannot compress noise. Cutting to a palette removes the noise as
information rather than trying to squeeze it, which is also the right look
for a four-colour diorama.

  py tools/optimize_floor_png.py <in.png> <out.png> [--size 256] [--colors 64]

Checks the seam before and after: this texture is sampled with a REPEAT wrap,
so its left edge lands against its right edge on screen. A resize that does
not preserve that is a visible grid line every cycle across the whole floor.
"""
import argparse
import os
import sys

from PIL import Image


def seam_error(im):
    """Mean absolute difference across the wrap, as 0..255 per channel.

    Column 0 sits against column w-1 on screen, and row 0 against row h-1.
    A tiling texture should score near zero on both.
    """
    px = im.convert("RGB")
    w, h = px.size
    left = px.crop((0, 0, 1, h)).tobytes()
    right = px.crop((w - 1, 0, w, h)).tobytes()
    top = px.crop((0, 0, w, 1)).tobytes()
    bot = px.crop((0, h - 1, w, h)).tobytes()
    dx = sum(abs(a - b) for a, b in zip(left, right)) / max(1, len(left))
    dy = sum(abs(a - b) for a, b in zip(top, bot)) / max(1, len(top))
    return dx, dy


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--size", type=int, default=256)
    ap.add_argument("--colors", type=int, default=64)
    args = ap.parse_args()

    im = Image.open(args.src).convert("RGB")
    before = os.path.getsize(args.src)
    sx, sy = seam_error(im)
    print(f"in   {im.size[0]}x{im.size[1]} {before/1024:.0f} KB  "
          f"seam dx={sx:.2f} dy={sy:.2f}")

    # BOX, not LANCZOS: a windowed filter overshoots at the hard edge between
    # a tile and its grout line and rings a bright halo along every seam in
    # the art. A box average is what a mipmap would have done anyway.
    small = im.resize((args.size, args.size), Image.BOX)

    # MEDIANCUT + no dither. Floyd-Steinberg would scatter the palette error
    # as noise, which is the thing being removed, and the scatter does not
    # survive the sampler's own filtering -- it just costs bytes.
    q = small.quantize(colors=args.colors, method=Image.MEDIANCUT, dither=Image.NONE)

    q.save(args.dst, format="PNG", optimize=True, compress_level=9)
    after = os.path.getsize(args.dst)
    qx, qy = seam_error(q)
    print(f"out  {args.size}x{args.size} {after/1024:.0f} KB  "
          f"seam dx={qx:.2f} dy={qy:.2f}  ({before/after:.0f}x smaller)")

    if qx > sx + 2 or qy > sy + 2:
        print("WARN: the resize made the wrap seam worse", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
