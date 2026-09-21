-- Overworld battles: the HUD, drawn rather than borrowed.
--
-- The mode already had an answer to "black glyphs on grass are not readable"
-- (lib/BattleHud.lua: frost the world behind them). That answer keeps the
-- GAME BOY's HUD -- a 4-shade block of tiles, 80x32, drawn by the engine's own
-- DrawEnemyHUDAndHPBar into the 160x144 UI canvas and lifted out of it. Over a
-- lit diorama with a 3D camera it reads as a screenshot pasted on, and no
-- amount of glass under it changes what it IS.
--
-- So this draws its own, out of the X/Y interface art: a capsule with the HP
-- trough milled into it, a coloured bar in the trough, the name and the level
-- in the series' own alphabet, and -- on the player's side only, exactly as
-- the games do it -- a slot of EXP under the capsule.
--
-- WHERE THE ART CAME FROM. A texture pack for the 3DS games, dumped at 5x
-- (`5X HUD/battle hud` and `5X HUD/text`). Dumps are named by content hash, so
-- nothing in them says which file is the player's frame and which is the
-- foe's; every box quoted below was MEASURED off the pixels -- see
-- data/hudxy_glyphs.lua for the glyph strips and TROUGH/EXP_SLOT for the two
-- holes in the frames. Re-cutting the art means re-measuring, not guessing.
--
-- WHAT IT DOES NOT DO. There is no gender mark. The sheet carries one and
-- Generation 1 has no such field -- gender arrived in Generation 2 -- so
-- drawing it would mean inventing a fact about the mon. The sheet's Mega
-- Evolution badge is unused for the same reason.
--
-- KNOWN ARTEFACT, and it is NOT this file's. A solid blue rectangle sits above
-- the player's EXP slot, at window x849..958 / y469..478 in a 1024x768 frame,
-- in RGB (50, 150, 250). It is the GAME BOY's own EXP bar, in the position the
-- band blit puts it, left behind on the world canvas. Everything below is
-- measured by tests/hudxy_probe.lua:
--   * it is not drawn by anything here -- switching BattleHudXY.ENABLED off
--     with the player's side LIVE leaves it exactly where it was, all 1100
--     pixels of it;
--   * it is not a live draw at all -- it comes back at exactly 1100 pixels in
--     six consecutive shots, including ones where the HP bar had moved from
--     full to a fifth. A live element would vary; a stale composite does not;
--   * it is not the band being blitted now -- the branch counters report 94
--     frames of `player.xy` and zero band blits over the very window the
--     picture was taken in;
--   * repainting EXP_COLOR and HP_HIGH magenta in turn moves the bars and
--     leaves the rectangle untouched;
--   * the art is innocent: frame_player.png has zero pixels of that blue and
--     the build's copy is byte-identical to the repo's.
-- SOLVED (2026-08-17), and the "stale composite" theory this note used to
-- close on was WRONG. The bar is a LIVE draw by the quality_of_life mod's
-- XP BAR feature (qol_feature_xp_bar.lua): its drawExpBar reads
-- `dramaticShapeShot` off the battle and paints straight onto the world
-- canvas at the snapped band's position, every frame, after this mod's own
-- draw. It measured as constant because EXP does not change mid-battle --
-- a live draw of a constant number is pixel-identical to a stale one, which
-- is what fooled the six-shot test. The branch counters never saw it
-- because it is not this mod's branch.
--
-- The fix is IN the QoL mod, by its own design language: its drawExpBar now
-- skips battles marked `terrariumXYBox` (the field BattleBoxXY.claim
-- rawsets), because this capsule already draws the same EXP in its own
-- slot. That patch lives in the INSTALLED copy of quality_of_life, not in
-- any repo -- reinstalling that mod resurrects the bar.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local BattleHudXY = {}

-- Off switch. Off leaves lib/BattleHud.lua's frosted-glass treatment of the
-- engine's own block exactly as it was, which is the fallback for a driver
-- that cannot load the art and the A/B a probe measures against.
BattleHudXY.ENABLED = true

-- OFF (see BattleDynamic): suppressed outright. Unlike a plain
-- `available()==false` (missing assets, say), which falls back to the
-- engine's own HUD, SUPPRESS means nothing this mod touches shows at
-- all -- OFF is a level below "fall back to classic," not classic itself.
BattleHudXY.SUPPRESS = false

BattleHudXY.ASSET_DIR = "assets/hudxy/"

