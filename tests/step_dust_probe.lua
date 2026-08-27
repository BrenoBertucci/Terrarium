-- T10: footstep dust, measured.
--
-- The claims, each as a number:
--
--   EMITS      walking N px emits ~N/8 footfalls' worth of particles
--              (each footfall tries a kick at 0.85 and a puff at 0.70,
--              so ~1.55 per stride at PFX ON on dry ground)
--   STILL AIR  all of it with the WIND ROW OFF: WindFX gated out ("wind
--              below FLOOR"), StepFX alive -- the whole reason it owns
--              its own field
--   KICKED     young kick grains carry backward velocity (walking east,
--              their vx is negative) which the drag then spends
--   SETTLES    stop walking: emission stops and the field drains to
--              zero inside the longest ttl
--   MUD        wetness >= WET_KILL kills emission exactly (the accessor
--              is overridable so the gate is tested without 70s of rain
--              -- armadilha 6); snow cover likewise
--   INDOORS    an indoor map gates the whole module ("indoors")
--   CLEAN      no errors, pipeline canaries alive, draw batches > 0
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/step_dust_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/step_dust.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local function hold(b, n)
    for _ = 1, n do
      game.input.pressQueue[#game.input.pressQueue + 1] = b
      coroutine.yield()
    end
  end
  local function shotWhileHolding(name, b)
    local done = false
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      done = true
    end)
    local guard = 0
    while not done and guard < 240 do
      if b then game.input.pressQueue[#game.input.pressQueue + 1] = b end
      coroutine.yield(); guard = guard + 1
    end
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
  local StepFX   = lib.require("StepFX")
  local AmbientLife = lib.require("AmbientLife")
  local Quality  = lib.require("Quality")
  local Voxel3D  = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")

  Weather.setting:sync("off")
  Wind.setting:sync(0)               -- WIND OFF: the still-air claim
  AmbientLife.setting:sync("off")
  Quality.particleSetting:sync(1)    -- PFX ON: mul 1, the countable rate
  Pipelines.setLevel("terrarium_voxel", 4)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  DayNight.setting:sync("day")
  local ow = game.overworld
  ow:setMap("ROUTE_1", 8, 22, "up")
  wait(400)
  -- a wild encounter mid-walk puts a battle on the stack and the walk
  -- dies at 80px ("overworld not on top") -- it happened. The engine's
  -- own repel counter blocks them.
  if game.save then game.save.repelSteps = 9999 end
  log("repelSteps: " .. tostring(game.save and game.save.repelSteps))
  local p = ow.player
  log(("map %s  player cell %d,%d  px=%s py=%s")
      :format(ow.map.id, p.cellX, p.cellY, tostring(p.px), tostring(p.py)))
  log(("wetness %.3f  snow %.3f  PFX mul %.2f")
      :format(StepFX.wetness() or -1, StepFX.snow() or -1, Quality.particles()))

  -- ------- BASELINE: the route's own walkers dust too (a feature, and
  -- the reason every count below subtracts them). Player stands still.
  local bgEmit, bgLive
  do
    local e0 = StepFX.emitted
    local liveMax = 0
    for _ = 1, 300 do
      coroutine.yield()
      local c = StepFX.count()
      if c > liveMax then liveMax = c end
    end
    bgEmit = StepFX.emitted - e0
    bgLive = liveMax
    log(("baseline (NPCs only): %d emissions / 300 ticks  live max %d  %s")
        :format(bgEmit, bgLive, bgEmit > 0 and "PASS (NPC path works)"
                                            or "note: no walkers near"))
  end

  -- ------- EMITS + KICKED, walking east with the wind row OFF
  --
  -- The first cut divided emissions by the PLAYER's distance and read
  -- x3.3 the expected rate. The overcount was the CAST: this is Yellow,
  -- so Pikachu walks every step the player does, and a route NPC paced
  -- alongside -- each a legitimate emitter (the feature, not a bug). The
  -- contract is per WALKER stride, so the probe now accounts every
  -- in-range walker's distance the same way the emitter does.
  local e0 = StepFX.emitted
  local x0 = (p.px or 0)
  local kickN, kickVx, maxLive, maxBatches = 0, 0, 0, -1
  local track, totalDist = {}, 0
  local function accumulate()
    local pl = ow.player
    local plx = ((pl and pl.px) or 0) + 8
    local plz = ((pl and pl.py) or 0) + 8
    local range = StepFX.REACH * 16
    local function acc(e)
      if not e then return end
      local x, z = (e.px or 0) + 8, (e.py or 0) + 8
      local t = track[e]
      if t then
        local ddx, ddz = x - t.x, z - t.z
        local d = math.sqrt(ddx * ddx + ddz * ddz)
        if d > 0.01 and d <= 24
           and math.abs(x - plx) <= range
           and math.abs(z - plz) <= range then
          totalDist = totalDist + d
        end
        t.x, t.z = x, z
      else
        track[e] = { x = x, z = z }
      end
    end
    acc(pl)
    local npcs = ow.npcs or {}
    for i = 1, #npcs do
      if npcs[i] ~= pl then acc(npcs[i]) end
    end
  end
  for i = 1, 300 do
    game.input.pressQueue[#game.input.pressQueue + 1] = "right"
    coroutine.yield()
    accumulate()
    local c = StepFX.count()
    if c > maxLive then maxLive = c end
    if StepFX.lastBatches > maxBatches then maxBatches = StepFX.lastBatches end
    if i % 10 == 0 then
      local ppx = ((ow.player and ow.player.px) or 0) + 8
      for j = 1, c do
        local m = StepFX.get(j)
        -- near the player: the player's own grains plus the follower's,
        -- and both walk east here, so both kick west
        if m and m.kind == "kick" and m.t < 0.25
           and math.abs(m.x - ppx) < 30 then
          kickN = kickN + 1
          kickVx = kickVx + (m.vx or 0)
        end
      end
    end
  end
  local x1 = ((ow.player and ow.player.px) or 0)
  local dist = math.abs(x1 - x0)
  local emitted = StepFX.emitted - e0
  local perStride = (totalDist > 8) and emitted / (totalDist / StepFX.STRIDE) or -1
  log(("walk: player dist %.0f px  all-walker dist %.0f px  emissions %d  "
       .. "per-stride %.2f (expect ~1.55)")
      :format(dist, totalDist, emitted, perStride))
  log(("walk verdict: %s")
      :format((dist > 100 and emitted > 0 and perStride > 0.9
               and perStride < 2.2) and "PASS" or "FAIL"))
  local meanKick = kickN > 0 and kickVx / kickN or 0
  log(("kick: %d young grains near player, mean vx %.2f (walking east)  %s")
      :format(kickN, meanKick, (kickN > 3 and meanKick < -2) and "PASS" or "FAIL"))
  log(("still air: WindFX gate [%s]  StepFX gate [%s]  %s")
      :format(tostring(WindFX.lastGate), tostring(StepFX.lastGate),
              (WindFX.lastGate ~= "live" and StepFX.lastGate == "live")
              and "PASS" or "FAIL"))
  log(("draw: max live %d  max scene batches %d  %s")
      :format(maxLive, maxBatches, maxBatches > 0 and "PASS" or "FAIL"))

  -- ------- SETTLES, against the background rate rather than zero
  do
    local eStop = StepFX.emitted
    wait(300)          -- same window as the baseline
    local after = StepFX.emitted - eStop
    local ok = after <= math.max(6, bgEmit * 2) and StepFX.count() <= bgLive + 6
    log(("settle: emitted +%d after stopping (bg was %d)  live %d "
         .. "(bg max %d)  %s")
        :format(after, bgEmit, StepFX.count(), bgLive, ok and "PASS" or "FAIL"))
  end

  -- ------- MUD and SNOW, by overriding the overridable accessors
  do
    local keepWet, keepSnow = StepFX.wetness, StepFX.snow
    StepFX.wetness = function() return 0.9 end
    local e1 = StepFX.emitted
    hold("left", 120)
    local mud = StepFX.emitted - e1
    StepFX.wetness = keepWet
    StepFX.snow = function() return 0.9 end
    local e2 = StepFX.emitted
    hold("right", 120)
    local snow = StepFX.emitted - e2
    StepFX.snow = keepSnow
    log(("mud: %d emissions on soaked ground  snow: %d under cover  %s")
        :format(mud, snow, (mud == 0 and snow == 0) and "PASS" or "FAIL"))
  end

  -- ------- INDOORS (soft: skipped if the warp does not land)
  do
    local okWarp = pcall(function() ow:setMap("REDS_HOUSE_1F", 4, 6, "up") end)
    if okWarp then
      wait(120)
      local e1 = StepFX.emitted
      hold("left", 90)
      hold("right", 90)
      log(("indoors: gate [%s]  emissions %d  %s")
          :format(tostring(StepFX.lastGate), StepFX.emitted - e1,
                  (StepFX.lastGate ~= "live" and StepFX.emitted - e1 == 0)
                  and "PASS" or "FAIL"))
      pcall(function() ow:setMap("ROUTE_1", 8, 22, "up") end)
      wait(200)
    else
      log("indoors: SKIP (warp failed)")
    end
  end

  -- ------- CLEAN
  log(("errors: update %s (%d)  draw %s (%d)")
      :format(tostring(StepFX.lastError), StepFX.errorCount,
              tostring(StepFX.drawError), StepFX.drawErrors))
  log(("canaries: Weather.ticks %s ok %s  StepFX.ticks %d live %d")
      :format(tostring(Weather.ticks), tostring(Weather.ticksOk),
              StepFX.ticks, StepFX.ticksLive))

  -- ------- the picture: a run with the wind back on, shot mid-stride.
  -- On PALLET's open paving: the Route 1 shot landed inside tall-grass
  -- hulls, which stand 16 high and correctly OCCLUDE boot-height dust --
  -- the depth test doing its job against the camera.
  Wind.setting:sync(2)
  pcall(function() ow:setMap("PALLET_TOWN", 12, 12, "up") end)
  wait(200)
  if game.save then game.save.repelSteps = 9999 end
  hold("right", 80)
  local pp = ow.player
  local sx, sy = Voxel3D.project((pp.px or 0) + 8, 4, (pp.py or 0) + 8)
  -- the projection reads LAST frame's camera; a warp round-trip can leave
  -- it absurd for a frame, and the camera centres the walker anyway
  if not (sx and sy and sx > 0 and sx < 1536 and sy > 0 and sy < 864) then
    sx, sy = 768, 500
  end
  log(("shot: player at screen %d,%d  px=%s py=%s")
      :format(math.floor(sx), math.floor(sy), tostring(pp.px), tostring(pp.py)))
  shotWhileHolding("step_dust.png", "right")

  log("done")
  logf:close()
  love.event.quit()
end
