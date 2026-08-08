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
-- ------- the two registers
--
-- Rain is drawn twice, and it has to be.
--
--   STREAKS are SCREEN-SPACE: flat pale lines falling across the whole frame,
--            slanted by the WIND row's own bearing. Rain between the camera
--            and the world has no world position -- it is in front of
--            everything, including the near edge of the diorama -- and
--            trying to give it one puts it behind the trees.
--
--   SPLASHES are WORLD-SPACE: little cel-shaded rings that open and vanish on
--            the ground around the player, projected through the same camera
--            the field FX and the ambient life anchor through. They are what
--            says the rain is landing on THIS world rather than on the lens,
--            and they are the reason the effect survives the camera moving.
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
-- for distance -- which is both what happens and what makes a far strike read
-- as far without anything having to say so. The flash is owned here because
-- it is a picture; the rumble is played by lib/AmbientSound, which polls
-- `thunderDue` for it. That is also why the dependency only points one way:
-- the sound module reads this file and this file reads nothing of it.
Weather.STRIKE_ABOVE = 0.78         -- power below which it never strikes
Weather.STRIKE_EVERY_MIN = 12
Weather.STRIKE_EVERY_MAX = 45
Weather.FLASH_LEN = 0.34            -- seconds the sky stays lit

-- After a rain shower clears: rainbow + saturated sky for a short spell of
-- absolute (wall-clock) time, then gone with no residual flag left behind.
-- 180s is three minutes of real time -- the same clock Weather.timer rides.
Weather.AFTER_RAIN = 180

local strike = { at = 1e9, next = 20, pending = false, far = 0 }

-- after.untilAbs is love.timer absolute seconds; 0 means idle.
-- hadRain latches while a rain spell is (or was) in progress so a pin->OFF
-- that nils `kind` before power hits zero still arms the post-rain spell.
local after = { untilAbs = 0, hadRain = false }

local function absNow()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return 0
end

-- Continuous 0..1 curve (for math); Weather.flash posterises it to hard steps.
local function flashRaw()
  local t = strike.at
  if t >= Weather.FLASH_LEN then return 0 end
  local shape = 1 - t / Weather.FLASH_LEN
  -- the flicker: bright, a gap, bright again
  if t > 0.06 and t < 0.11 then shape = shape * 0.15 end
  return shape * (0.55 + 0.45 * (1 - strike.far))
end

-- 0 / 0.5 / 1 only: a cel strike is a hard plate of light, not a soft ramp.
-- Soft alpha read as bloom-adjacent and as a screen transition.
function Weather.flash()
  local cont = flashRaw()
  if cont < 0.18 then return 0 end
  if cont < 0.55 then return 0.5 end
  return 1
end

-- Once per strike, when the sound has had time to arrive: the strike's
-- distance, 0 (overhead) to 1 (far). nil the rest of the time.
function Weather.thunderDue()
  if not strike.pending then return nil end
  local delay = 0.15 + strike.far * 2.4
  if strike.at < delay then return nil end
  strike.pending = false
  return strike.far
end

-- Heavy rain that can strike: the same gate the strike scheduler uses.
-- Ecology and AmbientSound read this; nothing writes back.
function Weather.storming()
  local kind, power = Weather.visible()
  return kind == "rain" and (power or 0) >= Weather.STRIKE_ABOVE
end

-- 0..1 remaining intensity of the post-rain spell (rainbow + sky sat).
-- Absolute time so two readers in one frame never desync on dt.
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

-- Probe / debug: arm a strike now. `far` 0 = overhead, 1 = distant.
function Weather.forceStrike(far)
  local f = tonumber(far)
  if f == nil then f = 0.35 end
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  strike.at, strike.pending, strike.far = 0, true, f
end

-- Probe / debug: start (or refresh) the post-rain window.
function Weather.armAfterRain(seconds)
  local s = tonumber(seconds) or Weather.AFTER_RAIN
  if s < 0 then s = 0 end
  after.untilAbs = absNow() + s
end

