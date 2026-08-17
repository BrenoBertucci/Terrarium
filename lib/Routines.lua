-- What the people do when nobody is watching them.
--
-- A Gen 1 NPC has exactly two behaviours in the ROM and this mod inherited
-- both. A STAY object faces one way forever. A WALK object takes a random
-- step every two to six seconds within its range and faces whichever way it
-- last stepped. That is the whole of it -- so a town reads as a set of
-- bookmarks holding places open until the player arrives to press A at them,
-- and the single most common thing anybody says about walking through Kanto
-- is that the people are furniture.
--
-- AmbientLife already put one crack in that: civilians GLANCE when you walk
-- past, and turning a head is the cheapest thing in the world that says
-- somebody is home. This is the other half -- what they are doing when you
-- are NOT walking past, which is most of the time and all of the time from
-- across a street.
--
-- ------- the four beats, and why they are all FACINGS
--
-- Everything here writes `facing`, or plays the engine's own turn-in-place
-- animation, and nothing here moves anybody a cell. That restraint is the
-- design rather than a limit hit on the way to something better:
--
--   a cell is a CLAIM.  Where an NPC stands is in the map record, it is what
--   the collision grid is built out of, and half of Kanto's scripts are a
--   line of dialogue attached to a person standing in a particular doorway.
--   Moving people around invents a pathing problem, a crowding problem and a
--   "why is the guard not at the gate" problem, and buys a town that is
--   busier and less legible.
--
--   a facing is FREE.  It is one string, the engine redraws off it every
--   frame, no collision reads it, no script depends on it, and it is the
--   single strongest signal a 16-pixel sprite has. Somebody who turns to
--   look at a sign is reading it. Two people who turn to face each other are
--   talking. Somebody who keeps looking at the same door is waiting for
--   whoever is behind it.
--
-- So: four beats, on a clock per person, all of them free.
--
--   LOOK    turn somewhere else for a while, and drift back to the facing
--           the map authored. The baseline, and on its own it is most of
--           the difference: a street where nobody's head ever moves is
--           uncanny in a way you notice before you can name it.
--
--   CHAT    two civilians standing within a couple of cells of each other,
--           in line, turn and face each other and hold it -- with a shuffle
--           on the spot now and then, which is the engine's own
--           turn-in-place animation and reads as a nod. This is the beat
--           that carries the whole feature. Two sprites facing each other
--           is a conversation, and the player's brain does the rest for
--           free.
--
--   WORK    face the thing you are standing next to. A sign, a counter, a
--           door: a Gen 1 town puts people beside exactly these and then
--           has them face the road. Turning them toward what they are
--           standing at costs one lookup and explains why they are there.
--
--   POST    go back to the facing the map gave you. Not idleness -- it is
--           what keeps the beats from washing the map's own authorship out:
--           the clerk faces the counter, the guard faces the gate, and the
--           routine is something that happens BETWEEN those rather than
--           instead of them.
--
-- ------- who this leaves alone, and it is a longer list than it looks
--
--   TRAINERS.  A trainer's facing is their line of sight. Turning one starts
--              or dodges a fight the map never rolled, which is the same
--              reason AmbientLife's glance has never touched one.
--   ANYBODY MID-SCRIPT.  `frozen` is the engine saying this person is
--              talking, and it is checked every beat rather than once.
--   ANYBODY MID-STEP.  A WALK object taking its own random step owns its own
--              facing until it lands; two things writing one field is a
--              flicker.
--   ANYBODY GLANCING.  AmbientLife owns the facing while the player is
--              close, and it is the one that should: a routine that talked
--              over the glance would have people looking away from a player
--              standing next to them.
--   ANYBODY SHELTERING.  lib/Shelter.lua is walking them to a door.
--
-- Which is to say: this runs on a civilian who is standing still, with
-- nobody near them and nothing happening. That is precisely the population
-- the complaint is about.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local DayNight = V.require("DayNight")
-- Safe at load time: Shelter requires ModSetting/Weather/CityLife and never
-- this file, and main.lua loads it first (main.lua:136 before :137).
local Shelter = V.require("Shelter")
-- No cycle: CityLife requires ModSetting/RoamerArt/Roamer and neither this
-- file nor Shelter. The chain is Routines -> Shelter -> CityLife.
local CityLife = V.require("CityLife")

local Collision = require("src.world.Collision")
local NPC = require("src.world.NPC")

local Routines = {}

local function game()
  return require("src.core.Game")
end

Routines.setting = ModSetting.new("routine", "ROUTINE",
                                  { "on", "off" }, { "ON", "OFF" })

function Routines.enabled()
  return Routines.setting:get() == "on"
end

function Routines.row()
  return Routines.setting:row()
end

