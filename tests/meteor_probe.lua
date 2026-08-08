-- Probe: the meteor, looked at.
--
-- It crosses for about nine tenths of a second once every seventeen, at
-- deep night only, which is a thing that cannot be caught by waiting and
-- pressing the shutter. So the crossing rate is turned right up for the
-- length of the probe and put back afterwards -- the painter is stateless
-- and answers entirely from the clock (Sky.paintMeteor), so changing how
-- often it fires changes nothing else about it.
--
-- Three shots across one flight: early, middle and late. What they have to
-- show is a STREAK -- a continuous tapered line with a bright head -- and
-- not the row of identical white squares this used to draw.
--
--   POKEPORT_VERSION=yellow \
--   DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/meteor_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/meteor_probe.log", "w"))
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
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      -- brightness of the TOP THIRD only: that is where the sky is, and a
      -- mean over the whole frame is mostly ground
      local okd, w, h = pcall(function()
        return data:getWidth(), data:getHeight()
      end)
      if not okd then return end
      local sum, n, hi = 0, 0, 0
      for gy = 0, 23 do
        for gx = 0, 31 do
          local px = math.floor(gx * (w - 1) / 31)
          local py = math.floor(gy * (h / 3 - 1) / 23)
          local okp, r, g, b = pcall(data.getPixel, data, px, py)
          if okp then
            local l = (r + g + b) / 3
            sum, n = sum + l, n + 1
            if l > hi then hi = l end
          end
        end
      end
      if n > 0 then
        log(("shot %s  sky mean=%.3f  brightest=%.3f"):format(
              name, sum / n, hi))
      end
    end)
    wait(4)
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close()
      love.event.quit() return end
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

  local Sky = lib.require("Sky")
  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local Pipelines = require("src.render.Pipelines")

  Weather.setting:sync("off")
  DayNight.setting:sync("night")
  Pipelines.setLevel("terrarium_voxel", 4)
  -- Outdoors with open sky, and a route rather than a town: fewer lit
  -- windows competing with the thing being looked at.
  game.overworld:setMap("ROUTE_1", 10, 20, "down")
  wait(180)

  log(("tail samples=%d  step=%.3f  every=%.1fs  len=%.3f"):format(
        Sky.METEOR_TAIL, Sky.METEOR_STEP, Sky.METEOR_EVERY, Sky.METEOR_LEN))

  -- Turn the rate up so a crossing is always in progress, and stretch the
  -- crossing so the three shots land at different points of one flight
  -- rather than on three different meteors.
  local realEvery, realLen = Sky.METEOR_EVERY, Sky.METEOR_LEN
  Sky.METEOR_EVERY = 6
  Sky.METEOR_LEN = 0.55          -- ~3.3s of flight, easy to sample across
  wait(30)

  shot("meteor_a_early.png")
  wait(24)
  shot("meteor_b_mid.png")
  wait(24)
  shot("meteor_c_late.png")

  Sky.METEOR_EVERY, Sky.METEOR_LEN = realEvery, realLen
  log("rate restored: every=" .. tostring(Sky.METEOR_EVERY))

  wait(10)
  logf:close()
  love.event.quit()
end
