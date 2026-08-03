-- Voxel world mode: ambient life -- the small things that make a diorama
-- read as a PLACE rather than a model of one.
--
-- Six kinds of creature, none of them game objects:
--
--   butterflies  by day, over the tall grass, wandering a few cells from
--                where they hatched with a sine-bob flutter
--   fireflies    through dusk and the night, over the same grass, drifting
--                slowly and BLINKING -- drawn additive, so each one is a
--                point of light the night actually receives
--   birds        a small flock crossing the sky every half minute or so,
--                high over the roofs, gone off the far edge
--   sparrows     on the GROUND: hopping about the open cells, pecking at
--                nothing -- until the player comes within a couple of
--                cells, when they startle and fly off. The startle is the
--                whole point: ambience that reacts to you is the
--                difference between a diorama and a terrarium
--   dragonflies  darting over the water by day -- a hover, a dash to a new
--                spot, another hover, the way the real thing moves
--   leaves       while the wind blows, torn loose and carried on the same
--                gust the grass is bending under (the drift reads
--                Wind.amount, so a stronger WIND row means more weather)
--
-- And one behaviour for the people: CIVILIAN NPCs GLANCE. Walk within a
-- couple of cells of someone and they turn to look at you, the way anyone
-- would; walk on and a standing NPC turns back to where they were facing.
-- Strictly civilians only -- an NPC with a trainerClass is never touched,
-- because a trainer's facing IS their line of sight and turning one would
-- start (or dodge) fights the map never rolled. Wanderers keep whatever
-- facing their next step picks, exactly as before; scripts freeze NPCs and
-- frozen NPCs are left alone.
--
-- Everything here is PURELY PRESENTATIONAL, more so even than the rest of
-- the mod: nothing stands in a cell, nothing joins ow.entities, nothing can
-- be bumped, talked to or collided with. A critter is a dot with a clock,
-- simulated in world coordinates and drawn through Voxel3D.project into the
-- finished scene -- the same overlay pass the field FX composite through,
-- so the depth story is the sprite one: painted over the world, anchored to
-- it by the camera.
--
-- The population follows the world's own clocks. DayNight decides who is
-- awake -- butterflies sleep at night, fireflies are invisible at noon --
-- Wind decides whether leaves fly, Map.isOutdoor keeps everything out of
-- buildings and caves, and the canopy maps (Viridian Forest) keep their
-- birds: there is no sky to cross under a roof of leaves.
--
-- One OPTIONS row, AMBIENT ON/OFF, because every moving thing is one more
-- reason a slow device drops a frame -- though the whole population is a
-- few dozen rectangles with no texture, so OFF is about taste as much as
-- speed.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local DayNight = V.require("DayNight")
local Wind = V.require("Wind")

local Map = require("src.world.Map")

local AmbientLife = {}

AmbientLife.setting = ModSetting.new("ambient", "AMBIENT",
                                     { "on", "off" }, { "ON", "OFF" })

function AmbientLife.enabled()
  return AmbientLife.setting:get() == "on"
end

function AmbientLife.row()
  return AmbientLife.setting:row()
end

local function game()
  return require("src.core.Game")
end

-- ------- the population
--
-- World-pixel coordinates (a cell is 16), height in the same units the
-- geometry stands in, because every one of these is projected through the
-- camera exactly like a piece of terrain.
local critters = {}
local state = { mapId = nil, birdTimer = 12, spawnTick = 0 }

-- Caps, and they are deliberately small: ambience is a thing you notice
-- out of the corner of your eye, and twenty butterflies over one patch is
-- not a meadow, it is a lure.
local MAX_BUTTERFLY = 6
local MAX_LEAF = 6
local MAX_SPARROW = 3
local MAX_DRAGONFLY = 3
local SPAWN_EVERY = 0.5           -- seconds between spawn attempts
local CELL_TRIES = 12             -- cells sampled per attempt
local RADIUS = 11                 -- cells around the player a spawn may land
local STARTLE = 40                -- world px at which a sparrow flees

