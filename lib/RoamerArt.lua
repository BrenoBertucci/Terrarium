-- Overworld art for a wild Pokemon, out of the art the game already has.
--
-- Gen 1 draws no Pokemon on the map.  Eleven species have an overworld
-- sheet because a script stands one somewhere (the Vermilion Machop, the
-- Snorlax, Bill's Pikachu); the other hundred and forty have exactly one
-- drawing each and it is the battle FRONT pic.  So that is what a roamer
-- wears, resampled down to the 16x16 cell every other character on the map
-- occupies.
--
-- Baked to a real 16x96 sheet on disk rather than kept as a canvas in
-- memory, and that is the whole reason this file exists.  A sheet at a PATH
-- is a sprite the ENGINE understands: SpriteRenderer loads it, the OBP bake
-- recolors it, the SGB zone shader colors it out of the map's own palette,
-- the voxel pass cuts its card from it, the sun pass throws its silhouette.
-- Every one of those is keyed on the image path.  An Image conjured at
-- runtime would have needed each of them taught about it; a file needs none
-- of them touched.
--
-- Baked once and kept: the sheet lands under the engine's own derived-asset
-- root (save/mod-derived/<id>/), where a hot reload and an uninstall already
-- know to look, and the revision in each filename means a change to this
-- generator supersedes what an older cut left there rather than being
-- mistaken for it.
--
-- Better art wins outright.  A sheet shipped in the mod's own
-- assets/roamers/<SPECIES>.png is used as-is and nothing is generated, so a
-- pixel artist can replace one species, or all of them, without touching a
-- line of this.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Assets = require("src.render.Assets")

local RoamerArt = {}

RoamerArt.FRAME = 16          -- the walk grid's own cell, like every sprite
RoamerArt.FRAMES = 6          -- stand down/up/left then walk down/up/left

-- Bumped when anything below changes what a sheet looks like.  It rides in
-- the filename, so an old bake is never picked up as a current one -- and
-- the old file is left alone rather than deleted, because a player who
-- pinned one on purpose should keep it.
RoamerArt.REV = "1"

local DERIVED = "save/mod-derived/DRAMATIC_SHAPE/roamers/"
local SHIPPED = "assets/roamers/"

-- The three shades a Game Boy OBJ can actually show.  Color 0 is
-- transparent in hardware -- which is why every overworld sheet in this
-- game is drawn in 170/85/0 and nothing lighter -- so a front pic's four
-- shades fold onto three, with its white going to the lightest visible one
-- rather than to a hole in the middle of the mon.
local LIGHT, MID, DARK = 170 / 255, 85 / 255, 0

-- One source pixel's shade, or nil when it is background.
--
-- `keyWhite` is the fallback for a pic with no alpha channel at all: there
-- the silhouette can only be told from the paper by its colour, so white
-- becomes background and an enclosed white belly becomes a hole.  Nothing
-- in this game takes that path -- the extractor keys the outside to alpha 0
-- and leaves interior whites opaque, which is exactly the distinction this
-- needs -- but a total conversion's own art might.
local function shadeAt(src, x, y, keyWhite)
  local r, _, _, a = src:getPixel(x, y)
  if a < 0.5 then return nil end
  if r > 0.83 then return keyWhite and nil or LIGHT end
  if r > 0.5 then return LIGHT end
  if r > 0.17 then return MID end
  return DARK
end

-- The box the drawing actually occupies, and whether the pic keys its
-- background by alpha or by colour.  Both come out of one walk.
local function contentBox(src)
  local sw, sh = src:getDimensions()
  local clear = 0
  for y = 0, sh - 1 do
    for x = 0, sw - 1 do
      local _, _, _, a = src:getPixel(x, y)
      if a < 0.5 then clear = clear + 1 end
    end
  end
  local keyWhite = clear == 0
  local x0, y0, x1, y1 = sw, sh, -1, -1
  for y = 0, sh - 1 do
    for x = 0, sw - 1 do
      if shadeAt(src, x, y, keyWhite) then
        if x < x0 then x0 = x end
        if y < y0 then y0 = y end
        if x > x1 then x1 = x end
        if y > y1 then y1 = y end
      end
    end
  end
  if x1 < x0 or y1 < y0 then return nil end
  return { x0, y0, x1, y1 }, keyWhite
end

-- Resample the box down to dw x dh, one vote per destination pixel.
--
-- Not an average.  Averaging four shades produces shades that are not any
-- of the four, and the whole point of staying on the DMG ramp is that the
-- OBP bake and the zone shader can then colour this sheet exactly like the
-- sheets beside it.  So each destination pixel takes the shade its source
-- block is MOST made of -- with the outline given a low bar, because at
-- this size the outline is most of what makes a mon recognisable and a
-- plain majority erases it (a one-pixel line inside a 3x3 block is never
-- the majority of anything).
local function resample(src, box, keyWhite, dw, dh)
  local bx, by = box[1], box[2]
  local bw, bh = box[3] - box[1] + 1, box[4] - box[2] + 1
  local out = {}
  for dy = 0, dh - 1 do
    for dx = 0, dw - 1 do
      local sx0 = bx + math.floor(dx * bw / dw)
      local sx1 = bx + math.ceil((dx + 1) * bw / dw) - 1
      local sy0 = by + math.floor(dy * bh / dh)
      local sy1 = by + math.ceil((dy + 1) * bh / dh) - 1
      if sx1 < sx0 then sx1 = sx0 end
      if sy1 < sy0 then sy1 = sy0 end
      local total, dark, mid, light = 0, 0, 0, 0
      for sy = sy0, sy1 do
        for sx = sx0, sx1 do
          total = total + 1
          local s = shadeAt(src, sx, sy, keyWhite)
          if s == DARK then dark = dark + 1
          elseif s == MID then mid = mid + 1
          elseif s == LIGHT then light = light + 1 end
        end
      end
      local solid = dark + mid + light
      local shade = nil
      -- a block the drawing barely reaches into stays background: a mon
      -- fringed with stray pixels reads as noise rather than as fur
      if total > 0 and solid * 5 >= total * 2 then
        if dark * 10 >= solid * 3 then shade = DARK
        elseif mid >= light then shade = MID
        else shade = LIGHT end
      end
      out[dy * dw + dx] = shade
    end
  end
  return out
end

-- The six frames, from the one drawing.
--
-- There is no side or back view of a Pokemon anywhere in this game, so
-- every facing shows the same picture -- which is what the front pic is
-- FOR, a creature looking at you.  What separates the walk rungs from the
-- stand rungs is a single pixel of lift, and that is enough: the engine
-- alternates them every eight frames of a step and mirrors every other one
-- (SpriteRenderer's stepFlip), so a walking mon bobs and sways where a
-- standing one is still.
local function compose(cells, dw, dh)
  local F, N = RoamerArt.FRAME, RoamerArt.FRAMES
  local sheet = love.image.newImageData(F, F * N)
  local ox = math.floor((F - dw) / 2)
  for frame = 0, N - 1 do
    local lift = frame >= 3 and 1 or 0
    local oy = F - dh - lift
    if oy < 0 then oy = 0 end
    for dy = 0, dh - 1 do
      local py = oy + dy
      if py >= 0 and py < F then
        for dx = 0, dw - 1 do
          local shade = cells[dy * dw + dx]
          local px = ox + dx
          if shade and px >= 0 and px < F then
            sheet:setPixel(px, frame * F + py, shade, shade, shade, 1)
          end
        end
      end
    end
  end
  return sheet
end

-- How wide a species stands, in the cell's own pixels.
--
-- Straight off the pic's own buffer size, which is the only statement Gen 1
-- makes about how big a Pokemon is: a 7x7 mon fills the cell, and every
-- rung down from there loses a pixel.  So a Caterpie is smaller than a
-- Snorlax on the map for the same reason it is smaller in a battle.
local function cellSize(mon)
  local n = tonumber(mon.frontSize) or 7
  local size = RoamerArt.FRAME - (7 - n)
  if size < 8 then size = 8 end
  if size > RoamerArt.FRAME then size = RoamerArt.FRAME end
  return size
end

local function bake(mon)
  local src = Assets.imageData(mon.spriteFront)
  local box, keyWhite = contentBox(src)
  if not box then return nil end
  local bw, bh = box[3] - box[1] + 1, box[4] - box[2] + 1
  local size = cellSize(mon)
  local scale = size / math.max(bw, bh)
  local dw = math.max(1, math.min(RoamerArt.FRAME, math.floor(bw * scale + 0.5)))
  local dh = math.max(1, math.min(RoamerArt.FRAME, math.floor(bh * scale + 0.5)))
  return compose(resample(src, box, keyWhite, dw, dh), dw, dh)
end

-- One failure retires the whole feature rather than half of it: a driver
-- with no pixel access, or a filesystem that will not take a write, cannot
-- do for the next species what it could not do for this one, and a world
-- where SOME wild Pokemon are visible and the rest are invisible is worse
-- than either answer on its own (see WildRoamers, which puts the random
-- encounters back when this says no).
local broken = false

function RoamerArt.available()
  return not broken
end

local function writeSheet(mon, path)
  local sheet = bake(mon)
  if not sheet then return false end
  local dir = path:match("^(.*)/[^/]+$")
  if dir then love.filesystem.createDirectory(dir) end
  local ok, err = love.filesystem.write(path, sheet:encode("png"))
  if not ok then
    broken = true
    V.mod.log:warn("could not bake overworld art (%s) -- wild Pokemon stay "
                   .. "in the grass and the random encounters come back",
                   tostring(err))
    return false
  end
  return true
end

-- species -> sprite def, or false once it is known there is none
local defs = {}

-- The sprite def for a species, in the shape data/generated/sprites.lua
-- uses, or nil.
--
-- Deliberately WITHOUT a `source`: that field is how the RED++ colour pack
-- assigns an object palette (PaletteFX.spriteObp reads the sprite's own
-- ROM table index out of it), and there is no honest index to claim for a
-- sheet the ROM never had.  What there IS an honest answer for is the
-- SPECIES: the ROM assigns every Pokemon a palette of its own (the SGB
-- mon palettes, which the RED++ pack carries too -- it is what colours
-- the battle pics), so the def carries `dsSpecies` and the spriteObp wrap
-- below resolves that mode from the species' own mon palette. A Pikachu
-- in the grass is YELLOWMON for exactly the reason its battle pic is.
-- Under every other mode -- the default included -- the sheet is coloured
-- by the map's own zone exactly like any NPC, because those paths read
-- neither field.
-- Returns the def, or nil plus DEFERRED when the only thing missing is a
-- bake the caller did not authorise this time (see RoamerArt.def).
local function build(species, mayBake)
  local Game = require("src.core.Game")
  local mon = Game.data and Game.data.pokemon and Game.data.pokemon[species]
  if not (mon and mon.spriteFront) then return nil end

  local path = V.path .. "/" .. SHIPPED .. species .. ".png"
  if not Assets.exists(path) then
    path = DERIVED .. species .. "-" .. RoamerArt.REV .. ".png"
    if not Assets.exists(path) then
      if not mayBake then return nil, true end
      if not writeSheet(mon, path) then return nil end
    end
  end
  return { id = "DS_ROAM_" .. species, image = path,
           frames = RoamerArt.FRAMES, walker = true,
           dsSpecies = species }
end

-- `mayBake` is the caller's permission to spend a bake HERE, on this frame.
--
-- Reading a sheet that already exists is free; making one walks every pixel
-- of a front pic three times and writes a file, which is a few milliseconds.
-- Once ever, per species, per save -- but "once ever" all lands on the frame
-- a route is first walked into, and half a dozen at once is a stutter
-- exactly where the player is looking. So the spawner spends a small budget
-- per pass and the rest come back nil, which costs nothing: the species is
-- NOT memoised as missing, so the very next pass can bake it.
-- Whether this session has already settled what art this species has (which
-- includes settling that it has none). The spawner's bake budget reads it,
-- so a species already in hand never costs one.
function RoamerArt.known(species)
  return defs[species] ~= nil
end

function RoamerArt.def(species, mayBake)
  if broken then return nil end
  local hit = defs[species]
  if hit ~= nil then return hit or nil end
  local ok, def, deferred = pcall(build, species, mayBake)
  if not ok then
    V.mod.log:warn("overworld art for %s failed: %s", tostring(species),
                   tostring(def))
    def, deferred = nil, false
  end
  if deferred then return nil end
  defs[species] = def or false
  return def
end

-- Hot reload drops the loaded images; the sheets on disk are still good, so
-- only the memo of which species resolved is thrown away.
function RoamerArt.invalidate()
  defs = {}
end

Assets.register(RoamerArt.invalidate)

-- ------- the RED++ answer: a species wears its own mon palette
--
-- PaletteFX.spriteObp is the one resolver every RED++ sprite draw goes
-- through (SpriteRenderer:draw, :drawTile and resolveImage all ask it),
-- and its answer for a def with no ROM table index is nil -- which left a
-- roamer's sheet drawn raw, in DMG shades, on the one colour mode whose
-- whole point is that nothing on screen is.  The wrap answers ONLY the
-- defs this module built (dsSpecies), only after the engine's own
-- resolution declined, and with the pack's own data: monPal is the same
-- species -> palette lookup that colours that species' battle pic, and
-- darkObp is the same dark-cave permutation every other OBJ palette gets.
-- Idempotent, like every other wrap this mod installs.
do
  local PaletteFX = require("src.render.PaletteFX")
  if not PaletteFX.dramaticShapeMonObp then
    local inner = PaletteFX.spriteObp
    function PaletteFX.spriteObp(spriteDef, seed)
      local colors, group = inner(spriteDef, seed)
      if colors ~= nil then return colors, group end
      local species = spriteDef and spriteDef.dsSpecies
      if not species then return colors, group end
      local ok, pal, name = pcall(function()
        local Game = require("src.core.Game")
        local data = Game and Game.data
        if not data then return nil end
        return PaletteFX.monPal(data, species),
               PaletteFX.monPalName(data, species)
      end)
      if not (ok and pal) then return nil end
      return PaletteFX.darkObp(pal, "dsmon:" .. tostring(name))
    end
    PaletteFX.dramaticShapeMonObp = true
  end
end

return RoamerArt
