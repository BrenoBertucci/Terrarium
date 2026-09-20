-- Voxel world mode: the ground of Lavender Town, and of the roads into it.
--
-- The drawn floor -- Lavender's generic Gen 1 checker, the routes' dithered
-- grass and speckled road -- is laid by the mesher as one flat plane wearing
-- the tile drawing: a coloured rectangle, the one surface with no depth of
-- its own, and the one the player looks at most. It is NOT kept. What stands
-- here is drawn from nothing, as ONE picture that runs across the town and
-- the three routes that meet it (8, 10 and 12) without a seam:
--
--   flagged paths   crazy paving in pale lilac stone. In town they run where
--                   feet go (gates, doors, the Tower); on a route they are
--                   the road the map already has, its edges let go ragged
--   the lawn        turf standing one voxel PROUD of the stones, in clumps
--                   along the verges, with clover, daisies and worn earth
--   lavender        in beds and drifts in town, thinning out along the roads
--   the pier        Route 12's boardwalk, in weathered planks
--   setts           Route 10's brick yard, in small squared stone
--
-- The lawn is the higher of the two on purpose: walkers stand on the stones
-- (`lift`) and wade ankle-deep through the turf, a puddle lies on a flag and
-- is lost in the grass, and the turf's edge throws the AO and the shadow a
-- flat drawing cannot. Tall grass and flower cells are laid too but NOT
-- claimed, so the blades and the blooms still stand, out of this turf.
--
-- HOW IT IS BUILT. Everything that is ART lives in tools/lavender_ground.py.
-- It paints all four maps on one canvas in WORLD coordinates -- every noise,
-- every stone, every street is a function of world position, which is the
-- whole reason nothing shows at a map's edge -- then cuts one sheet per map
-- (one texel a voxel: the sheet IS the map's plan) and writes one data file
-- per map: for each ground cell, which texels are turf and what grows. This
-- file only stands it up, a cell at a time. The cells round a placement
-- answer as PHANTOMS (Buildings.PHANTOM), read off the neighbour's own data
-- -- across a map's edge too, through the index -- so neither the hidden
-- faces nor the corner AO know where one map stops.
--
-- The template (data/voxel_heights.lua, `lavground`, `wild`) matches every
-- cell of the listed maps; the DATA says which are ground, and carries the
-- four tiles it was painted for, so a hack that moved a road gets the drawn
-- ground back there instead of a lawn across its new path.
-- Nothing here is extracted from the ROM.

-- the mod namespace (see main.lua): V.data loads a file out of data/
local V = ...

-- `INDEXES`: one per painted WORLD. Lavender and its three routes are one
-- picture (tools/lavender_ground.py); Vermilion City is another
-- (tools/vermilion_ground.py), with its own origin -- so a cell's neighbour
-- is only ever looked for inside its own world.
local Kit = { LIFT = 1, INDEXES = { "lavground_index", "vermground_index" } }

local floor = math.floor

local index = nil
local function maps()
  if index == nil then
    index = {}
    for world, name in ipairs(Kit.INDEXES) do
      local ok, t = pcall(V.data, name)
      if ok and type(t) == "table" and t.maps then
        for id, e in pairs(t.maps) do
          e.world = world
          index[id] = e
        end
      end
    end
  end
  return next(index) and index or nil
end

local loaded = {}
local function dataFor(mapId)
  local d = loaded[mapId]
  if d == nil then
    local m = maps()
    local e = m and m[mapId]
    local ok, t = false, nil
    if e then ok, t = pcall(V.data, e.data) end
    d = (ok and type(t) == "table" and t.cells) and t or false
    if d then d.entry = e end
    loaded[mapId] = d
  end
  return d or nil
end

-- One cell's strings, opened once: base[i] = 1 where turf stands, and what
-- grows on texel i -- a letter of `grows`, lower case one voxel, upper two.
-- `b` may be a single digit (the whole cell), `g` may be absent (nothing).
local opened = {}
local function cell(mapId, cx, cy)
  local id = mapId .. ":" .. cx .. ":" .. cy
  local o = opened[id]
  if o ~= nil then return o or nil end
  local d = dataFor(mapId)
  local src = d and d.cells[cx .. ":" .. cy]
  if not src then
    opened[id] = false
    return nil
  end
  o = { base = {}, extra = {}, kind = {}, tiles = src.t, claim = src.claim ~= false }
  local whole = #src.b == 1 and src.b:byte(1) - 48 or nil
  for i = 1, 256 do
    o.base[i] = whole or (src.b:byte(i) - 48)
    local g = src.g and src.g:sub(i, i) or "."
    if g == "." then
      o.extra[i] = 0
    else
      local low = g:lower()
      o.extra[i], o.kind[i] = (g == low) and 1 or 2, low
    end
  end
  opened[id] = o
  return o
end

-- The cell at (cx, cy) of `mapId`, which may lie off that map: then it is
-- some neighbour's, found through the index's world placement.
local function cellNear(mapId, cx, cy)
  local m = maps()
  local e = m and m[mapId]
  if not e then return nil end
  if cx >= 0 and cy >= 0 and cx < e.w and cy < e.h then return cell(mapId, cx, cy) end
  local gx, gy = e.gx + cx, e.gy + cy
  for id, o in pairs(m) do
    if o.world == e.world and gx >= o.gx and gy >= o.gy
       and gx < o.gx + o.w and gy < o.gy + o.h then
      return cell(id, gx - o.gx, gy - o.gy)
    end
  end
  return nil
end

-- What stands on the cell whose top-left tile is (tx, ty) of `mapId`, or nil.
function Kit.spec(tileAt, tx, ty, mapId)
  -- ENABLED: the A/B switch (tests/lavender_ground_probe.lua). It lives in
  -- the module because the build reads it; nothing outside can hold it off.
  if Kit.ENABLED == false or not mapId then return nil end
  local cx, cy = floor(tx / 2), floor(ty / 2)
  local o = cell(mapId, cx, cy)
  if not o then return nil end
  local t = o.tiles
  if tileAt(tx, ty) ~= t[1] or tileAt(tx + 1, ty) ~= t[2]
     or tileAt(tx, ty + 1) ~= t[3] or tileAt(tx + 1, ty + 1) ~= t[4] then
    return nil
  end
  local d = dataFor(mapId)
  return { map = mapId, cx = cx, cy = cy, sheet = d.entry.sheet,
           w = d.sheet.w, h = d.sheet.h }
end

function Kit.model(spec)
  local d = dataFor(spec.map)
  local cx, cy = spec.cx, spec.cy
  local o = d and cell(spec.map, cx, cy)
  if not o then return nil, "no cell " .. tostring(cx) .. ":" .. tostring(cy) end
  local PHANTOM = -1
  local SW, grows, mapId = d.sheet.w, d.grows, spec.map
  local origin = cy * 16 * SW + cx * 16     -- the sheet is the map's plan
  local base, extra, kind = o.base, o.extra, o.kind

  local function at(x, y, z)
    if x >= 0 and x <= 15 and z >= 0 and z <= 15 then
      local i = z * 16 + x + 1
      local b = base[i]
      if y <= b then return origin + z * SW + x end      -- stone, or turf
      local top = b + extra[i]
      if y > top then return nil end
      local g = grows[kind[i]]
      local list = (y == top) and g.top or g.stem
      return list[1 + (x * 7 + z * 13 + y * 5 + cx * 3 + cy) % #list]
    end
    -- the cell next door: solid at the slab, and as high as ITS turf says
    if y > 1 then return nil end
    local n = cellNear(mapId, cx + floor(x / 16), cy + floor(z / 16))
    if not n then return nil end
    -- (a texel may be VOID -- `b` = "-", under zero: the water's half of a
    -- shore cell, where Vermilion's quay stops -- and then nothing is there)
    local nb = n.base[(z % 16) * 16 + x % 16 + 1]
    if y == 0 then return nb >= 0 and PHANTOM or nil end
    return nb == 1 and PHANTOM or nil
  end

  local mask = nil
  if not o.claim then mask = { false, false, false, false } end
  return { at = at, W = 16, xmin = -1, xmax = 16, zmin = -1, zmax = 16,
           ytop = 3, claimMask = mask,
           -- a flank here is a sliver of turf one voxel high: let a run of
           -- them wear its first texel and merge (Buildings.emit)
           looseSides = true,
           -- a floor's contact shadows stay one voxel wide, and its open
           -- rows merge into sheets
           crispTops = true,
           -- an unclaimed cell (tall grass, flowers, a sign) keeps what
           -- stands in it and its own footing
           lift = o.claim and Kit.LIFT or nil,
           -- every voxel of a claimed cell is slab: the mesher need not
           -- paint (and the GPU need not shade) the ground under it
           covers = o.claim }
end

return Kit
