-- Voxel world mode: ambient life -- the small things that make a diorama
-- read as a PLACE rather than a model of one.
--
-- Six kinds of creature, none of them game objects:
--
--   butterflies  by day, over the tall grass, wandering a few cells from
--                where they hatched with a sine-bob flutter
--   fireflies    through dusk and the night, over the same grass, drifting
--                slowly and BLINKING -- drawn additive, so each one is a
--                point of light the night actually receives
--   birds        a small flock crossing the sky every half minute or so,
--                high over the roofs, gone off the far edge
--   sparrows     on the GROUND: hopping about the open cells, pecking at
--                nothing -- until the player comes within a couple of
--                cells, when they startle and fly off. The startle is the
--                whole point: ambience that reacts to you is the
--                difference between a diorama and a terrarium
--   dragonflies  darting over the water by day -- a hover, a dash to a new
--                spot, another hover, the way the real thing moves
--   leaves       while the wind blows, torn loose and carried on the same
--                gust the grass is bending under (the drift reads
--                Wind.amount, so a stronger WIND row means more weather)
--
-- And one behaviour for the people: CIVILIAN NPCs GLANCE. Walk within a
-- couple of cells of someone and they turn to look at you, the way anyone
-- would; walk on and a standing NPC turns back to where they were facing.
-- Strictly civilians only -- an NPC with a trainerClass is never touched,
-- because a trainer's facing IS their line of sight and turning one would
-- start (or dodge) fights the map never rolled. Wanderers keep whatever
-- facing their next step picks, exactly as before; scripts freeze NPCs and
-- frozen NPCs are left alone.
--
-- Everything here is PURELY PRESENTATIONAL, more so even than the rest of
-- the mod: nothing stands in a cell, nothing joins ow.entities, nothing can
-- be bumped, talked to or collided with. A critter is a dot with a clock,
-- simulated in world coordinates and drawn through Voxel3D.project into the
-- finished scene -- the same overlay pass the field FX composite through,
-- so the depth story is the sprite one: painted over the world, anchored to
-- it by the camera.
--
-- The population follows the world's own clocks. DayNight decides who is
-- awake -- butterflies sleep at night, fireflies are invisible at noon --
-- Wind decides whether leaves fly, Map.isOutdoor keeps everything out of
-- buildings and caves, and the canopy maps (Viridian Forest) keep their
-- birds: there is no sky to cross under a roof of leaves.
--
-- One OPTIONS row, AMBIENT ON/OFF, because every moving thing is one more
-- reason a slow device drops a frame. Leaves use a small CC0 sprite strip
-- (`assets/vfx/leaves.png`); everything else is still a few tinted
-- rectangles -- OFF is about taste as much as speed.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local DayNight = V.require("DayNight")
local Wind = V.require("Wind")

local Map = require("src.world.Map")

local AmbientLife = {}

AmbientLife.setting = ModSetting.new("ambient", "AMBIENT",
                                     { "on", "off" }, { "ON", "OFF" })

function AmbientLife.enabled()
  return AmbientLife.setting:get() == "on"
end

function AmbientLife.row()
  return AmbientLife.setting:row()
end

local function game()
  return require("src.core.Game")
end

-- ------- the population
--
-- World-pixel coordinates (a cell is 16), height in the same units the
-- geometry stands in, because every one of these is projected through the
-- camera exactly like a piece of terrain.
local critters = {}
local state = { mapId = nil, birdTimer = 12, spawnTick = 0 }

-- Caps, and they are deliberately small: ambience is a thing you notice
-- out of the corner of your eye, and twenty butterflies over one patch is
-- not a meadow, it is a lure.
local MAX_BUTTERFLY = 6
local MAX_LEAF = 160              -- hard ceiling; live cap scales with wind
local MAX_SPARROW = 3
local MAX_DRAGONFLY = 3
local SPAWN_EVERY = 0.5           -- seconds between spawn attempts
-- Leaves only fly once the air is moving; floor matches WindFX spirit.
local LEAF_WIND_FLOOR = 0.38

-- How many leaves may be aloft for this Wind.amount. Weak breeze = a few
-- tumblers; a real gale should look like the trees emptied. Soft-power
-- (1.25) so the middle of AUTO is not already a blizzard, but GALE
-- actually fills the frame.
local function leafQualityMax()
  local s = 1
  local ok, Q = pcall(V.require, "Quality")
  if ok and Q and Q.scale then
    local oks, n = pcall(Q.scale)
    if oks and tonumber(n) then s = n end
  end
  if s >= 4 then return 24 end
  if s == 3 then return 56 end
  if s == 2 then return 110 end
  return MAX_LEAF
end

local function leafCap(windAmt, canopy)
  windAmt = tonumber(windAmt) or 0
  if windAmt < LEAF_WIND_FLOOR then return 0 end
  local t = (windAmt - LEAF_WIND_FLOOR) / 3.2
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  local ceil = leafQualityMax()
  if canopy then ceil = math.min(MAX_LEAF, math.floor(ceil * 1.45)) end
  local n = math.floor(5 + (t ^ 1.25) * (ceil - 5))
  if n > ceil then n = ceil end
  return n
end
local CELL_TRIES = 12             -- cells sampled per attempt
local RADIUS = 11                 -- cells around the player a spawn may land
local STARTLE = 40                -- world px at which a sparrow flees

