-- Voxel world mode: the BRIDGES and piers of Kanto, built as bridges.
--
-- The overworld draws every bridge, pier and boardwalk as one tile ($3C, four
-- to a cell): Route 12's long pier, Nugget Bridge, Vermilion's dock, the
-- walks of Routes 13, 20 and 21. The mesher laid that tile flat at ground
-- height with a bank dropping to the water on either side -- a causeway
-- wearing a drawing of planks. What stands here instead is timber:
--
--   the deck      boards lying ACROSS the way you walk, DECK voxels above the
--                 ground so it clears the water, stepping down to every side
--                 you can walk off it onto land
--   the edge      a beam along every railed side, knee braces under it
--   posts         square timber OUTSIDE the deck (the whole width stays
--                 walkable), one at every cell's low end, at the corners and
--                 wherever a rail stops: a dark foot, a stone cap proud all
--                 round, and under the deck the pile, wet and weeded, in a
--                 stone footing at the waterline
--   the railing   two rails between the posts, on every side that looks onto
--                 water or onto land nobody can walk (Nugget Bridge's trees)
--                 -- NEVER on walkable land: that is a way on or off
--   lanterns      on the posts of every other cell: an iron frame, lit glass,
--                 a stepped roof. They burn after dark (`lights`)
--
-- The water runs UNDER the bridge (`overWater`: the mesher keeps these cells
-- water, see ChunkMesher) unless the bridge stands over land.
--
-- One model per SIGNATURE, which is a fact about the placement. The model is
-- sunk `SINK` voxels so its piles can reach below the ground plane emit
-- starts from, and overhangs its cell by MARGIN for the posts.
--
-- The sheet (assets/buildings/bridge_kit.png) is painted by
-- tools/bridge_sheet.py. Nothing here is extracted from the ROM.

local V = ...

local Kit = { SHEET = "assets/buildings/bridge_kit.png", SHEET_W = 32,
              TILE = 60, WATER = 20,
              SINK = 8,        -- the piles' reach below the ground plane (the water
              --                  is opaque by then, and every row is quads)
              DECK = 6,        -- the walking surface, above the ground plane: high
              --                  enough that the water is SEEN to run under it,
              --                  between the piles and below the edge beam
              RAIL_H = 9, LAMP_EVERY = 2, MARGIN = 5 }

local floor = math.floor
local C = 16

-- row 16 of the sheet: tools/bridge_sheet.py MATERIALS, in the same order
local ROW = 16 * Kit.SHEET_W
local T = { post = ROW, postDark = ROW + 1, beam = ROW + 2, pile = ROW + 3,
            wet = ROW + 4, weed = ROW + 5, capA = ROW + 6, capB = ROW + 7,
            iron = ROW + 8, glass = ROW + 9, glow = ROW + 10,
            railTop = ROW + 11, rail = ROW + 12, footing = ROW + 13 }
Kit.T = T
-- The glass's two texels as a UV rect of the sheet: VoxelScene hands it to
-- Voxel3D.lantern for this sheet's draws, and EVERY pane burns after dark
-- -- the lamp pools only ever reach the eight lanterns nearest the player.
Kit.BANDS = 4
Kit.GLASS_UV = { 9 / 32, 16 / (32 * Kit.BANDS), 11 / 32, 17 / (32 * Kit.BANDS) }
-- The sheet is BANDS identical copies stacked down it, and the copy a voxel
-- wears is how much lantern light reaches it: the shader adds the lamps'
-- colour by the band after dark. Baked, because a pier has sixty lanterns
-- and the scene has eight lamp pools. { bands, strength }, REACH in voxels.
Kit.GLOW = { Kit.BANDS, 0.6 }
Kit.REACH = 34

-- What the cell whose top-left tile is (tx, ty) is: b(ridge), w(ater),
-- l(and you can walk on), t(rees, or anything else that blocks)
local function kindAt(tileAt, walkAt, tx, ty)
  local a, b = tileAt(tx, ty), tileAt(tx + 1, ty)
  local c, d = tileAt(tx, ty + 1), tileAt(tx + 1, ty + 1)
  if a == Kit.TILE and b == a and c == a and d == a then return "b" end
  local W = Kit.WATER
  if a == W or b == W or c == W or d == W then return "w" end
  if walkAt and not walkAt(floor(tx / 2), floor(ty / 2)) then return "t" end
  return "l"
