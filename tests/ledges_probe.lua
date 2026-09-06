-- Probe: the hop-down ledges stand as banks (lib/LedgeKit.lua).
--
--   BUILD   in five places holding every kind of ledge cell, the bank
--           models build (ground variants keyed "@tile"), stand at the
--           bank's height over their cells, and leave the grass or path
--           sharing a cell unclaimed (claimMask).
--   LOOK    screenshots of each kind, day, and one at night.
--   TOGGLE  the LEDGES row on CLASSIC stamps nothing; BANK brings it back.
--   COST    frame time on Route 4, the map with the most ledge cells.
--
-- Traps respected: hour pinned with DayNight.setting:sync, 3D pass polled
-- via Voxel3D.lampLights, screenshots wait on their callback, the player's
-- drift released around every wait (memory: terrarium-pokemon-tower-
-- towerkit).
--
-- POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
-- POKEPORT_DRIVER=mods/TERRARIUM/tests/ledges_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/ledges_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit()
      return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit()
    return
  end
  log("version:", exports.TERRARIUM.version)

  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local Voxel3D = lib.require("Voxel3D")
  local Structures = lib.require("Structures")
  local Buildings = lib.require("Buildings")
  local StreetLamps = lib.require("StreetLamps")
  local MarioCam = lib.require("MarioCam")
  local MiniMap = lib.require("MiniMap")
  local AutoFarm = lib.require("AutoFarm")
  local LedgeKit = lib.require("LedgeKit")
  local TowerKit = lib.require("TowerKit")
  local ChunkMesher = lib.require("ChunkMesher")
  local Pipelines = require("src.render.Pipelines")
  Pipelines.setLevel("terrarium_voxel", 4)
  Pipelines.setLevel("terrarium_tiltshift", 0)

  Weather.setting:sync("off")
  DayNight.darkSetting:sync("deep")
  StreetLamps.setting:sync(true)
  MiniMap.setting:setIndex(3, game)
  AutoFarm.setting:setIndex(1, game)
  MarioCam.setting:setIndex(1, game)          -- the orbit camera
  LedgeKit.setting:sync("bank")
  TowerKit.setting:sync("new")
  local ww, wh = love.graphics.getDimensions()
  log(("window: %dx%d"):format(ww, wh))

  local fails = {}
  local function check(ok, msg)
    if not ok then fails[#fails + 1] = msg end
    log((ok and "  ok   " or "  FAIL ") .. msg)
  end

  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name .. ".png", "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      done = true
    end)
    local guard = 0
    while not done and guard < 600 do coroutine.yield() guard = guard + 1 end
    return done
  end

  local function releaseDirs()
    local st = game.input.state
    for _, d in ipairs({ "up", "down", "left", "right" }) do
      st[d] = false
      if game.input.sources then game.input.sources[d] = nil end
    end
    game.input.pressQueue = {}
  end

  local function voxelUp(guard)
    for _ = 1, guard or 900 do
      if Voxel3D.lampLights ~= nil then return true end
      coroutine.yield()
    end
    return false
  end

  local function lockCell(guard)
    local last, stable = nil, 0
    for _ = 1, guard or 1200 do
      local p = game.overworld.player
      local cur = p and (tostring(p.cellX) .. "," .. tostring(p.cellY)) or "?"
      if cur == last then stable = stable + 1 else stable, last = 0, cur end
      if stable >= 45 then return true, cur end
      coroutine.yield()
    end
    return false, last
  end

  -- A map's structure cache is published when its build FINISHES
  -- (Structures.forMap's last line), so peek() is the completion signal;
  -- and the 3D pass only draws once the meshes are up -- lampLights is
  -- reset first so the poll cannot be satisfied by the previous map's.
  local function structuresUp(map, guard)
    for _ = 1, guard or 4000 do
      if Structures.peek(map) then return true end
      coroutine.yield()
    end
    return false
  end

  local function arrive(mapId, cx, cy, hour)
    DayNight.setting:sync(hour or "day")
    Voxel3D.lampLights = nil
    game.overworld:setMap(mapId, cx, cy, "down")
    wait(30)
    releaseDirs()
    local map = game.overworld.map
    local built = structuresUp(map)
    local up = voxelUp(2000)
    log(("  arrive %s (%d,%d): structures %s, 3D pass %s")
        :format(mapId, cx, cy, built and "built" or "NOT BUILT",
                up and "up" or "NOT UP"))
    lockCell()
    releaseDirs()
    wait(240)
    releaseDirs()
  end

  local function hour(mode, settle)
    DayNight.setting:sync(mode)
    releaseDirs()
    wait(settle or 220)
    releaseDirs()
  end

  -- Structures' tile key (lib/Buildings.lua keyOf)
  local function keyOf(tx, ty) return (ty + 64) * 4096 + (tx + 64) end

  -- how many bank models the build cache holds (keys "OVERWORLD:<i>@<g>")
  local function bankModels()
    local ok, st = pcall(Buildings.stats)
    local nb, quads = 0, 0
    if ok and st then
      for k, v in pairs(st) do
        if k:find("@", 1, true) then nb = nb + 1; quads = quads + (v.quads or 0) end
      end
    end
    return nb, quads
  end

  -- ------- 1. BUILD + LOOK, per site
  local SITES = {
    -- { map, player cell, ledge cells to measure { cx, cy, minTop }, unclaimed tile {tx,ty} or nil, claimed tile }
    { "CERULEAN_CITY", 7, 5,
      { { 6, 3, 7 }, { 7, 3, 7 }, { 5, 3, 3 }, { 13, 3, 3 }, { 13, 1, 7 } },
      nil, { 12, 6 } },
    { "FUCHSIA_CITY", 4, 25,
      { { 2, 23, 7 }, { 2, 24, 7 }, { 2, 25, 5 }, { 2, 26, 5 }, { 2, 22, 3 } },
      { 5, 52 }, { 4, 46 } },
    { "ROUTE_24", 15, 6,
      { { 13, 4, 7 }, { 13, 5, 7 }, { 13, 7, 5 } }, nil, { 26, 8 } },
    { "PEWTER_CITY", 6, 9,
      { { 5, 7, 5 }, { 6, 7, 5 } }, { 10, 14 }, { 10, 15 } },
    { "LAVENDER_TOWN", 2, 3,
      { { 1, 1, 7 }, { 2, 1, 7 }, { 5, 1, 3 } }, nil, { 2, 2 } },
  }
  for _, s in ipairs(SITES) do
    local mapId, px, py, cells, unclaimed, claimed = s[1], s[2], s[3], s[4], s[5], s[6]
    log("")
    log("[" .. mapId .. "]")
    arrive(mapId, px, py, "day")
    local map = game.overworld.map
    local S = Structures.peek(map)
    local nb2, quads = bankModels()
    log(("  bank models cached: %d (%d quads)"):format(nb2, quads))
    check(nb2 > 0, mapId .. ": bank models built")
    log("  Buildings.lastError:", tostring(Buildings.lastError))
    check(Buildings.lastError == nil, mapId .. ": no bank fell back")
    for _, c in ipairs(cells) do
      local top = Buildings.tallAt(map, c[1], c[2])
      log(("  tallAt(%d,%d) = %d (want >= %d)"):format(c[1], c[2], top, c[3]))
      check(top >= c[3], ("%s: bank stands at (%d,%d)"):format(mapId, c[1], c[2]))
    end
    if unclaimed and S then
      local k = keyOf(unclaimed[1], unclaimed[2])
      check(not S.skip[k], ("%s: the shared tile (%d,%d) is left unclaimed")
            :format(mapId, unclaimed[1], unclaimed[2]))
    end
    if claimed and S then
      local k = keyOf(claimed[1], claimed[2])
      check(S.skip[k] == true, ("%s: the ledge tile (%d,%d) is claimed")
            :format(mapId, claimed[1], claimed[2]))
    end
    shot(mapId:lower() .. "_day")
    if mapId == "CERULEAN_CITY" then
      hour("night")
      shot(mapId:lower() .. "_night")
    end
  end

  -- ------- 2. TOGGLE
  log("")
  log("[TOGGLE]")
  LedgeKit.setting:sync("classic")
  ChunkMesher.invalidate()
  arrive("CERULEAN_CITY", 7, 5, "day")
  local mapC = game.overworld.map
  log("  classic tallAt(6,3) =", Buildings.tallAt(mapC, 6, 3))
  check(Buildings.tallAt(mapC, 6, 3) == 0, "CLASSIC: the ledge is the profile's box again")
  shot("cerulean_classic_day")
  LedgeKit.setting:sync("bank")
  ChunkMesher.invalidate()
  arrive("CERULEAN_CITY", 7, 5, "day")
  local mapN = game.overworld.map
  check(Buildings.tallAt(mapN, 6, 3) >= 7, "BANK again: the bank is back")

  -- ------- 3. COST on Route 4
  log("")
  log("[COST]")
  love.window.setVSync(0)
  local clock = love.timer.getTime
  local function measure(frames)
    local dts, prev = {}, clock()
    for i = 1, frames do
      coroutine.yield()
      local now = clock()
      dts[i] = now - prev
      prev = now
    end
    table.sort(dts)
    local sum = 0
    for _, d in ipairs(dts) do sum = sum + d end
    local function pct(p)
      return dts[math.max(1, math.min(frames, math.ceil(frames * p)))]
    end
    return sum / frames, pct(0.5), pct(0.95)
  end
  arrive("ROUTE_4", 40, 6, "day")
  local nb4, q4 = bankModels()
  local S4 = Structures.peek(game.overworld.map)
  log(("  Route 4: %d bank models, %d quads, objectQuads=%d")
      :format(nb4, q4, S4 and #S4.objectQuads or -1))
  local m, p50, p95 = measure(150)
  log(("  route 4 day: mean=%.2fms p50=%.2fms p95=%.2fms")
      :format(m * 1000, p50 * 1000, p95 * 1000))
  shot("route4_day")
  love.window.setVSync(1)
  DayNight.setting:sync("day")

  log("")
  if #fails == 0 then log("ALL CHECKS PASSED")
  else
    log("FAILURES (" .. #fails .. "):")
    for _, f in ipairs(fails) do log("  - " .. f) end
  end
  logf:close()
  love.event.quit()
end
