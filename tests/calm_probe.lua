-- Probe: how much does the SM64 camera MOVE while a player walks the way a
-- Pokemon player walks -- short runs, frequent turns -- on each rung.
--
-- The complaint this measures is "the camera changes all the time" and
-- "the sprite sits on a diagonal". Both are numbers: degrees of yaw the
-- view travels through per second of play, how many distinct turns that
-- is, how much of the time the view sits between two cardinals (where a
-- four-facing sprite has no drawing that matches), and how often the
-- D-pad quadrant is remapped under the player. Screenshots at fixed points
-- of the walk so the numbers can be checked against what is on screen.
--
-- Same script for every rung, so a before/after of the camera code is a
-- straight comparison of the summary lines.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/calm_probe.log", "w"))
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
    for _ = 1, 4 do
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

  local function sdeg(a)
    a = a % 65536; if a >= 32768 then a = a - 65536 end
    return a * 360 / 65536
  end

  -- ------- the walk: short runs and frequent turns, like a town
  local LEGS = {
    { "up", 30 }, { "right", 30 }, { "up", 30 }, { "left", 45 },
    { "down", 60 }, { "right", 20 }, { "up", 20 }, { "right", 60 },
    { "down", 30 }, { "left", 30 },
  }
  local SHOT_AT = { [2] = true, [4] = true, [5] = true, [8] = true }

  local function runScript(tag)
    local p = game.overworld.player
    local m = {
      frames = 0, yawTravel = 0, diagFrames = 0, quadChanges = 0,
      distTravel = 0, turns = 0, maxRate = 0, moved = 0,
    }
    local lastYaw, lastQuad, lastDist, turning = nil, nil, nil, false
    local lastPx, lastPz = p.px, p.py
    local function sample(legTag, f)
      local yaw = math.deg(MarioCam.viewYaw())
      local q = MarioCam.quadrant()
      local lk = MarioCam.lakitu
      local dx = lk.curFocus[1] - lk.curPos[1]
      local dy = lk.curFocus[2] - lk.curPos[2]
      local dz = lk.curFocus[3] - lk.curPos[3]
      local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
      m.frames = m.frames + 1
      if lastYaw then
        local d = math.abs(((yaw - lastYaw + 180) % 360) - 180)
        m.yawTravel = m.yawTravel + d
        if d > m.maxRate then m.maxRate = d end
        local isTurning = d > 0.5
        if isTurning and not turning then m.turns = m.turns + 1 end
        turning = isTurning
        m.distTravel = m.distTravel + math.abs(dist - lastDist)
        if q ~= lastQuad then m.quadChanges = m.quadChanges + 1 end
      end
      local toCardinal = math.abs(((yaw + 45) % 90) - 45)
      if toCardinal > 15 then m.diagFrames = m.diagFrames + 1 end
      m.moved = m.moved + math.abs(p.px - lastPx) + math.abs(p.py - lastPz)
      lastPx, lastPz = p.px, p.py
      lastYaw, lastQuad, lastDist = yaw, q, dist
      if f and f % 10 == 0 then
        local okP, pres = pcall(MarioCam.presentYaw)
        local av = MarioCam.avoidState and MarioCam.avoidState.offset or 0
        log(("    %s f%03d cell(%d,%d) face=%-5s yaw=%7.1f card=%5.1f quad=%d "
             .. "dist=%5.1f mode=%s avoid=%5.1f present=%5.1f")
            :format(legTag, f, math.floor((p.px + 8) / 16),
                    math.floor((p.py + 8) / 16), tostring(p.facing), yaw,
                    toCardinal, q, dist, tostring(MarioCam.cam.mode), sdeg(av),
                    okP and math.deg(pres or 0) or 0))
      end
    end

    sample("start", 0)
    for i, leg in ipairs(LEGS) do
      local dir, frames = leg[1], leg[2]
      local legTag = ("L%d:%s"):format(i, dir)
      for f = 1, frames do
        game.input.pressQueue[#game.input.pressQueue + 1] = dir
        DayNight.clock = CLOCK
        coroutine.yield()
        sample(legTag, f)
        if SHOT_AT[i] and f == math.floor(frames * 0.6) then
          shoot(("calm_%s_leg%d_walk"):format(tag, i))
        end
      end
      releaseDirs()
      for f = 1, 25 do
        hold(1)
        sample(legTag .. "+rest", frames + f)
      end
      log(("  leg %2d %-5s end: cell(%d,%d) yaw %7.1f quad %d dist %5.1f")
          :format(i, dir, math.floor((p.px + 8) / 16),
                  math.floor((p.py + 8) / 16), math.deg(MarioCam.viewYaw()),
                  MarioCam.quadrant(), lastDist or 0))
      if SHOT_AT[i] then shoot(("calm_%s_leg%d_rest"):format(tag, i)) end
    end
    local secs = m.frames / 60
    log(("SUMMARY %s: %d frames (%.1fs), player moved %.0f px | yaw travel "
         .. "%.0f deg (%.1f deg/s), %d turns, max %.2f deg/frame | diagonal "
         .. "%.0f%% of frames | quadrant remaps %d | eye distance travel %.0f px")
        :format(tag, m.frames, secs, m.moved, m.yawTravel, m.yawTravel / secs,
                m.turns, m.maxRate, 100 * m.diagFrames / m.frames,
                m.quadChanges, m.distTravel))
    return m
  end

  local MAP, CX, CY = "CELADON_CITY", 25, 30

  for _, rung in ipairs({ { 2, "on" }, { 3, "shoulder" } }) do
    MarioCam.setting:setIndex(rung[1], game)
    log(("== rung %s (index %d) -> %s"):format(rung[2], rung[1],
                                                tostring(MarioCam.rung())))
    local parked = parkAt(MAP, CX, CY, "up", 200)
    log("  parked: " .. tostring(parked))
    if parked then
      MarioCam.recenter()
      hold(120)
      shoot("calm_" .. rung[2] .. "_idle")
      runScript(rung[2])
    end
  end

  MarioCam.setting:setIndex(2, game)
  logf:close()
  love.event.quit()
end
