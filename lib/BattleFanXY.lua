-- The move list as a hand of cards, dealt into the arena.
--
-- The flat move rows (BattleBoxXY.drawMoves) put the four moves in the
-- box's rect, on the glass, in screen space. This puts them IN THE SHOT:
-- four cards fanned in mid-air beside the player's mon, each one a plane
-- with a real position and a real tilt in world space, projected every
-- frame with the same matrix the arena was drawn with (shot.vp, snapshotted
-- by BattleScene.render). That one decision buys everything the concept
-- asked for at once -- the cards parallax with the drift, swing with the
-- attack camera, and foreshorten like objects instead of skewing like
-- decals, because they ARE objects as far as the projection is concerned.
--
-- Only the projection. The cards are still drawn by the 2D pass, over the
-- finished frame, with the UI's own translucency -- the 3D pipeline never
-- hears about them. A card is a textured strip mesh whose column positions
-- are the projected world points of its own plane: LOVE's 2D meshes
-- interpolate UVs affinely, which warps text on a perspective trapezoid,
-- and slicing the card into columns bounds that error to a sliver. The
-- face itself is rendered once into a canvas and re-rendered only when
-- what it says changes (move, PP, selection) -- per frame, the whole fan
-- is eight projected points per card and one mesh draw.
--
-- The basis the fan hangs on is SELF-CALIBRATING: right and up are built
-- from the eye and then checked against their own projection -- if "right"
-- lands leftward on screen it is flipped, likewise "up". The fan cannot be
-- mirrored by a handedness mistake in anyone's matrix conventions,
-- including this file's.
--
-- WHAT IS READ is exactly what the flat rows read: `player.curMoves`,
-- `moveIndex`, `moveSwapIndex`, `disabledSlot`, `battle.data.moves`. The
-- engine's cursor is a vertical list; lib/BattleNav remaps the dpad onto
-- this left-to-right fan (and skips `disabledSlot`) so left/right walk
-- the hand. This file still only draws wherever moveIndex points.
--
-- Degradation: no vp on the shot, a canvas that will not allocate, a mon
-- behind the camera -- draw() answers false and the caller falls back to
-- the flat rows, which are the proven path and stay in the file.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local BattleHudXY = V.require("BattleHudXY")

local BattleFanXY = {}

BattleFanXY.ENABLED = true

-- ------- the fan's geometry, in world pixels (a map cell is 16)
--
-- Anchored beside the player's mon: RIGHT_OFF along the camera's own right
-- axis, UP_OFF above the arena floor. Sized against the tele rig's lens
-- the same way the flat rows were sized against the box.
--
-- RIGHT_OFF clears the HERO: under BACK SPRITES the player's mon stands
-- up to BACK_HERO times a cell wide (OverworldBattle), its head on the
-- side the hand hangs on, and a raised card on its face reads as the menu
-- pinned to the mon rather than floating beside it. So the hand starts
-- past the grown card's right edge and reaches toward the foe -- who is
-- far and small, and reads fine through the glass.
BattleFanXY.CARD_W = 4.6          -- card width
BattleFanXY.CARD_H = 6.4          -- card height
BattleFanXY.STEP = 6.0            -- spacing between card centres
BattleFanXY.RIGHT_OFF = 20.0      -- fan centre, along camera right
BattleFanXY.UP_OFF = 5.5          -- fan centre, above the arena floor
BattleFanXY.ROLL_STEP = math.rad(3)   -- in-plane lean per slot: the hand
BattleFanXY.YAW_TILT = math.rad(5)   -- turn per slot: the foreshortening
BattleFanXY.ARC_DROP = 0.42       -- outer cards sit lower, like held cards
-- The size knob. Every laid-out centre is pulled toward the eye along its
-- own view ray, which scales the whole hand up on screen without moving it
-- -- a point slid along its own ray projects to the same pixel. Sizing by
-- CARD_W instead would also change the fan's world footprint and re-tune
-- every offset above; this one number does not.
BattleFanXY.CLOSE = 0.66
BattleFanXY.RAISE_UP = 1.4        -- the selected card lifts...
BattleFanXY.RAISE_FWD = 2.6       -- ...and steps toward the camera
BattleFanXY.RAISE_K = 18          -- per-second exponential approach
-- An unselected card RECEDES; it does not turn to glass. At 0.62 the arena
-- came through the whole face and the three cards the player is not on read as
-- green panes with writing on them (probe shot look_move_cards.png) -- the
-- concept boards have them dark and solid, and only the raised one lit. The
-- dimming that separates them now lives in drawFace's own selected/unselected
-- colours, which dim the CARD instead of thinning it.
BattleFanXY.UNSEL_ALPHA = 1
BattleFanXY.UNSEL_RECEDE = 0.90   -- unselected cards sit back from the lens
BattleFanXY.CLICK_OVER = 0.18     -- cursor-change snap: raise briefly past 1
BattleFanXY.CLICK_K = 14          -- per-second decay of the click
BattleFanXY.WOBBLE = math.rad(0.8)  -- idle selected yaw/roll
-- the snap when the cursor lands on a card: a yaw kick that rings out like
-- a struck plate (damped), so the voxel slab shows its edge turning
BattleFanXY.KICK = math.rad(26)
BattleFanXY.RIM_SCALE = 1.09      -- additive type bloom, slightly larger
BattleFanXY.RIM_ALPHA = 0.08

