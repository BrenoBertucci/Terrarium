"""Optimize assets/ground/lamppost/lamppost_texture.glb into the shipped bake.

Outputs, next to the GLB:

    lamppost.mesh.bin    TPR2 prop mesh (body + glass index ranges)
    lamppost.png         256x256 basecolor with the lantern's emissive burnt in
    lamppost.meta.json   bake stats

Re-run after replacing the GLB.

WHY NOT SPATIAL CLUSTERING
--------------------------
The first two versions of this tool reduced triangles by snapping vertices to
a grid and dropping whatever collapsed.  Both destroyed the post.  A grid cell
sized to fit the whole model is far wider than the shaft (~1 world px radius
against a 28 px model), so every vertex in a slice of the shaft merged to one
point, every triangle in it became degenerate, and the shaft was deleted --
leaving a lantern floating over a base plate.  That is not a simplification
failure that shows up as "slightly coarser"; it shows up as missing geometry.

This version uses quadric error metric (QEM) edge collapse instead.  It only
ever merges two vertices that already share an edge, so a connected surface
stays connected no matter how far the triangle budget is pushed: a thin shaft
degrades into a coarser thin shaft, it cannot evaporate.  Collapsing across a
cylinder's cross-section carries a large quadric cost, which is exactly the
silhouette-preserving behaviour a lamp post needs.

The bake is verified at the end -- every height band of the source must still
carry triangles, and the shaft's radius must survive -- and the tool exits
non-zero if it does not.
"""
from __future__ import annotations

import heapq
import io
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GLB = ROOT / "assets" / "ground" / "lamppost" / "lamppost_texture.glb"
OUT = GLB.parent

# At most StreetLamps.MAX (28) posts are visible, each drawn once for the scene
# and once for the sun's shadow pass.  1800 triangles holds the shaft, the
# fluting and the lantern's facets at the size a post occupies on screen, and
# 28 * 1800 * 2 is a budget the mobile renderer already carries for grass.
MAX_TRIS = 1800
TEX_SIZE = 256
TARGET_HEIGHT = 28.0  # ~classic StreetLamps post height in world px

# A texel counts as lantern glass when the GLB's emissive map is this bright
# there.  The material carries a real emissiveTexture, so this is reading the
# author's own mask rather than guessing at "the top bit is probably the lamp".
EMISSIVE_CUT = 0.22

MAGIC = b"TPR2"


# ------------------------------------------------------------------ glTF --

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
    comp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    dtype = {
        5120: np.int8,
        5121: np.uint8,
        5122: np.int16,
        5123: np.uint16,
        5125: np.uint32,
        5126: np.float32,
    }[acc["componentType"]]
    raw = np.frombuffer(blob, dtype=dtype, count=acc["count"] * comp, offset=off)
    return raw.reshape(acc["count"], comp) if comp > 1 else raw


def texture_image(js, blob, tex_index):
    """Decode the glTF texture at `tex_index` (a *texture*, not an image)."""
    if tex_index is None:
        return None
    src = js["textures"][tex_index]["source"]
    im = js["images"][src]
    bv = js["bufferViews"][im["bufferView"]]
    off = bv.get("byteOffset", 0)
    return Image.open(io.BytesIO(blob[off : off + bv["byteLength"]]))


def sample(img: Image.Image, uv: np.ndarray) -> np.ndarray:
    """Nearest-texel sample of `img` at glTF UVs (origin top-left, v down)."""
    w, h = img.size
    a = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    x = np.clip((uv[:, 0] % 1.0) * w, 0, w - 1).astype(np.int32)
    y = np.clip((uv[:, 1] % 1.0) * h, 0, h - 1).astype(np.int32)
    return a[y, x]


# ------------------------------------------------------------------- QEM --

def weld(pos, uv, tris, eps=1e-7):
    """Merge corners that share a position *and* a UV.

    Welding on position alone would fuse the two sides of a UV seam and smear
    the atlas across it.  Keeping the seam split means the seam stays a
    topological boundary, which `simplify` then protects explicitly.
    """
    scale = 1.0 / max(eps, 1e-9)
    key = np.column_stack(
        [np.round(pos * scale).astype(np.int64), np.round(uv * 1e6).astype(np.int64)]
    )
    view = np.ascontiguousarray(key).view(
        np.dtype([(f"f{i}", np.int64) for i in range(key.shape[1])])
    ).reshape(-1)
    _, first, inverse = np.unique(view, return_index=True, return_inverse=True)
    return pos[first], uv[first], inverse[tris]


