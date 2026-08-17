"""Cut this mod's X/Y interface assets out of the 5X GUI pack.

The pack is somebody else's work and is not redistributed here:

    Pokemon X/Y 5X GUI -- https://gamebanana.com/mods/578206

Download it, unzip it, and point this script at the folder that contains
`5X HUD`. It writes everything lib/BattleHudXY.lua, lib/StartMenuXY.lua and
lib/BattleBoxXY.lua expect, under assets/.

    python tools/extract_xy_assets.py "C:/path/to/pokemon_xy_5x_gui_v25"

WHY A SCRIPT AND NOT THE FILES. Two reasons, and only the first is legal.
Crediting an author is not the same as holding a licence from them, and the
underlying art is Nintendo's and Game Freak's whichever way it travels -- the
same reasoning the GAME DATA block in .gitignore already spells out. The
second reason is that the interesting part is not the pixels. The pack's
files are named by content hash, so nothing in it says which texture is the
player's HUD frame and which is the foe's, where the HP trough sits inside
either, or what order the font atlas is in. Every box below was MEASURED off
the pixels, and the measurements are what this repository keeps.

Re-cutting after a pack update means re-measuring, not re-running: if the
author moves a glyph, this script will happily cut the wrong rectangle and
say nothing. The probes under tests/ are what catch that.
"""

import json
import pathlib
import sys

try:
    from PIL import Image
    import numpy as np
except ImportError:                                        # pragma: no cover
    sys.exit("needs Pillow and numpy:  pip install pillow numpy")

ROOT = pathlib.Path(__file__).resolve().parent.parent


def trim(im):
    """Crop to the opaque bounds. Every icon in the pack sits in a padded
    square, and the padding differs per file -- trimming is what makes them
    scale to a common size instead of to a common amount of empty space."""
    a = np.asarray(im)[..., 3]
    ys, xs = np.nonzero(a > 8)
    if not len(xs):
        return im
    return im.crop((int(xs.min()), int(ys.min()),
                    int(xs.max()) + 1, int(ys.max()) + 1))


# --------------------------------------------------------------- battle HUD

FRAMES = {
    "hudxy/frame_player.png": "battle hud/tex1_128x32_34F9C0104CC3659E_0_mip0.png",
    "hudxy/frame_enemy.png":  "battle hud/tex1_128x32_4665B84FCDF3A141_0_mip0.png",
    "hudxy/hp_fill.png":      "battle hud/tex1_128x16_085322E3FB24E39E_13_mip0.png",
    "hudxy/wedge_player.png": "battle hud/tex1_128x32_0759C7E408D95FEC_13_mip0.png",
    "hudxy/wedge_enemy.png":  "battle hud/tex1_128x32_B10F7EA4ABA6315B_13_mip0.png",
    "hudxy/ball.png":         "battle hud/tex1_16x16_D64E06FE80ACEDB0_4_mip0.png",
}

# The big HUD numerals live four to a sheet, and NOT on the sheet's own 2x2
# grid -- the glyphs straddle the cell boundaries. These boxes come from a
# connected-component scan, which is why they look arbitrary: they are the
# ink's actual bounds.
_A = "battle hud/tex1_32x32_0ADD6817E95A8C19_9_mip0.png"
_B = "battle hud/tex1_32x32_23E179B6AE4C996C_9_mip0.png"
_C = "battle hud/tex1_32x32_AAC227E39E98507F_9_mip0.png"
_D = "battle hud/tex1_32x32_D2C64FC80B2AF7C1_9_mip0.png"
DIGITS = [
    ("0", _A, (4, 69, 47, 52)),  ("1", _A, (74, 69, 42, 52)),
    ("2", _B, (6, 9, 44, 51)),   ("3", _B, (76, 9, 43, 52)),
    ("4", _B, (5, 69, 49, 51)),  ("5", _B, (77, 69, 42, 52)),
    ("6", _D, (5, 9, 45, 52)),   ("7", _D, (75, 9, 45, 51)),
    ("8", _D, (5, 69, 46, 52)),  ("9", _D, (74, 69, 46, 52)),
    ("/", _A, (74, 16, 52, 43)),
    ("?", _C, (9, 9, 38, 52)),
    ("L", _C, (74, 69, 67, 52)),          # the whole "Lv." lockup, one glyph
]

