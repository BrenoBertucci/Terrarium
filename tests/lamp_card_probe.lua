-- T5, passo um: does a street lamp's POINT light land on a particle card?
--
-- The scene shader adds the eight lamp pools to `light` before any
-- material is shaded, and drawParticles draws through that same shader
-- with the lamp uniforms still standing (they are sent once per scene).
-- So in THEORY a card in the pool warms exactly like a wall does -- as a
-- flank, since particles write shade +1 and vUp = step(shade, 0) reads
-- that as "not a top face". This probe is the measurement: theory has
-- been wrong in this pipeline before (the ANIME rim lit the whole floor).
--
-- ------- THE A/B IS THE LAMP TOGGLE, NOT TWO POSITIONS
--
-- One magenta mote (WindFX.pinOne -- nothing in a Game Boy palette is red
-- AND blue at once), pinned INSIDE the nearest post's pool, photographed
-- with the lamps on, off, and on again -- same camera, same hour, same
-- card. The third shot is the drift control. If the card takes the lamp,
-- its pixels change with the toggle; if only the road behind it changes,
-- they move by the alpha bleed and nothing more.
--
-- The same trio through the OVERLAY path is the negative control: that
-- path never sees the scene shader, so its mote must NOT respond to the
-- toggle beyond the bleed. And a blank pair (mote parked off-frame, lamps
-- on/off) measures the bleed itself: the mote blends at 0.75, so a
-- quarter of every measured pixel is road.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/lamp_card_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/lamp_card.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  -- waits for its own callback; see armadilha 7 in PARTICLES-PLAN.md
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
  local WindFX   = lib.require("WindFX")
  local AmbientLife = lib.require("AmbientLife")
  local StreetLamps = lib.require("StreetLamps")
  local Voxel3D  = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")

  Weather.setting:sync("off")
  Wind.setting:sync(2)
  AmbientLife.setting:sync("off")     -- no critters wandering the frame
  StreetLamps.setting:sync(true)
  Pipelines.setLevel("terrarium_voxel", 4)
  Pipelines.setLevel("terrarium_tiltshift", 0)

  -- a shader that failed to compile keeps the 2D renderer without a word,
  -- and every shot below would be measuring the fallback
  local sh = Voxel3D.shader()
  log("voxel shader:", sh and "PASS" or ("FAIL " .. tostring(Voxel3D.shaderError)))

  DayNight.setting:sync("night")
  DayNight.darkSetting:sync("deep")
  local ow = game.overworld
  ow:setMap("VIRIDIAN_CITY", 10, 10, "up")
  wait(120)

  -- nearest post to the default corner, then stand two cells south of it
  local lights = StreetLamps.lights(ow.map, 10 * 16, 10 * 16)
  if #lights == 0 then
    log("FAIL: no lamp sites on VIRIDIAN_CITY"); logf:close(); love.event.quit(); return
  end
  local l0 = lights[1]
  local cx, cy = math.floor(l0.x / 16), math.floor(l0.z / 16) + 2
  pcall(function() ow:setMap("VIRIDIAN_CITY", cx, cy, "up") end)
  wait(120)

  -- the pass is live exactly when VoxelScene fills the lamp list
  local ready = false
  for _ = 1, 900 do
    if Voxel3D.lampLights and #Voxel3D.lampLights > 0 then ready = true break end
    coroutine.yield()
  end
  log(ready and "PASS: 3D pass live, lamp pools bound"
             or "FAIL: 3D pass never came up")

  -- re-read from where the player stands NOW: the sort is by distance
  local p = ow.player
  lights = StreetLamps.lights(ow.map, p.cellX * 16 + 8, p.cellY * 16 + 8)
  local L = lights[1]
  local lampH = Voxel3D.lampHeight or Voxel3D.LAMP_HEIGHT
  log(("lamp: x=%.1f z=%.1f r=%.1f power=%.3f  flameH=%.1f  glow=%.2f")
      :format(L.x, L.z, L.radius, L.power, lampH, Voxel3D.LAMP_GLOW or -1))
  log(("player cell %d,%d"):format(p.cellX, p.cellY))

  -- the mote: inside the pool, east and camera-side of the post so the
  -- shaft cannot occlude it, at dust height off the actual ground
  local MX, MZ = L.x + 10, L.z + 8
  local ground = 0
  do
    local okG, g = pcall(WindFX.groundAt, MX, MZ)
    if okG and tonumber(g) then ground = g end
  end
  local MY = ground + 9
  log(("mote at %.1f,%.1f,%.1f (ground %.1f)"):format(MX, MY, MZ, ground))
  -- parking spot for the blank pair: far outside the crop, same map
  local FARX = MX - 200

  WindFX.HOLD = true
  local function shotAt(name)
    local sx, sy = Voxel3D.project(MX, MY, MZ)
    local t = DayNight.tint(true)
    log(("      %-24s mote at screen %s,%s  tint %.3f %.3f %.3f")
        :format(name, tostring(sx and math.floor(sx)),
                tostring(sy and math.floor(sy)), t[1], t[2], t[3]))
    shot(name)
  end
  local function lamps(on)
    StreetLamps.setting:sync(on)
    wait(40)
  end

  -- let the night tint finish easing before any A/B
  wait(200)

  -- ------- the scene-pass card, against the toggle
  WindFX.WORLD_PASS = true
  WindFX.pinOne("puff", MX, MY, MZ)
  wait(20)
  shotAt("card_world_on.png")
  lamps(false)
  shotAt("card_world_off.png")
  lamps(true)
  shotAt("card_world_on2.png")

  -- ------- the overlay mote, which must NOT respond
  WindFX.WORLD_PASS = false
  wait(8)
  shotAt("card_overlay_on.png")
  lamps(false)
  shotAt("card_overlay_off.png")
  lamps(true)

  -- ------- the road alone, both states, for the bleed
  WindFX.pinOne("puff", FARX, MY, MZ)
  wait(8)
  shotAt("card_blank_on.png")
  lamps(false)
  shotAt("card_blank_off.png")
  lamps(true)

  WindFX.WORLD_PASS = true
  WindFX.HOLD = false
  log("done")
  logf:close()
  love.event.quit()
end
