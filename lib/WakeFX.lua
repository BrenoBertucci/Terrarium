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

local V = ...
local Voxel3D = V.require("Voxel3D")
local StepFX = V.require("StepFX")
local RainOnFX = V.require("RainOnFX")

local Map = require("src.world.Map")

local WakeFX = {}

WakeFX.MAX = 8                 -- swimmers the sheet paints at once
WakeFX.SPEED_FULL = 70         -- world px/s that is a full-strength wake
WakeFX.FOAM_STRIDE = 7         -- px of travel between foam puffs
WakeFX.RISE = 5.0              -- how fast a wake grows when a swimmer moves
WakeFX.FALL = 1.3              -- and dissolves once they stop
WakeFX.REACH_X, WakeFX.REACH_Z = 280, 230   -- world px from the player

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

local function updateBody(dt, voxelOn)
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
  local list = {}
  Voxel3D.wake = list
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
end

function WakeFX.update(dt, voxelOn)
  local ok, err = pcall(updateBody, dt, voxelOn)
  if ok then return end
  WakeFX.errorCount = WakeFX.errorCount + 1
  WakeFX.lastError = tostring(err)
end

return WakeFX
