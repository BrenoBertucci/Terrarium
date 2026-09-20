-- Voxel world mode: the HOUSES of Vermilion City, outside -- six of them, and
-- no two alike.
--
-- Every one of them is the same drawing (data/voxel_heights.lua,
-- `flat_commercial` with a door, `flat_block_4x4` without): a 64x64 plot
-- folded into an orange-lidded brick box, six times over. A port is not
-- built like that. So here, and only here, each house is built from nothing
-- for whoever the map says lives in it, in one shared language -- a pale
-- stone plinth (the quay's stone), sun-bleached walls, white trim, roofs of
-- terracotta pantile -- and told apart by its FORM first, because the camera
-- looks down and what it sees of a house is mostly its roof:
--
--   ROD      the Fishing Guru's. A fisherman's cottage: grey-blue clapboard
--            under a steep shingled gable, a net with its floats drying on
--            the wall, rods by the door, a fish on the sign, a barrel.
--   CAPTAIN  (no door) a sea captain's house: white stucco, a hipped roof cut
--            off flat for a widow's walk with its railing and a flagstaff,
--            a porthole, an anchor on the wall.
--   LIGHT    (no door) the keeper's cottage and the harbour LIGHT: a round
--            tower banded red and white, a gallery, a lantern that burns.
--   CLUB     the Pokemon Fan Club. Cream plaster under a vermilion mansard
--            with dormers, bunting across the front, a bay window, a rosette
--            over the door.
--   TRADE    the trader's. A brick shop floor under a half-timbered loft, a
--            striped awning over a stall with its goods set out, crates, a
--            two-arrow sign.
--   PIDGEY   the pigeon-post house. Butter-yellow stucco, blue shutters, a
--            dovecote riding the ridge with its holes and perches, a red
--            letter box at the gate.
--
-- NO Nintendo mark is drawn here (assets/buildings/LICENSE.md): a fish, an
-- anchor, a rosette, two arrows.
--
-- Same contract as Lavender's (lib/LavenderCivicKit.lua): chosen ONLY for
-- these placements on VERMILION_CITY (Buildings.build), an authored swatch
-- sheet, Buildings' shell mesher and AO, the chimney's mouth handed to
-- HearthFX, `lights` to the lamps' pass. The plot, the door (x 16..31 of the
-- south face) and the warp lane are the template's: nothing below head
-- height stands in the door's cell. Window glass wears the GLASS row, which
-- VoxelScene lights after dark (Kit.GLASS_UV through Voxel3D.lantern) -- an
-- authored sheet has no glass mask of its own.
--
-- Coordinates are the plot's: x east 0..63, z south 0..63, y up. A person is
-- sixteen voxels. Nothing here is extracted from the ROM.
local Kit = { SHEET = "assets/buildings/vermilion_houses.png",
              SHEET_W = 8, SHEET_H = 30 }

local floor, abs, min, max, sqrt = math.floor, math.abs, math.min, math.max, math.sqrt

-- Rows of the swatch sheet, eight shades each: tools/vermilion_houses.py is
-- the mirror of this list.
local STONE, MORTAR, WHITE, CREAM, YELLOW, BLUEGREY, BRICK, TIMBER,
      WOOD, TERRA, TERRA_DK, SHINGLE, VERMILION, IRON, GLASS, LIGHT,
      SH_BLUE, SH_GREEN, RED, ROPE, LEAF, FLOWER, PINK, PAVE,
      PAVEJOINT, AWN_GREEN, GOLD, NAVY, SHADOW, LEAD =
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
      16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29
-- the GLASS and LIGHT rows (neighbours, on purpose) as a UV rect of the
-- sheet, for Voxel3D.lantern: panes, door lanterns and the harbour light
Kit.GLASS_UV = { 0, GLASS / Kit.SHEET_H, 1, (LIGHT + 1) / Kit.SHEET_H }

local function sw(row, n) return row * 8 + n % 8 end
local function noise(x, y, z) return (x * 17 + y * 31 + z * 13) % 8 end

-- --------------------------------------------------------------- materials --
local function stone(u, y, salt)
  local course = floor(y / 3)
  if y % 3 == 2 or (u + course % 2 * 4) % 8 == 0 then return sw(MORTAR, 3) end
  return sw(STONE, noise(floor((u + course % 2 * 4) / 8), course, salt))
end
local function brick(u, y, salt)
  local course = floor(y / 3)
  if y % 3 == 0 or (u + course % 2 * 3) % 6 == 0 then return sw(MORTAR, 5) end
  return sw(BRICK, noise(floor((u + course % 2 * 3) / 6), course, salt))
