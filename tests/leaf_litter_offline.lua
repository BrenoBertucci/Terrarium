-- LeafLitter, proved without a GPU.
--
-- lib/LeafLitter.lua is the part of the leaf system that has to stay right
-- over a whole session: slots handed out and taken back thousands of times,
-- chains unlinked from the middle, a full store evicting while the player
-- stands in it, a budget shrinking under it. None of that shows in a
-- screenshot, and all of it is reproducible arithmetic -- so this drives the
-- store with random traffic and checks every invariant against a brute-force
-- answer.
--
--   run:  python tools/run_leaf_litter_offline.py

local ROOT = ...
ROOT = ROOT or "."

local LeafLitter = assert(loadfile(ROOT .. "/lib/LeafLitter.lua"))()
local CELL, PER_CELL = LeafLitter.CELL, LeafLitter.PER_CELL

local fails, checks = 0, 0
local function check(ok, what, detail)
  checks = checks + 1
  if ok then
    print(("  PASS  %s"):format(what))
  else
    fails = fails + 1
    print(("  FAIL  %s%s"):format(what, detail and ("  -- " .. detail) or ""))
  end
end

-- ------- every invariant, against the store's own arrays
local function integrity(s)
  local chained = {}
  local total = 0
  for c = 1, s.cells do
    local n, guard = 0, 0
    local slot = s.head[c]
    while slot ~= 0 do
      if not s.used[slot] then return false, ("cell %d chains free slot %d"):format(c, slot) end
      if s.cell[slot] ~= c then return false, ("slot %d chained in %d, says %d"):format(slot, c, s.cell[slot]) end
      if chained[slot] then return false, ("slot %d chained twice"):format(slot) end
      if s:cellOf(s.x[slot], s.z[slot]) ~= c then return false, ("slot %d lies outside its cell"):format(slot) end
      chained[slot] = true
      n, total = n + 1, total + 1
      slot = s.nxt[slot]
      guard = guard + 1
      if guard > s.hard then return false, "a chain loops" end
    end
    if n ~= s.fill[c] then return false, ("cell %d fill %d, chain %d"):format(c, s.fill[c], n) end
    if n > PER_CELL then return false, ("cell %d holds %d"):format(c, n) end
  end
  if total ~= s.count then return false, ("chains hold %d, count says %d"):format(total, s.count) end
  local onStack = {}
  for k = 1, s.nfree do
    local slot = s.free[k]
    if s.used[slot] then return false, "the free stack holds a used slot" end
    if onStack[slot] then return false, "the free stack holds a slot twice" end
    if slot > s.high then return false, "a free slot above high" end
    onStack[slot] = true
  end
  for i = 1, s.hard do
    if s.used[i] and not chained[i] then return false, ("used slot %d in no chain"):format(i) end
    if s.used[i] and i > s.high then return false, ("used slot %d above high"):format(i) end
    if i <= s.high and not s.used[i] and not onStack[i] then
      return false, ("slot %d lost: neither used nor free"):format(i)
    end
  end
  if s.high > s.cap then return false, "high above cap" end
  return true
end

local function randomLeaf(s, born)
  local x = math.random() * s.cols * CELL
  local z = math.random() * s.rows * CELL
  return s:add(x, 2, z, math.random(0, 14), math.random() * 6.28, born or 0)
end

math.randomseed(20260910)

print("== 1. a cell holds PER_CELL and no more ==")
do
  local s = LeafLitter.new(64)
  s:reset(12, 10)
  local x0, z0 = 3 * CELL, 4 * CELL
  local placed = 0
  for i = 1, PER_CELL do
    if s:add(x0 + 1 + i, 2, z0 + 3, 3, 0, 0) then placed = placed + 1 end
  end
  check(placed == PER_CELL, ("%d leaves fit in one cell"):format(PER_CELL))
  check(s:add(x0 + 8, 2, z0 + 8, 3, 0, 0) == nil, "the next one in that cell is refused")
  check(s:add(-1, 2, 5, 3, 0, 0) == nil, "a point off the near edge is refused")
  check(s:add(12 * CELL + 1, 2, 5, 3, 0, 0) == nil, "and one past the far edge")
  local ok, why = integrity(s)
  check(ok, "chains intact", why)
end

print("")
print("== 2. unlinking the middle, the head and the tail of a chain ==")
do
  local s = LeafLitter.new(64)
  s:reset(4, 4)
  local slots = {}
  for i = 1, PER_CELL do slots[i] = s:add(20 + i, 2, 20, 0, 0, 0) end
  -- chains are LIFO: the last one added is the head
  check(s:remove(slots[3]), "remove from the middle")
  check(s:remove(slots[PER_CELL]), "remove the head")
  check(s:remove(slots[1]), "remove the tail")
  check(not s:remove(slots[1]), "removing it twice is refused")
  local ok, why = integrity(s)
  check(ok and s.fill[s:cellOf(21, 20)] == PER_CELL - 3, "chain and fill agree", why)
  check(s:add(30, 2, 30, 0, 0, 0) ~= nil and s:add(31, 2, 31, 0, 0, 0) ~= nil,
        "freed room takes new leaves")
  ok, why = integrity(s)
  check(ok and s.high == PER_CELL, "freed slots were reused, high did not climb", why)
