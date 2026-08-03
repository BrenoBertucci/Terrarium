-- Voxel world mode: the hidden items, findable.
--
-- Gen 1 buries about eighty items in the ground -- in bins, under trees, in
-- corners of caves -- and gives you exactly one way to know: the Itemfinder,
-- which says "there is one within a few tiles" and nothing about WHERE. What
-- follows is walking every tile of the area pressing A. That is not a puzzle,
-- it is a search, and the search has no information in it.
--
-- So the ground tells you. A small cel-shaded glint over the cell, in the
-- same overlay pass the ambient life composites through, on the cells the
-- game's own `field.hiddenItems` names -- and gone the moment the item is
-- taken, because `save.hiddenTaken` is the same record the pickup writes.
--
-- ------- what this deliberately does NOT do
--
-- It does not name the item, and it does not pick it up. You still have to
-- notice the glint, walk to it and press A -- so it is the Itemfinder made
-- honest rather than the item handed over. Nothing here writes to the save,
-- nothing joins ow.entities, nothing can be collided with. It is a light on
-- a floor.
--
-- ------- and why it is on the QOL row rather than AMBIENT
--
-- AMBIENT is the things that make the diorama read as alive: butterflies,
-- crickets, someone glancing up as you pass. A glint over a buried Rare
-- Candy is not alive -- it is a mercy, and QOL is the row that says "OFF is
-- the full 1996 friction". This belongs with the auto-repel and the HMs on A.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local QoL = V.require("QoL")

local HiddenItems = {}

local function game()
  return require("src.core.Game")
end

function HiddenItems.enabled()
  return QoL.enabled()
end

-- ------- the glint
--
-- Flat, hard-edged, two tones and a pulse -- the same rules the steam and the
-- splashes follow. A soft glowing orb over a world made of voxels would be
-- the one thing on screen that looked like it came from another game.
--
-- Pale gold rather than white: white is what this mod's snow, steam and rain
-- already are, and a fourth white thing on the ground would read as one of
-- them lying there.
HiddenItems.COLOR = { 1.00, 0.94, 0.62 }
HiddenItems.PERIOD = 1.9          -- seconds per pulse
HiddenItems.HEIGHT = 3            -- world px above the ground it floats
HiddenItems.REACH = 12            -- cells from the player it is drawn within

-- ------- what is buried near here
--
-- Rebuilt when the MAP changes and not otherwise: the list comes from static
-- field data and the only thing that shrinks it is a pickup, which the draw
-- re-checks per glint against `hiddenTaken`. So walking over one takes its
-- light out on the next frame without this having to be told.
local state = { mapId = nil, spots = {} }

local function rebuild(ow)
  local Game = game()
  local field = Game.data and Game.data.field
  local list = field and field.hiddenItems and field.hiddenItems[ow.map.id]
  local out = {}
  for _, h in ipairs(list or {}) do
    if h.x and h.y then
      out[#out + 1] = {
        cx = h.x, cy = h.y,
        key = ow.map.id .. "_" .. h.x .. "_" .. h.y,
        -- a phase per cell so two glints in one room are not a metronome
        seed = ((h.x * 31 + h.y * 17) % 100) / 100 * 6.2831,
      }
    end
  end
  return out
end

function HiddenItems.update()
  local Game = game()
  local ow = Game and Game.overworld
  if not (ow and ow.map) then return end
  if state.mapId == ow.map.id then return end
  state.mapId = ow.map.id
  local ok, spots = pcall(rebuild, ow)
  state.spots = (ok and spots) or {}
end

-- How many are still buried on this map, for the probe and for anyone asking.
function HiddenItems.remaining()
  local Game = game()
  local taken = (Game and Game.save and Game.save.hiddenTaken) or {}
  local n = 0
  for _, s in ipairs(state.spots) do
    if not taken[s.key] then n = n + 1 end
  end
  return n, #state.spots
end

-- ------- the draw
--
-- Inside the voxel overlay pass (main.lua's drawWorld), through the same
-- project function the ambient life and the weather anchor through. Culled to
-- REACH cells of the player rather than drawn map-wide: a glint across a cave
-- you cannot see the floor of is a draw call spent on nothing.
function HiddenItems.draw(project, scale)
  if not HiddenItems.enabled() then return end
  if #state.spots == 0 then return end
  local Game = game()
  local ow = Game and Game.overworld
  local p = ow and ow.player
  if not p then return end
  local taken = (Game.save and Game.save.hiddenTaken) or {}

  local g = love.graphics
  local prevBlend, prevAlpha = g.getBlendMode()
  local now = (love.timer and love.timer.getTime()) or 0
  local c = HiddenItems.COLOR

  for _, s in ipairs(state.spots) do
    -- taken re-checked per frame, not per map: walking over one puts its
    -- light out on the very next frame with nothing having to announce it
    if not taken[s.key]
       and math.abs(s.cx - p.cellX) <= HiddenItems.REACH
       and math.abs(s.cy - p.cellY) <= HiddenItems.REACH then
      -- the cell's middle, a few pixels off the floor
      local wx = s.cx * 16 + 8
      local wz = s.cy * 16 + 8
      local k = ((now / HiddenItems.PERIOD) + s.seed) % 1
      -- a pulse that spends most of its time LOW: a glint that was lit half
      -- the time would read as a lamp, and what is wanted is a catch of
      -- light you notice out of the corner of your eye
      local lit = math.max(0, math.sin(k * 6.2831)) ^ 3
      if lit > 0.02 then
        local sx, sy, ps = project(wx, HiddenItems.HEIGHT + lit * 2, wz)
        if sx then
          local u = math.max(1, scale * (ps or 1))
          g.setBlendMode("add")
          -- the soft bloom, then the hard core: two flat rectangles, which
          -- is what a sparkle is when everything else on screen is voxels
          g.setColor(c[1], c[2], c[3], 0.16 * lit)
          g.rectangle("fill", sx - u * 2.2, sy - u * 2.2, u * 4.4, u * 4.4)
          g.setColor(c[1], c[2], c[3], 0.85 * lit)
          g.rectangle("fill", sx - u * 0.5, sy - u * 0.5, u, u)
          -- and the four points of the star, so it reads as a glint rather
          -- than as a dot somebody left on the floor
          local arm = u * 1.6 * lit
          local t = math.max(1, u * 0.35)
          g.rectangle("fill", sx - arm, sy - t * 0.5, arm * 2, t)
          g.rectangle("fill", sx - t * 0.5, sy - arm, t, arm * 2)
        end
      end
    end
  end

  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  g.setColor(1, 1, 1, 1)
end

return HiddenItems
