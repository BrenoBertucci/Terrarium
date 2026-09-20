-- Voxel world mode: the three Lavender homes INSIDE.
--
-- Mr. Fuji's house, the Cubone house and the Name Rater's house are the
-- SAME 16x16 tile plan (tools/interior_plan.py: they hash identically), and
-- the plan is also the collision, so the furniture cannot move. What can
-- change is everything standing on those cells. The room is one function of
-- position, `room(v)(x, y, z)`, and `v` -- picked by MAP ID, nothing else --
-- decides who lives there:
--
--   1  Mr. Fuji      a warm shelter: lilac wainscot, tea for four, toys and
--                    blankets on the shelves, lavender in clay pots
--   2  Cubone house  mourning: cold plaster, drawn curtains, a half-empty
--                    bookcase, a memorial altar with two candles and a bone
--   3  Name Rater    a study: walnut panelling, ledgers to the cornice, a
--                    felt-topped desk with lamp and globe, a card catalogue
--
-- Same pipeline as lib/ShopKit.lua: an AUTHORED SHEET (one texel per voxel,
-- tools/lavender_home.py) through the spriteQuads path, a person is sixteen
-- voxels, and the camera is the Mart's fixed shot (data/camera_shots.lua),
-- so the side walls are cut dollhouse-style and nothing tall stands south.
--
-- Three templates (data/voxel_heights.lua, buildings.HOUSE): `room` is the
-- whole plan, `stoolsW`/`stoolsE` are only the seats -- their cells are
-- WALKABLE, so they carry a standH and the rest of the room must not. Two
-- seat templates, not one: a placement is refused if ANY cell of its grid is
-- already claimed, and one grid over all four seats spans the table.
--
-- Coordinates: x east 0..127, z south 0..127, y up. Side walls stand
-- outside the box. Nothing here is extracted from the ROM.
local Kit = { SHEET = "assets/buildings/lavender_home.png",
              SHEET_W = 8, SHEET_H = 32, SEAT_H = 6 }

Kit.MAPS = { MR_FUJIS_HOUSE = 1, LAVENDER_CUBONE_HOUSE = 2,
             NAME_RATERS_HOUSE = 3 }

local floor, abs, max, min = math.floor, math.abs, math.max, math.min

-- rows of the sheet; tools/lavender_home.py is the mirror of this list
local PLASTER_W, PLASTER_C, PARCH, WAINS, OAK, WALNUT, DARK, TRIM,
      SKY, CURT_L, CURT_D, BOOK_R, BOOK_G, BOOK_B, BOOK_O, PAPER,
      CLAY, LEAF, DRY, FLOWER, WHITE, LIGHT, BONE, FELT,
      BRASS, IRON, RUG_V, RUG_C, RUG_CREAM, PINK, TEAL, YELLOW =
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
      16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31

local function sw(row, n) return row * 8 + n % 8 end
local function hash(x, y, z)
  return (x * 127 + y * 311 + z * 571 + x * y * 7 + y * z * 3) % 97
end

local WALL_H, WALL_D = 28, 5
-- the dollhouse cut: the side walls step down toward the camera
local function sideH(z) return max(6, WALL_H - floor(max(0, z - 12) * 0.2)) end

-- `u` runs ALONG a wall, whichever wall it is
local function wallSkin(u, y, v)
  if v == 1 then
    if y <= 2 then return sw(WALNUT, 3) end
    if y <= 11 then return sw(WAINS, u % 10 == 0 and 1 or 5) end
    if y == 12 then return sw(TRIM, 5) end
    if y >= 26 then return sw(TRIM, 3) end
    return sw(PLASTER_W, u % 6 < 3 and 5 or 4)
  elseif v == 2 then
    if y <= 2 then return sw(DARK, 3) end
    if y >= 26 then return sw(PLASTER_C, 0) end
    if y >= 15 and y <= 22 and (u + y * 2) % 83 == 0 then return sw(DARK, 5) end
    if y <= 6 and hash(u, y, 0) % 5 == 0 then return sw(PLASTER_C, 0) end
    return sw(PLASTER_C, 3 + hash(floor(u / 5), floor(y / 4), 1) % 3)
  end
  if y <= 2 then return sw(DARK, 3) end
  if y <= 14 then
    if u % 12 == 0 or y == 14 or y == 3 then return sw(DARK, 5) end
    return sw(WALNUT, u % 12 < 2 and 3 or 5)
  end
  if y == 15 or y >= 26 then return sw(OAK, 3) end
  if u % 8 == 4 and y % 6 == 2 then return sw(PARCH, 0) end
  return sw(PARCH, 4)
