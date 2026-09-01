-- The menu, hung in the arena: the message panel and the four command
-- buttons as floating glass chips.
--
-- Same trade the move fan made (BattleFanXY), extended to the rest of the
-- battle costume: instead of panels lying ON the frame, panels standing IN
-- the shot -- world positions beside the player's mon, projected every
-- frame with the camera the scene was drawn with. The payoff is the
-- parallax: the chips slide against the arena under the drift, and when
-- the attack camera swings for a move the message panel leans with the
-- world it is standing in. A screen-space panel cannot do that last thing
-- at any price, and it is the thing that makes the UI read as part of the
-- scene rather than as glass in front of it.
--
-- The layout is the X/Y cluster's own: FIGHT alone on top, the three
-- others in a row under it, the message panel on the left. Selection is
-- still the engine's `menuIndex`; the pop and the breath are still
-- BattleBoxXY.popScale on the same clock -- applied here as a WORLD-size
-- multiplier, so the selected chip swells in the arena instead of on the
-- glass. One look, two coordinate systems, one selection feel.
--
-- Faces are canvases re-rendered only when what they show changes (the
-- typed message grows a character, the cursor moves); per frame the whole
-- menu is a handful of projected points and five mesh draws. Everything
-- geometric is borrowed from the fan -- rig, hang, vectors -- so the two
-- modules cannot disagree about where "beside the mon" is.
--
-- Degradation, as everywhere in this costume: any refusal answers false
-- and BattleBoxXY's flat panels take the frame.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local BattleHudXY = V.require("BattleHudXY")
local Fan = V.require("BattleFanXY")

local BattlePanelsXY = {}

BattlePanelsXY.ENABLED = true

-- ------- layout, in world pixels around the player's mon (cell = 16)
--
-- The message hangs low over the mon's own ground, turned a few degrees so
-- its far edge falls away -- a card lying toward the camera. The cluster
-- floats to the right where the flat buttons sat, turned the OTHER way, so
-- the two sides of the menu lean toward each other around the mon.
BattlePanelsXY.MSG_W = 13.0          -- panel width; height follows the face
BattlePanelsXY.MSG_RIGHT = -6.5      -- left of the mon, over open floor
BattlePanelsXY.MSG_UP = 2.2
BattlePanelsXY.MSG_YAW = math.rad(14)
BattlePanelsXY.MSG_CLOSE = 0.72      -- the fan's size knob (see CLOSE there)

BattlePanelsXY.BTN_RIGHT = 12.1      -- cluster centre, along camera right
BattlePanelsXY.FIGHT_UP = 6.6
BattlePanelsXY.ROW_UP = 3.0
BattlePanelsXY.ROW_STEP = 5.2        -- spacing of the bottom three
BattlePanelsXY.FIGHT_W = 6.2
BattlePanelsXY.SMALL_W = 4.4
BattlePanelsXY.BTN_YAW = math.rad(-12)
BattlePanelsXY.BTN_CLOSE = 0.74
BattlePanelsXY.UNSEL_ALPHA = 0.70
BattlePanelsXY.UNSEL_MUL = 0.90
BattlePanelsXY.UNSEL_SINK = -0.40
BattlePanelsXY.UNSEL_CLOSE = 0.035
BattlePanelsXY.SEL_MUL = 1.18          -- on top of popScale
BattlePanelsXY.SEL_LIFT = 1.4          -- toward camera, offU
BattlePanelsXY.SEL_CLOSE = -0.06       -- closer CLOSE
BattlePanelsXY.DEAL_TIME = 0.22
BattlePanelsXY.DEAL_STAGGER = 0.07
BattlePanelsXY.REENTRY_GAP = 0.25
BattlePanelsXY.DEAL_FROM_ABOVE = 5.8   -- FIGHT flies in from above
BattlePanelsXY.DEAL_FROM_BELOW = -4.4  -- the row, from below
BattlePanelsXY.DEAL_FROM_SIDE = 3.8
BattlePanelsXY.MSG_ENTER = 0.32        -- 0.7 -> 1.08 -> 1
BattlePanelsXY.UNDERLINE = 0.25
BattlePanelsXY.RIM_SCALE = 1.10
BattlePanelsXY.RIM_ALPHA = 0.25

