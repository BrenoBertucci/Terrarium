-- Does cutting the forest into bands actually pay?
--
-- tests/vertex_budget_probe.lua established the mechanism: the forest was
-- one mesh per species covering the whole map, submitted whole every frame,
-- and it was 75% of ROUTE_1's vertices and 80% of ROUTE_2's.  Cutting it
-- into 128px bands with a box each takes that to 29-64% of the trees.
--
-- What it does NOT establish is whether that is faster, and there is a real
-- reason to doubt it: a band is a draw call, the cut turns 8 tree draws into
-- roughly 130, and on this machine eighty-eight fewer draw calls were worth
-- two tenths of a millisecond.  Vertices saved against draws added is
-- exactly the trade that has to be MEASURED rather than argued.
--
-- So: the same scene, built both ways, alternating, several rounds, and the
-- reported number is the median of the per-round DIFFERENCES.  Blocks of A
-- then B measure the machine warming up -- that mistake is on the record
-- twice in this repo.
--
-- Both conditions also get a screenshot, because the cheapest way to ship a
-- broken cull is to ship a fast one: a band whose box is wrong does not look
-- wrong in a number, it looks wrong as a rectangle of missing forest.
--
--   POKEPORT_VERSION=yellow \
--   DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/tree_band_probe.lua gen1recomp

