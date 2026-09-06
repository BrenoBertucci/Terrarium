-- Voxel world mode: the POKEMON TOWER, modelled by hand.
--
-- The Gen 1 drawing of the tower (assets/docs/buildings/B30, composited
-- whole by Buildings.read through the template's `topRows`) is the only
-- building in Kanto whose sprite is a TOWER: a three-tier latticed roof
-- over twelve tile rows of windowed facade, straddling the ROUTE_10 /
-- LAVENDER_TOWN seam. The band pipeline (Buildings.model) folds that
-- drawing the way it folds a house -- roof band laid flat, facade extruded
-- -- and a house-shaped fold of a tower is a warehouse: a 96 x 100 brick
-- box with a striped lid, which is what stood in Lavender until now.
--
-- This module is the RoomKit answer for it: geometry the drawing IMPLIES
-- rather than geometry it paints. A stone plinth; a blind lower body in
-- weathered ashlar with a pointed portal, lantern niches and slit windows;
-- a cornice; a set-back storey of tall deep-set windows under string
-- courses; a second cornice; a lantern storey of pointed glass; and the
-- drawing's own three-tier lattice roof wrapped as a pagoda under a spire.
-- Every visible voxel still wears a texel of the tower's own drawing, so
-- the SGB palette (Lavender's violet) rides along untouched -- and the
-- SOMBRE part is done with light, not paint: `tint` hands Buildings.emit a
-- factor per texel class, so the drawing's WHITE held to less than half
-- its brightness comes out as grey stone, the same white a shade under it
-- as the joints, the roof's lattice deep violet, the cornices' fascia
-- pale, and the whole thing darkest at the foot, in the town's shadow,
-- climbing toward the light at the top -- which is most of what makes a
-- tall thing read tall. The glass is the facade's own panes, so GlassMask
-- finds it and the scene shader lights it after dark; inside the `haunt`
-- box this model reports that light is cold, sparse and breathing rather
-- than lamp-warm (the HAUNTED GLASS block in lib/Voxel3D.lua), and
-- lib/GhostFX.lua puts wisps in the air above it.
--
-- The TOWER options row picks which tower stands: NEW is this model,
-- CLASSIC the band fold the template's own fields describe (Buildings.build
-- asks `enabled` at build time; the row's own step drops every cached mesh
-- so the choice is re-read, exactly as TREES does).
--
-- Coordinates handed to `at` are the model's own: x east across the
-- matched footprint, y up from the ground, z south (toward the camera),
-- z = 0 the north edge of the matched grid and z = D - 1 the facade. The
-- model overhangs its footprint only where an eave would -- cornices and
-- the roof skirt reach a few voxels past the walls -- never at ground
-- level, where somebody walks.
--
-- Nothing here is extracted from the ROM: the numbers below are this
-- mod's own reading of what a tower of graves should look like.

local V = ...

local ModSetting = V.require("ModSetting")

local TowerKit = {}

local floor, abs, min, max, sin = math.floor, math.abs, math.min, math.max,
                                  math.sin

-- ------------------------------------------------------------- the row --

TowerKit.setting = ModSetting.new("tower", "TOWER",
                                  { "new", "classic" },
                                  { "NEW", "CLASSIC" })

function TowerKit.enabled()
  return TowerKit.setting:get() ~= "classic"
end

-- Remesh every map when the row flips: which model a `tower` template
-- gets is decided when Buildings.build runs, so a live toggle has to drop
-- the cached chunk meshes (and, through Structures, the built models).
local function remesh()
  pcall(function()
    V.require("ChunkMesher").invalidate()
  end)
end

-- OPTIONS row: cycle then rebuild. The manager page writes through
-- mod.options_changed (main.lua), which calls onOptionsChanged for this key.
function TowerKit.setting:row()
  local self_ = self
  return {
    id = ((V.mod and V.mod.id) or "TERRARIUM") .. ":" .. self.key,
    label = self.label,
    value = function() return self_.labels[self_:read()] end,
    step = function(game, dir)
      self_:cycle(game, dir)
      remesh()
      return true
    end,
  }
end

function TowerKit.onOptionsChanged(value)
  TowerKit.setting:sync(value)
  remesh()
end

-- ------------------------------------------------------------- defaults --
--
-- Every number a template may override through its `tower` table. Heights
-- are in voxels (world px) from the ground; spans in voxels of the
-- footprint; shades are factors on the face brightness. Tuned to the one
-- tower there is: 96 x 64 (12 x 8 tiles).
TowerKit.DEF = {
  plinthH    = 8,      -- the stone base, full footprint
  bodyTop    = 79,     -- blind lower body: plinthH .. bodyTop, walls inset 1
  courseY    = 44,     -- a two-tone string course across the lower body
  cornice1   = 4,      -- the cornice over the lower body, this tall
  upperIn    = 8,      -- the storeys above are set in this much (x) ...
  upperInZ   = 6,      -- ... and this much (z)
  upperH     = 56,     -- their height: three storeys of windows
  cornice2   = 4,
  belfryIn   = 18,     -- the lantern storey's set-in (x) ...
  belfryInZ  = 12,     -- ... and (z)
  belfryH    = 28,
  cornice3   = 4,
  eave       = 2,      -- a cornice juts this far past the wall under it
  -- the pagoda: bottom-to-top tiers, each a frustum h layers tall from
  -- half-extents (hx0, hz0) to (hx1, hz1), curved by k (1 = straight
  -- cone; more = steep at the ridge, flaring at the eave)
  roof = {
    { h = 10, k = 1.5, hx0 = 46, hz0 = 30, hx1 = 30,  hz1 = 20  },
    { h = 8,  k = 1.4, hx0 = 36, hz0 = 24, hx1 = 22,  hz1 = 15  },
    { h = 24, k = 1.8, hx0 = 26, hz0 = 18, hx1 = 1.5, hz1 = 1.5 },
  },
  spireH     = 16,
  winRecess  = 3,      -- how deep a storey window sinks
  portalW    = 24,     -- the pointed portal: width at the foot ...
  portalH    = 34,     -- ... its height to the apex ...
  portalD    = 8,      -- ... and how deep it hollows the wall
  -- the stone: ashlar courses this high and blocks this long, the foot of
  -- a wall damp-dark over `damp` rows (up to dampMax of its blocks), a
  -- share of blocks picked out black
  course     = 6,
  block      = 12,
  damp       = 14,
  dampMax    = 0.35,
  fleck      = 0.03,
  -- light, per texel class: what turns the drawing's white into grey stone
  stoneShade = 0.44,   -- the blocks
  jointShade = 0.30,   -- the joints, the damp foot, the streaks
  trimShade  = 0.62,   -- the light quoins, the plinth's top, the finial
  fasciaShade = 0.92,  -- the cornices' pale band, sills, archivolt, courses
  roofShade  = 0.78,   -- the lattice, which keeps the town's violet
  gloom      = 1.0,    -- and the whole tower, on top of the above
  tintLo     = 0.72,   -- the foot's share of light ...
  tintSpan   = 160,    -- ... climbing to full at this height
  hauntColor = { 0.62, 0.80, 1.0 },   -- what the haunted glass burns
}

local function params(t)
  local P = {}
  for k, v in pairs(TowerKit.DEF) do P[k] = v end
  local over = type(t.tower) == "table" and t.tower or nil
  if over then
    for k, v in pairs(over) do P[k] = v end
  end
  return P
end

-- ------------------------------------------------------------ materials --
--
-- Texel pickers into the composited drawing (96 wide, 20 tile rows). The
-- drawing's tile layout is fixed by the template (data/voxel_heights.lua
-- `pokemon_tower`), so the rows below are named once here:
--
--   sy   0..7    the roof ridge (tile 83, corners 5/6/8/9)
--   sy   8..23   two rows of lattice (18) between the roof's edges (21/25)
--   sy  24..31   the cornice line (22/23/24)
--   sy  56..63   the eave's pale fascia band (37/38/34/40/41)
--   sy  64..71   the first window course (15, 10 x 10, 31)
--   sy  72..79   the first brick course (75)
--   sy 152..159  the threshold the tower stands on (78, 26 x 10, 79)
--
-- The stone is the ridge tile's WHITE row: the roof palette group's
-- lightest colour, which every SGB recolour keeps white, so held down by
-- `tint` it is grey wherever the tower stands -- where the group's darker
-- shades would carry the town's violet into the walls. Four texels of that
-- one row are named so the light factor can tell them apart (the merge in
-- Buildings.emit keys on the texel, so a joint next to a block is a new
-- run either way).
local function materials(sp)
  local W = sp.W
  if W ~= 96 or sp.H ~= 160 then return nil end
  local function tex(sx, sy) return sy * W + sx end
  local function wrap(v, n) return v - floor(v / n) * n end
  local M = {}
  M.black = tex(16, 0)                 -- the outline
  M.white = tex(16, 1)                 -- pale trims (archivolt, sills, courses)
  M.stone = tex(17, 1)                 -- the blocks
  M.joint = tex(18, 1)                 -- joints, damp, streaks
  M.trim  = tex(19, 1)                 -- light quoins, plinth top, finial
  M.dark  = tex(16, 4)                 -- the roof's dark violet (hidden fill)
  -- the lattice, tiled over any span, and its darker twin (tile 56)
  M.roof  = function(x, z) return tex(16 + wrap(x, 64), 8 + wrap(z, 16)) end
  M.roofD = function(x, z) return tex(8 + wrap(x, 8), 8 + wrap(z, 16)) end
  -- the window tile: col 0 and 7 black frame, 1..6 glass; row 1 black,
  -- 2..5 glass, 6 the dark sill row, 7 black (row 0 is mortar, unused)
  M.win   = function(col, row) return tex(8 + col, 64 + row) end
  -- the pale fascia, rows 0 grey, 1..3 white, 4 grey, 5..7 white
  M.fascia = function(x, row) return tex(16 + wrap(x, 8), 56 + row) end
  return M
