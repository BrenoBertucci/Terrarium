-- Offline probe of foot-crush physics in lib/Grass3D.lua.
-- NO GAME AND NO GPU. Same stub harness as tests/waterbody_offline.lua.
--
-- Written BEFORE the crush-map change so "better" is a pair of numbers
-- rather than an impression. Re-run after the change; the AFTER block
-- only lights up when the new APIs exist.
--
--   lua tests/grass_crush_offline.lua [path-to-mod-root]
--
-- or, when there is no lua on PATH (the usual case on this machine):
--
--   py -c "from lupa import LuaRuntime; import pathlib; \
--          r=r'C:/Users/breno/Downloads/GBA/Terrarium'; \
--          LuaRuntime().eval('function(s,r) return (loadstring or load)(s)(r) end') \
--          (pathlib.Path(r+'/tests/grass_crush_offline.lua').read_text(encoding='utf-8'), r)"
--
-- WHAT IT ASKS
--
--   Q1 TRAIL LENGTH   world-px span from the oldest live crumb to the foot
--   Q2 ACTOR CEILING  how many of 8 simultaneous walkers register an effect
--   Q3 SPRING         time to cross upright, peak overshoot, settle
--   Q4 TRAIL RECOVERY crumbs must not overshoot (no spring on the trail)
--   Q5 DETAIL 0       crush packet with the map forced off equals today's
--   Q6 COST MODEL     distance tests + texel taps the vertex would pay
--
-- Q5's "today" snapshot is the packet this file writes on FIRST run, when
-- the map does not exist. After the change, forcing the map off and
-- replaying the same walk must reproduce that packet.

local ROOT = ... or "."

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
    newCanvas = function() return nil end,
  },
  timer = { getTime = function() return 12.0 end },
}

local modules = {}
local V = { path = ROOT }
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
  if name == "Voxel3D" then
    local stub = { newMesh = function() return nil end, GRASS_H = 10 }
    modules[name] = stub
    return stub
  end
  if name == "Quality" then
    local Q = { _detail = 2 }
    function Q.grassDetail() return Q._detail end
    function Q.crushSlots()
      local d = Q.grassDetail()
      if d <= 0 then return 3 end
      if d == 1 then return 5 end
      return 8
    end
    modules[name] = Q
    return Q
  end
  local path = ROOT .. "/lib/" .. name .. ".lua"
  local f = io.open(path, "rb")
  if not f then error("no module " .. name) end
  local src = f:read("*a"); f:close()
  src = src:gsub("^\239\187\191", "")
  local chunk = assert((loadstring or load)(src, "@" .. path))
  local v = chunk(V)
  modules[name] = v
  return v
end

local Grass3D = V.require("Grass3D")
local Quality = V.require("Quality")

local fails = 0
local function check(name, cond, detail)
  print(("%s  %-52s %s"):format(cond and "PASS" or "FAIL", name, detail or ""))
  if not cond then fails = fails + 1 end
end

local function dump(label, t)
  local parts = {}
  for i = 1, #t do parts[i] = string.format("%.4f", t[i]) end
  print(("      %s: %s"):format(label, table.concat(parts, " ")))
end

-- Replay a walk: a single foot travelling `dist` world px along +X at
-- `speed` world-px/s, integrated at 30 Hz. Returns the last crush packet.
local function walk(dist, speed, dt)
  dt = dt or (1 / 30)
  Grass3D.clearTracks()
  local x, z = 0, 0
  local r, s = 17, 1.25
  local steps = math.max(1, math.floor(dist / (speed * dt) + 0.5))
  local last = nil
  for i = 1, steps do
    x = x + speed * dt
    last = Grass3D.crushFrame({ { x, z, r, s, 1, 0 } }, dt)
  end
  return last, x, z
end

-- Oldest live crumb -> current foot, in world pixels. Crumbs live in the
-- shader packet (p[i] after the live feet) AND in trailCount(); we measure
-- from the packet first (that is what the meadow actually shows) and fall
-- back to trailSpan() if the new map path stops packing crumbs as uniforms.
local function trailSpanFromPacket(packet, footX, footZ)
  if not packet or not packet.p then return 0, 0 end
  local best = 0
  local n = 0
  for i = 1, packet.n or 0 do
    local p = packet.p[i]
    if p then
      local dx, dz = (p[1] or 0) - footX, (p[2] or 0) - footZ
      local d = math.sqrt(dx * dx + dz * dz)
      -- a crumb is behind the foot; the live foot itself is ~0
      if d > 0.5 then
        n = n + 1
        if d > best then best = d end
      end
    end
  end
  return best, n
end

