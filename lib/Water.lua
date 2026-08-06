-- Voxel world mode: the water surface.
--
-- Water in this mode has been a flat quad with a scrolling texture: the
-- tileset's own animated tile, recessed two world pixels so the shoreline
-- shows a lip. That is the 2D game's water standing on its side -- the
-- picture moves and the surface does not.
--
-- Out here the surface is geometry, so it can move for real:
--
--   SWELL     Y = f(XZ) only -- watertight unindexed mesh, two crossing
--             trains + body-size field + crest steepening under energy.
--   SPARKLE   analytic normal (two cosines), cel-quantized glint rings.
--   BODY      rain / snow / freeze / wind / thermal inertia / chop energy
--             that lags the weather, so the surface has mass.
--
-- Still a four-colour diorama: hard steps, checker dither, three varyings
-- (vWater, vWave, vSwellH), identity only `y < -1`. No mesh attribute, no
-- second RT, no normal map, no soft airbrush.
--
-- SURFACE ART (optional drop-in): put a PNG at `assets/water/water.png` and
-- lakes / rivers sample it in world XZ instead of the tileset's water tile.
-- Same contract as assets/ground/: replace the file and it is used; delete
-- it and the tileset art comes back. No constant, no rebuild.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local Water = {}

Water.setting = ModSetting.new("swell", "WATER",
                               { 0.8, 1.4, 0 },
                               { "CALM", "SWELL", "FLAT" })

-- World pixels one full cycle of water.png covers. 64 = four map cells.
Water.ART_SCALE = 64
Water.ASSET_DIR = "assets/water/"
Water.ASSET_FILE = "water.png"

-- Rest wavelengths (phase gain per world px). Live WAVE_A/B are mutated.
Water.WAVE_A0 = { 0.070, 0.038 }
Water.WAVE_B0 = { -0.031, 0.058 }
Water.WAVE_A = { Water.WAVE_A0[1], Water.WAVE_A0[2] }
Water.WAVE_B = { Water.WAVE_B0[1], Water.WAVE_B0[2] }

-- Base phase rate (rad/s) before wet/freeze/wind/energy scales in phase().
-- R0 water_shimmer_probe (VERMILION, CALM, weather off, RES 1/2): continuous
-- background ~5.9% of the water mask was almost all swell+paint (tile/glint/
-- SSR each <5%). Lower base rate slows hard step() crawl under nearest
-- upscale; chop still accelerates via energy (phase() * (1+0.20*e)).
-- Was 0.9. With 0.55 + calm-gated mid foam: bg ~2.2–2.7% of water mask
-- (≈55% less than R0 5.9%). Palindrome at low counts is noisier; C_flat
-- still clean (0 continuous + tile impulses only).
Water.RATE = 0.55
Water.SPARKLE = 0.55
Water.GLINT_LO = 0.020
Water.GLINT_HI = 0.075

-- Fragment-only phase snap (radians). Geometry always uses continuous phase.
-- Tried 0.20: converted crawl into ~32% water-mask IMPULSES and made the
-- shimmer palindrome unreadable (A vs A2 drift 69%). Left at 0.
Water.PAINT_PHASE_STEP = 0

-- World-XZ cell size (px) for fragment height re-eval / band / noise paint.
-- Geometry continuous; paint snaps to this grid (sky floor idiom).
-- Tried liquid 4.0: palindrome drift 22% (bursty cell flips). Back to 2 / 5.5
-- matching the pre-knob hardcodes that gave a readable R0.
Water.PAINT_WCELL = 2.0
Water.PAINT_WCELL_ICE = 5.5

-- Climate inputs (pushed by Weather -- never require Weather back).
Water.wet = 0
Water.snow = 0

-- Amplitude physics
Water.CHOP = 0.70
Water.WIND_CHOP = 0.48
Water.WIND_FREQ = 0.58
Water.WET_RATE = 0.38
Water.STEEP = 0.22          -- crest sharpening at full energy (Gerstner-ish Y)

-- Freeze / mass
Water.freeze = 0
Water.freezeVel = 0         -- thermal inertia (df/dt lag)
Water.ICE_LIFT = 0.75
Water.FREEZE_RATE = 0.10
Water.MELT_RATE = 0.26
Water.WALK_FREEZE = 0.66
Water.THERMAL_INERTIA = 0.55  -- 0 = snap to target, 1 = very laggy

