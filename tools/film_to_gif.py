# A probe's film (film_NNN.tga + film.txt with each frame's real time) to a
# GIF that plays at the speed it happened.
#
#   py tools/film_to_gif.py <dir> <out.gif> [width] [max_kb]
#
# Downscaled with Lanczos, one palette per frame (the water's gradients band
# badly on a shared one), frame durations from the real timestamps. If the
# result is over max_kb it steps the width down and tries again.
import os
import sys

from PIL import Image


def build(src, out, width):
    times = {}
    with open(os.path.join(src, "film.txt")) as f:
        for line in f:
            i, t = line.split()
            times[int(i)] = float(t)
    idx = sorted(i for i in times if os.path.exists(os.path.join(src, "film_%03d.tga" % i)))
    frames, durs = [], []
    for k, i in enumerate(idx):
        im = Image.open(os.path.join(src, "film_%03d.tga" % i)).convert("RGB")
        h = round(im.height * width / im.width)
        im = im.resize((width, h), Image.LANCZOS)
        frames.append(im.quantize(colors=255, method=Image.Quantize.MEDIANCUT,
                                  dither=Image.Dither.FLOYDSTEINBERG))
        nxt = times[idx[k + 1]] if k + 1 < len(idx) else times[i] + 1 / 15
        durs.append(max(20, round((nxt - times[i]) * 1000 / 10) * 10))
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=durs,
                   loop=0, optimize=False, disposal=1)
    return len(frames), sum(durs) / 1000


def main():
    src, out = sys.argv[1], sys.argv[2]
    width = int(sys.argv[3]) if len(sys.argv) > 3 else 768
    max_kb = int(sys.argv[4]) if len(sys.argv) > 4 else 15000
    while True:
        n, secs = build(src, out, width)
        kb = os.path.getsize(out) // 1024
        print("%s: %d frames, %.1f s, %dx?, %d KB" % (out, n, secs, width, kb))
        if kb <= max_kb or width <= 480:
            break
        width -= 96


if __name__ == "__main__":
    main()
