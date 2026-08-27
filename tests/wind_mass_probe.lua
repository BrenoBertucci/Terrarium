-- T8: mass and drag, measured as physics before it is believed as look.
--
-- The solver's velocity is now a STATE that converges on the air's
-- target with tau = Particles.TAU * mass / area. Four claims, four
-- measurements:
--
--   LAW        a particle started at rest converges geometrically with
--              ratio tau/(tau+dt) -- the implicit blend's own constant.
--              Fitted tau must match the configured one, light and heavy.
--              Measured in UNIFORM air: Wind.flow.amp = 0 collapses the
--              band to exactly 1 in the solver, so the target is
--              dir * speed everywhere and position stops mattering.
--   IDENTITY   in steady air every mass converges to the SAME target --
--              the baseline look is untouched. All seven shipping
--              mass/area pairs, curl stripped, 10s: |v - target| ~ 0.
--   MATERIAL   in live turbulent air, the light kind answers the eddies
--              and the heavy kind shrugs: RMS lateral velocity of a
--              leaf-mass ensemble vs a dash-mass ensemble, same starts,
--              same frozen air (one resume, no yields between runs).
--   SANITY     bounded velocities, zero allocation, live canaries.
--
-- Plus TRACE lines: ten trajectories (five light, five heavy) through
-- the same frozen eddies, for the picture the numbers cannot draw.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/wind_mass_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/wind_mass.log", "w"))
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
  log("version:", exports.TERRARIUM.version)

  local Weather  = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Wind     = lib.require("Wind")
  local WindFX   = lib.require("WindFX")
  local AmbientLife = lib.require("AmbientLife")
  local Particles = lib.require("Particles")
  local Pipelines = require("src.render.Pipelines")

  Weather.setting:sync("off")
  Wind.setting:sync(4)
  AmbientLife.setting:sync("off")
  Pipelines.setLevel("terrarium_voxel", 4)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  DayNight.setting:sync("day")
  local ow = game.overworld
  ow:setMap("ROUTE_1", 10, 20, "up")
  wait(400)
  log(("map %s  amount %.2f  TAU %.3f"):format(ow.map.id, Wind.amount(),
                                               Particles.TAU))

  local DT = 1 / 60
  local flat = function() return 0 end

  local function seedOne(F, kind, x, z, vx0)
    local p = F:claim()
    p.kind = kind
    p.x, p.z, p.y = x, z, 10
    p.t, p.ttl = 0, 1e9
    p.seed = 0
    p.fast, p.lift, p.spin = 1, 0, 0
    if vx0 ~= nil then p.vx, p.vz = vx0, 0 end
    return p
  end

  -- ------- LAW: geometric convergence at the configured tau
  do
    local f = Wind.flow
    local keepAmp = f.amp
    f.amp = 0                      -- uniform air: band collapses to 1
    local SPEED = 5
    local cases = {
      { name = "light(leaf m/a)", mass = 0.12, area = 2.20 },
      { name = "heavy(dash m/a)", mass = 0.50, area = 0.35 },
    }
    for _, c in ipairs(cases) do
      local tau = Particles.TAU * c.mass / c.area
      local kinds = { k = { mass = c.mass, area = c.area,
                            curlA = 0, curlB = 0, bob = 0, speed = 1 } }
      local F = Particles.newField(kinds, 4)
      local p = seedOne(F, "k", 300, 300, 0)   -- starts at REST
      local ctx = { dirX = 1, dirZ = 0, speed = SPEED, turbulence = 0,
                    floorAt = flat, originX = 300, originZ = 300,
                    reach = 1e9 }
      local v = { 0 }
      for s = 1, 12 do
        F:step(DT, ctx)
        v[#v + 1] = p.vx
      end
      -- fit the ratio over steps 2..6; v_inf is the exact target
      local rSum, rCnt = 0, 0
      for s = 2, 6 do
        local a = SPEED - v[s]
        local b = SPEED - v[s + 1]
        if a > 1e-9 then rSum = rSum + b / a; rCnt = rCnt + 1 end
      end
      local r = rCnt > 0 and rSum / rCnt or 0
      local tauHat = (r > 0 and r < 1) and (DT * r / (1 - r)) or -1
      local err = math.abs(tauHat - tau) / tau
      log(("law %s: tau %.4f  fitted %.4f  err %.1f%%  %s")
          :format(c.name, tau, tauHat, err * 100,
                  err < 0.15 and "PASS" or "FAIL"))
    end
    f.amp = keepAmp
  end

  -- ------- IDENTITY: every mass lands on the same steady target
  do
    local f = Wind.flow
    local keepAmp = f.amp
    f.amp = 0
    local SPEED = 40
    local worst, worstKind = 0, "?"
    for name, K in pairs(WindFX.KINDS) do
      local sm = K.speed
      if type(sm) == "function" then sm = 0.78 end   -- leaf: strip the pulse
      local kinds = { k = { mass = K.mass, area = K.area,
                            curlA = 0, curlB = 0, bob = 0, speed = sm } }
      local F = Particles.newField(kinds, 4)
      local p = seedOne(F, "k", 300, 300, 0)
      local ctx = { dirX = 1, dirZ = 0, speed = SPEED, turbulence = 0,
                    floorAt = flat, originX = 300, originZ = 300,
                    reach = 1e9 }
      for _ = 1, 600 do F:step(DT, ctx) end
      local target = SPEED * sm
      local err = math.abs(p.vx - target) / target
      if err > worst then worst, worstKind = err, name end
    end
    f.amp = keepAmp
    log(("identity: worst steady-state error %.2f%% (%s)  %s")
        :format(worst * 100, worstKind, worst < 0.02 and "PASS" or "FAIL"))
  end

  -- ------- MATERIAL: the light kind answers the eddies, the heavy shrugs
  --
  -- Live GALE air, both ensembles inside ONE resume so Wind is frozen
  -- between them. Lateral = velocity component across the bearing; the
  -- mean wind contributes none of it, the eddies all of it.
  do
    local amount = Wind.amount()
    local dirX, dirZ = Wind.DIR[1], Wind.DIR[2]
    local function ensemble(mass, area, trace, label)
      local kinds = { k = { mass = mass, area = area,
                            curlA = 0, curlB = 0, bob = 0, speed = 1 } }
      local F = Particles.newField(kinds, 64)
      for i = 1, 30 do
        seedOne(F, "k", 100 + (i * 61) % 400, 100 + (i * 37) % 400, nil)
      end
      local ctx = { dirX = dirX, dirZ = dirZ,
                    speed = amount * WindFX.SPEED,
                    turbulence = amount * WindFX.SPEED * WindFX.TURB,
                    floorAt = flat, originX = 300, originZ = 300,
                    reach = 1e9 }
      -- Two readings of "answers the eddies". Lateral VELOCITY is the
      -- gross drift, and the first run showed it barely separates
      -- (x1.22): the field's energy sits in 300-500px eddies, which at
      -- mote speed force at ~0.25Hz -- slow enough that even the dash
      -- follows them at 95%, WHICH IS WHAT HEAVY DEBRIS DOES. What the
      -- eye calls "the leaf dances, the dash glides" is the high
      -- frequency: lateral ACCELERATION weights the spectrum by f,
      -- exactly where a first-order filter with a bigger tau bites. The
      -- gate is the acceleration ratio; velocity stays as a report.
      local latSum, latCnt = 0, 0
      local accSum, accCnt = 0, 0
      local prevLat = {}
      for s = 1, 120 do
        F:step(DT, ctx)
        for i = 1, F:count() do
          local p = F:get(i)
          local lat = (p.vx or 0) * (-dirZ) + (p.vz or 0) * dirX
          if s > 20 then
            latSum = latSum + lat * lat
            latCnt = latCnt + 1
            local pl = prevLat[i]
            if pl then
              local a = (lat - pl) / DT
              accSum = accSum + a * a
              accCnt = accCnt + 1
            end
          end
          prevLat[i] = lat
        end
        if trace and s % 2 == 0 then
          for i = 1, 5 do
            local p = F:get(i)
            log(("TRACE %s %d %.2f %.2f"):format(label, i, p.x, p.z))
          end
        end
      end
      return math.sqrt(latSum / math.max(1, latCnt)),
             math.sqrt(accSum / math.max(1, accCnt))
    end
    local lv, la = ensemble(0.12, 2.20, true, "L")
    local gv, ga = ensemble(0.40, 0.30, false, "G")
    local hv, ha = ensemble(0.50, 0.35, true, "H")
    log(("material: lateral v RMS  leaf %.2f  grit %.2f  dash %.2f px/s"
         .. "  (leaf/dash x%.2f, report)")
        :format(lv, gv, hv, lv / math.max(1e-9, hv)))
    log(("material: lateral a RMS  leaf %.1f  grit %.1f  dash %.1f px/s2"
         .. "  (leaf/dash x%.2f)")
        :format(la, ga, ha, la / math.max(1e-9, ha)))
    log(("material verdict: %s")
        :format((la > ha * 1.5 and la > ga * 1.2) and "PASS" or "FAIL"))
  end

  -- ------- SANITY: bounded, allocation-free, canaries alive
  do
    local amount = Wind.amount()
    local kinds = { k = { mass = 0.5, area = 0.35, bob = 0, speed = 1 } }
    local F = Particles.newField(kinds, 80)
    for i = 1, 60 do
      seedOne(F, "k", 100 + (i * 61) % 400, 100 + (i * 37) % 400, nil)
    end
    local ctx = { dirX = Wind.DIR[1], dirZ = Wind.DIR[2],
                  speed = amount * WindFX.SPEED,
                  turbulence = amount * WindFX.SPEED * WindFX.TURB,
                  floorAt = flat, originX = 300, originZ = 300, reach = 1e9 }
    -- The first runs measured the WARMUP and read it as a leak: adding
    -- vx/vz to sixty pooled tables rehashes each once (~5 KB, one-time,
    -- the pool doing its job), and a control loop's GC arithmetic came
    -- back negative. The claim that matters is STEADY STATE: after the
    -- fields exist and every table has its shape, more steps allocate
    -- nothing. So: warm up first, then measure.
    local function scan()
      local vmax = 0
      for i = 1, F:count() do
        local p = F:get(i)
        local v = math.sqrt((p.vx or 0) ^ 2 + (p.vz or 0) ^ 2)
        if v > vmax then vmax = v end
      end
      return vmax
    end
    for _ = 1, 60 do F:step(DT, ctx) end     -- warmup: shapes settle
    collectgarbage("collect")
    local k0 = collectgarbage("count")
    local vmax = 0
    for _ = 1, 240 do
      F:step(DT, ctx)
      local v = scan()
      if v > vmax then vmax = v end
    end
    collectgarbage("collect")
    local k1 = collectgarbage("count")
    local cap = amount * WindFX.SPEED * 3
    log(("sanity: vmax %.1f (cap %.1f)  steady-state alloc %+.2f KB/240 steps  %s")
        :format(vmax, cap, k1 - k0,
                (vmax < cap and (k1 - k0) < 2) and "PASS" or "FAIL"))
  end

  -- the live field itself, running the shipping kinds under GALE
  wait(500)
  log(("canaries: WindFX.ticks %s live %s gate %s  batches %s")
      :format(tostring(WindFX.ticks), tostring(WindFX.ticksLive),
              tostring(WindFX.lastGate), tostring(WindFX.lastBatches)))

  log("done")
  logf:close()
  love.event.quit()
end
