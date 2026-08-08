-- Voxel world mode: the rest of Kanto, standing on the horizon.
--
-- THE PROBLEM, as a measurement. tests/aerial_probe.lua puts the camera on
-- ROUTE_1 at the low rung and finds the drawn world ending 145 pixels
-- ABOVE nothing and 145 pixels BELOW its own vanishing line -- a fifth of
-- the frame is empty sky between where the ground stops and where the
-- geometry says the horizon is, and everything above that is empty too.
-- The map is not small because the tiles are small. It is small because
-- past the border trees there is provably nothing, and the eye reads
-- "nothing" as "edge of the world".
--
-- Meanwhile tests/skyline_probe.lua walks the connection graph from the
-- same spot and finds eight to twenty-one further maps already placed,
-- spanning some THIRTY view-heights. The world is sixty times wider than
-- the part being drawn. None of it is missing; all of it is unplaced
-- geometry.
--
-- THE ANSWER is the one the PlayStation 2 and the Nintendo 64 both
-- reached for, and it is not "draw more world". Distant land is a few
-- dozen pixels tall on screen and it does not deserve -- cannot afford --
-- the mesh the ground under your feet gets. It deserves a SILHOUETTE: the
-- shape of the land against the sky, and nothing else. Death Mountain is
-- visible from every field in Hyrule and is a handful of triangles until
-- you walk to it.
--
-- So each far map becomes a coarse height field:
--
--   * built from the map DEF alone -- width, height, blocks, tileset --
--     which is generated data already resident for all 223 maps. No
--     MapLoader, no tile batch, no atlas, no texture. Placing and drawing
--     the whole region costs no memory that was not already spent.
--   * one sample grid two blocks across, so a town is a mass and a route
--     is a ribbon and neither is a tile.
--   * untextured and flat-coloured, because at ten view-heights out the
--     haze (lib/Aerial.lua) is going to crush it most of the way to the
--     sky colour anyway -- and that crushing is the point. Ridge behind
--     ridge, each paler than the last, is what distance looks like.
--   * cached by map id and never rebuilt, because a map's shape does not
--     depend on where you are standing. Only its offset does, and that
--     is a translate.
--
-- WHAT IT IS NOT is world. It has no collision, no warps, no encounters,
-- no NPCs and no tiles; nothing reads it and nothing can walk on it. It
-- sits two pixels lower than real ground so that wherever a silhouette and
-- an actual meshed map overlap, the real one wins without a depth fight.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Voxel3D = V.require("Voxel3D")
local Mat4 = V.require("Mat4")
local WorldAtlas = V.require("WorldAtlas")
local ModSetting = V.require("ModSetting")
local Sky = V.require("Sky")

local Map = require("src.world.Map")

local Skyline = {}

Skyline.KEY = "skyline"
Skyline.LABEL = "HORIZON"

-- The sample grid, in BLOCKS (a block is 32 world pixels, 2x2 cells). Two
-- is the coarsest step that still tells a town from the route it sits on:
-- at four, Pewter and the road through it merged into one slab.
Skyline.STEP = 2

-- How tall a "mass" coarse cell stands before the rung's exaggeration, in
-- world pixels. One cell -- the height the mesher gives a tree or a wall --
-- so a silhouette at its own scale is exactly as tall as the real thing it
-- stands in for.
Skyline.MASS_H = 16

-- A coarse cell is mass when at least this share of its cells are blocked.
-- Not a majority: a route is mostly walkable ground with a tree line down
-- each side, and at 0.5 the whole of Kanto's road network vanished and the
-- horizon became a row of disconnected towns.
Skyline.MASS_SHARE = 0.34

-- VERTICAL EXAGGERATION, and this is the second half of the trick rather
-- than a cheat on top of it. Land twenty view-heights away subtends almost
-- nothing: at true scale the far half of the region is a one-pixel line on
-- the horizon and might as well not be drawn. Every game that has ever
-- sold a big landscape from a low camera has raised the far ground -- the
-- N64 did it because it had to, and it turns out to be what the eye wants
-- anyway, because a horizon that STACKS reads as receding while a flat one
-- reads as a wall.
--
-- Applied per draw as a Y scale in the model matrix, so it costs nothing
-- and rebuilds nothing. Grows with distance from the player, in
-- view-heights, and CAPS -- past the cap the land is as tall as it is
-- going to get, which stops the far edge of the region from towering over
-- the near towns and inverting the depth cue the whole file exists for.
Skyline.LIFT_PER_VH = 0.55
Skyline.LIFT_MAX = 5.0

