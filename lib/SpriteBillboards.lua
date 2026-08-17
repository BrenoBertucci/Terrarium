-- Voxel world mode: characters as flat forward-facing sprite billboards.
--
-- Every character -- the player, NPCs, the ghosts standing on a neighbour
-- map -- is its CURRENT 2D sprite frame on a single flat quad. The sheets
-- carry real alpha and the shader discards it, so the quad cuts the
-- sprite's exact silhouette out of itself; no geometry is built from the
-- pixels and nothing about a sprite is voxelized.
--
-- That is deliberate. A sprite is a DRAWING, not an object seen from one
-- side: Gen 1's overworld figures are sprites with a fixed front-on
-- reading, and turning one into a solid -- whether a contoured slab or a
-- carved visual hull -- reconstructs a body the artist never drew and the
-- game never implied. It also had the mod ship a description of the ROM
-- art. One quad wearing the real frame is both more faithful and cheaper:
-- it needs no pixel access at all, only the sheet's dimensions.
--
-- The card always faces SOUTH -- the direction the 2D game implies -- and
-- only LEANS BACK, pivoting at its feet, by exactly the camera's pitch
-- (VoxelScene's billboardMatrix), so at every tilt level it reads face-on
-- like the flat game. Right-facing and the alternating walk step are
-- matrix mirrors, not extra meshes. UVs point into the live sheet image,
-- so RED++ OBP bakes, SGB palette bakes and sprite-replacing mods all
-- texture it with no rebuild.
--
-- The system now supports dynamic sprite dimensions with separate width and
-- height scaling, allowing for custom sprite sizes beyond the original 16x16 pixels.
-- Use def.scale for overall scaling, or def.heightScale for height-specific scaling.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Assets = require("src.render.Assets")
local Voxel3D = V.require("Voxel3D")

local SpriteBillboards = {}

local meshes = {}

-- One flat quad UV-mapped to a whole frame, with dynamic dimensions based on
-- the actual sprite size. A hair of inset keeps the sampler inside this frame
-- rather than picking up the neighbouring one along the shared edge.
local function buildCard(def, frame)
  local ok, img = pcall(Assets.image, def.image)
  if not (ok and img) then return nil end
  local iw, ih = img:getDimensions()
  
  -- Calculate frame dimensions dynamically from the sprite sheet
  -- Assume frames are arranged vertically in the sheet
  local frameCount = def.frames or 1
  local frameHeight = ih / frameCount
  local frameWidth = iw  -- Assume full width is used for one frame
  
  -- Get scale factor from sprite definition (defaults to 1.0)
  local scale = def.scale or 1.0
  
  -- Get height-specific scale factor (defaults to regular scale)
  local heightScale = def.heightScale or scale
  
  -- Calculate world dimensions (physical size in 3D space)
  local worldWidth = frameWidth * scale
  local worldHeight = frameHeight * heightScale
  
  local fy = frame * frameHeight
  if fy + frameHeight > ih then fy = 0 end
  
  -- Calculate UV coordinates with small inset to prevent bleeding
  local insetX = 0.02
  local insetY = 0.05
  local u0, u1 = insetX / iw, (frameWidth - insetX) / iw
  local v0, v1 = (fy + insetY) / ih, (fy + frameHeight - insetY) / ih
  
  -- Create quad vertices with world dimensions (scaled physical size)
  local verts = {
    { 0, 0, 0, u0, v1, 1 }, { worldWidth, 0, 0, u1, v1, 1 },
    { worldWidth, worldHeight, 0, u1, v0, 1 }, { 0, worldHeight, 0, u0, v0, 1 },
  }
  local indices = {}
  Voxel3D.pushQuad(indices, 0)
  local mesh = Voxel3D.newMesh(verts, indices)
  
  -- Apply high-quality texture filtering for scaled sprites
  if mesh and love and love.graphics then
    -- Enable linear filtering for smooth downsampling
    local filterMode = (scale < 1.0 or heightScale < 1.0) and "linear" or "nearest"
    pcall(function()
      mesh:setTexture(img)
      img:setFilter(filterMode, filterMode, 16) -- 16x anisotropic for quality
    end)
  end
  
  return mesh
end

-- The card for one (sprite def, frame index), or nil (headless / no
-- image), cached like every other derived GPU object.
--
-- The solid draw, the sun pass and the player's occlusion silhouette all
-- take THIS mesh. That the three agree is load-bearing, not tidiness: the
-- silhouette is drawn with the depth test INVERTED, so any self-overlap in
-- the mesh would read as "behind something" and repaint the figure on open
-- ground whether or not anything hides it; and the sun must see the same
-- outline the camera does, or a shadow stops matching what casts it.
function SpriteBillboards.mesh(def, frame)
  local key = def.image .. "#" .. frame
  if meshes[key] == nil then
    local ok, m = pcall(buildCard, def, frame)
    meshes[key] = (ok and m) or false
    
    -- Apply high-quality filtering to the image if mesh was created successfully
    if ok and m then
      local scale = def.scale or 1.0
      local heightScale = def.heightScale or scale
      local imgOk, img = pcall(Assets.image, def.image)
      if imgOk and img then
        SpriteBillboards.setHighQualityFiltering(img, scale, heightScale)
      end
    end
  end
  return meshes[key] or nil
end

-- Get the dimensions of a sprite frame for dynamic sizing
-- Returns: textureWidth, textureHeight, worldWidth, worldHeight
function SpriteBillboards.getSpriteDimensions(def, frame)
  local ok, img = pcall(Assets.image, def.image)
  if not (ok and img) then return 16, 16, 16, 16 end
  local iw, ih = img:getDimensions()
  
  -- Calculate frame dimensions dynamically from the sprite sheet
  local frameCount = def.frames or 1
  local frameHeight = ih / frameCount
  local frameWidth = iw  -- Assume full width is used for one frame
  
  -- Get scale factor from sprite definition (defaults to 1.0)
  local scale = def.scale or 1.0
  
  -- Get height-specific scale factor (defaults to regular scale)
  local heightScale = def.heightScale or scale
  
  -- Calculate world dimensions (physical size in 3D space)
  local worldWidth = frameWidth * scale
  local worldHeight = frameHeight * heightScale
  
  return frameWidth, frameHeight, worldWidth, worldHeight
end

-- Set high-quality texture filtering for scaled sprites
-- This ensures that sprites scaled down to 0.25 or less still look sharp
function SpriteBillboards.setHighQualityFiltering(img, scale, heightScale)
  if not (img and love and love.graphics) then return end
  
  local filterMode = "linear"
  local anisotropy = 16 -- Maximum anisotropic filtering for quality
  
  -- Use the smaller of the two scales for quality determination
  local effectiveScale = math.min(scale or 1.0, heightScale or 1.0)
  
  -- For very small scales, use maximum quality settings
  if effectiveScale < 0.5 then
    anisotropy = 16
  elseif effectiveScale < 0.75 then
    anisotropy = 8
  else
    anisotropy = 4
  end
  
  pcall(function()
    img:setFilter(filterMode, filterMode, anisotropy)
    -- Set mipmap filter for better downscaling quality
    img:setMipmapFilter(filterMode, 0.5) -- 0.5 sharpness balance
  end)
end

-- Get the recommended LOD bias for a sprite based on scale
function SpriteBillboards.getLodBiasForScale(scale)
  local lodBias = 0.0
  if scale < 0.25 then
    lodBias = -2.0  -- Maximum sharpness for very small sprites
  elseif scale < 0.5 then
    lodBias = -1.5  -- High sharpness for small sprites
  elseif scale < 0.75 then
    lodBias = -1.0  -- Moderate sharpness
  else
    lodBias = -0.5  -- Slight sharpness boost
  end
  return lodBias
end

-- Kept as its own name because the shadow and ghost passes read as their
-- own thing at the call sites; it once carried a different mesh from the
-- solid draw, and now deliberately does not.
SpriteBillboards.shadowQuad = SpriteBillboards.mesh

function SpriteBillboards.invalidate()
  meshes = {}
end

Assets.register(SpriteBillboards.invalidate)

return SpriteBillboards
