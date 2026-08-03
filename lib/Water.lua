-- Voxel world mode: the water surface.
--
-- Water in this mode has been a flat quad with a scrolling texture: the
-- tileset's own animated tile, recessed two world pixels so the shoreline
-- shows a lip. That is the 2D game's water standing on its side -- the
-- picture moves and the surface does not.
--
-- Out here the surface is geometry, so it can move for real. Two things
-- follow from that, and neither is available to a texture:
--
--   SWELL     the water plane rises and falls. Because the displacement
--             is a function of world XZ alone, two quads meeting at a
--             shared corner are displaced by the same amount and the
--             surface stays watertight -- no seams, no gaps, and no need
--             for the mesh to be indexed.
--
--   SPARKLE   a swell has SLOPE, and slope can be pointed at the sun. The
--             wave's own analytic gradient gives a normal for free (it is
--             the derivative of the height, which is two cosines), and
--             where that normal turns into the light the crest catches
--             it. That is a real reflection off a real surface, not a
--             pattern painted onto a flat one.
--
-- ------- how the shader knows which geometry is water
--
-- Without asking, and without a new vertex attribute. Water is the only
-- class in the shape profile that goes NEGATIVE -- it is recessed to -2 to
-- cut the shoreline lip, and everything else in the world stands at zero or
-- above (TileShape's class table; the profile says so in as many words).
-- So a vertex below -1 is water and nothing else is, which costs one
-- compare in the vertex shader and no memory at all.
--
-- The lip's own bottom edge sits at -2 as well, and therefore moves with
-- the water. That is not a leak, it is the right answer: the lip is where
-- the ground meets the water, and it should stay met. What it looks like
-- is the shore stretching and closing as the level breathes against it.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local Water = {}

-- Rise and fall at the crest, in world pixels. The water sits two pixels
-- below the shore, so anything much past one lifts the surface over its own
-- lip and the shoreline stops reading as a bank.
Water.setting = ModSetting.new("swell", "WATER",
                               { 0.8, 1.4, 0 },
                               { "CALM", "SWELL", "FLAT" })

-- Two wave trains, crossing. One alone is a corrugated roof: every crest
-- parallel, every trough the same depth. Two at an angle to each other
-- interfere, and interference is what makes a water surface look like it
-- has no pattern at all.
--
-- The vectors are phase gained per world pixel, so their magnitude is the
-- wavelength: about 75 and 100 world pixels here, which is four to six map
-- cells -- long enough to read as a swell rather than as ripples, and short
-- enough that a pond has more than one crest in it.
Water.WAVE_A = { 0.070, 0.038 }
Water.WAVE_B = { -0.031, 0.058 }

-- Radians per second on the first train. The second runs at 0.7 of it and
-- the other way, which is what stops the pair from ever repeating.
Water.RATE = 0.9

-- How far toward white a crest lifts when it catches the sun.
Water.SPARKLE = 0.55

-- The window of slope that sparkles, as an offset from the flat surface's
-- own alignment with the sun. Narrow on purpose: a wide window is a sheen
-- over the whole pond, and what is wanted is the few crests actually
-- turned into the light.
Water.GLINT_LO = 0.020
Water.GLINT_HI = 0.075

-- ------- rain on the water
--
-- How WET the surface is, 0..1, written from outside this file (lib/Weather.lua
-- sets it every tick and zeroes it when nothing is falling). Pushed in rather
-- than read out for the same reason DayNight.overcast is: Weather asks this
-- file what the water is doing, so a require back the other way would be a
-- cycle.
--
-- Rain does two things to a pond and this models both. It ROUGHENS the
-- surface, which lifts the swell a little -- the wind that brings the rain is
-- the same wind that raises the chop. And it KILLS THE GLINT: a toon glint is
-- one big smooth crest turned at the sun, and rain breaks every crest into a
-- thousand small ones pointing everywhere, so the one clean highlight becomes
-- a dull scatter. Killed rather than dimmed on purpose -- a half-strength
-- glint under a rain front reads as a bug, and there is no sun up there to
-- make one anyway (see DayNight.overcast).
Water.wet = 0

-- how much of the swell the rain's own chop adds at full downpour
Water.CHOP = 0.5

local function wetness()
  local n = tonumber(Water.wet) or 0
  if n < 0 then return 0 end
  return n > 1 and 1 or n
end

function Water.swell()
  local ok, v = pcall(Water.setting.get, Water.setting)
  local n = (ok and tonumber(v)) or 0
  if n < 0 then n = 0 end
  if n > 4 then n = 4 end
  -- FLAT stays flat: the row is the player saying they do not want the water
  -- to move, and weather is not an argument against that
  if n > 0 then n = n + Water.CHOP * wetness() end
  return n
end

-- The sparkle the scene shader should use THIS frame -- the row's own strength
-- with the rain taken out of it.
function Water.sparkleNow()
  return Water.SPARKLE * (1 - wetness())
end

-- How hard it is raining ON the water, 0..1, clamped -- the same number
-- `swell` and `sparkleNow` already read, published for the one caller that
-- wants the RAIN rather than the swell: the screen-space pass, which ripples
-- a PUDDLE off this and must go on doing it when the WATER row is at FLAT
-- (see RayFX's rainNormal). Read through here rather than off `Water.wet`
-- directly so a caller cannot be handed the unclamped field Weather writes.
function Water.rain()
  return wetness()
end

-- Absolute time rather than an accumulator: this is read once by the scene
-- and again by a staged battle, and an accumulator advanced per read would
-- run at whatever rate it happened to be called at.
function Water.phase()
  if love and love.timer and love.timer.getTime then
    return (love.timer.getTime() * Water.RATE) % (math.pi * 2048)
  end
  return 0
end

return Water
