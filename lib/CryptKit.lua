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
--           ashlar -- courses of blocks, staggered joints, a proud plinth,
--           a string course, a pilaster at every corner the ring turns --
--           and it is lit rather than painted: `tint` holds the drawing's
--           WHITE down to grey stone and lets the top rows fall to black,
--           so the far walls climb out of the light and no ceiling is
--           needed. The near walls are cut down to a parapet with a coping
--           (the dollhouse cut), so the fixed camera at the south looks
--           over them; how tall a row stands is lib/Crypt.lua's to say.
--           A cell the lantern table names carries an iron bracket and a
--           lantern at exactly the point the scene shader burns its light.
--   GRAVE   a headstone as a solid: a plinth, the stone on it wearing its
--           own drawing (front AND back), the two small posts beside it.
--           Three variants by cell hash so a field of them is not a stamp;
--           on a haunted floor some report a `haunt` so lib/GhostFX.lua
--           breathes wisps out of them.
--   MASS    the grey stock beyond the ring, and the ring cells that never
--           touch the room, go to a black slab: the crypt is walls standing
--           in darkness. (The mass tile is also pinned `void`, so the ring
--           beyond the map's edge lies flat instead of standing as a
--           plateau.)
--
-- Which cell gets which model is decided PER PLACEMENT: Buildings.build
-- asks `signature` for a short string (the wall's height band, which sides
-- face the room, a lantern side, a variant) and builds one model per
-- distinct signature, so a wall knows where the room is without the
-- template having to. Coordinates handed to `at` are the model's own:
-- x east, y up from the floor, z south (toward the camera), the cell 0..15
-- either way; a sconce overhangs the cell into the room the way a cornice
-- overhangs a facade -- never at ground level, where somebody walks.
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
  mass   = 0.16,    -- faces that look into the dark
  glow   = 1.05,    -- the lantern's glass (the flame card carries the light)
  black  = 1.0,     -- ironwork and the void slab (black is black)
}
CryptKit.FADE_FROM = 30       -- rows above this climb out of the light ...
CryptKit.FADE_TO = 0.05       -- ... down to this share at the top of a tall wall
CryptKit.FOOT = 0.84          -- the damp foot: the lowest course's share
CryptKit.COURSE = 8           -- an ashlar course, in voxels (7 stone + 1 joint)
CryptKit.PLINTH = 5           -- the plinth's top row
CryptKit.STRING = 40          -- the string course's first row (tall walls)
CryptKit.CAP = 44             -- a pilaster's capital (walls tall enough)

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

local function mapId(map)
  local def = map and map.def
  return def and (def.id or def.name) or "?"
end

-- The short string one placement of template `t` builds under. `tileAt`
-- reads the map in TILE coordinates; (tx, ty) is the placement's top-left.
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
  local n = room(tx, ty - 2) and 1 or 0
  local e = room(tx + 2, ty) and 1 or 0
  local s = room(tx, ty + 2) and 1 or 0
  local w = room(tx - 2, ty) and 1 or 0
  -- a ring cell that touches no room is backing: it goes to the dark
  if n + e + s + w == 0 then return "m" end
  local cx, cy = floor(tx / 2), floor(ty / 2)
  local H = Crypt.heightFor(id, cy)
  local site = Crypt.siteAt(id, cx, cy)
  -- a lantern must hang on a face that looks into the room
  if site and not ((site == "n" and n == 1) or (site == "e" and e == 1)
                   or (site == "s" and s == 1) or (site == "w" and w == 1)) then
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
  return ("w%d:%d%d%d%d:%s:%d%s"):format(H, n, e, s, w, site or "-", h % 3,
                                        phase)
end

local function parse(sig)
  local S = { kind = sig:sub(1, 1) }
  if S.kind == "g" then
    S.variant = tonumber(sig:sub(2, 2)) or 0
    S.haunted = sig:find("H", 1, true) ~= nil
  elseif S.kind == "w" then
    local H, nesw, site, seed = sig:match("^w(%d+):(%d%d%d%d):(.):(%d)")
    S.H = tonumber(H) or Crypt.TALL
    S.n = nesw:sub(1, 1) == "1"
    S.e = nesw:sub(2, 2) == "1"
    S.s = nesw:sub(3, 3) == "1"
    S.w = nesw:sub(4, 4) == "1"
    S.site = site ~= "-" and site or nil
    S.seed = tonumber(seed) or 0
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

