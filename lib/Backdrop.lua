-- The BACKDROP: a distant horizon for the outdoor world.
-- payload-version: 3
--
-- Dramatic Shape's outdoor maps end where their meshes end -- past the
-- last connected map is sky meeting nothing.  This hangs a painted
-- panorama around the world at a great radius: hills, forest, mountains,
-- a lighthouse headland and a walled town, wrapped 360 degrees and
-- centred on the player, so it reads as distance rather than as scenery.
--
-- Centred on the player is the whole trick.  A cylinder that follows you
-- never gets closer, which is exactly how a horizon behaves: it turns
-- with the camera and refuses to be approached.  A slow drift of the
-- texture against world position adds the last touch -- walk east far
-- enough and the mountains slide across the sky -- without ever letting
-- the player reach them.
--
-- Drawn after the sky and before the terrain, with depth writes off, so
-- every piece of real world draws over it and it never occludes anything.
-- Interiors and canopy maps skip it: the ceiling module owns those.

local V = ...

local Voxel3D = V.require("Voxel3D")
local Mat4 = V.require("Mat4")
local okDN, DayNight = pcall(V.require, "DayNight")

local Backdrop = {}

local RADIUS = 900        -- far enough to read as distance, inside far plane
local SEGMENTS = 64       -- around the full circle
local Y_BOTTOM = -120     -- skirt below the horizon: no gap under the band
local Y_TOP = 300         -- headroom above it
local DRIFT = 1 / 24000   -- texture drift per world pixel walked

local mesh, image, failed = nil, nil, false

local function status(s) _G.__ds_backdrop_status = s end
status("loaded; awaiting the first outdoor frame")

-- interiors and canopy maps belong to the ceiling, not the horizon

-- Draw blocks run inside this rather than a bare pcall.  Every one of
-- them changes graphics state -- colour, alpha, depth mode -- and a bare
-- pcall that throws midway leaves that state set for the REST OF THE
-- FRAME.  Anything drawn after us then inherits it: a stray alpha makes
-- another mod's sprites invisible, a stray depth mode makes them sort
-- wrongly, and the fault looks like theirs.  push("all")/pop() restores
-- the lot whatever happens inside.
local function guarded(fn)
  -- headless, or a driver without a graphics stack: just run it
  local g = love and love.graphics
  if not (g and g.push and g.pop) then return pcall(fn) end
  local pushed = pcall(g.push, "all")
  pcall(fn)
  if pushed then pcall(g.pop) end
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

-- the cylinder, built once: a ring of quads facing inward, uv running
-- once around the circumference
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

-- the panorama itself, written next to this module by the companion mod
local function texture()
  if image or failed then return image end
  local ok, img = pcall(function()
    local path = rawget(_G, "__ds_backdrop_path")
                 or "mods/DRAMATIC_SHAPE/lib/backdrop.png"
    -- Try multiple fallback paths
    local fallbackPaths = {
      path,
      "mods/DRAMATIC_SHAPE/lib/backdrop.png",
      "mods/ds_fp_ceiling/lib/backdrop.png",
      "backdrop.png"
    }
    for _, testPath in ipairs(fallbackPaths) do
      local testOk, testImg = pcall(function()
        return love.graphics.newImage(testPath)
      end)
      if testOk and testImg then
        testImg:setWrap("repeat", "clamp")
        testImg:setFilter("nearest", "nearest")
        status(("loaded backdrop from: %s"):format(testPath))
        return testImg
      end
    end
    return nil
  end)
  if ok and img then
    image = img
  else
    failed = true
    status("backdrop.png missing or unreadable from all paths")
  end
  return image
end

-- If the companion mod has been deleted, its config bridge is gone and
-- this module is an orphan: draw nothing. The ceiling module does the
-- actual clean-up; this just keeps quiet in the meantime.
local function abandoned()
  return rawget(_G, "__ds_ceiling_config") == nil
end

function Backdrop.draw(state)
  if abandoned() then 
    status("ceiling config missing - backdrop disabled")
    return 
  end
  local cfg = {}
  local pub = rawget(_G, "__ds_ceiling_config")
  if type(pub) == "function" then
    local okCfg, c = pcall(pub)
    if okCfg and type(c) == "table" then cfg = c end
  end
  if cfg.backdrop == false then
    status("backdrop switched off in config")
    return
  end

  local map = state and state.map
  if not map then 
    status("no map available")
    return 
  end
  if not isOutdoor(map) then
    status("indoors -- the ceiling owns this map")
    return
  end

  local tex = texture()
  -- the chosen panorama can change while the game is running, so notice
  -- when the published path is not the one we loaded
  local want = rawget(_G, "__ds_backdrop_path")
  if tex and want and want ~= texPath then 
    tex = nil
    status("backdrop path changed, reloading texture")
  end
  if not tex then
    texPath = want
    status("backdrop texture not available")
    return
  end
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

  -- drift: the horizon slides slowly against the world, so walking a long
  -- way east moves the mountains, but never brings them closer
  local okShift = pcall(function()
    tex:setWrap("repeat", "clamp")
  end)

  local drew = true
  guarded(function()
    -- behind everything: test against depth but never write to it, so no
    -- real geometry can ever be occluded by the painting
    love.graphics.setDepthMode("lequal", false)
    Voxel3D.draw(mesh, tex, Mat4.translate(px, 0, pz))
  end)
  if drew then
    status(("drawn at r=%d, drift %.3f"):format(RADIUS, (px * DRIFT) % 1))
  else
    status("draw failed")
  end
end

function Backdrop.invalidate()
  if mesh then pcall(mesh.release, mesh) end
  mesh = nil
end

return Backdrop
