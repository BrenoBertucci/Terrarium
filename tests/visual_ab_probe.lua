-- A frame from every class of map, for a pixel-exact before/after diff.
--
-- The performance work this was written for (the RenderTarget dpiscale fix,
-- the ShadowMap.available resize, the gated glassMask fetch, the clears
-- before the full-coverage blits, the sun pass's own cull box) is supposed
-- to be INVISIBLE: the same picture, cheaper.  "Supposed to be" is not a
-- claim anybody should accept about a render path, so this takes the picture
-- and the next run compares it.
--
-- Every knob that could move a pixel for a reason other than the change is
-- pinned: the clock, the weather, the wind, the RES rung, the shadow rung,
-- the RTX rung.  RES is pinned to an explicit 1/2 rather than left on AUTO,
-- because AUTO is one of the things being changed and a governor that picked
-- a different rung would diff every pixel in the frame for the right reason
-- and tell us nothing about the wrong ones.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/visual_ab_probe.lua gen1recomp

return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/visual_ab_probe.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
    logf:write(table.concat(p, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end

  local Quality   = lib.require("Quality")
  local RayFX     = lib.require("RayFX")
  local Weather   = lib.require("Weather")
  local DayNight  = lib.require("DayNight")
  local Wind      = lib.require("Wind")
  local MiniMap   = lib.require("MiniMap")
  local AutoFarm  = lib.require("AutoFarm")
  local Pipelines   = require("src.render.Pipelines")
  local ChunkMesher = lib.require("ChunkMesher")

  Pipelines.setLevel("terrarium_voxel", 3)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  MiniMap.setting:sync("off")
  AutoFarm.setting:sync("off")
  Weather.setting:sync("off")
  Wind.setting:sync(0)
  DayNight.setting:sync("day")
  Quality.setting:sync(2)              -- an explicit rung, never AUTO
  Quality.shadowSetting:sync("low")
  RayFX.setting:sync("rt")

  -- ------- EVERYTHING THAT MOVES ON ITS OWN, OFF
  --
  -- The first run of this probe compared a build against ITSELF and the two
  -- frames differed by 4% on a route and 71% inside the haunted tower.  That
  -- is not instability in the render path, it is butterflies, street
  -- Pokemon, civilians walking their routines and GhostFX breathing -- none
  -- of which are seeded, all of which are somewhere else by the time the
  -- second run reaches the same cell.  A diff whose noise floor is bigger
  -- than the effect is not a weak measurement, it is not a measurement.
  --
  -- So the movers come off, and each one is named rather than swept up in a
  -- loop: a row silently missing from this list is a row whose motion is
  -- being charged to the change under test.
  local function off(name, key, value)
    local ok, m = pcall(lib.require, name)
    if not (ok and m) then return end
    local s = m[key]
    if s and s.sync then pcall(s.sync, s, value) end
  end
  off("AmbientLife", "setting", "off")     -- butterflies, birds, fireflies
  off("WildRoamers", "setting", "off")     -- Pokemon standing in the grass
  off("CityLife",    "setting", "off")     -- Pokemon loose in the streets
  off("Routines",    "setting", "off")     -- civilians looking around
  off("Routines",    "agendaSetting", "off")
  off("Shelter",     "setting", "off")
  off("GhostFX",     "setting", "off")     -- the tower's 71% of noise
  off("GroundFX",    "setting", "off")     -- puddles, prints, drying
  off("Vfx",         "setting", "off")
  off("Water",       "setting", 0)         -- a flat sheet has no phase
  Quality.particleSetting:sync(0)          -- the LOW particle rung

  local CLOCK = 300
  local function hold(f)
    for _ = 1, f do DayNight.clock = CLOCK; coroutine.yield() end
    DayNight.clock = CLOCK
  end

  -- The classes of map that exercise different halves of the scene shader:
  -- open terrain with trees, a town with buildings and window panes, dense
  -- forest, a coast (the water sheet), a night street (the lamp loop), an
  -- interior (bloom, lamp specular), and the crypt (CRYPT_MATS).
  local SHOTS = {
    { "route1",    "ROUTE_1",           8, 12, "up",   "day" },
    { "pallet",    "PALLET_TOWN",      10,  8, "up",   "day" },
    { "viridian",  "VIRIDIAN_CITY",    24, 22, "up",   "day" },
    { "cerulean",  "CERULEAN_CITY",    16, 16, "up",   "day" },
    { "route2",    "ROUTE_2",          10, 20, "up",   "day" },
    { "lavender",  "LAVENDER_TOWN",    12, 12, "up",   "night" },
    { "tower1f",   "POKEMON_TOWER_1F",  9, 12, "up",   "day" },
    { "house",     "REDS_HOUSE_1F",     3,  5, "up",   "day" },
  }

  for _, s in ipairs(SHOTS) do
    DayNight.setting:sync(s[6])
    local ok = pcall(function()
      game.overworld:setMap(s[2], s[3], s[4], s[5])
    end)
    if not ok then
      log(("SKIP %-9s %s (setMap refused)"):format(s[1], s[2]))
    else
      -- ------- POLL THE BUILD, DO NOT COUNT FRAMES
      --
      -- The first version of this probe held 300 frames and assumed the
      -- mesher was done.  It is not, reliably: ChunkMesher streams a map in
      -- time-budgeted slices, so how far it gets in 300 frames depends on
      -- how long those frames took -- and a half-built map is a WHOLE CHUNK
      -- of world missing.  That is what the 0.7% "regression" on ROUTE_2
      -- turned out to be: a pond present in one run and not yet uploaded in
      -- another, which a pixel diff reports as a culling bug with a
      -- perfectly straight edge along a chunk boundary.
      --
      -- ChunkMesher.pending() is the honest signal.  It has to read zero
      -- for a stretch, not once: a neighbour's job is queued when the
      -- current map's finishes, so the queue passes through zero on the way
      -- to being full again.
      local quiet, guard = 0, 0
      while quiet < 45 and guard < 2400 do
        hold(1); guard = guard + 1
        local okP, p = pcall(ChunkMesher.pending)
        if okP and (tonumber(p) or 1) == 0 then quiet = quiet + 1 else quiet = 0 end
      end
      if guard >= 2400 then
        log(("WARN %-9s build never went quiet (%d pending)")
              :format(s[1], select(2, pcall(ChunkMesher.pending)) or -1))
      end
      hold(60)
      -- and re-pin, because the player drifts after a setMap (see the note
      -- in the underpass probe)
      pcall(function() game.overworld:setMap(s[2], s[3], s[4], s[5]) end)
      hold(60)
      local shot = nil
      local grabbed = false
      love.graphics.captureScreenshot(function(img)
        shot = img; grabbed = true
      end)
      -- WAIT FOR THE CALLBACK, do not count frames: a screenshot scheduled
      -- and then yielded past photographs the state that comes AFTER it.
      local guard = 0
      while not grabbed and guard < 240 do hold(1); guard = guard + 1 end
      if shot then
        shot:encode("png", "visual_ab_" .. s[1] .. ".png")
        log(("SHOT %-9s %s (%d,%d) %s"):format(s[1], s[2], s[3], s[4], s[6]))
      else
        log(("FAIL %-9s no screenshot after %d frames"):format(s[1], guard))
      end
    end
  end

  -- ------- AND THE TWO PATHS THE EIGHT SHOTS ABOVE CANNOT SEE
  --
  -- Everything above runs with MAP off, T-SHIFT off and the weather off,
  -- which is right for isolating the diorama and wrong for two changes that
  -- only exist on those paths: the radar and the start menu are no longer
  -- painted in drawWorld when the blur is going to repaint them, and
  -- Weather.present no longer binds the panel canvas on a dry frame. Both are
  -- "a pass that was thrown away is now not run", and the way that goes wrong
  -- is a widget that stops appearing at all.
  --
  -- So: the same corner of the same map, with each of them ON.
  local EXTRA = {
    { "hud_tilt",  function()
        MiniMap.setting:sync("on")
        Pipelines.setLevel("terrarium_tiltshift", 3)
      end },
    { "hud_flat",  function()
        MiniMap.setting:sync("on")
        Pipelines.setLevel("terrarium_tiltshift", 0)
      end },
    { "rain_tilt", function()
        MiniMap.setting:sync("on")
        Pipelines.setLevel("terrarium_tiltshift", 3)
        Weather.setting:sync("rain")
      end },
  }
  for _, e in ipairs(EXTRA) do
    e[2]()
    pcall(function() game.overworld:setMap("ROUTE_1", 8, 12, "up") end)
    hold(200)
    local shot, grabbed = nil, false
    love.graphics.captureScreenshot(function(img) shot = img; grabbed = true end)
    local g2 = 0
    while not grabbed and g2 < 240 do hold(1); g2 = g2 + 1 end
    if shot then
      shot:encode("png", "visual_ab_" .. e[1] .. ".png")
      log(("SHOT %-9s ROUTE_1 (8,12)"):format(e[1]))
    else
      log(("FAIL %-9s no screenshot"):format(e[1]))
    end
  end
  MiniMap.setting:sync("off")
  Weather.setting:sync("off")
  Pipelines.setLevel("terrarium_tiltshift", 0)

  -- ------- IS THE SUN PASS'S OUTPUT ACTUALLY REACHING THE SCENE
  --
  -- ShadowMap.active() is what the scene shader gates its sampled shadows on,
  -- and it is `ready and canvas`. Before the available() fix, `ready` was
  -- being forced false by a canvas resize on every single frame, so the sun
  -- pass ran, drew the whole map, and its result was then never read -- the
  -- world fell back to the flat decal shadows. Printing it here is the
  -- difference between "the flowers changed" and "the flowers finally have
  -- shadows".
  do
    local ShadowMap = lib.require("ShadowMap")
    pcall(function() game.overworld:setMap("VIRIDIAN_CITY", 24, 22, "up") end)
    hold(200)
    local live, n = 0, 120
    for _ = 1, n do
      hold(1)
      local okA, a = pcall(ShadowMap.active)
      if okA and a then live = live + 1 end
    end
    log("")
    log(("sun pass: ShadowMap.active() true on %d/%d frames | res=%s | avail=%s")
          :format(live, n, tostring(ShadowMap.res),
                  tostring(select(2, pcall(ShadowMap.available)))))
  end

  log("")
  log("device/quality report:")
  local okQ, q = pcall(Quality.report)
  log(okQ and q or "(unavailable)")
  log("done")
  logf:close()
  love.event.quit()
end
