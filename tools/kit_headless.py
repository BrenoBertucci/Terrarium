"""HEADLESS RENDER HARNESS -- look at a kit's voxel geometry in seconds.

Loads the game's lua51.dll with ctypes, runs tools/kit_headless.lua in it,
and lets a REAL kit module out of lib/ build its models against a REAL map
read out of the BUILD's generated data (tools/interior_plan.py does the
maps.lua + tilesets.lua walk; this file imports it rather than parsing Lua
data a second time). Every voxel of every model is walked exactly the way
Buildings.emit walks it -- PHANTOM rule and all -- and the assembled floor
is rendered isometrically with PIL.

    python tools/kit_headless.py --kit CryptKit --map POKEMON_TOWER_1F
    python tools/kit_headless.py --kit CryptKit --map POKEMON_TOWER_4F \
        --png tools/_kit_out/tower4f.png

It is GEOMETRY ONLY. There is no game shader here: no lanterns, no bloom,
no palette, no fog. A face count is a proxy for cost, not the cost. See
tools/kit_headless.md.
"""
import argparse
import ctypes
import json
import os
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import interior_plan  # noqa: E402  (the shipped map/tileset reader)

ROOT = Path(__file__).resolve().parent.parent
BUILD = interior_plan.BUILD
ROM = interior_plan.ROM
LUA_DLL = BUILD / "lua51.dll"
HARNESS = ROOT / "tools" / "kit_headless.lua"
WORK = ROOT / "tools" / "_kit_out"

# ---------------------------------------------------------------- kits --
#
# One entry per kit. A kit is anything in lib/ that exposes the pair
#
#     Kit.signature(t, tileAt, tx, ty, map) -> string   (or nil to skip)
#     Kit.model(sp, t, sig)                 -> model    (or nil, reason)
#
# where a model is { at(x,y,z) -> texel index | nil | PHANTOM, W, ytop,
# xmin, xmax, zmin, zmax } with an optional tint(y, i, dir, shade).
#
#   module    lib/<module>.lua, and the name passed to --kit
#   mark      the key on a data/voxel_heights.lua template that says
#             "this kit owns it" (t.crypt for the crypt, t.<mark> for
#             yours). Templates without it are still scanned, so the
#             first-claim-wins order Buildings.build relies on holds.
#   tileset   which buildings.<TILESET> list the templates live in
#   map       the default --map
#   settings  ModSetting rows forced for the run, keyed by setting KEY
#             (the first argument of ModSetting.new). A row not named
#             here falls back to values[1], the shipped default.
#   stubs     lib/ modules replaced by a no-op table, because they reach
#             for a GPU at load time. Keep this list as short as it can
#             be: every stub is a piece of the real thing not tested.
#   preload   mod-relative image files the kit reads through
#             V.mod.read + love.image.newImageData. Decoded here and
#             handed over as raw channel dumps.
KITS = {
    "CryptKit": dict(
        module="CryptKit",
        mark="crypt",
        tileset="CEMETERY",
        map="POKEMON_TOWER_1F",
        settings={"crypt": "new", "cryptfx": "on"},
        stubs=["Voxel3D"],
        preload=["assets/stone/crypt_wall_h.png"],
    ),
    # A kit written against the same contract drops in here. Nothing else
    # in this file or in kit_headless.lua is crypt-specific.
    "ShopKit": dict(
        module="ShopKit",
        mark="shop",
        tileset="MART",
        map="VIRIDIAN_MART",
        settings={"shop": "new", "shopfx": "on"},
        stubs=["Voxel3D"],
        preload=[],
        # this kit is read from an AUTHORED sheet, not from the four-grey
        # tileset: Buildings' `spriteBand` path, reproduced as readSheet
        sheet="assets/shop/shop_sheet.png",
    ),
}

# ------------------------------------------------------------ lua glue --

LUA_GLOBALSINDEX = -10002