end

-- ------------------------------------------------------- the north wall --

local function picture(x, y, v)
  if v == 1 then            -- the Tower over a lavender field
    if x == 80 or x == 95 or y == 12 or y == 23 then return sw(OAK, 2) end
    if abs(x - 88) <= 1 and y >= 15 and y <= 21 then return sw(CURT_D, 4) end
    if abs(x - 88) <= 2 and y >= 15 and y <= 16 then return sw(CURT_D, 2) end
    if y <= 14 then return sw(LEAF, 4) end
    if y <= 16 then return sw(FLOWER, x) end
    return sw(SKY, 5)
  elseif v == 2 then        -- a portrait under a black ribbon
    if x == 80 or x == 95 or y == 12 or y == 23 then return sw(IRON, 3) end
    if (95 - x) + (23 - y) <= 5 then return sw(IRON, 1) end
    local d = (x - 87.5) * (x - 87.5) + (y - 18) * (y - 18)
    if d <= 3 then return sw(BONE, 5) end
    if d <= 10 then return sw(DRY, 2) end
    return sw(BONE, 1)
  end
  local lx = (x - 79) % 6   -- three framed certificates
  if lx == 5 or y < 13 or y > 22 then return nil end
  if lx == 0 or lx == 4 or y == 13 or y == 22 then return sw(BRASS, 4) end
  if lx == 3 and y == 15 then return sw(BOOK_R, 4) end
  return sw(PAPER, y % 2 == 0 and 1 or 6)
end

local function northWall(x, y, z, v)
  -- the window: a real recess, glass three voxels back, sill and frame
  if x >= 49 and x <= 62 and y >= 9 and y <= 24 then
    local ring = x == 49 or x == 62 or y == 9 or y == 24
    if ring then
      if z <= 10 then return sw(v == 1 and TRIM or (v == 2 and DARK or OAK), 4) end
    elseif z >= 7 then
      if z <= 10 then return nil end
    elseif z == 6 then
      if x == 55 or x == 56 or y == 16 or y == 17 then
        return sw(v == 1 and TRIM or DARK, 4)
      end
      return sw(SKY, v == 2 and 0 or 6 - floor((24 - y) / 4))
    end
  end
  if y == 8 and x >= 48 and x <= 63 and z >= 10 and z <= 12 then
    return sw(v == 3 and OAK or TRIM, 5)
  end
  if z == 10 or z == 11 then
    if v == 1 then          -- lilac curtains, tied open on a brass rod
      if y == 25 and z == 11 and x >= 44 and x <= 67 then return sw(BRASS, 4) end
      if y >= 7 and y <= 24 and ((x >= 44 and x <= 48) or (x >= 63 and x <= 67)) then
        if y == 14 then return sw(TRIM, 4) end
        if y < 14 and (x == 44 or x == 67) then return nil end
        return sw(CURT_L, 3 + x % 2 * 3)
      end
    elseif v == 2 then      -- drawn almost shut
      if y == 25 and z == 11 and x >= 45 and x <= 66 then return sw(IRON, 3) end
      if y >= 6 and y <= 24 and x >= 46 and x <= 65 and not (x == 55 or x == 56) then
        return sw(CURT_D, 2 + x % 3 * 2)
      end
    elseif z == 10 then     -- folded shutters
      if y >= 9 and y <= 24 and ((x >= 44 and x <= 48) or (x >= 63 and x <= 67)) then
        return sw(y % 3 == 0 and DARK or WALNUT, 4)
      end
    end
    -- sconces either side of the table's axis; the mourning house's is out
    if (x == 38 or x == 39 or x == 104 or x == 105) and y >= 16 and y <= 21 then
      if y == 16 then return sw(IRON, 3) end
      if y == 21 then return sw(BRASS, 3) end
      return v == 2 and sw(IRON, 5) or sw(LIGHT, 5)
    end
    if z == 10 and x >= 79 and x <= 95 and y >= 12 and y <= 23 then
      local p = picture(x, y, v)
      if p then return p end
    end
    -- cornice and skirting stand one voxel proud of the face
    if z == 10 and (y >= 26 or y <= 2) then return wallSkin(x + 5, y, v) end
    return nil
  end
  if z <= 9 then return wallSkin(x + 5, y, v) end
  return nil
