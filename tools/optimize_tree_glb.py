"""Optimize an authored tree GLB into the shipped bake.

Outputs, next to the GLB:

    <name>.mesh.bin    TTR1 prop mesh (trunk + canopy index ranges)
    <name>.png         128x128 basecolor, quantized to the game's palette
    <name>.meta.json   bake stats

Usage:  python tools/optimize_tree_glb.py [name ...]      (default: every
GLB under assets/ground/tree/)

WHY 200 TRIANGLES AND NOT 1800
------------------------------
The lamp post affords 1800 because at most 28 posts exist and each is drawn
by TRANSFORM -- one mesh, 28 draw calls.  Trees cannot work that way.  The
round-tree hulls they replace live in the CHUNK MESH, which is built when a
map loads, so "swap the nearest N for authored models" is a per-frame
ranking against a per-build decision: the nearest N would come out wearing
the hull AND the model at once.

So a tree is stamped into one combined mesh at build time, like the hulls
were, and the budget is what a stamp can afford.  Structures hands us a few
hundred round stamps on a forested route:

    300 trees x 1800 tris  ->  1,620,000 verts   (what froze the grass)
    300 trees x  200 tris  ->    180,000 verts   (here)

180k vertex sub-tables in the build coroutine is roughly a tenth of the
grass freeze and it happens ONCE PER MAP rather than four times per cell.

WHY THAT IS ENOUGH
------------------
tests/prop_alpha_probe.lua measured the prop path honouring `discard` at
0.5: a texel at alpha 0.30 vanished rather than ghosting.  So the canopy's
silhouette can live in the TEXTURE -- a cut edge costs no triangles at all
-- and 200 tris go to volume instead of outline.

WHY THE PALETTE IS FORCED
-------------------------
An authored tree stands next to buildings textured from the real Game Boy
tileset.  Measured off tests' own daylight frame, this game's foliage is a
yellow-green ramp with essentially NO BLUE (B is 0 or 16 in all ten of the
commonest vegetation colours, R 16..96, G 64..192).  A generator's canopy
is bluer and more desaturated than that, and the mismatch is what makes an
imported asset read as imported.  So the canopy is snapped to the measured
ramp rather than merely tinted.
"""
from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from optimize_lamppost_glb import (  # noqa: E402  (path set above)
    read_glb, accessor, texture_image, sample, weld, simplify, vertex_normals,
)

ROOT = Path(__file__).resolve().parents[1]
TREE_DIR = ROOT / "assets" / "ground" / "tree"

MAX_TRIS = 300
CARD_COUNT = 60      # each is 2 tris, so 120 on top of the solid canopy
CARD_STRIP = 0.25    # bottom fraction of the atlas reserved for the leaf sprite
TEX_SIZE = 128
TARGET_HEIGHT = 30.0  # world px; a round-tree hull spans a 32px 2x2 cell

MAGIC = b"TTR2"   # v1 was 6 floats/vertex; v2 adds the canopy weight

# The measured ramp (see the header).  Dark to light, blue held at zero --
# that absence IS the signature; a canopy that keeps its blue reads as a
# different game's tree no matter how good its silhouette is.
FOLIAGE_RAMP = np.array([
    (24, 64, 0),
    (32, 96, 0),
    (48, 128, 0),
    (80, 176, 0),
    (112, 208, 16),
], dtype=np.float32)

# Gen 1 trunks are a short warm ramp, likewise blue-poor.
BARK_RAMP = np.array([
    (56, 32, 0),
    (96, 56, 8),
    (136, 88, 24),
], dtype=np.float32)


