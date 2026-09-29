-- Probe: what the rings and the ANIME sheet LOOK like, framed to be judged.
--
-- The player surfs in the middle of the Route 25 lake (p.surfing + setMap on
-- a water cell with water all round), camera rung 4, wind OFF so no crest
-- foam muddies the rings. Shots:
--   idle      the swimmer's own bob, rings off the body
--   drop_*    one drop three cells north, at 0.3 / 0.8 / 1.6 s
--   classic   the same drop in CLASSIC
--   storm     GALE + rain, ANIME: whitecaps and rain rings
--   rod_*     from a bank, the OLD ROD, shot on EVENTS (cast / float /
--             bite / strike), not on frame counts
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> POKEPORT_SPEED=1 \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/ripple_look_probe.lua ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local ONLY = os.getenv("DS_ONLY")          -- "rings" / "storm" / "rod"
  local logf = assert(io.open(OUT .. "/ripple_look_probe.log", "w"))
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
    log("shot", name, done and "ok" or "TIMEOUT")
  end
  local function finish(msg)
    if msg then log(msg) end
    logf:close()
    love.event.quit()
  end
  local function want(k) return (not ONLY) or ONLY:find(k, 1, true) ~= nil end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then return finish("FAIL: no overworld") end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end
  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then return finish("FAIL: TERRARIUM not loaded") end

  local Water = lib.require("Water")
  local RayFX = lib.require("RayFX")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Wind = lib.require("Wind")
  local Quality = lib.require("Quality")
  local Voxel3D = lib.require("Voxel3D")
  local Ripples = lib.require("Ripples")
  local FishFX = lib.require("FishFX")
  local Pipelines = require("src.render.Pipelines")
  local function sync(setting, v) if setting then pcall(setting.sync, setting, v) end end
  sync(Weather.setting, "off")
  sync(DayNight.setting, "day")
  sync(Wind.setting, 0)          -- OFF: nothing but the rings
  sync(Quality.setting, 2)
  sync(RayFX.setting, "rt")
  sync(Water.setting, 0.8)
  sync(Water.style, "anime")
  pcall(Pipelines.setLevel, "terrarium_voxel", 4)

  local function wait3D(cap)
    for i = 1, (cap or 900) do
      if Voxel3D.lampLights ~= nil then return i end
      coroutine.yield()
    end
    return -1
  end
  local function waterAround(m, cx, cy, r)
    for dy = -r, r do
      for dx = -r, r do
        if not (m:inBounds(cx + dx, cy + dy) and m:isWaterCell(cx + dx, cy + dy)) then return false end
      end
    end
    return true
  end

  local SEA = os.getenv("DS_SEA") or "ROUTE_21"
  local LAKE = os.getenv("DS_LAKE") or "ROUTE_25"
  local p = game.overworld.player
  local map
  local function goMap(id)
    local ok = pcall(function() game.overworld:setMap(id, 5, 5, "up") end)
    wait(30)
    map = game.overworld.map
    return ok
  end
  -- map.width is not a field; the def carries it in 2x2 BLOCKS
  local function cellsW() return math.floor((map.def and map.def.width or 20) * 2) end
  local function cellsH() return math.floor((map.def and map.def.height or 20) * 2) end

  -- ------- rings, from the middle of the lake
  if want("rings") or want("storm") then
    if not goMap(SEA) then return finish("FAIL: setMap " .. SEA) end
    local at
    log("map", SEA, "size", cellsW(), cellsH())
    for r = 4, 1, -1 do
      for cy = r + 1, cellsH() - r - 1 do
        for cx = r + 1, cellsW() - r - 1 do
          if not at and waterAround(map, cx, cy, r) then at = { cx, cy } end
        end
      end
      if at then log("open water radius", r) break end
    end
    if not at then return finish("FAIL: no open water cell") end
    log("surf at", at[1], at[2])
    p.surfing = true
    pcall(function() game.overworld:setMap(SEA, at[1], at[2], "down") end)
    p.surfing = true
    Voxel3D.lampLights = nil
    log("3D up after", wait3D(900))
    wait(180)
    log("player", p.cellX, p.cellY, "surfing", tostring(p.surfing), "onWater", tostring(p.onWater))
    local cx, cz = p.cellX * 16 + 8, p.cellY * 16 + 8
    if want("rings") then
      shot("idle_anime.png")
      -- the field along a line east of the drop, so a shot can be read
      -- against what the texture holds
      local function profile(tag, x0, z0)
        local parts = {}
        for d = 0, 72, 6 do
          parts[#parts + 1] = ("%d:%.2f"):format(d, Ripples.heightAt(x0 + d, z0))
        end
        log(tag, "live=" .. tostring(Ripples.live()), table.concat(parts, " "))
      end
      local dz = cz - 48
      for _, style in ipairs({ "anime", "classic" }) do
        sync(Water.style, style); wait(30)
        Ripples.poke(cx, dz, -3.0, 6, 0.9)
        wait(18); profile("drop03 " .. style, cx, dz); shot("drop03_" .. style .. ".png")
        wait(30); profile("drop08 " .. style, cx, dz); shot("drop08_" .. style .. ".png")
        wait(48); profile("drop16 " .. style, cx, dz); shot("drop16_" .. style .. ".png")
      end
      sync(Water.style, "anime"); wait(30)
      -- orientation: where do the player, a point north and a point east land
      -- on screen (canvas px scaled to the window)
      local function scr(tag, x, z)
        local sx, sy = Voxel3D.project(x, -2, z)
        log(("  %s world %d,%d -> canvas %s,%s"):format(tag, x, z, tostring(sx and math.floor(sx)), tostring(sy and math.floor(sy))))
      end
      log("canvas vs window", love.graphics.getWidth(), love.graphics.getHeight())
      scr("player", cx, cz); scr("north48", cx, cz - 48); scr("east64", cx + 64, cz)
      sync(RayFX.setting, "off"); wait(30)
      Ripples.poke(cx, cz - 48, -14.0, 10, 1.0)
      wait(20); profile("huge north", cx, cz - 48); shot("huge_north_nofx.png")
      wait(120)
      Ripples.poke(cx + 64, cz, -14.0, 10, 1.0)
      wait(20); profile("huge east", cx + 64, cz); shot("huge_east_nofx.png")
      sync(RayFX.setting, "rt")
    end
    if want("storm") then
      sync(Wind.setting, 4)
      sync(Weather.setting, "rain")
      wait(480)
      shot("storm_anime.png")
      sync(Water.style, "classic"); wait(30)
      shot("storm_classic.png")
      sync(Water.style, "anime")
      sync(Weather.setting, "off"); sync(Wind.setting, 0)
      wait(240)
    end
    log(("ripples: steps=%d uploads=%d pokes=%d peak=%.3f"):format(
      Ripples.steps, Ripples.uploads, Ripples.pokes, Ripples.maxAbs or 0))
  end

  -- ------- the rod, from a bank
  if want("rod") then
    if not goMap(LAKE) then return finish("FAIL: setMap " .. LAKE) end
    local best
    local DIRS = { up = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }
    for cy = 3, cellsH() - 3 do
      for cx = 3, cellsW() - 3 do
        if not best and map:isWalkableCell(cx, cy) and not map:isWaterCell(cx, cy) then
          for face, d in pairs(DIRS) do
            -- what the engine asks (the cell ahead is water) and room for
            -- the float to land in
            if not best and map:isWaterCell(cx + d[1], cy + d[2])
               and waterAround(map, cx + d[1] * 3, cy + d[2] * 3, 1) then
              best = { cx, cy, face }
            end
          end
        end
      end
    end
    if not best then return finish("FAIL: no bank") end
    p.surfing = false
    pcall(function() game.overworld:setMap(LAKE, best[1], best[2], best[3]) end)
    Voxel3D.lampLights = nil
    log("rod bank", best[1], best[2], best[3], "3D up after", wait3D(900))
    wait(120)
    local okF, errF = pcall(function() game.overworld:goFishing("OLD_ROD") end)
    log("goFishing:", okF, tostring(errF))
    local shotFloat, shotBite, shotStrike, shotCast = false, false, false, false
    local tFloat
    for f = 1, 900 do
      coroutine.yield()
      local st = FishFX.state()
      if st == "fly" and not shotCast then shotCast = true; wait(8); shot("rod_cast.png") end
      if st == "float" and not tFloat then tFloat = f end
      if tFloat and not shotFloat and f - tFloat >= 40 then shotFloat = true; shot("rod_float.png") end
      if FishFX.bites > 0 and not shotBite then shotBite = true; wait(2); shot("rod_bite.png") end
      if st == "strike" and not shotStrike then shotStrike = true; wait(4); shot("rod_strike.png") end
      if shotStrike then break end
    end
    log(("rod: casts=%d bites=%d hooks=%d reels=%d state=%s err=%s"):format(
      FishFX.casts, FishFX.bites, FishFX.hooks, FishFX.reels,
      tostring(FishFX.state()), tostring(FishFX.lastError)))
  end
  finish("done")
end
