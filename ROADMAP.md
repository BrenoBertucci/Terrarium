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

| item | draft | notes |
| --- | --- | --- |
| Battle command menu: EN labels, HUD shift, one window size | `01-battle-menu.md` | X/Y UI leftover |
| Town map still GB resolution | `02-town-map.md` | X/Y UI leftover |
| Move select in X/Y capsules | `03-move-select.md` | enhancement |
| Verify REV 3 roamer bake in-game | `04-roamer-bake-verify.md` | Sandshrew / Growlithe without pack |
| Purge stale derived roamer bakes on REV bump | `05-purge-stale-roamer-bakes.md` | players keep unreadable caches |
| Ear-pass ambient gains / loop seams | `07-ambient-ear-pass.md` | under map music, real speakers |
| Catalog text for optional installers | `10-mod-page-optional-assets.md` | X/Y + roamers |

## Next features

| item | draft | notes |
| --- | --- | --- |
| Ambient Tier 2 beds | `06-ambient-tier2.md` | stream, frogs, cicadas, fire, snow_wind, shop — **CC0 only** |
| Ambient Tier 3 one-shots | `09-ambient-tier3-oneshots.md` | door, wind gust, distant thunder |
| Bridge to installed PokePC Followers | `08-pokepc-followers-bridge.md` | use their sheets without a second copy |

## Done recently (unreleased until next package)

- Ambient Tier 1 beds + CC0 credits + source→build policy for audio
- Roamer policy: no redistributed Gen-2 sheets; installer + improved bake
  fallback (`RoamerArt.REV` 3); `trueColor` when sheets present
- Water size / swell fixes in 1.20.0-mobile (shipped)

## Policy reminders

- **No Nintendo / third-party art in the zip** without an explicit licence
  (X/Y GUI, roamer walk sheets). Install scripts only.
- **Ambient audio: CC0 1.0 only** — no CC-BY, no Pixabay/ZapSplat “royalty
  free” terms. See `assets/audio/CREDITS.md`.
- **Licence of the fork itself** is still open upstream — see README.
