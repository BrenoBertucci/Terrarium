"""Author the Poke Mart interior's TEXEL SHEET (assets/shop/shop_sheet.png).

The Mart's tileset is four greys under one flat palette. A voxel wears a
texel of whatever atlas its model was read from, so a room built off the
tileset can only ever be a grey box -- which is exactly what the old
lib/RoomKit.lua Mart was. The facade solved this in 2026-09 by standing the
building on an authored RGBA sheet (tools/mart_facade.py); the interior does
the same, one texel per voxel, and gets real colour for free.

THE SHEET IS A CONTRACT. lib/ShopKit.lua indexes it by the swatch table
below and refuses to build (falling back to RoomKit) if the PNG's size does
not match SHEET_W/SHEET_H. Bands are 16 rows tall and each band is ONE
MATERIAL, because lib/Voxel3D.lua's shop materials pick the photo detail to
modulate from the texel's v alone -- a 1-D lookup, no branching on u.

    band  rows      material          contents
    0     0.. 15    wall plaster      paint, skirting, cornice, case backing
    1    16.. 31    flat/emissive     ceiling panel, light diffuser, vent
    2    32.. 47    painted metal     shelf uprights, boards, cabinets, kick
    3    48.. 63    wood laminate     counter top, front, edge band
    4    64.. 79    glass             cooler and case panes, mullion, glow
    5    80..127    none (flat art)   products, 8x8 faces, 32 x 6 grid
    6   128..255    none (flat art)   signage, register, basket, mat, boxes

Photo grain comes from the Poly Haven CC0 textures in assets/shop/ when they
are present (assets/shop/README.md says which): each band's swatches are the
authored colour MODULATED by a crop of the matching photo, normalised so the
mean is the authored colour exactly. Without them the sheet is flat colour
and the room still builds -- the shader's material pass is the other half of
the detail either way.

    python tools/shop_sheet.py                 # write assets/shop/shop_sheet.png
    python tools/shop_sheet.py --preview p.png # x6 preview with swatch labels
    python tools/shop_sheet.py --check         # verify the shipped PNG matches
"""
import argparse
import hashlib
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SHOP = ROOT / "assets" / "shop"
OUT = SHOP / "shop_sheet.png"

SHEET_W, SHEET_H = 256, 256

