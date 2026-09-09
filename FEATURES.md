# Terrarium — the manual

Every row, every control, every rule. See [README.md](README.md) for what this
is, where it came from and the legal position; this file is the reference.

> Terrarium is a fork of the [Dramatic Shape Voxel
> Mod](https://github.com/DramaticShape/DramaticShapeVoxelMod) by Dramatic
> Shape. Most of what is described below is his work — this document grew out
> of his README and keeps its shape.

> **Play Gen 1.** Gold / Johto is an early first pass (since 1.26.0) and is
> **not recommended**. Stay on Red, Blue or Yellow.

A mod for the [Pokémon Gen 1 Recompilation
Project](https://github.com/bryanthaboi/gen1recomp).

The overworld as a 3D diorama. Terrain is extruded into real geometry,
occlusion comes from a depth buffer rather than a y-sort, characters stand
as leaning sprite slabs, a shadow map throws real cast shadows across
whatever they land on, and an optional tilt-shift pass sells the
miniature-model look.

And battles fought on that world rather than on a white field. When
something picks a fight the map's NPCs are culled, the engine's own wipe
plays over the empty map, and the battle draws over the nearest patch of
clear ground — shot over the shoulder, the player's mon low and left and
the enemy high and right, with a slow parallax drift behind them and a
depth-of-field pass that keeps both of them sharp.

And wild Pokémon you can **see**: the map's own encounter table decides who
is standing in the grass right now, and the fight starts when you walk into
one. See below.

The rendering is purely presentational — nothing in it reaches collision,
movement, triggers or scripts. The battle arena is where the **camera**
goes, not where anybody goes: no cell, facing, flag or warp is written, so
the player is standing exactly where the fight found them when it ends. The
one thing that does touch the world is the WILD row, and it is a row: leave
it OFF and the game rolls its dice exactly as it always did.

## Controls

Every key is free-roam only, and each one is also a row on the OPTIONS
menu.

| control | does |
| --- | --- |
| `3`, or the **VOXEL** options row | OFF → 15 → 35 → 50 → 75 → OFF (camera pitch) |
| `5`, or the **V-GRID** options row | OFF / ON — a one-pixel wireframe on every voxel |
| `6`, or the **T-SHIFT** options row | OFF → 1 → 2 → 3 → OFF (miniature blur) |
| `7`, or the **V-CURVE** options row | OFF → 1 → 2 → 3 — bend the world over the horizon |
| `m`, or the **SM64CAM** options row | ON / OFF — the Super Mario 64 camera. A camera operator instead of a fixed mount: it turns to look at you far faster than it flies to where it wants to stand, takes its height from the **ground** under you so walking up a step does not bob the frame, leads the way you are walking, and looks **over** a wall that stands between you for more than a moment rather than steering round it. It orbits **you**, at a bearing only you change, a quarter turn at a time — it never turns on its own — and the **D-pad turns with it**, as in Mario 64. See below |
| `8`, or the **3D-BTL** options row | ON / OFF — fight on the map instead of on a white field |
| `9`, or the **WILD** options row | ROAM / MIX / OFF — wild Pokémon standing in the grass instead of a dice roll on every step |
| the **W-COUNT** options row | SOME / FEW / MANY — how many stand within reach at once. Only on the menu while **WILD** is on |
| the mon pack (always on when `assets/mons` is present) | the Pokemon standing on the field wear their Generation 5 (Black/White) sprites, front and back, in full colour, instead of the Game Boy pic through a palette. ADVANCED and the other COLORS modes do not touch them; the hour's light does. Trainer pics stay the engine's |
| the **BACK SPRITES** options row | OFF / ON — your own Pokémon seen from behind, the series' shot: ON stands it on its tile in the arena wearing its back art, grown to a foreground hero (`OverworldBattle.BACK_HERO`) under the same light and shadow as the foe, with the move cards and the panels floating in front of it; OFF stands it on the map facing the foe, at the foe's own scale. Only on the menu while **3D-BTL** is on, because it decides nothing without it |
| the **DAYTIME** options row | SYNC / DAY / NIGHT / DUSK / DAWN / CYCLE — what time it is outdoors, on the diorama *and* on the flat 2D world; held at SYNC (and off the menu) while VOXEL is FULL |
| the **RTX** options row | RT / AO / OFF / MAX — the screen-space pass; see below |
| the **AMBIENT** options row | ON / OFF — butterflies and ground birds by day (the birds startle and fly off when you get close), dragonflies over the water, fireflies through the night, a flock crossing the sky, leaves on the wind — and civilian NPCs glance at you as you pass. Trainers never turn: their facing is their line of sight |
| the **WEATHER** options row | AUTO / OFF / RAIN / SNOW — occasional showers, with the whole sky going over with them; snow through the winter of the SYNC clock. See below |
| the **GROUND** options row | ON / OFF — what the weather leaves behind: puddles that gather through a shower and are still there afterwards, snow that settles in drifts, and footprints behind everybody walking on it. Only on the menu while **WEATHER** is on. See below |
| the **TREES** options row | VOXEL / 3D — which trees stand on the round-tree sites. VOXEL (default) is the blocky tree grown by `tools/grow_voxel_tree.py`: 2.5-pixel cubes, a visible bole with roots, a crown of lobes with notches and tufts, four shapes (round, tiered, broad, tall) mixed across the wood — and no colour of its own: every leaf cube is painted at map load in the greens the map's own tree tile wears (`TerrainAtlas.tileShades`), so Route 2's trees are Route 2 green and the forest's are the forest's. 3D is `tools/bake_tree.py`'s finer bake: a smoother canopy under a fringe of photographed leaf cards, four species (oak, pine, birch, willow), in its own colours. Both bend in the wind while the trunk stays planted. The old carved ball from the tileset art is no longer a row option; it stands in only where a set fails to load. Flipping the row rebuilds the map's meshes over the next frames |
| the **COMBAT** options row | DINAMICA / CLASSICA — the whole dynamic battle costume. DINAMICA swings the camera in behind the attacker, floats the menu and the box on glass in the arena, hangs HP capsules beside the mons, and puts typed hit sheets at the blow — and the blow reaches the room: a spotlight closes on the attacker, the hit flashes the defender's cell in the move's colour, voxel cubes fly off the floor, a scorch / puddle / frost / crater stays under the defender's feet, a gold damage figure floats up, and every pane of glass leans with the shove, cracks or ripples where the wave strikes it, and prints a shadow on the floor. On the move menu the chosen card wears its element: lightning crawls an ELECTRIC card's edges, flames lick a FIRE card's foot, a swell rolls a WATER card, frost grows on ICE, rings breathe on PSYCHIC, with the type's colour running the rim. CLASSICA holds the camera, lays every panel flat and answers a blow with nothing but the engine's own anims. Only on the menu while **3D-BTL** is on |
| the **EXP** options row | TEAM / SPLIT / OFF — experience for the whole party instead of only the Pokémon that fought. TEAM gives everyone still standing what the fighters got; SPLIT divides that same total among them; OFF is 1996. Only the fighter gets a text box |
| the **ECOLOGY** options row | ON / TIME / OFF — who is out *right now*: the nocturnal half of the dex after dark, the birds and the caterpillars by day, and water Pokémon while it rains. See below |
| the **SOUNDS** options row | ON / OFF — crickets after dark, birdsong by day, water within earshot, rain when it rains and thunder after the flash. CC0 recordings, crossfaded by what the world is doing, with the Game Boy's own channels as the fallback. See below |
| the **INDOOR** options row | ON / OFF — a Pokémon asleep on the floor of about two houses in five, and mugs still steaming on the tables |
| the **HEARTH** options row | ON / OFF — chimneys that smoke. The house family stands a chimney on its roof, and a house with a fire going puts a chain of cel puffs off it that climb, cool, take the wind and thin away. Most houses at dusk, some at dawn, a few through the night, and the cold lights the rest. See below |
| the **TOWER** options row | NEW / CLASSIC — which Pokemon Tower stands in Lavender: the tower modelled by hand (default), or the building kit's plain fold of the same drawing, as it stood before. Flipping it rebuilds the map's meshes on the spot. See below |
| the **LEDGES** options row | BANK / CLASSIC — what a hop-down ledge is: a bank of earth that rises steeply on the side you stand on, crests, and falls gently toward where you land, the ground's own grass rolling over its top and the drawing's earth showing where the fall is steep; or the profile's six-pixel box wearing the ledge drawing on top, as before. Every route in Kanto. See below |
| the **HAUNT** options row | ON / OFF — the tower of graves is haunted. Lavender's Pokemon Tower stands as a tower now (plinth, ashlar body with a pointed portal, storeys of pointed windows under cornices, a lantern storey, a pagoda roof and a spire), its glass burns cold, sparse and breathing after dark, and pale wisps drift out of it. The row is the wisps and the cold glass; the tower stands either way. See below |
| the **CRYPT** options row | NEW / CLASSIC — what the inside of the Pokemon Tower is. NEW stands its seven floors and Agatha's room as a crypt: one continuous octagon of grey stone (the stones proud of their joints, the corners chamfered, a plinth battering into the room) climbing out of the light, the near walls ramping down to a coped parapet so the camera looks over them, the dark beyond, every headstone on a plinth; candle lanterns in wall sconces, the room held dim and cool, a violet haze and wisps sighing out of the graves on the haunted floors, dark flagstones underfoot. CLASSIC is the profile's pins as they were. Flipping it rebuilds the map's meshes. See below |
| the **CRYPT-FX** options row | ON / OFF — the crypt's light, in the shader: every wall and headstone lit by the face it actually turns to the lantern, a hemisphere of fill from above read through the stone's relief, a wet sheen on the stone under each flame, ground mist drifting through the graves, weathered stone and granite on the walls and the headstones with their grain in the light — the walls standing those stones in depth so a lantern rakes a block, not a crate — and the flames blooming into a split-toned frame. OFF lights the crypt the way the streets are lit. Only inside the tower, with CRYPT on NEW |
| the **TOWN** options row | ON / OFF — trainers' Pokemon loose in the streets of every town. Most are out for a stroll (press A to hear them); the one that STARES you down wants to battle, at your own lead's level |
| the **A-FARM** options row | OFF / P1–P6 — pick a party slot and a bot trains that Pokemon; see below |
| the **QOL** options row | ON / OFF — ten mercies: the **bag sorted into pockets** (balls, medicine, TMs and HMs, key items), wrapping and taking a held direction; the PC **following a catch** into whichever box it landed in, and a full box rolling forward instead of refusing a deposit; **RENAME** on the party menu, because Kanto has no NAME RATER; **hidden items glint** on the ground (it does not name them or take them — you still walk there and press A); hold **B to run**; **field poison stops at 1 HP** instead of killing; **trade evolutions at level 37** without a second machine; effectiveness markers on the move menu (`+`/`-`/`x` against the Pokémon in front of you); a fresh REPEL used the moment one wears off; and HMs on the A button — A at a tree CUTs, A at water SURFs, A at a boulder wakes STRENGTH, all behind the same badges and checks the menu applies. OFF is the full 1996 friction |
| the **RES** options row | 1/2 / FULL / 1/3 / 1/4 — what fraction of the panel the 3D pass rasterises at |
| the **SHADOWS** options row | LOW / OFF / HIGH / SOFT — the sun pass; SOFT widens each shadow's edge with distance from what throws it |

**3D-BTL** is on by default and is independent of **VOXEL**: battles draw
on the world whether or not the free-roam camera is pitched over.

Two of the engine's own rows are taken away while this mod is installed:
**TILT**, which is the flat fake of what this mode does for real, and **GBC
FX**, a full-screen present pass over the top of the diorama. Both are held at
off rather than merely hidden — a row that is not there cannot switch off a
value an older save arrived with. Uninstall and both come back, at whatever
they were last set to.

## Wild Pokémon you can see — the WILD row

Gen 1's wild encounter is a dice roll on a step. Walk into tall grass and
every completed step draws `rand(0..255)` against the map's encounter rate;
when it comes up, the screen wipes and something you never saw is suddenly
in front of you. Nothing about that is a decision — you cannot pick a
fight, avoid one, choose which one, or know there was one to choose. The
grass is a slot machine you pull by walking.

This makes the roll **visible**. The same encounter table, rolled the same
way against the same ten probability buckets, decides who is standing in
the grass *right now* — as ordinary map objects, wearing their own art,
wandering their own patch — and the fight starts when you walk into one (or
press A at one). So the grass becomes a place with things in it: go round
the Zubat, go after the Abra, or cross the route without fighting anything
at all.

| rung | what happens |
| --- | --- |
| **ROAM** | they stand in the grass, and the blind roll is off. What you fight is what you walked into. |
| **MIX** | they stand in the grass **and** the roll still happens, so the grass can still surprise you. |
| **OFF** | none of this runs; the game rolls the dice exactly as it always did. |

Where they stand is the same three cases the roll covers, read off the same
records: **grass** on a route, the **whole floor** of a cave or a tower, and
the **water** — the last only while you are surfing, because a Tentacool
bobbing across a pond you cannot reach is set dressing that costs a sprite.

What is **not** changed is anything that decides *what* a wild Pokémon is.
The species, the levels and the slot odds are the ROM's, read through the
same data the roll reads. **REPEL** still works and reads better for being
seen — nothing weaker than your lead appears at all, so the grass is
visibly empty of the small stuff while it lasts. And a battle that starts
here is the engine's own wild battle pushed down the engine's own
`pushBattle`, so the transition, the Safari menu, the catch, the experience
and this mod's own staged arena all happen without knowing where the fight
came from.

Two places deliberately keep their dice. The **Pokémon Tower** without the
Silph Scope, because a Gastly wandering about with its own art answers the
question that floor exists to ask — pick the Scope up and it populates like
anywhere else. And any map this cannot cover at all: no encounter table, no
room to stand anything on, or art that would not bake. The blind roll stays
switched on exactly where nothing has replaced it, which is the difference
between replacing the encounter and deleting it.

## The SM64 camera (SM64CAM)

A port of Super Mario 64's camera, from the decomp (`n64decomp/sm64`,
`src/game/camera.c`). Off by default; the whole of it lives in
`lib/MarioCam.lua`, and the file names the decomp's own functions so it can be
read against that source.

The system is two ideas and the rest is detail hung off them.

**The target and the real are different objects.** One function says where the
camera *ought* to be this frame -- pure geometry, no history. A second layer
*chases* that answer. Mixing them is what makes cameras that get stuck in
feedback loops.

**The focus and the body move at different speeds.** The point the camera
looks at closes 80% of its gap per frame; the camera's own body closes 30%.
Run away and the operator is already looking at you while still catching up.
Measured in the running game, the body's steady-state lag comes out 6.33 times
the gaze's against a predicted 6.35 -- that gap is most of what SM64 feels
like, and it costs two constants.

### It never turns on its own

SM64's defining mode orbits a fixed point of the **area** -- a mountain you
cannot stand on -- and the first cut of this port did the same with the map's
own centre. On a Gen 1 town that centre is the square everybody walks through,
and the orbit's yaw swings hardest exactly there: measured, twenty degrees
across Celadon's plaza with no key touched. Add the wall steering (up to eighty
degrees round every fence and house corner, and back) and the camera "changed
all the time", which is the complaint that retired both.

