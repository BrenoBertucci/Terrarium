-- What the rod does to the water.
--
-- The Game Boy drew fishing as a pose and one rod sprite: nothing at the
-- other end of the line, because there was no line, and nothing in the water,
-- because the water was a tile. The engine draws exactly that, faithfully,
-- and in this diorama it reads as a man pointing a stick at a lake.
--
-- This puts the rest of it there. A float leaves the rod tip on the cast,
-- arcs out and lands with a plop, and rides the water -- the swell and the
-- rings both (Water.surfaceAt carries lib/Ripples.lua) -- bobbing a slow train
-- of rings off itself while it waits. A bite is the engine's own shake
-- (player.fishShakeDy, one toggle per bob of the sprite): every one of them
-- jerks the float under and throws a ring. The hook is the engine's "!"
-- bubble: the float is dragged down in a burst of white and the battle comes
-- in over it. No bite and the verdict reels it back to the rod.
--
-- Everything is READ off the engine's fishing state (OverworldState:
-- goFishing / tickFishAnim / fishVerdict, src/world/OverworldController.lua):
--   ow.fishing            set on the cast frame, cleared by the verdict
--   player.fishShakeDy    0/1 while the bite shakes, nil otherwise
--   ow.emote.bubble       the "!" -- the hook
-- Nothing here changes when a fish bites or what it is; the roll, the text
-- and the battle are the engine's, untouched.
--
-- The float and the line are 2D draws through the same projection the
-- engine's own rod sprite goes through (main.lua's overlay), so the three of
-- them stay attached whatever the camera does.

local V = ...
local Ripples = V.require("Ripples")
local StepFX = V.require("StepFX")
local Water = V.require("Water")
local WaterBody = V.require("WaterBody")

local FishFX = {}

FishFX.REACH = 30          -- world px from the player's centre to the float,
                           -- at most: it lands a little way INTO the first
                           -- water ahead, never past it onto the far bank
FishFX.INTO = 8            -- world px past the water's edge
FishFX.TIP = 11            -- world px out from the centre, the rod's tip
FishFX.TIP_Y = 9           -- ...and how high it is held
FishFX.CAST_TIME = 0.42    -- s in the air
FishFX.CAST_ARC = 14       -- world px the float rises over the cast
FishFX.REEL_TIME = 0.30
FishFX.SAG = 3.5           -- world px the line hangs at its middle
FishFX.FLOAT_R = 1.4       -- world px, the float's radius
FishFX.BOB_HZ = 0.55       -- the float's own slow bob, and its rings
FishFX.RING_LAND = -2.4    -- field units: the plop
FishFX.RING_BITE = -2.0    -- each jerk of a bite
FishFX.RING_HOOK = -4.5    -- the strike
FishFX.RING_BOB = 0.45

-- for the probe
FishFX.casts = 0
FishFX.bites = 0
FishFX.hooks = 0
FishFX.reels = 0
FishFX.lastError = nil

local FACE = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local s = nil               -- the float, or nil when no line is out

local function game() return require("src.core.Game") end

local function surface(x, z)
  local ok, y = pcall(Water.surfaceAt, x, z)
  return (ok and tonumber(y)) or -2
end

local function tip(p, f)
  return (p.px or 0) + 8 + f[1] * FishFX.TIP, (p.py or 0) + 8 + f[2] * FishFX.TIP
end

-- How far ahead the float lands: walk out along the facing until the first
-- water (the engine let the rod out because the cell ahead is shore or
-- water, but a one-cell channel has a bank right behind it), then INTO it.
local function landing(cx, cz, f)
  for d = 8, FishFX.REACH, 2 do
    if WaterBody.isWaterAt(cx + f[1] * d, cz + f[2] * d) then
      return math.min(d + FishFX.INTO, FishFX.REACH)
    end
  end
  return FishFX.REACH
end

local function begin(ow, p)
  local f = FACE[(ow.fishing and ow.fishing.facing) or p.facing] or FACE.down
  local cx, cz = (p.px or 0) + 8, (p.py or 0) + 8
  local d = landing(cx, cz, f)
  s = { phase = "fly", t = 0, f = f,
        x = cx + f[1] * d, z = cz + f[2] * d,
        dip = 0, bitten = false, shake = nil }
  FishFX.casts = FishFX.casts + 1
end