end

-- ------------------------------------------------------------ the cases --
-- An open case sixteen wide: ux 0..15 across, dz 0..20 deep (dz 20 is the
-- front). Shelves every six; `fill(ux, s, hy, dz)` stocks shelf `s`.
local function case(ux, y, dz, H, wood, fill)
  if y > H then return nil end
  if ux == 0 or ux == 15 or y == H or dz <= 1 then return sw(wood, 3) end
  if y <= 1 then return dz <= 18 and sw(DARK, 2) or nil end
  if (y - 2) % 6 == 0 then return sw(wood, 5) end
  if dz >= 18 then return nil end
  return fill(ux, floor((y - 3) / 6), (y - 3) % 6, dz)
end

local function books(v, unit, gapMod)
  return function(ux, s, hy, dz)
    if dz < 4 or dz > 16 then return nil end
    local bid = floor((ux - 1) / 2) + s * 7 + unit * 31
    local h = hash(bid, s, v)
    if gapMod and h % gapMod == 0 then return nil end
    if hy >= 3 + h % 3 then return nil end
    return sw(BOOK_R + h % 4, h)
  end
end

local function ledgers(unit)
  return function(ux, s, hy, dz)
    if dz < 4 or dz > 16 then return nil end
    if unit == 1 and s == 1 and ux <= 7 then        -- a stack of scrolls
      return hy <= 2 and sw(PAPER, ux % 2 * 4 + hy) or nil
    end
    local bid = floor((ux - 1) / 2)
    if hy == 4 and hash(bid, s, unit) % 3 == 0 then return nil end
    if hy == 3 and bid % 2 == 0 and dz == 16 then return sw(BRASS, 4) end
    return sw(BOOK_R + s % 4, 2 + hash(bid, s, 9) % 4)
  end
end

local DOLL = { PINK, YELLOW, TEAL }
local function toys(ux, s, hy, dz)
  if s == 0 then                                     -- folded blankets
    if dz < 3 or dz > 16 or hy >= 4 then return nil end
    return sw(floor((ux - 1) / 5) % 2 == 0 and PINK or TEAL, hy == 1 and 1 or 5)
  elseif s == 1 then                                 -- three dolls
    for i = 1, 3 do
      local dx, dd = abs(ux - i * 4), abs(dz - 10)
      if dx <= 1 and dd <= 1 and hy <= 3 and not (hy == 3 and dx + dd > 0) then
        return sw(DOLL[i], hy == 2 and 7 or 4)
      end
    end
    return nil
  end
  if ux >= 11 and ux <= 13 and dz >= 8 and dz <= 11 then
    return hy == 0 and sw(CLAY, 4) or (hy < 4 and sw(LEAF, hash(ux, hy, dz)) or nil)
  end
  return books(1, 1, 3)(ux, s, hy, dz)
end

-- The memorial: closed doors below, one tall niche above, no shelf in it.
local function altar(ux, y, dz)
  if y > 20 then return nil end
  if ux == 0 or ux == 15 or y == 20 or dz <= 1 then return sw(WALNUT, 3) end
  if y <= 8 then
    if dz < 18 then return sw(WALNUT, 2) end
    if dz == 19 then
      return ((ux == 6 or ux == 9) and y == 5) and sw(BRASS, 4) or nil
    end
    if dz == 20 then return nil end
    return sw((ux == 7 or ux == 8 or y <= 1) and DARK or WALNUT, 4)
  end
  if dz == 2 then return sw(CURT_D, 2 + ux % 2 * 2) end
  if dz == 4 and ux >= 6 and ux <= 9 and y >= 9 and y <= 15 then
    if ux == 6 or ux == 9 or y == 9 or y == 15 then return sw(BRASS, 4) end
    return sw(y <= 12 and DRY or BONE, 4)
  end
  if (ux == 3 or ux == 12) and dz == 8 then
    if y <= 12 then return sw(BONE, 6) end
    if y == 13 then return sw(LIGHT, 7) end
  end
  if y == 9 then
    if dz == 12 and ux >= 5 and ux <= 10 then return sw(BONE, 4) end
    if (ux == 5 or ux == 10) and (dz == 11 or dz == 13) then return sw(BONE, 5) end
    if (ux == 7 or ux == 8) and (dz == 15 or dz == 16) then return sw(TEAL, 2) end
  end
  if y == 10 and (ux == 7 or ux == 8) and (dz == 15 or dz == 16) then
    return sw(WHITE, ux + dz)
  end
  return nil
