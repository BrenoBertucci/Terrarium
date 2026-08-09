-- Offline check of the water spectrum: three trains of fixed length whose
-- LOUDNESS is what the size of the body moves. NO GAME AND NO GPU -- the same
-- stub harness as tests/waterbody_offline.lua, so it runs in any Lua 5.1+.
--
--   lua tests/water_spectrum_offline.lua [path-to-mod-root]
--
-- or, when there is no lua on PATH (the usual case on this machine):
--
--   py -c "from lupa import LuaRuntime; import pathlib; \
--          r=r'C:/Users/breno/Downloads/GBA/Terrarium'; \
--          LuaRuntime().eval('function(s,r) return (loadstring or load)(s)(r) end') \
--          (pathlib.Path(r+'/tests/water_spectrum_offline.lua').read_text(encoding='utf-8'), r)"
--
-- WHAT IT ASKS
--
--   Q1 COHERENCE   |grad a| against |k|, over a grid of clocks and world
--                  offsets. This is the question the spectrum exists to
--                  answer. The field it replaced scaled the wave VECTOR by
--                  the size of the body, which put `(k . x) * grad bf` into
--                  the gradient -- a product of world position, unbounded --
--                  and measured 1.14x the wave's own wavenumber at the world
--                  origin, 7.80x a thousand pixels out and 28.03x at four
--                  thousand. Watertightness never caught it: Y = f(XZ) stays
--                  continuous while the pattern under it comes apart. With
--                  fixed vectors the answer must be exactly 1.00x in every
--                  cell of the table, and any other number is a regression.
--
--   Q2 SPECTRUM    the weights. Sum to one, open water unchanged from the
--                  build this replaced, and never fewer than two trains
--                  crossing anywhere -- one surviving train is corduroy.
--
--   Q3 DISPERSION  crest speed, short train against long. omega ~ sqrt(k),
--                  so c ~ 1/sqrt(k): a pond's ripple travels slower than an
--                  ocean's swell, but not nearly as much slower as the old
--                  single clock made it (which went as 1/k).
--
--   Q4 GLINT       the specular ring histogram at the default rung. The old
--                  window was a pair of absolute deviations and put 100% of
--                  the water in ring 0 -- the effect did not exist.
local ROOT = ... or "."

-- ------- stubs (see tests/waterbody_offline.lua)
local ImageData = {}
ImageData.__index = ImageData
function ImageData:setPixel(x, y, r, g, b, a)
  self.px[y * self.w + x] = { r, g, b, a }
end
function ImageData:getPixel(x, y)
  local p = self.px[y * self.w + x]
  if not p then return 0, 0, 0, 1 end
  return p[1], p[2], p[3], p[4]
end

local CLOCK = 12.0
love = {
  image = {
    newImageData = function(w, h)
      return setmetatable({ w = w, h = h, px = {} }, ImageData)
    end,
  },
  graphics = {
    newImage = function(d)
      return { data = d, setFilter = function() end, setWrap = function() end,
               release = function() end }
    end,
  },
  timer = { getTime = function() return CLOCK end },
}

local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  if name == "ModSetting" then
    local M = {}
    M.new = function(_, _, values)
      local s = { value = values[1] }
      function s:get() return self.value end
      function s:sync(v) self.value = v end
      return s
    end
    modules[name] = M
    return M
  end
  local path = ROOT .. "/lib/" .. name .. ".lua"
  local f = io.open(path, "rb")
  if not f then error("no module " .. name) end
  local src = f:read("*a"); f:close()
  src = src:gsub("^\239\187\191", "")            -- two lib files carry a BOM
  local v = assert((loadstring or load)(src, "@" .. path))(V)
  modules[name] = v
  return v
end

local WaterBody = V.require("WaterBody")
local Water = V.require("Water")

-- the same synthetic map the sibling test uses: a 4x4 pond and a 26x26 lake
local function isWater(_, cx, cy)
  if cx >= 4 and cx <= 7 and cy >= 4 and cy <= 7 then return true end
  if cx >= 12 and cx <= 37 and cy >= 12 and cy <= 37 then return true end
  return false
end
local state = {
  map = { id = "TEST", def = { width = 20, height = 20 }, isWaterCell = isWater },
  neighbors = {},
}

local fails = 0
local function check(name, cond, detail)
  print(("%s  %-46s %s"):format(cond and "PASS" or "FAIL", name, detail or ""))
  if not cond then fails = fails + 1 end
end

WaterBody.refresh(state)
if not WaterBody.on() then print("no field baked, aborting") os.exit(1) end
Water.setting:sync(0.8)          -- CALM, the default rung
Water.refreshLive()

local function at(cx, cz) return cx * 16 + 8, cz * 16 + 8 end
local pondX, pondZ = at(5, 5)
local lakeX, lakeZ = at(25, 25)
local rampX, rampZ = at(13, 25)  -- two cells in from the lake's west bank