-- the faces, in their own pixels; world height follows these aspects. The
-- message canvas has headroom on purpose -- the pane inside it is sized to
-- its text and the rest stays transparent, which is what lets the panel
-- hug two short lines without reallocating a canvas per typed character.
BattlePanelsXY.MSG_FACE_W = 640
BattlePanelsXY.MSG_FACE_H = 320
BattlePanelsXY.BTN_FACE_W = 400
BattlePanelsXY.BTN_FACE_H = 190
BattlePanelsXY.FIGHT_FACE_W = 460
BattlePanelsXY.FIGHT_FACE_H = 210

-- the kit's one accent colour (concepts 05-07): selection, corner ticks,
-- the underline under a message
BattlePanelsXY.GOLD = { 1.0, 0.84, 0.40 }

-- lazy, exactly like the fan's: BattleBoxXY loads this module from inside
-- its own draw, so load order must not matter
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

-- the B2W2 kit, for its name font: the dialog box and the chips speak
-- the same Unova the capsules do (available() gates per draw, so a
-- missing sheet falls back to the HUD glyphs)
local Cap = nil
local function capsule()
  if Cap == nil then
    local ok, C = pcall(V.require, "BattleCapsule")
    Cap = (ok and C) or false
  end
  return (Cap and Cap.available and Cap.available()) and Cap or nil
end

local S = {
  msg = nil,          -- { canvas, mesh, key }
  btns = {},          -- [menuIndex] = { canvas, mesh, key }
  dealAt = 0,
  lastDraw = 0,
  msgIdent = nil,
  msgEnterAt = 0,
  underlineAt = 0,
  last = nil,         -- what a probe measures
}

function BattlePanelsXY.debug()
  return S.last
end

-- ------- faces (the glass kit of concepts 05-07)
--
-- Light frost, not a dark slab: a pale pane the world reads through, a
-- crisp luminous border with gold corner ticks, and text that carries its
-- own contrast as an OUTLINE. The first cut used the move rows' recipe --
-- a dark base for contrast -- and at panel size that recipe buries
-- whatever stands behind the glass; the concepts threw it out. Buttons
-- are FULL capsules drawn here, label and all: the pack's half-capsule
-- art was made to be cut by a screen edge, and floating free it read as a
-- severed tab. Drawing them also retires the two-languages compromise the
-- baked-in English words forced (see the note on COMMANDS in BattleBoxXY).

local GOLD = BattlePanelsXY.GOLD

-- ease-out-back: overshoots ~10% then lands. The chips' punch.
local function easeOutBack(t)
  if t <= 0 then return 0 end
  if t >= 1 then return 1 end
  local c1, c3 = 1.70158, 2.70158
  local x = t - 1
  return 1 + c3 * x * x * x + c1 * x * x
end

-- message enter: 0.7 at t=0, peaks 1.08, lands 1
local function msgEnterMul(t)
  if t <= 0 then return 0.70 end
  if t >= 1 then return 1 end
  if t < 0.5 then
    local u = t / 0.5
    u = 1 - (1 - u) ^ 3
    return 0.70 + 0.38 * u
  end
  local u = (t - 0.5) / 0.5
  u = u * u * (3 - 2 * u)
  return 1.08 + (1.00 - 1.08) * u
end

-- White glyphs on pale glass need more than a drop shadow: an outline all
-- the way round, which is what keeps them legible over whatever bright
-- floor the frost happens to be showing.
local function outlineText(str, x, y, th, color)
  local o = math.max(2, math.floor(th * 0.08))
  for _, d in ipairs({ { -o, 0 }, { o, 0 }, { 0, -o }, { 0, o },
                       { -o, -o }, { o, -o }, { -o, o }, { o, o } }) do
    BattleHudXY.text(str, x + d[1], y + d[2], th, { 0, 0, 0, 0.8 })
  end
  BattleHudXY.text(str, x, y, th, color or { 1, 1, 1, 1 })
end

