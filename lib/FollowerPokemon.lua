-- FOLLOWER POKEMON: Stadium models that follow the player character.
--
-- This module handles loading and rendering Stadium models that follow
-- the player around the map, similar to Pikachu in Pokémon Yellow.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local Voxel3D = V.require("Voxel3D")
local StadiumPack = V.require("StadiumPack")
local StadiumRig = V.require("StadiumRig")

local FollowerPokemon = {}

-- Cache for loaded follower rigs to avoid reloading
local rigCache = {}

-- Current follower data
local currentRig = nil
local currentStadiumModel = nil
local currentDex = nil
local currentFilename = nil

-- Follower positioning
local followerOffset = { x = 0, y = 0, z = -2 }  -- Behind player by 2 tiles
local followerScale = 0.8  -- Slightly smaller than player

-- Load a Stadium model by dex number as a follower
function FollowerPokemon.load(dex)
  if not dex then return false, "no dex number" end
  
  print("FollowerPokemon.load: Attempting to load dex", dex)
  
  -- Check cache first
  if rigCache[dex] then
    currentRig = rigCache[dex]
    currentStadiumModel = currentRig and currentRig.model
    currentDex = dex
    currentFilename = "follower_" .. dex
    print("FollowerPokemon.load: Loaded from cache")
    return true
  end
  
  -- Load the Stadium model
  local model = StadiumPack.load(dex)
  if not model then
    print("FollowerPokemon.load: Failed to load Stadium model for dex", dex)
    return false, "could not load stadium model"
  end
  
  if model.staticPose then
    print("FollowerPokemon.load: Model has static pose, declining")
    return false, "model has static pose"
  end
  
  -- Create the rig
  local rig = StadiumRig.new(model)
  if not rig then
    print("FollowerPokemon.load: Failed to create rig")
    return false, "could not create rig"
  end
  
  -- Cache the rig
  rigCache[dex] = rig
  currentRig = rig
  currentStadiumModel = model
  currentDex = dex
  currentFilename = "follower_" .. dex
  
  -- Start idle animation
  rig:pose(1, 0, true)  -- Animation 1 is idle, time 0, loop true
  rig:skin(0)  -- No rotation initially
  
  print("FollowerPokemon.load: Successfully loaded Stadium model")
  return true
end

-- Clear the current follower
function FollowerPokemon.clear()
  if currentRig then
    currentRig:release()
    currentRig = nil
  end
  currentStadiumModel = nil
  currentDex = nil
  currentFilename = nil
end

-- Check if a follower is currently loaded
function FollowerPokemon.loaded()
  return currentRig ~= nil and currentStadiumModel ~= nil
end

-- Get the dex number of the currently loaded follower
function FollowerPokemon.dex()
  return currentDex
end

-- Get the filename of the currently loaded follower
function FollowerPokemon.filename()
  return currentFilename
end

-- Draw the follower at the player's position
function FollowerPokemon.draw(px, py, y, facing, mirror)
  if not (currentRig and currentStadiumModel) then
    return false
  end
  
  -- Update animation time
  local dt = 1 / 60  -- Assume 60 FPS for simplicity
  currentRig:pose(1, (currentRig.frameAt or 0) + dt, true)  -- Idle animation
  currentRig:anchor(0.75, dt)  -- Anchor to prevent drifting
  currentRig:textures(nil)  -- Update textures (eyes blinking)
  
  -- Calculate follower position based on player facing
  local offsetX, offsetZ = 0, -2  -- Default: behind player
  local followerYaw = 0
  
  -- Check if we're in free-roam mode (1st or 3rd person)
  local FirstPerson = V.require("FirstPerson")
  local b = FirstPerson.cardBlend()
  
  if b > 0 then
    -- In free-roam mode, use camera-relative rotation like the player model
    if facing == "down" then
      -- When moving backwards, face the camera
      followerYaw = FirstPerson.cardYaw(px + 8, py + 8) * b
    else
      -- When moving in other directions, face forward (away from camera)
      followerYaw = (FirstPerson.cardYaw(px + 8, py + 8) + math.pi) * b
    end
    -- In free-roam mode, calculate offset based on camera direction
    local camYaw = FirstPerson.cardYaw(px + 8, py + 8)
    offsetX = -math.sin(camYaw) * 2
    offsetZ = math.cos(camYaw) * 2
  else
    -- In other modes, rotate based on movement direction
    if facing == "right" then
      offsetX, offsetZ = -2, 0
      followerYaw = math.pi / 2
    elseif facing == "up" then
      offsetX, offsetZ = 0, 2
      followerYaw = math.pi
    elseif facing == "left" then
      offsetX, offsetZ = 2, 0
      followerYaw = -math.pi / 2
    end
  end
  
  -- Calculate the model matrix based on player position and offset
  local m = Mat4.translate(px + 8 + offsetX, y, py + 8 + offsetZ)
  
  -- Apply rotation based on facing direction
  if followerYaw ~= 0 then
    m = Mat4.mul(m, Mat4.rotateY(followerYaw))
  end
  
  -- Apply mirroring if needed
  if mirror then
    m = Mat4.mul(m, Mat4.scale(-1, 1, 1))
  end
  
  -- Apply scaling for follower model
  local model = currentStadiumModel
  local root = model.rootScale or 1
  local h = model.height or 52.25
  local k = root * 14 / math.max(h, 1e-6)  -- REF_HEIGHT = 14 from StadiumMon
  local scale = k * followerScale
  m = Mat4.mul(m, Mat4.scale(scale, scale, scale))
  
  -- Skin the mesh with the calculated yaw
  currentRig:skin(followerYaw)
  
  -- Draw using the rig's built-in draw method
  currentRig:draw(m)
  
  return true
end

-- Clear the follower cache to free memory
function FollowerPokemon.clearCache()
  for dex, rig in pairs(rigCache) do
    if rig then
      pcall(function() rig:release() end)
    end
  end
  rigCache = {}
  currentRig = nil
  currentStadiumModel = nil
  currentDex = nil
  currentFilename = nil
end

return FollowerPokemon