# ------------------------------------------------------------- the palette --
#
# A konbini under fluorescent light: warm off-white walls, cool steel, one
# saturated brand blue on the counter front, and products that are the only
# strong colour in the room. Hex here, so a retune is one table.
# ------- the two families, and why they are two
#
# Measured on the shipped frames (assets/docs/shop/DRESSING.md): 52.6 % of
# the room sat in the top value decile, 75 % under saturation 0.10, and one
# swatch -- #F8F8F8 -- owned 25.2 % of it. Nine surfaces that are different
# objects were reading as ONE 46 % mass, which is most of what "the room
# looks like a white box" actually is. No amount of chamfering fixes that:
# a silhouette needs two values on either side of it to be a silhouette.
#
# So the palette is split, and the split is the room's own physics:
#
#   THE SHELL   walls, cornice, ceiling, counter edge. Painted plaster and
#               laminate under a ceiling of tubes: WARM and the palest
#               thing in the room, because it is what the light lands on.
#   THE FIXTURES gondolas, cabinets, cases, uprights, housings. Powder
#               coated steel: COOL, and a full stop darker. In a real
#               fitout the shelving is always darker than the wall behind
#               it -- that is how a shop reads as depth rather than as a
#               diagram, and it is free.
PAL = {
    "paint":      "#E9E5DB",
    "paint_dim":  "#DCD8CE",   # the wall behind the cases, in their shadow
    "skirt":      "#6F6B64",
    "cornice":    "#F4F1EA",
    "cornice_sh": "#C6C2B9",   # the shadow line under it
    "ceiling":    "#F2F0EC",
    "diffuser":   "#FFFDF2",   # emissive
    "housing":    "#AEB6BE",
    "vent":       "#9AA0A6",
    "steel":      "#98A3AD",
    "steel_dark": "#6B7077",
    "board":      "#BCC5CD",
    "board_lip":  "#8E949B",
    "cabinet":    "#AAB4BD",
    "kick":       "#4E5257",
    "laminate":   "#D8C3A0",
    "counter_fr": "#2E5FA3",   # the Mart's blue
    "counter_ed": "#EAE5DA",
    "glass_cool": "#B9D6E6",
    "glass_case": "#C3D9E5",
    "mullion":    "#8E969C",
    "glow":       "#E4F2FA",   # emissive, the cooler's interior
    # An entrance mat is dark, but this one was #3A3D42 over 44 x 15 voxels
    # -- the largest dark mass in the room by a wide margin, and at that
    # value it stopped being a mat and became a hole in the floor. Lifted
    # to a wet-slate grey, where the rib pattern can actually be seen.
    "mat":        "#585D66",
    "mat_rib":    "#4A4F57",
    "card":       "#C39A63",   # cardboard
    "leaf":       "#4E7A43",   # the planter: the only green in the room
    "leaf_lit":   "#6D9C56",
    "terracotta": "#9C6248",
    "bin":        "#33383E",   # the dark mass the room has none of
    "bin_lid":    "#4A5058",
    "ext_red":    "#A8241E",
    # THE BALLS, sampled from assets/battlexy/items/*_BALL.png rather than
    # invented -- those are the sprites the battle bag already ships, so
    # the shelf and the bag agree about what a Great Ball looks like.
    "ball_lid0":  "#FF9439",   # Poke
    "ball_shd0":  "#DE5A39",
    "ball_lid1":  "#3994FF",   # Great
    "ball_shd1":  "#3152D6",
    "ball_lid2":  "#FFFF00",   # Ultra
    "ball_shd2":  "#CEBD29",
    "ball_belt":  "#4A5252",
    "ball_belt2": "#313131",
    "ball_base":  "#DECEF7",
    "ball_base2": "#A5A5C6",
    "sign_blue":  "#1F4E8C",
    "sign_white": "#F6F6F2",
    "sign_red":   "#D23B33",
    "screen":     "#1D2A22",
    "screen_lit": "#7FE0A8",
}

# Products: (name, body, cap, label). The label band is the stripe across
# the middle of the face -- what reads at four screen pixels is the STRIPE,
# not the drawing, so every product is a body colour with one contrasting
# band and a lighter cap.
PRODUCTS = [
    ("potion",       "#E24B3C", "#F5F2EC", "#F5F2EC"),
    ("super_potion", "#F0932B", "#F5F2EC", "#F5F2EC"),
    ("hyper_potion", "#E05A8A", "#F5F2EC", "#F5F2EC"),
    ("antidote",     "#8E44AD", "#EDE4F2", "#EDE4F2"),
    ("paralyz_heal", "#E8C33C", "#5A4A18", "#5A4A18"),
    ("awakening",    "#4A7FD4", "#EAF0FA", "#EAF0FA"),
    ("burn_heal",    "#D9622C", "#F7E6D6", "#F7E6D6"),
    ("ice_heal",     "#6FC5D8", "#F0FAFC", "#F0FAFC"),
    ("poke_ball",    "#D33B3B", "#F2F2F2", "#2B2B2B"),
    ("great_ball",   "#2B6BD4", "#F2F2F2", "#2B2B2B"),
    ("ultra_ball",   "#E8B33C", "#2B2B2B", "#F2F2F2"),
    ("repel",        "#7FBF52", "#F0F7E8", "#F0F7E8"),
    ("super_repel",  "#4E9E58", "#F0F7E8", "#F0F7E8"),
    ("escape_rope",  "#B98A5A", "#F2E6D6", "#3A2A18"),
    ("tm_box",       "#4FB0A5", "#E6F7F5", "#204640"),
    ("soda",         "#C43A5A", "#F4E2E6", "#F4E2E6"),
    ("lemonade",     "#EBD25A", "#FAF4D8", "#6A5A18"),
    ("fresh_water",  "#5AA8E0", "#E6F4FC", "#E6F4FC"),
    ("milk",         "#F0EDE2", "#D8CFB8", "#3A3A32"),
    ("bento",        "#D8894A", "#F2DCC2", "#3A2A18"),
    ("onigiri",      "#EFEAD8", "#2E3A2E", "#2E3A2E"),
    ("candy",        "#E86FA8", "#FBE4EF", "#FBE4EF"),
    ("chips",        "#E8B33C", "#B03A2A", "#B03A2A"),
    ("noodles",      "#E2603C", "#F4E0C8", "#F4E0C8"),
]