-- Fireflies come out with the DARK rather than with the clock. A flat cap
-- meant the same dozen at a lit dusk and at midnight, which is the one
-- thing that gave them away as a spawner: the drift over a field should
-- THICKEN as the light goes. DayNight.starAmount is the curve for it and is
-- already the right one -- it is how deep the night is with the weather
-- taken out, so a downpour thins them out for the same reason it puts the
-- stars away, and neither needs to ask the weather anything.
local FIREFLY_DEEP = 18           -- at the darkest part of a clear night
local FIREFLY_DIM = 3             -- and what a dusk with light still in it gets

local function fireflyCap()
  local amt = DayNight.starAmount and DayNight.starAmount() or 1
  return math.floor(FIREFLY_DIM + (FIREFLY_DEEP - FIREFLY_DIM) * amt + 0.5)
end

local rand = love.math.random

local function count(kind)
  local n = 0
  for _, c in ipairs(critters) do
    if c.kind == kind then n = n + 1 end
  end
  return n
end

-- A grass cell near the player, or nil. Grass is where the living things
-- are -- it is also, not coincidentally, the one terrain the encounter
-- system says is inhabited.
local function grassCellNear(ow)
  local map, p = ow.map, ow.player
  for _ = 1, CELL_TRIES do
    local cx = p.cellX + rand(-RADIUS, RADIUS)
    local cy = p.cellY + rand(-RADIUS, RADIUS)
    if map:inBounds(cx, cy) and map:isGrassCell(cx, cy) then
      return cx * 16 + rand(2, 14), cy * 16 + rand(2, 14)
    end
  end
  return nil
end

local function spawnButterfly(ow)
  local x, z = grassCellNear(ow)
  if not x then return end
  critters[#critters + 1] = {
    kind = "butterfly", x = x, z = z, hx = x, hz = z,
    y = 6 + rand() * 6, dir = rand() * 6.2831,
    seed = rand() * 6.2831, t = 0, ttl = 18 + rand() * 20,
    tint = rand(3),
  }
end

local function spawnFirefly(ow)
  local x, z = grassCellNear(ow)
  if not x then return end
  critters[#critters + 1] = {
    kind = "firefly", x = x, z = z, hx = x, hz = z,
    y = 3 + rand() * 5, dir = rand() * 6.2831,
    seed = rand() * 6.2831, t = 0, ttl = 14 + rand() * 16,
  }
end

-- An open walkable cell near the player -- where a ground bird can stand.
local function openCellNear(ow)
  local map, p = ow.map, ow.player
  for _ = 1, CELL_TRIES do
    local cx = p.cellX + rand(-RADIUS, RADIUS)
    local cy = p.cellY + rand(-RADIUS, RADIUS)
    if map:inBounds(cx, cy) and map:isWalkableCell(cx, cy)
       and not map:warpAtCell(cx, cy) then
      return cx * 16 + rand(3, 13), cy * 16 + rand(3, 13)
    end
  end
  return nil
end

local function waterCellNear(ow)
  local map, p = ow.map, ow.player
  for _ = 1, CELL_TRIES do
    local cx = p.cellX + rand(-RADIUS, RADIUS)
    local cy = p.cellY + rand(-RADIUS, RADIUS)
    if map:inBounds(cx, cy) and map:isWaterCell(cx, cy) then
      return cx * 16 + rand(2, 14), cy * 16 + rand(2, 14)
    end
  end
  return nil
end

local function spawnSparrow(ow)
  local x, z = openCellNear(ow)
  if not x then return end
  critters[#critters + 1] = {
    kind = "sparrow", x = x, z = z, y = 0,
    mode = "ground", hopWait = 0.5 + rand() * 1.2,
    seed = rand() * 6.2831, t = 0, ttl = 20 + rand() * 20,
  }
end

