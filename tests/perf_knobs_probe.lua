-- Probe: what each row costs on THIS machine, from the player's own settings,
-- at one settled spot (Pallet: no meshes left to build), encounters off, vsync
-- off. Each knob is switched in memory (sync, never written), measured against
-- the base in a pair taken right next to it, three times with the order
-- rotated. Also the render sections for base and for RES 1/2, which says
-- whether the shadow section is the sun pass's own work or a GPU wait.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/perf_knobs.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local okAll, err = pcall(function()
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b) game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield() end
  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do wait(1); n = n + 1; if n > 900 then break end end
  n = 0
  while game.stack:top() ~= game.overworld do tap("a"); wait(10); n = n + 11; if n > 1500 then break end end
  local ow = game.overworld
  ow.rollEncounter = function() return nil end
  pcall(love.window.setVSync, 0)
  local lib = game.mods.exports.TERRARIUM.lib
  local function req(x) local ok, m = pcall(lib.require, x) return ok and m or nil end
  local VoxelScene, Quality, RayFX, Anime, Glow, Mist, Water = req("VoxelScene"), req("Quality"),
    req("RayFX"), req("Anime"), req("Glow"), req("Mist"), req("Water")
  local Pipelines = require("src.render.Pipelines")
  local clock = love.timer.getTime
  local function sync(s, v) if s then pcall(s.sync, s, v) end end
  local function get(s) local ok, v = pcall(s.get, s) return ok and v or nil end

  pcall(function() ow:setMap(os.getenv("DS_MAP") or "PALLET_TOWN", 4, 13, "down") end)
  local t0 = clock()
  while clock() - t0 < 35 do coroutine.yield(); if game.stack:top() ~= ow then pcall(function() game.stack:pop() end) end end

  local function window(secs, sections)
    if sections then VoxelScene.PROFILE = {} end
    local frames = 0
    local tS = clock()
    while clock() - tS < secs do
      coroutine.yield(); frames = frames + 1
      if game.stack:top() ~= ow then pcall(function() game.stack:pop() end) end
    end
    local ms = (clock() - tS) * 1000 / frames
    local P = VoxelScene.PROFILE
    VoxelScene.PROFILE = nil
    return ms, P, frames
  end
  local function sections(tag, P, frames)
    local arr = {}
    for k, v in pairs(P) do if k ~= "_t" then arr[#arr + 1] = { k, v * 1000 / frames } end end
    table.sort(arr, function(a, b) return a[2] > b[2] end)
    local parts = {}
    for i = 1, math.min(8, #arr) do parts[#parts + 1] = ("%s %.2f"):format(arr[i][1], arr[i][2]) end
    log(("   %s sections: %s"):format(tag, table.concat(parts, ", ")))
  end

  local saved = {
    res = get(Quality.setting), fx = get(RayFX.setting), anime = get(Anime.setting),
    glow = get(Glow.setting), mist = get(Mist.setting), shadow = get(Quality.shadowSetting),
    style = get(Water.style), tilt = Pipelines.level("terrarium_tiltshift"),
  }
  log("saved:", saved.res, saved.fx, saved.anime, tostring(saved.glow), saved.mist, saved.shadow, saved.style,
    "tilt", tostring(saved.tilt))
  local KNOBS = {
    { "RES 1/2",      function() sync(Quality.setting, 2) end, function() sync(Quality.setting, saved.res) end },
    { "SCREEN FX AO", function() sync(RayFX.setting, "ao") end, function() sync(RayFX.setting, saved.fx) end },
    { "SCREEN FX OFF",function() sync(RayFX.setting, "off") end, function() sync(RayFX.setting, saved.fx) end },
    { "SHADOWS LOW",  function() sync(Quality.shadowSetting, "low") end, function() sync(Quality.shadowSetting, saved.shadow) end },
    { "SHADOWS OFF",  function() sync(Quality.shadowSetting, "off") end, function() sync(Quality.shadowSetting, saved.shadow) end },
    { "ANIME CEL",    function() sync(Anime.setting, "cel") end, function() sync(Anime.setting, saved.anime) end },
    { "GLOW OFF",     function() sync(Glow.setting, false) end, function() sync(Glow.setting, saved.glow) end },
    { "MIST OFF",     function() sync(Mist.setting, "off") end, function() sync(Mist.setting, saved.mist) end },
    { "T-SHIFT OFF",  function() pcall(Pipelines.setLevel, "terrarium_tiltshift", 0) end,
                      function() pcall(Pipelines.setLevel, "terrarium_tiltshift", saved.tilt) end },
    { "WATER CLASSIC",function() sync(Water.style, "classic") end, function() sync(Water.style, saved.style) end },
  }
  -- the sections, base and half res
  do
    local ms, P, f = window(6, true)
    log(("base %.1f ms"):format(ms)); sections("base", P, f)
    sync(Quality.setting, 2); wait(60)
    ms, P, f = window(6, true)
    log(("RES 1/2 %.1f ms"):format(ms)); sections("RES 1/2", P, f)
    sync(Quality.setting, saved.res); wait(60)
  end
  local d = {}
  for cyc = 1, 3 do
    for j = 0, #KNOBS - 1 do
      local k = KNOBS[(j + cyc - 1) % #KNOBS + 1]
      local b = window(3)
      k[2](); wait(40)
      local r = window(3)
      k[3](); wait(40)
      d[k[1]] = d[k[1]] or {}
      table.insert(d[k[1]], { b, r })
    end
  end
  log("knob             base ms -> with knob ms   (3 pairs)   mean saving")
  for _, k in ipairs(KNOBS) do
    local sb, sr, parts = 0, 0, {}
    for _, pr in ipairs(d[k[1]]) do
      sb = sb + pr[1]; sr = sr + pr[2]
      parts[#parts + 1] = ("%.1f->%.1f"):format(pr[1], pr[2])
    end
    log(("%-15s %s   %+.1f ms"):format(k[1], table.concat(parts, "  "), (sr - sb) / #d[k[1]]))
  end
  end)
  if not okAll then log("ERROR", tostring(err)) end
  logf:close()
  love.event.quit()
end
