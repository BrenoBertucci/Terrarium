# assets/mons -- the mon pack

Generation 5 (Pokemon Black/White) battle sprites, front and back, for the
151 Kanto species, taken from the PokeAPI sprites repository
(https://github.com/PokeAPI/sprites, `sprites/pokemon/versions/generation-v/
black-white/`) on 2026-09-03 and cropped to their opaque bounding box by
`tools/install_mon_pack.py`. No resampling, no recolour.

These are Nintendo / Game Freak / The Pokemon Company artwork, redistributed
by PokeAPI for non-commercial fan use. They are NOT CC0 and are carried here
on the same footing as the Gen 1 pics the game itself ships and the B2W2 HUD
sheet in assets/battlexy: a fan project's own use, with the user's approval.

## anim/ -- the animated set (2026-09-03)

`anim/front|back/<name>.png` are the Black/White ANIMATED sprites from the
same PokeAPI repository (`.../generation-v/black-white/animated/{id}.gif`
and `animated/back/{id}.gif`), unrolled frame by frame into one grid per
species by `tools/install_mon_anim.py` (identical consecutive frames
merged, all frames cropped to their union box; `data/mons_anim.lua`
carries the frame holds). Same artwork, same terms as above.
