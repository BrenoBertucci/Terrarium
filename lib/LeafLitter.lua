-- The leaves lying on one map's ground: where they are, and nothing else.
--
-- LeafFallFX owns the life of a leaf -- torn from a crown, carried down by
-- the air, kicked back up by a boot. What it leaves on the ground lives
-- here, and this file knows nothing about drawing, wind or the game. It is
-- plain arithmetic, which is what lets tests/leaf_litter_offline.lua prove
-- it in lupa without a GPU.
--
-- ------- WHY NOT A LIST OF TABLES
--
-- A route under its trees holds a thousand leaves, and every one of them is
-- the same handful of numbers. As a thousand tables that is a thousand
-- objects for the collector to walk every cycle, for as long as the map is
-- remembered. As one array per field it is a dozen objects, allocated when
-- the store is born and never again: a slot is an index, freeing one is a
-- flag and a push.
--
-- ------- WHERE A LEAF IS, IN O(1)
--
-- The question the game asks every frame is "which leaves are under this
-- boot", once per walker. So each cell keeps a singly linked chain of the
-- slots lying in it (`head` / `nxt`), and a query reads the few cells a
-- boot overlaps instead of every leaf on the map. A cell never holds more
-- than PER_CELL, so unlinking a slot walks at most that far.
--
-- ------- FULL, AND STILL TAKING LEAVES
--
-- When every slot is taken, a new leaf gets the first slot the eviction
-- cursor reaches whose leaf lies FAR from the player: a leaf vanishing ten
-- cells away is a leaf nobody saw go. The cursor sweeps the slots in order,
-- so over a long session the ground turns over roughly oldest-first, which
-- is what keeps a route from filling up once and freezing.
--
-- ------- WHAT THE MESH NEEDS TO HEAR
--
-- A lying leaf never moves, so its quad is written once when it lands and
-- once when it leaves, never per frame. Every change queues its slot, and
-- LeafFallFX drains the queue into the mesh. Past QUEUE_MAX pending changes
-- (a map being seeded, a budget change) the queue stops tracking singles and
-- asks for the whole mesh instead -- one full rewrite beats thousands of
-- single ones.

local LeafLitter = {}

local floor = math.floor

LeafLitter.CELL = 16          -- world px per cell: one step of a walker
LeafLitter.PER_CELL = 6       -- leaves one cell may hold
LeafLitter.QUEUE_MAX = 256    -- pending slot changes before a full rewrite
LeafLitter.EVICT_TRIES = 16   -- slots the cursor examines for a far leaf

local Store = {}
Store.__index = Store

-- `hard` is the most slots this store will ever hold. Every per-slot array
-- is filled to that length here, so none of them grows -- and rehashes --
-- in the middle of play.
function LeafLitter.new(hard)
  hard = math.max(1, floor(tonumber(hard) or 1))
  local s = setmetatable({
    hard = hard,
    cap = hard,
    -- per slot
    x = {}, y = {}, z = {}, rot = {}, frame = {}, born = {},
    cell = {}, nxt = {}, used = {}, isDirty = {},
    free = {}, nfree = 0,
    high = 0,        -- highest slot handed out since the last reset
    count = 0,
    cursor = 0,
    evicted = 0,
    -- per cell
    head = {}, fill = {},
    cols = 0, rows = 0, cells = 0,
    -- the mesh's queue
    dirty = {}, ndirty = 0,
    overflow = true,
  }, Store)
  for i = 1, hard do
    s.x[i], s.y[i], s.z[i], s.rot[i] = 0, 0, 0, 0
    s.frame[i], s.born[i], s.cell[i], s.nxt[i] = 0, 0, 0, 0
    s.used[i], s.isDirty[i] = false, false
    s.free[i] = 0
  end
  for i = 1, LeafLitter.QUEUE_MAX do s.dirty[i] = 0 end
  return s
end

