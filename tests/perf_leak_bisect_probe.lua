-- Probe: bisect the per-visit heap leak by switching systems off. Each phase
-- turns one more row off (in memory -- sync, never written) and teleports
-- through maps; after each visit, a full collection and the live heap. A
-- phase whose visits stop growing the heap turned the leak off.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/perf_leak_bisect.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local okAll, err = pcall(function()
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b) game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield() end
  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do wait(1); n = n + 1; if n > 900 then break end end
  n = 0
  while game.stack:top() ~= game.overworld do tap("a"); wait(10); n = n + 11; if n > 1500 then break end end
  local ow = game.overworld
  ow.rollEncounter = function() return nil end
  local lib = game.mods.exports.TERRARIUM.lib
  local function req(x) local ok, m = pcall(lib.require, x) return ok and m or nil end
  local clock = love.timer.getTime
  local WAIT = tonumber(os.getenv("DS_WAIT") or "12")
  local function live()
    collectgarbage("collect"); collectgarbage("collect")
    return collectgarbage("count") / 1024
  end
  local function sync(mod, field, v)
    local M = req(mod)
    local s = M and M[field]
    if s then pcall(s.sync, s, v) end
  end
  local function visit(id)
    pcall(function() ow:setMap(id, 8, 8, "down") end)
    local t0 = clock()
    while clock() - t0 < WAIT do
      coroutine.yield()
      if game.stack:top() ~= ow then pcall(function() game.stack:pop() end) end
    end
    return live()
  end
  -- two maps a phase, bouncing between them so every visit is a rebuild of
  -- something just evicted
  local PHASES = {
    { "as saved", function() end },
    { "+SKYLINE OFF", function() sync("Skyline", "setting", 0) end },
    { "+GROUND OFF", function() sync("GroundFX", "setting", "off") end },
    { "+TOWER/LEDGES/SHOP CLASSIC", function()
        sync("TowerKit", "setting", "classic"); sync("LedgeKit", "setting", "classic")
        sync("Shop", "setting", "classic") end },
    { "+GRASS VOXEL", function() sync("Grass3D", "setting", "voxel") end },
    { "+SHADOWS OFF", function() sync("Quality", "shadowSetting", "off") end },
    { "+WIND OFF +WATER CLASSIC", function()
        sync("Wind", "setting", 0); sync("Water", "style", "classic") end },
    { "+AMBIENT/TOWN/ROUTINE OFF", function()
        sync("AmbientLife", "setting", "off"); sync("CityLife", "setting", "off")
        sync("Routines", "setting", "off") end },
  }
  local PAIRS = {
    { "ROUTE_1", "VIRIDIAN_CITY" }, { "ROUTE_2", "PEWTER_CITY" }, { "ROUTE_3", "ROUTE_4" },
    { "CERULEAN_CITY", "ROUTE_24" }, { "ROUTE_5", "ROUTE_6" }, { "VERMILION_CITY", "ROUTE_11" },
    { "ROUTE_7", "ROUTE_8" }, { "LAVENDER_TOWN", "ROUTE_10" },
  }
  local base = visit("PALLET_TOWN")
  log(("start: PALLET live %.1f MB"):format(base))
  for i, ph in ipairs(PHASES) do
    ph[2]()
    local p = PAIRS[i]
    local a = visit(p[1])
    local b = visit(p[2])
    local c = visit(p[1])
    local d = visit(p[2])
    log(("%-28s %s/%s: %.0f -> %.0f -> %.0f -> %.0f MB   (growth over the 2nd round: %+.0f MB)"):format(
      ph[1], p[1], p[2], a, b, c, d, d - b))
  end
  end)
  if not okAll then log("ERROR", tostring(err)) end
  logf:close()
  love.event.quit()
end
