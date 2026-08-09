## Idea

Players who already install [PokéPC Followers](https://github.com/gamecorner-033/PokePCFollowers)
have the Gen-2 walk sheets on disk under that mod's `assets/sprites/`. Today
Terrarium only looks at its own `assets/roamers/<SPECIES>.png` (or bakes).

## Wanted

If a shipped sheet is missing, try to resolve:

```text
<other-mod-path>/assets/sprites/follower_<SPECIES>.png
```

or `follower_NNN.png`, without copying files, and still mark the def
`trueColor`. Prefer explicit local `assets/roamers/` when present so a
player can override one species.

## Constraints

- Do not hard-depend on PokePC Followers (optional discovery only).
- Do not break when that mod is absent or renames its folder.
- Document in `assets/roamers/CREDITS.md` that using their sheets in-place
  still requires their install / their credit line.

## Files

- `lib/RoamerArt.lua` (`build`)