-- Freeze/thaw stand-up animation when the player is already ON the water
-- (surfing or standing on ice). event = { kind="lock"|"thaw", t, dur }.
-- Walking onto ice from land is allowed ONLY if the party can Surf (same
-- Soul Badge + SURF mon gate as mounting Surf) -- ice is not a free path.
Water.standEvent = nil
Water._wasSolidIce = false

-- Chop energy: lags wet+wind so the pond has momentum (not a switch).
Water.energy = 0
Water.ENERGY_ATTACK = 1.8   -- per second toward high chop
Water.ENERGY_RELEASE = 0.55 -- per second decay when weather calms

-- Live shader feeds
Water.CREST = 0
Water.SNOW_VEIL = 0
Water.ICE_SPARKLE = 0
Water.stepJitter = 0
Water.BODY = 1
Water.STEEP_NOW = 0         -- live steep sent to shader / used in heightField
Water.CURRENT = { 0.94, 0.34 }  -- unit XZ drift (from Wind.DIR)
Water.THERM = 0.5           -- 0 cold .. 1 warm (DayNight elevation proxy)

-- Spatial body-size field (pond vs open water stand-in).
Water.BODY_KX = 0.0039
Water.BODY_KZ = 0.0045

-- Advection: wind drags phase along CURRENT (group velocity feel).
Water.ADVECT = 0.045

local function clamp01(n)
  n = tonumber(n) or 0
  if n < 0 then return 0 end
  if n > 1 then return 1 end
  return n
end

local function wetness()
  return clamp01(Water.wet)
end

local function snowness()
  return clamp01(Water.snow)
end

function Water.windNorm()
  local ok, Wind = pcall(V.require, "Wind")
  if not ok or not Wind or not Wind.amount then return 0 end
  local n = tonumber(Wind.amount()) or 0
  if n < 0 then n = 0 end
  if n > 4 then n = 4 end
  return n / 4
end

function Water.windDir()
  local ok, Wind = pcall(V.require, "Wind")
  if ok and Wind and Wind.DIR then
    local x, z = tonumber(Wind.DIR[1]) or 0.94, tonumber(Wind.DIR[2]) or 0.34
    local len = math.sqrt(x * x + z * z)
    if len > 1e-4 then return x / len, z / len end
  end
  return Water.CURRENT[1], Water.CURRENT[2]
end

function Water.qualityMul()
  local ok, Quality = pcall(V.require, "Quality")
  if not ok or not Quality or not Quality.scale then return 1 end
  if Quality.scale() >= 4 then return 0.75 end
  return 1
end

-- Apparent body-size frequency scale at world XZ.
-- Shader twin: 0.90 + 0.35 * sin(x*BODY_KX) * cos(z*BODY_KZ)
function Water.bodyFreq(wx, wz)
  wx = tonumber(wx) or 0
  wz = tonumber(wz) or 0
  local n = math.sin(wx * Water.BODY_KX) * math.cos(wz * Water.BODY_KZ)
  return 0.90 + 0.35 * n
end

-- Thermal proxy from sun elevation: high noon melts, night freezes.
function Water.thermNow()
  local ok, DayNight = pcall(V.require, "DayNight")
  if not (ok and DayNight and DayNight.time and DayNight.bodyAt) then
    return Water.THERM
  end
  local _, el, moon = DayNight.bodyAt(DayNight.time())
  el = tonumber(el) or 45
  if moon then return 0.12 end
  -- 0 at horizon, ~1 at high sun
  local t = el / 50
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  return t
end

