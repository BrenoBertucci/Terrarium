-- Parry and charge, checked WITHOUT the game.
--
-- Everything these two modules decide is arithmetic over three numbers -- how
-- many frames are left, what a grade is worth, what a parry costs -- and none
-- of it needs a battle to be wrong in. So it is checked here, where a wrong
-- band or an off-by-one on the window fails in a second, and the live probe
-- (tests/battleparry_probe.lua) is left to check the one thing this cannot:
-- that the foe's turn really is deferred and the HP really does fall less.
--
-- Run: tools/run_battleparry_offline.py (lupa; no LOVE, no engine, no ROM).
-- The runner stubs `love` and hands each module the V namespace main.lua
-- would; a module reaching for anything else fails loudly here rather than
-- quietly in a fight.

local V = ...
local Parry = V.require("BattleParry")
local Charge = V.require("BattleCharge")

local fails, checks = 0, 0
local function eq(got, want, tag)
  checks = checks + 1
  if got ~= want then
    fails = fails + 1
    print(("FAIL %s: got %s want %s"):format(tag, tostring(got), tostring(want)))
  end
end

-- ------- the window's three bands
--
-- The press is graded off `waitFrames`, which the engine counts DOWN to zero
-- and then runs the foe's turn -- so the number IS frames-to-impact and the
-- bands are read at, not after, their edges.
local G = Parry.gradeFor
eq(G(0), "perfect", "impact frame is PERFECT")
eq(G(Parry.PERFECT_AT), "perfect", "perfect band is inclusive")
eq(G(Parry.PERFECT_AT + 1), "good", "one frame past perfect is GOOD")
eq(G(Parry.GOOD_AT), "good", "good band is inclusive")
eq(G(Parry.GOOD_AT + 1), "early", "one frame past good is a MISS")
eq(G(Parry.WINDOW), "early", "the first frame of the window is a MISS")

-- the bands have to be ordered, or the ring lies about where the beat is
checks = checks + 1
if not (Parry.PERFECT_AT < Parry.GOOD_AT and Parry.GOOD_AT < Parry.WINDOW) then
  fails = fails + 1
  print("FAIL the bands are not nested inside the window")
end

-- one press per window: the second never overwrites the first. press() is the
-- only stateful half, so it is driven through a stand-in battle.
do
  Parry.setting.index = 1                      -- LIGADO, without touching a save
  local fake = { waitFrames = Parry.WINDOW, queue = {},
                 enemy = {}, player = {}, data = { moves = {} } }
  fake.enemy = { mon = { hp = 10 }, isPlayer = false }
  fake.player = { mon = { hp = 10 }, isPlayer = true }
  Parry._open(fake, "TACKLE")
  eq(Parry.press(), true, "the first press is taken")
  fake.waitFrames = 0
  eq(Parry.press(), false, "the second is refused")
  eq(Parry.debug().grade, "early", "mashing spends the attempt")
  Parry._close()
  eq(Parry.debug(), nil, "a closed window reports nothing")
  eq(Parry.press(), false, "and answers no press")
end

-- ------- what a grade is worth
eq(Parry.multFor("perfect"), Parry.PERFECT_MULT, "perfect multiplier")
eq(Parry.multFor("good"), Parry.GOOD_MULT, "good multiplier")
eq(Parry.multFor("early"), 1, "a miss costs full damage")
eq(Parry.multFor(nil), 1, "no press costs full damage")
-- the invariant that matters more than any of them: a parry NEVER raises the
-- blow. If this ever fails, the feature is a punishment.
for _, grade in ipairs({ "perfect", "good", "early" }) do
  checks = checks + 1
  if Parry.multFor(grade) > 1 then
    fails = fails + 1
    print("FAIL parry raises damage for " .. grade)
  end
end

-- ------- CHARGE is the parry's fuel, and nothing else's
--
-- Moves are paid in PP only; the meter exists for the parry. Three things have
-- to hold: a press costs PARRY_COST, an empty meter REFUSES the press rather
-- than spending it as a miss, and a PERFECT gives the cost back.
do
  Charge.setting.index = 1                     -- LIGADO
  Charge.reset()
  local fake = { waitFrames = Parry.WINDOW, queue = {},
                 enemy = { mon = { hp = 10 } }, player = { mon = { hp = 10 } } }
  eq(Charge.canParry(fake), true, "a fresh meter can pay for a parry")
  eq(Charge.payParry(fake), true, "the press is paid")
  eq(Charge.read(), Charge.START - Charge.PARRY_COST, "...at PARRY_COST")

  -- drain it, then the press must be refused and leave no grade behind
  while Charge.canParry(fake) do Charge.payParry(fake) end
  Parry._open(fake, "TACKLE")
  eq(Parry.press(), false, "an empty meter refuses the press")
  eq(Parry.debug().grade, nil, "...and a refused press is not a MISS")
  Parry._close()

  -- a PERFECT refunds what the press cost
  Charge.reset()
  Charge.gain(fake, 0)                          -- sync to START
  local before = Charge.read()
  Parry._open(fake, "TACKLE")
  fake.waitFrames = 0
  eq(Parry.press(), true, "a funded press on the beat is taken")
  Parry._close()
  Charge.gain(fake, Charge.PARRY_GAIN)          -- what the deferred turn does
  eq(Charge.read(), before - Charge.PARRY_COST + Charge.PARRY_GAIN,
     "a PERFECT refunds its own cost")
  checks = checks + 1
  if Charge.PARRY_GAIN < Charge.PARRY_COST then
    fails = fails + 1
    print("FAIL a PERFECT no longer pays for itself")
  end

  -- the meter floors and ceilings
  for _ = 1, 10 do Charge.payParry(fake) end
  checks = checks + 1
  if (Charge.read()) < 0 then fails = fails + 1; print("FAIL meter went negative") end
  Charge.gain(fake, 99)
  eq(Charge.read(), Charge.MAX, "the meter ceilings at MAX")