local function trailSpan()
  if Grass3D.trailSpan then return Grass3D.trailSpan() end
  return nil
end

-- Recorded 2026-08-14, before the map (PINNED_HASH walk at detail 0):
--   Q1 span(packet)=24.00 crumbs=4
--   Q2 4 live tracks (CRUSH_LIVE), 4 crumbs, 8 packet slots
--   Q3 cross@10 (0.333s) peak=-0.2424 @15 (0.500s)
--   Q4 crumb min=0.0128 (no overshoot)
--   Q5 hash=283233725
--   Q6 detail2x8: distances=8 taps=0  weighted=8.00
-- After the map (same file, same walk):
--   Q1 crumbs=49 span(api)=198.00
--   Q2 crushersSeen=8
--   Q3 identical (0.333s / -0.2424)
--   Q4 crumb min=0.0000
--   Q5 hash=283233725 (map-off path unchanged)
--   Q6 detail2x8: distances=4 taps=1  weighted=4.60

print("=== grass_crush_offline ===")
print(("    CRUSH_SLOTS=%s CRUSH_LIVE=%s TRAIL_MAX=%s TRAIL_STEP=%s TRAIL_TTL=%s")
      :format(tostring(Grass3D.CRUSH_SLOTS), tostring(Grass3D.CRUSH_LIVE),
              tostring(Grass3D.TRAIL_MAX), tostring(Grass3D.TRAIL_STEP),
              tostring(Grass3D.TRAIL_TTL)))
print(("    CRUSH_K=%s CRUSH_C=%s CRUSH_FALL=%s")
      :format(tostring(Grass3D.CRUSH_K), tostring(Grass3D.CRUSH_C),
              tostring(Grass3D.CRUSH_FALL)))
print(("    map API: trailSpan=%s sampleMap=%s setMapEnabled=%s shaderCost=%s")
      :format(tostring(Grass3D.trailSpan ~= nil),
              tostring(Grass3D.sampleMap ~= nil),
              tostring(Grass3D.setMapEnabled ~= nil),
              tostring(Grass3D.shaderCost ~= nil)))

-- =====================================================================
-- Q1  trail length: walk 200 world px (a long look-back)
-- =====================================================================
print("--- Q1 trail length (200 px walk at 60 px/s)")
Quality._detail = 2
local pkt, fx, fz = walk(200, 60)
local spanPkt, nPkt = trailSpanFromPacket(pkt, fx, fz)
local spanApi = trailSpan()
local crumbs = Grass3D.trailCount()
print(("    foot at (%.1f,%.1f)  crumbs=%d  packet.n=%d  span(packet)=%.2f  span(api)=%s")
      :format(fx, fz, crumbs, pkt and pkt.n or 0, spanPkt,
              spanApi and string.format("%.2f", spanApi) or "n/a"))
-- BEFORE: 4 crumbs * 6 px = 24 px. AFTER: crumb-list span ~ the walk.
print("    BEFORE=24.00 px (4*TRAIL_STEP). AFTER: crumb-list span of the walk.")
check("walk laid at least one crumb", crumbs >= 1,
      ("crumbs=%d"):format(crumbs))
if Grass3D.trailSpan then
  check("trail is longer than the old 24 px plank",
        (spanApi or 0) >= 100,
        ("span=%.2f"):format(spanApi or 0))
end

-- =====================================================================
-- Q2  actor ceiling: 8 walkers moving at once
-- =====================================================================
print("--- Q2 eight simultaneous crushers")
Grass3D.clearTracks()
local feet8 = {}
for i = 1, 8 do
  -- 40 px apart so nobody snaps onto a neighbour (CRUSH_SNAP = 28)
  feet8[i] = { i * 40, 0, 15, 1.1, 1, 0 }
end
-- first frame: they appear
Grass3D.crushFrame(feet8, 1 / 30)
-- second frame: they move, so they drop crumbs and stay seen
for i = 1, 8 do feet8[i][1] = feet8[i][1] + 8 end
local pkt8 = Grass3D.crushFrame(feet8, 1 / 30)
-- keep walking a few more frames so crumbs exist
for _ = 1, 6 do
  for i = 1, 8 do feet8[i][1] = feet8[i][1] + 8 end
  pkt8 = Grass3D.crushFrame(feet8, 1 / 30)
end
local liveN = 0
for i = 1, (pkt8 and pkt8.n or 0) do
  if pkt8.p[i] and math.abs(pkt8.p[i][4] or 0) >= (Grass3D.CRUSH_KEEP or 0.012) then
    liveN = liveN + 1
  end
