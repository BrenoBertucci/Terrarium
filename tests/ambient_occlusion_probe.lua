-- Probe: the ambient life, in the scene pass instead of over it.
--
-- The mechanism is the one the wind field already proved -- cards in the
-- scene pass, hardware depth test -- so what is actually new here, and
-- what this has to catch, is the TRANSLATION. Every critter was a handful
-- of axis-aligned screen rectangles measured in multiples of `s`, and each
-- one had to be rewritten as a card offset in the camera's own plane.
-- Screen y points down and the card's axis points up, so a single missed
-- minus sign is a sparrow drawn upside down, or a dragonfly's wings on its
-- tail -- and nothing else in the frame would look wrong.
--
-- That is a visual failure, not a numeric one, so this probe's real output
-- is the pair of screenshots. The numbers are here to catch the two
-- failures a picture would NOT settle:
--
--   BATCHES > 0    the geometry reached the pass at all. Zero with a
--                  non-empty critter list means it is being built and
--                  thrown away.
--
--   NO DOUBLING    with the scene pass on, the overlay must paint only
--                  the flock. Two copies of a butterfly -- one occluded,
--                  one not -- is worse than the bug this replaces.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/ambient_occlusion_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/ambient_occlusion.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  -- ------- THE SHOT WAITS FOR ITS OWN CALLBACK, NOT A FRAME COUNT
  --
  -- captureScreenshot runs its callback at the next PRESENT, and at
  -- POKEPORT_SPEED=4 a yield is an UPDATE -- four of them to a present.
  -- The old two-yield version therefore returned with the capture still
  -- pending whenever it was scheduled early in the update batch, the probe
  -- walked on and called pinNone, and the pending capture photographed the
  -- NEXT frame: a world capture with no creature in it. That is the whole
  -- of the "firefly and sparrow build geometry but put no pixel" reading
  -- this probe produced -- the two kinds sat on the unlucky phase slots,
  -- and tests/ambient_kindorder_probe.lua showed the failure following the
  -- SLOT and not the kind (butterfly on an unlucky slot: world identical
  -- to blank; sparrow on a lucky one: painted).
  --
  -- Waiting for the callback means the state the shot was scheduled under
  -- is still standing when the capture actually happens.
  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      done = true
    end)
    local guard = 0
    while not done and guard < 240 do coroutine.yield(); guard = guard + 1 end
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
  log("version:", exports.TERRARIUM.version)

  local AmbientLife = lib.require("AmbientLife")
  local Weather  = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Wind     = lib.require("Wind")
  local Quality  = lib.require("Quality")
  local Pipelines = require("src.render.Pipelines")

  Weather.setting:sync("off")
  Wind.setting:sync(2)
  Quality.setting:sync(1)
  AmbientLife.setting:sync("on")
  Pipelines.setLevel("terrarium_voxel", 4)
  -- The machine's saved options keep T-SHIFT at 3, and the fixture sits at
  -- screen y~140 -- deep inside the blur band, where a shape comparison
  -- between the two paths is a comparison of two smudges. Level 0 is the
  -- documented pass-through. The scene shader still shades the world-pass
  -- cards (that is the point of the pass), so the two captures are NOT
  -- expected to match byte-for-byte; what must match is position, size and
  -- orientation of the painted shape.
  Pipelines.setLevel("terrarium_tiltshift", 0)

  local CELL_X, CELL_Y = 12, 12
  local ow = game.overworld
  DayNight.setting:sync("day")
  ow:setMap("PALLET_TOWN", CELL_X, CELL_Y, "up")
  wait(600)
  local p = ow.player
  log(("map %s  player %d,%d"):format(ow.map.id, p.cellX, p.cellY))

  -- ------- AGAINST THE SKY, NOT AGAINST A WALL
  --
  -- The first placement put the fixture two cells north at head height,
  -- which projects squarely onto a white building wall -- and the first
  -- butterfly tint is cabbage white. A two-pixel white card on a white
  -- wall is invisible in both passes, and the two captures came back
  -- BYTE-IDENTICAL, which reads exactly like "nothing was drawn".
  --
  -- The same trap the wind probe already walked into and solved with a
  -- magenta fixture: a test that cannot see its own subject proves
  -- nothing. Here the answer is the background rather than the colour --
  -- high enough to sit against the sky, where a white butterfly, a brown
  -- sparrow and a teal dragonfly all contrast, and no shipping colour has
  -- to be overridden to make the test work.

  -- ------- PROJECT IN THE SAME FRAME AS THE SHOT, NOT BEFORE IT
  --
  -- The first attempt logged the fixture's screen position once, up here,
  -- and cropped every one of the ten captures at it. The crops came out on
  -- a roof. Voxel3D.project reads the camera the LAST rendered frame left
  -- behind, and hundreds of frames pass between this point and the shots --
  -- during which the player walks on its own after a setMap, taking the
  -- camera with it.
  --
  -- love.graphics.captureScreenshot schedules for the END of the current
  -- frame, so projecting immediately before it, with no yield in between,
  -- reads the camera that same frame is being drawn with. Each capture then
  -- carries its own coordinates and the drift stops mattering.
  local Voxel3D = lib.require("Voxel3D")
  -- The point is PASSED, not captured. It used to close over FX/FY/FZ,
  -- which then moved inside the per-kind loop -- so at the moment this
  -- closure was built those names were globals, the globals were nil, and
  -- project(nil, nil, nil) threw on the first capture. Same shape of
  -- mistake as a local declared below its own caller, wearing a different
  -- hat.
  local function shotAt(name, wx, wy, wz)
    local sx, sy = Voxel3D.project(wx, wy, wz)
    log(("      %-26s fixture at screen %s,%s")
        :format(name, tostring(sx and math.floor(sx)),
                tostring(sy and math.floor(sy))))
    shot(name)
  end

  AmbientLife.HOLD = true
  local KINDS = { "butterfly", "firefly", "leaf", "sparrow", "dragonfly" }
  for _, kind in ipairs(KINDS) do
    -- ------- THE PAIR IS SHOT BACK TO BACK
    --
    -- The player walks on its own after a setMap -- a known trap in this
    -- engine, and it takes the camera with it. With forty frames between
    -- the two captures of a pair they came out a hundred pixels apart on
    -- screen and could not be compared at all: over ten shots the fixture
    -- wandered from y=129 to y=728.
    --
    -- So the pair is settled ONCE and then flipped and shot with nothing
    -- between: about four frames, over which the drift is a pixel or two.
    -- The fixture is also re-placed relative to where the player is NOW,
    -- rather than to where it was when the probe started.
    local pp = ow.player
    local FX = pp.cellX * 16 + 8
    local FZ = (pp.cellY - 1) * 16 + 8
    local FY = 22
    do
      local WANT = 140
      local bestErr = 1e9
      for h = 12, 120, 2 do
        local hx, hy = Voxel3D.project(FX, h, FZ)
        if hx and hy and hy > 30 and hy < 640 then
          local err = math.abs(hy - WANT)
          if err < bestErr then FY, bestErr = h, err end
        end
      end
    end

    -- leaf at size 4: at size 1 the card is two screen pixels here, under
    -- any diff threshold on both paths -- unmeasurable, not broken
    AmbientLife.pinOne(kind, FX, FY, FZ, kind == "leaf" and 4 or nil)
    AmbientLife.WORLD_PASS = false
    wait(40)

    -- ------- WHICH PATH PAINTED WHICH CAPTURE
    --
    -- The two captures came out byte-identical, which has two readings:
    -- the geometry reproduces the overlay exactly (the wanted answer), or
    -- the overlay painted both and the geometry is invisible (the failure).
    -- The counters tell them apart: in the world half the overlay must
    -- paint ZERO of these kinds, because `mine` is false for anything not
    -- in IN_OVERLAY.
    -- ------- THREE COUNTERS, BECAUSE "NOTHING ON SCREEN" HAS THREE CAUSES
    --
    -- calls   drawBody was entered at all
    -- seen    it reached this critter and asked for a projection
    -- painted the projection came back non-nil and it drew
    --
    -- The previous run logged only `painted`, read 0 in the OVERLAY
    -- capture -- where WORLD_PASS is false and it must paint -- and left
    -- no way to tell whether the function never ran, ran and skipped the
    -- critter, or ran and got a nil projection. These three separate them.
    local function resetDraw()
      AmbientLife.drawCalls, AmbientLife.drawSeen, AmbientLife.drawPainted = 0, 0, 0
    end
    local function readDraw()
      return AmbientLife.drawCalls, AmbientLife.drawSeen, AmbientLife.drawPainted
    end

    -- ------- THE WINDOW HAS TO BE WIDER THAN THE SHOT
    --
    -- shotAt yields exactly twice, and drawBody turns out to run about
    -- every second to fourth frame -- so a two-frame window caught `calls
    -- 0` and read as "the overlay never paints", when the stale lastXY
    -- right beside it proved it had painted moments earlier. Eight frames
    -- is enough to catch several calls.
    --
    -- The drift this costs does not matter: shotAt logs each capture's own
    -- screen position and the crops follow it per image. What could not be
    -- allowed was forty frames BETWEEN the pair with a single crop for
    -- both, which is the mistake this loop already fixed.
    resetDraw()
    wait(8)
    shotAt(("amb_%s_overlay.png"):format(kind), FX, FY, FZ)
    local oc, os_, op = readDraw()

    AmbientLife.WORLD_PASS = true
    resetDraw()
    AmbientLife.lastBatches = -1
    wait(8)
    shotAt(("amb_%s_world.png"):format(kind), FX, FY, FZ)
    local wc, ws, wp = readDraw()

    -- ------- AND A FRAME WITH NO CREATURE IN IT
    --
    -- The control. Without it "the two captures are identical" is
    -- ambiguous between "both drew the same thing" (the answer wanted) and
    -- "neither drew anything" (the failure), and this comparison has
    -- already been read the wrong way round once.
    AmbientLife.pinNone()
    wait(8)
    shotAt(("amb_%s_blank.png"):format(kind), FX, FY, FZ)
    AmbientLife.pinOne(kind, FX, FY, FZ)

    log(("      OVERLAY capture: drawBody calls %d  seen %d  painted %d"
         .. "  lastXY %s"):format(oc, os_, op, tostring(AmbientLife.drawLastXY)))
    log(("      WORLD   capture: drawBody calls %d  seen %d  painted %d"
         .. "  (seen must be 0)  scene batches %d")
        :format(wc, ws, wp, AmbientLife.lastBatches))

    log(("%-10s batches %d  | emit %s  push %s  dropped %s  kindSeen %s"
         .. "  drawPainted %d")
        :format(kind, AmbientLife.lastBatches,
                tostring(AmbientLife.lastEmit), tostring(AmbientLife.lastPush),
                tostring(AmbientLife.lastDropped),
                tostring(AmbientLife.lastKind), AmbientLife.drawPainted))
    if AmbientLife.drawError then
      log(("  THREW: %s"):format(AmbientLife.drawError))
      AmbientLife.drawError = nil
    end
  end
  AmbientLife.HOLD = false

  log(("fixture at world %.0f,%.0f,%.0f"):format(FX, FY, FZ))
  log("done")
  logf:close()
  love.event.quit()
end