local function spawnDragonfly(ow)
  local x, z = waterCellNear(ow)
  if not x then return end
  critters[#critters + 1] = {
    kind = "dragonfly", x = x, z = z, hx = x, hz = z,
    tx = x, tz = z, y = 3,
    seed = rand() * 6.2831, t = 0, ttl = 16 + rand() * 16,
  }
end

local function spawnLeaf(ow)
  local p = ow.player
  local x = (p.cellX + rand(-RADIUS, RADIUS)) * 16 + rand(0, 15)
  local z = (p.cellY + rand(-RADIUS, RADIUS)) * 16 + rand(0, 15)
  critters[#critters + 1] = {
    kind = "leaf", x = x, z = z, y = 22 + rand() * 10,
    seed = rand() * 6.2831, t = 0, ttl = 30,
  }
end

-- A flock: three to five birds abreast with a little scatter, entering off
-- one side of the view and flying straight across the sky to the other.
local function spawnFlock(ow)
  local p = ow.player
  local fromWest = rand() < 0.5
  local px, pz = p.cellX * 16, p.cellY * 16
  local n = rand(3, 5)
  local baseZ = pz + rand(-8, 8) * 16
  for i = 1, n do
    critters[#critters + 1] = {
      kind = "bird",
      x = px + (fromWest and -1 or 1) * (RADIUS + 3) * 16 - (i - 1) * 10,
      z = baseZ + (i - 1) * 7 - n * 3,
      y = 34 + rand() * 14,
      vx = (fromWest and 1 or -1) * (30 + rand() * 10),
      seed = rand() * 6.2831, t = 0, ttl = 30,
      px0 = px,
    }
  end
end

-- ------- the people glance
--
-- Civilians only, and the guard is the point: `def.trainerClass` is how
-- the sight check knows a trainer, and a trainer's facing IS their line of
-- sight -- turning one toward a passing player would start (or dodge)
-- fights the map never rolled. Everything else stands down: frozen NPCs
-- belong to a script, moving ones pick their own facing on the next step,
-- and this mod's own roamers and street Pokemon have moods of their own.
--
-- A standing NPC remembers the facing its map def gave it and turns BACK
-- when the player walks on -- a shopkeeper glances up from the counter,
-- then goes back to minding it.
local NPC = require("src.world.NPC")

local function glance(ow)
  local p = ow.player
  for _, npc in ipairs(ow.npcs or {}) do
    if getmetatable(npc) == NPC and npc.def and not npc.def.trainerClass
       and not npc.frozen and not npc.moving then
      local dx = math.abs(npc.cellX - p.cellX)
      local dy = math.abs(npc.cellY - p.cellY)
      local near = dx <= 2 and dy <= 2 and (dx + dy) > 0 and (dx + dy) <= 3
      if near then
        if npc.dsGlanceFacing == nil then
          npc.dsGlanceFacing = npc.facing or false
        end
        npc:facePlayer(p)
      elseif npc.dsGlanceFacing ~= nil and (dx > 3 or dy > 3) then
        -- only a STANDING NPC turns back; a wanderer's next step owns its
        -- facing already
        if not npc.wanders and npc.dsGlanceFacing then
          npc.facing = npc.dsGlanceFacing
        end
        npc.dsGlanceFacing = nil
      end
    end
  end
end

