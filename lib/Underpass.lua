-- Voxel world mode: lighting the underground passages.
--
-- A passage between two cities is BUILT. Somebody dug it, tiled the floor
-- and wired it -- and the thing that says so, before any texture does, is
-- that the light comes in a ROW at a regular spacing, from overhead, in a
-- colour nothing in nature makes. A cave is lit by whatever fell in through
-- the hole; a corridor is lit by fittings somebody bolted to the ceiling at
-- five-metre centres, and you can see where the next one is before you get
-- to it.
--
-- Unlit, this map is one black tunnel with a bright floor in it. There is no
-- sun down here (no shadow pass, no sky), so every surface takes the same
-- flat ambient and the walls have no shape at all -- which is why the
-- passage reads as a void with a stripe rather than as a place.
--
-- NOTHING NEW IS DRAWN AND NO SHADER IS TOUCHED. The scene shader already
-- carries eight point lights with a windowed inverse-square falloff, a hot
-- core and a height above the floor (see `localLamp` in Voxel3D) -- built
-- for StreetLamps, fed only on outdoor maps, and switched off indoors with
-- `Voxel3D.lampLights = nil`. This file fills that same list with a row of
-- fittings down the middle of the corridor. What was missing was never the
-- machinery; it was that nobody had told it there are lamps down here.
--
-- WHERE THE ROW GOES is measured off the map rather than listed. A passage
-- is a corridor: its walkable cells make a long thin box, and the row runs
-- along the LONG axis, centred on the short one. That holds for the
-- north-south passage (4x24 blocks) and the west-east one (25x4) with no
-- per-map table, and it holds for a mod that adds a third.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Underpass = {}

-- Tileset image paths this applies to, matched as a lowercase SUBSTRING --
-- the same contract as FloorArt.TILESETS, and the same reason: it is a fact
-- about somebody's map set, not about the renderer.
Underpass.TILESETS = { "underground" }

-- Off switch, for the probe. The A/B has to be here rather than in the
-- probe's own hands: VoxelScene.render rewrites Voxel3D.lampLights every
-- frame, so a probe that nils the list gets it back before the screenshot
-- lands -- which is exactly what the first run of this did, producing two
-- identical pictures and a conclusion that was worth nothing.
Underpass.ENABLED = true

-- World pixels between fittings. 64 is four map cells. Close enough that the
-- pools overlap at the floor and the corridor is continuously lit, far
-- enough that there is a visible dim between them -- which is the whole
-- point, because a corridor lit evenly end to end has no length to it.
Underpass.STEP = 64

-- How far one pool reaches along the floor. Wider than the step so the
-- overlap lands above the walker's head rather than at his feet, and wide
-- enough to reach the walls -- the corridor is only a few cells across, and
-- a pool that dies before the wall lights a floor in a void.
-- Only a little wider than the step, on purpose: a wide pool is a FLAT pool
-- -- the falloff has further to travel before it has fallen anywhere -- and
-- a corridor lit by eight overlapping flat pools is a corridor lit evenly,
-- which is the thing being fixed.
Underpass.RADIUS = 72

