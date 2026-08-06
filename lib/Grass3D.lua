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
-- and sent into the scene shader as up to 4 packed vec4s.
local crush = { n = 0, p = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 },
                              { 0, 0, 0, 0 }, { 0, 0, 0, 0 } } }

function Grass3D.clearCrush()
  crush.n = 0
end

-- Add a foot at world (wx, wz). `strength` 0..1, `radius` world px.
function Grass3D.addCrush(wx, wz, radius, strength)
  if crush.n >= 4 then return end
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
      if crush.n >= 4 then return end
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
