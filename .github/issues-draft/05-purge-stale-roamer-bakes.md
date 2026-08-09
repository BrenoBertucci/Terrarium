## Problem

Baked roamer sheets live under `save/mod-derived/TERRARIUM/roamers/` with
`RoamerArt.REV` in the filename. Bumping REV stops *new* lookups from using
old files, but the old files stay on disk forever. Players who already
played under REV 1/2 keep unreadable sheets until they delete the folder by
hand.

## Wanted

On load (or first bake miss), delete sibling files for the same species
whose revision is not the current `RoamerArt.REV`. One-shot per session is
enough. Do not touch files that do not match the derived naming pattern.

## Acceptance

- After an upgrade, standing in grass without shipped sheets produces a REV
  `"3"` (or current) bake without manual cleanup.
- No crash if the derived directory is missing or read-only.

## Files

- `lib/RoamerArt.lua` (`writeSheet` / `build` / `invalidate`)
