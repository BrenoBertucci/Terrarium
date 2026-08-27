-- T12: water spray, measured.
--
--   SITES     the shore scan finds the water's edge (Pallet's sea)
--   WHIPS     under GALE the shore band emits within a ten-second window
--   ORIGIN    young water-born motes sit within a spawn's reach of a
--             real shore site
--   SIZE LAW  the same gale over Viridian's pond emits a fraction of
--             what the sea does -- WaterBody.sizeAt as probability,
--             measured, not assumed. Sizes are logged either way: if the
--             bake reads both bodies alike, the numbers say so.
--   FLOOR     wind row OFF: nothing, and the gate says why
--   CLEAN     no errors, canaries alive
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/spray_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/spray.log", "w"))
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

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit() return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end
  log("version:", exports.TERRARIUM.version)

  local Weather  = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Wind     = lib.require("Wind")
  local WindFX   = lib.require("WindFX")
  local SprayFX  = lib.require("SprayFX")
  local WaterBody = lib.require("WaterBody")
  local AmbientLife = lib.require("AmbientLife")
  local Quality  = lib.require("Quality")
  local Voxel3D  = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")

  Weather.setting:sync("off")
  Wind.setting:sync(4)
  AmbientLife.setting:sync("off")
  Quality.particleSetting:sync(1)
  Pipelines.setLevel("terrarium_voxel", 4)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  DayNight.setting:sync("day")
  local ow = game.overworld

  -- Arrive, let the scan run, and if no shore is in range step the player
  -- inland of the nearest site -- works on any map with water at all.
  local function standNearWater(mapId, cx, cy)
    local okM = pcall(function() ow:setMap(mapId, cx, cy, "up") end)
    if not okM then return 0 end
    wait(400)
    wait(20)
    local S = SprayFX.sites.shore
    if #S == 0 then return 0 end
    local p = ow.player
    local px, pz = (p.px or 0) + 8, (p.py or 0) + 8
    local function inRange()
      local c = 0
      for i = 1, #S do
        if math.abs(S[i].x - px) <= SprayFX.RANGE
           and math.abs(S[i].z - pz) <= SprayFX.RANGE then c = c + 1 end
      end
      return c
    end
    -- Relocate to the best shore ALWAYS, and prefer one whose land is
    -- SOUTH of the water (normal nz > 0.5): the camera sits south of the
    -- player looking north, so water north of the player is in front of
    -- it and water south is behind it -- the first hunt on Route 19
    -- emitted plenty and photographed none, every wet cell off frustum.
    local best, bd = nil, 1e9
    for pass = 1, 2 do
      for i = 1, #S do
        local s = S[i]
        if pass == 2 or s.nz > 0.5 then
          local d = math.max(math.abs(s.x - px), math.abs(s.z - pz))
          if d < bd then best, bd = s, d end
        end
      end
      if best then break end
    end
    if best then
      local tx = math.floor((best.x + best.nx * 40) / 16)
      local tz = math.floor((best.z + best.nz * 40) / 16)
      pcall(function() ow:setMap(mapId, tx, tz, "up") end)
      wait(200)
      p = ow.player
      px, pz = (p.px or 0) + 8, (p.py or 0) + 8
    end
    return inRange(), px, pz
  end

  -- both numbers: at the band (where fetch dies by design) and offshore
  -- (what the emitter actually rolls)
  local function meanSize(px, pz)
    local S = SprayFX.sites.shore
    local sumAt, sumOff, c = 0, 0, 0
    for i = 1, #S do
      local s = S[i]
      if math.abs(s.x - px) <= SprayFX.RANGE
         and math.abs(s.z - pz) <= SprayFX.RANGE then
        sumAt = sumAt + WaterBody.sizeAt(s.x, s.z)
        sumOff = sumOff + WaterBody.sizeAt(s.x - s.nx * SprayFX.OFFSHORE,
                                           s.z - s.nz * SprayFX.OFFSHORE)
        c = c + 1
      end
    end
    if c == 0 then return -1, -1, 0 end
    return sumAt / c, sumOff / c, c
  end

  -- window: count emissions and check origins; rings + shot at the end
  local function window(px, pz, shotName)
    local e0 = SprayFX.emitted
    local checked, violations, worst = 0, 0, 0
    for i = 1, 600 do
      coroutine.yield()
      if i % 10 == 0 then
        for j = 1, WindFX.count() do
          local m = WindFX.get(j)
          if m and m.src == "water" and m.t < 0.15 then
            local best = 1e9
            local S = SprayFX.sites.shore
            for k = 1, #S do
              local d = math.max(math.abs(m.x - S[k].x),
                                 math.abs(m.z - S[k].z))
              if d < best then best = d end
            end
            checked = checked + 1
            if best > worst then worst = best end
            if best > 24 then violations = violations + 1 end
          end
        end
      end
    end
    if shotName then
      for j = 1, WindFX.count() do
        local m = WindFX.get(j)
        if m and m.src == "water" then
          local mx, my = Voxel3D.project(m.x, m.y, m.z)
          if mx and my then
            log(("MOTE %d %d"):format(math.floor(mx), math.floor(my)))
          end
        end
      end
      shot(shotName)
    end
    return SprayFX.emitted - e0, checked, violations, worst
  end

  -- ------- THE SEA. Route 19 is open ocean with a walkable north
  -- beach; Pallet's strip measured sizeAt 0.12 -- a sliver, honestly
  -- called small by the bake -- so it is the fallback, not the fixture.
  local irSea, spx, spz = standNearWater("ROUTE_19", 9, 3)
  if (irSea or 0) == 0 then
    log("ROUTE_19 gave no reachable shore; falling back to PALLET_TOWN")
    irSea, spx, spz = standNearWater("PALLET_TOWN", 12, 12)
  end
  log(("sea: %d shore sites, %d in range  WaterBody.on %s")
      :format(#SprayFX.sites.shore, irSea or 0, tostring(WaterBody.on())))
  local szSeaAt, szSea = meanSize(spx or 0, spz or 0)
  local seaEmit, chk, vio, worst = window(spx, spz, nil)
  -- ------- the picture is a MOMENT, not an endpoint: spray lives 0.7-1.6s
  -- and rides a gale, so the end of a window holds one or two motes
  -- already gone off frame (measured). Hunt the instant two are visible.
  do
    local hunted = false
    for tick = 1, 900 do
      coroutine.yield()
      local want = tick <= 450 and 2 or 1
      local vis = {}
      for j = 1, WindFX.count() do
        local m = WindFX.get(j)
        if m and m.src == "water" then
          local mx, my = Voxel3D.project(m.x, m.y, m.z)
          if mx and my and mx > 40 and mx < 1500 and my > 40 and my < 830 then
            vis[#vis + 1] = { mx, my }
          end
        end
      end
      if #vis >= want then
        for _, v in ipairs(vis) do
          log(("MOTE %d %d"):format(math.floor(v[1]), math.floor(v[2])))
        end
        shot("spray_sea.png")
        hunted = true
        break
      end
    end
    if not hunted then
      log("shot: no two-visible-spray moment in 900 ticks")
      shot("spray_sea.png")
    end
  end
  log(("sea: mean sizeAt band %.2f offshore %.2f  emissions/10s %d")
      :format(szSeaAt, szSea, seaEmit))
  log(("origin: %d young water motes, worst shore distance %.1f, "
       .. "violations %d  %s")
      :format(chk, worst, vio,
              (chk >= 3 and vio == 0) and "PASS" or "FAIL"))
  log(("sea verdict: %s"):format((irSea > 0 and seaEmit > 4) and "PASS" or "FAIL"))

  -- ------- THE POND (Viridian)
  local irPond, ppx, ppz = standNearWater("VIRIDIAN_CITY", 10, 10)
  log(("pond: %d shore sites, %d in range")
      :format(#SprayFX.sites.shore, irPond or 0))
  if (irPond or 0) > 0 then
    local szPondAt, szPond = meanSize(ppx, ppz)
    local pondEmit = window(ppx, ppz, nil)
    log(("pond: mean sizeAt band %.2f offshore %.2f  emissions/10s %d")
        :format(szPondAt, szPond, pondEmit))
    log(("size law: sea %d @size %.2f  vs  pond %d @size %.2f  %s")
        :format(seaEmit, szSea, pondEmit, szPond,
                (pondEmit * 3 <= seaEmit) and "PASS" or "FAIL"))
  else
    log("size law: SKIP (no pond shore in range)")
  end

  -- ------- FLOOR
  do
    Wind.setting:sync(0)
    wait(60)
    local e1 = SprayFX.emitted
    wait(300)
    log(("floor: %d emissions with the row OFF  gate [%s]  %s")
        :format(SprayFX.emitted - e1, tostring(SprayFX.lastGate),
                (SprayFX.emitted - e1 == 0
                 and SprayFX.lastGate == "wind below FLOOR")
                and "PASS" or "FAIL"))
    Wind.setting:sync(4)
  end

  log(("errors: %s (%d)"):format(tostring(SprayFX.lastError),
                                 SprayFX.errorCount))
  log(("canaries: SprayFX.ticks %d live %d  Weather.ticks %s ok %s")
      :format(SprayFX.ticks, SprayFX.ticksLive,
              tostring(Weather.ticks), tostring(Weather.ticksOk)))
  log("done")
  logf:close()
  love.event.quit()
end
