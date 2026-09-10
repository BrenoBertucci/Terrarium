-- Voxel world mode: what this device can afford.
--
-- Every other module in this mod was written against a desktop GPU, where
-- the scene canvas is the window, the shadow map is 2048 texels of it, and
-- both are redrawn from scratch every frame the camera moves a quarter of a
-- world pixel. On a two-core mobile Mali that is three separate ways to
-- miss the frame at once:
--
--   FILL   the scene renders at the panel's own pixel count. A 1080p
--          phone is 2.6 megapixels, against the 23 thousand the flat 2D
--          path shades -- a hundredfold, through a shader with six
--          texture fetches in it, on geometry that leans on the depth
--          buffer instead of a y-sort and therefore overdraws freely.
--          Worse, both passes `discard`, which switches a tile-based GPU
--          out of early-Z for the whole draw: none of that overdraw is
--          rejected before it is shaded.
--
--   SUN    the shadow map's rung is picked to resolve 0.45 world pixels
--          per texel. Work that target against a phone's view size and
--          every rung below 2048 fails it, so the ladder is decorative
--          and the map is always the top one -- 4.2 million more texels,
--          again with a discarding shader, again redrawn whenever the
--          camera moves.
--
--   BAND   each of those is a full-screen render target on a memory bus
--          that has about a tenth of a desktop's headroom, and every
--          canvas switch on a tiler is a resolve and a reload.
--
-- So: two rows the player can turn down on the device, because there is no
-- benchmarking a phone from here.
--
--   RES      the divisor the 3D pass renders at before it is scaled back
--            up to the panel. This is the one that matters -- it is
--            quadratic in every one of the three costs above, so 1/2 is
--            four times less of all of it and 1/3 is nine.
--
--   SHADOWS  LOW keeps real cast shadows but on a quarter-size map, one
--            tap instead of four, no neighbour maps casting, and redrawn
--            every other frame while walking. OFF drops the sun pass
--            entirely and the mod falls back to the flat decal shadows it
--            already carries for drivers without a depth canvas. SOFT is
--            the rung ABOVE the original: everything HIGH does, plus a
--            blocker search that widens each shadow's edge by how far it
--            stands from what throws it.
--
-- Both default to the cheap end. A desktop player who installs this build
-- sets them back to FULL / HIGH and gets the original mod exactly: at
-- scale 1 the render path is the same canvas it always was with no extra
-- blit, and at HIGH every constant below is the number it used to be. FULL
-- is one step off the default rather than three, because on a desktop it is
-- where most people are going.
--
-- ------- AND THEN A PHONE ACTUALLY RAN IT
--
-- Everything above was written blind, and the sentence it turns on -- "there
-- is no benchmarking a phone from here" -- was true and is the reason the
-- guesses were wrong.  A Poco X7 (Mali-G615 MC2, 2712x1220) ran the VOXEL
-- row at about one frame a second on the default rungs.  Three findings, in
-- order of how much they cost:
--
--   * Every render target in the mod was SEVEN TIMES the pixels it asked
--     for, because love.graphics.newCanvas(w, h) multiplies by the display
--     density and Android's is 2.625.  RES divided a number that was then
--     multiplied back twice.  See lib/RenderTarget.lua.
--   * ShadowMap.available() resized the shadow canvas every frame, which
--     destroyed and rebuilt two render targets per frame AND defeated the
--     every-other-frame deferral described above -- the sun pass ran on
--     every frame, including while standing still.
--   * The RES row is a DIVISOR, and a divisor is not a cost.  1/2 of the
--     window this was written on is 332k pixels; 1/2 of that phone's panel
--     is 827k.  The same rung, two and a half times the work.
--
-- So RES gained AUTO (lib/AutoQuality.lua): a pixel budget for the first
-- frame and a governor after it, which is the only honest answer to a
-- device that cannot be measured from here -- it measures itself.  Every
-- other row still means exactly what it meant, and a player who picks a
-- rung by hand is never overridden.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local AutoQuality = V.require("AutoQuality")
local Device = V.require("Device")

local Quality = {}

