-- Street lamps for the towns at night.
--
-- The DAYTIME row already lights WINDOWS (DayNight.windowLight + the glass
-- path in Voxel3D).  What a dark night still lacks is something on the
-- STREET itself -- Gen 1 towns are empty of lamps, and a DEEP night with
-- nothing between the windows is a town with no middle.  This file plants
-- posts on outdoor maps that are not routes (the same "is a town" test
-- CityLife uses), three hand-built models of them, and draws the heads
-- full-bright in lamp colour after dark so they read as lit rather than as
-- dim props under the hour's tint.
--
-- Placement is deterministic off the map id and cell, so the same lamp
-- stands on the same corner every load.  Nothing is written to the save.
-- The LAMPS row turns the whole feature off; N-DARK on DayNight decides how
-- much darkness the lamps are answering.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local Voxel3D = V.require("Voxel3D")
local Mat4 = V.require("Mat4")
local DayNight = V.require("DayNight")

local Map = require("src.world.Map")

local StreetLamps = {}

local function game()
  return require("src.core.Game")
end

StreetLamps.setting = ModSetting.new("lamps", "LAMPS",
                                     { true, false },
                                     { "ON", "OFF" })

function StreetLamps.enabled()
  local ok, v = pcall(StreetLamps.setting.get, StreetLamps.setting)
  return ok and v == true
end

-- How far apart two posts may stand, in cells.  Closer and a town is a
-- forest of poles; further and a block has none.
StreetLamps.SPACING = 6

-- Max posts per map.  A full Kanto city has room for more, but each is a
-- mesh draw and a shadow caster, and a phone-shaped view does not want
-- fifty of them.
StreetLamps.MAX = 28

-- The authored post from assets/ground/lamppost/ is the shipping model when
-- its bake is present; the box templates below remain the fallback for a
-- build that ships without one.
--
-- It was off for a while because the bake it was reading was broken -- the
-- optimizer of the day reduced triangles by snapping vertices to a grid, and
-- a grid cell wide enough to cover the lantern is far wider than the shaft,
-- so the whole middle of the post collapsed to nothing and what reached the
-- renderer was a lantern hanging over a base plate.  That was a bad bake, not
-- a bad importer.  tools/optimize_lamppost_glb.py now decimates by edge
-- collapse (which cannot disconnect a surface) and refuses to write a bake
-- with a missing height band at all.
StreetLamps.AUTHORED_MESH = true

-- Local pools of warm light are evaluated by the voxel shader.  Eight is
-- enough to cover a phone-sized view without turning every fragment into a
-- loop over every lamp in a large city.
--
-- Three tiles of ground reach, which is a little SHORTER than a lamp that
-- lights the whole street would want, and deliberately so: the posts stand
-- six cells apart, and a pool wide enough to meet its neighbours turns eight
-- separate lamps into one flat wash over the entire visible map -- measured,
-- on Viridian at midnight, and the night was gone. The dark between the pools
-- is the effect.
StreetLamps.LIGHT_RADIUS = 56
StreetLamps.LIGHT_LIMIT = 8

-- ------- is this a town
--
-- Outdoor map with no grass encounter table.  Same rule CityLife uses, so
-- a route keeps its wild grass and gets no posts, and Viridian Forest
-- (canopy) is not a street.
local function isTown(map)
  if not (map and map.def and Map.isOutdoor(map.def)) then return false end
  if DayNight.isCanopy(map) then return false end
  local Game = game()
  local encDef = Game and Game.data and Game.data.encounters
                 and Game.data.encounters[map.id]
  if encDef and encDef.grass and (encDef.grass.rate or 0) > 0 then
    return false
  end
  return true
end

local function hasSolidNeighbor(map, cx, cy)
  for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
    local nx, ny = cx + d[1], cy + d[2]
    if map:inBounds(nx, ny)
       and not map:isWalkableCell(nx, ny)
       and not map:isWaterCell(nx, ny) then
      return true
    end
  end
  return false
