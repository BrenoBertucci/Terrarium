-- What to do next, read off the save.
--
-- The world map draws Kanto; this decides what to point at. One question --
-- "what is the player's next step on the critical path" -- answered from the
-- save file and nothing else, so it is right on a fresh game, right on a
-- finished one, and right on a save that did things out of order.
--
-- WHAT IT READS, and why these and not the obvious thing.
--
-- The obvious thing is the event flags: `game.save.flags` carries pokered's
-- own names (EVENT_BEAT_BROCK, EVENT_GOT_SS_TICKET, and 127 more in the save
-- this was written against). They are exactly what you would want. The
-- trouble is that a flag which has not fired is not `false`, it is ABSENT --
-- the table only ever holds what is set. So the save cannot tell you what
-- the vocabulary is, and neither can the scripts: this build's map scripts
-- are native, and scanning the whole of Game.data for flag names turned up
-- 41 of them, every one about a Silph Co. door or a Seafoam boulder. Not one
-- EVENT_BEAT_* among them (tests/worldmap_quest_probe3.lua).
--
-- A step written against a flag name that this build never sets is a step
-- that never completes: an objective sitting on the map forever, pointing at
-- a town the player cleared an hour ago. That is worse than no objective.
--
-- So the chain is built on the two things that can be CHECKED:
--
--   BADGES are items. `save.inventory.BOULDERBADGE` is 1 when you have it,
--     and data.constants.badges is the ordered list of all eight. Nothing
--     removes a badge, so "have it" and "beat that leader" are the same
--     statement.
--   KEY ITEMS are items too, all of them confirmed present in data.items,
--     and in Gen 1 they persist -- the Poke Flute, the Silph Scope, the
--     Secret Key and the HMs are never consumed or sold away.
--
-- Four flags are used on top of that, and only four, because those four were
-- read verbatim out of a real save and are therefore known to exist.
--
-- Everything here is READ-ONLY. This file cannot set a flag, grant an item
-- or move the player; a wrong answer shows the wrong arrow and nothing else.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local WorldMapQuest = {}

WorldMapQuest.ENABLED = true

-- ---------------------------------------------------------------- the reads
local function inv(save, item)
  local bag = save and save.inventory
  local n = bag and bag[item]
  return type(n) == "number" and n > 0
end

local function flag(save, name)
  local f = save and save.flags
  return (f and f[name]) and true or false
end

