-- Voxel world mode: the hour's air -- ground mist the clock grows and burns off.
--
-- The day/night cycle already moved the sun, the shadows, the sky and the
-- light. What it never moved was the AIR, and the air is the half of a
-- morning that tells you it is one: before sunrise the low ground fills
-- with mist, the rising sun behind it sets it glowing, and by the middle of
-- the morning it has burnt off and noon is clear. At dusk it breathes back
-- in off the water; under the moon it lies thin and silver, and every lamp
-- and lit window stands in its own halo.
--
-- IT IS THE CRYPT'S MIST, TAKEN OUTSIDE. The scene shader has carried a
-- ground mist since the tower's crypt (two octaves of drifting value noise,
-- squared toward the floor, lit by the lamp pools it lies under). This file
-- only decides, per frame, how much of it there is and what lights it:
--
--   amount   a curve on the CLOCK, not on the palette weights -- the morning
--            and evening golden hours share a palette and must not share a
--            mist (the morning one is thick, the evening one is clear).
--   colour   the hour's own horizon band, the same colour the far haze is.
--   the sun  its bearing and colour, so the mist lying TOWARD the low sun
--            from the eye glows (forward scatter). The camera looks north
--            and the arc rises and sets in the north, so dawn and dusk put
--            the sun behind the far half of the frame -- the whole point.
--   the wake whoever walks through it parts it, and it closes back over
--            behind them in a few seconds; stand still and it settles in.
--
-- Height does the geography for free: the mist thins to nothing HEIGHT
-- world pixels up, so it pools in a recessed pond, lies on a route, and
-- leaves a raised ledge, a roof and a treetop standing clear of it.
--
-- OUTDOOR ONLY, like everything the clock touches -- plus the canopy, which
-- already takes the hour's tint through its leaves. Costs nothing at noon:
-- the shader's mist block sits behind a uniform `mist.x > 0` branch.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local DayNight = V.require("DayNight")

local Mist = {}

Mist.setting = ModSetting.new("mist", "MIST", { "on", "off" },
                              { "ON", "OFF" })
  :translate("NEVOA", { "LIGADA", "DESLIGADA" })

function Mist.enabled()
  return Mist.setting:get() == "on"
end

-- How much mist lies on the ground at each second of the clock (DayNight's
-- dial: 0 sunrise, 300 noon, 600 sunset, 900 midnight). Straight lines
-- between the keys. Zero from mid-morning through the late gold, so the
-- afternoon is exactly the clear world it always was.
Mist.CURVE = {
  { 0, 0.62 }, { 45, 0.62 },      -- sunrise: the low ground full of it
  { 120, 0.42 }, { 195, 0.12 },   -- the warm hour burns it thin
  { 270, 0 }, { 540, 0 },         -- noon through the late gold: clear air
  { 600, 0.14 },                  -- sunset: the first breath off the water
  { 705, 0.34 },                  -- civil twilight
  { 780, 0.45 }, { 1020, 0.45 },  -- the moon's hours: a thin silver layer
  { 1140, 0.56 },                 -- before dawn it thickens
  { 1200, 0.62 },
}
Mist.HEIGHT = 12      -- world px it has thinned to nothing at: knee to waist
Mist.SCALE = 72       -- world px across one bank of the drift
Mist.RAIN = 0.28      -- how much more lies after rain (DayNight.overcast)
Mist.MAX = 0.8        -- the ceiling, so a wet dawn is still a place
Mist.PERIOD = 2000    -- the drift clock wraps here: noise on a huge argument
                      -- loses its fraction on fp16, a wrap every half hour
                      -- is the cheaper artefact
-- The banks: the noise is shaped between these two edges, so it is dense
-- where the field is high and clear between -- a soft wash over a lit
-- street reads as the street getting paler, not as mist lying on it.
Mist.BANK_LO, Mist.BANK_HI = 0.40, 0.70   -- 0.30/0.72 at 0.78 turned a
                                           -- harbour at dawn into snow
Mist.BREATHE = 0.021  -- rad/s the field morphs at (a full breath ~5 min)

-- Mist is paler than what it lies on: water droplets scatter every colour
-- of the light they are in. By day, the hour's horizon band this much of
-- the way to white. Under the moon the band as it is -- already well above
-- a night street's own brightness, and any paler washes the dark out.
Mist.PALE = 0.35

-- The light the mist catches from the body behind it.
Mist.SCATTER = 0.36   -- the sun, at the horizon (fading out by SCATTER_DEG);
                      -- 0.55 blew a sunlit white plaza out to paper
Mist.SCATTER_DEG = 40
Mist.MOON = 0.22      -- the moon, which does not fade: it is always low

-- The wake.
Mist.WAKE_MAX = 8     -- the shader's array
Mist.WAKE_LIFE = 3.2  -- seconds for a parted patch to close back over
Mist.WAKE_STEP = 12   -- world px a walker moves between two marks
Mist.WAKE_GROW = 1.6  -- a mark's radius over the foot's own crush radius
Mist.WAKE_NEAR = 256  -- world px from the player a walker may part it at:
                      -- eight slots are for the screen, not the whole map

