-- Probe: the three additions of 1.10.0, exercised on a running game.
--
--   9  ambient sound   every chip program assembles, renders to real PCM and
--                      plays -- counted by asking the synth for the sample
--                      count of each, and by watching Source:play land
--  10  weather         rain pinned on Route 1: the streaks and the splashes
--                      are counted through a real overlay draw, and the sky
--                      palette, the world tint and the water's glint are
--                      read before and after so the darkening is a NUMBER
--                      rather than an impression
--  11  interiors       a house entered: the sleeper placed, the mugs found,
--                      and the steam counted through a real draw
--
-- Screenshots beside the log, because a visual feature is not done until it
-- has been seen (the battle-HUD ink lesson: a marker that draws nothing
-- draws nothing silently).
--
--   POKEPORT_VERSION=yellow \
--   DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/weather_life_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/weather_life_probe.log", "w"))
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

  local AmbientSound = lib.require("AmbientSound")
  local Weather = lib.require("Weather")
  local Interiors = lib.require("Interiors")
  local DayNight = lib.require("DayNight")
  local Water = lib.require("Water")
  local Voxel3D = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")

  local function teleport(mapId, x, y, facing)
    game.overworld:setMap(mapId, x, y, facing or "down")
    wait(90)
  end

  -- =====================================================================
  log("")
  log("== 9. ambient sound ==")

  -- the registry actually carries them
  local sfx = game.data.audio and game.data.audio.sfx or {}
  for _, entry in ipairs(AmbientSound.PROGRAMS) do
    local def = sfx[entry[1]]
    local blob = def and def.chip and def.chip.blob
    log(("registry %-16s def=%s blob=%s bytes chans=%s"):format(
      entry[1], tostring(def ~= nil), blob and #blob or "-",
      def and def.chip and #def.chip.channels or "-"))
  end

  -- and every one of them renders to real PCM through the engine's own synth
  local ChipSynth = require("src.core.ChipSynth")
  for _, entry in ipairs(AmbientSound.PROGRAMS) do
    local def = sfx[entry[1]]
    local ok, sd = pcall(ChipSynth.renderEffectData, game.data, def,
                         { sfx = true, allowLoops = false, frameTicks = 0x100 })
    local n = (ok and sd) and sd:getSampleCount() or 0
    log(("render   %-16s ok=%s samples=%d (%.2fs)"):format(
      entry[1], tostring(ok and sd ~= nil), n, n / 44100))
    if n == 0 then log("  FAIL: rendered silence") end
  end

  -- ------- and they actually PLAY: count Source:play while the schedule runs
  local plays = {}
  do
    local meta = nil
    local probeSrc = love.audio.newSource(
      love.sound.newSoundData(64, 44100, 16, 1), "static")
    meta = getmetatable(probeSrc).__index
    local inner = meta.play
    meta.play = function(self, ...)
      plays[#plays + 1] = true
      return inner(self, ...)
    end

    -- Source:play is shared with the game's own audio (music restarts, menu
    -- beeps), so every window below is measured against a BASELINE taken
    -- with the row OFF over the same number of frames. The difference is
    -- this feature's and nothing else's.
    teleport("ROUTE_1", 8, 12, "up")
    Weather.setting:sync("off")
    DayNight.setting:sync("night")

    local function window(frames_)
      local before = #plays
      for _ = 1, frames_ do coroutine.yield() end
      return #plays - before
    end

    AmbientSound.setting:sync("off")
    local base = window(420)
    AmbientSound.setting:sync("on")
    local night = window(420)
    log(("night on ROUTE_1: %d plays with SOUNDS on vs %d off (~7s each)")
        :format(night, base))
    if night <= base then log("  FAIL: no ambient sound at night") end

    DayNight.setting:sync("day")
    AmbientSound.setting:sync("off")
    base = window(900)
    AmbientSound.setting:sync("on")
    local day = window(900)
    log(("day on ROUTE_1:   %d plays with SOUNDS on vs %d off (~15s each)")
        :format(day, base))
    if day <= base then log("  FAIL: no ambient sound by day") end

    meta.play = inner
  end

  -- =====================================================================
  log("")
  log("== 10. weather ==")

  Pipelines.setLevel("terrarium_voxel", 5)
  DayNight.setting:sync("day")
  wait(150)

  local function skyLine(tag)
    local pal = DayNight.palette()
    local tint = DayNight.tint(true)
    log(("%-10s sky[1]=%d,%d,%d sky[6]=%d,%d,%d tint=%.3f,%.3f,%.3f "
         .. "overcast=%.2f wet=%.2f sparkle=%.3f swell=%.2f"):format(
      tag, pal[1][1], pal[1][2], pal[1][3], pal[6][1], pal[6][2], pal[6][3],
      tint[1], tint[2], tint[3], DayNight.overcast or 0, Water.wet or 0,
      Water.sparkleNow(), Water.swell()))
  end

  Weather.setting:sync("off")
  wait(120)
  skyLine("clear")
  shot("10_clear_route1.png")

  Weather.setting:sync("rain")
  -- BUILD is 7 seconds; give it twelve so the ramp is settled at its peak
  wait(720)
  local kind, power = Weather.falling()
  log(("falling: kind=%s power=%.2f"):format(tostring(kind), power))
  skyLine("raining")
  shot("11_rain_route1.png")

  -- ------- what the overlay actually issued
  --
  -- A real Weather.draw through a real projection, with the draw calls
  -- counted: rectangles are splashes and their drops, lines are streaks.
  do
    local g = love.graphics
    local rects, lines = 0, 0
    local innerR, innerL = g.rectangle, g.line
    g.rectangle = function(...) rects = rects + 1 return innerR(...) end
    g.line = function(...) lines = lines + 1 return innerL(...) end
    Weather.draw(Voxel3D.project, 3, 640, 576)
    g.rectangle, g.line = innerR, innerL
    log(("rain overlay: %d rectangles (splashes), %d lines (streaks)")
        :format(rects, lines))
    if lines == 0 then log("  FAIL: no streaks issued") end
    if rects == 0 then log("  FAIL: no splashes issued") end
  end

  -- ------- snow, on the same machinery
  Weather.setting:sync("snow")
  wait(720)
  kind, power = Weather.falling()
  log(("falling: kind=%s power=%.2f"):format(tostring(kind), power))
  skyLine("snowing")
  shot("12_snow_route1.png")
  do
    local g = love.graphics
    local rects = 0
    local innerR = g.rectangle
    g.rectangle = function(...) rects = rects + 1 return innerR(...) end
    Weather.draw(Voxel3D.project, 3, 640, 576)
    g.rectangle = innerR
    log(("snow overlay: %d rectangles (flakes)"):format(rects))
    if rects == 0 then log("  FAIL: no flakes issued") end
  end

  -- ------- the winter test, with the calendar pinned
  do
    local realMonth = DayNight.month
    for _, m in ipairs({ 1, 4, 7, 10 }) do
      DayNight.month = function() return m end
      log(("month %2d -> winter=%s"):format(m, tostring(Weather.isWinter())))
    end
    DayNight.month = realMonth
    log("hemisphere:", Weather.HEMISPHERE)
  end

  -- ------- and the flat 2D world takes the same rain
  Weather.setting:sync("rain")
  Pipelines.setLevel("terrarium_voxel", 0)
  wait(600)
  log("flat: paintsFlat=", tostring(Weather.paintsFlat()))
  shot("13_rain_flat2d.png")

  -- =====================================================================
  log("")
  log("== 11. interiors ==")

  Weather.setting:sync("off")
  Pipelines.setLevel("terrarium_voxel", 5)
  Interiors.setting:sync("on")
  wait(300)

  -- every HOUSE-family map the dataset carries: which get a sleeper, and
  -- how many mugs are on their tables. The hash is stable, so this table is
  -- the same on every run and on every machine.
  local homes = {}
  for id, def in pairs(game.data.maps) do
    if type(id) == "string" and type(def) == "table"
       and Interiors.HOMES[def.tileset] then
      homes[#homes + 1] = id
    end
  end
  table.sort(homes)
  log(("%d house maps in the dataset"):format(#homes))

  -- The sweep first and the A press LAST, in that order and deliberately: a
  -- text box left on the stack makes every module in this mod stop (top state
  -- is no longer the overworld, which is exactly the gate they all hold), so
  -- talking mid-sweep froze the survey and reported every later house as
  -- empty. The probe's own bug, and worth naming because the symptom looked
  -- exactly like the feature failing.
  local withPet, petShotAt, mugShotAt = 0, nil, nil
  for _, id in ipairs(homes) do
    teleport(id, 3, 5, "down")
    wait(40)
    local pet = nil
    for _, e in ipairs(game.overworld.entities or {}) do
      if e.housePet then pet = e end
    end
    -- the mug list is private; count it through a counted draw instead. A
    -- sleeper's Zs are exactly 5 rectangles, so what is left is the mugs.
    local g = love.graphics
    local rects = 0
    local innerR = g.rectangle
    g.rectangle = function(...) rects = rects + 1 return innerR(...) end
    Interiors.draw(Voxel3D.project, 3)
    g.rectangle = innerR
    if pet then withPet = withPet + 1 end
    local mugRects = rects - (pet and 5 or 0)
    log(("%-28s pet=%-10s mug_rects=%d z_rects=%d"):format(
      id, pet and pet.species or "-", math.max(0, mugRects), pet and 5 or 0))
    if pet and not petShotAt then petShotAt = id end
    if mugRects >= 10 and not mugShotAt then mugShotAt = id end
  end
  log(("%d of %d houses have a sleeper (%.0f%%)"):format(
    withPet, #homes, withPet / math.max(1, #homes) * 100))

  -- ------- and now the pictures, and the A press
  if mugShotAt then
    teleport(mugShotAt, 3, 5, "down")
    wait(90)
    -- three shots a third of a steam cycle apart, so a wisp that happened to
    -- be at its faintest in one of them is at its strongest in another: a
    -- single frame of a fading effect cannot tell you whether it is visible
    shot("20a_mugs_" .. mugShotAt .. ".png")
    wait(40)
    shot("20b_mugs_" .. mugShotAt .. ".png")
    wait(40)
    shot("20c_mugs_" .. mugShotAt .. ".png")
    log("mug shot:", mugShotAt)
  else
    log("FAIL: no house had mugs to photograph")
  end

  if petShotAt then
    teleport(petShotAt, 3, 5, "down")
    wait(90)
    local pet = nil
    for _, e in ipairs(game.overworld.entities or {}) do
      if e.housePet then pet = e end
    end
    if pet then
      -- stand the player one cell south of it, facing north
      local p = game.overworld.player
      p.cellX, p.cellY = pet.cellX, pet.cellY + 1
      p.px, p.py = p.cellX * 16, p.cellY * 16
      p.facing = "up"
      wait(30)
      -- three across the Z's cycle, same reasoning as the mugs: one frame of
      -- a fading mark cannot tell you whether the mark is visible
      shot("21a_sleeper_" .. petShotAt .. ".png")
      wait(50)
      shot("21b_sleeper_" .. petShotAt .. ".png")
      wait(50)
      shot("21c_sleeper_" .. petShotAt .. ".png")
      -- through the input queue rather than by calling interact() directly:
      -- the direct call skipped the talk on a player that had just been
      -- teleported by assignment, and the button is the path a player takes
      tap("a")
      wait(40)
      log("after A at the sleeper, a box is up:",
          tostring(game.stack:top() ~= game.overworld))
      shot("22_sleeper_talk.png")
      -- and press it away properly rather than once and hope
      local tries = 0
      while game.stack:top() ~= game.overworld and tries < 40 do
        tap("a"); wait(12); tries = tries + 1
      end
      log("box dismissed after", tries, "presses")
    end
  else
    log("FAIL: no house had a sleeper to photograph")
  end

  log("")
  log("done -- " .. OUT)
  logf:close()
  love.event.quit()
end
