#!/usr/bin/env python3
"""Fetch CC0 textures from Poly Haven and grade them for Terrarium's shaders.

Poly Haven ships every texture as CC0 (public domain, https://polyhaven.com/license),
which is why it is the only photo source in this repo.  This tool is the permanent
replacement for the throwaway script that produced `assets/stone/` -- the crypt's
surfaces were graded by hand once and the recipe was lost, so anything shipped from
here on must be reproducible by re-running a recorded command line.

    THE 403 TRAP
    ------------
    api.polyhaven.com and dl.polyhaven.org both answer HTTP 403 to a request that
    carries urllib's default `Python-urllib/3.x` User-Agent.  Every request this
    tool makes therefore sets a browser User-Agent (see BROWSER_UA).  If you write
    another script against this API, copy that header or you will spend an hour
    thinking the asset id is wrong.

WHY THE GRADING LOOKS THE WAY IT DOES
-------------------------------------
Terrarium's scene shader multiplies each albedo by a constant that brings the
texture's mean back to unity, so the photo carries the DETAIL and the geometry's
own light carries the TONE.  A photo dropped in raw therefore double-darkens the
surface it is painted on.  The pipeline below exists to hand the shader a texture
whose mean is a known number, so the shader author can hardcode 1/mean:

    resize -> desaturate -> tint -> flatten contrast -> anti-clip guard
           -> multiplicative mean normalisation -> anti-clip guard -> encode

Both guards only ever SHRINK deviations around the mean, so the mean survives the
normalisation exactly and no texel is crushed to 0 or blown to 255.  The mean this
tool reports is measured back off the encoded file, not off the float buffer, so
it is the number the game will actually sample.

Means are the plain mean of all RGB samples in stored (sRGB-encoded) 0..1 space --
the same convention `assets/stone/README.md` used when it recorded 1.94 and 2.2.

NORMAL MAPS
-----------
Terrarium is DirectX convention (green down), like the crypt's `_n` files.  Poly
Haven publishes `nor_dx` and `nor_gl`; this tool takes `nor_dx` and says so.  If an
asset only has `nor_gl` it flips the green channel and prints a loud note, which
belongs in the README of whatever it produced.  Normals are never desaturated,
tinted or mean-normalised; they are only resized and re-normalised to unit length
(bilinear/Lanczos resampling denormalises the vectors).

Check the channel means the report prints: a flat surface should bake to R=G=0.5.
Some Poly Haven normals carry the tilt of the panel the photo was shot off and sit
well off that (floor_tiles_08 is at R=0.603 G=0.399, a 16.7 deg lean, in nor_dx and
nor_gl alike, while its own displacement map is level).  On a tiled floor that reads
as the whole floor being on a slope; `--normal-recenter` pulls the mean tangent
vector back to straight up and leaves the per-texel relief alone.

USAGE
-----
    # find something
    python tools/prep_polyhaven.py list --search tile --search floor
    python tools/prep_polyhaven.py info floor_tiles_08

    # grade it (writes floor_tile.jpg + floor_tile_n.jpg + floor_tile_h.png)
    python tools/prep_polyhaven.py grade floor_tiles_08 \
        --out assets/shop/floor_tile.jpg \
        --res 1k --size 1024 --desaturate 0.8 --contrast 0.75 \
        --target-mean 0.60 --height

Re-running the same command reproduces the shipped bytes: the source files are
content-addressed by Poly Haven, the grade is pure arithmetic and the encoder
settings are pinned.  Downloads are cached under the system temp dir so a repeat
run is offline.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
import time
import urllib.request

import numpy as np
from PIL import Image

# --------------------------------------------------------------------------- #
# API
# --------------------------------------------------------------------------- #

API = "https://api.polyhaven.com"

# Required.  Without it the API and the CDN both answer 403.  See module docstring.
BROWSER_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"

# Poly Haven's whole library is CC0.  The JSON payload carries no per-asset
# `license` key, so this is asserted from the site licence, not read back.
LICENSE = "CC0 1.0 (public domain) -- https://polyhaven.com/license"

INDEX_TTL = 24 * 3600  # seconds before the cached asset list is refetched


def cache_root(explicit: str | None = None) -> str:
    path = explicit or os.path.join(tempfile.gettempdir(), "polyhaven_cache")
    os.makedirs(path, exist_ok=True)
    return path


def _fetch(url: str, timeout: int = 120) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": BROWSER_UA})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def get_json(url: str) -> dict:
    return json.loads(_fetch(url).decode("utf-8"))


def asset_index(cache: str, refresh: bool = False) -> dict:
    """The full texture list, cached on disk for INDEX_TTL."""
    path = os.path.join(cache, "assets_textures.json")
    fresh = os.path.exists(path) and (time.time() - os.path.getmtime(path)) < INDEX_TTL
    if fresh and not refresh:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    data = get_json(API + "/assets?t=textures")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh)
    return data


def asset_files(asset_id: str, cache: str) -> dict:
    """The per-asset map/resolution/format tree, cached on disk forever."""
    path = os.path.join(cache, "files_%s.json" % asset_id)
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    data = get_json(API + "/files/" + asset_id)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh)
    return data


def pick_map(files: dict, *names: str) -> tuple[str, dict] | tuple[None, None]:
    """First matching top-level map key, case-insensitively.

    Poly Haven is inconsistent about capitals: `Diffuse` on some assets, `diffuse`
    on others, `Displacement` vs `disp`.  Never index the tree with a literal.
    """
    lowered = {k.lower(): k for k in files}
    for name in names:
        key = lowered.get(name.lower())
        if key is not None:
            return key, files[key]
    return None, None


def download_map(asset_id: str, files: dict, map_names: tuple[str, ...],
                 res: str, fmt: str, cache: str) -> tuple[str, str]:
    """Download one map to the cache.  Returns (local path, the map key used)."""
    key, tree = pick_map(files, *map_names)
    if key is None:
        raise SystemExit("%s has no %s map (has: %s)"
                         % (asset_id, "/".join(map_names), ", ".join(sorted(files))))
    if res not in tree:
        raise SystemExit("%s %s has no %s resolution (has: %s)"
                         % (asset_id, key, res, ", ".join(sorted(tree))))
    if fmt not in tree[res]:
        raise SystemExit("%s %s %s has no %s format (has: %s)"
                         % (asset_id, key, res, fmt, ", ".join(sorted(tree[res]))))
    entry = tree[res][fmt]
    url = entry["url"]
    dest_dir = os.path.join(cache, asset_id)
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, os.path.basename(url))
    if not os.path.exists(dest) or os.path.getsize(dest) != entry.get("size", -1):
        sys.stderr.write("  downloading %s (%s)\n" % (os.path.basename(url), _human(entry.get("size", 0))))
        blob = _fetch(url)
        with open(dest, "wb") as fh:
            fh.write(blob)
    return dest, key


def _human(n: int) -> str:
    for unit in ("B", "KB", "MB"):
        if n < 1024 or unit == "MB":
            return "%.0f %s" % (n, unit) if unit == "B" else "%.1f %s" % (n, unit)
        n /= 1024.0
    return str(n)


# --------------------------------------------------------------------------- #
# Grading
# --------------------------------------------------------------------------- #

LUMA = np.array([0.2126, 0.7152, 0.0722], dtype=np.float64)


def load_rgb(path: str, size: int | None) -> np.ndarray:
    """sRGB image as float64 HxWx3 in 0..1, optionally resized."""
    im = Image.open(path).convert("RGB")
    if size and im.size != (size, size):
        im = im.resize((size, size), Image.Resampling.LANCZOS)
    return np.asarray(im, dtype=np.float64) / 255.0


def desaturate(rgb: np.ndarray, amount: float) -> np.ndarray:
    """Pull `amount` of the chroma out toward the pixel's own luma."""
    if amount <= 0:
        return rgb
    grey = (rgb * LUMA).sum(axis=2, keepdims=True)
    return rgb * (1.0 - amount) + grey * amount


