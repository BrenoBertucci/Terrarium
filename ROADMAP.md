# Roadmap / backlog

Living list of work that is **not** closed. Prefer a GitHub issue when one
exists; this file is the map when issues are not filed yet.

File drafts on GitHub (after `gh auth login`):

```text
powershell -File .github/issues-draft/create.ps1
powershell -File .github/issues-draft/create.ps1 -OnlyNew
```

Issues URL: https://github.com/BrenoBertucci/Terrarium/issues

---

## Must fix / verify soon

| item | issue | notes |
| --- | --- | --- |
| Battle command menu: EN labels, HUD shift, one window size | [#2](https://github.com/BrenoBertucci/Terrarium/issues/2) | X/Y UI leftover |
| Town map still GB resolution | [#3](https://github.com/BrenoBertucci/Terrarium/issues/3) | X/Y UI leftover |
| Move select in X/Y capsules | [#4](https://github.com/BrenoBertucci/Terrarium/issues/4) | enhancement |
| Verify REV 3 roamer bake in-game | [#5](https://github.com/BrenoBertucci/Terrarium/issues/5) | Sandshrew / Growlithe without pack |
| Purge stale derived roamer bakes on REV bump | [#6](https://github.com/BrenoBertucci/Terrarium/issues/6) | players keep unreadable caches |
| Ear-pass ambient gains / loop seams | [#8](https://github.com/BrenoBertucci/Terrarium/issues/8) | under map music, real speakers |
| Catalog text for optional installers | [#11](https://github.com/BrenoBertucci/Terrarium/issues/11) | X/Y + roamers |

## Next features

| item | issue | notes |
| --- | --- | --- |
| Ambient Tier 2 beds | [#7](https://github.com/BrenoBertucci/Terrarium/issues/7) | stream, frogs, cicadas, fire, snow_wind, shop — **CC0 only** |
| Ambient Tier 3 one-shots | [#10](https://github.com/BrenoBertucci/Terrarium/issues/10) | door, wind gust, distant thunder |
| Bridge to installed PokePC Followers | [#9](https://github.com/BrenoBertucci/Terrarium/issues/9) | use their sheets without a second copy |

## Done recently (unreleased until next package)

- (empty -- 1.22.0-mobile took trees, canopy shelter, rain/drip, lamp load)

## Policy reminders

- **No Nintendo / third-party art in the zip** without an explicit licence
  (X/Y GUI, roamer walk sheets). Install scripts only.
- **Ambient audio: CC0 1.0 only** — no CC-BY, no Pixabay/ZapSplat “royalty
  free” terms. See `assets/audio/CREDITS.md`.
- **Licence of the fork itself** is still open upstream — see README.
