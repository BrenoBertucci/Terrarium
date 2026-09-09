-- Authored camera shots, for lib/MarioCam.lua.
--
-- This file is the answer to the most repeated lesson in the Super Mario 64
-- camera writeup: no generic algorithm beats a HAND-PLACED camera in the ten
-- percent of cases that are actually hard, and those ten percent are the
-- ones the player remembers. SM64 has two mechanisms for it -- special
-- collision surfaces that command the camera (SURFACE_CAMERA_ROTATE_LEFT and
-- friends) and per-level trigger volumes (`struct CameraTrigger`, the
-- sCamBBH / sCamCastle / sCamRR arrays) -- and between them they are why
-- walking through the gate at Bob-omb Battlefield swings the camera to frame
-- the path up the mountain. There is no cleverness behind that moment. A
-- person painted a triangle on the floor.
--
-- A Gen 1 map has no camera surfaces to paint, so what is left is the volume:
-- a box the player walks into that names a mode for as long as they are in
-- it. That is this table.
--
-- ------- the shape of an entry
--
-- Keyed by map id (the `id` in data/generated/maps.lua -- "PALLET_TOWN",
-- "CELADON_CITY", "ROUTE_1"). Each map holds a LIST of boxes, tested in
-- order, first match wins:
--
--   x, z      the box's centre, in WORLD PIXELS (a cell is 16, a block 32)
--   bx, bz    its half-extents, world pixels. Default 32, i.e. two cells.
--   yaw       optional, in the s16 units MarioCam uses (MarioCam.degrees is
--             not exported; 0x4000 is a quarter turn). Rotates the player's
--             offset before the box is tested, so a diagonal corridor does
--             not have to be squared up to the world axes -- the same
--             `boundsYaw` the decomp's CameraTrigger carries, and it is here
--             for the same reason.
--   mode      which camera to run inside it. One of:
--               "radial"  the orbit around the map's centre (the default)
--               "close"   the same, pulled in -- what interiors get
--               "eight"   yaw locked to 45-degree detents; for a corridor
--                         or a bridge, where a swinging camera makes a line
--                         hard to judge
--               "behind"  over the shoulder, following the facing
--               "fixed"   a placed camera that only turns to follow
--   focY      "fixed" only: how far above the floor it looks, world pixels
--
-- A "fixed" entry also needs where the camera STANDS, in world pixels, and
-- these are deliberately NOT called x/y/z: those are the box, and the eye is
-- a different point. An entry missing camX simply falls back to the orbit.
--
--   camX, camY, camZ      default camY 64
--
-- ------- the cinematic fields, all optional
--
--   frames    how many frames (at 30fps) the transition into this shot
--             takes. Default 30; doors and interiors read better at 12.
--             The lens (below) moves at the same pace, so the arc and the
--             lens arrive together.
--   fov       the shot's lens, in DEGREES. Approached gradually on the way
--             in and released back to 45 (SM64's own default) on the way
--             out -- the SET-vs-APP lesson: instant is a cut, gradual is
--             an expression, and a floor trigger is not a cut. Clamped to
--             20..60 so a typo cannot fisheye the world.
--   zoom      pins the camera DISTANCE, world pixels at the 144-line frame
--             (the scale ZOOMS speaks: close 100, default 175, far 250).
--             Clamped 40..400.
--   pitch     pins the camera height as DEGREES ABOVE THE HORIZON (the
--             convention the SM64 doc uses), overriding the VOXEL ladder.
--             Clamped 4..87. Low numbers are the dramatic ones.
--   flat      true switches the world curve OFF for this shot, the same
--             way BattleCam declines it. For INTERIOR shots, where the
--             bend reads as standing on a small planet and entry is
--             always a map cut. On an outdoor box the on/off seam plays
--             mid-walk as a visible pop -- do not use it there.
--
-- A shot that pins zoom or pitch -- or stands "fixed" -- has taken the
-- framing from the player, and the framing keys say so out loud: q/e/f
-- inside such a shot answer with the Denied buzz instead of going quiet.
-- A shot that only names a mode leaves every key working.
--
-- ------- and why it ships empty
--
-- Every map without an entry gets the generic camera, which is the same
-- arrangement SM64 has in the parts of a level nobody placed a trigger in --
-- most of it. Shipping speculative shots would be worse than shipping none:
-- an authored camera is only worth having where somebody has LOOKED at it,
-- and a bad one is more jarring than an ordinary one because it is confident.
--
-- So this is the surface, documented and live, with nothing in it yet. Add a
-- box, walk into it, look. The example below is commented out and is there
-- to be copied.

-- ------- LAVENDER TOWN, the pilot (2026-08-27)
--
-- Every entry below was authored by LOOKING: candidate poses photographed
-- in the running game (tests/lavender_author*.lua), the frames read, the
-- losers cut. tests/lavender_shots_probe.lua re-verifies all of them --
-- shot acquired, lens landed, player on screen, sightline clear.
return {
  LAVENDER_TOWN = {
    -- The tower's front door: the player dead centre in the ledge-lined
    -- approach, the lantern at frame left, the tower base wall to wall
    -- above -- looming by PROXIMITY, not by a tilted lens (the camera
    -- stands on the street two cells south; a true contra-plongee shot
    -- from under the eaves photographed the model's underside). Flat,
    -- because the frame is all tower and the curve only contributed
    -- far-off cards floating in the sky band.
    -- (the box runs the doorway approach, rows 5..8 -- wide enough that a
    -- stray step does not blink the shot off, and STOPPING one row short
    -- of where the camera itself stands: a box that reached the camera's
    -- own row put a drifted player behind the lens)
    { x = 232, z = 112, bx = 24, bz = 28, mode = "fixed",
      camX = 232, camY = 40, camZ = 156, focY = 26,
      fov = 46, frames = 24, flat = true },
    -- The west arrival (Route 8): a fixed observer just inside town,
    -- slightly high, the plaza and the Poke Center facade filling the
    -- frame as the player walks in. Keeps the world curve: the box edge
    -- is crossed mid-walk, and the curve popping on and off would show.
    { x = 20, z = 112, bx = 28, bz = 56, mode = "fixed",
      camX = 24, camY = 90, camZ = 208, focY = 14, frames = 40 },
  },

  -- ------- the tower, floor by floor
  --
  -- One pattern, Big Boo's Haunt style: a fixed camera high at the south
  -- centre, the whole maze of graves legible in one look, the camera only
  -- turning to follow. Flat -- indoors the curve reads as standing on a
  -- small planet, and entry is always a map cut so the seam never shows.
  -- 6F drops lower and tighter (the Marowak floor should press in); 7F
  -- reads the corridor to Mr. Fuji as the procession it is.
  -- ------- the Poke Mart, inside (lib/ShopKit.lua, lib/Shop.lua)
  --
  -- The dollhouse cut only means anything under an authored fixed shot:
  -- under the player-driven orbit these maps got by default, a room cut
  -- away toward the south is a sawn-off wall as soon as the camera swings
  -- north of it. So the shot comes first and the geometry is built to it.
  --
  -- MEASURED AGAIN at fov 30: the content ran from 23.5 % of the height
  -- down to the very bottom edge -- a quarter of the frame dead at the top
  -- and the entrance sliced off at the bottom. 33 gives the height back and
  -- focY drops from 10 to -4. Measured after the first try at 4: still
  -- 22 % of the height was dead sky above the room, so the eye tips down a
  -- further two degrees. focY is the point the camera LOOKS AT, in the same
  -- world y as everything else, and below the floor is a legal place to
  -- aim it -- the room fills the frame, not the void over it.
  --
  -- MEASURED: at fov 38 the room filled about half the frame's width and
  -- 61 % of the screen was the black surround -- the largest single share
  -- of any pixel in the shot, and a diorama sitting in a void reads as a
  -- model on a table rather than as a place. The lens is 30 instead: same
  -- eye, same pitch, same cut -- only the field narrows, by 38/30 = 1.27x,
  -- which puts the room at about three quarters of the width and still
  -- leaves a sixth of the height as margin for the walls' coping.
  --
  -- The room is 128x128 world px, centre (64, 64). Framing eight cells
  -- plus a margin in a 38-degree lens needs 72 / tan(19) = 209 px of
  -- distance; held at the Tower's own pitch that puts the eye at
  -- z = 64 + 209*cos(27) = 248 and y = 10 + 209*sin(27) = 104. Eye to
  -- focus is then dy 94 over dz 184, so the pitch is atan(94/184) = 27.1
  -- degrees -- the same family as the Tower's floors, and the number the
  -- cut is derived from (k = tan 27.1 = 0.511: one voxel of height hides
  -- 1.96 world px of floor behind it). See
  -- assets/docs/shop/ART_DIRECTION.md.
  --
  -- All eight town Marts are the same room, tile for tile, so they share
  -- one shot. Celadon's ground floor is a different plan on a different
  -- tileset and gets the same camera only because the framing suits it.
  VIRIDIAN_MART = {
    { x = 64, z = 64, bx = 64, bz = 64, mode = "fixed",
      camX = 64, camY = 104, camZ = 248, focY = -4,
      fov = 33, frames = 12, flat = true },
  },
  PEWTER_MART = {
    { x = 64, z = 64, bx = 64, bz = 64, mode = "fixed",
      camX = 64, camY = 104, camZ = 248, focY = -4,
      fov = 33, frames = 12, flat = true },
  },
  CERULEAN_MART = {
    { x = 64, z = 64, bx = 64, bz = 64, mode = "fixed",
      camX = 64, camY = 104, camZ = 248, focY = -4,
      fov = 33, frames = 12, flat = true },
  },
  LAVENDER_MART = {
    { x = 64, z = 64, bx = 64, bz = 64, mode = "fixed",
      camX = 64, camY = 104, camZ = 248, focY = -4,
      fov = 33, frames = 12, flat = true },
  },
  VERMILION_MART = {
    { x = 64, z = 64, bx = 64, bz = 64, mode = "fixed",
      camX = 64, camY = 104, camZ = 248, focY = -4,
      fov = 33, frames = 12, flat = true },
  },
  CELADON_MART_1F = {
    { x = 64, z = 64, bx = 64, bz = 64, mode = "fixed",
      camX = 64, camY = 104, camZ = 248, focY = -4,
      fov = 33, frames = 12, flat = true },
  },
  FUCHSIA_MART = {
    { x = 64, z = 64, bx = 64, bz = 64, mode = "fixed",
      camX = 64, camY = 104, camZ = 248, focY = -4,
      fov = 33, frames = 12, flat = true },
  },
  SAFFRON_MART = {
    { x = 64, z = 64, bx = 64, bz = 64, mode = "fixed",
      camX = 64, camY = 104, camZ = 248, focY = -4,
      fov = 33, frames = 12, flat = true },
  },
  CINNABAR_MART = {
    { x = 64, z = 64, bx = 64, bz = 64, mode = "fixed",
      camX = 64, camY = 104, camZ = 248, focY = -4,
      fov = 33, frames = 12, flat = true },
  },

  POKEMON_TOWER_1F = {
    { x = 160, z = 144, bx = 160, bz = 144, mode = "fixed",
      camX = 160, camY = 150, camZ = 420, focY = 8,
      fov = 38, frames = 12, flat = true },
  },
  POKEMON_TOWER_2F = {
    { x = 160, z = 144, bx = 160, bz = 144, mode = "fixed",
      camX = 160, camY = 150, camZ = 420, focY = 8,
      fov = 38, frames = 12, flat = true },
  },
  POKEMON_TOWER_3F = {
    { x = 160, z = 144, bx = 160, bz = 144, mode = "fixed",
      camX = 160, camY = 150, camZ = 420, focY = 8,
      fov = 38, frames = 12, flat = true },
  },
  POKEMON_TOWER_4F = {
    { x = 160, z = 144, bx = 160, bz = 144, mode = "fixed",
      camX = 160, camY = 150, camZ = 420, focY = 8,
      fov = 38, frames = 12, flat = true },
  },
  POKEMON_TOWER_5F = {
    { x = 160, z = 144, bx = 160, bz = 144, mode = "fixed",
      camX = 160, camY = 150, camZ = 420, focY = 8,
      fov = 38, frames = 12, flat = true },
  },
  POKEMON_TOWER_6F = {
    { x = 160, z = 144, bx = 160, bz = 144, mode = "fixed",
      camX = 160, camY = 90, camZ = 380, focY = 8,
      fov = 38, frames = 12, flat = true },
  },
  POKEMON_TOWER_7F = {
    { x = 160, z = 144, bx = 160, bz = 144, mode = "fixed",
      camX = 192, camY = 110, camZ = 400, focY = 8,
      fov = 38, frames = 12, flat = true },
  },
}
