-- Voxel world mode: wind.
--
-- The grass in this mode is GEOMETRY -- Structures builds a per-pixel tuft
-- template and ChunkMesher stamps it across every cell the engine calls
-- tall grass. That is why nothing done to the tileset's animation data can
-- make it move: a tile animation rewrites ART, and out here the art has
-- already been turned into shape. Rolling the atlas slot slides a texture
-- across prisms that do not themselves go anywhere.
--
-- So move the shape. The scene's vertex shader displaces each grass vertex
-- along the wind, by an amount that grows with how high up the tuft it
-- sits -- so the base stays planted in the ground and the tip gives. That
-- is a bend rather than a slide, which is the whole difference between
-- grass in wind and a rug being pulled.
--
-- ------- why this can do what a tile animation cannot
--
-- A tile animation is one picture, shared by every cell drawing that tile.
-- Every tuft on a route therefore moves in perfect unison, which reads as
-- machinery -- and there is no way around it, because there is only one
-- tile.
--
-- A vertex shader knows WHERE each vertex is. Taking the wave's phase from
-- the vertex's own world position makes the gust TRAVEL: it arrives at the
-- near edge of a meadow, crosses it, and leaves. Nothing in this file is
-- clever; it is just the thing that becomes possible once the grass is
-- geometry, and it is the reason to do it here instead of there.
--
-- ------- the height it bends about
--
-- Structures builds a tuft's template at y = 0 and ChunkMesher offsets only
-- X and Z into the world (buildGrass: `{ q[1][1] + wx, q[1][2], q[1][3] +
-- wz }` -- the middle component is untouched). So a grass vertex's own y IS
-- its height above the base of the tuft it belongs to, and the bend factor
-- falls straight out of it with nothing to look up and no vertex attribute
-- to add.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local Wind = {}

-- Reach at the very tip, in world pixels, per rung. A tuft is about a cell
-- tall and a world pixel is the grid this whole mode exists to respect, so
-- two is already a visible lean and four is a storm.
Wind.setting = ModSetting.new("wind", "WIND",
                              { 2, 4, 0 },
                              { "BREEZE", "GALE", "OFF" })

-- How tall a tuft is taken to be, for the bend. Over-estimating only makes
-- the lean gentler, so this errs high on purpose.
Wind.TUFT = 16

-- Flowers are shorter and stiffer than grass, and they are also the one
-- thing in a meadow a player looks straight at, so they take a share of
-- the reach rather than all of it.
Wind.FLOWER_SHARE = 0.55

-- Radians per second. Slow: a gust that crosses a screen in a beat is a
-- flag, not weather.
Wind.RATE = 1.35

-- The wind's bearing, as a unit vector in world XZ. Blowing east and a
-- little south -- across the camera rather than into it, so the lean reads
-- as sideways movement instead of as the grass changing size.
Wind.DIR = { 0.94, 0.34 }

-- Wavelength, as the phase gained per world pixel along each axis. The two
-- differ so the crests run diagonally rather than in screen-aligned bars,
-- and both are small: about ninety world pixels to a full wave, which is
-- three cells -- long enough that a tuft and its neighbour lean together
-- and a meadow still has several crests in it at once.
Wind.FREQ = { 0.062, 0.047 }

function Wind.amount()
  local ok, v = pcall(Wind.setting.get, Wind.setting)
  local n = (ok and tonumber(v)) or 0
  if n < 0 then n = 0 end
  if n > 8 then n = 8 end
  return n
end

function Wind.enabled()
  return Wind.amount() > 0
end

-- The phase, from absolute time rather than an accumulator: this is read
-- once per frame by the scene and once more by a staged battle, and an
-- accumulator advanced per read would run at whatever rate it happened to
-- be called at.
function Wind.phase()
  if love and love.timer and love.timer.getTime then
    return (love.timer.getTime() * Wind.RATE) % (math.pi * 2048)
  end
  return 0
end

-- How far a point at world XZ leans with the wind, in world pixels on each
-- axis.  The same travelling wave the grass vertex shader rides
-- (Voxel3D.lua: sway * bend * (sin p + 0.35 sin 2.3p)), so a mon standing
-- in the meadow and the tuft next to it lean together rather than on two
-- clocks.  `heightFrac` is 0 at the ground and 1 at the tip -- squared the
-- same way the shader does, so the feet stay planted and the body gives.
--
-- Returns (dx, dz).  Zero under WIND OFF or a zero amount.
function Wind.leanAt(wx, wz, heightFrac)
  local sway = Wind.amount()
  if sway <= 0 then return 0, 0 end
  local h = tonumber(heightFrac) or 0.5
  if h < 0 then h = 0 elseif h > 1 then h = 1 end
  local bend = h * h
  local phase = Wind.phase()
  local p = wx * Wind.FREQ[1] + wz * Wind.FREQ[2] - phase
  local amp = sway * bend * (math.sin(p) + 0.35 * math.sin(p * 2.3 + 1.7))
  return Wind.DIR[1] * amp, Wind.DIR[2] * amp
end

return Wind
