## Problem

New ambient beds were validated by level analysis at the loop join (concat
2×/3×, mean energy at the seam). They were **not** heard on real speakers
under map music. Gains in `AmbientSound.BEDS` were set by analogy, not by
mix against Viridian / Route 21 / a house in rain.

## Wanted

In-game ear pass with SOUNDS on and map music at a normal volume:

| place | beds to check |
| --- | --- |
| town day | `town` under music, not cafeteria-loud |
| route wind | `wind` tracks `Wind.amount`, not constant drone |
| Viridian Forest | `forest` replaces open `birds` |
| Route 21 / sea | `waves` vs pond `water` |
| Mt. Moon / underpass | `cave` |
| house + rain | `indoor` + indoor rain, rain still wins |
| loop seams | three full loops of each new bed with no click |

Tune `gain` per bed; document any file that needs a re-encode for seam.

## Files

- `lib/AmbientSound.lua` (`AmbientSound.BEDS` gains)
- `assets/audio/*` if a loop must be re-cut