-- Fireflies come out with the DARK rather than with the clock. A flat cap
-- meant the same dozen at a lit dusk and at midnight, which is the one
-- thing that gave them away as a spawner: the drift over a field should
-- THICKEN as the light goes. DayNight.starAmount is the curve for it and is
-- already the right one -- it is how deep the night is with the weather
-- taken out, so a downpour thins them out for the same reason it puts the
-- stars away, and neither needs to ask the weather anything.
local FIREFLY_DEEP = 18           -- at the darkest part of a clear night
local FIREFLY_DIM = 3             -- and what a dusk with light still in it gets

local function fireflyCap()
  local amt = DayNight.starAmount and DayNight.starAmount() or 1
  return math.floor(FIREFLY_DIM + (FIREFLY_DEEP - FIREFLY_DIM) * amt + 0.5)
end

local rand = love.math.random

local function count(kind)
  local n = 0
  for _, c in ipairs(critters) do
    if c.kind == kind then n = n + 1 end
  end
  return n
end

-- A grass cell near the player, or nil. Grass is where the living things
-- are -- it is also, not coincidentally, the one terrain the encounter
-- system says is inhabited.
local function grassCellNear(ow)
  local map, p = ow.map, ow.player
  for _ = 1, CELL_TRIES do
    local cx = p.cellX + rand(-RADIUS, RADIUS)
    local cy = p.cellY + rand(-RADIUS, RADIUS)
    if map:inBounds(cx, cy) and map:isGrassCell(cx, cy) then
      return cx * 16 + rand(2, 14), cy * 16 + rand(2, 14)
    end
  end
  return nil
end

local function spawnButterfly(ow)
  local x, z = grassCellNear(ow)
  if not x then return end
  critters[#critters + 1] = {
    kind = "butterfly", x = x, z = z, hx = x, hz = z,
    y = 6 + rand() * 6, dir = rand() * 6.2831,
    seed = rand() * 6.2831, t = 0, ttl = 18 + rand() * 20,
    tint = rand(3),
  }
end

local function spawnFirefly(ow)
  local x, z = grassCellNear(ow)
  if not x then return end
  critters[#critters + 1] = {
    kind = "firefly", x = x, z = z, hx = x, hz = z,
    y = 3 + rand() * 5, dir = rand() * 6.2831,
    seed = rand() * 6.2831, t = 0, ttl = 14 + rand() * 16,
  }
end

-- An open walkable cell near the player -- where a ground bird can stand.
local function openCellNear(ow)
  local map, p = ow.map, ow.player
  for _ = 1, CELL_TRIES do
    local cx = p.cellX + rand(-RADIUS, RADIUS)
    local cy = p.cellY + rand(-RADIUS, RADIUS)
    if map:inBounds(cx, cy) and map:isWalkableCell(cx, cy)
       and not map:warpAtCell(cx, cy) then
      return cx * 16 + rand(3, 13), cy * 16 + rand(3, 13)
    end
  end
  return nil
end

local function waterCellNear(ow)
  local map, p = ow.map, ow.player
  for _ = 1, CELL_TRIES do
    local cx = p.cellX + rand(-RADIUS, RADIUS)
    local cy = p.cellY + rand(-RADIUS, RADIUS)
    if map:inBounds(cx, cy) and map:isWaterCell(cx, cy) then
      return cx * 16 + rand(2, 14), cy * 16 + rand(2, 14)
    end
  end
  return nil
end

local function spawnSparrow(ow)
  local x, z = openCellNear(ow)
  if not x then return end
  critters[#critters + 1] = {
    kind = "sparrow", x = x, z = z, y = 0,
    mode = "ground", hopWait = 0.5 + rand() * 1.2,
    seed = rand() * 6.2831, t = 0, ttl = 20 + rand() * 20,
  }
end

local function spawnDragonfly(ow)
  local x, z = waterCellNear(ow)
  if not x then return end
  critters[#critters + 1] = {
    kind = "dragonfly", x = x, z = z, hx = x, hz = z,
    tx = x, tz = z, y = 3,
    seed = rand() * 6.2831, t = 0, ttl = 16 + rand() * 16,
  }
end

-- Flight styles. The sheet only has a handful of silhouettes; the variety
-- is how they MOVE and what colour they wear. A maple and a willow chip
-- should not share a sine.
local LEAF_STYLES = { "flutter", "maple", "sail", "tumble",
                      "skip", "spiral", "heavy", "chip" }

-- Multipliers on the authored strip. Season picks the bag; the bag still
-- has leftovers so a March street is not one green.
local LEAF_TINTS = {
  { 1.00, 1.00, 1.00 },
  { 0.82, 1.12, 0.55 },   -- spring lime
  { 0.55, 0.78, 0.32 },   -- deep green
  { 0.72, 0.88, 0.40 },   -- summer
  { 1.15, 1.05, 0.42 },   -- gold
  { 1.18, 0.78, 0.28 },   -- yellow
  { 1.15, 0.48, 0.28 },   -- rust
  { 0.95, 0.32, 0.24 },   -- red
  { 0.68, 0.42, 0.24 },   -- dead brown
  { 0.52, 0.46, 0.34 },   -- grey-brown
  { 0.78, 0.82, 0.88 },   -- frost
  { 0.90, 0.62, 0.38 },   -- tan
}

local function leafTintBag()
  local month = 0
  local ok, m = pcall(DayNight.month)
  if ok then month = tonumber(m) or 0 end
  -- Kanto-as-Japan: autumn is Sep-Nov. HEMISPHERE is south for weather
  -- snow, but trees still follow a temperate palette -- mix, don't lock.
  if month >= 9 and month <= 11 then
    return { 5, 6, 7, 8, 9, 12, 1 }
  elseif month == 12 or month == 1 or month == 2 then
    return { 9, 10, 11, 8, 12 }
  elseif month >= 3 and month <= 5 then
    return { 2, 3, 4, 1, 5 }
  end
  return { 1, 3, 4, 2, 12, 5 }
