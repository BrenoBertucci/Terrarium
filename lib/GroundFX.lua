-- What the weather LEAVES BEHIND: puddles after the rain, drifts and
-- footprints in the snow.
--
-- The WEATHER row draws what is falling. This draws what has fallen. They
-- are two different features and the difference is time: a shower is over in
-- two minutes and the ground it soaked is wet for ten, which is most of the
-- time a player spends walking around in the aftermath of one. Without this
-- the sky clears and Kanto is instantly, impossibly dry -- the effect
-- switching off rather than the weather ending.
--
-- ------- the two numbers
--
-- `wet` and `cover`, both 0..1, both slow. Rain drives the first up over
-- about a minute of downpour and it drains away over four; snow drives the
-- second and it melts over seven. Everything below is a function of one of
-- those two, exactly as everything a shower does is a function of
-- Weather.power -- because that is what makes an aftermath read as an
-- aftermath rather than as a second effect that also switched on.
--
-- They accumulate off `Weather.falling`, NOT `Weather.visible`, and that is
-- the same distinction that file draws for its own sound: `falling` is what
-- the weather is doing in KANTO, and walking into a house does not stop the
-- route outside getting wet. `visible` is what may be DRAWN here, and it is
-- what the draw below gates on -- so a cave floor is never wet and a room
-- never has snow in it, while the route you came in from keeps soaking.
--
-- ------- these are DECALS, not overlay drawings
--
-- Every other drawing this mod composites -- the ambient life, the steam,
-- the glint, the rain's own splashes -- goes into the overlay pass, which
-- runs after the 3D scene is finished and therefore paints over everything
-- in it. That is right for a butterfly and wrong for a puddle: a butterfly
-- IS in front of the world, and a puddle is underneath the person standing
-- in it. An overlay puddle would be painted over the player's feet, which
-- is not a puddle, it is a sticker.
--
-- So these go into the 3D pass itself, between the terrain and the
-- characters, on the same decal footing the flat drop shadows use:
-- depth-TESTED, so a puddle behind the Mart stays behind the Mart, and never
-- depth-WRITING, so the tall grass drawn at the end of the frame still wins
-- its feet-overdraw fights. Which also means they take the hour's light and
-- the sun's own shadows for free -- they are geometry in the scene, so the
-- same shader that darkens a roof at dusk darkens them.
--
-- The price of that footing is that they want the VOXEL camera, exactly as
-- the steam and the Zs do: the flat 2D path has no depth buffer, no camera
-- to project through and no pass to sit between.
--
-- ------- where a puddle goes, and why it is not a die
--
-- Hashed off the cell, like the sleeping Meowth and for the same reason: a
-- random roll would put the puddles somewhere else every time the map
-- streamed back in, and water that teleports between paving stones is not
-- weather, it is a particle system. Hashed, the yard outside the Pewter gym
-- has a puddle in the same corner every time it rains, forever, which is
-- what a low spot IS.
--
-- Baked into one mesh per 16-cell chunk and cached per map, for the reason
-- the terrain is: the SET of puddles on a map never changes, only how full
-- they are, so walking should cost a matrix and a colour rather than a
-- rebuild. What varies per frame is one alpha and one colour -- and the
-- colour is the SKY's, because a puddle is a piece of the sky lying on the
-- ground, and a puddle at sunset that stayed grey would be the one thing on
-- screen not taking part in the evening.
--
-- ------- footprints
--
-- Every walker leaves them, not just the player: an NPC crossing the road
-- in the snow leaves a line of prints behind them, which is most of what
-- makes the snow read as lying there rather than as painted on. Dropped on
-- the cell somebody LEFT rather than the one they arrived at, so the trail
-- is behind them, and filled back in over half a minute -- faster while it
-- is still coming down, because that is what snow does to a footprint.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local DayNight = V.require("DayNight")
local Weather = V.require("Weather")
local Voxel3D = V.require("Voxel3D")
local Mat4 = V.require("Mat4")
-- Safe: Wind requires ModSetting and DayNight only, and Voxel3D above
-- already requires it. This file is where the SETTLED snow lives, and
-- settled snow is what bows a grass tuft over -- so it is pushed from here
-- (Wind.grassSnow), the same way Weather pushes the falling half.
local Wind = V.require("Wind")

local Map = require("src.world.Map")

local GroundFX = {}

local function game()
  return require("src.core.Game")
end

GroundFX.setting = ModSetting.new("ground", "GROUND",
                                  { "on", "off" }, { "ON", "OFF" })

function GroundFX.enabled()
  return GroundFX.setting:get() ~= "off"
end

function GroundFX.row()
  return GroundFX.setting:row()
end

-- ------- the clocks
--
-- Seconds of weather at FULL power to reach the top, and seconds to come
-- back down from it. The asymmetry is the whole point: soaking is faster
-- than drying, which is why there is still an aftermath to walk around in.
GroundFX.SOAK = 55            -- seconds of downpour to a saturated ground
GroundFX.DRY = 260            -- and to dry out again once it stops
GroundFX.SETTLE = 100         -- seconds of snowfall to full cover
GroundFX.MELT = 430           -- and to melt off

-- Where each layer starts showing. Below these the ground has taken the
-- weather but has nothing to show for it yet, which is the first half of
-- every shower.
GroundFX.PUDDLE_FROM = 0.30
GroundFX.DRIFT_FROM = 0.10
GroundFX.PRINT_FROM = 0.22    -- cover below which a step leaves no mark

GroundFX.REACH = 11           -- cells from the player anything is drawn within

local state = { wet = 0, cover = 0, mapId = nil }

function GroundFX.wetness() return state.wet end
function GroundFX.cover() return state.cover end

-- How DEEP a fully worked snowfall lies, which the scene shader turns into
-- cover per face. It used to be the ceiling on the blend as well -- short of
-- 1 so a roof kept its own art rather than turning into a white block -- and
-- that job has moved into the shader, which caps its top rung at 0.86 for the
-- same reason and rounds nothing up past it. What this sets now is the rate:
-- how far the drifts have got by the time the weather is at full tilt, and so
-- how much of a roof is buried rather than patched. See the snowTop block in
-- Voxel3D's SHADER.
GroundFX.SNOW_TINT = 0.88

-- 0..1: how much of the puddle layer is showing, and of the drifts.
local function puddleAmount()
  local w = (state.wet - GroundFX.PUDDLE_FROM) / (1 - GroundFX.PUDDLE_FROM)
  if w <= 0 then return 0 end
  return w > 1 and 1 or w
end

local function driftAmount()
  local c = (state.cover - GroundFX.DRIFT_FROM) / (1 - GroundFX.DRIFT_FROM)
  if c <= 0 then return 0 end
  return c > 1 and 1 or c
end

-- ------- the hash
--
-- The same multiply-and-add hash Interiors uses, for the same reason and
-- with the same constraint: this runs on LuaJIT, where the 5.3 spelling of
-- a bit mix is a syntax error rather than a slow path.
local function hash(text)
  local h = 5381
  local s = tostring(text)
  for i = 1, #s do
    h = (h * 33 + s:byte(i)) % 2147483647
  end
  return h
