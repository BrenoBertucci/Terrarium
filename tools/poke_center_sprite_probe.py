"""Headless silhouette check for the Ulithium Center+Mart PNG.

Asserts the shipped sprite has a real opaque footprint so voxelization
has something to extrude. Does not need LOVE or the game.
"""
from __future__ import print_function
import os
import sys

try:
    from PIL import Image
except ImportError:
    sys.stderr.write("PIL/Pillow required\n")
    sys.exit(2)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REL = os.path.join("assets", "buildings", "ulithium_poke_center_mart.png")
PATH = os.path.join(ROOT, REL)

im = Image.open(PATH).convert("RGBA")
w, h = im.size
n = sum(1 for p in im.getdata() if p[3] > 10)
print("path", PATH)
print("size %dx%d mode=RGBA" % (w, h))
print("opaque", n, "of", w * h)
if n <= 1000:
    sys.stderr.write("FAIL silhouette %d <= 1000\n" % n)
    sys.exit(1)
print("ok")
