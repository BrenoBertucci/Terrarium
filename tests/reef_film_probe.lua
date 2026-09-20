-- A film of the pier and its water garden, for a recorder to capture:
-- lib/BridgeKit.lua's deck, rails and lanterns and lib/ReefKit.lua's plants,
-- in the day, under rain, and at night -- with the player surfing through
-- the lily pads twice so the physics shows.
--
-- Everything is one stretch of ROUTE_12 (the pier runs down x ~ 170 and the
-- garden lies east of it), so nothing is ever teleported while the camera is
-- rolling: a map change pops chunks in for seconds and there is no cutting
-- room afterwards.
--
-- The camera is pinned (MarioCam's own seam) and moved by hand between
-- keyframes on the REAL clock, so the film runs at the speed it is watched
-- at: POKEPORT_SPEED=1. SM64CAM goes OFF for the shoot -- not for the look
-- (the shots are authored anyway) but because a camera that can turn rotates
-- the controls (main.lua), and then "down" is not south and the surf runs
-- the wrong way through the garden.
--
-- Handshake with the recorder: this writes READY when the world is up and
-- waits for a file called GO before the first shot.
-- Settings are synced in memory, never saved by this probe.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/reef_film_probe.log", "w"))
  local function log(s) file:write(s, "\n"); file:flush() end
  local t00 = love.timer.getTime()
  local function mark(s) log(("[%6.1fs] %s"):format(love.timer.getTime() - t00, s)) end
  for _ = 1, 1800 do
    if game.overworld and game.stack and game.stack:top() == game.overworld then break end
    if game.input then game.input.pressQueue[#game.input.pressQueue + 1] = "a" end
    coroutine.yield()
  end
  if not game.overworld then log("FAIL no overworld"); file:close(); love.event.quit(); return end
  local lib = game.mods.exports.TERRARIUM.lib
  local Structures = lib.require("Structures")
  local Cam, Voxel, Day = lib.require("MarioCam"), lib.require("Voxel3D"), lib.require("DayNight")
  local Water, Weather, Wind = lib.require("Water"), lib.require("Weather"), lib.require("Wind")
  require("src.render.Pipelines").setLevel("terrarium_voxel", 4)
  lib.require("AutoFarm").setting:sync("off")
  Cam.setting:sync("off")                 -- so the controls stay compass-true
  Day.setting:sync("day")
  Weather.setting:sync("off")
  Wind.setting:sync(1)                    -- AUTO
  Water.setting:sync(1.4)                 -- SWELL
  local camera, originalCamera = nil, Cam.camera
  Cam.camera = function() return camera or originalCamera() end
  local p = game.overworld.player

  local function settle(n)
    for _ = 1, n do
      for _, d in ipairs({ "up", "down", "left", "right" }) do
        game.input.state[d] = false
        if game.input.sources then game.input.sources[d] = nil end
      end
      game.input.pressQueue = {}
      coroutine.yield()
    end
  end
  local function enter(cx, cy, surfing)
    p.surfing = surfing or false
    game.overworld:setMap("ROUTE_12", cx, cy, "down")
    for _ = 1, 2400 do
      if Structures.peek(game.overworld.map) and Voxel.lampLights then break end
      settle(1)
    end
    settle(90)
    p.surfing = surfing or false
  end
  -- A rehearsal (DS_FILM_STILLS=1) photographs the middle of every shot, so
  -- a camera standing inside the pier or under the water is found before the
  -- recorder is ever started. Off during the take: writing a PNG costs a
  -- third of a second and the film would hitch.
  local STILLS = os.getenv("DS_FILM_STILLS")
  local ONLY = os.getenv("DS_FILM_ONLY")     -- rehearse one act at a time
  local function still(name)
    if not STILLS then return end
    local pending = true
    love.graphics.captureScreenshot(function(data)
      local f = io.open(out .. "/" .. name:gsub("[^%w]+", "_") .. ".png", "wb")
      if f then f:write(data:encode("png"):getString()); f:close() end
      pending = false
    end)
    for _ = 1, 240 do if not pending then break end; coroutine.yield() end
  end
  local function cam(eye, focus, fov)
    camera = { eye = eye, focus = focus, fov = math.rad(fov or 45), curve = 0 }
  end
  local function mix(a, b, u) return a + (b - a) * u end
  -- one shot: from one framing to another, eased at both ends, on the clock
  local function shot(name, a, b, seconds, hold)
    mark(name)
    local shotMid = true
    local t0 = love.timer.getTime()
    while true do
      local u = (love.timer.getTime() - t0) / seconds
      if u > 1 then u = 1 end
      local e = u * u * (3 - 2 * u)
      cam({ mix(a[1][1], b[1][1], e), mix(a[1][2], b[1][2], e), mix(a[1][3], b[1][3], e) },
          { mix(a[2][1], b[2][1], e), mix(a[2][2], b[2][2], e), mix(a[2][3], b[2][3], e) },
          mix(a[3] or 45, b[3] or 45, e))
      if hold then game.input.state[hold] = true end
      coroutine.yield()
      if u >= 1 then break end
      if shotMid and u >= 0.5 then shotMid = false; still(name) end
    end
    if hold then game.input.state[hold] = false end
  end
  -- ...and one that follows the swimmer, a little behind and above
  -- ...and one that follows the swimmer until they are through the garden,
  -- then keeps rolling: the seconds after the pass are the ones where the
  -- lilies come drifting back, and holding the key any longer just swims the
  -- shot out of the scene (the first rehearsal ended up two towns over).
  local function follow(name, key, seconds, off, stopAt)
    mark(name)
    local t0, cx, cz, shotMid = love.timer.getTime(), nil, nil, true
    while love.timer.getTime() - t0 < seconds do
      if shotMid and love.timer.getTime() - t0 > seconds * 0.55 then
        shotMid = false
        still(name)
      end
      game.input.state[key] = (not stopAt) or p.cellY < stopAt
      local px, pz = (p.px or 0) + 8, (p.py or 0) + 8
      cx = cx and (cx + (px - cx) * 0.05) or px
      cz = cz and (cz + (pz - cz) * 0.05) or pz
      cam({ cx + off[1], off[2], cz + off[3] }, { px, -2, pz + 8 }, off[4])
      coroutine.yield()
    end
    game.input.state[key] = false
  end

  -- ------- the world, and which key swims south (before the recorder rolls)
  enter(10, 64)
  local south = nil
  for _, try in ipairs({ "down", "up", "left", "right" }) do
    enter(12, 62, true)
    local y0 = p.cellY
    for _ = 1, 40 do game.input.state[try] = true; coroutine.yield() end
    settle(20)
    if p.cellY > y0 then south = try; break end
  end
  log("south is " .. tostring(south))
  enter(10, 64)
  cam({ 250, 95, 1160 }, { 195, 0, 1045 })
  settle(60)

  -- ------- ready, and wait for the recorder
  local ready = assert(io.open(out .. "/READY", "w"))
  ready:write("ready\n"); ready:close()
  for _ = 1, 60 * 60 * 5 do
    local go = io.open(out .. "/GO", "r")
    if go then go:close(); break end
    settle(1)
  end
  t00 = love.timer.getTime()

  -- ------- ACT ONE: the pier and the garden, in the morning light
  if ONLY ~= "surf" then
  shot("wide: the pier and the garden",
       { { 250, 95, 1160 }, { 195, 0, 1045 } },
       { { 228, 58, 1112 }, { 200, -2, 1045 } }, 11)
  shot("along the deck, north",
       { { 248, 34, 1112 }, { 180, 2, 1072 } },
       { { 248, 34, 1002 }, { 180, 2, 962 } }, 11)
  shot("down onto the water garden",
       { { 252, 56, 1112 }, { 218, -6, 1040 } },
       { { 234, 24, 1078 }, { 218, -5, 1046 } }, 10)
  shot("at water level, through the pads",
       { { 158, 9, 1092 }, { 205, -2, 1046 } },
       { { 248, 9, 1092 }, { 205, -2, 1046 } }, 11)

  end
  -- ------- ACT TWO: somebody swims through it
  enter(12, 62, true)
  mark(("surf from %d,%d surfing=%s"):format(p.cellX, p.cellY, tostring(p.surfing)))
  Weather.setting:sync("rain")            -- it starts to come in over this
  follow("the surf: through the lilies", south, 14, { 58, 46, 66, 45 }, 67)

  -- ------- ACT THREE: rain
  Wind.setting:sync(4)                    -- GALE, for the reeds
  if ONLY ~= "surf" then
  enter(10, 64)
  shot("rain on the reeds and the pads",
       { { 240, 20, 1074 }, { 198, 0, 1014 } },
       { { 236, 13, 1050 }, { 200, 0, 1032 } }, 12)
  end
  enter(12, 62, true)
  mark(("surf from %d,%d surfing=%s"):format(p.cellX, p.cellY, tostring(p.surfing)))
  follow("the surf: in the rain", south, 12, { 46, 34, 56, 48 }, 67)

  -- ------- ACT FOUR: night, and the lanterns
  if ONLY == "surf" then file:close(); love.event.quit(); return end
  Day.setting:sync("night")
  Wind.setting:sync(1)
  enter(10, 64)
  shot("the lanterns on the water",
       { { 258, 38, 1096 }, { 186, 2, 1052 } },
       { { 238, 28, 1058 }, { 186, 1, 1022 } }, 12)
  shot("last light: away from the pier",
       { { 228, 58, 1112 }, { 200, -2, 1045 } },
       { { 268, 104, 1188 }, { 190, 0, 1040 } }, 12)
  settle(120)
  mark("cut")
  Weather.setting:sync("off")
  file:close()
  love.event.quit()
end
