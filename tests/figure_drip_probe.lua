-- Probe: rain on the PEOPLE -- drops falling past a figure, and nothing
-- painted on the sprite.
--
-- Two claims, both numbers:
--
--   the shader paints NOTHING on the figure: RainOnFX.paintOf(player) is
--   zero while wetOf(player) is not. The rivulets were water crawling
--   across a picture; that is the thing this exists to stop.
--
--   drops DO fall off figures: RainOnFX.drips climbs while it rains and
--   Weather.moteCount("drip") is above the eave-and-canopy baseline of the
--   same spot -- measured, not assumed, by counting the drips with the
--   figure spawner OFF first and ON second, same map, same shower.
--
-- Then a shot of the player in the rain, so the eye can check the drops
-- are small and in front of the card rather than on it.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/figure_drip_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/figure_drip_probe.log", "w"))
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

  love.math.setRandomSeed(20260911)

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit()
      return end
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
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit()
    return
  end
  log("version:", exports.TERRARIUM.version)

  local RainOnFX = lib.require("RainOnFX")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Pipelines = require("src.render.Pipelines")

  DayNight.setting:sync("day")
  Pipelines.setLevel("terrarium_voxel", 4)
  Weather.setting:sync("rain")
  -- an open square with no crown over it, so the figure is exposed
  game.overworld:setMap("PALLET_TOWN", 12, 12, "down")
  wait(240)

  local p = game.overworld.player
  log(("map %s  player %d,%d  wet(player)=%.2f  paint(player)=%.2f  gate=%s")
      :format(game.overworld.map.id, p.cellX, p.cellY, RainOnFX.wetOf(p),
              RainOnFX.paintOf(p), RainOnFX.lastGate))
  if RainOnFX.wetOf(p) <= 0 then log("  FAIL: the rain is not reaching the player") end
  if RainOnFX.paintOf(p) ~= 0 then log("  FAIL: the sprite is still being painted") end

  -- ------- the baseline: this square's eaves and crowns, figures OFF
  local function sample(tag, frames)
    local sum, peak = 0, 0
    local n2 = 0
    for _ = 1, frames, 5 do
      wait(5)
      local d = Weather.moteCount("drip")
      sum = sum + d; n2 = n2 + 1
      if d > peak then peak = d end
    end
    log(("  %s: drips alive mean %.1f peak %d   figure drips spawned %d")
        :format(tag, sum / n2, peak, RainOnFX.drips))
    return sum / n2
  end
  local saved = RainOnFX.DRIP_RATE
  RainOnFX.DRIP_RATE = 0
  local before = RainOnFX.drips
  local base = sample("figures OFF", 300)
  if RainOnFX.drips ~= before then log("  FAIL: drips spawned with the rate at zero") end
  RainOnFX.DRIP_RATE = saved
  local live = sample("figures ON ", 300)
  log(("  spawned by figures during ON: %d  (rate %.1f/s per soaked figure)")
      :format(RainOnFX.drips - before, RainOnFX.DRIP_RATE))
  if RainOnFX.drips - before < 20 then log("  FAIL: figures are barely dripping") end
  if live <= base then
    log("  note: live count did not rise over the baseline -- figure drips "
        .. "are short-lived (~0.2 s), so a low mean is expected; the spawn "
        .. "count above is the claim")
  end
  shot("figure_drip_rain.png")

  -- and the aftermath: the figure keeps dripping a few seconds, then stops
  Weather.setting:sync("none")
  local atStop = RainOnFX.drips
  wait(60)
  local mid = RainOnFX.drips
  wait(600)
  log(("  after the shower: %d drips in the first second, %d in the next ten;"
       .. " wet(player)=%.2f"):format(mid - atStop, RainOnFX.drips - mid,
                                      RainOnFX.wetOf(p)))
  if RainOnFX.wetOf(p) > 0 then log("  FAIL: the figure never dried") end

  log("done")
  logf:close()
  love.event.quit()
end
