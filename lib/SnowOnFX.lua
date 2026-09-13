-- Snow on the people in it.
--
-- The sibling of lib/RainOnFX.lua, and it exists for the same reason that
-- one does: what the weather does to a figure had been drawn INTO the
-- figure, and a 16x16 overworld sprite is a drawing.
--
-- ------- what changed
--
-- The snow on everybody used to be a number handed to the scene shader,
-- which mixed white into the card's own texels along the drawing's top
-- edges -- a texel whose upstairs neighbour is transparent, plus the
-- frame's own top row, rationed by a hash of the sheet texel (Voxel3D's
-- coat block). That is the same construction the rain's rivulets used and
-- it reads the same way: the PICTURE goes white rather than the person.
-- It eats the ink outline the sprite is drawn with, it bleaches a hat and
-- a face instead of covering them, and on anything that is not shaped like
-- a person -- Pikachu, a roamer -- it lands wherever the art happens to
-- have a top edge, which is nowhere in particular.
--
-- So the painting is OFF (PAINT below keeps the old look one flag away)
-- and the number drives two things that are not the sprite:
--
--   the CAP   one small quad per column of the frame, standing on that
--             column's topmost opaque row and rising into the air above
--             it -- so it traces a hat, a pair of shoulders, a pair of
--             ears, and never touches a texel of the drawing.
--             lib/SnowField.lua's `cap`, drawn by VoxelScene beside the
--             collar that already stands around everybody's shins.
--
--   the SHED  clumps letting go of that cap and tumbling down in front of
--             the card, landing at the feet. Weather's own flake mote
--             (Weather.figureFlake) at a heavier fall, so snow off a
--             shoulder settles and heaps into the cover through the same
--             code snow out of the sky does.
--
-- ------- and what it knows that the old number did not
--
-- The coat was ONE number for the whole map: everybody wore the same snow,
-- including the ones standing under a tree's crown and the ones the
-- Shelter row walked into a doorway. This is per figure and asks the same
-- two questions the rain asks -- is there a crown over this cell, is this
-- one being held in a door -- so the snow stops where the sky does.
--
-- An entity this module never sees (a ghost standing on a neighbour map)
-- falls back to the ambient number, which is what it wore before.

local V = ...

local Weather = V.require("Weather")
local GroundFX = V.require("GroundFX")

local Map = require("src.world.Map")

local SnowOnFX = {}

SnowOnFX.SETTLE = 6.0          -- seconds of full fall to a full cap
SnowOnFX.SLIDE = 24.0          -- seconds for it to go once the fall stops
SnowOnFX.CANOPY_DRY = 0.45     -- crown cover over a cell that keeps it bare

-- Paint the white into the sprite's own texels as well? The old look; off.
SnowOnFX.PAINT = false

-- Clumps a second off a fully capped figure while it is coming down. Far
-- rarer than the rain's drips: water runs off continuously and snow lets
-- go in lumps, and a figure shedding three a second reads as steaming.
SnowOnFX.SHED_RATE = 0.55
-- ...and the burst when a load lands on somebody (a shaken branch, see
-- SnowField.dumpOn): that much snow does not sit still.
SnowOnFX.SHED_DUMP = 2.6
-- How far in FRONT of the card's centre line a clump falls (toward the
-- camera, +z) -- past the figure, never through it -- and how big it is.
SnowOnFX.SHED_FRONT = 9
SnowOnFX.SHED_SIZE = 1.15
-- Where it lets go, when the sheet will not say (world px above the feet).
SnowOnFX.SHED_TOP = 15

-- how many clumps figures have shed this session, for the probe
SnowOnFX.sheds = 0

-- per figure: how much snow is lying on it, and the fractional clump owed.
-- Weak keys, like the rain's.
local cap = setmetatable({}, { __mode = "k" })
local owed = setmetatable({}, { __mode = "k" })