The camera is now an orbit round **you**, at a bearing that **only you
change**. It does not turn for where you are on the map, for which way you
walk, or for a wall. What is left of SM64 is everything else: the two-layer
chase, the floor-derived height, the lead, the dead zone, and the spherical
arc between one bearing and the next.

**Every bearing it rests at is a quarter turn.** The sprites are four drawings
-- front, back, one profile and its mirror -- with nothing for in between, and
a camera parked at 60 degrees showed a character walking diagonally across the
screen in art drawn for straight on. So `q`/`e` step ninety degrees, the stick
snaps to the nearest quarter when you let go, and the SHOULDER follow re-aims
to a cardinal. The view still arcs between them; it never stops in between.

### The D-pad turns with it

**This is the one thing in the mod that changes how the game controls.**
Everything else is presentational and says so.

SM64 makes the stick camera-relative in one line, and without it an orbiting
camera is not a camera, it is a puzzle: the world turns under you while Up
keeps meaning north. So Up means **away from the camera**, at every quarter
turn -- and the mapping only ever changes when *you* turn the camera, never
under a held button.

The walk itself is an ordinary walk through ordinary collision -- the world
still speaks compass in every direction that matters, and press Up under a
quarter turn and the player genuinely walks west, exactly as if west had been
pressed. Turn the row off and the 1996 controls come back untouched.

