-- Light that comes FROM things (the GLOW row).
--
-- Every light this mod had was a pool of closed-form falloff: eight street
-- lamps sent as uniforms, a crypt's candles, a shop's tubes. They are good
-- pools and they walk straight through walls, and there could never be more
-- than eight of them. What Gen 1 has that none of that could light is the
-- thing that makes its darkness mean something: a Charmander's tail in Rock
-- Tunnel, FLASH, a Pikachu crackling in the dark of the Power Plant, a lit
-- doorway at night, a Flamethrower going off in a cave.
--
-- ------- the field
--
-- A small window of the world (Glow.SIZE texels square, one texel per half
-- cell) is redrawn every frame on the GPU as a stack of additive quads, one
-- per glowing thing, each textured with that thing's MASK: how much of its
-- light reaches each texel around it. The scene shader reads the window
-- once per fragment (lib/Voxel3D.lua, GLOW_FIELD) -- so forty lights cost
-- what one does, and a light's colour, flicker and strength are free to
-- change every frame because they are only the quad's colour.
--
-- The mask is where the light learns the map. It is built on the CPU from
-- the same heights the mesher extrudes (VoxelScene.groundAt, and the real
-- tops of stamped buildings, Buildings.tallAt): a texel taller than the
-- flame blocks, and visibility is PROPAGATED outward ring by ring, each
-- texel taking a blend of its two neighbours toward the source. That one
-- rule gives a shadow behind every rock that softens with distance and a
-- little light turning every corner, which is most of what makes a light
-- in a cave look like a light rather than a disc. A floor of BOUNCE keeps
-- a shadowed texel near the flame dim rather than black -- light off the
-- walls, which no GB game ever drew and every cave has. Masks are cached
-- by where the source stands, so a lantern that walks costs one small
-- build per half cell and a lamp that stands costs nothing at all.
--
-- ------- the dark
--
-- A light needs something to push against, and indoors this renderer has
-- always lit a cave at noon. So caves are held down (CAVE_AMBIENT), and
-- Rock Tunnel before FLASH is held down to almost nothing (DARK_AMBIENT) --
-- the original's own darkness, drawn as darkness rather than as a palette.
-- That last part matters: the engine darkens a dark map by PERMUTING its
-- palette (wMapPalOffset: white to grey, every other shade to black), and
-- a black texture stays black under any light. While the diorama is on and
-- this row is ON, the palette shift is intercepted (Glow.install) and the
-- same darkness comes from the light instead. The flat 2D game, and this
-- row OFF, keep the engine's own.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local RenderTarget = V.require("RenderTarget")
local DayNight = V.require("DayNight")
local Voxel3D = V.require("Voxel3D")
local Voxel = V.require("VoxelState")

local Map = require("src.world.Map")

local Glow = {}

Glow.setting = ModSetting.new("glow", "GLOW",
                              { true, false },
                              { "ON", "OFF" })

function Glow.enabled()
  local ok, v = pcall(Glow.setting.get, Glow.setting)
  return ok and v == true
end

local function game()
  local ok, G = pcall(require, "src.core.Game")
  return ok and G or nil
end

local function now()
  return (love.timer and love.timer.getTime and love.timer.getTime()) or 0
end

-- ------- the numbers

Glow.TEXEL = 8           -- world px per field texel: half a cell
Glow.SIZE = 128          -- texels per side: 1024 world px, 64 cells
-- The field is an 8-bit canvas (the one render target every GLES2 driver
-- has), so light is stored at half strength and the shader doubles it:
-- two overlapping lanterns can sum past 1 without clipping.
Glow.SCALE = 0.5
-- The height the field is measured at, and the height a source's flame
-- stands above its own floor. A Pokemon's body, roughly: high enough that
-- a fence does not shadow it, low enough that a boulder does.
Glow.HEIGHT = 14
Glow.FLAME = 10
-- What a shadowed texel keeps: light off the walls around it.
Glow.BOUNCE = 0.10
-- How much the row adds, as a whole. One number for the look.
Glow.STRENGTH = 2.0
-- The most lights drawn in one frame, nearest first.
Glow.MAX_SOURCES = 40
-- How many new masks one frame may build. A map arriving with thirty lit
-- doors spreads its builds over a few frames instead of spending them all
-- on the first one; the nearest (the companion first) come first.
Glow.BUILDS_PER_FRAME = 6
Glow.MASK_CACHE = 300

-- The dark, as a share of the light the room had (see the header).
Glow.CAVE_AMBIENT = 0.36
Glow.DARK_AMBIENT = 0.05
-- Rock Tunnel after FLASH: the original lights the whole tunnel, and a
-- tunnel lit end to end at CAVE_AMBIENT reads as any other cave with a
-- lantern nobody can see. Held low instead, so FLASH is what it looks like
-- from inside -- a wide circle of cold light around you, the dark at its rim.
Glow.FLASH_AMBIENT = 0.14
-- and the colour it takes: what little fill a cave has is cool
Glow.CAVE_TINT = { 0.90, 0.96, 1.10 }

Glow.CAVES = {
  MT_MOON_1F = true, MT_MOON_B1F = true, MT_MOON_B2F = true,
  ROCK_TUNNEL_1F = true, ROCK_TUNNEL_B1F = true,
  DIGLETTS_CAVE = true,
  SEAFOAM_ISLANDS_1F = true, SEAFOAM_ISLANDS_B1F = true,
  SEAFOAM_ISLANDS_B2F = true, SEAFOAM_ISLANDS_B3F = true,
  SEAFOAM_ISLANDS_B4F = true,
  VICTORY_ROAD_1F = true, VICTORY_ROAD_2F = true, VICTORY_ROAD_3F = true,
  CERULEAN_CAVE_1F = true, CERULEAN_CAVE_2F = true, CERULEAN_CAVE_B1F = true,
  POWER_PLANT = true,
}