end

local function unit(h) return (math.floor(h / 977) % 100000) / 100000 end

-- ------- the art: a pixel artist's file first, and a generated one only if
-- there isn't one
--
-- Drop a strip of 16x16 frames at `assets/ground/puddle.png`,
-- `assets/ground/drift.png` or `assets/ground/print.png` inside the mod and
-- it is used as-is, nothing is generated, and however many frames the strip
-- is wide is however many variants there are. That is the same contract the
-- roamers' own art already has (assets/roamers/<SPECIES>.png), and for the
-- same reason: a drawn puddle beats a described one, and nobody should have
-- to read a Lua file to replace a picture.
--
-- The generated shapes below are the FALLBACK -- what the mod looks like out
-- of the box, because a mod that shipped a feature and a note saying "now
-- draw five PNGs" has not shipped the feature.
--
-- Two rules any replacement has to keep, both of them the scene shader's
-- rather than this file's:
--
--   the ALPHA is the shape.  Anything under half alpha is DISCARDED, not
--   blended -- that is how a sprite cuts its own silhouette out of its quad
--   in this mode -- so a soft airbrushed edge does not fade, it vanishes at
--   the halfway line. Draw hard edges, and dither if you want a fringe.
--
--   the RGB is a TONE, not a colour.  Every texel is multiplied by the
--   colour this file picks -- the sky's own hue for a puddle, white for
--   snow -- so a strip drawn in greys lands in the right colour at every
--   hour of the day, and one drawn in blue comes out blue TIMES blue at
--   dusk. Grey in, weather out.
GroundFX.VARIANTS = 4          -- how many the GENERATED strips carry
GroundFX.ASSET_DIR = "assets/ground/"

-- name -> { img = Image, n = frames } , or false for "there is none"
local atlases = {}

-- The file a strip is looked for under, and the frame count is read off the
-- image rather than declared: a four-frame strip and a nine-frame one are
-- both fine, and neither needs a number written down twice.
-- The snow has THREE drawings per layer rather than one at three sizes, and
-- that is the difference between snow and water. A pool is the same pool
-- getting wider; a snowfall is a different picture at each depth -- specks
-- caught in the seams of the paving, then patches, then an unbroken sheet
-- with the ground showing through in dithered holes. Scaling one drawing up
-- could only ever make bigger specks.
--
-- The CAPS go the same way, and want it more: a rim of white along a hedge's
-- crown, then most of it, then the whole bush buried. A shape that just grew
-- would be a snowball sitting on a shrub.
local ASSET_FILE = {
  puddle = "puddle",
  print_ = "print",
  drift1 = "snow-ground-1",     -- a dusting caught in the seams
  drift2 = "snow-ground-2",     -- patches
  drift3 = "snow-ground-3",     -- lying
  crust1 = "snow-crust-1",          -- a rim along the crown
  crust2 = "snow-crust-2",          -- most of it
  crust3 = "snow-crust-3",          -- buried
  drift = "snow-ground-2",      -- the plain name, for the generated fallback
}

local function shippedAtlas(name)
  local okA, Assets = pcall(require, "src.render.Assets")
  if not okA then return nil end
  local path = V.path .. "/" .. GroundFX.ASSET_DIR .. ASSET_FILE[name] .. ".png"
  local okE, exists = pcall(Assets.exists, path)
  if not (okE and exists) then return nil end
  local ok, img = pcall(Assets.image, path)
  if not (ok and img) then return nil end
  pcall(img.setFilter, img, "nearest", "nearest")
  local okD, w = pcall(img.getWidth, img)
  local n = okD and math.max(1, math.floor(w / 16)) or 1
  return { img = img, n = n, shipped = true }
end

local function newStrip(n)
  if not (love.image and love.graphics) then return nil end
  local ok, data = pcall(love.image.newImageData, n * 16, 16)
  if not ok then return nil end
  return data
end

local function finish(data)
  local ok, img = pcall(love.graphics.newImage, data)
  if not ok then return nil end
  pcall(img.setFilter, img, "nearest", "nearest")
  return img
end

-- One ellipse per variant, each a different shape and each nudged off
-- centre, so four puddles in a row do not read as four copies of one.
local function buildPuddles()
  local data = newStrip(GroundFX.VARIANTS)
  if not data then return nil end
  for v = 0, GroundFX.VARIANTS - 1 do
    local h = hash("puddle" .. v)
    local rx = 4.4 + unit(h) * 2.6
    local ry = 3.0 + unit(h * 7 + 13) * 2.2
    local ox = 8 + (unit(h * 3 + 5) - 0.5) * 3
    local oy = 8 + (unit(h * 11 + 1) - 0.5) * 3
    local wob = unit(h * 17 + 3) * 6.2831
    local function inside(x, y)
      local dx, dy = x + 0.5 - ox, y + 0.5 - oy
      local ang = math.atan2(dy, dx)
      -- the wobble is what stops it being a drawn oval: the radius breathes
      -- twice around the rim, so the outline reads as a shape water found
      local k = 1 + 0.16 * math.sin(ang * 2 + wob)
      return (dx * dx) / (rx * rx * k * k) + (dy * dy) / (ry * ry * k * k) <= 1
    end
    for y = 0, 15 do
      for x = 0, 15 do
        if inside(x, y) then
          -- the rim is any body pixel with open air next to it: one pixel
          -- of bright edge, which is the whole of what a cel-shaded
          -- reflection needs to read as a surface rather than a stain
          local rim = not (inside(x - 1, y) and inside(x + 1, y)
                           and inside(x, y - 1) and inside(x, y + 1))
          local tone = rim and 1.0 or 0.34
          data:setPixel(v * 16 + x, y, tone, tone, tone, 1)
        else
          data:setPixel(v * 16 + x, y, 0, 0, 0, 0)
        end
      end
    end
  end
  return finish(data)
end

-- Drifts: the same shape language with the edge DITHERED instead of rimmed.
-- Snow has no waterline, so what says "this is settled rather than painted"
-- is the checkerboard fringe -- the same idiom the sky's ramp and the
-- water's foam already use for "between two things".
local function buildDrifts()
  local data = newStrip(GroundFX.VARIANTS)
  if not data then return nil end
  for v = 0, GroundFX.VARIANTS - 1 do
    local h = hash("drift" .. v)
    local rx = 5.2 + unit(h) * 2.6
    local ry = 4.4 + unit(h * 7 + 13) * 2.4
    local ox = 8 + (unit(h * 3 + 5) - 0.5) * 3
    local oy = 8 + (unit(h * 11 + 1) - 0.5) * 3
    local wob = unit(h * 17 + 3) * 6.2831
    for y = 0, 15 do
      for x = 0, 15 do
        local dx, dy = x + 0.5 - ox, y + 0.5 - oy
        local ang = math.atan2(dy, dx)
        local k = 1 + 0.18 * math.sin(ang * 2 + wob)
        local d = (dx * dx) / (rx * rx * k * k) + (dy * dy) / (ry * ry * k * k)
        local on = false
        if d <= 0.72 then
          on = true
        elseif d <= 1 then
          on = (x + y) % 2 == 0        -- the fringe, dissolving outward
        end
        if on then
          local tone = d <= 0.35 and 1.0 or 0.88
          data:setPixel(v * 16 + x, y, tone, tone, tone, 1)
        else
          data:setPixel(v * 16 + x, y, 0, 0, 0, 0)
        end
      end
    end
  end
  return finish(data)
