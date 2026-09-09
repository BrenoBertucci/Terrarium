"""Author the Poke Mart's drawing: a 64-wide RGBA sheet the band-table
voxelizer reads instead of the tileset composite.

WHY A PNG AND NOT TILES. The Gen1 overworld atlas is four shades of grey
(128x48, four unique colours) recoloured by one flat SGB palette per map, so
a tile-extruded Mart can never be more than four values of one hue -- which
is exactly why B06 reads as a grey shoebox. `readSprite` in lib/Buildings.lua
already builds the same {W,H,col,ax,ay,inside} struct `read` does, so the
whole band table -- roof plan, slab, eaves, pane recesses, ledge -- runs on
an arbitrary RGBA sheet at one texel per voxel. This file draws that sheet.

A 1:1 ROOF PLAN. The band table maps roofBack rows one-per-voxel down the
north rim, roofFront rows up the south rim, and CYCLES roofCycle across
everything between. That cycle is meant for a tiled roof; anything authored
into it -- a condenser, a duct -- repeats across the whole deck like
wallpaper. Setting roofRows = roofBack = roofFront = D removes the cycled
middle entirely (every z falls in one rim or the other, and both map one row
per voxel), so the roof is drawn once, from above, and reads as a real roof.
That is why ROOF_ROWS is 64 here and 32 in every atlas template.

GEOMETRY IS SPELLED IN COLOUR. Three of the reader's rules do real work and
the layout is built around them:
  - the silhouette is the ALPHA channel (readSprite floods alpha < 0.04 in
    from the border), so nothing needs a black outline and no `seal`;
  - a pane is a non-BLACK region bounded by BLACK and smaller than
    RECESS_MAX = 24 on both axes, so mullions must be black and no bay may
    exceed 24px or it stops sinking and turns back into flat facade;
  - a pane whose bottom reaches H-4 is a DOORWAY (recess 1, not
    recessDepth), so the glazing stops above the base course to keep its
    deep reveal.
`shadeOf` classifies by min(r,g,b): <=.25 BLACK, <=.55 DARK, <=.85 GREY,
else WHITE. Every colour below is picked to land in the class its role
needs -- notably the glass, which must stay above .25 or the pane detector
reads it as frame and nothing recesses at all.

INVENTED GEOMETRY WEARS THE PALETTE STRIP. The roof rim, the sill and the
chimney are surfaces the drawing implies but never paints; measure() dresses
them in `shadeTexel[class]`, the FIRST inside pixel of each shade class in
raster order. Row 0 therefore opens with four deliberate pixels -- one per
class -- so the parapet is the colour this file chose rather than whichever
texel happened to sort first. They sit on the roof's north rim, the one edge
a southern camera never sees.

THE PANE'S OWN LUMINANCE IS THE LAMP. lib/Voxel3D.lua's glass block reads
the drawn texel's luminance as the shape of the light behind it after dark,
so the diagonal shine painted into each pane is not decoration -- it is what
the window looks like lit.

Textures are CC0 (Poly Haven, OpenGameArt); see assets/buildings/LICENSE.md.
They are sampled as a low-frequency grain only: a 1K photoscan carries no
information at 8px, so each is downsampled, posterised to a handful of
levels, and used to modulate an authored flat colour -- never pasted.

    python tools/mart_facade.py [--tex DIR] [--out PATH]
"""
import argparse
import os
import random

from PIL import Image, ImageDraw

W = 64                      # 4 cells x 2 tiles x 8px -- one texel per voxel
DEPTH = 64                  # the footprint: 4 cells deep, same rule
ROOF_ROWS = DEPTH           # 1:1 roof plan -- see the module note
WALL_ROWS = 40              # the south facade
H = ROOF_ROWS + WALL_ROWS

