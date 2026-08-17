-- Voxel world mode: authored 3D grass tufts.
--
-- The classic path extrudes the tileset's 8x8 grass graphic into a two-sided
-- slab (Structures.grassTemplate). That reads as Gen 1, and it is free, but
-- it has no thickness and no room for real wind or foot-crush.
--
-- Drop an optimized bake under assets/ground/grass/ (grass.mesh.bin +
-- grass.png, produced by tools/optimize_grass_glb.py from a source GLB) and
-- this file stamps a real triangle tuft on every tall-grass tile instead.
-- Same mesh every time, random yaw/scale per cell so a meadow is not a
-- clone stamp. Wind, foot-crush and the camera-ward pull all ride the
-- existing grass pass (VoxelScene) -- the only new contract is that the
-- mesh is textured from grass.png rather than the tileset atlas.
--
-- The GRASS options row picks the path:
--   3D     authored tufts when the bake is present (default)
--   VOXEL  classic tileset slab, even if the bake is on disk
-- If the bake is missing or unreadable, available() is false either way and
-- Structures falls back to the slab -- this file never throws into the mesh
-- build.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local Voxel3D = V.require("Voxel3D")

local Grass3D = {}

-- mesh first = default when the bake ships with the mod
Grass3D.setting = ModSetting.new("grass3d", "GRASS",
                                 { "mesh", "voxel" },
                                 { "3D", "VOXEL" })

function Grass3D.wantsMesh()
  return Grass3D.setting:get() == "mesh"
end

-- Triangles a single tuft may cost, and it is a SMALL number on purpose.
-- Structures.buildGrass walks half-tiles, so one grass CELL is four of
-- these; at three hundred cells the template is copied twelve hundred
-- times. The shipped bake was 1800 and came to two million vertices in one
-- Lua-built mesh. See the budget note in loadTemplate.
Grass3D.MAX_TRIS = 40

-- And a ceiling on the meadow itself, for a map denser than any of Kanto's.
-- Past this the whole map takes the tileset slab: a hard limit that trips
-- is a frame that draws, and there is no honest way to draw half a meadow
-- in one mesh when the other half needs a different texture.
Grass3D.MAX_TUFTS = 6000

Grass3D.ASSET_DIR = "assets/ground/grass/"
Grass3D.META = "grass.meta.json"
Grass3D.BIN = "grass.mesh.bin"
Grass3D.TEX = "grass.png"

-- Template verts: { {x,y,z,u,v,shade}, ... } and 1-based triangle indices.
local tpl = nil          -- nil = untried, false = unavailable
local tex = nil          -- Image | false
local meta = nil

local function assetPath(name)
  return V.path .. "/" .. Grass3D.ASSET_DIR .. name
end

local function loadTexture()
  if tex ~= nil then return tex or nil end
  local okA, Assets = pcall(require, "src.render.Assets")
  if not okA or not Assets then
    tex = false
    return nil
  end
  local path = assetPath(Grass3D.TEX)
  local okE, exists = pcall(Assets.exists, path)
  if not (okE and exists) then
    tex = false
    return nil
  end
  local ok, img = pcall(Assets.image, path)
  if not (ok and img) then
    tex = false
    return nil
  end
  pcall(img.setFilter, img, "nearest", "nearest")
  tex = img
  return img
end

-- Read a little-endian float32 from a string at 0-based offset.
local function f32(s, o)
  local b1, b2, b3, b4 = s:byte(o + 1, o + 4)
  if not b4 then return 0 end
  local u = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
  local sign = 1
  if u >= 0x80000000 then
    sign = -1
    u = u - 0x80000000
  end
  local exp = math.floor(u / 0x800000) % 0x100
  local mant = u % 0x800000
  if exp == 0 then
    if mant == 0 then return sign * 0.0 end
    return sign * math.ldexp(mant / 0x800000, -126)
  elseif exp == 255 then
    if mant == 0 then return sign * math.huge end
    return 0 / 0
  end
  return sign * math.ldexp(1 + mant / 0x800000, exp - 127)
end

local function u16(s, o)
  local b1, b2 = s:byte(o + 1, o + 2)
  if not b2 then return 0 end
  return b1 + b2 * 256
end

