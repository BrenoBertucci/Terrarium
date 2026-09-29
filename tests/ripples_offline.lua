-- Offline check of the ripple field (lib/Ripples.lua). NO GAME AND NO GPU.
--
--   py -c "from lupa import LuaRuntime; import pathlib; \
--          r=r'C:/Users/breno/Downloads/GBA/Terrarium'; \
--          LuaRuntime().eval('function(s,r) return (loadstring or load)(s)(r) end') \
--          (pathlib.Path(r+'/tests/ripples_offline.lua').read_text(encoding='utf-8'), r)"
--
-- WHAT IT ASKS
--   Q1 SPEED      a drop's ring front after one second sits at SPEED px.
--   Q2 STABLE     a source pumping for ten seconds stays bounded, no NaN.
--   Q3 BANK       a land cell never moves, and a ring comes BACK off a bank
--                 (the probe point between drop and bank sees the echo).
--   Q4 EDGE       the grid's own border swallows: open water far from any
--                 bank is quiet again after the ring has gone past the edge.
--   Q5 SLEEP      with nothing touching it the field stops stepping.
--   Q6 FOLLOW     sliding the grid under a ring keeps the ring where it was.
--   Q7 ENCODE     the texel says what the field says.
--   Q8 ROUND      a ring is a circle: the crest is as far out along a
--                 diagonal as along an axis (the five-point laplacian made
--                 octagons).
local ROOT = ... or "."

local ImageData = {}
ImageData.__index = ImageData
function ImageData:setPixel(x, y, r, g, b, a) self.px[y * self.w + x + 1] = { r, g, b, a } end
love = {
  image = { newImageData = function(w, h) return setmetatable({ w = w, h = h, px = {} }, ImageData) end },
  graphics = { newImage = function(d) return { data = d, setFilter = function() end,
                                               setWrap = function() end,
                                               replacePixels = function() end } end },
}

local V = { path = "." }
local modules = { WaterBody = { isWaterAt = function() return nil end,
                                field = function() return "F" end } }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local path = ROOT .. "/lib/" .. name .. ".lua"
  local f = assert(io.open(path, "rb")); local src = f:read("*a"); f:close()
  src = src:gsub("^\239\187\191", "")
  local v = assert((loadstring or load)(src, "@" .. path))(V)
  modules[name] = v
  return v
end

local R = V.require("Ripples")
local fails = 0
local function check(name, ok, detail)
  print(("  %s  %s  %s"):format(ok and "PASS" or "FAIL", name, detail or ""))
  if not ok then fails = fails + 1 end
end

local CELL, N = R.CELL, R.N
local C = N * CELL / 2                 -- world px at the grid's centre
local function run(seconds) for _ = 1, math.floor(seconds * R.RATE + 0.5) do R.update(1 / R.RATE, true, C, C) end end
local function fresh(isWater)
  R.reset()
  R.isWaterAt = isWater or function() return nil end
  R.update(0, true, C, C)
end

-- Q1: the front is the outermost place the field is still loud
fresh()
R.poke(C, C, -1.0, 4)
run(1.0)
local front = 0
for d = 4, 180, 1 do
  if math.abs(R.heightAt(C + d, C)) > 0.02 then front = d end
end
check("Q1 SPEED", math.abs(front - R.SPEED) <= R.SPEED * 0.25,
      ("front %d px after 1 s, SPEED %d"):format(front, R.SPEED))

-- Q2
fresh()
local worst, nan = 0, false
for _ = 1, 10 * R.RATE do
  R.emit(C, C, 1.0, 1.2, 2.0, "pump")
  R.update(1 / R.RATE, true, C, C)
  for _, d in ipairs({ 0, 8, 24, 60 }) do
    local v = R.heightAt(C + d, C)
    if v ~= v then nan = true end
    if math.abs(v) > worst then worst = math.abs(v) end
  end
end
check("Q2 STABLE", not nan and worst < 3.0, ("peak %.3f px over 10 s"):format(worst))

