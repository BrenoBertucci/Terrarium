-- Probe: the SM64 camera (lib/MarioCam.lua) in the real renderer.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/mariocam_probe.lua gen1recomp
--
-- WHAT IS MEASURED, and why each of these and not "the screenshot looks
-- like Mario 64".
--
--   PARITY  VoxelScene.bounds at yaw zero must equal, to the pixel, the
--           four expressions it used before this feature existed. That box
--           is what culls terrain, and a change that quietly moved it with
--           the camera OFF would be a regression in the mode everybody is
--           already playing. Checked against the arithmetic written out
--           longhand here rather than against the function itself, so the
--           check cannot agree with a bug by sharing it.
--
--   SWING   the radial mode's whole claim is that the camera orbits the
--           MAP rather than the player. So: stand west of the map centre,
--           stand east of it, and the view yaw has to have swung. If it
--           has not, the mode is an expensive way to draw the old camera.
--
--   HOLE    THE RISK THIS FILE EXISTS FOR. The culling box was built
--           around a camera that always looked north; a yawed camera that
--           kept the old box would cull the ground it is actually pointed
--           at, and the failure is a hole in the world.
--
--           COUNTED, NOT PHOTOGRAPHED. Two earlier versions of this check
--           tried to see the hole in a screenshot and both measured
--           something else. The first looked for sky-coloured pixels in
--           the near field and was reading Pallet Town's SEA -- the beach
--           is blue, the test was "blue-dominant", and the number swung
--           between 3% and 34% purely with how much water the camera
--           happened to face. The second photographed the frame twice,
--           once with the real box and once with the box forced enormous,
--           and diffed them -- but the two shots are frames apart, and in
--           between them the shadow map lands on a different resolution
--           rung, NPCs walk, the grass sways and the follower moves. It
--           reported five percent of the NEAR FIELD lost on the untouched
--           orbit camera, which cannot be true and was the giveaway.
--
--           So the box is asked directly instead, on ONE frame, with no
--           pixels involved. For every terrain chunk the mesher built:
--           does it PROJECT INTO THE VIEWPORT, and does the box KEEP it?
--           A chunk that lands on screen and is not kept is a hole, and
--           the count of those is the measurement. Deterministic, immune
--           to anything that moves, and it names the offending chunk.
--   CARD    a character is a flat card, and for the life of this mod it
--           faced due south and only leaned -- correct for a camera that
--           cannot turn, and catastrophic for one that can: seen edge-on,
--           a person reads as LYING ON THE FLOOR. Measured as the card's
--           own width ON SCREEN, by projecting the corners of the real
--           matrix: edge-on collapses that width toward zero, and it has
--           to survive every yaw the player can reach. The canary is the
--           OLD matrix, written longhand, which must collapse.
--
--   CHASE   the 0.8 / 0.3 asymmetry, in the running game rather than in a
--           unit test: after a tenth of a second of a step, the focus must
--           have closed far more of its gap than the eye has of its own.
--           That asymmetry is the port's central claim.
--
--   Screenshots for every case, because a camera is a thing you look at.

