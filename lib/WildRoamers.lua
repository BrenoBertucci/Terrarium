-- Wild Pokemon you can see.
--
-- Gen 1's wild encounter is a dice roll on a step: walk into tall grass and
-- every completed step draws rand(0..255) against the map's encounter rate,
-- and when it comes up the screen wipes and something you never saw is
-- suddenly in front of you.  Nothing about that is a decision.  You cannot
-- pick a fight, avoid one, choose which one, or know there was one to
-- choose -- the grass is a slot machine you pull by walking.
--
-- This makes the roll VISIBLE.  The same encounter table, rolled the same
-- way with the same probability buckets, decides which Pokemon are standing
-- in the grass -- and on the water -- RIGHT NOW as ordinary map objects,
-- wearing their own art, wandering their own patch -- and the fight starts
-- when you walk into one.  So a meadow and a pond are both places with
-- things in them: you can see what is there, go round the Zubat, go after
-- the Magikarp (once you Surf), or walk the route without fighting.
--
-- Three settings' worth of that, on the WILD row:
--
--   ROAM  wild Pokemon stand in the grass and on the water; the random
--         roll is off.  What you fight is what you walked into.
--   MIX   they stand there AND the roll still happens, so the terrain can
--         still surprise you.
--   OFF   nothing here runs; the game rolls the dice exactly as it always
--         did.
--
-- WHAT DOES NOT MOVE.  The encounter TABLES are untouched -- the species,
-- the levels and the ten-slot buckets are the ROM's, read through the same
-- data the roll reads -- and so is REPEL, which keeps weaker mons from
-- appearing at all rather than from being rolled.  A battle that starts
-- here is the engine's own wild battle, pushed down the engine's own
-- pushBattle, so the transition, the ghost rule in the Pokemon Tower, the
-- Safari menu, the catch, the experience and this mod's own staged arena
-- all happen without knowing where the fight came from.
--
-- The feature declines cleanly rather than half-working: art that cannot be
-- baked, a map with no encounter table, or a map with no room to stand
-- anything on all end at the same place, which is the random roll the game
-- has always done (see `covers`).

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local RoamerArt = V.require("RoamerArt")
local Roamer = V.require("Roamer")
local Ecology = V.require("Ecology")

local Collision = require("src.world.Collision")
local FieldDefaults = require("src.world.FieldDefaults")
local Map = require("src.world.Map")

local WildRoamers = {}

local function game()
  return require("src.core.Game")
end

WildRoamers.KEY = "wild"
WildRoamers.LABEL = "WILD"

-- ROAM first, so it is the default and also what an unreadable stored value
-- falls back to: a mod that puts Pokemon in the grass should not need the
-- player to go and find the switch before any of them show up.
WildRoamers.setting = ModSetting.new(WildRoamers.KEY, WildRoamers.LABEL,
                                     { "roam", "mix", "off" },
                                     { "ROAM", "MIX", "OFF" })

WildRoamers.COUNT_KEY = "wildCount"
WildRoamers.COUNT_LABEL = "W-COUNT"

-- How many stand within reach at once.  SOME is a route that feels
-- inhabited without being a queue; MANY is closer to the density a modern
-- game's grass has, and costs one more sprite card per head.
WildRoamers.countSetting = ModSetting.new(WildRoamers.COUNT_KEY,
                                          WildRoamers.COUNT_LABEL,
                                          { 6, 3, 10 },
                                          { "SOME", "FEW", "MANY" })

function WildRoamers.enabled()
  return WildRoamers.setting:get() ~= "off"
end

