-- Voxel world mode: the wind drawn as LINES.
--
-- The wind you could see used to be sprite sheets: a swoosh that bloomed out
-- of a ring and trailed off as a green cloud, a green crescent turning over,
-- a grey puff in the rain. Drawn over a meadow they read as gas -- a cartoon
-- fart crossing the diorama, in the player's own words -- and no amount of
-- fading them made them read as air, because the SHAPE was a cloud.
--
-- Air is not a cloud. The drawn wind of every anime background and of the
-- Zelda games since Wind Waker is a LINE: a stroke that writes itself along
-- the flow, sometimes throws a loop or winds round a twin, and is erased from
-- its tail as it goes. That is this file.
--
--   PATH    integrated through the wind field the grass is bending in
--           (Wind.flowAt, eddies included) from the stroke's birth point,
--           with inertia so it curves rather than jitters. So a stroke swerves
--           where the meadow under it swirls -- the two are one wind. It holds
--           its height over the ground, rising and settling slowly.
--   SHAPES  a FLOW (long, lazy), a LOOP (one turn thrown along the way, in a
--           plane tilted between the ground and the sky so it reads as a loop
--           from this camera whichever way the wind runs), a TWIN (two strokes
--           winding round one path as a helix -- the gust with a twist in it),
--           and a FLICK (short, fast, straight: a gale's shred). The wind's
--           strength is the vocabulary: a breeze is a lazy stroke or two with
--           loops; a gale is a sky of long flows, twins and flicks, and a rank
--           of them on every gust front.
--   STROKE  the head runs the path and WRITES; the tail follows `lag` seconds
--           behind and ERASES; the head stops at the end and the tail catches
--           it up. Born as a point, dies as a point -- no fade in mid-air.
--   BODY    GEOMETRY in the scene pass (WindFX.drawWorld), so a crown or a
--           roof in front hides it, the hour lights it and the haze takes it
--           with distance. A ribbon turned to face the eye, in three stacked
--           layers -- a faint wide glow, a halo, a thin bright core -- each
--           tapered to nothing at both ends and widest toward the head. The
--           scene shader draws cutouts (alpha is per draw, not per texel), so
--           the soft edge is built as cel steps -- the house style anyway.
--   WHERE   BACKGROUND (WindFX rule 9): a band over the ground by the crowns,
--           never across the player's feet. Leaves are the wind at eye level.
--   SWIRL   in a real wind, now and then, a pair of strokes winds round a
--           tree crown near the player -- climbing a turn and a half in a
--           spiral, each with a leaf, then peeling off downwind: the air
--           going round an obstacle, the reference's leaves circling a tree.
--   CARRY   some loops and twins -- and half a gust front -- catch a LEAF
--           (one of WindFX's own tumbling leaves, lent through `hooks`): it
--           rides the head of the stroke, round the loop and along the twist,
--           and when the head reaches the end the gust lets it go and it
--           drifts off on the field like any other leaf.
--
-- One mesh; one draw range per layer x strength bucket; one uniform setup.

local V = ...

local Wind = V.require("Wind")
local Voxel3D = V.require("Voxel3D")

local WindLines = {}

WindLines.MAX = 34             -- strokes alive at once (a twin is two)
WindLines.SEG = 16             -- samples along the drawn part of a stroke
WindLines.DS = 3               -- world px between path points
WindLines.BAND = { 18, 46 }    -- world px above the ground (background)
WindLines.SPEED = { 64, 52 }   -- world px/s: base, and per unit Wind.amount
WindLines.LAG = { 0.30, 0.55 } -- s the tail runs behind: breeze .. gale
WindLines.INERTIA = 0.88       -- how much of its heading a path keeps a step
WindLines.EDDY = 0.9           -- how hard the eddies turn a path
-- full widths in world px of the three layers, and their alpha
-- (wide and soft: the reference's strokes are wisps of air, not wires)
WindLines.LAYERS = {
  { w = 6.4, a = 0.10 },       -- glow
  { w = 3.0, a = 0.24 },       -- halo
  { w = 1.15, a = 0.84 },      -- core
}
WindLines.LOW = { 5, 16 }      -- the low band a strong wind also fills
WindLines.LOW_SHARE = 0.35     -- of strokes in it, at a full gale
WindLines.CARRY = 0.40         -- of loops and twins that catch a leaf
WindLines.CARRY_FRONT = 0.50   -- of a gust front's strokes
WindLines.TINT = { dry = { 1.00, 1.00, 1.00 }, rain = { 0.78, 0.86, 0.96 },
                   snow = { 1.00, 1.00, 1.00 } }
WindLines.STRENGTH = { dry = 1.0, rain = 0.55, snow = 0.85 }
WindLines.FRONT = 6            -- strokes in a gust front's rank
WindLines.SWIRL_AT = 0.9       -- Wind.amount() a swirl needs
WindLines.SWIRL_EVERY = 5.0    -- s between swirls, on average, in a gale
WindLines.BACK = 5.0           -- cells upwind of the player a stroke is born
WindLines.WIDE = 11.0          -- cells either side of the wind's axis
-- (far enough back and wide enough that a stroke CROSSES the view, the way
-- the reference's sweep the whole frame, instead of starting mid-screen)

-- for the probes
WindLines.spawned = 0
WindLines.fronts = 0
WindLines.drawn = 0
WindLines.lastError = nil

local lines = {}
local rand = love and love.math and love.math.random or math.random

local function clamp(x, a, b)
  if x < a then return a elseif x > b then return b end
  return x
end

-- ------- the path, integrated once at birth

-- The flow's heading at a point, eddies included; `hx, hz` when the field
-- says nothing (calm, or no wind module state yet).
local function flowDir(x, z, hx, hz)
  local vx, vz = hx, hz
  local ok, fx, fz = pcall(Wind.flowAt, x, z)
  if ok and fx and (fx * fx + fz * fz) > 1e-6 then
    local m = math.sqrt(fx * fx + fz * fz)
    vx, vz = fx / m, fz / m
  end
  local okT, ux, uz = pcall(Wind.turbAt, x, z)
  if okT and ux then
    vx = vx + ux * WindLines.EDDY
    vz = vz + uz * WindLines.EDDY
  end
  local m = math.sqrt(vx * vx + vz * vz)
  if m < 1e-6 then return hx, hz end
  return vx / m, vz / m
end

-- Points every DS world px (xs, ys, zs) and the heading at each (dxs, dzs),
-- which the loop and the twin build their frames from.
local function buildPath(l, x, y, z, hx, hz, len, groundAt)
  local ds = WindLines.DS
  local xs, ys, zs, dxs, dzs = {}, {}, {}, {}, {}
  local n = math.max(2, math.floor(len / ds))
  local k = WindLines.INERTIA
  local loopAt = l.loopAt and math.floor(n * l.loopAt) or -1
  local i = 0
  for s = 0, n do
    local g = 0
    if groundAt then
      local okG, gh = pcall(groundAt, x, z)
      if okG and tonumber(gh) then g = gh end
    end
    -- hold the band over the ground, rising and settling slowly
    local want = g + l.height + l.rise * math.sin(s * l.riseK + l.riseP)
    y = y + (want - y) * 0.12
    i = i + 1
    xs[i], ys[i], zs[i], dxs[i], dzs[i] = x, y, z, hx, hz
    if s == loopAt and l.r > 0 then
      -- one turn up and over in the plane (heading, tilted normal)
      local sgn = l.loopSide
      local nx, ny, nz = -hz * sgn * 0.55, 0.83, hx * sgn * 0.55
      local steps = math.max(8, math.floor(2 * math.pi * l.r / ds))
      for j = 1, steps do
        local a = j / steps * 2 * math.pi
        local fwd = l.r * math.sin(a)
        local up = l.r * (1 - math.cos(a))
        i = i + 1
        xs[i] = x + hx * fwd + nx * up
        ys[i] = y + ny * up
        zs[i] = z + hz * fwd + nz * up
        dxs[i], dzs[i] = hx, hz
      end
    end
    local fx, fz = flowDir(x, z, hx, hz)
    hx, hz = hx * k + fx * (1 - k), hz * k + fz * (1 - k)
    local m = math.sqrt(hx * hx + hz * hz)
    if m > 1e-6 then hx, hz = hx / m, hz / m end
    x, z = x + hx * ds, z + hz * ds
  end
  l.xs, l.ys, l.zs, l.dxs, l.dzs = xs, ys, zs, dxs, dzs
  l.total = (#xs - 1) * ds
end

-- Position at arc length s along the path -- clamped at both ends, so a
-- sample a hair past the end (tail + (head - tail) * 1 rounds up) is the end
-- and not an error -- plus the twin's helix round it.
local function pathAt(l, s)
  local ds = WindLines.DS
  local last = #l.xs
  local f = clamp(s / ds, 0, last - 1)
  local i = math.floor(f)
  local t = f - i
  local a, b = i + 1, math.min(i + 2, last)
  local x = l.xs[a] + (l.xs[b] - l.xs[a]) * t
  local y = l.ys[a] + (l.ys[b] - l.ys[a]) * t
  local z = l.zs[a] + (l.zs[b] - l.zs[a]) * t
  if l.helix then
    local hx, hz = l.dxs[a], l.dzs[a]
    local th = s * l.helixK + l.helixP
    local c, sn = math.cos(th) * l.helix, math.sin(th) * l.helix
    -- round the path: sideways and up
    x = x - hz * c
    z = z + hx * c
    y = y + sn
  end
  return x, y, z
end

-- ------- birth

local function pickShape(amount, climateKind, front)
  if climateKind == "rain" then return "flow" end
  local r = rand()
  local gale = clamp((amount - 1.0) / 1.5, 0, 1)
  if front then
    if r < 0.25 + 0.2 * gale then return "twin" end
    return (r < 0.8) and "flow" or "flick"
  end
  local loop = 0.45 - 0.25 * gale
  local twin = 0.08 + 0.17 * gale
  local flick = 0.25 * gale
  if r < loop then return "loop" end
  if r < loop + twin then return "twin" end
  if r < loop + twin + flick then return "flick" end
  return "flow"
end

local function newStroke(p)
  lines[#lines + 1] = p
  WindLines.spawned = WindLines.spawned + 1
  return p
end

local function born(px, pz, amount, climateKind, groundAt, side, delay, front)
  local shape = pickShape(amount, climateKind, front)
  local need = (shape == "twin") and 2 or 1
  if #lines + need > WindLines.MAX then return false end
  local back = WindLines.BACK * 16
  local wdx, wdz = Wind.DIR[1] or 1, Wind.DIR[2] or 0
  side = side or (rand() * 2 - 1) * WindLines.WIDE * 16
  local x = px - wdx * back - wdz * side + (rand() * 2 - 1) * 24
  local z = pz - wdz * back + wdx * side + (rand() * 2 - 1) * 24
  local hx, hz = flowDir(x, z, wdx, wdz)
  local gale = clamp((amount - 1.0) / 1.5, 0, 1)
  local band = WindLines.BAND
  local slow = (climateKind == "snow") and 0.7 or 1
  local len
  if shape == "flick" then
    len = 34 + rand() * 26
  else
    len = (120 + rand() * 110) * (0.85 + 0.5 * gale)
  end
  -- a strong wind fills the air low too -- across the path, past the
  -- player's knees -- which a breeze never does
  local height = band[1] + rand() * (band[2] - band[1])
  if rand() < WindLines.LOW_SHARE * gale then
    height = WindLines.LOW[1] + rand() * (WindLines.LOW[2] - WindLines.LOW[1])
  end
  local l = {
    shape = shape,
    height = height,
    rise = 2 + rand() * 4, riseK = 0.05 + rand() * 0.06, riseP = rand() * 6.28,
    r = 0,
    speed = (WindLines.SPEED[1] + WindLines.SPEED[2] * math.min(amount, 3)) * slow
            * (0.85 + rand() * 0.3) * ((shape == "flick") and 1.45 or 1),
    lag = WindLines.LAG[1] + (WindLines.LAG[2] - WindLines.LAG[1]) * gale,
    t = -(delay or 0),
    front = front and true or false,
    climate = climateKind,
    -- how loud this one is: most are quiet, a few carry the gust
    strength = (0.55 + rand() * 0.45) * (front and 1.15 or 1),
    width = (0.85 + rand() * 0.3) * ((shape == "flick") and 0.8 or 1),
  }
  if shape == "loop" then
    l.r = 3.5 + rand() * 4.0
    l.loopAt = 0.55 + rand() * 0.3
    l.loopSide = (rand() < 0.5) and -1 or 1
  end
  if shape == "flick" then l.lag = l.lag * 0.6 end
  if climateKind == "dry" and shape ~= "flick"
     and rand() < (front and WindLines.CARRY_FRONT
                   or ((shape == "loop" or shape == "twin") and WindLines.CARRY or 0)) then
    l.wantLeaf = true
  end
  local g = 0
  if groundAt then
    local okG, gh = pcall(groundAt, x, z)
    if okG and tonumber(gh) then g = gh end
  end
  buildPath(l, x, g + l.height, z, hx, hz, len, groundAt)
  newStroke(l)
  if shape == "twin" then
    -- the pair winds round ONE path: same points, opposite phase
    -- a long, slow twist -- a short tight one reads as a zigzag, not a pair
    l.helix = 3.2 + rand() * 1.6
    l.helixK = (2 * math.pi) / (62 + rand() * 30)
    l.helixP = rand() * 6.28
    local m = {}
    for key, v in pairs(l) do m[key] = v end
    m.helixP = l.helixP + math.pi
    m.strength = l.strength * 0.85
    m.wantLeaf = nil               -- one leaf to a pair
    newStroke(m)
  end
  return true
end

-- ------- the swirl: round a crown and away
--
-- The path is written directly rather than integrated: a spiral of radius R
-- round (cx, cz), from low in the crown to just over it, turning with the
-- wind's handedness, then a tail that leaves along the flow.
local function buildSwirl(l, c, a0, sense, turns, R)
  local ds = WindLines.DS
  local xs, ys, zs, dxs, dzs = {}, {}, {}, {}, {}
  local y0, y1 = (c.h or 16) * 0.45, (c.h or 16) + 6
  local steps = math.max(12, math.floor(turns * 2 * math.pi * R / ds))
  local i = 0
  for k = 0, steps do
    local u = k / steps
    local a = a0 + sense * u * turns * 2 * math.pi
    local r = R * (1 + 0.15 * u)
    i = i + 1
    xs[i] = c.x + math.cos(a) * r
    zs[i] = c.z + math.sin(a) * r
    ys[i] = y0 + (y1 - y0) * u
    dxs[i], dzs[i] = -math.sin(a) * sense, math.cos(a) * sense
  end
  -- and away along the flow from where the spiral let go
  local x, y, z = xs[i], ys[i], zs[i]
  local hx, hz = dxs[i], dzs[i]
  for _ = 1, 18 do
    local fx, fz = flowDir(x, z, hx, hz)
    hx, hz = hx * 0.8 + fx * 0.2, hz * 0.8 + fz * 0.2
    local m = math.sqrt(hx * hx + hz * hz)
    if m > 1e-6 then hx, hz = hx / m, hz / m end
    x, z = x + hx * ds, z + hz * ds
    i = i + 1
    xs[i], ys[i], zs[i], dxs[i], dzs[i] = x, y, z, hx, hz
  end
  l.xs, l.ys, l.zs, l.dxs, l.dzs = xs, ys, zs, dxs, dzs
  l.total = (#xs - 1) * ds
end

local function bornSwirl(c, amount, climateKind)
  if #lines + 2 > WindLines.MAX then return false end
  local wdx, wdz = Wind.DIR[1] or 1, Wind.DIR[2] or 0
  -- the handedness a crosswind gives the air going round a trunk
  local sense = (rand() < 0.5) and 1 or -1
  local R = 12 + rand() * 6
  local turns = 1.2 + rand() * 0.5
  -- start on the upwind side (math.atan2 is LuaJIT's; 5.3+ spells it atan)
  local a0 = (math.atan2 or math.atan)(-wdz, -wdx)
  local gale = clamp((amount - 1.0) / 1.5, 0, 1)
  for j = 0, 1 do
    local l = {
      shape = "swirl", height = 0, rise = 0, riseK = 0, riseP = 0, r = 0,
      speed = (WindLines.SPEED[1] + WindLines.SPEED[2] * math.min(amount, 3))
              * (0.8 + rand() * 0.2),
      lag = WindLines.LAG[1] + (WindLines.LAG[2] - WindLines.LAG[1]) * gale,
      t = -j * 0.25, front = true, climate = climateKind,
      strength = 0.8 + rand() * 0.3, width = 0.9 + rand() * 0.2,
      wantLeaf = climateKind == "dry",
    }
    buildSwirl(l, c, a0 + j * math.pi, sense, turns, R + j * 2.5)
    newStroke(l)
  end
  WindLines.swirls = (WindLines.swirls or 0) + 1
  return true
end

-- A gust front: a rank of strokes across the view, staggered in time so they
-- read as one gust arriving rather than a formation.
function WindLines.front(px, pz, amount, climateKind, groundAt)
  WindLines.fronts = WindLines.fronts + 1
  local n = WindLines.FRONT
  for i = 1, n do
    local f = (n > 1) and ((i - 1) / (n - 1) * 2 - 1) or 0
    born(px, pz, amount, climateKind, groundAt,
         f * WindLines.WIDE * 16 * 0.7 + (rand() * 2 - 1) * 10,
         rand() * 0.45, true)
  end
end

-- ------- the frame

-- A carried leaf: follow the head while the stroke writes, let go when the
-- head reaches the end. `hooks.claimLeaf(x, y, z)` lends one (or nil), and
-- `hooks.releaseLeaf(m)` hands it back to the field's own drift.
local function carry(l, dt, hooks)
  local m = l.leaf
  if m and m.carriedBy ~= l then l.leaf = nil; m = nil end   -- recycled
  local head = l.t * l.speed
  if head >= l.total then
    if m then
      if hooks and hooks.releaseLeaf then hooks.releaseLeaf(m) end
      m.carriedBy = nil
      l.leaf = nil
    end
    l.wantLeaf = nil
    return
  end
  if l.t <= 0 then return end
  local x, y, z = pathAt(l, head)
  if not m and l.wantLeaf and hooks and hooks.claimLeaf then
    m = hooks.claimLeaf(x, y, z)
    l.wantLeaf = nil
    if m then m.carriedBy = l; l.leaf = m end
  end
  if m then
    m.x, m.y, m.z = x, y, z
    m.t = (m.t or 0) + dt          -- the tumble clip runs on the mote's clock
  end
end

local function drop(l, hooks)
  local m = l.leaf
  if m and m.carriedBy == l then
    if hooks and hooks.releaseLeaf then hooks.releaseLeaf(m) end
    m.carriedBy = nil
  end
  l.leaf = nil
end

-- `live` false clears everything: the strokes belong to the air of THIS view.
function WindLines.update(dt, live, px, pz, amount, climateKind, groundAt, hooks)
  if not live then
    for i = #lines, 1, -1 do drop(lines[i], hooks); lines[i] = nil end
    return
  end
  -- how many standing strokes this wind wants: a breeze is a couple, a gale
  -- a sky full of them; wet air half of that
  local t = clamp((amount - 0.45) / 1.6, 0, 1)
  local want = math.floor(1 + t * t * 22 + 0.5)
  if climateKind == "rain" then want = math.floor(want * 0.5 + 0.5) end
  local standing = 0
  for i = #lines, 1, -1 do
    local l = lines[i]
    l.t = l.t + dt
    carry(l, dt, hooks)
    if (l.t - l.lag) * l.speed >= l.total then
      drop(l, hooks)
      table.remove(lines, i)
    elseif not l.front then
      standing = standing + 1
    end
  end
  -- a trickle, not a burst: at most one birth a frame
  if standing < want and rand() < 0.35 then
    born(px, pz, amount, climateKind, groundAt)
  end
  -- now and then, the air going round a tree
  if amount >= WindLines.SWIRL_AT and climateKind ~= "rain" and hooks and hooks.crown
     and rand() < dt * clamp((amount - 0.6) / 1.4, 0, 1) / WindLines.SWIRL_EVERY then
    local c = hooks.crown()
    if c then bornSwirl(c, amount, climateKind) end
  end
end

-- ------- the draw (scene pass)

-- Drawn as INDEXED strips: two vertices per sample, shared by the quads on
-- either side of it, and the triangles named through the vertex map. The
-- first build wrote six vertices per segment per layer -- 8100 of them, six
-- floats each, crossing into C through setVertices every frame -- and that
-- crossing, not the arithmetic, was the cost (1.3 ms a frame in a gale on
-- the i3 this is tuned for).
local mesh = nil
local white = nil
local verts = {}
local map = {}
local ranges = {}               -- one per layer x strength bucket
local BUCKETS = 3
local MAXV = WindLines.MAX * #WindLines.LAYERS * WindLines.SEG * 2
local MAXI = WindLines.MAX * #WindLines.LAYERS * (WindLines.SEG - 1) * 6
local byBucket = {}
for b = 1, BUCKETS do byBucket[b] = {} end

local function whiteImage()
  if white == nil then
    local ok, img = pcall(function()
      local d = love.image.newImageData(1, 1)
      d:setPixel(0, 0, 1, 1, 1, 1)
      return love.graphics.newImage(d)
    end)
    white = ok and img or false
  end
  return white or nil
end

local function vert(i, x, y, z)
  local v = verts[i]
  if not v then v = {}; verts[i] = v end
  v[1], v[2], v[3], v[4], v[5], v[6] = x, y, z, 0.5, 0.5, 1
end

-- The drawn part of stroke l, sampled ONCE per frame into the stroke's own
-- arrays: position (l.px/py/pz), the ribbon's across-vector toward the eye
-- (l.ax/ay/az) and the taper (l.tw). The three layers then only scale a
-- width -- the first version re-sampled and re-crossed for every layer and
-- cost 0.8 ms a frame in a gale on the machine this is tuned for.
local function sample(l, ex, ey, ez)
  local SEG = WindLines.SEG
  local head = math.min(l.t * l.speed, l.total)
  local tail = math.max(0, (l.t - l.lag) * l.speed)
  if head <= tail + 0.5 then return false end
  local px, py, pz = l.px, l.py, l.pz
  if not px then
    px, py, pz = {}, {}, {}
    l.px, l.py, l.pz = px, py, pz
    l.ax, l.ay, l.az, l.tw = {}, {}, {}, {}
  end
  for k = 1, SEG do
    px[k], py[k], pz[k] = pathAt(l, tail + (head - tail) * (k - 1) / (SEG - 1))
  end
  local ax, ay, az, tw = l.ax, l.ay, l.az, l.tw
  for k = 1, SEG do
    local a = (k > 1) and (k - 1) or 1
    local b = (k < SEG) and (k + 1) or SEG
    local dx, dy, dz = px[b] - px[a], py[b] - py[a], pz[b] - pz[a]
    local m = math.sqrt(dx * dx + dy * dy + dz * dz)
    if m < 1e-6 then dx, dy, dz, m = 1, 0, 0, 1 end
    dx, dy, dz = dx / m, dy / m, dz / m
    -- across = tangent x (eye - point): the ribbon shows its face to the eye
    local vx, vy, vz = ex - px[k], ey - py[k], ez - pz[k]
    local cx = dy * vz - dz * vy
    local cy = dz * vx - dx * vz
    local cz = dx * vy - dy * vx
    local c = math.sqrt(cx * cx + cy * cy + cz * cz)
    if c < 1e-6 then cx, cy, cz, c = 0, 1, 0, 1 end
    ax[k], ay[k], az[k] = cx / c, cy / c, cz / c
    -- thin at the tail, swelling toward the head, and a ROUND head -- the
    -- pen's tip, the brightest part of a stroke being written
    local u = (k - 1) / (SEG - 1)
    local w = u ^ 0.6
    if u > 0.86 then
      local q = (u - 0.86) / 0.14
      w = w * math.sqrt(math.max(0, 1 - q * q))
    end
    tw[k] = w * l.width * 0.5
  end
  return true
end

function WindLines.drawWorld()
  WindLines.drawn = 0
  if #lines == 0 then return 0 end
  local eye = Voxel3D.eye
  if not eye then return 0 end
  local img = whiteImage()
  if not img then return 0 end
  if not mesh then
    local ok, m = pcall(love.graphics.newMesh, Voxel3D.FORMAT, MAXV, "triangles", "stream")
    if not ok then return 0 end
    mesh = m
  end
  local ex, ey, ez = eye[1], eye[2], eye[3]
  local SEG = WindLines.SEG
  -- sample every visible stroke once, and bucket it by strength, so a
  -- layer x bucket is one draw range
  for bk = 1, BUCKETS do
    local bb = byBucket[bk]
    for i = #bb, 1, -1 do bb[i] = nil end
  end
  local climate = "dry"
  for _, l in ipairs(lines) do
    if l.t > 0 and sample(l, ex, ey, ez) then
      climate = l.climate
      WindLines.drawn = WindLines.drawn + 1
      local st = l.strength * (WindLines.STRENGTH[l.climate] or 1)
      local bk = clamp(math.floor(st * BUCKETS + 0.5), 1, BUCKETS)
      local bb = byBucket[bk]
      bb[#bb + 1] = l
    end
  end
  local tint = WindLines.TINT[climate] or WindLines.TINT.dry
  local nv, ni, r = 0, 0, 0
  for _, layer in ipairs(WindLines.LAYERS) do
    local lw = layer.w
    for bk = 1, BUCKETS do
      local first = ni + 1
      for _, l in ipairs(byBucket[bk]) do
        if nv + SEG * 2 <= MAXV and ni + (SEG - 1) * 6 <= MAXI then
          local px, py, pz = l.px, l.py, l.pz
          local ax, ay, az, tw = l.ax, l.ay, l.az, l.tw
          local base = nv
          for k = 1, SEG do
            local w = tw[k] * lw
            local x, y, z = ax[k] * w, ay[k] * w, az[k] * w
            vert(nv + 1, px[k] + x, py[k] + y, pz[k] + z)
            vert(nv + 2, px[k] - x, py[k] - y, pz[k] - z)
            nv = nv + 2
          end
          for k = 0, SEG - 2 do
            local v0 = base + k * 2 + 1       -- this sample's two sides
            map[ni + 1], map[ni + 2], map[ni + 3] = v0, v0 + 1, v0 + 2
            map[ni + 4], map[ni + 5], map[ni + 6] = v0 + 2, v0 + 1, v0 + 3
            ni = ni + 6
          end
        end
      end
      local count = ni - first + 1
      if count > 0 then
        r = r + 1
        local rg = ranges[r]
        if not rg then rg = {}; ranges[r] = rg end
        rg.first, rg.count = first, count
        rg.r, rg.g, rg.b = tint[1], tint[2], tint[3]
        rg.a = layer.a * (bk / BUCKETS)
        rg.img = img
      end
    end
  end
  for i = r + 1, #ranges do ranges[i] = nil end
  if ni == 0 then return 0 end
  -- exactly the rows in use: the vertex map has no count argument, and a
  -- stale index past the end would name last frame's vertices
  for i = ni + 1, #map do map[i] = nil end
  local ok = pcall(mesh.setVertices, mesh, verts, 1, nv)
  if not ok then
    for i = nv + 1, #verts do verts[i] = nil end
    ok = pcall(mesh.setVertices, mesh, verts, 1)
    if not ok then return 0 end
  end
  if not pcall(mesh.setVertexMap, mesh, map) then return 0 end
  -- translucent: depth-TESTED (a crown in front hides a stroke) but not
  -- written, so a stroke's glow never punches a hole in the one behind it
  return Voxel3D.drawParticles(mesh, img, ranges, false)
end

-- for the probes
function WindLines.count() return #lines end
function WindLines.list() return lines end
function WindLines.clear(hooks)
  for i = #lines, 1, -1 do drop(lines[i], hooks); lines[i] = nil end
end
function WindLines._pathAt(l, s) return pathAt(l, s) end

return WindLines
