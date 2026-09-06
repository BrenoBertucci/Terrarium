-- Probe: the standing block in the real town. Finds cells with a tall
-- occluder (a stamped building, or extruded ground) directly SOUTH of a
-- walkable cell -- where the default camera, standing south, looks
-- straight into it -- parks the player there, and photographs the camera
-- before the engage delay and after the lift has settled. Logs the lift,
-- the pull and the yaw, and whether the game's own ray still calls the
-- player hidden. The yaw must not move; the lift is what should.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/lift_probe.log", "w"))
  local function log(s) logf:write(s, "\n"); logf:flush() end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit() return end
  end
  while game.stack:top() ~= game.overworld do tap("a"); wait(10) end

  local lib = game.mods.exports.TERRARIUM.lib
  local MarioCam = lib.require("MarioCam")
  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local MiniMap = lib.require("MiniMap")
  local AutoFarm = lib.require("AutoFarm")
  local Pipelines = require("src.render.Pipelines")
  Pipelines.setLevel("terrarium_voxel", 4)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  MiniMap.setting:setIndex(3, game)
  Weather.setting:setIndex(2, game)
  AutoFarm.setting:setIndex(1, game)

  local CLOCK = 300
  local function hold(frames)
    for _ = 1, frames do DayNight.clock = CLOCK; coroutine.yield() end
  end
  local function releaseDirs()
    local st = game.input.state
    for _, d in ipairs({ "up", "down", "left", "right" }) do
      st[d] = false
      if game.input.sources then game.input.sources[d] = nil end
    end
    game.input.pressQueue = {}
  end
  local function shoot(name)
    local pending = true
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name .. ".png", "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      pending = false
    end)
    local guard = 0
    while pending and guard < 300 do hold(1); guard = guard + 1 end
  end
  local function parkAt(mapId, cx, cy, face, frames)
    for _ = 1, 3 do
      game.overworld:setMap(mapId, cx, cy, face)
      hold(frames or 150)
      releaseDirs()
      local p = game.overworld.player
      if math.floor((p.px + 8) / 16) == cx
         and math.floor((p.py + 8) / 16) == cy then
        return true
      end
    end
    return false
  end
  local fails = {}
  local function check(ok, msg)
    if not ok then fails[#fails + 1] = msg end
    log((ok and "  ok   " or "  FAIL ") .. msg)
  end

  local MAP = "CELADON_CITY"
  MarioCam.setting:setIndex(2, game)          -- ON
  check(parkAt(MAP, 25, 30, "up", 200), "in Celadon")
  local map = game.overworld.map

  -- the real occluder height the camera itself uses
  local okB, Buildings = pcall(lib.require, "Buildings")
  local function tallAt(cx, cy)
    local h = MarioCam.groundAt(map, cx, cy)
    if okB and Buildings and Buildings.tallAt then
      local okT, t = pcall(Buildings.tallAt, map, cx, cy)
      if okT and t and t > h then h = t end
    end
    return h
  end
  local function walkable(cx, cy)
    local ok, w = pcall(map.isWalkableCell, map, cx, cy)
    return ok and w
  end

  -- candidates: a walkable cell with something tall (a building's worth)
  -- on the two cells straight south of it
  local cands = {}
  for cy = 2, (map.heightCells or 36) - 3 do
    for cx = 2, (map.widthCells or 50) - 3 do
      if walkable(cx, cy) and not walkable(cx, cy + 1)
         and tallAt(cx, cy + 1) >= 48 and tallAt(cx, cy + 2) >= 48 then
        cands[#cands + 1] = { cx, cy, tallAt(cx, cy + 1) }
      end
    end
  end
  log(("%d candidate cells with a tall occluder due south"):format(#cands))
  -- spread the picks across the list rather than taking three neighbours
  local picks = {}
  if #cands > 0 then
    for i = 1, math.min(3, #cands) do
      picks[#picks + 1] = cands[math.floor((i - 0.5) * #cands / math.min(3, #cands)) + 1]
    end
  end

  local function pose()
    local lk = MarioCam.lakitu
    local ex, ey, ez = lk.curPos[1], lk.curPos[2], lk.curPos[3]
    local fx, fy, fz = lk.curFocus[1], lk.curFocus[2], lk.curFocus[3]
    local blocked = MarioCam.rayBlocked(map, ex, ey, ez, fx, fy + 8, fz)
    local dx, dz = fx - ex, fz - ez
    local flat = math.sqrt(dx * dx + dz * dz)
    local pitch = math.deg(math.atan2(ey - fy, flat))
    return blocked, pitch, ey
  end

  for i, c in ipairs(picks) do
    local cx, cy, h = c[1], c[2], c[3]
    log(("-- pick %d: cell (%d,%d), occluder %.0f px tall to the south"):format(i, cx, cy, h))
    MarioCam.setting:setIndex(2, game)        -- ON, the orbit
    if parkAt(MAP, cx, cy, "up", 120) then
      MarioCam.recenter()
      MarioCam.cut()
      hold(2)
      local ps = MarioCam.pullState
      local b0, p0 = pose()
      hold(8)                                 -- 10 frames: inside the delay
      local liftEarly, tEarly = ps.lift, ps.t
      shoot(("lift_%d_early"):format(i))
      hold(150)
      local liftLate, tLate = ps.lift, ps.t
      local b1, p1, ey1 = pose()
      local yaw = math.deg(MarioCam.viewYaw())
      shoot(("lift_%d_settled"):format(i))
      log(("   ON: blocked at first %s | early lift %.1f t %.2f | settled lift %.1f "
           .. "t %.2f pitch %.1f->%.1f eye y %.0f | blocked now %s | yaw %.1f")
          :format(tostring(b0), liftEarly, tEarly, liftLate, tLate, p0, p1, ey1,
                  tostring(b1), yaw))
      check(liftEarly < 0.5 and tEarly > 0.99,
            ("pick %d: nothing moved inside the engage delay"):format(i))
      if b0 then
        check(liftLate > 5 or tLate < 0.99,
              ("pick %d: a standing block was answered (lift %.1f, t %.2f)")
              :format(i, liftLate, tLate))
        check(not b1, ("pick %d: the player is visible once settled"):format(i))
      else
        log("   (the default lens already saw over it: no block to answer)")
      end
      check(math.abs(yaw) < 2, ("pick %d: the yaw never moved (%.1f)"):format(i, yaw))

      -- and the SHOULDER, whose lens is eighteen degrees lower
      MarioCam.setting:setIndex(3, game)
      MarioCam.cut()
      hold(2)
      local sb0 = pose()
      hold(160)
      local sb1, sp1 = pose()
      local syaw = math.deg(MarioCam.viewYaw())
      shoot(("lift_%d_shoulder"):format(i))
      log(("   SHOULDER: blocked at first %s | settled lift %.1f t %.2f pitch %.1f "
           .. "| blocked now %s | yaw %.1f")
          :format(tostring(sb0), ps.lift, ps.t, sp1, tostring(sb1), syaw))
      if sb0 then
        check(not sb1, ("pick %d: shoulder sees the player once settled"):format(i))
      end
      check(math.abs(syaw) < 2, ("pick %d: shoulder yaw never moved (%.1f)"):format(i, syaw))
    else
      log("   could not park there")
    end
  end

  MarioCam.setting:setIndex(2, game)
  log("")
  if #fails == 0 then log("ALL CHECKS PASSED")
  else
    log("FAILURES (" .. #fails .. "):")
    for _, f in ipairs(fails) do log("  - " .. f) end
  end
  logf:close()
  love.event.quit()
end
