# assets/battlexy third-party (CC0 only)

Everything versioned in this folder is CC0 (`fx/`, below) or made for this
mod (`glass/`, baked in Blender).

The 5X pack cuts (`cmd_*.png`, `slot_*.png`, `items/`, `pockets/`, `types/`)
and the B2W2 HP-bar plates (`b2w2/`) are Nintendo / Game Freak art. They are
**not** in this repository or its packages (removed 2026-09-15), and
`.gitignore` keeps them out. The 5X cuts can be made on your own machine
with `tools/extract_xy_assets.py`; without them the mod uses its older HUD.

The CC0 files were downloaded for the X/Y bag preview twinkles, the cursor
hop landing spark, and a small preview-card frame.

## Particle textures

- Files: `fx/bishie_sparkle_1.png`, `fx/bishie_sparkle_2.png`, `fx/9_pointed_star.png`
- Author: Starry Skydancer
- URL: https://opengameart.org/content/particle-textures
- License: CC0 1.0 Universal (https://creativecommons.org/publicdomain/zero/1.0/)
- Direct files: https://opengameart.org/sites/default/files/<filename>

## Tiny RPG - Mana Soul GUI (pieces only)

- Files:
  - `fx/gui_item_frame.png` — gold item-slot diamond cropped from `20250423emptyFrame-Sheet.png`
  - `fx/gui_vcursor.png` — `20250421verticalCursorA-Sheet.png` (5-frame vertical cursor)
- Author: tiopalada
- URL: https://opengameart.org/content/tiny-rpg-mana-soul-gui
- Zip: https://opengameart.org/sites/default/files/tinyrpg_manasoulgui_v_1_0.zip
- License: CC0 1.0 Universal (https://creativecommons.org/publicdomain/zero/1.0/)
- Note: only the gold item frame and one animated vertical cursor were copied.
  The rest of the pack's chrome came later -- see the next section.

## Tiny RPG - Mana Soul GUI (the battle HUD's chrome)

- Files:
  - `ui/panel.png` — `20250420manaSoul9SlicesA-Sheet.png`, the navy plate with
    gold filigree corners, drawn as a 9-slice (insets 28/28/16/16, measured)
  - `ui/bar_outline.png` — `20250421barC-Sheet.png`, the plain capsule outline
    stretched over the HP and EXP fills
  - `ui/chip.png` — first of the four capsules in
    `20250421manaSoulButtonA-Sheet.png`; only its gold chevron caps are used
- Author: tiopalada
- URL: https://opengameart.org/content/tiny-rpg-mana-soul-gui
- Zip: https://opengameart.org/sites/default/files/tinyrpg_manasoulgui_v_1_0.zip
- License: CC0 1.0 Universal (https://creativecommons.org/publicdomain/zero/1.0/)
- Re-cut any time with `tools/install_ui_kit.py`, which measures the boxes off
  the sheet rather than trusting the numbers above.
- Why this pack for the HUD: the battle plates, the move cards and the command
  chips all want the same thing -- a dark panel with gold ornament -- and
  taking all three from one hand is what stops them drifting apart. It also
  replaces borrowed art rather than adding to it: the 5X HUD cuts this costume
  used to wear left the repository in 2026-09-15 and are not coming back, so
  the HUD is CC0 and mod-drawn from here on.
- Deliberately NOT imported: `20250421barA-Sheet.png`, the prettier bar. Its
  bottom rail carries a flourish at the centre, and a bar has to survive being
  stretched to three times its own width -- that pixel smears into a streak.
  Recolored/tinted in code toward Pokemon X/Y gold-orange. The rest of the
  mana-RPG pack (9-slices, bars, buttons, equipment slots) was not imported.
  Existing Unova/XY rounded panels remain the bag chrome; the frame is used
  on the preview card only.