end

local function westCases(x, y, z, v)
  local unit, ux, dz = floor(x / 16), x % 16, z - 10
  if v == 1 then
    return case(ux, y, dz, 20, OAK, unit == 0 and books(1, 0, 9) or toys)
  elseif v == 2 then
    if unit == 1 then return altar(ux, y, dz) end
    return case(ux, y, dz, 20, WALNUT, function(bx, s, hy, bz)
      if s == 1 then   -- one book left lying
        return (hy == 0 and bx >= 3 and bx <= 9 and bz >= 6 and bz <= 12)
               and sw(BOOK_B, 2) or nil
      end
      return books(2, 0, 2)(bx, s, hy, bz)
    end)
  end
  return case(ux, y, dz, 26, WALNUT, ledgers(unit))
end

local function eastCase(x, y, z, v)
  local ux, dz = x - 112, z - 10
  if v == 1 then            -- a dresser, a vase of lavender, a photograph
    if y <= 12 then
      if dz == 20 then
        if (ux == 4 or ux == 11) and (y == 2 or y == 6 or y == 10) then return sw(BRASS, 4) end
        if y == 4 or y == 8 or y == 0 then return sw(DARK, 4) end
      end
      return sw(OAK, y == 12 and 6 or 3)
    end
    local dx, dd = abs(ux - 4), abs(dz - 9)
    if y <= 16 then
      if dx <= 1 and dd <= 1 then return sw(TEAL, y) end
    elseif y <= 18 then
      if dx == 0 and dd == 0 then return sw(LEAF, 3) end
    elseif y <= 21 and dx <= 2 and dd <= 2 and hash(ux, y, dz) % 2 == 0 then
      return sw(FLOWER, ux + y)
    end
    if dz == 6 and ux >= 9 and ux <= 13 and y <= 18 then
      if ux == 9 or ux == 13 or y == 13 or y == 18 then return sw(OAK, 1) end
      return sw(y <= 15 and PINK or PAPER, 4)
    end
    return nil
  elseif v == 2 then        -- a shut wardrobe under a mourning cloth
    if y <= 24 then
      if dz == 20 then
        if (ux == 6 or ux == 9) and y == 12 then return sw(BRASS, 3) end
        if ux == 7 or ux == 8 or y <= 1 or y == 4 or y == 20
           or ux == 2 or ux == 5 or ux == 10 or ux == 13 then
          return sw(DARK, 4)
        end
      end
      return sw(WALNUT, 3)
    end
    if y == 25 and ux >= 7 then return sw(CURT_D, 3 + (ux + dz) % 2 * 2) end
    return nil
  end
  if y <= 18 then           -- a card catalogue, brass pulls, paper labels
    if dz == 20 and y < 18 then
      if y <= 1 then return sw(DARK, 3) end
      local lx, ly = ux % 4, (y - 2) % 4
      if lx == 0 or ly == 0 then return sw(DARK, 5) end
      if lx == 2 and ly == 2 then return sw(BRASS, 5) end
      if ly == 3 then return sw(PAPER, 4) end
    end
    return sw(y == 18 and WALNUT or OAK, 4)
  end
  if ux >= 2 and ux <= 6 and dz >= 6 and dz <= 11 and y <= 21 then return sw(PAPER, y * 3) end
  if ux >= 10 and ux <= 11 and dz >= 8 and dz <= 9 then
    if y <= 21 then return sw(IRON, 4) end
    if y == 22 then return sw(BRASS, 4) end
  end
  if ux >= 9 and ux <= 13 and dz >= 13 and dz <= 17 and y <= 20 then return sw(BOOK_G, y) end
  return nil
end

-- mourning cloth hanging off the wardrobe's front, one voxel proud
local function wardrobeDrape(x, y, z)
  local ux = x - 112
  if z == 31 and ux >= 8 and y <= 25 and y >= 15 + ux % 3 * 2 then
    return sw(CURT_D, 3 + ux % 2 * 2)
  end
  return nil
end

-- ------------------------------------------------------------ the table --

local function cornerCut(tx, tz, r)
  local dx, dz = max(0, r - tx, tx - (31 - r)), max(0, r - tz, tz - (31 - r))
  return dx * dx + dz * dz > r * r
end