-- the deal: cards FLY from the player's mon, overshoot, land, staggered
BattleFanXY.DEAL_TIME = 0.22      -- seconds per card
BattleFanXY.DEAL_STAGGER = 0.07
BattleFanXY.DEAL_SPIN = math.rad(72)  -- extra yaw that returns to rest
BattleFanXY.DEAL_HOP = 2.6            -- extra lift-from-below while in flight
-- a gap in draw calls longer than this is a fresh entry to the list --
-- phase exits are invisible from here (nothing calls this outside
-- moveSelect), so re-entry is detected by the silence
BattleFanXY.REENTRY_GAP = 0.25

-- columns per card mesh: the affine-UV warp on a tilted quad is bounded by
-- slice width, and eight slices put it under a pixel at these tilts
BattleFanXY.COLS = 8

-- the face canvas, in its own pixels
BattleFanXY.FACE_W = 320
BattleFanXY.FACE_H = 440

-- the PP meter's colours by state (see drawFace)
BattleFanXY.PP_COLOR = {
  full = { 0.38, 0.86, 0.42 },
  mid = { 0.96, 0.80, 0.25 },
  low = { 0.96, 0.32, 0.28 },
  empty = { 0.96, 0.32, 0.28 },
  disabled = { 0.55, 0.55, 0.60 },
}

local SWAP_RING = { 1.0, 0.84, 0.40, 0.95 }
local GOLD = { 1.0, 0.84, 0.40 }

-- ease-out-back: overshoots 1 (~10%) then lands. The deal's punch.
local function easeOutBack(t)
  if t <= 0 then return 0 end
  if t >= 1 then return 1 end
  local c1, c3 = 1.70158, 2.70158
  local x = t - 1
  return 1 + c3 * x * x * x + c1 * x * x
end

-- lazy: BattleBoxXY loads this module from inside drawMoves, so by the
-- time anything here runs the box is fully loaded -- but a top-level
-- require would make the two files' load order matter, and it should not
local Box = nil
local function box()
  if Box == nil then
    local ok, B = pcall(V.require, "BattleBoxXY")
    Box = (ok and B) or false
  end
  return Box or nil
end

local GlassFX = nil
local function glassFX()
  if GlassFX == nil then
    local ok, F = pcall(V.require, "BattleGlassFX")
    GlassFX = (ok and F) or false
  end
  return GlassFX or nil
end

-- the voxel dressing: frame, crown, the type's matter, the throw
-- (lib/BattleCardVoxel.lua)
local Voxel = nil
local function voxel()
  if Voxel == nil then
    local ok, X = pcall(V.require, "BattleCardVoxel")
    Voxel = (ok and X) or false
  end
  return (Voxel and Voxel.ENABLED) and Voxel or nil
end

-- the B2W2 kit, for its name font (see BattleCapsule.text): the cards
-- speak the same Unova as the capsules and the dialog box
local Cap = nil
local function capsule()
  if Cap == nil then
    local ok, C = pcall(V.require, "BattleCapsule")
    Cap = (ok and C) or false
  end
  return (Cap and Cap.available and Cap.available()) and Cap or nil
end

-- ------- state
--
-- Raises are stored, not derived from the clock: the selected card's lift
-- chases a target the way the attack camera chases its goal, so a cursor
-- sprinting down the list drags the lift smoothly through the slots
-- instead of teleporting it.
local S = {
  slots = {},       -- [i] = { canvas, mesh, key, raise, click }
  dealAt = 0,
  lastDraw = 0,
  lastSel = nil,    -- cursor-change snap
  last = nil,       -- what a probe measures
}

function BattleFanXY.debug()
  return S.last
end

-- ------- vectors
local function vadd(a, b, k)
  k = k or 1
  return { a[1] + b[1] * k, a[2] + b[2] * k, a[3] + b[3] * k }
end

local function vnorm(v)
  local d = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
  if d < 1e-6 then return { 0, 0, 0 } end
  return { v[1] / d, v[2] / d, v[3] / d }
end

local function vcross(a, b)
  return { a[2] * b[3] - a[3] * b[2],
           a[3] * b[1] - a[1] * b[3],
           a[1] * b[2] - a[2] * b[1] }
end

-- Rodrigues: v rotated about the unit axis a
local function vrot(v, a, ang)
  local c, s = math.cos(ang), math.sin(ang)
  local dot = v[1] * a[1] + v[2] * a[2] + v[3] * a[3]
  local cr = vcross(a, v)
  return { v[1] * c + cr[1] * s + a[1] * dot * (1 - c),
           v[2] * c + cr[2] * s + a[2] * dot * (1 - c),
           v[3] * c + cr[3] * s + a[3] * dot * (1 - c) }
end

-- World to WINDOW pixels under the shot's matrix -- the same rows
-- BattleScene.toGB reads, without the letterbox division: the fan draws on
-- the world canvas, which IS the window.
local function project(vp, pw, ph, p)
  local x, y, z = p[1], p[2], p[3]
  local cx = vp[1] * x + vp[2] * y + vp[3] * z + vp[4]
  local cy = vp[5] * x + vp[6] * y + vp[7] * z + vp[8]
  local cw = vp[13] * x + vp[14] * y + vp[15] * z + vp[16]
  if cw <= 1e-6 then return nil end
  return (cx / cw * 0.5 + 0.5) * pw, (cy / cw * 0.5 + 0.5) * ph
