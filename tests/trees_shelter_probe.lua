-- Does the ground under a crown know it is under a crown?
--
-- The claim is a per-cell canopy cover, baked when the map binds off where
-- the crowns actually landed, riding the alpha channel of GrassWear's
-- field and read by GroundFX to keep the ground dry and the snow thin.
--
-- Four ways that passes every count and is still wrong, which is what this
-- measures rather than asserts:
--
--   1. NOTHING BAKED. Trees3D.eachCanopyCell is guarded at every step (no
--      bake, no sites, over the ceiling) and every one of those guards
--      returns nil quietly. A field of zeroes is indistinguishable from
--      "this map has no trees" unless you count the cells.
--   2. BAKED SOMEWHERE ELSE. The cover is derived from the same
--      `placement` the mesh stamp uses, but only the offline check pins
--      that on one site. On a real route the question is whether cover
--      lands on the cells that actually HAVE trees -- so this correlates
--      the field against the site list.
--   3. BAKED EVERYWHERE. A cover that saturates the whole map dries the
--      entire route and reads as "rain stopped working". The open-ground
--      share is as much the result as the covered share.
--   4. NEVER REACHED THE GROUND. GroundFX's thresholds are what turn the
--      field into pixels, so the counts below are run through the real
--      constants rather than through a number retyped here.
--
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/trees_shelter_probe.lua
--   DS_PROBE_DIR=<absolute scratch dir>
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/trees_shelter_probe.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring((select(i, ...))) end
    logf:write(table.concat(p, " ") .. "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b
    coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: never booted"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end

  local lib = game.mods.exports.TERRARIUM.lib
  local Voxel3D   = lib.require("Voxel3D")
  local Trees3D   = lib.require("Trees3D")
  local GrassWear = lib.require("GrassWear")
  local GroundFX  = lib.require("GroundFX")
  local Structures = lib.require("Structures")
  local DayNight  = lib.require("DayNight")
  local Weather   = lib.require("Weather")

  log("voxel shader:", Voxel3D.shader() and "PASS" or "FAIL",
      tostring(Voxel3D.shaderError))
  log("bake:", Trees3D.available() and "PASS" or "FAIL")
  log(string.format("GroundFX thresholds: CANOPY_DRY=%.2f SNOW_KEEP=%.2f",
                    GroundFX.CANOPY_DRY, GroundFX.CANOPY_SNOW_KEEP))

  local function settle(label)
    local ticks = 0
    while ticks < 4000 do
      local map = game.overworld and game.overworld.map
      local done, state = Trees3D.ready(map)
      if Voxel3D.lampLights ~= nil and (done or state == "hulls") then
        if select(2, Trees3D.buildsInFlight()) == 0 or ticks > 1200 then
          log(string.format("settle %s: %s in %d ticks", label, state, ticks))
          return
        end
      end
      coroutine.yield(); ticks = ticks + 1
    end
    log("FAIL: settle " .. label .. " timed out")
  end

  DayNight.setting:sync("day")
  Weather.setting:sync("off")
  pcall(function() game.overworld:setMap("ROUTE_2", 10, 10, "up") end)
  settle("ROUTE_2")

  local map = game.overworld.map
  log("bound key =", tostring(GrassWear.boundKey()),
      "| map =", tostring(map and map.id))

  -- ---- 1. IS THERE A FIELD AT ALL, and how much of the map does it cover
  local W = math.min(map.widthCells or 0, GrassWear.RES)
  local H = math.min(map.heightCells or 0, GrassWear.RES)
  local covered, dry, sum, peak = 0, 0, 0, 0
  local total = W * H
  for cy = 0, H - 1 do
    for cx = 0, W - 1 do
      local v = GrassWear.canopyAt(cx, cy)
      if v > 0 then
        covered = covered + 1
        sum = sum + v
        if v > peak then peak = v end
        if v >= GroundFX.CANOPY_DRY then dry = dry + 1 end
      end
    end
  end
  log(string.format("map %dx%d = %d cells | covered %d (%.1f%%) | "
                    .. "past CANOPY_DRY %d (%.1f%%) | peak %.3f | "
                    .. "mean over covered %.3f",
                    W, H, total, covered, covered / math.max(total, 1) * 100,
                    dry, dry / math.max(total, 1) * 100, peak,
                    sum / math.max(covered, 1)))
  log(covered > 0 and "PASS: a canopy field was baked"
                   or "FAIL: nothing baked -- every guard in eachCanopyCell "
                      .. "returns nil quietly, so this is the only signal")
  -- A route is trees round the edges and a path up the middle. Saturating
  -- it would dry the whole map; touching nothing would be the bug above.
  log((covered > total * 0.05 and covered < total * 0.85)
      and "PASS: the cover is a wood, not the whole map and not a rounding "
          .. "error"
      or "FAIL: the covered share is not credible for a route")

  -- ---- 2. IS IT UNDER THE TREES? Correlate against the site list.
  local S = Structures.forMap(map)
  local sites = S.treeSites or {}
  local onSite, onSiteN = 0, 0
  for i = 1, #sites do
    local cx = math.floor((sites[i].mx or 0) / 16)
    local cy = math.floor((sites[i].mz or 0) / 16)
    onSite = onSite + GrassWear.canopyAt(cx, cy)
    onSiteN = onSiteN + 1
  end
  -- ...against cells picked from the map at large, most of which are not
  -- under anything
  local offSite, offSiteN = 0, 0
  for cy = 0, H - 1, 3 do
    for cx = 0, W - 1, 3 do
      offSite = offSite + GrassWear.canopyAt(cx, cy)
      offSiteN = offSiteN + 1
    end
  end
  local meanOn = onSite / math.max(onSiteN, 1)
  local meanOff = offSite / math.max(offSiteN, 1)
  log(string.format("mean cover ON a tree site %.3f (n=%d) vs ANYWHERE "
                    .. "%.3f (n=%d)", meanOn, onSiteN, meanOff, offSiteN))
  log(meanOn > meanOff * 1.5
      and "PASS: the cover sits on the cells that have trees"
      or "FAIL: cover is not correlated with the site list -- the bake and "
         .. "the stamp disagree about where the crowns are")

  -- ---- 3. DOES THE GROUND READ IT? Same call GroundFX makes.
  local viaFX, mismatch = 0, 0
  for cy = 0, H - 1, 2 do
    for cx = 0, W - 1, 2 do
      local a = GrassWear.canopyAt(cx, cy)
      local b = GroundFX.canopyOver(cx, cy)
      if b > 0 then viaFX = viaFX + 1 end
      if math.abs(a - b) > 1e-6 then mismatch = mismatch + 1 end
    end
  end
  log("cells GroundFX sees covered =", viaFX, "| disagreements =", mismatch)
  log(mismatch == 0 and viaFX > 0
      and "PASS: GroundFX reads the same field the bake wrote"
      or "FAIL: GroundFX and GrassWear disagree about the canopy")

  local function shot(name)
    love.graphics.captureScreenshot(function(d)
      local f = io.open(OUT .. "/" .. name .. ".png", "wb")
      if f then f:write(d:encode("png"):getString()); f:close() end
    end)
    wait(8)
  end

  -- ---- 4. AND THE PICTURES. Weather.BUILD is 20 s to peak, and the
  -- ground soaks/settles on its own clock after that (GroundFX.SOAK is 55
  -- seconds of downpour to saturated, SETTLE is 100 to full cover) -- so
  -- these waits are long on purpose. Shooting earlier photographs a
  -- feature that has not happened yet.
  Weather.setting:sync("rain")
  wait(3000)
  log(string.format("rain: wetness %.2f cover %.2f",
                    GroundFX.wetness(), GroundFX.cover()))
  shot("shelter_rain")

  Weather.setting:sync("snow")
  wait(4200)
  log(string.format("snow: wetness %.2f cover %.2f | winter=%s",
                    GroundFX.wetness(), GroundFX.cover(),
                    tostring(Weather.isWinter())))
  shot("shelter_snow")

  Weather.setting:sync("off")
  log("done")
  logf:close()
  wait(10)
  love.event.quit()
end