function Water.refreshLive()
  local w = Water.windNorm()
  local f = clamp01(Water.freeze)
  local e = clamp01(Water.energy)
  local scale = 1 + w * Water.WIND_FREQ + e * 0.22 - f * 0.65
  if scale < 0.28 then scale = 0.28 end
  if scale > 1.95 then scale = 1.95 end
  Water.WAVE_A[1] = Water.WAVE_A0[1] * scale
  Water.WAVE_A[2] = Water.WAVE_A0[2] * scale
  Water.WAVE_B[1] = Water.WAVE_B0[1] * scale
  Water.WAVE_B[2] = Water.WAVE_B0[2] * scale
  Water.BODY = scale
  Water.STEEP_NOW = Water.STEEP * e * (1 - f)

  local dx, dz = Water.windDir()
  Water.CURRENT[1], Water.CURRENT[2] = dx, dz

  local q = Water.qualityMul()
  local crest = e * 0.55 + wetness() * 0.90 + w * 0.70 + wetness() * w * 0.40
  if f > 0.30 then crest = crest * (1 - f) end
  Water.CREST = clamp01(crest) * q
  Water.SNOW_VEIL = snowness() * (1 - f * 0.35) * q
  Water.ICE_SPARKLE = f * 0.60 * (1 - wetness() * 0.45) * q
  Water.THERM = Water.thermNow()
end

function Water.swell()
  Water.refreshLive()
  local ok, v = pcall(Water.setting.get, Water.setting)
  local n = (ok and tonumber(v)) or 0
  if n < 0 then n = 0 end
  if n > 4 then n = 4 end
  local f = clamp01(Water.freeze)
  local e = clamp01(Water.energy)
  if n > 0 then
    n = n + Water.CHOP * wetness()
    n = n + Water.WIND_CHOP * Water.windNorm() * (1 - f)
    n = n + 0.30 * e * (1 - f)                 -- stored chop energy
    n = n + 0.25 * wetness() * Water.windNorm() * (1 - f)
    local sn = snowness()
    if sn > 0 then n = n * (1 - 0.45 * sn * (1 - f)) end
  end
  n = n * (1 - f)
  return n
end

function Water.tileRoll()
  if clamp01(Water.freeze) > 0.05 then return false end
  return Water.swell() <= 0
end

function Water.sparkleNow()
  local f = clamp01(Water.freeze)
  -- energy scatters specular; rain kills it
  local scatter = 1 - clamp01(Water.energy) * 0.35
  return Water.SPARKLE * (1 - wetness()) * (1 - f * 0.92) * scatter
end

function Water.rain()
  return wetness()
end

function Water.iceLift()
  -- mass conservation feel: as freeze rises, free surface lifts a little
  return Water.ICE_LIFT * clamp01(Water.freeze)
end

-- Absolute time phase with advection along wind current + dual tempo:
-- gravity swell (base RATE) + capillary hitch from rain energy.
function Water.phase()
  local rate = Water.RATE
  local f = clamp01(Water.freeze)
  local e = clamp01(Water.energy)
  rate = rate * (1 - Water.WET_RATE * wetness())
  rate = rate * (1 - 0.93 * f)
  rate = rate * (1 + 0.32 * Water.windNorm() * (1 - f))
  rate = rate * (1 + 0.20 * e * (1 - f))       -- choppy water clocks faster
  if rate < 0.012 then rate = 0.012 end
  if love and love.timer and love.timer.getTime then
    return (love.timer.getTime() * rate) % (math.pi * 2048)
  end
  return 0
end

-- Advected phase sample at a point: base phase + wind drag on XZ.
function Water.phaseAt(wx, wz)
  local p = Water.phase()
  local e = clamp01(Water.energy) * (1 - clamp01(Water.freeze))
  local dx, dz = Water.CURRENT[1], Water.CURRENT[2]
  local adv = Water.ADVECT * e * ((wx or 0) * dx + (wz or 0) * dz)
  return p + adv
end