local function u32(s, o)
  local b1, b2, b3, b4 = s:byte(o + 1, o + 4)
  if not b4 then return 0 end
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function readBinary(name)
  local rel = Grass3D.ASSET_DIR .. name
  local abs = assetPath(name)

  -- 0. the engine's own sanctioned route for a mod reading its own files.
  -- Tried FIRST because it is the one the loader actually wants; the rest
  -- are fallbacks for the source tree and for headless probes.
  if V.mod and V.mod.read then
    local ok, data = pcall(V.mod.read, V.mod, rel)
    if ok and type(data) == "string" and #data > 0 then return data end
    ok, data = pcall(V.mod.read, V.mod, name)
    if ok and type(data) == "string" and #data > 0 then return data end
  end

  -- 1. love.filesystem, IF this build lets a mod touch it at all.
  --
  -- THE WHOLE BLOCK IS INSIDE ONE pcall, AND THAT IS THE FIX.
  --
  -- The previous cut wrapped only the reads:
  --
  --     if love and love.filesystem and love.filesystem.read then
  --       local ok, data = pcall(love.filesystem.read, rel)
  --
  -- which looks defensive and is not, because this engine does not merely
  -- omit love.filesystem for mods -- it installs a proxy that RAISES ON
  -- FIELD ACCESS: "love.filesystem is not available to mods, use
  -- mod.storage and mod:read". So the `love.filesystem.read` in the *guard*
  -- threw, outside every pcall, before the guarded call was ever reached.
  --
  -- That error walked straight out of Grass3D.available() into
  -- Structures.buildGrass and into the chunk build -- which is exactly the
  -- thing the header of this file promises never happens. Selecting
  -- GRASS = 3D took the pause menu with it because the mesh build is not a
  -- place that expects to catch anything.
  do
    local ok, data = pcall(function()
      local lf = love and rawget(love, "filesystem")
      if not (lf and lf.read) then return nil end
      local d = lf.read(rel)
      if type(d) == "string" and #d > 0 then return d end
      d = lf.read(abs)
      if type(d) == "string" and #d > 0 then return d end
      return nil
    end)
    if ok and type(data) == "string" and #data > 0 then return data end
  end
  -- 2. engine Assets helper, if it has a raw read
  local okA, Assets = pcall(require, "src.render.Assets")
  if okA and Assets then
    if Assets.read then
      local ok, data = pcall(Assets.read, abs)
      if ok and type(data) == "string" and #data > 0 then return data end
      ok, data = pcall(Assets.read, rel)
      if ok and type(data) == "string" and #data > 0 then return data end
    end
  end
  -- 3. native file (desktop absolute path under V.path)
  if io and io.open then
    local f = io.open(abs, "rb")
    if f then
      local data = f:read("*a")
      f:close()
      if type(data) == "string" and #data > 0 then return data end
    end
  end
  return nil
end

local function loadTemplate()
  if tpl ~= nil then return tpl or nil end
  local blob = readBinary(Grass3D.BIN)
  if type(blob) ~= "string" or #blob < 16 then
    tpl = false
    return nil
  end
  local nv, ni = u32(blob, 0), u32(blob, 4)
  local height, radius = f32(blob, 8), f32(blob, 12)
  if nv < 3 or ni < 3 or nv > 20000 or ni > 60000 then
    tpl = false
    return nil
  end

  -- ------- THE BUDGET, and why refusing a bake is the honest answer
  --
  -- This template is not drawn once. Structures.buildGrass STAMPS IT ON
  -- EVERY TALL-GRASS TILE (see grassInstances there), and nothing between
  -- here and the vertex buffer counts what that comes to. So the only
  -- number that matters about a tuft is its cost TIMES the meadow.
  --
  -- The shipped bake was 1800 triangles and 1719 vertices per tuft, which
  -- tools/optimize_grass_glb.py had decimated down to -- its MAX_TRIS was
  -- set to 1800, and that is a budget for a model you look at, not for one
  -- you stamp three hundred times. A route with three hundred grass cells
  -- came to half a million triangles and half a million vertices in one
  -- meadow, on an integrated GPU, and the failure was not graceful: the
  -- OPTIONS row took the pause menu down with it.
  --
  -- The header above this file promises "this file never throws into the
  -- mesh build". It could not keep that promise, because nothing here ever
  -- looked at how big the thing it was handing over was. This is that look.
  --
  -- Refusing is deliberate and it is not a degradation to be sorry about:
  -- Structures falls back to the tileset slab, which is the classic Gen 1
  -- path, is free, and is what VOXEL selects on purpose. A meadow that
  -- draws beats a meadow that is correct and does not.
  local tris = math.floor(ni / 3)
  if tris > Grass3D.MAX_TRIS then
    tpl = false
    if V.mod and V.mod.log then
      pcall(V.mod.log.warn, V.mod.log,
            "grass bake refused: %d tris per tuft, budget is %d. This mesh "
            .. "is stamped on EVERY tall-grass tile, so %d cells would cost "
            .. "%d triangles. Falling back to the tileset slab. Re-bake with "
            .. "a lower MAX_TRIS in tools/optimize_grass_glb.py.",
            tris, Grass3D.MAX_TRIS, 300, tris * 300)
    end
    return nil
  end
  local need = 16 + nv * 24 + ni * 2
  if #blob < need then
    tpl = false
    return nil
  end
  local verts, indices = {}, {}
  local o = 16
  for i = 1, nv do
    local x = f32(blob, o); local y = f32(blob, o + 4); local z = f32(blob, o + 8)
    local u = f32(blob, o + 12); local v = f32(blob, o + 16); local sh = f32(blob, o + 20)
    verts[i] = { x, y, z, u, v, sh }
    o = o + 24
  end
  for i = 1, ni do
    -- LOVE vertex maps are 1-based
    indices[i] = u16(blob, o) + 1
    o = o + 2
  end
  tpl = {
    verts = verts,
    indices = indices,
    height = height,
    radius = radius,
  }
  meta = { height = height, radius = radius, verts = nv, indices = ni }
  return tpl
end

function Grass3D.available()
  -- Player chose the classic slab, or the bake is not on disk: Structures
  -- takes the tileset path. Checking the setting first so a VOXEL preference
  -- never pays to decode the mesh only to throw it away.
  if not Grass3D.wantsMesh() then return false end
  return loadTemplate() ~= nil and loadTexture() ~= nil
end