def face_quadrics(pos, tris):
    """Area-weighted fundamental error quadric per vertex."""
    a, b, c = pos[tris[:, 0]], pos[tris[:, 1]], pos[tris[:, 2]]
    cross = np.cross(b - a, c - a)
    area = 0.5 * np.linalg.norm(cross, axis=1)
    n = cross / np.maximum(np.linalg.norm(cross, axis=1, keepdims=True), 1e-20)
    d = -np.einsum("ij,ij->i", n, a)
    plane = np.column_stack([n, d])                       # (F, 4)
    kp = plane[:, :, None] * plane[:, None, :]            # (F, 4, 4)
    kp *= area[:, None, None]

    Q = np.zeros((len(pos), 4, 4), dtype=np.float64)
    for corner in range(3):
        np.add.at(Q, tris[:, corner], kp)
    return Q


def boundary_quadrics(pos, tris, Q):
    """Pin open edges (mesh borders and UV seams) with a perpendicular plane.

    Without this the simplifier happily eats a seam's border and the atlas
    tears.  The weight is large but finite, so a collapse *along* a seam is
    still allowed -- which is what keeps the budget reachable.
    """
    edges = np.concatenate(
        [tris[:, [0, 1]], tris[:, [1, 2]], tris[:, [2, 0]]], axis=0
    )
    face_of = np.tile(np.arange(len(tris)), 3)
    key = np.sort(edges, axis=1)
    view = np.ascontiguousarray(key).view(
        np.dtype([("a", np.int64), ("b", np.int64)])
    ).reshape(-1)
    uniq, inverse, counts = np.unique(view, return_inverse=True, return_counts=True)
    open_edge = counts[inverse] == 1
    if not open_edge.any():
        return np.zeros(len(pos), dtype=bool)

    a, b = edges[open_edge, 0], edges[open_edge, 1]
    f = tris[face_of[open_edge]]
    fa, fb, fc = pos[f[:, 0]], pos[f[:, 1]], pos[f[:, 2]]
    fn = np.cross(fb - fa, fc - fa)
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-20)
    edge = pos[b] - pos[a]
    n = np.cross(edge, fn)
    weight = np.linalg.norm(edge, axis=1)                 # long borders bind harder
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-20)
    d = -np.einsum("ij,ij->i", n, pos[a])
    plane = np.column_stack([n, d])
    kp = plane[:, :, None] * plane[:, None, :] * (100.0 * weight)[:, None, None]
    np.add.at(Q, a, kp)
    np.add.at(Q, b, kp)

    is_boundary = np.zeros(len(pos), dtype=bool)
    is_boundary[a] = True
    is_boundary[b] = True
    return is_boundary


