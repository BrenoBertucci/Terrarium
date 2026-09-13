-- The puddles, rebuilt as a SURFACE rather than a sticker.
--
-- ------- what was wrong with the decals, in the words it was reported in
--
-- "They break out of nowhere": a pool was one of three baked sprites at
-- three baked sizes, and the wetness clock picked which one. So a pool
-- did not GROW, it was replaced -- 13 px, then 20, then 28, each one a
-- different drawing landing on the same cell in a single frame. A stack
-- of stickers swapped by a clock is exactly what "breaks out of nowhere"
-- describes.
--
-- "They appear in the water, on the lake": a basin's decal was 38 world
-- pixels wide on a 16-pixel cell, jittered off its centre, and the score
-- that picked which cell got it REWARDED water neighbours -- so the
-- widest pools were placed on the bank and hung nineteen pixels out over
-- the lake, floating at ground height above a surface that lies at -2.
--
-- "They burst and only the outline shows": the sprite's body was painted
-- at 0.22 of a sky tone that was itself taken to 0.34, and its one-pixel
-- rim at 1.0. Under the SCREEN FX row the reflection replaced the body and the
-- bright rim was the only pixel left that said "puddle".
--
-- ------- what this is instead
--
-- A DEPTH FIELD. Every map cell that can hold water gets, once, a
-- height-below-the-street number per texel -- eight texels to a cell,
-- one 128x128 texture per 16-cell chunk -- built from the same hashed,
-- spaced seeds GroundFX has always placed (so "one pool per eleven cells
-- of ground" is still a claim the probe can count), with the shape of
-- each pool an ellipse with a noisy rim rather than a drawing. Then ONE
-- number per frame, the ground's wetness, is a WATERLINE across that
-- field: the pool is wherever the field lies below the line. As the
-- shower works the line drops and the water spreads out from the deepest
-- point, a texel at a time, and as the street dries it recedes the same
-- way. Nothing is swapped and nothing pops.
--
-- The field is cut at the CELL: a texel over a water cell, a grass cell,
-- a wall, a door, or a cell at a different height from the pool's own is
-- zero, and stays zero at every wetness. That is the whole of "never on
-- the lake" -- the shape cannot leave the ground it was placed on, and a
-- cell that touches open water is not ground it is placed on at all.
--
-- ------- and it is drawn as WATER, with its own shader
--
-- The scene shader draws a decal as a textured card: alpha cut at a
-- half, colour times the hour. Standing water is none of those things.
-- So the pools have a shader of their own, drawn in the same decal slot
-- (between the terrain and the people standing in it, depth-tested and
-- depth-writing, exactly where the decals were), and the pixel is built
-- from what a thin film over dark paving actually does:
--
--   it REFLECTS THE SKY. The reflected ray is bent by the ripples and
--   looks up into the dome, and the colour is the palette's own bands --
--   the horizon where the ray is shallow, the zenith where it is steep.
--   A puddle at sunset is orange because the sky is; at night it is the
--   night's blue. Under the SCREEN FX row the screen pass replaces this with a
--   real reflection (the alpha tag is still stamped, see GroundFX), and
--   without it this IS the reflection.
--
--   it CATCHES THE SUN. A Blinn lobe off the rippled normal toward the
--   sun ShadowMap already knows the direction of, scaled by daylight and
--   killed by overcast -- a glint that walks across the pool as the rain
--   dimples it.
--
--   it RIPPLES. Rain rings, one impact per cell on its own hashed clock
--   (the same construction RayFX uses, so the two agree when both run), a
--   fine chop scrolled off a tiling noise texture, and the rings a boot
--   or a rain shaft leaves, pushed in from GroundFX and Weather. All of it
--   dies with the shower, so the aftermath is a still mirror.
--
--   it has a WET HALO. The street around a pool is darker before there
--   is a pool and after it has gone -- damp paving, which is what says
--   "it rained" more than the water does. It is the same field read at a
--   lower line, so it is always exactly the pool's own shape, a little
--   wider.
--
-- ------- what it costs, and what it does not touch
--
-- One bake per chunk per map, cached like the terrain (a few
-- milliseconds each, two per frame at most so a map's worth arrives over
-- a handful of frames). Per frame: one quad per touched cell, one draw
-- per chunk in reach plus the alpha stamp, one small texture bound. No
-- new render target, no new attribute, no change to the scene shader.
--
-- GLES: no uniform is declared in a region both stages compile (the
-- 1.31 link rule -- see the note over VXHP in Voxel3D), the fragment
-- stage raises its precision under the same guard Voxel3D's does and is
-- dropped if the driver refuses it, every coordinate the fragment stage
-- sees is CHUNK-LOCAL (0..256, fp16-safe) rather than world, and the only
-- hashes it uses are read from textures rather than computed from a
-- position -- the 1.34 television-interference lesson, applied before
-- rather than after.
--
-- If the shader will not build at all, GroundFX keeps drawing the old
-- decals. Degrade quietly, as everything here does.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...
local WaterMap = V.require("WaterMap")
local Voxel3D = V.require("Voxel3D")
local Mat4 = V.require("Mat4")
local DayNight = V.require("DayNight")
local Water = V.require("Water")
local ShadowMap = V.require("ShadowMap")

local PuddleFX = {}

-- GroundFX requires THIS file, so it is fetched lazily where it is needed
-- (seed placement, canopy) rather than required back.
local function ground()
  local ok, G = pcall(V.require, "GroundFX")
  return ok and G or nil
end

-- ------- the numbers

PuddleFX.TEXELS = 8               -- texels per cell edge (2 world px each)
PuddleFX.CHUNK = 16               -- cells per chunk edge, same as GroundFX
PuddleFX.MARGIN = 3               -- cells of neighbouring chunks a seed reaches

-- A pool's radius in CELLS: base plus a share of the seed's score, so a
-- gutter is a pool you walk around and a flat street's pool is a hand
-- across. At the top a pool is three and a half cells wide.
PuddleFX.RADIUS_BASE = 0.55
PuddleFX.RADIUS_SCORE = 1.00
-- And not every block that may hold a pool gets one: GroundFX's rule
-- fills four blocks in five, which with pools this wide ran a plaza
-- together into one sheet. A second hash thins it to this share.
PuddleFX.FILL = 0.78
-- How much the rim wanders off the ellipse, in field units, and the two
-- scales of the wander in world pixels. Kept OFF the pool's centre (it is
-- multiplied by how far out this texel is) so a pool is born clean and
-- gets ragged as it widens, which is the order rain does it in.
PuddleFX.NOISE = 0.34
PuddleFX.NOISE_SCALE = { 6.5, 15.0 }
-- Where the waterline sits at wet = 1: not zero, so a full pool still
-- has a rim of damp street around it rather than filling its own halo.
PuddleFX.THR_FULL = 0.09
-- How far below the waterline the damp halo reaches, in field units.
PuddleFX.DAMP = 0.26
-- The field is stored biased so the halo has room below zero.
PuddleFX.FIELD_LO = -0.30