-- ------- where one may appear
--
-- Nothing may appear ON SCREEN.  A Pokemon that materialised in front of
-- the player would give the whole thing away as a spawner; one that walks
-- in from off the edge is simply a Pokemon that was already there.  So a
-- spawn is drawn from a band starting one cell past whichever edge of the
-- view it falls beyond -- measured PER AXIS, because a view is a rectangle
-- and a distance is not: a cell nine away diagonally is comfortably on
-- screen while one nine away due east is not.
--
-- The view is ASKED FOR rather than assumed.  This mod is played at
-- anything from the Game Boy's own ten by nine cells to a fullscreen
-- desktop window showing three times that, and a band tuned for one is
-- either visible or unreachable on the other.
--
-- Arrival is the one exception, and it is not an exception to the rule so
-- much as to what the rule protects: a map is entered from behind a
-- transition, so the first thing drawn is a whole screen at once and there
-- is nothing for a spawn to pop INTO.  That frame is where a route gets a
-- population in the grass you can already see; everything after it walks in
-- from off the edge.
local EDGE_PAD = 1            -- cells past the view's edge a spawn may land
local BAND = 6                -- how much further out the band reaches
local KEEP = 6                -- cells past the band before one is retired
local TRIES = 48              -- cells sampled per spawn attempt
local SEED_TRIES = 30         -- spawn attempts on arriving at a map
local EVERY = 12              -- frames between population passes

-- Half the view, in cells, per axis.  The fallback is the Game Boy's own
-- screen, which is what a headless run and a renderer that has not sized
-- itself yet both come to.
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

-- ------- the live set
--
-- Which map is populated, when the next pass is due, and which terrain has
-- actually had something stood on it.  Deliberately NOT a roster of the
-- roamers themselves; see live() below.
local state = { mapId = nil, tick = 0, covered = {} }

local function drop(ow, roamer)
  for i = #(ow.npcs or {}), 1, -1 do
    if ow.npcs[i] == roamer then table.remove(ow.npcs, i) end
  end
  for i = #(ow.entities or {}), 1, -1 do
    if ow.entities[i] == roamer then table.remove(ow.entities, i) end
  end
end