-- Remesh every map when the row flips: grassInstances vs grassQuads are
-- chosen at Structures.buildGrass time, so a live toggle has to drop the
-- cached meshes or the meadow keeps the shape it was built with.
local function remesh()
  pcall(function()
    V.require("ChunkMesher").invalidate()
  end)
end

-- OPTIONS row: cycle then rebuild. The manager page writes through
-- mod.options_changed (main.lua), which also calls remesh for this key.
function Grass3D.setting:row()
  local self_ = self
  return {
    id = ((V.mod and V.mod.id) or "TERRARIUM") .. ":" .. self.key,
    label = self.label,
    value = function() return self_.labels[self_:read()] end,
    step = function(game, dir)
      self_:cycle(game, dir)
      remesh()
      return true
    end,
  }
end

function Grass3D.onOptionsChanged(value)
  Grass3D.setting:sync(value)
  remesh()
end

function Grass3D.texture()
  return loadTexture()
end

function Grass3D.meta()
  loadTemplate()
  return meta
end

-- Deterministic hash in 0..1 from tile coords.
local function unit(tx, ty, salt)
  local n = tx * 374761393 + ty * 668265263 + (salt or 0) * 1274126177
  n = (n * 1103515245 + 12345) % 2147483647
  if n < 0 then n = -n end
  return (n % 100000) / 100000
end

