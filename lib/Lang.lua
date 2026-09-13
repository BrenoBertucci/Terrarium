-- The one knob for this mod's own drawn UI text: Portuguese or English.
--
-- gen1recomp's own strings are English -- src/core/Strings.lua ships as an
-- identity function until a translation mod overrides its catalog, and the
-- ROM text this build extracts (data/generated/text.lua) is the original
-- English cartridge script. This mod's OWN battle/menu overlays (ITENS,
-- MAPA, OPÇÕES, LUTAR/FUGIR on the X/Y command buttons) are hardcoded
-- Portuguese instead, because that is the language this mod has always been
-- authored in. Portuguese stays the default for exactly that reason; English
-- is here for a player who wants this mod's own glass-panel menus (the start
-- menu, the bag, the battle command buttons) to read in English instead,
-- independent of whatever the underlying game and its own translation mods
-- (if any) print everywhere else.
--
-- What this does NOT translate: the engine's own screens (the flat 160x144
-- menus this mod silences, dialogue, item names) -- those come from the ROM
-- and from Strings.lua, and stay whatever language the base game and its
-- own translation mods put them in. This is cosmetic to this mod's overlays
-- only.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local Lang = {}

Lang.setting = ModSetting.new("language", "IDIOMA",
  { "pt", "en" }, { "PORTUGUÊS", "ENGLISH" })

function Lang.get()
  return Lang.setting:get()
end

function Lang.isPT()
  return Lang.get() == "pt"
end

-- Pick between an English and a Portuguese string for this mod's own drawn
-- text, by the current setting -- `en` first because that is the ROM's own
-- reading order, even though `pt` is what actually shows by default.
function Lang.pick(en, pt)
  return Lang.isPT() and pt or en
end

return Lang
