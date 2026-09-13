#!/usr/bin/env python3
"""Cut the powder burst a boot throws in a drift out of Pimen's Smoke n Dust 03.

The snow a walker kicks up was two authored stamps -- a grit speck and a soft
puff -- tinted white, and at a footstep's scale that reads as a couple of
commas by the boots rather than as snow being disturbed. This cuts a real
clip for it.

Source: `Smoke N Dust 03` (pimen.itch.io/smoke-n-dust-03), already downloaded
under tools/_vfx_dl/pimen for the wind sheets in 2026-09. Five strips came in
that pack; the wind row took VFX 1 (dust thrown up, wired and then turned OFF
-- WindFX.KICK) and VFX 5 (the wet puff). VFX 4 is the one nobody used, and it
is the right shape here: it starts as a clump at ground level and BLOOMS
outward into a cloud of separate specks, which is what powder does when a boot
goes through it. VFX 2 and 3 rise and drift instead, which is smoke.

Packs 02 and 04 are paid; nothing here buys anything.

    python cut_snow_burst.py

Writes assets/vfx/snow_burst.png -- the non-empty frames only, left to right.
A trailing empty frame in the source is a held beat in an animation player and
a wasted, invisible card here, so it goes (the same trim install_pimen_wind.py
makes, and for the same reason).
"""

import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "_vfx_dl", "pimen", "Smoke_N_Dust_03",
                   "SmokeNDust P03 VFX 4.png")
OUT = os.path.join(HERE, "..", "assets", "vfx", "snow_burst.png")
FW = 64


def main():
    if not os.path.isfile(SRC):
        print("missing source: %s" % SRC, file=sys.stderr)
        print("re-download Smoke n Dust 03 from pimen.itch.io (name your "
              "price) into tools/_vfx_dl/pimen/", file=sys.stderr)
        return 2

    sheet = Image.open(SRC).convert("RGBA")
    w, h = sheet.size
    if w % FW:
        print("%s is %dpx wide, not a whole number of %dpx frames"
              % (os.path.basename(SRC), w, FW), file=sys.stderr)
        return 1

    frames = []
    for i in range(w // FW):
        cell = sheet.crop((i * FW, 0, (i + 1) * FW, h))
        if cell.getbbox() is None:
            continue
        alpha = cell.split()[3]
        if max(alpha.getdata()) < 8:
            continue
        frames.append(cell)

    if not frames:
        print("every frame was empty", file=sys.stderr)
        return 1

    strip = Image.new("RGBA", (FW * len(frames), h), (0, 0, 0, 0))
    for i, cell in enumerate(frames):
        strip.paste(cell, (i * FW, 0))

    out = os.path.abspath(OUT)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    strip.save(out)
    print("source : %s" % SRC)
    print("wrote  : %s" % out)
    print("frames : %d of %d kept, %dx%d each"
          % (len(frames), w // FW, FW, h))
    return 0


if __name__ == "__main__":
    sys.exit(main())
