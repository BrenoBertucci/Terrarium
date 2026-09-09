-- Voxel world mode: the authored forest -- two sets of trees, one row.
--
-- Every round-tree site of a map (Structures.buildCylinders records them)
-- gets one tree stamped from a TTR2 bake, four species mixed by the site's
-- own coordinates, built as one mesh per species per map over a few frames.
-- The TREES row picks WHICH set of bakes (see Trees3D.SETS):
--
--   VOXEL  assets/ground/tree/voxel/ -- blocky trees grown by
--          tools/grow_voxel_tree.py: 2.5 px cubes, a visible bole, lobed
--          crowns with tufts, and NO colour of their own: their leaf faces
--          point at a palette strip this file paints per map with the
--          greens the map's own tree tile got (TerrainAtlas.tileShades).
--   3D     assets/ground/tree/ -- tools/bake_tree.py's finer voxel bake
--          under photo leaf cards, shipping its own colours.
--
-- The carved hull -- the outline-hulled ball cut from the tileset art that
-- was the whole forest before either bake existed -- is no longer a row
-- option. It is the FALLBACK: if the chosen set does not load (a missing
-- bake, an over-budget one, a map past MAX_TREES), available() answers
-- false and Structures/ChunkMesher keep the hulls. This file never throws
-- into the mesh build.
--
-- WHY ONE COMBINED MESH AND NOT ONE DRAW PER TREE
--
-- The obvious shape is StreetLamps': keep one mesh, draw it once per site
-- with a transform. That works for 28 posts. It cannot work for trees,
-- because the thing a tree REPLACES lives in the chunk mesh, which is built
-- when the map loads. Deciding "the nearest 48 get the model, the rest keep
-- the hull" is a per-frame ranking against a per-build decision: the
-- nearest 48 would come out wearing both at once, and rebuilding the chunk
-- mesh as the player walks is not on the table.
--
-- So every site gets the model, the hulls are skipped wholesale, and the
-- cost is paid the way the hulls paid it -- once per map, as one mesh.
-- That is what holds the budget down:
--
--     300 trees x 1800 tris  ->  1,620,000 verts   (froze the grass)
--     300 trees x  200 tris  ->    180,000 verts   (here)
--
-- THE BUILD IS SLICED ACROSS FRAMES, and it had to be.
--
-- The first cut built the whole combined mesh on the first frame the map's
-- trees were drawn. tests/trees_probe.lua measured that on ROUTE_2:
--
--     combined-mesh build: 502.9 ms for 862 trees
--
-- Half a second of frozen game on entering a route. A player does not read
-- that as a forest loading, they read it as the game hanging.
--
-- BuildBudget's pump is not available here -- that coroutine belongs to the
-- chunk builder and this module is called from the DRAW path, where
-- Budget.tick() correctly does nothing. So the slicing is our own: each
-- frame stamps at most SLICE_SITES sites into the pending buffers and
-- returns; the LOVE mesh is created on the frame the last site lands. The
-- forest fades in over a few frames instead of arriving as a stall, and no
-- frame pays more than its slice.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Voxel3D = V.require("Voxel3D")
local ModSetting = V.require("ModSetting")

local Trees3D = {}

-- The TREES options row picks the set:
--   VOXEL  the blocky trees in the map's own palette (default)
--   3D     the finer bake with photo leaf cards
--
-- THE NAMES HAVE BEEN THROUGH THREE ROUNDS, and this is the one that says
-- what each thing IS rather than how it was made. Round one was 3D / VOXEL
-- with VOXEL meaning the carved hull; round two swapped to VOXEL / CLASSIC
-- with VOXEL meaning the card bake, on the argument that the bake was
-- built of voxels -- true of its lattice and false of its look. A player
-- reading VOXEL wants cubes; a player reading 3D wants leaves. So: VOXEL is
-- the set that looks like cubes, 3D is the set that looks like leaves, and
-- the hull is nobody's option.
--
-- ModSetting.indexOf falls back to values[1] for anything it does not
-- recognise, so a save left on round two's "classic" lands on VOXEL (the
-- cubes are what the hull was standing in for), one left on either
-- round's "voxel" lands on VOXEL, and one left on round one's "3d" keeps
-- its 3D. Nobody has to re-pick.
--
-- The set is chosen at chunk-build time -- Structures records sites when
-- available() is true -- so flipping the row has to drop the built meshes
-- (remesh below) or the forest keeps the shape it was built with.
Trees3D.setting = ModSetting.new("trees3d", "TREES",
                                 { "voxel", "3d" },
                                 { "VOXEL", "3D" })

-- Remesh every map when the row flips: hull quads vs recorded sites are
-- chosen at Structures build time (treesAuthored), so a live toggle has to
-- drop the cached chunk meshes AND this module's combined tree meshes.
local function remesh()
  pcall(function()
    V.require("ChunkMesher").invalidate()
  end)
  pcall(function()
    Trees3D.invalidate()
  end)
end

-- OPTIONS row: cycle then rebuild. The manager page writes through
-- mod.options_changed (main.lua), which calls onOptionsChanged for this key.
function Trees3D.setting:row()
  local self_ = self
  return {
    id = ((V.mod and V.mod.id) or "TERRARIUM") .. ":" .. self.key,
    label = self.label,
    value = function() return self_.labels[self_:read()] end,
    step = function(game, dir)
      self_:cycle(game, dir)
      remesh()
      return true
    end,
  }
end

function Trees3D.onOptionsChanged(value)
  Trees3D.setting:sync(value)
  remesh()
end