def quantize_to_game_palette(img: Image.Image) -> Image.Image:
    """Snap foliage to the measured green ramp and bark to the brown one.

    Classify by hue rather than by position in the atlas: a generator's UV
    layout is fragmented and there is no "top half is leaves" to rely on.
    Green-dominant texels are foliage, red-dominant are bark, and anything
    else (there should be almost nothing) is left alone rather than forced
    into a ramp it does not belong to.

    Within a ramp the texel keeps its RELATIVE brightness -- the rank of its
    luminance picks the rung.  That is what preserves the contact occlusion
    the generator painted, which is the only shading a tree gets here: the
    renderer's vertex format carries no normal, only a shade scalar baked
    off normal.y, so a canopy flattened to one flat green would have no
    volume at all.
    """
    a = np.asarray(img.convert("RGB"), dtype=np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    lum = 0.299 * r + 0.587 * g + 0.114 * b

    # Foliage is "green-DOMINANT", not "green and not blue": a stylized
    # canopy is often teal (the PerfectTree reference is ~(60,180,175)), and
    # a `g > b + 8` test rejects teal outright -- which left the reference's
    # canopy unquantized, still wearing its own colour next to Game Boy art.
    leaf = (g > r + 8) & (g >= b - 12)
    bark = (r > g + 8) & (r > b + 8)

    out = a.copy()
    for mask, ramp in ((leaf, FOLIAGE_RAMP), (bark, BARK_RAMP)):
        if not mask.any():
            continue
        v = lum[mask]
        lo, hi = float(v.min()), float(v.max())
        t = (v - lo) / max(hi - lo, 1e-6)
        rung = np.clip((t * len(ramp)).astype(int), 0, len(ramp) - 1)
        out[mask] = ramp[rung]

    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB")



def leaf_sprite(size: int, strip: int) -> Image.Image:
    """A cluster of leaf blades on transparent ground, for the alpha cards.

    tests/prop_alpha_probe.lua measured this renderer discarding texels
    below alpha 0.5 on the prop path, so a cut edge costs nothing: the
    ragged outline of a leaf cluster can live entirely in the texture while
    the geometry stays two triangles. That is the whole point of the cards
    -- solid canopy buys volume at ~7 tris per visible leaf clump, a card
    buys the same clump for 2 and a cut edge.

    Drawn rather than sampled off the model: the model's own canopy texels
    are a closed shell with no alpha anywhere to cut against.
    """
    import random
    from PIL import ImageDraw
    img = Image.new("RGBA", (size, strip), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rnd = random.Random(20260817)
    cx, cy = size * 0.5, strip * 0.5
    for i in range(34):
        ang = rnd.uniform(0, 6.2832)
        rad = rnd.uniform(0.05, 0.46) * size
        x = cx + rad * math.cos(ang)
        y = cy + rad * math.sin(ang) * (strip / size) * 2.2
        w = rnd.uniform(0.06, 0.15) * size
        h = w * rnd.uniform(0.45, 0.85)
        rung = FOLIAGE_RAMP[rnd.randrange(1, len(FOLIAGE_RAMP))]
        col = (int(rung[0]), int(rung[1]), int(rung[2]), 255)
        d.ellipse([x - w, y - h, x + w, y + h], fill=col)
    return img


def foliage_cards(pos, tris, canopy_mask, height, canopy_r):
    """Quads scattered over the canopy, tilted toward horizontal.

    ORIENTATION IS THE WHOLE DESIGN DECISION. The usual trick is crossed
    VERTICAL billboards, which is right for a camera at eye level and wrong
    here: this game's diorama camera sits between 35 and 75 degrees, and a
    vertical card seen from above collapses to a line. So each card is a
    plane tilted only 18-42 degrees off horizontal -- from this camera it
    presents its face, and from the low rungs its edge is hidden inside the
    canopy it sits on.

    Cards are seeded from real canopy vertices so they land ON the foliage
    rather than in a sphere around it, which keeps them off the trunk and
    out of the air under the tree.
    """
    import random
    rnd = random.Random(7717)
    idx = np.unique(tris[canopy_mask].ravel())
    if len(idx) == 0:
        return np.zeros((0, 3)), np.zeros((0, 2)), np.zeros((0, 3), dtype=np.int64)
    seeds = pos[idx]
    verts, uvs, faces = [], [], []
    for _ in range(CARD_COUNT):
        p = seeds[rnd.randrange(len(seeds))]
        size = canopy_r * rnd.uniform(0.30, 0.52)
        tilt = math.radians(rnd.uniform(18.0, 42.0))
        az = rnd.uniform(0.0, 6.2832)
        ca, sa = math.cos(az), math.sin(az)
        # in-plane axes: u sweeps horizontally, v is lifted by the tilt
        ux, uy, uz = ca, 0.0, sa
        vx, vy, vz = -sa * math.cos(tilt), math.sin(tilt), ca * math.cos(tilt)
        base = len(verts)
        for su, sv, tu, tv in ((-1, -1, 0.0, 1.0), (1, -1, 1.0, 1.0),
                               (1, 1, 1.0, 0.0), (-1, 1, 0.0, 0.0)):
            verts.append([p[0] + (ux * su + vx * sv) * size,
                          p[1] + (uy * su + vy * sv) * size * 0.55,
                          p[2] + (uz * su + vz * sv) * size])
            # into the atlas strip reserved for the leaf sprite
            uvs.append([tu, 1.0 - CARD_STRIP * (1.0 - tv)])
        faces.append([base, base + 1, base + 2])
        faces.append([base, base + 2, base + 3])
    return (np.array(verts, dtype=np.float64),
            np.array(uvs, dtype=np.float64),
            np.array(faces, dtype=np.int64))



def canopy_weight(pos, height):
    """How much each vertex belongs to the CANOPY, as a continuous 0..1.

    Replaces the old binary trunk/canopy split, which classified by COLOUR
    and broke on the first model that had moss painted on its trunk: the
    reference tree's bark is mossy green, the test read green as leaf, and
    the whole trunk came out as canopy (9 trunk triangles, canopyY = 0).

    Geometry cannot lie about that the way colour can. Two things make a
    vertex canopy-ish, and they multiply rather than add so that BOTH have
    to hold:

      * height along the tree, eased so the base of the trunk is hard zero
        and the weight only starts climbing above the lowest branches;
      * distance from the vertical axis, because at any given height the
        wood is near the axis and the leaves are out at the rim.

    The product is what a wind curve wants -- near zero at the roots,
    rising through the crown, highest at the tips -- and it is also what
    snow wants, since snow piles by how exposed and how high a surface is.
    Nothing here asks "is this a leaf", so moss, bark colour and a
    generator's texture choices cannot reach it.
    """
    y = np.clip(pos[:, 1] / max(height, 1e-9), 0.0, 1.0)
    r = np.sqrt(pos[:, 0] ** 2 + pos[:, 2] ** 2)
    r_ref = max(float(np.percentile(r, 95)), 1e-9)
    radial = np.clip(r / r_ref, 0.0, 1.0)

    # Height term: flat zero over the bole, then smooth to 1. A hard cut
    # here is exactly the seam the continuous weight exists to avoid.
    t = np.clip((y - 0.22) / 0.55, 0.0, 1.0)
    vertical = t * t * (3.0 - 2.0 * t)

    # Radial term never reaches zero: a vertex dead on the axis high in the
    # crown is still crown, and should still move and still catch snow.
    w = vertical * (0.35 + 0.65 * radial)
    return np.clip(w, 0.0, 1.0).astype(np.float32)


def split_trunk_canopy(pos, uv, tris, base_img, height):
    """Which triangles are canopy, so the two can be moved independently.

    Wind belongs to the canopy and not to the trunk -- a post that sways at
    its base looks broken -- and the split costs nothing here because the
    index buffer is already being written in two ranges.

    Colour decides, with height only as a tie-breaker: a crooked trunk can
    reach well into the canopy's height band, and a low skirt of leaves can
    hang below the trunk's top, so a pure height cut mislabels both.
    """
    uv_mid = (uv[tris[:, 0]] + uv[tris[:, 1]] + uv[tris[:, 2]]) / 3.0
    rgb = sample(base_img, uv_mid)
    green = (rgb[:, 1] > rgb[:, 0] + 0.03) & (rgb[:, 1] >= rgb[:, 2] - 0.05)
    cy = (pos[tris[:, 0], 1] + pos[tris[:, 1], 1] + pos[tris[:, 2], 1]) / 3.0
    canopy = green | (cy > height * 0.85)
    return canopy


def bake(glb_path: Path) -> None:
    name = glb_path.stem
    out_dir = glb_path.parent
    js, blob = read_glb(glb_path)

    prim = js["meshes"][0]["primitives"][0]
    pos = accessor(js, blob, prim["attributes"]["POSITION"]).astype(np.float64)
    uv = accessor(js, blob, prim["attributes"]["TEXCOORD_0"]).astype(np.float64)
    tris = accessor(js, blob, prim["indices"]).reshape(-1, 3).astype(np.int64)
    base_img = texture_image(
        js, blob, prim["material"] and
        js["materials"][prim["material"]]["pbrMetallicRoughness"]
        ["baseColorTexture"]["index"]
    )
    print(f"{name}: source verts={len(pos)} tris={len(tris)}")

    src_pos = pos.copy()
    pos, uv, tris = weld(pos, uv, tris)
    print(f"{name}: welded  verts={len(pos)} tris={len(tris)}")

    pos, uv, tris = simplify(pos, uv, tris, MAX_TRIS)
    print(f"{name}: reduced verts={len(pos)} tris={len(tris)}")

    def normalize(p, scale=None):
        p = p.copy()
        p[:, 0] -= (p[:, 0].min() + p[:, 0].max()) * 0.5
        p[:, 2] -= (p[:, 2].min() + p[:, 2].max()) * 0.5
        p[:, 1] -= p[:, 1].min()
        s = scale if scale is not None else TARGET_HEIGHT / max(p[:, 1].max(), 1e-9)
        return p * s, s

    _, scale = normalize(src_pos)
    pos, _ = normalize(pos, scale)
    height = float(pos[:, 1].max())
    radius = float(max(np.abs(pos[:, 0]).max(), np.abs(pos[:, 2]).max()))

    canopy_mask = split_trunk_canopy(pos, uv, tris, base_img, height)
    trunk_tris, canopy_tris = tris[~canopy_mask], tris[canopy_mask]
    if len(canopy_tris) < 12:
        raise SystemExit(
            f"{name}: only {len(canopy_tris)} canopy triangles -- the colour "
            "split failed. Refusing to ship a tree that is all trunk."
        )
    cpos = pos[np.unique(canopy_tris.ravel())]
    canopy_y = float(cpos[:, 1].min())
    canopy_r = float(np.sqrt(cpos[:, 0] ** 2 + cpos[:, 2] ** 2).max())
    print(f"{name}: trunk={len(trunk_tris)} canopy={len(canopy_tris)} "
          f"canopyY={canopy_y:.1f} canopyR={canopy_r:.2f}")

    # Verify the SOLID mesh, before the cards join it: the height-band check
    # is about silhouette survival through decimation, and cards would pad
    # every band and hide exactly the collapse it exists to catch.
    verify_bands(src_pos, pos, tris, scale, height, name)

    # ---- alpha cards.
    #
    # The atlas gets split: the model's own texels are squeezed into the top
    # (1 - CARD_STRIP) of it and the leaf sprite takes the bottom strip. So
    # every ORIGINAL uv.y has to be rescaled into that top band -- forget
    # this and the whole tree samples leaf sprite.
    card_pos, card_uv, card_faces = foliage_cards(
        pos, tris, canopy_mask, height, canopy_r)
    uv = uv.copy()
    uv[:, 1] = uv[:, 1] * (1.0 - CARD_STRIP)
    n_solid = len(pos)
    if len(card_pos):
        pos = np.vstack([pos, card_pos])
        uv = np.vstack([uv, card_uv])
        canopy_tris = np.vstack([canopy_tris, card_faces + n_solid])
        tris = np.vstack([trunk_tris, canopy_tris])
    print(f"{name}: +{len(card_faces)} card tris "
          f"({len(card_faces) // 2} cards), total {len(tris)}")

    strip_h = max(1, int(round(TEX_SIZE * CARD_STRIP)))
    body = quantize_to_game_palette(
        base_img.resize((TEX_SIZE, TEX_SIZE - strip_h),
                        Image.Resampling.LANCZOS))
    tex = Image.new("RGBA", (TEX_SIZE, TEX_SIZE), (0, 0, 0, 0))
    tex.paste(body.convert("RGBA"), (0, 0))
    tex.paste(leaf_sprite(TEX_SIZE, strip_h), (0, TEX_SIZE - strip_h))
    tex_path = out_dir / f"{name}.png"
    tex.save(tex_path, optimize=True)

    # Vertex shade: magnitude is the face's brightness, the SIGN is the
    # renderer's "this face points at the sky" flag (vUp in Voxel3D's
    # shader), which is what lets snow settle on a canopy's shoulders.
    n = vertex_normals(pos, tris)
    ny = np.clip(n[:, 1], -1.0, 1.0)
    shade = 0.55 + 0.45 * np.clip(0.5 + 0.5 * ny, 0.0, 1.0)
    shade = np.where(ny > 0.45, -shade, shade)
    # Cards are near-horizontal, so their averaged normal points at the sky
    # and the sign convention would flag every one of them as a snow-catching
    # roof -- a tree wearing a full white disc per card in winter. They are
    # leaves: bright, and not roofs.
    if len(card_pos):
        shade[n_solid:] = 0.93

    cw = canopy_weight(pos, height)
    print(f"{name}: canopy weight  base={cw[pos[:, 1] < height * 0.15].mean():.3f} "
          f"crown={cw[pos[:, 1] > height * 0.80].mean():.3f} max={cw.max():.3f}")
    # The field IS the contract now, so assert its shape rather than a
    # triangle count: near zero down the bole, near one out at the tips.
    base_w = float(cw[pos[:, 1] < height * 0.15].mean())
    crown_w = float(cw[pos[:, 1] > height * 0.80].mean())
    if base_w > 0.08 or crown_w < 0.55:
        raise SystemExit(
            f"{name}: canopy weight field is wrong (base={base_w:.3f} "
            f"should be ~0, crown={crown_w:.3f} should be ~1). A tree that "
            "ships this would sway from its roots.")

    indices = np.concatenate(
        [trunk_tris.reshape(-1), canopy_tris.reshape(-1)]
    ).astype(np.uint16)
    n_trunk = int(trunk_tris.size)
    nv, ni = len(pos), len(indices)
    if nv > 65535:
        raise SystemExit(f"{nv} verts will not fit a uint16 index buffer")

    bin_path = out_dir / f"{name}.mesh.bin"
    with open(bin_path, "wb") as f:
        f.write(MAGIC)
        f.write(struct.pack("<III", nv, ni, n_trunk))
        f.write(struct.pack("<ffff", height, radius, canopy_y, canopy_r))
        buf = np.empty((nv, 7), dtype=np.float32)
        buf[:, 0:3] = pos
        buf[:, 3:5] = uv
        buf[:, 5] = shade
        buf[:, 6] = cw          # clean, unpacked -- Trees3D packs at stamp time
        f.write(buf.tobytes())
        f.write(indices.tobytes())

    meta = {
        "format": "terrarium-tree-v2",
        "kind": name,
        "bin": bin_path.name,
        "texture": tex_path.name,
        "verts": nv,
        "indices": ni,
        "tris": ni // 3,
        "trunkTris": n_trunk // 3,
        "canopyTris": (ni - n_trunk) // 3,
        "height": height,
        "radius": radius,
        "canopyY": canopy_y,
        "canopyR": canopy_r,
        "canopyWeightBase": base_w,
        "canopyWeightCrown": crown_w,
        "source": glb_path.name,
    }
    (out_dir / f"{name}.meta.json").write_text(json.dumps(meta, indent=2))
    print(f"{name}: wrote {bin_path.name} ({bin_path.stat().st_size} B) "
          f"and {tex_path.name}; {glb_path.stat().st_size // 1024} KB GLB -> "
          f"{(bin_path.stat().st_size + tex_path.stat().st_size) // 1024} KB")


def verify_bands(src_pos, pos, tris, scale, height, name):
    """Every height band of the source must still carry triangles.

    This is the check that would have caught the lamp post's vanished shaft,
    and a tree has the same failure mode in a worse place: decimation eats
    the TRUNK first, because it is the thinnest thing in the model and the
    canopy owns most of the surface area.  A tree whose trunk collapsed is a
    green ball hovering over the grass, and no triangle count reports it.
    """
    sp = src_pos.copy()
    sp[:, 0] -= (sp[:, 0].min() + sp[:, 0].max()) * 0.5
    sp[:, 2] -= (sp[:, 2].min() + sp[:, 2].max()) * 0.5
    sp[:, 1] -= sp[:, 1].min()
    sp *= scale

    step = height / 10.0
    print(f"{name}: verify height band -> tris, radius (baked vs source)")
    bad = []
    cy = (pos[tris[:, 0], 1] + pos[tris[:, 1], 1] + pos[tris[:, 2], 1]) / 3.0
    for i in range(10):
        lo, hi = i * step, (i + 1) * step
        sel = (cy >= lo) & (cy < hi)
        src_sel = (sp[:, 1] >= lo) & (sp[:, 1] < hi)
        if not src_sel.any():
            continue
        r_src = float(np.sqrt(sp[src_sel, 0] ** 2 + sp[src_sel, 2] ** 2).max())
        r_bake = (float(np.sqrt(pos[tris[sel].ravel(), 0] ** 2
                                + pos[tris[sel].ravel(), 2] ** 2).max())
                  if sel.any() else 0.0)
        print(f"   y {lo:5.1f}-{hi:5.1f}: tris={int(sel.sum()):4d} "
              f"r={r_bake:5.2f} (src {r_src:5.2f})")
        if not sel.any():
            bad.append(f"band y {lo:.1f}-{hi:.1f} lost every triangle")
    if bad:
        raise SystemExit(f"{name}: " + "; ".join(bad))
    print(f"{name}: verify tree is whole (every source band survives)")


def main():
    names = sys.argv[1:]
    globs = [TREE_DIR / f"{n}.glb" for n in names] if names \
        else sorted(TREE_DIR.glob("*.glb"))
    if not globs:
        raise SystemExit(f"no tree GLBs under {TREE_DIR}")
    for p in globs:
        bake(p)


if __name__ == "__main__":
    main()
