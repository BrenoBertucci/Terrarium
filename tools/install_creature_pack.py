"""Fetch the Tuxemon creature sprites -- monsters that are nobody's property.

    py tools/install_creature_pack.py

WHY THIS EXISTS. assets/mons carries Generation 5 battle sprites from PokeAPI:
Nintendo / Game Freak artwork, redistributable for fan use at best, and the
reason that folder is in .gitignore and installed on the player's own machine
rather than shipped. It is also the last borrowed art the battle wears, now
that the 5X HUD cuts are gone (2026-09-15).

Tuxemon (https://www.tuxemon.org, GPLv3, art CC BY-SA 4.0) is a libre
monster-catching RPG with its own creatures -- 411 of them, drawn front and
back at 64x64 with a pair of menu icons, which is the exact shape lib/MonPack
already serves. They are original designs by named artists, credited
individually in the project's ATTRIBUTIONS.md, and they can be redistributed:
the pack this writes is versionable, packageable and nobody's to take away.

WHAT IS WRITTEN
  assets/creatures/<slug>.png   the sheet, BYTE FOR BYTE as upstream published
                                it. Not re-encoded and not re-cut: a share-alike
                                licence is easiest to honour when the file is
                                provably the file, and lib/CreaturePack.lua
                                reads the three quadrants with quads anyway.
  data/creature_pool.lua        each creature's type, stage and shape -- what
                                the runtime pairing needs and nothing else.
  assets/creatures/CREDITS.md   the licence, the source, and how to re-fetch.

WHAT IS NOT DECIDED HERE. Which creature stands in for which species. That
pairing needs the GAME's own species table (types and evolution stage), which
lives in the player's ROM and is not readable from a script -- so it is made at
runtime, once, by lib/CreaturePack.lua. This tool only lays out the shelf.
"""

import argparse
import concurrent.futures as cf
import json
import os
import sys
import urllib.request

import yaml

REPO = "Tuxemon/Tuxemon"
REF = "development"
API = "https://api.github.com/repos/%s/contents/%%s?ref=%s" % (REPO, REF)
RAW = "https://raw.githubusercontent.com/%s/%s/%%s" % (REPO, REF)
DB_DIR = "mods/tuxemon/db/monster"
ART_DIR = "mods/tuxemon/gfx/sprites/battle"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_ART = os.path.join(ROOT, "assets", "creatures")
OUT_DATA = os.path.join(ROOT, "data", "creature_pool.lua")

# Sheet geometry, measured off the sheets (all 411 are 128x88):
#   (0,0)-(64,64)    front, facing the viewer
#   (64,0)-(128,64)  back, facing away
#   (0,64)-(48,88)   two menu icons side by side
#   (64,64)-(128,88) empty
SHEET_W, SHEET_H = 128, 88


def listing(path):
    with urllib.request.urlopen(API % path, timeout=60) as fh:
        return json.load(fh)


