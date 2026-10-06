"""The houses of Cerulean and Celadon: the sheet, a check, and previews.

  python tools/town_houses.py --write            (re)paint assets/buildings/town_houses.png
  python tools/town_houses.py [name ...]         check the REAL kit (lib/TownHouseKit.lua)
                                                 under lupa and render tools/_kit_out/
                                                 town_<name>_{game,se}.png
  python tools/town_houses.py --town CERULEAN_CITY   one town's houses side by side

The sheet is STRIPS (lib/TownHouseKit.lua's header): a row per material,
128 texels of it, painted here BY NAME from the kit's own Kit.ROWS -- the kit
is the one list, and a name without a painter fails loudly. Alpha marks
light: 254 a window (lit after dark by a hash of its room), 253 a sign, a
neon, a furnace (always).

The check builds every house exactly as Buildings.emit will ask for it, and
asserts the door's lane (nothing below head height in the last tile row
across a door), the paving, and the sheet's bounds; it counts quads with
emit's own merge (a run of one texel, or of texels marching along a row).
Needs Pillow + numpy + lupa. No game process is touched.
"""
import math
import sys
from pathlib import Path

import numpy as np
from lupa import LuaRuntime
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
KIT = ROOT / "lib/TownHouseKit.lua"
SHEET = ROOT / "assets/buildings/town_houses.png"
OUT = ROOT / "tools/_kit_out"
W = 128
WINDOW, ALWAYS = 254, 253


# ------------------------------------------------------------------ painting --
def rng_for(name):
    return np.random.default_rng(sum(ord(c) * (i + 7) for i, c in enumerate(name)))


def clamp(c):
    return tuple(int(max(0, min(255, v))) for v in c)


def mul(c, f):
    return clamp(tuple(v * f for v in c))


def mix(a, b, t):
    return clamp(tuple(x + (y - x) * t for x, y in zip(a, b)))


def smooth_noise(r, n=W, period=16):
    """A row of low-frequency noise in -1..1 that wraps at 128."""
    k = n // period
    pts = r.uniform(-1, 1, k)
    out = []
    for u in range(n):
        f = u / period
        i = int(f) % k
        t = f - int(f)
        t = t * t * (3 - 2 * t)
        out.append(pts[i] * (1 - t) + pts[(i + 1) % k] * t)
    return out


def flat(rgb, var=0.035, a=255, blotch=0.03):
    def paint(name):
        r = rng_for(name)
        sn = smooth_noise(r)
        return [mul(rgb, 1 + (r.random() - 0.5) * var * 2 + sn[u] * blotch) + (a,) for u in range(W)]
    return paint


