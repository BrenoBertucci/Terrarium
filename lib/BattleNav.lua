-- Battle-menu navigation that matches the costume, not the Game Boy grid.
--
-- The engine's BattleState still thinks in a 2x2 (FIGHT/PKMN over BAG/RUN)
-- and a vertical move list. The X/Y costume draws FIGHT above a BAG-RUN-PKMN
-- row, the moves as a left-to-right fan, and the party as a 2x3. This module
-- intercepts the dpad so the cursor walks the picture, and records a short
-- hop so the draw pass can throw a Poke Ball in an arc between the two chips.
--
-- The wrap is the bag's idea (ListMenu.script) applied one layer down:
-- Input:wasPressed is where BattleState reads the dpad. Swallowing the four
-- directions AFTER applying one visual step is what stops the engine from
-- also moving -- writing the index after it has already stepped would be a
-- double-move. A/B/Start/Select pass through. The bag keeps its own script
-- and is never wrapped here; party submenu pills stay a vertical list.
--
-- Swallowing is not enough on the command (and safari) 2x2. BattleState
-- captures col/row from menuIndex, queries wasPressed (where we step and
-- write the new index), then ALWAYS assigns
--   menuIndex = row * 2 + col + 1
-- from the OLD col/row -- so FIGHT comes back. A successful step therefore
-- also stores S.held = { kind, index }; BattleNav.pin() writes that index
-- back onto the live object. OverworldBattle.snapHUDs pins before Panels/Fan
-- read the cursor, and observe pins at the end of the frame so the next
-- BattleState update starts on RUN and A confirms RUN. Held lives until a
-- new step or the phase/kind leaves the remapped screen.
--
-- CLASSICA still remaps the command cluster (flat BattleBoxXY uses the same
-- BOTTOM_ORDER). The fan is remapped only while BattleFanXY.ENABLED. The
-- party 2x3 is remapped whenever BattleScreenXY is costuming PartyMenu.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...
local unpack = unpack or table.unpack

local BattleNav = {}

BattleNav.HOP_TIME = 0.22
BattleNav.HOP_HEIGHT = 26
BattleNav.BALL_R = 10
BattleNav.GOLD = { 1.0, 0.84, 0.40 }
BattleNav.PULSE_AMP = 0.25

-- the live hop the draw pass reads: { kind, from, to, at, color, x0,y0,x1,y1 }
BattleNav.hop = nil

local DIR_ORDER = { "up", "down", "left", "right" }
local DIRS = { up = true, down = true, left = true, right = true }

-- FIGHT on top, BAG-RUN-PKMN along the bottom. Wrap the row at the ends.
-- Down from FIGHT lands on RUN, which is the chip sitting under it.
local CMD = {
  [1] = { up = 4, down = 4, left = 3, right = 2 },
  [3] = { up = 1, down = 1, left = 2, right = 4 },
  [4] = { up = 1, down = 1, left = 3, right = 2 },
  [2] = { up = 1, down = 1, left = 4, right = 3 },
}

local S = {
  live = false,
  battle = nil,
  shot = nil,
  arena = nil,
  groundY = 0,
  frame = 0,
  drainFrame = -1,
  installed = false,
  pulsed = nil,     -- hop.at already pulsed
  held = nil,       -- { kind, index } last successful step
}

local function now()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or 0
end

local function game()
  local ok, G = pcall(require, "src.core.Game")
  return (ok and G) or nil
end

local function lazy(name)
  local ok, M = pcall(V.require, name)
  return (ok and M) or nil
end

-- duplicated from BattleScreenXY: requiring that file from here is fine
-- today, but the predicate is the contract and must not depend on load
-- order (BattleScreenXY must never require BattleNav).
local function partyShape(s)
  return type(s) == "table" and s.screenId == "PartyMenu"
         and type(s.index) == "number"
end

