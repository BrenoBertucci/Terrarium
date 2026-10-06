-- Probe: frame time AS PLAYED, and where it goes.
--
-- The player's own settings, untouched (only vsync off: a vsync'd probe reads
-- 16.7 ms for everything). Wild encounters are switched off on the instance
-- and every sample is thrown away unless the overworld is on top AND the 3D
-- pass actually drew -- the first attribution run measured a battle screen
-- for most of its length and called it the overworld.
--
-- Per spot: frame median/p95, the CPU inside each mod system (wrapped), the
-- driver's draw calls, and the remainder (frame minus the mod's measured CPU),
-- which is the engine plus the GPU wait. Then, in the SAME spot, one system off
-- at a time (sync in memory, never written), paired, order rotated.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> POKEPORT_SPEED=1 \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/perf_asplayed_probe.lua ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/perf_asplayed.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b) game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield() end
  local function finish(msg) if msg then log(msg) end logf:close() love.event.quit() end
  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then return finish("FAIL: no overworld") end
  end
  n = 0
  while game.stack:top() ~= game.overworld do tap("a"); wait(10); n = n + 11; if n > 1500 then break end end
  local ow = game.overworld
  ow.rollEncounter = function() return nil end

  local lib = game.mods.exports.TERRARIUM.lib
  local function req(name) local ok, m = pcall(lib.require, name) return ok and m or nil end
  local M = {}
  for _, name in ipairs({ "Water", "RayFX", "Wind", "Quality", "Voxel3D", "Ripples", "WindFX",
                          "WindLines", "VoxelScene", "Anime", "Glow", "Mist", "ChunkMesher",
                          "Weather", "AmbientLife", "WakeFX", "StepFX", "Grass3D", "Trees3D",
                          "ShadowMap", "Bloom", "TiltShift", "Sky", "CloudShade", "VegFX",
                          "LeafFallFX", "GroundFX", "PuddleFX", "FishFX" }) do
    M[name] = req(name)
  end
  local Pipelines = require("src.render.Pipelines")
  local function sync(s, v) if s then pcall(s.sync, s, v) end end
  local function get(s) if not s then return "n/a" end local ok, v = pcall(s.get, s) return tostring(ok and v) end

  pcall(love.window.setVSync, 0)
  log(("window %dx%d  voxel level %s"):format(love.graphics.getWidth(), love.graphics.getHeight(),
    tostring(Pipelines.level("terrarium_voxel"))))
  log(("settings: RES=%s FX=%s ANIME=%s GLOW=%s MIST=%s WATER=%s STYLE=%s WIND=%s SHADOWS=%s PFX=%s WEATHER=%s"):format(
    get(M.Quality.setting), get(M.RayFX.setting), get(M.Anime and M.Anime.setting), get(M.Glow and M.Glow.setting),
    get(M.Mist and M.Mist.setting), get(M.Water.setting), get(M.Water.style), get(M.Wind.setting),
    get(M.Quality.shadowSetting), get(M.Quality.particleSetting), get(M.Weather.setting)))

  -- ------- CPU per system
  local cpu, rendered, renders = {}, false, 0
  local function wrap(mod, fname, tag)
    if not (mod and type(mod[fname]) == "function") then return end
    local inner = mod[fname]
    mod[fname] = function(...)
      local t0 = love.timer.getTime()
      local r = { inner(...) }
      cpu[tag] = (cpu[tag] or 0) + (love.timer.getTime() - t0)
      return unpack(r)
    end
  end
  do
    local inner = M.VoxelScene.render
    M.VoxelScene.render = function(...)
      local t0 = love.timer.getTime()
      local c = inner(...)
      cpu["scene.render"] = (cpu["scene.render"] or 0) + (love.timer.getTime() - t0)
      renders = renders + 1
      if c then rendered = true end
      return c
    end
  end
  wrap(M.ChunkMesher, "pump", "mesher.pump")
  wrap(M.RayFX, "apply", "rayfx.apply")
  wrap(M.Glow, "prepareWorld", "glow.prepare")
  wrap(M.WindFX, "update", "windfx.update")
  wrap(M.WindFX, "drawWorld", "windfx.drawWorld")
  wrap(M.WindLines, "drawWorld", "windlines.draw")
  wrap(M.WindLines, "update", "windlines.update")
  wrap(M.Ripples, "update", "ripples")
  wrap(M.Weather, "update", "weather.update")
  wrap(M.Weather, "draw", "weather.draw")
  wrap(M.AmbientLife, "update", "ambient.update")
  wrap(M.AmbientLife, "draw", "ambient.draw")
  wrap(M.WakeFX, "update", "wake")
  wrap(M.StepFX, "update", "stepfx")
  wrap(M.VegFX, "update", "vegfx")
  wrap(M.LeafFallFX, "update", "leaffall.update")
  wrap(M.GroundFX, "update", "groundfx")
  wrap(M.FishFX, "update", "fishfx")
  wrap(M.Bloom, "apply", "bloom")
  wrap(M.TiltShift, "apply", "tiltshift")

  -- ------- one window of frames
  local function window(frames)
    for k in pairs(cpu) do cpu[k] = 0 end
    local t, good, lost = {}, 0, 0
    local dc, sw = 0, 0
    local last = love.timer.getTime()
    while good < frames do
      rendered = false
      coroutine.yield()
      local now = love.timer.getTime()
      local dt = (now - last) * 1000
      last = now
      if game.stack:top() == ow and rendered then
        good = good + 1
        t[good] = dt
        local okS, st = pcall(love.graphics.getStats)
        if okS and st then dc = dc + (st.drawcalls or 0); sw = sw + (st.canvasswitches or 0) end
      else
        lost = lost + 1
        if game.stack:top() ~= ow then
          local top = game.stack:top()
          log("  stack top is not the overworld:", tostring(top and (top.name or top.__name) or top), "-- popping")
          pcall(function() game.stack:pop() end)
          wait(30)
        end
        if lost > 1200 then return nil end
      end
    end
    local sum = 0
    for i = 1, #t do sum = sum + t[i] end
    table.sort(t)
    local c, csum = {}, 0
    for k, v in pairs(cpu) do
      local ms = v * 1000 / frames
      c[#c + 1] = { k, ms }
      if k ~= "scene.render" then csum = csum + ms end
    end
    table.sort(c, function(a, b) return a[2] > b[2] end)
    return { med = t[math.floor(#t / 2)], p95 = t[math.floor(#t * 0.95)], mean = sum / #t,
             cpu = c, lost = lost, dc = dc / frames, sw = sw / frames }
  end
  local function report(tag, r)
    if not r then log(tag, "NO 3D FRAMES") return end
    local parts = {}
    for i = 1, math.min(#r.cpu, 12) do parts[#parts + 1] = ("%s %.2f"):format(r.cpu[i][1], r.cpu[i][2]) end
    log(("%s  median %.2f ms (%.1f fps)  mean %.2f  p95 %.2f  draws %.0f  canvas sw %.0f  (lost %d)"):format(
      tag, r.med, 1000 / r.med, r.mean, r.p95, r.dc, r.sw, r.lost))
    log("   cpu ms/frame: " .. table.concat(parts, ", "))
  end

  local savedFX, savedStyle = M.RayFX.setting:get(), M.Water.style:get()
  local savedGlow = M.Glow and M.Glow.setting:get()
  local realRU, realRL = M.Ripples.update, M.Ripples.live
  local CONDS = {
    { "classic",  function() sync(M.Water.style, "classic") end, function() sync(M.Water.style, savedStyle) end },
    { "noripple", function() M.Ripples.update = function() end; M.Ripples.live = function() return false end end,
                  function() M.Ripples.update, M.Ripples.live = realRU, realRL end },
    { "nowind",   function() M.WindFX.HOLD = true; M.WindFX.clear() end, function() M.WindFX.HOLD = false end },
    { "fx_ao",    function() sync(M.RayFX.setting, "ao") end, function() sync(M.RayFX.setting, savedFX) end },
    { "noglow",   function() sync(M.Glow and M.Glow.setting, false) end, function() sync(M.Glow and M.Glow.setting, savedGlow) end },
  }

  local function spot(tag, mapId, x, y, face, surf)
    ow.player.surfing = surf and true or false
    pcall(function() ow:setMap(mapId, x, y, face) end)
    ow.player.surfing = surf and true or false
    -- wait for the 3D, then for the meshes to settle
    local up = 0
    for i = 1, 3600 do
      rendered = false
      coroutine.yield()
      if rendered then up = up + 1 else up = 0 end
      if up >= 120 then break end
    end
    wait(300)
    report(("[%s] AS PLAYED"):format(tag), window(240))
    local base, delta = {}, {}
    for cyc = 1, 3 do
      for j = 0, #CONDS - 1 do
        local c = CONDS[(j + cyc - 1) % #CONDS + 1]
        local b = window(120)
        c[2](); wait(30)
        local r = window(120)
        c[3](); wait(20)
        if b and r then
          delta[c[1]] = delta[c[1]] or {}
          table.insert(delta[c[1]], r.med - b.med)
          table.insert(base, b.med)
        end
      end
    end
    local function mean(v) local s = 0 for _, x in ipairs(v) do s = s + x end return #v > 0 and s / #v or 0 end
    log(("[%s] paired, base %.2f ms:"):format(tag, mean(base)))
    for _, c in ipairs(CONDS) do
      local d = delta[c[1]] or {}
      log(("[%s]   %-9s %+6.2f ms (n=%d: %s)"):format(tag, c[1], mean(d), #d,
        table.concat((function() local o = {} for _, v in ipairs(d) do o[#o + 1] = ("%+.1f"):format(v) end return o end)(), " ")))
    end
  end

  spot("route21-surf", "ROUTE_21", 8, 14, "down", true)
  spot("pallet", "PALLET_TOWN", 4, 13, "down", false)
  spot("route1", "ROUTE_1", 9, 24, "up", false)
  finish("done")
end