def tint(rgb: np.ndarray, t: float) -> np.ndarray:
    """Signed warm/cool cast: positive lifts red and drops blue, negative reverses.

    Green is left alone so the cast reads as temperature rather than as a hue
    rotation.  Magnitudes here are meant to be small (0.02-0.06); anything bigger
    stops looking like fluorescent light and starts looking like a colour filter.
    """
    if t == 0:
        return rgb
    gains = np.array([1.0 + t, 1.0, 1.0 - t], dtype=np.float64)
    return rgb * gains


def flatten(rgb: np.ndarray, contrast: float) -> np.ndarray:
    """Scale each channel's deviation from ITS OWN mean by `contrast`.

    Per-channel, not about the grand mean: a wood photo's red channel sits a third
    of the range above its blue one, and scaling about the grand mean would treat
    that colour cast as contrast -- so raising the knob to recover grain would drag
    the cast back up with it, undoing the desaturation.  Per-channel keeps the two
    knobs orthogonal: `--desaturate` owns the cast, `--contrast` owns the detail.
    """
    if contrast == 1.0:
        return rgb
    m = rgb.mean(axis=(0, 1), keepdims=True)
    return m + (rgb - m) * contrast


def guard(rgb: np.ndarray, floor: float, ceil: float, pivot: float | None = None) -> np.ndarray:
    """Shrink deviations about `pivot` just enough that nothing clips.

    Only ever shrinks, and shrinking about the mean leaves the mean untouched --
    which is what lets the mean normalisation below stay exact.
    """
    m = rgb.mean() if pivot is None else pivot
    lo, hi = rgb.min(), rgb.max()
    s = 1.0
    if lo < floor and m > lo:
        s = min(s, (m - floor) / (m - lo))
    if hi > ceil and hi > m:
        s = min(s, (ceil - m) / (hi - m))
    if s >= 1.0:
        return rgb
    return m + (rgb - m) * s


