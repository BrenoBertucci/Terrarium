-- Voxel world mode: the wind you can SEE.
--
-- Wind.lua bends the grass; this file fills the air when grass is not on
-- screen. Particles are cel-hard grit, seeds and dashes (assets/vfx/wind_*.png,
-- authored by tools/make_wind_sprites.py) -- not soft photo-smoke circles.
--
-- Kinds (picked by weather + wind strength):
--   grit    tiny hard dust pixels low over the ground (dry air)
--   seed    elongated pollen/seed mid height (dry breeze+)
--   dash    velocity-aligned streak (gale / gust front)
--   spray   seed-shaped, rain-tinted (shower)
--   snow    grit-shaped, white (snow)
--
-- Gust front: rank of dashes + a short curl frame strip, same Wind.gust
-- envelope the grass already bows to.

local V = ...

local DayNight = V.require("DayNight")
local Wind = V.require("Wind")
local Weather = V.require("Weather")
local Quality = V.require("Quality")
local Voxel3D = V.require("Voxel3D")
local Particles = V.require("Particles")
local ParticleMesh = V.require("ParticleMesh")

local Map = require("src.world.Map")

local WindFX = {}

local function game()
  return require("src.core.Game")
end

local rand = love.math.random

-- Below this tip-reach the air shows nothing. Calm stays calm.
WindFX.FLOOR = 0.48

-- ------- WHICH PASS THE FIELD IS PAINTED IN
--
-- true  = geometry inside the scene pass, depth-tested (WindFX.drawWorld)
-- false = the old overlay paint, in front of everything (WindFX.draw)
--
-- Kept as a switch rather than deleted, and not out of sentiment: the two
-- paths differ ONLY in whether the world is allowed to hide a mote, so
-- flipping this in one build and screenshotting both is the entire proof
-- that occlusion arrived and nothing else moved with it. See
-- tests/particles_occlusion_probe.lua.
WindFX.WORLD_PASS = true

-- Freeze the field: no clear, no spawn, no step. Set by probes that have
-- placed their own fixture with pinOne and need it to be the only thing on
-- screen -- the ordinary update would refill the air around it within a
-- frame, and stilling the WIND instead would take the clear() path and
-- delete the fixture along with everything else.
WindFX.HOLD = false

-- Was 140, and that was a laptop's number rather than a squall's. The
-- field is drawn as sprite batches over a handful of images, so what it
-- costs is a table per mote and fill rate; QUALITY still cuts it by RES
-- for anyone who wants it cut.
WindFX.MAX = 380               -- hard ceiling; Quality.windStreaks cuts by RES
WindFX.REACH = 12
WindFX.SPAWN_AHEAD = 5
WindFX.SPAWN_WIDE = 8
WindFX.SPEED = 28              -- world px/s per unit Wind.amount
WindFX.TAIL = 0.14

WindFX.FRONT_AT = 0.70
WindFX.FRONT_WAIT = 2.5
WindFX.FRONT_WIDE = 8
WindFX.FRONT_N = 8

-- How much of the field's own speed one unit of eddy is worth (T7): the
-- solver samples Wind.turbAt per mote and converts at speed * TURB. Half
-- the mean at full envelope is strong texture that still transports --
-- the eddies are zero-mean, so the field swirls without losing its wind.
WindFX.TURB = 0.5

-- Flat palettes on the 5-bit lattice. Dust has several warm greys so a
-- field of grit is not one identical tint; spray/snow stay singular.
WindFX.DUST = { 0.92, 0.86, 0.68 }
WindFX.DUST_B = { 0.86, 0.78, 0.58 }   -- dirtier
WindFX.DUST_C = { 0.96, 0.92, 0.80 }   -- pale sand
WindFX.DUST_D = { 0.78, 0.70, 0.52 }   -- dark grit
WindFX.SEED = { 0.78, 0.84, 0.55 }
WindFX.SEED_B = { 0.88, 0.76, 0.42 }   -- dry chaff
WindFX.SPRAY = { 0.72, 0.82, 0.96 }
WindFX.BLOWN = { 0.96, 0.97, 1.00 }
WindFX.DASH = { 0.94, 0.90, 0.80 }
WindFX.LEAF = {
  { 1.00, 1.00, 1.00 },
  { 0.82, 1.10, 0.52 },
  { 1.15, 1.02, 0.40 },
  { 1.12, 0.50, 0.28 },
  { 0.70, 0.42, 0.24 },
  { 0.95, 0.34, 0.26 },
  { 0.55, 0.75, 0.32 },
  { 0.80, 0.62, 0.36 },
}

