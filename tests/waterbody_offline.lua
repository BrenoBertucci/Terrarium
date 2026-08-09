-- Offline check of the size-of-the-water field (lib/WaterBody.lua) and of
-- what lib/Water.lua does with it. NO GAME AND NO GPU: love.image and
-- love.graphics are stubbed to plain tables, the map is synthetic, and the
-- whole thing runs in any Lua 5.1+.
--
--   lua tests/waterbody_offline.lua [path-to-mod-root]
--
-- or, when there is no lua on PATH (the usual case on this machine):
--
--   py -c "from lupa import LuaRuntime; import pathlib; \
--          r=r'C:/Users/breno/Downloads/GBA/Terrarium'; \
--          LuaRuntime().eval('function(s,r) return (loadstring or load)(s)(r) end') \
--          (pathlib.Path(r+'/tests/waterbody_offline.lua').read_text(encoding='utf-8'), r)"
--
-- WHY THIS EXISTS as well as the in-game probe: the field is an algorithm --
-- a distance transform and a flood fill over a cell grid -- and an algorithm
-- is answerable without a frame. The first run of it caught a real inversion
-- (land was storing OPEN, so the swell grew INTO the shore instead of dying
-- on it) in under a second, which is not a thing a screenshot would have
-- made obvious. The probe is still what settles how it LOOKS.
local ROOT = ... or "."

-- ------- stubs
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
  timer = { getTime = function() return 12.0 end },
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

-- ------- a synthetic map: 20x20 BLOCKS = 40x40 cells
--   small pond   cells  4..7   x  4..7    (4x4)
--   big lake     cells 12..37  x 12..37   (26x26)
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
  print(("%s  %-44s %s"):format(cond and "PASS" or "FAIL", name, detail or ""))
  if not cond then fails = fails + 1 end
end

-- ------- 0. the fallback, before any bake
check("no field -> sizeAt is open water", Water.sizeAt(100, 100) == 1,
      ("sizeAt=%.3f"):format(Water.sizeAt(100, 100)))
check("no field -> bodyAmp is 1", Water.bodyAmp(100, 100) == 1,
      ("amp=%.3f"):format(Water.bodyAmp(100, 100)))
local fb = Water.bodyFreq(100, 100)
check("no field -> bodyFreq is the old sine",
      math.abs(fb - (0.90 + 0.35 * math.sin(100 * Water.BODY_KX)
                                 * math.cos(100 * Water.BODY_KZ))) < 1e-9,
      ("bf=%.4f"):format(fb))

-- ------- 1. bake
WaterBody.refresh(state)
check("field baked", WaterBody.on(), tostring(WaterBody.on()))
local f = WaterBody.field()
if not f then print("no field, aborting") os.exit(1) end
print(("      grid %dx%d step=%d origin=(%d,%d) span=%d")
      :format(f.w, f.h, f.step, f.ox, f.oz, f.span))

local function at(cx, cz) return cx * 16 + 8, cz * 16 + 8 end
local pondX, pondZ = at(5, 5)
local lakeX, lakeZ = at(25, 25)
local edgeX, edgeZ = at(13, 25)

local pond = Water.sizeAt(pondX, pondZ)
local lake = Water.sizeAt(lakeX, lakeZ)
local edge = Water.sizeAt(edgeX, edgeZ)
print(("      size: pond=%.3f  lakeMid=%.3f  lakeEdge=%.3f  land=%.3f")
      :format(pond, lake, edge, Water.sizeAt(at(1, 1))))

check("pond is small", pond < 0.30, ("%.3f"):format(pond))
check("lake middle is open", lake > 0.90, ("%.3f"):format(lake))
check("lake edge is calmer than its middle", edge < lake - 0.4,
      ("edge=%.3f mid=%.3f"):format(edge, lake))
-- fetch at the pond's centre is 2 cells = 0.20; its area term is
-- sqrt(16)/26 = 0.154. The AREA has to be what wins, or a pond is only ever
-- as calm as a channel of the same width -- which is the gap fetch cannot
-- close on its own and the reason both terms are measured.
check("area term is what caps the pond", pond < 0.20,
      ("pond=%.3f  (fetch alone would be ~0.20)"):format(pond))

-- ------- 2. amplitude AND wavelength both move
local ampPond, ampLake = Water.bodyAmp(pondX, pondZ), Water.bodyAmp(lakeX, lakeZ)
local bfPond, bfLake = Water.bodyFreq(pondX, pondZ), Water.bodyFreq(lakeX, lakeZ)
print(("      amp:  pond=%.3f lake=%.3f  (%.1fx)")
      :format(ampPond, ampLake, ampLake / ampPond))
print(("      freq: pond=%.3f lake=%.3f  (%.1fx shorter on the pond)")
      :format(bfPond, bfLake, bfPond / bfLake))
check("lake amplitude beats pond amplitude", ampLake > ampPond * 3,
      ("%.2fx"):format(ampLake / ampPond))
check("pond waves are shorter than lake waves", bfPond > bfLake * 2,
      ("%.2fx"):format(bfPond / bfLake))
check("pond keeps SOME amplitude", ampPond > 0.15, ("%.3f"):format(ampPond))

-- ------- 3. heightAt carries it into the surface the feet stand on
Water.setting:sync(0.8)   -- CALM
Water.refreshLive()
local hp, hl = 0, 0
for i = 0, 40 do
  local px, pz = at(4 + (i % 4), 4 + math.floor(i / 4) % 4)
  hp = math.max(hp, math.abs(Water.heightAt(px, pz)))
  local lx, lz = at(20 + (i % 8), 20 + math.floor(i / 8) % 8)
  hl = math.max(hl, math.abs(Water.heightAt(lx, lz)))
end
print(("      |heightAt| max: pond=%.4f lake=%.4f"):format(hp, hl))
check("the pond's surface moves less than the lake's", hl > hp * 2.5,
      ("%.2fx"):format(hl / math.max(hp, 1e-9)))

-- ------- 4. continuity, which is watertightness
-- Y = f(XZ) keeps the unindexed mesh sealed only while f is continuous, and
-- the size field is now a factor of f. A per-cell STEP here is a seam down
-- the middle of every lake -- and it is also how the land-holds-open
-- inversion showed itself, as a 0.9 jump in sixteen pixels at the bank.
local worst, wx0 = 0, 0
for x = 12 * 16, 20 * 16 do
  local d = math.abs(Water.sizeAt(x, lakeZ) - Water.sizeAt(x + 1, lakeZ))
  if d > worst then worst, wx0 = d, x end
end
print(("      worst 1px jump across the west bank: %.5f at x=%d")
      :format(worst, wx0))
check("size field is continuous (no per-cell step)",
      worst < (1 / WaterBody.FETCH_CELLS) / 16 * 1.6, ("%.5f"):format(worst))

-- ------- 5. a body that runs off the drawn world is OPEN
-- Its visible area is a lower bound, not its size: the sea at Vermilion
-- continues into Route 11 whether or not Route 11 is being rendered.
WaterBody.invalidate()
WaterBody.refresh({
  map = { id = "EDGE", def = { width = 20, height = 20 },
          isWaterCell = function(_, cx) return cx >= 36 end },
  neighbors = {},
})
local strip = Water.sizeAt(at(38, 20))
print(("      4-cell strip running off the map edge: size=%.3f"):format(strip))
check("a body running off the drawn world is not capped by area",
      strip > 0.10, ("%.3f"):format(strip))

print(fails == 0 and "\nALL PASS" or ("\n" .. fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