end

-- A pair of prints, pointing NORTH in the sheet -- the matrix turns them.
-- Two small ovals rather than a boot: at sixteen pixels to a person, a
-- footprint is a mark, and the thing that makes it read is that there are
-- two of them, side by side, and that they are darker than what they are in.
local function buildPrint()
  local data = newStrip(1)
  if not data then return nil end
  for y = 0, 15 do
    for x = 0, 15 do
      local on = false
      for _, foot in ipairs({ { 5, 6.5 }, { 11, 9.5 } }) do
        local dx, dy = x + 0.5 - foot[1], y + 0.5 - foot[2]
        if (dx * dx) / 5.5 + (dy * dy) / 11 <= 1 then on = true end
      end
      if on then
        data:setPixel(x, y, 1, 1, 1, 1)
      else
        data:setPixel(x, y, 0, 0, 0, 0)
      end
    end
  end
  return finish(data)
end

-- The strip for one layer: the artist's file if there is one, the generated
-- shapes otherwise. Returns { img, n } so the caller knows how many frames
-- it got -- an override is allowed to carry a different number from the
-- generated set, which is the point of reading it off the image.
local function atlas(name)
  if atlases[name] == nil then
    local shipped = shippedAtlas(name)
    if shipped then
      atlases[name] = shipped
    elseif name:find("^crust") then
      -- no generated fallback for the tree caps: a cap is a DRAWING of a
      -- snow-laden bush, and an ellipse pretending to be one would look
      -- worse than bare branches. Without the file the trees simply stay
      -- bare and the ground still goes white.
      atlases[name] = false
    else
      local builder = name == "puddle" and buildPuddles
                      or name:find("^drift") and buildDrifts or buildPrint
      local ok, img = pcall(builder)
      atlases[name] = (ok and img)
                      and { img = img, n = name == "print_"
                                          and 1 or GroundFX.VARIANTS }
                      or false
    end
  end
  return atlases[name] or nil
end

-- Whether a layer is wearing a file somebody drew rather than the generated
-- shapes -- for the probe, and for anybody wondering why their PNG did not
-- take.
function GroundFX.usingArt(name)
  local a = atlas(name)
  if not a then return false end
  return a.shipped == true
end

-- ------- the chunk meshes
--
-- One mesh per 16-cell chunk per layer, cached per map: the set of puddles
-- on a map is a fact about the map, so it is built once and then only ever
-- drawn. Only the current map's chunks are kept, because a route's worth of
-- them is a few dozen quads and a whole game's worth would be a leak.
local CHUNK = 16
local chunks = {}             -- key -> mesh or false

-- ------- how far off the ground each layer floats, and why they differ
--
-- World pixels. A whole pixel rather than the quarter the drop shadows float
-- at, and measured rather than guessed: at a quarter the decals came back
-- MOTTLED -- half of every quad winning the depth test against the very
-- surface it lies on and half losing it -- which reads as a dirty wash
-- rather than as snow lying. A pixel on a sixteen-pixel cell is invisible at
-- every pitch this camera has, and it settles the fight.
--
-- The three numbers being DIFFERENT used to be what let the RTX row tell a
-- puddle from a drift: that pass had only the depth buffer to read, so it
-- recognised a puddle by the FRACTION of its height being 0.7, a number no
-- class in the shape profile has. It does not any more, and the history is
-- worth keeping because it is why these three are still spread out. The
-- fraction was never an identifier -- a character is a card leaned back by
-- the camera's pitch, and its height crosses point-seven a dozen times on
-- the way up the player's own face. The puddles are MARKED now, in the alpha
-- channel of the scene buffer, by the stamp in draw3D below (see
-- Voxel3D.PUDDLE_TAG), and nothing about the mark cares what height they
-- float at.
--
-- So these three are back to meaning only what they say: how far off the
-- ground each layer floats so it wins the depth test against the ground and
-- against each other. Moving PUDDLE no longer breaks reflections. Moving it
-- INTO one of the others still breaks the decals.
--
-- Puddles are the LOWEST of the three because water lies in the low spot and
-- snow lies on top of everything, and a print is pressed into the snow, so
-- it has to float above it to win the depth test against it.
GroundFX.PUDDLE = 0.7
GroundFX.DRIFT = 1.0
GroundFX.PRINT = 1.35
GroundFX.EPS = GroundFX.DRIFT     -- the old name, for anything still asking

local function groundAt(map, cx, cy)
  local VoxelScene = V.require("VoxelScene")
  local ok, h = pcall(VoxelScene.groundAt, map, cx, cy)
  return (ok and h) or 0
end

-- Whether the thing on this cell has a flat lid at groundAt's height rather
-- than a crown carved from its own drawing. See VoxelScene.flatTop; a false
-- here is a cell no horizontal quad can lie flush on.
local function flatTop(map, cx, cy)
  local VoxelScene = V.require("VoxelScene")
  local ok, f = pcall(VoxelScene.flatTop, map, cx, cy)
  return ok and f or false
end

-- Where a puddle may lie: walkable, out of the water, out of the grass and
-- away from doors. Anywhere you can stand, at whatever height that is.
--
-- This used to insist on height ZERO, on the reasoning that water runs
-- downhill and a pool on a ledge would look like a sticker. That reasoning
-- was fine and the rule was wrong, because most of what a player walks on in
-- this game is not at zero: a town's paving, a Center's forecourt and half
-- of Route 1's path all carry a height from the shape profile, so the rule
-- quietly deleted the puddles from exactly the places rain is worth seeing.
-- A street was dry in a downpour and the draw count said one mesh.
--
-- Every walkable cell is FLAT, whatever its height -- that is what makes it
-- walkable -- so a pool on one is a pool on level ground, which is all the
-- original rule was really after.
local function puddleCell(map, cx, cy)
  if not map:inBounds(cx, cy) then return false end
  if map:isWaterCell(cx, cy) then return false end
  if not map:isWalkableCell(cx, cy) then return false end
  if map:isGrassCell(cx, cy) then return false end
  if map:warpAtCell(cx, cy) then return false end
  return true
end

-- Snow settles on EVERYTHING, which is the whole difference between a
-- snowfall and a white floor: not just the ground you walk on but the tops
-- of the hedges, the roofs, the ledges and the signposts. The walkable test
-- this used to hold was the wrong question -- it left every tree in a white
-- field standing green, which reads as a fresh coat of paint on the road.
--
-- The one thing that stays bare is water, because snow lands on a pond and
-- is gone, and doorways, because a drift across a door is a drift in a
-- doorway.
--
-- Height comes from the cell's own class, so a quad on a tree cell lands on
-- the tree's TOP rather than at its foot -- the shape profile already knows
-- how tall everything is, and this only had to stop ignoring it.
local function driftCell(map, cx, cy)
  if not map:inBounds(cx, cy) then return false end
  if map:isWaterCell(cx, cy) then return false end
  if map:warpAtCell(cx, cy) then return false end
  if not map:isWalkableCell(cx, cy) then return false end
  return true
