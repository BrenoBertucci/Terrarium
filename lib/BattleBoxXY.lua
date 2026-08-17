-- The battle's text box and command buttons, at the window's resolution.
--
-- Same problem the start menu had and the same answer: the engine draws its
-- box into the 160x144 UI canvas, so anything drawn THERE arrives on screen
-- at Game Boy resolution. This draws into the world canvas instead, from
-- inside OverworldBattle.snapHUDs, which is already bound to it.
--
-- WHAT IS REPLACED. The box's frame and fill, the message text, the four
-- commands -- drawn as buttons rather than as two columns of words with an
-- arrow beside one of them -- and the move list, drawn as one row per move
-- in the move's own type colour, with the type icon, the PP count and a
-- card for the selected move where the Game Boy put its TYPE/ box.
--
-- WHAT IS NOT. Which commands and moves exist, which one is highlighted,
-- what the message says, and how fast it types. All of it is read off the
-- battle every frame: `menuIndex` (1..4 in reading order, found by moving
-- the cursor and watching which field changed), `moveIndex`,
-- `player.curMoves`, `current.text`, and `charIndex`, which is the
-- typewriter's own cursor -- honouring it is what keeps the text appearing
-- a letter at a time instead of all at once.
--
-- EVERYTHING FITS IN THE BOX'S OWN RECT. The first cut of this menu grew
-- the panel to 1.9x the box's height, full width -- measured on a 1080p
-- window that is a 1200x684 slab, which buried the player's own mon and
-- most of the arena the mode exists to show. Nothing here leaves the
-- bottom third now: the message keeps to the left of the box, the buttons
-- and the move rows float on the right, and the world stays visible above
-- them. That is also what lets the player's HUD capsule sit still -- it
-- used to step upward to dodge the grown panel.
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

-- X/Y stands FIGHT on its own, big, with the other three along the bottom
-- edge running off it -- the shape says "this is the one you press" before
-- any word is read, and the three are drawn as the top half of a capsule
-- precisely so they can be cut by the edge of the screen. menuIndex's own
-- order is preserved underneath: the cursor still moves the way the engine
-- moves it, only the boxes it lands on have changed shape.
--
-- The cluster takes the RIGHT end of the box's rect and the message keeps
-- the left, so the whole menu lives in the bottom third of the letterbox.
-- The buttons float on the world with no panel behind them, X/Y's own
-- arrangement -- the art is opaque and carries its own silhouette, and a
-- backing slab behind it is how the first cut ended up covering the frame.
BattleBoxXY.MSG_FRAC = 0.52        -- of the box's width, for the message panel
BattleBoxXY.MENU_MSG_H = 0.78      -- and of its height, while the menu is up
BattleBoxXY.CLUSTER_FRAC = 0.46    -- of the box's width, for the buttons
BattleBoxXY.FIGHT_FRAC = 0.54      -- of the box's height, for FIGHT's band
BattleBoxXY.FIGHT_WIDE = 0.80      -- of the cluster's width
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

-- Landing on a button POPS it: it starts at the unselected scale, overshoots
-- full size and settles, and while it sits selected it breathes. Both are
-- functions of the wall clock rather than of a stored velocity, so a frame
-- hitch skips ahead instead of accumulating.
BattleBoxXY.POP_TIME = 0.16        -- seconds, cursor-landing pop
BattleBoxXY.POP_OVER = 0.10        -- how far past full size the pop swings
BattleBoxXY.PULSE = 0.013          -- idle breathing, as a scale amplitude
BattleBoxXY.PULSE_HZ = 1.4

-- The move list: one row per move on the right, the selected move's card on
-- the left where the Game Boy put its TYPE/ box. Rows keep four slots of
-- height whatever the mon knows, so a one-move mon gets one full-sized row
-- and three empty slots rather than one row the height of the box.
BattleBoxXY.INFO_FRAC = 0.30       -- of the box's width, for the move card
BattleBoxXY.MOVE_GAP = 0.035       -- between rows, as a fraction of box height
BattleBoxXY.ROW_SEL_ALPHA = 0.96
BattleBoxXY.ROW_UNSEL_ALPHA = 0.55

