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

-- ------- which map is being drawn
--
-- Pushed in from VoxelScene rather than pulled: this file has no business
-- knowing about the overworld, and the frame already knows what it is
-- drawing. Passages are interiors and draw no neighbours, so one answer per
-- frame is the whole truth here -- which would NOT hold outdoors, where a
-- frame carries a map and up to four of its neighbours on different sheets.
local active = false

local function matches(map)
  local img = map and map.tileset and map.tileset.image
  if type(img) ~= "string" then return false end
  img = img:lower()
  for _, name in ipairs(FloorArt.TILESETS) do
    if img:find(name, 1, true) then return true end
  end
  return false
end

function FloorArt.setMap(map)
  active = matches(map)
  return active
end

function FloorArt.active()
  return active
end

FloorArt._matches = matches   -- named for the suite

-- ------- the file

local artImage = nil    -- Image | false ("there is none") | nil (not tried)
local artBlank = nil

local function loadArt()
  if artImage ~= nil then return artImage or nil end
  local okA, Assets = pcall(require, "src.render.Assets")
  if not okA or not Assets then
    artImage = false
    return nil
  end
  local path = V.path .. "/" .. FloorArt.ASSET_DIR .. FloorArt.ASSET_FILE
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
  -- MIRROREDREPEAT, and it is not a preference. The shipped art does not
  -- tile: measured across the wrap, its left edge differs from its right by
  -- 35/255 mean absolute, and no crop of it fixes that (a sweep from 240 to
  -- 1024 bottomed out at 17). Under a plain repeat that lands as a hard seam
  -- ruled across the floor every cycle -- on a 256-pixel cycle, a line every
  -- sixteen cells, down a corridor whose whole job is to be long. Mirroring
  -- costs the pattern its handedness and costs the seam its existence; on a
  -- lattice that trade is free.
  pcall(img.setWrap, img, "mirroredrepeat", "mirroredrepeat")
  artImage = img
  return img
end

function FloorArt.art()
  return loadArt()
end

-- 1 only when there is art AND the map being drawn wears the right sheet.
function FloorArt.on()
  return (active and loadArt()) and 1 or 0
end

function FloorArt.scale()
  local n = tonumber(FloorArt.ART_SCALE) or 256
  if n < 8 then n = 8 end
  return n
end

function FloorArt.mix()
  local n = tonumber(FloorArt.ART_MIX) or 0.55
  if n < 0 then n = 0 elseif n > 1 then n = 1 end
  return n
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
-- assets/floor/floor.png if it appeared or changed on disk.
function FloorArt.dropGPU()
  if artImage and artImage ~= false and artImage.release then
    pcall(artImage.release, artImage)
  end
  artImage = nil
  if artBlank and artBlank ~= false and artBlank.release then
    pcall(artBlank.release, artBlank)
  end
  artBlank = nil
end

return FloorArt
