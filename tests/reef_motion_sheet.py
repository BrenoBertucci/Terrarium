"""Lays out tests/reef_motion_probe.lua's frames and measures them.

    py tests/reef_motion_sheet.py [probe_out_dir]

Two things, for the garden as built (ON) and the same garden rebuilt rigid
(OFF, Kit.pack told every voxel is stone):

  the SHEETS   each subject's frames side by side, ON above OFF, with the
               mean change between consecutive frames. The water's own swell
               and caustics move in both rows, so this is a reading, not a
               verdict.
  the FLOWER   a lily's flower is the one magenta thing out there, so it can
               be found without knowing the scene -- and a pad carries its
               flower rigidly, so where the flower goes, the pad went. With
               the camera pinned, OFF is the noise floor: whatever ON does
               over that, the physics did. This IS the verdict.
"""
import sys
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageStat

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else
           Path(__file__).resolve().parent.parent / "probe_out_reef_motion")

# reef_sheet.py's pink (255,96,150): red first, blue over green. The orange a
# surfing mon is painted in fails the second test, so it is never counted.
def is_flower(r, g, b):
    return r > 150 and b > g + 30 and r > b + 55 and g < 150


def flower_box(path, margin=60):
    """The biggest patch of flower in a frame, as a box to watch."""
    im = Image.open(path).convert("RGB")
    px, (w, h) = im.load(), im.size
    seen, best = set(), None
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            if (x, y) in seen or not is_flower(*px[x, y]):
                continue
            stack, blob = [(x, y)], []
            seen.add((x, y))
            while stack:                     # flood fill on the 2 px grid
                cx, cy = stack.pop()
                blob.append((cx, cy))
                for dx, dy in ((2, 0), (-2, 0), (0, 2), (0, -2)):
                    nx, ny = cx + dx, cy + dy
                    if (0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen
                            and is_flower(*px[nx, ny])):
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            if best is None or len(blob) > len(best):
                best = blob
    if not best:
        return None
    xs, ys = [p[0] for p in best], [p[1] for p in best]
    return (max(0, min(xs) - margin), max(0, min(ys) - margin),
            min(w, max(xs) + margin), min(h, max(ys) + margin))


def flower_at(path, box):
    im = Image.open(path).convert("RGB").crop(box)
    px, (w, h) = im.load(), im.size
    n = sx = sy = 0
    for y in range(h):
        for x in range(w):
            if is_flower(*px[x, y]):
                n += 1
                sx += x
                sy += y
    return n, (sx / n if n else 0), (sy / n if n else 0)


def track(pattern, box):
    """How far the flower strays from where it started, frame by frame."""
    base, walk = None, []
    for p in sorted(OUT.glob(pattern)):
        n, cx, cy = flower_at(p, box)
        if n < 300:                          # behind the swimmer: no reading
            walk.append(None)
            continue
        if base is None:
            base = (cx, cy)
        walk.append(((cx - base[0]) ** 2 + (cy - base[1]) ** 2) ** 0.5)
    return walk


def crop(path, frac=0.5):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    cw, ch = int(w * frac), int(h * frac)
    return im.crop(((w - cw) // 2, (h - ch) // 2, (w + cw) // 2, (h + ch) // 2))


def change(frames):
    diffs = [sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3
             for a, b in zip(frames, frames[1:])]
    return sum(diffs) / len(diffs) if diffs else 0.0


def sheet(rows, name, scale=0.5):
    tiles = [[im.resize((int(im.width * scale), int(im.height * scale))) for im in row]
             for _, row in rows]
    tw, th = tiles[0][0].size
    cols = max(len(r) for r in tiles)
    out = Image.new("RGB", (cols * tw + 60, len(tiles) * th), "black")
    draw = ImageDraw.Draw(out)
    for r, ((label, _), row) in enumerate(zip(rows, tiles)):
        draw.text((6, r * th + th // 2), label, fill="white")
        for c, im in enumerate(row):
            out.paste(im, (60 + c * tw, r * th))
    out.save(OUT / name)
    return OUT / name


for subject in ("pads", "kelp", "reeds"):
    rows = []
    for tag in ("on", "off"):
        frames = [crop(p) for p in sorted(OUT.glob(f"{tag}_{subject}_*.png"))]
        if frames:
            rows.append((tag.upper(), frames))
            print(f"{subject:6s} {tag:3s}: mean change {change(frames):6.2f} over {len(frames)} frames")
    if rows:
        print("   ->", sheet(rows, f"sheet_{subject}.png"))

rows = []
for tag in ("on", "off"):
    frames = [crop(p, 0.6) for p in sorted(OUT.glob(f"{tag}_pass_*.png"))][:10]
    if frames:
        rows.append((tag.upper(), frames))
if rows:
    print("pass   ->", sheet(rows, "sheet_pass.png", 0.35))

# ------- the verdict: one pad, watched, against the rigid rebuild
for what, least in (("pads", 8), ("pass", 20)):
    still = sorted(OUT.glob(f"off_{what}_*.png"))
    if not still:
        continue
    box = flower_box(still[0])
    if not box:
        print(f"{what}: no flower in frame to watch")
        continue
    walks = {tag: track(f"{tag}_{what}_*.png", box) for tag in ("on", "off")}
    far = {tag: max([d for d in w if d is not None] or [0]) for tag, w in walks.items()}
    # against the rigid rebuild, which is this scene's own noise floor
    ok = far["on"] > least and far["on"] > 3 * max(far["off"], 1.0)
    print(f"{'PASS' if ok else 'FAIL'} {what}: the pad strays {far['on']:.1f} px "
          f"with the physics on, {far['off']:.1f} px with the garden rigid "
          f"(box {box})")
    for tag in ("on", "off"):
        print("      " + tag.upper() + ": " +
              " ".join("----" if d is None else f"{d:4.0f}" for d in walks[tag]))