# Which Poly Haven graded albedo lends each band its grain, and how strongly
# (0 = flat colour, 1 = the photo's own contrast). Missing file -> flat.
# Re-pointed at the deeper grades. The old set modulated 1.4-5.6 % and the
# sheet was baking a grain nothing could see; these run 7.5-8.8 %
# (tools/surface_pick.py depth). Same bands, same strengths.
GRAIN = {
    0: ("ceiling_tile.jpg",  0.55),
    1: ("ceiling_tile.jpg",  0.35),
    2: ("steel_brushed.jpg", 0.70),
    3: ("wood_light.jpg",    0.85),
    4: ("floor_tile.jpg",    0.25),
}

BAND_ROWS = 16
BANDS = {"wall": 0, "ceil": 1, "steel": 2, "wood": 3, "glass": 4}
PROD_Y0, PROD_CELL, PROD_COLS = 80, 8, 32
# rows 0..1 of a product cell are the LID; prodFit in lib/ShopKit.lua skips
# them and samples 2..7, so art laid in a cell has to start there too.
PROD_TOP_ROWS = 2
ART_Y0 = 128


# ---------------------------------------------------------------- helpers --

def rgb(name):
    h = PAL[name].lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64)


def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64)


def draw_ball(s, x, y, k):
    """A ball drawn into a product cell, banded to the rows prodFit reads.

    Reducing the 160x160 bag sprite straight into the cell was tried first
    and does not survive the sampling: `prodFit` maps a THREE-voxel facing
    onto art rows 0, 2 and 4, and row 0 of a boxed-down sprite is its own
    black outline -- so every ball on the shelf wore a dark cap, which is
    the one face this camera always sees.

    So the rows are authored instead, in the sprite's own sampled palette
    (assets/battlexy/items/*_BALL.png):

        0  lid          1  lid, shaded
        2  belt + button    3  belt
        4  base         5  base, shaded

    Any three-row sampling of that -- 0/2/4 or 1/3/5 -- comes out lid,
    belt, base, which is a Poke Ball at any size a shelf can show one.
    """
    lid = (rgb("ball_lid%d" % k), rgb("ball_shd%d" % k))
    belt = (rgb("ball_belt"), rgb("ball_belt2"))
    base = (rgb("ball_base"), rgb("ball_base2"))
    for r, (a, b) in ((0, lid), (2, belt), (4, base)):
        s.fill(x, y + PROD_TOP_ROWS + r, PROD_CELL, 1, a)
        s.fill(x, y + PROD_TOP_ROWS + r + 1, PROD_CELL, 1, b)
        # the ball is round: its two outer columns fall away on every course
        s.fill(x, y + PROD_TOP_ROWS + r, 1, 2, b * 0.82)
        s.fill(x + PROD_CELL - 1, y + PROD_TOP_ROWS + r, 1, 2, b * 0.82)
    # the button, dead centre of the belt, on both of its courses
    s.fill(x + 3, y + PROD_TOP_ROWS + 2, 2, 1, rgb("sign_white"))
    s.fill(x + 3, y + PROD_TOP_ROWS + 3, 2, 1, rgb("sign_white") * 0.80)
    # a specular pip on the lid, which all four sprites carry
    s.fill(x + 1, y + PROD_TOP_ROWS, 2, 1, lid[0] * 0.35 + np.array([255.0] * 3) * 0.65)
    # and the lid seen from ABOVE, for prodCap
    s.fill(x, y, PROD_CELL, 2, lid[0])
    s.fill(x, y, 1, 2, lid[1])
    s.fill(x + PROD_CELL - 1, y, 1, 2, lid[1])




