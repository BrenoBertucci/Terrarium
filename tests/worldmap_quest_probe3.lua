-- Probe 3: every EVENT_ flag name this build actually uses.
--
-- game.save.flags only ever holds the flags that are SET -- an unfinished
-- event is an absent key, not a false one. So the save cannot tell you what
-- the full vocabulary is, and an objective written against a flag name that
-- this build never sets is an objective that never completes: it would sit
-- on the map forever, pointing at a town the player already cleared.
--
-- The scripts know. Walk the whole of Game.data and collect every string
-- that looks like a flag name, plus which map script mentions it -- that is
-- the authoritative list, and it is also a rough index of WHERE each event
-- happens, which is exactly what an objective marker needs.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/worldmap_quest3.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    game.input.pressQueue[#game.input.pressQueue + 1] = "a"
    wait(10); n = n + 11
    if n > 1500 then break end
  end
  wait(45)

  local Game = require("src.core.Game")
  local d = Game.data

  -- where each flag name is mentioned, by top-level map script
  local where = {}
  local function note(name, home)
    where[name] = where[name] or {}
    if home and not where[name][home] then
      where[name][home] = true
      where[name].n = (where[name].n or 0) + 1
    end
  end

  local seen = {}
  local function scan(t, home, depth)
    if type(t) ~= "table" or depth > 8 or seen[t] then return end
    seen[t] = true
    for k, v in pairs(t) do
      if type(k) == "string" and k:find("^EVENT_") then note(k, home) end
      if type(v) == "string" then
        if v:find("^EVENT_") then note(v, home) end
      elseif type(v) == "table" then
        scan(v, home, depth + 1)
      end
    end
  end

  if d.map_scripts then
    for mapId, script in pairs(d.map_scripts) do
      seen = {}
      scan(script, mapId, 1)
      coroutine.yield()
    end
  end
  seen = {}
  scan(d.field, "data.field", 1)
  seen = {}
  scan(d.constants, "data.constants", 1)

  local names = {}
  for k in pairs(where) do names[#names + 1] = k end
  table.sort(names)
  log("=== " .. #names .. " flag names, and where they are mentioned ===")
  local S = game.save
  for _, k in ipairs(names) do
    local homes, c = {}, 0
    for h in pairs(where[k]) do
      if h ~= "n" then c = c + 1; if c <= 4 then homes[#homes + 1] = h end end
    end
    table.sort(homes)
    if c > 4 then homes[#homes + 1] = "+" .. (c - 4) end
    log(("  %-46s %-5s %s"):format(k,
        (S.flags and S.flags[k]) and "SET" or "-", table.concat(homes, ",")))
  end

  -- and the items, because badges live in the bag and so do the key items an
  -- objective turns on
  log("")
  log("=== key items the chain might ask about ===")
  for _, want in ipairs({ "POKE_FLUTE", "SILPH_SCOPE", "LIFT_KEY", "CARD_KEY",
                          "S_S_TICKET", "BIKE_VOUCHER", "BICYCLE", "OLD_ROD",
                          "GOOD_ROD", "SUPER_ROD", "SECRET_KEY", "HM_SURF",
                          "HM_STRENGTH", "HM_CUT", "HM_FLY", "HM_FLASH",
                          "OAKS_PARCEL", "TOWN_MAP", "DOME_FOSSIL",
                          "HELIX_FOSSIL", "OLD_AMBER" }) do
    local known = d.items and d.items[want] ~= nil
    log(("  %-16s in data.items=%-5s  held=%s"):format(
        want, tostring(known), tostring((S.inventory or {})[want])))
  end

  log("")
  log("=== the maps an objective would point at ===")
  for _, want in ipairs({ "INDIGO_PLATEAU", "ROUTE_23", "VICTORY_ROAD_1",
                          "SAFARI_ZONE_ENTRANCE", "SILPH_CO_1F",
                          "POKEMON_TOWER_1", "POKEMON_TOWER_7",
                          "VIRIDIAN_GYM", "CINNABAR_GYM", "SAFFRON_GYM",
                          "FUCHSIA_GYM", "CELADON_GYM", "VERMILION_GYM",
                          "CERULEAN_GYM", "PEWTER_GYM", "OAKS_LAB",
                          "ROCKET_HIDEOUT_1", "SEAFOAM_ISLANDS_1" }) do
    local def = d.maps[want]
    log(("  %-24s %s"):format(want, def and ("exists, label=" ..
        tostring(def.label)) or "MISSING"))
  end

  log("")
  log("DONE")
  logf:close()
  wait(2)
  love.event.quit()
end
