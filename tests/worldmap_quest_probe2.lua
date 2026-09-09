-- Probe 2: the exact shape of progress.
--
-- Probe 1 found the seams: game.save.flags carries 129 NAMED pokered event
-- flags, game.save.inventory is the bag lib/StartMenuMap.lua could not find,
-- and data.constants.badges is a list of eight somethings. This reads all of
-- them out in full, because an objective chain written against a guess at
-- these names is a chain that points somewhere wrong on somebody else's save.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/worldmap_quest2.log", "w"))
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
  local S = game.save

  local function line(t)
    local rows = {}
    for k, v in pairs(t or {}) do
      rows[#rows + 1] = tostring(k) .. "=" .. tostring(v):sub(1, 30)
    end
    table.sort(rows)
    return table.concat(rows, " ")
  end

  log("=== data.constants.badges ===")
  for i, b in ipairs(d.constants.badges or {}) do
    log(("  [%d] %s"):format(i, type(b) == "table" and line(b) or tostring(b)))
  end
  log("")
  log("=== data.constants.hmBadges ===")
  for k, v in pairs(d.constants.hmBadges or {}) do
    log(("  %-10s %s"):format(k, type(v) == "table" and line(v) or tostring(v)))
  end
  log("")
  log("=== data.field.badgeGates ===")
  for k, v in pairs((d.field or {}).badgeGates or {}) do
    log(("  %-18s %s"):format(k, type(v) == "table" and line(v) or tostring(v)))
  end

  log("")
  log("=== every flag this save carries (" ..
      (function() local c = 0 for _ in pairs(S.flags or {}) do c = c + 1 end
       return c end)() .. ") ===")
  local names = {}
  for k in pairs(S.flags or {}) do names[#names + 1] = k end
  table.sort(names)
  for _, k in ipairs(names) do
    -- the per-trainer flags are noise for an objective chain; fold them
    if not k:find("_TRAINER_%d+$") then
      log(("  %-46s %s"):format(k, tostring(S.flags[k])))
    end
  end
  local trainers = 0
  for _, k in ipairs(names) do if k:find("_TRAINER_%d+$") then trainers = trainers + 1 end end
  log("  (" .. trainers .. " per-trainer flags folded away)")

  log("")
  log("=== the bag ===")
  log("inventory: " .. line(S.inventory))
  log("bagOrder: " .. table.concat(S.bagOrder or {}, " "))

  log("")
  log("=== visited / pokedex / misc ===")
  log("visited: " .. line(S.visited))
  log("pokedex keys: " .. line(type(S.pokedex) == "table" and
      (function() local o = {} for k, v in pairs(S.pokedex) do
         o[k] = type(v) == "table" and ("table#" .. #v) or v end return o end)() or {}))
  log("lastHeal: " .. line(S.lastHeal))
  log("lastOutdoor: " .. line(S.lastOutdoor))
  log("objectToggles: " .. line(S.objectToggles))
  log("meta: " .. line(S.meta))

  log("")
  log("=== how a badge is checked ===")
  -- probe 1 saw checkBadgeGate on the overworld state
  local st = game.stack.states and game.stack.states[1]
  if st and st.checkBadgeGate then
    log("stack.states[1].checkBadgeGate exists")
  end
  for _, name in ipairs({ "src.world.Badges", "src.core.Badges",
                          "src.world.Progress", "src.data.Badges" }) do
    local ok, M = pcall(require, name)
    log("  " .. name .. ": " .. tostring(ok and type(M)))
  end

  log("")
  log("DONE")
  logf:close()
  wait(2)
  love.event.quit()
end
