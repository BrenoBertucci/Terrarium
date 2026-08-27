-- A particle field as geometry, so the depth buffer can hide it.
--
-- ------- WHY THIS EXISTS
--
-- Every particle in this mod used to be painted in the OVERLAY: the pass
-- main.lua opens after the diorama is finished, with the depth test off by
-- construction (Voxel3D.beginOverlay calls setDepthMode with nothing). The
-- comment in Weather.lua said so outright -- "no depth test, this is the
-- overlay". Which means dust passed in front of the mountain, and rain fell
-- in front of the house it was supposed to be falling behind, always.
--
-- Drawn as geometry inside the scene pass instead, the hardware answers
-- both of those, exactly, for free -- and the particle also picks up the
-- scene's own light and the sun's shadow map, because the pass's fragment
-- shader does that to everything it draws.
--
-- ------- THE BILLBOARD IS ONE ROTATION, NOT A LOOK-AT
--
-- This engine's cards "always face SOUTH and only LEAN BACK by the camera's
-- pitch" (SpriteBillboards) -- the free-roam camera is an orbit with a
-- pitch and no yaw, so every card in the frame shares one orientation.
-- VoxelScene builds that as Mat4.rotateX(angle - pi/2) per card. A hundred
-- particles do not want a hundred matrices, so the same rotation is baked
-- straight into the vertices here: with t = angle - pi/2, a point (u, v) in
-- card space lands at
--
--   world = (x + u,  y + v*cos t,  z + v*sin t)
--
-- which is eight multiply-adds per vertex and one draw call for the field.
--
-- ------- AND THE SIZE IS IN WORLD UNITS NOW
--
-- The overlay sized every mote in SCREEN pixels and multiplied by the
-- projection's own scale to fake perspective. Geometry does not need the
-- fake: a quad of a given world size shrinks with distance because it is
-- actually further away. The numbers carried over are the old screen sizes
-- read as world pixels, which is what they always meant at the focus plane.
--
-- ------- BATCHING
--
-- Voxel3D.FORMAT has no colour attribute -- it is position, UV and a shade
-- float, shared with terrain and characters, and widening it for particles
-- would touch every mesh in the mod. So colour comes from setColor, which
-- is per DRAW, which means particles that share a colour have to be
-- contiguous in the mesh. They are bucketed by (image, colour, quantised
-- fade) and drawn as ranges of one mesh with the uniforms sent once -- the
-- shape Voxel3D.drawGroup already uses for terrain chunks.
--
-- Fade is quantised rather than exact because it is the only per-particle
-- term in the colour and an exact one would put every particle in its own
-- bucket. Most of a mote's life is spent at full fade (it fades in over a
-- quarter second and out over four tenths, out of a life of one to five
-- seconds), so the buckets stay few.

local V = ...

local Voxel3D = V.require("Voxel3D")
local VoxelState = V.require("VoxelState")

local ParticleMesh = {}

local sin, cos = math.sin, math.cos
local floor = math.floor

-- How many steps the fade is rounded to. Four is enough that the ramp still
-- reads as a ramp at the speed a mote fades, and few enough that the field
-- does not shatter into a bucket per particle.
ParticleMesh.FADE_STEPS = 4

-- ------- THE BUILDER
--
-- One per client, holding its own mesh and its own scratch tables, because
-- a builder that allocated per frame would undo the pooling next door.
local Builder = {}
Builder.__index = Builder

function ParticleMesh.newBuilder(capacity)
  return setmetatable({
    cap = tonumber(capacity) or 256,
    mesh = nil,
    verts = {},          -- reused vertex table
    batches = {},        -- key -> { img, r, g, b, a, first, count, items }
    order = {},          -- batch keys in emit order
    scratch = {},        -- reused per-batch item lists
  }, Builder)
end

local function ensureMesh(self)
  if self.mesh then return self.mesh end
  -- Stream usage: the whole buffer is rewritten every frame, which is
  -- exactly what "stream" tells the driver to expect.
  local ok, m = pcall(love.graphics.newMesh, Voxel3D.FORMAT,
                      self.cap * 4, "triangles", "stream")
  if not ok then return nil end
  local map = {}
  for n = 0, self.cap - 1 do Voxel3D.pushQuad(map, n) end
  pcall(m.setVertexMap, m, map)
  self.mesh = m
  return m
end

function Builder:release()
  if self.mesh and self.mesh.release then pcall(self.mesh.release, self.mesh) end
  self.mesh = nil
end

-- ------- BUILD
--
-- `describe(p)` is the client's own read of one particle, and returns
--
--   img            the image to sample (identity is half the batch key)
--   u0, v0, u1, v1 UV corners inside it
--   halfW, halfH   world half-extents of the card
--   ang            in-plane rotation, radians
--   r, g, b, a     colour and alpha
--
-- or nil to skip the particle entirely. Returning nil is how a client drops
-- what it does not want drawn without having to hold a second list.
--
-- Returns the mesh and the batch list, or nil when there is nothing to draw.
function Builder:build(field, describe)
  return self:buildCards(field:count(),
                         function(i) return field:get(i) end,
                         function(p, push)
                           push(describe(p))
                         end)
end