local function updateBody(dt, voxelOn)
  local Game = game()
  local ow = Game and Game.overworld
  local p = ow and ow.player
  if not (voxelOn and p) then s = nil return end
  local fishing = ow.fishing
  if fishing and (not s or s.phase == "gone" or s.phase == "reel") then
    begin(ow, p)
  end
  if not s then return end
  s.t = s.t + dt

  if s.phase == "fly" then
    if s.t >= FishFX.CAST_TIME then
      s.phase, s.t = "float", 0
      pcall(Ripples.poke, s.x, s.z, FishFX.RING_LAND, 5, 0.5)
      pcall(StepFX.splashAt, s.x, s.z, 0.3)
    end
  elseif s.phase == "float" then
    -- a bite: the engine bobs the player sprite, one toggle a jerk
    local dy = p.fishShakeDy
    if dy == 1 and s.shake ~= 1 then
      s.dip = 2.6
      s.bitten = true
      pcall(Ripples.poke, s.x, s.z, FishFX.RING_BITE, 4, 0.35)
      FishFX.bites = FishFX.bites + 1
    end
    s.shake = dy
    -- the hook: the "!" over the player once the shaking has been a bite
    local em = ow.emote
    if s.bitten and em and em.bubble and em.npc == p then
      s.phase, s.t = "strike", 0
      pcall(Ripples.poke, s.x, s.z, FishFX.RING_HOOK, 8, 1.0)
      pcall(StepFX.splashAt, s.x, s.z, 1.0)
      FishFX.hooks = FishFX.hooks + 1
    else
      pcall(Ripples.emit, s.x, s.z, FishFX.RING_BOB, FishFX.BOB_HZ, 0.6, "fish-float")
    end
    -- the verdict came with no bite: reel it in
    if not fishing and s.phase == "float" then
      s.phase, s.t = "reel", 0
      pcall(Ripples.poke, s.x, s.z, -1.0, 3, 0.2)
      FishFX.reels = FishFX.reels + 1
    end
  elseif s.phase == "strike" then
    -- dragged under; it stays under until the battle takes the screen
    if not fishing then s.phase = "gone" end
  elseif s.phase == "reel" then
    if s.t >= FishFX.REEL_TIME then s = nil return end
  end
  -- the jerk relaxes on a quick spring
  s.dip = s.dip * math.exp(-dt * 7)
end

function FishFX.update(dt, voxelOn)
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
  local ok, err = pcall(updateBody, dt, voxelOn)
  if not ok then FishFX.lastError = tostring(err); s = nil end
end

-- Where the float is now, world XZ and height (nil when there is none).
function FishFX.float()
  if not s or s.phase == "gone" then return nil end
  local Game = game()
  local p = Game and Game.overworld and Game.overworld.player
  if not p then return nil end
  local tx, tz = tip(p, s.f)
  if s.phase == "fly" or s.phase == "reel" then
    local k = math.min(1, s.t / ((s.phase == "fly") and FishFX.CAST_TIME or FishFX.REEL_TIME))
    if s.phase == "reel" then k = 1 - k end
    local x = tx + (s.x - tx) * k
    local z = tz + (s.z - tz) * k
    local y0 = FishFX.TIP_Y
    local y1 = surface(s.x, s.z) + 0.6
    local y = y0 + (y1 - y0) * k + FishFX.CAST_ARC * 4 * k * (1 - k)
    return x, y, z, s.phase
  end
  local bob = 0.35 * math.sin(s.t * FishFX.BOB_HZ * 2 * math.pi)
  local under = (s.phase == "strike") and math.min(1, s.t * 6) * 3 or 0
  return s.x, surface(s.x, s.z) + 0.6 + bob - s.dip - under, s.z, s.phase
end

function FishFX.draw(project, scale)
  local x, y, z, phase = FishFX.float()
  if not x then return end
  local Game = game()
  local p = Game and Game.overworld and Game.overworld.player
  if not p then return end
  local tx, tz = tip(p, s.f)
  local ax, ay = project(tx, FishFX.TIP_Y, tz)
  local bx, by, bs = project(x, y, z)
  if not (ax and bx) then return end
  local mx, my = project((tx + x) * 0.5, (FishFX.TIP_Y + y) * 0.5 - FishFX.SAG, (tz + z) * 0.5)
  local u = math.max(1, (scale or 1) * (bs or 1))
  local g = love.graphics
  local lw = g.getLineWidth()
  g.setLineWidth(math.max(1, u * 0.35))
  g.setColor(0.95, 0.97, 1.0, 0.8)
  if mx then g.line(ax, ay, mx, my, bx, by) else g.line(ax, ay, bx, by) end
  g.setLineWidth(lw)
  if phase == "strike" and s.t > 0.2 then return end   -- under
  local r = math.max(1.5, FishFX.FLOAT_R * u)
  -- a float is two colours and an outline, which is all a sprite this size
  -- ever is
  g.setColor(0.95, 0.94, 0.90, 1)
  g.circle("fill", bx, by, r)
  g.setColor(0.86, 0.16, 0.14, 1)
  g.arc("fill", bx, by, r, math.pi, 2 * math.pi)
  g.setColor(0.08, 0.08, 0.10, 0.9)
  g.circle("line", bx, by, r)
  g.setColor(1, 1, 1, 1)
end

-- for the probe
function FishFX.state()
  return s and s.phase or nil
end

return FishFX