-- Empty the store for a map of cols x rows cells. The cell arrays only ever
-- grow, so a smaller map after a bigger one allocates nothing.
function Store:reset(cols, rows)
  cols = math.max(0, floor(tonumber(cols) or 0))
  rows = math.max(0, floor(tonumber(rows) or 0))
  local cells = cols * rows
  local head, fill = self.head, self.fill
  for c = 1, math.max(cells, self.cells) do
    head[c], fill[c] = 0, 0
  end
  self.cols, self.rows, self.cells = cols, rows, cells
  local used, isDirty, nxt = self.used, self.isDirty, self.nxt
  for i = 1, self.hard do
    used[i], isDirty[i], nxt[i] = false, false, 0
  end
  self.count, self.high, self.nfree, self.cursor = 0, 0, 0, 0
  self.ndirty = 0
  self.overflow = true
end

-- The cell index (1-based) under a world point, or nil off the map.
function Store:cellOf(x, z)
  local cx = floor(x / LeafLitter.CELL)
  local cz = floor(z / LeafLitter.CELL)
  if cx < 0 or cz < 0 or cx >= self.cols or cz >= self.rows then return nil end
  return cz * self.cols + cx + 1
end

function Store:hasRoom(c)
  return self.fill[c] < LeafLitter.PER_CELL
end

function Store:markDirty(slot)
  if self.overflow or self.isDirty[slot] then return end
  local n = self.ndirty
  if n >= LeafLitter.QUEUE_MAX then
    self.overflow = true
    return
  end
  n = n + 1
  self.ndirty = n
  self.dirty[n] = slot
  self.isDirty[slot] = true
end

-- What changed since doneChanges(): `true` when the whole mesh must be
-- rewritten, otherwise false and how many slots wait in self.dirty.
function Store:pendingChanges()
  return self.overflow, self.ndirty
end

function Store:doneChanges()
  local dirty, isDirty = self.dirty, self.isDirty
  for i = 1, self.ndirty do isDirty[dirty[i]] = false end
  self.ndirty = 0
  self.overflow = false
end

local function unlink(self, slot)
  local c = self.cell[slot]
  local nxt = self.nxt
  local prev, cur = 0, self.head[c]
  while cur ~= 0 and cur ~= slot do
    prev, cur = cur, nxt[cur]
  end
  if cur == 0 then return end
  if prev == 0 then
    self.head[c] = nxt[slot]
  else
    nxt[prev] = nxt[slot]
  end
  nxt[slot] = 0
  self.fill[c] = self.fill[c] - 1
end

function Store:remove(slot)
  if not self.used[slot] then return false end
  unlink(self, slot)
  self.used[slot] = false
  self.count = self.count - 1
  self.nfree = self.nfree + 1
  self.free[self.nfree] = slot
  self:markDirty(slot)
  return true
end

-- The slot to empty when the store is full: the first one the cursor
-- reaches whose leaf lies outside keepR of (px, pz), or failing that the
-- first used one it saw -- a full store always takes the leaf.
local function victim(self, px, pz, keepR)
  local cap = self.cap
  local used, lx, lz = self.used, self.x, self.z
  local keep2 = (keepR or 0) * (keepR or 0)
  local fallback = 0
  for _ = 1, LeafLitter.EVICT_TRIES do
    local i = self.cursor % cap + 1
    self.cursor = i
    if used[i] then
      if not px then return i end
      if fallback == 0 then fallback = i end
      local dx, dz = lx[i] - px, lz[i] - pz
      if dx * dx + dz * dz > keep2 then return i end
    end
  end
  return fallback
end

local function allocate(self, px, pz, keepR)
  if self.nfree > 0 then
    local slot = self.free[self.nfree]
    self.nfree = self.nfree - 1
    return slot
  end
  if self.high < self.cap then
    self.high = self.high + 1
    return self.high
  end
  local slot = victim(self, px, pz, keepR)
  if slot == 0 then return nil end
  self:remove(slot)
  self.evicted = self.evicted + 1
  -- remove() pushed it on the free stack; take it straight back
  self.nfree = self.nfree - 1
  return slot
end

