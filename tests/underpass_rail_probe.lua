-- Probe: how tall is the rail the UNDERGROUND tileset draws, and at what
-- height does the corridor's own banding clear it?
--
-- The yellow band and the LED run are generated -- that much is readable in
-- lib/Underpass.lua -- and neither reaches the frame. The standing guess was
-- that the tileset's own rim geometry stands in front of them. A guess is
-- not a height, so this measures two things:
--
--   THE RAIL   the authored class and height of every cell in the ring
--              around the walkable box. data/voxel_heights.lua pins the
--              UNDERGROUND rim tiles to `wall`, and `wall` is 16 world px --
--              but the number that matters is what the map actually places,
--              not what the blockset could.
--
--   THE CLEAR  a sweep: one shot per candidate height, counted by colour
--              signature in tests/underpass_rail_report.py. The band's
--              yellow and the LED's blue are the only saturated hues in an
--              amber-and-red corridor, so each run can be counted in its own
--              shot without differencing against a reference.
--
-- WHY NOT A DIFFERENCE. The first version of this probe took one reference
-- shot and diffed every sweep frame against it. The numbers were enormous
-- and meant nothing: the frame does not hold still between shots -- the
-- camera and the walker both move -- so a whole-frame difference measures
-- the drift, not the band. Two all-off shots 240 frames apart already
-- differed in 1364 pixels, and shots further apart differed in 126000.
--
-- So the frame is RE-ANCHORED before every shot: setMap teleports the walker
-- back to the same cell and the settle runs from there, and the control pair
-- at the top of the sweep is what says whether that worked. If CONTROL comes
-- back with a big number, nothing below it is worth reading.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/underpass_rail_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/underpass_rail_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local function shot(name)
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
    wait(4)
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
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end

  local Underpass = lib.require("Underpass")
  local TileShape = lib.require("TileShape")
  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local Pipelines = require("src.render.Pipelines")

  Weather.setting:sync("off")
  DayNight.setting:sync("night")
  pcall(Pipelines.setLevel, "terrarium_voxel", 4)

  local MAP, MX, MY = "UNDERGROUND_PATH_NORTH_SOUTH", 3, 20

  -- Put the world back where it was for the last shot: same cell, same
  -- facing, same settle. Everything the sweep changes is a module constant,
  -- so this is the whole of the state that has to be re-pinned.
  --
  -- Fixed settle, no poll: Voxel3D.lampLights is written by VoxelScene.render
  -- only on the OUTDOOR branch, so waiting on it underground waits forever on
  -- a map whose 3D pass is running perfectly well.
  -- The walker does NOT stay where it is put. Logged on the run that found
  -- this: the anchor cell went 20, 22, 25, 24, 29, 29, 23 and only then
  -- settled on 20 for the rest of the session -- something drives it for the
  -- first few hundred frames after entry. A settle of a fixed length lands
  -- wherever that happens to have got to, which is why the control pair came
  -- back 232000 pixels apart.
  --
  -- So the settle is a CONDITION, not a count: hold until the walker has sat
  -- on the anchor cell for HOLD frames running, and start over if it steps
  -- off. The cap is there so a probe on a map that never settles fails
  -- loudly rather than hanging.
  local HOLD = 45
  local function anchor()
    local ok = pcall(function() game.overworld:setMap(MAP, MX, MY, "down") end)
    if not ok then return false end
    Underpass.invalidate()
    local still = 0
    for _ = 1, 1200 do
      coroutine.yield()
      local p = game.overworld and game.overworld.player
      if p and p.cellX == MX and p.cellY == MY then
        still = still + 1
        if still >= HOLD then return true end
      else
        still = 0
      end
    end
    return false
  end

  if not anchor() then
    log("FAIL: could not enter " .. MAP)
    logf:close(); love.event.quit(); return
  end

  local map = game.overworld and game.overworld.map
  log("tileset:", tostring(map and map.tileset and map.tileset.image))
  log("matches:", tostring(Underpass.matches(map)))

  -- ---- the rail, measured off the map
  local box = Underpass._walkBox(map)
  if not box then
    log("FAIL: no walk box"); logf:close(); love.event.quit(); return
  end
  log(("walkbox: x %d..%d  y %d..%d  (cells)")
      :format(box.x0, box.x1, box.y0, box.y1))

  local shapes = TileShape.forMap(map)
  -- The ring: one cell outside the walkable box on all four sides. This is
  -- where the tileset's rim lives, and its height is the number the band has
  -- to clear.
  local tally, order = {}, {}
  local function note(cx, cy)
    if not map:inBounds(cx, cy) then return end
    local s = shapes[map:cellTile(cx, cy)]
    local key = ("%s h=%s art=%s"):format(
      s and tostring(s.class) or "none",
      s and tostring(s.h) or "0",
      s and tostring(s.art) or "-")
    if not tally[key] then tally[key] = 0; order[#order + 1] = key end
    tally[key] = tally[key] + 1
  end
  for cx = box.x0 - 1, box.x1 + 1 do
    note(cx, box.y0 - 1); note(cx, box.y1 + 1)
  end
  for cy = box.y0, box.y1 do
    note(box.x0 - 1, cy); note(box.x1 + 1, cy)
  end
  log("--- ring cells (one out from the walkable box) ---")
  local tallest = 0
  for _, key in ipairs(order) do
    log(("  %-34s x%d"):format(key, tally[key]))
    local h = tonumber(key:match("h=(%-?%d+%.?%d*)"))
    if h and h > tallest then tallest = h end
  end
  log(("RAIL: tallest ring class = %g world px"):format(tallest))
  log(("shell: WALL_TOP=%g HAUNCH_Y=%g..%g")
      :format(Underpass.WALL_TOP, Underpass.HAUNCH_Y,
              Underpass.HAUNCH_Y + Underpass.HAUNCH_T))

  -- ---- the sweep
  --
  -- Spanning the rail (16) and the wall crest (WALL_TOP, 26), because those
  -- are the two things a run can be behind, and the point of a sweep is to
  -- have shots on both sides of each of them.
  local SWEEP = { 3, 11, 15, 17, 19, 21, 25, 27 }

  -- Where the walker actually is when the shutter opens. The control pair
  -- came back 232000 pixels apart on the first anchored run and the picture
  -- said "the camera moved"; this is the number that says WHY, and without
  -- it the next thing to do is another guess.
  local function where()
    local p = game.overworld and game.overworld.player
    if not p then return "player=nil" end
    return ("cell=(%s,%s) px=(%s,%s) facing=%s")
      :format(tostring(p.cellX), tostring(p.cellY),
              tostring(p.x or p.px), tostring(p.y or p.py),
              tostring(p.facing or p.dir))
  end

  local function take(name)
    local held = anchor()
    local b = Underpass._built
    log(("%-22s held=%s shell=%s glow=%s led=%s  %s")
        :format(name, tostring(held), tostring(b.shell ~= nil),
                tostring(b.glow ~= nil), tostring(b.led ~= nil), where()))
    shot(name .. ".png")
  end

  -- CONTROL. Two shots, same configuration, same anchor. Read this pair
  -- first: it is the noise floor every number below is measured against.
  Underpass.SHOW_BAND, Underpass.SHOW_STRIP = false, false
  take("rail_control_a")
  take("rail_control_b")

  -- band first, LED off throughout, so a yellow count is the band's alone
  take("rail_band_off")
  Underpass.SHOW_BAND = true
  for _, y in ipairs(SWEEP) do
    Underpass.BAND_Y = y
    take(("rail_band_y%02d"):format(y))
  end

  -- then the LED, band off throughout
  Underpass.SHOW_BAND, Underpass.SHOW_STRIP = false, false
  take("rail_strip_off")
  Underpass.SHOW_STRIP = true
  for _, y in ipairs(SWEEP) do
    Underpass.STRIP_Y = y
    take(("rail_strip_y%02d"):format(y))
  end

  -- ---- does the second flatten reach the LED draw at all?
  --
  -- The sweep above answers "is the run on screen". This answers the other
  -- half, and it is a separate question because the first anchored run had
  -- the LED contributing thousands of pixels at every height while the blue
  -- count stayed at zero -- a run that is visible and is not its own colour.
  --
  -- The reds are the CONTROL. Blue is the colour being asked for, so a blue
  -- that does not appear is ambiguous: the flatten might not be reaching this
  -- draw, or it might be reaching it and being graded back out downstream. A
  -- pure red at full flatten cannot be confused with the amber the corridor
  -- already is only by hue, but it MUST change the run's pixels if the send
  -- is landing at all. If red moves and blue does not, the send lands and the
  -- problem is downstream of it.
  Underpass.SHOW_BAND, Underpass.SHOW_STRIP = false, true
  Underpass.STRIP_Y = 17
  for _, t in ipairs({
    { tag = "asis",  col = { 0.42, 0.72, 1.00 }, amt = 0.94 },
    { tag = "blue1", col = { 0.00, 0.20, 1.00 }, amt = 1.00 },
    { tag = "red1",  col = { 1.00, 0.00, 0.00 }, amt = 1.00 },
    { tag = "green1", col = { 0.00, 1.00, 0.00 }, amt = 1.00 },
  }) do
    Underpass.LED_COLOR, Underpass.LED_FLATTEN = t.col, t.amt
    take("rail_ledcol_" .. t.tag)
  end
  Underpass.LED_COLOR, Underpass.LED_FLATTEN = { 0.42, 0.72, 1.00 }, 0.94

  -- ---- how far proud does a run have to stand to clear its own wall?
  --
  -- The height sweep said the runs only appear once they pass WALL_TOP, and
  -- the colour test said a run at 17 is not rasterised at all. Both point at
  -- the same thing: the wall's crest overhangs its own face at this camera
  -- pitch. That overhang is a DISTANCE, and this measures it -- one shot per
  -- protrusion, at a height well clear of the tileset's 16px rail and well
  -- under the crest, so the only thing that can bring the run into view is
  -- coming further out.
  --
  -- If nothing appears at any protrusion, the face is not visible at all from
  -- here and the runs have to move to a surface that is -- the crest itself.
  -- ---- and the shipped configuration, which is both runs on the crest
  --
  -- Four shots, because the two runs have to be separable: neither on, each
  -- alone, both. The band is counted in yellow and the LED in blue, and each
  -- has to clear its own baseline on its own shot -- "the pair together looks
  -- right" is exactly the reading that let the last two rounds pass.
  Underpass.BAND_Y, Underpass.STRIP_Y = nil, nil
  for _, place in ipairs({ "crest", "soffit" }) do
    Underpass.RUN_PLACE = place
    for _, t in ipairs({
      { tag = "none",  band = false, strip = false },
      { tag = "band",  band = true,  strip = false },
      { tag = "led",   band = false, strip = true },
      { tag = "both",  band = true,  strip = true },
    }) do
      Underpass.SHOW_BAND, Underpass.SHOW_STRIP = t.band, t.strip
      take(("rail_%s_%s"):format(place, t.tag))
    end
  end

  logf:close()
  love.event.quit()
end
