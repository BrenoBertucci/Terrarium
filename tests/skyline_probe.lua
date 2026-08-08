-- Probe: the far skyline -- lib/WorldAtlas.lua's placing, before any
-- geometry is hung on it.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/skyline_probe.lua gen1recomp
--
-- The question this answers is not "does it look good", it is "is there
-- anything out there at all, and how far out does it go". Three numbers
-- decide whether the skyline is worth building:
--
--   COUNT     how many maps the walk reaches that the scene is not already
--             drawing. Under about five and there is no horizon to fill.
--   REACH     how far the farthest of them sits, in VIEW-HEIGHTS -- the
--             unit lib/Aerial.lua's range is written in. This is the
--             number that says whether the haze will have to be
--             recalibrated once the silhouettes are standing, and by how
--             much.
--   COST      how long the walk takes, because it re-runs on every map
--             crossing and a seam is the one moment in this renderer that
--             cannot afford anything.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/skyline_probe.log", "w"))
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
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit() return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end

  local WorldAtlas = lib.require("WorldAtlas")
  local AutoFarm = lib.require("AutoFarm")
  local Pipelines = require("src.render.Pipelines")
  AutoFarm.setting:setIndex(1, game)
  Pipelines.setLevel("terrarium_voxel", 5)
  wait(60)

  -- the view the reach is measured against, in world pixels
  local vw, vh = game.renderer:worldViewSize()
  log(("view: %dx%d world px"):format(vw, vh))
  log(("hops: %d"):format(WorldAtlas.HOPS))

  local SPOTS = {
    { "PALLET_TOWN", 12, 14 },   -- the corner of the region
    { "ROUTE_1", 8, 12 },        -- a route between two towns
    { "CELADON_CITY", 20, 20 },  -- the middle of the map
    { "LAVENDER_TOWN", 10, 10 },
    { "CINNABAR_ISLAND", 12, 10 },  -- an island: few connections
  }

  for _, s in ipairs(SPOTS) do
    game.overworld:setMap(s[1], s[2], s[3], "up")
    wait(200)
    WorldAtlas.invalidate()

    local t0 = love.timer.getTime()
    local all = WorldAtlas.around(s[1])
    local t1 = love.timer.getTime()
    local beyond = WorldAtlas.beyond(game.overworld)

    local def = game.data.maps[s[1]]
    local mw = def and def.width * 32 or 0
    local mh = def and def.height * 32 or 0
    -- reach: the farthest corner of any placed map from the middle of the
    -- one being stood on
    local cx, cy = mw / 2, mh / 2
    local reach, far = 0, nil
    local x0, y0, x1, y1 = 0, 0, mw, mh
    for _, e in ipairs(beyond) do
      local ew, eh = e.def.width * 32, e.def.height * 32
      if e.ox < x0 then x0 = e.ox end
      if e.oy < y0 then y0 = e.oy end
      if e.ox + ew > x1 then x1 = e.ox + ew end
      if e.oy + eh > y1 then y1 = e.oy + eh end
      for _, c in ipairs({ { e.ox, e.oy }, { e.ox + ew, e.oy },
                           { e.ox, e.oy + eh }, { e.ox + ew, e.oy + eh } }) do
        local dx, dy = c[1] - cx, c[2] - cy
        local d = math.sqrt(dx * dx + dy * dy)
        if d > reach then reach, far = d, e.id end
      end
    end

    log("")
    log(("== %s (%dx%d blocks) =="):format(s[1], def and def.width or 0,
                                           def and def.height or 0))
    log(("  placed=%d  beyond the drawn set=%d  walk=%.2f ms")
        :format(#all, #beyond, (t1 - t0) * 1000))
    log(("  region spans %d x %d world px = %.1f x %.1f view-heights")
        :format(x1 - x0, y1 - y0, (x1 - x0) / vh, (y1 - y0) / vh))
    log(("  farthest: %s at %.1f view-heights")
        :format(tostring(far), reach / vh))
    -- the nearest handful, which is what the eye will actually read
    local sorted = {}
    for _, e in ipairs(beyond) do
      local dx = math.max(x0 - e.ox, 0, e.ox - mw)
      local dy = math.max(y0 - e.oy, 0, e.oy - mh)
      sorted[#sorted + 1] = { e.id, math.sqrt(dx * dx + dy * dy) / vh, e.ox, e.oy }
    end
    table.sort(sorted, function(a, b) return a[2] < b[2] end)
    for i = 1, math.min(6, #sorted) do
      local r = sorted[i]
      log(("    %-20s at (%+6d,%+6d)  %.2f vh out"):format(r[1], r[3], r[4], r[2]))
    end
  end

  -- ------- and what it looks like
  --
  -- Four shots from one spot, so the two features can be told apart: the
  -- bare world, the horizon alone, the haze alone, and both. The haze is
  -- calibrated for a world half a view-height deep; with silhouettes
  -- standing out to thirty, the pair shot is the one that says whether
  -- that calibration still holds or has to be re-swept.
  local Skyline = lib.require("Skyline")
  local Aerial = lib.require("Aerial")
  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local MiniMap = lib.require("MiniMap")
  Weather.setting:setIndex(2, game)
  MiniMap.setting:setIndex(3, game)

  local CLOCK = 300
  local function hold(f)
    for _ = 1, f do DayNight.clock = CLOCK; coroutine.yield() end
    DayNight.clock = CLOCK
  end

  game.overworld:setMap("ROUTE_1", 8, 12, "up")
  hold(300)

  local function shot(name)
    local pending = true
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name .. ".png", "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      pending = false
    end)
    local g = 0
    while pending and g < 240 do hold(1); g = g + 1 end
  end

  log("")
  log("=== shots ===")
  local COMBOS = {
    { "sky_a_bare", 1, 1 }, { "sky_b_horizon", 4, 1 },
    { "sky_c_haze", 1, 3 }, { "sky_d_both", 4, 3 },
  }
  for _, c in ipairs(COMBOS) do
    Skyline.setting:setIndex(c[2], game)
    Aerial.setting:setIndex(c[3], game)
    -- one impostor is built per frame on purpose, so give the horizon
    -- enough frames to fill in before judging it
    hold(120)
    local n = 0
    for _ in pairs(Skyline._meshes) do n = n + 1 end
    log(("  %-14s HORIZON=%s  V-HAZE=%s  impostors cached=%d")
        :format(c[1], tostring(Skyline.setting:get()),
                tostring(Aerial.setting:get()), n))
    shot(c[1])
  end

  log("")
  log("done -- " .. OUT)
  logf:close()
  love.event.quit()
end
