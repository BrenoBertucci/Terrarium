-- Road 3D: simple road texture provider
-- Just provides the road texture for road quads (no 3D mesh system)

local V = ...

local Road3D = {}

Road3D.ASSET_DIR = "assets/ground/grass/"
Road3D.TEX = "road.png"

local tex = nil

local function assetPath(name)
  return V.path .. "/" .. Road3D.ASSET_DIR .. name
end

local function loadTexture()
  if tex ~= nil then return tex or nil end
  local okA, Assets = pcall(require, "src.render.Assets")
  if not okA or not Assets then
    tex = false
    return nil
  end
  local path = assetPath(Road3D.TEX)
  local okE, exists = pcall(Assets.exists, path)
  if not (okE and exists) then
    tex = false
    return nil
  end
  local ok, img = pcall(Assets.image, path)
  if not (ok and img) then
    tex = false
    return nil
  end
  pcall(img.setFilter, img, "nearest", "nearest")
  tex = img
  return img
end

function Road3D.available()
  return loadTexture() ~= nil
end

function Road3D.texture()
  return loadTexture()
end

return Road3D