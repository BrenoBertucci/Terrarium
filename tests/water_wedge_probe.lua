-- Probe: where do the pale polygons on the water come from?
--
-- Big translucent wedges with straight edges drift over open water in every
-- film of Route 21, with SCREEN FX on SSR and on AO alike. One scene, frozen
-- (Water.HOLD-free: weather off, hour pinned, swimmer still), shot with one
-- suspect switched off at a time -- then the pale-pixel count in the water
-- region says which one it is.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> POKEPORT_SPEED=1 \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/water_wedge_probe.lua ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/water_wedge.log", "w"))
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
    if n > 1500 then break end
  end
  local lib = game.mods.exports.TERRARIUM.lib
  local function req(name) local ok, m = pcall(lib.require, name) return ok and m or nil end
  local Water, RayFX, Weather, DayNight = req("Water"), req("RayFX"), req("Weather"), req("DayNight")
  local Wind, Quality, Voxel3D = req("Wind"), req("Quality"), req("Voxel3D")
  local Mist, CloudShade, Glow, Sky = req("Mist"), req("CloudShade"), req("Glow"), req("Sky")
  local TiltShift, Light = req("TiltShift"), req("Light")
  local Pipelines = require("src.render.Pipelines")
  local function sync(s, v) if s then pcall(s.sync, s, v) end end
  sync(Weather.setting, "off"); sync(DayNight.setting, "day"); sync(Wind.setting, 2)
  sync(Quality.setting, 1); sync(RayFX.setting, "ao"); sync(Water.setting, 0.8)
  sync(Water.style, "anime")
  pcall(Pipelines.setLevel, "terrarium_voxel", 4)
  local p = game.overworld.player
  p.surfing = true
  pcall(function() game.overworld:setMap("ROUTE_21", 8, 14, "down") end)
  p.surfing = true
  Voxel3D.lampLights = nil
  for _ = 1, 900 do if Voxel3D.lampLights ~= nil then break end coroutine.yield() end
  wait(300)

  local cases = {
    { "base", function() end, function() end },
    { "sheetmask", function() RayFX.SHEET_DEBUG = true end,
                   function() RayFX.SHEET_DEBUG = nil end },
    { "mist_off", function() sync(Mist and Mist.setting, "off") end,
                  function() sync(Mist and Mist.setting, "on") end },
    { "cloudshade_off", function() sync(CloudShade and CloudShade.setting, "off") end,
                        function() sync(CloudShade and CloudShade.setting, "on") end },
    { "clouds_off", function() sync(Sky and Sky.cloudSetting, 0) end,
                    function() sync(Sky and Sky.cloudSetting, 1) end },
    { "glow_off", function() sync(Glow and Glow.setting, false) end,
                  function() sync(Glow and Glow.setting, true) end },
    { "fx_rt", function() sync(RayFX.setting, "rt") end,
               function() sync(RayFX.setting, "ao") end },
    { "fx_off", function() sync(RayFX.setting, "off") end,
                function() sync(RayFX.setting, "ao") end },
    { "classic", function() sync(Water.style, "classic") end,
                 function() sync(Water.style, "anime") end },
  }
  for _, c in ipairs(cases) do
    c[2](); wait(90)
    shot("wedge_" .. c[1] .. ".png")
    log("shot", c[1])
    c[3](); wait(30)
  end
  log("done")
  logf:close()
  love.event.quit()
end