end

local function pickLeafStyle()
  local r = rand()
  if r < 0.18 then return "flutter" end
  if r < 0.32 then return "maple" end
  if r < 0.46 then return "sail" end
  if r < 0.62 then return "tumble" end
  if r < 0.72 then return "skip" end
  if r < 0.82 then return "spiral" end
  if r < 0.92 then return "heavy" end
  return "chip"
end

local function spawnLeaf(ow)
  local p = ow.player
  -- Spawn UPWIND so the leaf crosses the camera (same idea as WindFX).
  local dx = (Wind.DIR and Wind.DIR[1]) or 1
  local dz = (Wind.DIR and Wind.DIR[2]) or 0
  local back = (2 + rand() * 6) * 16
  local side = (rand() * 2 - 1) * RADIUS * (8 + rand() * 6)
  local x = p.cellX * 16 + 8 - dx * back - dz * side
  local z = p.cellY * 16 + 8 - dz * back + dx * side
  local style = pickLeafStyle()
  local bag = leafTintBag()
  local tint = LEAF_TINTS[bag[rand(1, #bag)]] or LEAF_TINTS[1]
  local y0, fall, spin, size, ttl, carry
  if style == "maple" then
    y0, fall, spin, size, ttl, carry = 14 + rand() * 18, 2.2 + rand() * 2.0,
      (rand() * 2 - 1) * (7 + rand() * 5), 0.70 + rand() * 0.70,
      10 + rand() * 8, 0.85
  elseif style == "sail" then
    y0, fall, spin, size, ttl, carry = 12 + rand() * 14, 1.6 + rand() * 1.8,
      (rand() * 2 - 1) * (0.6 + rand() * 1.2), 0.85 + rand() * 0.80,
      12 + rand() * 10, 1.15
  elseif style == "tumble" then
    y0, fall, spin, size, ttl, carry = 8 + rand() * 20, 5.5 + rand() * 4.5,
      (rand() * 2 - 1) * (4 + rand() * 6), 0.50 + rand() * 0.90,
      7 + rand() * 8, 0.95
  elseif style == "skip" then
    y0, fall, spin, size, ttl, carry = 3 + rand() * 8, 3.0 + rand() * 2.5,
      (rand() * 2 - 1) * (2 + rand() * 3), 0.45 + rand() * 0.55,
      6 + rand() * 7, 1.05
  elseif style == "spiral" then
    y0, fall, spin, size, ttl, carry = 16 + rand() * 16, 3.2 + rand() * 2.4,
      (rand() * 2 - 1) * (5 + rand() * 4), 0.55 + rand() * 0.65,
      9 + rand() * 8, 0.80
  elseif style == "heavy" then
    y0, fall, spin, size, ttl, carry = 10 + rand() * 12, 8.0 + rand() * 4.0,
      (rand() * 2 - 1) * (1.2 + rand() * 1.6), 0.90 + rand() * 0.85,
      6 + rand() * 6, 0.70
  elseif style == "chip" then
    y0, fall, spin, size, ttl, carry = 6 + rand() * 18, 6.0 + rand() * 5.0,
      (rand() * 2 - 1) * (8 + rand() * 7), 0.28 + rand() * 0.35,
      5 + rand() * 6, 1.20
  else -- flutter
    y0, fall, spin, size, ttl, carry = 8 + rand() * 16, 3.8 + rand() * 3.2,
      (rand() * 2 - 1) * (2.0 + rand() * 2.8), 0.50 + rand() * 0.65,
      8 + rand() * 10, 1.00
  end
  critters[#critters + 1] = {
    kind = "leaf", x = x, z = z, y = y0,
    seed = rand() * 6.2831, t = 0, ttl = ttl,
    frame = rand(0, 15),
    spin = spin, size = size, fall = fall,
    style = style, tint = tint, carry = carry,
    flip = rand() < 0.5 and -1 or 1,
    wobble = 0.7 + rand() * 1.6,
  }
end

-- ------- leaf sprite strip
--
-- 10× 16×16 flying-leaf silhouettes in assets/vfx/leaves.png (cel, coloured;
-- tools/make_wind_sprites.py). Not plant growth stages.
local leafImg, leafQuads = nil, nil

local function leafArt()
  if leafImg == false then return nil end
  if leafImg then return leafImg, leafQuads end
  local path = V.path .. "/assets/vfx/leaves.png"
  local ok, img = pcall(love.graphics.newImage, path)
  if not (ok and img) then
    leafImg = false
    return nil
  end
  pcall(img.setFilter, img, "nearest", "nearest")
  local fw, fh = 16, 16
  local n = math.max(1, math.floor(img:getWidth() / fw))
  local quads = {}
  for i = 0, n - 1 do
    quads[i] = love.graphics.newQuad(i * fw, 0, fw, fh, img:getDimensions())
  end
  leafImg, leafQuads = img, quads
  return leafImg, leafQuads
end

-- ------- what is actually up there
--
-- The flock used to be three rectangles apiece -- a chevron of two wing
-- strokes about a body block, in a flat slate grey. It read as "bird" and
-- that was the whole problem: there are no birds in Kanto. Every other
-- living thing this mod put on the map is a Pokemon drawn in its own art,
-- and the one thing crossing the sky was a generic silhouette.
--
-- So the flock wears a species now, and RoamerArt is already the answer to
-- "what does this species look like on the map" -- the same 16x96 walker it
-- bakes for a wild roamer, or the shipped Gen-2 sheet when the optional pack
-- is installed. Nothing new is downloaded and nothing new is drawn: the art
-- for this has been in the game the whole time.
--
-- WHICH species is the map's own answer, not a list kept here. The encounter
-- table is what the WILD row already reads to decide who is standing in the
-- grass, and a route whose table is full of Spearow gets Spearow overhead
-- for the same reason it gets them underfoot. A cave's table is Zubat and
-- that is exactly right without a special case.
--
-- The set below is only the FILTER -- which Gen 1 species belong in the sky
-- at all. Doduo and Dodrio are birds that famously cannot fly; Gyarados and
-- Dragonite can, but a Dragonite crossing Route 1 is not ambience, it is an
-- event. Held to the ordinary sky traffic on purpose.
local FLYERS = {
  PIDGEY = true, PIDGEOTTO = true, PIDGEOT = true,
  SPEAROW = true, FEAROW = true,
  ZUBAT = true, GOLBAT = true,
  BUTTERFREE = true, BEEDRILL = true, VENOMOTH = true,
  SCYTHER = true,
}

-- ------- how big it reads
--
-- The flock drew every species at one multiplier, so a Pidgey and a Fearow
-- crossing the same sky were the same bird under two names -- and all of
-- them read as specks. Two separate things were wrong and only one of them
-- is a constant.
--
-- The constant: 3.0 was too small. Altitude is 34-48 world pixels and the
-- perspective scale has already taken most of the size away before this
-- multiplier lands, so a flock meant to be noticed arrived as grit on the
-- lens. Altitude itself stays where it is -- lowering it is the other way
-- to make a bird bigger and it flies them through the tree canopy.
local FLOCK_SCALE = 4.5

-- The other: `frontSize` is the battle pic's own buffer in tiles, and it is
-- the only statement Gen 1 ever makes about how big a Pokemon is. RoamerArt
-- already sizes a ground roamer off it (see cellSize), so reading the same
-- field here keeps a species the same creature whether it is standing in
-- the grass or passing overhead.
--
-- Wider spread than cellSize uses, on purpose: that one is defending
-- readability inside a 16-pixel cell and has to floor at 12. The sky has no
-- such floor, so the hierarchy can actually be seen.
local function sizeFromFront(n)
  local k = 0.80 + (n - 4) * 0.15
  if k < 0.70 then k = 0.70 end
  if k > 1.30 then k = 1.30 end
  return k
end

-- Overrides, by species. Empty on purpose. The derived number is right
-- until something is seen to be wrong, and a table filled in advance is a
-- table of guesses wearing the authority of data. A line goes in here when
-- a screenshot says so, not before.
local FLYER_SCALE = {}

-- Resolved once per species, never per frame: this is read from the draw
-- path's spawn side for the same reason flyerArt is (see spawnFlock).
local flyerScaleMemo = {}

local function flyerScale(species)
  if not species then return FLOCK_SCALE end
  local hit = flyerScaleMemo[species]
  if hit then return hit end
  local k = FLYER_SCALE[species]
  if not k then
    local Game = game()
    local mon = Game and Game.data and Game.data.pokemon
                and Game.data.pokemon[species]
    k = sizeFromFront(tonumber(mon and mon.frontSize) or 7)
  end
  local sc = FLOCK_SCALE * k
  flyerScaleMemo[species] = sc
  return sc
end

-- A flying species off this map's own encounter table.
--
-- This used to return nil where the map's table held nothing airborne, and
-- keep the grey chevron rather than name a species the route does not have.
-- That honesty cost more than it bought. The chevron is three rectangles --
-- it is the exact thing the species work was done to get rid of -- and on
-- any table without a flyer it is what the player actually sees. Nobody
-- audits a silhouette at forty pixels of altitude against Viridian's slot
-- list; everybody can see that one map has birds in it and the next one has
-- shapes.
--
-- So the map's own table still wins wherever it has an answer, and PIDGEY
-- stands in where it does not: Kanto's sparrow, on nearly every early
-- route, and the least surprising thing that can cross a sky here. The
-- chevron stays as the last resort for a species whose art cannot be baked
-- at all, which is the case it was always better at covering.
local FALLBACK_FLYER = "PIDGEY"

local function flockSpecies(ow)
  local Game = game()
  local map = ow.map
  local enc = Game.data and Game.data.encounters and map and map.id
              and Game.data.encounters[map.id]
  local tbl = enc and enc.grass
  if not (tbl and tbl.slots) then return FALLBACK_FLYER end
  local pool = {}
  for _, slot in ipairs(tbl.slots) do
    if slot.species and FLYERS[slot.species] then
      pool[#pool + 1] = slot.species
    end
  end
  if #pool == 0 then return FALLBACK_FLYER end
  return pool[rand(1, #pool)]
end

-- species -> Image, or false once it is known there is none. The sheet is
-- whatever RoamerArt hands out, so an installed Gen-2 pack shows up here
-- too without this file knowing the pack exists.
local flyerImg, flyerQuads = {}, {}

local function flyerArt(species)
  if not species then return nil end
  local hit = flyerImg[species]
  if hit ~= nil then return hit or nil, flyerQuads[species] end
  local RoamerArt = V.require("RoamerArt")
  -- mayBake = true, and this runs from the SPAWN path rather than the draw
  -- path on purpose: a first bake writes a PNG, and a frame that stalls for
  -- it is a frame the player sees stutter under a passing flock.
  local ok, def = pcall(RoamerArt.def, species, true)
  if not (ok and def and def.image) then flyerImg[species] = false return nil end
  local oki, img = pcall(love.graphics.newImage, def.image)
  if not (oki and img) then flyerImg[species] = false return nil end
  img:setFilter("nearest", "nearest")
  local F = RoamerArt.FRAME
  local q = {}
  for i = 0, RoamerArt.FRAMES - 1 do
    q[i] = love.graphics.newQuad(0, i * F, F, F, img:getDimensions())
  end
  flyerImg[species], flyerQuads[species] = img, q
  return img, q
end

-- A flock: three to five of one species abreast with a little scatter,
-- entering off one side of the view and crossing the sky to the other.
-- One species for the whole flock, because that is what a flock is.
local function spawnFlock(ow)
  local p = ow.player
  local fromWest = rand() < 0.5
  local px, pz = p.cellX * 16, p.cellY * 16
  local n = rand(3, 5)
  local baseZ = pz + rand(-8, 8) * 16
  local species = flockSpecies(ow)
  if species then flyerArt(species) end        -- bake now, never mid-draw
  local scale = flyerScale(species)            -- and size it now, not per frame
  for i = 1, n do
    critters[#critters + 1] = {
      kind = "bird",
      species = species,
      scale = scale,
      x = px + (fromWest and -1 or 1) * (RADIUS + 3) * 16 - (i - 1) * 10,
      z = baseZ + (i - 1) * 7 - n * 3,
      y = 34 + rand() * 14,
      vx = (fromWest and 1 or -1) * (30 + rand() * 10),
      seed = rand() * 6.2831, t = 0, ttl = 30,
      px0 = px,
    }
  end
end

-- ------- the people glance
--
-- Civilians only, and the guard is the point: `def.trainerClass` is how
-- the sight check knows a trainer, and a trainer's facing IS their line of
-- sight -- turning one toward a passing player would start (or dodge)
-- fights the map never rolled. Everything else stands down: frozen NPCs
-- belong to a script, moving ones pick their own facing on the next step,
-- and this mod's own roamers and street Pokemon have moods of their own.
--
-- A standing NPC remembers the facing its map def gave it and turns BACK
-- when the player walks on -- a shopkeeper glances up from the counter,
-- then goes back to minding it.
local NPC = require("src.world.NPC")

local function glance(ow)
  local p = ow.player
  for _, npc in ipairs(ow.npcs or {}) do
    if getmetatable(npc) == NPC and npc.def and not npc.def.trainerClass
       and not npc.frozen and not npc.moving then
      local dx = math.abs(npc.cellX - p.cellX)
      local dy = math.abs(npc.cellY - p.cellY)
      local near = dx <= 2 and dy <= 2 and (dx + dy) > 0 and (dx + dy) <= 3
      if near then
        if npc.dsGlanceFacing == nil then
          npc.dsGlanceFacing = npc.facing or false
        end
        npc:facePlayer(p)
      elseif npc.dsGlanceFacing ~= nil and (dx > 3 or dy > 3) then
        -- only a STANDING NPC turns back; a wanderer's next step owns its
        -- facing already
        if not npc.wanders and npc.dsGlanceFacing then
          npc.facing = npc.dsGlanceFacing
        end
        npc.dsGlanceFacing = nil
      end
    end
  end
end

-- ------- per-frame
--
-- Rides the voxel pipeline's update hook like everything else with a clock,
-- and then gates itself down to the frames where there is a diorama to be
-- alive on: the overworld on top, outdoors, and the voxel camera actually
-- pitched over -- ambience under a menu or on the flat 2D world would be
-- simulation nobody sees. The glance is the one part that runs on the FLAT
-- world too: a turned head is a facing, and facings draw in every mode.
function AmbientLife.update(dt, voxelOn)
  local Game = game()
  local ow = Game and Game.overworld

  if AmbientLife.enabled() and ow and ow.map and ow.player
     and Game.stack and Game.stack:top() == ow
     and not ow.transitioning
     and not (ow.runner and ow.runner.isRunning and ow.runner:isRunning()) then
    pcall(glance, ow)
  end

  local ok = voxelOn and AmbientLife.enabled()
             and ow and ow.map and ow.player
             and Game.stack and Game.stack:top() == ow
             and not ow.transitioning
             and Map.isOutdoor(ow.map.def)
  if not ok then
    if #critters > 0 and not (ow and Game.stack
                              and Game.stack:top() ~= ow) then
      -- gone for a real reason (indoors, mode off): drop the population.
      -- Under a battle or menu it is merely paused, and comes back intact.
      critters = {}
    end
    return
  end

  if state.mapId ~= ow.map.id then
    critters = {}
    state.mapId = ow.map.id
    state.birdTimer = 6 + rand() * 10
  end

  local tod = DayNight.tod()
  local day = tod == "DAY" or tod == "MORNING"
  local glowTime = tod == "NIGHT" or tod == "EVENING"
  local canopy = DayNight.isCanopy(ow.map)
  local windAmtNow = 0
  if Wind.enabled() then
    local okw, wa = pcall(Wind.amount)
    if okw then windAmtNow = tonumber(wa) or 0 end
  end
  local windy = windAmtNow > LEAF_WIND_FLOOR
  local leavesWant = leafCap(windAmtNow, canopy)

  -- one spawn attempt per half second for critters; leaves refill harder
  -- under a gale so the stream stays full as old ones land.
  state.spawnTick = state.spawnTick + dt
  if state.spawnTick >= SPAWN_EVERY then
    state.spawnTick = 0
    if day and count("butterfly") < MAX_BUTTERFLY then spawnButterfly(ow) end
    if glowTime and count("firefly") < fireflyCap() then spawnFirefly(ow) end
    if day and count("sparrow") < MAX_SPARROW then spawnSparrow(ow) end
    if day and count("dragonfly") < MAX_DRAGONFLY then spawnDragonfly(ow) end
  end
  -- Leaves: refill hard under a gale; cull when the wind dies so a calm
  -- field is not still full of tumblers from the last squall.
  do
    local have = count("leaf")
    if leavesWant <= 0 then
      if have > 0 then
        for i = #critters, 1, -1 do
          if critters[i].kind == "leaf" then table.remove(critters, i) end
        end
      end
    else
      if have > leavesWant then
        local drop = have - leavesWant
        for i = #critters, 1, -1 do
          if drop <= 0 then break end
          if critters[i].kind == "leaf" then
            table.remove(critters, i)
            drop = drop - 1
          end
        end
      elseif have < leavesWant then
        local t = math.min(1, (windAmtNow - LEAF_WIND_FLOOR) / 3.2)
        -- gale dumps a handful a tick so the stream fills in a couple of
        -- seconds, not half a minute of two-at-a-time
        local batch = 2 + math.floor(t * 16)
        for _ = 1, math.min(batch, leavesWant - have) do spawnLeaf(ow) end
      end
    end
  end

  -- the flock, on its own long clock, and only under an open sky
  if day and not canopy then
    state.birdTimer = state.birdTimer - dt
    if state.birdTimer <= 0 then
      spawnFlock(ow)
      state.birdTimer = 18 + rand() * 18
    end
  end

  local p = ow.player
  local px, pz = p.cellX * 16, p.cellY * 16
  local far = (RADIUS + 6) * 16
  local windAmt = windy and windAmtNow or 0

  for i = #critters, 1, -1 do
    local c = critters[i]
    c.t = c.t + dt
    local dead = c.t >= c.ttl

    if c.kind == "butterfly" then
      -- a random walk on the heading, a spring back toward home, a bob
      c.dir = c.dir + (rand() - 0.5) * 3.2 * dt
      local sp = 9
      c.x = c.x + math.cos(c.dir) * sp * dt + (c.hx - c.x) * 0.15 * dt
      c.z = c.z + math.sin(c.dir) * sp * dt + (c.hz - c.z) * 0.15 * dt
      c.y = 6 + 3 * math.sin(c.t * 2.6 + c.seed)
      if not day then dead = true end
    elseif c.kind == "firefly" then
      c.dir = c.dir + (rand() - 0.5) * 1.6 * dt
      local sp = 4
      c.x = c.x + math.cos(c.dir) * sp * dt + (c.hx - c.x) * 0.1 * dt
      c.z = c.z + math.sin(c.dir) * sp * dt + (c.hz - c.z) * 0.1 * dt
      c.y = 4 + 2 * math.sin(c.t * 1.3 + c.seed)
      if not glowTime then dead = true end
    elseif c.kind == "leaf" then
      -- Each style has its own air: maple spins and hangs, sail rides,
      -- tumble chaos, skip bounces, spiral corkscrews, heavy drops,
      -- chip is grit with a colour.
      local wdx = (Wind.DIR and Wind.DIR[1]) or 1
      local wdz = (Wind.DIR and Wind.DIR[2]) or 0
      local style = c.style or "flutter"
      local k = c.carry or 1
      local carry = (12 + 20 * windAmt) * k
      local wob = c.wobble or 1
      local flutter, lift, side
      if style == "maple" then
        flutter = math.sin(c.t * 5.4 + c.seed) * (10 + 6 * windAmt) * wob
        lift = math.cos(c.t * 2.6 + c.seed) * 7
        side = math.cos(c.t * 4.1 + c.seed * 0.7) * 5
      elseif style == "sail" then
        flutter = math.sin(c.t * 1.4 + c.seed) * (4 + 3 * windAmt)
        lift = math.sin(c.t * 0.9 + c.seed) * 3
        side = math.cos(c.t * 1.1 + c.seed) * 2
      elseif style == "tumble" then
        flutter = math.sin(c.t * 7.2 + c.seed) * (12 + 8 * windAmt) * wob
        lift = math.sin(c.t * 5.5 + c.seed * 2) * 11
        side = math.cos(c.t * 6.0 + c.seed) * 8
      elseif style == "skip" then
        flutter = math.sin(c.t * 4.0 + c.seed) * (7 + 4 * windAmt)
        lift = math.abs(math.sin(c.t * 3.3 + c.seed)) * 9 - 2
        side = math.sin(c.t * 2.2 + c.seed) * 4
      elseif style == "spiral" then
        local ang = c.t * 3.4 + c.seed
        flutter = math.cos(ang) * (9 + 5 * windAmt)
        lift = math.sin(c.t * 2.0) * 4
        side = math.sin(ang) * (9 + 5 * windAmt)
      elseif style == "heavy" then
        flutter = math.sin(c.t * 1.8 + c.seed) * (3 + 2 * windAmt)
        lift = math.sin(c.t * 1.2 + c.seed) * 1.5
        side = math.cos(c.t * 1.5 + c.seed) * 2
      elseif style == "chip" then
        flutter = math.sin(c.t * 9.0 + c.seed) * (8 + 7 * windAmt)
        lift = math.sin(c.t * 7.5 + c.seed) * 6
        side = math.cos(c.t * 8.2 + c.seed) * 6
      else
        flutter = math.sin(c.t * 3.2 + c.seed) * (6 + 4 * windAmt) * wob
        lift = math.cos(c.t * 2.1 + c.seed * 1.3) * (4 + 3 * windAmt)
        side = math.sin(c.t * 2.4 + c.seed) * 3
      end
      c.x = c.x + (wdx * carry - wdz * flutter + wdx * side * 0.15) * dt
      c.z = c.z + (wdz * carry + wdx * flutter + wdz * side * 0.15) * dt
      c.y = c.y - (c.fall or 6) * dt + lift * dt * 0.45
      if style == "skip" and c.y < 1.2 then
        c.y = 1.2
        c.fall = -(5 + rand() * 4)
      elseif c.fall and c.fall < 0 then
        c.fall = c.fall + 18 * dt
      end
      if c.y < 0.4 then dead = true end
      if c.y > 36 then c.y = 36 end
      if not windy then dead = true end
    elseif c.kind == "bird" then
      c.x = c.x + c.vx * dt
      c.y = c.y + math.sin(c.t * 3 + c.seed) * 2 * dt
      if math.abs(c.x - px) > (RADIUS + 5) * 16 and c.t > 2 then dead = true end
    elseif c.kind == "sparrow" then
      local pxc = p.cellX * 16 + 8
      local pzc = p.cellY * 16 + 8
      local ddx, ddz = c.x - pxc, c.z - pzc
      if c.mode == "ground" then
        -- startle: the player got close, and the bird is gone -- up, away,
        -- and off the roster once it is high and far
        if math.abs(ddx) < STARTLE and math.abs(ddz) < STARTLE then
          c.mode = "fly"
          local len = math.max(1, math.sqrt(ddx * ddx + ddz * ddz))
          c.vx, c.vz = ddx / len * 55, ddz / len * 55
          c.vy = 34
          c.ttl = c.t + 2.5
        elseif c.hop then
          -- mid-hop: a short arc, a few pixels along the ground
          c.hop.t = c.hop.t + dt
          local k = math.min(1, c.hop.t / c.hop.dur)
          c.x = c.x + c.hop.dx * dt / c.hop.dur
          c.z = c.z + c.hop.dz * dt / c.hop.dur
          c.y = math.sin(k * 3.1416) * 2
          if k >= 1 then
            c.hop, c.y = nil, 0
            c.hopWait = 0.5 + rand() * 1.4
          end
        else
          c.hopWait = c.hopWait - dt
          if c.hopWait <= 0 then
            local a = rand() * 6.2831
            c.hop = { t = 0, dur = 0.22,
                      dx = math.cos(a) * 6, dz = math.sin(a) * 6 }
          end
        end
      else
        c.x = c.x + c.vx * dt
        c.z = c.z + c.vz * dt
        c.y = c.y + c.vy * dt
        c.vy = math.max(10, c.vy - 8 * dt)
      end
    elseif c.kind == "dragonfly" then
      -- hover, then a dash to a new spot near home, then hover again
      local dxT, dzT = c.tx - c.x, c.tz - c.z
      local d2 = dxT * dxT + dzT * dzT
      if d2 < 4 then
        if rand() < dt * 0.8 then
          local a = rand() * 6.2831
          local r = 8 + rand() * 20
          c.tx = c.hx + math.cos(a) * r
          c.tz = c.hz + math.sin(a) * r
        end
      else
        local len = math.sqrt(d2)
        local sp = 46
        c.x = c.x + dxT / len * math.min(sp * dt, len)
        c.z = c.z + dzT / len * math.min(sp * dt, len)
      end
      c.y = 3 + math.sin(c.t * 5 + c.seed) * 0.8
      if not day then dead = true end
    end

    if not dead and c.kind ~= "bird"
       and (math.abs(c.x - px) > far or math.abs(c.z - pz) > far) then
      dead = true      -- left behind as the player walked on
    end
    if dead then table.remove(critters, i) end
  end
end

-- ------- the draw
--
-- Inside the voxel overlay pass (main.lua's drawWorld), with the same
-- project function the field FX anchor through. `scale` is pixels per world
-- pixel at the camera's focus; project's third return is the perspective
-- correction for this critter's own distance, so a bird far away is
-- smaller, exactly like the terrain under it.
local BUTTERFLY_TINTS = {
  { 0.96, 0.93, 0.86 },     -- cabbage white
  { 0.95, 0.82, 0.35 },     -- brimstone yellow
  { 0.65, 0.78, 0.95 },     -- pale blue
}

function AmbientLife.draw(project, scale)
  if #critters == 0 then return end
  local g = love.graphics
  local prevBlend, prevAlpha = g.getBlendMode()

  for _, c in ipairs(critters) do
    local sx, sy, ps = project(c.x, c.y, c.z)
    if sx then
      local s = math.max(1, scale * (ps or 1))
      -- ease in over the first half second and out over the last, so
      -- nothing pops into a frame it was not in
      local fade = math.min(1, c.t * 2, (c.ttl - c.t) * 2)

      if c.kind == "butterfly" then
        local tint = BUTTERFLY_TINTS[c.tint] or BUTTERFLY_TINTS[1]
        local flap = math.abs(math.sin(c.t * 16 + c.seed))
        g.setBlendMode("alpha")
        g.setColor(tint[1], tint[2], tint[3], 0.9 * fade)
        -- two wings about a 1px body, folding with the flap
        local w = s * (0.5 + flap)
        g.rectangle("fill", sx - w, sy - s * 0.5, w, s)
        g.rectangle("fill", sx, sy - s * 0.5, w, s)
      elseif c.kind == "firefly" then
        -- the blink: mostly off, a soft ramp on and off again
        local blink = math.sin(c.t * 2.2 + c.seed)
        blink = math.max(0, blink - 0.35) / 0.65
        if blink > 0.01 then
          g.setBlendMode("add")
          g.setColor(0.95, 0.85, 0.35, 0.22 * blink * fade)
          g.rectangle("fill", sx - s * 1.5, sy - s * 1.5, s * 3, s * 3)
          g.setColor(1.0, 0.95, 0.55, 0.9 * blink * fade)
          g.rectangle("fill", sx - s * 0.5, sy - s * 0.5, s, s)
        end
      elseif c.kind == "leaf" then
        g.setBlendMode("alpha")
        local img, quads = leafArt()
        local ang = c.t * (c.spin or 2) + c.seed
        local bob = math.sin(c.t * 4 + c.seed) * s * 0.25
        -- flip + squash so a spinning leaf turns over instead of orbiting
        local flip = math.sin(ang * 0.5)
        local sxScale = ((flip >= 0) and 1 or -1) * (c.flip or 1)
        local squash = 0.55 + 0.45 * math.abs(flip)
        local tint = c.tint or { 1, 1, 1 }
        if img and quads then
          local n = math.max(1, math.floor(img:getWidth() / 16))
          local q = quads[(c.frame or 0) % n]
          g.setColor(tint[1], tint[2], tint[3], 0.92 * fade)
          local sc = math.max(0.40, s * 0.62 * (c.size or 1))
          g.draw(img, q, sx, sy + bob, ang,
                 sxScale * sc / 16, squash * sc / 16, 8, 8)
        else
          g.setColor(tint[1] * 0.45, tint[2] * 0.62, tint[3] * 0.25, 0.85 * fade)
          g.rectangle("fill", sx - s * 0.35, sy - s * 0.25 + bob, s * 0.7, s * 0.5)
        end
      elseif c.kind == "bird" then
        g.setBlendMode("alpha")
        local flap = math.sin(c.t * 9 + c.seed)
        local img, quads = flyerArt(c.species)
        if img and quads then
          -- The walker sheet's LEFT-facing pair: frame 2 stands, frame 5 is
          -- the walk rung, and alternating them is the one animation this
          -- art has. It is a wingbeat here for the same reason it is a step
          -- on the ground -- the sheet only ever had two poses, and which
          -- one a passing Pidgey is in is the whole of the motion.
          --
          -- Mirrored when the flock is heading east, exactly as
          -- SpriteRenderer's stepFlip mirrors a walker: there is no right
          -- facing anywhere in this game's art.
          local q = quads[flap > 0 and 2 or 5] or quads[2]
          local sc = s * (c.scale or FLOCK_SCALE)
          local k = sc / 16
          g.setColor(1, 1, 1, 0.92 * fade)
          g.draw(img, q, sx, sy, 0, c.vx > 0 and -k or k, k, 8, 8)
        else
          -- No species on this map's table, or the bake said no. The old
          -- chevron: two wing strokes meeting at a body, beating.
          g.setColor(0.20, 0.22, 0.28, 0.9 * fade)
          local wing = s * 1.6
          local lift = flap * s * 0.8
          g.rectangle("fill", sx - wing, sy - lift, wing, s * 0.6)
          g.rectangle("fill", sx, sy - lift, wing, s * 0.6)
          g.rectangle("fill", sx - s * 0.4, sy - s * 0.2, s * 0.8, s * 0.8)
        end
      elseif c.kind == "sparrow" then
        g.setBlendMode("alpha")
        -- a plump brown speck with a paler breast; wings only in the air
        g.setColor(0.42, 0.30, 0.18, 0.95 * fade)
        g.rectangle("fill", sx - s, sy - s, s * 2, s * 1.4)
        g.setColor(0.72, 0.62, 0.45, 0.95 * fade)
        g.rectangle("fill", sx - s * 0.5, sy - s * 0.2, s, s * 0.6)
        if c.mode == "fly" then
          local flap = math.sin(c.t * 22)
          g.setColor(0.42, 0.30, 0.18, 0.95 * fade)
          g.rectangle("fill", sx - s * 2.2, sy - s - flap * s, s * 1.2, s * 0.5)
          g.rectangle("fill", sx + s, sy - s - flap * s, s * 1.2, s * 0.5)
        end
      elseif c.kind == "dragonfly" then
        g.setBlendMode("alpha")
        -- a teal needle with wings that shimmer rather than flap: real
        -- ones beat too fast to see, so a flicker of alpha is the truth
        g.setColor(0.25, 0.68, 0.62, 0.95 * fade)
        g.rectangle("fill", sx - s * 0.4, sy - s * 0.3, s * 0.8, s * 1.6)
        local shimmer = 0.25 + 0.35 * math.abs(math.sin(c.t * 30 + c.seed))
        g.setColor(0.75, 0.88, 0.92, shimmer * fade)
        g.rectangle("fill", sx - s * 1.6, sy - s * 0.2, s * 1.2, s * 0.5)
        g.rectangle("fill", sx + s * 0.4, sy - s * 0.2, s * 1.2, s * 0.5)
      end
    end
  end

  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  g.setColor(1, 1, 1, 1)
end

return AmbientLife