def simplify(pos, uv, tris, max_tris):
    """QEM edge collapse down to `max_tris`, preserving connectivity."""
    if len(tris) <= max_tris:
        return pos, uv, tris

    pos = pos.astype(np.float64).copy()
    uv = uv.astype(np.float64).copy()
    tris = tris.astype(np.int64).copy()

    Q = face_quadrics(pos, tris)
    is_boundary = boundary_quadrics(pos, tris, Q)

    nv = len(pos)
    alive_tri = np.ones(len(tris), dtype=bool)
    vert_faces = [set() for _ in range(nv)]
    for fi, t in enumerate(tris):
        for v in t:
            vert_faces[v].add(fi)
    neighbors = [set() for _ in range(nv)]
    for t in tris:
        for i in range(3):
            for j in range(3):
                if i != j:
                    neighbors[t[i]].add(t[j])

    version = np.zeros(nv, dtype=np.int64)
    merged_to = np.arange(nv)

    def cost_of(i, j):
        """Collapse cost and target position, restricted to the two endpoints
        and their midpoint.  Solving the quadric outright can place a vertex
        far outside the surface on the near-planar patches this model is full
        of; the constrained choice is stable and visually indistinguishable."""
        q = Q[i] + Q[j]
        best_c, best_p = None, None
        cands = [pos[i], pos[j], 0.5 * (pos[i] + pos[j])]
        if is_boundary[i] and not is_boundary[j]:
            cands = [pos[i]]
        elif is_boundary[j] and not is_boundary[i]:
            cands = [pos[j]]
        for p in cands:
            v = np.array([p[0], p[1], p[2], 1.0])
            c = float(v @ q @ v)
            if best_c is None or c < best_c:
                best_c, best_p = c, p
        return max(best_c, 0.0), np.asarray(best_p, dtype=np.float64)

    heap = []
    for i in range(nv):
        for j in neighbors[i]:
            if j > i:
                c, p = cost_of(i, j)
                heap.append((c, i, j, version[i], version[j], p))
    heapq.heapify(heap)

    def flips(keep, drop, target):
        """True when moving `keep` to `target` and folding `drop` into it
        would invert a surviving triangle -- the classic QEM failure that
        turns a silhouette inside out."""
        for fi in vert_faces[keep] | vert_faces[drop]:
            if not alive_tri[fi]:
                continue
            t = tris[fi]
            if drop in t and keep in t:
                continue                      # this face dies in the collapse
            p = [target if (v == keep or v == drop) else pos[v] for v in t]
            before = np.cross(pos[t[1]] - pos[t[0]], pos[t[2]] - pos[t[0]])
            after = np.cross(p[1] - p[0], p[2] - p[0])
            na = np.linalg.norm(after)
            if na < 1e-14:
                return True
            if float(before @ after) <= 0.0:
                return True
        return False

    live = int(alive_tri.sum())
    while live > max_tris and heap:
        c, i, j, vi, vj, target = heapq.heappop(heap)
        if version[i] != vi or version[j] != vj:
            continue                          # stale entry, endpoint moved on
        if merged_to[i] != i or merged_to[j] != j:
            continue
        if j not in neighbors[i]:
            continue
        # Never pull a seam or border vertex off its curve into the interior.
        if is_boundary[j] and not is_boundary[i]:
            i, j = j, i
        if is_boundary[j] and not is_boundary[i]:
            continue
        if flips(i, j, target):
            continue

        pos[i] = target
        if is_boundary[j] and is_boundary[i]:
            uv[i] = 0.5 * (uv[i] + uv[j])
        Q[i] = Q[i] + Q[j]
        is_boundary[i] = is_boundary[i] or is_boundary[j]
        merged_to[j] = i

        for fi in list(vert_faces[j]):
            if not alive_tri[fi]:
                continue
            t = tris[fi]
            t[t == j] = i
            if t[0] == t[1] or t[1] == t[2] or t[0] == t[2]:
                alive_tri[fi] = False
                live -= 1
                for v in set(t):
                    vert_faces[v].discard(fi)
            else:
                vert_faces[i].add(fi)
        vert_faces[j].clear()

        for k in neighbors[j]:
            neighbors[k].discard(j)
            if k != i:
                neighbors[k].add(i)
                neighbors[i].add(k)
        neighbors[i].discard(i)
        neighbors[j].clear()

        version[i] += 1
        version[j] += 1
        for k in neighbors[i]:
            version[k] += 0        # k's own entries stay valid; i's bumped above
            cc, pp = cost_of(i, k)
            a, b = (i, k) if i < k else (k, i)
            heapq.heappush(heap, (cc, a, b, version[a], version[b], pp))

    tris = tris[alive_tri]
    used = np.unique(tris.ravel())
    remap = np.full(len(pos), -1, dtype=np.int64)
    remap[used] = np.arange(len(used))
    return pos[used].astype(np.float32), uv[used].astype(np.float32), remap[tris]


# ----------------------------------------------------------------- shade --

def vertex_normals(pos, tris):
    a, b, c = pos[tris[:, 0]], pos[tris[:, 1]], pos[tris[:, 2]]
    fn = np.cross(b - a, c - a)                # unnormalized == area weighted
    n = np.zeros_like(pos)
    for corner in range(3):
        np.add.at(n, tris[:, corner], fn)
    length = np.linalg.norm(n, axis=1, keepdims=True)
    length[length < 1e-12] = 1.0
    return n / length


# ------------------------------------------------------------------ main --

