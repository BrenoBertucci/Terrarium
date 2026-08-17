-- PLAYER MODEL: importing a custom 3D model for the player character.
--
-- This opens a file picker to let the player choose a .obj, .gltf, or .glb file
-- to replace the default player sprite with a custom 3D model.
--
-- Uses the same infrastructure as StadiumRomPick for platform-specific file dialogs.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local PlayerModelInstall = V.require("PlayerModelInstall")

local PlayerModelPick = {}

PlayerModelPick.LABEL = "PLAYER MODEL"
PlayerModelPick.ID = "DRAMATIC_SHAPE:playerModel"

-- Stadium Mewtwo player model option
PlayerModelPick.MEWTWO_LABEL = "POKEMON PLAYER"
PlayerModelPick.MEWTWO_ID = "DRAMATIC_SHAPE:pokemonPlayer"

-- Stadium follower option
PlayerModelPick.FOLLOWER_LABEL = "POKEMON FOLLOWER"
PlayerModelPick.FOLLOWER_ID = "DRAMATIC_SHAPE:pokemonFollower"

-- Stadium wilds option
PlayerModelPick.WILDS_LABEL = "STADIUM WILDS"
PlayerModelPick.WILDS_ID = "DRAMATIC_SHAPE:stadiumWilds"

-- All 151 Pokemon species for cycling through
PlayerModelPick.POPULAR_SPECIES = {
  { dex = 1, name = "Bulbasaur" },
  { dex = 2, name = "Ivysaur" },
  { dex = 3, name = "Venusaur" },
  { dex = 4, name = "Charmander" },
  { dex = 5, name = "Charmeleon" },
  { dex = 6, name = "Charizard" },
  { dex = 7, name = "Squirtle" },
  { dex = 8, name = "Wartortle" },
  { dex = 9, name = "Blastoise" },
  { dex = 10, name = "Caterpie" },
  { dex = 11, name = "Metapod" },
  { dex = 12, name = "Butterfree" },
  { dex = 13, name = "Weedle" },
  { dex = 14, name = "Kakuna" },
  { dex = 15, name = "Beedrill" },
  { dex = 16, name = "Pidgey" },
  { dex = 17, name = "Pidgeotto" },
  { dex = 18, name = "Pidgeot" },
  { dex = 19, name = "Rattata" },
  { dex = 20, name = "Raticate" },
  { dex = 21, name = "Spearow" },
  { dex = 22, name = "Fearow" },
  { dex = 23, name = "Ekans" },
  { dex = 24, name = "Arbok" },
  { dex = 25, name = "Pikachu" },
  { dex = 26, name = "Raichu" },
  { dex = 27, name = "Sandshrew" },
  { dex = 28, name = "Sandslash" },
  { dex = 29, name = "Nidoran♀" },
  { dex = 30, name = "Nidorina" },
  { dex = 31, name = "Nidoqueen" },
  { dex = 32, name = "Nidoran♂" },
  { dex = 33, name = "Nidorino" },
  { dex = 34, name = "Nidoking" },
  { dex = 35, name = "Clefairy" },
  { dex = 36, name = "Clefable" },
  { dex = 37, name = "Vulpix" },
  { dex = 38, name = "Ninetales" },
  { dex = 39, name = "Jigglypuff" },
  { dex = 40, name = "Wigglytuff" },
  { dex = 41, name = "Zubat" },
  { dex = 42, name = "Golbat" },
  { dex = 43, name = "Oddish" },
  { dex = 44, name = "Gloom" },
  { dex = 45, name = "Vileplume" },
  { dex = 46, name = "Paras" },
  { dex = 47, name = "Parasect" },
  { dex = 48, name = "Venonat" },
  { dex = 49, name = "Venomoth" },
  { dex = 50, name = "Diglett" },
  { dex = 51, name = "Dugtrio" },
  { dex = 52, name = "Meowth" },
  { dex = 53, name = "Persian" },
  { dex = 54, name = "Psyduck" },
  { dex = 55, name = "Golduck" },
  { dex = 56, name = "Mankey" },
  { dex = 57, name = "Primeape" },
  { dex = 58, name = "Growlithe" },
  { dex = 59, name = "Arcanine" },
  { dex = 60, name = "Poliwag" },
  { dex = 61, name = "Poliwhirl" },
  { dex = 62, name = "Poliwrath" },
  { dex = 63, name = "Abra" },
  { dex = 64, name = "Kadabra" },
  { dex = 65, name = "Alakazam" },
  { dex = 66, name = "Machop" },
  { dex = 67, name = "Machoke" },
  { dex = 68, name = "Machamp" },
  { dex = 69, name = "Bellsprout" },
  { dex = 70, name = "Weepinbell" },
  { dex = 71, name = "Victreebel" },
  { dex = 72, name = "Tentacool" },
  { dex = 73, name = "Tentacruel" },
  { dex = 74, name = "Geodude" },
  { dex = 75, name = "Graveler" },
  { dex = 76, name = "Golem" },
  { dex = 77, name = "Ponyta" },
  { dex = 78, name = "Rapidash" },
  { dex = 79, name = "Slowpoke" },
  { dex = 80, name = "Slowbro" },
  { dex = 81, name = "Magnemite" },
  { dex = 82, name = "Magneton" },
  { dex = 83, name = "Farfetch'd" },
  { dex = 84, name = "Doduo" },
  { dex = 85, name = "Dodrio" },
  { dex = 86, name = "Seel" },
  { dex = 87, name = "Dewgong" },
  { dex = 88, name = "Grimer" },
  { dex = 89, name = "Muk" },
  { dex = 90, name = "Shellder" },
  { dex = 91, name = "Cloyster" },
  { dex = 92, name = "Gastly" },
  { dex = 93, name = "Haunter" },
  { dex = 94, name = "Gengar" },
  { dex = 95, name = "Onix" },
  { dex = 96, name = "Drowzee" },
  { dex = 97, name = "Hypno" },
  { dex = 98, name = "Krabby" },
  { dex = 99, name = "Kingler" },
  { dex = 100, name = "Voltorb" },
  { dex = 101, name = "Electrode" },
  { dex = 102, name = "Exeggcute" },
  { dex = 103, name = "Exeggutor" },
  { dex = 104, name = "Cubone" },
  { dex = 105, name = "Marowak" },
  { dex = 106, name = "Hitmonlee" },
  { dex = 107, name = "Hitmonchan" },
  { dex = 108, name = "Lickitung" },
  { dex = 109, name = "Koffing" },
  { dex = 110, name = "Weezing" },
  { dex = 111, name = "Rhyhorn" },
  { dex = 112, name = "Rhydon" },
  { dex = 113, name = "Chansey" },
  { dex = 114, name = "Tangela" },
  { dex = 115, name = "Kangaskhan" },
  { dex = 116, name = "Horsea" },
  { dex = 117, name = "Seadra" },
  { dex = 118, name = "Goldeen" },
  { dex = 119, name = "Seaking" },
  { dex = 120, name = "Staryu" },
  { dex = 121, name = "Starmie" },
  { dex = 122, name = "Mr. Mime" },
  { dex = 123, name = "Scyther" },
  { dex = 124, name = "Jynx" },
  { dex = 125, name = "Electabuzz" },
  { dex = 126, name = "Magmar" },
  { dex = 127, name = "Pinsir" },
  { dex = 128, name = "Tauros" },
  { dex = 129, name = "Magikarp" },
  { dex = 130, name = "Gyarados" },
  { dex = 131, name = "Lapras" },
  { dex = 132, name = "Ditto" },
  { dex = 133, name = "Eevee" },
  { dex = 134, name = "Vaporeon" },
  { dex = 135, name = "Jolteon" },
  { dex = 136, name = "Flareon" },
  { dex = 137, name = "Porygon" },
  { dex = 138, name = "Omanyte" },
  { dex = 139, name = "Omastar" },
  { dex = 140, name = "Kabuto" },
  { dex = 141, name = "Kabutops" },
  { dex = 142, name = "Aerodactyl" },
  { dex = 143, name = "Snorlax" },
  { dex = 144, name = "Articuno" },
  { dex = 145, name = "Zapdos" },
  { dex = 146, name = "Moltres" },
  { dex = 147, name = "Dratini" },
  { dex = 148, name = "Dragonair" },
  { dex = 149, name = "Dragonite" },
  { dex = 150, name = "Mewtwo" },
  { dex = 151, name = "Mew" },
}