-- The kit's corner brackets, gold, one L per corner.
local function cornerTicks(g, x, y, w, h)
  local len, lw = 30, 5
  local x2, y2 = x + w, y + h
  g.setColor(GOLD[1], GOLD[2], GOLD[3], 0.95)
  g.setLineWidth(lw)
  g.line(x, y + len, x, y, x + len, y)
  g.line(x2 - len, y, x2, y, x2, y + len)
  g.line(x2, y2 - len, x2, y2, x2 - len, y2)
  g.line(x + len, y2, x, y2, x, y2 - len)
  g.setLineWidth(1)
end

-- One command as a full capsule of tinted glass. The move rows' measured
-- lesson still holds at capsule size: colour alone dissolves over a bright
-- floor, so a dark base buys the contrast and the colour keeps the hue.
local function drawButtonFace(slot, B, cmd, selected, W, H)
  local g = love.graphics
  if not slot.canvas then
    local ok, c = pcall(g.newCanvas, W, H, { dpiscale = 1 })
    if not (ok and c) then return false end
    slot.canvas = c
  end
  local prevCanvas = g.getCanvas()
  local prevBlend, prevAlpha = g.getBlendMode()
  local ok, err = pcall(function()
    g.setCanvas(slot.canvas)
    g.clear(0, 0, 0, 0)
    g.setBlendMode("alpha")
    local m = 22                       -- room for the bloom to breathe
    local bx, by = m, m
    local bw, bh = W - 2 * m, H - 2 * m
    local r = bh * 0.5                 -- radius = half height: a capsule
    local c = cmd.color
    -- the capsule's own outline, for the frost under it
    slot.panePx = { bx, by, bw, bh }
    slot.paneR = r

    if selected then
      -- the bloom: expanding gold strokes fading out
      for i = 3, 1, -1 do
        g.setColor(GOLD[1], GOLD[2], GOLD[3], 0.07 * i)
        g.setLineWidth(6 + i * 7)
        g.rectangle("line", bx, by, bw, bh, r, r)
      end
    end
    -- lighter than they were: the frost underneath carries the body now
    g.setColor(B.PANEL[1], B.PANEL[2], B.PANEL[3],
               selected and 0.30 or 0.40)
    g.rectangle("fill", bx, by, bw, bh, r, r)
    g.setColor(c[1], c[2], c[3], selected and 0.66 or 0.38)
    g.rectangle("fill", bx, by, bw, bh, r, r)
    -- gloss across the crown
    g.setColor(1, 1, 1, selected and 0.22 or 0.14)
    g.rectangle("fill", bx + bw * 0.07, by + bh * 0.10,
                bw * 0.86, bh * 0.36, bh * 0.18, bh * 0.18)
    -- the rim: gold when chosen, the command's own colour brightened when
    -- not -- stepped back but still tellable apart at a glance
    if selected then
      g.setColor(GOLD[1], GOLD[2], GOLD[3], 0.95)
      g.setLineWidth(6)
    else
      g.setColor(c[1] * 0.55 + 0.45, c[2] * 0.55 + 0.45,
                 c[3] * 0.55 + 0.45, 1)
      g.setLineWidth(4.5)
    end
    g.rectangle("line", bx, by, bw, bh, r, r)
    g.setLineWidth(1)

    -- the label, the game's own word, shrunk to fit the capsule's flat
    -- middle rather than clipped by its round ends -- in Unova's font
    -- when the sheet is loaded
    local C = capsule()
    local maxw = bw - bh * 0.8
    if C then
      local kk = (bh * 0.50) / 9
      local tw = C.textWidth(cmd.label) * kk
      if tw > maxw and tw > 0 then
        kk = kk * maxw / tw
        tw = maxw
      end
      g.setColor(1, 1, 1, selected and 1 or 0.9)
      C.text(cmd.label, bx + (bw - tw) * 0.5, by + (bh - 9 * kk) * 0.5, kk)
      g.setColor(1, 1, 1, 1)
    else
      local th = bh * 0.46
      local tw = BattleHudXY.textWidth(cmd.label) * (th / 84)
      if tw > maxw and tw > 0 then
        th = th * maxw / tw
        tw = maxw
      end
      outlineText(cmd.label, bx + (bw - tw) * 0.5, by + (bh - th) * 0.5, th,
                  { 1, 1, 1, selected and 1 or 0.9 })
    end
  end)
  if prevCanvas then g.setCanvas(prevCanvas) else g.setCanvas() end
  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  g.setColor(1, 1, 1, 1)
  if not ok then error(err, 0) end
  return true