local function teaTable(tx, y, tz)
  if y <= 5 then
    local lx = (tx >= 3 and tx <= 5) or (tx >= 26 and tx <= 28)
    local lz = (tz >= 3 and tz <= 5) or (tz >= 26 and tz <= 28)
    return (lx and lz) and sw(OAK, 2) or nil
  end
  local runner = tz >= 13 and tz <= 18
  if y <= 7 then
    if runner and (tx == 0 or tx == 31) then return sw(CURT_L, 4) end
    if tx >= 2 and tx <= 29 and tz >= 2 and tz <= 29
       and (tx == 2 or tx == 29 or tz == 2 or tz == 29) then return sw(OAK, 1) end
    return nil
  end
  if y <= 9 then
    if cornerCut(tx, tz, 4) then return nil end
    if runner and (tx == 0 or tx == 31) then return sw(CURT_L, 4) end
    return sw(OAK, tz % 4 == 0 and 2 or 5)
  end
  local cx, cz = tx - 15.5, tz - 15.5
  local d = cx * cx + cz * cz
  if y == 10 then
    if runner then return sw((tz == 13 or tz == 18) and TRIM or CURT_L, 5) end
    for _, c in ipairs({ { 7, 7 }, { 24, 7 }, { 7, 24 }, { 24, 24 } }) do
      if abs(tx - c[1] - 0.5) <= 1.5 and abs(tz - c[2] - 0.5) <= 1.5 then return sw(PAPER, 5) end
    end
    if cx * cx + (tz - 6.5) * (tz - 6.5) <= 6 then return sw(PAPER, 6) end
    return nil
  end
  if y <= 12 then
    for _, c in ipairs({ { 7, 7 }, { 24, 7 }, { 7, 24 }, { 24, 24 } }) do
      if (tx == c[1] or tx == c[1] + 1) and (tz == c[2] or tz == c[2] + 1) then
        return sw(TRIM, 6)
      end
    end
  end
  if y == 11 and cx * cx + (tz - 6.5) * (tz - 6.5) <= 3 and hash(tx, 1, tz) % 2 == 0 then
    return sw(hash(tx, 2, tz) % 3 == 0 and DRY or YELLOW, 3)
  end
  if y >= 11 and y <= 14 then                        -- the teapot
    if d <= 6.5 then return sw(TEAL, y) end
    if (tz == 15 or tz == 16) and (tx == 18 or tx == 19) and y >= 12 and y <= 13 then return sw(TEAL, 6) end
    if tz == 15 and (tx == 11 or tx == 12) and y >= 12 then return sw(TEAL, 2) end
  elseif y == 15 then
    if d <= 2.6 then return sw(TEAL, 7) end
  elseif y == 16 and d <= 0.6 then
    return sw(BRASS, 5)
  end
  return nil
end

local function bareTable(tx, y, tz)
  if y <= 5 then
    local lx, lz = tx <= 2 or tx >= 29, tz <= 2 or tz >= 29
    return (lx and lz) and sw(DARK, 3) or nil
  end
  if y <= 7 then
    return (tx == 1 or tx == 30 or tz == 1 or tz == 30) and sw(DARK, 4) or nil
  end
  if y <= 9 then
    if cornerCut(tx, tz, 1) then return nil end
    return sw(tx % 5 == 0 and DARK or WALNUT, 4)
  end
  local d = (tx - 9.5) * (tx - 9.5) + (tz - 14.5) * (tz - 14.5)
  if y == 10 and d <= 6.5 then return sw(BONE, 3) end
  if y == 11 and d <= 6.5 and d > 2.5 then return sw(BONE, 5) end
  if y == 10 and tx >= 18 and tx <= 23 and tz >= 12 and tz <= 15 then
    return sw(PAPER, tx == 20 and 0 or 5)
  end
  if (tx == 25 or tx == 26) and (tz == 20 or tz == 21) and y <= 13 then return sw(IRON, 4) end
  if tx == 25 and tz == 20 then
    if y <= 15 then return sw(DRY, 3) end
    if y == 16 then return sw(FLOWER, 0) end
  end
  return nil
end