def normalise_mean(rgb: np.ndarray, target: float) -> np.ndarray:
    """Multiplicative -- an albedo scales, it does not offset."""
    m = rgb.mean()
    if m <= 0:
        return rgb
    return rgb * (target / m)


def grade_albedo(path: str, args) -> np.ndarray:
    rgb = load_rgb(path, args.size)
    rgb = desaturate(rgb, args.desaturate)
    rgb = tint(rgb, args.tint)
    rgb = flatten(rgb, args.contrast)
    rgb = guard(rgb, args.floor, args.ceil)
    if args.target_mean is not None:
        rgb = normalise_mean(rgb, args.target_mean)
        rgb = guard(rgb, args.floor, args.ceil, pivot=args.target_mean)
    return np.clip(rgb, 0.0, 1.0)


def save_jpeg(rgb: np.ndarray, path: str, quality: int) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    arr = np.rint(rgb * 255.0).astype(np.uint8)
    Image.fromarray(arr, "RGB").save(path, "JPEG", quality=quality, subsampling=0,
                                     optimize=True, progressive=False)


def measure(path: str) -> dict:
    """Read a written file back and report what the shader will see."""
    im = Image.open(path).convert("RGB")
    a = np.asarray(im, dtype=np.float64) / 255.0
    mean = float(a.mean())
    mx = a.reshape(-1, 3).max(axis=1)
    mn = a.reshape(-1, 3).min(axis=1)
    sat = float(np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-9), 0.0).mean())
    raw = np.asarray(im)
    return {
        "path": path,
        "size": im.size,
        "bytes": os.path.getsize(path),
        "mean": mean,
        "multiplier": (1.0 / mean) if mean > 0 else float("inf"),
        "saturation": sat,
        "rgb": (float(a[..., 0].mean()), float(a[..., 1].mean()), float(a[..., 2].mean())),
        "min": int(raw.min()),
        "max": int(raw.max()),
        "clipped_low": float((raw == 0).mean()),
        "clipped_high": float((raw == 255).mean()),
    }


# --------------------------------------------------------------------------- #
# Normals and height
# --------------------------------------------------------------------------- #