| control | does |
| --- | --- |
| `q` / `e` | turn the camera a quarter turn (SM64's C-left / C-right) |
| `r` | put the camera at your back (SM64's R button, repurposed: the alternate mode it swapped to existed to stop an automatic camera turning, and this one never does) |
| `f` | the zoom ladder, three rungs (SM64's C-down) |
| right stick | the same turn, continuously, settling on the nearest quarter when released. The N64 had four C buttons and no second stick; this machine has one |

Every press answers with a sound -- the game's own `Tink` and `Switch`, and
`Denied` inside an authored shot that has taken the framing.

### Characters turn to face you

Two fixes that the orbit made necessary, and both were plainly visible before
they were made.

A character is a flat card. It used to face due **south** and only lean back,
which is exactly right for a camera that cannot turn -- and the moment the
camera could, the card was seen edge-on and the character read as **lying flat
on the pavement**. The card now turns to face the eye before leaning.

And the *drawing* on it is now chosen by the angle **the camera sees**, not by
the compass. Stand north of someone walking north and the old code handed you
their back while they advanced toward you: a **moonwalk**. Four positions from
three drawings is the ROM's ceiling, not a choice -- Gen 1's sheets are
down / up / left, with right a mirror of left, and no sprite in the game has a
diagonal in it. So the reading quantises to a quarter turn, with hysteresis at
the boundary so it does not flicker.

The rest of the rig is there too: the height comes from the floor under you
rather than from you, so steps and ledges do not bob the frame; a dead zone
just under a cell absorbs the grid's staircase while you walk and recentres
when you stop; mode changes interpolate in spherical coordinates so the camera
*arcs* around you instead of cutting through the building it changed because
of; warps and map changes cut rather than fly; a wall that stands between
you and the lens for more than half a second lifts the lens to look over it,
and pulls the camera in only when no lift clears it (a corner passed at a
walk moves nothing); and the shake is a damped
cosine applied *after* the smoothing, attenuated by distance from whatever
caused it, so it leaves no drift behind.

Indoors it pulls in close, on water it drops behind you, and
`data/camera_shots.lua` is the surface for hand-placed shots -- the lesson the
SM64 writeup repeats most is that no generic algorithm beats an authored
camera in the ten percent of cases that are hard. It ships empty on purpose.

### The art

Gen 1 draws no Pokémon on the map. Eleven species have an overworld sheet
because a script stands one somewhere; the other hundred and forty have
exactly one drawing each, and it is the battle front pic. Resampling that
portrait into a 16×16 cell is how Sandshrew used to look like Charmander —
battle art is not walk-cycle art.

**Optional Gen 2-style walk sheets** make each species legible at map scale.
They do **not** ship with the mod (same licence rule as the X/Y GUI pack).
Install them with:

```text
python tools/install_roamer_sprites.py
```

That fetches [PokéPC Followers](https://github.com/gamecorner-033/PokePCFollowers)
(ShockSlayer / Crystal Clear lineage) and drops 16×96 sheets into
`assets/roamers/<SPECIES>.png`. Details:
[`assets/roamers/CREDITS.md`](assets/roamers/CREDITS.md). Installed sheets
are `trueColor` so the palette pipeline leaves their colours alone.

Without them, a greyscale front-pic bake still runs into
`save/mod-derived/TERRARIUM/roamers/` — the feature stays, the art is worse.

Because the sheet is a real file at a real path, it is a sprite the
**engine** understands: tall grass overdraws its feet, the diorama cuts its
card from it and the sun throws its silhouette. Drop a replacement 16×96
sheet at `assets/roamers/<SPECIES>.png` and it is used as-is.

## Pokemon in the streets — the TOWN row

A town in Gen 1 is the emptiest place in the game: no encounter table, no
grass, a handful of scripted NPCs walking two-cell beats. With this row on,
trainers' Pokemon are out in it — strays and companions loose in the
streets, wearing their own art, wandering the same walk every NPC walks.

Most are **pacifists**, just out for a stroll: press A and one turns,
cries its own cry, and a line of text says what it is doing out here. You
cannot fight what does not want to fight.

About one in three is a **challenger**, and the tell is that it *stares*:
walk within a few cells and it stops dead and turns to face you, and keeps
facing you — the trainer-sight stare, worn by the Pokemon instead. Press A
and it asks for the match. Accept and it is a real battle at your own
lead's level, so a town stop is always worth XP without outclassing the
route next door; refuse and it shrugs back into its stroll.

They are wild battles under the hood, so a thrown ball works. Whether
catching a town's stray is sporting is left to the player's conscience.

## Auto-farm — the A-FARM row

Pick a party slot and a bot trains that Pokemon. It is swapped to the
front of the party first — Gen 1 gives its experience to the Pokemon that
fought, and the lead is the one sent out — and the row follows the swap,
so the menu never lies about which slot is being trained.

On the map the bot walks the wild ground: tall grass on a route, the whole
floor of a cave. With the **WILD** row on it *hunts* — the nearest roamer
standing in the grass is walked into, the same bump that starts the fight
for a player. With WILD off it paces the grass and lets the engine's own
dice roll the encounters.

In a fight it always picks the strongest move against what it is actually
facing — power, STAB, the type chart and accuracy, with the
self-destructive and the situational (Explosion, Dream Eater on something
awake, the charge-turn moves) discounted for what they are — and runs from
a wild fight it is losing.

At level-up, the learn-a-move prompt is answered **by value**: the new
move and the four known ones are scored — damage output for attacks, a
curated worth for status moves, redundant same-type coverage discounted —
and the lowest-value move is the one forgotten, unless that would be the
new move itself, in which case it is declined. Thundershock is forgotten
for Thunder; Growl is forgotten for Agility; Tail Whip is declined
outright; Thunderbolt is never lost to anything, and an HM move is never
forgotten at all.

Below half health the bot drinks from the bag — weakest potion first, one
sip per beat, until the trained Pokemon is topped back up — so a stack of
potions makes the farm genuinely AFK. It stops itself — and sets its own
row OFF, so the state is visible — rather than grind a party into the
ground: when HP is critical and the bag has nothing left, when the mon
faints, when its damaging moves run out of PP, when the map has nothing to
farm, or when the local wild Pokemon are immune to everything it knows. It
never throws a ball, never uses any item but its potions, and a Safari
fight is immediately run from. While it runs, the bot owns the controls;
switch the row OFF to take them back.

## Weather — the WEATHER row

Kanto has one sky and it never changes. With this row on **AUTO** it gets
showers: a minute or two of rain every few, arriving and clearing on their
own, about one minute in eight.

What makes it read as weather rather than as an effect being switched on is
that **five things move on one number**. A single `power`, eased from zero to
its peak over seven seconds, drives every one of these — so the world darkens
at exactly the rate the rain thickens, because they are the same ramp.

| what | what the shower does to it |
| --- | --- |
| the sky | loses its blue toward a flat stratus grey, band by band, so the gradient survives — an overcast horizon is still paler than an overcast zenith |
| the light | drops and goes cool, on the diorama **and** on the flat 2D world, through the same one-tint-two-worlds seam the day/night clock already solved |
| the sun | loses its twilight halo. A sunset behind a rain front has no gold in it |
| the water | loses its glint and gains chop — rain breaks every crest that was catching the sun into a thousand small ones pointing everywhere, so the toon highlight is gone rather than dimmed |
| the air | fills with rain, drawn in two registers at once (below) |

Rain is drawn **twice**, and it has to be. **Streaks** are screen-space: flat
pale lines falling across the whole frame, leaning on the WIND row's own
bearing, because rain between the camera and the world has no world position —
it is in front of everything, and giving it one puts it behind the trees.
**Splashes** are world-space: little cel-shaded rings that open on the ground
around you, projected through the same camera the field FX and the ambient
life anchor through. They are what says the rain is landing on *this world*
rather than on the lens, and they are why the effect survives the camera
moving.

The heaviest of it brings **lightning**: the flash lights the whole diorama at
once, and the thunder arrives afterwards by however far away the strike was.

**Snow** drifts *in* the diorama rather than across the lens — a flake has a
position in the world, wanders down through it on the wind and lands, which is
the whole reason snow looks like snow. AUTO chooses it on its own through the
winter of the same wall clock the DAYTIME row's SYNC rung follows. Which
hemisphere that winter belongs to is the one thing in the feature that cannot
be derived — a timezone is a longitude and the seasons are a latitude — so it
is a constant, `Weather.HEMISPHERE` at the top of `lib/Weather.lua`, shipped
as `"south"` and one word away from Kanto's own December.

None of it is **drawn** indoors, or under Viridian Forest's canopy: a room has
no sky to rain out of, and a roof of leaves is why that map is a canopy. The
**sound** goes on, quieter and pitched down, because that is what a roof is
for.

That split is a real distinction in the code and it was a bug before it was a
feature. `Weather.falling` means "what is the weather doing in Kanto" — indoors
the answer is still *raining*, which is right for the sound and wrong for the
picture. `Weather.visible` is the one every draw path asks, and it is gated on
the same open-sky test the sky, the sun and the hour's tint already rest on.

### Watching it arrive

A shower **builds over twenty seconds**, not seven, and the length of that
number is the feature. From about a fifth of the way up the ramp there is a
**curtain** on the horizon — the same shower, drawn as vertical shafts under
the cloud deck and over the haze band, where a shower is the only place it is
ever visible *as* a shower: from far enough away to see the shape of it.

It is **not a forecast**. Nothing in this mod knows the future, and building a
lookahead would have meant leaking the next spell's roll to every reader for
one picture's sake. It reads as *coming* because it **leads** the near field:
`Weather.curtain` is full at a power where the near field is still a drop
here and there, so the wall is drawn and finished with thirteen seconds of
approach still to run. That ordering is the whole effect.

The rain itself is no longer a sheet on the lens. World-space **shafts** fall
through the diorama and stop on whatever `VoxelScene.groundAt` says is there
— the street, a puddle, a pond, a roof — and spawn a splash of the right
kind (a crown on water, a tick and a drip off an eave). A thin screen-space
mist stays between the camera and the near edge, because that air has no
world position. Indoors and under a canopy, none of it draws.

Snow gets a thinner one. A squall coming in reads as the horizon going soft,
not as shafts — shafts are what falling water does, and snow does not fall in
lines.

### The sky that can flash

The stratus grey is deliberately **neutral**: what says "it is raining" is the
loss of blue, not the loss of light, and an overcast noon is bright. That is
still right for an ordinary shower and it is left alone.

It is wrong for the shower that throws lightning, which is not a darker grey
but a **bruised** one. So `DayNight.storm` is a *second* register above the
stratus rather than a replacement for it, and it only leaves zero above
`Weather.STRIKE_ABOVE` — the same gate that arms the strike. A drizzle keeps
the grey it always had; a sky that has gone violet is, by definition, a sky
that can flash. Two storms is all it takes to learn that pairing, and it costs
nothing to teach.

### And after it stops

**God rays**, for the length of the post-rain spell. They are drawn where the
deck is **thin**, because that is what a ray is — light through a gap — and
the cloud raymarch has already worked out how thick the deck is at each pixel,
so the entire effect is one `atan` and one `sin` on top of work already done.

Hard rungs and the same checker dither as the bands, never a smooth falloff: a
soft ramp here is bloom, and bloom is the one thing this sky may not become. A
moon throws none — a moonrise is silver, not gold.

## The air — the WIND row

The tall grass out here is **geometry**, not a picture: a tuft is a real
stamped mesh with a base in the ground and a top free to give. That is the
whole reason this row can exist. A tile animation is one image shared by
every cell drawing that tile, so every tuft on a route moves in perfect
unison forever — machinery, at any price. A vertex shader knows *where each
vertex is*, so the wave's phase can come from the tuft's own world position,
and then the gust **travels**: it arrives at the near edge of a meadow,
crosses it, and leaves.

| Rung | What it does |
| --- | --- |
| `AUTO` | the row hands itself to the climate — **default** |
| `BREEZE` | living outdoor air, inside a fixed band |
| `GALE` | the same air, amplified |
| `OFF` | silence — accessibility, screenshots, quiet sessions |

**AUTO** is the answer to the one complaint the older ladder earned: BREEZE
and GALE are two fixed windows onto the same climate, so a player who wants
a storm to actually feel like a storm walks back to this menu every time the
sky changes — the row doing the weather's job by hand. AUTO spans both
windows on one continuous curve, bent low so a calm afternoon stays calm,
and pushed the last of the way by a front so a downpour arrives at gale on
its own. Measured: about **0.7 px** of tip reach on a clear day and **3.4–4.7
px** under a shower, with nobody touching anything.

### What the blade actually does

- **The bend is a bend.** Displacement grows with the vertex's own height
  above the base, squared, so the roots stay planted and the tip folds.
- **The tip comes down as it goes over.** A stem is not a rubber band:
  moving XZ alone silently *stretches* every blade as it leans, which is
  exactly the look of grass sliding. Holding the arc length instead drops
  the tip by about `lean² / 2H`.
- **Every tuft is its own plant.** One hash off the 8×8 cell a tuft stands
  in gives it a stiffness (some are young and whippy, some are woody), a
  phase offset, and a bearing it slumps along. Nothing is stored per
  instance — the mesh is one buffer for a whole map, and the only thing a
  vertex knows about which tuft it belongs to is where it is.
- **The gust is a front.** A second, much longer wave on the same bearing
  modulates the amplitude itself, so the air arrives in bands rather than
  blowing everywhere at one flat strength.
- **Rain is weight.** Falling rain damps the sway — a wet meadow moves
  *less*, not more — bows the blades down, and adds a fast little tick on
  each tuft's own phase as drops land.
- **Settled snow is worse, and it stays.** It reads off the accumulated
  cover rather than the snowfall, so a meadow is still bowed and half-still
  after the sky clears. Blades slump on their own bearings, so a snowed-in
  patch looks *loaded* rather than leaning together.
- **And snow PILES ON it.** This one needed a channel of its own. Every
  other surface in the world takes its snow from its face normal — a roof
  ridge points at the sky and goes white, a wall does not — and by that
  rule a grass blade is a *side*, correctly, along its whole length. So a
  meadow took the flank's third and stopped, standing green next to ground
  that had gone white. But snow does not care that a blade is vertical: it
  lands from above and rests on the **crown**, which is why real winter
  grass is white on top with green showing underneath. The tuft now carries
  a cap weighted by how far up the blade you are and how much has settled,
  and it feeds the same snow path a roof does — threshold, drift, grain and
  the sun's glitter all run on it — so a snowed meadow gets the world's own
  snow rather than a white decal laid over it.
- **Feet flatten it and it springs back.** The crush list is kept between
  frames with a strength and a velocity per foot: a fast chase on the way
  down (a boot does not bounce) and an underdamped spring on the way up,
  which carries the tuft *past* upright about a third of a second after the
  foot lifts and settles inside two. That kick is what reads as a plant
  standing up rather than as a flattened patch fading out.
- **And it lies DOWN, rather than getting shorter.** Shrinking a blade's
  height reads as the meadow deflating — the tuft stays upright and simply
  becomes a smaller upright tuft. A walked blade folds: the tip travels
  outward by most of its own height and comes down by nearly all of it, so
  it ends up along the ground pointing where the walker went.
- **A walk leaves a TRAIL.** A spring is right about one tuft and wrong
  about a walk — the crush is a disc that follows the walker, and two steps
  later nothing says anybody was ever there. So a moving foot drops
  **crumbs** every ten world pixels: weaker, narrower crushes at the places
  it just left, spaced closer than their own reach so the eye joins them
  into one laid line, fading on their own clock over four seconds with no
  spring, because grass that has been walked flat and left does not snap
  back, it recovers. Stop, turn around, and the way you came is still there
  for a couple of seconds. Roamers and street Pokémon lay one too, and
  flowers are in it — the beds people walk through are the same beds.

The eight shader slots are split rather than shared: the first three are
live feet, the rest are trail. A crowd of roamers can never crowd out the
trail, and a long walk can never crowd out the foot actually standing in
the grass.

Roamers standing in the meadow lean on the **same clock** — `Wind.leanAt`
is the CPU twin of the vertex shader's wave, front and load included, so a
body and the tuft beside it are never on two schedules.

### Wind you can see, off the grass

A meadow only reports the air that is *inside* it. On paving, on sand, on a
path with no tall grass in frame, a gale used to be invisible. So the air
carries **streaks** — short flat comet-tails of what is in it: dust on a
clear day, the rain's own pale blue as spray under a shower, blown white
under a fall. Nothing round, soft-edged or additive; a soft particle over a
cel-shaded diorama is the one thing that reads as a filter laid on the world
rather than as something in it.

And when the squall envelope crosses over — the same number the grass is
bending to — a **rank goes across abreast**, perpendicular to the bearing
and all on one clock, so the gust crosses the frame as a line while the
grass bows under it. The two are one event seen twice.

Below a floor of wind, indoors, under a canopy, or with the row OFF, it
draws nothing at all: a calm day is calm, and motes drifting through a still
meadow would be the effect announcing itself.

## What the meadow remembers — the wear field

Everything above is *reactive*. The wind pushes and the tuft leans back; a boot
folds a blade over and a spring stands it up; a trail crumb fades in six
seconds. Walk away and come back and the meadow is exactly as it was. Nothing
in it had a memory longer than a breath.

So every grass cell now carries a **wear** value that goes up when something
walks on it and comes back down over in-game **days**. It rides the save file,
next to what time it is in Kanto — because which paths this journey has worn
into a route is a fact about the journey.

And the player is not the only one writing it. The wild Pokemon wandering their
patch and the civilians walking their routines deposit too, at their own
weight, off the same list of feet the foot-crush springs already build. A route
therefore grows **desire paths** along the traffic that actually crosses it,
including corners the player has never stood in. Trample tops out short of bare
earth, though: the game only lets you walk where it lets you walk, so given
enough hours the walkable set *is* the trampled set, and a ceiling below bare is
what keeps a well-used path reading as a path instead of as a bald route.

A worn cell **thins** rather than shrinks. Individual tufts fold back to their
own root and drop out — the cell loses plants — because scaling every tuft down
together reads as the meadow deflating, which is what a level-of-detail pop
looks like rather than what a path looks like. Underneath, the earth shows
through as trodden dirt, since sparse tufts standing on vivid green would read
as a rendering fault.

Two things reach that value besides feet. **Cut** clears a cell outright, and a
cut cell has no wild encounter until it grows back — so a corridor through a
forest is something you can make and something that expires. And a **ground
lightning strike** burns the grass where it lands, leaving a char scar that
outlives a footpath by a good part of the journey.

The same texel carries one more thing, for free: how **sheltered** that cell
is, baked once per map out of the walls already in it. The wind goes around a
house instead of through it, so a meadow in a building's lee stands still while
the open field waves — and the edge of the calm moves with nothing at all,
because buildings do not move.

On the cheap quality rungs the tufts stop thinning and the earth still shows:
the ground is drawn on the processor, so the world keeps remembering even where
the grass has stopped commenting on it.

## What the rain leaves behind — the GROUND row

The WEATHER row draws what is falling. This draws what has **fallen**, and
the difference between them is time: a shower is over in two minutes and the
ground it soaked is wet for ten. Without it the sky clears and Kanto is
instantly, impossibly dry — the effect switching off rather than the weather
ending.

Two numbers, both slow, both driven by the shower the same way everything
else in it is driven by `Weather.power`. **Wet** climbs through a downpour
and drains away over four minutes. **Cover** is the snow settling, and takes
seven to melt.

**Puddles** gather where the ground is flat, walkable and out of the grass —
and *where* is a **hash**, not a die, for the same reason the sleeping
Meowth's house is: water that appeared somewhere else every time a map
streamed back in would be a particle system rather than weather. The same low
corner of the same yard holds water every time it rains, forever, which is
what a low spot is.

They are **few and wide**, on a block grid — the map is cut into three-cell
blocks and each holds at most one pool, on the first of its cells that can
actually hold water. Rain collects; the low spot next to a low spot is one
low spot, and a street stippled with small pools is not what a wet street
looks like. They wear the **sky's own colour** — the horizon band, normalised
so only the hue carries — because a puddle is a piece of the sky lying on the
ground, and one that stayed grey through a sunset would be the only thing on
screen not taking part in the evening. With the **RTX** row at RT or MAX they
also *reflect*: the same ray march across the same depth buffer the ponds
get, so a pool on the road carries the hedge beside it.

**Snow** falls in three drawings rather than one at three sizes — a dusting
caught in the seams of the paving, then patches, then lying with the ground
showing through in dithered holes. That is the difference between snow and
water: a pool is the same pool getting wider, and a snowfall is a different
picture at each depth.

And it settles on **everything** — the hedges, the trees, the roofs — not
only on the ground you can walk on. A field of snow with green bushes
standing in it reads as a fresh coat of paint. What wears a cap is any cell
you cannot stand on that stands above the ground, which is the shape
profile's own description of a tree or a roof and needs no list of tile ids.

And **footprints**, behind everybody: you, the NPCs, the wild Pokémon in the
grass. Dropped on the cell somebody *left* rather than the one they arrived
at, so the trail is behind them, and filled back in over half a minute —
faster while it is still snowing, because that is what snow does to a
footprint. When the list is full the oldest print *somebody else* left goes
first, so your own trail survives a meadow full of wandering Rattata.

All of it is drawn as **geometry between the ground and the people standing
on it**, not as an overlay: a butterfly is in front of the world and a puddle
is underneath the person standing in it. So it is depth-tested — a puddle
behind the Mart stays behind the Mart — takes the hour's light and the sun's
own shadows for free, and never paints over anybody's feet. The price of that
footing is the same one the steam off a mug pays: it wants the **VOXEL**
camera on.

The shapes are generated — an ellipse with a wobble, a blob with a dithered
fringe — but they are only the fallback. Drop a strip of 16×16 frames at
`assets/ground/puddle.png`, `assets/ground/drift.png` or
`assets/ground/print.png` and it is used as-is, however many frames wide it
is, with nothing generated. Two rules a replacement has to keep, and both are
the scene shader's rather than this feature's: the **alpha is the shape** (
anything under half alpha is discarded rather than blended, so draw hard
edges and dither a fringe), and the **RGB is a tone, not a colour** (every
texel is multiplied by the colour this picks, so a strip drawn in greys lands
right at every hour and one drawn in blue comes out blue times blue at dusk).

## Who is out right now — the ECOLOGY row

Gen 1 has one encounter table per map and it is the same table at every hour
of every day in every kind of weather. Gen 2 answered that with three tables
per map — morning, day, night — and it is the single change that did the most
to make Johto feel like a place rather than a set of rooms with monsters in
them. This is that, built out of what Gen 1 already ships.

**Nothing is added to a route and nothing is taken away.** Every Pokémon this
can produce is one that route's own table already names, at the level that
table already gives it, with exactly one exception (the rain, below). What
moves is the **odds**: the ten-slot table is drawn from with its own
cumulative buckets, exactly as `Encounter.roll` does, and each slot's share of
the 256 is then multiplied by what the hour and the sky think of that species.

So a Zubat is still on Route 4's table at noon — it is simply the least likely
thing on it instead of being as likely as it was at midnight. That is
deliberately weaker than Gen 2, which made its night species night-*only*:
deleting half a route's table for half the clock would break the promise the
WILD row rests on, and would turn a dex you are halfway through into a
waiting game.

Who keeps what hours is **Gen 2's own answer** wherever Gen 2 had one — every
name in the nocturnal list is a Gen 1 species that Johto or Kanto put on a
night table, so it is the series' own later reading of its own creatures
carried back a generation. Zubat, Gastly, Oddish, Venonat, Clefairy, Meowth,
Drowzee, Rattata, Grimer, Koffing, Cubone, Krabby and Pinsir are night; the
birds, the caterpillars, the fighting types and the fire types are day.
Anything in neither list falls back to its **types** — a Ghost or a Poison
leans nocturnal, a Flying or a Fire leans diurnal — at half the weight,
because it is half a guess. A Ditto has no opinion about the sun and does not
get one.

**Indoors none of it applies**, and that is the same rule the rest of this mod
already holds: a cave at midnight is exactly as dark as a cave at noon, so a
Zubat down there lives in the dark whatever the sky is doing.

At **ON** the sky joins in. While it rains the water types on a table come up
and the fire types go in, on the shower's own `power`, so it arrives at the
rate everything else the weather touches arrives at. On most Kanto routes that
alone would do very little — most grass tables have no water type on them at
all — so there is a second lever: **water Pokémon come ashore.** In a heavy
shower, a spawn on land within three cells of actual water may be drawn from
the map's own water roster instead — `encounters[map].water` where the map has
one, and otherwise `field.superRod[map]`, which is the ROM's own answer to
"what lives in this map's water" for thirty-three maps with no surf table. So
a Psyduck comes up out of the pond it was already in, onto the bank it was
already next to, because it is raining.

Its **level** is clamped into the band the map's own grass table uses, and
that is the one number here that is neither the ROM's nor derivable: the fish
rosters are levelled for a Super Rod you get late, and a level 23 Kingler on
Route 6 would not be atmosphere, it would be a difficulty spike wearing a
raincoat. The species is the ROM's, where it is standing is the rain's, and
how hard it hits is the route's.

All of this reaches the **blind roll** as well as the visible Pokémon: under
MIX and OFF it rides the engine's own `encounter.species` seam, which runs on
a roll that already happened and before the repel filter, so repel, the ghost
rule, the Safari menu and the battle itself all go on reading the answer
rather than the question. Under ROAM the tilt happened when the roamer was
placed, in the open, some distance away — which is the whole point of that
row.

**TIME** is the hour without the sky, for a player who wants Gen 2's clock and
Kanto's own indifferent weather. **OFF** is the flat table, drawn byte for
byte the way the original draws it.

## The sound of the place — the SOUNDS row

Crickets after dark, birdsong through the morning and the day, water moving
whenever there is water within a few cells of you, rain when it rains, thunder
after the flash.

They are **beds, not blips**. Four of the five loop, and what the world does is
crossfade them: nightfall brings the crickets up rather than switching them
on, walking away from a river takes the river down, a shower brings the rain up
over ten seconds beside the sky going grey, and dusk is one bed rising as
another falls. Only thunder is a one-shot, because a thunderclap is one.

The recordings live in `assets/audio/` and every one is **CC0** — no
attribution required, no share-alike, so nothing here sets terms on this mod
or on a fork of it. `assets/audio/CREDITS.md` names each recordist anyway, and
says why several otherwise-good CC-BY-SA nature recordings were passed over.
Drop a file with the same name in that folder and it is used instead.

This shipped once as **pure synthesis** — every sound a Game Boy channel
program, not a byte of audio on disk. It was a good argument and a bad result:
a square-wave blip is a convincing menu beep and an unconvincing cricket, and
at the level ambience has to sit, under the map's own looping song, a thin blip
is not quiet, it is inaudible. The synth reproduces a Game Boy's sound effects
perfectly, because that is exactly what they are; it cannot do a field at dusk,
because a field at dusk is a hundred overlapping sources and the hardware has
four.

The channel programs are still here and still registered under real ids
(`DS_AMB_CRICKET` and friends), and they finally do the job they were always
right for: the **fallback** when a file is missing, an assets folder is
stripped from a build, or a driver will not decode Vorbis. The ambience gets
worse rather than disappearing.

Everything sits under the map's own music and obeys the SFX volume row like
every other effect. It works with the diorama switched off: a sound needs no
camera.

Dead air is trimmed off each recording before it loops — a looping source
repeats its buffer with no gap, so a beat of silence at the tail is a hole you
hear every time round, and two of these files carry most of a second of it.
Decoding costs about 100 ms for the longest, once per bed per session, on the
frame that bed first comes up. `tests/ambient_beds_probe.lua` measures all of
it again.

Where there is water is counted by **looking**, in cells, rather than kept as
a list of maps with ponds on them — so a route with one pond in the corner
only sounds like water when you are in that corner.

## Houses somebody lives in — the INDOOR row

About two houses in five have a Pokémon asleep on the floor, usually the
family Meowth. It is a real map object — the same kind of thing the WILD row
stands in the grass, wearing its own art baked from its front pic — so the
engine y-sorts it, the sun throws its shadow, the palette bake colours it and
the diorama cuts its card. It is asleep, so it never takes a step and never
wants a fight. Press A and it stirs, yawns its own cry a little slow, and goes
back to sleep.

**Which** house has one is decided by the house's own name — a hash, not a die.
That is the load-bearing choice: a random roll would put a cat in a different
house every time you walked in, and a cat that teleports between houses is not
a pet, it is a spawner. Hashed, a house either has one or does not, forever,
and it is always the same Pokémon asleep in the same corner. It is placed
against a wall and clear of every door, because a real object blocks and the
answer to that is to put it where nobody was going to walk.

Gen 1 draws no sleeping pose for anything, so it stands in its ordinary
overworld art and the **Z**s over its head are what say it is asleep — three
bars in a Z rather than a font glyph, because the font's own characters are
black-with-alpha and a pale mark on a dark floor is not something `setColor`
can make out of them.

And **mugs left on the tables, still steaming**. Where a table is comes from
this mod's own shape profile rather than from a list of coordinates: every
interior tileset here already names its `table` and `counter` tiles by id, for
the entirely different purpose of extruding them to the right height, and that
list answers "is there a tabletop at this cell" for free. So a mug lands on a
table in a house nobody wrote a line of code about — and a total conversion
that adds its own tileset gets mugs on its tables by pinning them the way it
already had to.

The sleeper is a real map object and stands in the room in **both** modes; the
steam and the Zs are drawings composited into the diorama's own overlay pass,
so those two want the **VOXEL** camera on.

## Chimneys that smoke — the HEARTH row

Every house in Kanto has had a stove going since 1996 and not one of them has
ever shown it. The building kit already knew how to stand a **chimney** on a
roof — only the Center's rooftop ball ever asked for one. The house family
asks now: the two-storey gabled house, the cottage, the wide house, the day
care and the doorless blocks that share their drawings all carry a small stack
at the back of the roof, capped in the drawing's own outline shade.

**And a house with a fire going puts smoke on it.** A puff leaves the flue
every second or so (the **PFX** row scales that), climbs hard at first and
slower as it cools — the lift dies with the puff's age, squared — takes
whatever air the **WIND** row is moving and its eddies, spreads as it rises
and thins into nothing over about five seconds. Rain weighs the plume down and
shortens it; a gale tears it flat. In a dead calm the column stands straight
up, which is exactly when the wind's own field has nothing to draw.

**Which houses.** Not every house, and not all day. Each chimney holds a
stable number from a hash of the house's own place on the map — the same
trick the **INDOOR** row picks its sleepers by, so the same houses always
light first. Against it stands one figure: how many of the town's hearths are
lit *right now*. It rises with the meals of the day — nearly everyone at dusk,
about half at dawn, the banked fires through the night, almost nobody at noon
— and with the cold: winter on the SYNC calendar, snow falling or lying, a wet
evening. A chimney smokes while its number is under that figure, so as the
evening comes on the town lights up house by house, always in the same order.

**The puff is authored, not shipped.** A sixteen-pixel cloud drawn at load in
the three tones everything cel in this mod wears — a body, a darker underside,
a one-pixel rim — with a hard silhouette and no gradient. It is a card in the
diorama's own 3D pass, so a roof hides the smoke behind it, the hour tints it
(warm at dusk, near-white in snow) and the sun's shadow falls on it; drawn last
and without writing depth, because smoke is translucent and must not hide the
roof it is drifting past. Wants the **VOXEL** camera on; the flat 2D world
gets nothing, like every other drawing in this list.

`tests/hearth_probe.lua` measures it: the mouths the map stands, the gate, the
dusk figure, the rate against the module's own clock, the climb, the drift
with and without wind, the batches, and an ON/OFF pair of captures above each
stack.

## The tower of graves — the HAUNT row

Lavender's Pokemon Tower was the one building in Kanto whose Game Boy drawing
is a **tower** — a three-tier latticed roof over twelve rows of windowed
facade, straddling the Route 10 seam — and the one the building kit folded
wrong: the roof band laid flat, the facade extruded, a 96-by-100 brick box
with a striped lid. It stands as a tower now (`lib/TowerKit.lua`), modelled
by hand the way the interiors are: a stone plinth in the drawing's own
threshold; a blind lower body in weathered ashlar — staggered joints,
damp-dark at the foot, streaks running down from under the string course —
with a pointed portal opening on black, lantern niches either side of it and
slit windows; a pale cornice; a set-back storey of three courses of tall
pointed windows sunk three voxels deep under white sills, quoins at the
corners; a second cornice; a lantern storey of pointed glass on every face;
and the drawing's own lattice roof wrapped as a three-tier pagoda under a
spire. Two hundred and thirty voxels from the ground to the tip — four
houses high — and every voxel wears a texel of the tower's own drawing.

**The sombre part is light, not paint.** The palette is the town's own and
stays that way. What turns the drawing into stone is a shade per texel class
that the model hands the building kit: the drawing's white held to well under
half its brightness is the grey of the blocks, the same white a shade under it
the joints, the damp foot and the streaks; the lattice keeps its deep violet,
the cornices' fascia stays pale — and the whole tower is darkest at the foot,
in the town's shadow, climbing toward the light at the top, which is most of
what makes a tall thing read tall. Grey stone under a violet roof: the tower
belongs to Lavender without being another purple house. The sun pass grew to
cover it (`ShadowMap.HEIGHT`), so its shadow falls whole.

**Haunted glass.** The windows are the facade's own panes, so they light
after dark like every window in Kanto — except that inside the tower's
footprint the scene shader draws them as a dead house's: six in ten stay
dark, what burns is a cold pale blue rather than lamp-amber, dimmer, and every
lit pane breathes on the slow clock instead of the odd one flickering. By day
the same panes read as dark glass, no lamp-yellow behind the stone.

**And the tower breathes.** After dark — on the same curve that lights the
town's windows — pale wisps slip out of the lantern storey's glass, a few from
the portal's mouth, a rare one off the spire; they climb, hang, take the
**WIND** row's air and its eddies and thin into the violet haze over about
eight seconds. Each is a teardrop card with a halo behind it, drawn flattened
toward its own glow so the night cannot put it out, in the diorama's 3D pass
with depth writes off, like the smoke. The **HAUNT** row is the wisps and the
cold glass; the tower stands either way. Wants the **VOXEL** camera on.

**The terrace.** Lavender draws the edge of the tower's yard as hop-down
ledges — down both sides and along the south, with the entrance's dark arch
in the middle — and the profile's ledge class stood them as six-pixel boxes
wearing the lip drawing on top: a mat of orange wicker round the foot of a
stone tower. They stand now as the tower's own low ashlar wall, six voxels
thick under a pale coping, with piers at the corners, at the end and either
side of the gate, in the ledge's own white texels held down to grey. One
piece per cell shape, matched by tiles and confined to the terrace — the same
ledge tiles run every route in Kanto, and the town's other ledge line is Route
8's carrying on across the seam, so those stay ledges. The hop still works; it
is a wall you hop over. And the speckled ground of the yard and the strip east
of it — half of Kanto's routes wear the same tile and keep it — is paved one
voxel deep in grey flagstones of two sizes, the same white held down.

**Which tower.** The **TOWER** options row picks NEW — this one — or CLASSIC,
the building kit's plain fold of the same drawing, as it stood before.
Flipping it rebuilds the map's meshes on the spot, the way the **TREES** row
does; the cold glass, the wisps and the terrace wall belong to the NEW
tower only.

`tests/lavender_tower_probe.lua` measures it: the model builds without
falling back to the band fold, the stamp records its haunt and the camera's
occluder height, the shader compiles, the wisps are live at night, frame time
at a fixed frame day and night — and screenshots from the plaza, the door and
the orbit, at dawn, day and night (`tests/run_tower.cmd`).

## The crypt — the CRYPT and CRYPT-FX rows

The tower's seven floors and Agatha's room draw with one tileset: a ring of
wall panels cut out of a grey mass, a field of headstones, a flight up and a
flight down. The profile stood the ring as a 16px course of boxes wearing the
panel drawing — in Lavender's palette a ring of red crates on a grey table
top under a black sky, and the headstones as thin cutouts. A 2D chamber reads
as a chamber because the eye supplies the walls; a diorama has to build them.

**The walls** (`lib/CryptKit.lua`). Every ring cell that touches the room
stands as a tall wall of ashlar — courses of blocks with staggered joints, a
proud plinth, a string course, a pilaster at every corner the ring turns —
in the drawing's own white held down to grey by light, its top rows falling
into the dark so the far walls climb out of the light and no ceiling is
needed. The near walls are cut down to a parapet under a coping — the
dollhouse cut every fixed-camera crypt is drawn with — so the camera at the
south looks over them at the room. The grey stock beyond the ring, and the
ring cells that never touch the room, go to a black slab: the crypt is walls
standing in darkness. Which model a cell gets is decided per placement
(which sides face the room, how tall its row stands, whether a lantern hangs
on it), so a wall knows where the room is without the template having to.
The ring is ONE wall, not a stack of 16px crates: a cell knows what stands
beside it (the room, another wall cell, the dark) and answers the next
cell's masonry to the hidden-face test as phantom voxels computed by the
same formula, so no face is drawn where two cells touch; the wall is stone
through and through, whichever face of it the camera finds; where the ring
steps down toward the camera the top ramps from one row's height to the
next under a coping of stone, its stones a voxel up or down so the cut is
a wall's top and not a ruled line. Two-face cells chamfer to a true
octagon, the plinth batters two voxels into the room, tall walls lean back
a voxel every few courses, and with CRYPT-FX on every stone of the wall
photograph stands proud of its joint (two voxels into the room at the
highest, one voxel back at the mortar) so the silhouette is the picture the
shader paints, not a box wearing it. Every flank takes the same share of
light whichever way it turns — there is no sun in here — so it is the
lanterns and the occlusion that say which way a face looks.

**The graves.** A headstone is a solid: a plinth, the stone on it wearing
its own drawing front and back — its checker crown and ink rim turned to the
panel's own greys, the bands and the lettering kept — the two small posts
beside it; three variants by cell hash so a field of them is not a stamp,
and about the height of the person walking past — taller and a stone in
front of the player would hide him from the camera, which is the law every
authored shot answers to.

**The light** (`lib/Crypt.lua`). Candle lanterns hang in wall sconces where
the light is — the scene shader's point lights, warm, breathing on the gas
clock, a flame card with a halo over each — and the interior's flat light is
held down and cooled, lowest on the haunted floors, because there was never
too little light indoors, there was too little dark. Dark flagstones lie over
the white lattice. Every floor carries its own air: a dark haze below, the
town's violet heavier on 3F–6F, so the far wall sinks back; and on those
floors one grave in six sighs a wisp, small and low, in still air.

**The shader's share — the CRYPT-FX row.** The lanterns light every flank by
the face it actually turns to them (the real face normal, from the world
position's derivatives — exact on voxels), so a wall turned away goes dark;
a wet sheen sits on the stone under each flame; a ground mist drifts through
the graves on two octaves of noise, lit where it lies under a pool, and
stops where the floor stops. The walls wear photographed rubble masonry, the
headstones polished granite over their own drawing so the design stays, the
floor worn flagstones (three CC0 surfaces from Poly Haven, see
`assets/stone/README.md`), each with its relief map turned into the normal
the lanterns light by — so a flame rakes across real stone — a gloss and a
sheen per material, soot above every flame, moss and damp at the foot. The
kit carves those same stones in depth off the photograph's height map, so
a lantern rakes the *side* of a block, not a sticker on a crate. There is
no sun in here: the noon rig's shadow is off, and in its place a hemisphere
— a face that looks up takes the whole of the room's fill, one that looks
along takes less, read through the relief maps so the stone keeps its grain
between the lanterns too. A slow drift of tone across the wall on a scale
no cycle of the photograph has keeps the eye from finding the repeat. The
flames bloom into the frame and throw rays across it, the corners are
shaded, and the frame is finished with a contrast curve, a split tone (the
darks toward the crypt's violet, the lights toward the flame), a vignette
and a breath of grain. The voxel wireframe and the ANIME row's cel step
both stand aside while this is on. OFF lights the crypt the way the
streets are lit; CLASSIC on the **CRYPT** row is the interior as it stood
before, whole.

## What a ledge is — the LEDGES row

A Gen 1 ledge is a one-way step: you stand on the high side, press toward
it, and hop down to the landing. The overworld draws it as a bump of hatched
earth seen face-on, and the profile's ledge class stood every one of those
tiles as a six-pixel box wearing the drawing on its **top** — a run of orange
wicker mats across every route in Kanto.

**In a flat world a ledge is a bank.** The diorama's ground is one plane, so
the high side and the landing both stand at zero and there is no terrace for
a terrace edge to belong to. The honest shape left is a ridge of earth: it
rises steeply on the side you stand on, crests, and falls away gently toward
where you land. From the camera, which looks north and down, an east-west
bank's steep side hides behind its crest and the gentle side faces the lens —
a grassy slope with a dark rim at its foot, which is what the drawing meant. A
north-south bank shows its steep side obliquely, as the small earthen face it
is; a north-south bank is symmetric, crest down the middle, because a steep
side there would face the lens as a small cliff for no reason the flat world
can give. Eight voxels tall for a run sixteen deep, six for one eight deep.

**Every ledge in Kanto.** A census of the shipping maps finds seventeen cell
compositions holding a ledge tile — east-west runs and their rounded ends,
north-south runs hopped westward and eastward, the corners and junctions
between them — plus the mound's shaded east slope and its north-east corner,
which the same art language draws beside them and the profile stood as
sixteen-pixel boxes; each is one or two *strokes* in the profile
(`data/voxel_heights.lua`): a ridge along an axis with a height profile across
it and a rounded taper at its ends; a cell's height is the maximum of its
strokes, so an L of ridges meets in a rounded corner for free.

**Nothing is repainted.** The bank's top and its gentle slope wear the ground
tile of the side you hop from, picked per placement and tiled on the world
grid so the meadow continues over the bank; the steep risers and the foot
wear the drawing's own earth and outline. A grass or path tile that shares a
cell with a ledge is never claimed, so a path does not turn to grass where a
ledge crosses it. Lavender's terrace keeps its stone wall; the rest of the
town's ledges are banks like Route 8's, so nothing changes at the seam.

`tests/ledges_probe.lua` measures it in five towns and routes: the banks
build with their ground variants, the shared tiles stay unclaimed, the
CLASSIC row brings the boxes back, and frame time on Route 4's hundred-odd
ledge cells — with screenshots of each kind (`tests/run_ledges.cmd`).

## Water with a bed — the WATER row

CALM / SWELL / FLAT is still what the row says, and it still means what it
meant: how much the surface heaves. What changed is underneath it. The
water is no longer a picture of water.

It used to be one quad per water tile, sunk two pixels below the ground and
wearing the tileset's own animated tile — the Game Boy's water standing on
its side, with a two-pixel lip where the bank stepped down to it. A blue
floor. Now every water tile carries a **bed**, cut in whole voxel terraces
by how far the tile is from the nearest bank (five steps of one cell each,
from the shallows against the shore down to the deep), the banks drop all
the way to it, and the **surface is a translucent sheet** drawn last of the solid
world, so the bed shows through it.

What that buys, with nothing painted blue anywhere:

- **Depth you can read.** The bed is sand lit by the hour, and what comes
  back up through the water is what the water did not absorb — red first,
  blue last, per channel. So the shallows along every bank are sand and
  green-gold, and the middle of a lake is the deep blue because it is deep.
- **The shore continues under the water.** A bank keeps a share of its own
  art below the waterline, darkening as it goes down, instead of stopping
  at a lip.
- **Caustics.** Where the swell's long trains peak together the surface is
  a lens, and the bed under it lights up in hard cel diamonds that move
  with the waves and fade with depth. A FLAT pond focuses nothing.
- **A waterline that moves.** The surface's own height says where the
  water meets the bank, so the foam line on a wall climbs and falls with
  the swell, and just above it the bank is damp.
- **A Fresnel sky.** Looking down into the water you see the bed; looking
  across it you see the sky — the dome's own colour, greyed by whatever
  cloud deck is over it — and the sun still catches on the crests.
- **A foam ring** where the sheet meets the bank, lapping on the tide's
  clock and reaching further under chop.

Everything the row and the weather already did — three fixed wave trains,
the size-of-the-body field, the glint window measured against the slope
this water can reach, chop and crest foam under rain and wind, freeze into
an opaque lid, snow that only lies on it once it has frozen — still
happens, on the sheet. RT / MAX reflect off it as they did. Surfing, the
swimming Pokémon and the waterline cut on their sprites never moved: the
sheet sits exactly where the old plane sat.

Cost: every water pixel is now shaded twice (the bed, then the sheet over
it), plus one quad per water tile in a group of its own culled with the
terrain and bank walls a few pixels taller. Measured on the i3 + UHD at
FULL and RTX MAX, on the two wettest shots (the Route 25 lake, the Route
21 sea): about a tenth to a seventh slower than the flat water was --
and RES 1/2 or RTX RT gives it all back. Land is untouched.

## Fake ray tracing — the RTX row

Everything on this row is a **ray marched across the depth buffer the 3D
pass has already filled**. Nothing traces the world: there is no
acceleration structure, no second scene, no extra geometry. There is one
image of the diorama and one record of how far away each of its pixels is,
and every effect here is a question answered by walking a straight line
across that record and reading what it hits. That is why it costs texture
fetches rather than triangles — the world is drawn exactly once either way.

| rung | what it marches |
| --- | --- |
| **AO** | *ambient occlusion.* Eight neighbours in a ring, each asked whether it stands above this point's own surface plane. Where many do, the point is in a corner and the sky is boxed out of it — so doorways, the foot of every wall and the gap between two trees darken. |
| **RT** | AO, plus **the water reflects.** The ray leaves the surface along the swell's *own* analytic normal — the same two crossing wave trains the vertex shader displaced it by — and is marched until it lands on something, which is then read straight out of the colour buffer. So a pond reflects the tree beside it, and the reflection travels with the crest carrying it. |
| **MAX** | both, plus **light shafts.** Every pixel marches toward the sun's own disc — the same one the sky hangs — counting how much of that line is open air. A clear run gets the whole beam, a roof in the way gets none, and the boundary between them is a god ray. |
| **OFF** | nothing, and nothing allocated: the pass does not even ask for the readable depth buffer the others read. |

Two limits come with the technique and are worth knowing rather than
being surprised by. It can only reflect or shade **what is on screen** — a
reflected ray that leaves the frame fills in with the sky rather than with
the bank it would have hit. And it needs a driver that can hand back a
readable depth canvas; where one cannot, the row still cycles and nothing
happens, exactly like every other capability this mod asks for.

The whole row runs at the resolution the scene was *rasterised* at, so
turning **RES** down turns this down with it — quadratically, like
everything else in the frame.

Everything the battle screen draws as a box — the two HUD blocks, the text
box and the menus over it — sits on frosted glass rather than on the white
field it used to have behind it: the world underneath, blurred and laid back
down translucent, with the ink flipping white where the ground it lands on is
dark. Nothing the engine draws inside a box moves; only the paper is gone.