end

-- ------- the face
--
-- Rendered into the slot's canvas only when this key changes: the move, its
-- PP, and how the card is dressed (selected, swap-marked, disabled).
local function faceKey(mv, def, sel, swap, disabled, tname)
  local okL, Lang = pcall(V.require, "Lang")
  return table.concat({ tostring(mv and mv.id), tostring(mv and mv.pp),
                        sel and "S" or "-", swap and "W" or "-",
                        disabled and "D" or "-", tostring(tname),
                        okL and Lang and Lang.get and Lang.get() or "en" }, ":")
end

-- ------- what a card says about a move, beyond its name
--
-- Generation 1 ships no prose for moves -- there is no description field in
-- the data at all (Generation 2 has one, and it is used when it is there). So
-- rather than author flavour text and let it read as the game's own voice,
-- the line under the badge is the one fact the record DOES carry beyond the
-- cells below it: whether the blow works off Attack or Special. (How often it
-- lands has its own cell, ACCURACY, beside POWER.)
local function moveLine(B, def)
  if not def then return nil end
  if type(def.description) == "string" and #def.description > 0 then
    return def.description
  end
  local cat = def.category
  if not cat or cat == "" then
    local okT, TypeChart = pcall(require, "src.battle.TypeChart")
    if okT and TypeChart and TypeChart.category then
      local okC, c = pcall(TypeChart.category, def.type)
      if okC then cat = c end
    end
  end
  return (cat and cat ~= "" and tostring(cat):upper()) or nil
end