-- AUTO is values[1], so it is what a player who has never touched this row
-- gets and what an unreadable stored value falls back to.  It is not a
-- fifth constant: it is a pixel budget and a governor (lib/AutoQuality.lua),
-- because the same divisor is a different amount of work on every panel --
-- 1/2 of the 1536x864 window this was written on is 332k pixels and 1/2 of
-- the Poco X7's 2712x1220 is 827k, two and a half times as many through a
-- GPU with a fraction of the fill rate.
--
-- 1/6 and 1/8 are new rungs below the old floor.  1/4 used to be the bottom
-- and on a 3.31 Mpx panel it is still 207k pixels; 1/8 is 51k, which at a
-- phone's fitScale is about one canvas texel per world pixel and therefore
-- the point below which there is nothing left to save.  A player on a
-- device that needs them can now reach them by hand, and AUTO can reach
-- them without being asked.
--
-- The order of the rest is unchanged, so every value already in a save
-- still resolves to itself and cycling still walks the same direction.
Quality.setting = ModSetting.new("renderScale", "RES",
                                 { "auto", 2, 1, 3, 4, 6, 8 },
                                 { "AUTO", "1/2", "FULL", "1/3", "1/4",
                                   "1/6", "1/8" })

-- SOFT is a fourth rung above HIGH rather than a replacement for it: it
-- keeps everything HIGH does -- the big map, the neighbours casting, a
-- redraw every frame -- and changes only how the main pass READS the map,
-- from a fixed four-tap box to a blocker search and a filter sized by what
-- it finds (see SUN_SOFT in the scene shader). Twelve fetches against four,
-- which is a desktop's price and not a phone's, so it sits at the top of
-- the ladder and nothing arrives at it by default.
Quality.shadowSetting = ModSetting.new("shadowQuality", "SHADOWS",
                                       { "low", "off", "high", "soft" },
                                       { "LOW", "OFF", "HIGH", "SOFT" })

-- ------- HOW MUCH AIR THERE IS, ON ITS OWN ROW
--
-- Every particle budget in this mod used to hang off RES: the wind field
-- through windStreaks below, the rain's shafts through Weather's own
-- ladder. Which meant there was no way to ask for MORE weather without
-- also asking the grass, the shadows, the fog and the cloud raymarch to
-- get heavier -- and no way to cut the air without cutting the picture.
--
-- ------- IT IS A MULTIPLIER, NOT A REPLACEMENT
--
-- The obvious design is for this row to name the counts outright. It is
-- the wrong one: the counts that exist were tuned per RES rung for good
-- reasons (a quarter-resolution frame does not want a full-resolution
-- field), and replacing them would hand everyone at 1/3 a field sized for
-- FULL the first time they launched.
--
-- So ON is 1.0 and reproduces exactly what is there today at every RES
-- rung, and the row is a second axis over the top of it. Somebody at RES
-- 1/2 who wants a squall gets four times the air without the grass or the
-- shadow map noticing, which is the thing that could not be done before.
--
-- MAX is deliberately more than the machine this was written on enjoys.
-- That is what a MAX rung is for -- there is no frame-rate floor this has
-- to clear, because frame time on that machine is not repeatable enough to
-- define one (two runs of the same probe disagreed by five to seven fps).
-- What IS repeatable is the count, so the rungs are defined in counts.
Quality.particleSetting = ModSetting.new("particleFx", "PFX",
                                         { 1, 0, 2, 3 },
                                         { "ON", "LOW", "HIGH", "MAX" })

Quality.PARTICLE_MUL = { [0] = 0.40, [1] = 1.00, [2] = 2.00, [3] = 4.00 }

-- The multiplier every particle budget in the mod passes through. Read
-- from inside the render path like the rest of this file, so it is a pcall
-- and a clamp rather than a plain get.
function Quality.particles()
  local ok, v = pcall(Quality.particleSetting.get, Quality.particleSetting)
  local n = (ok and tonumber(v)) or 1
  return Quality.PARTICLE_MUL[n] or 1
end

-- Read through pcall and clamped, because these are consulted from inside
-- the render path: a setting that could throw there would take the frame
-- with it, and the whole contract of this mod is that it falls back rather
-- than errors.
-- True while the RES row is on AUTO, which is the only state in which
-- anything is allowed to move the rung on its own.
function Quality.autoScale()
  local ok, v = pcall(Quality.setting.get, Quality.setting)
  return ok and v == "auto"
end

function Quality.scale()
  local ok, v = pcall(Quality.setting.get, Quality.setting)
  if ok and v == "auto" then
    local okA, d = pcall(AutoQuality.divisor)
    if okA and type(d) == "number" then v = d else v = 2 end
  end
  local n = tonumber(v) or 2
  if n < 1 then n = 1 end
  if n > 8 then n = 8 end
  return math.floor(n)
end