-- ------- the agenda's own row, and why it is not a second value on ROUTINE
--
-- The beats above are free and invisible to everything: they write a facing
-- and nothing else can tell. The agenda moves bodies, and moving bodies is
-- the kind of change a player can dislike -- a town that empties after dark
-- changes how it feels to play at night, and somebody who wants the looking
-- without the leaving should be able to say so.
--
-- Separating it also buys the A/B for free, which is the reason it exists
-- before the wiring does: a feature you cannot switch off is a feature you
-- cannot measure.
--
--   OFF   nothing here runs; the beats above still do.
--   DAY   people go to the post the map authored and keep it. Purpose,
--         without the town ever emptying.
--   FULL  all four phases: at night they take a doorway and the street
--         Pokemon go in.
Routines.agendaSetting = ModSetting.new("agenda", "AGENDA",
                                        { "off", "day", "full" },
                                        { "OFF", "DAY", "FULL" })

function Routines.agendaMode()
  return Routines.agendaSetting:get() or "off"
end

function Routines.agendaRow()
  return Routines.agendaSetting:row()
end

-- ------- the clock
--
-- Seconds between beats, rolled per person per beat. Wide, and deliberately
-- wider than it feels like it should be: a street where everybody moves
-- every two seconds is not alive, it is twitching. What reads as alive is
-- one person doing one thing at a time while the rest hold still, and that
-- comes out of a long interval and a lot of independent clocks rather than
-- out of any one of them being interesting.
Routines.BEAT_MIN, Routines.BEAT_MAX = 3.5, 11.0

-- How long a turn is held before the clock rolls again. A CHAT runs much
-- longer than a glance: a conversation that broke off every three seconds
-- would read as two people repeatedly noticing each other.
Routines.CHAT_MIN, Routines.CHAT_MAX = 7.0, 16.0

-- Seconds between the shuffles inside a chat -- the nod. Through the
-- engine's own NPC_CHANGE_FACING path, which animates the walk cycle in
-- place without translating: exactly a person shifting their weight.
Routines.NOD_MIN, Routines.NOD_MAX = 1.6, 4.2

-- How far apart two people may stand and still be talking, in cells, and
-- they must be IN LINE -- same row or same column. Two sprites facing each
-- other across a diagonal do not read as facing each other at all, because
-- this game has four facings and none of them is diagonal.
Routines.CHAT_REACH = 2

-- The share of beats that go to each thing. Rolled in order, so these are
-- thresholds on one number rather than a distribution to normalise: chat
-- first because it is the beat worth having, and POST last as the fallback
-- so a person with nobody to talk to and nothing to look at goes back to
-- standing the way the map drew them.
Routines.CHAT_ODDS = 0.30
Routines.WORK_ODDS = 0.55       -- of what is left after chat
Routines.LOOK_ODDS = 0.75       -- and of what is left after that

local DIRS = { "up", "down", "left", "right" }

local rand = love.math.random

local function roll(lo, hi)
  return lo + love.math.random() * (hi - lo)
end

-- ------- is this person available
local function idle(npc)
  if getmetatable(npc) ~= NPC then return false end
  if not npc.def or npc.def.trainerClass then return false end
  if npc.frozen or npc.moving then return false end
  if npc.dsShelter then return false end        -- Shelter is walking them
  if npc.dsGlanceFacing ~= nil then return false end  -- AmbientLife has them
  return true
end

-- The facing the map authored, captured the first time this module touches
-- somebody. Read off `def.range`, the same field NPC.new builds the initial
-- facing from -- so this is the authored answer rather than wherever the
-- person happens to be pointing when the module first gets to them, which
-- after a few of the engine's own random steps is not the same thing.
local POST_FACING = { DOWN = "down", UP = "up", LEFT = "left", RIGHT = "right" }

local function post(npc)
  if npc.dsPost == nil then
    npc.dsPost = POST_FACING[npc.def and npc.def.range] or npc.facing or "down"
  end
  return npc.dsPost
end

-- Which way `other` is from `npc`, as a facing -- nil when they are not in
-- line, which is what keeps a chat to the four directions the sprites have.
local function facingToward(npc, other)
  local dx, dy = other.cellX - npc.cellX, other.cellY - npc.cellY
  if dx == 0 and dy == 0 then return nil end
  if dx ~= 0 and dy ~= 0 then return nil end
  if dx ~= 0 then return dx > 0 and "right" or "left" end
  return dy > 0 and "down" or "up"
end