-- The face, drawn to the battle concepts: a cream card inside a dark pixel
-- rim with stepped corners and a keyline, the type on a coloured tab with
-- its pixel icon, the move's name set large and heavy, its category over a
-- rule, POWER and ACCURACY as big figures, and the PP meter in the TYPE's
-- colours. An empty or disabled move is the same card drained of colour.
-- Colours, icon and words come from lib/BattleCardVoxel.lua (palette,
-- icon, the LANGUAGE row's pick).
local function drawFace(slot, mv, def, sel, swap, disabled)
  local B = box(); if not B then return false end
  local VX = voxel()
  local g = love.graphics
  local W, H = BattleFanXY.FACE_W, BattleFanXY.FACE_H
  if not slot.canvas then
    local ok, c = pcall(g.newCanvas, W, H, { dpiscale = 1 })
    if not (ok and c) then return false end
    slot.canvas = c
    c:setFilter("nearest", "nearest")
  end
  local tname = def and B.typeName(def.type)
  local pal = VX and VX.palette(tname) or {
    tab = { 0.90, 0.88, 0.80 }, ink = BattleHudXY.INK,
    bar = { { 0.30, 0.70, 0.35 }, { 0.45, 0.88, 0.45 } } }
  local pick = VX and VX.pick or function(en) return en end
  local pp, maxPP = B.ppOf(mv, def)
  local empty = disabled or (pp ~= nil and pp <= 0)
  -- the drained card: every colour taken to its own grey
  local function tone(c, a)
    if not empty then return { c[1], c[2], c[3], a or c[4] or 1 } end
    local l = c[1] * 0.30 + c[2] * 0.59 + c[3] * 0.11
    l = 0.18 + l * 0.72
    return { l, l, l, a or c[4] or 1 }
  end
  local INK = tone({ 0.11, 0.10, 0.10 })
  local MUTED = tone({ 0.42, 0.39, 0.35 })
  local CREAM = tone({ 0.98, 0.96, 0.90 })
  local EDGE = { 0.09, 0.08, 0.08, 1 }
  local LINE = tone({ 0.78, 0.74, 0.66 })
  local danger = { 0.65, 0.18, 0.17, 1 }
  local prevCanvas = g.getCanvas()
  local prevBlend, prevAlpha = g.getBlendMode()
  local ok, err = pcall(function()
    g.setCanvas(slot.canvas)
    g.clear(0, 0, 0, 0)
    g.setBlendMode("alpha")
    -- a rectangle with its corners cut in two pixel steps
    local function notched(x, y, w, h, st, c)
      g.setColor(c[1], c[2], c[3], c[4] or 1)
      g.rectangle("fill", x + 2 * st, y, w - 4 * st, h)
      g.rectangle("fill", x + st, y + st, w - 2 * st, h - 2 * st)
      g.rectangle("fill", x, y + 2 * st, w, h - 4 * st)
    end
    local function text(value, x, y, size, width, color, heavy)
      value = tostring(value)
      size = math.min(size, width * 84 / math.max(1, BattleHudXY.textWidth(value)))
      if heavy then
        -- a heavier stroke out of the one face there is: set twice, a
        -- hair apart
        BattleHudXY.text(value, x + size * 0.05, y, size, color)
        BattleHudXY.text(value, x + size * 0.025, y + size * 0.02, size, color)
      end
      BattleHudXY.text(value, x, y, size, color)
      return size
    end
    -- the plate: dark rim, keyline, face
    notched(2, 2, W - 4, H - 4, 6, EDGE)
    notched(9, 9, W - 18, H - 18, 5, CREAM)
    notched(15, 15, W - 30, H - 30, 4, LINE)
    notched(17, 17, W - 34, H - 34, 4, CREAM)
    -- the tab: the type's colour, its word, its icon
    notched(28, 28, W - 56, 54, 4, tone(pal.tab))
    g.setColor(0, 0, 0, 0.10)
    g.rectangle("fill", 36, 78, W - 72, 4)
    local iconW = 0
    if VX then iconW = VX.icon(tname, W - 38, 33, 44) end
    text(VX and VX.typeLabel(tname) or (tname or "MOVE"), 42, 38, 32,
         W - 100 - iconW, tone(pal.ink))
    if swap then
      g.setColor(unpack(SWAP_RING))
      g.rectangle("fill", 17, 100, 6, H - 150)
    end
    -- the name, large and heavy; long names wrap at a space
    local name = (def and def.name) or tostring(mv and mv.id or "?")
    local title, tail = name, nil
    if BattleHudXY.textWidth(name) * 40 / 84 > W - 64 then
      local left, right = name:match("^(.*)%s+(%S+)$")
      if left then title, tail = left, right end
    end
    local nameY = tail and 94 or 110
    text(title, 32, nameY, 40, W - 64, INK, true)
    if tail then text(tail, 32, nameY + 42, 40, W - 64, INK, true) end
    -- WATER's face carries a wave behind its words (the Jato Corrente
    -- concept): pixel steps in pale blue, a crest line over them
    if tname == "WATER" and not empty then
      for x = 40, W - 34, 4 do
        local y = 176 + math.floor(math.sin(x * 0.045) * 9 + 0.5)
        g.setColor(0.80, 0.92, 0.99, 0.85)
        g.rectangle("fill", x, y, 4, 14)
        g.setColor(0.55, 0.80, 0.96, 0.9)
        g.rectangle("fill", x, y, 4, 3)
      end
    end
    -- the category, over a rule
    local line = moveLine(B, def) or ""
    if line == "PHYSICAL" then line = pick("PHYSICAL", "FÍSICO")
    elseif line == "SPECIAL" then line = pick("SPECIAL", "ESPECIAL") end
    text(line, 32, 186, 23, W - 64, MUTED)
    g.setColor(LINE[1], LINE[2], LINE[3], 1)
    g.rectangle("fill", 30, 220, W - 60, 3)
    -- the two figures
    text(pick("POWER", "PODER"), 32, 236, 20, 120, MUTED)
    text(def and def.power and def.power > 1 and def.power
      or (def and def.power == 1 and "VAR") or "--", 32, 258, 54, 120, INK, true)
    local acc = def and tonumber(def.accuracy)
    text(pick("ACCURACY", "ACURÁCIA"), 172, 236, 20, 120, MUTED)
    text(acc and ("%d%%"):format(acc) or "--", 172, 258, 54, 124, INK, true)
    -- the PP meter, in the type's own colours
    local ratio = pp and maxPP and maxPP > 0 and math.max(0, math.min(1, pp / maxPP)) or 0
    local state = disabled and "disabled" or (not pp and "none")
      or (pp <= 0 and "empty") or (ratio < 0.30 and "low")
      or (ratio < 0.60 and "mid") or "full"
    slot.ppState = state
    text("PP", 32, 330, 23, 60, MUTED)
    local count = pp and ("%d / %d"):format(pp, maxPP or pp) or "--"
    local cw = BattleHudXY.textWidth(count) * 27 / 84
    text(count, W - 32 - cw, 326, 27, W - 96, INK)
    local bx, by, bw, bh = 30, 360, W - 60, 26
    g.setColor(EDGE[1], EDGE[2], EDGE[3], 1)
    g.rectangle("fill", bx, by, bw, bh)
    local trough = tone({ 0.26, 0.24, 0.23 })
    g.setColor(trough[1], trough[2], trough[3], 1)
    g.rectangle("fill", bx + 4, by + 4, bw - 8, bh - 8)
    local fillW = math.floor((bw - 8) * ratio + 0.5)
    local stops = pal.bar
    local slices = 24
    for k = 0, slices - 1 do
      local x0 = math.floor((bw - 8) * k / slices)
      local x1 = math.floor((bw - 8) * (k + 1) / slices)
      if x0 < fillW then
        x1 = math.min(x1, fillW)
        -- the gradient runs along the WHOLE bar, so a draining meter keeps
        -- its cold end and loses its hot one, like the concept's fire bar
        local f = (k + 0.5) / slices * (#stops - 1)
        local i = math.min(#stops - 1, math.floor(f))
        local t = f - i
        local a, b = stops[i + 1], stops[math.min(#stops, i + 2)]
        local c = tone({ a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t,
                         a[3] + (b[3] - a[3]) * t })
        g.setColor(c[1], c[2], c[3], 1)
        g.rectangle("fill", bx + 4 + x0, by + 4, x1 - x0, bh - 8)
        g.setColor(1, 1, 1, 0.28)
        g.rectangle("fill", bx + 4 + x0, by + 4, x1 - x0, 4)
      end
    end
    -- the status line
    local status = disabled and pick("DISABLED", "BLOQUEADO")
      or (pp and pp <= 0 and pick("NO PP", "SEM PP"))
      or (swap and pick("SWAP", "TROCAR")) or (sel and pick("SELECTED", "SELECIONADO")) or ""
    text(status, 32, 398, 20, W - 64,
      (disabled or (pp and pp <= 0)) and danger or MUTED)
    -- pixel flecks of the type in two corners, as the concept's fire card
    if not empty and VX then
      local fl = pal.glow or pal.ink
      g.setColor(fl[1], fl[2], fl[3], 0.9)
      g.rectangle("fill", W - 44, H - 40, 6, 6)
      g.rectangle("fill", W - 34, H - 50, 4, 4)
      g.rectangle("fill", W - 54, H - 32, 4, 4)
      g.rectangle("fill", 24, 92, 4, 4)
      g.rectangle("fill", 30, 100, 3, 3)
    end
    -- and the drained card is veiled, icon and all
    if empty then notched(9, 9, W - 18, H - 18, 5, { 0.62, 0.62, 0.62, 0.30 }) end
  end)
  if prevCanvas then g.setCanvas(prevCanvas) else g.setCanvas() end
  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  g.setColor(1, 1, 1, 1)
  if not ok then error(err, 0) end
  return true
end

-- Compose the existing animation locally, then restore the reading bands.
-- One reusable canvas per card; text stays cached and pixel-identical.
local function animateFace(slot, id, tname, strength, disabled)
  local CardFX = V.require("BattleCardFX")
  if disabled or not CardFX.ENABLED or not CardFX.TYPES[tname] then return slot.canvas end
  local g = love.graphics
  local W, H = BattleFanXY.FACE_W, BattleFanXY.FACE_H
  if not slot.animated then
    slot.animated = g.newCanvas(W, H, { dpiscale = 1 })
    slot.animated:setFilter("nearest", "nearest")
    slot.reading = {}
    for _, r in ipairs({ {28,30,W-56,173}, {28,228,W-56,77}, {28,315,W-56,94} }) do
      slot.reading[#slot.reading + 1] = { g.newQuad(r[1],r[2],r[3],r[4],W,H), r[1],r[2] }
    end
  end
  local previous = g.getCanvas()
  local blend, alpha = g.getBlendMode()
  local sx, sy, sw, sh = g.getScissor()
  local ok, err = pcall(function()
    g.setCanvas(slot.animated)
    g.setScissor()
    g.clear(0,0,0,0)
    g.setColor(1,1,1,1)
    g.setBlendMode("alpha", "premultiplied")
    g.draw(slot.canvas)
    g.setScissor(20,20,W-40,H-40)
    g.setBlendMode("alpha", "alphamultiply")
    CardFX.drawModern(id, function(x,y) return x+20,y+20 end, W-40,H-40,tname,strength)
    g.setScissor()
    g.setColor(1,1,1,1)
    g.setBlendMode("replace", "premultiplied")
    for _, r in ipairs(slot.reading) do g.draw(slot.canvas,r[1],r[2],r[3]) end
  end)
  g.setCanvas(previous)
  if sx then g.setScissor(sx,sy,sw,sh) else g.setScissor() end
  g.setBlendMode(blend,alpha)
  g.setColor(1,1,1,1)
  if not ok then error(err,0) end
  return slot.animated
end

-- ------- one panel's mesh, projected
--
-- Generalised over its size: the fan's cards use it, and so do the menu's
-- floating panels (BattlePanelsXY) through the `hang` export below.
local function cardMesh(slot, vp, pw, ph, center, cr, cu, hw, hh)
  local g = love.graphics
  local n = BattleFanXY.COLS
  if not slot.mesh then
    local ok, m = pcall(g.newMesh, (n + 1) * 2, "strip", "stream")
    if not (ok and m) then return nil end
    slot.mesh = m
  end
  local verts = {}
  for j = 0, n do
    local u = j / n
    local wx = (u * 2 - 1) * hw
    local col = vadd(center, cr, wx)
    local tx, ty = project(vp, pw, ph, vadd(col, cu, hh))
    local bx, by = project(vp, pw, ph, vadd(col, cu, -hh))
    if not (tx and bx) then return nil end
    verts[#verts + 1] = { tx, ty, u, 0 }
    verts[#verts + 1] = { bx, by, u, 1 }
  end
  slot.mesh:setVertices(verts)
  slot.mesh:setTexture(slot.canvas)
  return slot.mesh
end

-- ------- the camera frame everything hangs from
--
-- Built from the shot, self-calibrated (see the header), and shared: the
-- fan below and the menu's floating panels (BattlePanelsXY) both hang
-- their geometry on this same answer, so they agree about where "beside
-- the mon" is to the pixel.
function BattleFanXY.rig(shot)
  if not (shot and shot.vp and shot.eye and shot.playerCell
          and shot.pw and shot.ph) then
    return nil
  end
  local base = { shot.playerCell[1], shot.groundY or 0, shot.playerCell[2] }
  local dir = vnorm(vadd(base, shot.eye, -1))     -- eye toward the mon
  local right = vnorm(vcross(dir, { 0, 1, 0 }))
  if right[1] == 0 and right[2] == 0 and right[3] == 0 then return nil end
  local up = vnorm(vcross(right, dir))
  local function proj(p)
    return project(shot.vp, shot.pw, shot.ph, p)
  end
  local ax, ay = proj(base)
  if not ax then return nil end
  local rx = proj(vadd(base, right, 2))
  if not rx then return nil end
  if rx < ax then right = { -right[1], -right[2], -right[3] } end
  local _, uy = proj(vadd(base, up, 2))
  if not uy then return nil end
  if uy > ay then up = { -up[1], -up[2], -up[3] } end
  return { base = base, dir = dir, right = right, up = up, project = proj }
end

-- One world panel, projected and handed back as a drawable mesh -- the
-- shared half of "hang a canvas in the arena". The caller owns the slot
-- (its canvas and mesh live there), the placement and the draw.
function BattleFanXY.hang(slot, shot, center, cr, cu, w, h)
  return cardMesh(slot, shot.vp, shot.pw, shot.ph, center, cr, cu,
                  w * 0.5, h * 0.5)
end

-- and the vector kit, so a sibling module lays panels out in the same
-- arithmetic instead of a copy of it
BattleFanXY.vadd = vadd
BattleFanXY.vrot = vrot

-- A pane's own pixel space mapped to the screen, plus the scale (screen
-- px per pane px): effects drawn through this lean, slide and swing with
-- the glass they are falling on (see BattleGlassFX).
function BattleFanXY.paneMapper(shot, center, cr, cu, w, h,
                                faceW, faceH, pane)
  pane = pane or { 0, 0, faceW, faceH }
  local function map(lx, ly)
    local u = (pane[1] + lx) / faceW
    local v = (pane[2] + ly) / faceH
    local p = vadd(vadd(center, cr, (u * 2 - 1) * w * 0.5),
                   cu, (1 - 2 * v) * h * 0.5)
    return project(shot.vp, shot.pw, shot.ph, p)
  end
  local ax, ay = map(0, 0)
  local bx, by = map(pane[3], 0)
  local ss = 0.3
  if ax and bx then
    ss = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2) / math.max(1, pane[3])
  end
  return map, ss
end

-- ------- the frost, shared by every pane of glass in the costume
--
-- Real glass: the pane's screen footprint is cropped out of the CANVAS
-- BEING DRAWN, shrunk hard into a side buffer and stretched back through
-- a mesh whose UVs are each vertex's own screen position -- what shows on
-- the pane is exactly what stands behind it, blurred by the round trip.
-- It cannot sample in place (a canvas will not draw onto itself), hence
-- the buffer. The mesh follows the pane's ROUNDED outline -- a triangle
-- fan around the corner arcs -- because a rectangular frost pokes square
-- blurry ears past a capsule's round ends.
BattleFanXY.FROST_W = 160
BattleFanXY.FROST_H = 96
local FROST_ARC = 5   -- segments per corner arc

local function roundedPerimeter(pane, radius)
  local x, y, w, h = pane[1], pane[2], pane[3], pane[4]
  local r = math.min(radius or 0, w / 2, h / 2)
  local pts = {}
  local function arc(cx, cy, a0, a1)
    for i = 0, FROST_ARC do
      local a = a0 + (a1 - a0) * i / FROST_ARC
      pts[#pts + 1] = { cx + math.cos(a) * r, cy + math.sin(a) * r }
    end
  end
  -- face pixels, y down; four arcs bulging outward, clockwise
  arc(x + r, y + r, math.pi, math.pi * 1.5)
  arc(x + w - r, y + r, math.pi * 1.5, math.pi * 2)
  arc(x + w - r, y + h - r, 0, math.pi * 0.5)
  arc(x + r, y + h - r, math.pi * 0.5, math.pi)
  return pts
end

-- `pane` is the visible panel's rect in FACE pixels (faces keep
-- transparent headroom around what they actually show), `radius` its
-- corner radius there; the quad spanned by cr/cu is w x h in the world.
function BattleFanXY.frost(slot, shot, center, cr, cu, w, h,
                           faceW, faceH, pane, radius, alpha)
  local g = love.graphics
  local prev = g.getCanvas()
  if not prev then return end
  local perim = roundedPerimeter(pane or { 0, 0, faceW, faceH }, radius)
  local pts = {}
  local minx, miny = math.huge, math.huge
  local maxx, maxy = -math.huge, -math.huge
  for _, fp in ipairs(perim) do
    local u = fp[1] / faceW
    local v = fp[2] / faceH
    local p = vadd(vadd(center, cr, (u * 2 - 1) * w * 0.5),
                   cu, (1 - 2 * v) * h * 0.5)
    local sx, sy = project(shot.vp, shot.pw, shot.ph, p)
    if not sx then return end
    pts[#pts + 1] = { sx, sy }
    if sx < minx then minx = sx end
    if sx > maxx then maxx = sx end
    if sy < miny then miny = sy end
    if sy > maxy then maxy = sy end
  end
  local cw, ch = prev:getWidth(), prev:getHeight()
  local bx = math.max(0, math.floor(minx) - 4)
  local by = math.max(0, math.floor(miny) - 4)
  local bw = math.min(cw, math.ceil(maxx) + 4) - bx
  local bh = math.min(ch, math.ceil(maxy) + 4) - by
  if bw < 8 or bh < 8 then return end
  if not slot.frost then
    local ok, cv = pcall(g.newCanvas, BattleFanXY.FROST_W,
                         BattleFanXY.FROST_H, { dpiscale = 1 })
    if not (ok and cv) then return end
    pcall(cv.setFilter, cv, "linear", "linear")
    slot.frost = cv
  end
  local vcount = #pts + 2
  if not slot.fmesh or slot.fmeshN ~= vcount then
    local ok, m = pcall(g.newMesh, vcount, "fan", "stream")
    if not (ok and m) then return end
    slot.fmesh = m
    slot.fmeshN = vcount
  end
  local q = g.newQuad(bx, by, bw, bh, cw, ch)
  g.setCanvas(slot.frost)
  g.clear(0, 0, 0, 0)
  g.setColor(1, 1, 1, 1)
  g.draw(prev, q, 0, 0, 0, BattleFanXY.FROST_W / bw,
         BattleFanXY.FROST_H / bh)
  g.setCanvas(prev)
  -- centre first (a fan over a convex outline), perimeter, closed
  local ccx = (minx + maxx) * 0.5
  local ccy = (miny + maxy) * 0.5
  local verts = { { ccx, ccy, (ccx - bx) / bw, (ccy - by) / bh } }
  for _, p in ipairs(pts) do
    verts[#verts + 1] = { p[1], p[2], (p[1] - bx) / bw, (p[2] - by) / bh }
  end
  verts[#verts + 1] = { pts[1][1], pts[1][2],
                        (pts[1][1] - bx) / bw, (pts[1][2] - by) / bh }
  slot.fmesh:setVertices(verts)
  slot.fmesh:setTexture(slot.frost)
  g.setColor(1, 1, 1, (alpha or 1) * 0.95)
  g.draw(slot.fmesh)
  g.setColor(1, 1, 1, 1)
end

-- ------- the draw
--
-- Answers false for ANY reason it cannot put the whole hand up, and the
-- caller's flat rows take the frame. Half a hand is worse than none.
function BattleFanXY.draw(battle, shot)
  if not BattleFanXY.ENABLED then return false end
  if not battle then return false end
  local moves = (battle.player and battle.player.curMoves) or {}
  local nMoves = #moves
  if nMoves == 0 then return false end
  local data = (battle.data and battle.data.moves) or {}
  local sel = math.max(1, math.min(tonumber(battle.moveIndex) or 1, nMoves))

  local now = (love.timer and love.timer.getTime and love.timer.getTime())
              or 0
  local dt = now - S.lastDraw
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
  if now - S.lastDraw > BattleFanXY.REENTRY_GAP then
    S.dealAt = now
    S.lastSel = nil
    for _, slot in pairs(S.slots) do
      slot.raise = 0
      slot.click = 0
    end
  end
  S.lastDraw = now

  -- cursor-change snap: the NEW card overshoots raise then eases back
  if sel ~= S.lastSel then
    local ns = S.slots[sel]
    if not ns then ns = { raise = 0, click = 0 }; S.slots[sel] = ns end
    ns.click = 1
    ns.kickAt = now
    S.lastSel = sel
  end

  -- ------- the basis, from the shot's own camera (shared: see rig above)
  local R = BattleFanXY.rig(shot)
  if not R then return false end
  local dir, right, up = R.dir, R.right, R.up
  local VX = voxel()
  if VX then pcall(VX.fanBegin, shot, now) end
  local anchor = vadd(vadd(R.base, up, BattleFanXY.UP_OFF),
                      right, BattleFanXY.RIGHT_OFF)
  -- the deal flies FROM the player's mon: anchor minus STEP, minus UP
  local origin = vadd(vadd(anchor, right, -BattleFanXY.STEP),
                      up, -BattleFanXY.UP_OFF)

  -- ------- lay the hand out
  local g = love.graphics
  local B = box()
  local centre = (nMoves + 1) * 0.5
  local approach = 1 - math.exp(-BattleFanXY.RAISE_K * dt)
  local clickDecay = math.exp(-BattleFanXY.CLICK_K * dt)
  local order = {}
  for i = 1, nMoves do if i ~= sel then order[#order + 1] = i end end
  order[#order + 1] = sel        -- the selected card draws last, on top

  local dbg = { n = 0, sel = sel, cx = {}, cy = {}, raise = {},
                wx = {}, wy = {}, wz = {}, x0 = {}, x1 = {} }
  local drew = 0
  for _, i in ipairs(order) do
    local slot = S.slots[i]
    if not slot then slot = { raise = 0, click = 0 }; S.slots[i] = slot end
    slot.raise = slot.raise
                 + ((i == sel and 1 or 0) - slot.raise) * approach
    slot.click = (slot.click or 0) * clickDecay
    if slot.click < 0.01 then slot.click = 0 end
    -- visual raise can exceed 1 on the click; debug still reports the 0..1 chase
    local visRaise = slot.raise + (i == sel and slot.click * BattleFanXY.CLICK_OVER or 0)

    local mv = moves[i]
    local def = data[mv.id]
    local swap = battle.moveSwapIndex and battle.moveSwapIndex == i
                 and battle.moveSwapIndex ~= sel
    local disabled = battle.player.disabledSlot == i
    local key = faceKey(mv, def, i == sel, swap or false, disabled,
                        def and B and B.typeName(def.type))
    if slot.key ~= key then
      local okF = pcall(drawFace, slot, mv, def, i == sel, swap, disabled)
      if not (okF and slot.canvas) then return false end
      slot.key = key
    end

    -- the deal: this card's spread fraction. Until p>0 the card is invisible.
    local p = (now - S.dealAt - (i - 1) * BattleFanXY.DEAL_STAGGER)
              / BattleFanXY.DEAL_TIME
    p = math.max(0, math.min(1, p))
    local ease = easeOutBack(p)
    -- rest pose is the SETTLED hand; the deal lerps from the mon with overshoot
    local te = (i - centre)
    local lift = -BattleFanXY.ARC_DROP * te * te
                 + BattleFanXY.RAISE_UP * visRaise
    local rest = vadd(anchor, right, te * BattleFanXY.STEP)
    rest = vadd(rest, up, lift)
    -- selected steps toward the camera; unselected recede
    rest = vadd(rest, dir, -BattleFanXY.RAISE_FWD * visRaise
                            + BattleFanXY.UNSEL_RECEDE * (1 - slot.raise))
    local center
    if p <= 0 then
      center = { origin[1], origin[2], origin[3] }
    else
      center = {
        origin[1] + (rest[1] - origin[1]) * ease,
        origin[2] + (rest[2] - origin[2]) * ease,
        origin[3] + (rest[3] - origin[3]) * ease,
      }
      -- extra lift-from-below and a spin that returns to rest while in flight
      if p < 1 then
        local hop = math.sin(p * math.pi)
        center = vadd(center, up, hop * BattleFanXY.DEAL_HOP)
      end
    end
    -- the glass physics: the bob, and the shove when a hit's wave passes
    local FX = glassFX()
    local jT = 0
    if FX then
      local okJ, jR, jU, tilt = pcall(FX.jolt, "card" .. i, center, R)
      if okJ and jR then
        center = vadd(vadd(center, right, jR), up, jU)
        jT = tilt or 0
      end
    end
    -- the card turns with the shove, about its up
    local cr = vrot(right, up, te * BattleFanXY.YAW_TILT + jT)
    cr = vrot(cr, dir, te * BattleFanXY.ROLL_STEP)
    local cu = vrot(up, dir, te * BattleFanXY.ROLL_STEP)
    -- its footprint on the floor, for the contact shadow (arena pass)
    if FX and FX.footprint and p > 0 then
      pcall(FX.footprint, "card" .. i, center, cr, cu,
            BattleFanXY.CARD_W, BattleFanXY.CARD_H, shot.groundY)
    end
    -- the size knob: slide toward the eye along this card's own ray
    center = vadd(shot.eye, vadd(center, shot.eye, -1), BattleFanXY.CLOSE)
    if p > 0 and p < 1 then
      local spin = math.sin(p * math.pi) * BattleFanXY.DEAL_SPIN
      cr = vrot(cr, up, spin)
    end
    -- idle selected: a small yaw/roll wobble
    if i == sel and p >= 1 then
      local wob = BattleFanXY.WOBBLE
      local wt = now * 2.35
      cr = vrot(cr, up, math.sin(wt) * wob)
      local roll = math.cos(wt * 1.27) * wob
      cr = vrot(cr, dir, roll)
      cu = vrot(cu, dir, roll)
    end
    if i == sel and slot.kickAt then
      local kt = now - slot.kickAt
      if kt < 0.9 then
        cr = vrot(cr, up, BattleFanXY.KICK * math.exp(-kt * 7) * math.sin(kt * 26))
      end
    end

    local alpha = (i == sel) and 1 or BattleFanXY.UNSEL_ALPHA
    local aDeal = (p <= 0) and 0 or 1
    if p <= 0 then
      -- invisible until the deal starts; faces are ready, the slot still counts
      dbg.raise[i] = slot.raise
      drew = drew + 1
    else
      local mesh = cardMesh(slot, shot.vp, shot.pw, shot.ph, center, cr, cu,
                            BattleFanXY.CARD_W * 0.5, BattleFanXY.CARD_H * 0.5)
      if not mesh then return false end
      local tname = def and B and B.typeName(def.type)
      local strength = 0.30 + 0.55 * math.max(0, math.min(1, slot.raise or 0))
      -- with the voxel dressing the element lives AROUND the card and the
      -- face stays clean to read, as the concepts have it
      local tex = VX and slot.canvas
                  or animateFace(slot, "card" .. i, tname, strength, disabled)
      if VX then
        -- the slab goes down first: the face is laid on top of it
        local pp = B and B.ppOf and B.ppOf(mv, def)
        pcall(VX.card, i, i == sel, tname, center, cr, cu, p, visRaise,
              disabled or (pp ~= nil and pp <= 0), tex, now)
      end
      mesh:setTexture(tex)
      g.setColor(1, 1, 1, alpha * aDeal)
      g.draw(mesh)

      local sx, sy = project(shot.vp, shot.pw, shot.ph, center)
      dbg.cx[i], dbg.cy[i], dbg.raise[i] = sx, sy, slot.raise
      dbg.wx[i], dbg.wy[i], dbg.wz[i] = center[1], center[2], center[3]
      -- the card's own left and right edges on screen, for the probe that
      -- checks the hand clears the hero
      local hw = BattleFanXY.CARD_W * 0.5
      dbg.x0[i] = project(shot.vp, shot.pw, shot.ph, vadd(center, cr, -hw))
      dbg.x1[i] = project(shot.vp, shot.pw, shot.ph, vadd(center, cr, hw))
      drew = drew + 1
    end
  end
  if VX then pcall(VX.fanEnd, shot, now) end
  g.setColor(1, 1, 1, 1)
  dbg.n = drew
  S.last = dbg
  return drew == nMoves
end

-- what each card's face last showed for its PP -- for the probe
function BattleFanXY.faceDebug()
  local out = {}
  for i, slot in pairs(S.slots) do
    if type(i) == "number" then out[i] = slot.ppState end
  end
  return out
end

return BattleFanXY
