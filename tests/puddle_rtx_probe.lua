-- Probe: does a PUDDLE reflect, and does it move while it rains.
--
-- The bug this exists for was invisible in exactly the way a screenshot
-- cannot settle. The reflection was being computed, marched, hit and mixed
-- in -- every stage of it worked -- at a strength of about a tenth, under a
-- decal drawn at ninety percent alpha. So the row did its job, cost its
-- milliseconds, and produced a puddle indistinguishable from one with the
-- row switched off. "It does not reflect" and "it reflects at a twelfth of
-- the pixel" are the same picture and they are not the same bug.
--
-- So this probe does two things a screenshot cannot:
--
--   it PRINTS THE NUMBER.  The Fresnel term is arithmetic on the camera
--   angle and nothing else, so the share of the pixel a reflection is
--   allowed can be worked out here, per camera rung, and written down. A
--   regression in it is then a diff rather than an argument about a picture.
--
--   it SHOOTS THE PAIR.  Same map, same cell, same hour, same shower, RTX
--   OFF and RTX RT -- because the only honest test of "the reflection is
--   visible" is whether you can tell the two apart.
--
-- And then the same pair at every camera rung, because the whole failure was
-- that it DID work at 75 degrees, which is the rung nobody plays at.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/DRAMATIC_SHAPE/tests/puddle_rtx_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/puddle_rtx_probe.log", "w"))
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
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
    wait(3)
  end

  -- ------- the shot that COUNTS, which is the whole of how a mask is tested
  --
  -- With RayFX.DEBUG_MASK on, every pixel the pass classifies as a puddle
  -- comes out flat magenta -- the classification itself, before anything is
  -- reflected with it. So "where did it land" stops being a thing to squint
  -- at and becomes a number.
  --
  -- Counted rather than only saved because the failure this row spent two
  -- releases on was INVISIBLE in a screenshot: a wrong classification at a
  -- tenth of a pixel looks like a correct one. And it cannot be tested by
  -- diffing an OFF shot against an ON shot -- those are two different frames
  -- of a rain animation, so every ripple and every falling drop lands in the
  -- diff. One frame, one question, one integer.
  --
  -- Every second pixel on both axes: a pool is dozens across and the stripes
  -- a leaning card used to pick up were several, so nothing this is looking
  -- for hides between the samples, and it keeps a full-frame count off the
  -- wrong side of a second.
  local counted = {}
  local function maskShot(name)
    counted[name] = nil
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      local w, h = data:getWidth(), data:getHeight()
      local hits, seen = 0, 0
      for y = 0, h - 1, 2 do
        for x = 0, w - 1, 2 do
          local r, g, b = data:getPixel(x, y)
          seen = seen + 1
          -- "strongly magenta" rather than exactly 1,0,1: the hour's tint is
          -- a multiply over the finished frame, so the paint arrives shaded
          if r > 0.55 and b > 0.55 and g < 0.40
             and r - g > 0.25 and b - g > 0.25 then
            hits = hits + 1
          end
        end
      end
      counted[name] = { hits = hits, seen = seen }
    end)
    wait(6)
    return counted[name] or { hits = -1, seen = 0 }
  end

  love.math.setRandomSeed(20260802)

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit()
      return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.DRAMATIC_SHAPE and exports.DRAMATIC_SHAPE.lib
  if not lib then
    log("FAIL: DRAMATIC_SHAPE not loaded"); logf:close(); love.event.quit()
    return
  end
  log("version:", exports.DRAMATIC_SHAPE.version)

  local RayFX = lib.require("RayFX")
  local GroundFX = lib.require("GroundFX")
  local Voxel3D = lib.require("Voxel3D")
  local Weather = lib.require("Weather")
  local Water = lib.require("Water")
  local DayNight = lib.require("DayNight")
  local Voxel = lib.require("VoxelState")
  local Pipelines = require("src.render.Pipelines")

  for _, rung in ipairs({ "ao", "rt", "max" }) do
    log(("compile %-3s -> %s%s"):format(rung, tostring(RayFX.compile(rung)),
        RayFX.shaderError and (" [" .. tostring(RayFX.shaderError) .. "]")
        or ""))
  end
  if RayFX.shaderError then log("  FAIL: a rung did not build") end

  -- ------- the number, before a single pixel is drawn
  --
  -- `f = mix(floor, 1, (1 - cos A)^3)` where A is the camera's tilt off
  -- vertical, times the amount. Worked here rather than read off a
  -- screenshot: this is the whole of what the fix changed, and it is
  -- arithmetic.
  log("")
  log("reflection share of the pixel, per camera rung:")
  log("  rung    pond (0.10/0.80)    pool (PUDDLE_FRESNEL/PUDDLE_AMOUNT)")
  for _, deg in ipairs({ 15, 35, 50, 75 }) do
    local c = math.cos(math.rad(deg))
    local k = (1 - c) ^ 3
    local pond = (0.10 + (1 - 0.10) * k) * RayFX.SSR_AMOUNT
    local pool = (RayFX.PUDDLE_FRESNEL + (1 - RayFX.PUDDLE_FRESNEL) * k)
                 * RayFX.PUDDLE_AMOUNT
    log(("  %2d deg  %.3f               %.3f"):format(deg, pond, pool))
    if pool < 0.25 then
      log("    FAIL: a puddle at this rung is under a quarter of the pixel "
          .. "-- that is the bug this probe is for")
    end
  end

  -- ------- and the surface: it must MOVE while it rains and be STILL after
  log("")
  -- The mark, written down in the file that stamps it and again in the file
  -- that reads it. A disagreement here is not a degraded reflection, it is
  -- no reflection at all and no error either.
  log(("PUDDLE_TAG: stamped %.6f  read %.6f +/- %.4f")
      :format(Voxel3D.PUDDLE_TAG, RayFX.PUDDLE_TAG, RayFX.PUDDLE_TAG_W))
  if math.abs(Voxel3D.PUDDLE_TAG - RayFX.PUDDLE_TAG) > 1e-6 then
    log("  FAIL: the two files disagree -- the mask can never match")
  end
  -- and the window has to stay INSIDE the gap to the next byte, or every
  -- opaque pixel in the frame is standing water
  if RayFX.PUDDLE_TAG_W >= (1 - RayFX.PUDDLE_TAG) then
    log("  FAIL: the window reaches 1.0 -- the whole world would classify "
        .. "as a puddle")
  end

  GroundFX.setting:sync("on")
  DayNight.setting:sync("day")
  RayFX.setting:sync("rt")
  Pipelines.setLevel("voxel", 5)
  GroundFX.SOAK = 3                    -- soak in seconds rather than a minute

  -- A town, because a town is where the paving is RAISED -- the case the
  -- absolute-height test used to miss, and the case a wet street is worth
  -- looking at in.
  Weather.setting:sync("off")
  game.overworld:setMap("VIRIDIAN_CITY", 4, 16, "down")
  wait(240)

  -- ------- FIRST QUESTION: what does the pass call a puddle when there are
  -- none?
  --
  -- This is the half of the mask that matters and the half a wet screenshot
  -- cannot show. On a DRY street the ground row draws nothing and stamps
  -- nothing, so the alpha channel is uniform and the correct number of
  -- classified pixels is ZERO -- while the player, every NPC, every hedge
  -- and every fence rim are still standing there being exactly the things
  -- that used to classify as standing water.
  --
  -- So any magenta at all in these shots is a false positive, named and
  -- counted, with nothing in the frame it could legitimately be. Every gate
  -- this row has tried would have failed here: the fraction test painted the
  -- player in stripes on a dry street just as happily as on a wet one.
  --
  -- Two rungs rather than one, because both failed gates were rung-dependent
  -- -- the fraction stopped matching pools at 35 and 75 degrees, and the
  -- strict normal only ever passed near top-down.
  RayFX.DEBUG_MASK = true
  log("")
  log(("DRY street (wet=%.2f draws=%d stamps=%d) -- the mask must find "
       .. "NOTHING"):format(GroundFX.wetness(), GroundFX.lastDraws,
                            GroundFX.lastStamps))
  for _, rung in ipairs({ { 3, "35deg" }, { 5, "75deg" } }) do
    Pipelines.setLevel("voxel", rung[1]); wait(90)
    local c = maskShot(("40_dry_mask_%s.png"):format(rung[2]))
    log(("  dry %s: %d classified of %d sampled"):format(rung[2], c.hits,
                                                         c.seen))
    if c.hits < 0 then
      log("    FAIL: the shot never came back -- nothing was counted")
    elseif c.hits > 0 then
      log("    FAIL: pixels classified as standing water on a dry street. "
          .. "Open the shot: whatever is magenta is what the mask is "
          .. "leaking onto")
    end
  end

  Weather.setting:sync("rain")
  wait(600)

  local map = game.overworld.map
  local p = game.overworld.player
  local cells = GroundFX.puddleCells(map, p.cellX - 8, p.cellY - 8, 17)
  log("")
  log(("wet=%.2f  pools in the 17x17 around the player: %d  draws=%d")
      :format(GroundFX.wetness(), #cells, GroundFX.lastDraws))
  if #cells == 0 then
    log("  FAIL: no pools here -- the reflection has nothing to appear in, "
        .. "and every shot below is of dry ground")
  end
  for i, c in ipairs(cells) do
    if i <= 6 then log(("  pool at %d,%d"):format(c[1], c[2])) end
  end

  log(("Water.rain()=%.2f -- 0 means the ripple is off and the pool is a "
       .. "still mirror"):format(Water.rain()))
  if Water.rain() <= 0 then
    log("  FAIL: it is raining and the surface is not being told")
  end

  -- ------- SECOND QUESTION: and now that there ARE puddles, does it find
  -- them -- at every rung
  --
  -- The other half, and the one the old identifier failed quietly: the
  -- fraction test stopped matching real pools at 35 and 75 degrees, so the
  -- feature had never worked at the angles a player actually stands at and
  -- the shots that would have shown it were of pools reflecting nothing.
  --
  -- The count is not compared to an expected area -- a pool's pixel count
  -- depends on where the camera is standing. What is asserted is the thing
  -- that has actually been wrong: NOT ZERO, at every rung, and the shots are
  -- there to be looked at for whether the magenta is puddle-shaped.
  log("")
  log(("WET street (wet=%.2f draws=%d stamps=%d) -- the mask must find the "
       .. "pools at EVERY rung"):format(GroundFX.wetness(),
                                        GroundFX.lastDraws,
                                        GroundFX.lastStamps))
  if GroundFX.lastStamps == 0 then
    log("  FAIL: the ground row drew puddles and stamped none of them -- "
        .. "either the colour mask was refused or no depth buffer was "
        .. "bound (see Voxel3D.beginAlphaStamp)")
  end
  for _, rung in ipairs({ { 2, "15deg" }, { 3, "35deg" },
                          { 4, "50deg" }, { 5, "75deg" } }) do
    Pipelines.setLevel("voxel", rung[1]); wait(90)
    local c = maskShot(("41_wet_mask_%s.png"):format(rung[2]))
    log(("  wet %s: %d classified of %d sampled"):format(rung[2], c.hits,
                                                         c.seen))
    if c.hits <= 0 then
      log("    FAIL: it is raining, there are pools in front of the camera, "
          .. "and the pass classifies none of them at this rung")
    end
  end
  RayFX.DEBUG_MASK = false

  -- ------- the pairs
  --
  -- Every rung, OFF against RT. Two shots of the same frame that look the
  -- same are the bug; two that differ are the feature.
  local function pair(level, tag)
    -- through Pipelines, like every other probe here: it is the route the
    -- OPTIONS row itself takes, so a rung set this way is the rung a player
    -- would have. The wait is for the tween -- a shot taken mid-swing is a
    -- shot at an angle that is on no rung at all.
    Pipelines.setLevel("voxel", level)
    wait(90)
    RayFX.setting:sync("off"); wait(20); shot(tag .. "_a_rtOFF.png")
    RayFX.setting:sync("rt");  wait(20); shot(tag .. "_b_rtON.png")
    log(("shot %s  (angle %.0f deg, wet %.2f, rain %.2f)"):format(
      tag, math.deg(Voxel.angle or 0), GroundFX.wetness(), Water.rain()))
  end

  pair(2, "50_pool_15deg")
  pair(3, "51_pool_35deg")
  pair(4, "52_pool_50deg")
  pair(5, "53_pool_75deg")

  -- ------- and the aftermath: rain off, pools still there, surface STILL
  --
  -- The other half of the ripple's contract. A pool ten minutes after the
  -- shower is a mirror, and a mirror is the shot the long dry-out exists to
  -- give -- so a ripple that kept going after the rain stopped would be as
  -- wrong as one that never started.
  Weather.setting:sync("off")
  wait(400)
  Pipelines.setLevel("voxel", 4); wait(90)
  log("")
  log(("aftermath: wet=%.2f rain=%.2f -- rain must be 0.00 and wet must not")
      :format(GroundFX.wetness(), Water.rain()))
  if Water.rain() > 0.01 then
    log("  FAIL: the shower is over and the surface is still being rippled")
  end
  if GroundFX.wetness() < 0.3 then
    log("  FAIL: the pools have already gone -- there is no aftermath to "
        .. "photograph")
  end
  shot("54_aftermath_still_mirror.png")

  log("")
  log("done -- " .. OUT)
  logf:close()
  love.event.quit()
end
