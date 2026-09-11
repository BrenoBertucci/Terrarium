-- LeafFallFX, driven without the game.
--
-- tests/leaf_fall_probe.lua is the proof that leaves fall, lie and scatter
-- on a real route, and it takes minutes a run. This drives the same module
-- over a fake route in lupa in about a second, and asserts the laws the
-- probe can only sample: every leaf that let go is accounted for, a walked
-- path clears without a leaf going missing, a settled ground writes no
-- vertex, and a frame in regime allocates nothing.
--
--   run:  python tools/run_leaf_fall_offline.py

local ROOT = ...
ROOT = ROOT or "."
local floor = math.floor

math.randomseed(1234)

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

-- ------- the fake route, 24 x 20 cells
--   row 6   a tree line, cx 4..19: cylinder crowns, not walkable
--   row 12  tall grass, cx 2..8
--   rest    open, flat, walkable ground
local W, H = 24, 20
local function kind(cx, cz)
  if cz == 6 and cx >= 4 and cx <= 19 then return "tree" end
  if cz == 12 and cx >= 2 and cx <= 8 then return "grass" end
  return "ground"
end
local SHAPE = {
  tree = { art = "cylinder", h = 16 },
  grass = { art = "grass", h = 0 },
  ground = { h = 0 },
}
local ROUND = { cylinder = true, canopy = true, billboard = true, post = true,
                grass = true, flower = true }

local function newMap(id)
  local m = { id = id, def = {}, widthCells = W, heightCells = H }
  function m:tileAt(tx, ty) return floor(ty / 2) * 1000 + floor(tx / 2) end
  function m:isWalkableCell(cx, cz) return kind(cx, cz) ~= "tree" end
  function m:inBounds(cx, cz) return cx >= 0 and cz >= 0 and cx < W and cz < H end
  return m
end

local TileShape = {}
function TileShape.forMap() return {} end
function TileShape.at(_, _, tile) return SHAPE[kind(tile % 1000, floor(tile / 1000))] end

local VoxelScene = {}
function VoxelScene.flatTop(_, cx, cz) return not ROUND[SHAPE[kind(cx, cz)].art or ""] end
function VoxelScene.groundAt(_, cx, cz) return SHAPE[kind(cx, cz)].h end

