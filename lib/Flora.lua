-- FLORA: grass with height to it, and the small moving things.
-- payload-version: 44
--
-- TUFTS.  Dramatic Shape stands two thin rows of grass per tile, evenly,
-- which is honest to the art and reads as a lawn.  Tall grass in this
-- game is supposed to be where things live.  This adds extra blades at
-- hashed positions and varied heights across every encounter cell -- the
-- engine's own Map:isGrassCell decides which those are -- built as
-- crossed pairs so a blade reads from any angle, and textured from the
-- tileset's own grass art.  Deterministic by position: the same meadow
-- grows the same way every time you walk into it, which is what stops it
-- shimmering.
--
-- PARTICLES.  Three kinds, all short-lived camera-facing motes drawn
-- from textures generated here at load (no asset ships, and none is
-- derived from anything):
--
--   SEEDS    kicked up behind you while you move through tall grass --
--            the visible reason to be wary of it
--   DRIPS    falling in caves, with a splash at the bottom, seeded on
--            the ceiling above wherever you are
--   FIREFLIES  outdoors after dark, bobbing low over grass, slow and few
--   LEAVES   drifting down under the forest canopy, tumbling as they fall
--   DUST     motes turning slowly in the air of an interior
--   FOAM     spray lifting off the water's edge
--   SMOKE    rising from a building's chimney, thinning as it climbs
--   RUSTLE   very occasionally, a shudder in a distant grass cell with
--            nothing attached to it -- purely to make you look
--
-- DARKNESS.  Gen 1's unlit floors exist so that Flash has a point, but a
-- top-down view can only express that as a smaller window.  Standing in
-- one, it should be dark.  This nests translucent shells around the eye:
-- anything a long way off sits behind several of them and fades toward
-- black, anything close sits in front of them all and is clear.  The
-- engine's own answer decides when -- field.darkMaps for the floor,
-- save.flashLit for whether Flash is up -- so using Flash genuinely
-- pushes the walls back, which in 2D it never quite did.
--
-- RAIN.  Gen 1 has no weather, so this mod keeps its own: long dry
-- spells broken by showers, on a clock seeded per session, outdoors only.
-- Drops fall around the eye and burst on landing; the world does not get
-- wet, because nothing here may touch the game.  While it rains every
-- NPC puts up an UMBRELLA -- a small pixel canopy generated in code,
-- bobbing with their walk -- which is the single cheapest way to make a
-- town feel like it noticed the weather.
--
-- SHAFTS.  Under the forest canopy, angled slabs of pale light lean down
-- through the leaves, drifting slowly so the wood never looks still.
--
-- FOG.  Lavender Town and its tower wear pale shells, the same trick the
-- cave dark uses but reversed: distance whitens instead of blackening.
--
-- Everything here is presentational: no collision, no encounter rates, no
-- movement.  Particles live in a fixed pool and are recycled, so a long
-- walk costs no more than a short one.

local V = ...

local Voxel3D = V.require("Voxel3D")
local okTS, TileShape = pcall(V.require, "TileShape")
local Mat4 = V.require("Mat4")
-- The first-person rig, if this build has one.  absol89's battle-art fork
-- is based on Dramatic Shape 1.3.0, which predates the rig entirely --
-- and an unguarded require there would fail at load and take this whole
-- module with it.  Without a rig the blend reads as zero, which means the
-- diorama's cutaway view: exactly right for a build that has no first
-- person to be inside of.
local okFP, FirstPerson = pcall(V.require, "FirstPerson")
if not (okFP and type(FirstPerson) == "table") then
  FirstPerson = { yaw = 0, blendEased = function() return 0 end }
end
local okDN, DayNight = pcall(V.require, "DayNight")

local Flora = {}

-- ------- tufts
local BLADES = { OFF = 0, SUBTLE = 2, WILD = 4 }   -- extra blades per cell

-- ------- darkness
local SHELLS = 7             -- nested shells; more is smoother and dearer
local DARK_NEAR = 26         -- clear within this radius
local DARK_FAR = 150         -- effectively black beyond it
local FLASH_MULT = 3.4       -- how far Flash pushes the walls back
local SHELL_SEGMENTS = 20


-- Draw blocks run inside this rather than a bare pcall.  Every one of
-- them changes graphics state -- colour, alpha, depth mode -- and a bare
-- pcall that throws midway leaves that state set for the REST OF THE
-- FRAME.  Anything drawn after us then inherits it: a stray alpha makes
-- another mod's sprites invisible, a stray depth mode makes them sort
-- wrongly, and the fault looks like theirs.  push("all")/pop() restores
-- the lot whatever happens inside.
local function guarded(fn)
  -- headless, or a driver without a graphics stack: just run it
  local g = love and love.graphics
  if not (g and g.push and g.pop) then return pcall(fn) end
  local pushed = pcall(g.push, "all")
  pcall(fn)
  if pushed then pcall(g.pop) end
end

-- ------- WIND.
-- The tufts are a cached mesh, so per-blade animation would mean
-- rebuilding it every frame -- far too dear.  Instead the blades are
-- split into a few meshes by position, and each is drawn through a SHEAR
-- that leans its tops over and leaves its roots where they are.  Give
-- each group its own phase and a gust travels ACROSS a field rather than
-- the whole meadow nodding in unison, which is the thing that would
-- betray it as a trick.
local WIND = { OFF = 0, BREEZE = 0.10, GUSTY = 0.26 }
local WIND_GROUPS = 4
local WIND_RATE = 0.9        -- how quickly a gust passes
local WIND_DIR = 0.7         -- prevailing direction, radians

-- x and z displaced in proportion to height; row-major, as Mat4 is.
local function shear(kx, kz)
  return { 1, kx, 0, 0,
           0, 1,  0, 0,
           0, kz, 1, 0,
           0, 0,  0, 1 }
end

-- ------- weather
local RAIN_DROPS = 70          -- drops aloft while it rains
local STORM_DROPS = 130        -- and in a proper storm
local RAIN_RADIUS = 120
local RAIN_TOP, RAIN_FALL = 130, 260
local DRY_MIN, DRY_MAX = 240, 900     -- seconds between showers
local WET_MIN, WET_MAX = 45, 150      -- seconds a shower lasts
local STORM_ODDS = 0.14               -- how many showers turn into storms

-- ------- lightning, with care.
-- Flashing light is a genuine photosensitivity risk, so this is built to
-- be rare and gentle rather than dramatic: strikes are far apart, never
-- in bursts (a hard minimum gap is enforced, well below the three-per-
-- second guidance), the screen brightening is partial and low-alpha
-- rather than a white-out, and it eases in and out instead of cutting.
-- Anyone who wants the storm without the flash has LIGHTNING off, and
-- the rain and thunderheads remain.
local BOLT_GAP_MIN = 4.5      -- seconds; a hard floor between strikes
local BOLT_CHANCE = 0.10      -- per second beyond that floor
local BOLT_LIFE = 0.42        -- how long a bolt hangs in the air
local FLASH_MAX = 0.17        -- the very most the screen brightens
local FLASH_FADE = 0.55       -- seconds to ease back down
local BOLT_Y, BOLT_DIST = 300, 620

-- ------- puddles
local PUDDLE_EVERY = 11       -- roughly one walkable cell in this many
local PUDDLE_SIDES = 10       -- corners on a puddle: round, not square
local PUDDLE_GROUPS = 4       -- staggered so they appear a few at a time
local PUDDLE_FILL = 26        -- seconds of rain to fill them
local PUDDLE_DRY = 70         -- and to dry them out again
-- The umbrella's centre height above an NPC's feet.  The art hangs its
-- pole down to the bottom of the frame, so this puts the grip at about
-- the middle of a 16px sprite -- where a hand would be -- rather than
-- floating above the head.
local UMBRELLA_H = 14

-- ------- shafts, fog, windows
local SHAFTS = 7
local FOG_MAPS = { LAVENDER_TOWN = true, POKEMONTOWER = true,
                   LAVENDER = true }

local LIP_H = 1.5            -- how far the lip stands proud of the top
local LIP_SHADE = 1.35       -- brighter than the surface it sits on
local BLADE_MIN, BLADE_MAX = 7, 20                 -- pixel heights
local BLADE_W = 7

-- ------- particles
local POOL = 150
local SEED_RATE = 22        -- per second while moving through grass
local DRIP_RATE = 3.5
local FLY_TARGET = 14       -- fireflies aloft at once, after dark
local LEAF_RATE = 2.2       -- per second under canopy
local DUST_TARGET = 12      -- motes hanging in an interior
local FOAM_RATE = 5         -- per second near a shoreline
local SMOKE_RATE = 2.4      -- per chimney per second
local RUSTLE_CHANCE = 0.06  -- per second, somewhere in view
local SWARMS = 3            -- swarm columns near the player
local GNATS_PER_SWARM = 7
local SWARM_RANGE = 150

local tuftCache = nil       -- { map, key, mesh, note }
local shellMesh = nil
local shaftMesh, umbrellaImg, dropImg = nil, nil, nil
local canopyCache = nil     -- { map, mesh, note, vines }
local vineHits = {}         -- [block key] = { x, z, at }
local swarms = nil          -- { { x, y, z, r } , ... }
local storm, boltAt, bolts, flash = false, nil, nil, 0
local movedThisFrame = 0
local boltImgs = nil
local puddleCache, wetness = nil, 0
local lightCache = nil
local rainUntil, dryUntil, raining = nil, nil, false
local drops = nil
local featureCache = nil    -- { map, chimneys = {}, shores = {}, grass = {} }
local parts, partMesh, tex = nil, nil, nil
local lastT, wasX, wasZ = nil, nil, nil

local function status(s) _G.__ds_flora_status = s end
status("loaded; awaiting the first frame")

local OPEN_AIR_TILESETS = {
  OVERWORLD = true, FOREST = true, PLATEAU = true, SHIP_PORT = true,
}

local function config()
  local pub = rawget(_G, "__ds_ceiling_config")
  if type(pub) == "function" then
    local ok, cfg = pcall(pub)
    if ok and type(cfg) == "table" then return cfg end
  end
  return {}
end

local function now()
  local ok, t = pcall(function() return love.timer.getTime() end)
  return ok and t or 0
end

local function isOutdoor(map)
  local def = map and map.def
  if not def then return false end
  local tid = def.tileset or (map.tileset and map.tileset.id)
  if tid and OPEN_AIR_TILESETS[tid] then return true end
  local ok, outdoor = pcall(function()
    local Map = require("src.world.Map")
    return Map.isOutdoor and Map.isOutdoor(def)
  end)
  if ok and outdoor ~= nil then return outdoor end
  local conns = def.connections
  return (conns and next(conns) ~= nil) and true or false
end

-- Dramatic Shape 1.5.5 added a 3RD rung: the same first-person rig with
-- the eye boomed back behind the shoulder.  The blend reads as engaged
-- there, so a sealed ceiling would slam shut in front of a camera that
-- is now OUTSIDE the room -- the lid problem, again.
--
-- showsPlayer() is the signal to use rather than extended(): it is false
-- when the boom collapses into the head (backed against a wall), and at
-- that moment the view really is first person and really does want its
-- ceiling.  Dramatic Shape reasons the same way about its own character
-- card.
local okTP, ThirdPerson = pcall(V.require, "ThirdPerson")
local function boomedOut()
  if not (okTP and ThirdPerson and ThirdPerson.showsPlayer) then
    return false
  end
  local ok, out = pcall(ThirdPerson.showsPlayer)
  return (ok and out) and true or false
end

local function isCanopy(map)
  if not (okDN and DayNight and DayNight.isCanopy) then return false end
  local ok, v = pcall(DayNight.isCanopy, map)
  return ok and v or false
end

-- The engine's own answers: which floors are unlit, and whether Flash is
-- currently up.  Both live on the running game rather than on the map, so
-- they are read fresh every frame and every read is fenced.
local function darkness(map)
  local ok, res = pcall(function()
    local Game = require("src.core.Game")
    local id = map.def and (map.def.id or map.def.name)
    -- The engine keeps the list at field.darkMaps.MAPS -- an array
    -- inside a table, as its own Rock Tunnel test asserts. This module
    -- looked for the ids directly on darkMaps, matched nothing, and so
    -- CAVE DARKNESS never once fired. Everything gated behind it -- the
    -- shells, Flash widening them, and later the pools, torches and bats
    -- -- was dead for the same reason.
    local dark = Game.data and Game.data.field and Game.data.field.darkMaps
    local isDark = false
    if dark and id then
      for _, m in ipairs(dark.maps or {}) do
        if m == id then isDark = true break end
      end
      -- tolerate a plain list, or a set, in case the shape ever changes
      if not isDark and dark[id] == true then isDark = true end
      if not isDark then
        for _, m in ipairs(dark) do
          if m == id then isDark = true break end
        end
      end
    end
    local lit = Game.save and Game.save.flashLit and true or false
    return { dark = isDark, flash = lit }
  end)
  if ok and type(res) == "table" then return res end
  return { dark = false, flash = false }
end

local function isNight()
  -- Dramatic Shape has no isNight(); what it has is bodyAt(t), whose
  -- third return says whether the body in the sky is the MOON.  That is
  -- the honest answer to "is it night", and it follows whichever mode the
  -- player is in -- pinned, cycling, or synced to their own clock.
  if okDN and DayNight and DayNight.bodyAt then
    local ok, moon = pcall(function()
      local t = DayNight.time and DayNight.time() or 0
      local _, _, isMoon = DayNight.bodyAt(t)
      return isMoon
    end)
    if ok and moon ~= nil then return moon and true or false end
  end
  -- without the module at all, fall back to the wall clock
  local okD, h = pcall(function() return tonumber(os.date("%H")) end)
  if okD and h then return (h < 6 or h >= 20) end
  return false
end

-- stable per-position pseudo-random in [0, 1)
-- The voxel shader DISCARDS any texel under half alpha and draws the rest
-- fully opaque (see Voxel3D: "if (p.a < 0.5) discard"), so this renderer
-- cannot express a soft edge at all -- every gradient sprite becomes a
-- hard blob, which is why the glows looked like cut-out squares.  The
-- answer is the one the hardware this game came from used: ORDERED
-- DITHER.  Partial coverage becomes a stipple of fully-on and fully-off
-- texels, which survives the discard and looks like Game Boy art rather
-- than like a mistake.
local BAYER = {
  {  0,  8,  2, 10 },
  { 12,  4, 14,  6 },
  {  3, 11,  1,  9 },
  { 15,  7, 13,  5 },
}
local function dither(x, y, a)
  if a >= 0.999 then return 1 end
  if a <= 0.001 then return 0 end
  local threshold = (BAYER[(y % 4) + 1][(x % 4) + 1] + 0.5) / 16
  return (a > threshold) and 1 or 0
end

-- A position hash, well distributed in every bit.  The previous one --
-- an LCG step over a 2^20 modulus -- had such poor high bits that
-- floor(h * 4) returned ZERO for every cell on a map: every puddle
-- landed in the same group, and nothing that leaned on it varied as
-- much as it looked like it did.  This is the standard fract-of-sine
-- mixer: deterministic, no bit operations, and properly spread.
local function hash01(a, b, c)
  local x = a * 127.1 + b * 311.7 + (c or 0) * 74.7
  local s = math.sin(x) * 43758.5453123
  return s - math.floor(s)
end

-- ------- tuft mesh
local INSET = 0.5
-- The atlas geometry, taken the way the chunk mesher takes it: the row
-- stride is tileset.tilesPerRow, NOT imageWidth/8.  Outdoor atlases carry
-- animation frames beyond the tile grid, so the two disagree there -- and
-- when they do, every tile index lands in the wrong place and quads
-- sample wide ribbons of the whole tileset.  That was the sky-ribbon
-- glitch: the maths, not the geometry.
local function uvFor(map, tile)
  local ts = map.tileset or {}
  local perRow = ts.tilesPerRow or 16
  local aw = ts.imageWidth or (perRow * 8)
  local ah = ts.imageHeight or 48
  -- and clamp into the grid: a tile index the atlas has no room for
  -- would otherwise sample off the end of the texture, which is how a
  -- quad ends up wearing a ribbon of the whole tileset
  local rows = math.max(1, math.floor(ah / 8))
  tile = math.max(0, math.floor(tile or 0)) % (perRow * rows)
  local ax = (tile % perRow) * 8
  local ay = math.floor(tile / perRow) * 8
  return (ax + INSET) / aw, (ax + 8 - INSET) / aw,
         (ay + INSET) / ah, (ay + 8 - INSET) / ah