-- ------- WHAT SEPARATES ONE MOTE FROM ANOTHER, AS A TABLE
--
-- These are the numbers that used to be an if-chain inside the update
-- loop. Same values, read from here instead of branched to -- which is
-- what lets lib/Particles.lua integrate a leaf and a grain of grit
-- through one piece of arithmetic, and what lets the drag task change how
-- they differ in one place rather than in a ladder of elseifs.
--
-- `mass` and `area` are written down and read by nothing today: they are
-- the drag task's inputs, and putting them here now means that task is a
-- change to a solver rather than a change to every kind.
WindFX.KINDS = {
  grit  = { speed = 0.68, bob = 3.0, mass = 0.40, area = 0.30 },
  snow  = { speed = 0.68, bob = 3.0, mass = 0.22, area = 0.90 },
  puff  = { speed = 0.85, bob = 5.5, mass = 0.18, area = 1.20 },
  seed  = { speed = 1.00, bob = 7.5, mass = 0.30, area = 1.40 },
  spray = { speed = 1.00, bob = 7.5, mass = 0.55, area = 0.60 },
  dash  = { speed = 1.18, bob = 3.0, mass = 0.50, area = 0.35 },
  -- a leaf does not travel at one speed: it stalls, catches, and goes
  -- again. That pulse was the one per-kind rule the old loop could not
  -- write as a constant, so a kind's speed is allowed to be a function of
  -- the particle and its age.
  leaf  = {
    speed = function(p, t) return 0.78 + 0.20 * math.sin(t * 3.1 + (p.seed or 0)) end,
    bob = 9.5, mass = 0.12, area = 2.20,
  },
}

local field = Particles.newField(WindFX.KINDS, WindFX.MAX)
local frontCool = 0

local function notFront(m) return not m.front end

-- The step's context, reused. Building it fresh each frame was a table per
-- frame handed straight to the collector -- small against what the engine
-- allocates anyway, but this file has just finished pooling its motes for
-- exactly that reason and it would be odd to pool a hundred tables and then
-- drop one on the floor every frame.
local stepCtx = {}

-- Diagnostics for the same reason Weather.ticks exists: a probe found this
-- field frozen at 102 motes under a budget of 44, which the per-frame
-- setCap makes impossible if the update ran at all. `ticks` says whether
-- it was called; `lastGate` says which of the seven conditions in `live`
-- sent it home if it was.
WindFX.ticks = 0
WindFX.ticksLive = 0
WindFX.lastGate = "never ran"

local imgs = nil     -- { grit, seed, dash, swirl, swirlQ, swirlN } | false

local function loadImgs()
  if imgs ~= nil then return imgs or nil end
  local function one(name)
    local path = V.path .. "/assets/vfx/" .. name
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then
      pcall(img.setFilter, img, "nearest", "nearest")
      return img
    end
    return nil
  end
  local grit = one("wind_dust.png")
  local seed = one("wind_mote.png")
  local dash = one("wind_streak.png")
  local puff = one("wind_puff.png")
  local swirl = one("wind_swirl.png")
  local leaves = one("leaves.png")
  local swirlQ, swirlN = nil, 0
  if swirl then
    local fh = swirl:getHeight()
    swirlN = math.max(1, math.floor(swirl:getWidth() / math.max(1, fh)))
    swirlQ = {}
    for i = 0, swirlN - 1 do
      swirlQ[i] = love.graphics.newQuad(i * fh, 0, fh, fh, swirl:getDimensions())
    end
  end
  if not (grit or seed or dash or swirl or puff) then
    imgs = false
    return nil
  end
  local leafQ, leafN = nil, 0
  if leaves then
    local fw = 16
    leafN = math.max(1, math.floor(leaves:getWidth() / fw))
    leafQ = {}
    for i = 0, leafN - 1 do
      leafQ[i] = love.graphics.newQuad(i * fw, 0, fw, fw, leaves:getDimensions())
    end
  end
  imgs = {
    grit = grit, seed = seed or grit, dash = dash or seed,
    puff = puff, swirl = swirl, swirlQ = swirlQ, swirlN = swirlN,
    leaves = leaves, leafQ = leafQ, leafN = leafN,
  }
  return imgs
end

-- The sprite pack, for the other emitters that draw the same dust
-- through their own fields (StepFX is the first). One load, one texture
-- identity, no second copy of wind_dust.png in memory.
function WindFX.pack()
  return loadImgs()
end

