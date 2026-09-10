-- What the 3D frame COSTS, pass by pass, and where the cost lives.
--
-- Written for the Mali-G615 MC2 report (a Poco X7 at 2712x1220 ran the VOXEL
-- row at about one frame a second).  A phone cannot be benchmarked from here,
-- so this probe measures the two things that DO travel:
--
--   1. RESOLUTION SENSITIVITY.  The same scene at RES FULL / 1/2 / 1/3 / 1/4.
--      If frame time falls roughly with the pixel count the frame is FILL
--      bound and the fix is pixels (a smaller canvas, a cheaper shader, fewer
--      full-screen passes).  If it barely moves, the pixels are not the
--      problem and no amount of RES will save the phone -- the cost is
--      geometry, draw calls or Lua, and those are the same on both machines.
--
--   2. love.graphics.getStats().  drawcalls and CANVASSWITCHES per frame are
--      device-independent counts.  Every canvas switch on a tile-based GPU is
--      a resolve of the whole render target out to memory and a reload back
--      in; a desktop pays almost nothing for one and a Mali pays for the
--      entire framebuffer.  So a number that looks harmless here is the one
--      number most likely to explain the phone.
--
-- Method notes, all of them learned the hard way in this repo:
--   * ROUND-ROBIN, not a straight sweep: warm-up and background load drift
--     across a run and would otherwise be charged to whichever condition ran
--     first.  Each condition is visited once per round and the reported number
--     is the median of its per-round medians.
--   * p50, never the mean: one 300ms hitch from a background process drags an
--     average across a whole condition.
--   * The SPREAD is printed beside every number.  A delta smaller than the
--     spread of its own condition is not a small measurement, it is not a
--     measurement -- see the note in tests/grass_perf_probe.lua.
--   * The clock and the weather are PINNED.  A shower or a sunset moves more
--     pixels between two frames than any row on this list.
--
--   POKEPORT_VERSION=yellow \
--   DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/mali_cost_probe.lua gen1recomp