# ---------------------------------------------------------------- palette --
# min(r,g,b) is noted after each: it decides the shade class, and the class
# decides whether the reader treats the pixel as frame (BLACK) or field.
TRIM      = (0x14, 0x18, 0x1c)   # .078 BLACK  outline, mullions, reveals
KICK      = (0x35, 0x3f, 0x47)   # .208 BLACK  plinth under the glass
GLASS     = (0x6b, 0x8f, 0xa8)   # .420 DARK   storefront pane (must clear .25)
GLASS_LIT = (0xb2, 0xd2, 0xe4)   # .698 GREY   the shine -- the lamp's shape
# The sign band and its wordmark must ALL clear .25. Below it the band is
# BLACK-class, which makes it a frame rather than a field -- and then each
# white letter is a small non-BLACK region enclosed by black, i.e. a pane,
# and `MART` sinks recessDepth into the sign and reads as four dark holes.
# Above .25 the whole band is one region 64 wide, past RECESS_MAX, so it
# stays flat and the letters stay letters.
SIGN      = (0x45, 0x7f, 0xd8)   # .271 DARK   the signboard's cerulean
SIGN_DEEP = (0x42, 0x6d, 0xb8)   # .259 DARK   its shaded lower half
SIGN_LIP  = (0x74, 0xaa, 0xea)   # .455 DARK   the lit top edge of the band
WALL      = (0xe8, 0xe1, 0xd2)   # .824 GREY   cream plaster body
WALL_SH   = (0xc2, 0xba, 0xaa)   # .667 GREY   the same in shadow
FASCIA    = (0xf4, 0xf6, 0xf7)   # .957 WHITE  canopy edge, white metal
DECK      = (0x8d, 0x9a, 0xa4)   # .553 GREY   roof deck, box-profile steel
DECK_RIB  = (0x6d, 0x79, 0x83)   # .427 DARK   its standing seams
COPING    = (0xb6, 0xc0, 0xc7)   # .714 GREY   parapet coping, seen from above
PARAPET   = (0x8a, 0x93, 0x9a)   # .541 DARK   parapet face -- the roof RIM
PLANT     = (0x9c, 0xa6, 0xad)   # .612 GREY   rooftop condensers and duct
PLANT_SH  = (0x66, 0x70, 0x78)   # .400 DARK   their louvres
ACCENT_A  = (0xe8, 0x6a, 0x54)   # .329 DARK   brand stripe, warm
ACCENT_B  = (0xf2, 0xb4, 0x52)   # .322 DARK   brand stripe, amber
WHITE_INK = (0xff, 0xff, 0xff)   # .999 WHITE  the wordmark

# the four the rim/sill/chimney borrow, in raster order on row 0
PALETTE_STRIP = [TRIM, PARAPET, COPING, FASCIA]   # BLACK, DARK, GREY, WHITE

# ------------------------------------------------------------ facade bands --
# Absolute sprite rows. The reader measures the wall from ROOF_ROWS down, so
# every number here is one voxel of built height.
def _row(n):
    return ROOF_ROWS + n


Y_CAP0,   Y_CAP1   = _row(0),  _row(1)    # trim line closing the wall top
Y_PFACE0, Y_PFACE1 = _row(2),  _row(3)    # parapet face above the sign
Y_SIGN0,  Y_SIGN1  = _row(4),  _row(11)   # THE signboard
Y_REV0,   Y_REV1   = _row(12), _row(13)   # reveal under the sign
Y_FAS0,   Y_FAS1   = _row(14), _row(15)   # canopy fascia -- the `ledge` band
Y_SOF0,   Y_SOF1   = _row(16), _row(17)   # canopy soffit, in shadow
Y_GLZ0,   Y_GLZ1   = _row(18), _row(31)   # glazing (14 tall: under RECESS_MAX)
Y_KICK0,  Y_KICK1  = _row(32), _row(35)   # kick plate
Y_BASE0,  Y_BASE1  = _row(36), _row(39)   # base; H-4 == Y_BASE0, panes stay up

LEDGE = (Y_FAS0, Y_SOF1)        # what juts: the canopy, not the sign
PIER = 3                        # corner pier width, cream, no glass
DOOR_X0, DOOR_X1 = 16, 31       # over the warp cell: B06 local cell (2,4)

# The raised centre bay. STEP rows cleared off the top of the WING columns
# of the roof plan drop those columns' parapet by STEP voxels -- see roof().
# STEP == 4 puts the wings' wall top exactly on Y_SIGN0, the signboard's lit
# lip, so the step reads without cutting the sign.
CENTRE_X0, CENTRE_X1 = 11, 38
STEP = 4

# The one piece of rooftop plant with real HEIGHT. `chimney` is the only
# box the band table can stand on a roof, it is square in plan, and it
# wears shadeTexel (BLACK rim / DARK body) rather than the drawing -- so
# the plan art under it is drawn to the same square, in the same greys,
# and the two read as one object instead of a box parked on a decal.
# These numbers ARE the template's chimney; keep them in step.
PLANT_X, PLANT_Z, PLANT_W, PLANT_H = 44, 10, 10, 7