PuddleFX.ALPHA = 0.94             -- how opaque the water is
PuddleFX.DAMP_ALPHA = 0.50        -- how dark the damp street goes
PuddleFX.TONE = 0.22              -- the paving under the film, of the sky's hue
PuddleFX.FRESNEL_MIN = 0.30       -- a film reflects even seen from above
PuddleFX.MIRROR = 0.64            -- and hands back this much of the sky
-- How much a ripple's slope lights and shades the film. A ring on a pool
-- that reflects a flat overcast sky is INVISIBLE by reflection alone --
-- every bent ray finds the same grey -- and under a shower the sun is
-- gone too. What the eye actually sees on such a pool is the crest lit
-- from the bright half of the dome and the trough shaded by the dark
-- half, so that is drawn: a fixed light from high in the sky, off the
-- slope, before the reflection is mixed in.
PuddleFX.RIPPLE_SHADE = 0.55
PuddleFX.GLINT = 1.4
PuddleFX.GLINT_POWER = 64

-- The rain's own surface. Same construction and nearly the same numbers
-- as RayFX's rainSlope, on purpose: when the screen pass takes over the
-- pixel the two must not disagree about how a pool moves.
PuddleFX.CHOP = 0.16              -- slope from the scrolled noise
PuddleFX.RING = 0.55              -- an impact ring's height, world px
PuddleFX.RING_FREQ = 0.62         -- radians per world pixel
PuddleFX.RING_REACH = 6.5         -- world px a ring travels before it dies
PuddleFX.RAIN_RATE = 1.9          -- impacts per cell per second

-- Rings made by feet and rain shafts. Four, like RayFX.FOOT_MAX.
PuddleFX.FOOT_MAX = 4
PuddleFX.FOOT_TTL = 0.62

-- Bakes allowed per frame: a map's worth of chunks arrives over a few
-- frames rather than as one stutter on the first wet frame.
PuddleFX.BAKES_PER_FRAME = 6

-- 0..1, the ground's wetness. Written by GroundFX every tick; it is the
-- waterline and everything else here is a function of it.
PuddleFX.level = 0

-- ------- state

local CHUNK = PuddleFX.CHUNK
local fields = {}          -- key -> { img, mesh, cellMax = {}, seeds = n } or false
local bakesThisFrame = 0
local noiseImg = nil       -- the tiling chop texture, or false
local shader = nil         -- nil untried, false refused
local shaderHighp = false  -- did the FRAG_HIGHP line take
local feet = {}
local IDENTITY = Mat4.identity()

-- ------- the hash, GroundFX's own, so seeds land where its probe says

local function hash(text)
  local h = 5381
  local s = tostring(text)
  for i = 1, #s do
    h = (h * 33 + s:byte(i)) % 2147483647
  end
  return h
end

local function unit(h) return (math.floor(h / 977) % 100000) / 100000 end

-- A numeric hash for the field's noise: called tens of thousands of times
-- per bake, so no string is built. Stable across chunks -- keyed on the
-- world texel -- so the rim wander is continuous across a chunk seam.
local function nhash(x, y)
  local s = math.sin(x * 12.9898 + y * 78.233) * 43758.5453
  return s - math.floor(s)
end

-- Value noise, 0..1, lattice spacing `L` world pixels.
local function vnoise(x, y, L)
  local fx, fy = x / L, y / L
  local ix, iy = math.floor(fx), math.floor(fy)
  local tx, ty = fx - ix, fy - iy
  tx = tx * tx * (3 - 2 * tx)
  ty = ty * ty * (3 - 2 * ty)
  local a = nhash(ix, iy)
  local b = nhash(ix + 1, iy)
  local c = nhash(ix, iy + 1)
  local d = nhash(ix + 1, iy + 1)
  local top = a + (b - a) * tx
  local bot = c + (d - c) * tx
  return top + (bot - top) * ty
