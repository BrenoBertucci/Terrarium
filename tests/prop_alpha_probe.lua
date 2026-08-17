-- Does a PROP mesh honour its texture's alpha channel, and how?
--
-- This decides what we are allowed to ask a model generator for. A tree
-- canopy is either alpha-cut cards (cheap, dense, pretty) or closed volume
-- (expensive, blobby) and the two are different models -- generating before
-- knowing means generating twice.
--
-- Voxel3D's shader has `if (p.a < 0.5) discard;` but it is documented as
-- being for SPRITE SHEETS keying the Game Boy's OBJ colour 0. Nothing says
-- the prop path reaches that branch, and no prop ships with an alpha channel
-- today: grass.png is RGBA with alpha 255 everywhere, lamppost.png is RGB.
--
-- So: draw one quad through the exact call the props use --
-- Voxel3D.draw(mesh, tex, xf, 0, xf) -- with a texture in three vertical
-- bands, and read the frame back.
--
--   band   colour   alpha    if DISCARD(0.5)   if BLEND      if IGNORED
--   left   red      1.00     solid red         solid red     solid red
--   mid    green    0.30     GONE              ghost green   solid green
--   right  blue     0.00     GONE              GONE          solid blue
--
-- Three outcomes, three different plans:
--   discard  -> canopies can be alpha cards. Best case.
--   blend    -> usable, but transparent texels still write depth; foliage
--               needs draw-order care or it punches holes in what is behind.
--   ignored  -> closed volume only; the grass tuft stays 6 solid quads
--               forever and no amount of model generation fixes it.
--
-- Shot lands in DS_PROBE_DIR as prop_alpha.png; the counts are in the log,
-- so the verdict is a measurement and not my reading of a picture.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/prop_alpha_probe.log", "w"))
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
  local Mat4 = lib.require("Mat4")

  -- A shader that fails to compile does not crash and does not warn: the
  -- engine keeps the 2D renderer, every assert below still passes and the
  -- screenshot looks like nothing was drawn. Say it out loud first.
  local sh = Voxel3D.shader()
  log("voxel shader:", sh and "PASS" or "FAIL", tostring(Voxel3D.shaderError))

  -- ---- the test texture: three vertical bands, three alphas
  local SZ = 96
  local data = love.image.newImageData(SZ, SZ)
  data:mapPixel(function(x)
    local t = x / SZ
    if t < 1 / 3 then return 1, 0, 0, 1.0      -- opaque red    (control)
    elseif t < 2 / 3 then return 0, 1, 0, 0.30 -- 30% green     (discard vs blend)
    else return 0, 0, 1, 0.0 end               -- zero blue     (cut-out)
  end)
  local tex = love.graphics.newImage(data)
  tex:setFilter("nearest", "nearest")

  -- ---- one quad, upright, facing south (the camera looks north)
  -- Vertex layout is Voxel3D.FORMAT: x y z u v shade. Shade magnitude is
  -- brightness and its SIGN is the "faces the sky" flag -- keep it positive
  -- and flat so nothing here is mistaken for a roof.
  local W, H, Y0 = 30, 30, 3
  local quad = Voxel3D.newMesh({
    { -W / 2, Y0,     0, 0, 1, 1.0 },
    {  W / 2, Y0,     0, 1, 1, 1.0 },
    {  W / 2, Y0 + H, 0, 1, 0, 1.0 },
    { -W / 2, Y0 + H, 0, 0, 0, 1.0 },
  }, { 1, 2, 3, 1, 3, 4 })
  log(quad and "PASS: test quad built" or "FAIL: newMesh refused the quad")
  if not quad then logf:close(); love.event.quit(); return end

  -- ---- stand in a town, in daylight, next to a lamp site
  DayNight.setting:sync("day")
  -- The LAMPS row gates sitesFor: with it off, lights() returns {} on its
  -- first line and the whole prop pass has nothing to ride.
  StreetLamps.setting:sync(true)
  game.overworld:setMap("VIRIDIAN_CITY", 10, 10, "up")
  wait(80)
  StreetLamps.invalidate()
  local map = game.overworld.map
  log("VIRIDIAN lamps =", StreetLamps.count(map))
  local lights = StreetLamps.lights(map, 10 * 16, 10 * 16)
  log("lamp sites near start =", #lights)

  local qx, qz = 10 * 16, 10 * 16
  if #lights > 0 then
    qx, qz = lights[1].x, lights[1].z
    local cx = math.floor(qx / 16)
    local cy = math.floor(qz / 16) + 2
    pcall(function() game.overworld:setMap("VIRIDIAN_CITY", cx, cy, "up") end)
    wait(60)
  end

  -- Ride the prop pass itself rather than inventing a second one: whatever
  -- state the lamps are drawn under is exactly the state a tree would be
  -- drawn under. Draw the quad FIRST so it lands even on a map with no sites.
  local realDraw = StreetLamps.draw
  StreetLamps.draw = function(m, outdoor, ox, oz)
    if outdoor and Voxel3D.available() then
      local xf = Mat4.translate(qx + (tonumber(ox) or 0), 0,
                                qz + (tonumber(oz) or 0) - 6)
      pcall(Voxel3D.draw, quad, tex, xf, 0, xf)
    end
    return realDraw(m, outdoor, ox, oz)
  end

  -- The 3D pass takes time to come up after setMap and returns nil until the
  -- terrain is meshed -- counting frames shoots the 2D fallback. lampLights
  -- is only ever assigned by VoxelScene.render (VoxelScene.lua:951), so it
  -- is the real signal -- but the test is NON-NIL, not non-empty: a map with
  -- no lamps legitimately gets `{}` and would never pass a `#> 0` check.
  local ready = false
  for _ = 1, 900 do
    if Voxel3D.lampLights ~= nil then ready = true; break end
    coroutine.yield()
  end
  log(ready and "PASS: 3D pass live" or "FAIL: 3D pass never came up (2D shot)")
  wait(120)

  love.graphics.captureScreenshot(function(d)
    local f = io.open(OUT .. "/prop_alpha.png", "wb")
    if f then f:write(d:encode("png"):getString()); f:close() end
  end)
  wait(20)

  -- The verdict is counted off prop_alpha.png by tools/read_alpha_probe.py,
  -- not read off the picture by eye: the scene tints what it draws, so the
  -- bands have to be classified by dominant channel with a margin.
  StreetLamps.draw = realDraw
  log("done")
  logf:close()
  wait(10)
  love.event.quit()
end
