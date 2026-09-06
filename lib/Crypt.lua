-- Voxel world mode: the AIR of the tower of graves -- what the crypt is lit
-- by, what it is filled with, and which of its floors are restless.
--
-- lib/CryptKit.lua stands the Pokemon Tower's floors as a crypt: the ring of
-- wall panels the drawing spells as a chamber cut into grey stock becomes a
-- tall octagon of ashlar that climbs out of the light, the mass beyond it
-- goes to black, the headstones stand on plinths. Geometry is not what
-- makes a room read as a crypt, though -- light is. A Gen 1 interior is lit
-- flat, every surface the same white, and under that a stone wall is a grey
-- rectangle. So this module is the other half of the same idea, the half
-- that runs every frame:
--
--   AMBIENT   the tint is held DOWN and cooled (the passage's lesson, see
--             lib/Underpass.lua: there was never too little light indoors,
--             there was too little dark), lowest on the haunted floors.
--   LAMPS     candle lanterns in wall sconces -- the scene shader's eight
--             point lights, warm, breathing on the gas clock -- so the
--             stone is bright under a flame and gloomy between them. Their
--             SITES are authored here per floor, and the kit reads the same
--             table to put the iron bracket and the lantern on the wall,
--             so a pool of light always has a flame over it.
--   FLAMES    the flame itself, a flattened card at each lantern (the
--             street lamp's own trick: a drawn thing the hour's tint cannot
--             put out), with a halo, flickering.
--   AIR       a violet haze on the haunted floors (data/atmosphere.lua,
--             entries marked `indoor`), so the far wall greys out and the
--             room has depth. lib/GhostFX.lua reads `haunted` to let its
--             wisps breathe out of the graves.
--
-- Nothing here is extracted from the ROM: the sites and the numbers are
-- this mod's own reading of what a tower of graves should look like inside.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Voxel3D = V.require("Voxel3D")
local ModSetting = V.require("ModSetting")

local Crypt = {}

local floor = math.floor
local sin = math.sin

-- ------------------------------------------------------------- the row --
--
-- The CRYPT row lives here rather than in the kit because both halves
-- answer to it: on CLASSIC the kit stamps nothing AND the scene lights the
-- floors flat, lays no flagstones, carries no air and breathes no wisps --
-- the interior as it stood before, whole. (lib/CryptKit.lua re-exports the
-- setting and adds the remesh its own step needs.)
Crypt.setting = ModSetting.new("crypt", "CRYPT",
                               { "new", "classic" },
                               { "NEW", "CLASSIC" })

function Crypt.enabled()
  local ok, v = pcall(Crypt.setting.get, Crypt.setting)
  if not ok then return true end
  return v ~= "classic"
end

-- The CRYPT-FX row: the shader's share of the crypt -- the lanterns
-- lighting every flank by its real face normal, a wet sheen on the stone
-- under them, ground mist drifting through the graves, and the bloom that
-- makes a flame a light rather than a yellow drawing (lib/Bloom.lua).
-- Its own row because it is the costlier half, and because a player who
-- wants the geometry without the picture-processing should be able to say
-- so. Off, the crypt is lit exactly as the streets are.
Crypt.fxSetting = ModSetting.new("cryptfx", "CRYPT-FX",
                                 { "on", "off" }, { "ON", "OFF" })

function Crypt.fxOn()
  if not Crypt.enabled() then return false end
  local ok, v = pcall(Crypt.fxSetting.get, Crypt.fxSetting)
  if not ok then return true end
  return v ~= "off"
end

-- ------------------------------------------------------------- the maps --
--
-- Lantern sites in CELLS (cx, cy) plus the side of the wall cell the
-- lantern hangs on -- the side facing the room. Every octagon floor shares
-- one ring, so 1F..6F share one list; 7F is the hall to Mr. Fuji's shrine.
-- `ambient` is the share of the interior's flat light the floor keeps;
-- `haunted` floors are the ones whose Channelers are possessed (3F..6F),
-- and Agatha's room, which is a crypt of its own.
local OCTAGON = {
  { 9, 0, "s" }, { 12, 0, "s" },      -- the north wall, either side of centre
  { 2, 8, "e" }, { 19, 8, "w" },      -- the west and east walls
  { 3, 11, "e" }, { 18, 11, "w" },    -- the south-west and south-east flanks
}
local HALL = {
  { 8, 4, "e" }, { 13, 4, "w" },
  { 8, 8, "e" }, { 13, 8, "w" },
  { 8, 12, "e" }, { 13, 12, "w" },    -- standing lanterns on the low walls
}