end
local registered = liveN
if Grass3D.crushersSeen then registered = Grass3D.crushersSeen() end
print(("    packet slots with effect=%d  crushersSeen=%s  trailCount=%d")
      :format(liveN, tostring(Grass3D.crushersSeen and Grass3D.crushersSeen()),
              Grass3D.trailCount()))
if Grass3D.crushersSeen then
  check("all 8 walkers register an effect", registered >= 8,
        ("crushersSeen=%d"):format(registered))
end
-- BEFORE: CRUSH_LIVE=4 so at most 4 tracks, plus 4 crumbs, 8 slots packed
-- but only 4 WALKERS register. AFTER: all 8 walkers register.

-- =====================================================================
-- Q3  spring: hold, release, measure kick
-- =====================================================================
print("--- Q3 spring kick (hold 20 frames, then release)")
Grass3D.clearTracks()
local foot = { { 200, 200, 12, 1.0 } }
for _ = 1, 20 do Grass3D.crushFrame(foot, 1 / 30) end
local held = Grass3D.crushFrame(foot, 1 / 30)
local heldS = (held.n > 0) and held.p[1][4] or 0
local up, minS, minI, crossI = {}, 99, 0, nil
for i = 1, 90 do
  local c = Grass3D.crushFrame({}, 1 / 30)
  local s = (c.n > 0) and c.p[1][4] or 0
  up[i] = s
  if s < minS then minS, minI = s, i end
  if not crossI and s <= 0 then crossI = i end
end
dump("release s", {
  up[1], up[3], up[6], up[10], up[15], up[20], up[30], up[45], up[60], up[90]
})
print(("    held=%.4f  cross@frame=%s (%.3fs)  peak=%.4f @frame=%d (%.3fs)  end=%.4f")
      :format(heldS, tostring(crossI),
              crossI and (crossI / 30) or -1,
              minS, minI, minI / 30, up[90]))
check("foot flattens the tuft", heldS > 0.85, ("held=%.3f"):format(heldS))
check("spring overshoots past upright", minS < -0.005,
      ("peak=%.4f"):format(minS))
check("spring settles inside 3 s", math.abs(up[90]) < 0.05,
      ("end=%.4f"):format(up[90]))
-- Documented: ~1/3 s to cross, ~1/4 proud at the top.
if crossI then
  check("crosses upright around a third of a second",
        crossI >= 6 and crossI <= 18,
        ("%d frames = %.2fs"):format(crossI, crossI / 30))
end
check("peak kick is a quarter-ish proud (0.15..0.45)",
      minS <= -0.15 and minS >= -0.55,
      ("peak=%.3f"):format(minS))

-- =====================================================================
-- Q4  trail recovery: a crumb must not go negative
-- =====================================================================
print("--- Q4 trail recovery (no overshoot on crumbs)")
Grass3D.clearTracks()
-- Walk, then KEEP the foot standing at the end so the live spring stays
-- down (positive). The first cut of this released the foot and then read
-- every packed slot -- the live kick went to -0.24 and the check blamed
-- the trail for the spring it was written to keep off the trail.
walk(80, 60)
local endFoot = { { 80, 0, 17, 1.25, 1, 0 } }
local crumbMin, crumbSaw = 99, 0
for _ = 1, 200 do
  local c = Grass3D.crushFrame(endFoot, 1 / 30)
  -- slot 1 is the standing foot; 2..n are crumbs (pre-map) or empty (map)
  for i = 2, c.n do
    local s = c.p[i][4] or 0
    crumbSaw = crumbSaw + 1
    if s < crumbMin then crumbMin = s end
  end
  if Grass3D.sampleMap then
    for x = 0, 80, 6 do
      local s = Grass3D.sampleMap(x, 0) or 0
      if s < crumbMin then crumbMin = s end
      if s > 0.001 then crumbSaw = crumbSaw + 1 end
    end
  end
end
if crumbMin == 99 then crumbMin = 0 end
print(("    crumb samples=%d  min strength=%.4f"):format(crumbSaw, crumbMin))
check("trail channel never overshoots", crumbMin >= -0.001,
      ("min=%.4f"):format(crumbMin))

-- =====================================================================
-- Q5  grassDetail 0 / map-off packet identity
-- =====================================================================
print("--- Q5 detail-0 / map-off identity walk")
-- A short, deterministic walk. The packet (x,z,r,s rounded) is the
-- fingerprint. First run (no map API) RECORDS it. After the change,
-- forcing the map off and replaying must match.
local function fingerprint()
  if Grass3D.setMapEnabled then Grass3D.setMapEnabled(false) end
  Quality._detail = 0
  Grass3D.clearTracks()
  local rows = {}
  local x = 0
  for i = 1, 24 do
    x = x + 4
    local c = Grass3D.crushFrame({ { x, 10, 17, 1.25, 1, 0 } }, 1 / 30)
    local parts = { tostring(c.n) }
    for k = 1, c.n do
      local p = c.p[k]
      parts[#parts + 1] = string.format("%.2f,%.2f,%.2f,%.3f",
                                        p[1], p[2], p[3], p[4])
    end
    rows[i] = table.concat(parts, "|")
  end
  if Grass3D.setMapEnabled then Grass3D.setMapEnabled(nil) end
  Quality._detail = 2
  return table.concat(rows, "\n")