end

-- ------- and what wears a CAP
--
-- The other half of a snowfall, and the half a white floor cannot fake: the
-- hedges, the trees and the roofs go white on TOP. A field of snow with
-- green bushes standing in it reads as paint; the reference this was built
-- against has a cap on every one of them.
--
-- A cap cell is one you canNOT stand on and that stands ABOVE the ground --
-- which is the shape profile's own description of a tree, a hedge, a roof
-- or a ledge, and needs no list of tile ids. Its height is where the cap
-- goes, so the drawing lands on the thing's top rather than at its foot.
--
-- And it must have a FLAT top, which is the rule this was missing and the
-- reason a snowed forest looked like it had been stickered. A decal is one
-- horizontal quad: it lies flush on a lid and it CANNOT lie on a dome. A
-- tree canopy is a voxel hull carved from its own outline (see
-- Structures.buildCylinders), so the profile's height is where its highest
-- voxel lands and the crown falls away from that by half a cell before it
-- reaches the rim -- which put a 16px white tile in the air over every tree,
-- touching the crown at one point and floating clear of it everywhere else.
-- No lift value fixes that, because the mistake is not how high the quad
-- sits, it is that a flat quad is the wrong primitive for a round thing.
--
-- The round classes are not left bare: their snow is the crown's own
-- up-facing voxels going white in the scene shader (Voxel3D.snowTop, set for
-- the terrain pass in VoxelScene). That is the crown's real geometry, so it
-- follows every curve of it and cannot float by construction -- which is
-- exactly what this decal was failing to fake.
local function crustCell(map, cx, cy)
  if not map:inBounds(cx, cy) then return false end
  if map:isWaterCell(cx, cy) then return false end
  if map:isWalkableCell(cx, cy) then return false end
  if not flatTop(map, cx, cy) then return false end
  return groundAt(map, cx, cy) > 0
end

