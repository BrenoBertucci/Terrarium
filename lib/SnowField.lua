-- The snow's own MEMORY: where it has been walked on, and what that did to it.
--
-- A snowfall used to be a tint on every up-facing voxel plus a ring of
-- footprint decals, and the two never met: the tint was one number for the
-- whole map, so a field of snow was the same field wherever anybody had
-- walked, and the prints were stickers lying on it. What snow actually
-- does under a boot is DEFORM -- the boot goes down into it, the snow it
-- displaced piles up along the edge, and the next boot lands in the trench
-- the last one opened. A trail through a drift is a groove with a raised
-- rim and a line of prints along its floor, and it stays.
--
-- This file is that groove. One texel per world pixel (two on the longest
-- routes), sized to the map, two channels:
--
--   R  pressed   0..1  how far down this spot has been trodden
--   G  rim       0..1  how much displaced snow is heaped here
--
-- The scene shader reads it in the FRAGMENT stage (lib/Voxel3D.lua, the
-- snow block): the pressed channel lowers the local surface, the rim raises
-- it, the slope between neighbouring texels becomes a normal the sun and a
-- fixed key light shade -- which is what makes a trench read as a trench
-- rather than as a grey stripe -- and where the boot reached the ground,
-- the ground shows.
--
-- ------- why the fragment stage, and why not a mesh
--
-- The wear field (lib/GrassWear.lua) is a vertex tap, and that tap is the
-- construct a GLES2 driver is allowed to refuse: the compatibility ladder
-- exists because it did (see LADDER in Voxel3D). A fragment tap is
-- refusable by nothing, so this field works on the phones the vertex one
-- falls off. And a displaced MESH -- the obvious realistic answer -- would
-- rebuild geometry under every footstep, which is the one cost this mod's
-- whole terrain design (ChunkMesher's cache, BuildBudget) exists to never
-- pay. Relief from a normal costs five texture reads on snowed ground
-- and nothing anywhere else.
--
-- ------- what writes it
--
-- VoxelScene hands over the same `feet` list the grass springs and the wear
-- field already read: who is standing where this frame, and whether they
-- are moving. A moving walker in DEEP snow ploughs a soft groove the width
-- of the body along their path (the legs push through it); at every depth
-- they leave a FOOTPRINT every STRIDE pixels of travel -- a boot-shaped
-- pit, long along the way they are going, alternating left and right of
-- the line -- and the ring just outside every stamp takes the displaced
-- snow. Standing still writes nothing: a person waiting at a door for an
-- hour must not drill through the drift.
--
-- ------- and what erases it: almost nothing, on purpose
--
-- A trail is PERMANENT the way it is in the games this is measured
-- against: it outlives the walk, the map change and the session's clock,
-- and only two things take it away. Fresh snow buries it, slowly -- minutes
-- of a full fall to fill a trench level, so a path walked at the start of
-- a storm is still a shallow line at the end of it -- and the thaw wipes
-- it, because there is nothing left to be a trail in. Still air settles
-- nothing. Each texel stores its value AS WRITTEN plus the burial clock's
-- reading then, so the current value is computed on read and a map with
-- fifty thousand trodden texels costs nothing while nobody is looking at
-- them. The same design as GrassWear, and the same trap: the accumulator
-- reads the raw value, never a presentation-clamped one.
--
-- ------- and what the image costs
--
-- One RGBA8 per texel, and a town at one texel per pixel is a 640x576
-- image -- which is why nothing here uploads the whole of it. A walker
-- touches a few hundred texels a frame in one corner; the image is cut
-- into 32x32 BLOCKS and only the blocks touched since the last upload are
-- pushed (ImageData:paste into a scratch, Image:replacePixels at an
-- offset). A set of blocks rather than one bounding box, because six
-- walkers on six corners of a town make a box the size of the town, and
-- did: 182 blocks in one frame, measured. A probe that writes a region
-- wholesale calls flushAll.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local SnowField = {}

-- ------- resolution
--
-- One world pixel per texel wherever the map allows it: a boot is three
-- pixels wide and five long, and a footprint that is a shape rather than a
-- dab is the whole difference between this and the decal it replaced.
-- Texels per axis are capped; the longest route (Route 23, 72 cells tall)
-- lands on two-pixel texels, where a print is still a print.
SnowField.MAX_RES = 1024
SnowField.MIN_TEXEL = 1
SnowField.MAX_TEXEL = 4

-- ------- the boot
--
-- All in world pixels. A Gen 1 walker is 16 wide with the body about 10 of
-- it; the groove is the body's width, the footprint is a boot's.
SnowField.PRESS_R = 4.4        -- the groove's half-width
SnowField.PRESS_RATE = 5.0     -- compaction per second under the body's disc
-- The groove stops SHORT of a boot's pressing, and the difference is the
-- footprints: pressed to the same depth, the pits would vanish into the
-- trench they lie along. The legs push the fall aside; the boots go down.
SnowField.PRESS_MAX = 0.62
SnowField.FOOT_LONG = 2.7      -- a footprint's half-length, along the path
SnowField.FOOT_WIDE = 1.65     -- and half-width, across it
SnowField.FOOT_ADD = 0.90      -- a footfall presses nearly all the way
SnowField.FOOT_SIDE = 2.1      -- feet land either side of the line of travel
SnowField.STRIDE = 8           -- world px between footfalls (half a cell)
SnowField.RIM_W = 2.6          -- how far past a stamp the heap reaches
SnowField.RIM_RATE = 2.4       -- heap per second along the groove's edge
SnowField.RIM_FOOT = 0.42      -- and what one footfall throws up
SnowField.RIM_CAP = 1.0

-- The groove is the LEGS pushing through the fall, so it needs a fall deep
-- enough to push through: nothing below this cover, all of it above the
-- second number. The footprints do not care -- a boot prints in a dusting.
SnowField.PLOW_FROM = 0.35
SnowField.PLOW_FULL = 0.85

-- Who presses how hard. The player is the reference; NPCs walk more and
-- roamers weigh less, exactly as GrassWear weights them.
SnowField.WEIGHT = { player = 1.0, npc = 0.85, mon = 0.55, ghost = 0 }

-- ------- the clock
--
-- Seconds of full-power snowfall to bury a fresh trench level. Nothing
-- else erases one (FILL_STILL at or below zero is "never"), and the thaw
-- clears the map outright.
--
-- Seventy seconds, down from seven minutes: a trail is meant to be SEEN
-- going under -- walk out, turn round, and the prints you left are
-- already softening, the deepest last. Seven minutes was a permanence
-- nobody could tell from forever. With the sky still, it IS forever.
SnowField.FILL_SNOWING = 70
SnowField.FILL_STILL = 0

-- Below this a texel is level snow again and is dropped.
SnowField.KEEP = 0.02

-- Texels revisited per step for the lazy burial. Only matters while it is
-- snowing over an old trail; the budget bounds the frame, not the result.
SnowField.VISIT_BUDGET = 400
-- The GPU copy is refreshed at most this often while dirty.
SnowField.FLUSH_EVERY = 2
-- The upload block. 32x32 RGBA8 is four kilobytes; a walker's frame dirties
-- one to four of them.
SnowField.BLOCK = 32

-- ------- how far a walker SINKS
--
-- World pixels of the card hidden at full cover. A sixteen-pixel sprite is
-- knee-deep at five and buried at twelve; TWO is the boots and no more --
-- "up to the feet, not most of the body" was the second request, and the
-- collar below is cut to the same height.
SnowField.SINK_PX = 2
-- The cover at which anything starts to sink or print at all: a dusting
-- neither hides a boot nor holds a print.
SnowField.FROM = 0.12

-- ------- per-map state
--
-- Keyed by the map's id. Each:
--   w, h     texels        texel   world px per texel
--   p[idx]   pressed as written      t[idx]  burial clock then
--   g[idx]   rim as written
--   live     idx -> true             dirty   idx -> true
--   blocks   block index -> true, the image blocks touched since the
--            last upload
--   idata    ImageData (w x h rgba8)  img     Image, or false if refused
--   scratch  ImageData for the block uploads
local maps = {}
local bound = nil
local boundKey = nil
-- The last few maps keep their trails so walking back onto a route finds
-- what you left there. Oldest out.
SnowField.KEEP_MAPS = 6
local order = {}

-- Monotonic integrated burial, in "fills": 1.0 = one full trench buried.
local fill = 0.0
local flushCountdown = 0
local visitCursor = nil

-- Instruments. `stamps` counts footfalls placed (the probe's trail claim),
-- `mine` the player's own.
SnowField.stamps = 0
SnowField.myStamps = 0
SnowField.lastWrites = 0
SnowField.lastBlocks = 0
SnowField.lastError = nil
SnowField.errors = 0

-- ------- the two readings of a texel (see the header: two, on purpose)
local function rawAt(st, idx)
  local p = st.p[idx]
  if not p then return 0, 0 end
  local g = st.g[idx] or 0
  local gone = fill - (st.t[idx] or fill)
  if gone <= 0 then return p, g end
  -- fresh snow levels a trench and a heap alike: both go down by what
  -- has fallen since they were written. (A heap with no trench under it
  -- -- a slab off a roof -- is a texel of its own, not a side effect of
  -- pressing, and must not vanish with a pressing it never had.)
  local cp = p - gone
  if cp < 0 then cp = 0 end
  local cg = g - gone
  if cg < 0 then cg = 0 end
  return cp, cg
end

local function shown(st, idx)
  local p, g = rawAt(st, idx)
  if p < SnowField.KEEP then p = 0 end
  if g < SnowField.KEEP then g = 0 end
  return p, g
end

-- ------- sizing a map

local function sizeFor(map)
  local wc = (map and map.widthCells) or 64
  local hc = (map and map.heightCells) or 64
  local wpx, hpx = wc * 16, hc * 16
  local texel = SnowField.MIN_TEXEL
  local longest = math.max(wpx, hpx)
  while longest / texel > SnowField.MAX_RES and texel < SnowField.MAX_TEXEL do
    texel = texel + 1
  end
  local w = math.min(SnowField.MAX_RES, math.ceil(wpx / texel))
  local h = math.min(SnowField.MAX_RES, math.ceil(hpx / texel))
  if w < 1 then w = 1 end
  if h < 1 then h = 1 end
  return w, h, texel
end

local function newState(map)
  local w, h, texel = sizeFor(map)
  return { w = w, h = h, texel = texel,
           p = {}, g = {}, t = {}, live = {}, dirty = {}, n = 0,
           blocks = {}, idata = nil, img = nil, scratch = nil }
end

local function idxOf(st, x, z)
  if x < 0 or z < 0 or x >= st.w or z >= st.h then return nil end
  return z * st.w + x
end

-- ------- writing

-- Which upload block a texel sits in.
local function blockOf(st, x, z)
  local B = SnowField.BLOCK
  return math.floor(x / B) + math.floor(z / B) * 4096
end

local function touch(st, idx, x, z, dp, dg, cap)
  local p, g = rawAt(st, idx)
  local np = p + dp
  -- the cap holds the GROOVE short of a boot; it never lowers what a boot
  -- already pressed
  if np > cap then np = (p > cap) and p or cap end
  local ng = g + dg
  if ng > SnowField.RIM_CAP then ng = SnowField.RIM_CAP end
  if np <= 0 and ng <= 0 then return end
  -- the heap can only stand where nothing has pressed it flat
  if np > 0.6 then ng = ng * (1 - (np - 0.6) * 2.5) end
  if ng < 0 then ng = 0 end
  if st.p[idx] == nil then
    st.live[idx] = true
    st.n = st.n + 1
  end
  -- Re-stamped against the clock: the value written is what is there
  -- NOW, and the clock reading is now, so the burial resumes from here.
  st.p[idx] = np
  st.g[idx] = ng
  st.t[idx] = fill
  st.dirty[idx] = true
  st.blocks[blockOf(st, x, z)] = true
  SnowField.lastWrites = SnowField.lastWrites + 1
end

-- A stamp: an ELLIPSE of pressing centred on world (wx, wz), semi-axes
-- `along` on the bearing (mx, mz) and `across` at right angles to it;
-- `amount` inside, easing off only at the very edge (a boot has a flat
-- sole and a steep wall), and the heap in a band of RIM_W outside it.
local function stamp(st, wx, wz, mx, mz, along, across, amount, rimAmount,
                     cap)
  cap = cap or 1
  local reach = math.max(along, across) + SnowField.RIM_W
  local tx, tz = wx / st.texel, wz / st.texel
  local rt = reach / st.texel
  local x0, x1 = math.floor(tx - rt), math.floor(tx + rt)
  local z0, z1 = math.floor(tz - rt), math.floor(tz + rt)
  local rimW = SnowField.RIM_W
  for z = z0, z1 do
    for x = x0, x1 do
      local idx = idxOf(st, x, z)
      if idx then
        -- texel centre, in world px, then into the stamp's own frame
        local dx = (x + 0.5) * st.texel - wx
        local dz = (z + 0.5) * st.texel - wz
        local u = dx * mx + dz * mz
        local v = -dx * mz + dz * mx
        local e = (u * u) / (along * along) + (v * v) / (across * across)
        if e < 1 then
          -- flat floor, steep wall: full amount to 60 % of the radius
          local k = 1 - e
          if k > 0.4 then k = 1 else k = k / 0.4 end
          touch(st, idx, x, z, amount * k, 0, cap)
        elseif rimAmount > 0 then
          -- distance past the edge, approximately, along the same ray
          local r = math.sqrt(e)
          local edgeAlong = along / r
          local edgeAcross = across / r
          local d = math.sqrt(u * u + v * v)
              - math.sqrt(edgeAlong * edgeAlong * (u * u) / (u * u + v * v + 1e-6)
                          + edgeAcross * edgeAcross * (v * v) / (u * u + v * v + 1e-6))
          if d < rimW then
            local q = d / rimW
            if q < 0 then q = 0 end
            -- a hump peaking just past the lip
            touch(st, idx, x, z, 0, rimAmount * math.sin(q * math.pi), 1)
          end
        end
      end
    end
  end
end

-- Per-walker stride memory: where they were, how far since the last
-- footfall, and which foot is next. Weak keys: an NPC that despawns takes
-- its entry with it.
local strides = setmetatable({}, { __mode = "k" })

-- Whether pressing is possible at all right now: a bound field, the row
-- on, and enough cover on the ground to hold a shape.
local coverNow = 0
local function pressable()
  return bound ~= nil and coverNow >= SnowField.FROM
end

-- How much of the groove the legs plough at this cover: none in a dusting,
-- all of it in a deep fall.
local function plowNow()
  local k = (coverNow - SnowField.PLOW_FROM)
            / (SnowField.PLOW_FULL - SnowField.PLOW_FROM)
  if k < 0 then return 0 end
  if k > 1 then return 1 end
  return k
end

-- One walker, one frame. `ent` is the engine entity (identity only), `kind`
-- one of the WEIGHT keys, `moving` whether they are actually stepping.
function SnowField.walk(ent, wx, wz, kind, moving, dt)
  if not ent then return end
  local st = bound
  if not st then return end
  local tr = strides[ent]
  if not tr then
    strides[ent] = { x = wx, z = wz, acc = 0, side = 1, mx = 0, mz = 1 }
    return
  end
  local dx, dz = wx - tr.x, wz - tr.z
  tr.x, tr.z = wx, wz
  local d = math.sqrt(dx * dx + dz * dz)
  if d > 24 then tr.acc = 0 return end        -- a warp, not a sprint
  if not moving or d <= 0.01 then return end
  if not pressable() then return end
  local weight = SnowField.WEIGHT[kind or "npc"] or SnowField.WEIGHT.npc
  if weight <= 0 then return end
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
  local mx, mz = dx / d, dz / d
  tr.mx, tr.mz = mx, mz
  -- the groove: the body's disc, every frame it moves, in deep snow only
  local plow = plowNow()
  if plow > 0 then
    stamp(st, wx, wz, mx, mz, SnowField.PRESS_R, SnowField.PRESS_R,
          SnowField.PRESS_RATE * dt * weight * plow,
          SnowField.RIM_RATE * dt * weight * plow, SnowField.PRESS_MAX)
  end
  -- the footprints: every STRIDE px, alternating sides of the line of
  -- travel, each a boot-shaped pit pointing the way they are going
  tr.acc = tr.acc + d
  while tr.acc >= SnowField.STRIDE do
    tr.acc = tr.acc - SnowField.STRIDE
    tr.side = -tr.side
    local ox = -mz * SnowField.FOOT_SIDE * tr.side
    local oz = mx * SnowField.FOOT_SIDE * tr.side
    stamp(st, wx + ox, wz + oz, mx, mz,
          SnowField.FOOT_LONG, SnowField.FOOT_WIDE,
          SnowField.FOOT_ADD * weight, SnowField.RIM_FOOT * weight)
    SnowField.stamps = SnowField.stamps + 1
    if kind == "player" then SnowField.myStamps = SnowField.myStamps + 1 end
  end
end

-- A whole disc at once, at a fixed pressing: what a probe or an event uses.
function SnowField.stamp(wx, wz, r, amount)
  local st = bound
  if not st then return end
  r = tonumber(r) or SnowField.FOOT_LONG
  stamp(st, wx, wz, 1, 0, r, r, tonumber(amount) or 1, SnowField.RIM_FOOT)
end

-- Snow ARRIVING rather than being pressed: a clump off a roof or out of
-- a crown lands here and heaps up (lib/SnowFallFX.lua). A disc of the rim
-- channel, highest in the middle, that the shader raises the surface by.
function SnowField.heap(wx, wz, r, amount)
  local st = bound
  if not st then return end
  r = tonumber(r) or 3
  amount = tonumber(amount) or 0.2
  if not pressable() then return end
  local tx, tz = wx / st.texel, wz / st.texel
  local rt = r / st.texel
  local rr = r * r
  for z = math.floor(tz - rt), math.floor(tz + rt) do
    for x = math.floor(tx - rt), math.floor(tx + rt) do
      local idx = idxOf(st, x, z)
      if idx then
        local dx = (x + 0.5) * st.texel - wx
        local dz = (z + 0.5) * st.texel - wz
        local d2 = dx * dx + dz * dz
        if d2 < rr then
          touch(st, idx, x, z, 0, amount * (1 - d2 / rr), 1)
        end
      end
    end
  end
end

-- ------- snow on a particular somebody
--
-- A tree shaken over a walker leaves its load on their hat and shoulders
-- whether or not it is snowing: per entity, and sliding off over half a
-- minute like the fall's own coat. Read by VoxelScene for each figure's
-- draw and taken as the larger of this and the weather's.
SnowField.DUMP_SLIDE = 30
local dumped = setmetatable({}, { __mode = "k" })
local dumpClock = 0

function SnowField.dumpOn(ent, amount)
  if not ent then return end
  local d = dumped[ent]
  local cur = 0
  if d then
    cur = d.k - (dumpClock - d.t) / SnowField.DUMP_SLIDE
    if cur < 0 then cur = 0 end
  end
  cur = cur + (tonumber(amount) or 1)
  if cur > 1 then cur = 1 end
  -- a negative amount is the coat SHEDDING (a walker shaking it off);
  -- gone is gone
  if cur <= 0 then dumped[ent] = nil return end
  dumped[ent] = { k = cur, t = dumpClock }
end

function SnowField.coatOf(ent)
  local d = ent and dumped[ent]
  if not d then return 0 end
  local cur = d.k - (dumpClock - d.t) / SnowField.DUMP_SLIDE
  if cur <= 0 then
    dumped[ent] = nil
    return 0
  end
  return cur
end

-- ------- reading

-- Pressed and rim at a world position, 0,0 where the snow is level.
function SnowField.at(wx, wz)
  local st = bound
  if not st then return 0, 0 end
  local idx = idxOf(st, math.floor((tonumber(wx) or 0) / st.texel),
                        math.floor((tonumber(wz) or 0) / st.texel))
  if not idx then return 0, 0 end
  return shown(st, idx)
end

-- How many texels this map currently remembers as trodden or heaped.
function SnowField.count()
  local st = bound
  if not st then return 0 end
  local n = 0
  for idx in pairs(st.live) do
    local p, g = shown(st, idx)
    if p > 0 or g > 0 then n = n + 1 end
  end
  return n
end

function SnowField.texel()
  return bound and bound.texel or SnowField.MIN_TEXEL
end

function SnowField.size()
  if not bound then return 0, 0 end
  return bound.w, bound.h
end

-- How many world pixels of a walker's card the snow hides, for the cover
-- on the ground right now. Integer, because the card is cut in whole
-- texels (SpriteBillboards). 0 below FROM; the full SINK_PX at full cover.
-- Not read from the field on purpose: a walker is always standing in the
-- trench they just pressed, so a field reading would say "no snow here"
-- under everybody, and the cover a person sinks into is the snow AROUND
-- their legs, which is the undisturbed fall.
function SnowField.sink(cover)
  cover = tonumber(cover) or 0
  if cover < SnowField.FROM then return 0 end
  local k = (cover - SnowField.FROM) / (1 - SnowField.FROM)
  if k > 1 then k = 1 end
  return math.floor(SnowField.SINK_PX * k + 0.5)
end

-- ------- binding a map

local function release(st)
  if st.img and st.img ~= false and st.img.release then
    pcall(st.img.release, st.img)
  end
  if st.idata and st.idata ~= false and st.idata.release then
    pcall(st.idata.release, st.idata)
  end
  if st.scratch and st.scratch.release then pcall(st.scratch.release, st.scratch) end
end

local function evict()
  while #order > SnowField.KEEP_MAPS do
    local key = table.remove(order, 1)
    if key ~= boundKey then
      local st = maps[key]
      if st then release(st) end
      maps[key] = nil
    end
  end
end

function SnowField.bind(map, key)
  key = key or (map and (map.id or map.name)) or "?"
  if boundKey == key then return end
  boundKey = key
  local st = maps[key]
  if not st then
    st = newState(map)
    maps[key] = st
  end
  bound = st
  for i = #order, 1, -1 do
    if order[i] == key then table.remove(order, i) end
  end
  order[#order + 1] = key
  evict()
  visitCursor = nil
  flushCountdown = 0
end

function SnowField.boundKey()
  return boundKey
end

-- Forget every trail on the bound map (the fall has melted off, or a
-- probe wants a clean sheet). The image is repainted level.
function SnowField.clear()
  local st = bound
  if not st then return end
  for idx in pairs(st.live) do
    st.p[idx], st.g[idx], st.t[idx] = nil, nil, nil
    st.dirty[idx] = true
    st.blocks[blockOf(st, idx % st.w, math.floor(idx / st.w))] = true
  end
  st.live = {}
  st.n = 0
  visitCursor = nil
end

-- ------- the image

local function ensureImage(st)
  if st.idata == false then return false end
  if st.idata == nil then
    if not (love and love.image and love.image.newImageData) then
      st.idata = false
      return false
    end
    local ok, d = pcall(love.image.newImageData, st.w, st.h)
    if not (ok and d) then
      st.idata = false
      return false
    end
    -- a fresh ImageData is all zero, which is exactly level snow
    st.idata = d
  end
  return true
end

local function paint(st, idx)
  local p, g = shown(st, idx)
  local x, z = idx % st.w, math.floor(idx / st.w)
  pcall(st.idata.setPixel, st.idata, x, z, p, g, 0, 1)
end

-- Push the touched blocks to the GPU, or the whole image when `all` is
-- asked, the image does not exist yet, or more than a quarter of it moved
-- (one call beats a hundred).
local function upload(st, all)
  if st.img == nil then
    local ok, img = pcall(love.graphics.newImage, st.idata)
    if not (ok and img) then
      st.img = false
      return
    end
    -- LINEAR: the trench's walls are the slope between two texels, and a
    -- nearest sampler would make every wall a cliff one texel wide
    pcall(img.setFilter, img, "linear", "linear")
    pcall(img.setWrap, img, "clamp", "clamp")
    st.img = img
    st.blocks = {}
    return
  end
  if not st.img.replacePixels then return end
  local B = SnowField.BLOCK
  local bw, bh = math.min(B, st.w), math.min(B, st.h)
  local count = 0
  for _ in pairs(st.blocks) do count = count + 1 end
  local total = math.ceil(st.w / bw) * math.ceil(st.h / bh)
  if all or count == 0 or count * 4 > total then
    pcall(st.img.replacePixels, st.img, st.idata)
    st.blocks = {}
    SnowField.lastBlocks = count
    return
  end
  if not st.scratch then
    local ok, d = pcall(love.image.newImageData, bw, bh)
    if not (ok and d) then
      -- no scratch, no blocks: the whole image, every time
      pcall(st.img.replacePixels, st.img, st.idata)
      st.blocks = {}
      return
    end
    st.scratch = d
  end
  for key in pairs(st.blocks) do
    -- a block that would run off the image is slid back inside it
    local bx = math.min((key % 4096) * B, st.w - bw)
    local bz = math.min(math.floor(key / 4096) * B, st.h - bh)
    local ok = pcall(st.scratch.paste, st.scratch, st.idata, 0, 0, bx, bz,
                     bw, bh)
    if ok then
      pcall(st.img.replacePixels, st.img, st.scratch, 1, 1, bx, bz)
    end
  end
  SnowField.lastBlocks = count
  st.blocks = {}
end

local function flush(st, all)
  if not next(st.dirty) then
    if all and st.img and st.img ~= false and next(st.blocks) then
      upload(st, true)
    end
    return
  end
  if not ensureImage(st) then return end
  if st.img == false then return end
  for idx in pairs(st.dirty) do paint(st, idx) end
  st.dirty = {}
  upload(st, all)
end

-- Drain the whole dirty set and push the whole image now, whatever it
-- costs. A probe that wrote a region and shot two frames later must not
-- measure a patchwork.
function SnowField.flushAll()
  local st = bound
  if st then flush(st, true) end
  flushCountdown = SnowField.FLUSH_EVERY
end

-- ------- the per-frame tick
--
-- `kind, power` are Weather.falling()'s answer; `cover` is GroundFX's
-- settled cover, which gates pressing and, at zero, wipes the map's trails
-- (there is nothing left to be a trail in).
function SnowField.step(dt, kind, power, cover)
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.5 then dt = 0.5 end
  coverNow = tonumber(cover) or 0
  dumpClock = dumpClock + dt
  -- the burial clock: snowfall fills, and nothing else does
  local burying = false
  if kind == "snow" and SnowField.FILL_SNOWING > 0 then
    fill = fill + dt * (tonumber(power) or 0) / SnowField.FILL_SNOWING
    burying = true
  end
  if SnowField.FILL_STILL > 0 then
    fill = fill + dt / SnowField.FILL_STILL
    burying = true
  end
  local st = bound
  if not st then return end
  if coverNow <= 0.001 and st.n > 0 then
    SnowField.clear()
  end
  -- the rolling revisit: a texel being buried is never written by
  -- anything, so this walk is the only thing that carries its pixel down
  -- with it. Only while something is burying -- a permanent trail needs
  -- no revisiting at all.
  if burying then
    local retire = nil
    local n = 0
    local k = visitCursor
    while n < SnowField.VISIT_BUDGET do
      local idx = next(st.live, k)
      if idx == nil then
        k = nil
        break
      end
      k = idx
      local p, g = rawAt(st, idx)
      if p <= SnowField.KEEP and g <= SnowField.KEEP then
        retire = retire or {}
        retire[#retire + 1] = idx
      end
      st.dirty[idx] = true
      st.blocks[blockOf(st, idx % st.w, math.floor(idx / st.w))] = true
      n = n + 1
    end
    visitCursor = k
    if retire then
      for i = 1, #retire do
        local idx = retire[i]
        st.p[idx], st.g[idx], st.t[idx] = nil, nil, nil
        st.live[idx] = nil
        st.n = st.n - 1
        st.dirty[idx] = true
      end
      visitCursor = nil
    end
  end
  flushCountdown = flushCountdown - 1
  if flushCountdown <= 0 and next(st.dirty) then
    flush(st)
    flushCountdown = SnowField.FLUSH_EVERY
  end
end

-- What VoxelScene hands to Voxel3D for the map underfoot: the image, the
-- field's world extent, the size of one texel (for the relief taps) and
-- how steep a trench wall is. nil when there is no image, which the sender
-- turns into the always-bound blank.
function SnowField.state()
  local st = bound
  if not (st and st.img and st.img ~= false) then return nil end
  return {
    img = st.img,
    on = 1,
    ox = 0, oz = 0,
    invX = 1 / (st.w * st.texel),
    invZ = 1 / (st.h * st.texel),
    texelU = 1 / st.w,
    texelV = 1 / st.h,
    -- full cover stands SINK_PX world pixels tall; a slope of one cover
    -- unit across one texel is that many pixels over `texel` pixels
    slope = SnowField.SINK_PX / st.texel,
  }
end

-- ------- the collar
--
-- The snow that stands around a walker's legs, drawn as a card in front of
-- the figure once the cover has decided how deep they are. The cut in the
-- sprite card hides the boots; this is what hides them -- without it the
-- figure is simply shorter, which is a figure standing in a hole.
--
-- Twelve wide (the body, not the card, so its outline stays inside the
-- figure's own) and a few pixels tall: it covers the shins and stops. A
-- generated white with a ragged, dithered top, in the same alpha contract
-- every card in this mode obeys (under half is discarded), so the rim
-- dissolves into the snow behind it rather than ending in a line.
SnowField.COLLAR_W = 12
SnowField.COLLAR_ROWS = 4

local collarImg = nil
local collarMeshes = {}

local function collarImage()
  if collarImg ~= nil then return collarImg or nil end
  if not (love and love.image and love.image.newImageData
          and love.graphics and love.graphics.newImage) then
    collarImg = false
    return nil
  end
  local ok, img = pcall(function()
    local w, h = SnowField.COLLAR_W, SnowField.COLLAR_ROWS
    local d = love.image.newImageData(w, h)
    for x = 0, w - 1 do
      local u = (x + 0.5) / w
      local hump = math.sin(u * math.pi)
      -- rows count up from the bottom; the top runs 1.6..3.4 of 4
      local top = 1.6 + hump * 1.4 + ((x * 5) % 3) * 0.25
      for y = 0, h - 1 do
        local yy = h - y
        local a
        if yy <= top then a = 1
        elseif yy <= top + 1 and ((x + y) % 2 == 0) then a = 1
        else a = 0 end
        -- the body is a TONE the shader colours and lights: white, a shade
        -- darker at the very bottom where it meets the boot's shadow
        local v = (yy <= 1) and 0.86 or 1.0
        d:setPixel(x, y, v, v, v, a)
      end
    end
    local i = love.graphics.newImage(d)
    pcall(i.setFilter, i, "nearest", "nearest")
    return i
  end)
  collarImg = (ok and img) or false
  return collarImg or nil
end

-- The card for `sink` hidden pixels, standing on the same feet pivot the
-- figure's card stands on, centred on its cell. Up-facing shade so the
-- scene shader treats it as a surface snow lies on.
function SnowField.collar(sink)
  sink = math.floor(tonumber(sink) or 0)
  if sink <= 0 then return nil, nil end
  local img = collarImage()
  if not img then return nil, nil end
  local m = collarMeshes[sink]
  if m == nil then
    local Voxel3D = V.require("Voxel3D")
    local hgt = 1.5 + sink * 0.5
    local w = SnowField.COLLAR_W
    local x0 = (16 - w) / 2
    local verts = {
      { x0, 0, 0, 0, 1, -1 }, { x0 + w, 0, 0, 1, 1, -1 },
      { x0 + w, hgt, 0, 1, 0, -1 }, { x0, hgt, 0, 0, 0, -1 },
    }
    local indices = {}
    Voxel3D.pushQuad(indices, 0)
    local ok, mesh = pcall(Voxel3D.newMesh, verts, indices)
    m = (ok and mesh) or false
    collarMeshes[sink] = m
  end
  return m or nil, img
end

function SnowField.invalidate()
  collarMeshes = {}
  collarImg = nil
end

return SnowField
