-- T11: vegetation emitter, measured.
--
--   SITES     the TileShape scan finds trees, grass and flowers on
--             ROUTE_1 (it has all three)
--   SHEDS     under GALE, all classes with in-range sites emit within
--             a ten-second window
--   ORIGIN    the heart of the task: young falling leaves sit within a
--             crown's reach of a REAL tree site
--   CALM      wind row OFF: seeds and petals stop and the gate says why,
--             while leaves keep falling at the calm trickle
--   CLEAN     no errors, canaries alive
--
-- Where the leaves go after they let go -- the ground, the kick -- is
-- tests/leaf_fall_probe.lua's to measure.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/veg_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/veg.log", "w"))
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

  local Weather  = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Wind     = lib.require("Wind")
  local WindFX   = lib.require("WindFX")
  local VegFX    = lib.require("VegFX")
  local LeafFallFX = lib.require("LeafFallFX")
  local AmbientLife = lib.require("AmbientLife")
  local Quality  = lib.require("Quality")
  local Voxel3D  = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")

  Weather.setting:sync("off")
  Wind.setting:sync(4)                -- GALE
  AmbientLife.setting:sync("off")
  Quality.particleSetting:sync(1)
  Pipelines.setLevel("terrarium_voxel", 4)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  DayNight.setting:sync("day")
  local ow = game.overworld
  ow:setMap("ROUTE_1", 10, 20, "up")
  wait(400)
  local p = ow.player
  local px, pz = (p.px or 0) + 8, (p.py or 0) + 8
  log(("map %s  player %d,%d  amount %.2f")
      :format(ow.map.id, p.cellX, p.cellY, Wind.amount()))

  -- ------- SITES (the scan runs on the first live tick)
  wait(20)
  local S = VegFX.sites
  local function inRange(list)
    local c = 0
    for i = 1, #list do
      local s = list[i]
      if math.abs(s.x - px) <= VegFX.RANGE
         and math.abs(s.z - pz) <= VegFX.RANGE then c = c + 1 end
    end
    return c
  end
  local irT, irG, irF = inRange(S.trees), inRange(S.grass), inRange(S.flowers)
  log(("sites: trees %d (in range %d)  grass %d (%d)  flowers %d (%d)")
      :format(#S.trees, irT, #S.grass, irG, #S.flowers, irF))
  log(("sites verdict: %s")
      :format((#S.trees > 0 and #S.grass > 0 and irT > 0 and irG > 0)
              and "PASS" or "FAIL"))

  -- ------- SHEDS + ORIGIN over a ten-second window
  local l0, s0, f0 = VegFX.emittedLeaf, VegFX.emittedSeed, VegFX.emittedPetal
  local checked, violations, worst = 0, 0, 0
  for i = 1, 600 do
    coroutine.yield()
    if i % 5 == 0 then
      for j = 1, LeafFallFX.count() do
        local m = LeafFallFX.get(j)
        -- judged where it LET GO, not where a gale has carried it since:
        -- a leaf is born anywhere under its crown, within SHED_R of it
        if m and m.kind == "fall" and m.bornX and m.t < 0.15 then
          local best = 1e9
          for k = 1, #S.trees do
            local t = S.trees[k]
            local dx, dz = m.bornX - t.x, m.bornZ - t.z
            local d = math.sqrt(dx * dx + dz * dz)
            if d < best then best = d end
          end
          checked = checked + 1
          if best > worst then worst = best end
          if best > LeafFallFX.SHED_R + 0.01 then violations = violations + 1 end
        end
      end
    end
  end
  local dl = VegFX.emittedLeaf - l0
  local ds = VegFX.emittedSeed - s0
  local df = VegFX.emittedPetal - f0
  log(("sheds over 10s at GALE: leaves %d  seeds %d  petals %d")
      :format(dl, ds, df))
  local petalOk = (irF == 0) or df > 0
  log(("sheds verdict: %s%s")
      :format((dl > 3 and ds > 3 and petalOk) and "PASS" or "FAIL",
              irF == 0 and "  (no flowers in range: petal not judged)" or ""))
  log(("origin: %d young falling leaves checked, worst distance from a crown"
       .. " at birth %.1f px (SHED_R %d), violations %d  %s")
      :format(checked, worst, LeafFallFX.SHED_R, violations,
              (checked >= 5 and violations == 0) and "PASS" or "FAIL"))

  -- ------- the picture: shot against the nearest in-range tree
  local near, nd = nil, 1e9
  for k = 1, #S.trees do
    local t = S.trees[k]
    local d = math.max(math.abs(t.x - px), math.abs(t.z - pz))
    if d < nd then near, nd = t, d end
  end
  if near then
    local sx, sy = Voxel3D.project(near.x, near.h, near.z)
    log(("shot: nearest crown world %d,%d h %.0f -> screen %s,%s")
        :format(near.x, near.z, near.h,
                tostring(sx and math.floor(sx)), tostring(sy and math.floor(sy))))
  end
  -- every falling leaf's screen position, projected in the same resume the
  -- capture is scheduled in, so the offline crop can ring them -- a green
  -- leaf against a green crown needs the ring to be seen at all
  for j = 1, LeafFallFX.count() do
    local m = LeafFallFX.get(j)
    if m and not m.dying then
      local mx, my = Voxel3D.project(m.x, m.y, m.z)
      if mx and my then
        log(("MOTE %s %d %d"):format(m.kind, math.floor(mx), math.floor(my)))
      end
    end
  end
  shot("veg.png")

  -- ------- CALM: the wind's debris stops, the leaves do not
  do
    Wind.setting:sync(0)
    wait(420)                         -- the smoothed amount has to sink first
    local l1, s1, f1 = VegFX.emittedLeaf, VegFX.emittedSeed, VegFX.emittedPetal
    wait(600)
    local still = (VegFX.emittedSeed - s1) + (VegFX.emittedPetal - f1)
    local leaves = VegFX.emittedLeaf - l1
    log(("calm: amount %.2f  %d seeds+petals with the row OFF  gate [%s]"
         .. "  leaves still falling %d  %s")
        :format(Wind.amount(), still, tostring(VegFX.windGate), leaves,
                (still == 0 and VegFX.windGate == "wind below FLOOR"
                 and leaves > 0) and "PASS" or "FAIL"))
    Wind.setting:sync(4)
  end

  -- ------- CLEAN
  log(("errors: veg=%s (%d)  leaves update=%s (%d) draw=%s (%d)")
      :format(tostring(VegFX.lastError), VegFX.errorCount,
              tostring(LeafFallFX.lastError), LeafFallFX.errorCount,
              tostring(LeafFallFX.drawError), LeafFallFX.drawErrors))
  log(("canaries: VegFX.ticks %d live %d  WindFX gate [%s] batches %s  "
       .. "Weather.ticks %s ok %s")
      :format(VegFX.ticks, VegFX.ticksLive, tostring(WindFX.lastGate),
              tostring(WindFX.lastBatches),
              tostring(Weather.ticks), tostring(Weather.ticksOk)))

  log("done")
  logf:close()
  love.event.quit()
end
