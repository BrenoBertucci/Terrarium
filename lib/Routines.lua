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