end

-- The message on its pane, and the pane HUGS the text -- measured first,
-- drawn second, the rest of the canvas left transparent. That emptiness is
-- the fix for the slab: the quad in the world stays one size and the
-- visible panel inside it is exactly as big as what it has to say.
local function drawMsgFace(slot, B, msgLines, uFrac, showCaret)
  local g = love.graphics
  local W, H = BattlePanelsXY.MSG_FACE_W, BattlePanelsXY.MSG_FACE_H
  if not slot.canvas then
    local ok, c = pcall(g.newCanvas, W, H, { dpiscale = 1 })
    if not (ok and c) then return false end
    slot.canvas = c
  end

  -- Unova type when the sheet is loaded (see BattleCapsule.text), the
  -- HUD glyphs when it is not. Both paths measure first: the pane hugs
  -- whichever font is speaking.
  local C = capsule()
  local th = 64
  local padX, padY = 44, 30
  local widest = 0
  local ck = 6
  if C then
    for _, line in ipairs(msgLines) do
      widest = math.max(widest, C.textWidth(line) * ck)
    end
  else
    for _, line in ipairs(msgLines) do
      widest = math.max(widest, BattleHudXY.textWidth(line) * (th / 84))
    end
  end
  local maxTextW = W - 2 * (padX + 16)
  if widest > maxTextW and widest > 0 then
    if C then ck = ck * maxTextW / widest end
    th = th * maxTextW / widest
    widest = maxTextW
  end
  local lineH = C and (9 * ck * 1.5) or (th * 1.42)
  local n = #msgLines
  local pw = math.max(280, widest + 2 * padX)
  local ph = math.max(110, n * lineH + (n > 0 and 26 or 0) + 2 * padY)
  local px = (W - pw) * 0.5
  local py = (H - ph) * 0.5
  -- where the pane landed, for the frost pass
  slot.panePx = { px, py, pw, ph }
  slot.paneR = 14

  local prevCanvas = g.getCanvas()
  local prevBlend, prevAlpha = g.getBlendMode()
  local ok, err = pcall(function()
    g.setCanvas(slot.canvas)
    g.clear(0, 0, 0, 0)
    g.setBlendMode("alpha")
    local r = 14
    -- barely a tint: the REAL frost is the sampled blur laid under this
    -- face (frostPass); a strong fill here would paint over it
    g.setColor(0.90, 0.94, 1.00, 0.13)
    g.rectangle("fill", px, py, pw, ph, r, r)
    g.setColor(1, 1, 1, 0.07)
    g.rectangle("fill", px, py, pw, ph * 0.42, r, r)
    -- luminous border: a soft halo under a crisp line
    g.setColor(1, 1, 1, 0.14)
    g.setLineWidth(11)
    g.rectangle("line", px, py, pw, ph, r, r)
    g.setColor(1, 1, 1, 0.92)
    g.setLineWidth(3.5)
    g.rectangle("line", px, py, pw, ph, r, r)
    g.setLineWidth(1)
    cornerTicks(g, px, py, pw, ph)

    local ly = py + padY
    for _, line in ipairs(msgLines) do
      if C then
        g.setColor(1, 1, 1, 1)
        C.text(line, px + padX, ly, ck)
      else
        outlineText(line, px + padX, ly, th, B.TEXT)
      end
      ly = ly + lineH
    end
    -- the gold underline accent, growing from centre on a new message
    if n > 0 then
      local uw = pw * 0.44 * math.max(0, math.min(1, uFrac or 1))
      local ux = px + (pw - uw) * 0.5
      local uy = ly + 2
      if uw > 1 then
        g.setColor(GOLD[1], GOLD[2], GOLD[3], 0.30)
        g.setLineWidth(9)
        g.line(ux, uy, ux + uw, uy)
        g.setColor(GOLD[1], GOLD[2], GOLD[3], 0.95)
        g.setLineWidth(3.5)
        g.line(ux, uy, ux + uw, uy)
        g.setLineWidth(1)
      end
    end
    -- gold caret at the typewriter's own end (read charIndex, never write it)
    if showCaret and n > 0 then
      local last = msgLines[n]
      local tw
      if C then
        tw = C.textWidth(last) * ck
      else
        tw = BattleHudXY.textWidth(last) * (th / 84)
      end
      local cx = px + padX + tw + 8
      local cy = ly - lineH + 4
      g.setColor(GOLD[1], GOLD[2], GOLD[3], 0.95)
      g.rectangle("fill", cx, cy, 6, math.max(8, lineH * 0.62))
    end
  end)
  if prevCanvas then g.setCanvas(prevCanvas) else g.setCanvas() end
  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  g.setColor(1, 1, 1, 1)
  if not ok then error(err, 0) end
  return true
