-- The lead Pokemon, walking one step behind you (the FOLLOW row).
--
-- Yellow already does this for one Pokemon: src/world/PikachuFollower.lua
-- stands its Pikachu in ow.npcs (so the engine's own update/draw walk moves
-- and paints it) with `passable` set (so Collision.occupied lets you walk
-- straight through it) and chases the cell the player just vacated. This
-- is that, for whoever leads the party -- in Red and Blue, and in Yellow
-- whenever the engine's own Pikachu is not out. When it IS out, this stands
-- down: one companion, and the one the cartridge wrote wins.
--
-- It is here because of the GLOW row (lib/Glow.lua). A Charmander's tail is
-- a light, and a light needs somebody carrying it: in the dark of Rock
-- Tunnel the thing walking behind you is the lantern, and FLASH is it
-- lighting the whole cave around you. Glow reads `dsFollower` and the
-- species off this entity; nothing here knows about light.
--
-- Presentational, like the wild ones (lib/Roamer.lua): the art is the same
-- walk sheet (RoamerArt), the def is inert (no trainer class, no text, a
-- negative object index), so sight lines, scripts, npcByIndex and the
-- civilians' own modules (Shelter, Routines: NPC metatable only) all walk
-- past it. It is never saved: ow.npcs is rebuilt by every map load and the
-- tick below simply puts it back.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local RoamerArt = V.require("RoamerArt")

local Collision = require("src.world.Collision")
local SpriteRenderer = require("src.render.SpriteRenderer")

local Follower = {}

Follower.setting = ModSetting.new("follow", "FOLLOW",
                                  { true, false },
                                  { "ON", "OFF" })

function Follower.enabled()
  local ok, v = pcall(Follower.setting.get, Follower.setting)
  return ok and v == true
end

local function game()
  local ok, G = pcall(require, "src.core.Game")
  return ok and G or nil
end

-- Everything the engine reads off a map object, answered in the negative
-- (the same inert shape a roamer carries).
local INERT_DEF = { index = -1, name = false, sprite = false,
                    movement = "STAY", range = "NONE" }

local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }

-- ------- the entity
--
-- The contract src/world/NPC.lua answers and nothing more: cell, pixel
-- position, facing, a step in progress, update(), pose() and draw().

local Mon = {}
Mon.__index = Mon

local function newMon(def, species, cx, cy, facing, player)
  local self = setmetatable({}, Mon)
  self.dsFollower = true
  self.passable = true
  self.wanders = false
  self.def = INERT_DEF
  self.id = "TR_FOLLOW"
  self.species = species
  self.sprite = SpriteRenderer.new(def, self.id)
  self.cellX, self.cellY = cx, cy
  self.px, self.py = cx * 16, cy * 16
  self.facing = facing or "down"
  self.moving = false
  self.progress = 0
  self.stepFrames = 16
  self.stepFlip = false
  self.clock = 0
  self.hop = 0
  -- the cell the player is committed to; a change is a step to follow
  self.trail = { x = player.targetX or player.cellX,
                 y = player.targetY or player.cellY }
  return self
end

function Mon:advance()
  self.progress = self.progress + 1
  local d = Collision.DELTA[self.facing]
  local moved = math.floor(self.progress * 16 / self.stepFrames)
  self.px = self.cellX * 16 + d[1] * moved
  self.py = self.cellY * 16 + d[2] * moved
  if self.progress >= self.stepFrames then
    self.cellX, self.cellY = self.targetX, self.targetY
    self.targetX, self.targetY = nil, nil
    self.px, self.py = self.cellX * 16, self.cellY * 16
    self.moving = false
    self.stepFlip = not self.stepFlip
  end
end