-- How high the fitting hangs. The falloff runs off this (localLamp softens
-- the inverse square by the flame's own height), so it is also what decides
-- how flat the pool under a lamp is: low and it is a hot spot, high and it
-- is a wash. 20 puts it above head height in a corridor with a low roof.
Underpass.HEIGHT = 20

-- What is left of the interior's own ambient down here, as a multiplier on
-- DayNight.tint. This is the number that makes the fittings matter: at 1 the
-- corridor is already lit end to end and eight point lights on top of it
-- change almost nothing (measured -- lamps on against lamps off came back
-- nearly identical). Not 0 either: a wall between two pools has to stay a
-- wall, and a corridor that goes truly black between fittings is a horror
-- set.
--
-- 0.34 was the first try and it was too deep: measured on the corridor
-- floor, the whole package came out at luminance 53 against 107 without it
-- -- half as bright overall, because the fittings do not put back what the
-- dim takes away. The shader's pool energy saturates at x/(1+1.6x), a
-- ceiling of 0.625 built for a night street where eight pools overlap inside
-- one screen, so a lamp can add about half a unit of light and no more.
-- 0.55 is the level where the sum lands back near where it started, and the
-- change is in the SHAPE of the light rather than in how much of it there is.
Underpass.AMBIENT = 0.55

-- Brightness of one fitting. Full, and it does not follow the clock: a
-- passage has no windows, so the hour of the day has nothing to say about
-- what the lights in it are doing -- the one place in this mod where that is
-- true, and the reason this does not just call DayNight.windowLight the way
-- StreetLamps does.
-- Above 1 and that is not a mistake: `power` is the input to the shader's
-- saturating curve, not the output, so pushing it drives the core nearer the
-- 0.625 ceiling while the rim -- which is far enough down the curve to still
-- be roughly linear -- climbs less. It buys contrast, not brightness.
Underpass.POWER = 1.5

-- WARM. This was cold first -- the reasoning being that a public works
-- tunnel is fluorescent and cold light is what separates "built" from
-- "cave". The reference says otherwise: the fittings in a real underpass are
-- sodium or warm LED, the concrete goes amber under them, and the red floor
-- warms up rather than fighting the light. Cold read as a morgue.
Underpass.COLOR = { 1.00, 0.80, 0.48 }
Underpass.CORE = { 1.00, 0.95, 0.80 }

-- ------- the shell
--
-- A corridor needs a corridor around it. The tileset gives a floor and two
-- low rails and then stops, so everything past the rail is the void the
-- diorama draws when there is no geometry -- which is why the passage read
-- as a lit strip floating in black however the lighting was tuned. No amount
-- of light fixes a missing ceiling; there is nothing up there for it to land
-- on.
--
-- So: a slab overhead, a wall up each side to hold it, a visible fitting at
-- every lamp site, and a strip of light along the base of each wall. All of
-- it axis-aligned boxes through the same Voxel3D.newMesh path StreetLamps
-- uses for its posts -- no new shader, no new texture format, one small
-- generated atlas.
-- NO SLAB. A full ceiling was the first build and it is unshippable in this
-- camera: the diorama looks DOWN, so a lid over the corridor hides the
-- corridor -- the probe came back as a grey rectangle with two lit boxes on
-- top of it and the player nowhere. The reference photograph is not a lid
-- either, looked at properly: its fittings are mounted on a HAUNCH running
-- along the wall, above the yellow bands, throwing light inward and down.
-- A haunch is what a top-down camera can actually see the underside of.
Underpass.WALL_TOP = 26       -- how high the side walls stand, world px
Underpass.HAUNCH_Y = 20       -- underside of the haunch that carries the lights
Underpass.HAUNCH_T = 6        -- its depth
Underpass.HAUNCH_IN = 9       -- how far it oversails the wall, into the corridor
Underpass.WALL_OUT = 8        -- how far outside the walkable box a wall sits
Underpass.FITTING_W = 7       -- the housing on the ceiling: across the corridor
Underpass.FITTING_L = 14      -- and along it
Underpass.FITTING_T = 3       -- how far it hangs below the slab
-- ------- WHERE A RUN CAN BE SEEN AT ALL
--
-- Both the hazard band and the LED run were generated correctly and neither
-- reached the frame, and the standing explanation -- the tileset's own rail
-- stands in front of them -- was wrong. What the sweep found instead:
--
--   THE RAIL IS 16.   Measured off the map rather than assumed: every one of
--   the 90 cells ringing the walkable box resolves to class `wall`, art
--   `upright`, h=16 (the UNDERGROUND blockset pins $02/$06/$09/$16/$17 there,
--   and `wall` is 16px for every interior in the game).
--
--   AND IT IS NOT THE OCCLUDER. The runs stay invisible at 17, 19 and 21 --
--   all of them clear of 16 -- and only appear once they pass WALL_TOP (26).
--
--   NOR IS IT A MATTER OF STANDING FURTHER OUT. Swept at 2, 4, 6, 8 and 12
--   world px proud of the wall face, at a height between the rail and the
--   crest: nothing appeared at any of them.
--
--   NOR IS IT BRIGHTNESS. A PURE GREEN run at full flatten, at 17, produced a
--   frame byte-identical to the one with the run switched off -- 0 pixels
--   changed. That is not a surface too dim to see. That is a surface that was
--   never rasterised.
--
-- The conclusion the three of those force: this camera cannot see the
-- corridor's VERTICAL faces. It looks nearly straight down, so the inner face
-- of a 26px wall is two to four screen pixels wide and the haunch above it
-- oversails what is left. The surfaces that have area from up here are the
-- horizontal ones -- the floor, and the CREST where the wall and its haunch
-- make one flat 17px-wide top at WALL_TOP.
--
-- So both runs live on the crest, and that is not a compromise on the
-- reference so much as a different reading of it: what a real underpass shows
-- somebody standing IN it is a band down the wall, and what it shows somebody
-- looking DOWN into it is the same band along the top of the parapet. The one
-- this camera is looking at is the second.
--
-- STILL NOT SOLVED, and this comment is not going to pretend otherwise: on
-- the crest the runs read at the corridor's FAR end and fade out along the
-- near sides, for the reason set out under RUN_PLACE. The LED clears its
-- noise floor comfortably (blue 0 -> 567 px, and blue has no noise floor at
-- all down here); the band clears it by less than 2x (yellow +614 against a
-- +-452 frame-parity spread) and should be read as weak rather than as done.
-- What that costs is the reference's continuous run; what would buy it back
-- is a lower WALL_TOP or a camera pitch this file does not own.
--
-- The LED: a line along the crest's INNER lip, standing proud of it, which is
-- the edge that traces the corridor's direction.
-- AND THE CREST IS ONLY HALF OF IT. The camera's eye sits inside the
-- corridor, below WALL_TOP, so a crest run is above eye level for most of its
-- length and only drops into view where the corridor recedes past the
-- horizon: measured, the LED's blue landed in one patch at the far end
-- (x 463..560 of a 1024-wide frame) and nowhere down the near sides.
--
-- The obvious next move -- hang the runs from the haunch SOFFIT instead,
-- where the visible fittings already are -- was tried and is worse, not
-- better: band and LED both came back at 0 pixels changed against the same
-- anchored frame, against the crest's 567 blue and 614 yellow. So the
-- fittings are not visible because the soffit is; they are visible because
-- they are 7x14 boxes hanging 3px BELOW it, into the corridor.
--
-- Crest, then, and the knob stays because this is the one number here that
-- is about the camera's eye height rather than about the corridor: a rung or
-- a mod that moves the camera moves this answer with it.
Underpass.RUN_PLACE = "crest"       -- "crest" | "soffit"
Underpass.STRIP_W = 3         -- across the crest
Underpass.STRIP_H = 1.5       -- how far it stands proud of the crest
-- Kept as an override rather than derived, so a probe can still sweep the run
-- up and down the wall to re-check the finding above. nil = on the crest.
Underpass.STRIP_Y = nil

-- Which emissive runs are built. Separate from ENABLED on purpose: ENABLED
-- is the whole package (fittings AND the ambient dim), and a probe that
-- wants to know whether the BAND cleared the rail cannot ask that question
-- through a switch that also takes the light out of the corridor.
Underpass.SHOW_BAND = true
Underpass.SHOW_STRIP = true

-- The hazard banding. It is the loudest thing in the reference photograph and
-- the cheapest thing here: a stripe in a yellow nothing else in the corridor
-- wears. On the crest beside the LED for the reason set out above -- on the
-- wall face it is not dim, it is not drawn.
--
-- It is also what gives the corridor a horizon: without it the two crests are
-- flat grey rails and a flat rail lit from above is a gradient, and a gradient
-- has no scale to it.
Underpass.BAND_W = 6          -- across the crest
-- Both runs STRADDLE the crest rather than sit on it -- half the thickness
-- below WALL_TOP, half above. Sitting on it would put the run's underside
-- exactly coplanar with the crest's top face, which is a depth fight at every
-- pixel of a surface that runs the length of the corridor.
Underpass.BAND_H = 1.2        -- barely proud: a painted marking, not a kerb
Underpass.BAND_GAP = 1        -- clear space between the band and the LED
-- nil = on the crest, as with STRIP_Y.
Underpass.BAND_Y = nil
-- Atlas columns as UVs, not indices: the vertex carries a texture
-- coordinate and the sheet is three texels wide, so the centres are at 0,
-- 0.5 and 1. Writing 2 here (which is what the two-texel sheet's `1` looked
-- like it meant) samples off the end and clamps.
Underpass.U_CONCRETE = 0.0
Underpass.U_LIT = 0.5
Underpass.U_BAND = 1.0

-- How hard the emissive parts are pushed toward their own colour. Not 1:
-- a fitting flattened all the way is a white rectangle with no housing
-- around it, and the housing is what makes it read as a fixture rather than
-- as a hole in the ceiling.
Underpass.GLOW_FLATTEN = 0.82

-- The LED run's own colour, and its own draw.
--
-- `Voxel3D.flatten` is a uniform send (ghostColor/ghost) and nothing else --
-- it is not state that a mesh carries, it is state the SHADER is in when a
-- mesh goes through it. So one flatten can only ever describe one colour,
-- and the reason the run burned amber was that it shared a mesh with the
-- fittings. Two meshes and two sends, at a cost of one extra draw call and
-- two extra uniform writes per frame.
--
-- Cold, and colder than the fittings are warm: the whole job of this line is
-- to be the one thing down here that is NOT sodium. Against COLOR's
-- (1.00, 0.80, 0.48) this reads as a different kind of fitting rather than
-- as the same fitting at a different brightness.
Underpass.LED_COLOR = { 0.42, 0.72, 1.00 }
-- Harder than GLOW_FLATTEN. The fittings keep some housing because a lamp
-- needs a body; a strip light IS its lens, and a strip that keeps a quarter
-- of the corridor's amber ambient comes out grey-blue rather than blue.
Underpass.LED_FLATTEN = 0.94

-- And the band gets one too, for a different reason. On the crest the band's
-- geometry IS drawn -- about a thousand pixels of it, measured -- and it
-- still reads as grey: it is ordinary concrete-shaded surface, and the
-- corridor's ambient is held down to AMBIENT (0.55) so the fittings have
-- something to push against. Paint under that comes out near black, which is
-- the same problem the wall texel already had to be made unrealistically pale
-- to dodge.
--
-- So the band is pushed toward its own yellow -- but only half way, because
-- it is PAINT, not a light. Flattened hard it stops taking the fittings'
-- pools and the corridor loses the one cue that says the lamps are above the
-- band rather than beside it.
Underpass.BAND_COLOR = { 0.98, 0.78, 0.10 }
Underpass.BAND_FLATTEN = 0.62

-- No flicker. A gas flame wanders and this mod animates that; a tube on a
-- ballast does not, and a corridor whose lights breathe reads as a horror
-- set rather than as municipal infrastructure.
Underpass.FLICKER = 0

-- The shader takes eight (lamp0..lamp7). A corridor is longer than eight
-- fittings, so the row is generated whole and the NEAREST eight are sent --
-- same as StreetLamps.lights, and for the same reason.
Underpass.LIMIT = 8

function Underpass.matches(map)
  local img = map and map.tileset and map.tileset.image
  if type(img) ~= "string" then return false end
  img = img:lower()
  for _, name in ipairs(Underpass.TILESETS) do
    if img:find(name, 1, true) then return true end
  end
  return false
end

-- ------- the corridor's own axis
--
-- One scan per map, cached: the walkable cells' bounding box. Everything
-- below is read off it, so a passage that is not shaped the way these two
-- are still gets its row down its own long axis.

local cache = { id = nil, box = nil }

local function walkBox(map)
  if not (map and map.def) then return nil end
  if cache.id == map.id and cache.box then return cache.box end
  local cw = math.floor((tonumber(map.def.width) or 0) * 2)
  local ch = math.floor((tonumber(map.def.height) or 0) * 2)
  if cw <= 0 or ch <= 0 then return nil end
  local x0, y0, x1, y1
  for cy = 0, ch - 1 do
    for cx = 0, cw - 1 do
      local ok, walk = pcall(map.isWalkableCell, map, cx, cy)
      if ok and walk then
        if not x0 or cx < x0 then x0 = cx end
        if not y0 or cy < y0 then y0 = cy end
        if not x1 or cx > x1 then x1 = cx end
        if not y1 or cy > y1 then y1 = cy end
      end
    end
  end
  if not x0 then return nil end
  cache.id = map.id
  cache.box = { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
  return cache.box
end

Underpass._walkBox = walkBox     -- named for the suite

-- The whole row, in world pixels, unsorted and unlimited.
function Underpass.row(map)
  local box = walkBox(map)
  if not box then return {} end
  -- cell centres, in world pixels
  local wx0 = box.x0 * 16 + 8
  local wz0 = box.y0 * 16 + 8
  local wx1 = box.x1 * 16 + 8
  local wz1 = box.y1 * 16 + 8
  local spanX = wx1 - wx0
  local spanZ = wz1 - wz0
  local step = math.max(16, tonumber(Underpass.STEP) or 80)

  local out = {}
  if spanZ >= spanX then
    -- a north-south corridor: the row runs down Z, centred in X
    local mid = (wx0 + wx1) * 0.5
    -- start half a step in, so the first fitting is not sitting in the
    -- doorway and the last is not either
    local z = wz0 + step * 0.5
    while z <= wz1 do
      out[#out + 1] = { x = mid, z = z }
      z = z + step
    end
  else
    local mid = (wz0 + wz1) * 0.5
    local x = wx0 + step * 0.5
    while x <= wx1 do
      out[#out + 1] = { x = x, z = mid }
      x = x + step
    end
  end
  -- a corridor shorter than one step still gets one fitting, in the middle
  if #out == 0 then
    out[1] = { x = (wx0 + wx1) * 0.5, z = (wz0 + wz1) * 0.5 }
  end
  return out
end

-- The nearest LIMIT fittings to (wx, wz), in the shape Voxel3D.lampLights
-- wants: { x, z, radius, power }.
function Underpass.lights(map, wx, wz)
  if not (Underpass.ENABLED and Underpass.matches(map)) then return {} end
  wx, wz = tonumber(wx) or 0, tonumber(wz) or 0
  local out = {}
  for _, site in ipairs(Underpass.row(map)) do
    local dx, dz = site.x - wx, site.z - wz
    out[#out + 1] = {
      x = site.x, z = site.z,
      radius = Underpass.RADIUS,
      power = Underpass.POWER,
      d2 = dx * dx + dz * dz,
    }
  end
  table.sort(out, function(a, b) return a.d2 < b.d2 end)
  for i = #out, Underpass.LIMIT + 1, -1 do out[i] = nil end
  return out
end

-- ------- the shell's geometry
--
-- Same box-of-six-quads idiom StreetLamps bakes its posts from, and the same
-- two-texel atlas trick: u picks a column, so one mesh can carry concrete and
-- light without a second draw or a second texture.

local Voxel3D = V.require("Voxel3D")
local Mat4 = V.require("Mat4")

local shellTex = nil          -- Image | false

local function ensureTex()
  if shellTex ~= nil then return shellTex or nil end
  local ok, img = pcall(function()
    local d = love.image.newImageData(3, 1)
    -- Pale concrete, and paler than concrete really is. The corridor's
    -- ambient is held down so the fittings have something to push back
    -- against, and a realistic mid-grey under that comes out near black --
    -- measured, the first walls read at about RGB 40 and the reference's
    -- read as a lit surface. The wall has to give the light something to
    -- bounce off or there is no point lighting it.
    d:setPixel(0, 0, 0.74, 0.71, 0.66, 1)   -- U_CONCRETE
    d:setPixel(1, 0, 1.00, 0.97, 0.90, 1)   -- U_LIT
    d:setPixel(2, 0, 0.93, 0.74, 0.13, 1)   -- U_BAND
    local i = love.graphics.newImage(d)
    pcall(i.setFilter, i, "nearest", "nearest")
    return i
  end)
  shellTex = (ok and img) or false
  return shellTex or nil
end

-- One axis-aligned box as six quads. `u` selects the atlas column, `shade`
-- is the face shade the scene multiplies by. Copied in spirit from
-- StreetLamps.addBox -- and the per-face shades are NOT copied: down-facing
-- gets the brightest here because in a tunnel the only light comes from
-- overhead fittings pointing at the floor, so a soffit is the lit face and
-- the top of the slab is never seen at all.
local function addBox(verts, indices, x0, y0, z0, x1, y1, z1, u, shade)
  local faces = {
    { { x1, y0, z0 }, { x1, y0, z1 }, { x1, y1, z1 }, { x1, y1, z0 }, 0.82 },
    { { x0, y0, z1 }, { x0, y0, z0 }, { x0, y1, z0 }, { x0, y1, z1 }, 0.82 },
    { { x0, y1, z0 }, { x1, y1, z0 }, { x1, y1, z1 }, { x0, y1, z1 }, 0.45 },
    { { x0, y0, z1 }, { x1, y0, z1 }, { x1, y0, z0 }, { x0, y0, z0 }, 1.00 },
    { { x0, y0, z1 }, { x1, y0, z1 }, { x1, y1, z1 }, { x0, y1, z1 }, 0.88 },
    { { x1, y0, z0 }, { x0, y0, z0 }, { x0, y1, z0 }, { x1, y1, z0 }, 0.88 },
  }
  for _, f in ipairs(faces) do
    local base = #verts
    local s = shade * f[5]
    for i = 1, 4 do
      local c = f[i]
      verts[#verts + 1] = { c[1], c[2], c[3], u or 0, 0.5, s }
    end
    Voxel3D.pushQuad(indices, base / 4)
  end
end

local function bake(boxes)
  if #boxes == 0 then return nil end
  local verts, indices = {}, {}
  for _, b in ipairs(boxes) do
    addBox(verts, indices, b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8])
  end
  local ok, m = pcall(Voxel3D.newMesh, verts, indices)
  return ok and m or nil
end

-- shell = concrete (walls + haunches + bands), glow = the warm fittings,
-- led = the cold run. Three meshes because they are three shader states,
-- not because they are three shapes.
local built = { id = nil, shell = nil, band = nil, glow = nil, led = nil }

local function release(b)
  if b and b.release then pcall(b.release, b) end
end

-- Named for the suite: a probe that has just moved BAND_Y needs to be able to
-- say whether the band was baked at all before it reads anything off a
-- screenshot, and "the mesh exists" and "the mesh is visible" are the two
-- halves this bug has been sitting between.
Underpass._built = built

local function buildShell(map)
  if built.id == map.id then return built end
  release(built.shell); release(built.band)
  release(built.glow); release(built.led)
  built.id, built.shell, built.band, built.glow, built.led =
    map.id, nil, nil, nil, nil

  local box = walkBox(map)
  if not box then return built end
  local out = Underpass.WALL_OUT
  local x0 = box.x0 * 16 - out
  local z0 = box.y0 * 16 - out
  local x1 = (box.x1 + 1) * 16 + out
  local z1 = (box.y1 + 1) * 16 + out
  local wt = Underpass.WALL_TOP
  local hy = Underpass.HAUNCH_Y
  local ht = Underpass.HAUNCH_T
  local hin = Underpass.HAUNCH_IN
  local long = (z1 - z0) >= (x1 - x0)
  local UC, UL, UB = Underpass.U_CONCRETE, Underpass.U_LIT, Underpass.U_BAND

  -- The crest: the flat top the wall and its haunch make together, and the
  -- one surface of the corridor's shell that this camera has real area on.
  -- Both runs are laid ALONG it, inward from its inner lip: the LED first
  -- because it is the edge that traces the corridor, then a gap, then the
  -- band. `crestIn` is how far in from the lip a run starts; the geometry
  -- below turns that into a box on whichever pair of walls is the long one.
  local sw, shp = Underpass.STRIP_W, Underpass.STRIP_H
  local bw, bhp, gap = Underpass.BAND_W, Underpass.BAND_H, Underpass.BAND_GAP
  -- nil means "on the crest"; a number is a probe overriding it back onto the
  -- wall face, which is how the finding above stays re-checkable.
  local soffit = (Underpass.RUN_PLACE ~= "crest")
  -- On the soffit both runs HANG: their bottom face is the one seen, so they
  -- drop below HAUNCH_Y rather than straddling anything. On the crest they
  -- straddle WALL_TOP, half in and half proud, so no face of either is
  -- coplanar with the concrete underneath it.
  local sy = Underpass.STRIP_Y or (soffit and (hy - shp) or (wt - shp * 0.5))
  local by = Underpass.BAND_Y or (soffit and (hy - bhp) or (wt - bhp * 0.5))
  local bh = bhp
  -- distances in from the crest's inner lip
  local sIn0, sIn1 = 0, sw
  local bIn0, bIn1 = sw + gap, sw + gap + bw

  -- Its own list, and so its own mesh and its own flatten: see BAND_COLOR.
  local band = {}

  local concrete = {
    -- the four walls. They stop at WALL_TOP and nothing bridges them, so the
    -- corridor stays open to the camera looking into it.
    { x0, 0, z0, x0 + out, wt, z1, UC, 0.92 },
    { x1 - out, 0, z0, x1, wt, z1, UC, 0.92 },
    { x0, 0, z0, x1, wt, z0 + out, UC, 0.92 },
    { x0, 0, z1 - out, x1, wt, z1, UC, 0.92 },
  }
  -- the haunches: a beam along the top of each long wall, oversailing into
  -- the corridor. Its SOFFIT is the surface the fittings sit on and the one
  -- the camera can see, which is the whole reason this shape and not a slab.
  --
  -- The hazard band rides just under it, proud of the wall by a hair so it
  -- is a moulding rather than a decal and catches its own edge of light.
  if long then
    concrete[#concrete + 1] =
      { x0 + out, hy, z0 + out, x0 + out + hin, hy + ht, z1 - out, UC, 1.0 }
    concrete[#concrete + 1] =
      { x1 - out - hin, hy, z0 + out, x1 - out, hy + ht, z1 - out, UC, 1.0 }
    if Underpass.SHOW_BAND then
      -- measured in from each haunch's inner lip, so the two bands stay the
      -- same distance from the corridor whatever HAUNCH_IN is set to
      local lipL, lipR = x0 + out + hin, x1 - out - hin
      band[#band + 1] =
        { lipL - bIn1, by, z0 + out, lipL - bIn0, by + bh, z1 - out, UB, 1.0 }
      band[#band + 1] =
        { lipR + bIn0, by, z0 + out, lipR + bIn1, by + bh, z1 - out, UB, 1.0 }
    end
  else
    concrete[#concrete + 1] =
      { x0 + out, hy, z0 + out, x1 - out, hy + ht, z0 + out + hin, UC, 1.0 }
    concrete[#concrete + 1] =
      { x0 + out, hy, z1 - out - hin, x1 - out, hy + ht, z1 - out, UC, 1.0 }
    if Underpass.SHOW_BAND then
      local lipN, lipF = z0 + out + hin, z1 - out - hin
      band[#band + 1] =
        { x0 + out, by, lipN - bIn1, x1 - out, by + bh, lipN - bIn0, UB, 1.0 }
      band[#band + 1] =
        { x0 + out, by, lipF + bIn0, x1 - out, by + bh, lipF + bIn1, UB, 1.0 }
    end
  end

  local glow = {}
  local fw, fl, ft = Underpass.FITTING_W, Underpass.FITTING_L, Underpass.FITTING_T
  -- One fitting per lamp site, but on BOTH haunches rather than down the
  -- middle: that is where the reference puts them, it is what makes the two
  -- walls light up instead of only the floor, and it doubles the count for
  -- free because the point lights they stand for are still the row of eight.
  for _, site in ipairs(Underpass.row(map)) do
    if long then
      local zA, zB = site.z - fl * 0.5, site.z + fl * 0.5
      glow[#glow + 1] = { x0 + out + 1, hy - ft, zA,
                          x0 + out + 1 + fw, hy, zB, UL, 1.0 }
      glow[#glow + 1] = { x1 - out - 1 - fw, hy - ft, zA,
                          x1 - out - 1, hy, zB, UL, 1.0 }
    else
      local xA, xB = site.x - fl * 0.5, site.x + fl * 0.5
      glow[#glow + 1] = { xA, hy - ft, z0 + out + 1,
                          xB, hy, z0 + out + 1 + fw, UL, 1.0 }
      glow[#glow + 1] = { xA, hy - ft, z1 - out - 1 - fw,
                          xB, hy, z1 - out - 1, UL, 1.0 }
    end
  end
  -- the LED run along each wall. A continuous line, because that is the one
  -- shape in the reference that is not repeating -- it is what gives the
  -- corridor a direction to run in. Its own list and its own mesh: it is the
  -- only cold thing down here (see LED_COLOR).
  local led = {}
  if Underpass.SHOW_STRIP then
    if long then
      local lipL, lipR = x0 + out + hin, x1 - out - hin
      led[#led + 1] =
        { lipL - sIn1, sy, z0 + out, lipL - sIn0, sy + shp, z1 - out, UL, 1.0 }
      led[#led + 1] =
        { lipR + sIn0, sy, z0 + out, lipR + sIn1, sy + shp, z1 - out, UL, 1.0 }
    else
      local lipN, lipF = z0 + out + hin, z1 - out - hin
      led[#led + 1] =
        { x0 + out, sy, lipN - sIn1, x1 - out, sy + shp, lipN - sIn0, UL, 1.0 }
      led[#led + 1] =
        { x0 + out, sy, lipF + sIn0, x1 - out, sy + shp, lipF + sIn1, UL, 1.0 }
    end
  end

  built.shell = bake(concrete)
  built.band = bake(band)
  built.glow = bake(glow)
  built.led = bake(led)
  return built
end

-- Draw the corridor's shell. Called from VoxelScene beside StreetLamps.draw,
-- and for the same reason: these are props, not terrain, so they go down
-- after the world with the voxel seams off.
function Underpass.draw(map)
  if not (Underpass.ENABLED and Underpass.matches(map)) then return end
  if not Voxel3D.available() then return end
  local tex = ensureTex()
  if not tex then return end
  local b = buildShell(map)
  -- the boxes are baked in world coordinates already, so the model matrix is
  -- identity and the sun matrix is the same one (there is no sun down here,
  -- but the argument is not optional)
  local id = Mat4.identity()
  if b.shell then
    Voxel3D.draw(b.shell, tex, id, 0, id)
  end
  if b.band then
    -- half way toward its own yellow: enough that the corridor's held-down
    -- ambient cannot swallow the paint, not so much that the band stops
    -- taking the fittings' light (see BAND_FLATTEN).
    Voxel3D.flatten(Underpass.BAND_COLOR, Underpass.BAND_FLATTEN)
    Voxel3D.draw(b.band, tex, id, 0, id)
  end
  if b.glow then
    -- flattened toward the fitting's own colour so it survives the corridor's
    -- dimmed ambient: an emissive surface that takes the scene's light is not
    -- emissive, it is a pale box.
    Voxel3D.flatten(Underpass.COLOR, Underpass.GLOW_FLATTEN)
    Voxel3D.draw(b.glow, tex, id, 0, id)
  end
  if b.led then
    -- and the cold one, its own send between the two draws. This is the
    -- whole cost of a two-colour corridor: one draw, two uniforms.
    Voxel3D.flatten(Underpass.LED_COLOR, Underpass.LED_FLATTEN)
    Voxel3D.draw(b.led, tex, id, 0, id)
  end
  -- one reset for both, not one each: leaving `ghost` set leaks the corridor's
  -- colour onto whatever the next pass draws.
  Voxel3D.flatten(nil)
end

function Underpass.invalidate()
  cache.id, cache.box = nil, nil
  release(built.shell); release(built.band)
  release(built.glow); release(built.led)
  built.id, built.shell, built.band, built.glow, built.led =
    nil, nil, nil, nil, nil
  if shellTex and shellTex ~= false and shellTex.release then
    pcall(shellTex.release, shellTex)
  end
  shellTex = nil
end

return Underpass
