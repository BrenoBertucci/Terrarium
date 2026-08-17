-- Void rungs, take two: how much of the ROUTE_1 void closes when HORIZON and
-- V-HAZE come up from OFF -- measured at a POSE THAT DOES NOT DRIFT.
--
--   POKEPORT_VERSION=yellow \
--   DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=<build>/tests/void_rung2_probe.lua gen1recomp
--
-- Why this exists when tests/void_rung_probe.lua already ran:
--
--   1. THE POSE DRIFTED. That driver called setMap ONCE and then held for
--      thousands of frames across six captures. The player walks on its own,
--      so void_before_player, void_h0_* and void_h3_* are three different
--      spots on ROUTE_1. Every cross-rung number it printed compares two
--      different views. aerial_probe already knew this and repins per sample
--      (tests/aerial_probe.lua:116); this one does the same.
--
--   2. THE EDGE DETECTOR IS BLIND TO THE THING IT MEASURES. findEdge walks
--      down each column to the first pixel that is not `skyish`, and skyish
--      is a HUE test: b > g + 0.02 and b > r + 0.02. A distant silhouette
--      crushed toward the sky colour by the haze -- which lib/Skyline.lua
--      says in its header is the entire point of drawing it -- stays bluer
--      than it is green or red, so it counts as sky and the scan walks
--      straight through it. A skyline that WORKS reports as "gap unchanged".
--
--      So this driver does not decide anything from pixels in Lua. It
--      captures PNGs at a pinned pose and logs the pose next to each one;
--      the measuring happens offline where it can be re-run without the game.
--
-- What gets logged per shot: map + player cell + camera + horizonY, so the
-- analysis can REJECT any pair whose pose is not identical instead of
-- quietly averaging two different views like the last run did.
--
-- Settings are moved with ModSetting:sync only -- RAM, no writeOptions (see
-- lib/ModSetting.lua:101 vs :90). The player's options.lua is not touched.

