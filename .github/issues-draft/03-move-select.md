The command menu is X/Y art; the move list underneath it is still the Game
Boy's white box. This is the second half of the battle interface.

### The target

Four capsules in a 2x2 grid. Each carries the move's name, a type badge with
the type written on it, and `PP now/max`. The selected one is blue, the other
three silver, with a cursor arrow above the selection.

### Everything needed is already in place

- **Cursor**: `battle.moveIndex`, 1..4. Confirmed — DOWN took it from 1 to 2
  inside the `moveSelect` phase.
- **Per move**: `battle.player.curMoves[i]` = `{ id, pp }` (pp is what is
  left).
- **Per move definition**: `battle.data.moves[id]` = `{ name, type, pp, power,
  accuracy }`. `name` is already localised — "ATAQUE RÁPIDO".
- **Art**: `tools/extract_xy_assets.py` already cuts all fifteen Generation 1
  type badges with the word printed on them, plus `slot_sel.png` and
  `slot_plain.png`.
- **Where it goes**: `OverworldBattle.TEXT_RECT.moves`.

### To implement

Add `moveSelect = true` to `BattleBoxXY.PHASES` and draw the four capsules.
The phase gate is what currently hands this phase back to the engine.

### Do not skip the probe

`tests/moveselect_probe.lua` exists because this exact area produced a
regression that every screenshot missed: silencing `drawTextArea` for the
whole battle removed the move list, and choosing an attack became impossible
while the command menu still photographed perfectly. The probe enters the
phase, counts that something is on screen, and leaves again. Keep it passing.
