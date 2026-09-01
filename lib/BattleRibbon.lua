-- The turn ribbon: concept 04, the honest half.
--
-- Generation 1 has no timeline to show -- order is decided per round by
-- Speed, and re-decided every round -- so this ribbon never claims one.
-- What it shows is real either way: BETWEEN rounds, the mon predicted to
-- act first (the faster one, the game's own rule) sits at the arc's
-- crest under a pale ring; WHILE a move is playing, whoever is actually
-- throwing it slides up to the crest and the ring turns gold. The
-- medallions GLIDE along the arc when the turn passes -- pursued, never
-- teleported, the costume's house style.
--
-- The arc is a quadratic bezier strung IN THE WORLD between the two
-- mons' cells, above their capsules, so it swings with the drift and the
-- attack camera like everything else. Medallions are party icons -- the
-- engine's own mini sprites, front-facing for both sides -- on small
-- glass discs, hung as billboards through the shared rig, bobbing and
-- taking the impact wave through BattleGlassFX like every other pane.
--
-- The concept's OTHER half, the parry-timing ring, is deliberately not
-- here: it would touch damage resolution, and this costume's law is that
-- nothing presentational reaches the rules.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local BattleRibbon = {}

BattleRibbon.ENABLED = true

-- ------- the arc, in world offsets from each mon's cell
--
-- BELOW the capsules, through the open middle of the frame: the first
-- cut hung it above them, which projected the whole ribbon past the top
-- edge of the window -- six passing measurements and nothing on screen,
-- which is why the probe now checks visibility too.
BattleRibbon.P0_UP = 8.8         -- just over the player mon's head
BattleRibbon.P2_UP = 5.8         -- over the enemy's brow
BattleRibbon.CREST_UP = 10.5     -- the control point's lift, above the mid
BattleRibbon.SAMPLES = 24

-- medallions
BattleRibbon.SIZE = 2.9          -- world width at rest
BattleRibbon.CREST_GROW = 0.9    -- extra width at the crest
BattleRibbon.REST_P = 0.13       -- arc param each medallion rests at
BattleRibbon.REST_E = 0.87
BattleRibbon.CREST = 0.5
BattleRibbon.GLIDE_K = 8         -- per-second pursuit along the arc
BattleRibbon.FACE = 132          -- face canvas, px

BattleRibbon.GOLD = { 1.0, 0.84, 0.40 }
BattleRibbon.PALE = { 0.92, 0.95, 1.0 }

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

local Cap = nil
local function capsule()
  if Cap == nil then
    local ok, C = pcall(V.require, "BattleCapsule")
    Cap = (ok and C) or false
  end
  return (Cap and Cap.available and Cap.available()) and Cap or nil
end

-- ------- state
local S = {
  t = { player = BattleRibbon.REST_P, enemy = BattleRibbon.REST_E },
  crest = nil,          -- who owns the crest this frame
  golden = false,       -- true while it is the REAL turn, not a forecast
  slots = { player = {}, enemy = {} },
  lastT = nil,
  last = nil,           -- what a probe measures
}

function BattleRibbon.debug()
  return S.last
end

-- ------- watching the fight (called from OverworldBattle.update)
function BattleRibbon.observe(battle, dt)
  if not (BattleRibbon.ENABLED and battle) then return end
  dt = dt or 0

  -- who owns the crest: the actual attacker while a move plays, the
  -- faster mon's forecast otherwise (Speed is the game's own tiebreak;
  -- on a dead tie the player takes the spot -- a coin the game flips
  -- per round and a forecast cannot honestly call)
  if battle.animPlaying and battle.animAttackerIsPlayer ~= nil then
    S.crest = battle.animAttackerIsPlayer and "player" or "enemy"
    S.golden = true
  else
    local ps = battle.player and battle.player.curStats
               and battle.player.curStats.speed or 0
    local es = battle.enemy and battle.enemy.curStats
               and battle.enemy.curStats.speed or 0
    S.crest = (es > ps) and "enemy" or "player"
    S.golden = false
  end

  local a = 1 - math.exp(-BattleRibbon.GLIDE_K * dt)
  for _, side in ipairs({ "player", "enemy" }) do
    local rest = (side == "player") and BattleRibbon.REST_P
                                     or BattleRibbon.REST_E
    local target = (S.crest == side) and BattleRibbon.CREST or rest
    S.t[side] = S.t[side] + (target - S.t[side]) * a
  end