end

-- how many bridge cells run on from (tx, ty) along (dx, dy), up to six
local function reach(tileAt, tx, ty, dx, dy)
  local n = 0
  while n < 6 and kindAt(tileAt, nil, tx + (n + 1) * dx, ty + (n + 1) * dy) == "b" do
    n = n + 1
  end
  return n
end

-- The placement's signature, and the cache key's tail: the kinds of the
-- cells N E S W, then NE SE SW (whether a rail carries on into the next
-- cell), the axis it runs along, W(et) or D(ry), L for a lantern.
-- `walkAt(cx, cy)`: can that CELL be walked on (nil: all land can).
function Kit.signature(tileAt, tx, ty, walkAt)
  if Kit.ENABLED == false then return nil end
  local function k(dx, dy) return kindAt(tileAt, walkAt, tx + dx, ty + dy) end
  local ns = reach(tileAt, tx, ty, 0, -2) + reach(tileAt, tx, ty, 0, 2)
  local ew = reach(tileAt, tx, ty, -2, 0) + reach(tileAt, tx, ty, 2, 0)
  local axis = ew > ns and "x" or "z"
  -- over water, or over land (Nugget Bridge): what lies past the bridge's
  -- own cells, looking each way
  local wet = false
  for _, d in ipairs({ { 0, -2 }, { 2, 0 }, { 0, 2 }, { -2, 0 } }) do
    local r = reach(tileAt, tx, ty, d[1], d[2]) + 1
    if kindAt(tileAt, nil, tx + r * d[1], ty + r * d[2]) == "w" then wet = true end
  end
  local lamp = floor((axis == "x" and tx or ty) / 2) % Kit.LAMP_EVERY == 0
  return k(0, -2) .. k(2, 0) .. k(0, 2) .. k(-2, 0)
         .. k(2, -2) .. k(2, 2) .. k(-2, 2)
         .. axis .. (wet and "W" or "D") .. (lamp and "L" or "")
end

-- A side's frame: `d` is how deep into the cell a voxel stands from that
-- side's edge (negative: outside it), `a` where it stands along it. `lo` and
-- `hi` are the sides `a` runs from and toward, `diag` the signature's
-- character for the cell past the `hi` corner.
local SIDES = {
  { i = 1, lo = 4, hi = 2, diag = 5, f = function(x, z) return z, x end },           -- north
  { i = 2, lo = 1, hi = 3, diag = 6, f = function(x, z) return C - 1 - x, z end },   -- east
  { i = 3, lo = 4, hi = 2, diag = 6, f = function(x, z) return C - 1 - z, x end },   -- south
  { i = 4, lo = 1, hi = 3, diag = 7, f = function(x, z) return x, z end },           -- west
}

