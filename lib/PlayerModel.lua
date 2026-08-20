-- PLAYER MODEL: loading and rendering custom 3D models for the player character.
--
-- This module handles loading .obj, .gltf, and .glb files and rendering them
-- in place of the default player sprite. It integrates with the existing
-- Voxel3D rendering pipeline.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local Voxel3D = V.require("Voxel3D")
local PlayerModelInstall = V.require("PlayerModelInstall")
local StadiumPack = V.require("StadiumPack")
local StadiumRig = V.require("StadiumRig")
local StadiumMon = V.require("StadiumMon")

local PlayerModel = {}

-- Cache for loaded models to avoid reloading every frame
local modelCache = {}

-- Cache for loaded textures to avoid reloading every frame
local textureCache = {}

-- Current loaded model data
local currentModel = nil
local currentTexture = nil
local currentFilename = nil
local currentRig = nil
local currentStadiumModel = nil
local isStadiumModel = false

-- ------- OBJ file parsing (basic implementation)
--
-- Parses a simple .obj file to extract vertices, texture coordinates, faces, and material info.
-- This is a minimal implementation focused on getting basic geometry working with textures.
local function parseObj(objData)
  local vertices = {}
  local texCoords = {}
  local faces = {}
  local mtlFile = nil
  local currentMaterial = nil
  
  for line in objData:gmatch("[^\r\n]+") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line:sub(1, 1) == "#" or line == "" then
      -- Skip comments and empty lines
    elseif line:sub(1, 2) == "v " then
      -- Vertex: v x y z
      local x, y, z = line:match("^v%s+([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)")
      if x and y and z then
        table.insert(vertices, { tonumber(x), tonumber(y), tonumber(z) })
      end
    elseif line:sub(1, 3) == "vt " then
      -- Texture coordinate: vt u v
      local u, v = line:match("^vt%s+([%d%.%-]+)%s+([%d%.%-]+)")
      if u and v then
        table.insert(texCoords, { tonumber(u), tonumber(v) })
      end
    elseif line:sub(1, 7) == "mtllib " then
      -- Material library: mtllib filename.mtl
      mtlFile = line:match("^mtllib%s+(.+)")
    elseif line:sub(1, 7) == "usemtl " then
      -- Use material: usemtl material_name
      currentMaterial = line:match("^usemtl%s+(.+)")
    elseif line:sub(1, 2) == "f " then
      -- Face: f v1/t1/n1 v2/t2/n2 v3/t3/n3 (texture and normals optional)
      -- Parse with texture coordinates
      local v1, t1, v2, t2, v3, t3 = line:match("^f%s+(%d+)/(%d*)/?%d*%s+(%d+)/(%d*)/?%d*%s+(%d+)/(%d*)/?%d*")
      if v1 and v2 and v3 then
        table.insert(faces, {
          v = { tonumber(v1), tonumber(v2), tonumber(v3) },
          t = { t1 ~= "" and tonumber(t1) or nil, t2 ~= "" and tonumber(t2) or nil, t3 ~= "" and tonumber(t3) or nil },
          material = currentMaterial
        })
      else
        -- Try without texture coordinates
        v1, v2, v3 = line:match("^f%s+(%d+)%s+(%d+)%s+(%d+)")
        if v1 and v2 and v3 then
          table.insert(faces, {
            v = { tonumber(v1), tonumber(v2), tonumber(v3) },
            t = { nil, nil, nil },
            material = currentMaterial
          })
        end
      end
    end
  end
  
  return vertices, texCoords, faces, mtlFile
end

-- Parse MTL file to extract texture map references
local function parseMtl(mtlData)
  local materials = {}
  local currentMaterial = nil
  
  for line in mtlData:gmatch("[^\r\n]+") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line:sub(1, 1) == "#" or line == "" then
      -- Skip comments and empty lines
    elseif line:sub(1, 7) == "newmtl " then
      -- New material: newmtl material_name
      currentMaterial = line:match("^newmtl%s+(.+)")
      materials[currentMaterial] = {}
    elseif line:sub(1, 7) == "map_Kd " then
      -- Diffuse texture map: map_Kd filename.png
      if currentMaterial and materials[currentMaterial] then
        local textureFile = line:match("^map_Kd%s+(.+)")
        materials[currentMaterial].texture = textureFile
      end
    end
  end
  
  return materials
end

