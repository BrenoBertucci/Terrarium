-- Voxel world mode: three of Vermilion's homes INSIDE.
--
-- The Fishing Guru's house, the trader's and the pigeon-post house are the
-- SAME 16x16 tile plan every town house in Kanto is (lib/LavenderHomeKit.lua
-- stands Lavender's three on it), and the plan is also the collision, so the
-- furniture cannot move: two cases in the north-west, a window and a picture
-- on the north wall, a case in the north-east, a table with four seats, a
-- corner piece either side of the door. What can change is everything that
-- stands on those cells -- and here each room is the inside of the house
-- lib/VermilionHouseKit.lua built outside it:
--
--   1  ROD     the Fishing Guru's den. Whitewashed boards over a grey-blue
--              wainscot, a net swagged over the window, a trophy fish on a
--              plaque; a rack of rods and a case of tackle, a locker of rope
--              and nets under a sou'wester; a trestle table with the catch
--              on a board and the tackle box open; half-barrels to sit on, a
--              coil of rope, a barrel of glass floats, a rag rug.
--   2  TRADE   the trader's counting room. Ochre plaster over green
--              panelling, red curtains, a sea chart; shelves of cloth, tins
--              and boxes, an iron-bound strongbox under the ledgers with the
--              scales on top; a baize-topped table with a balance, coin in
--              stacks, a ledger and two parcels; crates, a fig in a brass
--              planter, a red carpet.
--   4  CLUB    the Pokemon Fan Club -- ANOTHER PLAN (the INTERIOR tileset):
--              see `the FAN CLUB` below. Red panelling under cream, a banner,
--              prize rosettes, a sideboard of cups, tea on a lace cloth round
--              the biggest cup of all, pink velvet couches.
--   3  PIDGEY  the pigeon post. Butter walls over a blue dado, gingham at
--              the window, a great sealed envelope in a frame; a wall of
--              pigeonholes stuffed with letters, a white dovecote with a
--              bird looking out; a writing table with ink, quill and the
--              post (its north-east quarter kept clear: the LETTER lies
--              there); blue stools, a perch with a pigeon on it, a sack of
--              seed, a braided rug, a feather or two on the boards.
--
-- Same contract as lib/LavenderHomeKit.lua, to the letter -- its three
-- templates (data/voxel_heights.lua, buildings.HOUSE: `room`, `stoolsW`,
-- `stoolsE`) carry these maps too, and Buildings picks the kit by MAP ID:
-- an authored sheet (tools/vermilion_home.py) through the spriteQuads path,
-- a person is sixteen voxels, the fixed dollhouse shot (data/
-- camera_shots.lua), side walls cut down toward the camera, nothing tall to
-- the south, the rug and boards laid but their cells not claimed.
--
-- Coordinates: x east 0..127, z south 0..127, y up. Side walls stand
-- outside the box. Nothing here is extracted from the ROM.
local Kit = { SHEET = "assets/buildings/vermilion_home.png",
              SHEET_W = 8, SHEET_H = 32,
              -- What a sitter stands at is the PROFILE's `stool` class (8), not a
              -- model's standH: VoxelScene.groundAt asks TileShape. So every seat
              -- here tops out at y 7, and whoever sits on it sits ON it.
              SEAT_H = 8 }

Kit.MAPS = { VERMILION_OLD_ROD_HOUSE = 1, VERMILION_TRADE_HOUSE = 2,
             VERMILION_PIDGEY_HOUSE = 3, POKEMON_FAN_CLUB = 4 }

local floor, abs, max, min = math.floor, math.abs, math.max, math.min

-- rows of the sheet; tools/vermilion_home.py is the mirror of this list
local WHITEWASH, OCHRE, BUTTER, BLUEGREY, GREEN, BLUE, DRIFT, OAK,
      WALNUT, DARK, TRIM, SKY, NET, ROPE, IRON, BRASS,
      RED, ORANGE, NAVY, TEAL, YELLOW, PAPER, FISH, FISHBLUE,
      LEAF, STRAW, BAIZE, CARPET, CREAM, PINK, JAR, LIGHT =
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
      16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31

local function sw(row, n) return row * 8 + n % 8 end
local function hash(x, y, z)
  return (x * 127 + y * 311 + z * 571 + x * y * 7 + y * z * 3) % 97
end
local function glyph(rows, x0, ytop, x, y)
  local row = rows[ytop - y + 1]
  local cx = x - x0 + 1
  return row ~= nil and cx >= 1 and cx <= #row and row:sub(cx, cx)
end

local WALL_H, WALL_D = 28, 5
-- the dollhouse cut: the side walls step down toward the camera
local function sideH(z) return max(6, WALL_H - floor(max(0, z - 12) * 0.2)) end

-- --------------------------------------------------------------- the walls --
-- `u` runs ALONG a wall, whichever wall it is
local function wallSkin(u, y, v)
  if v == 1 then
    if y <= 2 then return sw(DARK, 3) end
    if y <= 12 then return sw(BLUEGREY, u % 5 == 0 and 0 or 3 + floor(u / 5) % 3) end
    if y == 13 then return sw(TRIM, 5) end
    if y >= 26 then return sw(DRIFT, 2) end
    return sw(WHITEWASH, y % 4 == 0 and 1 or 4 + floor(y / 4) % 2)
  elseif v == 2 then
    if y <= 2 then return sw(WALNUT, 2) end
    if y <= 11 then
      if u % 10 == 0 or y == 3 then return sw(GREEN, 0) end
      return sw(GREEN, (u % 10 == 1 or y == 11) and 6 or 3)
    end
    if y == 12 then return sw(BRASS, 3) end
    if y >= 26 then return sw(WALNUT, 3) end
    if u % 8 == 4 and y % 6 == 2 then return sw(OCHRE, 7) end
    return sw(OCHRE, 3 + hash(floor(u / 9), floor(y / 7), 2) % 2)
  end
  if y <= 2 then return sw(OAK, 2) end
  if y <= 10 then return sw(BLUE, u % 6 == 0 and 1 or 4) end
  if y == 11 then return sw(TRIM, 5) end
  if y >= 26 then return sw(TRIM, 3) end
  return sw(BUTTER, u % 6 < 3 and 5 or 4)
end

local TROPHY = { "....ssssss.....", "..ssbbbbbbss..t", ".sbbbbbbbbbbstt", "sebbbbbbbbbbbt.",
                 ".sssssssssssstt", "..ssssssssss..t", "....ssss......." }
local CHART = { "ttttttttttttttt", "ttllttttttttctt", "tlllltttttcccct", "tllllttrtttcttt",
                "ttlllrttrtttttt", "tttlttttttrlltt", "ttttttttttlllct", "tttttttttttlttt" }
local CHART_ROW = { t = TEAL, l = LEAF, r = RED, c = CREAM }

local function picture(x, y, v)
  local frame = x == 79 or x == 95 or y == 12 or y == 23
  if v == 1 then            -- the one that did not get away, on a walnut plaque
    local d = ((x - 87) / 8.5) ^ 2 + ((y - 17.5) / 5.8) ^ 2
    if d > 1 then return nil end
    local c = glyph(TROPHY, 80, 21, x, y)
    if c == "s" then return sw(FISH, 3 + (x + y) % 3) end
    if c == "b" then return sw(FISHBLUE, 3 + x % 2) end
    if c == "t" then return sw(FISHBLUE, 1) end
    if c == "e" then return sw(DARK, 1) end
    return sw(WALNUT, d > 0.8 and 1 or 4)
  elseif v == 2 then        -- a sea chart: two coasts, a run between them
    if frame then return sw(WALNUT, 2) end
    local c = glyph(CHART, 80, 21, x, y)
    if c and CHART_ROW[c] then return sw(CHART_ROW[c], c == "t" and 5 + (x + y) % 2 or 4) end
    return sw(PAPER, 4)
  end
  if frame then return sw(OAK, 3) end                       -- a great envelope, sealed
  local fx, fy = x - 87, 22 - y
  if abs(fx) <= 1 and y >= 16 and y <= 18 then return sw(RED, 3) end
  if fy == floor(abs(fx) * 0.8) or fy == floor(abs(fx) * 0.8) + 1 then return sw(STRAW, 2) end
  if x >= 91 and y >= 19 then return sw(NAVY, 4 + (x + y) % 2) end
  return sw(CREAM, 5)
end

local function northWall(x, y, z, v)
  local wood = v == 1 and DRIFT or (v == 2 and WALNUT or TRIM)
  -- the window: a real recess, glass three voxels back, sill and frame
  if x >= 49 and x <= 62 and y >= 9 and y <= 24 then
    local ring = x == 49 or x == 62 or y == 9 or y == 24
    if ring then
      if z <= 10 then return sw(wood, 4) end
    elseif z >= 7 then
      if z <= 10 then return nil end
    elseif z == 6 then
      if x == 55 or x == 56 or y == 16 or y == 17 then return sw(wood, 4) end
      return sw(SKY, 6 - floor((24 - y) / 4))
    end
  end
  if y == 8 and x >= 48 and x <= 63 and z >= 10 and z <= 12 then return sw(wood, 5) end
  if z == 10 or z == 11 then
    if v == 1 then          -- a net swagged across it, its floats hanging
      if x >= 43 and x <= 68 then
        local sag = 25 - floor(3 * (1 - ((x - 55.5) / 12.5) ^ 2))
        if z == 11 and y <= sag and y >= sag - 5 then
          if y == sag then return sw(ROPE, 3) end
          if y == sag - 5 then return (x % 5 == 0) and sw(ORANGE, 4) or nil end
          if (x + y) % 3 == 0 or (x - y) % 3 == 0 then return sw(NET, 4) end
        end
      end
    elseif v == 2 then      -- red curtains tied back on a brass rod
      if y == 25 and z == 11 and x >= 44 and x <= 67 then return sw(BRASS, 4) end
      if y >= 7 and y <= 24 and ((x >= 44 and x <= 48) or (x >= 63 and x <= 67)) then
        if y == 14 then return sw(BRASS, 5) end
        if y < 14 and (x == 44 or x == 67) then return nil end
        return sw(CARPET, 2 + x % 2 * 3)
      end
    else                    -- gingham, tied back
      if y == 25 and z == 11 and x >= 44 and x <= 67 then return sw(OAK, 4) end
      if y >= 7 and y <= 24 and ((x >= 44 and x <= 48) or (x >= 63 and x <= 67)) then
        if y == 14 then return sw(PINK, 4) end
        if y < 14 and (x == 44 or x == 67) then return nil end
        return sw(((x + floor(y / 2)) % 2 == 0) and BLUE or TRIM, 5)
      end
    end
    -- a lamp either side of the table's axis
    if (x == 38 or x == 39 or x == 104 or x == 105) and y >= 16 and y <= 21 then
      if y == 16 or y == 21 then return sw(v == 1 and IRON or BRASS, 3) end
      return sw(LIGHT, 5)
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

-- --------------------------------------------------------------- the cases --
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

local TIN = { RED, TEAL, YELLOW, NAVY, ORANGE }
local function tackle(ux, s, hy, dz)
  if dz < 4 or dz > 16 then return nil end
  if s == 0 then                                   -- tackle boxes
    local b = floor((ux - 1) / 7)
    if (ux - 1) % 7 >= 6 or hy >= 4 then return nil end
    if hy == 2 then return sw(IRON, 4) end
    return sw(b == 0 and RED or TEAL, 3 + hy)
  elseif s == 1 then                               -- bait in jars
    if (ux - 1) % 4 == 3 or hy >= 4 then return nil end
    if hy == 3 then return sw(BRASS, 3) end
    return sw(JAR, 2 + (floor((ux - 1) / 4) + hy) % 4)
  end
  if hy >= 2 or (ux - 1) % 3 == 2 then return nil end   -- floats and spools
  return sw(hy == 1 and TRIM or TIN[floor((ux - 1) / 3) % 5 + 1], 4)
end
local function rodRack(ux, y, dz)
  if y > 26 then return nil end
  if dz <= 1 then return sw(DRIFT, 2 + floor(ux / 4) % 3) end               -- the back board
  if (y == 6 or y == 19) and dz >= 3 and dz <= 8 then return sw(DRIFT, 5) end  -- its two rails
  if y <= 1 then return dz <= 10 and sw(DRIFT, 1) or nil end
  if (dz == 5 or dz == 6) and ux % 3 == 1 and ux <= 13 then
    local top = 20 + hash(ux, 0, 1) % 7
    if y > top then return nil end
    if y >= 7 and y <= 9 and dz == 6 then return sw(BRASS, 3 + ux % 2) end     -- the reel
    if y <= 6 then return sw(STRAW, 3) end                                  -- a cork grip
    return sw(y == top and RED or WALNUT, 4)
  end
  return nil
end
local function locker(ux, s, hy, dz)
  if dz < 4 or dz > 16 then return nil end
  if s == 0 then                                   -- rope, coiled
    local d = (ux - 7.5) ^ 2 + (dz - 10) ^ 2
    return (hy <= 3 and d <= 36 and d >= 6) and sw(ROPE, 2 + hy % 2 * 3) or nil
  elseif s == 1 then                               -- nets, folded
    if hy >= 4 then return nil end
    return ((ux + dz) % 3 == 0 or hy == 3) and sw(NET, 3) or sw(NET, 6)
  elseif s == 2 then                               -- a storm lantern, two floats
    if ux >= 3 and ux <= 6 and dz >= 8 and dz <= 11 then
      if hy == 0 or hy == 4 then return sw(IRON, 3) end
      return hy <= 3 and sw(LIGHT, 4) or nil
    end
    local d = (ux - 11) ^ 2 + (dz - 10) ^ 2 + (hy - 2) ^ 2
    return d <= 6 and sw(ORANGE, 3 + hy % 2) or nil
  end
  return nil
end

local function cloth(ux, s, hy, dz)
  if dz < 3 or dz > 16 then return nil end
  if s == 0 or s == 2 then                         -- bolts of cloth, end on
    local c = (ux - 1) % 5
    if c == 4 or hy >= 5 then return nil end
    local d = (c - 1.5) ^ 2 + (hy - 2) ^ 2
    if d > 5 then return nil end
    return sw(TIN[(floor((ux - 1) / 5) + s) % 5 + 1], d < 1 and 1 or 4)
  elseif s == 1 then                               -- tins
    if (ux - 1) % 3 == 2 or hy >= 3 + floor(ux / 3) % 2 then return nil end
    return sw(hy == 1 and CREAM or TIN[floor((ux - 1) / 3) % 5 + 1], 4)
  end
  if (ux - 1) % 7 >= 6 or hy >= 4 then return nil end       -- boxes, labelled
  return sw((hy == 2 and (ux - 1) % 7 >= 2 and (ux - 1) % 7 <= 3) and RED or CREAM, 3 + hy % 2)
end
local function sundries(ux, s, hy, dz)
  if dz < 3 or dz > 16 then return nil end
  if s == 0 then                                   -- sacks
    local c = (ux - 1) % 7
    if c == 6 or hy >= 5 then return nil end
    if hy == 4 then return (c >= 2 and c <= 3) and sw(ROPE, 3) or nil end
    return sw(STRAW, 3 + (c + hy) % 3)
  elseif s == 1 then                               -- blue and white china
    if (ux - 1) % 4 == 3 or hy >= 4 then return nil end
    return sw((hy + floor(ux / 4)) % 2 == 0 and NAVY or TRIM, 4)
  elseif s == 2 then                               -- bottles
    if (ux - 1) % 3 ~= 0 or hy >= 5 then return nil end
    return sw(hy == 4 and BRASS or JAR, 3 + hy % 2)
  end
  return cloth(ux, 1, hy, dz)
end
local function strongbox(ux, y, dz)
  if y <= 12 then                                  -- iron-bound, a brass lock
    if dz > 18 then return nil end
    if dz == 18 and ux >= 7 and ux <= 8 and y >= 6 and y <= 8 then return sw(BRASS, 5) end
    if ux % 5 == 0 or y == 0 or y == 12 or y == 6 then return sw(IRON, 3) end
    return sw(WALNUT, 3 + (ux + y) % 2)
  end
  if y <= 19 then                                  -- the ledgers, standing on it
    if dz < 4 or dz > 14 or ux == 0 or ux == 15 then return nil end
    if y == 19 and hash(floor(ux / 2), 0, 3) % 3 == 0 then return nil end
    if y == 16 and dz == 14 then return sw(BRASS, 4) end
    return sw(floor(ux / 2) % 2 == 0 and CARPET or GREEN, 2 + hash(floor(ux / 2), 1, 1) % 4)
  end
  local cx = ux - 7.5                              -- and the scales on top of them
  if dz < 8 or dz > 10 then return nil end
  if y == 20 then return abs(cx) <= 3 and sw(BRASS, 3) or nil end
  if abs(cx) < 1 and y <= 26 then return sw(BRASS, 4) end
  if y == 26 and abs(cx) <= 6 then return sw(BRASS, 5) end
  if (abs(cx) >= 5 and abs(cx) <= 6) and y >= 23 then return sw(BRASS, 2) end
  if y == 22 and abs(cx) >= 4 and abs(cx) <= 7 then return sw(BRASS, 5) end
  return nil
end

local function pigeonholes(unit)
  return function(ux, y, dz)
    if y > 26 then return nil end
    if dz <= 1 or y == 26 or ux == 0 or ux == 15 then return sw(OAK, 3) end
    if y <= 1 then return dz <= 18 and sw(DARK, 2) or nil end
    if (y - 2) % 6 == 0 or ux % 5 == 0 then return dz <= 18 and sw(OAK, 5) or nil end
    if dz < 4 or dz > 17 then return nil end
    local s, hy, hole = floor((y - 3) / 6), (y - 3) % 6, floor(ux / 5)
    local h = hash(hole, s, unit)
    if unit == 1 and s == 0 then                   -- parcels in brown paper and string
      if hy >= 4 then return nil end
      return sw((hy == 2 or ux % 5 == 2) and ROPE or STRAW, 4)
    end
    if h % 5 == 0 then return nil end              -- an empty hole
    if hy > h % 4 then return nil end              -- letters, lying in a stack
    if dz == 17 and h % 3 == 0 then return sw(hy % 2 == 0 and RED or NAVY, 4) end   -- by air
    return sw(hy % 2 == 0 and PAPER or CREAM, 4 + h % 2)
  end
end
local function dovecote(ux, y, dz)
  if y > 27 then return nil end
  if y >= 23 then                                  -- its own little tiled roof
    local rise = y - 23
    if abs(ux - 7.5) > 8 - rise * 1.6 then return nil end
    return sw(ORANGE, 2 + (ux + y) % 3)
  end
  if dz > 18 then
    if (y == 4 or y == 11 or y == 18) and (ux == 4 or ux == 11) then return sw(OAK, 3) end  -- perches
    return nil
  end
  if y <= 1 then return sw(OAK, 2) end
  local s, hy = floor((y - 2) / 7), (y - 2) % 7
  local cx = (ux < 8) and 3.5 or 11.5
  local hole = abs(ux - cx) <= 2 and hy >= 2 and hy <= 5 and (hy <= 4 or abs(ux - cx) <= 1)
  if hole and dz >= 8 then
    if hy == 2 then return sw(STRAW, 3 + ux % 2) end          -- the nest
    if s == 1 and ux > 8 and dz <= 15 then                    -- somebody is home
      if hy == 5 then return nil end
      if dz == 15 and hy == 4 and abs(ux - cx) < 1 then return sw(ORANGE, 5) end
      return sw(TRIM, 5)
    end
    return dz == 8 and sw(DARK, 1) or nil
  end
  return sw(TRIM, 3 + (hy == 0 and 0 or 2))
end

local function westCases(x, y, z, v)
  local unit, ux, dz = floor(x / 16), x % 16, z - 10
  if v == 1 then
    if unit == 0 then return rodRack(ux, y, dz) end
    return case(ux, y, dz, 20, DRIFT, tackle)
  elseif v == 2 then
    return case(ux, y, dz, 26, WALNUT, unit == 0 and cloth or sundries)
  end
  return pigeonholes(unit)(ux, y, dz)
end

local function eastCase(x, y, z, v)
  local ux, dz = x - 112, z - 10
  if v == 1 then
    if y >= 21 then                                -- a sou'wester left on top
      local d = (ux - 7.5) ^ 2 + (dz - 9) ^ 2
      if y == 21 then return d <= 40 and sw(YELLOW, 3) or nil end
      return (y <= 24 and d <= 14 - (y - 22) * 4) and sw(YELLOW, 5) or nil
    end
    return case(ux, y, dz, 20, DRIFT, locker)
  elseif v == 2 then
    return strongbox(ux, y, dz)
  end
  return dovecote(ux, y, dz)
end

-- --------------------------------------------------------------- the table --
local function disk(tx, tz, cx, cz, r) return (tx - cx) ^ 2 + (tz - cz) ^ 2 <= r * r end

local CATCH = { "..ssssss...t", ".sbbbbbbs.tt", "sebbbbbbbst.", ".sssssssstt.", "..ssssss..t." }
local function trestle(tx, y, tz)
  if y <= 7 then                                   -- two trestles, a stretcher
    local leg = (tx >= 4 and tx <= 6) or (tx >= 25 and tx <= 27)
    if leg and (tz <= 4 + floor(y / 2) and tz >= 2 + floor(y / 2) or tz >= 27 - floor(y / 2) and tz <= 29 - floor(y / 2)) then
      return sw(DRIFT, 2)
    end
    if y == 4 and tx >= 6 and tx <= 25 and tz >= 15 and tz <= 16 then return sw(DRIFT, 3) end
    return nil
  end
  if y <= 9 then return sw(DRIFT, tz % 6 == 0 and 1 or 4 + floor(tz / 6) % 3) end
  -- the catch on its board, the knife beside it
  if tx >= 3 and tx <= 16 and tz >= 17 and tz <= 25 then
    if y == 10 then return sw(OAK, 4 + tx % 2) end
    if y == 11 then
      local c = glyph(CATCH, 4, 23, tx, tz)
      if c == "s" then return sw(FISH, 3 + tx % 3) end
      if c == "b" then return sw(FISHBLUE, 4) end
      if c == "t" then return sw(FISHBLUE, 2) end
      if c == "e" then return sw(DARK, 1) end
    end
    return nil
  end
  if y == 10 and tz == 27 and tx >= 4 and tx <= 13 then return sw(tx <= 7 and WALNUT or IRON, 5) end
  -- the tackle box, open: trays of lures under a lid thrown back
  if tx >= 18 and tx <= 28 and tz >= 4 and tz <= 12 then
    if tz == 4 then return y <= 16 and sw(RED, y == 16 and 1 or 3) or nil end
    if y <= 11 then return sw(RED, 4) end
    if y == 12 then
      if tx == 18 or tx == 28 or tz == 12 then return sw(RED, 2) end
      return sw(TIN[(tx * 3 + tz) % 5 + 1], 5)
    end
    return nil
  end
  if disk(tx, tz, 23.5, 22.5, 2) and y <= 12 then                       -- a mug
    return (y == 12 and disk(tx, tz, 23.5, 22.5, 1)) and sw(WALNUT, 1) or sw(TRIM, 4)
  end
  return nil
end

local function counting(tx, y, tz)
  if y <= 5 then
    local lx, lz = (tx >= 2 and tx <= 4) or (tx >= 27 and tx <= 29), (tz >= 2 and tz <= 4) or (tz >= 27 and tz <= 29)
    return (lx and lz) and sw(WALNUT, 2) or nil
  end
  if y <= 7 then return (tx <= 1 or tx >= 30 or tz <= 1 or tz >= 30) and sw(WALNUT, 3) or nil end
  if y <= 9 then
    local b = min(tx, 31 - tx, tz, 31 - tz)
    if y == 8 or b <= 1 then return sw(WALNUT, 4) end
    return sw(b == 2 and BRASS or BAIZE, 3 + (tx + tz) % 2)
  end
  -- the balance: a pillar, a beam, two pans on their chains, one of them down
  if tz >= 15 and tz <= 16 then
    if tx >= 15 and tx <= 16 and y <= 19 then return sw(BRASS, y == 10 and 2 or 4) end
    if y == 19 and tx >= 6 and tx <= 25 then return sw(BRASS, 5) end
    if (tx == 7 and y >= 14) or (tx == 24 and y >= 16) then return y < 19 and sw(BRASS, 2) or nil end
  end
  if y == 13 and disk(tx, tz, 7.5, 15.5, 3.2) then return sw(BRASS, 4) end
  if y == 15 and disk(tx, tz, 24.5, 15.5, 3.2) then return sw(BRASS, 4) end
  if y == 14 and disk(tx, tz, 7.5, 15.5, 1.6) then return sw(YELLOW, 5) end   -- what it is weighing
  -- coin in stacks, a ledger lying open, two parcels
  for i, c in ipairs({ { 5, 6, 3 }, { 8, 5, 5 }, { 6, 9, 2 }, { 26, 25, 4 }, { 23, 27, 2 } }) do
    if disk(tx, tz, c[1] + 0.5, c[2] + 0.5, 1.3) and y <= 9 + c[3] then
      return sw(YELLOW, (y + i) % 2 == 0 and 3 or 6)
    end
  end
  if tx >= 5 and tx <= 16 and tz >= 22 and tz <= 28 and y == 10 then
    if tx == 10 or tx == 11 then return sw(WALNUT, 2) end
    return sw(PAPER, (tz % 2 == 0 and tx % 6 ~= 5) and 2 or 6)
  end
  for _, b in ipairs({ { 20, 4, RED }, { 25, 8, NAVY } }) do
    if tx >= b[1] and tx <= b[1] + 4 and tz >= b[2] and tz <= b[2] + 4 and y <= 13 then
      if tx == b[1] + 2 or tz == b[2] + 2 then return sw(CREAM, 5) end
      return sw(b[3], 3 + y % 2)
    end
  end
  return nil
end

local function writing(tx, y, tz)
  if y <= 5 then                                   -- turned legs
    local lx, lz = (tx >= 3 and tx <= 5) or (tx >= 26 and tx <= 28), (tz >= 3 and tz <= 5) or (tz >= 26 and tz <= 28)
    if not (lx and lz) then return nil end
    return sw(OAK, (y == 2 or y == 4) and 6 or 2)
  end
  if y <= 7 then return (tx >= 2 and tx <= 29 and tz >= 2 and tz <= 29 and (tx <= 3 or tx >= 28 or tz <= 3 or tz >= 28)) and sw(OAK, 3) or nil end
  if y <= 9 then
    if y == 9 and tz >= 13 and tz <= 18 then return sw(BLUE, (tz == 13 or tz == 18) and 6 or 3 + tx % 2) end   -- a runner
    return sw(OAK, 4 + floor(tx / 8) % 3)
  end
  -- (the north-east quarter stays bare: that is where the LETTER lies)
  if tx >= 16 and tz <= 15 then return nil end
  if y == 10 then
    for i, r in ipairs({ { 3, 4, 8, 5 }, { 6, 7, 8, 5 }, { 4, 21, 9, 6 }, { 19, 22, 8, 5 } }) do   -- the post
      if tx >= r[1] and tx < r[1] + r[3] and tz >= r[2] and tz < r[2] + r[4] then
        if i == 3 and abs(tx - 8) <= 1 and abs(tz - 24) <= 1 then return sw(RED, 3) end    -- sealed
        if i == 4 and tx >= 25 and tz <= 23 then return sw(NAVY, 5) end                    -- stamped
        return sw(i % 2 == 0 and CREAM or PAPER, 5 + (tx + tz) % 2)
      end
    end
  end
  if disk(tx, tz, 12.5, 12.5, 1.6) and y <= 12 then return sw(y == 12 and BRASS or NAVY, 3) end   -- ink
  if tz == 12 and tx == 13 + (y - 12) and y >= 13 and y <= 18 then return sw(TRIM, 5) end          -- and the quill in it
  if tx >= 20 and tx <= 27 and tz >= 25 and tz <= 29 and y <= 13 then                              -- a parcel, tied
    return sw((tx == 23 or tz == 27) and ROPE or STRAW, 4)
  end
  return nil
end

-- --------------------------------------------------------------- the seats --
local function stools(x, y, z, v)
  if z < 48 or z > 79 then return nil end
  local west = x >= 32 and x <= 47
  if not west and not (x >= 80 and x <= 95) then return nil end
  local dx = x - (west and 39.5 or 87.5)
  local dz = z - (z <= 63 and 55.5 or 71.5)
  local d = dx * dx + dz * dz
  if v == 1 then            -- half a barrel, upturned
    if y > 7 or d > 27 then return nil end
    if y == 7 then return sw(OAK, 4 + floor(dx + 8) % 2) end
    if d < 16 then return sw(DARK, 2) end
    return sw((y == 1 or y == 5) and IRON or DRIFT, 2 + floor(dx + dz + 16) % 3)
  elseif v == 2 then        -- a studded stool in green baize
    if y <= 5 then return (abs(abs(dx) - 3) < 1 and abs(abs(dz) - 3) < 1) and sw(WALNUT, 2) or nil end
    if y == 6 then return d <= 27 and sw(d > 19 and BRASS or WALNUT, 4) or nil end
    if y == 7 then return d <= 23 and sw(BAIZE, 3 + hash(x, 0, z) % 2) or nil end
    return nil
  end
  if y <= 5 then return (abs(abs(dx) - 3) < 1 and abs(abs(dz) - 3) < 1) and sw(BLUE, 2) or nil end   -- painted blue
  if y == 6 then return (abs(dx) <= 4.5 and abs(dz) <= 4.5) and sw(BLUE, 5) or nil end
  if y == 7 then return d <= 16 and sw(CREAM, 4 + hash(x, 0, z) % 2) or nil end
  return nil
end

-- ------------------------------------------------------ either side the door --
local function corner(x, y, z, v)
  local east = x >= 112
  local px, pz = x - (east and 119.5 or 7.5), z - 119.5
  local d = px * px + pz * pz
  if v == 1 then
    if not east then                               -- rope in a coil, a glass float on it
      if y <= 6 then return (d <= 42 and d >= 9 - y) and sw(ROPE, 2 + (y + floor(d / 6)) % 3) or nil end
      local s = d + (y - 10) * (y - 10)
      if s <= 12 then return sw(((px + y) % 3 == 0) and NET or TEAL, 4) end
      return nil
    end
    if y <= 12 then                                -- a barrel of floats
      if d > 36 then return nil end
      if y == 12 and d < 25 then return nil end
      if d < 25 and y > 1 then return sw(DARK, 1) end
      return sw((y == 2 or y == 10) and IRON or DRIFT, 2 + floor(px + pz + 16) % 3)
    end
    for i, f in ipairs({ { -2, -1, 13, 3 }, { 2, 1, 14, 3 }, { 0, -2, 17, 2.4 } }) do
      if (px - f[1]) ^ 2 + (pz - f[2]) ^ 2 + (y - f[3]) ^ 2 <= f[4] * f[4] then
        return sw(i == 2 and ORANGE or TEAL, 3 + y % 3)
      end
    end
    return nil
  elseif v == 2 then
    if not east then                               -- crates, a sack thrown on them
      local hi = (pz <= 1) and 16 or 9
      if abs(px) > 6 or abs(pz) > 6 or y > hi + 3 then return nil end
      if y <= hi then
        local rim = abs(px) > 5 or y == 0 or y == hi or y == 9 or (pz <= 1 and abs(pz - 1) < 1)
        return sw(rim and WALNUT or OAK, 3 + floor(px + y + 8) % 2)
      end
      if pz <= 1 and abs(px) <= 4 and pz >= -5 then return sw(STRAW, 3 + y % 2) end
      return nil
    end
    if y <= 7 then                                 -- a fig in a brass-banded planter
      if abs(px) > 5 or abs(pz) > 5 then return nil end
      if y == 7 and abs(px) <= 4 and abs(pz) <= 4 then return sw(DARK, 2) end
      return sw((y == 1 or y == 6) and BRASS or WALNUT, 3)
    end
    if d <= 1 and y <= 14 then return sw(WALNUT, 2) end
    local b = d / 40 + (y - 19) * (y - 19) / 46
    if b <= 1 and hash(floor(px + 8), y, floor(pz + 8)) % 6 ~= 0 then
      return sw(LEAF, 2 + hash(floor(px + 8), y, floor(pz + 8)) % 5)
    end
    return nil
  end
  if not east then                                 -- a perch, and who is on it
    if y <= 1 then return d <= 30 and sw(OAK, 3) or nil end
    if d <= 1 and y <= 20 then return sw(OAK, 4) end
    if y == 20 and abs(pz) < 1 and abs(px) <= 6 then return sw(OAK, 5) end
    if y == 8 and d <= 9 then return sw(d <= 4 and YELLOW or BRASS, 4) end          -- the seed dish
    local bx = px - 3.5
    if abs(pz) <= 1 and y >= 21 and y <= 24 and abs(bx) <= 2 then                   -- a pigeon
      if y == 24 then return (bx >= 0) and sw(TRIM, 5) or nil end
      if y == 23 and bx > 1.5 then return sw(ORANGE, 5) end
      return sw((y == 22 and bx < 0) and FISH or TRIM, 4)
    end
    return nil
  end
  if y <= 11 then                                  -- a sack of seed, its mouth rolled down
    local r = 6 - abs(y - 5) * 0.35
    if d > r * r then return nil end
    if y == 11 then return sw(d <= 9 and YELLOW or STRAW, d <= 9 and 3 + floor(px + pz + 8) % 3 or 6) end
    return sw(STRAW, 2 + floor(px + y + 8) % 3)
  end
  if y <= 14 and abs(px - 1) <= 1 and abs(pz) < 1 then return sw(BRASS, 4) end     -- the scoop
  return nil
end

-- ----------------------------------------------------------------- the rug --
-- One voxel thick on the open floor. Its cells are NOT claimed: the mesher
-- keeps painting the floor under it (lib/LavenderHomeKit.lua says why).
local function rug(x, z, v)
  local dx, dz = x - 63.5, z - 63.5
  if v == 1 then            -- a rag rug, oval, in the colours of old shirts
    local e = (dx / 46) ^ 2 + (dz / 30) ^ 2
    if e > 1 then return nil end
    if e > 0.9 then return sw(ROPE, 3) end
    return sw(({ NAVY, TRIM, TEAL, TRIM, BLUEGREY })[floor(z / 3) % 5 + 1], 3 + hash(x, 0, floor(z / 3)) % 3)
  elseif v == 2 then        -- a red carpet: a border, a field, a medallion
    if x < 20 or x > 107 or z < 38 or z > 89 then return nil end
    local b = min(x - 20, 107 - x, z - 38, 89 - z)
    if b <= 3 then return sw(b == 2 and BRASS or CREAM, 3) end
    local m = abs(dx) / 1.6 + abs(dz)
    if m <= 12 then return sw(m <= 5 and CREAM or NAVY, 3) end
    if (abs(dx) + abs(dz)) % 10 < 2 then return sw(CREAM, 2) end
    return sw(CARPET, 3 + hash(x, 0, z) % 2)
  end
  local d = dx * dx + dz * dz   -- braided, round
  if d > 38 * 38 then return nil end
  return sw(({ BLUE, CREAM, TEAL, CREAM })[floor(d ^ 0.5 / 5) % 4 + 1], 4 + hash(x, 0, z) % 2)
end

-- --------------------------------------------------------------- the floor --
-- The tileset's floor is one white tile for every house in Kanto, so each
-- home lays its own boards over it, one voxel thick. The doormat's cells
-- are left open: the drawn mat shows through, set into the boards.
local function boards(x, z, v)
  if z >= 112 and x >= 32 and x <= 63 then return nil end
  if v == 1 then            -- grey boards, east to west, a gap between each
    local row = floor(z / 5)
    local run = x + row * 13
    if z % 5 == 0 or run % 28 == 0 then return sw(DARK, 5) end
    return sw(DRIFT, 3 + hash(floor(run / 28), row, 1) % 4)
  elseif v == 2 then        -- oak laid in chevrons
    local band = floor(x / 16)
    local k = (band % 2 == 0) and (z + x) or (z - x)
    if x % 16 == 0 or k % 6 == 0 then return sw(WALNUT, 4) end
    return sw(OAK, 2 + hash(band, floor(k / 6), 2) % 3)
  end
  local col = floor(x / 5)  -- honey boards, north to south; a feather or two
  local run = z + col * 11
  if x % 5 == 0 or run % 26 == 0 then return sw(OAK, 1) end
  if hash(x, 3, z) == 0 and (x + z) % 5 == 0 and z > 36 then return sw(TRIM, 6) end
  return sw(OAK, 5 + hash(col, floor(run / 26), 3) % 3)
end

-- ---------------------------------------------------------------- the room --
local TABLE = { trestle, counting, writing }

local function furniture(x, y, z, v)
  if z <= 11 then
    local w = northWall(x, y, z, v)
    if w or z <= 9 or not (x <= 31 or x >= 112) then return w end
  end
  if z >= 10 and z <= 30 then
    if x <= 31 then return westCases(x, y, z, v) end
    if x >= 112 then return eastCase(x, y, z, v) end
  end
  if x >= 48 and x <= 79 and z >= 48 and z <= 79 then return TABLE[v](x - 48, y, z - 48) end
  if z >= 108 and (x <= 15 or x >= 112) then return corner(x, y, z, v) end
  return nil
end

local function roomFor(v)
  return function(x, y, z)
    if x < 0 or x > 127 then                         -- side walls, outside
      if y > sideH(z) or z < 0 then return nil end
      return wallSkin(z + 5, y, v)
    end
    local hit = furniture(x, y, z, v)
    if hit or y > 0 or z <= 9 then return hit or nil end
    return rug(x, z, v) or boards(x, z, v)
  end
end

-- ------------------------------------------------------------ the FAN CLUB --
-- Another plan altogether (the INTERIOR tileset; tools/interior_plan.py
-- POKEMON_FAN_CLUB): a sideboard against the north wall between two pictures,
-- an eight-sided table filling the middle of the room, a couch down either
-- side of it -- whose cells are WALKABLE, the fans and their pets sit there,
-- so the couches are their own templates with a standH, as the stools are.
-- The inside of the house with the vermilion mansard and the bunting: red
-- panelling under cream, a banner and two prize rosettes, a sideboard of
-- cups, tea laid on a lace cloth round the biggest cup of all, pink velvet.
-- (The tileset draws a statue on the table. A cup stands there instead: no
-- Nintendo design is redrawn here -- assets/buildings/LICENSE.md.)
local LETTERS = {
  { "XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "X...." },   -- F
  { ".XXX.", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X" },   -- A
  { "X...X", "XX..X", "X.X.X", "X.X.X", "X..XX", "X...X", "X...X" },   -- N
}
local PENNANT = { RED, YELLOW, BLUE, TRIM, TEAL }

local function clubSkin(u, y)
  if y <= 2 then return sw(WALNUT, 2) end
  if y <= 11 then
    if u % 10 == 0 or y == 3 then return sw(RED, 0) end
    return sw(RED, (u % 10 == 1 or y == 11) and 6 or 3)
  end
  if y == 12 then return sw(BRASS, 3) end
  if y >= 26 then return sw(TRIM, 3) end
  return sw(u % 6 == 0 and PINK or CREAM, u % 6 == 0 and 6 or 5)
end

-- a prize rosette in a brass frame: x0 is the frame's west edge
local function rosette(x, y, x0, colour)
  if x < x0 or x > x0 + 15 or y < 8 or y > 21 then return nil end
  if x == x0 or x == x0 + 15 or y == 8 or y == 21 then return sw(BRASS, 4) end
  local dx, dy = x - x0 - 7.5, y - 16
  local d = dx * dx + dy * dy
  if d <= 3 then return sw(YELLOW, 5) end
  if d <= 18 then return sw((floor(dx) + floor(dy)) % 2 == 0 and colour or TRIM, 4) end
  if y <= 13 and y >= 9 and (abs(dx + 2) < 1.2 or abs(dx - 2) < 1.2) then return sw(colour, 2) end  -- its tails
  return sw(NAVY, 3)
end

local function cup(dx, dz, y, y0, h)                 -- a loving cup, `h` tall, standing on y0
  local d = dx * dx + dz * dz
  local k = y - y0
  if k < 0 or k > h then return nil end
  if k == 0 then return d <= 5 and sw(WALNUT, 3) or nil end
  if k <= 2 then return d <= 1.2 and sw(YELLOW, 3) or nil end
  local r = 1.4 + (k - 2) * 0.3
  if d <= r * r then return sw(YELLOW, k == h and 7 or 4 + k % 2) end
  if abs(dz) < 1 and k >= h - 2 and k < h and abs(abs(dx) - r - 0.8) < 0.9 then return sw(YELLOW, 3) end  -- handles
  return nil
end

local function clubNorth(x, y, z)
  if z <= 9 then return clubSkin(x + 5, y) end
  -- the sideboard: walnut, brass pulls, a runner, three cups
  if x >= 40 and x <= 71 and z <= 19 then
    if y <= 9 then
      if z == 19 and y >= 3 and y <= 7 and (x - 40) % 11 == 5 then return sw(BRASS, 5) end
      if (x - 40) % 11 == 0 or y == 9 or y <= 1 then return sw(WALNUT, 2) end
      return sw(WALNUT, 4 + (floor((x - 40) / 11) + y) % 2)
    end
    if y == 10 then return (z >= 12 and z <= 17) and sw(CREAM, 5 + x % 2) or nil end
    for _, c in ipairs({ { 46, 5 }, { 55.5, 6 }, { 65, 5 } }) do
      local v = cup(x - c[1], z - 14.5, y, 11, c[2])
      if v then return v end
    end
  end
  if z == 10 then
    if y >= 26 or y <= 2 then return clubSkin(x + 5, y) end       -- cornice and skirting, proud
    -- FAN, in cream on a vermilion board
    if x >= 43 and x <= 68 and y >= 15 and y <= 25 then
      if x == 43 or x == 68 or y == 15 or y == 25 then return sw(BRASS, 4) end
      local i = floor((x - 46) / 7)
      local lx = (x - 46) % 7
      if x >= 46 and i <= 2 and lx <= 4 and y >= 17 and y <= 23
         and LETTERS[i + 1][23 - y + 1]:sub(lx + 1, lx + 1) == "X" then
        return sw(CREAM, 6)
      end
      return sw(RED, 4)
    end
    local r = rosette(x, y, 16, RED) or rosette(x, y, 96, BLUE)
    if r then return r end
    if (x == 35 or x == 36 or x == 91 or x == 92) and y >= 14 and y <= 19 then
      return (y == 14 or y == 19) and sw(BRASS, 3) or sw(LIGHT, 5)
    end
  end
  if z == 11 and not (x >= 40 and x <= 71) then                   -- bunting under the cornice
    local lx = x % 32
    local line = 25 - floor(2 * (1 - ((lx - 15.5) / 15.5) ^ 2))
    if y == line then return sw(ROPE, 3) end
    local k = x % 5
    if y < line and y >= line - 3 + abs(k - 2) and k ~= 0 then
      return sw(PENNANT[floor(x / 5) % #PENNANT + 1], 4)
    end
  end
  return nil
end

-- the table: eight-sided, x 32..95 by z 32..79, on a panelled pedestal
local function clubTable(x, y, z)
  local dx, dz = abs(x - 63.5), abs(z - 55.5)
  -- (the corner tiles are cut from (16, 24) to (32, 8) off the middle: dx + dz = 40)
  if dx > 32 or dz > 24 or dx + dz > 40 then return nil end
  local inset = min(32 - dx, 24 - dz, (40 - dx - dz) * 0.7)
  if y <= 7 then
    if dx <= 16 and dz <= 12 then                                 -- the pedestal
      return sw(WALNUT, (floor(x / 8) + floor(z / 8)) % 2 == 0 and 3 or 4)
    end
    return (y >= 6 and inset >= 2 and inset < 4) and sw(WALNUT, 2) or nil
  end
  if y <= 9 then
    if inset < 2 then return sw(WALNUT, 4) end
    if y == 8 then return sw(WALNUT, 3) end
    if inset < 4 then return sw(PINK, 3 + (x + z) % 2) end        -- the cloth's scalloped hem
    return sw(TRIM, ((x + z) % 4 == 0) and 3 or 6)                -- lace
  end
  local v = cup(x - 63.5, z - 52.5, y, 10, 11)                    -- the cup everybody comes to see
  if v then return v end
  for _, c in ipairs({ { 40, 48 }, { 40, 64 }, { 87, 48 }, { 87, 64 } }) do    -- tea for four
    local d = (x - c[1]) ^ 2 + (z - c[2]) ^ 2
    if y == 10 and d <= 6 then return sw(TRIM, d > 3.5 and 3 or 6) end
    if y <= 12 and d <= 2 then return sw(y == 12 and ORANGE or TRIM, y == 12 and 2 or 5) end
  end
  local kx, kz = x - 63.5, z - 69.5                               -- a cake on its stand
  local kd = kx * kx + kz * kz
  if y <= 11 then return kd <= 1.5 and sw(TRIM, 4) or nil end
  if y == 12 then return kd <= 20 and sw(TRIM, 6) or nil end
  if y <= 15 then return kd <= 11 and sw(y == 15 and TRIM or PINK, 5) or nil end
  if y == 16 and kd <= 1 then return sw(RED, 4) end
  return nil
end

-- a couch: x0 its west edge, z 48..79; the back stands on the side away from the table
local function couch(x, y, z)
  if z < 48 or z > 79 then return nil end
  local west = x >= 16 and x <= 31
  if not west and not (x >= 96 and x <= 111) then return nil end
  local lx = west and (x - 16) or (111 - x)                       -- 0 at the back, 15 at the front
  local lz = z - 48
  if y <= 1 then                                                  -- brass feet
    return ((lx <= 1 or lx >= 14) and (lz <= 1 or lz >= 30)) and sw(BRASS, 3) or nil
  end
  local arm = lz <= 1 or lz >= 30
  if y <= 7 then
    if lx <= 2 or arm or lx == 15 then return sw(PINK, 2) end
    if y == 7 then return sw(PINK, ((lx % 5 == 3) and (lz % 6 == 3)) and 0 or 5 + (lx + lz) % 2) end  -- buttoned
    return sw(PINK, 3)
  end
  if arm then return y <= 10 and sw(y == 10 and WALNUT or PINK, 3) or nil end
  if lx <= 2 then
    if y > 15 then return nil end
    return sw(y == 15 and WALNUT or PINK, (lz % 8 == 0) and 1 or 4)
  end
  -- a cushion at either end, clear of where anybody sits
  if lx >= 3 and lx <= 6 and y <= 10 and (lz <= 5 or lz >= 26) then return sw(CREAM, 4 + (lx + y) % 2) end
  return nil
end

local function clubFloor(x, z)
  if z >= 112 and x >= 32 and x <= 63 then return nil end         -- the drawn mat shows through
  if x >= 20 and x <= 107 and z >= 26 and z <= 96 then            -- the carpet the table stands on
    local b = min(x - 20, 107 - x, z - 26, 96 - z)
    if b <= 1 then return sw(CREAM, 3 + (x + z) % 2) end
    if b == 3 or b == 4 then return sw(BRASS, 3) end
    if (abs(x - 63.5) + abs(z - 61)) % 14 < 2 then return sw(CARPET, 1) end
    return sw(RED, 2 + hash(x, 0, z) % 2)
  end
  local cx, cz = x % 8, z % 8                                     -- cream tiles, a pink diamond where four meet
  if abs(cx - 3.5) + abs(cz - 3.5) >= 7 then return sw(PINK, 5) end
  if cx == 0 or cz == 0 then return sw(STRAW, 5) end
  return sw(CREAM, (floor(x / 8) + floor(z / 8)) % 2 == 0 and 6 or 4)
end

local function clubRoom(x, y, z)
  if x < 0 or x > 127 then                                         -- side walls, outside
    if y > sideH(z) or z < 0 then return nil end
    return clubSkin(z + 5, y)
  end
  local hit = nil
  if z <= 19 then hit = clubNorth(x, y, z) end
  if not hit and y > 0 and z >= 32 and z <= 79 then hit = clubTable(x, y, z) end
  if hit or y > 0 or z <= 9 then return hit or nil end
  return clubFloor(x, z)
end

local CLUB_FLOOR = { [31] = true, [70] = true, [71] = true }
local CLUB_COUCH = { [59] = true, [60] = true, [61] = true, [62] = true }

local function clubModel(t)
  local seats = t.home == "couchW" or t.home == "couchE"
  local rows, cols = #t.tiles, #t.tiles[1]
  local mask = {}
  for r = 1, rows do
    for c = 1, cols do
      local id = t.tiles[r][c]
      if seats then mask[(r - 1) * cols + c] = CLUB_COUCH[id] or false
      else mask[(r - 1) * cols + c] = not (CLUB_FLOOR[id] or CLUB_COUCH[id]) end
    end
  end
  if seats then
    -- the template's own corner is tile (2, 6) or (12, 6)
    local x0 = t.home == "couchW" and 16 or 96
    return { at = function(x, y, z) return couch(x + x0, y, z + 48) end,
             W = 16, xmin = 0, xmax = 15, zmin = 0, zmax = 31, ytop = 15,
             standH = Kit.SEAT_H, claimMask = mask, noFigure = true }
  end
  return { at = clubRoom, W = 128, xmin = -WALL_D, xmax = 127 + WALL_D,
           zmin = 0, zmax = 127, ytop = WALL_H + 1,
           standH = 0, claimMask = mask, noFigure = true }
end

local FLOOR = { [1] = true, [4] = true, [20] = true }
local STOOL = { [2] = true, [3] = true, [18] = true, [19] = true }

-- `t.home` is "room", "stoolsW" or "stoolsE"; `mapId` picks who lives here.
function Kit.model(sp, t, mapId)
  local v = Kit.MAPS[mapId]
  if not v then return nil, "not a Vermilion home: " .. tostring(mapId) end
  if not sp or sp.W ~= Kit.SHEET_W or sp.H ~= Kit.SHEET_H then
    return nil, "sheet is not " .. Kit.SHEET_W .. "x" .. Kit.SHEET_H
  end
  -- the Fan Club is its own plan and its own templates (`club`, `couchW/E`)
  local clubT = t.home == "club" or t.home == "couchW" or t.home == "couchE"
  if (v == 4) ~= clubT then return nil, "template " .. tostring(t.home) .. " is not this map's" end
  if v == 4 then return clubModel(t) end
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

Kit.room, Kit.stools = roomFor, stools   -- for tools/vermilion_home.py
Kit.club, Kit.couch = clubRoom, couch

return Kit
