-- Probe: the authored Lavender camera shots (data/camera_shots.lua) and
-- the law the whole feature answers to: NOTHING STANDS BETWEEN THE EYE
-- AND THE PLAYER. Buildings count at their stamped model height
-- (Buildings.tallAt), not at the mesher's polite ground -- the player's
-- own screenshot of a camera parked behind five storeys of roof is the
-- failure this file exists to keep dead.
--
--   SHOTS   every authored box: walking into it acquires the shot, runs
--           the right mode, lands the lens, keeps the player on screen,
--           and leaves the 3D sightline clear.
--   SIGHT   a sweep of ordinary cells on the two big towns: settle, then
--           demand the eye-to-player ray clears terrain AND buildings.
--   ARC     entering the west box by walking is a TRANSITION, not a cut:
--           the real camera's largest single-frame step stays small.
--
-- Screenshots for every case, because a camera is a thing you look at.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/lavender_shots_probe.log", "w"))
  local function log(s) logf:write(s, "\n"); logf:flush() end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit() return end
  end
  while game.stack:top() ~= game.overworld do tap("a"); wait(10) end

  local lib = game.mods.exports.TERRARIUM.lib
  local MarioCam = lib.require("MarioCam")
  local Voxel3D = lib.require("Voxel3D")
  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local MiniMap = lib.require("MiniMap")
  local AutoFarm = lib.require("AutoFarm")
  local Pipelines = require("src.render.Pipelines")
  Pipelines.setLevel("terrarium_voxel", 4)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  MiniMap.setting:setIndex(3, game)
  Weather.setting:setIndex(2, game)
  AutoFarm.setting:setIndex(1, game)
  MarioCam.setting:setIndex(2, game)

  local CLOCK = 300
  local function hold(frames)
    for _ = 1, frames do DayNight.clock = CLOCK; coroutine.yield() end
  end
  local function releaseDirs()
    local st = game.input.state
    for _, d in ipairs({ "up", "down", "left", "right" }) do
      st[d] = false
      if game.input.sources then game.input.sources[d] = nil end
    end
    game.input.pressQueue = {}
  end

  local fails = {}
  local function check(ok, msg)
    if not ok then fails[#fails + 1] = msg end
    log((ok and "  ok   " or "  FAIL ") .. msg)
  end

  local function shoot(name)
    local pending = true
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name .. ".png", "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      pending = false
    end)
    local guard = 0
    while pending and guard < 300 do hold(1); guard = guard + 1 end
  end

  -- THE LAW: from where the camera really is to the player's middle,
  -- through terrain and stamped buildings, nothing in the way.
  local function sightClear()
    local e = MarioCam.lakitu.curPos
    local f = MarioCam.lakitu.curFocus
    local map = game.overworld.map
    return not MarioCam.rayBlocked(map, e[1], e[2], e[3],
                                   f[1], f[2] + 8, f[3])
  end

  local function playerOnScreen()
    local p = game.overworld.player
    local px, py = Voxel3D.project((p.px or 0) + 8, 8, (p.py or 0) + 8)
    if not px then return false end
    local w, h = love.graphics.getDimensions()
    return px >= 0 and px <= w and py >= 0 and py <= h
  end

  -- ------- 1. SHOTS: every authored box, acquired and honest
  local SHOTS = {
    { "shot_west",  "LAVENDER_TOWN",    1,  7, "fixed", nil },
    { "shot_door",  "LAVENDER_TOWN",   14,  6, "fixed", 46 },
    { "shot_t1f",   "POKEMON_TOWER_1F", 10, 8, "fixed", 38 },
    { "shot_t2f",   "POKEMON_TOWER_2F",  5, 7, "fixed", 38 },
    { "shot_t3f",   "POKEMON_TOWER_3F",  5, 6, "fixed", 38 },
    { "shot_t4f",   "POKEMON_TOWER_4F",  4, 8, "fixed", 38 },
    { "shot_t5f",   "POKEMON_TOWER_5F",  6, 6, "fixed", 38 },
    { "shot_t6f",   "POKEMON_TOWER_6F",  5, 7, "fixed", 30 },
    { "shot_t7f",   "POKEMON_TOWER_7F", 11, 8, "fixed", 38 },
  }
  for _, s in ipairs(SHOTS) do
    local name, mapId, cx, cy, mode, fov = s[1], s[2], s[3], s[4], s[5], s[6]
    game.overworld:setMap(mapId, cx, cy, "down")
    hold(150)
    releaseDirs()
    game.overworld:setMap(mapId, cx, cy, "down")
    hold(120)
    local shot = MarioCam.cam.shot
    check(shot ~= nil, name .. ": the box acquires a shot")
    check(MarioCam.cam.mode == mode,
          name .. ": mode " .. tostring(MarioCam.cam.mode) .. " want " .. mode)
    if fov then
      check(math.abs(MarioCam.lakitu.fov - fov) < 2,
            ("%s: lens %.1f want %d"):format(name, MarioCam.lakitu.fov, fov))
    end
    check(playerOnScreen(), name .. ": the player projects on screen")
    check(sightClear(), name .. ": nothing between the eye and the player")
    shoot(name)
  end

  -- ------- 2. SIGHT: ordinary cells, the universal law
  local SWEEP = {
    { "CELADON_CITY", { {24,30},{25,18},{8,16},{16,8},{35,10},{40,28},{6,28},{30,22} } },
    { "LAVENDER_TOWN", { {7,6},{2,14},{16,14},{8,8},{1,7},{17,15} } },
  }
  for _, m in ipairs(SWEEP) do
    local mapId, cells = m[1], m[2]
    for _, c in ipairs(cells) do
      game.overworld:setMap(mapId, c[1], c[2], "down")
      hold(90)
      releaseDirs()
      game.overworld:setMap(mapId, c[1], c[2], "down")
      hold(150)
      local p = game.overworld.player
      local at = ("(%d,%d)"):format(
        math.floor((p.px + 8) / 16), math.floor((p.py + 8) / 16))
      check(sightClear(),
            mapId .. " " .. at .. ": player visible past terrain and buildings")
    end
  end
  shoot("sight_last")

  -- ------- 3. ARC: walking into the west box is a transition, not a cut
  --
  -- WHICH BUTTON walks west is not this file's to assume: under
  -- camera-relative movement the physical button maps to whatever the
  -- camera's quadrant says. So each is tried and the one that actually
  -- moves the player toward -x is held -- the same honesty the CHASE
  -- section of the main probe had to learn.
  game.overworld:setMap("LAVENDER_TOWN", 5, 7, "down")   -- east of the box
  hold(200)
  releaseDirs()
  local pw = game.overworld.player
  local best, bestD = "left", 0
  for _, d in ipairs({ "left", "right", "up", "down" }) do
    local x0 = pw.px
    for _ = 1, 20 do
      game.input.pressQueue[#game.input.pressQueue + 1] = d
      DayNight.clock = CLOCK
      coroutine.yield()
    end
    releaseDirs()
    hold(10)
    local moved = x0 - pw.px          -- positive = went west
    if moved > bestD then best, bestD = d, moved end
    game.overworld:setMap("LAVENDER_TOWN", 5, 7, "down")
    hold(60)
    releaseDirs()
  end
  log(("ARC: physical '%s' walks west (%d px in 20 frames)"):format(best, bestD))
  local maxStep = 0
  local lastX, lastY, lastZ
  for i = 1, 90 do
    game.input.pressQueue[#game.input.pressQueue + 1] = best
    DayNight.clock = CLOCK
    coroutine.yield()
    local e = MarioCam.lakitu.curPos
    if lastX then
      local d = math.sqrt((e[1] - lastX) ^ 2 + (e[2] - lastY) ^ 2
                          + (e[3] - lastZ) ^ 2)
      if d > maxStep then maxStep = d end
    end
    lastX, lastY, lastZ = e[1], e[2], e[3]
  end
  releaseDirs()
  log(("ARC largest single-frame camera step entering the box: %.1f px")
      :format(maxStep))
  check(maxStep < 30,
        ("entering the west box arcs instead of cutting (max step %.1f)")
        :format(maxStep))
  check(MarioCam.cam.shot ~= nil, "and the walk did end inside the shot")
  shoot("shot_west_walkin")

  -- ------- 4. ATMO: Lavender breathes its own air; nobody else inherits
  game.overworld:setMap("LAVENDER_TOWN", 7, 6, "down")
  hold(150)
  local fog = Voxel3D.lastFog
  local col = Voxel3D.lastFogColor
  check(fog ~= nil and math.abs((fog and fog[3] or 0) - 0.62) < 0.01,
        "Lavender outdoors carries its authored air (strength 0.62)")
  check(col ~= nil and col[3] ~= nil and math.abs(col[3] - 0.70) < 0.01,
        "and the air is the violet the data file names")
  shoot("shot_lavender_air")
  game.overworld:setMap("POKEMON_TOWER_1F", 10, 8, "down")
  hold(120)
  check(Voxel3D.lastFog == nil, "the tower interior inherits no weather")
  game.overworld:setMap("PALLET_TOWN", 10, 9, "down")
  hold(150)
  check(Voxel3D.lastFog == nil,
        "a town without an entry keeps the placed camera's no-fog contract")

  log("")
  if #fails == 0 then log("ALL CHECKS PASSED")
  else
    log("FAILURES (" .. #fails .. "):")
    for _, f in ipairs(fails) do log("  - " .. f) end
  end
  logf:close()
  love.event.quit()
end