-- Convert OBJ data to a mesh compatible with Voxel3D
local function objToMesh(vertices, texCoords, faces)
  print("objToMesh: Starting conversion with", #vertices, "vertices,", #texCoords, "texCoords and", #faces, "faces")
  
  if #vertices == 0 or #faces == 0 then
    print("objToMesh: No vertices or faces")
    return nil
  end
  
  -- Build vertex buffer in Voxel3D.FORMAT
  -- Format: { "VertexPosition", "float", 3 }, { "VertexTexCoord", "float", 2 }, { "VertexShade", "float", 1 }
  -- LÖVE expects table of tables, where each vertex is its own table
  local vertexData = {}
  
  for faceIndex, face in ipairs(faces) do
    for i = 1, 3 do
      local vertexIndex = face.v[i]
      local texCoordIndex = face.t[i]
      
      -- OBJ indices are 1-based, convert to 0-based
      local v = vertices[vertexIndex] or vertices[1]
      local tc = texCoordIndex and texCoords[texCoordIndex]
      
      if v then
        -- Create a vertex table with 6 values: x, y, z, u, v, shade
        local vertex = {
          v[1],           -- x
          v[2],          -- y (flipped to match coordinate system)
          v[3],          -- z (flipped to face the right direction)
          tc and tc[1] or 0,  -- u (texture coordinate)
          tc and tc[2] or 0,  -- v (texture coordinate, flipped for LOVE)
          1.0             -- shade
        }
        table.insert(vertexData, vertex)
      else
        print("objToMesh: Invalid vertex index", vertexIndex, "in face", faceIndex)
      end
    end
  end
  
  print("objToMesh: Generated", #vertexData, "vertices")
  
  if #vertexData == 0 then
    print("objToMesh: No vertex data generated")
    return nil
  end
  
  -- Create mesh
  local ok, mesh = pcall(love.graphics.newMesh, Voxel3D.FORMAT, vertexData, "triangles")
  if not ok then
    print("objToMesh: love.graphics.newMesh failed:", mesh)
    return nil
  end
  
  print("objToMesh: Mesh created successfully")
  return mesh
end

-- ------- Model loading

-- Load a model from a file. Returns success plus mesh or error message.
function PlayerModel.load(filename)
  if not filename then return false, "no filename" end
  
  print("PlayerModel.load: Attempting to load", filename)
  
  -- Check cache first
  if modelCache[filename] then
    currentModel = modelCache[filename]
    currentTexture = textureCache[filename]
    currentFilename = filename
    print("PlayerModel.load: Loaded from cache")
    return true
  end
  
  local path = PlayerModelInstall.DIR .. "/" .. filename
  local f = love and love.filesystem
  if not (f and f.read) then return false, "no filesystem" end
  
  -- Read file
  local ok, data = pcall(f.read, path)
  if not ok or not data then
    print("PlayerModel.load: Failed to read file -", ok, data)
    return false, "could not read file"
  end
  
  print("PlayerModel.load: File read successfully, size:", #data)
  
  -- Determine file type and parse accordingly
  local ext = filename:lower():match("%.([^.]+)$")
  local mesh = nil
  local texture = nil
  
  print("PlayerModel.load: File extension:", ext)
  
  if ext == "obj" then
    local vertices, texCoords, faces, mtlFile = parseObj(data)
    print("PlayerModel.load: Parsed OBJ - vertices:", #vertices, "texCoords:", #texCoords, "faces:", #faces, "mtl:", mtlFile or "none")
    
    -- Load texture if MTL file is specified
    if mtlFile then
      local mtlPath = PlayerModelInstall.DIR .. "/" .. mtlFile
      local mtlOk, mtlData = pcall(f.read, mtlPath)
      if mtlOk and mtlData then
        print("PlayerModel.load: MTL file read successfully")
        local materials = parseMtl(mtlData)
        
        -- Get the first material's texture (simplified - uses first found texture)
        for matName, matData in pairs(materials) do
          if matData.texture then
            local texturePath = PlayerModelInstall.DIR .. "/" .. matData.texture
            local texOk, texData = pcall(f.read, texturePath)
            if texOk and texData then
              print("PlayerModel.load: Texture file read successfully:", matData.texture)
              local imgOk, image = pcall(love.graphics.newImage, love.filesystem.newFileData(texData, matData.texture))
              if imgOk and image then
                texture = image
                print("PlayerModel.load: Texture loaded successfully")
                break
              else
                print("PlayerModel.load: Failed to create image from texture data:", image)
              end
            else
              print("PlayerModel.load: Failed to read texture file:", texOk, texData)
            end
          end
        end
      else
        print("PlayerModel.load: Failed to read MTL file:", mtlOk, mtlData)
      end
    end
    
    mesh = objToMesh(vertices, texCoords, faces)
    print("PlayerModel.load: Mesh creation", mesh and "succeeded" or "failed")
  elseif ext == "gltf" or ext == "glb" then
    -- glTF support would require a library like Menori
    -- For now, return not implemented
    print("PlayerModel.load: glTF/.glb files are not yet supported. Please convert your model to .obj format.")
    return false, "glTF/.glb support not yet implemented - please use .obj format"
  else
    print("PlayerModel.load: Unsupported file format:", ext)
    return false, "unsupported file format: " .. (ext or "unknown")
  end
  
  if not mesh then
    print("PlayerModel.load: Failed to create mesh from model")
    return false, "failed to create mesh from model"
  end
  
  -- Cache the mesh and texture
  modelCache[filename] = mesh
  textureCache[filename] = texture
  currentModel = mesh
  currentTexture = texture
  currentFilename = filename
  
  print("PlayerModel.load: Successfully loaded model")
  return true
end

-- Load a Stadium model by dex number (e.g., 150 for Mewtwo)
function PlayerModel.loadStadium(dex)
  if not dex then return false, "no dex number" end
  
  print("PlayerModel.loadStadium: Attempting to load dex", dex)
  
  -- Check cache first
  local cacheKey = "stadium_" .. dex
  if modelCache[cacheKey] then
    currentModel = modelCache[cacheKey]
    currentRig = textureCache[cacheKey]  -- Reuse textureCache for rig cache
    currentStadiumModel = currentRig and currentRig.model
    currentFilename = "stadium_" .. dex
    isStadiumModel = true
    print("PlayerModel.loadStadium: Loaded from cache")
    return true
  end
  
  -- Load the Stadium model
  local model = StadiumPack.load(dex)
  if not model then
    print("PlayerModel.loadStadium: Failed to load Stadium model for dex", dex)
    return false, "could not load stadium model"
  end
  
  if model.staticPose then
    print("PlayerModel.loadStadium: Model has static pose, declining")
    return false, "model has static pose"
  end
  
  -- Create the rig
  local rig = StadiumRig.new(model)
  if not rig then
    print("PlayerModel.loadStadium: Failed to create rig")
    return false, "could not create rig"
  end
  
  -- Cache the rig and model
  modelCache[cacheKey] = rig  -- Store rig in modelCache
  textureCache[cacheKey] = rig  -- Store rig in textureCache for consistency
  currentRig = rig
  currentStadiumModel = model
  currentModel = nil  -- No static mesh for Stadium models
  currentTexture = nil
  currentFilename = "stadium_" .. dex
  isStadiumModel = true
  
  -- Start idle animation
  rig:pose(1, 0, true)  -- Animation 1 is idle, time 0, loop true
  rig:skin(0)  -- No rotation initially
  
  print("PlayerModel.loadStadium: Successfully loaded Stadium model")
  return true
end

-- Get the current Stadium dex number loaded
function PlayerModel.getStadiumDex()
  if not isStadiumModel or not currentFilename then return nil end
  local dexStr = currentFilename:match("stadium_(%d+)")
  return dexStr and tonumber(dexStr) or nil
end

-- Load the currently installed model (if any).
function PlayerModel.loadInstalled()
  local filename = PlayerModelInstall.modelFilename()
  if not filename then return false end
  
  -- Check if this is a Stadium model marker (format: stadium_player_X)
  local dexStr = filename:match("stadium_player_(%d+)")
  if dexStr then
    local dex = tonumber(dexStr)
    if dex and dex >= 1 and dex <= 151 then
      return PlayerModel.loadStadium(dex)
    end
  end
  
  -- Otherwise load as regular OBJ model
  return PlayerModel.load(filename)
end

-- Clear the current model.
function PlayerModel.clear()
  if currentRig then
    currentRig:release()
    currentRig = nil
  end
  currentModel = nil
  currentTexture = nil
  currentFilename = nil
  currentStadiumModel = nil
  isStadiumModel = false
end

-- Check if a model is currently loaded.
function PlayerModel.loaded()
  return currentModel ~= nil or (currentRig ~= nil and currentStadiumModel ~= nil)
end

-- Get the filename of the currently loaded model.
function PlayerModel.filename()
  return currentFilename
end

-- ------- Rendering

-- Draw the player model at the given position with the given transform.
-- This integrates with the existing Voxel3D pipeline.
function PlayerModel.draw(px, py, y, facing, mirror)
  -- Handle Stadium models (animated skeletal models)
  if isStadiumModel and currentRig and currentStadiumModel then
    -- Update animation time
    local dt = 1 / 60  -- Assume 60 FPS for simplicity
    currentRig:pose(1, (currentRig.frameAt or 0) + dt, true)  -- Idle animation
    currentRig:anchor(0.75, dt)  -- Anchor to prevent drifting
    currentRig:textures(nil)  -- Update textures (eyes blinking)
    
    -- Calculate the model matrix based on position and facing
    local m = Mat4.translate(px + 8, y, py + 8)
    
    -- Check if we're in free-roam mode (1st or 3rd person)
    local FirstPerson = V.require("FirstPerson")
    local b = FirstPerson.cardBlend()
    
    -- Apply rotation based on facing direction
    local yaw = 0
    if b > 0 then
      -- In free-roam mode
      if facing == "down" then
        -- When moving backwards, face the camera
        yaw = FirstPerson.cardYaw(px + 8, py + 8) * b
      else
        -- When moving in other directions, face forward (away from camera)
        yaw = (FirstPerson.cardYaw(px + 8, py + 8) + math.pi) * b
      end
    else
      -- In other modes, rotate based on movement direction
      if facing == "right" then
        yaw = math.pi / 2
      elseif facing == "up" then
        yaw = math.pi
      elseif facing == "left" then
        yaw = -math.pi / 2
      end
    end
    
    if yaw ~= 0 then
      m = Mat4.mul(m, Mat4.rotateY(yaw))
    end
    
    -- Apply mirroring if needed
    if mirror then
      m = Mat4.mul(m, Mat4.scale(-1, 1, 1))
    end
    
    -- Apply scaling for Stadium model (use similar scale to Pokemon in battles)
    local model = currentStadiumModel
    local scale = StadiumMon.scaleFor(model) * 1.5  -- 0.5 * 4 = 2.0 (4x larger for Mewtwo)
    m = Mat4.mul(m, Mat4.scale(scale, scale, scale))
    
    -- Stand the model on its own lowest point and give back HOVER_CAP of
    -- any authored hover, same as StadiumWilds/battle Pokemon -- otherwise
    -- a species authored with a hover (or centred on its origin) renders
    -- sunk into the ground instead of standing on it.
    local lift = StadiumMon.liftFor(model)
    if lift ~= 0 then
      m = Mat4.mul(m, Mat4.translate(0, -lift, 0))
    end
    
    -- Skin the mesh with the calculated yaw
    currentRig:skin(yaw)
    
    -- Draw using the rig's built-in draw method
    currentRig:draw(m)
    
    return true
  end
  
  -- Handle static OBJ models
  if not currentModel then 
    return false 
  end
  
  -- Calculate the model matrix based on position and facing
  local m = Mat4.translate(px + 8, y, py + 8)
  
  -- Apply rotation based on facing direction
  local yaw = 0
  if facing == "right" then
    yaw = math.pi / 2
  elseif facing == "up" then
    yaw = math.pi
  elseif facing == "left" then
    yaw = -math.pi / 2
  end
  
  if yaw ~= 0 then
    m = Mat4.mul(m, Mat4.rotateY(yaw))
  end
  
  -- Apply mirroring if needed
  if mirror then
    m = Mat4.mul(m, Mat4.scale(-1, 1, 1))
  end
  
  -- Apply scaling to match game world units
  -- Increased scale to make the model more visible
  local scale = 4.0  -- Increased from 0.1 to 1.0
  m = Mat4.mul(m, Mat4.scale(scale, scale, scale))
  
  -- Draw the mesh using Voxel3D with texture
  Voxel3D.draw(currentModel, currentTexture, m)
  
  return true
end

-- ------- Cleanup

-- Clear the model cache to free memory.
function PlayerModel.clearCache()
  for key, mesh in pairs(modelCache) do
    if mesh then
      -- Check if this is a rig (Stadium model) or a mesh (OBJ model)
      if type(mesh) == "table" and mesh.release then
        pcall(function() mesh:release() end)
      elseif type(mesh) == "userdata" then
        pcall(function() mesh:release() end)
      end
    end
  end
  for _, texture in pairs(textureCache) do
    if texture then
      pcall(function() texture:release() end)
    end
  end
  modelCache = {}
  textureCache = {}
  currentModel = nil
  currentTexture = nil
  currentFilename = nil
  currentRig = nil
  currentStadiumModel = nil
  isStadiumModel = false
end

return PlayerModel