end

print("")
print("== 3. collect() finds exactly what a brute force finds ==")
do
  local s = LeafLitter.new(600)
  s:reset(12, 10)
  for _ = 1, 450 do randomLeaf(s, math.random() * 10) end
  local out = {}
  local bad = 0
  for _ = 1, 400 do
    local qx = math.random() * 12 * CELL + math.random(-20, 20)
    local qz = math.random() * 10 * CELL + math.random(-20, 20)
    local r = 2 + math.random() * 28
    local rest = math.random() * 5
    local n = s:collect(qx, qz, r, 10, rest, out)
    local got = {}
    for k = 1, n do got[out[k]] = true end
    local want = 0
    for i = 1, s.high do
      if s.used[i] then
        local dx, dz = s.x[i] - qx, s.z[i] - qz
        local inside = dx * dx + dz * dz <= r * r and 10 - s.born[i] >= rest
        if inside then
          want = want + 1
          if not got[i] then bad = bad + 1 end
        end
      end
    end
    if want ~= n then bad = bad + 1 end
  end
  check(s.count > 300, ("%d leaves laid for the queries"):format(s.count))
  check(bad == 0, "400 random discs, rest times included, zero disagreements",
        bad .. " disagreements")
end

print("")
print("== 4. random traffic keeps every invariant ==")
do
  local s = LeafLitter.new(700)
  s:reset(20, 16)
  local out = {}
  local worst = nil
  for op = 1, 30000 do
    local r = math.random()
    if r < 0.50 then
      randomLeaf(s, op * 0.01)
    elseif r < 0.80 then
      local i = math.random(1, math.max(1, s.high))
      s:remove(i)
    elseif r < 0.95 then
      -- a boot: collect a disc and lift everything in it
      local n = s:collect(math.random() * 320, math.random() * 256, 10,
                          op * 0.01, 0.5, out)
      for k = 1, n do s:remove(out[k]) end
    else
      s:setCap(math.random(60, 700))
    end
    if op % 1000 == 0 then
      local ok, why = integrity(s)
      if not ok then worst = ("op %d: %s"):format(op, why) break end
    end
    if op % 97 == 0 then s:doneChanges() end
  end
  check(worst == nil, "30000 adds, removes, kicks and budget changes", worst)
end

