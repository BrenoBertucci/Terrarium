-- Voxel world mode: the CRYPT KIT -- the inside of the Pokemon Tower,
-- modelled by hand.
--
-- The seven floors of Lavender's tower and Agatha's room draw with one
-- tileset (CEMETERY): a ring of wall panels ($09/$0A over $19/$1A) cut out
-- of a grey mass ($11), a field of headstones ($05/$06 over $15/$16), a
-- flight up and a flight down. The profile pins stood the ring as a 16px
-- course of boxes wearing the panel drawing -- in Lavender's palette a ring
-- of red crates on a grey table top under a black sky, which is what the
-- floors looked like until now. A 2D chamber reads as a chamber because the
-- eye supplies the walls; a diorama has to build them.
--
-- This module is the RoomKit answer for it, on the same pipeline as every
-- building (data/voxel_heights.lua `buildings.CEMETERY`, matched by tile
-- grid, read from the atlas by Buildings.read, uploaded by Buildings.emit):
--
--   WALL    every ring cell that touches the room stands as a tall wall of
--           stone, and it is ONE wall: a cell knows what stands beside it
--           (the room, another wall cell, the dark) and builds its share
--           to meet it -- the next cell's masonry is answered to the
--           hidden-face test as a PHANTOM (Buildings.emit), computed by
--           the same formula, so no face is ever drawn where two cells
--           touch. The ring used to be sixteen-pixel crates: each cell
--           emitted its four sides in full and every seam where a
--           neighbour was shorter, or carved differently, showed as a lit
--           strip with a black core behind it. The wall is stone through
--           and through now, whichever face of it a camera finds.
--           Where the ring steps down toward the camera (the dollhouse
--           cut, lib/Crypt.lua's height per row) the top RAMPS from one
--           cell's height to the next instead of stepping, a course of
--           coping rides the cut, and the coping is a little ragged, the
--           way a wall's top is. The stone is lit rather than painted:
--           `tint` holds the drawing's WHITE down to grey and lets the
--           top rows fall to black, so the far walls climb out of the
--           light and no ceiling is needed -- and every flank gets the
--           SAME share whichever way it turns (the emitter's own south/
--           north/side is a sun standing to the south; there is no sun in
--           here), so it is the lanterns and the occlusion that say
--           which way a face looks. A cell the lantern table names
--           carries an iron bracket and a lantern at exactly the point
--           the scene shader burns its light.
--           With the photograph on (the CRYPT-FX row) every stone of the
--           wall's height map stands proud of its joint -- two voxels
--           into the room at the highest, one voxel back at the mortar --
--           so the silhouette IS the picture the shader paints, not a box
--           wearing it; two-face cells chamfer to a true octagon, the
--           plinth batters into the room, tall walls lean back a voxel
--           every few courses.
--   GRAVE   a headstone as a solid: a plinth, the stone on it wearing its
--           own drawing (front AND back) with the drawing's checker crown
--           and ink rim turned to the same grey as its panel -- a checker
--           of white and grey on a 16px stone is a pattern the eye reads
--           before it reads the stone -- and the lettering kept. Three
--           variants by cell hash so a field of them is not a stamp; on a
--           haunted floor some report a `haunt` so lib/GhostFX.lua
--           breathes wisps out of them.
--   MASS    the grey stock beyond the ring, and the ring cells that never
--           touch the room, go to a black slab: the crypt is walls standing
--           in darkness. (The mass tile is also pinned `void`, so the ring
--           beyond the map's edge lies flat instead of standing as a
--           plateau.)
--
-- Which cell gets which model is decided PER PLACEMENT: Buildings.build
-- asks `signature` for a short string (the wall's height band and its two
-- neighbours' along the run, what each side faces, a lantern side, a
-- variant, the photograph's phase) and builds one model per distinct
-- signature, so a wall knows where the room is without the template
-- having to. Coordinates handed to `at` are the model's own: x east, y up
-- from the floor, z south (toward the camera), the cell 0..15 either way;
-- a sconce overhangs the cell into the room the way a cornice overhangs a
-- facade -- never at ground level, where somebody walks.
--
-- Every visible voxel still wears a texel of the room's own atlas (the
-- palette row a template composites above its drawing: the all-white tile
-- $00 and the all-black $47), so the SGB palette and any recolour ride
-- along for free -- white stays white under every palette, which is what
-- makes the light do the colouring.
--
-- The CRYPT options row picks which interior stands: NEW is this kit,
-- CLASSIC the profile's pins as they were (Buildings.build asks `enabled`
-- at build time; the row's own step drops every cached mesh, as TOWER does).

local V = ...

local Crypt = V.require("Crypt")

local CryptKit = {}

local floor, sin = math.floor, math.sin

-- Buildings.PHANTOM: the next cell's voxel, present for the hidden-face
-- test and never drawn (any negative index)
local PHANTOM = -1

-- ------------------------------------------------------------- the row --
--
-- The setting itself is lib/Crypt.lua's (the scene half answers to it
-- too); the kit adds the remesh a flip of the geometry needs.
CryptKit.setting = Crypt.setting
CryptKit.enabled = Crypt.enabled