-- The series' own type colours, keyed by the type's display name. A type
-- this table does not know (a mod's) falls back to slate.
BattleBoxXY.TYPE_COLOR = {
  NORMAL   = { 0.66, 0.66, 0.47 },
  FIGHTING = { 0.75, 0.19, 0.16 },
  FLYING   = { 0.66, 0.56, 0.94 },
  POISON   = { 0.63, 0.25, 0.63 },
  GROUND   = { 0.88, 0.75, 0.41 },
  ROCK     = { 0.72, 0.63, 0.22 },
  BUG      = { 0.66, 0.72, 0.13 },
  GHOST    = { 0.44, 0.34, 0.60 },
  FIRE     = { 0.94, 0.50, 0.19 },
  WATER    = { 0.41, 0.56, 0.94 },
  GRASS    = { 0.47, 0.78, 0.31 },
  ELECTRIC = { 0.91, 0.77, 0.19 },
  PSYCHIC  = { 0.97, 0.35, 0.53 },
  ICE      = { 0.60, 0.85, 0.85 },
  DRAGON   = { 0.44, 0.22, 0.97 },
}
BattleBoxXY.TYPE_FALLBACK = { 0.45, 0.47, 0.52 }

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
  moveSelect = true,  -- the move rows and the selected move's card
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

-- ------- the selection's motion
--
-- One clock, two motions: a pop when the cursor lands (starts at the
-- unselected scale, overshoots by POP_OVER, settles at 1) and a slow breath
-- while it sits there. `group` keeps the command menu's cursor and the move
-- list's from resetting each other's pop.
local anim = {}

local function popScale(group, sel)
  local t = (love.timer and love.timer.getTime) and love.timer.getTime() or 0
  local a = anim[group]
  if not a or a.sel ~= sel then
    a = { sel = sel, at = t }
    anim[group] = a
  end
  local s = 1 + BattleBoxXY.PULSE
            * math.sin(t * BattleBoxXY.PULSE_HZ * 2 * math.pi)
  local dt = t - a.at
  if dt < BattleBoxXY.POP_TIME then
    local p = dt / BattleBoxXY.POP_TIME
    local u = BattleBoxXY.UNSEL_SCALE
    s = s * (u + (1 - u) * p + BattleBoxXY.POP_OVER * math.sin(p * math.pi))
  end
  return s
end

-- Text over a coloured fill needs its own contrast: the same offset copy in
-- black first, which reads as a cast shadow and keeps white glyphs legible
-- on ELECTRIC yellow as well as on GHOST purple.
local function shadowText(str, x, y, th, color)
  local off = math.max(1, th * 0.06)
  BattleHudXY.text(str, x + off, y + off, th, { 0, 0, 0, 0.55 })
  BattleHudXY.text(str, x, y, th, color or BattleBoxXY.TEXT)
end

-- Exported for the party and bag screens (lib/BattleScreenXY.lua): one
-- clock and one shadow across the whole battle costume, so every cursor in
-- it pops the same way. The anim table is shared on purpose -- the groups
-- keep the cursors apart.
BattleBoxXY.popScale = popScale
BattleBoxXY.shadowText = shadowText

-- One button, fitted INSIDE its slot with its own aspect kept. The four
-- buttons are different shapes -- FIGHT is a full oval, the other three are
-- the top half of a capsule -- so a slot is a box to fit into rather than a
-- rectangle to stretch over. Stretching them to a common rectangle is what
-- would make them stop looking like the pack's buttons.
-- `align` is "bottom" for the three half-capsules: the pack draws them as the
-- TOP half of a button, so they are meant to sit on a floor. Centred in their
-- slot they float with air under them and read as clipped rather than seated.
-- `mul` is the selection's animated scale (popScale); 1 when still.
local function button(x, y, w, h, cmd, selected, align, mul)
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
  local shrink = selected and (mul or 1) or BattleBoxXY.UNSEL_SCALE
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

-- ------- the message, typed into a panel
local function drawMessage(battle, x, y, w, h)
  local pad = h * BattleBoxXY.PAD
  panel(x, y, w, h)
  local msg = battle.current and battle.current.text
  local shown = revealed(msg, battle.charIndex)
  local th = h * BattleBoxXY.TEXT_H
  local ly = y + pad
  for _, line in ipairs(lines(shown)) do
    BattleHudXY.text(line, x + pad, ly, th, BattleBoxXY.TEXT)
    ly = ly + th * BattleBoxXY.LINE_GAP
  end
end

-- ------- the command menu: message left, cluster right, nothing grows
--
-- The menu phase has no `current.text` -- on the Game Boy the "What will
-- <mon> do?" prompt belongs to the LAYOUT, printed beside the commands (see
-- the engine's WideBattle.drawWide), so an empty panel here is not a missing
-- message, it is a prompt this file has to print itself. Through the
-- engine's own Strings so a translated build stays translated, and skipped
-- for the demo battle for the reason the engine skips it: Oak's scripted
-- catch has nobody to name (its #557).
local Strings = nil

local function engineString(s)
  if Strings == nil then
    local ok, S = pcall(require, "src.core.Strings")
    Strings = (ok and S) or false
  end
  if Strings then
    local ok, out = pcall(Strings, s)
    if ok and out then return out end
  end
  return s
end

local function drawMenu(battle, x, y, w, h)
  local pad = h * BattleBoxXY.PAD
  local mw = w * BattleBoxXY.MSG_FRAC
  local mh = h * BattleBoxXY.MENU_MSG_H
  local my = y + h - mh
  panel(x, my, mw, mh)
  local shown = revealed(battle.current and battle.current.text,
                         battle.charIndex)
  local msgLines
  if shown ~= "" then
    msgLines = lines(shown)
  elseif not battle.demo then
    local who = (battle.player and battle.player.name) or ""
    msgLines = { engineString("What will"), who .. engineString(" do?") }
  else
    msgLines = {}
  end
  local th = h * BattleBoxXY.TEXT_H
  local ly = my + pad
  for _, line in ipairs(msgLines) do
    BattleHudXY.text(line, x + pad, ly, th, BattleBoxXY.TEXT)
    ly = ly + th * BattleBoxXY.LINE_GAP
  end

  local cw = w * BattleBoxXY.CLUSTER_FRAC
  local cx = x + w - cw
  local sel = tonumber(battle.menuIndex) or 1
  local pop = popScale("menu", sel)

  -- FIGHT: centred, on its own, taking the top band
  local fh = h * BattleBoxXY.FIGHT_FRAC
  local fw = cw * BattleBoxXY.FIGHT_WIDE
  button(cx + (cw - fw) * 0.5, y, fw, fh, BattleBoxXY.COMMANDS[1],
         sel == 1, nil, pop)

  -- and the other three along the bottom edge, running off it
  local gap = cw * BattleBoxXY.STACK_GAP
  local sw = (cw - gap * 2) / 3
  local sy = y + fh
  local sh = h - fh
  for slot, i in ipairs(BattleBoxXY.BOTTOM_ORDER) do
    button(cx + (slot - 1) * (sw + gap), sy, sw, sh,
           BattleBoxXY.COMMANDS[i], sel == i, "bottom", pop)
  end
end

-- ------- the move list
--
-- What the engine knows about a move the mod did not inject: `def.name`,
-- `def.type`, `def.pp`, `def.power`, `def.category` (see
-- src/battle/BattleState.lua's moveSelect draw and Damage.lua). A def the
-- data table does not carry -- a mod-injected id -- prints its raw id on a
-- slate row, the engine's own fallback policy.
local TypeChart = nil

local function typeName(ty)
  if ty == nil then return nil end
  if TypeChart == nil then
    local ok, TC = pcall(require, "src.battle.TypeChart")
    TypeChart = (ok and TC) or false
  end
  local name = TypeChart and TypeChart.displayName and TypeChart.displayName(ty)
  return tostring(name or ty):upper()
end

local function ppOf(mv, def)
  if not (mv and def and def.pp) then return nil, nil end
  local maxPP = def.pp + (mv.ppUps or 0) * math.floor(def.pp / 5)
  return mv.pp or 0, maxPP
end

-- White above half, amber below, red at empty -- and never colour alone:
-- the numbers themselves are the information.
local function ppColor(pp, maxPP)
  if not (pp and maxPP) or maxPP == 0 then return BattleBoxXY.TEXT end
  local r = pp / maxPP
  if pp == 0 then return { 1.0, 0.42, 0.38, 1 } end
  if r <= 0.5 then return { 1.0, 0.84, 0.40, 1 } end
  return BattleBoxXY.TEXT
end

-- One move row: a rounded slab in the type's colour, the type's icon, the
-- name, and the PP count on the right edge. Selected rows sit at full
-- colour with a ring and the pop; the rest step back the way the command
-- buttons do. `ring` overrides the ring colour for the swap marker.
local function moveRow(x, y, w, h, label, tcolor, icon, ppText, ppCol,
                       selected, mul, ring)
  if selected and mul then
    local dw, dh = w * (mul - 1), h * (mul - 1)
    x, y, w, h = x - dw * 0.5, y - dh * 0.5, w + dw, h + dh
  end
  local r = math.min(h * 0.38, 16)
  local c = tcolor or BattleBoxXY.TYPE_FALLBACK
  -- A dark base first, the type's colour on top. The colour alone at row
  -- alpha dissolves into a bright floor -- measured on Vermilion's tiled
  -- ground, where an unselected ELECTRIC row all but vanished -- and
  -- darkening the colour itself would shift its identity. The base buys the
  -- contrast, the overlay keeps the hue.
  setColor(BattleBoxXY.PANEL, selected and 0.85 or 0.75)
  love.graphics.rectangle("fill", x, y, w, h, r, r)
  love.graphics.setColor(c[1], c[2], c[3],
                         selected and BattleBoxXY.ROW_SEL_ALPHA
                                  or BattleBoxXY.ROW_UNSEL_ALPHA)
  love.graphics.rectangle("fill", x, y, w, h, r, r)
  if selected or ring then
    setColor(ring or BattleBoxXY.SELECT_RING)
    love.graphics.setLineWidth(math.max(2, h * 0.045))
    love.graphics.rectangle("line", x, y, w, h, r, r)
    love.graphics.setLineWidth(1)
  end

  local pad = h * 0.18
  local tx = x + pad
  if icon then
    local iw, ih = icon:getDimensions()
    local is = (h * 0.64) / math.max(1, ih)
    love.graphics.setColor(1, 1, 1, selected and 1 or 0.75)
    love.graphics.draw(icon, tx, y + (h - ih * is) * 0.5, 0, is, is)
    tx = tx + iw * is + pad
  end

  local th = h * 0.42
  local alpha = selected and 1 or 0.85
  shadowText(label, tx, y + (h - th) * 0.5, th,
             { 1, 1, 1, alpha })
  if ppText then
    local tw = BattleHudXY.textWidth(ppText) * (th / 84)
    local pc = ppCol or BattleBoxXY.TEXT
    shadowText(ppText, x + w - pad - tw, y + (h - th) * 0.5, th,
               { pc[1], pc[2], pc[3], (pc[4] or 1) * alpha })
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- The selected move's card, where the Game Boy put its TYPE/ box: the type
-- icon with its name, the power (or STATUS), and the PP -- the stats a
-- player is actually weighing when the cursor moves.
local function drawMoveCard(x, y, w, h, def, mv, disabled)
  panel(x, y, w, h)
  local pad = h * BattleBoxXY.PAD
  local th = h * 0.155
  local cx = x + w * 0.5

  local ly = y + pad
  local tname = def and typeName(def.type)
  local icon = tname and art("types/" .. tname)
  if icon then
    local iw, ih = icon:getDimensions()
    local is = (h * 0.30) / math.max(1, ih)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(icon, cx - iw * is * 0.5, ly, 0, is, is)
    ly = ly + ih * is + pad * 0.6
  elseif tname then
    local tw = BattleHudXY.textWidth(tname) * (th / 84)
    shadowText(tname, cx - tw * 0.5, ly, th, BattleBoxXY.TEXT)
    ly = ly + th * BattleBoxXY.LINE_GAP
  end

  local linesOut = {}
  if disabled then
    linesOut[#linesOut + 1] = { "DISABLED!", { 1.0, 0.42, 0.38, 1 } }
  elseif def and (not def.power or def.power == 0
                  or def.category == "status") then
    linesOut[#linesOut + 1] = { "STATUS", BattleBoxXY.TEXT }
  elseif def then
    linesOut[#linesOut + 1] = { "POWER " .. tostring(def.power),
                                BattleBoxXY.TEXT }
  end
  local pp, maxPP = ppOf(mv, def)
  if pp then
    linesOut[#linesOut + 1] = { ("PP %d/%d"):format(pp, maxPP),
                                ppColor(pp, maxPP) }
  end
  for _, ln in ipairs(linesOut) do
    local tw = BattleHudXY.textWidth(ln[1]) * (th / 84)
    shadowText(ln[1], cx - tw * 0.5, ly, th, ln[2])
    ly = ly + th * BattleBoxXY.LINE_GAP
  end
end

local SWAP_RING = { 1.0, 0.84, 0.40, 0.95 }

local function drawMoves(battle, x, y, w, h)
  local moves = (battle.player and battle.player.curMoves) or {}
  if #moves == 0 then return end
  local data = (battle.data and battle.data.moves) or {}
  local sel = math.max(1, math.min(tonumber(battle.moveIndex) or 1, #moves))
  local pop = popScale("moves", sel)

  local iw = w * BattleBoxXY.INFO_FRAC
  local selMv = moves[sel]
  local selDef = selMv and data[selMv.id]
  drawMoveCard(x, y, iw, h, selDef, selMv,
               battle.player.disabledSlot == sel)

  local gap = h * BattleBoxXY.MOVE_GAP
  local rx = x + iw + gap
  local rw = w - iw - gap
  local rowH = (h - gap * 3) / 4
  for i, mv in ipairs(moves) do
    local def = data[mv.id]
    local tname = def and typeName(def.type)
    local pp, maxPP = ppOf(mv, def)
    moveRow(rx, y + (i - 1) * (rowH + gap), rw, rowH,
            (def and def.name) or tostring(mv.id),
            tname and BattleBoxXY.TYPE_COLOR[tname],
            tname and art("types/" .. tname),
            pp and ("%d/%d"):format(pp, maxPP), ppColor(pp, maxPP),
            i == sel, pop,
            (battle.moveSwapIndex and battle.moveSwapIndex == i
             and battle.moveSwapIndex ~= sel) and SWAP_RING or nil)
  end
end

-- ------- the draw
--
-- `rect` is the text box in WORLD-canvas pixels, which is what the caller
-- already computed for the frosted panel it is replacing. Every phase stays
-- inside it.
function BattleBoxXY.draw(battle, rect)
  if not (rect and BattleBoxXY.covers(battle)) then return false end
  local x, y, w, h = rect[1], rect[2], rect[3], rect[4]
  if not (w and h) or w < 8 or h < 8 then return false end

  if battle.phase == "menu" then
    drawMenu(battle, x, y, w, h)
  elseif battle.phase == "moveSelect" then
    drawMoves(battle, x, y, w, h)
  else
    drawMessage(battle, x, y, w, h)
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