return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/tree_band_probe.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
    logf:write(table.concat(p, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end

  local Quality     = lib.require("Quality")
  local Weather     = lib.require("Weather")
  local DayNight    = lib.require("DayNight")
  local Wind        = lib.require("Wind")
  local MiniMap     = lib.require("MiniMap")
  local AutoFarm    = lib.require("AutoFarm")
  local AmbientLife = lib.require("AmbientLife")
  local CityLife    = lib.require("CityLife")
  local WildRoamers = lib.require("WildRoamers")
  local Trees3D     = lib.require("Trees3D")
  local ChunkMesher = lib.require("ChunkMesher")
  local Structures  = lib.require("Structures")
  local Pipelines   = require("src.render.Pipelines")

  love.window.setVSync(0)

  -- Everything that moves on its own is off.  Ambient life and the roamers
  -- are not seeded, so leaving them on puts a different set of creatures in
  -- each condition and the difference is charged to the trees.
  Pipelines.setLevel("terrarium_voxel", 3)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  MiniMap.setting:sync("off")
  AutoFarm.setting:sync("off")
  Weather.setting:sync("off")
  DayNight.setting:sync("day")
  Wind.setting:sync(0)
  AmbientLife.setting:sync("off")
  CityLife.setting:sync("off")
  WildRoamers.setting:sync("off")
  local KEEP_RES = Quality.setting:get()
  Quality.setting:sync(2)

  local CLOCK = 300
  local function hold(f)
    for _ = 1, f do DayNight.clock = CLOCK; coroutine.yield() end
    DayNight.clock = CLOCK
  end

  local function shot(name)
    -- Wait for the CALLBACK, not a fixed number of yields: a scheduled
    -- capture lands a frame or more later, and counting yields photographs
    -- whatever the world looked like afterwards.
    local done = false
    love.graphics.captureScreenshot(function(d)
      local f = io.open(OUT .. "/" .. name .. ".png", "wb")
      if f then f:write(d:encode("png"):getString()); f:close() end
      done = true
    end)
    local k = 0
    while not done and k < 300 do DayNight.clock = CLOCK; coroutine.yield(); k = k + 1 end
  end

  local SPOTS = {
    { "ROUTE_2", 10, 10, "up" },
    { "VIRIDIAN_CITY", 24, 22, "up" },
    { "ROUTE_1", 8, 12, "up" },
  }

  -- ------- the meter
  local COUNT = { draw = 0, verts = 0 }
  do
    local g = love.graphics
    local rawDraw = g.draw
    g.draw = function(a, ...)
      COUNT.draw = COUNT.draw + 1
      if type(a) == "userdata" then
        local okR, _, c = pcall(function() return a:getDrawRange() end)
        if okR and type(c) == "number" and c > 0 then
          COUNT.verts = COUNT.verts + c
        else
          local okV, v = pcall(function() return a:getVertexCount() end)
          if okV and type(v) == "number" then COUNT.verts = COUNT.verts + v end
        end
      end
      return rawDraw(a, ...)
    end
  end

  local function settle(maxTicks)
    local quiet = 0
    for _ = 1, (maxTicks or 3000) do
      DayNight.clock = CLOCK
      coroutine.yield()
      local map = game.overworld and game.overworld.map
      local done, state = Trees3D.ready(map)
      if ChunkMesher.pending() == 0 and (done or state == "hulls") then
        quiet = quiet + 1
        if quiet >= 45 then return true end
      else
        quiet = 0
      end
    end
    return false
  end

  local function median(t)
    local s = {}
    for i, v in ipairs(t) do s[i] = v end
    table.sort(s)
    if #s == 0 then return 0, 0, 0 end
    return s[math.ceil(#s / 2)], s[1], s[#s]
  end

  -- Banding is a BUILD-time decision, so flipping it means dropping the
  -- meshes and building them again.  BAND_OVER is the gate: above the site
  -- count it is one mesh per species, which is what shipped before.
  local function setBanding(on, spot)
    Trees3D.BAND_OVER = on and 120 or 1e9
    Trees3D.invalidate()
    game.overworld:setMap(spot[1], spot[2], spot[3], spot[4])
    return settle(4000)
  end

  local N = 90
  local function sample(spot)
    for _ = 1, 5 do
      game.overworld:setMap(spot[1], spot[2], spot[3], spot[4])
      hold(6)
    end
    hold(30)
    local dts, draws, verts = {}, {}, {}
    local prev = love.timer.getTime()
    for _ = 1, N do
      DayNight.clock = CLOCK
      COUNT.draw, COUNT.verts = 0, 0
      coroutine.yield()
      local t = love.timer.getTime()
      dts[#dts + 1] = (t - prev) * 1000
      prev = t
      draws[#draws + 1] = COUNT.draw
      verts[#verts + 1] = COUNT.verts
    end
    local ms, lo, hi = median(dts)
    return ms, lo, hi, median(draws), median(verts)
  end

  log("== does banding the forest pay? ==")
  log(("band %d px, gate %d sites"):format(Trees3D.BAND, 120))
  local ww, wh = love.graphics.getDimensions()
  log(("window %dx%d, RES 1/2 pinned, vsync off"):format(ww, wh))

  for _, spot in ipairs(SPOTS) do
    log("")
    log(("== %s (%d,%d) =="):format(spot[1], spot[2], spot[3]))
    local diffs = {}
    for round = 1, 3 do
      local okB = setBanding(true, spot)
      local bMs, bLo, bHi, bDraws, bVerts = sample(spot)
      local okW = setBanding(false, spot)
      local wMs, wLo, wHi, wDraws, wVerts = sample(spot)
      diffs[#diffs + 1] = wMs - bMs
      log(("   r%d banded %6.2f ms [%5.2f..%6.2f] draws=%-4d verts=%-8d settled=%s")
            :format(round, bMs, bLo, bHi, bDraws, bVerts, tostring(okB)))
      log(("      whole  %6.2f ms [%5.2f..%6.2f] draws=%-4d verts=%-8d settled=%s")
            :format(wMs, wLo, wHi, wDraws, wVerts, tostring(okW)))
      if round == 1 then
        -- One picture of each, same cell, same clock.  A cull that is fast
        -- and wrong looks exactly like a cull that is fast.
        setBanding(true, spot)
        sample(spot)
        shot("band_" .. spot[1] .. "_banded")
        setBanding(false, spot)
        sample(spot)
        shot("band_" .. spot[1] .. "_whole")
      end
    end
    local d, dlo, dhi = median(diffs)
    log(("   BANDING SAVES %+.2f ms   rounds %s")
          :format(d, table.concat({ ("%+.2f"):format(diffs[1] or 0),
                                    ("%+.2f"):format(diffs[2] or 0),
                                    ("%+.2f"):format(diffs[3] or 0) }, " / ")))
    log(("   spread across rounds %.2f ms -- if that is bigger than the saving,"):format(dhi - dlo))
    log( "   this is not a small measurement, it is not a measurement")
  end

  Trees3D.BAND_OVER = 120
  Trees3D.invalidate()
  Quality.setting:sync(KEEP_RES)
  AmbientLife.setting:sync("auto")
  love.window.setVSync(1)
  log("")
  log("done")
  logf:close()
  love.event.quit()
end
