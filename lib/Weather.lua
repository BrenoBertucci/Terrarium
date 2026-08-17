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
Weather.STREAKS = 18
Weather.STREAKS_MAX = 80
-- World-space shafts at full power, around the player. Quality.scale cuts
-- this the same way it cuts WindFX -- 1/4 RES cannot afford a hundred
-- extra projections.
-- Raised once the field became ONE draw call instead of one per drop.
-- Thin rain is most of what made this look fake -- a shower is a texture
-- of many faint streaks, and at eighty-eight you can count them. The old
-- numbers were rationing draw calls, not fill rate.
Weather.SHAFTS = 150
Weather.SHAFTS_MAX = 240
Weather.SHAFT_FALL = 102            -- world px / s
Weather.SHAFT_LEN = 16              -- world px of streak above the drop
-- How far a shaft leans back per unit of streak, at full wind. A fraction
-- of its own LENGTH, so the slant is an angle rather than a pixel count
-- that vanishes the moment the streak gets longer.
Weather.LEAN = 0.20
Weather.SHAFT_REACH = 9             -- cells around the player
-- Splashes are mostly spawned by a shaft hitting something. A small
-- ambient floor stays so a street still ticks when the shafts are sparse.
Weather.SPLASHES = 56
Weather.SPLASH_FLOOR = 14
Weather.FLAKES = 90

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
Weather.ADD_HEAD = 0.62
Weather.ADD_TAIL = 0.05
Weather.SPLASH = { 0.85, 0.92, 1.00 }
Weather.SNOW = { 0.97, 0.98, 1.00 }

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

local function splashCell(ow)
  local map, p = ow.map, ow.player
  local pool = Weather.poolAt
  -- the pools first, and only within the reach GroundFX actually draws them
  -- in: a ring bursting over a puddle eleven cells away that is not on the
  -- screen is a ring nobody sees, spent out of the same budget
  if pool then
    for _ = 1, Weather.POOL_TRIES do
      local cx = p.cellX + rand(-6, 6)
      local cy = p.cellY + rand(-6, 6)
      local ok, holds = pcall(pool, map, cx, cy)
      if ok and holds then
        -- near the middle of the cell rather than anywhere in it: the pool
        -- is centred there and does not fill its own square
        return cx * 16 + rand(5, 11), cy * 16 + rand(5, 11),
               false, true, groundAt(map, cx, cy)
      end
    end
  end
  for _ = 1, 8 do
    local cx = p.cellX + rand(-7, 7)
    local cy = p.cellY + rand(-7, 7)
    if map:inBounds(cx, cy)
       and (map:isWalkableCell(cx, cy) or map:isWaterCell(cx, cy)) then
      local water = map:isWaterCell(cx, cy)
      return cx * 16 + rand(1, 15), cy * 16 + rand(1, 15),
             water, false, water and 0 or groundAt(map, cx, cy)
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

local function spawnSplash(ow)
  local x, z, onWater, inPool, gh = splashCell(ow)
  if not x then return end
  local lift = onWater and Weather.SPLASH_POND_LIFT
               or inPool and Weather.SPLASH_POOL_LIFT
               or Weather.SPLASH_LIFT
  motes[#motes + 1] = {
    kind = "splash", x = x, z = z, y = (gh or 0) + lift,
    size = inPool and Weather.SPLASH_POOL_SIZE or (onWater and 1.7 or 1),
    surf = onWater and "water" or inPool and "pool" or "ground",
    t = 0, ttl = (inPool and 0.44 or onWater and 0.52 or 0.34) + rand() * 0.16,
  }
end

