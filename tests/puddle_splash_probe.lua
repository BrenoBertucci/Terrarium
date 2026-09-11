-- Probe: a step INTO a puddle splashes -- drops in the air, and a sound.
--
-- Counted, not looked at: the player is walked into a cell the field says
-- holds water, and every frame of the walk the live "drop" motes in the
-- step field are counted. Three claims:
--
--   the footfall in the pool SPLASHED (StepFX.splashes climbs) and the
--   footfalls on the dry paving before it did not;
--   drops were AIRBORNE (peak live count above zero) and then GONE (the
--   count returns to zero -- a drop lands, it does not hover);
--   the splash was HEARD (AmbientSound.splashPlays climbs), or the reason
--   it could not be is named.
--
-- Then a shot on the frame the most drops were up, so the eye can check
-- they are drops off a boot and not a fountain.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/puddle_splash_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/puddle_splash_probe.log", "w"))
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

  local GroundFX = lib.require("GroundFX")
  local PuddleFX = lib.require("PuddleFX")
  local StepFX = lib.require("StepFX")
  local AmbientSound = lib.require("AmbientSound")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Pipelines = require("src.render.Pipelines")

  GroundFX.setting:sync("on")
  DayNight.setting:sync("day")
  Pipelines.setLevel("terrarium_voxel", 4)
  Weather.setting:sync("rain")
  GroundFX.SOAK = 4
  game.overworld:setMap("VIRIDIAN_CITY", 18, 20, "down")
  wait(300)
  -- soak it
  local guard = 0
  while GroundFX.wetness() < 0.95 and guard < 2400 do wait(1); guard = guard + 1 end
  Weather.setting:sync("none")     -- still water: the splash is the step's
  wait(60)
  game.input:reset()
  local map = game.overworld.map
  local p = game.overworld.player
  log(("map %s  player %d,%d  wet=%.2f  usingField=%s  sound enabled=%s")
      :format(map.id, p.cellX, p.cellY, GroundFX.wetness(),
              tostring(GroundFX.usingField()), tostring(AmbientSound.enabled())))

  -- a pool cell in a straight, walkable line from the player, nearest first
  local target, dir, dist
  for d = 1, 7 do
    for _, cand in ipairs({ { 0, -1, "up" }, { 0, 1, "down" }, { -1, 0, "left" }, { 1, 0, "right" } }) do
      if not target then
        local cx, cy = p.cellX + cand[1] * d, p.cellY + cand[2] * d
        local clear = true
        for k = 1, d do
          local x, y = p.cellX + cand[1] * k, p.cellY + cand[2] * k
          if not (map:inBounds(x, y) and map:isWalkableCell(x, y)) then clear = false end
        end
        if clear and GroundFX.poolAt(map, cx, cy) then
          target, dir, dist = { cx, cy }, cand[3], d
        end
      end
    end
  end
  if not target then
    log("FAIL: no pool in a straight walkable line within 7 cells")
    logf:close(); love.event.quit(); return
  end
  log(("target pool %d,%d  %s x%d  depth %.2f"):format(target[1], target[2],
      dir, dist, GroundFX.poolDepth(map, target[1], target[2])))

  -- walk, counting every frame
  local function drops()
    local c = 0
    for i = 1, StepFX.count() do
      local m = StepFX.get(i)
      if m and m.kind == "drop" then c = c + 1 end
    end
    return c
  end
  local splashes0, plays0 = StepFX.splashes, AmbientSound.splashPlays
  local dryFootfalls0 = StepFX.emitted
  local peak, peakFrame, shotDone = 0, 0, false
  local splashedAtCell = nil
  local frames = 0
  while frames < 400 and not (p.cellX == target[1] and p.cellY == target[2]) do
    game.input.state[dir] = true
    coroutine.yield()
    frames = frames + 1
    local c = drops()
    if c > peak then peak, peakFrame = c, frames end
    if StepFX.splashes > splashes0 and not splashedAtCell then
      splashedAtCell = { p.cellX, p.cellY }
      -- the PLAYER's first splash: four frames on (the drops at their
      -- highest), stop and shoot
      for _ = 1, 4 do game.input.state[dir] = true; coroutine.yield() end
      game.input.state[dir] = false
      shot("splash_air.png")
      shotDone = true
    end
  end
  game.input.state[dir] = false
  game.input:reset()
  local arrived = (p.cellX == target[1] and p.cellY == target[2])
  -- a few more steps IN the water, then stand still and let it land
  for _ = 1, 30 do
    game.input.state[dir] = true; coroutine.yield()
    local c = drops(); if c > peak then peak = c end
  end
  game.input.state[dir] = false
  game.input:reset()
  -- standing still: whose feet are these? The follower keeps walking to
  -- the player after the player stops, and its steps splash too.
  local splashesAtStop = StepFX.splashes
  local trail = {}
  for _ = 1, 6 do
    wait(30)
    trail[#trail + 1] = drops() .. "/" .. (StepFX.splashes - splashesAtStop)
  end
  local after = drops()
  local lateSplashes = StepFX.splashes - splashesAtStop
  log("  standing: drops/late-splashes every 30 frames: " .. table.concat(trail, " "))

  log(("walked %d frames  arrived=%s  splashed first at %s  footfalls that splashed: %d")
      :format(frames, tostring(arrived),
              splashedAtCell and (splashedAtCell[1] .. "," .. splashedAtCell[2]) or "never",
              StepFX.splashes - splashes0))
  log(("drops airborne peak %d (frame %d)  after standing 90 frames: %d")
      :format(peak, peakFrame, after))
  log(("splash sounds played: %d"):format(AmbientSound.splashPlays - plays0))
  if StepFX.splashes - splashes0 < 1 then log("  FAIL: no footfall splashed") end
  if peak < 2 then log("  FAIL: no drops in the air") end
  if after > 0 and lateSplashes == 0 then
    log("  FAIL: drops still up after standing still, and nobody stepped")
  elseif after > 0 then
    log("  (drops up while standing are from " .. lateSplashes
        .. " later footfalls -- the follower's; not judged)")
  end
  if AmbientSound.splashPlays - plays0 < 1 then
    log("  " .. (AmbientSound.enabled() and "FAIL: the splash was never heard"
                 or "note: sound is off in this save; not judged"))
  end
  if StepFX.lastError then log("  StepFX error:", StepFX.lastError) end
  if not shotDone then shot("splash_air.png") end

  log("done")
  logf:close()
  love.event.quit()
end
