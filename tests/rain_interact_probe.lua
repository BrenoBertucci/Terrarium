-- Probe: does the rain actually TOUCH the world, and can you SEE it?
--
-- The complaint this probe exists to settle: "the rain is pretty but
-- nothing interacts -- roofs don't drip, the ground doesn't react, the
-- water doesn't react." Every one of those interactions is implemented
-- (splashFromHit, spawnDrip, spawnEjecta, impactMix), so the claim is
-- either a runtime failure (a seam the engine moved, a pcall eating an
-- error, a gate stuck shut) or a visibility failure (it runs and cannot
-- be seen). Counting separates the two; the screenshots settle the rest.
--
-- What is counted, over a pinned downpour in a town with water:
--
--   SHAFTS ALIVE      zero means world-space rain is dead and the "rain"
--                     on screen is only the screen-space mist -- which
--                     would explain "nothing interacts" completely.
--
--   IMPACTS BY SURFACE  water / pool / roof / grass / stone. A missing
--                     key is that surface's detection broken (e.g. roofs
--                     never detected => no roof splash => no eave drips).
--
--   DRIPS ALIVE       the eave drips. Spawned at 38% per roof hit, so
--                     roof hits without drips is spawnDrip's early-out.
--
--   EJECTA ALIVE      the crowns off water hits.
--
--   POOL HOOK         Weather.poolAt wired by GroundFX, or nil.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/rain_interact_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/rain_interact.log", "w"))
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
    end)
    wait(3)
  end

  love.math.setRandomSeed(20260819)

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

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit()
    return
  end
  log("version:", exports.TERRARIUM.version)

  local Weather = lib.require("Weather")
  local GroundFX = lib.require("GroundFX")
  local Quality = lib.require("Quality")
  local DayNight = lib.require("DayNight")
  local Pipelines = require("src.render.Pipelines")

  GroundFX.setting:sync("on")
  DayNight.setting:sync("day")
  Weather.setting:sync("rain")
  Pipelines.setLevel("terrarium_voxel", 4)

  -- Pallet Town: sea at the south edge, two houses and the lab -- water,
  -- roofs, grass and paving all inside one shaft reach.
  game.overworld:setMap("PALLET_TOWN", 12, 12, "down")
  wait(240)

  local ow = game.overworld
  local map = ow.map
  log("map:", map.id, " player:", ow.player.cellX, ow.player.cellY)
  log("quality.scale:", (pcall(Quality.scale)) and select(2, pcall(Quality.scale)) or "?")

  -- what the reach actually offers: water cells and lids near the player
  do
    local p = ow.player
    local water, lids, walk = 0, 0, 0
    local VoxelScene = lib.require("VoxelScene")
    for dx = -9, 9 do
      for dy = -9, 9 do
        local cx, cy = p.cellX + dx, p.cellY + dy
        if map:inBounds(cx, cy) then
          if map:isWaterCell(cx, cy) then water = water + 1 end
          local okh, h = pcall(VoxelScene.groundAt, map, cx, cy)
          local gh = (okh and h) or 0
          if gh > 6 and not map:isWalkableCell(cx, cy) then
            lids = lids + 1
          elseif map:isWalkableCell(cx, cy) then
            walk = walk + 1
          end
        end
      end
    end
    log(("reach offers  water:%d  lids(roofs):%d  walkable:%d")
        :format(water, lids, walk))
  end

  -- skip the 20s build ramp: this probe measures the downpour, not the ramp
  Weather.pin("rain", 0.9)
  wait(120)

  log("visible:", Weather.visible())
  log("poolAt hook:", Weather.poolAt and "wired" or "NIL")
  log("refract:", Weather.refractState())

  -- ------- the count, sixty samples over ~20 seconds
  local mix = {}
  local peak = { shaft = 0, splash = 0, eject = 0, drip = 0 }
  local sum = { shaft = 0, splash = 0, eject = 0, drip = 0 }
  local samples = 60
  for i = 1, samples do
    wait(20)
    local sh = Weather.shaftDump()
    local sp = Weather.moteCount("splash")
    local ej = Weather.moteCount("eject")
    local dr = Weather.moteCount("drip")
    sum.shaft, sum.splash = sum.shaft + sh, sum.splash + sp
    sum.eject, sum.drip = sum.eject + ej, sum.drip + dr
    if sh > peak.shaft then peak.shaft = sh end
    if sp > peak.splash then peak.splash = sp end
    if ej > peak.eject then peak.eject = ej end
    if dr > peak.drip then peak.drip = dr end
    local m = Weather.impactMix()
    for k, v in pairs(m) do mix[k] = (mix[k] or 0) + v end
    if i == 10 then shot("rain_interact_a.png") end
    if i == 30 then shot("rain_interact_b.png") end
    if i == 50 then shot("rain_interact_c.png") end
  end
  log(("mean  shafts:%.0f  splashes:%.0f  ejecta:%.0f  drips:%.1f")
      :format(sum.shaft / samples, sum.splash / samples,
              sum.eject / samples, sum.drip / samples))
  log(("peak  shafts:%d  splashes:%d  ejecta:%d  drips:%d")
      :format(peak.shaft, peak.splash, peak.eject, peak.drip))
  local keys = {}
  for k in pairs(mix) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    log(("impact surf %-6s %d"):format(k, mix[k]))
  end
  if next(mix) == nil then log("impact surf NONE -- no splash ever lived") end

  -- ------- and the ground under the rain: puddles forming?
  do
    local p = ow.player
    local pools = 0
    if Weather.poolAt then
      for dx = -7, 7 do
        for dy = -7, 7 do
          local okp, holds = pcall(Weather.poolAt, map, p.cellX + dx, p.cellY + dy)
          if okp and holds then pools = pools + 1 end
        end
      end
    end
    log("pool cells in reach after downpour:", pools)
  end

  -- ------- and the minutes after: the half that used to draw nothing
  --
  -- End the shower outright and arm the after-rain window. The eaves and
  -- the wood should keep letting go -- and, since the draw no longer
  -- early-outs on a clear sky, the drips should be IN the screenshot,
  -- not merely in the mote list.
  Weather.pin(nil, 0)
  Weather.armAfterRain(180)
  wait(90)
  local dripSum, dripPeak, groundSp = 0, 0, 0
  for i = 1, 30 do
    wait(15)
    local dr = Weather.moteCount("drip")
    dripSum = dripSum + dr
    if dr > dripPeak then dripPeak = dr end
    groundSp = groundSp + Weather.moteCount("splash")
    if i == 10 then shot("rain_interact_after.png") end
  end
  log(("after-rain  drips mean:%.1f peak:%d  landing-splashes sum:%d")
      :format(dripSum / 30, dripPeak, groundSp))

  log("done")
  logf:close()
  love.event.quit()
end
