-- Chimney smoke (lib/HearthFX.lua), measured rather than admired.
--
-- What is held:
--   CHIMNEYS   the map's structure cache lists the mouths the house
--              templates now stand (data/voxel_heights.lua), each above
--              its roof (y > 0) and inside the map
--   GATE       the module runs live on an outdoor map with the voxel pass
--              up, and reads "HEARTH off" the moment the row is turned off
--   HEARTH     at a pinned dusk with the weather off, hearth() is high
--              enough that at least one house lights on its own hash
--   EMIT       forced, every chimney in reach puffs at ~1/PUFF_EVERY per
--              second (PFX ON), within 40%
--   CLIMB      a puff's y only ever rises, and the plume tops out under
--              40 world px over the mouth
--   DRIFT      with the wind on, the field's mean velocity leans with
--              Wind.DIR; with it off, the column stands (|vx|,|vz| small)
--   DRAW       the scene pass issued batches for the field, with zero
--              draw errors
--   PIXELS     an ON capture differs from an OFF capture above at least
--              one lit chimney, and the OFF capture is clean of smoke
--
-- Screenshots (the callback is awaited, never a fixed yield count):
--   hearth_on.png, hearth_off.png, hearth_on2.png -- the same dusk, WIND
--   OFF so nothing else in the frame moves between the pair
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/hearth_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/hearth.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  -- awaited capture; returns the ImageData too, for the pixel pass
  local function shot(name)
    local done, keep = false, nil
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      keep = data
      done = true
    end)
    local guard = 0
    while not done and guard < 240 do coroutine.yield(); guard = guard + 1 end
    return done, keep
  end

  local fails = {}
  local function check(rule, ok, msg)
    if ok then log("  PASS " .. rule .. ": " .. msg)
    else fails[#fails + 1] = rule; log("  FAIL " .. rule .. ": " .. msg) end
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

  local HearthFX   = lib.require("HearthFX")
  local Structures = lib.require("Structures")
  local Weather    = lib.require("Weather")
  local DayNight   = lib.require("DayNight")
  local Wind       = lib.require("Wind")
  local AmbientLife = lib.require("AmbientLife")
  local Voxel3D    = lib.require("Voxel3D")
  local Quality    = lib.require("Quality")
  local Pipelines  = require("src.render.Pipelines")

  Weather.setting:sync("off")
  AmbientLife.setting:sync("off")
  Wind.setting:sync(0)                 -- OFF: nothing else moves in the frame
  Pipelines.setLevel("terrarium_voxel", 4)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  DayNight.setting:sync("dusk")
  HearthFX.setting:sync("on")

  local ow = game.overworld
  -- in front of Red's house, facing it: the stack is in the top of the
  -- frame at a distance a player actually looks at a house from
  ow:setMap("PALLET_TOWN", 6, 8, "up")
  wait(300)

  -- ------- CHIMNEYS: the structure cache, read without building
  local S = nil
  for _ = 1, 900 do
    S = Structures.peek(ow.map)
    if S and S.chimneys then break end
    wait(1)
  end
  local list = S and S.chimneys or {}
  log(("map %s  chimneys %d  gate %s  shader %s"):format(
      ow.map.id, #list, HearthFX.lastGate,
      tostring(Voxel3D.shader and Voxel3D.shader() or "?")))
  if Voxel3D.shaderError then log("shaderError:", tostring(Voxel3D.shaderError)) end
  local mw, mh = ow.map.def.width * 32, ow.map.def.height * 32
  local inside = 0
  for i, c in ipairs(list) do
    log(("  chimney %d  world %.1f,%.1f,%.1f  tile %d,%d"):format(
        i, c.x, c.y, c.z, c.tx, c.ty))
    if c.y > 0 and c.x >= 0 and c.x <= mw and c.z >= 0 and c.z <= mh then
      inside = inside + 1
    end
  end
  check("CHIMNEYS", #list > 0 and inside == #list,
        ("%d mouths, %d inside the map and above ground"):format(#list, inside))

  -- ------- GATE and HEARTH, unforced
  wait(60)
  log(("gate %s  chimneys %d  hearth %.2f  lit %d  emitted %d  count %d  "
       .. "errors %d/%d"):format(HearthFX.lastGate, HearthFX.lastChimneys,
       HearthFX.lastHearth, HearthFX.lastLit, HearthFX.emitted,
       HearthFX.count(), HearthFX.errorCount, HearthFX.drawErrors))
  if HearthFX.lastError then log("lastError:", HearthFX.lastError) end
  if HearthFX.drawError then log("drawError:", HearthFX.drawError) end
  check("GATE", HearthFX.lastGate == "live", "gate " .. HearthFX.lastGate)
  check("HEARTH", HearthFX.lastHearth >= 0.6 and HearthFX.lastLit >= 1,
        ("dusk hearth %.2f lights %d of %d on their own hash"):format(
            HearthFX.lastHearth, HearthFX.lastLit, #list))

  -- ------- EMIT, forced: every chimney in reach, at the PFX ON rate
  HearthFX.force = true
  Quality.particleSetting:sync(1)
  wait(120)                            -- warm up: the first puffs are out
  local p = ow.player
  local px, pz = (p.px or 0) + 8, (p.py or 0) + 8
  local inReach = 0
  for _, c in ipairs(list) do
    if math.abs(c.x - px) <= HearthFX.REACH * 16
       and math.abs(c.z - pz) <= HearthFX.REACH * 16 then inReach = inReach + 1 end
  end
  -- against the module's OWN clock (the hook's dt summed over live ticks),
  -- not the wall: the engine's step is not wall time on a machine that
  -- cannot hold 60, and every timer in the chain runs on the step
  local e0, c0, t0 = HearthFX.emitted, HearthFX.clock, love.timer.getTime()
  wait(600)
  local secs = HearthFX.clock - c0
  local wall = love.timer.getTime() - t0
  local rate = (HearthFX.emitted - e0) / math.max(1e-6, secs)
  local want = inReach / HearthFX.PUFF_EVERY
  log(("emit: %d puffs in %.1fs of module clock (%.1fs wall) off %d stacks "
       .. "in reach -> %.2f/s, want %.2f/s")
      :format(HearthFX.emitted - e0, secs, wall, inReach, rate, want))
  check("EMIT", inReach > 0 and rate > want * 0.6 and rate < want * 1.4,
        ("%.2f/s vs %.2f/s"):format(rate, want))

  -- ------- CLIMB: follow the youngest puff; the plume's ceiling
  local youngest, yi = nil, 0
  for i = 1, HearthFX.count() do
    local m = HearthFX.get(i)
    if not youngest or m.t < youngest.t then youngest, yi = m, i end
  end
  local climbOK, lastY, drops = youngest ~= nil, youngest and youngest.y or 0, 0
  local top = 0
  if youngest then
    local y0 = youngest.y
    for _ = 1, 45 do
      wait(1)
      -- the pool swaps on death: make sure we still hold the same puff
      if HearthFX.get(yi) ~= youngest then break end
      if youngest.y < lastY - 0.01 then drops = drops + 1 end
      lastY = youngest.y
    end
    log(("climb: y %.2f -> %.2f over 45 frames, %d drops"):format(y0, lastY, drops))
    climbOK = lastY > y0 and drops == 0
  end
  local mouthY = list[1] and list[1].y or 0
  for i = 1, HearthFX.count() do
    local m = HearthFX.get(i)
    local over = m.y - mouthY
    if over > top then top = over end
  end
  check("CLIMB", climbOK and top < 40,
        ("rises without a drop, plume tops %.1f px over the mouth"):format(top))

  -- ------- DRIFT: WIND OFF holds the column; WIND on leans it
  local function meanV()
    local sx, sz, k = 0, 0, 0
    for i = 1, HearthFX.count() do
      local m = HearthFX.get(i)
      if m.vx then sx, sz, k = sx + m.vx, sz + m.vz, k + 1 end
    end
    if k == 0 then return 0, 0, 0 end
    return sx / k, sz / k, k
  end
  local cx, cz, ck = meanV()
  log(("drift OFF: mean v %.2f,%.2f over %d"):format(cx, cz, ck))
  local calmOK = ck > 0 and math.abs(cx) < 1.5 and math.abs(cz) < 1.5
  Wind.setting:sync(1)                 -- AUTO
  wait(240)
  local wx, wz, wk = meanV()
  local amount = Wind.amount()
  local dot = wx * (Wind.DIR[1] or 1) + wz * (Wind.DIR[2] or 0)
  log(("drift AUTO: amount %.2f dir %.2f,%.2f  mean v %.2f,%.2f over %d  dot %.2f")
      :format(amount, Wind.DIR[1] or 0, Wind.DIR[2] or 0, wx, wz, wk, dot))
  check("DRIFT", calmOK and wk > 0 and (amount <= 0.05 or dot > 0.5),
        ("calm |v|<1.5 (%s), windward dot %.2f"):format(tostring(calmOK), dot))
  Wind.setting:sync(0)
  wait(200)

  -- ------- DRAW
  check("DRAW", HearthFX.lastBatches > 0 and HearthFX.drawErrors == 0
        and HearthFX.errorCount == 0,
        ("batches %d, errors %d/%d"):format(HearthFX.lastBatches,
            HearthFX.errorCount, HearthFX.drawErrors))

  -- ------- PIXELS: the pair, shot with nothing else moving
  -- windows above each mouth in reach: the capture is the window, project
  -- answers in the scene canvas, and at this RES the two coincide (the
  -- occlusion probe reads them the same way)
  local function windows()
    local out = {}
    for _, c in ipairs(list) do
      local sx, sy = Voxel3D.project(c.x, c.y + 12, c.z)
      if sx and sy then
        out[#out + 1] = { x0 = math.floor(sx - 48), x1 = math.floor(sx + 48),
                          y0 = math.floor(sy - 90), y1 = math.floor(sy + 24),
                          name = ("%d,%d"):format(c.tx, c.ty) }
        log(("  mouth %d,%d projects to screen %d,%d"):format(
            c.tx, c.ty, math.floor(sx), math.floor(sy)))
      end
    end
    return out
  end
  local function diffCount(a, b, w)
    if not (a and b) then return -1 end
    local W, H = a:getWidth(), a:getHeight()
    local n = 0
    for y = math.max(0, w.y0), math.min(H - 1, w.y1) do
      for x = math.max(0, w.x0), math.min(W - 1, w.x1) do
        local r1, g1, b1 = a:getPixel(x, y)
        local r2, g2, b2 = b:getPixel(x, y)
        if math.abs(r1 - r2) > 0.12 or math.abs(g1 - g2) > 0.12
           or math.abs(b1 - b2) > 0.12 then n = n + 1 end
      end
    end
    return n
  end
  local wins = windows()
  local okOn, imgOn = shot("hearth_on.png")
  HearthFX.setting:sync("off")
  wait(40)
  log(("off: gate %s count %d batches %d"):format(HearthFX.lastGate,
      HearthFX.count(), HearthFX.lastBatches))
  check("GATE-OFF", HearthFX.lastGate == "HEARTH off" and HearthFX.count() == 0,
        "row OFF empties the field and names itself")
  local okOff, imgOff = shot("hearth_off.png")
  HearthFX.setting:sync("on")
  wait(240)
  local okOn2, imgOn2 = shot("hearth_on2.png")
  local best, bestName, best2 = -1, "?", -1
  for _, w in ipairs(wins) do
    local d1 = diffCount(imgOn, imgOff, w)
    local d2 = diffCount(imgOn2, imgOff, w)
    log(("  window %s  on-off %d px  on2-off %d px"):format(w.name, d1, d2))
    if d1 > best then best, bestName, best2 = d1, w.name, d2 end
  end
  check("PIXELS", okOn and okOff and okOn2 and best >= 30 and best2 >= 30,
        ("above %s: %d px differ ON vs OFF, %d px ON2 vs OFF"):format(
            bestName, best, best2))

  -- ------- and three plain portraits, for the eye. At the far rung (4)
  -- the roof of any house sits near the top of the frame and the plume
  -- climbs out of it, so: the middle rung two cells from the house, and
  -- the far rung right at its door -- at the dusk that lights it, and at
  -- a noon that shows the puffs against a blue sky
  Pipelines.setLevel("terrarium_voxel", 3)
  ow:setMap("PALLET_TOWN", 6, 8, "up")
  wait(360)
  shot("hearth_mid_dusk.png")
  DayNight.setting:sync("day")
  wait(240)
  shot("hearth_mid_day.png")
  DayNight.setting:sync("dusk")
  Pipelines.setLevel("terrarium_voxel", 4)
  ow:setMap("PALLET_TOWN", 6, 6, "up")
  wait(360)
  shot("hearth_door_dusk.png")

  log("")
  if #fails == 0 then log("ALL RULES PASS")
  else log("FAILED: " .. table.concat(fails, ", ")) end
  logf:close()
  love.event.quit()
end