return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = io.open(OUT .. "/mariocam_probe.log", "w")
  if not logf then
    OUT = "."
    logf = assert(io.open(OUT .. "/mariocam_probe.log", "w"))
  end
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  log("driver start")
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
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

  local MarioCam = lib.require("MarioCam")
  local VoxelScene = lib.require("VoxelScene")
  local ShadowMap = lib.require("ShadowMap")
  local Voxel3D = lib.require("Voxel3D")
  local Voxel = lib.require("VoxelState")
  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local MiniMap = lib.require("MiniMap")
  local AutoFarm = lib.require("AutoFarm")
  local Pipelines = require("src.render.Pipelines")

  -- 50 degrees: a real perspective with plenty of near ground in frame,
  -- which is what the VOID band needs. 75 is mostly sky and would leave
  -- the band measuring the horizon instead of the hole.
  Pipelines.setLevel("terrarium_voxel", 4)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  MiniMap.setting:setIndex(3, game)          -- nothing in the corner
  Weather.setting:setIndex(2, game)          -- nothing falling through it
  -- The save opens with A-FARM armed and a bot pushing directions into the
  -- press queue would walk the player between the halves of every pair.
  AutoFarm.setting:setIndex(1, game)

  local CLOCK = 300                           -- noon, pinned every frame
  local function hold(frames)
    for _ = 1, frames do DayNight.clock = CLOCK; coroutine.yield() end
    DayNight.clock = CLOCK
  end

  -- ------- LET GO OF THE STICK
  --
  -- A synthetic pressQueue inject is a press with NO SOURCE, and
  -- Input:step's rule for those is to set state[btn] = true and leave it
  -- there: nothing releases what nothing owns. So a walk burst leaves the
  -- direction held FOREVER, and the player keeps walking on every frame of
  -- every settle after it until they are jammed against a wall.
  --
  -- That cost three checks in one run -- two walks that reported "did not
  -- move (blocked)" and a chase that measured a lag of zero -- all of them
  -- describing a player who had walked into a building four sections ago
  -- and stayed there. Every burst below ends with this.
  local function releaseDirs()
    local st = game.input.state
    for _, d in ipairs({ "up", "down", "left", "right" }) do
      st[d] = false
      if game.input.sources then game.input.sources[d] = nil end
    end
    game.input.pressQueue = {}
  end

  -- One walk burst: hold `dir` for `frames`, then let go.
  local function walk(dir, frames)
    for _ = 1, frames do
      game.input.pressQueue[#game.input.pressQueue + 1] = dir
      DayNight.clock = CLOCK
      coroutine.yield()
    end
    releaseDirs()
    hold(15)
  end

  -- CELADON_CITY: 50 by 36 cells, the biggest town in Kanto, outdoors, and
  -- built around its middle -- which is the shape the radial mode's area
  -- centre assumes.
  --
  -- SIZE IS NOT A DETAIL HERE, it is what makes the culling checks mean
  -- anything. The first run of this file used PALLET_TOWN, got zero holes
  -- everywhere, and the canary at the bottom then showed why: Pallet is 20
  -- by 18 cells and the culling box is larger than the whole map, so
  -- NOTHING is ever culled at any yaw and every pass was vacuous. A test
  -- that cannot fail is not evidence, and the only reason that was caught
  -- is that the canary exists.
  local MAP = "CELADON_CITY"
  local function goTo(cx, cy, face)
    game.overworld:setMap(MAP, cx, cy, face or "down")
    hold(300)
  end

  local fails, notes = {}, {}
  local function check(ok, msg)
    if not ok then fails[#fails + 1] = msg end
    log((ok and "  ok   " or "  FAIL ") .. msg)
  end

  -- ------- the shot
  --
  -- `save` writes the png; the ImageData is kept either way so two frames
  -- can be diffed pixel for pixel.
  local function measure(name, save)
    local pending, rec = true, nil
    love.graphics.captureScreenshot(function(data)
      local W, H = data:getDimensions()
      rec = { name = name, W = W, H = H, data = data }
      if save ~= false then
        local f = io.open(OUT .. "/" .. name .. ".png", "wb")
        if f then f:write(data:encode("png"):getString()) f:close() end
      end
      pending = false
    end)
    -- WAIT FOR THE CALLBACK, not for N frames: a screenshot scheduled and
    -- then counted out in yields photographs whatever the next state is,
    -- which silently attributes one case's picture to another.
    local guard = 0
    while pending and guard < 300 do hold(1); guard = guard + 1 end
    if not rec then log("  (no shot for " .. name .. ")") end
    return rec
  end

  -- ------- the hole counter
  --
  -- A chunk is a box of world: x0..x1 by 0..ymax by z0..z1 (ChunkMesher's
  -- buckets). It is ON SCREEN if any of its eight corners projects inside
  -- the viewport with positive w, and it is KEPT if it meets the culling
  -- box -- the same test Voxel3D.drawGroup applies, restated here so the
  -- check does not agree with a bug by sharing the code that has it.
  local ChunkMesher = lib.require("ChunkMesher")

  local function onScreen(ch, W, H)
    local xs = { ch.x0, ch.x1 }
    local zs = { ch.z0, ch.z1 }
    local ys = { 0, ch.ymax or 0 }
    for _, x in ipairs(xs) do
      for _, y in ipairs(ys) do
        for _, z in ipairs(zs) do
          local px, py = Voxel3D.project(x, y, z)
          if px and px >= 0 and px <= W and py >= 0 and py <= H then
            return true
          end
        end
      end
    end
    return false
  end

  local function kept(ch, b)
    -- Voxel3D.drawGroup's own test, including the ymax reach on the north
    -- edge: a chunk whose GROUND is past the box still draws if something
    -- tall stands on it
    return ch.x1 >= b[1] and ch.x0 <= b[3]
           and ch.z1 + (ch.ymax or 0) >= b[2] and ch.z0 <= b[4]
  end

  -- ------- WHAT COUNTS AS A HOLE, and why "on screen and dropped" is not
  -- the definition
  --
  -- A chunk two thousand pixels away still PROJECTS into the viewport --
  -- it lands on the horizon row. Dropping it is not a bug, it is FAR_CAP,
  -- a trade this mod made long before this feature and made deliberately;
  -- counting those makes every camera look broken including the untouched
  -- orbit. The first version of this counter did exactly that and reported
  -- eleven holes on a working frame.
  --
  -- The invariant that actually belongs to this change is narrower and
  -- direction-free: WITHIN THE REACH THE BOX ITSELF CLAIMS, everything the
  -- camera can see must be kept, whichever way the camera is pointed. The
  -- yardstick is the ORBIT's reach -- the number the mod's far field was
  -- tuned against -- so the yawed camera is held to the same standard as
  -- the one it replaces rather than to one of its own.
  local function nearestTo(ch, x, z)
    local dx = math.max(ch.x0 - x, 0, x - ch.x1)
    local dz = math.max(ch.z0 - z, 0, z - ch.z1)
    return math.sqrt(dx * dx + dz * dz)
  end

  -- Everything that moves, stilled -- not for the counter, which does not
  -- care, but so the screenshots beside it are comparable frame to frame.
  local function holeTest(name)
    local shot = measure(name, true)
    local W = shot and shot.W or 1920
    local H = shot and shot.H or 1080
    local state = game.overworld
    local terrain = VoxelScene.prefetch and select(1, VoxelScene.prefetch(state))
    if not (terrain and terrain.chunks) then
      log("  (no terrain group for " .. name .. ")")
      return shot, 0, 0
    end
    -- THE BOX THIS FRAME, from the four numbers the renderer actually
    -- fitted it to (VoxelScene.lastView). Reconstructing them out here --
    -- guessing the view size, guessing whether the centre is the scroll or
    -- the camera focus -- would be asking about a box the frame never used.
    local lv = VoxelScene.lastView
    local b = VoxelScene.bounds(lv[1], lv[2], lv[3], lv[4], false)

    local reach = ShadowMap.groundReach(lv[4], VoxelScene.FAR_CAP)
    local seen, near, holes, total = 0, 0, 0, 0
    local worst = nil
    for _, ch in ipairs(terrain.chunks) do
      total = total + 1
      if onScreen(ch, W, H) then
        seen = seen + 1
        if nearestTo(ch, lv[1], lv[2]) <= reach then
          near = near + 1
          if not kept(ch, b) then
            holes = holes + 1
            worst = ("chunk x[%.0f..%.0f] z[%.0f..%.0f] is %.0f px away "
                     .. "(reach %.0f) but the box is [%.0f %.0f %.0f %.0f]")
                    :format(ch.x0, ch.x1, ch.z0, ch.z1,
                            nearestTo(ch, lv[1], lv[2]), reach,
                            b[1], b[2], b[3], b[4])
          end
        end
      end
    end
    log(("HOLE %-18s yaw %7.2f  %d built / %d on screen / %d within reach "
         .. "%.0f / %d CULLED")
        :format(name, math.deg(MarioCam.viewYaw()), total, seen, near,
                reach, holes))
    if worst then log("       e.g. " .. worst) end
    check(holes == 0,
          ("%s: %d chunks inside the box's own reach are on screen and culled")
          :format(name, holes))
    return shot, holes, near
  end

  -- ------- 1. PARITY: the box at yaw zero is the box we always had
  --
  -- Written out longhand from the four expressions bounds() used before
  -- this change, so the check has its own copy of the answer.
  local function oldBounds(cx, cy, vw, vh, forSun)
    local reach = ShadowMap.groundReach(vh, VoxelScene.FAR_CAP)
    local spread = reach * 0.5 + 64
    local sun = 0
    if forSun then
      sun = ShadowMap.HEIGHT
            * math.max(math.abs(ShadowMap.KX), math.abs(ShadowMap.KZ)) + 24
    end
    return { cx - vw / 2 - spread, cy - reach,
             cx + vw / 2 + spread + sun, cy + vh / 2 + 64 + sun }
  end
  local function boxEq(a, b, tol)
    for i = 1, 4 do
      if math.abs(a[i] - b[i]) > (tol or 0.001) then return false end
    end
    return true
  end
  local function boxStr(b)
    return ("[%.0f %.0f %.0f %.0f]"):format(b[1], b[2], b[3], b[4])
  end

  goTo(5, 6, "up")
  MarioCam.setting:setIndex(1, game)          -- OFF
  hold(60)
  for _, sun in ipairs({ false, true }) do
    local got = VoxelScene.bounds(400, 300, 160, 144, sun)
    local want = oldBounds(400, 300, 160, 144, sun)
    log("PARITY off sun=" .. tostring(sun), boxStr(got), "want", boxStr(want))
    check(boxEq(got, want), "bounds at yaw 0 (cam OFF, sun=" .. tostring(sun)
          .. ") matches the pre-feature box")
  end

  -- ------- AND NOT "the ON box covers the old box"
  --
  -- That check lived here while the ladder had a rung with the yaw pinned,
  -- and it made sense there: at yaw zero the two boxes describe the same
  -- camera, so the new one had better not be smaller. With the row simply
  -- ON the camera has a real yaw, and a box fitted to a camera looking
  -- EAST has no business reaching far north -- that would be covering
  -- ground nobody can see. Demanding coverage of the old box would be
  -- demanding the bug back.
  --
  -- The invariant that survives the yaw is the one the hole counter below
  -- tests: within the reach the box claims, everything on screen is kept,
  -- whichever way the camera points. The exact-parity check above still
  -- guards the case that must not move -- the row OFF.
  MarioCam.setting:setIndex(2, game)          -- ON
  hold(240)
  log("PARITY on", boxStr(VoxelScene.bounds(400, 300, 160, 144, false)),
      "old", boxStr(oldBounds(400, 300, 160, 144, false)))

  local shotOff, shotOn, shotW, shotE
  MarioCam.setting:setIndex(1, game); hold(120)
  shotOff = holeTest("cam_off")
  MarioCam.setting:setIndex(2, game); hold(240)
  shotOn = holeTest("cam_on")

  -- ------- 2. SWING: the radial orbits the map, not the player
  MarioCam.setting:setIndex(2, game)          -- ON
  local map = game.overworld.map
  local wCells = map and map.widthCells or 20
  local hCells = map and map.heightCells or 18
  log("map", MAP, "cells", wCells, "x", hCells)

  local westX = math.max(1, math.floor(wCells * 0.15))
  local eastX = math.min(wCells - 2, math.floor(wCells * 0.85))
  local midY = math.floor(hCells / 2)

  -- WHERE THE PLAYER ACTUALLY IS, not where they were put. setMap drops
  -- them on a cell and the game may then walk them off it -- a warp tile, a
  -- script, a ledge -- and a run where that happened reported a swing of
  -- 3 degrees between "west" and "east" because both readings were taken
  -- from the same side of the map. The yaw is a function of the position,
  -- so the position is what has to be reported beside it.
  local function spot(cx, cy, tag)
    goTo(cx, cy, "up")
    hold(240)
    local p = game.overworld.player
    local px = (p.px or 0) + 8
    log(("  %s: asked for cell (%d,%d), player is at (%.0f,%.0f) = cell "
         .. "(%d,%d), area centre x is %.0f")
        :format(tag, cx, cy, px, (p.py or 0) + 8,
                math.floor(px / 16), math.floor(((p.py or 0) + 8) / 16),
                MarioCam.cam.areaCenX))
    return px
  end

  local pxW = spot(westX, midY, "west")
  local yawW = math.deg(MarioCam.viewYaw())
  shotW = holeTest("cam_radial_west")
  local pxE = spot(eastX, midY, "east")
  local yawE = math.deg(MarioCam.viewYaw())
  shotE = holeTest("cam_radial_east")
  check(pxW < MarioCam.cam.areaCenX and pxE > MarioCam.cam.areaCenX,
        ("the two spots really are on opposite sides of the area centre "
         .. "(%.0f and %.0f, centre %.0f)")
        :format(pxW, pxE, MarioCam.cam.areaCenX))
  log(("SWING west=%.1fdeg east=%.1fdeg delta=%.1f"):format(yawW, yawE,
                                                            math.abs(yawW - yawE)))
  check(math.abs(yawW - yawE) > 20,
        "the radial yaw swings across the map (got "
        .. ("%.1f"):format(math.abs(yawW - yawE)) .. " deg)")

  -- ------- 3. HOLE: no culling hole at any yaw the player can reach
  --
  -- Driven by the turn keys rather than by position, so the sweep covers
  -- deflections the map centre never asks for -- which is exactly where a
  -- north-shaped culling box would fail and a position-only test would
  -- never look.
  for i = 1, 6 do
    game:keypressed(i <= 2 and "q" or "e")
    hold(90)
    log(("TURN %d yaw=%.1f deg"):format(i, math.deg(MarioCam.viewYaw())))
    holeTest("cam_turn_" .. i)
  end

  -- ------- 3c. CARD: the characters stand up at every yaw
  --
  -- WHAT IS MEASURED IS THE CARD'S NORMAL, not its width on screen.
  --
  -- Width was the first attempt and it is the wrong quantity twice over.
  -- The card's local X axis is a world-X segment under the old matrix, and
  -- a world-X segment only foreshortens when the camera happens to look
  -- along world X -- so the reading depends entirely on whether the sample
  -- yaws land near +/-90, which with 60-degree C steps from an arbitrary
  -- start they mostly do not. The old matrix duly came back at 71% and
  -- looked almost fine, on a frame where the character was flat on the
  -- floor.
  --
  -- The defect is not the width. It is that the card FACES THE WRONG WAY.
  -- So: take the card's own normal (its local +Z through the matrix's
  -- rotation), take the direction from the card to the eye, and measure
  -- the angle between them. A billboard that works answers ~0 at every
  -- yaw. The matrix this replaced answers the camera's yaw itself, which
  -- is what "seen edge-on" means as a number, and at 90 degrees it is a
  -- person seen as a vertical line.
  do
    local Mat4 = lib.require("Mat4")
    local function dir(m, x, y, z)      -- a DIRECTION: rotation only
      return m[1] * x + m[2] * y + m[3] * z,
             m[5] * x + m[6] * y + m[7] * z,
             m[9] * x + m[10] * y + m[11] * z
    end
    local function facingError(m, px, py)
      local nx, ny, nz = dir(m, 0, 0, 1)          -- the card's normal
      local eye = Voxel3D.eye
      if not eye then return nil end
      local ex, ey, ez = eye[1] - (px + 8), eye[2] - 8, eye[3] - (py + 8)
      local ln = math.sqrt(nx * nx + ny * ny + nz * nz)
      local le = math.sqrt(ex * ex + ey * ey + ez * ez)
      if ln < 1e-6 or le < 1e-6 then return nil end
      local d = (nx * ex + ny * ey + nz * ez) / (ln * le)
      d = math.max(-1, math.min(1, d))
      return math.deg(math.acos(d))
    end

    MarioCam.setting:setIndex(2, game)          -- ON
    goTo(25, 30, "down")
    MarioCam.recenter()
    hold(240)

    local p = game.overworld.player
    local worstNew, worstNewYaw = 0, 0
    local worstOld = 0
    for i = 0, 7 do
      if i > 0 then game:keypressed("e") end
      hold(120)
      local yaw = math.deg(MarioCam.viewYaw())
      local m = VoxelScene._billboardMatrix(p.px, p.py, 0, false)
      -- the matrix this replaced, longhand: translate, lean, anchor. No turn.
      local old = Mat4.mul(
        Mat4.mul(Mat4.translate(p.px + 8, 0, p.py + 8),
                 Mat4.rotateX(Voxel.angle - math.pi / 2)),
        Mat4.translate(-8, 0, 0))
      local eNew = facingError(m, p.px, p.py)
      local eOld = facingError(old, p.px, p.py)
      if eNew and eOld then
        -- the card no longer faces the eye DEAD-ON between cardinals: it
        -- under-rotates by the presentation yaw (MarioCam.presentYaw, the
        -- best-side turn). So the honest expectation is THAT angle, and
        -- the measurement is the deviation from it -- which also keeps
        -- this check able to fail: a card that ignored presentYaw would
        -- deviate by up to 18 degrees at the diagonals.
        local expected = math.abs(math.deg(MarioCam.presentYaw()))
        local dev = math.abs(eNew - expected)
        if dev > worstNew then worstNew, worstNewYaw = dev, yaw end
        if eOld > worstOld then worstOld = eOld end
        log(("CARD yaw %7.2f  card-vs-eye: NEW %5.1f deg (present %4.1f)"
             .. "   OLD %5.1f deg"):format(yaw, eNew, expected, eOld))
      end
    end
    check(worstNew < 8,
          ("the card sits on its presentation angle at every yaw (worst "
           .. "%.1f deg off at %.1f)"):format(worstNew, worstNewYaw))
    -- and the check can fail: the matrix this replaced does not
    check(worstOld > 45,
          ("the OLD card matrix DOES point the wrong way (up to %.1f deg "
           .. "off), so the check above is not vacuous"):format(worstOld))
    measure("cam_cards_free", true)
    MarioCam.setting:setIndex(2, game)
  end

  -- ------- 3d. INPUT: movement is camera-relative, as in SM64
  --
  -- The claim is one sentence -- push away from yourself and the character
  -- walks away from the camera, whatever the camera is doing -- and it is
  -- measured as exactly that sentence: press physical UP, take the world
  -- displacement that results, and PROJECT IT ONTO THE CAMERA'S FORWARD.
  -- A positive, dominant projection is the claim holding. A negative one
  -- is the player walking toward the camera when they asked to walk away,
  -- which is the failure this exists to catch.
  --
  -- CELADON (24,30) is used because it is open in all four world
  -- directions, which matters here and nowhere else in this file: under a
  -- quarter turn, physical UP becomes a DIFFERENT world direction at every
  -- camera angle, so a cell with a wall on any side would report "did not
  -- move" for one of the yaws and look like a failure of the remap.
  -- Found by walking all four ways out of a dozen candidates.
  do
    MarioCam.setting:setIndex(2, game)          -- ON
    local OPEN = { 24, 30 }
    local p = game.overworld.player
    local tested, worst, worstYaw = 0, 1e9, 0
    -- who is moving the player during a settle? Log the whole input state
    -- beside the position, every half second, so a held source shows up
    -- with its owner's name on it.
    local function settleTrail(tag, frames)
      local pp = game.overworld.player
      local st = game.input.state
      local so = game.input.sources or {}
      for f = 1, frames do
        DayNight.clock = CLOCK
        coroutine.yield()
        if f % 30 == 0 then
          local held = {}
          for _, d in ipairs({ "up", "down", "left", "right" }) do
            if st[d] then held[#held + 1] = d .. "(" .. tostring(so[d]) .. ")" end
          end
          log(("    %s f%03d px=%.0f py=%.0f phase=%s held=%s q=%s")
              :format(tag, f, pp.px, pp.py, tostring(pp.phase),
                      #held > 0 and table.concat(held, ",") or "-",
                      tostring(#game.input.pressQueue)))
        end
      end
    end
    -- goTo with a RECEIPT: the phantom input on this machine can walk the
    -- player ten cells off during the settle inside goTo itself (caught on
    -- camera: asked (24,30), landed (34,31), check judged the wrong scene)
    local function park()
      for _ = 1, 4 do
        goTo(OPEN[1], OPEN[2], "down")
        local pp = game.overworld.player
        if math.floor((pp.px + 8) / 16) == OPEN[1]
           and math.floor((pp.py + 8) / 16) == OPEN[2] then
          return true
        end
      end
      return false
    end
    for i = 0, 5 do
      park()
      log(("  goTo done: player at (%.0f,%.0f) = cell (%d,%d)")
          :format(game.overworld.player.px, game.overworld.player.py,
                  math.floor((game.overworld.player.px + 8) / 16),
                  math.floor((game.overworld.player.py + 8) / 16)))
      MarioCam.recenter()
      if i == 0 then settleTrail("SETTLE", 60) else hold(60) end
      for _ = 1, i do game:keypressed("e") end
      if i == 0 then settleTrail("SET2", 150) else hold(150) end
      local yaw = MarioCam.viewYaw()
      -- diagnostics: every s16 the yaw is assembled from, so a stray
      -- degree can be blamed on its owner rather than on the total
      local function sdeg(a)
        a = a % 65536; if a >= 32768 then a = a - 65536 end
        return a * 360 / 65536
      end
      log(("  state: mode=%s offY=%.1f goalY=%.1f avoid=%.1f auto=%s alt=%s")
          :format(MarioCam.cam.mode, sdeg(MarioCam.ctl.offsetYaw),
                  sdeg(MarioCam.ctl.goalOffsetYaw),
                  sdeg(MarioCam.avoidState and MarioCam.avoidState.offset or 0),
                  MarioCam.cam.autoYaw and ("%.1f"):format(sdeg(MarioCam.cam.autoYaw))
                    or "nil",
                  tostring(MarioCam.ctl.alt)))
      -- the direction the camera looks, which is the direction "away from
      -- the player, up the screen" -- see MarioCam.viewYaw
      local fx, fz = math.sin(yaw), -math.cos(yaw)
      local x0, z0 = p.px, p.py
      if i == 0 then
        -- the failing case, walked by hand with a per-frame trail
        for f = 1, 40 do
          game.input.pressQueue[#game.input.pressQueue + 1] = "up"
          DayNight.clock = CLOCK
          coroutine.yield()
          if f % 5 == 0 then
            log(("    f%02d px=%.0f py=%.0f yaw=%.1f quad=%d")
                :format(f, p.px, p.py, math.deg(MarioCam.viewYaw()),
                        MarioCam.quadrant()))
          end
        end
        releaseDirs()
        hold(15)
      else
        walk("up", 40)
      end
      local dx, dz = p.px - x0, p.py - z0
      local moved = math.sqrt(dx * dx + dz * dz)
      if moved > 8 then
        tested = tested + 1
        -- how much of the walk went "away from the camera", as a fraction
        local along = (dx * fx + dz * fz) / moved
        if along < worst then worst, worstYaw = along, math.deg(yaw) end
        log(("INPUT yaw %7.2f  quadrant %d  pressed UP -> moved (%+.0f,%+.0f) "
             .. "= %.0f%% along the camera's forward")
            :format(math.deg(yaw), MarioCam.quadrant(), dx, dz, along * 100))
      else
        log(("INPUT yaw %7.2f  pressed UP -> did not move (blocked)")
            :format(math.deg(yaw)))
      end
    end
    check(tested >= 4,
          ("enough yaws actually moved to judge (%d of 6)"):format(tested))
    check(tested >= 4 and worst > 0.8,
          ("UP always walks AWAY from the camera (worst %.0f%% at %.1f deg)")
          :format(worst * 100, worstYaw))

    -- ------- and the canary: with the row OFF, nothing is rotated
    --
    -- The remap is the one gameplay change in this mod, so the state that
    -- promises not to make it has to be shown keeping that promise -- and
    -- with the ladder down to ON/OFF, that state is OFF. A player who
    -- turns this row off gets the 1996 controls back, exactly.
    MarioCam.setting:setIndex(1, game)          -- OFF
    goTo(OPEN[1], OPEN[2], "down")
    hold(120)
    check(MarioCam.rotatesInput() == false, "OFF does not rotate the controls")
    check(MarioCam.buttonFor("up") == "up" and MarioCam.buttonFor("left") == "left",
          "and every button with the row OFF still means what it says")
    -- up to three tries: a wandering NPC parking one cell north blocks the
    -- walk and reports 7px of truth as a failure -- the DIRECTION is the
    -- claim here, and a blocked walk has no direction to judge
    local dx0, dz0 = 0, 0
    for attempt = 1, 3 do
      local x0, z0 = p.px, p.py
      walk("up", 40)
      dx0, dz0 = p.px - x0, p.py - z0
      log(("INPUT off (try %d): pressed UP -> moved (%+.0f,%+.0f); north is -z")
          :format(attempt, dx0, dz0))
      if dz0 < -8 then break end
      goTo(OPEN[1], OPEN[2], "down")
    end
    check(dz0 < -8 and math.abs(dx0) < 8,
          "with the row OFF, UP still walks due north as it always did")
    MarioCam.setting:setIndex(2, game)
  end

  -- ------- 3e. MOONWALK: the drawing agrees with the direction of travel
  --
  -- With the controls camera-relative, pressing UP walks the character
  -- away from the camera at every yaw -- so the drawing shown has to be
  -- the BACK one at every yaw, because that is what walking away looks
  -- like. If the compass facing were still choosing the frame, the same
  -- press would show the back at one camera angle and the FRONT at the
  -- opposite one, which is a character advancing while facing the other
  -- way: the moonwalk.
  do
    local SR = require("src.render.SpriteRenderer")
    MarioCam.setting:setIndex(2, game)
    local p = game.overworld.player
    local worstOK, sawDivergence, judged = true, false, 0
    for i = 0, 5 do
      goTo(24, 30, "down")
      MarioCam.recenter()
      hold(60)
      for _ = 1, i do game:keypressed("e") end
      -- SETTLE COMPLETELY, then check the camera held still THROUGH the
      -- walk. The quadrant is what maps the button to a world direction,
      -- and a camera still easing across a quadrant boundary maps the
      -- press one way and is read the other -- which showed up once as a
      -- character who walked north and was asked about as though they had
      -- walked east. That is the measurement drifting, not the feature.
      hold(300)
      local q0 = MarioCam.quadrant()
      walk("up", 30)
      local q1 = MarioCam.quadrant()
      local compass = p.facing
      local rel = MarioCam.relativeFacing(compass)
      -- the frame the pass would actually draw, through the real chooser
      local frame = VoxelScene._frameFor(p.sprite.def, compass, 0, false)
      local backFrame = SR.STAND["up"]
      log(("MOONWALK yaw %7.2f  compass %-5s -> relative %-5s  frame %s "
           .. "(back is %s)")
          :format(math.deg(MarioCam.viewYaw()), compass, rel,
                  tostring(frame), tostring(backFrame)))
      if q0 ~= q1 then
        log(("         (quadrant moved %d -> %d mid-walk; not judged)")
            :format(q0, q1))
      else
        judged = judged + 1
        if rel ~= "up" then worstOK = false end
        if compass ~= rel then sawDivergence = true end
      end
    end
    -- ------- and it must be a BIJECTION, not a collapse
    --
    -- Every reading above came back "up", which is right -- the character
    -- was walking away from the camera every time -- but it is also what a
    -- rotation that mapped EVERYTHING to "up" would print, and that bug
    -- would put four NPCs facing four ways all showing their backs. So ask
    -- the rotation directly: four distinct facings, four distinct answers.
    do
      local seen, n = {}, 0
      for _, d in ipairs({ "up", "right", "down", "left" }) do
        local r = MarioCam.relativeFacing(d)
        if not seen[r] then seen[r] = true; n = n + 1 end
      end
      log(("MOONWALK bijection: 4 compass facings -> %d distinct drawings"):format(n))
      check(n == 4,
            "four facings still map to four different drawings (the rotation "
            .. "turns the world, it does not flatten it)")
    end
    check(judged >= 4,
          ("enough yaws held still to judge (%d of 6)"):format(judged))
    check(worstOK,
          "walking away from the camera shows the BACK drawing at every yaw")
    -- and the check can fail: if the rotation did nothing, compass and
    -- relative would agree everywhere and the test would be vacuous
    check(sawDivergence,
          "the compass facing and the drawn facing really do diverge, so "
          .. "the check above is not vacuous")
    MarioCam.setting:setIndex(2, game)
  end

  -- ------- 4. CHASE: the focus outruns the eye, in the running game
  --
  -- Measured as the STEADY-STATE LAG of each layer behind its own target
  -- while the player walks, which is the honest in-game reading of the two
  -- constants. For an exponential chase of a target moving at v, the lag
  -- settles at v*(1-k)/k -- so the ratio between the two lags is fixed by
  -- the two coefficients alone and does not depend on how fast the player
  -- walks. At 0.8 and 0.3 corrected to 60fps that ratio is a little over
  -- six.
  --
  -- NOT measured by teleporting the player: setMap builds a new Map, which
  -- is a map change, which is a CUT -- both layers snap and the reading is
  -- of the cut rather than of the chase. The first version of this check
  -- did that and reported the eye moving nearly three times FURTHER than
  -- the focus, which is what a cut looks like when you call it a chase.
  MarioCam.recenter()
  -- ------- WALKING SIDEWAYS, AND THAT IS NOT A DODGE
  --
  -- The radial camera stands on the far side of the player from the area
  -- centre, looking inward. Camera-relative movement therefore makes UP
  -- mean "toward the middle of the map", at every position, by
  -- construction. Hold it and the player converges on the centre and then
  -- oscillates across it inside the yaw deadzone -- 150 frames of pressing
  -- up moved them sixteen pixels net, which is the sum of walking in and
  -- back out again. Correct behaviour, useless for measuring a lag that
  -- needs steady travel in one direction.
  --
  -- LEFT does not have that problem: perpendicular to the view is a walk
  -- AROUND the area centre rather than at it, so the player keeps moving
  -- and the camera keeps chasing.
  --
  -- (The convergence is true of SM64 too: in Bob-omb Battlefield, pushing
  -- away from the camera runs you at the mountain. It is liveable there
  -- because the stick is continuous, and liveable here for the same reason
  -- in reverse -- all four buttons rotate together, so down goes outward
  -- and left and right go around.)
  MarioCam.setting:setIndex(2, game)
  -- ------- A CORRIDOR LONG ENOUGH TO GET UP TO SPEED
  --
  -- The lag this measures is a STEADY-STATE lag, which needs the player
  -- moving continuously for the length of the sample. Celadon's open
  -- pocket is about two cells across in any direction: the player used it
  -- up inside forty frames, stopped against a wall, and the check reported
  -- zero moving frames out of two hundred.
  --
  -- ROUTE_17 is the Cycling Road -- twenty cells wide and a hundred and
  -- forty-four tall, the longest straight run in Kanto.
  --
  -- WHICH BUTTON walks along it is not something this file gets to assume:
  -- under camera-relative movement the physical button maps to whichever
  -- world direction currently reads as "away from the camera", and that
  -- depends on where the radial camera has swung to. So it tries all four
  -- and takes the one that actually travels, which is both robust and the
  -- honest way to write it -- hardcoding a direction here would be
  -- hardcoding an assumption about the camera the test is measuring.
  game.overworld:setMap("ROUTE_17", 9, 40, "down")
  hold(300)
  local pc = game.overworld.player
  local best, bestD = "left", -1
  for _, d in ipairs({ "up", "down", "left", "right" }) do
    local x0, z0 = pc.px, pc.py
    walk(d, 30)
    local moved = math.abs(pc.px - x0) + math.abs(pc.py - z0)
    if moved > bestD then best, bestD = d, moved end
    game.overworld:setMap("ROUTE_17", 9, 40, "down")
    hold(90)
  end
  log(("CHASE corridor: %s travels furthest (%.0f px in 30 frames)")
      :format(best, bestD))
  hold(120)

  releaseDirs()
  local p2 = game.overworld.player
  local startX = p2.px
  local startY = p2.py
  -- ONLY THE FRAMES THE PLAYER ACTUALLY MOVED ON.
  --
  -- The lag being measured is that of a chase behind a MOVING target;
  -- frames where the player stands still -- jammed on a wall, or between
  -- grid steps -- are frames where both lags decay toward zero, and
  -- averaging those in drags the answer toward noise. Averaging everything
  -- read lags of 0.05 and 0.34 pixels: the right ratio, on numbers too
  -- small to mean anything.
  local sumFoc, sumPos, samples = 0, 0, 0
  local lastX, lastZ = p2.px, p2.py
  for i = 1, 200 do
    -- one edge per frame into the press queue: step() sees a synthetic
    -- inject with no source map and holds the button for that step, which
    -- is exactly a held direction and is how the other probes here drive
    -- the game
    game.input.pressQueue[#game.input.pressQueue + 1] = best
    DayNight.clock = CLOCK
    coroutine.yield()
    local movedThisFrame = (p2.px ~= lastX or p2.py ~= lastZ)
    lastX, lastZ = p2.px, p2.py
    if i > 40 and movedThisFrame then
      local c, l = MarioCam.cam, MarioCam.lakitu
      local fx2, fz2 = c.focus[1] - l.curFocus[1], c.focus[3] - l.curFocus[3]
      local px2, pz2 = c.pos[1] - l.curPos[1], c.pos[3] - l.curPos[3]
      sumFoc = sumFoc + math.sqrt(fx2 * fx2 + fz2 * fz2)
      sumPos = sumPos + math.sqrt(px2 * px2 + pz2 * pz2)
      samples = samples + 1
    end
  end
  local walked = math.abs(game.overworld.player.px - startX)
                 + math.abs(game.overworld.player.py - startY)
  releaseDirs()
  local lagFoc = samples > 0 and sumFoc / samples or 0
  local lagPos = samples > 0 and sumPos / samples or 0
  log(("CHASE walked %.0f px over %d moving frames; mean lag: focus %.2f, "
       .. "eye %.2f, ratio %.2f")
      :format(walked, samples, lagFoc, lagPos,
              lagFoc > 0.001 and lagPos / lagFoc or -1))
  check(samples >= 20,
        ("enough moving frames to average (%d)"):format(samples))
  -- A LAG OF ZERO IS NOT A PASS, IT IS A PLAYER WHO NEVER MOVED. The first
  -- run of this check walked into a wall and reported 0.00 against 0.00,
  -- which the ratio test would have called a failure for the wrong reason
  -- and a "greater than" test would have called a pass for a worse one.
  check(walked > 16, ("the player actually walked (%.0f px)"):format(walked))
  check(lagFoc > 0.001 and lagPos / lagFoc > 2.5,
        ("the eye lags several times further than the focus (ratio %.2f)")
        :format(lagFoc > 0.001 and lagPos / lagFoc or -1))
  MarioCam.setting:setIndex(2, game)

  -- ------- 3b. THE CANARY: does the counter above actually catch anything?
  --
  -- Every case so far reported zero, and a check that cannot fail is not
  -- evidence -- the first version of this file proved that the hard way by
  -- running on a map smaller than the culling box and passing everything.
  --
  -- So: ROUTE_20, which is a hundred cells wide and eighteen tall -- a long
  -- east-west corridor, the one shape where a box that always reaches
  -- NORTH has to lose the ground a camera pointed EAST is looking at. Put
  -- the old box back, turn the camera, and demand the counter finds the
  -- holes. If it does not, every pass above is decoration.
  do
    -- ROUTE_17, 20 by 144 cells -- 320 wide and 2304 TALL.
    --
    -- The map has to be long on the axis the old box is asymmetric in, and
    -- that axis is Z: the old box reaches `reach` (about 280px) NORTH and
    -- only vh/2+64 (about 140) SOUTH, while east and west it is already
    -- symmetric at vw/2+spread (about 330) and so has margin to spare. So
    -- a camera turned EAST never embarrasses it -- the first canary tried
    -- exactly that on ROUTE_20 and found nothing, which is a fact about
    -- the old box rather than about the test.
    --
    -- Turned SOUTH on a map 2300 pixels tall, it has nowhere to hide.
    MarioCam.setting:setIndex(2, game)          -- ON
    game.overworld:setMap("ROUTE_17", 9, 60, "up")
    hold(300)
    MarioCam.recenter()
    -- 60 degrees per press, three presses to a half turn -- and a few more
    -- to be sure the ease has landed
    for _ = 1, 4 do game:keypressed("e") hold(90) end
    local yaw = math.deg(MarioCam.viewYaw())

    local terrain = select(1, VoxelScene.prefetch(game.overworld))
    local lv = VoxelScene.lastView
    local reach = ShadowMap.groundReach(lv[4], VoxelScene.FAR_CAP)
    local function countAgainst(b)
      local seen, holes = 0, 0
      if not (terrain and terrain.chunks) then return 0, 0 end
      for _, ch in ipairs(terrain.chunks) do
        if onScreen(ch, 4096, 4096)
           and nearestTo(ch, lv[1], lv[2]) <= reach then
          seen = seen + 1
          if not (ch.x1 >= b[1] and ch.x0 <= b[3]
                  and ch.z1 + (ch.ymax or 0) >= b[2] and ch.z0 <= b[4]) then
            holes = holes + 1
          end
        end
      end
      return holes, seen
    end

    local newHoles, seen = countAgainst(VoxelScene.bounds(lv[1], lv[2], lv[3], lv[4], false))
    local oldHoles = countAgainst(oldBounds(lv[1], lv[2], lv[3], lv[4], false))
    log(("CANARY ROUTE_17 at yaw %.1f, %d chunks on screen and within reach: "
         .. "the OLD box culls %d of them, the new box culls %d")
        :format(yaw, seen, oldHoles, newHoles))
    check(oldHoles > 0,
          "the hole counter CAN fail -- the old north-only box loses "
          .. oldHoles .. " on-screen chunks at this yaw")
    check(newHoles == 0,
          "and the yaw-aware box loses none of them")
    measure("cam_canary_route20", true)
  end

  -- ------- 5. it survives the things that cut
  MarioCam.setting:setIndex(2, game)          -- ON
  goTo(3, 3, "down"); hold(120)
  goTo(wCells - 3, hCells - 3, "up"); hold(120)
  check(MarioCam.camera() ~= nil, "still producing a camera after two warps")
  measure("cam_free", true)

  -- and OFF hands the slot back
  MarioCam.setting:setIndex(1, game); hold(60)
  check(MarioCam.camera() == nil, "OFF yields no camera")
  check(MarioCam.viewYaw() == 0, "OFF reports yaw 0, so the box is the old box")

  log("")
  if #fails == 0 then
    log("ALL CHECKS PASSED")
  else
    log("FAILURES (" .. #fails .. "):")
    for _, f in ipairs(fails) do log("  - " .. f) end
  end
  logf:close()
  love.event.quit()
end
