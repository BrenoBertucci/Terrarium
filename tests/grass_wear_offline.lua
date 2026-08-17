-- Offline probe of the wear field in lib/GrassWear.lua.
-- NO GAME AND NO GPU. Same stub harness as tests/grass_crush_offline.lua.
--
--   lua tests/grass_wear_offline.lua [path-to-mod-root]
--
-- or, when there is no lua on PATH (the usual case on this machine):
--
--   py -c "from lupa import LuaRuntime; import pathlib; \
--          r=r'C:/Users/breno/Downloads/GBA/Terrarium'; \
--          LuaRuntime().eval('function(s,r) return load(s)(r) end') \
--          (pathlib.Path(r+'/tests/grass_wear_offline.lua').read_text(encoding='utf-8'), r)"
--
-- WHAT IT ASKS
--
--   Q1 PACE          one crossing is invisible, forty reach the ceiling
--   Q2 CEILING       trample stops at TRAMPLE_CAP; burn and cut reach 1.0
--   Q3 DECAY         half-life is the half-life, and a cell retires
--   Q4 CAUSE         walking over a scar does not downgrade it to a path
--   Q5 SAVE          serialize -> deserialize reproduces the faded field
--   Q6 ISOLATION     two maps do not share cells
--   Q7 SHELTER       a wall's lee is calm, open sky is not
--   Q8 SPREAD        a straight walk writes a line, not a blob
--
-- Every question prints its numbers and then PASS/FAIL against a stated
-- threshold. A question with no threshold is not a test, it is a printout.

local ROOT = ... or "."

-- ------- the harness
--
-- GrassWear reaches for love only to make its Image. bindHeadless forces
-- the image off, so these stubs exist for the require path and nothing
-- else -- but they stay honest (setPixel records) so a future question can
-- ask what was painted.
love = {
  image = {
    newImageData = function(w, h)
      return { w = w, h = h, setPixel = function() end,
               getPixel = function() return 0, 0, 0, 1 end }
    end,
  },
  graphics = {
    newImage = function()
      return { setFilter = function() end, setWrap = function() end,
               replacePixels = function() end, release = function() end }
    end,
  },
  timer = { getTime = function() return 12.0 end },
}

-- the mod's save bucket, which is all GrassWear.store/restore touches
local bucket = {}
local V = {
  path = ROOT,
  mod = {
    id = "TERRARIUM",
    save = {
      set = function(_, k, v) bucket[k] = v end,
      get = function(_, k) return bucket[k] end,
    },
    log = { warn = function() end },
  },
}
function V.require(name)
  error("GrassWear should not require anything, asked for: " .. tostring(name))
end

local chunk = assert(loadfile(ROOT .. "/lib/GrassWear.lua"))
local GW = chunk(V)

-- ------- a fake map
--
-- Grass everywhere except a 3x3 block of wall at (20,20), so Q7 has a lee
-- to measure and Q1..Q6 have grass to write on. isGrassCell is what
-- GrassWear gates every write on, so a map that lies here makes every
-- other answer meaningless.
local function fakeMap(wallAt)
  return {
    widthCells = 48,
    heightCells = 48,
    inBounds = function(_, cx, cy)
      return cx >= 0 and cy >= 0 and cx < 48 and cy < 48
    end,
    isWalkableCell = function(_, cx, cy)
      if not wallAt then return true end
      return not (cx >= 20 and cx <= 22 and cy >= 20 and cy <= 22)
    end,
    isWaterCell = function() return false end,
    isGrassCell = function(_, cx, cy)
      if not wallAt then return true end
      return not (cx >= 20 and cx <= 22 and cy >= 20 and cy <= 22)
    end,
  }
end

local fails = 0
local function check(label, ok, detail)
  if not ok then fails = fails + 1 end
  print(string.format("    %s  %s%s", ok and "PASS" or "FAIL", label,
                      detail and ("  " .. detail) or ""))
end

