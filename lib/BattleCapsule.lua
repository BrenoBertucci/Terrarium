-- The HP capsules, wearing Black 2's own bars.
--
-- The art is the real thing: the Black 2 / White 2 HP bar sheet (ripped
-- by GameMaster12, spriters-resource), carved into parts by
-- scratchpad/extract_b2w2.py -- the carbon plate with its HP tag, baked
-- slash and EXP row; the silver track and the green/amber/red fill
-- strips; the segmented EXP strips; the italic HP digits; the gold level
-- numbers and Lv. tag; the five status chips; and the sheet's own name
-- font. The glass experiment that preceded this lives on only as unused
-- PNGs -- the user's ruling was: glass belongs to the dialog box, the HP
-- bar belongs to Unova.
--
-- WHAT IS COMPOSED. A name row (status chip, name, Lv. and level) above
-- the plate, exactly the layout the sheet's own example uses. The fill
-- is drawn live: the silver track first, full width -- it covers the
-- fill baked into the plate crop, which is what makes erasing it
-- unnecessary -- then the coloured strip cropped to the shown fraction,
-- picked by the same thresholds the engine's own bar uses. The EXP row
-- is the empty segmented strip with the filled one cropped over it: at
-- last part of the panel, never an orphan bar (see the QoL ghost).
--
-- Faces bake at an INTEGER scale (BAKE) with nearest filtering, so the
-- pixel art stays pixel art; the world mesh then scales the finished
-- canvas continuously, softening it exactly as much as every other HUD
-- glyph in the mode.
--
-- Placement is unchanged from the glass era: hung in the arena beside
-- its own mon through the shared rig, bobbing and rocking with
-- BattleGlassFX. Same block() contract as the pack renderer, same
-- degradation ladder: no sheet assets -> the 5X pack blocks.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local BattleHudXY = V.require("BattleHudXY")

local BattleCapsule = {}

BattleCapsule.ENABLED = true

BattleCapsule.ASSET_DIR = "assets/battlexy/b2w2/"

-- the frame, in SHEET pixels; faces bake at BAKE screen px per sheet px
BattleCapsule.FRAME_W = 115
BattleCapsule.PLAYER_H = 31
BattleCapsule.ENEMY_H = 25
BattleCapsule.BAKE = 6

-- ------- layout, in sheet pixels (measured off the extraction, see the
-- pixel dumps in the session: fill rows y2..4 of the plate, EXP rows
-- y15..16, strips carrying a 1px outline ring around a 48x3 / 80x2 core)
local L = {
  pad = 1,
  nameH = 9,
  chipY = 2,                    -- the 19x6 chip, inside the name row
  nameX = 22,
  lvEnd = 111,                  -- level digits right-align to here
  plateY = 11,                  -- name row + a 2px breath
  fillP = { 49, 2, 50, 3 },     -- plate-local fill rect, player
  fillE = { 37, 2, 50, 3 },     -- and enemy
  exp = { 26, 15, 80, 2 },
  digitsY = 5,                  -- plate-local top of the 8px digits row
  slashX = 74,                  -- where the drawn slash cell lands
}
local TRACK_SRC = { 1, 1, 48, 3 }   -- the strips' cores
local EXP_SRC = { 1, 1, 80, 2 }

local CHIP_ORDER = { SLP = 0, PSN = 1, TOX = 2, BRN = 3, FRZ = 4, PAR = 5 }

local images = {}

local function art(name)
  local hit = images[name]
  if hit ~= nil then return hit or nil end
  local okA, Assets = pcall(require, "src.render.Assets")
  if not okA or not Assets then images[name] = false; return nil end
  local path = V.path .. "/" .. BattleCapsule.ASSET_DIR .. name .. ".png"
  local okE, exists = pcall(Assets.exists, path)
  if not (okE and exists) then images[name] = false; return nil end
  local ok, img = pcall(Assets.image, path)
  if not (ok and img) then images[name] = false; return nil end
  -- nearest, unlike every other loader here: this is pixel art and a
  -- linear minifier would smear Unova's one-pixel outlines
  pcall(img.setFilter, img, "nearest", "nearest")
  images[name] = img
  return img