end

-- ------- what a cell is

local function groundAt(map, cx, cy)
  local VoxelScene = V.require("VoxelScene")
  local ok, h = pcall(VoxelScene.groundAt, map, cx, cy)
  return (ok and h) or 0
end

-- Where water may LIE. Walkable, not water, not grass, not a door -- and
-- not next to open water either: a pool on the bank of a lake is a pool
-- that would have drained into it, and it is the one place the old decals
-- were seen floating.
local DIRS4 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function eligible(map, cx, cy)
  if not map:inBounds(cx, cy) then return false end
  if WaterMap.surfaceCell(map, cx, cy) then return false end
  if map:isWaterCell(cx, cy) then return false end
  if not map:isWalkableCell(cx, cy) then return false end
  if map:isGrassCell(cx, cy) then return false end
  if map:warpAtCell(cx, cy) then return false end
  for _, d in ipairs(DIRS4) do
    local nx, ny = cx + d[1], cy + d[2]
    if map:inBounds(nx, ny) and WaterMap.surfaceCell(map, nx, ny) then
      return false
    end
  end
  return true
end

-- ------- the seeds
--
-- GroundFX.holdsPuddle is the placement rule and it is not rewritten here:
-- one pool per block of nine cells, four blocks in five, the block's own
-- hash choosing which cell, stable forever. What this adds is the SHAPE
-- each seed grows into.
local function seedsFor(map, x0, y0, x1, y1)
  local G = ground()
  if not G then return {} end
  local out = {}
  for cy = y0, y1 do
    for cx = x0, x1 do
      if eligible(map, cx, cy) and G.holdsPuddle(map, cx, cy)
         and G.canopyOver(cx, cy) < G.CANOPY_DRY then
        local s = G.puddleScore(map, cx, cy)
        if s < 0 then s = 0 end
        local k = hash(map.id .. "|pool|" .. cx .. "," .. cy)
        local u1, u2, u3, u4 = unit(k), unit(k * 7 + 3), unit(k * 13 + 5),
                               unit(k * 19 + 11)
        if unit(k * 23 + 17) >= PuddleFX.FILL then goto skip end
        local r = (PuddleFX.RADIUS_BASE + PuddleFX.RADIUS_SCORE * s)
                  * 16 * (0.88 + u3 * 0.24)
        local ex = 0.72 + u4 * 0.56      -- elongation: 0.72 .. 1.28
        local ang = u1 * math.pi
        out[#out + 1] = {
          x = cx * 16 + 8 + (u1 - 0.5) * 6,
          z = cy * 16 + 8 + (u2 - 0.5) * 6,
          r = r,
          h = groundAt(map, cx, cy),
          amp = 0.45 + 0.55 * s,
          cs = math.cos(ang), sn = math.sin(ang),
          ex = ex,
          cx = cx, cy = cy,
        }
      end
      ::skip::
    end
  end
  return out
end

