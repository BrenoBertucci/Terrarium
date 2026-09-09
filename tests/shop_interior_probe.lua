-- Probe: the inside of a Poke Mart, rebuilt as modelled furniture
-- (lib/ShopKit.lua under the SHOP row, on the same read/emit pipeline
-- lib/RoomKit.lua and lib/CryptKit.lua ride).
--
--   BUILD   the map builds geometry at all (objectQuads), the kit records
--           no fallback in Buildings.lastError, and -- once ShopKit
--           exists -- it built distinct models and stamped placements.
--   LOOK    five named frames of the room, the hour swept over the widest
--           of them, and the same room with the SHOP row FORCED OFF, so
--           there is an honest A/B against what ships today.
--   COST    frame time standing in the room, vsync off, against a stated
--           budget.
--
-- THE ROOM IS 8x8 CELLS AND THE DOOR IS FOUND, NOT GUESSED.
-- `python tools/interior_plan.py VIRIDIAN_MART` prints the real grid --
-- 4x4 blocks = 16x16 tiles = 8x8 cells, the product wall two cells deep
-- across the north, an L of counter in the south-west with the clerk
-- inside it, two 2x2-cell gondolas filling the east half at cy 3..4, and
-- two door warps on the south row. The plan is READ THERE, never
-- re-derived in Lua; what this file derives is only the door, and it
-- derives it from `map.def.warps` the way tests/mart_probe.lua does --
-- the authoring coordinates in assets/docs/buildings/ are a different
-- numbering and put the camera in an alley three runs running. Every
-- anchor below is then expressed relative to that door and to
-- map.def.width/height, so PEWTER_MART, CERULEAN_MART, LAVENDER_MART and
-- CELADON_MART_1F frame themselves without a second table.
--
-- Traps respected (memory: terrarium-probe-screenshot-race,
-- terrarium-underpass-visibility, terrarium-ambientlife-probe):
--   - captureScreenshot is a CALLBACK. Shooting and then yielding N
--     frames photographs the NEXT state, so every shot waits on the
--     callback's own flag -- and then re-opens the file, because "the
--     callback fired" and "a PNG is on disk" are different claims.
--   - the player DRIFTS on his own after setMap, so a placement is only
--     accepted once his cell has held still, never after a frame count;
--     and because two cells of this room are WARPS, a drift can walk him
--     out of the building entirely -- so map.id is re-checked after every
--     settle, and the anchors never stand on a warp tile.
--   - A-FARM pushes directions into the press queue between frames and
--     walks him back out again. It is turned off, and the direction state
--     is released before and after every settle.
--   - the 3D pass must be polled up, never frame-counted -- but INDOORS
--     Voxel3D.lampLights is a guaranteed false negative: a shop hangs no
--     lanterns, so it never rises and the poll would spin its whole
--     guard out. tests/pokecenter_interior_probe.lua's substitute is used
--     instead: wait until Structures hands back a build whose objectQuads
--     count has stopped moving. (The crypt probe may poll lampLights
--     because the crypt lights ITSELF; a Mart does not.)
--
-- ShopKit and the SHOP row are being written in parallel with this file.
-- Every reference to them goes through lib.require inside a pcall, and
-- their absence is logged loudly and skipped rather than failed -- so the
-- probe is runnable today, and judges the geometry tomorrow.
--
-- POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> SHOP_MAP=<map id> \
-- SHOP_TAG=<tag> SHOP_LEVEL=<0..5> SHOP_AB=<0|1> SHOP_AB_OFF=<value> \
-- SHOP_HOURS=<day,dusk,night> SHOP_BUDGET=<ms> SHOP_BUDGET_P95=<ms> \
-- POKEPORT_DRIVER=mods/TERRARIUM/tests/shop_interior_probe.lua gen1recomp
--
--   SHOP_MAP         which shop. Default VIRIDIAN_MART. Also PEWTER_MART,
--                    CERULEAN_MART, LAVENDER_MART, CELADON_MART_1F, ...
--   SHOP_TAG         filename stem for the log and the PNGs. Default
--                    "shop" -- set it per map so two runs do not collide.
--   SHOP_LEVEL       the terrarium_voxel rung. Default 4.
--   DS_PROBE_DIR     where the log and the PNGs land. Default ".".
--   SHOP_AB          1 (default) shoots the A/B with the SHOP row forced
--                    off; 0 skips it.
--   SHOP_AB_OFF      the value to force the row to. Default "classic";
--                    if the row has no such value the last one on its
--                    ladder is used instead, and the log says which.
--   SHOP_HOURS       comma list of DAYTIME values. Default "day,dusk,night".
--   SHOP_BUDGET      mean frame time budget, ms. Default 6.0.
--   SHOP_BUDGET_P95  p95 frame time budget, ms. Default 20.0.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local MAP = os.getenv("SHOP_MAP") or "VIRIDIAN_MART"
  local TAG = os.getenv("SHOP_TAG") or "shop"
  local LEVEL = tonumber(os.getenv("SHOP_LEVEL") or "") or 4
  local DO_AB = (os.getenv("SHOP_AB") or "1") ~= "0"
  local AB_OFF = os.getenv("SHOP_AB_OFF") or "classic"
  local BUDGET = tonumber(os.getenv("SHOP_BUDGET") or "") or 6.0
  local BUDGET95 = tonumber(os.getenv("SHOP_BUDGET_P95") or "") or 20.0
  local HOURS = {}
  for h in (os.getenv("SHOP_HOURS") or "day,dusk,night"):gmatch("[^,%s]+") do
    HOURS[#HOURS + 1] = h
  end

  local logf = assert(io.open(OUT .. "/" .. TAG .. "_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local function done(msg)
    if msg then log(msg) end
    logf:close(); love.event.quit()
  end

  -- ------------------------------------------------------- free roam --

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then return done("FAILURES (1):\n  - no overworld") end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("WARN: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    return done("FAILURES (1):\n  - TERRARIUM not loaded")
  end
  log("map:", MAP, " tag:", TAG)
  log("version:", exports.TERRARIUM.version)

  local DayNight    = lib.require("DayNight")
  local Weather     = lib.require("Weather")
  local Voxel3D     = lib.require("Voxel3D")
  local Structures  = lib.require("Structures")
  local Buildings   = lib.require("Buildings")
  local MarioCam    = lib.require("MarioCam")
  local MiniMap     = lib.require("MiniMap")
  local AutoFarm    = lib.require("AutoFarm")
  local ChunkMesher = lib.require("ChunkMesher")
  local Anime       = lib.require("Anime")
  local FloorArt    = lib.require("FloorArt")
  local Pipelines   = require("src.render.Pipelines")

  -- The kit under test, and its row. Both are being written in parallel
  -- with this probe; absent, everything that depends on them is SKIPPED
  -- and said out loud, so a green run today cannot be mistaken for a
  -- judgement on geometry that does not exist yet.
  local okKit, ShopKit = pcall(lib.require, "ShopKit")
  if not (okKit and type(ShopKit) == "table") then ShopKit = nil end
  local shopRow = ShopKit and ShopKit.setting or nil

  -- Pin everything two runs could disagree about.
  Weather.setting:sync("off")
  DayNight.setting:sync("day")
  Pipelines.setLevel("terrarium_voxel", LEVEL)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  pcall(function() MiniMap.setting:setIndex(3, game) end)    -- MAP off
  pcall(function() AutoFarm.setting:setIndex(1, game) end)   -- A-FARM off
  pcall(function() MarioCam.setting:setIndex(2, game) end)   -- SM64CAM on
  -- LIGHT and SHADOWS, pinned ON. Neither belongs to the shop, and both
  -- can silently take its shadows away: Light.split hands EVERYTHING to
  -- the ambient term when LIGHT is FLAT, so the sun pass still renders,
  -- sunDark is still positive, every Lua-side check is still green, and
  -- the room comes back with no shadow anywhere. That is four runs' worth
  -- of a wrong answer if the probe does not pin it.
  pcall(function()
    local Light = lib.require("Light")
    if Light and Light.setting then Light.setting:sync(true) end
  end)
  pcall(function()
    local Quality = lib.require("Quality")
    if Quality and Quality.shadowSetting then
      Quality.shadowSetting:setIndex(1, game)
    end
  end)

  local ww, wh = love.graphics.getDimensions()
  log(("window: %dx%d  voxelLevel=%d  anime=%s"):format(
      ww, wh, LEVEL, tostring(Anime.level and Anime.level() or "?")))
  if ShopKit then
    local v = "?"
    if shopRow then pcall(function() v = shopRow:get() end) end
    log("ShopKit: PRESENT  row value:", v)
  else
    log("ShopKit: ABSENT -- lib/ShopKit.lua does not load yet.")
    log("  Every kit check below is SKIPPED, not passed. The frames still")
    log("  shoot: they are the BEFORE half of the A/B.")
  end

  -- ------------------------------------------------- checks and shots --

  local fails, skips = {}, {}
  local function check(ok, msg)
    if not ok then fails[#fails + 1] = msg end
    log((ok and "  ok   " or "  FAIL ") .. msg)
  end
  local function skip(msg)
    skips[#skips + 1] = msg
    log("  skip " .. msg)
  end

  -- A screenshot is only taken when its own callback has fired AND a
  -- non-empty PNG is on disk. Those are two different claims and the
  -- second is the one a human judging the room actually needs.
  local shots = {}
  local function shot(name)
    local file = TAG .. "_" .. name .. ".png"
    local path = OUT .. "/" .. file
    local fired = false
    love.graphics.captureScreenshot(function(data)
      local f = io.open(path, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      fired = true
    end)
    for _ = 1, 600 do
      if fired then break end
      coroutine.yield()
    end
    local size = 0
    local f = io.open(path, "rb")
    if f then size = f:seek("end") or 0 f:close() end
    shots[#shots + 1] = { name = file, fired = fired, size = size }
    log(("    shot %-28s callback=%s bytes=%d"):format(
        file, fired and "fired" or "NEVER", size))
    return fired and size > 0
  end

  -- INDOORS lampLights never rises (no lanterns), so the honest poll is
  -- the build itself settling. See the header.
  local function quadsUp(guard)
    local last, stable = -1, 0
    for _ = 1, guard or 900 do
      local okS, S = pcall(Structures.forMap, game.overworld.map)
      -- BOTH buckets: a room built against an authored sheet lands wholly
      -- in spriteQuads and leaves objectQuads at zero, so polling only the
      -- one would wait out the guard on a room that was ready in a second
      -- (the Mart's first run did exactly that).
      local c = -1
      if okS and S then
        c = ((S.objectQuads and #S.objectQuads) or 0)
            + ((S.spriteQuads and #S.spriteQuads) or 0)
      end
      if c > 0 and c == last then stable = stable + 1 else stable, last = 0, c end
      if stable >= 30 then return true, c end
      coroutine.yield()
    end
    return false, last
  end

  local function releaseDirs()
    local st = game.input.state
    for _, d in ipairs({ "up", "down", "left", "right" }) do
      st[d] = false
      if game.input.sources then game.input.sources[d] = nil end
    end
    game.input.pressQueue = {}
  end

  local function lockCell(guard)
    local last, stable = nil, 0
    for _ = 1, guard or 1200 do
      local p = game.overworld.player
      local cur = p and (tostring(p.cellX) .. "," .. tostring(p.cellY)) or "?"
      if cur == last then stable = stable + 1 else stable, last = 0, cur end
      if stable >= 45 then return true, cur end
      coroutine.yield()
    end
    return false, last
  end

  -- setMap DOES NOT GUARANTEE THE CELL (mart_probe.lua's lesson): ask for
  -- one the map will not stand a player on and the engine silently drops
  -- him somewhere else. And in here it is worse -- two cells of the south
  -- row are door warps, so a drift can put him back on the street with
  -- every assert still green. A placement is accepted only when the map
  -- is still this map and he is still on the cell that was asked for.
  local function place(x, y, dir)
    local ok = pcall(function()
      game.overworld:setMap(MAP, x, y, dir or "up")
    end)
    if not ok then return false, "setMap error" end
    wait(40)
    releaseDirs()
    if game.overworld.map.id ~= MAP then
      return false, "warped out to " .. tostring(game.overworld.map.id)
    end
    local locked, cell = lockCell(600)
    releaseDirs()
    if game.overworld.map.id ~= MAP then
      return false, "warped out to " .. tostring(game.overworld.map.id)
    end
    return locked and cell == (x .. "," .. y), cell
  end

  -- Land anywhere first: map.def -- and with it the warps and the room's
  -- size -- only exists once the map is loaded.
  --
  -- lastError is cleared HERE, before the load, not later: models are
  -- cached module-wide and built once, so the build this setMap triggers
  -- is the only one that can record a fallback. Clearing after it would
  -- wipe the very message the probe exists to catch. The mesh cache is
  -- dropped for the same reason -- so the models counted below were built
  -- for this map, on this run.
  Buildings.lastError = nil
  pcall(ChunkMesher.invalidate)
  -- (5,5) only because mart_probe.lua's "land anywhere" call uses it and
  -- it is floor in every shipped Mart; the cell is irrelevant here, the
  -- point is that map.def exists afterwards.
  local ok0 = pcall(function() game.overworld:setMap(MAP, 5, 5, "up") end)
  if not ok0 or game.overworld.map.id ~= MAP then
    return done("FAILURES (1):\n  - could not load " .. MAP)
  end
  wait(60)
  releaseDirs()

  local map = game.overworld.map
  local def = map.def
  local CW, CH = (def.width or 4) * 2, (def.height or 4) * 2   -- room, in cells
  local tsid = tostring(map.tileset and map.tileset.id)
  log(("room: %s tileset=%s %dx%d blocks = %dx%d cells"):format(
      tostring(map.id), tsid, def.width or -1, def.height or -1, CW, CH))

  -- THE DOOR, from map.def.warps. An interior's exits name LAST_MAP; a
  -- floor-to-floor stair names another map, so the southernmost warp row
  -- is preferred and the west-most cell of it is taken as the door.
  local warpCell = {}
  local dx, dy = nil, nil
  for _, w in ipairs((def and def.warps) or {}) do
    if w.x and w.y then
      warpCell[w.x .. "," .. w.y] = true
      if (not dy) or w.y > dy or (w.y == dy and w.x < dx) then
        dx, dy = w.x, w.y
      end
    end
  end
  if not dx then
    log("  no warps on map.def -- falling back to the south row's middle")
    dx, dy = math.floor(CW / 2) - 1, CH - 1
  end
  log(("  door cell (%d,%d)   warp cells: %d"):format(
      dx, dy, (function() local c = 0 for _ in pairs(warpCell) do c = c + 1 end
               return c end)()))

  -- Where an anchor WANTS to stand. If the cell refuses (a gondola moved,
  -- a bigger Mart), rings outward until one holds -- never onto a warp,
  -- which would walk the probe out of the building.
  local function standAt(wx, wy, dir, label)
    local tried = {}
    local order = { { 0, 0 } }
    for r = 1, 3 do
      for d = -r, r do
        order[#order + 1] = { d, -r }; order[#order + 1] = { d, r }
        order[#order + 1] = { -r, d }; order[#order + 1] = { r, d }
      end
    end
    for _, o in ipairs(order) do
      local x, y = wx + o[1], wy + o[2]
      if x >= 0 and y >= 0 and x < CW and y < CH
         and not warpCell[x .. "," .. y] and not tried[x .. "," .. y] then
        tried[x .. "," .. y] = true
        local okP, why = place(x, y, dir)
        if okP then
          if x ~= wx or y ~= wy then
            log(("    %s: asked (%d,%d), stood (%d,%d)")
                :format(label, wx, wy, x, y))
          end
          return x, y
        end
        log(("    %s: (%d,%d) refused -> %s"):format(label, x, y, tostring(why)))
      end
    end
    return nil
  end

  -- ------------------------------------------------------ the anchors --
  --
  -- All five are expressed from the door and the room's size, so a Mart
  -- that is not Viridian's frames itself. For the 8x8 shipped room these
  -- land on the cells tools/interior_plan.py shows as floor:
  --
  --   room      (3,6)  one cell inside the door, the widest view
  --   wall      (5,2)  first walkable row under the two-cell product wall
  --   counter   (2,6)  east of the L, looking west across the till
  --   aisle     (3,4)  the north-south corridor: counter/shelf to the
  --                    west, the two gondolas to the east. (The gondolas
  --                    themselves stand back-to-back with no gap between
  --                    them -- interior_plan.py shows cx 4..5 and cx 6..7
  --                    touching -- so THIS is the room's only aisle, and
  --                    the shot is of it rather than of a gap that the
  --                    shipped map does not have.)
  --   dollhouse (5,7)  the south row, under an injected low camera
  local ANCHORS = {
    { name = "room",    x = dx,     y = dy - 1,  dir = "up",
      what = "the whole room from just inside the door" },
    { name = "wall",    x = CW - 3, y = 2,       dir = "up",
      what = "the north product wall, head-on" },
    { name = "counter", x = 2,      y = CH - 2,  dir = "left",
      what = "the checkout counter, from the east" },
    { name = "aisle",   x = dx,     y = CH - 4,  dir = "up",
      what = "down the aisle, gondolas east, counter west" },
  }

  -- ------------------------------------------------- arrive and report --

  local first = ANCHORS[1]
  local sx, sy = standAt(first.x, first.y, first.dir, first.name)
  if not sx then
    return done("FAILURES (1):\n  - no standable cell near the door")
  end
  local upOK, quadN = quadsUp()
  log("")
  log(("[%s] stood (%d,%d) facing %s -- %s"):format(
      first.name, sx, sy, first.dir, first.what))
  log(("  build settled: %s at objectQuads=%d"):format(
      upOK and "PASS" or "FAIL", quadN))

  map = game.overworld.map
  local okS, S = pcall(Structures.forMap, map)
  local objN = (okS and S) and #S.objectQuads or -1
  local sprN = (okS and S and S.spriteQuads) and #S.spriteQuads or 0
  local figN = (okS and S and S.figures) and #S.figures or 0
  log(("  objectQuads=%d spriteQuads=%d figures=%d outdoor=%s"):format(
      objN, sprN, figN, okS and tostring(S.outdoor) or "?"))
  -- the shop is built against an authored sheet, so its quads land in
  -- spriteQuads and NOT in objectQuads (lib/Buildings.lua sorts by
  -- whether the model carries a .tex). Either counts as "it built".
  check(objN > 0 or sprN > 0,
        "the map built geometry (objectQuads or spriteQuads > 0)")

  -- The kit's models, keyed "<tileset>:<index>[@<sig>]" the way
  -- Buildings.build keys every other kit's.
  local function kitStats()
    local okSt, st = pcall(Buildings.stats)
    if not (okSt and st) then return 0, 0, {} end
    local models, quads, keys = 0, 0, {}
    for key, v in pairs(st) do
      if key:sub(1, #tsid + 1) == tsid .. ":" then
        models = models + 1
        quads = quads + (v.quads or 0)
        keys[#keys + 1] = ("%s(q=%d)"):format(key, v.quads or 0)
      end
    end
    table.sort(keys)
    return models, quads, keys
  end

  -- PLACEMENTS, exactly. Buildings.stamp writes ONE fresh shape table per
  -- placement and shares it across that placement's cells, so counting
  -- distinct shape identities counts stamps, and counting entries counts
  -- the cells they claimed.
  local function stampCount()
    if not (okS and S and S.shapeAt) then return 0, 0 end
    local seen, placements, cells = {}, 0, 0
    for _, s in pairs(S.shapeAt) do
      if type(s) == "table" and s.class == "building" and s.authored then
        cells = cells + 1
        if not seen[s] then seen[s] = true; placements = placements + 1 end
      end
    end
    return placements, cells
  end

  local models, kitQuads, keys = kitStats()
  local placements, claimed = stampCount()
  log(("  kit models (%s:*) = %d, their quads = %d"):format(tsid, models, kitQuads))
  log(("  placements stamped = %d over %d claimed tiles"):format(
      placements, claimed))
  for _, k in ipairs(keys) do log("    " .. k) end
  log("  Buildings.lastError:", tostring(Buildings.lastError))
  check(Buildings.lastError == nil, "the build recorded no fallback")

  if ShopKit then
    check(models > 0, "ShopKit built at least one model")
    check(placements > 0, "ShopKit stamped at least one placement")
    -- opportunistic: if the kit keeps its own tally (Buildings.ledgeLog's
    -- shape), print it. Nothing depends on it existing.
    for _, f in ipairs({ "log", "stats" }) do
      local v = ShopKit[f]
      if type(v) == "table" then
        local parts = {}
        for k2, v2 in pairs(v) do parts[#parts + 1] = k2 .. "=" .. tostring(v2) end
        table.sort(parts)
        log(("  ShopKit.%s: %s"):format(f, table.concat(parts, " ")))
      end
    end
  else
    skip("ShopKit built at least one model (ShopKit absent)")
    skip("ShopKit stamped at least one placement (ShopKit absent)")
  end

  log("  shader:", Voxel3D.shader() and "built" or "NIL (2D fallback!)",
      "error:", tostring(Voxel3D.shaderError))
  check(Voxel3D.shader() ~= nil and Voxel3D.shaderError == nil,
        "the scene shader is live")
  log(("  camera: mode=%s shot=%s"):format(
      tostring(MarioCam.cam.mode), MarioCam.cam.shot and "authored" or "none"))
  do
    local okF, on = pcall(FloorArt.on)
    local okP, prof = pcall(FloorArt.profile)
    log(("  floor art: on=%s profile=%s"):format(
        okF and tostring(on) or "?",
        (okP and prof) and tostring(prof.name) or "none"))
  end

  -- The SHADER's half of the room, which nothing checked until the
  -- anisotropic floor reflection went in and did nothing for three runs:
  -- the geometry can be perfect and every photograph loaded while the
  -- material pass is silently off, because `Voxel3D.stone` is what carries
  -- it and a missing file leaves that nil without an error anywhere.
  do
    local okSh, Shop = pcall(lib.require, "Shop")
    if okSh and Shop then
      local okM, mats = pcall(Shop.matsFor)
      mats = okM and mats or nil
      local st = Voxel3D.stone
      log(("  shop fx: row=%s materials=%s wall=%s hard=%s floorFlag=%s")
          :format(tostring(select(2, pcall(Shop.fxOn))),
                  tostring(mats ~= nil),
                  tostring(mats and mats.art ~= nil),
                  tostring(mats and mats.granite ~= nil),
                  tostring(mats and mats.shop)))
      -- THE DRAWN TILL, which must not stand inside the modelled one.
      -- The MART tileset authors a figure over tiles 14/15 + 30/31 (the
      -- till lib/RoomKit relied on), and Structures.buildFigures matches
      -- it by TILE PATTERN -- it knows nothing about what Buildings put on
      -- the cell. So with ShopKit modelling its own till, both were built
      -- and one stood inside the other. `m.noFigure` turns the figure off;
      -- this is the number that says it worked.
      local okF, SF = pcall(Structures.forMap, map)
      local nFig = (okF and SF and SF.figures) and #SF.figures or -1
      check(nFig == 0,
            ("no drawn figure inside the modelled till (figures=%d)")
              :format(nFig))
      log(("  Voxel3D.stone=%s lampSpec=%s lampNormals=%s normalsOK=%s")
          :format(st and "set" or "NIL", tostring(Voxel3D.lampSpec),
                  tostring(Voxel3D.lampNormals),
                  tostring(Voxel3D.normalsOK)))
      -- THE SUN PASS, which indoors is the room's only occluder. Two
      -- shears have to agree: ShadowMap's is what the depth map is DRAWN
      -- with, Voxel3D's is what the scene shader LOOKS IT UP with, and
      -- DayNight.applyRig sets both every frame. Setting one of them (the
      -- shop's near-vertical sun, first attempt) puts every lookup off its
      -- own texel, and the room comes back with NO shadow rather than a
      -- wrong one -- indistinguishable, on screen, from the feature being
      -- switched off. So it is asserted here rather than eyeballed.
      local okSm, ShadowMap = pcall(lib.require, "ShadowMap")
      local smkx = okSm and ShadowMap and ShadowMap.KX
      local smkz = okSm and ShadowMap and ShadowMap.KZ
      local vkx, vkz = Voxel3D.SHADOW_KX, Voxel3D.SHADOW_KZ
      local alpha = Voxel3D.SHADOW_ALPHA or 0
      -- ...and the two rows that own whether ANY of it lands. The split in
      -- lib/Light.lua is where a shadow's cost actually lives; sunDark is
      -- only the gate that says a map is worth sampling.
      local okL, Light = pcall(lib.require, "Light")
      local lightOn = okL and Light and select(2, pcall(Light.enabled))
      local okQ, Quality = pcall(lib.require, "Quality")
      local shq = okQ and Quality and Quality.shadowSetting
      local shqv = shq and select(2, pcall(shq.get, shq))
      log(("  sun pass: alpha=%.3f  map shear=(%s,%s)  lookup shear=(%s,%s)")
          :format(alpha, tostring(smkx), tostring(smkz),
                  tostring(vkx), tostring(vkz)))
      log(("  sun pass: LIGHT=%s  SHADOWS=%s  (a shadow costs nothing when "
           .. "LIGHT is FLAT)"):format(tostring(lightOn), tostring(shqv)))
      -- HOW FINE the pass can actually resolve a shadow in HERE. The
      -- frustum is fitted to the CAMERA's reach, which is a number sized
      -- for open country; a room is 128 world px across, so a fit meant
      -- for a route spends most of its texels on ground this map does not
      -- have. `extent / res` is world px per texel: over about 0.5 and a
      -- fixture 10 voxels tall cannot cast a shadow with an edge.
      if okSm and ShadowMap then
        local ext = ShadowMap.extent
        local res = ShadowMap.res or 0
        if ext and res > 0 then
          local perTexel = math.max(ext[1], ext[2]) / res
          log(("  sun map: res=%d  extent=%.0fx%.0fx%.0f world px  "
               .. "%.2f px/texel  slack=%.2f px  bias=%.5f")
              :format(res, ext[1], ext[2], ext[3], perTexel,
                      ShadowMap.slack or -1, ShadowMap.bias or -1))
          check(perTexel <= 0.75,
                ("the sun map resolves the room (%.2f world px per texel "
                 .. "<= 0.75)"):format(perTexel))
        else
          log("  sun map: extent/res unavailable")
        end
      end
      check(lightOn == true,
            "LIGHT is SKY -- otherwise the sun pass darkens nothing")
      local function near(a, b)
        return type(a) == "number" and type(b) == "number"
               and math.abs(a - b) < 1e-4
      end
      check(alpha > 0.001, "the sun pass casts at all (SHADOW_ALPHA > 0)")
      check(near(smkx, vkx) and near(smkz, vkz),
            "the two sun shears agree (map == lookup)")
      -- WHICH RUNG. The scene shader has a compatibility ladder and the
      -- photographic samplers are a COMPILE-TIME feature on it: a build
      -- that falls past the crypt rung still renders, still lays the floor
      -- art, and silently has no materials and no sheen at all. Nothing
      -- said so until the shop's floor reflection was invisible for four
      -- runs with every Lua-side check green.
      log(("  shader rung: %s (%d of %d)  refusals=%d")
          :format(tostring(select(2, pcall(Voxel3D.rungName))),
                  tonumber(Voxel3D.rung) or -1,
                  tonumber(Voxel3D.rungCount) or -1,
                  #(Voxel3D.compileLog or {})))
      for i, r in ipairs(Voxel3D.compileLog or {}) do
        if i > 4 then break end
        log(("    refused %s/%s: %s"):format(tostring(r.key),
            tostring(r.name), tostring(r.err):sub(1, 160)))
      end
      check(st ~= nil, "the shop's materials reached the shader")
      check(Voxel3D.normalsOK ~= false,
            "the build carries derivatives (the lamps' real face normal)")
    end
  end

  -- The cell grid, so a frame can be tied back to a cell without
  -- re-reading tools/interior_plan.py: '#' a cell the kit claimed,
  -- 'D' a door warp, '.' anything else.
  log("  cell grid (# claimed by a stamped model, D door):")
  do
    local function keyOf(tx, ty) return (ty + 64) * 4096 + (tx + 64) end
    local head = {}
    for cx = 0, CW - 1 do head[#head + 1] = tostring(cx % 10) end
    log("      " .. table.concat(head, " "))
    for cy = 0, CH - 1 do
      local row = {}
      for cx = 0, CW - 1 do
        local m = "."
        local s = okS and S.shapeAt[keyOf(cx * 2, cy * 2 + 1)] or nil
        if type(s) == "table" and s.class == "building" and s.authored then
          m = "#"
        end
        if warpCell[cx .. "," .. cy] then m = "D" end
        row[#row + 1] = m
      end
      log(("   %2d %s"):format(cy, table.concat(row, " ")))
    end
  end

  releaseDirs()
  wait(60)
  check(shot(first.name), "shot " .. first.name .. ": written")

  -- --------------------------------------------------- the other three --

  for i = 2, #ANCHORS do
    local a = ANCHORS[i]
    log("")
    local ax, ay = standAt(a.x, a.y, a.dir, a.name)
    if not ax then
      log(("[%s] FAIL: no standable cell near (%d,%d)"):format(a.name, a.x, a.y))
      fails[#fails + 1] = "anchor " .. a.name .. ": no standable cell"
    else
      log(("[%s] stood (%d,%d) facing %s -- %s"):format(
          a.name, ax, ay, a.dir, a.what))
      quadsUp(300)
      releaseDirs()
      wait(90)
      check(shot(a.name), "shot " .. a.name .. ": written")
    end
  end

  -- ----------------------------------------------- the dollhouse cut --
  --
  -- The one question a fixed diorama camera from the south has to answer:
  -- is the south wall CUT AWAY, or is the shopper looking at the back of
  -- it? So the camera is dropped almost to the floor and pushed outside
  -- the room's south edge -- if the wall is standing, this frame is a
  -- wall; if it is cut, this frame is the whole shop. The shot is
  -- injected into the cached camera_shots table for this run only (the
  -- crypt probe's HERO trick) and dropped again with reloadShots, so
  -- nothing is authored into data/.
  log("")
  log("[dollhouse] the low-angle cut: does the south wall hide the room?")
  MarioCam.reloadShots()
  local okData, camShots = pcall(lib.data, "camera_shots")
  if not (okData and type(camShots) == "table") then
    skip("dollhouse: camera_shots is unreadable")
  else
    local cam = {
      x = CW * 8, z = CH * 8, bx = CW * 16, bz = CH * 16,
      mode = "fixed",
      camX = CW * 8, camY = 26, camZ = CH * 16 + 104, focY = 18,
      fov = 55, frames = 8, flat = true,
    }
    local prev = camShots[MAP]
    camShots[MAP] = { cam }
    local hx, hy = standAt(dx + 2, CH - 1, "up", "dollhouse")
    if not hx then
      -- the south row is walkable end to end in the shipped Marts, so
      -- this only fires on a map shaped differently
      hx, hy = standAt(math.floor(CW / 2), CH - 2, "up", "dollhouse")
    end
    if not hx then
      log("  FAIL: no standable cell on the south row")
      fails[#fails + 1] = "anchor dollhouse: no standable cell"
    else
      quadsUp(300)
      releaseDirs()
      wait(90)
      local e = MarioCam.lakitu and MarioCam.lakitu.curPos
      log(("  stood (%d,%d)  eye %s fov %s  acquired=%s"):format(
          hx, hy,
          e and ("(%.0f, %.0f, %.0f)"):format(e[1], e[2], e[3]) or "nil",
          tostring(MarioCam.lakitu and MarioCam.lakitu.fov),
          tostring(MarioCam.cam.shot == cam)))
      -- If the shot was NOT acquired the frame is the ordinary interior
      -- camera, which answers a different question -- say so rather than
      -- letting the PNG be read as the dollhouse cut.
      if MarioCam.cam.shot ~= cam then
        log("  WARN: the injected shot was not acquired (SM64CAM off, or the")
        log("        voxel pass is down) -- this frame is NOT the low cut.")
      end
      check(shot("dollhouse"), "shot dollhouse: written")
    end
    camShots[MAP] = prev
    MarioCam.reloadShots()
  end

  -- ------------------------------------------------------- the hours --
  --
  -- Whether an interior answers the clock at all is itself the finding,
  -- so the tint is logged at every hour and the verdict on it is stated
  -- rather than asserted: a shop that pins its own ambient is a design
  -- decision, not a failure.
  log("")
  log("[hours] the room at " .. table.concat(HOURS, ", "))
  local tints = {}
  standAt(ANCHORS[1].x, ANCHORS[1].y, ANCHORS[1].dir, "room")
  quadsUp(300)
  for _, h in ipairs(HOURS) do
    pcall(function() DayNight.setting:sync(h) end)
    releaseDirs()
    wait(150)
    local t = Voxel3D.tint or { -1, -1, -1 }
    tints[h] = { t[1], t[2], t[3] }
    log(("  %-6s tint=%.3f,%.3f,%.3f  fog=%s"):format(
        h, t[1], t[2], t[3],
        Voxel3D.lastFog and ("%.2f"):format(Voxel3D.lastFog[3]) or "nil"))
    check(shot("room_" .. h), "shot room_" .. h .. ": written")
  end
  local spread = 0
  for _, a in pairs(tints) do
    for _, b in pairs(tints) do
      for i = 1, 3 do
        local d = math.abs(a[i] - b[i])
        if d > spread then spread = d end
      end
    end
  end
  log(("  INTERIOR LIGHT RESPONDS TO THE HOUR: %s (max tint spread %.3f)")
      :format(spread > 0.02 and "yes" or "no", spread))
  DayNight.setting:sync("day")

  -- ---------------------------------------------------------- the A/B --

  log("")
  if not DO_AB then
    log("[ab] skipped (SHOP_AB=0)")
    skip("A/B with the SHOP row off (SHOP_AB=0)")
  elseif not shopRow then
    log("[ab] the SHOP row does not exist yet -- nothing to force off.")
    log("  Today's frames above ARE the 'off' half: keep them, and re-run")
    log("  this probe once lib/ShopKit.lua lands to get the 'on' half.")
    skip("A/B with the SHOP row off (no ShopKit.setting)")
  else
    local values = shopRow.values or {}
    local target = nil
    for _, v in ipairs(values) do if v == AB_OFF then target = v end end
    if not target then
      target = values[#values]
      log(("[ab] %q is not on the row; using the last value %q instead")
          :format(AB_OFF, tostring(target)))
    end
    local was = nil
    pcall(function() was = shopRow:get() end)
    log(("[ab] SHOP %s -> %s"):format(tostring(was), tostring(target)))
    pcall(function() shopRow:sync(target) end)
    pcall(ChunkMesher.invalidate)
    Buildings.lastError = nil
    local bx, by = standAt(ANCHORS[1].x, ANCHORS[1].y, ANCHORS[1].dir, "ab")
    if bx then
      quadsUp(600)
      releaseDirs()
      wait(120)
      local m2 = kitStats()
      local p2 = stampCount()
      log(("  with the row off: kit models=%d placements=%d lastError=%s")
          :format(m2, p2, tostring(Buildings.lastError)))
      if ShopKit then
        check(m2 < models or models == 0,
              "the SHOP row off builds fewer models than on")
      else
        skip("the SHOP row off builds fewer models than on (ShopKit absent)")
      end
      check(shot("room_off"), "shot room_off: written")
      standAt(ANCHORS[2].x, ANCHORS[2].y, ANCHORS[2].dir, "ab")
      quadsUp(300)
      releaseDirs()
      wait(90)
      check(shot("wall_off"), "shot wall_off: written")
    else
      log("  FAIL: no standable cell for the A/B")
      fails[#fails + 1] = "A/B: no standable cell"
    end
    if was then pcall(function() shopRow:sync(was) end) end
    pcall(ChunkMesher.invalidate)
  end

  -- ------------------------------------------------------- the sun A/B --
  --
  -- The room's ONLY occluder, photographed on and off from the same cell,
  -- so "is there a shadow in here" is a difference of two PNGs rather than
  -- a judgement about a render. It is here because the answer was wrong
  -- twice by eye: the pass was running, every check was green, and the
  -- frames looked identical -- once because the two shears disagreed, and
  -- once because a vertical sun puts a fixture's shadow under itself.
  log("")
  log("[sun] the same cell with the sun pass off")
  do
    local okSh2, Shop2 = pcall(lib.require, "Shop")
    if not (okSh2 and Shop2 and Shop2.SHADOW_SCALE) then
      skip("A/B with the sun pass off (no Shop.SHADOW_SCALE)")
    else
      local keep = Shop2.SHADOW_SCALE
      log(("  SHADOW_SCALE %s -> 0"):format(tostring(keep)))
      Shop2.SHADOW_SCALE = 0
      local sx = standAt(ANCHORS[2].x, ANCHORS[2].y, ANCHORS[2].dir, "sun")
      if sx then
        quadsUp(300)
        releaseDirs()
        wait(90)
        check(shot("wall_sunoff"), "shot wall_sunoff: written")
      else
        log("  FAIL: no standable cell for the sun A/B")
        fails[#fails + 1] = "sun A/B: no standable cell"
      end
      Shop2.SHADOW_SCALE = keep
      wait(30)
    end
  end

  -- ----------------------------------------------------------- cost --

  log("")
  log("[cost] frame time in the room, vsync off")
  standAt(ANCHORS[1].x, ANCHORS[1].y, ANCHORS[1].dir, "cost")
  quadsUp(600)
  releaseDirs()
  wait(90)
  love.window.setVSync(0)
  local clock = love.timer.getTime
  local FRAMES = 200
  local dts, prev = {}, clock()
  for i = 1, FRAMES do
    coroutine.yield()
    local now = clock()
    dts[i] = now - prev
    prev = now
  end
  love.window.setVSync(1)
  table.sort(dts)
  local sum = 0
  for _, d in ipairs(dts) do sum = sum + d end
  local function pct(p)
    return dts[math.max(1, math.min(FRAMES, math.ceil(FRAMES * p)))]
  end
  local mean, p50, p95 = sum / FRAMES * 1000, pct(0.50) * 1000, pct(0.95) * 1000
  local okS2, S2 = pcall(Structures.forMap, game.overworld.map)
  log(("  %d frames: mean=%.2fms p50=%.2fms p95=%.2fms (objectQuads=%d)")
      :format(FRAMES, mean, p50, p95,
              (okS2 and S2) and #S2.objectQuads or -1))
  log(("  budget: mean <= %.1fms, p95 <= %.1fms (SHOP_BUDGET, SHOP_BUDGET_P95)")
      :format(BUDGET, BUDGET95))
  check(mean <= BUDGET, ("cost: mean %.2fms <= %.1fms"):format(mean, BUDGET))
  check(p95 <= BUDGET95, ("cost: p95 %.2fms <= %.1fms"):format(p95, BUDGET95))

  -- --------------------------------------------------------- verdict --

  log("")
  log("screenshots:")
  for _, s in ipairs(shots) do
    log(("  %-30s %s %d bytes"):format(
        s.name, (s.fired and s.size > 0) and "OK  " or "MISS", s.size))
  end
  log("")
  if not ShopKit then
    log("SHOPKIT ABSENT -- " .. #skips .. " kit checks were skipped, not passed.")
  end
  if #skips > 0 then
    log("SKIPPED (" .. #skips .. "):")
    for _, s in ipairs(skips) do log("  - " .. s) end
  end
  if #fails == 0 then
    log("ALL CHECKS PASSED")
  else
    log("FAILURES (" .. #fails .. "):")
    for _, f in ipairs(fails) do log("  - " .. f) end
  end
  logf:close()
  love.event.quit()
end