function Mist.amountAt(t)
  local c = Mist.CURVE
  t = t % DayNight.CYCLE
  for i = 2, #c do
    local a, b = c[i - 1], c[i]
    if t <= b[1] then
      local span = b[1] - a[1]
      local s = span > 0 and (t - a[1]) / span or 1
      return a[2] + (b[2] - a[2]) * s
    end
  end
  return c[#c][2]
end

-- ------- the wake
--
-- Marks dropped along each walker's path from the SAME feet list the grass
-- crush is built from (VoxelScene), so the player, the civilians and the
-- wild Pokemon all part it. Kept here rather than in the shader because it
-- has a memory: a mark is where somebody WAS.
local marks = {}      -- { x, z, radius, age }
local lastAt = {}     -- walker -> { x, z } of its last mark
local marksMap = nil

function Mist.walk(feet, dt, mapKey)
  if mapKey ~= marksMap then
    marks, lastAt, marksMap = {}, {}, mapKey
  end
  dt = tonumber(dt) or 0
  for i = #marks, 1, -1 do
    local m = marks[i]
    m[4] = m[4] + dt
    if m[4] >= Mist.WAKE_LIFE then table.remove(marks, i) end
  end
  -- feet[1] is the player (VoxelScene builds the list player-first)
  local px = feet and feet[1] and tonumber(feet[1][1])
  local pz = feet and feet[1] and tonumber(feet[1][2])
  local near2 = Mist.WAKE_NEAR * Mist.WAKE_NEAR
  for i = 1, #(feet or {}) do
    local f = feet[i]
    local x, z = tonumber(f[1]), tonumber(f[2])
    if x and z and px
       and (x - px) * (x - px) + (z - pz) * (z - pz) <= near2 then
      local who = f[8] or i
      local last = lastAt[who]
      local dx, dz = last and (x - last[1]) or 0, last and (z - last[2]) or 0
      if not last or dx * dx + dz * dz >= Mist.WAKE_STEP * Mist.WAKE_STEP then
        marks[#marks + 1] = { x, z, (tonumber(f[3]) or 12) * Mist.WAKE_GROW, 0 }
        lastAt[who] = { x, z }
      end
    end
  end
  -- ponytail: oldest marks drop first when the array is full; a crowd
  -- shortens everyone's wake rather than hiding the newest one
  while #marks > Mist.WAKE_MAX do table.remove(marks, 1) end
end

-- the marks as the shader takes them: xy, radius, how open (eased shut)
local function wake()
  local out = {}
  for i, m in ipairs(marks) do
    local s = 1 - m[4] / Mist.WAKE_LIFE
    out[i] = { m[1], m[2], m[3], s * s * (3 - 2 * s) }
  end
  return out
end

-- ------- what the frame reads

-- Everything the scene needs this frame, or nil for no outdoor mist:
-- the `mist` and `mistColor` uniforms (the crypt's own pair), plus the
-- sun's bearing/strength and its colour. The drift runs on the wall
-- timer, as the crypt's does, so a frame drawn twice is the same instant.
function Mist.frame(outdoor)
  if not (outdoor and Mist.enabled()) then return nil end
  local t = DayNight.time()
  local amount = Mist.amountAt(t)
  local wet = math.max(0, math.min(1, DayNight.overcast or 0))
  amount = math.min(Mist.MAX, amount + (amount > 0 and Mist.RAIN * wet or 0))
  if amount <= 0.001 then return nil end

  local clock = ((love.timer and love.timer.getTime
                  and love.timer.getTime()) or 0) % Mist.PERIOD

  local th, el, moon = DayNight.bodyAt(t)
  local band = DayNight.palette(t)[1]
  local pale = moon and 0 or Mist.PALE
  local color = {}
  for i = 1, 3 do
    local c = band[i] / 255
    color[i] = c + (1 - c) * pale
  end

  local strength, tone
  if moon then
    strength = el > 0 and Mist.MOON or 0
    tone = DayNight.MOON_COLORS[2]
  else
    local low = 1 - math.max(0, el) / Mist.SCATTER_DEG
    strength = (el > -2 and low > 0) and Mist.SCATTER * low or 0
    local _, glow = DayNight.glow(t)
    tone = glow or DayNight.SUN_COLORS[2]
  end
  strength = strength * (1 - wet)
  local r = math.rad(th)

  return {
    mist = { amount, Mist.HEIGHT, 1 / Mist.SCALE, clock },
    shape = { Mist.BANK_LO, Mist.BANK_HI, 1.0,
              0.5 + 0.5 * math.sin(clock * Mist.BREATHE) },
    color = color,
    sun = { math.cos(r), math.sin(r), strength, 1 },
    sunColor = { tone[1] / 255, tone[2] / 255, tone[3] / 255 },
  }
end

-- The marks as the shader takes them, for whichever mist is lying there --
-- the crypt's parts under a boot exactly as the street's does.
function Mist.wake()
  return wake()
end

return Mist
