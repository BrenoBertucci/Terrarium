-- The one place a particle is integrated.
--
-- Before this file there were two solvers. WindFX kept a flat array of
-- motes, walked it backwards and cut the dead out with table.remove; the
-- weather's world motes kept a second array and stepped it its own way.
-- Both sampled the same air (Wind.flowAt, in bands, the field the meadow
-- is already bending to), and both then integrated it differently.
--
-- That duplication is the actual cost. Not the milliseconds -- at the
-- rungs anybody plays at, Quality.windStreaks caps the wind field at 110
-- motes and the arithmetic is nothing. The cost is that occlusion,
-- lighting, turbulence and drag are each ONE change here and TWO
-- everywhere else, and the second one is the one that gets forgotten.
--
-- ------- WHAT THIS FILE DOES NOT DO YET, DELIBERATELY
--
-- The integration below started as a port that reproduced WindFX's
-- existing motion to the letter -- a refactor whose look changes is a
-- refactor nobody can verify. The physics seams it cut are now live:
-- TURBULENCE through ctx.turbulence (T7 -- the eddy field lives in Wind,
-- this file only integrates it), and MASS/AREA through the drag
-- relaxation below (T8). What remains deliberately absent is vertical
-- physics: no gravity, no settling -- the bob/lift ladder is the look,
-- and a leaf that truly fell out of the air would leave the field.
--
-- ------- THE POOL
--
-- Dead particles are swapped with the last live one and the tail is kept
-- as a freelist rather than dropped, so a steady field allocates its
-- tables once and then never again. The array is never shifted: the old
-- table.remove moved every element after the dead one, which with the caps
-- in play was small, but it was also the reason the update had to walk
-- backwards, and a loop whose direction is load-bearing is a loop that
-- breaks the next time somebody touches it.

local V = ...

local Wind = V.require("Wind")

local Particles = {}

local sin = math.sin

-- ------- KINDS
--
-- What separates one particle from another, in one table. A client owns
-- its own kind table and hands it in; nothing here knows what "grit" is.
--
--   speed      multiplier on the wind the field hands this particle. A
--              number, or a function(p, t) for the ones that pulse.
--   bob        amplitude of the vertical wander, world px
--   lowClamp   how far above the ground under it the particle is held
--   highClamp  and how far below its ceiling
--   curlA      the two-sine cross-bearing wander, first term
--   curlB      and second
--   mass       with `area`, the particle's drag relaxation time (T8):
--   area       tau = Particles.TAU * mass / area, seconds. The velocity
--              is a STATE that converges to the air's target with that
--              time constant, so a dense grain shrugs at an eddy a leaf
--              orbits. mass = 0 is the escape hatch: tau 0, the blend
--              becomes 1, and the particle is the pre-T8 kinematic one,
--              velocity slaved to the air every frame.
--
-- Defaults are WindFX's own numbers, so a kind that specifies nothing
-- behaves the way its grit did.
Particles.DEFAULT = {
  speed = 1.0,
  bob = 3.0,
  lowClamp = 0.8,
  highClamp = 28,
  curlA = 0.28,
  curlB = 0.12,
  mass = 1.0,
  area = 1.0,
}

-- Seconds of relaxation per unit of mass/area. The scale was picked off
-- the shipping kinds' own ratios (T1 wrote them long before this ran):
-- leaf 0.055 -> tau 8ms, faithful to every eddy; grit 1.33 -> 0.20s,
-- a dense grain that answers a 1Hz eddy at ~60% amplitude and half a
-- turn late; dash 1.43 -> 0.21s, the heaviest thing in the air. In
-- STEADY air every tau converges to the same target, so the baseline
-- look is untouched -- mass shows only in the transients (gust arrival,
-- eddies, the bearing's meander), which is where material reads.
Particles.TAU = 0.15

local DEFAULT = Particles.DEFAULT

local function param(k, name)
  local v = k[name]
  if v == nil then return DEFAULT[name] end
  return v
end

-- ------- A FIELD

local Field = {}
Field.__index = Field

-- kinds is the caller's kind table; cap its hard ceiling (a LIVE cap, not
-- an allocation one -- the freelist may hold more tables than this).
function Particles.newField(kinds, cap)
  return setmetatable({
    kinds = kinds or {},
    cap = tonumber(cap) or 256,
    n = 0,              -- live count
    pool = {},          -- 1..n live, n+1..#pool dead but allocated
  }, Field)