-- ------- the bake
--
-- One field per chunk. Seeds are gathered from a margin of MARGIN cells
-- around it so a pool that straddles the seam is drawn whole on both sides,
-- and the field is splatted seed by seed over each one's own bounding box
-- rather than asked for at every texel -- a pool touches a few hundred
-- texels, a chunk has sixteen thousand.
local function bakeChunk(map, chunkX, chunkY)
  local T = PuddleFX.TEXELS
  local N = T * CHUNK
  local cx0, cy0 = chunkX * CHUNK, chunkY * CHUNK
  local wx0, wz0 = cx0 * 16, cy0 * 16
  local M = PuddleFX.MARGIN
  local seeds = seedsFor(map, cx0 - M, cy0 - M, cx0 + CHUNK - 1 + M,
                         cy0 + CHUNK - 1 + M)
  if #seeds == 0 then return false end

  -- eligibility and height per cell, over the chunk and its margin
  local elig, hgt = {}, {}
  local function cellKey(cx, cy) return cx * 4096 + cy end
  local function cellInfo(cx, cy)
    local k = cellKey(cx, cy)
    local e = elig[k]
    if e == nil then
      e = eligible(map, cx, cy)
      elig[k] = e
      hgt[k] = e and groundAt(map, cx, cy) or 0
    end
    return e, hgt[k]
  end

  local LO = PuddleFX.FIELD_LO
  local D = {}                       -- texel -> field value, sparse
  local touchedCells = {}            -- cellKey -> true, in-chunk only
  local cellMax = {}                 -- cellKey -> max field, in-chunk only
  local pxPerTexel = 16 / T

  for _, s in ipairs(seeds) do
    -- the box holds everything above FIELD_LO: the ellipse's long axis,
    -- out to where amp * (1 - d) crosses the floor
    local reach = s.r * math.max(s.ex, 1 / s.ex) * (1 - LO / s.amp) + 2
    local tx0 = math.floor((s.x - reach - wx0) / pxPerTexel)
    local tx1 = math.floor((s.x + reach - wx0) / pxPerTexel)
    local tz0 = math.floor((s.z - reach - wz0) / pxPerTexel)
    local tz1 = math.floor((s.z + reach - wz0) / pxPerTexel)
    if tx0 < 0 then tx0 = 0 end
    if tz0 < 0 then tz0 = 0 end
    if tx1 > N - 1 then tx1 = N - 1 end
    if tz1 > N - 1 then tz1 = N - 1 end
    for tz = tz0, tz1 do
      local wz = wz0 + (tz + 0.5) * pxPerTexel
      local cy = math.floor(wz / 16)
      for tx = tx0, tx1 do
        local wx = wx0 + (tx + 0.5) * pxPerTexel
        local cx = math.floor(wx / 16)
        local e, h = cellInfo(cx, cy)
        if e and h == s.h then
          local dx, dz = wx - s.x, wz - s.z
          -- elliptical distance in units of the radius
          local ax = (dx * s.cs + dz * s.sn) / s.ex
          local az = (-dx * s.sn + dz * s.cs) * s.ex
          local d = math.sqrt(ax * ax + az * az) / s.r
          local v = s.amp * (1 - d)
          if v > LO then
            local idx = tz * N + tx
            local cur = D[idx]
            if cur == nil or v > cur then
              D[idx] = v
              local ck = cellKey(cx, cy)
              touchedCells[ck] = true
              local m = cellMax[ck]
              if m == nil or v > m then cellMax[ck] = v end
            end
          end
        end
      end
    end
  end

  -- the rim wander, on every touched texel, scaled OFF the centre
  local NS1, NS2 = PuddleFX.NOISE_SCALE[1], PuddleFX.NOISE_SCALE[2]
  for idx, v in pairs(D) do
    local tx = idx % N
    local tz = (idx - tx) / N
    local wx = wx0 + (tx + 0.5) * pxPerTexel
    local wz = wz0 + (tz + 0.5) * pxPerTexel
    local n = vnoise(wx, wz, NS1) * 0.6 + vnoise(wx + 37.1, wz + 91.7, NS2) * 0.4
    local core = v
    if core < 0 then core = 0 elseif core > 1 then core = 1 end
    D[idx] = v + (n - 0.5) * PuddleFX.NOISE * (1 - core)
  end

  -- and the cell maxima with the wander in, for poolAt
  for ck in pairs(touchedCells) do cellMax[ck] = nil end
  for idx, v in pairs(D) do
    local tx = idx % N
    local tz = (idx - tx) / N
    local cx = math.floor((wx0 + (tx + 0.5) * pxPerTexel) / 16)
    local cy = math.floor((wz0 + (tz + 0.5) * pxPerTexel) / 16)
    local ck = cellKey(cx, cy)
    local m = cellMax[ck]
    if m == nil or v > m then cellMax[ck] = v end
  end

  -- ------- the texture
  --
  --   R  the field, biased: (D - LO) / (1 - LO), zero where nothing may lie
  --   G  the CELL's own hash, constant over the cell: the ring's clock
  --   B  fine per-texel noise: the chop's seed, and the glint's grain
  local okD, data = pcall(love.image.newImageData, N, N)
  if not okD or not data then return false end
  local span = 1 - LO
  local cellHashes = {}
  local okM = pcall(data.mapPixel, data, function(tx, tz)
    local v = D[tz * N + tx]
    local r = 0
    if v ~= nil then
      r = (v - LO) / span
      if r < 0 then r = 0 elseif r > 1 then r = 1 end
    end
    local cx = cx0 + math.floor(tx / T)
    local cy = cy0 + math.floor(tz / T)
    local ck = cx * 4096 + cy
    local g = cellHashes[ck]
    if g == nil then
      g = unit(hash(map.id .. "|ring|" .. cx .. "," .. cy))
      cellHashes[ck] = g
    end
    local b = nhash(wx0 + tx * 0.5, wz0 + tz * 0.5)
    return r, g, b, 1
  end)
  if not okM then return false end
  local okI, img = pcall(love.graphics.newImage, data)
  if not (okI and img) then return false end
  pcall(img.setFilter, img, "linear", "linear")
  pcall(img.setWrap, img, "clamp", "clamp")

  -- ------- the mesh: one quad per touched cell, on that cell's own ground
  --
  -- Cell-aligned exactly, which is the geometric half of "never over the
  -- lake": the quad cannot reach a neighbour the field says nothing about.
  local verts, indices = {}, {}
  local lift = (ground() and ground().PUDDLE) or 0.7
  local n = 0
  for ck in pairs(touchedCells) do
    local cy = ck % 4096
    local cx = (ck - cy) / 4096
    if cx >= cx0 and cx < cx0 + CHUNK and cy >= cy0 and cy < cy0 + CHUNK then
      local _, h = cellInfo(cx, cy)
      local y = h + lift
      local x0, z0 = cx * 16, cy * 16
      local u0, v0 = (cx - cx0) / CHUNK, (cy - cy0) / CHUNK
      local u1, v1 = u0 + 1 / CHUNK, v0 + 1 / CHUNK
      verts[#verts + 1] = { x0, y, z0, u0, v0, 1 }
      verts[#verts + 1] = { x0 + 16, y, z0, u1, v0, 1 }
      verts[#verts + 1] = { x0 + 16, y, z0 + 16, u1, v1, 1 }
      verts[#verts + 1] = { x0, y, z0 + 16, u0, v1, 1 }
      Voxel3D.pushQuad(indices, n)
      n = n + 1
    end
  end
  if n == 0 then return false end
  local mesh = Voxel3D.newMesh(verts, indices)
  if not mesh then return false end
  pcall(mesh.setTexture, mesh, img)

  -- in-chunk cell maxima only, keyed for poolAt
  local inChunk = {}
  for ck, m in pairs(cellMax) do
    local cy = ck % 4096
    local cx = (ck - cy) / 4096
    if cx >= cx0 and cx < cx0 + CHUNK and cy >= cy0 and cy < cy0 + CHUNK then
      inChunk[ck] = m
    end
  end
  return { img = img, mesh = mesh, cellMax = inChunk, seeds = #seeds,
           quads = n, ox = wx0, oz = wz0 }
end

-- How many bakes have run this session, and the last one's cost -- for
-- the probe, which has to be able to say "a map costs this much".
PuddleFX.bakes = 0
PuddleFX.lastBakeMs = 0

local function fieldFor(map, chunkX, chunkY, allowBake)
  local key = map.id .. "#" .. chunkX .. "#" .. chunkY
  local f = fields[key]
  if f ~= nil then return f or nil end
  if allowBake == false then return nil end
  if bakesThisFrame >= PuddleFX.BAKES_PER_FRAME then return nil end
  bakesThisFrame = bakesThisFrame + 1
  local t0 = love.timer and love.timer.getTime and love.timer.getTime() or 0
  local ok, built = pcall(bakeChunk, map, chunkX, chunkY)
  if love.timer and love.timer.getTime then
    PuddleFX.lastBakeMs = (love.timer.getTime() - t0) * 1000
  end
  PuddleFX.bakes = PuddleFX.bakes + 1
  fields[key] = (ok and built) or false
  return fields[key] or nil
end

-- For the probe: the baked record of one chunk, baking it on the spot.
function PuddleFX.fieldFor(map, chunkX, chunkY)
  bakesThisFrame = 0
  return fieldFor(map, chunkX, chunkY, true)
end

-- The waterline for a wetness. Everything that asks "is there water here"
-- asks this so the shader and the Lua side cannot disagree.
function PuddleFX.waterline(level)
  level = level or PuddleFX.level
  if level < 0 then level = 0 elseif level > 1 then level = 1 end
  return 1 - level * (1 - PuddleFX.THR_FULL)
end

-- Is there standing water on this cell RIGHT NOW? The field's own answer,
-- so a rain shaft aimed at a pool lands in one and a boot leaving one
-- leaves a print. Bakes the chunk if it has to -- the rain asks about
-- cells before they are drawn.
function PuddleFX.poolAt(map, cx, cy)
  if PuddleFX.level <= 0.01 then return false end
  local f = fieldFor(map, math.floor(cx / CHUNK), math.floor(cy / CHUNK))
  if not f then return false end
  local m = f.cellMax[cx * 4096 + cy]
  if not m then return false end
  return m >= PuddleFX.waterline() + 0.03
end

-- How DEEP the water on this cell stands, 0..1 of a full pool: the cell's
-- field maximum above the waterline, over the room the line has left. A
-- boot in a gutter throws more than a boot in a film, and this is the
-- number that says which is which.
function PuddleFX.depthAt(map, cx, cy)
  if PuddleFX.level <= 0.01 then return 0 end
  local f = fieldFor(map, math.floor(cx / CHUNK), math.floor(cy / CHUNK))
  if not f then return 0 end
  local m = f.cellMax[cx * 4096 + cy]
  local wl = PuddleFX.waterline()
  if not m or m < wl + 0.03 then return 0 end
  local d = (m - wl) / math.max(0.05, 1 - wl)
  if d > 1 then d = 1 end
  return d
end

-- Every cell of a square block that holds water at the current wetness --
-- the probe's table, the same shape GroundFX.puddleCells has.
function PuddleFX.poolCells(map, x0, y0, side)
  local out = {}
  for cy = y0, y0 + side - 1 do
    for cx = x0, x0 + side - 1 do
      if PuddleFX.poolAt(map, cx, cy) then out[#out + 1] = { cx, cy } end
    end
  end
  return out
end

-- ------- rings

PuddleFX.ripples = 0        -- rings ever pushed, for the probes

function PuddleFX.ripple(wx, wz)
  PuddleFX.ripples = PuddleFX.ripples + 1
  feet[#feet + 1] = { x = tonumber(wx) or 0, z = tonumber(wz) or 0, t = 0 }
  while #feet > PuddleFX.FOOT_MAX do table.remove(feet, 1) end
end

function PuddleFX.step(dt)
  dt = dt or 0
  for i = #feet, 1, -1 do
    feet[i].t = feet[i].t + dt
    if feet[i].t >= PuddleFX.FOOT_TTL then table.remove(feet, i) end
  end
  bakesThisFrame = 0
end

-- ------- the shader

-- The precision line is the same rung Voxel3D climbs first and drops if
-- refused: both halves of the guard are load-bearing (see the long note
-- over VX_GLOBAL_HP there). effect()'s float parameters are pinned to
-- mediump to agree with LOVE's own forward declaration on GLES.
local PRECISION = [[
#ifdef PIXEL
#if defined(GL_ES) && defined(GL_FRAGMENT_PRECISION_HIGH)
precision highp float;
#endif
#endif
]]

local SHADER = [[
varying vec2 vLocal;       // world XZ minus the chunk's origin: 0..256
varying vec3 vView;        // toward the eye, unit length
varying vec2 vUV;

#ifdef VERTEX
  uniform mat4 vp;
  uniform mat4 model;
  uniform vec4 curve;      // xy = focus in world XZ, z = k, w = cap
  uniform vec3 eye;
  uniform vec2 origin;     // the chunk's world XZ corner
  vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec4 w = model * vertex_position;
    vLocal = w.xz - origin;
    // normalised HERE, in the stage that is highp everywhere: eye - w runs
    // to hundreds of world pixels and its square overflows fp16
    vView = normalize(eye - w.xyz);
    vUV = VertexTexCoord.xy;
    if (curve.z > 0.0) {
      vec2 cd = w.xz - curve.xy;
      w.y -= min(dot(cd, cd) * curve.z, curve.w);
    }
    return vp * w;
  }
#endif

#ifdef PIXEL
  uniform Image field;
  uniform Image chop;
  uniform float level;      // the ground's wetness, 0..1
  uniform float thrFull;
  uniform float damp;       // how far below the line the halo reaches
  uniform float rain;       // the shower now, 0..1
  uniform float ringClock;  // fract(t * rate)
  uniform float ringFreq;
  uniform float ringReach;
  uniform float ringAmp;
  uniform float chopAmp;
  uniform vec2 chopA;       // scroll of the two chop samples, in tiles
  uniform vec2 chopB;
  uniform vec3 horizon;     // the sky's low band
  uniform vec3 zenith;      // and its high one
  uniform vec3 tone;        // the paving under the film
  uniform vec3 tint;        // the hour's light on that paving
  uniform vec3 sunDir;      // the direction the light TRAVELS
  uniform float sunK;       // how much sun there is to catch
  uniform float glint;
  uniform float glintPow;
  uniform float fresMin;
  uniform float mirror;
  uniform float rippleShade;
  uniform float alpha;
  uniform float dampAlpha;
  uniform float stamp;      // >0: write this into alpha and nothing else
  uniform vec3 foot0;       // chunk-local x, z, life
  uniform vec3 foot1;
  uniform vec3 foot2;
  uniform vec3 foot3;

  void addFoot(inout vec2 g, vec2 p, vec3 f) {
    if (f.z <= 0.001) return;
    vec2 d = p - f.xy;
    float r = length(d);
    if (r < 0.001 || r > 16.0) return;
    float life = f.z;
    float R = (1.0 - life) * 13.0;
    float env = exp(-abs(r - R) * 0.32) * life;
    g += (d / r) * (-sin((r - R) * 0.70) * 0.70 * env * 0.85);
  }

  vec4 effect(mediump vec4 color, Image tex, mediump vec2 tc, mediump vec2 sc) {
    vec4 f = Texel(field, vUV);
    // the field, unbiased: FIELD_LO .. 1
    float D = f.r * 1.30 - 0.30;
    float thr = 1.0 - level * (1.0 - thrFull);
    float pool = smoothstep(thr - 0.025, thr + 0.025, D);
    if (stamp > 0.0) {
      if (pool < 0.5) discard;
      return vec4(0.0, 0.0, 0.0, stamp);
    }
    float halo = smoothstep(thr - damp, thr - 0.015, D) * (1.0 - pool);
    float dampK = min(1.0, level * 2.5);
    float ad = halo * dampK * dampAlpha;
    float ap = pool * alpha;
    if (ap < 0.004 && ad < 0.01) discard;

    // ------- the surface
    vec2 g = vec2(0.0);
    if (rain > 0.0) {
      // the scatter: two scrolled reads of a tiling noise, as a slope
      float n1 = Texel(chop, vLocal * (1.0 / 44.0) + chopA).r;
      float n2 = Texel(chop, vLocal * (1.0 / 29.0) + chopB).g;
      g += (vec2(n1, n2) - 0.5) * (chopAmp * rain);
      // the ring: this cell's own impact on this cell's own clock. The
      // clock is read from the field at the cell's CENTRE texel so the
      // linear filter cannot blend two cells' clocks at the seam.
      vec2 cell = floor(vLocal / 16.0);
      vec2 cuv = (cell * 16.0 + 9.0) / 256.0;
      float k = Texel(field, cuv).g;
      vec2 c = (cell + vec2(0.30 + k * 0.40, 0.30 + fract(k * 7.31) * 0.40)) * 16.0;
      vec2 d = vLocal - c;
      float r = length(d);
      if (r > 0.001) {
        float life = fract(ringClock + k);
        float R = life * ringReach;
        float env = exp(-abs(r - R) * 0.45) * (1.0 - life);
        g += (d / r) * (-sin((r - R) * ringFreq) * ringFreq * env * ringAmp * rain);
      }
    }
    addFoot(g, vLocal, foot0);
    addFoot(g, vLocal, foot1);
    addFoot(g, vLocal, foot2);
    addFoot(g, vLocal, foot3);
    vec3 N = normalize(vec3(-g.x, 1.0, -g.y));
    vec3 Vv = normalize(vView);
    float ndv = max(dot(N, Vv), 0.0);
    vec3 R = reflect(-Vv, N);

    // ------- what the film shows: the sky, off the bent ray
    float up = clamp(R.y, 0.0, 1.0);
    vec3 sky = mix(horizon, zenith, up * up) * mirror;
    float fres = fresMin + (1.0 - fresMin) * pow(1.0 - ndv, 2.0);
    vec3 col = mix(tone * tint, sky, fres);
    // the sun, where the bent ray finds it
    float spec = pow(max(dot(R, -sunDir), 0.0), glintPow) * sunK;
    col += horizon * spec * glint;
    // the ripple's own light and shade -- see RIPPLE_SHADE
    col += horizon * ((g.x * 0.6 - g.y * 0.8) * rippleShade);
    // the meniscus: the last texels before dry ground catch a little light
    float rim = (1.0 - smoothstep(thr + 0.02, thr + 0.11, D)) * pool;
    col += vec3(0.14, 0.15, 0.16) * rim;

    // ------- and the damp street around it, composited under
    vec3 dampCol = vec3(0.04, 0.05, 0.07) * tint;
    float at = ap + ad * (1.0 - ap);
    vec3 c = (col * ap + dampCol * ad * (1.0 - ap)) / max(at, 0.001);
    return vec4(c, at);
  }
#endif
]]

function PuddleFX.compile()
  if shader ~= nil then return shader or nil end
  if not (love.graphics and love.graphics.newShader) then
    shader = false
    return nil
  end
  local ok, sh = pcall(love.graphics.newShader, PRECISION .. SHADER)
  if ok and sh then
    shader, shaderHighp = sh, true
    return sh
  end
  PuddleFX.compileError = tostring(sh)
  ok, sh = pcall(love.graphics.newShader, SHADER)
  if ok and sh then
    shader, shaderHighp = sh, false
    return sh
  end
  PuddleFX.compileError = tostring(sh)
  shader = false
  return nil
end

function PuddleFX.available()
  return PuddleFX.compile() ~= nil
end

function PuddleFX.highp()
  return shaderHighp
end

-- ------- the chop texture: tiling value noise, built once

local function chopTexture()
  if noiseImg ~= nil then return noiseImg or nil end
  if not (love.image and love.graphics) then noiseImg = false return nil end
  local S = 64
  local ok, data = pcall(love.image.newImageData, S, S)
  if not ok or not data then noiseImg = false return nil end
  local function tnoise(x, y, L, salt)
    local fx, fy = x / L, y / L
    local ix, iy = math.floor(fx), math.floor(fy)
    local tx, ty = fx - ix, fy - iy
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    local P = S / L
    local function h(a, b) return nhash((a % P) + salt, (b % P) + salt * 3) end
    local a, b = h(ix, iy), h(ix + 1, iy)
    local c, d = h(ix, iy + 1), h(ix + 1, iy + 1)
    local top = a + (b - a) * tx
    local bot = c + (d - c) * tx
    return top + (bot - top) * ty
  end
  pcall(data.mapPixel, data, function(x, y)
    local r = tnoise(x, y, 8, 1) * 0.65 + tnoise(x, y, 4, 2) * 0.35
    local g = tnoise(x, y, 8, 5) * 0.65 + tnoise(x, y, 4, 7) * 0.35
    return r, g, 0, 1
  end)
  local okI, img = pcall(love.graphics.newImage, data)
  if not (okI and img) then noiseImg = false return nil end
  pcall(img.setFilter, img, "linear", "linear")
  pcall(img.setWrap, img, "repeat", "repeat")
  noiseImg = img
  return img
end

-- ------- the light this frame

local function clamp01(v)
  if v < 0 then return 0 end
  return v > 1 and 1 or v
end

local function band(pal, i)
  local c = pal and pal[i]
  if not c then return { 0.55, 0.65, 0.85 } end
  return { c[1] / 255, c[2] / 255, c[3] / 255 }
end

local function lightNow()
  local okP, pal = pcall(DayNight.palette)
  if not okP then pal = nil end
  local horizon = band(pal, 1)
  local zenith = band(pal, 5)
  local okT, tint = pcall(DayNight.tint, true)
  if not (okT and tint) then tint = { 1, 1, 1 } end
  -- the paving under the film: the sky's HUE, dark
  local m = math.max(horizon[1], horizon[2], horizon[3], 0.001)
  local tone = { horizon[1] / m * PuddleFX.TONE, horizon[2] / m * PuddleFX.TONE,
                 horizon[3] / m * PuddleFX.TONE }
  local day = (tint[1] + tint[2] + tint[3]) / 3
  local sunK = clamp01((day - 0.45) / 0.4)
                * (1 - clamp01(DayNight.overcast or 0))
                * (1 - clamp01(DayNight.storm or 0))
  return horizon, zenith, tone, tint, sunK
end

-- ------- the draw
--
-- `places` is GroundFX's list of { map, ox, oy }: the map underfoot and the
-- neighbours drawn at their seam offsets. Returns the number of chunk
-- draws issued and how many of them were stamps -- two numbers, because
-- "it drew" and "the mask went down" are two different claims.
PuddleFX.lastDraws = 0
PuddleFX.lastStamps = 0

function PuddleFX.draw(places, px, py, level, reach)
  PuddleFX.lastDraws, PuddleFX.lastStamps = 0, 0
  local sh = PuddleFX.compile()
  if not sh then return 0, 0 end
  local chop = chopTexture()
  if not chop then return 0, 0 end
  PuddleFX.level = level or PuddleFX.level
  if PuddleFX.level <= 0.01 then return 0, 0 end

  local g = love.graphics
  local prev = g.getShader()
  g.setShader(sh)
  local send = function(name, ...) pcall(sh.send, sh, name, ...) end

  send("vp", "row", Voxel3D.vp or IDENTITY)
  send("curve", { Voxel3D.curveX or 0, Voxel3D.curveZ or 0,
                  Voxel3D.curveK or 0, Voxel3D.curveCap or 0 })
  local eye = Voxel3D.eye or { 0, 0, 0 }
  send("eye", { eye[1] or 0, eye[2] or 0, eye[3] or 0 })

  send("chop", chop)
  send("level", PuddleFX.level)
  send("thrFull", PuddleFX.THR_FULL)
  send("damp", PuddleFX.DAMP)
  local okR, rain = pcall(Water.rain)
  rain = (okR and tonumber(rain)) or 0
  send("rain", clamp01(rain))
  local t = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
  send("ringClock", (t * PuddleFX.RAIN_RATE) % 1)
  send("ringFreq", PuddleFX.RING_FREQ)
  send("ringReach", PuddleFX.RING_REACH)
  send("ringAmp", PuddleFX.RING)
  send("chopAmp", PuddleFX.CHOP)
  send("chopA", { (t * 0.13) % 1, (t * 0.09) % 1 })
  send("chopB", { (-t * 0.07) % 1, (t * 0.11) % 1 })
  local horizon, zenith, tone, tint, sunK = lightNow()
  send("horizon", horizon)
  send("zenith", zenith)
  send("tone", tone)
  send("tint", { tint[1] or 1, tint[2] or 1, tint[3] or 1 })
  local sd = (ShadowMap.sunDir and ShadowMap.sunDir()) or { 0, -1, 0 }
  send("sunDir", sd)
  send("sunK", sunK)
  send("glint", PuddleFX.GLINT)
  send("glintPow", PuddleFX.GLINT_POWER)
  send("fresMin", PuddleFX.FRESNEL_MIN)
  send("mirror", PuddleFX.MIRROR)
  send("rippleShade", PuddleFX.RIPPLE_SHADE)
  send("alpha", PuddleFX.ALPHA)
  send("dampAlpha", PuddleFX.DAMP_ALPHA)

  reach = reach or 11
  local drawn, stamped = 0, 0

  -- one walk of the chunks in reach, drawing each; `stamp` picks the pass
  local function pass(stampTag)
    send("stamp", stampTag or 0)
    local n = 0
    for _, place in ipairs(places) do
      local map = place.map
      local ox, oz = place.ox or 0, place.oy or 0
      local lx = px - math.floor(ox / 16)
      local ly = py - math.floor(oz / 16)
      local model = (ox ~= 0 or oz ~= 0) and Mat4.translate(ox, 0, oz) or IDENTITY
      local c0x = math.floor((lx - reach) / CHUNK)
      local c1x = math.floor((lx + reach) / CHUNK)
      local c0y = math.floor((ly - reach) / CHUNK)
      local c1y = math.floor((ly + reach) / CHUNK)
      for cy = c0y, c1y do
        for cx = c0x, c1x do
          local f = fieldFor(map, cx, cy)
          if f then
            send("model", "row", model)
            send("origin", { f.ox + ox, f.oz + oz })
            send("field", f.img)
            for i = 0, 3 do
              local ft = feet[i + 1]
              send("foot" .. i, ft and { ft.x - f.ox - ox, ft.z - f.oz - oz,
                                         1 - ft.t / PuddleFX.FOOT_TTL }
                                or { 0, 0, 0 })
            end
            g.draw(f.mesh)
            n = n + 1
          end
        end
      end
    end
    return n
  end

  g.setColor(1, 1, 1, 1)
  drawn = pass(0)
  if Voxel3D.beginAlphaStamp(Voxel3D.PUDDLE_TAG) then
    stamped = pass(Voxel3D.PUDDLE_TAG)
    Voxel3D.endAlphaStamp()
  end

  g.setShader(prev)
  g.setColor(1, 1, 1, 1)
  PuddleFX.lastDraws, PuddleFX.lastStamps = drawn, stamped
  return drawn, stamped
end

-- ------- and letting go

-- The map changed, or a block on it was rewritten: a field is a fact
-- about a map and is dropped with it. With a map id only THAT map's
-- fields go -- a Cut tree on the route is not a reason to rebuild the
-- town next door -- and without one everything does. Counted, because a
-- probe has to be able to tell "the pools came back over three frames"
-- from "the pools are being thrown away every frame".
PuddleFX.invalidations = 0

function PuddleFX.invalidate(mapId)
  PuddleFX.invalidations = PuddleFX.invalidations + 1
  local prefix = mapId and (tostring(mapId) .. "#") or nil
  for key, f in pairs(fields) do
    if not prefix or key:sub(1, #prefix) == prefix then
      if f and f.mesh and f.mesh.release then pcall(f.mesh.release, f.mesh) end
      if f and f.img and f.img.release then pcall(f.img.release, f.img) end
      fields[key] = nil
    end
  end
  if not prefix then feet = {} end
end

-- Window resize / hot reload: the GPU objects go, the shader is retried.
function PuddleFX.dropGPU()
  PuddleFX.invalidate()
  noiseImg = nil
  shader = nil
end

return PuddleFX
