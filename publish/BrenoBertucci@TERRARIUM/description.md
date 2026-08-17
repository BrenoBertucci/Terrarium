# Terrarium

A little world under glass: weather, day/night, and a full 3D diorama overworld for Gen1Recomp.

## Fork notice

**Terrarium is a fork of [Dramatic Shape Voxel Mod](https://github.com/DramaticShape/DramaticShapeVoxelMod) by [DramaticShape](https://github.com/DramaticShape).** The diorama, depth-buffered occlusion, shadow map, tilt-shift, and over-the-shoulder battles are his work. Look at the original first if you are choosing between them.

This fork is **independent**: different mod id (`TERRARIUM`), different install folder, different pipeline registry keys (`terrarium_voxel` / `terrarium_tiltshift`), and letter hotkeys so it can sit **beside** upstream `DRAMATIC_SHAPE` without overwriting it or fighting its digit hotkeys.

## Install

1. Import the release zip through FIND MODS / Import, or drop the folder into `mods/TERRARIUM`.
2. Enable **Terrarium** in the mod manager.
3. Optional: keep **Dramatic Shape Voxel Mod** installed too -- they do not share folder or id.

## Hotkeys (this fork)

| Key | Action |
|-----|--------|
| `v` | VOXEL camera ladder |
| `g` | V-GRID wireframe |
| `t` | T-SHIFT miniature blur |
| `c` | V-CURVE horizon |
| `b` | 3D-BTL overworld battles |
| `n` | WILD roam mode |
| `p` | Minimap |
| `h` | V-HAZE aerial perspective |
| `k` | HORIZON far silhouettes |

Upstream Dramatic Shape still uses `3` / `5` / `6` / `7` / `8` / `9`.

## Features (high level)

- 3D extruded overworld with cast shadows and tilt-shift
- Day/night cycle, weather, puddles and snow on the ground
- Wild Pokemon visible in the grass; ecology / shelter / city life systems
- Tuned defaults for lower-end / mobile hardware

## New in 1.22.0-mobile

Trees, rain, and the street lamps that were never actually loading.

- **Trees are trees.** Round-tree sites wear a real 3D willow instead of the
  round hull carved from the tileset. The forest builds across frames so a
  route does not hitch while it appears.
- **A wood stays dry underneath.** The crown keeps puddles off the ground
  it covers, and snow thins in patches rather than a clean circle. Rain
  still falls behind a wall -- that is a different kind of shelter.
- **Rain looks like water.** Streaks brighten what is behind them, fade
  along their length, and lean with the wind. After the shower the canopy
  keeps dripping for a few minutes.
- **Town lamps are the authored post again.** A host filesystem proxy was
  swallowing the bake, so every town silently drew the box templates. The
  lantern now lights from the glass, and posts on the next map over stay
  visible when you stand on the seam.

## Coming next

Tracked on GitHub:
https://github.com/BrenoBertucci/Terrarium/issues

### Readable wild Pokémon (optional art)

WILD roamers can wear **Gen 2-style walk sheets** (16×96) instead of a
shrunk battle portrait. **Those sheets are not in the zip** — same rule as
the X/Y GUI pack.

```text
python tools/install_roamer_sprites.py
```

Details: `assets/roamers/CREDITS.md`.

## New in 1.21.0-mobile

The grass remembers.

- **Routes develop paths where people actually walk.** Every grass cell keeps a
  wear value that climbs when somebody crosses it and recovers over in-game
  days. It rides your save file, so a route you have crossed forty times looks
  crossed forty times.
- **And it is not only you writing it.** Wild Pokemon and the civilians on
  their routines wear the ground down too, at their own weight -- so a route
  grows desire paths along the traffic that really crosses it, including
  corners you have never stood in.
- **Worn grass THINS, it does not shrink.** Individual tufts drop out of a
  trampled cell rather than the whole patch getting shorter, and the earth
  under them shows through as trodden dirt. A path you can look back at.
- **Lightning leaves a scar.** A ground strike burns the grass where it lands,
  and that mark outlives a footpath by a good part of the journey.
- **Grass is calm behind buildings.** The wind now goes around a house instead
  of through it, so a sheltered meadow stands still while the open field waves.
- **Cut clears a cell, and the cell regrows.** Tall grass you cut has no wild
  encounter until it grows back -- so a corridor through a forest is something
  you can make, and something that expires.

## In 1.20.0-mobile

The water.

- **Small water finally moves like small water.** A pond used to carry the
  open sea's swell at a tenth of the height and at half the speed, which reads
  as an ocean filmed in slow motion. It now carries a short chop of its own,
  travelling at the speed a wave that length actually travels.
- **Shorelines stopped fraying.** Along every bank far from the middle of the
  world the wave was quietly coming apart into noise -- for a while now, and
  invisibly to every test the mod had. It is a wave everywhere again.
- **The sun glints off the water.** It always meant to. The window a crest had
  to reach to catch the light was fixed, while how far a crest can tilt depends
  on how big the swell is, so outside of dawn and dusk nothing ever reached it.
  Now the window follows the water, and a still pond sparkles as well as a sea.

The open sea is deliberately untouched: same waves, same directions, same
lengths as the previous build.

## New in 1.19.0-mobile

The sky, and how far away everything is.

- **You can see the rain coming.** A curtain of it stands on the horizon as
  vertical shafts, and it fills in while the drops near you are still nothing
  -- so the weather arrives as something you watch approach for the better
  part of a minute instead of something that switches on.
- **Clouds travel over Kanto, not over your monitor.** The deck reads the
  camera now, and it shifts *less* than everything else on screen, which is
  what makes it read as far away. It also changes shape while it drifts,
  instead of being one rigid pattern towed past.
- **God rays after a shower**, thrown where the deck is breaking up -- light
  through the gaps, not a glow pasted over the sun. In hard steps with the
  same dither as the rest of the sky, so it stays painted rather than bloomed.
- **A storm sky.** Heavy rain now bruises the sky violet instead of only
  greying it -- and only the rain heavy enough to throw lightning does, so a
  purple sky is a promise. A drizzle looks exactly as it always did.
- **Stars go out one at a time** as cloud comes over, scattered, faint ones
  first, rather than the whole field dimming together.
- **V-HAZE** (`h`): the far ground goes paler and bluer with distance. Equal
  contrast reads as equal distance, and that one cue is most of why a map used
  to feel the size of one screen.
- **HORIZON** (`k`): the rest of Kanto standing on the skyline. The maps were
  never missing -- the game already knows where eight to twenty-one of them
  sit relative to you -- they were just never drawn.
- **ANIME** (OFF / CEL / FULL): cel-banded light, rim light and an ink line,
  with no new render pass at any rung.
- **IMPACT**: hand-drawn sprite-sheet effects (CC0 packs, see
  `assets/vfx/LICENSE.md`).

Every sky change above was isolated and measured rather than eyeballed -- they
all landed in one shader, where a screenshot cannot tell you which of them
moved. The whole lot costs under 5% of a sky paint, measured at a ceiling the
game never actually reaches.

## Previously, in 1.18.0-mobile

The tall grass is geometry out here, and that release made it behave like it.

- **WIND / AUTO**, the new default. BREEZE and GALE are two fixed windows onto
  the same climate, so keeping a storm feeling like a storm meant a trip back
  to the options menu every time the sky changed. AUTO spans both on one
  curve: near-still on a calm night, breeze by day, gale on its own under a
  front.
- **Grass that bends instead of sliding.** The tip drops as it goes over
  rather than stretching sideways, every tuft has its own stiffness and phase
  so a meadow is many plants rather than one animated surface, and the gust
  arrives in bands that travel across it.
- **Weather lands ON the grass.** Rain is weight: it damps the sway and adds a
  fast tick as drops hit. Settled snow bows the tufts over, stiffens them, and
  now piles white on the crowns with green showing underneath -- before this,
  a meadow stood green beside ground that had gone white.
- **Walk through it and it lies down**, springs back past upright, and leaves
  a **trail** behind you that recovers over a few seconds. Stop, turn round,
  and the way you came is still there.
- **Wind you can see off the grass**: dust on a clear day, spray under a
  shower, blown white under a fall -- plus a gust front that crosses the frame
  as a line while the meadow bows under it.

## Optional setup (not in the zip)

| what | why missing | install |
| --- | --- | --- |
| X/Y HUD / menu / battle box art | third-party pack; no redistributable licence | `python tools/extract_xy_assets.py <pack folder>` |
| Gen-2-style wild / town walk sprites | fan overworld art; same licence rule | `python tools/install_roamer_sprites.py` |

Without them the mod still runs: HUD falls back to Game Boy panels, roamers
fall back to a greyscale bake.

## Source & issues

- Source: https://github.com/BrenoBertucci/Terrarium
- Issues / roadmap: https://github.com/BrenoBertucci/Terrarium/issues
- Upstream: https://github.com/DramaticShape/DramaticShapeVoxelMod
