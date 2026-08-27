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
-- OUTDOOR ONLY, by construction: MarioCam attaches an entry only when the
-- map is outdoors, so an interior never inherits the town's weather.
return {
  LAVENDER_TOWN = {
    -- the town of graves: violet air, close and heavy for a town, so the
    -- far streets grey out the way the radio tower's silhouette should
    color = { 0.58, 0.55, 0.70 },
    near = 70,
    span = 210,
    strength = 0.62,
  },
}
