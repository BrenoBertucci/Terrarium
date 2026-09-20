"""Cut the battle HUD's chrome out of a CC0 pixel-art GUI pack.

    py tools/install_ui_kit.py

Downloads tiopalada's "Tiny RPG - Mana Soul GUI" (CC0, OpenGameArt) and writes
four pieces into assets/battlexy/ui/. Two of them -- the gold item frame and
the vertical cursor -- were already taken from this pack for the bag preview;
this is the rest of it, the half the LICENSE.md note recorded as "not
imported": the 9-slice panel, the bar frame and its fill, and a button capsule.

WHY THIS PACK AND NOT ANOTHER. The battle costume needs a dark plate with gold
ornament at the corners, a framed trough with a tintable fill, and a capsule
for a command chip -- which is the concept boards' whole vocabulary. Sheet A of
the 9-slices is a navy plate with gold filigree corners and is that language
already; everything else here is cut from the same hand, so the plates, the
bar and the chips cannot drift apart the way four separate downloads would.

And it is CC0, which assets/battlexy/LICENSE.md makes the only admissible
licence in that folder.

NOTHING HERE IS PIXEL-PERFECT BY ACCIDENT: every box below was measured off
the sheet by this script (the alpha bounding box, and the strip's own cell
width), not read off a description, so re-cutting after an upstream change
re-measures instead of trusting a number in a comment.
"""

import io
import os
import sys
import urllib.request
import zipfile

from PIL import Image

ZIP_URL = "https://opengameart.org/sites/default/files/tinyrpg_manasoulgui_v_1_0.zip"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "battlexy", "ui")

# source sheet -> written file. The strip sheets carry several variants side by
# side; `cell` says how wide one is and `index` which one to take.
CUTS = [
    # The plate: navy with gold filigree corners, drawn as a 9-slice.
    # Measured insets (lib/BattleHudXY.PANEL_INSET): 28 left/right for the
    # corner swirls, 16 top/bottom for the rails.
    dict(src="20250420manaSoul9SlicesA-Sheet.png", dst="panel.png"),
    # The bar's OUTLINE -- a pale capsule with rounded caps and a hollow
    # middle, stretched over a fill this mod tints itself. Sheet C and not
    # sheet A: A is the prettier bar and has a flourish at the centre of its
    # bottom rail, which is exactly the pixel a stretched middle smears into a
    # streak. A bar is the one piece of chrome that must survive being three
    # times its own width, so the plain one is the right one.
    dict(src="20250421barC-Sheet.png", dst="bar_outline.png"),
    # A command capsule, first variant of four: gold double-chevron caps with
    # a flat body between them. Only the caps are used -- the body is drawn in
    # the type's or the command's own colour.
    dict(src="20250421manaSoulButtonA-Sheet.png", dst="chip.png", cell=4, index=0),
]


def fetch() -> zipfile.ZipFile:
    print("downloading", ZIP_URL)
    with urllib.request.urlopen(ZIP_URL, timeout=60) as fh:
        blob = fh.read()
    print("  %d bytes" % len(blob))
    return zipfile.ZipFile(io.BytesIO(blob))


def main() -> int:
    z = fetch()
    os.makedirs(OUT, exist_ok=True)
    for cut in CUTS:
        with z.open(cut["src"]) as fh:
            im = Image.open(io.BytesIO(fh.read())).convert("RGBA")
        if cut.get("cell"):
            w = im.width // cut["cell"]
            im = im.crop((w * cut["index"], 0, w * (cut["index"] + 1), im.height))
        # trim fully transparent margins so the drawn rect is the ART's rect;
        # an untrimmed sheet makes every inset in the Lua a guess about padding
        box = im.getbbox()
        if box:
            im = im.crop(box)
        dst = os.path.join(OUT, cut["dst"])
        im.save(dst)
        print("  %-14s %s  <- %s" % (cut["dst"], im.size, cut["src"]))
    print("wrote", OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
