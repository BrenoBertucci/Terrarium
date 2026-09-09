-- Voxel world mode: a real surface on a painted floor.
--
-- The underground passages between cities are a checked pink floor: a flat
-- colour with a lattice ruled over it. Read at 2D scale that is tiling;
-- standing in it in a diorama, at four to twelve screen pixels per world
-- pixel, it is a coloured rectangle with lines on it -- the one class of
-- ground with no grain of its own, and the one you spend a whole corridor
-- looking at. Drop a PNG at `assets/floor/floor.png` and it is laid over
-- that class in world XZ, so the floor keeps still under the camera and
-- carries a texture at the size the camera is actually looking at it.
--
-- Same drop-in contract as assets/water/ and assets/ground/: replace the
-- file and it is used, delete it and the tileset comes back. No constant,
-- no rebuild.
--
-- WHICH FLOOR, and this is the part that is not free. There is no tile id in
-- the fragment stage -- terrain is one mesh sampling one atlas -- so the
-- class has to be recognised from what IS there. Four facts, and each one
-- was bought with a measurement rather than a guess:
--
--   THE TILESET  the outer gate, and the one that actually does the work.
--                The floor lives on the UNDERGROUND sheet
--                (assets/generated/tilesets/underground.png, 128x16), and
--                one of its two colours -- (247, 82, 49) -- is ALSO the
--                flower in the overworld sheet. Colour alone would have
--                carpeted every flowerbed in Kanto. The tileset is named on
--                the map def, so this costs one string compare per map and
--                nothing per pixel.
--   THE COLOUR   the atlas texel, before shade and before the hour's light,
--                inside one of TWO boxes. Two, not one: the field
--                (255, 156, 197) and the lattice ruled over it
--                (247, 82, 49) are far apart, and a single box wide enough
--                to hold both would swallow most of the sheet.
--   FACING UP    vUp, which the meshers already carry in the sign of
--                VertexShade -- costs nothing, drops every wall.
--   LOW DOWN     vWorld.y under a threshold, read BEFORE the V-curve bends
--                the world down. Measured: the passage floor stands at 0.
--
-- The first cut had only the colour and the height, tuned against the
-- OVERWORLD sheet, and it landed on a Fuchsia roof -- same pinks, wrong
-- building, wrong sheet entirely. The height sweep that caught it is
-- tests/floor_art_probe.lua; the reading that fixed it is
-- tests/gate_floor_probe.lua.
--
-- ------- more than one floor
--
-- The tower of graves is the second tenant (lib/CryptKit.lua stands its
-- floors as a crypt): its floor is the CEMETERY sheet's white lattice,
-- which under a crypt's candlelight should be flagstone. So the facts above
-- are a PROFILE -- a sheet, a file, a scale, a mix, a height cap and the
-- colour boxes -- and there is a list of them. One map is drawn per frame
-- indoors, and every profile here is an interior, so setMap picks the one
-- profile the frame needs and the shader's single set of uniforms carries
-- it. The passage's numbers are the first profile, unchanged; the crypt's
-- boxes are wide open (everything flat and low on that sheet IS the floor)
-- and its mix is high, because a lattice that stays white under a candle
-- is the whole thing this is here to fix.
--
-- The tileset list and the boxes are data rather than shader source because
-- they are facts about somebody's map set and somebody's palette rather than
-- about the renderer. A total conversion retunes a name and a few vectors.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local FloorArt = {}

FloorArt.ASSET_DIR = "assets/floor/"
FloorArt.ASSET_FILE = "floor.png"