-- ------- THE GENERAL FORM: N CARDS PER THING
--
-- A wind mote is one card, which is what build() above assumes. A
-- butterfly is two, a firefly is a glow and a core, a dragonfly is a body
-- and two wings -- the ambient life draws every critter as a handful of
-- small rectangles rather than as one sprite. So the emitter is handed a
-- `push` and may call it as many times as the creature has parts.
--
--   at(i)          the i-th thing
--   emit(p, push)  calls push(img, u0,v0,u1,v1, halfW,halfH, ang, r,g,b,a)
--                  once per card, or not at all to skip
--
-- push takes the card's offset from the thing's own world point through
-- the two extra arguments after the colour: a wing is not AT the butterfly,
-- it is beside it, and the offset is in the card's own plane so it leans
-- with everything else.
function Builder:buildCards(n, at, emit)
  if n == 0 then return nil end
  local mesh = ensureMesh(self)
  if not mesh then return nil end

  -- ------- A STAMP, NOT A SWEEP OF LAST FRAME'S LIST
  --
  -- This reset used to walk the PREVIOUS frame's `order` and zero those
  -- batches. `batches` is a persistent map, though, so any batch whose key
  -- was not in that particular list kept a stale count -- and the test
  -- below for "is this batch already in this frame's order" was
  -- `bt.n == 0`, which a stale count fails. The batch then collected cards
  -- that were never emitted, and a field made entirely of such batches
  -- built nothing at all while reporting no error.
  --
  -- A per-build stamp cannot go stale: a batch belongs to this frame if it
  -- carries this frame's number, whatever it did on any frame before.
  local batches, order = self.batches, self.order
  for i = #order, 1, -1 do order[i] = nil end
  local stamp = (self.stamp or 0) + 1
  self.stamp = stamp

  local steps = ParticleMesh.FADE_STEPS
  local cap = self.cap

  -- Diagnostics. A builder that returns nil is indistinguishable from one
  -- whose emitter chose to draw nothing, and telling those apart by
  -- reading the code has already cost more than counting would have.
  self.nEmit, self.nPush, self.nDropped = 0, 0, 0

  -- ------- pass one: bucket
  local cur = nil       -- the thing whose cards are being pushed
  local function push(img, u0, v0, u1, v1, halfW, halfH, ang, r, g, b, a,
                      offU, offV)
    self.nPush = self.nPush + 1
    if not (img and a and a > 0.02) then
      self.nDropped = self.nDropped + 1
      return
    end
    local q = floor(a * steps + 0.5)
    if q < 1 then q = 1 elseif q > steps then q = steps end
    -- colour is already one of a handful of flat palette entries, so
    -- rounding it to 8 bits collides exactly the way it should
    local key = tostring(img) .. "|"
             .. floor(r * 255) .. "," .. floor(g * 255) .. ","
             .. floor(b * 255) .. "|" .. q
    local bt = batches[key]
    if not bt then
      bt = { img = img, items = {}, n = 0 }
      batches[key] = bt
    end
    if bt.stamp ~= stamp then
      bt.stamp = stamp
      bt.n = 0
      order[#order + 1] = key
    end
    bt.r, bt.g, bt.b = r, g, b
    bt.a = q / steps
    local m = bt.n + 1
    bt.n = m
    local it = bt.items[m]
    if not it then it = {}; bt.items[m] = it end
    it[1], it[2], it[3] = cur.x, cur.y, cur.z
    it[4], it[5], it[6], it[7] = u0, v0, u1, v1
    it[8], it[9], it[10] = halfW, halfH, ang or 0
    it[11], it[12] = offU or 0, offV or 0
  end

  for i = 1, n do
    cur = at(i)
    if cur then
      self.nEmit = self.nEmit + 1
      emit(cur, push)
    end
  end
  if #order == 0 then return nil end

  -- ------- pass two: emit, batch by batch, so a batch is one range
  local t = (VoxelState.angle or 0) - math.pi / 2
  local ct, st = cos(t), sin(t)
  local verts = self.verts
  local vi = 0
  local quads = 0

  for oi = 1, #order do
    local bt = batches[order[oi]]
    bt.first = quads * 6 + 1
    local count = 0
    for k = 1, bt.n do
      if quads >= cap then break end
      local it = bt.items[k]
      local x, y, z = it[1], it[2], it[3]
      local u0, v0, u1, v1 = it[4], it[5], it[6], it[7]
      local hw, hh, ang = it[8], it[9], it[10]
      local offU, offV = it[11] or 0, it[12] or 0
      local ca, sa = cos(ang), sin(ang)
      -- the card's four corners in its own plane, rotated in-plane, shifted
      -- to where this PART of the creature sits, then leaned back by the
      -- camera's pitch on the way into world space
      for c = 1, 4 do
        local lu = (c == 1 or c == 2) and -hw or hw
        local lv = (c == 1 or c == 4) and -hh or hh
        local ru = lu * ca - lv * sa + offU
        local rv = lu * sa + lv * ca + offV
        vi = vi + 1
        local vt = verts[vi]
        if not vt then vt = {}; verts[vi] = vt end
        vt[1] = x + ru
        vt[2] = y + rv * ct
        vt[3] = z + rv * st
        vt[4] = (c == 1 or c == 2) and u0 or u1
        vt[5] = (c == 1 or c == 4) and v1 or v0
        -- Full brightness. A particle has no face turned away from the
        -- sun -- it is a card -- so the per-vertex darken that gives an
        -- extruded block its solidity would only make dust grey. The
        -- sun's own shadow still applies: that is the shader's shadow map
        -- lookup, which runs on everything the pass draws.
        vt[6] = 1
      end
      quads = quads + 1
      count = count + 1
    end
    bt.count = count * 6
  end

  if quads == 0 then return nil end
  -- trailing slots from a previous, bigger frame are left in the buffer;
  -- the draw ranges below never reach them
  for i = #verts, vi + 1, -1 do verts[i] = nil end
  pcall(mesh.setVertices, mesh, verts)

  self.liveBatches = self.liveBatches or {}
  local out = self.liveBatches
  for i = #out, 1, -1 do out[i] = nil end
  for oi = 1, #order do
    local bt = batches[order[oi]]
    if bt.count and bt.count > 0 then out[#out + 1] = bt end
  end
  return mesh, out
end

ParticleMesh.Builder = Builder

return ParticleMesh
