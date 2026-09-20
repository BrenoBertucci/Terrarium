-- What a swimmer does to the water.
--
-- A wild Tentacool crossing the lake, a Goldeen in the pond, the player
-- surfing: until now they sat on the sheet as if it were a floor. Water
-- answers a body moving through it, and the answer has a shape everybody
-- knows from every game that has ever put a boat on a lake: the V behind
-- it (a Kelvin wake, arms at nineteen and a half degrees), the bow wave
-- pushed ahead, ripples inside the V, and a trail of foam that lingers
-- after the swimmer has passed.
--
-- The V and the bow are the SHEET'S: lib/Voxel3D.lua's water fragment takes
-- up to MAX swimmers a frame (position, heading, speed, how much of a wake
-- they still own) and paints them, so they ride the swell, take the hour's
-- light and cost nothing when nobody is swimming. The foam trail is motes in
-- lib/StepFX.lua's field (kind "foam": lies on the surface, does not take
-- the wind, fades in a second and a half), laid every few pixels of travel
-- at the stern -- so a swimmer that turns leaves a trail that turns, which
-- a straight V behind the current heading cannot.
--
-- And the two moments the water is loudest: going IN throws a splash (the
-- same one a boot throws in a puddle, at full depth) and coming OUT leaves
-- the figure dripping for a few seconds (RainOnFX.soak -- the same drops a
-- shower leaves on them).
--
-- Who counts: `e.surfing` (the player on Surf, and every water roamer sets
-- it too -- lib/Roamer.lua) and roamers of kind "water". Read off the
-- entities the overworld already poses; nothing here moves anybody.
--
-- ------- and what a swimmer does to the GARDEN (lib/ReefKit.lua)
--
-- A plant is not paint: it has a root and a spring. Voxel3D.stir is the
-- packet the reef's draw reads through the eight crush slots the meadow
-- uses (VoxelScene swaps it in for that one draw):
--   the HULL of every swimmer in the water, first: the garden is shoved out
--     of its way, and STAYS shoved while it sits there (w = how present it
--     is, >= 0);
--   then the WAKE: a point every STIR_STRIDE px of travel, each a kick the
--     shader answers with every kind's own spring -- a reed whips back in a
--     fraction of a second, kelp comes back heavy, a pad drifts off and home
--     -- so what passes leaves the garden ringing behind it (w = -(age + 1),
--     how hard it was laid in the length of its bearing).
-- The player's wake first: the camera is on them.

local V = ...
local Voxel3D = V.require("Voxel3D")
local StepFX = V.require("StepFX")
local RainOnFX = V.require("RainOnFX")
local Quality = V.require("Quality")
local Water = V.require("Water")

local Map = require("src.world.Map")

local WakeFX = {}

