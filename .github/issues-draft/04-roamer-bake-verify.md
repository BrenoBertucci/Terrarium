## Context

WILD roamers used to wear a greyscale bake of the battle front pic. At 16×16
that made Sandshrew look like Charmander and Growlithe unreadable. Gen-2-style
16×96 walk sheets are the real fix, but they are **optional and not
redistributed** (`tools/install_roamer_sprites.py`). The bake remains the
fallback for anyone who does not install the pack.

`RoamerArt.REV` is now `"3"` with three bake changes:

1. outline bias only on silhouette-edge blocks (not interior hatch);
2. cell-size floor raised from 8 to 12;
3. head crop (~62% top) when the content box is upright enough.

## What to verify in-game (without the pack)

Delete `save/mod-derived/TERRARIUM/roamers/` so old REV 1/2 sheets cannot
be reused, then walk grass with WILD on and compare:

| species | expect |
| --- | --- |
| SANDSHREW | not identical to CHARMANDER; some body/interior detail |
| GROWLITHE | readable quadruped / mane, not a blob |
| PIKACHU | ears / cheek still legible |
| ONIX / EKANS | full-body crop (head crop must not fire) |

Also re-check **with** the pack installed: true-colour walk sheets, no
recolour wash under RED++ / zone palette.

## Files

- `lib/RoamerArt.lua`
- `tools/install_roamer_sprites.py`
- `assets/roamers/CREDITS.md`
