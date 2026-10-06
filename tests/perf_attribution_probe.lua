-- Probe: WHERE THE FRAME GOES, with the player's own settings.
--
-- "4 fps" is a symptom; this attributes it. VSYNC OFF (a vsync'd probe reads
-- 16.7 ms for everything). The settings are whatever the save says -- RES,
-- SCREEN FX, ANIME, GLOW, MIST all as the player plays -- and each condition
-- turns ONE thing off in memory (sync, never written), measured in paired
-- cycles with the order rotated so heat and mesh streaming land on all of
-- them alike:
--   base        as played
--   classic     WATER STYLE CLASSIC
--   noripple    the ripple field stubbed out
--   nowind      the visible wind (WindFX + WindLines) held and cleared
--   fxoff       SCREEN FX OFF (reference)
--   halfres     RES 1/2 (reference: is it fill?)
-- Two scenes: surfing the Route 21 channel, and a Route 1 meadow in a gale.
-- Also times, per frame, the CPU spent inside the modules this session added.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> POKEPORT_SPEED=1 \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/perf_attribution_probe.lua ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local CYCLES = tonumber(os.getenv("DS_CYCLES") or "4")
  local logf = assert(io.open(OUT .. "/perf_attribution.log", "w"))
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
  local lib = game.mods.exports.TERRARIUM.lib
  local function req(name) local ok, m = pcall(lib.require, name) return ok and m or nil end
  local Water, RayFX, Weather, DayNight = req("Water"), req("RayFX"), req("Weather"), req("DayNight")
  local Wind, Quality, Voxel3D, Ripples = req("Wind"), req("Quality"), req("Voxel3D"), req("Ripples")
  local WindFX, WindLines, VoxelScene, Anime = req("WindFX"), req("WindLines"), req("VoxelScene"), req("Anime")
  local Glow, Mist = req("Glow"), req("Mist")
  local Pipelines = require("src.render.Pipelines")
  local function sync(s, v) if s then pcall(s.sync, s, v) end end
  local function get(s) if not s then return "n/a" end local ok, v = pcall(s.get, s) return tostring(ok and v) end

  pcall(love.window.setVSync, 0)
  log("vsync", tostring(love.window.getVSync and love.window.getVSync()))
  log(("window %dx%d  dpi %.2f"):format(love.graphics.getWidth(), love.graphics.getHeight(),
    love.graphics.getDPIScale and love.graphics.getDPIScale() or 1))
  log("voxel level", tostring(Pipelines.level and Pipelines.level("terrarium_voxel")))
  log(("settings: RES=%s FX=%s ANIME=%s GLOW=%s MIST=%s WATER=%s STYLE=%s WIND=%s SHADOWS=%s PFX=%s"):format(
    get(Quality.setting), get(RayFX.setting), get(Anime and Anime.setting), get(Glow and Glow.setting),
    get(Mist and Mist.setting), get(Water.setting), get(Water.style), get(Wind.setting),
    get(Quality.shadowSetting), get(Quality.particleSetting)))
  local okR, rw, rh = pcall(function() return Voxel3D.renderSize() end)
  log("render size", tostring(okR and rw), tostring(okR and rh))

  -- CPU spent in what this session added, per frame
  local cpu = {}
  local function wrap(mod, fname, tag)
    if not (mod and mod[fname]) then return end
    local inner = mod[fname]
    mod[fname] = function(...)
      local t0 = love.timer.getTime()
      local a, b, c, d = inner(...)
      cpu[tag] = (cpu[tag] or 0) + (love.timer.getTime() - t0)
      return a, b, c, d
    end
  end
  wrap(Ripples, "update", "ripples")
  wrap(WindFX, "update", "windfx.update")
  wrap(WindFX, "drawWorld", "windfx.draw")
  wrap(VoxelScene, "render", "scene.render")
  wrap(RayFX, "apply", "rayfx.apply")

  sync(Weather.setting, "off")
  sync(DayNight.setting, "day")

  local realRU, realRL = Ripples.update, Ripples.live
  local savedFX, savedRES, savedStyle = get(RayFX.setting), Quality.setting:get(), Water.style:get()
  local CONDS = {
    base     = { on = function() end, off = function() end },
    classic  = { on = function() sync(Water.style, "classic") end,
                 off = function() sync(Water.style, savedStyle) end },
    noripple = { on = function() Ripples.update = function() end; Ripples.live = function() return false end end,
                 off = function() Ripples.update, Ripples.live = realRU, realRL end },
    nowind   = { on = function() WindFX.HOLD = true; WindFX.clear() end,
                 off = function() WindFX.HOLD = false end },
    fxoff    = { on = function() sync(RayFX.setting, "off") end,
                 off = function() sync(RayFX.setting, savedFX) end },
    halfres  = { on = function() sync(Quality.setting, 2) end,
                 off = function() sync(Quality.setting, savedRES) end },
  }
  local ORDER = { "base", "classic", "noripple", "nowind", "fxoff", "halfres" }

  local function block(frames)
    for k in pairs(cpu) do cpu[k] = 0 end
    local t = {}
    local last = love.timer.getTime()
    for i = 1, frames do
      coroutine.yield()
      local now = love.timer.getTime()
      t[i] = (now - last) * 1000
      last = now
    end
    table.sort(t)
    local c = {}
    for k, v in pairs(cpu) do c[k] = v * 1000 / frames end
    return t[math.floor(frames / 2)], t[math.floor(frames * 0.95)], c
  end

  local function scene(tag, setup)
    setup()
    Voxel3D.lampLights = nil
    for _ = 1, 900 do if Voxel3D.lampLights ~= nil then break end coroutine.yield() end
    wait(900)                                   -- meshes stream in for seconds
    local res = {}
    for _, k in ipairs(ORDER) do res[k] = {} end
    for cyc = 1, CYCLES do
      for j = 0, #ORDER - 1 do
        local k = ORDER[(j + cyc - 1) % #ORDER + 1]
        CONDS[k].on(); wait(45)
        local med, p95, c = block(150)
        CONDS[k].off(); wait(15)
        res[k][#res[k] + 1] = med
        local cs = {}
        for name, ms in pairs(c) do cs[#cs + 1] = ("%s %.2f"):format(name, ms) end
        table.sort(cs)
        log(("[%s] cycle %d %-9s median %6.2f  p95 %6.2f  cpu: %s"):format(
          tag, cyc, k, med, p95, table.concat(cs, ", ")))
      end
    end
    local function mean(v) local s = 0 for _, x in ipairs(v) do s = s + x end return s / #v end
    local b = mean(res.base)
    log(("[%s] SUMMARY base %.2f ms (%.1f fps)"):format(tag, b, 1000 / b))
    for _, k in ipairs(ORDER) do
      if k ~= "base" then
        log(("[%s]   %-9s %6.2f ms  (%+.2f vs base)"):format(tag, k, mean(res[k]), mean(res[k]) - b))
      end
    end
  end

  local p = game.overworld.player
  scene("route21-surf", function()
    p.surfing = true
    pcall(function() game.overworld:setMap("ROUTE_21", 8, 14, "down") end)
    p.surfing = true
  end)
  scene("route1-gale", function()
    p.surfing = false
    sync(Wind.setting, 4)
    pcall(function() game.overworld:setMap("ROUTE_1", 9, 24, "up") end)
  end)
  finish("done")
end
