-- Voxel world mode: two lights instead of one.
--
-- The scene shader has multiplied every surface by a single number for the
-- sun and a single tint for the hour:
--
--     rgb = art * faceShade * sunlight() * dayTint
--
-- which makes a shadow a DIMMER. Everything in shadow is the same colour it
-- was, only less of it -- and that is the one thing outdoor light never
-- does. A shadow is not an absence of light, it is a place lit by a
-- different light: the sky. The sun is warm and comes from one direction;
-- the sky is cool and comes from everywhere. What tells the eye a scene is
-- outdoors, more than the shadows' shape, is that they are BLUE.
--
-- So the one term is split in two:
--
--     light = sky + sun * sunlight()
--     rgb   = art * faceShade * light
--
-- In full sun a surface gets both and looks exactly as bright as it did.
-- In shadow it gets the sky alone -- dimmer, and cool. Nothing else in the
-- pipeline changes, and the shadow map, the day tint and the baked face
-- shading all keep doing precisely what they did.
--
-- ------- why the sum is arranged the way it is
--
-- The split is taken from SHADOW_ALPHA, which is already the mod's answer
-- to "how far into shadow does a shadowed surface go". At 0.40 that means
-- forty per cent of the light is directional and sixty is fill, so:
--
--     sun = tint * 0.40 * warm
--     sky = tint * 0.60 * cool
--
-- and their sum is the tint the shader used to multiply by, give or take
-- the warm/cool biases -- which are inverse of each other, so they cancel
-- in the sum and only show where the two are separated. Which is to say:
-- lit surfaces look the way they always did, and only shadows change.
-- That is the property worth having, because it means this cannot make the
-- world darker by accident.
--
-- ------- indoors
--
-- There is no sky in a cave, so there is nothing blue to fill with. The
-- caller says how much sky a map stands under (VoxelScene knows -- it is
-- the same Map.isOutdoor test the sky itself is painted on), and the
-- biases fade to neutral as that goes to zero. A gym's shadows stay grey,
-- which is what a room lit by its own ceiling looks like.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local Light = {}

Light.setting = ModSetting.new("light", "LIGHT",
                               { true, false },
                               { "SKY", "FLAT" })

-- Direct sunlight, and the sky's fill, as multipliers about 1. Deliberately
-- inverse of each other so they cancel in the sum -- see above.
Light.SUN = { 1.10, 1.02, 0.86 }
Light.SKY = { 0.84, 0.93, 1.18 }

-- How much of the difference actually gets applied. The full biases are
-- what the physics wants and rather more than a four-colour palette wants;
-- this is the dial between "outdoors" and "a blue filter".
Light.STRENGTH = 0.7

function Light.enabled()
  local ok, v = pcall(Light.setting.get, Light.setting)
  return ok and v == true
end

local function blend(bias, amount)
  return 1 + (bias - 1) * amount
end

-- The two colours the shader multiplies by, given the hour's tint, how much
-- of the light is directional (SHADOW_ALPHA) and how much sky the map
-- stands under (0 indoors, 1 outdoors).
--
-- Returns sky first because that is the one a surface always gets.
function Light.split(tint, direct, sky)
  tint = tint or { 1, 1, 1 }
  direct = math.max(0, math.min(1, direct or 0))
  sky = math.max(0, math.min(1, sky or 0))

  -- FLAT, or a frame with no shadow map at all: hand back the old
  -- behaviour exactly -- everything in the ambient term, nothing
  -- directional, no bias. The shader then computes `tint + 0 * lit`,
  -- which is the multiply it always did.
  if not Light.enabled() or direct <= 0 then
    return { tint[1], tint[2], tint[3] }, { 0, 0, 0 }
  end

  local amount = Light.STRENGTH * sky
  local fill = 1 - direct
  local out, dir = {}, {}
  for i = 1, 3 do
    out[i] = tint[i] * fill * blend(Light.SKY[i], amount)
    dir[i] = tint[i] * direct * blend(Light.SUN[i], amount)
  end
  return out, dir
end

return Light