-- Every roamer currently in the world's own lists.
--
-- Read out of the overworld each time rather than kept as a private roster,
-- because the overworld's list is the one that is TRUE: a map change, a
-- blackout warp and a script rebuilding the cast all rewrite it, and a
-- roster that disagreed with it would leak roamers onto the wrong map or
-- keep references to ones nothing draws.
local function live(ow)
  local out = {}
  for _, e in ipairs(ow.entities or {}) do
    if e.roamer then out[#out + 1] = e end
  end
  return out
end

local function sweep(ow)
  for _, r in ipairs(live(ow)) do drop(ow, r) end
end

-- ------- which terrain this map's wild Pokemon live in
--
-- The same three cases OverworldState:onStepComplete rolls for, read off
-- the same records, so a map that can produce a wild battle by walking can
-- produce one standing here and no map that cannot gets one anyway.
--
-- Water is ALWAYS populated when the map has a water encounter table -- the
-- same rule grass already has.  Earlier this was gated on the player
-- Surfing, on the grounds that a Tentacool on an unreachable pond was set
-- dressing; it is, and it is also the only way the pond makes sense next
-- to a meadow full of visible Rattata.  What you can SEE and what you can
-- REACH stay different questions: on foot they bob on the water as scenery,
-- and the fight only starts when you walk into one (which still needs Surf,
-- because Collision.canMove refuses water to a walker).  Step off the water
-- and the grass ones stay; the water ones stay too -- they live there.
local function terrainsFor(ow)
  local Game = game()
  local map = ow.map
  -- A city can have Super Rod water and NO encounter table at all
  -- (Vermilion, Cerulean).  Do not bail on a missing encDef -- grass and
  -- Surf water need it, the rod fallback does not.
  local encDef = Game.data.encounters and Game.data.encounters[map.id]

  -- The Pokemon Tower keeps its dice.
  --
  -- A ghost battle is a wild battle the game refuses to NAME until the
  -- player holds the Silph Scope -- that is the whole floor's puzzle -- and
  -- a Gastly wandering about in plain sight with its own art answers the
  -- question the map exists to ask.  So while the rule is live this map is
  -- left alone entirely, which puts the blind roll back on it (`covers` is
  -- only ever true for terrain something was actually stood on).  Pick the
  -- Scope up and the ghosts have names, and the floor populates like
  -- anywhere else.
  local ghost = Map.ghostBattles(map.def)
  if ghost and not (ghost.unlessItem
                    and Game.save.inventory[ghost.unlessItem]) then
    return {}
  end

  local out = {}

  local indoor = Game.data.field.indoorEncounters
  local isIndoor = indoor and map.def.index and indoor.firstIndoorMap
                   and map.def.index >= indoor.firstIndoorMap
                   and map.def.tileset ~= indoor.excludedTileset

  if encDef and encDef.grass and (encDef.grass.rate or 0) > 0 then
    if isIndoor then
      -- caves, towers, the Mansion, the Power Plant: the whole floor is the
      -- encounter, so the whole floor is where they stand
      out[#out + 1] = { kind = "indoor", table_ = encDef.grass }
    elseif map.tileset and map.tileset.grassTile then
      out[#out + 1] = { kind = "grass", table_ = encDef.grass }
    end
  end
  if encDef and encDef.water and (encDef.water.rate or 0) > 0 then
    out[#out + 1] = { kind = "water", table_ = encDef.water }
  else
    -- Maps with fishable water but no Surf encounter table (cities, docks)
    -- still know what lives there: the Super Rod list.  Ecology.waterRoster
    -- already prefers the Surf table and falls back to the rod, so a city
    -- pond gets its Krabby / Shellder the same way a route pond gets its
    -- Tentacool.  Built as a tiny equal-bucket table so pickSlot / Ecology
    -- can draw it without a second code path.
    local slots = Ecology.waterRoster(map.id)
    if slots and #slots > 0 then
      local buckets = {}
      for i = 1, #slots do
        buckets[i] = math.floor(i * 256 / #slots)
      end
      out[#out + 1] = {
        kind = "water",
        table_ = { rate = 1, slots = slots, buckets = buckets },
      }
    end
  end
  return out
end

-- One slot out of an encounter table, by the original's own cumulative
-- buckets (src/world/Encounter.roll draws the same way against the same
-- numbers).  The RATE is deliberately not consulted: rate answers "does a
-- fight start on this step", which is the question this feature replaces.
-- Which SPECIES, and how likely each is, is still entirely the table's.
--
-- With the ECOLOGY row off this IS that draw, byte for byte.  With it on the
-- same buckets are weighted by what the hour and the sky think of each
-- species before the draw, and a heavy shower near open water may put
-- something from the map's own water roster on the bank instead -- both in
-- lib/Ecology.lua, both declining to exactly this when there is nothing to
-- say.  The CELL is handed over because the arrival needs it: coming ashore
-- is a thing that happens next to a shore.
local function pickSlot(tbl, kind, map, cx, cy)
  if Ecology.enabled() then
    local slot = Ecology.slotFor(tbl, kind, map, cx, cy)
    if slot then return slot end
    return nil
  end
  local buckets = tbl.buckets
             or FieldDefaults.constant(game().data, "encounterBuckets")
  local pick = love.math.random(0, 255)
  for i, threshold in ipairs(buckets) do
    if pick < threshold then return tbl.slots and tbl.slots[i] end
  end
  return nil
end

-- REPEL, answered where it can be seen.
--
-- The item's rule is unchanged -- nothing weaker than the lead -- but it
-- reads better here than it did on the roll: instead of steps that
-- mysteriously produce nothing, the grass is visibly empty of the small
-- stuff while it lasts.
local function repelled(level)
  local Game = game()
  local steps = Game.save.repelSteps or 0
  if steps <= 0 then return false end
  local lead = Game.save.party[1]
  return lead ~= nil and level < lead.level
end

-- How many sheets this pass is still allowed to bake; see RoamerArt.def.
local bakeBudget = 0
local BAKES_PER_PASS = 2

local function place(ow, kind, slot, cx, cy)
  -- a species already resolved costs nothing to ask for again, so the budget
  -- is only spent on ones this session has not seen
  local known = RoamerArt.known(slot.species)
  if not known then bakeBudget = bakeBudget - 1 end
  local def = RoamerArt.def(slot.species, known or bakeBudget >= 0)
  if not def then return nil end
  local r = Roamer.new(def, slot.species, slot.level, kind, cx, cy)
  ow.npcs[#ow.npcs + 1] = r
  ow.entities[#ow.entities + 1] = r
  state.covered[kind] = true
  return r
end

-- One spawn attempt.  `onScreen` is only ever true on the arrival pass; see
-- the band's own note above for why that one frame is allowed to.
local function trySpawn(ow, terrain, onScreen)
  local map, p = ow.map, ow.player
  local hw, hh = halfView()
  local reach = math.max(hw, hh) + BAND
  for _ = 1, TRIES do
    local dx = love.math.random(-reach, reach)
    local dy = love.math.random(-reach, reach)
    local off = math.abs(dx) > hw or math.abs(dy) > hh
    if (off or onScreen) and not (dx == 0 and dy == 0) then
      local cx, cy = p.cellX + dx, p.cellY + dy
      if Roamer.standable(terrain.kind, map, cx, cy)
         and not Collision.occupied(ow.entities, cx, cy) then
        local slot = pickSlot(terrain.table_, terrain.kind, map, cx, cy)
        if slot and not repelled(slot.level) then
          return place(ow, terrain.kind, slot, cx, cy)
        end
        return nil    -- the roll was answered; the next pass rolls again
      end
    end
  end
  return nil
end

-- Retire the ones that have no business being here any more: the one the
-- player just fought, the ones left behind as the player walked on, and any
-- whose ground stopped being their terrain under them (a Cut tree, a
-- script's replaceBlock, stepping off the water).
--
-- The distance is per-axis for the same reason the spawn band is, and
-- KEEP cells further out than anything can be spawned at, so a head is
-- never dropped and re-rolled on alternate passes while the player stands
-- on the boundary.
local function prune(ow)
  local p = ow.player
  local hw, hh = halfView()
  local gone = math.max(hw, hh) + BAND + KEEP
  local kept = 0
  for _, r in ipairs(live(ow)) do
    local ok = not r.dead
               and math.abs(r.cellX - p.cellX) <= gone
               and math.abs(r.cellY - p.cellY) <= gone
               and Roamer.standable(r.kind, ow.map, r.cellX, r.cellY)
    -- never yank one out from under a step in progress: the cell it is
    -- leaving and the cell it is entering are both reserved, and dropping
    -- it mid-stride would free a cell somebody could already be walking into
    if ok or r.moving then kept = kept + 1 else drop(ow, r) end
  end
  return kept
end

-- Which terrain is shortest of heads right now.  A route with both grass
-- and water used to fill entirely with grass by pure luck of the coin --
-- the count cap is shared -- and the pond sat empty next to a crowded
-- meadow.  Biasing the next spawn at the thinner terrain keeps both
-- inhabited without raising the cap or inventing a second population.
local function pickTerrain(ow, terrains)
  if #terrains == 1 then return terrains[1] end
  local n = {}
  for _, r in ipairs(live(ow)) do
    n[r.kind] = (n[r.kind] or 0) + 1
  end
  local best, bestN = terrains[1], n[terrains[1].kind] or 0
  for i = 2, #terrains do
    local c = n[terrains[i].kind] or 0
    if c < bestN then best, bestN = terrains[i], c end
  end
  -- a coin still decides when they are even, so one kind never locks the
  -- other out once the counts have matched
  if love.math.random() < 0.35 then
    return terrains[love.math.random(#terrains)]
  end
  return best
end

-- One head per pass while walking: a route fills in over a second or two
-- from off the edge rather than several appearing at once.  On ARRIVAL the
-- same work runs until the map is populated, because there is a whole
-- screen of grass about to be revealed and it should have things in it.
local function pass(ow, seeding)
  local kept = prune(ow)
  local want = WildRoamers.countSetting:get() or 6
  if kept >= want then return end
  local terrains = terrainsFor(ow)
  if #terrains == 0 then return end
  bakeBudget = BAKES_PER_PASS
  local attempts = seeding and SEED_TRIES or 1
  for _ = 1, attempts do
    if kept >= want then return end
    if trySpawn(ow, pickTerrain(ow, terrains), seeding) then
      kept = kept + 1
    end
  end
end

-- ------- per-frame
--
-- Driven from the voxel pipeline's update hook, the one tick the engine
-- runs whatever is on top -- and then gated back down to the frames where
-- the overworld IS on top and settled.  Nothing here may run under a
-- battle, a menu or a transition: the mod's own staged battle swaps
-- ow.entities for a culled copy for the length of a fight (see
-- OverworldBattle.cullCast), and a spawn appended to that copy would be
-- thrown away with it.
local function tick()
  local Game = game()
  local ow = Game and Game.overworld
  if not (ow and ow.map and ow.player and ow.npcs and ow.entities) then return end
  if Game.stack and Game.stack:top() ~= ow then return end
  if ow.transitioning then return end

  if not (WildRoamers.enabled() and RoamerArt.available()) then
    if state.mapId ~= nil then
      sweep(ow)
      state.mapId, state.covered = nil, {}
    end
    return
  end

  if state.mapId ~= ow.map.id then
    -- setMap rebuilds both lists, so there is normally nothing to sweep;
    -- what this catches is a roamer carried across by a path that restored
    -- a captured list (a blackout warp landing under a staged battle's own
    -- cast restore), which would otherwise stand on the wrong map forever
    sweep(ow)
    state.mapId, state.covered, state.tick = ow.map.id, {}, 0
    pass(ow, true)
    return
  end

  state.tick = state.tick + 1
  if state.tick % EVERY ~= 0 then return end
  pass(ow)
end

-- This runs inside the voxel pipeline's update hook, and the registry
-- retires a PIPELINE that throws -- for the session, taking the whole
-- diorama with it.  Nothing this file can get wrong is worth that, so a
-- failure retires only this feature: the population is swept, the random
-- roll comes back (`covers` reads the same flag), and the world carries on
-- in 3D.  Warned once, because a per-frame hook fails sixty times a second.
local failed = false

function WildRoamers.update()
  if failed then return end
  local ok, err = pcall(tick)
  if ok then return end
  failed = true
  V.mod.log:warn("wild roamers failed: %s -- the visible Pokemon are off for "
                 .. "this session and the random encounters are back",
                 tostring(err))
  local Game = game()
  local ow = Game and Game.overworld
  if ow and ow.entities then pcall(sweep, ow) end
  state.mapId, state.covered = nil, {}
end

-- ------- what the random roll is allowed to do
--
-- Only ever answered for terrain this feature has actually put something
-- on.  A map with no encounter table, no room, or art that would not bake
-- never reaches `covered`, so the roll it always had is still there -- which
-- is the difference between replacing the encounter and deleting it.
function WildRoamers.covers(terrain)
  if failed or terrain == nil then return false end
  if WildRoamers.setting:get() ~= "roam" then return false end
  if not RoamerArt.available() then return false end
  return state.covered[terrain] and true or false
end

-- ------- the fight
--
-- Everything a wild battle needs, in the order OverworldState:onStepComplete
-- does it, because it IS that battle: the same constructor, the same ghost
-- rule, the same Safari menu and the same afterBattle.  What is not the same
-- is the roll that chose it, which already happened, in the open, when this
-- one was placed.
function WildRoamers.engage(ow, roamer)
  local Game = game()
  if not (ow and roamer) or roamer.dead then return false end
  if Game.stack and Game.stack:top() ~= ow then return false end
  if ow.transitioning or ow.engaging then return false end
  if ow.runner and ow.runner:isRunning() then return false end

  local BattleState = require("src.battle.BattleState")
  local battle = BattleState.newWild(Game, roamer.species, roamer.level)
  -- a battle with nobody able to fight it is not one this may start: the
  -- constructor marks it dead, and pushing it would wipe to an empty screen
  if battle.dead then return false end

  roamer.dead = true
  roamer:facePlayer(ow.player)
  -- taken out of the world BEFORE the push, not after it.  The push culls
  -- the map's cast into a snapshot for the length of the fight, and a
  -- roamer still in the list at that moment is a roamer the restore puts
  -- back afterwards -- standing on the cell you just cleared.
  drop(ow, roamer)

  local ghost = Map.ghostBattles(ow.map.def)
  if ghost and not (ghost.unlessItem
                    and Game.save.inventory[ghost.unlessItem]) then
    battle:makeGhost()
  end
  if Game.save.safari and Map.inRegion(ow.map.def, "SAFARI", "SAFARI_ZONE") then
    battle:makeSafari(Game.save.safari)
  end
  battle.onFinish = function(result) ow:afterBattle(result, battle) end
  ow:pushBattle(battle)
  return true
end

-- The player walked into something.  Which something is not reported by the
-- step -- tryMove answers "blocked, by an entity" and no more -- so the cell
-- in front is asked directly.
function WildRoamers.bumped(player, dir)
  local Game = game()
  local ow = Game and Game.overworld
  if not (ow and ow.map and ow.player == player) then return end
  local cx, cy = Collision.target(player.cellX, player.cellY, dir)
  for _, e in ipairs(ow.entities or {}) do
    if e.roamer and not e.dead
       and ((e.cellX == cx and e.cellY == cy)
            or (e.targetX == cx and e.targetY == cy)) then
      WildRoamers.engage(ow, e)
      return
    end
  end
end

-- ------- engine seams
--
-- Two wraps, each idempotent so a hot reload cannot stack them.

function WildRoamers.install()
  -- WALKING INTO ONE.  The step itself is the seam: tryMove is where the
  -- player's own attempt to enter a cell is refused, and "blocked by an
  -- entity" is the exact moment a modern game starts the encounter.  Read
  -- AFTER the inner call rather than instead of it, so the turn-in-place,
  -- the bump cooldown and every other thing a refused step does still
  -- happen -- this only notices what was standing there.
  local Player = require("src.world.Player")
  if not Player.dramaticShapeRoamHook then
    local inner = Player.tryMove
    function Player:tryMove(dir, map, entities)
      local result, why = inner(self, dir, map, entities)
      if result == "blocked" and why == "entity" then
        pcall(WildRoamers.bumped, self, dir)
      end
      return result, why
    end
    Player.dramaticShapeRoamHook = true
  end

  -- TALKING TO ONE.  A roamer sits in ow.npcs so the engine's own update
  -- walk steps it, which also puts it in front of the A button: interact()
  -- finds it at the facing cell and hands it to talkTo, whose whole body is
  -- about a map object's text, item, trainer and script arguments -- none of
  -- which a Pokemon has.  So it is answered here instead, and pressing A at
  -- one starts the same fight walking into it does.
  local OverworldState = require("src.world.OverworldController")
  if not OverworldState.dramaticShapeRoamHook then
    local inner = OverworldState.talkTo
    function OverworldState:talkTo(npc)
      if npc and npc.roamer then
        WildRoamers.engage(self, npc)
        return
      end
      return inner(self, npc)
    end
    OverworldState.dramaticShapeRoamHook = true
  end
end

return WildRoamers