def grade_normal(path: str, size: int | None, flip_green: bool, strength: float,
                 recenter: bool = False) -> np.ndarray:
    rgb = load_rgb(path, size)
    v = rgb * 2.0 - 1.0
    if flip_green:
        v[..., 1] = -v[..., 1]
    if recenter:
        # Some Poly Haven bakes carry the tilt of the physical panel the photo was
        # shot off: every texel of an otherwise flat surface leans the same way
        # (floor_tiles_08 leans 16.7 deg, in BOTH nor_dx and nor_gl, while its own
        # displacement map is level -- so it is the normal bake that is wrong).
        # On a tiled floor that reads as the whole floor being on a slope.  Pull
        # the mean tangent vector back to straight up; per-texel relief survives.
        v[..., 0] -= v[..., 0].mean()
        v[..., 1] -= v[..., 1].mean()
    if strength != 1.0:
        v[..., 0] *= strength
        v[..., 1] *= strength
    # Resampling denormalises; put the vectors back on the unit sphere.
    n = np.sqrt((v * v).sum(axis=2, keepdims=True))
    v = v / np.maximum(n, 1e-9)
    v[..., 2] = np.abs(v[..., 2])  # tangent space: Z always points out of the surface
    return np.clip(v * 0.5 + 0.5, 0.0, 1.0)


def grade_height(path: str, size: int | None, stretch: bool) -> np.ndarray:
    im = Image.open(path)
    a = np.asarray(im).astype(np.float64)
    if a.ndim == 3:
        a = a[..., :3].mean(axis=2)
    peak = 65535.0 if a.max() > 255.0 else 255.0
    a = a / peak
    if size and a.shape[0] != size:
        a = np.asarray(
            Image.fromarray(np.clip(a * 65535.0, 0, 65535).astype(np.uint16))
            .resize((size, size), Image.Resampling.LANCZOS),
            dtype=np.float64,
        ) / 65535.0
    if stretch:
        lo, hi = a.min(), a.max()
        if hi > lo:
            a = (a - lo) / (hi - lo)
    return np.clip(a, 0.0, 1.0)


def save_png_l(a: np.ndarray, path: str) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    Image.fromarray(np.rint(a * 255.0).astype(np.uint8), "L").save(path, "PNG", optimize=True)


# --------------------------------------------------------------------------- #
# Commands
# --------------------------------------------------------------------------- #

def cmd_list(args) -> int:
    cache = cache_root(args.cache)
    index = asset_index(cache, refresh=args.refresh)
    terms = [t.lower() for t in (args.search or [])]
    rows = []
    for aid, a in index.items():
        hay = " ".join([
            aid, a.get("name", ""),
            " ".join(a.get("tags", []) or []),
            " ".join(a.get("categories", []) or []),
            a.get("category", "") or "",
        ]).lower()
        if all(t in hay for t in terms):
            rows.append((aid, a))
    rows.sort(key=lambda r: -(r[1].get("download_count") or 0))
    if args.json:
        print(json.dumps({aid: a for aid, a in rows[: args.limit]}, indent=1))
        return 0
    print("%d match(es), %d textures in the index" % (len(rows), len(index)))
    for aid, a in rows[: args.limit]:
        print("  %-34s %-30s %s" % (aid, a.get("name", "")[:30],
                                    ",".join((a.get("categories") or [])[:5])))
        if args.tags:
            print("      tags: %s" % ", ".join((a.get("tags") or [])[:14]))
    return 0


def cmd_info(args) -> int:
    cache = cache_root(args.cache)
    index = asset_index(cache)
    meta = index.get(args.asset_id, {})
    files = asset_files(args.asset_id, cache)
    print("%s -- %s" % (args.asset_id, meta.get("name", "?")))
    print("  licence   : %s" % LICENSE)
    print("  authors   : %s" % ", ".join(sorted(meta.get("authors", {}) or {})))
    print("  categories: %s" % ", ".join(meta.get("categories", []) or []))
    print("  tags      : %s" % ", ".join(meta.get("tags", []) or []))
    print("  max res   : %s" % (meta.get("max_resolution") or "?"))
    print("  maps:")
    for key in sorted(files):
        tree = files[key]
        if not isinstance(tree, dict):
            continue
        res = sorted(tree)
        fmts = sorted(tree[res[0]]) if res and isinstance(tree[res[0]], dict) else []
        print("    %-14s res=%s fmt=%s" % (key, ",".join(res), ",".join(fmts)))
    return 0


