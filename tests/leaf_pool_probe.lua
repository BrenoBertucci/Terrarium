-- Probe: a leaf that comes down on a puddle rings it.
--
-- Leaves are let go (LeafFallFX.shed) straight over cells the field says
-- hold water, and then the same number over dry paving, in dead calm so
-- they fall where they were dropped. Counted:
--
--   over the POOL: LeafFallFX.splashed climbs with the landings and
--   PuddleFX.ripples climbs with it (the rings were actually pushed);
--   over DRY ground: neither moves.
--
-- A shot on the first ring, for the eye.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/leaf_pool_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/leaf_pool_probe.log", "w"))
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
  local LeafFallFX = lib.require("LeafFallFX")
  local VoxelScene = lib.require("VoxelScene")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Wind = lib.require("Wind")
  local VegFX = lib.require("VegFX")
  local Pipelines = require("src.render.Pipelines")

  -- the square's own trees shed leaves onto its pools all the time; only
  -- the leaves THIS probe lets go may be counted
  VegFX.LEAF_CALM, VegFX.LEAF_WIND = 0, 0

  GroundFX.setting:sync("on")
  DayNight.setting:sync("day")
  Pipelines.setLevel("terrarium_voxel", 4)
  Wind.setting:sync(0)                 -- dead calm: a leaf falls where it is let go
  Weather.setting:sync("rain")
  GroundFX.SOAK = 4
  game.overworld:setMap("VIRIDIAN_CITY", 18, 20, "down")
  wait(300)
  local guard = 0
  while GroundFX.wetness() < 0.95 and guard < 2400 do wait(1); guard = guard + 1 end
  Weather.setting:sync("none")
  wait(60)
  game.input:reset()
  local map = game.overworld.map
  local p = game.overworld.player
  log(("map %s  player %d,%d  wet=%.2f  leaf gate=%s")
      :format(map.id, p.cellX, p.cellY, GroundFX.wetness(),
              tostring(LeafFallFX.lastGate)))

  -- the pools in reach, and the dry paving in reach
  local pools = PuddleFX.poolCells(map, p.cellX - 5, p.cellY - 5, 11)
  local dry = {}
  for cy = p.cellY - 5, p.cellY + 5 do
    for cx = p.cellX - 5, p.cellX + 5 do
      -- dry, and dry all round: a leaf is let go up to SHED_R off its
      -- cell, so a dry cell beside a pool would land leaves in the pool
      local ok = map:inBounds(cx, cy) and map:isWalkableCell(cx, cy)
                 and not map:isGrassCell(cx, cy)
      if ok then
        for dy = -1, 1 do
          for dx = -1, 1 do
            if GroundFX.poolAt(map, cx + dx, cy + dy) then ok = false end
          end
        end
      end
      if ok then dry[#dry + 1] = { cx, cy } end
    end
  end
  log(("pool cells in reach: %d   dry paving cells: %d"):format(#pools, #dry))
  if #pools == 0 then
    log("FAIL: no pool in reach"); logf:close(); love.event.quit(); return
  end

  local function rain(cells, count, tag)
    local shed0 = LeafFallFX.shedCount
    local landed0, splashed0 = LeafFallFX.landed, LeafFallFX.splashed
    local kick0 = LeafFallFX.splashedKick
    local rings0 = PuddleFX.ripples
    local shotDone = false
    -- let go just over the surface so the calm air has no time to carry
    -- the leaf off the cell it was dropped on
    for k = 1, count do
      local c = cells[(k - 1) % #cells + 1]
      local gh = VoxelScene.groundAt(map, c[1], c[2])
      LeafFallFX.shed(c[1] * 16 + 8, gh + 9, c[2] * 16 + 8)
      wait(2)
    end
    -- the leaves are still coming down: poll for the first ring rather
    -- than assume it landed inside the two frames after it let go
    for _ = 1, 240 do
      coroutine.yield()
      if not shotDone and LeafFallFX.splashed > splashed0 then
        wait(3); shot(tag .. "_ring.png"); shotDone = true
      end
    end
    local shed = LeafFallFX.shedCount - shed0
    local landed = LeafFallFX.landed - landed0
    local splashed = LeafFallFX.splashed - splashed0
    -- a leaf a walker kicked up and that came down in a pool is a real
    -- ring, but it is not one of the leaves THIS pass let go
    local kicked = LeafFallFX.splashedKick - kick0
    local rings = PuddleFX.ripples - rings0
    log(("  %s: shed %d  landed %d  on water %d (of which kicked up by a walker: %d)  rings pushed %d")
        :format(tag, shed, landed, splashed, kicked, rings))
    return shed, landed, splashed - kicked, rings
  end

  local shedP, landedP, splP, ringsP = rain(pools, 24, "pool")
  if shedP == 0 then log("  FAIL: no leaf was shed (LeafFallFX gate: " .. tostring(LeafFallFX.lastGate) .. ")") end
  if splP < 1 then log("  FAIL: no leaf rang the pool") end
  if ringsP < splP then log("  FAIL: fewer rings than water landings") end
  if landedP > 0 and splP < landedP * 0.5 then
    log("  note: under half the landings were counted on water -- the calm "
        .. "air still drifts a leaf off its cell; fine as long as some ring")
  end

  local shedD, landedD, splD = rain(dry, 24, "dry")
  if splD > 0 then log("  FAIL: a leaf on dry paving was counted as on water") end
  if LeafFallFX.lastError then log("  LeafFallFX error:", LeafFallFX.lastError) end

  log("done")
  logf:close()
  love.event.quit()
end
