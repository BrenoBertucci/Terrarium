-- Voxel world mode: authored 3D trees.
--
-- The classic path carves a round tree from its own tileset art -- an
-- outline-hulled voxel ball, one hull template per distinct drawing,
-- stamped per cell (Structures.buildCylinders). That reads as Gen 1 and it
-- is free, but it is the same ball everywhere and it has no real canopy.
--
-- Drop a bake under assets/ground/tree/ (<name>.mesh.bin + <name>.png, from
-- tools/optimize_tree_glb.py) and this file stamps a real triangle tree on
-- every round-tree site instead. If no bake is present, available() is
-- false and Structures/ChunkMesher keep the hulls -- this file never throws
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

local Trees3D = {}

Trees3D.ASSET_DIR = "assets/ground/tree/"

-- Species ship as sibling bakes. Each carries its own texture, so each is
-- its own mesh and its own draw call -- four species is four calls for the
-- whole forest, which is still nothing next to the hulls' one.
Trees3D.SPECIES = { "tree_willow" }

-- Per-tree ceiling, checked against what the bake actually contains. The
-- number is not a preference: this template is stamped on EVERY round-tree
-- site, so its cost is multiplied by the forest. Refusing is the honest
-- answer -- the hulls are the classic path, they are free, and a forest
-- that draws beats one that is correct and does not.
Trees3D.MAX_TRIS = 450

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

local templates = {}   -- name -> template | false
local pending = {}     -- map id -> resumable build state
local textures = {}    -- name -> Image | false
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
  if textures[name] ~= nil then return textures[name] or nil end
  local file = name .. ".png"
  local okA, Assets = pcall(require, "src.render.Assets")
  for _, path in ipairs(candidatePaths(file)) do
    if okA and Assets and Assets.image then
      local okE, exists = pcall(Assets.exists, path)
      if okE and exists then
        local ok, img = pcall(Assets.image, path)
        if ok and img then
          pcall(img.setFilter, img, "nearest", "nearest")
          textures[name] = img
          return img
        end
      end
    end
    if love and love.graphics and love.graphics.newImage then
      local ok, img = pcall(love.graphics.newImage, path)
      if ok and img then
        pcall(img.setFilter, img, "nearest", "nearest")
        textures[name] = img
        return img
      end
    end
  end
  textures[name] = false
  return nil
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
  if templates[name] ~= nil then return templates[name] or nil end
  local blob = readBinary(name .. ".mesh.bin")
  if type(blob) ~= "string" or #blob < 32 or blob:sub(1, 4) ~= "TTR2" then
    templates[name] = false
    return nil
  end
  local nv, ni, nTrunk = u32(blob, 4), u32(blob, 8), u32(blob, 12)
  local height, radius = f32(blob, 16), f32(blob, 20)
  local canopyY, canopyR = f32(blob, 24), f32(blob, 28)
  if nv < 3 or ni < 3 or nv > 20000 or ni > 60000
     or ni % 3 ~= 0 or nTrunk > ni or not (height > 0) then
    templates[name] = false
    return nil
  end

  local tris = math.floor(ni / 3)
  if tris > Trees3D.MAX_TRIS then
    templates[name] = false
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
    templates[name] = false
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
      templates[name] = false            -- corrupt file, not a mesh to guess at
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

  templates[name] = {
    verts = verts, weights = weights, indices = indices,
    solidIndices = solid,
    height = height, radius = radius,
    canopyY = canopyY, canopyR = canopyR,
    trunkIndices = nTrunk,
  }
  return templates[name]
end

-- Which species ship and load. Empty means the hulls stay.
-- Exposed so a probe can measure the packed channel against the real
-- template rather than a synthetic value.
Trees3D.templates = templates

function Trees3D.loaded()
  local out = {}
  for _, name in ipairs(Trees3D.SPECIES) do
    if loadTemplate(name) and loadTexture(name) then out[#out + 1] = name end
  end
  return out
end

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
  return {
    pick = pick,
    yaw = unit(mx, mz, 1) * math.pi * 2,
    scale = siteScale * (1.55 + unit(mx, mz, 2) * 0.55),
    yscale = siteScale * (1.05 + unit(mx, mz, 4) * 0.75),
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
    local tpl = templates[names[pick]]
    stamp(b.verts, b.indices, tpl.verts, tpl.indices, mx + jx, mz + jz,
          yaw, scale, yscale, tpl.weights)
    local sb = st.shadow[pick]
    stamp(sb.verts, sb.indices, tpl.verts, tpl.solidIndices, mx + jx, mz + jz,
          yaw, scale, yscale, tpl.weights)
  end
end


-- Turn a finished build's buckets into meshes, one per species (each
-- carries its own texture, so they cannot share).
function Trees3D.finishBuild(st)
  local out = {}
  for i = 1, #st.names do
    local b = st.buckets[i]
    if #b.verts > 0 then
      local mesh = Voxel3D.newMesh(b.verts, b.indices)
      if mesh then
        local tex = loadTexture(st.names[i])
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
    local tpl = templates[names[pl.pick]]
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
        local SUB = 4
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
           frames = 0, seen = advances }
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
Trees3D.WIND_SHARE = 2.2

-- Draw this map's forest. One call per species, under the hour's own light
-- exactly like the terrain -- no flatten pass, a tree is not a lamp.
--
-- `ox, oz` is the neighbour-map translation in world pixels (0 on the map
-- being stood on); sites are stored in the map's own coordinates, so the
-- offset rides the transform rather than the mesh.
function Trees3D.draw(map, outdoor, ox, oz)
  if not outdoor then return end
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
end

return Trees3D
