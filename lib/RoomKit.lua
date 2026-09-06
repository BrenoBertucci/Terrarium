-- Voxel world mode: the INTERIOR KIT -- hand-modelled furniture and room
-- walls for the Gen 1 interiors, on the same pipeline as the buildings
-- (data/voxel_heights.lua `buildings[<tileset>]`, matched by tile grid,
-- read from the atlas by Buildings.read, uploaded by Buildings.emit).
--
-- The class pins can only fold a tile's drawing onto a box: a counter is
-- a half-cell slab, a healing machine a 16px block with its display
-- standing on it as a card, a potted plant a paper cutout. Every model
-- here is instead a small piece of geometry the drawing IMPLIES -- the
-- pillar is round and carries a capital, the counter has a toe kick and
-- an overhanging top, the machine's pokeball tray slopes up the wall,
-- the plant is a round pot under a round bush -- and every visible voxel
-- still wears a texel of the room's own atlas, so the SGB palette and
-- any recolour ride along for free.
--
-- A template names its kind in `room`. Coordinates handed to `at` are
-- the model's own: x east, y up from the floor, z south (toward the
-- camera), with z = 0 the north edge of the matched grid. A template's
-- `topRows` are used as a PALETTE row -- composited above the drawing by
-- Buildings.read but never matched -- so a window segment can borrow the
-- panel's grey for the plain wall around it; `off` below is that row's
-- height in pixels and every art lookup skips it.

local V = ...

local RoomKit = {}

local WHITE, GREY, DARK, BLACK = 0, 1, 2, 3

RoomKit.WALL_H = 32        -- room walls, in voxels; the drawn band is 16

-- --------------------------------------------------------------- helpers --

-- Sprite pixel index at (x, y), clamped to the drawing.
local function pix(sp, x, y)
  if x < 0 then x = 0 elseif x >= sp.W then x = sp.W - 1 end
  if y < 0 then y = 0 elseif y >= sp.H then y = sp.H - 1 end
  return y * sp.W + x
end

local function findShade(sp, shade, x0, y0, x1, y1)
  for y = y0, y1 do
    for x = x0, x1 do
      local i = y * sp.W + x
      if sp.col[i] == shade then return i end
    end
  end
  return nil
end

-- One texel per GB shade: from the palette rows first, then the drawing.
local function palette(sp, off)
  local P = {}
  for s = WHITE, BLACK do
    local i = nil
    if off > 0 then i = findShade(sp, s, 0, 0, sp.W - 1, off - 1) end
    P[s] = i or findShade(sp, s, 0, 0, sp.W - 1, sp.H - 1)
  end
  local any = P[GREY] or P[DARK] or P[BLACK] or P[WHITE] or 0
  for s = WHITE, BLACK do P[s] = P[s] or any end
  return P
end

local function inBox(x, y, z, x0, y0, z0, x1, y1, z1)
  return x >= x0 and x <= x1 and y >= y0 and y <= y1 and z >= z0 and z <= z1
end

-- A straight wall segment `c.W` wide, 16 deep (z 0..15), `c.h` tall.
-- The drawn 16px band folds up at the bottom, or at the top when
-- `c.artTop` (a window, a hanging sign); the rest is the palette's grey
-- with a dark rail where the band ends and a two-course cornice.
-- `c.recess(sx, sy)` sinks a pane that many voxels; `c.jut(sx, sy)` lets a
-- board stand proud of the face by that many.
local function wallVoxel(c, x, y, z)
  if x < 0 or x >= c.W or y < 0 or y >= c.h then return nil end
  local artY0 = c.artTop and (c.h - 16) or 0
  local inArt = y >= artY0 and y < artY0 + 16
  if inArt then
    local sy = c.off + 15 - (y - artY0)
    local sx = x
    if z > 15 then
      local j = c.jut and c.jut(sx, sy) or 0
      if z <= 15 + j then return pix(c.sp, sx, sy) end
      return nil
    end
    if z < 0 then return nil end
    local r = c.recess and c.recess(sx, sy) or 0
    if r > 0 and z > 15 - r then return nil end
    return pix(c.sp, sx, sy)
  end
  if z < 0 or z > 15 then return nil end
  if y == c.h - 1 then return c.P[BLACK] end
  if y == c.h - 2 then return c.P[DARK] end
  if (not c.artTop and y == 16) or (c.artTop and y == artY0 - 1) then
    return c.P[DARK]
  end
  return c.P[GREY]