# ------------------------------------------------------------------- font
#
# A 9-column grid of 70x80 cells. The order is ASCII WITH GAPS and then the
# Latin-1 block -- no straight quote, no apostrophe, no `<`, no bracket run,
# and `$` drawn as the series' currency mark. Read off the grid rather than
# derived, because the arithmetic does not hold.
#
# NOT IN THE SHEET: O-tilde (either case) and lowercase a-tilde. The pack
# does not draw them; BattleHudXY.FOLD handles the gap.
FONT_SRC = "text/tex1_128x1024_D196772E619EEC71_9_mip0.png"
FONT_ROWS = [
    " !#$%&()*", "+,-./0123", "456789:;=", "?@ABCDEFG",
    "HIJKLMNOP", "QRSTUVWXY", "Zabcdefgh", "ijklmnopq", "rstuvwxyz",
    "~\u00a1\u00ab\u00bb\u00bf\u00c0\u00c1\u00c2\u00c3",
    "\u00c7\u00c8\u00c9\u00ca\u00cb\u00cc\u00cd\u00ce\u00cf",
    "\u00d1\u00d2\u00d3\u00d4\u00d6\u00d7\u00d9\u00da\u00db",
    "\u00dc\u00df\u00e0\u00e1\u00e2\u00e4\u00e7\u00e8\u00e9",
    "\u00ea\u00eb\u00ec\u00ed\u00ee\u00ef\u00f1\u00f2\u00f3",
    "\u00f4\u00f6\u00f7\u00f9\u00fa\u00fb\u00fc\u0152\u0153",
]
CELL_W, CELL_H, PAD, SPACE_ADV = 70, 80, 2, 22

# ------------------------------------------------------------ overworld menu

MENU_ICONS = {
    "menuxy/icon_options.png": "menu/tex1_32x32_15C3ACF52A689E97_0_mip0.png",
    "menuxy/icon_report.png":  "menu/tex1_32x32_1EA18CDC496854A0_0_mip0.png",
    "menuxy/icon_save.png":    "menu/tex1_32x32_A6AE79A445EBA90C_0_mip0.png",
    "menuxy/icon_dex.png":     "menu/tex1_32x32_B427F83AEB58C06E_0_mip0.png",
    "menuxy/icon_bag.png":     "menu/tex1_32x32_DC3A88C11169DCA4_0_mip0.png",
    "menuxy/icon_party.png":   "menu/tex1_32x32_F9FD4EB17EC8D37A_0_mip0.png",
    "menuxy/icon_map.png":     "map/tex1_32x32_4154318B97048ACB_13_mip0.png",
    "menuxy/row_plain.png":    "menu/tex1_512x32_BB2C833968386761_13_mip0.png",
}

# ------------------------------------------------------------- battle menu

BATTLE_PLAIN = {
    "battlexy/cmd_pokemon.png": "battle menu/tex1_128x64_5326EDE38C85846F_0_mip0.png",
    "battlexy/cmd_bag.png":     "battle menu/tex1_128x64_853E7F0D4E1ECBE9_0_mip0.png",
    "battlexy/cmd_run.png":     "battle menu/tex1_128x64_D7A249C5EA85B1BF_0_mip0.png",
    "battlexy/slot_sel.png":    "battle menu/tex1_256x64_2946EF67A8065185_0_mip0.png",
    "battlexy/slot_plain.png":  "battle menu/tex1_256x64_FF0914F30BAE6011_0_mip0.png",
}