-- Lay a leaf at world (x, y, z). nil when the point is off the map, its
-- cell is full, or the store has no slots at all. `born` is the clock the
-- leaf landed at. `px, pz, keepR` are the player and the radius around them
-- an eviction must not empty when it has a choice.
function Store:add(x, y, z, frame, rot, born, px, pz, keepR)
  if self.cap <= 0 then return nil end
  local c = self:cellOf(x, z)
  if not c or self.fill[c] >= LeafLitter.PER_CELL then return nil end
  local slot = allocate(self, px, pz, keepR)
  if not slot then return nil end
  self.x[slot], self.y[slot], self.z[slot] = x, y, z
  self.frame[slot], self.rot[slot], self.born[slot] = frame or 0, rot or 0, born or 0
  self.cell[slot] = c
  self.nxt[slot] = self.head[c]
  self.head[c] = slot
  self.fill[c] = self.fill[c] + 1
  self.used[slot] = true
  self.count = self.count + 1
  self:markDirty(slot)
  return slot
end

-- The live ceiling, which the PFX row moves. Shrinking empties every slot
-- above it and asks for a full rewrite, since the draw range shrank too.
function Store:setCap(cap)
  cap = floor(tonumber(cap) or self.cap)
  if cap < 0 then cap = 0 elseif cap > self.hard then cap = self.hard end
  if cap == self.cap then return end
  if cap < self.high then
    self.overflow = true
    for i = cap + 1, self.high do
      if self.used[i] then self:remove(i) end
    end
    self.high = cap
    local kept = 0
    for k = 1, self.nfree do
      local slot = self.free[k]
      if slot <= cap then
        kept = kept + 1
        self.free[kept] = slot
      end
    end
    self.nfree = kept
  end
  self.cap = cap
  if self.cursor > cap then self.cursor = 0 end
end

-- Every leaf within r of (x, z) that has lain still for at least `rest`
-- seconds by the clock `now`, written into out[1..n]. The caller owns
-- `out`; nothing is removed here.
function Store:collect(x, z, r, now, rest, out)
  local CELL = LeafLitter.CELL
  local cols, rows = self.cols, self.rows
  local c0x, c1x = floor((x - r) / CELL), floor((x + r) / CELL)
  local c0z, c1z = floor((z - r) / CELL), floor((z + r) / CELL)
  if c0x < 0 then c0x = 0 end
  if c0z < 0 then c0z = 0 end
  if c1x >= cols then c1x = cols - 1 end
  if c1z >= rows then c1z = rows - 1 end
  local r2 = r * r
  local head, nxt, lx, lz, born = self.head, self.nxt, self.x, self.z, self.born
  local n = 0
  for cz = c0z, c1z do
    for cx = c0x, c1x do
      local slot = head[cz * cols + cx + 1]
      while slot ~= 0 do
        local dx, dz = lx[slot] - x, lz[slot] - z
        if dx * dx + dz * dz <= r2 and now - born[slot] >= rest then
          n = n + 1
          out[n] = slot
        end
        slot = nxt[slot]
      end
    end
  end
  return n
end

-- The leaf that has lain longest in cell c, or nil when the cell is empty.
function Store:oldestIn(c)
  local born, nxt = self.born, self.nxt
  local best, bestBorn = nil, math.huge
  local slot = self.head[c]
  while slot ~= 0 do
    if born[slot] < bestBorn then best, bestBorn = slot, born[slot] end
    slot = nxt[slot]
  end
  return best
end

-- ------- for probes

-- The most leaves any one cell holds.
function Store:perCellMax()
  local most = 0
  for c = 1, self.cells do
    if self.fill[c] > most then most = self.fill[c] end
  end
  return most
end

-- A fingerprint of where every leaf lies. The sum does not care which slot
-- holds which leaf, so two stores that laid the same leaves in a different
-- order agree -- equal fingerprints are the same ground.
function Store:checksum()
  local sum = 0
  local used, lx, lz, frame = self.used, self.x, self.z, self.frame
  for i = 1, self.high do
    if used[i] then
      sum = (sum + floor(lx[i] * 4) * 7 + floor(lz[i] * 4) * 13
             + frame[i] * 3) % 1000000007
    end
  end
  return sum
end

LeafLitter.Store = Store

return LeafLitter
