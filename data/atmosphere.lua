-- Per-map AIR, for the SM64 camera.
--
-- The free-roam orbit gets its haze from the hour (lib/Aerial.lua). A
-- placed camera -- which the SM64 camera is, every frame it is on --
-- declines that haze wholesale (see the note in Voxel3D's applyCamera:
-- a staged battle's framing would put the horizon's fog across the middle
-- of an arena). This table is the way back in for the maps that WANT air,
-- and wanted more of it than the hour gives: the entry rides the camera
-- (MarioCam.camera().atmo) into the same shader uniforms the hourly haze
-- uses.
--
-- Fields, all in world pixels and 0..1:
--   color     the haze itself. This is also the palette statement: a cold
--             violet reads as mourning without touching a single tile.
--   near      how far past the player the air begins
--   span      how many pixels until it reaches full strength
--   strength  the cap -- 1 would dissolve the horizon entirely
--
-- OUTDOOR by default: MarioCam attaches an entry to an interior only when
-- the entry says `indoor = true` -- that interior's own air, never the
-- town's weather leaking in.
local TOWER_CALM = {
  -- the tower's lower floors: a dark haze, so the far wall of the crypt
  -- sinks back and the room has depth (lib/Crypt.lua)
  color = { 0.10, 0.09, 0.13 }, near = 190, span = 300, strength = 0.42,
  indoor = true,
}
local TOWER_HAUNTED = {
  -- the haunted floors: the town's violet, inside, heavier
  color = { 0.34, 0.28, 0.46 }, near = 170, span = 280, strength = 0.55,
  indoor = true,
}
return {
  LAVENDER_TOWN = {
    -- the town of graves: violet air, close and heavy for a town, so the
    -- far streets grey out the way the radio tower's silhouette should
    color = { 0.58, 0.55, 0.70 },
    near = 70,
    span = 210,
    strength = 0.62,
  },
  POKEMON_TOWER_1F = TOWER_CALM,
  POKEMON_TOWER_2F = TOWER_CALM,
  POKEMON_TOWER_3F = TOWER_HAUNTED,
  POKEMON_TOWER_4F = TOWER_HAUNTED,
  POKEMON_TOWER_5F = TOWER_HAUNTED,
  POKEMON_TOWER_6F = TOWER_HAUNTED,
  POKEMON_TOWER_7F = {
    color = { 0.22, 0.17, 0.26 }, near = 180, span = 300, strength = 0.46,
    indoor = true,
  },
}