function Kit.model(sp, sig)
  if not sp or sp.W ~= Kit.SHEET_W then
    return nil, "sheet is not " .. Kit.SHEET_W .. " wide"
  end
  local function ch(i) return sig:sub(i, i) end
  local axis, wet, lamp = ch(8), ch(9) == "W", ch(10) == "L"
  local G, D = Kit.SINK, Kit.DECK        -- model y of the ground plane
  local deckRegion = axis == "z" and 0 or C

  -- stepped: walkable land, a way on or off. railed: water, or blocked land.
  local railed, stepped = {}, {}
  for _, S in ipairs(SIDES) do
    stepped[S.i] = ch(S.i) == "l"
    railed[S.i] = ch(S.i) == "w" or ch(S.i) == "t"
  end
  -- Where a side's posts stand along it (the `a` of their first voxel; a
  -- post is 4 square). The low end always has one -- it is the last cell's
  -- high end. A corner of two rails shares ONE post, outside both.
  local slots = {}
  for _, S in ipairs(SIDES) do
    local list = {}
    if railed[S.i] then
      list[1] = railed[S.lo] and -4 or 0
      local on = ch(S.hi) == "b" and (ch(S.diag) == "w" or ch(S.diag) == "t")
      if railed[S.hi] then list[2] = C
      elseif not on then list[2] = C - 4 end
    end
    slots[S.i] = list
  end

  -- the deck's top at (x, z): DECK, stepping down to the land a voxel a row
  local function deckTop(x, z)
    local h = D
    for _, S in ipairs(SIDES) do
      if stepped[S.i] then
        local d = S.f(x, z)
        if d + 1 < h then h = d + 1 end
      end
    end
    return G + h                          -- first EMPTY y above the boards
  end

  -- One post, in its own frame: (pa, pd) 0..3 is the timber, -1..4 the ring
  -- the cap, the footing and the lantern's roof stand proud by.
  local FOOT = wet and -3 or 0           -- the footing's first row (world y)
  local FOOT_TOP = wet and -1 or 1
  local CAP = D + Kit.RAIL_H             -- the cap's
  local LAMP = CAP + 2                   -- the lantern's
  local function post(pa, pd, wy)
    local core = pa >= 0 and pa <= 3 and pd >= 0 and pd <= 3
    if wy >= FOOT and wy <= FOOT_TOP then
      return wy == FOOT_TOP and T.capB or T.footing
    end
    if wy >= CAP and wy <= CAP + 1 then return wy == CAP and T.capB or T.capA end
    if lamp and wy == LAMP + 6 then return T.iron end          -- the roof's eave
    if not core then return nil end
    if wy < D then
      -- the pile: wet where the water laps it, weeded below
      if not wet or wy >= 0 then return T.pile end
      if wy >= -3 then return T.wet end
      return ((pa + pd + wy) % 3 == 0) and T.weed or T.wet
    end
    if wy < CAP then
      return (wy < D + 2 or wy == CAP - 1) and T.postDark or T.post
    end
    if not lamp then return wy == LAMP and T.capA or nil end
    local edge = (pa == 0 or pa == 3) and (pd == 0 or pd == 3)
    if wy == LAMP then return T.iron end
    if wy <= LAMP + 5 then
      if edge then return T.iron end
      return wy == LAMP + 3 and T.glow or T.glass
    end
    if wy == LAMP + 7 then return T.iron end
    if wy == LAMP + 8 and pa >= 1 and pa <= 2 and pd >= 1 and pd <= 2 then
      return T.iron
    end
    return nil
  end

  local function inner(x, y, z)
    if x >= 0 and x < C and z >= 0 and z < C then
      local top = deckTop(x, z)
      if y < top and y >= top - 2 then    -- the boards, two thick
        return deckRegion + z * Kit.SHEET_W + x
      end
    end
    local wy = y - G                      -- world y
    for _, S in ipairs(SIDES) do
      if railed[S.i] then
        local d, a = S.f(x, z)
        if d <= 0 and d >= -5 then
          local list = slots[S.i]
          for n = 1, 2 do
            local s = list[n]
            if s and a >= s - 1 and a <= s + 4 then
              local v = post(a - s, d + 4, wy)
              if v then return v end
            end
          end
          -- between the posts: the edge beam, the rails, the knee braces
          local from, to = list[1] + 4, (list[2] or C) - 1
          if a >= from and a <= to then
            if d == -1 and wy >= D - 3 and wy < D then return T.beam end
            if d == -2 then
              if wy == D + 8 then return T.railTop end
              if wy == D + 7 or wy == D + 4 or wy == D + 3 then return T.rail end
            end
            if wet and (d == -2 or d == -3) then
              local k = wy - (D - 8)      -- 1..4, rising away from a post
              if k >= 1 and k <= 4 and (a == from - 1 + k or a == to + 1 - k) then
                return T.beam
              end
            end
          end
        end
      end
    end
    return nil
  end

  -- The cells either side along the bridge answer as PHANTOMS where their
  -- boards are (the same formula, a cell over), so no face is drawn between
  -- one cell's deck and the next. Posts are left alone: a neighbour may not
  -- rail the side this one does.
  local at
  at = function(x, y, z)
    local v = inner(x, y, z)
    if v then return v end
    local ox, oz = (x == -1 or x == C), (z == -1 or z == C)
    if ox == oz or x < -1 or x > C or z < -1 or z > C then return nil end
    local i = (z == -1 and 1) or (x == C and 2) or (z == C and 3) or 4
    if ch(i) == "b" and y < G + D and y >= G + D - 2 then
      return -1                           -- Buildings.PHANTOM
    end
    return nil
  end

  -- the lanterns' light: the middle of every post's glass. A post is found
  -- by its timber's first voxel in each frame; a corner's is found twice.
  local lights = {}
  if lamp then
    local sum = {}
    for x = -Kit.MARGIN, C - 1 + Kit.MARGIN do
      for z = -Kit.MARGIN, C - 1 + Kit.MARGIN do
        for _, S in ipairs(SIDES) do
          local d, a = S.f(x, z)
          for n, s in pairs(slots[S.i]) do
            if d >= -4 and d <= -1 and a >= s and a <= s + 3 then
              local t = sum[S.i * 2 + n] or { x = 0, z = 0 }
              t.x, t.z = t.x + (x + 0.5) / 16, t.z + (z + 0.5) / 16
              sum[S.i * 2 + n] = t
            end
          end
        end
      end
    end
    local seen = {}
    for _, t in pairs(sum) do
      local id = floor(t.x * 2 + 0.5) * 1024 + floor(t.z * 2 + 0.5)
      if not seen[id] then
        seen[id] = true
        lights[#lights + 1] = { x = t.x, z = t.z, y = LAMP + 3 }
      end
    end
  end

  -- Baked lamplight. This cell's lanterns, or -- the lanterns stand on every
  -- other cell -- the ones the cells before and after it carry, which are
  -- this cell's own post places a cell along.
  local sources = {}
  if lamp then
    sources = lights
  else
    local lo, hi = axis == "z" and 1 or 4, axis == "z" and 3 or 2
    for x = -Kit.MARGIN, C - 1 + Kit.MARGIN do
      for z = -Kit.MARGIN, C - 1 + Kit.MARGIN do
        for _, S in ipairs(SIDES) do
          local d, a = S.f(x, z)
          for _, s in pairs(slots[S.i]) do
            if d == -3 and a == s + 1 then
              for _, e in ipairs({ { lo, -C }, { hi, C } }) do
                if ch(e[1]) == "b" then
                  sources[#sources + 1] = {
                    x = x + 1 + (axis == "x" and e[2] or 0),
                    z = z + 1 + (axis == "z" and e[2] or 0), y = LAMP + 3 }
                end
              end
            end
          end
        end
      end
    end
  end
  local BAND = 32 * Kit.SHEET_W
  local plain = at
  at = function(x, y, z)
    local v = plain(x, y, z)
    if not v or v < 0 or v == T.glass or v == T.glow then return v end
    -- a cell in the middle of a wide pier has no post of its own to measure
    -- from: it takes the dim band, not the dark one, or it reads as a hole
    if #sources == 0 then return v + BAND end
    local best = Kit.REACH
    for _, L in ipairs(sources) do
      local dx, dy, dz = x + 0.5 - L.x, (y - G - L.y) * 0.5, z + 0.5 - L.z
      local d = math.sqrt(dx * dx + dy * dy + dz * dz)
      if d < best then best = d end
    end
    return v + floor((1 - best / Kit.REACH) * (Kit.BANDS - 1) + 0.5) * BAND
  end

  -- Wet wood is dark wood: everything under the deck, darker toward the
  -- bed. And the glass is LIT, whichever way its face looks.
  local function tint(y, i, _, shade)
    i = i % BAND
    if i == T.glass or i == T.glow then return 1.2 / (shade or 1) end
    local wy = y - G
    if wy >= D - 3 then return 1 end
    if wy >= -2 then return 0.82 end
    return 0.62
  end

  local M = Kit.MARGIN
  return { at = at, W = C, ytop = G + LAMP + 8,
           xmin = -M, xmax = C - 1 + M, zmin = -M, zmax = C - 1 + M,
           tint = tint, crispTops = true, noDown = true,
           sink = G, lift = D, overWater = wet and Kit.WATER or nil,
           lights = #lights > 0 and lights or nil }
end

return Kit