# ------------------------------------------------------------------ grain --
def grain(path, w, h, levels, spread, seed=0):
    """A CC0 photoscan reduced to a small signed brightness field.

    Downsample hard, drop to `levels` steps, centre on zero and scale to
    +-`spread`. What survives is the texture's LARGE structure -- the ribs of
    a metal sheet, the mottle of plaster -- which is the only part of a 1K
    capture that still means anything once a texel is a voxel."""
    if not path or not os.path.exists(path):
        rnd = random.Random(seed)
        return [[rnd.choice((-spread, 0, spread)) for _ in range(w)]
                for _ in range(h)]
    im = Image.open(path).convert("L").resize((w, h), Image.LANCZOS)
    px = im.load()
    vals = [px[x, y] for y in range(h) for x in range(w)]
    lo, hi = min(vals), max(vals)
    span = max(1, hi - lo)
    return [[int(round((int((px[x, y] - lo) / span * (levels - 1) + 0.5)
                        / (levels - 1) - 0.5) * 2 * spread))
             for x in range(w)] for y in range(h)]


def shade(c, d):
    return tuple(max(0, min(255, v + d)) for v in c)


def band(dr, y0, y1, x0, x1, colour):
    dr.rectangle([x0, y0, x1, y1], fill=colour + (255,))


FONT = {
    "M": ["10001", "11011", "10101", "10001", "10001"],
    "A": ["01110", "10001", "11111", "10001", "10001"],
    "R": ["11110", "10001", "11110", "10100", "10011"],
    "T": ["11111", "00100", "00100", "00100", "00100"],
}


def wordmark(im, text, x, y, ink):
    """MART in a 5x5 hand font, drawn texel by texel. At this size a
    rasterised typeface is mush, and the sign is the one thing that has to
    stay legible from across the plaza."""
    px = im.load()
    cx = x
    for ch in text:
        for ry, row in enumerate(FONT.get(ch, [])):
            for rx, bit in enumerate(row):
                if bit == "1" and 0 <= cx + rx < W and 0 <= y + ry < H:
                    px[cx + rx, y + ry] = ink + (255,)
        cx += 6
    return cx - 1


