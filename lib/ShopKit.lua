-- Voxel world mode: the Poke Mart INSIDE, modelled as a shop.
--
-- What was here before (lib/RoomKit.lua's `case`/`rack`/`booth`/`worktop`)
-- folded the tile drawing onto a box: a display case was the picture
-- standing as the south face of a sixteen-deep slab, a shelf rack was the
-- same picture with a three-voxel sink where the goods were drawn, the
-- counter was a slab with a lip. It read as a grey box with a photograph of
-- a shop taped to the front, and it could not read as anything else: the
-- MART tileset is four greys under one flat palette, so every voxel of it
-- wears one of four values no matter how the geometry is cut.
--
-- Three things change here.
--
--   THE ATLAS. The room is built against an AUTHORED SHEET
--   (assets/shop/shop_sheet.png, written by tools/shop_sheet.py) instead of
--   the tileset, exactly as the Mart's own facade has been since the
--   `spriteBand` rebuild. One texel per voxel, real colour, and the sheet's
--   rows are banded by MATERIAL so lib/Voxel3D.lua's shop pass can pick the
--   photo detail to modulate from the texel's v alone.
--
--   THE PARTITION. Every one of the eight town Marts is the SAME 16x16 tile
--   plan -- verified, they hash identically (tools/interior_plan.py) -- so
--   the room is not eight rooms with a shared vocabulary, it is one room.
--   It is authored as ONE function of world position, `room(x, y, z)`, and
--   the templates are WINDOWS into it. A template answers with the room's
--   own voxel inside its band and with a PHANTOM (Buildings.PHANTOM:
--   occludes for the hidden-face test and the corner AO, never drawn)
--   outside it, so the three bands cull each other's faces at the seam and
--   the room emits as one piece. That is the crypt's white-seam lesson
--   (lib/CryptKit.lua) applied from the start rather than after.
--
--   THE SCALE, and it is the one that was wrong first time round. The
--   engine builds a character as a 16x16 quad with its feet at y = 0
--   (Voxel3D.casterMatrix), so a PERSON IS SIXTEEN VOXELS and one voxel is
--   about 10 cm. Every height below is a real fixture dimension divided by
--   that: a gondola is 14 (1.37 m, shorter than a person, which is what
--   makes a konbini read as open), a counter is 10, a reach-in cooler 22, a
--   ceiling 26. The first pass of this file used 40 and 48 and 56 and built
--   a cathedral with shelves in it. See assets/docs/shop/ART_DIRECTION.md.
--
-- Coordinates are the room's: x east 0..127 over the sixteen tile columns,
-- z south 0..127 over the sixteen tile rows (z grows TOWARD the camera),
-- y up from the floor. The perimeter walls stand OUTSIDE that box, because
-- the shop's floor is walkable to the map's very edge -- the clerk's own
-- cell is x 0 -- and a wall drawn inside it would stand in someone.
--
-- Nothing here is extracted from the ROM.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ShopKit = {}

local floor = math.floor

-- ------------------------------------------------------------- the sheet --
--
-- Mirror of tools/shop_sheet.py's SWATCHES. The two must agree; the kit
-- refuses to build (and Buildings falls back to RoomKit) when the PNG is
-- not the size this table was written against, which is the cheap check
-- that catches a regenerated sheet with a new layout.
ShopKit.SHEET = "assets/shop/shop_sheet.png"
ShopKit.SHEET_W, ShopKit.SHEET_H = 256, 256

local SW = {
  paint      = {  0,   0, 16, 16 },
  skirt      = { 16,   0, 16, 16 },
  cornice    = { 32,   0, 16, 16 },
  paint_dim  = { 48,   0, 16, 16 },
  ceiling    = {  0,  16, 16, 16 },
  diffuser   = { 16,  16, 16, 16 },
  housing    = { 32,  16, 16, 16 },
  vent       = { 48,  16, 16, 16 },
  steel      = {  0,  32, 16, 16 },
  board      = { 16,  32, 16, 16 },
  board_lip  = { 32,  32, 16, 16 },
  cabinet    = { 48,  32, 16, 16 },
  kick       = { 64,  32, 16, 16 },
  laminate   = {  0,  48, 16, 16 },
  counter_fr = { 16,  48, 16, 16 },
  counter_ed = { 32,  48, 16, 16 },
  glass_cool = {  0,  64, 16, 16 },
  glass_case = { 16,  64, 16, 16 },
  mullion    = { 32,  64, 16, 16 },
  glow       = { 48,  64, 16, 16 },
  sign_shop  = {  0, 128, 64, 16 },
  sign_sale  = { 64, 128, 32, 16 },
  price_rail = { 96, 128, 32, 16 },
  reg_body   = {  0, 144, 16, 16 },
  reg_screen = { 16, 144, 16, 16 },
  reg_keys   = { 32, 144, 16, 16 },
  mat        = {  0, 160, 32, 16 },
  carton     = { 32, 160, 16, 16 },
  foliage    = { 64, 160, 16, 16 },
  pot        = { 80, 160, 16, 16 },
  bin        = { 96, 160, 16, 16 },
  ext        = { 112, 160, 16, 16 },
  basket     = { 48, 160, 16, 16 },
  poster     = {  0, 176, 24, 32 },
  aisle_sign = { 24, 176, 40, 16 },
  tread      = { 64, 176, 16, 16 },
  shadow     = { 80, 176, 16, 16 },
}

-- the products grid: 8x8 faces, 32 across, starting at (0, 80)
local PROD_X, PROD_Y, PROD_CELL, PROD_COLS, PROD_N = 0, 80, 8, 32, 24

-- Emissive swatches: the fluorescent diffuser, the cooler's back glow, the
-- SALE header and the till's screen. `tint` hands these back a share the
-- room's light cannot take away, which is what makes a light read as a
-- light rather than as a pale rectangle (the street lamp's trick, see
-- lib/StreetLamps.lua).
local EMISSIVE = { diffuser = 1.30, glow = 1.18, sign_sale = 1.02,
                   reg_screen = 1.12 }

-- Not emissive -- a box of Potions does not glow -- but LIFTED. Every light
-- in this room hangs at ceiling height and every shelf board overhangs the
-- goods beneath it, so a facing two tiers down was landing at black while
-- the sheet texel behind it was a saturated label. A supermarket keeps its
-- stock legible with bounce off a pale floor and pale ceiling, and this is
-- that bounce, applied to the one class that needs it.
local PROD_LIFT = 1.18

local W = ShopKit.SHEET_W

-- A texel of swatch `name`, wrapped: (u, v) may be any integer, so a wall
-- can be indexed by world position and its grain never lines up twice.
local function tx(name, u, v)
  local s = SW[name]
  return (s[2] + (v % s[4])) * W + (s[1] + (u % s[3]))
end

-- One product face. `k` picks the product, (u, v) the texel inside its 8x8.
local function prod(k, u, v)
  k = k % PROD_N
  local cx, cy = k % PROD_COLS, floor(k / PROD_COLS)
  return (PROD_Y + cy * PROD_CELL + (v % PROD_CELL)) * W
         + (PROD_X + cx * PROD_CELL + (u % PROD_CELL))
end

-- The same face STRETCHED over a facing of (uw x vh) voxels, and flipped:
-- the drawing has its cap at row 0 and its label across rows 3-4, while a
-- box's y counts up from the shelf. Sampled 1:1 a three-voxel facing wore
-- the drawing's top-left corner -- cap and body, never the label -- which
-- is why the first render's shelves were pale. Every facing in the room
-- goes through here.
-- ...and it skips the drawing's own cap course. The face is a cap at row
-- 0, a label across rows 3-4 and body below; a two-voxel facing that
-- includes row 0 is half white, which is what a shelf of them looked like.
-- Rows 2..7 only, so every facing carries the label whatever its height.
-- ------- how tall each SKU stands
--
-- A shelf whose every facing is exactly as tall as its neighbour is a
-- BOARD WITH A PATTERN ON IT, and that is the one silhouette that reads as
-- printed rather than stocked. It is also the measurable half of "the room
-- looks square": the top of a tier was a perfectly horizontal run the whole
-- length of the fixture, three tiers to a gondola and two gondolas to the
-- room. Real stock is bottles beside boxes beside sachets, and the skyline
-- that makes is most of what says "shop" at a glance.
--
-- Indexed by the product's own cell on the sheet, so a tin of Chips is
-- short and a bottle of Lemonade is tall wherever the planogram puts them.
-- Keyed to a FRACTION of the tier's clear height rather than to voxels,
-- because the three tiers are 3, 3 and 2 voxels and an absolute height
-- would flatten the top one.
--
--   [1] height as a fraction of the tier's clear span
--   [2] neck courses -- the top of a BOTTLE, narrowed to its middle column.
--       Only spent where the facing is tall enough to have a shoulder.
local PROD_STAT = {
  [0]  = { 0.86, 1 },  -- potion, a flask
  [1]  = { 0.94, 1 },  -- super potion
  [2]  = { 1.00, 1 },  -- hyper potion
  [3]  = { 0.72, 1 },  -- antidote
  [4]  = { 0.72, 1 },  -- paralyz heal
  [5]  = { 0.78, 1 },  -- awakening
  [6]  = { 0.72, 1 },  -- burn heal
  [7]  = { 0.72, 1 },  -- ice heal
  [8]  = { 0.62, 0 },  -- poke ball, a cube in a box
  [9]  = { 0.62, 0 },  -- great ball
  [10] = { 0.62, 0 },  -- ultra ball
  [11] = { 0.90, 1 },  -- repel, an aerosol
  [12] = { 0.96, 1 },  -- super repel
  [13] = { 0.66, 0 },  -- escape rope, a coil in a carton
  [14] = { 0.58, 0 },  -- TM box, flat
  [15] = { 1.00, 1 },  -- soda, a bottle
  [16] = { 1.00, 1 },  -- lemonade
  [17] = { 1.00, 1 },  -- fresh water
  [18] = { 0.88, 0 },  -- milk, a carton: square shoulders
  [19] = { 0.46, 0 },  -- bento, a tray
  [20] = { 0.40, 0 },  -- onigiri
  [21] = { 0.55, 0 },  -- candy
  [22] = { 0.92, 0 },  -- chips, a tall light bag
  [23] = { 0.70, 0 },  -- noodles, a pot
}

-- height in voxels and neck courses for SKU `k` on a tier `span` tall.
local function prodStat(k, span)
  local st = PROD_STAT[k % PROD_N]
  if not st then return span, 0 end
  local h = floor(st[1] * span + 0.5)
  if h < 1 then h = 1 elseif h > span then h = span end
  -- a neck needs a shoulder to sit on: on a two-voxel facing it would be
  -- the whole product narrowed to one column, which reads as a nail
  local neck = (h >= 3) and st[2] or 0
  return h, neck
end

-- PRODUCTS 8, 9 and 10 are Poke, Great and Ultra, and their cells on the
-- sheet carry the BAG'S OWN SPRITE, boxed down to the facing's size
-- (tools/shop_sheet.py, load_ball). They were briefly built as voxel
-- SPHERES instead: at three voxels across a sphere is a lumpy cube, while
-- the sprite already has the lid, the belt, the button and the highlight
-- in the right places. So nothing outside this comment needs to know that
-- a ball is different from a carton, and every fixture below is plain
-- prodFit again.
local PROD_TOP = 2

-- The product's CAP course -- row 0 of its cell, the lid.
--
-- `prodFit` deliberately skips row 0 so every facing carries its label
-- whatever its height, and that is right for the face you look AT. It is
-- wrong for the face you look DOWN ON, and at 27 degrees of pitch this
-- camera looks down on every shelf in the room: the top voxel of every
-- facing was wearing a slice of the label, so a stocked tier read as rows
-- of coloured paper rather than as boxes with lids. One voxel per facing.
local function prodCap(k, u, uw)
  local su = (uw <= 1) and 4 or floor(u * PROD_CELL / uw)
  return prod(k, su, 0)
end

local function prodFit(k, u, uw, v, vh)
  local span = PROD_CELL - PROD_TOP
  local su = (uw <= 1) and 4 or floor(u * PROD_CELL / uw)
  local sv = (vh <= 1) and (PROD_TOP + 2)
             or (PROD_TOP + floor((vh - 1 - v) * span / vh))
  return prod(k, su, sv)
end

-- the emissive test, by the texel's row/column band rather than by a set:
-- one compare per lit face, and it survives a sheet whose swatches move
-- within their band
local function emissiveOf(i)
  if not i or i < 0 then return nil end
  local sx, sy = i % W, floor(i / W)
  if sy >= 16 and sy < 32 and sx >= 16 and sx < 32 then return EMISSIVE.diffuser end
  if sy >= 64 and sy < 80 and sx >= 48 and sx < 64 then return EMISSIVE.glow end
  if sy >= 128 and sy < 144 and sx >= 64 and sx < 96 then return EMISSIVE.sign_sale end
  if sy >= 144 and sy < 160 and sx >= 16 and sx < 32 then return EMISSIVE.reg_screen end
  return nil
end

-- a stable per-place hash, so "which product stands here, and how far back"
-- is a fact about the shelf rather than about the order it was built in
local function hash(a, b, c)
  return floor(((a * 73856093) + (b * 19349663) + (c * 83492791)) % 4093)
end

-- ------------------------------------------- a vocabulary that is not a box --
--
-- Nothing here is curved in the modelling sense; a voxel room cannot be.
-- These are the two shapes that stop a fixture reading as a crate, and
-- both cost faces the greedy merge was going to spend on the corner
-- anyway.

-- Inside a w x d footprint whose four corners are cut back by `r`?
local function chamfer(a, b, w, d, r)
  if r <= 0 then return true end
  local da = (a < w - 1 - a) and a or (w - 1 - a)
  local db = (b < d - 1 - b) and b or (d - 1 - b)
  return da + db >= r
end

-- Inside a disc of radius r about (ca, cb)? The half-voxel slack is what
-- makes an odd radius come out symmetric on an even-width post.
local function disc(a, b, ca, cb, r)
  local da, db = a - ca, b - cb
  return da * da + db * db <= r * r + 0.25
end

-- ------------------------------------------------------------- the plan --
--
-- Everything below is in ROOM coordinates. The numbers are the plan the
-- game ships (tools/interior_plan.py VIRIDIAN_MART), read as a shop:
--
--   z   0.. 31   the product wall: two SALE cases, four drink coolers, two
--                more SALE cases, under a lit fascia
--   z  32..111   the service run down the west side (x 0..31) and the open
--                floor; the clerk's own cell is x 0..15, z 80..95 and must
--                stay clear above ankle height
--   z  48.. 79   the two gondolas, x 64..127, two units back to back
--   z 112..127   the entrance: the mat, and the door gap at x 48..79
--
ShopKit.ROOM_W, ShopKit.ROOM_D = 128, 128

-- Five thick, not eight. Under the fixed camera a perimeter wall is seen
-- as its INNER FACE and its coping and nothing else, so thickness past
-- what holds the coping up is a slab of cubes stepping down the side of
-- the frame -- which is what the first in-game frames showed.
local WALL_D = 5
local X0, X1 = -WALL_D - 1, 127 + WALL_D + 1
local Z0, Z1 = -8, 127 + WALL_D + 1

local DOOR_X0, DOOR_X1 = 48, 79    -- the warp is cells 3 and 4, exactly

-- ------- the dollhouse cut
--
-- The camera is fixed, south of the room and looking down at 27 degrees
-- (assets/docs/shop/ART_DIRECTION.md derives the shot). At that pitch one
-- voxel of height hides 1.96 world px of floor behind it -- an eighth of a
-- cell per voxel -- so the room has to be cut away toward the camera or it
-- hides itself. Same shape as lib/Crypt.lua's `heightFor`: a tall band at
-- the back, a ramp, a sill at the front.
ShopKit.CEIL = 26                  -- the implied ceiling; never drawn
ShopKit.SILL = 5                   -- the south lip the camera looks over
-- cy 6 is 10 rather than the 8 the art direction first derived: 8 is
-- shorter than the counter that stands in it, and the cut ate the
-- checkout's own worktop and left a blue box (second headless render).
-- 10 hides 20 px of floor behind the counter -- a cell and a quarter,
-- which is the counter's own footprint.
ShopKit.BANDS = { [3] = 22, [4] = 17, [5] = 12, [6] = 10, [7] = 5 }

local CEIL, SILL, BANDS = ShopKit.CEIL, ShopKit.SILL, ShopKit.BANDS

local function capRow(cy)
  if cy <= 2 then return CEIL end
  return BANDS[cy] or SILL
end

-- Stepped per CELL ROW, not ramped between cell centres. The crypt ramps
-- because its wall is stone all the way up and a stair down its flank reads
-- as a stair; a shop's wall carries a two-course CORNICE, and under a ramp
-- that cornice traced the slope and corrugated every wall in the room
-- (visible in the first headless render). A step that lands on a cell
-- boundary reads as a cutaway, which is what it is.
local function capAt(z)
  return capRow(floor(z / 16))
end

ShopKit.capAt = capAt

-- ------- surfaces

-- A wall course, with a PROFILE rather than a flat slab. `d` is how far
-- this voxel is from the wall's room-facing face, so the skirting and the
-- cornice can stand proud of a face that steps back between them -- which
-- is what an actual wall does, and the cheapest possible thing that stops
-- a wall reading as a rectangle of paint. The coping (the last course)
-- steps back on BOTH faces, so the dollhouse cut reads as a moulded edge
-- instead of a sawn one.
-- The coping's own joint pitch: a course of capping every metre and a
-- half, which is what a real one is laid in.
local COPE_PITCH = 15

local function wallVox(u, y, top, dim, d)
  d = d or 1
  if y >= top then return nil end
  if y == top - 1 then
    if d < 1 then return nil end
    -- THE COPING, and it is the largest single surface in the frame.
    --
    -- The dollhouse cut saws every perimeter wall off at its cap, and this
    -- camera looks down, so what it mostly sees of "the back wall" is the
    -- five-voxel-wide TOP of it running the full 128 across. It was one
    -- unbroken course of cornice: the biggest flat area in the room after
    -- the floor, on a surface that does not exist in a real shop at all.
    --
    -- Two lines fix that without pretending the cut is not there. A JOINT
    -- every COPE_PITCH turns the slab into laid capping, and a NOSING on
    -- the outermost course gives the cap an arris to catch the light --
    -- which is what makes a coping read as a coping and not as a cut.
    if u % COPE_PITCH == 0 then return tx("paint_dim", u, y) end
    if d >= WALL_D - 1 then return tx("counter_ed", u, y) end
    return tx("cornice", u, y)
  end
  if y >= top - 3 then return tx("cornice", u, y) end
  if y <= 1 then return tx("skirt", u, y) end
  -- PILASTERS, and they are the dollhouse cut's problem as much as the
  -- wall's. The perimeter is one recessed face from end to end, and the
  -- cut saws it into steps -- so every step shows that same blank panel,
  -- five of them down each side, each one a plain white rectangle with a
  -- capping on top. A pier every 24 (2.4 m, a structural bay) brings the
  -- wall forward to its full depth and gives the run a rhythm the steps
  -- then cut ACROSS instead of merely repeating.
  local pier = (u % 24) < 3
  -- ...and a BAND COURSE at mid height, which is the other thing a long
  -- wall has. It sits below every one of the cut's steps except the
  -- lowest, so it reads as one continuous line behind them all -- which
  -- is exactly what ties five separated panels back into one wall.
  if y == 11 then return tx("cornice", u, y) end
  if d < 1 and not pier then return nil end    -- the face, stepped back
  return tx(dim and "paint_dim" or "paint", u, y)
end

-- the north wall. Thick on purpose: the product wall's cabinets stand in
-- the last twelve voxels of the four non-walkable tile rows, and filling
-- everything behind them with wall is both cheaper than a cavity (no inner
-- faces to cull) and stops the band reading as walkable floor.
local NWALL_Z1 = 19

-- The fascia: POKE MART across the wall above the drinks bay.
--
-- The interior carried NO BRAND MARK AT ALL -- measured, the Mart's blue
-- was about 2 % of the frame and there was no sign anywhere -- while
-- `sign_shop` had been drawn into the sheet from the first build and never
-- placed once. It goes in the WALL'S OWN PLANE, two voxels proud, which is
-- the one fixture in this room that costs nothing: at 27 degrees a header
-- standing on the wall hides only the wall behind it, and the cut already
-- takes the ceiling that would have carried a hanging sign.
--
-- y 22..25 is the band the cooler (COOL_TOP 22) leaves clear under the
-- cornice, and four voxels is 40 cm -- a real fascia. The art is sixteen
-- rows, sampled at 14 / 9 / 5 / 1.
--
-- FLIPPED, and it shipped wrong once: the drawing has row 0 at its TOP and
-- a voxel counts y UP from the floor, so the straight order put the red
-- rule above and the blue field below -- the sign upside down. This is the
-- same trap `prodFit` carries a paragraph about; it is worth a second one.
local SIGN_X0, SIGN_X1 = 34, 93
local SIGN_Y0, SIGN_ROWS = 22, { 14, 9, 5, 1 }

-- What ELSE lives on the visible band of the back wall.
--
-- The cooler tops out at 22 and the ceiling is at 26, so four courses of
-- wall show above the product run across the room's whole width -- and the
-- fascia only claims x 34..93 of it. The rest was blank cornice, which at
-- this camera is a pale strip 128 voxels long.
--
-- A RETURN-AIR GRILLE either side of the fascia and a CATEGORY SIGN over
-- the SALE cases. Both are canon konbini fittings, both live in the wall's
-- own plane so they cost no occlusion at all, and both have been drawn
-- into the sheet since the first build without ever being placed.
local VENT_Y0 = 22

local function backWallArt(x, y)
  if y < VENT_Y0 or y > VENT_Y0 + 3 then return nil end
  -- the grilles, flanking the fascia
  if (x >= 8 and x <= 23) or (x >= 104 and x <= 119) then
    return tx("vent", x, y - VENT_Y0 + 4)
  end
  -- A BANDEAU: one course of the Mart's blue running the wall's whole
  -- width, at the height the product run tops out.
  --
  -- Six-voxel `aisle_sign` plaques were tried in the gaps first and read
  -- as loose blue squares -- at this distance a sign has to be either
  -- legible or continuous, and six voxels is neither. A band is
  -- continuous, ties the fascia to the counter's own blue, and is what
  -- every fitted shop actually runs above its shelving.
  if y == VENT_Y0 then return tx("counter_fr", x, 3) end
  return nil
end

local function north(x, y, z)
  if z > NWALL_Z1 then return nil end
  if z >= NWALL_Z1 - 1 then
    if y >= SIGN_Y0 and y <= SIGN_Y0 + 3
       and x >= SIGN_X0 and x <= SIGN_X1 then
      return tx("sign_shop", x - SIGN_X0, SIGN_ROWS[y - SIGN_Y0 + 1])
    end
    local a = backWallArt(x, y)
    if a then return a end
  end
  return wallVox(x * 3 + z, y, CEIL, z >= 12, NWALL_Z1 - z)
end

-- the invented side and south walls
local function shell(x, y, z)
  if x < 0 then
    if x < -WALL_D then return nil end
    return wallVox(z, y, capAt(z), false, -1 - x)
  end
  if x >= ShopKit.ROOM_W then
    if x >= ShopKit.ROOM_W + WALL_D then return nil end
    return wallVox(z, y, capAt(z), false, x - ShopKit.ROOM_W)
  end
  if z >= 128 then
    if z >= 128 + WALL_D then return nil end
    if x >= DOOR_X0 and x <= DOOR_X1 then return nil end
    return wallVox(x, y, capAt(z), false, z - 128)
  end
  return nil
end

-- ------- the product wall (z 20..31)

local CAB_Z0, CAB_Z1 = 20, 31      -- twelve deep, standing on the wall
local CASE_TOP, COOL_TOP = 20, 22

-- A SALE display case. What sells it is not the stock in front, it is the
-- LIT RECESS: the drawing's own black niche (tiles 76/77) sunk four voxels
-- with its back face glowing, six boxes standing in it, and the red header
-- above.
local function saleCase(x, y, z)
  if y >= CASE_TOP then return nil end
  -- the run's own four vertical corners, cut back two. Only the run's:
  -- chamfering each unit would notch the joint where two cabinets meet.
  if not chamfer(x, z - CAB_Z0, 128, 12, 2) then return nil end
  -- and the top front edge, nosed
  if y >= CASE_TOP - 1 and z >= CAB_Z1 then return nil end
  local u = x % 32
  if y >= 16 then                                  -- the header
    if y == CASE_TOP - 1 then return tx("cabinet", x, z) end
    return tx("sign_sale", x, y - 16 + 4)
  end
  if y <= 2 then                                   -- the kick, set back two
    if z < CAB_Z0 + 2 then return nil end
    return tx("kick", x, y)
  end
  -- the niche: four voxels deep, inside a two-voxel frame
  local inFace = (u >= 2 and u <= 29 and y >= 5 and y <= 14)
  if z >= CAB_Z1 - 3 then
    if not inFace then return tx("cabinet", x, z) end
    -- six boxes, 3 wide x 4 tall x 3 deep, two voxels apart
    local f = floor((u - 2) / 5)
    if (u - 2) % 5 < 3 and y >= 6 and y <= 13 and z >= CAB_Z1 - 2 then
      local tier = (y <= 9) and 0 or 1
      if (y - 6) % 4 < 3 then
        -- A BALL in every niche slot -- this is the display case, the one
        -- fixture whose entire job is to show a single thing off, so its
        -- SKU is FORCED into the three ball lines rather than left to the
        -- hash. Cartons belong on the gondolas, not in the lit recess.
        local kk = 8 + hash(f, tier, 3) % 3
        if (y - 6) % 4 == 2 then return prodCap(kk, (u - 2) % 3, 3) end
        return prodFit(kk, (u - 2) % 3, 3, (y - 6) % 4, 3)
      end
    end
    return nil
  end
  if z == CAB_Z1 - 4 and inFace then
    return tx("glow", x, y)                        -- the lit back of the niche
  end
  return tx("cabinet", x, z)
end

-- A glass-door reach-in cooler. The cabinet interior is LIT, not black: a
-- reach-in is lit from inside, and that is what makes the drinks wall the
-- brightest object in the room, which is what makes the room read as a
-- konbini. Only the shelf nearest eye height carries modelled bottles; the
-- others are one-voxel colour cards, which behind glass at eight voxels'
-- depth is indistinguishable and costs a fortieth of the voxels.
local function cooler(x, y, z)
  if y >= COOL_TOP then return nil end
  if not chamfer(x, z - CAB_Z0, 128, 12, 2) then return nil end
  if y >= COOL_TOP - 1 and z >= CAB_Z1 then return nil end
  local u = x % 8                                  -- one reach-in door
  if y >= 19 then                                  -- the header band
    if z >= CAB_Z1 - 1 then return tx("diffuser", x, y) end
    return tx("cabinet", x, z)
  end
  if y <= 2 then
    if z < CAB_Z0 + 2 then return nil end
    return tx("kick", x, y)
  end
  local frame = (u == 0 or y == 3 or y == 18)
  if z >= CAB_Z1 - 1 then
    if frame then return tx("mullion", x, y) end
    -- THE HANDLE, and it is the one detail at this scale that says "door"
    -- and not "window": a full-height pull on a boss at each end, so the
    -- door reads as something a hand opens rather than as a pane of glass
    -- set in a hole.
    --
    -- IT HAS NEVER EXISTED. It was written under `z > CAB_Z1`, and
    -- CAB_Z1 is 31 while `room` only ever calls this function for z 20..31
    -- -- so the branch was unreachable from the first build, which is why
    -- adding to it did not change the face count by one. It belongs HERE,
    -- inside the door opening, where z 30 and 31 are otherwise air.
    if u == 6 and y >= 6 and y <= 16 then
      if z == CAB_Z1 then return tx("mullion", x, y) end
      if y == 6 or y == 16 then return tx("mullion", x, y) end
    end
    return nil                                     -- the opening
  end
  if z == CAB_Z1 - 2 then
    if frame then return tx("mullion", x, y) end
    -- THE PANE IS MOSTLY A HOLE, and it has to be.
    --
    -- This shader has no transparency: `glass_cool` is an opaque albedo
    -- with a Fresnel term laid over it (see the CRYPT_MATS branch in
    -- lib/Voxel3D.lua), and the sheet's own alpha is 255 everywhere. So a
    -- full pane is a wall. The drinks were moved forward to the shelf lip
    -- precisely so they could be seen, and then sat two voxels behind
    -- solid blue -- the widest fixture in the room measuring as flat
    -- #AAC0C8 all over again, for a different reason than the first time.
    --
    -- What a reach-in door reads as at this size is a bright FRAME, the
    -- ceiling battens reflected in it, and the stock behind them. So the
    -- pane keeps only the parts that carry light and drops the rest:
    --
    --   y 4, 17   the door's own top and bottom rail
    --   y 11, 15  the two battens, reflected -- the single thing that
    --             makes a pane read as glass and not as plastic
    --   y 5       the shelf-edge price strip every chiller carries
    --
    -- Everything between is open, and what shows through it is the
    -- cabinet this fixture exists to display.
    if y == 15 or y == 11 then return tx("glass_case", x, y) end
    if y == 5 then return tx("price_rail", x, 1) end
    if y == 4 or y == 17 then return tx("glass_cool", x, y) end
    return nil
  end
  if z >= CAB_Z0 + 1 then
    if frame then return tx("cabinet", x, z) end
    if z == CAB_Z0 + 1 then return tx("glow", x, y) end
    -- the eye-height shelf: real bottles, 2 wide x 3 tall x 2 deep
    if y >= 9 and y <= 12 and z >= CAB_Z1 - 5 and z <= CAB_Z1 - 4 then
      if u % 3 ~= 2 and y <= 11 then
        local kk = 15 + hash(floor(x / 3), 1, 7)
        if y == 11 then return prodCap(kk, u % 2, 2) end
        return prodFit(kk, u % 2, 2, y - 9, 3)
      end
      return nil
    end
    for _, sy in ipairs({ 4, 8, 12, 16 }) do
      if y == sy then return tx("board", x, z) end
      -- the other tiers: a one-voxel card of colour against the glow.
      -- AT THE FRONT OF THE SHELF, not the back. These stood at
      -- CAB_Z0 + 2 -- seven voxels behind the pane, through tinted glass,
      -- which is far enough that the widest fixture in the room measured
      -- as flat #AAC0C8 at saturation 0.15: a drinks wall with nothing in
      -- it. A reach-in is faced forward anyway; stock sits at the shelf
      -- lip and the empty space is BEHIND it, where nothing can see it.
      if y > sy and y < sy + 4 and z == CAB_Z1 - 4 then
        return prodFit(hash(floor(x / 5), sy, 9), x % 5, 5, y - sy - 1, 3)
      end
    end
    return nil
  end
  return tx("cabinet", x, z)
end

-- ------- the service run (x 0..31, z 32..111)

local CTOP = 10                    -- the counter's top face, 0.96 m

-- Is this column part of the counter's L? The clerk's own cell (x 0..15,
-- z 80..95) is deliberately not: he is an NPC the game walks, and a counter
-- drawn through him is a counter drawn through him.
local function onCounter(x, z)
  if x < 0 or x > 31 then return false end
  if z >= 32 and z <= 47 then return true end            -- the north cap
  if z >= 96 and z <= 111 then return true end           -- the south cap
  return x >= 16 and z >= 48 and z <= 95                 -- the run
end

local function counter(x, y, z)
  if not onCounter(x, z) or y >= CTOP then return nil end
  if y >= CTOP - 2 then
    -- the worktop's NOSE: the last course is cut back one voxel on every
    -- edge that faces the room, so the top reads as a rolled edge over an
    -- overhanging slab rather than as the lid of a box
    if y == CTOP - 1 and (x >= 31 or z >= 111 or z <= 32) then return nil end
    -- ...and its SEAMS. A four-metre laminate top is not one sheet, and
    -- the unbroken slab was the second largest flat surface in the room.
    -- Every 28 along the run -- two counter modules, which is where a
    -- fabricator would actually put the joint.
    if y == CTOP - 1 and (x + z) % 28 == 0 then return tx("counter_ed", x, z) end
    return tx("laminate", x, z)
  end
  if y <= 1 then                                         -- the toe kick
    if x <= 17 and z >= 48 and z <= 95 then return nil end
    if x >= 30 or z >= 110 or z <= 33 then return nil end
    return tx("kick", x, z)
  end
  if y == CTOP - 3 and (x == 31 or z == 111 or z == 32) then
    return tx("counter_ed", x, y)                        -- the edge band
  end
  -- ------- the front, PANELLED
  --
  -- A shop counter is not a slab. It is a run of modules about 90 cm wide,
  -- each one a panel set back inside a proud stile with a pull rail over
  -- it; ours was a single unbroken face of blue sixty-four voxels long,
  -- which after the floor was the largest flat surface in the room.
  --
  -- `s = x + z` is the distance ALONG the run whichever way the run points.
  -- The counter is an L: on the north-south leg x is fixed and z moves, on
  -- the two caps z is fixed and x moves, so neither coordinate alone can
  -- measure it and their sum can. It is also the coordinate the texel
  -- lookup already used, so the grain and the joinery agree by
  -- construction.
  local s = x + z
  local m = s % 14
  -- the stile between two modules, full height and flush with the face
  if m == 0 or m == 13 then return tx("counter_ed", s, y) end
  -- the pull rail across the top of each panel
  if y == CTOP - 3 then return tx("mullion", s, y) end
  -- The panel is drawn, NOT carved. Setting it back one voxel was tried
  -- first and is what a real counter does; at this room's occlusion
  -- (Shop.AO.power 0.95, and the sun pass on top of it) a one-voxel recess
  -- four courses tall goes far enough into shadow to read as a HOLE, and
  -- the counter came back as a worktop standing on legs with daylight
  -- under it. The stiles that were meant to frame the panels became the
  -- legs. A drawn frame gives the same joinery with no cavity to fill
  -- with shadow.
  -- ...and the frame is ONE course, not four. Framing the panel on all
  -- sides (m 1 and 12, y 3 and 6) left the blue field as a strip two
  -- voxels tall inside a pale surround, which inverted the counter: the
  -- Mart's blue went from the thing you see to a stripe on a white box.
  -- The stiles already separate the modules; the panel needs a shadow
  -- line under its rail and nothing else.
  if y == CTOP - 4 then return tx("counter_ed", s, y) end
  return tx("counter_fr", s, y)
end

-- The back fixture: the wall unit behind the counter, four shelves of
-- stock. It stops at z 79 so the clerk's cell stays open.
local function backFixture(x, y, z)
  if x > 9 or z < 48 or z > 79 or y >= 20 then return nil end
  -- NO CAP over the top tier. This run stands directly behind the till,
  -- which is the one spot a player is guaranteed to walk up to, and its
  -- two closing courses of `cabinet` were a pale slab ten voxels deep and
  -- thirty-two long lying flat under a camera that looks down -- the
  -- single largest thing in that corner of the frame, and it read as the
  -- lid of a chest freezer. Same rule the gondola has carried in this file
  -- all along, and the same one the two wall runs had to learn: at 27
  -- degrees a board across a fixture's top hides the fixture.
  if y <= 1 then return tx("kick", x, z) end
  if x >= 8 then return tx("cabinet", x, y) end          -- the carcass side
  for _, sy in ipairs({ 2, 7, 12, 17 }) do
    if y == sy then return tx("board", x, z) end
    if y > sy and y < sy + 5 then
      local f = floor((z - 48) / 4)
      if (z - 48) % 4 < 3 then
        return prodFit(hash(f, sy, 11), (z - 48) % 3, 3, y - sy - 1, 4)
      end
      return nil
    end
  end
  return nil
end

-- ------- the gondolas (two units, x 64..95 and 96..127)
--
-- Fourteen tall, twelve deep, CENTRED in a footprint that is thirty-two:
-- the plan's two cells are the fixture plus the aisle either side of it,
-- and a gondola built out to its claimed tiles is a wall.
local GTOP, GZ0, GZ1 = 14, 58, 69

-- Boards at y2, y6 and y10; three tiers of facings between them; the top
-- cap at y13 with a price rail one voxel proud on both faces.
-- ------- the east wall's run
--
-- The room's two long walls were doing very different amounts of work. The
-- WEST one is full: the counter's L, the `backFixture` shelving behind it
-- at z 48..79, and the clerk's own cell at z 80..95, which the plan says
-- must stay clear above ankle height. The EAST one carried a gondola end
-- at z 57..70 and nothing else -- two runs of bare wall, sixteen cells
-- long between them, in a shop. Every convenience store in the world
-- shelves every wall it has; that is what perimeter shelving IS.
--
-- Two sections, because the gondola sits between them, and each is capped
-- by its own row:
--
--   z 33..46   cy 2, cap 26. Built to 17, and the number is forced from
--              BOTH sides. It must clear the GONDOLA, which stands 14 tall
--              at z 57..70 directly in front of it and, at k = 0.511, hides
--              everything on screen above z 57 - 14/k = 30 -- so at the
--              gondola's own 14 this run showed nothing but its top course
--              and read as a grey cabinet (measured: first build). 17 puts
--              its top at 46 - 17/k = 13, well clear. And it must not
--              swallow the SALE cases behind it, which cover -8..31: at 17
--              it takes their bottom nine voxels, which is kick and one
--              facing; at the cap's 26 it would have taken all of them.
--   z 81..94   cy 5, cap 12. Built to 11.
--
-- The carcass goes against the WALL and the boards open into the room --
-- which is what perimeter shelving is, and which is NOT what `backFixture`
-- does on the west side. Mirroring that one literally put a solid two-voxel
-- carcass down the run's whole 17-voxel face, straight at the camera, and
-- the fixture came back as a grey cabinet with a shelf peeking out from
-- behind it. The west run gets away with it because it stands at x 0..9
-- against a camera at x 64 -- it is seen so far from the side that only its
-- top course reads. Nothing at x 118 is.
local EAST_X0 = 118

local function eastShelf(x, y, z)
  if x < EAST_X0 or x > 127 then return nil end
  local top
  if z >= 33 and z <= 46 then top = 17
  elseif z >= 81 and z <= 94 then top = 11
  else return nil end
  if y >= top then return nil end
  -- NO CAP AT ALL over the top tier, which is the rule the gondola already
  -- carries in this file: at 27 degrees the camera looks down INTO a
  -- fixture, so a board across its top is the one surface that hides the
  -- whole thing. This run shipped with two courses of cornice and then one,
  -- and both read as a closed grey cabinet with a shelf peeking out from
  -- under it. The top tier is open and short goods stand on it.
  if y <= 1 then return tx("kick", x, z) end
  -- the back panel, hard against the east wall
  if x >= 126 then return tx("cabinet", x, y) end
  local u = x - EAST_X0                        -- 0..7 across the boards
  for _, sy in ipairs({ 2, 6, 10, 14 }) do
    if sy >= top then break end
    if y == sy then return tx("board", x, z) end
    if y > sy and y < sy + 4 then
      local f = floor((z - 32) / 4)
      if (z - 32) % 4 >= 3 then return nil end
      local k = hash(f, sy, 13)
      -- the goods are faced to the FRONT of the board, with the empty
      -- depth behind them where nothing can see it -- the same rule the
      -- cooler learned when its stock was found seven voxels back
      if u > 5 then return nil end
      local h = y - sy
      if y == sy + 3 then return prodCap(k, (z - 32) % 3, 3) end
      return prodFit(k, (z - 32) % 3, 3, h - 1, 3)
    end
  end
  return nil
end

-- ------- the west wall, over the counter
--
-- The west wall has no bare stretch to shelve: the counter's L owns z
-- 32..47 and z 96..111 outright, `backFixture` stands at z 48..79, and z
-- 80..95 is the CLERK's own cell, which the plan requires to stay clear
-- above ankle height -- a sprite stands in it. What it does have is AIR:
-- the counter tops out at CTOP 10 and cy 2's cap is 26, so there are
-- sixteen voxels of nothing over the north cap.
--
-- That is where a konbini puts its back-bar -- the shelf behind the till,
-- which is a real and very canonical fixture. Six deep and eight tall,
-- and both numbers are the occlusion talking rather than taste: at k =
-- 0.511 a run topping out at 18 at z 46 hides the floor back to z 11, and
-- the SALE case behind it covers -8..31 on the same scale, so this takes
-- its kick and its bottom facing and stops. Two more courses of height, or
-- two more of depth in x, and it would start eating the case itself.
local WEST_X1 = 5
local WEST_Y0, WEST_TOP = 11, 18

local function westShelf(x, y, z)
  if x < 0 or x > WEST_X1 then return nil end
  if z < 33 or z > 46 then return nil end
  if y < WEST_Y0 or y >= WEST_TOP then return nil end
  -- the back panel against the wall, and the two boards
  if x <= 1 then return tx("cabinet", x, y) end
  for _, sy in ipairs({ WEST_Y0, WEST_Y0 + 4 }) do
    if y == sy then return tx("board", x, z) end
    if y > sy and y < sy + 4 then
      if (z - 32) % 4 >= 3 then return nil end
      local k = hash(floor((z - 32) / 4), sy, 17)
      -- faced to the front, like every other run in the room
      if x > 4 then return nil end
      if y == sy + 3 then return prodCap(k, (z - 32) % 3, 3) end
      return prodFit(k, (z - 32) % 3, 3, y - sy - 1, 3)
    end
  end
  return nil
end

local BOARDS = { 2, 6, 10 }

local function gondola(x, y, z)
  if x < 64 or z < GZ0 - 1 or z > GZ1 + 1 or y >= GTOP then return nil end
  local x0 = (x < 96) and 64 or 96
  local u = x - x0
  -- the price rails, one voxel proud of each face
  if z == GZ0 - 1 or z == GZ1 + 1 then
    for _, b in ipairs(BOARDS) do
      -- row 5 of the swatch is where the ticket marks are; row 1 is the
      -- blank strip it was reading before, which made the busiest edge in
      -- the room a plain white line
      if y == b then return tx("price_rail", u, 5) end
      -- and the strip UNDER it: a lit lip over each tier. Real fitouts
      -- have these, and it is what makes the goods on a lower shelf
      -- readable at all under a fixture that hangs at the ceiling.
      if b > 2 and y == b - 1 then return tx("diffuser", u, 8) end
    end
    if y == 13 then return tx("price_rail", u, 4) end
    return nil
  end
  if y <= 1 then                                         -- kick and deck
    if y == 1 then return tx("board", x, z) end
    if z <= GZ0 + 1 or z >= GZ1 - 1 then return nil end
    return tx("kick", x, z)
  end
  -- the uprights: a ROUND slotted post at each end of each unit, front and
  -- back. Square posts at the four corners of a rack are what made the
  -- first pass read as scaffolding.
  if (u <= 2 or u >= 29) and (z <= GZ0 + 2 or z >= GZ1 - 2) then
    local cu = (u <= 2) and 1 or 30
    local cz = (z <= GZ0 + 2) and (GZ0 + 1) or (GZ1 - 1)
    if disc(u, z, cu, cz, 1.4) then return tx("steel", x, y) end
    return nil
  end
  -- ...and an upright at every BAY. A 3.2 m gondola is not two posts and a
  -- span: it is a run of bays about 90 cm wide, each with its own slotted
  -- upright, and those uprights are most of what stops a tier reading as
  -- one continuous ribbon of packaging 64 voxels long. Ours had posts at
  -- the four corners and nothing between them.
  --
  -- These only ADD -- unlike the corner posts they never return nil,
  -- because rounding a corner off in the MIDDLE of the run would notch a
  -- bite out of the shelf either side of every bay.
  for _, cu in ipairs({ 10, 21 }) do
    if u >= cu - 2 and u <= cu + 2
       and (z <= GZ0 + 2 or z >= GZ1 - 2) then
      local cz = (z <= GZ0 + 2) and (GZ0 + 1) or (GZ1 - 1)
      if disc(u, z, cu, cz, 1.8) then return tx("steel", x, y) end
    end
  end
  for _, b in ipairs(BOARDS) do
    -- a board's ends are cut back one, so a shelf reads as a shelf between
    -- two posts rather than as a slab welded across them
    if y == b then
      if u == 0 or u == 31 then return nil end
      -- the board stops one short of the fixture's own face, so the goods
      -- on the tier BELOW stand proud of the shelf above them and catch
      -- the light instead of sitting in its shadow. That overhang is what
      -- put the bottom tier at black in the first two in-game runs, and it
      -- is also what a real gondola does -- the base deck is deeper than
      -- the shelves above it.
      if z <= GZ0 or z >= GZ1 then return nil end
      return tx("board", x, z)
    end
  end
  -- the facings. Eight to a tier (3 wide, 1 of gap), in runs of three
  -- before the SKU changes -- a real planogram repeats a line two to four
  -- times, and one facing per line reads as confetti -- and each facing
  -- set back off its own hash, which is the single cheapest thing that
  -- stops a shelf reading as a printed board with a bevel.
  -- The top tier has NO cap over it. At 27 degrees the camera looks down
  -- INTO a 1.4 m fixture, and a board across its top is the one surface
  -- that hides the whole shelf -- the first render's gondolas were two
  -- white slabs for exactly this reason. Short goods up there (the konbini
  -- habit) and the sightline stays open over the unit.
  local tier = (y < 6) and 0 or ((y < 10) and 1 or 2)
  local top = (tier == 0) and 5 or ((tier == 1) and 9 or 12)
  local base = BOARDS[tier + 1] + 1
  if y < base or y > top then return nil end
  local span = top - base + 1
  -- Three of product and one of air, and the gap EARNS its voxel. Filling
  -- it was tried -- real stock is faced up until it touches, and it puts a
  -- third more product on the shelf -- and it made the tier worse: with
  -- the SKU changing only every third facing, four touching facings of the
  -- same height and colour merged into one continuous stripe and the shelf
  -- stopped reading as separate items at all. The gap is what separates
  -- them at this size. Density comes from the run length below instead.
  local f = floor(u / 4)
  if u % 4 >= 3 then return nil end
  local rank = (z <= (GZ0 + GZ1) / 2) and 0 or 1
  local jit = hash(x0 + f, tier, rank) % 3
  local near, far
  -- The jitter goes on the BACK of the facing, never the front. Set on the
  -- front it cut a notch up to three voxels deep between the shelf rail
  -- and the goods, and at 27 degrees the camera looks straight down into
  -- that notch -- with every light in the room at ceiling height and a
  -- board over it, the notch renders black. In game that read as a dark
  -- band with white rails in it, running the length of the fixture
  -- (probe_out_shop, runs 2 and 3). Flush at the face, varied at the back:
  -- the depth still varies, and it is the box TOPS that show it, which is
  -- the face this camera sees anyway.
  if rank == 0 then
    near, far = GZ0, GZ0 + 2 + jit
  else
    near, far = GZ1 - 2 - jit, GZ1
  end
  if z < near or z > far then return nil end
  -- The run: how many facings a line holds before the SKU changes. Two,
  -- not three -- a real planogram repeats a line two to four times, and
  -- three at this scale put twelve voxels of one colour and one height in
  -- a row, which is the stripe the gap then had to break up on its own.
  local k = hash(x0 + floor(f / 2), tier, rank)
  -- and the SKU's own stature, which is what breaks the tier's skyline
  local h, neck = prodStat(k, span)
  if y > base + h - 1 then return nil end
  -- the bottle's neck: the top course keeps only its middle column, so the
  -- shoulder is a real step and not a bevel painted on a slab
  if neck > 0 and y > base + h - 1 - neck and (u % 3) ~= 1 then return nil end
  -- The three BALL lines are drawn as balls rather than as cartons with a
  -- ball printed on them. PRODUCTS 8..10 are Poke, Great and Ultra, and
  -- their stature is 0.62 of the tier, which on a three-voxel tier is
  -- exactly the two courses a small ball wants -- so the facing they were
  -- already getting is the right box to put a sphere in. About an eighth
  -- of the shelf comes up a ball, which is roughly what a Mart's
  -- planogram would give them.
  if y == base + h - 1 then return prodCap(k, u % 3, 3) end
  return prodFit(k, u % 3, 3, y - base, h)
end

-- ------- the light fixtures
--
-- A pool of light with nothing over it is the failure lib/Crypt.lua names
-- in its own header, so every one of the scene's eight sites carries
-- geometry. WHERE it can carry it is decided by the cut: at 27 degrees a
-- ceiling panel only survives where the cap is the full 26, which is the
-- back three cell rows. Further south the fixture moves onto the SIDE WALL
-- as a batten under that row's own cornice -- always visible, at the edges
-- of the frame where it hides nothing, and a real shop fitting rather than
-- a compromise.
--
-- 4 voxels deep, 12 long, 2 tall, long axis east-west along the aisles.
ShopKit.PANELS = {                 -- ceiling panels: { x0, z0 }, y 23..24
  { 16, 36 }, { 52, 36 }, { 100, 36 },
}
ShopKit.BATTENS = {                -- wall battens: { side, z0 }, 12 long
  { "w", 52 }, { "e", 52 }, { "w", 84 }, { "e", 84 },
}

-- A CEILING BULKHEAD across the room, and the reason it is a beam rather
-- than a ceiling.
--
-- The room has no top at all, which is most of what reads as "model on a
-- table" -- but a ceiling is useless at this camera: the eye is at y 104
-- looking DOWN, so it would see the slab's upper face and never its
-- underside. What it can see is the beam's SOUTH FACE, stood on edge, and
-- that is what tells you there is a roof over this.
--
-- Placed as far north as it can be and still be seen, because a bulkhead
-- hides whatever is behind it: at k = 0.511 a face at height y and depth z
-- lands on screen where the floor at z - y/k does. The beam's south face
-- (z 35, y 23..25) covers -14..-10 on that scale; the cooler wall's own
-- face (z 31, y 0..22) covers -12..20. The overlap is one voxel of the
-- cooler's top course, and nothing else in the room reaches it.
local BEAM_Z0, BEAM_Z1 = 32, 35
local BEAM_Y0, BEAM_Y1 = 23, 25

local function beam(x, y, z)
  if y < BEAM_Y0 or y > BEAM_Y1 then return nil end
  if z < BEAM_Z0 or z > BEAM_Z1 then return nil end
  if x < 0 or x >= ShopKit.ROOM_W then return nil end
  -- a continuous strip light let into its south face: one run of light
  -- across the whole room, which is what a shop's ceiling actually is and
  -- what the three separate panels below could never read as
  -- ITS TOP is a ceiling, and the camera sees it. `ceiling` has been in
  -- the sheet since the first build and never placed; this is the one
  -- surface in the room that is actually a ceiling panel.
  if y == BEAM_Y1 then return tx("ceiling", x, z) end
  local m = x % 32
  if z == BEAM_Z1 then
    -- the module joint: a bulkhead this long is built in bays, and one
    -- unbroken 128-voxel face is the same mistake the counter made
    if m == 0 then return tx("housing", x, y) end
    -- an air grille in the middle of every second bay, which is where a
    -- shopfitter puts one because that is where the duct already is
    if m >= 12 and m <= 19 and floor(x / 32) % 2 == 1 then
      return tx("vent", x, y - BEAM_Y0 + 4)
    end
    if y == BEAM_Y0 + 1 then return tx("diffuser", x, 8) end
    -- the south face is the DIM paint, not the cornice: a bulkhead in the
    -- same white as the wall behind it is not a bulkhead, it is a smudge.
    -- Only its bottom arris keeps the cornice, as a nosing.
    if y == BEAM_Y0 then return tx("cornice", x, y) end
    return tx("paint_dim", x, y)
  end
  return tx("paint", x + z, y)
end

local function fixtures(x, y, z)
  for _, p in ipairs(ShopKit.PANELS) do
    if x >= p[1] and x < p[1] + 12 and z >= p[2] and z < p[2] + 4 then
      if y == 25 and (x == p[1] + 2 or x == p[1] + 9) then
        return tx("steel", x, y)                    -- the two stems
      end
      if y < 23 or y > 24 then return nil end
      if not chamfer(x - p[1], z - p[2], 12, 4, 1) then return nil end
      -- a steel rim one voxel all round, the rest diffuser: the face the
      -- camera sees is the SOUTH one, so that is where the light goes
      if y == 24 or z == p[2] or x == p[1] or x == p[1] + 11 then
        return tx("housing", x, y)
      end
      return tx("diffuser", x, y)
    end
  end
  for _, b in ipairs(ShopKit.BATTENS) do
    if z >= b[2] and z < b[2] + 12 then
      local top = capAt(z)
      if y < top - 5 or y > top - 4 then return nil end
      local west = b[1] == "w"
      local inRun = west and (x >= -8 and x <= 3) or (x >= 124 and x <= 135)
      if not inRun then return nil end
      local face = west and (x == 3) or (x == 124)
      if face then return tx("diffuser", z, y) end
      return tx("housing", z, y)
    end
  end
  return nil
end

-- ------- the fittings

local function fittings(x, y, z)
  -- the basket stack, at the counter's north cap: TAPERED and cornered,
  -- because a stack of shopping baskets is a truncated pyramid and a
  -- 10x10x8 prism of red is a brick
  if x >= 4 and x <= 13 and z >= 34 and z <= 43 then
    if y < CTOP or y > CTOP + 7 then return nil end
    local ly = y - CTOP
    local inset = floor((7 - ly) / 3)
    local a, b = x - 4 - inset, z - 34 - inset
    local w = 10 - inset * 2
    if a < 0 or b < 0 or a >= w or b >= w then return nil end
    if not chamfer(a, b, w, w, 2) then return nil end
    return tx("basket", x, y)
  end
  -- a carton of stock left at the end of the aisle, its corners knocked in
  if x >= 34 and x <= 43 and z >= 98 and z <= 107 then
    if y > 7 then return nil end
    if not chamfer(x - 34, z - 98, 10, 10, 1) then return nil end
    return tx("carton", x, y)
  end
  -- THE DARK THINGS, and they are here for a measured reason: 2 % of the
  -- room sat below value 0.20 against a healthy 8, and a frame with no
  -- dark in it gives its own lights nothing to be brighter than. Both are
  -- small -- a few dozen screen pixels each -- and both are canon konbini
  -- fittings that happen to be the two darkest objects in any shop.
  --
  -- A WASTE BIN beside the door, on the east jamb where nobody walks.
  if x >= 92 and x <= 97 and z >= 116 and z <= 123 then
    if y > 7 then return nil end
    if not chamfer(x - 92, z - 116, 6, 8, 1) then return nil end
    return tx("bin", x, y)
  end
  -- AN EXTINGUISHER on the west wall, in its plane, over the skirting.
  if x >= 0 and x <= 1 and z >= 60 and z <= 64 then
    if y < 6 or y > 10 then return nil end
    return tx("ext", z - 60, y - 6)
  end
  -- A PLANTER in the south-east corner.
  --
  -- Not dressing for its own sake: it is the only ORGANIC form in the room
  -- and the only green. The measured complaint is that 82 % of the frame's
  -- coherent contours lie within 4 degrees of the voxel's three axes, and
  -- that number did not move when the exposure and the materials were
  -- fixed, because nothing in a room of cabinets and boards can move it.
  -- A canopy is the cheapest thing that is not a box: it contributes an
  -- edge at every angle, and the eye reads "this is a place" off exactly
  -- that. Konbini keep one by the door; ours is out of the walking line.
  --
  -- Twelve across, ten tall -- 1.2 m by 1 m -- which clears cy 6's cap of
  -- 10... only just, so the canopy is checked against the cap rather than
  -- assumed to fit.
  if x >= 114 and x <= 125 and z >= 98 and z <= 109 then
    local cap = capAt(z)
    local a, b = x - 114, z - 98
    if y >= cap then return nil end
    if y <= 3 then
      -- the pot: a truncated cone, so its rim is proud of its foot
      local r = 3.4 + y * 0.5
      if not disc(a, b, 5.5, 5.5, r) then return nil end
      return tx("pot", x, y)
    end
    if y <= 4 then
      if not disc(a, b, 5.5, 5.5, 1.6) then return nil end
      return tx("pot", x, y)                       -- the stem
    end
    -- the canopy: an ellipsoid squashed in y, widest at 7
    local dy = (y - 7.5) / 3.2
    local rr = 5.6 * math.sqrt(math.max(0, 1 - dy * dy))
    if rr < 0.9 then return nil end
    if not disc(a, b, 5.5, 5.5, rr) then return nil end
    -- and it is NOT solid: a canopy with holes in it is what stops the
    -- ellipsoid reading as a green boulder
    if hash(x, y, z) % 8 == 0 then return nil end
    return tx("foliage", x + y, z)
  end
  -- An IMPULSE DISPLAY on the counter's north cap, beside the baskets.
  --
  -- The counter top is the largest empty TOP face in the room and this
  -- camera looks straight down onto it. It goes on the NORTH cap because
  -- that is the only part of the counter with headroom: CTOP is 10 and
  -- cy 6's cap is 10 too, so the south arm is sliced flush with its own
  -- worktop and nothing can stand there at all -- the register at z 84..95
  -- is a named exception that spends cy 5's two voxels.
  --
  -- Three stepped tiers of small boxes, tallest at the back, which is what
  -- a counter unit is and also the shape that keeps every tier's top face
  -- visible from here.
  if x >= 16 and x <= 29 and z >= 33 and z <= 44 then
    if y < CTOP then return nil end
    local ly, a, b = y - CTOP, x - 16, z - 33
    local tier = floor(b / 4)                    -- 0 back, 2 front
    local top = 5 - tier * 2
    if ly > top then return nil end
    if ly == 0 then return tx("board", x, z) end
    if b % 4 == 3 then return nil end            -- the gap between tiers
    if a % 4 == 3 then return nil end            -- and between facings
    local k = hash(floor(a / 4), tier, 11)
    if ly == top then return prodCap(k, a % 4, 3) end
    return prodFit(k, a % 4, 3, ly - 1, top)
  end
  -- A PALLET OF STOCK in the south-east, where the plan leaves the biggest
  -- run of bare floor in the room. Measured, bare floor was 22-29 % of
  -- every pixel of the frame -- more than any other surface -- and the
  -- south-east quadrant carried none of it.
  --
  -- A T11 pallet is 110 cm square: eleven voxels. Two of pallet and eight
  -- of carton is ten, and cy 5's cap is twelve, so it clears with room --
  -- unlike a dump bin or a spinner, which want the cells at cy 4-5 where
  -- the cap is 17 and 12 and the aisle has to stay walkable.
  --
  -- It is also almost entirely TOP face, which at 27 degrees is the face
  -- this camera is best at: a pallet reads from above and needs no detail
  -- on any flank.
  if x >= 100 and x <= 110 and z >= 84 and z <= 94 then
    local a, b = x - 100, z - 84
    if y <= 1 then
      -- the deck: boards across, with the gaps a pallet actually has, and
      -- three bearers under them
      if y == 1 then
        if b % 3 == 2 then return nil end
        return tx("board", x, z)
      end
      if a % 5 == 4 or b % 5 == 4 then return nil end
      return tx("kick", x, z)
    end
    if y > 9 then return nil end
    -- two cartons, stacked short and tall so the stack has a shoulder
    -- rather than a flat lid the length of the pallet
    local tall = (a < 6)
    if not tall and y > 6 then return nil end
    local w = tall and 6 or 5
    local a0 = tall and 0 or 6
    local aa = a - a0
    if aa < 0 or aa >= w or b < 1 or b > 9 then return nil end
    if not chamfer(aa, b - 1, w, 9, 1) then return nil end
    return tx("carton", x, y)
  end
  -- the entrance mat
  if y == 0 and z >= 112 and z <= 126 and x >= 42 and x <= 85 then
    return tx("mat", x - 42, z - 112)
  end
  -- ...and the THRESHOLD PLATE where it ends: a strip of metal on the door
  -- line itself, which every shop has because that is where the floor
  -- finish changes and something has to cover the joint. One voxel, and it
  -- gives the doorway a line to sit on instead of the mat simply stopping.
  if y == 0 and z == 127 and x >= DOOR_X0 - 3 and x <= DOOR_X1 + 3 then
    return tx("mullion", x, 0)
  end
  return nil
end

-- the poster on the west wall's inner face, over the checkout
local function poster(x, y, z)
  if x ~= -1 or z < 96 or z > 119 or y < 4 or y > 11 then return nil end
  return tx("poster", z - 96, (y - 4) * 4)
end

-- ------- the two things the cut is allowed to keep
--
-- Both are named in assets/docs/shop/ART_DIRECTION.md and both are narrow:
-- what they hide is one cell of what is already their own.

-- The till: six voxels standing on a ten-voxel counter, at the cell the
-- plan draws it (tiles 14/15 over 30/31, rows 10-11).
-- THE CHECKOUT, which is more than a till.
--
-- This is the one part of the room a player is guaranteed to walk up to
-- and stand at, and it was a grey box on an otherwise empty two-metre
-- stretch of worktop. A real one is a POST: the till, its drawer, a pinpad
-- turned to face the customer's side, a coin tray and a stack of bags.
--
-- It stays a named exception to the height cap -- `room` calls it before
-- the `capAt` early-out, which is how the till gets six voxels where cy 5
-- only allows two -- so everything added here is checked against what it
-- would hide. At k = 0.511 the tallest piece is 15 at z 95, which lands
-- on screen where the floor at z 66 does; the gondola in front of it runs
-- to z 70 and covers 43..70, so the overlap is the last two voxels of an
-- aisle end. Nothing else in the room reaches that band.
local function register(x, y, z)
  if x < 18 or x > 31 or z < 79 or z > 95 then return nil end
  if y < CTOP or y >= CTOP + 6 then return nil end
  local ly = y - CTOP

  -- ------- the till
  if x >= 18 and x <= 29 and z >= 84 and z <= 95 then
    if ly >= 4 then
      -- the screen on its post: two voxels of glass, not a slab
      if x >= 22 and x <= 27 and z >= 89 and z <= 90 then
        if ly >= 5 then return tx("reg_screen", x - 22, ly) end
        return tx("reg_body", x, ly)
      end
      return nil
    end
    -- the CASH DRAWER: a shadow gap and a pull across the till's south
    -- face, which is the face the player stands at
    if z == 95 and ly == 1 then return tx("mullion", x, ly) end
    if ly == 3 and z >= 88 then return tx("reg_keys", x, z) end
    return tx("reg_body", x, ly)
  end

  -- ------- the pinpad, on the CUSTOMER's side and tipped toward them
  if x >= 30 and x <= 31 and z >= 88 and z <= 92 then
    if ly > 3 then return nil end
    if ly == 3 then
      if z >= 90 then return tx("reg_screen", x, ly) end
      return nil
    end
    if ly >= 1 and z >= 89 then return tx("reg_body", x, ly) end
    if ly == 0 then return tx("reg_body", x, ly) end
    return nil
  end

  -- ------- the coin tray: a shallow well the clerk drops change into.
  -- Five voxels square and one proud, in the dark of the mullion rather
  -- than the counter's own pale edge -- a 70 cm tray in the worktop's own
  -- colour is not a tray, it is a patch.
  if x >= 19 and x <= 23 and z >= 80 and z <= 84 then
    if ly > 0 then return nil end
    if x >= 20 and x <= 22 and z >= 81 and z <= 83 then return nil end
    return tx("mullion", x, z)
  end
  -- A stack of bags stood here too and was cut: five square by three tall
  -- in `board` came out as a pale cube most of a metre across, which at
  -- this scale outweighed the till it was meant to sit beside. A bag stack
  -- is a soft, low, shapeless thing and there is no honest way to say that
  -- in a 50 cm voxel -- so the worktop is left clear instead.
  return nil
end

-- The door's jambs. Two wide and twenty-one tall, and NO LINTEL: a lintel
-- across the bay would hide two and a half cells of the entry aisle at this
-- pitch, which is the whole reason nothing in this room hangs.
local function jambs(x, y, z)
  if z < 126 or z > 129 or y > 20 then return nil end
  local cx = nil
  if x >= DOOR_X0 - 3 and x < DOOR_X0 then cx = DOOR_X0 - 2
  elseif x > DOOR_X1 and x <= DOOR_X1 + 3 then cx = DOOR_X1 + 2 end
  if not cx then return nil end
  -- Round, and TURNED: a square post beside a doorway is a bollard, a
  -- round one is a pipe, and a round one with a plinth, a shaft, a collar
  -- and a cap is a jamb. Four radii is the whole difference, and the
  -- profile is what the eye reads at a doorway -- it is the one fixture in
  -- the room the player passes within a voxel of, every single time.
  local r, mat
  if y <= 2 then r, mat = 2.3, "cabinet"           -- the plinth
  elseif y <= 16 then r, mat = 1.6, "steel"        -- the shaft
  elseif y == 17 then r, mat = 2.0, "cabinet"      -- the collar
  else r, mat = 1.1, "cabinet" end                 -- the cap
  if disc(x, z, cx, 127.5, r) then return tx(mat, x, y) end
  return nil
end

-- ------------------------------------------------------------- the room --

local function room(x, y, z)
  if y < 0 or x < X0 or x > X1 or z < Z0 or z > Z1 then return nil end
  -- the two exceptions first: they are the only things that outgrow their
  -- row, and putting them here is also what lets the cap below be an
  -- unconditional early-out for the great empty middle of the box
  local v = register(x, y, z)
  if v then return v end
  v = jambs(x, y, z)
  if v then return v end
  if y >= capAt(z) then return nil end
  v = fixtures(x, y, z)
  if v then return v end
  v = beam(x, y, z)
  if v then return v end
  if x < 0 or x >= ShopKit.ROOM_W then
    v = poster(x, y, z)
    if v then return v end
    return shell(x, y, z)
  end
  if z >= 128 then return shell(x, y, z) end
  if z < 0 then return north(x, y, z) end
  if z <= 31 then
    if z <= NWALL_Z1 then return north(x, y, z) end
    if x < 32 or x >= 96 then return saleCase(x, y, z) end
    return cooler(x, y, z)
  end
  v = counter(x, y, z)
  if v then return v end
  v = backFixture(x, y, z)
  if v then return v end
  v = eastShelf(x, y, z)
  if v then return v end
  v = westShelf(x, y, z)
  if v then return v end
  v = gondola(x, y, z)
  if v then return v end
  return fittings(x, y, z)
end

ShopKit.room = room                    -- named for the headless harness

-- ----------------------------------------------------- the contact field --
--
-- NOTHING IN THIS ROOM CAST A SHADOW. Indoors the sun is held off -- a Mart
-- has a roof over it -- and the eight tubes are the scene shader's POINT
-- lights, which light a surface without occluding one. So in every build up
-- to this one each fixture stood on the floor without touching it. It is
-- measurable in probe_out_shop: the floor four voxels clear of a gondola
-- and the floor under its own kick came back the same luminance, and a
-- room where nothing is grounded reads as models floating over a texture
-- however well each model is made.
--
-- Every light in this room hangs at the CEILING, so a fixture's shadow is
-- its own vertical projection, softened. That makes the field the room's
-- own occupancy, blurred -- no ray, no second pass, no new sampler.
--
-- Read per VERTEX by Buildings.emit (`m.contact`), never per face: the
-- greedy merge hands the floor back in runs tens of voxels long, so a
-- per-face factor would step the shadow in blocks the size of the run.
--
-- SAMPLED IN SLICES, and that is what keeps a fixture out of its own
-- shadow. A face at height y is darkened only by the slices ABOVE it, so
-- the floor is shaded by everything and a gondola's own top -- at 13, above
-- the last slice -- by nothing. A single flattened field darkened every
-- fixture top by the fixture under it, which reads as grime.
local CONTACT_SLICES = { 1, 5, 10, 18 }
local K_NEAR, K_WIDE = 0.34, 0.30     -- the seam, and the pool
local R_NEAR, R_WIDE = 1, 5           -- voxels; 5 = half a metre of penumbra

local contactField                    -- baked once; see bakeContact

-- separable box blur over the room's plan. Two axes, one pass: a box is a
-- coarse tent, but the field it blurs is already a 0..1 occupancy and the
-- eye is reading a shadow's SOFTNESS, not its profile.
local function blurPlan(src, r)
  local Wd, D = ShopKit.ROOM_W, ShopKit.ROOM_D
  local tmp, out = {}, {}
  for z = 0, D - 1 do
    local row = z * Wd
    for x = 0, Wd - 1 do
      local acc, n = 0, 0
      for dx = -r, r do
        local u = x + dx
        if u >= 0 and u < Wd then acc = acc + src[row + u]; n = n + 1 end
      end
      tmp[row + x] = acc / n
    end
  end
  for z = 0, D - 1 do
    for x = 0, Wd - 1 do
      local acc, n = 0, 0
      for dz = -r, r do
        local w = z + dz
        if w >= 0 and w < D then acc = acc + tmp[w * Wd + x]; n = n + 1 end
      end
      out[z * Wd + x] = acc / n
    end
  end
  return out
end

-- Baked ONCE for the module, not once per band and not once per map: the
-- eight town Marts hash to the same tile grid (tools/interior_plan.py), so
-- the field is a property of the KIT. Three bands sharing one bake is also
-- what keeps the shadow continuous across the seam -- a per-band field
-- would have drawn a step down the middle of the floor.
local function bakeContact()
  if contactField then return contactField end
  local Wd, D = ShopKit.ROOM_W, ShopKit.ROOM_D
  local near, wide = {}, {}
  for s = 1, #CONTACT_SLICES do
    local y = CONTACT_SLICES[s]
    local occ = {}
    for z = 0, D - 1 do
      local row = z * Wd
      for x = 0, Wd - 1 do
        occ[row + x] = room(x, y, z) and 1 or 0
      end
    end
    near[s] = blurPlan(occ, R_NEAR)
    wide[s] = blurPlan(occ, R_WIDE)
  end
  contactField = { near = near, wide = wide }
  return contactField
end

-- The factor at one corner. `y` is the face's own height, so only the
-- slices standing over it count, and each one's shadow is harder and
-- darker the closer it is -- the 1/d an area light really has, quantised
-- to the slices we sample.
local function contactAt(x, y, z)
  local Wd, D = ShopKit.ROOM_W, ShopKit.ROOM_D
  if x < 0 then x = 0 elseif x > Wd - 1 then x = Wd - 1 end
  if z < 0 then z = 0 elseif z > D - 1 then z = D - 1 end
  local f = bakeContact()
  local i = z * Wd + x
  local acc = 1
  for s = 1, #CONTACT_SLICES do
    local sy = CONTACT_SLICES[s]
    if sy > y then
      local hard = 1 / (1 + 0.30 * (sy - y))
      local k = K_NEAR * f.near[s][i] * hard
              + K_WIDE * f.wide[s][i] * (1 - hard)
      acc = acc * (1 - k)
    end
  end
  return acc
end

ShopKit.contactAt = contactAt          -- named for the headless harness

-- ------------------------------------------------------------- the bands --
--
-- Three windows into `room`, matched against the plan's own tile rows. The
-- halo (`pad`) is how far the model reaches past its band so the emit sees
-- the neighbour's geometry as a phantom and cuts no face at the seam.
local BAND_DEF = {
  north = { z0 = 0,  z1 = 31,  pad0 = 8, pad1 = 1, ytop = CEIL },
  -- 26, not the 22 the mid band's own tallest fixture needs: the ceiling
  -- panels hang at y 23-24 over the back rows, and a ytop cut to the
  -- furniture never probed them -- three fixtures that existed in the kit
  -- and were invisible in the render.
  mid   = { z0 = 32, z1 = 79,  pad0 = 1, pad1 = 1, ytop = 26 },
  south = { z0 = 80, z1 = 127, pad0 = 1, pad1 = 8, ytop = 21 },
}

local function ownerOf(z)
  if z < 32 then return "north" end
  if z < 80 then return "mid" end
  return "south"
end

-- ------------------------------------------------------------- lighting --
--
-- The two numbers that are the crypt's, inverted, and the whole difference
-- in tone between the two rooms:
--
--   SIDE  0.94 against CryptKit's 0.90 -- flatter, because a shop is lit by
--         bounce off a pale floor and a pale ceiling, not by a flame.
--   FOOT  1.04 against CryptKit's 0.84 -- the lowest course LIFTS. A crypt's
--         floor is stone and eats light; a konbini's is polished and throws
--         it back up the kick.
--
-- And there is no vertical fade. The crypt climbs its walls out of the
-- light so it needs no ceiling; a shop is brightest AT the ceiling, and the
-- cornice band is the top of the light rather than the bottom.
local SIDE, FOOT = 0.94, 1.04

-- the products band of the sheet: rows 80..127
local function isProduct(i)
  if not i or i < 0 then return false end
  local sy = floor(i / W)
  return sy >= PROD_Y and sy < PROD_Y + 48
end

-- Is this texel the cornice column? SW.cornice is (32, 0, 16, 16).
local function isCornice(i)
  if not i or i < 0 then return false end
  local sx, sy = i % W, floor(i / W)
  return sy < 16 and sx >= 32 and sx < 48
end

local function tintFor(y, i, dir, shade)
  if not shade or shade <= 0 then return 1 end
  local lit = emissiveOf(i)
  if lit then return lit / shade end
  if isProduct(i) then
    -- graded by height, and this is the under-shelf strips doing their job.
    -- A facing on a low tier sits in a slot with a board over it and a deck
    -- under it, so the corner occlusion the emit bakes in takes it most of
    -- the way to black however flat the tint is -- measured: the bottom
    -- tier of both gondolas came out as one dark band with the rails
    -- showing through it, three in-game runs running, while the same texels
    -- read as saturated labels off the sheet. The lit lip over each tier is
    -- what a real fitout answers this with, and this is that lip's light.
    local k = (10 - y) / 10
    if k < 0 then k = 0 elseif k > 1 then k = 1 end
    return PROD_LIFT * (1 + 0.62 * k) / shade
  end
  local f
  -- THE COPING. The dollhouse cut manufactures a five-voxel-wide top face
  -- along three walls and the south sill, and those bands came out as the
  -- largest flat white areas in the frame -- a surface that does not exist
  -- in a real shop, reading as the brightest thing in it. Every wall's top
  -- course is already `cornice`; this is the same course seen from ABOVE,
  -- taken down a fifth, which is what a coping stone does and what stops
  -- the cut announcing itself. Faces only -- no geometry, no extra quad.
  if dir == "up" and isCornice(i) then return 0.80 / shade end
  if dir == "up" then f = 1.00 / shade
  elseif dir == "down" then f = 0.72 / shade
  else f = SIDE / shade end
  if y <= 1 then f = f * FOOT end
  return f
end

-- ------------------------------------------------------------------ api --

-- Is the sheet the one this table was written against? A regenerated sheet
-- with a different layout would index every swatch somewhere else, so the
-- kit refuses and Buildings falls back to lib/RoomKit.lua rather than
-- standing a room made of the wrong texels.
function ShopKit.sheetOk(sp)
  return sp and sp.W == ShopKit.SHEET_W and sp.H == ShopKit.SHEET_H
end

-- The SHOP row lives in lib/Shop.lua, because the scene answers to it too.
-- Re-exported here the way lib/CryptKit.lua re-exports the crypt's, so
-- anything holding the kit can reach the row without knowing that the
-- scene module is where it is declared (tests/shop_interior_probe.lua's
-- A/B half is what wanted it).
ShopKit.setting = (function()
  local ok, Shop = pcall(V.require, "Shop")
  return ok and Shop and Shop.setting or nil
end)()

function ShopKit.enabled()
  local ok, Shop = pcall(V.require, "Shop")
  if not (ok and Shop and Shop.enabled) then return false end
  local okE, on = pcall(Shop.enabled)
  return okE and on or false
end

-- Which of a band's tiles the room actually STANDS in.
--
-- The three bands match all 256 tiles of the plan between them, and a
-- stamp claims every tile it matches: `Buildings.stamp` then paints ground
-- under the claim from `groundVote`, which has no vote to take at the
-- map's south edge -- so the shop's whole entrance came out as black void
-- in the first in-game frames. Claim only the cells with something in
-- them and the mesher lays the floor everywhere else, as it always did.
--
-- Sampled off `room` itself rather than authored as a table, so it cannot
-- drift when a fixture moves. y starts at 1: the entrance mat is a decal
-- one voxel tall and must NOT claim the floor it lies on.
-- The plan's plain floor. Everything else in the grid is a FIXTURE's own
-- drawing, and its tile must be claimed even where this room leaves air
-- there -- otherwise the mesher's class pins stand the old drawing as a
-- box in the gap. That is what the dark fixture in front of the gondolas
-- was for four in-game runs: a leftover shelf rack, extruded from the
-- four-grey tileset (measured -- its pixels were the atlas's own neutral
-- greys and pure black, none of which exist on the shop's sheet), standing
-- in the two tile rows the modelled gondola does not reach.
local FLOOR_TILE = { [1] = true, [11] = true, [17] = true, [27] = true,
                     [54] = true, [26] = true, [12] = true, [28] = true }

local function claimMaskFor(b, t)
  local rows, cols = #t.tiles, #t.tiles[1]
  local mask = {}
  for r = 0, rows - 1 do
    for c = 0, cols - 1 do
      local hit = not FLOOR_TILE[t.tiles[r + 1][c + 1]]
      for dz = 0, 6, 2 do
        for dx = 0, 6, 2 do
          local x, z = c * 8 + dx, b.z0 + r * 8 + dz
          for _, y in ipairs({ 1, 3, 6, 10, 16, 22 }) do
            if room(x, y, z) then hit = true break end
          end
          if hit then break end
        end
        if hit then break end
      end
      mask[r * cols + c + 1] = hit
    end
  end
  return mask
end

-- The model for one band. `t.shop` names it.
function ShopKit.model(sp, t)
  local b = BAND_DEF[t.shop]
  if not b then return nil, "unknown band " .. tostring(t.shop) end
  if not ShopKit.sheetOk(sp) then
    return nil, ("sheet is %sx%s, expected %dx%d")
      :format(tostring(sp and sp.W), tostring(sp and sp.H),
              ShopKit.SHEET_W, ShopKit.SHEET_H)
  end
  local PHANTOM = -1
  local okB, Buildings = pcall(V.require, "Buildings")
  if okB and Buildings and Buildings.PHANTOM then
    PHANTOM = Buildings.PHANTOM
  end
  local name = t.shop
  local z0 = b.z0
  return {
    at = function(x, y, z)
      local rz = z0 + z
      local v = room(x, y, rz)
      if not v then return nil end
      if ownerOf(rz) ~= name then return PHANTOM end
      return v
    end,
    tint = tintFor,
    -- the emit hands corners in the BAND's coordinates; the field is the
    -- whole room's, so z comes back through the same z0 `at` uses
    contact = function(x, y, z) return contactAt(x, y, z0 + z) end,
    W = ShopKit.ROOM_W,
    ytop = b.ytop,
    xmin = X0, xmax = X1,
    zmin = -b.pad0, zmax = (b.z1 - z0) + b.pad1,
    standH = 0,
    -- This kit MODELS the till (see `register`), and the MART tileset has
    -- a drawn figure for the same two-by-two of tiles -- 14/15 over 30/31,
    -- the one lib/RoomKit relied on. Both were being built, one standing
    -- inside the other. The kit does the job, so the figure stands down.
    noFigure = true,
    claimMask = claimMaskFor(b, t),
  }
end

return ShopKit