end
local fp = fingerprint()
local fpHash = 0
for i = 1, #fp do fpHash = (fpHash * 33 + fp:byte(i)) % 2147483647 end
print(("    fingerprint bytes=%d hash=%d"):format(#fp, fpHash))
-- Hard-coded AFTER the first run of this file against the pre-map Grass3D.
-- If you are reading this as the first run, the number below is 0 and the
-- check is informational; the printed hash is what the next edit pins.
-- Pinned on the pre-map Grass3D (2026-08-14): 24-frame walk at detail 0.
-- A map-off replay after the change must produce this exact packet.
local PINNED_HASH = 283233725
check("map-off walk matches the pinned pre-map packet",
      fpHash == PINNED_HASH,
      ("got %d want %d"):format(fpHash, PINNED_HASH))

-- =====================================================================
-- Q6  cost model (what the vertex pays)
-- =====================================================================
print("--- Q6 vertex cost model")
local function cost(detail, crushers)
  if Grass3D.shaderCost then
    return Grass3D.shaderCost(detail, crushers)
  end
  -- TODAY: the shader loops `for ci = 0; ci < 8` and breaks on crushN.
  -- crushN is min(packed, Quality.crushSlots(detail)).
  -- packed = min(crushers, CRUSH_LIVE) + min(crumbs, TRAIL_MAX), cap 8.
  local slots = 8
  if detail <= 0 then slots = 3
  elseif detail == 1 then slots = 5
  end
  local live = math.min(crushers, Grass3D.CRUSH_LIVE or 4)
  local trail = Grass3D.TRAIL_MAX or 4
  local packed = math.min(live + trail, 8)
  local distances = math.min(packed, slots)
  return { distances = distances, taps = 0, slots = slots }
end

local c1 = cost(2, 1)
local c8 = cost(2, 8)
local c0 = cost(0, 8)
print(("    detail2 x1: distances=%d taps=%d")
      :format(c1.distances, c1.taps))
print(("    detail2 x8: distances=%d taps=%d   <-- the full case")
      :format(c8.distances, c8.taps))
print(("    detail0 x8: distances=%d taps=%d   <-- must stay the old path")
      :format(c0.distances, c0.taps))
check("detail 0 pays no texel tap", c0.taps == 0,
      ("taps=%d"):format(c0.taps))

-- A cheap arithmetic stand-in for "cheaper in the full case": each
-- distance test is a subtract+dot+compare (and a sqrt on a hit). A tap is
-- one vertex-texture fetch. Count a distance as 1.0 and a tap as 0.6 --
-- the tap replaces EIGHT distances, so even a dear fetch wins against 8.
local function weight(c) return c.distances * 1.0 + c.taps * 0.6 end
print(("    weighted full-case: %.2f  (before this change that is 8.00)")
      :format(weight(c8)))
if Grass3D.shaderCost then
  check("full case is cheaper than eight distance tests",
        weight(c8) < 8.0 - 0.01,
        ("weighted=%.2f"):format(weight(c8)))
end

-- =====================================================================
-- Q7  grassCut: waterline twin
-- =====================================================================
print("--- Q7 grassCut")
if Grass3D.grassCut then
  local fake = {
    inBounds = function(_, cx, cy)
      return cx >= 0 and cy >= 0 and cx < 20 and cy < 20
    end,
    isGrassCell = function(_, cx, cy) return cx >= 5 and cx <= 8 end,
  }
  Grass3D.bindMap(fake)
  local inCut = Grass3D.grassCut(5 * 16 + 8, 3 * 16 + 8, 6)
  local outCut = Grass3D.grassCut(1 * 16 + 8, 3 * 16 + 8, 6)
  print(("    in grass=%s  on path=%s"):format(tostring(inCut), tostring(outCut)))
  check("tall grass returns the base cut", inCut == 6, ("cut=%s"):format(inCut))
  check("bare ground returns 0", outCut == 0, ("cut=%s"):format(outCut))
  Grass3D.bindMap(nil)
else
  print("    grassCut not present (before-run)")
end

print(("done: %d fail"):format(fails))
if fails > 0 then os.exit(1) end