return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/mali_cost_probe.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
    logf:write(table.concat(p, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end

  local Quality     = lib.require("Quality")
  local RayFX       = lib.require("RayFX")
  local Sky         = lib.require("Sky")
  local Weather     = lib.require("Weather")
  local DayNight    = lib.require("DayNight")
  local AmbientLife = lib.require("AmbientLife")
  local GroundFX    = lib.require("GroundFX")
  local CityLife    = lib.require("CityLife")
  local WildRoamers = lib.require("WildRoamers")
  local Grass3D     = lib.require("Grass3D")
  local Trees3D     = lib.require("Trees3D")
  local StreetLamps = lib.require("StreetLamps")
  local Water       = lib.require("Water")
  local Wind        = lib.require("Wind")
  local MiniMap     = lib.require("MiniMap")
  local AutoFarm    = lib.require("AutoFarm")
  local Voxel3D     = lib.require("Voxel3D")
  local ShadowMap   = lib.require("ShadowMap")
  local Pipelines   = require("src.render.Pipelines")

  -- ------- the still scene
  --
  -- Everything that moves on its own is pinned or off, so the only thing that
  -- differs between two conditions is the condition.
  Pipelines.setLevel("terrarium_voxel", 3)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  MiniMap.setting:sync("off")
  AutoFarm.setting:sync("off")
  Weather.setting:sync("off")
  DayNight.setting:sync("day")
  Wind.setting:sync(0)

  local CLOCK = 300
  local function hold(f)
    for _ = 1, f do DayNight.clock = CLOCK; coroutine.yield() end
    DayNight.clock = CLOCK
  end

  local SPOT = { "ROUTE_1", 8, 12, "up" }
  game.overworld:setMap(SPOT[1], SPOT[2], SPOT[3], SPOT[4])
  hold(360)

  local function pin()
    for _ = 1, 6 do
      game.overworld:setMap(SPOT[1], SPOT[2], SPOT[3], SPOT[4])
      hold(6)
      local p = game.overworld.player
      if p and p.cellX == SPOT[2] and p.cellY == SPOT[3] then return true end
    end
    return false
  end

  local function pct(s, p)
    local i = math.max(1, math.min(#s, math.ceil(#s * p)))
    return s[i]
  end
  local function median(t)
    local s = {}
    for i, v in ipairs(t) do s[i] = v end
    table.sort(s)
    return pct(s, 0.5), s[1], s[#s]
  end

  -- ------- the sample
  --
  -- getStats() is cumulative for the frame LOVE is in, so it is read once per
  -- yield and the per-frame number is the difference.  drawcalls is the one
  -- that scales with the world; canvasswitches is the one that scales with
  -- the number of passes, and is the number a tiler charges for.
  -- getStats() reads zero here: LOVE clears it at present() and the driver's
  -- yield lands on the far side of that, so every field is the count of the
  -- nothing that has happened since.  Count the calls directly instead -- the
  -- probe runs unsandboxed, so it can wrap the real love.graphics.
  local COUNT = { draw = 0, canvas = 0, shader = 0 }
  do
    local g = love.graphics
    local rawDraw, rawCanvas, rawShader = g.draw, g.setCanvas, g.setShader
    g.draw = function(...) COUNT.draw = COUNT.draw + 1 return rawDraw(...) end
    g.setCanvas = function(...) COUNT.canvas = COUNT.canvas + 1 return rawCanvas(...) end
    g.setShader = function(...) COUNT.shader = COUNT.shader + 1 return rawShader(...) end
    -- meshes go through drawInstanced / draw depending on the call site
    if g.drawInstanced then
      local rawInst = g.drawInstanced
      g.drawInstanced = function(...) COUNT.draw = COUNT.draw + 1 return rawInst(...) end
    end
  end

  local N = 120
  local function sample()
    local pinned = pin()
    hold(30)
    local dts, draws, switches, shaders = {}, {}, {}, {}
    local prev = love.timer.getTime()
    for _ = 1, N do
      DayNight.clock = CLOCK
      COUNT.draw, COUNT.canvas, COUNT.shader = 0, 0, 0
      coroutine.yield()
      local t = love.timer.getTime()
      dts[#dts + 1] = (t - prev) * 1000
      prev = t
      draws[#draws + 1] = COUNT.draw
      switches[#switches + 1] = COUNT.canvas
      shaders[#shaders + 1] = COUNT.shader
    end
    local m, lo, hi = median(dts)
    -- what the 3D pass actually rasterised this condition, so a condition
    -- that quietly fell back to the flat 2D path is visible as such rather
    -- than as a spectacular saving
    local cw, ch = 0, 0
    local okC, cv = pcall(Voxel3D.canvas)
    if okC and cv then cw, ch = cv:getDimensions() end
    return {
      ms = m, lo = lo, hi = hi, pinned = pinned,
      draws = median(draws), switches = median(switches), shaders = median(shaders),
      cw = cw, ch = ch,
      level = Pipelines.level and (Pipelines.level("terrarium_voxel") or -1) or -1,
    }
  end

  -- ------- the conditions
  --
  -- `set` puts the world into the condition; `back` puts it back.  Both run
  -- every round, so a condition that leaks state shows up as drift in the
  -- baseline rather than as a silent bias.
  local function saveAll()
    return {
      res     = Quality.setting:get(),
      shadow  = Quality.shadowSetting:get(),
      rayfx   = RayFX.setting:get(),
      clouds  = Sky.cloudSetting:get(),
      ambient = AmbientLife.setting:get(),
      ground  = GroundFX.setting:get(),
      town    = CityLife.setting:get(),
      wild    = WildRoamers.setting:get(),
      grass   = Grass3D.setting:get(),
      trees   = Trees3D.setting:get(),
      lamps   = StreetLamps.setting:get(),
      water   = Water.setting:get(),
    }
  end
  local BASE = saveAll()
  local function restore()
    Quality.setting:sync(BASE.res)
    Quality.shadowSetting:sync(BASE.shadow)
    RayFX.setting:sync(BASE.rayfx)
    Sky.cloudSetting:sync(BASE.clouds)
    AmbientLife.setting:sync(BASE.ambient)
    GroundFX.setting:sync(BASE.ground)
    CityLife.setting:sync(BASE.town)
    WildRoamers.setting:sync(BASE.wild)
    Grass3D.setting:sync(BASE.grass)
    Trees3D.setting:sync(BASE.trees)
    StreetLamps.setting:sync(BASE.lamps)
    Water.setting:sync(BASE.water)
    Pipelines.setLevel("terrarium_tiltshift", 0)
    -- RE-ASSERTED, not assumed: the first run of this probe measured 7.45ms
    -- once and 1.2ms for every condition after it, which is the flat 2D path.
    -- Something in the RES walk drops the pipeline back to OFF, so the level
    -- is set again before every single condition.
    Pipelines.setLevel("terrarium_voxel", 3)
  end

  local CONDS = {
    { "base",        function() end },
    { "res=FULL",    function() Quality.setting:sync(1) end },
    { "res=1/3",     function() Quality.setting:sync(3) end },
    { "res=1/4",     function() Quality.setting:sync(4) end },
    { "rtx=OFF",     function() RayFX.setting:sync("off") end },
    { "clouds=OFF",  function() Sky.cloudSetting:sync(0) end },
    { "shadows=OFF", function() Quality.shadowSetting:sync("off") end },
    { "ambient=OFF", function() AmbientLife.setting:sync("off") end },
    { "ground=OFF",  function() GroundFX.setting:sync("off") end },
    { "life=OFF",    function() CityLife.setting:sync("off")
                               WildRoamers.setting:sync("off") end },
    { "grass=VOXEL", function() Grass3D.setting:sync("voxel") end },
    { "water=FLAT",  function() Water.setting:sync(0) end },
    { "lamps=OFF",   function() StreetLamps.setting:sync(false) end },
    { "tilt=ON",     function() Pipelines.setLevel("terrarium_tiltshift", 3) end },
    -- everything cheap at once: the ceiling a settings-only fix could reach
    { "ALL-CHEAP",   function()
        Quality.setting:sync(4)
        Quality.shadowSetting:sync("off")
        RayFX.setting:sync("off")
        Sky.cloudSetting:sync(0)
        AmbientLife.setting:sync("off")
        GroundFX.setting:sync("off")
        CityLife.setting:sync("off")
        WildRoamers.setting:sync("off")
        Grass3D.setting:sync("voxel")
        Water.setting:sync(0)
        StreetLamps.setting:sync(false)
      end },
  }

  -- ------- what the frame is actually made of, in pixels
  log("== geometry of the frame ==")
  local ww, wh = love.graphics.getDimensions()
  log(("window            %dx%d  (%.2f Mpx)"):format(ww, wh, ww * wh / 1e6))
  local vw, vh = game.renderer:worldViewSize()
  log(("world view        %dx%d world px"):format(vw or 0, vh or 0))
  for _, div in ipairs({ 1, 2, 3, 4 }) do
    log(("  RES 1/%d scene canvas  %dx%d  (%.3f Mpx)")
          :format(div, math.floor(ww / div), math.floor(wh / div),
                  math.floor(ww / div) * math.floor(wh / div) / 1e6))
  end
  local okR, rname = pcall(Voxel3D.rungName)
  local okP, pname = pcall(Voxel3D.precName)
  log(("shader rung       %s   precision %s")
        :format(okR and tostring(rname) or "?", okP and tostring(pname) or "?"))
  log(("shadow map        %s texels/side"):format(tostring(ShadowMap.res)))
  log("")

  log("== per-condition cost, ROUTE_1 (8,12) up, day pinned, weather off ==")
  log("   (ms is the p50 of 120 frames; lo/hi are that run's min and max --")
  log("    a delta smaller than the spread is NOT a measurement)")
  log("")

  local ROUNDS = 3
  local acc = {}
  for i = 1, #CONDS do acc[i] = {} end
  for round = 1, ROUNDS do
    log(("-- round %d"):format(round))
    for i, cond in ipairs(CONDS) do
      restore()
      hold(20)
      cond[2]()
      hold(45)
      local s = sample()
      acc[i][#acc[i] + 1] = s
      log(("   %-12s %7.2f ms  [%6.2f..%7.2f]  draws=%-5d canvas=%-3d shader=%-4d scene=%dx%d lvl=%d pin=%s")
            :format(cond[1], s.ms, s.lo, s.hi, s.draws, s.switches, s.shaders,
                    s.cw, s.ch, s.level, tostring(s.pinned)))
    end
  end
  restore()

  log("")
  log("== median of the per-round medians ==")
  local final = {}
  for i, cond in ipairs(CONDS) do
    local ms = {}
    for j, s in ipairs(acc[i]) do ms[j] = s.ms end
    final[i] = median(ms)
    log(("   %-12s %7.2f ms   rounds %s")
          :format(cond[1], final[i],
                  table.concat({ ("%.1f"):format(ms[1] or 0),
                                 ("%.1f"):format(ms[2] or 0),
                                 ("%.1f"):format(ms[3] or 0) }, " / ")))
  end

  log("")
  log("== saving against base (positive = this condition is CHEAPER) ==")
  local base = final[1]
  for i = 2, #CONDS do
    log(("   %-12s %+7.2f ms  (%+5.1f%%)")
          :format(CONDS[i][1], base - final[i],
                  base > 0 and (base - final[i]) / base * 100 or 0))
  end

  log("")
  log("== resolution sensitivity ==")
  -- FULL is index 2, 1/2 is base, 1/3 is 3, 1/4 is 4
  local px = {}
  for _, d in ipairs({ 1, 2, 3, 4 }) do
    px[d] = math.floor(ww / d) * math.floor(wh / d)
  end
  log(("   FULL %7.2f ms at %.3f Mpx"):format(final[2], px[1] / 1e6))
  log(("   1/2  %7.2f ms at %.3f Mpx"):format(final[1], px[2] / 1e6))
  log(("   1/3  %7.2f ms at %.3f Mpx"):format(final[3], px[3] / 1e6))
  log(("   1/4  %7.2f ms at %.3f Mpx"):format(final[4], px[4] / 1e6))
  local span = final[2] - final[4]
  log(("   FULL - 1/4 = %.2f ms over %.3f Mpx  ->  %.2f ms per Mpx")
        :format(span, (px[1] - px[4]) / 1e6,
                (px[1] - px[4]) > 0 and span / ((px[1] - px[4]) / 1e6) or 0))
  log(("   fixed cost that no RES rung removes: about %.2f ms")
        :format(final[4] - (span / math.max(1e-9, (px[1] - px[4]))) * px[4]))

  log("")
  log("done")
  logf:close()
  love.event.quit()
end