local function spawnFlake(ow)
  local p = ow.player
  local x = (p.cellX + rand(-9, 9)) * 16 + rand(0, 15)
  local z = (p.cellY + rand(-9, 9)) * 16 + rand(0, 15)
  motes[#motes + 1] = {
    kind = "flake", x = x, z = z, y = 40 + rand() * 26,
    seed = rand() * 6.2831, t = 0, ttl = 30,
    fall = 7 + rand() * 6, size = rand() < 0.35 and 1.4 or 0.9,
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
  return gh + Weather.SPLASH_LIFT, "ground"
end

local function splashFromHit(x, z, y, surf)
  if #motes >= Weather.SPLASHES then return end
  local size, ttl = 1, 0.34
  if surf == "water" then
    size, ttl = 1.85, 0.58
  elseif surf == "pool" then
    size, ttl = Weather.SPLASH_POOL_SIZE, 0.46
  elseif surf == "roof" then
    size, ttl = 0.62, 0.20
  end
  motes[#motes + 1] = {
    kind = "splash", x = x, z = z, y = y,
    size = size, surf = surf,
    t = 0, ttl = ttl + rand() * 0.14,
  }
  if surf == "pool" and Weather.notePoolHit then
    pcall(Weather.notePoolHit, x, z)
  end
end

-- A drop that left the roof and is looking for the street. Spawned beside
-- the hit, not on it, so the drip falls off the eave rather than through
-- the tiles it just landed on.
local function spawnDrip(ow, x, z, yRoof)
  local dir = rand(0, 3)
  local ox = (dir == 0 and 12) or (dir == 1 and -12) or 0
  local oz = (dir == 2 and 12) or (dir == 3 and -12) or 0
  local nx, nz = x + ox, z + oz
  local yLand = select(1, surfaceAt(ow, nx, nz))
  if yLand >= (yRoof or 0) - 2 then return end
  motes[#motes + 1] = {
    kind = "drip", x = nx, z = nz, y = yRoof - 1,
    yLand = yLand, fall = 70 + rand() * 30,
    t = 0, ttl = 1.4,
  }
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
Weather.DRIP_MAX = 26             -- live canopy drips at once
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
  local yLand = select(1, surfaceAt(ow, x, z))
  motes[#motes + 1] = {
    kind = "drip", x = x, z = z,
    y = yLand + Weather.DRIP_HEIGHT + rand() * 5,
    yLand = yLand, fall = 62 + rand() * 34,
    t = 0, ttl = 1.6,
  }
end

local function shaftBudget()
  local s = 1
  local ok, n = pcall(Quality.scale)
  if ok and tonumber(n) then s = n end
  if s >= 4 then return 22 end
  if s == 3 then return 40 end
  if s == 2 then return Weather.SHAFTS end
  return Weather.SHAFTS_MAX
end

local function spawnShaft(ow, anywhere)
  local p = ow.player
  local r = Weather.SHAFT_REACH
  local x = (p.cellX + rand(-r, r)) * 16 + rand(0, 15)
  local z = (p.cellY + rand(-r, r)) * 16 + rand(0, 15)
  local ySurf = select(1, surfaceAt(ow, x, z))
  -- always start ABOVE the lid, never inside a house
  local air = 22 + rand() * 56
  local y = ySurf + (anywhere and (4 + rand() * air) or air)
  local layer = pickLayer()
  local fall = Weather.SHAFT_FALL
  local len = Weather.SHAFT_LEN
  local alpha, thick
  if layer == "near" then
    fall = fall * (1.05 + rand() * 0.25)
    len = len * (1.15 + rand() * 0.35)
    alpha = 0.55 + rand() * 0.28
    thick = 1.35 + rand() * 0.55
  elseif layer == "mid" then
    fall = fall * (0.88 + rand() * 0.22)
    len = len * (0.90 + rand() * 0.25)
    alpha = 0.32 + rand() * 0.18
    thick = 0.95 + rand() * 0.35
  else
    fall = fall * (0.70 + rand() * 0.20)
    len = len * (0.70 + rand() * 0.20)
    alpha = 0.16 + rand() * 0.12
    thick = 0.65 + rand() * 0.25
  end
  shafts[#shafts + 1] = {
    x = x, y = y, z = z,
    fall = fall, len = len, layer = layer,
    alpha = alpha, thick = thick,
    seed = rand() * 6.2832,
  }
end

local function stepShafts(ow, dt, power)
  local want = math.floor(shaftBudget() * (0.35 + 0.65 * power))
  if want < 0 then want = 0 end
  local first = #shafts == 0
  for _ = 1, math.max(0, want - #shafts) do spawnShaft(ow, first) end
  while #shafts > want do table.remove(shafts) end

  local wAmt = 0
  local okw, n = pcall(Wind.amount)
  if okw then wAmt = n or 0 end
  local wdx = (Wind.DIR and Wind.DIR[1]) or 1
  local wdz = (Wind.DIR and Wind.DIR[2]) or 0
  local p = ow.player
  local px = (p.cellX or 0) * 16
  local pz = (p.cellY or 0) * 16
  local reach = Weather.SHAFT_REACH * 16 + 48

  for i = #shafts, 1, -1 do
    local s = shafts[i]
    s.x = s.x + wdx * wAmt * 16 * dt
    s.z = s.z + wdz * wAmt * 16 * dt
    s.y = s.y - s.fall * dt
    local yHit, surf = surfaceAt(ow, s.x, s.z)
    local far = math.abs(s.x - px) > reach or math.abs(s.z - pz) > reach
    if s.y <= yHit or far then
      if (not far) and s.y <= yHit + 6 then
        splashFromHit(s.x, s.z, yHit, surf)
        if surf == "roof" and rand() < 0.38 then
          spawnDrip(ow, s.x, s.z, yHit)
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

  if visible == "rain" then
    stepShafts(ow, dt, state.power)
    -- a few ambient rings so the street still ticks when shafts are
    -- sparse (1/4 RES, the first second of a shower). The shafts do
    -- the rest by landing.
    local floor = math.floor(Weather.SPLASH_FLOOR * state.power)
    local splashes = 0
    for i = 1, #motes do
      if motes[i].kind == "splash" then splashes = splashes + 1 end
    end
    for _ = 1, math.max(0, floor - splashes) do spawnSplash(ow) end
  elseif visible then
    if #shafts > 0 then shafts = {} end
    local want_n = math.floor(Weather.FLAKES * state.power)
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
  if dripAfter > 0 then
    local live = 0
    for i = 1, #motes do
      if motes[i].kind == "drip" then live = live + 1 end
    end
    if live < Weather.DRIP_MAX then
      local tries = Weather.DRIP_RATE * dripAfter * dt
      local whole = math.floor(tries)
      if rand() < tries - whole then whole = whole + 1 end
      for _ = 1, math.min(whole, Weather.DRIP_MAX - live) do
        spawnCanopyDrip(ow)
      end
    end
  end

  local windAmt = 0
  local okw, n = pcall(Wind.amount)
  if okw then windAmt = n or 0 end

  for i = #motes, 1, -1 do
    local m = motes[i]
    m.t = m.t + dt
    local dead = m.t >= m.ttl
    if m.kind == "flake" then
      -- falls slowly, wanders sideways on its own phase, and is carried by
      -- whatever the wind is doing to the grass underneath it
      m.y = m.y - m.fall * dt
      m.x = m.x + (math.sin(m.t * 1.1 + m.seed) * 3
                   + (Wind.DIR[1] or 1) * windAmt * 2.2) * dt
      m.z = m.z + (math.cos(m.t * 0.9 + m.seed) * 2
                   + (Wind.DIR[2] or 0) * windAmt * 2.2) * dt
      if m.y <= 0 then dead = true end
    elseif m.kind == "drip" then
      m.y = m.y - (m.fall or 80) * dt
      if m.y <= (m.yLand or 0) then
        splashFromHit(m.x, m.z, m.yLand or 0, "ground")
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
  if failed then return end
  local ok, err = pcall(tick, dt or 0)
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
    -- wind force over lifetime (Unity Force module): adds to horizontal
    local vx = v * lean + wDx * wAmt * v * 0.12
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
local RAIN_FMT = {
  { "VertexPosition", "float", 2 },
  { "VertexColor", "float", 4 },
}
local rainV, rainMesh, rainN, rainCap = {}, nil, 0, 0

local function rainReset(maxQuads)
  local need = maxQuads * 6
  if need > rainCap then
    -- The vertex tables are allocated ONCE and mutated in place from then
    -- on. Rebuilding them per frame would put a few thousand short-lived
    -- tables a second in front of the GC, on the machine least able to
    -- afford it.
    for i = rainCap + 1, need do rainV[i] = { 0, 0, 1, 1, 1, 0 } end
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
local function rainPush(hx, hy, ux, uy, w, r, g, b, aH, aT)
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
  local v
  v = rainV[i + 1]; v[1] = h1x; v[2] = h1y; v[3] = r; v[4] = g; v[5] = b; v[6] = aH
  v = rainV[i + 2]; v[1] = h2x; v[2] = h2y; v[3] = r; v[4] = g; v[5] = b; v[6] = aH
  v = rainV[i + 3]; v[1] = t2x; v[2] = t2y; v[3] = r; v[4] = g; v[5] = b; v[6] = aT
  v = rainV[i + 4]; v[1] = h1x; v[2] = h1y; v[3] = r; v[4] = g; v[5] = b; v[6] = aH
  v = rainV[i + 5]; v[1] = t2x; v[2] = t2y; v[3] = r; v[4] = g; v[5] = b; v[6] = aT
  v = rainV[i + 6]; v[1] = t1x; v[2] = t1y; v[3] = r; v[4] = g; v[5] = b; v[6] = aT
  rainN = rainN + 1
end

local function rainFlush()
  if not rainMesh or rainN == 0 then return end
  local g = love.graphics
  rainMesh:setVertices(rainV)
  rainMesh:setDrawRange(1, rainN * 6)
  local pm, pa = g.getBlendMode()
  g.setBlendMode("add", "alphamultiply")
  g.setColor(1, 1, 1, 1)
  g.draw(rainMesh)
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
  local wAmt = 0
  local okw, n = pcall(Wind.amount)
  if okw then wAmt = n or 0 end
  local wdx = (Wind.DIR and Wind.DIR[1]) or 1
  local wdz = (Wind.DIR and Wind.DIR[2]) or 0

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
      local hx, hy, hps = project(s.x, s.y, s.z)
      if hx then
        -- WHERE THE DROP WAS, and the lean is a fraction of the streak's
        -- own LENGTH rather than a flat number of pixels. It used to be
        -- `wAmt * 0.35` -- about half a pixel of sideways against sixteen
        -- of fall, so every shaft in every wind stood bolt upright and the
        -- field read as a picket fence rather than as weather. Tying it to
        -- the length means the lean survives whatever the streak length
        -- becomes, and a gale actually slants the rain.
        local lean = Weather.LEAN * math.min(wAmt, 3) * s.len
        local tx = s.x - wdx * lean
        local ty = s.y + s.len
        local tz = s.z - wdz * lean
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
        local a = (s.alpha or 0.35) * power
        -- perspective: nearer shafts read brighter and thicker
        if ps > 1 then a = a * math.min(1.25, 0.75 + ps * 0.25) end
        local thick = math.max(1, (s.thick or 1) * scale * math.max(0.7, ps))
        local head = c
        if s.layer == "near" then head = Weather.RAIN_CORE end
        rainPush(hx, hy, ux, uy, thick, head[1], head[2], head[3],
                 a * Weather.ADD_HEAD, a * Weather.ADD_TAIL)
      end
    end
  end
  rainFlush()
end


local function drawSplash(g, sx, sy, s, m, power)
  local k = m.t / m.ttl
  local size = m.size or 1
  local surf = m.surf
  local r = s * (0.55 + k * 2.8) * size
  local a = (1 - k) * (1 - k) * 0.95 * power
  local c = Weather.SPLASH
  local t = math.max(1, s * 0.7)
  g.setColor(c[1], c[2], c[3], a)
  -- ------- THE RING IS A RING
  --
  -- This was four axis-aligned bars -- left, right, top, bottom -- which
  -- is not a ring, it is a PLUS SIGN, and at splash sizes that is exactly
  -- what it read as: a little white cross blinking on the ground.
  --
  -- Eight ticks around an ELLIPSE instead. Ellipse rather than circle
  -- because the ground is seen at the diorama's angle, so a ring lying on
  -- it is squashed vertically -- a round one reads as a decal standing up
  -- facing the camera. Each tick is still a hard little rectangle, which
  -- keeps the cel look; what changed is where they are put.
  local squash = 0.42
  for k = 0, 7 do
    local ang = k * 0.7854 + 0.3927          -- 8 around, offset off-axis
    local ex = sx + math.cos(ang) * r
    local ey = sy + math.sin(ang) * r * squash
    g.rectangle("fill", ex - t * 0.5, ey - t * 0.4, t, t * 0.8)
  end
  -- water / puddle: a second wider ring so a hit on standing water
  -- reads from across the street, which is how rain on a pond looks
  if (surf == "water" or surf == "pool") and k < 0.85 then
    local r2 = r * (1.35 + k * 0.4)
    local a2 = a * 0.45
    local t2 = math.max(1, t * 0.55)
    g.setColor(c[1], c[2], c[3], a2)
    -- the outer ring the same way, half as many ticks: it is the fainter
    -- one and it only has to say "this is wider"
    for k2 = 0, 3 do
      local ang = k2 * 1.5708 + 0.7854
      g.rectangle("fill", sx + math.cos(ang) * r2 - t2 * 0.5,
                  sy + math.sin(ang) * r2 * squash - t2 * 0.4, t2, t2 * 0.8)
    end
  end
  -- secondary flecks on the diagonals (particle burst)
  if k < 0.75 then
    local fr = r * (0.55 + k * 0.9)
    local fa = a * 0.7
    local ft = math.max(1, t * 0.55)
    g.setColor(c[1], c[2], c[3], fa)
    g.rectangle("fill", sx - fr * 0.75, sy - fr * 0.55, ft, ft)
    g.rectangle("fill", sx + fr * 0.55, sy - fr * 0.5, ft, ft)
    g.rectangle("fill", sx - fr * 0.65, sy + fr * 0.35, ft, ft)
    g.rectangle("fill", sx + fr * 0.5, sy + fr * 0.4, ft, ft)
  end
  -- rebound droplet (collision bounce-up, dies fast)
  if k < 0.40 and surf ~= "roof" then
    local up = s * (1.6 - k * 3.2)
    g.setColor(c[1], c[2], c[3], (1 - k / 0.40) * 0.8 * power)
    g.rectangle("fill", sx - t * 0.35, sy - up - s * 0.4, t * 0.7, s * 1.4)
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
  if not kind then
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
  local g = love.graphics
  local prevBlend, prevAlpha = g.getBlendMode()
  g.setBlendMode("alpha")

  for _, m in ipairs(motes) do
    local sx, sy, ps = project(m.x, m.y, m.z)
    if sx then
      local s = math.max(1, scale * (ps or 1))
      if m.kind == "splash" then
        drawSplash(g, sx, sy, s, m, power)
      elseif m.kind == "drip" then
        local c = Weather.RAIN_NEAR
        local a = 0.7 * power
        local t = math.max(1, s * 0.7)
        local h = s * 2.4
        g.setColor(c[1], c[2], c[3], a)
        g.rectangle("fill", sx - t * 0.4, sy - h, t * 0.8, h)
      else
        local c = Weather.SNOW
        local fade = math.min(1, m.t * 3, m.y / 6)
        g.setColor(c[1], c[2], c[3], 0.92 * fade * power)
        local d = math.max(1, s * m.size)
        g.rectangle("fill", sx - d * 0.5, sy - d * 0.5, d, d)
      end
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
