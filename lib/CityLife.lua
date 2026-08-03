-- Town life: Pokemon in the streets.
--
-- A town in Gen 1 is the emptiest place in the game: no encounter table, no
-- grass, a handful of scripted NPCs walking their two-cell beats. This
-- module puts trainers' Pokemon out in it -- strays and companions loose in
-- the streets, wearing their own art (the same baked overworld sheets the
-- WILD row uses), wandering the same walk every NPC walks.
--
-- Two kinds of them, told apart by how they act when you come close:
--
--   PACIFISTS  are just out for a stroll. Most of the population. Press A
--              at one and it turns, cries its own cry, and a line of
--              flavour text says what it is doing out here. Nothing else:
--              you cannot fight what does not want to fight.
--
--   CHALLENGERS want a match. About one in three. The TELL is that they
--              STARE: walk within a few cells and a challenger stops dead
--              and turns to face you, and keeps facing you, the way a
--              trainer's sprite turns when you cross its line of sight.
--              Press A and it asks for the fight -- accept and it is a
--              real battle at your own lead's level, refuse and it goes
--              back to its stroll.
--
-- The fight is the engine's own wild battle (BattleState.newWild) pushed
-- down the engine's own pushBattle, so the transition, the experience and
-- the staged 3D arena all work unasked. It is winnable XP on maps that
-- never had any -- a town challenger scales to your lead, so it stays
-- worth a stop without outclassing the route next door. (They are wild
-- battles, so a thrown ball works. Whether catching a town's stray is
-- sporting is left to the player's conscience.)
--
-- WHERE this runs: outdoor maps whose encounter records roll no grass --
-- which is exactly the towns and cities, without a list of them. A route
-- keeps its wild grass and gets nothing here; Viridian Forest is a
-- dungeon; indoors is indoors.
--
-- Nothing here is written anywhere. A pet is a map object for exactly as
-- long as it is on screen plus a margin; it joins ow.npcs and ow.entities
-- like any cast member (so battles cull it, dialogue freezes it, the sun
-- throws its shadow) and is dropped when the player walks on or the map
-- changes.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local RoamerArt = V.require("RoamerArt")
local Roamer = V.require("Roamer")

local Collision = require("src.world.Collision")
local Map = require("src.world.Map")
local Strings = require("src.core.Strings")

local CityLife = {}

local function game()
  return require("src.core.Game")
end

CityLife.setting = ModSetting.new("town", "TOWN",
                                  { "on", "off" }, { "ON", "OFF" })

function CityLife.enabled()
  return CityLife.setting:get() == "on"
end

-- ------- and the one thing outside this file may say about the population
--
-- Set by Shelter while the town is indoors out of the rain. It stops the
-- spawner and nothing else: pets already on the street are Shelter's to walk
-- to a door and drop, and this only makes sure the street is not being
-- refilled one pet at a time behind them.
--
-- A plain field rather than a require, because Shelter loads this file and a
-- require back would be a cycle -- the same arrangement `Weather.poolAt` and
-- `Water.wet` already use.
CityLife.holdSpawns = false

-- ------- who is out today
--
-- Companion species only -- things that read as pets, strays and partners
-- in a Gen 1 town, not as an escaped dungeon. Filtered against the loaded
-- dataset at spawn time, so a total conversion without a MEOWTH simply
-- rolls fewer names.
local PACIFIST_POOL = {
  "PIKACHU", "CLEFAIRY", "JIGGLYPUFF", "MEOWTH", "PSYDUCK", "ODDISH",
  "POLIWAG", "VULPIX", "GROWLITHE", "EEVEE", "SANDSHREW", "RATTATA",
  "PIDGEY", "SLOWPOKE",
}
local CHALLENGER_POOL = {
  "PIKACHU", "GROWLITHE", "MACHOP", "MANKEY", "PONYTA", "DODUO",
  "EEVEE", "CHARMANDER", "SQUIRTLE", "BULBASAUR", "NIDORAN_M", "NIDORAN_F",
}

local STROLL_LINES = {
  "%s is out for\na stroll.",
  "%s looks happy\nto see you!",
  "%s is dozing\nin the sun.",
  "%s is sniffing\naround the street.",
  "%s seems to be\nwaiting for someone.",
}

-- one in three wants a fight
local CHALLENGER_ODDS = 3

-- how many are out at once, and the spawn geometry (the WILD row's own
-- numbers, restated: nothing may pop into the visible frame except on the
-- arrival pass)
local WANT = 4
local EDGE_PAD = 1
local BAND = 5
local KEEP = 6
local TRIES = 40
local SEED_TRIES = 24
local EVERY = 14
local STARE_REACH = 3         -- cells at which a challenger locks on

local state = { mapId = nil, tick = 0 }

local function halfView()
  local Game = game()
  local vw, vh = 160, 144
  local r = Game and Game.renderer
  if r and r.worldViewSize then
    local ok, w, h = pcall(r.worldViewSize, r)
    if ok and (w or 0) > 0 and (h or 0) > 0 then vw, vh = w, h end
  end
  return math.ceil(vw / 32) + EDGE_PAD, math.ceil(vh / 32) + EDGE_PAD
end

local function live(ow)
  local out = {}
  for _, e in ipairs(ow.entities or {}) do
    if e.townPet then out[#out + 1] = e end
  end
  return out
end

local function drop(ow, pet)
  for i = #(ow.npcs or {}), 1, -1 do
    if ow.npcs[i] == pet then table.remove(ow.npcs, i) end
  end
  for i = #(ow.entities or {}), 1, -1 do
    if ow.entities[i] == pet then table.remove(ow.entities, i) end
  end
end

local function sweep(ow)
  for _, pet in ipairs(live(ow)) do drop(ow, pet) end
end

-- A town: outdoors, and the encounter records roll no grass here. That one
-- test IS the town list -- routes have grass rates, dungeons are indoors.
local function isTown(ow)
  local Game = game()
  local map = ow.map
  if not Map.isOutdoor(map.def) then return false end
  local encDef = Game.data.encounters and Game.data.encounters[map.id]
  if encDef and encDef.grass and (encDef.grass.rate or 0) > 0 then
    return false
  end
  return true
end

local function poolPick(pool)
  local Game = game()
  for _ = 1, 6 do
    local species = pool[love.math.random(#pool)]
    if Game.data.pokemon[species] then return species end
  end
  return nil
end

-- A challenger fights at the player's own level, give or take: worth the
-- stop, never a wall.
local function challengerLevel()
  local Game = game()
  local lead = Game.save and Game.save.party and Game.save.party[1]
  local base = lead and lead.level or 5
  return math.max(3, math.min(100, base - 1 + love.math.random(-2, 2)))
end

local function place(ow, cx, cy)
  local challenger = love.math.random(CHALLENGER_ODDS) == 1
  local species = poolPick(challenger and CHALLENGER_POOL or PACIFIST_POOL)
  if not species then return nil end
  local def = RoamerArt.def(species, true)
  if not def then return nil end
  local level = challenger and challengerLevel() or 5
  local pet = Roamer.new(def, species, level, "indoor", cx, cy)
  -- NOT a roamer: WildRoamers must not prune it, walking into it must not
  -- start a fight (it blocks like an NPC), and its A-press is ours below
  pet.roamer = nil
  pet.townPet = true
  pet.challenger = challenger or nil
  ow.npcs[#ow.npcs + 1] = pet
  ow.entities[#ow.entities + 1] = pet
  return pet
end

local function trySpawn(ow, onScreen)
  local map, p = ow.map, ow.player
  local hw, hh = halfView()
  local reach = math.max(hw, hh) + BAND
  for _ = 1, TRIES do
    local dx = love.math.random(-reach, reach)
    local dy = love.math.random(-reach, reach)
    local off = math.abs(dx) > hw or math.abs(dy) > hh
    if (off or onScreen) and not (dx == 0 and dy == 0) then
      local cx, cy = p.cellX + dx, p.cellY + dy
      if Roamer.standable("indoor", map, cx, cy)
         and not Collision.occupied(ow.entities, cx, cy) then
        return place(ow, cx, cy)
      end
    end
  end
  return nil
end

local function prune(ow)
  local p = ow.player
  local hw, hh = halfView()
  local gone = math.max(hw, hh) + BAND + KEEP
  local kept = 0
  for _, pet in ipairs(live(ow)) do
    local ok = not pet.dead
               and math.abs(pet.cellX - p.cellX) <= gone
               and math.abs(pet.cellY - p.cellY) <= gone
    if ok or pet.moving then kept = kept + 1 else drop(ow, pet) end
  end
  return kept
end

-- The challenger's tell. Within reach it stops dead and faces the player,
-- and keeps facing -- the trainer-sight stare, worn by the Pokemon
-- instead. Out of reach it shakes it off and strolls on.
local function stare(ow)
  local p = ow.player
  for _, pet in ipairs(live(ow)) do
    if pet.challenger and not pet.dead then
      local reach = math.abs(pet.cellX - p.cellX)
                    + math.abs(pet.cellY - p.cellY)
      if reach <= STARE_REACH and not pet.moving then
        pet.frozen = true
        pet:facePlayer(p)
      elseif pet.frozen and reach > STARE_REACH + 1 then
        pet.frozen = false
      end
    end
  end
end

local function pass(ow, seeding)
  local kept = prune(ow)
  -- Pruning still runs while the town is sheltering -- a pet the player has
  -- walked away from should still be dropped -- but nothing new is placed:
  -- see CityLife.holdSpawns.
  if CityLife.holdSpawns then return end
  if kept >= WANT then return end
  local attempts = seeding and SEED_TRIES or 1
  for _ = 1, attempts do
    if kept >= WANT then return end
    if trySpawn(ow, seeding) then kept = kept + 1 end
  end
end

-- ------- per-frame, from the voxel pipeline's update hook
--
-- Same gates and the same survival rule as WildRoamers: never under a
-- battle, a menu or a transition, and a throw retires the feature rather
-- than the diorama.
local failed = false

local function tick()
  local Game = game()
  local ow = Game and Game.overworld
  if not (ow and ow.map and ow.player and ow.npcs and ow.entities) then return end
  if Game.stack and Game.stack:top() ~= ow then return end
  if ow.transitioning then return end
  if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then return end

  if not (CityLife.enabled() and RoamerArt.available() and isTown(ow)) then
    if state.mapId ~= nil then
      sweep(ow)
      state.mapId = nil
    end
    return
  end

  if state.mapId ~= ow.map.id then
    sweep(ow)
    state.mapId, state.tick = ow.map.id, 0
    pass(ow, true)
    return
  end

  stare(ow)
  state.tick = state.tick + 1
  if state.tick % EVERY ~= 0 then return end
  pass(ow)
end

function CityLife.update()
  if failed then return end
  local ok, err = pcall(tick)
  if ok then return end
  failed = true
  V.mod.log:warn("town life failed: %s -- the street Pokemon are off for "
                 .. "this session", tostring(err))
  local Game = game()
  local ow = Game and Game.overworld
  if ow and ow.entities then pcall(sweep, ow) end
  state.mapId = nil
end

-- ------- the cast, for Shelter
--
-- Two thin wrappers over the two locals that already do this, published for
-- the one caller that has business with the population it did not create:
-- the rain, which walks the strays to a door and drops them (lib/Shelter.lua).
--
-- Dropping is safe here in a way it is not for the map's own NPCs, and the
-- difference is the whole reason these exist rather than Shelter reaching in:
-- a town pet has no object index, is in no map record and no script has ever
-- heard of it, so it can leave the list and come back as a new one with
-- nothing downstream noticing.
function CityLife.cast(ow)
  return live(ow)
end

function CityLife.remove(ow, pet)
  drop(ow, pet)
end

-- ------- pressing A at one
--
-- A pacifist turns, cries, and says what it is doing out here. A
-- challenger asks for the match; YES is the engine's own wild battle at
-- the challenger's level, NO puts it back on its stroll.
local function speciesName(Game, species)
  local def = Game.data.pokemon[species]
  return (def and def.name) or species
end

local function engage(ow, pet)
  local Game = game()
  if ow.transitioning or ow.engaging then return end
  local BattleState = require("src.battle.BattleState")
  local battle = BattleState.newWild(Game, pet.species, pet.level)
  if battle.dead then return end
  pet.dead = true
  drop(ow, pet)
  battle.onFinish = function(result) ow:afterBattle(result, battle) end
  ow:pushBattle(battle)
end

local function talk(ow, pet)
  local Game = game()
  local TextBox = require("src.render.TextBox")
  pet:facePlayer(ow.player)
  pcall(function()
    require("src.core.Sound").playCry(Game.data, pet.species)
  end)
  local name = speciesName(Game, pet.species)
  if pet.challenger then
    Game.stack:push(TextBox.new(Game,
      Strings("%s is staring\nright at you!\fIt wants to battle!\vAccept?",
              name),
      nil, {
        choice = function(yes)
          if yes then engage(ow, pet) else pet.frozen = false end
        end,
      }))
  else
    local line = STROLL_LINES[love.math.random(#STROLL_LINES)]
    Game.stack:push(TextBox.new(Game, Strings(line, name)))
  end
end

-- ------- the engine seam: the A button
--
-- The same wrap WildRoamers holds, chained behind it (each checks its own
-- mark and passes everything else along), and idempotent for the same hot
-- reload reason.
function CityLife.install()
  local OverworldState = require("src.world.OverworldController")
  if OverworldState.dramaticShapeTownHook then return end
  local inner = OverworldState.talkTo
  function OverworldState:talkTo(npc)
    if npc and npc.townPet and not npc.dead then
      pcall(talk, self, npc)
      return
    end
    return inner(self, npc)
  end
  OverworldState.dramaticShapeTownHook = true
end

return CityLife
