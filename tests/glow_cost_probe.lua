-- Probe: what the GLOW row costs a frame, measured the way this repo
-- measures (see tests/mali_cost_probe.lua and the notes it carries).
--
--   * vsync OFF, or every condition reads the panel's refresh.
--   * A/B as a palindrome (OFF ON ON OFF OFF ON): the first and last phases
--     of one run differ on their own, and a straight OFF-then-ON charges the
--     second phase for the wear of the first.
--   * the median AND the tail: this machine hurts in its p95/p99, not in its
--     p50, so a change that only moves the tail is still a change.
--   * a warm-up per phase: toggling the row compiles the other shader
--     variant the first time, and a compile is not a frame cost.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/glow_cost_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/glow_cost.log", "w"))
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
  game.input:reset()

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end
  log("version:", exports.TERRARIUM.version)

  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local ChunkMesher = lib.require("ChunkMesher")
  local Glow = lib.require("Glow")
  local Follower = lib.require("Follower")
  local Pipelines = require("src.render.Pipelines")
  Weather.setting:sync("off")
  Pipelines.setLevel("terrarium_voxel", 4)
  Follower.setting:sync(true)
  love.window.setVSync(0)

  local save = game.save
  local party = save.party or {}
  local oldLead = party[1] and party[1].species
  if party[1] then party[1].species = "CHARMANDER" end
  save.pikachuInBall = true

  local ow = game.overworld
  local function settle()
    local quiet, guard = 0, 0
    while quiet < 45 and guard < 2400 do
      coroutine.yield(); guard = guard + 1
      if ChunkMesher.pending() == 0 then quiet = quiet + 1 else quiet = 0 end
    end
    game.input:reset()
  end

  local function stats(dts)
    table.sort(dts)
    local function q(p) return dts[math.max(1, math.min(#dts, math.floor(#dts * p + 0.5)))] end
    local sum = 0
    for _, v in ipairs(dts) do sum = sum + v end
    return q(0.5), q(0.95), q(0.99), sum / #dts, dts[#dts]
  end

  local N = 300
  -- a condition: the row, and the probe knob (nil, "skip", "dark")
  local function phase(on, knob)
    Glow.setting:sync(on)
    Glow.debug = knob
    wait(90)
    game.input:reset()
    local dts = {}
    local prep, rend = 0, 0
    local prev = love.timer.getTime()
    for _ = 1, N do
      coroutine.yield()
      local t = love.timer.getTime()
      dts[#dts + 1] = (t - prev) * 1000
      prev = t
      prep = prep + (Glow.stats.prepMs or 0)
      rend = rend + (Glow.stats.renderMs or 0)
    end
    Glow.debug = nil
    local p50, p95, p99, mean, max = stats(dts)
    return p50, p95, p99, mean, max, prep / N, rend / N
  end

  local CONDS = {
    off = { false, nil }, on = { true, nil },
    skip = { true, "skip" }, dark = { true, "dark" },
  }
  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      done = true
    end)
    local guard = 0
    while not done and guard < 240 do coroutine.yield(); guard = guard + 1 end
    return done
  end

  local function run(tag, mapId, cx, cy, tod, order)
    DayNight.setting:sync(tod)
    save.flashLit = nil
    ow:setMap(mapId, cx, cy, "down")
    settle()
    -- what is on screen is part of the measurement: a run that fell back to
    -- the flat game (or drew nothing at all) is fast and means nothing
    log(tag, "shot", tostring(shot("cost_" .. tag .. ".png")),
        "voxelLevel", tostring(Pipelines.level("terrarium_voxel")),
        "top", tostring(game.stack:top() == ow))
    local acc = {}
    for i, name in ipairs(order) do
      local c = CONDS[name]
      local p50, p95, p99, mean, max, prep, rend = phase(c[1], c[2])
      log(("%s phase%d %s p50=%.2f p95=%.2f p99=%.2f mean=%.2f max=%.2f "
           .. "prep=%.3f render=%.3f sources=%d eligible=%s")
          :format(tag, i, name, p50, p95, p99, mean, max, prep, rend,
                  Glow.stats.sources or 0,
                  tostring(Pipelines.eligible("terrarium_voxel"))))
      acc[name] = acc[name] or {}
      local a = acc[name]
      a[#a + 1] = { p50, p95, p99, mean }
    end
    for name, rows in pairs(acc) do
      local s = { 0, 0, 0, 0 }
      for _, r in ipairs(rows) do for k = 1, 4 do s[k] = s[k] + r[k] / #rows end end
      log(("%s AVG %s p50=%.2f p95=%.2f p99=%.2f mean=%.2f")
          :format(tag, name, s[1], s[2], s[3], s[4]))
    end
  end

  local ORDER = { "off", "on", "skip", "dark", "dark", "skip", "on", "off" }
  run("rocktunnel-dark", "ROCK_TUNNEL_1F", 20, 21, "day", ORDER)
  run("viridian-night", "VIRIDIAN_CITY", 20, 24, "night", ORDER)

  do
    local okR, Runtime = pcall(require, "src.mods.Runtime")
    for i, e in ipairs((okR and Runtime.errors) or {}) do
      log("runtime error", i, e)
    end
  end
  if party[1] then party[1].species = oldLead end
  save.pikachuInBall = nil
  Glow.setting:sync(true)
  love.window.setVSync(1)
  log("DONE")
  logf:close()
  love.event.quit()
end
