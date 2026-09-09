"""Isometric preview of a band-table building drawn from a custom PNG.

The design loop for the Poke Mart rebuild. tools/building_voxels.py is the
Python restatement of lib/Buildings.lua's band table, and its profile/build/
verify stages only ever touch {W,H,col,out,src} -- none of them cares that
`sprite()` happened to composite those out of the tileset atlas. So this
file swaps in a reader that takes them from an RGBA sheet instead, exactly
the way lib/Buildings.lua's `readSprite` does, and gets the same model.

Two differences from the atlas reader, both deliberate and both mirrored in
the Lua:
  - the silhouette is the ALPHA channel, not a light-pixel flood. An
    authored sheet states its own outline; it does not need to be sealed in
    by a black border, and `seal` is meaningless here.
  - `col` is the shade CLASS of each texel (shadeOf's min(r,g,b) rungs),
    used only to find frames, panes and the palette; the drawn COLOUR is
    kept alongside so the preview can paint what the game will paint,
    rather than four greys.

    python tools/mart_preview.py assets/buildings/mart_facade.png OUTDIR
"""
import argparse
import importlib.util
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
WHITE, GREY, DARK, BLACK = 0, 1, 2, 3


def load_bv():
    spec = importlib.util.spec_from_file_location(
        "building_voxels", os.path.join(HERE, "building_voxels.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def shade_of(r, g, b, a):
    """lib/Buildings.lua:75 -- transparent counts as WHITE so it never
    reads as a frame, and the rungs are on the darkest channel so a
    saturated blue lands in the same class its luminance implies."""
    if a == 0:
        return WHITE
    v = min(r, g, b) / 255.0
    if v <= 0.25:
        return BLACK
    if v <= 0.55:
        return DARK
    if v <= 0.85:
        return GREY
    return WHITE


def read_png(path):
    im = Image.open(path).convert("RGBA")
    W, H = im.size
    px = im.load()
    col = [[0] * W for _ in range(H)]
    rgb = [[(0, 0, 0)] * W for _ in range(H)]
    out = [[False] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            col[y][x] = shade_of(r, g, b, a)
            rgb[y][x] = (r, g, b)
            out[y][x] = a < 10          # alpha IS the silhouette
    # 4-connected flood from the border through transparent pixels only, so
    # a transparent hole the border cannot reach stays part of the building
    seen = [[False] * W for _ in range(H)]
    stack = []

    def seed(x, y):
        if 0 <= x < W and 0 <= y < H and not seen[y][x] and out[y][x]:
            seen[y][x] = True
            stack.append((x, y))

    for x in range(W):
        seed(x, 0)
        seed(x, H - 1)
    for y in range(H):
        seed(0, y)
        seed(W - 1, y)
    while stack:
        x, y = stack.pop()
        seed(x + 1, y)
        seed(x - 1, y)
        seed(x, y + 1)
        seed(x, y - 1)
    outside = [[seen[y][x] for x in range(W)] for y in range(H)]
    src = [[(x, y) for x in range(W)] for y in range(H)]
    return dict(W=W, H=H, col=col, out=outside, src=src, rgb=rgb,
                pal=[(255, 255, 255), (170, 170, 170), (85, 85, 85), (0, 0, 0)])


def preview(shell, vox, sp, name, out, flip, canvas=(1600, 1000), pad=24,
            bg=(0x2a, 0x2e, 0x34)):
    """building_voxels.preview, repainted from the sheet's real colours.

    Face factors match lib/Buildings.lua's SHADE table (south 1.0, side .78,
    top .95) so the preview and the game agree about which face is which,
    and a value read here is a value the shader will start from."""
    zs = [z for _, _, z in shell]
    zlo, zhi = min(zs), max(zs)
    pts = [(x, y, (zlo + zhi - z) if flip else z, vox[(x, y, z)][1])
           for (x, y, z) in shell]
    pts.sort(key=lambda p: (p[0] + p[2], p[1]))
    px_ = lambda x, z: 2 * (x - z)
    py_ = lambda x, y, z: (x + z) - 2 * y
    xs = ([px_(x, z) for x, _, z, _ in pts]
          + [px_(x + 1, z + 1) for x, _, z, _ in pts])
    ys = ([py_(x, y, z) for x, y, z, _ in pts]
          + [py_(x + 1, y + 1, z + 1) for x, y, z, _ in pts])
    W, H = canvas
    S = max(1, min((W - 2 * pad) // max(1, max(xs) - min(xs)),
                   (H - 2 * pad) // max(1, max(ys) - min(ys))))
    ox = pad - min(xs) * S + (W - 2 * pad - (max(xs) - min(xs)) * S) // 2
    oy = pad - min(ys) * S + (H - 2 * pad - (max(ys) - min(ys)) * S) // 2
    P = lambda x, y, z: (px_(x, z) * S + ox, py_(x, y, z) * S + oy)
    img = Image.new("RGB", canvas, bg)
    dr = ImageDraw.Draw(img)
    has = {(x, y, z) for x, y, z, _ in pts}
    rgb = sp["rgb"]

    def face(s, f):
        r, g, b = rgb[s[1]][s[0]]
        return (int(r * f), int(g * f), int(b * f))

    for x, y, z, s in pts:
        if (x, y + 1, z) not in has:                        # top
            dr.polygon([P(x, y + 1, z), P(x + 1, y + 1, z),
                        P(x + 1, y + 1, z + 1), P(x, y + 1, z + 1)],
                       fill=face(s, 0.95))
        if (x + 1, y, z) not in has:                        # east flank
            dr.polygon([P(x + 1, y, z), P(x + 1, y + 1, z),
                        P(x + 1, y + 1, z + 1), P(x + 1, y, z + 1)],
                       fill=face(s, 0.78))
        if (x, y, z + 1) not in has:                        # south facade
            dr.polygon([P(x, y, z + 1), P(x + 1, y, z + 1),
                        P(x + 1, y + 1, z + 1), P(x, y + 1, z + 1)],
                       fill=face(s, 1.0))
    img.save(os.path.join(out, name))


TEMPLATE = dict(
    roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
    slab=5, front_eave=6, eave_out=3, recess_depth=3, sill=False,
    ledge=None, tiles=[[0] * 8 for _ in range(8)], depth=64,
    chimney=None,
)


def run(png, outdir, t=None, name="mart"):
    bv = load_bv()
    t = dict(TEMPLATE, **(t or {}))
    sp = read_png(png)
    pr = bv.profile(sp, t)
    # The atlas reader can assume sprite height == footprint depth; an
    # authored sheet cannot (its roof plan and its facade are stacked in
    # one image), so the footprint is stated, the way `parts` states its
    # own z span. lib/Buildings.lua reads the same value as t.depth.
    pr["D"] = t.get("depth") or (len(t["tiles"]) * 8)
    vox = bv.build(sp, pr, t)
    ch = t.get("chimney")
    if ch:
        # building_voxels.build has no chimney clause -- the Lua's is in
        # emit()'s `at`, not the band table -- so the box is added here to
        # keep the preview's silhouette honest about what the game stands on
        # the roof. Same shading rule as lib/Buildings.lua: BLACK rims, DARK
        # body, both taken from the sheet's palette strip.
        pal = {}
        for y in range(sp["H"]):
            for x in range(sp["W"]):
                c = sp["col"][y][x]
                if not sp["out"][y][x] and c not in pal:
                    pal[c] = (x, y)
        dark = pal.get(DARK) or pal.get(BLACK) or (0, 0)
        black = pal.get(BLACK) or dark
        cx, cz, cw, chh = ch["x"], ch["z"], ch["w"], ch["h"]
        base = pr["ytop"]
        for x in range(cx, cx + cw):
            for z in range(cz, cz + cw):
                for y in range(base + 1, base + chh + 1):
                    s_ = black if (y == base + chh or y == base + 1) else dark
                    vox[(x, y, z)] = (sp["col"][s_[1]][s_[0]], s_)
    shell = bv.verify(vox, sp, pr, t) if not ch else [
        k for k in vox if not all(
            (k[0] + d[0], k[1] + d[1], k[2] + d[2]) in vox
            for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0),
                      (0, -1, 0), (0, 0, 1), (0, 0, -1)))]
    print("%s: %dx%d sheet, depth %d, height %d -> voxels %d  shell %d  "
          "recessed %d" % (name, sp["W"], sp["H"], pr["D"], pr["ytop"] + 1,
                           len(vox), len(shell), len(pr["recess"])))
    os.makedirs(outdir, exist_ok=True)
    preview(shell, vox, sp, name + "_front.png", outdir, True)
    preview(shell, vox, sp, name + "_back.png", outdir, False)
    return vox, shell


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("png")
    ap.add_argument("outdir")
    ap.add_argument("--name", default="mart")
    ap.add_argument("--ledge", default=None,
                    help="sy0,sy1 -- the band that juts front and back")
    ap.add_argument("--set", action="append", default=[],
                    help="key=value override of the band table")
    ap.add_argument("--chimney", default=None, help="x,z,w,h rooftop box")
    a = ap.parse_args()
    t = {}
    if a.ledge:
        t["ledge"] = tuple(int(v) for v in a.ledge.split(","))
    if a.chimney:
        v = [int(n) for n in a.chimney.split(",")]
        t["chimney"] = dict(x=v[0], z=v[1], w=v[2], h=v[3])
    for kv in a.set:
        k, v = kv.split("=", 1)
        if "," in v:
            t[k] = tuple(int(n) for n in v.split(","))
        elif v in ("True", "False"):
            t[k] = v == "True"
        else:
            t[k] = int(v)
    run(a.png, a.outdir, t, a.name)


if __name__ == "__main__":
    main()