-- The two sets. Species ship as sibling bakes under the set's directory;
-- each species is its own mesh and its own draw call (the 3D set because
-- each carries its own texture, the VOXEL set for symmetry -- four calls
-- for the whole forest is nothing next to the hulls' one).
--
-- windShare is per set because the number was never about the wind: it is
-- how far a crown may move before it looks detached from its bole, and a
-- blocky crown shows a sliding cube sooner than a photo leaf shows a
-- sliding lobe (see the note at Trees3D.WIND_SHARE).
--
-- palette = true means the set's leaf faces sample the strip this file
-- paints per map (see paletteTexture); the shipped .png is then only the
-- fallback for a map whose palette cannot be read.
Trees3D.SETS = {
  voxel = { dir = "assets/ground/tree/voxel/",
            species = { "round", "tiered", "broad", "tall" },
            windShare = 2.9, palette = true },
  ["3d"] = { dir = "assets/ground/tree/",
             species = { "oak", "pine", "birch", "willow" },
             windShare = 3.4, palette = false },
}

-- The set the row currently names.
function Trees3D.set()
  return Trees3D.SETS[Trees3D.setting:get()] or Trees3D.SETS.voxel
end

-- The ACTIVE set's directory and species list, as fields rather than
-- through set() because the probes read and even overwrite them
-- (tests/trees_probe.lua empties SPECIES to force the hull fallback).
-- applyMode below refreshes them whenever the row's value changes, and
-- leaves them alone otherwise, so a probe's override survives its round.
Trees3D.ASSET_DIR = Trees3D.SETS.voxel.dir
Trees3D.SPECIES = Trees3D.SETS.voxel.species
local appliedMode = nil

local function applyMode()
  local mode = Trees3D.setting:get()
  if mode == appliedMode then return end
  appliedMode = mode
  local set = Trees3D.set()
  Trees3D.ASSET_DIR = set.dir
  Trees3D.SPECIES = set.species
  Trees3D.WIND_SHARE = set.windShare
end

-- Per-tree ceiling, checked against what the bake actually contains. The
-- number is not a preference: this template is stamped on EVERY round-tree
-- site, so its cost is multiplied by the forest. Refusing is the honest
-- answer -- the hulls are the classic path, they are free, and a forest
-- that draws beats one that is correct and does not.
--
-- 450 WAS THE WRONG UNIT, and it refused meshes cheaper than the one it
-- was protecting. What this hardware pays for is the VERTEX stage: the
-- forest is one mesh and every vertex runs the sway branch. The GLB bake it
-- was written for spent 1091 verts on 420 triangles, because a decimator's
-- output shares almost nothing between faces. A greedy-meshed voxel quad is
-- 4 verts and 2 triangles, so the same 1091 verts buy 544 triangles -- and
-- a limit written in triangles reads that as 20% more expensive when it is
-- exactly the same cost.
--
-- 1200 admits the four species in tools/bake_tree.py at its default
-- lattice (RES = 0.6): 640 to 1100 triangles, 1300 to 2100 verts, one
-- lattice for wood and leaves so the crown is lobes rather than crates.
-- Against the shipped GLB that is roughly 1.6x the vertices on the species
-- average; the frame cost of that is measured in tests/treevox_probe.lua
-- (run_treefable.cmd), and the knob that buys it back is --res in the
-- baker, not this number.
Trees3D.MAX_TRIS = 1200

-- Whole-map ceiling. Past this the map keeps its hulls rather than paying
-- a build hitch measured in seconds.
Trees3D.MAX_TREES = 900

-- uv.y above this samples the atlas strip holding the leaf sprite; it must
-- match CARD_STRIP in tools/optimize_tree_glb.py.
Trees3D.CARD_UV_CUT = 0.75

-- Sites stamped per frame.
--
-- CALIBRATED AGAINST A MEASUREMENT, after the first attempt was calibrated
-- against a guess and was wrong by two orders of magnitude. The probe times
-- the synchronous build: 760.8 ms for 862 sites is 0.88 ms PER SITE. At the
-- old value of 100 that is an 88 ms slice -- the half-second stall was not
-- removed, it was cut into a handful of large ones, and "built over 3
-- frames" in the log read like success while three frames dropped.
--
-- RE-MEASURED, and both halves of the old note were wrong in the same
-- direction. tests/trees_probe.lua, ROUTE_2, polling Trees3D.ready:
--
--   synchronous build   1127 ms median for 862 sites = 1.31 ms/site
--   so a 6-site slice   ~7.8 ms, not the ~5 ms claimed
--   slices per frame    2.00, measured -- the scene pass and the sun's
--                       depth pass BOTH went through meshesFor, so both
--                       advanced the build
--
-- A constructing frame was therefore paying ~15.7 ms of stamping against
-- a 16.7 ms budget, while this number read as 7.8. Fixed at the source
-- rather than by halving the constant: the depth pass now consumes the
-- build through builtFor and only the scene pass advances it, so a slice
-- is a slice per frame again and the arithmetic here means what it says.
--
-- What that leaves is honest and still not comfortable: ~7.8 ms of a
-- 16.7 ms frame while a route builds, and ~145 frames of it on ROUTE_2.
-- The fade is real and it is the right shape (a fade reads as loading, a
-- stutter reads as broken), but there is no headroom left in it -- do not
-- raise this without re-running the probe's build timing.
--
-- DROPPED 6 -> 4 WITH THE VOXEL BAKE, THEN PUT BACK, and the round trip is
-- worth keeping because the reason it came back is not the reason it left.
--
-- It dropped because the stamp is a per-vertex loop and the voxel species
-- were heavier than the 1091-vert GLB it was tuned against: the probe
-- measured 2.03 ms/site, so six would have been 12 ms of a 16.7 ms frame.
--
-- It went back to 6 because SHADOW_PROXY changed the arithmetic underneath
-- it. stampRange stamps a site TWICE -- once into the scene mesh and once
-- into the caster -- and the caster went from the card-less solid mesh
-- (~1400 verts) to a 34-vert hull. So the second stamp all but disappeared,
-- and the probe now measures:
--
--     874.2 ms for 862 trees = 1.01 ms/site, so a 6-site slice is 6.1 ms
--
-- That is under the ~7.8 ms the note above settled on, at the top of the
-- measurement's own range (0.80-1.20 ms/site) as well as at its median. So
-- six is not a return to the old risk -- it is strictly safer than the
-- configuration that number was written for, and the forest fades in half
-- again as fast.
Trees3D.SLICE_SITES = 6

-- The sun's depth pass draws the card-less mesh (see solidIndices below).
--
-- This switch exists for ONE reason: so the probe can measure what dropping
-- the cards actually bought, by drawing the full mesh into the depth pass
-- and diffing. "120 of 420 triangles, each paying an alpha discard" is an
-- argument, not a number, and this renderer has a history of arguments that
-- turned out to cost nothing.
--
-- IT IS NOT ONE OF THEM -- but it took two runs to say so, and the first
-- one said the opposite. Measured on ROUTE_2, clear sky, medians of 3x100
-- frames:
--
--   sun pass, card-less   +7.37 ms
--   sun pass, full mesh  +10.94 ms
--   SAVING                +3.57 ms, a third of the pass, against 0.35 ms
--                         of drift on the repeated reading
--
-- Dropping 28.6% of the triangles takes a third off the depth pass, so the
-- alpha `discard` really was most of what it was paying for.
--
-- THE FIRST RUN MEASURED MINUS 1.41 ms AND WAS BELIEVED FOR AN HOUR. Its
-- samples spread 34% and 137% between min and max; this one spreads 2-6%.
-- The difference being measured was inside the noise of the run measuring
-- it, and a median of three samples reported it with a straight face.
-- Deltas from a run whose spread is wider than the effect are not small
-- measurements, they are not measurements -- check the spread column
-- before quoting anything out of this probe.
--
-- (What actually settled the noise: this run was the first with the depth
-- pass no longer advancing the build. Same hardware, same map.)
Trees3D.SHADOW_SOLID_ONLY = true

-- Cast from a measured hull instead of the tree (see buildShadowProxy).
--
-- A switch rather than a decision, for the same reason SHADOW_SOLID_ONLY is
-- one: the claim "the sun does not need the leaves" is an argument until a
-- probe diffs the two passes with it on and off, and this renderer has a
-- history of arguments that turned out to cost nothing. Flip it in
-- tests/treevox_probe.lua and remesh to price it.
Trees3D.SHADOW_PROXY = true

-- Advances a build may go untouched before it is thrown away.
--
-- A slice only ever lands while its map is being DRAWN, so walking off a
-- map mid-build freezes that build exactly where it stood: nothing calls
-- into it again, the half-filled vertex and index buffers stay resident,
-- and the site count it still owes is owed forever. Viridian borders two
-- routes, so crossing it starts three builds and finishes one -- the probe
-- caught the other two still owing 316 sites four minutes later.
--
-- Counted in advances rather than frames because this module is only ever
-- entered from the draw path and has no frame of its own. One frame is an
-- advance for the map underfoot plus one per neighbour, so 64 is a handful
-- of frames -- long enough that a map flickering out of the neighbour list
-- for a frame keeps its progress, short enough that nothing walked away
-- from survives to the next map.
Trees3D.RETIRE_AFTER = 64

local templates = {}   -- dir..name -> template | false
local pending = {}     -- map id -> resumable build state
local textures = {}    -- dir..name -> Image | false
local paletteTex = {}  -- palette key -> Image | false (the VOXEL strip per map)

-- A bake's cache key: its set's directory plus its name, so "round" of the
-- VOXEL set and a future "round" of another never collide, and flipping
-- the row finds the other set's templates still decoded.
local function cacheKey(name)
  return Trees3D.ASSET_DIR .. name
end

local function template(name)
  return templates[cacheKey(name)]
end
local meshes = {}      -- map id -> { {mesh=, tex=}, ... } | false
local builtSites = {}  -- map id -> site count, for ready()'s progress
local advances = 0     -- monotonic count of build advances, for retiring

local function assetPath(name)
  local base = tostring((V and V.path) or ""):gsub("\\", "/")
  local dir = Trees3D.ASSET_DIR:gsub("\\", "/")
  if base == "" then return dir .. name end
  if base:sub(-1) == "/" then return base .. dir .. name end
  return base .. "/" .. dir .. name
end

local function candidatePaths(name)
  local abs = assetPath(name)
  return { Trees3D.ASSET_DIR .. name, abs, abs:gsub("/", "\\") }
end

local function f32(s, o)
  local b1, b2, b3, b4 = s:byte(o + 1, o + 4)
  if not b4 then return 0 end
  local u = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
  local sign = 1
  if u >= 0x80000000 then sign = -1; u = u - 0x80000000 end
  local exp = math.floor(u / 0x800000) % 0x100
  local mant = u % 0x800000
  local ldexp = math.ldexp or function(x, e) return x * 2 ^ e end
  if exp == 0 then
    if mant == 0 then return sign * 0.0 end
    return sign * ldexp(mant / 0x800000, -126)
  elseif exp == 255 then
    if mant == 0 then return sign * (1 / 0) end
    return 0 / 0
  end
  return sign * ldexp(1 + mant / 0x800000, exp - 127)
end

local function u16(s, o)
  local b1, b2 = s:byte(o + 1, o + 2)
  if not b2 then return 0 end
  return b1 + b2 * 256
end

local function u32(s, o)
  local b1, b2, b3, b4 = s:byte(o + 1, o + 4)
  if not b4 then return 0 end
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

-- Read a shipped asset. THE love.filesystem BLOCK IS INSIDE ONE pcall.
-- This engine does not merely omit love.filesystem for mods -- it installs
-- a proxy that RAISES ON FIELD ACCESS, so naming `love.filesystem.read` in
-- a guard throws outside every pcall and takes the fallbacks with it. That
-- is what kept StreetLamps' authored post from ever loading; see the note
-- on readBinary there and the longer one in Grass3D.
local function readBinary(name)
  for _, path in ipairs(candidatePaths(name)) do
    if V and V.mod and V.mod.read then
      local ok, data = pcall(V.mod.read, V.mod, path)
      if ok and type(data) == "string" and #data > 32 then return data end
    end
    do
      local ok, data = pcall(function()
        local lf = love and rawget(love, "filesystem")
        if not (lf and lf.read) then return nil end
        local d = lf.read(path)
        if type(d) == "string" and #d > 32 then return d end
        return nil
      end)
      if ok and type(data) == "string" and #data > 32 then return data end
    end
    local okA, Assets = pcall(require, "src.render.Assets")
    if okA and Assets and Assets.read then
      local ok, data = pcall(Assets.read, path)
      if ok and type(data) == "string" and #data > 32 then return data end
    end
    if io and io.open then
      local f = io.open(path, "rb")
      if f then
        local data = f:read("*a")
        f:close()
        if type(data) == "string" and #data > 32 then return data end
      end
    end
  end
  return nil
end

local function loadTexture(name)
  local key = cacheKey(name)
  if textures[key] ~= nil then return textures[key] or nil end
  local file = name .. ".png"
  local okA, Assets = pcall(require, "src.render.Assets")
  for _, path in ipairs(candidatePaths(file)) do
    if okA and Assets and Assets.image then
      local okE, exists = pcall(Assets.exists, path)
      if okE and exists then
        local ok, img = pcall(Assets.image, path)
        if ok and img then
          pcall(img.setFilter, img, "nearest", "nearest")
          textures[key] = img
          return img
        end
      end
    end
    if love and love.graphics and love.graphics.newImage then
      local ok, img = pcall(love.graphics.newImage, path)
      if ok and img then
        pcall(img.setFilter, img, "nearest", "nearest")
        textures[key] = img
        return img
      end
    end
  end
  textures[key] = false
  return nil
end

-- ------- THE VOXEL SET'S COLOURS, painted per map
--
-- A VOXEL bake ships no greens. Its leaf faces all point into row 0 of a
-- 64x64 strip of 8x8 slots -- six leaf tones -- and its bark faces into
-- row 1 -- four fixed browns (Gen 1 draws no trunk, so there is no brown
-- to learn). tools/grow_voxel_tree.py writes the mesh against this layout
-- and it MUST NOT DRIFT: the uv of every leaf face is the centre of its
-- slot, so a slot moved here paints the crown with whatever moved into it.
--
-- Row 0 is painted from what the map's palette made of its own tree tile
-- (TerrainAtlas.tileShades): the tile's light shade is `lit`, its dark is
-- `dark`, and the rest are mixes -- `hi` leans the light shade toward the
-- tile's white rather than using the white itself, because that white is
-- the pale ground the sprite is drawn against and a crown wearing it reads
-- as snow (the offline preview did). One strip per distinct palette, so a
-- whole region shares one texture and a map with a palette of its own
-- (the forest) gets its own.
Trees3D.VOXEL_PALETTE = {
  tex = 64, tile = 8,
  bark = { { 74, 48, 28 }, { 104, 70, 40 }, { 134, 94, 54 }, { 60, 40, 24 } },
}

-- What the last finished build painted with, for the probe: the palette
-- key, or "shipped" when the map's colours could not be read.
Trees3D.lastPaint = nil

-- The tiles the map's tree is drawn with, off the same profile Structures
-- carves the hull from: the 2x2 group's anchor first, then the per-cell
-- round tiles. Shades missing from one are filled from the next.
local function treeTiles(map)
  local okP, prof = pcall(V.data, "voxel_heights")
  local entry = okP and type(prof) == "table" and prof.tilesets
                and map and map.tileset and prof.tilesets[map.tileset.id]
  if type(entry) ~= "table" then return nil end
  local list = {}
  for _, t in ipairs(entry.canopy or {}) do list[#list + 1] = t end
  for _, t in ipairs(entry.cylinder or {}) do list[#list + 1] = t end
  return #list > 0 and list or nil
end

local function paletteTexture(name, map)
  local shades, why = nil, "no-tiles"
  local ok, err = pcall(function()
    local tiles = treeTiles(map)
    if tiles then
      shades, why = V.require("TerrainAtlas").tileShades(map, tiles)
    end
  end)
  if not ok then why = "threw: " .. tostring(err) end
  if not shades then
    Trees3D.lastPaint = "shipped (" .. tostring(why) .. ")"
    return loadTexture(name)
  end

  local function mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t,
             a[3] + (b[3] - a[3]) * t }
  end
  local light = shades[2] or shades[3] or shades[1]
  local dark = shades[3] or light
  local white = shades[1] or light
  local black = shades[4] or dark
  if not light then
    Trees3D.lastPaint = "shipped"
    return loadTexture(name)
  end
  local tones = {
    mix(light, white, 0.40),           -- hi
    light,                             -- lit
    mix(light, dark, 0.50),            -- mid
    dark,                              -- dark
    mix(dark, black, 0.40),            -- deep
    black,                             -- outline
  }
  local parts = {}
  for i, c in ipairs(tones) do
    parts[i] = string.format("%.3f,%.3f,%.3f", c[1], c[2], c[3])
  end
  local key = table.concat(parts, ";")
  Trees3D.lastPaint = key
  if paletteTex[key] ~= nil then return paletteTex[key] or loadTexture(name) end

  local P = Trees3D.VOXEL_PALETTE
  local ok, img = pcall(function()
    if not (love and love.image and love.image.newImageData) then return nil end
    local data = love.image.newImageData(P.tex, P.tex)
    local function fill(x0, y0, c)
      for y = y0, y0 + P.tile - 1 do
        for x = x0, x0 + P.tile - 1 do
          data:setPixel(x, y, c[1], c[2], c[3], 1)
        end
      end
    end
    for i, c in ipairs(tones) do fill((i - 1) * P.tile, 0, c) end
    for i, c in ipairs(P.bark) do
      fill((i - 1) * P.tile, P.tile, { c[1] / 255, c[2] / 255, c[3] / 255 })
    end
    local image = love.graphics.newImage(data)
    pcall(image.setFilter, image, "nearest", "nearest")
    return image
  end)
  paletteTex[key] = (ok and img) or false
  if not paletteTex[key] then Trees3D.lastPaint = "shipped" end
  return paletteTex[key] or loadTexture(name)
end

-- ------- WHAT THE SUN ACTUALLY NEEDS
--
-- The depth pass costs MORE than the scene pass, and it is drawing detail
-- that cannot survive into a shadow. Measured on ROUTE_2, 862 trees, clear
-- sky, medians of 3 x 100 frames (spreads 1-12%):
--
--     no trees            21.55 ms/frame
--     + the scene pass    28.78   (+7.24)
--     + the sun's pass    39.96   (+11.18)
--
-- Eleven milliseconds to re-draw ~700 triangles per tree into a depth
-- buffer, so that a canopy fifty pixels across can put a soft grey patch on
-- the grass. SHADOW_SOLID_ONLY already dropped the alpha cards from that
-- pass for the same reason; this is the rest of the argument.
--
-- So the caster is not the tree. It is a HULL of the tree: a six-sided
-- barrel whose ring radii are measured off the bake's own crown, band by
-- band, plus a prism for the bole. ~60 triangles against ~700, and the
-- silhouette it casts is the silhouette the real crown casts, because the
-- rings come from the real crown rather than from a guessed cylinder.
--
-- MEASURED OFF THE MESH, NOT DERIVED FROM canopyR. A single radius makes
-- every species the same barrel, which throws away the one thing the
-- shadows differ by: the pine tapers to a point and the oak does not, and
-- at this size the taper is most of what says "conifer" in a shadow.
--
-- The proxy carries the same canopy weights as the crown it replaces, even
-- though the depth pass sends no `sway` today and therefore cannot bend it.
-- That is deliberate: the day the shadow does sway, a proxy weighted zero
-- would hold a still shadow under a moving tree, and that reads as a bug in
-- the wind rather than as a stale assumption here.
local PROXY_SIDES, PROXY_BANDS = 6, 3

local function buildShadowProxy(tpl)
  local verts, weights = tpl.verts, tpl.weights
  local solid = tpl.solidIndices
  if not (verts and solid and #solid >= 3) then return end

  -- Only vertices the SOLID mesh actually uses. A card vertex sits out past
  -- the crown by design, so letting one into the profile would inflate every
  -- ring to the reach of the fringe.
  local used = {}
  for i = 1, #solid do used[solid[i]] = true end

  -- One UV for the whole proxy, borrowed from a solid vertex so it is
  -- guaranteed to land on an opaque texel. The fragment stage still runs its
  -- alpha discard in the depth pass, and a proxy pointed at a transparent
  -- corner of the atlas would cast no shadow at all -- silently, and only
  -- for whichever species had a hole there.
  local uu, vv = 0.5, 0.5
  for i = 1, #verts do
    if used[i] and verts[i][5] <= Trees3D.CARD_UV_CUT then
      uu, vv = verts[i][4], verts[i][5]
      break
    end
  end

  local h = tpl.height or 0
  local cy = tpl.canopyY or 0
  if not (h > 0) or cy >= h then return end
  -- A crown that reaches the ground (the droopy species do) leaves no bole
  -- to model; the barrel simply starts at zero.
  local hasTrunk = cy > h * 0.06

  local pv, pi, pw = {}, {}, {}
  local function put(x, y, z, w)
    pv[#pv + 1] = { x, y, z, uu, vv, 0.80 }
    pw[#pw + 1] = w
    return #pv
  end
  local function tri(a, b, c)
    pi[#pi + 1] = a; pi[#pi + 1] = b; pi[#pi + 1] = c
  end

  -- ---- the crown, band by band
  local bandH = (h - cy) / PROXY_BANDS
  local rings = {}
  local crownW = 0
  local nW = 0
  for k = 0, PROXY_BANDS do
    local y = cy + bandH * k
    local r, w, n = 0, 0, 0
    for i = 1, #verts do
      if used[i] then
        local v = verts[i]
        if math.abs(v[2] - y) <= bandH * 0.65 and v[2] >= cy - 0.001 then
          local d = math.sqrt(v[1] * v[1] + v[3] * v[3])
          if d > r then r = d end
          w = w + (weights[i] or 0); n = n + 1
        end
      end
    end
    if n > 0 then w = w / n else w = crownW end
    -- An empty band (a crown with a waist, or the very tip) keeps a token
    -- radius rather than pinching the barrel shut on a ring nothing
    -- measured.
    if r <= 0 then r = (tpl.canopyR or 1) * 0.25 end
    rings[k] = { y = y, r = r, w = w }
    crownW = crownW + w; nW = nW + 1
  end
  crownW = (nW > 0) and (crownW / nW) or 0.6

  local ringIdx = {}
  for k = 0, PROXY_BANDS do
    local ring = rings[k]
    local idx = {}
    for s = 0, PROXY_SIDES - 1 do
      local a = (s / PROXY_SIDES) * math.pi * 2
      idx[s] = put(math.cos(a) * ring.r, ring.y, math.sin(a) * ring.r, ring.w)
    end
    ringIdx[k] = idx
  end
  for k = 0, PROXY_BANDS - 1 do
    local lo, hi = ringIdx[k], ringIdx[k + 1]
    for s = 0, PROXY_SIDES - 1 do
      local t = (s + 1) % PROXY_SIDES
      tri(lo[s], lo[t], hi[t])
      tri(lo[s], hi[t], hi[s])
    end
  end
  -- caps: a fan to the axis at each end, so the barrel is a closed volume
  -- and the depth buffer never sees through it from above
  local topC = put(0, h, 0, rings[PROXY_BANDS].w)
  local botC = put(0, cy, 0, rings[0].w)
  for s = 0, PROXY_SIDES - 1 do
    local t = (s + 1) % PROXY_SIDES
    tri(ringIdx[PROXY_BANDS][s], ringIdx[PROXY_BANDS][t], topC)
    tri(ringIdx[0][t], ringIdx[0][s], botC)
  end

  -- ---- the bole
  if hasTrunk then
    -- THE LOWER PART OF THE BOLE ONLY. Measuring the whole band below the
    -- crown catches the flare where the first limbs leave the trunk, and a
    -- prism built on that reach casts a stalk as wide as a branch spread --
    -- which on the oak and the birch, whose crowns start past half height,
    -- is most of the tree's width laid on the grass. The bottom 60% is
    -- unambiguously bole.
    local tr = 0
    local boleTop = cy * 0.6
    for i = 1, #verts do
      if used[i] then
        local v = verts[i]
        if v[2] < boleTop then
          local d = math.sqrt(v[1] * v[1] + v[3] * v[3])
          if d > tr then tr = d end
        end
      end
    end
    if tr > 0.2 then
      local SIDES = 4
      local lo, hi = {}, {}
      for s = 0, SIDES - 1 do
        local a = (s / SIDES) * math.pi * 2 + math.pi / SIDES
        local x, z = math.cos(a) * tr, math.sin(a) * tr
        lo[s] = put(x, 0, z, 0)
        hi[s] = put(x, cy, z, math.min(crownW * 0.35, 0.4))
      end
      for s = 0, SIDES - 1 do
        local t = (s + 1) % SIDES
        tri(lo[s], lo[t], hi[t])
        tri(lo[s], hi[t], hi[s])
      end
    end
  end

  tpl.shadowVerts = pv
  tpl.shadowIndices = pi
  tpl.shadowWeights = pw
end

-- A "TTR2" bake:
--
--   0  "TTR2"          8  indices       16  height    24  canopy y
--   4  vertices       12  trunk idx     20  radius    28  canopy r
--
-- then nv vertices of SEVEN floats: x y z u v shade canopyWeight.
--
-- The seventh is the continuous 0..1 "how much of this vertex is canopy"
-- that the weather response needs -- zero down the bole, rising through
-- the crown, one at the tips. It is stored CLEAN here rather than already
-- packed into shade, because the file format is ours and there is no
-- reason for it to be lossy or unreadable; the packing happens at stamp
-- time, against a shader uniform that only the tree draw call sets.
--
-- v1 was the same header with six floats per vertex and a binary
-- trunk/canopy split classified by COLOUR, which broke on a model with
-- moss painted on its trunk. Bakes in v1 are refused rather than read
-- with a guessed weight.
local function loadTemplate(name)
  local key = cacheKey(name)
  if templates[key] ~= nil then return templates[key] or nil end
  local blob = readBinary(name .. ".mesh.bin")
  if type(blob) ~= "string" or #blob < 32 or blob:sub(1, 4) ~= "TTR2" then
    templates[key] = false
    return nil
  end
  local nv, ni, nTrunk = u32(blob, 4), u32(blob, 8), u32(blob, 12)
  local height, radius = f32(blob, 16), f32(blob, 20)
  local canopyY, canopyR = f32(blob, 24), f32(blob, 28)
  if nv < 3 or ni < 3 or nv > 20000 or ni > 60000
     or ni % 3 ~= 0 or nTrunk > ni or not (height > 0) then
    templates[key] = false
    return nil
  end

  local tris = math.floor(ni / 3)
  if tris > Trees3D.MAX_TRIS then
    templates[key] = false
    if V.mod and V.mod.log then
      pcall(V.mod.log.warn, V.mod.log,
            "tree bake '%s' refused: %d tris, budget is %d. This mesh is "
            .. "stamped on EVERY round-tree site, so 300 sites would cost "
            .. "%d triangles. Keeping the hulls. Re-bake with a lower "
            .. "MAX_TRIS in tools/optimize_tree_glb.py.",
            name, tris, Trees3D.MAX_TRIS, tris * 300)
    end
    return nil
  end
  if #blob < 32 + nv * 28 + ni * 2 then
    templates[key] = false
    return nil
  end

  -- Six floats go to LOVE (that is Voxel3D.FORMAT); the seventh rides
  -- alongside in `weights` until the shader uniform exists to receive it.
  local verts, weights, indices = {}, {}, {}
  local o = 32
  for i = 1, nv do
    verts[i] = {
      f32(blob, o), f32(blob, o + 4), f32(blob, o + 8),
      f32(blob, o + 12), f32(blob, o + 16), f32(blob, o + 20),
    }
    weights[i] = f32(blob, o + 24)
    o = o + 28
  end
  for i = 1, ni do
    local vi = u16(blob, o) + 1          -- LOVE vertex maps are 1-based
    if vi > nv then
      templates[key] = false             -- corrupt file, not a mesh to guess at
      return nil
    end
    indices[i] = vi
    o = o + 2
  end

  -- Which triangles are ALPHA CARDS, derived rather than stored: the bake
  -- puts the leaf sprite in the top CARD_STRIP of the atlas and squeezes
  -- every solid UV into what is left, so sampling above the line is a
  -- card. Deriving it costs one pass at load and saves a format bump.
  --
  -- The sun's depth pass uses the list without them. Cards are 120 of 420
  -- triangles and each pays an alpha `discard` -- expensive in a pass that
  -- is otherwise depth-only -- to draw a fringe that is not legible in a
  -- cast shadow at this scale.
  --
  -- ONE VERTEX ABOVE THE LINE, NOT ALL THREE, AND THE DIFFERENCE IS THE
  -- WHOLE FEATURE. A card is a quad with its tv at 0 and 1, which the
  -- baker maps to v = CARD_UV_CUT and v = 1 exactly (optimize_tree_glb.py:
  -- `1.0 - CARD_STRIP * (1.0 - tv)`). Both of its triangles therefore
  -- carry a vertex sitting precisely ON the cut, so an "all three above
  -- it" test classified every card as solid and the card-less shadow mesh
  -- came out byte-for-byte the size of the full one -- an optimization
  -- that was measured only by counting triangles it never removed.
  --
  -- Above the cut is unambiguous in the other direction: solid UVs are
  -- scaled by (1 - CARD_STRIP), so no solid vertex can exceed it. Only the
  -- boundary value itself is shared, which is exactly why it cannot be the
  -- discriminator.
  local solid = {}
  for i = 1, #indices - 2, 3 do
    local a, b2, c = indices[i], indices[i + 1], indices[i + 2]
    local isCard = verts[a][5] > Trees3D.CARD_UV_CUT
                   or verts[b2][5] > Trees3D.CARD_UV_CUT
                   or verts[c][5] > Trees3D.CARD_UV_CUT
    if not isCard then
      solid[#solid + 1] = a; solid[#solid + 1] = b2; solid[#solid + 1] = c
    end
  end

  templates[key] = {
    verts = verts, weights = weights, indices = indices,
    solidIndices = solid,
    height = height, radius = radius,
    canopyY = canopyY, canopyR = canopyR,
    trunkIndices = nTrunk,
  }
  buildShadowProxy(templates[key])
  return templates[key]
end

-- The ACTIVE set's decoded templates by species name, read-only. Exposed so
-- a probe can measure the packed channel against the real template rather
-- than a synthetic value; a proxy rather than the table because the cache
-- behind it is keyed by set directory.
Trees3D.templates = setmetatable({}, {
  __index = function(_, name) return templates[cacheKey(name)] end,
})

-- Which species of the row's set ship and load. Empty means the hulls stay.
function Trees3D.loaded()
  applyMode()
  local out = {}
  for _, name in ipairs(Trees3D.SPECIES) do
    if loadTemplate(name) and loadTexture(name) then out[#out + 1] = name end
  end
  return out
end

-- The single gate the mesher consults: true when the row's set loads, and
-- the hull is the answer to false whichever row is picked.
function Trees3D.available()
  return #Trees3D.loaded() > 0
end

-- Stable 0..1 from a site's own coordinates, no love.math, so a probe and
-- a play agree and a tree does not change species between frames.
local function unit(x, z, salt)
  local n = x * 374761393 + z * 668265263 + (salt or 0) * 1274126177
  n = (n * 1103515245 + 12345) % 2147483647
  if n < 0 then n = -n end
  return (n % 100000) / 100000
end

-- Append one rotated/scaled copy of a template into verts/indices.
-- Pack a brightness and a canopy weight into one float, preserving the
-- sign that the renderer reads as "this face points at the sky".
--
-- THIS IS HALF OF A PAIR. The other half is the `packedShade` branch in
-- Voxel3D's vertex stage, and changing either alone silently produces a
-- tree lit by garbage. Layout, once multiplied by 64: the integer part is
-- a 0..63 brightness level, the fraction is the canopy weight.
--
-- Brightness loses resolution -- 64 levels instead of a continuous ramp --
-- and that is the price of not adding a fourth component to the vertex
-- format that terrain, characters, lamps and grass all share. 64 levels is
-- past what a cel-shaded voxel world resolves anyway.
function Trees3D.packShade(shade, canopy)
  local sgn = shade < 0 and -1 or 1
  local mag = math.abs(shade)
  if mag > 1 then mag = 1 end
  local lvl = math.floor(mag * 63 + 0.5)
  if lvl < 1 then lvl = 1 end          -- keep the sign readable at zero
  local w = canopy or 0
  if w < 0 then w = 0 elseif w > 0.999 then w = 0.999 end
  return sgn * (lvl + w) / 64
end

-- The inverse, mirroring Voxel3D's `packedShade` branch ARITHMETIC FOR
-- ARITHMETIC. It exists so a probe can measure the round trip instead of
-- inferring it from "the shader compiled and the picture looks the same",
-- which is exactly the evidence that has been wrong before in this
-- renderer. Returns brightness, canopy weight, and the sky-facing flag.
function Trees3D.unpackShade(packed)
  local up = packed < 0
  local m = math.abs(packed) * 64
  local lvl = math.floor(m)
  return lvl / 63, m - lvl, up
end

local function stamp(verts, indices, tplV, tplI, ox, oz, yaw, scale, yscale, tplW)
  local c, s = math.cos(yaw), math.sin(yaw)
  local base = #verts
  yscale = yscale or scale
  for i = 1, #tplV do
    local v = tplV[i]
    local x, y, z = v[1] * scale, v[2] * yscale, v[3] * scale
    -- VertexShade: magnitude is cel shade, the SIGN is the renderer's
    -- "this face points at the sky" flag (vUp in Voxel3D's shader), which
    -- is what lets snow settle on a canopy. Carry it through unchanged --
    -- clamping the magnitude only, never the sign.
    local shade = v[6] or 0.8
    if shade >= 0 and shade < 0.05 then shade = 0.05 end
    if shade < 0 and shade > -0.05 then shade = -0.05 end
    verts[base + i] = { ox + x * c - z * s, y, oz + x * s + z * c,
                        v[4], v[5],
                        Trees3D.packShade(shade, tplW and tplW[i] or 0) }
  end
  for i = 1, #tplI do
    indices[#indices + 1] = tplI[i] + base
  end
end

-- WHERE A SITE'S TREE ACTUALLY STANDS, in one place.
--
-- Species, yaw, both scales and the jitter, all derived from the site's own
-- coordinates so a forest is a mix rather than a clone stamp and the same
-- site picks the same tree every time the map is entered.
--
-- Factored out because it is now read by TWO passes -- the stamp that
-- builds the mesh, and the canopy coverage that tells the ground what is
-- standing over it -- and those two agreeing is the whole feature. A
-- second copy of this arithmetic that drifted by one salt would put the
-- dry ground next to the tree casting it, which reads as a bug in the
-- weather rather than as a bug here. Same trap as packShade/packedShade,
-- and this time the fix is to not have a pair at all.
local function placement(site, nNames)
  local mx, mz = site.mx or 0, site.mz or 0
  local pick = 1 + math.floor(unit(mx, mz, 3) * nNames)
  if pick > nNames then pick = nNames end
  local siteScale = (site.r or 8) / 16
  -- A 2x2 site (the forest's 32 px drawings, site.r = 16) is twice the
  -- cell but not twice the tree: the bakes are authored against a 16 px
  -- cell at 0.78-1.05x, and carrying the same band through a doubled
  -- siteScale would stand 65-100 px trees on 32 px spacing. The big site
  -- takes a tighter band of its own radius, 1.25-1.60x.
  local big = siteScale >= 1
  local lo, ylo, span = 1.55, 1.50, 0.55
  if big then lo, ylo, span = 1.25, 1.20, 0.35 end
  return {
    pick = pick,
    yaw = unit(mx, mz, 1) * math.pi * 2,
    scale = siteScale * (lo + unit(mx, mz, 2) * span),
    -- WAS 1.05-1.80 against a 1.55-2.10 width scale, which squashed every
    -- bake into a bush: a 52 px oak landed 27-47 px tall next to a 16 px
    -- cell.  Matching the width range stands the forest up without moving
    -- the canopy-cover discs (those use `scale`, not yscale).
    yscale = siteScale * (ylo + unit(mx, mz, 4) * span),
    -- Wider canopies close the gaps but make the 16px GRID louder, not
    -- quieter: bigger discs on exact lattice points read as a pattern. A
    -- few pixels of offset per site breaks the rows without moving a tree
    -- off the cell it belongs to.
    jx = (unit(mx, mz, 5) - 0.5) * 6.0,
    jz = (unit(mx, mz, 6) - 0.5) * 6.0,
  }
end

-- Build this map's tree meshes from site records `{ mx, mz [, r] }` in
-- world pixels. One mesh per species, because each carries its own texture.
-- Stamp sites [from..to] of a build into its buckets. One slice's worth.
function Trees3D.stampRange(st, from, to)
  local names, buckets = st.names, st.buckets
  for i = from, to do
    local site = st.sites[i]
    local mx, mz = site.mx or 0, site.mz or 0
    local pl = placement(site, #names)
    local pick = pl.pick
    local b = buckets[pick]
    local yaw, scale, yscale = pl.yaw, pl.scale, pl.yscale
    local jx, jz = pl.jx, pl.jz
    local tpl = template(names[pick])
    stamp(b.verts, b.indices, tpl.verts, tpl.indices, mx + jx, mz + jz,
          yaw, scale, yscale, tpl.weights)
    -- The caster is the HULL when there is one (buildShadowProxy above),
    -- and the card-less solid mesh when there is not -- an older bake, or
    -- one whose crown the profile could not read.
    local sb = st.shadow[pick]
    if Trees3D.SHADOW_PROXY and tpl.shadowVerts then
      stamp(sb.verts, sb.indices, tpl.shadowVerts, tpl.shadowIndices,
            mx + jx, mz + jz, yaw, scale, yscale, tpl.shadowWeights)
    else
      stamp(sb.verts, sb.indices, tpl.verts, tpl.solidIndices, mx + jx, mz + jz,
            yaw, scale, yscale, tpl.weights)
    end
  end
end


-- Turn a finished build's buckets into meshes, one per species (each
-- carries its own texture, so they cannot share).
function Trees3D.finishBuild(st)
  local out = {}
  local paint = st.map and Trees3D.set().palette
  for i = 1, #st.names do
    local b = st.buckets[i]
    if #b.verts > 0 then
      local mesh = Voxel3D.newMesh(b.verts, b.indices)
      if mesh then
        local tex = paint and paletteTexture(st.names[i], st.map)
                    or loadTexture(st.names[i])
        if tex then pcall(mesh.setTexture, mesh, tex) end
        local shadowMesh = nil
        local sb = st.shadow and st.shadow[i]
        if sb and #sb.verts > 0 then
          shadowMesh = Voxel3D.newMesh(sb.verts, sb.indices)
          if shadowMesh and tex then pcall(shadowMesh.setTexture, shadowMesh, tex) end
        end
        out[#out + 1] = { mesh = mesh, shadowMesh = shadowMesh,
                          tex = tex, species = st.names[i] }
      end
    end
  end
  if #out == 0 then return nil end
  return out
end

-- Synchronous whole-map build. The game does NOT use this -- meshesFor
-- slices the same work across frames because doing it in one go stalled
-- ROUTE_2 for half a second. Kept for the probe, which times the stall
-- this exists to avoid.
function Trees3D.meshesFromSites(sites)
  local names = Trees3D.loaded()
  if #names == 0 or not sites or #sites == 0 then return nil end
  if #sites > Trees3D.MAX_TREES then return nil end
  local st = { sites = sites, names = names, buckets = {}, shadow = {} }
  for k = 1, #names do
    st.buckets[k] = { verts = {}, indices = {} }
    st.shadow[k] = { verts = {}, indices = {} }
  end
  Trees3D.stampRange(st, 1, #sites)
  return Trees3D.finishBuild(st)
end

-- Round-tree sites for a map, recorded by Structures.buildCylinders next to
-- the hull stamps it skipped.
local function sitesFor(map)
  if not map then return nil end
  local ok, S = pcall(function()
    return V.require("Structures").forMap(map)
  end)
  if not ok or not S then return nil end
  return S.treeSites
end

-- ------- WHAT IS STANDING OVER EACH CELL
--
-- How much canopy covers a cell, 0..1, for every cell any crown reaches.
-- Calls fn(cx, cy, cover) once per covered cell. Returns how many cells it
-- reported, or nil if this map has no authored forest.
--
-- NOT DERIVABLE FROM THE SITE GRID, which is why it is a pass rather than
-- a lookup: each crown is offset by up to three pixels of jitter and
-- scaled per site (1.55x to 2.10x of the site's own radius), so a cell's
-- cover depends on where its neighbours' crowns actually landed. Two
-- adjacent sites can leave the cell between them in full shade or half
-- open, and the grid says the same thing about both.
--
-- Read off the SITES, not off the built mesh. The sites are known the
-- moment Structures has looked at the map, while the mesh is stamped over
-- ~145 frames -- and the ground wants to know it is sheltered on the frame
-- the map loads, not two and a half seconds later. Same `placement`, so
-- the shade lands under the tree that casts it.
--
-- No love, no GPU, no allocation per cell: the caller decides what to do
-- with each one.
function Trees3D.eachCanopyCell(map, fn)
  local sites = sitesFor(map)
  if not sites or #sites == 0 then return nil end
  local names = Trees3D.loaded()
  if #names == 0 then return nil end
  if #sites > Trees3D.MAX_TREES then return nil end

  local CELL = 16
  local n = 0
  for i = 1, #sites do
    local site = sites[i]
    local mx, mz = site.mx or 0, site.mz or 0
    local pl = placement(site, #names)
    local tpl = template(names[pl.pick])
    if tpl then
      -- The crown's reach on the ground, in world pixels: the bake's own
      -- canopy radius carried through the same scale the mesh is stamped
      -- at. A tree is not its trunk -- shelter is the width of what is
      -- over you.
      local r = (tpl.canopyR or 0) * pl.scale
      if r > 1 then
        local ox, oz = mx + pl.jx, mz + pl.jz
        local c0x = math.floor((ox - r) / CELL)
        local c1x = math.floor((ox + r) / CELL)
        local c0y = math.floor((oz - r) / CELL)
        local c1y = math.floor((oz + r) / CELL)
        -- HOW MUCH OF THE CELL IS UNDER THE CROWN, not how deep the crown
        -- is at the cell's centre. The first cut asked the centre and it
        -- was nearly always wrong: a crown here is about 14 px across the
        -- radius and a cell is 16, so the disc frequently covers most of a
        -- cell while missing its exact middle. The offline check caught it
        -- reporting 2 cells at a peak cover of 0.039 -- a forest that
        -- sheltered nothing.
        --
        -- So each cell is sampled on a SUB-GRID and the results averaged.
        -- SUB x SUB point tests on a handful of cells per site, once per
        -- map bind, is nothing; being wrong by an order of magnitude on
        -- every cell of every wood is not.
        --
        -- AND THE SUB-GRID SHRINKS AS THE CROWN GROWS, because the error it
        -- was written against does too. A 4x4 grid was needed when a crown
        -- was ~14 px across the radius and a cell is 16: at that size a cell
        -- is BIGGER than the thing it is sampling, so its centre routinely
        -- misses a crown covering most of it. The voxel bake's crowns reach
        -- 29-53 px, where a cell sits well inside the disc and 2x2 lands
        -- within a few percent of 4x4.
        --
        -- The cost is not academic: this is a triple loop per site over the
        -- crown's whole footprint, and the footprint grows with the SQUARE
        -- of the radius. Holding 4x4 through a 1.6x wider crown would have
        -- turned ~230k point tests per map bind into ~600k -- tens of
        -- milliseconds of Lua on the frame a map loads, which is the one
        -- frame that can least afford it.
        local SUB = (r > 24) and 2 or 4
        local step = CELL / SUB
        local inv = 1 / (SUB * SUB)
        local r2 = r * r
        for cy = c0y, c1y do
          for cx = c0x, c1x do
            local acc = 0
            for sy = 0, SUB - 1 do
              local py = cy * CELL + (sy + 0.5) * step - oz
              for sx = 0, SUB - 1 do
                local px = cx * CELL + (sx + 0.5) * step - ox
                local d2 = px * px + py * py
                if d2 < r2 then
                  -- A crown is a dome, so it is deepest under the axis and
                  -- a fringe at the drip line. Parabolic rather than
                  -- linear -- it is the shape of the thing overhead.
                  acc = acc + (1 - d2 / r2)
                end
              end
            end
            if acc > 0 then
              fn(cx, cy, acc * inv)
              n = n + 1
            end
          end
        end
      end
    end
  end
  return n
end

-- Advance this map's build by one slice. Returns the finished meshes, or
-- nil while there is still work left -- the caller draws nothing on those
-- frames, which is what "fades in over a few frames" means in practice.
local function meshesFor(map)
  local id = map and map.id
  if not id then return nil end

  -- RETIRE ABANDONED BUILDS -- above the early return for a finished map,
  -- and that placement is the fix rather than a detail. This is the one
  -- line the draw path runs every frame for every map it draws, whatever
  -- state that map is in. Sweeping further down, where work is actually
  -- stamped, means the sweep stops the moment nothing is building: walk
  -- off a half-built route onto one whose forest is already done and
  -- nothing advances again, so the stale build survives precisely the
  -- situation the sweep exists for. (Measured: it did.)
  advances = advances + 1
  if pending[id] then pending[id].seen = advances end
  for id2, st2 in pairs(pending) do
    if advances - (st2.seen or 0) > Trees3D.RETIRE_AFTER then
      pending[id2] = nil
    end
  end

  if meshes[id] ~= nil then return meshes[id] or nil end

  local st = pending[id]
  if not st then
    local sites = sitesFor(map)
    local names = Trees3D.loaded()
    if not sites or #sites == 0 or #names == 0 then
      meshes[id] = false
      return nil
    end
    if #sites > Trees3D.MAX_TREES then
      if V.mod and V.mod.log then
        pcall(V.mod.log.warn, V.mod.log,
              "trees: %d sites on this map is over the %d ceiling -- keeping "
              .. "the hulls here", #sites, Trees3D.MAX_TREES)
      end
      meshes[id] = false
      return nil
    end
    st = { sites = sites, names = names, i = 1, buckets = {}, shadow = {},
           frames = 0, seen = advances, map = map }
    for k = 1, #names do
      st.buckets[k] = { verts = {}, indices = {} }
      st.shadow[k] = { verts = {}, indices = {} }
    end
    pending[id] = st
  end

  st.frames = st.frames + 1
  local last = math.min(st.i + Trees3D.SLICE_SITES - 1, #st.sites)
  Trees3D.stampRange(st, st.i, last)
  st.i = last + 1
  if st.i <= #st.sites then return nil end

  local built = Trees3D.finishBuild(st)
  pending[id] = nil
  meshes[id] = built or false
  builtSites[id] = #st.sites
  if built and V.mod and V.mod.log then
    pcall(V.mod.log.info, V.mod.log,
          "trees: %d authored trees on %s in %d mesh(es), built over %d frames",
          #st.sites, tostring(id), #built, st.frames)
  end
  return built
end

-- A finished build, or nil while there is still work to do. ADVANCES
-- NOTHING -- it is meshesFor with the stamping taken out.
--
-- The sun's depth pass reads the forest through here, and that is a frame
-- budget decision rather than tidiness. Both passes used to go through
-- meshesFor, so both advanced the build and a constructing frame stamped
-- TWO slices: SLICE_SITES reads as a per-frame budget and was quietly
-- costing double it. Measured before the split, on ROUTE_2: 12.00
-- sites/tick, 2.00 draws/tick, ~15.7 ms of stamping in a frame whose
-- whole budget is 16.7.
--
-- The build belongs to the pass that puts trees on the SCREEN; the sun
-- takes whatever is finished. The cost of that is one frame of skew on
-- the last slice -- VoxelScene runs the depth pass first, so on the frame
-- the build completes the forest is lit before it casts. One frame, once
-- per map, against half the build cost of every frame before it.
local function builtFor(map)
  local id = map and map.id
  if not id then return nil end
  return meshes[id] or nil
end

-- Is this map's forest finished?
--
-- REPORTS the build, never advances it. The slicing lives in the DRAW path
-- -- meshesFor is only reachable through draw/castShadows -- so a caller
-- that stamped its own slices to "help" would race the draw path and
-- change the very frame cost it is usually polling in order to measure.
--
-- Returns done, state, sitesDone, sitesTotal. The state is not decoration:
--
--   "ready"     built; the whole forest is on screen
--   "building"  a build is in flight, sitesDone of sitesTotal stamped
--   "cold"      nothing started -- this map has not been drawn yet
--   "hulls"     this map decided AGAINST the model (no bake, no sites, or
--               over MAX_TREES) and will never build. TERMINAL: a loop
--               that waits for `done` alone spins here until its own
--               timeout, then reports a stall that never existed. Break
--               on it. That is why the state is returned and not just
--               the boolean.
--
-- Counting frames instead of asking this is what made the last cost run
-- meaningless: ROUTE_2 is 862 sites at SLICE_SITES=6, and the fixed
-- wait(150) it was sampled after did not cover even a third of the build,
-- so the build landed inside the sample and the forest was billed for it.
function Trees3D.ready(map)
  local id = map and map.id
  if not id then return false, "cold", 0, 0 end
  if meshes[id] then
    local n = builtSites[id] or 0
    return true, "ready", n, n
  end
  if meshes[id] == false then return false, "hulls", 0, 0 end
  local st = pending[id]
  if not st then return false, "cold", 0, 0 end
  return false, "building", st.i - 1, #st.sites
end

-- Builds in flight across ALL maps, and the sites they still owe.
--
-- The map underfoot is not the whole bill: VoxelScene draws neighbour maps
-- through the same path (and casts their shadows on the higher quality
-- rungs), so each neighbour runs its own sliced build in the same frames.
-- Polling only the map being stood on can therefore call a route "settled"
-- while three neighbours are still stamping, which lands in the sample
-- exactly like the local build did.
function Trees3D.buildsInFlight()
  local maps, sites = 0, 0
  for _, st in pairs(pending) do
    maps = maps + 1
    sites = sites + (#st.sites - (st.i - 1))
  end
  return maps, sites
end

-- How much of the wind's reach the canopy takes, against the grass's.
--
-- Wind.amount() is a tip reach in WORLD PIXELS calibrated on a 16px tuft
-- (Wind.TUFT), and a tree is not a tuft: the crown is further from its
-- anchor, so the same air moves it further. The share is more than one for
-- that reason and stays small in absolute terms -- at the resting amount
-- (~1.2 px) this is under three pixels at the tips, which is a canopy
-- breathing. Push it much past this and the leaves start sliding off the
-- trunk they are supposed to be attached to, because nothing here rotates
-- the tree: the bole is pinned by vCanopy = 0 and only the crown moves.
--
-- The same knob Wind.FLOWER_SHARE is, and for the same reason: the wind is
-- one system with one bearing and one clock, and everything standing in it
-- takes a share rather than keeping its own weather.
--
-- RAISED 2.2 -> 2.9 WITH THE VOXEL BAKE, and the reason is that this number
-- was never really about the wind -- it is about how far a crown may move
-- BEFORE IT LOOKS DETACHED, and that ceiling scales with the tree. The old
-- bake stood 28.5 px with a 15.7 px crown, and 2.2 was measured as its
-- limit (4.4 turned the canopy to a blur). The voxel species stand 40-48 px
-- with crowns of 18.6-25.4, about 1.6x, so holding 2.2 would have quietly
-- made the forest stiffer than the one it replaced while the number on the
-- page said nothing had changed.
--
-- 2.9 is that ratio applied, kept short of it deliberately: a blocky canopy
-- shows a sliding leaf more plainly than a smooth one, because the voxel
-- grid gives the eye a straight edge to notice the shear against.
-- 2.9 -> 3.4: photo leaf cards give the eye a lobe to follow, so the same
-- shear that looked like a sliding voxel now reads as leaves in the wind.
-- Still short of the old 4.4 that turned the crown into a blur.
--
-- NOW PER SET (Trees3D.SETS[..].windShare): 3.4 for the 3D cards, 2.9 for
-- the VOXEL cubes -- the number that was measured for a blocky crown before
-- the cards arrived. This field is the LIVE value applyMode copies in when
-- the row changes; the probes still zero and restore it per round.
Trees3D.WIND_SHARE = Trees3D.SETS.voxel.windShare

-- Whether a map gets the authored forest at all: outdoor maps, plus the
-- tilesets the profile flags with `authored_trees` (Viridian Forest -- not
-- "outdoor" to the engine, no door SFX and no sky, but a wood).
--
-- Read by Structures at build time and by draw() every frame, and it has
-- to be the SAME answer in both. It was not: sites were recorded under
-- "the bake loads" and drawn under "the map is outdoor", so the forest's
-- 430 sites had their hulls skipped for a mesh draw() then refused, and the
-- forest stood with no trees at all. (Celadon Gym's round hedges went the
-- same way, in the other direction: they keep their hulls now.)
function Trees3D.wantsMap(map, outdoor)
  if outdoor then return true end
  local okP, prof = pcall(V.data, "voxel_heights")
  local entry = okP and type(prof) == "table" and prof.tilesets
                and map and map.tileset and prof.tilesets[map.tileset.id]
  return type(entry) == "table" and entry.authored_trees == true
end

-- Draw this map's forest. One call per species, under the hour's own light
-- exactly like the terrain -- no flatten pass, a tree is not a lamp.
--
-- `ox, oz` is the neighbour-map translation in world pixels (0 on the map
-- being stood on); sites are stored in the map's own coordinates, so the
-- offset rides the transform rather than the mesh.
function Trees3D.draw(map, outdoor, ox, oz)
  if not Trees3D.wantsMap(map, outdoor) then return end
  if not Voxel3D.available() then return end
  local built = meshesFor(map)
  if not built then return end
  local Mat4 = V.require("Mat4")
  local xf = Mat4.translate(tonumber(ox) or 0, 0, tonumber(oz) or 0)
  -- Tell the shader this draw's shade channel is packed, and turn it off
  -- again: leaving it on would make the NEXT mesh's brightness decode as a
  -- 64-level ramp of nonsense.
  if Voxel3D.packedShade then Voxel3D.packedShade(true) end

  -- ---- THE WIND, AND WHAT IS FALLING THROUGH IT
  --
  -- `sway` is the whole switch: Voxel3D's vertex stage does nothing at all
  -- unless it is positive, so WIND OFF plants the forest by arithmetic
  -- rather than by a second setting to keep in step.
  --
  -- grassLoad has to be re-sent HERE and cannot be inherited. VoxelScene
  -- sets it for the grass pass and then clears it to nil three lines
  -- before this one (with crush and crushMap), precisely so a later pass
  -- cannot wear the meadow's weather -- which is the right rule, and it
  -- means the pass that DOES want the rain has to ask for it again. Read
  -- straight from Wind rather than cached: it is the same one-frame packet
  -- the grass just used, so a shower moves the meadow and the wood on the
  -- same tick and by the same number.
  local sway = 0
  local okW, Wind = pcall(V.require, "Wind")
  if okW and Wind and Wind.amount then
    local okA, amount = pcall(Wind.amount)
    applyMode()
    if okA then sway = (tonumber(amount) or 0) * Trees3D.WIND_SHARE end
    local okL, wet, snow, gust = pcall(Wind.load)
    if okL then
      Voxel3D.grassLoad = { wet or 0, snow or 0, gust or 0 }
    end
  end

  for i = 1, #built do
    Voxel3D.draw(built[i].mesh, built[i].tex, xf, 0, xf, sway)
  end

  -- Put the load channel back the way VoxelScene left it. Leaving the
  -- forest's packet up would hand it to whatever draws next -- the
  -- underground corridor, a battle field -- exactly the leak the clear
  -- before this pass exists to prevent.
  Voxel3D.grassLoad = nil
  if Voxel3D.packedShade then Voxel3D.packedShade(false) end
end

-- Cast the forest into the sun's depth pass.
--
-- Without this a tree is lit but prints no shadow, and on a bright route
-- that does not read as "missing shadow" -- it reads as the tree HOVERING,
-- because contact shadow is most of what tells an eye that something is
-- standing on the ground. The hulls this replaced were part of the terrain
-- mesh and got their shadow for free; a mesh drawn from the draw path has
-- to ask.
--
-- The combined mesh is already in map space, so one call per species with
-- the neighbour translation is the whole job -- no per-tree matrices, and
-- the shadow pass costs the same one draw the scene pass does.
function Trees3D.castShadows(map, ox, oz)
  if not Voxel3D.available() then return end
  -- builtFor, NOT meshesFor: this pass consumes the build, it does not
  -- advance it. See builtFor for the measurement that forced the split.
  local built = builtFor(map)
  if not built then return end
  local ShadowMap = V.require("ShadowMap")
  local Mat4 = V.require("Mat4")
  local m = Mat4.translate(tonumber(ox) or 0, 0, tonumber(oz) or 0)
  -- The depth pass reads the same vertex channel, so it needs the same
  -- decode: without this the shadow caster would read a packed shade as a
  -- brightness and could displace or drop geometry the scene pass kept.
  if Voxel3D.packedShade then Voxel3D.packedShade(true) end
  for i = 1, #built do
    local caster = built[i].mesh
    if Trees3D.SHADOW_SOLID_ONLY and built[i].shadowMesh then
      caster = built[i].shadowMesh
    end
    pcall(ShadowMap.draw, caster, built[i].tex, ShadowMap.snug(m))
  end
  if Voxel3D.packedShade then Voxel3D.packedShade(false) end
end

function Trees3D.count(map)
  local s = sitesFor(map)
  return s and #s or 0
end

function Trees3D.meta(name)
  local t = loadTemplate(name or Trees3D.SPECIES[1])
  if not t then return nil end
  return {
    height = t.height, radius = t.radius,
    canopyY = t.canopyY, canopyR = t.canopyR,
    tris = math.floor(#t.indices / 3),
    trunkTris = math.floor(t.trunkIndices / 3),
  }
end

-- Drop the per-map meshes (a re-bake, a map edit, a settings flip).
function Trees3D.invalidate()
  meshes, pending, builtSites = {}, {}, {}
end

-- Drop everything, including the decoded templates and their textures.
function Trees3D.reload()
  templates, textures, meshes, pending, builtSites = {}, {}, {}, {}, {}
  paletteTex = {}
end

return Trees3D