end

local fontData = nil
local function fdata()
  if fontData == nil then
    local ok, d = pcall(V.data, "b2w2_font")
    fontData = (ok and d) or false
  end
  return fontData or nil
end

function BattleCapsule.available()
  if not BattleCapsule.ENABLED then return false end
  if not fdata() then return false end
  return art("plate_player") ~= nil and art("plate_enemy") ~= nil
    and art("track") ~= nil and art("fill_green") ~= nil
    and art("fill_amber") ~= nil and art("fill_red") ~= nil
    and art("exp_fill") ~= nil and art("exp_empty") ~= nil
    and art("hp_digits") ~= nil and art("lv_digits") ~= nil
    and art("lv_tag") ~= nil and art("status_chips") ~= nil
    and art("name_font") ~= nil
end

local function quad(img, x, y, w, h)
  local iw, ih = img:getDimensions()
  return love.graphics.newQuad(x, y, w, h, iw, ih)
end

-- ------- the sheet's own type

-- the sheet's own name font, exported: the dialog box, the command chips
-- and the move cards all borrow it, so the whole costume speaks Unova.
-- 9px glyphs, 1px tracking, walked a CHARACTER at a time (the lesson
-- BattleHudXY's POKDEX bug already paid for) with Portuguese accents
-- folded to their bare letters -- the sheet has none, and a hole in the
-- middle of "Critico" is worse than a missing accent.
local FOLD = {
  ["\195\161"] = "a", ["\195\160"] = "a", ["\195\162"] = "a",
  ["\195\163"] = "a", ["\195\169"] = "e", ["\195\170"] = "e",
  ["\195\168"] = "e", ["\195\173"] = "i", ["\195\179"] = "o",
  ["\195\180"] = "o", ["\195\181"] = "o", ["\195\186"] = "u",
  ["\195\167"] = "c",
  ["\195\129"] = "A", ["\195\128"] = "A", ["\195\130"] = "A",
  ["\195\131"] = "A", ["\195\137"] = "E", ["\195\138"] = "E",
  ["\195\141"] = "I", ["\195\147"] = "O", ["\195\148"] = "O",
  ["\195\149"] = "O", ["\195\154"] = "U", ["\195\135"] = "C",
}

local function charAt(s, i)
  local b = s:byte(i)
  if not b then return nil, 0 end
  local len = 1
  if b >= 0xF0 then len = 4
  elseif b >= 0xE0 then len = 3
  elseif b >= 0xC0 then len = 2 end
  if i + len - 1 > #s then len = 1 end
  return s:sub(i, i + len - 1), len
end

local function glyphFor(d, ch)
  local m = d.nameFont[ch]
  if m then return m end
  local f = FOLD[ch]
  if f then
    m = d.nameFont[f]
    if m then return m end
  end
  return d.nameFont[ch:upper()] or d.nameFont[ch:lower()]
end

-- width in SHEET pixels; multiply by the caller's own k
function BattleCapsule.textWidth(str)
  local d = fdata()
  if not (d and str) then return 0 end
  local pen, i = 0, 1
  while i <= #str do
    local ch, len = charAt(str, i)
    if not ch then break end
    if ch == " " then
      pen = pen + 4
    else
      local m = glyphFor(d, ch)
      if m then pen = pen + m[2] + 1 end
    end
    i = i + len
  end
  return pen
end

-- draws in the CURRENT colour: the glyphs are white with a dark outline,
-- so a tint colours the face and leaves the outline its contrast
function BattleCapsule.text(str, x, y, k)
  local img = art("name_font")
  local d = fdata()
  if not (img and d and str) then return 0 end
  local pen, i = 0, 1
  while i <= #str do
    local ch, len = charAt(str, i)
    if not ch then break end
    if ch == " " then
      pen = pen + 4
    else
      local m = glyphFor(d, ch)
      if m then
        love.graphics.draw(img, quad(img, m[1], 0, m[2], 9),
                           x + pen * k, y, 0, k, k)
        pen = pen + m[2] + 1
      end
    end
    i = i + len
  end
  return pen * k
end

-- the italic HP digits: fixed 8x8 cells, drawn with a 7px advance so
-- the slants tuck together the way the sheet's own example spaces them
local HP_ADV = 7

local function hpNumberWidth(str)
  return #str * HP_ADV + 1
end

local function hpNumber(str, x, y, k)
  local img = art("hp_digits")
  if not img then return end
  local pen = 0
  for i = 1, #str do
    local c = str:byte(i) - 48
    if c >= 0 and c <= 9 then
      love.graphics.draw(img, quad(img, c * 8, 0, 8, 8),
                         x + pen * k, y, 0, k, k)
      pen = pen + HP_ADV
    end
  end
end

-- the gold level numbers: variable widths from the extraction table
local function lvNumberWidth(str)
  local d = fdata()
  if not d then return 0 end
  local pen = 0
  for i = 1, #str do
    local m = d.lvDigits[str:sub(i, i)]
    if m then pen = pen + m[2] + 1 end
  end
  return pen
end

local function lvNumber(str, x, y, k)
  local img = art("lv_digits")
  local d = fdata()
  if not (img and d) then return end
  local pen = 0
  for i = 1, #str do
    local m = d.lvDigits[str:sub(i, i)]
    if m then
      love.graphics.draw(img, quad(img, m[1], 0, m[2], 9),
                         x + pen * k, y, 0, k, k)
      pen = pen + m[2] + 1
    end
  end
end

-- ------- the bar itself

local function fillStrip(frac)
  if frac <= BattleHudXY.HP_LOW_AT then return art("fill_red") end
  if frac <= BattleHudXY.HP_MID_AT then return art("fill_amber") end
  return art("fill_green")
end

-- Same contract as ever: `info` is BattleHudXY.read's answer, `w` the
-- block's width on whatever it is being drawn into.
function BattleCapsule.block(info, x, y, w, expFrac)
  if not (info and BattleCapsule.available()) then return false end
  local isP = info.isPlayer
  local plate = art(isP and "plate_player" or "plate_enemy")
  if not plate then return false end
  local g = love.graphics
  local k = w / BattleCapsule.FRAME_W
  local ox = x + L.pad * k
  local rowY = y + L.pad * k

  g.setColor(1, 1, 1, 1)

  -- the name row: chip, name, Lv. and the gold level
  local chips = art("status_chips")
  local nx = ox
  if chips and type(info.status) == "string" then
    local idx = CHIP_ORDER[info.status:upper():sub(1, 3)]
    if idx then
      g.draw(chips, quad(chips, idx * 20, 0, 19, 6),
             ox, rowY + L.chipY * k, 0, k, k)
      nx = ox + 21 * k
    end
  end
  BattleCapsule.text(info.name, math.max(nx, ox + L.nameX * k), rowY, k)
  local lvStr = tostring(info.level or 0)
  local lvW = lvNumberWidth(lvStr)
  local lvX = ox + (L.lvEnd - lvW) * k
  lvNumber(lvStr, lvX, rowY, k)
  local tag = art("lv_tag")
  if tag then
    g.draw(tag, lvX - 10 * k, rowY + 1 * k, 0, k, k)
  end

  -- the plate, and the bar drawn live over its baked one: silver track
  -- first (it covers the crop's full green exactly), colour on top
  local plateY = y + (L.pad + L.plateY) * k
  g.draw(plate, ox, plateY, 0, k, k)
  local fr = isP and L.fillP or L.fillE
  local frac = math.max(0, math.min(1, info.hp / math.max(1, info.maxHP)))
  local track = art("track")
  if track then
    g.draw(track, quad(track, TRACK_SRC[1], TRACK_SRC[2],
                       TRACK_SRC[3], TRACK_SRC[4]),
           ox + fr[1] * k, plateY + fr[2] * k, 0,
           fr[3] * k / TRACK_SRC[3], fr[4] * k / TRACK_SRC[4])
  end
  if frac > 0 then
    local strip = fillStrip(frac)
    if strip then
      local sw = math.max(1, TRACK_SRC[3] * frac)
      g.draw(strip, quad(strip, TRACK_SRC[1], TRACK_SRC[2],
                         sw, TRACK_SRC[4]),
             ox + fr[1] * k, plateY + fr[2] * k, 0,
             (fr[3] * frac * k) / sw, fr[4] * k / TRACK_SRC[4])
    end
  end

  -- the pair around a DRAWN slash (cell 10 of the atlas -- the plate's
  -- baked one is a dotted placeholder, invisible at game scale); the foe
  -- keeps its numbers to itself, the asymmetry the games have always kept
  if isP then
    local hpStr = tostring(info.hp)
    local maxStr = tostring(info.maxHP)
    local dy = plateY + L.digitsY * k
    local img = art("hp_digits")
    if img then
      g.draw(img, quad(img, 80, 0, 8, 8), ox + L.slashX * k, dy, 0, k, k)
    end
    hpNumber(hpStr, ox + (L.slashX - 1) * k - hpNumberWidth(hpStr) * k,
             dy, k)
    hpNumber(maxStr, ox + (L.slashX + 8) * k, dy, k)
  end

  -- the EXP row: the empty segmented strip full width, the filled one
  -- cropped to the fraction -- part of the plate, not a bar of its own
  if isP and expFrac then
    local ee = art("exp_empty")
    local ef = art("exp_fill")
    local ex = ox + L.exp[1] * k
    local ey = plateY + L.exp[2] * k
    if ee then
      g.draw(ee, quad(ee, EXP_SRC[1], EXP_SRC[2], EXP_SRC[3], EXP_SRC[4]),
             ex, ey, 0, L.exp[3] * k / EXP_SRC[3], L.exp[4] * k / EXP_SRC[4])
    end
    local efrac = math.max(0, math.min(1, expFrac))
    if ef and efrac > 0 then
      local sw = math.max(1, EXP_SRC[3] * efrac)
      g.draw(ef, quad(ef, EXP_SRC[1], EXP_SRC[2], sw, EXP_SRC[4]),
             ex, ey, 0, (L.exp[3] * efrac * k) / sw,
             L.exp[4] * k / EXP_SRC[4])
    end
  end

  g.setColor(1, 1, 1, 1)
  BattleCapsule._last = BattleCapsule._last or {}
  BattleCapsule._last[isP and "player" or "enemy"] = {
    x = x, y = y, w = w, frac = frac, exp = expFrac or false,
  }
  return true
end

-- ------- stage two: the capsules IN the arena (unchanged geometry)
--
-- Concept 08's shot: each panel hangs tilted near its own mon, anchored
-- through the same rig the fan and the menu use. The face bakes at an
-- integer scale only when what it says changes; per frame the cost is
-- one mesh draw per side, plus the physics.

BattleCapsule.WORLD = true

BattleCapsule.W_PLAYER = { up = 14.6, right = -0.5, w = 11.0,
                           yaw = math.rad(-10), close = 0.78 }
BattleCapsule.W_ENEMY = { up = 11.3, right = -8.5, w = 11.0,
                          yaw = math.rad(12), close = 0.62 }

local Fan = nil
local function fan()
  if Fan == nil then
    local ok, F = pcall(V.require, "BattleFanXY")
    Fan = (ok and F) or false
  end
  return Fan or nil
end

local GlassFX = nil
local function glassFX()
  if GlassFX == nil then
    local ok, F = pcall(V.require, "BattleGlassFX")
    GlassFX = (ok and F) or false
  end
  return GlassFX or nil
end

local WSLOT = { player = {}, enemy = {} }

function BattleCapsule.debug()
  return BattleCapsule._world
end

function BattleCapsule.worldReady(shot)
  return (BattleCapsule.ENABLED and BattleCapsule.WORLD
          and BattleCapsule.available()
          and shot and shot.vp and shot.eye and shot.playerCell
          and shot.enemyCell) and true or false
end

local function faceKey(info, expFrac)
  return table.concat({ info.name, info.level, info.hp, info.maxHP,
                        tostring(info.status),
                        expFrac and math.floor(expFrac * 800) or -1 }, ":")
end

function BattleCapsule.hang(shot, side, info, expFrac)
  if not (info and BattleCapsule.worldReady(shot)) then return false end
  local F = fan()
  if not F then return false end
  local R = F.rig(shot)
  if not R then return false end

  local isP = side == "player"
  local slot = WSLOT[side]
  local B = BattleCapsule.BAKE
  local H = isP and BattleCapsule.PLAYER_H or BattleCapsule.ENEMY_H
  local faceW = BattleCapsule.FRAME_W * B
  local faceH = H * B
  if not slot.canvas then
    local ok, c = pcall(love.graphics.newCanvas, faceW, faceH,
                        { dpiscale = 1 })
    if not (ok and c) then return false end
    slot.canvas = c
  end

  local key = faceKey(info, isP and expFrac or nil)
  if slot.key ~= key then
    local g = love.graphics
    local prevCanvas = g.getCanvas()
    local prevBlend, prevAlpha = g.getBlendMode()
    local ok = pcall(function()
      g.setCanvas(slot.canvas)
      g.clear(0, 0, 0, 0)
      g.setBlendMode("alpha")
      if not BattleCapsule.block(info, 0, 0, faceW, expFrac) then
        error("block refused", 0)
      end
    end)
    if prevCanvas then g.setCanvas(prevCanvas)
    else love.graphics.setCanvas() end
    g.setBlendMode(prevBlend or "alpha", prevAlpha)
    g.setColor(1, 1, 1, 1)
    if not ok then return false end
    slot.key = key
  end

  local P = isP and BattleCapsule.W_PLAYER or BattleCapsule.W_ENEMY
  local cell = isP and shot.playerCell or shot.enemyCell
  local base = { cell[1], shot.groundY or 0, cell[2] }
  local c = F.vadd(F.vadd(base, R.up, P.up), R.right, P.right)
  -- the glass physics: the capsule bobs on its own phase and rocks when
  -- a landed hit's wave reaches it -- it hangs nearest the mons, so it
  -- is the first glass the wave arrives at
  local FX = glassFX()
  if FX then
    local okJ, jR, jU = pcall(FX.jolt, "cap:" .. side, c, R)
    if okJ and jR then
      c = F.vadd(F.vadd(c, R.right, jR), R.up, jU)
    end
  end
  c = F.vadd(shot.eye, F.vadd(c, shot.eye, -1), P.close)
  local cr = F.vrot(R.right, R.up, P.yaw)
  local capH = P.w * H / BattleCapsule.FRAME_W
  -- menu-adjacent HUD: the player's capsule breathes a 4% scale pulse
  local ww, hh = P.w, capH
  if isP then
    local t = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
    local pulse = 1 + 0.04 * math.sin(t * 2 * math.pi * 1.5)
    ww, hh = P.w * pulse, capH * pulse
  end
  local mesh = F.hang(slot, shot, c, cr, R.up, ww, hh)
  if not mesh then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(mesh)
  -- and the quiet tick of a carried status, on the plate itself
  if FX and type(info.status) == "string" and info.status ~= "" then
    local map, ss = F.paneMapper(shot, c, cr, R.up, ww, hh,
                                 faceW, faceH,
                                 { 6, 6, faceW - 12, faceH - 12 })
    pcall(FX.overlayStatus, "cap:" .. side, map, ss,
          faceW - 12, faceH - 12, info.status)
  end
  local cx, cy = R.project(c)
  BattleCapsule._world = BattleCapsule._world or {}
  BattleCapsule._world[side] = cx and { cx, cy, frac = info.hp
                                        / math.max(1, info.maxHP) } or nil
  return cx and true or false
end

return BattleCapsule