end

-- ------- the medallion's face: a glass disc wearing the party icon
--
-- Drawn by the ENGINE's own PartyMenu.drawIcon under a scaled transform:
-- its icon resolution is a chain of registries, an OBP0 palette bake and
-- an OAM-mirroring quirk (its #276), and re-implementing any of that
-- here would be a second copy waiting to drift. A species it cannot draw
-- wears its initial in the Unova font instead.

local function drawFace(slot, battle, mon, golden, atCrest)
  local g = love.graphics
  local W = BattleRibbon.FACE
  if not slot.canvas then
    local ok, c = pcall(g.newCanvas, W, W, { dpiscale = 1 })
    if not (ok and c) then return false end
    slot.canvas = c
  end
  local prevCanvas = g.getCanvas()
  local prevBlend, prevAlpha = g.getBlendMode()
  local ok, err = pcall(function()
    g.setCanvas(slot.canvas)
    g.clear(0, 0, 0, 0)
    g.setBlendMode("alpha")
    local cx = W / 2
    local r = W / 2 - 10
    -- the disc: dark base for contrast, pale glass over it
    g.setColor(0.08, 0.09, 0.12, 0.72)
    g.circle("fill", cx, cx, r)
    g.setColor(0.80, 0.85, 0.94, 0.22)
    g.circle("fill", cx, cx, r)
    -- the ring: gold and haloed for the real turn, pale for a forecast,
    -- thin for a medallion waiting at its own end of the arc
    if atCrest and golden then
      local GOLD = BattleRibbon.GOLD
      g.setColor(GOLD[1], GOLD[2], GOLD[3], 0.30)
      g.setLineWidth(12)
      g.circle("line", cx, cx, r)
      g.setColor(GOLD[1], GOLD[2], GOLD[3], 0.95)
      g.setLineWidth(5)
    elseif atCrest then
      local P = BattleRibbon.PALE
      g.setColor(P[1], P[2], P[3], 0.9)
      g.setLineWidth(4)
    else
      g.setColor(0.62, 0.67, 0.78, 0.7)
      g.setLineWidth(3)
    end
    g.circle("line", cx, cx, r)
    g.setLineWidth(1)

    local drew = false
    local okPM, PartyMenu = pcall(require, "src.ui.PartyMenu")
    if okPM and PartyMenu and PartyMenu.drawIcon and battle.game then
      local s = (W - 44) / 16
      g.setColor(1, 1, 1, 1)
      g.push()
      g.translate(cx - 8 * s, cx - 8 * s)
      g.scale(s, s)
      drew = pcall(PartyMenu.drawIcon, battle.game, mon, 0, 0, false, 0)
      g.pop()
    end
    if not drew then
      local C = capsule()
      local initial = tostring(mon and mon.species or "?"):sub(1, 1)
      if C then
        local kk = 7
        local tw = C.textWidth(initial) * kk
        g.setColor(1, 1, 1, 1)
        C.text(initial, cx - tw / 2, cx - 4.5 * kk, kk)
      end
    end
  end)
  if prevCanvas then g.setCanvas(prevCanvas) else g.setCanvas() end
  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  g.setColor(1, 1, 1, 1)
  if not ok then error(err, 0) end
  return true
end

-- ------- the draw (called from snapHUDs, canvas already bound)
local function bezier(P0, P1, P2, t, F)
  local u = 1 - t
  local a, b, c = u * u, 2 * u * t, t * t
  return { a * P0[1] + b * P1[1] + c * P2[1],
           a * P0[2] + b * P1[2] + c * P2[2],
           a * P0[3] + b * P1[3] + c * P2[3] }
end

function BattleRibbon.draw(battle, shot)
  if not (BattleRibbon.ENABLED and battle and shot
          and shot.playerCell and shot.enemyCell) then
    return false
  end
  local F = fan()
  if not F then return false end
  local R = F.rig(shot)
  if not R then return false end
  local g = love.graphics

  local gy = shot.groundY or 0
  local pB = { shot.playerCell[1], gy, shot.playerCell[2] }
  local eB = { shot.enemyCell[1], gy, shot.enemyCell[2] }
  local P0 = F.vadd(pB, R.up, BattleRibbon.P0_UP)
  local P2 = F.vadd(eB, R.up, BattleRibbon.P2_UP)
  local mid = { (pB[1] + eB[1]) / 2, gy, (pB[3] + eB[3]) / 2 }
  local P1 = F.vadd(mid, R.up, BattleRibbon.CREST_UP)

  -- the ribbon itself: a luminous polyline, glow under core
  local pts = {}
  for i = 0, BattleRibbon.SAMPLES do
    local p = bezier(P0, P1, P2, i / BattleRibbon.SAMPLES, F)
    local sx, sy = R.project(p)
    if not sx then return false end
    pts[#pts + 1] = sx
    pts[#pts + 1] = sy
  end
  local GOLD = BattleRibbon.GOLD
  g.setColor(GOLD[1], GOLD[2], GOLD[3], 0.32)
  g.setLineWidth(9)
  g.line(pts)
  g.setColor(1, 1, 1, 0.75)
  g.setLineWidth(2.5)
  g.line(pts)
  g.setLineWidth(1)

  -- the medallions: waiting one first, crest one on top
  local FX = glassFX()
  local order = (S.crest == "player") and { "enemy", "player" }
                                       or { "player", "enemy" }
  local dbg = { crest = S.crest, golden = S.golden,
                t = { player = S.t.player, enemy = S.t.enemy } }
  for _, side in ipairs(order) do
    local b = battle[side]
    local mon = b and b.mon
    if mon then
      local slot = S.slots[side]
      local atCrest = math.abs(S.t[side] - BattleRibbon.CREST) < 0.12
      local key = tostring(mon.species) .. ":"
                  .. (atCrest and (S.golden and "G" or "C") or "-")
      if slot.key ~= key then
        local okF = pcall(drawFace, slot, battle, mon, S.golden, atCrest)
        if not (okF and slot.canvas) then return false end
        slot.key = key
      end
      local crestness = math.max(0, 1 - math.abs(S.t[side]
                                 - BattleRibbon.CREST) / 0.37)
      local size = BattleRibbon.SIZE + BattleRibbon.CREST_GROW * crestness
      local c = bezier(P0, P1, P2, S.t[side], F)
      if FX then
        local okJ, jR, jU = pcall(FX.jolt, "rib:" .. side, c, R)
        if okJ and jR then
          c = F.vadd(F.vadd(c, R.right, jR), R.up, jU)
        end
      end
      local mesh = F.hang(slot, shot, c, R.right, R.up, size, size)
      if not mesh then return false end
      g.setColor(1, 1, 1, 1)
      g.draw(mesh)
      local sx, sy = R.project(c)
      dbg[side] = sx and { sx, sy } or nil
      -- visible, not merely projectable: valid coordinates past the
      -- window's edge are how the first cut passed six checks unseen
      dbg.on = dbg.on or {}
      dbg.on[side] = (sx and sx > 20 and sx < shot.pw - 20
                      and sy > 20 and sy < shot.ph - 20) and true or false
    end
  end
  S.last = dbg
  return true
end

return BattleRibbon