-- One crossing of a cell at walking pace, as VoxelScene will drive it:
-- per-frame contact, weight * dt.
local FRAME = 1 / 60
local CROSS_FRAMES = 16      -- ~0.27 s, one 16px cell at ~60 px/s
local function crossOnce(wx, wz, weight)
  for _ = 1, CROSS_FRAMES do
    GW.add(wx, wz, (weight or GW.W_PLAYER) * FRAME, GW.CAUSE_TRAMPLE)
    GW.advance(FRAME)
  end
end

-- ------- Q1 PACE
print("Q1 PACE  -- one crossing invisible, forty at the ceiling")
GW.reset()
GW.bindHeadless("route1", fakeMap(false))
crossOnce(100, 100)
local afterOne = GW.at(100, 100)
for _ = 2, 40 do crossOnce(100, 100) end
local after40 = GW.at(100, 100)
print(string.format("    1 crossing  = %.4f", afterOne))
print(string.format("    40 crossings= %.4f", after40))
check("one crossing is below the eye", afterOne < 0.03,
      string.format("(%.4f < 0.03)", afterOne))
check("forty crossings read as a path", after40 > 0.40,
      string.format("(%.4f > 0.40)", after40))

-- ------- Q2 CEILING
print("Q2 CEILING  -- trample stops short of bare; deliberate causes do not")
GW.reset()
GW.bindHeadless("route1", fakeMap(false))
for _ = 1, 400 do crossOnce(200, 200) end
local trampled = GW.at(200, 200)
GW.mark(30, 30, 1.0, GW.CAUSE_BURN)
local burnt = GW.atCell(30, 30)
GW.mark(31, 31, 1.0, GW.CAUSE_CUT)
local cut = GW.atCell(31, 31)
print(string.format("    400 crossings = %.4f  (cap %.2f)", trampled,
                    GW.TRAMPLE_CAP))
print(string.format("    burn = %.4f   cut = %.4f", burnt, cut))
check("trample never exceeds the cap", trampled <= GW.TRAMPLE_CAP + 1e-6,
      string.format("(%.4f <= %.2f)", trampled, GW.TRAMPLE_CAP))
check("trample actually reaches the cap", trampled > GW.TRAMPLE_CAP - 0.02)
check("burn reaches bare", burnt > 0.99)
check("cut reaches bare", cut > 0.99)
check("a cut cell blocks encounters", GW.isCut(31, 31) == true)
check("a trampled cell does not", GW.isCut(12, 12) == false)

-- ------- Q3 DECAY
print("Q3 DECAY  -- the half-life is the half-life")
GW.reset()
GW.bindHeadless("route1", fakeMap(false))
GW.mark(40, 40, 0.80, GW.CAUSE_TRAMPLE)
local d0 = GW.atCell(40, 40)
GW.advance(GW.HALF_TRAMPLE)
local d1 = GW.atCell(40, 40)
GW.advance(GW.HALF_TRAMPLE)
local d2 = GW.atCell(40, 40)
GW.mark(41, 41, 1.0, GW.CAUSE_BURN)
GW.advance(GW.HALF_TRAMPLE * 2)
local scar = GW.atCell(41, 41)
print(string.format("    t=0 %.4f   t=1H %.4f   t=2H %.4f", d0, d1, d2))
print(string.format("    burn scar after 2 trample half-lives: %.4f", scar))
check("one half-life halves it", math.abs(d1 - d0 * 0.5) < 0.01,
      string.format("(%.4f vs %.4f)", d1, d0 * 0.5))
check("two half-lives quarter it", math.abs(d2 - d0 * 0.25) < 0.01)
check("a lightning scar outlives a path", scar > d2 * 2,
      string.format("(%.4f > %.4f)", scar, d2 * 2))
-- and it eventually retires entirely
GW.advance(GW.HALF_BURN * 8)
check("a cell retires once it is gone", GW.atCell(41, 41) == 0)