def cmd_grade(args) -> int:
    cache = cache_root(args.cache)
    files = asset_files(args.asset_id, cache)
    index = asset_index(cache)
    meta = index.get(args.asset_id, {})

    stem, _ = os.path.splitext(args.out)
    report = []

    print("%s (%s)" % (args.asset_id, meta.get("name", "?")))
    print("  licence: %s" % LICENSE)

    # albedo -------------------------------------------------------------
    src, key = download_map(args.asset_id, files, ("Diffuse", "diffuse", "diff", "col"),
                            args.res, "jpg", cache)
    if args.dry_run:
        print("  [dry-run] would grade %s -> %s" % (key, args.out))
    else:
        save_jpeg(grade_albedo(src, args), args.out, args.quality)
        report.append(("albedo (%s)" % key, measure(args.out)))

    # normal -------------------------------------------------------------
    if args.normal:
        nkey, _ = pick_map(files, "nor_dx")
        flip = False
        if nkey is None or args.gl_normal:
            nkey, _ = pick_map(files, "nor_gl")
            flip = nkey is not None
            if flip:
                print("  NOTE: no nor_dx (or --gl-normal given) -- using nor_gl and "
                      "FLIPPING GREEN to DirectX. Record this in the README.")
        if nkey is None:
            print("  WARNING: asset has no normal map; skipping _n")
        else:
            nsrc, _ = download_map(args.asset_id, files, (nkey,), args.res, "jpg", cache)
            if args.dry_run:
                print("  [dry-run] would grade %s -> %s_n.jpg" % (nkey, stem))
            else:
                out_n = stem + "_n.jpg"
                save_jpeg(grade_normal(nsrc, args.normal_size or args.size, flip,
                                       args.normal_strength, args.normal_recenter),
                          out_n, args.normal_quality)
                report.append(("normal (%s%s)" % (nkey, ", green flipped" if flip else ""),
                               measure(out_n)))

    # height -------------------------------------------------------------
    if args.height:
        hkey, _ = pick_map(files, "Displacement", "displacement", "disp", "Height", "height", "bump")
        if hkey is None:
            print("  WARNING: asset has no displacement map; skipping _h")
        else:
            hsrc, _ = download_map(args.asset_id, files, (hkey,), args.res, "png", cache)
            if args.dry_run:
                print("  [dry-run] would grade %s -> %s_h.png" % (hkey, stem))
            else:
                out_h = stem + "_h.png"
                save_png_l(grade_height(hsrc, args.height_size or args.size, args.height_stretch),
                           out_h)
                im = Image.open(out_h)
                a = np.asarray(im)
                report.append(("height (%s, 8-bit L)" % hkey, {
                    "path": out_h, "size": im.size, "bytes": os.path.getsize(out_h),
                    "mean": float(a.mean()) / 255.0, "multiplier": float("nan"),
                    "saturation": 0.0, "min": int(a.min()), "max": int(a.max()),
                    "clipped_low": float((a == 0).mean()), "clipped_high": float((a == 255).mean()),
                }))

    for label, m in report:
        print("  %-30s %s" % (label, os.path.basename(m["path"])))
        print("      %dx%d  %s  min=%d max=%d  clip lo=%.4f%% hi=%.4f%%"
              % (m["size"][0], m["size"][1], _human(m["bytes"]), m["min"], m["max"],
                 m["clipped_low"] * 100.0, m["clipped_high"] * 100.0))
        if label.startswith("albedo"):
            print("      mean=%.4f  ->  SHADER MULTIPLIER %.3f   mean saturation=%.4f"
                  % (m["mean"], m["multiplier"], m["saturation"]))
            print("      channel means R=%.4f G=%.4f B=%.4f  (%s cast)"
                  % (m["rgb"][0], m["rgb"][1], m["rgb"][2],
                     "warm" if m["rgb"][0] > m["rgb"][2] else
                     "cool" if m["rgb"][2] > m["rgb"][0] else "neutral"))
        elif label.startswith("normal"):
            lean = np.degrees(np.arccos(np.clip(np.sqrt(max(0.0, 1.0
                   - (2 * m["rgb"][0] - 1) ** 2 - (2 * m["rgb"][1] - 1) ** 2)), -1, 1)))
            print("      channel means R=%.4f G=%.4f B=%.4f  (flat is 0.5/0.5/1.0; "
                  "mean normal leans %.1f deg)" % (m["rgb"][0], m["rgb"][1], m["rgb"][2], lean))
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="prep_polyhaven.py",
        description="Fetch CC0 Poly Haven textures and grade them for Terrarium.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="All requests carry a browser User-Agent; Poly Haven answers 403 without one.",
    )
    p.add_argument("--cache", help="download cache dir (default: <temp>/polyhaven_cache)")
    sub = p.add_subparsers(dest="cmd", required=True)

    lp = sub.add_parser("list", help="search the texture index")
    lp.add_argument("--search", action="append", help="substring that must appear (repeatable, ANDed)")
    lp.add_argument("--limit", type=int, default=40)
    lp.add_argument("--tags", action="store_true", help="also print each asset's tags")
    lp.add_argument("--json", action="store_true")
    lp.add_argument("--refresh", action="store_true", help="refetch the index")
    lp.set_defaults(func=cmd_list)

    ip = sub.add_parser("info", help="show one asset's maps, resolutions and formats")
    ip.add_argument("asset_id")
    ip.set_defaults(func=cmd_info)

    gp = sub.add_parser("grade", help="download an asset and write graded albedo/_n/_h")
    gp.add_argument("asset_id")
    gp.add_argument("--out", required=True, help="albedo path; _n.jpg and _h.png share its stem")
    gp.add_argument("--res", default="1k", help="source resolution to download (default 1k)")
    gp.add_argument("--size", type=int, default=None, help="output edge in px (default: source)")
    gp.add_argument("--desaturate", type=float, default=0.0,
                    help="0..1 fraction of chroma removed (default 0)")
    gp.add_argument("--tint", type=float, default=0.0,
                    help="signed warm(+)/cool(-) R-B split, e.g. 0.03 (default 0)")
    gp.add_argument("--contrast", type=float, default=1.0,
                    help="scale of every deviation from the mean; <1 flattens (default 1)")
    gp.add_argument("--target-mean", type=float, default=None,
                    help="final RGB mean in 0..1; the shader multiplier is 1/this")
    gp.add_argument("--floor", type=float, default=0.02, help="anti-clip lower bound (default 0.02)")
    gp.add_argument("--ceil", type=float, default=0.98, help="anti-clip upper bound (default 0.98)")
    gp.add_argument("--quality", type=int, default=90, help="albedo JPEG quality (default 90)")
    gp.add_argument("--no-normal", dest="normal", action="store_false", help="skip the _n map")
    gp.add_argument("--normal-quality", type=int, default=92, help="normal JPEG quality (default 92)")
    gp.add_argument("--normal-size", type=int, default=None, help="normal edge (default: --size)")
    gp.add_argument("--normal-strength", type=float, default=1.0, help="XY gain before renormalising")
    gp.add_argument("--normal-recenter", action="store_true",
                    help="pull the mean tangent vector back to straight up; use when a bake "
                         "leans (check `info`-time channel means: flat should be R=G=0.5)")
    gp.add_argument("--gl-normal", action="store_true",
                    help="force nor_gl and flip green (only if nor_dx is missing or wrong)")
    gp.add_argument("--height", action="store_true", help="also write the 8-bit _h.png")
    gp.add_argument("--height-size", type=int, default=None, help="height edge (default: --size)")
    gp.add_argument("--height-stretch", action="store_true",
                    help="stretch the height range to full 0..255 (off by default)")
    gp.add_argument("--dry-run", action="store_true")
    gp.set_defaults(func=cmd_grade, normal=True)
    return p


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