-- ------- Q1
--
-- The argument of the long train, rebuilt here so its gradient can be taken
-- numerically. `off` moves the body away from the world origin WITHOUT moving
-- it out of the baked field -- the field is read in its own coordinates and
-- the wave term in absolute world pixels, which is exactly what a lake at the
-- far end of a route is. Sampling past the bake instead would clamp the field
-- to a constant and measure nothing.
local function argLong(wx, wz, off)
  off = off or 0
  local A = Water.WAVE_A
  local ph = Water.phase() * (1 + (Water.RATE_LONG - 1) * Water.DISPERSE)
           + Water.advectAt(wx + off, wz + off)
  return (wx + off) * A[1] + (wz + off) * A[2] - ph
end
local function localK(wx, wz, off)
  local d = 0.5
  local gx = (argLong(wx + d, wz, off) - argLong(wx - d, wz, off)) / (2 * d)
  local gz = (argLong(wx, wz + d, off) - argLong(wx, wz - d, off)) / (2 * d)
  return math.sqrt(gx * gx + gz * gz)
end

print("")
print("=== Q1 COHERENCE: |grad a| / |k| at the lake's shore ramp ===")
print("      (the size field ramps hardest here; 1.00x is the only right answer)")
print("")
print("      shore at        clock      measured")
local wantK = Water.WAVE_K[1]
local worst = 0
for _, off in ipairs({ 0, 1000, 4000 }) do
  for _, t in ipairs({ 12, 300, 3600 }) do
    CLOCK = t
    local r = localK(rampX, rampZ, off) / wantK
    if math.abs(r - 1) > worst then worst = math.abs(r - 1) end
    print(("      %-14s  %5.0fs      %6.3fx")
          :format(off == 0 and "origin" or ("+" .. off .. "px"), t, r))
  end
end
CLOCK = 12
print("")
check("the wave is the wave, everywhere and always", worst < 1e-6,
      ("worst deviation %.2e"):format(worst))

-- ------- Q2
print("")
print("=== Q2 SPECTRUM: how loud each train is ===")
print("      point            long     mid    short     sum")
local function row(name, wx, wz)
  local l, m, s = Water.bodyWeights(wx, wz)
  print(("      %-14s  %.3f   %.3f   %.3f   %.3f")
        :format(name, l, m, s, l + m + s))
  return l, m, s
end
local pl, pm, ps = row("pond", pondX, pondZ)
local rl, rm, rs = row("shore ramp", rampX, rampZ)
local ll, lm, ls = row("lake centre", lakeX, lakeZ)

check("weights partition (pond)", math.abs(pl + pm + ps - 1) < 1e-9, "")
check("weights partition (lake)", math.abs(ll + lm + ls - 1) < 1e-9, "")
-- open water is the build this replaced, exactly: 0.55 long / 0.45 mid and no
-- short chop at all. The end of the ramp nobody could see is the end that
-- changed, and a sea that shifted would be a regression, not a feature.
check("open water is unchanged (0.55 / 0.45 / 0)",
      math.abs(ll - 0.55) < 1e-6 and math.abs(lm - 0.45) < 1e-6 and ls < 1e-9,
      ("%.4f / %.4f / %.4f"):format(ll, lm, ls))
check("the pond is carried by the short train", ps > pl * 3,
      ("short %.3f vs long %.3f"):format(ps, pl))
-- one surviving train is corduroy: parallel stripes with no interference.
local function crossing(l, m, s)
  local n = 0
  if l > 0.02 then n = n + 1 end
  if m > 0.02 then n = n + 1 end
  if s > 0.02 then n = n + 1 end
  return n
end
check("at least two trains cross everywhere",
      crossing(pl, pm, ps) >= 2 and crossing(rl, rm, rs) >= 2
      and crossing(ll, lm, ls) >= 2,
      ("pond %d, ramp %d, lake %d"):format(crossing(pl, pm, ps),
       crossing(rl, rm, rs), crossing(ll, lm, ls)))

-- ------- Q3
print("")
print("=== Q3 DISPERSION: crest speed, short train vs long ===")
local kL, kS = Water.WAVE_K[1], Water.WAVE_K[3]
local cL = Water.RATE_LONG / kL
local cS = Water.RATE_SHORT / kS
local ideal = math.sqrt(kL / kS)
-- what the single clock the spectrum replaced would have given: one omega for
-- everything, so c ~ 1/k rather than 1/sqrt(k)
local oldRatio = kL / kS
print(("      |k|: long=%.5f  short=%.5f  (%.2fx shorter)")
      :format(kL, kS, kS / kL))
print(("      crest speed short/long:  spectrum %.3f   ideal %.3f   one-clock %.3f")
      :format(cS / cL, ideal, oldRatio))
check("matches the gravity-wave relation", math.abs(cS / cL - ideal) < 2e-4,
      ("%.5f vs %.5f"):format(cS / cL, ideal))
check("the single clock was too slow on short water", oldRatio < ideal * 0.75,
      ("%.3f vs %.3f"):format(oldRatio, ideal))

