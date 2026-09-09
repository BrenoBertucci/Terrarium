"""Dump a Gen 1 interior's floor plan from the BUILD's generated data.

The mod matches templates against a map's TILE grid, but the shipped data
stores a map as BLOCKS (4x4 tiles each) plus the tileset's blockdefs. This
walks maps.lua + tilesets.lua and prints the expanded tile grid, so a room
is authored against what the game really holds instead of against the
authoring coordinates in assets/docs (which are a different numbering --
see tests/mart_probe.lua's header).

  python tools/interior_plan.py VIRIDIAN_MART
  python tools/interior_plan.py VIRIDIAN_MART --json out.json
  python tools/interior_plan.py VIRIDIAN_MART --atlas out.png   (x10, ids)
  python tools/interior_plan.py VIRIDIAN_MART --render out.png  (the room)

The files are machine-generated with fixed two-space indentation, so the
reader is line-based on purpose: a general Lua parser is more code and more
ways to be wrong about 900 KB of tables nobody reads.
"""
import json
import re
import sys
from pathlib import Path

BUILD = Path(r"C:/Users/breno/Downloads/GBA/Quiver-Windows-x64/Apps"
             r"/PokemonRedBlueYellow-Gen1RecompProject-Recomp")
ROM = "yellow"


def gen(name):
    return BUILD / ROM / "data" / "generated" / name


def top_block(path, key):
    """The lines of `  <key> = {` .. `  },` at the top level of the file."""
    lines = path.read_text(encoding="utf-8").splitlines()
    start = None
    for i, ln in enumerate(lines):
        if ln == f"  {key} = {{":
            start = i
            break
    if start is None:
        raise KeyError(f"{key} not in {path.name}")
    for j in range(start + 1, len(lines)):
        if lines[j] == "  },":
            return lines[start + 1:j]
    raise KeyError(f"{key} unterminated")


def scalar(lines, key):
    pat = re.compile(rf"^    {re.escape(key)} = (.+),$")
    for ln in lines:
        m = pat.match(ln)
        if m:
            v = m.group(1)
            if v.startswith('"'):
                return v[1:-1]
            if v in ("true", "false"):
                return v == "true"
            try:
                return int(v)
            except ValueError:
                return v
    return None


def numlist(lines, key, indent=4):
    """A flat list of numbers under `<key> = {`."""
    out, depth, on = [], 0, False
    head = " " * indent + key + " = {"
    for ln in lines:
        if not on:
            if ln == head:
                on, depth = True, 1
            continue
        s = ln.strip()
        depth += s.count("{") - s.count("}")
        if depth <= 0:
            break
        for tok in re.findall(r"-?\d+", s):
            out.append(int(tok))
    return out


def numlist_of_lists(lines, key, indent=4):
    """`<key> = { { n, .. }, { n, .. } }` -> list of lists."""
    out, cur, depth, on = [], None, 0, False
    head = " " * indent + key + " = {"
    for ln in lines:
        if not on:
            if ln == head:
                on, depth = True, 1
            continue
        s = ln.strip()
        if s.startswith("{"):
            cur = []
            depth += 1
            continue
        if s.startswith("}"):
            depth -= 1
            if depth <= 0:
                break
            if cur is not None:
                out.append(cur)
                cur = None
            continue
        if cur is not None:
            cur += [int(t) for t in re.findall(r"-?\d+", s)]
    return out


def records(lines, key, indent=4):
    """`<key> = { { a = 1, b = "x" }, .. }` -> list of dicts."""
    out, cur, depth, on = [], None, 0, False
    head = " " * indent + key + " = {"
    for ln in lines:
        if not on:
            if ln == head:
                on, depth = True, 1
            continue
        s = ln.strip()
        if s == "{":
            cur, depth = {}, depth + 1
            continue
        if s in ("},", "}"):
            depth -= 1
            if depth <= 0:
                break
            if cur is not None:
                out.append(cur)
                cur = None
            continue
        m = re.match(r'^(\w+) = (.+),$', s)
        if m and cur is not None:
            v = m.group(2)
            cur[m.group(1)] = (v[1:-1] if v.startswith('"')
                               else int(v) if re.fullmatch(r"-?\d+", v)
                               else v)
    return out