-- the map-wide number, for anything the update never walked
local ambient = 0

SnowOnFX.lastGate = "never ran"
SnowOnFX.lastError = nil
SnowOnFX.errorCount = 0

local function game()
  return require("src.core.Game")
end

-- How much snow is lying on this figure, 0..1: the fall's own, or the load
-- a branch dropped on this one in particular, whichever is more. Read by
-- VoxelScene for each figure's draw.
function SnowOnFX.capOf(ent)
  local k = ent and cap[ent]
  if k == nil then k = ambient end
  local okS, SnowField = pcall(V.require, "SnowField")
  if okS and SnowField and SnowField.coatOf and ent then
    local okc, d = pcall(SnowField.coatOf, ent)
    if okc and tonumber(d) and d > k then k = d end
  end
  return k or 0
end

-- ------- is a SOLID standing there, or a card?
--
-- A 3D character mod (Porygonal, through compat/porygonal) replaces the
-- sprite card with a real body, and everything this file draws on a figure
-- is built to a card: the cap is a ridge on the drawing's own top edges and
-- the collar is a card standing in front of the legs. On a body that is no
-- longer flat they hang at the outline of something that is not there, so
-- the bodies it replaced get neither. A slab lying on the model's crown was
-- built for this and rejected on sight; SnowField says why.
--
-- It replaces CHARACTERS only. The wild Pokemon walking the map are
-- Terrarium's own and it has no model for them, so they are still cards and
-- still get exactly what a card gets -- which is what VoxelScene's
-- `asACard` is asking.
--
-- Asked of the SEAM, not of a mod id, so it is true for whatever takes it.
-- Terrarium assigns SpriteBillboards.shadowQuad = SpriteBillboards.mesh --
-- one function under two names, deliberately. A renderer adapter has to
-- wrap them separately, because the two passes are told apart by which one
-- asked, so two distinct values there IS a solid body standing where the
-- card would be.
local billboards = nil
function SnowOnFX.solid()
  if billboards == nil then
    local ok, SB = pcall(V.require, "SpriteBillboards")
    billboards = (ok and SB) or false
  end
  if not billboards then return false end
  return billboards.mesh ~= billboards.shadowQuad
end

-- Probe seam.
function SnowOnFX.setCap(ent, k)
  if ent then cap[ent] = math.max(0, math.min(1, tonumber(k) or 0)) end
end

-- The map-wide fall, for the probe and for anything unseen.
function SnowOnFX.ambient()
  return ambient
end

-- How much of the coat painting the scene shader should draw on this
-- figure: the cap if PAINT is on, nothing otherwise. What VoxelScene hands
-- the shader, and with it at zero the whole coat block -- two extra texture
-- reads per fragment of every character -- is skipped.
function SnowOnFX.paintOf(ent)
  if not SnowOnFX.PAINT then return 0 end
  return SnowOnFX.capOf(ent)
end

-- World px above the feet the snow on this figure is sitting at: the top
-- of its own highest column, so a clump leaves Pikachu's ears at Pikachu's
-- height rather than at a person's.
local function topOf(e)
  local def = e and e.sprite and e.sprite.def
  if not def then return SnowOnFX.SHED_TOP end
  local okS, SnowField = pcall(V.require, "SnowField")
  if not (okS and SnowField and SnowField.capTop) then return SnowOnFX.SHED_TOP end
  local okt, top = pcall(SnowField.capTop, def, 0)
  return (okt and tonumber(top)) or SnowOnFX.SHED_TOP
end

local function shed(e, dt, k, rate)
  if not (e.px and e.py) then return end
  local due = (owed[e] or love.math.random()) + dt * rate * k
  while due >= 1 do
    due = due - 1
    local x = e.px + 3 + love.math.random() * 10
    local z = e.py + SnowOnFX.SHED_FRONT + love.math.random() * 4
    local top = topOf(e) - 1 + love.math.random() * 2
    local ok, made = pcall(Weather.figureFlake, x, z, top, SnowOnFX.SHED_SIZE)
    if ok and made then SnowOnFX.sheds = SnowOnFX.sheds + 1 end
  end
  owed[e] = due
