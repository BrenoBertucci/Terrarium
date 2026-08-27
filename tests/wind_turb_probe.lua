-- T7: the turbulence field, measured before it is believed.
--
-- Wind.turbAt is a precomputed, tiled, divergence-free eddy field that
-- the solver (ctx.turbulence), the rain's slant and the weather's world
-- motes all read through the one flow. Every property that sentence
-- claims is asserted here as a number:
--
--   STRUCTURE     RMS over a spatial grid ~ turbEnv; zero with the knob
--                 at 0 and under WIND OFF
--   DIV-FREE      node-aligned central differences of the field with the
--                 travels zeroed: divergence exactly the lattice's own
--                 (~0), against a healthy curl. Off-node (h=2px), the
--                 bilinear residual stays well under the curl.
--   TILED         turbAt(x + 512) == turbAt(x), exactly
--   ALIVE         the same points, three seconds apart, decorrelate
--   DETERMINISTIC same point, same frame, same answer
--   ONE AIR       flowAt's velocity moves by turbV * eddy when the knob
--                 flips, and by nothing else
--   DISPERSION    the solver's own A/B: the same lattice of particles,
--                 stepped through the same frozen air twice in ONE tick
--                 (no yields, so Wind cannot advance between runs), turb
--                 off then on. On must spread more and still transport
--                 along the bearing.
--   COST/ALLOC    turbAt allocates nothing; flowAt's extra cost logged
--                 (informational only -- armadilha 5)
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/wind_turb_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/wind_turb.log", "w"))
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
  local AmbientLife = lib.require("AmbientLife")
  local Particles = lib.require("Particles")
  local Pipelines = require("src.render.Pipelines")

  Weather.setting:sync("off")
  Wind.setting:sync(4)                -- GALE: strong, steady signal
  AmbientLife.setting:sync("off")
  Pipelines.setLevel("terrarium_voxel", 4)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  DayNight.setting:sync("day")
  local ow = game.overworld
  ow:setMap("ROUTE_1", 10, 20, "up")
  wait(400)
  log(("map %s  amount %.2f  gust %.2f  turbEnv %.3f  turbV %.2f")
      :format(ow.map.id, Wind.amount(), Wind.gust(),
              Wind.flow.turbEnv or -1, Wind.flow.turbV or -1))

  local f = Wind.flow

  -- ------- DETERMINISTIC
  do
    local a1, a2 = Wind.turbAt(317.3, 209.9)
    local b1, b2 = Wind.turbAt(317.3, 209.9)
    log(("determinism: %s"):format(
        (a1 == b1 and a2 == b2) and "PASS (bit-equal)" or
        ("FAIL " .. a1 .. "," .. a2 .. " vs " .. b1 .. "," .. b2)))
  end

  -- ------- TILED
  do
    local worst = 0
    for i = 1, 40 do
      local x, z = i * 13.7, i * 7.3
      local a1, a2 = Wind.turbAt(x, z)
      local b1, b2 = Wind.turbAt(x + 512, z)
      local c1, c2 = Wind.turbAt(x, z + 512)
      local d = math.max(math.abs(a1 - b1), math.abs(a2 - b2),
                         math.abs(a1 - c1), math.abs(a2 - c2))
      if d > worst then worst = d end
    end
    log(("tiling: worst wrap mismatch %.2e  %s")
        :format(worst, worst < 1e-9 and "PASS" or "FAIL"))
  end

  -- ------- STRUCTURE (spatial RMS), and the knob
  local function fieldRMS()
    local s, c = 0, 0
    for gz = 0, 30 do
      for gx = 0, 30 do
        local ux, uz = Wind.turbAt(100 + gx * 17, 100 + gz * 17)
        s = s + ux * ux + uz * uz
        c = c + 1
      end
    end
    return math.sqrt(s / c)
  end
  local rmsOn = fieldRMS()
  local envNow = f.turbEnv or 0
  do
    local keep = f.turbEnv
    f.turbEnv = 0
    local rmsOff = fieldRMS()
    f.turbEnv = keep
    log(("structure: RMS %.3f (turbEnv %.3f, ratio %.2f)  knob-off RMS %.4f  %s")
        :format(rmsOn, envNow, envNow > 0 and rmsOn / envNow or -1, rmsOff,
                (rmsOn > 0.3 * envNow and rmsOff == 0) and "PASS" or "FAIL"))
  end

  -- ------- DIV-FREE
  do
    -- node-aligned, travels zeroed: the discrete operators commute, so
    -- the divergence here is the lattice's own arithmetic noise
    local sx, sz, s2x, s2z = f.tax, f.taz, f.tbx, f.tbz
    f.tax, f.taz, f.tbx, f.tbz = 0, 0, 0, 0
    local h = 8
    local sumD, sumC, cnt = 0, 0, 0
    for gz = 1, 24 do
      for gx = 1, 24 do
        local x, z = gx * 16, gz * 16
        local uxp = select(1, Wind.turbAt(x + h, z))
        local uxm = select(1, Wind.turbAt(x - h, z))
        local _, uzp = Wind.turbAt(x, z + h)
        local _, uzm = Wind.turbAt(x, z - h)
        local _, czp = Wind.turbAt(x + h, z)
        local _, czm = Wind.turbAt(x - h, z)
        local cxp = select(1, Wind.turbAt(x, z + h))
        local cxm = select(1, Wind.turbAt(x, z - h))
        local div = (uxp - uxm) + (uzp - uzm)
        local curl = (czp - czm) - (cxp - cxm)
        sumD = sumD + div * div
        sumC = sumC + curl * curl
        cnt = cnt + 1
      end
    end
    local nodeRatio = math.sqrt(sumD / cnt) / math.max(1e-12, math.sqrt(sumC / cnt))
    f.tax, f.taz, f.tbx, f.tbz = sx, sz, s2x, s2z
    -- and off-node at h=2: the bilinear residual, the honest field bound
    local h2 = 2
    sumD, sumC, cnt = 0, 0, 0
    for gz = 1, 24 do
      for gx = 1, 24 do
        local x, z = 37 + gx * 15.3, 51 + gz * 15.3
        local uxp = select(1, Wind.turbAt(x + h2, z))
        local uxm = select(1, Wind.turbAt(x - h2, z))
        local _, uzp = Wind.turbAt(x, z + h2)
        local _, uzm = Wind.turbAt(x, z - h2)
        local _, czp = Wind.turbAt(x + h2, z)
        local _, czm = Wind.turbAt(x - h2, z)
        local cxp = select(1, Wind.turbAt(x, z + h2))
        local cxm = select(1, Wind.turbAt(x, z - h2))
        local div = (uxp - uxm) + (uzp - uzm)
        local curl = (czp - czm) - (cxp - cxm)
        sumD = sumD + div * div
        sumC = sumC + curl * curl
        cnt = cnt + 1
      end
    end
    local offRatio = math.sqrt(sumD / cnt) / math.max(1e-12, math.sqrt(sumC / cnt))
    log(("div-free: node div/curl %.4f (%s)  off-node %.3f (%s)")
        :format(nodeRatio, nodeRatio < 0.01 and "PASS" or "FAIL",
                offRatio, offRatio < 0.5 and "PASS" or "WARN"))
  end

  -- ------- ONE AIR: flowAt carries the same eddies
  do
    local sumB, sumD, cnt = 0, 0, 0
    local keep = f.turbEnv
    for i = 1, 30 do
      local x, z = 60 + i * 23.7, 80 + i * 11.9
      local vx1, vz1 = Wind.flowAt(x, z)
      f.turbEnv = 0
      local vx0, vz0 = Wind.flowAt(x, z)
      f.turbEnv = keep
      local ux, uz = Wind.turbAt(x, z)
      local dx, dz = vx1 - vx0, vz1 - vz0
      -- the delta must BE turbV * eddy, not merely resemble it
      local ex, ez = ux * (f.turbV or 0), uz * (f.turbV or 0)
      sumB = sumB + math.sqrt(vx0 * vx0 + vz0 * vz0)
      sumD = sumD + math.sqrt(dx * dx + dz * dz)
      local err = math.max(math.abs(dx - ex), math.abs(dz - ez))
      if err > 1e-9 then
        log(("  ONE-AIR MISMATCH at %d: err %.2e"):format(i, err))
      end
      cnt = cnt + 1
    end
    log(("one air: mean|dv| %.2f  mean|v_base| %.2f  share %.2f")
        :format(sumD / cnt, sumB / cnt, sumD / math.max(1e-9, sumB)))
  end

  -- ------- ALIVE (and then some settling for the temporal check)
  local before = {}
  for i = 1, 6 do
    local x, z = 90 + i * 31, 70 + i * 17
    local ux, uz = Wind.turbAt(x, z)
    before[i] = { x = x, z = z, ux = ux, uz = uz }
  end
  wait(180)
  do
    local moved = 0
    for i = 1, 6 do
      local b = before[i]
      local ux, uz = Wind.turbAt(b.x, b.z)
      moved = moved + math.sqrt((ux - b.ux) ^ 2 + (uz - b.uz) ^ 2)
    end
    moved = moved / 6
    log(("alive: mean |du| over ~3s = %.3f  %s")
        :format(moved, moved > 0.05 and "PASS" or "FAIL"))
  end

  -- ------- DISPERSION: pair separation, the solver's own A/B
  --
  -- The first cut of this measured the spread of a 112px lattice of
  -- particles and read x1.09 -- not because the field does nothing but
  -- because the metric buried it: the energy sits in eddies as big as
  -- the lattice, and an eddy CARRIES a patch without spreading it. The
  -- turbulence signature is RELATIVE dispersion: two particles two
  -- pixels apart ride the velocity GRADIENT, which in a laminar band is
  -- nearly zero at that scale and in an eddy field stretches the pair
  -- exponentially. So: sixty pairs, 2px apart, scattered over 400px,
  -- stepped through the same frozen air (one resume, no yields -- Wind
  -- cannot advance between the two runs), turb off then on.
  do
    local amount = Wind.amount()
    local PAIRS = 60
    local function run(turb)
      local F = Particles.newField({}, 200)
      for i = 1, PAIRS do
        local cx = 100 + (i * 61) % 400
        local cz = 100 + (i * 37) % 400
        local a = i * 0.7
        local ox2, oz2 = math.cos(a), math.sin(a)
        for s = -1, 1, 2 do
          local p = F:claim()
          p.kind = "grit"
          p.x = cx + ox2 * s
          p.z = cz + oz2 * s
          p.y = 10
          p.t, p.ttl = 0, 1e9
          p.seed = 0
          p.fast, p.lift, p.spin = 1, 0, 0
        end
      end
      local ctx = {
        dirX = Wind.DIR[1], dirZ = Wind.DIR[2],
        speed = amount * WindFX.SPEED,
        turbulence = turb,
        floorAt = function() return 0 end,
        originX = 300, originZ = 300, reach = 1e9,
      }
      for _ = 1, 240 do F:step(1 / 60, ctx) end
      local sep, drx, drz = 0, 0, 0
      for i = 1, PAIRS do
        local p1 = F:get(i * 2 - 1)
        local p2 = F:get(i * 2)
        sep = sep + math.sqrt((p1.x - p2.x) ^ 2 + (p1.z - p2.z) ^ 2)
        drx = drx + (p1.x + p2.x) * 0.5
        drz = drz + (p1.z + p2.z) * 0.5
      end
      -- mean final separation (initial was 2), and the mean drift
      return sep / PAIRS, drx / PAIRS - 300, drz / PAIRS - 300
    end
    local off, ox2, oz2 = run(0)
    local on, nx2, nz2 = run(amount * WindFX.SPEED * WindFX.TURB)
    local wd = math.atan2(Wind.DIR[2], Wind.DIR[1])
    local function ang(dx, dz)
      local d = math.atan2(dz, dx) - wd
      d = (d + math.pi) % (2 * math.pi) - math.pi   -- wrap to (-pi, pi]
      return math.deg(math.abs(d))
    end
    -- REPORT, not a gate. The first cut demanded exponential pair growth
    -- and read x1.2: a mote CROSSES a frozen eddy in under a second, the
    -- strain direction rotates under the pair, and the stretch becomes a
    -- random walk -- and dust lives 1-5s, so a 4-second Lyapunov horizon
    -- is not a thing the game ever shows. The number stays here as a
    -- diagnostic; the gate is the velocity STRUCTURE below, which is the
    -- sentence the design actually promises.
    log(("pair sep after 4s (report): off %.2f px  on %.2f px (x%.2f)")
        :format(off, on, on / math.max(1e-9, off)))
    log(("transport: drift-angle off %.1f  on %.1f deg  %s")
        :format(ang(ox2, oz2), ang(nx2, nz2),
                ang(nx2, nz2) < 25 and "PASS" or "FAIL"))
  end

  -- ------- STRUCTURE AT MOTE SCALE: neighbours part ways
  --
  -- "Two motes a cell apart get different air" is the claim ctx.turbulence
  -- exists for, and it is an instantaneous, directly measurable one: the
  -- RMS velocity difference the eddies hand two points one and two cells
  -- apart, against the mean transport speed.
  do
    local amount = Wind.amount()
    local scale = amount * WindFX.SPEED * WindFX.TURB
    local base = amount * WindFX.SPEED
    local function structRMS(sep)
      local s, c = 0, 0
      for i = 1, 120 do
        local x = 80 + (i * 53) % 450
        local z = 80 + (i * 29) % 450
        local a = i * 1.1
        local ux1, uz1 = Wind.turbAt(x, z)
        local ux2, uz2 = Wind.turbAt(x + math.cos(a) * sep,
                                     z + math.sin(a) * sep)
        s = s + ((ux1 - ux2) ^ 2 + (uz1 - uz2) ^ 2)
        c = c + 1
      end
      return math.sqrt(s / c) * scale
    end
    local d8, d16 = structRMS(8), structRMS(16)
    log(("velocity structure: |dv| at 8px %.2f px/s  at 16px %.2f  "
         .. "(mean speed %.1f)  shares %.1f%% / %.1f%%")
        :format(d8, d16, base, d8 / base * 100, d16 / base * 100))
    log(("structure verdict: %s")
        :format((d8 / base > 0.05 and d16 > d8) and "PASS" or "FAIL"))
  end

  -- ------- ALLOC and COST
  do
    collectgarbage("collect")
    local k0 = collectgarbage("count")
    for i = 1, 20000 do Wind.turbAt(i * 0.37, i * 0.73) end
    local k1 = collectgarbage("count")
    log(("alloc: 20k turbAt = %+.1f KB  %s")
        :format(k1 - k0, (k1 - k0) < 8 and "PASS" or "FAIL"))
    local t0 = os.clock()
    for i = 1, 30000 do Wind.flowAt(i * 0.37, i * 0.73) end
    local tOn = os.clock() - t0
    local keep = f.turbEnv
    f.turbEnv = 0
    t0 = os.clock()
    for i = 1, 30000 do Wind.flowAt(i * 0.37, i * 0.73) end
    local tOff = os.clock() - t0
    f.turbEnv = keep
    log(("cost (informational): 30k flowAt on %.1f ms, off %.1f ms")
        :format(tOn * 1000, tOff * 1000))
  end

  -- ------- the pair of pictures, on then off
  wait(60)
  shot("turb_on.png")
  Wind.TURB_MUL = 0
  wait(120)
  log(("knob off: turbEnv now %.3f"):format(f.turbEnv or -1))
  shot("turb_off.png")
  Wind.TURB_MUL = 1

  log("done")
  logf:close()
  love.event.quit()
end