-- Append one rotated/scaled instance of the template into verts/indices.
local function stamp(verts, indices, tplV, tplI, ox, oz, yaw, scale)
  local c, s = math.cos(yaw), math.sin(yaw)
  local base = #verts
  for i = 1, #tplV do
    local v = tplV[i]
    local x, y, z = v[1] * scale, v[2] * scale, v[3] * scale
    local rx = x * c - z * s
    local rz = x * s + z * c
    -- VertexShade: magnitude is cel shade, sign is face-up (snow). Positive
    -- = not sky-facing; negative = up. Grass blades are mostly sides.
    local shade = v[6] or 0.8
    if shade < 0.05 then shade = 0.05 end
    verts[base + i] = { ox + rx, y, oz + rz, v[4], v[5], shade }
  end
  for i = 1, #tplI do
    indices[#indices + 1] = tplI[i] + base
  end
end

-- Build the whole-map grass mesh from instance records
-- `{ wx, wz [, yaw, scale] }` (world-pixel tile origin, not cell centre).
function Grass3D.meshFromInstances(instances)
  local t = loadTemplate()
  if not t or not instances or #instances == 0 then return nil end
  -- Denser than the ceiling: hand back nil and let ChunkMesher take the
  -- slab path for this map whole. Half a meadow is not an option -- the
  -- two paths carry different textures, so they cannot share a mesh.
  if #instances > Grass3D.MAX_TUFTS then
    if V.mod and V.mod.log then
      pcall(V.mod.log.warn, V.mod.log,
            "grass: %d tufts on this map is over the %d ceiling -- using "
            .. "the tileset slab here", #instances, Grass3D.MAX_TUFTS)
    end
    return nil
  end
  -- The build budget is a coroutine deadline the chunk builder already
  -- runs on (lib/BuildBudget). Structures.buildGrass ticks it per tile;
  -- this loop never did, so it was the one uninterruptible stretch in the
  -- whole build -- and the longest, because it is per tuft rather than
  -- per cell. Ticking here is what lets a big meadow arrive over frames
  -- instead of as one stall.
  local Budget = nil
  do
    local okB, B = pcall(V.require, "BuildBudget")
    if okB then Budget = B end
  end
  local verts, indices = {}, {}
  local tplV, tplI = t.verts, t.indices
  for i = 1, #instances do
    if Budget and Budget.tick then Budget.tick() end
    local inst = instances[i]
    local wx = inst.wx or 0
    local wz = inst.wz or 0
    local yaw = inst.yaw or 0
    local scale = inst.scale or 1
    -- centre the tuft in its 8x8 tile
    stamp(verts, indices, tplV, tplI, wx + 4, wz + 4, yaw, scale)
  end
  local mesh = Voxel3D.newMesh(verts, indices)
  if mesh and loadTexture() then
    pcall(mesh.setTexture, mesh, loadTexture())
  end
  return mesh
end

-- One instance record for a grass TILE at (tx, ty) in tile coords.
function Grass3D.instanceForTile(tx, ty)
  local yaw = unit(tx, ty, 1) * math.pi * 2
  local scale = 0.82 + unit(tx, ty, 2) * 0.36
  return {
    wx = tx * 8,
    wz = ty * 8,
    yaw = yaw,
    scale = scale,
  }
end

-- Crush points for the grass pass this frame: player + roamers that are
-- walking on tall grass. Populated by Grass3D.gatherCrush from VoxelScene
-- and sent into the scene shader as up to 8 packed vec4s.
-- Eight slots, not four: the first few are feet standing in the meadow
-- right now and the rest are the TRAIL behind them (see crushFrame).
local crush = { n = 0, p = {} }
for i = 1, 8 do crush.p[i] = { 0, 0, 0, 0, 0, 0 } end

function Grass3D.clearCrush()
  crush.n = 0
end

-- Add a foot at world (wx, wz). `strength` 0..1, `radius` world px.
-- Optional pushDir {dx,dz} is the walk bearing so the shader can open a
-- wake ahead of the foot, not only a radial dent.
function Grass3D.addCrush(wx, wz, radius, strength, pushDir)
  if crush.n >= 8 then return end
  crush.n = crush.n + 1
  local p = crush.p[crush.n]
  p[1] = tonumber(wx) or 0
  p[2] = tonumber(wz) or 0
  p[3] = tonumber(radius) or 10
  p[4] = tonumber(strength) or 1
  if type(pushDir) == "table" then
    p[5] = tonumber(pushDir[1]) or 0
    p[6] = tonumber(pushDir[2]) or 0
  else
    p[5], p[6] = 0, 0
  end
end

function Grass3D.crushCount()
  return crush.n
end

-- ------- and the part a per-frame list cannot do: SPRING-BACK
--
-- Rebuilding the crush list from who is standing where, every frame, gives
-- grass that is flattened while a foot is in it and perfectly upright the
-- instant that foot leaves. That is not what a plant does. It is also the
-- single most visible thing wrong with foot-crush, because the eye is
-- already tracking the walker and lands on the tuft behind them.
--
-- So the list is kept BETWEEN frames instead, and each slot carries a
-- strength AND a velocity. Going down it is a plain fast chase -- a boot
-- does not bounce on its way into the ground. Coming back up it is a
-- damped SPRING, integrated rather than eased, and the difference is the
-- whole point: an ease can only approach upright from below and stops
-- being visible the moment it is close, while a spring carries momentum
-- through upright, overshoots, and comes back. That little kick past
-- vertical is what the eye reads as a plant standing up rather than as a
-- flattened patch fading out.
--
-- Underdamped on purpose: zeta below 1. At K=46 and C=5 the tuft passes
-- upright about a third of a second after the foot lifts, stands roughly a
-- quarter proud at the top of the kick half a second in, and is settled
-- inside two seconds -- grass, not jelly.
-- ------- and the part a spring cannot do either: the TRAIL
--
-- The spring is right about one tuft and wrong about a WALK. Somebody
-- crossing a meadow parts it the whole way, and what they leave behind is
-- a line of laid grass that stands up over several seconds -- a path you
-- can look back at and see where you came from. A springy foot gives none
-- of that: the crush is a disc that follows the walker, and two steps
-- later there is no evidence anybody was ever there.
--
-- So a moving foot DROPS CRUMBS. Every TRAIL_STEP world pixels it leaves a
-- weaker, narrower crush at the place it just left, and that crumb fades
-- on its own clock over TRAIL_TTL -- no spring, because a blade that has
-- been walked flat and left does not snap back, it recovers.
--
-- The eight shader slots are split rather than shared: live feet take the
-- first CRUSH_LIVE, the trail takes what is left. A fixed split means a
-- crowd of roamers can never crowd the trail out, and a long walk can
-- never crowd out the foot that is actually in the grass.
-- Heavier, faster lay-down so a boot reads as parting the meadow rather
-- than gently dimming it. Spring still kicks past upright on release.
Grass3D.CRUSH_FALL = 28.0     -- per second, toward a foot that is present (snappy part)
Grass3D.CRUSH_K = 48.0        -- spring stiffness on the way back up
Grass3D.CRUSH_C = 5.0         -- and its damping (below critical: it kicks)
Grass3D.CRUSH_KEEP = 0.012    -- below this, and still, a slot is done
-- How far a foot may travel between frames and still be recognised as the
-- same foot. Twenty rather than ten because this machine is not the only
-- machine: at twenty frames a second a walking sprite covers most of a
-- tile per frame, and a snap too tight turns one walker into a stream of
-- one-frame strangers -- each opening a slot, none of them living long
-- enough to drop a crumb.
Grass3D.CRUSH_SNAP = 28       -- world px a foot may move and stay the same slot
Grass3D.CRUSH_SLOTS = 8       -- what the shader takes (Voxel3D.CRUSH_SLOTS)
Grass3D.CRUSH_LIVE = 4        -- live feet (player + a few mons)

-- Trail: denser crumbs, wider disc, longer life -- a walk leaves a visible
-- corridor that recovers, not a row of faint dents.
Grass3D.TRAIL_STEP = 6        -- world px a foot travels between crumbs
Grass3D.TRAIL_TTL = 6.0       -- seconds a crumb takes to fade out entirely
Grass3D.TRAIL_STR = 1.15      -- how hard a crumb lies, against the foot's own
Grass3D.TRAIL_RAD = 14        -- world px -- path wide enough to read as a wake
Grass3D.TRAIL_MAX = 4         -- crumbs packed as uniforms when the map is off

-- ------- the crush MAP (trail lives here; live feet stay on uniforms)
--
-- Eight vec4 uniforms is a compile-time ceiling. Four of them are live
-- feet and four are crumbs, so the whole trail is 4 * TRAIL_STEP = 24
-- world pixels -- a plank and a half -- and a fifth walker flattens
-- nothing. A small field in world XZ, written on the CPU and sampled
-- once per vertex, is the trail the comment above actually asked for.
-- Live feet stay on uniforms: that is what the underdamped spring is
-- for, and a single decay on a field cannot do the kick.
--
-- ImageData + Image, not a new render target. 128*128 is 16 KB; a
-- canvas switch on the target UHD is the cost this is written to avoid.
-- Vertex-texture fetch is the same contract waterField already pays.
-- grassDetail 0, or a driver that will not make the image, keeps the
-- uniform trail exactly as it was (see tests/grass_crush_offline.lua,
-- PINNED_HASH).
Grass3D.MAP_RES = 128
Grass3D.MAP_WORLD = 384       -- 3 world px / texel; ~2 GB screens
Grass3D.TRACK_MAX = 32        -- CPU tracks when the map is on
Grass3D.TRAIL_CPU = 96        -- crumbs kept when the map is on
Grass3D.GRASS_CUT = 6         -- sprite-cut in tall grass (waterline twin)

-- live slots: { x, z, r, s, v, tgt, seen, lx, lz, pdx, pdz (walk bearing) }
local tracks = {}
-- crumbs: { x, z, r, s0, t, pdx, pdz }
local trail = {}

-- Crush map (CPU field, uploaded when a real Image can be made).
local mapForce = nil          -- nil = Quality.grassDetail, true/false = test
local mapOx, mapOz = 0, 0
local mapFocus = false
local mapS, mapDx, mapDz, mapLive = {}, {}, {}, {}
local mapIdata, mapImg = nil, nil   -- nil untried, false unavailable
local mapBound = nil          -- current overworld map, for grassCut
local seenThisFrame = 0

local function mapWanted()
  if mapForce == false then return false end
  if mapForce == true then return true end
  local ok, Q = pcall(V.require, "Quality")
  if ok and Q and Q.grassDetail then
    local d = tonumber(Q.grassDetail())
    return d ~= nil and d >= 1
  end
  return false
end

function Grass3D.setMapEnabled(v)
  mapForce = v
end

function Grass3D.mapWanted()
  return mapWanted()
end

function Grass3D.bindMap(map)
  mapBound = map
end

function Grass3D.setFocus(wx, wz)
  wx, wz = tonumber(wx) or 0, tonumber(wz) or 0
  local texel = Grass3D.MAP_WORLD / Grass3D.MAP_RES
  local half = Grass3D.MAP_WORLD * 0.5
  mapOx = math.floor((wx - half) / texel) * texel
  mapOz = math.floor((wz - half) / texel) * texel
  mapFocus = true
end

function Grass3D.grassCut(wx, wz, baseCut)
  local map = mapBound
  if not (map and map.isGrassCell) then
    pcall(function()
      local g = require("src.core.Game")
      map = g.overworld and g.overworld.map
    end)
  end
  if not (map and map.isGrassCell) then return 0 end
  local cx = math.floor((tonumber(wx) or 0) / 16)
  local cy = math.floor((tonumber(wz) or 0) / 16)
  if map.inBounds and not map:inBounds(cx, cy) then return 0 end
  if not map:isGrassCell(cx, cy) then return 0 end
  return math.floor(tonumber(baseCut) or Grass3D.GRASS_CUT)
end

local function nearestTrack(x, z)
  local best, bd = nil, Grass3D.CRUSH_SNAP * Grass3D.CRUSH_SNAP
  for i = 1, #tracks do
    local t = tracks[i]
    local dx, dz = t.x - x, t.z - z
    local d = dx * dx + dz * dz
    if d <= bd then best, bd = t, d end
  end
  return best
end

local function unit2(dx, dz)
  local len = math.sqrt(dx * dx + dz * dz)
  if len < 0.001 then return 0, 0 end
  return dx / len, dz / len
end

local function splatTexel(wx, wz, radius, strength, pdx, pdz)
  if strength < Grass3D.CRUSH_KEEP then return end
  local res = Grass3D.MAP_RES
  local texel = Grass3D.MAP_WORLD / res
  local cx = (wx - mapOx) / texel
  local cz = (wz - mapOz) / texel
  local rt = radius / texel
  if rt < 0.5 then rt = 0.5 end
  local x0 = math.max(0, math.floor(cx - rt))
  local x1 = math.min(res - 1, math.ceil(cx + rt))
  local z0 = math.max(0, math.floor(cz - rt))
  local z1 = math.min(res - 1, math.ceil(cz + rt))
  local r2 = rt * rt
  local fade = res * 0.08
  for tz = z0, z1 do
    for tx = x0, x1 do
      local dx, dz = (tx + 0.5) - cx, (tz + 0.5) - cz
      local d2 = dx * dx + dz * dz
      if d2 < r2 then
        local dist = math.sqrt(d2)
        local u = dist / rt
        local ring = u * (1.0 - u) * 4.0
        local t = (1.0 - u)
        t = t * t * (0.55 + 0.45 * ring) * strength
        local edge = 1
        if tx < fade then edge = tx / fade end
        if tx > res - 1 - fade then
          local e = (res - 1 - tx) / fade
          if e < edge then edge = e end
        end
        if tz < fade then
          local e = tz / fade
          if e < edge then edge = e end
        end
        if tz > res - 1 - fade then
          local e = (res - 1 - tz) / fade
          if e < edge then edge = e end
        end
        t = t * edge
        local idx = tz * res + tx
        if t > (mapS[idx] or 0) then
          if (mapS[idx] or 0) == 0 then
            mapLive[#mapLive + 1] = idx
          end
          mapS[idx] = t
          mapDx[idx] = pdx or 0
          mapDz[idx] = pdz or 0
        end
      end
    end
  end
end

local function uploadMap(prevLive)
  if not (love and love.image and love.image.newImageData
          and love.graphics and love.graphics.newImage) then
    return
  end
  if mapIdata == false then return end
  if mapIdata == nil then
    local ok, d = pcall(love.image.newImageData, Grass3D.MAP_RES, Grass3D.MAP_RES)
    if not (ok and d) then
      mapIdata = false
      mapImg = false
      return
    end
    mapIdata = d
  end
  if mapImg == false then return end
  local function put(idx, r, g, b)
    local res = Grass3D.MAP_RES
    local x, z = idx % res, math.floor(idx / res)
    pcall(mapIdata.setPixel, mapIdata, x, z, r, g, b, 1)
  end
  if prevLive then
    for i = 1, #prevLive do
      local idx = prevLive[i]
      if (mapS[idx] or 0) == 0 then put(idx, 0, 0.5, 0.5) end
    end
  end
  for i = 1, #mapLive do
    local idx = mapLive[i]
    local s = mapS[idx] or 0
    if s > 1 then s = 1 end
    put(idx, s,
        ((mapDx[idx] or 0) * 0.5) + 0.5,
        ((mapDz[idx] or 0) * 0.5) + 0.5)
  end
  if mapImg == nil then
    local ok, img = pcall(love.graphics.newImage, mapIdata)
    if not (ok and img) then
      mapImg = false
      return
    end
    pcall(img.setFilter, img, "linear", "linear")
    pcall(img.setWrap, img, "clamp", "clamp")
    mapImg = img
    return
  end
  if mapImg.replacePixels then
    pcall(mapImg.replacePixels, mapImg, mapIdata)
  else
    local ok, img = pcall(love.graphics.newImage, mapIdata)
    if ok and img then
      if mapImg.release then pcall(mapImg.release, mapImg) end
      pcall(img.setFilter, img, "linear", "linear")
      pcall(img.setWrap, img, "clamp", "clamp")
      mapImg = img
    end
  end
end

local function rebuildMap()
  local prev = mapLive
  for i = 1, #mapLive do
    local idx = mapLive[i]
    mapS[idx], mapDx[idx], mapDz[idx] = 0, 0, 0
  end
  mapLive = {}
  for i = 1, #trail do
    local c = trail[i]
    local k = 1 - c.t / Grass3D.TRAIL_TTL
    if k > 0 then
      local s = c.s0 * k * k
      if s >= Grass3D.CRUSH_KEEP then
        splatTexel(c.x, c.z, c.r, s, c.pdx or 0, c.pdz or 0)
      end
    end
  end
  local sent = 0
  for i = 1, #tracks do
    local t = tracks[i]
    if math.abs(t.s) >= Grass3D.CRUSH_KEEP then
      sent = sent + 1
      -- extras (past the uniform live budget) still flatten where they
      -- stand. Positive only: a negative is the spring kick, and that
      -- kick is a uniform's job -- putting it on the trail field would
      -- make a crumb overshoot.
      if sent > Grass3D.CRUSH_LIVE and t.s > 0 then
        splatTexel(t.x, t.z, t.r, t.s, t.pdx or 0, t.pdz or 0)
      end
    end
  end
  uploadMap(prev)
end

-- One frame of foot-crush from the poses already gathered for the draw.
-- `feet` is a list of { x, z, radius, strength [, pdx, pdz] } in world
-- pixels -- what VoxelScene builds -- and what comes back is the `{ n, p }`
-- packet Voxel3D.crush takes, with the springs applied and a walk bearing
-- for the repel wake.
function Grass3D.crushFrame(feet, dt)
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end

  local mapOn = mapWanted()
  local trackCap = mapOn and Grass3D.TRACK_MAX or Grass3D.CRUSH_LIVE
  local trailCap = mapOn and Grass3D.TRAIL_CPU or Grass3D.TRAIL_MAX

  for i = 1, #tracks do tracks[i].tgt, tracks[i].seen = 0, false end

  for i = 1, #(feet or {}) do
    local f = feet[i]
    local x, z = tonumber(f[1]) or 0, tonumber(f[2]) or 0
    local r, s = tonumber(f[3]) or 10, tonumber(f[4]) or 1
    local fdx, fdz = tonumber(f[5]) or 0, tonumber(f[6]) or 0
    local t = nearestTrack(x, z)
    if t then
      -- the same foot, moved: follow it rather than opening a second slot.
      -- And if it has travelled far enough since its last crumb, leave one
      -- WHERE IT WAS -- the trail is the places a foot has been, not the
      -- place it is.
      local ddx, ddz = x - (t.lx or x), z - (t.lz or z)
      local step = Grass3D.TRAIL_STEP
      local crumbR, crumbS = Grass3D.TRAIL_RAD, Grass3D.TRAIL_STR
      -- Speed from the displacement the track already stores. The mod has
      -- no bicycle and the isRunning flags in this tree are the script
      -- runner, so this is the only honest speed. Map-off leaves the
      -- constants alone: that path is pinned (tests/grass_crush_offline).
      if mapOn and dt > 1e-4 then
        local spd = math.sqrt(ddx * ddx + ddz * ddz) / dt
        t.speed = spd
        local k = spd / 60
        if k < 0.45 then k = 0.45 elseif k > 2.2 then k = 2.2 end
        step = Grass3D.TRAIL_STEP / k
        crumbR = Grass3D.TRAIL_RAD * (0.75 + 0.30 * k)
        crumbS = Grass3D.TRAIL_STR * (0.70 + 0.35 * k)
        r = r * (0.80 + 0.25 * k)
      end
      if ddx * ddx + ddz * ddz >= step * step then
        local pdx, pdz = unit2(ddx, ddz)
        if fdx * fdx + fdz * fdz > 0.01 then pdx, pdz = unit2(fdx, fdz) end
        trail[#trail + 1] = {
          x = t.lx or t.x, z = t.lz or t.z,
          r = crumbR,
          s0 = math.max(s, t.s) * crumbS,
          t = 0, pdx = pdx, pdz = pdz,
        }
        while #trail > trailCap do table.remove(trail, 1) end
        t.lx, t.lz = x, z
        t.pdx, t.pdz = pdx, pdz
        -- one-shot rustle: a new cell in tall grass, not a looping bed
        local ncx = math.floor(x / 16)
        local ncz = math.floor(z / 16)
        if t.cx ~= ncx or t.cz ~= ncz then
          t.cx, t.cz = ncx, ncz
          if mapBound and mapBound.isGrassCell
             and mapBound:isGrassCell(ncx, ncz) then
            local oka, Amb = pcall(V.require, "AmbientSound")
            if oka and Amb and Amb.playGrass then
              pcall(Amb.playGrass, x, z)
            end
          end
        end
      end
      t.x, t.z, t.r = x, z, r
      if s > t.tgt then t.tgt = s end
      if fdx * fdx + fdz * fdz > 0.01 then
        t.pdx, t.pdz = unit2(fdx, fdz)
      elseif ddx * ddx + ddz * ddz > 0.25 then
        t.pdx, t.pdz = unit2(ddx, ddz)
      end
      t.seen = true
    elseif #tracks < trackCap then
      local pdx, pdz = unit2(fdx, fdz)
      tracks[#tracks + 1] = { x = x, z = z, r = r, lx = x, lz = z,
                              s = 0, v = 0, tgt = s, seen = true,
                              pdx = pdx, pdz = pdz,
                              cx = math.floor(x / 16),
                              cz = math.floor(z / 16) }
    end
  end

  seenThisFrame = 0
  for i = 1, #tracks do
    if tracks[i].seen then seenThisFrame = seenThisFrame + 1 end
  end

  for i = #trail, 1, -1 do
    local c = trail[i]
    c.t = c.t + dt
    if c.t >= Grass3D.TRAIL_TTL then table.remove(trail, i) end
  end

  for i = #tracks, 1, -1 do
    local t = tracks[i]
    -- The branch is "is a foot in this tuft", NOT "is the strength below
    -- its target". Those read the same until the spring overshoots, and
    -- then they are opposites: past upright the strength is NEGATIVE, so a
    -- test on `tgt > s` sees a zero target above it, calls that a foot
    -- arriving, and zeroes the very velocity that was carrying the kick --
    -- which clamps every spring to the instant it crosses zero and turns
    -- the whole thing back into the ease it was written to replace.
    if t.seen and t.tgt > t.s then
      -- a foot arriving: fast, and it does not overshoot -- a boot going
      -- down does not bounce. The velocity goes with it, so the spring
      -- below starts from rest under the foot rather than from whatever
      -- the last release left behind.
      t.s = t.s + (t.tgt - t.s) * math.min(1, Grass3D.CRUSH_FALL * dt)
      t.v = 0
    else
      -- and standing back up: a damped spring, integrated. Explicit Euler
      -- is stable here because the step is a frame and the stiffness is
      -- deliberately low (K dt^2 well under 1).
      t.v = t.v + (t.tgt - t.s) * Grass3D.CRUSH_K * dt
      t.v = t.v - t.v * Grass3D.CRUSH_C * dt
      t.s = t.s + t.v * dt
    end
    if not t.seen
       and math.abs(t.s) < Grass3D.CRUSH_KEEP
       and math.abs(t.v) < 0.12 then
      table.remove(tracks, i)
    end
  end

  if mapOn then
    if not mapFocus then
      for i = 1, #tracks do
        if tracks[i].seen then
          Grass3D.setFocus(tracks[i].x, tracks[i].z)
          break
        end
      end
    end
    rebuildMap()
  end
  mapFocus = false

  crush.n = 0
  for i = 1, #tracks do
    if crush.n >= Grass3D.CRUSH_LIVE then break end
    local t = tracks[i]
    if math.abs(t.s) >= Grass3D.CRUSH_KEEP then
      crush.n = crush.n + 1
      local p = crush.p[crush.n]
      -- a negative strength is the overshoot: the shader reads it as a
      -- push the other way, which is the blade passing upright
      p[1], p[2], p[3], p[4] = t.x, t.z, t.r, t.s
      p[5], p[6] = t.pdx or 0, t.pdz or 0
    end
  end
  -- Trail crumbs stay on uniforms only when the map is off (detail 0)
  -- or the image could not be made. Newest first, same square fade.
  -- A working map already holds every crumb; packing them again would
  -- double-flatten the near path and spend the vertex loop we just freed.
  local packTrail = not (mapOn and mapImg)
  if packTrail then
    for i = #trail, 1, -1 do
      if crush.n >= Grass3D.CRUSH_SLOTS then break end
      local c = trail[i]
      local k = 1 - c.t / Grass3D.TRAIL_TTL
      if k > 0 then
        local s = c.s0 * k * k
        if s >= Grass3D.CRUSH_KEEP then
          crush.n = crush.n + 1
          local p = crush.p[crush.n]
          p[1], p[2], p[3], p[4] = c.x, c.z, c.r, s
          p[5], p[6] = c.pdx or 0, c.pdz or 0
        end
      end
    end
  end
  return crush
end

function Grass3D.trailCount()
  return #trail
end

function Grass3D.crushersSeen()
  return seenThisFrame
end

function Grass3D.trailSpan()
  if #trail == 0 then return 0 end
  local oldest = trail[1]
  local best = 0
  for i = 1, #tracks do
    local t = tracks[i]
    local dx, dz = t.x - oldest.x, t.z - oldest.z
    local d = math.sqrt(dx * dx + dz * dz)
    if d > best then best = d end
  end
  return best
end

function Grass3D.sampleMap(wx, wz)
  local res = Grass3D.MAP_RES
  local texel = Grass3D.MAP_WORLD / res
  local x = ((tonumber(wx) or 0) - mapOx) / texel
  local z = ((tonumber(wz) or 0) - mapOz) / texel
  if x < 0 or z < 0 or x >= res or z >= res then return 0 end
  local ix, iz = math.floor(x), math.floor(z)
  return mapS[iz * res + ix] or 0
end

function Grass3D.splat(wx, wz, radius, strength, pushDir)
  local pdx, pdz = 0, 0
  if type(pushDir) == "table" then
    pdx, pdz = unit2(tonumber(pushDir[1]) or 0, tonumber(pushDir[2]) or 0)
  end
  trail[#trail + 1] = {
    x = tonumber(wx) or 0,
    z = tonumber(wz) or 0,
    r = tonumber(radius) or Grass3D.TRAIL_RAD,
    s0 = tonumber(strength) or 1,
    t = 0, pdx = pdx, pdz = pdz,
  }
  local cap = mapWanted() and Grass3D.TRAIL_CPU or Grass3D.TRAIL_MAX
  while #trail > cap do table.remove(trail, 1) end
end

function Grass3D.shaderCost(detail, crushers)
  detail = tonumber(detail) or 2
  crushers = tonumber(crushers) or 1
  local slots = 8
  if detail <= 0 then slots = 3
  elseif detail == 1 then slots = 5
  end
  local map = mapForce ~= false and detail >= 1
  if mapForce == false then map = false end
  if not map then
    local live = math.min(crushers, Grass3D.CRUSH_LIVE)
    local packed = math.min(live + Grass3D.TRAIL_MAX, 8)
    return { distances = math.min(packed, slots), taps = 0, slots = slots }
  end
  local live = math.min(crushers, Grass3D.CRUSH_LIVE)
  return { distances = math.min(live, slots), taps = 1, slots = slots }
end

function Grass3D.mapState()
  if not mapWanted() then return nil end
  if not mapImg then return nil end
  return {
    img = mapImg,
    on = 1,
    ox = mapOx, oz = mapOz,
    ix = 1 / Grass3D.MAP_WORLD,
    iz = 1 / Grass3D.MAP_WORLD,
  }
end

function Grass3D.clearTracks()
  tracks = {}
  trail = {}
  crush.n = 0
  seenThisFrame = 0
  for i = 1, #mapLive do
    local idx = mapLive[i]
    mapS[idx], mapDx[idx], mapDz[idx] = 0, 0, 0
  end
  mapLive = {}
end

function Grass3D.crushAt(i)
  return crush.p[i]
end

-- Pull crush points off the overworld: the player always, and any roamer
-- that is currently stepping (moving) near grass. Best-effort -- a missing
-- module costs nothing.
function Grass3D.gatherCrush(state)
  Grass3D.clearCrush()
  if not state then return end
  local function faceDir(facing)
    if facing == "right" then return 1, 0 end
    if facing == "left"  then return -1, 0 end
    if facing == "down"  then return 0, 1 end
    if facing == "up"    then return 0, -1 end
    return 0, 0
  end
  local player = state.player
  if player and player.x and player.y then
    -- feet at sprite centre; wider + directed while moving so the meadow
    -- parts into a corridor instead of only dimming under the boot
    local moving = player.moving or player.walkTimer or false
    local str = moving and 1.25 or 0.7
    local rad = moving and 17 or 12
    local pdx, pdz = faceDir(player.facing or player.dir)
    Grass3D.addCrush(player.x + 8, player.y + 8, rad, str, { pdx, pdz })
  end
  local ok, Roamer = pcall(V.require, "Roamer")
  if ok and Roamer and Roamer.forEach then
    pcall(Roamer.forEach, function(r)
      if not r or not r.x then return end
      if crush.n >= 8 then return end
      local moving = r.moving or r.step
      local str = moving and 1.1 or 0.5
      local rad = moving and 15 or 11
      local pdx, pdz = faceDir(r.facing or r.dir)
      Grass3D.addCrush((r.x or 0) + 8, (r.y or 0) + 8, rad, str, { pdx, pdz })
    end)
  end
end

function Grass3D.dropGPU()
  if tex and tex ~= false and tex.release then pcall(tex.release, tex) end
  tex = nil
  if mapImg and mapImg ~= false and mapImg.release then
    pcall(mapImg.release, mapImg)
  end
  mapImg, mapIdata = nil, nil
  -- template is CPU data; keep it. Only GPU image drops.
end

function Grass3D.invalidate()
  tpl = nil
  meta = nil
  Grass3D.dropGPU()
end

return Grass3D
