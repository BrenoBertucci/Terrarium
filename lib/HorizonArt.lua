-- THE HORIZON ART: a painted distant panorama, ported from ADVANCED_SHAPE's
-- lib/Backdrop.lua so this merged mod's horizon reads with the same art
-- rather than Terrarium's own flat-coloured silhouettes.
--
-- A painted cylinder wrapped 360 degrees and centred on the player, drawn
-- BEHIND lib/Skyline.lua's real map-shaped massing: this is the paper sky
-- at the very back of the diorama, and Skyline's coarse height fields (the
-- actual placed towns and routes the connection graph found) still stand
-- in front of it as real geometry. The two layer the way a painted
-- backdrop and a model railway's foreground scenery do -- distance behind,
-- shape in front.
--
-- Centred on the player is the whole trick: a cylinder that follows you
-- never gets closer, which is exactly how a horizon behaves. A slow drift
-- of the texture against world position adds the last touch -- walk far
-- enough and the mountains slide across the sky -- without ever letting
-- the player reach them.
--
-- Drawn after the sky and before the terrain, with depth writes off, so
-- every piece of real world (and every Skyline silhouette) draws over it
-- and it never occludes anything. Interiors and canopy maps skip it, same
-- as ADVANCED_SHAPE's version did.
--
-- Unlike the original, this copy is NOT a patch for a separate companion
-- mod: the art ships right beside this file (lib/backdrop.png, carried
-- over from ADVANCED_SHAPE), so there is no orphan check and no external
-- config bridge to go looking for.

local V = ...

local Voxel3D = V.require("Voxel3D")
local Mat4 = V.require("Mat4")
local okDN, DayNight = pcall(V.require, "DayNight")

local HorizonArt = {}

local RADIUS = 900        -- far enough to read as distance, inside far plane
local SEGMENTS = 64       -- around the full circle
local Y_BOTTOM = -120     -- skirt below the horizon: no gap under the band
local Y_TOP = 300         -- headroom above it
local DRIFT = 1 / 24000   -- texture drift per world pixel walked

local mesh, image, failed = nil, nil, false

local function status(s) _G.__horizonart_status = s end
status("loaded; awaiting the first outdoor frame")

-- Draw blocks run inside this rather than a bare pcall. Every one of them
-- changes graphics state -- colour, alpha, depth mode -- and a bare pcall
-- that throws midway leaves that state set for the rest of the frame.
-- push("all")/pop() restores the lot whatever happens inside.
local function guarded(fn)
  local g = love and love.graphics
  if not (g and g.push and g.pop) then return pcall(fn) end
  local pushed = pcall(g.push, "all")
  local ok = pcall(fn)
  if pushed then pcall(g.pop) end
  return ok
end

local OPEN_AIR_TILESETS = {
  OVERWORLD = true, FOREST = true, PLATEAU = true, SHIP_PORT = true,
}

local function isOutdoor(map)
  local def = map and map.def
  if not def then return false end
  if okDN and DayNight and DayNight.isCanopy then
    local okC, canopy = pcall(DayNight.isCanopy, map)
    if okC and canopy then return false end
  end
  local tid = def.tileset or (map.tileset and map.tileset.id)
  if tid and OPEN_AIR_TILESETS[tid] then return true end
  local ok, outdoor = pcall(function()
    local Map = require("src.world.Map")
    return Map.isOutdoor and Map.isOutdoor(def)
  end)
  if ok and outdoor ~= nil then return outdoor end
  local conns = def.connections
  return (conns and next(conns) ~= nil) and true or false
end

-- the cylinder, built once: a ring of quads facing inward, uv running once
-- around the circumference
local function build()
  local verts, indexMap, quads = {}, {}, 0
  for i = 0, SEGMENTS - 1 do
    local a0 = (i / SEGMENTS) * math.pi * 2
    local a1 = ((i + 1) / SEGMENTS) * math.pi * 2
    local x0, z0 = math.cos(a0) * RADIUS, math.sin(a0) * RADIUS
    local x1, z1 = math.cos(a1) * RADIUS, math.sin(a1) * RADIUS
    local u0, u1 = i / SEGMENTS, (i + 1) / SEGMENTS
    -- wound so the painted face looks INWARD at the player
    verts[#verts + 1] = { x1, Y_TOP, z1, u1, 0, 1 }
    verts[#verts + 1] = { x0, Y_TOP, z0, u0, 0, 1 }
    verts[#verts + 1] = { x0, Y_BOTTOM, z0, u0, 1, 1 }
    verts[#verts + 1] = { x1, Y_BOTTOM, z1, u1, 1, 1 }
    Voxel3D.pushQuad(indexMap, quads)
    quads = quads + 1
  end
  return Voxel3D.newMesh(verts, indexMap)
end

-- the panorama, shipped right beside this file -- carried over from
-- ADVANCED_SHAPE/lib/backdrop.png -- loaded relative to this mod's own
-- V.path so it works regardless of the folder the merged mod is installed
-- under.
local function texture()
  if image or failed then return image end
  local ok, img = pcall(function()
    local path = (V.path or "") .. "/lib/backdrop.png"
    local im = love.graphics.newImage(path)
    im:setWrap("repeat", "clamp")
    im:setFilter("nearest", "nearest")
    return im
  end)
  if ok and img then
    image = img
    status("loaded backdrop from lib/backdrop.png")
  else
    failed = true
    status("backdrop.png missing or unreadable")
  end
  return image
end

function HorizonArt.draw(state)
  local map = state and state.map
  if not map then
    status("no map available")
    return
  end
  if not isOutdoor(map) then
    status("indoors -- no horizon to paint")
    return
  end

  local tex = texture()
  if not tex then return end

  if not mesh then
    mesh = build()
    if not mesh then
      failed = true
      status("driver refused the backdrop mesh")
      return
    end
  end

  local p = state.player
  local px = (p and p.px) or 0
  local pz = (p and p.py) or 0

  guarded(function()
    -- behind everything: test against depth but never write to it, so no
    -- real geometry -- including Skyline's silhouettes -- can ever be
    -- occluded by the painting
    love.graphics.setDepthMode("lequal", false)
    -- disable shader to prevent water reflection effects on backdrop
    love.graphics.setShader()
    Voxel3D.draw(mesh, tex, Mat4.translate(px, 0, pz))
    love.graphics.setShader()
  end)
  status(("drawn at r=%d, drift %.3f"):format(RADIUS, (px * DRIFT) % 1))
end

function HorizonArt.invalidate()
  if mesh then pcall(mesh.release, mesh) end
  mesh = nil
end

return HorizonArt