local TREES = {}
for cx = 4, 19 do TREES[#TREES + 1] = { x = cx * 16 + 8, z = 6 * 16 + 8, h = 16 } end
local VegFX = {}
function VegFX.grows() return true end
function VegFX.sitesFor(map)
  return { mapId = map.id, trees = TREES, grass = {}, flowers = {} }
end

local env = { amount = 0, cover = 0, wet = 0, mul = 1 }
local Wind = { DIR = { 1, 0 }, DIR0 = { 0.94, 0.34 } }
function Wind.amount() return env.amount end
function Wind.flowAt() return 0, 0, 1 end
function Wind.turbAt() return 0, 0 end

local img = { getDimensions = function() return 240, 16 end }
local WindFX = {
  SPEED = 28, TURB = 0.5,
  SHEETS = { leaf = { img = "leaf", fw = 16, fh = 16, cols = 15, n = 5,
                      fps = 10, hw = 4.5 } },
  KINDS = { leaf = {
    speed = function(p, t) return 0.78 + 0.20 * math.sin(t * 3.1 + (p.seed or 0)) end,
    bob = 9.5, mass = 0.12, area = 2.20 } },
}
local pack = { leaf = img }          -- cached, as the real pack is
function WindFX.pack() return pack end

local GroundFX = {}
function GroundFX.cover() return env.cover end
function GroundFX.wetness() return env.wet end
local Quality = {}
function Quality.particles() return env.mul end

local Voxel3D = { FORMAT = {} }
function Voxel3D.pushQuad(map, n)
  local b = n * 4
  map[#map + 1] = b + 1
  map[#map + 1] = b + 2
  map[#map + 1] = b + 3
  map[#map + 1] = b + 1
  map[#map + 1] = b + 3
  map[#map + 1] = b + 4
end
function Voxel3D.drawParticles(mesh, _, batches)
  mesh.draws = mesh.draws + 1
  return #batches
end
local VoxelState = { angle = 0.9 }

-- ------- love, as little of it as the module touches
local meshes = {}
local function newMesh(_, vertices)
  local m = { vertices = vertices, writes = 0, draws = 0, v = {} }
  for i = 1, vertices do m.v[i] = { 0, 0, 0, 0, 0, 0 } end
  function m:setVertex(i, x, y, z, u, v, s)
    local t = self.v[i]
    t[1], t[2], t[3], t[4], t[5], t[6] = x, y, z, u, v, s
    self.writes = self.writes + 1
  end
  function m:setVertexMap() end
  function m:setDrawRange() end
  function m:setTexture() end
  meshes[#meshes + 1] = m
  return m
end
local function newRng(seed)
  local state = floor(seed) % 2147483647
  if state <= 0 then state = state + 2147483646 end
  local r = {}
  function r:random(a, b)
    state = (state * 16807) % 2147483647
    local f = (state - 1) / 2147483646
    if not a then return f end
    if not b then a, b = 1, a end
    return a + floor(f * (b - a + 1))
  end
  return r
end
love = { math = { random = math.random, newRandomGenerator = newRng },
         graphics = { newMesh = newMesh } }

-- ------- the game
local player = { px = 0, py = 0, cellX = 0, cellY = 0 }
local ow = { map = newMap("ROUTE_TEST"), player = player, npcs = {},
             transitioning = false }
local Game = { overworld = ow, stack = {} }
function Game.stack:top() return ow end
package.loaded["src.core.Game"] = Game

local stubs = { TileShape = TileShape, VoxelScene = VoxelScene, VegFX = VegFX,
                Wind = Wind, WindFX = WindFX, GroundFX = GroundFX,
                Quality = Quality, Voxel3D = Voxel3D, VoxelState = VoxelState }
local V = {}
local cache = {}
function V.require(name)
  if stubs[name] then return stubs[name] end
  if cache[name] == nil then
    cache[name] = assert(loadfile(ROOT .. "/lib/" .. name .. ".lua"))(V)
  end
  return cache[name]
end

local FX = V.require("LeafFallFX")
local LeafLitter = V.require("LeafLitter")

local DT = 1 / 60
local function place(cx, cz)
  player.px, player.py = cx * 16, cz * 16
  player.cellX, player.cellY = cx, cz
end
local function run(n, each)
  for i = 1, n do
    if each then each(i) end
    FX.update(DT, true)
  end
end
local function litterMesh()
  for _, m in ipairs(meshes) do
    if m.vertices == FX.LITTER_MAX * 4 then return m end
  end
end
-- every lying leaf on a surveyed open cell, at floor + RAISE
local function validate(st)
  local s = st.store
  local off, height = 0, 0
  for i = 1, s.high do
    if s.used[i] then
      local c = s:cellOf(s.x[i], s.z[i])
      local cx, cz = floor(s.x[i] / 16), floor(s.z[i] / 16)
      if not (c and st.ok[c]) or kind(cx, cz) ~= "ground" then
        off = off + 1
      elseif math.abs(s.y[i] - (st.floor[c] + FX.RAISE)) > 1e-9 then
        height = height + 1
      end
    end
  end
  return off, height
end

print("== 1. a treed route binds with its ground already seeded ==")
place(12, 16)
run(1)
local st = FX.state()
check(st ~= nil and st.key == "ROUTE_TEST" and FX.lastGate == "live",
      "the route binds", FX.lastGate)
local off, height = validate(st)
check(st.seeded > 50, ("seeded %d leaves from %d crowns, cap %d, %d open cells")
      :format(st.seeded, st.trees, st.store.cap, st.open))
check(st.store.count == st.seeded, "the store holds exactly what was seeded")
check(off == 0 and height == 0, "none on a crown or in the grass, all at floor + RAISE",
      ("off %d, height %d"):format(off, height))
check(st.store:perCellMax() <= FX.SEED_PER_CELL,
      ("no cell seeded past SEED_PER_CELL (%d): room left for what falls")
      :format(FX.SEED_PER_CELL))
local seedSum, seedCount = st.store:checksum(), st.store.count
check(FX.errorCount == 0, "no update errors", tostring(FX.lastError))

print("")
print("== 2. the same route always shows the same ground ==")
FX.forget()
run(1)
st = FX.state()
check(st.store:checksum() == seedSum and st.store.count == seedCount,
      "forgotten and bound again: the identical ground")

print("")
print("== 3. a shed leaf lies on open ground, or is accounted lost ==")
do
  env.amount = 0.95
  local s = st.store
  local s0, l0, x0, k0, r0 = FX.shedCount, FX.landed, FX.lost, FX.kicked, FX.replaced
  local c0, e0 = s.count, s.evicted
  local n = 0
  for i = 1, 40 do
    local t = TREES[(i % #TREES) + 1]
    if FX.shed(t.x, 13, t.z) then n = n + 1 end
  end
  run(900)
  local dl, dx = FX.landed - l0, FX.lost - x0
  check(n == 40 and FX.shedCount - s0 == 40, "40 leaves let go")
  check(FX.count() == 0, "fifteen seconds later none is in the air",
        FX.count() .. " still up")
  check(dl + dx == 40, ("every one landed (%d) or was lost (%d)"):format(dl, dx))
  check(dl >= 8, "a fair share found open ground beside the crowns")
  off, height = validate(st)
  check(off == 0 and height == 0, "the ground is still all open cells at floor + RAISE",
        ("off %d, height %d"):format(off, height))
  check(s.count - c0 == dl - (FX.kicked - k0) - (s.evicted - e0) - (FX.replaced - r0),
        ("the count moved by exactly landed - kicked - evicted - replaced (%d replaced)")
        :format(FX.replaced - r0))
end

print("")
print("== 4. a path walked through a pile clears, and no leaf goes missing ==")
do
  env.amount = 0
  local s = st.store
  local zc = 15 * 16 + 8
  local out = {}
  for cx = 2, 14 do
    local n = s:collect(cx * 16 + 8, zc, 12, FX.clock() + 1e6, 0, out)
    for k = 1, n do s:remove(out[k]) end
  end
  local laid = 0
  for cx = 5, 10 do
    for k = 0, 3 do
      local z = zc + ((k % 2 == 0) and -3 or 3)
      if FX.deposit(cx * 16 + 2 + k * 4, z, FX.lyingFrame(0, 0.3), k) then
        laid = laid + 1
      end
    end
  end
  local function band(lo, hi)
    local n = 0
    for i = 1, s.high do
      if s.used[i] and s.x[i] >= 4 * 16 and s.x[i] < 12 * 16 then
        local dz = math.abs(s.z[i] - zc)
        if dz > lo and dz <= hi then n = n + 1 end
      end
    end
    return n
  end
  place(3, 15)
  run(2)
  local N0, side0 = band(-1, 7), band(7, 40)
  local c0, k0, l0, x0, e0 = s.count, FX.kicked, FX.landed, FX.lost, s.evicted
  local r0 = FX.replaced
  run(150, function()
    player.px = player.px + 1
    player.cellX = floor((player.px + 8) / 16)
  end)
  run(300)
  local N1, side1 = band(-1, 7), band(7, 40)
  local dk, dl, dx, de = FX.kicked - k0, FX.landed - l0, FX.lost - x0, s.evicted - e0
  check(laid == 24 and N0 == 24, ("a pile of %d on the path"):format(N0))
  check(dk >= 0.8 * N0, ("the walk kicked %d of them"):format(dk))
  check(N1 <= 0.25 * N0, ("%d left on the path afterwards"):format(N1))
  check(FX.count() == 0 and dk == dl + dx,
        ("every kicked leaf lay down again (%d) or was lost (%d)"):format(dl, dx))
  check(s.count - c0 == dl - dk - de - (FX.replaced - r0),
        "the count moved by exactly landed - kicked - evicted - replaced")
  check(side1 - side0 >= 0.5 * dl,
        ("they went to the sides of the path: %d -> %d"):format(side0, side1))
end

print("")
print("== 5. a settled ground writes no vertex ==")
do
  FX.drawWorld()
  local mesh = litterMesh()
  local f0, s0, w0 = FX.fullWrites, FX.slotWrites, mesh and mesh.writes
  run(120)
  for _ = 1, 30 do FX.drawWorld() end
  check(mesh and FX.fullWrites == f0 and FX.slotWrites == s0 and mesh.writes == w0,
        "120 quiet frames and 30 draws: zero writes")
  local slot = FX.deposit(20 * 16 + 8, 17 * 16 + 8, FX.lyingFrame(1, 0.5), 0.7)
  FX.drawWorld()
  check(slot and FX.slotWrites == s0 + 1 and mesh.writes == w0 + 4,
        "one new leaf is one slot and four vertices")
  local base = ((slot or 1) - 1) * 4
  local y = mesh.v[base + 1][2]
  local flat = true
  for c = 2, 4 do
    if mesh.v[base + c][2] ~= y or mesh.v[base + c][6] ~= -1 then flat = false end
  end
  check(flat and math.abs(y - FX.RAISE) < 1e-9 and mesh.v[base + 1][6] == -1,
        "flat, at floor + RAISE, shaded as a face that looks up")
  local freed = st.store:remove(slot)
  FX.drawWorld()
  local v1 = mesh.v[base + 1]
  local point = freed
  for c = 2, 4 do
    local v = mesh.v[base + c]
    if v[1] ~= v1[1] or v[2] ~= v1[2] or v[3] ~= v1[3] then point = false end
  end
  check(point, "and a freed slot collapses to a point")
end

print("")
print("== 6. the last MAP_KEEP maps keep their ground ==")
do
  local home = ow.map
  FX.deposit(22 * 16 + 4, 18 * 16 + 4)
  local sum, count = st.store:checksum(), st.store.count
  ow.map = newMap("ROUTE_B"); run(1)
  ow.map = newMap("ROUTE_C"); run(1)
  ow.map = home; run(1)
  check(FX.state() == st and st.store:checksum() == sum and st.store.count == count,
        "two maps away and back: the same ground, kicks and all")
  ow.map = newMap("ROUTE_B"); run(1)
  ow.map = newMap("ROUTE_C"); run(1)
  ow.map = newMap("ROUTE_D"); run(1)
  ow.map = newMap("ROUTE_TEST"); run(1)
  st = FX.state()
  check(st.store:checksum() == seedSum and st.store.count == seedCount,
        "three other maps later it was forgotten, and seeded identically")
end

print("")
print("== 7. PFX LOW shrinks the ground, rewritten whole once ==")
do
  -- fill past LOW's ceiling first, or the shrink has nothing to cut
  local s = st.store
  local guard = 0
  while s.count <= 450 and guard < 20000 do
    FX.deposit(math.random() * W * 16, math.random() * H * 16)
    guard = guard + 1
  end
  FX.drawWorld()
  local f0 = FX.fullWrites
  env.mul = 0.4
  run(1)
  FX.drawWorld()
  FX.drawWorld()
  check(st.store.cap == floor(FX.LITTER * 0.4) and st.store.count <= st.store.cap,
        ("cap %d, count %d"):format(st.store.cap, st.store.count))
  check(FX.fullWrites == f0 + 1, "exactly one full rewrite for the shrink",
        (FX.fullWrites - f0) .. " rewrites")
  env.mul = 1
  run(1)
end

print("")
print("== 8. under snow nothing lands and the ground is not drawn ==")
do
  env.cover, env.amount = 0.5, 0
  local l0, x0 = FX.landed, FX.lost
  for i = 1, 10 do
    local t = TREES[i]
    FX.shed(t.x, 13, t.z + 20)
  end
  run(600)
  check(FX.landed == l0 and FX.lost - x0 == 10, "10 leaves onto snow: none lies, 10 lost")
  local mesh = litterMesh()
  local d0 = mesh.draws
  FX.drawWorld()
  check(mesh.draws == d0, "and the ground draw is skipped")
  env.cover = 0
end

print("")
print("== 9. a frame in regime allocates nothing ==")
do
  env.amount = 0.95
  place(3, 15)
  local dir = 1
  local function pace(i)
    player.px = player.px + dir
    if player.px > 18 * 16 then dir = -1 elseif player.px < 3 * 16 then dir = 1 end
    player.cellX = floor((player.px + 8) / 16)
    if i % 20 == 0 then
      local t = TREES[(i % #TREES) + 1]
      FX.shed(t.x, 13, t.z)
    end
    if i % 3 == 0 then
      FX.deposit(math.random(1, 22) * 16 + 4, 15 * 16 + math.random(1, 14))
    end
    FX.drawWorld()
  end
  local k0, l0 = FX.kicked, FX.landed
  run(6000, pace)
  collectgarbage("collect")
  collectgarbage("stop")
  local g0 = collectgarbage("count")
  run(3000, pace)
  local g1 = collectgarbage("count")
  collectgarbage("restart")
  check(g1 - g0 < 2,
        ("3000 frames of walking, falling, landing, kicking and drawing allocate %.3f KB")
        :format(g1 - g0))
  check(FX.kicked > k0 and FX.landed > l0, ("(%d kicks, %d landings actually happened)")
        :format(FX.kicked - k0, FX.landed - l0))
  check(FX.errorCount == 0 and FX.drawErrors == 0, "no errors in update or draw",
        tostring(FX.lastError) .. " / " .. tostring(FX.drawError))
end

print("")
print(("%d checks, %d failures"):format(checks, fails))
if fails > 0 then os.exit(1) end