-- ------- how high the ground is under a mote
--
-- Cached per cell for the frame: a field of three hundred motes asking the
-- terrain its own question three hundred times a frame is the sort of
-- thing that turns a cheap effect into an expensive one, and the answer
-- for a given cell cannot change inside one frame.
local ghCache, ghFrame = {}, -1

local function groundUnder(wx, wz)
  local Game = game()
  local ow = Game and Game.overworld
  local map = ow and ow.map
  if not map then return 0 end
  local t = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
  if t ~= ghFrame then
    for k in pairs(ghCache) do ghCache[k] = nil end
    ghFrame = t
  end
  local cx = math.floor((wx or 0) / 16)
  local cy = math.floor((wz or 0) / 16)
  local key = cx * 4096 + cy
  local h = ghCache[key]
  if h then return h end
  local VoxelScene = V.require("VoxelScene")
  local ok, v = pcall(VoxelScene.groundAt, map, cx, cy)
  h = (ok and tonumber(v)) or 0
  ghCache[key] = h
  return h
end

local function openSky(map)
  if not (map and map.def) then return false end
  if not Map.isOutdoor(map.def) then return false end
  return not DayNight.isCanopy(map)
end

-- What the air carries + palette + brightness.
local function climate()
  local kind = Weather.visible()
  if kind == "rain" then return "spray", WindFX.SPRAY, 0.72 end
  if kind == "snow" then return "snow", WindFX.BLOWN, 0.88 end
  return "dry", WindFX.DUST, 0.78
end

local function budget()
  local n = WindFX.MAX
  local ok, q = pcall(Quality.windStreaks)
  if ok and tonumber(q) then n = math.floor(q) end
  if n < 0 then n = 0 end
  if n > WindFX.MAX then n = WindFX.MAX end
  return n
end

-- Pick a particle kind that makes sense for this climate and wind strength.
-- Stronger wind → more seeds/dashes mixed in; weak breeze stays mostly grit.
-- ------- WHAT A STORM ACTUALLY BLOWS AROUND
--
-- Rain used to switch this to spray and dashes and nothing else, which is
-- the one climate where that is least true. A wind hard enough to slant
-- rain is a wind stripping the trees: the air in a squall is full of torn
-- leaves, and they are the thing that reads as violence, because unlike
-- spray they are big, coloured, and tumbling.
--
-- Rain also SOAKS what it carries, and that is why the mix is not the dry
-- one with water added. Grit and chaff go down to almost nothing -- wet
-- dust is mud and stays on the ground -- while leaves go UP, because a wet
-- gale is tearing them off faster than a dry one ever does.
local function pickKind(amount, front, climateKind)
  if front then return "dash" end
  if climateKind == "rain" then
    local r = rand()
    if amount < 0.9 then
      -- a shower in still air: mostly spray, the odd leaf let go
      if r < 0.74 then return "spray" end
      if r < 0.90 then return "leaf" end
      return "dash"
    end
    -- a squall: the wood is coming apart
    if r < 0.44 then return "spray" end
    if r < 0.80 then return "leaf" end
    return "dash"
  end
  if climateKind == "snow" then
    return rand() < 0.80 and "snow" or "dash"
  end
  local r = rand()
  if amount < 0.75 then
    -- light air: almost all grit, rare seed / one lost leaf
    if r < 0.78 then return "grit" end
    if r < 0.90 then return "puff" end
    if r < 0.97 then return "seed" end
    return "leaf"
  elseif amount < 1.40 then
    if r < 0.38 then return "grit" end
    if r < 0.52 then return "puff" end
    if r < 0.70 then return "seed" end
    if r < 0.88 then return "leaf" end
    return "dash"
  else
    -- gale: the air is full of what the trees just lost
    if r < 0.18 then return "grit" end
    if r < 0.28 then return "puff" end
    if r < 0.42 then return "seed" end
    if r < 0.82 then return "leaf" end
    return "dash"
  end
end

local function dustTint()
  local r = rand()
  if r < 0.28 then return WindFX.DUST end
  if r < 0.52 then return WindFX.DUST_B end
  if r < 0.76 then return WindFX.DUST_C end
  return WindFX.DUST_D
end

local function seedTint()
  return (rand() < 0.55) and WindFX.SEED or WindFX.SEED_B
end

