-- Voxel world mode: the rooms of Celadon City, INSIDE -- eighteen of them, and
-- every one dressed for what it is.
--
-- Celadon's interiors are eighteen DIFFERENT plans across five tilesets (the
-- department store's six floors and its lift, the mansion's four and the
-- house on its roof, the Game Corner and its prize room, the diner, the
-- hotel, the chief's house, Erika's gym). Lavender's and Vermilion's homes
-- are one plan each, so their rooms are written out by hand, voxel by voxel;
-- eighteen plans cannot be. So this kit does not know any plan. It reads the
-- room the way the mesher does -- tile by tile, the CLASS and HEIGHT
-- Structures already gave each one (wall, counter, table, bookcase, ground)
-- -- and builds the same masses in the same places, so nothing the player
-- can walk into moves; and then it DRESSES them, from a theme per map:
--
--   the floor     laid one voxel thick under everything that stands, in the
--                 room's own pattern -- marble with celadon diamonds in the
--                 store's lobby, a black-and-white checker in the diner,
--                 violet carpet with gold lozenges in the Game Corner,
--                 tatami in the chief's house, moss and stepping stone in
--                 the gym -- by WORLD position, so it runs on across cells
--   the walls     skirting, wainscot, a rail, paper with a stripe, a cornice;
--                 the BACK wall (nothing but wall north of it) stands a full
--                 storey, a wall with floor behind it stays low enough to
--                 see over; pictures hang along the back wall
--   counters      a body and a top in the room's materials, and a FRONT that
--                 says what it is: panelled, a diner's chrome bar, a glass
--                 display case, a row of slot machines with lit screens
--   tables        legs and a slab (a cloth, in the diner and the hotel)
--   cases         shelved, and STOCKED in the floor's own goods -- a
--                 different palette on every floor of the store
--
-- What the tileset stands as a cut-out (stools, plants, machines, figures,
-- stairs) still stands as it did, on the new floor.
--
-- One model per CELL SIGNATURE (the four tiles' kinds and heights, the eight
-- tiles round them, which way the floor's pattern falls) -- a room is a few
-- dozen models however big it is. The cells round a model answer as phantoms
-- (Buildings.PHANTOM) so a run of wall or counter is one mass. The Pokemon
-- Centre keeps lib/RoomKit.lua's room. Nothing here is extracted from the ROM.
local Kit = { SHEET = "assets/buildings/celadon_rooms.png", SHEET_W = 8, SHEET_H = 32,
              TALL = 28, LOW = 14 }

local floor, abs, max, min = math.floor, math.abs, math.max, math.min

-- rows of the swatch sheet, eight shades each (tools/celadon_rooms.py, in order)
local CREAM, WHITE, CELADON, CELADON_DK, BLUE, BLUE_PALE, NAVY, PURPLE,
      PURPLE_DK, BLACK, GOLD, RED, BURGUNDY, PINK, MINT, GREEN,
      GREEN_DK, OAK, WALNUT, DARKWOOD, GREY, GREY_DK, CONCRETE, TERRA,
      ORANGE, YELLOW, CYAN, CHROME, TATAMI, MOSS, STONE, MAGENTA =
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
      16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31
local function sw(row, n) return row * 8 + n % 8 end
local function hash(a, b, c) return (a * 127 + b * 311 + c * 571 + a * b * 7) % 97 end

-- ------------------------------------------------------------------ floors --
-- (X, Z) are WORLD voxels modulo 32: every pattern repeats in 32 or a divisor.
local FLOOR = {}
function FLOOR.marble(t, X, Z)
  local cx, cz = X % 16, Z % 16
  if abs(cx - 7.5) + abs(cz - 7.5) >= 14 then return sw(t.b, 4) end          -- a diamond where four meet
  if cx == 0 or cz == 0 then return sw(t.a, 1) end
  return sw(t.a, 4 + (floor(X / 16) + floor(Z / 16)) % 2 * 2)
end
function FLOOR.checker(t, X, Z)
  local s = t.size or 8
  return sw((floor(X / s) + floor(Z / s)) % 2 == 0 and t.a or t.b, 4)
end
function FLOOR.planks(t, X, Z)
  local row = floor(Z / 4)
  if Z % 4 == 0 or (X + row * 12) % 32 == 0 then return sw(t.a, 1) end
  return sw(t.a, 3 + (row * 5 + floor((X + row * 12) / 32)) % 4)
end
function FLOOR.parquet(t, X, Z)
  local along = (floor(X / 8) + floor(Z / 8)) % 2 == 0
  local strip = along and Z % 8 or X % 8
  if strip == 0 then return sw(t.b, 3) end
  return sw(t.a, 3 + floor(strip / 2) % 3)
end
function FLOOR.carpet(t, X, Z)
  local d = abs(X % 16 - 7.5) + abs(Z % 16 - 7.5)
  if d < 2 then return sw(t.c or t.b, 5) end
  if d >= 5 and d < 6 then return sw(t.b, 4) end
  return sw(t.a, 3 + (X + Z) % 2)
end
function FLOOR.pavers(t, X, Z)
  local row = floor(Z / 8)
  local u = X + row % 2 * 8
  if Z % 8 == 0 or u % 16 == 0 then return sw(t.b, 2) end
  return sw(t.a, 3 + (floor(u / 16) + row) % 3)
end
function FLOOR.tatami(t, X, Z)
  local flip = (floor(X / 16) + floor(Z / 16)) % 2 == 0
  local a, b = flip and X % 16 or Z % 16, flip and Z % 16 or X % 16
  if a == 0 or a == 15 or b == 0 or b == 15 then return sw(t.b, 3) end
  return sw(t.a, 4 + a % 2)
end
function FLOOR.garden(t, X, Z)
  local d = (X % 16 - 7.5) ^ 2 + (Z % 16 - 7.5) ^ 2
  if d < 22 then return sw(t.b, d < 14 and 5 or 3) end                        -- a stepping stone
  return sw(t.a, 2 + hash(X, 1, Z) % 4)
end

-- ------------------------------------------------------------------ themes --
local function theme(o) return o end
local STORE_WALL = { skirt = CELADON_DK, wains = CELADON, rail = WHITE, paper = CREAM, stripe = CELADON, cornice = WHITE }
local THEMES = {
  store1 = theme { floor = { "marble", a = CREAM, b = CELADON }, wall = STORE_WALL,
                   counter = { body = WHITE, top = CELADON, front = "panel", accent = GOLD },
                   tabl = { leg = CHROME, top = WHITE }, case = { frame = WHITE, stock = { RED, BLUE, YELLOW, GREEN, PINK } },
                   art = { CELADON, GOLD } },
  store2 = theme { floor = { "checker", a = WHITE, b = BLUE_PALE, size = 8 }, wall = { skirt = NAVY, wains = BLUE, rail = WHITE, paper = WHITE, stripe = BLUE_PALE, cornice = WHITE },
                   counter = { body = BLUE, top = WHITE, front = "glass", accent = RED },
                   tabl = { leg = CHROME, top = BLUE_PALE }, case = { frame = NAVY, stock = { RED, WHITE, BLUE, RED, YELLOW } },
                   art = { BLUE, RED } },
  store3 = theme { floor = { "carpet", a = PURPLE_DK, b = MAGENTA, c = CYAN }, wall = { skirt = BLACK, wains = PURPLE_DK, rail = CYAN, paper = GREY_DK, stripe = PURPLE, cornice = BLACK },
                   counter = { body = BLACK, top = GREY_DK, front = "slot", accent = CYAN },
                   tabl = { leg = BLACK, top = GREY_DK }, case = { frame = BLACK, stock = { CYAN, MAGENTA, YELLOW, PURPLE, WHITE } },
                   art = { MAGENTA, CYAN } },
  store4 = theme { floor = { "parquet", a = OAK, b = WALNUT }, wall = { skirt = WALNUT, wains = PINK, rail = GOLD, paper = CREAM, stripe = PINK, cornice = GOLD },
                   counter = { body = OAK, top = PINK, front = "glass", accent = GOLD },
                   tabl = { leg = OAK, top = CREAM }, case = { frame = OAK, stock = { PINK, GOLD, MINT, WHITE, ORANGE } },
                   art = { PINK, GOLD } },
  store5 = theme { floor = { "checker", a = WHITE, b = MINT, size = 16 }, wall = { skirt = GREEN_DK, wains = MINT, rail = WHITE, paper = WHITE, stripe = MINT, cornice = WHITE },
                   counter = { body = WHITE, top = MINT, front = "panel", accent = GREEN },
                   tabl = { leg = CHROME, top = WHITE }, case = { frame = WHITE, stock = { GREEN, ORANGE, WHITE, MINT, YELLOW } },
                   art = { GREEN, WHITE } },
  roof   = theme { floor = { "pavers", a = CONCRETE, b = GREY_DK }, wall = { skirt = GREY_DK, wains = CONCRETE, rail = GREY, paper = CONCRETE, stripe = CONCRETE, cornice = CELADON, low = true },
                   counter = { body = CHROME, top = WHITE, front = "bar", accent = RED },
                   tabl = { leg = CHROME, top = WHITE }, case = { frame = RED, stock = { WHITE, CYAN, ORANGE, YELLOW, WHITE } },
                   art = { CELADON, WHITE } },
  lift   = theme { floor = { "carpet", a = BURGUNDY, b = GOLD }, wall = { skirt = DARKWOOD, wains = WALNUT, rail = GOLD, paper = WALNUT, stripe = DARKWOOD, cornice = GOLD },
                   counter = { body = WALNUT, top = GOLD, front = "panel", accent = GOLD },
                   tabl = { leg = WALNUT, top = GOLD }, case = { frame = WALNUT, stock = { GOLD } }, art = { GOLD, BURGUNDY } },
  mansion1 = theme { floor = { "carpet", a = BURGUNDY, b = GOLD, c = CREAM }, wall = { skirt = DARKWOOD, wains = WALNUT, rail = GOLD, paper = CREAM, stripe = BURGUNDY, cornice = GOLD },
                   counter = { body = WALNUT, top = DARKWOOD, front = "panel", accent = GOLD },
                   tabl = { leg = WALNUT, top = WALNUT, cloth = CREAM }, case = { frame = WALNUT, stock = { BURGUNDY, GREEN_DK, NAVY, GOLD, DARKWOOD } },
                   art = { BURGUNDY, GOLD } },
  mansion2 = theme { floor = { "carpet", a = GREEN_DK, b = GOLD, c = CREAM }, wall = { skirt = DARKWOOD, wains = OAK, rail = GOLD, paper = CREAM, stripe = GREEN, cornice = GOLD },
                   counter = { body = OAK, top = WALNUT, front = "panel", accent = GOLD },
                   tabl = { leg = OAK, top = OAK, cloth = GREEN }, case = { frame = OAK, stock = { GREEN_DK, BURGUNDY, CREAM, GOLD, NAVY } },
                   art = { GREEN, GOLD } },
  studio = theme { floor = { "carpet", a = GREY, b = BLUE, c = WHITE }, wall = { skirt = GREY_DK, wains = WHITE, rail = BLUE, paper = WHITE, stripe = BLUE_PALE, cornice = GREY },
                   counter = { body = GREY, top = WHITE, front = "slot", accent = BLUE },
                   tabl = { leg = GREY_DK, top = WHITE }, case = { frame = GREY, stock = { BLUE, RED, YELLOW, GREEN, WHITE } },
                   art = { BLUE, YELLOW } },
  terrace = theme { floor = { "pavers", a = TERRA, b = WALNUT }, wall = { skirt = STONE, wains = STONE, rail = CREAM, paper = STONE, stripe = STONE, cornice = CREAM, low = true },
                   counter = { body = TERRA, top = CREAM, front = "panel", accent = GREEN },
                   tabl = { leg = DARKWOOD, top = OAK }, case = { frame = OAK, stock = { GREEN, PINK, YELLOW } }, art = { GREEN, TERRA } },
  attic  = theme { floor = { "planks", a = OAK }, wall = { skirt = WALNUT, wains = YELLOW, rail = WHITE, paper = CREAM, stripe = YELLOW, cornice = WHITE },
                   counter = { body = OAK, top = WALNUT, front = "panel", accent = RED },
                   tabl = { leg = OAK, top = OAK, cloth = RED }, case = { frame = OAK, stock = { RED, BLUE, GREEN, YELLOW, ORANGE } },
                   art = { YELLOW, RED } },
  chief  = theme { floor = { "tatami", a = TATAMI, b = GREEN_DK }, wall = { skirt = DARKWOOD, wains = DARKWOOD, rail = DARKWOOD, paper = CREAM, stripe = DARKWOOD, cornice = DARKWOOD },
                   counter = { body = DARKWOOD, top = BLACK, front = "panel", accent = RED },
                   tabl = { leg = DARKWOOD, top = BLACK }, case = { frame = DARKWOOD, stock = { CREAM, RED, BLACK, GOLD, CREAM } },
                   art = { RED, BLACK } },
  diner  = theme { floor = { "checker", a = BLACK, b = WHITE, size = 8 }, wall = { skirt = BLACK, wains = RED, rail = CHROME, paper = CREAM, stripe = RED, cornice = CHROME },
                   counter = { body = RED, top = CHROME, front = "bar", accent = WHITE },
                   tabl = { leg = CHROME, top = WHITE, cloth = RED }, case = { frame = CHROME, stock = { RED, YELLOW, WHITE, CYAN, ORANGE } },
                   art = { RED, CYAN } },
  hotel  = theme { floor = { "marble", a = CREAM, b = NAVY }, wall = { skirt = DARKWOOD, wains = NAVY, rail = GOLD, paper = CREAM, stripe = GOLD, cornice = GOLD },
                   counter = { body = WALNUT, top = DARKWOOD, front = "panel", accent = GOLD },
                   tabl = { leg = WALNUT, top = WALNUT, cloth = WHITE }, case = { frame = WALNUT, stock = { NAVY, GOLD, WHITE, BURGUNDY, CREAM } },
                   art = { NAVY, GOLD } },
  gym    = theme { floor = { "garden", a = MOSS, b = STONE }, wall = { skirt = GREEN_DK, wains = GREEN, rail = OAK, paper = TATAMI, stripe = OAK, cornice = OAK },
                   counter = { body = OAK, top = GREEN, front = "panel", accent = PINK },
                   tabl = { leg = OAK, top = OAK }, case = { frame = OAK, stock = { PINK, GREEN, YELLOW, WHITE, PINK } },
                   art = { PINK, GREEN } },
  casino = theme { floor = { "carpet", a = PURPLE, b = GOLD, c = RED }, wall = { skirt = BLACK, wains = PURPLE_DK, rail = GOLD, paper = BLACK, stripe = MAGENTA, cornice = GOLD },
                   counter = { body = PURPLE_DK, top = BLACK, front = "slot", accent = GOLD },
                   tabl = { leg = BLACK, top = GREEN_DK }, case = { frame = BLACK, stock = { GOLD, RED, CYAN, MAGENTA, GOLD } },
                   art = { GOLD, MAGENTA } },
  prize  = theme { floor = { "carpet", a = RED, b = GOLD, c = WHITE }, wall = { skirt = BLACK, wains = BURGUNDY, rail = GOLD, paper = CREAM, stripe = GOLD, cornice = GOLD },
                   counter = { body = BLACK, top = GOLD, front = "glass", accent = GOLD },
                   tabl = { leg = BLACK, top = GOLD }, case = { frame = BLACK, stock = { GOLD, CYAN, PINK, WHITE, GOLD } },
                   art = { GOLD, RED } },
}

Kit.MAPS = {
  CELADON_MART_1F = "store1", CELADON_MART_2F = "store2", CELADON_MART_3F = "store3",
  CELADON_MART_4F = "store4", CELADON_MART_5F = "store5", CELADON_MART_ROOF = "roof",
  CELADON_MART_ELEVATOR = "lift",
  CELADON_MANSION_1F = "mansion1", CELADON_MANSION_2F = "mansion2", CELADON_MANSION_3F = "studio",
  CELADON_MANSION_ROOF = "terrace", CELADON_MANSION_ROOF_HOUSE = "attic",
  CELADON_CHIEF_HOUSE = "chief", CELADON_DINER = "diner", CELADON_HOTEL = "hotel",
  CELADON_GYM = "gym", GAME_CORNER = "casino", GAME_CORNER_PRIZE_ROOM = "prize",
}

-- ------------------------------------------------------------- reading a cell --
-- kinds: W wall, C counter, T table (desk, bed), B bookcase, F floor (and what
-- stands on it as a cut-out), "-" nothing of ours (void, stairs, water)
local SOLID = { wall = "W", counter = "C", table = "T", desk = "T", bed = "T", bookcase = "B" }
local OVER = { ground = true, stool = true, billboard = true, prop = true, cutout = true, cylinder = true,
               signpost = true, relief = true }
local function kindOf(class)
  if not class then return "-" end
  return SOLID[class] or (OVER[class] and "F") or "-"
end

-- `classAt(tx, ty)` -> class, height (Structures' own answer for that tile).
-- Answers a key for the cell whose top-left tile is (tx, ty), or nil.
function Kit.spec(mapId, classAt, tx, ty)
  if Kit.ENABLED == false then return nil end
  local name = Kit.MAPS[mapId]
  if not name then return nil end
  local T = THEMES[name]
  local parts, any = {}, false
  local function tile(x, y, north)
    local class, h = classAt(x, y)
    local k = kindOf(class)
    if k ~= "-" then any = true end
    h = tonumber(h) or 0
    if k == "W" then
      -- a BACK wall: nothing but wall (or nothing at all) for three tiles north of it
      local back = not T.wall.low
      if back and north then
        for d = 1, 3 do
          local c = classAt(x, y - d)
          if c and c ~= "wall" and c ~= "void" then back = false break end
        end
      end
      h = back and Kit.TALL or min(max(h, 8), Kit.LOW)
    elseif k == "F" or k == "-" then
      h = 0
    else
      h = max(4, min(h, 32))
    end
    return k .. h
  end
  for _, o in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
    parts[#parts + 1] = tile(tx + o[1], ty + o[2], true)
  end
  if not any then return nil end
  -- the eight tiles round it, for the phantoms: N N, E E, S S, W W
  for _, o in ipairs({ { 0, -1 }, { 1, -1 }, { 2, 0 }, { 2, 1 }, { 0, 2 }, { 1, 2 }, { -1, 0 }, { -1, 1 } }) do
    parts[#parts + 1] = tile(tx + o[1], ty + o[2], true)
  end
  local cx, cy = floor(tx / 2), floor(ty / 2)
  return name .. "|" .. table.concat(parts, ",") .. "|" .. (cx % 2) .. (cy % 2) .. (hash(cx, 3, 1) % 3)
end

-- -------------------------------------------------------------- building it --
local function frontOf(T, style, u, y, h)
  local c = T.counter
  if style == "slot" then                              -- a machine every eight: a lit screen, reels, a tray
    local k = u % 8
    if k == 0 or k == 7 then return sw(c.body, 1) end
    if y >= h - 4 and y <= h - 2 then return sw(CYAN, 4 + (k + y) % 2) end
    if y == h - 5 then return sw(c.accent, 5) end
    if y <= 2 then return sw(CHROME, 3) end
    return sw(c.body, 4)
  elseif style == "bar" then                           -- chrome bands on enamel
    if y % 3 == 1 then return sw(CHROME, 5) end
    return sw(c.body, 4)
  elseif style == "glass" then                         -- a display case: goods behind glass
    if y <= 1 or y >= h - 2 or u % 8 == 0 then return sw(c.body, 3) end
    if y == 3 or y == 4 then return sw(T.case.stock[floor(u / 3) % #T.case.stock + 1], 5) end
    return sw(BLUE_PALE, 5)
  end
  if y <= 1 then return sw(c.body, 1) end              -- panelled
  if u % 8 == 0 or y == h - 2 then return sw(c.body, 2) end
  if u % 8 == 4 and y == floor(h / 2) then return sw(c.accent, 5) end
  return sw(c.body, 4 + floor(u / 8) % 2)
end

function Kit.model(sp, key)
  if not sp or sp.W ~= Kit.SHEET_W or sp.H ~= Kit.SHEET_H then
    return nil, "sheet is not " .. Kit.SHEET_W .. "x" .. Kit.SHEET_H
  end
  local name, body, tail = key:match("^([^|]+)|([^|]+)|(%d+)$")
  local T = THEMES[name or ""]
  if not T then return nil, "no such room: " .. tostring(key) end
  local kinds, heights = {}, {}
  for part in body:gmatch("[^,]+") do
    kinds[#kinds + 1] = part:sub(1, 1)
    heights[#heights + 1] = tonumber(part:sub(2)) or 0
  end
  local ox, oz = tonumber(tail:sub(1, 1)) * 16, tonumber(tail:sub(2, 2)) * 16
  local hung = tonumber(tail:sub(3, 3)) == 0
  local lay = FLOOR[T.floor[1]]
  local W = T.wall

  -- which of the twelve tiles a voxel column stands in: 1..4 ours, 5..12 round it
  local function slot(x, z)
    local tx, tz = floor(x / 8), floor(z / 8)
    if tz == -1 then return 5 + tx end
    if tx == 2 then return 7 + tz end
    if tz == 2 then return 9 + tx end
    if tx == -1 then return 11 + tz end
    return tz * 2 + tx + 1
  end
  local function solidAt(x, z)
    if x < -8 or x > 23 or z < -8 or z > 23 then return 0 end
    if (x < 0 or x > 15) and (z < 0 or z > 15) then return 0 end
    return heights[slot(x, z)] or 0
  end

  local function at(x, y, z)
    local inside = x >= 0 and x <= 15 and z >= 0 and z <= 15
    if not inside then
      if (x < 0 or x > 15) and (z < 0 or z > 15) then return nil end
      local i = slot(x, z)
      local k, h = kinds[i], heights[i]
      if y == 0 and k ~= "-" and k ~= nil then return -1 end          -- its floor, its foot
      return (h and y < h and k ~= "F") and -1 or nil                -- Buildings.PHANTOM
    end
    local i = slot(x, z)
    local k, h = kinds[i], heights[i]
    if k == "-" then return nil end
    if k == "F" then return y == 0 and lay(T.floor, x + ox, z + oz) or nil end
    if y >= h then return nil end
    local u = x + ox
    if k == "W" then
      if y <= 1 then return sw(W.skirt, 3) end
      if h < Kit.TALL then                                           -- a low wall: a capped dwarf wall
        if y >= h - 2 then return sw(W.rail, 5) end
        return sw(W.wains, (u % 8 == 0 or (z + oz) % 8 == 0) and 2 or 4)
      end
      if y >= h - 3 then return sw(W.cornice, y == h - 3 and 2 or 5) end
      if y == 11 then return sw(W.rail, 5) end
      if y < 11 then return sw(W.wains, (u % 8 == 0 or y == 2) and 2 or 4) end
      -- a picture on the face that looks south, where there is one
      local face = solidAt(x, z + 1) <= y
      if hung and face and x >= 3 and x <= 12 and y >= 14 and y <= 22 and kinds[slot(x < 8 and 8 or 7, z)] == "W" then
        if x == 3 or x == 12 or y == 14 or y == 22 then return sw(GOLD, 3) end
        local dx, dy = x - 7.5, y - 18
        if dx * dx + dy * dy < 5 then return sw(T.art[2], 5) end
        return sw(T.art[1], y <= 16 and 2 or 4 + (x + y) % 2)
      end
      return sw((u % 8 == 0) and W.stripe or W.paper, 4 + floor(u / 8) % 2)
    elseif k == "C" then
      if y == h - 1 then
        -- seen from above a counter is mostly its TOP, so the top says what it is too:
        -- a machine every eight with its lit panel toward the player, a bar's chrome
        -- edge, a display case's glass with the goods under it
        local style, c = T.counter.front, T.counter
        if style == "slot" then
          if u % 8 == 0 or u % 8 == 7 then return sw(c.body, 1) end
          if z % 8 >= 5 then return sw(CYAN, 4 + u % 2) end
          if z % 8 == 4 then return sw(c.accent, 5) end
          return sw(c.top, 3)
        elseif style == "bar" then
          return sw((z % 8 == 7 or z % 8 == 0) and CHROME or c.top, 5)
        elseif style == "glass" then
          if u % 8 == 0 or z % 8 == 0 or z % 8 == 7 then return sw(c.body, 3) end
          return sw((u % 3 == 1 and z % 3 == 1) and T.case.stock[floor(u / 3) % #T.case.stock + 1] or BLUE_PALE, 5)
        end
        return sw(c.top, 4 + ((x + z) % 7 == 0 and 1 or 0))
      end
      if solidAt(x, z + 1) <= y then return frontOf(T, T.counter.front, u, y, h) end
      return sw(T.counter.body, 3)
    elseif k == "T" then
      local lx, lz = x % 8, z % 8
      if y >= h - 2 then
        if T.tabl.cloth and y == h - 1 then
          local rim = solidAt(x - 1, z) < h or solidAt(x + 1, z) < h or solidAt(x, z - 1) < h or solidAt(x, z + 1) < h
          return sw(T.tabl.cloth, rim and 2 or 5)
        end
        return sw(T.tabl.top, 4 + (u % 8 == 0 and -2 or 0))
      end
      -- a leg at every corner of the table that is a corner of the room's, not of a tile
      local edgeX = (lx <= 1 and solidAt(x - 2, z) < h) or (lx >= 6 and solidAt(x + 2, z) < h)
      local edgeZ = (lz <= 1 and solidAt(x, z - 2) < h) or (lz >= 6 and solidAt(x, z + 2) < h)
      if edgeX and edgeZ then return sw(T.tabl.leg, 3) end
      return y == 0 and lay(T.floor, x + ox, z + oz) or nil
    end
    -- a case: a frame, shelves every six, stock on them, the back solid
    local front = solidAt(x, z + 1) <= y
    if y == h - 1 or y <= 1 then return sw(T.case.frame, 3) end
    if not front then return sw(T.case.frame, 2) end
    if u % 8 == 0 or (y - 2) % 6 == 0 then return sw(T.case.frame, 4) end
    local shelf, col = floor((y - 2) / 6), floor(u / 2)
    local stock = T.case.stock
    if (y - 2) % 6 >= 4 - hash(col, shelf, 5) % 2 then return sw(BLACK, 2) end      -- the gap over the goods
    return sw(stock[(col + shelf * 2 + hash(col, shelf, 1)) % #stock + 1], 3 + (col + y) % 3)
  end

  local mask, top = {}, 1
  for i = 1, 4 do
    mask[i] = kinds[i] ~= "F" and kinds[i] ~= "-"
    if heights[i] > top then top = heights[i] end
  end
  return { at = at, W = 16, xmin = -1, xmax = 16, zmin = -1, zmax = 16, ytop = top,
           claimMask = mask, noFigure = false }
end

return Kit