def load_grain(fname):
    p = SHOP / fname
    if not p.exists():
        return None
    im = Image.open(p).convert("L")
    a = np.asarray(im, dtype=np.float64) / 255.0
    m = a.mean()
    if m <= 1e-6:
        return None
    return a / m                       # mean 1.0: a pure modulation field


class Sheet:
    """The RGB canvas plus the one operation everything is built from:
    paint a rect with a colour, optionally modulated by a band's grain."""

    def __init__(self):
        self.a = np.zeros((SHEET_H, SHEET_W, 3), dtype=np.float64)
        self.grain = {}
        self.missing = []
        for band, (fname, _) in GRAIN.items():
            g = load_grain(fname)
            if g is None:
                self.missing.append(fname)
            self.grain[band] = g

    def fill(self, x, y, w, h, colour, band=None, jitter=0.0, seed=0):
        c = colour if isinstance(colour, np.ndarray) else rgb(colour)
        patch = np.tile(c, (h, w, 1))
        if band is not None and self.grain.get(band) is not None:
            g = self.grain[band]
            gh, gw = g.shape
            # a deterministic crop, wrapped, so two calls with the same seed
            # get the same grain and neighbouring swatches do not
            oy, ox = (seed * 37) % gh, (seed * 101) % gw
            idx_y = (np.arange(h) + oy) % gh
            idx_x = (np.arange(w) + ox) % gw
            crop = g[np.ix_(idx_y, idx_x)][:, :, None]
            strength = GRAIN[band][1]
            patch = patch * (1.0 + strength * (crop - 1.0))
        if jitter > 0:
            rs = np.random.RandomState(1000 + seed)
            n = rs.normal(0.0, jitter, size=(h, w, 1))
            patch = patch * (1.0 + n)
        self.a[y:y + h, x:x + w] = np.clip(patch, 0, 255)

    def px(self, x, y, colour):
        self.a[y, x] = colour if isinstance(colour, np.ndarray) else rgb(colour)

    def row(self, x, y, w, colour):
        self.fill(x, y, w, 1, colour)

    def image(self):
        return Image.fromarray(self.a.round().astype(np.uint8), "RGB")


# ------------------------------------------------------------- the bands --

def band_wall(s):
    """Band 0. Four 16-wide columns; the model picks a column per feature
    and a texel within it by world x, so a long wall does not repeat."""
    y = BANDS["wall"] * BAND_ROWS
    s.fill(0, y, 16, 16, "paint", band=0, jitter=0.010, seed=1)
    s.fill(16, y, 16, 16, "skirt", band=0, jitter=0.014, seed=2)
    s.fill(32, y, 16, 16, "cornice", band=0, jitter=0.008, seed=3)
    s.fill(48, y, 16, 16, "paint_dim", band=0, jitter=0.010, seed=4)
    # the cornice column carries its own shadow line on its last row, so a
    # model can put light-over-dark without a second swatch
    s.fill(32, y + 15, 16, 1, "cornice_sh")
    # a scuff band on the skirting's top row: shops are scuffed at ankle
    s.fill(16, y, 16, 1, hexrgb("#57545090") * 0 + rgb("skirt") * 0.82)


def band_ceil(s):
    y = BANDS["ceil"] * BAND_ROWS
    s.fill(0, y, 16, 16, "ceiling", band=1, jitter=0.006, seed=5)
    s.fill(16, y, 16, 16, "diffuser", band=1, jitter=0.004, seed=6)
    s.fill(32, y, 16, 16, "housing", band=1, jitter=0.010, seed=7)
    s.fill(48, y, 16, 16, "vent", band=1, jitter=0.010, seed=8)
    # the vent's louvres: dark rows every 3, so the grille reads at distance
    for i in range(1, 16, 3):
        s.fill(48, y + i, 16, 1, rgb("vent") * 0.62)
    # the diffuser's frame: its first and last row a touch cooler, so the
    # fixture has an edge even before the housing is drawn around it
    s.fill(16, y, 16, 1, rgb("diffuser") * 0.90)
    s.fill(16, y + 15, 16, 1, rgb("diffuser") * 0.90)


