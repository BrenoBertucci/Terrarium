"""Install the Gen 5 (Black/White) battle sprites as the mod's mon pack.

Source: PokeAPI/sprites on GitHub, sprites/pokemon/versions/generation-v/
black-white/{id}.png and back/{id}.png (96x96, transparent), downloaded to
tools/_vfx_dl/pokeapi_bw/{front,back}/{id}.png. The id -> name list is
tools/_vfx_dl/pokeapi151.json (https://pokeapi.co/api/v2/pokemon?limit=151).

Each sprite is cropped to its opaque bounding box -- the engine hangs a pic
by its bottom-centre (feet on the baseline, centred on the slot), so the
transparent margins the sheets carry would float a mon above the ground
and off-centre -- and written as assets/mons/{front,back}/<name>.png,
where <name> is the species id lower-cased with everything but letters
and digits dropped (NIDORAN_F -> nidoranf, MR_MIME -> mrmime), which is
also how lib/MonPack.lua keys them at runtime. Pixels are copied as they
are: no resampling, no recolour.

    python tools/install_mon_pack.py
"""
import json
import re
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "_vfx_dl" / "pokeapi_bw"
LIST = ROOT / "tools" / "_vfx_dl" / "pokeapi151.json"
OUT = ROOT / "assets" / "mons"


def norm(name):
    return re.sub(r"[^a-z0-9]", "", name.lower())


def crop(img):
    a = np.array(img.convert("RGBA"))
    alpha = a[..., 3]
    ys, xs = np.where(alpha > 0)
    if len(ys) == 0:
        return None
    y0, y1 = ys.min(), ys.max() + 1
    x0, x1 = xs.min(), xs.max() + 1
    return Image.fromarray(a[y0:y1, x0:x1], "RGBA")


def main():
    names = json.loads(LIST.read_text(encoding="utf-8"))["results"]
    (OUT / "front").mkdir(parents=True, exist_ok=True)
    (OUT / "back").mkdir(parents=True, exist_ok=True)
    n = 0
    for i, entry in enumerate(names, start=1):
        key = norm(entry["name"])
        for side in ("front", "back"):
            src = SRC / side / f"{i}.png"
            if not src.exists():
                print(f"missing {src}")
                continue
            img = crop(Image.open(src))
            if img is None:
                print(f"blank {src}")
                continue
            out = OUT / side / f"{key}.png"
            img.save(out, optimize=True)
            n += 1
    print(f"wrote {n} sprites to {OUT}")


if __name__ == "__main__":
    main()