-- Every badge the player carries, in the game's own order. The list of ids
-- comes from data.constants.badges rather than from a copy typed here, so a
-- ROM or a mod that renames one still counts them.
function WorldMapQuest.badges(save)
  local ok, Game = pcall(require, "src.core.Game")
  local ids = (ok and Game.data and Game.data.constants
               and Game.data.constants.badges) or nil
  local held, total = 0, 0
  local list = {}
  if type(ids) == "table" then
    for _, b in ipairs(ids) do
      local id = type(b) == "table" and b.id or b
      if type(id) == "string" then
        total = total + 1
        local got = inv(save, id)
        list[#list + 1] = { id = id, got = got }
        if got then held = held + 1 end
      end
    end
  end
  return held, total, list
end

local function badge(save, id) return inv(save, id) end

-- ------------------------------------------------------------------ the text
--
-- English (US), the language of the ROM's own strings and of the screen
-- this feeds. One table, so a build in another language is a translation
-- and not a rewrite.
--
-- `title` is the instruction and `detail` is where to look once you are
-- there: the marker gets you to the town, and the town is not the hard part.

-- ------------------------------------------------------------------ the chain
--
-- In critical-path order, and read in order: the current objective is the
-- FIRST one that is not done. Each step is independently testable, so a
-- player who did something early simply has that step read as done and moves
-- past it -- the order is a preference, not a requirement.
--
-- `target` is always an OUTDOOR map, because that is what the world map can
-- put a marker on; the gym or the lab inside it is what `detail` says.
WorldMapQuest.CHAIN = {
  {
    id = "pokedex", target = "PALLET_TOWN",
    title = "Get the POKéDEX from PROF. OAK",
    detail = "At his lab in Pallet Town.",
    done = function(s) return flag(s, "EVENT_GOT_POKEDEX") end,
  },
  {
    id = "parcel", target = "PALLET_TOWN",
    title = "Deliver OAK's PARCEL",
    detail = "Pick it up at the Viridian Mart and bring it to the lab.",
    -- holding the parcel IS the objective: it is handed over, not consumed
    done = function(s) return not inv(s, "OAKS_PARCEL") end,
  },
  {
    id = "brock", target = "PEWTER_CITY",
    title = "Defeat BROCK, the Pewter Gym Leader",
    detail = "Pewter Gym. Earns the BOULDER BADGE.",
    done = function(s) return badge(s, "BOULDERBADGE") end,
  },
  {
    id = "misty", target = "CERULEAN_CITY",
    title = "Defeat MISTY, the Cerulean Gym Leader",
    detail = "Cerulean Gym. Earns the CASCADE BADGE.",
    done = function(s) return badge(s, "CASCADEBADGE") end,
  },
  {
    id = "ssanne", target = "VERMILION_CITY",
    title = "Board the S.S. ANNE and get HM01 CUT",
    detail = "The ship docked at Vermilion. It sails once you get off.",
    -- only while the ticket is in hand and the HM is not
    done = function(s) return inv(s, "HM_CUT") or not inv(s, "S_S_TICKET") end,
  },
  {
    id = "surge", target = "VERMILION_CITY",
    title = "Defeat LT. SURGE, the Vermilion Gym Leader",
    detail = "Vermilion Gym. Earns the THUNDER BADGE.",
    done = function(s) return badge(s, "THUNDERBADGE") end,
  },
  {
    id = "erika", target = "CELADON_CITY",
    title = "Defeat ERIKA, the Celadon Gym Leader",
    detail = "Celadon Gym. Earns the RAINBOW BADGE.",
    done = function(s) return badge(s, "RAINBOWBADGE") end,
  },
  {
    id = "scope", target = "CELADON_CITY",
    title = "Recover the SILPH SCOPE from Team Rocket",
    detail = "The hideout is under the Celadon Game Corner.",
    done = function(s) return inv(s, "SILPH_SCOPE") end,
  },
  {
    id = "flute", target = "LAVENDER_TOWN",
    title = "Free the POKéMON TOWER and rescue MR. FUJI",
    detail = "He gives you the POKé FLUTE, which wakes SNORLAX.",
    done = function(s) return inv(s, "POKE_FLUTE") end,
  },
  {
    id = "koga", target = "FUCHSIA_CITY",
    title = "Defeat KOGA, the Fuchsia Gym Leader",
    detail = "Wake the SNORLAX on Route 12 or 16 to get there.",
    done = function(s) return badge(s, "SOULBADGE") end,
  },
  {
    id = "surf", target = "FUCHSIA_CITY",
    title = "Find HM03 SURF in the Safari Zone",
    detail = "In the Secret House, deep in the Safari Zone.",
    done = function(s) return inv(s, "HM_SURF") end,
  },
  {
    id = "sabrina", target = "SAFFRON_CITY",
    title = "Free SILPH CO. and defeat SABRINA",
    detail = "Eleven floors of Rockets. Earns the MARSH BADGE.",
    done = function(s) return badge(s, "MARSHBADGE") end,
  },
  {
    id = "secret", target = "CINNABAR_ISLAND",
    title = "Find the SECRET KEY in the Pokémon Mansion",
    detail = "The ruined mansion on Cinnabar. It opens the Gym.",
    done = function(s) return inv(s, "SECRET_KEY") or badge(s, "VOLCANOBADGE") end,
  },
  {
    id = "blaine", target = "CINNABAR_ISLAND",
    title = "Defeat BLAINE, the Cinnabar Gym Leader",
    detail = "Cinnabar Gym. Earns the VOLCANO BADGE.",
    done = function(s) return badge(s, "VOLCANOBADGE") end,
  },
  {
    id = "giovanni", target = "VIRIDIAN_CITY",
    title = "Defeat GIOVANNI, the Viridian Gym Leader",
    detail = "The Gym that has been locked since the start.",
    done = function(s) return badge(s, "EARTHBADGE") end,
  },
  {
    -- ROUTE_23 and INDIGO_PLATEAU are not reached by the outdoor connection
    -- walk (Route 23 is behind a gate, not a map connection), so the marker
    -- goes to the last place that IS on the map and the text carries the
    -- rest. See WorldMap3D.placeFor.
    id = "league", target = "ROUTE_22", fallback = "VIRIDIAN_CITY",
    title = "Cross VICTORY ROAD and challenge the ELITE FOUR",
    detail = "West of Viridian, through Route 22 and the Route 23 gate.",
    done = function(s)
      local held, total = WorldMapQuest.badges(s)
      return total > 0 and held >= total and flag(s, "EVENT_BEAT_CHAMPION")
    end,
  },
}

-- ------------------------------------------------------------------- the read
--
-- The current step, plus the two after it, plus how far along the whole
-- chain is. Nil when there is nothing left to point at.
function WorldMapQuest.current(save)
  if not (WorldMapQuest.ENABLED and type(save) == "table") then return nil end
  local doneCount = 0
  local now, upcoming = nil, {}
  for _, step in ipairs(WorldMapQuest.CHAIN) do
    local ok, finished = pcall(step.done, save)
    finished = ok and finished and true or false
    if finished then
      doneCount = doneCount + 1
    elseif not now then
      now = step
    elseif #upcoming < 2 then
      upcoming[#upcoming + 1] = step
    end
  end
  if not now then return nil end
  local held, total = WorldMapQuest.badges(save)
  return {
    step = now,
    upcoming = upcoming,
    doneCount = doneCount,
    total = #WorldMapQuest.CHAIN,
    badges = held,
    badgeTotal = total,
  }
end

-- Where the player is, as an OUTDOOR map id -- which is what a route has to
-- start from. Indoors, the save remembers the last outdoor map, and that is
-- the door they will come back out of.
function WorldMapQuest.playerMap(save)
  if type(save) ~= "table" then return nil end
  local lo = save.lastOutdoor
  local here = save.player and save.player.map
  local ok, Game = pcall(require, "src.core.Game")
  local maps = ok and Game.data and Game.data.maps
  if here and maps and maps[here] then
    local okM, Map = pcall(require, "src.world.Map")
    if okM then
      local okO, outdoor = pcall(Map.isOutdoor, maps[here])
      if okO and outdoor then return here end
    end
  end
  return (lo and lo.id) or here
end

return WorldMapQuest