end

local function buildTufts(map, perCell)
  local grassTile = map.tileset and map.tileset.grassTile
  if not grassTile then return nil, "tileset names no grass tile" end
  local wc, hc = map.widthCells or 0, map.heightCells or 0
  if wc == 0 or hc == 0 then return nil, "map has no cells" end
  local u0, u1, v0, v1 = uvFor(map, grassTile)
  -- one vertex list per wind group, so each can be sheared on its own
  -- clock; with wind off they simply all draw unsheared
  local groups = {}
  for g = 1, WIND_GROUPS do groups[g] = { verts = {}, idx = {}, quads = 0 } end
  local quads, cells = 0, 0

  local function blade(g, bx, bz, h, ang, shade)
    local G = groups[g]
    -- crossed pair: two quads at right angles, so it reads from any side
    for k = 0, 1 do
      local a = ang + k * math.pi * 0.5
      local dx, dz = math.cos(a) * BLADE_W * 0.5, math.sin(a) * BLADE_W * 0.5
      G.verts[#G.verts + 1] = { bx - dx, h, bz - dz, u0, v0, shade }
      G.verts[#G.verts + 1] = { bx + dx, h, bz + dz, u1, v0, shade }
      G.verts[#G.verts + 1] = { bx + dx, 0, bz + dz, u1, v1, shade }
      G.verts[#G.verts + 1] = { bx - dx, 0, bz - dz, u0, v1, shade }
      Voxel3D.pushQuad(G.idx, G.quads)
      G.quads = G.quads + 1
      quads = quads + 1
    end
  end

  for cy = 0, hc - 1 do
    for cx = 0, wc - 1 do
      local ok, grass = pcall(function() return map:isGrassCell(cx, cy) end)
      if ok and grass then
        cells = cells + 1
        for i = 1, perCell do
          local r1 = hash01(cx, cy, i)
          local r2 = hash01(cy, cx, i * 7)
          local r3 = hash01(cx + i, cy - i, 3)
          local bx = cx * 16 + 2 + r1 * 12
          local bz = cy * 16 + 2 + r2 * 12
          local h = BLADE_MIN + r3 * (BLADE_MAX - BLADE_MIN)
          -- taller blades read slightly darker: depth in the clump
          local shade = 0.78 + 0.22 * (1 - (h - BLADE_MIN)
                        / (BLADE_MAX - BLADE_MIN))
          -- group by POSITION, so a gust sweeps a band of the meadow
          local g = 1 + math.floor(hash01(cx + cy, cx - cy, 53) * WIND_GROUPS)
                        % WIND_GROUPS
          blade(g, bx, bz, h, r1 * math.pi, shade)
        end
      end
    end
  end
  if quads == 0 then return nil, "no grass cells" end
  local meshes = {}
  for g = 1, WIND_GROUPS do
    local G = groups[g]
    if G.quads > 0 then
      local m = Voxel3D.newMesh(G.verts, G.idx)
      if m then meshes[#meshes + 1] = { mesh = m, phase = g * 1.7 } end
    end
  end
  if #meshes == 0 then return nil, "driver refused the tuft meshes" end
  return meshes, ("%d blades over %d cells"):format(quads / 2, cells)
end

-- ------- the darkness shells: nested cylinders, drawn back to front so
-- each adds a little more black to whatever is behind it
local function buildShells()
  local verts, indexMap, quads = {}, {}, 0
  for s = 1, SHELLS do
    local f = s / SHELLS
    local r = DARK_NEAR + (DARK_FAR - DARK_NEAR) * f
    -- alpha carried in the shade attribute: near shells barely tint,
    -- far ones are almost solid, so the falloff is not linear
    local shade = 1 - (f * f) * 0.55
    for i = 0, SHELL_SEGMENTS - 1 do
      local a0 = (i / SHELL_SEGMENTS) * math.pi * 2
      local a1 = ((i + 1) / SHELL_SEGMENTS) * math.pi * 2
      local x0, z0 = math.cos(a0) * r, math.sin(a0) * r
      local x1, z1 = math.cos(a1) * r, math.sin(a1) * r
      -- UVs kept inside a single texel of the white pixel: these are
      -- tints, and must never sample anything with art in it
      verts[#verts + 1] = { x1, 90, z1, 0.5, 0.5, shade }
      verts[#verts + 1] = { x0, 90, z0, 0.5, 0.5, shade }
      verts[#verts + 1] = { x0, -40, z0, 0.5, 0.5, shade }
      verts[#verts + 1] = { x1, -40, z1, 0.5, 0.5, shade }
      Voxel3D.pushQuad(indexMap, quads)
      quads = quads + 1
    end
  end
  return Voxel3D.newMesh(verts, indexMap)
end

-- ------- an umbrella, drawn in code: a four-shade GBC canopy with a
-- scalloped hem, a shaft and a crooked handle.  Eight pixels of dome is
-- all it takes to read as "raining" from across a street.
local function makeUmbrella()
  local ok, img = pcall(function()
    local S = 16
    local data = love.image.newImageData(S, S)
    local DARK = { 0.13, 0.13, 0.18 }
    local BODY = { 0.83, 0.24, 0.28 }
    local LITE = { 0.96, 0.52, 0.50 }
    local SHAF = { 0.55, 0.44, 0.30 }
    local function put(x, y, c, a)
      if x >= 0 and y >= 0 and x < S and y < S then
        data:setPixel(x, y, c[1], c[2], c[3], dither(x, y, a or 1))
      end
    end
    -- The pole sits a pixel right of centre, and the whole thing is
    -- drawn around it: carried off to one side, the way a person holds
    -- an umbrella, rather than balanced on their head.  Baking the
    -- offset into the ART keeps it true from every angle, which a world
    -- offset would not -- a billboard turns to face you.
    local POLE = 9

    -- the canopy, higher in the frame now to leave room for the pole
    for x = 0, 15 do
      local dx = (x - POLE + 0.5) / 8.5
      local top = math.floor(1 + dx * dx * 3.5)
      for y = top, 5 do
        local c = (y == top) and DARK or ((x < POLE) and LITE or BODY)
        put(x, y, c)
      end
    end
    -- the scalloped hem
    for x = 0, 15 do
      put(x, 5, DARK)
      if (x % 4) == 1 or (x % 4) == 2 then put(x, 6, BODY); put(x, 7, DARK) end
    end
    -- the pole: all the way down the frame, so the grip lands at the
    -- height this is drawn at rather than somewhere above the sprite
    for y = 5, 15 do
      put(POLE, y, SHAF)
      put(POLE + 1, y, DARK)
    end
    -- a hand-sized grip, and the crook turning off to the left
    put(POLE, 11, DARK); put(POLE + 1, 11, DARK)
    put(POLE - 1, 14, SHAF); put(POLE - 2, 15, SHAF)
    put(POLE - 1, 15, DARK)
    local i = love.graphics.newImage(data)
    i:setFilter("nearest", "nearest")
    return i
  end)
  return ok and img or nil
end

-- a raindrop: a short vertical streak, not a dot
local function makeDrop()
  local ok, img = pcall(function()
    local S = 8
    local data = love.image.newImageData(S, S)
    for y = 0, S - 1 do
      for x = 0, S - 1 do
        local on = (x >= 3 and x <= 4 and y >= 1 and y <= 6)
        data:setPixel(x, y, 0.72, 0.82, 0.98,
                      dither(x, y, on and 0.8 or 0))
      end
    end
    local i = love.graphics.newImage(data)
    i:setFilter("nearest", "nearest")
    return i
  end)
  return ok and img or nil
end

-- How green a tile is, measured off the atlas: green minus the mean of
-- red and blue, averaged over its 64 pixels.  Leaves score high, fence
-- posts and dirt paths score at or below zero.
local function greenness(map, tex, tiles)
  local data = nil
  local ok = pcall(function()
    if tex.newImageData then data = tex:newImageData()
    elseif tex.getData then data = tex:getData() end
  end)
  if not (ok and data) then return nil end
  local ts = map.tileset or {}
  local perRow = ts.tilesPerRow or 16
  local dw, dh = data:getWidth(), data:getHeight()
  local out = {}
  for _, tile in ipairs(tiles) do
    local ax = (tile % perRow) * 8
    local ay = math.floor(tile / perRow) * 8
    if ax + 8 <= dw and ay + 8 <= dh then
      local sum, n = 0, 0
      for y = 0, 7 do
        for x = 0, 7 do
          local okP, r, g, b = pcall(function()
            local rr, gg, bb = data:getPixel(ax + x, ay + y)
            return rr, gg, bb
          end)
          if okP and g then
            sum = sum + (g - (r + b) / 2)
            n = n + 1
          end
        end
      end
      out[tile] = (n > 0) and (sum / n) or -1
    end
  end
  pcall(function() data:release() end)
  return out
end



-- Shared by what works across a boundary: the neighbouring-map draws,
-- the distance haze and the backs of buildings.
local MOUND = {}

-- NEIGHBOURING MAPS.
-- Dramatic Shape already meshes and draws the maps either side of you --
-- but every feature in this module was built for state.map alone, so
-- mountains, grass and canopy stopped dead at the boundary and appeared
-- the moment you crossed it.  That is the popping.  These build the same
-- geometry for each neighbour and draw it at the neighbour's offset,
-- exactly as the terrain is drawn.
--
-- Caches are per MAP rather than a single slot, so a neighbour's mesh is
-- built once and kept for as long as it stays next door.
MOUND.tufts, MOUND.seen = {}, {}

-- ------- THE BACKS OF BUILDINGS.
-- The mesher extrudes a building cell as a box and wears the same tile
-- on every face, so a shopfront's door and windows appear again on the
-- back wall -- false doors all over Kanto, leading nowhere.
--
-- A building's SIDE tile is the honest one: plain wall, which is what a
-- back wall is.  For every building cell whose north face is exposed, a
-- quad of the side tile is laid a hair proud of it.  Fronts are left
-- alone: a shopfront should look like a shopfront.
MOUND.BACKS = { cache = {}, EPS = 0.35 }

function MOUND.buildBacks(map)
  local wc, hc = map.widthCells or 0, map.heightCells or 0
  if wc == 0 or hc == 0 then return nil, 0 end
  local function walk(cx, cy)
    if cx < 0 or cy < 0 or cx >= wc or cy >= hc then return true end
    local ok, w = pcall(function() return map:isWalkableCell(cx, cy) end)
    return ok and w
  end
  local function tileOf(cx, cy)
    local ok, t = pcall(function() return map:tileAt(cx * 2, cy * 2) end)
    return ok and t or nil
  end

  -- ONLY THE MIRRORED DOOR.
  -- Covering the whole back wall put a slab of one tile across the
  -- entire rear of a building, which bleeds past its edges and looks
  -- worse than the fault it was fixing.  The mirroring that matters is
  -- the DOOR: the mesher repeats the door tile on the far face, so a
  -- house appears to have a second entrance round the back.  Cover that
  -- column and nothing else.
  local body = {}
  for cy = 0, hc - 1 do
    for cx = 0, wc - 1 do
      local okD, door = pcall(function()
        return map.isDoorTileCell and map:isDoorTileCell(cx, cy)
      end)
      if okD and door then
        -- JUST THE MIRRORED DOOR, in the back wall's OWN brick.
        -- Six cells of the side wall's art was worse than the fault: it
        -- pasted the gable end's flat purple over the brick and ran past
        -- the corner of the house. Only the door cell is covered now,
        -- and the tile comes from ALONG THE SAME BACK WALL -- the
        -- nearest cell left or right whose north face is also exposed --
        -- so the patch is the same brick as its neighbours and vanishes
        -- into them.
        -- A cell that is a REAL door in its own right is never covered:
        -- some houses genuinely have a back entrance.
        for up = 1, 5 do
          local ay = cy - up
          if not walk(cx, ay) then
            local okB, isDoor = pcall(function()
              return map.isDoorTileCell and map:isDoorTileCell(cx, ay)
            end)
            if not (okB and isDoor) then body[ay * wc + cx] = true end
          else break end
        end
      end
    end
  end

  local verts, indexMap, quads, backs = {}, {}, 0, 0
  for key in pairs(body) do
    local cy, cx = math.floor(key / wc), key % wc
    -- the north face is the back: exposed when the cell above is open
    if walk(cx, cy - 1) then
      -- THE BACK WALL'S OWN BRICK. Walk left and right along this same
      -- row looking for a cell that is solid, is not itself patched, and
      -- whose north face is exposed too -- that is a neighbouring piece
      -- of the very wall being repaired, so the patch matches. Only if
      -- the wall is one cell wide does this fall back to the row above.
      local side = nil
      for step = 1, 6 do
        for _, dx in ipairs({ -step, step }) do
          local nx = cx + dx
          if not side and nx >= 0 and nx < wc
             and not walk(nx, cy) and walk(nx, cy - 1)
             and body[cy * wc + nx] == nil then
            side = tileOf(nx, cy)
          end
        end
        if side then break end
      end
      side = side or tileOf(cx, cy + 1) or tileOf(cx, cy)
      if side then
        local uv = { uvFor(map, side) }
        local x0, z0 = cx * 16, cy * 16
        local o = MOUND.BACKS.EPS
        verts[#verts + 1] = { x0 + 16, 16, z0 - o, uv[1], uv[3], 0.62 }
        verts[#verts + 1] = { x0, 16, z0 - o, uv[2], uv[3], 0.62 }
        verts[#verts + 1] = { x0, 0, z0 - o, uv[2], uv[4], 0.62 }
        verts[#verts + 1] = { x0 + 16, 0, z0 - o, uv[1], uv[4], 0.62 }
        Voxel3D.pushQuad(indexMap, quads)
        quads = quads + 1
        backs = backs + 1
      end
    end
  end
  if quads == 0 then return nil, 0 end
  return Voxel3D.newMesh(verts, indexMap), backs
end


-- DISTANCE HAZE.  Air is not clear: things far off lose contrast and go
-- toward the colour of the sky.  The renderer multiplies, so this cools
-- and softens rather than truly lightening -- enough to sit a far map
-- back behind a near one, which is what stops the boundary reading as a
-- cut.
MOUND.HAZE_START, MOUND.HAZE_FULL = 220, 900
function MOUND.haze(dist)
  local f = math.max(0, math.min(1,
    (dist - MOUND.HAZE_START)
    / (MOUND.HAZE_FULL - MOUND.HAZE_START)))
  -- toward a pale cool grey, never all the way
  return 1 - f * 0.30, 1 - f * 0.22, 1 - f * 0.08
end

-- keep a cache from growing without limit as the player crosses Kanto
function MOUND.trim(store, keep)
  local n = 0
  for _ in pairs(store) do n = n + 1 end
  if n <= keep then return end
  for k, v in pairs(store) do
    if not MOUND.seen[k] then
      if v and v.mesh then pcall(v.mesh.release, v.mesh) end
      store[k] = nil
      n = n - 1
      if n <= keep then return end
    end
  end
end

-- MOUNTAINS were tried here and removed.  Deriving HEIGHT from how deep
-- a cell sits inside its cluster worked well and looked good; deciding
-- WHICH cells are rock never did.  The classes come back unauthored for
-- ordinary terrain, an Image cannot be read back for colour, and every
-- rule tried either raised the whole world -- trees, houses and sea --
-- or none of it.  Left out rather than left broken.

-- ------- WHAT LIVES UNDERGROUND: still water, torches, and bats.
--
-- POOLS are the puddles' permanent cousin: water that was here before
-- you and will be here after, so they are built once per cave rather
-- than filled by weather.  The drips we already spawn land in them.
--
-- SCONCES are torches set into the rock at intervals along a wall, not
-- only at the mouth: somebody has been down here before, and a cave with
-- one lit entrance and a mile of blackness reads as unfinished rather
-- than as dark.
--
-- BATS roost in clusters near the roof and scatter when you come too
-- close, exactly as the ground flock does out in the daylight -- and
-- they wear frames derived from the player's own Zubat, which is both
-- the right animal and no new artwork.
local POOL_EVERY = 13         -- one walkable cave cell in this many
local POOL_SIDES = 9
local SCONCE_EVERY = 7        -- cells of wall between torches
local SCONCE_Y = 19
local BAT_ROOSTS = 3
local BAT_PER_ROOST = 6
local BAT_Y = 27
local BAT_FLUSH = 46
local BAT_LIFE = 120
local DERIVED = "save/mod-derived/ds_fp_ceiling/birds/"

local poolCache, sconceCache = nil, nil
local bats, batPics, batsAt = nil, nil, nil

local function buildPools(map)
  local wc, hc = map.widthCells or 0, map.heightCells or 0
  if wc == 0 or hc == 0 then return nil, 0 end
  local waterTile = nil
  for tile in pairs(map.waterTiles or {}) do
    if type(tile) == "number" and (not waterTile or tile < waterTile) then
      waterTile = tile
    end
  end
  local u0, u1, v0, v1 = 0.5, 0.5, 0.5, 0.5
  if waterTile then u0, u1, v0, v1 = uvFor(map, waterTile) end
  local verts, indexMap, quads, pools = {}, {}, 0, 0
  for cy = 0, hc - 1 do
    for cx = 0, wc - 1 do
      local ok, walk = pcall(function() return map:isWalkableCell(cx, cy) end)
      if ok and walk
         and math.floor(hash01(cx, cy, 281) * POOL_EVERY) == 0 then
        local ccx = cx * 16 + 4 + hash01(cx, cy, 283) * 8
        local ccz = cy * 16 + 4 + hash01(cy, cx, 293) * 8
        local rx = 4.5 + hash01(cx, cy, 307) * 3.5
        local rz = 4.0 + hash01(cy, cx, 311) * 3.5
        local y = 1.2
        for i = 0, POOL_SIDES - 1 do
          local a0 = (i / POOL_SIDES) * math.pi * 2
          local a1 = ((i + 1) / POOL_SIDES) * math.pi * 2
          local w0 = 0.78 + hash01(cx * 5 + i, cy, 313) * 0.44
          local w1 = 0.78 + hash01(cx * 5 + i + 1, cy, 313) * 0.44
          verts[#verts + 1] = { ccx, y, ccz, (u0 + u1) * 0.5,
                                (v0 + v1) * 0.5, 0.9 }
          verts[#verts + 1] = { ccx + math.cos(a0) * rx * w0, y,
                                ccz + math.sin(a0) * rz * w0, u0, v0, 0.8 }
          verts[#verts + 1] = { ccx + math.cos(a1) * rx * w1, y,
                                ccz + math.sin(a1) * rz * w1, u1, v1, 0.8 }
          verts[#verts + 1] = { ccx, y, ccz, (u0 + u1) * 0.5,
                                (v0 + v1) * 0.5, 0.9 }
          Voxel3D.pushQuad(indexMap, quads)
          quads = quads + 1
        end
        pools = pools + 1
      end
    end
  end
  if quads == 0 then return nil, 0 end
  return Voxel3D.newMesh(verts, indexMap), pools
end

-- torches along the rock: a cell that is solid with open floor beside it
local function buildSconces(map)
  local wc, hc = map.widthCells or 0, map.heightCells or 0
  local out = {}
  local function walk(cx, cy)
    local ok, w = pcall(function() return map:isWalkableCell(cx, cy) end)
    return ok and w
  end
  for cy = 0, hc - 1 do
    for cx = 0, wc - 1 do
      if not walk(cx, cy) and (walk(cx, cy + 1) or walk(cx, cy - 1)
                               or walk(cx + 1, cy) or walk(cx - 1, cy)) then
        if math.floor(hash01(cx, cy, 317) * SCONCE_EVERY) == 0 then
          out[#out + 1] = { cx * 16 + 8, cy * 16 + 8 }
        end
      end
    end
  end
  return out
end

local function loadBatPics()
  if batPics ~= nil then return batPics end
  local function frame(suffix)
    local ok, img = pcall(function()
      local i = love.graphics.newImage(DERIVED .. "zubat" .. suffix .. ".png")
      i:setFilter("nearest", "nearest")
      return i
    end)
    return ok and img or nil
  end
  local a, b = frame("_a"), frame("_b")
  batPics = (a and { a = a, b = b or a }) or false
  return batPics
end

-- ------- DYNAMIC LIGHT (prototype).
-- Route C of the three we weighed: no shader patching and no re-meshing
-- of Dramatic Shape's chunks.  Light is flood-filled through the CELL
-- GRID from each source -- it spreads into walkable cells and stops at
-- solids -- so occlusion is inherent rather than computed: a lamp lights
-- round a corner and not through a wall.  The result is drawn as our own
-- floor pool, one quad per lit cell shaded by its light level, plus a
-- glow at the source itself.
--
-- Sources are found rather than authored: every doorway on an outdoor map
-- gets a lamp over it, which is what puts light outside the Pokemon
-- Centre and either side of the Mt Moon entrance.  It is additive over
-- Dramatic Shape's own shading, so it brightens surfaces rather than
-- truly relighting them -- at this scale that reads as lamplight.
local LIGHT_RADIUS = 7        -- cells the fill reaches
local LIGHT_Y = 1.1
local LAMP_HEIGHT = 22        -- where the lamp itself hangs
local LIGHT_WARM = { 1.0, 0.86, 0.55 }

local function buildLight(map)
  local wc, hc = map.widthCells or 0, map.heightCells or 0
  if wc == 0 or hc == 0 then return nil, 0 end

  -- the sources: doorways, which is where a porch lamp would be
  local sources = {}
  for cy = 0, hc - 1 do
    for cx = 0, wc - 1 do
      local okD, door = pcall(function()
        return map.isDoorTileCell and map:isDoorTileCell(cx, cy)
      end)
      if okD and door then sources[#sources + 1] = { cx, cy } end
    end
  end
  if #sources == 0 then return nil, 0 end

  -- flood fill: light spreads cell to cell and stops at anything solid
  local level = {}
  local queue, head = {}, 1
  for _, srcCell in ipairs(sources) do
    local key = srcCell[2] * wc + srcCell[1]
    level[key] = LIGHT_RADIUS
    queue[#queue + 1] = srcCell
  end
  while head <= #queue do
    local cell = queue[head]; head = head + 1
    local cx, cy = cell[1], cell[2]
    local here = level[cy * wc + cx] or 0
    if here > 1 then
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local nx, ny = cx + d[1], cy + d[2]
        if nx >= 0 and ny >= 0 and nx < wc and ny < hc then
          local nkey = ny * wc + nx
          local okW, walk = pcall(function()
            return map:isWalkableCell(nx, ny)
          end)
          -- a wall takes the light: it neither lights up nor passes it on
          if okW and walk and (level[nkey] or 0) < here - 1 then
            level[nkey] = here - 1
            queue[#queue + 1] = { nx, ny }
          end
        end
      end
    end
  end

  local verts, indexMap, quads = {}, {}, 0
  for key, lv in pairs(level) do
    local cy = math.floor(key / wc)
    local cx = key % wc
    local f = lv / LIGHT_RADIUS
    if f > 0.05 then
      local x0, z0 = cx * 16, cy * 16
      -- brightness falls off with the square, as light does
      local a = f * f
      verts[#verts + 1] = { x0, LIGHT_Y, z0 + 16, 0.5, 0.5, a }
      verts[#verts + 1] = { x0 + 16, LIGHT_Y, z0 + 16, 0.5, 0.5, a }
      verts[#verts + 1] = { x0 + 16, LIGHT_Y, z0, 0.5, 0.5, a }
      verts[#verts + 1] = { x0, LIGHT_Y, z0, 0.5, 0.5, a }
      Voxel3D.pushQuad(indexMap, quads)
      quads = quads + 1
    end
  end
  if quads == 0 then return nil, 0 end
  local mesh = Voxel3D.newMesh(verts, indexMap)
  if not mesh then return nil, 0 end
  return { mesh = mesh, sources = sources }, #sources
end

-- ------- PUDDLES.
-- Flat sheens laid on walkable ground while the rain fills them, hashed
-- so the same lane puddles in the same places, and fading out slowly once
-- the sky clears.  Sat a hair above the floor so they never fight it for
-- depth, and dark rather than mirror-bright: this world has no reflection
-- to give them, and a fake one would look worse than a wet patch.
-- Puddles are ROUND, wear the map's own water art, and arrive a few at a
-- time.  The first version drew one square quad per cell in a flat grey,
-- all of them appearing together -- which read as tiles switching on,
-- because that is exactly what it was.
--
-- Each puddle is a fan of wedges about a centre, with a wobble on the rim
-- so it is not a neat circle either, and each belongs to one of a few
-- GROUPS.  A group is its own mesh, and the draw eases them in one after
-- another as the ground wets, so puddles gather across a street.
local function buildPuddles(map)
  local wc, hc = map.widthCells or 0, map.heightCells or 0
  if wc == 0 or hc == 0 then return nil end

  -- the map's own water, so a puddle is made of the stuff the sea is
  local waterTile = nil
  for tile in pairs(map.waterTiles or {}) do
    if type(tile) == "number" and (not waterTile or tile < waterTile) then
      waterTile = tile
    end
  end
  local wu0, wu1, wv0, wv1 = 0.5, 0.5, 0.5, 0.5
  if waterTile then wu0, wu1, wv0, wv1 = uvFor(map, waterTile) end

  local groups = {}
  for g = 1, PUDDLE_GROUPS do groups[g] = { verts = {}, idx = {}, n = 0 } end
  local total = 0

  for cy = 0, hc - 1 do
    for cx = 0, wc - 1 do
      local ok, walk = pcall(function() return map:isWalkableCell(cx, cy) end)
      if ok and walk
         and math.floor(hash01(cx, cy, 71) * PUDDLE_EVERY) == 0 then
        local g = 1 + math.floor(hash01(cx, cy, 97) * PUDDLE_GROUPS)
                      % PUDDLE_GROUPS
        local G = groups[g]
        local ccx = cx * 16 + 5 + hash01(cx, cy, 83) * 6
        local ccz = cy * 16 + 5 + hash01(cy, cx, 89) * 6
        local rx = 3.6 + hash01(cx, cy, 73) * 2.8
        local rz = 3.2 + hash01(cy, cx, 79) * 2.6
        -- clear of the floor by enough that a moving camera cannot make
        -- the two surfaces argue about which is in front
        local y = 1.6
        local shade = 0.88 + hash01(cx, cy, 101) * 0.20
        for i = 0, PUDDLE_SIDES - 1 do
          local a0 = (i / PUDDLE_SIDES) * math.pi * 2
          local a1 = ((i + 1) / PUDDLE_SIDES) * math.pi * 2
          local w0 = 0.80 + hash01(cx * 7 + i, cy, 103) * 0.40
          local w1 = 0.80 + hash01(cx * 7 + i + 1, cy, 103) * 0.40
          local x0p = ccx + math.cos(a0) * rx * w0
          local z0p = ccz + math.sin(a0) * rz * w0
          local x1p = ccx + math.cos(a1) * rx * w1
          local z1p = ccz + math.sin(a1) * rz * w1
          local mu, mv = (wu0 + wu1) * 0.5, (wv0 + wv1) * 0.5
          -- a wedge, as a quad with its inner edge collapsed
          G.verts[#G.verts + 1] = { ccx, y, ccz, mu, mv, shade }
          G.verts[#G.verts + 1] = { x0p, y, z0p, wu0, wv0, shade * 0.93 }
          G.verts[#G.verts + 1] = { x1p, y, z1p, wu1, wv1, shade * 0.93 }
          G.verts[#G.verts + 1] = { ccx, y, ccz, mu, mv, shade }
          Voxel3D.pushQuad(G.idx, G.n)
          G.n = G.n + 1
        end
        total = total + 1
      end
    end
  end

  local out = {}
  for g = 1, PUDDLE_GROUPS do
    local G = groups[g]
    if G.n > 0 then
      local m = Voxel3D.newMesh(G.verts, G.idx)
      -- the share of wetness at which this group starts to show
      if m then out[#out + 1] = { mesh = m, at = (g - 1) / PUDDLE_GROUPS } end
    end
  end
  if #out == 0 then return nil end
  return out, total
end

-- ------- THE CANOPY.
-- Under the trees the mod's own particles were falling through open
-- black: Viridian Forest has walls of trees but no roof, because the 2D
-- game never needed one.  This grows one.  Every cell gets a leaf panel
-- at a hashed height between two limits, so the underside is stepped and
-- uneven rather than a flat lid, and the panels wear the wood's own
-- foliage art.  Roughly one cell in nine is left OPEN -- a gap in the
-- leaves -- which is where the daylight and the sun shafts come through,
-- and what stops it reading as a ceiling with a texture on it.
local CANOPY_LOW, CANOPY_HIGH = 40, 62
local CANOPY_GAP = 9        -- one cell in this many is a hole
local CANOPY_SKIRT = 6      -- how far a panel's rim hangs below it
local CANOPY_UPPER = 74     -- the solid layer above, seen through gaps
local CANOPY_HOLE = 5       -- cells cleared around the player in cutaway
-- THE EDGE OF THE WOOD.  A curtain hung on the map's rim reads as a wall
-- with leaves on it, because that is what it is.  Beyond the rim there
-- is now a RING of further trees -- trunks at varied heights under the
-- same canopy -- and the curtain moves out behind them.  You see wood
-- receding into wood, and the wall that stops you seeing further is
-- three trees away rather than one.
-- ------- VINES.
-- Strands hanging from the underside of the canopy: a couple of pixels
-- of stem with stubs off it, swaying on the same slow clock the grass
-- uses -- and swinging when you walk through them.
--
-- The swing is the interesting part.  A mesh is drawn with ONE matrix,
-- so a single vine cannot be moved without moving every vine with it.
-- The strands are therefore built into BLOCKS of eight cells square,
-- each its own mesh: walking through a block disturbs that block and
-- nothing else, which at this scale reads as "the vines you just pushed
-- through".  Distant wood keeps swaying gently.
--
-- The bend is a shear about the CANOPY rather than the ground -- vines
-- hang, so the free end is the bottom and the fixed end is the top.
local VINE_EVERY = 9        -- one leafy cell in this many grows a strand
local VINE_MIN, VINE_MAX = 7, 22
local VINE_LONG = 0.28      -- share of strands that run to the floor
local VINE_FLOOR = 3        -- how far above the ground a long one stops
local VINE_BLOCK = 8        -- cells per independently swinging block
local VINE_SWAY = 0.055     -- idle sway, as a fraction of length
local VINE_PUSH = 0.42      -- how far a brush throws them
local VINE_SETTLE = 1.9     -- seconds for a disturbed block to still
local VINE_REACH = 26       -- how close you must be to disturb one

-- x' = x + k*(top - y): the top stays put, the tail swings.
local function bend(kx, kz, top)
  return { 1, -kx, 0, kx * top,
           0, 1,   0, 0,
           0, -kz, 1, kz * top,
           0, 0,   0, 1 }
end

local CANOPY_RING = 4       -- cells of extra wood beyond the map
local RING_DENSITY = 0.62   -- how much of the ring is wood
local RING_LOW, RING_HIGH = 24, 44
local TREE_H = 16           -- the height the game draws its own trees at
local TALL_ODDS = 0.16      -- how often a ring tree grows a taller trunk
local CANOPY_GATE = 0.5     -- first-person blend above which the roof is whole


-- `mode` is "fp" (the whole roof) or "cutaway" (the diorama's view in):
-- leaves near the player are cleared and the near rim walls come down,
-- exactly as the interior ceiling opens up, so a wood can be looked into
-- from above instead of presenting a lid.
local function buildCanopy(map, tex, mode, pcx, pcy)
  if not (okTS and TileShape) then return nil, "no TileShape" end
  local okS, shapes = pcall(TileShape.forMap, map)
  if not (okS and shapes) then return nil, nil, "TileShape refused" end
  local wc, hc = map.widthCells or 0, map.heightCells or 0
  if wc == 0 or hc == 0 then return nil, nil, "map has no cells" end

  -- The wood's whole foliage palette, not just its commonest tile: every
  -- distinct tile the trees are drawn from, so the canopy can mix greens
  -- and browns the way a real one does instead of tiling one leaf.
  local tally, leafTile = {}, nil
  for cy = 0, hc - 1 do
    for cx = 0, wc - 1 do
      local okT, tile = pcall(function() return map:tileAt(cx * 2, cy * 2) end)
      if okT and tile then
        local okC, sh = pcall(TileShape.at, map, shapes, tile, cx * 2, cy * 2)
        local class = okC and sh and sh.class
        -- Gather BROADLY -- anything standing full height is a candidate
        -- -- and let the greenness measurement below decide what is
        -- actually foliage.  Restricting to class `tree` looked tidier
        -- and emptied the canopy completely: a wood's trees are not
        -- necessarily classed `tree` by the mesher.
        if class == "tree" or class == "wall" or class == "cliff"
           or (sh and (sh.h or 0) >= 16) then
          tally[tile] = (tally[tile] or 0) + 1
          if not leafTile or tally[tile] > tally[leafTile] then
            leafTile = tile
          end
        end
      end
    end
  end
  if not leafTile then
    return nil, nil, "no foliage found (no full-height cells on this map)"
  end

  -- the palette: greenest first where the atlas can be read, commonest
  -- first where it cannot, capped so one odd tile cannot dominate
  local palette = {}
  for tile in pairs(tally) do palette[#palette + 1] = tile end
  local green = tex and greenness(map, tex, palette) or nil
  if green then
    table.sort(palette, function(a, b)
      return (green[a] or -1) > (green[b] or -1)
    end)
    -- drop anything that is not actually foliage -- but never drop
    -- everything: if nothing clears the bar, the greenest two still
    -- make a canopy, because no canopy at all is the worse failure
    local keep = {}
    for _, t in ipairs(palette) do
      if (green[t] or -1) > 0.02 then keep[#keep + 1] = t end
    end
    if #keep == 0 then
      for i = 1, math.min(2, #palette) do keep[i] = palette[i] end
    end
    if #keep > 0 then palette = keep end
  else
    table.sort(palette, function(a, b) return tally[a] > tally[b] end)
  end
  while #palette > 5 do table.remove(palette) end
  if #palette == 0 then palette = { leafTile } end
  leafTile = palette[1]

  local verts, indexMap, quads, holes = {}, {}, 0, 0

  -- one vertex list per block of cells, so each can swing on its own
  local vineBlocks = {}
  local function vineBlock(cx, cy)
    local bx = math.floor(cx / VINE_BLOCK)
    local by = math.floor(cy / VINE_BLOCK)
    local key = bx .. ":" .. by
    local B = vineBlocks[key]
    if not B then
      B = { verts = {}, idx = {}, n = 0, key = key, top = 0 }
      vineBlocks[key] = B
    end
    return B
  end

  -- a strand: a stem hanging from the leaves with a few stubs off it,
  -- drawn as crossed quads so it reads from any angle
  local function hangVine(cx, cy, topY, tile)
    if math.floor(hash01(cx, cy, 163) * VINE_EVERY) ~= 0 then return end
    local B = vineBlock(cx, cy)
    -- most are short; a good few run the whole way down, which is what
    -- makes a canopy feel like something hanging over you rather than a
    -- ceiling with fringing
    local len
    if hash01(cx, cy, 229) < VINE_LONG then
      len = math.max(VINE_MIN, topY - VINE_FLOOR
                     - hash01(cx, cy, 233) * 4)
    else
      len = VINE_MIN + hash01(cx, cy, 167) * (VINE_MAX - VINE_MIN)
    end
    local x = cx * 16 + 3 + hash01(cx, cy, 173) * 10
    local z = cy * 16 + 3 + hash01(cy, cx, 179) * 10
    local w = 1.2 + hash01(cx, cy, 181) * 0.9
    local u0, u1, v0, v1 = uvFor(map, tile)
    local bottom = topY - len
    B.top = math.max(B.top, topY)
    local shade = 0.40 + hash01(cx, cy, 191) * 0.26
    for k = 0, 1 do
      local a = k * math.pi * 0.5 + hash01(cx, cy, 193) * math.pi
      local dx, dz = math.cos(a) * w, math.sin(a) * w
      B.verts[#B.verts + 1] = { x - dx, topY, z - dz, u0, v0, shade }
      B.verts[#B.verts + 1] = { x + dx, topY, z + dz, u1, v0, shade }
      B.verts[#B.verts + 1] = { x + dx, bottom, z + dz, u1, v1, shade * 0.8 }
      B.verts[#B.verts + 1] = { x - dx, bottom, z - dz, u0, v1, shade * 0.8 }
      Voxel3D.pushQuad(B.idx, B.n)
      B.n = B.n + 1
    end
    -- a stub or two, so a strand is not just a line
    local stubs = 1 + math.floor(hash01(cx, cy, 197) * 2)
    for sIdx = 1, stubs do
      local sy = bottom + len * (0.25 + 0.4 * hash01(cx + sIdx, cy, 199))
      local sd = (hash01(cx, cy + sIdx, 211) < 0.5) and -3.2 or 3.2
      B.verts[#B.verts + 1] = { x, sy + 1.6, z, u0, v0, shade }
      B.verts[#B.verts + 1] = { x + sd, sy + 1.6, z, u1, v0, shade }
      B.verts[#B.verts + 1] = { x + sd, sy, z, u1, v1, shade * 0.8 }
      B.verts[#B.verts + 1] = { x, sy, z, u0, v1, shade * 0.8 }
      Voxel3D.pushQuad(B.idx, B.n)
      B.n = B.n + 1
    end
  end
  local function panel(c1, c2, c3, c4, shade, tile)
    local u0, u1, v0, v1 = uvFor(map, tile or leafTile)
    verts[#verts + 1] = { c1[1], c1[2], c1[3], u0, v0, shade }
    verts[#verts + 1] = { c2[1], c2[2], c2[3], u1, v0, shade }
    verts[#verts + 1] = { c3[1], c3[2], c3[3], u1, v1, shade }
    verts[#verts + 1] = { c4[1], c4[2], c4[3], u0, v1, shade }
    Voxel3D.pushQuad(indexMap, quads)
    quads = quads + 1
  end

  -- which leaf a cell wears, and how deeply shaded: two independent
  -- hashes, so colour and depth do not correlate into visible banding
  local function leafOf(cx, cy)
    return palette[1 + math.floor(hash01(cx, cy, 23) * #palette) % #palette]
  end

  -- cleared: inside the cutaway's hole, where the camera needs to see
  local function cleared(cx, cy)
    if mode ~= "cutaway" or not pcx then return false end
    return math.max(math.abs(cx - pcx), math.abs(cy - pcy)) <= CANOPY_HOLE
  end

  local function heightAt(cx, cy)
    -- the ring counts: leaves carry on past the map's edge
    if cx < -CANOPY_RING or cy < -CANOPY_RING
       or cx >= wc + CANOPY_RING or cy >= hc + CANOPY_RING then
      return nil
    end
    if cleared(cx, cy) then return nil end
    if (math.floor(hash01(cx, cy, 5) * CANOPY_GAP)) == 0 then return nil end
    return CANOPY_LOW + hash01(cx, cy, 2) * (CANOPY_HIGH - CANOPY_LOW)
  end

  -- THE RING, built from the wood's OWN trees rather than invented ones.
  -- Each ring cell mirrors the nearest cell inside the map: if that cell
  -- is a solid tree, this one is a box of the same 16-pixel height
  -- wearing the same tile art the game draws it with, so the extra wood
  -- matches the wood you are standing in.  A few grow taller trunks for
  -- variety.  And every ring cell gets a FLOOR, because the ring used to
  -- hang over the void -- invisible behind the old curtain, obvious once
  -- the curtain moved back.
  local ring, ringFloor = 0, 0
  local groundTile = (map.tileset and map.tileset.grassTile) or leafTile

  local function sourceCell(cx, cy)
    local sx = math.max(0, math.min(wc - 1, cx))
    local sy = math.max(0, math.min(hc - 1, cy))
    return sx, sy
  end

  local function box(cx, cy, top, tile, inset)
    local x0, z0 = cx * 16 + inset, cy * 16 + inset
    local x1, z1 = (cx + 1) * 16 - inset, (cy + 1) * 16 - inset
    local base = -0.2
    local faces = {
      { { x0, top, z1 }, { x1, top, z1 }, { x1, base, z1 }, { x0, base, z1 },
        0.86 },
      { { x1, top, z0 }, { x0, top, z0 }, { x0, base, z0 }, { x1, base, z0 },
        0.58 },
      { { x1, top, z1 }, { x1, top, z0 }, { x1, base, z0 }, { x1, base, z1 },
        0.74 },
      { { x0, top, z0 }, { x0, top, z1 }, { x0, base, z1 }, { x0, base, z0 },
        0.66 },
      -- a top, so a tree seen from a rise is not an open tube
      { { x0, top, z1 }, { x1, top, z1 }, { x1, top, z0 }, { x0, top, z0 }, 1.0 },
    }
    for _, f in ipairs(faces) do
      panel(f[1], f[2], f[3], f[4], f[5], tile)
    end
  end

  local function ringTrunk(cx, cy)
    -- The floor sits a hair BELOW the world's own ground rather than
    -- level with it.  Dramatic Shape draws the neighbouring maps too, so
    -- out here our floor and a real one can occupy the same plane -- and
    -- two surfaces at identical depth flicker as the camera moves, which
    -- is the glitching.  Half a pixel down means real ground always
    -- wins and ours only shows where there is genuinely nothing.
    local x0, z0 = cx * 16, cy * 16
    panel({ x0, 0.05, z0 + 16 }, { x0 + 16, 0.05, z0 + 16 },
          { x0 + 16, 0.05, z0 }, { x0, 0.05, z0 }, 0.92, groundTile)
    ringFloor = ringFloor + 1

    if hash01(cx, cy, 149) > RING_DENSITY then return end

    -- mirror the nearest cell inside the map: its art, its solidity
    local sx, sy = sourceCell(cx, cy)
    local okT, srcTile = pcall(function() return map:tileAt(sx * 2, sy * 2) end)
    local okW, walk = pcall(function() return map:isWalkableCell(sx, sy) end)
    local solidSource = okW and not walk
    local tile = (okT and srcTile) or leafOf(cx, cy)

    if solidSource then
      -- a tree the size the game draws its trees
      box(cx, cy, TREE_H, tile, 0)
      -- and occasionally a taller one behind it, for a treeline
      if hash01(cx, cy, 151) < TALL_ODDS then
        box(cx, cy, RING_LOW + hash01(cx, cy, 157)
                    * (RING_HIGH - RING_LOW), leafOf(cx, cy), 3)
      end
    else
      -- open ground inside the map means open ground out here too,
      -- with the odd standing trunk to break the sightline
      if hash01(cx, cy, 163) < 0.30 then
        box(cx, cy, RING_LOW + hash01(cx, cy, 167)
                    * (RING_HIGH - RING_LOW), leafOf(cx, cy), 4)
      end
    end
    ring = ring + 1
  end

  -- the upper layer: solid, flat-ish, and lighter, so a gap in the lower
  -- leaves shows sunlit foliage above instead of black
  local upper = 0
  for cy = -CANOPY_RING, hc - 1 + CANOPY_RING do
    for cx = -CANOPY_RING, wc - 1 + CANOPY_RING do
      if not cleared(cx, cy) then
        local uh = CANOPY_UPPER + hash01(cx, cy, 61) * 6
        local x0, z0 = cx * 16, cy * 16
        panel({ x0, uh, z0 + 16 }, { x0 + 16, uh, z0 + 16 },
              { x0 + 16, uh, z0 }, { x0, uh, z0 },
              0.62 + hash01(cx, cy, 67) * 0.20, leafOf(cx, cy))
        upper = upper + 1
      end
    end
  end

  for cy = -CANOPY_RING, hc - 1 + CANOPY_RING do
    for cx = -CANOPY_RING, wc - 1 + CANOPY_RING do
      -- beyond the map body: more wood, not a wall
      local beyond = cx < 0 or cy < 0 or cx >= wc or cy >= hc
      if beyond and not cleared(cx, cy) then ringTrunk(cx, cy) end
      local h = heightAt(cx, cy)
      if not h then
        holes = holes + 1
      else
        local x0, z0 = cx * 16, cy * 16
        -- deeper leaves are darker: the canopy has its own shading
        -- height gives the base shade; a second hash mottles it, so the
        -- ceiling reads as leaves at many depths rather than a gradient
        local shade = 0.30 + (h - CANOPY_LOW)
                      / (CANOPY_HIGH - CANOPY_LOW) * 0.26
                      + hash01(cx, cy, 31) * 0.22
        local tile = leafOf(cx, cy)
        -- the underside, seen from below
        panel({ x0, h, z0 + 16 }, { x0 + 16, h, z0 + 16 },
              { x0 + 16, h, z0 }, { x0, h, z0 }, shade, tile)
        hangVine(cx, cy, h, tile)
        -- a skirt wherever the neighbour is lower or missing, so the
        -- canopy has thickness instead of being paper
        local sides = {
          { heightAt(cx, cy + 1), { x0, z0 + 16 }, { x0 + 16, z0 + 16 } },
          { heightAt(cx, cy - 1), { x0 + 16, z0 }, { x0, z0 } },
          { heightAt(cx + 1, cy), { x0 + 16, z0 + 16 }, { x0 + 16, z0 } },
          { heightAt(cx - 1, cy), { x0, z0 }, { x0, z0 + 16 } },
        }
        for _, side in ipairs(sides) do
          local nh = side[1]
          local drop = nh and math.max(0, h - nh) or CANOPY_SKIRT
          if drop > 0.5 then
            local a, b = side[2], side[3]
            panel({ a[1], h, a[2] }, { b[1], h, b[2] },
                  { b[1], h - drop, b[2] }, { a[1], h - drop, a[2] },
                  shade * 0.8, tile)
          end
        end
      end
    end
  end
  -- THE WALLS.  A canopy over an open-sided wood still shows black at
  -- the horizon: the leaves stop and the void begins.  Every cell on the
  -- map's rim grows a curtain of foliage from the ground to the canopy,
  -- so the wood closes on all four sides and reads as depth rather than
  -- as an edge.  Doorways out are warp cells and stay clear.
  local walls = 0

  local function curtain(cx, cy, side)
    -- in cutaway the near rim is what the camera looks over, so the
    -- south wall and anything level with or below the player melts away
    if mode == "cutaway" and pcy then
      if side == "s" then return end
      if cy >= pcy and (side == "e" or side == "w") then return end
    end
    local x0, z0 = cx * 16, cy * 16
    local topH = CANOPY_UPPER + 8
    local tile = leafOf(cx, cy)
    local okW, isWarp = pcall(function()
      return map.isDoorTileCell and map:isDoorTileCell(cx, cy)
    end)
    if okW and isWarp then return end
    local c1, c2, c3, c4
    if side == "s" then
      c1 = { x0, topH, z0 + 16 }; c2 = { x0 + 16, topH, z0 + 16 }
      c3 = { x0 + 16, 0, z0 + 16 }; c4 = { x0, 0, z0 + 16 }
    elseif side == "n" then
      c1 = { x0 + 16, topH, z0 }; c2 = { x0, topH, z0 }
      c3 = { x0, 0, z0 }; c4 = { x0 + 16, 0, z0 }
    elseif side == "e" then
      c1 = { x0 + 16, topH, z0 + 16 }; c2 = { x0 + 16, topH, z0 }
      c3 = { x0 + 16, 0, z0 }; c4 = { x0 + 16, 0, z0 + 16 }
    else
      c1 = { x0, topH, z0 }; c2 = { x0, topH, z0 + 16 }
      c3 = { x0, 0, z0 + 16 }; c4 = { x0, 0, z0 }
    end
    -- darker than the roof: this is the wood receding, not lit leaves
    panel(c1, c2, c3, c4, 0.30 + hash01(cx, cy, 41) * 0.14, tile)
    walls = walls + 1
  end

  local lo, hiX, hiY = -CANOPY_RING, wc - 1 + CANOPY_RING, hc - 1 + CANOPY_RING
  for cy = lo, hiY do
    for cx = lo, hiX do
      if cy == lo then curtain(cx, cy, "n") end
      if cy == hiY then curtain(cx, cy, "s") end
      if cx == lo then curtain(cx, cy, "w") end
      if cx == hiX then curtain(cx, cy, "e") end
    end
  end

  if quads == 0 then return nil, nil, "canopy came out empty" end
  local vines = {}
  for _, B in pairs(vineBlocks) do
    if B.n > 0 then
      local m = Voxel3D.newMesh(B.verts, B.idx)
      if m then
        vines[#vines + 1] = { mesh = m, key = B.key, top = B.top,
                              phase = hash01(#vines + 1, 7, 223) * 6.28 }
      end
    end
  end

  local mesh = Voxel3D.newMesh(verts, indexMap)
  if not mesh then return nil, "driver refused the canopy mesh" end
  return mesh, vines,
    ("canopy %d panels, %d gaps over %d upper, %d ring trees on %d floor, "
     .. "%d walls, %d leaf tiles")
    :format(quads, holes, upper, ring, ringFloor, walls, #palette)
end

-- ------- FORKED LIGHTNING, drawn into a few textures at load and picked
-- between, so a strike costs nothing at the moment it happens.  A bolt is
-- a jagged trunk that wanders as it descends with two or three forks
-- peeling off it, each thinner and shorter than the last -- which is what
-- makes it read as lightning rather than as a crack in the screen.

local function makeBolts()
  local out = {}
  for n = 1, 3 do
    local ok, img = pcall(function()
      local W, H = 64, 128
      local data = love.image.newImageData(W, H)
      for y = 0, H - 1 do
        for x = 0, W - 1 do data:setPixel(x, y, 1, 1, 1, 0) end
      end
      local function put(x, y, a)
        x, y = math.floor(x), math.floor(y)
        if x >= 0 and y >= 0 and x < W and y < H then
          data:setPixel(x, y, 1, 1, 0.96, dither(x, y, a))
        end
      end
      -- a single limb: walks downward, wandering, thinning as it goes
      local function limb(x, y, len, wide, spread)
        local seg = 0
        while seg < len and y < H - 1 do
          local run = 3 + math.random() * 5
          local dx = (math.random() - 0.5) * spread
          for i = 0, run do
            local px2 = x + dx * (i / run)
            local py2 = y + i
            for w = 0, math.max(0, math.floor(wide)) do
              put(px2 - w, py2, w == 0 and 1 or 0.45)
              put(px2 + w, py2, w == 0 and 1 or 0.45)
            end
            -- a faint halo so it does not look like a hairline
            put(px2 - wide - 1, py2, 0.16)
            put(px2 + wide + 1, py2, 0.16)
          end
          x, y = x + dx, y + run
          seg = seg + run
          wide = math.max(0, wide - 0.05)
        end
        return x, y
      end
      local tx, ty = W / 2 + (math.random() - 0.5) * 10, 0
      -- the trunk, then forks peeling off partway down
      local forks = 2 + (n % 2)
      for f = 0, forks do
        local startX = tx + (math.random() - 0.5) * 14
        local startY = (f == 0) and 0 or (18 + math.random() * 52)
        limb(startX, startY, (f == 0) and H or (26 + math.random() * 44),
             (f == 0) and 1.4 or 0.7, (f == 0) and 7 or 11)
      end
      local i = love.graphics.newImage(data)
      i:setFilter("nearest", "nearest")
      return i
    end)
    if ok and img then out[#out + 1] = img end
  end
  return (#out > 0) and out or nil
end

-- ------- VINES.
-- Strands hanging out of the canopy: a stem with leaf stubs, drawn as a
-- crossed pair so they read from any angle.  Two things move them.
--
-- IDLE is a slow sine, each strand on its own phase, applied as a SHEAR
-- so the anchor at the top stays put and the free end swings -- the same
-- trick the grass uses, and the reason this costs nothing.
--
-- BRUSH is the interesting half.  Walk into one and it takes a shove
-- away from you, proportional to how fast you were going, and then
-- springs back over a second or so with the overshoot damped out.  The
-- state is two numbers per strand, and only strands near the player are
-- updated at all, so a wood full of them costs the same as a few.
--
-- Inside the head or over the shoulder only: from the diorama you would
-- be looking down at the tops of them through the leaves.
local VINE_EVERY = 5          -- one canopy cell in this many
local VINE_MIN, VINE_MAX = 10, 26
local VINE_W = 5
local VINE_VIEW = 190         -- strands beyond this are neither drawn nor moved
local BRUSH_R = 17            -- how close counts as brushing past
local BRUSH_PUSH = 4.6        -- how hard a stride shoves one
local SPRING = 7.0            -- how sharply it returns
local DAMP = 3.6              -- and how quickly it stops arguing about it
-- How much of a shove reaches the shear.  At 0.08 a brushed strand swung
-- no further than the idle breeze did, which made the whole effect
-- invisible: being walked through has to read as bigger than weather.
local BRUSH_LEAN = 0.24
local VINE_SWAY = 0.055

local vineMesh, vineImg, vines = nil, nil, nil

-- a strand: two stem pixels with stubs off alternate sides
local function makeVine()
  local ok, img = pcall(function()
    local W, H = 8, 16
    local data = love.image.newImageData(W, H)
    for y = 0, H - 1 do
      for x = 0, W - 1 do data:setPixel(x, y, 0, 0, 0, 0) end
    end
    local function put(x, y, r, g, b)
      if x >= 0 and y >= 0 and x < W and y < H then
        data:setPixel(x, y, r, g, b, 1)
      end
    end
    for y = 0, H - 1 do
      put(3, y, 0.26, 0.54, 0.28)
      put(4, y, 0.16, 0.40, 0.20)
      -- a stub every few pixels, alternating sides
      if y % 5 == 2 then
        put(2, y, 0.34, 0.62, 0.34); put(1, y, 0.26, 0.54, 0.28)
      elseif y % 5 == 4 then
        put(5, y, 0.34, 0.62, 0.34); put(6, y, 0.26, 0.54, 0.28)
      end
    end
    local i = love.graphics.newImage(data)
    i:setFilter("nearest", "nearest")
    return i
  end)
  return ok and img or nil
end

-- one unit strand, hanging from the origin down to y = -1
local function makeVineMesh()
  local verts, indexMap, quads = {}, {}, 0
  for k = 0, 1 do
    local a = k * math.pi * 0.5
    local dx, dz = math.cos(a) * 0.5, math.sin(a) * 0.5
    verts[#verts + 1] = { -dx, 0, -dz, 0, 0, 1 }
    verts[#verts + 1] = { dx, 0, dz, 1, 0, 1 }
    verts[#verts + 1] = { dx, -1, dz, 1, 1, 1 }
    verts[#verts + 1] = { -dx, -1, -dz, 0, 1, 1 }
    Voxel3D.pushQuad(indexMap, quads)
    quads = quads + 1
  end
  return Voxel3D.newMesh(verts, indexMap)
end

-- ------- sun shafts: leaning slabs of pale light under the canopy
local function buildShafts()
  local verts, indexMap, quads = {}, {}, 0
  for i = 1, SHAFTS do
    local a = (i / SHAFTS) * math.pi * 2
    local r = 40 + (i % 3) * 34
    local x, z = math.cos(a) * r, math.sin(a) * r
    local w = 14 + (i % 4) * 5
    local lean = 26
    -- a slab from the canopy down to the floor, leaning with the sun
    local shade = 0.5 + (i % 3) * 0.12
    verts[#verts + 1] = { x - w, 120, z - w, 0.5, 0.5, shade }
    verts[#verts + 1] = { x + w, 120, z - w, 0.5, 0.5, shade }
    verts[#verts + 1] = { x + w + lean, 0, z + w + lean, 0.5, 0.5, shade * 0.3 }
    verts[#verts + 1] = { x - w + lean, 0, z + w + lean, 0.5, 0.5, shade * 0.3 }
    Voxel3D.pushQuad(indexMap, quads)
    quads = quads + 1
  end
  return Voxel3D.newMesh(verts, indexMap)
end

-- A plain white pixel.  Passing nil as a texture does NOT unbind the
-- last one: the draw simply keeps whatever was bound, which for anything
-- following the terrain is the map atlas -- and that is how a sun shaft
-- ends up as a floating ribbon of the whole tileset.  Every untextured
-- surface samples this instead.
local whiteImg = nil
local function white()
  if whiteImg then return whiteImg end
  local ok, img = pcall(function()
    local data = love.image.newImageData(2, 2)
    for y = 0, 1 do
      for x = 0, 1 do data:setPixel(x, y, 1, 1, 1, 1) end
    end
    local i = love.graphics.newImage(data)
    i:setFilter("nearest", "nearest")
    return i
  end)
  if ok then whiteImg = img end
  return whiteImg
end

-- ------- particle textures, generated once
local function makeTex()
  -- A mote is a SOLID little disc whose edge darkens, not a soft one
  -- whose edge fades.  Dithering an alpha falloff at this size produced a
  -- sparse stipple that read as noise rather than as light -- the whole
  -- point of a firefly is that it is a small bright dot.
  local function dot(r, g, b, soft)
    local ok, img = pcall(function()
      local S = 8
      local data = love.image.newImageData(S, S)
      for y = 0, S - 1 do
        for x = 0, S - 1 do
          local dx, dy = (x - 3.5) / 3.5, (y - 3.5) / 3.5
          local d = math.sqrt(dx * dx + dy * dy)
          local a, k = 0, 1
          if d < 0.45 then a, k = 1, 1            -- the core, full bright
          elseif d < 0.75 then a, k = 1, 0.72     -- a rim, dimmer
          elseif d < 0.95 then a, k = 1, 0.42     -- and a darker edge
          end
          data:setPixel(x, y, r * k, g * k, b * k, a)
        end
      end
      local i = love.graphics.newImage(data)
      i:setFilter("nearest", "nearest")
      return i
    end)
    return ok and img or nil
  end
  -- a leaf is a flat flake rather than a dot: four pixels wide, so it
  -- catches the eye as it tumbles
  local function flake(r, g, b)
    local ok, img = pcall(function()
      local S = 8
      local data = love.image.newImageData(S, S)
      for y = 0, S - 1 do
        for x = 0, S - 1 do
          local inLeaf = (y >= 3 and y <= 4 and x >= 1 and x <= 6)
                      or (y >= 2 and y <= 5 and x >= 2 and x <= 5)
          data:setPixel(x, y, r, g, b, inLeaf and 1 or 0)
        end
      end
      local i = love.graphics.newImage(data)
      i:setFilter("nearest", "nearest")
      return i
    end)
    return ok and img or nil
  end
  return {
    seed  = dot(0.55, 0.78, 0.35, false),
    drip  = dot(0.62, 0.78, 0.95, true),
    fly   = dot(1.0, 0.95, 0.45, true),
    leaf  = flake(0.78, 0.62, 0.22),
    dust  = dot(0.95, 0.92, 0.80, true),
    foam  = dot(0.92, 0.96, 1.0, true),
    smoke = dot(0.72, 0.72, 0.70, true),
  }
end

local function makeQuad()
  local verts = {
    { -0.5, 0.5, 0, 0, 0, 1 }, { 0.5, 0.5, 0, 1, 0, 1 },
    { 0.5, -0.5, 0, 1, 1, 1 }, { -0.5, -0.5, 0, 0, 1, 1 },
  }
  local indexMap = {}
  Voxel3D.pushQuad(indexMap, 0)
  return Voxel3D.newMesh(verts, indexMap)
end

local function spawn(kind, x, y, z, vx, vy, vz, life, size)
  parts = parts or {}
  local slot = nil
  for i = 1, POOL do
    local p = parts[i]
    if not p or p.life <= 0 then slot = i; break end
  end
  if not slot then return end
  parts[slot] = { kind = kind, x = x, y = y, z = z, vx = vx, vy = vy,
                  vz = vz, life = life, max = life, size = size }
  -- returned so a caller can attach its own fields (a gnat's swarm and
  -- orbit) without hunting back through the pool for the one it just made
  return parts[slot]
end

-- ------- the map's features, found once: where smoke rises, where spray
-- lifts, where a rustle can happen.  A chimney is the north-west corner
-- of each roof cluster -- one per building, stable, and always the part
-- of a Gen 1 roof that reads as its top.
local function scanFeatures(map)
  local wc, hc = map.widthCells or 0, map.heightCells or 0
  local out = { chimneys = {}, shores = {}, grass = {} }
  local shapes = nil
  if okTS and TileShape then
    local ok, sh = pcall(TileShape.forMap, map)
    if ok then shapes = sh end
  end
  local roof, solidAt = {}, {}
  for cy = 0, hc - 1 do
    for cx = 0, wc - 1 do
      -- grass
      local okG, g = pcall(function() return map:isGrassCell(cx, cy) end)
      if okG and g then out.grass[#out.grass + 1] = { cx, cy } end
      -- shoreline: dry land touching water
      local okW, w = pcall(function() return map:isWaterCell(cx, cy) end)
      if okW and not w then
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          local okN, nw = pcall(function()
            return map:isWaterCell(cx + d[1], cy + d[2])
          end)
          if okN and nw then
            out.shores[#out.shores + 1] = { cx, cy }
            break
          end
        end
      end
      -- Buildings, for chimneys.  Asking TileShape for class "roof"
      -- found NOTHING in the real game -- the same trap the canopy fell
      -- into with class "tree" -- so a building is identified by its
      -- shape instead: a solid block of unwalkable cells at least two by
      -- two.  Trees and fences are unwalkable too, but they are thin;
      -- almost nothing except a building is square and solid.
      local okW, walk = pcall(function() return map:isWalkableCell(cx, cy) end)
      if okW and not walk then solidAt[cy * wc + cx] = true end
      if shapes then
        local okT, tile = pcall(function()
          return map:tileAt(cx * 2, cy * 2)
        end)
        tile = okT and tile or nil
        if tile then
          local okS, sh = pcall(TileShape.at, map, shapes, tile,
                                cx * 2, cy * 2)
          if okS and sh and sh.class == "roof" then roof[cy * wc + cx] = true end
        end
      end
    end
  end
  -- Prefer the class where it exists.  Where it does not, a solid 2x2
  -- was the test -- and a solid 2x2 is also a clump of trees, a rock, a
  -- fence corner or a hedge, which is why smoke was rising off the
  -- scenery.  A BUILDING has a DOOR: find the doors, walk up from each
  -- into the solid block above it, and smoke THAT.  Nothing else counts.
  local body = roof
  if not next(body) then
    for cy = 0, hc - 1 do
      for cx = 0, wc - 1 do
        local okD, door = pcall(function()
          return map.isDoorTileCell and map:isDoorTileCell(cx, cy)
        end)
        if okD and door then
          -- the roof sits above the doorway: climb until the solid runs
          -- out, and put the chimney on the last solid cell
          local top = nil
          for up = 1, 4 do
            if solidAt[(cy - up) * wc + cx] then top = cy - up else break end
          end
          if top then body[top * wc + cx] = true end
        end
      end
    end
  end

  -- one chimney per cluster: the cell with nothing of the same kind to
  -- its west or north, so a building smokes once rather than per tile
  for key in pairs(body) do
    local cy = math.floor(key / wc)
    local cx = key % wc
    if not body[cy * wc + (cx - 1)] and not body[(cy - 1) * wc + cx] then
      out.chimneys[#out.chimneys + 1] = { cx, cy }
    end
  end
  return out
end

-- Each of these was inlined in Flora.draw until the closure hit
-- LuaJIT's 60-upvalue ceiling; they are lifted out so the draw stays
-- inside it, and so each effect can be read on its own.

local function drawRain(state, cfg, px, pz, yaw, t, dt, raining)
  -- ---------- rain, and the umbrellas that answer it
  local rainNote = ""
  if raining then
    dropImg = dropImg or makeDrop()
    umbrellaImg = umbrellaImg or makeUmbrella()
    partMesh = partMesh or makeQuad()
    drops = drops or {}
    if dropImg and partMesh then
      guarded(function()
        love.graphics.setDepthMode("lequal", false)
        -- drops live in a ring around the eye and recycle upward: the
        -- shower travels with you, which is what a shower looks like
        local count = storm and STORM_DROPS or RAIN_DROPS
        for i = 1, math.min(count, RAIN_DROPS * 2) do
          local d = drops[i]
          if not d then
            local a = math.random() * math.pi * 2
            d = { x = math.cos(a) * math.random() * RAIN_RADIUS,
                  z = math.sin(a) * math.random() * RAIN_RADIUS,
                  y = math.random() * RAIN_TOP, splash = 0 }
            drops[i] = d
          end
          if d.splash > 0 then
            d.splash = d.splash - dt
            if d.splash <= 0 then
              local a = math.random() * math.pi * 2
              d.x, d.z = math.cos(a) * math.random() * RAIN_RADIUS,
                         math.sin(a) * math.random() * RAIN_RADIUS
              d.y = RAIN_TOP
            end
          else
            d.y = d.y - RAIN_FALL * (storm and 1.35 or 1) * dt
            if d.y <= 1 then d.y, d.splash = 1, 0.10 end
          end
          local sx = d.splash > 0 and 3.5 or 1.6
          local sy = d.splash > 0 and 1.2 or 9
          Voxel3D.draw(partMesh, dropImg,
                       Mat4.mul(Mat4.mul(
                         Mat4.translate(px + d.x, d.y, pz + d.z),
                         Mat4.rotateY(-yaw)), Mat4.scale(sx, sy, 1)))
        end

        -- an umbrella over every NPC, bobbing with their step
        if umbrellaImg and cfg.umbrellas ~= false then
          local me = state.player
          for _, e in ipairs(state.entities or {}) do
            if e ~= me and e.px and e.py then
              local bob = math.sin((e.px + e.py) * 0.2 + t * 6) * 0.6
              Voxel3D.draw(partMesh, umbrellaImg,
                           Mat4.mul(Mat4.mul(
                             Mat4.translate(e.px + 8, UMBRELLA_H + bob,
                                            e.py + 8),
                             Mat4.rotateY(-yaw)), Mat4.scale(15, 15, 1)))
            end
          end
        end
        love.graphics.setDepthMode("lequal", true)
      end)
      rainNote = ", raining"
    end
  elseif drops then
    drops = nil
  end
  return rainNote
end

local function drawShafts(map, cfg, px, pz, t, raining)
  -- ---------- sun shafts under the canopy
  local shaftNote = ""
  if cfg.shafts ~= false and isCanopy(map) and not raining then
    shaftMesh = shaftMesh or buildShafts()
    if shaftMesh then
      guarded(function()
        love.graphics.setDepthMode("lequal", false)
        love.graphics.setColor(1, 0.98, 0.82, 0.16)
        -- the wood breathes: the shafts drift on a slow clock
        Voxel3D.draw(shaftMesh, white(),
                     Mat4.mul(Mat4.translate(px, 0, pz),
                              Mat4.rotateY(math.sin(t * 0.05) * 0.12)))
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setDepthMode("lequal", true)
      end)
      shaftNote = ", shafts"
    end
  end
  return shaftNote
end

local function drawFog(map, cfg, px, pz)
  -- ---------- fog on the maps that deserve it
  local fogNote = ""
  local mapId = map.def and (map.def.id or map.def.name)
  if cfg.fog ~= false and mapId and FOG_MAPS[tostring(mapId)] then
    shellMesh = shellMesh or buildShells()
    if shellMesh then
      guarded(function()
        love.graphics.setDepthMode("lequal", false)
        -- the same shells as the cave dark, but pale: distance whitens
        love.graphics.setColor(0.78, 0.76, 0.84, 0.55)
        Voxel3D.draw(shellMesh, white(),
                     Mat4.mul(Mat4.translate(px, 0, pz),
                              Mat4.scale(1.6, 1, 1.6)))
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setDepthMode("lequal", true)
      end)
      fogNote = ", fog"
    end
  end
  return fogNote
end

-- Lamplight: only where it is dark enough to matter -- after dark
-- outdoors, and in unlit caves at any hour.
local function drawLights(map, cfg, px, pz, yaw, t, outdoor, dark)
  if cfg.lights == false then return "" end
  local wantLight = dark or (outdoor and isNight())
  if not wantLight then return "" end
  if not lightCache or lightCache.map ~= map then
    if lightCache and lightCache.built and lightCache.built.mesh then
      pcall(lightCache.built.mesh.release, lightCache.built.mesh)
    end
    local built, n = buildLight(map)
    lightCache = { map = map, built = built, count = n or 0 }
  end
  if not (lightCache.built and lightCache.built.mesh) then return "" end
  local flicker = 0.94 + 0.06 * math.sin(t * 3.1)
  guarded(function()
    love.graphics.setDepthMode("lequal", false)
    -- additive, so lamplight lightens the rock instead of tinting it
    local okB = pcall(love.graphics.setBlendMode, "add")
    love.graphics.setColor(LIGHT_WARM[1] * 0.40 * flicker,
                           LIGHT_WARM[2] * 0.34 * flicker,
                           LIGHT_WARM[3] * 0.20 * flicker, 1.0)
    Voxel3D.draw(lightCache.built.mesh, white(), nil)
    if okB then pcall(love.graphics.setBlendMode, "alpha") end
    -- and the lamps themselves, so the light has a visible source: a
    -- small ROUND mote, not the square pane the windows used to use
    local lampImg = tex and tex.fly
    if partMesh and lampImg then
      for _, srcCell in ipairs(lightCache.built.sources) do
        local lx, lz = srcCell[1] * 16 + 8, srcCell[2] * 16 + 8
        if math.abs(lx - px) < 320 and math.abs(lz - pz) < 320 then
          love.graphics.setColor(1, 1, 1, 0.9 * flicker)
          Voxel3D.draw(partMesh, lampImg,
                       Mat4.mul(Mat4.mul(
                         Mat4.translate(lx, LAMP_HEIGHT, lz),
                         Mat4.rotateY(-yaw)), Mat4.scale(5, 5, 1)))
        end
      end
    end
  end)
  return (", %d lamps"):format(lightCache.count)
end

-- Everything the cave has that a room does not, drawn in one pass.
local function drawCave(map, cfg, px, pz, yaw, t, dt, dark, partMesh)
  if not dark then
    bats, batsAt = nil, nil
    return ""
  end
  local note = ""

  -- ---- still water
  if cfg.pools ~= false then
    if not poolCache or poolCache.map ~= map then
      if poolCache and poolCache.mesh then
        pcall(poolCache.mesh.release, poolCache.mesh)
      end
      local mesh, n = buildPools(map)
      poolCache = { map = map, mesh = mesh, count = n or 0 }
    end
    if poolCache.mesh then
      guarded(function()
        love.graphics.setDepthMode("lequal", false)
        love.graphics.setColor(0.52, 0.66, 0.86, 0.85)
        Voxel3D.draw(poolCache.mesh, white(), nil)
      end)
      note = note .. (", %d pools"):format(poolCache.count)
    end
  end

  -- ---- torches: a flame, and the light it throws on the rock
  if cfg.sconces ~= false and partMesh then
    if not sconceCache or sconceCache.map ~= map then
      sconceCache = { map = map, list = buildSconces(map) }
    end
    local lit = 0
    guarded(function()
      love.graphics.setDepthMode("lequal", false)
      for i, sc in ipairs(sconceCache.list) do
        if math.abs(sc[1] - px) < 240 and math.abs(sc[2] - pz) < 240 then
          -- each flame on its own guttering clock
          local f = 0.78 + 0.22 * math.sin(t * (5 + (i % 4)) + i)
          local sz = 6 + f * 2.5
          love.graphics.setColor(1.0, 0.72 + 0.12 * f, 0.34, 0.92)
          Voxel3D.draw(partMesh, tex and tex.fly or white(),
                       Mat4.mul(Mat4.mul(
                         Mat4.translate(sc[1], SCONCE_Y, sc[2]),
                         Mat4.rotateY(-yaw)), Mat4.scale(sz, sz * 1.5, 1)))
          lit = lit + 1
        end
      end
    end)
    if lit > 0 then note = note .. (", %d torches"):format(lit) end
  end

  -- ---- bats: roosting, then not
  if cfg.bats ~= false and partMesh and loadBatPics() then
    if not bats or batsAt ~= map or (t - (bats.born or 0)) > BAT_LIFE then
      bats = { born = t, list = {} }
      batsAt = map
      for r = 1, BAT_ROOSTS do
        local a = math.random() * math.pi * 2
        local rad = 90 + math.random() * 160
        local rx, rz = px + math.cos(a) * rad, pz + math.sin(a) * rad
        for _ = 1, BAT_PER_ROOST do
          bats.list[#bats.list + 1] = {
            x = rx + (math.random() - 0.5) * 34,
            z = rz + (math.random() - 0.5) * 34,
            y = BAT_Y - math.random() * 3,
            phase = math.random() * 6.28, up = false,
            vx = 0, vy = 0, vz = 0,
          }
        end
      end
    end
    local flying = 0
    guarded(function()
      love.graphics.setDepthMode("lequal", false)
      love.graphics.setColor(1, 1, 1, 1)
      for _, b in ipairs(bats.list) do
        local dx, dz = b.x - px, b.z - pz
        if not b.up and (dx * dx + dz * dz) < BAT_FLUSH * BAT_FLUSH then
          -- one bat waking wakes the roost
          for _, o in ipairs(bats.list) do o.up = true end
        end
        if b.up then
          if b.vy == 0 then
            local ang = math.atan2(b.z - pz, b.x - px)
                        + (math.random() - 0.5) * 1.6
            b.vx = math.cos(ang) * (46 + math.random() * 40)
            b.vz = math.sin(ang) * (46 + math.random() * 40)
            b.vy = -14 - math.random() * 10      -- they drop before they climb
          end
          b.x = b.x + b.vx * dt
          b.z = b.z + b.vz * dt
          b.y = b.y + b.vy * dt
          b.vy = b.vy + 34 * dt                  -- and then climb, hard
          -- an erratic flutter, because bats do not fly in lines
          b.x = b.x + math.sin(t * 9 + b.phase) * 14 * dt
          b.z = b.z + math.cos(t * 8 + b.phase) * 14 * dt
        else
          b.y = BAT_Y - 1.5 + math.sin(t * 1.4 + b.phase) * 0.6
        end
        if b.y > 4 and b.y < 90 then
          flying = flying + 1
          local beat = (t + b.phase) * 9
          local img = ((math.floor(beat) % 2) == 0) and batPics.a or batPics.b
          local size = b.up and 9 or 7
          Voxel3D.draw(partMesh, img,
                       Mat4.mul(Mat4.mul(Mat4.translate(b.x, b.y, b.z),
                                         Mat4.rotateY(-yaw)),
                                Mat4.scale(size, size, 1)))
        end
      end
    end)
    if flying > 0 then
      note = note .. (", %d bats%s"):format(flying,
                       bats.list[1] and bats.list[1].up and " UP" or "")
    end
  end
  return note
end

-- Puddles fill while it rains and dry slowly afterwards; the mesh itself
-- is built once per map and simply faded.
local function drawPuddles(map, cfg, raining, dt, atlasFor, outdoor)
  if cfg.puddles == false then return "" end
  -- Rain does not fall indoors, and neither should puddles lie there.
  -- The ground still dries while you are inside, so stepping out after a
  -- long visit finds the street drying rather than frozen wet.
  if not outdoor then
    wetness = math.max(0, wetness - dt / PUDDLE_DRY)
    return ""
  end
  wetness = math.max(0, math.min(1, wetness
    + (raining and (dt / PUDDLE_FILL) or -(dt / PUDDLE_DRY))))

  -- Built as soon as the map is known rather than at the moment the
  -- puddles first show: constructing a few hundred quads mid-walk is a
  -- hitch you can feel, and it landed exactly when they appeared.
  if not puddleCache or puddleCache.map ~= map then
    if puddleCache and puddleCache.mesh then
      for _, grp in ipairs(puddleCache.mesh) do
        pcall(grp.mesh.release, grp.mesh)
      end
    end
    local mesh, n = buildPuddles(map)
    puddleCache = { map = map, mesh = mesh, count = n or 0 }
  end
  if wetness <= 0.01 then return "" end
  if not puddleCache.mesh then return "" end
  local tx = nil
  if atlasFor then
    local okT, a = pcall(atlasFor, map)
    if okT then tx = a end
  end
  guarded(function()
    love.graphics.setDepthMode("lequal", false)
    for _, grp in ipairs(puddleCache.mesh) do
      -- each group eases in over its own quarter of the filling, so
      -- puddles gather across a street instead of appearing together
      local local_f = (wetness - grp.at) / (1 / PUDDLE_GROUPS)
      local f = math.max(0, math.min(1, local_f))
      if f > 0.01 then
        love.graphics.setColor(0.78, 0.86, 1.0, 0.72 * f)
        Voxel3D.draw(grp.mesh, tx or white(), nil)
      end
    end
  end)
  return (", %d puddles %.0f%%"):format(puddleCache.count, wetness * 100)
end

-- The storm: strikes far apart, a partial and gentle brightening, and
-- everything eased rather than cut.  See the constants above for why.
local function drawStorm(cfg, px, pz, yaw, t, dt, partMesh)
  local note = ""
  if not storm then
    flash = math.max(0, flash - dt / FLASH_FADE)
    bolts = nil
    return note
  end
  if cfg.lightning ~= false then
    boltImgs = boltImgs or makeBolts()
    bolts = bolts or {}
    -- a hard floor between strikes, then a modest chance beyond it
    if boltImgs and (not boltAt or (t - boltAt) > BOLT_GAP_MIN)
       and math.random() < BOLT_CHANCE * dt then
      boltAt = t
      local a = math.random() * math.pi * 2
      bolts[#bolts + 1] = {
        x = px + math.cos(a) * BOLT_DIST,
        z = pz + math.sin(a) * BOLT_DIST,
        img = boltImgs[math.random(#boltImgs)],
        life = BOLT_LIFE,
      }
      -- the brightening is a fraction of a white-out, and eases away
      flash = FLASH_MAX
    end
  end

  if bolts and #bolts > 0 and partMesh then
    guarded(function()
      love.graphics.setDepthMode("lequal", false)
      for i = #bolts, 1, -1 do
        local b = bolts[i]
        b.life = b.life - dt
        if b.life <= 0 then
          table.remove(bolts, i)
        else
          -- a bolt does not simply fade: it flickers down in two steps,
          -- which is what a real strike does and what stops it looking
          -- like a dissolve
          local f = b.life / BOLT_LIFE
          local a = (f > 0.75 and 1) or (f > 0.5 and 0.35)
                 or (f > 0.3 and 0.8) or f
          love.graphics.setColor(1, 1, 1, a)
          Voxel3D.draw(partMesh, b.img,
                       Mat4.mul(Mat4.mul(Mat4.translate(b.x, BOLT_Y, b.z),
                                         Mat4.rotateY(-yaw)),
                                Mat4.scale(190, 380, 1)))
          note = ", BOLT"
        end
      end
    end)
  end

  flash = math.max(0, flash - dt / FLASH_FADE)
  if flash > 0.001 and cfg.lightning ~= false then
    guarded(function()
      -- painted at the horizon rather than over the whole view: the sky
      -- lightens, the ground does not glare
      love.graphics.setDepthMode("lequal", false)
      love.graphics.setColor(1, 1, 1, flash)
      Voxel3D.draw(partMesh, white(), Mat4.mul(
        Mat4.mul(Mat4.translate(px, 260, pz), Mat4.rotateY(-yaw)),
        Mat4.scale(2400, 900, 1)))
    end)
  end
  return note .. (storm and ", STORM" or "")
end

-- Where the strands hang, worked out once per wood: under cells the
-- canopy actually covers, at the canopy's own height.
local function seedVines(map)
  local wc, hc = map.widthCells or 0, map.heightCells or 0
  local out = {}
  for cy = -CANOPY_RING, hc - 1 + CANOPY_RING do
    for cx = -CANOPY_RING, wc - 1 + CANOPY_RING do
      if math.floor(hash01(cx, cy, 191) * VINE_EVERY) == 0 then
        local hang = CANOPY_LOW + hash01(cx, cy, 193)
                     * (CANOPY_HIGH - CANOPY_LOW)
        out[#out + 1] = {
          x = cx * 16 + 3 + hash01(cx, cy, 197) * 10,
          z = cy * 16 + 3 + hash01(cy, cx, 199) * 10,
          y = hang - 1,
          len = VINE_MIN + hash01(cx, cy, 211) * (VINE_MAX - VINE_MIN),
          ang = hash01(cx, cy, 223) * math.pi,
          phase = hash01(cy, cx, 227) * 6.28,
          rate = 0.6 + hash01(cx, cy, 229) * 0.7,
          ox = 0, oz = 0, vx = 0, vz = 0,   -- brush state
        }
      end
    end
  end
  return out
end

-- The strands themselves: idle sway for all of them, a shove for any the
-- player walks through, and a spring back afterwards.
local function drawVines(map, cfg, px, pz, t, dt, sealed, moved)
  if cfg.vines == false or not sealed then return "" end
  if not isCanopy(map) then return "" end
  vineImg = vineImg or makeVine()
  vineMesh = vineMesh or makeVineMesh()
  if not (vineImg and vineMesh) then return "" end
  if not vines or vines.map ~= map then
    vines = seedVines(map)
    vines.map = map
  end

  local shown = 0
  guarded(function()
    love.graphics.setDepthMode("lequal", true)
    for _, v in ipairs(vines) do
      local dx, dz = v.x - px, v.z - pz
      local d2 = dx * dx + dz * dz
      if d2 < VINE_VIEW * VINE_VIEW then
        -- brushed: shoved away from the player, harder the faster you go
        if d2 < BRUSH_R * BRUSH_R and moved > 0.2 then
          local d = math.max(1, math.sqrt(d2))
          local push = BRUSH_PUSH * math.min(3, moved)
          v.vx = v.vx + (dx / d) * push
          v.vz = v.vz + (dz / d) * push
        end
        -- a damped spring back to hanging straight
        v.vx = v.vx + (-SPRING * v.ox - DAMP * v.vx) * dt
        v.vz = v.vz + (-SPRING * v.oz - DAMP * v.vz) * dt
        v.ox = v.ox + v.vx * dt
        v.oz = v.oz + v.vz * dt
        -- idle sway on top, each strand on its own clock
        local sway = math.sin(t * v.rate + v.phase) * VINE_SWAY
        -- the mesh hangs from 0 down to -1, so a shear displaces the free
        -- end and leaves the anchor where the canopy holds it
        local kx = sway + v.ox * BRUSH_LEAN
        local kz = sway * 0.6 + v.oz * BRUSH_LEAN
        local model = Mat4.mul(
          Mat4.mul(Mat4.translate(v.x, v.y, v.z), shear(-kx, -kz)),
          Mat4.mul(Mat4.rotateY(v.ang), Mat4.scale(VINE_W, v.len, 1)))
        Voxel3D.draw(vineMesh, vineImg, model)
        shown = shown + 1
      end
    end
  end)
  return (", %d vines"):format(shown)
end

-- Lifted out of Flora.draw, which sits at LuaJIT's 60-upvalue ceiling.
local function drawTufts(map, cfg, atlasFor, t, outdoor)
  -- ---------- tufts
  local tuftNote = "no tufts"
  local perCell = BLADES[cfg.grass or "SUBTLE"] or 2
  if perCell > 0 and outdoor then
    local key = tostring(perCell)
    if not tuftCache or tuftCache.map ~= map or tuftCache.key ~= key then
      if tuftCache and tuftCache.mesh then
        pcall(tuftCache.mesh.release, tuftCache.mesh)
      end
      local mesh, note = buildTufts(map, perCell)
      tuftCache = { map = map, key = key, mesh = mesh, note = note }
    end
    if tuftCache.mesh then
      local tx = nil
      if atlasFor then
        local okT, a = pcall(atlasFor, map)
        if okT then tx = a end
      end
      local amp = WIND[cfg.wind or "BREEZE"] or 0
      guarded(function()
        for _, part in ipairs(tuftCache.mesh) do
          local model = nil
          if amp > 0 then
            -- a gust is a slow wave plus a faster flutter, so the grass
            -- never settles into an obvious sine
            local w = math.sin(t * WIND_RATE + part.phase) * 0.75
                    + math.sin(t * WIND_RATE * 2.7 + part.phase * 1.9) * 0.25
            local k = amp * w
            model = shear(math.cos(WIND_DIR) * k, math.sin(WIND_DIR) * k)
          end
          Voxel3D.draw(part.mesh, tx, model)
        end
      end)
      tuftNote = tuftCache.note .. (amp > 0 and ", wind" or "")
    else
      tuftNote = tuftCache.note or "no tufts"
    end
  end

  if not featureCache or featureCache.map ~= map then
    local ok, f = pcall(scanFeatures, map)
    featureCache = ok and f or { chimneys = {}, shores = {}, grass = {} }
    featureCache.map = map
  end
  return tuftNote
end

-- Particles were the last big block left inside Flora.draw; lifting it
-- out keeps that function under LuaJIT's 60-upvalue ceiling as features
-- accumulate.
local function drawParticles(state, map, cfg, px, pz, yaw, t, dt, outdoor)
  local live = 0
  if cfg.particles ~= false then
    tex = tex or makeTex()
    partMesh = partMesh or makeQuad()
    if tex and partMesh then
      -- emit: seeds while moving through grass
      local moved = movedThisFrame or 0
      local onGrass = false
      if outdoor then
        local cx, cy = math.floor(px / 16), math.floor(pz / 16)
        local okG, g = pcall(function() return map:isGrassCell(cx, cy) end)
        onGrass = okG and g or false
      end
      if onGrass and moved > 0.2 and tex.seed then
        local n = SEED_RATE * dt
        while n > 0 do
          if n < 1 and math.random() > n then break end
          local a = math.random() * math.pi * 2
          spawn("seed", px + (math.random() - 0.5) * 14, 4 + math.random() * 8,
                pz + (math.random() - 0.5) * 14,
                math.cos(a) * 6, 10 + math.random() * 14, math.sin(a) * 6,
                0.5 + math.random() * 0.4, 1.6 + math.random())
          n = n - 1
        end
      end
      -- drips in caves
      local tid = map.def and map.def.tileset
                  or (map.tileset and map.tileset.id)
      if tid == "CAVERN" and tex.drip and math.random() < DRIP_RATE * dt then
        spawn("drip", px + (math.random() - 0.5) * 150, 30,
              pz + (math.random() - 0.5) * 150, 0, -46, 0, 1.6, 2.2)
      end
      -- fireflies after dark
      if outdoor and isNight() and tex.fly then
        local flies = 0
        for i = 1, POOL do
          local q = parts and parts[i]
          if q and q.life > 0 and q.kind == "fly" then flies = flies + 1 end
        end
        if flies < FLY_TARGET and math.random() < 4 * dt then
          local a = math.random() * math.pi * 2
          local r = 40 + math.random() * 110
          spawn("fly", px + math.cos(a) * r, 6 + math.random() * 14,
                pz + math.sin(a) * r, 0, 0, 0, 4 + math.random() * 4, 1.8)
        end
      end

      -- leaves under the canopy: spawned high, ahead and around
      if isCanopy(map) and tex.leaf and math.random() < LEAF_RATE * dt then
        local a = math.random() * math.pi * 2
        local r = math.random() * 130
        spawn("leaf", px + math.cos(a) * r, 34 + math.random() * 20,
              pz + math.sin(a) * r,
              (math.random() - 0.5) * 8, -7 - math.random() * 5,
              (math.random() - 0.5) * 8, 5.5, 2.6)
      end

      -- dust turning in interior air: kept topped up rather than emitted
      if not outdoor and tex.dust then
        local motes = 0
        for i = 1, POOL do
          local q = parts and parts[i]
          if q and q.life > 0 and q.kind == "dust" then motes = motes + 1 end
        end
        if motes < DUST_TARGET and math.random() < 6 * dt then
          local a = math.random() * math.pi * 2
          local r = 10 + math.random() * 70
          spawn("dust", px + math.cos(a) * r, 4 + math.random() * 22,
                pz + math.sin(a) * r, 0, 1.2, 0,
                6 + math.random() * 5, 1.1)
        end
      end

      -- spray at the water's edge: from the nearest shoreline cells
      local shores = featureCache and featureCache.shores or {}
      if #shores > 0 and tex.foam and math.random() < FOAM_RATE * dt then
        local pick = shores[math.random(#shores)]
        local sx, sz = pick[1] * 16 + 8, pick[2] * 16 + 8
        if math.abs(sx - px) < 190 and math.abs(sz - pz) < 190 then
          spawn("foam", sx + (math.random() - 0.5) * 14, 2,
                sz + (math.random() - 0.5) * 14,
                (math.random() - 0.5) * 5, 12 + math.random() * 10,
                (math.random() - 0.5) * 5, 0.75, 2.0)
        end
      end

      -- chimney smoke: one plume per building, thinning as it climbs
      local chimneys = featureCache and featureCache.chimneys or {}
      if #chimneys > 0 and tex.smoke then
        for _, c in ipairs(chimneys) do
          local sx, sz = c[1] * 16 + 8, c[2] * 16 + 8
          if math.abs(sx - px) < 260 and math.abs(sz - pz) < 260
             and math.random() < SMOKE_RATE * dt then
            spawn("smoke", sx + (math.random() - 0.5) * 4, 26,
                  sz + (math.random() - 0.5) * 4,
                  (math.random() - 0.5) * 3, 9 + math.random() * 4,
                  (math.random() - 0.5) * 3, 2.6, 2.4)
          end
        end
      end

      -- the rustle: a distant tuft shudders, with nothing in it
      local grass = featureCache and featureCache.grass or {}
      if outdoor and #grass > 0 and tex.seed
         and math.random() < RUSTLE_CHANCE * dt then
        local pick = grass[math.random(#grass)]
        local gx, gz = pick[1] * 16 + 8, pick[2] * 16 + 8
        local d = math.abs(gx - px) + math.abs(gz - pz)
        if d > 40 and d < 260 then
          for _ = 1, 5 do
            local a = math.random() * math.pi * 2
            spawn("seed", gx + (math.random() - 0.5) * 10, 5,
                  gz + (math.random() - 0.5) * 10,
                  math.cos(a) * 9, 16 + math.random() * 10, math.sin(a) * 9,
                  0.55, 1.7)
          end
        end
      end

      -- Footfall in the wet: walking through rain kicks a little water
      -- up off the ground, harder once the puddles have filled.  It is
      -- the small thing that ties the weather to you rather than to the
      -- scenery.
      if raining and tex.foam then
        local moved2 = movedThisFrame or 0
        if moved2 > 0.2 and math.random() < (10 + 14 * wetness) * dt then
          local a = math.random() * math.pi * 2
          spawn("foam", px + (math.random() - 0.5) * 7, 1,
                pz + (math.random() - 0.5) * 7,
                math.cos(a) * (7 + math.random() * 9),
                14 + math.random() * 12,
                math.sin(a) * (7 + math.random() * 9),
                0.36, 1.3 + math.random() * 0.7)
        end
      end

      -- Gnats: a swarm is a COLUMN of air that insects orbit, not a
      -- scatter of independent motes -- which is what makes a cloud of
      -- them read as one thing hanging over a patch of grass.  Over
      -- grass by day; under the canopy at any hour, where the light is
      -- doing something anyway.
      if cfg.insects ~= false and tex.fly
         and (isCanopy(map) or (outdoor and not isNight())) then
        local grassCells = featureCache and featureCache.grass or {}
        if not swarms or #swarms == 0 or math.random() < 0.15 * dt then
          swarms = {}
          for i = 1, SWARMS do
            local hx, hz
            if #grassCells > 0 then
              local pick = grassCells[math.random(#grassCells)]
              hx, hz = pick[1] * 16 + 8, pick[2] * 16 + 8
            else
              local a = math.random() * math.pi * 2
              local r = 40 + math.random() * SWARM_RANGE
              hx, hz = px + math.cos(a) * r, pz + math.sin(a) * r
            end
            swarms[i] = { x = hx, z = hz,
                          y = isCanopy(map) and (26 + math.random() * 16)
                              or (10 + math.random() * 10),
                          r = 5 + math.random() * 6 }
          end
        end
        for si, sw in ipairs(swarms) do
          if math.abs(sw.x - px) < 260 and math.abs(sw.z - pz) < 260 then
            local living = 0
            for i = 1, POOL do
              local q = parts and parts[i]
              if q and q.life > 0 and q.kind == "gnat" and q.swarm == si then
                living = living + 1
              end
            end
            if living < GNATS_PER_SWARM and math.random() < 8 * dt then
              local q = spawn("gnat", sw.x, sw.y, sw.z, 0, 0, 0,
                              3 + math.random() * 4, 0.9)
              if q then
                q.swarm = si
                q.phase = math.random() * 6.28
                q.orbit = sw.r * (0.4 + math.random() * 0.8)
                q.rate = 1.6 + math.random() * 2.4
              end
            end
          end
        end
      end

      -- integrate and draw
      guarded(function()
        love.graphics.setDepthMode("lequal", false)
        for i = 1, POOL do
          local q = parts and parts[i]
          if q and q.life > 0 then
            q.life = q.life - dt
            if q.kind == "seed" then
              q.vy = q.vy - 34 * dt
              q.x = q.x + q.vx * dt
              q.y = q.y + q.vy * dt
              q.z = q.z + q.vz * dt
              if q.y < 1 then q.y, q.vy = 1, 0 end
            elseif q.kind == "drip" then
              q.vy = q.vy - 40 * dt
              q.y = q.y + q.vy * dt
              if q.y <= 1 then
                -- the splash: a brief flat flare, then gone
                q.y, q.vy, q.life = 1, 0, math.min(q.life, 0.12)
                q.size = 3.2
              end
            elseif q.kind == "leaf" then
              -- tumbling fall: sideways drift reverses on its own clock
              local ph = i * 0.9
              q.x = q.x + (q.vx + math.sin(t * 1.4 + ph) * 9) * dt
              q.z = q.z + (q.vz + math.cos(t * 1.1 + ph) * 9) * dt
              q.y = q.y + q.vy * dt
              if q.y < 1 then q.life = 0 end
            elseif q.kind == "gnat" then
              -- a tight, fast orbit of its swarm column, on its own clock
              local sw = swarms and swarms[q.swarm or 0]
              if sw then
                local a = t * (q.rate or 2) + (q.phase or 0)
                q.x = sw.x + math.cos(a) * (q.orbit or 4)
                q.z = sw.z + math.sin(a * 1.3) * (q.orbit or 4)
                q.y = sw.y + math.sin(a * 2.1) * 3
              else
                q.life = 0
              end
            elseif q.kind == "dust" then
              local ph = i * 2.3
              q.x = q.x + math.sin(t * 0.35 + ph) * 3 * dt
              q.z = q.z + math.cos(t * 0.28 + ph) * 3 * dt
              q.y = q.y + q.vy * dt * 0.4
            elseif q.kind == "foam" then
              q.vy = q.vy - 40 * dt
              q.x = q.x + q.vx * dt
              q.y = q.y + q.vy * dt
              q.z = q.z + q.vz * dt
              if q.y < 1 then q.life = 0 end
            elseif q.kind == "smoke" then
              -- rises, slows, and spreads as it goes
              q.vy = q.vy * (1 - 0.5 * dt)
              q.x = q.x + q.vx * dt
              q.y = q.y + q.vy * dt
              q.z = q.z + q.vz * dt
              q.size = q.size + 2.2 * dt
            else -- fly: a slow bob on its own clock
              local ph = i * 1.7
              q.x = q.x + math.sin(t * 0.7 + ph) * 8 * dt
              q.z = q.z + math.cos(t * 0.5 + ph) * 8 * dt
              q.y = q.y + math.sin(t * 1.9 + ph) * 5 * dt
            end
            if q.life > 0 then
              live = live + 1
              local fade = math.min(1, q.life / (q.max * 0.5))
              local s = q.size * (0.6 + 0.4 * fade)
              -- fireflies pulse; the others simply shrink as they die
              if q.kind == "fly" then
                s = q.size * (0.7 + 0.5 * math.abs(math.sin(t * 3 + i)))
              elseif q.kind == "smoke" or q.kind == "dust" then
                s = q.size    -- these thin out by growing, not by shrinking
              end
              local img = tex[q.kind] or (q.kind == "gnat" and tex.fly)
                       or tex.seed
              Voxel3D.draw(partMesh, img,
                           Mat4.mul(Mat4.mul(Mat4.translate(q.x, q.y, q.z),
                                             Mat4.rotateY(-yaw)),
                                    Mat4.scale(s, s, 1)))
            end
          end
        end
        love.graphics.setDepthMode("lequal", true)
      end)
    end
  end

  -- ---------- the weather clock: dry spells broken by showers
  local rainMode = cfg.rain or "SOMETIMES"
  local wantRain = false
  if rainMode == "ALWAYS" then
    wantRain = true
  elseif rainMode ~= "OFF" then
    if not dryUntil and not rainUntil then
      dryUntil = t + DRY_MIN + math.random() * (DRY_MAX - DRY_MIN)
    end
    if rainUntil then
      if t > rainUntil then
        rainUntil = nil
        dryUntil = t + DRY_MIN + math.random() * (DRY_MAX - DRY_MIN)
      else
        wantRain = true
      end
    elseif dryUntil and t > dryUntil then
      dryUntil = nil
      rainUntil = t + WET_MIN + math.random() * (WET_MAX - WET_MIN)
      wantRain = true
      -- a shower occasionally arrives as something bigger
      storm = math.random() < STORM_ODDS
    end
  end
  if rainMode == "ALWAYS" and not rainUntil then storm = storm end
  if not wantRain then storm = false end
  raining = wantRain and outdoor
  -- Published for the sky layer: a rainbow belongs to the moment a
  -- shower ENDS, and the weather clock lives here.
  local was = rawget(_G, "__ds_weather") or {}
  _G.__ds_weather = {
    raining = raining,
    storm = raining and storm or false,
    wetness = wetness,
    stoppedAt = (was.raining and not raining) and t or was.stoppedAt,
  }
  local rainNote = ""

  return live
end

-- ------- the draw
-- If the companion mod has been deleted, its config bridge is gone and
-- this module is an orphan: draw nothing. The ceiling module does the
-- actual clean-up; this just keeps quiet in the meantime.
local function abandoned()
  return rawget(_G, "__ds_ceiling_config") == nil
end

function Flora.draw(state, atlasFor)
  if abandoned() then return end
  local cfg = config()
  local map = state and state.map
  if not map then return end
  local p = state.player
  local px = (p and p.px or 0) + 8
  local pz = (p and p.py or 0) + 8
  local t = now()
  local dt = lastT and math.min(0.1, t - lastT) or 0
  lastT = t
  local outdoor = isOutdoor(map)
  local yaw = (FirstPerson and FirstPerson.yaw) or 0

  -- Are we in the world at eye level -- inside the head, or on the boom
  -- just behind it?  Vines want that view and no other: from the diorama
  -- you would be looking down at the tops of them.
  -- How far the player moved this frame.  This used to be worked out
  -- inside the particle pass, which meant that turning PARTICLES off
  -- silently stopped the vines noticing anyone walking through them.
  local movedNow = wasX and (math.abs(px - wasX) + math.abs(pz - wasZ)) or 0
  movedThisFrame = movedNow
  wasX, wasZ = px, pz

  local okBlend, headBlend = pcall(FirstPerson.blendEased)
  headBlend = (okBlend and headBlend) or 0
  local canopySealed = headBlend > CANOPY_GATE

  local tuftNote = drawTufts(map, cfg, atlasFor, t, outdoor)

  -- ---------- the forest canopy
  local canopyNote = ""
  if cfg.canopy ~= false and isCanopy(map) then
    -- the same gate the interior ceiling uses: whole roof inside the
    -- head, opened up for the diorama so the wood can be seen into
    local okB, blend = pcall(FirstPerson.blendEased)
    blend = (okB and blend) or 0
    -- the same three cases the interior ceiling answers: inside the
    -- head, boomed out in 3RD, or the diorama
    local mode
    if blend > CANOPY_GATE and not boomedOut() then
      mode = "fp"
    elseif blend > CANOPY_GATE then
      local want = cfg.third or "CUTAWAY"
      if want == "FULL" then mode = "fp"
      elseif want == "CUTAWAY" then mode = "cutaway"
      else
        canopyNote = ", canopy off in 3RD"
        mode = nil
      end
    else
      mode = "cutaway"
    end
    local pcx, pcy
    if mode == nil then
      -- 3RD with the canopy switched off: no leaves at all
      if canopyCache and canopyCache.mesh then
        pcall(canopyCache.mesh.release, canopyCache.mesh)
      end
      canopyCache = nil
    end
    if mode == "cutaway" then
      pcx = math.floor(px / 16)
      pcy = math.floor(pz / 16)
    end
    local ckey = table.concat({ mode or "off", pcx or "-", pcy or "-" }, ":")
    if mode and (not canopyCache or canopyCache.map ~= map
                 or canopyCache.key ~= ckey) then
      if canopyCache and canopyCache.mesh then
        pcall(canopyCache.mesh.release, canopyCache.mesh)
      end
      local tx0 = nil
      if atlasFor then
        local okA, a = pcall(atlasFor, map)
        if okA then tx0 = a end
      end
      local mesh, vines, note = buildCanopy(map, tx0, mode, pcx, pcy)
      canopyCache = { map = map, key = ckey, mesh = mesh, note = note,
                      vines = vines }
    end
    if canopyCache and canopyCache.mesh then
      local tx = nil
      if atlasFor then
        local okT, a = pcall(atlasFor, map)
        if okT then tx = a end
      end
      guarded(function()
        Voxel3D.draw(canopyCache.mesh, tx, nil)

        -- the strands: each block swings on its own, and remembers being
        -- walked through for a couple of seconds
        if cfg.vines ~= false and canopyCache.vines then
          local pcx2 = math.floor(px / 16)
          local pcy2 = math.floor(pz / 16)
          local hereKey = math.floor(pcx2 / VINE_BLOCK) .. ":"
                          .. math.floor(pcy2 / VINE_BLOCK)
          if movedThisFrame > 0.2 then
            vineHits[hereKey] = { x = px, z = pz, at = t }
          end
          for _, blk in ipairs(canopyCache.vines) do
            -- idle: a slow wave, offset per block
            local w = math.sin(t * 0.62 + blk.phase) * 0.7
                    + math.sin(t * 1.31 + blk.phase * 2.1) * 0.3
            local kx = math.cos(WIND_DIR) * VINE_SWAY * w
            local kz = math.sin(WIND_DIR) * VINE_SWAY * w
            -- brushed: thrown away from where you pushed through, easing
            -- back over a second or two
            local hit = vineHits[blk.key]
            if hit then
              local age = t - hit.at
              if age > VINE_SETTLE then
                vineHits[blk.key] = nil
              else
                local f = 1 - age / VINE_SETTLE
                -- a swing back and forth as it settles, not a slump
                local swing = f * f * math.cos(age * 7.5)
                -- away from the point you pushed through
                local ang = math.atan2(pz - hit.z, px - hit.x)
                if math.abs(px - hit.x) < 0.01
                   and math.abs(pz - hit.z) < 0.01 then
                  ang = WIND_DIR
                end
                kx = kx + math.cos(ang) * VINE_PUSH * swing
                kz = kz + math.sin(ang) * VINE_PUSH * swing
              end
            end
            Voxel3D.draw(blk.mesh, tx, bend(kx, kz, blk.top))
          end
        end
      end)
      canopyNote = ", " .. tostring(canopyCache.note)
      if cfg.vines ~= false and canopyCache.vines then
        canopyNote = canopyNote
                     .. (", %d vine blocks"):format(#canopyCache.vines)
      end
    end
  end

  local live = drawParticles(state, map, cfg, px, pz, yaw, t, dt, outdoor)
  local rainNote = drawRain(state, cfg, px, pz, yaw, t, dt, raining)
  local puddleNote = drawPuddles(map, cfg, raining, dt, atlasFor, outdoor)
  local stormNote = drawStorm(cfg, px, pz, yaw, t, dt,
                              partMesh or makeQuad())
  -- ---------- the same features, on the maps either side of you
  local nbNote = ""
  if outdoor and state.neighbors then
    MOUND.seen = {}
    local drawnNb = 0
    for _, nb in ipairs(state.neighbors) do
      if nb.map then MOUND.seen[nb.map] = true end
    end
    guarded(function()
      for _, nb in ipairs(state.neighbors) do
        local nmap, ox, oy = nb.map, nb.ox or 0, nb.oy or 0
        if nmap then
          local model = Mat4.translate(ox, 0, oy)
          -- how far the middle of that map is from you, for the haze
          local mx = ox + (nmap.widthCells or 0) * 8
          local mz = oy + (nmap.heightCells or 0) * 8
          local d = math.sqrt((mx - px) ^ 2 + (mz - pz) ^ 2)
          local hr, hg, hb = MOUND.haze(d)
          local tx = nil
          if atlasFor then
            local okA, a = pcall(atlasFor, nmap)
            if okA then tx = a end
          end

          -- grass
          local gkey = cfg.grass or "SUBTLE"
          local per = BLADES[gkey] or 2
          if per and per > 0 then
            local slot = MOUND.tufts[nmap]
            if not slot or slot.key ~= gkey then
              if slot and slot.mesh then
                for _, part in ipairs(slot.mesh) do
                  pcall(part.mesh.release, part.mesh)
                end
              end
              local mesh = buildTufts(nmap, per)
              slot = { mesh = mesh, key = gkey }
              MOUND.tufts[nmap] = slot
            end
            if slot.mesh then
              love.graphics.setColor(hr, hg, hb, 1)
              for _, part in ipairs(slot.mesh) do
                Voxel3D.draw(part.mesh, tx, model)
              end
              drawnNb = drawnNb + 1
            end
          end
        end
      end
      love.graphics.setColor(1, 1, 1, 1)
    end)
      MOUND.trim(MOUND.tufts, 8)
    if drawnNb > 0 then
      nbNote = (", %d neighbour draws"):format(drawnNb)
    end
  end

  -- ---------- the backs of buildings, in plain wall
  local backNote = ""
  if outdoor and cfg.backs ~= false then
    local slot = MOUND.BACKS.cache[map]
    if not slot then
      local mesh, n = MOUND.buildBacks(map)
      slot = { mesh = mesh, count = n or 0 }
      MOUND.BACKS.cache[map] = slot
    end
    if slot.mesh then
      local tx4 = nil
      if atlasFor then
        local okA, a = pcall(atlasFor, map)
        if okA then tx4 = a end
      end
      guarded(function()
        Voxel3D.draw(slot.mesh, tx4, nil)
      end)
      backNote = (", %d backs"):format(slot.count)
    end
  end

  local isDark = darkness(map).dark
  local lightNote = drawLights(map, cfg, px, pz, yaw, t, outdoor, isDark)
  local caveNote = drawCave(map, cfg, px, pz, yaw, t, dt, isDark,
                            partMesh or makeQuad())
  local vineNote = drawVines(map, cfg, px, pz, t, dt, canopySealed,
                             movedThisFrame or 0)
  local shaftNote = drawShafts(map, cfg, px, pz, t, raining)
  local fogNote = drawFog(map, cfg, px, pz)


  -- ---------- darkness: last, so it tints everything already drawn
  local darkNote = ""
  if cfg.dark ~= false then
    local d = darkness(map)
    if d.dark then
      shellMesh = shellMesh or buildShells()
      if shellMesh then
        -- Flash does not switch the dark off, it pushes it back: the
        -- shells scale outward, so the cave opens up around you
        local scale = d.flash and FLASH_MULT or 1
        guarded(function()
          love.graphics.setDepthMode("lequal", false)
          Voxel3D.draw(shellMesh, white(),
                       Mat4.mul(Mat4.translate(px, 0, pz),
                                Mat4.scale(scale, 1, scale)))
          love.graphics.setDepthMode("lequal", true)
        end)
        darkNote = d.flash and ", dark (FLASH)" or ", dark"
      end
    end
  end

  local f = featureCache or {}
  status(("%s, %d particles, %d chimneys, %d shore%s%s%s"):format(tuftNote,
         live, #(f.chimneys or {}), #(f.shores or {}),
         isNight() and ", night" or "",
         canopyNote .. rainNote .. puddleNote .. stormNote
           .. backNote .. nbNote .. lightNote .. caveNote .. vineNote
           .. shaftNote .. fogNote,
         darkNote))
end

function Flora.invalidate()
  if tuftCache and tuftCache.mesh then
    for _, part in ipairs(tuftCache.mesh) do
      pcall(part.mesh.release, part.mesh)
    end
  end
  if partMesh then pcall(partMesh.release, partMesh) end
  if shellMesh then pcall(shellMesh.release, shellMesh) end
  if shaftMesh then pcall(shaftMesh.release, shaftMesh) end
  if vineMesh then pcall(vineMesh.release, vineMesh) end
  vineMesh, vines = nil, nil
  swarms = nil
  if puddleCache and puddleCache.mesh then
    for _, grp in ipairs(puddleCache.mesh) do
      pcall(grp.mesh.release, grp.mesh)
    end
  end
  if lightCache and lightCache.built and lightCache.built.mesh then
    pcall(lightCache.built.mesh.release, lightCache.built.mesh)
  end
  lightCache = nil
  if poolCache and poolCache.mesh then
    pcall(poolCache.mesh.release, poolCache.mesh)
  end
  -- batPics too: a reload should look for the derived frames again
  -- rather than remember that they were missing last time
  for _, slot in pairs(MOUND.BACKS.cache) do
    if slot.mesh then pcall(slot.mesh.release, slot.mesh) end
  end
  MOUND.BACKS.cache = {}
  poolCache, sconceCache, bats, batsAt, batPics =
    nil, nil, nil, nil, nil
  puddleCache, bolts, boltAt, flash, wetness = nil, nil, nil, 0, 0
  if canopyCache and canopyCache.mesh then
    pcall(canopyCache.mesh.release, canopyCache.mesh)
  end
  canopyCache = nil
  tuftCache, partMesh, shellMesh, parts = nil, nil, nil, nil
  shaftMesh, drops, rainUntil, dryUntil = nil, nil, nil, nil
  featureCache = nil
end

return Flora
