-- The battle's text box and command buttons, at the window's resolution.
--
-- Same problem the start menu had and the same answer: the engine draws its
-- box into the 160x144 UI canvas, so anything drawn THERE arrives on screen
-- at Game Boy resolution. This draws into the world canvas instead, from
-- inside OverworldBattle.snapHUDs, which is already bound to it.
--
-- WHAT IS REPLACED. The box's frame and fill, the message text, and -- while
-- the command menu is up -- the four commands, drawn as buttons rather than
-- as two columns of words with an arrow beside one of them.
--
-- WHAT IS NOT. Which commands exist, which one is highlighted, what the
-- message says, and how fast it types. All four are read off the battle every
-- frame: `menuIndex` (1..4 in reading order, found by moving the cursor and
-- watching which field changed), `current.text`, and `charIndex`, which is
-- the typewriter's own cursor -- honouring it is what keeps the text appearing
-- a letter at a time instead of all at once.
--
-- THE LABELS ARE THE GAME'S. The 5X pack draws its command buttons with the
-- words baked in, in English -- POKéMON, BAG, RUN. This build runs in
-- Portuguese (LUTAR, PKMN, ITENS, FUGIR), so the art's own labels would put
-- two languages in one frame. The buttons here are drawn rather than blitted
-- and the words come from the same place the Game Boy's did.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local BattleBoxXY = {}

BattleBoxXY.ENABLED = true

BattleBoxXY.ASSET_DIR = "assets/battlexy/"

-- The four commands, in the order menuIndex counts them. Measured, not
-- assumed -- DOWN took the cursor from 1 to 3, RIGHT from 3 to 4, UP from 4
-- to 2, which is a 2x2 read row-first.
--
-- The art is the pack's own button for each, so the words on them are the
-- pack's too: FIGHT, POKéMON, BAG, RUN. That does put English on a menu the
-- rest of this build shows in Portuguese, and it is deliberate -- these are
-- the X/Y buttons, and redrawing them to translate the label would make them
-- something else. `label` is kept beside each for the tooltip-less case where
-- the art fails to load and the fallback has to say something.
BattleBoxXY.COMMANDS = {
  { art = "cmd_fight",   label = "LUTAR", color = { 0.86, 0.24, 0.21 } },
  { art = "cmd_pokemon", label = "PKMN",  color = { 0.24, 0.70, 0.36 } },
  { art = "cmd_bag",     label = "ITENS", color = { 0.93, 0.66, 0.16 } },
  { art = "cmd_run",     label = "FUGIR", color = { 0.20, 0.52, 0.86 } },
}

-- X/Y stands FIGHT on its own, big, with the other three stacked beside it --
-- the shape says "this is the one you press" before any word is read. The
-- Game Boy's 2x2 grid of words carried no such weight, and menuIndex's own
-- order is preserved underneath: the cursor still moves the way the engine
-- moves it, only the boxes it lands on have changed shape.
-- The three go in a ROW beside FIGHT, not in a column.
--
-- Stacked, they were limited by a third of the box's height and came out tiny
-- with a band of empty panel beside them: this box is 160x48 in Game Boy
-- terms, which is very wide and very short, and three things stacked down its
-- short axis have nowhere to grow. In a row each one gets a third of the WIDE
-- axis and roughly doubles.
-- X/Y's own arrangement, which is not a row and not a grid: FIGHT alone on
-- top, filling most of the panel, and the other three along the BOTTOM edge
-- running off it -- they are drawn as the top half of a capsule precisely so
-- they can be cut by the edge of the screen.
--
-- That needs more height than the Game Boy's text box has (160x48, a third of
-- the frame), so with the command menu up the panel grows UPWARD from the
-- box's own bottom edge. Only upward, and only here: the box's baseline is
-- where the player's eye already is, and the message phases keep the
-- engine's own rectangle exactly.
BattleBoxXY.MENU_GROW = 1.9        -- panel height, as a multiple of the box's
BattleBoxXY.FIGHT_FRAC = 0.62      -- of the panel's height, for FIGHT's band
BattleBoxXY.FIGHT_WIDE = 0.72      -- and of its width
BattleBoxXY.STACK_GAP = 0.02       -- between buttons, as a fraction