-- ------- climate integration with thermal inertia + energy lag
function Water.step(dt)
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end

  local sn = snowness()
  local w = Water.windNorm()
  local therm = Water.thermNow()
  Water.THERM = therm

  -- freeze target from snow + cold therm + night
  local target = 0
  if sn > 0.04 then
    target = 0.38 + 0.62 * sn
  end
  if therm < 0.20 and (sn > 0.02 or Water.freeze > 0.06) then
    target = math.max(target, 0.55 + (0.20 - therm))
  end
  if therm < 0.12 and sn > 0.01 then
    target = math.max(target, 0.80)
  end
  if therm > 0.45 and sn < 0.08 then
    target = math.min(target, 0.15)
  end
  if therm > 0.62 and sn < 0.04 then
    target = 0
  end

  -- critically-damped-ish inertia toward target
  local f = clamp01(Water.freeze)
  local err = target - f
  local rate = err > 0
    and Water.FREEZE_RATE * (0.40 + 0.60 * sn)
    or  Water.MELT_RATE * (0.70 + 0.55 * therm)
  local inert = Water.THERMAL_INERTIA
  local vel = Water.freezeVel or 0
  vel = vel * (1 - (1 - inert) * 6 * dt) + err * rate * (1.4 - inert) * dt * 8
  if vel > 0.5 then vel = 0.5 elseif vel < -0.5 then vel = -0.5 end
  f = f + vel * dt
  if (err > 0 and f > target) or (err < 0 and f < target) then
    f = target
    vel = vel * 0.3
  end
  Water.freeze = clamp01(f)
  Water.freezeVel = vel

  -- chop energy lag (mass of the surface agitation)
  local wantE = clamp01(wetness() * 0.85 + w * 0.70 + wetness() * w * 0.45)
  wantE = wantE * (1 - clamp01(Water.freeze))
  local e = clamp01(Water.energy)
  if wantE > e then
    e = e + Water.ENERGY_ATTACK * (wantE - e) * dt
  else
    e = e - Water.ENERGY_RELEASE * (e - wantE) * dt
  end
  Water.energy = clamp01(e)

  -- Stand animation: lake freezes/thaws under a body already out there.
  -- Crossing the solid-ice threshold kicks a short hop + waterline blend
  -- so the mon rises onto the ice (or sinks back into a swim).
  local solid = Water.freeze >= Water.WALK_FREEZE
  if solid ~= Water._wasSolidIce then
    local onSurface, px, pz, p = Water._playerOnWaterSurface()
    if onSurface then
      if solid then
        Water.standEvent = { kind = "lock", t = 0, dur = 0.95 }
        Water.stepJitter = 1
        Water.noteFoot(px, pz)
      else
        Water.standEvent = { kind = "thaw", t = 0, dur = 0.75 }
        Water.stepJitter = 0.7
        -- Ice went liquid under a walker who is not surfing: keep them
        -- afloat if they still know Surf (same skill that let them on ice).
        if p and not p.surfing and Water.canUseSurf() then
          p.surfing = true
        end
      end
    end
    Water._wasSolidIce = solid
  end
  if Water.standEvent then
    local ev = Water.standEvent
    ev.t = (ev.t or 0) + dt
    if ev.t >= (ev.dur or 0.8) then
      Water.standEvent = nil
    end
  end

  if Water.stepJitter > 0 then
    Water.stepJitter = Water.stepJitter - dt * 6.5
    if Water.stepJitter < 0 then Water.stepJitter = 0 end
  end

  Water.refreshLive()
end

-- True when the party may use Surf (Soul Badge + a mon that knows SURF).
-- Same gate as mounting Surf from the shore -- ice walk reuses it so the
-- HM is still required, just not a free pass for a party without Surf.
function Water.canUseSurf()
  local ok, Game = pcall(require, "src.core.Game")
  if not ok or not Game or not Game.save then return false end
  local inv = Game.save.inventory
  if not inv or not inv.SOULBADGE then return false end
  local ow = Game.overworld
  if not ow then return false end
  if type(ow.partyKnows) == "function" then
    local pok, mon = pcall(ow.partyKnows, ow, "SURF")
    if pok and mon then return true end
  end
  -- Fallback: some builds only expose the field-move probe
  if type(ow.useSurfFieldMove) == "function" then
    local uok, res = pcall(ow.useSurfFieldMove, ow)
    if uok and res == "ok" then return true end
  end
  return false
end

-- Player is on a water cell (surfing, or standing on solid ice).
-- Returns onSurface, wx, wz, player.
function Water._playerOnWaterSurface()
  local ok, Game = pcall(require, "src.core.Game")
  if not ok or not Game or not Game.overworld then return false end
  local ow = Game.overworld
  local p = ow.player
  if not p then return false end
  local px = (p.px or ((p.cellX or 0) * 16)) + 8
  local pz = (p.py or ((p.cellY or 0) * 16)) + 8
  local onWaterCell = false
  if ow.map and ow.map.isWaterCell then
    local wok, water = pcall(ow.map.isWaterCell, ow.map, p.cellX, p.cellY)
    onWaterCell = wok and water
  end
  if not onWaterCell then return false end
  if p.surfing then return true, px, pz, p end
  if Water.walkableIce(px, pz) then return true, px, pz, p end
  return false
