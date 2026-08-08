-- Voxel world mode: aerial perspective -- the far ground going to haze.
--
-- Air is not clear. Look down a real valley and the far wall is paler,
-- flatter and bluer than the near one, because a few kilometres of
-- atmosphere have scattered their own colour in between. That single cue
-- is most of how a picture says HOW FAR, and until this file the diorama
-- did not have it: a tree at the map edge was drawn with exactly the
-- contrast of the tree the player is standing next to, and the eye reads
-- equal contrast as equal distance. A world where everything is the same
-- distance away is a world the size of one screen -- which is the whole of
-- why a small map read small.
--
--     rgb' = mix(rgb, haze, t(d))
--
-- and that is the effect. `haze` is not a colour of this file's choosing:
-- it is the sky's own palest band (Sky.haze, the same value beginScene
-- CLEARS the frame to), so the far ground does not fade toward some grey
-- of its own -- it fades toward the exact pixel the sky behind it is
-- painted with, and the horizon join has nothing to give it away. At dusk
-- the distance goes gold because the sky did; at midnight it goes navy.
-- Nothing here knows what time it is.
--
-- MEASURED FROM THE EYE, which cost a rewrite to learn. The first cut
-- measured from the camera's FOCUS -- the player -- on the argument that
-- the focus holds still while the camera orbits, so a pitch tween could
-- not slide the haze across the ground, and that it put this file on the
-- same anchor as WorldCurve. It is wrong, and the probe said so in one
-- line: at the 75-degree rung it hazed the BOTTOM of the frame harder
-- than the tree line. The camera down there is looking from low and far
-- south, so the ground at the bottom of the screen -- the nearest thing in
-- the picture, the tile the player is standing on the edge of -- is a long
-- way south of the player in world XZ, and a focus-anchored ramp fogs it
-- before it fogs anything actually distant. Air does not work that way and
-- neither does the eye: haze is the length of the air path to the CAMERA.
--
-- IN VIEW-HEIGHTS PAST THE PLAYER, for the reason the curve is measured
-- that way: a rung has to look the same at every zoom. `NEAR` and `FAR`
-- below are extra path length beyond the camera's own distance to the
-- player, in units of the view's height -- Voxel3D adds that distance
-- before sending the range. Without the offset the whole first view-height
-- of the ramp would be spent between the camera and the player, where
-- there is nothing to draw.
--
-- AND IT IS CEL, not a gradient. A smooth ramp is the one thing this
-- renderer never draws; it would also band on its own, since the palette
-- it is mixing toward has four colours in it. So the amount is quantised
-- to hard rungs and the rung edge is broken with the same per-world-pixel
-- grain the snow uses -- a dithered boundary anchored in world space,
-- which does not crawl when the camera pans.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local Aerial = {}

Aerial.KEY = "haze"
Aerial.LABEL = "V-HAZE"

-- Where the haze begins and where it tops out, in VIEW-HEIGHTS of extra
-- path length past the player.
--
-- The first numbers here were 0.90 and 2.60, inherited from WorldCurve's
-- own calibration note -- that the far edge of visible ground sits a
-- little over two view-heights out. That note is about the ground PLANE,
-- which runs all the way to the vanishing line in the projection. It is
-- not about the ground that is DRAWN, which stops at the border trees, and
-- the two are nowhere near each other: the probe measures the drawn world
-- ending about 140 pixels SHORT of its own horizon row, with most of the
-- frame above it empty sky. At 0.90 the haze started past everything there
-- was and the far band moved by less than the wind noise.
--
-- These are what tests/aerial_probe.lua's sweep settled on instead. Its
-- ladder, at the top rung, on ROUTE_1 at the 75-degree camera -- the far
-- band is the border tree line, the mid band is the walkable ground
-- between it and the player, and the noise floor from an OFF/OFF pair is
-- 1.6% far, 0.3% mid:
--
--     0.10 .. 0.45     far +27.8%     mid  +0.7%
--     0.15 .. 0.55     far +18.0%     mid  +0.0%      <- this
--     0.20 .. 0.60     far +13.6%     mid  +0.1%
--     0.30 .. 0.75     far  +6.5%     mid  +0.1%
--     0.45 .. 1.00     far  +2.7%     mid  +0.3%
--     0.90 .. 2.60     far  +2.5%     mid  -0.3%      (the first guess)
--
-- 0.10 moves the far band hardest and its mid cost is still nothing, but
-- it starts the ramp a tenth of a view-height past the player's own feet,
-- which leaves no room at all for the ground a player walks onto next.
-- 0.15 keeps eleven times the noise floor at the tree line and spends
-- literally nothing anywhere else, and that margin is worth more than the
-- last few per cent.
--
-- WHEN THE HORIZON GROWS, THESE MOVE. Both numbers are small because the
-- drawn world is small -- the whole of it fits inside about half a
-- view-height past the player. Put real distance out there and a FAR of
-- 0.55 would saturate everything beyond it into one flat wall of haze,
-- throwing away exactly the depth that was just added. Re-run the sweep.
Aerial.NEAR = 0.15
Aerial.FAR = 0.55

-- The ladder is the TOP rung's strength -- how far the farthest ground
-- goes toward the haze colour.
--
-- 1 is a veil you notice only by turning it off, 2 is the read (the far
-- edge clearly sits behind the near ground, the border ring reads as
-- distance rather than as a wall), 3 is a heavy morning where the far
-- routes are most of the way gone.
--
-- None of them is 1.0, and that is deliberate rather than timid: at a full
-- 1 the far edge stops being far ground and becomes a hole cut in the
-- world the same colour as the sky, and the silhouette of anything
-- standing on it -- the shape that was supposed to say "there is more
-- world out there" -- goes with it. The same reasoning caps the snow's
-- top rung at 0.86.
Aerial.AMOUNTS = { 0, 0.34, 0.56, 0.78 }

-- Hard steps, and the dither that breaks them is one rung wide (the
-- shader reads the amplitude straight off this number). Four is what the
-- sky's own bands use.
Aerial.RUNGS = 4

Aerial.setting = ModSetting.new(Aerial.KEY, Aerial.LABEL,
                                { 0, 1, 2, 3 },
                                { "OFF", "1", "2", "3" })

function Aerial.level()
  return Aerial.setting:get() or 0
end

function Aerial.active()
  return Aerial.level() > 0
end

-- The top rung's strength, or 0 when off -- which is also the shader's
-- "skip it" signal.
function Aerial.amount()
  return Aerial.AMOUNTS[Aerial.level() + 1] or 0
end

-- The ramp for a view `vh` world pixels tall, as the pair the shader
-- wants: where the haze starts, in world pixels, and the reciprocal of the
-- span it saturates over. Returns nil when there is nothing to send.
function Aerial.range(vh)
  if not vh or vh <= 0 then return nil end
  local near = Aerial.NEAR * vh
  local span = (Aerial.FAR - Aerial.NEAR) * vh
  if span <= 0 then return nil end
  return near, 1 / span
end

-- What to fade toward: the descriptor's own fill, which Sky.dress has
-- already made the palest band of the hour (see the header). nil where
-- there is no sky -- indoors, and at a top-down camera where no horizon is
-- in frame -- and nil is the right answer there rather than a fallback
-- grey: a room has no distance to lose and hazing one would only wash the
-- floor out.
function Aerial.color(sky)
  if not sky then return nil end
  local r, g, b = sky[1], sky[2], sky[3]
  if not (r and g and b) then return nil end
  return { r, g, b }
end

function Aerial.row()
  return Aerial.setting:row()
end

function Aerial.sync(value)
  Aerial.setting:sync(value)
end

return Aerial