-- Driven by the engine's own per-frame walk over ow.npcs. One step behind:
-- the trail is the cell the player COMMITTED to (targetX while a step is in
-- flight), so the follower sets off into the cell being vacated on the same
-- frame the player does -- PikachuFollower's reading of pikachu_follow.asm,
-- and the reason it rests exactly one cell back instead of two.
function Mon:update()
  self.clock = self.clock + 1
  if self.hop > 0 then self.hop = self.hop - 1 end
  local G = game()
  local p = G and G.overworld and G.overworld.player
  if not p then return end
  local destX, destY = p.targetX or p.cellX, p.targetY or p.cellY
  local tr = self.trail
  if destX ~= tr.x or destY ~= tr.y then
    self.goalX, self.goalY = tr.x, tr.y
    tr.x, tr.y = destX, destY
  end
  if self.moving then
    self:advance()
    return
  end
  if not self.goalX then return end
  local gx, gy = self.goalX, self.goalY
  if self.cellX == gx and self.cellY == gy then
    self.goalX, self.goalY = nil, nil
    return
  end
  -- fell far behind (a warp's placement, a forced slide): snap, as the
  -- engine's own follower does
  local far = math.abs(self.cellX - gx) + math.abs(self.cellY - gy)
  if far > 6 then
    self.cellX, self.cellY = gx, gy
    self.px, self.py = gx * 16, gy * 16
    self.goalX, self.goalY = nil, nil
    return
  end
  local dir
  if self.cellX < gx then dir = "right"
  elseif self.cellX > gx then dir = "left"
  elseif self.cellY < gy then dir = "down"
  else dir = "up" end
  self.facing = dir
  local d = Collision.DELTA[dir]
  self.targetX, self.targetY = self.cellX + d[1], self.cellY + d[2]
  -- the player's own step length (running shortens it), halved while more
  -- than a cell behind -- FastPikachuFollow's rule
  local len = p.stepFramesCur or p.stepFrames or 16
  if far > 1 then len = math.max(1, math.floor(len / 2)) end
  self.stepFrames = len
  self.moving = true
  self.progress = 0
  -- the engine's npc walk already ran this frame's update; burn the step's
  -- first frame now or the follower drifts a pixel further back every tile
  self:advance()
end

function Mon:walkPhase()
  if not self.moving then return 0 end
  local p = self.progress % self.stepFrames
  return (p >= self.stepFrames / 4 and p < self.stepFrames * 3 / 4) and 1 or 0
end

-- The visual y rides a breath while standing (a pixel up, a pixel down, on
-- the half-second the wild ones use) and a small hop when spoken to.
function Mon:pose()
  local vy = self.py
  if self.hop > 0 then
    local t = self.hop / Follower.HOP_FRAMES
    vy = vy - math.floor(math.sin(t * math.pi) * 6 + 0.5)
  elseif not self.moving and math.floor(self.clock / 30) % 2 == 1 then
    vy = vy - 1
  end
  return self.sprite, self.px, vy, self.facing,
         self:walkPhase(), self.stepFlip, false
end

function Mon:draw(camX, camY)
  local sprite, px, py, facing, phase, flip = self:pose()
  sprite:draw(px, py, camX, camY, facing, phase, flip)
end

Follower.HOP_FRAMES = 18

-- ------- who leads
--
-- The first Pokemon in the party still standing: the one that would be sent
-- out, which is the one that walks with you.
local function leadSpecies(G)
  for _, mon in ipairs((G.save and G.save.party) or {}) do
    if (mon.hp or 0) > 0 and mon.species then return mon.species end
  end
  return nil
end

local function find(ow)
  for i, npc in ipairs(ow.npcs or {}) do
    if npc.dsFollower then return npc, i end
  end
  return nil
end

local function enginePikachu(ow)
  for _, npc in ipairs(ow.npcs or {}) do
    if npc.pikachuFollower then return npc end
  end
  return nil
end

local function remove(ow, mon)
  for i = #(ow.npcs or {}), 1, -1 do
    if ow.npcs[i] == mon then table.remove(ow.npcs, i) end
  end
  for i = #(ow.entities or {}), 1, -1 do
    if ow.entities[i] == mon then table.remove(ow.entities, i) end
  end
end

-- Where a fresh follower stands: the cell BEHIND the player when that is
-- ground, so the two cards never start on one spot (in 3D two cards on one
-- cell fight over the same depth); under the player when it is not, and
-- the first step walks it out -- the engine's own spawn for its Pikachu.
local function spawnCell(map, p)
  local d = Collision.DELTA[OPPOSITE[p.facing] or "up"]
  local cx, cy = p.cellX + d[1], p.cellY + d[2]
  if map:inBounds(cx, cy) and map:isWalkableCell(cx, cy)
     and not map:warpAtCell(cx, cy) then
    return cx, cy
  end
  return p.cellX, p.cellY
end

-- The one follower this module owns, or nil. Read by lib/Glow.lua.
function Follower.current()
  local G = game()
  local ow = G and G.overworld
  return ow and find(ow) or nil
end

local function tick()
  local G = game()
  local ow = G and G.overworld
  if not (ow and ow.map and ow.player and ow.npcs and ow.entities) then return end
  -- only while the overworld itself is running: a battle culls the cast
  -- into a copy (OverworldBattle.cullCast) and anything added to it would
  -- be thrown away with it
  if G.stack and G.stack:top() ~= ow then return end
  if ow.transitioning then return end

  local p = ow.player
  local species = leadSpecies(G)
  local want = Follower.enabled() and species ~= nil
               and RoamerArt.available()
               and not enginePikachu(ow)
               and not p.surfing and not (G.save and G.save.onBike)
  local mon = find(ow)
  if mon and (not want or mon.species ~= species) then
    remove(ow, mon)
    mon = nil
  end
  if not want or mon then return end

  local def = RoamerArt.def(species, true)
  if not def then return end
  local cx, cy = spawnCell(ow.map, p)
  mon = newMon(def, species, cx, cy, p.facing, p)
  ow.npcs[#ow.npcs + 1] = mon
  -- entities is the draw list; `passable` keeps it out of collision
  ow.entities[#ow.entities + 1] = mon
end

-- A per-frame hook that throws retires the whole pipeline it rides for the
-- session, so a failure here retires only this feature (the pattern
-- WildRoamers set): the follower is taken off the map and stays off.
local failed = false

function Follower.update()
  if failed then return end
  local ok, err = pcall(tick)
  if ok then return end
  failed = true
  V.mod.log:warn("follower failed: %s -- the walking companion is off for "
                 .. "this session", tostring(err))
  local G = game()
  local ow = G and G.overworld
  local mon = ow and find(ow)
  if mon then pcall(remove, ow, mon) end
end

-- ------- talking to it
--
-- A follower sits in ow.npcs, which puts it in front of the A button, and
-- the engine's talkTo is all about a map object's text and scripts. So it
-- is answered here: it turns to you, hops, and says its name the way it
-- does in battle. Chained like WildRoamers' and CityLife's wraps, each
-- passing along whatever is not its own.
local function talk(ow, mon)
  local p = ow.player
  if p then mon.facing = OPPOSITE[p.facing] or mon.facing end
  mon.hop = Follower.HOP_FRAMES
  local G = game()
  pcall(function()
    require("src.core.Sound").playCry(G.data, mon.species)
  end)
end

function Follower.install()
  local OverworldState = require("src.world.OverworldController")
  if OverworldState.terrariumFollowHook then return end
  local inner = OverworldState.talkTo
  function OverworldState:talkTo(npc)
    if npc and npc.dsFollower then
      pcall(talk, self, npc)
      return
    end
    return inner(self, npc)
  end
  OverworldState.terrariumFollowHook = true
end

return Follower