end

-- Stable 0..1 from map id + cell, no love.math so a probe and a play agree.
local function cellHash(mapId, cx, cy)
  local s = tostring(mapId or "") .. ":" .. cx .. "," .. cy
  local h = 2166136261
  for i = 1, #s do
    h = (h * 16777619 + s:byte(i)) % 2147483647
  end
  return (h % 10007) / 10007
end

-- ------- the three models (+ optional authored 3D bake)
--
-- Built once as local-space meshes (feet on y = 0, centred on xz).  Style
-- names are the only thing a site remembers; the mesh is shared.
--
--   classic  thin pole, single lantern box on top
--   twin     same pole, two lanterns side by side (main streets)
--   globe    thicker pole, taller lantern (plazas / gym roads)
--
-- When assets/ground/lamppost/ ships a bake (lamppost.mesh.bin +
-- lamppost.png from tools/optimize_lamppost_glb.py), every style uses that
-- single authored post instead of the box models. Missing bake → boxes.

local templates = nil          -- { classic={pole,head}, ... } or 3d={mesh}
local lampTex = nil            -- 2x1 procedural OR authored PNG
-- nil untried, false missing, else { body, glass, height, radius, lampY }.
-- Two meshes over ONE vertex list: the bake orders its indices body-first so
-- the lantern's panes can be drawn in a second pass and burnt full-bright
-- while the ironwork stays under the hour's tint -- the same pole/head split
-- the box models get, taken from the art instead of from hand-placed boxes.
local mesh3d = nil
local tex3d = nil

StreetLamps.ASSET_DIR = "assets/ground/lamppost/"
StreetLamps.BIN = "lamppost.mesh.bin"
StreetLamps.TEX = "lamppost.png"

local function assetPath(name)
  local base = (V and V.path) or ""
  -- normalize to forward slashes; Assets and love.filesystem both accept them
  base = tostring(base):gsub("\\", "/")
  local dir = StreetLamps.ASSET_DIR:gsub("\\", "/")
  if base:sub(-1) == "/" then
    return base .. dir .. name
  end
  return base .. "/" .. dir .. name
end

local function logOnce(msg, ...)
  if StreetLamps._logged then return end
  StreetLamps._logged = true
  if V and V.mod and V.mod.log and V.mod.log.info then
    pcall(V.mod.log.info, V.mod.log, msg, ...)
  end
end

local function f32(s, o)
  local b1, b2, b3, b4 = s:byte(o + 1, o + 4)
  if not b4 then return 0 end
  local u = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
  local sign = 1
  if u >= 0x80000000 then sign = -1; u = u - 0x80000000 end
  local exp = math.floor(u / 0x800000) % 0x100
  local mant = u % 0x800000
  local ldexp = math.ldexp or function(x, e) return x * 2 ^ e end
  if exp == 0 then
    if mant == 0 then return sign * 0.0 end
    return sign * ldexp(mant / 0x800000, -126)
  elseif exp == 255 then
    if mant == 0 then return sign * (1 / 0) end
    return 0 / 0
  end
  return sign * ldexp(1 + mant / 0x800000, exp - 127)
end

local function u16(s, o)
  local b1, b2 = s:byte(o + 1, o + 2)
  if not b2 then return 0 end
  return b1 + b2 * 256
end

local function u32(s, o)
  local b1, b2, b3, b4 = s:byte(o + 1, o + 4)
  if not b4 then return 0 end
  -- force integer (Lua numbers); keep low 32 bits
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function candidatePaths(name)
  local rel = StreetLamps.ASSET_DIR .. name
  local abs = assetPath(name)
  local absWin = abs:gsub("/", "\\")
  return { rel, abs, absWin }
end

