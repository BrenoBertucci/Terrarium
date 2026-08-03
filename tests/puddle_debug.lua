-- Probe: WHERE the puddles are, counted rather than looked at.
--
-- A screenshot answers "can I see them", which is the question -- but when
-- the answer is no it does not say which of the four things went wrong:
-- no cells qualified, no quads were built, no mesh was drawn, or it was all
-- drawn in a colour indistinguishable from the road. This counts each one
-- separately.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/DRAMATIC_SHAPE/tests/puddle_debug.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/puddle_debug.log", "w"))
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
    wait(1); n = n + 1; if n > 900 then log("FAIL: no overworld") return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11; if n > 1500 then break end
  end

  local lib = game.mods.exports.DRAMATIC_SHAPE.lib
  local GroundFX = lib.require("GroundFX")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Pipelines = require("src.render.Pipelines")

  GroundFX.setting:sync("on")
  DayNight.setting:sync("day")
  Pipelines.setLevel("voxel", 5)
  Weather.setting:sync("rain")
  GroundFX.SOAK = 3
  game.overworld:setMap("VIRIDIAN_CITY", 4, 16, "down")
  wait(600)

  local map = game.overworld.map
  local p = game.overworld.player
  log(("map %s  player %d,%d  wet=%.2f  step=%d  draws=%d"):format(
    map.id, p.cellX, p.cellY, GroundFX.wetness(),
    GroundFX.step((GroundFX.wetness() - GroundFX.PUDDLE_FROM)
                  / (1 - GroundFX.PUDDLE_FROM)), GroundFX.lastDraws))

  -- what the cells around the player actually are
  local walk, grass, water, warp, heights = 0, 0, 0, 0, {}
  for dy = -8, 8 do
    for dx = -8, 8 do
      local cx, cy = p.cellX + dx, p.cellY + dy
      if map:inBounds(cx, cy) then
        if map:isWalkableCell(cx, cy) then walk = walk + 1 end
        if map:isGrassCell(cx, cy) then grass = grass + 1 end
        if map:isWaterCell(cx, cy) then water = water + 1 end
        if map:warpAtCell(cx, cy) then warp = warp + 1 end
        local h = lib.require("VoxelScene").groundAt(map, cx, cy)
        heights[h] = (heights[h] or 0) + 1
      end
    end
  end
  log(("17x17 around the player: walkable=%d grass=%d water=%d warp=%d")
      :format(walk, grass, water, warp))
  local hs = {}
  for h, c in pairs(heights) do hs[#hs + 1] = ("h%d:%d"):format(h, c) end
  table.sort(hs)
  log("ground heights: " .. table.concat(hs, " "))

  -- and how many quads each chunk actually carries, per LAYER -- a cap that
  -- is never built and a cap that is built and swallowed by a bush look the
  -- same on screen and are two different bugs
  local CH = 16
  local function quads(layer, cx, cy)
    local mesh = GroundFX.chunkFor(map, layer, cx, cy)
    return (mesh and mesh.getVertexCount and mesh:getVertexCount() or 0) / 4
  end
  for cy = math.floor((p.cellY - 11) / CH), math.floor((p.cellY + 11) / CH) do
    for cx = math.floor((p.cellX - 11) / CH), math.floor((p.cellX + 11) / CH) do
      log(("chunk %d,%d  puddle=%d/%d/%d  drift3=%d  cap=%d/%d/%d"):format(
        cx, cy,
        quads("puddle1", cx, cy), quads("puddle2", cx, cy),
        quads("puddle3", cx, cy), quads("drift3", cx, cy),
        quads("cap1", cx, cy), quads("cap2", cx, cy), quads("cap3", cx, cy)))
    end
  end

  -- what the cells that WEAR a cap actually look like: how many there are and
  -- how tall the profile says they stand, which is where the cap is put
  local caps, capH = 0, {}
  for dy = -10, 10 do
    for dx = -10, 10 do
      local cx, cy = p.cellX + dx, p.cellY + dy
      if map:inBounds(cx, cy) and not map:isWalkableCell(cx, cy)
         and not map:isWaterCell(cx, cy) then
        local h = lib.require("VoxelScene").groundAt(map, cx, cy)
        if h > 0 then
          caps = caps + 1
          capH[h] = (capH[h] or 0) + 1
        end
      end
    end
  end
  local hs = {}
  for h, c in pairs(capH) do hs[#hs + 1] = ("h%d:%d"):format(h, c) end
  table.sort(hs)
  log(("cap cells within 10: %d -- heights %s; cap floats at +%.1f"):format(
    caps, table.concat(hs, " "), GroundFX.CAP_LIFT))

  log(("colour: tone=%.2f alpha=%.2f -> rgba %s"):format(
    GroundFX.PUDDLE_TONE, GroundFX.PUDDLE_ALPHA,
    table.concat({ GroundFX.debugColour() }, ",")))
  log(("size step3 = %.1f px on a 16 px cell"):format(GroundFX.PUDDLE_SIZE[3]))

  -- WHICH cells, and how far apart -- the two numbers the look depends on
  local cells = GroundFX.puddleCells(map, p.cellX - 12, p.cellY - 12, 24)
  local list = {}
  for _, c in ipairs(cells) do list[#list + 1] = c[1] .. "," .. c[2] end
  log(("%d pools in a 24x24 block: %s"):format(#cells, table.concat(list, " ")))
  if #cells > 1 then
    local near = 1e9
    for i = 1, #cells do
      for j = i + 1, #cells do
        local dx = cells[i][1] - cells[j][1]
        local dy = cells[i][2] - cells[j][2]
        local d = math.sqrt(dx * dx + dy * dy)
        if d < near then near = d end
      end
    end
    log(("closest pair: %.1f cells apart; one pool per %.0f cells of block")
        :format(near, 24 * 24 / #cells))
  end

  -- and a shot standing right next to one, because a 75-degree camera across
  -- a plaza makes anything the size of a cell into a smudge
  if cells[1] then
    local cx, cy = cells[1][1], cells[1][2]
    for _, d in ipairs({ { 0, 2 }, { 0, -2 }, { 2, 0 }, { -2, 0 } }) do
      if map:isWalkableCell(cx + d[1], cy + d[2]) then
        game.overworld:setMap(map.id, cx + d[1], cy + d[2], "up")
        break
      end
    end
    wait(240)
    log(("stood at %d,%d looking at the pool on %d,%d"):format(
      p.cellX, p.cellY, cx, cy))
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/60_pool_closeup.png", "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
    wait(5)
  end

  log("done")
  logf:close()
  love.event.quit()
end