end

-- Is the sky open over this figure? Not under a crown, not in a doorway.
-- The same two questions lib/RainOnFX.lua asks, and for the same reason.
local function exposed(e)
  local okG, GW = pcall(V.require, "GrassWear")
  if okG and GW and GW.canopyAt then
    local okc, c = pcall(GW.canopyAt, e.cellX or 0, e.cellY or 0)
    if okc and tonumber(c) and c >= SnowOnFX.CANOPY_DRY then return false end
  end
  local okS, Shelter = pcall(V.require, "Shelter")
  if okS and Shelter and Shelter.isHeld then
    local okh, held = pcall(Shelter.isHeld, e)
    if okh and held then return false end
  end
  return true
end

local function figure(e, dt, falling, power)
  if not e then return end
  local k = cap[e] or 0
  local open = falling and exposed(e)
  if open then
    k = k + power * dt / SnowOnFX.SETTLE
    if k > 1 then k = 1 end
  else
    k = k - dt / SnowOnFX.SLIDE
    if k < 0 then k = 0 end
  end
  cap[e] = k
  -- and the clumps: while there is snow on them at all. A branch's load
  -- (SnowField.coatOf) sheds far harder than the sky's slow build -- that
  -- much snow arriving at once does not sit there.
  local rate = SnowOnFX.SHED_RATE
  local load = 0
  local okS, SnowField = pcall(V.require, "SnowField")
  if okS and SnowField and SnowField.coatOf then
    local okc, d = pcall(SnowField.coatOf, e)
    load = (okc and tonumber(d)) or 0
  end
  if load > k then
    k = load
    rate = SnowOnFX.SHED_DUMP
  end
  -- and nothing comes off a figure that has none ON it. With a 3D character
  -- mod driving the pass, no cap is drawn on the bodies it replaced (see
  -- VoxelScene), so a clump letting go of one of those would be snow
  -- appearing out of the air above somebody. The wild Pokemon are not
  -- replaced -- they are still cards, they still wear a cap, and they still
  -- shed it.
  local bare = SnowOnFX.solid() and not e.roamer
  if k > 0.08 and rate > 0 and not bare then shed(e, dt, k, rate) end
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
    SnowOnFX.lastGate = "not live"
    -- indoors and in a transition the fall is not reaching anybody; let
    -- the map-wide number fade rather than freezing at whatever the last
    -- outdoor frame left, or stepping outside restores an old snowfall
    ambient = math.max(0, ambient - dt / SnowOnFX.SLIDE)
    return
  end
  local okV, kind, power = pcall(Weather.visible)
  local falling = okV and kind == "snow" and GroundFX.enabled()
  power = (okV and tonumber(power)) or 0
  SnowOnFX.lastGate = falling and "snowing" or "clear"

  local target = falling and math.min(1, power * 1.25) or 0
  if target > ambient then
    ambient = ambient + (target - ambient) * math.min(1, dt / SnowOnFX.SETTLE)
  else
    ambient = ambient - dt / SnowOnFX.SLIDE
    if ambient < target then ambient = target end
  end
  if ambient < 0 then ambient = 0 end

  local p = ow.player
  figure(p, dt, falling, power)
  local npcs = ow.npcs
  if npcs then
    for i = 1, #npcs do
      local e = npcs[i]
      if e ~= p then figure(e, dt, falling, power) end
    end
  end
end

function SnowOnFX.update(dt, voxelOn)
  local ok, err = pcall(updateBody, dt, voxelOn)
  if ok then return end
  SnowOnFX.errorCount = SnowOnFX.errorCount + 1
  SnowOnFX.lastError = tostring(err)
end

return SnowOnFX
