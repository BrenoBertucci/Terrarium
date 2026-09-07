#!/usr/bin/env python3
"""Render a baked TTR2 the way the game will, offline.

Not a substitute for the probe -- the probe is what proves the forest reaches
the screen -- but it is a hundred times faster at catching the bakes that are
wrong before they ever get there: UVs off the field, a canopy sampling the
card strip, a trunk decimated to nothing, shade with the wrong sign.  All of
those look like "the tree is a bit odd" in a 320px screenshot of a forest and
like an obvious defect in a 256px render of one tree.

The camera matches the game's: a 3/4 view looking down, the sun in the
southeast, VertexShade multiplied into the texel exactly as Voxel3D does.
"""

from __future__ import annotations

import math
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

DIR = Path(__file__).resolve().parent.parent / "assets" / "ground" / "tree"
SIZE = 320
PITCH = math.radians(52.0)
YAW = math.radians(28.0)


def load(name: str):
    blob = (DIR / f"{name}.mesh.bin").read_bytes()
    assert blob[:4] == b"TTR2", name
    nv, ni, ntrunk = struct.unpack_from("<III", blob, 4)
    height, radius, cy, cr = struct.unpack_from("<ffff", blob, 16)
    v = np.frombuffer(blob, dtype=np.float32, count=nv * 7, offset=32).reshape(nv, 7)
    idx = np.frombuffer(blob, dtype=np.uint16, count=ni, offset=32 + nv * 28)
    return v, idx.astype(np.int32), dict(height=height, radius=radius,
                                         canopyY=cy, canopyR=cr, trunk=ntrunk)


def render(name: str, out: Path, sway: float = 0.0, span: float | None = None):
    v, idx, meta = load(name)
    tex = np.asarray(Image.open(DIR / f"{name}.png").convert("RGBA"), dtype=np.float32)
    th, tw = tex.shape[:2]

    pos = v[:, 0:3].copy()

    # The bend the shader applies, reproduced here so a preview can answer
    # "does the canopy lean and the trunk stay put" without the game.
    if sway:
        bend = v[:, 6]
        pos[:, 0] += sway * bend
        pos[:, 2] += sway * bend * 0.3

    cy, sy = math.cos(YAW), math.sin(YAW)
    cp, sp = math.cos(PITCH), math.sin(PITCH)
    x = pos[:, 0] * cy - pos[:, 2] * sy
    z = pos[:, 0] * sy + pos[:, 2] * cy
    sx = x
    sy_ = -pos[:, 1] * cp + z * sp
    depth = pos[:, 1] * sp + z * cp

    # ONE SCALE FOR EVERY TREE.  Fitting each to its own bounds makes a
    # 28 px bake and a 46 px one the same size on the sheet, which is the
    # one comparison the sheet exists to make.
    if span is None:
        span = max(meta["height"], meta["radius"] * 2) * 1.15
    scale = SIZE / span
    px = sx * scale + SIZE * 0.5
    py = sy_ * scale + SIZE * 0.80

    img = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    img[:, :] = (96, 132, 92)                    # the game's grass, roughly
    zbuf = np.full((SIZE, SIZE), 1e9, dtype=np.float32)

    for t in range(0, len(idx) - 2, 3):
        a, b, c = idx[t], idx[t + 1], idx[t + 2]
        xs = [px[a], px[b], px[c]]
        ys = [py[a], py[b], py[c]]
        x0, x1 = int(max(0, min(xs))), int(min(SIZE - 1, max(xs)) + 1)
        y0, y1 = int(max(0, min(ys))), int(min(SIZE - 1, max(ys)) + 1)
        if x1 <= x0 or y1 <= y0:
            continue
        ax, ay = xs[0], ys[0]
        bx, by = xs[1], ys[1]
        cx, cx_ = xs[2], ys[2]
        den = (by - cx_) * (ax - cx) + (cx - bx) * (ay - cx_)
        if abs(den) < 1e-9:
            continue
        for yy in range(y0, y1):
            for xx in range(x0, x1):
                w0 = ((by - cx_) * (xx + 0.5 - cx) + (cx - bx) * (yy + 0.5 - cx_)) / den
                w1 = ((cx_ - ay) * (xx + 0.5 - cx) + (ax - cx) * (yy + 0.5 - cx_)) / den
                w2 = 1 - w0 - w1
                if w0 < -1e-4 or w1 < -1e-4 or w2 < -1e-4:
                    continue
                d = w0 * depth[a] + w1 * depth[b] + w2 * depth[c]
                if d >= zbuf[yy, xx]:
                    continue
                u = w0 * v[a, 3] + w1 * v[b, 3] + w2 * v[c, 3]
                vv = w0 * v[a, 4] + w1 * v[b, 4] + w2 * v[c, 4]
                tu = min(tw - 1, max(0, int(u * tw)))
                tv = min(th - 1, max(0, int(vv * th)))
                texel = tex[tv, tu]
                if texel[3] < 128:               # the shader's alpha discard
                    continue
                sh = abs(w0 * v[a, 5] + w1 * v[b, 5] + w2 * v[c, 5])
                zbuf[yy, xx] = d
                img[yy, xx] = np.clip(texel[:3] * sh, 0, 255)

    Image.fromarray(img.astype(np.uint8)).resize((SIZE, SIZE), Image.NEAREST).save(out)
    print(f"{name}: {out.name}  tris={len(idx)//3} verts={len(v)} "
          f"h={meta['height']:.1f} canopyR={meta['canopyR']:.1f}")


def main():
    names = sys.argv[1:] or [p.stem.replace(".mesh", "")
                             for p in sorted(DIR.glob("*.mesh.bin"))]
    outdir = DIR.parent.parent.parent / "probe_out_treevox"
    outdir.mkdir(exist_ok=True)
    common = 0.0
    for n in names:
        _, _, m = load(n)
        common = max(common, m["height"] * 1.18, m["radius"] * 2.3)
    tiles = []
    for n in names:
        out = outdir / f"preview_{n}.png"
        render(n, out, span=common)
        tiles.append(Image.open(out))
    if len(tiles) > 1:
        sheet = Image.new("RGB", (SIZE * len(tiles), SIZE))
        for i, t in enumerate(tiles):
            sheet.paste(t, (i * SIZE, 0))
        sheet.save(outdir / "preview_sheet.png")
        print(f"sheet: {outdir / 'preview_sheet.png'}")


if __name__ == "__main__":
    main()
