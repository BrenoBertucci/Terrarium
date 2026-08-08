-- Probe: aerial perspective (lib/Aerial.lua) -- does far ground actually go
-- to haze, and does near ground stay put?
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/aerial_probe.lua gen1recomp
--
-- WHAT IS MEASURED, and why it is this and not "the screenshot looks foggy".
-- The haze colour is known exactly (Sky.haze -- the sky's palest band), so
-- for any pixel the distance to it in RGB is a number, and the claim the
-- feature makes is a claim about TWO of those numbers moving differently:
--
--   FAR band    the world's own top edge -- the first non-sky pixel down
--               each column, which is the far tree line. This has to
--               COLLAPSE toward the haze when the rung comes on.
--   NEAR band   the bottom of the frame, the ground within a screen of the
--               player. This has to BARELY MOVE -- a rung that washes out
--               the ground being played on is a bug, not a stronger effect.
--
-- WHY THE FAR BAND IS NOT PLACED ON THE HORIZON, which is where it started.
-- Voxel3D.horizonY gives the ground plane's vanishing row exactly, and it
-- was the obvious anchor. It measured pure sky and reported 0.0000 for
-- every rung -- because the drawn world STOPS about 140 pixels short of its
-- own vanishing line. That is not a flaw in the probe, it is the subject:
-- the ground runs out, the curve bends what is left away, and most of the
-- frame is empty sky. The gap is reported below as a number in its own
-- right.
--
-- EVERYTHING IS PAIRED, and that is the whole structure of this file. An
-- earlier cut took one OFF shot at the top and compared a dozen later shots
-- against it; over those shots the player drifted several tiles, the near
-- band slid off flat path onto a dark ledge, and the log faithfully reported
-- the haze making near ground DARKER. Every band here is a fixed rectangle
-- of screen, so nothing may move between the two halves of a comparison. So
-- each measurement is its own OFF/ON pair taken a few frames apart, the
-- world edge is re-found from that pair's own OFF frame, and a pair whose
-- two halves disagree about where the player is standing is thrown out.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/aerial_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  log("driver start")
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

  local Aerial = lib.require("Aerial")
  local Voxel3D = lib.require("Voxel3D")
  local Sky = lib.require("Sky")
  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local MiniMap = lib.require("MiniMap")
  local AutoFarm = lib.require("AutoFarm")
  local Pipelines = require("src.render.Pipelines")

  -- The lowest camera rung: 75 degrees is the only one with the horizon
  -- genuinely in frame, and a horizon is what this whole file is about.
  Pipelines.setLevel("terrarium_voxel", 5)
  -- The blur would average the two bands into each other, which is exactly
  -- the measurement.
  Pipelines.setLevel("terrarium_tiltshift", 0)
  -- Nothing in the corner of the frame, and nothing falling through it.
  MiniMap.setting:setIndex(3, game)          -- OFF
  Weather.setting:setIndex(2, game)          -- OFF
  -- And this is what was walking the player out of frame. The save this
  -- probe opens has A-FARM armed, so a bot was pushing directions into the
  -- press queue between the two halves of every pair -- which is why the
  -- log kept voiding pairs and why the near band appeared to move.
  AutoFarm.setting:setIndex(1, game)         -- OFF
  wait(120)

  -- Noon: the widest gap between the haze and the ground's own colours, so
  -- the metric has the most room to move. Re-pinned every frame -- the
  -- clock advances from the pipeline's update and would drift the sky out
  -- from under a comparison.
  local CLOCK = 300
  local function hold(frames)
    for _ = 1, frames do DayNight.clock = CLOCK; coroutine.yield() end
    DayNight.clock = CLOCK
  end

  -- Somewhere with a distance to lose. Wherever the save happens to sit is
  -- no good: the first run opened beside a building on ROUTE_8, the roof
  -- filled the frame from the near band to past the horizon row, and every
  -- number was a measurement of one roof two tiles away. ROUTE_1 facing
  -- north is a long open run.
  local SPOT = { "ROUTE_1", 8, 12, "up" }
  -- The settle is long on purpose. At 70 frames the first three pairs of a
  -- run came back identical whatever the rung, because the chunk mesher
  -- builds asynchronously and until its terrain lands the pass falls back
  -- to the flat 2D path -- which no shader uniform can touch. Those pairs
  -- were not measuring a weak effect, they were measuring a different
  -- renderer.
  local function repin()
    game.overworld:setMap(SPOT[1], SPOT[2], SPOT[3], SPOT[4])
    hold(300)
  end
  repin()

  -- ------- the bands
  local function skyish(r, g, b)
    return b > g + 0.02 and b > r + 0.02
  end

  local function findEdge(data, W, H, x0, x1)
    local edge = {}
    for x = x0, x1, 2 do
      for y = 2, H - 24 do
        local r, g, b, a = data:getPixel(x, y)
        if a > 0.01 and not skyish(r, g, b) then
          edge[#edge + 1] = { x, y }
          break
        end
      end
    end
    return edge
  end

  local FAR_DEPTH = 18        -- rows of world below the edge that count

  local function edgeStats(data, edge, H, haze)
    local sum, sumL, count = 0, 0, 0
    for _, p in ipairs(edge) do
      for y = p[2] + 1, math.min(H - 2, p[2] + FAR_DEPTH) do
        local r, g, b, a = data:getPixel(p[1], y)
        if a > 0.01 then
          local dr, dg, db = r - haze[1], g - haze[2], b - haze[3]
          sum = sum + math.sqrt(dr * dr + dg * dg + db * db)
          sumL = sumL + (r * 0.30 + g * 0.59 + b * 0.11)
          count = count + 1
        end
      end
    end
    if count == 0 then return nil end
    return sum / count, sumL / count, count
  end

  local function bandStats(data, y0, y1, x0, x1, haze)
    local sum, sumL, count = 0, 0, 0
    for y = y0, y1 do
      for x = x0, x1 do
        local r, g, b, a = data:getPixel(x, y)
        if a > 0.01 then
          local dr, dg, db = r - haze[1], g - haze[2], b - haze[3]
          sum = sum + math.sqrt(dr * dr + dg * dg + db * db)
          sumL = sumL + (r * 0.30 + g * 0.59 + b * 0.11)
          count = count + 1
        end
      end
    end
    if count == 0 then return nil end
    return sum / count, sumL / count, count
  end

  -- `edge` is handed in for the ON half of a pair so both halves count the
  -- same pixels. Re-finding it under haze would be the classic
  -- self-defeating measurement: fog makes far trees sky-coloured, the
  -- detector walks past them onto nearer ground, and the effect hides its
  -- own evidence.
  local function measure(name, edge)
    local haze = Sky.haze()
    local pending, rec = true, nil
    love.graphics.captureScreenshot(function(data)
      local W, H = data:getDimensions()
      local p = game.overworld.player
      rec = { name = name, W = W, H = H, haze = haze,
              hy = Voxel3D.horizonY(H),
              at = p and ("%s,%s"):format(tostring(p.cellX), tostring(p.cellY)) }
      if haze then
        local x0, x1 = math.floor(W * 0.10), math.floor(W * 0.90)
        if not edge then
          edge = findEdge(data, W, H, x0, x1)
          local sum = 0
          for _, q in ipairs(edge) do sum = sum + q[2] end
          rec.edgeY = #edge > 0 and sum / #edge or nil
        end
        rec.edge = edge
        rec.far, rec.farL = edgeStats(data, edge, H, haze)
        rec.near, rec.nearL = bandStats(data, math.floor(H * 0.80),
                                        math.floor(H * 0.93), x0, x1, haze)
        -- MID: the ground between the two, which is where the player is
        -- about to walk. The near band alone cannot vouch for the rung --
        -- it sits BETWEEN the camera and the player, closer to the eye
        -- than the player is, so it clamps to zero haze no matter how
        -- aggressive the range gets and would report every setting as
        -- free. This band is the one that has something to lose.
        local mid = 0
        for _, q in ipairs(edge) do mid = mid + q[2] end
        mid = #edge > 0 and (mid / #edge) or (H * 0.45)
        local my0 = math.floor(mid + FAR_DEPTH + 12)
        local my1 = math.floor(H * 0.78)
        if my1 > my0 + 8 then
          rec.mid, rec.midL = bandStats(data, my0, my1, x0, x1, haze)
        end
      end
      local f = io.open(OUT .. "/" .. name .. ".png", "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      pending = false
    end)
    local guard = 0
    while pending and guard < 240 do hold(1); guard = guard + 1 end
    return rec
  end

  -- One OFF/ON pair, four frames apart, at one range and one rung.
  local function pair(tag, level, near, far)
    Aerial.NEAR, Aerial.FAR = near, far
    Aerial.setting:setIndex(1, game)              -- OFF
    hold(4)
    local a = measure(tag .. "_off", nil)
    Aerial.setting:setIndex(level + 1, game)      -- ladder is 0,1,2,3
    hold(4)
    local b = measure(tag .. "_on", a and a.edge)
    return a, b
  end

  local function report(label, a, b)
    if not (a and b and a.far and b.far) then
      log(("  %-18s FAIL: no bands"):format(label))
      return nil
    end
    if a.at ~= b.at then
      log(("  %-18s VOID: the player moved between halves (%s -> %s)")
          :format(label, tostring(a.at), tostring(b.at)))
      return nil
    end
    local dF = (a.far - b.far) / math.max(1e-6, a.far) * 100
    local dN = (a.near - b.near) / math.max(1e-6, a.near) * 100
    local dM = (a.mid and b.mid)
               and (a.mid - b.mid) / math.max(1e-6, a.mid) * 100 or nil
    log(("  %-18s far %.4f -> %.4f (%+6.1f%%)   mid %s   near (%+5.1f%%)")
        :format(label, a.far, b.far, dF,
                dM and ("%.4f -> %.4f (%+6.1f%%)"):format(a.mid, b.mid, dM)
                    or "n/a", dN))
    return dF, dM or dN
  end

  log("")
  log("=== setup ===")
  local hz = Sky.haze()
  log(("  clock=%d  weather=%s  voxel rung=5 (75deg)  tilt=0  spot=%s(%d,%d)")
      :format(CLOCK, tostring(Weather.setting:get()), SPOT[1], SPOT[2], SPOT[3]))
  log(("  haze=%.3f,%.3f,%.3f  shipped NEAR=%.2fvh FAR=%.2fvh rungs=%d")
      :format(hz and hz[1] or -1, hz and hz[2] or -1, hz and hz[3] or -1,
              Aerial.NEAR, Aerial.FAR, Aerial.RUNGS))
  local nearWas, farWas = Aerial.NEAR, Aerial.FAR

  -- ------- phase 0: is the uniform even arriving?
  --
  -- Separated from the measurement on purpose. "The far band did not move"
  -- has two completely different causes -- the fog never reached the shader,
  -- or it reached it and the band was pointed at the wrong part of the world
  -- -- and a probe that cannot tell them apart sends you to read the wrong
  -- file. With the haze starting at the player's feet every pixel of ground
  -- must move, whatever the frame happens to be looking at.
  log("")
  log("=== phase 0: plumbing (haze forced to 0.00 .. 0.60 vh, top rung) ===")
  local p0, p1 = pair("aerial_0_plumb", 3, 0.0, 0.60)
  local pF = report("0.00 .. 0.60", p0, p1)
  log(("  %s"):format(pF and pF > 20
                      and "PASS: the uniform reaches the shader"
                      or "FAIL: nothing moved -- the fog never got there"))

  if p0 and p0.edgeY and p0.hy then
    log("")
    log("=== how much world there is to fog ===")
    log(("  horizon row %.1f, world's top edge row %.1f -- the drawn world "
         .. "stops %.0f px (%.0f%% of the frame) short of its own vanishing "
         .. "line"):format(p0.hy, p0.edgeY, p0.edgeY - p0.hy,
                           (p0.edgeY - p0.hy) / p0.H * 100))
  end

  -- ------- phase 1: WHERE IS THE WORLD, actually?
  --
  -- NEAR / FAR are written in view-heights against a claim inherited from
  -- WorldCurve -- that the far edge of visible ground sits a little over two
  -- view-heights out. That claim is about the ground PLANE, which runs to
  -- the horizon in the projection. It is not about the ground that is DRAWN,
  -- which stops at the border trees. This sweep asks the drawn world where
  -- it is. What is wanted is the range with a large far delta and a near
  -- delta in the noise: a range that moves both is not depth, it is a tint.
  log("")
  log("=== phase 1: range sweep, top rung ===")
  local SWEEP = {
    { 0.10, 0.45 }, { 0.15, 0.55 }, { 0.20, 0.60 }, { 0.25, 0.70 },
    { 0.30, 0.75 }, { 0.45, 1.00 }, { 0.60, 1.40 }, { 0.90, 2.60 },
  }
  local best, bestScore = nil, -1e9
  for i, s in ipairs(SWEEP) do
    local a, b = pair(("aerial_1_sweep%d"):format(i), 3, s[1], s[2])
    local dF, dN = report(("%.2f .. %.2f"):format(s[1], s[2]), a, b)
    if dF then
      -- what is wanted, as one number: far movement, minus a heavy penalty
      -- for anything the near ground had to pay for it
      local score = dF - 2.5 * math.abs(dN)
      if score > bestScore then best, bestScore = s, score end
    end
  end
  if best then
    log(("  best trade: NEAR=%.2f FAR=%.2f (score %.1f)")
        :format(best[1], best[2], bestScore))
  end

  -- ------- phase 2: the shipped range, every rung
  log("")
  log(("=== phase 2: shipped range %.2f .. %.2f, rung by rung ==="):
      format(nearWas, farWas))
  for level = 1, 3 do
    local a, b = pair(("aerial_2_rung%d"):format(level), level, nearWas, farWas)
    report(("rung %d (%.2f)"):format(level, Aerial.AMOUNTS[level + 1] or 0), a, b)
  end

  -- ------- phase 3: OFF twice, to size the noise floor
  --
  -- Two identical settings a few frames apart. Whatever they differ by is
  -- what wind in the trees and the world's own animation cost, and no delta
  -- above is worth reading unless it clears this.
  log("")
  log("=== phase 3: noise floor (OFF vs OFF) ===")
  local z0, z1 = pair("aerial_3_noise", 0, nearWas, farWas)
  report("OFF vs OFF", z0, z1)

  Aerial.NEAR, Aerial.FAR = nearWas, farWas
  log("")
  log("done -- " .. OUT)
  logf:close()
  love.event.quit()
end