def band_steel(s):
    y = BANDS["steel"] * BAND_ROWS
    s.fill(0, y, 16, 16, "steel", band=2, jitter=0.012, seed=9)
    s.fill(16, y, 16, 16, "board", band=2, jitter=0.010, seed=10)
    s.fill(32, y, 16, 16, "board_lip", band=2, jitter=0.012, seed=11)
    s.fill(48, y, 16, 16, "cabinet", band=2, jitter=0.010, seed=12)
    s.fill(64, y, 16, 16, "kick", band=2, jitter=0.016, seed=13)
    # the upright's perforation: a shelf standard is a slotted post, and two
    # dark texels every four rows is what that reads as at this scale
    for i in range(1, 16, 4):
        s.px(7, y + i, rgb("steel") * 0.55)
        s.px(8, y + i, rgb("steel") * 0.55)


def band_wood(s):
    y = BANDS["wood"] * BAND_ROWS
    s.fill(0, y, 16, 16, "laminate", band=3, jitter=0.014, seed=14)
    s.fill(16, y, 16, 16, "counter_fr", band=3, jitter=0.010, seed=15)
    s.fill(32, y, 16, 16, "counter_ed", band=3, jitter=0.008, seed=16)
    # the front panel's brand stripe: one lighter course near its top, the
    # painted band every Mart counter in the series has
    s.fill(16, y + 3, 16, 2, rgb("counter_fr") * 0.55 + rgb("sign_white") * 0.45)


def band_glass(s):
    y = BANDS["glass"] * BAND_ROWS
    s.fill(0, y, 16, 16, "glass_cool", band=4, jitter=0.010, seed=17)
    s.fill(16, y, 16, 16, "glass_case", band=4, jitter=0.008, seed=18)
    s.fill(32, y, 16, 16, "mullion", band=4, jitter=0.010, seed=19)
    s.fill(48, y, 16, 16, "glow", band=4, jitter=0.004, seed=20)
    # the painted highlight: a diagonal streak across each pane swatch, the
    # cue the original tile art used and the one thing that says "glass"
    # before any shader runs
    for i in range(16):
        for x0, base in ((0, "glass_cool"), (16, "glass_case")):
            xs = x0 + (i * 3) // 4
            if x0 <= xs < x0 + 16:
                s.px(xs, y + i, rgb(base) * 0.55 + rgb("sign_white") * 0.45)


def band_products(s):
    """8x8 faces. Each is a body, a cap course at the top, a label stripe
    across the middle and a one-texel darker foot, so a row of them on a
    shelf reads as separate boxes rather than as a striped board."""
    # THE PACKAGE IS MOSTLY CARD, and the colour is a BAND on it.
    #
    # These shipped as a saturated field per SKU -- the whole facing one
    # pure hue -- and a shelf of them read as moulded plastic tiles rather
    # than as stock. Nothing in a shop looks like that: a box is printed on
    # white card or a bottle is clear over a pale liquid, and the brand's
    # colour lives in a band across it, a cap and a stripe of text. That
    # ratio is roughly a quarter colour to three quarters light, and it is
    # most of the difference between "toy" and "photograph" at this size.
    #
    # The saturated hue is still in every SKU -- it is what tells two lines
    # apart at eight voxels -- it just stops being the whole box.
    CARD = np.array([232.0, 229.0, 222.0])
    # SKU -> the bag sprite it is actually a picture of. `prodFit` samples
    # rows 2..7, so the art is boxed to 8 x 6 and laid in there; row 0 is
    # the lid `prodCap` reads from above and gets the ball's own top course.
    BALL_ART = {8: 0, 9: 1, 10: 2}      # Poke, Great, Ultra
    for i, (_, body, cap, label) in enumerate(PRODUCTS):
        cx, cy = i % PROD_COLS, i // PROD_COLS
        x, y = cx * PROD_CELL, PROD_Y0 + cy * PROD_CELL
        b, c, l = hexrgb(body), hexrgb(cap), hexrgb(label)
        if i in BALL_ART:
            draw_ball(s, x, y, BALL_ART[i])
            continue
        # the card the brand is printed on: the hue survives at a quarter
        # strength, so a red line still reads warm and a blue one cool
        base = b * 0.42 + CARD * 0.58
        s.fill(x, y, PROD_CELL, PROD_CELL, base, jitter=0.02, seed=40 + i)
        # the brand band across the middle, and a thinner rule under it
        # a WIDE band, because prodFit samples rows 2..7 over a facing that
        # is often only two or three voxels tall: a two-row band landed on
        # one voxel in two and half the shelf came back as bare card.
        s.fill(x, y + 3, PROD_CELL, 3, b)
        s.fill(x, y + 6, PROD_CELL, 1, b * 0.72 + CARD * 0.28)
        # ROW 0 IS THE LID, and it is the package seen from ABOVE -- so it
        # is the BODY, lifted, with the cap colour only as a seal down the
        # middle. It used to be the flat cap colour, which is white or
        # near-white for nineteen of the twenty-four SKUs; that was
        # invisible while `prodFit` skipped row 0, and the moment the top
        # voxel of each facing started using it (ShopKit's prodCap, which
        # exists because this camera looks DOWN on every shelf) a stocked
        # tier went from rows of colour to rows of white.
        # the lid, seen from above: card again, a touch lifted, with the
        # cap colour as a seal down the middle
        s.fill(x, y, PROD_CELL, 1, base * 1.05)
        s.fill(x + 3, y, 2, 1, c)
        # a line of "text" under the band -- two texels of the label colour,
        # which at this size is all a printed name ever amounts to
        s.fill(x + 1, y + 7, 4, 1, l * 0.55 + base * 0.45)
        s.fill(x, y + PROD_CELL - 1, PROD_CELL, 1, base * 0.68)  # foot shadow
        s.fill(x + PROD_CELL - 1, y + 1, 1, PROD_CELL - 2, base * 0.82)  # side


