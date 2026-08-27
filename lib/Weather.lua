-- Voxel world mode: weather.
--
-- Kanto has one sky and it never changes. This gives it showers -- rain that
-- arrives, falls for a minute or two and clears again -- and snow through the
-- winter of the clock on the wall.
--
-- ------- what a shower actually is here
--
-- Not a particle system bolted over the frame. Five things move together, and
-- the point is that they are the SAME number:
--
--   the sky      loses its colour toward a flat stratus grey, band by band,
--                so the gradient survives and an overcast horizon is still
--                paler than an overcast zenith (DayNight.overcast)
--   the light    drops and goes cool, on the same blend, on the diorama AND
--                on the flat 2D world -- one tint, two worlds, because the
--                clock already solved that problem (DayNight.tint, DayTint)
--   the sun      loses its twilight halo: a sunset behind a rain front has no
--                gold in it (DayNight.glow)
--   the water    loses its glint and gains chop -- rain breaks every crest
--                into a thousand small ones pointing everywhere, so the one
--                clean toon highlight becomes nothing (Water.wet)
--   the air      fills with rain, drawn in two registers at once (below)
--
-- One value, `power`, eased from 0 to its peak over a handful of seconds,
-- drives every one of them. That is why a shower reads as weather rather than
-- as an effect being switched on: the world darkens at exactly the rate the
-- rain thickens, because they are the same ramp.
--
-- ------- the three registers
--
-- Rain is drawn three times, and it has to be.
--
--   SHAFTS   are WORLD-SPACE: a drop with an (x, y, z) that falls through
--            the diorama and STOPS on whatever is under it -- the street,
--            a puddle, a pond, a roof. Projected through the same camera
--            as the splashes. This is the rain you can walk through, the
--            one that hits the Mart and then drips off the eave. A 2D
--            cloth over the frame cannot do any of that.
--
--   STREAKS  are SCREEN-SPACE, and now they are only the air BETWEEN the
--            camera and the near edge of the diorama -- a thin mist, not
--            the shower. Rain that close has no world position, and
--            giving it one puts it behind the trees. Kept few and dim so
--            they do not read as a sheet taped to the lens.
--
--   SPLASHES are WORLD-SPACE: cel rings that open where a shaft actually
--            landed. Water gets a crown, a roof a tick and a drip, dry
--            stone a small ring. They are what says the rain is landing
--            on THIS world rather than on the glass.
--
-- Snow is world-space only, and slower: a flake has a position in the
-- diorama, drifts down through it and lands, which is the whole reason snow
-- looks like snow. Screen-space snow is dandruff.
--
-- ------- when it snows
--
-- In the winter of the machine's own calendar, which is the same clock the
-- DAYTIME row's SYNC rung follows -- Kanto's evening falls when yours does,
-- so Kanto's winter is yours as well. See HEMISPHERE: it is one word, and it
-- is the only thing in this file that cannot be derived.
--
-- ------- and where it does not happen
--
-- Indoors, and under a canopy. A room has no sky to rain out of -- the same
-- test the sky, the sun and the hour's tint already rest on -- and Viridian
-- Forest's roof of leaves is why that map is a canopy in the first place.
-- The SOUND goes on indoors (lib/AmbientSound), because that is what a roof
-- is for.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local DayNight = V.require("DayNight")
local Water = V.require("Water")
local Wind = V.require("Wind")
local Quality = V.require("Quality")

local Map = require("src.world.Map")

local Weather = {}

-- ------- THE RENDER PASS, REACHED FOR LAZILY
--
-- Not `V.require`d at the top with the others, and the reason is a cycle:
-- Voxel3D's own header describes the order it has to be loaded in, and a
-- weather file dragging the renderer in at load time is not the place to
-- discover the rest of it. Memoised, so the pcall happens once.
--
-- Declared HERE, above everything, and that is not tidiness either. It
-- first lived down beside the rain shader -- four hundred lines BELOW
-- Weather.update, which calls it. Inside update the name was therefore a
-- global, the global was nil, and calling it threw on every single frame:
-- the tick never ran, and a probe found the shower with zero shafts and
-- zero splashes in it. A silent, total failure of the weather system,
-- caused by a local declared too far down the file.
local V3D = nil
local function voxel3D()
  if V3D == nil then
    local ok, m = pcall(V.require, "Voxel3D")
    V3D = (ok and m) or false
  end
  return V3D or nil
end

-- AUTO is first, so it is the default and what an unreadable stored value
-- falls back to (ModSetting values[1]). RAIN and SNOW are pins for a player
-- who wants the weather they want rather than the weather they are given --
-- and they are also how the feature is looked at without waiting for it.
Weather.setting = ModSetting.new("weather", "WEATHER",
                                 { "auto", "off", "rain", "snow" },
                                 { "AUTO", "OFF", "RAIN", "SNOW" })

function Weather.enabled()
  return Weather.setting:get() ~= "off"
end

function Weather.row()
  return Weather.setting:row()
end

local function game()
  return require("src.core.Game")
end

local rand = love.math.random

-- ------- the calendar
--
-- Which half of the world the machine's clock belongs to. There is no honest
-- way to derive this -- a timezone offset is a longitude, and the seasons are
-- a latitude -- so it is a constant, and it is deliberately the ONE thing in
-- this file a player might want to edit.
--
-- SOUTH is the shipped answer because the row it feeds is the one that
-- follows the machine's own clock: the winter this makes snow in is the
-- winter the player is actually standing in. Set it to "north" for Kanto's
-- own calendar (the region is Japan, and its snow falls in December).
Weather.HEMISPHERE = "south"

-- meteorological winter: the three coldest months, either way up
local WINTER = {
  north = { [12] = true, [1] = true, [2] = true },
  south = { [6] = true, [7] = true, [8] = true },
}

function Weather.isWinter()
  local ok, month = pcall(DayNight.month)
  if not ok or type(month) ~= "number" then return false end
  local set = WINTER[Weather.HEMISPHERE] or WINTER.north
  return set[month] and true or false
end

-- ------- the shower's own clock
--
-- Rain is OCCASIONAL and that word is doing work: a mod that rained half the
-- time would be a mod people switched off. The numbers below make it about
-- one minute in eight, in showers of a minute or two -- often enough that a
-- long session sees several and rare enough that arriving somewhere in the
-- rain still feels like something happened.
Weather.CLEAR_MIN, Weather.CLEAR_MAX = 300, 720     -- seconds between showers
Weather.WET_MIN, Weather.WET_MAX = 60, 170          -- seconds one lasts
-- BUILD was seven, which was fine while the only thing it governed was how
-- fast the streaks thickened -- seven seconds of that is a shower starting.
-- It is far too fast for a front you are supposed to WATCH ARRIVE. The far
-- curtain (below) is legible from about a fifth of the way up this ramp, so
-- the length of this number is literally how long you get to stand there and
-- see grey close in before it is on you. Twenty seconds is most of a minute
-- of approach with the curtain leading, and still lands well inside the
-- sixty-second floor on a wet spell (WET_MIN).
Weather.BUILD = 20                                  -- seconds to reach peak
Weather.CLEAR_FADE = 14                             -- seconds to fall away

-- How hard it can come down. The low end is a drizzle worth noticing, the
-- high end is the one that brings thunder (see STRIKE_ABOVE).
Weather.PEAK_MIN, Weather.PEAK_MAX = 0.45, 1.0

local state = {
  kind = nil,       -- what is falling, or nil
  power = 0,        -- 0..1, eased -- the number everything else reads
  target = 0,       -- where power is heading
  timer = 0,        -- seconds left in the current spell
  mode = nil,       -- the row's value the spell above was decided under
}

-- The AUTO roll, one of a pair: a dry spell and a wet one, each ending by
-- rolling the other.
local function rollClear()
  state.kind, state.target = nil, 0
  state.timer = Weather.CLEAR_MIN
                + rand() * (Weather.CLEAR_MAX - Weather.CLEAR_MIN)
end

local function rollWet()
  state.kind = Weather.isWinter() and "snow" or "rain"
  state.target = Weather.PEAK_MIN
                 + rand() * (Weather.PEAK_MAX - Weather.PEAK_MIN)
  state.timer = Weather.WET_MIN + rand() * (Weather.WET_MAX - Weather.WET_MIN)
end

-- ------- lightning
--
-- The FLASH comes first and the THUNDER follows it, by a delay that stands
-- for distance. AmbientSound polls `thunderDue` for the rumble.
--
-- A strike lives in the SKY. The first version planted the bolt one to
-- four cells off the player and painted a white plate over the whole
-- frame, which is why it read as a 2D sticker in your face: the camera
-- looks AT the player, so a zigzag at their feet fills the canvas. Now
-- the default is a cloud-to-cloud sheet, high and past the player into
-- the horizon half of the view. Cloud-to-ground is the rare far one,
-- still many cells out. The sky shader takes the flash (a cel lift of
-- the deck); the overlay draws thin world-space strokes, not a chain of
-- squares and not a full-screen whiteout.
Weather.STRIKE_ABOVE = 0.78
Weather.STRIKE_EVERY_MIN = 10
Weather.STRIKE_EVERY_MAX = 38
Weather.FLASH_LEN = 0.48
-- How close a bolt is allowed to land, in cells. Anything under this
-- stands between the camera and the player and becomes the sticker.
Weather.BOLT_MIN_CELLS = 9
Weather.BOLT_MAX_CELLS = 22
-- Cloud deck the sheet lives in (world px). Roofs top out around 28;
-- 110+ is above the diorama proper and projects into the sky rectangle.
Weather.BOLT_SHEET_Y = 124
Weather.BOLT_SHEET_SPAN = 36

-- After a rain shower clears: rainbow + saturated sky for a short spell of
-- absolute (wall-clock) time, then gone with no residual flag left behind.
Weather.AFTER_RAIN = 180

-- Cloud base / tip height in world pixels (same units as grass height).
Weather.BOLT_TOP = 96
Weather.BOLT_TOP_FAR = 110
Weather.BOLT_GROUND = 1.2

-- strike.bolt: world polyline + forks + sparks. nil when idle.
-- far 0 = near/overhead, 1 = distant horizon strike.
local strike = {
  at = 1e9, next = 20, pending = false, far = 0,
  bolt = nil, sparks = nil,
}

local after = { untilAbs = 0, hadRain = false }

local function absNow()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return 0
end

local function playerXZ()
  local Game = game()
  local ow = Game and Game.overworld
  local p = ow and ow.player
  if not p then return 0, 0 end
  local px = p.px or ((p.cellX or 0) * 16)
  local pz = p.py or ((p.cellY or 0) * 16)
  return px + 8, pz + 8
end

-- Camera look on XZ: from the eye toward the focus, which is INTO the
-- scene and toward the sky rectangle. A bolt between eye and player sits
-- on the lens; a bolt past the player sits in the sky.
local function lookXZ()
  local ok, V3 = pcall(V.require, "Voxel3D")
  local eye = ok and V3 and V3.eye
  local focus = ok and V3 and V3.focus
  if type(eye) == "table" and type(focus) == "table" then
    local dx = (focus[1] or 0) - (eye[1] or 0)
    local dz = (focus[3] or 0) - (eye[3] or 0)
    local len = math.sqrt(dx * dx + dz * dz)
    if len > 1 then return dx / len, dz / len end
  end
  return 0, -1
end

