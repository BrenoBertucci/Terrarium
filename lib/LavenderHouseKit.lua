-- Three authored exteriors; selected ONLY for Lavender's gabled_cottage.
-- Uses Buildings' shell mesher, AO, camera heights and chimney smoke.
-- Coordinates are world pixels: x east, y up, z south. The original
-- 64x32 plot and the door at x=16..31 stay fixed, including the warp lane.
local Kit = { SHEET = "assets/buildings/lavender_materials.png" }
local floor, abs, min, max = math.floor, math.abs, math.min, math.max

-- Rows of the small authored material swatch sheet (eight shades each).
local STONE, MORTAR, PLASTER, TRIM, SLATE, EDGE, WOOD, GRAIN,
      IRON, GLASS, LIGHT, MOSS, LEAF, FLOWER, CLAY, SHADOW =
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15

local function swatch(row, n) return row * 8 + n % 8 end
local function noise(x, y, z) return (x * 17 + y * 31 + z * 13) % 8 end

function Kit.model(sp, t, tx, ty)
  if sp.W ~= 8 or sp.H ~= 16 or #t.tiles ~= 4 or #t.tiles[1] ~= 8 then
    return nil, "expected 8x16 material sheet and 64x32 cottage plot"
  end
  -- Tile coordinates, not cells. Fuji is the northern home, Cubone the
  -- southwestern home; the eastern southern home is the Name Rater's.
  local fuji, cubone = ty == 16, tx == 4
  local variant = fuji and 1 or (cubone and 2 or 3)
  local wallTop = fuji and 31 or (cubone and 27 or 29)
  local roofRise = fuji and 21 or (cubone and 25 or 23)
  local ridge = wallTop + roofRise
  local chimneyX = cubone and 10 or 49
  local chimneyTop = ridge + (fuji and 8 or 5)

  local function stone(u, y, z)
    local course = floor(y / 4)
    local seam = (u + course % 2 * 5) % 10
    if y % 4 == 0 or seam == 0 then return swatch(MORTAR, 3) end
    if y < 5 and (floor(u / 7) + z + variant) % 7 == 0 then
      return swatch(MOSS, 2)
    end
    return swatch(STONE, noise(floor(u / 10), course, variant))
  end
  local function timber(u, y)
    return swatch((u % 4 == 0) and GRAIN or WOOD, floor(y / 7) % 3 + 2)
  end
  -- Four curved hips replace the extruded rectangular roof entirely.
  -- Fuji's eaves turn up; Cubone's roof has a steeper, off-centre ridge.
  -- The Name Rater has a tall, softer bell-shaped roof and an east dormer.
  local function roofY(x, z)
    local center = cubone and 12 or 15
    local span = z <= center and (center + 1) or (33 - center)
    local rise = max(0, min(1 - abs(z - center) / span,
                           (x + 1) / 15, (64 - x) / 15))
    local curve = cubone and 0.65 or (fuji and 1.25 or 1.5)
    local lip = fuji and rise < 0.2 and 2 or 0
    return wallTop + floor(roofRise * rise ^ curve) + lip
  end
  local function roofPlan(x, z)
    return max(0, 4 - x, x - 59) + max(0, 3 - z, z - 29) <= 5
  end
  local function wallPlan(x, z)
    if x < 2 or x > 61 or z < 2 or z > 29 then return false end
    local dx, dz = max(0, 8 - x, x - 55), max(0, 8 - z, z - 23)
    return dx * dx + dz * dz <= 37
  end
  local function roofTile(x, z)
    local course = floor(abs(z - 14.5) / 3)
    local joint = (x + course % 2 * 3) % 7
    if joint == 0 then return swatch(EDGE, 3) end
    return swatch(SLATE, noise(floor((x + course % 2 * 3) / 7), course, variant))
  end

  -- Recessed casement including projecting stone sill and hinged shutters.
  -- A boolean distinguishes a carved opening from an unhandled voxel.
  local function window(u, y, depth, center, boarded)
    local dx, dy = u - center, y - 17
    if abs(dx) <= 7 and dy >= -8 and dy <= 8 and depth >= -2 and depth <= 3 then
      if dy == -8 and abs(dx) <= 7 and depth >= 0 then
        return true, swatch(TRIM, 4)
      end
      if abs(dx) >= 6 and abs(dx) <= 7 and dy >= -6 and dy <= 7 and depth >= 0 then
        return true, timber(u, y + 3)
      end
      local arch = 7 - floor((abs(dx) / 5) ^ 2 * 4)
      if abs(dx) <= 5 and dy >= -6 and dy <= arch then
        if abs(dx) == 5 or dy == -6 or dy >= arch - 1 then
          return true, swatch(TRIM, 3)
        end
        if depth > 0 then return true, nil end
        if boarded and (dy == floor(dx / 2) or dy == floor(dx / 2) + 1) then
          return true, timber(u, y)
        end
        if depth > -2 then
          if dx == 0 or dy == 0 then return true, swatch(WOOD, 2) end
          return true, nil
        end
        return true, swatch(GLASS, (dx < 0 and dy > 0) and 6 or 2)
      end
    end
    return false
  end

  local function at(x, y, z)
    if x < 0 or x > 63 or z < 0 or z > 33 or y < 0 or y > chimneyTop then return nil end
    -- Chimney: staggered masonry, lead flashing, a corbelled crown and
    -- an open flue. Smoke uses the same metadata as the original houses.
    if x >= chimneyX - 1 and x <= chimneyX + 6 and z >= 7 and z <= 14 then
      if y >= roofY(x, z) - 1 and y <= roofY(x, z) + 1 then return swatch(IRON, 4) end
      if y >= roofY(x, z) and y <= chimneyTop then
        if y >= chimneyTop - 2 then
          if x >= chimneyX + 1 and x <= chimneyX + 4 and z >= 9 and z <= 12 then
            return nil
          end
          return swatch(y == chimneyTop - 2 and TRIM or STONE, 3)
        end
        if x >= chimneyX and x <= chimneyX + 5 and z >= 8 and z <= 13 then
          return stone(x, y, z)
        end
      end
    end

    -- A real gabled dormer over the entrance, with a little louvred attic.
    local dormerX = variant == 3 and 47 or 24
    local dx = abs(x - dormerX)
    local dormerTop = ridge - (cubone and 5 or 1) - floor(dx ^ (cubone and 1.6 or 1.1) * 0.65)
    if dx <= 9 and z >= 20 and z <= 29 and y >= roofY(x, z) - 1 and y <= dormerTop then
      if y >= dormerTop - 1 then return roofTile(x, z) end
      if dx == 9 or y == wallTop + 4 then return timber(x, y) end
      if z >= 28 and dx <= 3 and y >= wallTop + 7 and y <= wallTop + 13 then
        if y % 3 == 0 then return swatch(WOOD, 3) end
        return z == 28 and swatch(SHADOW, 1) or nil
      end
      return swatch(PLASTER, 3)
    end

    -- Solid stepped roof, individual slate courses, ridge caps, deep
    -- fascia and gutters. Its side edges stay inside the adjacent plots.
    if z <= 32 and roofPlan(x, z) then
      local ry = roofY(x, z)
      if y >= ry - 2 and y <= ry then
        if x <= 1 or x >= 62 then return swatch(EDGE, 5) end
        if y >= ridge - 2 then return swatch(EDGE, 6) end
        return roofTile(x, z)
      end
      if (z <= 1 or z >= 31) and y == ry - 3 then return swatch(IRON, 3) end
      if wallPlan(x, z) and y >= wallTop - 1 and y < ry - 2 then
        if y % 6 == 0 or x == 3 or x == 60 then return timber(x, y) end
        return swatch(PLASTER, 2 + floor(x / 16) % 3)
      end
    end

    -- Entrance canopy: timber brackets and a steep little violet roof.
    if x >= 14 and x <= 33 and z >= 28 and z <= 33 then
      local canopyY = 29 - floor((abs(x - 23.5) / 3) ^ 1.5)
      if y == canopyY or y == canopyY - 1 then return roofTile(x, z) end
      if (x == 15 or x == 32) and y >= 22 and y < canopyY - 1 and z <= 31 then
        return timber(x, y)
      end
    end

    -- Wrought iron lantern by each entrance: bracket, cage and amber core.
    if x >= 33 and x <= 36 and z >= 29 and z <= 32 and y >= 15 and y <= 23 then
      if y == 23 or y == 16 or x == 33 or x == 36 then return swatch(IRON, 3) end
      if y >= 17 and y <= 21 then return swatch(LIGHT, 4) end
    end

    -- The Name Rater's hanging carved plaque; Fuji has a diamond memorial
    -- crest, Cubone a quieter bare lintel. All details fit the existing lot.
    if not fuji and not cubone and x >= 39 and x <= 55 and y >= 25 and y <= 28 and z == 31 then
      if y == 25 or y == 28 or x == 39 or x == 55 then return swatch(TRIM, 3) end
      return swatch((x % 4 == 0) and TRIM or WOOD, 3)
    end
    if fuji and z == 30 and abs(x - 24) + abs(y - 30) <= 2 then
      return swatch(TRIM, 5)
    end

    -- Window boxes with stems and muted lavender blooms. Cubone's box is
    -- sparse and weathered; the houses remain inhabited, never ruined.
    if x >= 42 and x <= 54 and z >= 29 and z <= 31 then
      if y >= 5 and y <= 7 then return swatch(y == 7 and STONE or CLAY, 3) end
      if y >= 8 and y <= 10 and x % (cubone and 5 or 3) == 0 then
        return swatch(y == 10 and FLOWER or LEAF, (x + variant) % 8)
      end
    end

    -- Windows face front, rear and both sides, not just a textured facade.
    if z >= 26 then
      local handled, v = window(x, y, z - 28, 48, cubone)
      if handled then return v end
      if fuji then
        handled, v = window(x, y, z - 28, 8, false)
        if handled then return v end
      end
    elseif z <= 5 then
      local handled, v = window(x, y, 3 - z, 43, false)
      if handled then return v end
    end
    if x <= 5 or x >= 58 then
      local handled, v = window(z, y, x <= 5 and 3 - x or x - 60, 15, false)
      if handled then return v end
    end

    -- Door alcove. Nothing projects onto the walkable southern warp cell;
    -- the threshold is level and the door panel sits four voxels back.
    local doorTop = 25 - floor((abs(x - 23.5) / 7.5) ^ 2 * 6)
    if x >= 16 and x <= 31 and y <= doorTop and z >= 25 then
      if y >= doorTop - 1 or x == 16 or x == 31 then return swatch(TRIM, 4) end
      if y == 0 then return swatch(STONE, 4) end
      if z > 25 then return nil end
      if x == 28 and y == 12 then return swatch(IRON, 6) end
      if y == 21 or y == 5 or x == 18 or x == 29 then return swatch(WOOD, 5) end
      return timber(x, y)
    end

    -- Raised corner quoins, downpipes, timber sill plates and weathered
    -- lime plaster over an irregular coursed stone foundation.
    if wallPlan(x, z) and y <= wallTop then
      if y <= 7 then return stone((z <= 3 or z >= 28) and x or z, y, variant) end
      if (x <= 8 or x >= 55) and (z <= 8 or z >= 23) then
        return swatch(y % 5 == 0 and MORTAR or TRIM, 3)
      end
      if y == 8 or y == wallTop - 2 or x == 6 or x == 57 then return timber(x, y) end
      local patch = (floor(x / 9) + floor(y / 6) * 3 + floor(z / 7) + variant) % 8
      return swatch(PLASTER, patch)
    end
    if (x == 3 or x == 60) and z == 30 and y >= 1 and y <= wallTop - 2 then
      return swatch(IRON, y % 9 == 0 and 5 or 2)
    end
    return nil
  end

  return { at = at, W = 64, xmin = 0, xmax = 63, zmin = 0, zmax = 33,
           ytop = chimneyTop, tex = Kit.SHEET,
           chimney = { x = chimneyX + 3, y = chimneyTop + 1, z = 11 },
           tint = function(y) return 0.88 + min(y / 32, 1) * 0.12 end }
end

return Kit
