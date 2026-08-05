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
local Water = V.require("Water")
local Wind = V.require("Wind")

local Roamer = {}
Roamer.__index = Roamer

-- Longer than the 16-frame walk every person on the map takes.  A mon that
-- moved at walking pace read as another NPC; ambling is what tells the eye
-- that this one is not on an errand.
local STEP_FRAMES = 24

-- How many pixels of a water mon's 16px card sit UNDER the waterline.
-- The top of the body sticks out; the cut edge is the waterline (see
-- SpriteBillboards.buildCard with cut, and VoxelScene's waterline pose).
-- Five is enough to read as swimming without losing the species silhouette.
Roamer.WATERLINE = 5

-- Where on a grass mon the wind is felt (0 = feet, 1 = head).  Mid-body so
-- the feet stay in the grass and the torso leans with the tufts around it.
Roamer.WIND_HEIGHT = 0.55

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
  self.id = ("TR_ROAM_%d"):format(nextId)
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
  -- Water mon amble more slowly than land mon -- a fish crossing a pond is
  -- not in a hurry -- and land mon keep the wider window.  A breeze shortens
  -- the grass mon's pause: the meadow is restless, so they are too.
  local wind = 0
  if self.kind == "grass" then
    local ok, a = pcall(Wind.amount)
    if ok and a then wind = a end
  end
  if self.kind == "water" then
    self.timer = love.math.random(40, 140)
  else
    local hi = math.max(20, 110 - math.floor(wind * 12))
    local lo = math.max(12, 25 - math.floor(wind * 4))
    self.timer = love.math.random(lo, hi)
  end
  local dir = pickDir(self)
  -- Under a real breeze, grass mon prefer the wind's own bearing about half
  -- the time -- they lean into the gust rather than pacing a grid of coin
  -- flips.  The wind DIR is world XZ; map facing maps x->left/right, z->up/down.
  if wind > 0 and self.kind == "grass" and love.math.random() < 0.45 then
    local dx, dz = Wind.DIR[1], Wind.DIR[2]
    if math.abs(dx) > math.abs(dz) then
      dir = dx > 0 and "right" or "left"
    else
      dir = dz > 0 and "down" or "up"
    end
  end
  self.facing = dir
  -- sometimes it only looks: a mon that turned its head is doing something,
  -- and a mon that stepped every single time it thought about it is a
  -- machine.  Water mon look more than they swim (0.5 vs 0.35): a pond full
  -- of things always moving reads as busy traffic, not as wildlife.  Wind
  -- lowers the grass mon's look-only chance so a gale actually moves them.
  local lookOnly = self.kind == "water" and 0.50
                   or math.max(0.15, 0.35 - wind * 0.04)
  if love.math.random() < lookOnly then return end
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
-- The y handed back is the VISUAL one, which is the seam a breath rides on.
-- On LAND a standing mon lifts a pixel and settles; on WATER the breath IS
-- the swell -- the same two sines the surface rides (Water.heightAt), so
-- the mon and the pond rise and fall together rather than the mon ticking
-- on its own clock against a plane that has its own.  On GRASS the body
-- also leans with Wind.leanAt, the same travelling wave the tufts ride, so
-- a mon in the meadow and the grass around it move together.  The flat
-- draw blits at this y; the voxel pass puts water mon on Water.surfaceAt
-- with a waterline-cut card (VoxelScene) and applies the same lean offset.
function Roamer:pose()
  local px, py = self.px, self.py
  local vy = py
  if self.kind == "water" then
    local ok, h = pcall(Water.heightAt, px + 8, py + 8)
    if ok and h then vy = vy - h end
  elseif self.kind == "grass" then
    local ok, lx, lz = pcall(Wind.leanAt, px + 8, py + 8, Roamer.WIND_HEIGHT)
    if ok and lx then
      px = px + lx
      py = py + lz
      vy = py
    end
    if not self.moving and math.floor(self.clock / 30) % 2 == 1 then
      vy = vy - 1
    end
  elseif not self.moving and math.floor(self.clock / 30) % 2 == 1 then
    vy = vy - 1
  end
  return self.sprite, px, vy, self.facing,
         self:walkPhase(), self.stepFlip, false
end

function Roamer:draw(camX, camY)
  local sprite, px, py, facing, phase, flip = self:pose()
  if self.kind ~= "water" or not love or not love.graphics then
    sprite:draw(px, py, camX, camY, facing, phase, flip)
    return
  end
  -- Waterline respects ice + freeze/thaw blend (Water.waterlineCut).
  local cut = Roamer.WATERLINE
  do
    local ok, c = pcall(Water.waterlineCut, px + 8, py + 8, Roamer.WATERLINE)
    if ok and c then cut = c end
  end
  if cut <= 0 then
    sprite:draw(px, py, camX, camY, facing, phase, flip)
    return
  end
  -- 2D waterline: hide the bottom cut pixels of the 16x16 blit so the mon
  -- is cut at the water the same way the 3D card is.  Scissor is in screen
  -- pixels of the current canvas; if anything about the camera scale
  -- disagrees, fall back to the full draw rather than a wrong crop.
  local g = love.graphics
  local sx = math.floor(px - camX)
  local sy = math.floor(py - camY)
  local ok = pcall(function()
    local x, y, w, h = g.getScissor()
    g.setScissor(sx, sy, 16, 16 - cut)
    sprite:draw(px, py, camX, camY, facing, phase, flip)
    if x then g.setScissor(x, y, w, h) else g.setScissor() end
  end)
  if not ok then
    sprite:draw(px, py, camX, camY, facing, phase, flip)
  end
end

return Roamer
