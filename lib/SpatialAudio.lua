-- Voxel world mode: where a sound sits in the air.
--
-- Beds and cries used to be mono point sources at the listener -- volume
-- faked distance by arithmetic, but left and right never differed, so a
-- Magikarp on the left bank and a Pidgey on the right both came from the
-- middle of the headphones. LOVE/OpenAL already does 3D attenuation; this
-- file only points it at the diorama.
--
-- Coordinates match Voxel3D: X east, Y up, Z south. The listener is the
-- player (or the free-roam camera eye when one is up), looking the way the
-- orbit looks, so panning agrees with what the frame is facing.
--
-- Safe to call with a nil Source or a driver that has no spatial API: every
-- OpenAL call is pcall'd and a missing function is a no-op, so the feature
-- degrades to the old flat mix rather than taking the ambience down with it.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local SpatialAudio = {}

-- Reference / max distance in WORLD PIXELS (one cell is 16). A cry at the
-- same cell as the player is full; past MAX it is silence. Tuned so a mon
-- seven cells off (AmbientSound's CRY_REACH) is still audible but soft.
SpatialAudio.REF = 24          -- ~1.5 cells
SpatialAudio.MAX = 160         -- 10 cells
SpatialAudio.ROLLOFF = 1.15

local ready = false

local function ensure()
  if ready or not love or not love.audio then return ready end
  -- inverseclamped: full volume inside REF, then inverse falloff, silence
  -- past MAX. The older "inverse" model never fully quiets, which left far
  -- water as a constant hiss.
  pcall(love.audio.setDistanceModel, "inverseclamped")
  ready = true
  return true
end

-- World-pixel position of the listener and the way it is facing.
-- Prefer the free-roam camera eye (matches what the player is looking at);
-- fall back to the player's feet so 2D flat mode still pans a little when
-- cries fire beside them.
function SpatialAudio.updateListener(ow, eye, focus)
  if not ensure() then return end
  local lx, ly, lz = 0, 8, 0
  local fx, fy, fz = 0, 0, 1
  if eye and eye[1] then
    lx, ly, lz = eye[1], eye[2], eye[3]
  elseif ow and ow.player then
    local p = ow.player
    lx = (p.cellX or 0) * 16 + 8
    ly = 12
    lz = (p.cellY or 0) * 16 + 8
  end
  if focus and focus[1] and eye and eye[1] then
    fx = focus[1] - eye[1]
    fy = focus[2] - eye[2]
    fz = focus[3] - eye[3]
    local len = math.sqrt(fx * fx + fy * fy + fz * fz)
    if len > 0.001 then
      fx, fy, fz = fx / len, fy / len, fz / len
    else
      fx, fy, fz = 0, 0, 1
    end
  end
  pcall(love.audio.setPosition, lx, ly, lz)
  -- forward + world up. OpenAL wants unit vectors; up is always +Y so the
  -- horizon stays level the same way Voxel3D's free-roam camera does.
  pcall(love.audio.setOrientation, fx, fy, fz, 0, 1, 0)
  -- mild Doppler off: a walking mon should not pitch-shift
  pcall(love.audio.setDopplerScale, 0)
end

-- Attach a Source to a world point. Relative=false means "in the world";
-- attenuation is in world pixels so it tracks the diorama, not the window.
function SpatialAudio.place(src, wx, wy, wz, opts)
  if not src then return end
  if not ensure() then return end
  opts = opts or {}
  local ref = opts.ref or SpatialAudio.REF
  local maxd = opts.max or SpatialAudio.MAX
  local roll = opts.rolloff or SpatialAudio.ROLLOFF
  pcall(src.setRelative, src, false)
  pcall(src.setPosition, src, wx or 0, wy or 0, wz or 0)
  pcall(src.setAttenuationDistances, src, ref, maxd)
  pcall(src.setRolloff, src, roll)
  -- volume is still the caller's job (SFX row, bed level); this only places
end

-- Keep a Source glued to the listener (rain on a roof, indoor room tone).
-- Relative=true ignores world position and sits in the headphones centre.
function SpatialAudio.relative(src)
  if not src then return end
  if not ensure() then return end
  pcall(src.setRelative, src, true)
  pcall(src.setPosition, src, 0, 0, 0)
end

-- Cell centre in world pixels. Y is a standing mon's chest-ish height so a
-- cry does not come from the floor under the feet.
function SpatialAudio.cell(cx, cy, height)
  return (cx or 0) * 16 + 8, height or 10, (cy or 0) * 16 + 8
end

return SpatialAudio