end

-- ------- switched off: no meter, and the parry is free
do
  Charge.setting.index = 2                     -- DESLIGADO
  Charge.reset()
  local fake = { waitFrames = 0, queue = {} }
  eq(Charge.read(), nil, "OFF draws no meter")
  eq(Charge.canParry(fake), true, "OFF never refuses a parry")
  Parry._open(fake, "TACKLE")
  eq(Parry.press(), true, "OFF: the press is taken without a meter")
  Parry._close()
  Charge.setting.index = 1
end

-- ------- moves are PP only: the move-cost API is gone for good
eq(Charge.costOf, nil, "no move cost function survives")
eq(Charge.blocks, nil, "nothing gates a move on CHARGE")

-- ------- the creature pairing
--
-- lib/CreaturePack.lua chooses which of Tuxemon's 411 creatures stands in for
-- each species, off the species' own types and evolution depth. Four things
-- have to hold or the pack is worse than no pack: everybody gets one, nobody
-- shares, the element is respected, and the answer is the SAME every session
-- (a save whose Pikachu is a different creature each launch is a bug the
-- player cannot report).
do
  local Creatures = V.require("CreaturePack")
  -- index 2, not 1: NINTENDO is values[1] and therefore the default, because
  -- this row repaints every mon in the game and does not get to do that
  -- unasked. LIVRE is the one under test here.
  Creatures.setting.index = 2
  eq(Creatures.setting.values[1], "mons",
     "the creature row defaults to the art the player installed")
  local pool = Creatures.available() and true or false
  checks = checks + 1
  if not pool then
    fails = fails + 1
    print("FAIL creature pool missing -- run tools/install_creature_pack.py")
  else
    -- a stand-in dex: two lines and a loner, with types the map knows
    local dex = {
      EMBERLING = { types = { "FIRE" }, evolutions = { { species = "EMBERION" } } },
      EMBERION  = { types = { "FIRE", "FLYING" }, evolutions = {} },
      SPROUTLET = { types = { "GRASS", "POISON" }, evolutions = { { species = "BLOOMER" } } },
      BLOOMER   = { types = { "GRASS", "POISON" }, evolutions = {} },
      TIDEFIN   = { types = { "WATER" }, evolutions = {} },
      SPARKMOUSE = { types = { "ELECTRIC" }, evolutions = {} },
      BOULDERKIN = { types = { "ROCK", "GROUND" }, evolutions = {} },
    }
    local map = Creatures.pair(dex)
    checks = checks + 1
    if type(map) ~= "table" then
      fails = fails + 1
      print("FAIL pair() returned no map")
    else
      local n, seen, dupe = 0, {}, nil
      for _, slug in pairs(map) do
        n = n + 1
        if seen[slug] then dupe = slug end
        seen[slug] = true
      end
      eq(n, 7, "every species is paired")
      eq(dupe, nil, "no creature is used twice")

      -- element: the pool row for the chosen creature has to carry the type
      -- the species asked for. Read straight off the shelf, not off the score.
      local byslug = {}
      for _, row in ipairs(V.data("creature_pool")) do byslug[row.slug] = row end
      local function typesOf(species)
        local row = byslug[map[species:lower()]]
        local set = {}
        for _, t in ipairs(row and row.types or {}) do set[t] = true end
        return set
      end
      eq(typesOf("TIDEFIN").water, true, "a WATER species gets a water creature")
      eq(typesOf("EMBERLING").fire, true, "a FIRE species gets a fire creature")
      eq(typesOf("SPARKMOUSE").lightning, true,
         "an ELECTRIC species gets a lightning creature")
      eq(typesOf("BOULDERKIN").earth, true, "a ROCK/GROUND species gets earth")

      -- the line: the first form must not be paired deeper than the second
      local DEPTH = { basic = 0, stage1 = 1, stage2 = 2, standalone = 0 }
      local d1 = DEPTH[(byslug[map.emberling] or {}).stage] or 0
      local d2 = DEPTH[(byslug[map.emberion] or {}).stage] or 0
      checks = checks + 1
      if d1 > d2 then
        fails = fails + 1
        print(("FAIL the first form is paired deeper than the second (%d > %d)")
              :format(d1, d2))
      end

      -- determinism: same dex, same answer
      local again = Creatures.pair(dex)
      local same = true
      for k, v in pairs(map) do if again[k] ~= v then same = false end end
      eq(same, true, "the pairing is the same every time it is built")
    end
  end
end

print(("battleparry_offline: %d checks, %d fail"):format(checks, fails))
print(fails == 0 and "PASS" or "FAIL")
return fails