local function remesh()
  pcall(function()
    V.require("ChunkMesher").invalidate()
  end)
end

function CryptKit.setting:row()
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

function CryptKit.onOptionsChanged(value)
  CryptKit.setting:sync(value)
  remesh()
end

-- The CRYPT-FX row remeshes too: whether the walls draw their own courses
-- is decided when the model is built (see `ashlar` below).
function Crypt.fxSetting:row()
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

function CryptKit.onFxChanged(value)
  Crypt.fxSetting:sync(value)
  remesh()
end

-- ------------------------------------------------------------- the light --
--
-- Light per texel class, as a factor on the face shade (Buildings.emit
-- multiplies it in before the corner AO). The stone is the drawing's white
-- held to about half; three shades of it so a course is not one flat run.
CryptKit.SHADE = {
  stoneA = 0.56, stoneB = 0.48, stoneC = 0.64,
  joint  = 0.26,    -- the mortar, and the vertical joints
  trim   = 0.62,    -- plinth top, string course, coping, capitals
  damp   = 0.34,    -- the plinth's face
  mass   = 0.16,    -- (kept for the classic slab's neighbours)
  glow   = 1.05,    -- the lantern's glass (the flame card carries the light)
  black  = 1.0,     -- ironwork and the void slab (black is black)
}
-- Every vertical face's share of the emitter's shade, whichever way it
-- turns (see `tint`): the emitter's south is 1.0, its flanks 0.78, its
-- north 0.68 -- a sun to the south, which a crypt has not got. The tops
-- keep their own (0.95): what little fill there is comes from above.
CryptKit.SIDE = 0.90
CryptKit.FADE_FROM = 28       -- rows above this climb out of the light ...
CryptKit.FADE_TO = 0.05       -- ... down to this share at the top of a TALL wall
CryptKit.FOOT = 0.84          -- the damp foot: the lowest course's share
CryptKit.COURSE = 8           -- an ashlar course, in voxels (7 stone + 1 joint)
CryptKit.PLINTH = 5           -- the plinth's top row
CryptKit.STRING = 40          -- the string course's first row (tall walls)
CryptKit.CAP = 44             -- a pilaster's capital (walls tall enough)
CryptKit.LOW = 34             -- a wall this low is a parapet: coping, no batter
CryptKit.COPING = 2           -- rows of coping on every cut wall

-- --------------------------------------------------------------- texels --
--
-- The palette row composited above every template: tile $00 (all white)
-- at sx 0..7 and tile $47 (all black) at sx 8..15, sprite rows 0..7. Every
-- class is its own white texel so the light can tell them apart -- and the
-- ones that meet along a row sit two atlas columns apart, so the greedy
-- merge (which folds CONSECUTIVE atlas texels into one strip) never fuses
-- a joint into the block beside it.
local W = 16
local function tex(sx, sy) return sy * W + sx end
local T = {
  stoneA = tex(0, 0), stoneB = tex(2, 0), stoneC = tex(4, 0), joint = tex(7, 0),
  trim = tex(0, 1), glow = tex(2, 1), mass = tex(4, 1), damp = tex(6, 1),
  black = tex(8, 0),
}
local STONES = { T.stoneA, T.stoneB, T.stoneC }
local CLASS = {}
for name, i in pairs(T) do CLASS[i] = name end

local function hash2(x, z)
  local n = sin(x * 12.9898 + z * 78.233) * 43758.5453
  return n - floor(n)
end

-- ------------------------------------------------------------ signature --
--
-- The cells that count as ROOM when a wall asks what is beside it: the
-- floor, the graves, both flights, the 1F counter (its surface and its
-- north-south arm), 5F's healing pad and 7F's potted palms. Keyed by the
-- cell's top-left tile, which is what the placement scan reads.
local ROOM = { [0x01] = true, [0x05] = true, [0x03] = true, [0x0B] = true,
               [0x02] = true, [0x1D] = true, [0x22] = true,
               [0x27] = true, [0x37] = true, [0x3D] = true }
-- and the cells that are the RING itself, by the same tile: the chamber's
-- wall panel and Agatha's band (the two templates below)
local RING = { [0x09] = true, [0x20] = true }

local function mapId(map)
  local def = map and map.def
  return def and (def.id or def.name) or "?"
end

-- The short string one placement of template `t` builds under. `tileAt`
-- reads the map in TILE coordinates; (tx, ty) is the placement's top-left.
--
--   w<H>:<n><e><s><w>:<site>:<seed>:<Hn>.<Hs>[:p<px>.<py>]
--
-- Each side is one of `r` (the room: a face, worn and lit), `w` (a wall
-- cell that touches the room: the wall goes on, nothing to draw between
-- the two) or `o` (open to the dark: the black slabs, the void past the
-- map's edge -- a face, worn where the camera can see a wall's outside).
-- Hn and Hs are the rows' heights to the north and the south, for the
-- ramp a cut wall's top runs between them.
function CryptKit.signature(t, tileAt, tx, ty, map)
  local kind = t.crypt
  if kind == "mass" then return "m" end
  local id = mapId(map)
  local h = floor(hash2(tx + 3, ty + 7) * 1000)
  if kind == "grave" then
    -- one grave in six sighs on a haunted floor: enough that the field
    -- is never still, few enough that the stones stay visible under it
    local haunted = Crypt.haunted(id) and (h % 6 == 0)
    return ("g%d%s"):format(h % 3, haunted and "H" or "")
  end
  local function room(x, y)
    local tile = tileAt(x, y)
    return tile ~= nil and ROOM[tile] == true
  end
  local function touches(x, y)
    if not RING[tileAt(x, y)] then return false end
    return room(x, y - 2) or room(x + 2, y) or room(x, y + 2) or room(x - 2, y)
  end
  local function side(dx, dy)
    if room(tx + dx, ty + dy) then return "r" end
    if touches(tx + dx, ty + dy) then return "w" end
    return "o"
  end
  local n, e, s, w = side(0, -2), side(2, 0), side(0, 2), side(-2, 0)
  -- a ring cell that touches no room is backing: it goes to the dark
  if n ~= "r" and e ~= "r" and s ~= "r" and w ~= "r" then return "m" end
  local cx, cy = floor(tx / 2), floor(ty / 2)
  local H = Crypt.heightFor(id, cy)
  local Hn, Hs = Crypt.heightFor(id, cy - 1), Crypt.heightFor(id, cy + 1)
  local site = Crypt.siteAt(id, cx, cy)
  -- a lantern must hang on a face that looks into the room
  if site and not ((site == "n" and n == "r") or (site == "e" and e == "r")
                   or (site == "s" and s == "r") or (site == "w" and w == "r")) then
    site = nil
  end
  -- With the photograph on, the wall is carved by the photograph's own
  -- height (see wallModel), and where a cell stands in the photograph's
  -- cycle -- sixteen cells (Crypt.STONE.scale) -- is part of what it is.
  -- The phase along x is what a south or north face reads, the phase
  -- along y what an east or west face reads; the model is built per pair
  -- that occurs, and the octagon repeats floor to floor so the pairs do.
  local phase = ""
  if Crypt.fxOn() then
    local cells = floor((Crypt.STONE.scale or 256) / 16)
    if cells < 1 then cells = 1 end
    phase = (":p%d.%d"):format(cx % cells, cy % cells)
  end
  return ("w%d:%s%s%s%s:%s:%d:%d.%d%s"):format(H, n, e, s, w, site or "-",
                                             h % 3, Hn, Hs, phase)
end

local function parse(sig)
  local S = { kind = sig:sub(1, 1) }
  if S.kind == "g" then
    S.variant = tonumber(sig:sub(2, 2)) or 0
    S.haunted = sig:find("H", 1, true) ~= nil
  elseif S.kind == "w" then
    local H, nesw, site, seed, Hn, Hs =
      sig:match("^w(%d+):(%a%a%a%a):(.):(%d):(%d+)%.(%d+)")
    if not H then return S end
    S.H = tonumber(H) or Crypt.TALL
    S.side = { n = nesw:sub(1, 1), e = nesw:sub(2, 2),
               s = nesw:sub(3, 3), w = nesw:sub(4, 4) }
    S.site = site ~= "-" and site or nil
    S.seed = tonumber(seed) or 0
    S.Hn = tonumber(Hn) or S.H
    S.Hs = tonumber(Hs) or S.H
    local px, py = sig:match(":p(%d+)%.(%d+)$")
    if px then
      S.photo = true
      S.px, S.py = tonumber(px), tonumber(py)
    end
  end
  return S
end

-- ------------------------------------------------------- the height map --
--
-- The wall photograph's own height (assets/stone/crypt_wall_h.png, 8-bit,
-- baked from Poly Haven's displacement), read the way the scene shader
-- reads its albedo: u and v in world pixels over Crypt.STONE.scale per
-- cycle, v the world's y. Loaded once, through the mod's own reader (the
-- StreetLamps lesson: love.filesystem cannot see the mod tree).
local heightData = nil       -- ImageData | false

local function loadHeight()
  if heightData ~= nil then return heightData or nil end
  local rel = (Crypt.STONE.dir or "assets/stone/") .. (Crypt.STONE.wallHeight or "")
  local data = nil
  local newID = love and love.image and love.image.newImageData
  if newID and V.mod and V.mod.read then
    local ok, bytes = pcall(V.mod.read, V.mod, rel)
    if ok and type(bytes) == "string" and #bytes > 16
        and love.data and love.data.newByteData then
      local okF, fd = pcall(love.data.newByteData, bytes)
      if okF and fd then
        local okD, d = pcall(newID, fd)
        if okD and d and d.getPixel then data = d end
      end
    end
  end
  if not data and newID then
    local base = tostring((V and V.path) or ""):gsub("\\", "/")
    if base ~= "" and base:sub(-1) ~= "/" then base = base .. "/" end
    local okD, d = pcall(newID, base .. rel)
    if okD and d and d.getPixel then data = d end
  end
  heightData = data or false
  return data
end

-- height 0..1 at world (u, v), or nil without a map
local function heightAt(u, v)
  local d = loadHeight()
  if not d then return nil end
  local scale = Crypt.STONE.scale or 256
  local w, h = d:getDimensions()
  -- box-filtered over the voxel's own patch of the map (four texels to a
  -- world pixel here), so the carving follows the stones and not the
  -- grain: sampled at one texel the joints came out speckled
  local fx = u / scale * w
  local fy = v / scale * h
  local sum = 0
  for oy = -1, 1, 2 do
    for ox = -1, 1, 2 do
      local tx = floor(fx + ox * 1.5) % w
      local ty = floor(fy + oy * 1.5) % h
      if tx < 0 then tx = tx + w end
      if ty < 0 then ty = ty + h end
      sum = sum + d:getPixel(tx, ty)
    end
  end
  return sum * 0.25