# Item sprites for the battle bag's rows (lib/BattleScreenXY.lua), keyed by
# the engine item id each depicts. Identified by EYE off numbered contact
# sheets of all 422 dumps -- the filenames are content hashes and say
# nothing -- so re-cutting means re-looking. Notes from that pass:
#   * TM / HM are two generic discs (blue / gold): the pack colours TMs per
#     move type and Gen 1 has no such fact to read off an item id.
#   * the repels share one canister and the X items one capsule: the pack
#     draws the families apart, but not in any dump this set includes.
#   * BURN_HEAL, PARLYZ_HEAL and FULL_HEAL were NOT found among the 422;
#     the draw falls back to the pocket icon for them.
ITEM_SPRITES = {
    "ANTIDOTE":     "tex1_32x32_7C0BBDB48FBCA701_2_mip0.png",
    "AWAKENING":    "tex1_32x32_8E5E027235EF5383_2_mip0.png",
    "BICYCLE":      "tex1_32x32_9A2B3F40FC77BAF1_2_mip0.png",
    "DIRE_HIT":     "tex1_32x32_C63EACDCCF046C90_2_mip0.png",
    "ELIXER":       "tex1_32x32_9D875F01E63D4F8D_2_mip0.png",
    "ESCAPE_ROPE":  "tex1_32x32_4D209ADB827CFAF0_2_mip0.png",
    "ETHER":        "tex1_32x32_D7244856BABF8DD5_2_mip0.png",
    "FRESH_WATER":  "tex1_32x32_8401241AEDBB7842_2_mip0.png",
    "FULL_RESTORE": "tex1_32x32_CC406A472814FAF3_2_mip0.png",
    "GOOD_ROD":     "tex1_32x32_9D61E7AB2B6C1DC5_2_mip0.png",
    "GREAT_BALL":   "tex1_32x32_A1C9548279C3B09D_2_mip0.png",
    "GUARD_SPEC":   "tex1_32x32_C63EACDCCF046C90_2_mip0.png",
    "HM":           "tex1_32x32_0B0932228C4AFC32_2_mip0.png",
    "HYPER_POTION": "tex1_32x32_33449CD772AB9CA7_2_mip0.png",
    "ICE_HEAL":     "tex1_32x32_AD31989D8C43A439_2_mip0.png",
    "LEMONADE":     "tex1_32x32_62029CC62744975A_2_mip0.png",
    "MASTER_BALL":  "tex1_32x32_587767C4F2115004_2_mip0.png",
    "MAX_ELIXER":   "tex1_32x32_641BF7E161473063_2_mip0.png",
    "MAX_ETHER":    "tex1_32x32_DF766DED40D9ECAC_2_mip0.png",
    "MAX_POTION":   "tex1_32x32_FB0A776516C78C58_2_mip0.png",
    "MAX_REPEL":    "tex1_32x32_7CAE6F33E5B9623D_2_mip0.png",
    "MAX_REVIVE":   "tex1_32x32_E5F612A55DE77D60_2_mip0.png",
    "NUGGET":       "tex1_32x32_4123790F7C45A459_2_mip0.png",
    "OLD_ROD":      "tex1_32x32_8478AE340C2AA017_2_mip0.png",
    "POKE_BALL":    "tex1_32x32_0203A9CFEB82A029_2_mip0.png",
    "POKE_DOLL":    "tex1_32x32_D43411C06D37208D_2_mip0.png",
    "POKE_FLUTE":   "tex1_32x32_F8CE16ADCF30959F_2_mip0.png",
    "POTION":       "tex1_32x32_0D10C3A673A81CC3_2_mip0.png",
    "RARE_CANDY":   "tex1_32x32_25505E4429FB8DE9_2_mip0.png",
    "REPEL":        "tex1_32x32_7CAE6F33E5B9623D_2_mip0.png",
    "REVIVE":       "tex1_32x32_B102D86FC1FD7242_2_mip0.png",
    "SODA_POP":     "tex1_32x32_8D21F8153DD95FE5_2_mip0.png",
    "SUPER_POTION": "tex1_32x32_2C8FBDBA8744A2E5_2_mip0.png",
    "SUPER_REPEL":  "tex1_32x32_7CAE6F33E5B9623D_2_mip0.png",
    "SUPER_ROD":    "tex1_32x32_E867126E8511E61F_2_mip0.png",
    "S_S_TICKET":   "tex1_32x32_F3DEFCB5CE4DAF23_2_mip0.png",
    "TM":           "tex1_32x32_69C769DEF3C58F53_2_mip0.png",
    "TOWN_MAP":     "tex1_32x32_B04F32200C52D933_2_mip0.png",
    "ULTRA_BALL":   "tex1_32x32_7B03BC925CA81801_2_mip0.png",
    "X_ACCURACY":   "tex1_32x32_C63EACDCCF046C90_2_mip0.png",
    "X_ATTACK":     "tex1_32x32_C63EACDCCF046C90_2_mip0.png",
    "X_DEFEND":     "tex1_32x32_C63EACDCCF046C90_2_mip0.png",
    "X_SPECIAL":    "tex1_32x32_C63EACDCCF046C90_2_mip0.png",
    "X_SPEED":      "tex1_32x32_C63EACDCCF046C90_2_mip0.png",
}

