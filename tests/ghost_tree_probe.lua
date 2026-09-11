-- Probe: the player's silhouette shows through a TREE.
--
-- The ghost pass draws the player again wherever the world's depth is in
-- front of them. The voxel trees used to be drawn AFTER that pass, so a
-- crown standing between the camera and the player hid them outright --
-- a Mart gave a silhouette, a tree gave nothing. Trees now go down before
-- the pass, and this counts the pixels that prove it.
--
-- Same frame twice, silhouette on and silhouette off (GHOST_ALPHA), on a
-- cell the camera sees through a crown (Viridian (4,16) at the top-down
-- rung, which is where the puddle probe first stumbled on this). The
-- pixels that differ ARE the silhouette; anything else in the frame is
-- identical between the two shots because nothing else changed.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/ghost_tree_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/ghost_tree_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  -- returns the ImageData too, kept for the diff
  local function shot(name)
    local done, keep = false, nil
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      keep = data
      done = true
    end)
    local guard = 0
    while not done and guard < 240 do coroutine.yield(); guard = guard + 1 end
    return keep
  end

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

  local Voxel3D = lib.require("Voxel3D")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Pipelines = require("src.render.Pipelines")

  DayNight.setting:sync("day")
  Weather.setting:sync("none")
  Pipelines.setLevel("terrarium_voxel", 5)

  -- A cell with nothing standing near it: every cell of a 5x5 square
  -- around it walkable, not grass, and on the same ground. Pallet's lab
  -- door cell, the first pick, had the lintel over the player's hat --
  -- which is a real occlusion and a real silhouette, not open ground.
  local function openCell(map)
    local VoxelScene = lib.require("VoxelScene")
    local W, H = map.widthCells or 20, map.heightCells or 18
    for r = 0, 12 do
      for cy = math.max(3, math.floor(H / 2) - r), math.min(H - 4, math.floor(H / 2) + r) do
        for cx = math.max(3, math.floor(W / 2) - r), math.min(W - 4, math.floor(W / 2) + r) do
          local ok = true
          local h0 = VoxelScene.groundAt(map, cx, cy)
          for dy = -2, 2 do
            for dx = -2, 2 do
              local x, y = cx + dx, cy + dy
              if not map:inBounds(x, y) or not map:isWalkableCell(x, y)
                 or map:isGrassCell(x, y)
                 or VoxelScene.groundAt(map, x, y) ~= h0 then
                ok = false
              end
            end
          end
          if ok then return cx, cy end
        end
      end
    end
    return nil
  end

  local function pair(tag, mapId, cx, cy)
    game.overworld:setMap(mapId, cx or 12, cy or 12, "down")
    wait(300)
    if not cx then
      local okc, ox, oy = pcall(openCell, game.overworld.map)
      if not okc then log(tag, "openCell error:", tostring(ox)); ox = nil end
      if ox then
        game.overworld:setMap(mapId, ox, oy, "down")
        log(("  %s: open cell chosen at %d,%d"):format(tag, ox, oy))
      else
        log(tag, "no fully open cell on this map; keeping the spawn")
      end
    end
    -- The player walks on their own for a few hundred frames after a
    -- setMap (see the underpass probe's note): wait by CONDITION -- the
    -- same cell for 45 frames straight -- not by a count.
    local p = game.overworld.player
    game.input:reset()
    do
      local still, lx, ly, guard = 0, p.cellX, p.cellY, 0
      while still < 45 and guard < 1200 do
        coroutine.yield(); guard = guard + 1
        if p.cellX == lx and p.cellY == ly then still = still + 1
        else still, lx, ly = 0, p.cellX, p.cellY end
      end
      if still < 45 then log(tag, "warning: the player never settled") end
    end
    local saved = Voxel3D.GHOST_ALPHA
    Voxel3D.GHOST_ALPHA = saved
    local on = shot(tag .. "_on.png")
    Voxel3D.GHOST_ALPHA = 0
    wait(2)
    local off = shot(tag .. "_off.png")
    Voxel3D.GHOST_ALPHA = saved
    if not (on and off) then log(tag, "FAIL: no capture") return end
    -- Only the player's own patch of screen: the rest of the frame moves
    -- between two captures (wind, birds, walkers) and a whole-frame diff
    -- counted all of it. The card is projected through the scene camera
    -- and scaled from the render canvas to the window.
    local VoxelScene = lib.require("VoxelScene")
    local gh = VoxelScene.groundAt(game.overworld.map, p.cellX, p.cellY)
    local sx, sy = Voxel3D.project(p.px + 8, gh + 8, p.py + 8)
    local cv = Voxel3D.canvas()
    local ww, wh = love.graphics.getDimensions()
    local cw, ch = ww, wh
    if cv then cw, ch = cv:getDimensions() end
    if not sx then log(tag, "FAIL: the player did not project") return end
    sx, sy = sx * ww / cw, sy * wh / ch
    local w, h = on:getWidth(), on:getHeight()
    local R = math.floor(28 * ww / cw + 0.5)
    local x0 = math.max(0, math.floor(sx - R))
    local x1 = math.min(w - 1, math.floor(sx + R))
    local y0 = math.max(0, math.floor(sy - R * 1.4))
    local y1 = math.min(h - 1, math.floor(sy + R * 0.8))
    local darkOn, darkOff, diff = 0, 0, 0
    for y = y0, y1 do
      for x = x0, x1 do
        local r1, g1, b1 = on:getPixel(x, y)
        local r2, g2, b2 = off:getPixel(x, y)
        if r1 + g1 + b1 < 0.40 then darkOn = darkOn + 1 end
        if r2 + g2 + b2 < 0.40 then darkOff = darkOff + 1 end
        local d = math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2)
        if d > 0.08 and r1 + g1 + b1 < r2 + g2 + b2 then diff = diff + 1 end
      end
    end
    log(("%s  map %s  player %d,%d  screen %d,%d  rect %dx%d  near-black on/off: %d/%d  darker-with-ghost: %d")
        :format(tag, game.overworld.map.id, p.cellX, p.cellY, sx, sy,
                x1 - x0 + 1, y1 - y0 + 1, darkOn, darkOff, diff))
    return diff, darkOn - darkOff
  end

  -- behind a crown (the case that used to fail), and behind nothing (must
  -- stay clean: a silhouette over open ground is the bug the ghost pass
  -- was written to avoid)
  -- Judged on the RISE in near-black pixels, not on pixels that merely
  -- differ: a follower walking through the rect between the two captures
  -- differs by hundreds of pixels and darkens nothing.
  local _, d1 = pair("tree", "VIRIDIAN_CITY", 4, 16)
  d1 = d1 or 0
  if d1 < 300 then log("  FAIL: no silhouette through the tree") end
  local _, d2 = pair("open", "VIRIDIAN_CITY", nil, nil)
  d2 = d2 or 0
  -- was the cell the player SETTLED on actually open? If not, this is not
  -- the claim being tested and the number is reported, not judged.
  do
    local m = game.overworld.map
    local p = game.overworld.player
    local VoxelScene = lib.require("VoxelScene")
    local h0 = VoxelScene.groundAt(m, p.cellX, p.cellY)
    local open = true
    for dy = -2, 2 do
      for dx = -2, 2 do
        local x, y = p.cellX + dx, p.cellY + dy
        if not m:inBounds(x, y) or not m:isWalkableCell(x, y)
           or m:isGrassCell(x, y) or VoxelScene.groundAt(m, x, y) ~= h0 then
          open = false
        end
      end
    end
    log(("  settled on %d,%d  open 5x5: %s"):format(p.cellX, p.cellY,
        tostring(open)))
    if open and d2 > 150 then log("  FAIL: a silhouette on open ground") end
    if not open then log("  (not judged: the cell is not open ground)") end
  end

  log("done")
  logf:close()
  love.event.quit()
end