-- Delay seconds until thunder for a given far (or the pending strike's far).
function Weather.thunderDelay(far)
  local f = far
  if f == nil then f = strike.far end
  f = tonumber(f) or 0
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  return 0.15 + f * 2.4
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
-- Screen-space streaks and world-space splashes and flakes, all in one list
-- with a `kind` on each, exactly like the ambient life's critters -- and for
-- the same reason: one list means one update loop and one draw loop, and the
-- caps below mean the loop is always short.
local drops = {}                    -- screen-space rain streaks
local motes = {}                    -- world-space splashes and snowflakes

-- Streak count at full power, per 320x288 of canvas -- so the frame is as
-- full of rain at 1/4 resolution as it is at full, instead of thinning out
-- every time the RES row is turned down.
Weather.STREAKS = 34
Weather.STREAKS_MAX = 240
-- Splashes and flakes are counted in the WORLD rather than on the screen, and
-- most of the ground they are scattered over is behind the camera or under
-- the frame -- so the numbers that read right on screen are roughly double
-- what a screen-space count would want. Measured off the probe's shots at
-- VOXEL 75 rather than guessed.
Weather.SPLASHES = 24
Weather.FLAKES = 90

Weather.FALL = 900                  -- streak fall speed, canvas px/second
Weather.SLANT = 0.20                -- how far a streak leans, before wind

-- The rain's own palette: two flat pale blues and a white, all on the 5-bit
-- lattice the rest of the mod's colour lives on. No gradients anywhere in
-- here -- a soft-edged raindrop over a cel-shaded diorama is the one thing
-- that would make the world look like a photograph with a filter on it.
Weather.RAIN_NEAR = { 0.78, 0.86, 0.97 }
Weather.RAIN_FAR = { 0.55, 0.66, 0.85 }
Weather.SPLASH = { 0.85, 0.92, 1.00 }
Weather.SNOW = { 0.97, 0.98, 1.00 }

local function slant()
  -- rain leans on the wind, and the wind already has a bearing and a strength
  -- this world agrees on (Wind.DIR / Wind.amount). Only the X of it matters
  -- on screen, and only a share of it: rain that lay flat would be a gale.
  local amount = 0
  local ok, n = pcall(Wind.amount)
  if ok then amount = n or 0 end
  return Weather.SLANT + (Wind.DIR[1] or 1) * amount * 0.075
end

-- A fresh streak somewhere above the frame (or, on the first fill, anywhere
-- in it -- otherwise a shower starts as a curtain descending from the top).
local function spawnDrop(w, h, anywhere)
  drops[#drops + 1] = {
    x = rand() * (w + h * 0.6) - h * 0.3,
    y = anywhere and rand() * h or -rand() * h * 0.4,
    len = 8 + rand() * 16,
    speed = 0.75 + rand() * 0.5,
    near = rand() < 0.4,
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
    size = inPool and Weather.SPLASH_POOL_SIZE or 1,
    t = 0, ttl = (inPool and 0.44 or 0.34) + rand() * 0.16,
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
  if visible == "rain" and state.power >= Weather.STRIKE_ABOVE then
    strike.next = strike.next - dt
    if strike.next <= 0 then
      strike.next = Weather.STRIKE_EVERY_MIN
                    + rand() * (Weather.STRIKE_EVERY_MAX
                                - Weather.STRIKE_EVERY_MIN)
      strike.at, strike.pending, strike.far = 0, true, rand()
    end
  elseif strike.next < 5 then
    strike.next = 5
  end

  -- ------- the world-space half
  --
  -- Splashes and flakes need a map to stand on and a player to stand near, so
  -- they stop the moment either is missing -- and they are dropped outright
  -- when the sky closes over, rather than left to drift indoors.
  local canDraw = visible and ow and ow.map and ow.player
                  and Game.stack and Game.stack:top() == ow
                  and not ow.transitioning
  if not canDraw then
    if #motes > 0 then motes = {} end
    if #drops > 0 then drops = {} end
    return
  end

  local p = ow.player
  local px, pz = p.cellX * 16, p.cellY * 16

  if visible == "rain" then
    local want_n = math.floor(Weather.SPLASHES * state.power)
    for _ = 1, math.max(0, want_n - #motes) do spawnSplash(ow) end
  else
    local want_n = math.floor(Weather.FLAKES * state.power)
    for _ = 1, math.min(3, math.max(0, want_n - #motes)) do spawnFlake(ow) end
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
  drops, motes = {}, {}
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
local function stepDrops(w, h, dt, power)
  local want = math.floor(Weather.STREAKS * power * (w * h) / (320 * 288))
  if want > Weather.STREAKS_MAX then want = Weather.STREAKS_MAX end
  local first = #drops == 0
  for _ = 1, math.max(0, want - #drops) do spawnDrop(w, h, first) end
  while #drops > want do table.remove(drops) end

  local lean = slant()
  local scale = math.max(1, h / 288)
  for _, d in ipairs(drops) do
    local v = Weather.FALL * d.speed * scale * (0.6 + 0.4 * power)
    d.y = d.y + v * dt
    d.x = d.x + v * lean * dt
    if d.y > h then
      d.y = -d.len * scale - rand() * h * 0.2
      d.x = rand() * (w + h * 0.6) - h * 0.3
    end
  end
end

-- The streaks themselves: flat lines, two shades, no soft edges. NEAR drops
-- are brighter, longer and thicker; FAR ones are dimmer and thinner, and the
-- two together are the only depth cue rain in front of the world can have.
local function drawDrops(h, power)
  local g = love.graphics
  local lean = slant()
  local scale = math.max(1, h / 288)
  local prevWidth = g.getLineWidth and g.getLineWidth() or 1
  for _, d in ipairs(drops) do
    local c = d.near and Weather.RAIN_NEAR or Weather.RAIN_FAR
    local len = d.len * scale * (0.7 + 0.5 * power)
    g.setLineWidth((d.near and 1.6 or 1) * scale)
    g.setColor(c[1], c[2], c[3], (d.near and 0.55 or 0.34) * power)
    g.line(d.x, d.y, d.x + len * lean, d.y + len)
  end
  if g.setLineWidth then g.setLineWidth(prevWidth) end
end

-- ------- the draw
--
-- Inside the voxel overlay pass (main.lua's drawWorld), with the same project
-- function the field FX and the ambient life anchor through. Splashes and
-- flakes go down FIRST, so the screen-space rain falls in front of them --
-- which is the correct order, because a streak is by definition nearer than
-- the ground it is about to hit.
function Weather.draw(project, scale, w, h)
  -- visible, NOT falling: indoors and under a canopy this draws nothing at
  -- all -- no splashes, no flakes, no streaks and no lightning. See
  -- Weather.visible for why those are two different questions.
  local kind, power = Weather.visible()
  if not kind then
    -- and the streak field goes with it, so walking back out does not open
    -- on a screenful of rain that was accumulating behind the ceiling
    if #drops > 0 then drops = {} end
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
        -- a ring that opens and goes: four flat ticks on the cardinals rather
        -- than a circle, which is what a two-colour drawing of a splash is
        local k = m.t / m.ttl
        local r = s * (0.6 + k * 2.4) * (m.size or 1)
        local a = (1 - k) * 0.95 * power
        local c = Weather.SPLASH
        g.setColor(c[1], c[2], c[3], a)
        local t = math.max(1, s * 0.7)
        g.rectangle("fill", sx - r, sy - t * 0.5, r * 0.55, t)
        g.rectangle("fill", sx + r * 0.45, sy - t * 0.5, r * 0.55, t)
        g.rectangle("fill", sx - t * 0.5, sy - r * 0.5, t, r * 0.3)
        -- and the drop that made it, standing up out of the middle while the
        -- ring is young
        if k < 0.45 then
          g.setColor(c[1], c[2], c[3], (1 - k / 0.45) * 0.7 * power)
          g.rectangle("fill", sx - t * 0.4, sy - s * 2.2, t * 0.8, s * 2)
        end
      else
        local c = Weather.SNOW
        local fade = math.min(1, m.t * 3, m.y / 6)
        g.setColor(c[1], c[2], c[3], 0.92 * fade * power)
        local d = math.max(1, s * m.size)
        g.rectangle("fill", sx - d * 0.5, sy - d * 0.5, d, d)
      end
    end
  end

  if kind == "rain" and w and h then
    stepDrops(w, h, love.timer and love.timer.getDelta() or 0, power)
    drawDrops(h, power)
  end

  -- the strike, over everything: the sky lighting the whole diorama at once,
  -- which is what it does
  -- hard plate: lit is already 0 / 0.5 / 1; alpha is a fixed step, not a fade
  local lit = Weather.flash()
  if lit > 0 and w and h then
    g.setBlendMode("add")
    local a = lit >= 1 and 0.72 or 0.40
    g.setColor(0.62, 0.66, 0.82, a)
    g.rectangle("fill", 0, 0, w, h)
  end

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
  local lit = Weather.flash()
  if lit > 0 then
    g.setBlendMode("add")
    local a = lit >= 1 and 0.72 or 0.40
    g.setColor(0.62, 0.66, 0.82, a)
    g.rectangle("fill", 0, 0, w, h)
  end
  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  g.setColor(1, 1, 1, 1)
end

return Weather