end

-- How the photograph (and the drawn ashlar) stand in DEPTH, not just on
-- a box. d = 0 is the cell's room-facing plane; negative is into the
-- room; positive is into the wall. A stone at 0.80 of the height map
-- stands two voxels proud; mortar recedes one. The old binary "outermost
-- voxel or nothing" left the ring a stack of 16px crates with holes
-- punched in the paper -- the texture never sat, because the silhouette
-- was still a rectangle.
CryptKit.RELIEF_THRESHOLD = 0.46   -- flush stone vs joint
CryptKit.RELIEF_MAX = 2            -- voxels into the room at the highest stones
CryptKit.RELIEF_RECESS = 1         -- voxels into the wall at the mortar
CryptKit.CHAMFER = 5               -- 45-cut on two-face cells, in voxels
CryptKit.BATTER_EVERY = 28         -- 1 voxel of lean-back per this many rows
CryptKit.RAG = 6                   -- the coping's stones, world px each

-- ------------------------------------------------------------------ mass --

local function massModel()
  return {
    at = function(x, y, z)
      if x < 0 or x > 15 or z < 0 or z > 15 or y < 0 or y > 1 then return nil end
      return T.black
    end,
    W = W, ytop = 1, xmin = 0, xmax = 15, zmin = 0, zmax = 15,
  }