class Lua:
    """The smallest ctypes binding that can run one script and report why
    it failed. Everything bulky (the atlas, the height map, the faces)
    travels through files, so nothing here has to marshal a table."""

    def __init__(self, dll):
        os.add_dll_directory(str(Path(dll).parent))
        self.lib = ctypes.CDLL(str(dll))
        L = self.lib
        L.luaL_newstate.restype = ctypes.c_void_p
        for name, args in (
            ("luaL_openlibs", [ctypes.c_void_p]),
            ("lua_close", [ctypes.c_void_p]),
            ("lua_pushstring", [ctypes.c_void_p, ctypes.c_char_p]),
            ("lua_setfield", [ctypes.c_void_p, ctypes.c_int, ctypes.c_char_p]),
            ("lua_settop", [ctypes.c_void_p, ctypes.c_int]),
        ):
            getattr(L, name).argtypes = args
            getattr(L, name).restype = None
        L.luaL_loadfile.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        L.luaL_loadfile.restype = ctypes.c_int
        L.lua_pcall.argtypes = [ctypes.c_void_p] + [ctypes.c_int] * 3
        L.lua_pcall.restype = ctypes.c_int
        L.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int,
                                    ctypes.c_void_p]
        L.lua_tolstring.restype = ctypes.c_char_p
        self.L = ctypes.c_void_p(L.luaL_newstate())
        if not self.L:
            raise RuntimeError("luaL_newstate failed")
        L.luaL_openlibs(self.L)

    def setglobal(self, name, value):
        self.lib.lua_pushstring(self.L, value.encode("utf-8"))
        self.lib.lua_setfield(self.L, LUA_GLOBALSINDEX, name.encode("ascii"))

    def error(self):
        s = self.lib.lua_tolstring(self.L, -1, None)
        return s.decode("utf-8", "replace") if s else "(no message)"

    def dofile(self, path):
        if self.lib.luaL_loadfile(self.L, str(path).encode("utf-8")):
            raise RuntimeError("lua load: " + self.error())
        if self.lib.lua_pcall(self.L, 0, 0, 0):
            raise RuntimeError("lua run: " + self.error())

    def close(self):
        if self.L:
            self.lib.lua_close(self.L)
            self.L = None


# ------------------------------------------------------------ job file --


def lua_literal(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if v is None:
        return "nil"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, (list, tuple)):
        return "{" + ",".join(lua_literal(x) for x in v) + "}"
    if isinstance(v, dict):
        parts = []
        for k, x in v.items():
            key = k if str(k).isidentifier() else '["%s"]' % k
            parts.append("%s=%s" % (key, lua_literal(x)))
        return "{" + ",".join(parts) + "}"
    raise TypeError(type(v))


def dump_image(path, out, mode):
    img = Image.open(path).convert(mode)
    out.write_bytes(img.tobytes())
    return img.width, img.height, len(mode)


# --------------------------------------------------------------- render --
#
# True isometric, camera to the SOUTH-EAST and above -- the quarter the
# crypt's dollhouse cut is authored for (Crypt.BANDS steps the near walls
# down so a camera at the south looks over them). Painter's algorithm on
# the face centroid: the quads are axis-aligned voxel faces, so a centroid
# sort misorders only where two coplanar runs interleave, which shows up
# as speckle and never as a wrong wall.

SQ2, SQ3, SQ6 = np.sqrt(2.0), np.sqrt(3.0), np.sqrt(6.0)
# which face directions the camera can see at all (1 s, 2 n, 3 up,
# 4 down, 5 e, 6 w) -- the back half is culled before anything is sorted
FRONT_DIRS = (1, 3, 5)