end

function Field:count() return self.n end

function Field:full() return self.n >= self.cap end

function Field:get(i)
  if i < 1 or i > self.n then return nil end
  return self.pool[i]
end

function Field:setCap(cap)
  cap = tonumber(cap) or self.cap
  if cap < 0 then cap = 0 end
  self.cap = cap
  while self.n > cap do self:kill(self.n) end
end

-- Hand back a table to fill, or nil if the field is at its cap. The table
-- is WIPED before it is returned: a reused slot that kept a previous
-- particle's tint or frame is a bug that only shows up under load, which
-- is the worst kind to go looking for.
function Field:claim()
  if self.n >= self.cap then return nil end
  self.n = self.n + 1
  local p = self.pool[self.n]
  if p then
    for key in pairs(p) do p[key] = nil end
  else
    p = {}
    self.pool[self.n] = p
  end
  return p
end

-- Swap-remove: the last live particle takes the dead one's slot, and the
-- dead table stays in the array past n to be claimed again.
function Field:kill(i)
  local n = self.n
  if i < 1 or i > n then return end
  local dead = self.pool[i]
  self.pool[i] = self.pool[n]
  self.pool[n] = dead
  self.n = n - 1
end

function Field:clear()
  self.n = 0             -- tables stay, for the freelist
end

-- Drop the freelist too. For a map change, where the next field may be a
-- different size and holding a hundred tables is not worth it.
function Field:release()
  self.n = 0
  for i = #self.pool, 1, -1 do self.pool[i] = nil end
end

