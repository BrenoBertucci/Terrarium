-- Voxel world mode: assemble and draw one frame of the 3D scene.
--
-- World space is world pixels and shares its origin with the 2D paths, so
-- the terrain mesh needs no transform at all and a connected map just
-- translates by the same (ox, oy) the flat renderer already offsets it by.
--
-- Order is: the sun's shadow pass, then terrain, then characters, then a 2D
-- overlay for the field FX. There is no y-sort anywhere -- the depth buffer
-- resolves occlusion, which is the whole point of the mode. Walk behind a
-- building and the building is simply in front.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local Voxel3D = V.require("Voxel3D")
local ShadowMap = V.require("ShadowMap")
local ChunkMesher = V.require("ChunkMesher")
local SpriteBillboards = V.require("SpriteBillboards")
local TileShape = V.require("TileShape")
local TerrainAtlas = V.require("TerrainAtlas")
local Voxel = V.require("VoxelState")
local Sky = V.require("Sky")
local DayNight = V.require("DayNight")
local GroundFX = V.require("GroundFX")
local Quality = V.require("Quality")
local Wind = V.require("Wind")
local Water = V.require("Water")
local Roamer = V.require("Roamer")
local StreetLamps = V.require("StreetLamps")
local Skyline = V.require("Skyline")
local PaletteFX = require("src.render.PaletteFX")
local Map = require("src.world.Map")

local VoxelScene = {}

-- When the grass pass last ran, in love.timer seconds. The grass springs
-- and the walked trail are integrated per PASS rather than per frame (see
-- the crush block in render), so this is what tells them how much time
-- actually went by. nil until the first pass.
local lastGrassAt = nil

-- What the active display mode actually paints with.
--
-- paletteFor hands back a map's RAW SGB zone palette, and that is not what
-- any of the non-colour modes draw. The flat path runs it through
-- PaletteFX.effectiveColors on the way to the shade-remap shader, and that
-- call IS where GRAY, INVERTED and CLASSIC happen -- OG / OG INV replace
-- the palette with the DMG greys (inverted for the latter), CLASSIC
-- replaces it with the green DMG set, and GBC INV permutes the zone's own
-- shades. GBC and RED++ pass through untouched.
--
-- This pass has no shader to apply that in: colour is baked into the atlas
-- and into the sprite sheets ahead of the draw, so it has to run the same
-- transform itself. Without it every mode that is not already a colour mode
-- comes through wearing the SGB palette -- grey and inverted both rendering
-- as plain SGB blue.
local function modeColors(paletteFor, map)
  local c = paletteFor and paletteFor(map) or nil
  return PaletteFX.effectiveColors(c)
end

VoxelScene._modeColors = modeColors   -- named for the suite

-- ------------------------------------------------------------------ sky --
--
-- The void behind the diorama is SKY, at every rung -- so the world reads as
-- standing under something rather than floating on a black plate.
--
-- What is up there differs by rung, and the sky follows it rather than being
-- retuned for each. At 75 degrees the camera is pitched far enough over that
-- the horizon is genuinely in frame, and the bands run down to meet it. At the
-- steeper rungs the horizon is above the top edge and the void that shows is
-- where the ground runs OUT -- past the map edge, past the curve -- so the
-- bands take a fixed slice of the frame instead (lib/Sky.lua, Sky.SPAN) and the
-- haze below them fills the rest.
--
-- INDOORS THERE IS NO SKY. A house, a cave or a gym is a room with a
-- ceiling, and the void past its walls is the outside of a box, not open
-- air. Map.isOutdoor is the same test the engine uses for door SFX and the
-- town map, and the same one Structures already asks to decide whether a
-- map rings with trees.
--
-- The colour is a four-shade ramp shaped like a world palette so the
-- display mode can transform it exactly like one: GRAY gets a grey sky,
-- CLASSIC a green one, GBC INV a dark one, and the colour modes the blue.
-- A hardcoded blue would sit wrong in every non-colour mode -- the same
-- mismatch the terrain bake had.
--
-- This ramp is the FLAT sky -- what a caller clears the void to. The free-roam
-- camera's banded sky has a palette of its own (lib/Sky.lua), transformed the
-- same way by the same seam; they are separate because the flat one also has to
-- serve an indoor void and a battle's arena, which want a colour rather than a
-- sky.
local SKY_SHADES = { { 222, 242, 255 }, { 135, 196, 240 },
                     { 64, 120, 192 }, { 16, 40, 80 } }
local SKY_SHADE = 2       -- the ramp's "sky" proper; 1 is its highlight

-- the ramp as the display mode has it, which is the only form anything here
-- should be reading it in
local function skyRamp()
  return PaletteFX.effectiveColors(SKY_SHADES) or SKY_SHADES
end

-- Full strength at every rung: the sky is painted wherever the diorama is.
--
-- The ramp that is left is for ARRIVAL alone. Switching the mode on eases the
-- camera up from flat, and the sky comes up with it over the first few degrees
-- rather than appearing whole on the keypress -- which is also what keeps a
-- top-down camera, where there is no void worth speaking of, from painting one.
local SKY_FADE_DEG = 8

local function skyStrength(angleRad)
  local deg = math.deg(angleRad or 0)
  if deg <= 0 then return 0 end
  local t = deg / SKY_FADE_DEG
  return t < 1 and t or 1
end

-- One shade off the sky ramp, transformed by the display mode, as an
-- {r, g, b, a} in 0..1. `shade` picks the rung (SKY_SHADE is the sky
-- proper; 4 is its darkest, which is what an indoor void wants).
function VoxelScene.skyShade(shade, alpha)
  local shades = skyRamp()
  local c = shades[shade] or SKY_SHADES[shade] or SKY_SHADES[SKY_SHADE]
  return { c[1] / 255, c[2] / 255, c[3] / 255, alpha or 1 }
end

-- The sky `map` stands under at strength `t`, or nil where there is no sky
-- to paint: indoors, or with the horizon out of frame.
--
-- One flat colour, which is what a caller that only needs something to clear the
-- void to wants -- the overworld battle's arena shot is one of those. The
-- gradient is added on top of this by skyFor, for the free-roam camera alone.
function VoxelScene.skyColor(map, t)
  if not (map and map.def and Map.isOutdoor(map.def)) then return nil end
  if not t or t <= 0 then return nil end
  local sky = VoxelScene.skyShade(SKY_SHADE, t)
  -- outdoors the flat fill follows the CLOCK: it becomes the hour's haze --
  -- gold at dusk, navy at night -- so a battle staged on the map at
  -- midnight is under a midnight void, not a noon one. Free-roam is
  -- unchanged by this: Sky.dress overwrites the fill with the same value.
  local haze = Sky.haze()
  if haze then sky[1], sky[2], sky[3] = haze[1], haze[2], haze[3] end
  return sky
end

-- The free-roam sky: the flat one above, dressed with the banded gradient
-- (lib/Sky.lua).
--
-- Only here, and deliberately. This is the sky the walking camera stands under,
-- where the horizon is a quarter of the way down the frame at the top rung and
-- one flat blue reads as a wall of paint. A battle is a staged shot with its own
-- placed camera whose horizon sits above the frame entirely, so it keeps the
-- flat fill it has always had -- there is no gradient to see from down there,
-- and the arena's look is not this rung's to change.
local function skyFor(map)
  local sky = VoxelScene.skyColor(map, skyStrength(Voxel.angle))
  if not sky then return nil end
  sky = Sky.dress(sky)
  if sky then sky.map = map end
  return sky