end
local function stucco(row)
  return function(u, y, salt)
    return sw(row, 2 + (floor(u / 9) + floor(y / 6) * 3 + salt) % 5)
  end
end
-- boards lying along the wall, each lapped over the one below: a shadow line
local function clapboard(row)
  return function(u, y, salt)
    if y % 3 == 0 then return sw(row, 0) end
    return sw(row, 3 + (floor(y / 3) * 5 + floor(u / 16) + salt) % 4)
  end
end
local function timber(u, y) return sw((u + y) % 5 == 0 and WOOD or TIMBER, 2 + floor(y / 7) % 3) end
-- cream infill in a dark frame: studs, plates at lo/hi, braces off the rail
local function halftimber(lo, hi)
  local rail = floor((lo + hi) / 2)
  return function(u, y, salt)
    if y == lo or y == hi or y == rail or u % 9 == 0 then return timber(u, y) end
    if (u + y) % 18 == 0 or (u - y) % 18 == 0 then return timber(u, y) end
    return sw(CREAM, 3 + (floor(u / 9) + floor(y / 6) + salt) % 4)
  end
end
-- pantiles: a rib every third voxel along the eave, a course line up the slope
local function pantile(u, d, salt)
  if d % 4 == 0 then return sw(TERRA_DK, 3 + u % 2) end
  if u % 3 == 0 then return sw(TERRA_DK, 5) end
  return sw(TERRA, 2 + (floor(u / 3) + floor(d / 4) * 3 + (salt or 0)) % 5)
end
local function shingle(u, d, salt)
  local course = floor(d / 3)
  if d % 3 == 0 then return sw(SHINGLE, 0) end
  if (u + course % 2 * 2) % 5 == 0 then return sw(SHINGLE, 1) end
  return sw(SHINGLE, 3 + noise(floor((u + course % 2 * 2) / 5), course, salt or 0) % 5)
end
local function mansardTile(u, d, salt)
  if d % 3 == 0 then return sw(VERMILION, 0) end
  if (u + floor(d / 3) % 2 * 2) % 4 == 0 then return sw(VERMILION, 1) end
  return sw(VERMILION, 3 + (floor(u / 4) + floor(d / 3) + (salt or 0)) % 5)
end
-- the plot's own paving, one voxel thick: the quay's pale slabs, on the same
-- eight-voxel grid as the ground's (tools/vermilion_ground.py)
local function pave(x, z)
  if x % 8 == 0 or z % 8 == 0 then return sw(PAVEJOINT, 3) end
  return sw(PAVE, 2 + (floor(x / 8) * 3 + floor(z / 8) * 5) % 4)
end
local function glyph(rows, x0, ytop, x, y)
  local row = rows[ytop - y + 1]
  local cx = x - x0 + 1
  return row ~= nil and cx >= 1 and cx <= #row and row:sub(cx, cx) == "X"
end

-- A window let into a wall: `u` across, `y` up, `depth` IN from the face
-- (0 = the face, negative = proud of it). Answers handled, texel -- a texel
-- of nil is a carved voxel. `shut`: a row, for shutters hung either side.
local function window(u, y, depth, W)
  local du = u - W.c + 0.5
  local w2, y0, y1 = W.w2, W.y0, W.y1
  local reach = w2 + (W.shut and 5.5 or 1.5)
  if abs(du) > reach or y < y0 - 2 or y > y1 + 1 or depth < -1 or depth > 2 then return false end
  local inside = abs(du) <= w2 and y >= y0 and y <= y1
  if inside and W.arch then
    local spring = y1 - w2
    if y > spring and du * du + (y - spring) * (y - spring) > w2 * w2 + 1 then inside = false end
  end
  if y == y0 - 1 and abs(du) <= w2 + 1.5 and depth <= 0 then return true, sw(WHITE, 6) end   -- the sill, proud
  if W.box and y == y0 - 2 and abs(du) <= w2 + 0.5 and depth == -1 then return true, sw(WOOD, 3) end
  if W.box and y == y0 - 1 and abs(du) <= w2 + 0.5 and depth == -1 then                      -- a window box
    return true, sw((floor(du) % 3 == 0) and W.box or LEAF, 3 + floor(du) % 3)
  end
  if W.shut and depth == -1 and abs(du) > w2 + 1 and abs(du) <= w2 + 5 and y >= y0 and y <= y1 then
    return true, sw(W.shut, (y % 2 == 0) and 1 or 4)                                         -- louvred shutters
  end
  if not inside then
    if depth == 0 and abs(du) <= w2 + 1 and y >= y0 and y <= y1 + 1 then return true, sw(WHITE, 5) end
    return false
  end
  if depth < 0 then return false end
  if depth < 2 then
    if depth == 1 and (abs(du) < 1 or y == floor((y0 + y1) / 2)) then return true, sw(WHITE, 4) end
    return true, nil
  end
  return true, sw(GLASS, 2 + (floor(du) + y) % 4)