-- (the ambient came down a step when the lanterns went up -- see RADIUS
-- and POWER below: a candle-lit room is dark BETWEEN the candles, and the
-- pools only read as pools against that)
Crypt.MAPS = {
  POKEMON_TOWER_1F = { sites = OCTAGON, ambient = 0.50, haunted = false },
  POKEMON_TOWER_2F = { sites = OCTAGON, ambient = 0.46, haunted = false },
  POKEMON_TOWER_3F = { sites = OCTAGON, ambient = 0.41, haunted = true },
  POKEMON_TOWER_4F = { sites = OCTAGON, ambient = 0.39, haunted = true },
  POKEMON_TOWER_5F = { sites = OCTAGON, ambient = 0.39, haunted = true },
  POKEMON_TOWER_6F = { sites = OCTAGON, ambient = 0.35, haunted = true },
  POKEMON_TOWER_7F = { sites = HALL, ambient = 0.45, haunted = false },
  AGATHAS_ROOM = { sites = {}, ambient = 0.56, haunted = true },
}

-- The tileset every one of them draws with. A map on it that the table
-- above does not name still gets the geometry (the kit matches tiles, not
-- maps) and the default air below.
Crypt.TILESET = "CEMETERY"
Crypt.DEFAULT = { sites = {}, ambient = 0.62, haunted = false }

-- ------------------------------------------------------------- the light --

Crypt.RADIUS = 136            -- how far a lantern's pool reaches, world px
Crypt.POWER = 2.6             -- and how hard it burns at the flame
Crypt.HEIGHT = 25             -- world y of a sconce's flame
Crypt.COLOR = { 1.00, 0.72, 0.40 }   -- candle amber at the rim of a pool
Crypt.CORE = { 1.00, 0.94, 0.78 }    -- near-white under the flame
Crypt.LIMIT = 8               -- the shader's lamp slots
-- the ambient, on top of the floor's own share: cooled, and on a haunted
-- floor pushed toward violet
Crypt.COOL = { 0.90, 0.93, 1.10 }
Crypt.HAUNT_COOL = { 0.90, 0.86, 1.14 }

-- ------- the CRYPT-FX numbers (see the uniforms in lib/Voxel3D.lua)
Crypt.SPEC = 0.55             -- the wet sheen's strength under a lantern
-- the mist: how much, how high it has thinned to nothing, the drift's
-- scale in world px, and the colour -- heavier and violet where it is
-- haunted, a thin grey breath elsewhere
Crypt.MIST = { amount = 0.38, height = 13, scale = 26,
               color = { 0.40, 0.40, 0.48 } }
Crypt.MIST_HAUNTED = { amount = 0.58, height = 16, scale = 24,
                       color = { 0.60, 0.52, 0.76 } }
-- the bloom: what counts as a light (luminance over this), how much of
-- it comes back, and the reduction the blur runs at
Crypt.BLOOM = { threshold = 0.82, strength = 0.52, div = 4, passes = 1 }

-- the materials (see the uniforms): the two surfaces in assets/stone/ with
-- their relief maps (tools: make_stone2.py bakes albedo and normal from one
-- height field, periodic), world px per cycle, how far the white goes
-- toward the art, the relief's strength
Crypt.STONE = { dir = "assets/stone/",
                -- Poly Haven's castle_wall_slates and granite_tile_03 (CC0),
                -- graded for the crypt: see assets/stone/README.md
                wall = "crypt_wall.jpg", wallNorm = "crypt_wall_n.jpg",
                -- and the same wall's HEIGHT, 8-bit: the kit stands each
                -- stone of it in DEPTH -- proud of its joint, two voxels
                -- into the room at the highest -- so the voxels, the
                -- albedo and the relief map describe the same stones
                -- (lib/CryptKit.lua)
                wallHeight = "crypt_wall_h.png",
                granite = "crypt_granite.jpg",
                graniteNorm = "crypt_granite_n.jpg",
                -- the granite is one slab's interior and does not tile; a
                -- mirror is invisible on speckle
                graniteWrap = "mirroredrepeat",
                scale = 256, mix = 0.94, bump = 1.15,
                -- the hemisphere: how much less of the room's fill a face
                -- gets for looking along instead of up -- read off the
                -- relief maps too, so the stone keeps a grain in the fill
                -- light and not only under a flame (see `stoneHemi`)
                hemi = 0.60 }