def render(faces, out_png, width=1400, bg=(9, 9, 12), images=(),
           cull=True, max_faces=None, shade_only=False):
    """faces: (n, 20) uint16 as kit_headless.lua wrote them. `images` is
    indexed by the face's texture id: 0 the map's tileset, 1.. the
    authored sheets."""
    if len(faces) == 0:
        raise SystemExit("no faces to render")
    xyz = faces[:, :12].astype(np.float64) - 1024.0
    shade = faces[:, 12:16].astype(np.float64) / 1000.0
    tax, tay = faces[:, 16].astype(np.int32), faces[:, 17].astype(np.int32)
    dirs = faces[:, 18].astype(np.int32)
    tex = faces[:, 19].astype(np.int32)

    if cull:
        keep = np.isin(dirs, FRONT_DIRS)
        xyz, shade, tax, tay, dirs, tex = (xyz[keep], shade[keep], tax[keep],
                                           tay[keep], dirs[keep], tex[keep])
    n = len(xyz)
    if n == 0:
        raise SystemExit("every face was culled")

    X = xyz[:, 0::3]
    Y = xyz[:, 1::3]
    Z = xyz[:, 2::3]
    sx = (X - Z) / SQ2
    sy = (X - 2.0 * Y + Z) / SQ6
    depth = (X + Y + Z).mean(axis=1) / SQ3

    x0, x1 = sx.min(), sx.max()
    y0, y1 = sy.min(), sy.max()
    scale = (width - 24) / max(x1 - x0, 1e-6)
    height = int((y1 - y0) * scale) + 24
    px = (sx - x0) * scale + 12
    py = (sy - y0) * scale + 12

    # base colour: the texel the run's first pixel wears, straight off
    # whichever image that run came from
    base = np.full((n, 3), 255.0)
    for k, img in enumerate(images):
        if img is None:
            continue
        sel = tex == k
        if not sel.any():
            continue
        ah, aw = img.shape[0], img.shape[1]
        base[sel] = img[np.clip(tay[sel], 0, ah - 1),
                        np.clip(tax[sel], 0, aw - 1)]
    # `shade_only` throws the texel away and draws the LIGHT: a room whose
    # every surface is the same white is the only way to see a shadow that
    # a photograph would otherwise hide. It is what the contact field is
    # read on.
    if shade_only:
        base = np.full((n, 3), 235.0)

    # GOURAUD, not one colour a face. The four corner shades are the whole
    # point of the corner AO and of the contact field, and averaging them
    # (which this did until the shadow work) renders both as a flat step --
    # the harness would have reported a working contact field as a no-op.
    # Four triangles about the face's centre is the cheap approximation:
    # each one carries the mean of the centre and its own two corners, so
    # the gradient survives at four times the polygon count.
    corner = shade[:, :, None] * base[:, None, :]          # (n, 4, 3)
    centre = corner.mean(axis=1)                           # (n, 3)
    cx, cy = px.mean(axis=1), py.mean(axis=1)

    order = np.argsort(depth, kind="stable")
    if max_faces and n > max_faces:
        order = order[-max_faces:]

    from PIL import ImageDraw
    img = Image.new("RGB", (width, height), bg)
    d = ImageDraw.Draw(img)
    pxl, pyl = px.tolist(), py.tolist()
    cxl, cyl = cx.tolist(), cy.tolist()
    tri = np.clip((corner + np.roll(corner, -1, axis=1)
                   + centre[:, None, :]) / 3.0, 0, 255).astype(np.uint8)
    tril = [[tuple(int(c) for c in v) for v in f] for f in tri]
    for k in order.tolist():
        a, b, mx, my = pxl[k], pyl[k], cxl[k], cyl[k]
        t = tril[k]
        for j in range(4):
            j2 = (j + 1) & 3
            d.polygon([(a[j], b[j]), (a[j2], b[j2]), (mx, my)], fill=t[j])
    img.save(out_png)
    return img.size, n


