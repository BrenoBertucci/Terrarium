-- The one knob for this mod's own drawn UI text: English or Portuguese.
--
-- WHAT IT COVERS: the words this mod paints itself -- the battle command
-- buttons (ATTACK / SWITCH / ITEMS / FLEE), the bag's pocket tabs, and the
-- start menu's MAP row. Three places, and they are the only ones: a word
-- this mod draws that is not in here is a bug in the wiring, not a choice.
--
-- WHY ENGLISH IS THE DEFAULT. It is what those three already said. The 5X
-- pack's buttons carried their own English words baked in and left the
-- repository with the rest of the Nintendo-derived art in 1.37.0-beta; what
-- replaced them is the concept board's wording, also English. The engine's
-- own start menu prints ITEM, in English, right where the MAP row lands
-- (src/ui/StartMenu.lua). PORTUGUES is for a save running under a
-- Portuguese translation mod, where those three would otherwise be the only
-- English left on the screen.
--
-- WHAT IT DOES NOT COVER: anything the ENGINE prints -- dialogue, item
-- names, the flat 160x144 menus this mod silences. Those come from the ROM
-- and from src/core/Strings.lua and stay whatever language the base game
-- and its own translation mods put them in. This row is cosmetic to this
-- mod's own overlays, and switching it mid-game is safe: every reader picks
-- its word at draw time.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local Lang = {}

Lang.setting = ModSetting.new("language", "LANGUAGE",
  { "en", "pt" }, { "ENGLISH", "PORTUGUES" })

function Lang.get()
  return Lang.setting:get()
end

function Lang.isPT()
  return Lang.get() == "pt"
end

-- Pick between an English and a Portuguese string for this mod's own drawn
-- text -- `en` first because it is values[1], the default, and the one an
-- unreadable stored value falls back to.
function Lang.pick(en, pt)
  return Lang.isPT() and pt or en
end

return Lang