local PROMPT = "Choose your player model (.obj, .gltf, .glb)"

-- ------- the host, at arm's length
--
-- Everything below is read through pcall and a presence test. The mod loader
-- hands a mod the real `io` and `os` today, but a mod that TAKES that for
-- granted is one that stops loading the day a sandbox arrives.

local function haveShell()
  local ok, popen = pcall(function() return io and io.popen end)
  return (ok and popen) and true or false
end

local function haveFiles()
  local ok, open = pcall(function() return io and io.open end)
  return (ok and open) and true or false
end

local function osName()
  local ok, name = pcall(function() return love.system.getOS() end)
  return ok and name or nil
end

-- Run a command and return its trimmed stdout, or nil for anything that did
-- not produce a line -- a cancelled dialog, a missing zenity, a shell that
-- is not there.
local function commandOutput(cmd)
  if not haveShell() then return nil end
  local ok, pipe = pcall(io.popen, cmd)
  if not (ok and pipe) then return nil end
  local okRead, out = pcall(pipe.read, pipe, "*a")
  pcall(pipe.close, pipe)
  if not (okRead and type(out) == "string") then return nil end
  out = out:gsub("^%s+", ""):gsub("%s+$", "")
  return (out ~= "") and out or nil
end

-- ------- can this machine open a DIALOG
--
-- Desktop only, and honestly so.
function PlayerModelPick.canDialog()
  if not (haveShell() and haveFiles()) then return false end
  local p = osName()
  return p == "Windows" or p == "OS X" or p == "Linux"