print("")
print("== 5. a full store evicts far from the player ==")
do
  local s = LeafLitter.new(100)
  s:reset(40, 40)
  while s.count < 100 do randomLeaf(s, 0) end
  local px, pz, keep = 8, 8, 80
  local nearBefore = {}
  for i = 1, s.high do
    local dx, dz = s.x[i] - px, s.z[i] - pz
    if dx * dx + dz * dz <= keep * keep then
      nearBefore[#nearBefore + 1] = { slot = i, x = s.x[i], z = s.z[i] }
    end
  end
  local added = 0
  for _ = 1, 60 do
    local x = 200 + math.random() * 400
    local z = 200 + math.random() * 400
    if s:add(x, 2, z, 1, 0, 1, px, pz, keep) then added = added + 1 end
  end
  local survived = 0
  for _, l in ipairs(nearBefore) do
    if s.used[l.slot] and s.x[l.slot] == l.x and s.z[l.slot] == l.z then
      survived = survived + 1
    end
  end
  check(added == 60 and s.count == 100, "a full store still takes every leaf",
        ("added %d, count %d"):format(added, s.count))
  check(#nearBefore > 0 and survived == #nearBefore,
        ("the %d leaves within reach of the player all survived"):format(#nearBefore),
        ("%d of %d"):format(survived, #nearBefore))
  check(s.evicted == 60, "and each new leaf evicted exactly one", "evicted " .. s.evicted)
  -- everything near: the store must still take the leaf rather than refuse
  local t = LeafLitter.new(30)
  t:reset(10, 10)
  while t.count < 30 do randomLeaf(t, 0) end
  check(t:add(70, 2, 70, 0, 0, 0, 80, 80, 1e6) ~= nil,
        "with every leaf near, it evicts anyway")
  local ok, why = integrity(t)
  check(ok and t.count == 30, "and stays consistent", why)
end

print("")
print("== 6. the budget shrinks and grows under a full store ==")
do
  local s = LeafLitter.new(200)
  s:reset(30, 30)
  while s.count < 200 do randomLeaf(s, 0) end
  s:doneChanges()
  s:setCap(70)
  local full = s:pendingChanges()
  local ok, why = integrity(s)
  check(ok and s.count <= 70 and s.high == 70, "shrunk to 70: nothing above it", why)
  check(full, "and the mesh is told to rewrite whole")
  s:setCap(200)
  while s.count < 200 do randomLeaf(s, 0) end
  ok, why = integrity(s)
  check(ok and s.count == 200, "grown back and refilled", why)
end

print("")
print("== 7. the mesh queue ==")
do
  local s = LeafLitter.new(400)
  s:reset(30, 30)
  s:doneChanges()
  local a = {}
  for i = 1, 5 do a[i] = randomLeaf(s, 0) end
  s:remove(a[2])                 -- already queued: must not queue twice
  local full, n = s:pendingChanges()
  local unique, seen = true, {}
  for k = 1, n do
    if seen[s.dirty[k]] then unique = false end
    seen[s.dirty[k]] = true
  end
  check(not full and n == 5 and unique, "five changes, five unique slots",
        ("full %s n %d"):format(tostring(full), n))
  s:doneChanges()
  local clean = true
  for i = 1, s.hard do if s.isDirty[i] then clean = false end end
  check(clean, "done clears every flag")
  for _ = 1, LeafLitter.QUEUE_MAX + 20 do randomLeaf(s, 0) end
  full = s:pendingChanges()
  check(full, "past QUEUE_MAX it asks for a full rewrite")
end

print("")
print("== 8. the fingerprint is the ground, not the slots ==")
do
  local leaves = {}
  for i = 1, 120 do
    leaves[i] = { math.random() * 300, math.random() * 300, math.random(0, 14) }
  end
  local a, b = LeafLitter.new(200), LeafLitter.new(200)
  a:reset(20, 20); b:reset(20, 20)
  for i = 1, #leaves do
    local l = leaves[i]
    a:add(l[1], 2, l[2], l[3], 0, 0)
  end
  for i = #leaves, 1, -1 do
    local l = leaves[i]
    b:add(l[1], 2, l[2], l[3], 0, 0)
  end
  check(a.count == b.count and a:checksum() == b:checksum(),
        "the same leaves laid in reverse order read the same")
  b:remove(b.high)
  check(a:checksum() ~= b:checksum(), "one leaf fewer does not")
end

print("")
print("== 9. reset for a smaller map, then a bigger one ==")
do
  local s = LeafLitter.new(300)
  s:reset(40, 40)
  for _ = 1, 250 do randomLeaf(s, 0) end
  s:reset(5, 5)
  local ok, why = integrity(s)
  check(ok and s.count == 0 and s.high == 0, "a reset empties everything", why)
  for _ = 1, 100 do randomLeaf(s, 0) end
  s:reset(60, 60)
  for _ = 1, 280 do randomLeaf(s, 0) end
  ok, why = integrity(s)
  check(ok and s.count > 250, "a bigger map after it lays and chains cleanly", why)
end

print("")
print("== 10. zero allocation in regime ==")
do
  local s = LeafLitter.new(2000)
  s:reset(40, 40)
  local out = {}
  for i = 1, 64 do out[i] = 0 end
  local function traffic(ops, t0)
    for op = 1, ops do
      local r = math.random()
      local t = t0 + op * 0.01
      if r < 0.55 then
        s:add(math.random() * 640, 2, math.random() * 640, 3, 1.0, t, 320, 320, 96)
      elseif r < 0.80 then
        s:remove(math.random(1, math.max(1, s.high)))
      else
        local n = s:collect(math.random() * 640, math.random() * 640, 10, t, 0.6, out)
        for k = 1, n do s:remove(out[k]) end
      end
      if op % 50 == 0 then s:doneChanges() end
    end
  end
  traffic(40000, 0)                       -- warm every array to its shape
  collectgarbage("collect")
  collectgarbage("stop")
  local k0 = collectgarbage("count")
  traffic(40000, 400)
  local k1 = collectgarbage("count")
  collectgarbage("restart")
  check(k1 - k0 < 1.0, ("40000 ops after warm-up allocate %.3f KB"):format(k1 - k0))
  local ok, why = integrity(s)
  check(ok, "and the store is still consistent", why)
end

print("")
print("== 11. the leaf that has lain longest in a cell ==")
do
  local s = LeafLitter.new(32)
  s:reset(4, 4)
  local a = s:add(20, 2, 20, 0, 0, 5.0)
  local b = s:add(22, 2, 21, 0, 0, 1.5)
  s:add(24, 2, 22, 0, 0, 9.0)
  local cell = s:cellOf(20, 20)
  check(s:oldestIn(cell) == b, "picks the earliest landing, wherever it sits in the chain")
  s:remove(b)
  check(s:oldestIn(cell) == a, "and the next earliest once that one is gone")
  check(s:oldestIn(s:cellOf(60, 60)) == nil, "an empty cell has none")
end

print("")
print(("%d checks, %d failures"):format(checks, fails))
if fails > 0 then os.exit(1) end