end

VoxelScene._skyFor = skyFor           -- named for the suite
VoxelScene._skyStrength = skyStrength

-- A facing as a yaw about +Y, kept for callers that reason about which way
-- an entity points (the mod exports it). The character cards themselves
-- never yaw -- they face south and lean, like the flat game.
local YAW = {
  down = 0,
  up = math.pi,
  right = math.pi / 2,
  left = -math.pi / 2,
}

-- The ground height a cell stands at, so a character on a ledge stands on
-- top of it rather than sunk into it. Uses the same bottom-left collision
-- tile the engine walks on (Map:cellTile).
local function groundAt(map, cellX, cellY)
  -- Off the map, cellTile border-extends into the map's borderBlock --
  -- which on maps ringed with trees is a RAISED tile. The only entity
  -- ever standing off-map is the player mid seam-step (placed one cell
  -- before the connection entry), and the ground actually rendered
  -- there is the departed neighbour's flat walkway: height 0. Without
  -- this, crossing into such a map hoisted the walker tree-high for
  -- exactly one step -- the "hops like a ledge" seam bug.
  if not map:inBounds(cellX, cellY) then return 0 end
  local shapes = TileShape.forMap(map)
  local s = shapes[map:cellTile(cellX, cellY)]
  if not s then return 0 end
  -- a recessed class (water) still supports whatever stands on it; only
  -- raised ground lifts the model.  Stairs never do: the class height is
  -- the flight's TALL end, but the player enters at floor level and the
  -- warp fires as they step in -- lifting them onto the geometry read as
  -- climbing an invisible block
  if s.art == "stair" then return 0 end
  -- Recessed water sits at TileShape.water (-2).  Callers that need the
  -- LIVE surface (swell under a surfer / water roamer) ask Water.surfaceAt
  -- with the entity's pixel position; this answer is only the still floor.
  if s.h and s.h < 0 then return s.h end
  return s.h > 0 and s.h or 0
end

-- Ground under an entity this frame.  Water is the only class whose floor
-- MOVES: the same two sines the mesh rides (Water.heightAt).  Anything
-- with `surfing` set (the player mid-Surf, a water roamer) stands on the
-- live surface at its own pixel centre so feet and plane rise together.
-- Land uses the cell's static height; mid-step hop lift still comes from
-- pose() as before.
local function entityGround(map, e, px, py)
  local wx = (px or 0) + 8
  local wz = (py or 0) + 8
  if e and (e.surfing or (e.roamer and e.kind == "water")) then
    local ok, y = pcall(Water.surfaceAt, wx, wz)
    if ok and y then return y end
    return Water.BASE or -2
  end
  -- Walkable ice: height identity is still water, but the effective floor is
  -- the frozen surface (Water.surfaceAt), not the land groundAt of -2.
  if e and map and map.isWaterCell and Water.walkableIce then
    local wok, water = pcall(map.isWaterCell, map, e.cellX, e.cellY)
    if wok and water then
      local iok, ice = pcall(Water.walkableIce, wx, wz)
      if iok and ice then
        local ok, y = pcall(Water.surfaceAt, wx, wz)
        if ok and y then return y end
        return (Water.BASE or -2) + (Water.iceLift and Water.iceLift() or 0)
      end
    end
  end
  return groundAt(map, e.cellX, e.cellY)
end

-- Whether what stands on this cell has a FLAT top at groundAt's height, or a
-- shape carved out of its own artwork.
--
-- groundAt answers how HIGH the profile puts a cell, and for a box that is
-- also where its top face is: a wall, a roof, a ledge and a fence are all
-- 16x16 lids at exactly that height. For the round classes it is not. A
-- `cylinder` or `canopy` cell is a voxel HULL cut from the drawing's own
-- outline (Structures.buildCylinders) and a `billboard` or `post` is a
-- per-pixel slab, so the class height is where the crown's HIGHEST voxel
-- lands and the surface falls away from it in every direction -- by half a
-- cell at the rim of a dome.
--
-- Anything that wants to lie ON a cell has to know the difference, because a
-- flat quad at the class height of a rounded crown touches it at one point
-- and hangs in the air everywhere else. See GroundFX's crusts, which is the
-- one caller and the reason this exists.
local ROUND_ART = {
  cylinder = true,     -- tree canopies, stumps: hulls cut from the art
  canopy = true,       -- the 2x2-cell forest trees, same carve at 32px
  billboard = true,    -- signs and props: per-pixel standing slabs
  post = true,         -- fence posts, one depth band per cell
  grass = true,        -- tufts standing in rows
  flower = true,
}

local function flatTop(map, cellX, cellY)
  if not map:inBounds(cellX, cellY) then return false end
  local shapes = TileShape.forMap(map)
  local s = shapes[map:cellTile(cellX, cellY)]
  -- no shape is flat ground at zero, which groundAt already reports as 0 and
  -- every caller here rejects on its own
  if not s then return true end
  return not ROUND_ART[s.art]
end

VoxelScene.YAW = YAW
-- shared with the overworld battle, which stands its mons on map cells and
-- needs the same answer about what height "the floor" is there
VoxelScene.groundAt = groundAt
VoxelScene.flatTop = flatTop

-- Camera-ward pull distance for billboards (and the grass rows, which
-- must keep their relative depth to feet): just enough that a leaned-back
-- slab clears the wall it leans over. The lean flattens toward top-down,
-- so the needed pull grows exactly as real occlusion stops mattering.
function VoxelScene.pull(a)
  return 6 + math.max(0, 16 * math.cos(a) - 8) / math.max(math.sin(a), 0.2)
end

-- The sheet frame and mirror flag the 2D path would draw for this pose
-- (same tables as SpriteRenderer). Shared by the billboard pass and the
-- shadow pass so a walking character's shadow swings its legs too.
local function frameFor(def, facing, phase, flip)
  local SR = require("src.render.SpriteRenderer")
  local frame, mirror = 0, false
  if (def.frames or 1) > 1 then
    frame = (def.walker and phase == 1) and SR.WALK[facing]
            or SR.STAND[facing]
    mirror = facing == "right"
      or ((facing == "down" or facing == "up") and phase == 1 and flip)
  end
  return frame, mirror
end

-- FALLBACK ONLY (see castShadows below). Draw one entity's drop shadow as
-- a decal: its current sprite frame as a single quad, flattened onto the
-- ground along the sun line (Voxel3D.shadowMatrix). Runs inside
-- beginShadows, which supplies the translucent black; the texture is only
-- consulted for its alpha, so no palette work is needed.
local function drawShadow(sprite, px, py, facing, phase, flip, gh, lift,
                          waterline)
  local def = sprite.def
  local frame, mirror = frameFor(def, facing, phase, flip)
  local mesh = SpriteBillboards.shadowQuad(def, frame, waterline or 0)
  if not mesh then return end
  Voxel3D.draw(mesh, sprite:resolveImage(),
               Voxel3D.shadowMatrix(px, py, gh, lift, mirror))
end