# ------------------------------------------------------------------- roof --
def roof(im, dr, px, tex):
    """The roof from above, drawn once at one row per voxel of depth.

    North (row 0) is the far edge; south (row ROOF_ROWS-1) is the eave over
    the facade. Everything here is what a player looking down at the diorama
    actually sees, which on a flat-roofed shop is most of the building."""
    deck = grain(tex("roof_metal.jpg"), W, ROOF_ROWS, 3, 9, seed=1)
    for y in range(ROOF_ROWS):
        for x in range(W):
            px[x, y] = shade(DECK, deck[y][x]) + (255,)
    # box-profile standing seams, running north-south
    for x in range(2, W - 2, 6):
        for y in range(ROOF_ROWS):
            px[x, y] = DECK_RIB + (255,)
            if x + 1 < W:
                px[x + 1, y] = shade(DECK_RIB, 16) + (255,)

    # plant deck: two condensers, the duct that links them, and a stair
    # bulkhead against the north parapet. Drawn once, so it can be specific.
    def unit(x0, y0, w, h):
        band(dr, y0, y0 + h - 1, x0, x0 + w - 1, PLANT_SH)
        band(dr, y0 + 1, y0 + h - 2, x0 + 1, x0 + w - 2, PLANT)
        for x in range(x0 + 2, x0 + w - 2, 2):
            band(dr, y0 + 2, y0 + h - 3, x, x, PLANT_SH)
        band(dr, y0 + h, y0 + h, x0 + 1, x0 + w - 1, shade(PLANT_SH, -22))

    unit(10, 16, 13, 9)
    unit(PLANT_X, PLANT_Z, PLANT_W, PLANT_W)    # the one that gets height
    band(dr, 21, 23, 23, 43, PLANT_SH)          # duct run between them
    band(dr, 21, 22, 24, 42, PLANT)
    band(dr, 40, 44, 14, 27, PLANT_SH)          # stair bulkhead
    band(dr, 40, 43, 15, 26, shade(PLANT, 12))
    band(dr, 45, 45, 15, 27, shade(PLANT_SH, -22))
    for x, y in ((7, 46), (56, 34)):            # roof drains
        band(dr, y, y + 1, x, x + 1, PLANT_SH)

    # the parapet, seen from above: coping all round, closed by a trim line
    band(dr, 0, 2, 0, W - 1, COPING)
    band(dr, ROOF_ROWS - 3, ROOF_ROWS - 1, 0, W - 1, COPING)
    band(dr, 0, ROOF_ROWS - 1, 0, 1, COPING)
    band(dr, 0, ROOF_ROWS - 1, W - 2, W - 1, COPING)
    band(dr, 0, 0, 0, W - 1, TRIM)
    band(dr, ROOF_ROWS - 1, ROOF_ROWS - 1, 0, W - 1, TRIM)
    band(dr, 0, ROOF_ROWS - 1, 0, 0, TRIM)
    band(dr, 0, ROOF_ROWS - 1, W - 1, W - 1, TRIM)

    # THE RAISED CENTRE. measure() takes each column's height from `top[x]`,
    # the first DRAWN row of the roof band in that column -- the taper a
    # pitched roof's art states implicitly. Clearing STEP rows off the top
    # of the wing columns therefore drops their parapet by STEP voxels and
    # lifts the middle of the shop into a sign tower over the entrance,
    # which is the one silhouette break a flat-roofed box can have. STEP is
    # chosen so the wings' wall still tops out ON the signboard's lit lip
    # (facade row Y_SIGN0): any deeper and the wings would cut the sign in
    # half; any shallower and there is no step to see.
    for x in range(W):
        if x < CENTRE_X0 or x > CENTRE_X1:
            for y in range(STEP):
                px[x, y] = (0, 0, 0, 0)

    # THE PALETTE STRIP -- see the module note. It has to sit on a row the
    # centre still draws, or the strip itself would be flooded away.
    for i, c in enumerate(PALETTE_STRIP):
        px[CENTRE_X0 + i, 0] = c + (255,)