local function desk(tx, y, tz)
  if y <= 8 then
    if tz < 2 or tz > 29 then return nil end
    local ped = (tx >= 1 and tx <= 11) or (tx >= 20 and tx <= 30)
    if ped then
      if tz == 29 then
        if (tx == 6 or tx == 25) and (y == 1 or y == 5 or y == 8) then return sw(BRASS, 4) end
        if y == 3 or y == 6 then return sw(DARK, 4) end
      end
      return sw(WALNUT, 3)
    end
    if tz <= 3 and y >= 3 and tx > 11 and tx < 20 then return sw(WALNUT, 2) end
    return nil
  end
  local edgeX, edgeZ = tx <= 1 or tx >= 30, tz <= 1 or tz >= 30
  if y == 9 then return sw(WALNUT, 4) end
  if y == 10 then
    if edgeX and edgeZ then return sw(BRASS, 5) end
    if edgeX or edgeZ then return sw(WALNUT, 5) end
    return sw(FELT, 4)
  end
  -- an open book, a stack of name cards, inkwell and quill
  if y == 11 and tx >= 12 and tx <= 21 and tz >= 18 and tz <= 25 then
    if tx == 16 or tx == 17 then return sw(PAPER, 0) end
    return sw(PAPER, tz % 2 == 0 and 2 or 6)
  end
  if tx >= 24 and tx <= 27 and tz >= 20 and tz <= 24 and y <= 13 then
    if y == 13 and tx == 25 and tz == 22 then return sw(BOOK_R, 4) end
    return sw(PAPER, y * 2)
  end
  if (tx == 23 or tx == 24) and (tz == 12 or tz == 13) and y <= 12 then return sw(IRON, 4) end
  if y >= 13 and y <= 17 and tx == 24 + (y - 13) and (tz == 12 or (y >= 15 and tz == 13)) then
    return sw(BONE, 6)
  end
  -- the banker's lamp
  local lx, lz = tx - 27, tz - 6
  local ld = lx * lx + lz * lz
  if y == 11 and ld <= 4 then return sw(BRASS, 3) end
  if y <= 17 and ld == 0 then return sw(BRASS, 5) end
  if y == 17 and ld <= 4 then return sw(LIGHT, 6) end
  if y >= 18 and y <= 20 and ld <= (21 - y) * (21 - y) then return sw(FELT, 5) end
  -- the globe
  local gx, gz = tx - 5, tz - 6
  if y == 11 and gx * gx + gz * gz <= 4 then return sw(WALNUT, 3) end
  if y == 12 and gx == 0 and gz == 0 then return sw(BRASS, 4) end
  local gd = gx * gx + gz * gz + (y - 16) * (y - 16)
  if gd <= 9.5 then
    return hash(tx, y, tz) % 3 == 0 and sw(LEAF, 5) or sw(BOOK_B, 5)
  end
  return nil
end

-- ----------------------------------------------------------- the stools --
-- All three sit at SEAT_H: the cell is walkable and the template's standH
-- is one number, so a variant may change a seat's shape but not its height.
local CUSHION = { PINK, TEAL, CURT_L, YELLOW }

local function stools(x, y, z, v)
  if z < 48 or z > 79 then return nil end
  local west = x >= 32 and x <= 47
  if not west and not (x >= 80 and x <= 95) then return nil end
  local dx = x - (west and 39.5 or 87.5)
  local dz = z - (z <= 63 and 55.5 or 71.5)
  local d = dx * dx + dz * dz
  local idx = (west and 0 or 1) + (z <= 63 and 1 or 3)
  if v == 1 then
    if y <= 3 then return d <= 3 and sw(OAK, 2) or nil end
    if y == 4 then return d <= 27 and sw(OAK, 5) or nil end
    if y == 5 then return d <= 21 and sw(CUSHION[idx], 4 + hash(x, 0, z) % 2) or nil end
    return nil
  elseif v == 2 then
    local ax, az = abs(dx), abs(dz)
    if ax > 4.5 or az > 4.5 then return nil end
    if y <= 3 then return (ax >= 3.5 and az >= 3.5) and sw(DARK, 3) or nil end
    if y <= 5 then return sw((ax >= 3.5 or az >= 3.5) and DARK or WALNUT, 4) end
    return nil
  end
  local ax, az = abs(dx), abs(dz)
  if ax > 5.5 or az > 5.5 then return nil end
  if y <= 3 then return (ax >= 4.5 and az >= 4.5) and sw(DARK, 3) or nil end
  if y == 4 then return sw(WALNUT, 4) end
  if y == 5 then
    if ax >= 4.5 and az >= 4.5 then return sw(BRASS, 4) end
    return sw(RUG_C, 4 + hash(x, 0, z) % 2)
  end
  -- the back, on the side away from the desk
  local outer = west and dx <= -4 or (not west and dx >= 4)
  if outer and y <= 13 then
    if az >= 4.5 or y == 13 then return sw(WALNUT, 3) end
    return sw(RUG_C, 3)
  end
  return nil