-- One rendered frame of the 3D pass, for the governor.  A no-op unless the
-- row is on AUTO, so a player who picked a rung by hand is never overridden
-- and never pays for the measurement.
function Quality.frame()
  if not Quality.autoScale() then return end
  pcall(AutoQuality.frame)
end

-- The window changed size (or the mod hot-reloaded): the pixel budget's
-- answer is different now and a rung that failed at the old size says
-- nothing about the new one.
function Quality.invalidate()
  pcall(AutoQuality.invalidate)
end

-- One line for the GPU report and the probes.
function Quality.report()
  local okD, d = pcall(Device.report)
  local okA, a = pcall(AutoQuality.report)
  local lines = { okD and d or "device: ?" }
  lines[#lines + 1] = ("scale:    1/%d  %s")
    :format(Quality.scale(), okA and a or "(auto unavailable)")
  return table.concat(lines, "\n")
end

function Quality.shadows()
  local ok, v = pcall(Quality.shadowSetting.get, Quality.shadowSetting)
  if ok and (v == "off" or v == "high" or v == "low" or v == "soft") then
    return v
  end
  return "low"
end

function Quality.shadowsOff()
  return Quality.shadows() == "off"
end

-- Four shadow taps or one. The 2x2 box filter is what turns the map's
-- texel staircase into a one-pixel soft edge, which is worth four texture
-- fetches per fragment on a desktop and is not worth them here -- at 1/2
-- render scale that edge is landing on half a display pixel anyway.
-- Everything on this side of the ladder: the big map, the loose target, the
-- neighbours casting, a redraw every frame. SOFT is HIGH plus a filter, so
-- it answers yes here too and every consumer below is unchanged by it.
function Quality.softShadows()
  local v = Quality.shadows()
  return v == "high" or v == "soft"
end

-- And the filter itself: the blocker search that sizes a shadow's edge by
-- how far it is from the thing throwing it. Only the top rung.
function Quality.pcss()
  return Quality.shadows() == "soft"
end

-- The rung ladder and the world-pixels-per-texel target ShadowMap.fit
-- picks from. The low ladder is the high one divided by two throughout:
-- a quarter of the texels, and a target loose enough that the smallest
-- rung is actually reachable on a phone-shaped view instead of the fit
-- falling through to the top of the ladder every time.
function Quality.shadowSizes()
  if Quality.softShadows() then
    -- HIGH and SOFT are the DESKTOP rungs, and on a phone-shaped view the
    -- fit lands on the top of that ladder every time -- 2048 squared is
    -- 4.2 megatexels of colour plus the same again of depth, cleared and
    -- filled with the whole map's geometry every frame.  MOBILE.md
    -- describes fixing exactly this and only fixed it for LOW.
    --
    -- On a tiler the top rung is capped.  HIGH still means what it says --
    -- the neighbours cast, the redraw is every frame, and SOFT still gets
    -- its blocker search -- it just stops meaning "four megatexels", which
    -- is not a thing this class of GPU can do sixty times a second.
    if Device.mobile() then return { 768, 1024, 1280 } end
    return { 1024, 1536, 2048 }
  end
  return { 512, 768, 1024 }
end

function Quality.shadowTarget()
  return Quality.softShadows() and 0.45 or 1.4
end

-- How many frames a wanted shadow redraw may be deferred. The map is
-- already reused whole while nothing moves (ShadowMap.stale); this is
-- about WALKING, where the signature changes every frame and the sun pass
-- redraws the world every frame with it. At 2 the shadows are one frame
-- stale half the time, which is not a thing anyone has ever seen, and the
-- pass costs half of what it did.
function Quality.shadowInterval()
  return Quality.softShadows() and 1 or 2
end

-- How many stars the night sky may paint (lib/Sky.lua). They are plain
-- cell rectangles on the sky's own grid -- the same idiom, and roughly the
-- same count, as the sun and moon discs already cost -- so this is a draw
-- call budget and nothing else: no target, no shader, no pass.
--
-- Hung on the RENDER SCALE rather than on the shadow ladder, because that
-- is the rung that actually says how much frame there is to fill: at 1/4 a
-- star is a quarter of the cells it is at FULL and a full field reads as
-- noise as well as costing more than it is worth. Zero is never returned --
-- a night with no stars at all is the thing this exists to end -- so the
-- cheapest rung still gets a sky, just a sparser one.
function Quality.starCount()
  local s = Quality.scale()
  if s <= 1 then return 96 end
  if s == 2 then return 72 end
  if s == 3 then return 48 end
  return 32
end

-- Low fog bands (Sky.paintFog). RES values: 1=FULL, 2=1/2, 3=1/3, 4=1/4
-- (same as starCount — higher number is the cheaper phone rung).
-- 1/4 offs fog entirely; 1/3 is thin; FULL and 1/2 get the full stack.
function Quality.fogBands()
  local s = Quality.scale()
  if s >= 4 then return 0 end
  if s == 3 then return 2 end
  return 4
end

-- Rainbow arc after rain. Off only at 1/4 RES.
function Quality.rainbow()
  return Quality.scale() < 4
end

-- Volumetric cloud raymarch steps inside the sky shader (Sky.lua).
-- Higher RES scale number = cheaper phone rung. 0 turns clouds off so the
-- sky rectangle stays a handful of ALU ops on the bottom rung.
function Quality.cloudSteps()
  local s = Quality.scale()
  if s >= 4 then return 0 end
  if s == 3 then return 4 end
  if s == 2 then return 6 end
  return 8
end

-- ------- how much grass physics this device can afford
--
-- The grass pass is the heaviest VERTEX work in the mod, and unlike every
-- other cost on this page it does not shrink with RES: the scene canvas
-- gets smaller, the tuft count does not. A route's grass mesh is tens of
-- thousands of vertices and each one was, briefly, paying for ten sines, a
-- square root and an eight-slot crush loop -- which is a desktop's price
-- charged to a machine that picked 1/2 because it could not afford a
-- desktop's price anywhere else.
--
-- So the physics comes in tiers, and the tier rides the same RES rung
-- everything else here does:
--
--   0  (1/4, 1/3)  the travelling wave and nothing else. Grass still bends,
--                  still plants its base, still parts under a foot. What
--                  goes is everything that is texture rather than motion.
--   1  (1/2)       per-tuft stiffness and the squall front -- the two that
--                  make a meadow read as many plants in moving air. Still
--                  no flutter harmonic, no cross-axis drift, no tip bob.
--   2  (FULL)      all of it.
--
-- Tier 1 is the default rung and it is the one that had to be genuinely
-- cheap, not merely cheaper.
function Quality.grassDetail()
  local s = Quality.scale()
  if s >= 3 then return 0 end
  if s == 2 then return 1 end
  return 2
end

-- How many crush slots the grass shader loops over. The loop is per VERTEX,
-- so every slot is paid by the whole meadow whether or not anybody is
-- standing in it -- eight is worth it on a desktop and is most of the
-- regression on a phone. Three still holds the player plus two, and the
-- trail simply keeps fewer crumbs (see Grass3D.crushFrame).
-- When the crush map is on (detail >= 1), these slots are live feet only
-- -- the trail has left the array. The numbers stay so a driver that
-- cannot make the image still degrades to the old packed trail.
function Quality.crushSlots()
  local d = Quality.grassDetail()
  if d <= 0 then return 3 end
  if d == 1 then return 5 end
  return 8
end

-- Whether the walked trail lives on the world-space field rather than in
-- leftover crush[] slots. Detail 0 is the uniform path, unchanged.
function Quality.crushMap()
  return Quality.grassDetail() >= 1
end

-- Streaks in the air (lib/WindFX). A draw-call budget like starCount: each
-- one is two projections and a line, and at 1/4 the frame is 23 thousand
-- pixels and a streak is a smear. Zero there.
function Quality.windStreaks()
  local s = Quality.scale()
  local base
  if s >= 4 then base = 0
  elseif s == 3 then base = 22
  elseif s == 2 then base = 48
  else base = 110 end
  -- ------- AND THEN THE PFX ROW, WHICH IS THE ONE ABOUT THE AIR
  --
  -- A multiplier rather than a replacement, so ON is what was always here.
  -- The floor of one at anything above LOW matters: at RES 1/4 the base is
  -- zero, and a player who has deliberately turned the air UP should get
  -- air, not a row that does nothing because a different row said no.
  local m = Quality.particles()
  local n = math.floor(base * m)
  if m > 0.5 and n < 1 and s < 4 then n = 1 end
  return n
end

-- Whether the neighbouring maps cast into the shadow map. They are drawn
-- in the scene either way; this is only about whether their geometry is
-- also rasterised into the sun's own pass, which doubles or triples the
-- caster count for shadows that mostly fall off the edge of the view.
function Quality.neighbourShadows()
  return Quality.softShadows()
end

return Quality
