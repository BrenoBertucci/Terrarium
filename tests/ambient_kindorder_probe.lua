-- Probe: is the ambient world-pass failure a property of the KIND, or of
-- the ITERATION?
--
-- The occlusion probe's one full run failed exactly its 2nd and 4th kinds
-- (firefly, sparrow) -- and its log shows the world-capture window catching
-- 3 overlay draws on every kind that passed and 2 on every kind that
-- failed, a perfect alternation by iteration index. Two readings of that:
-- the two kinds genuinely build invisible geometry, or the probe's capture
-- cadence photographs a bad frame on even iterations and the kinds are
-- innocent.
--
-- So: the same mechanics, with the kind list reordered and the two suspects
-- run TWICE each at opposite parities. Kind-based failure follows the kind
-- to both slots; iteration-based failure stays on the even slots whatever
-- kind sits in them.
--
-- Each capture also logs AmbientLife.worldCalls (scene renders that reached
-- the module) and worldTrace (per-render batch counts, newest last), so
-- "how many renders did this window actually see, and what did each build"
-- stops being an inference.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/ambient_kindorder_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/ambient_kindorder.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  -- The diagnosis this probe exists for: the two-yield shot() returned
  -- with the capture still PENDING on the unlucky phase of the 4-updates-
  -- per-present cycle, the caller then changed state (pinNone), and the
  -- pending capture photographed the next frame. Fixed here as in the
  -- occlusion probe: wait for the callback itself.
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

  local CELL_X, CELL_Y = 12, 12
  local ow = game.overworld
  DayNight.setting:sync("day")
  ow:setMap("PALLET_TOWN", CELL_X, CELL_Y, "up")
  wait(600)
  local p = ow.player
  log(("map %s  player %d,%d"):format(ow.map.id, p.cellX, p.cellY))

  local Voxel3D = lib.require("Voxel3D")
  local function shotAt(name, wx, wy, wz)
    local sx, sy = Voxel3D.project(wx, wy, wz)
    log(("      %-28s fixture at screen %s,%s  worldCalls %d")
        :format(name, tostring(sx and math.floor(sx)),
                tostring(sy and math.floor(sy)), AmbientLife.worldCalls))
    shot(name)
  end

  AmbientLife.HOLD = true
  -- the two suspects at BOTH parities; one known-good kind on an even slot
  local KINDS = { "firefly", "sparrow", "leaf", "butterfly",
                  "dragonfly", "firefly", "sparrow" }
  for ki, kind in ipairs(KINDS) do
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

    AmbientLife.pinOne(kind, FX, FY, FZ)
    AmbientLife.WORLD_PASS = false
    wait(40)

    local function resetDraw()
      AmbientLife.drawCalls, AmbientLife.drawSeen, AmbientLife.drawPainted = 0, 0, 0
    end
    local tag = ("%02d_%s"):format(ki, kind)

    resetDraw()
    wait(8)
    shotAt(("amb2_%s_overlay.png"):format(tag), FX, FY, FZ)
    local oc, os_, op =
      AmbientLife.drawCalls, AmbientLife.drawSeen, AmbientLife.drawPainted

    AmbientLife.WORLD_PASS = true
    resetDraw()
    AmbientLife.lastBatches = -1
    AmbientLife.worldTrace = ""
    local callsAtFlip = AmbientLife.worldCalls
    wait(8)
    shotAt(("amb2_%s_world.png"):format(tag), FX, FY, FZ)
    local wc, ws, wp =
      AmbientLife.drawCalls, AmbientLife.drawSeen, AmbientLife.drawPainted
    local callsAtShot = AmbientLife.worldCalls

    AmbientLife.pinNone()
    wait(8)
    shotAt(("amb2_%s_blank.png"):format(tag), FX, FY, FZ)
    AmbientLife.pinOne(kind, FX, FY, FZ)

    log(("      OVERLAY: drawBody calls %d seen %d painted %d")
        :format(oc, os_, op))
    log(("      WORLD:   drawBody calls %d seen %d painted %d  batches %d")
        :format(wc, ws, wp, AmbientLife.lastBatches))
    log(("      WORLD:   renders flip->shot %d  trace [%s]")
        :format(callsAtShot - callsAtFlip, AmbientLife.worldTrace))
    log(("%02d %-10s batches %d | emit %s push %s dropped %s")
        :format(ki, kind, AmbientLife.lastBatches,
                tostring(AmbientLife.lastEmit), tostring(AmbientLife.lastPush),
                tostring(AmbientLife.lastDropped)))
    if AmbientLife.drawError then
      log(("  THREW: %s"):format(AmbientLife.drawError))
      AmbientLife.drawError = nil
    end
  end
  AmbientLife.HOLD = false

  log("done")
  logf:close()
  love.event.quit()
end
