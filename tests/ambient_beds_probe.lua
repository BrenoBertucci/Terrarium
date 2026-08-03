-- Probe: the recorded ambience beds, and the indoor gate on the weather.
--
--   * every file in assets/audio decodes, and to how many seconds
--   * stripSilence actually trims the MP3's encoder padding (the loop seam)
--   * each bed comes UP where the world wants it and DOWN where it does not,
--     read off the live Source volumes rather than off the intent
--   * rain draws OUTDOORS and draws NOTHING indoors -- the bug this run is
--     really about: streaks kept refilling behind a ceiling
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/DRAMATIC_SHAPE/tests/ambient_beds_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/ambient_beds.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b
    coroutine.yield()
  end

  local f = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); f = f + 1; if f > 900 then break end
  end
  f = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); f = f + 11; if f > 1500 then break end
  end
  log("free roam:", game.stack:top() == game.overworld)

  local lib = game.mods.exports.DRAMATIC_SHAPE.lib
  local AmbientSound = lib.require("AmbientSound")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Voxel3D = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")

  -- ------- 1. the files decode
  log("")
  log("== the recordings ==")
  local specs = {}
  for key, spec in pairs(AmbientSound.BEDS) do specs[#specs + 1] = { key, spec } end
  specs[#specs + 1] = { "thunder", AmbientSound.THUNDER }
  table.sort(specs, function(a, b) return a[1] < b[1] end)
  for _, e in ipairs(specs) do
    local path = lib.path .. "/assets/audio/" .. e[2].file
    local ok, data = pcall(love.sound.newSoundData, path)
    if ok and data then
      log(("  %-9s %-14s %6.2fs  %dHz  %dch  %d-bit"):format(
        e[1], e[2].file, data:getDuration(), data:getSampleRate(),
        data:getChannelCount(), data:getBitDepth()))
    else
      log(("  %-9s %-14s FAIL: %s"):format(e[1], e[2].file, tostring(data)))
    end
  end

  -- ------- 2. the loop seam: how much silence is on the ends
  log("")
  log("== loop seam (silence trimmed off each end) ==")
  for _, e in ipairs(specs) do
    local path = lib.path .. "/assets/audio/" .. e[2].file
    local ok, data = pcall(love.sound.newSoundData, path)
    if ok and data then
      local n, ch = data:getSampleCount(), data:getChannelCount()
      local function loud(i)
        for c = 1, ch do
          local o, v = pcall(data.getSample, data, i, c)
          if o and math.abs(v or 0) > 0.004 then return true end
        end
        return false
      end
      local first, last = 0, n - 1
      while first < last and not loud(first) do first = first + 1 end
      while last > first and not loud(last) do last = last - 1 end
      log(("  %-9s head=%5d tail=%5d samples (%.1fms + %.1fms)"):format(
        e[1], first, n - 1 - last,
        first / data:getSampleRate() * 1000,
        (n - 1 - last) / data:getSampleRate() * 1000))
    end
  end

  -- ------- 2b. what building each Source costs
  --
  -- Decode plus trim, once per bed per session, on the frame the bed first
  -- comes up. The trim is a per-sample copy in Lua, so a thirty-second stereo
  -- recording is millions of calls -- this is the number that decides whether
  -- it can be done lazily at dawn or has to be paid for somewhere else.
  log("")
  log("== source build cost (decode + trim), once per session ==")
  AmbientSound.invalidate()
  local worst, worstKey = 0, "-"
  for _, e in ipairs(specs) do
    local t0 = love.timer.getTime()
    local path = lib.path .. "/assets/audio/" .. e[2].file
    local data = love.sound.newSoundData(path)
    local tDecode = (love.timer.getTime() - t0) * 1000
    -- the trim, measured on its own
    local t1 = love.timer.getTime()
    local n, ch = data:getSampleCount(), data:getChannelCount()
    local out = love.sound.newSoundData(n, data:getSampleRate(),
                                        data:getBitDepth(), ch)
    for i = 0, n - 1 do
      for c = 1, ch do out:setSample(i, c, data:getSample(i, c)) end
    end
    local tCopy = (love.timer.getTime() - t1) * 1000
    log(("  %-9s decode %7.1fms  full copy %8.1fms  (%d samples x %dch)")
        :format(e[1], tDecode, tCopy, n, ch))
    if tDecode + tCopy > worst then worst, worstKey = tDecode + tCopy, e[1] end
  end
  log(("  worst: %s at %.0fms (%.1f frames at 60fps)"):format(
    worstKey, worst, worst / 16.67))

  -- ------- 3. the beds respond to the world
  --
  -- Read off the live Sources, by wrapping setVolume: what the mixer is
  -- actually being told, not what the code meant to say.
  log("")
  log("== bed levels ==")
  local vols = {}
  do
    local probe = love.audio.newSource(
      love.sound.newSoundData(64, 44100, 16, 1), "static")
    local meta = getmetatable(probe).__index
    local inner = meta.setVolume
    meta.setVolume = function(self, v)
      vols[self] = v
      return inner(self, v)
    end
  end
  local function levels(tag)
    local out, n = {}, 0
    for _, v in pairs(vols) do
      if v and v > 0.0005 then n = n + 1; out[#out + 1] = ("%.3f"):format(v) end
    end
    table.sort(out)
    log(("  %-34s %d sounding: %s"):format(tag, n,
        n > 0 and table.concat(out, " ") or "-"))
    return n
  end

  local function teleport(id, x, y)
    game.overworld:setMap(id, x, y, "down")
    wait(80)
  end

  AmbientSound.setting:sync("on")
  Weather.setting:sync("off")
  Pipelines.setLevel("voxel", 5)

  teleport("ROUTE_1", 8, 12)
  DayNight.setting:sync("night"); wait(260)
  local nightN = levels("ROUTE_1 night, clear")
  DayNight.setting:sync("day"); wait(260)
  local dayN = levels("ROUTE_1 day, clear")

  -- water: Route 6 has the pond by Vermilion; fall back to any water map
  teleport("PALLET_TOWN", 12, 14); wait(200)
  levels("PALLET_TOWN day (water south)")

  Weather.setting:sync("rain"); wait(700)
  local rainOut = levels("PALLET_TOWN day, RAINING outdoors")

  -- ------- 4. THE BUG: indoors
  log("")
  log("== indoors, still raining ==")
  teleport("REDS_HOUSE_1F", 3, 5); wait(300)
  local rainIn = levels("REDS_HOUSE_1F, rain outside")

  local g = love.graphics
  local rects, lines = 0, 0
  local iR, iL = g.rectangle, g.line
  g.rectangle = function(...) rects = rects + 1 return iR(...) end
  g.line = function(...) lines = lines + 1 return iL(...) end
  Weather.draw(Voxel3D.project, 3, 640, 576)
  g.rectangle, g.line = iR, iL
  log(("  Weather.draw indoors issued %d rectangles, %d lines"):format(
    rects, lines))
  log(("  Weather.falling=%s  Weather.visible=%s  paintsFlat=%s"):format(
    tostring((Weather.falling())), tostring((Weather.visible())),
    tostring(Weather.paintsFlat())))
  if rects > 0 or lines > 0 then
    log("  FAIL: weather still drawing indoors")
  else
    log("  OK: nothing drawn indoors")
  end

  -- and back out again, where it must resume
  teleport("PALLET_TOWN", 12, 14); wait(200)
  rects, lines = 0, 0
  g.rectangle = function(...) rects = rects + 1 return iR(...) end
  g.line = function(...) lines = lines + 1 return iL(...) end
  Weather.draw(Voxel3D.project, 3, 640, 576)
  g.rectangle, g.line = iR, iL
  log(("  back outdoors: %d rectangles, %d lines"):format(rects, lines))
  if rects == 0 and lines == 0 then
    log("  FAIL: weather did not resume outdoors")
  else
    log("  OK: resumed outdoors")
  end

  -- ------- 5. snow indoors too
  Weather.setting:sync("snow"); wait(700)
  teleport("REDS_HOUSE_1F", 3, 5); wait(260)
  rects = 0
  g.rectangle = function(...) rects = rects + 1 return iR(...) end
  Weather.draw(Voxel3D.project, 3, 640, 576)
  g.rectangle = iR
  log(("  snow indoors issued %d rectangles"):format(rects))
  if rects > 0 then log("  FAIL: snow still drawing indoors")
  else log("  OK: no snow indoors") end

  log("")
  log(("summary: night=%d day=%d rainOut=%d rainIn=%d sounding")
      :format(nightN, dayN, rainOut, rainIn))
  log("done -- " .. OUT)
  logf:close()
  love.event.quit()
end