-- Broken polyline from A to B. `keepUp` refuses to drop below minY, which
-- is what keeps a sheet from wandering down into the street.
local function chainTo(x0, y0, z0, x1, y1, z1, steps, wander, minY)
  local pts = { { x0, y0, z0 } }
  steps = math.max(3, steps or 8)
  wander = wander or 18
  for i = 1, steps - 1 do
    local t = i / steps
    local j = wander * (0.4 + 0.6 * math.sin(t * 3.1))
    local x = x0 + (x1 - x0) * t + (rand() - 0.5) * 2 * j
    local y = y0 + (y1 - y0) * t + (rand() - 0.5) * j * 0.45
    local z = z0 + (z1 - z0) * t + (rand() - 0.5) * 2 * j
    if minY and y < minY then y = minY + rand() * 6 end
    pts[#pts + 1] = { x, y, z }
  end
  pts[#pts + 1] = { x1, y1, z1 }
  return pts
end

local function skyForks(main, minY)
  local forks = {}
  if not main or #main < 4 then return forks end
  local n = 2 + rand(0, 3)
  for _ = 1, n do
    local root = main[2 + rand(0, math.max(0, #main - 4))]
    if not root then break end
    local fx, fy, fz = root[1], root[2], root[3]
    local fork = { { fx, fy, fz } }
    local ang = rand() * 6.2831853
    local steps = 2 + rand(0, 3)
    for _ = 1, steps do
      fy = fy + (rand() - 0.65) * 10
      if minY and fy < minY then fy = minY + rand() * 4 end
      fx = fx + math.cos(ang) * (8 + rand() * 14)
      fz = fz + math.sin(ang) * (8 + rand() * 14)
      ang = ang + (rand() - 0.5) * 1.4
      fork[#fork + 1] = { fx, fy, fz }
    end
    if #fork >= 2 then forks[#forks + 1] = fork end
  end
  return forks
end

-- World-space bolt. Default is a SHEET in the cloud deck, past the player
-- toward the horizon. Ground strikes are the far minority and still sit
-- many cells out -- never in the camera-player corridor.
local function genBoltWorld(far, px, pz)
  far = tonumber(far) or 0.7
  if far < 0 then far = 0 elseif far > 1 then far = 1 end
  px, pz = px or 0, pz or 0

  local lx, lz = lookXZ()
  local sx, sz = lz, -lx
  local cells = Weather.BOLT_MIN_CELLS
                + far * (Weather.BOLT_MAX_CELLS - Weather.BOLT_MIN_CELLS)
                + rand() * 3
  local side = (rand() - 0.5) * (7 + far * 8) * 16
  local cx = px + lx * cells * 16 + sx * side
  local cz = pz + lz * cells * 16 + sz * side

  -- Sheet unless this is a deliberately close probe AND a coin says ground.
  -- Auto weather always passes far >= 0.5, so it almost never grounds.
  local sheet = far >= 0.32 or rand() < 0.7
  local yDeck = Weather.BOLT_SHEET_Y + far * 18 + rand() * Weather.BOLT_SHEET_SPAN

  if sheet then
    local span = (5 + far * 7 + rand() * 4) * 16
    local ang = rand() * 6.2831853
    local x1 = cx + math.cos(ang) * span
    local z1 = cz + math.sin(ang) * span
    local y1 = yDeck + (rand() - 0.5) * 22
    local minY = Weather.BOLT_SHEET_Y - 18
    local main = chainTo(cx, yDeck, cz, x1, y1, z1, 7 + rand(0, 3), 22, minY)
    local channels = { main }
    if rand() < 0.45 then
      channels[#channels + 1] = chainTo(
        cx + (rand() - 0.5) * 18, yDeck + (rand() - 0.5) * 10, cz + (rand() - 0.5) * 18,
        x1 + (rand() - 0.5) * 24, y1 + (rand() - 0.5) * 10, z1 + (rand() - 0.5) * 24,
        6, 16, minY)
    end
    return {
      kind = "sheet",
      channels = channels,
      forks = skyForks(main, minY),
      sparks = {},
      beads = {},
      ground = nil,
      cloud = { cx, yDeck, cz },
      far = far,
    }
  end

  -- Distant cloud-to-ground: still past the player, still starting in
  -- the deck. Thin, few forks, a handful of sparks at the far impact.
  local topY = yDeck + 8
  local gx = cx + (rand() - 0.5) * 28
  local gz = cz + (rand() - 0.5) * 28
  local main = chainTo(cx, topY, cz, gx, Weather.BOLT_GROUND, gz,
                       9 + rand(0, 3), 14, nil)
  local sparks = {}
  for _ = 1, 5 + rand(0, 4) do
    local a = rand() * 6.2831853
    local sp = 12 + rand() * 28
    sparks[#sparks + 1] = {
      x = gx, y = 1.2, z = gz,
      vx = math.cos(a) * sp, vy = 12 + rand() * 22, vz = math.sin(a) * sp,
      t = 0, ttl = 0.14 + rand() * 0.16, size = 0.45 + rand() * 0.4,
    }
  end
  return {
    kind = "ground",
    channels = { main },
    forks = skyForks(main, 40),
    sparks = sparks,
    beads = {},
    ground = { gx, Weather.BOLT_GROUND, gz },
    cloud = { cx, topY, cz },
    far = far,
  }
end

local function armStrike(far)
  local f = tonumber(far)
  -- unset far used to be a flat rand(), which planted half the bolts
  -- in the player's lap. The open sky is the default now.
  if f == nil then f = 0.55 + rand() * 0.45 end
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  local px, pz = playerXZ()
  strike.at, strike.pending, strike.far = 0, true, f
  strike.bolt = genBoltWorld(f, px, pz)
end

local function flashRaw()
  local t = strike.at
  if t >= Weather.FLASH_LEN then
    if strike.bolt and t > Weather.FLASH_LEN + 0.08 then
      strike.bolt = nil
    end
    return 0
  end
  local farScale = 0.50 + 0.50 * (1 - strike.far)
  local shape = 0
  if t < 0.035 then
    shape = 0.75 + 0.25 * (1 - t / 0.035)
  elseif t < 0.070 then
    shape = 0.08
  elseif t < 0.130 then
    shape = 1.0
  elseif t < 0.175 then
    shape = 0.12
  elseif t < 0.240 then
    shape = 0.70
  elseif t < 0.300 then
    shape = 0.10
  else
    local u = (t - 0.300) / math.max(0.001, Weather.FLASH_LEN - 0.300)
    shape = (1 - u) * 0.35
  end
  return shape * farScale
end

function Weather.flash()
  local cont = flashRaw()
  if cont < 0.14 then return 0 end
  if cont < 0.55 then return 0.5 end
  return 1
end

function Weather.thunderDue()
  if not strike.pending then return nil end
  local delay = 0.15 + strike.far * 2.4
  if strike.at < delay then return nil end
  strike.pending = false
  return strike.far
end

function Weather.storming()
  local kind, power = Weather.visible()
  return kind == "rain" and (power or 0) >= Weather.STRIKE_ABOVE
end

function Weather.afterRain()
  local u = after.untilAbs
  if not u or u <= 0 then return 0 end
  local left = u - absNow()
  if left <= 0 then
    after.untilAbs = 0
    return 0
  end
  local n = left / Weather.AFTER_RAIN
  if n > 1 then n = 1 end
  return n
end

function Weather.forceStrike(far)
  armStrike(far ~= nil and far or 0.35)
end

function Weather.armAfterRain(seconds)
  local s = tonumber(seconds) or Weather.AFTER_RAIN
  if s < 0 then s = 0 end
  after.untilAbs = absNow() + s
end

function Weather.thunderDelay(far)
  local f = far
  if f == nil then f = strike.far end
  f = tonumber(f) or 0
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  return 0.15 + f * 2.4
end

-- Step ground sparks every weather tick (called from update path via paint).
local function stepSparks(dt)
  local bolt = strike.bolt
  if not bolt or not bolt.sparks then return end
  for i = #bolt.sparks, 1, -1 do
    local s = bolt.sparks[i]
    s.t = s.t + dt
    s.x = s.x + s.vx * dt
    s.y = s.y + s.vy * dt
    s.z = s.z + s.vz * dt
    s.vy = s.vy - 120 * dt
    s.vx = s.vx * (1 - 2.5 * dt)
    s.vz = s.vz * (1 - 2.5 * dt)
    if s.y < 0.3 then s.y = 0.3; s.vy = s.vy * -0.2 end
    if s.t >= s.ttl then table.remove(bolt.sparks, i) end
  end
end

-- Draw a world-space polyline as STROKES, not a chain of squares. A
-- rectangle-per-pixel bolt is what made the last one look like UI. Segments
-- that project too close (between camera and player) are dropped -- those
-- are the ones that filled the frame.
Weather.BOLT_PS_CAP = 1.45

local function drawWorldChain(g, project, scale, pts, thickMul, r, gv, b, a)
  if not pts or #pts < 2 or a < 0.02 then return end
  local prev = g.getLineWidth and g.getLineWidth() or 1
  g.setColor(r, gv, b, a)
  for i = 1, #pts - 1 do
    local p0, p1 = pts[i], pts[i + 1]
    local sx0, sy0, ps0 = project(p0[1], p0[2], p0[3])
    local sx1, sy1, ps1 = project(p1[1], p1[2], p1[3])
    if sx0 and sx1 then
      local ps = ((ps0 or 1) + (ps1 or 1)) * 0.5
      if ps < Weather.BOLT_PS_CAP then
        local thick = math.max(1, (scale or 1) * math.max(0.4, ps) * 0.7
                                 * (thickMul or 1))
        if g.setLineWidth then g.setLineWidth(thick) end
        g.line(sx0, sy0, sx1, sy1)
      end
    end
  end
  if g.setLineWidth then g.setLineWidth(prev) end
end

-- Sky flash only. A full-frame plate is what made a distant strike feel
-- like a bomb in the player's face. Bands stay in the top of the canvas
-- (the sky rectangle) and a small hotspot sits on the cloud that threw it.
local function paintSkyFlash(g, project, w, h, lit, bolt)
  if not (lit and lit > 0 and w and h) then return end
  g.setBlendMode("add")
  local far = strike.far or 0.7
  -- farther = more of the flash is "in the sky", none of it on the grass
  local plate = (lit >= 1 and 0.14 or 0.06) * (0.50 + 0.50 * far)
  local reach = h * (0.38 + 0.14 * far)
  local bands = 6
  for i = 0, bands - 1 do
    local y0 = reach * (i / bands)
    local hh = reach / bands + 1
    local a = plate * ((1 - i / bands) ^ 1.7)
    g.setColor(0.52, 0.60, 0.96, a)
    g.rectangle("fill", 0, y0, w, hh)
  end
  if bolt and bolt.cloud and project then
    local sx, sy, ps = project(bolt.cloud[1], bolt.cloud[2], bolt.cloud[3])
    if sx and sy and sy < h * 0.58 and (ps or 1) < Weather.BOLT_PS_CAP then
      local amp = (lit >= 1 and 0.20 or 0.09) * (0.6 + 0.4 * far)
      for k = 3, 1, -1 do
        local rw = (28 + far * 18) * k
        local rh = (16 + far * 10) * k
        g.setColor(0.72, 0.82, 1.0, amp / k)
        g.rectangle("fill", sx - rw, sy - rh * 0.55, rw * 2, rh)
      end
    end
  end
end

-- Soft plate for the flat 2D path (no camera, no bolt). Still sky-only.
local function paintPlate(g, w, h, lit)
  paintSkyFlash(g, nil, w, h, lit, nil)
end

-- World-space bolt through the camera. `project` is Voxel3D.project.
local function paintStrike3D(project, scale, lit, w, h)
  if not (lit and lit > 0) then return end
  local g = love.graphics
  local bolt = strike.bolt
  if w and h then paintSkyFlash(g, project, w, h, lit, bolt) end

  if not bolt or not project then return end
  local raw = flashRaw()
  if raw < 0.10 then return end
  if lit < 0.5 and raw < 0.40 then return end

  -- Sheet lightning is a sky event: keep it bright but not a white wall.
  -- Ground strikes (the rare far ones) can be a touch hotter.
  local sky = bolt.kind ~= "ground"
  local amp = raw * (sky and 0.72 or 0.88)
  local scl = scale or 1
  g.setBlendMode("add")

  for _, ch in ipairs(bolt.channels or {}) do
    drawWorldChain(g, project, scl, ch, 2.4, 0.35, 0.48, 0.98, 0.22 * amp)
    drawWorldChain(g, project, scl, ch, 1.15, 0.72, 0.84, 1.00, 0.50 * amp)
    drawWorldChain(g, project, scl, ch, 0.55, 1.00, 1.00, 1.00, 0.95 * amp)
  end
  for _, fk in ipairs(bolt.forks or {}) do
    drawWorldChain(g, project, scl, fk, 1.4, 0.40, 0.55, 1.00, 0.28 * amp)
    drawWorldChain(g, project, scl, fk, 0.5, 0.95, 0.97, 1.00, 0.75 * amp)
  end

  if bolt.kind == "ground" then
    local gr = bolt.ground
    if gr then
      local sx, sy, ps = project(gr[1], gr[2], gr[3])
      if sx and (ps or 1) < Weather.BOLT_PS_CAP then
        local d = math.max(1.5, scl * (ps or 1) * 2.0)
        g.setColor(0.60, 0.75, 1.0, 0.28 * amp)
        g.rectangle("fill", sx - d * 1.4, sy - d * 0.4, d * 2.8, d * 0.8)
        g.setColor(1, 1, 1, 0.55 * amp)
        g.rectangle("fill", sx - d * 0.35, sy - d * 0.35, d * 0.7, d * 0.7)
      end
    end
    for _, s in ipairs(bolt.sparks or {}) do
      local k = 1 - s.t / s.ttl
      if k > 0 then
        local sx, sy, ps = project(s.x, s.y, s.z)
        if sx and (ps or 1) < Weather.BOLT_PS_CAP then
          local d = math.max(1, scl * (ps or 1) * s.size * (0.5 + k))
          g.setColor(0.75, 0.88, 1.0, 0.45 * amp * k)
          g.rectangle("fill", sx - d, sy - d, d * 2, d * 2)
        end
      end
    end
  end
end

-- ------- what the rest of the mod asks
--
-- Whether this map can have weather ON it. The same Map.isOutdoor test the
-- sky, the sun and the hour's tint already rest on, plus the canopy: a forest
-- floor gets night falling on it (DayNight says so) but not rain landing on
-- it, because the leaves are the roof that map is named for.
--
-- Declared HERE, above its callers, rather than beside the tick that first
-- needed it: a Lua closure captures the locals in scope where it is written,
-- so a `local function` further down the file is a nil global to everything
-- above it -- silently, until the first call.
local function openSky(map)
  if not (map and map.def) then return false end
  if not Map.isOutdoor(map.def) then return false end
  return not DayNight.isCanopy(map)
end

-- `falling` is the one question everything outside this file has: what is
-- coming down, and how hard. nil kind means nothing is.
function Weather.falling()
  if state.power <= 0.005 then return nil, 0 end
  return state.kind, state.power
end

function Weather.power()
  return state.power
end

-- ------- and what should be DRAWN, which is a different question
--
-- `falling` answers "what is the weather doing in Kanto", and indoors that
-- answer is still "raining" -- which is exactly right for the sound, because
-- you can hear it on the roof. It is exactly wrong for the picture: a room
-- has no sky to rain out of.
--
-- Those two being the same function was a bug and a visible one. The tick
-- below drops every splash and every streak the moment the sky closes over,
-- but the DRAW re-filled the streak field from scratch on the very next frame
-- (that is what stepDrops does when the list is short), so rain went on
-- falling through the ceiling of every house you walked into. Clearing the
-- list was never going to be enough while the thing that refills it did not
-- know it was indoors.
--
-- So this is the question every DRAW path asks, and there is only one of it.
function Weather.visible()
  local kind, power = Weather.falling()
  if not kind then return nil, 0 end
  local Game = game()
  local ow = Game and Game.overworld
  if not openSky(ow and ow.map) then return nil, 0 end
  return kind, power
end

-- ------- the far curtain
--
-- The wall of rain you can see standing on the horizon before you are in it,
-- painted by lib/Sky.lua up in the sky rectangle.
--
-- It is NOT a forecast. Nothing in this file knows the future, and building a
-- lookahead would have meant leaking the next spell's roll to every reader
-- for one picture's sake. It is the SAME shower, drawn where a shower is the
-- only place it is ever visible AS a shower -- from far enough away to see
-- the shape of it -- and it reads as *coming* because it LEADS the near
-- field: a curtain is legible at a power where the streaks are still a drop
-- here and there, so it fills in over the first fifth of the ramp and the
-- streaks arrive after it. That ordering is the whole effect. With BUILD at
-- twenty seconds it buys the better part of a minute of watching.
--
-- Rides `visible` rather than `falling`, because a curtain is a picture and a
-- picture needs a sky to be in (see the header on Weather.visible).
Weather.CURTAIN_IN = 0.02       -- power at which the far wall first shows
Weather.CURTAIN_FULL = 0.34     -- and where it is drawn in full

function Weather.curtain()
  local kind, power = Weather.visible()
  if not kind then return 0 end
  local a = ((power or 0) - Weather.CURTAIN_IN)
            / (Weather.CURTAIN_FULL - Weather.CURTAIN_IN)
  if a <= 0 then return 0 end
  if a > 1 then a = 1 end
  -- snow gets a thinner one: a squall coming in reads as the horizon going
  -- soft, not as shafts -- shafts are what falling water does and snow does
  -- not fall in lines
  if kind == "snow" then a = a * 0.55 end
  return a
end

-- ------- particles
--
-- Screen-space streaks, world-space shafts, and world-space splashes /
-- flakes. Caps keep every loop short on the UHD this was written for.
local drops = {}                    -- screen-space near-camera mist
local shafts = {}                   -- world-space falling rain
local motes = {}                    -- world-space splashes, drips, flakes

-- Screen-space mist only. Used to be the whole shower (52 / 360) and that
-- is why it read as a cloth on the lens. The shafts do the work now; these
-- are the drops between the camera and the near edge, kept few and dim.
Weather.STREAKS = 44
Weather.STREAKS_MAX = 190
-- World-space shafts at full power, around the player. Quality.scale cuts
-- this the same way it cuts WindFX -- 1/4 RES cannot afford a hundred
-- extra projections.
-- Raised once the field became ONE draw call instead of one per drop.
-- Thin rain is most of what made this look fake -- a shower is a texture
-- of many faint streaks, and at eighty-eight you can count them. The old
-- numbers were rationing draw calls, not fill rate.
-- ------- THE COUNTS, OFF THE LEASH
--
-- These used to be rationed against a two-core laptop, and the rationing
-- was visible: thin rain is most of what makes a shower look fake, and
-- every one of these numbers was set by what could be AFFORDED rather
-- than by what a downpour looks like.
--
-- The whole field is one mesh and one draw call, so what these actually
-- cost is a table per drop, a projection per drop, and fill rate. The
-- QUALITY row still cuts them for anyone who needs it cut (shaftBudget
-- below), which is the right place for that decision -- not baked into
-- the ceiling so that nobody can ever have the downpour.
Weather.SHAFTS = 440
Weather.SHAFTS_MAX = 780
Weather.SHAFT_FALL = 102            -- world px / s, a mid-sized drop
-- ------- a streak is a length of TIME
--
-- How long the eye holds a moving highlight. Multiply by the drop's own
-- fall speed and you get the streak: a fast drop draws a long one and a
-- slow drop a short one, out of the same number, which is what stretch-to-
-- velocity means when it is done at the source instead of clamped on at
-- draw time.
--
-- Set so a drop at the reference speed above draws the sixteen world
-- pixels the fixed SHAFT_LEN used to hand every drop in the world.
Weather.SHAFT_SMEAR = 0.165         -- seconds
Weather.SHAFT_LEN = 16              -- legacy: the flat length every shaft
                                    -- used to get, kept as the reference
                                    -- SHAFT_SMEAR above is calibrated to
-- Legacy. The world shafts no longer lean by a constant -- they lean
-- because their own sideways velocity says so (see drawShafts), which is
-- the only way a fine drop and a heavy one can slant differently in the
-- same gust. Kept because probes written against the old field read it.
Weather.LEAN = 0.20
Weather.SHAFT_REACH = 9             -- cells around the player
-- Splashes are mostly spawned by a shaft hitting something. A small
-- ambient floor stays so a street still ticks when the shafts are sparse.
-- Raised from 170 when the ink stamps arrived (below): a stamp outlives
-- its ring by INK_LINGER, so a mote now holds its slot in this budget for
-- about three times as long, and the old ceiling starved the SPAWNS to a
-- third without anyone deciding that.
Weather.SPLASHES = 300
Weather.SPLASH_FLOOR = 40
Weather.FLAKES = 280

-- ------- THE INK, because the street is white
--
-- Every impact below is ADDITIVE light, and additive light is the correct
-- physics for water -- and completely illegible on exactly the surfaces
-- the player is standing on. Pallet's paving is nearly white at noon; a
-- faint white ring ADDED to it is arithmetic that goes nowhere. Measured
-- off a pinned downpour (tests/rain_interact_probe.lua): a hundred and
-- sixty splashes alive in the frame and the street reads bone dry.
--
-- What rain actually does to dry ground is DARKEN it where it lands, and
-- what this art style does with darkness is draw it as ink -- the same
-- lesson the battle overlay already paid for: on a bright ground you draw
-- with ink, not with light. So every landing now has two halves:
--
--   the INK    a small dark stamp under the impact, alpha-blended, that
--              pops in with the hit and dries out over INK_LINGER times
--              the ring's own life. It is the "the ground got hit" of the
--              picture, and it is what survives a pale street.
--
--   the LIGHT  the crown / shards / rings above, additive, unchanged --
--              water catching the sky. On dark ground and at night this
--              half does the work and the ink quietly vanishes.
--
-- On WATER and in a puddle nothing darkens (water cannot get wetter);
-- those get a dark RIM under the expanding crest instead -- the two-tone
-- ring every cel-shaded ripple is drawn with.
--
-- The ink's own alpha is scaled by the hour's brightness (rainLight): at
-- night the ground is already dark and stamping ink on it is mud.
Weather.INK = { 0.07, 0.10, 0.16 }  -- wet ground, as this palette's dark
Weather.INK_A = 0.34                -- stamp alpha at full day, full power
Weather.INK_RIM_A = 0.5             -- water ring's dark half
-- Stamp life, in ring lifetimes. Priced before being chosen
-- (tests/rain_cost_probe.lua): the lingering stamps are most of the live
-- mote population at peak -- ~680 motes for 300 bursts at 2.6 -- and every
-- tenth of this number is a slice of that projection loop on the machines
-- the QUALITY row exists for.
Weather.INK_LINGER = 2.2
-- a stamp is a blob, not a circle: six chords disappear at these sizes,
-- and the default segment count is fill rate spent on nothing
Weather.INK_SEGS = 6

Weather.FALL = 820                  -- base fall speed, canvas px/second
Weather.SLANT = 0.16                -- lean before wind (wind adds on top)
-- Stretch-to-velocity: streak length scales with fall speed (Unity stretch
-- billboard analogue). Cap keeps a gale from drawing metre-long needles.
Weather.STRETCH = 0.055
Weather.STRETCH_MIN = 0.55
Weather.STRETCH_MAX = 2.4
-- Lateral turbulence (noise force) as a fraction of fall speed.
Weather.TURB = 0.045
-- Layer mix of the particle field (must sum ~1). Far is densest: depth cue.
Weather.LAYER_FAR  = 0.48
Weather.LAYER_MID  = 0.34
Weather.LAYER_NEAR = 0.18

-- The rain's own palette: two flat pale blues and a white, all on the 5-bit
-- lattice the rest of the mod's colour lives on. No gradients anywhere in
-- here -- a soft-edged raindrop over a cel-shaded diorama is the one thing
-- that would make the world look like a photograph with a filter on it.
Weather.RAIN_NEAR = { 0.86, 0.92, 1.00 }
Weather.RAIN_MID  = { 0.70, 0.80, 0.94 }
Weather.RAIN_FAR  = { 0.50, 0.62, 0.82 }
Weather.RAIN_CORE = { 0.96, 0.98, 1.00 }   -- bright tip on near streaks
-- The streak's alpha at each end, as a share of the drop's own. Additive,
-- so these are far below the opaque draw's: a shower is hundreds of faint
-- highlights, and a drop bright enough to read on its own is a scratch.
-- The tail is not zero on purpose -- a trail that vanishes completely
-- makes the head look like a floating dash.
-- The widest a world streak may be drawn, in render-scale units. See the
-- thickness block in drawShafts for what this is protecting against.
-- Measured against the reference art rather than guessed: a streak there
-- is two or three pixels of core on a twelve-hundred-pixel frame. At this
-- render size that is about three, and the cap is what holds a near drop
-- to it -- perspective alone would take it to a dozen.
Weather.THICK_CAP = 0.95

Weather.ADD_HEAD = 0.62
Weather.ADD_TAIL = 0.05
Weather.SPLASH = { 0.85, 0.92, 1.00 }
Weather.SNOW = { 0.97, 0.98, 1.00 }

-- ------- A DROP HAS A SIZE, AND EVERYTHING ELSE IS A CONSEQUENCE
--
-- What was here gave every shaft its fall speed, its length, its width and
-- its brightness from the depth LAYER it was sorted into -- three buckets,
-- three sets of constants. That is a fine way to fake distance and a poor
-- way to make water, because in the world none of those four numbers is
-- free: they are all downstream of one thing, how big the drop is.
--
-- Rain is not one drop size. A shower is a whole distribution of them,
-- mostly fine with a scatter of fat ones, and the visible texture of rain
-- IS that distribution -- the few heavy drops falling fast and near
-- vertical, the haze of fine ones drifting sideways behind them. Sorting a
-- field into three fixed speeds cannot produce it: you get three combs.
--
-- So a shaft rolls a SIZE, and:
--
--   its SPEED is the terminal velocity of that size, on the curve below
--   its LEAN is not set at all -- it falls out of the speed (see stepShafts)
--   its LENGTH is how far it travels while the eye integrates, i.e. speed
--   its WEIGHT on screen -- width and brightness -- is the size again
--
-- Which means one roll, and the field sorts ITSELF into what reads as
-- depth without anybody assigning depth.
--
-- Biased toward the fine end: the exponent is what stops the roll from
-- being a uniform spread of sizes, which real rain never is (Marshall and
-- Palmer measured an exponential, and the far tail is where the fat drops
-- live). A flat roll gives a shower made half of heavy drops, which reads
-- as hail.
-- ------- and the four rains
--
-- The size distribution is not a constant, it is a function of how hard it
-- is raining -- so these come in pairs: what the roll looks like at the
-- faint edge of a shower, and what it looks like at the peak of one.
--
--   DRIZZLE     a hard small bias and a low floor. Almost nothing but fine
--               rain, falling slowly, leaning a long way in any wind.
--   CLOUDBURST  a nearly flat roll off a raised floor. The fat drops
--               arrive, fall fast, lean hardly at all, and land heavily.
--
-- Everything downstream -- speed, streak length, width, brightness, how
-- big a crown it throws, how much it is pushed by a gust -- already comes
-- out of the size, so moving the distribution moves the whole character of
-- the weather and nothing has to be told about it twice.
Weather.DROP_MIN = 0.10
Weather.DROP_MIN_WET = 0.26
Weather.DROP_MAX = 1.00
Weather.DROP_BIAS = 2.7           -- drizzle: >1 rolls small, fat drops rare
Weather.DROP_BIAS_WET = 1.15      -- cloudburst: nearly a flat roll
-- Filled once a frame by the tick from the shower's own power, so a
-- spawning drop does not have to go and ask.
Weather.dropPower = 1

-- ------- terminal velocity, in miniature
--
-- The real curve (Gunn and Kinzer) rises steeply for fine drops and then
-- flattens: drag grows with the SQUARE of the radius while weight grows
-- with the CUBE, so a drop twice as wide is nowhere near twice as fast,
-- and past about four millimetres it stops gaining at all. That shape is
-- the whole point. A linear size-to-speed map -- which is what "big drops
-- fall faster" turns into if you write it straight -- gives a field whose
-- fastest drop is six times its slowest, and that does not look like rain,
-- it looks like a screensaver.
--
-- Returned as a MULTIPLIER on Weather.SHAFT_FALL so the shower's overall
-- pace stays one number a person can turn.
-- Scaled so the AVERAGE drop in the roll above falls at roughly the pace
-- the shipped field's average drop did (about 0.95 of SHAFT_FALL). That
-- calibration is not cosmetic: a distribution whose mean sits below the
-- old constant is a shower that got quietly slower, thinner and less
-- often-landing everywhere at once, and every one of those reads as the
-- rain having been turned down rather than made of drops.
local function terminal(d)
  return 0.349 + 1.106 * (1 - math.exp(-2.2 * d))
end

-- ------- how long a drop takes to notice the wind
--
-- This is the number that makes a gust look like a gust, and it is the one
-- thing a per-particle sine can never produce.
--
-- A drop does not travel WITH the air, it travels TOWARD it: pushed by
-- drag until its own sideways speed matches the air's, and the time that
-- takes goes with its mass over its drag -- so, with its terminal
-- velocity. A fine drop matches the air almost at once. A fat one takes
-- most of a second, and crosses the gust still going roughly where it was
-- already going.
--
-- Stand in a squall and that is exactly what you see: the front arrives
-- and the fine rain veers first, in a sheet, while the heavy drops keep
-- coming straight down through it. The rain SORTS ITSELF, and the sorting
-- is the picture. Give every drop the same response and the whole field
-- swings together like a curtain on a rail.
Weather.DRAG_MIN = 0.07           -- seconds, the finest drop
Weather.DRAG_SPAN = 0.62          -- added across the size range

-- ------- and where a shaft stops being drawn
--
-- The reach used to end in a wall: past it a shaft was deleted and
-- respawned overhead at full brightness. Every one of those is a raindrop
-- blinking out and another blinking in, at a fixed radius around a player
-- who is walking -- so the far edge of the shower was a ring of popping
-- that travelled with you.
--
-- Now the last stretch of the reach is a fade, and a shaft that leaves has
-- been invisible for a while by the time it goes. Same for the first
-- moments of its life, which is what stops the respawn being a flash.
-- Both of these are small, and they are small because of how SHORT a
-- shaft's life is. It is spawned twenty to eighty pixels up and falls at
-- around a hundred a second, so it exists for about half a second -- which
-- means a fade-in of a fifth of a second is spent on nearly half of every
-- drop in the world, and the field loses a fifth of its brightness to a
-- transition nobody asked to see. The first pass at these numbers cost the
-- shower forty per cent of its ink; the screenshot measured it.
--
-- The edge band has the same trap in two dimensions: a band 30% deep on
-- each side of a square reach is HALF its area, so most of the rain was
-- standing in the fade rather than passing through it.
Weather.FADE_EDGE = 0.14          -- share of the reach spent fading out
Weather.FADE_IN = 0.06            -- seconds a fresh shaft spends arriving

-- ------- rain is not white
--
-- Water is clear. You see rain because it CATCHES light and throws a
-- little of it back, which means a streak is the colour of whatever is
-- lighting it and never a colour of its own. The palette above is rain at
-- NOON. Painting it unchanged at midnight is what makes a night shower
-- read as white scratches ruled over a dark picture -- the brightest thing
-- in a frame lit by a moon.
--
-- So it is multiplied by the hour's own light: the same value the diorama
-- and the flat world are already tinted by, which is the rule this mod
-- follows everywhere else -- one clock, one tint, every surface. A dusk
-- shower goes warm because the sky it is falling out of is warm. A deep
-- night one nearly vanishes, which is what rain at night actually does,
-- and it is the reason the lamps below are worth the arithmetic.
--
-- Never fully dark: a floor stays, because rain nobody can see at all is
-- indistinguishable from a bug.
Weather.LIGHT_FLOOR = 0.34

-- ------- THE LAMPS ARE WHERE NIGHT RAIN LIVES
--
-- After dark the only place anybody has actually SEEN rain is in the cone
-- under a street lamp. That is not a stylistic choice, it is how the eye
-- works: drops are lit by whatever reaches them, and at night the only
-- thing reaching them is the gas.
--
-- The nearest few posts are asked for ONCE a frame and every shaft is
-- scored against them. A couple of hundred squared distances is nothing
-- beside the projection each shaft already pays for, and it buys the one
-- night-weather image worth having.
Weather.LAMP_LIFT = 1.45          -- brightness multiplier at a lamp's core
Weather.LAMP_REACH = 1.35         -- of the lamp's own radius
Weather.LAMP_N = 4

local lampBuf = {}
local lightC = { r = 1, g = 1, b = 1, key = nil }

-- The hour's light as the rain sees it: the tint, lifted off the floor so
-- a shower at 3am is dim rather than absent.
local function rainLight()
  local ok, t = pcall(DayNight.tint, true)
  if not (ok and t) then return 1, 1, 1 end
  if lightC.key == t then return lightC.r, lightC.g, lightC.b end
  local f = Weather.LIGHT_FLOOR
  lightC.key = t
  lightC.r = f + (1 - f) * (t[1] or 1)
  lightC.g = f + (1 - f) * (t[2] or 1)
  lightC.b = f + (1 - f) * (t[3] or 1)
  return lightC.r, lightC.g, lightC.b
end

-- The nearest posts, refreshed once per draw. Empty by day: the list the
-- lamps hand back is already gated on windowLight, so a noon shower pays
-- one pcall and no loop at all.
local function gatherLamps(ow)
  for i = #lampBuf, 1, -1 do lampBuf[i] = nil end
  if not (ow and ow.map and ow.player) then return end
  local okR, StreetLamps = pcall(V.require, "StreetLamps")
  if not (okR and StreetLamps and StreetLamps.lightsAround) then return end
  local px = (ow.player.cellX or 0) * 16
  local pz = (ow.player.cellY or 0) * 16
  local ok, list = pcall(StreetLamps.lightsAround, ow, px, pz, Weather.LAMP_N)
  if not (ok and list) then return end
  for i = 1, #list do
    local L = list[i]
    local r = (L.radius or 56) * Weather.LAMP_REACH
    lampBuf[#lampBuf + 1] = { x = L.x, z = L.z, r2 = r * r, p = L.power or 1 }
  end
end

-- How much brighter a drop at (x, z) is for standing in the gas. 1 outside
-- every cone. Falls off with the square of the distance the same way the
-- shader's own pools do, so the streaks brighten over exactly the patch of
-- road that is already lit.
local function lampGain(x, z)
  local n = #lampBuf
  if n == 0 then return 1 end
  local g = 0
  for i = 1, n do
    local L = lampBuf[i]
    local dx, dz = x - L.x, z - L.z
    local d2 = dx * dx + dz * dz
    if d2 < L.r2 then
      local k = 1 - d2 / L.r2
      g = g + k * k * L.p
    end
  end
  if g <= 0 then return 1 end
  if g > 1 then g = 1 end
  return 1 + (Weather.LAMP_LIFT - 1) * g
end

local function slant()
  -- rain leans on the wind, and the wind already has a bearing and a strength
  -- this world agrees on (Wind.DIR / Wind.amount). Only the X of it matters
  -- on screen, and only a share of it: rain that lay flat would be a gale.
  local amount = 0
  local ok, n = pcall(Wind.amount)
  if ok then amount = n or 0 end
  return Weather.SLANT + (Wind.DIR[1] or 1) * amount * 0.10
end

local function windForce()
  local amount = 0
  local ok, n = pcall(Wind.amount)
  if ok then amount = n or 0 end
  if amount < 0 then amount = 0 elseif amount > 1.5 then amount = 1.5 end
  return amount, (Wind.DIR and Wind.DIR[1]) or 1
end

-- Pick a depth layer the way a Unity rain setup uses 2–3 particle systems:
-- far sheet (many thin), mid, near (few thick, bright).
local function pickLayer()
  local r = rand()
  if r < Weather.LAYER_FAR then return "far" end
  if r < Weather.LAYER_FAR + Weather.LAYER_MID then return "mid" end
  return "near"
end

-- A fresh streak in the emission volume above (or across) the frame.
-- `anywhere` prewarms the field so a shower does not start as an empty top.
local function spawnDrop(w, h, anywhere)
  local layer = pickLayer()
  local speed, len, alpha, thick
  -- Mist between the camera and the diorama: shorter, dimmer than the
  -- old cloth. The world shafts carry the shower.
  if layer == "near" then
    speed = 0.95 + rand() * 0.45
    len   = 8 + rand() * 10
    alpha = 0.28 + rand() * 0.14
    thick = 1.2 + rand() * 0.4
  elseif layer == "mid" then
    speed = 0.70 + rand() * 0.40
    len   = 6 + rand() * 8
    alpha = 0.14 + rand() * 0.10
    thick = 0.85 + rand() * 0.25
  else
    speed = 0.50 + rand() * 0.35
    len   = 4 + rand() * 6
    alpha = 0.07 + rand() * 0.07
    thick = 0.6 + rand() * 0.2
  end
  drops[#drops + 1] = {
    x = rand() * (w + h * 0.7) - h * 0.35,
    y = anywhere and rand() * h or (-rand() * h * 0.55 - len),
    len = len,
    speed = speed,
    layer = layer,
    near = layer == "near",   -- legacy flag (probes / older draw)
    alpha = alpha,
    thick = thick,
    seed = rand() * 6.2832,
    phase = rand(),           -- 0..1 for alpha shimmer over lifetime
  }
end

-- ------- where a splash lands, and the two things that were wrong with it
--
-- WHERE a splash may land is a question this file cannot answer alone, and
-- the puddles are the reason. GroundFX knows which cells hold water, and
-- GroundFX requires THIS file (it reads `falling` every tick) -- so a require
-- back the other way is a cycle. It is pushed in instead, exactly as
-- `Water.wet` is pushed the other way for the same reason: a hook this file
-- declares and that file fills in, nil until it does.
--
-- Rain landing everywhere EXCEPT in the standing water is the single thing
-- that made a wet street read as two unrelated effects bolted together --
-- pools that nothing touched, and splashes bursting off dry paving beside
-- them. So a splash rolls for a pool first and takes open ground only when
-- it cannot find one nearby, which is also what real rain looks like: you
-- see it in the water and barely at all on the road.
Weather.poolAt = nil            -- filled by GroundFX; (map, cx, cy) -> bool
Weather.POOL_TRIES = 5          -- rolls spent looking for standing water

-- How high the ground is at a cell. A splash used to be pinned at world zero
-- whatever it landed on, which is right on a route's dirt and sixteen pixels
-- underground on a town's raised paving -- so in exactly the places worth
-- standing in a downpour, every ring drew sunk into the street. The shape
-- profile already knows the height; this only had to ask.
local function groundAt(map, cx, cy)
  local VoxelScene = V.require("VoxelScene")
  local ok, h = pcall(VoxelScene.groundAt, map, cx, cy)
  return (ok and h) or 0
end

-- ------- WHAT LANDS WHERE, AND HOW LOUD IT IS ALLOWED TO BE
--
-- Two separate questions, and running them together is what went wrong.
--
-- WHETHER the rain does something is a question with one answer: yes,
-- everywhere. A shower that visibly lands on the pond and passes through
-- the street without touching it is not a shower, it is an effect switched
-- on over one tile type -- and the street is where the player is standing.
--
-- WHAT it does is a different question with four answers, and only one of
-- them is loud. The crown, the collapsing cavity and the COLUMN thrown up
-- out of it are things a body of water does. Paving has no cavity to
-- collapse: a drop hitting stone bursts flat, small and quick. So a column
-- standing up out of a lawn is not rain, it is a sprinkler -- and that is
-- what was being drawn, because `Weather.poolAt` calls a grass cell
-- "holding water" during a shower and the pool branch routed it to the
-- water animation.
--
-- So the drawing is picked by surface (see pushImpact) and the size and
-- brightness with it. Everything still gets rain on it. Only water gets the
-- column.
--
-- The roll is weighted toward water rather than restricted to it: a pond in
-- frame should be visibly busier than the path beside it, which is what
-- rain actually looks like.
Weather.WATER_TRIES = 4     -- rolls spent looking for open water first

local function splashCell(ow)
  local map, p = ow.map, ow.player
  for _ = 1, Weather.WATER_TRIES do
    local cx = p.cellX + rand(-7, 7)
    local cy = p.cellY + rand(-7, 7)
    if map:inBounds(cx, cy) and map:isWaterCell(cx, cy) then
      return cx * 16 + rand(1, 15), cy * 16 + rand(1, 15), "water", 0
    end
  end
  -- then a puddle, which is water on the ground and reads as neither the
  -- pond nor the dry paving
  local pool = Weather.poolAt
  if pool then
    for _ = 1, Weather.POOL_TRIES do
      local cx = p.cellX + rand(-6, 6)
      local cy = p.cellY + rand(-6, 6)
      local ok, holds = pcall(pool, map, cx, cy)
      if ok and holds then
        return cx * 16 + rand(5, 11), cy * 16 + rand(5, 11),
               "pool", groundAt(map, cx, cy)
      end
    end
  end
  for _ = 1, 8 do
    local cx = p.cellX + rand(-7, 7)
    local cy = p.cellY + rand(-7, 7)
    if map:inBounds(cx, cy) and map:isWalkableCell(cx, cy) then
      local surf = "stone"
      if map.isGrassCell then
        local okG, isGrass = pcall(map.isGrassCell, map, cx, cy)
        if okG and isGrass then surf = "grass" end
      end
      return cx * 16 + rand(1, 15), cy * 16 + rand(1, 15),
             surf, groundAt(map, cx, cy)
    end
  end
  return nil
end

-- How far above the surface it lands on a ring is drawn. A hair, in every
-- case -- what these numbers are for is being ON the right surface rather
-- than at world zero. A pool's own decal floats at GroundFX.PUDDLE (0.7), so
-- a ring in one has to clear that or it draws inside the water it is
-- breaking; a pond's surface is recessed and the ring sits down in it.
Weather.SPLASH_LIFT = 0.15
Weather.SPLASH_POOL_LIFT = 0.9
Weather.SPLASH_POND_LIFT = -1.5

-- and how much wider a ring in standing water opens than one on dry stone,
-- which is the difference you can see from across a street
Weather.SPLASH_POOL_SIZE = 1.45

-- ------- ONE CENSUS A FRAME, NOT ONE PER SPAWN
--
-- Four kinds of mote share one list and each has its own ceiling: rings,
-- ejecta, drips, flakes. Every ceiling used to be enforced by walking the
-- whole list at the moment of asking, which is fine when the caller is the
-- tick (once) and wrong when it is a landing raindrop (dozens a frame,
-- each walking a hundred and twenty motes).
--
-- Worse, the ring's ceiling was `#motes` -- the WHOLE list -- so the
-- moment ejecta existed they crowded the rings out of their own budget
-- and a downpour on a pond lost half its rings to the crowns coming off
-- them. Counting all four separately is what stops one effect eating
-- another's allowance.
local live = { splash = 0, eject = 0, drip = 0, flake = 0 }

local function census()
  live.splash, live.eject, live.drip, live.flake = 0, 0, 0, 0
  for i = 1, #motes do
    local m = motes[i]
    local k = m.kind
    -- a splash past its burst is only its ink drying (see THE INK): it
    -- costs one ellipse, not a crown, so it does not hold a slot in the
    -- splash budget -- counting it there starved the SPAWNS, and the
    -- pond's own hits were what went missing first
    if k == "splash" and m.t >= m.ttl then k = nil end
    if k then live[k] = (live[k] or 0) + 1 end
  end
end

local function spawnSplash(ow)
  local x, z, surf, gh = splashCell(ow)
  if not x then return end
  local lift = (surf == "water" and Weather.SPLASH_POND_LIFT)
               or (surf == "pool" and Weather.SPLASH_POOL_LIFT)
               or Weather.SPLASH_LIFT
  live.splash = live.splash + 1
  local life = (surf == "water" and 0.52)
               or (surf == "pool" and 0.44)
               or (surf == "grass" and 0.22) or 0.26
  motes[#motes + 1] = {
    kind = "splash", seed = rand() * 6.2832,
    x = x, z = z, y = (gh or 0) + lift,
    size = (surf == "water" and 1.7)
           or (surf == "pool" and Weather.SPLASH_POOL_SIZE) or 0.62,
    surf = surf,
    t = 0, ttl = life,
    ink = (surf == "water" or surf == "pool") and life
          or life * Weather.INK_LINGER,
  }
end

-- What a shaft is about to hit at (wx, wz): the LIVE water surface, a
-- puddle, a roof / tree crown, or the walkable ground. groundAt already
-- answers the height of a building cell as the roof, so rain stops on
-- the Mart instead of falling through the counter.
local function surfaceAt(ow, wx, wz)
  local map = ow.map
  local cx = math.floor((wx or 0) / 16)
  local cy = math.floor((wz or 0) / 16)
  if not map:inBounds(cx, cy) then return 0, "ground" end
  if map:isWaterCell(cx, cy) then
    local y = Weather.SPLASH_POND_LIFT
    local ok, s = pcall(Water.surfaceAt, wx, wz)
    if ok and tonumber(s) then y = s end
    return y, "water"
  end
  local gh = groundAt(map, cx, cy)
  if Weather.poolAt then
    local ok, holds = pcall(Weather.poolAt, map, cx, cy)
    if ok and holds then
      return gh + Weather.SPLASH_POOL_LIFT, "pool"
    end
  end
  -- a raised cell you cannot walk is a lid (roof, hedge, tree crown)
  if gh > 6 and not map:isWalkableCell(cx, cy) then
    return gh, "roof"
  end
  -- ------- and the ground is not one thing
  --
  -- Grass and paving take a drop completely differently and nothing
  -- downstream could tell them apart, because this returned "ground" for
  -- both. A blade of grass is a springy edge a drop breaks over; a paving
  -- slab is a hard flat plane a drop shatters on. Same rain, two sights.
  if map.isGrassCell then
    local okG, isGrass = pcall(map.isGrassCell, map, cx, cy)
    if okG and isGrass then
      return gh + Weather.SPLASH_LIFT, "grass"
    end
  end
  return gh + Weather.SPLASH_LIFT, "stone"
end

-- Placed AFTER surfaceAt on purpose: a flake now lands on whatever is
-- under it rather than at world zero, and `local function` means the
-- name it needs does not exist yet one line above this one.

-- How much of the air's speed a flake ends up carrying. Higher than rain
-- by a long way and still under one: snow is nearly weightless, so it goes
-- almost where the wind goes -- but a flake that matched the air exactly
-- would stop reading as an object at all.
Weather.SNOW_CARRY = 0.85

local function spawnFlake(ow)
  local p = ow.player
  local x = (p.cellX + rand(-9, 9)) * 16 + rand(0, 15)
  local z = (p.cellY + rand(-9, 9)) * 16 + rand(0, 15)
  -- Size drives fall speed the same way it does for rain, and much more
  -- weakly: every flake in a fall is close to the same terminal velocity
  -- (that is WHY snow drifts rather than falling), so this is a narrow
  -- spread on purpose. What varies wildly is the WANDER, not the descent.
  local d = rand() ^ 1.6
  local yLand = select(1, surfaceAt(ow, x, z))
  motes[#motes + 1] = {
    kind = "flake", x = x, z = z, y = yLand + 40 + rand() * 26,
    yLand = yLand,
    seed = rand() * 6.2831, t = 0, ttl = 30,
    fall = 6.5 + d * 5.5,
    -- the flake's own tumble: rate and radius, both scattered hard, which
    -- is the whole reason a handful of them reads as a snowfall
    rate = 0.7 + rand() * 2.2,
    wob = 2.6 + rand() * 7.5,
    vx = 0, vz = 0,
    size = (d > 0.72) and 1.4 or 0.9,
  }
end

-- ------- WHAT A DROP ACTUALLY DOES WHEN IT LANDS
--
-- A ring, and that was all there was. A ring is the right FIRST half: the
-- wave going out from the impact is what you see on a wet road from across
-- the street. But it is not what you see from two feet away, and this
-- camera is two feet away.
--
-- Close up, a drop hitting water does something much more specific. The
-- surface caves, the wall of the cavity climbs back up as a CROWN, the
-- crown becomes unstable and throws a handful of small drops off its rim,
-- and those drops fly up, arc over and fall back in. That is the whole
-- reason rain on a puddle reads as violent -- the water is being thrown
-- around, not merely rippled.
--
-- So a splash now spawns EJECTA: a few tiny ballistic drops off the rim,
-- with a real vertical velocity and real gravity, that land and are gone.
-- They cost a table each and no draw call of their own (they ride the same
-- mote loop as everything else here), and they are budgeted by surface,
-- because the surface is what decides how much water there is to throw:
--
--   WATER  the most, and the highest -- an open pond has depth to give
--   POOL   fewer, lower: a puddle is a film, and a film has little to give
--   GROUND one or two, barely -- this is spray off stone, not a crown
--   ROOF   none. A tile is a hard dry surface at a slant; what leaves it
--          leaves as a drip off the eave, which this file already has.
Weather.EJECT_MAX = 150             -- live ejecta ceiling, all surfaces
Weather.EJECT_G = 260               -- world px/s/s, the arc's whole shape

local function spawnEjecta(x, z, y, surf, d, n)
  local room = Weather.EJECT_MAX - live.eject
  if room <= 0 then return end
  if n > room then n = room end
  live.eject = live.eject + n
  for _ = 1, n do
    -- off the rim, so they leave the crown rather than the centre
    local a = rand() * 6.2832
    local out = 14 + rand() * 26
    -- Steep. A crown throws almost straight up: a shallow spray is what a
    -- hose does, and it reads as a firework rather than as water.
    local up = 42 + rand() * 46 + d * 30
    motes[#motes + 1] = {
      kind = "eject", x = x, z = z, y = y + 0.6,
      vx = math.cos(a) * out, vz = math.sin(a) * out, vy = up,
      yLand = y,
      size = 0.55 + rand() * 0.45,
      t = 0, ttl = 0.9,
    }
  end
end

-- ------- EVERY LIVE CAP IN THIS FILE, THROUGH THE PFX ROW
--
-- The counts below are the ones that were tuned per RES rung, and ON
-- leaves every one of them exactly where it was. The row is a second axis
-- over the top: somebody who wants a squall can have four times the water
-- without the grass, the shadow map and the cloud raymarch getting heavier
-- with it, which is the thing the RES row could never express.
--
-- Read per call rather than cached, because a row the player can cycle
-- mid-shower has to take effect in that shower.
local function pfxMul()
  local ok, m = pcall(Quality.particles)
  return (ok and tonumber(m)) or 1
end

local function splashCap()
  local n = math.floor(Weather.SPLASHES * pfxMul())
  return (n < 1) and 1 or n
end

local function flakeCap()
  local n = math.floor(Weather.FLAKES * pfxMul())
  return (n < 1) and 1 or n
end

local function dripCap()
  local n = math.floor(Weather.DRIP_MAX * pfxMul())
  return (n < 1) and 1 or n
end

-- (Declared HERE, well above shaftBudget, and not for tidiness: splashCap
-- is read by splashFromHit a few hundred lines up. A local declared below
-- its own caller is a GLOBAL at the call site, the global is nil, and
-- calling it throws -- which in this file has already cost one silent,
-- total failure of the weather system. Sweep for it after every insert.)

-- ------- WHY A RING FLOATS TWO PIXELS OFF WHAT IT LANDED ON
--
-- The rain shader's depth test (the T3 occlusion) compares each fragment
-- against the scene's own depth buffer, and a ring lying ON the surface
-- that wrote that depth is a tie -- which the small DEPTH_BIAS was meant
-- to forgive and, measured, does not: with the test armed, a shower held
-- two hundred live roof rings and two hundred and fifty stone rings and
-- painted NONE of them (probe_out_rainland; the player's own report was
-- "os pingos não atingem o chão"). Raising the bias is the wrong lever:
-- device depth is nonlinear, so a slack wide enough for a far tie starts
-- forgiving near geometry that really is in front. A WORLD-space raise
-- projects to exactly the right depth slack at every distance. Two
-- pixels is under the drawn thickness of the ring, so nothing visibly
-- hovers. Water keeps its own height: the pond ink is measured against
-- the recessed floor and was never eaten.
Weather.SPLASH_RAISE = 2.0

local function splashFromHit(x, z, y, surf, d)
  if live.splash >= splashCap() then return end
  if surf ~= "water" then y = y + Weather.SPLASH_RAISE end
  -- "ground" is surfaceAt's answer for a cell OFF THE MAP -- the void
  -- past the diorama's edge, where the reach outruns a small town. It
  -- used to make a mote no branch of pushImpact drew, which was merely
  -- waste; now that every landing also stamps ink, it would be wet marks
  -- floating in nothing. The void does not splash.
  if surf == "ground" or not surf then return end
  -- ------- every surface gets something; only one gets the column
  --
  -- The sizes below are the whole of the difference in loudness, and they
  -- are deliberately far apart. A pond hit is nearly twice the drawn size
  -- of a paving hit and lasts twice as long; the paving hit is a quick
  -- small burst that says the rain arrived and then gets out of the way.
  -- WHAT each one draws is pushImpact's business, and that is where the
  -- column lives -- along with the flat star stone throws, the one-sided
  -- flick a blade of grass gives, and the downhill skid off a tile.
  d = tonumber(d) or 0.5
  local size, ttl, eject
  if surf == "water" then
    size, ttl = 1.85, 0.58
    eject = 2 + math.floor(rand() * 3 + d * 2)
  elseif surf == "pool" then
    size, ttl = Weather.SPLASH_POOL_SIZE, 0.40
    eject = (d > 0.45) and 1 or 0
  elseif surf == "roof" then
    size, ttl, eject = 0.55, 0.22, 0
  elseif surf == "grass" then
    -- gone almost before it started: a blade takes the drop and springs
    size, ttl, eject = 0.5, 0.22, 0
  else
    size, ttl = 0.62, 0.26
    eject = (d > 0.62 and rand() < 0.45) and 1 or 0
  end
  -- the ring reads the drop too: a fat one opens a wider, longer-lived one
  size = size * (0.78 + 0.48 * d)
  live.splash = live.splash + 1
  local life = ttl + rand() * 0.14
  motes[#motes + 1] = {
    kind = "splash", seed = rand() * 6.2832,
    x = x, z = z, y = y,
    size = size, surf = surf,
    t = 0, ttl = life,
    -- the dark half's own clock (see THE INK above): dry ground holds the
    -- wet mark long after the burst is over; water has no mark to hold
    ink = (surf == "water" or surf == "pool") and life
          or life * Weather.INK_LINGER,
  }
  if eject > 0 then spawnEjecta(x, z, y, surf, d, eject) end
  if surf == "pool" and Weather.notePoolHit then
    -- and GroundFX's own ripple inside the film of water on the road,
    -- which is a different drawing from this one
    pcall(Weather.notePoolHit, x, z)
  end
end

-- ------- THE EAVE, which is where a roof actually lets go
--
-- What was here spawned the drip BESIDE the hit -- twelve pixels off in
-- one random direction, kept only if that spot happened to be off the
-- roof. On a real building almost every hit is an INTERIOR tile, all four
-- of whose neighbours are more roof, so almost every call threw its drip
-- away: measured under a pinned downpour, SEVEN drips alive across a
-- whole town (tests/rain_interact_probe.lua). Seven one-pixel threads in
-- a nineteen-cell reach is not a roof dripping, it is noise.
--
-- Water on a pitched roof does not drop where it lands. It RUNS, and it
-- leaves at the edge -- and it leaves at the same low points every time,
-- which is why standing by a house in rain you watch one spot of the
-- pavement being hit over and over. Both halves matter and both were
-- missing:
--
--   THE WALK.  From the hit cell, walk roofward cells in a fixed
--   direction until the edge (a handful of cells at most). Every interior
--   hit now finds an eave instead of being discarded.
--
--   THE SPOT.  Which direction, and where along that edge, comes off a
--   HASH of the cell rather than a roll -- so a given roof tile drains to
--   the same point of the same eave forever. That repetition is the
--   entire difference between "drips" and "a gutter".
--
-- And the drop itself gets its two real phases: it HANGS at the eave,
-- swelling for a fraction of a second -- the bead on the gutter lip --
-- and then falls. The bead is what makes an eave read as dripping even
-- between drops, because there is nearly always one growing somewhere.
Weather.EAVE_WALK = 4             -- cells an interior hit runs before giving up
Weather.EAVE_CHANCE = 0.30        -- drips per roof hit (was 0.38 of nearly none)
Weather.DRIP_HANG_MIN = 0.18      -- seconds the bead swells before letting go
Weather.DRIP_HANG_VAR = 0.34

-- the cell's own die, cast once forever: which way its water runs and
-- where on the lip it beads. Any cheap integer mash does; this one only
-- has to be stable and spread.
local function eaveHash(cx, cy)
  local h = (cx * 73856093 + cy * 19349663) % 2147483647
  return h
end

local function spawnDrip(ow, x, z, yRoof)
  local cx = math.floor((x or 0) / 16)
  local cy = math.floor((z or 0) / 16)
  local h = eaveHash(cx, cy)
  local dir = h % 4
  local dx = (dir == 0 and 1) or (dir == 1 and -1) or 0
  local dz = (dir == 2 and 1) or (dir == 3 and -1) or 0
  -- run downhill to the eave: the first neighbour that is not more roof
  local ex, ey = cx, cy
  local yLand, over
  for _ = 1, Weather.EAVE_WALK do
    local nx, ny = ex + dx, ey + dz
    local yl = select(1, surfaceAt(ow, nx * 16 + 8, ny * 16 + 8))
    if yl < (yRoof or 0) - 2 then yLand, over = yl, true break end
    ex, ey = nx, ny
  end
  if not over then return end
  -- the bead's fixed spot on the lip, just off the roof cell's edge
  local along = 3 + (math.floor(h / 7) % 11)
  local wx, wz
  if dx ~= 0 then
    wx = (dx > 0) and (ex * 16 + 17) or (ex * 16 - 1)
    wz = ey * 16 + along
  else
    wx = ex * 16 + along
    wz = (dz > 0) and (ey * 16 + 17) or (ey * 16 - 1)
  end
  local _, lsurf = surfaceAt(ow, wx, wz)
  motes[#motes + 1] = {
    kind = "drip", x = wx, z = wz, y = (yRoof or 0) - 1,
    yLand = yLand, surf = lsurf, fall = 70 + rand() * 30,
    hang = Weather.DRIP_HANG_MIN + rand() * Weather.DRIP_HANG_VAR,
    t = 0, ttl = 1.8,
  }
end

-- ------- and the eaves keep dripping when the shafts are elsewhere
--
-- Shaft landings alone gate the gutters to wherever the sheets happen to
-- be falling this second. A roof in rain sheds CONTINUOUSLY -- it is
-- draining everything that landed on it in the last minute -- so the
-- eaves also drip on their own clock: a dart at a cell near the player,
-- kept if it is a lid, drained through the same walk as a hit. Same
-- pattern as the canopy's dart below, for the same O(1) reason.
--
-- Runs off the LARGER of the live power and the after-rain window (the
-- window squared -- a roof is sheet metal and tile, it drains in a
-- minute, not the wood's three), so walking past a house just after a
-- shower still means water off the eave in front of you.
Weather.EAVE_RATE = 26            -- ambient dart attempts per second

-- ------- AND THE SAME DART HAS TO CARRY TWICE THE LOAD ONCE THE SKY STOPS
--
-- While it rains the gutters have TWO sources, and the dart is the small
-- one: every roof splash also spawns a drip at EAVE_CHANCE, and with ~194
-- roof splashes live that source is most of what is on screen. Measured in
-- a pinned downpour over Pallet Town: 35 drips alive.
--
-- The moment the shower ends, that source is gone outright -- no shafts, no
-- splashes, no roof hits -- and the dart is left holding the whole effect
-- at the rate it was given as a SUPPLEMENT. The arithmetic of what that
-- leaves:
--
--   26 attempts/s
--   x ~0.23     the fraction of cells inside SHAFT_REACH that are a lid
--               (Pallet Town offers 83 of them; the reach is 361 cells)
--   x ~0.7 s    a bead hangs 0.18-0.52 s and then falls a roof's height at
--               ~85 px/s, so it exists for well under a second
--   = ~3 drips alive
--
-- Measured: 5. Five drips over a whole town is a mote count, not a
-- picture -- and it is the entire reason the after-rain read as empty
-- against a dry frame (signal/noise 1.0x on the pixel A/B).
--
-- So the after-rain regime gets its own rate, sized to land back on the
-- during-rain density it is standing in for: 30 = rate x 0.23 x 0.7 gives
-- ~186. The shower keeps the old number, because the shower still has its
-- roof hits and does not need the help -- raising one rate for both would
-- have bought a heavier storm to fix a problem the storm does not have.
--
-- DRIP_MAX still caps it at 72 live, so this cannot become the frame.
Weather.EAVE_RATE_AFTER = 190     -- and per second once the sky has stopped

local function spawnEaveDrip(ow)
  local p = ow.player
  if not p then return end
  local r = Weather.SHAFT_REACH
  local cx = p.cellX + rand(-r, r)
  local cy = p.cellY + rand(-r, r)
  local map = ow.map
  if not map:inBounds(cx, cy) then return end
  local wx, wz = cx * 16 + 8, cy * 16 + 8
  local yl, surf = surfaceAt(ow, wx, wz)
  if surf ~= "roof" then return end
  spawnDrip(ow, wx, wz, yl)
end

-- ------- AND THE WOOD KEEPS RAINING AFTER THE SKY STOPS
--
-- A canopy holds water and lets it go slowly, so the minutes after a
-- shower are the ones where standing under a tree still gets you wet. It
-- is the other half of the shelter the canopy gives (GrassWear's alpha
-- channel, baked by Trees3D): the same crown that kept the ground dry is
-- what is dripping onto it now.
--
-- NEVER ITERATES THE FOREST. A route is 862 trees and this runs every
-- frame for three minutes; walking that list to find the near ones would
-- cost more than the whole weather system. Instead it throws a dart at a
-- cell near the player and ASKS whether that cell is under a crown -- one
-- O(1) read of a field that is already baked and already resident. The
-- reach is what makes it local, and the cover is what makes it land on
-- trees; neither needs a list.
--
-- Reuses the "drip" mote the eaves already use, so a drop off a branch and
-- a drop off the Mart's roof fall and land through the same code.
Weather.DRIP_REACH = 7            -- cells around the player
Weather.DRIP_COVER = 0.35         -- below this a cell is not under enough tree
Weather.DRIP_MAX = 72             -- live canopy drips at once
-- SPAWN ATTEMPTS per second, and it is four steps removed from how many
-- drips are actually on screen -- which is why the first two guesses at
-- this number were both far too low (11 and 48 each measured a peak of
-- THREE in a whole wood).
--
-- The arithmetic, because guessing it twice was enough:
--
--   attempts/s            this number
--   x ~0.25               most darts land on a cell with no crown over
--                         it, or lose the roll against a thin one
--   = spawns/s
--   x ~0.25 s of LIFE     and this is the part that bites: a drop leaves
--                         a branch about DRIP_HEIGHT above the ground and
--                         falls at ~80 px/s, so it exists for a quarter
--                         of a second. The mote's 1.6 s ttl never runs --
--                         it lands long before that.
--   = drips alive
--
-- So ~16 attempts for every drip visible at once. 170 buys about ten,
-- which is a wood letting go here and there rather than a downpour.
Weather.DRIP_RATE = 170
-- How far above the ground a branch lets go. The bake stands ~28 model
-- units and a route's sites scale it to about two thirds of that, so this
-- is the underside of a crown rather than its top -- a drop that started
-- at the very tip would fall past the silhouette it is supposed to come
-- from.
Weather.DRIP_HEIGHT = 14

local function spawnCanopyDrip(ow)
  local p = ow.player
  if not p then return end
  local r = Weather.DRIP_REACH
  local cx = p.cellX + rand(-r, r)
  local cy = p.cellY + rand(-r, r)
  local cover = 0
  local okg, GW = pcall(V.require, "GrassWear")
  if okg and GW and GW.canopyAt then
    local okv, v = pcall(GW.canopyAt, cx, cy)
    cover = (okv and tonumber(v)) or 0
  end
  if cover < Weather.DRIP_COVER then return end
  -- Denser crown drips more often, so a wood's interior ticks and its
  -- fringe only occasionally -- the gradient the field already carries,
  -- spent rather than thresholded away.
  if rand() > cover then return end
  local x = cx * 16 + rand(0, 15)
  local z = cy * 16 + rand(0, 15)
  local yLand, lsurf = surfaceAt(ow, x, z)
  motes[#motes + 1] = {
    kind = "drip", x = x, z = z,
    y = yLand + Weather.DRIP_HEIGHT + rand() * 5,
    yLand = yLand, surf = lsurf, fall = 62 + rand() * 34,
    t = 0, ttl = 1.6,
  }
end

local function shaftBudget()
  local s = 1
  local ok, n = pcall(Quality.scale)
  if ok and tonumber(n) then s = n end
  local base
  if s >= 4 then base = math.floor(Weather.SHAFTS * 0.10)
  elseif s == 3 then base = math.floor(Weather.SHAFTS * 0.22)
  elseif s == 2 then base = Weather.SHAFTS
  else base = Weather.SHAFTS_MAX end
  local out = math.floor(base * pfxMul())
  return (out < 1) and 1 or out
end

-- Every shaft gets an id, and it exists for one reason: a probe that wants
-- to know whether drops are DISAPPEARING in front of the player cannot
-- match them by position -- they move every frame, which is the whole
-- point of them.
local shaftId = 0

-- ------- RAIN COMES IN SHEETS, NOT IN A FOG OF EVEN DENSITY
--
-- Where a drop spawns used to be a flat roll over the reach, which gives a
-- field with the same number of drops everywhere. Look out of a window in
-- a squall and that is not what is there: the rain arrives in visible
-- BANDS, dense curtains sweeping across with thinner air between them, and
-- that texture is most of what makes a downpour read as moving weather
-- rather than as a screen effect.
--
-- The bands already exist -- Wind.flowAt carries them, the grass is
-- bending in them, the drops are already leaning with them. This just
-- makes the rain DENSER where the band is strong, by rolling a position
-- and keeping it in proportion to the air there. Three tries and then take
-- what you are given, so a lull still gets rain and the loop still ends.
Weather.BUNCH = 3                 -- rolls spent looking for a dense band

local function spawnShaft(ow, anywhere)
  local p = ow.player
  local r = Weather.SHAFT_REACH
  local x, z
  for try = 1, Weather.BUNCH do
    x = (p.cellX + rand(-r, r)) * 16 + rand(0, 15)
    z = (p.cellY + rand(-r, r)) * 16 + rand(0, 15)
    if try == Weather.BUNCH then break end
    local _, _, band = Wind.flowAt(x, z)
    -- band runs about 0.4 in a lull to 1.6 in the crest; squared, so the
    -- crest is four times as likely to be chosen as the lull rather than
    -- merely twice
    if (band or 1) >= 1 then break end
    if rand() < band * band then break end
  end
  local ySurf = select(1, surfaceAt(ow, x, z))
  -- always start ABOVE the lid, never inside a house
  local air = 22 + rand() * 56
  local y = ySurf + (anywhere and (4 + rand() * air) or air)

  -- ------- the one roll everything else comes out of
  --
  -- Biased small (DROP_BIAS), so a shower is mostly fine rain with a
  -- scatter of heavy drops through it rather than an even mix of both.
  --
  -- And the bias MOVES WITH THE SHOWER, which is the difference between
  -- four kinds of rain and one kind of rain at four densities. Drizzle is
  -- not a downpour with fewer drops in it -- it is a cloud of drops so
  -- fine they barely fall, and it has no fat ones at all. A cloudburst is
  -- the opposite: the distribution slides bodily up, the big drops arrive,
  -- and that is why heavy rain sounds and looks like a different substance
  -- rather than more of the same one. (Marshall and Palmer again: the
  -- exponential's slope flattens as the rate goes up.)
  --
  -- So the exponent falls from a hard small-drop bias at the start of a
  -- shower to nearly a flat roll at its peak, and the floor of the size
  -- range rises with it.
  local pw = Weather.dropPower or 1
  local bias = Weather.DROP_BIAS - (Weather.DROP_BIAS - Weather.DROP_BIAS_WET) * pw
  local dmin = Weather.DROP_MIN + (Weather.DROP_MIN_WET - Weather.DROP_MIN) * pw
  local d = dmin + (Weather.DROP_MAX - dmin) * rand() ^ bias
  local fall = Weather.SHAFT_FALL * terminal(d)

  -- The layer survives, but it no longer decides the physics -- only how
  -- much of the frame this drop is entitled to. A "far" shaft is one the
  -- camera is meant to read as distant haze, so it is thin and dim; the
  -- SIZE then modulates that, because a fat drop is heavier on screen
  -- wherever it is standing.
  local layer = pickLayer()
  -- ------- and the brightness the two fades cost, paid back
  --
  -- Every shaft now spends the start of its life fading in and the rim of
  -- the reach fading out, which is what stops the field popping -- and it
  -- is also brightness removed from a shower nobody asked to turn down. A
  -- fifth of the ink, measured off the screenshots rather than guessed:
  -- the birth fade is a slice of a life that only lasts half a second, and
  -- the edge band is a quarter of the reach's AREA even at a modest depth.
  --
  -- So the alphas carry it back. This is a level correction and nothing
  -- else: the point of the size roll is to REDISTRIBUTE the weight of the
  -- field, and a redistribution that also removes a fifth of it is two
  -- changes wearing one coat.
  -- ------- and the brightness, against a field three times as dense
  --
  -- These carry two corrections at once and it is worth saying which is
  -- which, because they pull opposite ways.
  --
  -- UP, for the two fades. Every shaft spends the start of its life fading
  -- in and the rim of the reach fading out, which is what stops the field
  -- popping and is also brightness removed from a shower nobody asked to
  -- turn down -- a fifth of the ink, measured off the screenshots.
  --
  -- DOWN, and further, for the COUNT. The field went from a hundred and
  -- fifty drops to four hundred and forty, and drops overlap: three times
  -- the streaks at the old per-drop alpha is not three times the rain, it
  -- is a white sheet. What a downpour looks like is MANY FAINT streaks,
  -- not a few bright ones drawn more often -- so the density went up and
  -- the individual drop went down to meet it.
  --
  -- And they are THINNER. A raindrop seen from two feet is a needle; the
  -- near layer was drawing bars, and at three times the count that is the
  -- difference between rain and a bad screen wipe.
  -- THIN AND BRIGHT beats thick and faint, and that is not a preference,
  -- it is what rain is: a drop is a needle catching a highlight, so the
  -- eye wants a narrow hard core rather than a wide soft band carrying the
  -- same amount of light. The widths came down by a quarter and the alphas
  -- went up to hold the field's total weight where it was.
  local alpha, thick
  if layer == "near" then
    alpha = 0.56 + rand() * 0.29
    thick = 0.78 + rand() * 0.28
  elseif layer == "mid" then
    alpha = 0.33 + rand() * 0.19
    thick = 0.60 + rand() * 0.20
  else
    alpha = 0.17 + rand() * 0.13
    thick = 0.46 + rand() * 0.16
  end
  -- Both terms average to one across the size roll, on purpose: SIZE is
  -- supposed to redistribute the weight across the field, not remove it.
  -- An expression that happens to average 0.95 is a shower five per cent
  -- fainter than the one it replaced, for no reason anybody chose.
  thick = thick * (0.72 + 0.67 * d)
  alpha = alpha * (0.80 + 0.48 * d)

  -- Sideways, a fresh drop is ALREADY going where the air is going. It has
  -- been falling out of a cloud for a while by the time it enters the
  -- frame, and starting it at rest would make the top of the emission
  -- volume a band where every drop is visibly straightening up.
  local ax, az = Wind.flowAt(x, z)

  shaftId = shaftId + 1
  shafts[#shafts + 1] = {
    id = shaftId,
    x = x, y = y, z = z,
    vx = ax, vz = az,
    d = d,
    tau = Weather.DRAG_MIN + Weather.DRAG_SPAN * d,
    fall = fall,
    -- Length is TIME, not a constant: how far this drop travels in the
    -- span the eye smears it over. Which is why it no longer has to be
    -- stretched separately at draw -- the streak IS the distance covered.
    len = fall * Weather.SHAFT_SMEAR * (0.85 + rand() * 0.30),
    layer = layer,
    alpha = alpha, thick = thick,
    age = 0,
    fade = anywhere and 1 or 0,
    seed = rand() * 6.2832,
  }
end

-- ------- THE STEP THAT MAKES IT WEATHER
--
-- What was here moved every drop in the world by the same vector: one
-- global wind speed, times sixteen, times dt. Every shaft, every size,
-- every position -- identical. That is not a shortcut with a cost in
-- realism, it is the ABSENCE of the effect: a field where every member
-- moves identically has no internal structure at all, so a gale and a
-- drizzle differ only in how fast the whole sheet slides sideways.
--
-- Two things replace it, and they are the two things that are actually
-- true about rain in wind:
--
--   THE AIR IS NOT THE SAME EVERYWHERE. It is asked for per drop, at that
--   drop's own position, out of the field the grass under it already rides
--   (Wind.flowAt). Drops close together get nearly the same answer and
--   drops a wood apart get different ones, so the shower arrives in
--   sheets -- and the sheet crossing the meadow is the same sheet bending
--   the meadow, because it is one field.
--
--   A DROP IS NOT THE AIR. It is pulled toward the air's velocity over its
--   own response time, which is longer for a heavy drop (see DRAG_SPAN).
--   So a gust front sorts the rain as it passes: the fine stuff veers
--   first and the fat drops plough through it. That sorting is most of
--   what a squall looks like, and no amount of per-particle noise
--   produces it, because noise has no front.
--
-- Vertical is untouched by any of it, which is also correct: a drop is at
-- terminal velocity by the time it reaches the frame and stays there.
local function stepShafts(ow, dt, power)
  local want = math.floor(shaftBudget() * (0.35 + 0.65 * power))
  if want < 0 then want = 0 end
  local first = #shafts == 0
  for _ = 1, math.max(0, want - #shafts) do spawnShaft(ow, first) end
  while #shafts > want do table.remove(shafts) end

  local p = ow.player
  local px = (p.cellX or 0) * 16
  local pz = (p.cellY or 0) * 16
  local reach = Weather.SHAFT_REACH * 16 + 48
  -- where the fade starts, and where the shaft is finally let go
  local fadeAt = reach * (1 - Weather.FADE_EDGE)
  local fadeSpan = math.max(1, reach - fadeAt)
  local fadeInK = dt / math.max(0.01, Weather.FADE_IN)

  for i = #shafts, 1, -1 do
    local s = shafts[i]
    s.age = (s.age or 0) + dt

    -- the air here, and how fast this particular drop can answer it
    local ax, az = Wind.flowAt(s.x, s.z)
    local k = dt / (s.tau or 0.3)
    if k > 1 then k = 1 end
    s.vx = (s.vx or 0) + (ax - (s.vx or 0)) * k
    s.vz = (s.vz or 0) + (az - (s.vz or 0)) * k

    s.x = s.x + s.vx * dt
    s.z = s.z + s.vz * dt
    s.y = s.y - s.fall * dt

    local yHit, surf = surfaceAt(ow, s.x, s.z)
    local dx = math.abs(s.x - px)
    local dz = math.abs(s.z - pz)
    local out = (dx > dz) and dx or dz
    -- Out at the rim the streak thins to nothing before it is recycled, so
    -- the ring of popping that used to follow the player around is a ring
    -- of rain going quiet instead.
    local edge = 1
    if out > fadeAt then
      edge = 1 - (out - fadeAt) / fadeSpan
      if edge < 0 then edge = 0 end
    end
    local born = s.fade or 0
    if born < 1 then
      born = born + fadeInK
      if born > 1 then born = 1 end
      s.fade = born
    end
    s.vis = edge * born

    if s.y <= yHit or out > reach then
      if out <= reach and s.y <= yHit + 6 then
        splashFromHit(s.x, s.z, yHit, surf, s.d)
        if surf == "roof" and rand() < Weather.EAVE_CHANCE
           and live.drip < dripCap() then
          spawnDrip(ow, s.x, s.z, yHit)
          live.drip = live.drip + 1
        end
      end
      -- recycle into the air column above a fresh cell
      local ns = #shafts
      table.remove(shafts, i)
      if ns <= want then spawnShaft(ow, false) end
    end
  end
end

-- ------- per-frame
--
-- Rides the voxel pipeline's update hook with the rest of the mod's clocks,
-- which is the tick that keeps running through battles and menus -- so a
-- shower that started while you were walking is still going when you come out
-- of the fight, exactly as the sky's own hour is.
local failed = false
local lastErr = nil

-- ------- HOW MANY TIMES THIS ACTUALLY RAN
--
-- A diagnostic, and it exists because a probe found the shafts and the
-- splashes frozen to the digit over four hundred frames and there was no
-- way to tell WHICH of the three possible reasons it was: the update not
-- being called, the update being called and returning early, or the tick
-- inside it having thrown once and latched `failed`. Those want three
-- different fixes. A counter at the top and one after the tick separates
-- them in a single reading.
Weather.ticks = 0
Weather.ticksOk = 0

local function tick(dt)
  local Game = game()
  local ow = Game and Game.overworld

  local mode = Weather.setting:get() or "auto"

  -- ------- the spell
  --
  -- The row CHANGING is its own event, and it has to be: a pin holds the
  -- spell open forever (an infinite timer, a pinned target), so arriving at AUTO
  -- with that spell still in place left a shower whose clock could not run
  -- out and whose target nothing would lower -- permanent rain, from a row
  -- that says AUTO. So every change of the row starts a fresh spell, which
  -- is also the behaviour a player expects: choosing AUTO means "you decide
  -- from here", not "keep what I picked".
  local changed = state.mode ~= mode
  state.mode = mode

  if mode == "off" then
    state.kind, state.target, state.timer = nil, 0, 0
  elseif mode == "rain" or mode == "snow" then
    -- a pin: no clock at all, straight to a settled downpour
    state.kind, state.target = mode, 0.85
    state.timer = math.huge
  else
    -- Rolled dry on the first tick and on every arrival at AUTO, so a
    -- session never OPENS in the rain: weather already happening when you
    -- press START reads as a broken sky rather than as a shower.
    if changed then rollClear() end
    state.timer = state.timer - dt
    if state.timer <= 0 then
      if state.kind then rollClear() else rollWet() end
    end
  end

  -- ------- the ramp
  --
  -- Up over BUILD, down over CLEAR_FADE, and everything the weather touches
  -- is a function of the number this line moves -- which is why the sky, the
  -- light, the water and the air all arrive together.
  local want = state.target
  local rate = want > state.power and (1 / Weather.BUILD)
                                  or (1 / Weather.CLEAR_FADE)
  local step = rate * dt
  if math.abs(want - state.power) <= step then
    state.power = want
  else
    state.power = state.power + (want > state.power and step or -step)
  end
  -- Snapped to zero only while the power is FALLING, and that guard is not
  -- cosmetic: one frame of build at 60fps is dt/BUILD = about 0.0024, which
  -- is UNDER this floor -- so a clamp that ran on the way up as well put the
  -- ramp back to zero on every single frame and the shower never started.
  -- (It looked exactly like the row doing nothing, which is the failure mode
  -- worth naming: nothing threw, nothing logged, the sky simply stayed blue.)
  --
  -- And only when it has finished falling is the spell really over: `kind`
  -- outlives `target` by the whole fade, because the rain still coming down
  -- has to know what it is while it thins out.
  --
  -- Leaving rain (not snow) arms the post-rain spell once: rainbow and a
  -- short saturated sky. Snow does not leave a rainbow. Re-entering wet
  -- cancels any leftover post-rain so the two states never stack.
  if state.kind == "rain" then
    after.hadRain = true
  elseif state.kind == "snow" then
    after.hadRain = false
  end
  if state.kind and state.power > 0.08 then
    after.untilAbs = 0
  end
  if state.target == 0 and state.power <= 0.005 then
    local armAfter = after.hadRain
    state.power = 0
    state.kind = nil
    after.hadRain = false
    if armAfter then
      after.untilAbs = absNow() + Weather.AFTER_RAIN
    end
  end

  -- ------- what the world reads
  --
  -- Written every tick, including the ticks where it is zero: these are plain
  -- fields on two other modules, and a value left behind by a shower that
  -- ended would be a permanently overcast sky. Zeroed indoors as well, so
  -- walking into a house takes the gloom off with the rain.
  local out = openSky(ow and ow.map) and state.power or 0
  local visible = out > 0 and state.kind or nil
  DayNight.overcast = state.kind == "snow" and out * 0.75 or out
  -- The storm register, pushed the same way and on the same tick, so the
  -- purple sky and the flash are one fact rather than two that happen to
  -- coincide: this ramps over exactly the band STRIKE_ABOVE gates the
  -- lightning with, so a sky that has gone violet is by definition a sky that
  -- can strike. Snow never storms -- a blizzard is white, not bruised.
  local bruise = 0
  if state.kind == "rain" and out > Weather.STRIKE_ABOVE then
    bruise = (out - Weather.STRIKE_ABOVE) / (1 - Weather.STRIKE_ABOVE)
    if bruise > 1 then bruise = 1 end
  end
  DayNight.storm = bruise
  Water.wet = state.kind == "rain" and out or 0
  -- snow on the water is its own channel (veil + freeze target). Pushed the
  -- same way wet is, so Water never requires this file back.
  Water.snow = state.kind == "snow" and out or 0
  -- Natural wind drive: showers shove the air hard, snow less so, clear
  -- sky lets Wind fall back on diurnal/seasonal breeze alone. Pushed so
  -- Wind never requires this file (cycle).
  if Wind then
    local drive = 0
    if state.kind == "rain" then
      drive = out * 0.95
    elseif state.kind == "snow" then
      drive = out * 0.55
    end
    Wind.weatherDrive = drive
    -- and what the shower is LYING ON the grass, which is a different
    -- number from what it is doing to the air: water is weight and damping
    -- on a blade, and it is the falling rain that does it, so this is the
    -- shower's own power rather than the ground's accumulated wetness.
    -- (The settled snow half is pushed by GroundFX, off `cover` -- snow
    -- keeps bowing a tuft over long after the fall has stopped.)
    Wind.grassWet = state.kind == "rain" and out or 0
    if Wind.step then pcall(Wind.step, dt) end
  end
  if Water.step then pcall(Water.step, dt) end
  if ow and ow.player and Water.noteFoot then
    local fp = ow.player
    local fpx = fp.px or ((fp.cellX or 0) * 16)
    local fpz = fp.py or ((fp.cellY or 0) * 16)
    pcall(Water.noteFoot, fpx + 8, fpz + 8)
  end

  -- ------- lightning
  strike.at = strike.at + dt
  if strike.bolt then
    stepSparks(dt)
    if strike.at > Weather.FLASH_LEN + 0.25 then
      strike.bolt = nil
    end
  end
  if visible == "rain" and state.power >= Weather.STRIKE_ABOVE then
    strike.next = strike.next - dt
    if strike.next <= 0 then
      strike.next = Weather.STRIKE_EVERY_MIN
                    + rand() * (Weather.STRIKE_EVERY_MAX
                                - Weather.STRIKE_EVERY_MIN)
      -- far / sheet by default. rand^0.55 biases HIGH, so the sky
      -- lights up and the street in front of the player does not.
      armStrike(0.50 + rand() ^ 0.55 * 0.50)
    end
  elseif strike.next < 5 then
    strike.next = 5
  end

  -- ------- the world-space half
  --
  -- Splashes and flakes need a map to stand on and a player to stand near, so
  -- they stop the moment either is missing -- and they are dropped outright
  -- when the sky closes over, rather than left to drift indoors.
  -- The after-rain window keeps the world half alive: the sky is clear, so
  -- `visible` is nil and everything below used to be dropped outright --
  -- which would have thrown away the canopy drips on the frame the shower
  -- ended, i.e. exactly when they are the whole point.
  local dripAfter = 0
  do
    local okA, v = pcall(Weather.afterRain)
    if okA then dripAfter = tonumber(v) or 0 end
  end
  local canDraw = (visible or dripAfter > 0) and ow and ow.map and ow.player
                  and Game.stack and Game.stack:top() == ow
                  and not ow.transitioning
  if not canDraw then
    if #motes > 0 then motes = {} end
    if #drops > 0 then drops = {} end
    if #shafts > 0 then shafts = {} end
    return
  end

  local p = ow.player
  local px, pz = p.cellX * 16, p.cellY * 16

  -- one pass over the list, and every ceiling below reads off it
  census()

  -- The shower's own power, shaped, as the drop roll reads it. Shaped
  -- because power spends most of its ramp in the middle and the interesting
  -- half of the size range is the top: a linear read leaves a peak shower
  -- still rolling drizzle-sized drops.
  do
    local pw = state.power
    if pw < 0 then pw = 0 elseif pw > 1 then pw = 1 end
    Weather.dropPower = pw * pw * (3 - 2 * pw)
  end

  if visible == "rain" then
    stepShafts(ow, dt, state.power)
    -- a few ambient rings so the street still ticks when shafts are
    -- sparse (1/4 RES, the first second of a shower). The shafts do
    -- the rest by landing.
    local floor = math.floor(Weather.SPLASH_FLOOR * state.power)
    for _ = 1, math.max(0, floor - live.splash) do spawnSplash(ow) end
  elseif visible then
    if #shafts > 0 then shafts = {} end
    local want_n = math.floor(flakeCap() * state.power)
    for _ = 1, math.min(3, math.max(0, want_n - #motes)) do spawnFlake(ow) end
  else
    if #shafts > 0 then shafts = {} end
  end

  -- ------- the wood, still letting go of the last shower
  --
  -- Runs whether or not the sky is still doing something, because the
  -- window outlives the rain by design (AFTER_RAIN is three minutes) and
  -- because a shower tailing off into a dripping wood is the transition
  -- worth having. Budgeted by a live count rather than a rate limiter: the
  -- ceiling is what guarantees this cannot become the frame, and drips die
  -- on their own in under two seconds.
  if dripAfter > 0 and live.drip < dripCap() then
    local tries = Weather.DRIP_RATE * dripAfter * dt
    local whole = math.floor(tries)
    if rand() < tries - whole then whole = whole + 1 end
    for _ = 1, math.min(whole, dripCap() - live.drip) do
      spawnCanopyDrip(ow)
    end
  end

  -- ------- and the gutters, on their own clock (see THE EAVE above)
  --
  -- Driven by the shower while it runs and by the after-rain window once
  -- it stops -- the window SQUARED, because a roof drains in the first
  -- minute of the three the wood takes.
  do
    local drive = (visible == "rain") and state.power or 0
    local rate = Weather.EAVE_RATE
    local shed = dripAfter * dripAfter
    -- the after-rain window is the regime with no roof hits behind it, so
    -- it is also the one that needs the bigger dart rate (see EAVE_RATE_AFTER)
    if shed > drive then drive, rate = shed, Weather.EAVE_RATE_AFTER end
    -- under an open sky only: the after-rain window follows the player
    -- through doors, and a bookshelf is a lid too as far as surfaceAt can
    -- tell. (The canopy dart gets this for free -- no map has crown cover
    -- indoors -- but a lid is a lid everywhere.)
    if drive > 0.02 and live.drip < dripCap()
       and openSky(ow.map) then
      local tries = rate * drive * dt
      local whole = math.floor(tries)
      if rand() < tries - whole then whole = whole + 1 end
      for _ = 1, math.min(whole, dripCap() - live.drip) do
        spawnEaveDrip(ow)
      end
    end
  end

  local windAmt = 0
  local okw, n = pcall(Wind.amount)
  if okw then windAmt = n or 0 end

  for i = #motes, 1, -1 do
    local m = motes[i]
    m.t = m.t + dt
    -- a splash's ink outlives its burst (see THE INK): the mote stays for
    -- whichever clock runs longer
    local span = m.ttl
    if m.kind == "splash" and m.ink and m.ink > span then span = m.ink end
    local dead = m.t >= span
    if m.kind == "flake" then
      -- ------- A FLAKE DOES NOT FALL. IT TUMBLES.
      --
      -- What was here was two sines, one per axis, at nearly the same rate
      -- -- which traces a lopsided ellipse, so every flake in the sky was
      -- doing the same little circle at the same speed while descending at
      -- a constant rate. It reads as confetti on strings.
      --
      -- Real snow does something else, and it is the drag that does it. A
      -- flake is enormous for its weight, so it is not falling through the
      -- air so much as being held up by it, and its attitude keeps
      -- changing: broadside it stalls and slides, edge-on it drops. So the
      -- fall speed PULSES, and the horizontal path is a helix whose radius
      -- and rate are the flake's own -- two flakes side by side wander on
      -- different clocks, which is what makes falling snow look infinitely
      -- detailed from a handful of particles.
      --
      -- The wind is the field, not a constant: the same one the rain and
      -- the grass read, so a gust carries the snow across the meadow in a
      -- sheet and the meadow bends under the same sheet.
      local swing = math.sin(m.t * m.rate + m.seed)
      local stall = 0.62 + 0.38 * math.abs(math.sin(m.t * m.rate * 0.5 + m.seed))
      m.y = m.y - m.fall * stall * dt
      local ax, az = Wind.flowAt(m.x, m.z)
      -- Snow answers the air far more readily than rain does -- there is
      -- almost no mass to lag -- but not instantly, or a flake would be a
      -- speck of wind rather than a thing being blown.
      local k = dt / 0.35
      if k > 1 then k = 1 end
      m.vx = (m.vx or 0) + (ax * Weather.SNOW_CARRY - (m.vx or 0)) * k
      m.vz = (m.vz or 0) + (az * Weather.SNOW_CARRY - (m.vz or 0)) * k
      -- the helix, across the bearing so it is a wander and not a shove
      local wx = -(Wind.DIR[2] or 0) * swing * m.wob
      local wz = (Wind.DIR[1] or 1) * swing * m.wob
      m.x = m.x + (m.vx + wx) * dt
      m.z = m.z + (m.vz + wz) * dt
      m.spin = (m.spin or 0) + dt * m.rate * 0.6
      -- and it lands ON something rather than at world zero, which on a
      -- town's raised paving is sixteen pixels underground
      if m.y <= (m.yLand or 0) then
        m.y = m.yLand or 0
        -- settle: a flake that has arrived stops moving and goes out over
        -- a moment, so the ground edge is snow arriving rather than snow
        -- being deleted at a plane
        m.settled = (m.settled or 0) + dt
        if m.settled > 0.5 then dead = true end
      end
    elseif m.kind == "eject" then
      -- a thrown drop, on nothing but gravity: this is the one place in
      -- this file where the arc is the whole point, so it is integrated
      -- properly rather than faked with a sine
      m.vy = m.vy - Weather.EJECT_G * dt
      m.x = m.x + m.vx * dt
      m.z = m.z + m.vz * dt
      m.y = m.y + m.vy * dt
      if m.vy < 0 and m.y <= (m.yLand or 0) then dead = true end
    elseif m.kind == "drip" then
      -- the bead first: an eave drop hangs and swells before it lets go,
      -- and while it hangs it does not move (a canopy drip has no hang --
      -- a leaf tips, the water is simply gone)
      if m.hang and m.hang > 0 then
        m.hang = m.hang - dt
      else
        m.y = m.y - (m.fall or 80) * dt
      end
      if m.y <= (m.yLand or 0) then
        -- on whatever is actually down there: the stone burst, the grass
        -- flick, a pool's ring. "ground" -- a surface pushImpact has no
        -- drawing for -- is what every drip used to land as, which made
        -- the landing, the half of a drip you are looking at, invisible.
        splashFromHit(m.x, m.z, m.yLand or 0, m.surf or "stone")
        dead = true
      end
    end
    if not dead and (math.abs(m.x - px) > 200 or math.abs(m.z - pz) > 200) then
      dead = true
    end
    if dead then table.remove(motes, i) end
  end
end

function Weather.update(dt)
  Weather.ticks = Weather.ticks + 1
  if failed then return end
  local ok, err = pcall(tick, dt or 0)
  if ok then Weather.ticksOk = Weather.ticksOk + 1 else lastErr = err end
  -- ------- ASK FOR THE FRAME'S DEPTH, BUT ONLY WHILE IT IS RAINING
  --
  -- The readable depth buffer is a whole extra attachment, and until now
  -- only RayFX ever wanted one -- at RTX OFF the pass allocated nothing.
  -- Rather than make that unconditional, the weather asks per frame and
  -- only while it has something to draw, so a clear sky at RTX OFF costs
  -- exactly what it always did. Set in UPDATE rather than in draw because
  -- beginScene binds its attachments before anything is painted.
  do
    local m = voxel3D()
    if m then
      m.wantDepth = (state.kind ~= nil) or (#motes > 0)
    end
  end
  if ok then return end
  failed = true
  state.kind, state.power, state.target = nil, 0, 0
  after.untilAbs, after.hadRain = 0, false
  DayNight.overcast, Water.wet, Water.snow = 0, 0, 0
  if Wind then Wind.weatherDrive, Wind.grassWet = 0, 0 end
  if Water.freeze then Water.freeze = 0 end
  drops, motes, shafts = {}, {}, {}
  if V.mod and V.mod.log then
    V.mod.log:warn("weather failed: %s -- the sky is clear for this session",
                   tostring(err))
  end
end

-- ------- the screen-space half
--
-- Shared by both draw paths below, because rain on the diorama and rain on
-- the flat 2D world are the same rain and must not be two different effects.
-- `w`,`h` are whatever surface is being drawn into: the scene canvas at its
-- rasterised size in voxel mode, the window in flat mode.
--
-- Motion model (Unity particle rain, cel port):
--   velocity = fall * layerSpeed * powerCurve + wind force on X
--   stretch  = length scales with |velocity| (motion-blur streak)
--   turb     = small lateral sine so paths are not parallel rulers
--   recycle  = volume re-emit above the frame (continuous rate-over-time)
local function stepDrops(w, h, dt, power)
  -- Heavier than linear at low power so a drizzle still reads; soft-caps
  -- density at full so the max stays a downpour not a whiteout.
  local dens = power * (0.55 + 0.45 * power)
  local want = math.floor(Weather.STREAKS * dens * (w * h) / (320 * 288))
  if want > Weather.STREAKS_MAX then want = Weather.STREAKS_MAX end
  local first = #drops == 0
  for _ = 1, math.max(0, want - #drops) do spawnDrop(w, h, first) end
  while #drops > want do table.remove(drops) end

  local lean = slant()
  local wAmt, wDx = windForce()
  -- ------- the mist and the shower have to be in the same wind
  --
  -- These drops have no world position -- that is the whole point of them,
  -- they are the air between the camera and the near edge -- so they
  -- cannot ask the field where THEY are. They ask where the PLAYER is,
  -- which is the one world point this half of the rain can honestly claim
  -- to be near, and they ride the band that is passing over it.
  --
  -- Without this the mist sat on the flat global wind while the shafts
  -- behind it swung with the gusts, and a squall crossing the frame
  -- visibly stopped at the near plane.
  local band = 1
  do
    local Game = game()
    local ow = Game and Game.overworld
    local p = ow and ow.player
    if p then
      local _, _, b = Wind.flowAt((p.cellX or 0) * 16, (p.cellY or 0) * 16)
      if b and b > 0 then band = b end
    end
  end
  local scale = math.max(1, h / 288)
  local t = 0
  if love.timer and love.timer.getTime then t = love.timer.getTime() end
  for _, d in ipairs(drops) do
    -- legacy drops (pre-layer) keep working
    local spd = d.speed or 1
    local v = Weather.FALL * spd * scale * (0.55 + 0.45 * power)
    -- near layer falls a touch faster (closer = higher terminal feel)
    if d.layer == "near" then
      v = v * 1.12
    elseif d.layer == "far" then
      v = v * 0.78
    end
    -- wind force over lifetime, on the band passing over the player rather
    -- than on a flat global figure -- so the near mist leans with the gust
    -- the shafts behind it are leaning with
    local vx = v * lean * band + wDx * wAmt * v * 0.12 * band
    local seed = d.seed or 0
    local turb = math.sin(t * (2.1 + spd) + seed) * v * Weather.TURB
    d.x = d.x + (vx + turb) * dt
    d.y = d.y + v * dt
    d.phase = ((d.phase or 0) + dt * (0.7 + spd * 0.4)) % 1
    -- cache velocity for stretch draw
    d._vx, d._vy = vx + turb, v
    if d.y > h + 8 then
      -- re-emit in the box above the frame (continuous particle recycle)
      d.y = -d.len * scale - rand() * h * 0.35
      d.x = rand() * (w + h * 0.7) - h * 0.35
      d.phase = rand()
      d.seed = rand() * 6.2832
    end
  end
end

-- Depth order: far → mid → near so nearer streaks overdraw farther ones
-- (two particle systems stacked, same idea as Unity camera-sorted layers).
local LAYER_ORDER = { far = 1, mid = 2, near = 3 }
local function layerRank(d)
  return LAYER_ORDER[d.layer or (d.near and "near" or "far")] or 2
end
-- ------- A RAIN STREAK IS A NEEDLE, NOT A BAR
--
-- What was here was `setLineWidth` + `g.line`, and a thick LOVE line is a
-- rectangle with square ends -- so every drop in the world was a white
-- stick of even brightness that stopped dead at both ends. Zoomed in on a
-- rain screenshot they read as poles standing in the air, which is exactly
-- what a rectangle is.
--
-- A falling drop does not look like that. It is brightest and widest where
-- the water is, and behind it is a thinning trail of where it just was. So
-- this draws a QUAD that is wide at the head and comes to a point at the
-- tail -- one draw call, same as the line it replaces, and the shape does
-- the work.
--
-- The bright head is a SECOND short needle rather than the square that
-- used to be stamped over the tip. A square head on a slanted streak sits
-- crooked on it at every angle except vertical, which was most of what
-- made the near drops look pasted on.
--
-- Two flat tones and no gradient, which is this file's rule and the right
-- one: a soft-edged raindrop over a cel-shaded diorama reads as a photo
-- filter. A taper is a SHAPE, not a blur.
-- ONE MESH FOR THE WHOLE SHOWER, and the colour lives in the vertices.
--
-- Three problems solved by the same change, which is why it is a mesh and
-- not another loop of primitives:
--
--   IT LOOKED PAINTED. Every drop was one flat colour from end to end, so
--   the field read as white sticks lying on the picture. Water does not
--   look like that: a falling drop is bright where the water IS and fades
--   to nothing along the trail behind it. Per-vertex alpha gives that for
--   free -- the head vertices carry the light, the tail vertices carry
--   almost none, and the hardware interpolates between them. There is no
--   way to draw that with a line or a polygon, which take one colour.
--
--   IT LOOKED OPAQUE. Rain is nearly clear: you see it because it CATCHES
--   light, not because it covers what is behind it. So this draws
--   ADDITIVE -- it brightens the trees and the sky rather than painting
--   over them -- which is also why the alphas below are far lower than the
--   ones the old opaque draw needed.
--
--   IT COST A DRAW CALL PER DROP. A hundred-odd setColor/line pairs per
--   frame is what kept the counts down, and thin rain is exactly what
--   makes a shower look fake. One buffer, one draw, and the density stops
--   being the thing being rationed.
--
-- g.polygon is also gone, and not only for cost: LOVE throws on a fill it
-- considers degenerate or self-intersecting, so a streak that happened to
-- collapse took the whole driver down mid-run. A mesh has no such opinion.
-- ------- A RAINDROP IS A LENS, NOT A LIGHT
--
-- Everything above draws the streak as ADDED light: a pale quad that
-- brightens whatever is behind it. That is a fair model of the highlight a
-- drop carries and a poor model of the drop, and the difference is the
-- whole of "it looks like a white thing falling out of the sky".
--
-- Water is CLEAR. You do not see a raindrop because it glows; you see it
-- because it is a little cylinder of glass hanging in the air, and three
-- things happen at once when you look through one:
--
--   IT BENDS what is behind it. A cylinder is a lens. The bend is zero
--   straight through the middle, grows toward the edge, and is worth the
--   most at about seventy per cent of the way out -- so a drop carries a
--   smeared, sideways-shifted little picture of the world behind it. This
--   is the part no amount of colour tuning can fake, because it is
--   parallax, and parallax needs the background.
--
--   IT CATCHES ONE HIGHLIGHT. A specular line down the side facing the
--   light, not an even glow along the whole width. A single bright edge is
--   what says "curved and wet"; an even glow says "drawn with a pen".
--
--   ITS RIM GOES DARK. At a grazing angle the surface stops transmitting
--   and starts reflecting away from you, so the outline of a drop is
--   DARKER than the sky behind it. Dark edges are most of what makes water
--   read as an object at all, and an additive quad can only ever get
--   brighter.
--
-- So the mesh carries two more things per vertex: where across the streak's
-- WIDTH the fragment is, and which way "across" points on screen. With
-- those the fragment shader can do all three, sampling a copy of the frame
-- taken just before the rain went on.
--
-- The additive path stays, unchanged, as the fallback: if the shader will
-- not compile on somebody's driver, or the copy cannot be made, the rain
-- is the pale quad it was rather than nothing.
local RAIN_FMT = {
  { "VertexPosition", "float", 2 },
  -- x: -1..1 across the streak. y: 0 at the head, 1 at the tail.
  { "VertexTexCoord", "float", 2 },
  { "VertexColor", "float", 4 },
  -- unit vector, in screen pixels, pointing across the streak. Carried
  -- per-vertex rather than derived in the shader because screen-space
  -- derivatives are an extension on some of the drivers this has to run on,
  -- and this costs two floats.
  { "RainPerp", "float", 2 },
  -- ------- AND HOW FAR AWAY THIS PIECE OF WATER ACTUALLY IS
  --
  -- Everything in this buffer is drawn in SCREEN space: rings, jets,
  -- crowns and needles, worked out in pixels and pushed as flat quads.
  -- That is why they could never be handed to the depth test as geometry
  -- the way the wind field was -- and it is also why, until now, rain fell
  -- inside houses and splashes landed on top of the wall in front of them.
  --
  -- The fix is not to move them. It is to give each vertex the DEVICE
  -- depth of the world point it stands for (Voxel3D.projectDepth), so the
  -- shader can ask the frame's own depth buffer whether something is
  -- already in front of it. One float, and nothing about how the water is
  -- drawn has to change -- the refraction, the additive buffer and the
  -- tapered needle all survive intact.
  { "RainDepth", "float", 1 },
}
local rainV, rainMesh, rainN, rainCap = {}, nil, 0, 0

-- ------- the refraction shader
--
-- Sampled against `behind`, which is a copy of the frame taken immediately
-- before the rain is drawn over it. A canvas cannot be read and written in
-- the same pass, which is the only reason the copy exists.
Weather.REFRACT = 9.0        -- how far a drop shifts what is behind it, px
Weather.REFRACT_ALPHA = 3.4  -- the additive alphas, re-based for alpha blend
Weather.SPEC = 1.15          -- the highlight down the lit side
-- The glint on the drop ITSELF rather than on its trail, and it is the
-- largest of these numbers on purpose. A streak is one drop plus the
-- afterimage of where it just was; the drop is the only part with water in
-- it, and a field where the heads read and the tails only suggest is what
-- separates rain from a set of ruled lines.
Weather.HEAD = 0.90
Weather.GAIN = 1.22          -- a lens gathers: how much brighter than behind
Weather.RIM = 0.30           -- how dark the outline goes
-- Which side the highlight sits on. Mostly horizontal on purpose: the light
-- in this world is high, and a highlight from straight above lands on the
-- TOP of a vertical cylinder, which is the one part of a falling streak the
-- camera cannot see.
Weather.LIGHT_DIR = { -0.90, -0.44 }

local RAIN_GLSL = [[
extern Image behind;
extern vec2 behindSize;
extern float refractPx;
extern vec2 lightDir;
extern float specAmt;
extern float rimAmt;
extern float gainAmt;
extern float headAmt;

extern Image sceneDepth;
extern vec2 depthSize;
// 0 disables the test outright -- no buffer this frame, or a draw whose
// screen coordinates do not correspond to it (see Weather.present).
extern float depthOn;
extern float depthBias;

varying vec2 vPerp;
varying float vDepth;

#ifdef VERTEX
attribute vec2 RainPerp;
attribute float RainDepth;
vec4 position(mat4 transform_projection, vec4 vertex_position)
{
  vPerp = RainPerp;
  vDepth = RainDepth;
  return transform_projection * vertex_position;
}
#endif

#ifdef PIXEL
vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 sc)
{
  // ------- IS THERE ALREADY SOMETHING IN FRONT OF THIS DROP?
  //
  // The frame's own depth buffer, sampled where this fragment is, against
  // the depth of the world point this fragment stands for. Larger is
  // further (GL device depth, the same [0,1] RayFX reverses with
  // d*2.0-1.0), so a fragment deeper than what is already there is behind
  // it and must not be painted.
  //
  // The bias is not tuning-by-feel: a splash sits ON the surface it landed
  // on, at the same depth as the ground the pass already wrote, and
  // without a little slack every impact would self-occlude and the whole
  // effect would disappear on contact with the thing it is an effect ABOUT.
  if (depthOn > 0.5) {
    float scene = Texel(sceneDepth, sc / depthSize).r;
    if (vDepth > scene + depthBias) discard;
  }
  float u = clamp(uv.x, -1.0, 1.0);
  float body = 1.0 - u * u;              // the cylinder's cross-section
  if (body <= 0.002) discard;
  float rad = sqrt(body);

  // The sideways shift a ray picks up crossing a cylinder: zero through
  // the axis, greatest near the rim, and it reverses sign across the
  // middle -- which is what makes the background behind a drop look
  // pinched rather than merely blurred.
  float bend = u * rad;
  vec2 off = vPerp * (bend * refractPx) / behindSize;
  vec3 back = Texel(behind, sc / behindSize + off).rgb;

  // What the water does to what it is magnifying: the drop's own tint (the
  // hour's light is already folded into vcolor by rainLight) and real
  // gain, because a lens GATHERS -- which is the only reason rain is
  // visible against a bright sky at all.
  vec3 wet = back * vcolor.rgb * gainAmt;

  // ------- one bright line down the lit side
  //
  // The first cut of this multiplied u by the raw dot product and raised
  // the result to the sixteenth. The dot between a near-vertical streak's
  // perpendicular and the light never exceeds about 0.87, and 0.87 shifted
  // and raised to the sixteenth is under a tenth -- so the highlight was
  // arithmetically dead and the rain came out as dark violet scratches. It
  // is the SIDE that the light picks, not the strength: which edge, then a
  // full-range falloff across the width from that edge.
  float lit = sign(dot(vPerp, lightDir));
  float su = u * lit;                     // +1 on the lit edge, -1 opposite
  float spec = pow(max(0.0, su * 0.5 + 0.5), 9.0);
  wet += vcolor.rgb * spec * specAmt;

  // ------- and the head is where the water actually IS
  //
  // uv.y runs 0 at the head and 1 at the tail. A streak is not a uniform
  // rod: it is a drop, plus the afterimage of where that drop just was. The
  // drop end has to carry a real highlight or the whole thing reads as a
  // scratch rather than as something falling.
  float head = pow(1.0 - uv.y, 3.0);
  wet += vcolor.rgb * head * rad * headAmt;

  // and the rim darkens: past the grazing angle the surface stops
  // transmitting toward the eye
  float rim = smoothstep(0.70, 1.0, abs(u));
  wet *= 1.0 - rim * rimAmt;

  // Coverage: full through the middle of the drop, tapering at the edges
  // so the quad does not read as a rectangle with a picture in it.
  float a = vcolor.a * (0.28 + 0.72 * rad);
  return vec4(wet, a);
}
#endif
]]

-- Probe switch. The lens is a full-screen copy plus a texture fetch per
-- rain fragment with heavy overdraw, and "how much does it cost" is not a
-- question a screenshot answers -- it has to be measured against the same
-- frame with it off, on the same map, in the same weather.
Weather.lens = true

local rainShader = nil       -- Shader | false (tried and failed)
local behindCanvas = nil     -- the copy of the frame under the rain
local behindW, behindH = 0, 0
-- ONE copy per frame, and this flag is what enforces it.
--
-- The buffer is flushed two or three times in a frame -- the world shafts,
-- the near mist, and the splash fallback are separate passes over the same
-- mesh -- and the copy was being taken inside the flush, so a frame of rain
-- was costing three full-screen copies instead of one. Weather.draw takes
-- it once, at the top, and clears this on the way out.
local behindReady = false

-- ------- THE SAME TEST, WITHOUT THE LENS
--
-- REFRACT is a row the player can turn off, and the plain additive path
-- has no shader at all -- which would mean occlusion arrives only for
-- people who left the lens on. So the additive draw gets a shader whose
-- entire job is the depth test: same attribute, same compare, and the
-- colour handed straight back.
--
-- It is a separate program rather than a branch in the big one because the
-- additive path is the CHEAP path, chosen on the machines least able to
-- afford the lens, and paying for the refraction shader's texture fetch
-- and its cylinder maths to then throw them away is exactly backwards.
local DEPTH_GLSL = [==[
extern Image sceneDepth;
extern vec2 depthSize;
extern float depthOn;
extern float depthBias;

varying float vDepth;

#ifdef VERTEX
attribute float RainDepth;
vec4 position(mat4 transform_projection, vec4 vertex_position)
{
  vDepth = RainDepth;
  return transform_projection * vertex_position;
}
#endif

#ifdef PIXEL
vec4 effect(vec4 vcolor, Image tex, vec2 uv, vec2 sc)
{
  if (depthOn > 0.5) {
    float scene = Texel(sceneDepth, sc / depthSize).r;
    if (vDepth > scene + depthBias) discard;
  }
  float u = clamp(uv.x, -1.0, 1.0);
  float body = 1.0 - u * u;
  if (body <= 0.002) discard;
  return vcolor;
}
#endif
]==]

local depthShader = nil

local function depthOnlyShader()
  if depthShader ~= nil then return depthShader or nil end
  if not (love.graphics and love.graphics.newShader) then
    depthShader = false
    return nil
  end
  local ok, sh = pcall(love.graphics.newShader, DEPTH_GLSL)
  depthShader = (ok and sh) or false
  return depthShader or nil
end

-- Whether the frame's depth buffer corresponds to the surface being drawn
-- on right now. Set by Weather.draw and cleared by Weather.present -- see
-- the note there: the tilt-shift path paints the rain onto a DIFFERENT,
-- already-blurred surface, where the scene's depth is no longer a fact
-- about the pixels underneath.

-- How much slack a fragment gets before it counts as behind. A splash sits
-- ON the ground the pass already wrote, at the same depth, so with no
-- slack every impact would occlude itself. Device depth is nonlinear and
-- crowds toward 1 with distance, so this is small.
Weather.DEPTH_BIAS = 0.0012

-- Is there a depth texture at all this frame? Kept apart from the grid
-- check below on purpose: conflating "there is a buffer" with "it applies
-- to this surface" made the first probe report both false at once and say
-- nothing about which had actually failed.
local function rawDepthTex()
  local m = voxel3D()
  if not (m and m.sceneDepthTex) then return nil end
  local ok, t = pcall(m.sceneDepthTex)
  return ok and t or nil
end

-- ------- WHEN IS THE FRAME'S DEPTH A FACT ABOUT THESE PIXELS?
--
-- The first answer here was "in the ordinary path, but not under
-- T-SHIFT", on the reasoning that the tilt-shift paints the rain onto an
-- already-blurred canvas. That reasoning was wrong, and it mattered: the
-- saved options on the machine this was written on have T-SHIFT at 3, so
-- the test armed on exactly zero frames and the whole thing measured
-- nothing.
--
-- A blur changes what colour a pixel is. It does not move anything. The
-- depth buffer says where the world is, and after a blur the world is
-- still there -- so the test is perfectly valid on the blurred surface
-- too. What actually has to hold is narrower and checkable: the surface
-- being painted must be the same GRID as the depth texture, because the
-- shader indexes one with the other's coordinates. Same width, same
-- height, or the lookup is reading somewhere else.
--
-- So the question is asked of the canvas rather than of the call path,
-- which also means a future third draw path gets the right answer without
-- anyone remembering to teach it.
local function depthGridMatches(dw, dh)
  local g = love.graphics
  if not g.getCanvas then return false end
  local target = g.getCanvas()
  if type(target) == "table" then target = target[1] end
  if not (target and target.getDimensions) then return false end
  local tw, th = target:getDimensions()
  return tw == dw and th == dh
end

-- Whether the last flush actually armed the test. The conditions are only
-- knowable DURING a draw, so a probe asking between frames could never
-- work it out for itself -- this is the fact it actually wants.
local depthArmed = false

local function sendDepth(sh)
  depthArmed = false
  local tex = rawDepthTex()
  if tex and tex.getDimensions then
    local w, h = tex:getDimensions()
    if depthGridMatches(w, h) then
      pcall(sh.send, sh, "sceneDepth", tex)
      pcall(sh.send, sh, "depthSize", { w, h })
      pcall(sh.send, sh, "depthOn", 1)
      pcall(sh.send, sh, "depthBias", Weather.DEPTH_BIAS)
      depthArmed = true
      return true
    end
  end
  pcall(sh.send, sh, "depthOn", 0)
  return false
end

-- What the depth test is doing, for probes: whether the last flush armed
-- it, and whether a buffer exists at all right now. Separate, because
-- "no buffer" and "wrong surface" are different failures with different
-- fixes, and the first version of this returned false for both and sent
-- the search off after the wrong one.
-- The live caps this frame, for probes and for the row's own proof: the
-- PFX row is only doing something if these move when it moves.
function Weather.budgets()
  return shaftBudget(), splashCap(), flakeCap(), dripCap(), pfxMul()
end

-- Whether the tick has latched off, and the error that did it. `failed` is
-- sticky by design -- a weather system throwing every frame would be worse
-- than a clear sky -- which also means one bad frame at boot silences it
-- for the whole session, and that is exactly the failure a probe cannot
-- see from the outside.
function Weather.failState()
  return failed, lastErr and tostring(lastErr) or nil
end

function Weather.depthTestState()
  return depthArmed, rawDepthTex() and true or false
end

local function refractShader()
  if not Weather.lens then return nil end
  if rainShader ~= nil then return rainShader or nil end
  if not (love.graphics and love.graphics.newShader) then
    rainShader = false
    return nil
  end
  local ok, sh = pcall(love.graphics.newShader, RAIN_GLSL)
  rainShader = (ok and sh) or false
  return rainShader or nil
end

-- ------- the copy the shader reads
--
-- Takes whatever canvas is currently bound, copies it, and rebinds. Both
-- draw paths land here -- the one inside the diorama and the one after the
-- tilt-shift -- so the rain refracts whatever is actually underneath it in
-- either, rather than only in the one that happens to be handed a canvas.
--
-- Returns nil when there is no canvas to copy (the flat 2D world, a
-- headless probe), and the refraction quietly stands down to the additive
-- path rather than failing.
local function captureBehind()
  if behindReady then return behindCanvas end
  local g = love.graphics
  if not (g.getCanvas and g.newCanvas) then return nil end
  local target = g.getCanvas()
  if type(target) == "table" then target = target[1] end
  if not target or not target.getDimensions then return nil end
  local w, h = target:getDimensions()
  if w < 1 or h < 1 then return nil end
  if behindCanvas == nil or behindW ~= w or behindH ~= h then
    local okC, c = pcall(g.newCanvas, w, h)
    if not okC then return nil end
    behindCanvas, behindW, behindH = c, w, h
  end
  local pm, pa = g.getBlendMode()
  if not pcall(g.setCanvas, behindCanvas) then return nil end
  g.setBlendMode("replace", "premultiplied")
  g.setColor(1, 1, 1, 1)
  g.draw(target)
  g.setBlendMode(pm, pa)
  if not pcall(g.setCanvas, target) then
    pcall(g.setCanvas)
    return nil
  end
  behindReady = true
  return behindCanvas
end

-- The device depth of a world point, or nil when the camera cannot see
-- it. nil is what rainPush reads as "further than anything", which leaves
-- the fragment untestable rather than hidden -- the right answer for a
-- frame with no 3D pass at all (the flat 2D world, a headless probe).
local function projectDepth(wx, wy, wz)
  local m = voxel3D()
  if not (m and m.projectDepth) then return nil end
  local ok, d = pcall(m.projectDepth, wx, wy, wz)
  return ok and d or nil
end

local function rainReset(maxQuads)
  local need = maxQuads * 6
  if need > rainCap then
    -- The vertex tables are allocated ONCE and mutated in place from then
    -- on. Rebuilding them per frame would put a few thousand short-lived
    -- tables a second in front of the GC, on the machine least able to
    -- afford it.
    for i = rainCap + 1, need do
      rainV[i] = { 0, 0, 0, 0, 1, 1, 1, 0, 0, 0 }
    end
    rainCap = need
    rainMesh = nil
  end
  if rainMesh == nil and love.graphics and love.graphics.newMesh then
    local ok, m = pcall(love.graphics.newMesh, RAIN_FMT, rainV,
                        "triangles", "stream")
    rainMesh = (ok and m) or false
  end
  rainN = 0
end

-- One streak: a quad, wide and bright at the head, narrow and transparent
-- at the tail.
-- The depth every push inherits when it does not name one.
--
-- An impact is a dozen strokes -- a crown of spokes, a jet, two or three
-- rings -- and all of them belong to ONE mote at one world point. Threading
-- a depth argument through pushRing, the spoke loop and the jet would be
-- the same value written out in ten places and forgotten in the eleventh.
-- The shafts, which genuinely differ head to tail, pass theirs explicitly.
local pushZ = nil

local function rainPush(hx, hy, ux, uy, w, r, g, b, aH, aT, dH, dT)
  if not rainMesh then return end
  local i = rainN * 6
  if i + 6 > rainCap then return end
  local dx, dy = hx - ux, hy - uy
  local l2 = dx * dx + dy * dy
  if l2 < 0.25 then return end
  local inv = 1 / math.sqrt(l2)
  local px, py = -dy * inv, dx * inv
  local hw = w * 0.5
  local tw = hw * 0.22
  local h1x, h1y = hx + px * hw, hy + py * hw
  local h2x, h2y = hx - px * hw, hy - py * hw
  local t1x, t1y = ux + px * tw, uy + py * tw
  local t2x, t2y = ux - px * tw, uy - py * tw
  -- px, py is the SAME perpendicular the four corners were offset along, so
  -- the shader knows which way "across the drop" points on screen without
  -- having to work it out from screen-space derivatives.
  --
  -- Written out six times rather than through a local helper, and that is
  -- not stubbornness: this runs several hundred times a frame, and a
  -- closure declared inside it is several hundred allocations a frame put
  -- in front of the GC on the machine least able to afford them -- which is
  -- the same reasoning that made the vertex tables permanent above.
  -- Depth rides the vertex the same way the perpendicular does, and the
  -- head and the tail get their OWN: a near-vertical needle can easily
  -- have its head in front of a fence and its tail behind it, and one
  -- depth for the whole quad would make the whole streak pick a side.
  -- 1.0 is "further than anything", which is what a caller that cannot
  -- work out a depth should leave behind -- the shader treats it as
  -- untestable rather than as hidden.
  local zH = dH or pushZ or 1
  local zT = dT or zH
  local v
  v = rainV[i + 1]
  v[1] = h1x; v[2] = h1y; v[3] =  1; v[4] = 0
  v[5] = r; v[6] = g; v[7] = b; v[8] = aH; v[9] = px; v[10] = py; v[11] = zH
  v = rainV[i + 2]
  v[1] = h2x; v[2] = h2y; v[3] = -1; v[4] = 0
  v[5] = r; v[6] = g; v[7] = b; v[8] = aH; v[9] = px; v[10] = py; v[11] = zH
  v = rainV[i + 3]
  v[1] = t2x; v[2] = t2y; v[3] = -1; v[4] = 1
  v[5] = r; v[6] = g; v[7] = b; v[8] = aT; v[9] = px; v[10] = py; v[11] = zT
  v = rainV[i + 4]
  v[1] = h1x; v[2] = h1y; v[3] =  1; v[4] = 0
  v[5] = r; v[6] = g; v[7] = b; v[8] = aH; v[9] = px; v[10] = py; v[11] = zH
  v = rainV[i + 5]
  v[1] = t2x; v[2] = t2y; v[3] = -1; v[4] = 1
  v[5] = r; v[6] = g; v[7] = b; v[8] = aT; v[9] = px; v[10] = py; v[11] = zT
  v = rainV[i + 6]
  v[1] = t1x; v[2] = t1y; v[3] =  1; v[4] = 1
  v[5] = r; v[6] = g; v[7] = b; v[8] = aT; v[9] = px; v[10] = py; v[11] = zT
  rainN = rainN + 1
end

local function rainFlush()
  if not rainMesh or rainN == 0 then return end
  local g = love.graphics
  rainMesh:setVertices(rainV)
  rainMesh:setDrawRange(1, rainN * 6)
  local pm, pa = g.getBlendMode()

  -- ------- the refractive draw, and why it is alpha and not add
  --
  -- Added light can only ever brighten. A drop has to be able to DARKEN --
  -- its rim does, and the picture it bends into view is whatever colour
  -- that picture happens to be, which over a dark hedge is dark. So the
  -- refractive path composites normally and carries the whole result,
  -- background included, in its own colour.
  --
  -- The alphas were tuned for additive, where they are a share of a
  -- highlight; here they are coverage, and coverage of a third reads as no
  -- drop at all. REFRACT_ALPHA re-bases them.
  local sh = refractShader()
  local back = sh and captureBehind() or nil
  if sh and back then
    local okS = pcall(g.setShader, sh)
    if okS then
      pcall(sh.send, sh, "behind", back)
      pcall(sh.send, sh, "behindSize", { behindW, behindH })
      pcall(sh.send, sh, "refractPx", Weather.REFRACT)
      pcall(sh.send, sh, "lightDir", Weather.LIGHT_DIR)
      pcall(sh.send, sh, "specAmt", Weather.SPEC)
      pcall(sh.send, sh, "rimAmt", Weather.RIM)
      pcall(sh.send, sh, "gainAmt", Weather.GAIN)
      pcall(sh.send, sh, "headAmt", Weather.HEAD)
      sendDepth(sh)
      g.setBlendMode("alpha", "alphamultiply")
      g.setColor(1, 1, 1, Weather.REFRACT_ALPHA)
      g.draw(rainMesh)
      pcall(g.setShader)
      g.setBlendMode(pm, pa)
      g.setColor(1, 1, 1, 1)
      return
    end
  end

  -- the cheap path, and it still gets the test (see DEPTH_GLSL)
  local dsh = depthOnlyShader()
  local pushed = false
  if dsh then
    if pcall(g.setShader, dsh) then
      sendDepth(dsh)
      pushed = true
    end
  end
  g.setBlendMode("add", "alphamultiply")
  g.setColor(1, 1, 1, 1)
  g.draw(rainMesh)
  if pushed then pcall(g.setShader) end
  g.setBlendMode(pm, pa)
end


local function drawDrops(h, power)
  if power <= 0.01 or #drops == 0 then return end
  local g = love.graphics
  local scale = math.max(1, h / 288)
  rainReset(#drops)

  -- cheap insertion order: partition into three buckets (no full sort)
  local buckets = { {}, {}, {} }
  for i = 1, #drops do
    local d = drops[i]
    local b = buckets[layerRank(d)]
    b[#b + 1] = d
  end

  for bi = 1, 3 do
    local list = buckets[bi]
    for i = 1, #list do
      local d = list[i]
      local c
      if d.layer == "near" or d.near then
        c = Weather.RAIN_NEAR
      elseif d.layer == "mid" then
        c = Weather.RAIN_MID
      else
        c = Weather.RAIN_FAR
      end
      local vx = d._vx or 0
      local vy = d._vy or (Weather.FALL * (d.speed or 1) * scale)
      local speed = math.sqrt(vx * vx + vy * vy)
      -- stretch-to-velocity: faster drops leave a longer streak
      local stretch = speed * Weather.STRETCH / math.max(1, scale)
      if stretch < Weather.STRETCH_MIN then stretch = Weather.STRETCH_MIN end
      if stretch > Weather.STRETCH_MAX then stretch = Weather.STRETCH_MAX end
      local baseLen = (d.len or 10) * scale * (0.65 + 0.55 * power)
      local len = baseLen * stretch
      -- direction of travel (align streak to velocity, not a fixed lean)
      local inv = 1 / math.max(1e-3, speed)
      local dx = vx * inv * len
      local dy = vy * inv * len
      -- alpha shimmer (colour-over-lifetime analogue, hard steps)
      local shim = 0.82 + 0.18 * math.sin((d.phase or 0) * 6.2832)
      local a = (d.alpha or 0.4) * power * shim
      local thick = (d.thick or 1) * scale
      -- Head is where the drop IS (x+dx, y+dy); the tail is where it came
      -- from. Same buffer as the world shafts, so the mist in front of the
      -- camera and the rain behind it are one drawing at two scales rather
      -- than two different-looking rains in one frame.
      local head = c
      if d.layer == "near" or d.near then head = Weather.RAIN_CORE end
      rainPush(d.x + dx, d.y + dy, d.x, d.y, thick,
               head[1], head[2], head[3],
               a * Weather.ADD_HEAD, a * Weather.ADD_TAIL)
    end
  end
  rainFlush()
end

-- World-space shafts: project the drop and a point `len` above it (upwind
-- of the wind), draw a cel line between them. Far / mid / near by the
-- layer the spawn picked, so a near drop overdraws a far one without a
-- full sort. No depth test -- this is the overlay -- so the collision
-- against the roof is what stops a shaft falling through the Mart.
local function drawShafts(project, scale, power)
  if power <= 0.01 or #shafts == 0 then return end
  local g = love.graphics
  rainReset(#shafts)
  -- the hour's light, once, and the posts standing in it
  local lr, lg, lb = rainLight()

  local buckets = { {}, {}, {} }
  for i = 1, #shafts do
    local s = shafts[i]
    local b = buckets[layerRank(s)]
    b[#b + 1] = s
  end

  for bi = 1, 3 do
    local list = buckets[bi]
    for i = 1, #list do
      local s = list[i]
      local vis = s.vis or 1
      local hx, hy, hps = project(s.x, s.y, s.z)
      if hx and vis > 0.01 then
        -- ------- THE STREAK POINTS WHERE THE DROP IS GOING
        --
        -- It used to point wherever a single constant said, times the
        -- global wind: one lean, shared by every drop in the world. Two
        -- separate things were wrong with that, and only the second one is
        -- visible in a still.
        --
        -- The FAN was missing. Divide that lean by the streak's own length
        -- and you get an ANGLE, and the angle came out the same for every
        -- shaft in the frame -- so a shower was a hundred perfectly
        -- parallel needles. Real rain is a fan of angles, because a fine
        -- drop reaches the air's sideways speed while falling slowly and a
        -- heavy one barely leans at all while falling fast.
        --
        -- And the streak did not match its own DROP. The thing was drawn
        -- on that fixed lean while the drop underneath it travelled on the
        -- wind vector, so every raindrop in the frame was sliding sideways
        -- inside its own trail. Nobody sees that in one frame. It is why
        -- the rain never quite looked like it was falling.
        --
        -- Both go away by asking the drop. The tail is simply where this
        -- drop WAS, `smear` seconds ago -- position minus velocity times
        -- time -- which is what a streak physically is: the eye holding a
        -- moving highlight for a moment. The fan, the slant, the way a
        -- gust turns the fine rain and not the heavy, all come out of that
        -- one subtraction for free.
        local vy = s.fall or 1
        local back = s.len / math.max(1e-3, vy)     -- seconds of smear
        local tx = s.x - (s.vx or 0) * back
        local ty = s.y + s.len
        local tz = s.z - (s.vz or 0) * back
        local ux, uy, ups = project(tx, ty, tz)
        if not ux then ux, uy, ups = hx, hy - (s.len * (hps or 1)), hps end
        local c
        if s.layer == "near" then
          c = Weather.RAIN_NEAR
        elseif s.layer == "mid" then
          c = Weather.RAIN_MID
        else
          c = Weather.RAIN_FAR
        end
        local ps = hps or 1
        local a = (s.alpha or 0.35) * power * vis
        -- perspective: nearer shafts read brighter and thicker
        if ps > 1 then a = a * math.min(1.25, 0.75 + ps * 0.25) end
        -- ------- AND A RAINDROP IS A NEEDLE AT ANY DISTANCE
        --
        -- This used to be the drop's own width times the render scale
        -- times the full perspective factor, all three multiplying -- so a
        -- near drop on a high-resolution window came out a dozen pixels
        -- across. A dozen pixels is not a raindrop, it is a white bar, and
        -- a frame full of them is the single loudest reason the shower
        -- read as paint strokes over the picture rather than as weather.
        --
        -- Perspective still counts, because a near drop IS wider -- but it
        -- is clamped, and so is the result. Rain is fine at every distance;
        -- what changes with distance is how MANY you can see, which the
        -- field already handles by having hundreds of them.
        local thick = (s.thick or 1) * scale * math.min(1.5, math.max(0.7, ps))
        local capW = scale * Weather.THICK_CAP
        if thick > capW then thick = capW end
        if thick < 1 then thick = 1 end
        local head = c
        if s.layer == "near" then head = Weather.RAIN_CORE end
        -- the hour, and the gas the drop happens to be falling through
        local gain = lampGain(s.x, s.z)
        -- head and tail get their OWN depth: a needle leaning across a
        -- fence can have one end in front of it and the other behind, and
        -- one depth for the quad would make the whole streak pick a side
        rainPush(hx, hy, ux, uy, thick,
                 head[1] * lr * gain, head[2] * lg * gain, head[3] * lb * gain,
                 a * Weather.ADD_HEAD, a * Weather.ADD_TAIL,
                 projectDepth(s.x, s.y, s.z), projectDepth(tx, ty, tz))
      end
    end
  end
  rainFlush()
end


-- ------- WHAT A DROP DOES WHEN IT LANDS, IN THREE PARTS
--
-- One expanding ring was the whole of it. A ring is what you see from
-- across the street, and this camera is not across the street -- so what
-- was drawn was the far-away reading of an impact happening two feet from
-- the lens, and no amount of tuning a ring fixes that, because the parts
-- that are missing are not rings.
--
-- A drop hitting standing water does three things, in order, and they
-- overlap:
--
--   THE CROWN.  The surface caves, and the wall of the cavity climbs. For
--   a moment there is a ring of raised water with points on it -- that is
--   the crown, and it is what makes rain on stone read as violent rather
--   than as decals blinking on and off. It is drawn as SPOKES: short
--   tapered strokes leaning up and out from the impact, bright at the
--   root, gone at the tip.
--
--   THE JET.  The cavity collapses, the walls meet at the middle, and the
--   water has nowhere to go but UP -- a thin vertical column, taller than
--   the crown was wide, that rises, hangs, and falls back. This is the
--   single most recognisable thing about rain on water and there was
--   nothing like it here at all. It is the tall spike in every photograph
--   of a raindrop landing.
--
--   THE RINGS.  Plural, and staggered. One ring is a decal. Two or three
--   leaving the same point a fraction of a second apart, each expanding
--   and thinning at its own rate, is a surface with waves on it.
--
-- Everything except the rings goes through the same additive mesh the rain
-- streaks use -- one buffer, one draw call for every crown and every jet
-- in the frame -- because a stroke leaning at an arbitrary angle is
-- exactly the tapered quad that buffer already makes, and because water
-- catching light should ADD light rather than paint over what is behind.

-- How tall the jet stands, as a multiple of the ring's own scale, and how
-- much of that a given impact actually gets. The spread is not decoration:
-- a pond in rain is a field of columns of every height, and a set of
-- identical ones reads as a fountain feature rather than as water being
-- hit.
Weather.JET_H = 3.8
Weather.JET_H_VAR = 0.85
Weather.JET_W = 0.62

-- ------- WHAT THE RAIN DOES WHEN IT ARRIVES, AND IT IS NEVER THE SAME TWICE
--
-- Two earlier answers are gone from here, and both of them failed for
-- reasons worth writing down, because both looked reasonable first.
--
-- ONE ANSWER FOR EVERY SURFACE. A crown, a column and a ring, played
-- wherever a drop landed. It is what water does and it is right for
-- exactly one of the things in this world: a column of water standing up
-- out of a lawn is not rain, it is a sprinkler, and it broke the picture
-- harder than having no splash at all.
--
-- SPRITE SHEETS. Three authored animations, one SpriteBatch each, and the
-- draw-call arithmetic was sound. The cost was not: measured on Route 1
-- against the same frame without them, the impacts alone were +21.9 ms --
-- against +6.4 ms for four hundred and forty falling drops and, to
-- everybody's surprise including this file's, MINUS two for the refraction
-- shader. Twenty-two milliseconds is a third of the frame budget spent on
-- the smallest thing on screen.
--
-- So: geometry again, and pushed into the SAME buffer the streaks already
-- use, which means the whole field of impacts costs no draw call of its
-- own at all -- it is drawn with the rain, because it IS the rain.
--
-- ------- and every surface gets its own
--
-- The rule is that nothing behaves like anything else, because in the
-- world nothing does:
--
--   WATER   the loud one, and the only loud one. The surface caves, the
--           cavity collapses, the walls meet in the middle and throw a
--           COLUMN up out of it -- taller than the crown was wide. Then
--           rings, plural and staggered, because a surface with waves on
--           it is what water is.
--
--   PUDDLE  a film over stone. There is no depth for a column to come out
--           of, so there is no column: one ring, wide and fast and flat,
--           and a couple of flecks off the rim. A puddle is loud in AREA
--           and quiet in HEIGHT, which is the opposite of the pond.
--
--   STONE   nothing rises at all. A drop hitting a hard flat plane
--           shatters SIDEWAYS -- a low star of spray going out almost
--           horizontally, gone in a fifth of a second, no ring. This is
--           the one that reads as "hard".
--
--   GRASS   nothing rises and nothing spreads. A blade is a springy edge:
--           it takes the drop, throws two small pieces of it UP and off to
--           one side, and springs back. The shortest-lived of all of them,
--           and the only one that is asymmetric.
--
--   ROOF    a tile is a hard surface at a SLANT, so the water does not
--           burst, it skids: one short streak running downhill from the
--           point of contact. What leaves the roof leaves off the eave,
--           which spawnDrip already handles.
--
--   CANOPY  nothing here at all, and that is the interaction. A crown
--           holds the water and lets it go minutes later
--           (spawnCanopyDrip), which is why standing under a tree after a
--           shower still gets you wet.

-- how tall the column stands out of open water, per unit of impact scale
Weather.JET_H = 3.8
Weather.JET_H_VAR = 0.85
Weather.JET_W = 0.62
-- how flat a ring lying on the ground looks from the diorama's camera
Weather.RING_SQUASH = 0.42
-- segments in a drawn ring. Eight is where an ellipse stops reading as a
-- polygon at these sizes; more is fill rate spent on nothing.
Weather.RING_SEGS = 8
-- the low star a drop throws off stone
Weather.SHARD_N = 5
-- and the two pieces a blade of grass flicks away
Weather.FLICK_N = 2

-- One ELLIPTICAL RING, as a fan of short chords in the shared buffer.
--
-- Chords rather than ticks: the ring used to be eight separate little
-- rectangles standing around a circle, which at any real size reads as a
-- dotted line. A chord between two points on the ellipse is the same cost
-- in the buffer and closes the shape.
local function pushRing(sx, sy, r, thick, cr, cg, cb, a)
  local segs = Weather.RING_SEGS
  local step = 6.2832 / segs
  local sq = Weather.RING_SQUASH
  local px, py = sx + r, sy
  for i = 1, segs do
    local ang = i * step
    local nx = sx + math.cos(ang) * r
    local ny = sy + math.sin(ang) * r * sq
    -- flat alpha along the chord: a ring is a wave crest, not a streak, so
    -- it must not taper the way a falling drop does
    rainPush(nx, ny, px, py, thick, cr, cg, cb, a, a)
    px, py = nx, ny
  end
end

-- Everything an impact draws, by what it landed on. Pushed into the rain
-- buffer; the caller flushes once for the whole field.
local function pushImpact(m, sx, sy, s, power, lr, lg, lb)
  local k = m.t / m.ttl
  if k < 0 or k > 1 then return end
  -- everything this function pushes stands at the mote's own world point
  pushZ = m._d
  local surf = m.surf
  local size = m.size or 1
  local seed = m.seed or 0
  local c = Weather.SPLASH
  local cr, cg, cb = c[1] * lr, c[2] * lg, c[3] * lb
  local base = s * size
  local w = math.max(1, s * 0.5)

  if surf == "water" then
    -- ------- the column
    if k < 0.62 then
      local jk = k / 0.62
      local hh = math.sin(jk ^ 0.7 * 3.1416)
      if hh > 0 then
        local vary = 1 - Weather.JET_H_VAR * 0.5
                       + Weather.JET_H_VAR * (0.5 + 0.5 * math.sin(seed * 5.7))
        local h = base * Weather.JET_H * hh * vary
        local a = 0.95 * power * (1 - jk * 0.35)
        rainPush(sx, sy, sx, sy - h,
                 math.max(1, s * Weather.JET_W * size), cr, cg, cb, a, a * 0.3)
        if jk > 0.35 and jk < 0.9 then
          local bw = math.max(1, s * 0.5)
          rainPush(sx, sy - h, sx, sy - h - bw * 1.4, bw * 1.2,
                   cr, cg, cb, a * 0.9, a * 0.5)
        end
      end
    end
    -- ------- and the rings behind it, one after another
    for n = 1, 3 do
      local born = (n - 1) * 0.17
      local kk = (k - born) / (1 - born)
      if kk > 0 and kk < 1 then
        local r = base * (0.45 + kk * 3.1) * (1 + (n - 1) * 0.25)
        local a = (1 - kk) * (1 - kk) * 0.9 * power / (1 + (n - 1) * 0.9)
        pushRing(sx, sy, r, math.max(1, w - (n - 1) * 0.3), cr, cg, cb, a)
      end
    end

  elseif surf == "pool" then
    -- ------- wide and flat: a film has area and no depth
    local r = base * (0.5 + k * 4.4)
    local a = (1 - k) * (1 - k) * 0.85 * power
    pushRing(sx, sy, r, w, cr, cg, cb, a)
    if k < 0.4 then
      local fk = k / 0.4
      local fa = (1 - fk) * 0.8 * power
      for i = 0, 1 do
        local ang = seed + i * 3.1416
        local o = base * (0.8 + fk * 1.6)
        rainPush(sx + math.cos(ang) * o,
                 sy + math.sin(ang) * o * Weather.RING_SQUASH - base * 0.5 * (1 - fk),
                 sx, sy, w * 0.8, cr, cg, cb, fa, fa * 0.2)
      end
    end

  elseif surf == "stone" then
    -- ------- a low star, going out and not up
    if k < 0.62 then
      local sk = k / 0.62
      local a = (1 - sk) * (1 - sk) * 0.9 * power
      local out = base * (0.6 + sk * 2.6)
      local n = Weather.SHARD_N
      local step = 6.2832 / n
      for i = 0, n - 1 do
        local ang = i * step + seed
        local len = 0.65 + 0.7 * (0.5 + 0.5 * math.sin(seed * 4.1 + i * 2.7))
        -- barely any lift: the whole point of stone is that nothing rises
        local ex = sx + math.cos(ang) * out * len
        local ey = sy + math.sin(ang) * out * len * Weather.RING_SQUASH
                      - base * 0.28 * (1 - sk)
        rainPush(ex, ey, sx, sy, w * 0.85, cr, cg, cb, a, a * 0.12)
      end
    end

  elseif surf == "grass" then
    -- ------- two pieces, one side, and gone
    --
    -- Asymmetric on purpose: a blade is not a plane, it is an edge, and a
    -- drop breaking over an edge goes one way. Radial symmetry here would
    -- make grass look like small stone, which is exactly the thing this
    -- whole block exists to avoid.
    if k < 0.85 then
      local gk = k / 0.85
      local a = (1 - gk) * 0.8 * power
      local side = (math.sin(seed * 7.3) > 0) and 1 or -1
      for i = 0, Weather.FLICK_N - 1 do
        local ang = seed * 0.5 + side * (0.5 + i * 0.55)
        local o = base * (0.5 + gk * 1.5) * (1 + i * 0.35)
        -- UP, and falling back: this is the only impact with an arc in it
        local ex = sx + math.cos(ang) * o
        local ey = sy + math.sin(ang) * o * Weather.RING_SQUASH
                      - base * (2.0 * gk - 2.4 * gk * gk)
        rainPush(ex, ey, sx, sy, w * 0.7, cr, cg, cb, a, a * 0.1)
      end
    end

  elseif surf == "roof" then
    -- ------- a skid downhill, not a burst
    if k < 0.7 then
      local rk = k / 0.7
      local a = (1 - rk) * 0.85 * power
      local run = base * (0.8 + rk * 3.0)
      rainPush(sx, sy + run * Weather.RING_SQUASH, sx, sy,
               w * 0.8, cr, cg, cb, a, a * 0.15)
    end
  end
end


-- ------- the draw
--
-- Inside the voxel overlay pass (main.lua's drawWorld), with the same project
-- function the field FX and the ambient life anchor through. Splashes land
-- FIRST (they are on the ground), shafts through the volume next, then the
-- thin screen-space mist in front of everything -- rain between the camera
-- and the near edge of the diorama has no world position.
function Weather.draw(project, scale, w, h)
  -- visible, NOT falling: indoors and under a canopy this draws nothing at
  -- all -- no splashes, no flakes, no streaks. A mid-flash bolt may still
  -- draw if one was armed (storm / probe), because the strike is already
  -- in world space and does not need rain power to project.
  local kind, power = Weather.visible()
  -- The sky being done is NOT the picture being done: the after-rain
  -- window keeps the tick spawning eave and canopy drips for minutes
  -- after `kind` goes nil, and this early-out was throwing every one of
  -- them away unpainted -- the whole "the wood keeps raining after the
  -- sky stops" feature drew nothing, ever, and the probe that blessed it
  -- was counting motes rather than pixels. So the gate is now "no rain
  -- AND nothing left in the world", and the drips get their own power
  -- floor below since the shower's own power is zero out here.
  if not kind and #motes == 0 then
    if #drops > 0 then drops = {} end
    if #shafts > 0 then shafts = {} end
    local lit = Weather.flash()
    if lit > 0 and project then
      local g = love.graphics
      local prevBlend, prevAlpha = g.getBlendMode()
      paintStrike3D(project, scale, lit, w, h)
      g.setBlendMode(prevBlend or "alpha", prevAlpha)
      g.setColor(1, 1, 1, 1)
    end
    return
  end
  power = power or 0
  -- what the leftover motes are lit by once the shower's power is spent:
  -- the after-rain window, at drip strength
  local mPower = power
  do
    local okA, v = pcall(Weather.afterRain)
    local floorP = ((okA and tonumber(v)) or 0) * 0.65
    if mPower < floorP then mPower = floorP end
  end
  local g = love.graphics
  local prevBlend, prevAlpha = g.getBlendMode()
  g.setBlendMode("alpha")

  -- The frame as it stands before any water goes on it, for the lens
  -- shader to refract. Taken here, once, rather than inside each flush.
  behindReady = false
  if kind and refractShader() then captureBehind() end

  -- The hour, and the posts standing in it. Once per frame for the whole
  -- field: splashes, flakes, drips and shafts are all water catching the
  -- same light, and any one of them painted at a different brightness from
  -- the others is the thing that reads as fake.
  local lr, lg, lb = rainLight()
  do
    local Game = game()
    gatherLamps(Game and Game.overworld)
  end
  -- how bright the hour is, which is how much the INK is worth: at night
  -- the ground is already dark and a stamp on it is mud (see THE INK)
  local inkGain = (lr + lg + lb) / 3
  if inkGain > 1 then inkGain = 1 end
  local ink = Weather.INK

  -- One pass to place every mote on screen. The impacts are only PROJECTED
  -- here -- what each of them draws is pushed into the shared buffer below,
  -- because they are additive and the drips and flakes in this same loop
  -- are not, and swapping the blend mode per mote is a state change per
  -- raindrop.
  for _, m in ipairs(motes) do
    local sx, sy, ps = project(m.x, m.y, m.z)
    if sx then
      local s = math.max(1, scale * (ps or 1))
      m._sx, m._sy, m._s = sx, sy, s
      -- and how far away it is, in the buffer's own units, so the shader
      -- can ask whether the house in front of it got there first
      m._d = projectDepth(m.x, m.y, m.z)
      if m.kind == "splash" then
        -- ------- the ink, under the light (see THE INK, by the counts)
        --
        -- The additive half of this mote is pushed into the shared buffer
        -- below; here, first and underneath it, goes the dark half --
        -- the only part of a landing that can survive a white street.
        local base = s * (m.size or 1)
        local surf = m.surf
        if surf == "water" or surf == "pool" then
          -- the two-tone rim: a dark ring expanding with the crest, the
          -- way every cel-shaded ripple is inked
          local kk = m.t / m.ttl
          if kk >= 0 and kk <= 1 then
            local r = (surf == "water") and base * (0.45 + kk * 3.1)
                                        or base * (0.5 + kk * 4.4)
            local a = (1 - kk) * (1 - kk) * Weather.INK_RIM_A
                      * mPower * inkGain
            if a > 0.01 then
              g.setColor(ink[1], ink[2], ink[3], a)
              g.setLineWidth(math.max(1, s * 0.4))
              g.ellipse("line", sx, sy, r, r * Weather.RING_SQUASH, 10)
              g.setLineWidth(1)
            end
          end
        else
          -- the wet stamp: pops in with the hit, dries over its own
          -- longer clock. Grass at half strength -- a lawn is already
          -- dark and half-hides its ground anyway.
          local span = m.ink or m.ttl
          local kk = m.t / span
          if kk >= 0 and kk <= 1 then
            local rise = m.t / 0.07
            if rise > 1 then rise = 1 end
            local a = Weather.INK_A * rise * (1 - kk) * mPower * inkGain
            if surf == "grass" then a = a * 0.5 end
            if a > 0.01 then
              local grow = m.t / 0.12
              if grow > 1 then grow = 1 end
              local rx = base * (0.9 + 0.7 * grow)
              g.setColor(ink[1], ink[2], ink[3], a)
              g.ellipse("fill", sx, sy, rx, rx * Weather.RING_SQUASH,
                        Weather.INK_SEGS)
            end
          end
        end
      elseif m.kind == "drip" then
        local c = Weather.RAIN_NEAR
        local a = 0.78 * mPower
        g.setColor(c[1] * lr, c[2] * lg, c[3] * lb, a)
        if m.hang and m.hang > 0 then
          -- the bead, swelling on the lip until it lets go: drawn from
          -- how much of its hang is spent, so it visibly grows
          local left = m.hang
          local total = Weather.DRIP_HANG_MIN + Weather.DRIP_HANG_VAR * 0.5
          local swell = 1 - left / total
          if swell < 0.2 then swell = 0.2 elseif swell > 1 then swell = 1 end
          local d = math.max(1.5, s * 0.85 * swell)
          g.ellipse("fill", sx, sy, d * 0.5, d * 0.62, 8)
        else
          -- falling: a thread with a bright head, so the drop reads as a
          -- drop and not as a scratch on the wall behind it
          local t = math.max(1, s * 0.7)
          local hgt = s * 2.4
          g.rectangle("fill", sx - t * 0.5, sy - hgt, t, hgt)
          local hc = Weather.RAIN_CORE
          g.setColor(hc[1] * lr, hc[2] * lg, hc[3] * lb, math.min(1, a * 1.3))
          local d = math.max(1.5, s * 0.7)
          g.ellipse("fill", sx, sy, d * 0.5, d * 0.6, 8)
        end
      elseif m.kind == "eject" then
        -- A thrown drop, and it is deliberately the brightest thing in the
        -- splash: this is the water that left the surface, catching the
        -- sky from above while the ring below it is only a wave. One or
        -- two pixels, no trail -- a streak here would read as a spark.
        local c = Weather.SPLASH
        local a = 0.85 * mPower * (1 - (m.t / m.ttl) ^ 3)
        local d = math.max(1, s * 0.55 * (m.size or 1))
        g.setColor(c[1] * lr, c[2] * lg, c[3] * lb, a)
        g.rectangle("fill", sx - d * 0.5, sy - d * 0.5, d, d)
      else
        local c = Weather.SNOW
        -- Fades in as it arrives and out as it settles, and the height is
        -- measured from what it is going to LAND on -- on a town's raised
        -- paving, world zero is sixteen pixels underground and a flake
        -- fading toward it never faded at all.
        local above = m.y - (m.yLand or 0)
        local fade = math.min(1, m.t * 3, (above + 2) / 6)
        if m.settled then
          fade = fade * math.max(0, 1 - m.settled / 0.5)
        end
        g.setColor(c[1] * lr, c[2] * lg, c[3] * lb, 0.92 * fade * mPower)
        local d = math.max(1, s * m.size)
        g.rectangle("fill", sx - d * 0.5, sy - d * 0.5, d, d)
      end
    end
  end

  -- ------- the impacts, in the buffer the rain is already using
  --
  -- Not a draw call of their own: every ring, column, shard and flick in
  -- the frame goes into the same mesh as the falling drops and leaves with
  -- them. That is the whole reason this is geometry again -- the sprite
  -- sheets it replaced were three batches and twenty-two milliseconds.
  --
  -- ADDITIVE, for the reason the streaks are: water is clear, and what you
  -- see when it is thrown around is the light it catches. A white ring
  -- painted OVER pale paving reads as a sticker; a ring that brightens the
  -- paving reads as wet.
  do
    -- The widest an impact can be is water's: three rings of RING_SEGS
    -- chords, the column, and the bead on it. Everything else is smaller,
    -- so this sizes the buffer for all of them.
    local per = Weather.RING_SEGS * 3 + 2
    local n = 0
    for i = 1, #motes do
      if motes[i].kind == "splash" then n = n + 1 end
    end
    if n > 0 then
      rainReset(n * per)
      for i = 1, #motes do
        local m = motes[i]
        if m.kind == "splash" and m._sx then
          pushImpact(m, m._sx, m._sy, m._s, mPower, lr, lg, lb)
        end
      end
      rainFlush()
    end
  end

  if kind == "rain" then
    drawShafts(project, scale, power)
    if w and h then
      stepDrops(w, h, love.timer and love.timer.getDelta() or 0, power)
      drawDrops(h, power)
    end
  end

  -- World-space bolt through the same camera as splashes (not a HUD PNG).
  paintStrike3D(project, scale, Weather.flash(), w, h)

  behindReady = false
  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  g.setColor(1, 1, 1, 1)
end

-- ------- the flat 2D world
--
-- Called from DayTint's seam -- the one instant between the world blit and
-- the UI blit -- so the rain lands on the world and not on the dialog box in
-- front of it, for exactly the reason the hour's tint goes there and the
-- tilt-shift is a worldPresent (see lib/DayTint.lua).
--
-- Streaks and the flash only: the splashes and flakes are projected through a
-- camera that does not exist on this path, and screen-space rain over the
-- flat world is the whole of what the flat world can honestly show.
-- Whether the flat path has anything to paint this frame. Asked by DayTint
-- BEFORE it decides the frame needs no pass at all -- the hour can be neutral
-- (a clear midday multiplies by white and is skipped entirely) while the
-- weather is not, and a clear-sky midday must still cost nothing.
--
-- Snow answers false unless the sky is lit: there is nothing for a flake to
-- fall THROUGH without the camera, and screen-space snow is dandruff.
-- ------- a seam the screenshot probes need
--
-- How many world-space motes of a kind are alive, and where they are.
-- Drips in particular are otherwise unmeasurable: they are a handful of
-- 2px specks falling for a second and a half in the minutes AFTER a
-- shower, which is exactly the sort of feature a screenshot agrees with
-- whether or not it is running. Counting them is how the probe tells
-- "dripping" from "the rain stopped and nothing replaced it".
--
-- Returns the count and, for a caller that asks, the list itself so a
-- probe can check the drips are near the player and under a crown rather
-- than raining somewhere off-screen.
function Weather.moteCount(kind, out)
  local n = 0
  for i = 1, #motes do
    local m = motes[i]
    if not kind or m.kind == kind then
      n = n + 1
      if out then out[#out + 1] = { x = m.x, y = m.y, z = m.z, kind = m.kind } end
    end
  end
  return n
end

-- ------- the seam the rain probes need
--
-- A shaft is a world-space drop with a velocity, and every claim worth
-- making about the shower is a claim about that velocity: whether the
-- streak points where the drop is actually going, whether two drops a
-- metre apart are being pushed by the same air, whether a fat drop
-- ploughs through a gust a fine one veers in. None of that is a
-- screenshot -- a still frame of parallel white needles and a still frame
-- of rain sorted by drop size look the same until you measure the angles.
--
-- Returns the live count and, for a caller that asks, a copy of each
-- shaft's position, velocity and size.
-- Two more probe seams, and they exist because the two changes hardest to
-- see are also the two easiest to get silently wrong.
--
-- lightNow is the hour's own multiplier on the rain. A shower that got
-- dimmer could be dimmer because it is correctly taking a storm sky's
-- light, or because something in the physics quietly thinned it out, and
-- from a screenshot those are the same picture. This separates them.
--
-- lampCount is whether the posts were found at all. The night-rain cone is
-- the whole reason the lamp arithmetic exists, and an empty list draws
-- exactly the same frame as a list that was never asked for.
function Weather.lightNow()
  return rainLight()
end

-- Which impact path the frame took. A sheet that silently failed to decode
-- and fell back to the drawn rings looks, in a screenshot of a downpour,
-- exactly like a sheet that loaded -- so the probe asks instead of looking.
-- Which streak path the frame took. A shader that failed to compile falls
-- back to the additive quads, and in a screenshot of a shower that is a
-- subtle difference and an easy one to ship by accident.
function Weather.refractState()
  local sh = refractShader()
  if not sh then return "additive" end
  return behindCanvas and "refract" or "refract-nocopy"
end

-- What each surface is currently doing, counted rather than looked at. The
-- claim this file makes is that no two surfaces behave alike; a probe can
-- only check that by counting how many impacts of each kind are live and
-- confirming a scene with grass, stone and water in it produces all three.
function Weather.impactMix(out)
  out = out or {}
  for i = 1, #motes do
    local m = motes[i]
    if m.kind == "splash" then
      local k = m.surf or "?"
      out[k] = (out[k] or 0) + 1
    end
  end
  return out
end

function Weather.lampCount()
  return #lampBuf
end

function Weather.shaftDump(out)
  if out then
    for i = 1, #shafts do
      local s = shafts[i]
      -- drawx/y/z is the streak AS DRAWN -- tail minus head -- built the
      -- same way drawShafts builds it, so a probe can compare where the
      -- streak points with where the drop is going without reimplementing
      -- (and therefore agreeing with) the draw by hand.
      local back = (s.len or 0) / math.max(1e-3, s.fall or 1)
      out[#out + 1] = {
        id = s.id,
        x = s.x, y = s.y, z = s.z,
        vx = s.vx or 0, vy = -(s.fall or 0), vz = s.vz or 0,
        drawx = -(s.vx or 0) * back, drawy = -(s.len or 0), drawz = -(s.vz or 0) * back,
        fall = s.fall, len = s.len, layer = s.layer,
        d = s.d, tau = s.tau, vis = s.vis or 1,
      }
    end
  end
  return #shafts
end

-- ------- and the seam that stops a probe waiting out the weather
--
-- A shower BUILDS. The ramp is the feature -- the sky, the light, the
-- water and the air all arrive on one curve, over the better part of a
-- minute -- and a probe that pins the row and starts counting is measuring
-- a drizzle at a sixth of its power while believing it is looking at the
-- downpour. Which is exactly what the first run of the rain probe did.
--
-- So: set the state outright, the way forceStrike sets the lightning.
-- Probes only. Nothing in the mod calls this.
function Weather.pin(kind, power)
  state.kind = kind
  state.power = tonumber(power) or 1
  state.target = state.power
  state.timer = 600
  state.mode = Weather.setting:get()
end

-- ------- AND WHY THE RAIN IS PAINTED TWICE OVER, IN TWO DIFFERENT PLACES
--
-- Because the tilt-shift was eating it, and from inside this file that was
-- invisible.
--
-- Weather.draw runs inside drawWorld, which paints the diorama's canvas --
-- and that canvas is then handed to TiltShift.apply, which blurs it. So
-- every streak this file drew as a hard-edged needle arrived on screen as a
-- soft grey smear four times wider than it was authored. Measured off four
-- screenshots of the same shower with the blur and the resolution switched
-- independently (tests/rain_look_probe.lua): the edge energy in the sky
-- band falls from 3.43 to 0.87 and the streaks fatten from seven pixels to
-- twenty-two. The RESOLUTION made almost no difference -- 3.43 against
-- 3.48. It was the blur, all of it.
--
-- Which is a thing the pipeline file had already solved twice: the
-- orientation radar and the start menu are BOTH re-painted after the blur,
-- for the stated reason that text and a HUD through a tilt-shift are
-- unreadable in a way a landscape is not. Rain is the third: a raindrop is
-- a hard little needle, and a hard little needle put through a depth-of-
-- field is not a soft raindrop, it is a smudge.
--
-- So when the blur is running the weather is drawn AFTER it, through this,
-- and drawWorld skips it; when the blur is off, drawWorld draws it as
-- before. One paint per frame either way -- main.lua owns that choice
-- because main.lua is where both passes live.
function Weather.present(canvas, project, scale)
  if not canvas then return canvas end
  local g = love.graphics
  local w = canvas.getWidth and canvas:getWidth() or 0
  local h = canvas.getHeight and canvas:getHeight() or 0
  if w < 1 or h < 1 then return canvas end
  local prev = g.getCanvas and g.getCanvas() or nil
  if not pcall(g.setCanvas, canvas) then return canvas end
  -- The depth test still applies here. This path paints onto the blurred
  -- canvas rather than the raw one, but a blur moves no geometry, so the
  -- frame's depth is still a true statement about what is in front of
  -- what. sendDepth checks the one thing that actually has to hold -- that
  -- this surface is the same grid as the depth texture -- and stands the
  -- test down by itself if it is not.
  pcall(Weather.draw, project, scale or 1, w, h)
  if prev then pcall(g.setCanvas, prev) else pcall(g.setCanvas) end
  return canvas
end

function Weather.paintsFlat()
  local kind = Weather.visible()
  if not kind then return false end
  if kind == "snow" and Weather.flash() <= 0 then return false end
  return true
end

function Weather.paintFlat()
  if not Weather.paintsFlat() then return end
  local kind, power = Weather.visible()

  local g = love.graphics
  local w, h = g.getDimensions()
  local prevBlend, prevAlpha = g.getBlendMode()
  g.setBlendMode("alpha")
  if kind == "rain" then
    stepDrops(w, h, love.timer and love.timer.getDelta() or 0, power)
    drawDrops(h, power)
  end
  -- No camera on the flat path: ambient plate only (bolt needs project).
  paintPlate(g, w, h, Weather.flash())
  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  g.setColor(1, 1, 1, 1)
end

return Weather
