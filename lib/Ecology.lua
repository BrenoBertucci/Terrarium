-- Who is out RIGHT NOW: the hour and the weather, on the encounter table.
--
-- Gen 1 has one encounter table per map and it is the same table at every
-- hour of every day in every kind of weather. Gen 2 answered that with three
-- tables per map -- morning, day, night -- and it is the single change that
-- did the most to make Johto feel like a place rather than a set of rooms
-- with monsters in them: a Hoothoot is a thing you meet because it is dark,
-- and the route at four in the afternoon is not the route at nine at night.
--
-- This is that, built out of what Gen 1 already ships.
--
-- ------- what it does NOT do, first, because it is the load-bearing part
--
-- It does not add a species to a map. It does not remove one either. Every
-- Pokemon this can produce on a route is a Pokemon that route's own table
-- already names, at the level that table already gives it -- with exactly
-- one exception, which is the rain, and which is spelled out in its own
-- section below.
--
-- What moves is the ODDS. The ten-slot table is drawn from with its own
-- cumulative buckets, exactly as `src/world/Encounter.roll` does, and each
-- slot's share of the 256 is then multiplied by what the hour and the sky
-- think of that species. So a Zubat is still on Route 4's table at noon --
-- it is simply the least likely thing on it, instead of being as likely as
-- it was at midnight.
--
-- That is deliberately weaker than Gen 2, which made its night species
-- night-ONLY. Deleting half a route's table for half the clock would break
-- the promise the WILD row is built on ("the species, the levels and the
-- slot odds are the ROM's"), and it would make a dex a player is halfway
-- through into a waiting game. Tilting the odds says the same thing about
-- the world and takes nothing away from anybody.
--
-- ------- where the hour reaches, and where it does not
--
-- OUTDOORS ONLY, and that is the same rule the rest of this mod already
-- holds: a cave at midnight is exactly as dark as a cave at noon, which is
-- what a room with no windows looks like (see DayNight's header). A Zubat
-- lives in the dark whatever the sky is doing, so the indoor tables -- the
-- caves, the towers, the Mansion, the Power Plant -- are left alone
-- entirely. The weather is left out of them for the plainer version of the
-- same reason: there is no sky in there to rain out of.
--
-- ------- the rain, which is the one thing that adds
--
-- Two levers, and only the second one is new.
--
-- The first is the same reweighting the hour uses: while it rains the
-- WATER types on the table come up, the FIRE types go down, and the grass
-- perks up. On most Kanto routes that does very little, because most Kanto
-- grass tables have no water type on them at all -- which is why there is
-- a second lever.
--
-- The second is that water Pokemon COME ASHORE. While it is raining hard,
-- a spawn on land within a few cells of actual water may be drawn from the
-- map's own water roster instead: `encounters[map].water` where the map has
-- one, and otherwise `field.superRod[map]`, which is the ROM's own answer
-- to "what lives in this map's water" for thirty-three maps that have no
-- surf table. So a Poliwag comes up out of the pond it was already in, onto
-- the bank it was already next to, because it is raining -- and a map with
-- no water and no roster is a map where nothing about this happens.
--
-- Its LEVEL is clamped into the range the map's own grass table uses. That
-- is the one number here that is neither the ROM's nor derivable: the fish
-- rosters are levelled for a Super Rod you get late, and a level 23 Kingler
-- on Route 6 would not be atmosphere, it would be a difficulty spike wearing
-- a raincoat. The species is the ROM's; where it is standing is the rain's;
-- how hard it hits is the route's.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local DayNight = V.require("DayNight")
local Weather = V.require("Weather")

local FieldDefaults = require("src.world.FieldDefaults")
local Map = require("src.world.Map")

local Ecology = {}

local function game()
  return require("src.core.Game")
end

local rand = love.math.random

-- ON is first, so it is the default and what an unreadable stored value
-- falls back to. TIME is the hour without the weather, for a player who
-- wants Gen 2's clock and Kanto's own indifferent sky.
Ecology.setting = ModSetting.new("ecology", "ECOLOGY",
                                 { "on", "time", "off" },
                                 { "ON", "TIME", "OFF" })

function Ecology.enabled()
  return Ecology.setting:get() ~= "off"
end

function Ecology.weatherOn()
  return Ecology.setting:get() == "on"
end

function Ecology.row()
  return Ecology.setting:row()
end

-- ------- who keeps what hours
--
-- Two curated sets and a type-derived fallback, in that order.
--
-- The sets are Gen 2's own answer wherever Gen 2 had one: every species
-- below is a Gen 1 species that Johto and Kanto put on a night table or a
-- day table, so this is not an invention about Pokemon, it is the series'
-- own later reading of its own creatures carried back one generation. The
-- famous ones are the point -- Zubat, Gastly and Oddish are night, the
-- birds and the caterpillars are morning and day -- and the rest follow the
-- same list.
--
-- Everything not named here is NEUTRAL and stays exactly as likely as its
-- bucket says at every hour, which is most of the dex and is the right
-- default: a Ditto has no opinion about the sun.
Ecology.NIGHT = {
  ZUBAT = true, GOLBAT = true,
  GASTLY = true, HAUNTER = true, GENGAR = true,
  ODDISH = true, GLOOM = true, VILEPLUME = true,
  VENONAT = true, VENOMOTH = true,
  CLEFAIRY = true, CLEFABLE = true,
  MEOWTH = true, PERSIAN = true,
  DROWZEE = true, HYPNO = true,
  RATTATA = true, RATICATE = true,
  GRIMER = true, MUK = true,
  KOFFING = true, WEEZING = true,
  CUBONE = true, MAROWAK = true,
  KRABBY = true, KINGLER = true,
  PINSIR = true,
  NIDORAN_F = true, NIDORINA = true, NIDOQUEEN = true,
}

Ecology.DAY = {
  PIDGEY = true, PIDGEOTTO = true, PIDGEOT = true,
  SPEAROW = true, FEAROW = true,
  CATERPIE = true, METAPOD = true, BUTTERFREE = true,
  WEEDLE = true, KAKUNA = true, BEEDRILL = true,
  NIDORAN_M = true, NIDORINO = true, NIDOKING = true,
  MANKEY = true, PRIMEAPE = true,
  GROWLITHE = true, ARCANINE = true,
  VULPIX = true, NINETALES = true,
  PONYTA = true, RAPIDASH = true,
  DODUO = true, DODRIO = true,
  SANDSHREW = true, SANDSLASH = true,
  BELLSPROUT = true, WEEPINBELL = true, VICTREEBEL = true,
  EXEGGCUTE = true, EXEGGUTOR = true,
  SCYTHER = true, TAUROS = true, CHANSEY = true,
  KANGASKHAN = true, RHYHORN = true, RHYDON = true,
  FARFETCHD = true, LICKITUNG = true,
  ABRA = true, KADABRA = true,
  PIKACHU = true, RAICHU = true,
}

-- The fallback, for a species in neither set -- which on the shipped ROM is
-- about half the dex, and in a total conversion is all of it. Types are the
-- only thing about a Pokemon this can read that says anything about when it
-- is awake, and two of them say it loudly enough to use: a GHOST or a
-- POISON leans nocturnal, a FLYING or a FIRE leans diurnal. It is half the
-- weight of a curated answer, because it is half a guess.
local TYPE_LEAN = {
  GHOST = -1, POISON = -0.6,
  FLYING = 0.8, FIRE = 0.8, FIGHTING = 0.5,
}

-- -1 (nocturnal) .. +1 (diurnal), 0 for anything with no opinion.
function Ecology.lean(species)
  if Ecology.NIGHT[species] then return -1 end
  if Ecology.DAY[species] then return 1 end
  local Game = game()
  local def = Game and Game.data and Game.data.pokemon
               and Game.data.pokemon[species]
  local types = def and def.types
  if not types then return 0 end
  local sum, n = 0, 0
  for _, t in ipairs(types) do
    local lean = TYPE_LEAN[t]
    if lean then sum, n = sum + lean, n + 1 end
  end
  if n == 0 then return 0 end
  return (sum / n) * 0.5
end

-- Where the clock is pulling, on the same -1..+1 scale. DayNight.tod is the
-- engine's own vocabulary for the hour (it is what map.palette and
-- music.select are handed), so the two agree on what "night" is by reading
-- the same function rather than by both deciding.
--
-- EVENING pulls less hard than NIGHT and MORNING less hard than DAY, which
-- is what a twilight IS: the shift change. The night things are out early
-- and the day things have not all gone in.
local PERIOD_PULL = { DAY = 1, MORNING = 0.55, EVENING = -0.5, NIGHT = -1 }

-- How far the hour is allowed to move a slot's odds. At 0.85 a curated
-- night species at midnight is 1.85x its bucket and at noon is 0.15x it --
-- roughly a twelvefold swing across the day, and never zero.
Ecology.HOUR_STRENGTH = 0.85

function Ecology.period()
  local ok, tod = pcall(DayNight.tod)
  return (ok and tod) or "DAY"
end

-- ------- and what the sky is doing to it
--
-- Multiplicative, and on top of the hour rather than instead of it: a rainy
-- night is both. Scaled by the shower's own `power`, so it arrives at the
-- rate everything else the weather touches arrives at -- the same ramp the
-- sky, the light and the water are already riding.
local RAIN_PULL = {
  WATER = 1.9, GRASS = 0.5, ELECTRIC = 0.3,
  FIRE = -0.8, ROCK = -0.3, GROUND = -0.3,
}

-- While Weather.storming() (heavy rain that can strike), electric types
-- get a real boost rather than the mild rain lean above. Same 1-way read
-- as everything else that asks the weather -- no require cycle.
local STORM_ELECTRIC = 1.85

local SNOW_PULL = {
  ICE = 2.2, WATER = 0.4,
  FIRE = -0.7, BUG = -0.7, GRASS = -0.4,
}

local function weatherWeight(species, kind, power)
  if not kind or power <= 0 then return 1 end
  local pulls = kind == "snow" and SNOW_PULL or RAIN_PULL
  local Game = game()
  local def = Game and Game.data and Game.data.pokemon
               and Game.data.pokemon[species]
  local types = def and def.types
  if not types then return 1 end
  local storm = false
  if kind == "rain" then
    local ok, s = pcall(Weather.storming)
    storm = ok and s and true or false
  end
  local best = 0
  for _, t in ipairs(types) do
    local pull = pulls[t]
    if storm and t == "ELECTRIC" then
      pull = STORM_ELECTRIC
    end
    -- the STRONGEST opinion wins rather than the average: a Poliwag is a
    -- water Pokemon in the rain, and averaging a second type in would say
    -- it is only half of one
    if pull and math.abs(pull) > math.abs(best) then best = pull end
  end
  if best == 0 then return 1 end
  local w = 1 + best * power
  return w > 0.08 and w or 0.08
end

-- ------- the two questions the rest of the mod asks
--
-- Whether this terrain takes the hour at all. Indoors it does not, for the
-- reason in the header; and the row can switch the whole thing off.
local function open(terrain)
  if not Ecology.enabled() then return false end
  return terrain ~= "indoor"
end

-- What the weather is doing where the player is standing, or nil. Asked
-- through Weather.visible rather than Weather.falling deliberately: `falling`
-- answers "what is the weather doing in Kanto", which is still "raining"
-- inside a cave, and a Tentacool has no business coming ashore in there.
-- `visible` is the one gated on the same open-sky test the sky itself rests
-- on, which is exactly the question this wants.
local function sky()
  if not Ecology.weatherOn() then return nil, 0 end
  local ok, kind, power = pcall(Weather.visible)
  if not ok then return nil, 0 end
  return kind, power or 0
end

-- The whole multiplier for one species, hour and sky together. Exposed
-- because the probe reads it, and because it is the number the feature IS.
function Ecology.weight(species, terrain)
  if not open(terrain) then return 1 end
  local pull = PERIOD_PULL[Ecology.period()] or 0
  local w = 1 + Ecology.lean(species) * pull * Ecology.HOUR_STRENGTH
  if w < 0.08 then w = 0.08 end
  local kind, power = sky()
  return w * weatherWeight(species, kind, power)
end

-- ------- drawing from the table
--
-- The bucket widths ARE the vanilla odds -- slot i's share of the 256 is
-- buckets[i] minus buckets[i-1] -- so weighting those and drawing from the
-- total is the same roll with a thumb on it, rather than a different roll
-- that happens to use the same list.
local function bucketsFor(tbl)
  return tbl.buckets
         or FieldDefaults.constant(game().data, "encounterBuckets")
end

-- The vanilla draw, kept exactly as WildRoamers and Encounter.roll do it --
-- including returning nil for a bucket with no slot behind it, which is the
-- original's own "the roll was answered and the answer was nothing".
local function plainPick(tbl)
  local buckets = bucketsFor(tbl)
  local pick = rand(0, 255)
  for i, threshold in ipairs(buckets) do
    if pick < threshold then return tbl.slots and tbl.slots[i] end
  end
  return nil
end

-- One slot from `tbl`, with the hour and the sky on the scale. `terrain` is
-- the engine's own word for which of the three tables this is ("grass",
-- "water", "indoor"), because that is what decides whether any of this
-- applies at all.
function Ecology.pick(tbl, terrain)
  if not (tbl and tbl.slots and #tbl.slots > 0) then return nil end
  if not open(terrain) then return plainPick(tbl) end

  local buckets = bucketsFor(tbl)
  local total, weights, prev = 0, {}, 0
  for i, slot in ipairs(tbl.slots) do
    local edge = buckets[i]
    if not edge then break end
    local width = edge - prev
    prev = edge
    local w = width > 0 and width * Ecology.weight(slot.species, terrain) or 0
    weights[i] = w
    total = total + w
  end
  if total <= 0 then return plainPick(tbl) end

  local pick = rand() * total
  for i, w in ipairs(weights) do
    pick = pick - w
    if pick <= 0 then return tbl.slots[i] end
  end
  return tbl.slots[#tbl.slots]
end

-- ------- the rain's own arrival
--
-- Which water roster this map has, in the order of how much it is the
-- map's: its own surf table first, the Super Rod's list second. Both are
-- the ROM's answer to "what lives in this map's water"; only eight maps
-- carry the first and thirty-three carry the second, which is the whole
-- reason the second is consulted at all.
function Ecology.waterRoster(mapId)
  local Game = game()
  local data = Game and Game.data
  if not data then return nil end
  local encDef = data.encounters and data.encounters[mapId]
  local water = encDef and encDef.water
  if water and water.slots and #water.slots > 0 then return water.slots end
  local rod = data.field and data.field.superRod and data.field.superRod[mapId]
  if rod and #rod > 0 then return rod end
  return nil
end

-- The level band the map's OWN land table works in, so an arrival is as
-- hard as the route it arrives on. nil when there is nothing to measure
-- against, which is the case that declines the whole thing.
local function landBand(mapId)
  local Game = game()
  local encDef = Game and Game.data and Game.data.encounters
                 and Game.data.encounters[mapId]
  local slots = encDef and encDef.grass and encDef.grass.slots
  if not (slots and #slots > 0) then return nil end
  local lo, hi = math.huge, 0
  for _, s in ipairs(slots) do
    if s.level then
      if s.level < lo then lo = s.level end
      if s.level > hi then hi = s.level end
    end
  end
  if hi == 0 then return nil end
  return lo, hi
end

Ecology.ASHORE_REACH = 3        -- cells from open water an arrival may stand
Ecology.ASHORE_FROM = 0.35      -- rain power below which nothing comes up
Ecology.ASHORE_MAX = 0.45       -- share of land spawns at the heaviest rain

-- Is there water within reach of this cell? Counted by LOOKING, in cells,
-- rather than kept as a list of maps with ponds on them -- the same way the
-- ambient sound decides where a river is audible, and for the same reason:
-- a route with one pond in the corner should only do this in that corner.
local function nearWater(map, cx, cy)
  local r = Ecology.ASHORE_REACH
  for dy = -r, r do
    for dx = -r, r do
      if map:inBounds(cx + dx, cy + dy)
         and map:isWaterCell(cx + dx, cy + dy) then
        return true
      end
    end
  end
  return false
end

-- A water Pokemon coming up onto the bank, or nil -- which is the answer
-- almost all of the time and every time on a map with no water in it.
function Ecology.ashore(map, cx, cy, terrain)
  if terrain ~= "grass" then return nil end
  if not (map and map.id and map.def) then return nil end
  if not open(terrain) then return nil end
  local kind, power = sky()
  if kind ~= "rain" or power < Ecology.ASHORE_FROM then return nil end
  if not Map.isOutdoor(map.def) then return nil end

  local share = Ecology.ASHORE_MAX * (power - Ecology.ASHORE_FROM)
                / (1 - Ecology.ASHORE_FROM)
  if rand() > share then return nil end

  if not nearWater(map, cx, cy) then return nil end
  local roster = Ecology.waterRoster(map.id)
  if not roster then return nil end
  local lo, hi = landBand(map.id)
  if not lo then return nil end

  local slot = roster[rand(#roster)]
  if not (slot and slot.species) then return nil end
  local level = slot.level or lo
  if level < lo then level = lo elseif level > hi then level = hi end
  return { species = slot.species, level = level, ashore = true }
end

-- ------- what the WILD row asks
--
-- One call: the arrival first, because it is the rarer and more specific
-- answer, and the weighted table pick when there is no arrival. `terrain`
-- and the cell come from the spawner, which knows both.
function Ecology.slotFor(tbl, terrain, map, cx, cy)
  local up = Ecology.ashore(map, cx, cy, terrain)
  if up then return up end
  return Ecology.pick(tbl, terrain)
end

-- ------- and what the BLIND ROLL asks
--
-- The engine's encounter.species hook hands over a roll that already
-- happened and takes back whatever it should have been. That is the seam
-- for MIX and for OFF -- the two rungs where the dice are still being
-- thrown -- so the hour and the sky reach a player who never switched the
-- visible Pokemon on at all.
--
-- The table is looked up again from ctx rather than carried in, because the
-- hook is handed the ROLL and not the record it came out of. Failing that
-- lookup returns the encounter untouched, which is the right failure: the
-- game rolled something, and something is what it gets.
function Ecology.substitute(enc, ctx)
  if not (enc and ctx and ctx.mapId) then return enc end
  local terrain = ctx.terrain
  if not open(terrain) then return enc end
  local Game = game()
  local ow = Game and Game.overworld
  local map = ow and ow.map
  if map and map.id == ctx.mapId and ow.player then
    local up = Ecology.ashore(map, ow.player.cellX, ow.player.cellY, terrain)
    if up then return { species = up.species, level = up.level } end
  end
  local encDef = Game.data and Game.data.encounters
                 and Game.data.encounters[ctx.mapId]
  if not encDef then return enc end
  local tbl = terrain == "water" and encDef.water or encDef.grass
  local slot = Ecology.pick(tbl, terrain)
  if not slot then return enc end
  return { species = slot.species, level = slot.level }
end

return Ecology
