-- T5, passo final, v2: does the sun's shadow map land on a particle card?
--
-- ------- WHY v1 DIED, AND WHAT THIS ONE DOES DIFFERENTLY
--
-- v1 proved its placement with a ray-walk over WindFX.groundAt -- CLASS
-- heights. The border trees it picked as caster are round hulls whose
-- real voxels fall away from the class height, and the card measured
-- fully sunlit inside a "verified" shadow. Worse, the wide blank shows no
-- obvious cast shadow anywhere in Pallet at the day pin -- so before
-- measuring the card, this probe first has to find a patch of ground the
-- shadow map PROVABLY darkens, using the renderer itself as the oracle:
--
--   1. Capture the town with shadows HIGH, OFF, HIGH again (no mote).
--      Read the frames back (captureScreenshot hands over ImageData) at a
--      grid of candidate ground points, projected in the same resume the
--      capture is scheduled in. A real shadow texel is darker in both
--      HIGH frames and lighter in the OFF frame, consistently -- an NPC
--      wandering across a candidate fails the consistency test.
--   2. Among consistent candidates prefer one whose sun ray blocks LOW
--      (class-height walk again, but now only as a relative rank for
--      headroom): the card floats 3.5 up and needs the shadow volume to
--      still be over it at that height.
--   3. Pin the magenta card there and run the same toggle A/B the lamp
--      probe proved: shadows HIGH / OFF / HIGH with the card in the world
--      pass, then HIGH / OFF through the overlay (negative control), the
--      discovery frames doubling as the per-state blanks.
--
-- If step 1 finds no consistent darkening anywhere, that is the finding:
-- the sun pass casts nothing on this map at this hour, and no card can
-- receive what is not rendered.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/sun_shadow_card2_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/sun_shadow_card2.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  -- capture that both saves the PNG and hands the ImageData back for
  -- pixel reads; waits for its own callback (armadilha 7)
  local function shotData(name)
    local done, keep = false, nil
    love.graphics.captureScreenshot(function(data)
      keep = data
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      done = true
    end)
    local guard = 0
    while not done and guard < 240 do coroutine.yield(); guard = guard + 1 end
    return keep
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
  Quality.shadowSetting:sync("high")
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
  log("ShadowMap.active:", tostring(ShadowMap.active()),
      " shadows row:", tostring(Quality.shadows()))
  local KX, KZ = ShadowMap.KX or 0, ShadowMap.KZ or 0
  log(("shear KX=%.3f KZ=%.3f"):format(KX, KZ))

  local function groundAt(x, z)
    local ok, g = pcall(WindFX.groundAt, x, z)
    return (ok and tonumber(g)) or 0
  end
  -- how much height the sun ray gains before something with class height
  -- blocks it; huge when nothing does. Relative rank only.
  local function blockRise(x, y, z)
    for h = y + 1, y + 40 do
      if groundAt(x - KX * (h - y), z - KZ * (h - y)) >= h - 0.5 then
        return h - y
      end
    end
    return 999
  end

  local function lum(r, g, b) return 0.2126 * r + 0.7152 * g + 0.0722 * b end
  local function shadowsOn(on)
    Quality.shadowSetting:sync(on and "high" or "off")
    wait(40)
  end

  -- ------- step 1: find ground the shadow map provably darkens
  --
  -- Candidates on an 8px grid around the player; projected once, in the
  -- same resume the first capture is scheduled in. The camera is an idle
  -- orbit here and drifts a pixel or two over the trio, which a 50px-wide
  -- shadow band does not care about.
  local cands = {}
  for wz = (p.cellY - 9) * 16, (p.cellY + 5) * 16, 8 do
    for wx = (p.cellX - 10) * 16, (p.cellX + 10) * 16, 8 do
      if groundAt(wx, wz) <= 2 then
        local sx, sy = Voxel3D.project(wx, groundAt(wx, wz) + 0.5, wz)
        if sx and sy and sx > 8 and sy > 8 then
          cands[#cands + 1] = { wx = wx, wz = wz, sx = sx, sy = sy }
        end
      end
    end
  end
  log(#cands .. " ground candidates on screen")

  local dOn = shotData("disc_on.png")
  shadowsOn(false)
  local dOff = shotData("disc_off.png")
  shadowsOn(true)
  local dOn2 = shotData("disc_on2.png")
  if not (dOn and dOff and dOn2) then
    log("FAIL: discovery capture missing"); logf:close(); love.event.quit(); return
  end

  local W, H = dOn:getWidth(), dOn:getHeight()
  -- v2 first ran with a mixed delta/headroom score and put the card at
  -- y 3.5..6.5 in a SHALLOW volume: the card straddled the shadow's
  -- ceiling, only ~a third of its pixels lost the sun, and the toggle
  -- moved the mean a reproducible but dilute 14%. So: DEPTH first. Among
  -- solidly dark candidates (delta >= 0.30) take the lowest blocker, and
  -- the card below flies lower and smaller so the whole card fits under
  -- it.
  local dark = {}
  local nDark = 0
  for _, c in ipairs(cands) do
    local x, y = math.floor(c.sx), math.floor(c.sy)
    if x >= 0 and y >= 0 and x < W and y < H then
      local r1, g1, b1 = dOn:getPixel(x, y)
      local r2, g2, b2 = dOff:getPixel(x, y)
      local r3, g3, b3 = dOn2:getPixel(x, y)
      local l1, l2, l3 = lum(r1, g1, b1), lum(r2, g2, b2), lum(r3, g3, b3)
      local delta = l2 - (l1 + l3) * 0.5
      if math.abs(l1 - l3) < 0.03 and delta > 0.03 then
        nDark = nDark + 1
        if delta >= 0.30 then
          local rise = blockRise(c.wx, groundAt(c.wx, c.wz) + 2.2, c.wz)
          dark[#dark + 1] = { c = c, delta = delta, rise = rise }
        end
      end
    end
  end
  log(nDark .. " candidates consistently darkened; "
      .. #dark .. " deeply (delta >= 0.30)")
  table.sort(dark, function(a, b)
    if a.rise ~= b.rise then return a.rise < b.rise end
    return a.delta > b.delta
  end)
  for i = 1, math.min(5, #dark) do
    local d = dark[i]
    log(("  #%d world %d,%d  delta %.3f  blockRise %s")
        :format(i, d.c.wx, d.c.wz, d.delta, tostring(d.rise)))
  end
  local best = dark[1]
  if not best then
    log("FINDING: the sun pass darkens NO sampled ground on this map at")
    log("this hour -- there is no cast shadow for a card to stand in.")
    logf:close(); love.event.quit(); return
  end
  local SX, SZ = best.c.wx, best.c.wz
  local SY = groundAt(SX, SZ) + 2.2
  log(("shadow spot %.1f,%.1f,%.1f  screen %d,%d  delta %.3f  blockRise %s")
      :format(SX, SY, SZ, best.c.sx, best.c.sy, best.delta, tostring(best.rise)))

  -- ------- step 2: the card, against the shadow toggle
  WindFX.HOLD = true
  local function shotAt(name)
    local sx, sy = Voxel3D.project(SX, SY, SZ)
    log(("      %-26s card at screen %s,%s")
        :format(name, tostring(sx and math.floor(sx)),
                tostring(sy and math.floor(sy))))
    shotData(name)
  end

  WindFX.WORLD_PASS = true
  WindFX.pinOne("puff", SX, SY, SZ, 2)
  wait(20)
  shotAt("card_world_shadow.png")        -- shadows HIGH: card in shade
  shadowsOn(false)
  shotAt("card_world_sunlit.png")        -- shadows OFF: same spot, full sun
  shadowsOn(true)
  shotAt("card_world_shadow2.png")       -- drift control

  WindFX.WORLD_PASS = false
  wait(8)
  shotAt("card_overlay_shadow.png")
  shadowsOn(false)
  shotAt("card_overlay_sunlit.png")
  shadowsOn(true)

  WindFX.WORLD_PASS = true
  WindFX.HOLD = false
  log("done")
  logf:close()
  love.event.quit()
end
