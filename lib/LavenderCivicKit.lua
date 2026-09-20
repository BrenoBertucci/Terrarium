-- Voxel world mode: Lavender's Pokemon Centre and its Mart, OUTSIDE.
--
-- Every Centre in Kanto is one template and every Mart another (data/
-- voxel_heights.lua, `pokecenter` / `pokemart`): a 64x64 plot folded out of
-- the tile drawing into a flat-roofed box. That is right for a city. In
-- Lavender the two of them stand between hand-built stone cottages under
-- violet slate (lib/LavenderHouseKit.lua) and read as two appliances left on
-- a village green. So here, and only here, they are built from nothing in
-- the houses' own language -- coursed limestone, lime plaster in a timber
-- frame, bell-cast slate, stone chimneys that smoke -- and told apart the
-- way a village tells its buildings apart:
--
--   the CENTRE  the town's hospice. A hipped roof under a louvred cupola, an
--               entrance bay with its own gable, a columned porch roofed in
--               RED clay tile, red awnings over arched windows, a bench
--               under them, lavender in stone troughs. Its sign is a red
--               heart on a white roundel.
--   the MART    the general store. A half-hipped gable with a loft hoist, a
--               boarded lean-to for the stock, a glazed shop front with the
--               goods set out behind it, a BLUE and cream striped awning
--               under a painted fascia that says MART, barrels and crates.
--
-- NO Nintendo mark is drawn here: no ball, no logotype. The repository was
-- cleared of derived art on 2026-09-15 (assets/buildings/LICENSE.md) and a
-- voxel ball on a gable is the same design in another medium. Red and a
-- heart say "you get well here"; blue and an awning say "shop".
--
-- Same contract as the houses: selected ONLY for these two templates on
-- LAVENDER_TOWN (Buildings.build), an authored swatch sheet, Buildings'
-- shell mesher and AO, the chimney's mouth handed to HearthFX. The plot,
-- the door (x 16..31 of the south face) and the warp lane are the
-- template's and do not move: nothing below head height stands in the
-- door's cell, and the leaves hang well behind where a walker stops.
--
-- Coordinates are the plot's: x east 0..63, z south 0..63, y up. A person
-- is sixteen voxels. Nothing here is extracted from the ROM.
local Kit = { SHEET = "assets/buildings/lavender_civic.png",
              SHEET_W = 8, SHEET_H = 32 }

local floor, abs, min, max = math.floor, math.abs, math.min, math.max