-- The bottom row, left to right, by menuIndex. X/Y puts BAG, RUN and POKéMON
-- in that order and this follows it -- the cursor's own numbering (2 = party,
-- 3 = bag, 4 = run) is a Game Boy fact about a 2x2 grid that no longer
-- exists, and reproducing it here would put the buttons in an order the
-- reference does not have.
BattleBoxXY.BOTTOM_ORDER = { 3, 4, 2 }

-- An unselected button steps back rather than greying out: the four have to
-- stay tellable apart at a glance, which is the whole reason a player can
-- reach for RUN without reading it.
BattleBoxXY.UNSEL_ALPHA = 0.62
BattleBoxXY.UNSEL_SCALE = 0.90

BattleBoxXY.PANEL = { 0.08, 0.09, 0.12, 0.90 }
BattleBoxXY.PANEL_EDGE = { 0.62, 0.67, 0.78, 0.60 }
BattleBoxXY.TEXT = { 1, 1, 1, 1 }
-- An unselected button is the same colour turned down, not a grey one: the
-- four have to stay tellable apart at a glance, which is the whole reason a
-- player can pick FUGIR without reading it.
BattleBoxXY.DIM = 0.42
BattleBoxXY.SELECT_RING = { 1, 1, 1, 0.95 }

-- Fractions of the box's own height, so the layout survives any window size.
BattleBoxXY.TEXT_H = 0.20        -- message glyph height
BattleBoxXY.LINE_GAP = 1.35      -- line height, as a multiple of TEXT_H
BattleBoxXY.PAD = 0.10           -- inside the panel
BattleBoxXY.BUTTON_H = 0.34      -- one button's height
BattleBoxXY.MENU_FRAC = 0.42     -- how much of the box's width the buttons take

local BattleHudXY = V.require("BattleHudXY")

function BattleBoxXY.available()
  return BattleBoxXY.ENABLED and BattleHudXY.available()
end

-- Which phases this file actually DRAWS.
--
-- This exists because of a bug it should have prevented: `drawTextArea` puts
-- up the message box, the command menu AND the move list, and silencing it
-- silenced all three. The move list had no replacement, so choosing FIGHT led
-- to an empty panel and there was no way to pick an attack -- the battle was
-- unplayable, and it looked fine in every screenshot of the command menu.
--
-- So the suppression is now per PHASE, and the rule is the honest one: the
-- engine keeps every phase this file cannot draw yet. A phase added to the
-- engine later is covered by the engine until somebody adds it here.
BattleBoxXY.PHASES = {
  menu = true,        -- the four command buttons
  messages = true,    -- the typed message
}

function BattleBoxXY.covers(battle)
  if not (battle and BattleBoxXY.available()) then return false end
  return BattleBoxXY.PHASES[battle.phase] and true or false
end

local function setColor(c, a)
  love.graphics.setColor(c[1], c[2], c[3], (a or 1) * (c[4] or 1))
end

-- ------- the message
--
-- `charIndex` counts BYTES of the message the engine has revealed, and the
-- message is UTF-8 -- so cutting at charIndex can land in the middle of an
-- accented letter and hand the renderer half a code point. Backing off to the
-- last whole character is one loop and avoids a glyph that flickers into
-- existence as a wrong one.
local function revealed(text, charIndex)
  if type(text) ~= "string" then return "" end
  local n = math.min(#text, math.max(0, math.floor(charIndex or #text)))
  while n > 0 do
    local b = text:byte(n)
    -- a continuation byte (10xxxxxx) is never the end of a character
    if b >= 0x80 and b < 0xC0 then n = n - 1 else break end
  end
  -- and if the last kept byte STARTS a sequence, it is incomplete too
  if n > 0 then
    local b = text:byte(n)
    if b >= 0xC0 then n = n - 1 end
  end
  return text:sub(1, n)
end

BattleBoxXY._revealed = revealed     -- named for the suite

-- The message, split on the engine's own newlines. No re-wrapping: the engine
-- decided where the breaks go and it knows about the box it wrote them for.
local function lines(text)
  local out = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = line end
  -- a trailing empty line is an artefact of the pattern, not a blank row
  if #out > 0 and out[#out] == "" then out[#out] = nil end
  return out
end

local function panel(x, y, w, h)
  local r = math.min(16, h * 0.45, w * 0.45)
  setColor(BattleBoxXY.PANEL)
  love.graphics.rectangle("fill", x, y, w, h, r, r)
  setColor(BattleBoxXY.PANEL_EDGE)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x, y, w, h, r, r)
  love.graphics.setLineWidth(1)
