-- A wild Pokemon standing on the map, as an ordinary map object.
--
-- Same contract as src/world/NPC.lua and nothing more: cell, pixel
-- position, facing, a step in progress, pose() and draw().  That is the
-- whole trick.  The engine's overworld already y-sorts, collides against,
-- updates and draws whatever is in its two lists, and this mod's voxel pass
-- already stands a card up for whatever pose() hands it -- so a roamer that
-- answers like an NPC gets the flat game, the diorama, the sun's shadow,
-- the palette bake and the tall-grass overdraw with nothing written twice.
--
-- What it deliberately is NOT is a MAP OBJECT: `def` carries no trainer
-- class, no species argument, no item, no text and a sprite id that is not
-- the boulder's, so trainer sight-lines, the Strength push, npcByIndex, the
-- script commands and the interact chain all walk straight past it.  The
-- one thing that knows a roamer from an NPC is `roamer`, and the two places
-- that read it are in WildRoamers.
--
-- It does not wander like an NPC either.  An NPC roams whatever ground the
-- object's range allows; a wild Pokemon stays in the terrain it was rolled
-- out of -- grass in the grass, water on the water, a cave's floor in the
-- cave -- because a Rattata standing on the road is not a wild Rattata, it
-- is a loose sprite.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Collision = require("src.world.Collision")
local SpriteRenderer = require("src.render.SpriteRenderer")

local Roamer = {}
Roamer.__index = Roamer

-- Longer than the 16-frame walk every person on the map takes.  A mon that
-- moved at walking pace read as another NPC; ambling is what tells the eye
-- that this one is not on an errand.
local STEP_FRAMES = 24

-- How a roamer answers the player being near.  Most do not -- a wild mon
-- minding its own business is the baseline and the thing you are dodging --
-- but a few come and have a look and a few keep their distance, which is
-- what stops a meadow full of them reading as clockwork.
local MOODS = { "wander", "wander", "wander", "wander",
                "curious", "curious", "shy" }
local NOTICE = 5              -- cells; beyond this nobody has an opinion

local DIRS = { "up", "down", "left", "right" }

-- Everything the engine reads off a map object, answered in the negative.
-- Shared by every roamer because nothing ever writes to it.
local INERT_DEF = { index = -1, name = false, sprite = false,
                    movement = "WALK", range = "ANY_DIR" }

local nextId = 0

-- Whether `kind` terrain can hold a roamer at this cell.
--
-- Exposed as a plain function as well as a method because the spawner asks
-- the same question about cells that have no roamer on them yet.
--
-- Warps are refused outright, for the reason NPC:update refuses them: a
-- wanderer that steps onto a door is a wanderer that leaves the map.
function Roamer.standable(kind, map, cx, cy)
  if not map:inBounds(cx, cy) then return false end
  if map:warpAtCell(cx, cy) then return false end
  if kind == "water" then return map:isWaterCell(cx, cy) end
  if not map:isWalkableCell(cx, cy) then return false end
  if kind == "grass" then return map:isGrassCell(cx, cy) end
  return true
end

