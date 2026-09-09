-- Voxel world mode: the AIR of the Poke Mart -- what the shop is lit by,
-- what its surfaces are made of, and the rows that turn both off.
--
-- lib/ShopKit.lua stands the room; this is the other half, the half that
-- runs every frame. A Gen 1 interior is lit flat -- every surface the same
-- white -- and under that a shop is a diagram of a shop. Three things fix
-- it, and they are the crypt's three (lib/Crypt.lua) pointed the other way:
--
--   AMBIENT   held DOWN and cooled a little, so the tubes have something to
--             push against. Not dark: a konbini is the brightest room in
--             any of these towns, and the point of holding it down is only
--             that a light must be able to be BRIGHTER than the room.
--   TUBES     eight fluorescent battens as the scene shader's eight point
--             lights -- cool, wide, overlapping into an even wash with soft
--             pools under the fixtures. Their SITES are authored here and
--             the kit puts a lit diffuser at each one it can reach, so a
--             pool always has a tube over it (the crypt's rule).
--   SURFACES  the photographs in assets/shop/ on the walls, the steel and
--             the laminate, and the tiled floor through lib/FloorArt.lua.
--             The sheet the kit builds against (assets/shop/shop_sheet.png)
--             is banded by material, so the fragment stage picks which
--             photograph to modulate from the texel's v alone.
--
-- The samplers are NOT new. CRYPT_MATS already binds five, which with
-- sunMap, waterArt, floorArt, glassMask and MainTex is the eight GLES2
-- guarantees; a sixth would refuse the link and take the whole voxel mode
-- with it. So the shop borrows the crypt's two pairs -- `stoneArt` carries
-- the wall's plaster, `graniteArt` the shop's hard surfaces -- and the
-- branch that reads them is chosen by `shopOn` rather than by luminance.
--
-- Nothing here is extracted from the ROM.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local Shop = {}

-- ------------------------------------------------------------- the rows --
--
-- The SHOP row lives here rather than in the kit because both halves answer
-- to it: on CLASSIC the kit stamps nothing (and lib/RoomKit.lua's old
-- fixtures stand again, whole) AND the scene lights the room flat, lays no
-- tiles and carries no materials.
Shop.setting = ModSetting.new("shop", "SHOP",
                              { "new", "classic" },
                              { "NEW", "CLASSIC" })

function Shop.enabled()
  local ok, v = pcall(Shop.setting.get, Shop.setting)
  if not ok then return true end
  return v ~= "classic"
end

-- The SHOP-FX row: the shader's share -- the photographed surfaces, the
-- relief the tubes rake across, the sheen on the floor and the bloom that
-- makes a diffuser a light rather than a pale rectangle. Its own row
-- because it is the costlier half, exactly as CRYPT-FX is.
Shop.fxSetting = ModSetting.new("shopfx", "SHOP-FX",
                                { "on", "off" }, { "ON", "OFF" })

function Shop.fxOn()
  if not Shop.enabled() then return false end
  local ok, v = pcall(Shop.fxSetting.get, Shop.fxSetting)
  if not ok then return true end
  return v ~= "off"
end

-- ------------------------------------------------------------- the maps --
--
-- The MART tileset is not enough on its own: the Indigo Plateau's Pokemon
-- Centre is drawn on it too (see lib/WaterMap.lua, which had to learn the
-- same thing to keep a pond out of it). A shop is a map on that sheet whose
-- name says MART, which is the same test lib/MiniMap.lua's landmarkKind
-- makes. The eight town Marts are ONE room -- their tile grids hash
-- identically -- so there is no per-map table of sites, only one.
Shop.TILESET = "MART"

function Shop.onSheet(map)
  local ts = map and map.tileset
  local id = ts and ts.id
  return type(id) == "string" and id == Shop.TILESET
end

function Shop.matches(map)
  if not Shop.enabled() then return false end
  if not Shop.onSheet(map) then return false end
  local id = map and map.id
  return type(id) == "string" and id:find("MART", 1, true) ~= nil
end

-- ------------------------------------------------------------ the light --
--
-- Sites in WORLD px on the room's own 128x128 plan (lib/ShopKit.lua's
-- coordinates are the map's): three along the soffit over the product
-- wall, two battens a side on the walls, one over the entrance. Eight,
-- which is the shader's slot count exactly, so none is ever dropped.
-- The centres of lib/ShopKit.lua's PANELS and BATTENS. The two tables are
-- read TWICE, once here for the shader's point lights and once by the kit
-- for the fixture geometry, so a pool always has a diffuser over it.
Shop.SITES = {
  {  22, 38 }, {  58, 38 }, { 106, 38 },     -- the ceiling panels
  {   2, 58 }, { 126, 58 },                  -- the aisle battens
  {   2, 90 }, { 126, 90 },                  -- the checkout battens
  {  64, 26 },                               -- inside the cold case
}

-- 84 against a 128-px room is deliberate: two adjacent fixtures both reach
-- every point between them, so the shader's saturating sum lands the whole
-- floor near its ceiling. A konbini has no dark BETWEEN its lights, and
-- that is the one crypt number that must not be reused.
Shop.RADIUS = 84
Shop.POWER = 1.50             -- flat, not hot
Shop.HEIGHT = 24              -- world y of a diffuser
Shop.COLOR = { 0.94, 0.97, 1.00 }    -- 5000 K at the rim of a pool
Shop.CORE = { 1.00, 1.00, 0.98 }     -- near-white under the panel
Shop.LIMIT = 8
-- the ambient the tubes push against: bright, but a shade under white and
-- barely cooled, because a room already at full white cannot be lit
-- MEASURED, and the single most consequential number in this file.
--
-- At 0.90 the room was CLIPPING: 27.8 % of its pixels had a channel pinned
-- at 255 and 14.0 % were pure #FFFFFF, including the most common colour of
-- both the white wall (31.9 %) and the floor (12.8 %). The correlation
-- between "this patch is clipped" and "this patch has no shading ramp left"
-- came back at -0.944 -- an unclipped patch carried a ramp of 30.9 levels,
-- a clipped one 4.7 (assets/docs/shop/SILHOUETTE_AUDIT.md).
--
-- So the room was not flat because it was modelled flat. The engine was
-- computing the shading and the exposure was erasing it, and every fix
-- aimed at the models -- the chamfers, the per-SKU statures, the corner AO,
-- the contact field, the sun pass -- was landing inside a white that could
-- not get any whiter. THIS is what had to come down first; nothing else in
-- the room can be judged until it does.
--
-- 0.74 puts the pale plaster near 235 rather than over 255, which leaves
-- the top twenty levels for the things that are genuinely brighter than the
-- room: the diffusers, the cooler's glow, the specular off the floor.
-- 0.80. 0.74 was the number that broke the clip (27.8 % -> 3.1 %) and it
-- overshot: with the sun pass now doing real work the room measured a mean
-- of 114 with the south-east corner falling away, and a konbini is the
-- brightest room in any of these towns. Six points back puts the mean near
-- 128 and still leaves clipping around 2 % -- there is headroom, and the
-- dark in the frame should be SHADOW, not underexposure.
Shop.AMBIENT = 0.80
Shop.COOL = { 0.98, 1.00, 1.02 }
-- a 100 Hz hum on the phase, tiny: a fluorescent tube is not a candle and
-- anything readable here reads as a fault, not as a shop
Shop.FLICKER_RATE = 0.6

function Shop.lights(map, wx, wz)
  wx, wz = tonumber(wx) or 0, tonumber(wz) or 0
  local out = {}
  local ox, oz = Shop.origin(map)
  for _, s in ipairs(Shop.SITES) do
    local x, z = ox + s[1], oz + s[2]
    local dx, dz = x - wx, z - wz
    out[#out + 1] = { x = x, z = z, radius = Shop.RADIUS,
                      power = Shop.POWER, d2 = dx * dx + dz * dz }
  end
  table.sort(out, function(a, b) return a.d2 < b.d2 end)
  for i = #out, Shop.LIMIT + 1, -1 do out[i] = nil end
  return out
end

-- Where the room's own (0,0) stands in the map. The plan is matched at tile
-- (0,0) in every one of the eight, so this is zero -- it exists so a mod
-- that moves the room does not have to move eight tables of lights.
function Shop.origin(_)
  return 0, 0
end

-- How much of the room's light is left when the street outside has gone.
-- A konbini's tubes never change, but its whole south wall is glass and a
-- door, and by night that wall stops giving and starts taking.
Shop.NIGHT_K = 0.86
-- ...and what the room is lit BY once it does: fluorescent alone, which
-- runs green against daylight. The COOL cast above is the daylit mix.
Shop.TUBE_CAST = { 0.945, 1.005, 0.975 }

-- The interior's tint: held to the shop's share, cooled a touch, and
-- MOVED BY THE HOUR.
--
-- DayNight is outdoor-only by design -- a cave at midnight is as dark as a
-- cave at noon -- so indoors it hands back the same untinted world every
-- frame, and the probe measured this room's day, dusk and night frames as
-- identical to three decimal places. That is right for a cave and wrong
-- for a shop: the whole south wall of a Mart is its own front, and the
-- difference between a konbini at noon and the same konbini at 2 a.m. is
-- one of the most legible things about it.
--
-- So the hour is fetched here rather than taken from the tint. Two terms,
-- both small: the room dims by a seventh, and its cast walks from the
-- daylit mix toward the tubes' own green. Nothing swings far enough to
-- change what is readable -- a shop must stay the brightest room in town.
function Shop.ambient(map, tint)
  if type(tint) ~= "table" or not tint[3] then tint = { 1, 1, 1 } end
  local k, c = Shop.AMBIENT, Shop.COOL
  local day = 1
  local okD, DayNight = pcall(V.require, "DayNight")
  if okD and DayNight then
    local okT, t = pcall(DayNight.time)
    if okT and type(t) == "number" then
      -- strengthAt alone is NOT the day: DayNight.bodyAt swaps to the MOON
      -- past DAY_LEN and reports its elevation, so a strength of 1 at
      -- t = 900 means the moon is high, and the first version of this made
      -- midnight exactly as bright as noon (probe: day and night came back
      -- at the same tint to three decimals while only dusk moved). The
      -- third return says which body it is; the moon does not light a shop.
      local okB, _, _, isMoon = pcall(DayNight.bodyAt, t)
      if okB and isMoon then
        day = 0
      else
        local okS, sN = pcall(DayNight.strengthAt, t)
        if okS and type(sN) == "number" then day = sN end
      end
    end
  end
  if day < 0 then day = 0 elseif day > 1 then day = 1 end
  k = k * (Shop.NIGHT_K + (1 - Shop.NIGHT_K) * day)
  local out = {}
  for i = 1, 3 do
    local cast = c[i] + (Shop.TUBE_CAST[i] - c[i]) * (1 - day)
    out[i] = tint[i] * k * cast
  end
  return out
end

-- ------------------------------------------------------- the FX numbers --

Shop.SPEC = 0.72              -- the sheen under a tube: the floor is polished
-- RayFX's ambient occlusion: softer than the crypt's. A shop's corners are
-- shelves and cabinet returns, and this room has a great many of them; at
-- the crypt's 1.75 every shelf lip drew a black line under itself.
-- 0.85, walked down from 1.30. The crypt's own notes record the same walk
-- (2.9 -> 2.0 -> 1.75) as its stones stood proud; a shop has far more
-- one-voxel edges than a crypt -- every shelf board, every mullion, every
-- box gap -- and a bounce-lit room genuinely has softer corners. At 1.30
-- the goods on an overhung shelf went to black.
-- 0.95, walked back UP, and the reason is worth keeping: this number was
-- taken from 1.30 down to 0.55 because "at 1.30 the goods on an overhung
-- shelf went to black" -- which was true, and was not the occlusion's
-- fault. The room was clipping at 27.8 % then, so its whole shading ramp
-- lived in the four levels under 255 and ANY occlusion crushed. With the
-- exposure fixed the ramp is 39 levels and the corners can have their
-- weight back. Occlusion is what gives a voxel room volume; a shop with
-- none is a set of coloured planes.
Shop.AO = { power = 0.95, range = 8 }
-- ------- the sun that is not a sun
--
-- NOTHING IN THE ROOM TOUCHED THE FLOOR, and this is the line that did it.
-- The eight tubes are the scene shader's POINT lights, and a point light
-- here lights a surface without occluding one -- so with the sun pass at
-- zero the room had no occluder at all and every fixture floated over a
-- texture. It is measurable rather than a matter of taste: the floor under
-- a gondola's own kick and the floor four voxels clear of it came back the
-- same luminance (probe_out_shop, the runs before this one).
--
-- The pass costs nothing to turn back on. ChunkMesher.spriteGroups goes
-- into ShadowMap.drawGroup whether this number is 0 or 0.34, so the room
-- was already being rendered into the shadow map every frame and then
-- multiplied out.
--
-- A third of the street's alpha, because what this is standing in for is
-- not weather: it is the soft pool a shelf drops on a pale polished floor
-- under a ceiling of battens.
-- 0.85. It went 0 -> 0.34 -> 0.60 -> here, and only the last step was a
-- taste call: the first two were made while the pass could not resolve the
-- room (ShadowMap.clamp, 1.30 world px per texel and 4.52 px of slack) and
-- were really measuring a blur. With the frustum capped to the room the
-- A/B against 0 moves 25.3 % of the frame, so there is a real shadow to
-- set the strength OF -- and at 0.60 its mean delta was 3.9 levels, which
-- is a shadow you can measure and cannot see.
Shop.SHADOW_SCALE = 0.85
-- And its SHEAR. The world's noon is (-0.85, -0.55) -- well off vertical,
-- because outdoors a vertical sun flattens every roof in the town. Indoors
-- that same shear throws a gondola's shadow four metres up the aisle and
-- reads as late afternoon through a window this room does not have. Every
-- light in here hangs at the ceiling, so the shadow falls nearly straight
-- down; the small offset that remains is what keeps a fixture's shadow
-- from hiding underneath it entirely at this camera's 27 degrees.
-- MEASURED, twice. At (-0.26, -0.17) -- near vertical, which is what a
-- ceiling of battens physically is -- the sun pass was working and
-- invisible: differencing a run against SHADOW_SCALE = 0 moved 10.3 % of
-- the frame with a peak delta of 249, and almost all of it landed on the
-- fixtures' own vertical faces. A vertical sun puts a fixture's shadow
-- UNDERNEATH the fixture, where at 27 degrees of pitch nothing can see it.
--
-- So this is a compromise between the physics and the camera: steep enough
-- to still read as ceiling light rather than as afternoon through a wall
-- the room does not have, slanted enough that a gondola's pool clears its
-- own kick and lands on floor the camera can see. The world's own noon is
-- (-0.85, -0.55); this is about six tenths of it.
Shop.SUN = { kx = -0.52, kz = -0.34 }
-- the bloom: only the diffusers and the cooler glow are over this, so the
-- room does not haze. Weaker than the crypt's -- a fluorescent tube has a
-- hard edge, a candle does not.
-- 0.90 rather than the crypt's 0.82 is not a taste call: at ambient 0.86 a
-- threshold of 0.82 puts the walls, the floor and every shelf board over
-- the line and the frame goes to milk. Only the emissive classes bloom.
Shop.BLOOM = { threshold = 0.90, strength = 0.30, div = 4, passes = 1 }
Shop.RAYS = nil               -- no god rays off a ceiling panel
-- exposure 0.94, not 1.0: the last few per cent of the clip, taken after
-- the tone curve rather than before it, so the diffusers keep their bloom.
Shop.GRADE = { exposure = 0.94, vignette = 0.22, grain = 0.008, tone = 0.30,
               split = 0.30 }

-- The surfaces (see the uniforms in lib/Voxel3D.lua). `wall` goes into the
-- crypt's stoneArt pair and `hard` into its graniteArt pair; which of them
-- a fragment reads is decided by the sheet band it wears, not by its
-- luminance -- see `shopOn` in the scene shader.
-- CHOSEN ON RELATIVE SD, not on what the photograph is of. The shader
-- normalises each albedo's MEAN away, so the only thing that decides
-- whether a surface reads on screen is its sd/mean -- how deep its own
-- modulation is. Measured over the set (tools/surface_pick.py depth):
-- wall_paint 0.014, counter_wood 0.033, metal_shelf 0.056, floor_tile
-- 0.105 -- and floor_tile was the ONLY one visible in any shipped frame.
-- wall_paint at 1.4 % is plus or minus three levels, which is why the
-- room's walls read as moulded plastic no matter how the models are cut.
--
--   wall -> ceiling_tile   an even roller stipple at 0.079. It is sold as
--                          an interior ceiling, and a rolled emulsion wall
--                          is the same surface at the same scale.
--   hard -> steel_brushed  0.088 and measurably COOL (R-B -0.027), which
--                          is the fixtures' half of the palette split
--                          arriving in the photograph as well as the sheet.
Shop.MATS = { dir = "assets/shop/",
              -- Poly Haven CC0, graded for the shop: assets/shop/README.md
              wall = "ceiling_tile.jpg", wallNorm = "ceiling_tile_n.jpg",
              hard = "steel_brushed.jpg", hardNorm = "steel_brushed_n.jpg",
              wrap = "repeat",
              -- world px per cycle of the wall photograph. 96 was chosen
              -- so the plaster never visibly repeats -- true, and it also
              -- blew the grain up to six map cells across, which on the
              -- deeper ceiling_tile stipple came out as cast concrete
              -- rather than as rolled emulsion. 30 puts a stipple cell at
              -- roughly a centimetre, which is what paint looks like; it
              -- repeats every two map cells and at that size no one can
              -- see that it does.
              -- mix 0.52, not 0.80: ceiling_tile modulates 0.079 against
              -- wall_paint's 0.014, so the same mix that was invisible on
              -- the old photograph came out as cast concrete on the new
              -- one. The mix is the dial that has to move whenever the
              -- material's depth does.
              -- 16, not 30: at 30 a stipple cell came out three or four
              -- screen pixels across on the wall caps and read as gravel.
              -- The photograph repeats every map cell now and no one can
              -- see that it does, because the thing repeating is a speck.
              scale = 16, mix = 0.42, bump = 0.50,
              hemi = 0.34 }

local matImgs = {}            -- file -> Image | false

local function loadMat(file, wrap)
  local have = matImgs[file]
  if have ~= nil then return have or nil end
  local img = nil
  local okA, Assets = pcall(require, "src.render.Assets")
  if okA and Assets then
    local path = V.path .. "/" .. Shop.MATS.dir .. file
    local okE, exists = pcall(Assets.exists, path)
    if okE and exists then
      local ok, i = pcall(Assets.image, path)
      if ok and i then
        pcall(i.setFilter, i, "linear", "linear")
        local w = wrap or Shop.MATS.wrap
        pcall(i.setWrap, i, w, w)
        img = i
      end
    end
  end
  matImgs[file] = img or false
  return img
end

-- The materials for this frame, in the shape lib/Voxel3D.lua's `stone`
-- uniform block expects, or nil when the row is off or the files are not
-- there (drop-in contract: delete them and the room keeps its geometry and
-- loses only the grain).
function Shop.matsFor()
  if not Shop.fxOn() then return nil end
  local art = loadMat(Shop.MATS.wall)
  if not art then return nil end
  local M = Shop.MATS
  return { art = art, norm = loadMat(M.wallNorm),
           granite = loadMat(M.hard) or art,
           graniteNorm = loadMat(M.hardNorm),
           scale = M.scale, mix = M.mix, bump = M.bump, hemi = M.hemi,
           shop = true }
end

function Shop.dropGPU()
  for k in pairs(matImgs) do matImgs[k] = nil end
end

-- What the post pass needs this frame: the same shape lib/Crypt.lua hands
-- lib/Bloom.lua, with the tubes standing in for the lanterns.
function Shop.bloomOpts(map, w, h)
  local o = { threshold = Shop.BLOOM.threshold,
              strength = Shop.BLOOM.strength,
              div = Shop.BLOOM.div, passes = Shop.BLOOM.passes,
              rays = Shop.RAYS, grade = Shop.GRADE, lights = {} }
  return o, w, h
end

return Shop
