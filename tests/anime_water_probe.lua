-- Probe: the ANIME water, the rings and the fishing float, in the real game.
--
-- For each map: stand on the bank that faces the most water, facing it; shoot
-- the idle sheet in ANIME, drop a few rings and shoot them spreading and
-- bouncing, switch to CLASSIC and do the same. The lake also gets a storm
-- (whitecaps), a dusk, and last of all a cast of the OLD ROD (it always
-- bites) shot through the float landing, the bite and the strike.
--
-- Logs what the shader built (and any refusal), what the ripple field did
-- (steps, uploads, peak) and what it COST: Ripples.update is wrapped and
-- timed per call while the field is awake.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> POKEPORT_SPEED=1 \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/anime_water_probe.lua ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/anime_water_probe.log", "w"))
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
  log("version:", exports.TERRARIUM.version)

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

  local function sync(setting, v)
    if setting then pcall(setting.sync, setting, v) end
  end
  sync(Weather.setting, "off")
  sync(DayNight.setting, "day")
  sync(Wind.setting, 2)          -- BREEZE
  sync(Quality.setting, 2)       -- RES 1/2
  sync(RayFX.setting, "rt")
  sync(Water.setting, "auto")
  sync(Water.style, "anime")
  pcall(Pipelines.setLevel, "terrarium_voxel", 5)
  log("window:", love.graphics.getWidth(), love.graphics.getHeight())

  -- the field's cost, per call while awake
  local cost = { n = 0, sum = 0, max = 0 }
  do
    local inner = Ripples.update
    Ripples.update = function(...)
      local t0 = love.timer.getTime()
      inner(...)
      local dt = love.timer.getTime() - t0
      if Ripples.live() then
        cost.n = cost.n + 1
        cost.sum = cost.sum + dt
        if dt > cost.max then cost.max = dt end
      end
    end
  end
  local function costLine(tag)
    log(("[%s] ripples: steps=%d uploads=%d pokes=%d recenters=%d peak=%.3f  cost %.3f ms/frame avg, %.3f max over %d awake frames"):format(
      tag, Ripples.steps, Ripples.uploads, Ripples.pokes, Ripples.recenters,
      Ripples.maxAbs or 0, cost.n > 0 and cost.sum / cost.n * 1000 or 0,
      cost.max * 1000, cost.n))
    cost.n, cost.sum, cost.max = 0, 0, 0
  end

  local function wait3D(cap)
    for i = 1, (cap or 900) do
      if Voxel3D.lampLights ~= nil then return i end
      coroutine.yield()
    end
    return -1
  end
  local function holdStill(frames)
    local p = game.overworld.player
    local lx, ly, same = nil, nil, 0
    for _ = 1, 600 do
      local x, y = p and p.cellX, p and p.cellY
      if x == lx and y == ly then same = same + 1 else same = 0 end
      lx, ly = x, y
      if same >= frames then return true end
      coroutine.yield()
    end
    return false
  end

  -- a walkable, dry cell with water right in front of it, scored by the water
  -- the camera will see (it looks north, the player sits high in the frame)
  local DIRS = { up = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 }, down = { 0, 1 } }
  local function bankFacing(m)
    local best, bestN = nil, 0
    local W, H = m.width or 40, m.height or 40
    for cy = 3, H - 3 do
      for cx = 3, W - 3 do
        if m:inBounds(cx, cy) and m:isWalkableCell(cx, cy) and not m:isWaterCell(cx, cy) then
          for face, d in pairs(DIRS) do
            local fx, fy = cx + d[1], cy + d[2]
            if m:inBounds(fx, fy) and m:isWaterCell(fx, fy)
               and m:inBounds(fx + d[1], fy + d[2]) and m:isWaterCell(fx + d[1], fy + d[2]) then
              local cnt = 0
              for dy = -3, 9 do
                for dx = -8, 8 do
                  local x, y = cx + dx, cy + dy
                  if m:inBounds(x, y) and m:isWaterCell(x, y) then cnt = cnt + 1 end
                end
              end
              if cnt > bestN then best, bestN = { cx, cy, face }, cnt end
            end
          end
        end
      end
    end
    return best, bestN
  end

  -- water cells near the player to drop rings on
  local function dropRings(map, at, k)
    local placed = 0
    for r = 2, 6 do
      for _, d in ipairs({ { 0, -1 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 1, -1 }, { -1, 1 } }) do
        local x, y = at[1] + d[1] * r, at[2] + d[2] * r
        if placed < k and map:inBounds(x, y) and map:isWaterCell(x, y) then
          Ripples.poke(x * 16 + 8, y * 16 + 8, -3.0, 6, 0.9)
          placed = placed + 1
        end
      end
    end
    return placed
  end

  local function report(tag)
    log(("[%s] shader=%s err=%s refused=%s rung=%s key-anime=%s"):format(
      tag, tostring(Voxel3D.shader() ~= nil), tostring(Voxel3D.shaderError),
      tostring(Voxel3D.animeWaterRefused), tostring(Voxel3D.rungName()),
      tostring(Water.anime())))
    for i, e in ipairs(Voxel3D.compileLog or {}) do
      log(("  refusal %d key=%s rung=%s prec=%s: %s"):format(i, tostring(e.key),
        tostring(e.name), tostring(e.prec), tostring(e.err):sub(1, 400)))
    end
  end

  -- the lake last: its rod ends the probe in a battle
  local MAPS = {
    { id = "PALLET_TOWN", tag = "pond" },
    { id = "ROUTE_21",    tag = "sea" },
    { id = "ROUTE_25",    tag = "lake", extra = true },
  }

  for _, m in ipairs(MAPS) do
    local ok = pcall(function() game.overworld:setMap(m.id, 5, 5, "up") end)
    if not ok then
      log(("[%s] SKIP: setMap failed"):format(m.id))
    else
      wait(30)
      local map = game.overworld.map
      local okB, at, cnt = pcall(bankFacing, map)
      if not (okB and at) then
        log(("[%s] SKIP: no bank (%s)"):format(m.id, tostring(at)))
      else
        log(("[%s] bank %d,%d facing %s, %d water cells in frame"):format(m.id, at[1], at[2], at[3], cnt))
        pcall(function() game.overworld:setMap(m.id, at[1], at[2], at[3]) end)
        Voxel3D.lampLights = nil
        local up = wait3D(900)
        holdStill(45)
        wait(150)
        log(("[%s] 3D up after %s frames"):format(m.id, tostring(up)))
        report(m.tag)
        sync(Water.style, "anime"); wait(20)
        shot(m.tag .. "_anime.png")
        log(("[%s] placed %d rings"):format(m.tag, dropRings(map, at, 3)))
        wait(24); shot(m.tag .. "_anime_rings.png")
        wait(50); shot(m.tag .. "_anime_rings_late.png")
        costLine(m.tag .. " anime")
        sync(Water.style, "classic"); wait(20)
        dropRings(map, at, 3)
        wait(24); shot(m.tag .. "_classic_rings.png")
        costLine(m.tag .. " classic")
        wait(200); shot(m.tag .. "_classic.png")
        log(("[%s] field asleep after: %s"):format(m.tag, tostring(not Ripples.live())))
        sync(Water.style, "anime"); wait(20)
        report(m.tag .. " back to anime")
        if m.extra then
          sync(Wind.setting, 4)            -- GALE
          sync(Weather.setting, "rain"); wait(420)
          shot(m.tag .. "_anime_storm.png")
          costLine(m.tag .. " storm")
          sync(Weather.setting, "off"); sync(Wind.setting, 2)
          sync(DayNight.setting, "dusk"); wait(300)
          shot(m.tag .. "_anime_dusk.png")
          sync(DayNight.setting, "day"); wait(300)
          -- THE ROD: the Old Rod always bites (engine: goFishing)
          local okF, errF = pcall(function() game.overworld:goFishing("OLD_ROD") end)
          log("[fish] goFishing:", okF, tostring(errF))
          local plan = { [118] = "fish_cast.png", [150] = "fish_float.png",
                         [196] = "fish_bite.png", [226] = "fish_strike.png" }
          for f = 1, 240 do
            coroutine.yield()
            if plan[f] then
              log(("[fish] frame %d state=%s ow.fishing=%s shake=%s"):format(f,
                tostring(FishFX.state()), tostring(game.overworld.fishing ~= nil),
                tostring(game.overworld.player.fishShakeDy)))
              shot(plan[f])
            end
          end
          log(("[fish] casts=%d bites=%d hooks=%d reels=%d err=%s"):format(
            FishFX.casts, FishFX.bites, FishFX.hooks, FishFX.reels, tostring(FishFX.lastError)))
          costLine("fish")
          return finish("done")
        end
      end
    end
  end
  finish("done")
end
