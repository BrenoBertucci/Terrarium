-- The field the world writes into: what the gramado REMEMBERS.
--
-- Everything already in Grass3D is reactive and has no memory past a few
-- seconds. Wind pushes, a boot lays a tuft over, the spring stands it back
-- up, a crumb fades in six seconds, and the meadow is exactly as it was
-- before anybody walked through it. Leave the map and come back and there
-- is no evidence a journey happened here at all.
--
-- This file is the other half. One scalar per 16px CELL -- `wear`, 0..1 --
-- that goes UP when something walks on it and comes back down on the
-- in-game clock over days, not seconds. It rides the save slot, so a route
-- you have crossed forty times looks crossed forty times.
--
-- ------- why a scalar and not a state enum
--
-- The obvious model is `intact / cut / burnt / regrowing` per cell, and it
-- is the wrong one, because every transition in it CHANGES GEOMETRY --
-- and geometry here comes from ChunkMesher. A cell that thins as it gets
-- walked on would remesh a chunk per footstep. BuildBudget spreads that
-- cost over frames; it does not remove it, and on an integrated GPU a
-- remesh per trail is a stutter you can feel.
--
-- A scalar never touches the mesh. It reaches the tuft as ONE MORE VERTEX
-- TEXTURE TAP -- the same contract crushMap already pays at grassDetail 1
-- -- and the tuft thins by collapsing individual blades to zero scale off
-- the per-tuft hash the shader already computes. The only thing in this
-- system that does touch geometry is HM Cut, which is rare, explicit, and
-- already has a working block-swap path (main.lua's replaceBlock route).
--
-- ------- what is in the texel
--
--   R  wear      0..1   how laid/bare this cell is
--   G  shelter   0..1   1 = open sky, 0 = in a building's lee. STATIC.
--   B  cause     0/0.5/1  trample / cut / burn
--
-- Shelter is in here rather than in its own texture because it is free
-- once the wear tap is paid, and because buildings do not move: it is
-- baked once when a map binds and never touched again. That is the whole
-- of "local wind" -- grass calm behind a house, waving in the open -- for
-- zero per-frame cost.
--
-- ------- decay is LAZY, and that is not an optimisation
--
-- Nothing here sweeps the map per frame. Each cell stores its strength
-- AND the clock reading when that strength was written; the current value
-- is computed on read as an exponential from that stamp. So a map with
-- four thousand worn cells costs nothing while you are not looking at
-- them, a save that sat closed for an hour of play comes back correctly
-- faded without replaying an hour, and there is no frame where the decay
-- pass is the spike.
--
-- The clock is DayNight's, not the wall: `DayNight.clock` wraps every
-- cycle so it cannot be a stamp, and this file keeps its own monotonic
-- accumulation of the same seconds instead (see GrassWear.step).

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local GrassWear = {}

-- One texel per overworld cell. 128 texels * 16 world px = 2048 world px,
-- and `map.widthCells` is `def.width * 2` -- no Kanto overworld map is
-- 128 cells on a side, so one field covers any map whole. Same 16 KB
-- footprint as Grass3D's crushMap, which is the budget this was sized to.
GrassWear.RES = 128
GrassWear.CELL = 16
GrassWear.EXTENT = GrassWear.RES * GrassWear.CELL   -- 2048 world px

GrassWear.CAUSE_TRAMPLE = 0
GrassWear.CAUSE_CUT = 1
GrassWear.CAUSE_BURN = 2

-- ------- the saturation ceiling, and why trample stops short of 1
--
-- A cell that only ever gets walked on tops out at 0.75, never 1.0. This
-- is the single line that stops the whole feature turning every route
-- bald: the player walks where the game LETS them walk, so given enough
-- hours the walkable set is exactly the set they have trampled. Capping
-- below 1 means a heavily used path reads as a path and still reads as
-- grass. Only the two DELIBERATE causes -- a swung Cut and a lightning
-- strike -- are allowed all the way to bare.
GrassWear.TRAMPLE_CAP = 0.75

-- Weights, and they are not equal on purpose. The player is the reference;
-- an NPC on a routine is lighter because there are more of them walking
-- more often, and a wild mon is lighter still because it weighs less than
-- a person and because a Rattata should not carve a highway.
GrassWear.W_PLAYER = 1.00
GrassWear.W_NPC = 0.60
GrassWear.W_MON = 0.35

-- Per second of contact, against the weight above.
--
-- The number is derived, not picked. A cell is 16 world px and a walking
-- sprite covers about 60 px/s, so ONE crossing is ~0.27 s of contact. For
-- forty crossings to be what it takes to reach the trample ceiling --
-- which is the pace that makes a path feel earned rather than sprayed on
-- -- a crossing may add at most 0.75/40 = 0.019, so the rate is
-- 0.019/0.27. The first version of this was 0.55, which saturated a cell
-- in FIVE crossings and turned a single lap of Route 1 into a bald route.
GrassWear.GAIN = 0.07

-- Half-lives, in the same seconds DayNight.clock counts. One in-game day
-- is DayNight.CYCLE of them.
GrassWear.HALF_TRAMPLE = 2400.0   -- ~2 in-game days
GrassWear.HALF_CUT = 2400.0       -- cut regrows on the same clock as a path
GrassWear.HALF_BURN = 8400.0      -- ~7 days: a lightning scar outlives the run's chapter

-- Below this a cell is indistinguishable from untouched and is dropped
-- from the sparse table entirely (and from the save).
GrassWear.KEEP = 0.012

-- Cells pruned per step. Bounded so a map with thousands of faded cells
-- cleans itself over seconds instead of in one frame.
GrassWear.PRUNE_BUDGET = 24

-- Texels re-uploaded per step. The image is only ever partially dirty --
-- a walker touches one cell at a time -- so a bounded flush keeps the
-- setPixel loop off the frame graph even when a seed pass dirties hundreds.
GrassWear.UPLOAD_BUDGET = 96

-- ------- per-map state
--
-- Keyed by whatever the engine calls the map, because wear is a fact about
-- a PLACE. Each entry:
--   s[idx]  strength as written        t[idx]  clock reading when written
--   c[idx]  cause                      sh[idx] baked shelter (nil = open)
--   dirty   idx -> true, texels whose pixel no longer matches s/sh
--   live    idx -> true, the sparse set (for prune and for save)
local maps = {}
local bound = nil          -- the state entry for the map being drawn
local boundKey = nil
local boundMap = nil       -- the engine map object, for isGrassCell

-- Monotonic in-game seconds. NOT DayNight.clock, which wraps.
local age = 0.0

local mapIdata, mapImg = nil, nil    -- nil untried, false unavailable
local pruneCursor = nil

-- Which texels of the ImageData are currently NOT the neutral value. The
-- image outlives the map binding, so this is the only way a cell that was
-- worn on the last map gets cleared when the next map has nothing there --
-- without it, walking from Route 1 into Viridian carries Route 1's paths
-- over as phantom wear on whatever cell happens to share the index.
local painted = {}

-- Probe override for the shelter bake (GrassWear.forceShelter). Declared
-- here rather than beside its setter because `flush` reads it, and a local
-- declared after flush would be a different, invisible variable.
local shelterForce = nil

-- The one place shelter is read. Both consumers -- the texel painter and
-- the probe's shelterAt -- come through here so the override cannot apply
-- to one and not the other.
local function shelterOf(st, idx)
  if shelterForce then return shelterForce end
  return (st.sh and st.sh[idx]) or 1
end

-- How much CANOPY stands over this cell, 0 = open sky, 1 = deep under a
-- crown. Rides the texel's fourth channel, which was a constant 1 and is
-- now the one number in this field that is about the SKY rather than the
-- wind. See the note on the texel layout for why it is not folded into
-- shelter.
local function canopyOf(st, idx)
  return (st.cv and st.cv[idx]) or 0
end

local function halfFor(cause)
  if cause == GrassWear.CAUSE_BURN then return GrassWear.HALF_BURN end
  if cause == GrassWear.CAUSE_CUT then return GrassWear.HALF_CUT end
  return GrassWear.HALF_TRAMPLE
end

local LN2 = 0.6931471805599453

-- ------- the two readings of a cell, and why they must be two
--
-- `rawAt` is the true exponential. `decayed` is that value with anything
-- under KEEP reported as nothing at all, which is what every CONSUMER
-- wants: a cell at 0.004 is untouched grass as far as the shader, the
-- ground decal and a probe are concerned.
--
-- The accumulator must NOT use the clamped one, and the first cut of this
-- file did. A frame of walking contact adds about 0.001, so every single
-- frame read its own previous value back as zero, added one frame, and
-- stored that -- the cell sat at one frame's worth forever and no amount
-- of walking ever wore anything. Four hundred crossings measured 0.0000.
-- The clamp is a presentation rule; accumulation is arithmetic, and they
-- do not get to share a function.
local function rawAt(st, idx)
  local s = st.s[idx]
  if not s then return 0 end
  local dt = age - (st.t[idx] or age)
  if dt <= 0 then return s end
  return s * math.exp(-LN2 * dt / halfFor(st.c[idx]))
end

local function decayed(st, idx)
  local v = rawAt(st, idx)
  if v < GrassWear.KEEP then return 0 end
  return v
end

local function entry(key)
  local st = maps[key]
  if not st then
    st = { s = {}, t = {}, c = {}, sh = nil, dirty = {}, live = {}, n = 0 }
    maps[key] = st
  end
  return st
end

local function idxOf(cx, cy)
  if cx < 0 or cy < 0 or cx >= GrassWear.RES or cy >= GrassWear.RES then
    return nil
  end
  return cy * GrassWear.RES + cx
end

-- ------- BUCKETS: the seam the ground decal hangs on
--
-- The tuft shader reads a continuous wear value straight off a texel, but
-- the bare-earth decal underneath it cannot: GroundFX builds a MESH of
-- quads per chunk and caches it, so a continuously-growing patch would
-- remesh a chunk every time anybody took a step -- the exact cost this
-- whole design exists to avoid.
--
-- So the decal sees wear QUANTISED to a few steps, and GroundFX keeps one
-- cached mesh per step (bare1..bareN, the same trick its puddles already
-- use to grow through three sizes). A chunk is rebuilt only when a cell
-- actually CROSSES a step, which at forty crossings to fill the range is
-- rare -- and never at all once a path has settled.
GrassWear.BUCKETS = 3
-- Below this a cell gets no decal at all. One crossing is worth 0.019, so
-- this is "more than a few people have come this way".
GrassWear.BARE_MIN = 0.10

-- 0 = no decal, 1..BUCKETS = which step's mesh this cell belongs in.
function GrassWear.bucketOf(v)
  v = tonumber(v) or 0
  if v < GrassWear.BARE_MIN then return 0 end
  local span = (1.0 - GrassWear.BARE_MIN) / GrassWear.BUCKETS
  local k = math.floor((v - GrassWear.BARE_MIN) / span) + 1
  if k < 1 then return 1 end
  if k > GrassWear.BUCKETS then return GrassWear.BUCKETS end
  return k
end

-- Cells whose bucket changed since anybody last asked. A queue rather than
-- a callback: GroundFX drains it on its own update, so neither module needs
-- to know when the other runs, and a burst of writes in one frame costs one
-- invalidation per cell rather than one per write.
local bucketQueue = {}
local bucketSeen = {}    -- idx -> the bucket this cell was last known to be in

local function noteBucket(st, idx, cx, cy)
  local b = GrassWear.bucketOf(decayed(st, idx))
  if bucketSeen[idx] == b then return end
  bucketSeen[idx] = b
  bucketQueue[#bucketQueue + 1] = cx
  bucketQueue[#bucketQueue + 1] = cy
end

-- Flat { cx, cy, cx, cy, ... } of cells whose decal is stale. Emptied by
-- the asking.
function GrassWear.takeBucketChanges()
  if #bucketQueue == 0 then return nil end
  local out = bucketQueue
  bucketQueue = {}
  return out
end

-- `bucketSeen` is keyed by texel index, and a texel index means a different
-- place on a different map -- the same trap `painted` has. Anything that
-- swaps or wipes the field has to forget it, or a cell that was bucket 2 on
-- Route 1 would suppress the first change of whatever cell shares its index
-- on the next map and that path would never get its decal.
local function forgetBuckets()
  bucketSeen = {}
  bucketQueue = {}
end

-- ------- writing

-- Add wear to the cell containing world (wx, wz). `weight` is one of the
-- W_* constants times however long the walker was in contact; `cause`
-- picks the ceiling and the half-life.
function GrassWear.add(wx, wz, weight, cause)
  local st = bound
  if not st then return end
  local cx = math.floor((tonumber(wx) or 0) / GrassWear.CELL)
  local cy = math.floor((tonumber(wz) or 0) / GrassWear.CELL)
  local idx = idxOf(cx, cy)
  if not idx then return end
  -- Wear is a fact about GRASS. A cell of road or floor has nothing to
  -- lay down, and writing there would put desire paths on pavement.
  if boundMap and boundMap.isGrassCell then
    local ok, isGrass = pcall(boundMap.isGrassCell, boundMap, cx, cy)
    if not (ok and isGrass) then return end
  end
  cause = cause or GrassWear.CAUSE_TRAMPLE
  local cap = (cause == GrassWear.CAUSE_TRAMPLE)
              and GrassWear.TRAMPLE_CAP or 1.0
  local v = rawAt(st, idx)
  -- A cause that is already deeper than this one keeps its own cause: a
  -- footprint across a lightning scar must not downgrade the scar to a
  -- path, or the ground decal would flip from charred to dirt under it.
  local was = st.c[idx]
  local keepCause = was
  if not was or halfFor(cause) >= halfFor(was) or v <= 0 then
    keepCause = cause
  end
  v = v + (tonumber(weight) or 0) * GrassWear.GAIN
  -- The cap applies to what THIS cause may reach, never downward: a cell
  -- at 1.0 from a burn is not pulled to 0.75 by somebody walking over it.
  local ceiling = cap
  if keepCause ~= cause then ceiling = 1.0 end
  if v > ceiling then v = ceiling end
  if st.s[idx] == nil then
    st.live[idx] = true
    st.n = st.n + 1
  end
  st.s[idx] = v
  st.t[idx] = age
  st.c[idx] = keepCause
  st.dirty[idx] = true
  noteBucket(st, idx, cx, cy)
end

-- A whole cell at once, at a fixed strength: what Cut and a lightning
-- strike use. No accumulation and no gain -- these are events, not
-- contact.
function GrassWear.mark(cx, cy, strength, cause)
  local st = bound
  if not st then return end
  local idx = idxOf(math.floor(cx or 0), math.floor(cy or 0))
  if not idx then return end
  if boundMap and boundMap.isGrassCell then
    local ok, isGrass = pcall(boundMap.isGrassCell, boundMap, cx, cy)
    if not (ok and isGrass) then return end
  end
  local v = tonumber(strength) or 1.0
  if v > 1 then v = 1 elseif v < 0 then v = 0 end
  if rawAt(st, idx) > v and halfFor(st.c[idx]) > halfFor(cause) then
    return
  end
  if st.s[idx] == nil then
    st.live[idx] = true
    st.n = st.n + 1
  end
  st.s[idx] = v
  st.t[idx] = age
  st.c[idx] = cause or GrassWear.CAUSE_TRAMPLE
  st.dirty[idx] = true
  noteBucket(st, idx, math.floor(cx), math.floor(cy))
end

-- ------- reading

-- Current wear at a world position, 0 when there is none. This is what
-- GroundFX asks to decide whether to lay bare earth, and what a probe
-- measures.
function GrassWear.at(wx, wz)
  local st = bound
  if not st then return 0, GrassWear.CAUSE_TRAMPLE end
  local cx = math.floor((tonumber(wx) or 0) / GrassWear.CELL)
  local cy = math.floor((tonumber(wz) or 0) / GrassWear.CELL)
  local idx = idxOf(cx, cy)
  if not idx then return 0, GrassWear.CAUSE_TRAMPLE end
  return decayed(st, idx), st.c[idx] or GrassWear.CAUSE_TRAMPLE
end

function GrassWear.atCell(cx, cy)
  local st = bound
  if not st then return 0, GrassWear.CAUSE_TRAMPLE end
  local idx = idxOf(math.floor(cx or 0), math.floor(cy or 0))
  if not idx then return 0, GrassWear.CAUSE_TRAMPLE end
  return decayed(st, idx), st.c[idx] or GrassWear.CAUSE_TRAMPLE
end

-- A cut cell has no tall grass standing in it, so it has no encounter.
-- This is the ONE place wear touches the rules, and it is deliberate: a
-- swung Cut is something the player did on purpose and can see the result
-- of. Accumulated trample never reaches here -- it is cosmetic by
-- decision, because a hidden encounter-rate drift the player cannot read
-- is noise dressed as depth.
function GrassWear.isCut(cx, cy)
  local st = bound
  if not st then return false end
  local idx = idxOf(math.floor(cx or 0), math.floor(cy or 0))
  if not idx then return false end
  if st.c[idx] ~= GrassWear.CAUSE_CUT then return false end
  return decayed(st, idx) > 0.5
end

-- How many cells this map currently remembers. The long-run probe's first
-- metric.
function GrassWear.count()
  local st = bound
  if not st then return 0 end
  local n = 0
  for idx in pairs(st.live) do
    if decayed(st, idx) > 0.1 then n = n + 1 end
  end
  return n
end

-- Concentration: the share of all wear sitting in the top `frac` of
-- cells. The highway detector -- see the pathfinding bias in Roamer. A
-- healthy meadow spreads; a collapsed one puts everything in one road.
function GrassWear.concentration(frac)
  local st = bound
  if not st then return 0 end
  local vals = {}
  local total = 0
  for idx in pairs(st.live) do
    local v = decayed(st, idx)
    if v > 0 then
      vals[#vals + 1] = v
      total = total + v
    end
  end
  if total <= 0 or #vals == 0 then return 0 end
  table.sort(vals, function(a, b) return a > b end)
  local take = math.max(1, math.floor(#vals * (tonumber(frac) or 0.05)))
  local top = 0
  for i = 1, take do top = top + vals[i] end
  return top / total
end

function GrassWear.clockAge()
  return age
end

-- ------- shelter (static, baked once per map)
--
-- 1 = open sky, 0 = fully in something's lee. The shader multiplies the
-- wind amplitude by this, so the meadow behind a house goes calm and the
-- boundary of the calm moves with nothing -- it is the building's shape,
-- and buildings do not move. That is the entire cost of "local wind": a
-- bake, and a channel of a texel that was already being fetched.
--
-- TWO THINGS SHELTER A CELL AND THEY ARE NOT THE SAME NUMBER -- the canopy
-- rides the ALPHA channel, not this one, and that separation is the whole
-- design note.
--
-- Folding them together is the obvious move and it is wrong. This channel
-- is a WIND lee: it is baked around every unwalkable cell within three
-- cells, which is most of the ground next to any hedge, wall or boulder on
-- a route. Rain still falls behind a wall. Sharing one number would have
-- meant the puddles disappearing from every cell within three of anything
-- solid the first time the ground consulted it, which is not a canopy
-- feature, it is a drought.
--
-- What they DO share is the texel, and that is what the sharing was for:
-- alpha was a constant 1, already fetched and already uploaded, so the
-- cover costs no second field, no second upload and no second tap.
GrassWear.SHELTER_REACH = 3     -- cells downwind a wall keeps calming
GrassWear.SHELTER_MIN = 0.30    -- deepest calm directly behind a wall

local function bakeShelter(st, map)
  if st.sh then return end
  local sh = {}
  st.sh = sh
  if not (map and map.widthCells and map.heightCells) then return end
  local blocked = nil
  if map.isWalkableCell then
    blocked = function(cx, cy)
      if map.inBounds and not map:inBounds(cx, cy) then return false end
      local ok, walk = pcall(map.isWalkableCell, map, cx, cy)
      -- Unwalkable and not water: a wall, a tree, a boulder. Those are
      -- the things a breeze goes around rather than through.
      if not ok then return false end
      if walk then return false end
      if map.isWaterCell then
        local okw, wet = pcall(map.isWaterCell, map, cx, cy)
        if okw and wet then return false end
      end
      return true
    end
  end
  if not blocked then return end
  local W = math.min(map.widthCells, GrassWear.RES)
  local H = math.min(map.heightCells, GrassWear.RES)
  for cy = 0, H - 1 do
    for cx = 0, W - 1 do
      if blocked(cx, cy) then
        -- Calm spreads in a small disc rather than along one bearing.
        -- The wind direction turns with the weather; the bake cannot, so
        -- an omnidirectional lee is the honest approximation -- and at
        -- three cells of reach it reads as shelter either way.
        local R = GrassWear.SHELTER_REACH
        for dy = -R, R do
          for dx = -R, R do
            local d = math.sqrt(dx * dx + dy * dy)
            if d <= R then
              local i = idxOf(cx + dx, cy + dy)
              if i then
                local calm = GrassWear.SHELTER_MIN
                             + (1 - GrassWear.SHELTER_MIN) * (d / R)
                if calm < (sh[i] or 1) then
                  sh[i] = calm
                  st.dirty[i] = true
                end
              end
            end
          end
        end
      end
    end
  end

  -- ------- and then the canopies, into their OWN channel
  --
  -- Authored trees stand on cells the player WALKS OVER (the round-tree
  -- sites are the shrubbery, r=8, one cell each), so the walkability test
  -- above cannot see them: to that loop a wood is open ground. That is the
  -- whole reason the canopy needs a pass of its own rather than a wider
  -- reach on the existing one.
  --
  -- Trees3D owns where the crowns actually landed -- the jitter and the
  -- per-site scale are its arithmetic, and asking it is what keeps the
  -- cover under the tree that casts it. Guarded at every step: no bake, no
  -- forest, no Trees3D at all, and this is a no-op that leaves a map with
  -- no authored trees reading exactly as it did before.
  local cv = {}
  st.cv = cv
  local okT, Trees3D = pcall(V.require, "Trees3D")
  if okT and Trees3D and Trees3D.eachCanopyCell then
    pcall(Trees3D.eachCanopyCell, map, function(cx, cy, cover)
      local i = idxOf(cx, cy)
      if not i then return end
      if cover > 1 then cover = 1 end
      -- Crowns that overlap take the DEEPEST rather than adding up: two
      -- canopies over one cell is not twice the shade, it is the same sky
      -- blocked twice. Summing put a solid 1.0 across the middle of every
      -- wood, which is a roof, not a canopy.
      if cover > (cv[i] or 0) then
        cv[i] = cover
        st.dirty[i] = true
      end
    end)
  end
end

-- Shelter never goes out on the public read path -- the shader gets it
-- through the texel's green channel and nothing on the CPU needs it. This
-- exists so a probe can measure the bake, which is otherwise invisible
-- until it is wrong on screen.
function GrassWear.shelterAt(cx, cy)
  local st = bound
  if not st then return 1 end
  local idx = idxOf(math.floor(cx or 0), math.floor(cy or 0))
  if not idx then return 1 end
  return shelterOf(st, idx)
end

-- How much canopy stands over this cell: 0 = open sky, 1 = deep under a
-- crown. Unlike shelter this one DOES go out on the public read path --
-- GroundFX decides where puddles and drifts may lie on the CPU, at chunk
-- build time, and needs the same answer the shader gets from alpha.
--
-- Safe before any bake: an unbound map, a map with no authored trees, or a
-- run with no Trees3D all read 0, which is open sky and the behaviour
-- everything had before this existed.
function GrassWear.canopyAt(cx, cy)
  local st = bound
  if not st then return 0 end
  local idx = idxOf(math.floor(cx or 0), math.floor(cy or 0))
  if not idx then return 0 end
  return canopyOf(st, idx)
end

-- ------- binding a map

function GrassWear.bind(map, key)
  key = key or (map and (map.id or map.name)) or "?"
  if boundKey ~= key then
    boundKey = key
    bound = entry(key)
    -- Every texel the previous map dirtied is wrong for this one, and so
    -- is every texel this one wants. Both sets go in: repainting a stale
    -- texel writes decayed()=0 and shelter=1 through the same paint()
    -- path, which IS the neutral value, so clearing needs no second code
    -- path -- only the knowledge of which texels to revisit.
    for idx in pairs(painted) do bound.dirty[idx] = true end
    for idx in pairs(bound.live) do bound.dirty[idx] = true end
    if bound.sh then
      for idx in pairs(bound.sh) do bound.dirty[idx] = true end
    end
    -- and the canopy, for the same reason and it is not the same set: a
    -- crown covers cells no wall shelters, so a map returned to would come
    -- back with its wood's alpha still holding the PREVIOUS map's texels.
    if bound.cv then
      for idx in pairs(bound.cv) do bound.dirty[idx] = true end
    end
    pruneCursor = nil
    forgetBuckets()
    boundMap = map
    bakeShelter(bound, map)
    flush(true)
    -- and every cell this map already remembers needs its decal placed:
    -- forgetBuckets just wiped the record of what was drawn, so re-noting
    -- them is what puts this map's existing paths back on the ground.
    for idx in pairs(bound.live) do
      noteBucket(bound, idx, idx % GrassWear.RES,
                 math.floor(idx / GrassWear.RES))
    end
    return
  end
  boundMap = map
  bakeShelter(bound, map)
end

function GrassWear.boundKey()
  return boundKey
end

-- ------- the image
--
-- ImageData + Image, not a render target: a canvas switch on the target
-- integrated GPU is the cost this whole design is written to avoid. Same
-- contract Grass3D's crushMap and Water's waterField already pay.

-- Neutral texel: no wear, FULLY OPEN to the wind, trample cause. The
-- green channel matters -- a blank field of zeroes would multiply the
-- wind amplitude by nothing and stop the meadow dead on any driver that
-- refused the image.
local function paint(idx, wear, shelter, cause, canopy)
  local res = GrassWear.RES
  local x, z = idx % res, math.floor(idx / res)
  -- ALPHA IS THE CANOPY. It was a constant 1 -- a channel already being
  -- fetched, already uploaded, and carrying nothing -- so the cover under
  -- a crown costs no second field and no second tap. Written as 1 MINUS
  -- the cover so the neutral value stays 1 exactly like the other
  -- channels' neutrals, and a driver that refuses the image degrades to
  -- "open sky everywhere" rather than to "the whole map is under a tree".
  pcall(mapIdata.setPixel, mapIdata, x, z,
        wear, shelter, (cause or 0) * 0.5, 1 - (canopy or 0))
  -- Neutral is wear 0 AND open sky. A sheltered cell with no wear is
  -- still non-neutral, so it has to stay tracked or the shelter bake
  -- would leak across a map change.
  if wear <= 0 and shelter >= 1 and (canopy or 0) <= 0 then
    painted[idx] = nil
  else
    painted[idx] = true
  end
end

local function ensureImage()
  if mapIdata == false then return false end
  if mapIdata == nil then
    if not (love and love.image and love.image.newImageData) then
      mapIdata = false
      return false
    end
    local ok, d = pcall(love.image.newImageData,
                        GrassWear.RES, GrassWear.RES)
    if not (ok and d) then
      mapIdata = false
      return false
    end
    -- Whole field starts neutral: open sky, no wear.
    for z = 0, GrassWear.RES - 1 do
      for x = 0, GrassWear.RES - 1 do
        pcall(d.setPixel, d, x, z, 0, 1, 0, 1)
      end
    end
    mapIdata = d
  end
  return true
end

local function flush(all)
  local st = bound
  if not st then return end
  if not next(st.dirty) then return end
  if not ensureImage() then return end
  if mapImg == false then return end
  -- A map change dirties every stale texel at once, and a budgeted flush
  -- would leave the previous route's paths visible on this one for the
  -- second it takes to drain. That flush is unbounded on purpose: it
  -- happens during a map transition, which is already stalling on the
  -- chunk build, and a phantom path is a bug where a long frame is not.
  local budget = all and math.huge or GrassWear.UPLOAD_BUDGET
  local done = {}
  for idx in pairs(st.dirty) do
    if budget <= 0 then break end
    paint(idx, decayed(st, idx), shelterOf(st, idx), st.c[idx],
          canopyOf(st, idx))
    done[#done + 1] = idx
    budget = budget - 1
  end
  for i = 1, #done do st.dirty[done[i]] = nil end
  if mapImg == nil then
    local ok, img = pcall(love.graphics.newImage, mapIdata)
    if not (ok and img) then
      mapImg = false
      return
    end
    -- linear so the cell grid does not read as 16px squares on the tufts
    pcall(img.setFilter, img, "linear", "linear")
    pcall(img.setWrap, img, "clamp", "clamp")
    mapImg = img
    return
  end
  if mapImg.replacePixels then
    pcall(mapImg.replacePixels, mapImg, mapIdata)
  end
end

-- ------- the per-frame tick
--
-- Three bounded jobs and nothing else: advance the clock, repaint the
-- texels that changed, and retire a few cells that have faded out. No
-- sweep, no full-map pass, no allocation.
function GrassWear.step(dt)
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.5 then dt = 0.5 end
  age = age + dt
  local st = bound
  if not st then return end

  -- A rolling revisit of the live set, because a DECAYING cell is never
  -- marked dirty by anything -- nothing writes to it, it just gets quieter
  -- -- so this walk is the only thing that carries its texel down with it
  -- and eventually retires it.
  --
  -- The walk gathers first and mutates after. Removing a key from the
  -- table being walked makes the next `next(t, k)` undefined, and the
  -- version of this that deleted in place could only ever retire one cell
  -- per step because it had to abandon the cursor each time.
  local retire = nil
  local n = 0
  local k = pruneCursor
  while n < GrassWear.PRUNE_BUDGET do
    local idx = next(st.live, k)
    if idx == nil then
      k = nil
      break
    end
    k = idx
    if rawAt(st, idx) <= GrassWear.KEEP then
      retire = retire or {}
      retire[#retire + 1] = idx
    end
    st.dirty[idx] = true
    -- Decay lowers a cell's bucket too, and nothing WRITES to a fading
    -- cell -- so this walk is the only place a shrinking path gets noticed
    -- by the decal. It is a rolling visit, so a bucket coming DOWN is seen
    -- within a sweep of the live set rather than the instant it happens;
    -- over a two-day half-life that lag is invisible.
    noteBucket(st, idx, idx % GrassWear.RES,
               math.floor(idx / GrassWear.RES))
    n = n + 1
  end
  pruneCursor = k
  if retire then
    for i = 1, #retire do
      local idx = retire[i]
      st.s[idx], st.t[idx], st.c[idx] = nil, nil, nil
      st.live[idx] = nil
      st.n = st.n - 1
      st.dirty[idx] = true
    end
    -- the cursor may have pointed at something just removed
    pruneCursor = nil
  end

  flush()
end

-- Drain the whole dirty set in one go, whatever it costs.
--
-- The per-step flush is BUDGETED (UPLOAD_BUDGET texels a frame) because in
-- play the field is only ever a few texels dirty -- a walker touches one
-- cell at a time. Anything that dirties the field WHOLESALE breaks that
-- assumption, and the failure is silent and confusing: the field goes to
-- its new value in patches over the next couple of hundred frames, so a
-- probe that set a value and shot two frames later measured a patchwork
-- and read it as noise. (Two questions of grass_wear_shot failed exactly
-- this way before this existed.) Every wholesale writer calls this.
function GrassWear.flushAll()
  flush(true)
end

-- What VoxelScene hands to Voxel3D. `origin` is the map's world offset --
-- zero for the map underfoot, the neighbour's own offset for a neighbour
-- map, so each map samples ITS OWN field and the seam at a map boundary
-- carries wear on both sides.
function GrassWear.state(ox, oz)
  if not mapImg or mapImg == false then return nil end
  return {
    img = mapImg,
    on = 1,
    ox = tonumber(ox) or 0,
    oz = tonumber(oz) or 0,
    inv = 1 / GrassWear.EXTENT,
  }
end

-- ------- persistence
--
-- Flat numeric array per map, four numbers a cell: idx, quantised
-- strength AS WRITTEN, age BEHIND now, cause. Storing the age as a delta
-- rather than an absolute is what lets `age` restart at zero on load
-- without every cell reading as freshly written.
--
-- The strength is the one that was WRITTEN, not the one showing now, and
-- that distinction was a bug the first time. Writing the faded value and
-- the age behind it stores the same decay twice: the loader then fades an
-- already-faded number over the same interval again, and a cell at 0.141
-- came back as 0.099 -- every save quietly mowed the meadow by 30%.
GrassWear.SAVE_KEY = "grassWear"

function GrassWear.serialize()
  local out = {}
  for key, st in pairs(maps) do
    local flat = {}
    for idx in pairs(st.live) do
      -- what it reads as NOW decides whether it is worth keeping; what it
      -- was WRITTEN as is what gets stored, with the interval alongside
      if decayed(st, idx) > 0 then
        flat[#flat + 1] = idx
        flat[#flat + 1] = math.floor((st.s[idx] or 0) * 255 + 0.5)
        flat[#flat + 1] = math.floor(age - (st.t[idx] or age))
        flat[#flat + 1] = st.c[idx] or 0
      end
    end
    if #flat > 0 then out[key] = flat end
  end
  return out
end

function GrassWear.deserialize(blob)
  maps = {}
  bound, boundKey, boundMap = nil, nil, nil
  age = 0
  forgetBuckets()
  if type(blob) ~= "table" then return end
  for key, flat in pairs(blob) do
    if type(flat) == "table" then
      local st = entry(key)
      local i = 1
      while i + 3 <= #flat do
        local idx = tonumber(flat[i])
        local q = tonumber(flat[i + 1])
        local back = tonumber(flat[i + 2]) or 0
        local cause = tonumber(flat[i + 3]) or 0
        if idx and q and q > 0 then
          st.s[idx] = q / 255
          -- negative stamp = written `back` seconds ago, which is exactly
          -- what decayed() needs to reproduce the faded value
          st.t[idx] = -back
          st.c[idx] = cause
          st.live[idx] = true
          st.dirty[idx] = true
          st.n = st.n + 1
        end
        i = i + 4
      end
    end
  end
end

function GrassWear.store()
  local saveApi = V.mod and V.mod.save
  if not (saveApi and saveApi.set) then return end
  pcall(saveApi.set, saveApi, GrassWear.SAVE_KEY, GrassWear.serialize())
end

function GrassWear.restore()
  local saveApi = V.mod and V.mod.save
  local stored = nil
  if saveApi and saveApi.get then
    local ok, got = pcall(saveApi.get, saveApi, GrassWear.SAVE_KEY)
    if ok then stored = got end
  end
  GrassWear.deserialize(stored)
end

-- ------- test seams

function GrassWear.reset()
  maps = {}
  bound, boundKey, boundMap = nil, nil, nil
  age = 0
  pruneCursor = nil
  forgetBuckets()
  painted = {}
  if mapImg and mapImg ~= false and mapImg.release then
    pcall(mapImg.release, mapImg)
  end
  mapImg, mapIdata = nil, nil
end

-- Headless probes have no love.image; bind still has to work so the
-- long-run and save probes can measure the field without a GPU.
function GrassWear.bindHeadless(key, map)
  boundKey = key or "probe"
  bound = entry(boundKey)
  boundMap = map
  mapIdata = false
  mapImg = false
  bakeShelter(bound, map)
end

function GrassWear.advance(seconds)
  age = age + (tonumber(seconds) or 0)
end

-- ------- seams the screenshot probe needs
--
-- Wear normally arrives one footstep at a time over in-game days, and
-- shelter arrives from a map's buildings. Neither is something a probe can
-- wait for, and a probe that walked for forty crossings to get one A/B
-- frame would be measuring the walk as much as the field. These set the
-- field DIRECTLY so a shot can be taken with a known value in it.

-- Every grass cell in a rectangle of cells, at one strength. `mark`'s own
-- isGrassCell gate still applies, so this cannot paint wear onto a road.
function GrassWear.fillCells(cx0, cy0, cx1, cy1, strength, cause)
  for cy = math.floor(cy0), math.floor(cy1) do
    for cx = math.floor(cx0), math.floor(cx1) do
      GrassWear.mark(cx, cy, strength, cause or GrassWear.CAUSE_TRAMPLE)
    end
  end
end

-- Wipe the bound map's wear without disturbing its shelter bake, so an A/B
-- can return to a true zero between shots.
function GrassWear.clearWear()
  local st = bound
  if not st then return end
  for idx in pairs(st.live) do
    st.s[idx], st.t[idx], st.c[idx] = nil, nil, nil
    st.dirty[idx] = true
    -- queue the decal removal BEFORE forgetting, so the ground goes back
    -- to grass rather than keeping a patch nothing is under any more
    noteBucket(st, idx, idx % GrassWear.RES,
               math.floor(idx / GrassWear.RES))
  end
  st.live = {}
  st.n = 0
  pruneCursor = nil
end

-- Override the shelter bake for the whole field. nil restores the bake.
-- The bake is derived from a map's walls and there is no wall a probe can
-- build, so measuring the shelter path at all needs this.
function GrassWear.forceShelter(v)
  shelterForce = tonumber(v)
  local st = bound
  if not st then return end
  -- every texel's green channel just changed
  for idx in pairs(painted) do st.dirty[idx] = true end
  for idx in pairs(st.live) do st.dirty[idx] = true end
  if st.sh then
    for idx in pairs(st.sh) do st.dirty[idx] = true end
  end
  if shelterForce then
    -- and the cells that were neutral in BOTH channels have to be visited
    -- too, or a forced shelter would only reach cells that happened to be
    -- worn or already sheltered
    for i = 0, GrassWear.RES * GrassWear.RES - 1 do st.dirty[i] = true end
  end
  -- 16384 texels against a 96-a-frame budget is 170 frames of patchwork.
  -- This is a probe seam, so it pays for itself in one long frame instead.
  GrassWear.flushAll()
end

function GrassWear.shelterForced()
  return shelterForce
end

function GrassWear.dropGPU()
  if mapImg and mapImg ~= false and mapImg.release then
    pcall(mapImg.release, mapImg)
  end
  mapImg, mapIdata = nil, nil
  if bound then
    for idx in pairs(bound.live) do bound.dirty[idx] = true end
  end
end

return GrassWear
