-- Offline check of the drawn wind (lib/WindLines.lua). NO GAME AND NO GPU.
--
--   py -c "from lupa import LuaRuntime; import pathlib; --          r=r'C:/Users/breno/Downloads/GBA/Terrarium'; --          LuaRuntime().eval('function(s,r) return (loadstring or load)(s)(r) end') --          (pathlib.Path(r+'/tests/wind_lines_offline.lua').read_text(encoding='utf-8'), r)"
--
--   Q1 SMOOTH   every path is one unbroken curve: no two neighbouring points
--               further apart than a step and a half, loops included
--   Q2 DIES     a stroke is gone once its tail has run the whole path, and
--               not before its head has
--   Q3 MORE     a gale keeps more strokes up than a breeze; rain fewer
--   Q4 BANDS    a breeze keeps high; a gale also fills the low band
--   Q5 FRONT    a gust front puts at least FRONT strokes up at once, marked
--   Q6 END      a sample a hair past the end is the end, not an error (one
--               such error took the whole 3D pass down)
--   Q7 TWIN     a twin's two strokes wind round one path in opposite phase
--   Q8 FOLLOWS  a path turns with the field it is born in
local ROOT = ... or "."

local flow = { x = 30, z = 0 }
local modules = {
  Wind = { DIR = { 1, 0 },
           flowAt = function() return flow.x, flow.z, 1 end,
           turbAt = function() return 0, 0 end },
  Voxel3D = {},
}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local path = ROOT .. "/lib/" .. name .. ".lua"
  local f = assert(io.open(path, "rb")); local src = f:read("*a"); f:close()
  local v = assert((loadstring or load)(src, "@" .. path))(V)
  modules[name] = v
  return v
end
math.randomseed(7)
local W = V.require("WindLines")

local fails = 0
local function check(name, ok, detail)
  print(("  %s  %s  %s"):format(ok and "PASS" or "FAIL", name, detail or ""))
  if not ok then fails = fails + 1 end
end
local function ground() return 0 end
local function run(frames, amount, climate)
  for _ = 1, frames do W.update(1 / 60, true, 0, 0, amount, climate or "dry", ground) end
end

-- Q1
W.clear(); run(60 * 6, 3.0)
local worst, shapes = 0, {}
for _, l in ipairs(W.list()) do
  shapes[l.shape] = (shapes[l.shape] or 0) + 1
  for i = 2, #l.xs do
    local d = math.sqrt((l.xs[i] - l.xs[i - 1]) ^ 2 + (l.ys[i] - l.ys[i - 1]) ^ 2
                        + (l.zs[i] - l.zs[i - 1]) ^ 2)
    if d > worst then worst = d end
  end