function BattleNav.commandNext(i, dir)
  i = tonumber(i) or 1
  local row = CMD[i] or CMD[1]
  return row[dir] or i
end

function BattleNav.moveNext(i, dir, n, disabled)
  n = tonumber(n) or 0
  if n <= 0 then return i end
  i = math.max(1, math.min(tonumber(i) or 1, n))
  local delta = (dir == "left" or dir == "up") and -1 or 1
  local start = i
  for _ = 1, n do
    i = ((i - 1 + delta) % n) + 1
    if i ~= disabled then return i end
    if i == start then break end
  end
  return start
end

function BattleNav.partyNext(i, dir, n)
  n = tonumber(n) or 0
  if n <= 0 then return i end
  i = math.max(1, math.min(tonumber(i) or 1, n))
  local col = (i - 1) % 2
  local row = math.floor((i - 1) / 2)
  if dir == "left" or dir == "right" then
    local other = row * 2 + (1 - col) + 1
    if other >= 1 and other <= n then return other end
    return i
  end
  local delta = (dir == "up") and -2 or 2
  return math.max(1, math.min(n, i + delta))
end

-- ------- centres the ball hops between
local function centresOf(kind)
  if kind == "menu" then
    local P = lazy("BattlePanelsXY")
    local pd = P and P.debug and P.debug()
    if pd and pd.phase == "menu" and pd.cx then return pd end
    local B = lazy("BattleBoxXY")
    local bd = B and B.debug and B.debug()
    if bd and bd.phase == "menu" and bd.cx then return bd end
  elseif kind == "move" then
    local F = lazy("BattleFanXY")
    local fd = F and F.debug and F.debug()
    if fd and fd.cx then return fd end
    local B = lazy("BattleBoxXY")
    local bd = B and B.debug and B.debug()
    if bd and bd.phase == "move" and bd.cx then return bd end
  elseif kind == "party" then
    local Scr = lazy("BattleScreenXY")
    local sd = Scr and Scr.debug and Scr.debug()
    if sd and sd.kind == "party" and sd.cx then return sd end
  end
  return nil
end

local function xyOf(dbg, i)
  if not (dbg and i) then return nil end
  local x, y = dbg.cx and dbg.cx[i], dbg.cy and dbg.cy[i]
  if not (x and y) then return nil end
  local wx = dbg.wx and dbg.wx[i]
  local wy = dbg.wy and dbg.wy[i]
  local wz = dbg.wz and dbg.wz[i]
  return x, y, wx, wy, wz
end

local function hopColor(kind, to, battle)
  if kind == "move" and battle and battle.player then
    local mv = battle.player.curMoves and battle.player.curMoves[to]
    local B = lazy("BattleBoxXY")
    if mv and B and B.typeName then
      local def = battle.data and battle.data.moves and battle.data.moves[mv.id]
      local tname = def and B.typeName(def.type)
      local c = tname and B.TYPE_COLOR and B.TYPE_COLOR[tname]
      if c then return { c[1], c[2], c[3] } end
    end
  end
  if kind == "menu" then
    local B = lazy("BattleBoxXY")
    local cmd = B and B.COMMANDS and B.COMMANDS[to]
    if cmd and cmd.color then
      return { cmd.color[1], cmd.color[2], cmd.color[3] }
    end
  end
  return { BattleNav.GOLD[1], BattleNav.GOLD[2], BattleNav.GOLD[3] }
end

local function recordHop(kind, from, to, battle)
  if from == to then return end
  local dbg = centresOf(kind)
  local x0, y0, wx0, wy0, wz0 = xyOf(dbg, from)
  local x1, y1, wx1, wy1, wz1 = xyOf(dbg, to)
  local at = now()
  BattleNav.hop = {
    kind = kind, from = from, to = to, at = at,
    color = hopColor(kind, to, battle),
    x0 = x0, y0 = y0, x1 = x1, y1 = y1,
    wx = wx1, wy = wy1, wz = wz1,
  }
  S.pulsed = nil
  -- the destination chip's own pop still runs (popScale watches the
  -- index); this is the travel between them, plus a small glass kick
  -- if the panels are objects in the arena this frame
  local FX = lazy("BattleGlassFX")
  if FX and FX.ENABLED and FX.pulse and wx1 then
    pcall(FX.pulse, wx1, wy1, wz1, BattleNav.PULSE_AMP)
    S.pulsed = at
  end