end

function Water._playerSurfingOnWater()
  local on, px, pz, p = Water._playerOnWaterSurface()
  if not on or not p or not p.surfing then return false end
  return true, px, pz
end

-- Multi-octave plate mask for partial freeze (leads of open water).
function Water.frozenAt(wx, wz)
  local f = clamp01(Water.freeze)
  if f <= 0 then return 0 end
  if f >= 0.999 then return 1 end
  local cx = math.floor((tonumber(wx) or 0) / 16)
  local cz = math.floor((tonumber(wz) or 0) / 16)
  local h1 = math.sin(cx * 12.9898 + cz * 78.233) * 43758.5453
  h1 = h1 - math.floor(h1)
  local h2 = math.sin(cx * 39.346 + cz * 11.135) * 23421.631
  h2 = h2 - math.floor(h2)
  local h3 = math.sin(cx * 7.1 + cz * 93.7) * 9123.17
  h3 = h3 - math.floor(h3)
  local h = h1 * 0.50 + h2 * 0.30 + h3 * 0.20
  local plate = f * 1.42 - 0.32 * h - 0.10
  return clamp01(plate)
end

function Water.walkableIce(wx, wz)
  return Water.frozenAt(wx, wz) >= Water.WALK_FREEZE
end

-- True when a character at world XZ is standing ON ice (not swimming).
-- Used to drop the waterline cut so the full sprite shows. Does NOT make
-- the cell freely walkable from land -- Surf is still how you get out there.
function Water.isStandingOnIce(wx, wz)
  return Water.walkableIce(wx, wz)
end

-- Waterline cut in pixels for a swimming body at (wx,wz).
-- Liquid: full swim cut. Ice: 0 (standing). During lock/thaw anim: blends
-- so the mon visibly rises out of / sinks into the surface.
function Water.waterlineCut(wx, wz, baseCut)
  baseCut = tonumber(baseCut) or 5
  local onIce = Water.isStandingOnIce(wx, wz)
  local ev = Water.standEvent
  if ev and ev.dur and ev.dur > 0 then
    local u = (ev.t or 0) / ev.dur
    if u < 0 then u = 0 elseif u > 1 then u = 1 end
    -- ease: smoothstep-ish without being a soft airbrush on the sprite
    local e = u * u * (3 - 2 * u)
    if ev.kind == "lock" then
      -- swimming cut -> standing (0)
      return math.floor(baseCut * (1 - e) + 0.5)
    elseif ev.kind == "thaw" then
      -- standing -> swimming cut
      return math.floor(baseCut * e + 0.5)
    end
  end
  if onIce then return 0 end
  return baseCut
end

-- Extra Y lift during freeze/thaw hop (world px). Sin pulse: up then settle.
function Water.standAnimLift(wx, wz)
  local ev = Water.standEvent
  if not ev or not ev.dur or ev.dur <= 0 then return 0 end
  local u = (ev.t or 0) / ev.dur
  if u < 0 or u > 1 then return 0 end
  local amp = ev.kind == "lock" and 2.6 or 1.4
  return math.sin(math.pi * u) * amp
end

local footCX, footCZ = nil, nil
function Water.noteFoot(wx, wz)
  local cx = math.floor((tonumber(wx) or 0) / 16)
  local cz = math.floor((tonumber(wz) or 0) / 16)
  if footCX == cx and footCZ == cz then return end
  footCX, footCZ = cx, cz
  if Water.walkableIce(wx, wz) then
    Water.stepJitter = 1
  end
end

Water.BASE = -2

-- Shared height field -- byte for byte with the vertex shader.
-- Two trains * bodyFreq * advection, then crest steepening under energy:
--   h' = h + steep * h * |h|   (sharpens crests, deepens troughs a touch)
function Water.heightField(wx, wz, phase)
  wx = tonumber(wx) or 0
  wz = tonumber(wz) or 0
  local ax, az = Water.WAVE_A[1], Water.WAVE_A[2]
  local bx, bz = Water.WAVE_B[1], Water.WAVE_B[2]
  local bf = Water.bodyFreq(wx, wz)
  local a = (wx * ax + wz * az) * bf - phase
  local b = (wx * bx + wz * bz) * bf + phase * 0.7
  local h = math.sin(a) * 0.55 + math.sin(b) * 0.45
  local steep = Water.STEEP_NOW or 0
  if steep > 0 then
    local ah = h < 0 and -h or h
    h = h + steep * h * ah
  end
  return h, a, b, bf
