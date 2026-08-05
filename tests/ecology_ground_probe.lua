-- Probe: the three additions of 1.13.0, exercised on a running game.
--
--   13  ecology / the hour     the same route's table drawn two thousand
--                              times at noon and at midnight, and the two
--                              distributions printed side by side -- so
--                              "the night Pokemon come out" is a COLUMN OF
--                              NUMBERS rather than an impression
--   14  ecology / the rain     water types up under a downpour, and the
--                              come-ashore roll counted against a real cell
--                              next to real water on a real route
--   15  ground fx              the ground soaking and drying on its own
--                              clock, the decal meshes counted through a
--                              real frame, and footprints counted after the
--                              player actually walks
--
-- Screenshots beside the log, because a visual feature is not done until it
-- has been seen (the battle-HUD ink lesson: a marker that draws nothing
-- draws nothing silently).
--
--   POKEPORT_VERSION=yellow \
--   DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/ecology_ground_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/ecology_ground_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n")
    logf:flush()
  end
  local function wait(n)
    for _ = 1, n do coroutine.yield() end
  end
  local function tap(btn)
    game.input.pressQueue[#game.input.pressQueue + 1] = btn
    coroutine.yield()
  end
  local function shot(name)
    local path = OUT .. "/" .. name
    love.graphics.captureScreenshot(function(data)
      local f = io.open(path, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
    wait(3)
  end

  love.math.setRandomSeed(20260801)

  -- ------- reach free roam
  local frames = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); frames = frames + 1
    if frames > 900 then log("FAIL: no overworld") logf:close()
      love.event.quit() return end
  end
  frames = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); frames = frames + 11
    if frames > 1500 then log("FAIL: never reached free roam") break end
  end
  log("free roam:", game.stack:top() == game.overworld)

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded")
    logf:close(); love.event.quit(); return
  end
  log("version:", exports.TERRARIUM.version)

  local Ecology = lib.require("Ecology")
  local GroundFX = lib.require("GroundFX")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local WildRoamers = lib.require("WildRoamers")
  local Pipelines = require("src.render.Pipelines")

  local function teleport(mapId, x, y, facing)
    game.overworld:setMap(mapId, x, y, facing or "down")
    wait(90)
  end

  -- =====================================================================
  log("")
  log("== 13. ecology: the hour ==")

  Ecology.setting:sync("on")
  Weather.setting:sync("off")
  Pipelines.setLevel("terrarium_voxel", 5)
  teleport("ROUTE_4", 10, 8, "down")
  wait(120)

  local encDef = game.data.encounters["ROUTE_4"]
  if not (encDef and encDef.grass) then
    log("FAIL: ROUTE_4 has no grass table")
  end

  -- The table itself, and what this mod thinks of each name on it.
  local seen = {}
  for _, slot in ipairs(encDef.grass.slots or {}) do
    seen[slot.species] = true
  end
  local names = {}
  for s in pairs(seen) do names[#names + 1] = s end
  table.sort(names)

  local function distribution(n)
    local tally = {}
    for _ = 1, n do
      local slot = Ecology.pick(encDef.grass, "grass")
      if slot then tally[slot.species] = (tally[slot.species] or 0) + 1 end
    end
    return tally
  end

  local N = 4000
  DayNight.setting:sync("day")
  wait(4)
  log("period at DAY pin:", Ecology.period())
  local byDay = distribution(N)
  DayNight.setting:sync("night")
  wait(4)
  log("period at NIGHT pin:", Ecology.period())
  local byNight = distribution(N)
  Ecology.setting:sync("off")
  local flat = distribution(N)
  Ecology.setting:sync("on")

  log("")
  log(("%-12s %6s %8s %8s %8s   %s"):format(
    "species", "lean", "OFF", "day", "night", "verdict"))
  for _, s in ipairs(names) do
    DayNight.setting:sync("day")
    local lean = Ecology.lean(s)
    local d, n2, f = byDay[s] or 0, byNight[s] or 0, flat[s] or 0
    local verdict = "-"
    if lean < -0.05 then
      verdict = (n2 > d) and "night up  OK" or "  FAIL: not nocturnal"
    elseif lean > 0.05 then
      verdict = (d > n2) and "day up    OK" or "  FAIL: not diurnal"
    end
    log(("%-12s %6.2f %8d %8d %8d   %s"):format(s, lean, f, d, n2, verdict))
  end

  -- and that the SET did not change: everything drawn is on the table, and
  -- nothing on the table has been deleted from either half of the day
  local strayed, vanished = 0, 0
  for s in pairs(byNight) do if not seen[s] then strayed = strayed + 1 end end
  for s in pairs(byDay) do if not seen[s] then strayed = strayed + 1 end end
  for _, s in ipairs(names) do
    if (byDay[s] or 0) == 0 or (byNight[s] or 0) == 0 then
      vanished = vanished + 1
      log(("  note: %s reached 0 in %d draws"):format(s, N))
    end
  end
  log(("species off the table: %d (want 0); species deleted by an hour: %d")
      :format(strayed, vanished))
  if strayed > 0 then log("  FAIL: a species not on ROUTE_4's table appeared") end

  -- =====================================================================
  log("")
  log("== 14. ecology: the rain ==")

  -- A route with water on it, and a land cell within reach of that water --
  -- found by looking rather than by a coordinate written down here, so this
  -- keeps working on a dataset whose maps are drawn differently.
  local function bankCell(mapId)
    teleport(mapId, 5, 5, "down")
    local map = game.overworld.map
    for cy = 0, (map.height or 40) - 1 do
      for cx = 0, (map.width or 40) - 1 do
        if map:inBounds(cx, cy) and map:isWalkableCell(cx, cy)
           and not map:isWaterCell(cx, cy) then
          for dy = -3, 3 do
            for dx = -3, 3 do
              if map:inBounds(cx + dx, cy + dy)
                 and map:isWaterCell(cx + dx, cy + dy) then
                return map, cx, cy
              end
            end
          end
        end
      end
    end
    return map, nil, nil
  end

  local map, bx, by = bankCell("ROUTE_6")
  log(("ROUTE_6 bank cell: %s,%s"):format(tostring(bx), tostring(by)))
  local roster = Ecology.waterRoster("ROUTE_6")
  log(("ROUTE_6 water roster: %d entries"):format(roster and #roster or 0))
  if roster then
    local list = {}
    for _, s in ipairs(roster) do list[#list + 1] = s.species .. "@" .. s.level end
    log("  " .. table.concat(list, " "))
  end

  Weather.setting:sync("rain")
  wait(780)                       -- BUILD is 7s; twelve for a settled peak
  local kind, power = Weather.falling()
  log(("falling: kind=%s power=%.2f visible=%s"):format(
    tostring(kind), power, tostring((Weather.visible()))))

  if bx then
    local up, dry = 0, 0
    local kinds = {}
    for _ = 1, 3000 do
      local slot = Ecology.ashore(map, bx, by, "grass")
      if slot then
        up = up + 1
        kinds[slot.species] = (kinds[slot.species] or 0) + 1
      else
        dry = dry + 1
      end
    end
    log(("came ashore in 3000 land spawns: %d (%.1f%%)"):format(
      up, up / 30))
    local parts = {}
    for s, n in pairs(kinds) do parts[#parts + 1] = ("%s x%d"):format(s, n) end
    table.sort(parts)
    log("  " .. table.concat(parts, ", "))
    if up == 0 then log("  FAIL: nothing came ashore in a downpour") end

    -- and the level is the ROUTE's, not the fish roster's
    local lo, hi = 99, 0
    for _ = 1, 500 do
      local slot = Ecology.ashore(map, bx, by, "grass")
      if slot then
        if slot.level < lo then lo = slot.level end
        if slot.level > hi then hi = slot.level end
      end
    end
    local land = { 99, 0 }
    for _, s in ipairs(game.data.encounters.ROUTE_6.grass.slots) do
      if s.level < land[1] then land[1] = s.level end
      if s.level > land[2] then land[2] = s.level end
    end
    log(("ashore levels %d..%d against ROUTE_6's own grass %d..%d"):format(
      lo, hi, land[1], land[2]))
    if lo < land[1] or hi > land[2] then
      log("  FAIL: an arrival is outside the route's own level band")
    end

    -- and NOTHING comes ashore once it stops
    Weather.setting:sync("off")
    wait(900)
    local afterDry = 0
    for _ = 1, 2000 do
      if Ecology.ashore(map, bx, by, "grass") then afterDry = afterDry + 1 end
    end
    log(("came ashore with a clear sky: %d (want 0)"):format(afterDry))
    if afterDry > 0 then log("  FAIL: arrivals without rain") end
  else
    log("FAIL: no bank cell found on ROUTE_6")
  end

  -- the reweighting itself, measured on a table that HAS a water type
  do
    Weather.setting:sync("off")
    wait(600)
    local dryW = Ecology.weight("POLIWAG", "grass")
    Weather.setting:sync("rain")
    wait(780)
    local wetW = Ecology.weight("POLIWAG", "grass")
    local fireDry, fireWet = 0, 0
    Weather.setting:sync("off"); wait(600)
    fireDry = Ecology.weight("GROWLITHE", "grass")
    Weather.setting:sync("rain"); wait(780)
    fireWet = Ecology.weight("GROWLITHE", "grass")
    log(("POLIWAG   weight dry=%.2f  raining=%.2f"):format(dryW, wetW))
    log(("GROWLITHE weight dry=%.2f  raining=%.2f"):format(fireDry, fireWet))
    if wetW <= dryW then log("  FAIL: rain did not favour the water type") end
    if fireWet >= fireDry then log("  FAIL: rain did not discourage the fire type") end
  end

  -- =====================================================================
  log("")
  log("== 15. ground fx ==")

  GroundFX.setting:sync("on")
  Weather.setting:sync("off")
  DayNight.setting:sync("day")
  for _, layer in ipairs({ "puddle", "drift", "print_" }) do
    log(("%-7s art: %s"):format(
      layer, GroundFX.usingArt(layer) and "assets/ground (drawn)"
                                       or "generated"))
  end
  -- the real clocks are minutes long on purpose; the probe is not
  GroundFX.SOAK, GroundFX.DRY = 3, 8
  GroundFX.SETTLE, GroundFX.MELT = 3, 12
  teleport("ROUTE_1", 8, 12, "up")
  wait(600)
  log(("dry start: wet=%.2f cover=%.2f draws=%d"):format(
    GroundFX.wetness(), GroundFX.cover(), GroundFX.lastDraws))
  shot("30_dry_route1.png")

  Weather.setting:sync("rain")
  wait(700)
  log(("raining:   wet=%.2f cover=%.2f draws=%d"):format(
    GroundFX.wetness(), GroundFX.cover(), GroundFX.lastDraws))
  if GroundFX.wetness() < 0.5 then log("  FAIL: the ground never got wet") end
  if GroundFX.lastDraws == 0 then log("  FAIL: no puddle meshes drawn") end
  shot("31_wet_route1.png")

  -- ------- and the same frame with the row off, because A SIDE BY SIDE is
  -- the only way to answer "is that visible": a decal that draws nothing
  -- draws nothing silently, and a screenshot of a world with weather in it
  -- looks like a screenshot of a world.
  --
  -- The spot is FOUND rather than written down. A coordinate typed into a
  -- probe is a coordinate that is wrong on the next dataset, and the two
  -- shots this took at a guessed one came back black -- which looks exactly
  -- like the feature drawing nothing.
  local function openSpot(mapId)
    game.overworld:setMap(mapId, 5, 5, "down")
    wait(60)
    local m = game.overworld.map
    local bx2, by2, best = nil, nil, -1
    for cy = 2, (m.height or 20) - 3 do
      for cx = 2, (m.width or 20) - 3 do
        if m:isWalkableCell(cx, cy) and not m:isGrassCell(cx, cy)
           and not m:isWaterCell(cx, cy) and not m:warpAtCell(cx, cy) then
          local n = 0
          for dy = -2, 2 do
            for dx = -2, 2 do
              if m:inBounds(cx + dx, cy + dy)
                 and m:isWalkableCell(cx + dx, cy + dy)
                 and not m:isGrassCell(cx + dx, cy + dy) then n = n + 1 end
            end
          end
          if n > best then bx2, by2, best = cx, cy, n end
        end
      end
    end
    return bx2, by2, best
  end

  local tx, ty, open = openSpot("VIRIDIAN_CITY")
  log(("VIRIDIAN_CITY open spot: %s,%s (%s clear cells around it)"):format(
    tostring(tx), tostring(ty), tostring(open)))
  teleport("VIRIDIAN_CITY", tx or 10, ty or 10, "down")
  wait(200)
  GroundFX.setting:sync("off")
  wait(30)
  shot("31a_town_ground_OFF.png")
  GroundFX.setting:sync("on")
  wait(30)
  log(("town A/B: wet=%.2f draws=%d"):format(
    GroundFX.wetness(), GroundFX.lastDraws))
  shot("31b_town_ground_ON_puddles.png")
  teleport("ROUTE_1", 8, 12, "up")
  wait(150)

  -- the aftermath, which is the whole feature: the sky clears and the
  -- ground is still wet
  Weather.setting:sync("off")
  wait(240)
  log(("just cleared: wet=%.2f draws=%d falling=%s"):format(
    GroundFX.wetness(), GroundFX.lastDraws, tostring((Weather.falling()))))
  if GroundFX.wetness() < 0.4 then
    log("  FAIL: the ground dried the moment the rain stopped")
  end
  shot("32_puddles_after_rain.png")

  wait(900)
  log(("long after:  wet=%.2f draws=%d"):format(
    GroundFX.wetness(), GroundFX.lastDraws))
  if GroundFX.wetness() > 0.05 then log("  note: still drying") end

  -- ------- indoors it is dry, however hard it is raining outside
  Weather.setting:sync("rain")
  wait(700)
  teleport("REDS_HOUSE_1F", 3, 5, "down")
  wait(120)
  log(("indoors in a downpour: wet=%.2f draws=%d (want draws=0)"):format(
    GroundFX.wetness(), GroundFX.lastDraws))
  if GroundFX.lastDraws > 0 then log("  FAIL: puddles indoors") end

  -- ------- snow, drifts and footprints
  teleport("VIRIDIAN_CITY", tx or 10, ty or 10, "down")
  Weather.setting:sync("snow")
  wait(700)
  log(("snowing: cover=%.2f draws=%d"):format(
    GroundFX.cover(), GroundFX.lastDraws))
  if GroundFX.cover() < 0.5 then log("  FAIL: no snow settled") end
  GroundFX.setting:sync("off")
  wait(30)
  shot("33a_snow_ground_OFF.png")
  GroundFX.setting:sync("on")
  wait(30)
  shot("33b_snow_ground_ON_drifts.png")

  -- The PLAYER's own prints, counted apart from everybody else's: a route
  -- with ten wild Pokemon wandering it makes marks all by itself, and a
  -- total that a Rattata can move is not a measurement of whether walking
  -- leaves a trail.
  local before = GroundFX.myPrintCount()
  -- walked through the input state rather than by moving the player by
  -- assignment: a print is dropped by NOTICING a step, and an assignment is
  -- not a step. The DIRECTION is tried rather than chosen -- a probe that
  -- walks into a wall and then reports no footprints has measured the wall.
  local pl = game.overworld.player
  local walked, went = 0, "-"
  local home = game.overworld.map.id
  for _, dir in ipairs({ "up", "down", "left", "right" }) do
    local x0, y0 = pl.cellX, pl.cellY
    for _ = 1, 5 do
      game.input.state[dir] = true
      wait(14)
      game.input.state[dir] = false
      wait(8)
      -- A walk that leaves the map takes the trail with it (the prints are
      -- cleared on a map change, as they must be), and the probe then
      -- reports zero and calls the feature broken. So the edge is the end of
      -- the walk: one run wandered forty cells into the next route and
      -- measured nothing but its own restlessness.
      if game.overworld.map.id ~= home then break end
    end
    wait(20)
    if game.overworld.map.id ~= home then
      game.overworld:setMap(home, tx or 10, ty or 10, "down")
      wait(90)
      break
    end
    local moved = math.abs(pl.cellX - x0) + math.abs(pl.cellY - y0)
    if moved > walked then walked, went = moved, dir end
    if moved >= 3 then break end
  end
  -- and then a couple of steps ACROSS the frame, so the trail is beside the
  -- player rather than directly behind them under the camera
  for _, dir in ipairs({ "left", "right" }) do
    local x0 = pl.cellX
    for _ = 1, 3 do
      game.input.state[dir] = true
      wait(22)
      game.input.state[dir] = false
      wait(8)
    end
    if math.abs(pl.cellX - x0) >= 2 then break end
  end
  wait(30)
  local after = GroundFX.myPrintCount()
  log(("walked %d cells %s; MY footprints: %d -> %d (%d in all)"):format(
    walked, went, before, after, GroundFX.printCount()))
  log(("player now at %d,%d"):format(pl.cellX, pl.cellY))
  if walked == 0 then log("  FAIL: the probe never moved the player") end
  if after <= before then log("  FAIL: walking in snow left no prints") end
  shot("34_footprints.png")

  -- and they fill back in
  local peak = GroundFX.printCount()
  GroundFX.PRINT_TTL = 4
  wait(400)
  log(("prints after they had time to fill: %d -> %d"):format(
    peak, GroundFX.printCount()))
  if GroundFX.printCount() >= peak then
    log("  FAIL: prints never faded")
  end
  GroundFX.PRINT_TTL = 34

  -- ------- and the row switches it all off
  GroundFX.setting:sync("off")
  Weather.setting:sync("rain")
  wait(700)
  log(("GROUND off in a downpour: draws=%d (want 0)"):format(GroundFX.lastDraws))
  if GroundFX.lastDraws > 0 then log("  FAIL: the row does not switch it off") end
  GroundFX.setting:sync("on")

  -- ------- and the WILD row still stands things in the grass with all of
  -- this on, which is the one thing that must not have broken
  Weather.setting:sync("off")
  WildRoamers.setting:sync("roam")
  teleport("ROUTE_1", 8, 12, "up")
  wait(300)
  local roamers = {}
  for _, e in ipairs(game.overworld.entities or {}) do
    if e.roamer then roamers[#roamers + 1] = e.species .. "@" .. e.level end
  end
  log(("roamers on ROUTE_1: %d -- %s"):format(
    #roamers, table.concat(roamers, " ")))
  if #roamers == 0 then log("  FAIL: nothing standing in the grass") end
  shot("35_roamers_with_ecology.png")

  log("")
  log("done -- " .. OUT)
  logf:close()
  love.event.quit()
end