-- Where a billboard character's card stands: on the middle of its cell at
-- height `y`, pivoted at the feet and tipped back by exactly the camera's
-- pitch. The slab is built centred on its sprite plane (z = 0), so only the
-- x anchor shifts; the relief bulges symmetrically front and back of it.
--
-- Shared by the solid draw and the silhouette below, so the two can never
-- drift apart -- a silhouette standing anywhere but exactly behind the
-- figure would read as a second character.
local function billboardMatrix(px, py, y, mirror)
  local Voxel = V.require("VoxelState")
  local m = Mat4.mul(Mat4.translate(px + 8, y, py + 8),
                     Mat4.rotateX(Voxel.angle - math.pi / 2))
  if mirror then m = Mat4.mul(m, Mat4.scale(-1, 1, 1)) end
  return Mat4.mul(m, Mat4.translate(-8, 0, 0))
end

local function billboardPull()
  local Voxel = V.require("VoxelState")
  return VoxelScene.pull(math.max(Voxel.angle, 0.05))
end

-- An authored FIGURE's card -- a person the tileset draws INTO a piece of
-- furniture, cut out by the profile's mask (Structures.buildFigures). It is
-- a sprite, so it gets the sprite treatment: the mesh arrives in its own
-- local space with its feet on y = 0, and this stands it at its drawn
-- position and tips it back by exactly the camera's pitch -- the same
-- pivot-at-the-feet lean billboardMatrix gives a character, so the man on
-- the Pokemon Center couch reads face-on at every tilt like the NPCs
-- around him. No cell centring: unlike a character he is not standing on a
-- cell, he is standing where he was drawn, which may straddle two.
local function figureMatrix(f, offX, offZ)
  local Voxel = V.require("VoxelState")
  return Mat4.mul(Mat4.translate(f.wx + (offX or 0), f.y, f.wz + (offZ or 0)),
                  Mat4.rotateX(Voxel.angle - math.pi / 2))
end

-- What the sun sees: the same card UNLEANED and flattened, exactly as
-- Voxel3D.casterMatrix does it for a character.
local function figureCaster(f, offX, offZ)
  return Mat4.mul(
    Mat4.translate(f.wx + (offX or 0), f.y, f.wz + (offZ or 0)),
    Mat4.scale(1, 1, 0))
end

-- Every figure on `map`, drawn with `draw(mesh, model, caster)`.
local function eachFigure(map, offX, offZ, draw)
  for _, f in ipairs(ChunkMesher.figures(map) or {}) do
    draw(f.mesh, figureMatrix(f, offX, offZ), figureCaster(f, offX, offZ))
  end
end

-- Draw one posed entity. Returns true if 3D geometry carried it, false
-- when nothing could be built and the caller should fall back.
-- `colors` is the 4-color world palette the entity stands under in the SGB
-- modes (nil under RED++/trueColor): the 2D path colorizes sprites with a
-- screen-space shader the voxel canvas never runs through, so the model's
-- texture gets the palette baked in instead (TerrainAtlas.forSprite).
-- `lift` raises the figure off the ground plane (ledge hops arc UP in 3D,
-- where the 2D path could only slide the sprite north).
local function drawEntity(sprite, px, py, facing, phase, flip, gh, colors,
                          lift, waterline)
  local def = sprite.def
  local tex = sprite:resolveImage()
  if colors and not def.trueColor then
    tex = TerrainAtlas.forSprite(def.image, colors) or tex
  end
  local y = gh + (lift or 0)

  -- pick the very frame the 2D path would draw (same tables). The card
  -- always faces SOUTH -- the direction the 2D game implies -- and only
  -- LEANS BACK, pivoting at its feet, by exactly the camera's pitch, so
  -- at every tilt level the sprite reads face-on like the flat game.
  -- No camera-tracking yaw: every sprite leans in parallel.
  -- waterline > 0: only the top of the card is built, origin at the
  -- waterline (SpriteBillboards), so a swimming mon is cut by the pond
  -- rather than standing on it.
  local frame, mirror = frameFor(def, facing, phase, flip)
  local mesh = SpriteBillboards.mesh(def, frame, waterline or 0)
  if not mesh then return false end
  -- Camera-ward pull (applied per vertex in the shader, along each
  -- vertex's own eye ray, so it is a PURE depth bias with zero screen
  -- drift): lets the leaned-back head win against the wall it leans
  -- OVER while a character genuinely BEHIND a building is dozens of
  -- pixels deeper and still loses, so real occlusion works.
  -- the same card UNLEANED -- and SNUGGED, exactly as the sun stored it
  -- (castShadows draws this mesh through ShadowMap.snug) -- is where each
  -- vertex asks whether the light reached it; see ShadowMap.snug for why
  -- the lookup must match the stored transform to the letter
  Voxel3D.draw(mesh, tex, billboardMatrix(px, py, y, mirror),
               billboardPull(),
               ShadowMap.snug(Voxel3D.casterMatrix(px, py, y, mirror)))
  return true
end

VoxelScene.drawEntity = drawEntity

-- The player's silhouette, for wherever the scenery is standing in front of
-- them (Voxel3D.beginGhost inverts the depth test around this call).
--
-- The same flat card the solid pass and the sun pass draw. That it has no
-- self-overlap is what makes it safe here: with the depth test inverted, a
-- mesh carrying both front and back faces would read its own back faces as
-- "behind something" and repaint the figure on open ground, occluded or
-- not. One quad cannot do that, and cannot double-blend into a mottled
-- patch either. A silhouette is an outline, so an outline is the right
-- mesh for it.
local function drawGhost(p)
  local def = p.sprite.def
  local frame, mirror = frameFor(def, p.facing, p.phase, p.flip)
  local mesh = SpriteBillboards.shadowQuad(def, frame)
  if not mesh then return end
  local tex = p.sprite:resolveImage()
  if p.colors and not def.trueColor then
    tex = TerrainAtlas.forSprite(def.image, p.colors) or tex
  end
  local y = p.gh + (p.lift or 0)
  Voxel3D.draw(mesh, tex, billboardMatrix(p.px, p.py, y, mirror),
               billboardPull())
end

-- Render the world. `state` is the OverworldState; `vw`/`vh` the world view
-- size in world pixels; `w`/`h` the pixel size of the canvas to render
-- into; `paletteFor(map)` yields a map's 4-color world palette (nil in the
-- color modes whose atlas is already true color). Returns the finished
-- canvas, or nil if the 3D pass could not run (headless, no depth support)
-- so the caller can fall back to 2D.
-- The last live-set key, so eviction only runs when the neighbourhood
-- actually changes (a map crossing), not every frame.
local lastLiveKey = nil