def band_planter(s):
    """The planter, in the PRINTED band so no photograph modulates it: a
    leaf is not plaster and not steel, and there is no sixth sampler to
    give it its own. Two greens, mottled, because a canopy that is one
    flat colour reads as a painted cone."""
    y = 160
    s.fill(64, y, 16, 16, "leaf", jitter=0.05, seed=80)
    # lit flecks scattered through it -- the light comes from above, so the
    # paler green goes in the upper rows more often than the lower
    rng = np.random.default_rng(81)
    for row in range(16):
        n = 7 - row // 3
        for _ in range(max(0, n)):
            cx = int(rng.integers(0, 16))
            s.fill(64 + cx, y + row, 1, 1, rgb("leaf_lit"))
    s.fill(80, y, 16, 16, "terracotta", jitter=0.03, seed=82)
    # two darker courses: the rim's shadow and the soil at the top
    s.fill(80, y, 16, 2, rgb("terracotta") * 0.62)
    s.fill(80, y + 15, 16, 1, rgb("terracotta") * 0.78)
    # the waste bin and the extinguisher: the room measured 2 % of itself
    # below value 0.20 against a target of 8, and a frame with no dark in
    # it has nothing for its lights to be brighter THAN.
    s.fill(96, y, 16, 16, "bin", jitter=0.03, seed=83)
    s.fill(96, y, 16, 3, "bin_lid")
    s.fill(96, y + 3, 16, 1, rgb("bin") * 0.7)
    for c in range(2, 15, 4):
        s.fill(96 + c, y + 6, 2, 7, rgb("bin") * 1.18)     # the flutes
    s.fill(112, y, 16, 16, "ext_red", jitter=0.03, seed=84)
    s.fill(112, y, 16, 2, rgb("bin") * 1.1)                # the neck
    s.fill(112, y + 7, 16, 3, rgb("sign_white") * 0.92)    # the label


