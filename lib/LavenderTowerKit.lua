-- Voxel world mode: the Pokemon Tower, OUTSIDE, in the town's own stone.
--
-- lib/TowerKit.lua already stood the tower by hand instead of folding it
-- out of the drawing, and it is still here: it is the fallback, and the
-- TOWER row's CLASSIC. But it was built inside the rule of its day -- the
-- tileset's own texels, held down to grey by a tint -- so it is four flat
-- boxes under a purple lid, and since the cottages, the Centre and the Mart
-- went up in authored colour it has been the plainest thing in Lavender,
-- which is backwards: it is the reason the town exists.
--
-- So this is the tower as a building, in the same limestone and violet slate
-- as the rest (the sheet is the Centre's, lib/LavenderCivicKit.lua):
--
--   a battered plinth and a flight of steps up to a deep pointed portal, its
--     doors standing a hand ajar on a cold light
--   a blind lower body tied by clasping buttresses that step back and end in
--     pinnacles, a rose window over the door, slit lights, damp down the
--     stone under every cornice, ivy up the south-west corner
--   three storeys of paired lancets, a few of them lit by nothing living
--   an OPEN belfry -- the bronze bell hangs where it can be seen -- under a
--     battlemented parapet
--   an eight-sided slate spire with lucarnes, an iron rod and a gilt ball
--
-- Same plot (96 x 64), same precinct round it (TowerKit.precinct stands the
-- terrace wall; nothing of that moves), same `haunt` handed to the scene so
-- the wisps still rise from the belfry, the portal and the spire. Nobody
-- walks into this model: the way in is the gate in the terrace wall.
--
-- Coordinates are the plot's: x east 0..95, z south 0..63, y up. A person
-- is sixteen voxels. Nothing here is extracted from the ROM.
local Kit = { SHEET = "assets/buildings/lavender_civic.png",
              SHEET_W = 8, SHEET_H = 32, W = 96, D = 64 }

local floor, abs, min, max = math.floor, math.abs, math.min, math.max

-- rows of the Centre's sheet that the tower wears (tools/lavender_civic.py)
local STONE, MORTAR, TRIM, SLATE, EDGE, WOOD, GRAIN, IRON, GLASS, MOSS, LEAF,
      SHADOW, GOLD, GHOST, DAMP = 0, 1, 3, 4, 5, 6, 7, 8, 9, 11, 12, 15, 22, 30, 31

local function sw(row, n) return row * 8 + n % 8 end
local function hash(a, b, c) return (a * 127 + b * 311 + c * 571 + a * b * 7) % 97 end

local CX, CZ = 47.5, 31.5
-- the stages, bottom to top: y0, y1, half-extents
local PLINTH, BODY, CORN1 = 9, 81, 86
local UPPER, CORN2 = 145, 149
local B0 = CORN2 + 1                     -- the belfry's floor
local BELFRY, PARAPET = 178, 183
local SPIRE0, SPIRE1, YTOP = 181, 228, 236   -- ShadowMap.HEIGHT is 240

-- ashlar: courses six high, blocks twelve long and staggered; `wet` is how
-- far under a cornice this voxel hangs (damp runs down from every ledge)
local function stone(u, y, wet)
  local course = floor(y / 6)
  local v = u + course % 2 * 6
  if y % 6 == 0 or v % 12 == 0 then return sw(MORTAR, 3) end
  local block = floor(v / 12)
  if y < 7 and hash(block, course, 1) % 4 == 0 then return sw(MOSS, 1 + block % 3) end
  if wet and wet < 14 and hash(u, 0, 3) % 7 == 0 and wet < 5 + hash(u, 1, 3) % 9 then
    return sw(DAMP, 2)
  end
  if hash(block, course, 2) % 9 == 0 then return sw(DAMP, 4) end
  return sw(STONE, hash(block, course, 5) % 8)
end

-- a pointed opening: `du` off its axis, `h` up from its sill; w2 half-width,
-- `spring` where the arch leaves the jamb, apex where two arcs of radius
-- 2*w2 cross
local function pointed(du, h, w2, spring, top)
  if h < 0 or h > top or abs(du) > w2 then return false end
  if h <= spring then return true end
  local a = abs(du) + w2
  return a * a + (h - spring) * (h - spring) <= 4 * w2 * w2
end

function Kit.model(sp, t)
  if not sp or sp.W ~= Kit.SHEET_W or sp.H ~= Kit.SHEET_H then
    return nil, "sheet is not " .. Kit.SHEET_W .. "x" .. Kit.SHEET_H
  end
  if #t.tiles ~= 8 or #t.tiles[1] ~= 12 then return nil, "expected a 96x64 plot" end

  -- a stage's half-extents at height y, or nil above the masonry
  local function stage(y)
    if y <= PLINTH then return 46 - floor(y / 4), 30 - floor(y / 4) end
    if y <= BODY then return 42, 26 end
    if y <= CORN1 then return 44, 28 end
    if y <= UPPER then return 35, 21 end
    if y <= CORN2 then return 37, 23 end
    if y <= BELFRY then return 26, 16 end
    if y <= PARAPET then return 28, 18 end
    return nil
  end

  local function at(x, y, z)
    if y < 0 or y > YTOP then return nil end
    local dx, dz = x - CX, z - CZ
    local ax, az = abs(dx), abs(dz)

    -- ---- the finial, the spire and its lucarnes
    if y > SPIRE1 then
      if ax < 1 and az < 1 then return sw(IRON, 3) end
      if y >= 231 and y <= 233 and ax < 2 and az < 2 then return sw(GOLD, 3 + y % 2) end
      return nil
    end
    if y >= SPIRE0 then
      local f = 1 - (y - SPIRE0) / (SPIRE1 - SPIRE0 + 1)
      local hx, hz = 24 * f + 1, 15 * f + 1
      local a, b = ax / hx, az / hz
      if max(a, b, (a + b) * 0.72) <= 1 then
        local d = y - SPIRE0
        if max(a, b, (a + b) * 0.72) > 0.86 and (a > 0.98 * b and b > 0.98 * a
           or abs((a + b) * 0.72 - max(a, b)) < 0.04) then
          return sw(EDGE, 6)                                 -- the arrises
        end
        if d % 4 == 0 then return sw(EDGE, 4) end
        local u = x + z
        if (u + floor(d / 4) % 2 * 3) % 7 == 0 then return sw(EDGE, 3) end
        return sw(SLATE, hash(floor(u / 7), floor(d / 4), 9) % 8)
      end
      -- lucarnes: a little gabled light low on each face
      if y >= SPIRE0 + 6 and y <= SPIRE0 + 17 then
        local face = (az * 24 > ax * 15) and "z" or "x"
        local du = face == "z" and ax or az
        local out = face == "z" and (az - hz) or (ax - hx)
        local peak = SPIRE0 + 17 - floor(du * 1.4)
        if du <= 4 and out > 0 and out <= 4 and y <= peak then
          if y >= peak - 1 then return sw(EDGE, 5) end
          if du <= 1 and y >= SPIRE0 + 8 and y <= SPIRE0 + 13 and out >= 3 then return sw(SHADOW, 1) end
          return sw(TRIM, 3)
        end
      end
      if y > PARAPET then return nil end
    end

    local hx, hz = stage(y)
    if not hx then return nil end
    local u = (ax * hz > az * hx) and z or x                 -- along the nearer face
    local inBox = ax <= hx and az <= hz

    -- ---- the parapet: a walk round the spire's foot, merlons on it
    if y > BELFRY then
      if not inBox or (ax <= hx - 3 and az <= hz - 3 and y > BELFRY + 1) then return nil end
      if y >= PARAPET - 1 and (u % 6) >= 3 then return nil end
      return (y == BELFRY + 1) and sw(TRIM, 4) or stone(u, y)
    end

    -- ---- the belfry: open arches, the bell hung where it can be seen
    if y > CORN2 then
      if ax <= hx - 4 and az <= hz - 4 then                  -- the chamber
        if y <= CORN2 + 2 or y >= BELFRY - 1 then return stone(u, y) end
        local r2 = dx * dx + dz * dz
        if y >= B0 + 19 and y <= B0 + 21 and az <= 1.5 then return sw(GRAIN, 3) end   -- the headstock
        if y >= B0 + 7 and y <= B0 + 18 then
          local r = 3 + (B0 + 18 - y) * 0.45
          if r2 <= r * r and (y >= B0 + 17 or r2 >= (r - 1.6) * (r - 1.6)) then
            return sw(GOLD, (y % 3 == 0) and 1 or 4)
          end
        end
        if y >= B0 + 4 and y <= B0 + 12 and r2 < 1.2 then return sw(IRON, 4) end      -- the clapper
        return nil
      end
      if not inBox then return nil end
      local face = (ax * hz > az * hx) and "x" or "z"
      local across = face == "z" and ax or az
      local axis = face == "z" and 12 or 0
      if pointed(across - axis, y - (B0 + 4), 5, 11, 20) then return nil end
      if pointed(across - axis, y - (B0 + 3), 6, 11, 22) then return sw(TRIM, 3) end   -- the hood
      if y == CORN2 + 1 then return sw(TRIM, 4) end
      return stone(u, y, BELFRY - y)
    end

    -- ---- cornices: a corbel table under each, gargoyles at the first
    if y > UPPER or (y > BODY and y <= CORN1) then
      if inBox then
        local base = (y > UPPER) and UPPER or BODY
        if y == base + 1 and u % 4 >= 2 and (ax > hx - 2 or az > hz - 2) then return nil end
        return sw(TRIM, y == base + 1 and 2 or 4)
      end
      if y == 84 or y == 85 then                             -- the spouts
        local gx = (abs(ax - 30) <= 1 or ax <= 1) and az > hz and az <= hz + 4
        local gz = az <= 1 and ax > hx and ax <= hx + 4
        if gx or gz then return sw(DAMP, 2) end
      end
      return nil
    end

    -- ---- three storeys of paired lancets
    if y > CORN1 then
      if not inBox then return nil end
      local depth = min(hx - ax, hz - az)
      if depth <= 3 then
        local face = (hx - ax < hz - az) and "x" or "z"
        local across = face == "z" and ax or az
        for storey = 0, 2 do
          local sill = 91 + storey * 18
          for k, c in ipairs(face == "z" and { 9, 25 } or { 9 }) do
            if pointed(across - c, y - sill, 3, 7, 13) then
              if depth < 3 then
                if depth == 1 and abs(across - c) < 0.6 then return sw(TRIM, 2) end  -- the mullion
                return nil
              end
              local side = ((face == "z" and dz or dx) > 0 and 1 or 0)
                           + ((face == "z" and dx or dz) > 0 and 2 or 0)
              if hash(storey * 5 + k, side, face == "z" and 1 or 2) % 6 == 0 then
                return sw(GHOST, 2 + y % 3)
              end
              return sw(GLASS, 0)
            end
            if depth == 0 and pointed(across - c, y - sill + 1, 4, 7, 15) then
              return sw(TRIM, 3)
            end
          end
        end
      end
      if y == 107 or y == 125 then return sw(TRIM, 4) end
      if ax > hx - 4 and az > hz - 4 then return sw(y % 6 < 3 and TRIM or MORTAR, 3) end
      return stone(u, y, UPPER - y)
    end

    -- ---- the lower body and the plinth
    -- clasping buttresses at the four corners, stepping back, then pinnacles
    local kx, kz = ax - 41, az - 25
    local half = (y <= 40) and 6 or ((y <= 64) and 5 or 4)
    local buttress = abs(kx) <= half and abs(kz) <= half
    -- and one on each long face either side of the door, one on each flank
    if not buttress and y <= 76 then
      local jut = (y <= 52) and 3 or 2
      if (abs(ax - 22) <= 2 and az > hz and az <= hz + jut)
         or (az <= 2 and ax > hx and ax <= hx + jut) then
        return (y == 76 or y == 52) and sw(TRIM, 4) or stone(y, u + 3)
      end
    end
    if buttress and not inBox then
      if y == 40 or y == 64 then return sw(TRIM, 4) end
      return stone(x + z, y)
    end

    -- the steps up to the door
    if z >= 56 and ax <= 15 and y < min(4, floor((64 - z) / 2) + 0) then
      return sw(TRIM, 2 + (z % 2))
    end
    -- the portal: eight deep, doors a hand ajar on a cold light
    if z >= 49 and pointed(dx, y - 4, 11, 18, 37) then
      if z >= 50 then return nil end
      if z == 49 then
        if ax < 1 then return sw(GHOST, 5) end
        if y == 12 or y == 24 or y == 33 then return sw(IRON, 3) end
        if ax > 9.5 or ax < 2 then return sw(GRAIN, 3) end
        return sw(WOOD, 2 + floor(ax / 2) % 3)
      end
    end
    if not inBox then
      -- the archivolt stands a voxel proud of the wall, and ivy climbs the
      -- south-west corner
      if dz > 0 and az <= hz + 1 and y > PLINTH and pointed(dx, y - 3, 13, 18, 41)
         and not pointed(dx, y - 4, 11, 18, 37) then
        return sw(TRIM, 3 + y % 2)
      end
      -- (each clause names its OWN face: the west one used to be true for
      -- every voxel south of the wall, and hung a green tarp over the door)
      local south = dz > 0 and az > hz and az <= hz + 1 and ax <= hx and dx < -18
      local west = dx < 0 and ax > hx and ax <= hx + 1 and az <= hz and dz > 6
      if y > 6 and y < 58 and (south or west) then
        local reach = 50 - (south and (dx + 42) or (26 - dz)) * 1.6
        -- one mass with a ragged crown and a few holes: scattered leaves
        -- read as slabs hung off the wall
        if y < reach + hash(floor(u / 3), 0, 8) % 9 - 4 and hash(u, y, 8) % 11 ~= 0 then
          return sw(LEAF, hash(u, y, 4))
        end
      end
      return nil
    end
    if y <= PLINTH then return stone(u, y) end

    local depth = min(hx - ax, hz - az)
    if depth <= 2 and dz > 0 and az >= hz - 2 then
      -- the rose over the door
      local rx, ry = dx, y - 60
      local r2 = rx * rx + ry * ry
      if r2 <= 100 then
        if r2 > 72 or r2 <= 5 then return sw(TRIM, 3) end
        local spoke = abs(rx) < 0.8 or abs(ry) < 0.8 or abs(abs(rx) - abs(ry)) < 0.9
        if depth == 0 then return spoke and sw(TRIM, 4) or nil end
        if depth == 1 then return nil end
        local petal = (rx > 0 and 1 or 0) + (ry > 0 and 2 or 0) + (abs(rx) > abs(ry) and 4 or 0)
        return (petal % 3 == 0) and sw(GHOST, 1 + petal % 3) or sw(GLASS, 0)
      end
    end
    if depth <= 2 then
      -- slit lights, two a face
      local face = (hx - ax < hz - az) and "x" or "z"
      local across = face == "z" and ax or az
      local c = face == "z" and 30 or 12
      if abs(across - c) <= 1 and y >= 30 and y <= 46 then
        if depth < 2 then return nil end
        return sw(SHADOW, 1)
      end
    end
    if y == 28 or y == 46 then return sw(TRIM, 4) end
    return stone(u, y, BODY - y)
  end

  -- pinnacles over the corner buttresses, outside the stage boxes
  local body = at
  at = function(x, y, z)
    if y > CORN1 and y <= 102 then
      local kx, kz = abs(abs(x - CX) - 41), abs(abs(z - CZ) - 25)
      local half = 3 - floor((y - 87) / 5)
      if half >= 0 and kx <= half and kz <= half then
        return sw(TRIM, (y - 87) % 5 == 0 and 2 or 4)
      end
    end
    return body(x, y, z)
  end

  local wisps = { { CX, 10, Kit.D + 0.5, "portal" }, { CX, YTOP + 1, CZ, "spire" } }
  for _, s in ipairs({ -1, 1 }) do
    for _, c in ipairs({ -12, 12 }) do
      wisps[#wisps + 1] = { CX + c, B0 + 14, CZ + s * 17.5, "lantern" }
    end
    wisps[#wisps + 1] = { CX + s * 27.5, B0 + 14, CZ, "lantern" }
  end
  return { at = at, W = Kit.W, xmin = -4, xmax = Kit.W + 3, zmin = -4, zmax = Kit.D + 3,
           ytop = YTOP,
           haunt = { color = { 0.62, 0.80, 1.0 }, box = { -4, -4, Kit.W + 3, Kit.D + 3 },
                     top = YTOP, wisps = wisps },
           tint = function(y) return 0.80 + min(y / 120, 1) * 0.20 end }
end

return Kit
