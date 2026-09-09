-- The VOXEL trees: do they load, do they wear the map's greens, do they
-- move, and does the row still say what it does.
--
-- Three questions, each with a way to pass and be wrong (see trees_probe):
--   1. THE ROW. values are { voxel, 3d } now; a save left on round two's
--      "classic" must land on VOXEL, one on "3d" must keep 3D, and each
--      value must load ITS set (four species each) -- a wrong cache key
--      would load one set under both names and look fine on screen.
--   2. THE PAINT. A VOXEL bake ships no greens. After a map's forest
--      finishes, Trees3D.lastPaint says whether it was painted from the
--      map's tree tile ("shipped" means the fallback png, which is a bug
--      on any outdoor Kanto map). ROUTE_2 and VIRIDIAN_FOREST use different
--      tilesets, so their keys must differ.
--   3. THE WIND. The paired pixel-difference measurement from
--      treevox_probe, unchanged -- it has three known traps and this is
--      the shape that survives them.
-- Then pictures: VOXEL on three maps, and the 3D set on one for the A/B.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local TAG = os.getenv("DS_PROBE_TAG") or "vt"
  local logf = assert(io.open(OUT .. "/voxeltree_" .. TAG .. ".log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring((select(i, ...))) end
    logf:write(table.concat(p, " ") .. "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b
    coroutine.yield()
  end
  local fails = 0
  local function check(ok, msg)
    log((ok and "PASS " or "FAIL ") .. msg)
    if not ok then fails = fails + 1 end
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: never booted"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end

  local lib = game.mods.exports.TERRARIUM.lib
  local Voxel3D  = lib.require("Voxel3D")
  local Trees3D  = lib.require("Trees3D")
  local Wind     = lib.require("Wind")
  local DayNight = lib.require("DayNight")

  -- ---- 1. THE ROW
  local function names() return table.concat(Trees3D.loaded(), ",") end
  Trees3D.setting:sync("classic")
  check(Trees3D.setting:get() == "voxel", "old 'classic' lands on voxel: " .. tostring(Trees3D.setting:get()))
  Trees3D.setting:sync("3d")
  check(Trees3D.setting:get() == "3d", "'3d' keeps 3d")
  local n3 = Trees3D.loaded()
  check(#n3 == 4 and n3[1] == "oak", "3D set loads its four: " .. names())
  check(Trees3D.ASSET_DIR == "assets/ground/tree/", "3D dir " .. tostring(Trees3D.ASSET_DIR))
  check(math.abs((Trees3D.WIND_SHARE or 0) - 3.4) < 1e-6, "3D windShare " .. tostring(Trees3D.WIND_SHARE))
  Trees3D.setting:sync("voxel")
  local nv = Trees3D.loaded()
  check(#nv == 4 and nv[1] == "round", "VOXEL set loads its four: " .. names())
  check(Trees3D.ASSET_DIR == "assets/ground/tree/voxel/", "VOXEL dir " .. tostring(Trees3D.ASSET_DIR))
  check(math.abs((Trees3D.WIND_SHARE or 0) - 2.9) < 1e-6, "VOXEL windShare " .. tostring(Trees3D.WIND_SHARE))
  check(Trees3D.available(), "available() on VOXEL")
  for _, nm in ipairs(nv) do
    local t = Trees3D.templates[nm]
    if t then
      local wmin, wmax, vmax = 1e9, -1e9, 0
      for i = 1, #t.weights do
        local w = t.weights[i]
        if w < wmin then wmin = w end
        if w > wmax then wmax = w end
        if t.verts[i][5] > vmax then vmax = t.verts[i][5] end
      end
      log(string.format("  %s: verts=%d tris=%d solidTris=%d h=%.1f r=%.1f canopyY=%.1f "
                        .. "canopyR=%.1f weight %.3f..%.3f vmax=%.3f proxy=%s",
                        nm, #t.verts, #t.indices / 3, #t.solidIndices / 3, t.height,
                        t.radius, t.canopyY, t.canopyR, wmin, wmax, vmax,
                        tostring(t.shadowVerts and #t.shadowVerts or "none")))
      check(wmax < 0.985, nm .. " no vertex reaches the card tier")
      check(vmax < 0.75, nm .. " no uv above the card cut")
      check(#t.solidIndices == #t.indices, nm .. " every triangle is solid (no cards)")
    else
      check(false, nm .. " template missing")
    end
  end
  -- a remesh so the world below is built with the VOXEL set whatever the
  -- save carried
  Trees3D.onOptionsChanged("voxel")

  -- ---- helpers
  local function meshQueue()
    local ok, q = pcall(function()
      local CM = lib.require("ChunkMesher")
      return CM.pending and CM.pending() or 0
    end)
    return (ok and tonumber(q)) or 0
  end

  local function settle(label, maxTicks)
    maxTicks = maxTicks or 4000
    local ticks, live = 0, false
    local state = "?"
    while true do
      if Voxel3D.lampLights ~= nil then live = true end
      local map = game.overworld and game.overworld.map
      local done
      done, state = Trees3D.ready(map)
      if live and (done or state == "hulls") then break end
      if ticks >= maxTicks then
        log("FAIL: settle " .. label .. " never came up after " .. ticks); break
      end
      coroutine.yield(); ticks = ticks + 1
    end
    local owed, queued = select(2, Trees3D.buildsInFlight()), meshQueue()
    local waited = 0
    while (owed > 0 or queued > 0) and waited < 900 do
      coroutine.yield(); ticks, waited = ticks + 1, waited + 1
      owed, queued = select(2, Trees3D.buildsInFlight()), meshQueue()
    end
    log(string.format("settled %s in %d ticks (state=%s owed=%d queued=%d)",
                      label, ticks, tostring(state), owed, queued))
    return state
  end

  -- Shots wait on the CALLBACK, not on a frame count.
  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(d)
      local f = io.open(OUT .. "/" .. name .. ".png", "wb")
      if f then f:write(d:encode("png"):getString()); f:close() end
      done = true
    end)
    local guard = 0
    while not done and guard < 240 do coroutine.yield(); guard = guard + 1 end
    if not done then log("WARN: shot " .. name .. " never landed") end
  end

  local function visit(mapId, x, y)
    local ok, err = pcall(function() game.overworld:setMap(mapId, x, y, "up") end)
    if not ok then log("WARN: setMap " .. mapId .. " failed: " .. tostring(err)) return nil end
    local state = settle(mapId)
    wait(20)
    return state
  end

  -- pin the hour (NOT forceSync -- see treevox_probe)
  pcall(function() DayNight.setting:sync("day") end)
  wait(30)
  log(string.format("clock pinned: mode=%s t=%.0f", tostring(DayNight.setting:get()),
                    tonumber(DayNight.time()) or -1))

  -- ---- 2. THE PAINT, and the LOOK
  local paints = {}
  local function paintOf(mapId)
    local p = Trees3D.lastPaint
    paints[mapId] = p
    log("paint on " .. mapId .. ": " .. tostring(p))
    return p
  end

  -- (10,10) on Viridian is inside the west border wood: a wall of canopy
  -- with no ground in frame. Pallet's lawn and Viridian's centre both show
  -- trees standing on grass, which is the picture that judges a tree.
  local state = visit("PALLET_TOWN", 10, 8)
  paintOf("PALLET_TOWN")
  shot("voxeltree_" .. TAG .. "_pallet")
  state = visit("VIRIDIAN_CITY", 24, 22)
  paintOf("VIRIDIAN_CITY")
  shot("voxeltree_" .. TAG .. "_viridian")

  state = visit("ROUTE_2", 10, 10)
  check(state == "ready", "ROUTE_2 forest built with the VOXEL set (state " .. tostring(state) .. ")")
  local pr2 = paintOf("ROUTE_2")
  local function painted(p) return p and not tostring(p):find("shipped", 1, true) end
  check(painted(pr2), "ROUTE_2 crown painted from the map's tree tile (" .. tostring(pr2) .. ")")
  local tsId = tostring(game.overworld.map and game.overworld.map.tileset and game.overworld.map.tileset.id)
  log("ROUTE_2 tileset " .. tsId .. " sites=" .. tostring(Trees3D.count(game.overworld.map)))
  -- where the map's pixels come from, so a "shipped" above has a cause
  pcall(function()
    local map = game.overworld.map
    local TR = require("src.render.TileRenderer")
    log(string.format("  renderer=%s gbcAtlas=%s trueColor=%s atlasImageData=%s",
                      tostring(map.renderer ~= nil),
                      tostring(map.renderer and map.renderer.gbcAtlas),
                      tostring(map.tileset.trueColor),
                      tostring(TR.atlasImageData ~= nil)))
    local TA = lib.require("TerrainAtlas")
    -- the profile's whole cylinder list, pot AND tree wall, as Trees3D asks
    local sh, why = TA.tileShades(map, { 42, 43, 58, 59, 64, 65, 80, 81 })
    if sh then
      for k = 1, 4 do
        local c = sh[k]
        if c then log(string.format("  tile shade %d -> %.2f %.2f %.2f", k, c[1], c[2], c[3])) end
      end
    else
      log("  tileShades refused: " .. tostring(why))
    end
    -- the atlas it read, as a picture, and the tree tile's texels raw vs
    -- baked -- "grey" is a verdict, this is the evidence
    local src = TA.lastShadeSource
    if src and src.encode then
      local f = io.open(OUT .. "/atlas_" .. TAG .. "_route2.png", "wb")
      if f then f:write(src:encode("png"):getString()); f:close() end
      local Assets = require("src.render.Assets")
      local raw = Assets.imageData(map.tileset.image)
      local w, h = src:getDimensions()
      local rw, rh = raw:getDimensions()
      log(string.format("  atlas %dx%d raw %dx%d", w, h, rw, rh))
      for _, xy in ipairs({ { 80, 16 }, { 84, 20 }, { 82, 30 }, { 88, 18 }, { 8, 8 }, { 0, 0 } }) do
        local r1, g1, b1 = raw:getPixel(xy[1], xy[2])
        local r2, g2, b2, a2 = src:getPixel(xy[1], xy[2])
        log(string.format("  texel %d,%d raw %.2f -> baked %.2f %.2f %.2f a%.2f",
                          xy[1], xy[2], r1, r2, g2, b2, a2))
      end
    end
  end)
  shot("voxeltree_" .. TAG .. "_route2")
  if os.getenv("DS_PROBE_QUICK") then
    log("quick stop"); logf:close(); love.event.quit(); return
  end

  state = visit("VIRIDIAN_FOREST", 17, 43)
  if state then
    local pf = paintOf("VIRIDIAN_FOREST")
    local ts2 = tostring(game.overworld.map and game.overworld.map.tileset and game.overworld.map.tileset.id)
    log("VIRIDIAN_FOREST tileset " .. ts2 .. " state=" .. tostring(state)
        .. " sites=" .. tostring(Trees3D.count(game.overworld.map)))
    if state == "ready" then
      check(painted(pf), "forest crown painted from ITS tree tile")
      check(pf ~= pr2, "forest palette differs from ROUTE_2's")
    end
    shot("voxeltree_" .. TAG .. "_forest")
  end

  -- ---- 3. THE WIND (paired, downward -- see treevox_probe for why)
  state = visit("ROUTE_2", 10, 10)
  -- clear sky: a shower or a snowfall moves more of the screen between two
  -- frames than the whole forest does (vt4 read 65 on both halves of a pair)
  pcall(function() lib.require("Weather").setting:sync("off") end)
  wait(120)
  pcall(function() Wind.setting:sync(4) end)      -- GALE (numeric row values)
  wait(400)
  shot("voxeltree_" .. TAG .. "_wind")

  -- ten rounds, not six: at 2.9 the cubes move less than the cards did and
  -- the first run split 4/6 on a real 1.8 delta -- clouds and the ambient
  -- life are the other 2. More pairs, same trap-proof shape.
  local GAP, ROUNDS = 3, 10
  local function frameDiff()
    local px, py = 0, 0
    pcall(function() px, py = game.overworld.player.cellX, game.overworld.player.cellY end)
    local a, b, got = nil, nil, 0
    love.graphics.captureScreenshot(function(d) a = d; got = got + 1 end)
    local g = 0
    while got < 1 and g < 240 do coroutine.yield(); g = g + 1 end
    wait(GAP)
    love.graphics.captureScreenshot(function(d) b = d; got = got + 1 end)
    g = 0
    while got < 2 and g < 240 do coroutine.yield(); g = g + 1 end
    local qx, qy = 0, 0
    pcall(function() qx, qy = game.overworld.player.cellX, game.overworld.player.cellY end)
    if not (a and b) or px ~= qx or py ~= qy then return nil end
    local w, h = a:getDimensions()
    local acc, cnt = 0, 0
    for y = math.floor(h * 0.15), math.floor(h * 0.60), 3 do
      for x = 0, w - 1, 3 do
        local r1, g1, b1 = a:getPixel(x, y)
        local r2, g2, b2 = b:getPixel(x, y)
        acc = acc + math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2)
        cnt = cnt + 1
      end
    end
    return (acc / math.max(1, cnt)) * 255
  end
  local function median(t)
    table.sort(t)
    if #t == 0 then return -1 end
    return t[math.ceil(#t / 2)]
  end
  local function pairedSway(share)
    local keep = Trees3D.WIND_SHARE
    local on, off, delta = {}, {}, {}
    for _ = 1, ROUNDS do
      Trees3D.WIND_SHARE = 0
      wait(6)
      local a = frameDiff()
      Trees3D.WIND_SHARE = share
      wait(6)
      local b = frameDiff()
      if a and b then
        off[#off + 1] = a; on[#on + 1] = b; delta[#delta + 1] = b - a
      end
    end
    Trees3D.WIND_SHARE = keep
    local mD = median(delta)
    local won = 0
    for _, d in ipairs(delta) do if d > 0 then won = won + 1 end end
    log(string.format("sway share=%.2f: on=%.3f off=%.3f delta=%.3f | %d/%d rounds moved more with wind",
                      share, median(on), median(off), mD, won, #delta))
    return mD, won, #delta
  end
  local keep = Trees3D.WIND_SHARE
  local dFull, wFull, nFull = pairedSway(keep)
  local dHalf, wHalf, nHalf = pairedSway(keep * 0.5)
  if nFull >= 4 and wFull >= math.ceil(nFull * 0.75) and dFull > 0 and dHalf > 0 and dFull > dHalf then
    check(true, string.format("the crown moves and tracks the wind: full %.3f > half %.3f (%d/%d)",
                              dFull, dHalf, wFull, nFull))
  elseif nFull >= 4 and wFull >= math.ceil(nFull * 0.75) and dFull > 0 then
    check(true, string.format("(weak) the crown moves (delta %.3f, %d/%d) but half read %.3f",
                              dFull, wFull, nFull, dHalf))
  else
    check(false, string.format("canopy sway not separable: full %.3f (%d/%d) half %.3f (%d/%d)",
                               dFull, wFull, nFull, dHalf, wHalf, nHalf))
  end
  pcall(function() Wind.setting:sync(1) end)      -- AUTO

  -- ---- the A/B: the same route under the 3D set, then back
  Trees3D.onOptionsChanged("3d")
  state = settle("ROUTE_2 as 3D")
  check(state == "ready" and Trees3D.setting:get() == "3d", "row flip to 3D rebuilt the forest")
  wait(20)
  shot("voxeltree_" .. TAG .. "_route2_3d")
  Trees3D.onOptionsChanged("voxel")
  state = settle("ROUTE_2 back to VOXEL")
  check(state == "ready" and Trees3D.setting:get() == "voxel", "row flip back to VOXEL rebuilt the forest")

  log(fails == 0 and "ALL PASS" or ("FAILS: " .. fails))
  log("done")
  logf:close()
  love.event.quit()
end
