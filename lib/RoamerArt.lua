-- Overworld art for a wild Pokemon.
--
-- Gen 1 draws no Pokemon on the map.  Eleven species have an overworld
-- sheet because a script stands one somewhere (the Vermilion Machop, the
-- Snorlax, Bill's Pikachu); the other hundred and forty have exactly one
-- drawing each and it is the battle FRONT pic.
--
-- Resampling a 40x40 front pic into a 16x16 cell is what this file first
-- did, and it is what made Sandshrew look like Charmander and Growlithe
-- into an unreadable blob: a battle portrait is drawn to read at battle
-- size, not as a walk-cycle tile.  So the preferred path is a Gen-2-style
-- 16x96 walker sheet at:
--
--   assets/roamers/<SPECIES>.png
--
-- Those sheets are NOT in the repository. Same rule as the X/Y GUI pack:
-- crediting ShockSlayer / Crystal Clear / PokePC Followers is not holding a
-- licence from them. tools/install_roamer_sprites.py fetches the pack and
-- renames it into place; assets/roamers/CREDITS.md is the install note.
-- Shipped sheets are marked `trueColor` so the OBP bake and the zone shader
-- leave the species colours alone (VoxelScene already respects that flag).
--
-- When a sheet is missing, the front-pic bake is the FALLBACK: a greyscale
-- 16x96 under save/mod-derived/<id>/roamers/, revisioned so an old cut is
-- never mistaken for a new one. The bake is what players without the pack
-- see -- so its outline bias and size floor matter, and they are tuned for
-- recognition rather than for a perfect miniature of the battle portrait.
--
-- Drop a replacement at assets/roamers/<SPECIES>.png and nothing is generated
-- for that species.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Assets = require("src.render.Assets")

local RoamerArt = {}

RoamerArt.FRAME = 16          -- the walk grid's own cell, like every sprite
RoamerArt.FRAMES = 6          -- stand down/up/left then walk down/up/left

-- Bumped when anything below changes what a sheet looks like.  It rides in
-- the filename, so an old bake is never picked up as a current one -- and
-- the old file is left alone rather than deleted, because a player who
-- pinned one on purpose should keep it.  (Shipped Gen-2 sheets do not use
-- this revision; only the front-pic fallback bake does.)
RoamerArt.REV = "3"

local function derivedRoot()
  local id = (V.mod and V.mod.id) or "TERRARIUM"
  return "save/mod-derived/" .. id .. "/roamers/"
end
local DERIVED = derivedRoot()
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
-- Not an average. Averaging four shades produces shades that are not any of
-- the four, and the whole point of staying on the DMG ramp is that the OBP
-- bake and the zone shader can then colour this sheet exactly like the
-- sheets beside it. So each destination pixel takes the shade its source
-- block is MOST made of.
--
-- Outline bias used to fire on EVERY block with 30% dark ink. That was meant
-- to protect a one-pixel line inside a 3x3 (which is never the majority of
-- anything), and it did -- but Gen 1 front pics are full of INTERNAL hatch
-- too, so the interior collapsed to black and every mon became a silhouette.
-- Similar silhouettes are identical: Sandshrew and Charmander. The low bar
-- now applies only to blocks that TOUCH background -- real outline -- and
-- the interior takes a plain majority among the three shades.
local function resample(src, box, keyWhite, dw, dh)
  local bx, by = box[1], box[2]
  local bw, bh = box[3] - box[1] + 1, box[4] - box[2] + 1
  local solid = {}
  local darkC, midC, lightC = {}, {}, {}

  for dy = 0, dh - 1 do
    for dx = 0, dw - 1 do
      local i = dy * dw + dx
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
      local ink = dark + mid + light
      -- a block the drawing barely reaches into stays background: a mon
      -- fringed with stray pixels reads as noise rather than as fur
      solid[i] = total > 0 and ink * 5 >= total * 2
      darkC[i], midC[i], lightC[i] = dark, mid, light
    end
  end

  local out = {}
  for dy = 0, dh - 1 do
    for dx = 0, dw - 1 do
      local i = dy * dw + dx
      if not solid[i] then
        out[i] = nil
      else
        -- edge of the silhouette: any neighbour off the ink, or off the cell
        local edge = false
        for _, o in ipairs({
          { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 },
        }) do
          local nx, ny = dx + o[1], dy + o[2]
          if nx < 0 or nx >= dw or ny < 0 or ny >= dh
             or not solid[ny * dw + nx] then
            edge = true
            break
          end
        end
        local dark, mid, light = darkC[i], midC[i], lightC[i]
        local shade
        if edge then
          -- low bar for dark: keep the outline that actually separates the
          -- mon from the grass
          if dark * 10 >= (dark + mid + light) * 3 then shade = DARK
          elseif mid >= light then shade = MID
          else shade = LIGHT end
        else
          -- interior: simple majority -- hatch stays hatch, not a black fill
          if dark >= mid and dark >= light then shade = DARK
          elseif mid >= light then shade = MID
          else shade = LIGHT end
        end
        out[i] = shade
      end
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
-- rung down from there loses a pixel. So a Caterpie is smaller than a
-- Snorlax on the map for the same reason it is smaller in a battle.
--
-- Floor is 12, not 8: at sixteen pixels total, readability beats scale
-- fidelity. A frontSize-4 mon used to bake at 13 and throw away three
-- precious pixels; 12 keeps the hierarchy without starving the small ones.
local function cellSize(mon)
  local n = tonumber(mon.frontSize) or 7
  local size = RoamerArt.FRAME - (7 - n)
  if size < 12 then size = 12 end
  if size > RoamerArt.FRAME then size = RoamerArt.FRAME end
  return size
end

-- Gen-2 walk sheets read because they are almost all head. A full-body
-- front pic squeezed into 16px leaves every distinctive mark under three
-- pixels. For tall, upright content boxes, crop to the upper ~60% so ear,
-- snout and mane get the budget. Long thin mons (Onix, Ekans, Gyarados)
-- keep the full box -- their identity IS the length.
local HEAD_CROP_MIN_RATIO = 1.15   -- bh/bw above this: upright enough to crop
local HEAD_CROP_FRAC = 0.62        -- keep this fraction of height from the top

local function bakeBox(box)
  local bw = box[3] - box[1] + 1
  local bh = box[4] - box[2] + 1
  if bw <= 0 or bh <= 0 then return box end
  if bh / bw < HEAD_CROP_MIN_RATIO then return box end
  local keep = math.max(1, math.floor(bh * HEAD_CROP_FRAC + 0.5))
  if keep >= bh then return box end
  return { box[1], box[2], box[3], box[2] + keep - 1 }
end

local function bake(mon)
  local src = Assets.imageData(mon.spriteFront)
  local box, keyWhite = contentBox(src)
  if not box then return nil end
  box = bakeBox(box)
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

  -- Shipped Gen-2 style walk sheet wins: true colour, already 16x96, no bake.
  local shipped = V.path .. "/" .. SHIPPED .. species .. ".png"
  if Assets.exists(shipped) then
    return { id = "TR_ROAM_" .. species, image = shipped,
             frames = RoamerArt.FRAMES, walker = true,
             trueColor = true, dsSpecies = species }
  end

  -- Fallback: greyscale bake from the battle front pic (REV in the path so
  -- older unreadable cuts are never reused after a generator change).
  local path = DERIVED .. species .. "-" .. RoamerArt.REV .. ".png"
  if not Assets.exists(path) then
    if not mayBake then return nil, true end
    if not writeSheet(mon, path) then return nil end
  end
  return { id = "TR_ROAM_" .. species, image = path,
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
      -- True-colour walker sheets (the shipped Gen-2 roamers) already carry
      -- their own species colours. Remapping them through monPal would wash
      -- a sandshrew into the zone's ground brown and undo the whole point.
      if spriteDef and spriteDef.trueColor then return nil end
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
