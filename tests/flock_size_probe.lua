-- Probe: how big a flock bird actually draws.
--
-- The claim under test is a claim about PIXELS -- "the birds were too small"
-- -- and the one thing that cannot prove it is the constant in the source.
-- `s` in the draw path is a perspective scale, so raising the multiplier and
-- raising what the player sees are two different statements.
--
-- The rig isolates the bird instead of photographing it. AmbientLife.draw
-- takes `project` as a PARAMETER, so this probe hands it a stub that
--
--   * returns nil for anything below y=20, which drops every leaf, firefly,
--     butterfly and dragonfly on the map (a flock spawns at y=34..48, and
--     nothing else this file makes flies that high), and
--   * returns a position for the FIRST bird only, so the canvas holds one
--     bird rather than an overlapping flock of three to five, and
--   * pins ps=1.0, so the perspective term is a constant and what is left
--     moving is only the size under test.
--
-- Drawn at scale=20 to lift the measurement off the quantisation floor: the
-- multiplier is linear, so a ratio measured at 20 is the ratio at 1.
--
-- Also takes an ordinary in-game screenshot, because an isolated canvas
-- passing is not evidence that the thing draws in the real frame -- that is
-- the battle-HUD ink lesson, and it cost a "done" that was not.
--
--   POKEPORT_VERSION=yellow \
--   DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/flock_size_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/flock_size_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n")
    logf:flush()
  end
  local function wait(n)
    for _ = 1, n do coroutine.yield() end
  end
  local function tap(btn)
    game.input.pressQueue[#game.input.pressQueue + 1] = btn
    coroutine.yield()
  end
  local function done(msg)
    log(msg); logf:close(); love.event.quit()
  end

  love.math.setRandomSeed(20260817)

  -- ------- reach free roam
  local frames = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); frames = frames + 1
    if frames > 900 then return done("FAIL: no overworld") end
  end
  frames = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); frames = frames + 11
    if frames > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then return done("FAIL: TERRARIUM not loaded") end
  log("version:", exports.TERRARIUM.version)

  local AmbientLife = lib.require("AmbientLife")
  local DayNight    = lib.require("DayNight")
  local Voxel3D     = lib.require("Voxel3D")
  local Map         = require("src.world.Map")

  -- ------- an outdoor map, at the hour the flock is allowed to fly
  --
  -- The flock gate is `day and not canopy`, so night and a tree ceiling both
  -- read as "no birds" and would look exactly like a broken feature.
  -- Which map, from the environment, because the three things worth
  -- measuring live on three different ones:
  --
  --   ROUTE_1      Pidgey off the map's own table -- the ordinary path
  --   ROUTE_18     Fearow, frontSize 7 -- the top of the size hierarchy
  --   PALLET_TOWN  no encounter table AT ALL -- the fallback path. No
  --                outdoor map in the game has a grass table without a
  --                flyer in it, so `#pool == 0` is unreachable outdoors;
  --                a town with no table is the only way this branch runs.
  local MAP = os.getenv("DS_PROBE_MAP") or "ROUTE_1"
  local MX = tonumber(os.getenv("DS_PROBE_X")) or 10
  local MY = tonumber(os.getenv("DS_PROBE_Y")) or 20
  game.overworld:setMap(MAP, MX, MY, "down")
  wait(90)
  local outdoor = Map.isOutdoor(game.overworld.map.def)
  log("map:", game.overworld.map.id, "outdoor:", tostring(outdoor))
  if not outdoor then return done("FAIL: probe map is not outdoor") end

  -- The flock gate is `tod == "DAY" or tod == "MORNING"` -- a STRING off
  -- DayNight.tod(), bucketed by the T thresholds (dawn=0, day=300,
  -- dusk=600, night=900). It is not the same discriminator as mix.day.
  --
  -- Sweeping for peak mix.day lands on t=270, which reads day=1.000 and is
  -- still DAWN by the buckets -- so the gate stays shut, no flock ever
  -- spawns, and the probe reports the feature missing. That cost a run.
  -- Pick the hour by the same function the gate reads, and assert it.
  -- And writing DayNight.clock is not how you set the hour. `time()` only
  -- reads the clock under the CYCLE mode; under the default it reads the
  -- machine's wall clock (`syncTime`), and under a pin it reads T[mode].
  -- So a probe that sets .clock and runs in the evening gets tod=NIGHT and
  -- a silent, permanently shut flock gate. Pin the MODE instead.
  DayNight.setting:sync("day")
  log("daynight mode:", tostring(DayNight.setting:get()))
  local tod = DayNight.tod()
  log(("time=%s tod=%s"):format(tostring(DayNight.time()), tostring(tod)))
  if not (tod == "DAY" or tod == "MORNING") then
    return done("FAIL: not in the flock's window (tod=" .. tostring(tod) .. ")")
  end

  -- ------- wait for the 3D pass, which is not up when setMap returns
  --
  -- main.lua calls `AmbientLife.update(dt, Voxel.active())`, and the FIRST
  -- thing update does when that flag is false is drop the whole population.
  -- So until the voxel pass is meshed, every frame of the game's own loop
  -- deletes the flock this probe just forced into being -- which reads as
  -- "the birds vanish", and cost two runs before it was the 3D pass rather
  -- than the birds. Frame counting does not work here: VoxelScene.render
  -- returns nil until the terrain is meshed, so poll the thing it fills.
  local waited = 0
  while Voxel3D.lampLights == nil and waited < 900 do
    wait(1); waited = waited + 1
  end
  log(("3D pass: up after %d frames (lampLights=%s)")
      :format(waited, tostring(Voxel3D.lampLights ~= nil)))
  if Voxel3D.lampLights == nil then
    return done("FAIL: 3D pass never came up -- every reading below would be a lie")
  end
  local okShader, shader = pcall(Voxel3D.shader)
  log("shader:", tostring(okShader and shader ~= nil),
      "err:", tostring(Voxel3D.shaderError))
  wait(60)

  -- ------- drive the flock clock until birds exist
  --
  -- birdTimer is 18..36s and lives in an upvalue, so the only honest way to
  -- fire it is to hand update() the seconds. Counted through a real draw,
  -- because that is the only reader of the population this file exposes.
  -- ------- telling a bird from everything else, with only (x, y, z)
  --
  -- `project` is handed no `kind`, so altitude is the only discriminator
  -- available -- and the obvious cut, "above the ground life", is WRONG.
  -- Leaves ride the wind up to a hard ceiling of 36 (`if c.y > 36 then
  -- c.y = 36`), so a y>=20 filter counts every leaf on a windy route as a
  -- bird. That is what the first four runs of this probe were measuring:
  -- the 5x5 box it reported was a maple chip, not a Pidgey.
  --
  -- 37 is above the leaf ceiling and inside the flock's 34..48 spawn band.
  -- It gives up the birds that roll below 37 -- about a fifth of them --
  -- which costs nothing here: a flock is three to five, and the odds of a
  -- whole one landing under the cut are about one in a hundred.
  -- ...and 37 is still not enough, because a STARTLED SPARROW launches at
  -- vy=34 and climbs straight through the band. Its rectangles are drawn at
  -- a size this change never touched, so measuring one gives a reading that
  -- is identical on both builds -- which is exactly what Pallet Town
  -- reported before this guard existed: 176px wide and 6400 opaque on the
  -- old build AND the new one. Two builds agreeing on a number I changed is
  -- the tell that the number is about something else.
  --
  -- The separator is the RATE of motion. Both move: a flock bird bobs
  -- (`c.y = c.y + sin(...) * 2 * dt`, so at most ~0.034 per frame) and a
  -- startled sparrow climbs (`c.y = c.y + 34 * dt`, ~0.57 per frame) --
  -- seventeen times faster. Matching on an unchanged y therefore finds
  -- NOTHING, bird or sparrow, which is how the first version of this guard
  -- reported zero birds on Route 1, a map that had just measured four.
  local BIRD_Y = 37
  local BOB_MAX = 0.15          -- per frame: above a bob, far below a climb

  local function birdYs()
    local ys = {}
    AmbientLife.draw(function(_, y)
      if y and y >= BIRD_Y then ys[#ys + 1] = y end
    end, 1)
    return ys
  end

  -- Returns the current y of one bobbing bird, and how many there were.
  local function steadyBirdY()
    local a = birdYs()
    wait(1)
    local b = birdYs()
    local first, n = nil, 0
    for _, y2 in ipairs(b) do
      local best = math.huge
      for _, y1 in ipairs(a) do
        local d = math.abs(y2 - y1)
        if d < best then best = d end
      end
      if best <= BOB_MAX then n = n + 1; first = first or y2 end
    end
    return first, n
  end

  local function birdCount()
    local _, n = steadyBirdY()
    return n
  end

  -- Waited for on real frames, not fast-forwarded.
  --
  -- The obvious shortcut is to hand update() two seconds at a time until
  -- the 18-36s flock timer fires. It does fire -- and it also advances the
  -- BIRDS two seconds per call, so a flock that should arrive abreast is
  -- flung 70px per step and arrives as one survivor, or none. Three runs
  -- of this probe reported "1 bird" and "0 birds still aloft" and every one
  -- of those numbers was the fast-forward talking, not the feature.
  --
  -- So: let the game run. It costs up to ~36 seconds of frames and it is
  -- the only way the thing being measured is the thing that ships.
  -- Wait out the current flock, then wait for the next one, then let it
  -- fade in. Returns the head count, or 0 if none arrived in time.
  --
  -- Two things this deliberately does NOT do. It does not fast-forward:
  -- handing update() two seconds at a time fires the 18-36s timer but flings
  -- the birds 70px per call, so they cross the view and cull, and three runs
  -- of this probe reported "1 bird" / "0 aloft" that were the fast-forward
  -- talking rather than the feature. And it does not measure on the spawn
  -- frame: `fade = min(1, c.t * 2, (c.ttl - c.t) * 2)` is ZERO at t=0, so a
  -- newborn draws at alpha nothing and reads exactly like a feature that
  -- does not draw.
  local function awaitFlock()
    local f = 0
    while birdCount() > 0 and f < 3000 do wait(1); f = f + 1 end
    while birdCount() == 0 and f < 3000 do wait(1); f = f + 1 end
    if birdCount() == 0 then return nil, 0, f / 60 end
    wait(45)                                    -- past the fade ramp
    local y, n = steadyBirdY()                  -- re-read: the flock aged
    return y, n, f / 60
  end

  -- ------- measure exactly one bird, on a canvas of its own
  --
  -- Swept over `scale` rather than measured once. A single number cannot
  -- tell "the argument never arrived" from "it arrived and something else
  -- shrank it": if the box is the same at 1 and at 40 then `s` is pinned by
  -- the max(1, ...) floor and the reading says nothing about size at all.
  -- The centre pixel separates the two draw paths -- the sheet tints white,
  -- the fallback chevron is a fixed dark slate (0.20, 0.22, 0.28).
  local SIZE = 256
  local canvas = love.graphics.newCanvas(SIZE, SIZE)

  local function measure(scale, targetY)
    local shown = false
    local function oneBird(_, y)
      -- Matched against the y of a bird already shown to be bobbing rather
      -- than climbing. A tolerance, not equality: the bob keeps writing y,
      -- so it has drifted a little since it was sampled.
      if not y or math.abs(y - targetY) > 0.5 then return nil end
      if shown then return nil end             -- flockmates: not this test
      shown = true
      return SIZE / 2, SIZE / 2, 1.0           -- ps pinned: size is the only variable
    end

    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1, 1)
    AmbientLife.draw(oneBird, scale)
    love.graphics.setCanvas()

    local data = canvas:newImageData()
    local minX, minY, maxX, maxY, opaque = SIZE, SIZE, -1, -1, 0
    for y = 0, SIZE - 1 do
      for x = 0, SIZE - 1 do
        local _, _, _, a = data:getPixel(x, y)
        if a > 0.05 then
          opaque = opaque + 1
          if x < minX then minX = x end
          if x > maxX then maxX = x end
          if y < minY then minY = y end
          if y > maxY then maxY = y end
        end
      end
    end
    local cr, cg, cb = data:getPixel(SIZE / 2, SIZE / 2)
    data:release()
    if maxX < 0 then return 0, 0, 0, nil end
    return maxX - minX + 1, maxY - minY + 1, opaque,
           ("%.2f,%.2f,%.2f"):format(cr, cg, cb)
  end

  -- ------- trial 1: the scale sweep, which is the sanity check
  local targetY, born, secs = awaitFlock()
  log(("flock 1: %d steady birds after %.1fs (y=%s)")
      :format(born, secs, tostring(targetY)))
  if born == 0 or not targetY then
    return done("FAIL: no flock spawned -- gate or timer")
  end

  local lastCentre
  for _, scale in ipairs({ 1, 5, 20, 40 }) do
    local w, h, opaque, centre = measure(scale, targetY)
    if w == 0 then
      log(("MEASURE scale=%-3d bbox=EMPTY -- nothing reached the canvas"):format(scale))
    else
      lastCentre = centre
      log(("MEASURE scale=%-3d bbox=%dx%d opaque=%d px  centre=%s  drawn-mult=%.2f")
          :format(scale, w, h, opaque, centre, w / scale))
    end
  end

  -- ------- further flocks, for maps whose flyer pool is not a singleton
  --
  -- No outdoor map in Kanto has a grass table whose only flyer is a big one:
  -- every singleton pool is a frontSize-5 bird, and the routes that carry
  -- FEAROW carry SPEAROW beside it. So the species of any ONE flock is a
  -- coin flip, and a single reading cannot be attributed to a species.
  --
  -- Repeating across flocks is what makes it attributable: if per-species
  -- scaling is live, the readings separate into clusters -- one per species
  -- in the pool -- and if it is dead they all land on one number. That is
  -- the claim worth testing here, and it does not need to know which bird
  -- it got.
  local TRIALS = tonumber(os.getenv("DS_PROBE_TRIALS")) or 1
  for trial = 2, TRIALS do
    local ty, n, waited = awaitFlock()
    if n == 0 or not ty then
      log(("flock %d: none arrived (%.1fs) -- stopping"):format(trial, waited))
      break
    end
    local w, h, opaque, centre = measure(40, ty)
    log(("flock %d: %d birds  bbox=%dx%d opaque=%d  centre=%s  drawn-mult=%.2f")
        :format(trial, n, w, h, opaque, tostring(centre), w / 40))
  end

  -- Which of the two draw paths ran. The sheet tints white, so the centre
  -- carries the species' own colour; the fallback chevron is a hardcoded
  -- slate. This is the whole test on a map with no encounter table -- the
  -- point there is not the size, it is that a SPRITE arrived where the old
  -- build put three grey rectangles.
  -- Compared by HUE ORDER, not by string. The chevron's slate is written as
  -- (0.20, 0.22, 0.28) but drawn at `0.9 * fade`, so it reaches the canvas
  -- as something like 0.18,0.20,0.25 -- and an equality test against the
  -- source constant calls that a sprite. What survives the fade is the
  -- ordering: the slate is strictly blue-heavy (r < g < b), while a baked
  -- bird is warm (Pidgey lands at 0.58,0.22,0.10, red-heavy).
  if lastCentre then
    local r, g2, b = lastCentre:match("([%d%.]+),([%d%.]+),([%d%.]+)")
    r, g2, b = tonumber(r), tonumber(g2), tonumber(b)
    local isChevron = r and g2 and b and r < g2 and g2 < b
    log(("PATH: %s  (centre=%s)")
        :format(isChevron and "CHEVRON fallback" or "species sprite", lastCentre))
  end

  -- ------- and the ordinary frame, because isolation is not evidence
  love.graphics.captureScreenshot(function(d)
    local f = io.open(OUT .. "/flock_ingame.png", "wb")
    if f then f:write(d:encode("png"):getString()) f:close() end
  end)
  wait(5)

  done("done")
end