end

local function beep(battle)
  local data = (battle and battle.data) or (game() and game().data)
  if not data then return end
  pcall(function()
    require("src.core.Sound").play(data, "Press_AB")
  end)
end

local function hold(kind, index)
  S.held = { kind = kind, index = index }
end

-- ------- which screen owns the dpad this frame
local function partyLive()
  if not S.live then return nil end
  local g = game()
  local top = g and g.stack and g.stack:top()
  if not partyShape(top) then return nil end
  -- the SWITCH/STATS pills are a vertical list; leave UP/DOWN to the engine
  if top.submenu then return nil end
  local Scr = lazy("BattleScreenXY")
  if not (Scr and Scr.ENABLED) then return nil end
  if Scr.available and not Scr.available() then return nil end
  return top
end

function BattleNav.wants()
  local party = partyLive()
  if party then return "party", party end
  if not S.live then return nil end
  local battle = S.battle
  if type(battle) ~= "table" then return nil end
  local Box = lazy("BattleBoxXY")
  if battle.phase == "menu" then
    -- safari uses the same phase/menuIndex 2x2 assignment; if Box
    -- covers the menu, pin writes menuIndex and that is enough
    if Box and Box.covers and Box.covers(battle) then
      return "menu", battle
    end
    return nil
  end
  if battle.phase == "moveSelect" then
    local Fan = lazy("BattleFanXY")
    if Fan and Fan.ENABLED and Box and Box.covers and Box.covers(battle) then
      return "move", battle
    end
  end
  return nil
end

function BattleNav.step(dir)
  local kind, obj = BattleNav.wants()
  if not (kind and obj and dir) then return false end
  if kind == "menu" then
    local from = tonumber(obj.menuIndex) or 1
    local to = BattleNav.commandNext(from, dir)
    if to == from then return false end
    obj.menuIndex = to
    hold("menu", to)
    recordHop("menu", from, to, obj)
    beep(obj)
    return true
  elseif kind == "move" then
    local moves = (obj.player and obj.player.curMoves) or {}
    local n = #moves
    if n <= 0 then return false end
    local from = math.max(1, math.min(tonumber(obj.moveIndex) or 1, n))
    local disabled = obj.player and obj.player.disabledSlot
    local to = BattleNav.moveNext(from, dir, n, disabled)
    if to == from then return false end
    obj.moveIndex = to
    hold("move", to)
    recordHop("move", from, to, obj)
    beep(obj)
    return true
  elseif kind == "party" then
    local g = game()
    local party = obj.party or (g and g.save and g.save.party) or {}
    local n = #party
    if n <= 0 then return false end
    local from = math.max(1, math.min(tonumber(obj.index) or 1, n))
    local to = BattleNav.partyNext(from, dir, n)
    if to == from then return false end
    obj.index = to
    hold("party", to)
    recordHop("party", from, to, S.battle)
    beep(S.battle)
    return true
  end
  return false
end

-- Write S.held back onto the live object. BattleState always reassigns
-- menuIndex from the col/row it captured BEFORE wasPressed (where we
-- already wrote the costume index), so without this the highlight and
-- A stay on FIGHT. Same assignment on the safari 2x2. Move select is
-- pinned so WideBattle.navigate cannot clobber a swallowed step.
function BattleNav.pin()
  local held = S.held
  if not held then return false end
  local kind, obj = BattleNav.wants()
  if not (kind and obj) or kind ~= held.kind then
    S.held = nil
    return false
  end
  local i = held.index
  if kind == "menu" then
    obj.menuIndex = i
  elseif kind == "move" then
    obj.moveIndex = i
  elseif kind == "party" then
    obj.index = i
  else
    return false
  end
  return true