-- ------- per-frame
--
-- Rides the voxel pipeline's update hook like everything else with a clock,
-- and then gates itself down to the frames where there is a diorama to be
-- alive on: the overworld on top, outdoors, and the voxel camera actually
-- pitched over -- ambience under a menu or on the flat 2D world would be
-- simulation nobody sees. The glance is the one part that runs on the FLAT
-- world too: a turned head is a facing, and facings draw in every mode.
function AmbientLife.update(dt, voxelOn)
  local Game = game()
  local ow = Game and Game.overworld

  if AmbientLife.enabled() and ow and ow.map and ow.player
     and Game.stack and Game.stack:top() == ow
     and not ow.transitioning
     and not (ow.runner and ow.runner.isRunning and ow.runner:isRunning()) then
    pcall(glance, ow)
  end

  local ok = voxelOn and AmbientLife.enabled()
             and ow and ow.map and ow.player
             and Game.stack and Game.stack:top() == ow
             and not ow.transitioning
             and Map.isOutdoor(ow.map.def)
  if not ok then
    if #critters > 0 and not (ow and Game.stack
                              and Game.stack:top() ~= ow) then
      -- gone for a real reason (indoors, mode off): drop the population.
      -- Under a battle or menu it is merely paused, and comes back intact.
      critters = {}
    end
    return
  end

  if state.mapId ~= ow.map.id then
    critters = {}
    state.mapId = ow.map.id
    state.birdTimer = 6 + rand() * 10
  end

  local tod = DayNight.tod()
  local day = tod == "DAY" or tod == "MORNING"
  local glowTime = tod == "NIGHT" or tod == "EVENING"
  local canopy = DayNight.isCanopy(ow.map)
  local windy = Wind.enabled() and Wind.amount() > 0

  -- one spawn attempt per half second, one kind per attempt: a route fills
  -- in over a few seconds rather than all at once
  state.spawnTick = state.spawnTick + dt
  if state.spawnTick >= SPAWN_EVERY then
    state.spawnTick = 0
    if day and count("butterfly") < MAX_BUTTERFLY then spawnButterfly(ow) end
    if glowTime and count("firefly") < fireflyCap() then spawnFirefly(ow) end
    if windy and count("leaf") < MAX_LEAF then spawnLeaf(ow) end
    if day and count("sparrow") < MAX_SPARROW then spawnSparrow(ow) end
    if day and count("dragonfly") < MAX_DRAGONFLY then spawnDragonfly(ow) end
  end

  -- the flock, on its own long clock, and only under an open sky
  if day and not canopy then
    state.birdTimer = state.birdTimer - dt
    if state.birdTimer <= 0 then
      spawnFlock(ow)
      state.birdTimer = 18 + rand() * 18
    end
  end

  local p = ow.player
  local px, pz = p.cellX * 16, p.cellY * 16
  local far = (RADIUS + 6) * 16
  local windAmt = windy and Wind.amount() or 0

  for i = #critters, 1, -1 do
    local c = critters[i]
    c.t = c.t + dt
    local dead = c.t >= c.ttl

    if c.kind == "butterfly" then
      -- a random walk on the heading, a spring back toward home, a bob
      c.dir = c.dir + (rand() - 0.5) * 3.2 * dt
      local sp = 9
      c.x = c.x + math.cos(c.dir) * sp * dt + (c.hx - c.x) * 0.15 * dt
      c.z = c.z + math.sin(c.dir) * sp * dt + (c.hz - c.z) * 0.15 * dt
      c.y = 6 + 3 * math.sin(c.t * 2.6 + c.seed)
      if not day then dead = true end
    elseif c.kind == "firefly" then
      c.dir = c.dir + (rand() - 0.5) * 1.6 * dt
      local sp = 4
      c.x = c.x + math.cos(c.dir) * sp * dt + (c.hx - c.x) * 0.1 * dt
      c.z = c.z + math.sin(c.dir) * sp * dt + (c.hz - c.z) * 0.1 * dt
      c.y = 4 + 2 * math.sin(c.t * 1.3 + c.seed)
      if not glowTime then dead = true end
    elseif c.kind == "leaf" then
      -- falls, and the wind carries it sideways on the gust's own strength;
      -- the flutter is the leaf's, the drift is the weather's
      c.y = c.y - 6 * dt
      c.x = c.x + (10 + 6 * math.sin(c.t * 2 + c.seed)) * windAmt * dt
      c.z = c.z + 3 * math.cos(c.t * 1.7 + c.seed) * windAmt * dt
      if c.y <= 0.5 then dead = true end
      if not windy then dead = true end
    elseif c.kind == "bird" then
      c.x = c.x + c.vx * dt
      c.y = c.y + math.sin(c.t * 3 + c.seed) * 2 * dt
      if math.abs(c.x - px) > (RADIUS + 5) * 16 and c.t > 2 then dead = true end
    elseif c.kind == "sparrow" then
      local pxc = p.cellX * 16 + 8
      local pzc = p.cellY * 16 + 8
      local ddx, ddz = c.x - pxc, c.z - pzc
      if c.mode == "ground" then
        -- startle: the player got close, and the bird is gone -- up, away,
        -- and off the roster once it is high and far
        if math.abs(ddx) < STARTLE and math.abs(ddz) < STARTLE then
          c.mode = "fly"
          local len = math.max(1, math.sqrt(ddx * ddx + ddz * ddz))
          c.vx, c.vz = ddx / len * 55, ddz / len * 55
          c.vy = 34
          c.ttl = c.t + 2.5
        elseif c.hop then
          -- mid-hop: a short arc, a few pixels along the ground
          c.hop.t = c.hop.t + dt
          local k = math.min(1, c.hop.t / c.hop.dur)
          c.x = c.x + c.hop.dx * dt / c.hop.dur
          c.z = c.z + c.hop.dz * dt / c.hop.dur
          c.y = math.sin(k * 3.1416) * 2
          if k >= 1 then
            c.hop, c.y = nil, 0
            c.hopWait = 0.5 + rand() * 1.4
          end
        else
          c.hopWait = c.hopWait - dt
          if c.hopWait <= 0 then
            local a = rand() * 6.2831
            c.hop = { t = 0, dur = 0.22,
                      dx = math.cos(a) * 6, dz = math.sin(a) * 6 }
          end
        end
      else
        c.x = c.x + c.vx * dt
        c.z = c.z + c.vz * dt
        c.y = c.y + c.vy * dt
        c.vy = math.max(10, c.vy - 8 * dt)
      end
    elseif c.kind == "dragonfly" then
      -- hover, then a dash to a new spot near home, then hover again
      local dxT, dzT = c.tx - c.x, c.tz - c.z
      local d2 = dxT * dxT + dzT * dzT
      if d2 < 4 then
        if rand() < dt * 0.8 then
          local a = rand() * 6.2831
          local r = 8 + rand() * 20
          c.tx = c.hx + math.cos(a) * r
          c.tz = c.hz + math.sin(a) * r
        end
      else
        local len = math.sqrt(d2)
        local sp = 46
        c.x = c.x + dxT / len * math.min(sp * dt, len)
        c.z = c.z + dzT / len * math.min(sp * dt, len)
      end
      c.y = 3 + math.sin(c.t * 5 + c.seed) * 0.8
      if not day then dead = true end
    end

    if not dead and c.kind ~= "bird"
       and (math.abs(c.x - px) > far or math.abs(c.z - pz) > far) then
      dead = true      -- left behind as the player walked on
    end
    if dead then table.remove(critters, i) end
  end