end

-- ------------------------------------------------------------------ kinds --

local kinds = {}

-- wall: a 2x2-tile segment. Variants by template fields: artTop, recess
-- (pane depth, applied inside a 1px frame), jut (board relief).
function kinds.wall(sp, t, off, P)
  local W = sp.W
  local recess, jut = nil, nil
  if t.recess and t.recess > 0 then
    local r = t.recess
    recess = function(sx, sy)
      local ay = sy - off
      if sx >= 1 and sx <= W - 2 and ay >= 1 and ay <= 14 then return r end
      return 0
    end
  end
  if t.jut and t.jut > 0 then
    local j = t.jut
    jut = function(sx, sy)
      local ay = sy - off
      if sx >= 1 and sx <= W - 2 and ay >= 2 and ay <= 13 then return j end
      return 0
    end
  end
  local c = { sp = sp, W = W, h = t.height or RoomKit.WALL_H, off = off,
              P = P, artTop = t.artTop, recess = recess, jut = jut }
  return {
    at = function(x, y, z) return wallVoxel(c, x, y, z) end,
    W = W, ytop = c.h - 1, xmin = 0, xmax = W - 1,
    zmin = 0, zmax = 15 + (t.jut or 0),
  }
end

-- pillar: 2 cols x 6 rows -- four rows of shaft against the wall band,
-- then the plinth (base) in its own cell. A round shaft on a square
-- plinth, wearing the drawing's own light/dark halves as its shading,
-- with a capital above the wall's cornice -- the ceiling it holds up is
-- implied, not drawn.
function kinds.pillar(sp, t, off, P)
  local W = sp.W
  local h = t.height or RoomKit.WALL_H
  local wall = { sp = sp, W = W, h = h, off = off, P = P }
  local top = 48
  local cx, cz = 7.5, 39.5
  return {
    at = function(x, y, z)
      -- capital
      if y >= top - 4 and y <= top - 1 and x >= 1 and x <= 14
          and z >= 33 and z <= 46 then
        local dx, dz = x - cx, z - cz
        if dx * dx + dz * dz <= 7.2 * 7.2 then
          if y == top - 1 then return P[DARK] end
          return pix(sp, x, off + 31 - (y - 16))
        end
      end
      -- shaft
      if y >= 16 and y <= top - 1 and x >= 2 and x <= 13
          and z >= 34 and z <= 45 then
        local dx, dz = x - cx, z - cz
        local r = (y <= 17) and 6.4 or 5.4
        if dx * dx + dz * dz <= r * r then
          return pix(sp, x, off + 31 - (y - 16))
        end
      end
      -- plinth
      if inBox(x, y, z, 0, 0, 32, 15, 15, 47) then
        if y == 15 then return P[GREY] end
        return pix(sp, x, off + 47 - y)
      end
      -- the wall behind, plain
      if z <= 15 then
        local wv = wallVoxel(wall, x, y, z)
        if wv and y < 16 then return P[GREY] end
        return wv
      end
      return nil
    end,
    W = W, ytop = top - 1, xmin = 0, xmax = W - 1, zmin = 0, zmax = 47,
  }
end

-- machine: 4 cols x 4 rows -- the healing machine. Rows 0-1 are the
-- wall with the pokeball tray drawn on it; rows 2-3 the console. The
-- console is a 16-deep, 16-tall block with its screen sunk one voxel and
-- a bordered top; the tray becomes a panel that slopes from the top of
-- the console up the wall, one step per voxel, wearing the tray art.
function kinds.machine(sp, t, off, P)
  local W = sp.W
  local h = t.height or RoomKit.WALL_H
  local wall = { sp = sp, W = W, h = h, off = off, P = P }
  return {
    at = function(x, y, z)
      -- the sloped display: 16 steps from (y 16, z 15) up to (y 31, z 0)
      if y >= 16 and y <= 31 and x >= 7 and x <= 24 then
        local k = y - 16
        local z0 = 15 - k
        if z >= z0 and z <= z0 + 3 then
          if x == 7 or x == 24 then return P[DARK] end
          return pix(sp, x, off + 15 - k)
        end
      end
      -- the console
      if inBox(x, y, z, 0, 0, 16, W - 1, 15, 31) then
        if y == 15 then
          if x == 0 or x == W - 1 or z == 16 or z == 31 then return P[DARK] end
          return P[WHITE]
        end
        local sy = off + 31 - y
        -- the screen (tiles 76/77, columns 8..23 of the top console row)
        -- sinks one voxel inside its frame
        if z == 31 and x >= 9 and x <= 22 and sy >= off + 17
            and sy <= off + 22 then
          return nil
        end
        return pix(sp, x, sy)
      end
      -- the wall behind, plain where the tray was drawn
      if z <= 15 then
        local wv = wallVoxel(wall, x, y, z)
        if wv and y < 16 then return P[GREY] end
        return wv
      end
      return nil
    end,
    W = W, ytop = h - 1, xmin = 0, xmax = W - 1, zmin = 0, zmax = 31,
  }
