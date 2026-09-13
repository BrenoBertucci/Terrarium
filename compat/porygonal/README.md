# Terrarium × Porygonal

[Porygonal – Overworld Characters](https://github.com/CurlyG004/porygonal-overworld-characters)
replaces the overworld cast with 3D models. It does **not** draw anything
itself: it detects one supported 3D renderer mod and swaps the characters
through that renderer's own draw calls, using a per-renderer adapter under
`renderers/<mod>/`.

Every adapter detects by **exact mod id**, so Terrarium was invisible to it —
Porygonal logged *"No compatible 3D renderer was detected"* and did nothing.
This directory is Terrarium's adapter. It is meant to go upstream; until it
does, `install.py` puts it into a local Porygonal install.

| | |
| --- | --- |
| Adapter version | 1.0.0 |
| Validated Porygonal | 0.6.2 (repo), release channel 0.6.4 |
| Validated Terrarium | 1.36.0-beta |
| Licence | GPL-3.0 — derived from Porygonal's `dramatic_shape_adapter.lua` |

## Use it

```bash
python compat/porygonal/make_adapter.py
```

```bash
python compat/porygonal/install.py
```

`install.py` copies the adapter into the installed Porygonal and registers it
in that mod's `renderers/renderer_manager.lua` candidate list, keeping the
original as `renderer_manager.lua.pre-terrarium`. `--uninstall` puts both back.
Both scripts take `--porygonal <path>`; the default is the PC build under
`Quiver-Windows-x64`.

Then enable both mods. `OPTION → PORYGONAL` names the active target mod, and
it should say Terrarium.

## Why a fork of the Dramatic Shape adapter, and not the adapter itself

Terrarium is a Dramatic Shape Voxel Mod fork and keeps its module layout, so
the *integration* is upstream's — this adapter is generated from it. What
differs is that **three of the public functions the adapter wraps grew a
parameter in Terrarium after Dramatic Shape 1.8.2**. Wrapping them at the old
arity does not fail. It drops the new argument on every call, silently:

| seam | Terrarium | wrapped at DS arity | what the player sees |
| --- | --- | --- | --- |
| `Voxel3D.draw` | `(mesh, texture, model, pull, sunModel, sway)` | 5 params | grass, trees and the battle scene's grass stop moving — **the whole frame**, because Voxel3D sends the shader uniform from `sway or 0` on every draw so a swaying pass cannot leak into the terrain after it |
| `SpriteBillboards.mesh` | `(def, frame, cut)` | 2 params | swimmers stand *on* the pond; anybody in tall grass or settled snow is drawn at full height |
| `SpriteBillboards.shadowQuad` | `(def, frame, cut)` | 2 params | the same, in the shadow and ghost passes |

`VoxelScene.render` also differs — upstream's wrapper already forwards a 7th
`eyes` argument that Terrarium ignores — but that one needs no edit.

And `FirstPerson`: Terrarium has no first-person mode and ships no such
module, while its `V.require` **raises** on a missing one rather than
returning `nil`. Upstream requires it unguarded, which would abort
`initialize()` inside the renderer manager's `pcall` and surface as *"adapter
could not be initialized"*. The adapter requires it through `pcall` and treats
absence as a supported state; every use of it in the shared integration is
already nil-guarded.

## The generator

`terrarium_adapter.lua` is **generated**, not maintained by hand.
`make_adapter.py` applies the edits above to upstream's
`dramatic_shape_adapter.lua` and **asserts each one matched the expected
number of times**. A Porygonal release that reshapes one of those call sites
fails the generator loudly:

```
upstream adapter has moved -- these edits no longer apply:
  Voxel3D.draw accepts `sway`                   expected 1, found 0
```

which is the whole point — the alternative is 4k copied lines that quietly
half-work after an update. To re-sync: update Porygonal, re-run
`make_adapter.py`, fix any edit it reports, re-run `install.py`, re-run the
probe.

`luacheck.py` syntax-checks Lua with the engine's own `lua51.dll`, since there
is no standalone Lua on this machine. A broken adapter does not crash — it
reads as *"Porygonal found no renderer"* — so this is worth running on every
regeneration.

## What was measured

`tests/porygonal_probe.lua`, run twice on the same maps: once with the adapter
installed, once without. It instruments **both ends** of each wrapped pair —
the adapter's wrapper (SENT) and the original it captured (ARRIVED) — so a
truncated argument shows up as a number, not a guess.

| | baseline (no adapter) | adapter bound |
| --- | --- | --- |
| `mesh ~= shadowQuad` (something took the seam) | false | **true** |
| `VoxelScene.render` arity | 6 | **7** |
| sway — sent / arrived max | 6.75 / — | **6.64 / 6.64** |
| sway — draws with `sway > 0` | 516 | **532 / 532** |
| cut — sent / arrived max | 5 town, 6 route / — | **5 / 5, 6 / 6** |
| solid draws from a **card**, Viridian | 1610 | **460** |
| solid draws from a **card**, Route 1 | 1537 | **318** |
| total `Voxel3D.draw` calls, Route 1 | 4173 | 4189 |

Terrarium's own behaviour is unchanged — it makes the same 1610 / 1537 card
requests in both runs. What changes is what reaches the draw: roughly 71 % of
character card draws in town and 79 % on Route 1 become Porygonal models. The
remainder are wild roamers (Pokémon, not characters) and anyone Porygonal has
no model for, which correctly keep Terrarium's card.

Screenshots: `probe_out_porygonal/` (bound) against `probe_out_porygonal_base/`
(baseline), same map, same camera, SM64CAM off so the shot is comparable.

Terrarium's own `trees_wind_probe` was run both ways and is byte-for-byte the
same verdict either way, so nothing there regressed. (It reports a broken
motion measurement — `-1.000` on all four rows — in **both** runs. That is
pre-existing and unrelated; it looks like the probe never turns SM64CAM off,
so it collects no still-camera samples.)

## Not covered

- **Gen 2 (Gold).** Porygonal declares `games: ["gen1"]`, so it does not load
  on a Gold boot and Terrarium is untouched there.
- **Fly, bike, surf, fishing and the seated Pokémon Center figure.** The
  adapter carries upstream's handling for all of these unchanged; none was
  exercised by the probe.
- **Installing real `DRAMATIC_SHAPE` alongside Terrarium.** Porygonal refuses
  to choose when it detects more than one renderer, so it would bind to
  neither. That is upstream's rule, deliberately.
- **Cut characters.** Where Terrarium would cut a card at the boots — a player
  standing in tall grass or snow — a Porygonal model replaces it at full
  height, as it does under any renderer with no waterline cut. Water roamers
  are Pokémon, so they keep Terrarium's cut card.

## Upstreaming

The PR into `CurlyG004/porygonal-overworld-characters` is two files and one
list entry:

- `renderers/terrarium/terrarium_adapter.lua` (generated)
- `renderers/terrarium/TERRARIUM_README.txt`
- the `Terrarium` entry in `renderers/renderer_manager.lua`'s `CANDIDATES`,
  plus a row in `renderers/README_RENDERERS.txt`

Once merged, `install.py` is no longer needed — Porygonal ships the adapter
and Terrarium users just enable both mods.