# The bag's own pocket buttons, for the tab strip: the pack draws each
# pocket twice, coloured (active) and olive (idle). ITENS has only the one
# state in the dump and the draw dims it instead.
POCKETS = {
    "balls":     "tex1_32x32_A334FB21D9BD4F01_4_mip0.png",
    "balls_off": "tex1_32x32_0EF07A46C9ABE85B_4_mip0.png",
    "cura":      "tex1_32x32_6C6EAA3951FC5D4C_4_mip0.png",
    "cura_off":  "tex1_32x32_CD86F88E1A2B4A55_4_mip0.png",
    "items":     "tex1_32x32_D48CD573A4F8BFAB_0_mip0.png",
    "tm":        "tex1_32x32_C8D62F2AC01C1A3E_4_mip0.png",
    "tm_off":    "tex1_32x32_E8770FB053357F36_4_mip0.png",
}
# FIGHT ships as the LEFT HALF of its oval -- the texture ends at the seam,
# because in the games the other half is that half mirrored. Its word is a
# separate texture again.
FIGHT_HALF = "battle menu/tex1_128x256_BDD86A10C8D54EA2_0_mip0.png"
FIGHT_WORD = "battle menu/tex1_128x64_39B4BDC1E72AA3E6_4_mip0.png"

# Type badges, identified by the word printed on each -- the filenames are
# content hashes and say nothing. Only Generation 1's fifteen are taken; the
# pack also carries Dark, Steel and Fairy, which this game has no concept of.
TYPES = {
    "FIRE": "29D2EFDB27E5500B", "GHOST": "2C6ABCCA680B7FA0",
    "GRASS": "3AA96BD181272EC1", "PSYCHIC": "3B6C123817E2A498",
    "NORMAL": "465F8465628DC5BA", "FLYING": "786E5BD983E70A87",
    "ELECTRIC": "86C4E4EEB2961F50", "ICE": "8C9A54773153D914",
    "GROUND": "94C98FFF53E916C7", "POISON": "AE4935708700C88D",
    "DRAGON": "AE4E251000D9804F", "ROCK": "B1771A527DFF66F9",
    "WATER": "BD020BDCDB40BF0B", "BUG": "C4A02D8E90BF1651",
    "FIGHTING": "FB1C383B5FC1F179",
}