end

function Water.heightAt(wx, wz)
  local swell = Water.swell()
  if swell <= 0 then return 0 end
  local h = Water.heightField(wx, wz, Water.phaseAt(wx, wz))
  return swell * h
end

function Water.surfaceAt(wx, wz)
  return Water.BASE + Water.heightAt(wx, wz) + Water.iceLift()
end

function Water.paints()
  if clamp01(Water.freeze) > 0.02 then return true end
  local ok, v = pcall(Water.setting.get, Water.setting)
  local n = (ok and tonumber(v)) or 0
  return n > 0
end

-- ------- optional surface art (assets/water/water.png)
--
-- Cached Image or false ("there is none"). nil = not tried yet. A 1x1 blank
-- is always available for the scene sampler so an unbound Image is never
-- sent (driver-dependent crash, same pattern as GlassMask.blank).

local artImage = nil   -- Image | false
local artBlank = nil   -- Image | false

local function loadArt()
  if artImage ~= nil then return artImage or nil end
  local okA, Assets = pcall(require, "src.render.Assets")
  if not okA or not Assets then
    artImage = false
    return nil
  end
  local path = V.path .. "/" .. Water.ASSET_DIR .. Water.ASSET_FILE
  local okE, exists = pcall(Assets.exists, path)
  if not (okE and exists) then
    artImage = false
    return nil
  end
  local ok, img = pcall(Assets.image, path)
  if not (ok and img) then
    artImage = false
    return nil
  end
  pcall(img.setFilter, img, "linear", "linear")
  pcall(img.setWrap, img, "repeat", "repeat")
  artImage = img
  return img
end

-- The shipped water surface texture, or nil when the file is missing.
function Water.art()
  return loadArt()
end

-- 1 when art() is a real file, 0 when the tileset tile should stay.
function Water.artOn()
  return loadArt() and 1 or 0
end

function Water.artScale()
  local n = tonumber(Water.ART_SCALE) or 64
  if n < 8 then n = 8 end
  return n
end

-- Always-bound stand-in for the scene shader's waterArt sampler.
function Water.artBlank()
  if artBlank == nil then
    local ok, img = pcall(function()
      local data = love.image.newImageData(1, 1)
      data:setPixel(0, 0, 0.1, 0.35, 0.75, 1)
      local i = love.graphics.newImage(data)
      pcall(i.setFilter, i, "nearest", "nearest")
      pcall(i.setWrap, i, "repeat", "repeat")
      return i
    end)
    artBlank = (ok and img) or false
  end
  return artBlank or nil
end

-- Hot reload / window resize: drop GPU objects so the next frame reloads
-- assets/water/water.png if it appeared or changed on disk.
function Water.dropGPU()
  if artImage and artImage ~= false and artImage.release then
    pcall(artImage.release, artImage)
  end
  artImage = nil
  if artBlank and artBlank ~= false and artBlank.release then
    pcall(artBlank.release, artBlank)
  end
  artBlank = nil
end

-- Walk-on-ice: frozen water cells count as ground IF the party can Surf
-- (Soul Badge + SURF). Liquid water stays blocked without mounting Surf.
-- So ice is walkable and immersive, but the HM is still required.
function Water.installWalk()
  local ok, Map = pcall(require, "src.world.Map")
  if not ok or not Map or Map._dsIceWalk then return end
  local walk = Map.isWalkableCell
  if type(walk) ~= "function" then return end
  function Map:isWalkableCell(cx, cy)
    if walk(self, cx, cy) then return true end
    if type(self.isWaterCell) == "function" then
      local wok, water = pcall(self.isWaterCell, self, cx, cy)
      if wok and water and Water.canUseSurf() then
        local wx, wz = (cx or 0) * 16 + 8, (cy or 0) * 16 + 8
        if Water.walkableIce(wx, wz) then return true end
      end
    end
    return false
  end
  Map._dsIceWalk = true
end

return Water
