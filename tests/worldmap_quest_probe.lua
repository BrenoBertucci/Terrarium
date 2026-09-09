-- Probe: where does the game keep the player's PROGRESS?
--
-- A world map that tells you what to do next can only be as honest as what
-- it reads. A hardcoded list of "go to Pewter, then Cerulean" is fiction the
-- moment the player does anything out of order, and Gen 1 lets you do a
-- great deal out of order. So before any of it: what can actually be asked?
--
--   * BADGES -- the spine of the critical path, and the one thing every save
--     has. Where are they, and are they a count, a bitfield or a set?
--   * EVENT FLAGS -- what makes the difference between "beat Brock" and
--     "get the Poke Flute". Are they named, numbered, or absent?
--   * THE BAG -- lib/StartMenuMap.lua looked for it and could not find one
--     (`game.player` has no items field). Is it somewhere else?
--   * WHERE THE PLAYER IS, by map id, which is where any route has to start.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/worldmap_quest.log", "w"))
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

  local function dump(label, t, depth, maxKeys)
    if type(t) ~= "table" then
      log(label .. " = " .. type(t) .. " " .. tostring(t)); return
    end
    local rows, count = {}, 0
    for k, v in pairs(t) do
      count = count + 1
      if count <= (maxKeys or 60) then
        local d = type(v)
        if d == "table" then
          local nn = 0
          for _ in pairs(v) do nn = nn + 1 end
          d = "table(" .. #v .. "/" .. nn .. ")"
        elseif d == "boolean" or d == "number" or d == "string" then
          d = d .. "=" .. tostring(v):sub(1, 40)
        end
        rows[#rows + 1] = tostring(k) .. ":" .. d
      end
    end
    table.sort(rows)
    log(label .. " (" .. count .. " keys)")
    log("   " .. table.concat(rows, "  "))
  end

  log("=== the obvious places ===")
  dump("game", game, 1, 80)
  dump("game.player", game.player, 1, 80)
  dump("game.save", game.save, 1, 80)
  if game.save then
    for _, k in ipairs({ "player", "flags", "events", "badges", "options",
                         "progress", "world", "state", "bag", "items" }) do
      if game.save[k] ~= nil then dump("game.save." .. k, game.save[k], 1, 80) end
    end
  end
  if game.overworld then
    dump("game.overworld", game.overworld, 1, 40)
    if game.overworld.state then
      dump("game.overworld.state", game.overworld.state, 1, 60)
      local m = game.overworld.state.map
      log("current map id: " .. tostring(m and m.id))
    end
  end

  log("")
  log("=== anything that says 'badge', 'flag' or 'event' ===")
  local seen, hits = {}, 0
  local function hunt(t, path, depth)
    if type(t) ~= "table" or depth > 4 or seen[t] or hits > 60 then return end
    seen[t] = true
    for k, v in pairs(t) do
      local ks = tostring(k):lower()
      if ks:find("badge") or ks:find("flag") or ks:find("event")
         or ks:find("quest") or ks:find("progress") then
        hits = hits + 1
        local d = type(v)
        if d == "table" then
          local nn = 0
          for _ in pairs(v) do nn = nn + 1 end
          d = "table(" .. #v .. "/" .. nn .. ")"
        else
          d = d .. "=" .. tostring(v):sub(1, 60)
        end
        log("  " .. path .. "." .. tostring(k) .. " : " .. d)
        if type(v) == "table" then
          local rows, c = {}, 0
          for k2, v2 in pairs(v) do
            c = c + 1
            if c <= 24 then
              rows[#rows + 1] = tostring(k2) .. "=" .. tostring(v2):sub(1, 24)
            end
          end
          table.sort(rows)
          log("      " .. table.concat(rows, " "))
        end
      end
      if type(v) == "table" and not tostring(k):find("^__") then
        hunt(v, path .. "." .. tostring(k), depth + 1)
      end
    end
  end
  hunt(game, "game", 1)

  log("")
  log("=== the data side ===")
  local Game = require("src.core.Game")
  local d = Game.data
  for _, k in ipairs({ "constants", "field", "map_scripts", "items", "tokens",
                       "rulesets", "strings", "text" }) do
    if d[k] then
      local rows, c = {}, 0
      for k2, v2 in pairs(d[k]) do
        c = c + 1
        if c <= 30 then rows[#rows + 1] = tostring(k2) end
      end
      table.sort(rows)
      log("data." .. k .. " (" .. c .. "): " .. table.concat(rows, " "))
    end
  end

  -- badges are usually a constant list somewhere
  if d.constants then
    for k, v in pairs(d.constants) do
      local ks = tostring(k):lower()
      if ks:find("badge") or ks:find("gym") or ks:find("event") then
        log("constants." .. tostring(k) .. " = " .. type(v))
        if type(v) == "table" then
          local rows, c = {}, 0
          for k2, v2 in pairs(v) do
            c = c + 1
            if c <= 40 then
              rows[#rows + 1] = tostring(k2) .. "=" .. tostring(v2):sub(1, 20)
            end
          end
          table.sort(rows)
          log("    " .. table.concat(rows, " "))
        end
      end
    end
  end

  -- and what a gym map is called, so an objective can point at one
  log("")
  log("=== gyms and their towns ===")
  for id, def in pairs(d.maps) do
    if tostring(id):find("GYM") then
      log(("  %-28s label=%-24s tileset=%s"):format(
          id, tostring(def.label), tostring(def.tileset)))
    end
  end

  log("")
  log("DONE")
  logf:close()
  wait(2)
  love.event.quit()
end