end

-- A window's texel, for an opening `w` wide and `h` tall, at (dx, dy) from
-- its bottom-left, wearing the drawing's own pane: black frame on the two
-- side columns and the top and bottom rows (a slit or a niche, narrower
-- than the pane, is all glass), the shine rows cycling up the glass so a
-- tall light reads as one pane.
local function paneTexel(M, dx, dy, w, h)
  local col
  if w >= 8 then
    if dx == 0 then col = 0 elseif dx == w - 1 then col = 7
    else col = 1 + (dx - 1) % 6 end
  else
    col = 2 + dx % 4
  end
  local row
  if w >= 8 and dy == 0 then row = 7
  elseif w >= 8 and dy == h - 1 then row = 1
  elseif w >= 8 and dy == 1 then row = 6
  else row = 5 - (dy % 4) end
  return M.win(col, row)
end

-- Deterministic in the voxel's own position, so every build of the tower
-- is the same tower.
local function hash3(x, y, z)
  local n = sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453
  return n - floor(n)
end

-- ---------------------------------------------------------------- model --

function TowerKit.model(sp, t)
  local M = materials(sp)
  if not M then return nil end
  local P = params(t)
  local W = sp.W                       -- 96, east across the footprint
  local D = #t.tiles * 8               -- 64, the matched footprint's depth
  local cx, cz = W / 2, D / 2

  -- the storeys, bottom to top
  local y1p = P.plinthH - 1
  local y0b, y1b = P.plinthH, P.bodyTop
  local y0c1 = y1b + 1
  local y1c1 = y0c1 + P.cornice1 - 1
  local y0u = y1c1 + 1
  local y1u = y0u + P.upperH - 1
  local y0c2 = y1u + 1
  local y1c2 = y0c2 + P.cornice2 - 1
  local y0l = y1c2 + 1
  local y1l = y0l + P.belfryH - 1
  local y0c3 = y1l + 1
  local y1c3 = y0c3 + P.cornice3 - 1
  local y0r = y1c3 + 1

  local eave = P.eave

  -- ------- the stone
  --
  -- Ashlar: courses `course` voxels high, blocks `block` long, every second
  -- course shifted half a block so the joints stagger. Blocks are the
  -- drawing's white held down to stone grey by `tint`, joints the same
  -- white a shade under. Weathering on top: the foot of a wall damp-darkens
  -- toward the ground, thin streaks run down from under the string courses
  -- and cornices, and a few blocks are picked out black. `useZ` says which
  -- face the voxel shows -- a flank runs its joints along z, a front along
  -- x -- because the same voxel wears one texel on every face it has.
  local COURSE, BLOCK = P.course, P.block
  local function stone(x, y, z, useZ, base, drips)
    local along = useZ and z or x
    if y % COURSE == 0 then return M.joint end
    local shift = (floor(y / COURSE) % 2) * floor(BLOCK / 2)
    if (along + shift) % BLOCK == 0 then return M.joint end
    local r = hash3(floor(along / 3), floor(y / 3), useZ and 7 or 3)
    if base and y - base < P.damp then
      local k = 1 - (y - base) / P.damp
      if r < P.dampMax * k * k then return M.joint end
    end
    if drips then
      for j = 1, #drips do
        local d = drips[j] - y
        if d > 0 and d <= 10 then
          local h = hash3(along, 11, useZ and 5 or 1)
          if h < 0.10 and d <= 3 + h * 70 then return M.joint end
        end
      end
    end
    if r < P.fleck then return M.black end
    return M.stone
  end

  -- ------- walls: a solid box, openings cut into its faces, details
  -- standing proud of them. `open` entries: face S/N/E/W, a0..a1 along
  -- the face (x for S/N, z for E/W), y0..y1, depth, w/h for the pane,
  -- `point` rows of taper at the top, `back` a fixed texel for the rear
  -- wall (else the pane).
  local function newWall(x0, x1, z0, z1, y0, y1, base, drips)
    return { x0 = x0, x1 = x1, z0 = z0, z1 = z1, y0 = y0, y1 = y1,
             open = {}, base = base, drips = drips }
  end

  local function addOpen(Wl, face, a0, a1, y0, y1, depth, point, back)
    Wl.open[#Wl.open + 1] = { face = face, a0 = a0, a1 = a1, y0 = y0,
                              y1 = y1, depth = depth, point = point,
                              back = back, w = a1 - a0 + 1, h = y1 - y0 + 1 }
  end

  -- nil: not this opening. false: hollow. A texel: the rear wall.
  local function openAt(Wl, o, x, y, z)
    local along, face = x, o.face
    if face == "E" or face == "W" then along = z end
    local a0, a1 = o.a0, o.a1
    if o.point then
      local top = o.y1 - o.point + 1
      if y >= top then
        local shrink = y - top + 1
        a0, a1 = a0 + shrink, a1 - shrink
      end
    end
    if along < a0 or along > a1 then return nil end
    local depth, back = o.depth, nil
    local inward
    if face == "S" then
      back = Wl.z1 - depth
      if z > back then return false end
      inward = (z == back)
    elseif face == "N" then
      back = Wl.z0 + depth
      if z < back then return false end
      inward = (z == back)
    elseif face == "E" then
      back = Wl.x1 - depth
      if x > back then return false end
      inward = (x == back)
    else
      back = Wl.x0 + depth
      if x < back then return false end
      inward = (x == back)
    end
    if not inward then return nil end
    if o.back then return o.back end
    return paneTexel(M, along - o.a0, y - o.y0, o.w, o.h)
  end

  local function wallAt(Wl, x, y, z)
    if Wl.proud then
      local p = Wl.proud(x, y, z)
      if p then return p end
    end
    if x < Wl.x0 or x > Wl.x1 or z < Wl.z0 or z > Wl.z1 then return nil end
    local open = Wl.open
    for i = 1, #open do
      local o = open[i]
      if y >= o.y0 and y <= o.y1 then
        local r = openAt(Wl, o, x, y, z)
        if r ~= nil then return r or nil end
      end
    end
    local useZ = (x == Wl.x0 or x == Wl.x1)
    return stone(x, y, z, useZ, Wl.base, Wl.drips)
  end

  -- ------- the plinth and the lower body
  local LB = newWall(1, W - 2, 1, D - 2, y0b, y1b, y0b, { P.courseY, y1b + 1 })

  -- The portal: a pointed arch cut through the plinth and the lower body
  -- on the facade, its rear wall the black of the drawing's outline -- a
  -- doorway into the dark. Two rings stand round it flush with the plinth,
  -- black inside pale, the archivolt every gothic door wears.
  local pw, ph, pd = P.portalW, P.portalH, P.portalD
  local hw0 = pw / 2
  local portalTop = ph - 1                 -- apex row, from the ground
  local taper = hw0                        -- rows over which it closes
  local function inArch(x, y, grow)
    if y < 0 or y > portalTop + grow then return false end
    local hw = hw0 + grow
    local t0 = portalTop - taper + 1
    if y >= t0 then hw = hw - (y - t0 + 1) end
    if hw <= 0 then return false end
    return abs(x + 0.5 - cx) <= hw
  end
  local portalBack = D - 1 - pd
  local function portalAt(x, y, z)
    if z == D - 1 then
      -- the archivolt, on the plinth's own plane
      if inArch(x, y, 1) and not inArch(x, y, 0) then return M.black end
      if inArch(x, y, 2) and not inArch(x, y, 1) then return M.white end
    end
    if inArch(x, y, 0) then
      if z > portalBack then return false end
      if z == portalBack then return M.black end
    end
    return nil
  end

  -- lantern niches either side of the portal, and slit windows: narrow
  -- glass set deep in the blind wall, the only light the lower body shows
  local nx = floor(cx - hw0) - 12
  addOpen(LB, "S", nx, nx + 5, 18, 27, 2)
  addOpen(LB, "S", W - 1 - nx - 5, W - 1 - nx, 18, 27, 2)
  local sy0, sy1 = 50, 65
  addOpen(LB, "S", 12, 13, sy0, sy1, 3)
  addOpen(LB, "S", W - 14, W - 13, sy0, sy1, 3)
  addOpen(LB, "N", 30, 31, sy0, sy1, 3)
  addOpen(LB, "N", W - 32, W - 31, sy0, sy1, 3)
  for _, zc in ipairs({ 14, 30, 46 }) do
    addOpen(LB, "E", zc, zc + 1, sy0, sy1, 3)
    addOpen(LB, "W", zc, zc + 1, sy0, sy1, 3)
  end

  -- flush corner pilasters (the wall between them is inset one voxel) and
  -- the string course, both on the plinth's plane
  local PIL = 10
  LB.proud = function(x, y, z)
    if x < 0 or x > W - 1 or z < 0 or z > D - 1 then return nil end
    local ring = (x == 0 or x == W - 1 or z == 0 or z == D - 1)
    if not ring then return nil end
    if y == P.courseY then return M.black end
    if y == P.courseY + 1 then return M.white end
    local corner = (x < PIL or x > W - 1 - PIL) and (z < PIL or z > D - 1 - PIL)
    if corner then
      return stone(x, y, z, x == 0 or x == W - 1, y0b, LB.drips)
    end
    return nil
  end

  -- the plinth: a stone step, light on top, dark below, the outline's
  -- black shadow line near the foot
  local function plinthAt(x, y, z)
    if x < 0 or x > W - 1 or z < 0 or z > D - 1 then return nil end
    local dy = y1p - y
    if dy == 0 then return M.trim end
    if dy <= 2 then return M.stone end
    if dy == 6 then return M.black end
    return M.joint
  end

  -- ------- the upper storeys: set back, three courses of tall pointed
  -- windows sunk deep, string courses between them
  local ux0, ux1 = P.upperIn, W - 1 - P.upperIn
  local uz0, uz1 = P.upperInZ, D - 1 - P.upperInZ
  local WIN_W, WIN_H = 8, 11
  local storeys = { y0u + 3, y0u + 19, y0u + 35 }
  local courses = { y0u + 16, y0u + 32 }
  local UB = newWall(ux0, ux1, uz0, uz1, y0u, y1u, nil,
                     { courses[1], courses[2], y1u + 1 })
  local uw = ux1 - ux0 + 1
  local cols = {}
  do
    -- four windows across, symmetric: margins share what the panes and
    -- their equal gaps leave
    local n, gap = 4, 8
    local span = n * WIN_W + (n - 1) * gap
    local m0 = ux0 + floor((uw - span) / 2)
    for i = 0, n - 1 do cols[#cols + 1] = m0 + i * (WIN_W + gap) end
  end
  local ud = uz1 - uz0 + 1
  local sides = {}
  do
    local n, gap = 2, 16
    local span = n * WIN_W + (n - 1) * gap
    local m0 = uz0 + floor((ud - span) / 2)
    for i = 0, n - 1 do sides[#sides + 1] = m0 + i * (WIN_W + gap) end
  end
  for _, wy in ipairs(storeys) do
    for _, wx in ipairs(cols) do
      addOpen(UB, "S", wx, wx + WIN_W - 1, wy, wy + WIN_H - 1, P.winRecess, 3)
      addOpen(UB, "N", wx, wx + WIN_W - 1, wy, wy + WIN_H - 1, P.winRecess, 3)
    end
    for _, wz in ipairs(sides) do
      addOpen(UB, "E", wz, wz + WIN_W - 1, wy, wy + WIN_H - 1, P.winRecess, 3)
      addOpen(UB, "W", wz, wz + WIN_W - 1, wy, wy + WIN_H - 1, P.winRecess, 3)
    end
  end
  -- proud: quoins at the corners in alternating courses, a pale sill
  -- under every window, and the two string courses between storeys
  local QUOIN = 6
  UB.proud = function(x, y, z)
    local px0, px1, pz0, pz1 = ux0 - 1, ux1 + 1, uz0 - 1, uz1 + 1
    if x < px0 or x > px1 or z < pz0 or z > pz1 then return nil end
    local ring = (x == px0 or x == px1 or z == pz0 or z == pz1)
    if not ring then return nil end
    for _, cy in ipairs(courses) do
      if y == cy then return M.black end
      if y == cy + 1 then return M.white end
    end
    local corner = (x <= ux0 + QUOIN - 1 or x >= ux1 - QUOIN + 1)
                   and (z <= uz0 + QUOIN - 1 or z >= uz1 - QUOIN + 1)
    if corner then
      return (floor((y - y0u) / 4) % 2 == 0) and M.trim or M.stone
    end
    -- sills: the row under a pane, only on the pane's own face
    for _, wy in ipairs(storeys) do
      if y == wy - 1 then
        if z == pz1 or z == pz0 then
          for _, wx in ipairs(cols) do
            if x >= wx and x <= wx + WIN_W - 1 then return M.white end
          end
        end
        if x == px1 or x == px0 then
          for _, wz in ipairs(sides) do
            if z >= wz and z <= wz + WIN_W - 1 then return M.white end
          end
        end
      end
    end
    return nil
  end

  -- ------- the lantern storey: tall pointed glass on every face
  local bx0, bx1 = P.belfryIn, W - 1 - P.belfryIn
  local bz0, bz1 = P.belfryInZ, D - 1 - P.belfryInZ
  local BF = newWall(bx0, bx1, bz0, bz1, y0l, y1l, nil, { y1l + 1 })
  local ly0, ly1 = y0l + 4, y1l - 4
  local bw = bx1 - bx0 + 1
  local bcols = {}
  do
    local n, gap = 3, 12
    local span = n * WIN_W + (n - 1) * gap
    local m0 = bx0 + floor((bw - span) / 2)
    for i = 0, n - 1 do bcols[#bcols + 1] = m0 + i * (WIN_W + gap) end
  end
  local bd = bz1 - bz0 + 1
  local bsides = {}
  do
    local n, gap = 2, 12
    local span = n * WIN_W + (n - 1) * gap
    local m0 = bz0 + floor((bd - span) / 2)
    for i = 0, n - 1 do bsides[#bsides + 1] = m0 + i * (WIN_W + gap) end
  end
  for _, wx in ipairs(bcols) do
    addOpen(BF, "S", wx, wx + WIN_W - 1, ly0, ly1, 2, 3)
    addOpen(BF, "N", wx, wx + WIN_W - 1, ly0, ly1, 2, 3)
  end
  for _, wz in ipairs(bsides) do
    addOpen(BF, "E", wz, wz + WIN_W - 1, ly0, ly1, 2, 3)
    addOpen(BF, "W", wz, wz + WIN_W - 1, ly0, ly1, 2, 3)
  end
  BF.proud = function(x, y, z)
    local px0, px1, pz0, pz1 = bx0 - 1, bx1 + 1, bz0 - 1, bz1 + 1
    if x < px0 or x > px1 or z < pz0 or z > pz1 then return nil end
    local ring = (x == px0 or x == px1 or z == pz0 or z == pz1)
    if not ring then return nil end
    local corner = (x <= bx0 + 3 or x >= bx1 - 3)
                   and (z <= bz0 + 3 or z >= bz1 - 3)
    if corner then
      return (floor((y - y0l) / 4) % 2 == 0) and M.trim or M.stone
    end
    return nil
  end

  -- ------- cornices: slabs overhanging the wall beneath, pale fascia over
  -- a black underside
  local function newCornice(x0, x1, z0, z1, y0, y1)
    return { x0 = x0, x1 = x1, z0 = z0, z1 = z1, y0 = y0, y1 = y1 }
  end
  local C1 = newCornice(-eave, W - 1 + eave, -eave, D - 1 + eave, y0c1, y1c1)
  local C2 = newCornice(ux0 - 1 - eave, ux1 + 1 + eave,
                        uz0 - 1 - eave, uz1 + 1 + eave, y0c2, y1c2)
  local C3 = newCornice(bx0 - 2 - eave, bx1 + 2 + eave,
                        bz0 - 2 - eave, bz1 + 2 + eave, y0c3, y1c3)
  local function corniceAt(C, x, y, z)
    if x < C.x0 or x > C.x1 or z < C.z0 or z > C.z1 then return nil end
    local dy = y - C.y0
    if dy == 0 then return M.black end
    local ring = (x == C.x0 or x == C.x1 or z == C.z0 or z == C.z1)
    if ring then
      if dy == 1 then return M.fascia(x + z, 0) end
      return M.fascia(x + z, 1 + (dy - 2) % 3)
    end
    return M.dark
  end

  -- ------- the pagoda: stacked frusta, the lattice on every step, the
  -- flared bottom row of each tier in the dark lattice so the eaves read
  -- as shadow
  local tiers = {}
  local yy = y0r
  for i, spec in ipairs(P.roof) do
    local tier = { y0 = yy, y1 = yy + spec.h - 1, hx = {}, hz = {} }
    for L = 0, spec.h - 1 do
      local f = L / spec.h
      local s = (1 - f) ^ spec.k
      tier.hx[L] = spec.hx1 + (spec.hx0 - spec.hx1) * s
      tier.hz[L] = spec.hz1 + (spec.hz0 - spec.hz1) * s
    end
    tiers[i] = tier
    yy = yy + spec.h
  end
  local y0s = yy
  local function roofAt(x, y, z)
    for i = 1, #tiers do
      local tier = tiers[i]
      if y >= tier.y0 and y <= tier.y1 then
        local L = y - tier.y0
        if abs(x + 0.5 - cx) <= tier.hx[L]
            and abs(z + 0.5 - cz) <= tier.hz[L] then
          if L == 0 then return M.roofD(x, z) end
          return M.roof(x, z)
        end
        return nil
      end
    end
    return nil
  end

  -- ------- the spire: a black mast on a collar, a ball under the tip
  local y1s = y0s + P.spireH - 1
  local function spireAt(x, y, z)
    if y < y0s or y > y1s then return nil end
    local dx, dz = abs(x + 0.5 - cx), abs(z + 0.5 - cz)
    if y <= y0s + 1 or (y >= y1s - 3 and y <= y1s - 1) then
      if dx <= 2 and dz <= 2 then
        if dx <= 1 and dz <= 1 then return M.black end
        return M.trim
      end
      return nil
    end
    if dx <= 1 and dz <= 1 then return M.black end
    return nil
  end
  local ytop = y1s

  -- ------- the lookup, top down so each storey answers its own band
  local px0, px1 = floor(cx - hw0) - 2, floor(cx + hw0) + 1
  local function at(x, y, z)
    if y < 0 or y > ytop then return nil end
    if y >= y0s then return spireAt(x, y, z) end
    if y >= y0r then return roofAt(x, y, z) end
    if y >= y0c3 then return corniceAt(C3, x, y, z) end
    if y >= y0l then return wallAt(BF, x, y, z) end
    if y >= y0c2 then return corniceAt(C2, x, y, z) end
    if y >= y0u then return wallAt(UB, x, y, z) end
    if y >= y0c1 then return corniceAt(C1, x, y, z) end
    -- the portal cuts the plinth and the lower body alike
    if y <= portalTop + 2 and z >= portalBack and x >= px0 and x <= px1 then
      local r = portalAt(x, y, z)
      if r ~= nil then return r or nil end
    end
    if y >= y0b then return wallAt(LB, x, y, z) end
    return plinthAt(x, y, z)
  end

  -- ------- what the rest of the mod wants to know about this model
  --
  -- The light, per texel class (see the header) times the height gradient:
  -- the foot stands in the town's shadow and the top catches the sky.
  local function matShade(i)
    if i == M.black then return 1.0 end
    if i == M.white then return P.fasciaShade end
    if i == M.stone then return P.stoneShade end
    if i == M.joint then return P.jointShade end
    if i == M.trim then return P.trimShade end
    if i == M.dark then return P.jointShade end
    local sy = floor(i / W)
    if sy >= 8 and sy <= 23 then return P.roofShade end
    if sy >= 56 and sy <= 63 then return P.fasciaShade end
    return 1.0
  end
  local gloom, lo, span = P.gloom, P.tintLo, P.tintSpan
  local function tint(y, i)
    local f = y / span
    if f > 1 then f = 1 elseif f < 0 then f = 0 end
    return gloom * (lo + (1 - lo) * f) * (i and matShade(i) or 1)
  end

  -- The haunt: the box the cold glass burns in, and where the wisps rise
  -- -- out of the lantern storey's glass, the portal's mouth, the spire.
  local wisps = {}
  local lyMid = floor((ly0 + ly1) / 2)
  for _, wx in ipairs(bcols) do
    wisps[#wisps + 1] = { wx + WIN_W / 2, lyMid, bz1 + 1.5, "lantern" }
    wisps[#wisps + 1] = { wx + WIN_W / 2, lyMid, bz0 - 0.5, "lantern" }
  end
  for _, wz in ipairs(bsides) do
    wisps[#wisps + 1] = { bx1 + 1.5, lyMid, wz + WIN_W / 2, "lantern" }
    wisps[#wisps + 1] = { bx0 - 0.5, lyMid, wz + WIN_W / 2, "lantern" }
  end
  wisps[#wisps + 1] = { cx, 10, D + 0.5, "portal" }
  wisps[#wisps + 1] = { cx, ytop + 1, cz, "spire" }
  local xmin, xmax = min(-eave, C1.x0), max(W - 1 + eave, C1.x1)
  local zmin, zmax = min(-eave, C1.z0), max(D - 1 + eave, C1.z1)
  for _, tier in ipairs(tiers) do
    xmin = min(xmin, floor(cx - tier.hx[0]))
    xmax = max(xmax, floor(cx + tier.hx[0]))
    zmin = min(zmin, floor(cz - tier.hz[0]))
    zmax = max(zmax, floor(cz + tier.hz[0]))
  end
  local haunt = {
    color = P.hauntColor,
    box = { xmin, zmin, xmax, zmax },
    top = ytop,
    wisps = wisps,
  }

  return { at = at, W = W, ytop = ytop, tint = tint, haunt = haunt,
           xmin = xmin, xmax = xmax, zmin = zmin, zmax = zmax }
end

-- ------------------------------------------------------------- precinct --
--
-- The terrace the tower stands on. Lavender draws the edge of the tower's
-- yard as hop-down LEDGE tiles -- $27 along the north-south sides, $37 with
-- its $36/$13 ends along the south, the entrance's dark arch ($48/$49 over
-- $58/$59) in the middle -- and the profile's ledge class stands those as
-- a six-pixel box wearing the lip drawing on its top: a mat of orange
-- wicker round the foot of a stone tower. These pieces stand the same
-- tiles as the tower's own wall: a low ashlar wall six voxels thick under
-- a pale coping, piers at the corners, at the ends and either side of the
-- gate, all of it the ledge's own WHITE texels held down to grey the way
-- the tower's stone is. One template per cell shape (data/voxel_heights
-- .lua, OVERWORLD, field `precinct`), matched by tiles and confined to
-- Lavender by `maps` and `where`: the same ledge tiles run every route in
-- Kanto, and there a stone wall would be wrong.
--
--   ew     a run east-west (the hop-down ledge)     ns     north-south
--   nw     a corner, from the north turning east    ne     from the west, south
--   gate   two piers with the way through between   end_s  a north-south run's end
--   end_e  an east-west run's east end
--   pave   the yard itself: one voxel of flagstones over a cell of the
--          speckled ground ($11), the same white held down to grey, joints
--          on the eight-voxel grid with every other one dropped so the
--          stones come out as slabs of two sizes. The ground tile is half
--          of Kanto's routes; `where` keeps the paving to the terrace.
TowerKit.WALL = {
  thick  = 6,      -- the wall, centred in its cell
  h      = 8,      -- courses of masonry under the coping
  pierW  = 8,      -- a pier's footprint
  pierH  = 12,     -- its masonry, under a cap and a finial
  course = 4,      -- ashlar: courses this high ...
  block  = 6,      -- ... blocks this long, staggered
  fleck  = 0.04,   -- share of blocks picked out black
  stone  = 0.38,   -- the light: the white held down to the tower's foot
  joint  = 0.27,
  trim   = 0.56,
  -- the paving: four tones of flagstone, its joints, and a dark fleck
  paveTones = { 0.40, 0.36, 0.44, 0.33 },
  paveJoint = 0.26,
  paveFleck = 0.50,
}

function TowerKit.precinct(sp, t)
  local kind = t.precinct
  local Wd = TowerKit.WALL
  local C = sp.W                      -- the cell: 16
  -- three of the drawing's white texels -- one colour, distinct indices
  -- so `tint` can tell the classes apart -- and its black
  local whites, black, dark = {}, nil, nil
  for i = 0, sp.W * sp.H - 1 do
    local c = sp.col[i]
    if c == 0 and #whites < 6 then whites[#whites + 1] = i end
    if c == 3 and not black then black = i end
    if c == 2 and not dark then dark = i end
  end
  if #whites == 0 then return nil end

  -- ------- the yard's flagstones: a slab one voxel thick over the cell
  if kind == "pave" then
    local tones, shade = {}, {}
    for k = 1, 4 do
      tones[k] = whites[((k - 1) % #whites) + 1]
    end
    local jointP = whites[(4 % #whites) + 1]
    local fleck = dark or black or jointP
    for k = 1, 4 do shade[tones[k]] = Wd.paveTones[k] end
    shade[jointP] = Wd.paveJoint
    shade[fleck] = shade[fleck] or Wd.paveFleck
    local function flag(x, z)
      -- joints on the 8-voxel grid, every other one dropped by a hash so
      -- the stones merge into 8x16 and 16x8 slabs; one tone per stone
      local jx = (x % 8 == 0) and hash3(floor(x / 8), floor(z / 16), 1) < 0.65
      local jz = (z % 8 == 0) and hash3(floor(x / 16), floor(z / 8), 2) < 0.65
      if jx or jz then return jointP end
      local s = hash3(floor(x / 8), floor(z / 8), 3)
      if s < 0.03 then return fleck end
      return tones[1 + (floor(s * 40) % 4)]
    end
    local function at(x, y, z)
      if y ~= 0 or x < 0 or x > C - 1 or z < 0 or z > C - 1 then return nil end
      return flag(x, z)
    end
    local function tint(y, i)
      return (i and shade[i]) or 1
    end
    return { at = at, W = C, ytop = 0, tint = tint,
             xmin = 0, xmax = C - 1, zmin = 0, zmax = C - 1 }
  end
  local stoneT = whites[1]
  local jointT = whites[2] or whites[1]
  local trimT = whites[3] or whites[1]
  black = black or jointT

  local thick, h, ph = Wd.thick, Wd.h, Wd.pierH
  local a0 = floor((C - thick) / 2)
  local a1 = a0 + thick - 1
  local p0 = floor((C - Wd.pierW) / 2)
  local p1 = p0 + Wd.pierW - 1

  -- ashlar in miniature: bed joints every course, head joints staggered
  -- by half a block; `across` adds a pier's second set of head joints
  local function masonry(along, y, across)
    if y % Wd.course == 0 then return jointT end
    local shift = (floor(y / Wd.course) % 2) * floor(Wd.block / 2)
    if (along + shift) % Wd.block == 0 then return jointT end
    if across and (across + shift) % Wd.block == 0 then return jointT end
    if hash3(along, y, across or 0) < Wd.fleck then return black end
    return stoneT
  end

  -- boxes answer in order, so a pier is listed before the wall it caps
  local boxes = {}
  local function box(x0, x1, z0, z1, y0, y1, tex)
    boxes[#boxes + 1] = { x0, x1, z0, z1, y0, y1, tex }
  end
  -- a wall: masonry, a shadow line, a coping proud one voxel on each flank
  local function wall(x0, x1, z0, z1, alongZ)
    box(x0, x1, z0, z1, 0, h - 1,
        function(x, y, z) return masonry(alongZ and z or x, y) end)
    box(x0, x1, z0, z1, h, h, black)
    if alongZ then
      box(x0 - 1, x1 + 1, z0, z1, h + 1, h + 2, trimT)
    else
      box(x0, x1, z0 - 1, z1 + 1, h + 1, h + 2, trimT)
    end
  end
  -- a pier: masonry, a shadow line, a cap proud all round, a finial
  local function pier(x0, x1, z0, z1)
    box(x0, x1, z0, z1, 0, ph - 1,
        function(x, y, z) return masonry(x, y, z) end)
    box(x0, x1, z0, z1, ph, ph, black)
    box(x0 - 1, x1 + 1, z0 - 1, z1 + 1, ph + 1, ph + 2, trimT)
    local mx, mz = floor((x0 + x1) / 2), floor((z0 + z1) / 2)
    box(mx, mx + 1, mz, mz + 1, ph + 3, ph + 4, trimT)
  end

  if kind == "ew" then
    wall(0, C - 1, a0, a1, false)
  elseif kind == "ns" then
    wall(a0, a1, 0, C - 1, true)
  elseif kind == "nw" then
    pier(p0, p1, p0, p1)
    wall(a0, a1, 0, a1, true)               -- from the north
    wall(a0, C - 1, a0, a1, false)          -- turning east
  elseif kind == "ne" then
    pier(p0, p1, p0, p1)
    wall(0, a1, a0, a1, false)              -- from the west
    wall(a0, a1, a0, C - 1, true)           -- turning south
  elseif kind == "gate" then
    pier(0, 3, 3, C - 4)
    pier(C - 4, C - 1, 3, C - 4)
  elseif kind == "end_s" then
    pier(p0, p1, C - 1 - Wd.pierW, C - 2)
    wall(a0, a1, 0, a1, true)
  elseif kind == "end_e" then
    pier(C - 1 - Wd.pierW, C - 2, p0, p1)
    wall(0, a1, a0, a1, false)
  else
    return nil
  end

  local ytop, xmin, xmax, zmin, zmax = 0, 0, C - 1, 0, C - 1
  for i = 1, #boxes do
    local b = boxes[i]
    xmin, xmax = min(xmin, b[1]), max(xmax, b[2])
    zmin, zmax = min(zmin, b[3]), max(zmax, b[4])
    ytop = max(ytop, b[6])
  end

  local function at(x, y, z)
    for i = 1, #boxes do
      local b = boxes[i]
      if x >= b[1] and x <= b[2] and z >= b[3] and z <= b[4]
          and y >= b[5] and y <= b[6] then
        local tex = b[7]
        if type(tex) == "function" then return tex(x, y, z) end
        return tex
      end
    end
    return nil
  end

  -- the light, per texel class; no height gradient on a wall this low
  local shade = {}
  shade[black] = 1.0
  shade[trimT] = Wd.trim
  shade[jointT] = Wd.joint
  shade[stoneT] = Wd.stone
  local function tint(y, i)
    return (i and shade[i]) or 1
  end

  return { at = at, W = C, ytop = ytop, tint = tint,
           xmin = xmin, xmax = xmax, zmin = zmin, zmax = zmax }
end

return TowerKit