-- Tileset image paths this applies to, matched as a lowercase SUBSTRING of
-- the map's own `tileset.image`. A list rather than a single name so a mod
-- that splits the passages across sheets, or renames one, keeps working.
-- (The passage profile's list; see PROFILES for the rest.)
FloorArt.TILESETS = { "underground" }

-- World pixels one full cycle of the art covers. 256 = sixteen map cells,
-- and the art's own lattice is sixteen squares across -- so one square of
-- the texture lands on one 16-pixel cell of the map, and the drawn grid sits
-- on the grid the world is actually built on. Change this and the two drift
-- apart; that is a number to keep, not a taste.
FloorArt.ART_SCALE = 256

-- How far toward the art, 0..1. Lower than water's because paving has less
-- to hide behind: the tileset's own lattice is what says which cell you are
-- standing on, and a floor that loses it loses the grid the whole diorama is
-- measured in.
FloorArt.ART_MIX = 0.55

-- Highest a floor may be, in world pixels, pre-curve. Measured at 0 in every
-- passage (groundAt in tests/gate_floor_probe.lua); 4 clears a step and
-- nothing else. Belt and braces next to the tileset gate, and cheap.
FloorArt.Y_MAX = 4.0

-- The two colour boxes, in 0..1, against the ATLAS TEXEL -- not the shaded
-- pixel, so the class does not change colour at dusk and stop being
-- recognised half way through an evening. Read off the live atlas:
--
--   (255, 156, 197)  the field,   x200 texels
--   (247,  82,  49)  the lattice, x104 texels
FloorArt.KEY_LO = { 0.92, 0.52, 0.68 }   -- the field
FloorArt.KEY_HI = { 1.00, 0.70, 0.86 }
FloorArt.KEY2_LO = { 0.88, 0.24, 0.10 }  -- the lattice
FloorArt.KEY2_HI = { 1.00, 0.42, 0.30 }

-- ------- the profiles
--
-- The passage reads its numbers LIVE off the fields above (the suite
-- retunes ART_MIX and reads it back); the crypt carries its own. `keys`
-- is { { lo, hi }, { lo, hi } } -- the two boxes.
FloorArt.PROFILES = {
  { name = "passage", tilesets = FloorArt.TILESETS, file = "floor.png" },
  { name = "crypt", tilesets = { "cemetery" }, file = "crypt.jpg",
    -- Poly Haven's monastery_stone_floor (CC0; see assets/stone/README.md)
    -- with its relief (a DirectX tangent-space normal map), and a plain
    -- repeat: this art tiles, and a mirror would flip the relief's x at
    -- every fold
    normal = "crypt_n.jpg", wrap = "repeat",
    scale = 256, mix = 0.86, yMax = 1.5,
    -- wide open but for black: on this sheet everything flat and this low
    -- is the floor -- except the dark beyond the walls, which the void
    -- cells wear as the sheet's own black and which must stay dark. The
    -- SGB's black is 49/255 (0.19), so the box starts well above it; the
    -- floor's own darkest texel is the lattice's grey, up past 0.7.
    keys = { { { 0.30, 0.30, 0.30 }, { 1, 1, 1 } },
             { { 0.30, 0.30, 0.30 }, { 1, 1, 1 } } },
    -- the crypt's flagstones belong to the CRYPT row (lib/Crypt.lua): on
    -- CLASSIC the floor is the tileset's own lattice, as it was
    when = function()
      local ok, Crypt = pcall(V.require, "Crypt")
      return ok and Crypt and Crypt.enabled() or false
    end },
  -- The Poke Mart's floor (lib/ShopKit.lua, the SHOP row). The tile art
  -- the game ships here is a white field with a grey lattice ruled over
  -- it -- the same "coloured rectangle with lines on it" the passage was,
  -- and the surface a shopper spends the whole room looking down at.
  -- Poly Haven's floor_tiles_08 (CC0; see assets/shop/README.md), read
  -- from the shop's own directory rather than copied here.
  --
  -- `ids` is load-bearing: the Centre's lobby is on this same sheet.
  -- The boxes are the atlas's own two greys -- the field at 255 and the
  -- lattice at 170, plus the darker 85/170 pair the plan uses along the
  -- west and at the door -- and nothing below 0.26, which keeps the
  -- entrance mat and every dark texel of the fixtures out of it.
  { name = "shop", tilesets = { "pokecenter" }, ids = { "MART" },
    -- BUILT, not picked: tools/shop_floor.py lays a drawn grout grid over
    -- the graded vinyl. Neither photograph on its own is a shop floor --
    -- floor_tiles_08 has the grid and gives every tile a different tone,
    -- which at this scale reads as staining and made the room look like a
    -- weathered pavement; linoleum_brown is the right surface and has no
    -- seam anywhere, so the floor loses the one grid that tells the eye
    -- how big the room is. Same mean (0.621) as the tile it replaces, so
    -- nothing downstream needs re-deriving.
    dir = "assets/shop/", file = "shop_floor.jpg",
    normal = "shop_floor_n.jpg", wrap = "repeat",
    -- 32 world px per cycle, and the photograph is five ceramic tiles
    -- across, so ONE TILE IS 6.4 world px = 64 cm. That is a shop tile.
    -- It shipped at 96, which put a tile at one and a fifth MAP CELLS --
    -- 1.9 m across, a slab no building has ever been floored with, and
    -- the single loudest reason the room read as a scale model: a floor
    -- whose grid is coarser than the furniture standing on it tells the
    -- eye the furniture is small, not that the tiles are big.
    -- (1 map cell = 16 world px = 16 voxels = 1.6 m; see ART_DIRECTION.)
    scale = 32, mix = 0.88, yMax = 1.5,
    -- Wide open above black, like the crypt's, and NOT the two grey boxes
    -- this profile shipped with first. Those were read off the raw atlas
    -- (a white field at 255 with a grey lattice at 170) and in game the SGB
    -- palette recolours shade 1 to the TOWN's own colour -- Viridian's is a
    -- pale green -- so the boxes matched nothing and the floor came out
    -- green (probe_out_shop/shop_room.png, first run). The tileset id gate
    -- above is what does the work; everything flat and low on this sheet is
    -- the floor, except the entrance mat, which is darker than 0.30.
    keys = { { { 0.30, 0.30, 0.30 }, { 1, 1, 1 } },
             { { 0.30, 0.30, 0.30 }, { 1, 1, 1 } } },
    when = function()
      local ok, Shop = pcall(V.require, "Shop")
      return ok and Shop and Shop.enabled() or false
    end },
}

-- ------- which map is being drawn
--
-- Pushed in from VoxelScene rather than pulled: this file has no business
-- knowing about the overworld, and the frame already knows what it is
-- drawing. Passages and crypts are interiors and draw no neighbours, so one
-- answer per frame is the whole truth here -- which would NOT hold outdoors,
-- where a frame carries a map and up to four of its neighbours on different
-- sheets.
local active = false          -- the profile the frame wears, or false

-- Two tilesets can share one SHEET: the Mart and the Pokemon Centre are
-- both drawn on pokecenter.png, and a profile keyed on the image alone
-- would tile the Centre's lobby with the shop's floor. `ids` is the
-- refinement -- the tileset's own id, which the map def carries.
local function idOk(p, tsid)
  if not p.ids then return true end
  for _, want in ipairs(p.ids) do
    if want == tsid then return true end
  end
  return false
end

local function profileFor(map)
  local img = map and map.tileset and map.tileset.image
  if type(img) ~= "string" then return nil end
  img = img:lower()
  local tsid = map and map.tileset and map.tileset.id
  for _, p in ipairs(FloorArt.PROFILES) do
    for _, name in ipairs(p.tilesets or {}) do
      if img:find(name, 1, true) and idOk(p, tsid) then
        -- a profile may answer to a row of its own (`when`)
        if p.when then
          local ok, on = pcall(p.when)
          if not (ok and on) then return nil end
        end
        return p
      end
    end
  end
  return nil
end

local function matches(map)
  return profileFor(map) ~= nil
end

function FloorArt.setMap(map)
  active = profileFor(map) or false
  return active and true or false
end

function FloorArt.active()
  return active and true or false
end

function FloorArt.profile()
  return active or nil
end

FloorArt._matches = matches   -- named for the suite

-- ------- the file

local images = {}       -- file -> Image | false ("there is none")
local artBlank = nil

-- `dir` lets a profile keep its art with the rest of its own surfaces
-- (the shop's tile photograph is one of the four in assets/shop/, and
-- shipping a second copy of a 1024px JPEG under assets/floor/ to satisfy
-- a hard-coded directory would be a quarter of a megabyte of nothing).
-- The cache key is the full relative path for the same reason.
local function loadArt(file, wrap, dir)
  file = file or FloorArt.ASSET_FILE
  dir = dir or FloorArt.ASSET_DIR
  local key = dir .. file
  local have = images[key]
  if have ~= nil then return have or nil end
  local okA, Assets = pcall(require, "src.render.Assets")
  if not okA or not Assets then
    images[key] = false
    return nil
  end
  local path = V.path .. "/" .. dir .. file
  local okE, exists = pcall(Assets.exists, path)
  if not (okE and exists) then
    images[key] = false
    return nil
  end
  local ok, img = pcall(Assets.image, path)
  if not (ok and img) then
    images[key] = false
    return nil
  end
  pcall(img.setFilter, img, "linear", "linear")
  -- MIRROREDREPEAT, and it is not a preference. The shipped art does not
  -- tile: measured across the wrap, its left edge differs from its right by
  -- 35/255 mean absolute, and no crop of it fixes that (a sweep from 240 to
  -- 1024 bottomed out at 17). Under a plain repeat that lands as a hard seam
  -- ruled across the floor every cycle -- on a 256-pixel cycle, a line every
  -- sixteen cells, down a corridor whose whole job is to be long. Mirroring
  -- costs the pattern its handedness and costs the seam its existence; on a
  -- lattice that trade is free.
  -- (a profile whose art tiles asks for the plain repeat instead)
  local w = wrap or "mirroredrepeat"
  pcall(img.setWrap, img, w, w)
  images[key] = img
  return img
end

-- The art the frame wears: the active profile's file, or the passage's
-- when nothing is active (the suite reads it without a map).
function FloorArt.art()
  local p = active or FloorArt.PROFILES[1]
  return loadArt(p and p.file or FloorArt.ASSET_FILE, p and p.wrap,
                 p and p.dir)
end

-- The active profile's relief (a tangent-space normal map), or nil.
function FloorArt.normal()
  local p = active
  if not (p and p.normal) then return nil end
  return loadArt(p.normal, p.wrap, p.dir)
end

-- A flat normal, always bound where a relief map is missing: the scene
-- shader decodes it to straight up. (Kept here rather than in the crypt's
-- module because Voxel3D loads this file and not that one.)
local flatNormal = nil
function FloorArt.flatNormal()
  if flatNormal == nil then
    local ok, img = pcall(function()
      local d = love.image.newImageData(1, 1)
      d:setPixel(0, 0, 0.5, 0.5, 1, 1)
      local i = love.graphics.newImage(d)
      pcall(i.setFilter, i, "nearest", "nearest")
      pcall(i.setWrap, i, "clamp", "clamp")
      return i
    end)
    flatNormal = (ok and img) or false
  end
  return flatNormal or nil
end

-- 1 only when there is art AND the map being drawn wears a profile's sheet.
function FloorArt.on()
  return (active and FloorArt.art()) and 1 or 0
end

function FloorArt.scale()
  local n = tonumber(active and active.scale) or tonumber(FloorArt.ART_SCALE)
            or 256
  if n < 8 then n = 8 end
  return n
end

function FloorArt.mix()
  local n = tonumber(active and active.mix) or tonumber(FloorArt.ART_MIX)
            or 0.55
  if n < 0 then n = 0 elseif n > 1 then n = 1 end
  return n
end

function FloorArt.yMax()
  return tonumber(active and active.yMax) or tonumber(FloorArt.Y_MAX) or 4.0
end

-- The two colour boxes of the active profile: lo1, hi1, lo2, hi2.
function FloorArt.keys()
  local k = active and active.keys
  if k then return k[1][1], k[1][2], k[2][1], k[2][2] end
  return FloorArt.KEY_LO, FloorArt.KEY_HI, FloorArt.KEY2_LO, FloorArt.KEY2_HI
end

-- Always-bound stand-in for the scene shader's floorArt sampler: an unbound
-- sampler is a driver-dependent crash rather than a fallback, the rule
-- waterArt and glassMask already follow. floorArtOn is the switch.
function FloorArt.blank()
  if artBlank == nil then
    local ok, img = pcall(function()
      local d = love.image.newImageData(1, 1)
      d:setPixel(0, 0, 1, 1, 1, 1)
      local i = love.graphics.newImage(d)
      pcall(i.setFilter, i, "nearest", "nearest")
      pcall(i.setWrap, i, "clamp", "clamp")
      return i
    end)
    artBlank = (ok and img) or false
  end
  return artBlank or nil
end

-- Hot reload / window resize: drop GPU objects so the next frame reloads
-- the files if they appeared or changed on disk.
function FloorArt.dropGPU()
  for file, img in pairs(images) do
    if img and img ~= false and img.release then pcall(img.release, img) end
    images[file] = nil
  end
  if artBlank and artBlank ~= false and artBlank.release then
    pcall(artBlank.release, artBlank)
  end
  artBlank = nil
  if flatNormal and flatNormal ~= false and flatNormal.release then
    pcall(flatNormal.release, flatNormal)
  end
  flatNormal = nil
end

return FloorArt
