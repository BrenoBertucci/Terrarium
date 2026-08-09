"""Read the sweep from tests/underpass_rail_probe.lua and say which height clears the rail.

Counted by COLOUR SIGNATURE, not by differencing. The corridor is amber
fittings, grey concrete and a red floor; the hazard band's yellow and the LED
run's blue are the only saturated hues in it, so each run can be counted in
its own frame. Differencing was tried first and measured the camera: the
frame does not hold still between shots, and a whole-frame diff came back in
the hundred-thousands for a run three pixels wide.

The CONTROL pair -- two shots of the same configuration -- is printed first.
Its counts are the noise floor; a sweep row that does not clear it by a wide
margin is not a signal.

    python tests/underpass_rail_report.py <probe-dir>
"""
import sys
import pathlib
import numpy as np
from PIL import Image


def signature(path):
    a = np.asarray(Image.open(path).convert("RGB")).astype(int)
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    # the hazard band: atlas texel (0.93, 0.74, 0.13), so red leads green
    # leads blue by a wide margin whatever the corridor's light does to it
    yellow = (R > 110) & (G > 70) & (B < G - 40) & (R > B + 70)
    # the LED: blue has to actually LEAD, which the amber corridor never does
    blue = (B > 90) & (B > R + 40) & (B > G + 15)
    return int(yellow.sum()), int(blue.sum())


def main():
    d = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    rows = []
    for p in sorted(d.glob("rail_*.png")):
        y, b = signature(p)
        rows.append((p.stem, y, b))

    def show(tag, keep):
        sel = [r for r in rows if keep(r[0])]
        if not sel:
            return
        print(f"\n=== {tag} ===")
        print(f"{'shot':<22}{'yellow px':>11}{'blue px':>10}")
        for name, y, b in sel:
            print(f"{name:<22}{y:>11}{b:>10}")

    show("control (noise floor)", lambda n: "control" in n)
    show("band sweep -- watch YELLOW", lambda n: "band" in n)
    show("LED sweep -- watch BLUE", lambda n: "strip" in n)

    ctrl = [r for r in rows if "control" in r[0]]
    if len(ctrl) == 2:
        print(f"\ncontrol spread: yellow {abs(ctrl[0][1] - ctrl[1][1])}, "
              f"blue {abs(ctrl[0][2] - ctrl[1][2])}")


if __name__ == "__main__":
    main()
