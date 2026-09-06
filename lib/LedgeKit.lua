-- Voxel world mode: the hop-down LEDGES as banks (the LEDGES row).
--
-- A Gen 1 ledge is a one-way step: you stand on the high side, press toward
-- it, and hop down to the landing. The overworld draws it as a bump of
-- hatched earth seen face-on ($37 with its $36/$34 ends along an east-west
-- run, $27 down a north-south one hopped westward, $0D/$1D hopped
-- eastward, $24/$35/$1E as the shaded faces and corners of those). The
-- profile's `ledge` class stood every one of those tiles as a six-pixel
-- box wearing the bump drawing on its TOP -- a run of orange wicker mats
-- across every route in Kanto, which is what this module replaces.
--
-- ------- WHAT A LEDGE IS IN A FLAT WORLD
--
-- The diorama's ground is one plane: the high side and the landing both
-- stand at zero. So a ledge cannot be a terrace edge -- there is no
-- terrace -- and the honest shape for it is a BANK: a ridge of earth that
-- rises steeply on the high side, crests, and falls away gently toward the
-- landing, with the ground's own grass rolling over its top and its earth
-- showing where the fall is steep. From the camera, which looks north and
-- down, an east-west bank's steep side is hidden behind its crest and the
-- gentle side faces the lens: a grassy slope with a dark rim at its foot,
-- exactly what the drawing meant. A north-south bank shows its steep side
-- obliquely, as the small earthen face it is.
--
-- ------- STROKES
--
-- The census of every overworld cell holding a ledge tile comes to
-- seventeen compositions (data/voxel_heights.lua lists them), and every one
-- is one or two STROKES: a ridge along an axis, with a height profile
-- across it and a rounded taper at an end. A stroke names its direction
-- (`ew` runs east-west, `ns` north-south), which side is high (`n`, `e`,
-- `w`), the range it stands across (`a0`..`a1`: z for `ew`, x for `ns`),
-- the range it runs along (`b0`..`b1`), and how many voxels of its ends
-- are rounded (`lo`, `hi`, from the low end of the along-axis). The cell's
-- height field is the maximum over its strokes, so an L of two ridges
-- meets in a rounded corner for free.
--
-- ------- TEXELS
--
-- Every voxel wears a texel of the map's own atlas. The bank's top and its
-- gentle slope wear the HIGH side's ground tile -- Buildings composites
-- that tile above the drawing as a palette row (`topRows`, the RoomKit
-- trick) and picks it per placement, so a bank between grass and a path
-- wears the grass it came from, tiled on the world grid so it continues
-- the meadow around it. The steep risers and the foot wear the drawing's
-- own dark and light earth, and its outline black. Nothing is repainted.
--
-- The grass and path tiles that share a cell with a ledge (the standing
-- tile above an eight-deep run) are never claimed: a claim mask leaves
-- them to the mesher with their own art, so a path does not turn to grass
-- where a ledge crosses it.

local V = ...

local ModSetting = V.require("ModSetting")

local LedgeKit = {}

local floor, sqrt, max, min, sin = math.floor, math.sqrt, math.max, math.min,
                                   math.sin

-- ------------------------------------------------------------- the row --

LedgeKit.setting = ModSetting.new("ledges", "LEDGES",
                                  { "bank", "classic" },
                                  { "BANK", "CLASSIC" })

function LedgeKit.enabled()
  return LedgeKit.setting:get() ~= "classic"
end

local function remesh()
  pcall(function()
    V.require("ChunkMesher").invalidate()
  end)
end

function LedgeKit.setting:row()
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

function LedgeKit.onOptionsChanged(value)
  LedgeKit.setting:sync(value)
  remesh()
end

-- ------------------------------------------------------------- numbers --

LedgeKit.H16 = 8         -- a bank sixteen voxels across stands this tall
LedgeKit.H8 = 6          -- one eight across
LedgeKit.RISE = 2        -- the steep side: this many voxels of run
LedgeKit.CURVE = 1.4     -- the gentle side: (1 - s)^CURVE, steep at the crest
LedgeKit.SOIL = 0.62     -- light on the earth texels: the drawing's dark shade
                         -- is an orange-brown in most palettes, and at full
                         -- light a riser of it read as the wicker it replaced
