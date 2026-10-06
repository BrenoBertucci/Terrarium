-- Voxel world mode: the SKYLINE of Celadon City.
--
-- The landmarks are towers (the department store, the mansion, the Game
-- Corner, the hotel, the gym, the Centre): Celadon is the big city, and a
-- big city builds up. Every other plot on the map is a house of
-- lib/TownHouseKit.lua's, each its own.
--
-- The tileset stands every one of them as the same green-lidded brick box,
-- which is a market town. The landmarks are built from nothing as what a
-- big city builds:
-- TOWERS, stepped back as they rise the way a 1930s zoning law made them,
-- each in its own stone or glass under its own crown --
--
--   the DEPARTMENT STORE  a podium the width of a city block under twin
--                         stepped towers of celadon glass, a glass pyramid
--                         on each, MART across the fascia in lights
--   the MANSION           sandstone in three storeys-high orders under a
--                         copper dome and lantern
--   the GAME CORNER       black and violet, gold bands, a crown of neon
--   the HOTEL             white, balconied, HOTEL down its face in lights
--   the GYM               a concrete arena under a barrel vault, four pylons
--   the CENTRE            white with red bands, a heart in a roundel (no
--                         Nintendo mark is drawn -- assets/buildings/LICENSE.md)
--   and the rest          a limestone deco tower with a spire, glass slabs
--                         with a helipad or a mast, brick apartment blocks
--                         under water tanks, a slate tower with a clock, a
--                         terracotta block with a roof garden, a bronze
--                         office, the diner with its awning, a conservatory
--                         by the pond.
--
-- THE TALL PART STANDS TO THE SOUTH. The camera looks north and down, so a
-- plot's height climbs with every step back from its north edge (`RISE`):
-- the face the camera sees is the tall one, and the street behind a tower
-- keeps as much sky as a tower can leave it.
--
-- HOW IT STAYS CHEAP. The sheet (tools/celadon_towers.py) is facade STRIPS:
-- one row per kind of course, 128 texels wide, and a voxel answers
-- `row * 128 + u` with u running along its wall. Buildings.emit merges a run
-- whose texels march along the sheet, so one course of one face is ONE quad,
-- windows and all (`stripSides`: the flanks too). Glass is marked in the
-- sheet's alpha and lit after dark by the scene shader (Voxel3D.emissive).
--
-- Same terms as lib/VermilionHouseKit.lua: chosen ONLY for these placements
-- on CELADON_CITY, cached per placement, and a kit that will not build
-- leaves the classic box standing. The last cell row of every plot -- every
-- door's lane -- carries nothing below head height.
-- Coordinates are the plot's: x east, z south, y up. A person is sixteen
-- voxels. Nothing here is extracted from the ROM.
local Kit = { SHEET = "assets/buildings/celadon_towers.png",
              SHEET_W = 128, SHEET_H = 112,
              RISE = 3.0, LOW = 48 }       -- a tier h tall starts (h - LOW) / RISE in from the north

local floor, ceil, abs, min, max, sqrt = math.floor, math.ceil, math.abs, math.min, math.max, math.sqrt
local W = Kit.SHEET_W

-- styles, eight rows each (tools/celadon_towers.py STYLES, in order)
local DECO, GLASS, BRICK, CELADON, HOTEL, CASINO, MANSION, CONCRETE,
      CENTRE, TERRACOTTA, BRONZE, SLATE = 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
local PLINTH, SHOP, SPANDREL, WIN_HEAD, WIN_MID, WIN_SILL, CORNICE, ROOF = 0, 1, 2, 3, 4, 5, 6, 7
-- then rows of one colour (FLAT, in order)
local F0 = 96
local PAVE, PAVEJOINT, GOLD, COPPER, RED, WHITE, IRON, NEON_PINK, NEON_CYAN,
      BEACON, SIGN_LIT, LEAF, LEAF_DK, WOOD, NAVY, GLASS_ROOF =
      F0, F0 + 1, F0 + 2, F0 + 3, F0 + 4, F0 + 5, F0 + 6, F0 + 7, F0 + 8,
      F0 + 9, F0 + 10, F0 + 11, F0 + 12, F0 + 13, F0 + 14, F0 + 15
local function flat(row, x) return row * W + x % W end