-- Request everything `state`'s frame wants and evict what it no longer
-- does; returns the current map's terrain mesh (or nil while it builds)
-- and the neighbour meshes ready to draw. render() calls this for the
-- frame it is drawing, and the pipeline's update hook calls it EVERY
-- frame -- including the frames a warp's Transition covers, when the
-- world pass is off. That update-side call is what lets a door fade hide
-- the destination's build: the map swaps behind the fade, and waiting
-- for the first visible frame to request meshes would show the flat
-- fallback while the first slices run.
function VoxelScene.prefetch(state)
  local Voxel = V.require("VoxelState")

  -- The live set is the current map plus its rendered neighbours. When
  -- it changes, everything outside it (and the previous set, which
  -- ChunkMesher retains so stepping into a house keeps the town warm)
  -- is evicted -- meshes released, analysis dropped -- so memory stays
  -- bounded by the neighbourhood instead of growing with every area
  -- ever visited.
  local liveKey = state.map.id
  local live = { [state.map.id] = true }
  for _, nb in ipairs(state.neighbors or {}) do
    live[nb.map.id] = true
    liveKey = liveKey .. "|" .. nb.map.id
  end
  if liveKey ~= lastLiveKey then
    lastLiveKey = liveKey
    ChunkMesher.setLive(live)
    -- RED++ bakes one atlas per map, so its animated copy is per map too
    -- and is bounded by the same neighbourhood
    TerrainAtlas.setLive(live)
  end

  -- masks: where connected neighbour BODIES sit, so the border ring is
  -- suppressed under them (see runGeometry)
  local masks = {}
  for _, nb in ipairs(state.neighbors or {}) do
    masks[#masks + 1] = { nb.ox, nb.oy,
                          nb.ox + nb.map.def.width * 32,
                          nb.oy + nb.map.def.height * 32 }
  end

  -- Builds are asynchronous (ChunkMesher.pump runs in the pipeline's
  -- update): request what this frame wants and draw what is ready.
  -- The current map draws its body-only mesh while the full one (the
  -- border ring) is still building -- a seam crossing promotes a
  -- neighbour whose body is already cached, and only the RING arrives
  -- a few frames later (mostly hidden behind the map just left). The
  -- body itself keeps the same trees and props as the full mesh; it is
  -- not a lower LOD, so the world does not "load in" when you step
  -- across. A neighbour missing its body-only mesh draws its cached
  -- FULL mesh instead -- a crossing demotes the map just left, and it
  -- must not vanish from behind the player while its body variant
  -- builds; its ring is already masked out under this map's body, so
  -- the stand-in is safe.
  -- COLD is a map nothing has ever built anything for: a door, a Fly
  -- landing, a blackout -- anywhere that was not a drawn neighbour a moment
  -- ago. The fallback below has always wanted the body-only variant to
  -- stand in while the full one cooks, and on a map crossed into from a
  -- seam it is there, because the map spent the previous minute being a
  -- neighbour and neighbours are asked for exactly that. On a cold map
  -- nobody ever asked, so the fallback fell back to nothing and the scene
  -- sat on the flat 2D path until the FULL mesh landed -- measured at 128
  -- frames, over two seconds, walking onto a fresh map.
  --
  -- So the cheap variant is queued FIRST and the full one drops a tier
  -- behind it: same two meshes, same budget, the one that can be shown
  -- soonest goes first. The tier is given back the moment there is
  -- something to draw, and request() only ever promotes, so the full mesh
  -- does not lose its place -- it waits behind a stand-in instead of
  -- behind an empty screen.
  local cold = not (ChunkMesher.peek(state.map, false)
                    or ChunkMesher.peek(state.map, true))
  if cold then ChunkMesher.request(state.map, true, nil, true) end
  local terrain = ChunkMesher.request(state.map, false, masks,
                                      cold and ChunkMesher.HOLE or true)
  if not terrain then
    terrain = ChunkMesher.peek(state.map, true)
  end
  local nbMesh = {}
  for i, nb in ipairs(state.neighbors or {}) do
    -- A neighbour holding NEITHER variant is a gap in the world: nothing
    -- is drawn at its offset and the sky clear behind the scene shows
    -- through it. One holding the other variant is only waiting on an
    -- upgrade -- its ground is covered either way -- so it stays idle and
    -- does not compete with a map that is showing sky. The difference is
    -- exactly the one the priority tier exists for, and it is answered
    -- here rather than in ChunkMesher because this is the loop that knows
    -- what is about to be drawn.
    local held = ChunkMesher.peek(nb.map, true)
                 or ChunkMesher.peek(nb.map, false)
    nbMesh[i] = ChunkMesher.request(nb.map, true, nil,
                                    (not held) and ChunkMesher.HOLE or nil)
                or ChunkMesher.peek(nb.map, false)
  end
  Voxel.ready = terrain ~= nil
  return terrain, nbMesh
end