-- ------- THE STEP
--
-- ctx carries what is true of the whole field this frame rather than of
-- one particle:
--
--   dirX, dirZ   the wind's bearing (Wind.DIR)
--   speed        world px/s at band 1 -- the client's own scale
--   floorAt      function(x, z) -> ground height under a point. REQUIRED
--                in practice: a particle held above world zero instead of
--                above the ground under it runs inside a town's raised
--                paving and through a roof, which is the bug this
--                argument exists to prevent.
--   originX/Z    what the reach is measured from (the player)
--   reach        world px past which a particle is gone
--   turbulence   world px/s this client gives one unit of eddy. The eddy
--                itself is Wind's (turbAt: precomputed, divergence-free,
--                zero when calm) -- this is only the client's conversion
--                rate, the same shape as `speed`. Nil or 0 = laminar,
--                which is what every client that predates T7 gets.
--
-- Returns the live count.
function Field:step(dt, ctx)
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
  if self.n == 0 or dt == 0 then return self.n end

  local kinds = self.kinds
  local dirX = ctx.dirX or 1
  local dirZ = ctx.dirZ or 0
  local speed = ctx.speed or 0
  local floorAt = ctx.floorAt
  local ox = ctx.originX or 0
  local oz = ctx.originZ or 0
  local reach = ctx.reach or 1e9
  local turb = tonumber(ctx.turbulence) or 0
  local flowAt = Wind.flowAt
  local turbAt = Wind.turbAt
  local TAU = Particles.TAU

  local i = 1
  while i <= self.n do
    local p = self.pool[i]
    -- ------- A PARKED PARTICLE IS A FIXTURE, NOT PART OF THE FIELD
    --
    -- Nothing in the game sets this; probes do. A measurement of whether
    -- the world is allowed to hide a particle has to be taken of the SAME
    -- pixel in both builds, and a particle that ages, drifts, bobs, gets
    -- clamped to the ground under it or falls out of reach is not the same
    -- pixel twice. The clamp matters most: a probe wants to put a mote
    -- INSIDE a building, and the ordinary path would lift it onto the roof
    -- and quietly test nothing.
    if p.pinned then
      i = i + 1
    else
    local t = p.t + dt
    p.t = t

    local k = kinds[p.kind] or DEFAULT

    -- the air this particle is in, in bands -- the same field the grass
    -- and the rain are already reading
    local _, _, band = flowAt(p.x, p.z)
    local v = speed * (p.fast or 1) * ((band and band > 0) and band or 1)
    local sm = param(k, "speed")
    if type(sm) == "function" then sm = sm(p, t) end
    v = v * (sm or 1)

    -- Curl across the bearing: air tumbles, and a dead-straight particle
    -- reads as a bullet. Two sines rather than one so the wander does not
    -- repeat on a period the eye can count. Kept UNDER the turbulence:
    -- this is the particle's own flutter, per-particle in TIME; the eddy
    -- below is the air's structure in SPACE, and they answer different
    -- questions (a mote flutters even in a laminar band).
    local seed = p.seed or 0
    local curl = sin(t * 2.1 + seed) * param(k, "curlA")
               + sin(t * 4.6 + seed * 1.7) * param(k, "curlB")

    local vx = dirX * v - dirZ * v * curl
    local vz = dirZ * v + dirX * v * curl

    -- The eddy this particle is inside of. Spatial, shared and
    -- divergence-free (Wind.turbAt), so two motes a cell apart part ways
    -- here -- the thing the per-particle curl cannot do -- and the field
    -- stirs without herding anything into clumps.
    if turb ~= 0 then
      local ux, uz = turbAt(p.x, p.z)
      vx = vx + ux * turb
      vz = vz + uz * turb
    end

    -- ------- MASS (T8): the velocity is a state, not a slave
    --
    -- Everything above is the air's TARGET for this particle. What the
    -- particle actually does is converge on it with its own relaxation
    -- time -- implicit blend, dt/(tau+dt), stable at any dt and exactly
    -- the kinematic old motion when tau is 0. A particle's first frame
    -- has no state yet and starts AT the target, which is what spawning
    -- into the wind always looked like.
    local mass = param(k, "mass")
    if mass and mass > 0 then
      local area = param(k, "area")
      local tau = TAU * mass / ((area and area > 0) and area or 1)
      local blend = dt / (tau + dt)
      local pvx = p.vx
      if pvx then
        vx = pvx + (vx - pvx) * blend
        vz = p.vz + (vz - p.vz) * blend
      end
    end
    p.vx, p.vz = vx, vz
    p.x = p.x + vx * dt
    p.z = p.z + vz * dt

    p.y = p.y + ((p.lift or 0) + sin(t * 2.8 + seed) * param(k, "bob"))
                * dt * 0.55

    -- ------- HELD ABOVE THE GROUND, NOT ABOVE ZERO
    if floorAt then
      local g = floorAt(p.x, p.z)
      local lo = g + param(k, "lowClamp")
      local hi = g + param(k, "highClamp")
      if p.y < lo then p.y = lo elseif p.y > hi then p.y = hi end
    end

    p.ang = (p.ang or 0) + (p.spin or 0) * dt

    local dx = p.x - ox
    local dz = p.z - oz
    if dx < 0 then dx = -dx end
    if dz < 0 then dz = -dz end
    if t >= (p.ttl or 0) or dx > reach or dz > reach then
      self:kill(i)                 -- the swapped-in particle lands on i,
    else                           -- so i does NOT advance here
      i = i + 1
    end
    end                            -- (not pinned)
  end

  return self.n
end

-- Count live particles a predicate accepts. For callers that budget one
-- sub-population separately (the gust front against the standing field,
-- say) without keeping a second array for it.
function Field:countIf(fn)
  local c = 0
  for i = 1, self.n do
    if fn(self.pool[i]) then c = c + 1 end
  end
  return c
end

Particles.Field = Field

return Particles
