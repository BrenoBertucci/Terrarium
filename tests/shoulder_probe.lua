-- Probe: the SHOULDER rung in the real game -- behind everywhere on land,
-- swinging with the player's turns, and still yielding to authored shots.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/shoulder_probe.log", "w"))
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

  MarioCam.setting:setIndex(3, game)          -- SHOULDER
  check(MarioCam.rung() == "shoulder", "index 3 is the SHOULDER rung")

  -- Teleport, then MAKE SURE the player is really standing on the asked
  -- cell before judging anything: this machine's phantom input can walk
  -- them off during any settle, and a camera judged around the wrong cell
  -- judges the wrong scene (the door-box saga, all over again).
  local function parkAt(mapId, cx, cy, face, frames)
    for _ = 1, 4 do
      game.overworld:setMap(mapId, cx, cy, face)
      hold(frames or 150)
      releaseDirs()
      local p = game.overworld.player
      if math.floor((p.px + 8) / 16) == cx
         and math.floor((p.py + 8) / 16) == cy then
        return true
      end
    end
    return false
  end

  -- the OPEN check runs on the Cycling Road: twenty cells of nothing, so
  -- the follow has no wall to legitimately deviate around. (Near buildings
  -- it deviates BY DESIGN -- the player's own visibility law outranks the
  -- perfect back view -- so a strict back-angle check belongs in the open.)
  check(parkAt("ROUTE_17", 9, 60, "up", 200), "parked on the open road")
  hold(150)
  check(MarioCam.cam.mode == "behind",
        "dry land runs the follow: mode " .. tostring(MarioCam.cam.mode))
  local vy = math.deg(MarioCam.viewYaw()) % 360
  check(math.min(vy, 360 - vy) < 15,
        ("facing up in the open, the camera stands at the back (viewYaw %.1f)")
        :format(vy))
  shoot("shoulder_idle")

  -- walk forward: the camera should stay on the back the whole way
  local worst = 0
  for i = 1, 50 do
    game.input.pressQueue[#game.input.pressQueue + 1] = "up"
    DayNight.clock = CLOCK
    coroutine.yield()
    if i > 15 then
      local p = game.overworld.player
      local fb = ({ up = 0, right = 90, down = 180, left = 270 })[p.facing] or 0
      local v = math.deg(MarioCam.viewYaw()) % 360
      local dev = math.abs(((v - fb + 180) % 360) - 180)
      if dev > worst then worst = dev end
    end
    if i == 30 then shoot("shoulder_walk") end
  end
  releaseDirs()
  check(worst < 40,
        ("walking keeps the camera near the back (worst %.1f deg off)")
        :format(worst))

  -- an authored shot still wins: the tower door
  check(parkAt("LAVENDER_TOWN", 14, 6, "down", 120), "parked on the door box")
  hold(90)
  check(MarioCam.cam.mode == "fixed" and MarioCam.cam.shot ~= nil,
        "the authored tower-door shot overrides the follow")
  shoot("shoulder_door_shot")

  MarioCam.setting:setIndex(2, game)          -- back to ON
  hold(60)
  check(MarioCam.rung() == "on", "and the rung steps back to ON")

  log("")
  if #fails == 0 then log("ALL CHECKS PASSED")
  else
    log("FAILURES (" .. #fails .. "):")
    for _, f in ipairs(fails) do log("  - " .. f) end
  end
  logf:close()
  love.event.quit()
end
