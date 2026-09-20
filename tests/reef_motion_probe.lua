-- The water garden moves (lib/ReefKit.lua, the reef branch of
-- lib/Voxel3D.lua, the stir lib/WakeFX.lua lays), on Route 12:
--   1. the sheet's corners say which plant they are: every kind reaches the
--      mesh (decoded off S.spriteQuads with the shader's own arithmetic)
--   2. it MOVES: a close camera on the pads, the kelp and the reeds, six
--      frames apart in real time -- and the SAME garden rebuilt rigid
--      (Kit.pack told every voxel is stone), same cameras. The frames are
--      laid side by side and measured by tests/reef_motion_sheet.py; a
--      frame-to-frame change over a wide view is mostly the sheet's own
--      swell and caustics, which move in both, so it is not measured here.
--   3. a swimmer: the stir packet carries a hull and a wake while the player
--      surfs through the pads, and frames through the pass and after it,
--      both ways
-- Run at POKEPORT_SPEED=1: the wake's springs run on the game's clock and
-- the swell on the real one, and at 4x the two disagree by four.
-- Settings are synced in memory, never saved by this probe.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/reef_motion_probe.log", "w"))
  local function log(s) file:write(s, "\n"); file:flush() end
  local function check(ok, message) log((ok and "PASS " or "FAIL ") .. message) end
  for _ = 1, 1200 do
    if game.overworld and game.stack and game.stack:top() == game.overworld then break end
    if game.input then game.input.pressQueue[#game.input.pressQueue + 1] = "a" end
    coroutine.yield()
  end
  if not game.overworld then log("FAIL no overworld"); file:close(); love.event.quit(); return end
  local lib = game.mods.exports.TERRARIUM.lib
  local Buildings, Structures = lib.require("Buildings"), lib.require("Structures")
  local Cam, Voxel, Day = lib.require("MarioCam"), lib.require("Voxel3D"), lib.require("DayNight")
  local Kit, Mesher = lib.require("ReefKit"), lib.require("ChunkMesher")
  local Water, WaterMap = lib.require("Water"), lib.require("WaterMap")
  require("src.render.Pipelines").setLevel("terrarium_voxel", 4)
  require("src.render.Pipelines").setLevel("terrarium_tiltshift", 0)
  lib.require("AutoFarm").setting:sync("off")
  lib.require("Weather").setting:sync("off")
  Cam.setting:sync("on")
  Day.setting:sync("day")
  Water.setting:sync(1.4)                          -- SWELL
  local camera, originalCamera = nil, Cam.camera
  Cam.camera = function() return camera or originalCamera() end
  local function settle(n)
    for _ = 1, n do
      for _, d in ipairs({ "up", "down", "left", "right" }) do
        game.input.state[d] = false
        if game.input.sources then game.input.sources[d] = nil end
      end
      game.input.pressQueue = {}
      coroutine.yield()
    end
  end
  -- one capture, waited for by its callback (never a count of yields)
  -- `hold` is kept pressed while the shot is waited for: writing a PNG
  -- takes a third of a second of wall time, and a key let go for that long
  -- is a swimmer who stops dead in the middle of the pass being photographed
  local function capture(name, hold)
    local pending = true
    love.graphics.captureScreenshot(function(data)
      local f = assert(io.open(out .. "/" .. name .. ".png", "wb"))
      f:write(data:encode("png"):getString()); f:close()
      pending = false
    end)
    for _ = 1, 240 do
      if not pending then break end
      if hold then game.input.state[hold] = true end
      coroutine.yield()
    end
    return not pending
  end
  local function waitReal(seconds, hold)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < seconds do
      if hold then game.input.state[hold] = true; coroutine.yield() else settle(1) end
    end
  end
  -- eye above and to the south of the cell, looking down at `y`
  local function look(cell, y, height, back)
    local x, z = cell.cx * 16 + 8, cell.cz * 16 + 8
    camera = { eye = { x, height, z + back }, focus = { x, y, z },
               fov = math.rad(45), curve = 0 }
  end
  local function enter(mapId, cx, cy)
    Voxel.lampLights = nil
    game.overworld.player.surfing = false
    game.overworld:setMap(mapId, cx, cy, "down")
    for _ = 1, 2400 do
      if Structures.peek(game.overworld.map) and Voxel.lampLights then break end
      settle(1)
    end
    settle(240)
  end
  -- the shader's decode, on the CPU: which kind a quad's first corner is
  local function kindOf(q)
    local s = type(q.shade) == "table" and q.shade[1] or q.shade
    local m = math.abs(s) * 64
    return math.floor(math.floor((m - math.floor(m)) * 32768 / 256) / 8)
  end
  local function census()
    local S = Structures.forMap(game.overworld.map)
    local kinds, cells = {}, {}
    for _, q in ipairs(S.spriteQuads or {}) do
      if q.tex == Kit.SHEET then
        local k = kindOf(q)
        kinds[k] = (kinds[k] or 0) + 1
        local cx, cz = math.floor(q[1][1] / 16), math.floor(q[1][3] / 16)
        local key = cx * 4096 + cz
        local c = cells[key] or { cx = cx, cz = cz, n = {} }
        cells[key] = c
        c.n[k] = (c.n[k] or 0) + 1
      end
    end
    return kinds, cells
  end

  -- ------- 1. what reached the mesh
  enter("ROUTE_12", 10, 64)
  check(not Buildings.lastError, "building error=" .. tostring(Buildings.lastError))
  check(Voxel.shader() ~= nil and not Voxel.shaderError, "voxel shader compiled: " .. tostring(Voxel.shaderError))
  local kinds, cells = census()
  local line = {}
  for name, k in pairs(Kit.KIND) do line[#line + 1] = ("%s=%d"):format(name, kinds[k] or 0) end
  table.sort(line)
  log("  reef quads by kind: " .. table.concat(line, " "))
  for _, name in ipairs({ "rigid", "pad", "stem", "reed", "kelp", "grass", "clover", "fan", "anemone" }) do
    check((kinds[Kit.KIND[name]] or 0) > 0, "the mesh carries " .. name)
  end
  -- the subjects: the pads, the kelp and the reeds nearest the player
  local p = game.overworld.player
  local function nearest(kind, least)
    local best, bd = nil, nil
    for _, c in pairs(cells) do
      local d = (c.cx - p.cellX) ^ 2 + (c.cz - p.cellY) ^ 2
      if (c.n[kind] or 0) > least and (not bd or d < bd) then best, bd = c, d end
    end
    return best
  end
  local subjects = {
    { name = "pads", cell = nearest(Kit.KIND.pad, 40), y = -2, height = 30, back = 26 },
    { name = "kelp", cell = nearest(Kit.KIND.kelp, 30), y = -7, height = 26, back = 22 },
    { name = "reeds", cell = nearest(Kit.KIND.reed, 150), y = 3, height = 16, back = 34 },
  }
  for _, s in ipairs(subjects) do
    check(s.cell ~= nil, "found " .. s.name .. " to look at")
    if s.cell then log(("  %s at cell %d,%d"):format(s.name, s.cell.cx, s.cell.cz)) end
  end

  -- ------- 2. six frames of each, 0.6 s apart
  local function frames(tag)
    for _, s in ipairs(subjects) do
      if s.cell then
        look(s.cell, s.y, s.height, s.back)
        settle(90)
        for i = 1, 6 do
          capture(("%s_%s_%d"):format(tag, s.name, i))
          waitReal(0.6)
        end
      end
    end
  end

  -- ------- 3. the run through the pads
  --
  -- Open water only: a pier's deck is a water cell to WaterMap and a wall to
  -- a swimmer, and the first run of this probe put the line down the column
  -- the pier stands in -- the player swam one cell and stopped against it.
  local Scene, DECK = lib.require("VoxelScene"), lib.require("BridgeKit").DECK
  local function swimmable(map, cx, cy)
    return map:inBounds(cx, cy) and WaterMap.surfaceCell(map, cx, cy)
       and Scene.groundAt(map, cx, cy) ~= DECK
  end
  local function runThrough(map)
    local best = nil
    for _, c in pairs(cells) do
      local pads = c.n[Kit.KIND.pad] or 0
      if pads > 30 then
        for _, d in ipairs({ { 1, 0, "right" }, { -1, 0, "left" }, { 0, 1, "down" }, { 0, -1, "up" } }) do
          local ok = true
          for k = -3, 3 do
            if not swimmable(map, c.cx + d[1] * k, c.cz + d[2] * k) then ok = false; break end
          end
          local far = (c.cx - p.cellX) ^ 2 + (c.cz - p.cellY) ^ 2
          if ok and (not best or far < best.far) then best = { cell = c, d = d, far = far } end
        end
      end
    end
    return best
  end
  local function pass(tag)
    local map = game.overworld.map
    local run = runThrough(map)
    if not run then log("  no clear run of open water through any pads; pass skipped"); return end
    local padCell, path = run.cell, run.d
    log(("  %s pass line: pads at %d,%d going %s"):format(tag, padCell.cx, padCell.cz, path[3]))
    local sx, sy = padCell.cx - path[1] * 3, padCell.cz - path[2] * 3
    look(padCell, -2, 34, 30)
    -- WHICH KEY GOES THAT WAY. The camera turns the controls (lib/MarioCam),
    -- so "down" is not south: the first run of this probe held down and the
    -- player swam north, away from the pads, and every shot of the pass was
    -- of water nobody was crossing. Asked, not assumed.
    local key = nil
    for _, try in ipairs({ "down", "up", "left", "right" }) do
      p.surfing = true
      game.overworld:setMap(map.id, sx, sy, "down")
      settle(120)
      p.surfing = true
      local x0, y0 = p.cellX, p.cellY
      for _ = 1, 48 do game.input.state[try] = true; coroutine.yield() end
      settle(40)
      local dx, dy = p.cellX - x0, p.cellY - y0
      log(("  %s: %s moves %d,%d"):format(tag, try, dx, dy))
      if dx * path[1] + dy * path[2] > 0 then key = try; break end
    end
    if not key then log("  no key swims toward the pads; pass skipped"); return end
    path[3] = key
    p.surfing = true
    game.overworld:setMap(map.id, sx, sy, "down")
    settle(150)
    p.surfing = true
    settle(60)
    log(("  %s pass %s from %d,%d (surfing=%s)"):format(tag, path[3], p.cellX, p.cellY, tostring(p.surfing)))
    local peakN, hull, wake, trail, shots = 0, false, false, {}, 0
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < 14 do
      local moving = (p.cellX - padCell.cx) * path[1] + (p.cellY - padCell.cz) * path[2] < 2
      if moving then game.input.state[path[3]] = true else settle(1) end
      coroutine.yield()
      local st = Voxel.stir
      if st then
        if st.n > peakN then peakN = st.n end
        for i = 1, st.n do
          if st.p[i][4] >= 0 then hull = true else wake = true end
        end
      end
      local here = ("%d,%d"):format(p.cellX, p.cellY)
      if trail[#trail] ~= here then trail[#trail + 1] = here end
      -- a frame every half second through the pass and after it
      if love.timer.getTime() - t0 >= shots * 0.6 then
        shots = shots + 1
        capture(("%s_pass_%02d"):format(tag, shots), moving and path[3] or nil)
      end
    end
    log(("  %s pass: cells %s; stir peak n=%d hull=%s wake=%s"):format(
        tag, table.concat(trail, " > "), peakN, tostring(hull), tostring(wake)))
    check(#trail >= 4, tag .. " pass crossed the pads (" .. #trail .. " cells)")
    return peakN, hull, wake
  end

  frames("on")
  local nOn, hullOn, wakeOn = pass("on")

  local realPack = Kit.pack
  Kit.pack = function(shade, _, y) return realPack(shade, nil, y) end
  Buildings.invalidate()
  Mesher.invalidate()
  enter("ROUTE_12", 10, 64)
  local still = census()
  check((still[Kit.KIND.rigid] or 0) > 0 and not still[Kit.KIND.pad],
        "the rigid rebuild really is rigid")
  frames("off")
  pass("off")
  Kit.pack = realPack
  Buildings.invalidate()
  Mesher.invalidate()

  check((nOn or 0) >= 2 and hullOn and wakeOn,
        "a swimmer reaches the garden: a hull and a wake in the stir packet")
  file:close()
  love.event.quit()
end