def main():
    if not GLB.exists():
        raise SystemExit(f"missing {GLB}")
    js, blob = read_glb(GLB)
    prim = js["meshes"][0]["primitives"][0]
    pos = accessor(js, blob, prim["attributes"]["POSITION"]).astype(np.float64)
    uv = accessor(js, blob, prim["attributes"]["TEXCOORD_0"]).astype(np.float64)
    idx = accessor(js, blob, prim["indices"]).astype(np.int64).reshape(-1, 3)
    print(f"source verts={len(pos)} tris={len(idx)}")

    mat = js["materials"][0]
    base_img = texture_image(
        js, blob, mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    ).convert("RGB")
    emis_tex = mat.get("emissiveTexture", {}).get("index")
    emis_img = texture_image(js, blob, emis_tex)
    emis_img = emis_img.convert("RGB") if emis_img is not None else None
    emis_factor = np.asarray(mat.get("emissiveFactor", [1.0, 1.0, 1.0]), np.float32)

    src_pos = pos.copy()
    pos, uv, tris = weld(pos, uv, idx)
    print(f"welded  verts={len(pos)} tris={len(tris)}")
    pos, uv, tris = simplify(pos, uv, tris, MAX_TRIS)
    print(f"reduced verts={len(pos)} tris={len(tris)}")

    # Place the post: feet on y=0, centred on xz, scaled to the world height.
    def find_glass_without_emissive(pos, uv, tris, base_img, height):
        """Which triangles are lantern glass, for a GLB that ships no emissive map.

        Model generators produce a basecolor and (optionally) metallic /
        roughness / normal.  Emissive is not among them, so the mask the
        original bake read simply is not there, and the old fallback -- "the
        top 20% is the lantern" -- is a guess about HEIGHT.  It decides where
        StreetLamps hangs its point light (flameHeight reads lampY straight
        out of this bake), so a guess puts the pool of light in the wrong
        place on every post in every town.

        The shape knows better than the guess.  A lamp post is a thin shaft
        with something WIDE on top, so:

          1. Bin the model into height bands and measure each band's radius
             about the vertical axis.
          2. The shaft is the middle of the model; take its median radius.
          3. The lantern is the topmost run of bands wider than 1.5x that.

        That much finds the whole head -- roof cap, panes and collar.  The
        roof is not glass: flattening it to the lamp colour at night would
        light up the tin.  So inside the head, glass is the part that is
        WARM AND BRIGHT in the basecolor, which is the amber the panes were
        authored with.  Colour alone is not enough (a cream shaft is bright
        too), and geometry alone is not enough (the roof is up there too);
        the pair is what isolates the panes.
        """
        r = np.sqrt(pos[:, 0] ** 2 + pos[:, 2] ** 2)
        BANDS = 64
        band = np.clip((pos[:, 1] / max(height, 1e-9) * BANDS).astype(int), 0, BANDS - 1)
        band_r = np.array([
            r[band == b].max() if (band == b).any() else 0.0 for b in range(BANDS)
        ])
        mid = band_r[int(BANDS * 0.30):int(BANDS * 0.70)]
        shaft_r = float(np.median(mid[mid > 0])) if (mid > 0).any() else 0.0
        if shaft_r <= 0:
            raise SystemExit("lantern: no shaft to measure; the model is not a post")

        wide = band_r > shaft_r * 1.5
        if not wide[int(BANDS * 0.5):].any():
            raise SystemExit(
                "lantern: nothing above half height is wider than 1.5x the shaft "
                f"(shaft r={shaft_r:.3f}, max r={band_r.max():.3f}). "
                "Refusing to ship a post whose light would hang at a guessed height."
            )
        top = BANDS - 1
        while top > 0 and not wide[top]:
            top -= 1
        low = top
        while low > 0 and wide[low - 1]:
            low -= 1
        head_y0 = low / BANDS * height
        print(f"lantern: shaft r={shaft_r:.3f}, head from y={head_y0:.1f} to {height:.1f}")

        centroid = (pos[tris[:, 0]] + pos[tris[:, 1]] + pos[tris[:, 2]]) / 3.0
        in_head = centroid[:, 1] >= head_y0

        # Amber is not merely "warm": the roof cap is warm too, and a plain
        # warm test handed 1262 of 1800 triangles to the glass -- the whole
        # head, tin roof included, which the night pass would then light up.
        #
        # What separates them is the GREEN-TO-RED RATIO, measured off the
        # baked atlas rather than guessed:
        #
        #     amber pane   (224,160, 64)   G/R 0.71   B/G 0.40
        #     roof cap     (160, 32, 32)   G/R 0.20
        #     cream shaft  (224,224,192)   G/R 1.00   B/G 0.86
        #
        # so glass is the middle band of that ratio, bright, and low in blue
        # (which is what keeps cream out).
        uv_mid = (uv[tris[:, 0]] + uv[tris[:, 1]] + uv[tris[:, 2]]) / 3.0
        rgb = sample(base_img, uv_mid)
        red = np.maximum(rgb[:, 0], 1e-6)
        gr = rgb[:, 1] / red
        amber = (rgb[:, 0] > 0.60) & (gr > 0.55) & (gr < 0.90) & (rgb[:, 2] < 0.65 * rgb[:, 1])
        glass = in_head & amber
        if glass.sum() < 8:
            print(f"note: only {int(glass.sum())} warm triangles in the head; "
                  "using the whole head as glass")
            glass = in_head
        return glass

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

    # ---- the lantern.  The author's emissive map is the mask; a vertex whose
    # texel glows is glass, and glass is drawn as a separate index range so the
    # night pass can burn it full-bright while the ironwork stays under the
    # hour's tint (see StreetLamps.draw).
    #
    # Sample at the triangle's UV CENTROID, not at its corners.  A pane's
    # corners sit on the dark lead frame between panes, so a per-vertex test
    # finds almost no glass at all (the first attempt classified 100 of 1799
    # triangles and the lantern stayed dark).  The centroid lands inside the
    # pane, which is what the mask is drawn for.
    if emis_img is not None:
        mid = (uv[tris[:, 0]] + uv[tris[:, 1]] + uv[tris[:, 2]]) / 3.0
        centre = (sample(emis_img, mid) * emis_factor).max(axis=1)
        corners = (sample(emis_img, uv) * emis_factor).max(axis=1)
        # A triangle is glass when its middle glows, or when it is small enough
        # that the centroid is unreliable and two corners agree.
        tri_glass = (centre > EMISSIVE_CUT) | (
            (corners[tris] > EMISSIVE_CUT).sum(axis=1) >= 2
        )
    else:
        tri_glass = np.zeros(len(tris), dtype=bool)
    body_tris, glass_tris = tris[~tri_glass], tris[tri_glass]
    if len(glass_tris) == 0:
        tri_glass = find_glass_without_emissive(pos, uv, tris, base_img, height)
        body_tris, glass_tris = tris[~tri_glass], tris[tri_glass]
    glass_pos = pos[np.unique(glass_tris.ravel())] if len(glass_tris) else pos
    lamp_y = float(glass_pos[:, 1].mean())
    lamp_r = float(np.sqrt(glass_pos[:, 0] ** 2 + glass_pos[:, 2] ** 2).max())
    print(
        f"glass tris={len(glass_tris)} body tris={len(body_tris)} "
        f"lampY={lamp_y:.1f} lampR={lamp_r:.2f}"
    )

    # ---- albedo.  Emissive is burnt into the basecolor so the lantern is
    # already warm at noon; the night pass then lifts it, rather than having to
    # invent a colour that is not in the art.
    tex = base_img.resize((TEX_SIZE, TEX_SIZE), Image.Resampling.LANCZOS)
    if emis_img is not None:
        e = np.asarray(
            emis_img.resize((TEX_SIZE, TEX_SIZE), Image.Resampling.LANCZOS),
            dtype=np.float32,
        ) / 255.0 * emis_factor
        base = np.asarray(tex, dtype=np.float32) / 255.0
        lifted = np.clip(base + e * 0.85, 0.0, 1.0)
        tex = Image.fromarray((lifted * 255.0 + 0.5).astype(np.uint8), "RGB")
    tex_path = OUT / "lamppost.png"
    tex.save(tex_path, optimize=True)

    # ---- vertex shade.  Magnitude is the face's own brightness; the SIGN is
    # the renderer's "this face points at the sky" flag (see vUp in Voxel3D's
    # shader), which is what lets snow settle on the lamp's shoulders.
    n = vertex_normals(pos, tris)
    ny = np.clip(n[:, 1], -1.0, 1.0)
    shade = 0.55 + 0.45 * np.clip(0.5 + 0.5 * ny, 0.0, 1.0)
    shade = np.where(ny > 0.45, -shade, shade)

    indices = np.concatenate(
        [body_tris.reshape(-1), glass_tris.reshape(-1)]
    ).astype(np.uint16)
    n_body = int(body_tris.size)
    nv, ni = len(pos), len(indices)
    if nv > 65535:
        raise SystemExit(f"{nv} verts will not fit a uint16 index buffer")

    bin_path = OUT / "lamppost.mesh.bin"
    with open(bin_path, "wb") as f:
        f.write(MAGIC)
        f.write(struct.pack("<III", nv, ni, n_body))
        f.write(struct.pack("<ffff", height, radius, lamp_y, lamp_r))
        buf = np.empty((nv, 6), dtype=np.float32)
        buf[:, 0:3] = pos
        buf[:, 3:5] = uv
        buf[:, 5] = shade
        f.write(buf.tobytes())
        f.write(indices.tobytes())

    meta = {
        "format": "terrarium-prop-v2",
        "kind": "lamppost",
        "bin": bin_path.name,
        "texture": tex_path.name,
        "verts": nv,
        "indices": ni,
        "tris": ni // 3,
        "bodyTris": n_body // 3,
        "glassTris": (ni - n_body) // 3,
        "height": height,
        "radius": radius,
        "lampY": lamp_y,
        "lampR": lamp_r,
        "source": GLB.name,
    }
    (OUT / "lamppost.meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")

    verify(src_pos, pos, tris, scale, height)

    print(
        f"wrote {tex_path.name} ({tex_path.stat().st_size}) "
        f"{bin_path.name} ({bin_path.stat().st_size}) "
        f"nv={nv} tris={ni//3} h={height:.2f} r={radius:.2f}"
    )
    print(
        f"from {GLB.stat().st_size/1e6:.1f} MB GLB -> "
        f"{(tex_path.stat().st_size + bin_path.stat().st_size)/1e3:.0f} KB"
    )