def fetch(url, timeout=60):
    with urllib.request.urlopen(url, timeout=timeout) as fh:
        return fh.read()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", type=int, default=12)
    ap.add_argument("--limit", type=int, default=0,
                    help="stop after N creatures (for a smoke run)")
    args = ap.parse_args()

    print("listing the monster database ...")
    db = [x for x in listing(DB_DIR) if x["name"].endswith(".yaml")]
    print("listing the battle sheets ...")
    art = {x["name"][: -len("-sheet.png")]: x["download_url"]
           for x in listing(ART_DIR) if x["name"].endswith("-sheet.png")}
    print("  %d records, %d sheets" % (len(db), len(art)))

    def one(entry):
        slug = entry["name"][:-5]
        if slug not in art:
            return slug, None, None          # a record with no drawing yet
        try:
            rec = yaml.safe_load(fetch(entry["download_url"]).decode("utf-8"))
            png = fetch(art[slug])
        except Exception as err:             # noqa: BLE001 - reported, not raised
            return slug, None, str(err)
        return slug, (rec, png), None

    todo = db[: args.limit] if args.limit else db
    os.makedirs(OUT_ART, exist_ok=True)
    pool, skipped, failed = [], 0, []
    with cf.ThreadPoolExecutor(args.jobs) as ex:
        for slug, got, err in ex.map(one, todo):
            if err:
                failed.append((slug, err))
                continue
            if not got:
                skipped += 1
                continue
            rec, png = got
            with open(os.path.join(OUT_ART, slug + ".png"), "wb") as fh:
                fh.write(png)
            pool.append(dict(
                slug=slug,
                types=[str(t) for t in (rec.get("types") or [])],
                stage=str(rec.get("stage") or "standalone"),
                shape=str(rec.get("shape") or ""),
                species=str(rec.get("species") or ""),
                height=float(rec.get("height") or 0),
                weight=float(rec.get("weight") or 0),
            ))

    pool.sort(key=lambda m: m["slug"])
    print("  wrote %d sheets, skipped %d without art, %d failed"
          % (len(pool), skipped, len(failed)))
    for slug, err in failed[:10]:
        print("    FAILED", slug, err)

    def lua_str(s):
        return '"%s"' % str(s).replace("\\", "\\\\").replace('"', '\\"')

    lines = [
        "-- The creature shelf: what lib/CreaturePack.lua has to choose from.",
        "--",
        "-- GENERATED by tools/install_creature_pack.py from Tuxemon's own",
        "-- monster database. Do not hand-edit -- re-run the tool.",
        "--",
        "-- Each row is one drawing in assets/creatures/<slug>.png and the three",
        "-- facts the pairing scores on: the creature's element, how far along",
        "-- its own evolution line it stands, and its silhouette.",
        "return {",
    ]
    for m in pool:
        types = ", ".join(lua_str(t) for t in m["types"])
        lines.append(
            "  { slug = %s, types = { %s }, stage = %s, shape = %s,"
            " species = %s, h = %g, w = %g },"
            % (lua_str(m["slug"]), types, lua_str(m["stage"]),
               lua_str(m["shape"]), lua_str(m["species"]),
               m["height"], m["weight"]))
    lines.append("}")
    lines.append("")
    with open(OUT_DATA, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))
    print("  wrote", OUT_DATA)

    credits = """# assets/creatures -- the creature pack

411 creature sprites from [Tuxemon](https://www.tuxemon.org), a libre
monster-catching RPG. Each `<slug>.png` is one creature's battle sheet, copied
byte for byte from the project's own repository:

    https://github.com/Tuxemon/Tuxemon
    mods/tuxemon/gfx/sprites/battle/<slug>-sheet.png   (branch: development)

Re-fetch with `tools/install_creature_pack.py`.

## Licence

Tuxemon's code is GPLv3; its art is licensed per asset, and the creature
sprites are **CC BY-SA 4.0** (a few are CC BY 4.0). Every one of them is
credited by name, artist and licence in the project's own attributions file,
which is the authoritative list and travels with this folder by reference:

    https://github.com/Tuxemon/Tuxemon/blob/development/ATTRIBUTIONS.md
    (see the section headed `### Tuxemon`)

CC BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/
Attribution is to the individual artists named there, and to the Tuxemon
project. Share-alike applies to adaptations of these sprites -- this mod draws
them unmodified, cutting the sheet's quadrants with quads at runtime.

## Why these and not the ones in assets/mons

`assets/mons` holds Generation 5 Pokemon battle sprites. That is Nintendo /
Game Freak artwork: it cannot be redistributed, it is in `.gitignore`, and it
never ships in a package. These creatures are original designs whose authors
licensed them for exactly this. Both sets serve the same slot in
`lib/MonPack.lua`; the CREATURES row in OPTIONS picks between them.

## Sheet layout (measured, all 411 are 128x88)

| region | contents |
| --- | --- |
| `(0,0)-(64,64)` | front sprite, facing the viewer |
| `(64,0)-(128,64)` | back sprite, facing away |
| `(0,64)-(48,88)` | two menu icons, 24x24 each |
| `(64,64)-(128,88)` | empty |
"""
    with open(os.path.join(OUT_ART, "CREDITS.md"), "w",
              encoding="utf-8", newline="\n") as fh:
        fh.write(credits)
    print("  wrote", os.path.join(OUT_ART, "CREDITS.md"))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