end
local names = {}
for k, c in pairs(shapes) do names[#names + 1] = k .. "=" .. c end
table.sort(names)
check("Q1 SMOOTH", worst <= W.DS * 1.5,
      ("widest step %.2f px (DS %d); shapes %s"):format(worst, W.DS, table.concat(names, " ")))

-- Q2
W.clear()
W.front(0, 0, 1.0, "dry", ground)
local l = W.list()[1]
local diedAt, lastSeen = nil, 0
for i = 1, 60 * 10 do
  W.update(1 / 60, true, 0, 0, 0, "dry", ground)
  local alive = false
  for _, m in ipairs(W.list()) do if m == l then alive = true end end
  if alive then lastSeen = i / 60 elseif not diedAt then diedAt = i / 60 end
end
local headDone = l.total / l.speed
check("Q2 DIES", diedAt ~= nil and lastSeen >= headDone - 0.5,
      ("gone at %.2f s; the head reaches the end after %.2f s of flight"):format(diedAt or -1, headDone))

-- Q3
local function settle(amount, climate)
  W.clear()
  local sum, n = 0, 0
  for i = 1, 60 * 20 do
    W.update(1 / 60, true, 0, 0, amount, climate, ground)
    if i > 60 * 5 then sum = sum + W.count(); n = n + 1 end
  end
  return sum / n
end
local breeze, gale, rain = settle(0.9, "dry"), settle(3.0, "dry"), settle(3.0, "rain")
check("Q3 MORE", gale > breeze * 1.8 and rain < gale,
      ("breeze %.1f, gale %.1f, rain %.1f strokes up on average"):format(breeze, gale, rain))

-- Q4: a breeze keeps to the high band; a gale also fills the low one, and
-- nothing flies outside the two
local function heights(amount)
  local lo, hi, low, n = 1e9, -1e9, 0, 0
  W.clear()
  for _ = 1, 60 * 20 do
    W.update(1 / 60, true, 0, 0, amount, "dry", ground)
    for _, m in ipairs(W.list()) do
      if m.height < lo then lo = m.height end
      if m.height > hi then hi = m.height end
      n = n + 1
      if m.height < W.BAND[1] then
        low = low + 1
        if m.height < W.LOW[1] or m.height > W.LOW[2] then low = -1e9 end
      end
    end
  end
  return lo, hi, low, n
end
local blo, bhi, blow = heights(0.9)
local glo, ghi, glow, gn = heights(3.0)
check("Q4 BANDS", blo >= W.BAND[1] and bhi <= W.BAND[2] and blow == 0
      and glow > 0 and ghi <= W.BAND[2],
      ("breeze %.1f..%.1f px; gale %.1f..%.1f px with %.0f%% low"):format(
        blo, bhi, glo, ghi, 100 * math.max(0, glow) / math.max(1, gn)))

-- Q5
W.clear()
W.front(0, 0, 2.0, "dry", ground)
local fronts = 0
for _, m in ipairs(W.list()) do if m.front then fronts = fronts + 1 end end
check("Q5 FRONT", fronts >= W.FRONT, ("%d front strokes, FRONT = %d"):format(fronts, W.FRONT))

-- Q6
local okEnd, err = true, nil
W.clear(); run(60 * 4, 3.0)
for _, m in ipairs(W.list()) do
  local ok, e = pcall(W._pathAt, m, m.total * (1 + 1e-9) + 1e-9)
  if not ok then okEnd, err = false, e end
end
check("Q6 END", okEnd, err and tostring(err) or "")

-- Q7: find a twin (fronts until one is born -- a gale front is a quarter to
-- half twins) and compare its two strokes at the same arc length
local pair
for _ = 1, 40 do
  W.clear()
  W.front(0, 0, 3.0, "dry", ground)
  for _, m in ipairs(W.list()) do
    if m.helix then
      for _, o in ipairs(W.list()) do
        if o ~= m and o.xs == m.xs then pair = { m, o } end
      end
    end
    if pair then break end
  end
  if pair then break end
end
if pair then
  local a, b = pair[1], pair[2]
  local s = a.total * 0.5
  local ax, ay, az = W._pathAt(a, s)
  local bx, by, bz = W._pathAt(b, s)
  local sep = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
  check("Q7 TWIN", math.abs(sep - 2 * a.helix) < 0.05,
        ("the pair %.2f px apart, helix radius %.2f"):format(sep, a.helix))
else
  check("Q7 TWIN", false, "no twin born in a gale")
end

-- Q8: the field turns 90 degrees; a new path must end up heading with it
W.clear()
flow.x, flow.z = 0, 30
run(60 * 3, 1.0)
local turned, n8 = 0, 0
for _, m in ipairs(W.list()) do
  n8 = n8 + 1
  if m.dzs[#m.dzs] > 0.9 then turned = turned + 1 end
end
flow.x, flow.z = 30, 0
check("Q8 FOLLOWS", n8 > 0 and turned == n8,
      ("%d of %d paths heading down the new field"):format(turned, n8))

-- Q9 CARRY: a leaf lent to a stroke rides its head and is handed back when
-- the head reaches the end -- never kept, never lent twice to a pair
W.clear()
local lent, back, onHead, maxLag = {}, 0, 0, 0
local hooks = {
  claimLeaf = function(x, y, z) local m = { x = x, y = y, z = z, t = 0 }; lent[#lent + 1] = m; return m end,
  releaseLeaf = function(m) m.released = true; back = back + 1 end,
}
local oldC, oldF = W.CARRY, W.CARRY_FRONT
W.CARRY, W.CARRY_FRONT = 1, 1
W.front(0, 0, 2.0, "dry", ground)
for _ = 1, 60 * 6 do
  W.update(1 / 60, true, 0, 0, 0, "dry", ground, hooks)
  for _, l in ipairs(W.list()) do
    if l.leaf then
      local hx, hy, hz = W._pathAt(l, math.min(l.t * l.speed, l.total))
      local d = math.sqrt((l.leaf.x - hx) ^ 2 + (l.leaf.y - hy) ^ 2 + (l.leaf.z - hz) ^ 2)
      if d > maxLag then maxLag = d end
      onHead = onHead + 1
    end
  end
end
W.CARRY, W.CARRY_FRONT = oldC, oldF
-- the view goes away (a map change, a menu): whatever is still carried is
-- handed back too, not kept pinned in the air forever
W.update(1 / 60, false, 0, 0, 0, "dry", ground, hooks)
check("Q9 CARRY", #lent > 0 and back == #lent and onHead > 0 and maxLag < 0.01,
      ("%d leaves lent, %d handed back, riding the head within %.3f px"):format(#lent, back, maxLag))

-- Q10 SWIRL: in a gale, with a crown to go round, a pair of strokes winds
-- round it at a steady radius and climbs over it
W.clear()
local crown = { x = 200, z = 100, h = 18 }
local swirl
local hooksC = { crown = function() return crown end }
for _ = 1, 60 * 60 do
  W.update(1 / 60, true, 0, 0, 3.0, "dry", ground, hooksC)
  for _, m in ipairs(W.list()) do if m.shape == "swirl" then swirl = m end end
  if swirl then break end
end
if swirl then
  local rmin, rmax, n = 1e9, 0, 0
  local turn = math.floor(#swirl.xs * 0.6)
  for i = 1, turn do
    local r = math.sqrt((swirl.xs[i] - crown.x) ^ 2 + (swirl.zs[i] - crown.z) ^ 2)
    if r < rmin then rmin = r end
    if r > rmax then rmax = r end
  end
  check("Q10 SWIRL", rmin > 10 and rmax < 26 and swirl.ys[turn] > swirl.ys[1],
        ("round the crown at %.1f..%.1f px, climbing %.1f -> %.1f"):format(
          rmin, rmax, swirl.ys[1], swirl.ys[turn]))
else
  check("Q10 SWIRL", false, "no swirl in a minute of gale beside a crown")
end

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
return fails