# ----------------------------------------------------------------- facade --
def facade(im, dr, px, tex):
    plaster = grain(tex("plaster.jpg"), W, H, 4, 7, seed=2)
    corr = grain(tex("corrugated.jpg"), W, H, 3, 6, seed=3)
    for y in range(Y_CAP0, Y_BASE1 + 1):
        for x in range(W):
            px[x, y] = shade(WALL, plaster[y][x]) + (255,)

    band(dr, Y_CAP0, Y_CAP1, 0, W - 1, TRIM)
    band(dr, Y_PFACE0, Y_PFACE1, 0, W - 1, COPING)

    # the signboard: internally lit acrylic the full width of the facade.
    # A lit top edge and a deeper lower half make the band read as a
    # cylinder of light rather than a sticker.
    band(dr, Y_SIGN0, Y_SIGN1, 0, W - 1, SIGN)
    band(dr, Y_SIGN0 + 4, Y_SIGN1, 0, W - 1, SIGN_DEEP)
    band(dr, Y_SIGN0, Y_SIGN0, 0, W - 1, SIGN_LIP)
    # brand stripes closing the band on the left, the konbini tell
    for i, c in enumerate((ACCENT_A, ACCENT_B, FASCIA)):
        band(dr, Y_SIGN0 + 1, Y_SIGN1 - 1, 4 + i * 2, 5 + i * 2, c)
    wordmark(im, "MART", 26, Y_SIGN0 + 2, WHITE_INK)

    # reveal / fascia / soffit: the three bands that make the canopy read as
    # a slab with air under it. The fascia pair is what `ledge` juts.
    band(dr, Y_REV0, Y_REV1, 0, W - 1, TRIM)
    band(dr, Y_FAS0, Y_FAS1, 0, W - 1, FASCIA)
    band(dr, Y_FAS1, Y_FAS1, 0, W - 1, shade(FASCIA, -34))
    band(dr, Y_SOF0, Y_SOF1, 0, W - 1, TRIM)

    # ---------------------------------------------------------- glazing ---
    band(dr, Y_GLZ0, Y_KICK1, PIER, W - 1 - PIER, TRIM)

    def pane(x0, x1, y0, y1, lit=True):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                px[x, y] = shade(GLASS, corr[y][x]) + (255,)
        if lit:
            for k in range(min(x1 - x0, y1 - y0) + 1):
                for w in range(2):
                    x, y = x0 + k + w, y0 + k
                    if x0 <= x <= x1 and y0 <= y <= y1:
                        px[x, y] = GLASS_LIT + (255,)

    bays = []
    x = PIER + 2
    while x + 8 <= W - PIER - 2:
        if not (x + 7 >= DOOR_X0 - 2 and x <= DOOR_X1 + 2):
            bays.append((x, x + 7))
        x += 10
    for bx0, bx1 in bays:
        pane(bx0, bx1, Y_GLZ0 + 2, Y_GLZ1 - 1)

    # the entrance: a pair of sliding leaves over the warp cell, with a
    # header light above them so the doorway reads as the way in
    band(dr, Y_GLZ0, Y_GLZ0 + 1, DOOR_X0 - 1, DOOR_X1 + 1, FASCIA)
    pane(DOOR_X0, DOOR_X0 + 6, Y_GLZ0 + 3, Y_KICK1 - 1, lit=False)
    pane(DOOR_X1 - 6, DOOR_X1, Y_GLZ0 + 3, Y_KICK1 - 1, lit=False)

    # ------------------------------------------------------- kick + base --
    band(dr, Y_KICK0, Y_KICK1, 0, PIER + 1, WALL_SH)
    band(dr, Y_KICK0, Y_KICK1, W - 2 - PIER, W - 1, WALL_SH)
    for bx0, bx1 in bays:
        band(dr, Y_KICK0, Y_KICK1, bx0 - 2, bx1 + 2, KICK)
    band(dr, Y_BASE0, Y_BASE1, 0, W - 1, TRIM)
    band(dr, Y_BASE0, Y_BASE0, 0, W - 1, shade(KICK, 12))

    # Corner piers last, so nothing overruns them.
    #
    # THE FLANKS ARE THIS COLUMN. A sprite-extruded side face wears its edge
    # column's texel smeared the whole depth of the building, so everything
    # the east and west walls will ever show is the vertical banding drawn
    # here -- and a pier of one flat cream was 24 rows of nothing, the
    # largest dead surface on the model. Each band below is therefore a
    # horizontal line running the full depth of the flank: a coping course
    # under the canopy, a service band at mid-wall, and the kick wrapping
    # the corner. The gradient does the rest -- a wall that darkens toward
    # the ground reads as a wall rather than a swatch.
    for x0, x1 in ((0, PIER - 1), (W - PIER, W - 1)):
        for y in range(Y_REV0, Y_BASE0):
            k = (y - Y_REV0) / max(1, Y_BASE0 - 1 - Y_REV0)
            for x in range(x0, x1 + 1):
                px[x, y] = shade(WALL_SH,
                                 plaster[y][x] - int(k * 26)) + (255,)
        band(dr, Y_FAS0, Y_FAS1, x0, x1, FASCIA)
        band(dr, Y_SOF1, Y_SOF1, x0, x1, shade(WALL_SH, 26))   # coping course
        band(dr, Y_GLZ0 + 6, Y_GLZ0 + 7, x0, x1, shade(WALL_SH, -46))
        band(dr, Y_GLZ0 + 8, Y_GLZ0 + 8, x0, x1, shade(WALL_SH, 14))
        band(dr, Y_KICK0, Y_KICK1, x0, x1, shade(KICK, 26))


def build(tex_dir):
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    px = im.load()
    tex = (lambda n: os.path.join(tex_dir, n)) if tex_dir else (lambda n: None)
    roof(im, dr, px, tex)
    facade(im, dr, px, tex)
    return im


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument("--tex", default=None, help="dir of the CC0 source maps")
    ap.add_argument("--out", default=os.path.join(
        os.path.dirname(here), "assets", "buildings", "mart_facade.png"))
    a = ap.parse_args()
    im = build(a.tex)
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    im.save(a.out)
    im.resize((W * 6, H * 6), Image.NEAREST).save(
        os.path.splitext(a.out)[0] + "_x6.png")
    print("%s  %dx%d  roofRows=%d wall=%d ledge=%s"
          % (a.out, im.size[0], im.size[1], ROOF_ROWS, WALL_ROWS, LEDGE))


if __name__ == "__main__":
    main()
