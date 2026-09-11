-- Leaves that fall, lie where they land, and scatter under a boot.
--
-- VegFX decides WHEN a tree lets a leaf go and from which crown (T11). This
-- file is everything after that: the fall, the ground, the kick.
--
-- ------- IN THE AIR: WINDFX'S LEAF, WITH WEIGHT
--
-- The falling leaf is the one the wind already draws -- EdgeLoopRepeat's
-- tumbling strip, opaque and at eye level, the look WindFX's rule 9 settled
-- on -- and it moves through the same solver with the same mass and area as
-- the wind's own leaf, so it dances the same eddies. Two things differ, and
-- they are why this is a field of its own rather than WindFX's:
--
--   * it FALLS. The solver has no vertical physics on purpose (a leaf that
--     truly fell would leave the wind's field); here `lift` is integrated as
--     a sink that grows to a terminal rate, and the solver's own bob rides
--     on top of it -- the flutter of a leaf on its way down.
--   * it outlives the wind. WindFX clears below FLOOR; a leaf already in
--     the air when the gust dies still has to reach the ground.
--
-- ------- ON THE GROUND: ONE MESH, WRITTEN WHEN SOMETHING CHANGES
--
-- A leaf that reaches an open floor cell becomes a flat card in LeafLitter's
-- store and in one static mesh: a single draw call for the whole map's
-- litter, whose vertices are rewritten only for the slot that changed. Per
-- frame the ground costs a setColor and a draw. A cell holds PER_CELL
-- leaves; one landing on a full cell takes the place of the leaf that has
-- lain there longest.
--
-- Where a leaf may lie is decided once per map, per cell: walkable, and flat
-- (VoxelScene.flatTop -- a crown's hull is air at its class height) or a
-- flower bed. Never tall grass: a 16-high tuft hides anything at a leaf's
-- height, so a leaf that falls into one is lost in it. Everything else --
-- roofs, ledges, water, the crowns themselves -- takes the leaf, and it goes.
--
-- A map starts with the leaves its trees would already have dropped: seeded
-- from its own tree sites, around each crown and a little downwind, by a
-- generator keyed to the map's id -- the same route shows the same ground
-- every time you walk onto it.
--
-- ------- UNDER A BOOT
--
-- A walker who MOVED this frame (the player, Pikachu, the route's NPCs)
-- lifts every leaf within KICK_R of their centre that has lain still for
-- REST seconds. It leaves the store and re-enters the air as a kicked leaf,
-- thrown to the side of the stride and a little along it, with a hop. The
-- kick is dense (tau ~0.24 s), so the push carries about a cell before the
-- air has it; then it lands again somewhere else. Walking deletes nothing --
-- the path clears because the leaves on it moved to its sides.
--
-- ------- BUDGETS
--
-- PFX scales both pools. The ground is remembered for the last MAP_KEEP maps
-- walked; a map forgotten and revisited is seeded again, identically.
-- Neighbour maps are not drawn (the same limit VegFX and StepFX have).

local V = ...

local Particles = V.require("Particles")
local LeafLitter = V.require("LeafLitter")
local Wind = V.require("Wind")
local WindFX = V.require("WindFX")
local GroundFX = V.require("GroundFX")
local Quality = V.require("Quality")
local Voxel3D = V.require("Voxel3D")
local VoxelState = V.require("VoxelState")

local LeafFallFX = {}

local rand = love.math.random
local floor, sqrt, cos, sin, abs = math.floor, math.sqrt, math.cos, math.sin, math.abs
local TWO_PI = math.pi * 2
local CELL = LeafLitter.CELL

-- ------- budgets: the live ones ride PFX, the hard ones size the buffers
LeafFallFX.AIR = 72               -- leaves in the air at PFX ON
LeafFallFX.AIR_MAX = 128
LeafFallFX.LITTER = 1000          -- leaves lying on one map at PFX ON
LeafFallFX.LITTER_MAX = 2000
LeafFallFX.SEED_FILL = 0.6        -- share of the ground budget a map starts with
LeafFallFX.MAP_KEEP = 3           -- maps whose ground is remembered

-- ------- the fall
LeafFallFX.FALL_G = 12            -- lift a falling leaf loses per second...
LeafFallFX.FALL_SINK = 16         -- ...down to this: its terminal sink
LeafFallFX.FALL_TTL = 14
-- A leaf lets go anywhere under the crown, not from its trunk: a crown is
-- ~14 px of radius over a 16 px cell, and a leaf dropped from the centre in
-- still air would land back on the tree's own cell every time -- which no
-- leaf may lie on -- so calm would never add a leaf to the ground.
LeafFallFX.SHED_R = 15
LeafFallFX.REACH = 18             -- cells from the player a leaf in the air survives

-- ------- the ground
-- Two world px, not a depth bias: a card lying ON the surface that wrote the
-- depth ties with it, and device depth is too non-linear for a constant
-- bias to forgive the tie far away without forgiving real geometry near
-- (PARTICLES-PLAN, armadilha 4: the rain decals).
LeafFallFX.RAISE = 2.0
LeafFallFX.LAND_AT = 3.0          -- height over the floor where a falling leaf lands
LeafFallFX.HALF = WindFX.SHEETS.leaf.hw   -- the air's card size: a leaf does not shrink as it lands
LeafFallFX.DIE_TIME = 0.25        -- seconds a leaf with nowhere to lie takes to go
LeafFallFX.KEEP_R = 12 * CELL     -- an eviction leaves this much ground round the player alone
LeafFallFX.SNOW_HIDE = 0.35       -- settled snow that buries the litter
LeafFallFX.WET_DARK = 0.30        -- how much darker a soaked leaf lies

-- ------- the ground a map starts with
LeafFallFX.SEED_IN = 6            -- world px from a crown's centre, nearest...
LeafFallFX.SEED_OUT = 30          -- ...and furthest
LeafFallFX.SEED_DRIFT = 10        -- world px further downwind, at most
LeafFallFX.SEED_TRIES = 3         -- positions tried before a leaf is given up
LeafFallFX.SEED_PER_CELL = 3      -- a map starts half full, so what falls has room to show

-- ------- the kick
LeafFallFX.KICK_R = 10            -- world px round a moving walker's centre
LeafFallFX.REST = 0.6             -- seconds a landed leaf lies before it can be kicked again
LeafFallFX.WALK_SPEED = 60        -- world px/s of a walk; a bike kicks harder by the ratio
LeafFallFX.KICK_SPEED = 60        -- world px/s a leaf leaves the boot at, walking
LeafFallFX.KICK_AWAY = 1.0        -- how much of the throw goes to the side of the stride
LeafFallFX.KICK_ALONG = 0.55      -- and how much along it
LeafFallFX.HOP = 48               -- a kicked leaf's first lift
LeafFallFX.KICK_G = 120           -- which it loses this fast...
LeafFallFX.KICK_SINK = 30         -- ...down to this
LeafFallFX.KICK_TTL = 4

-- Probe switches: the same frame with and without each half is the whole
-- proof that the half draws.
LeafFallFX.DRAW_LITTER = true
LeafFallFX.DRAW_AIR = true

local SHEET = WindFX.SHEETS.leaf
local LEAF = WindFX.KINDS.leaf

-- The fall moves exactly like the wind's leaf; the kick is the StepFX grain's
-- language, a dense thing thrown that the drag spends.
LeafFallFX.KINDS = {
  fall = { speed = LEAF.speed, bob = LEAF.bob, mass = LEAF.mass, area = LEAF.area },
  kick = { speed = 0.45, bob = 2.0, mass = 0.55, area = 0.35, curlA = 0.10, curlB = 0.05 },
}

local air = Particles.newField(LeafFallFX.KINDS, LeafFallFX.AIR_MAX)
local airCtx = {}

local states = {}          -- remembered maps, most recently walked first
local bound = nil          -- the state of the map underfoot
local barrenKey = nil      -- the last map found to grow no trees
local now = 0
local picked = {}
for i = 1, 64 do picked[i] = 0 end
-- last seen centre per walker. Weak keys: an NPC that despawns takes its
-- entry with it.
local trail = setmetatable({}, { __mode = "k" })

-- The instruments, same contract as every module in the chain (armadilha 1):
-- a throw in update or draw is caught, counted and named.
LeafFallFX.ticks = 0
LeafFallFX.ticksLive = 0
LeafFallFX.lastGate = "never ran"
LeafFallFX.shedCount = 0
LeafFallFX.landed = 0
LeafFallFX.splashed = 0           -- of those, the ones that came down on water
LeafFallFX.splashedKick = 0       -- and of THOSE, the ones a boot had kicked up
LeafFallFX.lost = 0
LeafFallFX.kicked = 0
LeafFallFX.replaced = 0           -- old leaves a landing on a full cell took the place of
LeafFallFX.walkersSeen = 0        -- walker tables first met (one trail entry each)
LeafFallFX.fullWrites = 0         -- whole-mesh rewrites of the ground
LeafFallFX.slotWrites = 0         -- single lying leaves written into it
LeafFallFX.lastBatches = -1
LeafFallFX.lastError = nil
LeafFallFX.errorCount = 0
LeafFallFX.drawError = nil
LeafFallFX.drawErrors = 0

local function game()
  return require("src.core.Game")
end

local function budget(base, hard, mulCap)
  local mul = Quality.particles()
  if mul < 0.4 then mul = 0.4 elseif mul > mulCap then mul = mulCap end
  local n = floor(base * mul)
  if n > hard then n = hard end
  return n
end

-- The strip's colourways as the ground wears them: mostly fall, some
-- spring, the odd winter leaf.
local function pickVariant(r)
  if r < 0.62 then return 0 end
  if r < 0.95 then return 1 end
  return 2
end

-- The clip frames that read as a leaf lying flat: the open blade (3), the
-- blade on its stem (4), the curl (0). The two edge-on frames would lie on
-- the path as a stick.
local function lyingFrame(variant, r)
  local k = (r < 0.45) and 3 or ((r < 0.80) and 4 or 0)
  return variant * SHEET.n + k
end

local function mapKey(map)
  return tostring(map.id or map.name or "?")
end

local function seedOf(key)
  local h = 5381
  for i = 1, #key do h = (h * 33 + key:byte(i)) % 2147483629 end
  return h
end

-- ------- WHERE A LEAF MAY LIE, once per map
local function survey(st, map)
  local VoxelScene = V.require("VoxelScene")
  local TileShape = V.require("TileShape")
  local shapes = TileShape.forMap(map)
  local cols, rows = st.store.cols, st.store.rows
  local ok, flo = st.ok, st.floor
  local open = 0
  for cz = 0, rows - 1 do
    for cx = 0, cols - 1 do
      local c = cz * cols + cx + 1
      local tx, ty = cx * 2, cz * 2 + 1
      local okS, s = pcall(TileShape.at, map, shapes, map:tileAt(tx, ty), tx, ty)
      local art = okS and s and s.art or nil
      local okF, flat = pcall(VoxelScene.flatTop, map, cx, cz)
      flat = okF and flat
      local okH, h = pcall(VoxelScene.groundAt, map, cx, cz)
      h = okH and tonumber(h) or 0
      local okW, walk = pcall(map.isWalkableCell, map, cx, cz)
      walk = okW and walk
      local lie = walk and h >= 0 and art ~= "stair" and art ~= "grass"
                  and (flat or art == "flower")
      ok[c] = lie and true or false
      -- where a leaf that may NOT lie here stops: the top of a box (roof,
      -- ledge, the water's recessed floor), the ground under a round thing
      flo[c] = flat and h or 0
      if lie then open = open + 1 end
    end
  end
  return open
end

-- ------- THE GROUND A MAP STARTS WITH
local function seed(st, trees)
  local store = st.store
  local want = floor(store.cap * LeafFallFX.SEED_FILL)
  local n = #trees
  if n == 0 or want <= 0 then return 0 end
  local rng = love.math.newRandomGenerator(seedOf(st.key))
  local per = want / n
  local carry = 0
  local dx, dz = Wind.DIR0[1] or 1, Wind.DIR0[2] or 0
  local span = LeafFallFX.SEED_OUT - LeafFallFX.SEED_IN
  local born = now - LeafFallFX.REST
  local placed = 0
  for i = 1, n do
    local t = trees[i]
    carry = carry + per
    while carry >= 1 do
      carry = carry - 1
      for _ = 1, LeafFallFX.SEED_TRIES do
        -- sqrt: even over the ring's AREA, so the rim is not starved
        local a = rng:random() * TWO_PI
        local d = LeafFallFX.SEED_IN + span * sqrt(rng:random())
        local drift = LeafFallFX.SEED_DRIFT * rng:random()
        local x = t.x + cos(a) * d + dx * drift
        local z = t.z + sin(a) * d + dz * drift
        local c = store:cellOf(x, z)
        if c and st.ok[c] and store.fill[c] < LeafFallFX.SEED_PER_CELL then
          local frame = lyingFrame(pickVariant(rng:random()), rng:random())
          if store:add(x, st.floor[c] + LeafFallFX.RAISE, z, frame,
                       rng:random() * TWO_PI, born) then
            placed = placed + 1
          end
          break
        end
      end
    end
  end
  return placed
end

local function newState()
  return {
    key = nil, map = nil,
    store = LeafLitter.new(LeafFallFX.LITTER_MAX),
    ok = {}, floor = {},
    open = 0, trees = 0, seeded = 0,
  }
end

-- The state for the map underfoot, or nil when it grows no trees. O(1) for
-- the map already bound; a map change looks through the remembered ones and
-- only a map never seen (or forgotten) pays the survey and the seeding.
local function bind(map)
  if bound and bound.map == map then return bound end
  local key = mapKey(map)
  if bound and bound.key == key then
    bound.map = map
    return bound
  end
  if not bound and barrenKey == key then return nil end
  air:clear()
  -- a remembered map keeps its ground, not its Map object: whatever else
  -- hangs off the map being left must stay free to be collected
  if bound then bound.map = nil end
  for i = 1, #states do
    local st = states[i]
    if st.key == key then
      table.remove(states, i)
      table.insert(states, 1, st)
      st.map = map
      bound = st
      return st
    end
  end
  local VegFX = V.require("VegFX")
  local sites = VegFX.grows(map) and VegFX.sitesFor(map)
  if not (sites and #sites.trees > 0) then
    bound, barrenKey = nil, key
    return nil
  end
  local st
  if #states >= LeafFallFX.MAP_KEEP then
    st = table.remove(states)
  else
    st = newState()
  end
  table.insert(states, 1, st)
  st.key, st.map = key, map
  st.store:reset(map.widthCells or 0, map.heightCells or 0)
  st.store:setCap(budget(LeafFallFX.LITTER, LeafFallFX.LITTER_MAX, 2))
  st.open = survey(st, map)
  st.trees = #sites.trees
  st.seeded = seed(st, sites.trees)
  bound, barrenKey = st, nil
  return st
end

-- ------- A LEAF LETS GO (VegFX calls this at the crown)
function LeafFallFX.shed(x, y, z)
  local m = air:claim()
  if not m then return false end
  m.kind = "fall"
  local a = rand() * TWO_PI
  local r = LeafFallFX.SHED_R * sqrt(rand())
  m.x = x + cos(a) * r
  m.z = z + sin(a) * r
  m.y = y
  -- the crown it came from and the point it let go at: probes judge the
  -- origin by these, since the air moves the leaf from the first frame
  m.srcX, m.srcZ = x, z
  m.bornX, m.bornZ = m.x, m.z
  m.seed = rand() * TWO_PI
  m.t = 0
  m.ttl = LeafFallFX.FALL_TTL
  m.fast = 0.55 + rand() * 0.90
  m.lift = -rand() * 3
  m.spin, m.ang = 0, 0
  m.variant = pickVariant(rand())
  m.phase = rand()
  m.flip = (rand() < 0.5) and -1 or 1
  m.rot = rand() * TWO_PI
  LeafFallFX.shedCount = LeafFallFX.shedCount + 1
  return true
end

-- ------- THE AIR: the solver, then gravity and the ground
local function stepAir(dt, st, px, pz)
  if air:count() == 0 then return end
  local amount = Wind.amount()
  airCtx.dirX = Wind.DIR[1] or 1
  airCtx.dirZ = Wind.DIR[2] or 0
  airCtx.speed = amount * WindFX.SPEED
  airCtx.turbulence = amount * WindFX.SPEED * WindFX.TURB
  airCtx.originX, airCtx.originZ = px, pz
  airCtx.reach = LeafFallFX.REACH * CELL
  -- no floorAt: the solver's clamp would hoist a leaf onto every crown hull
  -- it drifts over. The ground is judged below, against this map's survey.
  air:step(dt, airCtx)

  local store, ok, flo = st.store, st.ok, st.floor
  local buried = (GroundFX.cover() or 0) >= LeafFallFX.SNOW_HIDE
  local i = 1
  while i <= air:count() do
    local m = air:get(i)
    if m.dying then
      if now - m.dying >= LeafFallFX.DIE_TIME then air:kill(i) else i = i + 1 end
    else
      local kick = m.kind == "kick"
      local lift = m.lift - (kick and LeafFallFX.KICK_G or LeafFallFX.FALL_G) * dt
      local sink = kick and LeafFallFX.KICK_SINK or LeafFallFX.FALL_SINK
      if lift < -sink then lift = -sink end
      m.lift = lift
      local c = store:cellOf(m.x, m.z)
      local base = c and flo[c] or 0
      -- only on the way DOWN: a kicked leaf starts at the ground
      if lift <= 0 and m.y <= base + LeafFallFX.LAND_AT then
        -- ------- a leaf on WATER
        --
        -- A leaf that comes down in a puddle rings it, the way a boot does
        -- (GroundFX.ripple: the field's own ring and the screen pass's).
        -- It still lies where it fell -- RAISE is above the pool's plane,
        -- so it floats on the film rather than showing through it -- and
        -- the ring is what says the surface is water and not a grey patch
        -- of road. Asked of the ground row per landing: a handful a second
        -- at the most, and the row's own lookup is a table read.
        if c then
          local Game = game()
          local map = Game and Game.overworld and Game.overworld.map
          if map then
            local okp, pool = pcall(GroundFX.poolAt, map,
                                    math.floor(m.x / 16), math.floor(m.z / 16))
            if okp and pool then
              pcall(GroundFX.ripple, m.x, m.z)
              LeafFallFX.splashed = LeafFallFX.splashed + 1
              if kick then LeafFallFX.splashedKick = LeafFallFX.splashedKick + 1 end
            end
          end
        end
        local laid = nil
        if c and ok[c] and not buried then
          -- A full cell takes the leaf anyway; the one that has lain there
          -- longest makes room. The eye is on the leaf coming down, not on
          -- an old one a few pixels off -- and ground that refused leaves
          -- would be ground where every leaf you watch fall vanishes on
          -- touching it.
          if not store:hasRoom(c) then
            store:remove(store:oldestIn(c))
            LeafFallFX.replaced = LeafFallFX.replaced + 1
          end
          laid = store:add(m.x, base + LeafFallFX.RAISE, m.z,
                           lyingFrame(m.variant, rand()), m.rot, now,
                           px, pz, LeafFallFX.KEEP_R)
        end
        if laid then
          LeafFallFX.landed = LeafFallFX.landed + 1
          air:kill(i)
        else
          m.dying = now
          m.pinned = true
          m.y = base + LeafFallFX.LAND_AT
          LeafFallFX.lost = LeafFallFX.lost + 1
          i = i + 1
        end
      else
        i = i + 1
      end
    end
  end
end

-- ------- A BOOT
local function kickFor(e, st, px, pz, dt, wet)
  if not e then return end
  local x, z = (e.px or 0) + 8, (e.py or 0) + 8
  local tr = trail[e]
  if not tr then
    trail[e] = { x = x, z = z }
    LeafFallFX.walkersSeen = LeafFallFX.walkersSeen + 1
    return
  end
  local dx, dz = x - tr.x, z - tr.z
  tr.x, tr.z = x, z
  local d2 = dx * dx + dz * dz
  if d2 <= 1e-4 or d2 > 576 then return end    -- standing, or a warp
  local reach = LeafFallFX.REACH * CELL
  if abs(x - px) > reach or abs(z - pz) > reach then return end
  local store = st.store
  local n = store:collect(x, z, LeafFallFX.KICK_R, now, LeafFallFX.REST, picked)
  if n == 0 then return end

  local d = sqrt(d2)
  local mx, mz = dx / d, dz / d
  local pace = d / dt / LeafFallFX.WALK_SPEED
  if pace < 0.6 then pace = 0.6 elseif pace > 2 then pace = 2 end
  local damp = 1 - 0.5 * wet          -- a soaked leaf sticks
  for k = 1, n do
    local m = air:claim()
    if not m then break end            -- the rest lie until the air has room
    local slot = picked[k]
    local lx, lz = store.x[slot], store.z[slot]
    -- to the side of the stride the leaf lies on (a random side when it
    -- lies dead ahead), and a little along it
    local rx, rz = lx - x, lz - z
    local along = rx * mx + rz * mz
    local sx, sz = rx - along * mx, rz - along * mz
    local sl = sqrt(sx * sx + sz * sz)
    if sl < 2 then
      local side = (rand() < 0.5) and -1 or 1
      sx, sz, sl = -mz * side, mx * side, 1
    end
    local ux = sx / sl * LeafFallFX.KICK_AWAY + mx * LeafFallFX.KICK_ALONG
    local uz = sz / sl * LeafFallFX.KICK_AWAY + mz * LeafFallFX.KICK_ALONG
    local ul = sqrt(ux * ux + uz * uz)
    local v = LeafFallFX.KICK_SPEED * pace * damp * (0.7 + rand() * 0.6)
    m.kind = "kick"
    m.x, m.y, m.z = lx, store.y[slot], lz
    m.srcX, m.srcZ = lx, lz
    m.vx, m.vz = ux / ul * v, uz / ul * v
    m.seed = rand() * TWO_PI
    m.t = 0
    m.ttl = LeafFallFX.KICK_TTL
    m.fast = 1
    m.lift = LeafFallFX.HOP * (1 - 0.6 * wet) * (0.8 + rand() * 0.4)
    m.spin, m.ang = 0, 0
    m.variant = floor(store.frame[slot] / SHEET.n)
    m.phase = rand()
    m.flip = (rand() < 0.5) and -1 or 1
    m.rot = store.rot[slot] + (rand() * 2 - 1) * 1.2
    store:remove(slot)
    LeafFallFX.kicked = LeafFallFX.kicked + 1
  end
end

local function updateBody(dt, voxelOn)
  LeafFallFX.ticks = LeafFallFX.ticks + 1
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end

  local Game = game()
  local ow = Game and Game.overworld
  local live = voxelOn and ow and ow.map and ow.player
               and Game.stack and Game.stack:top() == ow
               and not ow.transitioning
  if not live then
    -- nothing is cleared: the ground keeps its leaves through a battle, a
    -- menu, a trip indoors
    LeafFallFX.lastGate =
      (not voxelOn and "voxelOn=false")
      or (not (ow and ow.map and ow.player) and "no overworld/map/player")
      or (not (Game.stack and Game.stack:top() == ow) and "overworld not on top")
      or (ow.transitioning and "map transitioning")
      or "unknown"
    return
  end
  local st = bind(ow.map)
  if not st then
    LeafFallFX.lastGate = "no trees here"
    air:clear()
    return
  end
  LeafFallFX.lastGate = "live"
  LeafFallFX.ticksLive = LeafFallFX.ticksLive + 1
  now = now + dt

  air:setCap(budget(LeafFallFX.AIR, LeafFallFX.AIR_MAX, 1.7))
  st.store:setCap(budget(LeafFallFX.LITTER, LeafFallFX.LITTER_MAX, 2))

  local p = ow.player
  local px, pz = (p.px or 0) + 8, (p.py or 0) + 8
  stepAir(dt, st, px, pz)

  if dt <= 0 or (GroundFX.cover() or 0) >= LeafFallFX.SNOW_HIDE then return end
  local wet = GroundFX.wetness() or 0
  kickFor(p, st, px, pz, dt, wet)
  local npcs = ow.npcs
  if npcs then
    for i = 1, #npcs do
      local e = npcs[i]
      if e ~= p then kickFor(e, st, px, pz, dt, wet) end
    end
  end
end

function LeafFallFX.update(dt, voxelOn)
  local ok, err = pcall(updateBody, dt, voxelOn)
  if ok then return end
  LeafFallFX.errorCount = LeafFallFX.errorCount + 1
  LeafFallFX.lastError = tostring(err)
end

-- ------- DRAWING, in the scene pass (VoxelScene, beside WindFX and StepFX)
local litterMesh, airMesh = nil, nil
local meshOwner = nil          -- the state whose leaves litterMesh holds
local litterBatch = { img = nil, r = 1, g = 1, b = 1, a = 1, first = 1, count = 0 }
local litterBatches = { litterBatch }
local airBatch = { img = nil, r = 1, g = 1, b = 1, a = 1, first = 1, count = 0 }
local airBatches = { airBatch }

local function quadMesh(quads, usage)
  local ok, m = pcall(love.graphics.newMesh, Voxel3D.FORMAT, quads * 4,
                      "triangles", usage)
  if not (ok and m) then return nil end
  local map = {}
  for q = 0, quads - 1 do Voxel3D.pushQuad(map, q) end
  pcall(m.setVertexMap, m, map)
  return m
end

local function frameUV(f, iw, ih)
  local u0 = ((f % SHEET.cols) * SHEET.fw) / iw
  local v0 = (floor(f / SHEET.cols) * SHEET.fh) / ih
  return u0, v0, u0 + SHEET.fw / iw, v0 + SHEET.fh / ih
end

-- One lying leaf: a flat card turned about the vertical, wound like a
-- terrain top face, shade -1 so the shader reads it as facing up (the lamps
-- light it as the ground it lies on; the sun does not ask). An empty slot
-- collapses to a point and rasterises nothing.
local function writeLying(store, slot, iw, ih)
  local m = litterMesh
  local base = (slot - 1) * 4
  if not store.used[slot] then
    for c = 1, 4 do m:setVertex(base + c, 0, 0, 0, 0, 0, 1) end
    return
  end
  local u0, v0, u1, v1 = frameUV(store.frame[slot], iw, ih)
  local x, y, z = store.x[slot], store.y[slot], store.z[slot]
  local a = store.rot[slot]
  local ca, sa = cos(a) * LeafFallFX.HALF, sin(a) * LeafFallFX.HALF
  m:setVertex(base + 1, x - ca + sa, y, z - sa - ca, u0, v1, -1)
  m:setVertex(base + 2, x + ca + sa, y, z + sa - ca, u1, v1, -1)
  m:setVertex(base + 3, x + ca - sa, y, z + sa + ca, u1, v0, -1)
  m:setVertex(base + 4, x - ca - sa, y, z - sa + ca, u0, v0, -1)
end

local function syncLitter(st, img)
  local store = st.store
  local iw, ih = img:getDimensions()
  local full, n = store:pendingChanges()
  if full or meshOwner ~= st then
    for slot = 1, store.high do writeLying(store, slot, iw, ih) end
    meshOwner = st
    LeafFallFX.fullWrites = LeafFallFX.fullWrites + 1
  elseif n > 0 then
    local dirty = store.dirty
    for k = 1, n do writeLying(store, dirty[k], iw, ih) end
    LeafFallFX.slotWrites = LeafFallFX.slotWrites + n
  end
  store:doneChanges()
end

-- One leaf in the air: the wind's card, ParticleMesh's corner order and
-- lean, the clip's own frame. A leaf with nowhere to lie shrinks away.
local function writeAir(q, m, iw, ih, ct, st)
  local f = (m.variant or 0) * SHEET.n
            + floor(((m.t or 0) + (m.phase or 0)) * SHEET.fps) % SHEET.n
  local u0, v0, u1, v1 = frameUV(f, iw, ih)
  if (m.flip or 1) < 0 then u0, u1 = u1, u0 end
  local hw = SHEET.hw
  if m.dying then
    local k = 1 - (now - m.dying) / LeafFallFX.DIE_TIME
    hw = hw * ((k > 0) and k or 0)
  end
  local hh = hw * (SHEET.fh / SHEET.fw)
  local x, y, z = m.x, m.y, m.z
  local ly, lz = hh * ct, hh * st
  local mesh = airMesh
  local base = q * 4
  mesh:setVertex(base + 1, x - hw, y - ly, z - lz, u0, v1, 1)
  mesh:setVertex(base + 2, x - hw, y + ly, z + lz, u0, v0, 1)
  mesh:setVertex(base + 3, x + hw, y + ly, z + lz, u1, v0, 1)
  mesh:setVertex(base + 4, x + hw, y - ly, z - lz, u1, v1, 1)
end

local function drawBody()
  local pack = WindFX.pack()
  local img = pack and pack.leaf
  if not img then
    LeafFallFX.lastBatches = 0
    return 0
  end
  local drew = 0

  local st = bound
  if st then
    litterMesh = litterMesh or quadMesh(LeafFallFX.LITTER_MAX, "dynamic")
    if litterMesh then
      syncLitter(st, img)
      local high = st.store.high
      if LeafFallFX.DRAW_LITTER and high > 0
         and (GroundFX.cover() or 0) < LeafFallFX.SNOW_HIDE then
        local k = 1 - LeafFallFX.WET_DARK * (GroundFX.wetness() or 0)
        litterBatch.img = img
        litterBatch.r, litterBatch.g, litterBatch.b = k, k, k
        litterBatch.count = high * 6
        -- cutouts, like the wind's sprites: the shader discards the
        -- transparent surround, so writing depth is honest
        drew = drew + Voxel3D.drawParticles(litterMesh, img, litterBatches, true)
      end
    end
  end

  local n = air:count()
  if n > 0 and LeafFallFX.DRAW_AIR then
    airMesh = airMesh or quadMesh(LeafFallFX.AIR_MAX, "stream")
    if airMesh then
      local iw, ih = img:getDimensions()
      local t = (VoxelState.angle or 0) - math.pi / 2
      local ct, stn = cos(t), sin(t)
      for i = 1, n do writeAir(i - 1, air:get(i), iw, ih, ct, stn) end
      airBatch.img = img
      airBatch.count = n * 6
      drew = drew + Voxel3D.drawParticles(airMesh, img, airBatches, true)
    end
  end

  LeafFallFX.lastBatches = drew
  return drew
end

function LeafFallFX.drawWorld()
  local ok, res = pcall(drawBody)
  if ok then return res or 0 end
  LeafFallFX.drawErrors = LeafFallFX.drawErrors + 1
  LeafFallFX.drawError = "drawWorld: " .. tostring(res)
  return 0
end

-- ------- for probes

-- the leaves in the air
function LeafFallFX.count() return air:count() end
function LeafFallFX.get(i) return air:get(i) end

-- the map underfoot: { key, store, ok[c], floor[c], open, trees, seeded }
function LeafFallFX.state() return bound end
function LeafFallFX.clock() return now end
function LeafFallFX.lyingFrame(variant, r) return lyingFrame(variant, r) end

-- Lay a leaf by hand where the survey allows one, kickable at once.
function LeafFallFX.deposit(x, z, frame, rot)
  local st = bound
  if not st then return nil end
  local c = st.store:cellOf(x, z)
  if not (c and st.ok[c]) then return nil end
  return st.store:add(x, st.floor[c] + LeafFallFX.RAISE, z,
                      frame or lyingFrame(0, 0), rot or 0,
                      now - LeafFallFX.REST)
end

-- Drop every remembered map, so the next bind surveys and seeds afresh.
function LeafFallFX.forget()
  for i = #states, 1, -1 do states[i] = nil end
  bound, barrenKey, meshOwner = nil, nil, nil
  air:clear()
end

return LeafFallFX
