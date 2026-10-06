-- Voxel world mode: the HOUSES of Cerulean and Celadon, outside -- twenty-five
-- of them, and no two alike.
--
-- Each is built from its Yellow drawing first and from whoever lives in it
-- second. The drawing gives the FORM: Cerulean's houses are one long low
-- hipped roof over a white wall, a door at the west end and two pairs of
-- windows (data/voxel_heights.lua `gabled_house_wide`, `gabled_block_6x2`);
-- Celadon's are flat-roofed city blocks, a lattice for a roof, one band of
-- six windows under the cornice and the door low on the left
-- (`flat_commercial`, `flat_block_*`). The Bike Shop is Celadon's block in
-- Cerulean's blue. Those stay -- window for window, door for door -- and the
-- rest is who they are:
--
--   CERULEAN  white stucco on a river-stone plinth under glazed blue tile,
--             every roof its own blue --
--     BADGE    the medal collector's: a glass case of eight medals in a bay,
--              gilded finials on the ridge, a flag
--     TRASHED  the house the Rockets broke into: a tarp roped over the
--              roof, a window boarded, one cracked, caution tape along the
--              front, and the hole they came in by in the back wall
--     MELANIE  the carer's: a vine pergola over two pet beds and a trough,
--              a picket fence, herb beds, window boxes
--     DYE      the dyeworks (cerulean is a pigment): banners of blue cloth
--              drying on frames, two vats, a louvred vent along the ridge
--     PAINTER  a studio: a skylight in the south slope, every shutter a
--              different colour, an easel out front
--     BAKERY   a bread oven's broad chimney, awnings, loaves on a stall
--     GLASS    the glassworks: a brick BOTTLE KILN at the west end, its door
--              glowing, blue bottles lit along the sill
--     BIKE     the Bike Shop: a neon bicycle on the roof, bikes in a rack,
--              a wall of tyres
--   CELADON   (below, with its own language)
--
-- NO Nintendo mark is drawn (assets/buildings/LICENSE.md): medals are round
-- discs, the leaf is a leaf, the bicycle is a bicycle.
--
-- HOW IT STAYS CHEAP. The sheet (tools/town_houses.py) is STRIPS, as the
-- skyline's is (lib/CeladonTowerKit.lua): a row per material, 128 texels of
-- it, and a voxel answers `row * 128 + u` with u running along its wall --
-- so a course of brick, a slope of tile, a whole lattice deck merge into one
-- quad a run, texture and all (`stripSides`: the flanks too). Glass is marked
-- in the ALPHA (254 a window, lit by a hash of its room after dark; 253 a
-- sign, a neon, a furnace -- always) and lit by the scene shader
-- (Voxel3D.emissive), exactly as the skyline's is.
--
-- Same contract as lib/VermilionHouseKit.lua: chosen ONLY for these
-- placements (Buildings.build), cached per placement, and a kit that will not
-- build leaves the classic drawing standing. The door's cell keeps its lane:
-- nothing below head height in the last tile row across the door.
-- Coordinates are the plot's: x east, z south, y up. A person is sixteen
-- voxels. Nothing here is extracted from the ROM.
local Kit = { SHEET = "assets/buildings/town_houses.png", SHEET_W = 128 }

-- The sheet's rows, in order. tools/town_houses.py paints each by name.
Kit.ROWS = {
  -- ground
  "pave_cel", "joint_cel", "pave_cer", "joint_cer",
  -- walls
  "stucco_white", "stucco_cream", "stucco_sky", "stucco_mint", "stucco_rose", "render_white", "render_grey",
  "brick_red_a", "brick_red_b", "brick_buff_a", "brick_buff_b", "brick_dark_a", "brick_dark_b",
  "brick_blue_a", "brick_blue_b", "brick_cream_a", "brick_cream_b", "mortar", "mortar_dk",
  "jade_a", "jade_b", "jade_grout", "river_a", "river_b", "river_joint", "ashlar_a", "ashlar_b", "ashlar_joint",
  "koshi", "shoji", "board", "board_line", "wood", "wood_dk", "wood_lt", "bamboo",
  "marble_green", "terrazzo", "lacquer_red", "black_gloss", "chrome", "violet",
  "trim_white", "trim_cream", "dentil", "frieze_gold",
  -- glass and light
  "glass", "glass_shop", "glass_dark", "glass_crack",
  "sign_lit", "neon_pink", "neon_cyan", "neon_red", "neon_green", "neon_yellow", "bulbs", "lantern_red",
  "furnace", "bottle_glow",
  -- roofs
  "tcer_a", "tcer_b", "tcer_line", "tslate_a", "tslate_b", "tslate_line", "tindigo_a", "tindigo_b", "tindigo_line",
  "tteal_a", "tteal_b", "tteal_line", "tsky_a", "tsky_b", "tsky_line", "tnavy_a", "tnavy_b", "tnavy_line",
  "kawara_a", "kawara_b", "kawara_line", "tjade_a", "tjade_b", "tjade_line",
  "ridge_blue", "ridge_dark", "ridge_jade", "fascia",
  "lat_jade_0", "lat_jade_1", "lat_jade_2", "lat_jade_3", "lat_jade_4", "lat_jade_5", "lat_jade_6", "lat_jade_7",
  "lat_blue_0", "lat_blue_1", "lat_blue_2", "lat_blue_3", "lat_blue_4", "lat_blue_5", "lat_blue_6", "lat_blue_7",
  "sky_0", "sky_1", "sky_2", "sky_3", "sky_4", "sky_5", "sky_6", "sky_7",
  "gravel", "tar", "lead", "deck",
  -- growing things, water
  "grass", "grass_dk", "soil", "leaf", "leaf_dk", "leaf_lt", "moss", "sand", "sand_line", "rock", "water", "water_dk",
  "fl_red", "fl_pink", "fl_yellow", "fl_white", "fl_purple", "fl_blue", "fl_orange",
  -- cloth
  "cloth_indigo", "cloth_cer", "cloth_sky", "cloth_teal", "cloth_white", "cloth_red", "canvas",
  "awn_bw", "awn_rw", "awn_gw", "awn_rainbow", "tape", "tarp",
  -- plain
  "white", "black", "iron", "steel", "red", "yellow", "orange", "green", "blue", "purple", "pink",
  "gold", "brass", "copper", "verdigris", "navy", "cream", "brown", "shadow",
  "rb_1", "rb_2", "rb_3", "rb_4", "rb_5", "rb_6", "rb_7",
  -- things
  "poster_a", "poster_b", "poster_c", "books", "bread", "vase_cel", "record",
}
Kit.SHEET_H = #Kit.ROWS
local W = Kit.SHEET_W
local K = {}
for i, name in ipairs(Kit.ROWS) do K[name] = i - 1 end
setmetatable(K, { __index = function(_, name) error("TownHouseKit: no sheet row '" .. tostring(name) .. "'", 2) end })

local floor, abs, min, max, sqrt = math.floor, math.abs, math.min, math.max, math.sqrt

-- a texel: `row` at `u` along the run
local function T(row, u) return row * W + u % W end
-- a scatter: the same answer for the same voxel on every build
local function hash(a, b, c) return (a * 7919 + b * 104729 + (c or 0) * 15485863 + a * b * 31 + a * a * 7) % 1024 end
local atan2 = math.atan2 or math.atan

-- ------------------------------------------------------------ wall skins --
-- skin(u, y) -> texel. Brick lies in courses three voxels tall, the bed
-- joint on the bottom row, alternate courses a half-brick along.
local function brick(a, b, joint)
  return function(u, y)
    if y % 3 == 0 then return T(joint or K.mortar, u) end
    return T(floor(y / 3) % 2 == 0 and a or b, u)
  end
end
local function plain(row) return function(u) return T(row, u) end end
local function coursed(a, b, joint, h)             -- stone: courses `h` tall
  return function(u, y)
    if y % h == 0 then return T(joint, u) end
    return T(floor(y / h) % 2 == 0 and a or b, u)
  end
end
local RIVER = coursed(K.river_a, K.river_b, K.river_joint, 3)
local ASHLAR = coursed(K.ashlar_a, K.ashlar_b, K.ashlar_joint, 4)

