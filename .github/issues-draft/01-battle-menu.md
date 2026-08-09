The X/Y command menu draws and works (buttons follow `menuIndex`, the Game
Boy's box is suppressed, everything falls back when the art is missing), but
three things are wrong or unfinished.

### 1. Two languages in one frame

The buttons are the pack's own art with the words baked in — **FIGHT**,
**POKÉMON**, **BAG**, **RUN** — and this build runs in Portuguese everywhere
else (LUTAR, PKMN, ITENS, FUGIR).

Options, cheapest first:
- paint the game's own label over the flat area of each button, keeping the
  body and the little icon;
- go back to drawn buttons (`BattleBoxXY` still has that fallback path, used
  when the art fails to load);
- accept it as a stylistic choice and leave it.

### 2. The player's HUD is moved out of the way by hand

With the command menu up, the panel grows to `MENU_GROW` (1.9x the text
box) and the player's capsule would land on top of FIGHT. `drawXYBlock`
currently shifts it up by the grown amount. It works, but it is two files
agreeing about a number instead of one owning the layout — change
`MENU_GROW` and the shift has to be changed with it.

### 3. Only checked at 1024x768

Every measurement in this work was taken at one window size. The layout is
written in fractions so it *should* scale, but nothing has verified that —
in particular whether the three bottom buttons still read at a small window,
since they are already cut by the panel edge by design.

### Where

- `lib/BattleBoxXY.lua` — buttons, layout, phase gating
- `lib/OverworldBattle.lua` — `drawXYBlock`, the HUD shift
- `tests/battlebox_probe.lua` — measures highlight-follows-cursor by colour

Note the probe's own weakness: its cursor navigation is unreliable and has
landed on the wrong command more than once. Set `menuIndex` directly when
what you are testing is not the cursor.