end

local images = {}

local function art(name)
  local hit = images[name]
  if hit ~= nil then return hit or nil end
  local okA, Assets = pcall(require, "src.render.Assets")
  if not okA or not Assets then images[name] = false; return nil end
  local path = V.path .. "/" .. BattleBoxXY.ASSET_DIR .. name .. ".png"
  local okE, exists = pcall(Assets.exists, path)
  if not (okE and exists) then images[name] = false; return nil end
  local ok, img = pcall(Assets.image, path)
  if not (ok and img) then images[name] = false; return nil end
  pcall(img.setFilter, img, "linear", "linear")
  images[name] = img
  return img
end

BattleBoxXY._art = art     -- named for the suite

-- One button, fitted INSIDE its slot with its own aspect kept. The four
-- buttons are different shapes -- FIGHT is a full oval, the other three are
-- the top half of a capsule -- so a slot is a box to fit into rather than a
-- rectangle to stretch over. Stretching them to a common rectangle is what
-- would make them stop looking like the pack's buttons.
-- `align` is "bottom" for the three half-capsules: the pack draws them as the
-- TOP half of a button, so they are meant to sit on a floor. Centred in their
-- slot they float with air under them and read as clipped rather than seated.
local function button(x, y, w, h, cmd, selected, align)
  local img = art(cmd.art)
  if not img then
    -- the art did not load: a coloured rounded rectangle with the game's own
    -- word on it, which is legible and does not pretend to be the pack
    local r = math.min(h * 0.48, 18)
    local c = cmd.color
    love.graphics.setColor(c[1], c[2], c[3], selected and 1 or BattleBoxXY.DIM)
    love.graphics.rectangle("fill", x, y, w, h, r, r)
    local th = h * 0.46
    local tw = BattleHudXY.textWidth(cmd.label) * (th / 84)
    BattleHudXY.text(cmd.label, x + (w - tw) * 0.5, y + (h - th) * 0.5, th,
                     BattleBoxXY.TEXT)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  local iw, ih = img:getDimensions()
  local shrink = selected and 1 or BattleBoxXY.UNSEL_SCALE
  local s = math.min(w / iw, h / ih) * shrink
  local dw, dh = iw * s, ih * s
  local dx = x + (w - dw) * 0.5
  local dy = (align == "bottom") and (y + h - dh) or (y + (h - dh) * 0.5)

  if selected then
    -- a soft halo, drawn as the same button blown up slightly and dimmed.
    -- Cheaper than a shader and it follows whatever shape the button is,
    -- which a rounded rectangle behind it would not.
    love.graphics.setColor(1, 1, 1, 0.35)
    local gs = s * 1.06
    local gy = (align == "bottom") and (y + h - ih * gs)
               or (y + (h - ih * gs) * 0.5)
    love.graphics.draw(img, x + (w - iw * gs) * 0.5, gy, 0, gs, gs)
  end
  love.graphics.setColor(1, 1, 1, selected and 1 or BattleBoxXY.UNSEL_ALPHA)
  love.graphics.draw(img, dx, dy, 0, s, s)
  love.graphics.setColor(1, 1, 1, 1)
end

