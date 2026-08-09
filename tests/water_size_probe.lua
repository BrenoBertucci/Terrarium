-- Probe: does the water know how big it is, and did the pond stop looking
-- like a sky?
--
-- Three questions per map, and the point of all three is that they are
-- numbers off the LIVE field rather than an eyeball on a screenshot -- the
-- screenshots are here to settle the look, not the logic (tests/
-- waterbody_offline.lua already settles the logic, with no game running).
--
--   Q1 size spread   min / median / max of Water.sizeAt over every water
--                    cell on the map. A map with one pond should have a LOW
--                    max; a coastal map should reach open water.
--   Q2 amplitude     what that does to Water.heightAt -- the surface the
--                    surfer's feet actually stand on.
--   Q3 paint         ART_MIX, the deck's reflect amount and colour, and
--                    whether RayFX handed back a shader at all (the cache
--                    key bug: with ANIME on FULL, getShader was reading a
--                    name it never wrote and the whole pass was silently
--                    off).
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/water_size_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/water_size_probe.log", "w"))
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
    wait(3)
  end
  local function median(t)
    local c = {}
    for i = 1, #t do c[i] = t[i] end
    table.sort(c)
    if #c == 0 then return -1 end
    if #c % 2 == 1 then return c[(#c + 1) / 2] end
    return (c[#c / 2] + c[#c / 2 + 1]) / 2
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

  local Water = lib.require("Water")
  local WaterBody = lib.require("WaterBody")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Sky = lib.require("Sky")
  local RayFX = lib.require("RayFX")
  local Anime = lib.require("Anime")
  local Pipelines = require("src.render.Pipelines")

  -- The 3D pass has to be ON and WARM before a screenshot means anything.
  -- The first run of this probe shot Cerulean 150 frames after setMap and
  -- caught the flat 2D fallback -- a 9 KB picture of tiles, logged beside
  -- perfectly good numbers, which is exactly the shape of "measured nothing
  -- and reported a pass". Vermilion happened to land on a real frame only
  -- because the pipeline had warmed up by then.
  pcall(Pipelines.setLevel, "terrarium_voxel", 4)
  local Voxel3D = lib.require("Voxel3D")
  -- Poll rather than count: VoxelScene.render returns nil until the terrain
  -- is meshed and the engine draws 2D on those frames, and how many frames
  -- that takes is a property of the map and the machine. lampLights is only
  -- ever written by VoxelScene.render, so it going non-nil is the pass
  -- saying it ran.
  local function wait3D(cap)
    for i = 1, (cap or 600) do
      if Voxel3D.lampLights ~= nil then return i end
      coroutine.yield()
    end
    return -1
  end
  wait(60)
  log("warm: 3D pass up after " .. tostring(wait3D(600)) .. " frames")

  Weather.setting:sync("off")
  DayNight.setting:sync("day")
  Water.setting:sync(0.8)          -- CALM: the row the bug was reported on
  Water.wet, Water.snow, Water.freeze = 0, 0, 0

  ---------------------------------------------------------- the RayFX gate
  -- One line, and it is the whole of the cache-key regression: on any rung
  -- above OFF, with ANIME wherever the player left it, apply() must be able
  -- to get a shader. It could not, and nothing said so.
  local built = RayFX.compile and RayFX.compile(RayFX.level())
  log(("Q3_rayfx: level=%s anime=%s screen=%s built=%s -> %s")
      :format(tostring(RayFX.level()), tostring(Anime.level()),
              tostring(Anime.screen()), tostring(built),
              (RayFX.level() == "off" or built) and "PASS" or "FAIL"))

  ---------------------------------------------------------------- per map
  -- CERULEAN has a fenced pond, VERMILION opens onto the sea, PALLET has a
  -- bit of both. The claim under test is that these come out DIFFERENT --
  -- before this change every one of them reported the same single amplitude.
  -- PALLET's water is a handful of cells; CERULEAN carries a real town lake;
  -- ROUTE_21 is the Cinnabar channel and is almost nothing but sea. The
  -- first cut of this list used VERMILION as "the sea" and it is not one --
  -- what is drawn there is a harbour seven cells off the quay, and it
  -- correctly measured SMALLER than Cerulean's lake. That was the probe
  -- being wrong about Kanto, not the field being wrong about water.
  local maps = {
    { id = "PALLET_TOWN",    x = 10, y = 10, tag = "puddle" },
    { id = "CERULEAN_CITY",  x = 14, y = 7,  tag = "lake" },
    { id = "ROUTE_21",       x = 9,  y = 10, tag = "sea" },
  }

  local seen = {}
  for _, m in ipairs(maps) do
    local ok = pcall(function()
      game.overworld:setMap(m.id, m.x, m.y, "down")
    end)
    if not ok then
      log(("[%s] SKIP: setMap failed"):format(m.id))
    else
      Voxel3D.lampLights = nil       -- so wait3D answers about THIS map
      local up = wait3D(600)
      wait(200)                      -- settle: the hour's tint ramps in, and
                                     -- an A/B across that ramp differs in the
                                     -- whole frame rather than in the water
      log(("[%s] 3D pass up after %s frames"):format(m.id, tostring(up)))
      local map = game.overworld and game.overworld.map
      local sizes, heights = {}, {}
      if map and map.isWaterCell and map.def then
        local cw = math.floor((tonumber(map.def.width) or 0) * 2)
        local chh = math.floor((tonumber(map.def.height) or 0) * 2)
        for cy = 0, chh - 1 do
          for cx = 0, cw - 1 do
            local wok, isw = pcall(map.isWaterCell, map, cx, cy)
            if wok and isw then
              local wx, wz = cx * 16 + 8, cy * 16 + 8
              sizes[#sizes + 1] = Water.sizeAt(wx, wz)
              heights[#heights + 1] = math.abs(Water.heightAt(wx, wz))
            end
          end
        end
      end
      local lo, hi = 2, -1
      for _, s in ipairs(sizes) do
        if s < lo then lo = s end
        if s > hi then hi = s end
      end
      if #sizes == 0 then lo, hi = -1, -1 end
      local hhi = 0
      for _, h in ipairs(heights) do if h > hhi then hhi = h end end
      seen[m.tag] = { max = hi, hmax = hhi, cells = #sizes }
      log(("[%s/%s] Q1_size: cells=%d fieldOn=%s min=%.3f med=%.3f max=%.3f")
          :format(m.id, m.tag, #sizes, tostring(WaterBody.on()),
                  lo, median(sizes), hi))
      log(("[%s/%s] Q2_amp: |heightAt| max=%.4f  swell=%.3f")
          :format(m.id, m.tag, hhi, Water.swell()))
      local col = Sky.deckColor()
      log(("[%s/%s] Q3_paint: artMix=%.2f cloudAmt=%.3f reflect=%.3f "
           .. "deck=(%.2f,%.2f,%.2f)")
          :format(m.id, m.tag, tonumber(Water.ART_MIX) or -1,
                  Sky.cloudAmount(), Sky.waterReflect(),
                  col[1], col[2], col[3]))
      -- THE A/B, on the same frame and the same camera: the only honest way
      -- to say whether the surface art stopped reading as sky. `a_` is the
      -- build as shipped (the mix was a hard 1.0 -- the PNG WAS the water),
      -- `b_` is the knob, and `c_` is the art off entirely so the third
      -- picture says how much of what is left is the art at all.
      local keep = Water.ART_MIX
      Water.ART_MIX = 1.0;  wait(6); shot(("art_a_full_%s.png"):format(m.tag))
      Water.ART_MIX = keep; wait(6); shot(("art_b_mixed_%s.png"):format(m.tag))
      Water.ART_MIX = 0.0;  wait(6); shot(("art_c_off_%s.png"):format(m.tag))
      Water.ART_MIX = keep; wait(6)
      shot(("size_%s.png"):format(m.tag))
    end
  end

  ---------------------------------------------------------------- verdict
  -- The pond must NOT reach the sea's amplitude. Stated as a comparison
  -- between maps rather than as a threshold on either, because the absolute
  -- number moves with the row, the wind and the hour and the RELATION is
  -- what this change is actually claiming.
  local small, sea = seen.puddle, seen.sea
  if small and sea and small.cells > 0 and sea.cells > 0 then
    local ok = sea.max > small.max + 0.25
    log(("VERDICT size: puddle.max=%.3f (%d cells) sea.max=%.3f (%d cells) -> %s")
        :format(small.max, small.cells, sea.max, sea.cells,
                ok and "PASS" or "FAIL"))
  else
    log("VERDICT size: SKIP (a map reported no water cells)")
  end

  logf:close()
  love.event.quit()
end