return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = io.open(OUT .. "/void_rung2_probe.log", "w")
  if not logf then
    OUT = "."
    logf = assert(io.open(OUT .. "/void_rung2_probe.log", "w"))
  end
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close(); love.event.quit(); return end
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
  log("sync-only driver: never calls setIndex/writeOptions.")

  local Skyline = lib.require("Skyline")
  local Aerial = lib.require("Aerial")
  local Voxel3D = lib.require("Voxel3D")
  local WorldAtlas = lib.require("WorldAtlas")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local MiniMap = lib.require("MiniMap")
  local Quality = lib.require("Quality")
  local Grass3D = lib.require("Grass3D")
  local AutoFarm = lib.require("AutoFarm")
  local Pipelines = require("src.render.Pipelines")

  local saved = {
    skyline = Skyline.setting:get(),
    haze = Aerial.setting:get(),
    weather = Weather.setting:get(),
    daytime = DayNight.setting:get(),
    shadows = Quality.shadowSetting:get(),
    grass = Grass3D.setting:get(),
    minimap = MiniMap.setting:get(),
    autofarm = AutoFarm.setting:get(),
  }
  log(("stored rows: HORIZON=%s V-HAZE=%s weather=%s daytime=%s shadows=%s grass3d=%s")
        :format(tostring(saved.skyline), tostring(saved.haze),
                tostring(saved.weather), tostring(saved.daytime),
                tostring(saved.shadows), tostring(saved.grass)))

  -- The GRASS row, honestly this time. The old driver printed
  --   getInfo(path) ~= nil or true
  -- which is `true` no matter what -- it never checked the bake at all.
  -- pcall'd: a broken bake must not take the void measurement down with it.
  local okG, errG = pcall(function()
    local function has(p)
      local ok, info = pcall(love.filesystem.getInfo, p)
      return ok and info ~= nil
    end
    local bake = Grass3D.meta()
    log(("GRASS: row=%s wantsMesh=%s available=%s | bake bin=%s png=%s meta=%s height=%s")
          :format(tostring(Grass3D.setting:get()),
                  tostring(Grass3D.wantsMesh()), tostring(Grass3D.available()),
                  tostring(has("assets/ground/grass/grass.mesh.bin")),
                  tostring(has("assets/ground/grass/grass.png")),
                  tostring(has("assets/ground/grass/grass.meta.json")),
                  tostring(bake and bake.height)))
  end)
  if not okG then log("GRASS: probe failed -- " .. tostring(errG)) end

  -- Step markers instead of an xpcall wrapper: the driver body yields, and
  -- yielding across a pcall boundary is only legal on LuaJIT. Not worth
  -- betting the run on which Lua this build ships -- a flushed marker before
  -- each risky call localises a crash just as well and cannot itself break.
  local step = 0
  local function mark(what)
    step = step + 1
    log(("  .. step %d: %s"):format(step, what))
  end

  mark("Pipelines.setLevel voxel/tiltshift")
  Pipelines.setLevel("terrarium_voxel", 5)     -- 75deg: horizon in frame
  Pipelines.setLevel("terrarium_tiltshift", 0)
  mark("MiniMap/AutoFarm sync off")
  MiniMap.setting:sync("off")
  AutoFarm.setting:sync("off")

  local CLOCK = 300
  local function hold(frames)
    for _ = 1, frames do
      DayNight.clock = CLOCK
      coroutine.yield()
    end
    DayNight.clock = CLOCK
  end

  local SPOT = { "ROUTE_1", 8, 12, "up" }

  -- THE PIN, and the ordering is the whole point.
  --
  -- Take one repinned before each sample and then settled for 300 frames.
  -- That is backwards: the player walks on its own (~1 cell per 100 frames
  -- at SPEED=4), so the settle IS the drift window, and all six captures
  -- landed on different cells -- (4,12), (5,14), (13,12), (6,12). Every
  -- cross-rung number from that run compares two different views.
  --
  -- So: settle FIRST (once, in warm()), then pin and shoot inside a handful
  -- of frames, and VERIFY the cell at capture time rather than trusting it
  -- (the check tests/underpass_rail_probe.lua:113 does).
  local function warm()
    game.overworld:setMap(SPOT[1], SPOT[2], SPOT[3], SPOT[4])
    hold(400)          -- chunk mesher is async; a short settle measures the
                       -- flat 2D fallback instead (aerial_probe.lua:110-115)
  end

  local function atSpot()
    local p = game.overworld and game.overworld.player
    return p and p.cellX == SPOT[2] and p.cellY == SPOT[3]
  end

  -- Returns true when the player is standing exactly on SPOT.
  local function pin()
    for _ = 1, 6 do
      game.overworld:setMap(SPOT[1], SPOT[2], SPOT[3], SPOT[4])
      hold(6)
      if atSpot() then return true end
    end
    return atSpot()
  end

  local function poseStr()
    local o = game.overworld
    local p = o and o.player
    local c = o and o.camera
    local m = o and o.map
    return ("map=%s cell=(%s,%s) xy=(%s,%s) cam=(%s,%s)")
      :format(tostring(m and (m.id or m.name)),
              tostring(p and p.cellX), tostring(p and p.cellY),
              tostring(p and p.x), tostring(p and p.y),
              tostring(c and c.x), tostring(c and c.y))
  end

  mark("renderer:worldViewSize")
  local vw, vh = game.renderer:worldViewSize()
  log(("view: %dx%d world px"):format(vw, vh))
  log(("REACHES: OFF=%d NEAR=%d FAR=%d ALL=%d (view-heights)")
        :format(Skyline.REACHES[1], Skyline.REACHES[2],
                Skyline.REACHES[3], Skyline.REACHES[4]))

  local function cachedCount()
    local c = 0
    for _ in pairs(Skyline._meshes or {}) do c = c + 1 end
    return c
  end

  local function atlasCounts(reachVH)
    local state = game.overworld
    WorldAtlas.invalidate()
    local beyond = WorldAtlas.beyond(state)
    local cam = state.camera
    local cx = (cam and cam.x or 0) + vw / 2
    local cy = (cam and cam.y or 0) + vh / 2
    local reach = (reachVH or 0) * vh
    local nIn, far, farId = 0, 0, nil
    for _, e in ipairs(beyond) do
      local dx = (e.ox + e.def.width * 16) - cx
      local dz = (e.oy + e.def.height * 16) - cy
      local d = math.sqrt(dx * dx + dz * dz)
      if d > far then far, farId = d, e.id end
      if d <= reach then nIn = nIn + 1 end
    end
    return #beyond, nIn, far / vh, farId
  end

  -- Capture only. No pixel verdicts in here.
  local function shot(name, note)
    local pending = true
    local hy
    love.graphics.captureScreenshot(function(data)
      local W, H = data:getDimensions()
      hy = Voxel3D.horizonY(H)
      local f = io.open(OUT .. "/" .. name .. ".png", "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      log(("  [%s] %dx%d horizonY=%.2f  %s"):format(name, W, H, hy or -1, poseStr()))
      pending = false
    end)
    local g = 0
    while pending and g < 240 do hold(1); g = g + 1 end
    log(("  [%s] %s | cached=%d"):format(name, note or "", cachedCount()))
  end

  -- One rung sample: set the rows, repin, settle, capture.
  local LABELS = { [0] = "OFF", [1] = "NEAR", [2] = "FAR", [3] = "ALL" }
  local function sample(name, horizon, haze, weather, daytime, shadows)
    mark(("sample %s -> sync rows"):format(name))
    Weather.setting:sync(weather)
    DayNight.setting:sync(daytime)
    Quality.shadowSetting:sync(shadows or saved.shadows)
    Skyline.setting:sync(horizon)
    Aerial.setting:sync(haze)
    -- let the new rows take effect (weather ramp, haze uniform, day tint)
    -- BEFORE pinning, so the drift happens here and not after the pin
    hold(120)
    mark(("sample %s -> pin"):format(name))
    local pinned = pin()
    mark(("sample %s -> atlasCounts"):format(name))
    local beyond, inR, far, farId = atlasCounts(Skyline.REACHES[horizon + 1])
    mark(("sample %s -> shot (pinned=%s)"):format(name, tostring(pinned)))
    if not pinned then log(("  WARN %s: could not pin to SPOT"):format(name)) end
    shot(name, ("HORIZON=%s(reach=%d) V-HAZE=%d weather=%s day=%s shadows=%s "
                .. "| beyond=%d in-reach=%d farthest=%s@%.1fvh")
                :format(LABELS[horizon], Skyline.REACHES[horizon + 1], haze,
                        tostring(weather), tostring(daytime), tostring(shadows),
                        beyond, inR, tostring(farId), far or -1))
  end

  -- Warm-up, once: build the terrain at SPOT, then build every skyline
  -- impostor up front at HORIZON=ALL. They are cached in a module-level
  -- table and one is built per frame, so paying for all eight here means
  -- each later sample can pin and shoot in a few frames instead of needing
  -- a 200-frame build window that the player would walk away during.
  mark("warm: settle terrain at SPOT")
  Weather.setting:sync("rain")
  DayNight.setting:sync("cycle")
  warm()
  mark("warm: prebuild impostors at HORIZON=ALL")
  Skyline.setting:sync(3)
  Aerial.setting:sync(2)
  hold(200)
  log(("  warm done: cached=%d  %s"):format(cachedCount(), poseStr()))

  -- ---- A: the player's stored pair, rain (the BEFORE the screenshot shows)
  log("")
  log("=== A. player's stored pair: HORIZON=OFF V-HAZE=OFF, rain ===")
  sample("v2_before_player", 0, 0, "rain", "cycle", "high")

  -- ---- B: the HORIZON ladder with V-HAZE held at 2, rain
  log("")
  log("=== B. HORIZON ladder at V-HAZE=2, rain, clock=300 ===")
  for level = 0, 3 do
    sample(("v2_h%d_%s_haze2"):format(level, LABELS[level]), level, 2,
           "rain", "cycle", "high")
  end

  -- ---- C: cardboard -- silhouettes at full ink, haze off
  log("")
  log("=== C. cardboard check: HORIZON on, V-HAZE=OFF ===")
  sample("v2_near_hazeOFF", 1, 0, "rain", "cycle", "high")
  sample("v2_all_hazeOFF", 3, 0, "rain", "cycle", "high")

  -- ---- D: is the dark corner shadow, or a hole? same rungs, shadows moved
  log("")
  log("=== D. class D test: shadows HIGH vs OFF at the player's rungs ===")
  sample("v2_shadows_high", 0, 0, "rain", "cycle", "high")
  sample("v2_shadows_off", 0, 0, "rain", "cycle", "off")

  -- ---- E: the player is actually on daytime=night now, not cycle
  log("")
  log("=== E. night pass (the row options.lua actually holds) ===")
  sample("v2_night_off", 0, 0, "rain", "night", "high")
  sample("v2_night_all_haze2", 3, 2, "rain", "night", "high")

  -- put the RAM rows back exactly as found, so a quit-time write is a no-op
  Skyline.setting:sync(saved.skyline)
  Aerial.setting:sync(saved.haze)
  Weather.setting:sync(saved.weather)
  DayNight.setting:sync(saved.daytime)
  Quality.shadowSetting:sync(saved.shadows)
  Grass3D.setting:sync(saved.grass)
  MiniMap.setting:sync(saved.minimap)
  AutoFarm.setting:sync(saved.autofarm)
  log("")
  log(("restored rows: HORIZON=%s V-HAZE=%s weather=%s daytime=%s shadows=%s")
        :format(tostring(Skyline.setting:get()), tostring(Aerial.setting:get()),
                tostring(Weather.setting:get()), tostring(DayNight.setting:get()),
                tostring(Quality.shadowSetting:get())))
  log("done -- " .. OUT)
  logf:close()
  love.event.quit()
end