local function spawn(px, pz, amount, opts)
  if field:count() >= budget() then return end
  opts = opts or {}
  local dx, dz = Wind.DIR[1] or 1, Wind.DIR[2] or 0
  local back = (opts.back or WindFX.SPAWN_AHEAD) * 16
  -- wider scatter when the wind is hard so the stream fills the view
  local wide = WindFX.SPAWN_WIDE * (0.75 + 0.55 * math.min(1.4, amount))
  local side = (opts.side ~= nil) and opts.side
               or (rand() * 2 - 1) * wide * 16
  local x = px - dx * back - dz * side
  local z = pz - dz * back + dx * side
  local climateKind = opts.climate or "dry"
  local kind = opts.kind or pickKind(amount, opts.front, climateKind)

  -- Height by kind: grit skims the grass, seeds float mid, dashes higher.
  -- measured from the ground under the spawn, not from world zero
  local floor = groundUnder(x, z)
  local y
  if kind == "grit" or kind == "snow" then
    y = floor + 1.8 + rand() * 6
  elseif kind == "puff" then
    y = floor + 3 + rand() * 8
  elseif kind == "leaf" then
    y = floor + 6 + rand() * 18
  elseif kind == "seed" or kind == "spray" then
    y = floor + 5 + rand() * 12
  else
    y = floor + 5 + rand() * 14
  end

  local tint
  if kind == "grit" or kind == "puff" then
    tint = dustTint()
  elseif kind == "seed" then
    tint = seedTint()
  elseif kind == "leaf" then
    tint = WindFX.LEAF[rand(1, #WindFX.LEAF)]
  end

  -- A claimed slot is a WIPED slot, so nothing carries over from whoever
  -- held it last; every field this kind reads is written here.
  local m = field:claim()
  if not m then return end
  m.x, m.z, m.y = x, z, y
  m.kind = kind
  m.seed = rand() * 6.2831
  m.t = 0
  m.ttl = (kind == "dash" and (1.0 + rand() * 1.1))
       or (kind == "grit" and (1.2 + rand() * 1.6))
       or (kind == "puff" and (1.3 + rand() * 1.5))
       or (kind == "leaf" and (2.2 + rand() * 2.8))
       or (1.6 + rand() * 2.2)
  m.fast = 0.55 + rand() * 0.90
  m.lift = (rand() * 2 - 1) * (kind == "dash" and 3 or (kind == "leaf" and 8 or 6))
  m.spin = (rand() * 2 - 1) * ((kind == "leaf" and (3.5 + rand() * 5))
                            or ((kind == "seed" or kind == "puff") and 4.5 or 1.6))
  m.frame = kind == "leaf" and rand(0, 15) or 0
  m.flip = rand() < 0.5 and -1 or 1
  m.front = opts.front or false
  -- wide size range so a cloud of grit is not one stamp
  m.size = 0.45 + rand() * 1.05
  m.tint = tint
  m.ang = 0
end

-- ------- T11: SPAWN AT AN EXACT POINT
--
-- spawn() above answers "put something in the AIR around the player" and
-- picks its own position from the wind. An emitter that knows WHERE a
-- particle comes from -- a tree crown shedding the leaf, a grass tuft
-- letting a seed go (VegFX) -- needs the opposite: the position is the
-- point, everything else defaults like spawn()'s. Same budget, same
-- field, same draw; `opts` overrides ttl/size/tint/lift/spin/fast, and
-- opts.veg marks the mote as vegetation-born so a probe can tell a leaf
-- torn OFF A TREE from the generic storm leaf pickKind carries in.
function WindFX.emit(kind, x, y, z, opts)
  if field:count() >= budget() then return false end
  opts = opts or {}
  local m = field:claim()
  if not m then return false end
  m.x, m.z, m.y = x, z, y
  m.kind = kind or "grit"
  m.seed = rand() * 6.2831
  m.t = 0
  m.ttl = opts.ttl or (1.6 + rand() * 2.2)
  m.fast = opts.fast or (0.55 + rand() * 0.90)
  m.lift = opts.lift or ((rand() * 2 - 1) * 6)
  m.spin = opts.spin or ((rand() * 2 - 1)
             * ((kind == "leaf" and (3.5 + rand() * 5)) or 3))
  m.frame = kind == "leaf" and rand(0, 15) or 0
  m.flip = rand() < 0.5 and -1 or 1
  m.front = false
  m.size = opts.size or (0.45 + rand() * 1.05)
  m.tint = opts.tint
  m.ang = 0
  m.veg = opts.veg or nil
  -- which emitter this mote was born from ("water", ...), for probes that
  -- need to judge one emitter's motes among everybody else's
  m.src = opts.src or nil
  if opts.vx then m.vx, m.vz = opts.vx, opts.vz or 0 end
  return true
end

-- for probes that need to look at the motes themselves
function WindFX.count() return field:count() end
function WindFX.get(i) return field:get(i) end

local function spawnFront(px, pz, amount, climateKind)
  local n = WindFX.FRONT_N
  if n < 1 then return end
  local cap = budget()
  local wide = WindFX.FRONT_WIDE * 16
  for i = 1, n do
    if field:count() >= cap then break end
    local f = (n > 1) and ((i - 1) / (n - 1) * 2 - 1) or 0
    spawn(px, pz, amount, {
      back = WindFX.SPAWN_AHEAD + 1.5,
      side = f * wide + (rand() * 2 - 1) * 8,
      front = true,
      kind = "dash",
      climate = climateKind,
    })
  end
end

function WindFX.clear()
  field:clear()
end

function WindFX.update(dt, voxelOn)
  WindFX.ticks = WindFX.ticks + 1
  if WindFX.HOLD then WindFX.lastGate = "HOLD" return end
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
  frontCool = frontCool - dt

  local amount = 0
  local okA, n = pcall(Wind.amount)
  if okA then amount = n or 0 end

  local cap = budget()
  -- the live ceiling is the RES rung's, not WindFX.MAX -- and it moves
  -- when the row does, so it is pushed every frame rather than at build
  field:setCap(cap)
  local Game = game()
  local ow = Game and Game.overworld
  local live = voxelOn and cap > 0 and amount > WindFX.FLOOR
                and ow and ow.map and ow.player
                and openSky(ow.map)
                and Game.stack and Game.stack:top() == ow
                and not ow.transitioning
  if not live then
    WindFX.lastGate =
      (not voxelOn and "voxelOn=false")
      or (cap <= 0 and "budget=0")
      or (amount <= WindFX.FLOOR and "wind below FLOOR")
      or (not (ow and ow.map and ow.player) and "no overworld/map/player")
      or (not openSky(ow.map) and "indoors (no open sky)")
      or (not (Game.stack and Game.stack:top() == ow) and "overworld not on top")
      or (ow.transitioning and "map transitioning")
      or "unknown"
    WindFX.clear()
    return
  end
  WindFX.lastGate = "live"
  WindFX.ticksLive = WindFX.ticksLive + 1

  local climateKind = select(1, climate())
  local p = ow.player
  local px, pz = p.cellX * 16, p.cellY * 16

  -- Density scales hard with wind: weak breeze = a few specks, gale = a
  -- stream. Quadratic so the middle of AUTO does not already look full.
  local headroom = math.max(0, cap - WindFX.FRONT_N)
  local t = (amount - WindFX.FLOOR) / 1.35
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  local want = math.floor(2 + (t * t) * (headroom - 2))
  if want > headroom then want = headroom end
  if want < 0 then want = 0 end
  local standing = field:countIf(notFront)
  -- refill faster under a gale so the field stays dense as motes expire
  local burst = 2 + math.floor(t * 10)
  for _ = 1, math.min(burst, math.max(0, want - standing)) do
    spawn(px, pz, amount, { climate = climateKind })
  end

  local gust = 0
  local okG, g = pcall(Wind.gust)
  if okG then gust = g or 0 end
  if gust >= WindFX.FRONT_AT and frontCool <= 0 then
    frontCool = WindFX.FRONT_WAIT
    spawnFront(px, pz, amount, climateKind)
  end

  -- ------- AND FROM HERE THE AIR IS ONE PIECE OF ARITHMETIC
  --
  -- What used to be sixty lines here -- the band lookup, the per-kind
  -- speed ladder, the two-sine curl, the bob, the ground clamp and the
  -- reach cull -- is lib/Particles.lua now, and the weather's own world
  -- motes will step through the same code. The numbers did not change;
  -- where they live did. Verified as statistics rather than as a claim:
  -- tests/particles_parity_probe.lua samples the field before and after
  -- and prints its own noise floor to judge the difference against.
  --
  -- floorAt is not optional in practice. The clamp used to be an absolute
  -- 0.8..28, which is right on a route's dirt and wrong everywhere worth
  -- standing: a town's paving is raised, so on it the whole dust field ran
  -- INSIDE the street, and on a roof it ran through the tiles. Measuring
  -- from the ground under each mote is what fixed that, and it is why the
  -- solver takes a function rather than two numbers.
  stepCtx.dirX = Wind.DIR[1] or 1
  stepCtx.dirZ = Wind.DIR[2] or 0
  stepCtx.speed = amount * WindFX.SPEED
  -- the eddies (T7): world px/s per unit of Wind.turbAt, this field's own
  -- conversion just like `speed` is
  stepCtx.turbulence = amount * WindFX.SPEED * WindFX.TURB
  stepCtx.floorAt = groundUnder
  stepCtx.originX, stepCtx.originZ = px, pz
  stepCtx.reach = WindFX.REACH * 16 + 48
  field:step(dt, stepCtx)
end

local function imgFor(pack, kind)
  if not pack then return nil end
  if kind == "dash" then return pack.dash end
  if kind == "leaf" then return pack.leaves end
  if kind == "seed" or kind == "spray" then return pack.seed end
  if kind == "puff" then return pack.puff or pack.grit end
  if kind == "grit" or kind == "snow" then return pack.grit end
  return pack.grit or pack.seed
end

local function colourFor(m, base)
  if m.tint then return m.tint end
  if m.kind == "seed" then return WindFX.SEED end
  if m.kind == "dash" and base == WindFX.DUST then return WindFX.DASH end
  return base
end

function WindFX.draw(project, scale)
  if WindFX.WORLD_PASS then return end
  local live = field:count()
  if live == 0 then return end
  local g = love.graphics
  local climateKind, baseCol, bright = climate()
  local prevBlend, prevAlpha = g.getBlendMode()
  g.setBlendMode("alpha")

  local pack = loadImgs()
  local scl = scale or 1

  -- standing first, front second (front overdraws = closer read)
  for pass = 0, 1 do
    local wantFront = (pass == 1)
    for i = 1, live do
      local m = field:get(i)
      if (m.front and true or false) == wantFront then
        local sx, sy, ps = project(m.x, m.y, m.z)
        if sx then
          local fade = math.min(1, m.t * 4, (m.ttl - m.t) * 2.5)
          local a = bright * fade * (wantFront and 1.2 or 1.0)
          if a > 0.02 then
            local s = math.max(1, scl * (ps or 1))
            local col = colourFor(m, baseCol)
            if climateKind == "rain" then col = WindFX.SPRAY end
            if climateKind == "snow" then col = WindFX.BLOWN end

            local ang = m.ang or 0
            local vx, vz = m.vx or 0, m.vz or 0
            -- align dashes to travel
            if m.kind == "dash" or wantFront then
              local ex, ey = project(m.x - vx * WindFX.TAIL,
                                     m.y, m.z - vz * WindFX.TAIL)
              if ex then ang = math.atan2(sy - ey, sx - ex) end
            end

            -- Gust front: curl strip (opens over life) + thin dash under it
            if wantFront and pack and pack.swirl and pack.swirlQ then
              local u = math.min(1, math.max(0, m.t / math.max(0.001, m.ttl)))
              local qi = math.min(pack.swirlN - 1, math.floor(u * pack.swirlN))
              local q = pack.swirlQ[qi]
              if q then
                local fh = pack.swirl:getHeight()
                local px = math.max(5, s * 2.6)
                g.setColor(col[1], col[2], col[3], math.min(1, a * 0.9))
                pcall(g.draw, pack.swirl, q, sx, sy, ang,
                      px / fh, px / fh, fh * 0.5, fh * 0.5)
              end
            end

            local use = imgFor(pack, m.kind)
            if m.kind == "leaf" and pack and pack.leaves and pack.leafQ then
              local n = pack.leafN or 1
              local q = pack.leafQ[(m.frame or 0) % n]
              local flip = math.sin(ang * 0.5)
              local sxS = ((flip >= 0) and 1 or -1) * (m.flip or 1)
              local squash = 0.55 + 0.45 * math.abs(flip)
              local px = math.max(4, s * 1.7 * (m.size or 1))
              g.setColor(col[1], col[2], col[3], math.min(1, a))
              if q then
                pcall(g.draw, pack.leaves, q, sx, sy, ang,
                      sxS * px / 16, squash * px / 16, 8, 8)
              end
            elseif use then
              local iw = use:getWidth()
              local ih = use:getHeight()
              if iw > 0 and ih > 0 then
                local px
                local stretchX, stretchY = 1, 1
                if m.kind == "dash" then
                  px = math.max(5, s * 2.0 * (m.size or 1))
                  stretchX, stretchY = 2.6, 0.85
                elseif m.kind == "seed" or m.kind == "spray" then
                  px = math.max(3.5, s * 1.5 * (m.size or 1))
                  stretchX, stretchY = 1.5, 0.9
                elseif m.kind == "puff" then
                  px = math.max(4, s * 1.8 * (m.size or 1))
                  stretchX, stretchY = 1.2, 1.1
                else
                  -- grit / snow: small hard dots, size varies a lot
                  px = math.max(2.5, s * 1.05 * (m.size or 1))
                  stretchX, stretchY = 1.0, 1.0
                end
                g.setColor(col[1], col[2], col[3], math.min(1, a))
                pcall(g.draw, use, sx, sy, ang,
                      (px * stretchX) / iw, (px * stretchY) / ih,
                      iw * 0.5, ih * 0.5)
              end
            else
              g.setColor(col[1], col[2], col[3], math.min(1, a))
              local d = math.max(1, s * (m.kind == "dash" and 2.5 or 1.0))
              if m.kind == "dash" then
                g.rectangle("fill", sx - d * 1.4, sy - 0.5, d * 2.8, math.max(1, s * 0.5))
              else
                g.rectangle("fill", sx - d * 0.4, sy - d * 0.4, d * 0.8, d * 0.8)
              end
            end
          end
        end
      end
    end
  end

  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  g.setColor(1, 1, 1, 1)
end

-- ------- AND THE SAME FIELD, AS GEOMETRY IN THE SCENE PASS
--
-- The draw above paints into the OVERLAY, which has no depth test by
-- construction -- so every mote in it passed in front of the mountain and
-- through the roof, always. This one hands the field to the scene pass as
-- cards, and the depth buffer answers both.
--
-- Deliberately NOT a rewrite of the look. Image, colour, alpha and angle
-- are read through the very same imgFor / colourFor / climate the overlay
-- draw uses, so the only thing that differs between the two paths is
-- whether the geometry in front of a mote is allowed to hide it. That is
-- what makes the change checkable: anything else that moved is a bug.
--
-- Size does change register, and has to. The overlay sized a mote in
-- SCREEN pixels and multiplied by the projection's own scale to fake
-- perspective; a card of a given WORLD size shrinks with distance because
-- it genuinely is further away. The constants carried over are the old
-- screen numbers read as world pixels -- which is what they always meant
-- at the focus plane, where the projection's scale is one.
local builder = nil

-- Per-kind card size in world pixels, and how it is stretched. Lifted
-- straight out of the overlay draw's ladder so the two agree.
local CARD = {
  dash  = { 2.0, 2.6, 0.85 },
  seed  = { 1.5, 1.5, 0.90 },
  spray = { 1.5, 1.5, 0.90 },
  puff  = { 1.8, 1.2, 1.10 },
  leaf  = { 1.7, 1.0, 1.00 },
  grit  = { 1.05, 1.0, 1.0 },
  snow  = { 1.05, 1.0, 1.0 },
}

function WindFX.drawWorld()
  if not WindFX.WORLD_PASS then return 0 end
  local live = field:count()
  if live == 0 then return 0 end
  local pack = loadImgs()
  if not pack then return 0 end
  local climateKind, baseCol, bright = climate()
  builder = builder or ParticleMesh.newBuilder(WindFX.MAX)

  local leafN = pack.leafN or 1
  local describe = function(m)
    local img = imgFor(pack, m.kind)
    if not img then return nil end
    local fade = math.min(1, m.t * 4, (m.ttl - m.t) * 2.5)
    local a = bright * fade * (m.front and 1.2 or 1.0)
    if a <= 0.02 then return nil end
    if a > 1 then a = 1 end
    local col = colourFor(m, baseCol)
    if climateKind == "rain" then col = WindFX.SPRAY end
    if climateKind == "snow" then col = WindFX.BLOWN end

    local u0, v0, u1, v1 = 0, 0, 1, 1
    if m.kind == "leaf" and pack.leaves then
      -- the strip is leafN frames wide; pick this mote's own
      local f = (m.frame or 0) % leafN
      u0 = f / leafN
      u1 = (f + 1) / leafN
    end

    local c = CARD[m.kind] or CARD.grit
    local base = c[1] * (m.size or 1)
    local hw = base * c[2] * 0.5
    local hh = base * c[3] * 0.5
    if hw < 0.5 then hw = 0.5 end
    if hh < 0.5 then hh = 0.5 end

    return img, u0, v0, u1, v1, hw, hh, m.ang or 0,
           col[1], col[2], col[3], a
  end

  local mesh, batches = builder:build(field, describe)
  if not mesh then WindFX.lastBatches = 0 return 0 end
  -- Depth WRITES on. These sprites are hard cutouts -- white pixels and
  -- fully transparent ones, nothing between (tools/make_wind_sprites.py
  -- authors them that way on purpose) -- and the scene shader discards the
  -- transparent half before it does anything else. So a mote writing its
  -- own depth is honest, and it buys the field its own sorting: a grain in
  -- front of another grain hides it, with no sort in Lua.
  local drew = Voxel3D.drawParticles(mesh, nil, batches, true)
  WindFX.lastBatches = drew
  return drew
end

-- ------- A FIELD OF EXACTLY ONE MOTE, PUT WHERE THE PROBE WANTS IT
--
-- Statistics cannot settle occlusion. The first attempt tried to isolate
-- the field by subtracting a WIND OFF frame -- but WIND OFF also stops the
-- grass, so what it measured was a meadow rather than a mote, and 95% of
-- the frame came back "lit".
--
-- One mote, parked, is unambiguous instead: put inside a building it must
-- DRAW through the overlay and VANISH through the scene pass, and put in
-- the open it must survive both. Two frames, two pixel counts, nothing to
-- interpret.
--
-- `pinned` is what keeps the solver's hands off it -- including the ground
-- clamp, which would otherwise lift a mote placed inside a house up onto
-- its roof and quietly test nothing at all.
function WindFX.pinOne(kind, x, y, z, size)
  field:clear()
  local m = field:claim()
  if not m then return false end
  m.x, m.z, m.y = x, z, y
  m.kind = kind or "puff"
  m.seed = 0
  m.t = 0.5              -- past the fade-in, so alpha is full at once
  m.ttl = 1e6
  m.fast, m.lift, m.spin = 0, 0, 0
  m.frame, m.flip = 0, 1
  m.front = false
  m.size = size or 6
  m.ang = 0
  m.vx, m.vz = 0, 0
  -- magenta: Pallet Town's roofs are red and its grass is green, but
  -- nothing in a Game Boy Pokemon palette is red AND blue at once, so
  -- a pixel with r and b high and g low can only be this mote
  m.tint = { 1.0, 0.0, 1.0 }
  m.pinned = true
  return true
end

-- The ground height under a point, so a probe can place a mote relative to
-- the surface it is testing against rather than to world zero.
function WindFX.groundAt(x, z)
  return groundUnder(x, z)
end

-- How many colour batches the last scene-pass draw actually issued. Zero
-- means the field reached the pass and nothing came out, which is a
-- different failure from an empty field and has to be visible as such.
WindFX.lastBatches = -1

function WindFX.count()
  return field:count()
end

-- ------- WHAT THE FIELD IS DOING, AS NUMBERS
--
-- Aggregates rather than a dump, because the point of them is a BEFORE and
-- an AFTER that have to match: the solver extraction in lib/Particles.lua
-- is a port, and a port whose motion changed is a port nobody can sign
-- off. Individual motes are seeded from love.math.random and will never
-- line up run to run; the statistics of a steady field will.
--
-- Sampled by tests/particles_parity_probe.lua over hundreds of frames of a
-- pinned wind, which is what turns these into something with a tolerance.
function WindFX.stats(out)
  out = out or {}
  local n = field:count()
  out.n = n
  out.kinds = out.kinds or {}
  for k in pairs(out.kinds) do out.kinds[k] = nil end
  local sumV, sumY, sumAge, sumDX, sumDZ, sumSpin = 0, 0, 0, 0, 0, 0
  local minY, maxY = 1e9, -1e9
  for i = 1, n do
    local m = field:get(i)
    local vx, vz = m.vx or 0, m.vz or 0
    sumV = sumV + math.sqrt(vx * vx + vz * vz)
    sumY = sumY + (m.y or 0)
    if (m.y or 0) < minY then minY = m.y or 0 end
    if (m.y or 0) > maxY then maxY = m.y or 0 end
    sumAge = sumAge + ((m.ttl and m.ttl > 0) and (m.t / m.ttl) or 0)
    sumSpin = sumSpin + math.abs(m.spin or 0)
    -- ground-relative spread is what a reach cull actually shapes, and it
    -- is measured from the mote's own floor rather than from world zero
    local g = groundUnder(m.x, m.z)
    sumDX = sumDX + math.abs((m.y or 0) - g)
    sumDZ = sumDZ + (m.size or 0)
    out.kinds[m.kind] = (out.kinds[m.kind] or 0) + 1
  end
  local d = (n > 0) and n or 1
  out.meanSpeed = sumV / d
  out.meanY = sumY / d
  out.meanAboveGround = sumDX / d
  out.meanSize = sumDZ / d
  out.meanAge = sumAge / d
  out.meanSpin = sumSpin / d
  out.minY = (n > 0) and minY or 0
  out.maxY = (n > 0) and maxY or 0
  return out
end

return WindFX