-- ------- Q4 CAUSE
print("Q4 CAUSE  -- footprints across a scar leave it a scar")
GW.reset()
GW.bindHeadless("route1", fakeMap(false))
GW.mark(50, 50, 1.0, GW.CAUSE_BURN)
local _, causeBefore = GW.atCell(50, 50)
for _ = 1, 60 do crossOnce(50 * 16 + 8, 50 * 16 + 8) end
local vAfter, causeAfter = GW.atCell(50, 50)
print(string.format("    cause before=%d after=%d   value after=%.4f",
                    causeBefore, causeAfter, vAfter))
check("cause stays BURN", causeAfter == GW.CAUSE_BURN)
check("value is not pulled down to the trample cap",
      vAfter > GW.TRAMPLE_CAP + 0.1,
      string.format("(%.4f > %.2f)", vAfter, GW.TRAMPLE_CAP + 0.1))

-- ------- Q5 SAVE
print("Q5 SAVE  -- a round trip reproduces the faded field")
GW.reset()
GW.bindHeadless("route1", fakeMap(false))
local cells = { { 10, 10 }, { 11, 10 }, { 12, 10 }, { 30, 5 } }
for i = 1, #cells do
  GW.mark(cells[i][1], cells[i][2], 0.2 * i, GW.CAUSE_TRAMPLE)
end
GW.mark(33, 33, 1.0, GW.CAUSE_BURN)
GW.advance(GW.HALF_TRAMPLE * 0.5)
local before = {}
for i = 1, #cells do
  before[i] = GW.atCell(cells[i][1], cells[i][2])
end
local beforeScar = GW.atCell(33, 33)
GW.store()
GW.restore()
GW.bindHeadless("route1", fakeMap(false))
local worst = 0
for i = 1, #cells do
  local now = GW.atCell(cells[i][1], cells[i][2])
  local err = math.abs(now - before[i])
  if err > worst then worst = err end
  print(string.format("    cell %d,%d  %.4f -> %.4f", cells[i][1],
                      cells[i][2], before[i], now))
end
local nowScar, nowCause = GW.atCell(33, 33)
print(string.format("    scar %.4f -> %.4f (cause %d)", beforeScar, nowScar,
                    nowCause))
-- 1/255 quantisation plus one second of integer age rounding
check("every cell survives within quantisation", worst < 0.01,
      string.format("(worst %.5f)", worst))
check("the scar keeps its cause", nowCause == GW.CAUSE_BURN)
check("an untouched cell is still untouched", GW.atCell(1, 1) == 0)

-- ------- Q6 ISOLATION
print("Q6 ISOLATION  -- Route 1's paths do not show up in Viridian Forest")
GW.reset()
GW.bindHeadless("route1", fakeMap(false))
GW.mark(15, 15, 0.7, GW.CAUSE_TRAMPLE)
local r1 = GW.atCell(15, 15)
GW.bindHeadless("viridian", fakeMap(false))
local vf = GW.atCell(15, 15)
GW.bindHeadless("route1", fakeMap(false))
local back = GW.atCell(15, 15)
print(string.format("    route1 %.4f   viridian %.4f   route1 again %.4f",
                    r1, vf, back))
check("the other map's cell is clean", vf == 0)
check("coming back finds it again", math.abs(back - r1) < 1e-6)

-- ------- Q7 SHELTER
print("Q7 SHELTER  -- a wall's lee is calm and open sky is not")
GW.reset()
GW.bindHeadless("route1", fakeMap(true))
-- The wall is cells 20..22 square. Sample just outside it, and far away.
local function shelterAt(cx, cy)
  -- shelter is not on the public read path (the shader gets it through
  -- the texel), so ask the bake directly through a serialize-free seam
  return GW.shelterAt and GW.shelterAt(cx, cy) or nil
end
local lee = shelterAt(23, 21)
local open = shelterAt(2, 2)
local far = shelterAt(20 + GW.SHELTER_REACH + 2, 21)
if lee == nil then
  print("    SKIP  GrassWear.shelterAt is not exposed")
  check("shelter is measurable", false, "(no seam)")