-- ----------------------------------------------------------------- glyphs --
local GLYPH = {
  A = { ".XXX.", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X" },
  B = { "XXXX.", "X...X", "X...X", "XXXX.", "X...X", "X...X", "XXXX." },
  C = { ".XXXX", "X....", "X....", "X....", "X....", "X....", ".XXXX" },
  D = { "XXXX.", "X...X", "X...X", "X...X", "X...X", "X...X", "XXXX." },
  E = { "XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "XXXXX" },
  H = { "X...X", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X" },
  I = { "XXXXX", "..X..", "..X..", "..X..", "..X..", "..X..", "XXXXX" },
  K = { "X...X", "X..X.", "X.X..", "XX...", "X.X..", "X..X.", "X...X" },
  M = { "X...X", "XX.XX", "X.X.X", "X.X.X", "X...X", "X...X", "X...X" },
  N = { "X...X", "XX..X", "X.X.X", "X..XX", "X...X", "X...X", "X...X" },
  O = { ".XXX.", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX." },
  P = { "XXXX.", "X...X", "X...X", "XXXX.", "X....", "X....", "X...." },
  R = { "XXXX.", "X...X", "X...X", "XXXX.", "X.X..", "X..X.", "X...X" },
  S = { ".XXXX", "X....", "X....", ".XXX.", "....X", "....X", "XXXX." },
  T = { "XXXXX", "..X..", "..X..", "..X..", "..X..", "..X..", "..X.." },
  Z = { "XXXXX", "....X", "...X.", "..X..", ".X...", "X....", "XXXXX" },
  [" "] = { ".....", ".....", ".....", ".....", ".....", ".....", "....." },
}
-- Is (x, y) lit in `word` drawn left to right from x0 with its top at y0?
local function inWord(word, x0, y0, x, y)
  local col, row = x - x0, y0 - y
  if col < 0 or row < 0 or row > 6 or col > #word * 6 - 2 then return false end
  local i = floor(col / 6) + 1
  local c = col % 6
  if c > 4 then return false end
  local g = GLYPH[word:sub(i, i)]
  return g ~= nil and g[row + 1]:sub(c + 1, c + 1) == "X"
end
local function wordWidth(word) return #word * 6 - 1 end
-- a picture drawn as strings, top row first; (x, y) inside it or not
local function inPic(pic, x0, y0, x, y)
  local r = pic[y0 - y + 1]
  local c = x - x0 + 1
  return r ~= nil and c >= 1 and c <= #r and r:sub(c, c) == "X"
end

-- ------------------------------------------------------------------ parts --
-- A part is a box that may answer for the voxels in it: f(x, y, z) returns a
-- texel, nil for air carved out of what stands there, or false to pass.
local function part(x0, x1, y0, y1, z0, z1, f) return { x0, x1, y0, y1, z0, z1, f } end

local function assemble(m, base, parts)
  local n = #parts
  local XM, ZM, YT = m.xmax, m.zmax, m.ytop
  m.at = function(x, y, z)
    if x < 0 or x > XM or z < 0 or z > ZM or y < 0 or y > YT then return nil end
    for i = 1, n do
      local p = parts[i]
      if x >= p[1] and x <= p[2] and y >= p[3] and y <= p[4] and z >= p[5] and z <= p[6] then
        local v = p[7](x, y, z)
        if v ~= false then return v end
      end
    end
    return base(x, y, z)
  end
  m.stripSides = true
  m.tint = function(y) return 0.88 + min(y / 30, 1) * 0.12 end
  return m
end

-- ---------------------------------------------------------------- windows --
-- A window let into a wall: `u` along it, `y` up, `depth` IN from the face
-- (0 = the face, -1 = the voxel standing proud of it). Answers a texel, nil
-- for a carved voxel, or false when it is not this window's.
--   W = { c, w2, y0, y1, double, arch, shut = row, box = row, glass = row }
local function window(W, u, y, depth)
  local du = u - W.c + 0.5
  local w2, y0, y1 = W.w2, W.y0, W.y1
  if abs(du) > w2 + (W.shut and 5 or 1.5) or y < y0 - 2 or y > y1 + 1 or depth < -1 or depth > 2 then return false end
  local inside = abs(du) <= w2 and y >= y0 and y <= y1
  if inside and W.arch then
    local spring = y1 - w2
    if y > spring and du * du + (y - spring) ^ 2 > w2 * w2 + 1 then inside = false end
  end
  if y == y0 - 1 and abs(du) <= w2 + 1.5 and depth <= 0 then return T(K.trim_white, u) end        -- the sill
  if W.box and depth == -1 and abs(du) <= w2 + 0.5 then                                            -- a window box
    if y == y0 - 2 then return T(K.wood_dk, u) end
    if y == y0 - 1 then return T((floor(du) % 3 == 0) and W.box or K.leaf, u) end
    if y == y0 then return (floor(du + 1) % 3 == 0) and T(W.box, u) or nil end
  end
  if W.shut and depth == -1 and abs(du) > w2 + 1 and abs(du) <= w2 + 5 and y >= y0 and y <= y1 then
    return T((y % 2 == 0) and W.shut or K.shadow, u)                                                -- louvred shutters
  end
  if not inside then
    if depth == 0 and abs(du) <= w2 + 1 and y >= y0 and y <= y1 + 1 then return T(W.frame or K.trim_white, u) end
    return false
  end
  if depth < 0 then return false end
  if depth < 2 then
    if depth == 1 and ((W.double and abs(du) < 1) or (W.transom and y == W.transom)) then
      return T(W.frame or K.trim_white, u)
    end
    return nil
  end
  return T(W.glass or K.glass, u)
end

-- the faces of a box a voxel lies on or just outside of: face, u, depth
-- (four deep: a door's alcove is)
local function faceOf(x, z, X0, X1, Z0, Z1)
  local inX, inZ = x >= X0 and x <= X1, z >= Z0 and z <= Z1
  if inX and inZ then
    if z >= Z1 - 4 then return "s", x, Z1 - z end
    if z <= Z0 + 4 then return "n", x, z - Z0 end
    if x >= X1 - 4 then return "e", z, X1 - x end
    if x <= X0 + 4 then return "w", z, x - X0 end
    return nil
  end
  if inX and z == Z1 + 1 then return "s", x, -1 end
  if inX and z == Z0 - 1 then return "n", x, -1 end
  if inZ and x == X1 + 1 then return "e", z, -1 end
  if inZ and x == X0 - 1 then return "w", z, -1 end
  return nil
end

local function windows(list, face, u, y, depth)
  for i = 1, #list do
    local Wn = list[i]
    if Wn.face == face then
      local v = window(Wn, u, y, depth)
      if v ~= false then return v end
    end
  end
  return false
end

-- A door: an alcove `deep` voxels into the wall, a frame, the leaf, a knob,
-- a glazed fanlight. D = { face, x0, x1, head, leaf = row, deep }
local function door(D, u, y, depth)
  if u < D.x0 or u > D.x1 or y < 1 or y > D.head + 1 or depth < 0 then return false end
  local deep = D.deep or 3
  if depth > deep then return false end
  if u == D.x0 or u == D.x1 or y == D.head + 1 then
    return depth == 0 and T(D.frame or K.trim_white, u) or false
  end
  if depth < deep then return nil end
  if y >= D.head - 3 then return T(K.glass, u) end                                -- the fanlight
  if y == D.head - 4 then return T(D.frame or K.trim_white, u) end
  local mid = floor((D.x0 + D.x1) / 2)
  if D.double and u == mid then return T(K.wood_dk, u) end
  if u == D.x1 - 2 and y == 8 then return T(K.brass, u) end
  if (u - D.x0) % 4 == 2 and y > 3 and y < D.head - 5 then return T(K.shadow, u) end   -- the panels' shadow
  return T(D.leaf, u)
end

-- ---------------------------------------------------------------- roofs --
-- A hipped roof over x0..x1, z0..z1, ridge along x: top(x, z) and the
-- distance up the slope `d`, whether it is the ridge, a hip or the eave.
local function hipRoof(R)
  local x0, x1, z0, z1, eave, pitch = R.x0, R.x1, R.z0, R.z1, R.eave, R.pitch
  local half = (z1 - z0) / 2
  local cap = R.cap
  return function(x, z)
    if x < x0 or x > x1 or z < z0 or z > z1 then return nil end
    local dx, dz = min(x - x0, x1 - x), min(z - z0, z1 - z)
    local d = min(dx, dz)
    local top = eave + floor(d * pitch)
    if R.kick then top = top + floor(max(0, R.kick - max(dx, dz) * R.kick / 12)) end   -- corners swept up
    local ridge = dz >= floor(half) and dx >= floor(half)
    local hip = abs(dx - dz) < 1 and not ridge
    if cap and top > cap then top = cap end
    return top, d, ridge, hip, dz <= dx
  end
end

-- tiles: a course line under each lap, alternate courses a half-tile along
local function tiles(a, b, line)
  return function(u, d)
    if d % 3 == 2 then return T(line, u) end
    return T(floor(d / 3) % 2 == 0 and a or b, u)
  end
end
local TILE = {
  cerulean = tiles(K.tcer_a, K.tcer_b, K.tcer_line), slate = tiles(K.tslate_a, K.tslate_b, K.tslate_line),
  indigo = tiles(K.tindigo_a, K.tindigo_b, K.tindigo_line), teal = tiles(K.tteal_a, K.tteal_b, K.tteal_line),
  sky = tiles(K.tsky_a, K.tsky_b, K.tsky_line), navy = tiles(K.tnavy_a, K.tnavy_b, K.tnavy_line),
  kawara = tiles(K.kawara_a, K.kawara_b, K.kawara_line), jade = tiles(K.tjade_a, K.tjade_b, K.tjade_line),
}

-- ------------------------------------------------------- Cerulean's house --
-- The long hipped house: 96 x 32, walls x 7..88 and z 3..23, the roof
-- overhanging to the plot's edges and five voxels over the front. S: skin,
-- plinth, wall (its top), roof { tile, pitch, ridge, fascia }, windows,
-- doors, chimneys { x, z, w, d, top, skin }, pave.
local function cottage(S)
  local PW, PD = 96, 32
  local X0, X1, Z0, Z1 = S.x0 or 7, S.x1 or 88, S.z0 or 3, S.z1 or 23
  local WALL = S.wall or 24
  local R = S.roof
  local roofAt = hipRoof({ x0 = R.x0 or 1, x1 = R.x1 or PW - 2, z0 = R.z0 or 0, z1 = R.z1 or 28,
                           eave = WALL + 1, pitch = R.pitch or 0.85, cap = R.cap, kick = R.kick })
  local tile = R.tile or TILE.cerulean
  local ridgeRow, fasciaRow = R.ridge or K.ridge_blue, R.fascia or K.fascia
  local skin = S.skin or plain(K.stucco_white)
  local plinth = S.plinth or 4
  local plinthSkin = S.plinthSkin or RIVER
  local wins, doors, chims = S.windows or {}, S.doors or {}, S.chimneys or {}
  local paveA, paveJ = S.pave or K.pave_cer, S.paveJoint or K.joint_cer
  local ytop = 0

  local function base(x, y, z)
    if y == 0 then
      if x % 16 == 0 or z % 16 == 0 then return T(paveJ, x) end
      return T(paveA, x)
    end
    local top, d, ridge, hip, slopeZ = roofAt(x, z)
    -- the chimneys: stuccoed stacks, a cap, an open flue
    for i = 1, #chims do
      local c = chims[i]
      if x >= c.x and x < c.x + c.w and z >= c.z and z < c.z + c.d and y <= c.top and top and y > top - 2 then
        if y >= c.top - 1 then
          if x > c.x and x < c.x + c.w - 1 and z > c.z and z < c.z + c.d - 1 then return y == c.top - 1 and T(K.black, x) or nil end
          return T(K.trim_white, x)
        end
        return (c.skin or skin)(x + z, y)
      end
    end
    if top and y <= top and y >= top - 1 then
      if d == 0 then return T(fasciaRow, x) end
      if ridge or hip then return T(ridgeRow, x) end
      return tile(slopeZ and x or z, d)
    end
    local inside = x >= X0 and x <= X1 and z >= Z0 and z <= Z1
    if inside and top and y < top - 1 then
      local face, u, depth = faceOf(x, z, X0, X1, Z0, Z1)
      if face then
        for i = 1, #doors do
          local D = doors[i]
          if D.face == face then
            local v = door(D, u, y, depth)
            if v ~= false then return v end
          end
        end
        local v = windows(wins, face, u, y, depth)
        if v ~= false then return v end
      end
      local edge = x == X0 or x == X1 or z == Z0 or z == Z1
      if not edge then return T(K.shadow, x) end
      local wu = (z == Z0 or z == Z1) and x or z
      if y <= plinth then return plinthSkin(wu, y) end
      if y == WALL or y == WALL - 1 then return T(K.trim_white, wu) end
      return skin(wu, y)
    end
    if top and y > 0 and y < top - 1 then
      local face, u, depth = faceOf(x, z, X0, X1, Z0, Z1)
      if face and depth == -1 then
        local v = windows(wins, face, u, y, depth)
        if v then return v end
      end
    end
    return nil
  end

  local lights, lanes = S.lights or {}, {}
  for _, D in ipairs(doors) do
    if D.face == "s" then
      lights[#lights + 1] = { x = D.x1 + 3, y = D.head, z = Z1 + 2 }
      lanes[#lanes + 1] = { D.x0 - 2, D.x1 + 1 }
    end
  end
  local c1 = chims[1]
  ytop = S.ytop or 72
  local m = { W = PW, xmin = 0, xmax = PW - 1, zmin = 0, zmax = PD - 1, ytop = ytop,
              lights = #lights > 0 and lights or nil, lanes = lanes,
              chimney = c1 and { x = c1.x + c1.w / 2, y = c1.top + 1, z = c1.z + c1.d / 2 } or nil }
  return m, base, { X0 = X0, X1 = X1, Z0 = Z0, Z1 = Z1, WALL = WALL, roofAt = roofAt, PW = PW, PD = PD }
end

-- the two pairs of windows every Cerulean house wears, and the single one
-- the doorless houses have where the door would be (the drawing's own)
local function ceruleanWindows(opts)
  opts = opts or {}
  local list = {
    { face = "s", c = 49, w2 = 7, y0 = 10, y1 = 19, double = true, transom = 16, shut = opts.shut, box = opts.box },
    { face = "s", c = 73, w2 = 7, y0 = 10, y1 = 19, double = true, transom = 16, shut = opts.shut, box = opts.box },
    { face = "n", c = 36, w2 = 5, y0 = 10, y1 = 19, double = true },
    { face = "n", c = 64, w2 = 5, y0 = 10, y1 = 19, double = true },
    { face = "e", c = 13, w2 = 3, y0 = 10, y1 = 19 }, { face = "w", c = 13, w2 = 3, y0 = 10, y1 = 19 },
  }
  if opts.single then list[#list + 1] = { face = "s", c = 22, w2 = 4, y0 = 10, y1 = 19, shut = opts.shut, box = opts.box } end
  if opts.shutters then                                   -- one row of shutters per window, in order
    local k = 0
    for _, Wn in ipairs(list) do
      if Wn.face == "s" then k = k + 1; Wn.shut = opts.shutters[k] end
    end
  end
  return list
end
local FRONT_DOOR = function(leaf) return { face = "s", x0 = 18, x1 = 30, head = 16, leaf = leaf } end

-- ---------------------------------------------------------------- shapes --
local function disc(cx, cy, r) return function(x, y) return (x - cx) ^ 2 + (y - cy) ^ 2 <= r * r end end
local function ring(cx, cy, r0, r1)
  return function(x, y)
    local q = (x - cx) ^ 2 + (y - cy) ^ 2
    return q <= r1 * r1 and q >= r0 * r0
  end
end
-- is (x, y) within `w` of the segment (ax, ay)-(bx, by)?
local function seg(ax, ay, bx, by, w)
  local dx, dy = bx - ax, by - ay
  local L = dx * dx + dy * dy
  return function(x, y)
    local t = L > 0 and ((x - ax) * dx + (y - ay) * dy) / L or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local px, py = ax + t * dx - x, ay + t * dy - y
    return px * px + py * py <= w * w
  end
end

-- A bicycle drawn in the x-y plane, `x0` its back wheel's hub, `y0` the
-- hubs' height, wheels of radius r. Answers the part of the bike or nil.
local function bicycle(x0, y0, r, frame)
  local x1 = x0 + r * 3.1                                     -- the front hub
  local rimA, rimB = ring(x0, y0, r - 1.2, r + 0.4), ring(x1, y0, r - 1.2, r + 0.4)
  local crank = { x0 + r * 1.35, y0 }
  local seatTop = { x0 + r * 0.95, y0 + r * 1.35 }
  local headTop = { x1 - r * 0.45, y0 + r * 1.45 }
  local bars = {
    seg(x0, y0, crank[1], crank[2], 0.7), seg(x0, y0, seatTop[1], seatTop[2], 0.7),
    seg(crank[1], crank[2], seatTop[1], seatTop[2], 0.8), seg(seatTop[1], seatTop[2], headTop[1], headTop[2], 0.8),
    seg(crank[1], crank[2], headTop[1], headTop[2], 0.8), seg(headTop[1], headTop[2], x1, y0, 0.7),
  }
  local seat = seg(seatTop[1] - 1.5, seatTop[2] + 1, seatTop[1] + 1.5, seatTop[2] + 1, 0.8)
  local bar = seg(headTop[1] - 1, headTop[2] + 1.5, headTop[1] + 1.5, headTop[2] + 1.5, 0.7)
  return function(x, y)
    if rimA(x, y) or rimB(x, y) then return "rim" end
    if (abs(x - x0) < 1 and abs(y - y0) < 1) or (abs(x - x1) < 1 and abs(y - y0) < 1) then return "hub" end
    if seat(x, y) or bar(x, y) then return "seat" end
    for i = 1, #bars do if bars[i](x, y) then return frame or "frame" end end
    return nil
  end
end

-- ================================================================ CERULEAN ==

local MEDALS = { K.steel, K.blue, K.orange, K.rb_4, K.pink, K.gold, K.red, K.green }

local function badge()
  local m, base, B = cottage({
    roof = { tile = TILE.cerulean, pitch = 0.9 },
    windows = ceruleanWindows({ shut = K.blue }),
    doors = { FRONT_DOOR(K.navy), { face = "n", x0 = 18, x1 = 30, head = 16, leaf = K.navy } },
    chimneys = { { x = 70, z = 6, w = 5, d = 5, top = 42 } },
  })
  local parts = {}
  -- the medal case: a glazed bay over the first pair of windows, eight
  -- medals on navy velvet behind the glass, its own little tiled roof
  parts[#parts + 1] = part(39, 59, 1, 25, 24, 28, function(x, y, z)
    local u = x
    if y <= 5 then return (x == 39 or x == 59 or z == 28) and RIVER(u, y) or T(K.shadow, x) end
    if y <= 20 then
      if x == 39 or x == 59 or y == 20 or y == 6 then return T(K.trim_white, x) end
      if z < 28 then return T(K.navy, x) end
      if (x - 39) % 5 == 0 then return T(K.trim_white, x) end
      -- the medals: two rows of four, gold-rimmed
      for i = 0, 7 do
        local mx, my = 43 + (i % 4) * 4.5, (i < 4) and 16 or 10.5
        local q = (x - mx) ^ 2 + (y - my) ^ 2
        if q <= 3.2 then return T(q <= 1.2 and MEDALS[i + 1] or K.gold, x) end
      end
      return T(K.glass_shop, x)
    end
    if y <= 21 + (28 - z) * 0.8 then return TILE.cerulean(x, 28 - z) end
    return false
  end)
  -- gilded finials at the ridge's two ends
  for _, fx in ipairs({ 15, 80 }) do
    parts[#parts + 1] = part(fx - 1, fx + 1, 34, 44, 13, 15, function(x, y, z)
      local top = B.roofAt(x, z)
      if not top or y <= top then return false end
      if y >= 41 then return ((x - fx) ^ 2 + (z - 14) ^ 2 + (y - 42) ^ 2 <= 2.5) and T(K.gold, x) or false end
      return (x == fx and z == 14) and T(K.gold, x) or false
    end)
  end
  -- a flagstaff at the west end, a navy flag with a gold disc
  parts[#parts + 1] = part(4, 14, 1, 49, 30, 30, function(x, y)
    if x == 4 then return y <= 48 and T(y >= 47 and K.gold or K.white, x) or false end
    if y >= 38 and y <= 45 then
      local sag = floor((x - 4) / 4)
      if y - sag < 38 then return false end
      return T((((x - 9) ^ 2 + (y - 41.5) ^ 2) <= 3) and K.gold or K.navy, x)
    end
    return false
  end)
  -- a clipped box hedge along the front, either side of the door
  parts[#parts + 1] = part(2, 95, 1, 5, 29, 31, function(x, y, z)
    if x >= 15 and x <= 33 then return false end
    if x >= 88 and x <= 94 then return false end
    if y == 5 and (x + z) % 3 == 0 then return false end
    return T((x * 3 + y + z) % 5 == 0 and K.leaf_dk or K.leaf, x)
  end)
  return assemble(m, base, parts)
end

local function trashed()
  local m, base, B = cottage({
    roof = { tile = TILE.slate, pitch = 0.9, ridge = K.ridge_dark },
    windows = ceruleanWindows(),
    doors = { FRONT_DOOR(K.red) },
    chimneys = { { x = 24, z = 6, w = 5, d = 5, top = 41 } },
  })
  local parts = {}
  -- the tarp roped over the hole in the south slope, sandbags at its corners
  parts[#parts + 1] = part(58, 82, 24, 44, 15, 27, function(x, y, z)
    local top = B.roofAt(x, z)
    if not top then return false end
    local corner = (x <= 59 or x >= 81) and (z <= 16 or z >= 26)
    if corner and y >= top + 1 and y <= top + 2 then return T(K.brown, x) end
    if y ~= top + 1 then return false end
    if (x - 58) % 7 == 0 or z == 21 then return T(K.canvas, x) end        -- the ropes
    return T(K.tarp, x)
  end)
  -- missing tiles: dark gaps and a loose tile or two slid down the slope
  parts[#parts + 1] = part(30, 50, 22, 40, 16, 27, function(x, y, z)
    local top = B.roofAt(x, z)
    if not top or y ~= top then return false end
    local h = hash(x, z)
    if h < 24 then return T(K.shadow, x) end
    return false
  end)
  -- the first window boarded up: planks across and a cross of two more
  parts[#parts + 1] = part(41, 57, 8, 21, 24, 24, function(x, y)
    local u = x - 41
    local cross = abs((y - 9) - u * 0.72) < 1 or abs((y - 9) - (16 - u) * 0.72) < 1
    if cross or y == 11 or y == 17 then return T((x + y) % 7 == 0 and K.wood_dk or K.wood, x) end
    return false
  end)
  -- the second one cracked
  parts[#parts + 1] = part(66, 80, 10, 19, 21, 21, function(x, y)
    if abs(x - 73) < 0.5 then return false end
    return T(K.glass_crack, x)
  end)
  -- caution tape along the front on three cones, clear of the door
  parts[#parts + 1] = part(34, 94, 1, 10, 29, 31, function(x, y, z)
    for _, cx in ipairs({ 35, 64, 93 }) do
      local dx, dz = x - cx, z - 30
      local r = 2.4 - y * 0.26
      if y <= 8 and dx * dx + dz * dz <= r * r then
        return T((y == 4 or y == 5) and K.white or K.orange, x)
      end
    end
    if z == 30 and y == 8 and x > 35 and x < 93 then return T(K.tape, x) end
    return false
  end)
  -- the back wall: the hole they came in by, and its rubble
  parts[#parts + 1] = part(14, 34, 1, 18, 0, 4, function(x, y, z)
    local jag = 16 - abs(x - 24) * 0.9 + (hash(x, 1) % 4) - 1.5
    if z >= 3 and z <= 4 and x >= 16 and x <= 32 and y <= jag then return nil end
    if z <= 2 and y <= 3 then
      local h = hash(x, z, y)
      local heap = 3 - abs(x - 24) * 0.25 - (2 - z) * 0.6
      if y <= heap and h % 3 ~= 0 then return RIVER(x, y + (h % 3)) end
      if y == 1 and h < 60 then return T(K.stucco_white, x) end
    end
    return false
  end)
  return assemble(m, base, parts)
end

local function melanie()
  local m, base, B = cottage({
    roof = { tile = TILE.teal, pitch = 0.85 },
    windows = ceruleanWindows({ shut = K.green, box = K.fl_pink }),
    doors = { FRONT_DOOR(K.yellow) },
    chimneys = { { x = 30, z = 6, w = 5, d = 5, top = 40 } },
  })
  local parts = {}
  -- a dormer in the south slope with a round window
  parts[#parts + 1] = part(62, 74, 26, 40, 12, 22, function(x, y, z)
    local top = B.roofAt(x, z)
    if not top or y < top - 1 then return false end
    local du = abs(x - 68)
    local gable = 37 - floor(du * 0.9)
    if y > gable then return false end
    if y >= gable - 1 then return TILE.teal(x, du) end
    if du > 5 then return false end
    if z == 22 then
      local q = (x - 68) ^ 2 + (y - 32) ^ 2
      if q <= 4.5 then return T(K.glass, x) end
      if q <= 9 then return T(K.trim_white, x) end
      return T(K.stucco_white, x)
    end
    if du == 5 then return T(K.stucco_white, z) end
    return T(K.shadow, x)
  end)
  -- the pergola over the east end: posts, beams, the vine over it all
  parts[#parts + 1] = part(58, 94, 1, 28, 24, 31, function(x, y, z)
    local post = (x == 60 or x == 75 or x == 91) and z == 30
    if post and y <= 24 then
      if (y + x) % 5 == 0 and y > 4 then return T(K.leaf_dk, x) end
      return T(K.wood, x)
    end
    if y == 25 and z == 30 and x >= 59 and x <= 92 then return T(K.wood_dk, x) end
    if y == 26 and z >= 29 and (x - 58) % 4 == 0 then return T(K.wood, x) end
    if y >= 26 and y <= 27 and z >= 29 then
      local h = hash(x, z, 3)
      if h % 5 < 3 then return T(h % 7 == 0 and K.fl_purple or (h % 2 == 0 and K.leaf or K.leaf_dk), x) end
    end
    -- hanging vine tassels
    if y >= 18 and y <= 25 and z == 31 and hash(x, 7) % 4 == 0 and y >= 18 + hash(x, 9) % 6 then
      return T(K.leaf_lt, x)
    end
    -- two pet beds and a trough under it
    for _, b in ipairs({ { 66, K.red }, { 81, K.blue } }) do
      local dx, dz = (x - b[1]) / 4.2, (z - 27) / 2.6
      local q = dx * dx + dz * dz
      if y <= 3 and q <= 1 then
        if y == 3 and q < 0.45 then return T(K.cream, x) end
        if y <= 2 or q > 0.55 then return T(b[2], x) end
      end
    end
    if x >= 86 and x <= 92 and z >= 25 and z <= 27 and y <= 4 then
      if y == 4 and x > 86 and x < 92 and z == 26 then return T(K.water, x) end
      return T(K.wood_dk, x)
    end
    return false
  end)
  -- a picket fence along the front, and herb beds at the west end
  parts[#parts + 1] = part(0, 57, 1, 7, 24, 31, function(x, y, z)
    if x >= 16 and x <= 32 then return false end
    if z == 31 and x >= 34 then
      if y == 3 or y == 5 then return T(K.trim_white, x) end
      if x % 2 == 0 and y <= 6 + (x % 4 == 0 and 1 or 0) then return T(K.trim_white, x) end
      return false
    end
    if x <= 14 and z >= 25 and z <= 30 then
      if x == 1 or x == 14 or z == 25 or z == 30 or x == 7 or x == 8 then return y <= 2 and T(K.wood, x) or false end
      if y <= 2 then return T(K.soil, x) end
      if y <= 5 and hash(x, z, y) % 3 ~= 0 then
        return T(((x + z) % 4 == 0 and y == 5) and K.fl_white or (x < 7 and K.leaf or K.leaf_lt), x)
      end
    end
    return false
  end)
  -- a leaf on a board by the door
  local LEAF = { "...XX", "..XXX", ".XXXX", "XXXX.", "XX.X.", "X...." }
  parts[#parts + 1] = part(33, 39, 11, 18, 24, 24, function(x, y)
    if x == 33 or x == 39 or y == 11 or y == 18 then return T(K.wood_dk, x) end
    return T(inPic(LEAF, 34, 17, x, y) and K.leaf or K.cream, x)
  end)
  return assemble(m, base, parts)
end

local function dye()
  local m, base, B = cottage({
    roof = { tile = TILE.indigo, pitch = 0.9, ridge = K.ridge_dark },
    windows = ceruleanWindows({ single = true }),
    chimneys = { { x = 78, z = 5, w = 5, d = 5, top = 41 } },
  })
  local parts = {}
  -- a louvred vent riding the ridge, and its own cap
  parts[#parts + 1] = part(30, 66, 34, 46, 11, 17, function(x, y, z)
    local top = B.roofAt(x, z)
    if not top or y <= top then return false end
    local k = y - top
    if k <= 3 then
      if x == 30 or x == 66 or z == 11 or z == 17 then
        if (x - 30) % 6 == 0 then return T(K.wood_dk, x) end
        return T((k % 2 == 0) and K.wood or K.shadow, x)
      end
      return T(K.shadow, x)
    end
    if k <= 6 and abs(z - 14) <= 7 - k then return TILE.indigo(x, 6 - k) end
    return false
  end)
  -- cloth drying on three frames: long banners, the dip darker at the foot
  local BANNERS = { { 30, 38, K.cloth_indigo, K.cloth_indigo }, { 58, 63, K.cloth_sky, K.cloth_cer },
                    { 83, 92, K.cloth_white, K.cloth_cer } }
  parts[#parts + 1] = part(28, 94, 1, 24, 27, 30, function(x, y, z)
    for _, b in ipairs(BANNERS) do
      local x0, x1 = b[1], b[2]
      if (x == x0 - 1 or x == x1 + 1) and z == 30 and y <= 23 then return T(K.wood, x) end
      if y == 23 and z == 30 and x >= x0 - 1 and x <= x1 + 1 then return T(K.wood_dk, x) end
      if x >= x0 and x <= x1 and y >= 3 and y <= 22 then
        local sway = floor((y + x) / 5) % 2
        if z == 29 - sway then
          local deep = (y < 10) and b[4] or b[3]
          return T(deep, x)
        end
      end
    end
    return false
  end)
  -- two vats of dye at the west end, and blue where it splashed
  parts[#parts + 1] = part(0, 16, 0, 8, 24, 31, function(x, y, z)
    for i, c in ipairs({ { 5, 27.5, K.cloth_indigo }, { 12.5, 28, K.cloth_cer } }) do
      local q = (x - c[1]) ^ 2 + (z - c[2]) ^ 2
      if q <= 12.5 and y >= 1 and y <= 7 then
        if q <= 7 and y >= 6 then return y == 6 and T(c[3], x) or nil end
        if y == 2 or y == 6 then return T(K.iron, x) end
        return T(K.wood, x + i)
      end
    end
    if y == 0 and hash(x, z) % 6 == 0 then return T(K.cloth_indigo, x) end
    return false
  end)
  return assemble(m, base, parts)
end

local function painter()
  local m, base, B = cottage({
    roof = { tile = TILE.sky, pitch = 0.85 },
    windows = ceruleanWindows({ single = true, shutters = { K.red, K.yellow, K.green } }),
    chimneys = { { x = 12, z = 6, w = 5, d = 5, top = 40 } },
  })
  local parts = {}
  -- the studio's skylight: a band of glass in the south slope
  parts[#parts + 1] = part(38, 82, 20, 40, 17, 25, function(x, y, z)
    local top = B.roofAt(x, z)
    if not top or y ~= top then return false end
    if x == 38 or x == 82 or z == 17 or z == 25 then return T(K.trim_white, x) end
    if (x - 38) % 11 == 0 then return T(K.iron, x) end
    return T(K.glass, x)
  end)
  -- an easel with a canvas out front: sky, hills, a sun
  parts[#parts + 1] = part(34, 46, 1, 21, 27, 30, function(x, y, z)
    if z == 29 and (x == 35 or x == 45) and y <= 12 then return T(K.wood, x) end
    if z == 30 and x == 40 and y <= 20 then return T(K.wood, x) end
    if z == 28 and x >= 35 and x <= 45 and y >= 9 and y <= 19 then
      if x == 35 or x == 45 or y == 9 or y == 19 then return T(K.wood_dk, x) end
      if (x - 42) ^ 2 + (y - 16) ^ 2 <= 2.5 then return T(K.yellow, x) end
      local hill = 12 + floor(1.8 * math.sin(x * 0.7))
      if y <= hill then return T(y < 11 and K.green or K.leaf, x) end
      return T(y > 16 and K.blue or K.cloth_sky, x)
    end
    if z == 28 and y == 8 and x >= 35 and x <= 45 then return T(K.wood, x) end
    return false
  end)
  -- a bench of paint pots at the east end
  parts[#parts + 1] = part(83, 94, 1, 9, 25, 30, function(x, y, z)
    if y <= 5 then
      if (x == 84 or x == 93) and (z == 26 or z == 29) then return T(K.wood_dk, x) end
      if y == 5 then return T(K.wood, x) end
      return false
    end
    local pots = { K.red, K.yellow, K.blue, K.green, K.pink }
    for i, row in ipairs(pots) do
      local px = 83 + i * 2
      if x == px and z >= 26 + (i % 2) and z <= 27 + (i % 2) and y <= 8 then
        return T(y == 8 and row or K.steel, x)
      end
    end
    return false
  end)
  return assemble(m, base, parts)
end

local LOAF = { "..XX..", ".X..X.", "X.XX.X", "X.XX.X", ".X..X.", "..XX.." }
local function bakery()
  local m, base, B = cottage({
    roof = { tile = TILE.cerulean, pitch = 0.85 },
    windows = ceruleanWindows({ single = true, box = K.fl_yellow }),
    chimneys = { { x = 7, z = 5, w = 9, d = 7, top = 50, skin = brick(K.brick_red_a, K.brick_red_b) } },
  })
  local parts = {}
  -- awnings over the two pairs of windows
  for _, c in ipairs({ 49, 73 }) do
    parts[#parts + 1] = part(c - 10, c + 10, 17, 23, 24, 29, function(x, y, z)
      local ay = 22 - floor((z - 24) * 0.7)
      if y == ay then return T(K.awn_bw, x) end
      if z == 29 and y == ay - 1 then return T((x % 4 < 2) and K.blue or K.white, x) end
      return false
    end)
  end
  -- a stall of loaves in front of the first pair
  parts[#parts + 1] = part(40, 58, 1, 9, 25, 29, function(x, y, z)
    if y <= 6 then
      if (x == 40 or x == 58) and y <= 6 then return T(K.wood_dk, x) end
      if y == 6 then return T(K.wood, x) end
      return false
    end
    if (x - 41) % 4 < 3 and (z == 26 or z == 28) and y <= 8 then
      return T((y == 8 and (x % 4 == 1)) and K.cream or K.bread, x)
    end
    return false
  end)
  -- the baker's sign: a loaf on a round board on a bracket
  parts[#parts + 1] = part(32, 40, 13, 23, 24, 26, function(x, y, z)
    if z <= 25 and y == 23 and x >= 34 then return T(K.iron, x) end
    if z ~= 25 then return false end
    local q = (x - 36) ^ 2 + (y - 17) ^ 2
    if q > 18 then return false end
    if inPic(LOAF, 33, 20, x, y) then return T(K.bread, x) end
    return T(q > 12 and K.wood_dk or K.cream, x)
  end)
  -- flour sacks by the east end
  parts[#parts + 1] = part(84, 94, 1, 8, 25, 30, function(x, y, z)
    for _, s in ipairs({ { 86, 27, 0 }, { 91, 28, 0 }, { 88.5, 27.5, 4 } }) do
      local dx, dz, dy = (x - s[1]) / 2.6, (z - s[2]) / 2, (y - s[3] - 2) / 2.2
      if y > s[3] and dx * dx + dz * dz + dy * dy <= 1 then return T(K.cream, x) end
    end
    return false
  end)
  return assemble(m, base, parts)
end

local function glassworks()
  local KX, KZ = 14, 14                              -- the kiln's axis
  local m, base, B = cottage({
    x0 = 26, roof = { tile = TILE.navy, pitch = 0.85, x0 = 21 },
    windows = ceruleanWindows({ single = false }),
    chimneys = { { x = 80, z = 6, w = 5, d = 5, top = 40 } },
  })
  local parts = {}
  -- the bottle kiln: a brick cone swelling out of a round foot and narrowing
  -- to a neck, iron bands round it, a glowing stoke-hole to the south
  local KILN = brick(K.brick_red_a, K.brick_red_b)
  local function radius(y)
    if y <= 6 then return 11.5 end                        -- the plinth
    if y <= 20 then return 11 + sqrt(max(0, 1 - ((y - 16) / 10) ^ 2)) * 2 end   -- the belly
    if y <= 50 then                                        -- drawing in to the neck
      local t = (y - 20) / 30
      return 13 - 8.6 * (t * t * (3 - 2 * t))
    end
    if y <= 58 then return 4.4 end
    return 5.4                                             -- the lip
  end
  parts[#parts + 1] = part(0, 28, 1, 64, 0, 29, function(x, y, z)
    local dx, dz = x - KX + 0.5, z - KZ + 0.5
    local q = dx * dx + dz * dz
    local r = radius(y)
    if y > 60 or q > r * r then return false end
    if y >= 59 then return q > (r - 1.5) ^ 2 and T(K.iron, x) or (y == 59 and T(K.black, x) or nil) end
    if q < (r - 2) ^ 2 then return T(K.shadow, x) end
    if y <= 6 then return RIVER(floor(atan2(dz, dx) * 20), y) end
    if y == 22 or y == 34 or y == 46 then return T(K.iron, x) end
    if y >= 50 and hash(x, y, z) % 3 == 0 then return T(K.brick_dark_a, x) end   -- soot
    if dz > 0 and abs(dx) <= 4 and y <= 16 - dx * dx * 0.25 then
      if abs(dx) <= 3 and y <= 15 - dx * dx * 0.25 then return T(K.furnace, x) end
      return T(K.trim_white, x)
    end
    return KILN(floor(atan2(dz, dx) * 20), y)
  end)
  -- blue glass along the sill shelves, lit from within after dark
  parts[#parts + 1] = part(40, 82, 7, 13, 24, 25, function(x, y, z)
    local inPair = (x >= 42 and x <= 56) or (x >= 66 and x <= 80)
    if not inPair then return false end
    if y == 8 and z == 24 then return T(K.wood_dk, x) end
    if y <= 8 then return false end
    local k = x % 4
    if z == 24 and k ~= 3 and y <= 9 + (x % 3) + (k == 1 and 1 or 0) then
      return T(K.bottle_glow, x * 3 + y)
    end
    return false
  end)
  -- crates of cullet at the east end
  parts[#parts + 1] = part(84, 94, 1, 7, 25, 30, function(x, y, z)
    if y <= 6 then
      local rim = x == 84 or x == 89 or x == 90 or x == 94 or z == 25 or z == 30 or y == 1
      if rim then return T(K.wood, x) end
      if y == 6 then return T((x + z) % 3 == 0 and K.bottle_glow or K.glass, x) end
      return T(K.wood_dk, x)
    end
    return false
  end)
  local c = assemble(m, base, parts)
  c.chimney = { x = KX, y = 61, z = KZ }
  c.lights = c.lights or {}
  c.lights[#c.lights + 1] = { x = KX, y = 10, z = KZ + 14 }
  return c
end

-- ============================================================ city blocks ==
-- The flat-roofed block (Celadon's drawing, and the Bike Shop's): walls x
-- X0..X1, z Z0..Z1 (the street face), a ground floor to 18, `bands` upper
-- storeys 16 tall with the drawing's six windows in each, a cornice, a
-- parapet, and a DECK inside it at the parapet's foot.
-- S: pw, pd, bands, skin(u, y), gf(u, y) (the ground floor's skin), plinth,
-- deck(x, z) -> texel, windows (overrides the drawing's), doors, parapet
-- (row), cornice (row), pave.
local function block(S)
  local PW, PD = S.pw or 64, S.pd or 64
  local X0, X1, Z0, Z1 = S.x0 or 3, S.x1 or PW - 4, S.z0 or 3, S.z1 or PD - 10
  local bands = S.bands or 1
  local GF = 18
  local WALL = GF + 16 * bands + (S.lift or 0)        -- the wall's top course
  local PAR = WALL + (S.parapetH or 4)                 -- the parapet's top
  local DECK = WALL + 1
  local skin = S.skin
  local gf = S.gf or skin
  local plinth = S.plinth or 2
  local plinthSkin = S.plinthSkin or ASHLAR
  local deck = S.deck
  local wins = S.windows
  if not wins then
    wins = {}
    for b = 0, bands - 1 do
      local y0 = GF + 16 * b + 6 + (S.lift or 0)
      for k = 1, S.blind and 0 or (floor(PW / 8) - 2) do   -- the drawing's: one a tile, the end tiles blind
        local c = 8 * k + 4
        wins[#wins + 1] = { face = "s", c = c, w2 = S.winHalf or 3, y0 = y0, y1 = y0 + 7, transom = S.transom and y0 + 5,
                            double = S.mullion, arch = S.arch, shut = S.shut, box = S.box, frame = S.frame, glass = S.glass }
      end
      for k = 1, 3 do
        wins[#wins + 1] = { face = "n", c = X0 + floor((X1 - X0) * (k - 0.5) / 3) + 1, w2 = 3, y0 = y0, y1 = y0 + 7 }
      end
    end
  end
  local doors = S.doors or {}
  local paveA, paveJ = S.pave or K.pave_cel, S.paveJoint or K.joint_cel
  local corniceRow, parapetRow = S.cornice or K.trim_cream, S.parapet or K.trim_cream

  local function base(x, y, z)
    if y == 0 then
      if (x + 8) % 16 == 0 or (z + 8) % 16 == 0 then return T(paveJ, x) end
      return T(paveA, x)
    end
    local inside = x >= X0 and x <= X1 and z >= Z0 and z <= Z1
    if inside then
      if y > PAR then return nil end
      local edge = x == X0 or x == X1 or z == Z0 or z == Z1
      local rim = x <= X0 + 1 or x >= X1 - 1 or z <= Z0 + 1 or z >= Z1 - 1
      if y > WALL then                                   -- the parapet and the deck inside it
        if rim then
          if y == PAR then return T(K.lead, x) end
          return T(parapetRow, (z == Z0 or z == Z1 or z == Z0 + 1 or z == Z1 - 1) and x or z)
        end
        if y == DECK then return deck(x, z) end
        return nil
      end
      local face, u, depth = faceOf(x, z, X0, X1, Z0, Z1)
      if face then
        for i = 1, #doors do
          local D = doors[i]
          if D.face == face then
            local v = door(D, u, y, depth)
            if v ~= false then return v end
          end
        end
        local v = windows(wins, face, u, y, depth)
        if v ~= false then return v end
      end
      if not edge then return T(K.shadow, x) end
      local wu = (z == Z0 or z == Z1) and x or z
      if y <= plinth then return plinthSkin(wu, y) end
      if y == WALL or y == WALL - 1 then return T(corniceRow, wu) end
      if y == GF or y == GF + 1 then return T(S.band or corniceRow, wu) end
      if y < GF then return gf(wu, y) end
      return skin(wu, y)
    end
    -- proud of the wall: the cornice's lip, sills, shutters, boxes
    local face, u, depth = faceOf(x, z, X0, X1, Z0, Z1)
    if face and depth == -1 then
      if y == WALL then return T(corniceRow, u) end
      if y == GF then return T(S.band or corniceRow, u) end
      local v = windows(wins, face, u, y, depth)
      if v then return v end
    end
    return nil
  end

  local lights, lanes = S.lights or {}, {}
  for _, D in ipairs(doors) do
    if D.face == "s" then
      lights[#lights + 1] = { x = D.x1 + 3, y = D.head, z = Z1 + 2 }
      lanes[#lanes + 1] = { D.x0 - 2, D.x1 + 1 }
    end
  end
  local m = { W = PW, xmin = 0, xmax = PW - 1, zmin = 0, zmax = PD - 1, ytop = S.ytop or (PAR + 40),
              lights = #lights > 0 and lights or nil, lanes = lanes }
  return m, base, { X0 = X0, X1 = X1, Z0 = Z0, Z1 = Z1, WALL = WALL, PAR = PAR, DECK = DECK, GF = GF, PW = PW, PD = PD }
end

-- the drawing's roof: a lattice, eight rows of it in the sheet, one per z
local function lattice(first) return function(x, z) return T(first + z % 8, x) end end
local SHOP_DOOR = function(leaf) return { face = "s", x0 = 18, x1 = 30, head = 15, leaf = leaf, deep = 4 } end

local function bike()
  local m, base, B = block({
    bands = 1, lift = 3,
    skin = brick(K.brick_blue_a, K.brick_blue_b), plinthSkin = RIVER, plinth = 3,
    cornice = K.trim_white, parapet = K.trim_white, band = K.navy,
    deck = lattice(K.lat_blue_0), pave = K.pave_cer, paveJoint = K.joint_cer,
    frame = K.trim_white,
    doors = { SHOP_DOOR(K.blue) },
  })
  local Z1, GF, DECK = B.Z1, B.GF, B.DECK
  local parts = {}
  -- the shop window: the whole ground floor east of the door
  parts[#parts + 1] = part(34, 59, 3, 16, Z1 - 2, Z1, function(x, y, z)
    if x == 34 or x == 59 or y == 3 or y == 16 or (x - 34) % 8 == 0 then
      return z == Z1 and T(K.trim_white, x) or T(K.shadow, x)
    end
    if z == Z1 then return nil end
    if z == Z1 - 1 then return nil end
    return T(K.glass_shop, x)
  end)
  -- BIKE SHOP across the band, lit, on a navy board
  local word = "BIKE SHOP"
  local wx = floor((B.X0 + B.X1 - wordWidth(word)) / 2) + 1
  parts[#parts + 1] = part(wx - 2, wx + wordWidth(word) + 1, GF - 1, GF + 7, Z1 + 1, Z1 + 1, function(x, y)
    if inWord(word, wx, GF + 6, x, y) then return T(K.sign_lit, x) end
    return T(K.navy, x)
  end)
  -- an awning over the shop window
  parts[#parts + 1] = part(33, 60, 14, 17, Z1 + 1, Z1 + 5, function(x, y, z)
    local ay = 17 - floor((z - Z1 - 1) * 0.75)
    if y == ay then return T(K.awn_bw, x) end
    return false
  end)
  -- two bicycles in a rack out front, the rack itself, a wall of tyres
  local b1, b2 = bicycle(37, 5, 4), bicycle(42, 5, 4)
  parts[#parts + 1] = part(32, 63, 1, 13, Z1 + 3, Z1 + 8, function(x, y, z)
    local k = (z == Z1 + 4 and b1(x, y)) or (z == Z1 + 7 and b2(x, y)) or nil
    if k == "rim" then return T(K.black, x) end
    if k == "hub" or k == "seat" then return T(K.steel, x) end
    if k then return T(z == Z1 + 4 and K.red or K.yellow, x) end
    if (x == 34 or x == 60) and y <= 7 and z >= Z1 + 3 and z <= Z1 + 8 then return T(K.steel, x) end
    if y == 7 and z == Z1 + 5 and x >= 34 and x <= 60 then return T(K.steel, x) end
    return false
  end)
  parts[#parts + 1] = part(0, 14, 1, 12, Z1 + 2, Z1 + 8, function(x, y, z)
    for i, t in ipairs({ { 5, 1 }, { 5, 4 }, { 5, 7 }, { 11, 1 }, { 11, 4 } }) do
      local dx, dz = x - t[1], z - (Z1 + 5)
      local q = dx * dx + dz * dz
      if y > t[2] and y <= t[2] + 3 and q <= 11 and q >= 2.2 then
        return T((y == t[2] + 2 and i % 2 == 0) and K.iron or K.black, x)
      end
    end
    return false
  end)
  -- the NEON BICYCLE on the roof: tubes on a steel frame, lit after dark
  local big = bicycle(14, DECK + 13, 10, "frame")
  local SZ = Z1 - 6
  parts[#parts + 1] = part(2, 61, DECK, DECK + 38, SZ - 6, SZ + 1, function(x, y, z)
    if z == SZ then
      local k = big(x, y)
      if k == "rim" then return T(K.neon_cyan, x) end
      if k == "frame" then return T(K.neon_pink, x) end
      if k then return T(K.neon_yellow, x) end
    end
    -- the steel it stands on: two raked legs, braced back to the deck
    if z == SZ + 1 and (x == 18 or x == 48) and y <= DECK + 12 then return T(K.iron, x) end
    if (x == 18 or x == 48) and y <= DECK + 12 and z < SZ and SZ - z == floor((y - DECK) / 2) then return T(K.iron, x) end
    return false
  end)
  local c = assemble(m, base, parts)
  c.lights = c.lights or {}
  c.lights[#c.lights + 1] = { x = 34, y = DECK + 14, z = Z1 - 4 }
  return c
end

-- ================================================================ CELADON ==
-- The city of rainbow dreams, one block at a time. Every one is the
-- drawing's block -- a flat roof in a parapet, the six windows under the
-- cornice, the door low on the left where there is one -- in its own stone,
-- and its roof (which is most of what this camera sees) is what it does.

-- a lathe: is (x, y, z) inside the solid of revolution r(y) about (cx, cz)?
local function lathe(cx, cz, y0, y1, r)
  return function(x, y, z)
    if y < y0 or y > y1 then return false end
    local q = (x - cx) ^ 2 + (z - cz) ^ 2
    local R = r(y - y0)
    return q <= R * R, q, R
  end
end
-- a ring lying in the x-y plane (a donut, a coin's rim), z0..z1 thick
local function torusXY(cx, cy, cz, R, r)
  return function(x, y, z)
    local d = sqrt((x - cx) ^ 2 + (y - cy) ^ 2) - R
    return d * d + (z - cz) ^ 2 <= r * r, d
  end
end
local function box(x, y, z, x0, x1, y0, y1, z0, z1)
  return x >= x0 and x <= x1 and y >= y0 and y <= y1 and z >= z0 and z <= z1
end
-- a shop window let into the ground floor: frame, a mullion every `step`,
-- glass two deep. Returns a part.
local function shopWindow(x0, x1, y0, y1, Z1, frame, glass, step)
  return part(x0, x1, y0, y1, Z1 - 2, Z1, function(x, y, z)
    if x == x0 or x == x1 or y == y0 or y == y1 or (step and (x - x0) % step == 0) then
      return z == Z1 and T(frame, x) or T(K.shadow, x)
    end
    if z >= Z1 - 1 then return nil end
    return T(glass or K.glass_shop, x)
  end)
end
-- an awning over x0..x1, falling from y at the wall toward the street
local function awning(x0, x1, y, Z1, row, reach)
  reach = reach or 5
  return part(x0, x1, y - reach, y, Z1 + 1, Z1 + reach, function(x, yy, z)
    local ay = y - floor((z - Z1 - 1) * 0.7)
    if yy == ay then return T(row, x) end
    if z == Z1 + reach and yy == ay - 1 then return T(row, x + 2) end
    return false
  end)
end
-- words on a board facing the street: `word` at x0 (left), top y0, board row
local function signBoard(word, x0, y0, z, lit, board, pad)
  pad = pad or 1
  local w = wordWidth(word)
  return part(x0 - pad, x0 + w - 1 + pad, y0 - 6 - pad, y0 + pad, z, z, function(x, y)
    if inWord(word, x0, y0, x, y) then return T(lit, x) end
    return T(board, x)
  end)
end

-- --- 4:8  the BALCONY FLATS: buff brick four storeys up, a balcony on every
-- floor and every one lived in differently; a water tank on the roof
local function flatsTall()
  local m, base, B = block({
    pw = 64, pd = 96, bands = 3,
    skin = brick(K.brick_buff_a, K.brick_buff_b), gf = brick(K.brick_red_a, K.brick_red_b),
    cornice = K.trim_cream, parapet = K.trim_cream, band = K.trim_cream,
    deck = function(x, z) return T(K.gravel, x + z * 53) end,
  })
  local Z1, GF, DECK = B.Z1, B.GF, B.DECK
  local parts = {}
  local LIFE = { "laundry", "plants", "parasol", "bike", "plants", "laundry", "ac", "parasol", "plants" }
  for b = 0, 2 do
    local fy = GF + 16 * b + 4                       -- the balcony's floor, under the sills
    local bikes = {}
    parts[#parts + 1] = part(5, 58, fy, fy + 12, Z1 + 1, Z1 + 4, function(x, y, z)
      if y == fy then return T(K.render_grey, x) end
      local flat = floor((x - 5) / 18)               -- three flats a floor
      local edge = z == Z1 + 4 or x == 5 or x == 58 or (x - 5) % 18 == 0
      if edge and y <= fy + 4 then
        if y == fy + 4 then return T(K.iron, x) end
        return ((x + z) % 2 == 0) and T(K.iron, x) or false
      end
      local life = LIFE[b * 3 + flat + 1]
      local lx = x - (5 + flat * 18)                 -- 0..17 across the flat
      if life == "laundry" and z == Z1 + 3 then
        if y == fy + 10 and lx > 1 and lx < 17 then return T(K.white, x) end
        local k = floor((lx - 2) / 4)
        if lx > 1 and lx < 17 and (lx - 2) % 4 < 3 and y < fy + 10 and y >= fy + 5 + (k % 2) * 2 then
          return T(({ K.cloth_red, K.cloth_white, K.cloth_sky, K.yellow })[k % 4 + 1], x)
        end
      elseif life == "plants" and z <= Z1 + 3 then
        for _, px in ipairs({ 3, 8, 13 }) do
          local q = (lx - px) ^ 2 + (z - Z1 - 2) ^ 2
          if y <= fy + 2 and q <= 2 then return T(K.copper, x) end
          if y > fy + 2 and y <= fy + 5 + px % 3 and q <= 4 - (y - fy - 3) * 0.3 then return T(K.leaf, x) end
        end
      elseif life == "parasol" then
        if lx == 9 and z == Z1 + 2 and y <= fy + 9 then return T(K.white, x) end
        local q = (lx - 9) ^ 2 + (z - Z1 - 2) ^ 2 * 3
        if y == fy + 10 - floor(q / 22) and q <= 60 then return T((floor(atan2(z - Z1 - 2, lx - 9) * 2) % 2 == 0) and K.red or K.white, x) end
        if y <= fy + 3 and z == Z1 + 3 and (lx == 4 or lx == 14) then return T(K.white, x) end
      elseif life == "bike" and z == Z1 + 2 then
        bikes[flat] = bikes[flat] or bicycle(5 + flat * 18 + 3, fy + 3, 2.6)
        local k = bikes[flat](x, y)
        if k then return T(k == "rim" and K.black or K.green, x) end
      elseif life == "ac" then
        if box(lx, y, z, 11, 16, fy + 6, fy + 10, Z1 + 1, Z1 + 2) then
          if z == Z1 + 2 and lx >= 12 and lx <= 15 and y >= fy + 7 and y <= fy + 9 then
            return T((y % 2 == 0) and K.iron or K.steel, x)
          end
          return T(K.steel, x)
        end
      end
      return false
    end)
  end
  -- two shopfronts on the ground floor under a green awning
  parts[#parts + 1] = shopWindow(8, 27, 3, 14, Z1, K.wood_dk, K.glass_shop, 5)
  parts[#parts + 1] = shopWindow(36, 55, 3, 14, Z1, K.wood_dk, K.glass_shop, 5)
  parts[#parts + 1] = awning(6, 57, 17, Z1, K.awn_gw, 5)
  -- the water tank on stilts, a hatch house, an aerial
  local TX, TZ, TB = 44, 30, DECK + 9
  local tank = lathe(TX, TZ, TB, TB + 17, function(k) return k <= 12 and 6.5 or 6.5 - (k - 12) * 1.3 end)
  parts[#parts + 1] = part(30, 58, DECK + 1, DECK + 40, 16, 44, function(x, y, z)
    local inT, q = tank(x, y, z)
    if inT then
      local k = y - TB
      if k > 12 then return T(K.tar, x) end
      if k == 3 or k == 9 then return T(K.iron, x) end
      return T(K.wood, floor(atan2(z - TZ, x - TX) * 12))
    end
    if y < TB and ((abs(x - TX) == 4 and abs(z - TZ) == 4)) then return T(K.iron, x) end
    if y == TB - 3 and (abs(x - TX) == 4 or abs(z - TZ) == 4) and abs(x - TX) <= 4 and abs(z - TZ) <= 4 then return T(K.iron, x) end
    if x == 33 and z == 20 and y <= DECK + 34 then return T(K.iron, x) end
    if (y == DECK + 30 or y == DECK + 26) and z == 20 and abs(x - 33) <= 3 then return T(K.iron, x) end
    return false
  end)
  parts[#parts + 1] = part(10, 22, DECK + 1, DECK + 10, 20, 30, function(x, y, z)
    if y == DECK + 10 then return T(K.tar, x) end
    if z == 30 and x >= 14 and x <= 18 and y <= DECK + 7 then return T(K.wood_dk, x) end
    return T(K.render_grey, x)
  end)
  return assemble(m, base, parts)
end

-- --- 28:8  the PERFUMERY: glazed celadon tile four storeys up, an arcade at
-- the street, arched windows, a roof of scented beds round a glass dome, and
-- a flask on the corner as tall as a man, lit from within
local function perfumery()
  local m, base, B = block({
    pw = 96, pd = 96, bands = 3, arch = true, frame = K.trim_cream,
    skin = coursed(K.jade_a, K.jade_b, K.jade_grout, 3), gf = plain(K.marble_green), plinthSkin = ASHLAR,
    cornice = K.frieze_gold, parapet = K.trim_cream, band = K.frieze_gold,
    deck = function(x, z) return T(K.terrazzo, x + z * 53) end,
  })
  local Z1, GF, DECK, X0, X1 = B.Z1, B.GF, B.DECK, B.X0, B.X1
  local parts = {}
  -- the arcade: round arches every sixteen, shop glass three deep behind
  parts[#parts + 1] = part(X0, X1, 1, GF - 1, Z1 - 3, Z1, function(x, y, z)
    local k = (x - X0 - 8) % 16
    local du = abs(k - 8)
    if du > 6 or y < 2 then return false end
    local inside = y <= 10 or du * du + (y - 10) ^ 2 <= 36
    if not inside then return false end
    if z > Z1 - 3 then return nil end
    return T(K.glass_shop, x)
  end)
  -- the roof: beds of lavender, rose, jasmine and orange blossom in rows,
  -- gravel paths between, a glass dome in the middle
  local BEDS = { K.fl_purple, K.fl_pink, K.fl_white, K.fl_orange, K.fl_purple, K.fl_yellow }
  local dome = lathe(48, 44, DECK, DECK + 18, function(k) return sqrt(max(0, 18 * 18 - k * k)) * 0.9 end)
  parts[#parts + 1] = part(X0 + 3, X1 - 3, DECK, DECK + 20, B.Z0 + 3, Z1 - 3, function(x, y, z)
    local inD, q, R = dome(x, y, z)
    if inD then
      if q < (R - 1.5) ^ 2 and y > DECK then return T(K.shadow, x) end
      local ang = atan2(z - 44, x - 48)
      if floor(ang * 8 / 3.1416) ~= floor((ang + 0.05) * 8 / 3.1416) or y == DECK + 6 or y == DECK + 12 then return T(K.frieze_gold, x) end
      return T(K.sky_0 + (x + y) % 8, x)
    end
    if y == DECK + 19 and (x - 48) ^ 2 + (z - 44) ^ 2 <= 2 then return T(K.gold, x) end
    local row = floor((z - B.Z0 - 3) / 7)
    local inBed = (z - B.Z0 - 3) % 7 < 5 and (x - X0 - 3) % 22 < 18
    if inBed and y == DECK + 1 then return T(K.leaf_dk, x) end
    if inBed and y == DECK + 2 and hash(x, z) % 3 ~= 0 then return T(BEDS[row % #BEDS + 1], x) end
    if y == DECK and not inBed then return T(K.gravel, x) end
    return false
  end)
  -- the flask: a round body of rose glass on the south-east corner, a gold
  -- collar and stopper, the atomizer's bulb on its tube
  local FX, FZ, FY = 80, Z1 - 10, DECK + 11
  parts[#parts + 1] = part(66, 94, DECK, DECK + 34, Z1 - 24, Z1, function(x, y, z)
    local dx, dy, dz = x - FX, y - FY, z - FZ
    local q = dx * dx + dy * dy * 1.1 + dz * dz
    if q <= 100 then return q >= 70 and T(K.neon_pink, x) or T(K.shadow, x) end
    if y > FY + 8 and y <= FY + 12 and dx * dx + dz * dz <= 12 then return T(K.gold, x) end
    if y > FY + 12 and y <= FY + 17 and dx * dx + dz * dz <= 6 - (y - FY - 13) then return T(K.neon_pink, x) end
    if y == FY + 18 and dx * dx + dz * dz <= 3 then return T(K.gold, x) end
    -- the tube over the shoulder and the bulb hanging off it
    if z == FZ and y == FY + 11 and x < FX - 3 and x >= FX - 10 then return T(K.gold, x) end
    local bq = (x - FX + 12) ^ 2 + (y - FY - 7) ^ 2 * 1.4 + (z - FZ) ^ 2
    if bq <= 9 then return T(K.lacquer_red, x) end
    if y <= DECK + 1 and dx * dx + dz * dz <= 36 then return T(K.frieze_gold, x) end
    return false
  end)
  return assemble(m, base, parts)
end

-- --- 56:12 the TEA HOUSE: a dark wooden lattice at the street, cream
-- plaster over it, paper windows; on the roof, red parasols over red
-- benches and a string of lanterns
local function teahouse()
  local m, base, B = block({
    skin = plain(K.stucco_cream), gf = plain(K.koshi), frame = K.wood_dk, glass = K.shoji, mullion = true,
    cornice = K.wood_dk, parapet = K.wood, band = K.wood_dk,
    deck = function(x, z) return T(K.deck, z) end,
  })
  local Z1, GF, DECK = B.Z1, B.GF, B.DECK
  local parts = {}
  -- a noren across the middle of the lattice: three indigo panels, a white disc
  parts[#parts + 1] = part(24, 39, 8, 16, Z1 + 1, Z1 + 1, function(x, y)
    if (x - 24) % 5 == 4 and y < 15 then return false end
    if (x - 31.5) ^ 2 + (y - 12) ^ 2 <= 4 then return T(K.white, x) end
    return T(K.cloth_indigo, x)
  end)
  -- red parasols over red-felted benches, lanterns strung along the front
  local UMB = { { 18, 26 }, { 44, 22 } }
  parts[#parts + 1] = part(4, 59, DECK, DECK + 18, 6, Z1, function(x, y, z)
    for _, u in ipairs(UMB) do
      local dx, dz = x - u[1], z - u[2]
      local q = dx * dx + dz * dz
      if dx == 0 and dz == 0 and y <= DECK + 14 then return T(K.bamboo, x) end
      if q <= 100 and y == DECK + 15 - floor(q / 30) then
        if q < 4 then return T(K.bamboo, x) end
        return T((floor(atan2(dz, dx) * 8 / 3.1416) % 2 == 0) and K.lacquer_red or K.red, x)
      end
      if y <= DECK + 3 and abs(dz) <= 2 and abs(dx) >= 4 and abs(dx) <= 9 then
        if y == DECK + 3 then return T(K.cloth_red, x) end
        if abs(dx) == 4 or abs(dx) == 9 then return T(K.lacquer_red, x) end
      end
    end
    -- the lantern string, sagging between posts on the parapet's front
    if z == Z1 - 1 and x >= 5 and x <= 58 then
      local sag = DECK + 9 - floor(3 * (1 - ((x - 31.5) / 26.5) ^ 2))
      if y == sag and (x - 5) % 7 ~= 0 then return T(K.black, x) end
      if (x - 5) % 7 == 0 and y <= sag and y >= sag - 3 then return T(K.lantern_red, x) end
      if (x == 5 or x == 58) and y <= DECK + 9 then return T(K.bamboo, x) end
    end
    return false
  end)
  return assemble(m, base, parts)
end

-- --- 64:12 the WATCHMAKER: slate-blue brick, a clock tower rising off the
-- roof with a lit face, a copper spire; watches in the window
local function watchmaker()
  local m, base, B = block({
    skin = brick(K.brick_blue_a, K.brick_blue_b), gf = plain(K.wood_dk), frame = K.trim_white,
    cornice = K.trim_white, parapet = K.trim_white, band = K.navy, ytop = 96,
    deck = lattice(K.lat_jade_0),
  })
  local Z1, GF, DECK = B.Z1, B.GF, B.DECK
  local parts = {}
  parts[#parts + 1] = part(34, 57, 3, 15, Z1 - 2, Z1, function(x, y, z)
    if x == 34 or x == 57 or y == 3 or y == 15 then return z == Z1 and T(K.brass, x) or T(K.shadow, x) end
    if z >= Z1 - 1 then return nil end
    if (y == 6 or y == 11) then return T(K.navy, x) end
    if (y == 7 or y == 12) and x % 3 == 0 then return T(K.gold, x) end   -- watches on velvet
    return T(K.glass_shop, x)
  end)
  -- the tower: cream, quoined, a face to the street, a verdigris spire
  local TX0, TX1, TZ0, TZ1 = 24, 39, 30, 45
  local TOP = DECK + 30
  local CX, CY = 31.5, DECK + 20
  local HOUR, MINUTE = seg(CX, CY, CX - 3.5, CY + 2, 0.6), seg(CX, CY, CX + 4.8, CY + 3, 0.6)
  parts[#parts + 1] = part(TX0, TX1, DECK, TOP + 24, TZ0, TZ1 + 1, function(x, y, z)
    local inT = x >= TX0 and x <= TX1 and z >= TZ0 and z <= TZ1
    if inT and y <= TOP then
      if y == TOP or y == TOP - 1 then return T(K.trim_white, x) end
      local edge = x == TX0 or x == TX1 or z == TZ0 or z == TZ1
      if not edge then return T(K.shadow, x) end
      if (x <= TX0 + 1 or x >= TX1 - 1) and (z <= TZ0 + 1 or z >= TZ1 - 1) then
        return T(floor(y / 3) % 2 == 0 and K.trim_white or K.stucco_cream, x)
      end
      return T(K.stucco_cream, (z == TZ0 or z == TZ1) and x or z)
    end
    -- the face, proud of the tower's south wall
    if z == TZ1 + 1 then
      local dx, dy = x - CX, y - CY
      local q = dx * dx + dy * dy
      if q <= 49 then
        if q >= 36 then return T(K.gold, x) end
        -- ten past ten
        if HOUR(x, y) or MINUTE(x, y) then return T(K.black, x) end
        if q >= 25 and (abs(dx) < 0.6 or abs(dy) < 0.6) then return T(K.black, x) end
        return T(K.sign_lit, x)
      end
      return false
    end
    -- the spire
    local k = y - TOP
    if k >= 1 and k <= 18 then
      local r = 8 - k * 0.45
      if abs(x - CX) <= r and abs(z - (TZ0 + TZ1) / 2) <= r then return T(K.verdigris, x + k) end
    end
    if k > 18 and k <= 23 and abs(x - CX) < 1 and abs(z - (TZ0 + TZ1) / 2) < 1 then return T(K.gold, x) end
    return false
  end)
  return assemble(m, base, parts)
end

-- --- 72:12 the APOTHECARY (beside the Centre): white tile, mint below, a
-- green cross lit at the corner, the roof all raised beds of herbs
local function apothecary()
  local m, base, B = block({
    skin = plain(K.render_white), gf = plain(K.stucco_mint), frame = K.green, box = K.leaf_lt,
    cornice = K.green, parapet = K.render_white, band = K.green,
    deck = function(x, z) return T(K.terrazzo, x + z * 53) end,
  })
  local Z1, GF, DECK = B.Z1, B.GF, B.DECK
  local parts = {}
  parts[#parts + 1] = shopWindow(8, 28, 3, 15, Z1, K.green, K.glass_shop, 7)
  parts[#parts + 1] = shopWindow(36, 56, 3, 15, Z1, K.green, K.glass_shop, 7)
  -- the cross: on a white disc on a bracket off the east corner
  parts[#parts + 1] = part(50, 63, 18, 33, Z1 + 1, Z1 + 3, function(x, y, z)
    if z == Z1 + 1 and y == 30 and x >= 56 and x <= 60 then return T(K.iron, x) end
    if z ~= Z1 + 2 then return false end
    local dx, dy = x - 57, y - 25
    local q = dx * dx + dy * dy
    if q > 42 then return false end
    if (abs(dx) <= 1.5 and abs(dy) <= 4.5) or (abs(dy) <= 1.5 and abs(dx) <= 4.5) then return T(K.neon_green, x) end
    return T(q >= 34 and K.green or K.white, x)
  end)
  -- raised beds: sage, lavender, camomile, mint, in cedar frames
  local HERB = { K.leaf_lt, K.fl_purple, K.fl_white, K.leaf, K.fl_yellow, K.leaf_dk }
  parts[#parts + 1] = part(6, 57, DECK, DECK + 6, 7, Z1 - 3, function(x, y, z)
    local bx, bz = floor((x - 6) / 17), floor((z - 7) / 14)
    local lx, lz = (x - 6) % 17, (z - 7) % 14
    if lx > 14 or lz > 10 then return false end
    if lx == 0 or lx == 14 or lz == 0 or lz == 10 then return y <= DECK + 3 and T(K.wood, x) or false end
    if y <= DECK + 2 then return T(K.soil, x) end
    local h = hash(x, z)
    if y <= DECK + 3 + h % 3 and h % 4 ~= 0 then
      local herb = HERB[(bx + bz * 3) % #HERB + 1]
      return T((y > DECK + 3 and herb ~= K.leaf and herb ~= K.leaf_dk) and herb or (h % 2 == 0 and K.leaf or K.leaf_dk), x)
    end
    return false
  end)
  return assemble(m, base, parts)
end

-- --- 40:28 the POND PAVILION: the drawing is a long hipped house, and at a
-- pond that is a pavilion -- red lacquer posts, lattice screens between,
-- glazed celadon tile with its corners swept up, lanterns under the eaves
local function pavilion()
  local LAC = function(u, y) return ((u - 7) % 12 <= 1) and T(K.lacquer_red, u) or T(K.koshi, u) end
  local m, base, B = cottage({
    skin = LAC, plinth = 3, plinthSkin = ASHLAR,
    roof = { tile = TILE.jade, pitch = 0.95, ridge = K.ridge_jade, fascia = K.lacquer_red, kick = 6 },
    windows = { { face = "s", c = 49, w2 = 6, y0 = 9, y1 = 20, arch = true, frame = K.lacquer_red },
                { face = "s", c = 73, w2 = 6, y0 = 9, y1 = 20, arch = true, frame = K.lacquer_red },
                { face = "s", c = 25, w2 = 6, y0 = 9, y1 = 20, arch = true, frame = K.lacquer_red } },
    pave = K.pave_cel, paveJoint = K.joint_cel,
  })
  local parts = {}
  -- lanterns hanging from the eave
  for _, lx in ipairs({ 13, 37, 61, 85 }) do
    parts[#parts + 1] = part(lx - 2, lx + 2, 13, 24, 28, 31, function(x, y, z)
      if x == lx and z == 29 and y >= 19 then return T(K.black, x) end
      local q = (x - lx) ^ 2 + (z - 29) ^ 2 + ((y - 16) * 0.8) ^ 2
      if q <= 4.5 then return T((y == 14 or y == 18) and K.black or K.lantern_red, x) end
      return false
    end)
  end
  -- fish-tail finials on the ridge's two ends
  for _, fx in ipairs({ 16, 79 }) do
    parts[#parts + 1] = part(fx - 3, fx + 3, 36, 48, 12, 16, function(x, y, z)
      local top = B.roofAt(x, z)
      if not top or y <= top or abs(z - 14) > 1 then return false end
      local k = y - top
      local dx = (x - fx) * (fx < 48 and -1 or 1)      -- outward
      if k <= 5 and dx >= -1 and dx <= 1 then return T(K.gold, x) end
      if k > 3 and k <= 8 and dx >= 0 and dx <= 3 and dx >= (k - 5) then return T(K.gold, x) end
      return false
    end)
  end
  local c = assemble(m, base, parts)
  c.lights = { { x = 37, y = 16, z = 30 }, { x = 61, y = 16, z = 30 } }
  return c
end

-- --- 64:32 the PRIZE EXCHANGE (the Game Corner's): red lacquer and gold,
-- a marquee of bulbs over the door, PRIZE in lights, a gold coin on the roof
local function prize()
  local m, base, B = block({
    lift = 7, frame = K.frieze_gold, ytop = 90,
    skin = plain(K.lacquer_red), gf = plain(K.black_gloss), plinthSkin = coursed(K.black_gloss, K.black_gloss, K.iron, 4),
    cornice = K.frieze_gold, parapet = K.lacquer_red, band = K.frieze_gold,
    deck = lattice(K.lat_jade_0),
    doors = { { face = "s", x0 = 18, x1 = 30, head = 15, leaf = K.lacquer_red, deep = 4, frame = K.frieze_gold } },
  })
  local Z1, GF, DECK = B.Z1, B.GF, B.DECK
  local parts = {}
  -- the marquee: a canopy over the door, bulbs round its edge
  parts[#parts + 1] = part(14, 36, 18, 20, Z1 + 1, Z1 + 6, function(x, y, z)
    local rim = x == 14 or x == 36 or z == Z1 + 6
    if y == 20 then return T(K.frieze_gold, x) end
    if rim then return T(K.bulbs, x + z) end
    if y == 18 then return T(K.bulbs, x) end
    return T(K.black_gloss, x)
  end)
  parts[#parts + 1] = signBoard("PRIZE", 18, 28, Z1 + 1, K.bulbs, K.black_gloss, 1)
  -- the coin on its edge on the roof, a rim of bulbs, on two legs
  local CX, CY, CZ = 32, DECK + 17, 36
  parts[#parts + 1] = part(16, 48, DECK, DECK + 32, CZ - 3, CZ + 1, function(x, y, z)
    local dx, dy = x - CX, y - CY
    local q = dx * dx + dy * dy
    if q <= 196 and (z == CZ or z == CZ - 1) then
      if q >= 169 then return T(K.bulbs, floor(atan2(dy, dx) * 12)) end
      if q >= 110 and q <= 128 then return T(K.brass, x) end
      if abs(dx) + abs(dy) * 0.8 <= 5 then return T(K.sign_lit, x) end        -- a lit diamond at its heart
      return T(K.gold, x)
    end
    if (x == CX - 6 or x == CX + 6) and y <= DECK + 4 and z >= CZ - 3 and z <= CZ + 1 then return T(K.iron, x) end
    return false
  end)
  return assemble(m, base, parts)
end

-- --- 76:32 the CINEMA: cream deco with a black-glass foot, posters in
-- their cases, a marquee of bulbs, CINEMA down a sign that climbs past the
-- roof, searchlights on it
local function cinema()
  local m, base, B = block({
    skin = plain(K.stucco_cream), gf = plain(K.black_gloss), frame = K.frieze_gold, plinthSkin = ASHLAR,
    cornice = K.frieze_gold, parapet = K.stucco_cream, band = K.frieze_gold,
    deck = function(x, z) return T(K.tar, x + z * 53) end,
  })
  local Z1, GF, DECK = B.Z1, B.GF, B.DECK
  local parts = {}
  -- the vertical sign: a navy board edged in bulbs, the letters one under another
  local WORD = "CINEMA"
  parts[#parts + 1] = part(47, 57, GF + 2, GF + 2 + #WORD * 9 + 3, Z1 + 1, Z1 + 3, function(x, y, z)
    if z < Z1 + 3 then return (x == 49 or x == 55) and y <= GF + 10 and T(K.iron, x) or false end
    local topY = GF + 2 + #WORD * 9 + 3
    if x == 47 or x == 57 or y == GF + 2 or y == topY then return T(K.bulbs, x + y) end
    local row = topY - 2 - y
    local i = floor(row / 9) + 1
    local g = GLYPH[WORD:sub(i, i)]
    local gy, gx = row % 9, x - 50
    if g and gy < 7 and gx >= 0 and gx <= 4 and g[gy + 1]:sub(gx + 1, gx + 1) == "X" then return T(K.neon_red, x) end
    return T(K.navy, x)
  end)
  -- the marquee over the front, bulbs along its lip
  parts[#parts + 1] = part(5, 44, 17, 22, Z1 + 1, Z1 + 6, function(x, y, z)
    if y == 22 then return T(K.frieze_gold, x) end
    if z == Z1 + 6 then return (y == 17 or y == 21) and T(K.bulbs, x) or T(K.white, x) end
    if y == 17 then return T(K.bulbs, x + z) end
    return false
  end)
  -- posters in gilt cases on the black glass
  for i, px in ipairs({ 7, 20, 33 }) do
    local row = ({ K.poster_a, K.poster_b, K.poster_c })[i]
    parts[#parts + 1] = part(px, px + 9, 3, 15, Z1 + 1, Z1 + 1, function(x, y)
      if x == px or x == px + 9 or y == 3 or y == 15 then return T(K.frieze_gold, x) end
      return T(row, x * 2 + y)
    end)
  end
  -- the projection box and two searchlights raking the sky
  parts[#parts + 1] = part(6, 58, DECK, DECK + 12, 8, 40, function(x, y, z)
    if box(x, y, z, 20, 40, DECK + 1, DECK + 8, 10, 22) then
      if y == DECK + 8 then return T(K.tar, x) end
      return T(K.stucco_cream, x)
    end
    for _, sx in ipairs({ 10, 50 }) do
      local dx, dz = x - sx, z - 34
      if y <= DECK + 4 and dx * dx + dz * dz <= 4 then return T(K.iron, x) end
      local k = y - DECK - 4
      if k >= 0 and k <= 6 and dx * dx + (dz - k * 0.6) ^ 2 <= 7 then
        return T(k >= 5 and K.sign_lit or K.steel, x)
      end
    end
    return false
  end)
  return assemble(m, base, parts)
end

-- --- 84:32 the BATHHOUSE: timber at the street, white plaster over it, a
-- curved gable over the entrance with its noren, the brick chimney every
-- bathhouse has, and an open-air bath on the roof behind a bamboo screen
local function bathhouse()
  local m, base, B = block({
    skin = plain(K.stucco_white), gf = coursed(K.board, K.board, K.board_line, 3), frame = K.wood_dk,
    cornice = K.wood_dk, parapet = K.wood_dk, band = K.wood_dk, glass = K.shoji, mullion = true,
    deck = function(x, z) return T(K.deck, z) end, ytop = 112,
  })
  local Z1, GF, DECK = B.Z1, B.GF, B.DECK
  local parts = {}
  -- the curved gable: a tiled bonnet over the middle of the front
  parts[#parts + 1] = part(18, 45, 16, 28, Z1 + 1, Z1 + 6, function(x, y, z)
    local dx = abs(x - 31.5)
    local crown = 27 - floor(dx * dx / 30)
    local ey = crown - floor((z - Z1 - 1) * 0.6)
    if dx > 13.5 then return false end
    if y == ey or y == ey - 1 then return T(y == ey and K.kawara_a or K.kawara_line, x) end
    if z == Z1 + 1 and y < ey - 1 and y >= 18 and dx >= 11.5 then return T(K.wood_dk, x) end
    return false
  end)
  parts[#parts + 1] = part(24, 39, 7, 16, Z1 + 1, Z1 + 1, function(x, y)
    if (x - 24) % 4 == 3 and y < 15 then return false end
    local dx, dy = x - 31.5, y - 11
    if dy < 0 and dx * dx + dy * dy * 3 <= 12 then return T(K.white, x) end     -- a bowl
    if dy >= 0 and dy <= 3 and floor(abs(dx) + 0.5) % 3 == 0 and abs(dx) <= 3 then return T(K.white, x) end  -- its steam
    return T(K.cloth_indigo, x)
  end)
  -- the chimney: square, brick, a white band near the top
  local CH = { x = 48, z = 14, top = DECK + 70 }
  parts[#parts + 1] = part(CH.x, CH.x + 5, DECK, CH.top, CH.z, CH.z + 5, function(x, y, z)
    if y >= CH.top - 1 and x > CH.x and x < CH.x + 5 and z > CH.z and z < CH.z + 5 then
      return y == CH.top - 1 and T(K.black, x) or nil
    end
    if y >= CH.top - 12 and y <= CH.top - 8 then return T(K.white, x) end
    return brick(K.brick_red_a, K.brick_red_b)(x + z, y)
  end)
  -- the open-air bath: rocks round warm water, a bamboo screen at the front
  parts[#parts + 1] = part(6, 44, DECK, DECK + 9, 8, Z1 - 2, function(x, y, z)
    local dx, dz = (x - 24) / 15, (z - 30) / 11
    local q = dx * dx + dz * dz
    if q <= 1 then
      if y == DECK then return T(q < 0.75 and K.water or K.rock, x) end
      if y == DECK + 1 and q >= 0.75 and hash(x, z) % 3 ~= 0 then return T(K.rock, x) end
      return false
    end
    if z == Z1 - 3 and y <= DECK + 8 then return T(K.bamboo, x) end
    return false
  end)
  local c = assemble(m, base, parts)
  c.chimney = { x = CH.x + 2.5, y = CH.top + 1, z = CH.z + 2.5 }
  return c
end

-- --- 4:48 the RADIO STATION: white and navy, a porthole studio window,
-- ON AIR lit red, dishes on the roof and a lattice mast that tops the town
local function radio()
  local m, base, B = block({
    skin = plain(K.render_white), gf = plain(K.render_grey), frame = K.navy,
    cornice = K.navy, parapet = K.render_white, band = K.navy, ytop = 150,
    deck = function(x, z) return T(K.tar, x + z * 53) end,
  })
  local Z1, GF, DECK = B.Z1, B.GF, B.DECK
  local parts = {}
  -- the studio's porthole, and ON AIR over it
  parts[#parts + 1] = part(44, 58, 2, 16, Z1 - 2, Z1, function(x, y, z)
    local q = (x - 51) ^ 2 + (y - 9) ^ 2
    if q > 49 then return false end
    if q >= 30 then return z == Z1 and T(K.steel, x) or false end
    if z >= Z1 - 1 then return nil end
    return T(K.glass_dark, x)
  end)
  parts[#parts + 1] = signBoard("ON AIR", 5, 13, Z1 + 1, K.neon_red, K.black, 1)
  -- the mast: four legs drawn in as it climbs, girts and a cross of braces
  -- every six, red and white by the hundred-foot, beacons
  local MX, MZ, M0, MH = 44, 22, DECK, 104
  parts[#parts + 1] = part(MX - 7, MX + 7, M0, M0 + MH + 3, MZ - 7, MZ + 7, function(x, y, z)
    local k = y - M0
    local h = 6.5 * (1 - k / (MH + 8))
    local dx, dz = abs(x - MX), abs(z - MZ)
    if k > MH then return (dx < 1 and dz < 1) and T(K.neon_red, x) or false end
    local onX, onZ = abs(dx - h) < 0.8, abs(dz - h) < 0.8
    local band = floor(k / 13) % 2 == 0 and K.red or K.white
    if onX and onZ then return T(band, x) end                          -- the legs
    if (onX and dz <= h) or (onZ and dx <= h) then
      local t = k % 6
      if t == 0 then return T(band, x) end                              -- girts
      local s = (onX and (z - MZ) or (x - MX)) / max(h, 0.5)            -- -1..1 across the face
      if abs(s - (t / 3 - 1)) < 0.35 or abs(-s - (t / 3 - 1)) < 0.35 then return T(K.iron, x) end
    end
    if k == floor(MH / 2) and dx < 1.5 and dz < 1.5 then return T(K.neon_red, x) end
    return false
  end)
  -- two dishes on the roof, looking south and up
  for _, d in ipairs({ { 14, 38 }, { 24, 18 } }) do
    parts[#parts + 1] = part(d[1] - 6, d[1] + 6, DECK, DECK + 14, d[2] - 5, d[2] + 5, function(x, y, z)
      if abs(x - d[1]) < 1 and abs(z - d[2]) < 1 and y <= DECK + 5 then return T(K.steel, x) end
      local dx, dy = x - d[1], y - DECK - 9
      local q = dx * dx + dy * dy
      if q <= 30 and z == d[2] - floor(dy * 0.6) + floor(q / 16) then return T(q < 2 and K.iron or K.white, x) end
      return false
    end)
  end
  return assemble(m, base, parts)
end

-- --- 28:48 the BOOKSHOP: dark brick, a bay of books at the street, tall
-- arched windows, an open book on a bracket, a glazed lantern on the roof
local function bookshop()
  local m, base, B = block({
    skin = brick(K.brick_dark_a, K.brick_dark_b, K.mortar_dk), gf = plain(K.wood_dk), frame = K.trim_cream,
    arch = true, cornice = K.trim_cream, parapet = K.trim_cream, band = K.frieze_gold,
    deck = function(x, z) return T(K.lead, x + z * 53) end,
  })
  local Z1, GF, DECK = B.Z1, B.GF, B.DECK
  local parts = {}
  -- the bay: a box of shelves behind glass, standing out into the street
  parts[#parts + 1] = part(30, 58, 1, 17, Z1 + 1, Z1 + 4, function(x, y, z)
    if y <= 3 then return T(K.wood_dk, x) end
    if y >= 16 then return T(K.wood_dk, x) end
    local rim = x == 30 or x == 58 or (x - 30) % 7 == 0
    if z == Z1 + 4 or x == 30 or x == 58 then
      if rim or y == 4 then return T(K.wood_dk, x) end
      if y == 9 or y == 10 then return T(K.wood, x) end
      return T(K.books, x * 3 + y)
    end
    return T(K.shadow, x)
  end)
  -- the open book hung over the door
  parts[#parts + 1] = part(6, 24, 18, 30, Z1 + 1, Z1 + 3, function(x, y, z)
    if z == Z1 + 1 and y == 29 and x >= 13 and x <= 17 then return T(K.iron, x) end
    if z ~= Z1 + 2 then return false end
    local dx = x - 15
    local ad = abs(dx)
    -- the pages rise from the spine to their outer corners; the cover shows under them
    local top = 25 + floor(ad * 0.34)
    local bottom = 20 + floor(ad * 0.2)
    if ad > 8 or y > top or y < bottom - 1 then return false end
    if y == bottom - 1 or ad == 8 then return T(K.lacquer_red, x) end
    if ad == 0 then return y <= top - 1 and T(K.wood_dk, x) or false end
    if (y == bottom + 2 or y == bottom + 4) and ad >= 2 and ad <= 6 then return T(K.render_grey, x) end
    return T(K.cream, x)
  end)
  -- the roof lantern: a glazed ridge of iron and glass
  parts[#parts + 1] = part(10, 53, DECK, DECK + 14, 12, 40, function(x, y, z)
    if x < 12 or x > 51 then return false end
    local dz = abs(z - 26)
    local k = y - DECK
    if k <= 3 then
      if dz <= 12 then return (dz == 12 or x == 12 or x == 51) and T(K.trim_cream, x) or T(K.shadow, x) end
      return false
    end
    local top = 3 + floor((12 - dz) * 0.8)
    if dz > 12 or k > top then return false end
    if k == top or k == top - 1 then
      if (x - 12) % 5 == 0 or dz <= 1 then return T(K.iron, x) end
      return T(K.glass, x)
    end
    return T(K.shadow, x)
  end)
  return assemble(m, base, parts)
end

-- --- 36:48 the RECORD SHOP: aubergine brick and gold, a record the size of
-- a door on the corner of the front, a brass gramophone horn on the roof
local function records()
  local m, base, B = block({
    skin = plain(K.violet), gf = plain(K.black_gloss), frame = K.frieze_gold,
    cornice = K.frieze_gold, parapet = K.violet, band = K.frieze_gold,
    deck = function(x, z) return T(K.tar, x + z * 53) end,
  })
  local Z1, GF, DECK = B.Z1, B.GF, B.DECK
  local parts = {}
  parts[#parts + 1] = shopWindow(8, 40, 3, 15, Z1, K.frieze_gold, K.glass_shop, 8)
  -- the record: grooves, a red label, the hole, half over the parapet
  local RX, RY = 50, 36
  parts[#parts + 1] = part(RX - 12, RX + 12, RY - 12, RY + 12, Z1 + 1, Z1 + 1, function(x, y)
    local q = (x - RX) ^ 2 + (y - RY) ^ 2
    if q > 132 then return false end
    if q <= 1.5 then return T(K.black, x) end
    if q <= 16 then return T(K.red, x) end
    return T(K.record, floor(sqrt(q)))
  end)
  -- the horn: a flaring brass bell on a crank box, its mouth turned east so
  -- the street sees it in profile -- the shape everyone knows
  local AX, AY, AZ = 18, DECK + 9, 26                 -- the throat
  parts[#parts + 1] = part(6, 50, DECK, DECK + 34, 10, Z1 - 1, function(x, y, z)
    if box(x, y, z, 8, 22, DECK + 1, DECK + 7, 20, 32) then
      if z == 32 and y == DECK + 4 and x == 15 then return T(K.brass, x) end
      if y == DECK + 7 then return T(K.wood, x) end
      return T(K.wood_dk, x)
    end
    if x == 15 and y > DECK + 7 and y <= DECK + 9 and z == 26 then return T(K.brass, x) end   -- the neck
    -- along the axis (0.8, 0.6, 0) from the throat
    local vx, vy, vz = x - AX, y - AY, z - AZ
    local t = vx * 0.8 + vy * 0.6
    if t < 0 or t > 30 then return false end
    local px, py, pz = vx - t * 0.8, vy - t * 0.6, vz
    local d = sqrt(px * px + py * py + pz * pz)
    local r = 1.3 + 12 * (t / 30) ^ 2.6
    if abs(d - r) <= 0.9 then return T(t > 28 and K.gold or (d < r and K.copper or K.brass), x) end
    return false
  end)
  return assemble(m, base, parts)
end

-- --- 36:56 the TOY SHOP: sunflower yellow, red trim, a rainbow awning,
-- giant building blocks stacked on the roof and a spinning top
local function toyshop()
  local m, base, B = block({
    skin = plain(K.yellow), gf = plain(K.red), frame = K.white, box = K.fl_red,
    cornice = K.red, parapet = K.blue, band = K.white,
    deck = lattice(K.lat_blue_0),
  })
  local Z1, GF, DECK = B.Z1, B.GF, B.DECK
  local parts = {}
  parts[#parts + 1] = shopWindow(6, 57, 3, 14, Z1, K.white, K.glass_shop, 17)
  parts[#parts + 1] = awning(4, 59, 17, Z1, K.awn_rainbow, 5)
  -- the blocks: eight a side, each its own colour, stacked like a child would
  local BLOCKS = { { 8, 30, 0, K.rb_1 }, { 17, 30, 0, K.rb_5 }, { 12, 30, 1, K.rb_3 }, { 8, 20, 0, K.rb_4 },
                   { 9, 21, 1, K.rb_7 }, { 17, 20, 0, K.rb_2 } }
  parts[#parts + 1] = part(6, 58, DECK, DECK + 30, 8, Z1 - 3, function(x, y, z)
    for _, b in ipairs(BLOCKS) do
      local bx, bz, by = b[1], b[2], DECK + 1 + b[3] * 8
      if x >= bx and x < bx + 8 and z >= bz and z < bz + 8 and y >= by and y < by + 8 then
        local lx, ly = x - bx, y - by
        if (lx == 0 or lx == 7) and (ly == 0 or ly == 7) then return T(K.white, x) end
        -- a raised letter-dot in the middle of each face
        if (lx >= 3 and lx <= 4 and ly >= 3 and ly <= 4) then return T(K.white, x) end
        return T(b[4], x)
      end
    end
    -- the top: a cone point-down on the deck, a striped body, a handle
    local dx, dz = x - 44, z - 30
    local q = dx * dx + dz * dz
    local k = y - DECK
    if k >= 1 and k <= 8 and q <= (k * 1.3) ^ 2 then return T(K.rb_1 + (floor(sqrt(q) / 2) % 7), x) end
    if k > 8 and k <= 12 and q <= (10.4 - (k - 8) * 2.2) ^ 2 then return T(K.rb_1 + (floor(sqrt(q) / 2) % 7), x) end
    if k > 12 and k <= 17 and q <= 1.5 then return T(K.red, x) end
    return false
  end)
  return assemble(m, base, parts)
end

-- --- 52:48 CELADON WARE: the potter's -- glazed celadon tile, an ashlar
-- foot, three great crackle-glazed vases on the roof and two at the door
local function pottery()
  local VASE = function(k, h, w)
    local t = k / h
    return w * (0.55 + 0.45 * math.sin(3.1416 * min(1, t * 1.15)) - (t > 0.82 and 0.2 or 0)) + (t > 0.93 and 1 or 0)
  end
  local m, base, B = block({
    skin = coursed(K.jade_a, K.jade_b, K.jade_grout, 3), gf = ASHLAR, frame = K.trim_white, box = K.fl_white,
    cornice = K.trim_white, parapet = K.trim_white, band = K.trim_white,
    deck = lattice(K.lat_jade_0),
  })
  local Z1, GF, DECK = B.Z1, B.GF, B.DECK
  local parts = {}
  parts[#parts + 1] = shopWindow(8, 56, 3, 15, Z1, K.wood_dk, K.glass_shop, 12)
  -- { x, z, foot, height, belly }
  local V = { { 18, 28, DECK + 1, 26, 7 }, { 36, 22, DECK + 1, 34, 9 }, { 48, 38, DECK + 1, 18, 6 },
              { 3, 60, 1, 14, 3.5 }, { 60, 60, 1, 14, 3.5 } }
  for i, v in ipairs(V) do
    V[i] = { lathe(v[1], v[2], v[3], v[3] + v[4], function(k) return VASE(k, v[4], v[5]) end), v[3], v[4] }
  end
  parts[#parts + 1] = part(0, 63, 1, DECK + 35, 10, 63, function(x, y, z)
    for i = 1, #V do
      local inV, q, R = V[i][1](x, y, z)
      if inV then
        if q < (R - 1.3) ^ 2 then return T(K.shadow, x) end
        local t = (y - V[i][2]) / V[i][3]
        if t > 0.9 then return T(K.trim_white, x) end                          -- the lip
        if t > 0.6 and t < 0.66 then return T(K.brown, x) end                   -- an iron-spot band at the shoulder
        if t < 0.06 then return T(K.wood_dk, x) end                            -- the unglazed foot
        return T(K.vase_cel, floor(atan2(z, x) * 30) + y * 7)
      end
    end
    return false
  end)
  return assemble(m, base, parts)
end

-- --- 60:48 the DINER: white enamel over chrome, a red band, a window the
-- width of the counter, DINER in neon, and a giant iced donut on the roof
local function diner()
  local m, base, B = block({
    skin = plain(K.render_white), gf = plain(K.chrome), frame = K.red, plinthSkin = coursed(K.red, K.red, K.chrome, 3),
    cornice = K.red, parapet = K.red, band = K.red,
    deck = function(x, z) return T(K.terrazzo, x + z * 53) end,
    doors = { { face = "s", x0 = 18, x1 = 30, head = 15, leaf = K.chrome, deep = 4, frame = K.red } },
  })
  local Z1, GF, DECK = B.Z1, B.GF, B.DECK
  local parts = {}
  parts[#parts + 1] = shopWindow(34, 59, 3, 15, Z1, K.chrome, K.glass_shop, 6)
  parts[#parts + 1] = awning(33, 60, 17, Z1, K.awn_rw, 4)
  -- DINER in red neon on a white board along the roof's front edge
  parts[#parts + 1] = signBoard("DINER", 18, DECK + 11, Z1 - 1, K.neon_red, K.white, 2)
  parts[#parts + 1] = part(16, 48, DECK, DECK + 3, Z1 - 1, Z1 - 1, function(x) return (x == 17 or x == 46) and T(K.chrome, x) or false end)
  -- the donut standing on its rim, leaning back to show the street its
  -- icing (and the sky too), sprinkles
  local DX, DY, DZ = 32, DECK + 24, 30
  local ring = torusXY(DX, DY, DZ, 9, 5.5)
  parts[#parts + 1] = part(14, 50, DECK, DECK + 40, 14, 46, function(x, y, z)
    local zz = z + floor((y - DY) * 0.5)
    local inR, d = ring(x, y, zz)
    if inR then
      if zz >= DZ + 1 and y >= DY - 12 then
        local h = hash(x, y, z)
        if h % 11 == 0 then return T(({ K.rb_1, K.rb_3, K.rb_5, K.white })[h % 4 + 1], x) end
        return T(K.pink, x)
      end
      return T(K.bread, x)
    end
    if (x == DX - 5 or x == DX + 5) and z == DZ + 7 and y <= DY - 13 then return T(K.chrome, x) end
    return false
  end)
  return assemble(m, base, parts)
end

-- --- 68:48 the CHIEF'S HOUSE (tatami inside): a townhouse of the old
-- kind -- a lattice front, white plaster over it, a tiled pent roof between
-- the floors, a noren at the door; on the roof, a raked gravel garden, a
-- pine, a stone lantern
local function chief()
  local m, base, B = block({
    skin = plain(K.stucco_white), gf = plain(K.koshi), frame = K.wood_dk, glass = K.koshi,
    cornice = K.wood_dk, parapet = K.wood_dk, band = K.wood_dk, lift = 3,
    deck = function(x, z) return T(z % 3 == 0 and K.sand_line or K.sand, x) end,
    doors = { { face = "s", x0 = 18, x1 = 30, head = 15, leaf = K.koshi, deep = 4, frame = K.wood_dk } },
  })
  local Z1, GF, DECK = B.Z1, B.GF, B.DECK
  local parts = {}
  -- the pent roof: kawara falling toward the street across the whole front
  parts[#parts + 1] = part(1, 62, 17, 23, Z1 + 1, Z1 + 6, function(x, y, z)
    local ey = 23 - floor((z - Z1 - 1) * 0.8)
    if y == ey then return TILE.kawara(x, z - Z1) end
    if y == ey - 1 and z == Z1 + 6 then return T(K.kawara_line, x) end
    return false
  end)
  -- posts every eight across the plaster
  parts[#parts + 1] = part(3, 60, 24, B.WALL - 2, Z1 + 1, Z1 + 1, function(x)
    return ((x - 3) % 8 == 0) and T(K.wood_dk, x) or false
  end)
  -- the noren at the door, a white crest
  parts[#parts + 1] = part(18, 30, 9, 16, Z1 + 1, Z1 + 1, function(x, y)
    if (x - 18) % 4 == 3 and y < 15 then return false end
    local q = (x - 24) ^ 2 + (y - 12.5) ^ 2
    if q <= 5 and q >= 2 then return T(K.white, x) end
    return T(K.cloth_indigo, x)
  end)
  -- the roof garden: three mossy rocks, a pine in cloud-pruned pads, a lantern
  local ROCKS = { { 16, 22, 4 }, { 22, 26, 2.6 }, { 44, 40, 3.4 } }
  parts[#parts + 1] = part(6, 58, DECK, DECK + 24, 8, Z1 - 3, function(x, y, z)
    local k = y - DECK
    for _, r in ipairs(ROCKS) do
      local q = (x - r[1]) ^ 2 + (z - r[2]) ^ 2 + (k * 1.4) ^ 2
      if k >= 1 and q <= r[3] * r[3] then return T(k >= r[3] - 1 and K.moss or K.rock, x) end
    end
    -- the pine: a leaning trunk, three flat pads of needles
    local tx = 40 + floor(k * 0.25)
    if k >= 1 and k <= 16 and abs(x - tx) <= 1 and abs(z - 22) <= 1 then return T(K.wood_dk, x) end
    for _, p in ipairs({ { 38, 22, 9, 6 }, { 46, 24, 13, 5 }, { 42, 20, 17, 4 } }) do
      local q = (x - p[1]) ^ 2 + (z - p[2]) ^ 2
      if k >= p[3] and k <= p[3] + 1 and q <= p[4] * p[4] then return T(k == p[3] + 1 and K.leaf or K.leaf_dk, x) end
    end
    -- the lantern: foot, post, firebox, cap
    local dx, dz = abs(x - 22), abs(z - 38)
    if k >= 1 and k <= 2 and dx <= 2 and dz <= 2 then return T(K.rock, x) end
    if k >= 3 and k <= 6 and dx <= 0 and dz <= 0 then return T(K.rock, x) end
    if k >= 7 and k <= 9 and dx <= 2 and dz <= 2 then return (dx <= 1 and dz <= 1 and k == 8) and T(K.lantern_red, x) or T(K.rock, x) end
    if k == 10 and dx <= 3 and dz <= 3 then return T(K.rock, x) end
    if k == 11 and dx <= 1 and dz <= 1 then return T(K.rock, x) end
    return false
  end)
  return assemble(m, base, parts)
end

-- --- 76:48 the GALLERY: a white box, one great rainbow across its blind
-- upper floor (the city of rainbow dreams), a glass front, and a red ring
-- on the roof that is either art or not
local function gallery()
  local m, base, B = block({
    skin = plain(K.render_white), gf = plain(K.render_white), frame = K.render_grey, blind = true,
    cornice = K.render_grey, parapet = K.render_white, band = K.render_grey,
    deck = function(x, z) return T(K.gravel, x + z * 53) end,
  })
  local Z1, GF, DECK = B.Z1, B.GF, B.DECK
  local parts = {}
  parts[#parts + 1] = shopWindow(6, 57, 3, 15, Z1, K.render_grey, K.glass_shop, 17)
  -- the mural: seven bands, a cloud at each foot
  parts[#parts + 1] = part(4, 59, GF + 2, B.WALL - 2, Z1, Z1, function(x, y)
    local r = sqrt((x - 31.5) ^ 2 + (y - GF + 4) ^ 2)
    local band = floor((r - 11) / 2.4)
    if band >= 0 and band <= 6 then return T(K.rb_7 - band, x) end
    for _, cx in ipairs({ 13, 50 }) do
      if (x - cx) ^ 2 + ((y - GF - 4) * 1.6) ^ 2 <= 30 then return T(K.white, x) end
    end
    return false
  end)
  -- the ring, leaning, on a black plinth
  local ring = torusXY(32, DECK + 16, 30, 11, 2)
  parts[#parts + 1] = part(16, 48, DECK, DECK + 32, 24, 36, function(x, y, z)
    local zz = z + floor((y - DECK - 16) * 0.35)               -- leaning back
    if ring(x, y, zz) then return T(K.red, x) end
    if box(x, y, z, 26, 38, DECK + 1, DECK + 4, 26, 34) then return T(K.black, x) end
    return false
  end)
  return assemble(m, base, parts)
end

-- ============================================================== the places ==
-- key = the placement's top-left TILE; the plot is the template's.
-- { name, tiles wide, tiles deep }
Kit.PLACES = {
  CERULEAN_CITY = {
    ["16:20"] = { "badge", 12, 4 }, ["52:20"] = { "trashed", 12, 4 }, ["24:28"] = { "melanie", 12, 4 },
    ["28:20"] = { "dye", 12, 4 }, ["68:20"] = { "painter", 12, 4 }, ["36:48"] = { "bakery", 12, 4 },
    ["56:48"] = { "glassworks", 12, 4 }, ["24:44"] = { "bike", 8, 8 },
  },
  CELADON_CITY = {
    ["4:8"] = { "flatsTall", 8, 12 }, ["28:8"] = { "perfumery", 12, 12 }, ["56:12"] = { "teahouse", 8, 8 },
    ["64:12"] = { "watchmaker", 8, 8 }, ["72:12"] = { "apothecary", 8, 8 }, ["40:28"] = { "pavilion", 12, 4 },
    ["64:32"] = { "prize", 8, 8 }, ["76:32"] = { "cinema", 8, 8 }, ["84:32"] = { "bathhouse", 8, 8 },
    ["4:48"] = { "radio", 8, 8 }, ["28:48"] = { "bookshop", 8, 8 }, ["36:48"] = { "records", 8, 8 },
    ["36:56"] = { "toyshop", 8, 8 }, ["52:48"] = { "pottery", 8, 8 }, ["60:48"] = { "diner", 8, 8 },
    ["68:48"] = { "chief", 8, 8 }, ["76:48"] = { "gallery", 8, 8 },
  },
}
local BUILD = { badge = badge, trashed = trashed, melanie = melanie, dye = dye, painter = painter,
                bakery = bakery, glassworks = glassworks, bike = bike,
                flatsTall = flatsTall, perfumery = perfumery, teahouse = teahouse, watchmaker = watchmaker,
                apothecary = apothecary, pavilion = pavilion, prize = prize, cinema = cinema,
                bathhouse = bathhouse, radio = radio, bookshop = bookshop, records = records,
                toyshop = toyshop, pottery = pottery, diner = diner, chief = chief, gallery = gallery }

function Kit.model(sp, t, tx, ty, mapId)
  if Kit.ENABLED == false then return nil, "switched off" end
  if not sp or sp.W ~= Kit.SHEET_W or sp.H ~= Kit.SHEET_H then
    return nil, "sheet is not " .. Kit.SHEET_W .. "x" .. Kit.SHEET_H
  end
  local places = Kit.PLACES[mapId]
  local key = tostring(tx) .. ":" .. tostring(ty)
  local p = places and places[key]
  if not p then return nil, "no house of the kit's stands at " .. tostring(mapId) .. " " .. key end
  if #t.tiles ~= p[3] or #t.tiles[1] ~= p[2] then
    return nil, key .. " is not " .. p[2] .. "x" .. p[3] .. " tiles"
  end
  return BUILD[p[1]]()
end

return Kit
