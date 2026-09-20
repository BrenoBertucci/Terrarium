-- Voxel world mode: the shadows of the clouds.
--
-- The sky had clouds, the wind pushed them, the sun threw shadows -- and
-- the ground never once went dark because a cloud had passed over it. On
-- a real afternoon that is the most visible thing the sky does to the land:
-- soft, slow patches of shade crossing the fields downwind, the lake going
-- dull and bright again. It is also the cheapest kind of light there is to
-- add, because a cloud's shadow has no edge to speak of -- it is a wide,
-- smooth field, and a smooth field can be evaluated ONCE PER VERTEX and
-- interpolated, which is nothing at all next to the shadow map's fetches.
--
-- ------- how it is drawn
--
-- lib/Voxel3D.lua's vertex stage evaluates a sum of five sines on the
-- vertex's world XZ, offset by this file's drift, and hands the fragment a
-- 0..1 "how much sun reaches here" in the spare lane of the sun-view
-- varying (vSun.w). The fragment multiplies the SUN's share of the light
-- by it -- not the sky's: a cloud takes the sun away and leaves the sky,
-- which is exactly what the shadow map does, so cloud shade and cast
-- shadow are the same cool colour and sit together without a seam. A
-- small share of the fill goes too (cloudFill), because the hemisphere
-- over a shaded patch is a little darker than over a lit one -- and on a
-- frame with no shadow map (SHADOWS OFF), where the sun's whole share is
-- folded into the fill, that share is raised so the shade still reads.
--
-- The field is PERIODIC in world space (integer wave numbers over one
-- base period), so the drift can wrap instead of growing for ever, and the
-- vertex stage is highp on every GLES driver -- no fp16 anywhere near it.
--
-- ------- what decides the shade
--
-- Coverage follows Sky.cloudAmount(): a fair-weather sky shades a few
-- patches, a thickening deck shades most of the ground with a few bright
-- gaps, and a flat overcast (DayNight.overcast) shades NOTHING -- under a
-- stratus sheet there are no patches, the light is simply grey, and the
-- weather already made it so. The drift runs downwind at a cloud's pace,
-- slower than the sky's own deck reads (it is nearer), and faster under a
-- gale. Indoors there is no sky, so the term is sent as 1.

local V = ...
local ModSetting = V.require("ModSetting")
local Wind = V.require("Wind")
local Sky = V.require("Sky")
local DayNight = V.require("DayNight")
local Weather = V.require("Weather")

local Map = require("src.world.Map")

local CloudShade = {}

CloudShade.setting = ModSetting.new("cloudshade", "CLOUD SHADE",
                                    { "on", "off" }, { "ON", "OFF" })

CloudShade.PERIOD = 1400        -- world px the field repeats over
CloudShade.DEPTH = 0.58         -- how much of the sun a cloud takes
CloudShade.FILL = 0.16          -- and of the sky's fill, with a shadow map
CloudShade.FILL_NOMAP = 0.42    -- ...without one (the sun lives in the fill)
CloudShade.SPEED_CALM = 8       -- world px/s the shade travels, no wind
CloudShade.SPEED_WIND = 18      -- added at full Wind.amount
CloudShade.WINDOW = 0.22        -- softness of a patch's edge, in noise units

-- the drift, in world px, wrapped over PERIOD
CloudShade.offX, CloudShade.offZ = 0, 0
CloudShade.on = false
CloudShade.strength = 0
CloudShade.lo, CloudShade.hi = 0.6, 0.82

local function clamp01(v) if v < 0 then return 0 elseif v > 1 then return 1 end return v end

function CloudShade.enabled()
  local ok, v = pcall(CloudShade.setting.get, CloudShade.setting)
  return not ok or v ~= "off"
end

local function outdoors()
  local ok, Game = pcall(require, "src.core.Game")
  local ow = ok and Game and Game.overworld
  return ow and ow.map and ow.map.def and Map.isOutdoor(ow.map.def) or false
end

function CloudShade.update(dt, voxelOn)
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
  local wind = 0
  local okw, wa = pcall(Wind.amount)
  if okw then wind = clamp01(tonumber(wa) or 0) end
  local speed = CloudShade.SPEED_CALM + CloudShade.SPEED_WIND * wind
  local dir = Wind.DIR or { 1, 0 }
  local P = CloudShade.PERIOD
  CloudShade.offX = (CloudShade.offX + dir[1] * speed * dt) % P
  CloudShade.offZ = (CloudShade.offZ + dir[2] * speed * dt) % P

  local on = voxelOn and CloudShade.enabled() and outdoors()
  local amt = 0
  if on then
    local oka, a = pcall(Sky.cloudAmount)
    amt = oka and clamp01(tonumber(a) or 0) or 0
    if amt <= 0 then on = false end
  end
  CloudShade.on = on and true or false
  if not on then CloudShade.strength = 0 return end
  -- a flat overcast is one sheet, not patches: the shade fades out as the
  -- front closes in and the weather's own dimming takes over
  local overcast = clamp01(tonumber(DayNight.overcast) or 0)
  local wet = 0
  local okv, kind, power = pcall(Weather.visible)
  if okv and kind and power then wet = clamp01(tonumber(power) or 0) end
  local clear = (1 - overcast) * (1 - wet * 0.8)
  CloudShade.strength = CloudShade.DEPTH * clear
  -- coverage: the window over the noise slides down as the deck thickens
  local lo = 0.80 - 0.50 * amt
  CloudShade.lo, CloudShade.hi = lo, lo + CloudShade.WINDOW
end

-- The two packets the scene shader takes (see Voxel3D's cloudA / cloudB),
-- and the fill share for the fragment. `hasMap` is whether a shadow map
-- carries the sun this frame.
function CloudShade.uniforms(hasMap)
  local k = 2 * math.pi / CloudShade.PERIOD
  local a = { CloudShade.offX, CloudShade.offZ, k, CloudShade.strength }
  local b = { CloudShade.lo, CloudShade.hi, 0, CloudShade.on and 1 or 0 }
  return a, b, hasMap and CloudShade.FILL or CloudShade.FILL_NOMAP
end

-- The same field on the CPU, for anything that wants to know how much sun
-- reaches a world point (a probe, a future critter that seeks the shade).
-- 1 = full sun, lower = under a cloud. Mirrors the GLSL exactly.
function CloudShade.sunAt(wx, wz)
  if not CloudShade.on then return 1 end
  local k = 2 * math.pi / CloudShade.PERIOD
  local x, z = (wx - CloudShade.offX) * k, (wz - CloudShade.offZ) * k
  local n = 0.5
          + 0.28 * math.sin(x * 4.0 + 0.7) * math.sin(z * 5.0 - 1.3)
          + 0.17 * math.sin(x * 7.0 - z * 9.0 + 2.1)
          + 0.12 * math.sin(z * 11.0 - x * 6.0 + 4.4)
          + 0.08 * math.sin(x * 13.0 + z * 4.0 + 0.9)
  local t = clamp01((n - CloudShade.lo) / (CloudShade.hi - CloudShade.lo))
  t = t * t * (3 - 2 * t)
  return 1 - t * CloudShade.strength
end

return CloudShade
