## Context

Ambient beds shipped (Tier 1 + original five) cover town walla, wind,
forest, waves, cave, indoor, plus crickets / birds / water / rain / thunder.
See `lib/AmbientSound.lua` and `assets/audio/CREDITS.md`.

Tier 2 was intentionally skipped so Tier 1 could be complete under the
strict CC0-only rule.

## Candidates (all must stay CC0 1.0 only)

| key | sound | drive |
| --- | --- | --- |
| `stream` | flowing brook | small `WaterBody` near player |
| `waterfall` | fall | near waterfall tiles if detectable |
| `frogs` | frogs | night + water near |
| `cicadas` | cicadas | hot day (counterpoint to crickets) |
| `fire` | lantern flame | night + near `StreetLamps` |
| `snow_wind` | muffled snow wind | `Weather` snow |
| `shop` | indoor commercial murmur | Poké Mart / Center interiors |

Same rules as Tier 1: beds with crossfade (no discrete event schedulers),
loop seams clean, folder under 10 MB, no CC-BY / Pixabay / ZapSplat.

## Deliverables

- files in `assets/audio/`
- entries + level rules in `AmbientSound.lua`
- lines in `assets/audio/CREDITS.md` and README Credits
- discarded-licence list in the PR / issue comment
