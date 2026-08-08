# Third-party effect sheets

Every PNG in this directory is **CC0 1.0 (public domain dedication)**. None of
it was made for this project, and none of it is covered by whatever licence
this mod eventually ships under.

CC0 imposes no attribution requirement. The record below is kept anyway,
because a file whose provenance nobody wrote down becomes a file nobody can
safely publish.

## Source

**Free VFX asset pack** — 22 pixel-art effects authored in SpriteMancer,
released CC0 on OpenGameArt.

<https://opengameart.org/content/free-vfx-asset-pack>

Downloaded 2026-08-07 as `vfx_free_pack.zip` (94,598,540 bytes).

## What was taken, and what was changed

Eight of the pack's 22 effects were kept — the ones that read as a battle
impact in this game. The rest (worms, tentacles, vortices, constellations)
were left behind.

Only the pack's own **30fps spritesheets** were taken. The pack also ships
per-frame PNGs, GIF previews and `.smp` SpriteMancer project files; none of
those are here.

Each sheet was then **resampled down**, frame by frame, to a maximum frame
edge of 128 px. The originals ran up to 557 px per frame, which is roughly
twelve times the size these are ever drawn at in the diorama — on the target
hardware that is VRAM and bandwidth spent on detail that never reaches a
pixel. Frames were resized individually rather than the sheet as a whole, so
no frame bleeds a column of its neighbour.

Result: 1.4 MB on disk, about 15 MB of VRAM if every sheet is live at once
(they are loaded on first use, so normally far less).

| file | frame | grid | frames |
|---|---|---|---|
| `bighit.png` | 128×127 | 6×5 | 30 |
| `charged.png` | 111×128 | 7×6 | 42 |
| `electricshield.png` | 128×128 | 6×5 | 30 |
| `explosion.png` | 128×128 | 6×5 | 30 |
| `impact.png` | 124×128 | 6×5 | 30 |
| `powerchords.png` | 128×87 | 6×5 | 30 |
| `puffandstars.png` | 120×109 | 7×6 | 42 |
| `smallhit.png` | 128×127 | 6×5 | 30 |

The grid for each sheet is recorded in `data/vfx.lua`, read off the pack's own
filenames (SpriteMancer writes the frame size into the sheet name) rather than
counted by hand.

## Not used

`Weapon Slash - Effect` (<https://opengameart.org/content/weapon-slash-effect>,
also CC0) was downloaded and set aside: it ships loose frames with no
spritesheet, so it would need a sheet built for it first.