-- RayFX's ambient occlusion, asked for whatever the RTX row says (at least
-- the `ao` rung), and harder and closer than the streets': a crypt is
-- corners, and the shading in them is what makes the stone solid.
-- The walls now stand their stones in DEPTH (lib/CryptKit.lua: proud
-- stones, recessed joints, a chamfered octagon), so the relief already
-- shades itself -- 2.9 turned every joint into a black stain, 2.0 still
-- dirtied the mortar once the stones were two voxels proud; 1.75 (up
-- from 1.55 once the wall lost its black core) lets the lanterns rake
-- the sides of a stone without filling the joint.
Crypt.AO = { power = 1.75, range = 12 }
-- the sun pass indoors is the noon rig's shadow from nowhere: OFF. There
-- is no sun in a crypt; the lanterns, the hemisphere and the occlusion
-- own the dark (and the shadow map's fetches are not paid for a light
-- that is not there)
Crypt.SHADOW_SCALE = 0

local stoneImgs = {}          -- file -> Image | false

local function loadStone(file, wrap)
  local have = stoneImgs[file]
  if have ~= nil then return have or nil end
  local img = nil
  local okA, Assets = pcall(require, "src.render.Assets")
  if okA and Assets then
    local path = V.path .. "/" .. Crypt.STONE.dir .. file
    local okE, exists = pcall(Assets.exists, path)
    if okE and exists then
      local ok, i = pcall(Assets.image, path)
      if ok and i then
        pcall(i.setFilter, i, "linear", "linear")
        -- plain repeat by default: the art tiles, and a mirror would flip
        -- the relief's x at every fold
        local w = wrap or "repeat"
        pcall(i.setWrap, i, w, w)
        img = i
      end
    end
  end
  stoneImgs[file] = img or false
  return img
end

-- The materials for this frame -- { art, norm, granite, graniteNorm,
-- scale, mix, bump } -- or nil when the row is off or the files are not
-- there.
function Crypt.stoneFor()
  if not Crypt.fxOn() then return nil end
  local art = loadStone(Crypt.STONE.wall)
  if not art then return nil end
  local gw = Crypt.STONE.graniteWrap
  return { art = art, norm = loadStone(Crypt.STONE.wallNorm),
           granite = loadStone(Crypt.STONE.granite, gw) or art,
           graniteNorm = loadStone(Crypt.STONE.graniteNorm, gw),
           scale = Crypt.STONE.scale, mix = Crypt.STONE.mix,
           bump = Crypt.STONE.bump, hemi = Crypt.STONE.hemi }
end

-- ------- the post pass (lib/Bloom.lua): rays off the lanterns, the grade
Crypt.RAYS = { decay = 0.90, weight = 0.32, max = 4 }
-- exposure 1: the curve keeps black black and only steepens the middle;
-- `split` leans the darks toward the crypt's cool violet and the lights
-- toward the flame -- the room's two lights, finishing the frame
Crypt.GRADE = { exposure = 1.0, vignette = 0.52, grain = 0.016, tone = 0.42,
                split = 0.55 }