def verify(src_pos, pos, tris, scale, height):
    """Fail the bake if the post is not whole.

    The previous two tools both shipped a lantern floating over a base plate,
    and nothing caught it until it was on screen.  A bake that loses a slice of
    the post now stops the build.
    """
    src = src_pos.copy()
    src[:, 0] -= (src[:, 0].min() + src[:, 0].max()) * 0.5
    src[:, 2] -= (src[:, 2].min() + src[:, 2].max()) * 0.5
    src[:, 1] -= src[:, 1].min()
    src *= scale

    a, b, c = pos[tris[:, 0]], pos[tris[:, 1]], pos[tris[:, 2]]
    cy = (a[:, 1] + b[:, 1] + c[:, 1]) / 3.0
    bands = np.linspace(0.0, height, 15)
    bad = []
    print("verify: height band -> tris, radius (baked vs source)")
    for i in range(14):
        lo, hi = bands[i], bands[i + 1]
        m = (cy >= lo) & (cy < hi)
        sm = (src[:, 1] >= lo) & (src[:, 1] < hi)
        if not sm.any():
            continue
        s_rad = float(np.percentile(np.hypot(src[sm, 0], src[sm, 2]), 90))
        if m.any():
            pp = np.concatenate([a[m], b[m], c[m]])
            rad = float(np.percentile(np.hypot(pp[:, 0], pp[:, 2]), 90))
        else:
            rad = 0.0
        flag = ""
        if not m.any():
            flag, _ = "  <== EMPTY", bad.append(f"y {lo:.1f}-{hi:.1f} has no triangles")
        elif rad < s_rad * 0.55:
            flag, _ = "  <== PINCHED", bad.append(
                f"y {lo:.1f}-{hi:.1f} radius {rad:.2f} vs source {s_rad:.2f}"
            )
        print(f"  y {lo:5.1f}-{hi:5.1f}: tris={int(m.sum()):5d} "
              f"r={rad:5.2f} (src {s_rad:5.2f}){flag}")
    if bad:
        raise SystemExit("BAKE REJECTED - the post is not whole:\n  " + "\n  ".join(bad))
    print("verify: post is whole (every source band survives)")


if __name__ == "__main__":
    main()