function Roamer.new(spriteDef, species, level, kind, cellX, cellY)
  nextId = nextId + 1
  local self = setmetatable({}, Roamer)
  self.roamer = true
  self.def = INERT_DEF
  self.id = ("DS_ROAM_%d"):format(nextId)
  self.species, self.level, self.kind = species, level, kind
  self.sprite = SpriteRenderer.new(spriteDef, self.id)
  self.cellX, self.cellY = cellX, cellY
  self.px, self.py = cellX * 16, cellY * 16
  self.facing = "down"
  self.moving = false
  self.progress = 0
  self.stepFlip = false
  self.frozen = false
  self.wanders = true
  -- what lets Collision.canMove hand it a water cell, which is otherwise
  -- unwalkable to everybody: the same field the player's surf sets
  self.surfing = kind == "water"
  self.mood = MOODS[love.math.random(#MOODS)]
  self.timer = love.math.random(20, 90)
  self.clock = love.math.random(0, 60)
  return self
end

function Roamer:facePlayer(player)
  local dx = player.cellX - self.cellX
  local dy = player.cellY - self.cellY
  if math.abs(dx) > math.abs(dy) then
    self.facing = dx > 0 and "right" or "left"
  else
    self.facing = dy > 0 and "down" or "up"
  end
end

-- Which way this one fancies going.  A mood only speaks when the player is
-- close enough to be the reason for it; otherwise, and for most of them,
-- it is a coin.
local function pickDir(self)
  if self.mood ~= "wander" then
    local Game = require("src.core.Game")
    local ow = Game and Game.overworld
    local p = ow and ow.player
    if p then
      local dx, dy = p.cellX - self.cellX, p.cellY - self.cellY
      local reach = math.abs(dx) + math.abs(dy)
      if reach > 0 and reach <= NOTICE then
        local toward = self.mood == "curious" and 1 or -1
        if math.abs(dx) > math.abs(dy) then
          return (dx * toward > 0) and "right" or "left"
        end
        return (dy * toward > 0) and "down" or "up"
      end
    end
  end
  return DIRS[love.math.random(#DIRS)]
end

-- Driven by the engine's own per-frame walk over ow.npcs, on the same tick
-- and with the same arguments every NPC gets -- so a roamer is frozen by
-- the same dialogue, stopped by the same battle and stepped at the same
-- rate as the people around it, with nothing scheduling it separately.
function Roamer:update(map, entities)
  self.clock = self.clock + 1
  if self.moving then
    self.progress = self.progress + 1
    local d = Collision.DELTA[self.facing]
    local moved = math.floor(self.progress * 16 / STEP_FRAMES)
    self.px = self.cellX * 16 + d[1] * moved
    self.py = self.cellY * 16 + d[2] * moved
    if self.progress >= STEP_FRAMES then
      self.cellX, self.cellY = self.targetX, self.targetY
      self.targetX, self.targetY = nil, nil
      self.px, self.py = self.cellX * 16, self.cellY * 16
      self.moving = false
      self.stepFlip = not self.stepFlip
    end
    return
  end
  if self.frozen or self.dead then return end
  self.timer = self.timer - 1
  if self.timer > 0 then return end
  self.timer = love.math.random(25, 110)
  local dir = pickDir(self)
  self.facing = dir
  -- sometimes it only looks: a mon that turned its head is doing something,
  -- and a mon that stepped every single time it thought about it is a
  -- machine
  if love.math.random() < 0.35 then return end
  local tx, ty = Collision.target(self.cellX, self.cellY, dir)
  if not Roamer.standable(self.kind, map, tx, ty) then return end
  if not Collision.canMove(map, entities, self, dir) then return end
  self.targetX, self.targetY = tx, ty
  self.moving = true
  self.progress = 0
end

function Roamer:walkPhase()
  if not self.moving then return 0 end
  local p = self.progress % STEP_FRAMES
  return (p >= STEP_FRAMES / 4 and p < STEP_FRAMES * 3 / 4) and 1 or 0
end

-- The same contract Player:pose and NPC:pose answer: the sheet, the
-- position, the facing and the step phase this frame renders to.
--
-- The y handed back is the VISUAL one, which is the seam a breath rides on:
-- a standing mon lifts a pixel and settles, and because the flat draw blits
-- at this y while the voxel pass turns the difference from the entity's own
-- y into vertical LIFT (VoxelScene's posesOf), the one line reads as a bob
-- in 2D and as the mon actually rising off the ground in 3D.
function Roamer:pose()
  local vy = self.py
  if not self.moving and math.floor(self.clock / 30) % 2 == 1 then
    vy = vy - 1
  end
  return self.sprite, self.px, vy, self.facing,
         self:walkPhase(), self.stepFlip, false
end

function Roamer:draw(camX, camY)
  local sprite, px, py, facing, phase, flip = self:pose()
  sprite:draw(px, py, camX, camY, facing, phase, flip)
end

return Roamer