end

-- ------- the draw
--
-- Inside the voxel overlay pass (main.lua's drawWorld), with the same
-- project function the field FX anchor through. `scale` is pixels per world
-- pixel at the camera's focus; project's third return is the perspective
-- correction for this critter's own distance, so a bird far away is
-- smaller, exactly like the terrain under it.
local BUTTERFLY_TINTS = {
  { 0.96, 0.93, 0.86 },     -- cabbage white
  { 0.95, 0.82, 0.35 },     -- brimstone yellow
  { 0.65, 0.78, 0.95 },     -- pale blue
}

function AmbientLife.draw(project, scale)
  if #critters == 0 then return end
  local g = love.graphics
  local prevBlend, prevAlpha = g.getBlendMode()

  for _, c in ipairs(critters) do
    local sx, sy, ps = project(c.x, c.y, c.z)
    if sx then
      local s = math.max(1, scale * (ps or 1))
      -- ease in over the first half second and out over the last, so
      -- nothing pops into a frame it was not in
      local fade = math.min(1, c.t * 2, (c.ttl - c.t) * 2)

      if c.kind == "butterfly" then
        local tint = BUTTERFLY_TINTS[c.tint] or BUTTERFLY_TINTS[1]
        local flap = math.abs(math.sin(c.t * 16 + c.seed))
        g.setBlendMode("alpha")
        g.setColor(tint[1], tint[2], tint[3], 0.9 * fade)
        -- two wings about a 1px body, folding with the flap
        local w = s * (0.5 + flap)
        g.rectangle("fill", sx - w, sy - s * 0.5, w, s)
        g.rectangle("fill", sx, sy - s * 0.5, w, s)
      elseif c.kind == "firefly" then
        -- the blink: mostly off, a soft ramp on and off again
        local blink = math.sin(c.t * 2.2 + c.seed)
        blink = math.max(0, blink - 0.35) / 0.65
        if blink > 0.01 then
          g.setBlendMode("add")
          g.setColor(0.95, 0.85, 0.35, 0.22 * blink * fade)
          g.rectangle("fill", sx - s * 1.5, sy - s * 1.5, s * 3, s * 3)
          g.setColor(1.0, 0.95, 0.55, 0.9 * blink * fade)
          g.rectangle("fill", sx - s * 0.5, sy - s * 0.5, s, s)
        end
      elseif c.kind == "leaf" then
        g.setBlendMode("alpha")
        g.setColor(0.45, 0.62, 0.25, 0.85 * fade)
        local tilt = math.sin(c.t * 4 + c.seed) * 0.5
        g.rectangle("fill", sx - s * 0.5, sy - s * 0.5 + tilt * s, s, s * 0.7)
      elseif c.kind == "bird" then
        g.setBlendMode("alpha")
        g.setColor(0.20, 0.22, 0.28, 0.9 * fade)
        local flap = math.sin(c.t * 9 + c.seed)
        -- a chevron: two wing strokes meeting at the body, beating
        local wing = s * 1.6
        local lift = flap * s * 0.8
        g.rectangle("fill", sx - wing, sy - lift, wing, s * 0.6)
        g.rectangle("fill", sx, sy - lift, wing, s * 0.6)
        g.rectangle("fill", sx - s * 0.4, sy - s * 0.2, s * 0.8, s * 0.8)
      elseif c.kind == "sparrow" then
        g.setBlendMode("alpha")
        -- a plump brown speck with a paler breast; wings only in the air
        g.setColor(0.42, 0.30, 0.18, 0.95 * fade)
        g.rectangle("fill", sx - s, sy - s, s * 2, s * 1.4)
        g.setColor(0.72, 0.62, 0.45, 0.95 * fade)
        g.rectangle("fill", sx - s * 0.5, sy - s * 0.2, s, s * 0.6)
        if c.mode == "fly" then
          local flap = math.sin(c.t * 22)
          g.setColor(0.42, 0.30, 0.18, 0.95 * fade)
          g.rectangle("fill", sx - s * 2.2, sy - s - flap * s, s * 1.2, s * 0.5)
          g.rectangle("fill", sx + s, sy - s - flap * s, s * 1.2, s * 0.5)
        end
      elseif c.kind == "dragonfly" then
        g.setBlendMode("alpha")
        -- a teal needle with wings that shimmer rather than flap: real
        -- ones beat too fast to see, so a flicker of alpha is the truth
        g.setColor(0.25, 0.68, 0.62, 0.95 * fade)
        g.rectangle("fill", sx - s * 0.4, sy - s * 0.3, s * 0.8, s * 1.6)
        local shimmer = 0.25 + 0.35 * math.abs(math.sin(c.t * 30 + c.seed))
        g.setColor(0.75, 0.88, 0.92, shimmer * fade)
        g.rectangle("fill", sx - s * 1.6, sy - s * 0.2, s * 1.2, s * 0.5)
        g.rectangle("fill", sx + s * 0.4, sy - s * 0.2, s * 1.2, s * 0.5)
      end
    end
  end

  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  g.setColor(1, 1, 1, 1)
end

return AmbientLife
