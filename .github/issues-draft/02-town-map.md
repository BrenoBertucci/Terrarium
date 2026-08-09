The map is now one row under ITENS in the start menu instead of five inputs
through the bag (`lib/StartMenuMap.lua`), and it opens the engine's own
`src.ui.TownMap`. Reaching it is fixed; the screen itself is untouched.

### What it looks like now

The Game Boy's town map: 160x144, four shades, a blinking square for where
you are. Next to the X/Y menu that opens it, it reads as a different game.

### Worth doing

- **Draw it at window resolution.** Same move the start menu needed: the
  engine draws into the 160x144 UI canvas, so the fix is to draw into the
  world canvas from the pipeline's present hook and shadow the screen's own
  `draw` on the INSTANCE. `lib/StartMenuXY.lua` is the worked example.
- **Say where you are properly.** The engine marks the player's location;
  a name plate and a clearer marker would carry further than a blinking
  square.
- **The pack has map art.** `5X HUD/map` carries a green pin (already cut as
  `assets/menuxy/icon_map.png`), plus 256x128 pieces not yet identified.

### Things already known

- `TownMap.new(game)` takes the game and nothing else — no bag state needed.
- The screen object carries `locs`, `playerLoc`, `sel`, `mode`, `byMap`,
  `blink`, `bg`.
- `tools/extract_xy_assets.py` is where any new cut belongs, not a manual
  crop: the pack is not in this repository.
