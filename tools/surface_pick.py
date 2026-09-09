#!/usr/bin/env python3
"""Choose a Poly Haven surface, grade a BRIGHT one, and check that it modulates.

Three jobs `prep_polyhaven.py` does not do, each of which cost this build a round:

`cats` / `show` -- CHOOSING.  `prep_polyhaven.py list --search` matches one flat
haystack (id + name + tags + categories), which finds an asset but cannot rank
twenty of them.  The cached index also carries a `category` PATH ("Wood/Veneer/
Light Hardwood Veneer"), prose `description` and `dimensions` in millimetres:

  * the category path is the library's own taxonomy, and listing a whole leaf is
    how you learn a leaf DOES NOT EXIST -- there is no acoustic-ceiling and no
    brushed-metal leaf in the 857 textures, which no keyword search can prove;
  * `dimensions` decides whether a photograph reads as a surface or as noise.
    A 1500 mm cycle across a 1 m gondola shows two thirds of a pattern; a 300 mm
    one shows three and a half and turns to grain.

`depth` -- CHECKING.  Terrarium's shader divides every albedo by its own mean, so
the only thing a photograph contributes is its RELATIVE spread.  Absolute sd is
therefore the wrong number to grade against, and mean is a red herring: two files
at 0.58 and 0.78 are the same picture once the shader is done with them.

    relative sd = sd(luma) / mean(luma)

The Mart's shipped set, measured, against what the probe frame shows:

    floor_tile   0.105   the ONLY surface whose texture is visible in a frame
    metal_shelf  0.056   reads, just
    counter_wood 0.033   reads as flat
    wall_paint   0.014   reads as white plastic

and the room's own exposure is why: sampling `probe_out_shop/shop_room.png`, the
back wall sits at mean 250/255 with sd 7.8, so a 1.4% modulation is +/-3 levels
under a surface that is already clipping.  **Target 0.07-0.10 relative sd** for
anything that has to read in that room.

`grade` -- GRADING A BRIGHT PHOTOGRAPH.  `prep_polyhaven.py` flattens contrast
BEFORE it normalises the mean, and its anti-clip guard is symmetric about the
current mean.  A photograph of a white material arrives with a mean near the
ceiling -- polystyrene at 0.868, white maple veneer at 0.835 -- so there are only
0.11-0.15 of headroom above it and 0.85 below, the guard shrinks the whole image
to fit the side that has none, and `--contrast` SATURATES:

    polystyrene, shipped order, --contrast 3 -> rel sd 0.0158
    polystyrene, shipped order, --contrast 8 -> rel sd 0.0160   (no change)

That cap is a property of the source's brightness, not of the knob, and 0.016 is
the wall's number -- the surface would ship reading as flat white plastic.  This
`grade` normalises the mean to the target FIRST, so the guard's headroom is
symmetric, and only then flattens:

    resize -> desaturate -> tint -> MEAN NORMALISE -> flatten -> anti-clip guard

`flatten` scales each channel about its own mean and the guard pivots on the
target, so the mean still survives exactly and the reported multiplier is still
1/mean.  Same arithmetic, same encoder, one step moved:

    polystyrene, this order, --contrast 3 -> rel sd 0.0588, and still climbing

Use `prep_polyhaven.py` for anything darker than about 0.7; it is the reference
implementation and its four shipped surfaces are all below that.  Normals and
height maps are not touched here -- they are `prep_polyhaven.py`'s functions,
imported and called unchanged.

    python tools/surface_pick.py cats --grep veneer
    python tools/surface_pick.py show --cat "Wood/Veneer/Light Hardwood"
    python tools/surface_pick.py grade polystyrene --out assets/shop/plastic_scuff.jpg \
        --res 1k --size 512 --desaturate 0.90 --contrast 5.0 --target-mean 0.60
    python tools/surface_pick.py depth "assets/shop/*.jpg"
    python tools/surface_pick.py frame probe_out_shop/shop_room.png

`cats`/`show` need the index `prep_polyhaven.py` cached; `depth`/`frame` need
only the files and write nothing.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import tempfile
from collections import Counter

import numpy as np
from PIL import Image


# --------------------------------------------------------------------------- #
# Choosing
# --------------------------------------------------------------------------- #

def load_index(cache: str | None) -> dict:
    root = cache or os.path.join(tempfile.gettempdir(), "polyhaven_cache")
    path = os.path.join(root, "assets_textures.json")
    if not os.path.exists(path):
        raise SystemExit("no cached index at %s -- run "
                         "`python tools/prep_polyhaven.py list` first" % path)
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def _ascii(s: str) -> str:
    """Poly Haven's prose carries U+2011 non-breaking hyphens; a Windows console
    is cp1252 and raises on them halfway through a listing."""
    return s.encode("ascii", "replace").decode("ascii")


def _dims(a: dict) -> str:
    d = a.get("dimensions") or []
    return "%.0fx%.0f mm" % (d[0], d[1]) if len(d) == 2 else "?"


def cmd_cats(args) -> int:
    counts = Counter(a.get("category", "?") for a in load_index(args.cache).values())
    needle = (args.grep or "").lower()
    for cat, n in sorted(counts.items()):
        if needle in cat.lower():
            print("%4d  %s" % (n, cat))
    return 0


def cmd_show(args) -> int:
    index = load_index(args.cache)
    if not args.cat and not args.id:
        raise SystemExit("give --cat and/or --id")
    rows = []
    for aid, a in index.items():
        cat = a.get("category", "") or ""
        # --cat and --id are ORed, not ANDed: the usual call is "this whole leaf
        # PLUS the two strays keyword search turned up", and ANDing returns none.
        hit = bool(args.cat) and any(c.lower() in cat.lower() for c in args.cat)
        hit = hit or (bool(args.id) and aid in args.id)
        if hit:
            rows.append((aid, a))
    rows.sort(key=lambda r: -(r[1].get("download_count") or 0))
    for aid, a in rows:
        print("%s  --  %s" % (aid, _ascii(a.get("name", "?"))))
        print("   %-38s %s   %s" % (a.get("category", "?"), _dims(a),
                                    (a.get("max_resolution") or ["?"])[0]))
        tags = _ascii(", ".join((a.get("tags") or [])[:16]))
        if tags:
            print("   tags: %s" % tags)
        desc = _ascii((a.get("description") or "").strip().replace("\n", " "))
        if desc:
            print("   %s" % desc[: args.width])
        if args.attrs and a.get("attributes"):
            print("   attrs: %s" % _ascii(json.dumps(a["attributes"]))[: args.width])
        print()
    print("%d asset(s)" % len(rows))
    return 0


# --------------------------------------------------------------------------- #
# Checking
# --------------------------------------------------------------------------- #

def depth_of(path: str) -> dict:
    a = np.asarray(Image.open(path).convert("RGB"), dtype=np.float64) / 255.0
    luma = a.mean(axis=2)
    mean = float(luma.mean())
    rel = luma / max(mean, 1e-9)
    raw = np.asarray(Image.open(path).convert("RGB"))
    return {
        "mean": float(a.mean()),
        "mult": 1.0 / max(float(a.mean()), 1e-9),
        "rel_sd": float(rel.std()),
        "rel_p1": float(np.percentile(rel, 1)),
        "rel_p99": float(np.percentile(rel, 99)),
        "rb": float(a[..., 0].mean() - a[..., 2].mean()),
        "min": int(raw.min()), "max": int(raw.max()),
        "size": Image.open(path).size, "bytes": os.path.getsize(path),
    }


VERDICT = ((0.070, "reads"), (0.045, "marginal"), (0.0, "FLAT -- will read as plastic"))


def cmd_depth(args) -> int:
    paths = []
    for pat in args.paths:
        paths.extend(sorted(glob.glob(pat)) or [pat])
    print("%-22s %6s %7s %8s %14s %8s  %s"
          % ("file", "mean", "mult", "rel sd", "rel p1..p99", "R-B", "verdict"))
    for p in paths:
        is_normal = p.endswith(("_n.jpg", "_n.png"))
        if is_normal and not args.normals:
            continue  # a normal map's spread means nothing here
        d = depth_of(p)
        # ...and it still means nothing with --normals, which is for reading the
        # channel means (flat is 0.5/0.5/1.0), so do not print a verdict on one.
        verdict = "(normal map -- verdict N/A)" if is_normal else \
            next(v for t, v in VERDICT if d["rel_sd"] >= t)
        print("%-22s %6.3f %7.3f %8.4f  %5.3f..%5.3f %+8.4f  %s"
              % (os.path.basename(p), d["mean"], d["mult"], d["rel_sd"],
                 d["rel_p1"], d["rel_p99"], d["rb"], verdict))
    return 0


def cmd_frame(args) -> int:
    """What a rendered frame says about whether any of it survived."""
    a = np.asarray(Image.open(args.frame).convert("RGB"), dtype=np.float64)
    luma = a.mean(axis=2)
    lit = luma[luma > 24]  # drop the letterbox and the void
    print("%s  %dx%d" % (args.frame, a.shape[1], a.shape[0]))
    print("  lit pixels     : %.1f%% of frame" % (100.0 * lit.size / luma.size))
    print("  lit mean/sd    : %.1f / %.1f" % (lit.mean(), lit.std()))
    print("  at 255 (clipped): %.2f%% of lit" % (100.0 * (lit >= 254.5).mean()))
    print("  p50/p90/p99    : %.0f / %.0f / %.0f"
          % (np.percentile(lit, 50), np.percentile(lit, 90), np.percentile(lit, 99)))
    print("  warm cast R-B  : %+.1f levels" % (a[..., 0].mean() - a[..., 2].mean()))
    return 0


# --------------------------------------------------------------------------- #
# Grading a bright photograph
# --------------------------------------------------------------------------- #

def grade_albedo_bright(path: str, args) -> "np.ndarray":
    """`prep_polyhaven.grade_albedo` with the mean normalisation moved in front of
    the contrast flatten.  See the module docstring for the measurement that made
    this necessary; every step is prep_polyhaven's own function."""
    import prep_polyhaven as ph

    rgb = ph.load_rgb(path, args.size)
    rgb = ph.desaturate(rgb, args.desaturate)
    rgb = ph.tint(rgb, args.tint)
    if args.target_mean is None:
        raise SystemExit("--target-mean is required here: normalising first is "
                         "the whole point of this grader")
    rgb = ph.normalise_mean(rgb, args.target_mean)
    rgb = ph.flatten(rgb, args.contrast)
    # One guard, pivoting on the target: `flatten` preserves each channel's mean
    # and `guard` only shrinks about the pivot, so the mean lands on the target
    # exactly and the reported multiplier stays 1/target.
    rgb = ph.guard(rgb, args.floor, args.ceil, pivot=args.target_mean)
    return np.clip(rgb, 0.0, 1.0)


