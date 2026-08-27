-- SUPERSEDED by tests/sun_shadow_card2_probe.lua -- this version verified
-- its placement with a ray-walk over CLASS heights, and the round hulls
-- (trees, fence posts) that dominate Pallet's casters are mostly air at
-- their class height, so "verified blocked" spots measured sunlit. Kept
-- for the record; v2 finds real shadow with the renderer itself.
--
-- T5, passo final: does the SUN's shadow map land on a particle card?
--
-- The scene shader gates the sun's share of every fragment on
-- sunlight(vSun), and cards ride the same vertex path as terrain, so in
-- theory a card standing in a building's cast shadow loses the sun term
-- and keeps only skyTint. This is the measurement.
--
-- ------- THE A/B IS TWO POSITIONS, VERIFIED A PRIORI IN LUA
--
-- No toggle can settle this one (turning shadows off relights the card
-- only if it stood in shadow to begin with -- circular), so the A/B is
-- shadow-vs-sun placement, and the probe PROVES each placement before
-- shooting it: from the mote's position it walks the ray toward the sun
-- (displacement (-KX,+1,-KZ) per unit height, the same shear the shadow
-- map renders with) sampling WindFX.groundAt -- for the shadow spot the
-- walk must hit a roof, for the open spot it must reach the sky clean.
-- The building itself is found the same way: groundAt returns roof height
-- over a building cell, so a west wall with clear ground beside it is a
-- pattern in that field. At the "day" pin the shear is (-0.85, -0.55):
-- shadows fall west-and-north, one caster-height long -- so a mote hugging
-- a west wall is inside, side-on to the camera, and visible.
--
-- Magenta mote, blanks for the bleed, overlay trio as negative control --
-- the rig tests/lamp_card_probe.lua proved.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/sun_shadow_card_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/sun_shadow_card.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  -- waits for its own callback; armadilha 7 in PARTICLES-PLAN.md
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
  local ShadowMap = lib.require("ShadowMap")
  local Quality  = lib.require("Quality")
  local Voxel3D  = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")

  Weather.setting:sync("off")
  Wind.setting:sync(2)
  AmbientLife.setting:sync("off")
  Quality.shadowSetting:sync("high")   -- full-size map: real cast shadows
  Pipelines.setLevel("terrarium_voxel", 4)
  Pipelines.setLevel("terrarium_tiltshift", 0)

  local sh = Voxel3D.shader()
  log("voxel shader:", sh and "PASS" or ("FAIL " .. tostring(Voxel3D.shaderError)))

  DayNight.setting:sync("day")
  local ow = game.overworld
  ow:setMap("PALLET_TOWN", 12, 12, "up")
  wait(600)
  local p = ow.player
  log(("map %s  player %d,%d"):format(ow.map.id, p.cellX, p.cellY))
  log("ShadowMap.active:", tostring(ShadowMap.active()))

  local ray = ShadowMap.sunDir()
  local KX, KZ = ShadowMap.KX, ShadowMap.KZ
  log(("shear KX=%.3f KZ=%.3f  sunDir=(%.3f,%.3f,%.3f)")
      :format(KX or 0, KZ or 0, ray[1], ray[2], ray[3]))

  local function groundAt(x, z)
    local ok, g = pcall(WindFX.groundAt, x, z)
    return (ok and tonumber(g)) or 0
  end

  -- ------- find a west wall with clear ground beside it
  --
  -- Pallet's collision profile is 16 high EVERYWHERE it is high at all
  -- (houses, the lab, the border trees -- measured by
  -- tests/ground_grid_dump.lua), so the shadow a wall throws is one
  -- caster-height ~= one cell to the west. Two building cells stacked in z
  -- (the sun ray drifts south on its way up), and two clear cells west of
  -- them for the mote and the line of sight. Scanned nearest-first in z so
  -- the wall found is close to the view centre.
  local B = nil
  for dz = 0, 9 do
    for _, cz in ipairs({ p.cellY - dz, p.cellY + dz }) do
      for cx = p.cellX - 10, p.cellX + 10 do
        local g1 = groundAt(cx * 16 + 8, cz * 16 + 8)
        local g2 = groundAt(cx * 16 + 8, cz * 16 + 24)
        local w1 = groundAt(cx * 16 - 8, cz * 16 + 8)
        local w2 = groundAt(cx * 16 - 24, cz * 16 + 8)
        if g1 >= 14 and g2 >= 14 and w1 <= 2 and w2 <= 2 then
          B = { cx = cx, cz = cz, h = math.min(g1, g2) }
          break
        end
      end
      if B then break end
    end
    if B then break end
  end
  if not B then
    log("FAIL: no west wall with clear ground found"); logf:close(); love.event.quit(); return
  end
  local wallX = B.cx * 16
  log(("building cell %d,%d  roof %.1f  west wall x=%d"):format(B.cx, B.cz, B.h, wallX))

  -- Shadow mote: 5 px west of the wall, low. With a 16-high caster the
  -- geometry is tight: the sun ray gains ~1 unit of height per unit of
  -- horizontal travel (shear length 1.01), so a card corner at west edge
  -- d and top y hits the wall plane at y+d -- every corner must land
  -- under the roof. Size-3 puff (half extents ~3.2 x 3.0) at d=5,
  -- y=ground+3.5 puts the worst corner at ~14.7 against a roof of 16.
  local SX, SZ = wallX - 5, B.cz * 16 + 8
  local SY = groundAt(SX, SZ) + 3.5

  local function rayWalk(x, y, z)
    for h = y + 1, y + 44 do
      local rx = x - (KX or 0) * (h - y)
      local rz = z - (KZ or 0) * (h - y)
      if groundAt(rx, rz) >= h - 0.5 then
        return h, groundAt(rx, rz)
      end
    end
    return nil
  end

  -- Open mote: any clear cell whose whole ring of neighbours is clear and
  -- whose own sun ray reaches the sky, far enough from the shadow spot
  -- that the two crops cannot overlap.
  local OX, OY, OZ
  for dz = 0, 9 do
    for _, cz in ipairs({ p.cellY + dz, p.cellY - dz }) do
      for cx = p.cellX - 8, p.cellX + 8 do
        local clear = true
        for nz = -1, 1 do
          for nx = -1, 1 do
            if groundAt((cx + nx) * 16 + 8, (cz + nz) * 16 + 8) > 2 then
              clear = false
            end
          end
        end
        if clear then
          local x, z = cx * 16 + 8, cz * 16 + 8
          local dxs, dzs = x - SX, z - SZ
          if dxs * dxs + dzs * dzs > 80 * 80 then
            local y = groundAt(x, z) + 3.5
            if not rayWalk(x, y, z) then
              OX, OY, OZ = x, y, z
              break
            end
          end
        end
      end
      if OX then break end
    end
    if OX then break end
  end
  if not OX then
    log("FAIL: no provably sunlit open cell found"); logf:close(); love.event.quit(); return
  end

  -- ------- prove the shadow placement, corners included
  local hw, hh = 3.3, 3.0        -- size-3 puff half extents, plus margin
  local corners = {
    { SX - hw, SY + hh }, { SX + hw, SY + hh },
    { SX - hw, SY - hh }, { SX + hw, SY - hh },
  }
  local allBlocked = true
  for i, c in ipairs(corners) do
    local bh = rayWalk(c[1], c[2], SZ)
    log(("  shadow corner %d (%.1f,%.1f): %s")
        :format(i, c[1], c[2], bh and ("blocked at h=" .. bh) or "SUNLIT"))
    if not bh then allBlocked = false end
  end
  local sh1 = rayWalk(SX, SY, SZ)
  log(("shadow mote %.1f,%.1f,%.1f  centre %s  corners %s")
      :format(SX, SY, SZ, sh1 and "BLOCKED" or "SUNLIT (BAD)",
              allBlocked and "ALL BLOCKED" or "PARTLY SUNLIT"))
  log(("open   mote %.1f,%.1f,%.1f  ray CLEAR"):format(OX, OY, OZ))
  if not sh1 then
    log("FAIL: shadow placement not provable"); logf:close(); love.event.quit(); return
  end

  WindFX.HOLD = true
  local function shotAt(name)
    local ssx, ssy = Voxel3D.project(SX, SY, SZ)
    local osx, osy = Voxel3D.project(OX, OY, OZ)
    log(("      %-26s S at %s,%s  O at %s,%s")
        :format(name, tostring(ssx and math.floor(ssx)), tostring(ssy and math.floor(ssy)),
                tostring(osx and math.floor(osx)), tostring(osy and math.floor(osy))))
    shot(name)
  end

  wait(120)   -- let the hour and the shadow pass settle

  WindFX.WORLD_PASS = true
  WindFX.pinOne("puff", SX, SY, SZ, 3)
  wait(20)
  shotAt("sun_world_shadow.png")
  WindFX.pinOne("puff", OX, OY, OZ, 3)
  wait(20)
  shotAt("sun_world_open.png")

  WindFX.WORLD_PASS = false
  WindFX.pinOne("puff", SX, SY, SZ, 3)
  wait(20)
  shotAt("sun_overlay_shadow.png")
  WindFX.pinOne("puff", OX, OY, OZ, 3)
  wait(20)
  shotAt("sun_overlay_open.png")

  -- the road alone: one frame serves both crops (mote parked far west,
  -- outside the view like the lamp probe's blank)
  WindFX.pinOne("puff", SX - 300, SY, SZ, 3)
  wait(20)
  shotAt("sun_blank.png")

  WindFX.WORLD_PASS = true
  WindFX.HOLD = false
  log("done")
  logf:close()
  love.event.quit()
end
