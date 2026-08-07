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
-- If the bake is missing or unreadable the caller falls back to the slab
-- path; this file never throws into the mesh build.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Voxel3D = V.require("Voxel3D")

local Grass3D = {}

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
  -- 1. love.filesystem (mod mount / source tree)
  if love and love.filesystem and love.filesystem.read then
    local ok, data = pcall(love.filesystem.read, rel)
    if ok and type(data) == "string" and #data > 0 then return data end
    ok, data = pcall(love.filesystem.read, abs)
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
  return loadTemplate() ~= nil and loadTexture() ~= nil
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
  local verts, indices = {}, {}
  local tplV, tplI = t.verts, t.indices
  for i = 1, #instances do
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
for i = 1, 8 do crush.p[i] = { 0, 0, 0, 0 } end

function Grass3D.clearCrush()
  crush.n = 0
end

-- Add a foot at world (wx, wz). `strength` 0..1, `radius` world px.
function Grass3D.addCrush(wx, wz, radius, strength)
  if crush.n >= 8 then return end
  crush.n = crush.n + 1
  local p = crush.p[crush.n]
  p[1] = tonumber(wx) or 0
  p[2] = tonumber(wz) or 0
  p[3] = tonumber(radius) or 10
  p[4] = tonumber(strength) or 1
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
Grass3D.CRUSH_FALL = 14.0     -- per second, toward a foot that is present
Grass3D.CRUSH_K = 46.0        -- spring stiffness on the way back up
Grass3D.CRUSH_C = 5.0         -- and its damping (below critical: it kicks)
Grass3D.CRUSH_KEEP = 0.015    -- below this, and still, a slot is done
-- How far a foot may travel between frames and still be recognised as the
-- same foot. Twenty rather than ten because this machine is not the only
-- machine: at twenty frames a second a walking sprite covers most of a
-- tile per frame, and a snap too tight turns one walker into a stream of
-- one-frame strangers -- each opening a slot, none of them living long
-- enough to drop a crumb.
Grass3D.CRUSH_SNAP = 20       -- world px a foot may move and stay the same slot
Grass3D.CRUSH_SLOTS = 8       -- what the shader takes (Voxel3D.CRUSH_SLOTS)
Grass3D.CRUSH_LIVE = 3        -- of those, how many may be live feet

-- Spacing against radius is the whole of whether this reads as a PATH or
-- as a row of dents: ten apart with a nine-pixel reach, the discs overlap
-- and the eye joins them into one laid line, and five of them span fifty
-- world pixels -- three tiles of trail behind you, which is about as far
-- back as anybody turns to look.
Grass3D.TRAIL_STEP = 10       -- world px a foot travels between crumbs
Grass3D.TRAIL_TTL = 4.2       -- seconds a crumb takes to fade out entirely
Grass3D.TRAIL_STR = 0.90      -- how hard a crumb lies, against the foot's own
Grass3D.TRAIL_RAD = 9         -- world px -- narrower than a foot: it is a path
Grass3D.TRAIL_MAX = 5         -- crumbs kept (CRUSH_SLOTS - CRUSH_LIVE)

-- live slots: { x, z, r, s (live strength), v (its velocity), tgt, seen,
--               lx, lz (where this foot last dropped a crumb) }
local tracks = {}
-- crumbs: { x, z, r, s0 (strength at birth), t (age) }
local trail = {}

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

-- One frame of foot-crush from the poses already gathered for the draw.
-- `feet` is a list of { x, z, radius, strength } in world pixels -- what
-- the old inline block in VoxelScene built -- and what comes back is the
-- same `{ n, p }` packet Voxel3D.crush takes, with the springs applied.
function Grass3D.crushFrame(feet, dt)
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end

  for i = 1, #tracks do tracks[i].tgt, tracks[i].seen = 0, false end

  for i = 1, #(feet or {}) do
    local f = feet[i]
    local x, z = tonumber(f[1]) or 0, tonumber(f[2]) or 0
    local r, s = tonumber(f[3]) or 10, tonumber(f[4]) or 1
    local t = nearestTrack(x, z)
    if t then
      -- the same foot, moved: follow it rather than opening a second slot.
      -- And if it has travelled far enough since its last crumb, leave one
      -- WHERE IT WAS -- the trail is the places a foot has been, not the
      -- place it is.
      local ddx, ddz = x - (t.lx or x), z - (t.lz or z)
      if ddx * ddx + ddz * ddz
         >= Grass3D.TRAIL_STEP * Grass3D.TRAIL_STEP then
        trail[#trail + 1] = {
          x = t.lx or t.x, z = t.lz or t.z,
          r = Grass3D.TRAIL_RAD,
          s0 = math.max(s, t.s) * Grass3D.TRAIL_STR,
          t = 0,
        }
        -- oldest first out: the far end of a walk is the part nobody is
        -- looking at any more
        while #trail > Grass3D.TRAIL_MAX do table.remove(trail, 1) end
        t.lx, t.lz = x, z
      end
      t.x, t.z, t.r = x, z, r
      if s > t.tgt then t.tgt = s end
      t.seen = true
    elseif #tracks < Grass3D.CRUSH_LIVE then
      tracks[#tracks + 1] = { x = x, z = z, r = r, lx = x, lz = z,
                              s = 0, v = 0, tgt = s, seen = true }
    end
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
    end
  end
  -- and the trail behind them, NEWEST FIRST: a walk longer than the slot
  -- budget should lose its far end, not its near one.
  --
  -- SQUARED, not cubed and not linear. Linear reads as the path dimming
  -- evenly, which is a fade rather than a recovery. Cubed was the first
  -- try and collapses too fast to look at: a crumb at four fifths of its
  -- life still has half its lie under a square and only a fifth under a
  -- cube, and a screenshot taken a moment after the walker stopped came
  -- back with one crumb left out of four. Squared holds the path long
  -- enough to turn round and see, then lets it go.
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
      end
    end
  end
  return crush
end

function Grass3D.trailCount()
  return #trail
end

function Grass3D.clearTracks()
  tracks = {}
  trail = {}
  crush.n = 0
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
  local player = state.player
  if player and player.x and player.y then
    -- feet at sprite centre; slightly larger radius while moving
    local moving = player.moving or player.walkTimer or false
    local str = moving and 1.0 or 0.55
    Grass3D.addCrush(player.x + 8, player.y + 8, 11, str)
  end
  local ok, Roamer = pcall(V.require, "Roamer")
  if ok and Roamer and Roamer.forEach then
    pcall(Roamer.forEach, function(r)
      if not r or not r.x then return end
      if crush.n >= 8 then return end
      local str = (r.moving or r.step) and 0.85 or 0.4
      Grass3D.addCrush((r.x or 0) + 8, (r.y or 0) + 8, 10, str)
    end)
  end
end

function Grass3D.dropGPU()
  if tex and tex ~= false and tex.release then pcall(tex.release, tex) end
  tex = nil
  -- template is CPU data; keep it. Only GPU image drops.
end

function Grass3D.invalidate()
  tpl = nil
  meta = nil
  Grass3D.dropGPU()
end

return Grass3D