function Glow.isCave(map)
  return (map and map.id and Glow.CAVES[map.id]) and true or false
end

-- ------- who glows
--
-- By species, not by type: a Squirtle is Water and gives off nothing, a
-- Staryu's gem does. Colour, reach in cells, strength, and how it moves.
local FIRE  = { 1.00, 0.50, 0.16 }
local SPARK = { 1.00, 0.90, 0.42 }
local COLD_SPARK = { 0.70, 0.86, 1.00 }
local GHOST = { 0.62, 0.34, 1.00 }
local FROST = { 0.52, 0.84, 1.00 }
local PSY   = { 0.95, 0.50, 1.00 }
local GEM   = { 1.00, 0.36, 0.52 }
Glow.FLASH_COLOR = { 0.82, 0.90, 1.00 }

local function E(color, reach, power, kind)
  return { color = color, reach = reach, power = power, kind = kind }
end

Glow.EMITTERS = {
  CHARMANDER = E(FIRE, 3.5, 1.00, "fire"),
  CHARMELEON = E(FIRE, 4.0, 1.10, "fire"),
  CHARIZARD  = E(FIRE, 5.0, 1.30, "fire"),
  VULPIX     = E(FIRE, 2.5, 0.60, "fire"),
  NINETALES  = E(FIRE, 3.5, 0.85, "fire"),
  GROWLITHE  = E(FIRE, 2.5, 0.60, "fire"),
  ARCANINE   = E(FIRE, 3.5, 0.90, "fire"),
  PONYTA     = E(FIRE, 4.0, 1.10, "fire"),
  RAPIDASH   = E(FIRE, 4.5, 1.25, "fire"),
  MAGMAR     = E(FIRE, 4.5, 1.25, "fire"),
  FLAREON    = E(FIRE, 3.0, 0.80, "fire"),
  MOLTRES    = E(FIRE, 6.0, 1.50, "fire"),
  PIKACHU    = E(SPARK, 3.0, 0.80, "spark"),
  RAICHU     = E(SPARK, 3.5, 1.00, "spark"),
  VOLTORB    = E(SPARK, 2.5, 0.70, "spark"),
  ELECTRODE  = E(SPARK, 3.5, 0.90, "spark"),
  ELECTABUZZ = E(SPARK, 4.0, 1.10, "spark"),
  JOLTEON    = E(SPARK, 3.0, 0.80, "spark"),
  ZAPDOS     = E(SPARK, 6.0, 1.50, "spark"),
  MAGNEMITE  = E(COLD_SPARK, 2.5, 0.70, "spark"),
  MAGNETON   = E(COLD_SPARK, 3.5, 0.90, "spark"),
  GASTLY     = E(GHOST, 3.0, 0.70, "ghost"),
  HAUNTER    = E(GHOST, 3.5, 0.80, "ghost"),
  GENGAR     = E(GHOST, 3.5, 0.80, "ghost"),
  STARYU     = E(GEM, 2.0, 0.55, "pulse"),
  STARMIE    = E(GEM, 2.5, 0.70, "pulse"),
  ARTICUNO   = E(FROST, 5.0, 1.20, "pulse"),
  MEWTWO     = E(PSY, 4.5, 1.10, "pulse"),
  MEW        = E(PSY, 3.0, 0.80, "pulse"),
}

-- FLASH: a lantern the whole party's worth of light, carried by whoever
-- walks with you. Wide and cold, with a warm-white core only in the sense
-- that it is the brightest thing in the cave.
Glow.FLASH = E(Glow.FLASH_COLOR, 6.5, 1.35, "steady")

-- A lit doorway at night: the room behind it spilling out. Coloured by what
-- the room is, so a Center reads as a Center across a dark square.
Glow.DOOR_REACH = 4.5
Glow.DOOR_POWER = 1.20
local DOOR_WARM   = { 1.00, 0.66, 0.30 }
local DOOR_CENTER = { 1.00, 0.62, 0.66 }
local DOOR_MART   = { 0.72, 0.88, 1.00 }
local DOOR_GYM    = { 1.00, 0.90, 0.70 }

local function doorColor(dest)
  local s = tostring(dest or "")
  if s:find("POKECENTER") then return DOOR_CENTER end
  if s:find("MART") then return DOOR_MART end
  if s:find("GYM") then return DOOR_GYM end
  return DOOR_WARM
end

-- ------- how a light moves
local function flicker(kind, t, seed)
  if kind == "fire" then
    return 0.84 + 0.09 * math.sin(t * 10.3 + seed)
               + 0.07 * math.sin(t * 23.1 + seed * 2.3)
  elseif kind == "spark" then
    local base = 0.82 + 0.08 * math.sin(t * 6.1 + seed)
    -- a crackle: a few fixed slots a second go bright for their slot
    local slot = math.floor(t * 14 + seed)
    local h = (math.sin(slot * 12.9898 + seed * 78.233) * 43758.5453) % 1
    if h > 0.9 then base = base + 0.45 end
    return base
  elseif kind == "ghost" then
    return 0.55 + 0.45 * (0.5 + 0.5 * math.sin(t * 1.3 + seed))
  elseif kind == "pulse" then
    return 0.82 + 0.18 * math.sin(t * 2.1 + seed)
  end
  return 1