-- Rows of the swatch sheet (eight shades each). The first sixteen are the
-- houses' own, colour for colour, so the stone and the slate match theirs;
-- tools/lavender_civic.py is the mirror of this list. (Its last two rows, a
-- cold light and damp stone, are the Tower's: lib/LavenderTowerKit.lua.)
local STONE, MORTAR, PLASTER, TRIM, SLATE, EDGE, WOOD, GRAIN,
      IRON, GLASS, LIGHT, MOSS, LEAF, FLOWER, CLAY, SHADOW,
      RED, RED_DK, WHITE, BLUE, BLUE_DK, CREAM, GOLD, OAK,
      GOODS_R, GOODS_G, GOODS_Y, CANVAS, FLAG, FLAGJOINT =
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
      16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29

local function sw(row, n) return row * 8 + n % 8 end
local function noise(x, y, z) return (x * 17 + y * 31 + z * 13) % 8 end

-- coursed limestone: bed joints every four, head joints staggered, moss low
local function stone(u, y, salt)
  local course = floor(y / 4)
  if y % 4 == 0 or (u + course % 2 * 5) % 10 == 0 then return sw(MORTAR, 3) end
  if y < 5 and (floor(u / 7) + salt) % 7 == 0 then return sw(MOSS, 2) end
  return sw(STONE, noise(floor(u / 10), course, salt))
end
local function timber(u, y)
  return sw((u % 4 == 0) and GRAIN or WOOD, floor(y / 7) % 3 + 2)
end
-- lime plaster in a frame: a stud every nine, plates at `lo` and `hi`, and
-- optionally a mid `rail` with braces rising off it
local function framed(u, y, lo, hi, salt, rail)
  if y == lo or y == hi or u % 9 == 0 then return timber(u, y) end
  if rail and (y == rail or (y > rail and y < rail + 9
                             and ((u + y) % 18 == 0 or (u - y) % 18 == 0))) then
    return timber(u, y)
  end
  return sw(PLASTER, (floor(u / 9) + floor(y / 6) * 3 + salt) % 8)
end
-- slate laid in courses up the slope (`d` voxels in from the eave), joints
-- staggered along it (`u`)
local function slate(u, d, salt)
  local course = floor(d / 3)
  if d % 3 == 0 and d > 0 then return sw(EDGE, 4) end
  if (u + course % 2 * 3) % 7 == 0 then return sw(EDGE, 3) end
  return sw(SLATE, noise(floor((u + course % 2 * 3) / 7), course, salt))
end
-- The plot's own paving, one voxel thick, wherever nothing else stands: the
-- mesher paints the DRAWN ground under a building, and round these two that
-- was a ring of the old checker. Pale flags, the colour of the town's paths
-- (tools/lavender_ground.py); one texel a stone, so a stone is one quad.
local function flag(x, z)
  local row = floor(z / 6)
  local u = x + row % 2 * 4
  if z % 6 == 0 or u % 8 == 0 then return sw(FLAGJOINT, 3) end
  return sw(FLAG, 2 + (floor(u / 8) * 3 + row * 5) % 4)
end
local function clayTile(u, d)
  if d % 2 == 0 then return sw(RED_DK, 3 + u % 2) end
  return sw(RED, 2 + (u + floor(d / 2)) % 4)
end

-- A window let into a wall: `u` across, `y` up, `depth` voxels IN from the
-- wall's face (0 = the face, negative = standing proud of it). Answers
-- handled, texel -- a texel of nil is a carved voxel, not an unhandled one.
-- `arch` rounds the head; `w2`/`y0`/`y1` are half-width and the opening.
local function window(u, y, depth, c, w2, y0, y1, arch, glow)
  local du = u - c + 0.5
  if abs(du) > w2 + 1.5 or y < y0 - 2 or y > y1 + 1 or depth < -1 or depth > 2 then
    return false
  end
  local inside = abs(du) <= w2 and y >= y0 and y <= y1
  if inside and arch then
    local spring = y1 - w2
    if y > spring and du * du + (y - spring) * (y - spring) > w2 * w2 + 1 then
      inside = false
    end
  end
  if y == y0 - 1 and abs(du) <= w2 + 1.5 and depth <= 0 then
    return true, sw(TRIM, 5)                                 -- the sill, proud
  end
  if not inside then
    if depth >= 0 and abs(du) <= w2 + 1 and y >= y0 and y <= y1 + 1 and depth == 0 then
      return true, sw(TRIM, 3)                               -- the surround
    end
    return false
  end
  if depth < 0 then return false end
  if depth < 2 then
    if depth == 1 and (abs(du) < 1 or y == floor((y0 + y1) / 2)) then
      return true, sw(WOOD, 3)                               -- glazing bars
    end
    return true, nil
  end
  if glow then return true, sw(LIGHT, 1 + (y1 - y) % 4) end
  return true, sw(GLASS, (du < 0 and y > (y0 + y1) / 2) and 6 or 2)
end

-- ------------------------------------------------------------ the CENTRE --

local HEART = { ".XX.XX.", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..." }

local function centre()
  local X0, X1, Z0, Z1 = 5, 58, 9, 53          -- the hall's walls
  local WALL, EAVE = 35, 36
  local BAYC, BAYW = 23.5, 11.5                -- the entrance bay, on the door
  local CHX, CHZ, CHTOP = 47, 13, 67           -- the chimney's corner, its top

  -- a bell-cast hip: gentle for four voxels at the eave, then one in one
  local function roofTop(x, z)
    local d = min(x - 2, 61 - x, z - 6, 56 - z)
    if d < 0 then return nil end
    return EAVE + (d < 4 and floor(d * 0.5) or d - 2), d
  end
  local function gableTop(x) return 47 - floor(abs(x - BAYC) * 0.92) end
  local function porchTop(x) return 26 + floor((13 - abs(x - BAYC)) * 0.7) end

  local function at(x, y, z)
    if x < 0 or x > 63 or z < 0 or z > 65 or y < 0 or y > 75 then return nil end
    local top, d = roofTop(x, z)

    -- ---- the door: an arched alcove five deep, glazed leaves behind it
    if x >= 16 and x <= 31 and z >= 50 and y <= 22 then
      local du = x - BAYC
      local open = abs(du) <= 6.5 and y >= 1
                   and (y <= 15 or du * du + (y - 15) * (y - 15) <= 44)
      if open then
        if z >= 51 then return nil end
        if abs(du) < 1 or y == 11 then return sw(WHITE, 4) end
        if abs(du) > 5.5 or y <= 2 then return sw(RED, 3) end
        if (abs(du) == 1.5) and y == 9 then return sw(GOLD, 4) end
        return sw(GLASS, y > 11 and 5 or 3)
      end
      if z >= 54 and z <= 55 and abs(du) <= 8 and y >= 1 and y <= 22
         and (y <= 15 or du * du + (y - 15) * (y - 15) <= 60) then
        return sw(RED, y % 3 == 0 and 2 or 4)               -- the red surround
      end
    end

    -- ---- the porch: two columns, a beam, a red tiled gable, a lantern
    if z >= 56 and x >= 9 and x <= 38 then
      local du = abs(x - BAYC)
      if y == 0 and x >= 11 and x <= 36 and z <= 63 then return sw(STONE, 5) end
      for _, cx in ipairs({ 13, 34 }) do
        local ax, az = abs(x - cx), abs(z - 61)
        if ax <= 2 and az <= 2 and y >= 1 and y <= 22 then
          if y <= 2 or y >= 21 then return sw(TRIM, 4) end
          if ax <= 1 and az <= 1 and not (ax == 1 and az == 1 and y % 6 == 0) then
            return sw(TRIM, 5 + (ax + az) % 2)
          end
        end
      end
      if y >= 23 and y <= 25 and x >= 11 and x <= 36 and z <= 63
         and (z >= 59 or x <= 12 or x >= 35) then
        return timber(x + z, y)
      end
      local pt = porchTop(x)
      if du <= 13.5 and z <= 64 and y >= 26 then
        if y == pt or y == pt - 1 then
          if z == 64 or du >= 13 then return sw(RED_DK, 2) end
          return clayTile(z, floor(13 - du))
        end
        if z == 63 and y < pt - 1 then                       -- the tympanum
          if du * du + (y - 29) * (y - 29) <= 3 then return sw(SHADOW, 2) end
          return sw(PLASTER, 4)
        end
      end
      if (x == 23 or x == 24) and (z == 60 or z == 61) then
        if y == 22 or y == 23 then return sw(IRON, 3) end
        if y >= 18 and y <= 21 then
          return (y == 18 or y == 21) and sw(IRON, 4) or sw(LIGHT, 5)
        end
      end
    end

    -- ---- out in front: a bench under the windows, lavender in troughs
    if z >= 54 and z <= 58 and x >= 39 and x <= 54 and y <= 9 then
      if z == 54 and y >= 6 then return sw(OAK, 2 + y % 2) end
      if z >= 55 and (y == 4 or y == 5) then return sw(OAK, z % 2 == 0 and 5 or 3) end
      if z >= 55 and y <= 3 and (x <= 40 or x >= 53) and (z == 55 or z == 58) then
        return sw(IRON, 3)
      end
    end
    for _, t in ipairs({ { 4, 9, 56, 62 }, { 56, 60, 55, 60 } }) do
      if x >= t[1] and x <= t[2] and z >= t[3] and z <= t[4] and y <= 8 then
        local rim = x == t[1] or x == t[2] or z == t[3] or z == t[4]
        if y <= 4 then return rim and stone(x + z, y + 1, 3) or sw(SHADOW, 3) end
        if not rim and (x * 3 + z * 5 + y) % 4 ~= 0 then
          return sw(y >= 7 and FLOWER or LEAF, x + z + y)
        end
      end
    end

    -- ---- the cupola on the ridge: louvres, a little slate cap, a finial
    if x >= 27 and x <= 36 and z >= 26 and z <= 35 and y >= 56 then
      local ax, az = abs(x - 31.5), abs(z - 30.5)
      if y <= 67 then
        if ax <= 4 and az <= 4 then
          if ax >= 3.5 and az >= 3.5 then return sw(TRIM, 4) end
          if y <= 58 or y >= 66 then return sw(TRIM, 3) end
          if max(ax, az) >= 3.5 then
            return y % 2 == 0 and sw(SHADOW, 2) or sw(WOOD, 4)
          end
          return sw(SHADOW, 1)
        end
      elseif y <= 72 then
        local r = 5.5 - (y - 68)
        if ax <= r and az <= r then return slate(x + z, y - 67, 5) end
      elseif y <= 74 and ax <= 0.5 and az <= 0.5 then
        return sw(GOLD, 4 + y % 2)
      end
    end

    -- ---- the chimney: masonry through the slope, a capped flue
    if x >= CHX - 1 and x <= CHX + 6 and z >= CHZ - 1 and z <= CHZ + 6 and top then
      local core = x >= CHX and x <= CHX + 5 and z >= CHZ and z <= CHZ + 5
      if y >= CHTOP - 2 and y <= CHTOP then
        if x >= CHX + 2 and x <= CHX + 3 and z >= CHZ + 2 and z <= CHZ + 3 then
          return nil
        end
        return sw(y == CHTOP - 2 and TRIM or STONE, 3)
      end
      if core and y > top - 3 and y < CHTOP - 2 then return stone(x + z, y, 2) end
      if not core and y >= top and y <= top + 1 then return sw(IRON, 4) end  -- flashing
    end

    -- ---- the entrance bay: a gable of its own, the heart on its face
    local bdu = abs(x - BAYC)
    if bdu <= BAYW + 1.5 and z >= 40 and z <= 57 then
      local gt = gableTop(x)
      if y == gt + 1 or y == gt + 2 then                     -- its slate
        if (not top or y > top) and z >= 42 then
          if z == 57 then return sw(EDGE, 5) end
          if bdu < 1 then return sw(EDGE, 6) end
          return slate(z, floor(BAYW + 2 - bdu), 4)
        end
      elseif bdu <= BAYW and z <= 55 and y <= gt and (not top or y > top - 1 or z >= 54) then
        if z >= 54 then
          if z == 55 and y >= 36 then
            local hx, hy = x - 20, 43 - y                    -- the sign
            if (x - BAYC) * (x - BAYC) + (y - 40.5) * (y - 40.5) <= 30 then
              local row = HEART[hy + 1]
              if row and hx >= 0 and hx <= 6 and row:sub(hx + 1, hx + 1) == "X" then
                return sw(RED, 4 + (hx + hy) % 2)
              end
              return sw(WHITE, 5)
            end
            if (x - BAYC) * (x - BAYC) + (y - 40.5) * (y - 40.5) <= 40 then
              return sw(TRIM, 2)
            end
          end
          if y <= 7 then return stone(x, y, 1) end
          if bdu >= BAYW - 1 then return sw(y % 5 == 0 and MORTAR or TRIM, 3) end
          if y == 24 or y == gt then return timber(x, y) end
          return y < 24 and stone(x, y, 1) or framed(x, y, 25, 35, 2)
        end
        return sw(PLASTER, 3)                                -- its buried body
      end
    end

    -- ---- the roof: slate on every slope, caps on the hips and the ridge
    if top then
      if y <= top and y >= top - 2 and y > WALL - 1 then
        if d == 0 then return sw(EDGE, 5) end
        local dx, dz = min(x - 2, 61 - x), min(z - 6, 56 - z)
        if abs(dx - dz) < 1 or d >= 25 then return sw(EDGE, 6) end
        return slate(dx < dz and z or x, d, 1)
      end
    end

    -- ---- the walls
    local inside = x >= X0 and x <= X1 and z >= Z0 and z <= Z1
    if inside and y <= WALL + 1 then
      -- windows, on all four faces
      local face, u, depth = nil, 0, 0
      if z >= Z1 - 2 then face, u, depth = "s", x, Z1 - z
      elseif z <= Z0 + 2 then face, u, depth = "n", x, z - Z0
      elseif x >= X1 - 2 then face, u, depth = "e", z, X1 - x
      elseif x <= X0 + 2 then face, u, depth = "w", z, x - X0 end
      if face == "s" then
        for _, c in ipairs({ 42, 52 }) do
          local h, v = window(u, y, depth, c, 4, 9, 20, true, c == 52)
          if h then return v end
          h, v = window(u, y, depth, c, 3, 27, 32, false, c == 42)
          if h then return v end
        end
      elseif face == "e" or face == "w" then
        for _, c in ipairs({ 18, 31, 44 }) do
          local h, v = window(u, y, depth, c, 4, 9, 20, true, face == "e" and c == 31)
          if h then return v end
          h, v = window(u, y, depth, c, 3, 27, 32, false, false)
          if h then return v end
        end
      elseif face == "n" then
        for _, c in ipairs({ 14, 26, 38, 50 }) do
          local h, v = window(u, y, depth, c, 3, 27, 32, false, false)
          if h then return v end
        end
      end
      local corner = (x <= X0 + 2 or x >= X1 - 2) and (z <= Z0 + 2 or z >= Z1 - 2)
      local along = (z <= Z0 + 2 or z >= Z1 - 2) and x or z
      if y <= 7 then return stone(along, y, 1) end
      if corner then return sw(y % 5 == 0 and MORTAR or TRIM, 3) end
      if y == 23 or y >= WALL then return sw(TRIM, 4) end
      if y < 23 then return stone(along, y, 1) end
      return framed(along, y, 24, WALL - 1, 1)
    end
    -- the plinth, the string course and the cornice stand a voxel proud
    if x >= X0 - 1 and x <= X1 + 1 and z >= Z0 - 1 and z <= Z1 + 1 then
      local along = (z < Z0 or z > Z1) and x or z
      if y <= 5 then return stone(along, y, 1) end
      if y == 23 or y == WALL then return sw(TRIM, 5) end
    end
    -- the red awnings over the two south windows
    if z >= 54 and z <= 57 and y >= 21 and y <= 24 then
      for _, c in ipairs({ 42, 52 }) do
        if x >= c - 4 and x <= c + 3 and y == 24 - (z - 54) then
          return sw(z == 57 and RED_DK or RED, 3 + (x % 2))
        end
      end
    end
    -- the hall under the roof: solid, so the shell has nothing to hide
    if inside and top and y < top - 2 then return sw(PLASTER, 3) end
    if y == 0 and z <= 63 then return flag(x, z) end       -- the forecourt
    return nil
  end

  return { at = at, W = 64, xmin = 0, xmax = 63, zmin = 0, zmax = 65,
           ytop = 75, chimney = { x = CHX + 3, y = CHTOP + 1, z = CHZ + 3 },
           -- the porch lantern, for the lamps' pass after dark
           lights = { { x = 24, y = 20, z = 61 } },
           tint = function(y) return 0.88 + min(y / 32, 1) * 0.12 end }
end

-- -------------------------------------------------------------- the MART --

local GLYPH = {
  { "X...X", "XX.XX", "X.X.X", "X.X.X", "X...X", "X...X", "X...X" },   -- M
  { ".XXX.", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X" },   -- A
  { "XXXX.", "X...X", "X...X", "XXXX.", "X.X..", "X..X.", "X...X" },   -- R
  { "XXXXX", "..X..", "..X..", "..X..", "..X..", "..X..", "..X.." },   -- T
}
local GOODS = { GOODS_R, GOODS_G, GOODS_Y, BLUE, CANVAS, CLAY }

local function mart()
  local X0, X1, Z0, Z1 = 4, 51, 9, 55          -- the shop
  local LX0, LX1, LZ0 = 52, 61, 22             -- the lean-to against its east wall
  -- the eave stands clear of the fascia: two voxels lower and the slate's
  -- overhang hid the top of every letter (the sign read MHKI from the street)
  local WALL, EAVE = 32, 33
  local CHX, CHZ, CHTOP = 9, 15, 63
  local DORC = 39.5                            -- the loft hoist's dormer

  -- a gable along x, its ends clipped to half-hips
  local function roofTop(x, z)
    local dz = min(z - 6, 58 - z)
    local dx = min(x - 2, 53 - x)
    if dz < 0 or dx < 0 then return nil end
    return min(EAVE + floor(dz * 0.9), EAVE + 8 + dx), dz, dx
  end
  local function leanTop(x) return 27 - floor((x - LX0) * 0.9) end
  local function dormerTop(x) return 52 - floor(abs(x - DORC) * 0.9) end

  local function at(x, y, z)
    if x < 0 or x > 63 or z < 0 or z > 65 or y < 0 or y > 66 then return nil end
    local top, dz, dx = roofTop(x, z)

    -- ---- the door: a square-headed alcove, a painted door with a light
    if x >= 16 and x <= 31 and z >= 51 and y <= 22 then
      local open = x >= 18 and x <= 29 and y >= 1 and y <= 20
      if open then
        if z >= 52 then return nil end
        if x == 18 or x == 29 or y == 20 or y == 11 then return sw(TRIM, 4) end
        if y > 11 then
          if x == 23 or x == 24 or y == 16 then return sw(BLUE_DK, 3) end
          return sw(GLASS, 4)
        end
        if x == 27 and y == 9 then return sw(GOLD, 5) end
        return sw(x % 3 == 0 and BLUE_DK or BLUE, 3)
      end
    end

    -- ---- the fascia, MART painted on it, and the striped awning under it
    if z >= 56 and x >= 5 and x <= 50 then
      if z == 56 and y >= 23 and y <= 31 then
        local g = floor((x - 17) / 6) + 1
        local gx = (x - 17) % 6
        if y >= 24 and y <= 30 and g >= 1 and g <= 4 and gx <= 4 and x >= 17 then
          if GLYPH[g][30 - y + 1]:sub(gx + 1, gx + 1) == "X" then return sw(CREAM, 5) end
        end
        if y == 23 or y == 31 then return sw(GOLD, 3) end
        return sw(BLUE, 3 + x % 2)
      end
      if z >= 57 and z <= 62 then
        local ay = 22 - floor((z - 57) * 0.75)
        local stripe = floor((x - 5) / 4) % 2 == 0
        if z <= 61 and y == ay then return sw(stripe and BLUE or CREAM, 4) end
        if z >= 61 and y == ay - (z == 62 and 0 or 1) and (x % 4 == 1 or x % 4 == 2 or z == 61) then
          return sw(stripe and BLUE_DK or CANVAS, 3)         -- the valance
        end
      end
    end
    -- a lantern on the pilaster by the door
    if (x == 32 or x == 33) and z >= 56 and z <= 58 and y >= 13 and y <= 18 then
      if z == 56 then return (y == 17) and sw(IRON, 3) or nil end
      if y == 13 or y == 18 then return sw(IRON, 4) end
      return sw(LIGHT, 5)
    end

    -- ---- stock out in front: produce by the small bay, barrel and crates
    if z >= 57 and z <= 62 and y <= 11 then
      if x >= 6 and x <= 13 and z <= 60 then                 -- two trays of produce
        local tray = (x <= 9) and 1 or 2
        if x ~= 10 then
          if y <= 3 then
            local rim = x == 6 or x == 9 or x == 11 or x == 13 or z == 57 or z == 60
            return rim and sw(OAK, 3) or sw(SHADOW, 3)
          end
          if y == 4 and (x + z) % 2 == 0 then
            return sw(tray == 1 and GOODS_R or GOODS_G, x + z)
          end
        end
      end
      if x >= 53 and x <= 58 then                            -- a crate, one on it
        if y <= 5 then
          local edge = x == 53 or x == 58 or z == 57 or z == 62 or y == 0 or y == 5
          return edge and sw(OAK, 2) or sw(OAK, 5)
        end
        if y <= 9 and x >= 54 and x <= 57 and z >= 58 and z <= 61 then
          return (x == 54 or x == 57 or y == 9) and sw(OAK, 2) or sw(OAK, 6)
        end
      end
      local bx, bz = x - 60.5, z - 59.5                      -- a barrel
      if bx * bx + bz * bz <= 6.5 and y <= 8 then
        return (y == 2 or y == 6) and sw(IRON, 3) or sw(OAK, 3 + (x + z) % 2)
      end
    end

    -- ---- the chimney
    if x >= CHX - 1 and x <= CHX + 6 and z >= CHZ - 1 and z <= CHZ + 6 and top then
      local core = x >= CHX and x <= CHX + 5 and z >= CHZ and z <= CHZ + 5
      if y >= CHTOP - 2 and y <= CHTOP then
        if x >= CHX + 2 and x <= CHX + 3 and z >= CHZ + 2 and z <= CHZ + 3 then
          return nil
        end
        return sw(y == CHTOP - 2 and TRIM or STONE, 3)
      end
      if core and y > top - 3 and y < CHTOP - 2 then return stone(x + z, y, 4) end
      if not core and y >= top and y <= top + 1 then return sw(IRON, 4) end
    end

    -- ---- the loft hoist: a gabled dormer, a boarded door, a beam and hook
    local ddu = abs(x - DORC)
    if ddu <= 7.5 and z >= 40 and z <= 63 then
      if (x == 39 or x == 40) and z >= 58 then
        if y == 49 or y == 50 then return timber(z, y) end
        if z == 62 and y >= 45 and y <= 48 then return sw(IRON, y == 45 and 5 or 3) end
      end
      local dt = dormerTop(x)
      if z <= 58 and (y == dt + 1 or y == dt + 2) and ddu <= 7.5 then
        if not top or y > top then
          if z == 58 then return sw(EDGE, 5) end
          return slate(z, floor(8 - ddu), 6)
        end
      elseif ddu <= 6 and z <= 57 and y <= dt and y > WALL and (not top or y > top - 1) then
        if z == 57 then
          if ddu <= 3.5 and y >= 35 and y <= 45 then
            if ddu >= 3 or y == 45 or y == 35 then return sw(TRIM, 3) end
            return timber(x * 2, y)
          end
          return framed(x, y, 34, 99, 3)
        end
        return sw(PLASTER, 3)
      end
    end

    -- ---- the roofs
    if top and x <= 53 then
      if y <= top and y >= top - 2 and y > WALL - 1 then
        if dz == 0 or dx == 0 then return sw(EDGE, 5) end
        if top == EAVE + 8 + dx and top < EAVE + floor(dz * 0.9) then
          return slate(z, dx + 8, 2)                         -- the half-hip
        end
        if dz >= 26 then return sw(EDGE, 6) end
        return slate(x, dz, 2)
      end
    end
    if x >= LX0 and x <= LX1 + 1 and z >= LZ0 - 1 and z <= Z1 + 1 then
      local lt = leanTop(x)
      if y == lt or y == lt - 1 then
        if x == LX1 + 1 or z == LZ0 - 1 or z == Z1 + 1 then return sw(EDGE, 4) end
        return slate(z, x - LX0, 7)
      end
    end

    -- ---- the shop front: bays of goods behind glazing bars
    if z >= 52 and z <= Z1 and y >= 8 and y <= 20 and x >= 6 and x <= 49 then
      local bay = (x >= 6 and x <= 14) and 1 or ((x >= 33 and x <= 49) and 2 or nil)
      if bay then
        local lx = x - (bay == 1 and 6 or 33)
        if z == Z1 then
          if lx % 4 == 0 or y == 8 or y == 20 or y == 17 then return sw(TRIM, 4) end
          return nil
        end
        if z == 52 then return sw(SHADOW, 2) end
        if y == 8 or y == 13 then return sw(OAK, 4) end      -- the shelves
        local item = floor(x / 2) + (y > 13 and 7 or 0)
        local tall = 2 + item % 3
        local base = y > 13 and 14 or 9
        if y < base + tall and x % 2 == 0 or (y < base + tall - 1) then
          return sw(GOODS[1 + item % #GOODS], item)
        end
        return nil
      end
    end

    -- ---- the walls: the shop, then its lean-to
    local inside = x >= X0 and x <= X1 and z >= Z0 and z <= Z1
    if inside and (y <= WALL + 1 or (top and y < top - 2)) then
      if y > WALL + 1 then
        -- the gable ends, framed up to the slate
        if x == X0 or x == X1 then
          if abs(z - 32) <= 2 and y >= 40 and y <= 45 then
            return (abs(z - 32) == 2 or y == 40 or y == 45) and sw(TRIM, 3) or sw(GLASS, 3)
          end
          return framed(z, y, 33, 99, 4, 33)
        end
        return sw(PLASTER, 3)
      end
      local face, u, depth = nil, 0, 0
      if x <= X0 + 2 then face, u, depth = "w", z, x - X0
      elseif z <= Z0 + 2 then face, u, depth = "n", x, z - Z0
      elseif x >= X1 - 2 and z < LZ0 then face, u, depth = "e", z, X1 - x end
      if face then
        local cs = face == "n" and { 16, 40 } or (face == "e" and { 15 } or { 24, 42 })
        for _, c in ipairs(cs) do
          local h, v = window(u, y, depth, c, 3, 12, 21, false, c == 24)
          if h then return v end
          -- blue shutters, folded back either side
          if depth == 0 and y >= 12 and y <= 21
             and (abs(u - c + 0.5) == 5.5 or abs(u - c + 0.5) == 6.5) then
            return sw(y % 3 == 0 and BLUE_DK or BLUE, 3)
          end
        end
      end
      local corner = (x <= X0 + 2 or x >= X1 - 2) and (z <= Z0 + 2 or z >= Z1 - 2)
      local along = (z <= Z0 + 2 or z >= Z1 - 2) and x or z
      if y <= 7 then return stone(along, y, 4) end
      if corner then return sw(y % 5 == 0 and MORTAR or TRIM, 3) end
      if z == Z1 and (x == 15 or x == 16 or x == 31 or x == 32 or x == 50) then
        return timber(y, x)                                  -- the front's pilasters
      end
      if y >= WALL then return sw(TRIM, 4) end
      return framed(along, y, 8, WALL - 1, 4, 19)
    end
    if x >= LX0 and x <= LX1 and z >= LZ0 and z <= Z1 and y < leanTop(x) - 1 then
      if y <= 7 then return stone(x + z, y, 6) end
      if x == LX1 and abs(z - 38) <= 3 and y >= 11 and y <= 16 then
        return (abs(z - 38) == 3 or y == 11 or y == 16) and sw(TRIM, 2) or sw(GLASS, 2)
      end
      if z == Z1 and x >= 54 and x <= 59 and y <= 17 then   -- the store's own door
        if x == 54 or x == 59 or y == 17 then return sw(GRAIN, 3) end
        return (y == 5 or y == 13) and sw(IRON, 3) or timber(x * 2, y)
      end
      return timber((x == LX1 or x == LX0) and z or x, y + x)   -- upright boards
    end
    if x >= X0 - 1 and x <= X1 + 1 and z >= Z0 - 1 and z <= Z1 + 1 and y <= 5 then
      return stone((z < Z0 or z > Z1) and x or z, y, 4)      -- the plinth
    end
    if y == 0 and z <= 63 then return flag(x, z) end       -- the forecourt
    return nil
  end

  return { at = at, W = 64, xmin = 0, xmax = 63, zmin = 0, zmax = 65,
           ytop = 66, chimney = { x = CHX + 3, y = CHTOP + 1, z = CHZ + 3 },
           lights = { { x = 33, y = 16, z = 58 } },
           tint = function(y) return 0.88 + min(y / 32, 1) * 0.12 end }
end

-- `t` is the template that matched: `pokecenter` or `pokemart`.
function Kit.model(sp, t)
  if not sp or sp.W ~= Kit.SHEET_W or sp.H ~= Kit.SHEET_H then
    return nil, "sheet is not " .. Kit.SHEET_W .. "x" .. Kit.SHEET_H
  end
  if #t.tiles ~= 8 or #t.tiles[1] ~= 8 then return nil, "expected a 64x64 plot" end
  if t.id == "pokecenter" then return centre() end
  if t.id == "pokemart" then return mart() end
  return nil, "not a civic template: " .. tostring(t.id)
end

Kit.TEMPLATES = { pokecenter = true, pokemart = true }

return Kit