CryptKit.RELIEF_THRESHOLD = 0.56   -- height under which a voxel of face is a joint
CryptKit.RELIEF_MAX = 1.0          -- (kept for the probe: one voxel of carving)

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
  local low = H <= 34
  local tall = H >= 52
  local ex = { n = S.n, e = S.e, s = S.s, w = S.w }
  -- a low wall is looked at from the outside too (the parapets the camera
  -- looks over), so every side of it wears the stone
  local wear = low and { n = true, e = true, s = true, w = true } or ex

  -- With the photograph on (see `ashlar` and the signature's phase) the
  -- wall's face is CARVED BY THE PHOTOGRAPH: the outermost voxel of every
  -- room-facing side stands where the picture's height says a stone is
  -- and is missing where it says a joint is, so the stones the albedo
  -- and the relief map paint are the stones the voxels stand as -- the
  -- lantern, the occlusion and the silhouette all agree. The drawn
  -- dressings (pilasters, string course) stand aside for the same reason
  -- the courses do: the picture carries the masonry. Off, the wall is the
  -- ashlar the kit always drew.
  local photo = S.photo and loadHeight() ~= nil
  local phaseX = (S.px or 0) * 16
  local phaseY = (S.py or 0) * 16
  -- corner pilasters: one for every pair of adjacent room-facing sides
  local piers = {}
  if not photo then
    if ex.s and ex.e then piers[#piers + 1] = { 13, 15, 13, 15 } end
    if ex.s and ex.w then piers[#piers + 1] = { 0, 2, 13, 15 } end
    if ex.n and ex.e then piers[#piers + 1] = { 13, 15, 0, 2 } end
    if ex.n and ex.w then piers[#piers + 1] = { 0, 2, 0, 2 } end
  end
  local capY = (H >= 34 and not photo) and math.min(CryptKit.CAP, H - 6) or nil
  -- the face's world coordinate along it, for the height map: an x for a
  -- south or north face, a z for an east or west one
  local function alongWorld(x, z)
    local d, side = 99, nil
    if wear.s and 15 - z < d then d, side = 15 - z, "s" end
    if wear.n and z < d then d, side = z, "n" end
    if wear.e and 15 - x < d then d, side = 15 - x, "e" end
    if wear.w and x < d then d, side = x, "w" end
    if side == "e" or side == "w" then return phaseY + z end
    return phaseX + x
  end
  local function stoneProud(x, y, z)
    local hgt = heightAt(alongWorld(x, z), y)
    return hgt ~= nil and hgt >= CryptKit.RELIEF_THRESHOLD
  end

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

  -- depth from the nearest worn side, and the coordinate along it
  local function depth(x, z)
    local d, u = 99, x
    if wear.s and 15 - z < d then d, u = 15 - z, x end
    if wear.n and z < d then d, u = z, x end
    if wear.e and 15 - x < d then d, u = 15 - x, z end
    if wear.w and x < d then d, u = x, z end
    return d, u
  end

  local seed = S.seed
  local plinth = CryptKit.PLINTH
  local course = CryptKit.COURSE

  -- With the CRYPT-FX row on, the masonry is the PHOTOGRAPH's (the wall
  -- wears Poly Haven's rubble stone, its own joints and all -- see
  -- lib/Crypt.lua), so the drawn courses step aside: one stone class, no
  -- joints, and the picture is not ruled over with a second grid. Off,
  -- the courses are what says "ashlar". Decided at build time, which is
  -- why the row remeshes.
  local function ashlar(u, y)
    if photo then return T.stoneA end
    local yy = y - plinth - 1
    if yy % course == course - 1 then return T.joint end
    local c = floor(yy / course)
    local stagger = ((c + seed) % 2) * 8
    if (u + stagger) % 16 == 0 then return T.joint end
    local blockIx = floor((u + stagger) / 16)
    local r = hash2(c * 3 + seed, blockIx * 5 + 1)
    return STONES[1 + floor(r * 2.999)]
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

  local function at(x, y, z)
    if y < 0 then return nil end
    -- outside the cell: only a capital's overhang and the sconce live there
    if x < 0 or x > 15 or z < 0 or z > 15 then
      if capY and y >= capY and y <= capY + 1 and inPier(x, z, 1) then
        return T.trim
      end
      return lantern(x, y, z)
    end
    if y >= H then return lantern(x, y, z) end
    local d, u = depth(x, z)
    local pier = inPier(x, z)
    if d == 0 then
      -- the outermost layer: present only where the profile stands proud
      -- -- and, carved by the photograph, wherever the picture's own
      -- stones stand (the plinth and a low wall's coping stay whole)
      local proud
      if photo then
        proud = (y <= plinth) or (low and y >= H - 2) or stoneProud(x, y, z)
      else
        proud = (y <= plinth) or pier
                or (tall and (y == CryptKit.STRING or y == CryptKit.STRING + 1))
                or (low and y >= H - 2)
      end
      if not proud then return nil end
    end
    -- the profile's own dressings
    if low and y >= H - 2 then return T.trim end
    if capY and pier and y >= capY and y <= capY + 1 then return T.trim end
    if d <= 1 then
      if photo then
        -- the picture carries every dressing; the foot is the shader's
        -- damp and moss, so the class stays one stone
        return T.stoneA
      end
      if y == plinth then return T.trim end
      if y < plinth then return T.damp end
      if tall and (y == CryptKit.STRING or y == CryptKit.STRING + 1) then
        return T.trim
      end
      if pier then return T.stoneA end
      return ashlar(u, y)
    end
    -- inside: whatever looks out of a non-worn side looks into the dark
    return T.mass
  end

  -- the light: the class's own share, falling away up a tall wall
  local fadeFrom, fadeTo = CryptKit.FADE_FROM, CryptKit.FADE_TO
  local function vert(y)
    if low or y <= fadeFrom then return 1 end
    local t = (y - fadeFrom) / (H - fadeFrom)
    if t > 1 then t = 1 end
    return 1 - (1 - fadeTo) * t * t * (3 - 2 * t)
  end
  local function tint(y, i)
    local name = i and CLASS[i]
    if not name then return 1 end
    local f = CryptKit.SHADE[name] or 1
    if name == "glow" or name == "black" then return f end
    if y < CryptKit.COURSE and name ~= "trim" then f = f * CryptKit.FOOT end
    return f * vert(y)
  end

  local ytop = H - 1
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
--                band, a framed panel)
--   rows  7..10  two small posts flanking it, columns 1..2 and 13..14
--   rows 11..15  the plinth, columns 1..14 (a light top rim, a dark face,
--                a black foot)
-- A stone stands about as tall as the person walking past it (the drawing's
-- ten rows over twelve voxels, on a four-voxel plinth): taller and the
-- field reads as monoliths, and a stone in front of the player hides him
-- from the fixed camera -- the LAW every authored shot answers to.
local PLINTH_H = 4
local STONE_H = { 12, 10, 14 }
local function graveModel(sp, S)
  local off = 8
  local function pix(x, r) return (off + r) * W + x end
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
        return pix(5, 2)
      end
      if (z == 10 or z == 7) and (x == sx0 or x == sx1) and y >= H - 3 then
        return nil
      end
      if z == 10 or z == 7 then return pix(x, r) end
      return pix(4, r)
    end
    -- the posts
    if y <= PLINTH_H + 3 and z >= 7 and z <= 9
        and ((x >= 1 and x <= 2) or (x >= 13 and x <= 14)) then
      return pix(x, 7 + (PLINTH_H + 3 - y))
    end
    return nil
  end
  local function tint(y, i)
    if y < PLINTH_H then return 0.82 end
    return 1
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
  if S.kind == "w" and S.H then return wallModel(sp, S) end
  return nil, "bad signature " .. tostring(sig)
end

return CryptKit
