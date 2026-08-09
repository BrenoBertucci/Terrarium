# Ambient audio credits

Every file in this folder is **CC0 1.0 (public domain dedication)**. CC0 asks
for no attribution and imposes no share-alike, so nothing here puts a
condition on this mod or on anything built from it -- but the people who
recorded them are named anyway, because that is the decent thing and because
anyone replacing a file should know what they are replacing.

Nothing here is CC-BY or CC-BY-SA. That was a deliberate filter: a
share-alike recording would reach out and set terms on the rest of the mod,
and an attribution-only one would put a condition on every fork. Several
otherwise-good cricket and bird recordings on Wikimedia Commons were passed
over for exactly that reason. Pixabay, ZapSplat, Sonniss GDC bundles, Envato,
Adobe Stock and the YouTube Audio Library were also passed over -- they are
"royalty free" under their own terms, not CC0.

Verified on each asset's own page (not a search-filter result). Check date
for the added Tier-1 beds: 2026-08-09.

| file | source | author | licence |
| --- | --- | --- | --- |
| `crickets.mp3` | [Crickets Ambient Noise - loopable](https://opengameart.org/content/crickets-ambient-noise-loopable) | Wolfgang_ | CC0 1.0 |
| `birds.ogg` | [Ambient Bird Sounds](https://opengameart.org/content/ambient-bird-sounds) | isaiah658 | CC0 1.0 |
| `rain.ogg` | [Rain (loopable)](https://opengameart.org/content/rain-loopable) | Ylmir | CC0 1.0 |
| `water.ogg` | [100 CC0 SFX #2](https://opengameart.org/content/100-cc0-sfx-2) | rubberduck | CC0 1.0 |
| `thunder.ogg` | [100 CC0 SFX #2](https://opengameart.org/content/100-cc0-sfx-2) | rubberduck | CC0 1.0 |
| `wind.ogg` | [wind1](https://opengameart.org/content/wind1) | Luke.RUSTLTD | CC0 1.0 |
| `forest.ogg` | [Forest Ambience](https://opengameart.org/content/forest-ambience) | TinyWorlds | CC0 1.0 |
| `cave.ogg` | [Loopable Dungeon Ambience](https://opengameart.org/content/loopable-dungeon-ambience) | JaggedStone | CC0 1.0 |
| `waves.ogg` | [Sea and river wave sounds](https://opengameart.org/content/sea-and-river-wave-sounds) | RandomMind | CC0 1.0 |
| `town.ogg` | [S13-05 Light cafe background walla](https://freesound.org/people/craigsmith/sounds/675073/) | craigsmith | CC0 1.0 |
| `indoor.ogg` | [Room white noise - Room Ambience](https://freesound.org/people/Littleboot/sounds/147300/) | Littleboot | CC0 1.0 |

`rain.ogg` is track 2 of the four in that pack; `water.ogg` is
`sfx100v2_loop_water_02.ogg` and `thunder.ogg` is `sfx100v2_thunder_01.ogg`,
both taken unedited out of the hundred-sound pack.

`wind.ogg` is a mono loop cut from `wind1.wav` (one of the five PureData
wind beds in that set). `forest.ogg` is a mono loop cut from
`Forest_Ambience.mp3`. `cave.ogg` is a mono loop cut from
`dungeon_ambient_1.ogg`. `waves.ogg` is a mono loop cut from the short
`VistulaShort.mp3` river/wave recording (not the 180 MB full hour).
`town.ogg` is a mono loop from craigsmith's vintage Hollywood walla transfer
(unintelligible murmur -- not spoken dialogue). `indoor.ogg` is a mono loop
from Littleboot's room-tone recording.

All six added beds were re-encoded to mono Ogg Vorbis (~q5, 44.1 kHz),
level-matched, and given a short crossfade seam so a looping Source does not
click on the wrap.

## Replacing one

Drop a file with the same name here and it is used instead -- the paths are
resolved at play time, not baked. Ogg Vorbis or MP3, either is fine.

Four of the original five loop, so **dead air on the ends matters**: a looping
source repeats its buffer with no gap, and a beat of silence at the tail
becomes a hole you hear every time round. `stripSilence` in
`lib/AmbientSound.lua` measures it off whatever it is given, so a replacement
file does not have to be tightly topped and tailed. What it actually found in
the original set is worth knowing, because it is not the file format you would
expect:

| file | head | tail |
| --- | --- | --- |
| `crickets.mp3` | 0 | 0 |
| `rain.ogg` | 0 | 0 |
| `water.ogg` | 0 | 0 |
| `birds.ogg` | 65 ms | 767 ms |
| `thunder.ogg` | 40 ms | 829 ms |

The MP3's encoder padding is already handled by the decoder; the two files
that needed trimming are Oggs whose recordist simply left the tape running.

Decoding a file costs about 100 ms for the longest one here, once per session,
on the frame that bed first comes up.

The original five also have a **synthesized fallback** -- a Game Boy channel
program in `lib/AmbientSound.lua` -- used when a file here is missing or will
not decode. The six beds added later have **no chip fallback** (`chip = nil`):
if their file is missing they stay silent. Degrade quiet is the house default
for anything that never had a synth version. So deleting this folder costs the
quality of the original ambience and removes the new layers entirely, never
the feature that was already there.