-- What the post pass needs this frame: the bloom's numbers, the lanterns'
-- places on the canvas (for the rays; the nearest few to the centre), the
-- grade.
function Crypt.bloomOpts(map, w, h)
  local o = { threshold = Crypt.BLOOM.threshold, strength = Crypt.BLOOM.strength,
              div = Crypt.BLOOM.div, passes = Crypt.BLOOM.passes,
              rays = Crypt.RAYS, grade = Crypt.GRADE, lights = {} }
  w, h = tonumber(w) or 1, tonumber(h) or 1
  local list = {}
  for _, l in ipairs(Crypt.lanterns(map)) do
    local px, py = Voxel3D.project(l.x, l.y + 1.5, l.z)
    if px and py and px > -0.3 * w and px < 1.3 * w
        and py > -0.3 * h and py < 1.3 * h then
      local u, v = px / w, py / h
      list[#list + 1] = { u, v, d2 = (u - 0.5) ^ 2 + (v - 0.5) ^ 2 }
    end
  end
  table.sort(list, function(a, b) return a.d2 < b.d2 end)
  for i = 1, math.min(#list, Crypt.RAYS.max) do o.lights[i] = list[i] end
  return o
end

-- The mist uniform for a map this frame: { amount, height, 1/scale, time }
-- and its colour, or nil when the row is off.
function Crypt.mistFor(map)
  if not Crypt.fxOn() then return nil, nil end
  local e = Crypt.entry(map)
  local m = e.haunted and Crypt.MIST_HAUNTED or Crypt.MIST
  local t = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
  return { m.amount, m.height, 1 / math.max(1, m.scale), t % 100000 },
         m.color
end

-- ------------------------------------------------------------ the walls --
--
-- How tall the ring stands, by CELL ROW: the far walls climb out of the
-- light, the near ones are cut down to a parapet so the fixed camera at the
-- south (data/camera_shots.lua) looks over them -- the dollhouse cut every
-- fixed-camera crypt is drawn with. Agatha's room has no such camera and
-- keeps one moderate wall.
Crypt.TALL = 88
Crypt.LOW = 14
Crypt.BANDS = { [9] = 72, [10] = 52, [11] = 34, [12] = 20 }
Crypt.AGATHA_H = 56

function Crypt.heightFor(id, cy)
  if id == "AGATHAS_ROOM" then return Crypt.AGATHA_H end
  cy = tonumber(cy) or 0
  if cy <= 8 then return Crypt.TALL end
  return Crypt.BANDS[cy] or Crypt.LOW
end

-- ------------------------------------------------------------- lookups --

local function idOf(map)
  local def = map and map.def
  return def and (def.id or def.name) or nil
end

function Crypt.entry(map)
  local id = type(map) == "string" and map or idOf(map)
  return (id and Crypt.MAPS[id]) or Crypt.DEFAULT
end

-- Whether the map is one of the crypt's, with the row on NEW. The sheet
-- is the test, not the map table: a map on it the table does not name
-- still gets the default air.
function Crypt.onSheet(map)
  local ts = map and map.tileset
  if not ts then return false end
  if ts.id == Crypt.TILESET then return true end
  local img = ts.image
  return type(img) == "string" and img:lower():find("cemetery", 1, true) ~= nil
end

function Crypt.matches(map)
  return Crypt.enabled() and Crypt.onSheet(map)
end

-- `map` may be the map object or its id
function Crypt.haunted(map)
  if not Crypt.enabled() then return false end
  return Crypt.entry(map).haunted and true or false
end

-- The side a lantern hangs on for wall cell (cx, cy) of map `id`, or nil.
function Crypt.siteAt(id, cx, cy)
  local e = Crypt.entry(id)
  for _, s in ipairs(e.sites or {}) do
    if s[1] == cx and s[2] == cy then return s[3] end
  end
  return nil
end

-- Where the flame of a site is, in the wall cell's OWN coordinates (x east,
-- y up, z south, 0..15 the cell): a sconce reaches into the room past the
-- face it hangs on; on a wall too low for a bracket the lantern stands on
-- the coping instead. Shared with the kit so the drawn lantern and the
-- shader's point light never disagree.
Crypt.SCONCE_OUT = 4          -- how far past the face the lantern hangs
Crypt.STAND_MIN = 32          -- walls shorter than this carry a standing lantern

function Crypt.flameLocal(side, H)
  H = tonumber(H) or Crypt.TALL
  local standing = H < Crypt.STAND_MIN
  local out = Crypt.SCONCE_OUT
  local y = standing and (H + 3) or Crypt.HEIGHT
  if side == "s" then
    return 8, y, standing and 13.5 or (16 + out), standing
  elseif side == "n" then
    return 8, y, standing and 2.5 or (-1 - out), standing
  elseif side == "e" then
    return standing and 13.5 or (16 + out), y, 8, standing
  else
    return standing and 2.5 or (-1 - out), y, 8, standing
  end
end

-- Every lantern of the map in world space: { x, y, z, side, standing }.
local siteCache = { id = nil, list = nil }

function Crypt.lanterns(map)
  local id = idOf(map)
  if not id then return {} end
  if siteCache.id == id and siteCache.list then return siteCache.list end
  local out = {}
  for _, s in ipairs(Crypt.entry(id).sites or {}) do
    local cx, cy, side = s[1], s[2], s[3]
    local H = Crypt.heightFor(id, cy)
    local lx, ly, lz, standing = Crypt.flameLocal(side, H)
    out[#out + 1] = { x = cx * 16 + lx, y = ly, z = cy * 16 + lz,
                      side = side, standing = standing, cx = cx, cy = cy }
  end
  siteCache.id, siteCache.list = id, out
  return out
end

-- The nearest LIMIT lanterns to (wx, wz), in the shape Voxel3D.lampLights
-- wants: { x, z, radius, power }.
function Crypt.lights(map, wx, wz)
  wx, wz = tonumber(wx) or 0, tonumber(wz) or 0
  local out = {}
  for _, l in ipairs(Crypt.lanterns(map)) do
    local dx, dz = l.x - wx, l.z - wz
    out[#out + 1] = { x = l.x, z = l.z, radius = Crypt.RADIUS,
                      power = Crypt.POWER, d2 = dx * dx + dz * dz }
  end
  table.sort(out, function(a, b) return a.d2 < b.d2 end)
  for i = #out, Crypt.LIMIT + 1, -1 do out[i] = nil end
  return out
end

-- The interior's tint, held down to the floor's share and cooled.
function Crypt.ambient(map, tint)
  local e = Crypt.entry(map)
  local k = tonumber(e.ambient) or 0.6
  local c = e.haunted and Crypt.HAUNT_COOL or Crypt.COOL
  if type(tint) ~= "table" or not tint[3] then tint = { 1, 1, 1 } end
  return { tint[1] * k * c[1], tint[2] * k * c[2], tint[3] * k * c[3] }
end

-- ------------------------------------------------------------- the flame --
--
-- Drawn once at load, not shipped: a 10x14 teardrop, hot core over an
-- amber body with the one-texel rim every cel thing in this mod wears,
-- alpha 1 inside and 0 out (the scene shader discards under half alpha).
Crypt.FLAME_W, Crypt.FLAME_H = 10, 14
Crypt.FLAME_HW = 2.6          -- card half-width at rest, world px
Crypt.FLAME_HH = 4.0
Crypt.FLAME_HALO = 3.2        -- the halo, as a multiple of the core
Crypt.FLAME_HALO_A = 0.30
Crypt.FLAME_GLOW = { 1.0, 0.86, 0.55 }
Crypt.FLAME_FLAT = 0.88

local flameImg = nil
local builder = nil
local current = nil           -- the map being drawn (VoxelScene pushes it)

local function makeFlame()
  local W, H = Crypt.FLAME_W, Crypt.FLAME_H
  if not (love.image and love.graphics) then return nil end
  local ok, data = pcall(love.image.newImageData, W, H)
  if not ok then return nil end
  local inside = {}
  local function within(x, y)
    if x < 0 or y < 0 or x >= W or y >= H then return false end
    return inside[y * W + x] or false
  end
  -- a teardrop: wide at the bottom third, narrowing to a point at the top
  local cx = (W - 1) / 2
  for y = 0, H - 1 do
    local t = (y + 0.5) / H          -- 0 at the tip, 1 at the base
    local r = (W / 2 - 0.4) * (t < 0.7 and (t / 0.7) or (1 - (t - 0.7) / 0.3 * 0.55))
    for x = 0, W - 1 do
      inside[y * W + x] = math.abs(x + 0.5 - cx - 0.5) <= r
    end
  end
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      if inside[y * W + x] then
        local t = (y + 0.5) / H
        local dx = (x + 0.5 - cx - 0.5) / (W / 2)
        local core = (t > 0.45 and t < 0.92 and math.abs(dx) < 0.42)
        local r, g, b = 1.0, 0.72, 0.30
        if core then r, g, b = 1.0, 0.96, 0.80 end
        if not (within(x - 1, y) and within(x + 1, y)
                and within(x, y - 1) and within(x, y + 1)) then
          r, g, b = 0.95, 0.45, 0.12
        end
        data:setPixel(x, y, r, g, b, 1)
      end
    end
  end
  local okI, image = pcall(love.graphics.newImage, data)
  if not okI then return nil end
  pcall(image.setFilter, image, "nearest", "nearest")
  return image
end

local function loadFlame()
  if flameImg ~= nil then return flameImg or nil end
  flameImg = makeFlame() or false
  return flameImg or nil
end

function Crypt.flame() return loadFlame() end

function Crypt.setMap(map)
  current = map
end

Crypt.lastBatches = -1
Crypt.drawErrors = 0
Crypt.drawError = nil

local function clock()
  return (love.timer and love.timer.getTime and love.timer.getTime()) or 0
end

local function emitFlame(l, push)
  local image = flameImg
  if not image then return end
  local t = clock()
  local ph = l.x * 0.13 + l.z * 0.07
  -- two octaves of breath, phased off the site so a row of flames does
  -- not blink as one
  local f = 1 + 0.10 * sin(t * 9.1 + ph) * (0.6 + 0.4 * sin(t * 23.7 + ph * 3))
  local lean = 0.10 * sin(t * 5.3 + ph)
  local hw = Crypt.FLAME_HW * (1.05 - 0.1 * f)
  local hh = Crypt.FLAME_HH * f
  local g = Crypt.FLAME_GLOW
  -- the halo first, so the core draws over it
  push(image, 0, 0, 1, 1, hw * Crypt.FLAME_HALO, hh * Crypt.FLAME_HALO * 0.8,
       lean * 0.5, g[1], g[2], g[3], Crypt.FLAME_HALO_A * (0.9 + 0.1 * f))
  push(image, 0, 0, 1, 1, hw, hh, lean, 1, 1, 1, 1)
end

local function drawWorldBody()
  local map = current
  if not (map and Crypt.matches(map)) then Crypt.lastBatches = 0 return 0 end
  local list = Crypt.lanterns(map)
  if #list == 0 then Crypt.lastBatches = 0 return 0 end
  if not loadFlame() then Crypt.lastBatches = 0 return 0 end
  builder = builder or V.require("ParticleMesh").newBuilder(Crypt.LIMIT * 4)
  local mesh, batches = builder:buildCards(#list,
                                           function(i)
                                             local l = list[i]
                                             -- the card sits a little above
                                             -- the flame point, where the
                                             -- pool's light is centred
                                             return { x = l.x, y = l.y + 1.5, z = l.z }
                                           end,
                                           emitFlame)
  if not mesh then Crypt.lastBatches = 0 return 0 end
  -- translucent: alpha blend, depth TEST on, depth WRITE off -- and lit by
  -- nothing: flattened toward the glow for this draw only, put back after
  local g = love.graphics
  local pm, pa = g.getBlendMode()
  g.setBlendMode("alpha")
  pcall(Voxel3D.flatten, Crypt.FLAME_GLOW, Crypt.FLAME_FLAT)
  local drew = Voxel3D.drawParticles(mesh, nil, batches, false)
  pcall(Voxel3D.flatten, nil)
  g.setBlendMode(pm, pa)
  Crypt.lastBatches = drew
  return drew
end

function Crypt.drawWorld()
  local ok, err = pcall(drawWorldBody)
  if ok then return err or 0 end
  Crypt.drawErrors = Crypt.drawErrors + 1
  Crypt.drawError = "drawWorld: " .. tostring(err)
  return 0
end

function Crypt.dropGPU()
  if flameImg and flameImg ~= false and flameImg.release then
    pcall(flameImg.release, flameImg)
  end
  flameImg = nil
  for file, img in pairs(stoneImgs) do
    if img and img.release then pcall(img.release, img) end
    stoneImgs[file] = nil
  end
  if builder and builder.release then pcall(builder.release, builder) end
  builder = nil
end

return Crypt
