-- Rain on the people in it.
--
-- This file answers HOW MUCH rain is reaching each figure, 0..1: it climbs
-- over a couple of seconds in the open and is gone a few seconds after the
-- rain stops or the figure steps out of it. Out of it: under a tree's
-- crown (GrassWear.canopyAt), or standing in a doorway the Shelter row
-- walked them to.
--
-- ------- and what that number DRAWS, which changed
--
-- It used to drive rivulets painted down the sprite's own card by the
-- scene shader (Voxel3D's coat block: a few sheet columns at a time, a
-- bright bead with a tail sliding down the frame, on the drawing's own
-- opaque texels). That read as the DRAWING being wet rather than the
-- person -- water crawling across a face that is a picture -- and it was
-- reported as exactly that: unnatural, and too big. So the painting is
-- OFF (PAINT below keeps the old look one flag away), and the number
-- drives DROPS instead: small drips let go from the top of the figure --
-- the hat brim, the shoulders -- that fall past the card, in front of it,
-- and burst at the feet. Weather's own drip mote, at half size
-- (Weather.figureDrip), so a drop off a person and a drop off an eave
-- fall and land through the same code.

local V = ...

local Weather = V.require("Weather")

local Map = require("src.world.Map")

local RainOnFX = {}

RainOnFX.SOAK = 2.0            -- seconds of full rain to full run-off
RainOnFX.DRY = 6.0             -- seconds for it to stop once the rain does
RainOnFX.CANOPY_DRY = 0.45     -- crown cover over a cell that keeps it dry

-- Paint the rivulets on the sprite as well? The old look; off.
RainOnFX.PAINT = false
-- Drops a second off a fully soaked figure in full rain. A figure is a
-- card sixteen wide; three a second is a hat brim letting go, not a
-- gutter.
RainOnFX.DRIP_RATE = 3.2
-- World px above the feet a drop lets go, and how far in FRONT of the
-- card's centre line it falls (toward the camera, +z) -- past the figure,
-- never through it.
RainOnFX.DRIP_TOP = 15
RainOnFX.DRIP_FRONT = 10
RainOnFX.DRIP_SIZE = 0.5

-- how many drops figures have shed this session, for the probe
RainOnFX.drips = 0

-- per figure: the fractional drop owed. Weak keys, like `wet`.
local owed = setmetatable({}, { __mode = "k" })

-- per figure: how much rain is running down it. Weak keys.
local wet = setmetatable({}, { __mode = "k" })

RainOnFX.lastGate = "never ran"
RainOnFX.lastError = nil
RainOnFX.errorCount = 0

local function game()
  return require("src.core.Game")
end

-- How much rain is running down this figure, 0..1. Read by VoxelScene for
-- each figure's draw.
function RainOnFX.wetOf(ent)
  return (ent and wet[ent]) or 0
end

-- Probe seam.
function RainOnFX.setWet(ent, k)
  if ent then wet[ent] = tonumber(k) or 0 end
end

-- How much of the rivulet painting the scene shader should draw on this
-- figure: the wetness if PAINT is on, nothing otherwise. What VoxelScene
-- hands the shader.
function RainOnFX.paintOf(ent)
  if not RainOnFX.PAINT then return 0 end
  return RainOnFX.wetOf(ent)
end

local function shed(e, dt, w, power)
  if not (e.px and e.py) then return end
  local due = (owed[e] or love.math.random())
              + dt * RainOnFX.DRIP_RATE * w * power
  while due >= 1 do
    due = due - 1
    local x = e.px + 3 + love.math.random() * 10
    local z = e.py + RainOnFX.DRIP_FRONT + love.math.random() * 4
    local top = RainOnFX.DRIP_TOP + love.math.random() * 3
    local ok, made = pcall(Weather.figureDrip, x, z, top, RainOnFX.DRIP_SIZE)
    if ok and made then RainOnFX.drips = RainOnFX.drips + 1 end
  end
  owed[e] = due
end

-- Is the sky open over this figure? Not under a crown, not in a doorway.
local function exposed(e)
  local okG, GW = pcall(V.require, "GrassWear")
  if okG and GW and GW.canopyAt then
    local okc, c = pcall(GW.canopyAt, e.cellX or 0, e.cellY or 0)
    if okc and tonumber(c) and c >= RainOnFX.CANOPY_DRY then return false end
  end
  local okS, Shelter = pcall(V.require, "Shelter")
  if okS and Shelter and Shelter.isHeld then
    local okh, held = pcall(Shelter.isHeld, e)
    if okh and held then return false end
  end
  return true
end

local function figure(e, dt, raining, power)
  if not e then return end
  local w = wet[e] or 0
  local open = raining and exposed(e)
  if open then
    w = w + power * dt / RainOnFX.SOAK
    if w > 1 then w = 1 end
  else
    w = w - dt / RainOnFX.DRY
    if w < 0 then w = 0 end
  end
  if w > 0 then wet[e] = w else wet[e] = nil end
  -- and the drops: while it rains on them, and for the few seconds after
  -- that they are still wet (a coat keeps dripping after the sky stops)
  if w > 0.05 and RainOnFX.DRIP_RATE > 0 then
    shed(e, dt, w, open and power or 0.35)
  end
end

local function updateBody(dt, voxelOn)
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
  local Game = game()
  local ow = Game and Game.overworld
  local live = voxelOn and ow and ow.map and ow.player
               and Map.isOutdoor(ow.map.def)
               and Game.stack and Game.stack:top() == ow
               and not ow.transitioning
  if not live then
    RainOnFX.lastGate = "not live"
    return
  end
  local okV, kind, power = pcall(Weather.visible)
  local raining = okV and kind == "rain"
  power = (okV and tonumber(power)) or 0
  RainOnFX.lastGate = raining and "raining" or "dry"
  local p = ow.player
  figure(p, dt, raining, power)
  local npcs = ow.npcs
  if npcs then
    for i = 1, #npcs do
      local e = npcs[i]
      if e ~= p then figure(e, dt, raining, power) end
    end
  end
end

function RainOnFX.update(dt, voxelOn)
  local ok, err = pcall(updateBody, dt, voxelOn)
  if ok then return end
  RainOnFX.errorCount = RainOnFX.errorCount + 1
  RainOnFX.lastError = tostring(err)
end

return RainOnFX