-- ------- the art, and the holes measured in it
--
-- Both frames are 640x160 (the pack's 5x of a 128x32 texture). The trough is
-- the recessed channel the bar sits in, and it is the same 250x30 in both --
-- only its position moves, because the foe's capsule sits lower and further
-- right in its own sheet. Measured by scanning each row for its longest run
-- of near-black opaque pixels: the player's settled at x260..509 / y60..89,
-- the foe's at x310..559 / y85..114.
BattleHudXY.FRAME_W, BattleHudXY.FRAME_H = 640, 160
BattleHudXY.TROUGH = {
  player = { 260, 60, 250, 30 },
  enemy  = { 310, 85, 250, 30 },
}
-- The EXP slot, player frame only: the pale strip between the two dark rules
-- at the bottom of the sheet, x85..549 / y145..154.
BattleHudXY.EXP_SLOT = { 85, 145, 465, 10 }

-- hp_fill.png is a white bar with a ROUNDED cap on its right end: straight
-- from x0 to x451, the cap from 451 to 467, over rows 16..52. The straight
-- part is what gets stretched; the cap rides on the end of it, so a bar at
-- 40% still finishes in a round end rather than a chopped one.
BattleHudXY.FILL_BODY = { 0, 16, 451, 37 }
BattleHudXY.FILL_CAP = { 451, 16, 17, 37 }

-- Bar colours. The thresholds are Gen 1's own -- the game changes the bar's
-- shade at one half and at one fifth, and those are the fractions the whole
-- series' tension is built on, so they are kept even though the palette is
-- not.
BattleHudXY.HP_HIGH = { 0.44, 0.87, 0.41 }
BattleHudXY.HP_MID  = { 0.97, 0.78, 0.24 }
BattleHudXY.HP_LOW  = { 0.94, 0.31, 0.32 }
BattleHudXY.HP_MID_AT = 0.50
BattleHudXY.HP_LOW_AT = 0.20
BattleHudXY.EXP_COLOR = { 0.36, 0.78, 0.98 }

-- How wide the whole block is drawn, as a fraction of the window's width.
-- The art is 4:1 and the Game Boy's block was 2.5:1, so this is NOT the old
-- rect scaled -- the block is laid out in its own proportions and only its
-- CORNER is shared with what came before (see OverworldBattle.snapRects: the
-- foe's block hangs off the top-left, the player's off the bottom-right).
BattleHudXY.WIDTH_FRAC = 0.42
BattleHudXY.MIN_W, BattleHudXY.MAX_W = 260, 560

-- Text sizes, as a fraction of the drawn frame's height. Fractions rather
-- than pixels so the block survives a window resize as one object.
BattleHudXY.NAME_H = 0.30
BattleHudXY.NUM_H = 0.22

local glyphs = nil            -- data/hudxy_glyphs.lua
local images = {}             -- name -> Image | false

local function art(name)
  local hit = images[name]
  if hit ~= nil then return hit or nil end
  local okA, Assets = pcall(require, "src.render.Assets")
  if not okA or not Assets then images[name] = false; return nil end
  local path = V.path .. "/" .. BattleHudXY.ASSET_DIR .. name .. ".png"
  local okE, exists = pcall(Assets.exists, path)
  if not (okE and exists) then images[name] = false; return nil end
  local ok, img = pcall(Assets.image, path)
  if not (ok and img) then images[name] = false; return nil end
  -- linear, because every one of these is drawn at a scale the window
  -- decides and none of them is pixel art in the tileset's sense
  pcall(img.setFilter, img, "linear", "linear")
  images[name] = img
  return img
end

-- ------- Gen 1 Modern atlas (generated for this project)
-- Nearest filtering and atlas quads preserve the source pixel edges.
BattleHudXY.UI_DIR = "assets/ui/gen1-modern/"
BattleHudXY.INK = { 0.09, 0.15, 0.18, 1 }
-- Pixel rectangles in the generated atlas; no duplicate textures or runtime cuts.
BattleHudXY.UI_REGIONS = {
  panel = { 25, 50, 729, 182 },
  dialogue = { 25, 265, 897, 221 },
  button = { 25, 529, 350, 107 },
  selected = { 404, 529, 350, 107 },
  bar = { 25, 683, 350, 51 },
  charge_empty = { 239, 867, 53, 59 },
  charge_full = { 624, 867, 53, 59 },
  cursor = { 37, 867, 44, 59 },
}

-- Insets cover the complete stepped border, including its sage inner rule.
BattleHudXY.PANEL_INSET = { l = 40, r = 40, t = 32, b = 32 }

local uiImages = {}
local function uiArt(name)
  name = "ui-pack"
  local hit = uiImages[name]
  if hit ~= nil then return hit or nil end
  local okA, Assets = pcall(require, "src.render.Assets")
  if not okA or not Assets then uiImages[name] = false; return nil end
  local path = V.path .. "/" .. BattleHudXY.UI_DIR .. name .. ".png"
  local okE, exists = pcall(Assets.exists, path)
  if not (okE and exists) then uiImages[name] = false; return nil end
  local ok, img = pcall(Assets.image, path)
  if not (ok and img) then uiImages[name] = false; return nil end
  pcall(img.setFilter, img, "nearest", "nearest")
  uiImages[name] = img
  return img
end

-- Nine quads out of one image: corners at `k` pixels per source pixel, edges
-- stretched along their own axis, the middle stretched both ways. `k` rather
-- than "scale to fit" because the ornament has a size it reads at -- letting
-- a wide plate stretch its own corners is how a pixel-art frame turns to mush.
function BattleHudXY.nineSlice(img, x, y, w, h, ins, k, region)
  local g = love.graphics
  local aw, ah = img:getDimensions()
  local ox, oy = region and region[1] or 0, region and region[2] or 0
  local iw, ih = region and region[3] or aw, region and region[4] or ah
  local l, r, t, b = ins.l, ins.r, ins.t, ins.b
  local mw, mh = iw - l - r, ih - t - b
  if mw <= 0 or mh <= 0 then return false end
  -- the borders cannot eat more than the box: shrink k rather than overlap
  local kk = math.min(k, w / (l + r), h / (t + b))
  if kk <= 0 then return false end
  local dl, dr, dt, db = l * kk, r * kk, t * kk, b * kk
  local cw, ch = math.max(0, w - dl - dr), math.max(0, h - dt - db)
  local function q(qx, qy, qw, qh, dx, dy, dw, dh)
    if qw <= 0 or qh <= 0 or dw <= 0 or dh <= 0 then return end
    g.draw(img, g.newQuad(ox + qx, oy + qy, qw, qh, aw, ah), dx, dy, 0, dw / qw, dh / qh)
  end
  q(0, 0, l, t, x, y, dl, dt)
  q(l, 0, mw, t, x + dl, y, cw, dt)
  q(iw - r, 0, r, t, x + w - dr, y, dr, dt)
  q(0, t, l, mh, x, y + dt, dl, ch)
  q(l, t, mw, mh, x + dl, y + dt, cw, ch)
  q(iw - r, t, r, mh, x + w - dr, y + dt, dr, ch)
  q(0, ih - b, l, b, x, y + h - db, dl, db)
  q(l, ih - b, mw, b, x + dl, y + h - db, cw, db)
  q(iw - r, ih - b, r, b, x + w - dr, y + h - db, dr, db)
  return true
end

function BattleHudXY.uiSprite(name, x, y, w, h, sliced)
  local img, region = uiArt(name), BattleHudXY.UI_REGIONS[name]
  if not (img and region) then return false end
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  if sliced then
    return BattleHudXY.nineSlice(img, x, y, w, h,
      BattleHudXY.PANEL_INSET, math.min(0.6, h / 150), region)
  end
  local iw, ih = img:getDimensions()
  g.draw(img, g.newQuad(region[1], region[2], region[3], region[4], iw, ih),
    x, y, 0, w / region[3], h / region[4])
  return true
end

local function glyphData()
  if glyphs == nil then
    local ok, g = pcall(V.data, "hudxy_glyphs")
    glyphs = (ok and g) or false
  end
  return glyphs or nil
end

-- ------- the NATIVE alphabet: what this HUD says when there is no art
--
-- The 5X strips and data/hudxy_glyphs.lua left the tree in 2026-09-15 (they
-- were a dump of somebody else's interface), and with them every module that
-- asks this file to spell something: the cards, the panels, the ribbon, the
-- box. The whole costume degraded to the Game Boy's own HUD in one step,
-- which is the ladder working -- and also the costume being gone.
--
-- What replaces them is not another dump. LOVE carries a scalable face of its
-- own (love.graphics.newFont with no file: Vera Sans, permissively licensed,
-- always present), and the battle concepts this HUD is drawn from ask for a
-- typeset line rather than a pixel strip anyway -- lowercase prose on a move
-- card is not something a 5x Game Boy alphabet could ever have set.
--
-- The one thing that has to survive the swap is ARITHMETIC. Every caller in
-- lib/ measures with `textWidth(s) * (th / 84)` and `numberWidth(s) * (h / 56)`
-- -- 84 and 56 are the two strips' own cell heights, hardcoded at a dozen
-- sites. So the native metrics are reported in those same units and nothing
-- downstream has to learn a second convention.
local FONT_CELL, DIGIT_CELL = 84, 56

-- One baked size, scaled per draw. Baking per requested height would allocate
-- a rasteriser every frame the HP numbers changed.
local BAKE_PX = 64
local vecFont = nil        -- Font | false

local function nativeFont()
  if vecFont == nil then
    local ok, f = pcall(love.graphics.newFont, BAKE_PX)
    vecFont = (ok and f) or false
  end
  return vecFont or nil
end

-- True when this file is spelling with its own face rather than the strips.
-- Asked per call rather than cached: `ENABLED` and the assets are both things
-- a probe flips mid-run.
local function native()
  return not (glyphData() and art("font") and art("digits"))
end

-- Whether the whole feature can run. Two roads now: the strips if they are
-- there, the native face if they are not. Only a LOVE that cannot make a font
-- at all falls through to lib/BattleHud.lua's frosted Game Boy block.
function BattleHudXY.available()
  if not BattleHudXY.ENABLED then return false end
  if native() then return nativeFont() ~= nil end
  return art("frame_player") ~= nil and art("frame_enemy") ~= nil
    and art("hp_fill") ~= nil
end

-- ------- drawing text off the strips
--
-- Both strips are one row of glyphs with a transparent gutter between them,
-- so a string is a run of quads out of one texture and one draw call each --
-- and, more to the point, one image bound for a whole name rather than a
-- sheet swap per character.

local function quad(img, x, y, w, h)
  local iw, ih = img:getDimensions()
  return love.graphics.newQuad(x, y, w, h, iw, ih)
end

-- ------- reading a string a CHARACTER at a time
--
-- Not a byte at a time, which is what this did first and it printed "POKDEX"
-- on the start menu: the label is "POKéDEX" in UTF-8, the accented letter is
-- two bytes, and a byte-wise walk looked up each half, found neither, and
-- skipped both. Every accented name in the game had a hole in it.
--
-- Only the length prefix is decoded, not the code point -- the atlas is keyed
-- by the glyph's own UTF-8 BYTES (see data/hudxy_glyphs.lua), so the whole
-- sequence is the lookup and there is nothing to convert it to.
local function charAt(s, i)
  local b = s:byte(i)
  if not b then return nil, 0 end
  local len = 1
  if b >= 0xF0 then len = 4
  elseif b >= 0xE0 then len = 3
  elseif b >= 0xC0 then len = 2 end
  -- a truncated sequence at the end of the string is one byte, not a read
  -- past the end
  if i + len - 1 > #s then len = 1 end
  return s:sub(i, i + len - 1), len
end

-- What to draw when the sheet has no glyph for a character.
--
-- The pack draws no O-tilde at all, upper or lower, and no lowercase
-- a-tilde -- so OPÇÕES cannot be spelled in this font. Folding to the bare
-- vowel loses the accent and keeps the word; the alternative, substituting a
-- DIFFERENT accent that does exist, would spell it wrong on purpose.
BattleHudXY.FOLD = {
  ["\195\149"] = "O", ["\195\181"] = "o",   -- O-tilde
  ["\195\163"] = "a",                        -- a-tilde
}

-- Width of `text` in the proportional alphabet, at scale 1.
-- The glyph box for one character, after folding. nil means "draw nothing and
-- do not advance", which is what an unknown character gets.
local function glyphOf(g, ch)
  local m = g.font[ch]
  if m then return m end
  local fold = BattleHudXY.FOLD[ch]
  return fold and g.font[fold] or nil
end

function BattleHudXY.textWidth(text, tracking)
  if native() then
    local f = nativeFont()
    if not (f and text) then return 0 end
    return f:getWidth(text) * (FONT_CELL / f:getHeight())
  end
  local g = glyphData()
  if not (g and text) then return 0 end
  local w, i = 0, 1
  while i <= #text do
    local ch, len = charAt(text, i)
    if not ch then break end
    local m = glyphOf(g, ch)
    if m then w = w + m.adv + (tracking or 2) end
    i = i + len
  end
  return w
end

-- Draw `text` with its top-left at (x, y), scaled so the CELL is `h` tall.
-- Unknown characters are skipped rather than substituted: the alphabet has
-- real gaps (no apostrophe, no `<`), and a row of question marks in a
-- Pokemon's name is worse than a missing punctuation mark.
function BattleHudXY.text(text, x, y, h, color)
  if native() then
    local f = nativeFont()
    if not (f and text) then return 0 end
    -- `h` names the CELL, and a rasterised face's cell is its own line
    -- height -- so the scale is that ratio and not h/ascender, which would
    -- set every caller's name one size too large.
    local s = h / f:getHeight()
    local prev = love.graphics.getFont()
    love.graphics.setColor(color and color[1] or 1, color and color[2] or 1,
                           color and color[3] or 1, color and color[4] or 1)
    love.graphics.setFont(f)
    love.graphics.print(text, x, y, 0, s, s)
    if prev then love.graphics.setFont(prev) end
    love.graphics.setColor(1, 1, 1, 1)
    return f:getWidth(text) * s
  end
  local g, img = glyphData(), art("font")
  if not (g and img and text) then return 0 end
  local s = h / g.fontHeight
  local tracking = 2
  love.graphics.setColor(color and color[1] or 1, color and color[2] or 1,
                         color and color[3] or 1, color and color[4] or 1)
  local pen, i = 0, 1
  while i <= #text do
    local ch, len = charAt(text, i)
    if not ch then break end
    local m = glyphOf(g, ch)
    if m then
      if m.w > 0 then
        love.graphics.draw(img, quad(img, m.x, 0, m.w, g.fontHeight),
                           x + pen * s, y, 0, s, s)
      end
      pen = pen + m.adv + tracking
    end
    i = i + len
  end
  love.graphics.setColor(1, 1, 1, 1)
  return pen * s
end

function BattleHudXY.numberWidth(text, tracking)
  if native() then
    local f = nativeFont()
    if not (f and text) then return 0 end
    return f:getWidth(text) * (DIGIT_CELL / f:getHeight())
  end
  local g = glyphData()
  if not g then return 0 end
  local w = 0
  for i = 1, #text do
    local m = g.digits[text:sub(i, i)]
    if m then w = w + m.w + (tracking or 4) end
  end
  return w
end

-- The big numerals. Bottom-aligned rather than top-aligned: the strip was
-- packed to a single baseline, and `Lv.` and `/` are shorter than a digit --
-- top-aligning them would float them above the numbers they belong to.
function BattleHudXY.number(text, x, baseline, h, color)
  if native() then
    local f = nativeFont()
    if not (f and text) then return 0 end
    local s = h / f:getHeight()
    local prev = love.graphics.getFont()
    love.graphics.setColor(color and color[1] or 1, color and color[2] or 1,
                           color and color[3] or 1, color and color[4] or 1)
    love.graphics.setFont(f)
    -- bottom-aligned, like the strip: `baseline` is where the digits SIT
    love.graphics.print(text, x, baseline - f:getHeight() * s, 0, s, s)
    if prev then love.graphics.setFont(prev) end
    love.graphics.setColor(1, 1, 1, 1)
    return f:getWidth(text) * s
  end
  local g, img = glyphData(), art("digits")
  if not (g and img and text) then return 0 end
  local s = h / g.digitHeight
  local tracking = 4
  love.graphics.setColor(color and color[1] or 1, color and color[2] or 1,
                         color and color[3] or 1, color and color[4] or 1)
  local pen = 0
  for i = 1, #text do
    local m = g.digits[text:sub(i, i)]
    if m then
      love.graphics.draw(img, quad(img, m.x, m.y, m.w, m.h),
                         x + pen * s, baseline - m.h * s, 0, s, s)
      pen = pen + m.w + tracking
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  return pen * s
end

-- ------- the bar
--
-- Drawn INTO the trough measured off the frame, so the bar cannot drift off
-- its own channel when the block is scaled: everything below is in frame
-- texture coordinates and multiplied by the one scale at the end.

function BattleHudXY.hpColor(frac)
  if frac <= BattleHudXY.HP_LOW_AT then return BattleHudXY.HP_LOW end
  if frac <= BattleHudXY.HP_MID_AT then return BattleHudXY.HP_MID end
  return BattleHudXY.HP_HIGH
end

local function drawFill(slot, frac, color, ox, oy, s)
  local img = art("hp_fill")
  if not img then return end
  frac = math.max(0, math.min(1, frac or 0))
  if frac <= 0 then return end
  local sx, sy, sw, sh = slot[1], slot[2], slot[3], slot[4]
  local body, cap = BattleHudXY.FILL_BODY, BattleHudXY.FILL_CAP
  -- the cap keeps its aspect; the body takes whatever is left
  local capW = cap[3] * (sh / body[4])
  local full = sw * frac
  local bodyW = math.max(0, full - capW)
  love.graphics.setColor(color[1], color[2], color[3], 1)
  if bodyW > 0 then
    love.graphics.draw(img, quad(img, body[1], body[2], body[3], body[4]),
                       ox + sx * s, oy + sy * s, 0,
                       bodyW * s / body[3], sh * s / body[4])
  end
  love.graphics.draw(img, quad(img, cap[1], cap[2], cap[3], cap[4]),
                     ox + (sx + bodyW) * s, oy + sy * s, 0,
                     capW * s / cap[3], sh * s / cap[4])
  love.graphics.setColor(1, 1, 1, 1)
end

-- ------- what a side is worth, as numbers
--
-- Read off the LIVE battle rather than off a copy: the fields were dumped
-- from a running fight (tests/battle_fields_probe.lua) rather than read out of
-- an engine source tree, because the engine ships inside the executable.
--
-- `shownHP` and not `mon.hp`: the engine animates the bar down over several
-- frames after a hit and `shownHP` is that animation's own value. Drawing
-- `mon.hp` would snap the bar to the new total on the frame the damage lands,
-- which is the one thing a HP bar exists not to do.
function BattleHudXY.read(side)
  if not side then return nil end
  local mon = side.mon
  if not mon then return nil end
  local maxHP = (side.curStats and side.curStats.hp) or (mon.stats and mon.stats.hp)
  local now = side.shownHP or mon.hp or 0
  local info = {
    name = side.name or mon.species or "?",
    level = mon.level or 0,
    hp = math.max(0, math.floor(now + 0.5)),
    maxHP = math.max(1, maxHP or 1),
    isPlayer = side.isPlayer and true or false,
    status = mon.status,
  }
  -- CHARGE is the player's alone (the foe spends no pips, and a meter on a
  -- side nothing can read is a meter that lies). Pulled rather than passed so
  -- block()'s signature -- and both of drawXYBlock's call sites -- stay put.
  if info.isPlayer then
    local ok, Charge = pcall(V.require, "BattleCharge")
    if ok and Charge and Charge.read then
      info.charge, info.chargeMax = Charge.read()
    end
  end
  return info
end

-- The fraction of the way through the current level, for the EXP slot.
--
-- The growth curve lives in the engine's own data, keyed by the species'
-- `growthRate` -- and it is not a table of thresholds. Dumped from a running
-- battle, `data.growth_rates.MEDIUM_FAST` has exactly one key and it is a
-- FUNCTION, `expForLevel`. Indexing it by level (which is what this did
-- first) returns nil for every level there is, which is why the slot came
-- back empty on a Pikachu that was two thirds of the way to 40.
--
-- Still returns nil rather than a guess when the shape is not the one below:
-- an EXP bar that is wrong is worse than one that is empty, because an empty
-- one is visibly empty and a wrong one is just a lie about how close you are.
function BattleHudXY.expFraction(side, data)
  local mon = side and side.mon
  local rate = side and side.def and side.def.growthRate
  local curve = data and data.growth_rates and rate and data.growth_rates[rate]
  local fn = curve and curve.expForLevel
  if not (mon and mon.exp and mon.level and type(fn) == "function") then
    return nil
  end
  local okLo, lo = pcall(fn, mon.level)
  local okHi, hi = pcall(fn, mon.level + 1)
  if not (okLo and okHi) then return nil end
  if type(lo) ~= "number" or type(hi) ~= "number" or hi <= lo then return nil end
  return math.max(0, math.min(1, (mon.exp - lo) / (hi - lo)))
end

-- ------- the block
--
-- `x, y` is the block's top-left in window pixels and `w` its width; the
-- frame's own aspect fixes the height. Everything inside is placed in the
-- frame's 640x160 texture space and scaled by one number, so the layout
-- cannot come apart at a different window size.
-- ------- the native plate
--
-- Drawn, not blitted: smoked glass with a pale double rim and gold L-corners,
-- which is the language lib/BattlePanelsXY.lua already speaks for the message
-- box and the command chips (concept 12/13). It is redrawn here in six lines
-- rather than required from there, because BattlePanelsXY requires THIS file
-- and a cycle through V.require is a stack overflow, not a warning.
BattleHudXY.PANEL = { 0.98, 0.97, 0.91 }
BattleHudXY.GOLD  = { 0.29, 0.39, 0.32 }

-- Plate heights in the same 640-wide space FRAME_W measures, so the caller's
-- `h = w * fh / fw` needs no new convention. The player's is taller because
-- it carries two rows the foe's does not: the CHARGE pips and the EXP rule.
BattleHudXY.PLAYER_H = 170
BattleHudXY.ENEMY_H  = 124

-- Where the two plates sit. The 5X frames were hung foe top-left / player
-- bottom-right (see drawXYBlock); the concept boards put BOTH along the top,
-- player left and foe right, with the whole lower half left to the cards, the
-- prompt and the command row. BattleDynamic owns this flag, so CLASSICA keeps
-- the corners the pack was cut for.
BattleHudXY.CONCEPT_CORNERS = true

-- CHARGE: how many pips the player's plate shows. The value itself is the
-- economy's (lib/BattleCharge.lua); this file only draws what it is handed.
BattleHudXY.CHARGE_PIPS = 5

-- Shared opaque ivory panel for status blocks and attack cards.
function BattleHudXY.plateArt(g, x, y, w, h, k)
  return BattleHudXY.uiSprite("panel", x, y, w, h, true)
end

BattleHudXY.PLATE_FILL = BattleHudXY.PANEL

local function plate(g, x, y, w, h)
  if BattleHudXY.plateArt(g, x, y, w, h) then return end
  g.setColor(unpack(BattleHudXY.PANEL))
  g.rectangle("fill", x, y, w, h)
  g.setColor(unpack(BattleHudXY.INK))
  g.setLineWidth(2)
  g.rectangle("line", x, y, w, h)
  g.setLineWidth(1)
end

-- A length of lit liquid in a glass tube: the trough first (so an empty bar
-- is still a bar), then the fill cropped to `frac`, then a highlight down its
-- top half. `frac` is clamped, never trusted -- shownHP can lead mon.hp by a
-- frame during a drain and a bar wider than its trough is a visible bug.
local function tube(g, x, y, w, h, frac, color, dim)
  frac = math.max(0, math.min(1, frac or 0))
  local rim = uiArt("bar")
  if rim then
    g.setColor(1, 1, 1, 1)
    BattleHudXY.nineSlice(rim, x, y, w, h,
      { l = 20, r = 20, t = 16, b = 16 }, h / 51, BattleHudXY.UI_REGIONS.bar)
  else
    g.setColor(unpack(BattleHudXY.INK))
    g.rectangle("fill", x, y, w, h)
  end
  local inset = h * 0.30
  g.setColor(color[1], color[2], color[3], dim or 1)
  g.rectangle("fill", x + inset, y + inset,
    math.max(0, w - inset * 2) * frac, h - inset * 2)
  g.setColor(1, 1, 1, 1)
end

-- The CHARGE row: diamonds, filled to `n` of `max`. Diamonds and not squares
-- because the same shape is the move cards' COST (BattleFanXY.drawFace), and
-- one shape for one currency is what makes "this move costs three of those"
-- legible without a legend.
function BattleHudXY.pips(g, x, y, size, gap, n, max, color)
  for i = 1, max do
    local px = x + (i - 1) * (size + gap)
    local sprite = i <= n and "charge_full" or "charge_empty"
    if not BattleHudXY.uiSprite(sprite, px, y, size, size) then
      g.setColor(unpack(color or BattleHudXY.GOLD))
      g.rectangle(i <= n and "fill" or "line", px, y, size, size)
    end
  end
  g.setColor(1, 1, 1, 1)
  return max * (size + gap) - gap
end

local function nativeBlock(info, x, y, w, expFrac)
  local g = love.graphics
  local isP = info.isPlayer
  local S = w / BattleHudXY.FRAME_W            -- one scale for the whole plate
  local H = (isP and BattleHudXY.PLAYER_H or BattleHudXY.ENEMY_H) * S
  local PAD = 30 * S
  plate(g, x, y, w, H)

  local nameH = 42 * S
  local top = 18 * S


  -- Lv. right-aligned to the plate. Drawn as one string so the tag and the
  -- number can never drift apart by a rounding difference the way two
  -- separately-placed draws did on the pack's frame.
  local lv = ("Lv. %d"):format(info.level or 0)
  local lvH = 34 * S
  local lvW = BattleHudXY.textWidth(lv) * (lvH / 84)
  local nameW = math.max(1, w - PAD * 2 - lvW - 20 * S)
  nameH = math.min(nameH, nameW * 84 / math.max(1, BattleHudXY.textWidth(info.name)))
  BattleHudXY.text(info.name, x + PAD, y + top, nameH, BattleHudXY.INK)
  BattleHudXY.text(lv, x + w - PAD - lvW, y + top + (nameH - lvH) * 0.55, lvH,
                   BattleHudXY.GOLD)

  -- the HP row
  local barY, barH = y + 74 * S, 24 * S
  local labH = 24 * S
  BattleHudXY.text("HP", x + PAD, barY + (barH - labH) * 0.5, labH,
                   BattleHudXY.GOLD)
  local barX = x + PAD + 46 * S
  local barR = x + w - PAD
  local pair
  if isP then
    pair = ("%d / %d"):format(info.hp, info.maxHP)
    barR = barR - (BattleHudXY.textWidth(pair) * (labH / 84) + 14 * S)
  end
  local frac = info.hp / math.max(1, info.maxHP)
  tube(g, barX, barY, math.max(1, barR - barX), barH, frac,
       BattleHudXY.hpColor(frac))
  if isP then
    BattleHudXY.text(pair, barR + 14 * S, barY + (barH - labH) * 0.5, labH,
                     BattleHudXY.INK)
  end

  if isP then
    -- CHARGE, on the row the concept boards give it -- and ONLY when the
    -- economy is live. With its row switched off BattleCharge.read answers
    -- nothing, and a meter drawn empty forever would be the plate promising a
    -- resource the fight does not have.
    if info.chargeMax then
      local chH = 22 * S
      local chY = y + 106 * S
      BattleHudXY.text("CHARGE", x + PAD, chY, chH, BattleHudXY.GOLD)
      -- past the label's own width, not at the HP tube's left rule: "CHARGE"
      -- is four glyphs longer than "HP" and ran under its own first pip there
      BattleHudXY.pips(g, x + PAD + 132 * S, chY, 20 * S, 7 * S,
                       info.charge or 0, info.chargeMax)
    end
    -- EXP as a thin filament along the plate's foot, never an orphan bar
    if expFrac then
      local ey = y + H - 17 * S
      tube(g, x + PAD, ey, w - PAD * 2, 7 * S, expFrac,
           BattleHudXY.EXP_COLOR, 0.95)
    end
  end
  g.setColor(1, 1, 1, 1)
  return true
end

function BattleHudXY.block(info, x, y, w, expFrac)
  if not (info and BattleHudXY.available()) then return false end
  if native() then return nativeBlock(info, x, y, w, expFrac) end
  local side = info.isPlayer and "player" or "enemy"
  local frame = art(info.isPlayer and "frame_player" or "frame_enemy")
  if not frame then return false end
  local s = w / BattleHudXY.FRAME_W

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(frame, x, y, 0, s, s)

  local frac = info.hp / info.maxHP
  drawFill(BattleHudXY.TROUGH[side], frac, BattleHudXY.hpColor(frac), x, y, s)

  if info.isPlayer and expFrac then
    drawFill(BattleHudXY.EXP_SLOT, expFrac, BattleHudXY.EXP_COLOR, x, y, s)
  end

  -- The name sits above the capsule, left-aligned to it; the level's digits
  -- follow the `Lv.` the FRAME already prints, so the two are never spaced
  -- apart by a rounding difference.
  local trough = BattleHudXY.TROUGH[side]
  local capTop = trough[2]
  local nameH = BattleHudXY.NAME_H * BattleHudXY.FRAME_H
  local nameX = (side == "player") and 165 or 215
  BattleHudXY.text(info.name, x + nameX * s, y + (capTop - nameH - 6) * s,
                   nameH * s)

  local numH = BattleHudXY.NUM_H * BattleHudXY.FRAME_H
  local lvX = (side == "player") and 440 or 460
  BattleHudXY.number(tostring(info.level), x + lvX * s,
                     y + (capTop - 8) * s, numH * s)

  -- The HP pair, player only -- the games show the foe's bar and not its
  -- numbers, and that asymmetry is information: it is what makes the foe's
  -- remaining health a judgement rather than a readout.
  if info.isPlayer then
    local pair = ("%d/%d"):format(info.hp, info.maxHP)
    local pw = BattleHudXY.numberWidth(pair) * (numH / 56)
    -- Baseline just clear of the EXP slot's top rule, not measured down from
    -- the trough: at trough-bottom + 26 the pair sat ON the capsule, over the
    -- bar it is describing. The gap between the capsule's shadow (ends ~110)
    -- and the EXP rule (starts 140) is the only clean band on this frame, and
    -- the numbers are right-aligned into it under the end of the bar.
    BattleHudXY.number(pair, x + (trough[1] + trough[3]) * s - pw,
                       y + (BattleHudXY.EXP_SLOT[2] - 5) * s, numH * s)
  end
  return true
end

return BattleHudXY
