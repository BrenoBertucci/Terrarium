# Terrarium

A little world under glass: weather, day/night, and a full 3D diorama overworld for Gen1Recomp.

## Fork notice

**Terrarium is a fork of [Dramatic Shape Voxel Mod](https://github.com/DramaticShape/DramaticShapeVoxelMod) by [DramaticShape](https://github.com/DramaticShape).** The diorama, depth-buffered occlusion, shadow map, tilt-shift, and over-the-shoulder battles are his work. Look at the original first if you are choosing between them.

This fork is **independent**: different mod id (`TERRARIUM`), different install folder, different pipeline registry keys (`terrarium_voxel` / `terrarium_tiltshift`), and letter hotkeys so it can sit **beside** upstream `DRAMATIC_SHAPE` without overwriting it or fighting its digit hotkeys.

## Install

1. Import the release zip through FIND MODS / Import, or drop the folder into `mods/TERRARIUM`.
2. Enable **Terrarium** in the mod manager.
3. Optional: keep **Dramatic Shape Voxel Mod** installed too ? they do not share folder or id.

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

Upstream Dramatic Shape still uses `3` / `5` / `6` / `7` / `8` / `9`.

## Features (high level)

- 3D extruded overworld with cast shadows and tilt-shift
- Day/night cycle, weather, puddles and snow on the ground
- Wild Pok?mon visible in the grass; ecology / shelter / city life systems
- Tuned defaults for lower-end / mobile hardware

## Source

https://github.com/BrenoBertucci/Terrarium

Upstream: https://github.com/DramaticShape/DramaticShapeVoxelMod