-- Sunk this far, so real geometry always wins an overlap outright rather
-- than fighting for the depth buffer along a seam.
Skyline.SINK = 2

-- The ladder is HOW FAR OUT the silhouettes go, in view-heights from the
-- player. Distance rather than detail: the mesh is already the cheapest
-- thing in the frame, and what actually costs is how many of them are
-- submitted.
Skyline.REACHES = { 0, 6, 14, 30 }

Skyline.setting = ModSetting.new(Skyline.KEY, Skyline.LABEL,
                                 { 0, 1, 2, 3 },
                                 { "OFF", "NEAR", "FAR", "ALL" })

function Skyline.level()
  return Skyline.setting:get() or 0
end

function Skyline.active()
  return Skyline.level() > 0
end

function Skyline.reach()
  return Skyline.REACHES[Skyline.level() + 1] or 0
end

-- ------- the height field

-- Blocked-cell lookup for one tileset, hashed once. Map.defIsWalkableCell
-- does a linear scan of the walkable list per call and this file asks it
-- about a couple of thousand cells per map.
local walkSets = {}

local function walkSet(tilesetDef)
  local id = tilesetDef and tilesetDef.id
  if not id then return nil end
  local s = walkSets[id]
  if s then return s end
  s = {}
  for _, t in ipairs(tilesetDef.walkable or {}) do s[t] = true end
  walkSets[id] = s
  return s
end

local function tilesetFor(def)
  local ok, Game = pcall(require, "src.core.Game")
  local d = ok and Game and Game.data or nil
  return d and d.tilesets and d.tilesets[def.tileset] or nil
end

-- The coarse mass grid for one map def: gw x gh booleans, one per STEP x
-- STEP block cell, true where the land stands up.
local function massGrid(def, tilesetDef)
  local set = walkSet(tilesetDef)
  if not set then return nil, 0, 0 end
  local gw = math.ceil(def.width / Skyline.STEP)
  local gh = math.ceil(def.height / Skyline.STEP)
  if gw < 1 or gh < 1 then return nil, 0, 0 end
  local grid = {}
  for gy = 0, gh - 1 do
    for gx = 0, gw - 1 do
      local blocked, total = 0, 0
      -- kept, not just thresholded: the SHARE is what makes the horizon a
      -- profile instead of a bar. A coarse cell that is a thin tree line
      -- beside a road and one that is the solid middle of a city are both
      -- "mass", and drawing them the same height is what made the first
      -- cut read as a girder laid across the sky.
      -- a block is 2x2 cells, so a STEP-block coarse cell is 2*STEP cells
      local c0x, c0y = gx * Skyline.STEP * 2, gy * Skyline.STEP * 2
      for cy = c0y, c0y + Skyline.STEP * 2 - 1 do
        for cx = c0x, c0x + Skyline.STEP * 2 - 1 do
          if cx < def.width * 2 and cy < def.height * 2 then
            total = total + 1
            local tile = Map.defCellTile(def, tilesetDef, cx, cy)
            if tile == nil or not set[tile] then blocked = blocked + 1 end
          end
        end
      end
      local share = total > 0 and (blocked / total) or 0
      -- 0 for flat, otherwise a height in world pixels that runs from
      -- about half MASS_H at the threshold to a little over it when the
      -- cell is solid
      grid[gy * gw + gx] = share >= Skyline.MASS_SHARE
                           and Skyline.MASS_H * (0.45 + 0.75 * share)
                           or 0
    end
  end
  return grid, gw, gh
end

-- Face shades. The magnitude darkens a face by its angle; the SIGN carries
-- the normal's Y, and negative means up (see the vertex shader). Flatter
-- steps than the terrain mesher's, on purpose: this is a silhouette read
-- through haze, and strong side shading would put contrast into the one
-- part of the frame the haze is there to take it out of.
local TOP_SHADE = -1.0
local SIDE_SHADE = 0.78

