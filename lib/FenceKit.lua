-- Voxel world mode: the FENCES of Vermilion City, built as fences.
--
-- The overworld draws a fence as two little posts a cell ($0E over $55), and
-- the profile's `post` class stood each one as a thin standee: a row of
-- pegs. What stands here is a harbour town's crossbuck fence, in heavy
-- timber:
--
--   the post     four voxels square, one to a cell: tarred where it meets
--                the ground, grain running up it, a knot, an iron collar
--                under a cap that shows its end grain
--   the rails    two, a top one bleached by the sun and a low one, let into
--                the post and bolted to it (an iron head on the post's face)
--   the brace    a lattice between every two posts: each cell builds an X on
--                either side of its post, a voxel a column, and they meet
--                where two cells do
--
-- Rails and brace run only toward a NEIGHBOUR that is fence too, so a run
-- ends in a post, turns a corner in one, and stops either side of a sign.
-- One model per signature (which of N E S W carry on). It stands in whatever
-- ground lib/LavenderGroundKit.lua laid under it first (that kit lays a
-- fence's cell and does not claim it; this template comes after it and does).
--
-- The sheet (assets/buildings/fence_kit.png) is painted by
-- tools/fence_sheet.py. Nothing here is extracted from the ROM.

local V = ...

local Kit = { SHEET = "assets/buildings/fence_kit.png", SHEET_W = 32,
              TILES = { 14, 14, 85, 85 },
              POST_H = 14,             -- to the underside of the cap
              LOW = 3, TOP = 11 }      -- each rail's lower course

local C = 16
local W = Kit.SHEET_W
local IRON, IRON_HI = 24, 25

local function fenceAt(tileAt, tx, ty)
  local t = Kit.TILES
  return tileAt(tx, ty) == t[1] and tileAt(tx + 1, ty) == t[2]
     and tileAt(tx, ty + 1) == t[3] and tileAt(tx + 1, ty + 1) == t[4]
end

-- Which of N E S W carry the fence on: "0110". Also the cache key's tail.
-- `joins(tx, ty)`: is that tile past the map's edge on a side another map
-- is joined to? A run that reaches such an edge is taken to carry on across
-- it -- the next map's tiles are not this one's to read, and a fence that
-- stopped a post short either side of the seam drew the seam.
function Kit.signature(tileAt, tx, ty, joins)
  if Kit.ENABLED == false then return nil end
  local function c(dx, dy)
    local on = fenceAt(tileAt, tx + dx, ty + dy) or (joins and joins(tx + dx, ty + dy))
    return on and "1" or "0"
  end
  return c(0, -2) .. c(2, 0) .. c(0, 2) .. c(-2, 0)
end

-- Each arm in its own frame: `a` runs from the post's face (0) out to the
-- cell's edge (5), `d` across the rail (0..3 over the post's four voxels).
local ARMS = {
  function(x, z) return 5 - z, x - 6 end,       -- north
  function(x, z) return x - 10, z - 6 end,      -- east
  function(x, z) return z - 10, x - 6 end,      -- south
  function(x, z) return 5 - x, z - 6 end,       -- west
}

function Kit.model(sp, sig)
  if not sp or sp.W ~= W then return nil, "sheet is not " .. W .. " wide" end
  local on = {}
  for i = 1, 4 do on[i] = sig:sub(i, i) == "1" end
  local H, LOW, TOP = Kit.POST_H, Kit.LOW, Kit.TOP

  local function at(x, y, z)
    if x >= 6 and x <= 9 and z >= 6 and z <= 9 then
      if y < H then
        -- a bolt's head on the face a rail comes in at
        local face = (z == 9 and (x == 7 or x == 8)) or (x == 9 and (z == 7 or z == 8))
        if face and (y == LOW or y == TOP) then return (x + z) % 2 == 0 and IRON or IRON_HI end
        -- the post's face, foot (row 15, tarred) to collar (row 2, iron)
        return (15 - y) * W + 16 + (x - 6)
      end
      if y == H then return (z - 6) * W + 20 + (x - 6) end                     -- the cap: end grain
      if y == H + 1 and x >= 7 and x <= 8 and z >= 7 and z <= 8 then
        return (z - 6) * W + 20 + (x - 6)
      end
      return nil
    end
    for i = 1, 4 do
      if on[i] then
        local a, d = ARMS[i](x, z)
        if a >= 0 and a <= 5 and d >= 0 and d <= 3 then
          -- along the rail, in the run's own direction, so the grain carries
          -- on from one cell's arm into the next's
          local along = (i == 2 or i == 3) and (10 + a) or (5 - a)
          if d == 1 or d == 2 then
            if y == TOP + 1 then return 0 * W + along end
            if y == TOP then return 1 * W + along end
            if y == LOW + 1 then return 2 * W + along end
            if y == LOW then return 3 * W + along end
          end
          -- the brace, on the rails' south (or east) face: two arms closing
          -- on the middle of the gap as they near the cell's edge
          -- (at forty-five degrees, a voxel a column: each arm is a whole
          -- little X, so a gap between two posts holds two, a lattice)
          if d == 2 then
            -- two voxels thick, so each step shares an edge with the last:
            -- corner to corner, a diagonal reads as loose cubes
            if y == TOP - 1 - a or y == TOP - 2 - a then return 4 * W + along end
            if y == LOW + 2 + a or y == LOW + 3 + a then return 5 * W + along end
          end
        end
      end
    end
    return nil
  end

  return { at = at, W = C, ytop = H + 1, zmin = 0, zmax = C - 1 }
end

return Kit
