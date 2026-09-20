# assets/creatures -- the creature pack

411 creature sprites from [Tuxemon](https://www.tuxemon.org), a libre
monster-catching RPG. Each `<slug>.png` is one creature's battle sheet, copied
byte for byte from the project's own repository:

    https://github.com/Tuxemon/Tuxemon
    mods/tuxemon/gfx/sprites/battle/<slug>-sheet.png   (branch: development)

Re-fetch with `tools/install_creature_pack.py`.

## Licence

Tuxemon's code is GPLv3; its art is licensed per asset, and the creature
sprites are **CC BY-SA 4.0** (a few are CC BY 4.0). Every one of them is
credited by name, artist and licence in the project's own attributions file,
which is the authoritative list and travels with this folder by reference:

    https://github.com/Tuxemon/Tuxemon/blob/development/ATTRIBUTIONS.md
    (see the section headed `### Tuxemon`)

CC BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/
Attribution is to the individual artists named there, and to the Tuxemon
project. Share-alike applies to adaptations of these sprites -- this mod draws
them unmodified, cutting the sheet's quadrants with quads at runtime.

## Why these and not the ones in assets/mons

`assets/mons` holds Generation 5 Pokemon battle sprites. That is Nintendo /
Game Freak artwork: it cannot be redistributed, it is in `.gitignore`, and it
never ships in a package. These creatures are original designs whose authors
licensed them for exactly this. Both sets serve the same slot in
`lib/MonPack.lua`; the CREATURES row in OPTIONS picks between them.

## Sheet layout (measured, all 411 are 128x88)

| region | contents |
| --- | --- |
| `(0,0)-(64,64)` | front sprite, facing the viewer |
| `(64,0)-(128,64)` | back sprite, facing away |
| `(0,64)-(48,88)` | two menu icons, 24x24 each |
| `(64,64)-(128,88)` | empty |