def plan(map_id):
    ml = top_block(gen("maps.lua"), map_id)
    tsid = scalar(ml, "tileset")
    tl = top_block(gen("tilesets.lua"), tsid)
    w, h = scalar(ml, "width"), scalar(ml, "height")
    blocks = numlist(ml, "blocks")
    defs = numlist_of_lists(tl, "blocks")
    grid = [[0] * (w * 4) for _ in range(h * 4)]
    for by in range(h):
        for bx in range(w):
            b = defs[blocks[by * w + bx]]
            for r in range(4):
                for c in range(4):
                    grid[by * 4 + r][bx * 4 + c] = b[r * 4 + c]
    meta = {
        "map": map_id, "tileset": tsid, "w": w, "h": h,
        "image": scalar(tl, "image"),
        "imageWidth": scalar(tl, "imageWidth"),
        "imageHeight": scalar(tl, "imageHeight"),
        "tilesPerRow": scalar(tl, "tilesPerRow"),
        "walkable": numlist(tl, "walkable"),
        "warpTiles": numlist(tl, "warpTiles"),
        "objects": records(ml, "objects"),
        "warps": records(ml, "warps"),
        "blockIds": blocks,
    }
    return meta, grid


def atlas_png(meta, out, scale=10):
    from PIL import Image, ImageDraw
    src = Image.open(BUILD / ROM / meta["image"]).convert("RGB")
    per = meta["tilesPerRow"]
    rows = src.height // 8
    cell = 8 * scale
    img = Image.new("RGB", (per * (cell + 2), rows * (cell + 14)), (24, 24, 28))
    d = ImageDraw.Draw(img)
    for ty in range(rows):
        for tx in range(per):
            t = src.crop((tx * 8, ty * 8, tx * 8 + 8, ty * 8 + 8))
            t = t.resize((cell, cell), Image.NEAREST)
            px, py = tx * (cell + 2), ty * (cell + 14) + 12
            img.paste(t, (px, py))
            d.text((px + 1, py - 11), str(ty * per + tx), fill=(210, 210, 120))
    img.save(out)
    return img.size


def render_png(meta, grid, out, scale=6):
    from PIL import Image, ImageDraw
    src = Image.open(BUILD / ROM / meta["image"]).convert("RGB")
    per = meta["tilesPerRow"]
    cell = 8 * scale
    H, W = len(grid), len(grid[0])
    img = Image.new("RGB", (W * cell, H * cell), (0, 0, 0))
    for y in range(H):
        for x in range(W):
            t = grid[y][x]
            tx, ty = t % per, t // per
            crop = src.crop((tx * 8, ty * 8, tx * 8 + 8, ty * 8 + 8))
            img.paste(crop.resize((cell, cell), Image.NEAREST),
                      (x * cell, y * cell))
    d = ImageDraw.Draw(img)
    for y in range(H):
        for x in range(W):
            d.text((x * cell + 2, y * cell + 2), str(grid[y][x]),
                   fill=(255, 90, 90))
    img.save(out)
    return img.size


def main():
    map_id = sys.argv[1] if len(sys.argv) > 1 else "VIRIDIAN_MART"
    meta, grid = plan(map_id)
    print(f"{map_id}  tileset={meta['tileset']}  "
          f"{meta['w']}x{meta['h']} blocks = {len(grid[0])}x{len(grid)} tiles")
    print(f"image={meta['image']} {meta['imageWidth']}x{meta['imageHeight']}"
          f" perRow={meta['tilesPerRow']}")
    print(f"walkable={meta['walkable']}  warpTiles={meta['warpTiles']}")
    print()
    print("     " + "".join(f"{c:>4}" for c in range(len(grid[0]))))
    for y, row in enumerate(grid):
        print(f"{y:>3}  " + "".join(f"{t:>4}" for t in row))
    print()
    for o in meta["objects"]:
        print(f"  object {o.get('name')} {o.get('sprite')} "
              f"x={o.get('x')} y={o.get('y')}")
    for wp in meta["warps"]:
        print(f"  warp -> {wp.get('destMap')} x={wp.get('x')} y={wp.get('y')}")

    def arg(flag):
        return sys.argv[sys.argv.index(flag) + 1] if flag in sys.argv else None

    if arg("--json"):
        Path(arg("--json")).write_text(
            json.dumps({"meta": meta, "grid": grid}, indent=1))
        print(f"\nwrote {arg('--json')}")
    if arg("--atlas"):
        print("atlas", atlas_png(meta, arg("--atlas")))
    if arg("--render"):
        print("render", render_png(meta, grid, arg("--render")))


if __name__ == "__main__":
    main()