local function readBinary(name)
  for _, path in ipairs(candidatePaths(name)) do
    if love and love.filesystem and love.filesystem.read then
      local ok, data = pcall(love.filesystem.read, path)
      if ok and type(data) == "string" and #data > 16 then return data end
    end
    local okA, Assets = pcall(require, "src.render.Assets")
    if okA and Assets and Assets.read then
      local ok, data = pcall(Assets.read, path)
      if ok and type(data) == "string" and #data > 16 then return data end
    end
    if io and io.open then
      local f = io.open(path, "rb")
      if f then
        local data = f:read("*a")
        f:close()
        if type(data) == "string" and #data > 16 then return data end
      end
    end
  end
  return nil
end

local function loadTex3d()
  if tex3d ~= nil then return tex3d or nil end
  local okA, Assets = pcall(require, "src.render.Assets")
  for _, path in ipairs(candidatePaths(StreetLamps.TEX)) do
    if okA and Assets then
      local okE, exists = pcall(Assets.exists, path)
      if okE and exists then
        local ok, img = pcall(Assets.image, path)
        if ok and img then
          pcall(img.setFilter, img, "nearest", "nearest")
          tex3d = img
          return img
        end
      end
    end
    -- desktop absolute path (love.graphics.newImage accepts real files)
    if love and love.graphics and love.graphics.newImage then
      local ok, img = pcall(love.graphics.newImage, path)
      if ok and img then
        pcall(img.setFilter, img, "nearest", "nearest")
        tex3d = img
        return img
      end
    end
  end
  tex3d = false
  return nil
end

-- Header of a "TPR2" prop bake, or nil for the legacy headerless layout.
--
--   0  "TPR2"            8  indices        16  height    24  lampY
--   4  vertices         12  body indices   20  radius    28  lampR
--
-- The body indices come first and the lantern's follow, so one vertex list
-- makes two meshes with no second copy of the geometry.
local function readHeader(blob)
  if blob:sub(1, 4) == "TPR2" then
    return {
      size = 32,
      nv = u32(blob, 4), ni = u32(blob, 8), nBody = u32(blob, 12),
      height = f32(blob, 16), radius = f32(blob, 20),
      lampY = f32(blob, 24), lampR = f32(blob, 28),
    }
  end
  -- v1: no magic, no lantern split. Everything is body; the flame is guessed
  -- at four fifths of the post's height so an old bake still lights up.
  local nv, ni = u32(blob, 0), u32(blob, 4)
  local height = f32(blob, 8)
  return {
    size = 16,
    nv = nv, ni = ni, nBody = ni,
    height = height, radius = f32(blob, 12),
    lampY = height * 0.8, lampR = 0,
  }
end