-- ------- the draw
--
-- `rect` is the text box in WORLD-canvas pixels, which is what the caller
-- already computed for the frosted panel it is replacing.
function BattleBoxXY.draw(battle, rect)
  if not (rect and BattleBoxXY.covers(battle)) then return false end
  local x, y, w, h = rect[1], rect[2], rect[3], rect[4]
  if not (w and h) or w < 8 or h < 8 then return false end

  local menuUp = (battle.phase == "menu")
  local pad = h * BattleBoxXY.PAD

  -- The panel grows upward with the buttons, so FIGHT is inside it rather
  -- than standing on it. Anchored on the box's BOTTOM edge either way: that
  -- line is where every message in the game has been read from, and moving it
  -- would make the menu feel like it belongs to a different screen.
  local ph = menuUp and (h * BattleBoxXY.MENU_GROW) or h
  local py = y + h - ph
  panel(x, py, w, ph)

  local textW = w

  local msg = battle.current and battle.current.text
  local shown = revealed(msg, battle.charIndex)
  local th = h * BattleBoxXY.TEXT_H
  local ly = y + pad
  for _, line in ipairs(lines(shown)) do
    BattleHudXY.text(line, x + pad, ly, th, BattleBoxXY.TEXT)
    ly = ly + th * BattleBoxXY.LINE_GAP
  end

  if menuUp then
    local bx = x + pad
    local bw = w - pad * 2
    local bh = ph - pad * 2
    local by = py + pad
    local sel = tonumber(battle.menuIndex) or 1

    -- FIGHT: centred, on its own, taking the top band
    local fh = bh * BattleBoxXY.FIGHT_FRAC
    local fw = bw * BattleBoxXY.FIGHT_WIDE
    button(bx + (bw - fw) * 0.5, by, fw, fh, BattleBoxXY.COMMANDS[1], sel == 1)

    -- and the other three along the bottom edge, running off it
    local gap = bw * BattleBoxXY.STACK_GAP
    local sw = (bw - gap * 2) / 3
    local sy = by + fh
    local sh = bh - fh
    for slot, i in ipairs(BattleBoxXY.BOTTOM_ORDER) do
      button(bx + (slot - 1) * (sw + gap), sy, sw, sh,
             BattleBoxXY.COMMANDS[i], sel == i, "bottom")
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

-- ------- silencing the engine's box
--
-- On the CLASS, unlike the start menu -- a battle is not a screen object the
-- mod gets handed, and OverworldBattle already wraps BattleState this way
-- (see its install()). Idempotent for the same reason.
--
-- Only the box: the HUDs are lib/BattleHudXY.lua's and the pics are the
-- engine's own. And only while this can actually draw, so a driver that
-- cannot load the font still gets the Game Boy's box rather than none.
-- Silence this ONE battle's box, on the instance.
--
-- The class wrap below could not win: `BattleState.drawTextArea` is a
-- different function by the time a battle is running than it was at install
-- time -- three wrappers in this mod alone plus a separate `quality_of_life`
-- mod all reassign it, and whichever captured its `inner` first and assigned
-- last leaves everyone else's wrapper pointing at a chain nobody calls.
--
-- An instance field does not have to win that argument. Lua looks at the
-- object before the metatable, so this shadows whatever the class currently
-- holds, however many wrappers deep it is -- and it dies with the battle, so
-- nothing outlives the fight. Same trick the start menu uses on its own
-- instance, and for the same reason.
function BattleBoxXY.claim(battle)
  if type(battle) ~= "table" then return false end
  if rawget(battle, "terrariumXYBox") then return true end
  if not BattleBoxXY.available() then return false end
  rawset(battle, "terrariumXYBox", true)
  rawset(battle, "drawTextArea", function(self, ...)
    -- asked per frame AND per phase: the row can be switched off mid-battle,
    -- and the move list is the engine's either way (see PHASES)
    if BattleBoxXY.covers(self) then return end
    local mt = getmetatable(self)
    local classDraw = mt and mt.__index and mt.__index.drawTextArea
    if classDraw then return classDraw(self, ...) end
  end)
  return true
end

function BattleBoxXY.install()
  local ok, BattleState = pcall(require, "src.battle.BattleState")
  if not (ok and BattleState) then return false end
  if BattleState.terrariumXYBox then return true end
  local inner = BattleState.drawTextArea
  if type(inner) ~= "function" then return false end
  BattleState.drawTextArea = function(self, ...)
    -- Named for the suite: which branch each call took. "the box is still
    -- there" is not a diagnosis -- the box being drawn by the engine because
    -- this wrapper declined is a different bug from this wrapper never being
    -- reached, and the picture cannot tell them apart.
    local st = BattleBoxXY._stats
    if st then
      local k = (self.dramaticShapeShot and "shot" or "noshot") ..
                (BattleBoxXY.available() and ".avail" or ".unavail")
      st[k] = (st[k] or 0) + 1
    end
    -- `dramaticShapeShot` is how the rest of the mod asks "is this battle
    -- being drawn over the diorama": on the plain battle background the
    -- engine's own box is right and nothing here should run.
    if self.dramaticShapeShot and BattleBoxXY.available() then return end
    return inner(self, ...)
  end
  BattleState.terrariumXYBox = true
  return true
end

return BattleBoxXY
