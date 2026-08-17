-- The battle's party and bag, drawn over the diorama instead of over white.
--
-- Choosing PKMN or ITENS mid-battle pushes the engine's PartyMenu or the
-- bag's ListMenu onto the stack, and both are OPAQUE 160x144 screens: the
-- arena the mode spent a whole render pipeline standing up is replaced by a
-- white Game Boy page until the player backs out. Same disease the start
-- menu had, one screen deeper.
--
-- The cure is the engine's own seam. StateStack asks the
-- `screen.render_visible` hook before counting a state toward the visible
-- base, precisely so a mod can mirror a screen elsewhere and hide the
-- original: answered false (main.lua wires it, gated on a staged battle),
-- the party screen stays on the stack -- update, input and every choice
-- still its own -- but the frame's visible base falls through to the battle
-- underneath, and the diorama keeps drawing with the camera still drifting.
-- This file then draws the screen's STATE at the window's resolution, from
-- inside OverworldBattle.snapHUDs, which is already bound to the world
-- canvas: a costume over live engine state, the StartMenuXY trick with a
-- battle under it instead of a route.
--
-- WHAT IS DRAWN. For the party: a veil to push the arena back, a card per
-- mon -- the engine's own animated icon, name, level, an HP bar in the HP's
-- own colour, the status as a chip -- plus the SWITCH/STATS submenu as
-- pills and the screen's own bottom message. For a list (the ether's
-- "Which move?" picker and anything else ListMenu-shaped): a column of rows
-- with the quantity on the right edge, a scrollbar when the list outgrows
-- the window, and the screen's footer.
--
-- THE BAG GETS POCKETS. Gen 1 has one inventory in acquisition order; the
-- DS games split it into pockets and that is the shape this draws: a tab
-- strip (ITENS / CURA / BOLAS / TM/HM), rows grouped under whichever tab
-- the cursor is in, LEFT/RIGHT to change pocket with the cursor's place in
-- each remembered. That needs more than a costume -- grouped rows and a
-- linear cursor cannot both be true -- so the bag's NAVIGATION is taken
-- over through the engine's own seam for exactly that: ListMenu.script,
-- which replaces update's input reading wholesale (the old-man tutorial is
-- the engine's own user of it, and a list already carrying a script is
-- left alone). What A, B and SELECT do is still the list's own handlers
-- (onChoose, onCancel, onSelectKey); the takeover decides only which row
-- the cursor stands on. The pocketing is display and motion; the items,
-- their order in the save, and every effect stay the engine's.
--
-- WHAT IS NOT. Cursor movement, wrapping, what A and B do, the heal
-- animation's pacing, which rows exist -- all read off the screen instance
-- every frame (`index`, `subIndex`, `swapFrom`, `heal.shown`, `items`,
-- `scroll`...). The one number this file animates that the engine does not
-- is presentation: the pop on a landed cursor and the staggered slide-in
-- when a screen opens.
--
-- NESTED SCREENS. While a picker sits on TOP of the bag, the bag is no
-- longer the stack's top -- but it is still opaque, and letting it back
-- into the visible base would put the white page under the picker. So
-- main.lua hides every covered SHAPE on the stack during a staged battle,
-- and this file draws only the top one. A TextBox or the STATS summary is
-- not a covered shape: those stay the engine's, drawn where the engine
-- draws them.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local BattleScreenXY = {}

BattleScreenXY.ENABLED = true

local BattleHudXY = V.require("BattleHudXY")
local BattleBoxXY = V.require("BattleBoxXY")

-- ------- the look, shared with the rest of the X/Y costume
BattleScreenXY.VEIL = { 0.03, 0.04, 0.06, 0.42 }
BattleScreenXY.PANEL = { 0.08, 0.09, 0.12, 0.90 }
BattleScreenXY.PANEL_EDGE = { 0.62, 0.67, 0.78, 0.60 }
BattleScreenXY.CARD = { 0.10, 0.11, 0.15, 0.92 }
BattleScreenXY.CARD_SEL = { 0.14, 0.18, 0.27, 0.96 }
BattleScreenXY.ACCENT = { 0.20, 0.52, 0.86, 0.95 }
BattleScreenXY.RING = { 1, 1, 1, 0.95 }
BattleScreenXY.SWAP_RING = { 1.0, 0.84, 0.40, 0.95 }
BattleScreenXY.TEXT = { 1, 1, 1, 1 }
BattleScreenXY.TEXT_DIM = { 0.78, 0.80, 0.85, 1 }

-- The bar's colour bands are Gen 1's own thirds: green while comfortable,
-- amber under half, red at the tail end.
BattleScreenXY.HP_TRACK = { 0.04, 0.05, 0.07, 0.85 }
BattleScreenXY.HP_GREEN = { 0.30, 0.85, 0.35 }
BattleScreenXY.HP_YELLOW = { 0.95, 0.80, 0.25 }
BattleScreenXY.HP_RED = { 0.94, 0.30, 0.25 }

