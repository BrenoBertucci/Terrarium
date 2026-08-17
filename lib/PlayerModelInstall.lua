-- PLAYER MODEL: finding and managing custom 3D models for the player character.
--
-- The mod can load custom 3D models (.obj, .gltf, .glb) to replace the default
-- player sprite. Models are stored in the save directory and managed through
-- a marker file similar to the Stadium system.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local PlayerModelInstall = {}

-- Where player models are stored and where the marker file is kept.
PlayerModelInstall.DIR = "player_models"
PlayerModelInstall.MARKER = PlayerModelInstall.DIR .. "/model.info"

-- Format version for the marker file
PlayerModelInstall.FORMAT = "PM1"

local function fs()
  return love and love.filesystem
end

local function isFile(path)
  local f = fs()
  if not (f and f.getInfo) then return false end
  local ok, info = pcall(f.getInfo, path, "file")
  return (ok and info) and true or false
end

-- The marker file stores the current active model filename and format version.
local function readMarker()
  local f = fs()
  if not (f and isFile(PlayerModelInstall.MARKER)) then return nil end
  local ok, text = pcall(f.read, PlayerModelInstall.MARKER)
  if not (ok and type(text) == "string") then return nil end
  local format, filename = text:match("^(%S+)%s+(.+)$")
  if not format then return nil end
  return { format = format, filename = filename }
end

-- Write the marker file with the current model information.
function PlayerModelInstall.writeMarker(filename)
  local f = fs()
  if not (f and f.write) then return false end
  local content = PlayerModelInstall.FORMAT .. " " .. (filename or "")
  local ok, err = pcall(f.write, PlayerModelInstall.MARKER, content)
  return ok, err
end

-- Get the path to the currently installed player model, or nil if none.
function PlayerModelInstall.modelPath()
  local marker = readMarker()
  if not marker or marker.format ~= PlayerModelInstall.FORMAT then
    return nil
  end
  if not marker.filename or marker.filename == "" then
    return nil
  end
  local path = PlayerModelInstall.DIR .. "/" .. marker.filename
  return isFile(path) and path or nil
end

-- Whether a player model is currently installed.
function PlayerModelInstall.installed()
  local marker = readMarker()
  if not marker or marker.format ~= PlayerModelInstall.FORMAT then
    return false
  end
  if not marker.filename or marker.filename == "" then
    return false
  end
  -- Check if this is a Stadium model marker (format: stadium_player_X)
  local dexStr = marker.filename:match("stadium_player_(%d+)")
  if dexStr then
    return true  -- Stadium models don't need physical files
  end
  -- For regular models, check if the file exists
  local path = PlayerModelInstall.DIR .. "/" .. marker.filename
  return isFile(path)
end

-- Get the filename of the currently installed model.
function PlayerModelInstall.modelFilename()
  local marker = readMarker()
  if not marker or marker.format ~= PlayerModelInstall.FORMAT then
    return nil
  end
  return marker.filename
end

-- Check if a specific model file exists in the models directory.
function PlayerModelInstall.modelExists(filename)
  if not filename then return false end
  local path = PlayerModelInstall.DIR .. "/" .. filename
  return isFile(path)
end

-- List all available model files in the models directory.
function PlayerModelInstall.availableModels()
  local f = fs()
  if not f then return {} end
  
  local ok, items = pcall(f.getDirectoryItems, PlayerModelInstall.DIR)
  if not ok or not items then return {} end
  
  local models = {}
  for _, name in ipairs(items) do
    -- Filter for supported formats
    if name:lower():match("%.obj$") or name:lower():match("%.gltf$") or name:lower():match("%.glb$") then
      local path = PlayerModelInstall.DIR .. "/" .. name
      if isFile(path) then
        table.insert(models, name)
      end
    end
  end
  
  table.sort(models)
  return models
end

-- Remove a specific model file.
function PlayerModelInstall.removeModel(filename)
  if not filename then return false end
  local path = PlayerModelInstall.DIR .. "/" .. filename
  local f = fs()
  if not (f and f.remove) then return false end
  
  local ok, err = pcall(f.remove, path)
  if not ok then return false, err end
  
  -- If this was the active model, clear the marker
  local current = PlayerModelInstall.modelFilename()
  if current == filename then
    PlayerModelInstall.writeMarker("")
  end
  
  return true
end

-- Clear the current player model (revert to default sprite).
function PlayerModelInstall.clear()
  return PlayerModelInstall.writeMarker("")
end

-- Ensure the models directory exists.
function PlayerModelInstall.ensureDirectory()
  local f = fs()
  if not f then return false end
  
  -- Check if directory exists
  local ok, info = pcall(f.getInfo, PlayerModelInstall.DIR)
  if ok and info then return true end
  
  -- Try to create it
  local okCreate, err = pcall(f.createDirectory, PlayerModelInstall.DIR)
  return okCreate, err
end

return PlayerModelInstall
