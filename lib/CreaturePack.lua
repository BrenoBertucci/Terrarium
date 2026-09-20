-- CreaturePack: creatures that are nobody's property, standing in for the mons.
--
-- lib/MonPack.lua serves Generation 5 battle sprites out of assets/mons. That
-- art is Nintendo's: it cannot be redistributed, it is in .gitignore, it never
-- ships in a package, and it is the last borrowed drawing the battle wears.
-- This is the other shelf -- 411 creatures from Tuxemon, a libre
-- monster-catching game, CC BY-SA 4.0 and credited by artist in
-- assets/creatures/CREDITS.md. They are original designs that read as the same
-- KIND of thing without being any of it.
--
-- THE PAIRING IS EARNED, NOT DRAWN FROM A HAT. A creature is chosen for a
-- species by what the game itself says about that species: its ELEMENT (the
-- engine's own `def.types`, mapped onto Tuxemon's thirteen) and HOW FAR ALONG
-- ITS LINE it stands (walked out of `def.evolutions`, so a first form gets a
-- first form). Shape breaks the remaining ties -- a serpent for something
-- shaped like a snake. The result is stable: the same save shows the same
-- creature for the same species every session, because the walk is ordered and
-- the tie-break is a hash of the species' own name rather than a clock.
--
-- WHY AT RUNTIME. The pairing needs the species table, and in this engine that
-- table is extracted from the ROM the player dumped (src/import/RomExtractor
-- builds `data.pokemon` with `types` and `evolutions`). A build script has no
-- ROM and no right to one, so tools/install_creature_pack.py only lays the
-- shelf out and the choosing happens here, once, the first time a fight needs
-- a picture.
--
-- One sheet per creature, 128x88, three regions used (front, back, icon) --
-- copied byte for byte from upstream, which is the easiest way to honour a
-- share-alike licence. The quadrant is cut here, not on disk.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local CreaturePack = {}

-- NINTENDO first, so it is the DEFAULT. This row swaps the art of every mon in
-- the game, and a row like that does not get to be on by default just because
-- the alternative is the licensable one: assets/mons is what the player
-- installed and what their save looks like, and a mod that quietly replaced it
-- would be answering a question nobody asked.
CreaturePack.setting = ModSetting.new("creatures", "CRIATURAS",
                                      { "mons", "free" },
                                      { "NINTENDO", "LIVRE" })

function CreaturePack.enabled()
  return CreaturePack.setting:get() == "free"
end

CreaturePack.ASSET_DIR = "assets/creatures/"

-- ------- how big a creature stands
--
-- MonPack's SCALE (2/3) and MENU_SCALE (0.5) are tuned for 96-pixel art: they
-- land a mon at 64 GB pixels in the arena and 48 on the menu. This shelf draws
-- at 64, so the same numbers would put every creature a quarter shorter than
-- the mon it replaces -- next to a 56-pixel engine pic that reads as a
-- different game's sprite dropped in. 1 and 0.75 are the same two heights from
-- 64-pixel art, and both stay integer once MonPack.DENSITY (3) is counted,
-- which is what keeps the pixels square.
CreaturePack.SCALE = 1
CreaturePack.MENU_SCALE = 0.75

-- Sheet geometry, measured (tools/install_creature_pack.py records it too).
CreaturePack.FRONT = { 0, 0, 64, 64 }
CreaturePack.BACK = { 64, 0, 64, 64 }
CreaturePack.ICON = { 0, 64, 24, 24 }

-- ------- the two vocabularies
--
-- Generation 1's fifteen types onto Tuxemon's thirteen. Three of them have no
-- clean partner and are given the nearest one that exists: BUG shares wood
-- with GRASS (Tuxemon has no insect element), ROCK shares earth with GROUND,
-- and DRAGON has nothing at all -- it leans on cosmic and is pulled back by
-- the SHAPE bonus below, which is the only thing that will actually find the
-- dragons in the pool.
local TYPE_MAP = {
  NORMAL = "normal", FIRE = "fire", WATER = "water", ELECTRIC = "lightning",
  GRASS = "wood", ICE = "frost", FIGHTING = "heroic", POISON = "venom",
  GROUND = "earth", FLYING = "sky", PSYCHIC = "cosmic", BUG = "wood",
  ROCK = "earth", GHOST = "shadow", DRAGON = "cosmic",
}

-- A shape worth reaching for when the species' type says so. Only the ones
-- that are a real signal -- most of Tuxemon's fourteen silhouettes say nothing
-- about a Kanto species and are left out rather than guessed at.
local SHAPE_HINT = {
  DRAGON = "dragon", WATER = "piscine", FLYING = "flier", BUG = "grub",
}