-- Capture every entity's pose for this frame. pose() advances the hop /
-- surf bob / spinner timers, so it must be called EXACTLY once per entity
-- per frame -- the sun pass and the character pass then read the same
-- answer instead of disagreeing by a tick. Ghost NPCs live on a neighbour
-- map, so their position, ground lookup and palette all belong to that
-- map. pose() returns the VISUAL y (ledge hops arc it, surfing bobs it);
-- the difference from the entity's base y becomes vertical LIFT in 3D, so
-- a hop rises off the ground instead of sliding north.
-- Returns the pose list and, separately, the PLAYER's entry in it (nil
-- during a Fly animation, which draws the player itself and is skipped
-- below). Only that one entry gets the see-through treatment: NPCs and the
-- ghosts standing on a neighbour map are left to honest occlusion, because
-- it is only your own character you cannot afford to lose behind a roof.
local function posesOf(state, spriteColors)
  local colors = spriteColors(state.map)
  local posed = {}
  local me = nil
  for _, g in ipairs(state.ghosts or {}) do
    local sprite, vx, vy, facing, phase, flip = g.npc:pose()
    local gpx, gpy = vx + g.ox, g.npc.py + g.oy
    local waterRoamer = g.npc.roamer and g.npc.kind == "water"
    local onWater = g.npc.surfing or waterRoamer
    -- On water the swell is already in entityGround; pose()'s bob is for
    -- the 2D blit only and must not be added again as lift.  Waterline cut
    -- while swimming; full body on ice; freeze/thaw anim blends the cut.
    local wl, hop = 0, 0
    if waterRoamer then
      local okc, cut = pcall(Water.waterlineCut, gpx + 8, gpy + 8,
                             Roamer.WATERLINE)
      wl = (okc and cut) or Roamer.WATERLINE
    end
    if onWater then
      local okl, lift = pcall(Water.standAnimLift, gpx + 8, gpy + 8)
      hop = (okl and lift) or 0
    end
    posed[#posed + 1] = {
      sprite = sprite, px = gpx, py = gpy,
      facing = facing, phase = phase, flip = flip,
      gh = entityGround(g.map or state.map, g.npc, gpx, gpy) + hop,
      lift = onWater and 0 or (g.npc.py - vy),
      waterline = wl,
      colors = spriteColors(g.map or state.map),
    }
  end
  for _, e in ipairs(state.entities or {}) do
    if not (state.flyAnim and e == state.player) then
      local sprite, vx, vy, facing, phase, flip = e:pose()
      local waterRoamer = e.roamer and e.kind == "water"
      local onWater = e.surfing or waterRoamer
      -- Grass roamers: pose() already leaned px (vx); recompute the same
      -- lean on map-y so the 3D card sits at the leaned cell centre.  lift
      -- is then only the breath/hop (drawPy - vy), never the wind twice.
      local drawPx, drawPy = vx, e.py
      if e.roamer and e.kind == "grass" then
        local ok, _, lz = pcall(Wind.leanAt, e.px + 8, e.py + 8,
                                Roamer.WIND_HEIGHT)
        if ok and lz then drawPy = e.py + lz end
      elseif e ~= state.player and not e.roamer and not onWater then
        -- NPC "cloth" substitute: whole billboard leans with the meadow wave
        -- (no skeleton in Gen 1 sprites). heightFrac 0.55 = torso, not feet.
        -- Share 0.55 keeps it subtler than grass tips so people do not skate.
        local ok, lx, lz = pcall(Wind.leanAt, e.px + 8, e.py + 8, 0.55)
        if ok and lx then
          drawPx = drawPx + lx * 0.55
          drawPy = drawPy + lz * 0.55
        end
      end
      -- Swim cut / ice stand / freeze-thaw blend (keeps Surf as the mount).
      local wl, hop = 0, 0
      if waterRoamer then
        local okc, cut = pcall(Water.waterlineCut, drawPx + 8, drawPy + 8,
                               Roamer.WATERLINE)
        wl = (okc and cut) or Roamer.WATERLINE
      end
      if onWater then
        local okl, lift = pcall(Water.standAnimLift, drawPx + 8, drawPy + 8)
        hop = (okl and lift) or 0
      end
      -- Player mid-Surf also gets the freeze/thaw hop + full body on ice
      -- (no waterline cut on the player card, but hop still reads).
      posed[#posed + 1] = {
        sprite = sprite, px = drawPx, py = drawPy,
        facing = facing, phase = phase, flip = flip,
        gh = entityGround(state.map, e, drawPx, drawPy) + hop,
        lift = onWater and 0 or (drawPy - vy),
        waterline = wl,
        colors = colors,
      }
      if e == state.player then me = posed[#posed] end
    end
  end
  return posed, me
end

-- ------- what is worth submitting
--
-- The world XZ box a pass has to cover, as {x0, z0, x1, z1} in world
-- pixels. Terrain chunks outside it are not drawn (ChunkMesher's cells,
-- Voxel3D.drawGroup's test), and a connected neighbour whose whole body
-- falls outside it costs nothing at all -- which is most of them most of
-- the time, because a map is only ever connected on the side you are not
-- looking at.
--
-- Deliberately generous on all four sides. Every term here is a bound on
-- something the camera might see, and being wrong about that is a hole in
-- the world where being wrong the other way is a few thousand wasted
-- triangles.
--
--   NORTH   how far the camera still sees ground (ShadowMap.groundReach --
--           the same answer the light frustum is fitted to), but taken
--           against a cap twice as far out. The sun pass can let the far
--           field go because its shader fades those shadows out anyway;
--           terrain that stops has an edge on it. At the steep rungs the
--           horizon is genuinely in frame and this reaches past any map.
--           A tall thing standing on ground just past this still shows
--           above it -- that is handled at the draw, per chunk, out of the
--           height each one actually reaches rather than out of the
--           tallest one that could exist anywhere.
--   SIDES   the view widens with distance, so the far ground spans more
--           than the near ground does; half the depth is the same
--           serviceable stand-in ShadowMap.fit uses for the true spread.
--   SOUTH   the camera sits south of its focus, so a little behind.
--
-- `forSun` adds the caster margin on the two sides shadows come FROM. The
-- sun hangs southeast, so what casts onto visible ground stands south and
-- east of it -- the same asymmetry, and the same two sides, as fit().
VoxelScene.FAR_CAP = 5      -- multiples of the view height; ShadowMap's own is 2.5

function VoxelScene.bounds(cx, cy, vw, vh, forSun)
  local reach = ShadowMap.groundReach(vh, VoxelScene.FAR_CAP)
  local north = reach
  local spread = reach * 0.5 + 64
  local sun = 0
  if forSun then
    sun = ShadowMap.HEIGHT
          * math.max(math.abs(ShadowMap.KX), math.abs(ShadowMap.KZ)) + 24
  end
  return { cx - vw / 2 - spread, cy - north,
           cx + vw / 2 + spread + sun, cy + vh / 2 + 64 + sun }
end

-- The same box in a connected neighbour's own coordinates: its geometry is
-- built about its own origin and placed with translate(ox, oy), so the box
-- has to come back the other way rather than the mesh going forward.
local function shifted(b, ox, oy)
  return { b[1] - ox, b[2] - oy, b[3] - ox, b[4] - oy }
end

-- ------- the glint's drive
--
-- A reflection is something the VIEWPOINT does, so the window glint is fed
-- by the camera's own travel rather than by a clock: its phase advances
-- with distance covered and its strength fades in over a few steps of
-- walking and back out within a beat of standing still. Stand still and
-- the glass is still; move and the light crosses it.
-- The rate is slow on purpose: the sweep pattern lives in the pane's own
-- texels (see the scene shader), so this is a FRACTION of a texel per world
-- pixel walked -- one full pass of the glint across a pane per eight or so
-- cells of travel, with no frame ever jumping it far enough to strobe.
VoxelScene.GLINT_RATE = 0.05     -- radians of sweep per world pixel travelled
VoxelScene.GLINT_IN = 0.12      -- strength gained per moving frame
VoxelScene.GLINT_OUT = 0.08     -- and lost per resting frame

function VoxelScene.glintStep(g, cx, cy)
  local dist = 0
  if g.x then
    dist = math.abs(cx - g.x) + math.abs(cy - g.y)
  end
  g.x, g.y = cx, cy
  g.phase = ((g.phase or 0) + dist * VoxelScene.GLINT_RATE) % (2 * math.pi)
  if dist > 0.05 then
    g.amp = math.min(1, (g.amp or 0) + VoxelScene.GLINT_IN)
  else
    g.amp = math.max(0, (g.amp or 0) - VoxelScene.GLINT_OUT)
  end
  return g
end

local glint = {}

-- A stamp of everything the sun pass depends on. Nothing in it moving
-- means the shadow map it produced last frame is still exactly right, and
-- redrawing the whole world from the sun would buy nothing -- which is
-- most of a dialog, a menu, or any moment standing still.
local sigBuf = {}
local function shadowSignature(terrain, nbMesh, posed, cx, cy, vw, vh)
  local n = 0
  local function put(v)
    n = n + 1
    sigBuf[n] = v
  end
  -- quarter-pixel camera granularity: the light frustum is snapped to
  -- whole texels anyway, each a third of a world pixel
  put(math.floor(cx * 4))
  put(math.floor(cy * 4))
  -- the view size and the camera PITCH are both what the light frustum is
  -- fitted to (a lower camera sees further north, so the box grows), so a
  -- zoom step, a window resize or a rung change invalidates the map even
  -- standing perfectly still
  put(vw); put(vh)
  put(math.floor((V.require("VoxelState").angle or 0) * 512))
  -- the sun itself: the cycle swings the shear as the clock runs, and a map
  -- lit from somewhere new must be redrawn from there too. Quantised by the
  -- rig's own step (DayNight.rigTime), so a running cycle redraws the map a
  -- few times a minute rather than every frame.
  put(math.floor(ShadowMap.KX * 128))
  put(math.floor(ShadowMap.KZ * 128))
  put(tostring(terrain))
  for i = 1, #nbMesh do put(tostring(nbMesh[i])) end
  for _, p in ipairs(posed) do
    put(p.sprite.def.image)
    put(p.px); put(p.py); put(p.gh); put(p.lift or 0)
    put(p.facing); put(p.phase); put(p.flip and 1 or 0)
    put(p.waterline or 0)
  end
  for i = n + 1, #sigBuf do sigBuf[i] = nil end
  return table.concat(sigBuf, ",")
end

-- The sun pass: render the scene once from the light, so the main pass can
-- ask any fragment whether the sun reached it. Every caster the main pass
-- draws goes in -- the terrain mesh, which is where buildings, trees,
-- ledges, signs and every prop live, plus one UPRIGHT card per character
-- (Voxel3D.casterMatrix; the leaning slab is a trick for the camera, not
-- for the sun) -- so shadows land on walls, roofs, ledges and passing NPCs
-- as readily as on the floor.
--
-- Runs BEFORE Voxel3D.beginScene, because canvases do not nest. Grass is
-- left out on purpose: thousands of tufts would cast a speckle no bigger
-- than the pixels it lands on, at the cost of the mesh being drawn twice.
local function castShadows(state, terrain, nbMesh, posed, cx, cy, vw, vh,
                           atlasFor)
  if not ShadowMap.available() then return end
  local sig = shadowSignature(terrain, nbMesh, posed, cx, cy, vw, vh)
  if not ShadowMap.stale(sig) then return end
  if not ShadowMap.begin(cx, cy, vw, vh) then return end

  -- On the LOW rung the neighbours are drawn in the SCENE as usual and
  -- simply do not cast. They are whole route-sized meshes -- the mesher's
  -- own note puts one at 10 to 20 MB of vertices -- so letting up to four
  -- of them through here multiplies the sun pass's geometry by five for
  -- shadows that fall almost entirely off the side of the view. What is
  -- lost is a strip along the seam where a neighbour's border trees should
  -- be throwing onto this map's edge; what is bought is most of the pass.
  local casters = Quality.neighbourShadows() and (state.neighbors or {}) or {}
  local box = VoxelScene.bounds(cx, cy, vw, vh, true)

  ShadowMap.drawGroup(terrain, atlasFor(state.map), nil, box)
  for i, nb in ipairs(casters) do
    ShadowMap.drawGroup(nbMesh[i], atlasFor(nb.map),
                        Mat4.translate(nb.ox, 0, nb.oy),
                        shifted(box, nb.ox, nb.oy))
  end
  -- flower billboards live outside the terrain mesh (they draw after the
  -- characters, pulled -- see render), but the sun still sees them: a
  -- handful of cutouts per meadow, unlike the grass left out below.
  -- Every thin card from here down is SNUGGED toward the sun along its own
  -- ray (ShadowMap.snug) so its shadow keeps contact with its feet instead
  -- of starting a bias-width away.
  ShadowMap.draw(ChunkMesher.flowers(state.map), atlasFor(state.map),
                 ShadowMap.snug(nil))
  for _, nb in ipairs(casters) do
    ShadowMap.draw(ChunkMesher.flowers(nb.map), atlasFor(nb.map),
                   ShadowMap.snug(Mat4.translate(nb.ox, 0, nb.oy)))
  end
  -- authored figures cast too, for the same reason the flowers do: a
  -- handful of cards per map, and a person with no shadow reads as pasted on
  eachFigure(state.map, 0, 0, function(mesh, _, caster)
    ShadowMap.draw(mesh, atlasFor(state.map), ShadowMap.snug(caster))
  end)
  for _, nb in ipairs(casters) do
    eachFigure(nb.map, nb.ox, nb.oy, function(mesh, _, caster)
      ShadowMap.draw(mesh, atlasFor(nb.map), ShadowMap.snug(caster))
    end)
  end
  for _, p in ipairs(posed) do
    local def = p.sprite.def
    local frame, mirror = frameFor(def, p.facing, p.phase, p.flip)
    local mesh = SpriteBillboards.shadowQuad(def, frame, p.waterline or 0)
    if mesh then
      ShadowMap.draw(mesh, p.sprite:resolveImage(),
                     ShadowMap.snug(
                       Voxel3D.casterMatrix(p.px, p.py, p.gh + (p.lift or 0),
                                            mirror)))
    end
  end
  -- town street lamps cast from their poles (heads are small and would
  -- speck the pavement).  Neighbour-map lamps are skipped: their sites are
  -- in the neighbour's own coordinates and a wrong offset lands the shadow
  -- on the wrong block.
  pcall(StreetLamps.castShadows, state.map)

  ShadowMap.finish(sig)
end

function VoxelScene.render(state, w, h, vw, vh, paletteFor)
  -- With nothing cached at all (the first frame of a fresh toggle),
  -- return nil: the engine keeps the 2D path for the frame and
  -- Voxel.ready holds the camera tween at flat, so the switch waits
  -- invisibly instead of freezing or tilting an empty stage.
  local terrain, nbMesh = VoxelScene.prefetch(state)
  if not terrain then return nil end

  local cam = state.camera
  local cx, cy = cam.x + vw / 2, cam.y + vh / 2

  -- the hour's light, before anything is cast or drawn: point the shared
  -- rig at the clock (or at noon, indoors -- a cave at midnight is exactly
  -- as dark as a cave at noon) and set the tint the scene shader multiplies
  -- every surface by. A CANOPY map (Viridian Forest) is the case between:
  -- the rig stays at noon and no sky is painted, but the hour's tint still
  -- falls through the leaves -- night reaches a forest floor.
  local outdoor = state.map.def and Map.isOutdoor(state.map.def) or false
  -- how much SKY there is to be filled by, which is the other half of the
  -- lighting split (see Light.lua). There is none in a cave, so a gym's
  -- shadows stay grey rather than turning the blue that says "outdoors" --
  -- the same Map.isOutdoor test the sky itself is painted on.
  Voxel3D.skyAmount = outdoor and 1 or 0
  DayNight.applyRig(outdoor)
  Voxel3D.tint = DayNight.tint(outdoor or DayNight.isCanopy(state.map))
  -- and the window glass: the tileset's own panes (found in its art --
  -- GlassMask), lit after dark. Outdoors only, like everything the clock
  -- touches, which also keeps any pane-shaped art in an interior tileset
  -- from picking up a glint.
  local GlassMask = V.require("GlassMask")
  Voxel3D.glassMask = outdoor and GlassMask.texture(state.map.tileset) or nil
  Voxel3D.glassNight = outdoor and DayNight.windowLight() or 0
  Voxel3D.lampColor = DayNight.lampColor()
  -- Send only the nearby active posts to the shader.  This belongs before
  -- beginScene: the ground is the first mesh drawn and must receive the same
  -- warm pools as the post itself.
  -- Map data must never be allowed to abort the whole 3D frame.  A bad or
  -- half-streamed map simply gets no local pools for that frame and retries
  -- on the next one; the post meshes and the rest of the renderer stay live.
  if outdoor then
    local ok, lamps = pcall(StreetLamps.lights, state.map, cx, cy)
    Voxel3D.lampLights = ok and lamps or nil
    -- The flame's height belongs to whichever post is shipping, not to a
    -- number the renderer assumes: the authored bake measures its own lantern
    -- and the box models put theirs somewhere else entirely.
    local okH, y = pcall(StreetLamps.flameHeight)
    Voxel3D.lampHeight = okH and y or nil
    -- The gas clock. Wrapped so a long session cannot walk sin() out into the
    -- range where a float has no fraction left and the flicker freezes.
    Voxel3D.lampFlicker =
      (Voxel3D.lampLights and #Voxel3D.lampLights > 0)
      and ((love.timer and love.timer.getTime and love.timer.getTime() or 0)
           * 2.4) % 6283.185
      or 0
  else
    Voxel3D.lampLights = nil
    Voxel3D.lampFlicker = 0
  end
  local g = VoxelScene.glintStep(glint, cx, cy)
  Voxel3D.glassPhase, Voxel3D.glassGlint = g.phase, g.amp

  local function atlasFor(map)
    return TerrainAtlas.forMap(map, modeColors(paletteFor, map))
  end

  -- sprite palettes only exist in the SGB modes; under RED++ the OBP bake
  -- inside sprite:resolveImage() already colors the sheet
  local function spriteColors(map)
    if PaletteFX.usesGbcPack() then return nil end
    return modeColors(paletteFor, map)
  end

  local posed, me = posesOf(state, spriteColors)
  castShadows(state, terrain, nbMesh, posed, cx, cy, vw, vh, atlasFor)

  if not Voxel3D.beginScene(w, h, cx, cy, vw, vh, skyFor(state.map)) then
    return nil
  end

  -- Terrain, chunked and culled: only the cells of this map -- and only
  -- the connected maps -- that the camera can still see ground on. This is
  -- the pass that made a route heavy and a house free, because the cost was
  -- never the camera, it was how much map was being submitted behind it.
  -- SNOW ON THE WORLD ITSELF, for the length of the terrain pass and no
  -- longer. Every up-facing voxel goes white -- the ground, the top of a
  -- stone wall, the crown of a tree, a roof, a ledge -- which is what snow
  -- does and what no decal ever quite did: a quad laid over a rounded crown
  -- either sinks into it or hovers over it, and the second is the one you
  -- cannot stop seeing. There is nothing to float here. The face the camera
  -- is already looking at is the face that turns white.
  -- THE HORIZON FIRST, before anything real. The far silhouettes
  -- (lib/Skyline.lua) are the most distant thing in the frame by an order
  -- of magnitude, so they go down first and the depth buffer lets every
  -- actual map overwrite them -- which is also why they need no culling
  -- box and no sort. Ahead of the snow tint on purpose: a silhouette is a
  -- shape, not a surface, and whitening its crowns would put a snowfield
  -- on a hill nobody can reach.
  Skyline.frame()
  Skyline.draw(state, cx, cy, vh)

  Voxel3D.snowTop = GroundFX.snowTint(state.map)
  local box = VoxelScene.bounds(cx, cy, vw, vh, false)
  Voxel3D.drawGroup(terrain, atlasFor(state.map), nil, nil, nil, box)
  for i, nb in ipairs(state.neighbors or {}) do
    Voxel3D.drawGroup(nbMesh[i], atlasFor(nb.map),
                      Mat4.translate(nb.ox, 0, nb.oy), nil, nil,
                      shifted(box, nb.ox, nb.oy))
  end
  -- and off again before anything that is not the world is drawn: a
  -- character's card is a sprite facing the camera, and its shade is 1 for
  -- the same reason a voxel's top is -- so leaving this on would put snow on
  -- everybody's face. It goes back on for the WORLD's other passes below --
  -- the authored figures, the grass and the flowers are all things snow
  -- falls on, and the bushes a town is hedged with live in those passes
  -- rather than in the terrain group.
  local snowOnWorld = Voxel3D.snowTop
  Voxel3D.snowTop = 0

  -- What the weather LEFT on that ground: puddles after a shower, drifts
  -- and footprints in the snow. Here rather than in the overlay pass every
  -- other drawing this mod composites goes through, and the difference is
  -- the whole reason it is a decal: a butterfly IS in front of the world,
  -- and a puddle is underneath the person standing in it. Between the
  -- terrain and the characters, depth-tested and never depth-writing --
  -- the same footing the flat drop shadows below use, for the same
  -- reasons. See lib/GroundFX.lua.
  GroundFX.draw3D(state)

  -- Without a shadow map (headless, or a driver that could not make the
  -- canvas) the old flat decals stand in: ground-only, characters only,
  -- but better than a world with nothing under anybody. They go down
  -- first, as decals the characters then stand over -- depth-tested
  -- against the terrain just drawn (a shadow behind a building stays
  -- hidden) but never depth-writing, so the grass pass at the end of the
  -- frame still wins its feet-overdraw fights.
  if not Voxel3D.shadowsActive() then
    Voxel3D.beginShadows()
    for _, p in ipairs(posed) do
      drawShadow(p.sprite, p.px, p.py, p.facing, p.phase, p.flip, p.gh,
                 p.lift, p.waterline)
    end
    Voxel3D.endShadows()
  end

  -- Sprite sheets from here to the figure pass: their texture coordinates
  -- mean nothing to the tileset-shaped glass mask, so the glass is off or
  -- the panes' atlas positions stripe the cast with lamplight at night
  Voxel3D.glass(false)

  -- The player's silhouette goes down BEFORE the characters, so the only
  -- thing it can meet in the depth buffer is the WORLD -- terrain, buildings,
  -- trees. Drawn after the solid pass it would meet the player's own card
  -- instead, and every fragment of a figure sits behind the one that just
  -- wrote it, so the silhouette would paint over the player at all times.
  -- Every character then draws on top as usual, which leaves the silhouette
  -- showing in exactly one situation: where the world hides them.
  if me then
    Voxel3D.beginGhost()
    drawGhost(me)
    Voxel3D.endGhost()
  end

  -- Characters carry no wireframe out here, whatever the V-GRID row says.
  -- The seams are what makes the WORLD read as built out of voxels, and
  -- the people walking around in it are the one thing that should read as
  -- drawn instead -- a grid over a 16x16 sprite lands a line every couple
  -- of display pixels and turns a face into a mesh. (The battle pass makes
  -- the opposite call for its own combatants, deliberately: that is a
  -- staged shot rather than the world being walked around in -- see
  -- BattleBillboard.)
  --
  -- Characters, normally depth-tested: the camera-ward pull inside
  -- drawEntity resolves the lean-over-the-wall-in-front case, and a
  -- character genuinely behind a building is far deeper and loses the
  -- test, so buildings and trees really occlude.
  Voxel3D.seams(false)
  for _, p in ipairs(posed) do
    drawEntity(p.sprite, p.px, p.py, p.facing, p.phase, p.flip, p.gh,
               p.colors, p.lift, p.waterline)
  end
  -- back on for everything textured from the atlas again -- figures, grass
  -- and flowers all sample it, where the mask's coordinates are honest
  Voxel3D.glass(true)
  -- Authored figures, alongside the characters and with the same lean and
  -- the same camera-ward pull -- they ARE characters as far as the artwork
  -- is concerned, just ones the tileset draws instead of a sprite sheet.
  -- Drawn after the walkers so a player standing in front of the couch
  -- wins the overlap, which is the order the flat game draws them in.
  local figPull = billboardPull()
  eachFigure(state.map, 0, 0, function(mesh, model, caster)
    Voxel3D.draw(mesh, atlasFor(state.map), model, figPull,
                 ShadowMap.snug(caster))
  end)
  for _, nb in ipairs(state.neighbors or {}) do
    eachFigure(nb.map, nb.ox, nb.oy, function(mesh, model, caster)
      Voxel3D.draw(mesh, atlasFor(nb.map), model, figPull,
                   ShadowMap.snug(caster))
    end)
  end
  -- and the snow is back on with them: a hedge, a tuft of grass and a flower
  -- bed are all things a snowfall lands on, and the town's bushes are drawn
  -- in these passes rather than in the terrain group -- which is why the
  -- crowns stayed green while the ground and the walls went white.
  Voxel3D.snowTop = snowOnWorld
  -- and the seams are back on for the terrain art that follows: grass and
  -- flowers are the world's own drawing, not people
  Voxel3D.seams(true)
  -- tall grass last, pulled camera-ward exactly as far as the characters
  -- were (same per-vertex shader bias, so grass never drifts either):
  -- relative depth between a walker and the tuft row south of their feet
  -- is preserved, so the row still overdraws feet -- the 3D version of
  -- the GB's grass-over-feet trick -- while grass keeps losing to the
  -- buildings it genuinely stands behind (far deeper than the pull).
  local Voxel = V.require("VoxelState")
  local pull = VoxelScene.pull(math.max(Voxel.angle, 0.05))
  -- and the wind, which only these last two passes take: the grass and the
  -- flowers are the only things out here with a base planted in the ground
  -- and a top free to give. Everything above is either terrain, which does
  -- not lean, or a character, whose card is a trick played on the camera
  -- and would read as the person swaying rather than the meadow.
  local sway = Wind.amount()
  -- 3D grass bake (if present) + foot-crush physics from everyone walking
  -- through the meadow this frame.
  local grassTex = atlasFor(state.map)
  local Grass3D = nil
  local GrassMod = nil
  do
    local ok, G = pcall(V.require, "Grass3D")
    if ok and G then
      -- the module is wanted either way: the springs below are physics on
      -- whatever the grass pass is drawing, and the classic extruded slab
      -- is crushed underfoot exactly like a bake is
      GrassMod = G
      if G.available and G.available() then
        Grass3D = G
        grassTex = G.texture() or grassTex
      end
    end
  end
  -- ------- how tall the thing that is about to lean stands
  --
  -- The bake knows its own height; the classic slab does not, and takes the
  -- default. Handed over rather than assumed, so the bend curve runs over
  -- the geometry actually in front of the shader (see Voxel3D's sway block).
  do
    local h = nil
    if Grass3D and Grass3D.meta then
      local okm, m = pcall(Grass3D.meta)
      if okm and m and tonumber(m.height) and m.height > 0.5 then
        h = m.height
      end
    end
    Voxel3D.grassH = h
    -- and what is lying on the blades this frame: rain, settled snow, gust
    local wet, snow, gust = 0, 0, 0
    local okl, a, b, c = pcall(Wind.load)
    if okl then wet, snow, gust = a or 0, b or 0, c or 0 end
    Voxel3D.grassLoad = { wet, snow, gust }
  end
  do
    -- Everyone standing in the world parts the grass; moving parts it
    -- harder. Handed to Grass3D rather than sent straight down, because
    -- what the shader wants is not where the feet are this frame -- it is
    -- how far each tuft has got in bending down and standing back up, and
    -- that is a thing with a memory (Grass3D.crushFrame).
    -- ------- and the player goes FIRST
    --
    -- There are only so many live foot slots, and `posed` is in draw order
    -- -- ghosts on neighbouring maps, then this map's cast, with the
    -- player wherever they happen to fall in it. Filling the slots in that
    -- order means three wild Pokemon standing near you can take all of
    -- them, and then the one walker whose trail anybody is looking at --
    -- yours -- silently drops out. Measured: a walk down Route 1 laid two
    -- crumbs instead of five, all of them a Rattata's.
    local feet = {}
    local function foot(p)
      if not p or #feet >= 4 then return end
      local lift = p.lift or 0
      local moving = math.abs(lift) > 0.15
      feet[#feet + 1] = {
        (p.px or 0) + 8,
        (p.py or 0) + 8,
        moving and 12 or 10,
        moving and 1.0 or 0.6,
      }
    end
    foot(me)
    for _, p in ipairs(posed) do
      if p ~= me then foot(p) end
    end
    -- Time since the LAST grass pass, not love.timer.getDelta(): the
    -- springs and the trail are integrated in here, and a frame that
    -- renders the scene twice (a staged battle over the overworld) would
    -- otherwise step them twice and run the meadow at double speed. Asked
    -- this way, a second pass in the same frame gets dt = 0 and changes
    -- nothing, which is exactly right -- it is the same instant.
    local now = (love.timer and love.timer.getTime and love.timer.getTime())
                or 0
    local dt = (lastGrassAt and (now - lastGrassAt)) or 0
    lastGrassAt = now
    if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
    local crush = nil
    if GrassMod and GrassMod.crushFrame then
      local okc, c = pcall(GrassMod.crushFrame, feet, dt)
      if okc then crush = c end
    end
    if not crush then
      -- springs unavailable: the old per-frame list, which is still right,
      -- just instant
      crush = { n = #feet, p = feet }
    end
    Voxel3D.crush = crush
  end
  Voxel3D.draw(ChunkMesher.grass(state.map), grassTex, nil, pull,
               nil, sway)
  for _, nb in ipairs(state.neighbors or {}) do
    local ntex = grassTex
    if not Grass3D then ntex = atlasFor(nb.map) end
    Voxel3D.draw(ChunkMesher.grass(nb.map), ntex,
                 Mat4.translate(nb.ox, 0, nb.oy), pull, nil, sway)
  end
  -- The crush stays ON through the flowers. They are the other thing out
  -- here with a base in the ground and a top free to give, they grow in
  -- the same beds people walk through, and a boot that lays the grass flat
  -- and steps over a flower bed untouched is the seam showing.
  -- and the flowers stand on their own height again: they are the tileset's
  -- own slab whatever the grass bake is, so a tall bake must not stretch
  -- their bend curve with it
  Voxel3D.grassH = nil
  -- flower billboards: pulled like the characters and the grass, MINUS
  -- the depth of 8 world pixels along the view (8 sin a -- the camera
  -- looks along (0, -cos a, -sin a), so that is exactly one tile row of
  -- northness). A pure depth handicap with zero screen drift: every
  -- flower is judged as if it stood one tile row further north. The
  -- character card's feet plane sits at its cell's MIDDLE (py + 8), so
  -- a flower on the walker's own cell (z +4 or +12 across the cell)
  -- lands behind the card and the player obscures the patch they stand
  -- ON, while the nearest flower of the cell south (+20) stays in front
  -- and keeps overdrawing their feet.
  local fpull = math.max(0, pull - 8 * math.sin(math.max(Voxel.angle, 0.05)))
  -- flowers are snugged casters too, so they read their own shadowing
  -- through the same snugged transform the sun stored them with
  -- flowers take a share of the wind rather than all of it: they are
  -- shorter and stiffer than a grass tuft, and they are also the one thing
  -- in a meadow the eye settles on
  local fsway = sway * Wind.FLOWER_SHARE
  Voxel3D.draw(ChunkMesher.flowers(state.map), atlasFor(state.map), nil,
               fpull, ShadowMap.snug(nil), fsway)
  for _, nb in ipairs(state.neighbors or {}) do
    Voxel3D.draw(ChunkMesher.flowers(nb.map), atlasFor(nb.map),
                 Mat4.translate(nb.ox, 0, nb.oy), fpull,
                 ShadowMap.snug(Mat4.translate(nb.ox, 0, nb.oy)), fsway)
  end
  Voxel3D.crush = nil
  Voxel3D.grassLoad = nil

  -- Street lamps last among the world props: poles take the hour's light,
  -- heads flatten to lampColor after dusk so a DEEP night still has light
  -- on the street.  Seams off -- these are not voxel-grid props.
  Voxel3D.seams(false)
  pcall(StreetLamps.draw, state.map, outdoor)
  Voxel3D.seams(true)

  return Voxel3D.endScene()
end

return VoxelScene
