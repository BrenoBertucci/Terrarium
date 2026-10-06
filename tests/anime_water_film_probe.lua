-- Probe: a FILM of the ANIME water, for a GIF. Not a check -- a camera.
--
-- Surfing in the Route 21 channel (open water all round, the reef garden
-- under it), day, a breeze, WATER on AUTO and WATER STYLE on ANIME. The
-- script: the swimmer bobbing, three drops landing round it, a swim across
-- the channel (wake, bow rings, rings reflecting), then a last drop.
--
-- Frames are captured at up to FPS a second and KEPT IN MEMORY (an ImageData
-- each, ~5 MB at 1536x864) -- writing them as they came stalled the game to
-- 7 fps -- and written as TGA once the film is over. Each one's REAL time
-- goes in film.txt, because the swell runs on the wall clock and the GIF has
-- to play it back at the speed it happened. tools/film_to_gif.py assembles it.
--
-- SCREEN FX is whatever the player's save says (DS_FX overrides it). The pale
-- polygons the first takes showed were NOT the reflection: they were the
-- sheet's own depth bands cut on a reef garden's stamped lagoon distance --
-- see the DEPTH note in Voxel3D's ANIME block, and tests/water_wedge_probe.lua
-- for how that was pinned down.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> POKEPORT_SPEED=1 \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/anime_water_film_probe.lua ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local LENGTH = tonumber(os.getenv("DS_LENGTH") or "7")
  local FPS = tonumber(os.getenv("DS_FPS") or "12")
  local logf = assert(io.open(OUT .. "/anime_water_film.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
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
    if n > 1500 then break end
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
  local Pipelines = require("src.render.Pipelines")
  local function sync(s, v) if s then pcall(s.sync, s, v) end end
  sync(Weather.setting, "off")
  sync(DayNight.setting, "day")
  sync(Wind.setting, 2)
  sync(Quality.setting, 1)            -- RES FULL: the GIF is downscaled anyway
  if os.getenv("DS_FX") then sync(RayFX.setting, os.getenv("DS_FX")) end
  sync(Water.setting, "auto")
  sync(Water.style, "anime")
  pcall(Pipelines.setLevel, "terrarium_voxel", 4)

  local map
  local p = game.overworld.player
  local SEA, X, Y = "ROUTE_21", 8, 14
  local function place(x, y)
    p.surfing = true
    pcall(function() game.overworld:setMap(SEA, x, y, "down") end)
    p.surfing = true
    map = game.overworld.map
  end
  place(X, Y)
  Voxel3D.lampLights = nil
  for _ = 1, 900 do if Voxel3D.lampLights ~= nil then break end coroutine.yield() end
  wait(200)

  local KEYS = { "down", "up", "left", "right" }
  local function release()
    for _, k in ipairs(KEYS) do game.input.state[k] = false end
  end
  -- which key swims across open water (the camera turns the controls);
  -- south first: swimming away from this camera trails the wake toward it
  local function openAhead(cx, cy, dx, dy, k)
    for i = 1, k do
      for s = -1, 1 do
        local x, y = cx + dx * i + dy * s, cy + dy * i + dx * s
        if not (map:inBounds(x, y) and map:isWaterCell(x, y)) then return false end
      end
    end
    return true
  end
  local found = {}
  for _, try in ipairs(KEYS) do
    release(); place(X, Y); wait(90)
    local x0, y0 = p.cellX, p.cellY
    for _ = 1, 20 do game.input.state[try] = true; coroutine.yield() end
    release(); wait(40)
    local dx, dy = p.cellX - x0, p.cellY - y0
    local sx = (dx > 0 and 1) or (dx < 0 and -1) or 0
    local sy = (dy > 0 and 1) or (dy < 0 and -1) or 0
    log(("key %s moves %d,%d from %d,%d"):format(try, dx, dy, x0, y0))
    if (sx ~= 0) ~= (sy ~= 0) and openAhead(x0, y0, sx, sy, 6) then
      found[#found + 1] = { key = try, dx = sx, dy = sy }
    end
  end
  local key
  for _, f in ipairs(found) do if f.dy > 0 then key = f.key end end
  if not key and found[1] then key = found[1].key end
  log("swim key:", tostring(key))
  release()
  place(X, Y)
  wait(300)
  log("player", p.cellX, p.cellY, "surfing", tostring(p.surfing))

  -- ------- the film
  local frames = {}
  local t0 = love.timer.getTime()
  local nextAt = 0
  local cx, cz = p.cellX * 16 + 8, p.cellY * 16 + 8
  local cues = {
    { at = 0.35, fn = function() Ripples.poke(cx, cz - 48, -3.2, 6, 0.9) end },
    { at = 1.05, fn = function() Ripples.poke(cx + 60, cz - 12, -3.2, 6, 0.9) end },
    { at = 1.75, fn = function() Ripples.poke(cx - 52, cz - 36, -3.6, 7, 1.0) end },
  }
  local swimFrom, swimTo = 2.7, 5.4
  local lastDrop = false
  while true do
    local t = love.timer.getTime() - t0
    if t >= LENGTH then break end
    for _, c in ipairs(cues) do
      if not c.done and t >= c.at then c.done = true; c.fn(); log(("cue at %.2f"):format(t)) end
    end
    if key and t >= swimFrom and t < swimTo then game.input.state[key] = true
    elseif key then release() end
    if not lastDrop and t >= 5.9 then
      lastDrop = true
      local px, pz = p.cellX * 16 + 8, p.cellY * 16 + 8
      Ripples.poke(px + 20, pz - 44, -4.0, 8, 1.0)
      log(("last drop at %.2f"):format(t))
    end
    if t >= nextAt then
      nextAt = t + 1 / FPS
      local done = false
      local idx = #frames + 1
      love.graphics.captureScreenshot(function(data)
        frames[idx] = { t = love.timer.getTime() - t0, data = data }
        done = true
      end)
      local guard = 0
      while not done and guard < 60 do
        if key and t >= swimFrom and t < swimTo then game.input.state[key] = true end
        coroutine.yield(); guard = guard + 1
      end
    else
      coroutine.yield()
    end
  end
  release()
  local f = io.open(OUT .. "/film.txt", "w")
  for i, fr in ipairs(frames) do
    f:write(("%d %.4f\n"):format(i, fr.t))
    local ok, fd = pcall(fr.data.encode, fr.data, "tga")
    if ok and fd then
      local o = io.open(("%s/film_%03d.tga"):format(OUT, i), "wb")
      if o then o:write(fd:getString()) o:close() end
    end
    fr.data = nil
  end
  f:close()
  log(("frames %d over %.2f s; ripples steps %d pokes %d; player ended %d,%d"):format(
    #frames, frames[#frames] and frames[#frames].t or 0, Ripples.steps, Ripples.pokes,
    p.cellX, p.cellY))
  finish("done")
end
