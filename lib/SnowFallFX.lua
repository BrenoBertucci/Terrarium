-- Snow that comes DOWN off things: roofs letting go, and trees shaken.
--
-- A snowed town is not still. Every few seconds somewhere in it a roof
-- lets a slab of its load slide off the eave -- a scatter of clumps and a
-- puff of powder, and a mound growing on the ground beneath -- and a tree
-- somebody walks into drops what its crown was holding straight onto them.
-- A strong gust does the same to a crown on its own.
--
-- ------- what it is made of
--
-- The shared particle solver (lib/Particles.lua), in a field of its own
-- like the footstep dust: two kinds, a CLUMP that falls under gravity the
-- solver does not have (integrated here, handed to the solver as `lift`)
-- and lands, and a POWDER that hangs, takes the air and fades. Drawn in
-- the scene pass through the same builder and the same call the dust
-- uses, so a slide behind the Mart stays behind the Mart. Every clump that
-- lands HEAPS the snow field where it fell (SnowField.heap), which is what
-- puts a drift under every eave by the end of a storm and a ring of fallen
-- snow around a shaken tree; a tree shaken onto somebody leaves its snow on
-- their hat (SnowField.dumpOn -> the figure's coat).
--
-- ------- where the roofs and the trees are
--
-- Scanned once per map off the shape profile, exactly as VegFX finds its
-- trees: a tree is a cell whose art is a cylinder or a canopy; an EAVE is
-- a cell you cannot stand on that is a roof -- the profile's own `roof`
-- class, or a cell the building kit stamped a model over, whose real top
-- Buildings.tallAt remembers -- whose southern neighbour is ground you can
-- stand on: the lip a slab slides over. A clump born inside a roof is
-- hidden by the depth test until it clears the eave, which is where a slide
-- becomes visible anyway.
--
-- ------- the bump
--
-- The engine has no event for walking into a wall, but the Player knows:
-- a blocked step re-arms `bumpFrames` for the length of a step (the legs
-- cycle in place, Gen 1's own idiom), and a real step clears it. Its rising
-- edge is the bump; the cell in front of the player's facing is what they
-- bumped, and if that is a tree with snow on it, the tree lets go.

local V = ...

local Particles = V.require("Particles")
local ParticleMesh = V.require("ParticleMesh")
local Wind = V.require("Wind")
local WindFX = V.require("WindFX")
local GroundFX = V.require("GroundFX")
local SnowField = V.require("SnowField")
local Quality = V.require("Quality")
local Voxel3D = V.require("Voxel3D")
local TileShape = V.require("TileShape")

local Map = require("src.world.Map")

local SnowFallFX = {}

local rand = math.random

-- The clump is heavy and barely takes the wind; the powder is the lightest
-- thing in the air. Clamps let a clump reach the ground (lowClamp is where
-- it is caught) and start a storey up.
SnowFallFX.KINDS = {
  clump  = { speed = 0.20, bob = 0.4, lowClamp = 0.3, highClamp = 90,
             curlA = 0.04, curlB = 0.02, mass = 0.90, area = 0.35 },
  powder = { speed = 0.80, bob = 2.2, lowClamp = 0.4, highClamp = 60,
             curlA = 0.25, curlB = 0.12, mass = 0.15, area = 1.20 },
  -- meltwater off an eave: a bead, straight down, no wind to speak of
  drip   = { speed = 0.05, bob = 0.0, lowClamp = 0.3, highClamp = 90,
             curlA = 0.0, curlB = 0.0, mass = 1.0, area = 0.20 },
}

SnowFallFX.MAX = 200           -- hard field cap; PFX scales the RATE
SnowFallFX.GRAVITY = 150       -- world px/s^2: a storey in about half a second
SnowFallFX.REACH = 12          -- cells from the player anything happens in
-- ------- roofs
SnowFallFX.SLIDE_EVERY = 8     -- mean seconds between slides in reach, deep cover
SnowFallFX.SLIDE_MIN = 0.50    -- cover a roof needs before it lets go
SnowFallFX.SLIDE_CLUMPS = 9    -- per slide, before the PFX multiplier
-- ------- trees
SnowFallFX.TREE_MIN = 0.28     -- cover a crown needs to have anything to drop
SnowFallFX.TREE_COOL = 6       -- seconds before the same tree drops again
SnowFallFX.SHAKE_CLUMPS = 12
SnowFallFX.GUST_LEVEL = 0.72   -- the gust envelope at which crowns let go
SnowFallFX.GUST_EVERY = 7      -- mean seconds between gust sheds at full gust
-- ------- what a landing leaves
SnowFallFX.HEAP_R = 3.2        -- world px a clump heaps over
SnowFallFX.HEAP_ADD = 0.16     -- rim per clump landed
SnowFallFX.DUMP_COAT = 1.0     -- what a shaken tree leaves on a hat
SnowFallFX.SNOW = { 0.97, 0.98, 1.00 }
-- ------- the thaw
SnowFallFX.DRIP_EVERY = 0.45   -- mean seconds between drips in reach, melting
SnowFallFX.DRIP_MIN = 0.10     -- cover under which the eaves are dry
SnowFallFX.DRIP_TINT = { 0.78, 0.88, 1.00 }
-- ------- shedding
SnowFallFX.SHED_COAT = 0.35    -- a coat this heavy sheds when its wearer moves
SnowFallFX.SHED_EVERY = 6      -- world px of travel per shed
SnowFallFX.SHED_LOSS = 0.025   -- coat lost per shed

local field = Particles.newField(SnowFallFX.KINDS, SnowFallFX.MAX)
local ctx = {}
local builder = nil

-- Instruments, the same contract as every module in the chain: a throw in
-- update or draw is caught, counted and named.
SnowFallFX.slides = 0
SnowFallFX.shakes = 0
SnowFallFX.bumps = 0
SnowFallFX.landed = 0
SnowFallFX.lastGate = "never ran"
SnowFallFX.lastBatches = -1
SnowFallFX.lastError = nil
SnowFallFX.errorCount = 0
SnowFallFX.drawError = nil
SnowFallFX.drawErrors = 0

function SnowFallFX.count() return field:count() end
function SnowFallFX.get(i) return field:get(i) end

local function game()
  return require("src.core.Game")
end

-- ------- the sites

local sites = { mapId = nil, roofs = {}, trees = {}, treeAt = {} }

local function wipe(t) for i = #t, 1, -1 do t[i] = nil end end

local function scan(map)
  wipe(sites.roofs); wipe(sites.trees)
  sites.treeAt = {}
  sites.mapId = map.id
  local ok, shapes = pcall(TileShape.forMap, map)
  if not ok or not shapes then return end
  local cols = tonumber(map.widthCells) or 64
  local rows = tonumber(map.heightCells) or 64
  local function shapeAt(cx, cy)
    if not map:inBounds(cx, cy) then return nil end
    local tx, ty = cx * 2, cy * 2 + 1
    local okS, s = pcall(TileShape.at, map, shapes, map:tileAt(tx, ty), tx, ty)
    if okS then return s end
    return nil
  end
  for cy = 0, rows - 1 do
    for cx = 0, cols - 1 do
      local s = shapeAt(cx, cy)
      if s then
        if s.art == "cylinder" or s.art == "canopy" then
          local t = { x = cx * 16 + 8, z = cy * 16 + 8, cx = cx, cy = cy,
                      h = (s.h and s.h > 4) and s.h or 16 }
          sites.trees[#sites.trees + 1] = t
          sites.treeAt[cy * 4096 + cx] = t
        elseif not map:isWalkableCell(cx, cy) and not map:isWaterCell(cx, cy)
               and map:inBounds(cx, cy + 1) and map:isWalkableCell(cx, cy + 1)
               and not map:isWaterCell(cx, cy + 1) then
          -- the FRONT EAVE of anything built: a cell you cannot stand on
          -- whose southern neighbour you can. A building's bottom row is
          -- its facade (`wall`, upright) and the `roof` rows sit above it,
          -- so the lip a slab slides over is the top of the COLUMN of
          -- built cells standing on this one -- or the real top the
          -- building kit stamped over any of them (Buildings.tallAt: the
          -- mesher paints ankle-height ground under a stamped model, so
          -- the profile alone would call the Mart a lawn).
          local top = 0
          for up = 0, 6 do
            local cy2 = cy - up
            if not map:inBounds(cx, cy2) then break end
            if map:isWalkableCell(cx, cy2) or map:isWaterCell(cx, cy2) then break end
            local c = shapeAt(cx, cy2)
            if not c then break end
            local a = c.art
            if a == "cylinder" or a == "canopy" or a == "grass" or a == "flower"
               or a == "billboard" or a == "post" then
              break
            end
            local h = c.h or 0
            if h > top then top = h end
            local okB, tall = pcall(function()
              local B = V.require("Buildings")
              return B and B.tallAt and B.tallAt(map, cx, cy2) or 0
            end)
            if okB and tonumber(tall) and tall > top then top = tall end
          end
          -- a fence is too low to shed; a garden wall, a cliff and every
          -- roof are not
          if top >= 12 then
            sites.roofs[#sites.roofs + 1] = {
              x = cx * 16 + 8, z = cy * 16 + 16, y = top,
              cx = cx, cy = cy,
            }
          end
        end
      end
    end
  end
end

function SnowFallFX.sitesFor(map)
  if sites.mapId ~= map.id then scan(map) end
  return sites
end

-- ------- spawning

local function spawn(kind, x, y, z, vx, vz, vy, ttl, size)
  if field:full() then return nil end
  local m = field:claim()
  if not m then return nil end
  m.kind = kind
  m.x, m.y, m.z = x, y, z
  m.t, m.ttl = 0, ttl
  m.seed = rand() * 6.2831
  m.fast = 0.6 + rand() * 0.8
  m.vy = vy
  -- the solver adds lift * 0.55 * dt to y; the fall is integrated here
  -- and handed over through it
  m.lift = vy / 0.55
  m.spin = (rand() * 2 - 1) * 2.0
  m.frame, m.flip, m.front = 0, 1, false
  m.size = size
  m.ang = rand() * 6.2831
  m.vx, m.vz = vx, vz
  return m
end

-- A slab off an eave: clumps along the lip, thrown a little outward,
-- and a powder cloud that hangs where the slab broke.
function SnowFallFX.slide(site, depth)
  depth = tonumber(depth) or 1
  local mul = Quality.particles()
  local n = math.floor(SnowFallFX.SLIDE_CLUMPS * (0.6 + depth * 0.6) * mul + 0.5)
  if n < 3 then n = 3 end
  for _ = 1, n do
    local x = site.x + (rand() * 2 - 1) * 7
    spawn("clump", x, site.y + 1 + rand() * 2, site.z + rand() * 2,
          (rand() * 2 - 1) * 4, 6 + rand() * 12, -(2 + rand() * 10),
          4, 0.55 + rand() * 0.75)
  end
  for _ = 1, math.max(2, math.floor(n * 0.6)) do
    local x = site.x + (rand() * 2 - 1) * 8
    spawn("powder", x, site.y + 1 + rand() * 3, site.z + rand() * 3,
          (rand() * 2 - 1) * 3, 2 + rand() * 6, -(1 + rand() * 3),
          0.9 + rand() * 0.7, 1.1 + rand() * 0.9)
  end
  SnowFallFX.slides = SnowFallFX.slides + 1
end

-- A crown letting go: clumps out of the canopy, most of them straight down
-- around the trunk, and -- when somebody shook it -- a share of them onto
-- that somebody, whose hat takes the coat.
function SnowFallFX.shake(tree, depth, ent, share)
  depth = tonumber(depth) or 1
  share = tonumber(share) or 1
  local mul = Quality.particles()
  local n = math.floor(SnowFallFX.SHAKE_CLUMPS * (0.5 + depth * 0.7) * share * mul + 0.5)
  if n < 3 then n = 3 end
  local ex, ez = nil, nil
  if ent then ex, ez = (ent.px or 0) + 8, (ent.py or 0) + 8 end
  for i = 1, n do
    local onto = ex and (i % 5 ~= 0)
    local x, z
    if onto then
      x = ex + (rand() * 2 - 1) * 5
      z = ez + (rand() * 2 - 1) * 5
    else
      x = tree.x + (rand() * 2 - 1) * 7
      z = tree.z + (rand() * 2 - 1) * 7
    end
    spawn("clump", x, tree.h * (0.7 + rand() * 0.3), z,
          (rand() * 2 - 1) * 5, (rand() * 2 - 1) * 5, -(1 + rand() * 6),
          4, 0.5 + rand() * 0.7)
  end
  for _ = 1, math.max(2, math.floor(n * 0.5)) do
    spawn("powder", tree.x + (rand() * 2 - 1) * 8,
          tree.h * (0.6 + rand() * 0.4), tree.z + (rand() * 2 - 1) * 8,
          (rand() * 2 - 1) * 4, (rand() * 2 - 1) * 4, -(1 + rand() * 3),
          0.8 + rand() * 0.8, 1.0 + rand() * 1.0)
  end
  if ent then
    pcall(SnowField.dumpOn, ent, SnowFallFX.DUMP_COAT * math.min(1, depth + 0.3))
  end
  SnowFallFX.shakes = SnowFallFX.shakes + 1
end

-- ------- the per-frame tick

local wasBumping = false
local treeCool = {}     -- cell key -> clock reading it may drop again
local clock = 0
local lastCover = nil
-- per walker: where they were and how far since the coat last shed
local shedders = setmetatable({}, { __mode = "k" })

local function inReach(x, z, px, pz)
  local r = SnowFallFX.REACH * 16
  return math.abs(x - px) <= r and math.abs(z - pz) <= r
end

local function bumpedTree(ow, map, depth)
  local pl = ow.player
  if not pl then return end
  local bf = pl.bumpFrames or 0
  if bf <= 0 then
    wasBumping = false
    return
  end
  if wasBumping then return end
  wasBumping = true
  SnowFallFX.bumps = SnowFallFX.bumps + 1
  if depth < SnowFallFX.TREE_MIN then return end
  local okC, Collision = pcall(require, "src.world.Collision")
  if not (okC and Collision and Collision.target) then return end
  local okT, tx, ty = pcall(Collision.target, pl.cellX, pl.cellY, pl.facing)
  if not okT then return end
  local tree = sites.treeAt[ty * 4096 + tx]
  if not tree then return end
  local key = ty * 4096 + tx
  if (treeCool[key] or 0) > clock then return end
  treeCool[key] = clock + SnowFallFX.TREE_COOL
  SnowFallFX.shake(tree, depth, pl, 1)
end

local function roofsLetGo(dt, depth, px, pz)
  if depth < SnowFallFX.SLIDE_MIN then return end
  local k = (depth - SnowFallFX.SLIDE_MIN) / (1 - SnowFallFX.SLIDE_MIN)
  if rand() >= dt / SnowFallFX.SLIDE_EVERY * (0.4 + 0.6 * k) then return end
  -- a random roof in reach: sampled, not searched, so a town of two
  -- hundred eaves costs the same as a route with one
  local roofs = sites.roofs
  local n = #roofs
  if n == 0 then return end
  for _ = 1, 12 do
    local s = roofs[rand(1, n)]
    if inReach(s.x, s.z, px, pz) then
      SnowFallFX.slide(s, depth)
      return
    end
  end
end

local function gustsShake(dt, depth, px, pz)
  if depth < SnowFallFX.TREE_MIN then return end
  local okG, g = pcall(Wind.gust)
  g = (okG and tonumber(g)) or 0
  if g < SnowFallFX.GUST_LEVEL then return end
  if rand() >= dt / SnowFallFX.GUST_EVERY * g then return end
  local trees = sites.trees
  local n = #trees
  if n == 0 then return end
  for _ = 1, 12 do
    local t = trees[rand(1, n)]
    if inReach(t.x, t.z, px, pz) then
      local key = t.cy * 4096 + t.cx
      if (treeCool[key] or 0) <= clock then
        treeCool[key] = clock + SnowFallFX.TREE_COOL
        SnowFallFX.shake(t, depth, nil, 0.5)
      end
      return
    end
  end
end

-- A coat that is walked in comes off in pinches: specks of powder from
-- the hat and the shoulders every few pixels of travel, and the coat
-- thins with them. What makes "snow ON somebody" read as a load rather
-- than a paint job.
local function shedCoat(e)
  if not e then return end
  local okc, k = pcall(SnowField.coatOf, e)
  k = (okc and tonumber(k)) or 0
  if k < SnowFallFX.SHED_COAT then
    shedders[e] = nil
    return
  end
  local x, z = (e.px or 0) + 8, (e.py or 0) + 8
  local sh = shedders[e]
  if not sh then
    shedders[e] = { x = x, z = z, acc = 0 }
    return
  end
  local dx, dz = x - sh.x, z - sh.z
  sh.x, sh.z = x, z
  local d = math.sqrt(dx * dx + dz * dz)
  if d <= 0.01 or d > 24 then sh.acc = 0 return end
  sh.acc = sh.acc + d
  while sh.acc >= SnowFallFX.SHED_EVERY do
    sh.acc = sh.acc - SnowFallFX.SHED_EVERY
    local top = WindFX.groundAt(x, z) + 10 + rand() * 5
    spawn("powder", x + (rand() * 2 - 1) * 4, top, z + (rand() * 2 - 1) * 3,
          -dx * 3 + (rand() * 2 - 1) * 3, -dz * 3 + (rand() * 2 - 1) * 3,
          -(2 + rand() * 4), 0.5 + rand() * 0.4, 0.55 + rand() * 0.4)
    pcall(SnowField.dumpOn, e, -SnowFallFX.SHED_LOSS)
  end
end

-- The thaw: while the cover is going DOWN and there is still some, the
-- eaves drip -- a bead of meltwater off a random lip in reach, falling
-- straight, gone where it lands.
local function eavesDrip(dt, cover, px, pz)
  local melting = lastCover ~= nil and cover < lastCover - 1e-7
  lastCover = cover
  if not melting or cover < SnowFallFX.DRIP_MIN then return end
  if rand() >= dt / SnowFallFX.DRIP_EVERY then return end
  local roofs = sites.roofs
  local n = #roofs
  if n == 0 then return end
  for _ = 1, 12 do
    local s = roofs[rand(1, n)]
    if inReach(s.x, s.z, px, pz) then
      spawn("drip", s.x + (rand() * 2 - 1) * 7, s.y - 0.5, s.z + 0.5 + rand(),
            0, 0, -(4 + rand() * 6), 3, 0.30 + rand() * 0.15)
      return
    end
  end
end

-- What a clump does when it lands: a puff, and a heap in the field.
local function land(m, groundY)
  SnowFallFX.landed = SnowFallFX.landed + 1
  pcall(SnowField.heap, m.x, m.z, SnowFallFX.HEAP_R,
        SnowFallFX.HEAP_ADD * (m.size or 1))
  spawn("powder", m.x + (rand() * 2 - 1) * 2, groundY + 1.2,
        m.z + (rand() * 2 - 1) * 2,
        (rand() * 2 - 1) * 5, (rand() * 2 - 1) * 5, 3 + rand() * 4,
        0.5 + rand() * 0.4, 0.8 + rand() * 0.6)
end

local function updateBody(dt, voxelOn)
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
  clock = clock + dt

  local Game = game()
  local ow = Game and Game.overworld
  local live = voxelOn and ow and ow.map and ow.player
               and Map.isOutdoor(ow.map.def)
               and Game.stack and Game.stack:top() == ow
               and not ow.transitioning
  if not live then
    SnowFallFX.lastGate =
      (not voxelOn and "voxelOn=false")
      or (not (ow and ow.map and ow.player) and "no overworld/map/player")
      or (not Map.isOutdoor(ow.map.def) and "indoors")
      or (not (Game.stack and Game.stack:top() == ow) and "overworld not on top")
      or (ow.transitioning and "map transitioning")
      or "unknown"
    field:clear()
    wasBumping = false
    return
  end
  local map = ow.map
  local okD, depth = pcall(GroundFX.snowDepth, map)
  depth = (okD and tonumber(depth)) or 0
  if depth <= 0 and field:count() == 0 then
    SnowFallFX.lastGate = "no snow on the ground"
    lastCover = GroundFX.cover()
    return
  end
  SnowFallFX.lastGate = "live"
  SnowFallFX.sitesFor(map)

  local p = ow.player
  local px, pz = (p.px or 0) + 8, (p.py or 0) + 8
  if depth > 0 then
    bumpedTree(ow, map, depth)
    roofsLetGo(dt, depth, px, pz)
    gustsShake(dt, depth, px, pz)
    eavesDrip(dt, GroundFX.cover(), px, pz)
  end
  -- coats shed on the move, whatever the ground is doing
  shedCoat(p)
  local npcs = ow.npcs
  if npcs then
    for i = 1, #npcs do
      local e = npcs[i]
      if e ~= p then shedCoat(e) end
    end
  end

  if field:count() > 0 then
    -- gravity, into the solver's own lift
    local G = SnowFallFX.GRAVITY
    for i = 1, field:count() do
      local m = field:get(i)
      if m.kind == "clump" or m.kind == "drip" then
        m.vy = (m.vy or 0) - G * dt
        m.lift = m.vy / 0.55
      end
    end
    local amount = Wind.amount()
    ctx.dirX = Wind.DIR[1] or 1
    ctx.dirZ = Wind.DIR[2] or 0
    ctx.speed = amount * WindFX.SPEED
    ctx.turbulence = amount * WindFX.SPEED * WindFX.TURB
    ctx.floorAt = WindFX.groundAt
    ctx.originX = px
    ctx.originZ = pz
    ctx.reach = SnowFallFX.REACH * 16
    field:step(dt, ctx)
    -- and the landings: a clump the solver caught at the floor is done
    local low = SnowFallFX.KINDS.clump.lowClamp
    local i = 1
    while i <= field:count() do
      local m = field:get(i)
      if m.kind == "clump" then
        local g = WindFX.groundAt(m.x, m.z)
        if m.y <= g + low + 0.05 and (m.vy or 0) < 0 then
          land(m, g)
          field:kill(i)
        else
          i = i + 1
        end
      elseif m.kind == "drip" then
        -- a bead is gone where it lands, and nothing else
        local g = WindFX.groundAt(m.x, m.z)
        if m.y <= g + low + 0.05 and (m.vy or 0) < 0 then
          field:kill(i)
        else
          i = i + 1
        end
      else
        i = i + 1
      end
    end
  end
end

function SnowFallFX.update(dt, voxelOn)
  local ok, err = pcall(updateBody, dt, voxelOn)
  if ok then return end
  SnowFallFX.errorCount = SnowFallFX.errorCount + 1
  SnowFallFX.lastError = tostring(err)
end

-- ------- the draw

local CARD = {
  clump  = { 1.30, 1.0, 0.9 },
  powder = { 2.20, 1.2, 1.0 },
  drip   = { 1.00, 0.55, 1.4 },
}

local function drawWorldBody()
  local live = field:count()
  if live == 0 then SnowFallFX.lastBatches = 0 return 0 end
  local pack = WindFX.pack()
  if not pack then SnowFallFX.lastBatches = 0 return 0 end
  builder = builder or ParticleMesh.newBuilder(SnowFallFX.MAX)
  local snow = SnowFallFX.SNOW

  local describe = function(m)
    local img = pack.puff or pack.grit
    if not img then return nil end
    local a
    local col = snow
    if m.kind == "clump" then
      a = 0.92 * math.min(1, m.t * 8)
    elseif m.kind == "drip" then
      a = 0.80
      col = SnowFallFX.DRIP_TINT
    else
      a = 0.55 * math.min(1, m.t * 6, (m.ttl - m.t) * 2.2)
    end
    if a <= 0.02 then return nil end
    local c = CARD[m.kind] or CARD.clump
    local base = c[1] * (m.size or 1)
    local hw = base * c[2] * 0.5
    local hh = base * c[3] * 0.5
    if hw < 0.5 then hw = 0.5 end
    if hh < 0.5 then hh = 0.5 end
    return img, 0, 0, 1, 1, hw, hh, (m.kind == "drip") and 0 or (m.ang or 0),
           col[1], col[2], col[3], a
  end

  local mesh, batches = builder:build(field, describe)
  if not mesh then SnowFallFX.lastBatches = 0 return 0 end
  local drew = Voxel3D.drawParticles(mesh, nil, batches, true)
  SnowFallFX.lastBatches = drew
  return drew
end

function SnowFallFX.drawWorld()
  local ok, err = pcall(drawWorldBody)
  if ok then return err or 0 end
  SnowFallFX.drawErrors = SnowFallFX.drawErrors + 1
  SnowFallFX.drawError = "drawWorld: " .. tostring(err)
  return 0
end

return SnowFallFX
