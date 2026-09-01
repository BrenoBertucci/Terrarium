-- The sprite-sheet effects, and the grid each one is laid out on.
--
-- GENERATED from the packs' own filenames -- SpriteMancer writes the frame
-- size into the sheet name (Effect_BigHit_1_557x553.png), so the grid is
-- read off the file rather than counted by hand, and then re-derived after
-- the frames were resampled down to something a laptop GPU should be asked
-- to fetch. See assets/vfx/LICENSE.md for where they came from.
--
-- `frames` is cols * rows. Some sheets end with a blank cell or two, which
-- costs those cells' worth of time at the tail of the animation and nothing
-- else -- an empty frame draws nothing. Trimming them would mean deciding
-- per sheet where the animation really ends, which is a judgement the file
-- cannot make for itself.
--
-- `fps` is the rate the pack authored at (the 30fps folder). The player
-- advances on real time, so this is not tied to the game's frame rate.
--
-- The bt_* keys are authored hard-pixel sheets (tools/make_battle_sprites.py),
-- 64x64, 8x2, 16 frames at 20 fps. They are the battle HitFX vocabulary;
-- the eight OGA keys above them stay for the overworld IMPACT demo.

return {
  { key = "bighit",          file = "bighit.png",
    frameW = 128, frameH = 127, cols = 6, rows = 5, frames = 30,
    fps = 30 },
  { key = "charged",         file = "charged.png",
    frameW = 111, frameH = 128, cols = 7, rows = 6, frames = 42,
    fps = 30 },
  { key = "electricshield",  file = "electricshield.png",
    frameW = 128, frameH = 128, cols = 6, rows = 5, frames = 30,
    fps = 30 },
  { key = "explosion",       file = "explosion.png",
    frameW = 128, frameH = 128, cols = 6, rows = 5, frames = 30,
    fps = 30 },
  { key = "impact",          file = "impact.png",
    frameW = 124, frameH = 128, cols = 6, rows = 5, frames = 30,
    fps = 30 },
  { key = "powerchords",     file = "powerchords.png",
    frameW = 128, frameH =  87, cols = 6, rows = 5, frames = 30,
    fps = 30 },
  { key = "puffandstars",    file = "puffandstars.png",
    frameW = 120, frameH = 109, cols = 7, rows = 6, frames = 42,
    fps = 30 },
  { key = "smallhit",        file = "smallhit.png",
    frameW = 128, frameH = 127, cols = 6, rows = 5, frames = 30,
    fps = 30 },

  { key = "bt_charge", file = "bt_charge.png",
    frameW = 64, frameH = 64, cols = 8, rows = 2, frames = 16, fps = 20 },
  { key = "bt_slash",  file = "bt_slash.png",
    frameW = 64, frameH = 64, cols = 8, rows = 2, frames = 16, fps = 20 },
  { key = "bt_bolt",   file = "bt_bolt.png",
    frameW = 64, frameH = 64, cols = 8, rows = 2, frames = 16, fps = 20 },
  { key = "bt_beam",   file = "bt_beam.png",
    frameW = 64, frameH = 64, cols = 8, rows = 2, frames = 16, fps = 20 },
  { key = "bt_burst",  file = "bt_burst.png",
    frameW = 64, frameH = 64, cols = 8, rows = 2, frames = 16, fps = 20 },
  { key = "bt_spray",  file = "bt_spray.png",
    frameW = 64, frameH = 64, cols = 8, rows = 2, frames = 16, fps = 20 },
  { key = "bt_shards", file = "bt_shards.png",
    frameW = 64, frameH = 64, cols = 8, rows = 2, frames = 16, fps = 20 },
  { key = "bt_spiral", file = "bt_spiral.png",
    frameW = 64, frameH = 64, cols = 8, rows = 2, frames = 16, fps = 20 },
  { key = "bt_leaves", file = "bt_leaves.png",
    frameW = 64, frameH = 64, cols = 8, rows = 2, frames = 16, fps = 20 },
  { key = "bt_fist",   file = "bt_fist.png",
    frameW = 64, frameH = 64, cols = 8, rows = 2, frames = 16, fps = 20 },
  { key = "bt_wisp",   file = "bt_wisp.png",
    frameW = 64, frameH = 64, cols = 8, rows = 2, frames = 16, fps = 20 },
  { key = "bt_arc",    file = "bt_arc.png",
    frameW = 64, frameH = 64, cols = 8, rows = 2, frames = 16, fps = 20 },
}