local function pushTop(verts, x0, z0, x1, z1, y)
  verts[#verts + 1] = { x0, y, z0, 0, 0, TOP_SHADE }
  verts[#verts + 1] = { x1, y, z0, 0, 0, TOP_SHADE }
  verts[#verts + 1] = { x1, y, z1, 0, 0, TOP_SHADE }
  verts[#verts + 1] = { x0, y, z1, 0, 0, TOP_SHADE }
end

local function pushSide(verts, ax, az, bx, bz, y0, y1)
  verts[#verts + 1] = { ax, y0, az, 0, 0, SIDE_SHADE }
  verts[#verts + 1] = { bx, y0, bz, 0, 0, SIDE_SHADE }
  verts[#verts + 1] = { bx, y1, bz, 0, 0, SIDE_SHADE }
  verts[#verts + 1] = { ax, y1, az, 0, 0, SIDE_SHADE }
end

-- Cached impostors, by map id. Never evicted: one is a few hundred
-- vertices with no texture, and a map's shape does not change.
local meshes = {}

local function build(def, id)
  local tilesetDef = tilesetFor(def)
  if not tilesetDef then return false end
  local grid, gw, gh = massGrid(def, tilesetDef)
  if not grid then return false end

  local S = Skyline.STEP * 32          -- coarse cell size in world pixels
  local H = Skyline.MASS_H
  local verts, tris, n = {}, {}, 0

  local function at(gx, gy)
    if gx < 0 or gy < 0 or gx >= gw or gy >= gh then return 0 end
    return grid[gy * gw + gx] or 0
  end

  for gy = 0, gh - 1 do
    for gx = 0, gw - 1 do
      local y = at(gx, gy)
      local x0, z0 = gx * S, gy * S
      local x1, z1 = x0 + S, z0 + S
      pushTop(verts, x0, z0, x1, z1, y)
      Voxel3D.pushQuad(tris, n); n = n + 1
      -- Sides only down to whatever the NEIGHBOUR stands at, not to the
      -- ground: with the heights varied there are steps everywhere inside
      -- a town, and skirting each one to y=0 would triple the mesh to draw
      -- walls buried inside their own hill.
      if y > 0 then
        local sides = {
          { at(gx, gy - 1), x0, z0, x1, z0 },
          { at(gx, gy + 1), x1, z1, x0, z1 },
          { at(gx - 1, gy), x0, z1, x0, z0 },
          { at(gx + 1, gy), x1, z0, x1, z1 },
        }
        for _, s in ipairs(sides) do
          if s[1] < y then
            pushSide(verts, s[2], s[3], s[4], s[5], s[1], y)
            Voxel3D.pushQuad(tris, n); n = n + 1
          end
        end
      end
    end
  end

  meshes[id] = Voxel3D.newMesh(verts, tris) or false
  return meshes[id] and true or false
end

-- ------- the colour
--
-- Not a constant, and not the map's own palette either. The silhouette is
-- read through the haze, so it is defined AS the haze: the hour's palest
-- sky band (Sky.haze, the same value the frame is cleared to) pulled part
-- of the way toward dark. That single line is why the horizon is gold at
-- dusk and navy at midnight without this file owning a clock, a palette or
-- a single colour of its own -- and why the near end of the skyline and
-- the far end of the real world are always the same family of colours.
Skyline.INK = 0.30        -- how far toward dark the NEAREST silhouette pulls

-- AND THE HAZE IS APPLIED HERE, on the CPU, per map -- not left to the
-- shader's fog, which is the obvious thing and is wrong. lib/Aerial.lua's
-- ramp is calibrated against the drawn world and saturates about half a
-- view-height out, because that is where the drawn world ENDS. Every
-- silhouette in this file stands between six and thirty view-heights out,
-- so all of them sit past the top of that ramp and every one of them gets
-- the identical maximum haze -- which is exactly no depth cue at all. The
-- first cut looked like one flat girder laid across the sky for precisely
-- this reason.
--
-- A silhouette is drawn by this file with a colour of this file's
-- choosing, so it can simply be given its own ramp over its own range, and
-- ridge-behind-ridge falls straight out: each map paler than the one in
-- front of it, all the way to the far edge of the region dissolving into
-- the sky it is standing against.
Skyline.FADE_START = 3.0   -- view-heights: nearest silhouette, full ink
Skyline.FADE_END = 22.0    -- view-heights: gone but for a suggestion
Skyline.FADE_MAX = 0.92    -- never all the way, or the far land is a hole

-- `d` is the distance to the map, in view-heights.
local function inkColor(haze, d)
  local k = 1 - Skyline.INK
  local r, g, b = haze[1] * k, haze[2] * k, haze[3] * k
  local t = (d - Skyline.FADE_START)
            / math.max(1e-6, Skyline.FADE_END - Skyline.FADE_START)
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  t = t * Skyline.FADE_MAX
  return r + (haze[1] - r) * t,
         g + (haze[2] - g) * t,
         b + (haze[3] - b) * t
end

-- ------- the plate
--
-- One quad under the whole region, and it is not decoration -- it is what
-- stops the horizon from FLOATING. Kanto's connection graph does not tile
-- the plane: there are gaps between the maps it places, and through every
-- gap the first cut showed a slot of sky UNDER the far land, which reads
-- as a slab hanging in the air rather than as ground going away. The plate
-- is the landmass those maps are standing on. It sits below them and below
-- the sink, so anything real -- and every silhouette -- covers it.
--
-- PADDED WELL PAST THE REGION, because the region's own bounding box is
-- not big enough to hide its own corner: the first cut ended the plate at
-- the outermost map and the straight edge of it cut across the sky
-- diagonally, which is a worse artefact than the hole it replaced. The pad
-- is in view-heights so it clears the horizon at any zoom.
Skyline.PLATE_PAD = 24

local plate = { root = nil, mesh = nil, ox = 0, oz = 0 }

local function plateFor(state, vh)
  if plate.root == state.map.id then return plate end
  local x0, z0, x1, z1 = 0, 0, state.map.def.width * 32,
                               state.map.def.height * 32
  local any = false
  for _, e in ipairs(WorldAtlas.around(state.map.id)) do
    any = true
    local ew, eh = e.def.width * 32, e.def.height * 32
    if e.ox < x0 then x0 = e.ox end
    if e.oy < z0 then z0 = e.oy end
    if e.ox + ew > x1 then x1 = e.ox + ew end
    if e.oy + eh > z1 then z1 = e.oy + eh end
  end
  plate.root = state.map.id
  plate.mesh = nil
  if any then
    local pad = Skyline.PLATE_PAD * vh
    x0, z0, x1, z1 = x0 - pad, z0 - pad, x1 + pad, z1 + pad
    local verts = {}
    pushTop(verts, 0, 0, x1 - x0, z1 - z0, 0)
    plate.mesh = Voxel3D.newMesh(verts, { 1, 2, 3, 1, 3, 4 })
    plate.ox, plate.oz = x0, z0
  end
  return plate
end

-- ------- the pass

-- One impostor build per frame at most. A map crossing re-roots the atlas
-- and can want a dozen new silhouettes at once; a seam is the one moment
-- in this renderer that cannot afford a stall, and a horizon that fills in
-- over the next dozen frames is not something a player walking through a
-- gate is ever going to catch.
local builtThisFrame = false

function Skyline.frame()
  builtThisFrame = false
end

-- Draw everything the atlas places that the scene is not already meshing.
-- `cx, cy` is the camera's focus and `vh` the view height, both in world
-- pixels -- the same pair every other distance in this mod is measured
-- against.
function Skyline.draw(state, cx, cy, vh)
  if not Skyline.active() then return 0 end
  if not (state and state.map and vh and vh > 0) then return 0 end

  local haze = Sky.haze()
  if not haze then return 0 end       -- indoors: no sky, no horizon

  local reach = Skyline.reach() * vh
  local drawn = 0

  -- The plate goes down first and at the far end of the fade, so it is the
  -- palest thing in the frame and everything -- real world and silhouette
  -- alike -- stands in front of it.
  local p = plateFor(state, vh)
  if p.mesh then
    local pr, pg, pb = inkColor(haze, Skyline.FADE_END)
    love.graphics.setColor(pr, pg, pb, 1)
    Voxel3D.draw(p.mesh, nil,
                 Mat4.translate(p.ox, -Skyline.SINK - 2, p.oz))
  end

  for _, e in ipairs(WorldAtlas.beyond(state)) do
    local def = e.def
    local w2 = def.width * 16
    local h2 = def.height * 16
    -- distance from the player to the map's middle, which is what decides
    -- both whether it is drawn at all and how far it is lifted
    local dx = (e.ox + w2) - cx
    local dz = (e.oy + h2) - cy
    local d = math.sqrt(dx * dx + dz * dz)
    if d <= reach then
      local mesh = meshes[e.id]
      if mesh == nil and not builtThisFrame then
        builtThisFrame = true
        build(def, e.id)
        mesh = meshes[e.id]
      end
      if mesh then
        local dvh = d / vh
        local lift = 1 + Skyline.LIFT_PER_VH * dvh
        if lift > Skyline.LIFT_MAX then lift = Skyline.LIFT_MAX end
        local r, g, b = inkColor(haze, dvh)
        love.graphics.setColor(r, g, b, 1)
        Voxel3D.draw(mesh, nil,
                     Mat4.mul(Mat4.translate(e.ox, -Skyline.SINK, e.oy),
                              Mat4.scale(1, lift, 1)))
        drawn = drawn + 1
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  return drawn
end

function Skyline.row()
  return Skyline.setting:row()
end

function Skyline.sync(value)
  Skyline.setting:sync(value)
end

-- For the suite and the probe.
Skyline._meshes = meshes
Skyline._massGrid = massGrid

return Skyline