def build(pack: pathlib.Path):
    hud = pack / "5X HUD"
    if not hud.is_dir():
        sys.exit(f"no '5X HUD' folder under {pack}\n"
                 "point this at the unzipped pack, not at a subfolder of it")

    out = ROOT / "assets"
    for sub in ("hudxy", "menuxy", "battlexy", "battlexy/types",
                "battlexy/items", "battlexy/pockets"):
        (out / sub).mkdir(parents=True, exist_ok=True)

    missing = []

    def load(rel):
        p = hud / rel
        if not p.exists():
            missing.append(rel)
            return None
        return Image.open(p).convert("RGBA")

    # plain copies -- frames keep their padding, because the trough boxes in
    # BattleHudXY are measured in the FULL 640x160 texture's coordinates
    for dst, src in FRAMES.items():
        im = load(src)
        if im:
            im.save(out / dst)

    for dst, src in list(MENU_ICONS.items()) + list(BATTLE_PLAIN.items()):
        im = load(src)
        if im:
            trim(im).save(out / dst)

    for name, h in TYPES.items():
        im = load(f"type icons/tex1_64x32_{h}_4_mip0.png")
        if im:
            trim(im).save(out / "battlexy/types" / f"{name}.png")

    # plain copies, no trim: the 32x32 cell IS the sprite's frame and the
    # rows scale by the image's height -- trimming would make every item a
    # different size on the list
    for name, src in ITEM_SPRITES.items():
        im = load(f"item sprites/{src}")
        if im:
            im.save(out / "battlexy/items" / f"{name}.png")

    for name, src in POCKETS.items():
        im = load(f"bag/{src}")
        if im:
            im.save(out / "battlexy/pockets" / f"{name}.png")

    # FIGHT: mirror the half, then drop its word on top
    half, word = load(FIGHT_HALF), load(FIGHT_WORD)
    if half and word:
        half, word = trim(half), trim(word)
        w, h = half.size
        oval = Image.new("RGBA", (w * 2, h), (0, 0, 0, 0))
        oval.paste(half, (0, 0))
        oval.paste(half.transpose(Image.FLIP_LEFT_RIGHT), (w, 0))
        lw = int(oval.size[0] * 0.52)
        word = word.resize((lw, int(word.size[1] * lw / word.size[0])),
                           Image.LANCZOS)
        oval.alpha_composite(word, ((oval.size[0] - lw) // 2,
                                    int(oval.size[1] * 0.50 - word.size[1] * 0.5)))
        oval.save(out / "battlexy/cmd_fight.png")

    # ---- the two strips, and the Lua table that indexes them
    meta = {}

    src = load(DIGITS[0][1])
    if src:
        cut = []
        for ch, f, (x, y, w, h) in DIGITS:
            im = load(f)
            cut.append((ch, im.crop((x, y, x + w, y + h)) if im else None))
        H = max(g[2][3] for g in DIGITS)
        W = sum((im.size[0] if im else 0) + PAD for _, im in cut) + PAD
        atlas = Image.new("RGBA", (W, H + PAD * 2), (0, 0, 0, 0))
        dmeta, x = {}, PAD
        for ch, im in cut:
            if im is None:
                continue
            w, h = im.size
            atlas.paste(im, (x, PAD + (H - h)), im)   # bottom-aligned baseline
            dmeta[ch] = {"x": x, "y": PAD + (H - h), "w": w, "h": h}
            x += w + PAD
        atlas.save(out / "hudxy/digits.png")
        meta["digits"] = (dmeta, H + PAD * 2)

    fsrc = load(FONT_SRC)
    if fsrc:
        alpha = np.asarray(fsrc)[..., 3]
        cells = []
        for r, line in enumerate(FONT_ROWS):
            for c, ch in enumerate(line):
                x0, y0 = c * CELL_W, r * CELL_H
                xs = np.nonzero(
                    (alpha[y0:y0 + CELL_H, x0:x0 + CELL_W] > 8).any(axis=0))[0]
                if ch == " " or not len(xs):
                    cells.append((ch, None, 0, SPACE_ADV))
                    continue
                lo, hi = int(xs.min()), int(xs.max())
                cells.append((ch, (x0 + lo, y0), hi - lo + 1, hi - lo + 1))
        W = sum(w + PAD for _, _, w, _ in cells) + PAD
        atlas = Image.new("RGBA", (max(W, 4), CELL_H + PAD * 2), (0, 0, 0, 0))
        fmeta, x = {}, PAD
        for ch, box, w, adv in cells:
            if box:
                gx, gy = box
                # the FULL cell height, so a descender still hangs below the
                # baseline; only the horizontal extent is trimmed
                atlas.paste(fsrc.crop((gx, gy, gx + w, gy + CELL_H)), (x, PAD))
            fmeta[ch] = {"x": x, "w": w, "adv": adv}
            x += w + PAD
        atlas.save(out / "hudxy/font.png")
        meta["font"] = (fmeta, CELL_H + PAD * 2)

    if "font" in meta and "digits" in meta:
        write_lua(meta)

    if missing:
        print(f"\n{len(missing)} texture(s) not found in the pack:")
        for m in missing[:10]:
            print("   ", m)
        print("the pack may have been updated -- the boxes in this script "
              "were measured against v25")
    print(f"\nwrote assets under {out}")


def write_lua(meta):
    """Regenerate data/hudxy_glyphs.lua so the table matches the packing this
    run produced. The file is committed as well, because it is the measured
    part -- but a re-cut moves every x, so it has to be rewritten with it."""
    fmeta, fh = meta["font"]
    dmeta, dh = meta["digits"]

    def key(s):
        return '["' + "".join(f"\\{b}" for b in s.encode("utf-8")) + '"]'

    out = [
        "-- Glyph boxes for the X/Y interface font, generated by",
        "-- tools/extract_xy_assets.py -- do not hand-edit.",
        "--",
        "-- Keys are the glyph's UTF-8 BYTES as numeric escapes, so this file",
        "-- stays pure ASCII: the renderer decodes one code point at a time and",
        "-- looks the whole sequence up.",
        "return {",
        f"  fontHeight = {fh},",
        "  font = {",
    ]
    for ch, m in sorted(fmeta.items()):
        out.append(f'    {key(ch)} = {{ x = {m["x"]}, w = {m["w"]}, '
                   f'adv = {m["adv"]} }},')
    out += ["  },", f"  digitHeight = {dh},", "  digits = {"]
    for ch, m in sorted(dmeta.items()):
        out.append(f'    {key(ch)} = {{ x = {m["x"]}, y = {m["y"]}, '
                   f'w = {m["w"]}, h = {m["h"]} }},')
    out += ["  },", "}"]
    (ROOT / "data" / "hudxy_glyphs.lua").write_text("\n".join(out) + "\n",
                                                    encoding="ascii")
    print("wrote data/hudxy_glyphs.lua")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    build(pathlib.Path(sys.argv[1]))
