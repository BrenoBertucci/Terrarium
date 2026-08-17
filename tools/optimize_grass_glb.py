"""Optimize assets/ground/grass/grass-texture.glb into shipped grass.png + grass.mesh.bin.

Love/Gen1Recomp cannot load glTF; this bakes a light triangle mesh and a 128
basecolor so Structures/Grass3D can stamp real 3D tufts instead of the 8x8
voxel slab. Re-run after replacing the GLB.
"""
from __future__ import annotations

import io
import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GLB = ROOT / "assets" / "ground" / "grass" / "grass-texture.glb"
OUT = GLB.parent
# THE MESH IS STAMPED FOUR TIMES PER GRASS CELL, not drawn once.
#
# Structures.buildGrass walks HALF-tiles -- `wx = tx * 8` where a cell is 16
# -- so one tall-grass cell produces FOUR instances, and every one of them
# is a full copy of this template appended into a Lua table in
# Grass3D.meshFromInstances.
#
# This was 1800 triangles / 1719 vertices, which is a budget for a model you
# look at. On a route with three hundred grass cells that is twelve hundred
# tufts:
#
#     1800 tris   ->  2,062,800 vertices in one mesh   (the shipped bake)
#      160 tris   ->    283,200                        (first cut at this)
#       24 tris   ->     46,800                        (here)
#
# Two million vertices is not a GPU problem, it is a LUA problem: they are
# built as two million six-element sub-tables in a single loop that cannot
# yield. That is what froze the game and took the pause menu with it when
# the GRASS row was set to 3D.
#
# lib/Grass3D.MAX_TRIS is the runtime guard. It refuses a bake above its
# budget and falls back to the tileset slab, so a future re-bake that
# forgets this note degrades instead of hanging.
MAX_TRIS = 24
TEX_SIZE = 128
TARGET_HEIGHT = 10.0  # world pixels (knee-high Gen1 grass)


def read_glb(path: Path):
    data = path.read_bytes()
    if data[:4] != b"glTF":
        raise SystemExit(f"not a GLB: {path}")
    chunk_len = struct.unpack_from("<I", data, 12)[0]
    js = json.loads(data[20 : 20 + chunk_len])
    bin_off = 20 + chunk_len
    bin_off += (4 - (bin_off % 4)) % 4
    bin_len = struct.unpack_from("<I", data, bin_off)[0]
    blob = data[bin_off + 8 : bin_off + 8 + bin_len]
    return js, blob


def accessor(js, blob, idx):
    acc = js["accessors"][idx]
    bv = js["bufferViews"][acc["bufferView"]]
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    ctype = acc["componentType"]
    t = acc["type"]
    count = acc["count"]
    comp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[t]
    dtype = {
        5120: np.int8,
        5121: np.uint8,
        5122: np.int16,
        5123: np.uint16,
        5125: np.uint32,
        5126: np.float32,
    }[ctype]
    raw = np.frombuffer(blob, dtype=dtype, count=count * comp, offset=off)
    return raw.reshape(count, comp) if comp > 1 else raw