-- ------- WORK: the thing this person is standing next to
--
-- Signs and doors, off the map's own two lookups. Asked of the four
-- neighbours rather than of the cell itself, because you stand BESIDE a sign
-- to read it and ON a door to go through one -- and somebody standing on a
-- door is Shelter's business, not this module's.
--
-- Deliberately does not include the counter tiles. A clerk behind a counter
-- is a STAY object whose authored facing already points across it, so `post`
-- covers that better than a lookup would, and the one thing worse than a
-- clerk who never moves is a clerk who turns away from the till.
local function interest(map, npc)
  local best = nil
  for _, dir in ipairs(DIRS) do
    -- the engine's own table, so a direction means here exactly what it
    -- means to every step in the game
    local d = Collision.DELTA[dir]
    local cx, cy = npc.cellX + d[1], npc.cellY + d[2]
    if map:inBounds(cx, cy) then
      local okS, sign = pcall(map.signAtCell, map, cx, cy)
      if okS and sign then return dir end
      local okD, door = pcall(map.isDoorTileCell, map, cx, cy)
      if okD and door then best = best or dir end
    end
  end
  return best
end

-- ------- CHAT: find somebody to talk to
--
-- In line, within reach, available, and not already in a conversation. The
-- scan is over the map's whole cast, which in a Gen 1 town is a dozen
-- people -- and it only runs on the beat that rolled a chat, for the one
-- person whose clock came up, so the cost is a dozen comparisons every few
-- seconds rather than anything per frame.
local function partnerFor(ow, npc)
  for _, other in ipairs(ow.npcs) do
    if other ~= npc and idle(other) and not other.dsChat then
      local reach = math.abs(other.cellX - npc.cellX)
                    + math.abs(other.cellY - npc.cellY)
      if reach > 0 and reach <= Routines.CHAT_REACH then
        local mine = facingToward(npc, other)
        if mine then return other, mine end
      end
    end
  end
  return nil
end

-- ------- has the conversation ended by itself
--
-- Deliberately NOT `idle`, and that distinction is a bug this had. `idle`
-- refuses anybody mid-step -- and a NOD is a step: the turn-in-place sets
-- `moving` for its sixteen frames. Checked with `idle`, every conversation
-- in Kanto ended a quarter of a second in, the instant either party shifted
-- their weight, which is the one thing the nod exists to do.
--
-- What actually ends one is the other person being gone, taken by something
-- with a better claim (a script, the rain, the player walking up), or simply
-- no longer standing where they were.
local function chatLost(npc, other)
  if not other or getmetatable(other) ~= NPC then return true end
  if other.dsChat ~= npc then return true end
  if other.frozen or other.dsShelter then return true end
  if other.dsGlanceFacing ~= nil then return true end
  local reach = math.abs(other.cellX - npc.cellX)
                + math.abs(other.cellY - npc.cellY)
  return reach == 0 or reach > Routines.CHAT_REACH
end

-- Both of them look away, and both take a moment before they do anything
-- else. Without that pause the one whose clock ran out rolls a fresh beat on
-- the very next frame -- and `partnerFor` would hand it straight back to the
-- person it has just stopped talking to, so the pair would nod at each other
-- forever with a stutter in it.
local function endChat(npc)
  local with = npc.dsChat
  npc.dsChat, npc.dsNod = nil, nil
  npc.dsBeat = roll(1.0, 2.5)
  if with and with.dsChat == npc then
    with.dsChat, with.dsNod = nil, nil
    with.dsBeat = roll(1.0, 2.5)
  end
end

-- The engine's own turn-in-place: `marching` animates the walk cycle without
-- translating (NPC_CHANGE_FACING, movement.asm), and NPC:update settles it
-- on its own before it ever looks at `frozen`. So this is one assignment and
-- the engine does the rest, at the same 16 frames every other step takes.
local function nod(npc)
  npc.moving = true
  npc.marching = true
  npc.progress = 0
end