LedgeKit.FOOT = 0.50     -- and on the dark rim at the foot

-- Ground the bank's top would rather not wear: the mound body's gravel
-- ($11), which is right on the flat plateau it draws and reads as the
-- speckled box art this module replaced when draped over a bank. When the
-- high side is gravel and the landing side is grass or a path, the bank
-- wears the landing's ground instead -- a grassy bank at the plateau's edge.
LedgeKit.PLAIN = { [17] = true }

-- The tiles that ARE a ledge's drawing, claimed by the bank. Anything else
-- in the cell (grass, a path) keeps its own art and class. $24 is the
-- mound's shaded east slope and $02 its north-east corner (the profile
-- pins both `wall`, one 16px course): a mound's edge like the ledges,
-- only not hopped, so it stands as the same bank.
LedgeKit.ART = { [2] = true, [13] = true, [19] = true, [29] = true,
                 [30] = true, [36] = true, [39] = true, [52] = true,
                 [53] = true, [54] = true, [55] = true }

local function hash2(x, z)
  local n = sin(x * 12.9898 + z * 78.233) * 43758.5453
  return n - floor(n)
end

-- ------------------------------------------------------------- profile --

-- Height across a stroke `d` voxels wide, `t` voxels in from its HIGH edge:
-- a short steep rise, the crest, the long gentle fall to a one-voxel foot.
local function profile(t, d, H)
  local rise = LedgeKit.RISE
  if t < rise then
    return H * (0.6 + 0.3 * t / rise)
  end
  local run = d - 1 - rise
  if run <= 0 then return H end
  local s = (t - rise) / run
  if s > 1 then s = 1 end
  return 1 + (H - 1) * (1 - s) ^ LedgeKit.CURVE
end

-- A north-south bank is SYMMETRIC: crest down the middle, the same gentle
-- fall to either foot. The steep side of the east-west profile hides
-- behind its own crest from a camera looking north; on a north-south
-- bank it would face the lens as a small cliff, and in a world whose two
-- sides both stand at zero the asymmetry tells nothing worth a cliff.
local function profileSym(t, d, H)
  local half = (d - 1) / 2
  local s = math.abs(t - half) / half
  if s > 1 then s = 1 end
  return 1 + (H - 1) * (1 - s) ^ LedgeKit.CURVE
end

-- The rounded end: a quarter sine over `n` voxels, `u` in from the end --
-- a voxel or two at the very tip, most of the height only two thirds of
-- the way in, so a run melts into the ground rather than stopping at a
-- block. (A quarter circle here stood a third of the height at the tip.)
local function taper(u, n)
  local v = (u + 0.5) / n
  if v >= 1 then return 1 end
  return math.sin(v * math.pi / 2)
end

-- One stroke's height at (x, z), or 0 outside it.
local function strokeAt(st, x, z)
  local across, along
  if st.dir == "ew" then across, along = z, x else across, along = x, z end
  if across < st.a0 or across > st.a1 then return 0 end
  if along < st.b0 or along > st.b1 then return 0 end
  local d = st.a1 - st.a0 + 1
  local H = (d >= 12) and LedgeKit.H16 or LedgeKit.H8
  local h
  if st.dir == "ns" then
    h = profileSym(across - st.a0, d, H)
  else
    local t
    if st.high == "n" then t = across - st.a0 else t = st.a1 - across end
    h = profile(t, d, H)
  end
  if st.lo and st.lo > 0 then h = h * taper(along - st.b0, st.lo) end
  if st.hi and st.hi > 0 then h = h * taper(st.b1 - along, st.hi) end
  return h
end

-- --------------------------------------------------------------- model --