def main():
    if not GLB.exists():
        raise SystemExit(f"missing {GLB}")
    js, blob = read_glb(GLB)
    prim = js["meshes"][0]["primitives"][0]
    pos = accessor(js, blob, prim["attributes"]["POSITION"]).astype(np.float32)
    norm = accessor(js, blob, prim["attributes"]["NORMAL"]).astype(np.float32)
    uv = accessor(js, blob, prim["attributes"]["TEXCOORD_0"]).astype(np.float32)
    idx = accessor(js, blob, prim["indices"]).astype(np.int64)
    print(f"source verts={len(pos)} tris={len(idx)//3}")

    # baseColor is images[2] in this asset (pbr baseColorTexture index 2)
    mat = js["materials"][0]
    bci = mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    img_i = js["textures"][bci]["source"]
    im = js["images"][img_i]
    bv = js["bufferViews"][im["bufferView"]]
    raw = blob[bv.get("byteOffset", 0) : bv.get("byteOffset", 0) + bv["byteLength"]]
    img = Image.open(io.BytesIO(raw)).convert("RGBA")

    # quantize-merge
    q = np.round(pos * 1000.0).astype(np.int32)
    dtype = np.dtype([("x", q.dtype), ("y", q.dtype), ("z", q.dtype)])
    st = np.ascontiguousarray(q).view(dtype).reshape(-1)
    uniq, inv = np.unique(st, return_inverse=True)
    new_pos = np.zeros((len(uniq), 3), np.float32)
    new_uv = np.zeros((len(uniq), 2), np.float32)
    new_n = np.zeros((len(uniq), 3), np.float32)
    cnt = np.zeros(len(uniq), np.float32)
    for i in range(len(pos)):
        j = inv[i]
        new_pos[j] += pos[i]
        new_uv[j] += uv[i]
        new_n[j] += norm[i]
        cnt[j] += 1
    new_pos /= cnt[:, None]
    new_uv /= cnt[:, None]
    new_n /= cnt[:, None]
    ln = np.linalg.norm(new_n, axis=1, keepdims=True)
    ln[ln < 1e-8] = 1
    new_n /= ln
    tris = inv[idx].reshape(-1, 3)
    keep = (tris[:, 0] != tris[:, 1]) & (tris[:, 1] != tris[:, 2]) & (
        tris[:, 0] != tris[:, 2]
    )
    tris = tris[keep]

    if len(tris) > MAX_TRIS:
        y = new_pos[:, 1]
        score = y[tris].max(axis=1) + np.random.RandomState(0).rand(len(tris)) * 0.01
        order = np.argsort(-score)
        n_top = int(MAX_TRIS * 0.7)
        n_base = MAX_TRIS - n_top
        top = order[:n_top]
        rest = order[n_top:]
        base = rest[np.argsort(score[rest])[:n_base]] if len(rest) > n_base else rest
        sel = np.unique(np.concatenate([top, base]))[:MAX_TRIS]
        tris = tris[sel]

    used = np.unique(tris.ravel())
    remap = np.full(len(new_pos), -1, np.int32)
    remap[used] = np.arange(len(used), dtype=np.int32)
    pos2 = new_pos[used]
    uv2 = new_uv[used]
    n2 = new_n[used]
    idx2 = remap[tris.ravel()].astype(np.uint16)

    # fit world pixels
    h = float(pos2[:, 1].max() - pos2[:, 1].min())
    s = TARGET_HEIGHT / max(h, 1e-6)
    pos2 = pos2.copy()
    pos2[:, 0] -= (pos2[:, 0].min() + pos2[:, 0].max()) * 0.5
    pos2[:, 2] -= (pos2[:, 2].min() + pos2[:, 2].max()) * 0.5
    pos2[:, 1] -= pos2[:, 1].min()
    pos2 *= s
    height = float(pos2[:, 1].max())
    radius = float(max(np.abs(pos2[:, 0]).max(), np.abs(pos2[:, 2]).max()))

    tex = img.resize((TEX_SIZE, TEX_SIZE), Image.Resampling.LANCZOS)
    tex_path = OUT / "grass.png"
    tex.save(tex_path, optimize=True)

    verts = []
    for i in range(len(pos2)):
        ny = float(n2[i, 1])
        shade = 0.55 + 0.45 * max(0.0, min(1.0, 0.5 + 0.5 * ny))
        verts.append(
            (
                float(pos2[i, 0]),
                float(pos2[i, 1]),
                float(pos2[i, 2]),
                float(uv2[i, 0]),
                float(uv2[i, 1]),
                shade,
            )
        )
    indices = idx2.reshape(-1).tolist()
    nv, ni = len(verts), len(indices)
    bin_path = OUT / "grass.mesh.bin"
    with open(bin_path, "wb") as f:
        f.write(struct.pack("<IIff", nv, ni, height, radius))
        for v in verts:
            f.write(struct.pack("<6f", *v))
        f.write(np.array(indices, dtype=np.uint16).tobytes())
    meta = {
        "format": "terrarium-grass-v1",
        "bin": "grass.mesh.bin",
        "texture": "grass.png",
        "verts": nv,
        "indices": ni,
        "tris": ni // 3,
        "height": height,
        "radius": radius,
        "source": "grass-texture.glb",
    }
    (OUT / "grass.meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print(
        f"wrote {tex_path.name} ({tex_path.stat().st_size}) "
        f"{bin_path.name} ({bin_path.stat().st_size}) "
        f"nv={nv} tris={ni//3} h={height:.2f} r={radius:.2f}"
    )
    print(f"from {GLB.stat().st_size/1e6:.1f} MB GLB -> {(tex_path.stat().st_size+bin_path.stat().st_size)/1e3:.0f} KB")


if __name__ == "__main__":
    main()