def brick_row(rgb, offset, length=8, joint=(196, 190, 178)):
    def paint(name):
        r = rng_for(name)
        tone = [1 + (r.random() - 0.5) * 0.16 for _ in range(W // length + 2)]
        out = []
        for u in range(W):
            k = (u + offset) % length
            if k == 0:
                out.append(mul(joint, 0.96 + r.random() * 0.06) + (255,))
                continue
            b = (u + offset) // length
            f = tone[b % len(tone)] * (1 + (r.random() - 0.5) * 0.07)
            if k == 1:
                f *= 1.06                      # the arris catches light
            out.append(mul(rgb, f) + (255,))
        return out
    return paint


def river_row(offset):
    stones = [(128, 140, 158), (112, 124, 144), (140, 146, 156), (100, 112, 132), (150, 156, 166)]

    def paint(name):
        r = rng_for(name)
        out, u = [], -offset
        cells = []
        while u < W + 8:
            w = int(r.integers(4, 8))
            cells.append((u, w, stones[int(r.integers(0, len(stones)))]))
            u += w
        for x in range(W):
            for (s, w, c) in cells:
                if s <= x < s + w:
                    k = x - s
                    if k == 0:
                        out.append((70, 76, 88, 255))
                    else:
                        edge = min(k, w - k) / (w / 2)
                        out.append(mul(c, 0.84 + 0.2 * edge + (r.random() - 0.5) * 0.06) + (255,))
                    break
        return out
    return paint


def ashlar_row(rgb, offset, length=12):
    def paint(name):
        r = rng_for(name)
        tone = [1 + (r.random() - 0.5) * 0.1 for _ in range(W // length + 2)]
        out = []
        for u in range(W):
            k = (u + offset) % length
            if k == 0:
                out.append(mul(rgb, 0.7) + (255,))
            else:
                out.append(mul(rgb, tone[((u + offset) // length) % len(tone)] * (1 + (r.random() - 0.5) * 0.05)) + (255,))
        return out
    return paint


def tile_row(rgb, offset, glaze=True, period=3):
    """A course of glazed pantile: a crest every `period` texels, a trough between."""
    def paint(name):
        r = rng_for(name)
        sn = smooth_noise(r, period=24)
        out = []
        for u in range(W):
            k = (u + offset) % period
            f = (1.12, 1.0, 0.82)[k] if period == 3 else (1.1 if k == 0 else 0.96)
            f *= 1 + sn[u] * 0.05 + (r.random() - 0.5) * 0.05
            c = mul(rgb, f)
            if glaze and k == 0 and r.random() < 0.18:
                c = mix(c, (255, 255, 255), 0.35)          # a glint on the glaze
            out.append(c + (255,))
        return out
    return paint


def stripes(colors, width, a=255):
    def paint(name):
        r = rng_for(name)
        out = []
        for u in range(W):
            c = colors[(u // width) % len(colors)]
            out.append(mul(c, 1 + (r.random() - 0.5) * 0.04) + (a,))
        return out
    return paint


def lattice(k, tile, line, light, a_tile=255, a_line=255):
    """Row k (0..7) of the drawing's diamond lattice: lines where (u +- k) % 8 == 0."""
    def paint(name):
        r = rng_for(name)
        out = []
        for u in range(W):
            p, q = (u + k) % 8, (u - k) % 8
            if p == 0 or q == 0:
                out.append(mul(line, 1 + (r.random() - 0.5) * 0.05) + (a_line,))
                continue
            # each diamond lit from the upper left: its upper half brighter
            upper = (p + q) < 8
            c = light if (upper and (p < 3 or q < 3)) else tile
            out.append(mul(c, 1 + (r.random() - 0.5) * 0.05) + (a_tile,))
        return out
    return paint


def glass_row(base, hi, a=WINDOW, streak=11):
    def paint(name):
        r = rng_for(name)
        out = []
        for u in range(W):
            k = u % streak
            t = 0.55 if k in (2, 3) else (0.25 if k == 4 else 0.0)
            out.append(mix(base, hi, t + (r.random() - 0.5) * 0.06) + (a,))
        return out
    return paint


def speckle(base, specks, density=0.18, a=255):
    def paint(name):
        r = rng_for(name)
        out = []
        for u in range(W):
            if r.random() < density:
                out.append(specks[int(r.integers(0, len(specks)))] + (a,))
            else:
                out.append(mul(base, 1 + (r.random() - 0.5) * 0.06) + (a,))
        return out
    return paint


def pattern(fn, a=255):
    def paint(name):
        r = rng_for(name)
        return [clamp(fn(u, r)) + (a if not callable(a) else a(u),) for u in range(W)]
    return paint


def crack(u, r):
    if u % 17 in (3, 9) or u % 23 == 5:
        return (236, 242, 246)
    return mix((96, 134, 164), (170, 200, 220), 0.2 + (u % 11 < 3) * 0.4)


# jade: glazed tiles six wide, a grout line, the left texel catching light
def jade(offset):
    def fn(u, r):
        k = (u + offset) % 6
        if k == 0:
            return (206, 222, 212)
        base = (104, 176, 142)
        f = 1.12 if k == 1 else (0.9 if k == 5 else 1.0)
        return mul(base, f * (1 + (r.random() - 0.5) * 0.06))
    return pattern(fn)


RAINBOW = [(228, 64, 64), (240, 142, 56), (246, 208, 72), (96, 186, 96), (72, 150, 222), (88, 96, 196), (156, 94, 192)]

PAINTERS = {
    "pave_cel": flat((214, 214, 208), 0.03), "joint_cel": flat((158, 160, 156), 0.03),
    "pave_cer": flat((222, 224, 222), 0.03), "joint_cer": flat((170, 176, 184), 0.03),
    "stucco_white": flat((240, 238, 230), 0.02, blotch=0.025), "stucco_cream": flat((238, 226, 196), 0.02),
    "stucco_sky": flat((206, 226, 240), 0.02), "stucco_mint": flat((206, 236, 216), 0.02),
    "stucco_rose": flat((240, 206, 204), 0.02), "render_white": flat((246, 246, 244), 0.015, blotch=0.01),
    "render_grey": flat((176, 180, 184), 0.02),
    "brick_red_a": brick_row((172, 82, 62), 0), "brick_red_b": brick_row((172, 82, 62), 4),
    "brick_buff_a": brick_row((222, 190, 140), 0), "brick_buff_b": brick_row((222, 190, 140), 4),
    "brick_dark_a": brick_row((112, 70, 66), 0, joint=(150, 140, 132)),
    "brick_dark_b": brick_row((112, 70, 66), 4, joint=(150, 140, 132)),
    "brick_blue_a": brick_row((104, 128, 168), 0, joint=(200, 208, 220)),
    "brick_blue_b": brick_row((104, 128, 168), 4, joint=(200, 208, 220)),
    "brick_cream_a": brick_row((238, 226, 198), 0, joint=(186, 178, 164)),
    "brick_cream_b": brick_row((238, 226, 198), 4, joint=(186, 178, 164)),
    "mortar": flat((196, 190, 178), 0.04), "mortar_dk": flat((140, 134, 126), 0.04),
    "jade_a": jade(0), "jade_b": jade(3), "jade_grout": flat((206, 222, 212), 0.03),
    "river_a": river_row(0), "river_b": river_row(3), "river_joint": flat((84, 90, 102), 0.04),
    "ashlar_a": ashlar_row((212, 196, 166), 0), "ashlar_b": ashlar_row((212, 196, 166), 6),
    "ashlar_joint": flat((150, 138, 116), 0.04),
    "koshi": pattern(lambda u, r: (58, 40, 30) if u % 3 == 2 else mul((104, 72, 50), 1 + (r.random() - .5) * .08)),
    "shoji": pattern(lambda u, r: (78, 54, 38) if u % 4 == 0 else mul((244, 236, 214), 1 + (r.random() - .5) * .03),
                     a=lambda u: 255 if u % 4 == 0 else WINDOW),
    "board": flat((156, 112, 76), 0.08), "board_line": flat((92, 62, 42), 0.05),
    "wood": flat((150, 106, 70), 0.1, blotch=0.06), "wood_dk": flat((96, 64, 44), 0.08),
    "wood_lt": flat((200, 162, 112), 0.08),
    "bamboo": pattern(lambda u, r: (120, 140, 60) if u % 7 == 0 else mul((178, 188, 96), 1 + (r.random() - .5) * .08)),
    "marble_green": pattern(lambda u, r: mix((70, 140, 110), (210, 236, 222), 0.5 + 0.5 * math.sin(u * 0.45 + math.sin(u * 0.13) * 3) ** 9)),
    "terrazzo": speckle((226, 220, 208), [(140, 130, 120), (190, 110, 90), (90, 140, 120), (240, 240, 236)], 0.25),
    "lacquer_red": pattern(lambda u, r: mul((178, 36, 40), 1.18 if u % 13 in (4, 5) else 1 + (r.random() - .5) * .05)),
    "black_gloss": pattern(lambda u, r: (70, 70, 84) if u % 13 in (4, 5) else mul((30, 30, 38), 1 + (r.random() - .5) * .1)),
    "chrome": pattern(lambda u, r: mix((120, 128, 140), (250, 252, 255), 0.5 + 0.5 * math.sin(u * 0.9))),
    "violet": flat((92, 60, 130), 0.05),
    "trim_white": flat((250, 250, 246), 0.015, blotch=0.01), "trim_cream": flat((244, 234, 208), 0.02),
    "dentil": pattern(lambda u, r: (250, 246, 234) if u % 3 else (168, 160, 146)),
    "frieze_gold": pattern(lambda u, r: (250, 214, 110) if u % 4 in (0, 1) else (196, 150, 64)),
    "glass": glass_row((88, 128, 164), (196, 222, 238)),
    "glass_shop": glass_row((120, 160, 184), (228, 240, 246), streak=9),
    "glass_dark": glass_row((40, 52, 70), (110, 130, 150)),
    "glass_crack": pattern(crack, a=WINDOW),
    "sign_lit": flat((255, 238, 176), 0.02, a=ALWAYS), "neon_pink": flat((255, 90, 196), 0.03, a=ALWAYS),
    "neon_cyan": flat((96, 236, 255), 0.03, a=ALWAYS), "neon_red": flat((255, 70, 64), 0.03, a=ALWAYS),
    "neon_green": flat((120, 255, 140), 0.03, a=ALWAYS), "neon_yellow": flat((255, 230, 90), 0.03, a=ALWAYS),
    "bulbs": pattern(lambda u, r: (255, 232, 150) if u % 3 == 0 else (120, 90, 60),
                     a=lambda u: ALWAYS if u % 3 == 0 else 255),
    "lantern_red": flat((236, 74, 60), 0.05, a=ALWAYS),
    "furnace": pattern(lambda u, r: mix((255, 120, 30), (255, 220, 120), r.random()), a=ALWAYS),
    "bottle_glow": pattern(lambda u, r: [(70, 150, 230), (60, 200, 210), (100, 200, 120), (220, 170, 70), (120, 110, 220)][u % 5], a=ALWAYS),
    "tcer_a": tile_row((62, 124, 204), 0), "tcer_b": tile_row((62, 124, 204), 1), "tcer_line": flat((30, 66, 124), 0.05),
    "tslate_a": tile_row((96, 110, 138), 0, glaze=False), "tslate_b": tile_row((96, 110, 138), 1, glaze=False),
    "tslate_line": flat((52, 60, 78), 0.05),
    "tindigo_a": tile_row((70, 70, 150), 0), "tindigo_b": tile_row((70, 70, 150), 1), "tindigo_line": flat((36, 34, 88), 0.05),
    "tteal_a": tile_row((50, 140, 150), 0), "tteal_b": tile_row((50, 140, 150), 1), "tteal_line": flat((24, 76, 86), 0.05),
    "tsky_a": tile_row((110, 170, 228), 0), "tsky_b": tile_row((110, 170, 228), 1), "tsky_line": flat((56, 104, 160), 0.05),
    "tnavy_a": tile_row((46, 62, 116), 0), "tnavy_b": tile_row((46, 62, 116), 1), "tnavy_line": flat((24, 30, 62), 0.05),
    "kawara_a": tile_row((96, 100, 108), 0, glaze=False, period=4), "kawara_b": tile_row((96, 100, 108), 2, glaze=False, period=4),
    "kawara_line": flat((48, 50, 56), 0.05),
    "tjade_a": tile_row((96, 170, 136), 0), "tjade_b": tile_row((96, 170, 136), 1), "tjade_line": flat((46, 100, 76), 0.05),
    "ridge_blue": pattern(lambda u, r: (64, 104, 170) if u % 4 == 0 else (34, 60, 112)),
    "ridge_dark": pattern(lambda u, r: (84, 90, 104) if u % 4 == 0 else (48, 52, 62)),
    "ridge_jade": pattern(lambda u, r: (140, 206, 170) if u % 4 == 0 else (60, 120, 92)),
    "fascia": flat((244, 246, 248), 0.015),
    "gravel": speckle((150, 152, 150), [(120, 122, 120), (180, 180, 176), (100, 102, 104)], 0.4),
    "tar": flat((70, 72, 78), 0.06), "lead": flat((136, 144, 152), 0.04),
    "deck": pattern(lambda u, r: (104, 72, 50) if u % 5 == 0 else mul((170, 124, 84), 1 + (r.random() - .5) * .1)),
    "grass": flat((98, 170, 84), 0.1, blotch=0.06), "grass_dk": flat((70, 136, 70), 0.1),
    "soil": flat((110, 80, 56), 0.12), "leaf": flat((84, 158, 80), 0.14, blotch=0.08),
    "leaf_dk": flat((52, 116, 62), 0.12), "leaf_lt": flat((140, 196, 96), 0.12),
    "moss": flat((110, 150, 80), 0.12), "sand": flat((232, 226, 208), 0.03), "sand_line": flat((204, 196, 176), 0.03),
    "rock": flat((120, 118, 114), 0.12, blotch=0.1),
    "water": pattern(lambda u, r: mix((70, 150, 200), (170, 220, 240), 0.5 + 0.5 * math.sin(u * 0.7) ** 5)),
    "water_dk": flat((44, 96, 140), 0.06),
    "fl_red": speckle((222, 60, 64), [(250, 230, 110)], 0.1), "fl_pink": speckle((246, 140, 186), [(255, 236, 140)], 0.1),
    "fl_yellow": speckle((250, 214, 70), [(200, 120, 40)], 0.1), "fl_white": speckle((248, 246, 240), [(250, 214, 90)], 0.1),
    "fl_purple": speckle((156, 96, 200), [(240, 220, 120)], 0.1), "fl_blue": speckle((96, 136, 232), [(255, 255, 255)], 0.1),
    "fl_orange": speckle((246, 140, 50), [(255, 220, 120)], 0.1),
    "cloth_indigo": flat((50, 56, 130), 0.05, blotch=0.08), "cloth_cer": flat((56, 140, 222), 0.05, blotch=0.08),
    "cloth_sky": flat((150, 204, 244), 0.04, blotch=0.06), "cloth_teal": flat((50, 150, 160), 0.05, blotch=0.06),
    "cloth_white": flat((246, 246, 242), 0.02, blotch=0.03), "cloth_red": flat((200, 54, 56), 0.05, blotch=0.06),
    "canvas": flat((222, 210, 180), 0.05),
    "awn_bw": stripes([(60, 118, 204), (248, 248, 244)], 4), "awn_rw": stripes([(206, 56, 56), (248, 246, 240)], 4),
    "awn_gw": stripes([(64, 150, 100), (248, 246, 240)], 4), "awn_rainbow": stripes(RAINBOW, 3),
    "tape": stripes([(250, 210, 40), (30, 30, 30)], 3), "tarp": pattern(lambda u, r: mul((40, 120, 230), 0.86 if u % 9 == 0 else 1.0 + (r.random() - .5) * .05)),
    "white": flat((250, 250, 250), 0.015), "black": flat((32, 32, 36), 0.05), "iron": flat((66, 70, 80), 0.05),
    "steel": flat((170, 176, 186), 0.05), "red": flat((210, 56, 56), 0.04), "yellow": flat((248, 204, 60), 0.04),
    "orange": flat((244, 128, 44), 0.04), "green": flat((64, 150, 84), 0.04), "blue": flat((60, 110, 210), 0.04),
    "purple": flat((130, 80, 180), 0.04), "pink": flat((244, 150, 190), 0.04), "gold": pattern(lambda u, r: mix((200, 150, 50), (255, 228, 130), 0.5 + 0.5 * math.sin(u * 1.3))),
    "brass": flat((206, 168, 84), 0.05), "copper": flat((190, 110, 70), 0.06), "verdigris": flat((96, 176, 150), 0.06),
    "navy": flat((40, 52, 100), 0.04), "cream": flat((244, 232, 204), 0.03), "brown": flat((120, 90, 60), 0.06),
    "shadow": flat((36, 34, 40), 0.03),
    "rb_1": flat(RAINBOW[0], 0.03), "rb_2": flat(RAINBOW[1], 0.03), "rb_3": flat(RAINBOW[2], 0.03),
    "rb_4": flat(RAINBOW[3], 0.03), "rb_5": flat(RAINBOW[4], 0.03), "rb_6": flat(RAINBOW[5], 0.03),
    "rb_7": flat(RAINBOW[6], 0.03),
    "poster_a": pattern(lambda u, r: (250, 250, 250) if u % 10 == 0 else [(230, 80, 70), (250, 200, 80), (60, 60, 90)][(u // 3) % 3]),
    "poster_b": pattern(lambda u, r: (250, 250, 250) if u % 10 == 0 else [(70, 140, 220), (240, 240, 230), (240, 120, 160)][(u // 3) % 3]),
    "poster_c": pattern(lambda u, r: (250, 250, 250) if u % 10 == 0 else [(90, 180, 110), (250, 220, 120), (60, 70, 120)][(u // 3) % 3]),
    "books": pattern(lambda u, r: [(170, 60, 50), (60, 90, 150), (220, 190, 110), (70, 120, 80), (120, 70, 120), (230, 230, 220)][int((u * 7 + u // 3) % 6)]),
    "bread": pattern(lambda u, r: (240, 200, 130) if u % 5 == 2 else mul((196, 132, 64), 1 + (r.random() - .5) * .1)),
    "vase_cel": pattern(lambda u, r: (80, 128, 104) if r.random() < 0.07 else mul((150, 206, 176), 1 + (r.random() - .5) * .05)),
    "record": pattern(lambda u, r: (70, 70, 80) if u % 2 else (22, 22, 26)),
}
for name, (tile, line, light) in {"jade": ((146, 206, 176), (78, 134, 110), (184, 232, 206)),
                                  "blue": ((130, 168, 228), (56, 86, 150), (176, 204, 244))}.items():
    for k in range(8):
        PAINTERS[f"lat_{name}_{k}"] = lattice(k, tile, line, light)
for k in range(8):
    PAINTERS[f"sky_{k}"] = lattice(k, (120, 176, 196), (70, 80, 92), (190, 226, 238), a_tile=WINDOW)


def load_kit():
    lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
    kit = lua.eval("function(p) return assert(loadfile(p))() end")(KIT.as_posix().encode())
    return lua, kit


def paint():
    _, kit = load_kit()
    rows = [kit.ROWS[i + 1].decode() for i in range(len(kit.ROWS))]
    missing = [n for n in rows if n not in PAINTERS]
    assert not missing, f"rows without a painter: {missing}"
    img = Image.new("RGBA", (W, len(rows)))
    px = img.load()
    for y, name in enumerate(rows):
        texels = PAINTERS[name](name)
        assert len(texels) == W, name
        for u, c in enumerate(texels):
            px[u, y] = c
    img.save(SHEET)
    print("wrote", SHEET, img.size)


# ------------------------------------------------------------------ checking --
PACK = """
function(m)
  local out, n, floor = {}, 0, math.floor
  for y = 0, m.ytop do
    for z = 0, m.zmax do
      for x = 0, m.xmax do
        local v = m.at(x, y, z)
        local k = v and (floor(v) + 1) or 0
        n = n + 1
        out[n] = string.char(k % 256, floor(k / 256))
      end
    end
  end
  return table.concat(out)
end
"""


def voxels(lua, model):
    raw = lua.eval(PACK)(model)
    ny, nz, nx = int(model.ytop) + 1, int(model.zmax) + 1, int(model.xmax) + 1
    return np.frombuffer(raw, dtype="<u2").astype(np.int32).reshape(ny, nz, nx) - 1


def count_quads(grid):
    """Buildings.emit's merge: runs of one texel, or of texels marching one along a row."""
    solid = grid >= 0
    pad = np.pad(solid, 1)
    n = 0
    for (dy, dz, dx), axis in (((1, 0, 0), 2), ((-1, 0, 0), 2), ((0, 1, 0), 2), ((0, -1, 0), 2),
                               ((0, 0, 1), 1), ((0, 0, -1), 1)):
        nb = pad[1 + dy:pad.shape[0] - 1 + dy, 1 + dz:pad.shape[1] - 1 + dz, 1 + dx:pad.shape[2] - 1 + dx]
        face = solid & ~nb
        if dy == -1:
            face[0] = False
        key = np.where(face, grid, -10)
        prev = np.roll(key, 1, axis=axis)
        prev2 = np.roll(key, 2, axis=axis)
        pf = np.roll(face, 1, axis=axis)
        if axis == 2:
            prev[:, :, 0] = -10; prev2[:, :, :2] = -10; pf[:, :, 0] = False
        else:
            prev[:, 0, :] = -10; prev2[:, :2, :] = -10; pf[:, 0, :] = False
        same_row = (key // W) == (prev // W)
        d = key - prev
        cont = pf & same_row & ((d == 0) | (d == 1))
        # a run is flat or a strip, not both: a change of step starts a new quad
        d2 = prev - prev2
        cont &= ~((d != d2) & (np.roll(cont, 1, axis=axis)))
        n += int((face & ~cont).sum())
    return n


def shade(rgb, f):
    return tuple(min(255, int(c * f)) for c in rgb)


def game_view(grid, sheet, scale=5, elev=48):
    """Square on from the south and above, as the game's camera leans."""
    ny, nz, nx = grid.shape
    s, c = math.sin(math.radians(elev)), math.cos(math.radians(elev))
    solid = grid >= 0
    pad = np.pad(solid, 1)
    top = solid & ~pad[2:, 1:-1, 1:-1]
    south = solid & ~pad[1:-1, 2:, 1:-1]
    H = int((nz * s + ny * c) * scale) + 8
    img = Image.new("RGB", (nx * scale + 8, H), (150, 172, 186))
    draw = ImageDraw.Draw(img)
    oy = ny * c * scale + 4

    def Y(y, z):
        return oy + (z * s - y * c) * scale

    faces = []
    for (y, z, x) in zip(*np.nonzero(top | south)):
        depth = y * s + z * c
        faces.append((depth, y, z, x))
    faces.sort()
    for _, y, z, x in faces:
        rgb = sheet[grid[y, z, x]]
        x0, x1 = 4 + x * scale, 4 + (x + 1) * scale
        if top[y, z, x]:
            ao = 1.0
            if y + 1 < ny and ((z > 0 and solid[y + 1, z - 1, x]) or (x > 0 and solid[y + 1, z, x - 1])):
                ao = 0.86
            draw.rectangle([x0, Y(y + 1, z), x1 - 1, Y(y + 1, z + 1)], fill=shade(rgb, ao))
        if south[y, z, x]:
            draw.rectangle([x0, Y(y + 1, z + 1), x1 - 1, Y(y, z + 1)], fill=shade(rgb, 0.8))
    return img


def iso(grid, sheet, scale=3):
    ny, nz, nx = grid.shape
    solid = grid >= 0
    pad = np.pad(solid, 1)
    w = (nx + nz) * scale + 8
    h = (nx + nz) * scale // 2 + ny * scale + 8
    img = Image.new("RGB", (w, h), (150, 172, 186))
    draw = ImageDraw.Draw(img)
    ox, oy = nz * scale + 4, ny * scale + 4

    def P(x, y, z):
        return (ox + (x - z) * scale, oy + (x + z) * scale / 2 - y * scale)

    seen = solid & ~(pad[2:, 1:-1, 1:-1] & pad[1:-1, 2:, 1:-1] & pad[1:-1, 1:-1, 2:])
    for y, z, x in sorted(zip(*np.nonzero(seen)), key=lambda v: (v[2] + v[1], v[0])):
        r, g, b = sheet[grid[y, z, x]]
        if not pad[y + 2, z + 1, x + 1]:
            draw.polygon([P(x, y + 1, z), P(x + 1, y + 1, z), P(x + 1, y + 1, z + 1), P(x, y + 1, z + 1)], fill=(r, g, b))
        if not pad[y + 1, z + 2, x + 1]:
            draw.polygon([P(x, y, z + 1), P(x + 1, y, z + 1), P(x + 1, y + 1, z + 1), P(x, y + 1, z + 1)], fill=shade((r, g, b), 0.80))
        if not pad[y + 1, z + 1, x + 2]:
            draw.polygon([P(x + 1, y, z), P(x + 1, y, z + 1), P(x + 1, y + 1, z + 1), P(x + 1, y + 1, z)], fill=shade((r, g, b), 0.62))
    return img


def tiles_of(lua, w, h):
    return lua.eval("function(w, h) local t = {} for r = 1, h do t[r] = {} for c = 1, w do t[r][c] = 1 end end return t end")(w, h)


def check(only, town):
    png = Image.open(SHEET).convert("RGBA")
    lua, kit = load_kit()
    rows = int(kit.SHEET_H)
    assert png.size == (W, rows), (png.size, rows, "run --write")
    sheet = [png.getpixel((i % W, i // W))[:3] for i in range(W * rows)]
    sp = lua.eval("function(w, h) return { W = w, H = h } end")(W, rows)
    OUT.mkdir(exist_ok=True)
    total = 0
    strips = {}
    for mapId, places in kit.PLACES.items():
        mapId = mapId.decode()
        if town and mapId != town:
            continue
        for key, p in sorted(places.items(), key=lambda kv: kv[1][1]):
            key = key.decode()
            name, tw, th = p[1].decode(), int(p[2]), int(p[3])
            if only and name not in only:
                continue
            tx, ty = map(int, key.split(":"))
            t = lua.eval("function(tiles) return { id = \"x\", tiles = tiles } end")(tiles_of(lua, tw, th))
            model = kit.model(sp, t, tx, ty, mapId.encode())
            if isinstance(model, tuple):
                raise SystemExit(f"{name}: {model[1]}")
            assert model is not None, name
            grid = voxels(lua, model)
            solid = grid >= 0
            assert (grid < W * rows).all(), f"{name}: a texel past the sheet"
            PD = th * 8
            assert solid[0].all(), f"{name}: the plot's paving has a hole in it"
            if model.lanes:
                for lane in model.lanes.values():
                    x0, x1 = int(lane[1]), int(lane[2])
                    bad = solid[1:18, PD - 8:, x0:x1 + 1]
                    assert not bad.any(), f"{name}: {int(bad.sum())} voxels stand in the door lane x {x0}..{x1}"
            q = count_quads(grid)
            total += q
            print(f"{mapId[:8]} {name:12s} {tw * 8}x{PD} top {int(np.nonzero(solid)[0].max()):3d}  "
                  f"{int(solid.sum()):7d} voxels  {q:6d} quads")
            gv = game_view(grid, sheet)
            gv.save(OUT / f"town_{name}_game.png")
            iso(grid, sheet, 3 if tw * th < 80 else 2).save(OUT / f"town_{name}_se.png")
            strips.setdefault(mapId, []).append(gv)
    for mapId, views in strips.items():
        wmax = max(v.width for v in views)
        hsum = sum(v.height for v in views) + 6 * len(views)
        sheet_img = Image.new("RGB", (wmax, hsum), (30, 30, 36))
        y = 0
        for v in views:
            sheet_img.paste(v, (0, y))
            y += v.height + 6
        sheet_img.save(OUT / f"town_{mapId}.png")
    print(f"PASS  {total} quads ->", OUT / "town_*.png")


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--write" in args:
        paint()
    town = None
    if "--town" in args:
        town = args[args.index("--town") + 1]
    names = [a for i, a in enumerate(args) if not a.startswith("--") and (i == 0 or args[i - 1] != "--town")]
    check(names or None, town)
