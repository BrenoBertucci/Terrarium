-- Voxel world mode: the wind you can SEE.
--
-- Wind.lua bends the grass, and the grass is where the wind is really read
-- -- but a meadow only tells you about the air that is inside it. Stand on
-- a path, on paving, on sand, at the edge of a route with no tall grass in
-- frame, and a gale is invisible: the one thing in the world that could
-- have shown it is not on screen. That is the gap this file fills.
--
-- ------- what it draws, and why it is not a particle system
--
-- Streaks. Short comet-tails of whatever the air is carrying -- dust off a
-- path, pollen and seed off a meadow, spray under a shower, snow off the
-- ground under a fall -- each one a two-pixel line drawn along the bearing
-- it is travelling, fading in and out at its ends. Nothing here is round,
-- soft-edged, additive or gradient-filled: a soft particle over a
-- cel-shaded diorama is the one thing that reads as a filter laid on the
-- world rather than as something in it, which is the same rule the rain's
-- own streaks are drawn under (see Weather.lua's palette note).
--
-- ------- the gust front, which is the whole point
--
-- A constant scatter of motes is atmosphere and reads as dust in a sunbeam.
-- What makes air read as WEATHER is that it arrives: Wind.gustNow is the
-- squall envelope the grass shader is already bending to, and when it
-- crosses over, this file throws a rank of streaks abreast -- perpendicular
-- to the bearing, upwind of the player, all on one clock -- so the gust
-- crosses the frame as a line and the grass bows under it as it passes.
-- The two are the same event seen twice, which is why the front here is
-- taken from the same number rather than rolled on its own.
--
-- ------- what it costs
--
-- One table of at most WindFX.MAX records, one update loop, one draw loop
-- of two `line` calls each, and it is skipped outright whenever the wind is
-- below WindFX.FLOOR, the sky is closed, or the diorama is not on screen.
-- No mesh, no canvas, no shader: the world's air should not cost what the
-- world's water does.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local DayNight = V.require("DayNight")
local Wind = V.require("Wind")
local Weather = V.require("Weather")
local Quality = V.require("Quality")

local Map = require("src.world.Map")

local WindFX = {}

local function game()
  return require("src.core.Game")
end

local rand = love.math.random

-- Below this tip-reach the air shows nothing at all. A calm day is calm,
-- and motes drifting through a still meadow would be the effect announcing
-- itself -- which is exactly the failure the AUTO row exists to avoid.
WindFX.FLOOR = 0.85

-- ------- the numbers, and the screenshot that set them
--
-- The first cut of this file was measured rather than eyeballed and passed
-- every count -- five streaks alive, WIND OFF clean -- while the actual
-- frame showed nothing at all. Five one-pixel lines at a quarter alpha,
-- four pixels long, thrown in seven cells upwind of a camera that mostly
-- looks the other way, is a feature that exists only in the log. The
-- numbers below are what it took to make the same frame READ:
--
--   more of them        five is a rounding error across a 320-wide frame
--   nearer the middle   spawned four cells upwind, not seven, and scattered
--                       across six cells rather than ten, so they cross
--                       where the camera is actually pointed
--   longer tails        a streak is legible at eight or nine pixels and
--                       invisible at four -- TAIL is in SECONDS of travel,
--                       so it is the wind's own speed that draws it
--   brighter            over green grass at half alpha, warm dust is the
--                       grass. It has to sit clearly above its background.
-- The ceiling. What the device will actually carry is Quality.windStreaks,
-- which cuts it by RES rung and reaches zero at 1/4 -- each streak is two
-- world-space projections and a line, and at the bottom rung the frame is
-- 23 thousand pixels and a streak is a smear across four of them.
WindFX.MAX = 30                -- streaks alive at once, gale and gust included
WindFX.REACH = 10              -- cells from the player anything lives within
WindFX.SPAWN_AHEAD = 4         -- cells UPWIND a streak is thrown in from
WindFX.SPAWN_WIDE = 6          -- and the cells either side it scatters over
WindFX.SPEED = 34              -- world px/second per unit of Wind.amount
WindFX.TAIL = 0.17             -- seconds of travel a tail is drawn back over

-- The gust front: how far into a squall it fires, and how long it must
-- wait before it may fire again. The cooldown is what keeps a front an
-- event -- without it a windy minute is one continuous rank of streaks,
-- which is the same flat texture the constant scatter would have been.
WindFX.FRONT_AT = 0.70
WindFX.FRONT_WAIT = 2.6
WindFX.FRONT_WIDE = 7          -- cells across the rank stands
WindFX.FRONT_N = 7             -- streaks in it

-- Flat palette, on the same 5-bit lattice as the rain's. Dust is warm and
-- dim because it is lit by the same sun the ground is; spray is the rain's
-- own far blue so a shower's air matches a shower's streaks; blown snow is
-- the snow's white. Nothing is white-hot -- these sit IN the world's light.
WindFX.DUST = { 0.95, 0.91, 0.74 }
WindFX.SPRAY = { 0.74, 0.83, 0.97 }
WindFX.BLOWN = { 0.97, 0.98, 1.00 }

local motes = {}
local frontCool = 0

local function openSky(map)
  if not (map and map.def) then return false end
  if not Map.isOutdoor(map.def) then return false end
  return not DayNight.isCanopy(map)
end

-- What the air is carrying right now, and how bright it is allowed to be.
-- Falling weather wins: under a shower the air is full of spray and there
-- is no dust in it, which is both true and what keeps a rainy frame from
-- carrying two unrelated palettes at once.
local function carried()
  local kind = Weather.visible()
  if kind == "rain" then return WindFX.SPRAY, 0.62 end
  if kind == "snow" then return WindFX.BLOWN, 0.80 end
  return WindFX.DUST, 0.58
end

-- What this device will carry this frame, ceiling included.
local function budget()
  local n = WindFX.MAX
  local ok, q = pcall(Quality.windStreaks)
  if ok and tonumber(q) then n = math.floor(q) end
  if n < 0 then n = 0 end
  if n > WindFX.MAX then n = WindFX.MAX end
  return n
end

local function spawn(px, pz, amount, opts)
  if #motes >= budget() then return end
  opts = opts or {}
  local dx, dz = Wind.DIR[1] or 1, Wind.DIR[2] or 0
  -- upwind of the player by SPAWN_AHEAD cells, scattered across the bearing
  local back = (opts.back or WindFX.SPAWN_AHEAD) * 16
  local side = (opts.side ~= nil) and opts.side
               or (rand() * 2 - 1) * WindFX.SPAWN_WIDE * 16
  local x = px - dx * back - dz * side
  local z = pz - dz * back + dx * side
  motes[#motes + 1] = {
    x = x,
    z = z,
    -- Low, but clear of the tufts: this is air moving OVER the ground, and
    -- a mote at head height reads as an insect -- while one down at a
    -- pixel or two is inside the grass it is supposed to be crossing and
    -- never comes out. A few ride higher so the column has depth.
    y = 3 + rand() * (rand() < 0.2 and 14 or 8),
    seed = rand() * 6.2831,
    t = 0,
    ttl = 1.6 + rand() * 1.9,
    -- each mote keeps its own share of the wind: the air is not one speed
    fast = 0.72 + rand() * 0.75,
    lift = (rand() * 2 - 1) * 5,
    front = opts.front or false,
    amount = amount,
  }
end

-- A rank abreast, thrown in perpendicular to the bearing: the squall
-- itself, arriving. Every streak in it shares one clock, which is what
-- makes it read as a line crossing the meadow rather than as more scatter.
local function spawnFront(px, pz, amount)
  local n = WindFX.FRONT_N
  if n < 1 then return end
  local cap = budget()
  local wide = WindFX.FRONT_WIDE * 16
  for i = 1, n do
    if #motes >= cap then break end
    -- -1 .. 1 across the rank. The span is guarded because FRONT_N is a
    -- tunable and a rank of ONE would divide by zero here -- and a NaN
    -- position does not crash, it silently puts the streak nowhere.
    local f = (n > 1) and ((i - 1) / (n - 1) * 2 - 1) or 0
    spawn(px, pz, amount, {
      back = WindFX.SPAWN_AHEAD + 1.5,
      side = f * wide + (rand() * 2 - 1) * 10,
      front = true,
    })
  end
end

function WindFX.clear()
  if #motes > 0 then motes = {} end
end

function WindFX.update(dt, voxelOn)
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
  frontCool = frontCool - dt

  local amount = 0
  local okA, n = pcall(Wind.amount)
  if okA then amount = n or 0 end

  local cap = budget()
  local Game = game()
  local ow = Game and Game.overworld
  local live = voxelOn and cap > 0 and amount > WindFX.FLOOR
                and ow and ow.map and ow.player
                and openSky(ow.map)
                and Game.stack and Game.stack:top() == ow
                and not ow.transitioning
  if not live then
    WindFX.clear()
    return
  end

  local p = ow.player
  local px, pz = p.cellX * 16, p.cellY * 16

  -- Standing density: a share of the reach above the floor, so a breeze
  -- carries a few specks and a gale carries a stream.
  local over = amount - WindFX.FLOOR
  local want = math.floor(6 + over * 7.0)
  if want > cap - WindFX.FRONT_N then
    want = cap - WindFX.FRONT_N
  end
  if want < 0 then want = 0 end
  local standing = 0
  for i = 1, #motes do
    if not motes[i].front then standing = standing + 1 end
  end
  -- three a frame rather than two: at a two-second life the field has to
  -- refill as fast as it empties or a gale runs at half the density it
  -- asked for
  for _ = 1, math.min(3, math.max(0, want - standing)) do
    spawn(px, pz, amount)
  end

  -- and the front, off the same envelope the grass is bending to
  local gust = 0
  local okG, g = pcall(Wind.gust)
  if okG then gust = g or 0 end
  if gust >= WindFX.FRONT_AT and frontCool <= 0 then
    frontCool = WindFX.FRONT_WAIT
    spawnFront(px, pz, amount)
  end

  local dx, dz = Wind.DIR[1] or 1, Wind.DIR[2] or 0
  local speed = amount * WindFX.SPEED
  local reach = WindFX.REACH * 16 + 48
  for i = #motes, 1, -1 do
    local m = motes[i]
    m.t = m.t + dt
    local v = speed * m.fast
    -- a curl across the bearing, on the mote's own phase: air tumbles, and
    -- a speck travelling in a dead-straight line reads as a bullet
    local curl = math.sin(m.t * 2.4 + m.seed) * 0.30
               + math.sin(m.t * 5.1 + m.seed * 1.7) * 0.14
    m.vx = dx * v - dz * v * curl
    m.vz = dz * v + dx * v * curl
    m.x = m.x + m.vx * dt
    m.z = m.z + m.vz * dt
    m.y = m.y + (m.lift + math.sin(m.t * 3.3 + m.seed) * 6) * dt
    if m.y < 0.5 then m.y = 0.5 end
    if m.t >= m.ttl
       or math.abs(m.x - px) > reach or math.abs(m.z - pz) > reach then
      table.remove(motes, i)
    end
  end
end

function WindFX.draw(project, scale)
  if #motes == 0 then return end
  local g = love.graphics
  local colour, bright = carried()
  local prevBlend, prevAlpha = g.getBlendMode()
  local prevWidth = g.getLineWidth and g.getLineWidth() or 1
  g.setBlendMode("alpha")

  -- ------- two passes, and the reason is state changes
  --
  -- Drawn in one loop, a streak sets the line width, sets the colour, and
  -- draws one two-point line: three calls each and a width change between
  -- every pair of them, thirty times a frame. Line width is the expensive
  -- one -- it is pipeline state, not a uniform. So the field is walked
  -- twice, once for the trailing streaks and once for the front's, with
  -- the width set ONCE per group. Alpha still varies per streak, so the
  -- colour call stays; there is no batching a per-streak fade without a
  -- mesh, and a mesh for thirty lines costs more than it saves.
  local scl = scale or 1
  for pass = 0, 1 do
    local wantFront = (pass == 1)
    local widthSet = false
    for i = 1, #motes do
      local m = motes[i]
      if (m.front and true or false) == wantFront then
        -- the tail is where this mote WAS: projected as a second world
        -- point rather than smeared in screen space, so a streak lies down
        -- along the ground the way the camera sees the ground and not
        -- along the screen
        local sx, sy, ps = project(m.x, m.y, m.z)
        if sx then
          -- in over the first fifth, out over the last third
          local fade = math.min(1, m.t * 5, (m.ttl - m.t) * 3)
          local a = bright * fade * (wantFront and 1.25 or 0.9)
          if a > 0.01 then
            local s = math.max(1, scl * (ps or 1))
            if not widthSet then
              g.setLineWidth(math.max(1, s * (wantFront and 1.1 or 0.8)))
              widthSet = true
            end
            local tx = m.x - (m.vx or 0) * WindFX.TAIL
            local tz = m.z - (m.vz or 0) * WindFX.TAIL
            local ex, ey = project(tx, m.y, tz)
            g.setColor(colour[1], colour[2], colour[3], math.min(1, a))
            if ex then
              g.line(sx, sy, ex, ey)
            else
              g.rectangle("fill", sx - s * 0.5, sy - s * 0.5, s, s)
            end
          end
        end
      end
    end
  end

  if g.setLineWidth then g.setLineWidth(prevWidth) end
  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  g.setColor(1, 1, 1, 1)
end

-- How many streaks are alive. Probes read this; nothing in the game does.
function WindFX.count()
  return #motes
end

return WindFX
