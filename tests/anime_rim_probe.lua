-- Probe: WHAT is washing the frame out?
--
-- Context. RayFX's shader cache was reading a key it never wrote, so on any
-- build with ANIME above CEL the whole screen-space pass was silently off.
-- Fixing that turned RT_AO and RT_ANIME on for the first time, and the frame
-- came back hazy across the WHOLE map -- ground, sand, buildings -- not just
-- the water.
--
-- The suspicion is the ANIME rim. `animeRimAt` fires on
-- step(RIM_EDGE, 1 - dot(N, toEye)), N comes out of `normalAt`, and normalAt
-- reads the DEPTH BUFFER -- which holds the world already bent by the
-- V-CURVE. The SSR block undoes that bend on purpose (see curveDrop); the
-- rim does not. Distant ground under a strong curve leans away from the eye,
-- crosses the threshold, and takes a flat +RIM of cool white.
--
-- This does not try to prove that mechanism. It isolates WHICH pass owns the
-- haze, which is the question that has to be answered before touching
-- anything: four shots of one frame, one variable at a time.
--
--   a  rayfx OFF            -- what the build looked like with the bug
--   b  rayfx AO + anime FULL -- what it looks like now
--   c  rayfx AO + anime CEL  -- the rim and the ink gone, AO kept
--   d  rayfx OFF + anime FULL -- ANIME's own banded light, no screen pass
--
-- If the haze is in b and gone in c, it is the rim or the ink. If it is in c
-- as well, it is the ambient occlusion. If it is in d, it was never this
-- pass at all and the curve or the aerial haze owns it.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/anime_rim_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/anime_rim_probe.log", "w"))
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
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
    wait(4)
  end

  love.math.setRandomSeed(20260808)

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit()
      return end
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

  local RayFX = lib.require("RayFX")
  local Anime = lib.require("Anime")
  local Voxel3D = lib.require("Voxel3D")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Aerial = lib.require("Aerial")
  local WorldCurve = lib.require("WorldCurve")
  local Pipelines = require("src.render.Pipelines")

  -- the two knobs that could ALSO wash a frame out, pinned so they are not
  -- the free variable in an A/B about something else
  Weather.setting:sync("off")
  DayNight.setting:sync("day")
  log(("knobs: curve=%s haze=%s rayfx=%s anime=%s")
      :format(tostring(WorldCurve.setting and WorldCurve.setting:get()),
              tostring(Aerial.setting and Aerial.setting:get()),
              tostring(RayFX.level()), tostring(Anime.level())))
  log(("anime numbers: RIM=%.2f RIM_EDGE=%.2f INK=%.2f")
      :format(Anime.RIM, Anime.RIM_EDGE, Anime.INK))

  pcall(Pipelines.setLevel, "terrarium_voxel", 4)
  local function wait3D(cap)
    for i = 1, (cap or 600) do
      if Voxel3D.lampLights ~= nil then return i end
      coroutine.yield()
    end
    return -1
  end
  wait(60); wait3D(600)

  local maps = {
    { id = "ROUTE_21", x = 9, y = 10, tag = "sea" },
    { id = "FUCHSIA_CITY", x = 18, y = 20, tag = "town" },
  }

  local rayfxWas, animeWas = RayFX.level(), Anime.level()

  for _, m in ipairs(maps) do
    local ok = pcall(function()
      game.overworld:setMap(m.id, m.x, m.y, "down")
    end)
    if not ok then
      log(("[%s] SKIP: setMap failed"):format(m.id))
    else
      Voxel3D.lampLights = nil
      local up = wait3D(600)
      -- settle: the hour's tint ramps in, and a pair of shots across that
      -- ramp differs in the whole frame rather than in what is being tested
      wait(200)
      log(("[%s] 3D pass up after %s frames"):format(m.id, tostring(up)))

      local function phase(tag, rayfx, anime)
        RayFX.setting:sync(rayfx)
        Anime.setting:sync(anime)
        wait(45)
        log(("[%s] %s: rayfx=%s anime=%s compiled=%s")
            :format(m.id, tag, rayfx, anime,
                    tostring(rayfx == "off" or RayFX.compile(rayfx))))
        shot(("rim_%s_%s.png"):format(m.tag, tag))
      end

      phase("a_rtOFF",        "off", "full")
      phase("b_ao_animeFULL", "ao",  "full")
      phase("c_ao_animeCEL",  "ao",  "cel")
      phase("d_rtOFF_animeCEL", "off", "cel")
    end
  end

  RayFX.setting:sync(rayfxWas)
  Anime.setting:sync(animeWas)
  logf:close()
  love.event.quit()
end