end

-- Kept as the old name for callers that only wanted "is there a dialog".
PlayerModelPick.available = PlayerModelPick.canDialog

-- Where a picked model would land if the native bridge is used.
PlayerModelPick.PICKED = "picked_player_model"

-- Open the dialog. Returns the chosen absolute path, or nil when the player
-- cancelled or no dialog could be opened.
function PlayerModelPick.choose()
  local p = osName()
  if p == "OS X" then
    return commandOutput(
      ([[osascript -e 'POSIX path of (choose file with prompt "%s" of type ]]
       .. [[{"obj", "gltf", "glb"})' 2>/dev/null]]):format(PROMPT))
  elseif p == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. PROMPT .. "';",
      "$d.Filter='3D Model (*.obj;*.gltf;*.glb)|*.obj;*.gltf;*.glb"
      .. "|All files (*.*)|*.*';",
      -- as UTF-8: the console's OEM codepage would mangle a non-ASCII path
      "if($d.ShowDialog() -eq 'OK'){[Console]::OutputEncoding="
      .. "[Text.Encoding]::UTF8; [Console]::Write($d.FileName)}",
    })
    return commandOutput(
      'powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif p == "Linux" then
    local path = commandOutput(
      ([[zenity --file-selection --title="%s" ]]
       .. [[--file-filter="3D Model | *.obj *.gltf *.glb" 2>/dev/null]])
        :format(PROMPT))
    if path then return path end
    -- zenity is absent on plenty of installs; KDE's own dialog is the usual second answer
    return commandOutput(
      [[kdialog --getopenfilename "$HOME" "*.obj *.gltf *.glb|]]
      .. [[3D Model" 2>/dev/null]])
  end
  return nil
end

-- Read an ABSOLUTE path, which love.filesystem cannot: it only sees inside
-- the physfs mount, and a picked file is anywhere on the disk. Returns the
-- bytes, or nil plus a reason short enough to fit the loading screen.
function PlayerModelPick.read(path)
  if not haveFiles() then return nil, "no file access" end
  local ok, fp = pcall(io.open, path, "rb")
  if not (ok and fp) then return nil, "could not open that file" end
  local okRead, bytes = pcall(fp.read, fp, "*a")
  pcall(fp.close, fp)
  if not (okRead and type(bytes) == "string" and #bytes > 0) then
    return nil, "could not read that file"
  end
  return bytes
end

-- ------- the whole flow, from one keypress
--
-- Pick, read, and copy the model to the save directory. Returns false plus a
-- reason if anything failed.
function PlayerModelPick.install(targetDir)
  local path = PlayerModelPick.choose()
  if not path then return false, "no file chosen" end
  
  local bytes, err = PlayerModelPick.read(path)
  if not bytes then return false, err end
  
  -- Extract the filename from the path
  local filename = path:match("[^/\\]+$") or "player_model.obj"
  
  -- Determine the target path in the save directory
  local targetPath = (targetDir or "player_models") .. "/" .. filename
  
  -- Write the file to the save directory
  local f = love and love.filesystem
  if not (f and f.write) then return false, "no filesystem" end
  
  local ok, err = pcall(f.write, targetPath, bytes)
  if not ok then return false, tostring(err) end
  
  return true, filename
end

-- ------- the action
--
-- Triggered from the options menu row. Opens the file picker and installs
-- the selected model.
function PlayerModelPick.action()
  print("PlayerModelPick.action: Starting model import")
  
  -- Ensure the directory exists
  PlayerModelInstall.ensureDirectory()
  
  local ok, filename = PlayerModelPick.install(PlayerModelInstall.DIR)
  if not ok then
    print("PlayerModelPick.action: Failed to install player model:", filename)
    return false
  end
  
  print("PlayerModelPick.action: Model file copied to:", filename)
  
  -- Update the marker
  PlayerModelInstall.writeMarker(filename)
  print("PlayerModelPick.action: Marker written")
  
  -- Reload the model
  local PlayerModel = V.require("PlayerModel")
  PlayerModel.clear()
  local loadOk, loadErr = PlayerModel.load(filename)
  print("PlayerModelPick.action: Model load result:", loadOk, loadErr)
  
  print("PlayerModelPick.action: Player model installed:", filename)
  return true
end

-- ------- Stadium Pokemon player model
--
-- Cycle through Pokemon species for the player model
-- dir: 1 for forward (right arrow), -1 for backward (left arrow)
function PlayerModelPick.cyclePokemonPlayer(dir)
  dir = dir or 1  -- Default to forward if no direction specified
  local PlayerModel = V.require("PlayerModel")
  local current = PlayerModel.getStadiumDex()
  
  -- Find current index in popular list
  local currentIndex = 0
  for i, species in ipairs(PlayerModelPick.POPULAR_SPECIES) do
    if species.dex == current then
      currentIndex = i
      break
    end
  end
  
  -- Move to next/previous species based on direction
  local nextIndex
  if dir > 0 then
    -- Forward (right arrow): count up
    nextIndex = currentIndex + 1
    if nextIndex > #PlayerModelPick.POPULAR_SPECIES then
      nextIndex = 0  -- Disable (back to normal player sprite)
    end
  else
    -- Backward (left arrow): count down
    if currentIndex == 0 then
      -- If currently disabled, go to the last species (151)
      nextIndex = #PlayerModelPick.POPULAR_SPECIES
    else
      nextIndex = currentIndex - 1
      if nextIndex < 0 then
        nextIndex = 0  -- Disable
      end
    end
  end
  
  -- Ensure the directory exists
  PlayerModelInstall.ensureDirectory()
  
  if nextIndex == 0 then
    -- Disable Stadium player model
    PlayerModel.clear()
    PlayerModelInstall.writeMarker("")
    print("PlayerModelPick.cyclePokemonPlayer: Stadium player model disabled")
  else
    local species = PlayerModelPick.POPULAR_SPECIES[nextIndex]
    local ok = PlayerModel.loadStadium(species.dex)
    if ok then
      PlayerModelInstall.writeMarker("stadium_player_" .. species.dex)
      print("PlayerModelPick.cyclePokemonPlayer: Player model set to", species.name)
    else
      print("PlayerModelPick.cyclePokemonPlayer: Failed to load", species.name)
    end
  end
end

-- ------- the row
--
-- An ACTION rather than a value, similar to StadiumRomPick. Shows the current
-- state (NONE/INSTALLED) and allows the player to pick a new model.
--
-- nil where no dialog can be opened, which takes the row off the menu
-- entirely rather than offering a button that cannot do anything.
function PlayerModelPick.row()
  if not PlayerModelPick.canDialog() then return nil end
  
  return {
    id = PlayerModelPick.ID,
    label = PlayerModelPick.LABEL,
    value = function()
      if PlayerModelInstall.installed() then
        local filename = PlayerModelInstall.modelFilename()
        return "INSTALLED: " .. (filename or "unknown")
      else
        return "IMPORT"
      end
    end,
    step = function(game)
      pcall(PlayerModelPick.action)
      return true
    end,
  }
end

-- ------- the Pokemon player row
--
-- A separate option to cycle through Pokemon species for the player model.
-- This requires Stadium models to be installed.
function PlayerModelPick.mewtwoRow()
  return {
    id = PlayerModelPick.MEWTWO_ID,
    label = PlayerModelPick.MEWTWO_LABEL,
    value = function()
      local PlayerModel = V.require("PlayerModel")
      local current = PlayerModel.getStadiumDex()
      if not current then
        return "OFF"
      end
      -- Find the name
      for _, species in ipairs(PlayerModelPick.POPULAR_SPECIES) do
        if species.dex == current then
          return species.name
        end
      end
      return "DEX " .. current
    end,
    step = function(game, dir)
      pcall(PlayerModelPick.cyclePokemonPlayer, dir)
      return true
    end,
  }
end

-- ------- Stadium follower selection
--
-- Cycle through popular species for the follower
-- dir: 1 for forward (right arrow), -1 for backward (left arrow)
function PlayerModelPick.cycleFollower(dir)
  dir = dir or 1  -- Default to forward if no direction specified
  local StadiumFollower = V.require("StadiumFollower")
  local current = StadiumFollower.getSpecies()
  
  -- Find current index in popular list
  local currentIndex = 0
  for i, species in ipairs(PlayerModelPick.POPULAR_SPECIES) do
    if species.dex == current then
      currentIndex = i
      break
    end
  end
  
  -- Move to next/previous species based on direction
  local nextIndex
  if dir > 0 then
    -- Forward (right arrow): count up
    nextIndex = currentIndex + 1
    if nextIndex > #PlayerModelPick.POPULAR_SPECIES then
      nextIndex = 0  -- Disable
    end
  else
    -- Backward (left arrow): count down
    if currentIndex == 0 then
      -- If currently disabled, go to the last species (151)
      nextIndex = #PlayerModelPick.POPULAR_SPECIES
    else
      nextIndex = currentIndex - 1
      if nextIndex < 0 then
        nextIndex = 0  -- Disable
      end
    end
  end
  
  if nextIndex == 0 then
    StadiumFollower.setSpecies(nil)
    print("PlayerModelPick.cycleFollower: Follower disabled")
  else
    local species = PlayerModelPick.POPULAR_SPECIES[nextIndex]
    local ok = StadiumFollower.setSpecies(species.dex)
    if ok then
      print("PlayerModelPick.cycleFollower: Follower set to", species.name)
    else
      print("PlayerModelPick.cycleFollower: Failed to load", species.name)
    end
  end
end

-- ------- the follower row
--
-- A simple button to cycle through popular follower species
function PlayerModelPick.followerRow()
  return {
    id = PlayerModelPick.FOLLOWER_ID,
    label = PlayerModelPick.FOLLOWER_LABEL,
    value = function()
      local StadiumFollower = V.require("StadiumFollower")
      local current = StadiumFollower.getSpecies()
      -- If not loaded, try to read from marker file for display purposes
      if not current then
        current = StadiumFollower.readSaved()
      end
      if not current then
        return "OFF"
      end
      -- Find the name
      for _, species in ipairs(PlayerModelPick.POPULAR_SPECIES) do
        if species.dex == current then
          return species.name
        end
      end
      return "DEX " .. current
    end,
    step = function(game, dir)
      pcall(PlayerModelPick.cycleFollower, dir)
      return true
    end,
  }
end

-- ------- Stadium wilds row
--
-- A toggle option to enable/disable stadium models for wild Pokemon
function PlayerModelPick.wildsRow()
  local StadiumWilds = V.require("StadiumWilds")
  local row = StadiumWilds.setting:row()
  row.id = PlayerModelPick.WILDS_ID
  row.label = PlayerModelPick.WILDS_LABEL
  return row
end

return PlayerModelPick