-- a storey: two courses of wall, a window's head, its middle (twice), its sill
local STOREY = { SPANDREL, WIN_HEAD, WIN_MID, WIN_MID, WIN_SILL, SPANDREL }
local GRAND = { SPANDREL, SPANDREL, WIN_HEAD, WIN_MID, WIN_MID, WIN_MID, WIN_SILL, SPANDREL }   -- taller floors
local RIBBON = { SPANDREL, WIN_HEAD, WIN_MID, WIN_SILL }                                        -- curtain wall

local GLYPH = {
  M = { "X...X", "XX.XX", "X.X.X", "X.X.X", "X...X", "X...X", "X...X" },
  A = { ".XXX.", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X" },
  R = { "XXXX.", "X...X", "X...X", "XXXX.", "X.X..", "X..X.", "X...X" },
  T = { "XXXXX", "..X..", "..X..", "..X..", "..X..", "..X..", "..X.." },
  H = { "X...X", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X" },
  O = { ".XXX.", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX." },
  E = { "XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "XXXXX" },
  L = { "X....", "X....", "X....", "X....", "X....", "X....", "XXXXX" },
  G = { ".XXXX", "X....", "X....", "X..XX", "X...X", "X...X", ".XXX." },
  Y = { "X...X", "X...X", ".X.X.", "..X..", "..X..", "..X..", "..X.." },
}

local HEART = { ".XX.XX.", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..." }
local function lit(rows, col, row) return rows[row] and rows[row]:sub(col, col) == "X" end

-- ------------------------------------------------------------------ crowns --
-- Each is built with the top tier's box `B` { x0, x1, z0, z1, h } and answers
-- a texel or nil for a voxel the tiers did not claim.
local C = {}
function C.spire(r0, h, row)
  return function(B)
    local cx, cz = (B.x0 + B.x1) / 2, (B.z0 + B.z1) / 2
    return function(x, y, z)
      local k = y - B.h
      if k < 1 or k > h + 3 then return nil end
      if k > h then return (abs(x - cx) < 1 and abs(z - cz) < 1) and flat(BEACON, x) or nil end
      local r = r0 * (1 - k / h) ^ 0.8 + 0.6
      if abs(x - cx) <= r and abs(z - cz) <= r then return flat(k % 9 == 0 and GOLD or row, x) end
    end
  end
end
function C.mast(h)
  return function(B)
    local cx, cz = floor((B.x0 + B.x1) / 2), floor((B.z0 + B.z1) / 2) - 2
    return function(x, y, z)
      local k = y - B.h
      if k < 1 or k > h then return nil end
      if x == cx and z == cz then return flat((k == h or k == floor(h / 2)) and BEACON or IRON, x) end
      if k <= 3 and abs(x - cx) <= 2 and abs(z - cz) <= 2 then return flat(IRON, x) end
    end
  end
end
function C.helipad()
  return function(B)
    local cx, cz = (B.x0 + B.x1) / 2, (B.z0 + B.z1) / 2
    local r = min(B.x1 - B.x0, B.z1 - B.z0) / 2 - 2
    return function(x, y, z)
      if y ~= B.h + 1 then return nil end
      local dx, dz = x - cx, z - cz
      if dx * dx + dz * dz > r * r then return nil end
      if dx * dx + dz * dz > (r - 1.5) ^ 2 then return flat(SIGN_LIT, x) end
      if (abs(abs(dx) - 2.5) < 1 and abs(dz) <= 4) or (abs(dz) < 1 and abs(dx) <= 2.5) then return flat(WHITE, x) end
      return flat(IRON, x)
    end
  end
end
function C.tank()
  return function(B)
    local cx, cz = B.x0 + 9.5, B.z0 + 8.5
    return function(x, y, z)
      local k = y - B.h
      if k < 1 or k > 19 then return nil end
      local dx, dz = x - cx, z - cz
      local d = dx * dx + dz * dz
      if k <= 6 then return (abs(abs(dx) - 3.5) < 1 and abs(abs(dz) - 3.5) < 1) and flat(IRON, x) or nil end
      if k <= 15 then return d <= 30 and flat((k == 9 or k == 13) and IRON or WOOD, x) or nil end
      local r = (20 - k) * 1.4
      return d <= r * r and flat(IRON, x) or nil
    end
  end
end
function C.dome(row)
  return function(B)
    local cx, cz = (B.x0 + B.x1) / 2, (B.z0 + B.z1) / 2
    local r = min(B.x1 - B.x0, B.z1 - B.z0) / 2 - 3
    return function(x, y, z)
      local k = y - B.h
      if k < 1 then return nil end
      local dx, dz = x - cx, z - cz
      local d = dx * dx + dz * dz
      if k <= 4 then return d <= (r + 1) ^ 2 and flat(WHITE, x) or nil end              -- the drum
      local q = k - 4
      if q <= r then return d <= r * r - q * q and flat((floor(dx) % 6 == 0) and GOLD or row, x) or nil end
      if q <= r + 8 then return d <= 5 and flat(q == r + 8 and BEACON or WHITE, x) or nil end   -- the lantern
    end
  end
end
function C.pyramid(row)
  return function(B)
    return function(x, y, z)
      local k = y - B.h
      if k < 1 then return nil end
      local inset = k - 1
      if x >= B.x0 + inset and x <= B.x1 - inset and z >= B.z0 + inset and z <= B.z1 - inset then
        local rim = x == B.x0 + inset or x == B.x1 - inset or z == B.z0 + inset or z == B.z1 - inset
        return flat((rim and k % 4 == 0) and WHITE or row, x)
      end
    end
  end
end
function C.garden()
  return function(B)
    return function(x, y, z)
      local k = y - B.h
      if k < 1 or k > 7 then return nil end
      if x < B.x0 + 2 or x > B.x1 - 2 or z < B.z0 + 2 or z > B.z1 - 2 then return nil end
      local gx, gz = floor(x / 7), floor(z / 7)
      local h = (gx * 37 + gz * 91) % 8
      if h < 3 then return nil end
      local dx, dz = x - gx * 7 - 3, z - gz * 7 - 3
      local r2 = (h - 1) - (k - 3) * (k - 3) * 0.6
      if dx * dx + dz * dz <= r2 then return flat((x + z + k) % 3 == 0 and LEAF_DK or LEAF, x) end
    end
  end
end
function C.neon(rowA, rowB)                          -- two bands of light round the crown
  return function(B)
    return function(x, y, z)
      local k = y - B.h
      local edge = (x == B.x0 - 1 or x == B.x1 + 1) and z >= B.z0 - 1 and z <= B.z1 + 1
                   or (z == B.z0 - 1 or z == B.z1 + 1) and x >= B.x0 - 1 and x <= B.x1 + 1
      if edge and (k == -3 or k == -9) then return flat(k == -3 and rowA or rowB, x) end
      if k >= 1 and k <= 10 and abs(x - (B.x0 + B.x1) / 2) + abs(z - B.z1 + 3) <= 10 - k then     -- a gold gem
        return flat(k % 3 == 0 and rowA or GOLD, x)
      end
    end
  end
end
function C.vault(row)                                -- a barrel vault along x
  return function(B)
    local cz, r = (B.z0 + B.z1) / 2, (B.z1 - B.z0) / 2
    return function(x, y, z)
      local k = y - B.h
      if k < 1 or x < B.x0 or x > B.x1 then return nil end
      local top = sqrt(max(0, r * r - (z - cz) ^ 2)) * 0.55
      if k <= top then return flat((x - B.x0) % 16 < 2 and WHITE or row, x) end
    end
  end
end
function C.pylons(h)
  return function(B)
    return function(x, y, z)
      local k = y - B.h
      if k < 1 or k > h then return nil end
      local cornerX = (x - B.x0 <= 3) or (B.x1 - x <= 3)
      local cornerZ = (z - B.z0 <= 3) or (B.z1 - z <= 3)
      if cornerX and cornerZ then return flat(k == h and BEACON or WHITE, x) end
    end
  end
end
-- words on the south face of tier `t`, in lights: across, or one letter under another
function C.sign(word, tier, y0, vertical, x0)
  return function(_, tiers)
    local T = tiers[tier]
    local z = T.z1 + 1
    return function(x, y, zz)
      if zz ~= z then return nil end
      local n = #word
      if vertical then
        local col = x - x0
        if col < -1 or col > 5 then return nil end
        local row = y0 - y                         -- 0 at the top
        if row < -1 or row > n * 9 - 1 then return nil end
        local i = floor(row / 9) + 1
        local g = GLYPH[word:sub(i, i)]
        if col >= 0 and col <= 4 and row >= 0 and row % 9 < 7 and g and lit(g, col + 1, row % 9 + 1) then
          return flat(SIGN_LIT, x)
        end
        return flat(NAVY, x)
      end
      local left = floor((T.x0 + T.x1) / 2 - (n * 7 - 2) / 2)
      local col = x - left
      if col < -2 or col > n * 7 - 1 or y > y0 + 1 or y < y0 - 7 then return nil end
      local i = floor(col / 7) + 1
      local g = GLYPH[word:sub(i, i)]
      if col >= 0 and col % 7 < 5 and y <= y0 and y >= y0 - 6 and g and lit(g, col % 7 + 1, y0 - y + 1) then
        return flat(SIGN_LIT, x)
      end
      return flat(NAVY, x)
    end
  end
end
function C.heart(tier, y0)
  return function(_, tiers)
    local T = tiers[tier]
    local cx, z = (T.x0 + T.x1) / 2, T.z1 + 1
    return function(x, y, zz)
      if zz ~= z then return nil end
      local dx, dy = x - cx, y - y0
      if dx * dx + dy * dy > 110 then return nil end
      local col, row = floor((dx + 7) / 2) + 1, floor((6 - dy) / 2) + 1
      if col >= 1 and col <= 7 and lit(HEART, col, row) then return flat(RED, x) end
      return flat(WHITE, x)
    end
  end
end
function C.clock(tier, y0)
  return function(_, tiers)
    local T = tiers[tier]
    local cx, z = (T.x0 + T.x1) / 2, T.z1 + 1
    return function(x, y, zz)
      if zz ~= z then return nil end
      local dx, dy = x - cx, y - y0
      local d = dx * dx + dy * dy
      if d > 64 then return nil end
      if d > 44 then return flat(GOLD, x) end
      if (abs(dx) < 1 and dy >= 0 and dy <= 6) or (abs(dy) < 1 and dx >= 0 and dx <= 4) then return flat(IRON, x) end
      return flat(SIGN_LIT, x)
    end
  end
end
function C.awning(rowA, rowB)                         -- striped, over the whole shopfront
  return function(_, tiers)
    local T = tiers[1]
    return function(x, y, z)
      if z <= T.z1 or z > T.z1 + 6 or x < T.x0 + 2 or x > T.x1 - 2 then return nil end
      if y == 24 - floor((z - T.z1) * 0.8) then return flat(floor(x / 4) % 2 == 0 and rowA or rowB, x) end
    end
  end
end

-- -------------------------------------------------------------- the plots --
-- key = "tx:ty" of the placement's top-left TILE; { name, tiles wide, tiles deep }
Kit.PLOTS = {
  ["12:12"] = { "store", 16, 16 },     ["44:8"] = { "mansion", 12, 12 },   ["80:12"] = { "centre", 8, 8 },
  ["52:32"] = { "casino", 12, 8 },     ["12:48"] = { "gym", 16, 8 },       ["84:48"] = { "hotel", 8, 8 },
}
Kit.NAMES = {}
for key, p in pairs(Kit.PLOTS) do Kit.NAMES[key] = p[1] end

-- name = { style, heights (tier tops, rising), x insets per tier, door x0 or nil, cycle, crowns... }
local SPEC = {
  store   = { style = CELADON, h = { 58, 58, 150, 196 }, inset = { 0, 0, 10, 20 }, doors = { 32, 64 }, cycle = RIBBON, twin = true,
              crowns = { C.pyramid(GLASS_ROOF), C.sign("MART", 1, 56) } },
  mansion = { style = MANSION, h = { 52, 92, 124 }, inset = { 0, 8, 18 }, door = 32, cycle = GRAND, crowns = { C.dome(COPPER) } },
  centre  = { style = CENTRE, h = { 40, 96, 130 }, inset = { 0, 4, 12 }, door = 16, cycle = STOREY, crowns = { C.mast(18), C.heart(2, 82) } },
  casino  = { style = CASINO, h = { 44, 96, 150 }, inset = { 0, 10, 24 }, door = 32, cycle = STOREY, crowns = { C.neon(NEON_PINK, NEON_CYAN) } },
  gym     = { style = CONCRETE, h = { 40, 74 }, inset = { 0, 8 }, door = 96, cycle = GRAND, crowns = { C.vault(COPPER), C.pylons(22), C.sign("GYM", 1, 38) } },
  hotel   = { style = HOTEL, h = { 40, 182 }, inset = { 0, 3 }, door = 16, cycle = STOREY, crowns = { C.sign("HOTEL", 2, 170, true, 48), C.garden() } },
}

local function build(name, PW, PD)
  local S = SPEC[name]
  local base = S.style * 8
  local zf = PD - 10                                   -- the street face: the last cell row stays clear
  -- the tiers: each taller one further from the north edge, and a little in from the street
  local tiers = {}
  for i, h in ipairs(S.h) do
    local z0 = max(1, ceil((h - Kit.LOW) / Kit.RISE))
    local z1 = zf - min(i - 1, 3) * 2
    if z1 - z0 < 12 then z0 = z1 - 12 end
    tiers[i] = { x0 = S.inset[i], x1 = PW - 1 - S.inset[i], z0 = z0, z1 = z1, h = h }
  end
  -- the department store's towers are TWO: the upper tiers are split down the middle
  local gap = S.twin and 3 or nil
  local doors = S.doors or (S.door and { S.door }) or {}
  local top = tiers[#tiers]
  local crowns = {}
  for i, make in ipairs(S.crowns or {}) do crowns[i] = make(top, tiers) end
  local ytop = top.h + 40
  if ytop > 236 then ytop = 236 end
  local cycle, n = S.cycle, #S.cycle
  local mid = (PW - 1) / 2

  local function at(x, y, z)
    if x < 0 or x >= PW or z < 0 or z >= PD or y < 0 or y > ytop then return nil end
    local k, T = nil, nil
    for i = 1, #tiers do
      if y <= tiers[i].h then k, T = i, tiers[i] break end
    end
    if T and x >= T.x0 and x <= T.x1 and z >= T.z0 and z <= T.z1
       and not (gap and k >= 3 and abs(x - mid) < gap + (k - 3) * 4) then
      if k == 1 and y <= 17 and z > T.z1 - 5 then              -- a door: an alcove five deep
        for _, d in ipairs(doors) do
          if x >= d and x <= d + 15 then
            if y == 0 then return flat(PAVE, x) end
            if x == d or x == d + 15 or y == 17 then return (base + CORNICE) * W + x end
            return nil
          end
        end
      end
      local inner = gap and k >= 3 and abs(x - mid) < gap + (k - 3) * 4 + 1
      local side = x == T.x0 or x == T.x1 or inner
      local u = side and z or x
      local edge = side or z == T.z0 or z == T.z1
      local row
      if y == T.h then row = edge and CORNICE or ROOF
      elseif y >= T.h - 2 then row = CORNICE
      elseif y <= 2 then row = PLINTH
      elseif k == 1 and y <= 16 then row = (y == 16) and CORNICE or SHOP
      else row = cycle[(y - 17) % n + 1] end
      return (base + row) * W + u
    end
    for i = 1, #crowns do
      local v = crowns[i](x, y, z)
      if v then return v end
    end
    -- a canopy over every door, lit along its edge
    if (y == 19 or y == 20) and z > tiers[1].z1 and z <= tiers[1].z1 + 6 then
      for _, d in ipairs(doors) do
        if x >= d - 3 and x <= d + 18 then
          return flat((y == 19 and z == tiers[1].z1 + 6) and SIGN_LIT or IRON, x)
        end
      end
    end
    if y == 0 then return flat((x % 16 == 8 or z % 16 == 8) and PAVEJOINT or PAVE, x) end
    return nil
  end

  local lights = {}
  for _, d in ipairs(doors) do lights[#lights + 1] = { x = d + 8, y = 17, z = tiers[1].z1 + 5 } end
  return { at = at, W = PW, xmin = 0, xmax = PW - 1, zmin = 0, zmax = PD - 1, ytop = ytop,
           stripSides = true, lights = lights }
end

function Kit.model(sp, t, tx, ty)
  if Kit.ENABLED == false then return nil, "switched off" end
  if not sp or sp.W ~= Kit.SHEET_W or sp.H ~= Kit.SHEET_H then
    return nil, "sheet is not " .. Kit.SHEET_W .. "x" .. Kit.SHEET_H
  end
  local key = tostring(tx) .. ":" .. tostring(ty)
  local plot = Kit.PLOTS[key]
  if not plot then return nil, "no building of Celadon's stands at " .. key end
  if #t.tiles ~= plot[3] or #t.tiles[1] ~= plot[2] then
    return nil, "plot " .. key .. " is not " .. plot[2] .. "x" .. plot[3] .. " tiles"
  end
  return build(plot[1], plot[2] * 8, plot[3] * 8)
end

return Kit