-- Q3: a bank 40 px east of the drop
local bankX = C + 40
local function bank(wx) return wx < bankX end
local function probeTrace(isWater)
  fresh(isWater)
  R.poke(C, C, -1.0, 4)
  local tr = {}
  for s = 1, 3 * R.RATE do
    R.update(1 / R.RATE, true, C, C)
    tr[s] = R.heightAt(C + 20, C)
  end
  return tr
end
local open = probeTrace(nil)
local walled = probeTrace(function(wx) return bank(wx) end)
local st = R._state()
local landStill = true
for j = 0, N - 1 do
  for i = 0, N - 1 do
    local k = j * N + i + 1
    if st.wet[k] == 0 and st.h[k] ~= 0 then landStill = false end
  end
end
-- the echo: after the ring has passed the probe (0.5 s) and had time to go
-- 20 px on to the bank and 20 px back (1.0 s more), the walled trace differs
local diff = 0
for s = math.floor(1.0 * R.RATE), math.floor(2.0 * R.RATE) do
  diff = math.max(diff, math.abs(walled[s] - open[s]))
end
check("Q3 BANK still", landStill, "")
local direct = 0
for s = 1, math.floor(1.0 * R.RATE) do direct = math.max(direct, math.abs(open[s])) end
check("Q3 BANK echo", diff > 0.25 * direct,
      ("echo %.3f px at the probe, the ring itself %.3f"):format(diff, direct))

-- Q4: open water, after the ring has run off the grid
fresh()
R.poke(C, C, -1.0, 4)
run(9.0)
local late = 0
for d = 0, 120, 4 do late = math.max(late, math.abs(R.heightAt(C + d, C))) end
check("Q4 EDGE", late < 0.02, ("left in the middle after 9 s: %.4f px"):format(late))

-- Q5
local before = R.steps
run(3.0)
local after = R.steps
run(1.0)
check("Q5 SLEEP", not R._state().awake and R.steps == after,
      ("steps %d -> %d -> %d, awake %s"):format(before, after, R.steps, tostring(R._state().awake)))

-- Q6: a ring, then the player walks 24 cells east
fresh()
R.poke(C, C, -1.0, 4)
run(0.5)
local at = { C + 12, C - 4 }
local v0 = R.heightAt(at[1], at[2])
R.follow(C + 24 * CELL, C)
local v1 = R.heightAt(at[1], at[2])
check("Q6 FOLLOW", math.abs(v0 - v1) < 1e-9 and R.recenters > 0,
      ("%.5f before, %.5f after the slide"):format(v0, v1))

-- Q7
local s2 = R._state()
local k = (N / 2) * N + N / 2 + 1
local r = R.encode(k)
local back = (r - 0.5) * R.H_ENC
check("Q7 ENCODE", math.abs(back - s2.h[k]) < 1e-6, ("%.5f vs %.5f"):format(back, s2.h[k]))

-- Q8 ROUND: the ring's crest sits at the same radius along an axis and along
-- a diagonal. The five-point laplacian failed this (an octagon on Route 21).
fresh()
R.poke(C, C, -2.0, 6)
run(1.2)
local function crestAt(ux, uz)
  local best, at = -1, 0
  for d = 8, 120 do
    local v = R.heightAt(C + ux * d, C + uz * d)
    if v > best then best, at = v, d end
  end
  return at
end
local rAxis = crestAt(1, 0)
local rDiag = crestAt(0.70710678, 0.70710678)
check("Q8 ROUND", math.abs(rDiag - rAxis) <= 0.08 * rAxis,
      ("crest at %d px on the axis, %d px on the diagonal"):format(rAxis, rDiag))

-- cost, in whatever Lua this is (lupa is not LuaJIT: an upper bound)
fresh()
R.poke(C, C, -1.0, 4)
local t0 = os.clock()
for _ = 1, 90 do R.update(1 / R.RATE, true, C, C) end
print(("  cost: %.3f ms per step+upload (this interpreter)"):format((os.clock() - t0) * 1000 / 90))

print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
return fails