end

-- counter: 2x2 -- top tile over front tile. 12 tall: a toe kick two
-- voxels high and two deep, the drawn front panel on the body, and a
-- two-voxel top slab that overhangs the front by one, wearing the top
-- tile stretched over the cell.
function kinds.counter(sp, t, off, P)
  local W = sp.W
  return {
    at = function(x, y, z)
      if x < 0 or x >= W then return nil end
      if y >= 10 and y <= 11 then
        if z >= 1 and z <= 16 then
          if z == 16 and y == 10 then return P[DARK] end
          return pix(sp, x, off + math.floor((z - 1) / 2))
        end
        return nil
      end
      if y >= 2 and y <= 9 then
        if z >= 3 and z <= 15 then return pix(sp, x, off + 8 + (9 - y)) end
        return nil
      end
      if y >= 0 and y <= 1 then
        if z >= 5 and z <= 15 then return P[BLACK] end
        return nil
      end
      return nil
    end,
    W = W, ytop = 11, xmin = 0, xmax = W - 1, zmin = 1, zmax = 16,
  }
end

-- pc: 2 cols x 3 rows of the same monitor-over-drive strip -- a rack of
-- three units. A 16-deep cabinet with each dark screen sunk one voxel,
-- a bordered top, and a keyboard shelf out front at desk height.
function kinds.pc(sp, t, off, P)
  local W = sp.W
  local H = sp.H - off                 -- 24
  return {
    at = function(x, y, z)
      -- keyboard shelf
      if inBox(x, y, z, 2, 9, 24, 13, 10, 27) then
        if y == 10 then return P[WHITE] end
        return P[DARK]
      end
      if inBox(x, y, z, 0, 0, 8, W - 1, H - 1, 23) then
        if y == H - 1 then
          if x == 0 or x == W - 1 or z == 8 or z == 23 then return P[DARK] end
          return P[GREY]
        end
        local i = pix(sp, x, off + (H - 1) - y)
        if z == 23 and x < 8 and sp.col[i] == BLACK then return nil end
        return i
      end
      return nil
    end,
    W = W, ytop = H - 1, xmin = 0, xmax = W - 1, zmin = 8, zmax = 27,
  }
end

-- couch: 2 cols x 4 rows -- arm column beside cushion column, drawn
-- from above for three rows, then the front base row. An L: the arm
-- stands 14 tall along the west, a back cushion along the north, the
-- seat at 8 (where the authored figure sits), the base row folded up as
-- the front. `paint` on the template supplies the drawing WITHOUT the
-- man, so his head is not upholstered into the arm.
function kinds.couch(sp, t, off, P)
  local W = sp.W
  local function topOrFront(x, y, z, ymax)
    if z >= 24 then
      local yy = y
      if yy > 7 then yy = 7 end
      return pix(sp, x, off + 31 - yy)
    end
    return pix(sp, x, off + z)
  end
  return {
    at = function(x, y, z)
      if x < 0 or x >= W or z < 0 or z > 31 or y < 0 then return nil end
      -- arm, west column, rounded at the top
      if x <= 7 then
        local h = 13
        if y <= h then
          if y >= 12 and (x == 0 or x == 7) then return nil end
          return topOrFront(x, y, z)
        end
        return nil
      end
      -- back cushion, north end
      if z <= 3 and y <= 11 then
        if y >= 10 and z == 3 then return nil end
        return topOrFront(x, y, z)
      end
      -- seat
      if y <= 7 then return topOrFront(x, y, z) end
      return nil
    end,
    W = W, ytop = 13, xmin = 0, xmax = W - 1, zmin = 0, zmax = 31,
  }
end