end

-- ----------------------------------------------------------- the plants --

local function pot(px, y, pz, v)
  if v == 3 then            -- a brass-banded box planter
    if abs(px) > 5 or abs(pz) > 5 then return nil end
    if y == 7 and abs(px) <= 4 and abs(pz) <= 4 then return sw(DARK, 2) end
    return sw((y == 1 or y == 6) and BRASS or OAK, 3)
  end
  local r = 3 + floor(y / 3)
  local d = px * px + pz * pz
  if d > r * r + 1 then return nil end
  if y == 7 and d <= (r - 1) * (r - 1) then return sw(DARK, 2) end
  return sw(v == 1 and CLAY or PLASTER_C, y == 6 and 6 or 2 + hash(px, 0, pz) % 3)
end

local function plant(x, y, z, v)
  local east = x >= 112
  local px, pz = x - (east and 120 or 8), z - 120
  if y <= 7 then return pot(px, y, pz, v) end
  local d = px * px + pz * pz
  if v == 1 then
    if y <= 10 then return d <= 1 and sw(DRY, 3) or nil end
    if east then            -- a low white-flowered bush
      local e = d / 36 + (y - 14) * (y - 14) / 30
      if e > 1 or hash(px, y, pz) % 8 == 0 then return nil end
      return (y >= 15 and hash(px, y, pz) % 3 == 0) and sw(WHITE, px) or sw(LEAF, hash(px, y, pz))
    end
    local e = d / 49 + (y - 17) * (y - 17) / 81
    if e <= 1 then
      if hash(px, y, pz) % 8 == 0 then return nil end
      return (y >= 20 and hash(px, y, pz) % 3 == 0) and sw(FLOWER, px + y) or sw(LEAF, hash(px, y, pz))
    end
    if y <= 28 and d <= 25 and hash(px, 0, pz) % 11 == 0 then return sw(FLOWER, y) end
    return nil
  elseif v == 2 then        -- nobody has watered these
    local top = east and 16 or 22
    if y > top then return nil end
    if px == 0 and pz == 0 then return sw(DRY, 2) end
    local reach = floor((y - 11) / 2)
    if reach >= 1 and ((abs(px) == reach and pz == 0) or (abs(pz) == reach - 1 and px == 0 and reach > 1)) then
      return sw(DRY, 3)
    end
    if reach >= 2 and d <= (reach + 1) * (reach + 1) and hash(px, y, pz) % 23 == 0 then
      return sw(DRY, 6)
    end
    return nil
  end
  -- clipped topiary: two balls on a stem
  if d <= 1 and y <= 27 then
    if y <= 9 or (y >= 21 and y <= 22) then return sw(DRY, 2) end
  end
  local b1 = d + (y - 15) * (y - 15)
  local b2 = d + (y - 25) * (y - 25)
  if b1 <= 36 or b2 <= 16 then return sw(LEAF, 2 + hash(px, y, pz) % 4) end
  return nil
end

-- -------------------------------------------------------------- the rug --
-- One voxel thick on the open floor. Its cells are NOT claimed: the mesher
-- keeps painting the floor under it, which is what keeps the entrance from
-- going black the way the shop's claimed floor did.
local function rug(x, z, v)
  if v == 1 then
    local d = (x - 63.5) * (x - 63.5) + (z - 63.5) * (z - 63.5)
    if d > 38 * 38 then return nil end
    if d > 36 * 36 then return sw(TRIM, 3) end
    return sw(floor(d ^ 0.5 / 6) % 2 == 0 and RUG_V or RUG_CREAM, 4 + hash(x, 0, z) % 2)
  elseif v == 3 then
    if x < 20 or x > 107 or z < 38 or z > 89 then return nil end
    local bx, bz = min(x - 20, 107 - x), min(z - 38, 89 - z)
    local b = min(bx, bz)
    if b <= 2 then return sw(b == 1 and BRASS or RUG_CREAM, 3) end
    if abs(x - 63.5) + abs(z - 63.5) <= 7 then return sw(BOOK_B, 3) end
    if (abs(x - 63.5) + abs(z - 63.5)) % 12 < 2 then return sw(RUG_CREAM, 3) end
    return sw(RUG_C, 3 + hash(x, 0, z) % 2)
  end
  return nil
end

