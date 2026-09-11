-- Probe: the puddle FIELD (lib/PuddleFX.lua) -- built, drawn, and kept off
-- the lake.
--
-- Three claims, each as a number rather than a picture, and then the
-- pictures:
--
--   the SHADER BUILDS on this driver, and which precision rung it took.
--   A field that falls back to the decals is not a failure of the mod but
--   it is a different picture, and the log has to say which one it is.
--
--   NOT ONE TEXEL of any field lies over a water cell or a cell that
--   touches one. This is the bug the rewrite exists for ("puddles on the
--   lake"), and it is checked on the lake at Route 25 by reading every
--   baked chunk's mesh back: every quad's cell is tested against the map.
--
--   the pools GROW rather than pop. The waterline is stepped through
--   twenty levels and the count of cells holding water is logged at each:
--   a monotone sequence with no jump larger than a handful of cells is a
--   pool spreading, a sequence with three plateaus is the old decals.
--
-- Then a street in the rain at four wetnesses and once in the aftermath,
-- and the lake once, wet, so the eye can check what the numbers claim.
-- Screenshots wait for the capture callback rather than a count of yields
-- (see the note in tests/ambient_occlusion_probe.lua).
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/puddle_field_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/puddle_field_probe.log", "w"))
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
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local WaterMap = lib.require("WaterMap")
  local Voxel3D = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")

  -- ------- 1. the shader
  log("")
  log("shader available:", PuddleFX.available(), " highp line took:",
      PuddleFX.highp(), " error:", tostring(PuddleFX.compileError))
  log("GroundFX.usingField:", GroundFX.usingField(),
      " (usingArt puddle:", GroundFX.usingArt("puddle"), ")")
  if not PuddleFX.available() then log("  FAIL: the field shader did not build") end

  GroundFX.setting:sync("on")
  DayNight.setting:sync("day")
  Pipelines.setLevel("terrarium_voxel", 5)
  Weather.setting:sync("rain")
  GroundFX.SOAK = 4        -- a shower that soaks in seconds, for the probe

  -- ------- 2. the lake: nothing over water
  --
  -- Route 25 (37,12) is the lake that frames (see the water-look probe).
  game.overworld:setMap("ROUTE_25", 37, 12, "down")
  wait(300)
  do
    local map = game.overworld.map
    local p = game.overworld.player
    log("")
    log(("lake map %s  player %d,%d  wet=%.2f"):format(map.id, p.cellX,
        p.cellY, GroundFX.wetness()))
    -- bake every chunk within reach and read every quad's cell back
    local bad, quads, chunksBaked, chunksEmpty = 0, 0, 0, 0
    local water = 0
    local c0x = math.floor((p.cellX - 16) / 16)
    local c1x = math.floor((p.cellX + 16) / 16)
    local c0y = math.floor((p.cellY - 16) / 16)
    local c1y = math.floor((p.cellY + 16) / 16)
    for cy = c0y, c1y do
      for cx = c0x, c1x do
        local f = PuddleFX.fieldFor(map, cx, cy)
        if f then
          chunksBaked = chunksBaked + 1
          quads = quads + f.quads
          -- the cells the mesh covers: read the vertex positions back
          local okc, count = pcall(f.mesh.getVertexCount, f.mesh)
          if okc then
            for i = 1, count, 4 do
              local okv, x, _, z = pcall(f.mesh.getVertex, f.mesh, i)
              if okv then
                local ccx, ccy = math.floor(x / 16), math.floor(z / 16)
                if WaterMap.surfaceCell(map, ccx, ccy) or map:isWaterCell(ccx, ccy) then
                  bad = bad + 1
                else
                  for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                    if map:inBounds(ccx + d[1], ccy + d[2])
                       and WaterMap.surfaceCell(map, ccx + d[1], ccy + d[2]) then
                      bad = bad + 1
                      break
                    end
                  end
                end
              end
            end
          end
        else
          chunksEmpty = chunksEmpty + 1
        end
      end
    end
    for dy = -16, 16 do
      for dx = -16, 16 do
        if map:inBounds(p.cellX + dx, p.cellY + dy)
           and WaterMap.surfaceCell(map, p.cellX + dx, p.cellY + dy) then
          water = water + 1
        end
      end
    end
    log(("  water cells in 33x33: %d   chunks baked: %d  empty: %d  quads: %d")
        :format(water, chunksBaked, chunksEmpty, quads))
    log(("  quads on or beside water: %d  %s"):format(bad,
        bad == 0 and "PASS" or "FAIL"))
    log(("  last bake: %.2f ms"):format(PuddleFX.lastBakeMs))
    wait(400)
    log(("  wet now %.2f  draws %d  stamps %d"):format(GroundFX.wetness(),
        PuddleFX.lastDraws, PuddleFX.lastStamps))
    shot("lake_wet.png")
  end

  -- ------- 3. the street: growth, and the pictures
  --
  -- The spot is CHOSEN rather than written down: the cell of the town
  -- with the most pools in the window the camera will show (it looks
  -- north over the player, so the window is ahead), with open ground
  -- behind so no crown stands between the camera and the street.
  Weather.setting:sync("none")
  game.overworld:setMap("VIRIDIAN_CITY", 4, 16, "down")
  wait(200)
  do
    local m = game.overworld.map
    local best, bx, by = -1, 4, 16
    local saved = PuddleFX.level
    PuddleFX.level = 1
    for cy = 6, (m.heightCells or 36) - 8, 2 do
      for cx = 6, (m.widthCells or 40) - 6, 2 do
        local ok = m:isWalkableCell(cx, cy) and not m:isGrassCell(cx, cy)
        -- open ground behind (the camera) and AHEAD (the window): a fence
        -- or a hedge between the two hides exactly what this is for
        for k = 1, 3 do
          if ok and not m:isWalkableCell(cx, cy + k) then ok = false end
        end
        for k = 1, 5 do
          for dx = -1, 1 do
            if ok and not m:isWalkableCell(cx + dx, cy - k) then ok = false end
          end
        end
        if ok then
          local n = #PuddleFX.poolCells(m, cx - 6, cy - 8, 13)
          if n > best then best, bx, by = n, cx, cy end
        end
      end
    end
    PuddleFX.level = saved
    log(("  spot: (%d,%d) with %d pool cells in its window"):format(bx, by, best))
    game.overworld:setMap("VIRIDIAN_CITY", bx, by, "down")
    wait(200)
  end
  -- dry it out completely first, so the growth is measured from zero
  GroundFX.DRY = 2
  wait(200)
  GroundFX.DRY = 260
  local map = game.overworld.map
  local p = game.overworld.player
  log("")
  log(("street map %s  player %d,%d  wet=%.2f"):format(map.id, p.cellX,
      p.cellY, GroundFX.wetness()))
  shot("street_dry.png")

  -- the waterline stepped by hand: cells holding water at each level
  do
    local seq = {}
    local prevLevel = PuddleFX.level
    for i = 0, 20 do
      PuddleFX.level = i / 20
      local cells = PuddleFX.poolCells(map, p.cellX - 12, p.cellY - 12, 25)
      seq[#seq + 1] = #cells
    end
    PuddleFX.level = prevLevel
    local jumps, maxJump = 0, 0
    for i = 2, #seq do
      local d = seq[i] - seq[i - 1]
      if d < 0 then jumps = jumps + 1 end
      if d > maxJump then maxJump = d end
    end
    log("  cells with water, level 0..1 in twentieths: " .. table.concat(seq, " "))
    log(("  monotone: %s   largest step: %d cells   at full: %d of 625")
        :format(jumps == 0 and "yes" or "NO", maxJump, seq[#seq]))
    local field = PuddleFX.fieldFor(map, math.floor(p.cellX / 16),
                                    math.floor(p.cellY / 16))
    if field then
      log(("  player's chunk: %d seeds, %d quads"):format(field.seeds, field.quads))
    else
      log("  player's chunk: no field (no seed in reach)")
    end
  end

  Weather.setting:sync("rain")
  local marks = { 0.12, 0.30, 0.55, 1.0 }
  local mi = 1
  local guard = 0
  while mi <= #marks and guard < 4000 do
    if GroundFX.wetness() >= marks[mi] then
      log(("  wet %.2f  draws %d  stamps %d  bakes %d  invalidations %d  last bake %.2f ms")
          :format(GroundFX.wetness(), PuddleFX.lastDraws, PuddleFX.lastStamps,
                  PuddleFX.bakes, PuddleFX.invalidations, PuddleFX.lastBakeMs))
      shot(("street_wet_%02d.png"):format(math.floor(marks[mi] * 100)))
      mi = mi + 1
    end
    wait(1); guard = guard + 1
  end

  -- walk through it: rings and prints
  for _ = 1, 24 do game.input.state.up = true; coroutine.yield() end
  game.input.state.up = false
  game.input:reset()
  wait(6)
  shot("street_walked.png")

  -- the aftermath: still water, damp street
  Weather.setting:sync("none")
  wait(240)
  log(("  after: wet %.2f  rain %.2f  draws %d"):format(GroundFX.wetness(),
      lib.require("Water").rain(), PuddleFX.lastDraws))
  shot("street_after.png")

  -- and drying: the count comes DOWN the same way it went up
  GroundFX.DRY = 12
  local seq, inv, bk = {}, {}, {}
  for _ = 1, 24 do
    wait(30)
    if game.overworld.map ~= map then log("  (map changed during drying)") break end
    seq[#seq + 1] = #PuddleFX.poolCells(map, p.cellX - 12, p.cellY - 12, 25)
    inv[#inv + 1] = PuddleFX.invalidations
    bk[#bk + 1] = PuddleFX.bakes
  end
  log("  cells with water while drying, every 30 frames: " .. table.concat(seq, " "))
  log("  invalidations at each sample: " .. table.concat(inv, " "))
  log("  bakes at each sample:         " .. table.concat(bk, " "))
  shot("street_drying.png")

  log("")
  log("done")
  logf:close()
  love.event.quit()
end