WakeFX.MAX = 8                 -- swimmers the sheet paints at once
WakeFX.SPEED_FULL = 70         -- world px/s that is a full-strength wake
WakeFX.FOAM_STRIDE = 7         -- px of travel between foam puffs
WakeFX.RISE = 5.0              -- how fast a wake grows when a swimmer moves
WakeFX.FALL = 1.3              -- and dissolves once they stop
WakeFX.REACH_X, WakeFX.REACH_Z = 280, 230   -- world px from the player
WakeFX.HULL_R = 14             -- world px a body shoves the garden out of
WakeFX.STIR_R = 22             -- ...and a point of its wake reaches
WakeFX.STIR_STRIDE = 10        -- px of travel between wake points
WakeFX.STIR_LIFE = 4.0         -- s a point rings for (kelp's spring is the slowest)
WakeFX.STIR_KEEP = 6           -- points the player's wake keeps; others keep 2
WakeFX.STIR_HULLS = 2          -- hulls sent at most

-- for the probe
WakeFX.swimmers = 0
WakeFX.foamEmitted = 0
WakeFX.splashes = 0
WakeFX.exits = 0
WakeFX.lastGate = "never ran"
WakeFX.lastError = nil
WakeFX.errorCount = 0

local track = setmetatable({}, { __mode = "k" })
local FACE = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

local function game() return require("src.core.Game") end

local function isSwimmer(e)
  return (e.surfing or (e.roamer and e.kind == "water")) and true or false
end

local function approach(a, b, rate, dt)
  local k = 1 - math.exp(-rate * dt)
  return a + (b - a) * k
end

-- The garden's packet, in the shape Voxel3D.crush takes, reused every frame
local stirPacket = { n = 0, p = {} }
for i = 1, 8 do stirPacket.p[i] = { 0, 0, 0, 0, 0, 0 } end

local function stirGarden(player, px, pz)
  local cap = math.min(Quality.crushSlots(), 8)
  local calm = 1 - math.max(0, math.min(1, tonumber(Water.freeze) or 0))
  local now, n = WakeFX.clock, 0
  local function put(x, z, r, w, bx, bz)
    n = n + 1
    local s = stirPacket.p[n]
    s[1], s[2], s[3], s[4], s[5], s[6] = x, z, r, w, bx, bz
  end
  -- the hulls: every body in the water near the player, nearest first
  local near = {}
  for _, t in pairs(track) do
    if t.on and math.abs(t.x - px) < WakeFX.REACH_X and math.abs(t.z - pz) < WakeFX.REACH_Z then
      t.dist = (t.x - px) ^ 2 + (t.z - pz) ^ 2
      near[#near + 1] = t
    end
  end
  table.sort(near, function(a, b) return a.dist < b.dist end)
  for i = 1, math.min(#near, WakeFX.STIR_HULLS, cap) do
    local t = near[i]
    put(t.x, t.z, WakeFX.HULL_R, calm, t.dx, t.dz)
  end
  -- the wakes, the player's first (even just out of the water: it still
  -- rings), newest first
  local owners = { track[player] }
  for i = 1, #near do
    if near[i] ~= owners[1] then owners[#owners + 1] = near[i] end
  end
  for _, t in ipairs(owners) do
    local pts = t.stir or {}
    while pts[1] and now - pts[1].t0 >= WakeFX.STIR_LIFE do table.remove(pts, 1) end
    local room = cap - n
    local sent = math.min(#pts, room)
    for k = 0, sent - 1 do
      local q = pts[#pts - k]
      local age = now - q.t0
      local s = q.s * calm * math.min(1, WakeFX.STIR_LIFE - age)
      -- the last one sent leaves as the next is laid, so the tail never
      -- pops out of a garden still ringing with it
      if k == sent - 1 and (#pts > room or #pts >= (t.keep or 0)) then
        s = s * (1 - math.min(1, (t.stirAcc or 0) / WakeFX.STIR_STRIDE))
      end
      put(q.x, q.z, WakeFX.STIR_R, -(age + 1), q.dx * s, q.dz * s)
    end
  end
  stirPacket.n = n
  Voxel3D.stir = stirPacket
end

local function updateBody(dt, voxelOn)
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
  local list = {}
  Voxel3D.wake = list
  Voxel3D.stir = nil
  WakeFX.clock = (WakeFX.clock or 0) + dt
  local Game = game()
  local ow = Game and Game.overworld
  local live = voxelOn and ow and ow.map and ow.player
               and Map.isOutdoor(ow.map.def)
               and Game.stack and Game.stack:top() == ow
               and not ow.transitioning
  if not live then WakeFX.lastGate = "not live" return end
  WakeFX.lastGate = "live"
  local ents = { ow.player }
  for _, e in ipairs(ow.entities or {}) do
    if e ~= ow.player then ents[#ents + 1] = e end
  end
  local px, pz = (ow.player.px or 0) + 8, (ow.player.py or 0) + 8
  local count = 0
  for _, e in ipairs(ents) do
    local x, z = (e.px or 0) + 8, (e.py or 0) + 8
    local on = isSwimmer(e)
    local t = track[e]
    if not t then
      track[e] = { x = x, z = z, on = on, active = 0, dx = 0, dz = 1, acc = 0, speed = 0 }
    else
      local dx, dz = x - t.x, z - t.z
      local d = math.sqrt(dx * dx + dz * dz)
      if d > 24 then d = 0; dx, dz = 0, 0 end       -- a warp, not a sprint
      -- in, and out
      if on and not t.on then
        pcall(StepFX.splashAt, x, z, 1.0)
        WakeFX.splashes = WakeFX.splashes + 1
      elseif t.on and not on then
        pcall(RainOnFX.soak, e, 0.9)
        WakeFX.exits = WakeFX.exits + 1
      end
      t.on = on
      local speed = (dt > 0) and (d / dt) or 0
      if d > 0.05 then
        t.dx, t.dz = dx / d, dz / d
      else
        local f = FACE[e.facing]
        if f then t.dx, t.dz = f[1], f[2] end
      end
      local target = (on and speed > 8) and 1 or 0
      t.active = approach(t.active, target,
                          target > t.active and WakeFX.RISE or WakeFX.FALL, dt)
      t.speed = math.max(0, math.min(1, speed / WakeFX.SPEED_FULL))
      t.x, t.z = x, z
      if on then
        count = count + 1
        -- the wake the garden feels: a point where the bow is now, every
        -- STIR_STRIDE px (the oldest goes when a swimmer keeps too many)
        t.keep = (e == ow.player) and WakeFX.STIR_KEEP or 2
        t.stir = t.stir or {}
        t.stirAcc = (t.stirAcc or 0) + d
        while t.stirAcc >= WakeFX.STIR_STRIDE do
          t.stirAcc = t.stirAcc - WakeFX.STIR_STRIDE
          local pts = t.stir
          pts[#pts + 1] = { x = x, z = z, t0 = WakeFX.clock,
                            s = math.max(t.speed, 0.4), dx = t.dx, dz = t.dz }
          while #pts > t.keep do table.remove(pts, 1) end
        end
        -- the foam trail, laid at the stern on both quarters
        t.acc = t.acc + d
        while t.acc >= WakeFX.FOAM_STRIDE do
          t.acc = t.acc - WakeFX.FOAM_STRIDE
          for side = -1, 1, 2 do
            local fx = x - t.dx * 6 - t.dz * side * 2.5
            local fz = z - t.dz * 6 + t.dx * side * 2.5
            local ok = pcall(StepFX.foam, fx, fz, 0.7 + math.random() * 0.5)
            if ok then WakeFX.foamEmitted = WakeFX.foamEmitted + 1 end
          end
          -- and spray off the bow now and then: a few drops thrown up
          -- where the body meets the water, no sound -- the water's
          -- sound is the swimmer's own
          t.spray = (t.spray or 0) + 1
          if t.spray >= 3 and t.speed > 0.3 then
            t.spray = 0
            pcall(StepFX.splashAt, x + t.dx * 5, z + t.dz * 5, 0.25, true)
          end
        end
        if t.active > 0.02 and math.abs(x - px) < WakeFX.REACH_X
           and math.abs(z - pz) < WakeFX.REACH_Z then
          list[#list + 1] = { x, z, t.dx, t.dz, t.speed, t.active,
                              dist = (x - px) * (x - px) + (z - pz) * (z - pz) }
        end
      end
    end
  end
  WakeFX.swimmers = count
  if #list > WakeFX.MAX then
    table.sort(list, function(a, b) return a.dist < b.dist end)
    for i = #list, WakeFX.MAX + 1, -1 do list[i] = nil end
  end
  stirGarden(ow.player, px, pz)
end

function WakeFX.update(dt, voxelOn)
  local ok, err = pcall(updateBody, dt, voxelOn)
  if ok then return end
  WakeFX.errorCount = WakeFX.errorCount + 1
  WakeFX.lastError = tostring(err)
end

return WakeFX
