-- Probe: what each CRT set costs, on this machine, at 1080p.
--
-- A whole-frame A/B here has a standard error of about 3 ms (see the memory
-- notes on measuring this mod), which is twice the budget being checked. So
-- the pass is measured AMPLIFIED: CRT.present is run K times per frame and
-- the cost is the frame-time growth over K. The GPU pipelines the repeats
-- like any other work, so this is the pass's throughput cost -- what it
-- takes from a GPU-bound frame -- with the noise divided by K.
--
-- Every condition is measured in a palindrome (OFF, xK, xK, OFF), because
-- the first and the last phase of one run drift apart with no change at all.
-- The 3D scene is photographed under every condition: a cost measured while
-- the diorama silently fell back to 2D is not a measurement.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/crt_cost_probe.lua ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local K = tonumber(os.getenv("DS_K") or "8")
  local FRAMES = tonumber(os.getenv("DS_FRAMES") or "240")
  local logf = assert(io.open(OUT .. "/crt_cost.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local shots = {}
  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      shots[#shots + 1] = { name, data }
      done = true
    end)
    for _ = 1, 90 do
      if done then return end
      coroutine.yield()
    end
    log("WARN: screenshot " .. name .. " never called back")
  end
  local function quit(msg)
    if msg then log(msg) end
    for _, s in ipairs(shots) do
      local f = io.open(OUT .. "/" .. s[1], "wb")
      if f then f:write(s[2]:encode("png"):getString()) f:close() end
    end
    logf:close(); love.event.quit()
  end

  local lib
  for _ = 1, 600 do
    local ex = game.mods and game.mods.exports
    lib = ex and ex.TERRARIUM and ex.TERRARIUM.lib
    if lib and game.stack and game.stack:top() then break end
    coroutine.yield()
  end
  if not lib then return quit("FAIL: TERRARIUM not loaded") end
  local n = 0
  while not (game.overworld and game.stack:top() == game.overworld) do
    tap("a"); wait(10); n = n + 11
    if n > 2500 then return quit("FAIL: never reached free roam") end
  end

  local CRT = lib.require("CRT")
  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local ChunkMesher = lib.require("ChunkMesher")
  local Pipelines = require("src.render.Pipelines")
  pcall(function() DayNight.setting:sync("day") end)
  pcall(function() Weather.setting:sync("off") end)

  local W, H = tonumber(os.getenv("DS_W") or "1920"), tonumber(os.getenv("DS_H") or "1080")
  pcall(love.window.setMode, W, H, { resizable = true, vsync = 1 })
  wait(30)
  local pw, ph = love.graphics.getPixelDimensions()
  log("window", pw, ph, "gpu", select(4, love.graphics.getRendererInfo()))

  Pipelines.setLevel("terrarium_voxel", 4)
  local ow = game.overworld
  pcall(function() ow:setMap(os.getenv("DS_MAP") or "ROUTE_1", 10, 18, "down") end)
  game.input:reset()
  local quiet = 0
  for _ = 1, 1500 do
    if ChunkMesher.pending() == 0 then quiet = quiet + 1 else quiet = 0 end
    if quiet >= 60 then break end
    coroutine.yield()
  end
  wait(60)

  -- the amplifier: CRT.present run k times a frame
  local present = CRT.present
  local k = 1
  CRT.present = function(canvas, ctx)
    local out = canvas
    for _ = 1, k do out = present(canvas, ctx) end
    return out
  end

  local function set(key, isLite, frameOn)
    CRT.setting:sync(key or "off")
    CRT.frameSetting:sync(frameOn and "on" or "off")
    CRT.force(key, isLite, nil)
  end

  -- photograph every condition first (with vsync on: a capture after the
  -- vsync switch has come back black on this machine)
  local CONDS = {
    { "off" }, { "pvm", "pvm" }, { "trinitron", "trinitron" }, { "home", "home" },
    { "rf", "rf" }, { "home+frame", "home", false, true },
    { "trinitron-lite", "trinitron", true },
  }
  for _, c in ipairs(CONDS) do
    set(c[2], c[3], c[4]); k = 1
    wait(20)
    shot("cost_" .. c[1] .. ".png")
  end

  pcall(love.window.setVSync, 0)
  wait(30)

  local function phase(frames)
    local dts = {}
    local stats0 = love.graphics.getStats()
    local t0 = love.timer.getTime()
    local last = t0
    for i = 1, frames do
      coroutine.yield()
      local now = love.timer.getTime()
      dts[i] = (now - last) * 1000
      last = now
    end
    table.sort(dts)
    local sum = 0
    for _, v in ipairs(dts) do sum = sum + v end
    local st = love.graphics.getStats()
    return sum / #dts, dts[math.floor(#dts * 0.5)], dts[math.floor(#dts * 0.95)], st.drawcalls
  end

  local function measure(label, key, isLite, frameOn, kk)
    local r = {}
    local order = { false, true, true, false }
    for i, on in ipairs(order) do
      if on then set(key, isLite, frameOn); k = kk else set(nil); k = 1 end
      wait(30)
      local mean, p50, p95, dc = phase(FRAMES)
      r[i] = { mean = mean, p50 = p50, p95 = p95, dc = dc }
    end
    local off = (r[1].p50 + r[4].p50) / 2
    local on = (r[2].p50 + r[3].p50) / 2
    local offM = (r[1].mean + r[4].mean) / 2
    local onM = (r[2].mean + r[3].mean) / 2
    log(("%-16s x%d  p50 off %.2f / on %.2f ms  -> %.3f ms per pass (mean-based %.3f)  "
         .. "[spread off %.2f, on %.2f]  draws %d/%d  p95 on %.2f"):format(
      label, kk, off, on, (on - off) / kk, (onM - offM) / kk,
      math.abs(r[1].p50 - r[4].p50), math.abs(r[2].p50 - r[3].p50),
      r[1].dc or 0, r[2].dc or 0, (r[2].p95 + r[3].p95) / 2))
  end

  for _, c in ipairs(CONDS) do
    if c[2] then measure(c[1], c[2], c[3], c[4], K) end
  end
  -- and the real thing, once per frame, for the honest whole-frame delta
  for _, c in ipairs(CONDS) do
    if c[2] then measure(c[1] .. " (x1)", c[2], c[3], c[4], 1) end
  end
  CRT.present = present
  set(nil)
  pcall(love.window.setVSync, 1)
  wait(30)
  shot("cost_after.png")
  quit("done")
end