-- One flat quad on the ground plane, appended to `verts`. `u0` is the
-- variant's own left edge in the strip.
local function pushDecal(verts, indices, x, z, y, size, u0, u1)
  local half = size * 0.5
  local n = #verts / 4
  verts[#verts + 1] = { x - half, y, z - half, u0, 0, 1 }
  verts[#verts + 1] = { x + half, y, z - half, u1, 0, 1 }
  verts[#verts + 1] = { x + half, y, z + half, u1, 1, 1 }
  verts[#verts + 1] = { x - half, y, z + half, u0, 1, 1 }
  Voxel3D.pushQuad(indices, n)
end

-- ------- how many, how big, and the three steps it gets there in
--
-- The SIZE grows in three steps as the weather works, and the steps are the
-- point rather than a compromise. A pool that swelled smoothly would want a
-- rebuilt mesh every frame; three baked sizes cost three meshes per chunk,
-- built once, of which exactly ONE is ever drawn. And on a world made of
-- voxels the right way for a puddle to grow is a pixel at a time anyway --
-- the same reason nothing else in this mod tweens.
--
-- ------- puddles: FEW and BIG, and spaced
--
-- A share-of-cells density was the wrong tool for water and it looked it: at
-- one cell in six, small pools landed next to each other in twos and threes
-- and a wet street came out stippled, which is not what rain does. Rain
-- collects: a few wide shallow pools with dry ground between them, because
-- the low spot next to a low spot is one low spot.
--
-- So a puddle cell has to WIN its neighbourhood -- it is placed only where
-- its own hash is the lowest of every candidate within SPACING cells. That
-- is a Poisson-disc thinning done with arithmetic instead of a die: stable
-- across sessions like everything else here, needing no list of what was
-- placed, and guaranteeing by construction that no two pools are closer than
-- the spacing. The candidate density is generous precisely because the
-- thinning is what decides the count.
--
-- And then they are WIDE -- a pool at its fullest is a cell and a half
-- across, which is what a puddle in the references looks like: something you
-- would walk around, not a spot.
--
-- ------- snow: everywhere, thickening
--
-- The opposite problem, so the opposite answer. Snow does not collect in
-- spots, it covers, and it covers the hedges and the roofs too (see
-- driftCell). Its density RISES with the fall rather than staying put: bare
-- patches at first, most of the ground by the second step, and every eligible
-- cell at the third -- which with quads wider than their cells is a single
-- unbroken sheet with a ragged edge where it meets what it cannot settle on.
GroundFX.STEPS = 3

-- Puddles: the pool of candidates, and the neighbourhood a candidate has to
-- win to become one.
--
-- The neighbourhood sets the count, and it was measured rather than reasoned
-- about, because reasoning about it was wrong twice. A local-minimum rule
-- leaves roughly one winner per neighbourhood, so the arithmetic says a
-- radius of 3 gives one pool per forty-nine cells; what the probe counted
-- was one per a hundred and forty-four, because most of a town is buildings
-- and hedges and only a third of it is ground a pool may lie on. A street in
-- a downpour had four.
--
-- So: the eight neighbours, and nothing further. One pool per nine eligible
-- cells, and two winners can never touch -- the nearest a pair can be is two
-- cells, which at the size below leaves a hand's width of dry ground between
-- them. Sparse enough to read as rain collecting, close enough that a wet
-- street looks wet.
GroundFX.PUDDLE_CANDIDATES = 0.70
GroundFX.PUDDLE_SPACING = 1        -- cells checked around a candidate

-- Snow: a share of eligible cells per step, climbing to all of them.
GroundFX.DRIFT_DENSITY = { 0.55, 0.82, 1.0 }

-- World pixels across, per step. Both end WIDER than the 16-pixel cell --
-- the drifts so they merge into a field, the puddles so a pool reads as a
-- pool. Varied a little per cell so a street is not a stencil.
GroundFX.PUDDLE_SIZE = { 14, 21, 28 }
GroundFX.DRIFT_SIZE = { 13, 20, 28 }
-- A cap is worn by a thing rather than spread over the ground, so it stays
-- near the size of what it is sitting on: a dusting on the crown, then most
-- of it, then the whole hedge under it.
-- The three cap drawings already carry the difference in HOW MUCH snow, so
-- the size does not move at all: what grows is the picture, not the blob. A
-- hedge does not get bigger when it snows.
--
-- And the number is the CELL, exactly. It read 16, 17, 18 -- a pixel of lip
-- over the edge at the deepest step, which merges a run of hedge cells the
-- way the drifts merge a field. But a lid is only 16 wide, so on the cells
-- that have no neighbour wearing a cap -- the end of a wall, a lone sign,
-- the rim of a roof -- that lip was white hanging past the edge with nothing
-- under it. At exactly 16 the caps still tile edge to edge with no seam,
-- because they are the cells, and none of them ever leaves the thing it is
-- lying on.
GroundFX.CRUST_SIZE = { 16, 16, 16 }

-- ------- and how far above its cell a crust sits: FLUSH, always
--
-- This number went five, then one, then per-class, and every version of it
-- was the same mistake -- trying to guess how far a rounded crown stands
-- proud of the flat height the profile gives it. Five floated a white slab
-- over every roof and wall in the town, which is the one failure you cannot
-- stop seeing. One fixed that and let the bushes swallow their crusts.
--
-- The guess is gone because the question is: the snow lying on a rounded
-- crown is not a decal at all now, it is the crown's own up-facing voxels
-- going white in the scene shader (Voxel3D.snowTop, set for the terrain pass
-- in VoxelScene). Geometry cannot float above itself.
--
-- What is left for a decal is the TEXTURE -- the drifted, dithered look on
-- the flat tops where a white face alone would read as paint -- and a
-- texture on a flat top belongs flush with it. One pixel, like the drifts.
--
-- That was the intent when the number was written and it was only half true
-- in the code: the lift stopped guessing, but crustCell went on handing the
-- decal to the rounded crowns as well, so the quad kept floating over every
-- tree at whatever height the lift picked -- which is why moving this number
-- never fixed anything. crustCell asks for a flat top now. This is the lift
-- for the surfaces that are left, and every one of them is a lid.
GroundFX.CRUST_LIFT = GroundFX.DRIFT


-- The step an amount is at, 1..STEPS.
function GroundFX.step(amount)
  local k = math.floor(amount * GroundFX.STEPS) + 1
  if k < 1 then return 1 end
  return k > GroundFX.STEPS and GroundFX.STEPS or k
end

-- "puddle2" -> "puddle", 2
local function layerOf(name)
  local base = name:sub(1, -2)
  return base, tonumber(name:sub(-1)) or 1
end

-- The cell hashes, memoised across chunk builds. The spacing scan below asks
-- about every neighbour of every candidate, so the same cell is hashed from
-- several chunks and several size steps -- and hashing a string thirteen
-- times per cell is the difference between a build nobody notices and a
-- stutter when a route streams in. Dropped with the meshes.
local hashes = {}

local function cellHash(map, base, cx, cy)
  -- keyed on the BASE layer rather than the step, so the three sizes are the
  -- same puddles at three sizes and not three different sets
  local k = map.id .. "|" .. base .. "|" .. cx .. "," .. cy
  local v = hashes[k]
  if v == nil then
    v = hash(k)
    hashes[k] = v
  end
  return v
end

-- ------- does this cell hold a pool?
--
-- Asked here rather than inside the mesh builder because it is the whole of
-- how a wet street READS, and a claim about how a wet street reads should be
-- checkable as a table of coordinates rather than only as a screenshot (see
-- GroundFX.puddleCells, which the probe walks).
--
-- A BLOCK GRID, and it is the third rule this has had -- the first two were
-- both attempts to thin a per-cell die down to something spaced, and both
-- were unpredictable in the same way. A local-minimum-of-the-hash rule is a
-- Poisson-disc thinning and reads beautifully on paper; what it actually
-- produced was one pool per a hundred and forty-four cells where the
-- arithmetic promised one per forty-nine, because the estimate assumes every
-- neighbour is eligible and most of a town is buildings. Tightening the
-- radius from three to one moved it from four pools to five. A rule whose
-- output cannot be predicted from its input is a rule that gets tuned by
-- screenshot forever.
--
-- So the map is cut into BLOCKS of PUDDLE_BLOCK cells square, and each block
-- holds at most one pool: the hash decides whether that block gets one at
-- all, and then which of its cells -- walking the block in a hash-rotated
-- order and taking the first that can actually hold water, so a block whose
-- middle is a building still gets its pool on the pavement beside it.
--
-- What that buys is a count you can state: one pool per PUDDLE_BLOCK squared
-- cells, times PUDDLE_FILL, and never two in the same block. At three cells
-- and four fifths that is a pool every eleven cells of ground -- which is
-- what a wet street looks like -- and the arithmetic and the probe agree.
GroundFX.PUDDLE_BLOCK = 3
GroundFX.PUDDLE_FILL = 0.80

function GroundFX.holdsPuddle(map, cx, cy)
  if not puddleCell(map, cx, cy) then return false end
  local B = GroundFX.PUDDLE_BLOCK
  local bx = math.floor(cx / B)
  local by = math.floor(cy / B)
  local h = cellHash(map, "pblock", bx, by)
  if unit(h) >= GroundFX.PUDDLE_FILL then return false end
  -- the block's own cells, started at a hashed corner and walked in order:
  -- the first one that can hold water is the one that does
  local start = h % (B * B)
  for i = 0, B * B - 1 do
    local k = (start + i) % (B * B)
    local px = bx * B + (k % B)
    local py = by * B + math.floor(k / B)
    if puddleCell(map, px, py) then
      return px == cx and py == cy
    end
  end
  return false
end

local function buildChunk(map, layer, chunkX, chunkY)
  local verts, indices = {}, {}
  local base, step = layerOf(layer)
  -- however many frames the strip this layer is actually wearing carries --
  -- read from the image, so an artist's nine-frame puddle sheet is used
  -- nine frames wide with nothing here changed
  -- the art is per STEP for the snow (three different drawings) and per BASE
  -- for the rest (one drawing at three sizes) -- see ASSET_FILE
  local sheet = atlas(base == "puddle" and "puddle" or layer)
  local strip = (sheet and sheet.n) or GroundFX.VARIANTS
  local puddle = base == "puddle"
  local crust = base == "crust"
  local sizes = puddle and GroundFX.PUDDLE_SIZE
                or crust and GroundFX.CRUST_SIZE or GroundFX.DRIFT_SIZE
  -- one number per layer, because every cell a layer lands on is flat now:
  -- the drifts and pools lie on walkable ground, and the crusts only on lids
  -- (crustCell). The rounded crowns are painted in the shader instead of
  -- being covered by a quad, so nothing here has anything to float over.
  local lift = puddle and GroundFX.PUDDLE
               or crust and GroundFX.CRUST_LIFT
               or GroundFX.DRIFT
  local x0, y0 = chunkX * CHUNK, chunkY * CHUNK

  for cy = y0, y0 + CHUNK - 1 do
    for cx = x0, x0 + CHUNK - 1 do
      local h = cellHash(map, base, cx, cy)
      local want
      if puddle then
        want = GroundFX.holdsPuddle(map, cx, cy)
      elseif crust then
        -- every eligible cell, at every step: a bush either has snow on it
        -- or does not, and half the hedge white is not a lighter snowfall,
        -- it is a bug. What the steps change is how MUCH (the size below).
        want = crustCell(map, cx, cy)
      else
        want = unit(h) < (GroundFX.DRIFT_DENSITY[step] or 1)
                 and driftCell(map, cx, cy)
      end
      if want then
        local v = h % strip
        -- a pool sits nearly where its cell is; snow scatters a little more,
        -- which is what stops a full field reading as a grid.
        --
        -- A CAP does neither, and that is not a missing feature. The drifts
        -- and the pools lie on open ground, where wandering off the cell's
        -- centre is the whole point -- there is always more ground under
        -- them. A cap lies on a THING, and the thing ends at its cell: jitter
        -- it two and a half pixels and scale it a seventh wider and the white
        -- hangs off the edge of the wall it is sitting on, in the air, which
        -- is the same failure as floating over a tree in a smaller size. So a
        -- cap is centred on what wears it and is exactly its authored size.
        -- The variation is still there -- it is the STRIP, a different
        -- drawing per cell, which is where variation belongs for a thing
        -- whose outline has to stay inside a 16px lid.
        local spread = crust and 0 or (puddle and 3 or 5)
        local jx = (unit(h * 5 + 7) - 0.5) * spread
        local jz = (unit(h * 13 + 3) - 0.5) * spread
        local size = sizes[step] or sizes[1]
        if not crust then
          size = size * (0.86 + unit(h * 3 + 11) * 0.28)
        end
        pushDecal(verts, indices,
                  cx * 16 + 8 + jx, cy * 16 + 8 + jz,
                  groundAt(map, cx, cy)
                    + lift, size,
                  (v * 16 + 0.05) / (strip * 16),
                  (v * 16 + 15.95) / (strip * 16))
      end
    end
  end
  if #verts == 0 then return false end
  return Voxel3D.newMesh(verts, indices) or false
end

-- Keyed by the MAP as well as the chunk, and that is not tidiness: a route
-- draws its connected neighbours' ground in the same pass, so two different
-- maps ask this for chunk (0,0) in the same frame and a key without the map
-- in it would hand the second one the first one's puddles.
local function chunkMesh(map, layer, chunkX, chunkY)
  local key = map.id .. "#" .. layer .. "#" .. chunkX .. "#" .. chunkY
  if chunks[key] == nil then
    local ok, mesh = pcall(buildChunk, map, layer, chunkX, chunkY)
    chunks[key] = (ok and mesh) or false
  end
  return chunks[key] or nil
end

-- Dropped when the map changes, and when a block on it is rewritten -- a
-- Cut tree is a new cell to stand on, and one that could hold a puddle.
function GroundFX.invalidate()
  hashes = {}
  chunks = {}
end

-- ------- footprints
--
-- A ring of recent marks, and a note of where every walker was last frame
-- so a step can be NOTICED without anything having to announce it. The note
-- is keyed by the entity itself in a weak table: an NPC that leaves the
-- cast list takes its entry with it rather than pinning a dead object here.
GroundFX.PRINT_TTL = 34           -- seconds a print lasts in still air
GroundFX.PRINT_FILL = 3.2         -- how much faster it fills while snowing
GroundFX.MAX_PRINTS = 80

local prints = {}
local wasAt = setmetatable({}, { __mode = "k" })

-- How many marks are lying on the ground right now. Read by the probe: a
-- trail that draws nothing draws nothing silently, and "somebody walked"
-- is not the same claim as "there is a print where they walked".
function GroundFX.printCount() return #prints end

local FACE_ANGLE = { down = 0, up = math.pi,
                     right = -math.pi / 2, left = math.pi / 2 }

-- When the ring is full the oldest print goes -- but the oldest print
-- SOMEBODY ELSE left goes first, and that ordering is not politeness, it is
-- the feature working at all. A route with ten wild Pokemon wandering the
-- grass fills this list in a couple of seconds, and a plain oldest-first
-- eviction spent the whole of it on their trails: the player would turn
-- round to look at where they had walked and find nothing there. Yours
-- outlive theirs, which is the trail anybody actually looks for.
local function dropPrint(cx, cy, facing, mine)
  prints[#prints + 1] = { cx = cx, cy = cy, t = 0, mine = mine,
                          angle = FACE_ANGLE[facing] or 0 }
  while #prints > GroundFX.MAX_PRINTS do
    local victim = nil
    for i, pr in ipairs(prints) do
      if not pr.mine then victim = i break end
    end
    table.remove(prints, victim or 1)
  end
end

local function trackSteps(ow)
  local map = ow.map
  for _, e in ipairs(ow.entities or {}) do
    local cx, cy = e.cellX, e.cellY
    if cx and cy then
      local last = wasAt[e]
      if last and (last[1] ~= cx or last[2] ~= cy) then
        -- the cell they LEFT, which is where the foot actually was
        if driftCell(map, last[1], last[2]) then
          dropPrint(last[1], last[2], e.facing, e == ow.player)
        end
        last[1], last[2] = cx, cy
      elseif not last then
        wasAt[e] = { cx, cy }
      end
    end
  end
end

-- How many of the marks on the ground are the PLAYER's. The probe reads
-- this rather than the total: a count that a wandering Rattata can move is
-- not a measurement of whether walking leaves a trail.
function GroundFX.myPrintCount()
  local n = 0
  for _, pr in ipairs(prints) do if pr.mine then n = n + 1 end end
  return n
end

-- ------- per-frame
--
-- Rides the voxel pipeline's update hook with the rest of the mod's clocks,
-- ahead of nothing and behind Weather, which is what writes the number this
-- reads.
local failed = false

local function tick(dt)
  local kind, power = Weather.falling()

  if kind == "rain" then
    state.wet = state.wet + power * dt / GroundFX.SOAK
  else
    state.wet = state.wet - dt / GroundFX.DRY
  end
  if kind == "snow" then
    state.cover = state.cover + power * dt / GroundFX.SETTLE
  else
    state.cover = state.cover - dt / GroundFX.MELT
  end
  -- rain washes snow off faster than a thaw does, which is both true and
  -- the thing that stops a shower falling through a snowfield
  if kind == "rain" then
    state.cover = state.cover - power * dt / GroundFX.SETTLE
  end
  if state.wet < 0 then state.wet = 0 elseif state.wet > 1 then state.wet = 1 end
  if state.cover < 0 then state.cover = 0
  elseif state.cover > 1 then state.cover = 1 end

  -- What the snow is doing to the grass, pushed rather than pulled (Wind
  -- must never require this file back). The full cover would bury a tuft
  -- outright, so this is the share of it a blade can actually hold: enough
  -- that a snowed meadow stands bowed and half-still, not enough that it
  -- lies flat and stops being grass.
  Wind.grassSnow = state.cover * 0.85

  local Game = game()
  local ow = Game and Game.overworld
  if not (ow and ow.map and ow.player) then return end

  if state.mapId ~= ow.map.id then
    state.mapId = ow.map.id
    GroundFX.invalidate()
    prints = {}
  end

  -- the marks age wherever the walkers are, but only get MADE where there
  -- is snow lying to make one in
  local fill = 1 + (kind == "snow" and GroundFX.PRINT_FILL - 1 or 0)
  for i = #prints, 1, -1 do
    local pr = prints[i]
    pr.t = pr.t + dt * fill
    if pr.t >= GroundFX.PRINT_TTL then table.remove(prints, i) end
  end

  if GroundFX.enabled() and state.cover >= GroundFX.PRINT_FROM
     and Game.stack and Game.stack:top() == ow and not ow.transitioning then
    trackSteps(ow)
  end
end

function GroundFX.update(dt)
  if failed then return end
  local ok, err = pcall(tick, dt or 0)
  if ok then return end
  failed = true
  state.wet, state.cover = 0, 0
  Wind.grassSnow = 0
  prints = {}
  chunks = {}
  if V.mod and V.mod.log then
    V.mod.log:warn("ground fx failed: %s -- the ground is dry for this session",
                   tostring(err))
  end
end

-- ------- the draw
--
-- Called from VoxelScene.render, between the terrain and everything standing
-- on it (see the header for why it is there and not in the overlay).
--
-- Gated on Weather.visible's own question rather than on the accumulated
-- numbers alone: the ground under a roof is not wet however hard it is
-- raining outside, and that answer already exists.
local function openSky(map)
  if not (map and map.def) then return false end
  if not Map.isOutdoor(map.def) then return false end
  return not DayNight.isCanopy(map)
end

-- ------- the snow on the WORLD's own faces
--
-- How white every up-facing voxel goes, 0..1 -- read by the terrain pass
-- (VoxelScene) and handed to the scene shader, which lays it on the faces
-- whose shade says they point up. This is the half of a snowfall no decal
-- could do: a tree's crown, a stone wall's top and a roof's ridge are
-- geometry the camera is already looking at, and painting THEM is the only
-- way snow on them can never float, sink or shear away as the camera turns.
--
-- Declared HERE rather than beside the other two readers at the top of the
-- file, and the position is load-bearing: it closes over `openSky` and
-- `failed`, both of which are locals further down, and a Lua closure written
-- above a local sees a nil global instead -- silently, until the first call.
-- Weather.lua's own header names this trap; this is the same one.
--
-- Gated on the same open sky the drawing is, and on the same row: a cave
-- roof does not get snow on it, and GROUND OFF means off.
function GroundFX.snowTint(map)
  if failed or not GroundFX.enabled() then return 0 end
  if map and not openSky(map) then return 0 end
  return driftAmount() * GroundFX.SNOW_TINT
end

-- A puddle is a piece of the sky lying on the ground, so it wears the sky's
-- own colour -- the horizon band, which is the part of it a shallow pool
-- actually reflects. Normalised to its own brightest channel so only the
-- HUE carries: the scene shader is already multiplying this decal by the
-- hour's light, and taking the sky's brightness as well would darken a
-- night puddle twice.
local function skyHue()
  local ok, pal = pcall(DayNight.palette)
  if not (ok and pal and pal[2]) then return 0.72, 0.80, 0.95 end
  local c = pal[2]
  local m = math.max(c[1], c[2], c[3], 1) / GroundFX.PUDDLE_TONE
  return c[1] / m, c[2] / m, c[3] / m
end

-- How dark a pool is against what it is lying on, and it has to be DARK.
-- Standing water reads by being a hole in the road: at the sky's own
-- brightness a puddle on pale paving was a slightly different pale, visible
-- in the draw count and invisible on the screen. Taken to a bit over half,
-- the body lands at about a third of the street's value while the art's own
-- highlight stays bright -- which is the dark pool with a lit edge every
-- reference of wet ground has.
GroundFX.PUDDLE_TONE = 0.42
GroundFX.PUDDLE_ALPHA = 0.90
GroundFX.DRIFT_ALPHA = 1.0
-- A print is a HOLE in the snow, and a hole reads by being a good deal
-- darker than what it is in -- at half this contrast the trail was there in
-- the draw count and invisible in the screenshot, which is the whole reason
-- this file has a probe.
GroundFX.PRINT_ALPHA = 0.78
GroundFX.PRINT_COLOR = { 0.28, 0.34, 0.48 }

local function drawLayer(map, layer, px, py, offX, offZ, alpha, r, g, b)
  local sheet = atlas(layer:find("^puddle") and "puddle" or layer)
  if not sheet then return 0 end
  local tex = sheet.img
  local model = (offX ~= 0 or offZ ~= 0)
                and Mat4.translate(offX, 0, offZ) or nil
  local c0x = math.floor((px - GroundFX.REACH) / CHUNK)
  local c1x = math.floor((px + GroundFX.REACH) / CHUNK)
  local c0y = math.floor((py - GroundFX.REACH) / CHUNK)
  local c1y = math.floor((py + GroundFX.REACH) / CHUNK)
  local drawn = 0
  love.graphics.setColor(r, g, b, alpha)
  for cy = c0y, c1y do
    for cx = c0x, c1x do
      local mesh = chunkMesh(map, layer, cx, cy)
      if mesh then
        Voxel3D.draw(mesh, tex, model)
        drawn = drawn + 1
      end
    end
  end
  return drawn
end

-- How many meshes and marks the last draw issued -- read by the probe,
-- because "it drew something" is a claim that has to be counted rather than
-- believed.
GroundFX.lastDraws = 0
-- And how many of those were the alpha STAMP (see draw3D). Counted apart
-- from the rest because zero here is a specific claim -- the mask never went
-- down, so nothing in the frame can reflect -- and it is indistinguishable
-- from every other way a puddle can fail to appear if it is added into the
-- same total.
GroundFX.lastStamps = 0

-- The two things a probe needs to tell "nothing was placed" from "it was
-- placed and drawn in the colour of the road": one chunk's mesh, and the
-- colour a pool is actually painted in.
function GroundFX.chunkFor(map, layer, cx, cy)
  return chunkMesh(map, layer, cx, cy)
end

function GroundFX.debugColour()
  local r, g, b = skyHue()
  return ("%.2f"):format(r), ("%.2f"):format(g), ("%.2f"):format(b)
end

-- Every cell in a square block that ends up holding a pool. The spacing rule
-- is the whole of how a wet street reads, and "one per thirteen cells" is a
-- claim about a table rather than about a picture -- so it is asked for as a
-- table.
function GroundFX.puddleCells(map, x0, y0, side)
  local out = {}
  for cy = y0, y0 + side - 1 do
    for cx = x0, x0 + side - 1 do
      if GroundFX.holdsPuddle(map, cx, cy) then out[#out + 1] = { cx, cy } end
    end
  end
  return out
end

function GroundFX.draw3D(scene)
  GroundFX.lastDraws = 0
  GroundFX.lastStamps = 0
  if failed or not GroundFX.enabled() then return end
  local map = scene and scene.map
  local player = scene and scene.player
  if not (map and player) then return end
  if not openSky(map) then return end

  local wetK = puddleAmount()
  local snowK = driftAmount()
  if wetK <= 0.01 and snowK <= 0.01 then return end

  Voxel3D.beginDecals()
  local px, py = player.cellX, player.cellY
  local drawn = 0

  -- The maps a route is CONNECTED to are drawn as terrain in this same
  -- pass, so their ground gets the same treatment: a shower that stopped at
  -- the seam would draw the seam.
  local places = { { map = map, ox = 0, oy = 0 } }
  for _, nb in ipairs(scene.neighbors or {}) do
    if nb.map then places[#places + 1] = { map = nb.map, ox = nb.ox, oy = nb.oy }
    end
  end

  -- Exactly ONE size step per layer is drawn: the meshes are the same set of
  -- cells at three sizes, so drawing two would be drawing the same puddles
  -- twice on top of each other.
  if snowK > 0.01 then
    local a = GroundFX.DRIFT_ALPHA * snowK
    local step = GroundFX.step(snowK)
    for _, place in ipairs(places) do
      local lx = px - math.floor((place.ox or 0) / 16)
      local ly = py - math.floor((place.oy or 0) / 16)
      drawn = drawn + drawLayer(place.map, "drift" .. step, lx, ly,
                                place.ox or 0, place.oy or 0, a, 1, 1, 1)
      -- and the CAPS, after the ground and before everything else: a hedge
      -- with snow on it is what stops a white field reading as fresh paint.
      -- Same step, its own art, its own cells (see crustCell).
      drawn = drawn + drawLayer(place.map, "crust" .. step, lx, ly,
                                place.ox or 0, place.oy or 0, a, 1, 1, 1)
    end
  end

  if wetK > 0.01 then
    local r, g, b = skyHue()
    local a = GroundFX.PUDDLE_ALPHA * wetK
    local rank = "puddle" .. GroundFX.step(wetK)
    -- the one layer that WRITES depth, and the only reason is that the RTX
    -- row reads the depth buffer to find where a puddle's own plane is: a
    -- puddle that is not in there reflects off the road it lies on
    -- (Voxel3D.beginDecals)
    Voxel3D.beginDecals(true)
    for _, place in ipairs(places) do
      local lx = px - math.floor((place.ox or 0) / 16)
      local ly = py - math.floor((place.oy or 0) / 16)
      drawn = drawn + drawLayer(place.map, rank, lx, ly,
                                place.ox or 0, place.oy or 0, a, r, g, b)
    end

    -- ------- and the MARK, which is the whole of how the reflection pass
    -- knows these pixels from a person standing on them
    --
    -- The same meshes, a second time, with the colour write masked down to
    -- the alpha channel and the blend set to replace: the picture does not
    -- change by one bit, and the byte RayFX reads does. Everything the pass
    -- needs to know about a puddle -- exactly which pixels, and no others --
    -- is in the frame it was already going to read, which is why this is not
    -- a second render target and not a fourth guess at geometry. See the
    -- long note over Voxel3D.beginAlphaStamp.
    --
    -- The tag rides in as the layer's own COLOUR alpha, because drawLayer
    -- sets a colour per layer and would otherwise overwrite the stamp's. The
    -- RGB is masked off, so 0,0,0 goes nowhere.
    --
    -- Costs one draw per chunk in reach, of meshes already built and already
    -- resident, and nothing at all when the screen pass is off -- the stamp
    -- refuses to open without a depth buffer to prove somebody will read it.
    local stamped = 0
    if Voxel3D.beginAlphaStamp(Voxel3D.PUDDLE_TAG) then
      for _, place in ipairs(places) do
        local lx = px - math.floor((place.ox or 0) / 16)
        local ly = py - math.floor((place.oy or 0) / 16)
        stamped = stamped + drawLayer(place.map, rank, lx, ly,
                                      place.ox or 0, place.oy or 0,
                                      Voxel3D.PUDDLE_TAG, 0, 0, 0)
      end
      Voxel3D.endAlphaStamp()
    end
    drawn = drawn + stamped
    GroundFX.lastStamps = stamped
    Voxel3D.beginDecals(false)
  end

  -- and the marks on top of the drifts, which is where a footprint is
  if snowK > 0.01 and #prints > 0 then
    local sheet = atlas("print_")
    if sheet then
      local tex = sheet.img
      local c = GroundFX.PRINT_COLOR
      local quad = GroundFX.printQuad()
      if quad then
        for _, pr in ipairs(prints) do
          if math.abs(pr.cx - px) <= GroundFX.REACH
             and math.abs(pr.cy - py) <= GroundFX.REACH then
            local fade = 1 - pr.t / GroundFX.PRINT_TTL
            if fade > 0 then
              love.graphics.setColor(c[1], c[2], c[3],
                                     GroundFX.PRINT_ALPHA * fade * snowK)
              local m = Mat4.mul(
                Mat4.translate(pr.cx * 16 + 8,
                               groundAt(map, pr.cx, pr.cy) + GroundFX.PRINT,
                               pr.cy * 16 + 8),
                Mat4.rotateY(pr.angle))
              Voxel3D.draw(quad, tex, m)
              drawn = drawn + 1
            end
          end
        end
      end
    end
  end

  Voxel3D.endDecals()
  GroundFX.lastDraws = drawn
end

-- The single quad every footprint is drawn with, centred on the origin so
-- the matrix can turn it about the walker's own cell. Built once, on the
-- FIRST frame of the strip it is wearing -- an override may be a strip like
-- the other two, and the first frame of one is the whole of a one-frame
-- sheet either way.
local printMesh = nil
function GroundFX.printQuad()
  if printMesh == nil then
    local sheet = atlas("print_")
    local n = (sheet and sheet.n) or 1
    local verts, indices = {}, {}
    pushDecal(verts, indices, 0, 0, 0, 15,
              0.05 / (n * 16), (16 - 0.05) / (n * 16))
    printMesh = Voxel3D.newMesh(verts, indices) or false
  end
  return printMesh or nil
end

-- Window resize / hot reload drops the GPU objects; the shapes are facts
-- about the map and are rebuilt on demand exactly as the terrain's are --
-- which is also what picks up an assets/ground/ file dropped in while the
-- game is running.
function GroundFX.dropGPU()
  chunks = {}
  printMesh = nil
  atlases = {}
end

-- ------- and telling the RAIN where the water is
--
-- Weather picks the cells its splashes burst on, and it picked them off
-- "walkable or water" -- so in a downpour the rings landed on the dry road
-- BESIDE the pools and never in them, which is the one place rain is
-- actually visible. A wet street read as two unrelated effects bolted
-- together for exactly that reason.
--
-- It cannot ask this file directly: Weather is required BY this file, so a
-- require back is a cycle. The answer is PUSHED instead, the way `Water.wet`
-- is pushed the other way and for the same reason.
--
-- Written at the FOOT of the file, and the position is load-bearing for the
-- same reason `snowTint`'s is: this closes over `failed` and `puddleAmount`,
-- and a Lua closure written above a local sees a nil global instead --
-- silently, until the first call. See this file's own note over snowTint,
-- which is the same trap.
--
-- It answers false while there is nothing SHOWING. The set of cells that can
-- hold a pool is a fact about the map and never changes, but for the first
-- half of every shower none of them has water in it yet, and a splash aimed
-- at an invisible puddle is a splash aimed at nothing.
Weather.poolAt = function(map, cx, cy)
  if failed or not GroundFX.enabled() then return false end
  if puddleAmount() <= 0.01 then return false end
  return GroundFX.holdsPuddle(map, cx, cy)
end

return GroundFX