-- ------------------------------------------------------------ the floor --
-- The tileset's floor is one white tile for every house in Kanto, so each
-- home lays its own boards over it, one voxel thick. The doormat's cells
-- are left open: the drawn mat shows through, set into the boards.
local function boards(x, z, v)
  if z >= 112 and x >= 32 and x <= 63 then
    -- ...except in the mourning house, where a red mat is the one loud
    -- thing in the room: a dark woven one lies over it, bound in iron grey.
    if v ~= 2 then return nil end
    if x <= 33 or x >= 62 or z <= 113 or z >= 126 then return sw(IRON, 4) end
    return sw(CURT_D, 2 + (x + floor(z / 2)) % 2 * 3)
  end
  if v == 3 then            -- parquet, blocks of eight turned against each other
    local along = (floor(x / 8) + floor(z / 8)) % 2 == 0
    local strip = along and z % 8 or x % 8
    if strip == 0 then return sw(DARK, 6) end
    return sw(OAK, hash(floor(x / 8), floor(strip / 2), floor(z / 8)) % 3)
  end
  local row = floor(z / 4)
  local run = x + row * 11
  if z % 4 == 0 or run % 24 == 0 then return sw(v == 1 and OAK or DARK, v == 1 and 3 or 6) end
  local plank = hash(floor(run / 24), row, v) % 3
  return v == 1 and sw(OAK, 5 + plank) or sw(DRY, plank)
end

-- ------------------------------------------------------------- the room --

local function furniture(x, y, z, v)
  if z <= 11 then
    local w = northWall(x, y, z, v)
    if w or z <= 9 or not (x <= 31 or x >= 112) then return w end
  end
  if z >= 10 and z <= 30 then
    if x <= 31 then return westCases(x, y, z, v) end
    if x >= 112 then return eastCase(x, y, z, v) end
  end
  if v == 2 and z == 31 and x >= 112 then return wardrobeDrape(x, y, z) end
  if x >= 48 and x <= 79 and z >= 48 and z <= 79 then
    local t = v == 1 and teaTable or (v == 2 and bareTable or desk)
    return t(x - 48, y, z - 48)
  end
  if z >= 108 and (x <= 15 or x >= 112) then return plant(x, y, z, v) end
  return nil
end

local function roomFor(v)
  return function(x, y, z)
    if x < 0 or x > 127 then                         -- side walls, outside
      if y > sideH(z) or z < 0 then return nil end
      return wallSkin(z + 5, y, v)
    end
    local hit = furniture(x, y, z, v)
    if hit or y > 0 or z <= 9 then return hit end
    return rug(x, z, v) or boards(x, z, v)
  end
end

local FLOOR = { [1] = true, [4] = true, [20] = true }
local STOOL = { [2] = true, [3] = true, [18] = true, [19] = true }

-- `t.home` is "room", "stoolsW" or "stoolsE"; `mapId` picks who lives here.
function Kit.model(sp, t, mapId)
  local v = Kit.MAPS[mapId]
  if not v then return nil, "not a Lavender home: " .. tostring(mapId) end
  if not sp or sp.W ~= Kit.SHEET_W or sp.H ~= Kit.SHEET_H then
    return nil, "sheet is not " .. Kit.SHEET_W .. "x" .. Kit.SHEET_H
  end
  local seats = t.home == "stoolsW" or t.home == "stoolsE"
  local rows, cols = #t.tiles, #t.tiles[1]
  local mask = {}
  for r = 1, rows do
    for c = 1, cols do
      local id = t.tiles[r][c]
      if seats then mask[(r - 1) * cols + c] = STOOL[id] or false
      else mask[(r - 1) * cols + c] = not (FLOOR[id] or STOOL[id]) end
    end
  end
  if seats then
    -- the template's own corner is tile (4, 6) or (10, 6)
    local x0 = t.home == "stoolsW" and 32 or 80
    return { at = function(x, y, z) return stools(x + x0, y, z + 48, v) end,
             W = 16, xmin = 0, xmax = 15, zmin = 0, zmax = 31, ytop = 13,
             standH = Kit.SEAT_H, claimMask = mask, noFigure = true }
  end
  return { at = roomFor(v), W = 128, xmin = -WALL_D, xmax = 127 + WALL_D,
           zmin = 0, zmax = 127, ytop = WALL_H + 1,
           standH = 0, claimMask = mask, noFigure = true }
end

Kit.room, Kit.stools = roomFor, stools   -- for tools/lavender_home.py

return Kit