-- plant: 2 cols x 4 rows -- bush over pot, both drawn face-on. The pot
-- is a round tub in the south cell (its drawn shape wrapped around),
-- the bush an ellipsoid resting on its rim and leaning a little north
-- over the empty cell, wearing the bush drawing projected from the front
-- so it reads the same from every side.
function kinds.plant(sp, t, off, P)
  local W = sp.W
  local cx, cz = 7.5, 23.5
  -- The bush drawing's white checker is a highlight on a flat picture;
  -- wrapped around a ball it reads as white spots. Each white pixel wears
  -- its nearest leaf pixel instead, so the ball is leaf all over and the
  -- shading comes from the faces, as it does for every other voxel.
  local leaf = {}
  for sy = off, off + 15 do
    for sx = 0, W - 1 do
      local i = sy * W + sx
      if sp.col[i] ~= WHITE then
        leaf[i] = i
      else
        local best = nil
        for r = 1, 3 do
          for ny = sy - r, sy + r do
            for nx = sx - r, sx + r do
              if nx >= 0 and nx < W and ny >= off and ny <= off + 15 then
                local j = ny * W + nx
                if sp.col[j] ~= WHITE and sp.col[j] ~= BLACK then
                  best = j
                  break
                end
              end
            end
            if best then break end
          end
          if best then break end
        end
        leaf[i] = best or i
      end
    end
  end
  -- pot: 12 tall, waisted, a wider rim; the pot drawing's 16 rows are
  -- squeezed onto it so the rim band and the base band both survive
  local potH = 12
  return {
    at = function(x, y, z)
      if x < 0 or x >= W or z < 0 or z > 31 or y < 0 then return nil end
      -- bush: a ball resting on the rim, leaning a little north
      if y >= potH - 2 and y <= 31 then
        local dx, dy, dz = (x - cx) / 8.6, (y - 21) / 10.2, (z - 21) / 8.4
        if dx * dx + dy * dy + dz * dz <= 1 then
          local ay = math.floor((31 - y) * 16 / 21)
          if ay < 0 then ay = 0 elseif ay > 15 then ay = 15 end
          return leaf[pix(sp, x, off + ay)]
        end
      end
      -- pot
      if y < potH then
        local r = 5.8
        if y <= 1 then r = 5.0 elseif y >= potH - 2 then r = 6.9 end
        local dx, dz = x - cx, z - cz
        if dx * dx + dz * dz <= r * r then
          local ay = 16 + math.floor((potH - 1 - y) * 16 / potH)
          if ay > 31 then ay = 31 end
          return pix(sp, x, off + ay)
        end
      end
      return nil
    end,
    W = W, ytop = 31, xmin = 0, xmax = W - 1, zmin = 11, zmax = 31,
  }
end

-- ------------------------------------------------------- the Poke Mart --

-- A plain wall: no drawn band, the palette's grey with the cornice.
local function plainWall(P, h, x, y, z, W)
  if x < 0 or x >= W or z < 0 or z > 15 or y < 0 or y >= h then return nil end
  if y == h - 1 then return P[BLACK] end
  if y == h - 2 then return P[DARK] end
  return P[GREY]
end

-- case: a display case drawn face-on over R tile rows (the Mart's back
-- wall: SALE case, glass fridge). The whole drawing stands as the south
-- face of a 16-deep body in the LAST cell of the run; the rows behind
-- are hidden floor. `sink` bands -- { artRow0, artRow1, depth } in rows
-- of the drawing from its top -- carve the niche and the glass back
-- inside a one-pixel frame. `backWall` raises a plain wall in the
-- first cell, a little taller than the case, so a cornice runs above.
function kinds.case(sp, t, off, P)
  local W = sp.W
  local artH = sp.H - off
  local zb0, zb1 = artH - 16, artH - 1
  local wallH = t.height or (artH + 4)
  local sink = t.sink or {}
  return {
    at = function(x, y, z)
      if inBox(x, y, z, 0, 0, zb0, W - 1, artH - 1, zb1) then
        if y == artH - 1 then
          if x == 0 or x == W - 1 or z == zb1 then return P[DARK] end
          return P[GREY]
        end
        local ay = artH - 1 - y
        for _, b in ipairs(sink) do
          if ay >= b[1] and ay <= b[2] and x >= 1 and x <= W - 2
              and z > zb1 - b[3] then
            return nil
          end
        end
        return pix(sp, x, off + ay)
      end
      if t.backWall then return plainWall(P, wallH, x, y, z, W) end
      return nil
    end,
    W = W, ytop = math.max(artH, t.backWall and wallH or 0) - 1,
    xmin = 0, xmax = W - 1, zmin = 0, zmax = zb1,
  }