-- ------- Q4
print("")
print("=== Q4 GLINT: specular ring histogram at the default rung ===")
-- Sun pinned at 44.6 deg elevation, ground track along +X -- the geometry the
-- earlier measurement used, so the numbers are comparable to it.
local EL = math.rad(44.6)
local rY = -math.sin(EL)                 -- sunRay is the direction light TRAVELS
local rXZ = math.cos(EL)
local flat = -rY
local swell = Water.swell()
local steep = Water.STEEP_NOW or 0
print(("      swell=%.3f  steep=%.3f  flat=%.4f  |rXZ|=%.4f")
      :format(swell, steep, flat, rXZ))
print(("      gradMax: pond=%.5f  lake=%.5f")
      :format(Water.gradMaxAt(pondX, pondZ), Water.gradMaxAt(lakeX, lakeZ)))

local function smoothstep(e0, e1, x)
  if e1 <= e0 then return x >= e1 and 1 or 0 end
  local t = (x - e0) / (e1 - e0)
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  return t * t * (3 - 2 * t)
end

-- the vertex stage's analytic normal, rebuilt here
local function slopeAt(wx, wz)
  local A, B, C = Water.WAVE_A, Water.WAVE_B, Water.WAVE_C
  local wl, wm, ws = Water.bodyWeights(wx, wz)
  local amp = swell * Water.bodyAmp(wx, wz)
  local d = Water.DISPERSE
  local p = Water.phase()
  local adv = Water.advectAt(wx, wz)
  local pL = p * (1 + (Water.RATE_LONG - 1) * d) + adv
  local pM = p * (1 + (Water.RATE_MID - 1) * d) + adv
  local pS = p * (1 + (Water.RATE_SHORT - 1) * d) + adv
  local aL = wx * A[1] + wz * A[2] - pL
  local aM = wx * B[1] + wz * B[2] + pM
  local aS = wx * C[1] + wz * C[2] - pS
  local h = math.sin(aL) * wl + math.sin(aM) * wm + math.sin(aS) * ws
  local ah = h < 0 and -h or h
  local chain = 1 + 2 * steep * ah
  local gx = (A[1] * math.cos(aL) * wl + B[1] * math.cos(aM) * wm
            + C[1] * math.cos(aS) * ws) * chain
  local gz = (A[2] * math.cos(aL) * wl + B[2] * math.cos(aM) * wm
            + C[2] * math.cos(aS) * ws) * chain
  return gx * amp, gz * amp, ah
end

-- Sampled every STEP world pixels, not once per cell. The shader evaluates
-- this per FRAGMENT, and a 4x4 pond is sixteen cells -- reading it once per
-- cell asks whether sixteen arbitrary phases happen to include a crest, which
-- is a question about the sampling and not about the water.
local STEP = 4
local function ringsOver(c0, c1, mode)
  local hist = { [0] = 0, 0, 0, 0, 0 }
  local peak, n = 0, 0
  for wx = c0 * 16, (c1 + 1) * 16 - 1, STEP do
    for wz = c0 * 16, (c1 + 1) * 16 - 1, STEP do
      local sx, sz, ah = slopeAt(wx, wz)
      local len = math.sqrt(1 + sx * sx + sz * sz)
      local dot = (flat + sx * rXZ) / len         -- sun track along +X
      local lo, hi
      if mode == "old" then
        lo, hi = flat + 0.020, flat + 0.075       -- the absolute window
      else
        local gradMax = Water.gradMaxAt(wx, wz) * (1 + 2 * steep * ah)
        local devMax = math.max(swell * Water.bodyAmp(wx, wz) * gradMax * rXZ,
                                1e-5)
        lo = flat + Water.GLINT_LO * devMax
        hi = flat + Water.GLINT_HI * devMax
      end
      local s = smoothstep(lo, hi, dot)
      if s > peak then peak = s end
      hist[math.floor(s * 4 + 0.5)] = hist[math.floor(s * 4 + 0.5)] + 1
      n = n + 1
    end
  end
  return hist, peak, n
end

for _, mode in ipairs({ "old", "new" }) do
  local hist, peak, n = ringsOver(12, 37, mode)
  local lit = n - hist[0]
  print(("      lake %-4s peak s=%.4f  rings 0/1/2/3/4 = %d/%d/%d/%d/%d  lit %.1f%%")
        :format(mode, peak, hist[0], hist[1], hist[2], hist[3], hist[4],
                lit / n * 100))
  if mode == "old" then
    check("old window put the whole lake in ring 0", hist[0] == n,
          ("%d of %d"):format(hist[0], n))
  else
    check("new window lights part of the lake", lit > 0 and lit < n,
          ("%d of %d lit"):format(lit, n))
  end
end
-- and the puddle, which is the case the old absolute window could never have
-- reached: its swell is a fifth of the lake's, so an absolute floor measured
-- a slope it is five times further from making.
do
  local hist, peak, n = ringsOver(4, 7, "new")
  local lit = n - hist[0]
  print(("      pond new  peak s=%.4f  lit %d of %d (%.1f%%)")
        :format(peak, lit, n, lit / n * 100))
  check("the pond glints too", lit > 0, ("%d of %d"):format(lit, n))
end

print("")
print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
