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

## Source

https://github.com/BrenoBertucci/Terrarium

Upstream: https://github.com/DramaticShape/DramaticShapeVoxelMod