end

-- ------- hanging one panel
--
-- offR/offU place the centre in the rig's frame; the fan's CLOSE knob
-- (slide toward the eye along the centre's own ray) sets the size on
-- screen without moving it; `mul` is the pop, as a world-size multiplier.
-- `frost` lays the sampled-blur glass under the face first (Fan.frost,
-- shared with the move cards), following the pane rect and radius the
-- face recorded on its slot -- so it hugs the message's tight pane and
-- the buttons' capsule outline alike.
local function hangPanel(slot, shot, R, offR, offU, w, faceW, faceH, yaw,
                         close, alpha, mul, frost, fxId,
                         extraOffU, extraClose, rimColor)
  offU = offU + (extraOffU or 0)
  close = close + (extraClose or 0)
  local c = Fan.vadd(Fan.vadd(R.base, R.up, offU), R.right, offR)
  -- the glass physics first (BattleGlassFX): the idle bob, and the shove
  -- when a landed hit's wave reaches this panel -- applied in world
  -- units, BEFORE the size pull, so every panel rocks at its own depth
  local FX = fxId and glassFX()
  if FX then
    local okJ, jR, jU = pcall(FX.jolt, fxId, c, R)
    if okJ and jR then
      c = Fan.vadd(Fan.vadd(c, R.right, jR), R.up, jU)
    end
  end
  c = Fan.vadd(shot.eye, Fan.vadd(c, shot.eye, -1), close)
  local ww = w * (mul or 1)
  local cr = Fan.vrot(R.right, R.up, yaw)
  local hh = ww * faceH / faceW
  if frost then
    pcall(Fan.frost, slot, shot, c, cr, R.up,
          ww, hh, faceW, faceH,
          slot.panePx, slot.paneR or 14, alpha or 1)
  end
  local mesh = Fan.hang(slot, shot, c, cr, R.up, ww, hh)
  if not mesh then return nil end
  local g = love.graphics
  g.setColor(1, 1, 1, alpha or 1)
  g.draw(mesh)
  g.setColor(1, 1, 1, 1)
  -- additive gold/type rim on the selected chip (or any caller that asks)
  if rimColor then
    local rs = BattlePanelsXY.RIM_SCALE
    local hw, hv = ww * 0.5 * rs, hh * 0.5 * rs
    local function corner(sx, sy)
      return R.project(Fan.vadd(Fan.vadd(c, cr, sx), R.up, sy))
    end
    local x1, y1 = corner(-hw, hv)
    local x2, y2 = corner(hw, hv)
    local x3, y3 = corner(hw, -hv)
    local x4, y4 = corner(-hw, -hv)
    if x1 and x2 and x3 and x4 then
      local prevBlend, prevA = g.getBlendMode()
      g.setBlendMode("add")
      local t = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
      local pulse = 0.55 + 0.45 * math.sin(t * 5.4)
      g.setColor(rimColor[1], rimColor[2], rimColor[3],
                 BattlePanelsXY.RIM_ALPHA * pulse)
      g.polygon("fill", x1, y1, x2, y2, x3, y3, x4, y4)
      g.setBlendMode(prevBlend or "alpha", prevA)
      g.setColor(1, 1, 1, 1)
    end
  end
  -- the weather lands on the dialog box: the playing move's element, and
  -- status bursts (paralysis arcing across the glass and kin)
  if FX and fxId == "msg" and slot.panePx then
    local map, ss = Fan.paneMapper(shot, c, cr, R.up, ww, hh,
                                   faceW, faceH, slot.panePx)
    pcall(FX.overlayMsg, map, ss, slot.panePx[3], slot.panePx[4])
  end
  local px, py = R.project(c)
  return px, py, c
end

local function msgPanel(shot, R, B, msgLines, battle)
  S.msg = S.msg or {}
  local now = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
  -- Empty lines with a pane already up HOLD the last pane: the pane is
  -- sized to its text now, and re-rendering it empty between two chained
  -- messages would blink it down to a stub and back up -- a flicker the
  -- old fixed slab never had to think about.
  local ident
  local full = battle and battle.current and battle.current.text
  if type(full) == "string" and full ~= "" then
    ident = full
  else
    ident = table.concat(msgLines or {}, "\n")
  end
  if ident ~= S.msgIdent then
    S.msgIdent = ident
    S.msgEnterAt = now
    S.underlineAt = now
  end
  local uFrac = math.min(1, (now - (S.underlineAt or now))
                         / BattlePanelsXY.UNDERLINE)
  local ci = battle and battle.charIndex
  local typing = type(full) == "string" and type(ci) == "number" and ci < #full
  local caretOn = typing and ((now * 3.2) % 1 > 0.38)
  if #msgLines > 0 or not S.msg.canvas then
    local key = table.concat(msgLines, "\n")
                .. ":" .. tostring(math.floor(uFrac * 16))
                .. (caretOn and "C" or "-")
    if S.msg.key ~= key then
      local ok = pcall(drawMsgFace, S.msg, B, msgLines, uFrac, caretOn)
      if not (ok and S.msg.canvas) then return nil end
      S.msg.key = key
    end
  end
  local enterT = (now - (S.msgEnterAt or now)) / BattlePanelsXY.MSG_ENTER
  local msgMul = msgEnterMul(enterT)
  return hangPanel(S.msg, shot, R,
                   BattlePanelsXY.MSG_RIGHT, BattlePanelsXY.MSG_UP,
                   BattlePanelsXY.MSG_W,
                   BattlePanelsXY.MSG_FACE_W, BattlePanelsXY.MSG_FACE_H,
                   BattlePanelsXY.MSG_YAW, BattlePanelsXY.MSG_CLOSE, 1, msgMul,
                   true, "msg")
end

-- ------- the phases

-- The messages phase: just the panel, hanging where the menu left it --
-- which is the continuity that makes the two phases read as one piece of
-- furniture, and the frame the attack camera gets to push around.
function BattlePanelsXY.message(battle, shot, msgLines)
  if not (BattlePanelsXY.ENABLED and battle and shot) then return false end
  local B = box(); if not B then return false end
  local R = Fan.rig(shot)
  if not R then return false end
  local mx, my = msgPanel(shot, R, B, msgLines or {}, battle)
  if not mx then return false end
  S.last = { phase = "message", msg = { mx, my } }
  return true
end

-- The command menu: the panel plus the four chips. All or nothing, like
-- the fan -- half a menu is worse than the flat one.
function BattlePanelsXY.menu(battle, shot, msgLines)
  if not (BattlePanelsXY.ENABLED and battle and shot) then return false end
  local B = box(); if not B then return false end
  local R = Fan.rig(shot)
  if not R then return false end

  local mx, my = msgPanel(shot, R, B, msgLines or {}, battle)
  if not mx then return false end

  local sel = tonumber(battle.menuIndex) or 1
  local pop = B.popScale("menu", sel)
  local dbg = { phase = "menu", sel = sel, msg = { mx, my },
                cx = {}, cy = {}, wx = {}, wy = {}, wz = {} }

  -- where each command sits: FIGHT alone on top, the pack's own bottom
  -- order underneath (see BattleBoxXY.BOTTOM_ORDER for why it is not the
  -- cursor's). Each entry carries its face dimensions too -- FIGHT's
  -- capsule is cut larger than the row's.
  local place = { [1] = { BattlePanelsXY.BTN_RIGHT, BattlePanelsXY.FIGHT_UP,
                          BattlePanelsXY.FIGHT_W,
                          BattlePanelsXY.FIGHT_FACE_W,
                          BattlePanelsXY.FIGHT_FACE_H } }
  for slotPos, i in ipairs(B.BOTTOM_ORDER) do
    place[i] = { BattlePanelsXY.BTN_RIGHT
                 + (slotPos - 2) * BattlePanelsXY.ROW_STEP,
                 BattlePanelsXY.ROW_UP, BattlePanelsXY.SMALL_W,
                 BattlePanelsXY.BTN_FACE_W, BattlePanelsXY.BTN_FACE_H }
  end

  -- menu-open deal: first time this phase, or a reentry gap like the fan
  local now = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
  if now - S.lastDraw > BattlePanelsXY.REENTRY_GAP then
    S.dealAt = now
  end
  S.lastDraw = now

  -- deal index: FIGHT first (0), then BAG / RUN / POKEMON in the row
  local dealOf = { [1] = 0 }
  local sideOf = { [1] = 0 }
  for slotPos, i in ipairs(B.BOTTOM_ORDER) do
    dealOf[i] = slotPos
    sideOf[i] = (slotPos == 1) and -1 or (slotPos == 3) and 1 or 0
  end

  -- the selected chip draws last, so its swell overlaps its neighbours
  -- instead of vanishing under them
  local order = {}
  for i = 1, 4 do if i ~= sel then order[#order + 1] = i end end
  order[#order + 1] = sel

  for _, i in ipairs(order) do
    local cmd = B.COMMANDS[i]
    local p = place[i]
    if not (cmd and p) then return false end
    local slot = S.btns[i]
    if not slot then slot = {}; S.btns[i] = slot end
    local key = cmd.art .. (i == sel and ":S" or ":-")
    if slot.key ~= key then
      local okF = pcall(drawButtonFace, slot, B, cmd, i == sel, p[4], p[5])
      if not (okF and slot.canvas) then return false end
      slot.key = key
    end

    local raw = (now - S.dealAt - (dealOf[i] or 0) * BattlePanelsXY.DEAL_STAGGER)
                / BattlePanelsXY.DEAL_TIME
    local dp = math.max(0, math.min(1, raw))
    local ease = easeOutBack(dp)
    local fly = 1 - ease
    local dealU, dealR = 0, 0
    if i == 1 then
      dealU = BattlePanelsXY.DEAL_FROM_ABOVE * fly
    else
      dealU = BattlePanelsXY.DEAL_FROM_BELOW * fly
      dealR = (sideOf[i] or 0) * BattlePanelsXY.DEAL_FROM_SIDE * fly
    end

    local selected = (i == sel)
    local mul = selected and (pop * BattlePanelsXY.SEL_MUL)
                        or BattlePanelsXY.UNSEL_MUL
    local extraU = dealU + (selected and BattlePanelsXY.SEL_LIFT
                                     or BattlePanelsXY.UNSEL_SINK)
    local extraC = selected and BattlePanelsXY.SEL_CLOSE
                            or BattlePanelsXY.UNSEL_CLOSE
    local alpha = selected and 1 or BattlePanelsXY.UNSEL_ALPHA
    local rim = selected and ((i == 1 and cmd.color) or GOLD) or nil
    -- until this chip's deal starts it stays invisible; faces stay ready
    if dp > 0 then
      local cx, cy, world = hangPanel(slot, shot, R, p[1] + dealR, p[2], p[3],
                               p[4], p[5],
                               BattlePanelsXY.BTN_YAW,
                               BattlePanelsXY.BTN_CLOSE,
                               alpha, mul, true, "btn" .. i,
                               extraU, extraC, rim)
      if not cx then return false end
      dbg.cx[i], dbg.cy[i] = cx, cy
      if world then
        dbg.wx[i], dbg.wy[i], dbg.wz[i] = world[1], world[2], world[3]
      end
    end
  end

  S.last = dbg
  return true
end

return BattlePanelsXY