def cmd_grade(args) -> int:
    import sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import prep_polyhaven as ph

    cache = ph.cache_root(args.cache)
    files = ph.asset_files(args.asset_id, cache)
    meta = ph.asset_index(cache).get(args.asset_id, {})
    stem, _ = os.path.splitext(args.out)
    report = []

    print("%s (%s)" % (args.asset_id, meta.get("name", "?")))
    print("  licence: %s" % ph.LICENSE)
    print("  grader : surface_pick (mean normalised BEFORE contrast)")

    src, key = ph.download_map(args.asset_id, files,
                               ("Diffuse", "diffuse", "diff", "col"), args.res, "jpg", cache)
    ph.save_jpeg(grade_albedo_bright(src, args), args.out, args.quality)
    report.append(("albedo (%s)" % key, ph.measure(args.out)))

    if args.normal:
        nkey, _ = ph.pick_map(files, "nor_dx")
        flip = False
        if nkey is None or args.gl_normal:
            nkey, _ = ph.pick_map(files, "nor_gl")
            flip = nkey is not None
            if flip:
                print("  NOTE: no nor_dx -- using nor_gl and FLIPPING GREEN to "
                      "DirectX. Record this in the README.")
        if nkey is None:
            print("  WARNING: asset has no normal map; skipping _n")
        else:
            nsrc, _ = ph.download_map(args.asset_id, files, (nkey,), args.res, "jpg", cache)
            out_n = stem + "_n.jpg"
            ph.save_jpeg(ph.grade_normal(nsrc, args.normal_size or args.size, flip,
                                         args.normal_strength, args.normal_recenter),
                         out_n, args.normal_quality)
            report.append(("normal (%s%s)" % (nkey, ", green flipped" if flip else ""),
                           ph.measure(out_n)))

    for label, m in report:
        print("  %-30s %s" % (label, os.path.basename(m["path"])))
        print("      %dx%d  %d B  min=%d max=%d  clip lo=%.4f%% hi=%.4f%%"
              % (m["size"][0], m["size"][1], m["bytes"], m["min"], m["max"],
                 m["clipped_low"] * 100.0, m["clipped_high"] * 100.0))
        if label.startswith("albedo"):
            d = depth_of(m["path"])
            print("      mean=%.4f  ->  SHADER MULTIPLIER %.3f   mean saturation=%.4f"
                  % (m["mean"], m["multiplier"], m["saturation"]))
            print("      channel means R=%.4f G=%.4f B=%.4f  (R-B %+0.4f)"
                  % (m["rgb"][0], m["rgb"][1], m["rgb"][2], d["rb"]))
            print("      RELATIVE sd=%.4f  (%s)"
                  % (d["rel_sd"], next(v for t, v in VERDICT if d["rel_sd"] >= t)))
        else:
            lean = np.degrees(np.arccos(np.clip(np.sqrt(max(0.0, 1.0
                   - (2 * m["rgb"][0] - 1) ** 2 - (2 * m["rgb"][1] - 1) ** 2)), -1, 1)))
            print("      channel means R=%.4f G=%.4f B=%.4f  (flat is 0.5/0.5/1.0; "
                  "mean normal leans %.1f deg)" % (m["rgb"][0], m["rgb"][1], m["rgb"][2], lean))
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="surface_pick.py",
                                description=__doc__.split("\n")[0])
    p.add_argument("--cache", help="cache dir (default: <temp>/polyhaven_cache)")
    sub = p.add_subparsers(dest="cmd", required=True)

    cp = sub.add_parser("cats", help="the library's own category tree, with counts")
    cp.add_argument("--grep", help="substring the category path must contain")
    cp.set_defaults(func=cmd_cats)

    sp = sub.add_parser("show", help="descriptions and real sizes for a leaf or some ids")
    sp.add_argument("--cat", action="append", help="category substring (repeatable, ORed)")
    sp.add_argument("--id", action="append", help="asset id (repeatable, ORed with --cat)")
    sp.add_argument("--width", type=int, default=200, help="truncate prose at N chars")
    sp.add_argument("--attrs", action="store_true")
    sp.set_defaults(func=cmd_show)

    dp = sub.add_parser("depth", help="relative sd of graded albedos -- will they read?")
    dp.add_argument("paths", nargs="+", help="albedo files or globs")
    dp.add_argument("--normals", action="store_true", help="do not skip _n maps")
    dp.set_defaults(func=cmd_depth)

    fp = sub.add_parser("frame", help="exposure of a rendered probe frame")
    fp.add_argument("frame")
    fp.set_defaults(func=cmd_frame)

    gp = sub.add_parser("grade", help="grade a BRIGHT asset (mean normalised before contrast)")
    gp.add_argument("asset_id")
    gp.add_argument("--out", required=True, help="albedo path; _n.jpg shares its stem")
    gp.add_argument("--res", default="1k")
    gp.add_argument("--size", type=int, default=None)
    gp.add_argument("--desaturate", type=float, default=0.0)
    gp.add_argument("--tint", type=float, default=0.0)
    gp.add_argument("--contrast", type=float, default=1.0)
    gp.add_argument("--target-mean", type=float, default=None, help="required here")
    gp.add_argument("--floor", type=float, default=0.02)
    gp.add_argument("--ceil", type=float, default=0.98)
    gp.add_argument("--quality", type=int, default=90)
    gp.add_argument("--no-normal", dest="normal", action="store_false")
    gp.add_argument("--normal-quality", type=int, default=92)
    gp.add_argument("--normal-size", type=int, default=None)
    gp.add_argument("--normal-strength", type=float, default=1.0)
    gp.add_argument("--normal-recenter", action="store_true")
    gp.add_argument("--gl-normal", action="store_true")
    gp.set_defaults(func=cmd_grade, normal=True)

    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