end

-- rack: a free-standing shelf unit drawn face-on over R rows (two
-- shelves of goods, 16px each). Stands 16 deep in the last cell; each
-- shelf's goods sit three voxels back behind the board and the posts.
function kinds.rack(sp, t, off, P)
  local W = sp.W
  local artH = sp.H - off
  local zb0, zb1 = artH - 16, artH - 1
  local depth = t.shelfDepth or 3
  return {
    at = function(x, y, z)
      if not inBox(x, y, z, 0, 0, zb0, W - 1, artH - 1, zb1) then return nil end
      if y == artH - 1 then
        if x == 0 or x == W - 1 or z == zb1 or z == zb0 then return P[DARK] end
        return P[GREY]
      end
      local ay = artH - 1 - y
      local inShelf = (ay % 16) >= 2 and (ay % 16) <= 13
      if inShelf and x >= 1 and x <= W - 2 and z > zb1 - depth then
        return nil
      end
      return pix(sp, x, off + ay)
    end,
    W = W, ytop = artH - 1, xmin = 0, xmax = W - 1, zmin = zb0, zmax = zb1,
  }
end

-- booth: the clerk's booth back, 4 cols x 4 rows -- the bottle display
-- (rows 0-1) over the back panel (rows 2-3), whose east column is the
-- counter's north-east corner (89 end panel over the 41 work surface)
-- and whose row 3 at column 2 is work surface too. A 16-tall panel
-- closing the alcove (two cells deep on the west, where the drawing
-- draws it twice), the shelf of bottles on top of it with the bottles
-- set back behind their board, and the corner of the counter, 12 tall,
-- wearing the work-surface art on top.
function kinds.booth(sp, t, off, P)
  local W = sp.W                       -- 32
  local panelRow = off + 16            -- the 40 row
  return {
    at = function(x, y, z)
      if x < 0 or x >= W or z < 16 or z > 31 or y < 0 then return nil end
      -- the shelf of bottles, over the panel
      if y >= 16 and y <= 31 and z >= 16 and z <= 23 then
        local ay = 15 - (y - 16)
        if y == 31 then return P[DARK] end
        if ay >= 2 and ay <= 13 and x >= 1 and x <= W - 2 and z > 20 then
          return nil
        end
        return pix(sp, x, off + ay)
      end
      if y > 15 then return nil end
      -- the counter corner: column 3 (both rows) and column 2, row 3
      local corner = (x >= 24) or (x >= 16 and z >= 24)
      if corner then
        if y > 11 then return nil end
        if y == 11 then return pix(sp, x, off + 16 + (z - 16)) end
        if z == 31 then return pix(sp, x, off + 31 - math.min(y, 7)) end
        return pix(sp, x, off + 16 + (z - 16))
      end
      -- the back panel: 8 deep, 16 deep on the west two columns
      if z <= 23 or x < 16 then
        return pix(sp, x, panelRow + math.floor((15 - y) / 2))
      end
      return nil
    end,
    W = W, ytop = 31, xmin = 0, xmax = W - 1, zmin = 16, zmax = 31,
  }
end

-- worktop: a counter drawn from above over two rows (the register cell
-- of the Mart's east arm): 12 tall, the drawing laid over the top 1:1,
-- a dark lip all round.
function kinds.worktop(sp, t, off, P)
  local W = sp.W
  return {
    at = function(x, y, z)
      if x < 0 or x >= W or z < 0 or z > 15 or y < 0 or y > 11 then
        return nil
      end
      if y <= 1 and (z < 2 or z > 13) then return nil end
      if y == 11 and (z == 0 or z == 15) then return P[DARK] end
      return pix(sp, x, off + z)
    end,
    W = W, ytop = 11, xmin = 0, xmax = W - 1, zmin = 0, zmax = 15,
  }
end

-- ------------------------------------------------------------------- api --

-- The model for template `t` read into sprite `sp`, or nil when the kind
-- is unknown (the caller then leaves the tiles to the class pins).
function RoomKit.model(sp, t)
  local build = kinds[t.room]
  if not build then return nil end
  local off = t.topRows and (#t.topRows * 8) or 0
  local P = palette(sp, off)
  return build(sp, t, off, P)
end

return RoomKit
