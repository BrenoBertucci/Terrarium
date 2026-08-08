-- Voxel world mode: the anime rung -- cel-banded light, rim light, ink line.
--
-- Three effects that together are what a cel-animated frame does and a
-- rendered one does not: light arrives in a small number of FLAT steps
-- rather than as a ramp, a silhouette carries a bright edge where the key
-- light wraps past it, and every shape is closed by a line.
--
-- None of them is a new pass. That is the whole reason this rung is
-- affordable on the hardware the rest of this mod was tuned down for:
--
--   CEL     a dozen instructions inside the scene shader that already runs,
--           between the light being summed and the material being multiplied
--           by it (see Voxel3D's effect(), the ANIME_CEL block). It costs
--           arithmetic, no fetch, no target, no draw -- so it is the one
--           piece that works at every rung of everything else, including
--           with RTX switched off entirely.
--
--   RIM     one dot product against a normal that ALREADY EXISTS. The
--           screen-space pass recovers a per-pixel normal out of four
--           neighbouring depths for its ambient occlusion (RayFX.normalAt)
--           and hands it to every AO tap; the rim reads that same vector.
--
--   LINE    four depth taps, and the only new fetches on this page. They
--           are measured against the point's own TANGENT PLANE rather than
--           against its depth -- the same test aoTap already makes -- which
--           is what keeps a floor seen at a grazing angle from coming out
--           as a solid black field. See animeEdge in RayFX.
--
-- ------- why RIM and LINE need the RTX row and CEL does not
--
-- Both live in the screen-space pass, and that pass reads a depth buffer
-- that only EXISTS when the RTX row is above OFF: Voxel3D.beginScene
-- attaches a readable depth texture on RayFX.wanted() and a plain
-- write-only one otherwise, so with RTX OFF there is no depth to tap and no
-- normal to recover. FULL therefore draws as CEL there, silently, which is
-- the contract every other feature in this mod follows -- it declines
-- cleanly rather than half-working, and it never turns a render target back
-- on that the player switched off to buy frames.
--
-- ------- the bands crawl, and that is what the dither is for
--
-- A hard step riding a continuously moving field walks one fragment at a
-- time. The cel water hit this first and named it: "the ants on the pond",
-- made worse at the default 1/2 render scale where a nearest upscale
-- freezes each crawl step onto a whole display pixel. Here the moving field
-- is the SUN -- DayNight advances it all day, so every band boundary sweeps
-- across the terrain it lands on.
--
-- The cure is the one that file already found, and this uses it unchanged:
-- decide the step on a CELL of the render buffer (floor(sc / CELL)) and
-- jitter the threshold by a checkerboard of those cells, so a boundary
-- reads as a dithered transition a couple of pixels wide instead of a hard
-- line crawling sideways. That checkerboard is this mod's established idiom
-- for "between two colours" -- the 8-bit sky set it, the water followed it,
-- and a fourth spelling of the same thing would only be a fourth spelling.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local Anime = {}

-- values[1] is ModSetting's default and its fallback for an unreadable
-- stored value, so OFF sits first: this changes what the whole world looks
-- like, and a mod that repaints someone's game on update without being
-- asked is a mod that gets uninstalled. Same reasoning Quality uses to put
-- its cheap rung first, for a different reason.
Anime.setting = ModSetting.new("anime", "ANIME",
                               { "off", "cel", "full" },
                               { "OFF", "CEL", "FULL" })

-- ------- the numbers

-- How many flat steps the light is crushed into. Four, because four is
-- what the cel water already bands its depth colour into
-- (floor(depth01 * 3.0) / 3.0 is four rungs) and because it is the count a
-- painted cel actually uses: base, shadow, deep shadow, highlight.
--
-- Counted per unit of luminance rather than across the range, so light
-- above 1.0 -- which is where a lamp core sits, see the x/(1+kx) ceiling in
-- Voxel3D -- keeps climbing in steps of the same size instead of clamping
-- into the top band. An amber core stays hot; it is just hot in steps.
Anime.BANDS = 4

-- The render-buffer cell the step decision and its dither snap to, in
-- canvas pixels. 2.0 is the cel water's own value and for its own reason:
-- one display pixel at the default 1/2 rung, and still reading as the pixel
-- grid at FULL.
Anime.CELL = 2.0

-- Checkerboard jitter on the band threshold, in BAND units -- so 0.5 moves
-- the threshold by half a band across a checker pair, which dithers a
-- boundary about half a band wide. Wider than the water's own jitter
-- because a band here spans a quarter of the light range rather than a
-- swell crest, and a boundary that dissolves over a narrower window than
-- that is still a visible line.
Anime.DITHER = 0.5

-- ------- rim

-- How much light the rim adds at full strength. It is added to the colour
-- AFTER the scene is shaded rather than folded into the light, which is
-- what makes it a rim and not a fill: a rim light in a cel frame is drawn
-- ON the character, at one brightness, and does not respect the material
-- underneath it.
Anime.RIM = 0.34

-- Where the silhouette starts, as 1 - dot(N, toEye). At 0 every surface
-- takes some; at 1 only the exact profile does. 0.62 puts the band on the
-- last few degrees of curvature, which on axis-aligned voxel faces means
-- the faces turned nearly edge-on to the camera -- the ones a cel artist
-- would have drawn as the outline's inner highlight.
Anime.RIM_EDGE = 0.62

-- Cool rather than white. The rim in a cel frame is a SECOND light -- the
-- sky, or a back light -- and this mod already decided in Light.lua that
-- the second light is cool and comes from everywhere. Warm here would read
-- as a second sun.
Anime.RIM_COLOR = { 0.78, 0.86, 1.00 }

-- ------- line

-- How dark the line draws, 0..1 as a mix toward INK_COLOR. Not 1.0: a
-- painted line over a coloured world is ink on top of paint, and paint
-- shows through at the edges. Full black closes every shape into a coloring
-- book and buries the terrain art the atlas spent a bake on.
Anime.INK = 0.72

Anime.INK_COLOR = { 0.05, 0.04, 0.09 }

-- How far a neighbouring pixel must stand OUT OF this pixel's tangent plane
-- to count as an edge, in world pixels per unit of camera distance. Scaled
-- by distance because a silhouette should stay one screen pixel wide
-- wherever it stands: at a fixed world threshold the far half of a route
-- outlines every tile seam and the near half outlines nothing.
Anime.EDGE_BIAS = 0.020

-- ------- what the rest of the mod asks

function Anime.level()
  local ok, v = pcall(Anime.setting.get, Anime.setting)
  if ok and (v == "off" or v == "cel" or v == "full") then return v end
  return "off"
end

-- Whether the scene shader wants its banded-light variant. True on both
-- rungs above OFF -- FULL is CEL plus the screen-space pair, never instead
-- of it.
function Anime.cel()
  return Anime.level() ~= "off"
end

-- Whether the screen-space pass wants the rim and the line. Asked by RayFX
-- when it picks a shader, and answered without consulting RayFX back: this
-- module requires ModSetting and nothing else, so that RayFX and Voxel3D
-- can both require IT without a cycle. The depth-buffer half of the
-- question is RayFX's own to answer -- the block is compiled inside its
-- RT_AO region, which only exists on a rung that allocated the buffer.
function Anime.screen()
  return Anime.level() == "full"
end

function Anime.row()
  return Anime.setting:row()
end

return Anime