BattleScreenXY.STATUS_COLOR = {
  PSN = { 0.63, 0.25, 0.63 },
  BRN = { 0.94, 0.50, 0.19 },
  PAR = { 0.91, 0.77, 0.19 },
  SLP = { 0.55, 0.60, 0.75 },
  FRZ = { 0.60, 0.85, 0.85 },
  FNT = { 0.94, 0.30, 0.25 },
}

-- ------- the entrance
--
-- A screen OPENING is a fact worth a frame of motion: the cards slide in
-- with a small stagger, eased so they land rather than stop. Wall-clock
-- like the cursor pop, so a hitch skips ahead instead of accumulating.
BattleScreenXY.IN_TIME = 0.22      -- seconds per element
BattleScreenXY.IN_STAGGER = 0.05   -- extra delay per row/card
BattleScreenXY.SLIDE_FRAC = 0.045  -- slide distance, of the letterbox width

-- `subAt` is the bag's second clock: switching pockets replays the rows'
-- entrance without replaying the panel's.
local entrance = { key = nil, at = 0, subAt = 0 }

local function now()
  return (love.timer and love.timer.getTime) and love.timer.getTime() or 0
end

-- 0..1 progress of element `i`'s entrance, eased (cubic out). `since`
-- defaults to the screen's own opening.
local function enterEase(i, since)
  local dt = now() - (since or entrance.at)
             - (i - 1) * BattleScreenXY.IN_STAGGER
  if dt <= 0 then return 0 end
  local p = math.min(1, dt / BattleScreenXY.IN_TIME)
  return 1 - (1 - p) * (1 - p) * (1 - p)
end

-- ------- identifying the screens this file covers
--
-- By SHAPE, with the stamp as a corroborating witness, the StartMenuXY
-- policy: a party screen is whatever Screens stamped "PartyMenu" that
-- carries a numeric cursor, and a list is whatever holds an items array
-- with a cursor and a scroll -- the trio ListMenu.new always builds. A
-- TextBox, a ChoiceBox or the summary matches neither and stays visible.
local function partyShape(s)
  return type(s) == "table" and s.screenId == "PartyMenu"
         and type(s.index) == "number"
end

local function listShape(s)
  return type(s) == "table" and type(s.items) == "table"
         and type(s.index) == "number" and type(s.scroll) == "number"
end

function BattleScreenXY.available()
  return BattleScreenXY.ENABLED and BattleHudXY.available()
end

-- Should `state`'s own render be hidden? Asked by the render_visible hook
-- (main.lua), for every state on the stack -- which is what keeps a bag
-- UNDER a party picker hidden too, instead of flashing its white page back
-- the moment it stops being the top.
function BattleScreenXY.hides(state)
  if not BattleScreenXY.available() then return false end
  return partyShape(state) or listShape(state)
end

-- The covered screen this frame's frame should show: the stack's top, or
-- nothing. Below-top covered screens are hidden but not drawn.
function BattleScreenXY.of(game)
  local top = game and game.stack and game.stack:top()
  if partyShape(top) then return top, "party" end
  if listShape(top) then return top, "list" end
  return nil
end

-- ------- small draw helpers
local function setColor(c, a)
  love.graphics.setColor(c[1], c[2], c[3], (a or 1) * (c[4] or 1))
end

local function rounded(mode, x, y, w, h, c, a, rFrac)
  local r = math.min(h * (rFrac or 0.30), 18)
  setColor(c, a)
  love.graphics.rectangle(mode, x, y, w, h, r, r)
end

local function panel(x, y, w, h, a)
  rounded("fill", x, y, w, h, BattleScreenXY.PANEL, a, 0.18)
  love.graphics.setLineWidth(2)
  rounded("line", x, y, w, h, BattleScreenXY.PANEL_EDGE, a, 0.18)
  love.graphics.setLineWidth(1)
end

local function ring(x, y, w, h, c, a, lw)
  love.graphics.setLineWidth(lw or 3)
  rounded("line", x, y, w, h, c, a)
  love.graphics.setLineWidth(1)
end

local function text(str, x, y, th, c, a)
  BattleBoxXY.shadowText(str, x, y, th,
                         { c[1], c[2], c[3], (c[4] or 1) * (a or 1) })
end

local function textW(str, th)
  return BattleHudXY.textWidth(str) * (th / 84)
end

local function hpColor(ratio)
  if ratio <= 0.2 then return BattleScreenXY.HP_RED end
  if ratio <= 0.5 then return BattleScreenXY.HP_YELLOW end
  return BattleScreenXY.HP_GREEN
end