end

-- ----------------------------------------------------------------- wall --

local function wallModel(sp, S)
  local H = S.H
  local K = S.side
  local ex = { n = K.n == "r", e = K.e == "r", s = K.s == "r", w = K.w == "r" }
  local TALL = Crypt.TALL or 88
  local isTall = H >= TALL
  local low = H <= CryptKit.LOW
  local tall = H >= 52
  -- Which sides wear the stone: one that looks into the room; and, on a
  -- wall the camera looks over or past (anything under the tall band),
  -- one that looks out into the dark -- its outside shows. A side against
  -- another wall cell is the wall's own inside and wears nothing: that
  -- boundary is answered to the emitter as phantom masonry (see `at`).
  local wear = {}
  for _, k in ipairs({ "n", "e", "s", "w" }) do
    wear[k] = (K[k] == "r") or (K[k] == "o" and not isTall)
  end

  -- With the photograph on (see `ashlar` and the signature's phase) the
  -- wall's face is CARVED BY THE PHOTOGRAPH IN DEPTH: each stone of the
  -- height map stands proud of its joint -- two voxels into the room at
  -- the highest, flush in the middle, one voxel back at the mortar --
  -- so the silhouette, the albedo, the relief map and the occlusion all
  -- describe the same stones. Two-face cells take a 45-cut so the ring
  -- is an octagon, not a stack of crates; the plinth batters into the
  -- room; tall walls lean back. The drawn dressings (pilasters, string
  -- course) stand aside for the same reason the courses do: the picture
  -- carries the masonry. Off, the wall is the ashlar the kit always
  -- drew, with the same depth (a joint sits back, a block sits proud)
  -- so even without the picture the wall is masonry, not a painted box.
  local photo = S.photo and loadHeight() ~= nil
  local phaseX = (S.px or 0) * 16
  local phaseY = (S.py or 0) * 16
  -- corner pilasters: one for every pair of adjacent room-facing sides.
  -- The photograph chamfers those corners instead (see `chamferRecess`).
  local piers = {}
  if not photo then
    if ex.s and ex.e then piers[#piers + 1] = { 13, 15, 13, 15 } end
    if ex.s and ex.w then piers[#piers + 1] = { 0, 2, 13, 15 } end
    if ex.n and ex.e then piers[#piers + 1] = { 13, 15, 0, 2 } end
    if ex.n and ex.w then piers[#piers + 1] = { 0, 2, 0, 2 } end
  end
  local capY = (H >= 34 and not photo) and math.min(CryptKit.CAP, H - 6) or nil

  local function inPier(x, z, grow)
    grow = grow or 0
    for i = 1, #piers do
      local p = piers[i]
      if x >= p[1] - grow and x <= p[2] + grow
          and z >= p[3] - grow and z <= p[4] + grow then
        return true
      end
    end
    return false
  end

  -- d = 0 is the cell's face plane on the nearest worn side (x/z = 0 or
  -- 15); negative is out past it, positive into the wall. `u` runs along
  -- the face -- an x on a south/north, a z on an east/west -- which is
  -- also the photograph's u (the shader maps a Z-facing wall in world XY,
  -- an X-facing wall in world ZY, so moving in depth does not slide the
  -- art off the stones we stand). Answered for positions outside the
  -- cell too: u past 0..15 is simply the next cell's u.
  local function faceDepth(x, z)
    local d, u, side = 99, x, nil
    if wear.s then
      local ds = 15 - z
      if ds < d then d, u, side = ds, x, "s" end
    end
    if wear.n then
      local dn = z
      if dn < d then d, u, side = dn, x, "n" end
    end
    if wear.e then
      local de = 15 - x
      if de < d then d, u, side = de, z, "e" end
    end
    if wear.w then
      local dw = x
      if dw < d then d, u, side = dw, z, "w" end
    end
    return d, u, side
  end

  local function alongWorld(u, side)
    if side == "e" or side == "w" then return phaseY + u end
    return phaseX + u
  end

  -- 45-cut on a two-face cell: k is manhattan distance from the inner
  -- corner of the L, so k = 0 is the 90-degree nose. Recessing that
  -- nose by CHAMFER voxels turns the crate-corner into an octagon
  -- facet. Axis-aligned still -- the greedy mesher only emits those --
  -- but the silhouette reads as a diagonal from the authored south
  -- camera, which is the whole point of the dollhouse.
  local CHAMFER = CryptKit.CHAMFER
  local function chamferRecess(x, z)
    if CHAMFER <= 0 then return 0 end
    local extra = 0
    local function cut(k)
      if k < CHAMFER then
        local e = CHAMFER - k
        if e > extra then extra = e end
      end
    end
    if ex.s and ex.e then cut((15 - x) + (15 - z)) end
    if ex.s and ex.w then cut(x + (15 - z)) end
    if ex.n and ex.e then cut((15 - x) + z) end
    if ex.n and ex.w then cut(x + z) end
    return extra
  end

  local seed = S.seed
  local plinth = CryptKit.PLINTH
  local course = CryptKit.COURSE
  local BATTER_EVERY = CryptKit.BATTER_EVERY
  local PROUD_MAX = CryptKit.RELIEF_MAX

  -- With the CRYPT-FX row on, the masonry is the PHOTOGRAPH's (the wall
  -- wears Poly Haven's rubble stone, its own joints and all -- see
  -- lib/Crypt.lua), so the drawn courses step aside: one stone class, no
  -- joints, and the picture is not ruled over with a second grid. Off,
  -- the courses are what says "ashlar" -- laid in WORLD units along the
  -- face, so a joint falls where the next cell's joint falls. Decided at
  -- build time, which is why the row remeshes.
  local function ashlar(wu, y)
    if photo then return T.stoneA end
    local yy = y - plinth - 1
    if yy % course == course - 1 then return T.joint end
    local c = floor(yy / course)
    local stagger = (c % 2) * 8
    if (wu + stagger) % 16 == 0 then return T.joint end
    local blockIx = floor((wu + stagger) / 16)
    local r = hash2(c * 3 + 1, blockIx * 5 + 1)
    return STONES[1 + floor(r * 2.999)]
  end

  -- height samples repeat across a column of depths; cache per (u, y)
  local hcache = {}
  local function heightCached(wu, y)
    local key = wu * 4096 + y
    local h = hcache[key]
    if h ~= nil then
      if h < 0 then return nil end
      return h
    end
    local got = heightAt(wu, y)
    hcache[key] = got or -1
    return got
  end

  -- how many voxels this (along, y) stands out past the face (negative =
  -- recessed into the wall). The height map's own gradients bevel the
  -- stones: a neighbour at a lower proud is the stone's side.
  local function proudOf(u, y, side)
    local wu = alongWorld(u, side)
    if not photo then
      local yy = y - plinth - 1
      if yy >= 0 and yy % course == course - 1 then return -1 end
      local c = floor(yy / course)
      local stagger = (c % 2) * 8
      if (wu + stagger) % 16 == 0 then return -1 end
      return 1
    end
    local h = heightCached(wu, y)
    if h == nil then return 0 end
    if h >= 0.80 then return PROUD_MAX end
    if h >= 0.62 then return 1 end
    if h >= CryptKit.RELIEF_THRESHOLD then return 0 end
    return -CryptKit.RELIEF_RECESS
  end

  -- the sconce, in cell coordinates, from the shared table
  local site = S.site
  local fx, fy, fz, standing
  if site then fx, fy, fz, standing = Crypt.flameLocal(site, H) end
  local lx, lz = fx and floor(fx) or 0, fz and floor(fz) or 0

  local function lantern(x, y, z)
    if not site then return nil end
    -- the lantern box: base, three rows of glass, cap
    if x >= lx - 1 and x <= lx + 1 and z >= lz - 1 and z <= lz + 1 then
      if y == fy - 3 or y == fy + 1 then return T.black end
      if y >= fy - 2 and y <= fy then
        -- a black corner post at each edge so the glass reads as panes
        if (x == lx - 1 or x == lx + 1) and (z == lz - 1 or z == lz + 1) then
          return T.black
        end
        return T.glow
      end
    end
    if standing then return nil end
    -- the bracket: an arm from the face to over the lantern, at fy + 2
    if y == fy + 2 then
      if site == "s" and x == lx and z >= 16 and z <= lz then return T.black end
      if site == "n" and x == lx and z <= -1 and z >= lz then return T.black end
      if site == "e" and z == lz and x >= 16 and x <= lx then return T.black end
      if site == "w" and z == lz and x <= -1 and x >= lx then return T.black end
    end
    -- and a short stem down the face under the arm's root
    if y >= fy - 1 and y <= fy + 1 then
      if site == "s" and x == lx and z == 16 then return T.black end
      if site == "n" and x == lx and z == -1 then return T.black end
      if site == "e" and z == lz and x == 16 then return T.black end
      if site == "w" and z == lz and x == -1 then return T.black end
    end
    return nil
  end

  -- THE TOP. Along the run (north to south: the rows are what the
  -- dollhouse cut is authored by) the top ramps from the cell's own
  -- height toward each neighbour's -- a neighbour that is wall or dark;
  -- a wall ending at the room ends square. Cell centres carry the row's
  -- height, so two cells meet at the mean of theirs and the ramp is
  -- continuous across the seam. A standing lantern needs its coping
  -- level: that cell keeps its height flat. The tall band has no ramp
  -- to speak of (its neighbours are tall) and no rag: its top is in the
  -- dark anyway.
  local Hn = (K.n ~= "r") and S.Hn or H
  local Hs = (K.s ~= "r") and S.Hs or H
  if standing then Hn, Hs = H, H end
  local function rampAt(z)
    if z < 8 then return Hn + (H - Hn) * ((z + 8) / 16) end
    return H + (Hs - H) * ((z - 8) / 16)
  end
  -- the rag: the coping's stones stand a voxel up or down in stones of
  -- RAG world px along the face -- a wall's top, not a ruled line
  local runX = (ex.n or ex.s) and not (ex.e or ex.w)
  local RAG = CryptKit.RAG
  local function ragAt(x, z)
    if isTall or standing then return 0 end
    local wu = runX and (phaseX + x) or (phaseY + z)
    local r = hash2(floor(wu / RAG) * 7 + seed, 3)
    if r < 0.18 then return -1 end
    if r > 0.86 then return 1 end
    return 0
  end
  local function topAt(x, z)
    return floor(rampAt(z) + 0.5) + ragAt(x, z)
  end

  local function at(x, y, z)
    if y < 0 then return nil end
    -- the lantern first: it lives outside the cell and above the wall
    local L = lantern(x, y, z)
    if L then return L end
    local outX = (x < 0) and -1 or ((x > 15) and 1 or 0)
    local outZ = (z < 0) and -1 or ((z > 15) and 1 or 0)
    local outside = outX ~= 0 or outZ ~= 0
    -- a capital's overhang (non-photo)
    if outside and capY and y >= capY and y <= capY + 1 and inPier(x, z, 1) then
      return T.trim
    end
    local top = topAt(x, z)
    if y >= top then return nil end
    -- past a side that another wall cell stands on, what is there is
    -- that cell's masonry: phantom, for the hidden-face test
    local crossW = (outX == -1 and K.w == "w") or (outX == 1 and K.e == "w")
                   or (outZ == -1 and K.n == "w") or (outZ == 1 and K.s == "w")
    -- past a corner of the cell only the neighbour's own overhang lives
    if outside and not crossW and outX ~= 0 and outZ ~= 0 then return nil end

    local d, u, side = faceDepth(x, z)
    local proud = side and proudOf(u, y, side) or 0
    -- the plinth is a solid step, two voxels proud at the foot so the
    -- wall sits on a base instead of rising as a plane
    if y <= plinth then
      local foot = (y <= 1) and 2 or 1
      if proud < foot then proud = foot end
    end
    -- the coping stays whole (the dollhouse lip the camera looks over),
    -- a voxel proud
    local coping = (not isTall) and y >= top - CryptKit.COPING
    if coping and proud < 1 then proud = 1 end
    -- non-photo dressings: piers and the string course stand proud
    local pier = (not photo) and inPier(x, z)
    if pier and proud < 2 then proud = 2 end
    if (not photo) and tall
        and (y == CryptKit.STRING or y == CryptKit.STRING + 1)
        and proud < 1 then
      proud = 1
    end
    -- a few footing stones scatter along the foot so the wall meets
    -- the flagstones as masonry, not a ruled line
    if y == 0 and side and hash2(alongWorld(u, side) * 0.37 + 5, 19) < 0.32
        and proud < PROUD_MAX then
      proud = proud + 1
    end

    local batter = 0
    if (not low) and y > plinth and BATTER_EVERY > 0 then
      batter = floor((y - plinth) / BATTER_EVERY)
      if batter > 2 then batter = 2 end
    end

    local need = -proud + chamferRecess(x, z) + batter
    if side and d < need then return nil end

    if outside then
      if crossW then return PHANTOM end
      -- past a worn face: the overhang, straight out of that face
      if not side or d >= 0 then return nil end
      local straight = (outX == 1 and side == "e") or (outX == -1 and side == "w")
                       or (outZ == 1 and side == "s") or (outZ == -1 and side == "n")
      if not straight then return nil end
    end

    -- the texel: a cut wall's top course is coping through its whole
    -- thickness (a wall shows its top); the rest is stone through and
    -- through -- whichever face of it a camera finds is a face of stone
    if coping then return T.trim end
    if capY and pier and y >= capY and y <= capY + 1 then return T.trim end
    if photo then return T.stoneA end
    if y == plinth then return T.trim end
    if y < plinth then return T.damp end
    if tall and (y == CryptKit.STRING or y == CryptKit.STRING + 1) then
      return T.trim
    end
    if pier then return T.stoneA end
    return ashlar(side and alongWorld(u, side) or x, y)
  end

  -- the light: the class's own share, falling away up the wall -- from
  -- the same row on every wall, so a cut wall's top stays in the light
  -- the tall band has left by that height
  local fadeFrom, fadeTo = CryptKit.FADE_FROM, CryptKit.FADE_TO
  local function vert(y)
    if y <= fadeFrom then return 1 end
    local t = (y - fadeFrom) / (TALL - fadeFrom)
    if t > 1 then t = 1 end
    return 1 - (1 - fadeTo) * t * t * (3 - 2 * t)
  end
  local SIDE = CryptKit.SIDE
  local function tint(y, i, dir, shade)
    local name = i and CLASS[i]
    if not name then return 1 end
    local f = CryptKit.SHADE[name] or 1
    if name == "glow" or name == "black" then return f end
    if y < CryptKit.COURSE and name ~= "trim" then f = f * CryptKit.FOOT end
    f = f * vert(y)
    -- lit, not sunlit: every flank the same share whichever way it
    -- turns; the lanterns and the occlusion say which way is which
    if shade and shade > 0 and dir ~= "up" and dir ~= "down" then
      f = f * (SIDE / shade)
    end
    return f
  end

  local ytop = floor(math.max(H, (H + Hn) / 2, (H + Hs) / 2)) + 1
  if site then ytop = math.max(ytop, floor(fy) + 2) end
  return {
    at = at, W = W, ytop = ytop, tint = tint,
    xmin = -6, xmax = 21, zmin = -6, zmax = 21,
  }
end

-- ---------------------------------------------------------------- grave --
--
-- The drawing ($05/$06 over $15/$16), rows 0..15 of the cell:
--   rows  1..10  the headstone, columns 3..12 (a black rim, a checker
--                crown, a framed panel with its lettering)
--   rows  7..10  two small posts flanking it, columns 1..2 and 13..14
--   rows 11..15  the plinth, columns 1..14 (a light top rim, a dark face,
--                a black foot)
-- A stone stands about as tall as the person walking past it (the drawing's
-- ten rows over twelve voxels, on a four-voxel plinth): taller and the
-- field reads as monoliths, and a stone in front of the player hides him
-- from the fixed camera -- the LAW every authored shot answers to.
local PLINTH_H = 4
local STONE_H = { 12, 10, 14 }
local GRAVE_SIDE = 0.86       -- every flank's share (see wallModel's tint)
local function graveModel(sp, S)
  local off = 8
  local function pix(x, r) return (off + r) * W + x end
  -- the drawing's greys by name: the panel's light grey and the frame's
  -- dark grey are what the shader dresses in granite (its whites would
  -- come out as wall, its blacks as ink -- see the material block)
  local LIGHT = pix(5, 5)
  local DARK = pix(4, 4)
  local v = S.variant or 0
  local stoneH = STONE_H[v + 1]
  local pz0, pz1 = ({ 5, 6, 4 })[v + 1], ({ 12, 11, 12 })[v + 1]
  local H = PLINTH_H + stoneH
  -- The stone's SILHOUETTE is the drawing's: per row, the span of its
  -- painted pixels (the arch's outline rounds the top corners off, and
  -- the shoulders come in a pixel), so the granite the shader lays over it
  -- lies on a headstone's shape rather than a brick's. Read once.
  local span = {}
  for r = 1, 10 do
    local x0, x1 = nil, nil
    for x = 2, 13 do
      if sp.col[pix(x, r)] ~= 0 then
        x0 = x0 or x
        x1 = x
      end
    end
    span[r] = { x0 or 3, x1 or 12 }
  end
  -- the face: the drawing, its checker crown and its ink rim turned to
  -- the stone's own greys (the crown light, the rim a weathered edge in
  -- shadow), the bands and the lettering kept
  local function face(x, r)
    if r <= 3 then
      return (x <= 3 or x >= 12) and DARK or LIGHT
    end
    if x == 3 or x == 12 then return DARK end
    return pix(x, r)
  end
  local function at(x, y, z)
    if x < 0 or x > 15 or z < 0 or z > 15 or y < 0 then return nil end
    -- the plinth: two steps, the lower a voxel wider all round
    if y < PLINTH_H then
      local step = (y < 2) and 1 or 0
      if x >= 1 - step and x <= 14 + step and z >= pz0 - step and z <= pz1 + step then
        if y == PLINTH_H - 1 then return pix(x < 1 and 1 or (x > 14 and 14 or x), 12) end
        if y == 0 then return pix(x < 1 and 1 or (x > 14 and 14 or x), 15) end
        return pix(x < 1 and 1 or (x > 14 and 14 or x), 13 + (y % 2))
      end
      return nil
    end
    -- the headstone, front and back wearing the drawing, its edges
    -- chamfered a voxel where the drawing rounds them
    if y < H and z >= 7 and z <= 10 then
      local r = 1 + floor((H - 1 - y) * 10 / stoneH)
      if r > 10 then r = 10 end
      local sx0, sx1 = span[r][1], span[r][2]
      if x < sx0 or x > sx1 then return nil end
      -- the top: one voxel in from the shoulders, and the front and back
      -- faces a voxel in at the very top so the crown rounds
      if y == H - 1 then
        if x == sx0 or x == sx1 or z == 7 or z == 10 then return nil end
        return LIGHT
      end
      if (z == 10 or z == 7) and (x == sx0 or x == sx1) and y >= H - 3 then
        return nil
      end
      if z == 10 or z == 7 then return face(x, r) end
      return LIGHT
    end
    -- the posts
    if y <= PLINTH_H + 3 and z >= 7 and z <= 9
        and ((x >= 1 and x <= 2) or (x >= 13 and x <= 14)) then
      return DARK
    end
    return nil
  end
  local function tint(y, i, dir, shade)
    local f = (y < PLINTH_H) and 0.82 or 1
    if shade and shade > 0 and dir ~= "up" and dir ~= "down" then
      f = f * (GRAVE_SIDE / shade)
    end
    return f
  end
  local m = {
    at = at, W = W, ytop = H - 1, tint = tint,
    xmin = 0, xmax = 15, zmin = 0, zmax = 15,
  }
  if S.haunted then
    -- a sigh every dozen or so seconds, small and low: the tower's
    -- lantern storey pours, a grave breathes
    m.haunt = { box = { 0, 0, 15, 15 }, top = H, color = { 0.62, 0.80, 1.0 },
                slow = 30, scale = 0.55, wisps = { { 8, H + 1, 8, "grave" } } }
  end
  return m
end

-- ------------------------------------------------------------------- api --

-- The model for template `t` read into sprite `sp` under signature `sig`,
-- or nil and a reason (the caller records it and leaves the tiles to the
-- class pins).
function CryptKit.model(sp, t, sig)
  if sp.W ~= 16 or sp.H ~= 24 then
    return nil, ("unexpected sprite %dx%d"):format(sp.W, sp.H)
  end
  local S = parse(tostring(sig))
  if S.kind == "m" then return massModel() end
  if S.kind == "g" then return graveModel(sp, S) end
  if S.kind == "w" and S.H and S.side then return wallModel(sp, S) end
  return nil, "bad signature " .. tostring(sig)
end

-- for the probes: what a signature says
CryptKit.parse = parse

return CryptKit
