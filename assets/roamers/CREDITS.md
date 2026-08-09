# Overworld roamer sprites

These sheets do **not** ship with the mod.

The same reason the X/Y GUI pack does not ship applies here: crediting an
author is not the same as holding a licence from them, and the underlying
art is Nintendo's and Game Freak's whichever way it travels. A Gen 2-style
overworld walk cycle of a Gen 1 species is still a derivative of those
characters. Fan-made authorship adds another party with rights over the
drawing — it does not clear the ones that were already there, and it does
not grant this repository a redistributable licence.

Without the sheets, wild and town Pokémon still appear: `lib/RoamerArt.lua`
bakes a greyscale 16×96 walker from each species' battle front pic. The
feature does not go away; it is worse (that bake is what made Sandshrew look
like Charmander). Install the pack and the readable set takes over.

## Install

One command, from the mod root:

```text
python tools/install_roamer_sprites.py
```

That downloads [PokéPC Followers](https://github.com/gamecorner-033/PokePCFollowers),
renames `follower_<SPECIES>.png` (or `follower_NNN.png`) into
`assets/roamers/<SPECIES>.png`, checks each file is 16×96, and reports any
species still missing.

Or do it by hand:

1. Get the pack from
   https://github.com/gamecorner-033/PokePCFollowers
2. From `assets/sprites/`, copy each `follower_<SPECIES>.png` to
   `assets/roamers/<SPECIES>.png` (engine ids: `SANDSHREW`, `MR_MIME`,
   `NIDORAN_F`, …)
3. Drop a replacement 16×96 sheet for any one species the same way

## Art lineage (for credit, not a licence)

| role | who |
| --- | --- |
| Overworld walk sheets | **ShockSlayer** and the **Pokémon Crystal Clear** team |
| Gen1Recomp packaging used as the download source | [PokéPC Followers](https://github.com/gamecorner-033/PokePCFollowers) (`gamecorner-033`) |

What this repository keeps is the **loader** (`lib/RoamerArt.lua`: prefer
shipped sheet, mark it `trueColor`, fall back to bake) and this note — not
the pixels.

## Format

Each file is a **16×96** six-frame walker sheet (stand down / up / left, walk
down / up / left), matching the engine's `walker = true` layout. Shipped
sheets are loaded with `trueColor = true` so the palette pipeline leaves
their species colours alone.