-- ------- one party card
--
-- `shownHP` is what the bar draws, which during a medicine's fill is the
-- engine's own animation (heal.shown) rather than the final value -- the
-- same shim PartyMenu:draw uses, so the bar lengthens at the pace the
-- engine set (#252 over there).
local function partyCard(game, mon, x, y, w, h, opts)
  local a = opts.alpha
  local sel = opts.selected
  rounded("fill", x, y, w, h,
          sel and BattleScreenXY.CARD_SEL or BattleScreenXY.CARD, a)
  if sel then
    ring(x, y, w, h, BattleScreenXY.RING, a, math.max(2, h * 0.035))
  elseif opts.swapMark then
    ring(x, y, w, h, BattleScreenXY.SWAP_RING, a, math.max(2, h * 0.035))
  end

  local pad = h * 0.12
  local fnt = mon.hp <= 0

  -- the engine's own party icon, scaled up and still animating: drawIcon
  -- takes the menu's frame counter, so the mon keeps walking in place here
  -- exactly as it does on the Game Boy screen
  local iconS = (h * 0.72) / 16
  local ix = x + pad
  local okPM, PartyMenu = pcall(require, "src.ui.PartyMenu")
  if okPM and PartyMenu and PartyMenu.drawIcon then
    love.graphics.push()
    love.graphics.translate(ix, y + (h - 16 * iconS) * 0.55)
    love.graphics.scale(iconS, iconS)
    love.graphics.setColor(1, 1, 1, a * (fnt and 0.45 or 1))
    pcall(PartyMenu.drawIcon, game, mon, 0, 0, sel, opts.counter or 0)
    love.graphics.pop()
  end
  local tx = ix + 16 * iconS + pad * 0.8

  local def = game.data and game.data.pokemon
              and game.data.pokemon[mon.species]
  local name = mon.nickname or (def and def.name) or tostring(mon.species)
  local dimA = a * (fnt and 0.55 or 1)
  local th = h * 0.24
  local lv = "Lv." .. tostring(mon.level)
  local lvTh = th * 0.9
  local lvX = x + w - pad - textW(lv, lvTh)
  -- a long name shrinks to fit the room the level leaves, rather than
  -- running under it -- BLASTOISE taught this line its manners
  local avail = lvX - pad * 0.6 - tx
  local nth = th * math.min(1, avail / math.max(1, textW(name, th)))
  text(name, tx, y + pad * 0.8 + (th - nth) * 0.5, nth,
       BattleScreenXY.TEXT, dimA)
  text(lv, lvX, y + pad * 0.8, lvTh, BattleScreenXY.TEXT_DIM, dimA)

  -- the bar, in the HP's own colour
  local maxHP = (mon.stats and mon.stats.hp) or 1
  local shown = math.max(0, math.min(opts.shownHP or mon.hp, maxHP))
  local ratio = shown / math.max(1, maxHP)
  local bx = tx
  local bw = x + w - pad - bx
  local bh = h * 0.13
  local by = y + h * 0.52
  rounded("fill", bx, by, bw, bh, BattleScreenXY.HP_TRACK, a, 0.5)
  if ratio > 0 then
    local c = hpColor(ratio)
    rounded("fill", bx, by, math.max(bh, bw * ratio), bh, c, a, 0.5)
  end

  local hpText = ("%d/%d"):format(shown, maxHP)
  local th2 = h * 0.20
  text(hpText, x + w - pad - textW(hpText, th2), by + bh + h * 0.05, th2,
       BattleScreenXY.TEXT, dimA)

  -- the status as a chip rather than three raw letters: colour AND the
  -- label, never colour alone
  local status = fnt and "FNT" or mon.status
  if status then
    local sc = BattleScreenXY.STATUS_COLOR[status]
                or BattleScreenXY.TEXT_DIM
    local sth = h * 0.185
    local sw = textW(status, sth) + pad
    rounded("fill", bx, by + bh + h * 0.045, sw, sth * 1.35,
            { sc[1], sc[2], sc[3], 0.9 }, a, 0.5)
    text(status, bx + pad * 0.5, by + bh + h * 0.07, sth,
         BattleScreenXY.TEXT, a)
  end
end

-- ------- the party screen
local function drawParty(game, scr, shot)
  local lx, ly = shot.lx, shot.ly
  local lw, lh = 160 * shot.scale, 144 * shot.scale
  local party = scr.party or (game.save and game.save.party) or {}
  local n = #party
  if n == 0 then return end
  local sel = math.max(1, math.min(scr.index or 1, n))
  local pop = BattleBoxXY.popScale("party", sel)

  -- 2x3 grid, centred; a short party keeps full-sized cards in the same
  -- grid rather than growing to fill it
  local cw = lw * 0.34
  local ch = lh * 0.155
  local gap = lh * 0.022
  local rows = math.ceil(n / 2)
  local gw = (n > 1) and (cw * 2 + gap) or cw
  local gh = rows * ch + (rows - 1) * gap
  local gx = lx + (lw - gw) * 0.5
  local gy = ly + lh * 0.07 + (lh * 0.66 - gh) * 0.5

  local slide = lw * BattleScreenXY.SLIDE_FRAC
  for i, mon in ipairs(party) do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local e = enterEase(i)
    if e > 0 then
      local x = gx + col * (cw + gap) - slide * (1 - e)
      local y = gy + row * (ch + gap)
      local selected = (i == sel)
      local w, h = cw, ch
      if selected then
        local dw, dh = w * (pop - 1), h * (pop - 1)
        x, y, w, h = x - dw * 0.5, y - dh * 0.5, w + dw, h + dh
      end
      local shownHP = mon.hp
      if scr.heal and scr.heal.mon == mon then
        shownHP = math.floor(scr.heal.shown)
      end
      partyCard(game, mon, x, y, w, h, {
        alpha = e,
        selected = selected,
        swapMark = (scr.swapFrom == i or scr.softboiledFrom == i)
                   and i ~= sel,
        counter = scr.blink or 0,
        shownHP = shownHP,
      })
    end
  end

  -- the screen's own message, bottom left -- swap prompts, "Bring out
  -- which POKemon?", the lot, straight from bottomMessage
  local okMsg, msg = pcall(scr.bottomMessage, scr)
  if okMsg and type(msg) == "string" and msg ~= "" then
    local mw = lw * 0.42
    local mh = lh * 0.15
    local mx = lx + lw * 0.02
    local my = ly + lh - mh - lh * 0.02
    panel(mx, my, mw, mh)
    local th = mh * 0.26
    local tly = my + mh * 0.16
    for line in (msg .. "\n"):gmatch("([^\n]*)\n") do
      text(line, mx + mw * 0.06, tly, th, BattleScreenXY.TEXT)
      tly = tly + th * 1.4
    end
  end

  -- the submenu, as pills growing up from the bottom right; labels are the
  -- engine's own (already translated), selection pops like everything else
  if scr.submenu and type(scr.subItems) == "table" then
    local m = #scr.subItems
    local pw = lw * 0.24
    local ph = lh * 0.075
    local pgap = lh * 0.014
    local px = lx + lw - pw - lw * 0.03
    local py0 = ly + lh - lh * 0.03 - m * (ph + pgap)
    local spop = BattleBoxXY.popScale("psub", scr.subIndex or 1)
    for si, entry in ipairs(scr.subItems) do
      local e = enterEase(si)
      local x = px + (lw * BattleScreenXY.SLIDE_FRAC) * (1 - e)
      local y = py0 + (si - 1) * (ph + pgap)
      local selP = (si == (scr.subIndex or 1))
      local w, h = pw, ph
      if selP then
        local dw, dh = w * (spop - 1), h * (spop - 1)
        x, y, w, h = x - dw * 0.5, y - dh * 0.5, w + dw, h + dh
      end
      rounded("fill", x, y, w, h,
              selP and BattleScreenXY.ACCENT or BattleScreenXY.CARD, e, 0.5)
      if selP then ring(x, y, w, h, BattleScreenXY.RING, e, 2) end
      local th = h * 0.42
      local label = tostring(entry.label or "")
      text(label, x + (w - textW(label, th)) * 0.5, y + (h - th) * 0.5,
           th, BattleScreenXY.TEXT, e)
    end
  end
end

-- ------- the bag's pockets
--
-- The taxonomy leans on the engine wherever the engine has one: a ball is
-- whatever ItemEffects.isBall says, healing is healsHP plus the status and
-- PP cures (those tables are ItemEffects locals, so the ten Gen 1 ids are
-- restated here -- they are ROM facts, not moving parts), a machine is any
-- def with the `machine` field. Everything else -- X items, stones,
-- repels, the key items -- is the plain pocket, exactly the DS games'
-- catch-all.
local POCKET_ORDER = { "items", "cura", "balls", "tm" }

BattleScreenXY.POCKET_LABEL = {
  items = "ITENS", cura = "CURA", balls = "BOLAS", tm = "TM/HM",
}

local STATUS_PP_HEAL = {
  ANTIDOTE = true, BURN_HEAL = true, ICE_HEAL = true, AWAKENING = true,
  PARLYZ_HEAL = true, FULL_HEAL = true,
  ETHER = true, MAX_ETHER = true, ELIXER = true, MAX_ELIXER = true,
}

local ItemEffects = nil

local function pocketOf(game, id)
  if ItemEffects == nil then
    local ok, IE = pcall(require, "src.inventory.ItemEffects")
    ItemEffects = (ok and IE) or false
  end
  if ItemEffects and ItemEffects.isBall and ItemEffects.isBall(id) then
    return "balls"
  end
  if STATUS_PP_HEAL[id]
     or (ItemEffects and ItemEffects.healsHP and ItemEffects.healsHP(id)) then
    return "cura"
  end
  local def = game.data and game.data.items and game.data.items[id]
  if def and def.machine then return "tm" end
  return "items"
end

-- engine indices grouped by pocket, in the save's own order within each
local function bagGroups(game, scr)
  local groups = { items = {}, cura = {}, balls = {}, tm = {} }
  for i, it in ipairs(scr.items) do
    local g = groups[pocketOf(game, it.value)]
    g[#g + 1] = i
  end
  return groups
end

-- ListMenu's own beep, restated: HandleMenuInput_ replays SFX_PRESS_AB for
-- watched A/B presses and the harness stub has no audio cache to play from.
local function beep(scr, game)
  if scr.noSound or not (game and game.data) then return end
  pcall(function()
    require("src.core.Sound").play(game.data, "Press_AB")
  end)
end

-- LEFT/RIGHT: the next pocket with anything in it, cyclic, with each
-- pocket's cursor remembered the way the DS bags remember theirs.
local function switchPocket(scr, game, groups, cur, dir)
  local at
  for p, key in ipairs(POCKET_ORDER) do
    if key == cur then at = p break end
  end
  if not at then return end
  for step = 1, #POCKET_ORDER - 1 do
    local key = POCKET_ORDER[((at - 1 + dir * step) % #POCKET_ORDER) + 1]
    local seq = groups[key]
    if #seq > 0 then
      local mem = rawget(scr, "terrariumPocketMem")
      mem[cur] = scr.index
      local target = seq[1]
      local want = mem[key]
      if want then
        for _, i in ipairs(seq) do
          if i == want then target = want break end
        end
      end
      scr.index = target
      entrance.subAt = now()      -- the rows re-enter under the new tab
      beep(scr, game)
      return
    end
  end
end

-- The bag's whole per-frame input read, installed as the list's `script`.
-- UP/DOWN wrap within the pocket; A, B and SELECT hand straight to the
-- list's own handlers, so choosing, closing and the SELECT swap behave to
-- the letter -- a swap across pockets reorders the save's acquisition
-- order, which is what SELECT always did.
local function bagScript(scr, game)
  local input = game.input
  local items = scr.items
  if #items == 0 then
    if input:wasPressed("a") or input:wasPressed("b") then
      beep(scr, game)
      game.stack:pop()
      if scr.onCancel then scr.onCancel() end
    end
    return
  end
  scr.index = math.max(1, math.min(scr.index or 1, #items))
  local groups = bagGroups(game, scr)
  local cur = pocketOf(game, items[scr.index].value)
  local seq = groups[cur]
  local pos = 1
  for p, i in ipairs(seq) do
    if i == scr.index then pos = p break end
  end

  if input:wasPressed("up") then
    scr.index = seq[pos > 1 and pos - 1 or #seq]
  elseif input:wasPressed("down") then
    scr.index = seq[pos < #seq and pos + 1 or 1]
  elseif input:wasPressed("left") then
    switchPocket(scr, game, groups, cur, -1)
  elseif input:wasPressed("right") then
    switchPocket(scr, game, groups, cur, 1)
  elseif scr.onSelectKey and input:wasPressed("select") then
    scr.onSelectKey(items[scr.index], scr)
  elseif input:wasPressed("b") then
    beep(scr, game)
    game.stack:pop()
    if scr.onCancel then scr.onCancel() end
    return
  elseif input:wasPressed("a") then
    beep(scr, game)
    if scr.onChoose then scr.onChoose(items[scr.index], scr) end
    return
  end
  local mem = rawget(scr, "terrariumPocketMem")
  if mem and items[scr.index] then
    mem[pocketOf(game, items[scr.index].value)] = scr.index
  end
end

-- Is this list the battle bag, and if so, take its navigation. Decided
-- once per instance: the bag is the ListMenu that carries both a SELECT
-- handler (the swap) and a footer (the money), and no script of its own --
-- the old man's scripted tutorial bag keeps its script and its lines.
local function bagInstall(scr, game)
  local known = rawget(scr, "terrariumPockets")
  if known ~= nil then return known end
  local isBag = scr.onSelectKey ~= nil and scr.footer ~= nil
                and rawget(scr, "script") == nil
  rawset(scr, "terrariumPockets", isBag)
  if isBag then
    rawset(scr, "terrariumPocketMem", {})
    rawset(scr, "script", function(s) return bagScript(s, game) end)
  end
  return isBag
end

-- ------- a list screen: the move picker, anything ListMenu-shaped
local LIST_ROWS = 8

local function drawList(game, scr, shot)
  local lx, ly = shot.lx, shot.ly
  local lw, lh = 160 * shot.scale, 144 * shot.scale
  local items = scr.items or {}
  local n = #items
  local sel = math.max(1, math.min(scr.index or 1, math.max(1, n)))
  local pop = BattleBoxXY.popScale("list", sel)

  local pw = math.max(280, math.min(560, lw * 0.42))
  local px = lx + lw - pw - lw * 0.025
  local py = ly + lh * 0.05
  local ph = lh * 0.90
  panel(px, py, pw, ph)

  local pad = pw * 0.05
  local th = lh * 0.032

  -- the title is the screen's own ("ITEMS", "Which move?"), so a picker a
  -- mod pushes tomorrow names itself
  local title = tostring(scr.title or "")
  local ty = py + pad
  if title ~= "" then
    text(title, px + pad, ty, th * 1.15, BattleScreenXY.TEXT)
  end
  local top0 = ty + th * 1.15 + pad * 0.7

  local footer = scr.footer and tostring(scr.footer) or nil
  local footH = footer and (th * 1.15 + pad) or pad * 0.6
  local rowsH = py + ph - footH - top0
  local rowH = (rowsH - (LIST_ROWS - 1) * pad * 0.30) / LIST_ROWS
  local rgap = pad * 0.30

  -- this file's own window on the list, centred on the cursor -- the
  -- engine's `scroll` fits 7 GB rows and this panel fits its own count
  local vis = math.min(LIST_ROWS, math.max(1, n))
  local first = math.max(1, math.min(sel - math.floor(vis / 2),
                                     n - vis + 1))
  for slot = 1, vis do
    local i = first + slot - 1
    local item = items[i]
    if not item then break end
    local e = enterEase(slot)
    if e > 0 then
      local x = px + pad + (lw * BattleScreenXY.SLIDE_FRAC) * (1 - e)
      local y = top0 + (slot - 1) * (rowH + rgap)
      local w = pw - pad * 2 - (n > vis and pad * 0.8 or 0)
      local h = rowH
      local selR = (i == sel)
      if selR then
        local dw, dh = w * (pop - 1), h * (pop - 1)
        x, y, w, h = x - dw * 0.5, y - dh * 0.5, w + dw, h + dh
      end
      rounded("fill", x, y, w, h,
              selR and BattleScreenXY.ACCENT or BattleScreenXY.CARD,
              e * (selR and 1 or 0.85), 0.4)
      if selR then
        ring(x, y, w, h, BattleScreenXY.RING, e, 2)
      elseif scr.swapIndex == i then
        ring(x, y, w, h, BattleScreenXY.SWAP_RING, e, 2)
      end
      local lth = h * 0.44
      local label = tostring(item.label or item.value or "")
      text(label, x + h * 0.35, y + (h - lth) * 0.5, lth,
           BattleScreenXY.TEXT, e)
      if item.right then
        local rs = tostring(item.right)
        text(rs, x + w - h * 0.35 - textW(rs, lth * 0.95),
             y + (h - lth) * 0.5, lth * 0.95, BattleScreenXY.TEXT_DIM, e)
      end
    end
  end

  -- a thin scrollbar, only when there is something to scroll: position is
  -- information the Game Boy list gave with MORE arrows, given here as
  -- where-you-are instead
  if n > vis then
    local tx = px + pw - pad * 0.9
    local trackY = top0
    local trackH = rowsH - rgap
    rounded("fill", tx, trackY, pad * 0.35, trackH,
            BattleScreenXY.HP_TRACK, 1, 0.5)
    local frac = vis / n
    local thumbH = math.max(trackH * frac, pad)
    local thumbY = trackY + (trackH - thumbH)
                   * ((first - 1) / math.max(1, n - vis))
    -- the accent, not the panel edge: an edge-grey thumb on a panel-dark
    -- track was invisible in the very screenshot meant to show it
    rounded("fill", tx, thumbY, pad * 0.35, thumbH,
            BattleScreenXY.ACCENT, 1, 0.5)
  end

  if footer then
    text(footer, px + pw - pad - textW(footer, th),
         py + ph - pad - th, th, BattleScreenXY.TEXT_DIM)
  end
end

-- ------- the bag, in pockets
local BAG_ROWS = 7

-- the tab underline's motion: it slides from the tab it was under to the
-- tab the cursor moved to, instead of teleporting
local bagTab = { key = nil, x = nil, from = nil, at = 0 }

-- ------- the pack's own item art
--
-- The 5X pack's item sprites, cut to assets/battlexy/items/<ITEM_ID>.png.
-- The dump names by content hash, so every file was identified by EYE off a
-- contact sheet and renamed to the id it depicts -- re-cutting means
-- re-looking, not re-guessing. Machines share two discs (the pack colours
-- TMs per type and Gen 1 has no such fact to read), and an item with no
-- sprite of its own falls back to its POCKET's icon, stepped back, so the
-- row still says at a glance which family it belongs to.
local function itemIcon(id)
  id = tostring(id or "")
  local img = BattleBoxXY._art("items/" .. id)
  if img then return img end
  if id:find("^TM") then return BattleBoxXY._art("items/TM") end
  if id:find("^HM") then return BattleBoxXY._art("items/HM") end
  return nil
end

-- The pack draws each pocket's button twice, coloured and olive; ITENS has
-- only the one state and gets dimmed by the caller instead.
local function pocketIcon(key, active)
  if not active then
    local off = BattleBoxXY._art("pockets/" .. key .. "_off")
    if off then return off end
  end
  return BattleBoxXY._art("pockets/" .. key)
end

local function drawBag(game, scr, shot)
  local lx, ly = shot.lx, shot.ly
  local lw, lh = 160 * shot.scale, 144 * shot.scale
  local items = scr.items or {}
  local n = #items
  local sel = math.max(1, math.min(scr.index or 1, math.max(1, n)))
  local pop = BattleBoxXY.popScale("list", sel)
  local groups = bagGroups(game, scr)
  local cur = (n > 0) and pocketOf(game, items[sel].value) or "items"

  local pw = math.max(300, math.min(600, lw * 0.46))
  local px = lx + lw - pw - lw * 0.025
  local py = ly + lh * 0.05
  local ph = lh * 0.90
  panel(px, py, pw, ph)

  local pad = pw * 0.05
  local th = lh * 0.032

  -- the tab strip, in the pack's own pocket buttons -- coloured for the
  -- pocket the cursor is in, olive for the rest, the exact pair of states
  -- the X/Y bag draws them in. An empty pocket stays on the strip, stepped
  -- back, the way the DS bags keep their empty pockets on the wheel.
  local tabH = lh * 0.065
  local tgap = pad * 0.3
  local tw = (pw - pad * 2 - tgap * 3) / 4
  local tabY = py + pad
  local tabXs = {}
  local tpop = BattleBoxXY.popScale("bagtab", cur)
  for p, key in ipairs(POCKET_ORDER) do
    local x = px + pad + (p - 1) * (tw + tgap)
    tabXs[key] = x
    local active = (key == cur)
    local a = enterEase(p) * (#groups[key] == 0 and 0.45 or 1)
    local tx, ty, tww, thh = x, tabY, tw, tabH
    if active then
      local dw, dh = tw * (tpop - 1), tabH * (tpop - 1)
      tx, ty, tww, thh = x - dw * 0.5, tabY - dh * 0.5, tw + dw, tabH + dh
    end
    rounded("fill", tx, ty, tww, thh,
            active and BattleScreenXY.ACCENT or BattleScreenXY.CARD, a, 0.45)
    local icon = pocketIcon(key, active)
    if icon then
      local iw, ih = icon:getDimensions()
      local s = (thh * 0.82) / math.max(1, ih)
      love.graphics.setColor(1, 1, 1, a * (active and 1 or 0.8))
      love.graphics.draw(icon, tx + (tww - iw * s) * 0.5,
                         ty + (thh - ih * s) * 0.5, 0, s, s)
    else
      local lth = thh * 0.42
      local label = BattleScreenXY.POCKET_LABEL[key]
      text(label, tx + (tww - textW(label, lth)) * 0.5,
           ty + (thh - lth) * 0.5, lth,
           active and BattleScreenXY.TEXT or BattleScreenXY.TEXT_DIM, a)
    end
  end
  local lineH = math.max(3, lh * 0.006)
  if bagTab.key ~= cur then
    bagTab.from = bagTab.x or tabXs[cur]
    bagTab.at = now()
    bagTab.key = cur
  end
  local q = math.min(1, (now() - bagTab.at) / 0.18)
  q = 1 - (1 - q) * (1 - q) * (1 - q)
  local fromX = bagTab.from or tabXs[cur]
  bagTab.x = fromX + (tabXs[cur] - fromX) * q
  rounded("fill", bagTab.x, tabY + tabH + tgap, tw, lineH,
          BattleScreenXY.ACCENT, 1, 0.5)

  -- the icons carry the strip, so the active pocket's NAME goes in a
  -- header under it, with how many items it holds on the far edge
  local headTh = lh * 0.03
  local headY = tabY + tabH + tgap + lineH + pad * 0.55
  text(BattleScreenXY.POCKET_LABEL[cur], px + pad, headY, headTh,
       BattleScreenXY.TEXT)
  local countS = tostring(#groups[cur])
  text(countS, px + pw - pad - textW(countS, headTh), headY, headTh,
       BattleScreenXY.TEXT_DIM)

  local top0 = headY + headTh * 1.35 + pad * 0.4
  local footer = scr.footer and tostring(scr.footer) or nil
  local footH = footer and (th * 1.15 + pad) or pad * 0.6
  local rowsH = py + ph - footH - top0
  local rowH = (rowsH - (BAG_ROWS - 1) * pad * 0.30) / BAG_ROWS
  local rgap = pad * 0.30

  -- the current pocket's rows, re-entering whenever the pocket turns
  -- (entrance.subAt -- switchPocket stamps it)
  local seq = groups[cur]
  local m = #seq
  if m > 0 then
    local posSel = 1
    for p, i in ipairs(seq) do
      if i == sel then posSel = p break end
    end
    local vis = math.min(BAG_ROWS, m)
    local first = math.max(1, math.min(posSel - math.floor(vis / 2),
                                       m - vis + 1))
    local since = math.max(entrance.at, entrance.subAt)
    for slot = 1, vis do
      local p = first + slot - 1
      local i = seq[p]
      local item = items[i]
      if not item then break end
      local e = enterEase(slot, since)
      if e > 0 then
        local x = px + pad + (lw * BattleScreenXY.SLIDE_FRAC) * (1 - e)
        local y = top0 + (slot - 1) * (rowH + rgap)
        local w = pw - pad * 2 - (m > vis and pad * 0.8 or 0)
        local h = rowH
        local selR = (i == sel)
        if selR then
          local dw, dh = w * (pop - 1), h * (pop - 1)
          x, y, w, h = x - dw * 0.5, y - dh * 0.5, w + dw, h + dh
        end
        rounded("fill", x, y, w, h,
                selR and BattleScreenXY.ACCENT or BattleScreenXY.CARD,
                e * (selR and 1 or 0.85), 0.4)
        if selR then
          ring(x, y, w, h, BattleScreenXY.RING, e, 2)
        elseif scr.swapIndex == i then
          ring(x, y, w, h, BattleScreenXY.SWAP_RING, e, 2)
        end
        local lx2 = x + h * 0.28
        local icon = itemIcon(item.value)
        local fell = false
        if not icon then
          icon, fell = pocketIcon(cur, true), true
        end
        if icon then
          local iw, ih = icon:getDimensions()
          local s = (h * 0.74) / math.max(1, ih)
          love.graphics.setColor(1, 1, 1, e * (fell and 0.5 or 1))
          love.graphics.draw(icon, lx2, y + (h - ih * s) * 0.5, 0, s, s)
          lx2 = lx2 + iw * s + h * 0.25
        end
        local lth = h * 0.44
        local label = tostring(item.label or item.value or "")
        text(label, lx2, y + (h - lth) * 0.5, lth,
             BattleScreenXY.TEXT, e)
        if item.right then
          local rs = tostring(item.right)
          text(rs, x + w - h * 0.35 - textW(rs, lth * 0.95),
               y + (h - lth) * 0.5, lth * 0.95, BattleScreenXY.TEXT_DIM, e)
        end
      end
    end

    if m > vis then
      local tx = px + pw - pad * 0.9
      local trackH = rowsH - rgap
      rounded("fill", tx, top0, pad * 0.35, trackH,
              BattleScreenXY.HP_TRACK, 1, 0.5)
      local thumbH = math.max(trackH * (vis / m), pad)
      local thumbY = top0 + (trackH - thumbH)
                     * ((first - 1) / math.max(1, m - vis))
      rounded("fill", tx, thumbY, pad * 0.35, thumbH,
              BattleScreenXY.ACCENT, 1, 0.5)
    end
  end

  if footer then
    text(footer, px + pw - pad - textW(footer, th),
         py + ph - pad - th, th, BattleScreenXY.TEXT_DIM)
  end
end

-- ------- the draw, from snapHUDs' already-bound canvas
function BattleScreenXY.draw(game, battle, shot)
  if not (shot and shot.scale and BattleScreenXY.available()) then
    return false
  end
  local scr, kind = BattleScreenXY.of(game)
  if not scr then
    entrance.key = nil
    return false
  end
  if entrance.key ~= scr then
    entrance.key, entrance.at = scr, now()
    entrance.subAt = 0
    bagTab.key, bagTab.x, bagTab.from = nil, nil, nil
  end

  local drawer = drawList
  if kind == "party" then
    drawer = drawParty
  elseif bagInstall(scr, game) then
    drawer = drawBag
  end

  love.graphics.push("all")
  -- the veil: the arena stays visible and stays background
  setColor(BattleScreenXY.VEIL)
  love.graphics.rectangle("fill", 0, 0, shot.pw, shot.ph)
  local ok, err = pcall(drawer, game, scr, shot)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1, 1)
  if not ok then
    V.mod.log:warn("BattleScreenXY draw failed: %s", tostring(err))
    return false
  end
  return true
end

return BattleScreenXY
