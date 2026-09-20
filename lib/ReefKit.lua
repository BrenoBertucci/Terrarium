-- Voxel world mode: THE WATER GARDEN -- what grows in, on and beside the big
-- waters.
--
-- The water is a translucent sheet over a terraced bed (lib/Water.lua,
-- ChunkMesher), and the bed was bare sand everywhere. Here it grows, in the
-- zones a real shore has, by how far a cell lies from land:
--
--   the BANK    (against the land) cattails and reeds standing OUT of the
--               water along the land's side of the cell, mossy stones at
--               their feet
--   the PADS    (one cell out) water lilies lying on the sheet -- pads with
--               a notch and veins, pink and white flowers -- on stems that
--               go down to the bed, seagrass under them
--   the GARDEN  (three cells out, where the bed is deep enough for it)
--               seagrass in clumps, kelp with fronds reaching for the
--               surface, branching and brain and table corals, sea fans,
--               tube sponges, anemones, clover weed, piles of mossy stone
--               -- in PATCHES with open sand between them
--
-- ONLY IN BIG WATER: the connected body (a bridge's cells count -- the pier
-- is where the player stands to look down) must be BIG cells or more. A
-- pond, a canal and a fountain stay clean.
--
-- One model per KEY (zone, variant, the bed terrace under the cell, and for
-- a bank which sides are land), sunk to that terrace; the cell stays water (`overWater`, the
-- seam lib/BridgeKit.lua made) and the sheet over it thins to lagoon water
-- (`clearWater`). The sheet's draw raises Voxel3D's `reefOn`, so what stands
-- under the waterline is absorbed and lit by the caustics like the bed, in
-- its own colours.
--
-- And it MOVES, each plant its own way. Every voxel knows which plant it is
-- part of (`motion`: its KIND, a draw of its own so no two stands move in
-- step, and the heights its give is measured between); Buildings packs that
-- into the shade of each corner (Kit.pack), and the reef branch of
-- lib/Voxel3D.lua's vertex stage answers three things with it:
--   the WATER  -- a pad rides the sheet's own swell, so it can never sink
--                 into a crest or hang over a trough; what grows under it
--                 goes to and fro with every train passing overhead (the
--                 parcel's orbit), kelp with a slow wave climbing its stalk
--                 and a lean down the current;
--   the WIND   -- the reeds and cattails, above the water only;
--   a SWIMMER  -- its hull shoves the garden aside, and the wake it leaves
--                 is an impulse each kind answers with its own spring
--                 (lib/WakeFX.lua lays it, VoxelScene hands it over).
-- Stone, coral and sponge stand still: that is what the rest moves against.
--
-- The palette (assets/buildings/reef_kit.png) is painted by
-- tools/reef_sheet.py. Nothing here is extracted from the ROM.

local V = ...

local Kit = { SHEET = "assets/buildings/reef_kit.png", SHEET_W = 32,
              WATER = 20, BRIDGE = 60,
              BIG = 150,       -- cells of connected water that make a big one
              FLOOD_MAX = 6000,
              CLEAR = 0.8,     -- the sheet over a garden reads this many tiles from
              --                  a bank: lagoon water, or the deep hides all of it
              SWAY = 1.8,      -- a reed's reach at the tip, world px per unit
              --                  of Wind.amount() (the shader's `sway`)
              SURFACE = -2,    -- Water.BASE
              -- per zone: the bed terrace it stands on, how much of its cells
              -- grow, and how many variants it has
              ZONES = {
                B = { fill = 0.62, variants = 3 },
                P = { fill = 0.48, variants = 4 },
                G = { fill = 0.62, variants = 8 },
              },
              PATCH = 4, PATCH_FILL = 0.75 }

local floor, sqrt, max, min = math.floor, math.sqrt, math.max, math.min
local C = 16

-- tools/reef_sheet.py PALETTE, in the same order
local T = { rock = 0, rockLit = 1, moss = 2, pebble = 3,
            pink = 4, pinkTip = 5, magenta = 6, red = 7,
            orange = 8, orangeTip = 9, fan = 10, fanRim = 11,
            kelp = 12, leaf = 13, kelpTip = 14,
            grassD = 15, grass = 16, grassTip = 17,
            clover = 18, cloverLit = 19,
            tube = 20, mouth = 21, white = 22, yellow = 23,
            reedD = 24, reed = 25, reedTip = 26, cattail = 27, cattailD = 28,
            padRim = 29, pad = 30, padVein = 31 }
Kit.T = T
-- How a plant moves -- the shader's reef branch switches on this, in this
-- order, so the numbers are a contract with lib/Voxel3D.lua.
Kit.KIND = { rigid = 0, pad = 1, stem = 2, reed = 3, kelp = 4, grass = 5,
             clover = 6, fan = 7, anemone = 8 }

-- The shade a corner of the sheet carries, the exact inverse of the decode
-- in lib/Voxel3D.lua's reef branch. Trees3D's packing: a 0..63 brightness
-- level, and in the fraction what the shader needs about the voxel --
--   the PLANT   kind * 8 + its own draw (0..71)
--   and a byte  how far up that plant this corner stands (0..255)...
--               ...except on a lily's PAD, where it is how far this corner
--               lies from the STALK (-5..5 in x and z, five bits and five).
--               A pad must not bend: every corner of it reads the wave and
--               the swimmer at that one point, so the leaf and its flower
--               move as one rigid thing. Carried as a reach from the corner
--               rather than a place in the cell, because a pad's rim can sit
--               exactly on the cell's edge and would then read its stalk a
--               cell over. (A stalk needs none of this: it IS that point.)
-- Half a code of margin, so float32 never rounds one into its neighbour.
function Kit.pack(shade, plant, x, y, z)
  local lvl = max(1, floor(min(math.abs(shade), 1) * 63 + 0.5))
  local code, v = 0, 0
  if plant then
    code = plant.code
    if plant.ax then
      local dx = max(-5, min(5, plant.ax - x)) + 5
      local dz = max(-5, min(5, plant.az - z)) + 5
      v = dx * 16 + dz
    else
      v = floor(max(0, min(1, (y - plant.base) / plant.ref)) * 255 + 0.5)
    end
  end
  return (shade < 0 and -1 or 1) * (lvl + (code * 256 + v + 0.5) / 32768) / 64
end

-- Which plant a corner of an emitted face belongs to: the voxel on the
-- solid side of the face, at that corner's end of the run -- a merged run
-- spans several voxels, and each end answers for its own, so a face shared
-- by two stands never makes either tear off its other faces.
function Kit.plantAt(m, quad, i)
  local c, v, plane = quad[i], {}, 1
  for a = 1, 3 do
    local lo, hi = quad[1][a], quad[1][a]
    for j = 2, 4 do lo, hi = min(lo, quad[j][a]), max(hi, quad[j][a]) end
    if lo == hi then
      plane, v[a] = a, lo
    elseif c[a] >= hi then
      v[a] = hi - 1
    else
      v[a] = c[a]
    end
  end
  local x, y, z = v[1], v[2], v[3]
  local bx, by, bz = x, y, z
  if plane == 1 then bx = x - 1 elseif plane == 2 then by = y - 1 else bz = z - 1 end
  if m.at(bx, by, bz) then return m.motion(bx, by, bz) end
  return m.motion(x, y, z)
end

-- a hash in [0, 1) of three numbers: the same garden on every load
local function hash(a, b, c)
  return (math.sin(a * 12.9898 + b * 78.233 + c * 37.719) * 43758.5453) % 1
end

local function wet(tileAt, tx, ty)
  local a, b = tileAt(tx, ty), tileAt(tx + 1, ty)
  local c, d = tileAt(tx, ty + 1), tileAt(tx + 1, ty + 1)
  local W, B = Kit.WATER, Kit.BRIDGE
  return (a == W and b == W and c == W and d == W)
      or (a == B and b == B and c == B and d == B)
end

-- Is the body of water this cell belongs to a big one? A flood fill over
-- wet cells, once per body: every cell it reaches gets the answer.
local bodies = {}
local function big(tileAt, cx, cy, seed)
  local known = bodies[seed]
  if not known then known = {} bodies[seed] = known end
  local k0 = cx * 4096 + cy
  if known[k0] ~= nil then return known[k0] end
  local queue, head, seen = { { cx, cy } }, 1, { [k0] = true }
  while queue[head] and #queue < Kit.FLOOD_MAX do
    local x, y = queue[head][1], queue[head][2]
    head = head + 1
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, ny = x + d[1], y + d[2]
      local k = nx * 4096 + ny
      if not seen[k] and wet(tileAt, nx * 2, ny * 2) then
        seen[k] = true
        queue[#queue + 1] = { nx, ny }
      end
    end
  end
  local answer = #queue >= Kit.BIG
  for k in pairs(seen) do known[k] = answer end
  return answer
end
function Kit.forget() bodies = {} end

-- How deep the bed lies under the tile (tx, ty), the way ChunkMesher lays
-- it: a terrace (Water.BED) every BED_TILES tiles of 4-neighbour distance
-- from the nearest tile that is not water.
local BED, BED_TILES = { -5, -7, -9, -11, -13 }, 2
do
  local ok, Water = pcall(function() return V.require("Water") end)
  if ok and type(Water) == "table" and Water.BED then
    BED, BED_TILES = Water.BED, Water.BED_TILES or 2
  end
end
local function wetTile(tileAt, tx, ty)
  if tileAt(tx, ty) == Kit.WATER then return true end
  local cx, cy = tx - tx % 2, ty - ty % 2
  local B = Kit.BRIDGE
  return tileAt(cx, cy) == B and tileAt(cx + 1, cy) == B
     and tileAt(cx, cy + 1) == B and tileAt(cx + 1, cy + 1) == B
end
local function bedUnder(tileAt, tx, ty)
  local far = #BED * BED_TILES
  for r = 1, far do
    for i = 0, r do
      local j = r - i
      if not (wetTile(tileAt, tx + i, ty + j) and wetTile(tileAt, tx - i, ty + j)
              and wetTile(tileAt, tx + i, ty - j) and wetTile(tileAt, tx - i, ty - j)) then
        return BED[math.ceil(r / BED_TILES)], r
      end
    end
  end
  return BED[#BED], far
end

-- What grows on the water cell whose top-left tile is (tx, ty): a key --
-- zone, variant, the bed it stands on, and for a bank which sides are land
-- (n = 1, e = 2, s = 4, w = 8): "G3s11", "G7s13m" (mirrored), "P2s7",
-- "B1s5:5" -- or nil for open water.
function Kit.spec(tileAt, tx, ty, seed)
  if Kit.ENABLED == false then return nil end
  local W = Kit.WATER
  if not (tileAt(tx, ty) == W and tileAt(tx + 1, ty) == W
          and tileAt(tx, ty + 1) == W and tileAt(tx + 1, ty + 1) == W) then
    return nil
  end
  local cx, cy = floor(tx / 2), floor(ty / 2)
  seed = seed or 0
  local mask = 0
  if not wet(tileAt, tx, ty - 2) then mask = mask + 1 end
  if not wet(tileAt, tx + 2, ty) then mask = mask + 2 end
  if not wet(tileAt, tx, ty + 2) then mask = mask + 4 end
  if not wet(tileAt, tx - 2, ty) then mask = mask + 8 end
  -- the cheap questions first: most water grows nothing
  local roll = hash(cx, cy, seed + 1)
  if roll >= 0.62 then return nil end
  -- the bed under its four tiles: the deepest is what it stands on, the
  -- shallowest says how near the land is
  local deepest, near = 0, 99
  for dy = 0, 1 do
    for dx = 0, 1 do
      local bed, r = bedUnder(tileAt, tx + dx, ty + dy)
      if bed < deepest then deepest = bed end
      if r < near then near = r end
    end
  end
  local zone = (mask > 0 and "B") or (near <= 4 and "P") or (near >= 5 and deepest <= -9 and "G") or nil
  if not zone then return nil end            -- a band of open water between
  local Z = Kit.ZONES[zone]
  if roll >= Z.fill then return nil end
  if zone == "G" and hash(floor(cx / Kit.PATCH), floor(cy / Kit.PATCH), seed) >= Kit.PATCH_FILL then
    return nil
  end
  if not big(tileAt, cx, cy, seed) then return nil end
  local v = floor(hash(cx, cy, seed + 2) * Z.variants) + 1
  local key = zone .. v .. "s" .. (-deepest)
  if zone == "B" then return key .. ":" .. mask end
  return key .. (hash(cx, cy, seed + 3) < 0.5 and "m" or "")
end

-- ------------------------------------------------------------- the garden --
-- Every builder writes voxels through set(); y = 0 is the zone's bed.

local RIGID = { code = 0, base = 0, ref = 1 }

local function garden(top)
  local vox, mot, G = {}, {}, {}
  -- the plant the next voxels are part of: RIGID unless a builder of
  -- something soft says otherwise, and put back when it is done, so a
  -- stone laid after a weed is never mistaken for the weed
  local plant = RIGID
  -- `ax, az`: a pad's stalk, for the rigid leaf (Kit.pack). The draw is of
  -- the PLACE, not of the kind, so a lily's pad and its stalk share one.
  function G.as(kind, x, z, base, ref, ax, az)
    plant = { code = Kit.KIND[kind] * 8 + floor(hash(x, z, 17) * 8),
              base = base, ref = ref, ax = ax, az = az }
  end
  function G.rigid() plant = RIGID end
  function G.set(x, y, z, t)
    x, y, z = floor(x + 0.5), floor(y + 0.5), floor(z + 0.5)
    if x < 0 or x >= C or z < 0 or z >= C or y < 0 or y > top then return end
    local i = (y * C + z) * C + x
    vox[i], mot[i] = t, plant
  end
  local set = G.set
  -- (outside the box is empty: the index would wrap into the next row)
  function G.at(x, y, z)
    if x < 0 or x >= C or z < 0 or z >= C then return nil end
    return vox[(y * C + z) * C + x]
  end
  function G.motion(x, y, z)
    if x < 0 or x >= C or z < 0 or z >= C then return nil end
    return mot[(y * C + z) * C + x]
  end

  function G.dome(cx, cz, r, y0, h, t, tip)
    for x = cx - r, cx + r do
      for z = cz - r, cz + r do
        local d = ((x - cx) ^ 2 + (z - cz) ^ 2) / (r * r)
        if d <= 1 then
          local hi = y0 + floor(h * sqrt(1 - d) + 0.5)
          for y = y0, hi do
            set(x, y, z, (tip and y == hi and (x + z) % 2 == 0) and tip or t)
          end
        end
      end
    end
  end
  -- a pile of squared stone, moss on what looks up
  function G.stones(cx, cz, n, s)
    for i = 1, n do
      local w = 2 + floor(hash(i, s, 1) * 3)
      local x0 = cx + floor(hash(i, s, 2) * 5) - 3
      local z0 = cz + floor(hash(i, s, 3) * 5) - 3
      local h = 1 + floor(hash(i, s, 4) * 3)
      for x = x0, x0 + w - 1 do
        for z = z0, z0 + w - 1 do
          for y = 0, h do
            local t = T.rock
            if y == h then t = hash(x, z, s) < 0.4 and T.moss or T.rockLit end
            set(x, y, z, t)
          end
        end
      end
    end
  end
  -- one blade: dark at the root, pale at the tip, its top third leaning
  function G.blade(x, z, h, lean, c)
    for y = 0, h do
      local xx = x + ((y > h * 0.66) and lean or 0)
      set(xx, y, z, (y == h and c[3]) or (y > h * 0.45 and c[2]) or c[1])
    end
  end
  function G.clump(cx, cz, n, h0, h1, s, c)
    c = c or { T.grassD, T.grass, T.grassTip }
    for i = 1, n do
      local x = cx + floor(hash(i, s, 5) * 5) - 2
      local z = cz + floor(hash(i, s, 6) * 5) - 2
      local h = h0 + floor(hash(i, s, 7) * (h1 - h0 + 1))
      -- measured over the blade's own height: a short one's tip gives too
      G.as("grass", x, z, 0, max(2, min(h, top)))
      G.blade(x, z, min(h, top), floor(hash(i, s, 8) * 3) - 1, c)
    end
    G.rigid()
  end
  -- kelp: a stalk that wanders, a pair of fronds every other voxel
  function G.kelp(cx, cz, h)
    h = min(h, top)
    G.as("kelp", cx, cz, 0, 12)
    for y = 0, h do
      local x = cx + floor(y / 3) % 2
      set(x, y, cz, y == h and T.kelpTip or T.kelp)
      if y >= 2 and y % 2 == 0 and y < h then
        local side = (y % 4 == 0) and 1 or -1
        set(x + side, y, cz, T.leaf)
        set(x + side * 2, y + 1, cz, T.kelpTip)
        set(x, y, cz - side, T.leaf)
      end
    end
    G.rigid()
  end
  -- a branching coral: a trunk, three arms climbing outward, a nub on each
  function G.coral(cx, cz, h, t, tip)
    h = min(h, top)
    local trunk = max(1, floor(h * 0.35))
    for y = 0, trunk do set(cx, y, cz, t) end
    for i, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local x, z, len = cx, cz, h - trunk - (i % 2)
      for k = 1, len do
        if k % 2 == 1 then x, z = x + d[1], z + d[2] end
        set(x, trunk + k, z, k == len and tip or t)
        if k == floor(len / 2) then set(x + d[2], trunk + k, z + d[1], tip) end
      end
    end
  end
  -- (its stalk is stiff; the plate flexes from where it leaves the stalk)
  function G.fan(cx, cz, r, y0)
    G.as("fan", cx, cz, y0, r + 1)
    for y = 0, y0 do set(cx, y, cz, T.fan) end
    for dx = -r, r do
      for dy = 0, r do
        local d = dx * dx + dy * dy
        if d <= r * r then
          local rim = d > (r - 1) * (r - 1)
          if rim or (dx + dy) % 2 == 0 then
            set(cx + dx, y0 + dy, cz, rim and T.fanRim or T.fan)
          end
        end
      end
    end
    G.rigid()
  end
  function G.tube(cx, cz, r, h)
    h = min(h, top)
    for x = cx - r, cx + r do
      for z = cz - r, cz + r do
        local d = (x - cx) ^ 2 + (z - cz) ^ 2
        if d <= r * r + 0.5 then
          local core = d < (r - 1) * (r - 1) + 0.5
          for y = 0, h do
            if not (core and y == h) then set(x, y, z, T.tube) end
          end
          if core then set(x, h - 1, z, T.mouth) end
        end
      end
    end
  end
  -- (the rock it holds is rock; the crown on it stirs, and closes)
  function G.anemone(cx, cz)
    G.dome(cx, cz, 3, 0, 2, T.rock, T.rockLit)
    G.as("anemone", cx, cz, 3, 3)
    G.dome(cx, cz, 2, 3, 2, T.white, T.red)
    G.rigid()
  end
  function G.table(cx, cz, r, h)
    h = min(h, top)
    for y = 0, h - 1 do set(cx, y, cz, T.orange) set(cx + 1, y, cz, T.orange) end
    for x = cx - r, cx + r do
      for z = cz - r, cz + r do
        local d = (x - cx) ^ 2 + (z - cz) ^ 2
        if d <= r * r then set(x, h, z, d > (r - 1.5) ^ 2 and T.orangeTip or T.orange) end
      end
    end
  end
  -- clover weed: a stem, a cross of leaves on top and a smaller one half way
  function G.cloverWeed(cx, cz, h)
    h = min(h, top)
    G.as("clover", cx, cz, 0, max(2, h))
    for y = 0, h - 1 do set(cx, y, cz, T.grassD) end
    for _, d in ipairs({ { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      set(cx + d[1], h, cz + d[2], (d[1] == 0 and d[2] == 0) and T.cloverLit or T.clover)
    end
    local m = floor(h / 2)
    set(cx + 1, m, cz, T.clover) set(cx + 2, m, cz, T.cloverLit) set(cx + 1, m, cz + 1, T.clover)
    G.rigid()
  end
  -- a water lily: the pad on the sheet (notched, veined), its stem to the
  -- bed, and a flower on it if `petal`. It FLOATS: the pad and flower ride
  -- the sheet whole, and the stem gives more the higher it climbs.
  function G.lily(cx, cz, r, y, petal)
    -- the stalk is planted and gives more the higher it climbs; the leaf
    -- and its flower are ONE rigid thing, and they carry where the stalk is
    G.as("stem", cx, cz, 0, max(1, y))
    for yy = 0, y - 1 do set(cx, yy, cz, T.padRim) end
    G.as("pad", cx, cz, 0, 1, cx, cz)
    for x = cx - r, cx + r do
      for z = cz - r, cz + r do
        local dx, dz = x - cx, z - cz
        local d = dx * dx + dz * dz
        local notch = dx > 0 and dz >= 0 and dz <= dx * 0.5      -- the pad's cut
        if d <= r * r + 1 and not notch then
          local t = T.pad
          if d > (r - 1) * (r - 1) + 1 then t = T.padRim
          elseif dx == 0 or dz == 0 then t = T.padVein end
          set(x, y, z, t)
        end
      end
    end
    if petal then
      -- the flower: an open ring of outer petals, a cup of inner ones a
      -- voxel up, the stamens in it
      local px, pz = cx - 1, cz - 1
      local outer = petal == T.white and T.pinkTip or T.pinkTip
      local inner = petal
      for dx = -2, 2 do
        for dz = -2, 2 do
          local d = dx * dx + dz * dz
          if d >= 2 and d <= 5 and (dx + dz) % 2 ~= 0 or d == 4 then set(px + dx, y + 1, pz + dz, outer) end
          if d >= 1 and d <= 2 then set(px + dx, y + 2, pz + dz, inner) end
        end
      end
      for dx = -1, 1 do for dz = -1, 1 do set(px + dx, y + 1, pz + dz, inner) end end
      set(px, y + 2, pz, T.yellow)
      set(px, y + 3, pz, T.yellow)
    end
    G.rigid()
  end
  -- a cattail: the stalk out of the water, the brown head, the spike over it
  function G.cattail(x, z, h)
    for y = 0, h do
      local t = T.reed
      if y > h - 2 then t = T.reedTip
      elseif y > h - 6 then t = (y == h - 5) and T.cattailD or T.cattail
      elseif y < 4 then t = T.reedD end
      set(x, y, z, t)
    end
  end
  return G
end

local REED = { T.reedD, T.reed, T.reedTip }

-- The GARDEN's variants, by how tall a plant may stand (`H`)
local GARDEN = {
  function(G, H) G.clump(4, 5, 12, H * 0.5, H * 0.9, 1) G.clump(11, 10, 12, H * 0.4, H * 0.8, 2)
                 G.clump(12, 3, 7, H * 0.3, H * 0.6, 3) G.stones(5, 12, 2, 1) end,
  function(G, H) G.kelp(3, 4, H) G.kelp(8, 7, H - 1) G.kelp(12, 3, H) G.kelp(5, 12, H - 2)
                 G.kelp(11, 12, H) G.clump(8, 12, 6, 2, H * 0.4, 4) G.stones(9, 4, 1, 2) end,
  function(G, H) G.stones(8, 8, 3, 3) G.coral(5, 6, H * 0.8, T.pink, T.pinkTip)
                 G.coral(11, 10, H * 0.9, T.magenta, T.pink) G.coral(10, 4, H * 0.6, T.red, T.pinkTip)
                 G.clump(3, 12, 6, 2, H * 0.4, 5) end,
  function(G, H) G.dome(6, 7, 4, 0, min(4, H - 1), T.pink, T.pinkTip) G.table(11, 11, 4, min(6, H))
                 G.anemone(12, 3) G.clump(3, 13, 5, 2, H * 0.4, 6) end,
  function(G, H) G.cloverWeed(4, 4, H * 0.8) G.cloverWeed(9, 6, H * 0.6) G.cloverWeed(12, 11, H * 0.9)
                 G.cloverWeed(5, 11, H * 0.5) G.stones(9, 12, 2, 4) G.clump(13, 4, 5, 2, H * 0.4, 7) end,
  function(G, H) G.stones(8, 8, 2, 5) G.tube(5, 7, 2, H * 0.8) G.tube(10, 5, 1, H * 0.6)
                 G.tube(10, 11, 2, H * 0.7) G.fan(4, 13, min(4, H - 3), 2) G.clump(13, 13, 5, 2, H * 0.4, 8) end,
  function(G, H) G.stones(7, 8, 5, 6) G.clump(3, 3, 8, H * 0.3, H * 0.7, 9) G.clump(12, 12, 8, H * 0.3, H * 0.7, 10)
                 G.coral(12, 4, H * 0.6, T.orange, T.orangeTip) end,
  function(G, H) G.kelp(13, 13, H) G.kelp(2, 12, H - 1) G.coral(4, 4, H * 0.8, T.pink, T.pinkTip)
                 G.fan(11, 8, min(4, H - 3), 2) G.cloverWeed(8, 12, H * 0.6) G.tube(7, 3, 1, H * 0.5)
                 G.clump(9, 9, 8, 2, H * 0.6, 11) end,
}

-- The PADS: `y` is the sheet
local PADS = {
  function(G, y) G.lily(5, 5, 4, y, T.pink) G.lily(12, 10, 3, y) G.lily(4, 13, 2, y)
                 G.clump(12, 3, 8, 1, y - 2, 12) end,
  function(G, y) G.lily(9, 8, 4, y, T.white) G.lily(3, 3, 2, y) G.lily(13, 14, 2, y)
                 G.clump(3, 12, 8, 1, y - 2, 13) end,
  function(G, y) G.lily(4, 10, 3, y) G.lily(11, 5, 4, y, T.pink) G.lily(12, 13, 2, y)
                 G.stones(4, 3, 1, 7) G.clump(7, 14, 6, 1, y - 2, 16) end,
  function(G, y) G.lily(8, 8, 4, y, T.pink) G.lily(2, 2, 2, y) G.clump(3, 13, 8, 1, y - 2, 14)
                 G.clump(13, 3, 8, 1, y - 2, 15) end,
}

-- The BANK: reeds along every side that is land. `y` is the sheet.
local function bank(G, v, mask, y)
  local sides = { { 1, function(a, d) return a, d end }, { 2, function(a, d) return C - 1 - d, a end },
                  { 4, function(a, d) return a, C - 1 - d end }, { 8, function(a, d) return d, a end } }
  for _, S in ipairs(sides) do
    if mask % (S[1] * 2) >= S[1] then
      -- tufts: three or four stands along the side, each a handful of
      -- blades close together with the cattails standing out of the middle
      for tuft = 1, (v == 3) and 2 or 4 do
        local a0 = floor(hash(tuft, S[1], v) * (C - 4)) + 2
        local d0 = 1 + floor(hash(tuft, S[1], v + 9) * 3)
        for i = 1, 6 do
          local a = a0 + floor(hash(i, tuft, S[1] + v) * 5) - 2
          local d = d0 + floor(hash(i, tuft, S[1] + v + 20) * 3) - 1
          local x, z = S[2](a, max(0, d))
          -- measured from the bed to the tallest a cattail stands, so a
          -- tall stalk gives more at its tip than a short blade does
          G.as("reed", x, z, 0, y + 13)
          if i <= ((v == 2) and 1 or 2) then
            G.cattail(x, z, y + 8 + floor(hash(i, tuft, 3) * 5))
          else
            G.blade(x, z, y + 3 + floor(hash(i, tuft, 4) * 7), floor(hash(i, tuft, 5) * 3) - 1, REED)
          end
        end
      end
      G.rigid()
      if v == 3 then
        local x, z = S[2](8, 2)
        G.stones(x, z, 2, S[1])
      end
    end
  end
  if v == 2 then G.lily(8, 8, 2, y, T.white) end
end

function Kit.model(sp, key)
  if not sp or sp.W ~= Kit.SHEET_W then
    return nil, "sheet is not " .. Kit.SHEET_W .. " wide"
  end
  local zone, v, sink, rest = key:match("^(%a)(%d+)s(%d+)(.*)$")
  local Z = Kit.ZONES[zone or ""]
  v, sink = tonumber(v), tonumber(sink)
  if not (Z and v and sink and v >= 1 and v <= Z.variants) then
    return nil, "no water garden " .. tostring(key)
  end
  local sheet = sink + Kit.SURFACE           -- the model y the sheet lies at
  local G, top
  if zone == "B" then
    top = sheet + 13
    G = garden(top)
    bank(G, v, tonumber(rest:match(":(%d+)")) or 0, sheet)
  elseif zone == "P" then
    top = sheet + 2
    G = garden(top)
    PADS[v](G, sheet)
  else
    top = sheet - 2                           -- a voxel of water over the tallest
    G = garden(top)
    GARDEN[v](G, top)
  end
  local mirror = rest:find("m", 1, true) ~= nil
  local function at(x, y, z)
    return G.at(mirror and (C - 1 - x) or x, y, z)
  end
  -- which plant a voxel is part of, and how it moves (Kit.pack). A mirrored
  -- model mirrors where its stalks stand too, or every pad in it would reach
  -- for a stalk on the wrong side of the cell.
  local flipped = mirror and {} or nil
  local function motion(x, y, z)
    local rec = G.motion(mirror and (C - 1 - x) or x, y, z)
    if not (rec and flipped and rec.ax) then return rec end
    local f = flipped[rec]
    if not f then
      f = { code = rec.code, base = rec.base, ref = rec.ref,
            ax = C - 1 - rec.ax, az = rec.az }
      flipped[rec] = f
    end
    return f
  end
  return { at = at, motion = motion, W = C, ytop = top, zmin = 0, zmax = C - 1,
           noDown = true, sink = sink, overWater = Kit.WATER,
           clearWater = Kit.CLEAR }
end

return Kit
