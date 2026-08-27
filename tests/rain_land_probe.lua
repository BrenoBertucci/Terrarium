-- Reproduction probe: "os pingos não atingem o chão e não integram com
-- as casas". Before touching anything, look -- with counters and with
-- the screen, in BOTH tilt configs (the player's options keep T-SHIFT 3).
--
--   MECHANICS  shaft heights above their own local surface (none should
--              sit below a roof/floor), and impactMix by surface: roofs
--              collecting splashes is the "integra com as casas" claim
--              in one number.
--   PICTURES   pairs of frames a few ticks apart at PALLET (houses in
--              frame), tilt 0 and tilt 3.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/rain_land_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/rain_land.log", "w"))
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
    if n > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end
  log("version:", exports.TERRARIUM.version)

  local Weather  = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Wind     = lib.require("Wind")
  local AmbientLife = lib.require("AmbientLife")
  local VoxelScene = lib.require("VoxelScene")
  local Voxel3D  = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")

  Wind.setting:sync(1)               -- AUTO: the shipping feel
  AmbientLife.setting:sync("off")
  Pipelines.setLevel("terrarium_voxel", 4)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  DayNight.setting:sync("day")
  local ow = game.overworld
  ow:setMap("PALLET_TOWN", 12, 12, "up")
  wait(300)
  Weather.setting:sync("rain")
  wait(900)                          -- let the shower ramp to power

  -- ------- MECHANICS
  local dump = {}
  pcall(Weather.shaftDump, dump)
  log(("shafts: %d"):format(#dump))
  local below, minAbove, sumAbove, cnt = 0, 1e9, 0, 0
  local map = ow.map
  for i = 1, #dump do
    local s = dump[i]
    local cx = math.floor(s.x / 16)
    local cy = math.floor(s.z / 16)
    if map:inBounds(cx, cy) and not map:isWaterCell(cx, cy) then
      local ok, gh = pcall(VoxelScene.groundAt, map, cx, cy)
      gh = (ok and tonumber(gh)) or 0
      local above = s.y - gh
      cnt = cnt + 1
      sumAbove = sumAbove + above
      if above < minAbove then minAbove = above end
      if above < -1 then below = below + 1 end
    end
  end
  log(("heights: %d sampled  mean above-surface %.1f  min %.1f  "
       .. "BELOW their surface: %d  %s")
      :format(cnt, cnt > 0 and sumAbove / cnt or -1, minAbove, below,
              below == 0 and "PASS" or "FAIL (drops inside geometry)"))
  local mix = {}
  pcall(Weather.impactMix, mix)
  local mixs = {}
  for k, v in pairs(mix) do mixs[#mixs + 1] = k .. "=" .. v end
  table.sort(mixs)
  log("impactMix: " .. table.concat(mixs, "  "))
  log(("roof splashes live: %s  %s")
      :format(tostring(mix.roof or 0),
              (mix.roof or 0) > 0 and "PASS (casas coletam splash)"
                                   or "note: none this instant"))

  -- ------- INK A/B: the number that says the landings are BACK
  --
  -- Rings are a handful of pixels each and argue with the dither; the
  -- INK is not -- every landing stamps a lingering dark wet mark, so a
  -- patch of paving under steady rain is measurably darker when the
  -- impacts actually paint. Same camera, same shower: mean luminance of
  -- a ground patch with SPLASH_RAISE at 2 (the fix) vs 0 (the
  -- regression: decals flush with the surface, eaten by the depth tie).
  do
    -- patch luminance NORMALISED by a sky strip (no landings up there),
    -- so the shower's own global brightness drift cancels out
    local function patchLum()
      local p2 = ow.player
      local wx, wz = (p2.px or 0) + 8, (p2.py or 0) - 12
      local sx, sy = Voxel3D.project(wx, 0, wz)
      if not sx then return nil end
      local grabbed, ratio = false, nil
      love.graphics.captureScreenshot(function(data)
        local W, H = data:getWidth(), data:getHeight()
        local x0 = math.max(0, math.floor(sx) - 60)
        local y0 = math.max(0, math.floor(sy) - 30)
        local s, c = 0, 0
        for y = y0, math.min(H - 1, y0 + 60), 2 do
          for x = x0, math.min(W - 1, x0 + 120), 2 do
            local r, g2, b = data:getPixel(x, y)
            s = s + 0.2126 * r + 0.7152 * g2 + 0.0722 * b
            c = c + 1
          end
        end
        local sky, kc = 0, 0
        for y = 8, 40, 2 do
          for x = 300, 1200, 6 do
            local r, g2, b = data:getPixel(x, y)
            sky = sky + 0.2126 * r + 0.7152 * g2 + 0.0722 * b
            kc = kc + 1
          end
        end
        if c > 0 and kc > 0 and sky > 0 then
          ratio = (s / c) / (sky / kc)
        end
        grabbed = true
      end)
      local guard = 0
      while not grabbed and guard < 240 do coroutine.yield(); guard = guard + 1 end
      return ratio
    end
    local function meanLum(frames)
      local s, c = 0, 0
      for _ = 1, frames do
        local l = patchLum()
        if l then s = s + l; c = c + 1 end
        wait(12)
      end
      return c > 0 and s / c or -1
    end
    -- A-B-A: the drift control the first cut lacked (it read a phase
    -- swing as the effect). A1 ~ A2 is what makes A vs B a comparison.
    Weather.SPLASH_RAISE = 2.0
    wait(300)
    local a1 = meanLum(5)
    Weather.SPLASH_RAISE = 0.0
    wait(300)
    local b = meanLum(5)
    Weather.SPLASH_RAISE = 2.0
    wait(300)
    local a2 = meanLum(5)
    local aa = (a1 + a2) * 0.5
    local drift = math.abs(a1 - a2)
    local effect = math.abs(aa - b)
    log(("ink A-B-A (patch/sky): A1 %.4f  B %.4f  A2 %.4f  |effect| %.4f"
         .. "  |drift| %.4f  %s")
        :format(a1, b, a2, effect, drift,
                (a1 > 0 and b > 0 and a2 > 0 and effect > drift * 2
                 and effect > 0.004)
                and "PASS (os pousos mudam o chao de novo)"
                or "FAIL/inconclusive"))
  end

  -- ------- PICTURES, tilt 0
  shot("rain_t0_a.png")
  wait(3)
  shot("rain_t0_b.png")

  -- ------- PICTURES, tilt 3 (the player's own config)
  Pipelines.setLevel("terrarium_tiltshift", 3)
  wait(90)
  shot("rain_t3_a.png")
  wait(3)
  shot("rain_t3_b.png")
  Pipelines.setLevel("terrarium_tiltshift", 0)
  wait(30)

  -- ------- THE BIAS LADDER
  --
  -- 463 impact rings alive and not one on screen: the suspect is the
  -- depth discard eating decals that lie ON the surface that wrote the
  -- depth (the shader's own bias comment says this is the case it exists
  -- for -- at 0.0012 it may simply be too small). sendDepth re-reads
  -- Weather.DEPTH_BIAS every flush, so the ladder needs no reload.
  for _, bias in ipairs({ 0.004, 0.012, 0.03 }) do
    Weather.DEPTH_BIAS = bias
    wait(30)
    shot(("rain_bias_%s.png"):format(tostring(bias):gsub("%.", "p")))
    log(("bias ladder: shot at %.4f"):format(bias))
  end
  Weather.DEPTH_BIAS = 0.0012

  -- a second impact reading after the pictures: rings are short-lived
  local mix2 = {}
  pcall(Weather.impactMix, mix2)
  local m2 = {}
  for k, v in pairs(mix2) do m2[#m2 + 1] = k .. "=" .. v end
  table.sort(m2)
  log("impactMix (later): " .. table.concat(m2, "  "))
  log(("failState: %s"):format(tostring(Weather.failState
                                        and Weather.failState() or "?")))
  log("done")
  logf:close()
  love.event.quit()
end