def band_art(s):
    """Everything that is a DRAWING rather than a surface: the shop sign,
    the register, price rails, the door mat, cardboard, the poster."""
    y = ART_Y0
    # --- the fascia sign over the counter: blue field, white lettering slot
    s.fill(0, y, 64, 16, "sign_blue", jitter=0.006, seed=60)
    s.fill(2, y + 3, 60, 9, "sign_white")
    s.fill(2, y + 3, 60, 1, rgb("sign_white") * 0.80)
    # a red rule under it, the series' own trim
    s.fill(0, y + 14, 64, 2, "sign_red")

    # --- SALE header for the display cases (red field, white slot)
    s.fill(64, y, 32, 16, "sign_red", jitter=0.006, seed=61)
    s.fill(66, y + 4, 28, 7, "sign_white")

    # --- price rail: white strip with ticket marks, for shelf front lips
    #
    # One narrow ticket every EIGHT, not a two-wide block every four. The
    # dense version made the busiest edge in the room read as a keyboard:
    # at the shelf's scale a rail is mostly blank strip with the odd label
    # on it, and the marks have to be sparse enough to read as labels
    # rather than as a pattern.
    s.fill(96, y, 32, 16, "sign_white", jitter=0.004, seed=62)
    for i in range(2, 32, 8):
        s.fill(96 + i, y + 5, 1, 3, rgb("sign_blue"))
        s.fill(96 + i + 1, y + 5, 1, 3, rgb("sign_blue") * 0.55
               + rgb("sign_white") * 0.45)
    # a shadow line along the rail's bottom, so the lip has an edge
    s.fill(96, y + 9, 32, 1, rgb("sign_white") * 0.72)

    # --- the register: body, keypad, screen (lit)
    y2 = y + 16
    s.fill(0, y2, 16, 16, "steel", band=2, jitter=0.012, seed=63)
    s.fill(16, y2, 16, 16, "screen", jitter=0.010, seed=64)
    s.fill(17, y2 + 2, 14, 6, "screen_lit")
    for r in range(3):                                    # the keypad
        for c in range(4):
            s.fill(33 + c * 3, y2 + 3 + r * 4, 2, 3, rgb("steel") * 0.72)
    s.fill(32, y2, 16, 16, rgb("steel_dark"), jitter=0.012, seed=65)
    for r in range(3):
        for c in range(4):
            s.fill(33 + c * 3, y2 + 3 + r * 4, 2, 3, rgb("board"))

    # --- the door mat: dark rubber, ribbed, with a bound edge
    #
    # The ribs run ACROSS the doorway (along x), because that is the way a
    # scraper mat is laid and the way the camera crosses it. Every second
    # rib is a proper groove rather than a tint, so the weave survives the
    # room's own shading instead of washing out into one flat slab.
    y3 = y + 32
    s.fill(0, y3, 32, 16, "mat", jitter=0.020, seed=66)
    for i in range(0, 16, 2):
        s.fill(0, y3 + i, 32, 1, "mat_rib")
    # the bound edge: a mat has a raised lip all the way round, and it is
    # what stops this reading as a painted rectangle
    s.fill(0, y3, 32, 1, rgb("mat") * 1.18)
    s.fill(0, y3 + 15, 32, 1, rgb("mat") * 1.18)

    # --- cardboard: a stock box, flaps drawn as a cross
    s.fill(32, y3, 16, 16, "card", band=3, jitter=0.018, seed=67)
    s.fill(32, y3 + 7, 16, 2, rgb("card") * 0.70)
    s.fill(39, y3, 2, 16, rgb("card") * 0.70)

    # --- a shopping basket: red weave
    s.fill(48, y3, 16, 16, hexrgb("#B5342E"), jitter=0.02, seed=68)
    for i in range(1, 16, 3):
        s.fill(48, y3 + i, 16, 1, hexrgb("#8C241F"))

    # --- the wall poster: a blue field with a pale block, no lettering (it
    #     would be four texels wide in the room and read as noise)
    y4 = y + 48
    s.fill(0, y4, 24, 32, "sign_blue", jitter=0.008, seed=69)
    s.fill(2, y4 + 2, 20, 18, hexrgb("#EAF0FA"))
    s.fill(2, y4 + 22, 20, 8, hexrgb("#D23B33"))

    # --- an aisle sign hanging from the ceiling: white board, blue arrow
    s.fill(24, y4, 40, 16, "sign_white", jitter=0.004, seed=70)
    s.fill(24, y4, 40, 2, rgb("sign_blue"))
    s.fill(24, y4 + 14, 40, 2, rgb("sign_blue"))

    # --- floor mat / entry tread and a dark generic shadow swatch
    s.fill(64, y4, 16, 16, rgb("mat") * 0.55)
    s.fill(80, y4, 16, 16, hexrgb("#101216"))