-- ------- one person's beat
local function beat(ow, map, npc, night)
  local r = love.math.random()

  -- CHAT, unless it is late -- people are not standing in the street
  -- chatting at two in the morning, and the ones who are out at that hour
  -- reading as busy would be the wrong kind of alive
  if not night and r < Routines.CHAT_ODDS then
    local other, mine = partnerFor(ow, npc)
    if other then
      local theirs = facingToward(other, npc)
      npc.facing, other.facing = mine, theirs or other.facing
      npc.dsChat, other.dsChat = other, npc
      local hold = roll(Routines.CHAT_MIN, Routines.CHAT_MAX)
      npc.dsBeat, other.dsBeat = hold, hold
      npc.dsNod = roll(Routines.NOD_MIN, Routines.NOD_MAX)
      other.dsNod = roll(Routines.NOD_MIN, Routines.NOD_MAX)
      return
    end
  end

  -- WORK: face what you are standing beside. At night a door outranks
  -- everything else this could do -- somebody outside after dark is
  -- somebody about to go in, and `interest` already prefers a sign by day.
  if r < Routines.WORK_ODDS or night then
    local dir = interest(map, npc)
    if dir then
      npc.facing = dir
      npc.dsBeat = roll(Routines.BEAT_MIN, Routines.BEAT_MAX)
      return
    end
  end

  -- LOOK: somewhere else, for a bit. Never back at the way it is already
  -- facing, because a turn to where you were already looking is a beat that
  -- visibly did nothing.
  if r < Routines.LOOK_ODDS then
    for _ = 1, 4 do
      local dir = DIRS[rand(#DIRS)]
      if dir ~= npc.facing then
        npc.facing = dir
        npc.dsBeat = roll(Routines.BEAT_MIN, Routines.BEAT_MAX)
        return
      end
    end
  end

  -- POST: back to the facing the map authored.
  npc.facing = post(npc)
  npc.dsBeat = roll(Routines.BEAT_MIN, Routines.BEAT_MAX)
end

-- ------- per-frame
local failed = false

local function tick(dt)
  local Game = game()
  local ow = Game and Game.overworld
  if not (ow and ow.map and ow.player and ow.npcs) then return end
  if Game.stack and Game.stack:top() ~= ow then return end
  if ow.transitioning then return end
  if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then return end
  if not Routines.enabled() then return end

  local map = ow.map
  local tod = DayNight.tod()
  local night = tod == "NIGHT"

  for _, npc in ipairs(ow.npcs) do
    -- a chat has to be able to END even when one of the pair has since been
    -- frozen, moved or taken by the rain, or the other one stands there
    -- facing an empty cell for the rest of the session. Checked OUTSIDE the
    -- `idle` gate below, because the person who needs releasing is often the
    -- one who is no longer idle.
    if npc.dsChat and chatLost(npc, npc.dsChat) then endChat(npc) end

    if idle(npc) then
      post(npc)                     -- captured once, before anything moves it
      npc.dsBeat = (npc.dsBeat or roll(0, Routines.BEAT_MAX)) - dt
      if npc.dsChat then
        npc.dsNod = (npc.dsNod or 0) - dt
        if npc.dsNod <= 0 then
          nod(npc)
          npc.dsNod = roll(Routines.NOD_MIN, Routines.NOD_MAX)
        end
        if npc.dsBeat <= 0 then endChat(npc) end
      elseif npc.dsBeat <= 0 then
        beat(ow, map, npc, night)
      end
    end
  end
end

function Routines.update(dt)
  if failed then return end
  local ok, err = pcall(tick, dt or 0)
  if ok then return end
  failed = true
  if V.mod and V.mod.log then
    V.mod.log:warn("routines failed: %s -- the people stand still for this "
                   .. "session", tostring(err))
  end
end

-- ------- the agenda: who has one
--
-- Everything above is a facing, and the reason is written at the top of this
-- file: a cell is a claim, and moving the person standing in a doorway
-- invents a pathing problem to buy a town that is busier and less legible.
--
-- That argument holds for a STAY object. It does not hold for a WALK one.
-- A Gen 1 WALK object ALREADY takes a random step every two to six seconds
-- inside its range -- the ROM itself declared that this person may be
-- anywhere -- so no script can depend on the cell it is standing in, and
-- nothing downstream can tell the difference between the wandering it does
-- now and wandering with somewhere to be. Giving those a destination is not
-- adding movement to the game. It is putting a reason under movement that
-- is already there and currently reads as noise.
--
-- There are 98 of them in the whole game, 28-odd of those on maps with a
-- sky. That is a thin population and it is the honest one.

-- `npc.wanders` is the engine's own walker flag, and it is the filter here
-- for a specific reason: it is what the engine ACTS on, so a rule built
-- from it cannot drift from the behaviour being reasoned about. The data's
-- `def.movement == "WALK"` agrees with it on every map probed -- and is one
-- generated-file change away from not.
--
-- What this deliberately is NOT is `POST_FACING[def.range] == nil`, which
-- is what `post` reads a few dozen lines up and which would be a disaster
-- here: `range = "NONE"` is a STAY object with no authored facing -- the
-- bike shop clerk is one -- and there are 249 of those against 98 real
-- walkers. That filter puts a quarter of Kanto on the road.
--
-- `dsSpecies` is RoamerArt's stamp on a baked Pokemon sheet, so the guard
-- keeps this off the street Pokemon and CityLife pets, which have moods of
-- their own. No probe has caught one in `ow.npcs` yet; it is here for when
-- one appears rather than because one has.
function Routines.walkers(ow)
  local out = {}
  for _, npc in ipairs((ow and ow.npcs) or {}) do
    if getmetatable(npc) == NPC and npc.def and npc.wanders
       and not npc.def.trainerClass and not npc.def.dsSpecies then
      out[#out + 1] = npc
    end
  end
  return out
end

-- ------- the agenda: what hour it is
--
-- Four phases, because four is what the dial has. `DayNight.tod()` collapses
-- its six palette weights onto exactly these names, and the whole cycle is
-- CYCLE = 1200 seconds -- twenty real minutes, so each phase is five.
--
-- Nothing finer, and that is a constraint rather than a preference. A
-- schedule subdivided below this has somebody changing their mind every
-- couple of minutes, which reads as indecision; what makes a player call
-- something a routine is seeing the same person in the same place at the
-- same hour TWICE, and at five minutes a phase they get that inside one
-- session.
Routines.PHASES = { MORNING = "morning", DAY = "day",
                    EVENING = "evening", NIGHT = "night" }

function Routines.phase()
  local ok, tod = pcall(DayNight.tod)
  return (ok and Routines.PHASES[tod]) or "day"
end

-- ------- the agenda: where to be, and why it hangs off the AUTHORED cell
--
-- `def.x` and `def.y` are where the ROM put this person. That is the anchor,
-- and everything here measures from it rather than from `cellX/cellY`.
--
-- The difference looks pedantic and is the whole design. A WALK object has
-- been drifting since the map loaded, so its current cell is a function of
-- how long the player has been standing around -- and a destination computed
-- from it would inherit that history. The plan for this feature is that
-- position is a function of the CLOCK (so somebody off-screen costs one
-- lookup instead of a simulation), and a function of the clock cannot take
-- the wander as an input. Anchoring on `def` makes the same hour always
-- name the same place, which is also the thing that makes a player read it
-- as a routine rather than as drift.
--
-- Shelter anchors on `cellX/cellY` instead (`npc.dsHomeX = npc.cellX`) and
-- is right to: rain is transient and it only owes you the cell it took you
-- from. This owes you the cell the map author chose.

local function anchorOf(npc)
  local d = npc.def
  local ax, ay = d and tonumber(d.x), d and tonumber(d.y)
  if ax and ay then return ax, ay end
  return npc.cellX, npc.cellY        -- no authored cell: stand where you are
end

-- Doors, nearest-first from the anchor, one person per doorway.
--
-- The claim set is this module's own rather than Shelter's: the two features
-- can want the same doorway and must not silently share a ledger. Spreading
-- matters for the same reason it does there -- two NPCs cannot occupy one
-- cell, so filing a whole town into the closest door means everybody after
-- the first arrives to be refused.
--
-- Assigned over the cast in list order, which is stable for a given map, so
-- the same map at the same hour always produces the same assignment. That
-- determinism is not tidiness; it is what lets a walker be placed straight
-- at its destination without having simulated the walk.
local function doorFor(map, ax, ay, claimed)
  local ok, doors = pcall(Shelter.doorsFor, map)
  if not ok or not doors or #doors == 0 then return nil end
  local best, bestD, fallback, fallbackD = nil, nil, nil, nil
  for _, d in ipairs(doors) do
    local dist = math.abs(d[1] - ax) + math.abs(d[2] - ay)
    if not fallbackD or dist < fallbackD then fallback, fallbackD = d, dist end
    local key = d[1] .. "," .. d[2]
    if not claimed[key] and (not bestD or dist < bestD) then
      best, bestD = d, dist
    end
  end
  return best or fallback
end

-- Where every walker on this map belongs right now: npc -> { x, y }.
--
-- Computed for the whole cast at once because the night assignment is a
-- spread, and a spread cannot be decided one person at a time.
--
-- Three of the four phases send everybody to their anchor. That is not three
-- phases doing nothing: the anchor is where the ROM put them, so "go home to
-- your post" is what makes the night departure legible as a departure. A
-- street that never fills has not emptied.
function Routines.destinations(ow)
  local map = ow and ow.map
  if not map then return {} end
  -- Only FULL sends anybody to a doorway. Under DAY the night destination is
  -- the anchor like every other phase, which is the whole difference between
  -- "the people have somewhere to be" and "the town empties after dark".
  local night = (Routines.phase() == "night")
                and (Routines.agendaMode() == "full")
  local out, claimed = {}, {}
  local walkers = Routines.walkers(ow)

  -- Seed the claim set with the bodies that are ALREADY standing somewhere.
  --
  -- The spread below only knows about walkers, so on its own it will happily
  -- hand somebody a doorway that a STAY object has been parked in since the
  -- map loaded -- or that the player is standing in. Two NPCs cannot share a
  -- cell, so that is not a near miss: it is a person given a night post they
  -- can never occupy, standing in the street until morning.
  --
  -- Found by measurement rather than by reading: one of Fuchsia City's five
  -- walkers drew an occupied door.
  local isWalker = {}
  for _, npc in ipairs(walkers) do isWalker[npc] = true end
  for _, npc in ipairs(ow.npcs or {}) do
    if not isWalker[npc] then
      claimed[npc.cellX .. "," .. npc.cellY] = true
    end
  end
  if ow.player then
    claimed[ow.player.cellX .. "," .. ow.player.cellY] = true
  end

  for _, npc in ipairs(walkers) do
    local ax, ay = anchorOf(npc)
    if night then
      local d = doorFor(map, ax, ay, claimed)
      if d then
        claimed[d[1] .. "," .. d[2]] = true
        out[npc] = { d[1], d[2] }
      else
        out[npc] = { ax, ay }      -- a map with no warps: nowhere to go in
      end
    else
      out[npc] = { ax, ay }
    end
  end
  return out
end

-- ------- the agenda: placing somebody nobody is watching
--
-- The cheap half of the feature, and the half the hardware demands. Walking
-- every person on the map toward a destination every frame is a simulation
-- whose cost grows with the town; placing them costs one assignment each,
-- and it does not care whether the player has been standing still for two
-- seconds or twenty minutes, because the destination is a function of the
-- clock and not of the walk.
--
-- Which means the honest description of this feature is: the town rearranges
-- itself when you are not looking. That IS how open-world games do it, and
-- it is only a lie if you catch it happening -- so the entire correctness
-- condition here is that you cannot.

-- How far the player can see, in cells, ASKED OF THE RENDERER rather than
-- assumed from the Game Boy's 10x9 tiles: this mod draws a 3D scene and the
-- camera reaches further than the handheld ever did. Same question CityLife
-- asks before it spawns a pet.
--
-- The pad is deliberately fatter than CityLife's EDGE_PAD = 1. A pet that
-- pops in at the edge of view is a spawn and reads as one; a PERSON who
-- teleports at the edge of view is the illusion coming apart. The two are
-- not worth the same margin.
local TELEPORT_PAD = 4

-- Public because the probe has to assert against the SAME box this uses --
-- a test that recomputes the margin independently only proves the two agree
-- with each other.
function Routines.viewCells()
  local Game = game()
  local vw, vh = 160, 144
  local r = Game and Game.renderer
  if r and r.worldViewSize then
    local ok, w, h = pcall(r.worldViewSize, r)
    if ok and (w or 0) > 0 and (h or 0) > 0 then vw, vh = w, h end
  end
  return math.ceil(vw / 32) + TELEPORT_PAD, math.ceil(vh / 32) + TELEPORT_PAD
end

local function unseen(p, cx, cy, hw, hh)
  return math.abs(cx - p.cellX) > hw or math.abs(cy - p.cellY) > hh
end

-- Put every unwatched walker where the hour says it belongs. Returns how
-- many were moved, which is the number the probe reads.
--
-- BOTH ends have to be out of sight, and that is the rule most likely to be
-- got wrong by someone shortening this later. Checking only the destination
-- lets a person the player is looking at vanish; checking only the origin
-- lets one appear out of nothing a few cells ahead. Neither is softer than
-- the other -- they are the same bug seen from opposite sides.
--
-- Four things are left alone. Anybody Shelter is holding, because that body
-- is spoken for and the rain outranks the clock (main.lua runs Shelter first
-- for exactly this reason). Anybody mid-step, because the engine settles
-- `moving` before it reads `frozen` and interrupting that strands the
-- animation. Anybody already standing where they belong. And any destination
-- somebody else is already on, since two NPCs cannot share a cell and the
-- loser of that race would be standing inside a neighbour.
function Routines.materialize(ow)
  local p, map = ow and ow.player, ow and ow.map
  if not (p and map) then return 0 end
  local hw, hh = Routines.viewCells()
  local dest = Routines.destinations(ow)

  local taken = { [p.cellX .. "," .. p.cellY] = true }
  for _, npc in ipairs(ow.npcs or {}) do
    taken[npc.cellX .. "," .. npc.cellY] = true
  end

  local moved = 0
  for npc, d in pairs(dest) do
    local tx, ty = d[1], d[2]
    local key = tx .. "," .. ty
    if not (npc.cellX == tx and npc.cellY == ty)
       and not npc.dsShelter and not npc.moving
       and not taken[key]
       and unseen(p, npc.cellX, npc.cellY, hw, hh)
       and unseen(p, tx, ty, hw, hh) then
      taken[npc.cellX .. "," .. npc.cellY] = nil
      taken[key] = true
      -- the full placement, as Shelter's release does it: cell, pixels, and
      -- the half-finished step cleared behind them
      npc.cellX, npc.cellY = tx, ty
      npc.px, npc.py = tx * 16, ty * 16
      npc.targetX, npc.targetY = nil, nil
      npc.moving = false
      npc.progress = 0
      moved = moved + 1
    end
  end
  return moved
end

-- ------- the agenda: walking somebody who IS being watched
--
-- The expensive half, and the only half the player ever actually sees. A
-- person who is on screen cannot be placed, so they have to walk -- through
-- Shelter's own stepper, which is the engine's own step, so an NPC on the
-- agenda is refused by the same walls and bodies as any other and moves at
-- exactly the same speed.
--
-- This is what makes the cheap half honest. Materialisation rearranges the
-- town off screen; without this, the seam between the two is visible as a
-- person who is in the wrong place whenever you happen to be looking.

-- Agenda control is a hold, and it has to be releasable from anywhere: a map
-- change, a battle, the row going off, Shelter taking the town, or this
-- module throwing. Kept in a weak table for the same reason Shelter's is.
local onAgenda = setmetatable({}, { __mode = "k" })

local function agendaRelease(npc)
  if not npc.dsAgenda then return end
  npc.frozen = npc.dsAgendaFrozen or false
  if npc.dsAgendaSolid ~= nil then
    npc.passable = npc.dsAgendaSolid or nil
    npc.dsAgendaSolid = nil
  end
  npc.dsAgenda, npc.dsAgendaFrozen = nil, nil
  onAgenda[npc] = nil
end

-- ------- not being a wall
--
-- Somebody standing in a doorway all night is standing in a WARP, which is
-- the one cell the player most wants to walk through. Gen 1 NPCs are solid,
-- so a night post would quietly lock the player out of every shop in town.
--
-- The engine has had the answer since Yellow and Shelter already uses it:
-- `passable`. It is the same fix for the same situation -- a person who has
-- gone inside is not really standing in the door any more -- and it is why
-- this feature does not need the player and the NPC to trade cells. A swap
-- would be a mechanic this game has never had, invented to solve a problem
-- that only looked unsolved: the blocking that PERSISTS is the destination,
-- and the destination stops blocking. The blocking in transit lasts a second
-- and Gen 1's own wanderers have been doing it since 1996.
local function makePassable(npc)
  if npc.dsAgendaSolid == nil then npc.dsAgendaSolid = npc.passable or false end
  npc.passable = true
end

function Routines.releaseAgenda()
  for npc in pairs(onAgenda) do pcall(agendaRelease, npc) end
  onAgenda = setmetatable({}, { __mode = "k" })
end

local function agendaTake(npc)
  if npc.dsAgenda then return end
  npc.dsAgendaFrozen = npc.frozen or false
  -- freeze so the engine's own random wander stops fighting the destination;
  -- a step already set up still animates, because NPC:update settles
  -- `moving` before it ever reads this
  npc.frozen = true
  npc.dsAgenda = true
  onAgenda[npc] = true
end

-- One step each, for the walkers the player can see. Returns how many are
-- still short of where the hour says they belong.
--
-- Shelter outranks the clock, and this is where that is enforced rather than
-- hoped for. `Shelter.indoors()` is the public read of its phase; while it
-- is holding the town, the agenda lets go of every body it had and does
-- nothing, so the rain gets an uncontested town. main.lua already runs
-- Shelter first, which is the other half of the same rule.
--
-- The hold is dropped the moment somebody arrives. Leaving people frozen at
-- their destination would keep them there through the next phase, and a
-- shopkeeper who never goes back to the till is worse than one who never
-- left it.
function Routines.walkTick(ow)
  if Shelter.indoors() then
    Routines.releaseAgenda()
    return 0
  end
  local p, map = ow and ow.player, ow and ow.map
  if not (p and map) then return 0 end

  local hw, hh = Routines.viewCells()
  local dest = Routines.destinations(ow)
  local pending = 0

  for npc, d in pairs(dest) do
    local tx, ty = d[1], d[2]
    local arrived = (npc.cellX == tx and npc.cellY == ty)
    local seen = math.abs(npc.cellX - p.cellX) <= hw
                 and math.abs(npc.cellY - p.cellY) <= hh
    if npc.dsShelter then
      agendaRelease(npc)                  -- Shelter owns this one
    elseif arrived then
      -- Held rather than released once they are posted, and only at night:
      -- a doorway is a warp and a solid body in it locks the player out of
      -- the building. By day the anchor is ordinary ground and they should
      -- go back to being a person you can bump into.
      if Routines.phase() == "night" and Routines.agendaMode() == "full" then
        agendaTake(npc)
        npc.facing = "up"                 -- a door is drawn above its cell
        makePassable(npc)
      else
        agendaRelease(npc)
      end
    elseif seen then
      agendaTake(npc)
      pcall(Shelter.stepToward, map, ow.entities, npc, tx, ty)
      -- Cannot get there -- fenced yard, a body in the only gap, a door on
      -- the far side of a building. Hand them back rather than let them
      -- stand where they gave up: a walker frozen mid-corridor IS the
      -- persistent block this feature must not create, and an ordinary
      -- wanderer moves out of the way by itself within seconds.
      if (npc.dsStuck or 0) >= (Shelter.PATIENCE or 12) then
        npc.dsStuck = 0
        agendaRelease(npc)
      end
      pending = pending + 1
    else
      -- off screen: materialize() will place it, and holding it frozen in
      -- the meantime would stop its ordinary wander for no visible gain
      agendaRelease(npc)
      pending = pending + 1
    end
  end
  return pending
end

-- ------- the agenda: the strays go in
--
-- This is the half that actually reads as a town emptying, and it is the
-- cheapest thing in the feature.
--
-- The map's own people cannot be thinned much: there are 98 WALK objects in
-- all of Kanto and Pewter City owns exactly one, so "everybody goes home"
-- moves a single sprite there. The street Pokemon are a different kind of
-- thing entirely -- this mod made them, they hold no object index, and no
-- script has ever heard of one -- so they can simply stop being there, which
-- is the same licence Shelter already takes when it rains.
--
-- Removed only OUT OF SIGHT, on the same rule materialisation follows: a pet
-- winking out in front of the player is worse than a pet that is still
-- around. It means the streets thin over a few seconds as the player walks
-- rather than all at once, which is also how a town actually empties.
function Routines.nightPets(ow)
  local night = (Routines.phase() == "night")
                and (Routines.agendaMode() == "full")
  -- The brake goes on and off with the hour whether or not there is a map to
  -- act on, so morning -- or the row being turned down -- always releases the
  -- spawner even if this returns early. A hold that outlives its reason is
  -- indistinguishable from the feature working until the streets are
  -- permanently empty.
  CityLife.holdNight = night
  if not night then return 0 end

  local p = ow and ow.player
  if not p then return 0 end
  local hw, hh = Routines.viewCells()
  local gone = 0
  local ok, cast = pcall(CityLife.cast, ow)
  if not ok or not cast then return 0 end

  -- Walked backwards: CityLife.remove mutates the cast it was read from, and
  -- a forward ipairs over a list being spliced skips entries.
  for i = #cast, 1, -1 do
    local pet = cast[i]
    local cx, cy = pet and pet.cellX, pet and pet.cellY
    if cx and (math.abs(cx - p.cellX) > hw or math.abs(cy - p.cellY) > hh) then
      if pcall(CityLife.remove, ow, pet) then gone = gone + 1 end
    end
  end
  return gone
end

-- ------- the agenda, per frame
--
-- The same guards the beats run behind, and one of them is load-bearing here
-- in a way it is not up there: `ow.runner:isRunning()` means a script owns
-- the cast, and a script that has positioned somebody for a cutscene must
-- not find them walked away mid-sentence. A facing changing under a script
-- is a small wrongness; a body changing cell is a broken scene.
--
-- Order inside the frame matters. `walkTick` first, so anybody in shot is
-- stepped and, on arrival, released -- then `materialize`, which will not
-- touch a body that is mid-step anyway, and finally the strays. Running the
-- placement first would race the stepper for the same person on the frame
-- they cross the edge of view.
local agendaFailed = false

local function agendaTick(dt)
  local Game = game()
  local ow = Game and Game.overworld
  if not (ow and ow.map and ow.player and ow.npcs) then return end
  if Game.stack and Game.stack:top() ~= ow then return end
  if ow.transitioning then return end
  if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then return end

  if Routines.agendaMode() == "off" then
    -- Turned down mid-session: hand back every body and lift the brake, or
    -- the town keeps whatever arrangement it had when the row moved.
    Routines.releaseAgenda()
    CityLife.holdNight = false
    return
  end

  Routines.walkTick(ow)
  Routines.materialize(ow)
  Routines.nightPets(ow)
end

function Routines.agendaUpdate(dt)
  if agendaFailed then return end
  local ok, err = pcall(agendaTick, dt or 0)
  if ok then return end
  agendaFailed = true
  -- Leave nothing held: a body frozen by a throw never wanders again, and
  -- a spawner brake left on empties the streets for the rest of the session.
  pcall(Routines.releaseAgenda)
  CityLife.holdNight = false
  if V.mod and V.mod.log then
    V.mod.log:warn("agenda failed: %s -- the people keep their posts for "
                   .. "this session", tostring(err))
  end
end

-- ------- for the probe
--
-- "The street is alive" is not a claim a screenshot settles -- one frame of
-- a turning head and one frame of a still one are the same picture. What is
-- checkable is that the facings CHANGE and that two people ever end up
-- pointed at each other, so both are counted.
function Routines.chatting(ow)
  local n = 0
  for _, npc in ipairs((ow and ow.npcs) or {}) do
    if npc.dsChat then n = n + 1 end
  end
  return n
end

return Routines
