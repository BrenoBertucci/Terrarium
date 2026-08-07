-- Does the authored 3D lamp post reach the screen, whole and lit?
--
-- Two questions the numbers alone cannot answer, which is why this probe
-- exists rather than another assertion in night_lamps_probe:
--
--   1. Is the POST whole?  The bake was shipping a lantern floating over a
--      base plate for a while, with the entire shaft missing, and every
--      count-based check passed the whole time -- the mesh loaded, the tris
--      were there, the sites were placed.  Only a picture catches it.
--   2. Does the light READ?  A pool of lamp light is a judgement about
--      contrast against the hour's tint, so the probe shoots the same frame
--      with the lamps on and off and measures the difference rather than
--      trusting that a uniform was sent.
--
-- Shots land in DS_PROBE_DIR: lamppost_night_on / _off / _day.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/lamppost_probe.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring((select(i, ...))) end
    logf:write(table.concat(p, " ") .. "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b
    coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: never booted"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end

  local lib = game.mods.exports.TERRARIUM.lib
  local DayNight = lib.require("DayNight")
  local StreetLamps = lib.require("StreetLamps")
  local Voxel3D = lib.require("Voxel3D")

  StreetLamps.setting:sync(true)
  StreetLamps.invalidate()

  -- Say it out loud. A scene shader that fails to compile does not crash and
  -- does not warn: the engine simply keeps the flat 2D renderer, every count
  -- in this probe still passes, and the screenshots look like the feature was
  -- never written. One reserved word in the GLSL is enough to cause it.
  local sh = Voxel3D.shader()
  log("voxel shader:", sh and "PASS" or "FAIL", tostring(Voxel3D.shaderError))

  -- ---- the bake actually loaded
  local authored = StreetLamps.usesAuthoredMesh()
  log("AUTHORED_MESH flag:", tostring(StreetLamps.AUTHORED_MESH))
  log(authored and "PASS: authored 3D post in use"
                or "FAIL: fell back to the box templates")
  log(string.format("flame height = %.2f world px", StreetLamps.flameHeight()))

  -- ---- stand next to one, at night, in the deepest dark the mod ships
  DayNight.setting:sync("night")
  DayNight.darkSetting:sync("deep")
  game.overworld:setMap("VIRIDIAN_CITY", 10, 10, "up")
  wait(80)
  StreetLamps.invalidate()
  local map = game.overworld.map
  log("VIRIDIAN lamps =", StreetLamps.count(map))

  local lights = StreetLamps.lights(map, 10 * 16, 10 * 16)
  log("local lights =", #lights, "of limit", StreetLamps.LIGHT_LIMIT)
  if #lights > 0 then
    local l = lights[1]
    log(string.format("nearest lamp: x=%.1f z=%.1f r=%.1f power=%.3f",
                      l.x, l.z, l.radius, l.power))
    -- Put the player two cells south of the post so the whole thing, base to
    -- lantern, is inside the frame rather than under the HUD.
    local cx = math.floor(l.x / 16)
    local cy = math.floor(l.z / 16) + 2
    pcall(function() game.overworld:setMap("VIRIDIAN_CITY", cx, cy, "up") end)
    wait(60)
  else
    log("WARN: no lights to stand under; shooting the default corner")
  end

  -- Wait for the 3D path, do not count frames at it.  The voxel scene returns
  -- nil until its terrain is meshed and the engine quietly keeps the flat 2D
  -- renderer for those frames -- during which the lamp shader does not run at
  -- all.  A fixed wait shot that 2D frame and the picture looked like the
  -- feature had simply done nothing.  Voxel3D.lampLights is only ever filled
  -- by VoxelScene.render, so it is the exact signal that the pass is live.
  local ready = false
  for _ = 1, 900 do
    if Voxel3D.lampLights and #Voxel3D.lampLights > 0 then ready = true; break end
    coroutine.yield()
  end
  log(ready and "PASS: 3D pass live with lamp pools bound"
             or "FAIL: 3D pass never came up; shots are the 2D fallback")

  local function shot(name)
    local t = DayNight.tint(true)
    log(string.format("shot %-22s tint %.4f %.4f %.4f", name, t[1], t[2], t[3]))
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name .. ".png", "wb")
      if f then f:write(data:encode("png"):getString()); f:close() end
    end)
    wait(8)
  end

  -- Let the hour SETTLE before the A/B. The night tint eases in rather than
  -- snapping, and two shots taken either side of that ease differ across the
  -- whole frame -- which reads exactly like a global lighting change and
  -- buries the local one being measured.
  wait(200)

  -- Same camera, same hour, lamps on then off then on again. The third shot
  -- is the control: if it matches the first, the difference between them and
  -- the middle one is the feature and nothing else.
  shot("lamppost_night_on")
  StreetLamps.setting:sync(false)
  wait(40)
  shot("lamppost_night_off")
  StreetLamps.setting:sync(true)
  wait(40)
  shot("lamppost_night_on2")

  -- ---- what the pools COST.
  --
  -- Eight point lights evaluated per fragment, over a city holding up to 28
  -- posts each drawn twice (scene + sun pass). On the integrated GPU this mod
  -- targets that is a real question and not a rhetorical one, so measure it
  -- the same way the picture was measured: both states, same camera.
  local function frameCost(frames)
    local t0 = love.timer.getTime()
    for _ = 1, frames do coroutine.yield() end
    return (love.timer.getTime() - t0) / frames * 1000
  end
  StreetLamps.setting:sync(true);  wait(30)
  local msOn = frameCost(150)
  StreetLamps.setting:sync(false); wait(30)
  local msOff = frameCost(150)
  StreetLamps.setting:sync(true)
  log(string.format("frame cost: lamps ON %.2f ms, OFF %.2f ms, delta %+.2f ms (%.0f%%)",
                    msOn, msOff, msOn - msOff, (msOn / math.max(msOff, 1e-6) - 1) * 100))

  DayNight.setting:sync("day")
  wait(120)
  shot("lamppost_day")

  log("done"); logf:close(); love.event.quit()
end