local STAGE_DEPTH = { basic = 0, stage1 = 1, stage2 = 2, standalone = 0 }

-- ------- the shelf
local pool = nil            -- data/creature_pool.lua, once
local assigned = nil        -- species key -> creature slug
local images = {}           -- "front:slug" -> Image | false
local sheets = {}           -- slug -> ImageData | false
local stats = { paired = 0, served = 0, missed = 0, last = nil }

local function loadPool()
  if pool == nil then
    local ok, p = pcall(V.data, "creature_pool")
    pool = (ok and type(p) == "table" and #p > 0) and p or false
  end
  return pool or nil
end

function CreaturePack.available()
  return CreaturePack.enabled() and loadPool() ~= nil
end

-- A small, stable string hash. Deterministic across sessions and machines --
-- which love.math.random seeded by anything would not be, and which is the
-- whole difference between "this species is that creature" and "this species
-- is a different creature every time you load".
local function hash(s)
  local h = 5381
  for i = 1, #s do
    h = (h * 33 + s:byte(i)) % 2147483647
  end
  return h
end

-- ------- how far along its own line a species stands
--
-- `def.evolutions` says what a species turns INTO, so the depth has to be
-- walked backwards: anything nothing evolves into is a first form, and every
-- step out from there is one deeper. Cycles cannot happen in this data but the
-- walk is bounded anyway -- a malformed dataset should cost a wrong picture,
-- never a hang at the start of a battle.
local function depths(dex)
  local parent = {}
  for id, def in pairs(dex) do
    for _, evo in ipairs(def.evolutions or {}) do
      local into = evo.species or evo.into or evo.target or evo.id
      if type(into) == "string" then parent[into] = id end
    end
  end
  local out = {}
  for id in pairs(dex) do
    local d, at, guard = 0, id, 0
    while parent[at] and guard < 8 do
      d, at, guard = d + 1, parent[at], guard + 1
    end
    out[id] = d
  end
  return out
end

-- ------- the pairing
--
-- Greedy over the species in a fixed order, each taking the best free creature
-- it can find. Greedy and not optimal on purpose: an assignment problem solved
-- exactly would pair better on paper and would also mean that adding one
-- creature upstream reshuffles the whole Pokedex. This way a species keeps its
-- creature as long as the pool keeps it.
local function score(def, depth, mon)
  local s = 0
  local types = def.types or {}
  local want1 = types[1] and TYPE_MAP[types[1]]
  local want2 = types[2] and TYPE_MAP[types[2]]
  for i, t in ipairs(mon.types or {}) do
    if want1 and t == want1 then s = s + (i == 1 and 6 or 4) end
    if want2 and t == want2 then s = s + (i == 1 and 3 or 2) end
  end
  -- the line: a first form should look like a first form
  local md = STAGE_DEPTH[mon.stage] or 0
  s = s + (3 - math.min(3, math.abs(depth - md)))
  -- and the silhouette, where the type actually implies one
  for _, t in ipairs(types) do
    if SHAPE_HINT[t] and mon.shape == SHAPE_HINT[t] then s = s + 2 end
  end
  return s
end

local function keyOf(species)
  if type(species) ~= "string" then return nil end
  local k = species:lower():gsub("[^a-z0-9]", "")
  return (#k > 0) and k or nil
end

-- Build the whole map in one pass. `dex` is the engine's data.pokemon.
function CreaturePack.pair(dex)
  local p = loadPool()
  if not (p and type(dex) == "table") then return nil end
  local ids = {}
  for id, def in pairs(dex) do
    if type(def) == "table" then ids[#ids + 1] = id end
  end
  if #ids == 0 then return nil end
  table.sort(ids)
  local depth = depths(dex)

  local taken, map = {}, {}
  for _, id in ipairs(ids) do
    local def = dex[id]
    local bestSlug, bestScore
    for i = 1, #p do
      local mon = p[i]
      if not taken[mon.slug] then
        local sc = score(def, depth[id] or 0, mon) * 1000
                   -- the tie-break: this species' own name against this
                   -- creature's, so the order of the pool cannot decide it
                   + (hash(id .. "/" .. mon.slug) % 997)
        if not bestScore or sc > bestScore then bestScore, bestSlug = sc, mon.slug end
      end
    end
    if bestSlug then
      taken[bestSlug] = true
      local k = keyOf(id)
      if k then map[k] = bestSlug end
    end
  end
  assigned = map
  stats.paired = 0
  for _ in pairs(map) do stats.paired = stats.paired + 1 end
  return map
end

-- Hand the engine's dataset over the first time anything has one. Cheap to
-- call every battle: the map is built once and kept.
function CreaturePack.bind(data)
  if assigned or not CreaturePack.available() then return assigned end
  local dex = data and data.pokemon
  if type(dex) ~= "table" then return nil end
  local ok, map = pcall(CreaturePack.pair, dex)
  return ok and map or nil
end

function CreaturePack.slugFor(species)
  if not CreaturePack.available() then return nil end
  local k = keyOf(species)
  return k and assigned and assigned[k] or nil
end

-- ------- the picture
local function sheetData(slug)
  local held = sheets[slug]
  if held ~= nil then return held or nil end
  local rel = CreaturePack.ASSET_DIR .. slug .. ".png"
  local data = nil
  -- the mod's own reader first: a mod folder may live inside a mounted .love
  -- archive, which love.image cannot open by path
  if V.mod and V.mod.read then
    local okR, bytes = pcall(function() return V.mod:read(rel) end)
    if okR and bytes then
      local okF, fd = pcall(love.filesystem.newFileData, bytes, slug .. ".png")
      if okF and fd then
        local okI, id = pcall(love.image.newImageData, fd)
        if okI then data = id end
      end
    end
  end
  if not data then
    local okI, id = pcall(love.image.newImageData, (V.path or "") .. "/" .. rel)
    if okI then data = id end
  end
  sheets[slug] = data or false
  return data
end

-- Cut one region and trim it to its own opaque box.
--
-- The trim is not tidiness: lib/MonPack's callers place a sprite by its
-- dimensions (the billboard, the party icon, the ribbon medallion all measure
-- what they are handed), and assets/mons is cropped to the bounding box for
-- exactly that reason. An untrimmed 64x64 quadrant would hang every creature
-- in the arena by the empty air around it.
local function cut(slug, region)
  local src = sheetData(slug)
  if not src then return nil end
  local rx, ry, rw, rh = region[1], region[2], region[3], region[4]
  local sw, sh = src:getDimensions()
  if rx + rw > sw or ry + rh > sh then return nil end
  local x0, y0, x1, y1 = rw, rh, -1, -1
  for y = 0, rh - 1 do
    for x = 0, rw - 1 do
      local _, _, _, a = src:getPixel(rx + x, ry + y)
      if a > 0.02 then
        if x < x0 then x0 = x end
        if y < y0 then y0 = y end
        if x > x1 then x1 = x end
        if y > y1 then y1 = y end
      end
    end
  end
  if x1 < x0 or y1 < y0 then return nil end     -- the region is empty
  local w, h = x1 - x0 + 1, y1 - y0 + 1
  local okN, out = pcall(love.image.newImageData, w, h)
  if not (okN and out) then return nil end
  local okP = pcall(out.paste, out, src, 0, 0, rx + x0, ry + y0, w, h)
  if not okP then return nil end
  local okG, img = pcall(love.graphics.newImage, out)
  if not (okG and img) then return nil end
  pcall(img.setFilter, img, "nearest", "nearest")
  return img
end

-- The sprite for a species, front or back; nil when this shelf has none.
-- Same contract as MonPack.image, which is what lets MonPack ask this first
-- and change nothing else about how a battler is drawn.
function CreaturePack.image(species, back)
  local slug = CreaturePack.slugFor(species)
  if not slug then stats.missed = stats.missed + 1; return nil end
  local id = (back and "back" or "front") .. ":" .. slug
  local held = images[id]
  if held ~= nil then
    if held then stats.served = stats.served + 1; stats.last = slug end
    return held or nil
  end
  local img = cut(slug, back and CreaturePack.BACK or CreaturePack.FRONT)
  images[id] = img or false
  if img then
    stats.served = stats.served + 1
    stats.last = slug
  else
    stats.missed = stats.missed + 1
  end
  return img
end

function CreaturePack.has(species, back)
  return CreaturePack.image(species, back) ~= nil
end

function CreaturePack.debug()
  return { on = CreaturePack.available(), paired = stats.paired,
           served = stats.served, missed = stats.missed, last = stats.last,
           pool = loadPool() and #loadPool() or 0 }
end

-- OPTIONS row. Flipping it drops the cut images so the next draw re-cuts from
-- the other shelf; the PAIRING is kept, because it is expensive to build and
-- does not change when the row does.
function CreaturePack.setting:row()
  local self_ = self
  return {
    id = ((V.mod and V.mod.id) or "TERRARIUM") .. ":" .. self.key,
    label = self.label,
    value = function() return self_.labels[self_:read()] end,
    step = function(game, dir)
      self_:cycle(game, dir)
      images = {}
      return true
    end,
  }
end

function CreaturePack.onOptionsChanged(value)
  CreaturePack.setting:sync(value)
  images = {}
end

return CreaturePack
