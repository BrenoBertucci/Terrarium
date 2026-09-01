-- The downloaded wind sheets, held to the rules written above WindFX.SHEETS.
--
-- The first wiring of these sheets made the whole standing field out of
-- them, and "it looks messy" is not a measurement. Each rule is one, here:
--
--   R1 FRONT ONLY     kick and whirl are never standing motes (front=true
--                     always), and in the natural window each is born with
--                     Wind.gust() >= WindFX.FRONT_AT
--   R2 OWN CLOCK      a one-shot sheet's ttl == n / fps, to the float
--   R3 NO SPIN        spin == 0 and lift == 0 on every sheet mote
--   R4 ONE SIZE       size == 1 on every sheet mote
--   R5 GROUNDED       a ground sheet's y - groundAt == its clamp, every frame
--   R6 ONE HERO       whirl count <= 1 in every frame, even with
--                     HERO_CHANCE forced to 1 and a front every cooldown;
--                     with HERO_CHANCE 0 (shipping), no whirl is ever born
--   R7 NO SPECKS      standing motes are only leaf / ribbon / curl / wetpuff;
--                     the grey stamps are never in the air
--   R8 CLIMATE        dry: ribbon (+ kick only if WindFX.KICK), no wetpuff;
--                     rain: wetpuff, no ribbon, no kick
--   R9 BACKGROUND     a banded sheet (ribbon, curl, wetpuff) stays inside
--                     its band above the ground, every frame
--   COUNT             live motes never exceed
--                     STANDING_MAX + FRONT_SHEETS + 1 (kick) + 1 (hero)
--
-- Screenshots (the callback is awaited, never a fixed yield count):
--   sheet_front_*.png   a dry front, three moments of the ribbon clip
--   sheet_hero.png      the whirl, once one is alive
--   sheet_rain.png      a wet front
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/windfx_sheet_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/windfx_sheet.log", "w"))
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
    return done
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
  local AmbientLife = lib.require("AmbientLife")
  local Voxel3D  = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")

  Weather.setting:sync("off")
  Wind.setting:sync(4)                -- GALE: amount >= HERO_AT
  AmbientLife.setting:sync("off")
  Pipelines.setLevel("terrarium_voxel", 4)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  DayNight.setting:sync("day")
  local ow = game.overworld
  ow:setMap("ROUTE_1", 10, 20, "up")
  wait(400)
  log(("map %s  amount %.2f  gust %.2f  gate %s  shader %s")
      :format(ow.map.id, Wind.amount(), Wind.gust(), WindFX.lastGate,
              tostring(Voxel3D.shader and Voxel3D.shader() or "?")))
  if Voxel3D.shaderError then log("shaderError:", tostring(Voxel3D.shaderError)) end

  local SHEETS = WindFX.SHEETS
  local KINDS = WindFX.KINDS
  local STANDING_OK = { leaf = true, ribbon = true, curl = true, wetpuff = true }
  local FRONT_ONLY = { kick = true, whirl = true }

  -- ------- the per-frame audit, shared by every window
  local fails = {}
  local function fail(rule, msg)
    fails[rule] = (fails[rule] or 0) + 1
    if fails[rule] <= 3 then log("  FAIL " .. rule .. ": " .. msg) end
  end
  local seen = {}          -- mote table -> true, to notice births
  local audit = {
    frames = 0, maxSheets = 0, maxHero = 0, births = {},
    standingKinds = {}, sheetKinds = {},
  }
  local function resetAudit()
    seen = {}
    audit = { frames = 0, maxSheets = 0, maxHero = 0, births = {},
              standingKinds = {}, sheetKinds = {} }
  end
  local function auditFrame(natural)
    audit.frames = audit.frames + 1
    local sheets, hero = 0, 0
    local gust = Wind.gust()
    local live = 0
    for i = 1, WindFX.count() do
      local m = WindFX.get(i)
      local s = SHEETS[m.kind]
      -- VegFX / SprayFX / StepFX put their own motes in this field through
      -- WindFX.emit; they are another system's and not the wind's
      local own = not (m.veg or m.src)
      if own then live = live + 1 end
      if s then
        sheets = sheets + 1
        audit.sheetKinds[m.kind] = (audit.sheetKinds[m.kind] or 0) + 1
        if m.kind == "whirl" then hero = hero + 1 end
        if FRONT_ONLY[m.kind] and not m.front then fail("R1", m.kind .. " standing") end
        if not seen[m] then
          seen[m] = true
          audit.births[m.kind] = (audit.births[m.kind] or 0) + 1
          if natural and FRONT_ONLY[m.kind] and gust < WindFX.FRONT_AT then
            fail("R1", ("%s born at gust %.2f"):format(m.kind, gust))
          end
          if not s.loop then
            local want = s.n / s.fps
            if math.abs((m.ttl or 0) - want) > 1e-6 then
              fail("R2", ("%s ttl %.3f want %.3f"):format(m.kind, m.ttl or -1, want))
            end
          end
        end
        -- R3/R4 are the wind's own promises; a leaf VegFX emitted carries
        -- VegFX's spin and size (the sheet draw ignores both)
        if own and ((m.spin or 0) ~= 0 or (m.lift or 0) ~= 0) then
          fail("R3", ("%s spin %.2f lift %.2f"):format(m.kind, m.spin or 0, m.lift or 0))
        end
        if own and (m.size or 0) ~= 1 then fail("R4", m.kind .. " size " .. tostring(m.size)) end
        -- R9: a banded sheet stays in its band
        if own and s.band then
          local got = (m.y or 0) - WindFX.groundAt(m.x, m.z)
          if got < s.band[1] - 0.01 or got > s.band[2] + 0.01 then
            fail("R9", ("%s above ground %.1f, band %d..%d"):format(m.kind, got, s.band[1], s.band[2]))
          end
        end
        if s.ground then
          local want = KINDS[m.kind].lowClamp
          local got = (m.y or 0) - WindFX.groundAt(m.x, m.z)
          if math.abs(got - want) > 0.01 then
            fail("R5", ("%s above ground %.2f want %.2f"):format(m.kind, got, want))
          end
        end
      end
      if own and not m.front then
        audit.standingKinds[m.kind] = (audit.standingKinds[m.kind] or 0) + 1
        if not STANDING_OK[m.kind] then fail("R7", "standing kind " .. tostring(m.kind)) end
      end
    end
    if sheets > audit.maxSheets then audit.maxSheets = sheets end
    if live > (audit.maxLive or 0) then audit.maxLive = live end
    if hero > audit.maxHero then audit.maxHero = hero end
    if hero > 1 then fail("R6", hero .. " whirls alive") end
    local cap = WindFX.STANDING_MAX + WindFX.FRONT_SHEETS + 1 + 1
    if live > cap then fail("COUNT", live .. " live motes > " .. cap) end
  end
  local function kindsLine(t)
    local ks = {}
    for k, v in pairs(t) do ks[#ks + 1] = k .. "=" .. v end
    table.sort(ks)
    return table.concat(ks, " ")
  end
  local function report(name)
    log(("%s: %d frames  maxLive %d  maxSheets %d  maxHero %d"):format(
        name, audit.frames, audit.maxLive or 0, audit.maxSheets, audit.maxHero))
    log("  births:   " .. kindsLine(audit.births))
    log("  sheets:   " .. kindsLine(audit.sheetKinds))
    log("  standing: " .. kindsLine(audit.standingKinds))
  end

  -- ------- WINDOW 1: natural. Fronts come when the gust envelope says so.
  resetAudit()
  local firstFront = nil
  for f = 1, 1500 do
    auditFrame(true)
    if not firstFront and (audit.births.ribbon or 0) > 0 then firstFront = f end
    coroutine.yield()
  end
  report("natural")
  log("  first front at frame " .. tostring(firstFront))

  -- ------- WINDOW 2: forced. A front every cooldown, a hero every time it
  -- is allowed. R6 has to hold under this, or it is not a rule.
  local realGust = Wind.gust
  Wind.gust = function() return 1 end
  -- the hero is forced only if the mod has it on at all; with it off the
  -- rule under test is that no whirl is ever born
  local realChance = WindFX.HERO_CHANCE
  local heroOn = realChance > 0
  if heroOn then WindFX.HERO_CHANCE = 1 end
  resetAudit()
  local shotsLeft = { 3, 9, 15 }
  local frontAt, heroShot = nil, false
  local fronts0 = WindFX.fronts or 0
  for f = 1, 900 do
    auditFrame(false)
    if not frontAt and (WindFX.fronts or 0) > fronts0 then frontAt = f end
    if frontAt and #shotsLeft > 0 and f - frontAt == shotsLeft[1] then
      table.remove(shotsLeft, 1)
      log("  shot sheet_front_" .. (f - frontAt) .. ".png ok=" ..
          tostring(shot("sheet_front_" .. (f - frontAt) .. ".png")))
    end
    if not heroShot and (audit.births.whirl or 0) > 0 then
      wait(20)
      heroShot = true
      log("  shot sheet_hero.png ok=" .. tostring(shot("sheet_hero.png")))
    end
    coroutine.yield()
  end
  report("forced-dry")
  if (audit.births.wetpuff or 0) > 0 then fail("R8", "wetpuff in dry air") end
  if WindFX.KICK and (audit.births.kick or 0) == 0 then fail("R8", "no kick in dry air") end
  if not WindFX.KICK and (audit.births.kick or 0) > 0 then fail("R8", "kick with KICK off") end
  if (audit.births.ribbon or 0) == 0 then fail("R8", "no ribbon in dry air") end
  if heroOn and (audit.births.whirl or 0) == 0 then fail("R6", "no hero at all under forced fronts") end
  if not heroOn and (audit.births.whirl or 0) > 0 then fail("R6", "whirl born with HERO_CHANCE 0") end

  -- ------- WINDOW 3: forced, wet.
  Weather.setting:sync("rain")
  wait(360)
  log(("rain: visible=%s amount %.2f"):format(tostring(Weather.visible()), Wind.amount()))
  resetAudit()
  local rainShot = false
  for f = 1, 600 do
    auditFrame(false)
    if not rainShot and (audit.births.wetpuff or 0) > 0 then
      wait(6)
      rainShot = true
      log("  shot sheet_rain.png ok=" .. tostring(shot("sheet_rain.png")))
    end
    coroutine.yield()
  end
  report("forced-rain")
  if (audit.births.ribbon or 0) > 0 then fail("R8", "ribbon in rain") end
  if (audit.births.kick or 0) > 0 then fail("R8", "kick in rain") end
  if (audit.births.wetpuff or 0) == 0 then fail("R8", "no wetpuff in rain") end

  Wind.gust = realGust
  WindFX.HERO_CHANCE = realChance

  local bad = 0
  for rule, c in pairs(fails) do bad = bad + c; log(("RULE %s: %d failures"):format(rule, c)) end
  log(bad == 0 and "ALL RULES PASS" or ("FAILURES: " .. bad))
  logf:close()
  love.event.quit()
end