end

-- OverworldBattle calls this so the wrap knows the fight is staged.
-- Passing nil retires the wrap (battle ended / scene broke).
function BattleNav.observe(battle, shot, arena, groundY)
  -- a reliable once-a-frame tick even if Input.step was not wrapped
  BattleNav.beginFrame()
  if not battle then
    S.live, S.battle, S.shot, S.arena = false, nil, nil, nil
    S.held = nil
    return
  end
  S.battle = battle
  S.shot = shot
  S.arena = arena
  S.groundY = groundY or 0
  S.live = true
  BattleNav.pin()
end

function BattleNav.beginFrame()
  S.frame = (S.frame or 0) + 1
end

-- 4-point star, the landing spark (not a laser bloom)
local function star4(g, cx, cy, r)
  local inner = r * 0.30
  local pts = {}
  for i = 0, 3 do
    local a = -math.pi / 2 + i * math.pi / 2
    pts[#pts + 1] = cx + math.cos(a) * r
    pts[#pts + 1] = cy + math.sin(a) * r
    local b = a + math.pi / 4
    pts[#pts + 1] = cx + math.cos(b) * inner
    pts[#pts + 1] = cy + math.sin(b) * inner
  end
  g.polygon("fill", unpack(pts))
end

-- Poke Ball at the origin, already transformed (rotate + squash)
local function drawBall(g, fade, buttonTint)
  local R = BattleNav.BALL_R
  -- clip the belt to the disc so the equator does not square off
  local stMode, stValue = nil, nil
  pcall(function()
    stMode, stValue = g.getStencilTest()
  end)
  local function disc()
    g.circle("fill", 0, 0, R)
  end
  g.stencil(disc, "replace", 1)
  g.setStencilTest("greater", 0)

  g.setColor(1, 1, 1, fade)
  g.circle("fill", 0, 0, R)

  -- top hemisphere: Love2D y-down, ccw from +x, so pi..2pi is screen-up
  g.setColor(0.90, 0.18, 0.18, fade)
  g.arc("fill", 0, 0, R, math.pi, math.pi * 2)

  -- black belt
  g.setColor(0.08, 0.08, 0.10, fade)
  local belt = R * 0.20
  g.rectangle("fill", -R, -belt * 0.5, R * 2, belt)

  if stMode then
    g.setStencilTest(stMode, stValue)
  else
    g.setStencilTest()
  end

  -- outline
  g.setLineWidth(1.4)
  g.setColor(0.06, 0.06, 0.08, fade)
  g.circle("line", 0, 0, R)

  -- center button: black ring, white disc, inner ring
  local br = R * 0.34
  g.setColor(0.07, 0.07, 0.09, fade)
  g.circle("fill", 0, 0, br)
  local wr = R * 0.20
  local cr, cg, cb = 1, 1, 1
  if buttonTint then
    cr = 0.78 + 0.22 * (buttonTint[1] or 1)
    cg = 0.78 + 0.22 * (buttonTint[2] or 1)
    cb = 0.78 + 0.22 * (buttonTint[3] or 1)
  end
  g.setColor(cr, cg, cb, fade)
  g.circle("fill", 0, 0, wr)
  g.setLineWidth(1.15)
  g.setColor(0.10, 0.10, 0.12, fade)
  g.circle("line", 0, 0, wr)

  -- tiny highlight on the red cap
  g.setColor(1, 1, 1, 0.28 * fade)
  g.circle("fill", -R * 0.32, -R * 0.42, R * 0.16)
end

local function hopArt(name)
  local B = lazy("BattleBoxXY")
  if not (B and B._art) then return nil end
  local img = B._art(name)
  if img then pcall(img.setFilter, img, "nearest", "nearest") end
  return img
end

-- ------- the hop, drawn on shot.canvas after the HUDs
function BattleNav.draw(shot)
  local hop = BattleNav.hop
  if not hop then return end
  local t = now() - (hop.at or 0)
  if t >= BattleNav.HOP_TIME or t < 0 then
    BattleNav.hop = nil
    return
  end
  local p = t / BattleNav.HOP_TIME
  -- ease-out along the ground line (x and the un-lifted y)
  local u = 1 - (1 - p) * (1 - p) * (1 - p)

  local dbg = centresOf(hop.kind)
  local x0, y0 = hop.x0, hop.y0
  local x1, y1 = hop.x1, hop.y1
  local lx, ly = xyOf(dbg, hop.from)
  local rx, ry, wx, wy, wz = xyOf(dbg, hop.to)
  if lx then x0, y0 = lx, ly end
  if rx then x1, y1 = rx, ry end
  if wx then hop.wx, hop.wy, hop.wz = wx, wy, wz end
  if not (x0 and y0 and x1 and y1) then return end

  -- a late pulse if the centres only landed after the hop was recorded
  -- (first cursor move of a phase, before debug() has chips)
  if not S.pulsed and hop.wx then
    local FX = lazy("BattleGlassFX")
    if FX and FX.ENABLED and FX.pulse then
      pcall(FX.pulse, hop.wx, hop.wy, hop.wz, BattleNav.PULSE_AMP)
      S.pulsed = hop.at
    end
  end

  local gx = x0 + (x1 - x0) * u
  local gy = y0 + (y1 - y0) * u
  local dist = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0))
  local hopH = math.max(16, math.min(BattleNav.HOP_HEIGHT + 8,
                                     (BattleNav.HOP_HEIGHT) * 0.55 + dist * 0.28))
  local lift = math.sin(math.pi * u) * hopH
  local x, y = gx, gy - lift

  -- squash on takeoff and landing; a hint of stretch at the apex
  local air = math.sin(math.pi * u)
  local scaleY = 0.70 + 0.38 * air
  local scaleX = 1.26 - 0.30 * air
  -- a little tumble in the direction of travel, biggest in the air
  local dx = x1 - x0
  local rot = air * 0.72 * ((dx >= 0) and 1 or -1)

  local g = love.graphics
  local prev, prevA = g.getBlendMode()

  -- tiny shadow on the ground line, shrinking while airborne
  local sh = 1 - 0.50 * air
  g.setBlendMode("alpha")
  g.setColor(0.05, 0.05, 0.08, 0.30 * sh)
  g.ellipse("fill", gx, gy + BattleNav.BALL_R * 0.55,
            BattleNav.BALL_R * 0.92 * sh, BattleNav.BALL_R * 0.28 * sh)

  g.push()
  g.translate(x, y)
  g.rotate(rot)
  g.scale(scaleX, scaleY)
  -- move-type tint only on the button spark, and only near landing
  local buttonTint = nil
  if hop.kind == "move" and hop.color and u > 0.85 then
    buttonTint = hop.color
  end
  local ballImg = hopArt("items/POKE_BALL")
  local usedSprite = false
  if ballImg then
    usedSprite = pcall(function()
      local iw, ih = ballImg:getDimensions()
      local s = (BattleNav.BALL_R * 2) / math.max(1, ih)
      g.setColor(1, 1, 1, 1)
      g.draw(ballImg, 0, 0, 0, s, s, iw * 0.5, ih * 0.5)
      if buttonTint then
        local bmode, balpha = g.getBlendMode()
        g.setBlendMode("add")
        g.setColor(buttonTint[1], buttonTint[2], buttonTint[3], 0.32)
        g.draw(ballImg, 0, 0, 0, s, s, iw * 0.5, ih * 0.5)
        if balpha ~= nil then
          g.setBlendMode(bmode or "alpha", balpha)
        else
          g.setBlendMode(bmode or "alpha")
        end
      end
    end)
  end
  if not usedSprite then
    drawBall(g, 1, buttonTint)
  end
  g.pop()

  -- landing spark: 4-point star, ~1-2 frames via the u>0.85 window
  if u > 0.85 then
    local spark = math.sin((u - 0.85) / 0.15 * math.pi)
    local sr, sg, sb = 1, 1, 1
    if hop.kind == "move" and hop.color then
      sr = 0.70 + 0.30 * hop.color[1]
      sg = 0.70 + 0.30 * hop.color[2]
      sb = 0.70 + 0.30 * hop.color[3]
    end
    g.setBlendMode("add")
    local drew = false
    local okBlit = pcall(function()
      local star = hopArt("fx/9_pointed_star")
      local sp1 = hopArt("fx/bishie_sparkle_1")
      local sp2 = hopArt("fx/bishie_sparkle_2")
      local function blit(img, size, a)
        if not img then return false end
        local iw, ih = img:getDimensions()
        local sc = size / math.max(1, ih)
        g.setColor(sr, sg, sb, a)
        g.draw(img, x1, y1, 0, sc, sc, iw * 0.5, ih * 0.5)
        return true
      end
      drew = blit(star, 12 + 7 * spark, 0.90 * spark)
      blit(sp1, 9 + 5 * spark, 0.70 * spark)
      blit(sp2, 7 + 4 * spark, 0.55 * spark)
    end)
    if not (okBlit and drew) then
      g.setColor(sr, sg, sb, 0.85 * spark)
      star4(g, x1, y1, 5.5 + 3.5 * spark)
      g.setColor(1, 1, 1, 0.70 * spark)
      star4(g, x1, y1, 2.4 + 1.2 * spark)
    end
  end

  if prevA ~= nil then
    g.setBlendMode(prev or "alpha", prevA)
  else
    g.setBlendMode(prev or "alpha")
  end
  g.setLineWidth(1)
  g.setColor(1, 1, 1, 1)
end

function BattleNav.debug()
  return {
    live = S.live,
    phase = S.battle and S.battle.phase,
    frame = S.frame,
    held = S.held and {
      kind = S.held.kind,
      index = S.held.index,
    } or nil,
    hop = BattleNav.hop and {
      kind = BattleNav.hop.kind,
      from = BattleNav.hop.from,
      to = BattleNav.hop.to,
    } or nil,
    wants = (BattleNav.wants()),
  }
end

-- ------- Input:wasPressed wrap (installed from main.lua)
function BattleNav.install()
  if S.installed then return true end
  local okI, Input = pcall(require, "src.core.Input")
  if not (okI and Input and Input.wasPressed) then return false end

  local inner = Input.wasPressed
  function Input:wasPressed(btn)
    if not DIRS[btn] then
      return inner(self, btn)
    end
    if not BattleNav.wants() then
      return inner(self, btn)
    end
    -- first direction query this input-frame: drain every direction
    -- through the inner so the engine cannot also step, then apply at
    -- most one visual move
    if S.drainFrame ~= S.frame then
      S.drainFrame = S.frame
      local hit
      for i = 1, #DIR_ORDER do
        local d = DIR_ORDER[i]
        if inner(self, d) then
          hit = hit or d
        end
      end
      if hit then BattleNav.step(hit) end
    end
    return false
  end

  if Input.step then
    local innerStep = Input.step
    function Input:step(...)
      BattleNav.beginFrame()
      return innerStep(self, ...)
    end
  end

  local hooks = V.mod and V.mod.hooks
  if hooks and hooks.wrap then
    pcall(function()
      hooks:wrap("input.step", function(next, game, dt)
        BattleNav.beginFrame()
        return next(game, dt)
      end)
    end)
  end

  S.installed = true
  return true
end

return BattleNav