end

-- ------- the map's heights
--
-- What blocks a flame: a cell nobody can stand on, as tall as the mesher
-- built it or as the building stamped on it, whichever is taller (the same
-- two answers the SM64 camera's line of sight takes, lib/MarioCam.lua).
-- A cell somebody CAN stand on never blocks -- tall grass and flowers are
-- tufts, not walls -- and water sits below the floor.
local NEVER = -1000
local WALL = 48           -- off every map: rock in a cave, the tree ring outside

local occMemo = setmetatable({}, { __mode = "k" })
local floorMemo = setmetatable({}, { __mode = "k" })

local VoxelSceneMod, BuildingsMod
local function sceneMod()
  if VoxelSceneMod == nil then
    local ok, m = pcall(V.require, "VoxelScene")
    VoxelSceneMod = ok and m or false
  end
  return VoxelSceneMod or nil
end
local function buildingsMod()
  if BuildingsMod == nil then
    local ok, m = pcall(V.require, "Buildings")
    BuildingsMod = ok and m or false
  end
  return BuildingsMod or nil
end

local function floorAt(map, cx, cy)
  local t = floorMemo[map]
  if not t then t = {}; floorMemo[map] = t end
  local k = cx * 4096 + cy
  local h = t[k]
  if h then return h end
  h = 0
  local S = sceneMod()
  if S and map:inBounds(cx, cy) then
    local ok, g = pcall(S.groundAt, map, cx, cy)
    h = (ok and tonumber(g)) or 0
  end
  t[k] = h
  return h
end

local function occluderAt(map, cx, cy)
  local t = occMemo[map]
  if not t then t = {}; occMemo[map] = t end
  local k = cx * 4096 + cy
  local h = t[k]
  if h then return h end
  if not map:inBounds(cx, cy) then
    h = WALL
  elseif map:isWalkableCell(cx, cy) then
    h = NEVER
  else
    h = floorAt(map, cx, cy)
    local B = buildingsMod()
    if B and B.tallAt then
      local ok, tall = pcall(B.tallAt, map, cx, cy)
      if ok and tall and tall > h then h = tall end
    end
  end
  t[k] = h
  return h
end

-- The maps a world cell may land on this frame: the one underfoot and its
-- connected neighbours, each with its origin in cells.
local ctx = { map = nil, nbs = {} }

-- When a map's heights are FINAL. The mesher paints flat ground under a
-- building until its model is stamped (Buildings.tallAt), and the stamping
-- lands with the map's structures, a moment after the map itself -- so a
-- height read before then would let a lantern shine through a house. Two
-- signals retire what was read early: the map's structure cache appearing
-- (or being rebuilt), and its first full build finishing (see the tick).
-- Both happen a handful of times per visit, never per frame.
local structSeen = setmetatable({}, { __mode = "k" })
local settled = setmetatable({}, { __mode = "k" })

local forgetMap   -- defined with the masks, below

local function watchMap(map)
  local okS, Structures = pcall(V.require, "Structures")
  local S = (okS and Structures and Structures.peek and Structures.peek(map))
            or false
  local seen = structSeen[map]
  if seen == nil then
    structSeen[map] = S
  elseif seen ~= S then
    structSeen[map] = S
    forgetMap(map)
  end
end

local function setContext(map, neighbors)
  if map then watchMap(map) end
  for _, nb in ipairs(neighbors or {}) do
    if nb.map then watchMap(nb.map) end
  end
  ctx.map = map
  local nbs = ctx.nbs
  for i = #nbs, 1, -1 do nbs[i] = nil end
  for _, nb in ipairs(neighbors or {}) do
    if nb.map then
      nbs[#nbs + 1] = { map = nb.map,
                        ocx = math.floor((tonumber(nb.ox) or 0) / 16 + 0.5),
                        ocz = math.floor((tonumber(nb.oy) or 0) / 16 + 0.5) }
    end
  end
end

local function locate(wcx, wcz)
  local map = ctx.map
  if map and map:inBounds(wcx, wcz) then return map, wcx, wcz end
  for _, nb in ipairs(ctx.nbs) do
    local lx, lz = wcx - nb.ocx, wcz - nb.ocz
    if nb.map:inBounds(lx, lz) then return nb.map, lx, lz end
  end
  return nil
end

local function occluderWorld(wcx, wcz)
  local map, lx, lz = locate(wcx, wcz)
  if not map then return WALL end
  return occluderAt(map, lx, lz)
end

local function floorWorld(wx, wz)
  local map, lx, lz = locate(math.floor(wx / 16), math.floor(wz / 16))
  if not map then return 0 end
  local h = floorAt(map, lx, lz)
  return h > 0 and h or 0
end

-- ------- the masks
--
-- All of them live in ONE texture, a slot each. Making a texture per mask
-- was measured at over half the cost of a mask (a new GPU object for every
-- half cell a lantern walks); uploading into a slot of one that already
-- exists is a sub-rectangle copy. The slot is wider than the widest mask,
-- so the filter never reads a neighbour's light across the gap.

Glow.SLOT = 40
Glow.ATLAS_W, Glow.ATLAS_H = 1024, 512
Glow.MAX_R = 18          -- texels: the widest reach a mask may have (144 px)

local masks = {}          -- key -> { quad, R, stx, stz } or false
local maskCount = 0
local buildsLeft = 0
local atlas = nil         -- the shared Image; false once it cannot be made
local nextSlot = 0
local scratch = {}        -- side -> ImageData, reused for every build
local SLOTS_X = math.floor(Glow.ATLAS_W / Glow.SLOT)
local SLOTS = SLOTS_X * math.floor(Glow.ATLAS_H / Glow.SLOT)

Glow.stats = { sources = 0, built = 0, buildMs = 0, cpuMs = 0, cached = 0 }

local function dropMasks()
  for k, m in pairs(masks) do
    if m and m.img and m.img.release then pcall(m.img.release, m.img) end
    masks[k] = nil
  end
  maskCount = 0
  nextSlot = 0
end

-- Forget every height and every mask: the row was reloaded, or a probe
-- wants a clean start. The per-map forgetting (a map's buildings arriving)
-- is `forgetMap` below.
function Glow.invalidate()
  for k in pairs(occMemo) do occMemo[k] = nil end
  for k in pairs(floorMemo) do floorMemo[k] = nil end
  dropMasks()
end

function forgetMap(map)
  occMemo[map] = nil
  floorMemo[map] = nil
  -- a mask does not record which maps it read, so they all go: this
  -- happens a handful of times per map visit, never per frame
  dropMasks()
end

local function ensureAtlas()
  if atlas == nil then
    local ok, img = pcall(function()
      local d = love.image.newImageData(Glow.ATLAS_W, Glow.ATLAS_H)
      local im = love.graphics.newImage(d)
      im:setFilter("linear", "linear")
      return im
    end)
    atlas = (ok and img) or false
  end
  return atlas or nil
end

-- How much of a source's light reaches each texel around it, as an
-- ImageData with a one-texel clear border (so the linear filter fades a
-- mask to nothing at its edge instead of smearing its last row).
local function buildMask(stx, stz, sh, R, reachPx)
  local T = Glow.TEXEL
  local D = 2 * R + 1
  local blocked, vis = {}, {}
  local cxw, czw = (stx + 0.5) * T, (stz + 0.5) * T
  -- a texel blocks when the cell it lies on stands taller than the flame;
  -- the cells are asked once each (four texels share one)
  local lim = sh + 2
  local c0x = math.floor((cxw - R * T) / 16)
  local c0z = math.floor((czw - R * T) / 16)
  local cw = math.floor((cxw + R * T) / 16) - c0x + 1
  local c1z = math.floor((czw + R * T) / 16)
  local cells = {}
  for cz = c0z, c1z do
    local base = (cz - c0z) * cw - c0x
    for cx = c0x, c0x + cw - 1 do
      cells[base + cx] = occluderWorld(cx, cz) > lim
    end
  end
  for j = -R, R do
    local base = (math.floor((czw + j * T) / 16) - c0z) * cw - c0x
    local row = (j + R) * D + R
    for i = -R, R do
      blocked[row + i] = cells[base + math.floor((cxw + i * T) / 16)]
    end
  end
  local c0 = R * D + R
  blocked[c0] = false
  vis[c0] = 1
  -- outward in diamond rings: every texel's two parents (one step toward
  -- the source along each axis) sit on the ring before it
  for k = 1, 2 * R do
    local ilo = math.max(-R, -k)
    local ihi = math.min(R, k)
    for i = ilo, ihi do
      local ai = i < 0 and -i or i
      local aj = k - ai
      if aj <= R then
        local si = (i > 0 and 1) or (i < 0 and -1) or 0
        for s = -1, 1, 2 do
          if not (aj == 0 and s == 1) then
            local j = aj * s
            local id = (j + R) * D + (i + R)
            if blocked[id] then
              vis[id] = 0
            else
              local sj = (j > 0 and 1) or (j < 0 and -1) or 0
              local v
              if ai == 0 then
                v = vis[(j - sj + R) * D + R]
              elseif aj == 0 then
                v = vis[R * D + (i - si + R)]
              else
                v = (ai * vis[(j + R) * D + (i - si + R)]
                     + aj * vis[(j - sj + R) * D + (i + R)]) / (ai + aj)
              end
              vis[id] = v or 0
            end
          end
        end
      end
    end
  end

  -- one scratch per size, rewritten whole every time (every interior texel
  -- is set below, zeros included; the border is never touched and stays
  -- the clear it was made with)
  local side = D + 2
  local data = scratch[side]
  if not data then
    data = love.image.newImageData(side, side)
    scratch[side] = data
  end
  local r2 = reachPx * reachPx
  local bounce = Glow.BOUNCE
  local val = {}
  for j = -R, R do
    for i = -R, R do
      local dx, dz = i * T, j * T
      local d2 = dx * dx + dz * dz
      local id = (j + R) * D + (i + R)
      local v = 0
      if d2 < r2 then
        local nd2 = d2 / r2
        local win = 1 - nd2 * nd2
        -- a bright core that falls off smoothly to nothing at the reach:
        -- windowed like the lamps (zero slope at the rim, so no ring) but
        -- far softer than their inverse square, because this is a body
        -- glowing rather than a bulb
        local atten = win * win / (1 + 2.5 * nd2)
        if blocked[id] then
          v = -atten            -- settled below, from its open neighbours
        else
          v = atten * (bounce + (1 - bounce) * vis[id])
        end
      end
      val[id] = v
    end
  end
  -- A wall texel takes half the light of its brightest open neighbour.
  -- Without it the linear filter blends every lit floor texel against the
  -- black of the wall beside it and a dark seam runs along the foot of
  -- every wall facing the flame -- and a low wall's top, which the flame
  -- does see, stays black.
  for j = -R, R do
    for i = -R, R do
      local id = (j + R) * D + (i + R)
      local v = val[id]
      if v < 0 then
        local best = 0
        if i > -R then local n = val[id - 1]; if n > best then best = n end end
        if i < R then local n = val[id + 1]; if n > best then best = n end end
        if j > -R then local n = val[id - D]; if n > best then best = n end end
        if j < R then local n = val[id + D]; if n > best then best = n end end
        v = best * 0.5
      end
      if v > 1 then v = 1 elseif v < 0 then v = 0 end
      data:setPixel(i + R + 1, j + R + 1, v, v, v, 1)
    end
  end
  return data
end

local function maskFor(sx, sz, sh, reachPx)
  local T = Glow.TEXEL
  reachPx = math.min(reachPx, Glow.MAX_R * T)
  local R = math.max(1, math.ceil(reachPx / T))
  local stx, stz = math.floor(sx / T), math.floor(sz / T)
  local key = tostring(ctx.map and ctx.map.id) .. ":" .. stx .. ":" .. stz
              .. ":" .. R .. ":" .. math.floor(sh)
  local m = masks[key]
  if m then
    Glow.stats.cached = Glow.stats.cached + 1
    return m
  end
  if m == false then return nil end
  if buildsLeft <= 0 then return nil end
  buildsLeft = buildsLeft - 1
  if maskCount >= Glow.MASK_CACHE or nextSlot >= SLOTS then dropMasks() end
  local t0 = now()
  local t1 = t0
  local ok, entry = pcall(function()
    local data = buildMask(stx, stz, sh, R, reachPx)
    t1 = now()
    local side = 2 * R + 3
    local A = ensureAtlas()
    if A then
      local slot = nextSlot
      local ax = (slot % SLOTS_X) * Glow.SLOT
      local ay = math.floor(slot / SLOTS_X) * Glow.SLOT
      if pcall(A.replacePixels, A, data, 1, 1, ax, ay) then
        nextSlot = nextSlot + 1
        return { tex = A, quad = love.graphics.newQuad(ax, ay, side, side,
                                                       Glow.ATLAS_W,
                                                       Glow.ATLAS_H) }
      end
      -- a LOVE that cannot upload a sub-rectangle: a texture per mask
      atlas = false
    end
    local im = love.graphics.newImage(data)
    im:setFilter("linear", "linear")
    return { tex = im, img = im }
  end)
  local t2 = now()
  Glow.stats.built = Glow.stats.built + 1
  Glow.stats.buildMs = Glow.stats.buildMs + (t2 - t0) * 1000
  Glow.stats.cpuMs = (Glow.stats.cpuMs or 0) + (t1 - t0) * 1000
  if not ok then
    masks[key] = false
    return nil
  end
  entry.R, entry.stx, entry.stz = R, stx, stz
  masks[key] = entry
  maskCount = maskCount + 1
  return entry
end

-- ------- the field

local field = nil        -- the canvas, false once it could not be made

local function ensureField()
  if field == nil then
    local ok, c = pcall(RenderTarget.new, Glow.SIZE, Glow.SIZE)
    field = (ok and c) or false
    if field then pcall(field.setFilter, field, "linear", "linear") end
  end
  return field or nil
end

-- Draw every source into the field around (cx, cz) and hand the result to
-- the scene shader through Voxel3D.glow. `list` entries carry x, z (world
-- px), h (flame height), reach (px), color, and a (final strength).
-- Probe knobs (tests/glow_cost_probe.lua), nil in play: "skip" draws
-- nothing into the field, "dark" draws it and sends a gain of zero.
Glow.debug = nil

local function render(list, cx, cz)
  Voxel3D.glow = nil
  if #list == 0 or Glow.debug == "skip" then return end
  local c = ensureField()
  if not c then return end
  local T, N = Glow.TEXEL, Glow.SIZE
  local fx0 = (math.floor(cx / T) - N / 2) * T
  local fz0 = (math.floor(cz / T) - N / 2) * T
  local span = N * T
  buildsLeft = Glow.BUILDS_PER_FRAME
  Glow.stats.sources = 0
  local ok = pcall(function()
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setScissor()
    love.graphics.setShader()
    love.graphics.setCanvas(c)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setBlendMode("add", "premultiplied")
    for _, s in ipairs(list) do
      if s.x + s.reach > fx0 and s.x - s.reach < fx0 + span
         and s.z + s.reach > fz0 and s.z - s.reach < fz0 + span then
        local m = maskFor(s.x, s.z, s.h, s.reach)
        if m then
          -- the mask's first texel (inside its border) is the source
          -- texel's column minus R; shifted by where in its texel the
          -- source actually stands, so a walking light glides instead of
          -- stepping half a cell at a time
          local ox = (s.x / T) - (m.stx + 0.5)
          local oz = (s.z / T) - (m.stz + 0.5)
          local px = (m.stx - m.R - 1) - fx0 / T + ox
          local pz = (m.stz - m.R - 1) - fz0 / T + oz
          local a = s.a * Glow.SCALE
          love.graphics.setColor(s.color[1] * a, s.color[2] * a,
                                 s.color[3] * a, 1)
          if m.quad then
            love.graphics.draw(m.tex, m.quad, px, pz)
          else
            love.graphics.draw(m.tex, px, pz)
          end
          Glow.stats.sources = Glow.stats.sources + 1
        end
      end
    end
    love.graphics.pop()
  end)
  if not ok then
    pcall(love.graphics.pop)
    return
  end
  Voxel3D.glow = {
    tex = c,
    rect = { fx0, fz0, 1 / span, 1 / span },
    gain = (Glow.debug == "dark") and 0 or (Glow.STRENGTH / Glow.SCALE),
    height = Glow.HEIGHT,
  }
end

-- ------- how much a glow counts, here and now
--
-- Light only shows against dark: a Charmander at noon lights nothing, the
-- same Charmander at midnight lights the road. Outdoors that is the hour
-- (and the weather); a cave is always dark; a house is lit by its own room.
Glow.INDOOR = 0.35

local function darkness(map)
  if not (map and map.def) then return 0 end
  if Glow.isCave(map) then return 1 end
  if not Map.isOutdoor(map.def) then return Glow.INDOOR end
  local okW, night = pcall(DayNight.windowLight)
  night = (okW and tonumber(night)) or 0
  if DayNight.isCanopy(map) then night = math.max(night, 0.5) end
  local d = 0.08 + 0.92 * night + 0.25 * (DayNight.overcast or 0)
  if d > 1 then d = 1 end
  return d
end

Glow.darkness = darkness

local function seedOf(e)
  local s = tostring(e.id or e.species or "")
  local h = 0
  for i = 1, #s do h = (h * 31 + s:byte(i)) % 1000 end
  return h / 37
end

local function speciesOf(e)
  if e.pikachuFollower then return "PIKACHU" end
  return e.species
end

-- ------- the dark maps
--
-- The engine's own flag, read rather than re-derived: ROCK_TUNNEL before
-- FLASH (OverworldState.dark, field.darkMaps).
local function flashLit(G)
  return G and G.save and G.save.flashLit and true or false
end

-- Whether the lights can actually be drawn: the row, and a scene shader
-- that took the field (Voxel3D's ladder drops it first on a driver that
-- refuses it). Darkening a cave with no light to push back is worse than
-- leaving it lit, so everything that takes light away asks this first.
local function lightOK()
  return Glow.enabled() and not Voxel3D.glowRefused
end

function Glow.ambient(map, tint, outdoor)
  if outdoor or not lightOK() or not Glow.isCave(map) then return tint end
  if type(tint) ~= "table" or not tint[3] then return tint end
  local G = game()
  local ow = G and G.overworld
  local here = ow and ow.map == map
  local k = Glow.CAVE_AMBIENT
  if here and ow.dark then
    k = Glow.DARK_AMBIENT
  elseif here and flashLit(G) then
    k = Glow.FLASH_AMBIENT
  end
  local c = Glow.CAVE_TINT
  return { tint[1] * k * c[1], tint[2] * k * c[2], tint[3] * k * c[3] }
end

-- ------- lightning
--
-- The sky already flashes (lib/Weather.lua) and deliberately goes no
-- further: a full-frame plate read as a bomb. What a close strike DOES do
-- is light the ground for a tenth of a second, cold, so the world is lit
-- the way it is in a photograph taken in the dark. Returned as a tint to
-- add: small, and nothing at all for the half-strength (distant) flashes.
Glow.BOLT = { 0.16, 0.19, 0.26 }

function Glow.boltFill()
  if not Glow.enabled() then return nil end
  local okW, Weather = pcall(V.require, "Weather")
  if not (okW and Weather and Weather.flash) then return nil end
  local okF, f = pcall(Weather.flash)
  if not (okF and f and f >= 1) then return nil end
  return Glow.BOLT
end

-- ------- sources: the world

local list = {}

-- The fight's edges (Glow.observeBattle, below): the move being thrown and
-- the blow that landed. Up here because the free-roam frame resets it.
local fight = { prev = false, move = nil, burst = nil, battle = nil }

local function push(x, z, h, em, a, prio)
  if a <= 0.004 then return end
  local s = list[#list + 1] or {}
  s.x, s.z, s.h = x, z, h
  s.reach = em.reach * 16
  s.color = em.color
  s.a = a
  s.prio = prio
  list[#list + 1] = s
end

local function clearList()
  for i = #list, 1, -1 do list[i] = nil end
end

local function sortAndCap(cx, cz)
  for _, s in ipairs(list) do
    local dx, dz = s.x - cx, s.z - cz
    s.d2 = dx * dx + dz * dz - (s.prio or 0) * 1e7
  end
  table.sort(list, function(a, b) return a.d2 < b.d2 end)
  for i = #list, Glow.MAX_SOURCES + 1, -1 do list[i] = nil end
end

-- Every lit door on `map`, whose origin is (ox, oz) world px from the map
-- underfoot. Doors out of a building into the night: the warp's cell, on an
-- outdoor map, into a room that is not a cave.
local function doors(G, map, ox, oz, a)
  if a <= 0.02 then return end
  local def = map and map.def
  if not (def and Map.isOutdoor(def)) then return end
  local maps = G.data and G.data.maps or {}
  for _, w in ipairs(def.warps or {}) do
    local dest = w.destMap or w.map or w.dest or w.to or w.target
    local dd = dest and maps[dest]
    if dd and not Map.isOutdoor(dd) and not Glow.CAVES[dest] then
      local x = (tonumber(w.x) or 0) * 16 + 8 + ox
      local z = (tonumber(w.y) or 0) * 16 + 8 + oz
      push(x, z, floorWorld(x, z) + Glow.FLAME,
           { reach = Glow.DOOR_REACH, color = doorColor(dest) },
           Glow.DOOR_POWER * a, 0)
    end
  end
end

-- The free-roam frame. Called by VoxelScene.render ahead of its scene,
-- with the same focus the rest of the frame was fitted to.
function Glow.prepareWorld(state, cx, cz)
  Voxel3D.glow = nil
  if not (lightOK() and Voxel3D.glowLive ~= false) then return end
  if not (state and state.map) then return end
  local G = game()
  if not G then return end
  setContext(state.map, state.neighbors)
  clearList()
  local t = now()
  local dark = darkness(state.map)
  local lit = flashLit(G) and Glow.isCave(state.map)

  -- the companion: this mod's follower, or the engine's own Pikachu
  local companion = nil
  for _, e in ipairs(state.entities or {}) do
    if e.dsFollower or e.pikachuFollower then companion = e break end
  end
  local carrier = companion or state.player
  if carrier then
    local x, z = (carrier.px or 0) + 8, (carrier.py or 0) + 8
    local h = floorWorld(x, z) + Glow.FLAME
    if lit then push(x, z, h, Glow.FLASH, Glow.FLASH.power, 3) end
  end

  for _, e in ipairs(state.entities or {}) do
    local em = Glow.EMITTERS[speciesOf(e) or ""]
    -- the player carries nobody's light but FLASH's (above), and a lead
    -- who is not out walking still shines from the pocket it is in: when
    -- the companion is hidden (surfing, cycling) the player carries it
    if not em and e == state.player and not companion then
      local lead = G.save and G.save.party and G.save.party[1]
      em = lead and (lead.hp or 0) > 0 and Glow.EMITTERS[lead.species] or nil
      if em then em = { reach = em.reach * 0.8, color = em.color,
                        power = em.power * 0.6, kind = em.kind } end
    end
    if em and (e ~= state.player or not companion) then
      local x, z = (e.px or 0) + 8, (e.py or 0) + 8
      local a = em.power * dark * flicker(em.kind, t, seedOf(e))
      -- the companion is the hero light; a wild one is a little less
      local mine = (e == companion or e == state.player)
      if not mine then a = a * 0.75 end
      push(x, z, floorWorld(x, z) + Glow.FLAME, em, a, mine and 2 or 0)
    end
  end
  for _, g in ipairs(state.ghosts or {}) do
    local e = g.npc
    local em = e and Glow.EMITTERS[speciesOf(e) or ""]
    if em then
      local x = (e.px or 0) + 8 + (tonumber(g.ox) or 0)
      local z = (e.py or 0) + 8 + (tonumber(g.oy) or 0)
      push(x, z, floorWorld(x, z) + Glow.FLAME, em,
           em.power * 0.75 * darkness(g.map) * flicker(em.kind, t, seedOf(e)), 0)
    end
  end

  -- the doors, at night
  local okW, night = pcall(DayNight.windowLight)
  night = (okW and tonumber(night)) or 0
  doors(G, state.map, 0, 0, night)
  for _, nb in ipairs(state.neighbors or {}) do
    doors(G, nb.map, tonumber(nb.ox) or 0, tonumber(nb.oy) or 0, night)
  end

  sortAndCap(cx, cz)
  local t1 = now()
  render(list, cx, cz)
  local t2 = now()
  Glow.stats.prepMs = (t1 - t) * 1000
  Glow.stats.renderMs = (t2 - t1) * 1000
end

-- What the last frame lit, for the probes: { x, z, reach, a } per source.
function Glow.debugList()
  local out = {}
  for i, s in ipairs(list) do
    out[i] = { x = s.x, z = s.z, reach = s.reach, a = s.a, h = s.h }
  end
  return out
end

-- ------- sources: the arena
--
-- The fight is staged on the map itself (BattleArena), so the same field
-- lights it: both Pokemon glow by their species where they stand, and a
-- move of the right kind lights the attacker as it is thrown and the
-- defender as it lands.

local MOVE_KIND = {
  FIRE = E(FIRE, 5.0, 1.6, "fire"),
  ELECTRIC = E(SPARK, 5.0, 1.6, "spark"),
  ICE = E(FROST, 4.5, 1.2, "pulse"),
  PSYCHIC = E(PSY, 4.5, 1.2, "pulse"),
  GHOST = E(GHOST, 4.5, 1.2, "ghost"),
  DRAGON = E({ 0.56, 0.62, 1.00 }, 4.5, 1.2, "pulse"),
}
local MOVE_NAMED = {
  FLASH = E(Glow.FLASH_COLOR, 9.0, 2.0, "steady"),
  SOLARBEAM = E({ 1.00, 0.92, 0.55 }, 6.0, 1.8, "steady"),
  HYPER_BEAM = E({ 1.00, 0.86, 0.66 }, 6.0, 1.8, "steady"),
  SELFDESTRUCT = E({ 1.00, 0.62, 0.28 }, 7.0, 2.0, "fire"),
  EXPLOSION = E({ 1.00, 0.62, 0.28 }, 8.0, 2.2, "fire"),
  AURORA_BEAM = E({ 0.70, 1.00, 0.86 }, 5.0, 1.4, "pulse"),
}

function Glow.observeBattle(battle, dt)
  dt = dt or 0
  fight.battle = battle
  if not battle then
    fight.prev, fight.move, fight.burst = false, nil, nil
    return
  end
  local playing = battle.animPlaying and true or false
  if playing and not fight.prev then
    local name = battle.animName
    local em = name and MOVE_NAMED[name]
    if not em then
      local data = battle.data and battle.data.moves
      local def = data and name and data[name]
      local okB, Box = pcall(V.require, "BattleBoxXY")
      local tname = def and okB and Box and Box.typeName
                    and Box.typeName(def.type) or nil
      em = tname and MOVE_KIND[tostring(tname):upper()] or nil
    end
    if em then
      local att = battle.animAttackerIsPlayer and "player" or "enemy"
      fight.move = { em = em, from = att,
                     to = (att == "player") and "enemy" or "player", t = 0 }
    else
      fight.move = nil
    end
  end
  if fight.move then fight.move.t = fight.move.t + dt end
  if not playing and fight.prev and fight.move then
    -- the anim's end is the blow's tell (the HP bar is written a second
    -- earlier -- the lesson BattleShot and BattleHitFX both learned)
    fight.burst = { em = fight.move.em, at = fight.move.to, t = 0 }
    fight.move = nil
  end
  if fight.burst then
    fight.burst.t = fight.burst.t + dt
    if fight.burst.t > 1.2 then fight.burst = nil end
  end
  fight.prev = playing
end

-- The arena's frame. Called by BattleScene.render ahead of its scene; the
-- battle itself is the one OverworldBattle's tick handed observeBattle.
function Glow.prepareBattle(host, neighbors, arena, groundY)
  Voxel3D.glow = nil
  if not (lightOK() and Voxel3D.glowLive ~= false and host and arena) then
    return
  end
  local battle = fight.battle
  setContext(host, neighbors)
  clearList()
  local t = now()
  local dark = darkness(host)
  local y = (tonumber(groundY) or 0) + Glow.FLAME
  local spots = { player = arena.player, enemy = arena.enemy }
  for side, at in pairs(spots) do
    local b = battle and battle[side]
    local species = b and b.mon and b.mon.species
    local em = species and Glow.EMITTERS[species]
    if em and at then
      push(at[1], at[2], y, em,
           em.power * dark * flicker(em.kind, t, side == "player" and 1 or 7), 1)
    end
  end
  -- a move lights up whatever the hour: a Flamethrower at noon still
  -- throws orange on the grass under it, only less of it
  local moveDark = math.max(dark, 0.45)
  local mv = fight.move
  if mv and spots[mv.from] then
    local at = spots[mv.from]
    local ramp = math.min(1, mv.t / 0.35)
    push(at[1], at[2], y, mv.em,
         mv.em.power * 0.7 * ramp * moveDark * flicker(mv.em.kind, t, 3), 2)
  end
  local bu = fight.burst
  if bu and spots[bu.at] then
    local at = spots[bu.at]
    push(at[1], at[2], y, bu.em,
         bu.em.power * math.exp(-bu.t * 3.2) * moveDark
         * flicker(bu.em.kind, t, 5), 2)
  end
  local mid = arena.mid or arena.player or { 0, 0 }
  sortAndCap(mid[1], mid[2])
  render(list, mid[1], mid[2])
end

-- ------- the palette's darkness, while the light owns it (see the header)

Glow.ownsDark = false

local function wantsOwnership()
  return lightOK() and (Voxel.level or 0) > 0
         and Voxel3D.available and Voxel3D.available() and true or false
end

function Glow.install()
  local PaletteFX = require("src.render.PaletteFX")
  if PaletteFX.terrariumGlowHook then return end
  local innerDark = PaletteFX.setDarkWorld
  local innerShade = PaletteFX.setShadeMap
  -- what the engine ASKED for, so ownership can hand it back unchanged
  Glow.wantDark = PaletteFX.darkWorld and PaletteFX.darkWorld() or false
  function PaletteFX.setDarkWorld(on)
    Glow.wantDark = on and true or false
    return innerDark(Glow.wantDark and not Glow.ownsDark)
  end
  function PaletteFX.setShadeMap(map)
    if map ~= nil and map == PaletteFX.DARK_BGP and Glow.ownsDark then
      map = nil
    end
    return innerShade(map)
  end
  PaletteFX.terrariumGlowHook = true
end

-- ------- per frame
--
-- The flag the scene shader's variant is keyed on, the mesher's progress
-- (a finished build changes what blocks), and the dark's owner.
local lastPending = 0
local failed = false

local function tick()
  Voxel3D.glowWanted = Glow.enabled()
  -- the map underfoot finishing its first full build (see watchMap)
  local okC, ChunkMesher = pcall(V.require, "ChunkMesher")
  if okC and ChunkMesher and ChunkMesher.pending then
    local okP, pend = pcall(ChunkMesher.pending)
    pend = (okP and tonumber(pend)) or 0
    local map = ctx.map
    if lastPending > 0 and pend == 0 and map and not settled[map] then
      settled[map] = true
      forgetMap(map)
    end
    lastPending = pend
  end
  local owns = wantsOwnership()
  if owns ~= Glow.ownsDark then
    Glow.ownsDark = owns
    -- hand the engine's own request back through the wrap: setDark rebuilds
    -- the map's bakes when the effective palette actually changes
    local G = game()
    local ow = G and G.overworld
    if ow and ow.setDark and ow.map then
      pcall(ow.setDark, ow, ow.dark)
    end
  end
end

function Glow.update()
  if failed then return end
  local ok, err = pcall(tick)
  if ok then return end
  failed = true
  Voxel3D.glowWanted = false
  V.mod.log:warn("glow failed: %s -- the lights are off for this session",
                 tostring(err))
end

return Glow
