-- STADIUM FOLLOWER: Replace Yellow's Pikachu follower with any Stadium Pokémon.
--
-- This module extends the gen1recomp Pikachu follower system to use 3D Stadium
-- models instead of 2D sprites. It hooks into the overworld rendering to draw
-- Stadium models for the follower NPC.
--
-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local StadiumPack = V.require("StadiumPack")
local StadiumRig = V.require("StadiumRig")
local StadiumMon = V.require("StadiumMon")
local Voxel3D = V.require("Voxel3D")

local StadiumFollower = {}

-- Cache for loaded follower rigs
local rigCache = {}

-- Current follower species (nil = disabled, 1-151 = dex number)
local currentSpecies = nil

-- Current rig and model
local currentRig = nil
local currentModel = nil

-- Animation state
local animTime = 0
local currentAnim = 1  -- 1 = idle

-- ------- Configuration

-- Scale for the follower model (smaller than player)
local FOLLOWER_SCALE = 0.9  -- 0.3 * 3 = 0.9 (3x larger)

-- ------- Species Management

-- Set the follower species by dex number (1-151)
function StadiumFollower.setSpecies(dex)
  if dex == currentSpecies then return true end
  
  -- Clear current rig
  if currentRig then
    currentRig:release()
    currentRig = nil
  end
  currentModel = nil
  currentSpecies = nil
  
  if not dex or dex < 1 or dex > 151 then
    return true  -- Disabled
  end
  
  -- Check cache first
  if rigCache[dex] then
    currentRig = rigCache[dex]
    currentModel = currentRig.model
    currentSpecies = dex
    return true
  end
  
  -- Load the Stadium model
  local model = StadiumPack.load(dex)
  if not model then
    print("StadiumFollower: Failed to load model for dex", dex)
    return false
  end
  
  if model.staticPose then
    print("StadiumFollower: Model has static pose, declining dex", dex)
    return false
  end
  
  -- Create the rig
  local rig = StadiumRig.new(model)
  if not rig then
    print("StadiumFollower: Failed to create rig for dex", dex)
    return false
  end
  
  -- Cache and set current
  rigCache[dex] = rig
  currentRig = rig
  currentModel = model
  currentSpecies = dex
  
  -- Start idle animation
  rig:pose(1, 0, true)
  rig:skin(0)
  
  print("StadiumFollower: Loaded follower dex", dex)
  return true
end

-- Get the current follower species
function StadiumFollower.getSpecies()
  return currentSpecies
end

-- ------- Rendering

-- Update animation state
function StadiumFollower.update(dt)
  if not currentRig then return end
  
  animTime = animTime + dt
  currentRig:pose(currentAnim, animTime * 30, true)  -- 30 FPS
  currentRig:anchor(0.75, dt)
  currentRig:textures(nil)
end

-- Draw the follower at the given position
-- x, y: world coordinates (pixel position)
-- facing: direction the follower is facing ("up", "down", "left", "right")
function StadiumFollower.draw(x, y, facing)
  if not currentRig or not currentModel then return false end
  
  -- Calculate the model matrix
  local m = Mat4.translate(x, 0, y)
  
  -- Check if we're in free-roam mode (1st or 3rd person)
  local FirstPerson = V.require("FirstPerson")
  local b = FirstPerson.cardBlend()
  
  -- Apply rotation based on facing direction
  local yaw = 0
  if b > 0 then
    -- In free-roam mode, use camera-relative rotation like the player model
    if facing == "down" then
      -- When moving backwards, face the camera
      yaw = FirstPerson.cardYaw(x, y) * b
    else
      -- When moving in other directions, face forward (away from camera)
      yaw = (FirstPerson.cardYaw(x, y) + math.pi) * b
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
  
  -- Apply scaling
  local model = currentModel
  local scale = StadiumMon.scaleFor(model) * FOLLOWER_SCALE
  m = Mat4.mul(m, Mat4.scale(scale, scale, scale))
  
  -- Stand the model on its own lowest point and give back HOVER_CAP of any
  -- authored hover, same as StadiumWilds/PlayerModel/battle Pokemon --
  -- otherwise a hovering or origin-centred species renders sunk into the
  -- ground instead of standing on it.
  local lift = StadiumMon.liftFor(model)
  if lift ~= 0 then
    m = Mat4.mul(m, Mat4.translate(0, -lift, 0))
  end
  
  -- Skin and draw
  currentRig:skin(yaw)
  currentRig:draw(m)
  
  return true
end

-- ------- Cleanup

-- Clear all cached rigs
function StadiumFollower.clearCache()
  for dex, rig in pairs(rigCache) do
    if rig then
      pcall(function() rig:release() end)
    end
  end
  rigCache = {}
  currentRig = nil
  currentModel = nil
  currentSpecies = nil
  animTime = 0
end

-- Check if a follower is currently loaded
function StadiumFollower.loaded()
  return currentRig ~= nil and currentModel ~= nil
end

return StadiumFollower