# ----------------------------------------------------------------- main --


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--kit", default="CryptKit", help="a key of KITS")
    ap.add_argument("--map", default=None, help="a map id, e.g. POKEMON_TOWER_4F")
    ap.add_argument("--template", default=None,
                    help="restrict modelling to one template id, e.g. crypt_wall")
    ap.add_argument("--set", action="append", default=[], metavar="KEY=VALUE",
                    help="force a ModSetting row, e.g. --set cryptfx=off")
    ap.add_argument("--png", default=None, help="where the render goes")
    ap.add_argument("--width", type=int, default=1400)
    ap.add_argument("--json", default=None, help="also write the raw report")
    ap.add_argument("--no-render", action="store_true")
    ap.add_argument("--no-cull", action="store_true",
                    help="draw back faces too (they should never show)")
    ap.add_argument("--shade-only", action="store_true",
                    help="draw the LIGHT, not the texel: every surface the "
                         "same white, so AO and the contact field show")
    ap.add_argument("--placements", type=int, default=0,
                    help="print the N slowest placements")
    args = ap.parse_args()

    if args.kit not in KITS:
        raise SystemExit("unknown kit %r; known: %s"
                         % (args.kit, ", ".join(sorted(KITS))))
    cfg = KITS[args.kit]
    map_id = args.map or cfg["map"]
    WORK.mkdir(parents=True, exist_ok=True)

    if not (ROOT / "lib" / (cfg["module"] + ".lua")).exists():
        raise SystemExit("lib/%s.lua does not exist" % cfg["module"])

    t0 = time.perf_counter()
    try:
        meta, grid = interior_plan.plan(map_id)
    except KeyError as e:
        raise SystemExit("no such map in the BUILD's generated data: %s\n"
                         "  (%s)" % (map_id, e))
    if meta["tileset"] != cfg["tileset"]:
        print("note: %s is tileset %s, kit %s expects %s"
              % (map_id, meta["tileset"], args.kit, cfg["tileset"]))
    atlas_path = BUILD / ROM / meta["image"]
    atlas_raw = WORK / "atlas.rgba"
    aw, ah, achan = dump_image(atlas_path, atlas_raw, "RGBA")

    preload = []
    for i, rel in enumerate(cfg.get("preload", [])):
        src = ROOT / rel
        if not src.exists():
            print("note: preload missing, kit will fall back: %s" % rel)
            continue
        raw = WORK / ("preload%d.gray" % i)
        w, h, chan = dump_image(src, raw, "L")
        preload.append(dict(rel=rel, path=str(raw).replace("\\", "/"),
                            w=w, h=h, chan=chan))

    # Authored sheets: the kit's default plus anything a template names.
    # Index 0 in the dump is the map's tileset; these start at 1.
    sheets, sheet_imgs = [], []
    for rel in dict.fromkeys(list(cfg.get("sheets", []))
                             + ([cfg["sheet"]] if cfg.get("sheet") else [])):
        src = ROOT / rel
        if not src.exists():
            print("note: sheet missing, the kit will fall back to the "
                  "tileset: %s" % rel)
            continue
        raw = WORK / ("sheet%d.rgba" % len(sheets))
        w, h, chan = dump_image(src, raw, "RGBA")
        sheets.append(dict(rel=rel, path=str(raw).replace("\\", "/"),
                           w=w, h=h, chan=chan))
        sheet_imgs.append(np.asarray(Image.open(src).convert("RGB")))

    settings = dict(cfg.get("settings", {}))
    for kv in args.set:
        if "=" not in kv:
            raise SystemExit("--set wants KEY=VALUE, got %r" % kv)
        k, v = kv.split("=", 1)
        settings[k] = v

    faces_bin = WORK / ("%s_%s.faces" % (args.kit, map_id))
    report_js = WORK / ("%s_%s.json" % (args.kit, map_id))
    job = dict(
        root=str(ROOT).replace("\\", "/"),
        kit=cfg["module"],
        mark=cfg.get("mark"),
        tileset=meta["tileset"],
        only=args.template,
        map=dict(id=map_id, width=meta["w"], height=meta["h"]),
        atlas=dict(path=str(atlas_raw).replace("\\", "/"), w=aw, h=ah,
                   perRow=meta["tilesPerRow"], image=meta["image"]),
        grid=dict(w=len(grid[0]), h=len(grid),
                  tiles=[t for row in grid for t in row]),
        settings=settings,
        stubs=cfg.get("stubs", []),
        preload=preload,
        sheets=sheets,
        sheet=cfg.get("sheet"),
        out=str(faces_bin).replace("\\", "/"),
        report=str(report_js).replace("\\", "/"),
    )
    job_lua = WORK / "job.lua"
    job_lua.write_text("return " + lua_literal(job), encoding="utf-8")

    lua = Lua(LUA_DLL)
    lua.setglobal("KH_JOB", str(job_lua).replace("\\", "/"))
    t_lua = time.perf_counter()
    try:
        lua.dofile(HARNESS)
    except RuntimeError as e:
        # a Lua error is the normal way a broken kit reports itself; the
        # traceback below it would only be this file's plumbing
        raise SystemExit("%s\n  job: %s" % (e, job_lua))
    finally:
        lua.close()
    lua_s = time.perf_counter() - t_lua

    rep = json.loads(report_js.read_text(encoding="utf-8"))
    raw = np.frombuffer(faces_bin.read_bytes(), dtype=">u2")
    faces = raw.reshape(-1, 20)

    print("%s on %s (tileset %s)" % (args.kit, map_id, meta["tileset"]))
    print("  settings   %s" % (settings or "(defaults)"))
    print("  lib/Buildings.lua loaded=%s PHANTOM=%s   kit row on=%s"
          % (bool(rep["buildings_loaded"]), rep["phantom"],
             bool(rep.get("kit_enabled", 1))))
    scanned = sum(t["placements"] for t in rep["templates"])
    print("  placements %d scanned, %d modelled by the kit"
          % (scanned, rep["placements_total"]))
    print("  models     %d built   %d distinct signatures"
          % (rep["models_total"], len({m["sig"] for m in rep["models"]})))
    print("  faces      %d emitted into the floor (%d rows in the dump)"
          % (rep["faces"], len(faces)))
    print("  lua        %.2f s (%.2f s of it modelling)"
          % (lua_s, rep["seconds"]))
    print("  templates:")
    for t in rep["templates"]:
        if not t["placements"]:
            continue
        print("    %-16s %s  placements %3d  models %3d  faces %7d  %6.0f ms"
              % (t["id"], "kit" if t["mine"] else "---", t["placements"],
                 t["models"], t["faces"], t["seconds"] * 1000))
    if rep["models"]:
        slow = sorted(rep["models"], key=lambda m: -m["seconds"])[:5]
        print("  slowest models (build once, stamp many):")
        for m in slow:
            print("    %-34s faces %6d  voxels %7d  shell %7d  %5.0f ms"
                  % (m["sig"][:34], m["faces"], m["voxels"], m["shell"],
                     m["seconds"] * 1000))
    if args.placements and rep["placements"]:
        slow = sorted(rep["placements"], key=lambda p: -p["ms"])[:args.placements]
        print("  slowest placements:")
        for p in slow:
            print("    %-12s @%3d,%3d  %-30s faces %6d  %6.1f ms"
                  % (p["id"], p["tx"], p["ty"], p["sig"][:30], p["faces"],
                     p["ms"]))
    for e in rep["errors"]:
        print("  ERROR  %s" % e)

    if args.json:
        Path(args.json).write_text(json.dumps(rep, indent=1), encoding="utf-8")
        print("  wrote %s" % args.json)

    if not args.no_render:
        out = Path(args.png) if args.png else (
            WORK / ("%s_%s.png" % (args.kit, map_id)))
        out.parent.mkdir(parents=True, exist_ok=True)
        atlas_rgb = np.asarray(Image.open(atlas_path).convert("RGB"))
        size, drawn = render(faces, out, width=args.width,
                             images=[atlas_rgb] + sheet_imgs,
                             cull=not args.no_cull,
                             shade_only=args.shade_only)
        print("  render     %dx%d, %d faces drawn -> %s" % (size[0], size[1],
                                                            drawn, out))
    print("  total      %.2f s" % (time.perf_counter() - t0))
    if rep["errors"]:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