# ------------------------------------------------------------- the swatches --
#
# The table lib/ShopKit.lua mirrors. (x, y) is the swatch's top-left texel;
# w, h its size. Kept here as the single authoring source -- the kit's copy
# is checked against the PNG's dimensions at load, and this file's --check
# mode re-derives the sheet and compares hashes.
SWATCHES = {
    "paint":      (0, 0, 16, 16),
    "skirt":      (16, 0, 16, 16),
    "cornice":    (32, 0, 16, 16),
    "paint_dim":  (48, 0, 16, 16),
    "ceiling":    (0, 16, 16, 16),
    "diffuser":   (16, 16, 16, 16),
    "housing":    (32, 16, 16, 16),
    "vent":       (48, 16, 16, 16),
    "steel":      (0, 32, 16, 16),
    "board":      (16, 32, 16, 16),
    "board_lip":  (32, 32, 16, 16),
    "cabinet":    (48, 32, 16, 16),
    "kick":       (64, 32, 16, 16),
    "laminate":   (0, 48, 16, 16),
    "counter_fr": (16, 48, 16, 16),
    "counter_ed": (32, 48, 16, 16),
    "glass_cool": (0, 64, 16, 16),
    "glass_case": (16, 64, 16, 16),
    "mullion":    (32, 64, 16, 16),
    "glow":       (48, 64, 16, 16),
    "products":   (0, 80, 256, 48),
    "sign_shop":  (0, 128, 64, 16),
    "sign_sale":  (64, 128, 32, 16),
    "price_rail": (96, 128, 32, 16),
    "reg_body":   (0, 144, 16, 16),
    "reg_screen": (16, 144, 16, 16),
    "reg_keys":   (32, 144, 16, 16),
    "mat":        (0, 160, 32, 16),
    "carton":     (32, 160, 16, 16),
    "foliage":    (64, 160, 16, 16),
    "pot":        (80, 160, 16, 16),
    "bin":        (96, 160, 16, 16),
    "ext":        (112, 160, 16, 16),
    "basket":     (48, 160, 16, 16),
    "poster":     (0, 176, 24, 32),
    "aisle_sign": (24, 176, 40, 16),
    "tread":      (64, 176, 16, 16),
    "shadow":     (80, 176, 16, 16),
}


def build():
    s = Sheet()
    band_wall(s)
    band_ceil(s)
    band_steel(s)
    band_wood(s)
    band_glass(s)
    band_products(s)
    band_art(s)
    band_planter(s)
    return s


def preview(img, out):
    scale = 4
    big = img.resize((SHEET_W * scale, SHEET_H * scale), Image.NEAREST)
    d = ImageDraw.Draw(big)
    for name, (x, y, w, h) in SWATCHES.items():
        d.rectangle([x * scale, y * scale,
                     (x + w) * scale - 1, (y + h) * scale - 1],
                    outline=(255, 0, 128))
        d.text((x * scale + 2, y * scale + 2), name, fill=(255, 255, 0))
    big.save(out)
    return big.size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(OUT))
    ap.add_argument("--preview")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()

    s = build()
    img = s.image()
    if s.missing:
        print("grain textures not present yet (flat colour used): "
              + ", ".join(sorted(set(s.missing))))
    else:
        print("grain from assets/shop/: all four photo albedos found")

    digest = hashlib.sha256(img.tobytes()).hexdigest()[:16]
    if a.check:
        if not Path(a.out).exists():
            print("MISSING", a.out)
            return 1
        have = hashlib.sha256(
            Image.open(a.out).convert("RGB").tobytes()).hexdigest()[:16]
        print(f"shipped {have}  rebuilt {digest}  "
              + ("MATCH" if have == digest else "DIFFERS"))
        return 0 if have == digest else 1

    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    img.save(a.out)
    print(f"wrote {a.out}  {SHEET_W}x{SHEET_H}  sha {digest}  "
          f"{Path(a.out).stat().st_size} bytes")
    if a.preview:
        print("preview", preview(img, a.preview))
    return 0


if __name__ == "__main__":
    sys.exit(main())
