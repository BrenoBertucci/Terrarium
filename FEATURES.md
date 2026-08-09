# Terrarium — the manual

Every row, every control, every rule. See [README.md](README.md) for what this
is, where it came from and the legal position; this file is the reference.

> Terrarium is a fork of the [Dramatic Shape Voxel
> Mod](https://github.com/DramaticShape/DramaticShapeVoxelMod) by Dramatic
> Shape. Most of what is described below is his work — this document grew out
> of his README and keeps its shape.

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
| `8`, or the **3D-BTL** options row | ON / OFF — fight on the map instead of on a white field |
| `9`, or the **WILD** options row | ROAM / MIX / OFF — wild Pokémon standing in the grass instead of a dice roll on every step |
| the **W-COUNT** options row | SOME / FEW / MANY — how many stand within reach at once. Only on the menu while **WILD** is on |
| the **BACK SPRITES** options row | OFF / ON — keep your own Pokémon on the battle menu, seen from behind in its classic slot, instead of standing it on the map; the foe is still out there. Only on the menu while **3D-BTL** is on, because it decides nothing without it |
| the **DAYTIME** options row | SYNC / DAY / NIGHT / DUSK / DAWN / CYCLE — what time it is outdoors, on the diorama *and* on the flat 2D world; held at SYNC (and off the menu) while VOXEL is FULL |
| the **RTX** options row | RT / AO / OFF / MAX — the screen-space pass; see below |
| the **AMBIENT** options row | ON / OFF — butterflies and ground birds by day (the birds startle and fly off when you get close), dragonflies over the water, fireflies through the night, a flock crossing the sky, leaves on the wind — and civilian NPCs glance at you as you pass. Trainers never turn: their facing is their line of sight |
| the **WEATHER** options row | AUTO / OFF / RAIN / SNOW — occasional showers, with the whole sky going over with them; snow through the winter of the SYNC clock. See below |
| the **GROUND** options row | ON / OFF — what the weather leaves behind: puddles that gather through a shower and are still there afterwards, snow that settles in drifts, and footprints behind everybody walking on it. Only on the menu while **WEATHER** is on. See below |
| the **EXP** options row | TEAM / SPLIT / OFF — experience for the whole party instead of only the Pokémon that fought. TEAM gives everyone still standing what the fighters got; SPLIT divides that same total among them; OFF is 1996. Only the fighter gets a text box |
| the **ECOLOGY** options row | ON / TIME / OFF — who is out *right now*: the nocturnal half of the dex after dark, the birds and the caterpillars by day, and water Pokémon while it rains. See below |
| the **SOUNDS** options row | ON / OFF — crickets after dark, birdsong by day, water within earshot, rain when it rains and thunder after the flash. CC0 recordings, crossfaded by what the world is doing, with the Game Boy's own channels as the fallback. See below |
| the **INDOOR** options row | ON / OFF — a Pokémon asleep on the floor of about two houses in five, and mugs still steaming on the tables |
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
`Weather.curtain` is full at a power where the streaks are still a drop here
and there, so the wall is drawn and finished with thirteen seconds of approach
still to run. That ordering is the whole effect.

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