-- The model for template `t` read into sprite `sp` (its ground palette row
-- over the cell's own drawing). `t.bank` is the stroke list -- `bank`, not
-- `ledge`, which the building templates already use for their awning band.
function LedgeKit.model(sp, t)
  local strokes = t.bank
  if type(strokes) ~= "table" or #strokes == 0 then return nil end
  local C = 16
  local W = sp.W
  if W ~= C then return nil end
  -- the palette row: the high side's ground, eight rows above the drawing
  local off = t.topRows and (#t.topRows * 8) or 0
  local function groundTexel(x, z)
    if off == 0 then return nil end
    return (z % 8) * W + (x % 8)
  end
  -- the drawing's own earth: dark, light, and the outline
  local dark, light, black = nil, nil, nil
  local darks = {}
  for i = off * W, W * sp.H - 1 do
    local c = sp.col[i]
    if c == 2 then
      if #darks < 4 then darks[#darks + 1] = i end
      dark = dark or i
    elseif c == 1 then light = light or i
    elseif c == 3 then black = black or i end
  end
  dark = dark or light or black
  light = light or dark
  black = black or dark
  if not dark then return nil end
  if #darks == 0 then darks[1] = dark end

  -- the height field
  local hv = {}
  local ytop = 0
  for z = 0, C - 1 do
    for x = 0, C - 1 do
      local h = 0
      for i = 1, #strokes do
        local v = strokeAt(strokes[i], x, z)
        if v > h then h = v end
      end
      local n = floor(h + 0.5)
      if n > LedgeKit.H16 then n = LedgeKit.H16 end
      hv[z * C + x] = n
      if n > ytop then ytop = n end
    end
  end
  if ytop == 0 then return nil end

  local function at(x, y, z)
    if x < 0 or x >= C or z < 0 or z >= C or y < 0 then return nil end
    local n = hv[z * C + x]
    if y >= n then return nil end
    if y == n - 1 then
      -- the top: grass rolling over the bank; a one-voxel foot is the dark
      -- rim at the bottom of the fall
      if n == 1 then return black end
      return groundTexel(x, z) or light
    end
    -- below the top: the earth, showing wherever the fall is steep. Dark
    -- texels only, with a few of the outline's black: the drawing's LIGHT
    -- shade is the speckle of the bump art, and a riser wearing it came
    -- out as the same wicker the boxes wore.
    local r = hash2(x, y * 7 + z)
    if r < 0.08 then return black end
    return darks[1 + floor(r * 29) % #darks]
  end

  -- light per texel class: ground full, earth a little under, the rim dark
  local function tint(y, i)
    if i == nil then return 1 end
    if i == black then return LedgeKit.FOOT end
    if off > 0 and i < off * W then return 1 end
    return LedgeKit.SOIL
  end

  -- claim only the drawing's own tiles (LedgeKit.ART); the cell's grass or
  -- path keeps its art
  local mask = {}
  local tiles = t.tiles
  for r = 1, #tiles do
    for c = 1, #tiles[r] do
      mask[(r - 1) * #tiles[1] + c] = LedgeKit.ART[tiles[r][c]] and true or false
    end
  end

  return { at = at, W = C, ytop = ytop - 1, tint = tint, claimMask = mask,
           xmin = 0, xmax = C - 1, zmin = 0, zmax = C - 1 }
end

-- The tile the bank's top should wear. The candidates are the tiles just
-- beyond the first stroke's two edges -- the HIGH side first, then the
-- landing -- inside the cell when the ledge is the cell's lower row or
-- western column, the neighbour beyond it otherwise. Ledge art is never
-- a candidate; the mound's gravel (PLAIN) only when nothing else offers.
-- `tileAt(tx, ty)` reads the map; nil sends the caller to the plot's vote.
function LedgeKit.groundFor(t, tileAt, tx, ty)
  local st = t.bank and t.bank[1]
  if not st then return nil end
  local hx, hy, lx, ly
  if st.dir == "ew" then
    local col = tx + floor(st.b0 / 8)
    hx, hy = col, ty + floor(st.a0 / 8) - 1
    lx, ly = col, ty + floor((st.a1 + 1) / 8)
  else
    local row = ty + floor(st.b0 / 8)
    local west, east = tx + floor(st.a0 / 8) - 1, tx + floor((st.a1 + 1) / 8)
    if st.high == "e" then
      hx, hy, lx, ly = east, row, west, row
    else
      hx, hy, lx, ly = west, row, east, row
    end
  end
  local high, low = tileAt(hx, hy), tileAt(lx, ly)
  if high ~= nil and LedgeKit.ART[high] then high = nil end
  if low ~= nil and LedgeKit.ART[low] then low = nil end
  if high ~= nil and not LedgeKit.PLAIN[high] then return high end
  if low ~= nil and not LedgeKit.PLAIN[low] then return low end
  return high or low
end

return LedgeKit