end

-- ------------------------------------------------------------------- roofs --
-- Each answers top, u, d for a column: the y of its outer skin, where along
-- the eave and how far up the slope (for the tiles) -- or nil outside it.
local function gableNS(x0, x1, z0, z1, eave, pitch)
  local cx = (x0 + x1) / 2
  return function(x, z)
    if x < x0 or x > x1 or z < z0 or z > z1 then return nil end
    local d = (x1 - x0) / 2 - abs(x - cx)
    return eave + floor(d * pitch), z, floor(d), (z == z0 or z == z1), d >= (x1 - x0) / 2 - 1
  end
end
local function gableEW(x0, x1, z0, z1, eave, pitch)
  local cz = (z0 + z1) / 2
  return function(x, z)
    if x < x0 or x > x1 or z < z0 or z > z1 then return nil end
    local d = (z1 - z0) / 2 - abs(z - cz)
    return eave + floor(d * pitch), x, floor(d), (x == x0 or x == x1), d >= (z1 - z0) / 2 - 1
  end
end
local function hip(x0, x1, z0, z1, eave, rise, cap)
  return function(x, z)
    if x < x0 or x > x1 or z < z0 or z > z1 then return nil end
    local dx, dz = min(x - x0, x1 - x), min(z - z0, z1 - z)
    local d = min(dx, dz)
    local top = eave + floor(rise(d))
    local flat = cap and top >= cap
    if flat then top = cap end
    return top, (dz < dx) and x or z, d, false, dx == dz and not flat, flat
  end
end