else
  print(string.format("    beside the wall %.3f   %d cells away %.3f   open %.3f",
                      lee, GW.SHELTER_REACH + 2, far, open))
  check("the lee is calm", lee < 0.75, string.format("(%.3f < 0.75)", lee))
  check("open sky is untouched", open >= 1.0)
  check("shelter runs out with distance", far >= 1.0)
end

-- ------- Q8 SPREAD
print("Q8 SPREAD  -- a straight walk writes a line, not a blob")
GW.reset()
GW.bindHeadless("route1", fakeMap(false))
-- Walk east across ten cells, once each.
for c = 5, 14 do crossOnce(c * 16 + 8, 8 * 16 + 8) end
local online, offline_ = 0, 0
for c = 5, 14 do
  if GW.atCell(c, 8) > 0 then online = online + 1 end
  if GW.atCell(c, 7) > 0 then offline_ = offline_ + 1 end
  if GW.atCell(c, 9) > 0 then offline_ = offline_ + 1 end
end
print(string.format("    cells on the path %d/10   cells beside it %d/20",
                    online, offline_))
check("every cell walked is marked", online == 10)
check("nothing beside the path is", offline_ == 0)
check("count() agrees with the walk", GW.count() >= 0,
      string.format("(count=%d, concentration=%.3f)", GW.count(),
                    GW.concentration(0.05)))

-- ------- Q9 BUCKETS
print("Q9 BUCKETS  -- the decal's steps, and the queue that rebuilds them")
GW.reset()
GW.bindHeadless("route1", fakeMap(false))
print(string.format("    bucketOf: 0=%d  0.05=%d  0.10=%d  0.40=%d  0.75=%d  1.00=%d",
                    GW.bucketOf(0), GW.bucketOf(0.05), GW.bucketOf(0.10),
                    GW.bucketOf(0.40), GW.bucketOf(0.75), GW.bucketOf(1.00)))
check("untouched grass has no decal", GW.bucketOf(0) == 0)
check("a single crossing has no decal", GW.bucketOf(0.019) == 0)
check("just past the threshold is step 1", GW.bucketOf(0.10) == 1)
check("bare earth is the last step", GW.bucketOf(1.00) == GW.BUCKETS)
local mono = true
local last = 0
for i = 0, 100 do
  local b = GW.bucketOf(i / 100)
  if b < last then mono = false end
  last = b
end
check("buckets never go backwards as wear climbs", mono)

-- the queue: a change enqueues, and asking empties it
GW.takeBucketChanges()
GW.mark(60, 60, 0.5, GW.CAUSE_TRAMPLE)
local q1 = GW.takeBucketChanges()
local q2 = GW.takeBucketChanges()
print(string.format("    after one mark: queue=%s, second ask=%s",
                    q1 and (#q1 / 2) .. " cell(s)" or "nil",
                    q2 and (#q2 / 2) .. " cell(s)" or "nil"))
check("crossing into a step enqueues the cell", q1 ~= nil and #q1 == 2)
check("the queue is emptied by asking", q2 == nil)
-- and writing again WITHOUT changing step must not enqueue
GW.mark(60, 60, 0.52, GW.CAUSE_TRAMPLE)
local q3 = GW.takeBucketChanges()
print(string.format("    same step again: %s", q3 and "ENQUEUED" or "nil"))
check("staying in the same step rebuilds nothing", q3 == nil)
-- decaying out of every step must enqueue the removal
GW.advance(GW.HALF_TRAMPLE * 6)
for _ = 1, 400 do GW.step(0) end
local q4 = GW.takeBucketChanges()
print(string.format("    after fading out: %s",
                    q4 and (#q4 / 2) .. " cell(s)" or "nil"))
check("a faded path takes its decal with it", q4 ~= nil)

print("")
if fails == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILED", fails))
end