local function loadMesh3d()
  if not StreetLamps.AUTHORED_MESH then return nil end
  if mesh3d ~= nil then return mesh3d or nil end
  local blob = readBinary(StreetLamps.BIN)
  local tex = loadTex3d()
  if type(blob) ~= "string" or #blob < 32 then
    logOnce("StreetLamps: 3D bake missing (bin at %s) — using box posts",
            assetPath(StreetLamps.BIN))
    mesh3d = false
    return nil
  end
  if not tex then
    logOnce("StreetLamps: 3D bake texture missing (%s) — using box posts",
            assetPath(StreetLamps.TEX))
    mesh3d = false
    return nil
  end
  local hd = readHeader(blob)
  if hd.nv < 3 or hd.ni < 3 or hd.nv > 20000 or hd.ni > 60000
     or hd.nBody > hd.ni or hd.nBody % 3 ~= 0 or hd.ni % 3 ~= 0
     or not (hd.height > 0) then
    logOnce("StreetLamps: 3D bake header bad nv=%s ni=%s body=%s — using box posts",
            tostring(hd.nv), tostring(hd.ni), tostring(hd.nBody))
    mesh3d = false
    return nil
  end
  local need = hd.size + hd.nv * 24 + hd.ni * 2
  if #blob < need then
    logOnce("StreetLamps: 3D bake truncated (%d < %d) — using box posts",
            #blob, need)
    mesh3d = false
    return nil
  end
  local verts = {}
  local o = hd.size
  for i = 1, hd.nv do
    verts[i] = {
      f32(blob, o), f32(blob, o + 4), f32(blob, o + 8),
      f32(blob, o + 12), f32(blob, o + 16), f32(blob, o + 20),
    }
    o = o + 24
  end
  local body, glass = {}, {}
  for i = 1, hd.ni do
    local v = u16(blob, o) + 1
    if v > hd.nv then                 -- an index past the vertex list is a
      logOnce("StreetLamps: 3D bake index %d out of range — using box posts", v)
      mesh3d = false                  -- corrupt file, not a mesh to guess at
      return nil
    end
    if i <= hd.nBody then body[#body + 1] = v else glass[#glass + 1] = v end
    o = o + 2
  end
  local bodyMesh = Voxel3D.newMesh(verts, body)
  if not bodyMesh then
    logOnce("StreetLamps: Voxel3D.newMesh failed — using box posts")
    mesh3d = false
    return nil
  end
  pcall(bodyMesh.setTexture, bodyMesh, tex)
  local glassMesh = nil
  if #glass >= 3 then
    glassMesh = Voxel3D.newMesh(verts, glass)
    if glassMesh then pcall(glassMesh.setTexture, glassMesh, tex) end
  end
  mesh3d = {
    body = bodyMesh,
    glass = glassMesh,
    height = hd.height,
    radius = hd.radius,
    lampY = hd.lampY,
    lampR = hd.lampR,
  }
  logOnce("StreetLamps: authored 3D lamppost (%d body + %d lantern tris, flame y=%.1f)",
          math.floor(hd.nBody / 3), math.floor((hd.ni - hd.nBody) / 3), hd.lampY)
  return mesh3d
end

function StreetLamps.usesAuthoredMesh()
  return loadMesh3d() ~= nil
end

-- Where the flame hangs on whichever post is actually shipping, in world
-- pixels above its feet. The renderer places its point light here (see
-- lampHeight in Voxel3D's shader), so this must follow the model rather than
-- be a constant either side guesses at.
function StreetLamps.flameHeight()
  local m = loadMesh3d()
  if m and m.lampY and m.lampY > 0 then return m.lampY end
  return 19.0                          -- the box models' lantern centre
end

local function ensureTex()
  -- Prefer the authored PNG when the 3D bake is present.
  local t3 = loadTex3d()
  if t3 then
    lampTex = t3
    return lampTex
  end
  if lampTex then return lampTex end
  if not (love and love.image and love.graphics) then return nil end
  local ok, data = pcall(love.image.newImageData, 2, 1)
  if not ok or not data then return nil end
  -- u≈0: dark metal pole.  u≈1: warm lantern glass (daytime look; at night
  -- the head is flattened to lampColor and this texel barely matters).
  pcall(data.setPixel, data, 0, 0, 0.28, 0.26, 0.24, 1)
  pcall(data.setPixel, data, 1, 0, 0.95, 0.78, 0.40, 1)
  local okI, img = pcall(love.graphics.newImage, data)
  if not okI or not img then return nil end
  pcall(img.setFilter, img, "nearest", "nearest")
  lampTex = img
  return lampTex
end

-- One axis-aligned box as six quads.  u selects the atlas column (0 metal,
-- 1 lamp).  shade is the face shade the scene multiplies by.
local function addBox(verts, indices, x0, y0, z0, x1, y1, z1, u, shade)
  local faces = {
    -- +X -X +Y -Y +Z -Z
    { { x1, y0, z0 }, { x1, y0, z1 }, { x1, y1, z1 }, { x1, y1, z0 }, 0.85 },
    { { x0, y0, z1 }, { x0, y0, z0 }, { x0, y1, z0 }, { x0, y1, z1 }, 0.70 },
    { { x0, y1, z0 }, { x1, y1, z0 }, { x1, y1, z1 }, { x0, y1, z1 }, 1.00 },
    { { x0, y0, z1 }, { x1, y0, z1 }, { x1, y0, z0 }, { x0, y0, z0 }, 0.55 },
    { { x0, y0, z1 }, { x1, y0, z1 }, { x1, y1, z1 }, { x0, y1, z1 }, 0.90 },
    { { x1, y0, z0 }, { x0, y0, z0 }, { x0, y1, z0 }, { x1, y1, z0 }, 0.75 },
  }
  local v = u or 0
  for _, f in ipairs(faces) do
    local base = #verts
    local s = shade * f[5]
    for i = 1, 4 do
      local c = f[i]
      verts[#verts + 1] = { c[1], c[2], c[3], v, 0.5, s }
    end
    Voxel3D.pushQuad(indices, base / 4)
  end
end

local function bakePart(boxes)
  local verts, indices = {}, {}
  for _, b in ipairs(boxes) do
    addBox(verts, indices, b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8])
  end
  return Voxel3D.newMesh(verts, indices)
end

local function buildTemplates()
  if templates then return templates end
  -- classic: 2x2 pole to y=18, 5x5x4 lantern on top
  local classicPole = bakePart({
    { -1, 0, -1, 1, 18, 1, 0, 0.9 },
    { -1.5, 0, -1.5, 1.5, 1.5, 1.5, 0, 0.75 },   -- base plinth
  })
  local classicHead = bakePart({
    { -2.5, 17, -2.5, 2.5, 21, 2.5, 1, 1.0 },
    { -1.5, 21, -1.5, 1.5, 22.5, 1.5, 0, 0.85 }, -- cap
  })
  -- twin: same pole, two lanterns
  local twinPole = bakePart({
    { -1, 0, -1, 1, 17, 1, 0, 0.9 },
    { -1.5, 0, -1.5, 1.5, 1.5, 1.5, 0, 0.75 },
    { -5, 16, -1, 5, 17.5, 1, 0, 0.8 },           -- crossbar
  })
  local twinHead = bakePart({
    { -6.5, 15.5, -2, -3.5, 19.5, 2, 1, 1.0 },
    { 3.5, 15.5, -2, 6.5, 19.5, 2, 1, 1.0 },
  })
  -- globe: thicker shaft, chunky lantern
  local globePole = bakePart({
    { -1.5, 0, -1.5, 1.5, 16, 1.5, 0, 0.9 },
    { -2, 0, -2, 2, 2, 2, 0, 0.75 },
  })
  local globeHead = bakePart({
    { -3, 15, -3, 3, 21, 3, 1, 1.0 },
    { -2, 21, -2, 2, 22.5, 2, 0, 0.85 },
  })
  templates = {
    classic = { pole = classicPole, head = classicHead },
    twin = { pole = twinPole, head = twinHead },
    globe = { pole = globePole, head = globeHead },
  }
  return templates
end

local STYLES = { "classic", "twin", "globe" }

-- ------- per-map site cache
--
-- key -> { {cx, cy, style, wx, wz}, ... }
local cache = {}

local function sitesFor(map)
  if not map or not map.id then return {} end
  local hit = cache[map.id]
  if hit then return hit end
  if not isTown(map) then
    cache[map.id] = {}
    return cache[map.id]
  end

  -- Map cells use widthCells/heightCells (not .width/.height — those are nil
  -- on this engine's Map).
  local w = map.widthCells or map.width or 0
  local h = map.heightCells or map.height or 0
  local candidates = {}
  for cy = 2, h - 3 do
    for cx = 2, w - 3 do
      if map:isWalkableCell(cx, cy)
         and not map:isWaterCell(cx, cy)
         and not map:warpAtCell(cx, cy)
         and not (map.isGrassCell and map:isGrassCell(cx, cy)) then
        local r = cellHash(map.id, cx, cy)
        local sidewalk = hasSolidNeighbor(map, cx, cy)
        -- Sidewalk cells preferred (r < 0.55); open plaza cells rarer
        -- (r < 0.12) so a big square still gets a few posts.
        if (sidewalk and r < 0.55) or ((not sidewalk) and r < 0.12) then
          candidates[#candidates + 1] = {
            cx = cx, cy = cy, r = r, sidewalk = sidewalk,
            wx = cx * 16 + 8, wz = cy * 16 + 8,
          }
        end
      end
    end
  end
  -- sidewalks first so plazas fill the gaps rather than taking the budget
  table.sort(candidates, function(a, b)
    if a.sidewalk ~= b.sidewalk then return a.sidewalk end
    return a.r < b.r
  end)

  local placed, sites = {}, {}
  local gap = StreetLamps.SPACING
  for _, c in ipairs(candidates) do
    if #sites >= StreetLamps.MAX then break end
    local ok = true
    for _, p in ipairs(placed) do
      if math.abs(p.cx - c.cx) < gap and math.abs(p.cy - c.cy) < gap then
        ok = false; break
      end
    end
    if ok then
      local style = STYLES[1 + math.floor(c.r * #STYLES) % #STYLES]
      sites[#sites + 1] = {
        cx = c.cx, cy = c.cy, wx = c.wx, wz = c.wz, style = style,
      }
      placed[#placed + 1] = c
    end
  end
  cache[map.id] = sites
  return sites
end

function StreetLamps.invalidate()
  cache = {}
  templates = nil
  lampTex = nil
  mesh3d = nil
  tex3d = nil
end

-- The nearest active lamps for the current camera.  This is called before
-- the terrain is drawn, so their light lands on the road and nearby walls as
-- well as on the post that emits it.  Returning ordinary tables keeps the
-- renderer independent of map internals and makes this usable in probes.
function StreetLamps.lights(map, wx, wz, limit)
  if not StreetLamps.enabled() then return {} end
  local ok, lit = pcall(DayNight.windowLight)
  lit = ok and tonumber(lit) or 0
  if lit <= 0.05 then return {} end

  wx, wz = tonumber(wx) or 0, tonumber(wz) or 0
  limit = math.max(1, math.min(StreetLamps.LIGHT_LIMIT, limit or StreetLamps.LIGHT_LIMIT))
  local out = {}
  for _, site in ipairs(sitesFor(map)) do
    local dx, dz = site.wx - wx, site.wz - wz
    out[#out + 1] = {
      x = site.wx,
      z = site.wz,
      radius = StreetLamps.LIGHT_RADIUS,
      -- Tiny deterministic variation prevents a row of lamps reading like
      -- cloned sprites while keeping a save/load frame perfectly stable.
      power = lit * (0.88 + cellHash(map.id, site.cx, site.cy) * 0.12),
      d2 = dx * dx + dz * dz,
    }
  end
  table.sort(out, function(a, b) return a.d2 < b.d2 end)
  for i = #out, limit + 1, -1 do out[i] = nil end
  return out
end

-- ------- draw
--
-- Pole under the hour's light (casts a real shadow when the sun pass runs).
-- Head: after dusk, flattened to DayNight.lampColor so DEEP night does not
-- snuff it out.  Daytime heads keep their warm texel under the ordinary
-- tint and read as unlit glass.
--
-- Authored 3D bake: one mesh (pole+lantern). Daytime under the hour tint;
-- at night a warm flatten wash so the lantern still reads as lit without
-- splitting the GLB into parts.

function StreetLamps.draw(map, outdoor)
  if not StreetLamps.enabled() then return end
  if not outdoor then return end
  if not Voxel3D.available() then return end
  local sites = sitesFor(map)
  if #sites == 0 then return end

  local lit = 0
  if outdoor then
    local ok, n = pcall(DayNight.windowLight)
    if ok and n then lit = n end
  end
  local lampColor = DayNight.lampColor()

  local authored = loadMesh3d()
  if authored then
    local tex = loadTex3d() or ensureTex()
    -- Each post keeps its own facing, so a street is not a row of clones.
    -- Worked once here and reused by the lantern pass below rather than
    -- hashed twice: the two passes MUST agree or the panes rotate off the
    -- ironwork they belong to.
    local xf = {}
    for i, s in ipairs(sites) do
      local yaw = cellHash(map.id, s.cx, s.cy) * math.pi * 2
      xf[i] = Mat4.mul(Mat4.translate(s.wx, 0, s.wz), Mat4.rotateY(yaw))
    end

    -- The ironwork, under the hour's own light. It is a dark object at night
    -- and it should look like one -- what says "lit" is the pool it throws and
    -- the panes below, not a pole washed yellow.
    for i = 1, #sites do
      Voxel3D.draw(authored.body, tex, xf[i], 0, xf[i])
    end

    -- The lantern. Its panes already carry the GLB's emissive burnt into the
    -- basecolor, so by day they read as warm glass under the ordinary tint and
    -- need no pass of their own. After dusk they are flattened most of the way
    -- to the lamp's colour, which is what keeps them burning through a DEEP
    -- night instead of being tinted out with everything else.
    if authored.glass then
      if lit > 0.05 then
        Voxel3D.flatten(lampColor, 0.55 + 0.45 * lit)
      end
      for i = 1, #sites do
        Voxel3D.draw(authored.glass, tex, xf[i], 0, xf[i])
      end
      if lit > 0.05 then
        Voxel3D.flatten(nil)
      end
    end
    return
  end

  local tpl = buildTemplates()
  local tex = ensureTex()
  if not tpl or not tex then return end

  -- poles first (receive shade, cast via sun path if included — see cast)
  for _, s in ipairs(sites) do
    local t = tpl[s.style] or tpl.classic
    if t and t.pole then
      local m = Mat4.translate(s.wx, 0, s.wz)
      Voxel3D.draw(t.pole, tex, m, 0, m)
    end
  end

  -- heads: glow when the hour has lamps on
  if lit > 0.05 then
    -- amount climbs with the hour so dusk is a half-glow and midnight is full
    local amount = 0.40 + 0.60 * lit
    Voxel3D.flatten(lampColor, amount)
  end
  for _, s in ipairs(sites) do
    local t = tpl[s.style] or tpl.classic
    if t and t.head then
      local m = Mat4.translate(s.wx, 0, s.wz)
      Voxel3D.draw(t.head, tex, m, 0, m)
    end
  end
  if lit > 0.05 then
    Voxel3D.flatten(nil)
  end
end

-- Shadow casters for the sun pass: poles only on the box models (heads are
-- small and would speck the ground).  Authored mesh casts as a whole.
function StreetLamps.castShadows(map)
  if not StreetLamps.enabled() then return end
  if not Voxel3D.available() then return end
  local sites = sitesFor(map)
  if #sites == 0 then return end
  local ShadowMap = V.require("ShadowMap")
  local authored = loadMesh3d()
  if authored then
    local tex = loadTex3d() or ensureTex()
    -- Ironwork only. The lantern's panes are the light source; casting them
    -- would print a shadow of the thing doing the lighting.
    for _, s in ipairs(sites) do
      local yaw = cellHash(map.id, s.cx, s.cy) * math.pi * 2
      local m = Mat4.mul(Mat4.translate(s.wx, 0, s.wz), Mat4.rotateY(yaw))
      pcall(ShadowMap.draw, authored.body, tex, ShadowMap.snug(m))
    end
    return
  end
  local tpl = buildTemplates()
  local tex = ensureTex()
  if not (tpl and tex) then return end
  for _, s in ipairs(sites) do
    local t = tpl[s.style] or tpl.classic
    if t and t.pole then
      local m = Mat4.translate(s.wx, 0, s.wz)
      pcall(ShadowMap.draw, t.pole, tex, ShadowMap.snug(m))
    end
  end
end

-- For probes / debug: how many posts a map would get.
function StreetLamps.count(map)
  return #sitesFor(map)
end

return StreetLamps