-- --------------------------------------------------------------- the house --
-- S: x0 x1 z0 z1 (walls), wall (their top), skin(face) -> material fn,
-- plinth, roof (fn above), tile (material fn), windows { face, ... }, door
-- (a row, or nil), porch, chimney { x, z, top }, extra(x, y, z) -> handled,
-- texel, lights, ytop.
local function house(S)
  local X0, X1, Z0, Z1, WALL = S.x0, S.x1, S.z0, S.z1, S.wall
  local roof, ch = S.roof, S.chimney
  local DOORC = 23.5

  local function at(x, y, z)
    if x < 0 or x > 63 or z < 0 or z > 63 or y < 0 or y > S.ytop then return nil end
    if S.extra then
      local handled, v = S.extra(x, y, z)
      if handled then return v end
    end
    local top, u, d, barge, ridge, flat = roof(x, z)

    -- ---- the chimney: brick, a stone cap, an open flue
    if ch and x >= ch.x and x <= ch.x + 5 and z >= ch.z and z <= ch.z + 5 and top and y > top - 2 then
      if y <= ch.top then
        if y >= ch.top - 1 then
          if x >= ch.x + 2 and x <= ch.x + 3 and z >= ch.z + 2 and z <= ch.z + 3 then return nil end
          return sw(STONE, 5)
        end
        return brick(x + z, y, 3)
      end
      return nil
    end

    -- ---- the roof: a skin two voxels thick, barge boards, a ridge
    if top and y <= top and y >= top - 2 then
      if flat then return sw(LEAD, 2 + (x + z) % 3) end
      if barge then return sw(WHITE, 5) end
      if ridge then return sw(TERRA_DK, 6) end
      return S.tile(u, d, S.salt)
    end

    local inside = x >= X0 and x <= X1 and z >= Z0 and z <= Z1
    if inside and top and y < top - 2 then
      -- ---- the door: an alcove four deep, the leaf behind it
      if S.door and x >= 17 and x <= 30 and z >= Z1 - 4 and y <= 21 then
        local du = abs(x - DOORC)
        local head = 21 - floor((du / 6.5) ^ 2 * 4)
        if y <= head then
          if y == 0 then return sw(STONE, 5) end
          if x == 17 or x == 30 or y >= head - 1 then return sw(WHITE, 5) end
          if z > Z1 - 4 then return nil end
          if x == 27 and y == 10 then return sw(GOLD, 5) end
          if y == 5 or y == 12 or x == 19 or x == 28 or du < 1 then return sw(S.door, 1) end
          return sw(S.door, 4 + y % 2)
        end
      end
      local face, fu, depth = nil, nil, nil
      if z >= Z1 - 2 then face, fu, depth = "s", x, Z1 - z
      elseif z <= Z0 + 2 then face, fu, depth = "n", x, z - Z0
      elseif x >= X1 - 2 then face, fu, depth = "e", z, X1 - x
      elseif x <= X0 + 2 then face, fu, depth = "w", z, x - X0 end
      if face then
        for _, W in ipairs(S.windows) do
          if W.face == face then
            local handled, v = window(fu, y, depth, W)
            if handled then return v end
          end
        end
      end
      local edge = x == X0 or x == X1 or z == Z0 or z == Z1
      if not edge then return sw(SHADOW, 2) end          -- solid within: nothing to see into
      local wu = (z == Z0 or z == Z1) and x or z
      if y <= S.plinth then return stone(wu, y, S.salt) end
      if (x <= X0 + 1 or x >= X1 - 1) and (z <= Z0 + 1 or z >= Z1 - 1) and S.quoin then
        return sw(S.quoin, 4 + floor(y / 4) % 2)
      end
      return S.skin(y)(wu, y, S.salt)
    end

    -- ---- proud of the walls: shutters, sills, window boxes
    if y > 0 and top then
      local face, fu, depth = nil, nil, nil
      if z == Z1 + 1 and x >= X0 and x <= X1 then face, fu, depth = "s", x, -1
      elseif z == Z0 - 1 and x >= X0 and x <= X1 then face, fu, depth = "n", x, -1
      elseif x == X1 + 1 and z >= Z0 and z <= Z1 then face, fu, depth = "e", z, -1
      elseif x == X0 - 1 and z >= Z0 and z <= Z1 then face, fu, depth = "w", z, -1 end
      if face then
        for _, W in ipairs(S.windows) do
          if W.face == face then
            local handled, v = window(fu, y, depth, W)
            if handled and v then return v end
          end
        end
      end
    end

    -- ---- a porch over the door: a little tiled roof on two brackets
    if S.porch and x >= 13 and x <= 34 and z > Z1 and z <= Z1 + 6 then
      local py = 25 - floor((z - Z1) * 0.7)
      if y == py or y == py - 1 then return S.tile(x, z - Z1, S.salt) end
      if (x == 14 or x == 33) and z <= Z1 + 4 and y >= 18 and y < py - 1 and y >= py - 1 - (Z1 + 5 - z) then
        return timber(x, y)
      end
    end
    -- ---- a lantern by the door
    if S.door and x >= 33 and x <= 35 and z >= Z1 + 1 and z <= Z1 + 3 and y >= 13 and y <= 19 then
      if y == 19 or y == 13 then return sw(IRON, 3) end
      if x == 34 and z == Z1 + 2 then return sw(LIGHT, 5) end
      if (x + z) % 2 == 0 then return sw(IRON, 3) end
      return sw(LIGHT, 3)
    end

    if y == 0 then return pave(x, z) end
    return nil
  end

  local lights = S.lights or {}
  if S.door then lights[#lights + 1] = { x = 34, y = 16, z = Z1 + 2 } end
  return { at = at, W = 64, xmin = 0, xmax = 63, zmin = 0, zmax = 63, ytop = S.ytop,
           chimney = ch and { x = ch.x + 3, y = ch.top + 1, z = ch.z + 3 } or nil,
           lights = #lights > 0 and lights or nil,
           tint = function(y) return 0.90 + min(y / 32, 1) * 0.10 end }
end

local function pitchOf(k) return function(d) return d * k end end
-- the walls' skins, made once: `skin` is asked for every voxel of a wall
local BOARDS, LIMEWASH, PLASTER, BUTTER = clapboard(BLUEGREY), stucco(WHITE), stucco(CREAM), stucco(YELLOW)
local FRAME = halftimber(20, 33)                  -- the trader's loft, over LOFT = 19

-- ------------------------------------------------------------------ the six --

local FISH = { "..XXXX...X", ".XXXXXX.XX", "XXXXXXXXX.", ".XXXXXX.XX", "..XXXX...X" }
local ANCHOR = { "...XXX...", "...X.X...", "...XXX...", "....X....", ".XXXXXXX.", "....X....",
                 "....X....", "X...X...X", "X...X...X", "XX..X..XX", ".XXXXXXX.", "...XXX..." }
local ARROWS = { "..X......", ".XXXXXXXX", "..X......", ".........", "......X..", "XXXXXXXX.", "......X.." }
local PENNANT = { RED, GOLD, SH_BLUE, WHITE, AWN_GREEN }

local function rod()
  local Z1 = 54
  return house({
    x0 = 6, x1 = 57, z0 = 12, z1 = Z1, wall = 26, plinth = 5, salt = 1, ytop = 66,
    skin = function() return BOARDS end, quoin = WHITE,
    roof = gableNS(3, 60, 9, 58, 27, 1.05), tile = shingle,
    door = RED, porch = true,
    chimney = { x = 44, z = 22, top = 60 },
    windows = { { face = "s", c = 46, w2 = 5, y0 = 9, y1 = 20, shut = WHITE },
                { face = "s", c = 32, w2 = 4, y0 = 32, y1 = 41, arch = true },
                { face = "e", c = 30, w2 = 5, y0 = 9, y1 = 20 }, { face = "w", c = 30, w2 = 5, y0 = 9, y1 = 20 },
                { face = "n", c = 32, w2 = 5, y0 = 9, y1 = 20 } },
    extra = function(x, y, z)
      -- a net drying on the wall under its rope, floats along the top
      if z == Z1 + 1 and x >= 39 and x <= 55 and y >= 2 and y <= 8 then
        if y == 8 then return true, sw((x % 5 == 0) and RED or ROPE, 4) end
        if (x + y) % 4 == 0 or (x - y) % 4 == 0 then return true, sw(ROPE, 3) end
      end
      -- two rods leaning by the door
      if z == Z1 + 1 and y >= 1 and y <= 30 and (x == 35 + floor(y / 9) or x == 37 + floor(y / 7)) then
        return true, sw(y > 26 and ROPE or TIMBER, 5)
      end
      -- the sign: a fish on a board, hung from the porch
      if z == Z1 + 7 and y >= 19 and y <= 25 and x >= 18 and x <= 29 then
        if glyph(FISH, 19, 24, x, y) then return true, sw(SH_BLUE, 5) end
        return true, sw(WHITE, 5)
      end
      -- a barrel at the corner
      local bx, bz = x - 59.5, z - 59.5
      if y >= 1 and y <= 9 and bx * bx + bz * bz <= 10 then
        return true, sw((y == 2 or y == 8) and IRON or WOOD, 2 + (x + z) % 4)
      end
      return false
    end,
  })
end

local function captain()
  local Z1, CAP = 54, 46
  return house({
    x0 = 6, x1 = 57, z0 = 12, z1 = Z1, wall = 30, plinth = 5, salt = 2, ytop = 74,
    skin = function() return LIMEWASH end, quoin = STONE,
    roof = hip(3, 60, 9, 57, 31, pitchOf(1.0), CAP), tile = pantile,
    chimney = { x = 10, z = 16, top = 50 },
    windows = { { face = "s", c = 16, w2 = 5, y0 = 9, y1 = 22, shut = NAVY },
                { face = "s", c = 48, w2 = 5, y0 = 9, y1 = 22, shut = NAVY },
                { face = "e", c = 33, w2 = 5, y0 = 9, y1 = 22, shut = NAVY },
                { face = "w", c = 33, w2 = 5, y0 = 9, y1 = 22, shut = NAVY } },
    extra = function(x, y, z)
      -- the widow's walk: a white railing round the deck, a flagstaff in it
      local onDeck = x >= 19 and x <= 44 and z >= 25 and z <= 41
      if onDeck and y > CAP and y <= CAP + 6 then
        local rim = x == 19 or x == 44 or z == 25 or z == 41
        if rim and (y == CAP + 6 or y == CAP + 3 or (x + z) % 5 == 0) then return true, sw(WHITE, 5) end
      end
      if x == 32 and z == 33 and y > CAP and y <= CAP + 27 then return true, sw(WHITE, 4) end
      if z == 33 and x >= 33 and x <= 42 and y >= CAP + 19 and y <= CAP + 26
         and (x - 33) <= (CAP + 26 - y) * 2 + 3 and (x - 33) <= (y - CAP - 19) * 2 + 3 then
        return true, sw((y >= CAP + 22 and y <= CAP + 23) and WHITE or NAVY, 4)
      end
      -- the anchor on the wall, and a brass porthole over it
      if z == Z1 + 1 and glyph(ANCHOR, 28, 19, x, y) then return true, sw(IRON, 3) end
      local px, py = x - 32, y - 25
      if z >= Z1 - 1 and z <= Z1 and px * px + py * py <= 14 then
        if px * px + py * py > 6 then return true, sw(GOLD, 4) end
        if z == Z1 then return true, nil end
        return true, sw(GLASS, 3)
      end
      return false
    end,
  })
end

local function light()
  local Z1 = 54
  local TX, TZ, BASE, GAL = 47, 32, 11, 72          -- the tower's axis, its foot's radius, its gallery
  local function radius(y) return BASE - y * 3.5 / GAL end
  local cottage = house({
    x0 = 4, x1 = 34, z0 = 16, z1 = Z1, wall = 22, plinth = 5, salt = 3, ytop = 96,
    skin = function() return LIMEWASH end, quoin = STONE,
    roof = hip(1, 37, 13, 57, 23, pitchOf(0.95)), tile = pantile,
    chimney = { x = 8, z = 22, top = 42 },
    windows = { { face = "s", c = 19, w2 = 5, y0 = 8, y1 = 18, shut = RED, box = FLOWER },
                { face = "w", c = 35, w2 = 5, y0 = 8, y1 = 18 } },
    lights = { { x = TX + 0.5, y = GAL + 7, z = TZ + 0.5 } },
    extra = function(x, y, z)
      local dx, dz = x - TX + 0.5, z - TZ + 0.5
      local r2 = dx * dx + dz * dz
      if r2 > 15 * 15 then return false end
      if y == 0 then return false end
      if y < GAL then
        local r = radius(y)
        if r2 > r * r then return false end
        if r2 < (r - 2) * (r - 2) then return true, sw(SHADOW, 2) end
        -- a door in its foot, two slit windows up it, red and white bands
        if dz > 0 and abs(dx) <= 3 and y <= 15 - floor(dx * dx / 3) then
          return true, sw((abs(dx) > 2 or y >= 14 - floor(dx * dx / 3)) and STONE or TIMBER, 4)
        end
        if dz > 0 and abs(dx) <= 1 and ((y >= 30 and y <= 36) or (y >= 52 and y <= 58)) then
          return true, sw(GLASS, 3)
        end
        if y <= 4 then return true, stone(x + z, y, 3) end
        return true, sw((floor(y / 14) % 2 == 1) and RED or WHITE, 3 + (x + z + y) % 3)
      end
      if y <= GAL + 1 then                                  -- the gallery's deck
        if r2 <= 13 * 13 then return true, sw(y == GAL and STONE or IRON, 4) end
        return false
      end
      if y <= GAL + 5 then                                  -- its railing
        if r2 <= 13 * 13 and r2 > 11.5 * 11.5 and (y == GAL + 5 or (x + z) % 3 == 0) then
          return true, sw(IRON, 3)
        end
      end
      if y <= GAL + 12 then                                 -- the lantern: glass in iron
        if r2 <= 6.5 * 6.5 then
          if r2 < 4.5 * 4.5 then return true, sw(LIGHT, 5) end
          if y == GAL + 12 or (x * 3 + z) % 4 == 0 then return true, sw(IRON, 3) end
          return true, sw(GLASS, 5)
        end
        return false
      end
      local dome = 8 - (y - GAL - 12) * 1.1                 -- a red cap, a finial
      if dome > 0 and r2 <= dome * dome then return true, sw(RED, 2 + (y % 3)) end
      if r2 < 1 and y <= GAL + 24 then return true, sw(IRON, 4) end
      return false
    end,
  })
  return cottage
end

local function club()
  local Z1 = 54
  local function mansard(d) return d < 7 and d * 2.3 or 16 + (d - 7) * 0.22 end
  return house({
    x0 = 5, x1 = 58, z0 = 12, z1 = Z1, wall = 28, plinth = 5, salt = 4, ytop = 62,
    skin = function() return PLASTER end, quoin = WHITE,
    roof = hip(3, 60, 10, 56, 29, mansard, 47), tile = mansardTile,       -- a mansard's top is a flat, in lead
    door = VERMILION,
    chimney = { x = 46, z = 16, top = 56 },
    windows = { { face = "s", c = 9, w2 = 3, y0 = 9, y1 = 20, arch = true },
                { face = "e", c = 33, w2 = 6, y0 = 9, y1 = 21, arch = true, box = PINK },
                { face = "w", c = 33, w2 = 6, y0 = 9, y1 = 21, arch = true, box = PINK },
                { face = "n", c = 32, w2 = 6, y0 = 9, y1 = 21 } },
    extra = function(x, y, z)
      -- bunting across the front, sagging between its two hooks
      if z == Z1 + 2 and x >= 7 and x <= 56 then
        local line = 27 - floor(4 * (1 - ((x - 31.5) / 24.5) ^ 2))
        if y == line then return true, sw(ROPE, 3) end
        local k = (x - 7) % 5
        if y < line and y >= line - 3 + abs(k - 2) and k ~= 0 then
          return true, sw(PENNANT[floor((x - 7) / 5) % #PENNANT + 1], 4)
        end
      end
      -- a bay window: three lights under its own little roof
      if x >= 38 and x <= 54 and z > Z1 and z <= Z1 + 4 then
        if y >= 1 and y <= 6 then return true, stone(x, y, 4) end
        if y >= 7 and y <= 20 then
          local mull = x == 38 or x == 54 or x == 43 or x == 49 or y == 7 or y == 20 or y == 14
          if z == Z1 + 4 or x == 38 or x == 54 then
            return true, mull and sw(WHITE, 5) or sw(GLASS, 2 + (x + y) % 4)
          end
          return true, sw(SHADOW, 3)
        end
        if y >= 21 and y <= 21 + (Z1 + 5 - z) then return true, mansardTile(x, y - 21, 4) end
      end
      -- two dormers in the mansard, and a rosette over the door
      for _, c in ipairs({ 18, 45 }) do
        local du = abs(x - c - 0.5)
        if du <= 5 and z >= 46 and z <= 52 and y >= 31 and y <= 44 - floor(du) then
          if y >= 43 - floor(du) then return true, mansardTile(x, z, 4) end
          if z < 52 then return true, sw(SHADOW, 3) end
          if du <= 3 and y >= 33 and y <= 40 then return true, sw(GLASS, 2 + (x + y) % 4) end
          return true, sw(WHITE, 5)
        end
      end
      local rx, ry = x - 23.5, y - 26
      if z == Z1 + 1 and rx * rx + ry * ry <= 16 then
        local q = rx * rx + ry * ry
        return true, sw(q <= 3 and RED or ((q > 9 or (floor(x) + y) % 2 == 0) and GOLD or WHITE), 4)
      end
      return false
    end,
  })
end

local function trade()
  local Z1, LOFT = 54, 19
  return house({
    x0 = 5, x1 = 58, z0 = 12, z1 = Z1, wall = 34, plinth = 4, salt = 5, ytop = 66,
    skin = function(y) return y <= LOFT and brick or FRAME end,
    roof = gableEW(2, 61, 8, 58, 35, 1.0), tile = pantile,
    door = SH_GREEN,
    chimney = { x = 10, z = 24, top = 62 },
    windows = { { face = "s", c = 46, w2 = 8, y0 = 9, y1 = 17 },
                { face = "s", c = 16, w2 = 4, y0 = 23, y1 = 31 }, { face = "s", c = 32, w2 = 4, y0 = 23, y1 = 31 },
                { face = "s", c = 48, w2 = 4, y0 = 23, y1 = 31 },
                { face = "e", c = 33, w2 = 5, y0 = 23, y1 = 31 }, { face = "w", c = 33, w2 = 5, y0 = 23, y1 = 31 } },
    extra = function(x, y, z)
      -- the stall: a counter under the shop window, its goods set out
      if x >= 37 and x <= 55 and z > Z1 and z <= Z1 + 4 and y >= 1 and y <= 9 then
        if y <= 7 then return true, timber(x, y) end
        if y == 8 then return true, sw(WOOD, 5) end
        if z <= Z1 + 3 and x % 3 ~= 0 then
          return true, sw(({ RED, GOLD, LEAF, FLOWER, PINK })[floor(x / 3) % 5 + 1], 4)
        end
      end
      -- a striped awning over it, falling toward the street
      if x >= 35 and x <= 57 and z > Z1 and z <= Z1 + 7 then
        local ay = 21 - floor((z - Z1) * 0.6)
        if y == ay then return true, sw((x % 6 < 3) and AWN_GREEN or WHITE, 4) end
        if z == Z1 + 7 and y == ay - 1 then return true, sw((x % 6 < 3) and AWN_GREEN or WHITE, 2) end
      end
      -- crates, and a sack against them
      if y >= 1 and x >= 1 and x <= 12 and z >= Z1 + 2 and z <= Z1 + 8 then
        local hi = (x <= 7) and 12 or 6
        if y <= hi then
          local rim = x == 1 or x == 7 or x == 8 or x == 12 or y == 1 or y == hi or y == 6 or y == 7
          return true, sw(rim and TIMBER or WOOD, 3 + (x + y) % 3)
        end
      end
      -- the sign: two arrows, this way and that, on a bracket over the door
      if z == Z1 + 3 and x >= 18 and x <= 29 and y >= 23 and y <= 31 then
        if x == 18 or x == 29 or y == 23 or y == 31 then return true, sw(TIMBER, 3) end
        return true, sw(glyph(ARROWS, 19, 30, x, y) and SH_GREEN or CREAM, 5)
      end
      if (z == Z1 + 1 or z == Z1 + 2) and (x == 19 or x == 28) and y == 32 then return true, sw(IRON, 3) end
      return false
    end,
  })
end

local function pidgey()
  local Z1 = 54
  local CX, CZ, FOOT, LOFT = 31.5, 30, 50, 64       -- the dovecote, astride the ridge
  return house({
    x0 = 7, x1 = 56, z0 = 12, z1 = Z1, wall = 26, plinth = 5, salt = 6, ytop = 76,
    skin = function() return BUTTER end, quoin = WHITE,
    roof = gableNS(4, 59, 9, 58, 27, 0.92), tile = pantile,
    door = SH_BLUE, porch = true,
    chimney = { x = 12, z = 40, top = 50 },
    windows = { { face = "s", c = 46, w2 = 5, y0 = 9, y1 = 20, shut = SH_BLUE, box = PINK },
                { face = "s", c = 32, w2 = 4, y0 = 31, y1 = 40, arch = true, shut = SH_BLUE },
                { face = "e", c = 33, w2 = 5, y0 = 9, y1 = 20, shut = SH_BLUE },
                { face = "w", c = 33, w2 = 5, y0 = 9, y1 = 20, shut = SH_BLUE } },
    extra = function(x, y, z)
      local dx, dz = abs(x - CX), abs(z - CZ)
      -- the dovecote: a white loft on the ridge, holes and perches, a cap
      if dx <= 7 and dz <= 7 and y >= FOOT and y <= LOFT then
        if dx > 6 or dz > 6 then
          if y == FOOT + 4 or y == FOOT + 10 then return true, sw(WOOD, 4) end   -- the perches
          return false
        end
        local rim = dx > 5 or dz > 5
        if not rim then return true, sw(SHADOW, 2) end
        local across = (dz > 5) and (x - CX) or (z - CZ)
        local hole = (abs(abs(across) - 3) <= 1) and ((y >= FOOT + 5 and y <= FOOT + 8) or (y >= FOOT + 11 and y <= FOOT + 13))
        if hole then return true, sw(SHADOW, 0) end
        return true, sw(WHITE, 3 + y % 3)
      end
      local capd = max(dx, dz)
      if y > LOFT and y <= LOFT + 9 and capd <= 9 - (y - LOFT) then
        return true, pantile(x + z, y - LOFT, 6)
      end
      if dx < 1 and dz < 1 and y > LOFT + 8 and y <= LOFT + 12 then return true, sw(IRON, 4) end
      -- a red letter box on its post, by the gate
      if x >= 37 and x <= 38 and z >= Z1 + 5 and z <= Z1 + 6 and y >= 1 and y <= 9 then return true, timber(x, y) end
      if x >= 36 and x <= 40 and z >= Z1 + 4 and z <= Z1 + 7 and y >= 10 and y <= 14 then
        if z == Z1 + 7 and y == 12 and x >= 37 and x <= 39 then return true, sw(SHADOW, 1) end
        return true, sw(y == 14 and WHITE or RED, 4)
      end
      return false
    end,
  })
end

-- Which house stands on the placement whose top-left TILE is (tx, ty).
Kit.PLACES = { ["12:0"] = rod, ["28:0"] = captain, ["40:0"] = light,
               ["16:20"] = club, ["28:20"] = trade, ["44:32"] = pidgey }
Kit.TEMPLATES = { flat_commercial = true, flat_block_4x4 = true }

function Kit.model(sp, t, tx, ty)
  -- the A/B switch (tests/vermilion_houses_cost_probe.lua): off, the classic box stands
  if Kit.ENABLED == false then return nil, "switched off" end
  if not sp or sp.W ~= Kit.SHEET_W or sp.H ~= Kit.SHEET_H then
    return nil, "sheet is not " .. Kit.SHEET_W .. "x" .. Kit.SHEET_H
  end
  if #t.tiles ~= 8 or #t.tiles[1] ~= 8 then return nil, "expected a 64x64 plot" end
  local make = Kit.PLACES[tostring(tx) .. ":" .. tostring(ty)]
  if not make then return nil, "no house of Vermilion's stands at " .. tostring(tx) .. ":" .. tostring(ty) end
  return make()
end

return Kit
