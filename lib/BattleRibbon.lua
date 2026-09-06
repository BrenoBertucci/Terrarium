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
BattleRibbon.SIZE = 3.3          -- world width at rest
BattleRibbon.CREST_GROW = 1.6    -- extra width at the crest
BattleRibbon.REST_P = 0.13       -- arc param each medallion rests at
BattleRibbon.REST_E = 0.87
BattleRibbon.CREST = 0.5
BattleRibbon.GLIDE_K = 8         -- per-second pursuit along the arc
BattleRibbon.FACE = 176          -- face canvas, px (room for crown + halo)

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
-- A coin of smoked glass, not a ring around an icon. The face carries:
--   the DISC   -- charcoal glass with a cap of light and a gloss band,
--                 over a soft drop shadow;
--   the RIM    -- the mon's own TYPE colour as a thick ring, so the two
--                 coins are told apart across the arena; gold and haloed
--                 for the real turn, pale for a forecast;
--   the SPRITE -- the mon pack's art (MonPack.drawIcon), larger than the
--                 disc's middle so it reads as a portrait, the engine's
--                 two-bit party icon only when the pack has none;
--   the CROWN  -- a small gold crown over the crest owner's coin while
--                 a move is really being thrown; a pale chevron while
--                 the crest is only a forecast;
--   the BADGE  -- the round's order, "1" on the crest owner and "2" on
--                 the other, stamped bottom-right in the Unova font.
local function typeColorOf(battle, mon)
  local okB, B = pcall(V.require, "BattleBoxXY")
  if not (okB and B and B.TYPE_COLOR) then return { 0.62, 0.67, 0.78 } end
  local data = battle and battle.data
  local def = data and data.pokemon and mon and data.pokemon[mon.species]
  local t = def and def.types and def.types[1]
  local tname = t and B.typeName and B.typeName(t) or t
  return (tname and B.TYPE_COLOR[tname]) or B.TYPE_FALLBACK or { 0.62, 0.67, 0.78 }
end

local function crown(g, cx, top, w, color)
  local h = w * 0.62
  local x0, x1 = cx - w * 0.5, cx + w * 0.5
  g.setColor(0.25, 0.15, 0.02, 0.9)
  g.setLineWidth(3)
  g.polygon("line", x0, top + h, x0, top + h * 0.25, cx - w * 0.25, top + h * 0.62,
            cx, top, cx + w * 0.25, top + h * 0.62, x1, top + h * 0.25, x1, top + h)
  g.setLineWidth(1)
  g.setColor(color[1], color[2], color[3], 1)
  g.polygon("fill", x0, top + h, x0, top + h * 0.25, cx - w * 0.25, top + h * 0.62,
            cx, top, cx + w * 0.25, top + h * 0.62, x1, top + h * 0.25, x1, top + h)
  -- three jewels
  g.setColor(0.95, 0.25, 0.3, 1)
  g.circle("fill", cx, top + h * 0.5, w * 0.07)
  g.setColor(0.35, 0.6, 1.0, 1)
  g.circle("fill", cx - w * 0.28, top + h * 0.7, w * 0.05)
  g.circle("fill", cx + w * 0.28, top + h * 0.7, w * 0.05)
  g.setColor(1, 1, 1, 0.9)
  g.rectangle("fill", x0 + 2, top + h - 4, w - 4, 2)
end

local function drawFace(slot, battle, mon, golden, atCrest, order)
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
    local cy = W / 2 + 4                      -- room for the crown above
    local r = W / 2 - 22
    local tcol = typeColorOf(battle, mon)
    local GOLD = BattleRibbon.GOLD
    local PALE = BattleRibbon.PALE

    -- the shadow: soft, offset down-right
    for i = 4, 1, -1 do
      g.setColor(0, 0, 0, 0.09)
      g.circle("fill", cx + 3, cy + 5, r + i * 2)
    end
    -- the halo behind a crest coin
    if atCrest then
      local hc = golden and GOLD or PALE
      for i = 5, 1, -1 do
        g.setColor(hc[1], hc[2], hc[3], (golden and 0.10 or 0.06))
        g.circle("fill", cx, cy, r + 4 + i * 3)
      end
    end
    -- the disc: charcoal glass, a cap of light, a gloss band
    g.setColor(0.08, 0.09, 0.12, 0.88)
    g.circle("fill", cx, cy, r)
    g.setColor(tcol[1], tcol[2], tcol[3], 0.16)
    g.circle("fill", cx, cy, r)
    -- (no stencil: a plain canvas carries none in this LOVE, and a
    -- throw here would take the whole ribbon down -- the shapes are kept
    -- inside the disc by size instead)
    g.setColor(1, 1, 1, 0.13)
    g.ellipse("fill", cx - r * 0.22, cy - r * 0.42, r * 0.62, r * 0.36)
    g.setColor(0, 0, 0, 0.22)
    g.ellipse("fill", cx, cy + r * 0.66, r * 0.72, r * 0.26)
    -- the sprite: the pack's art, a portrait bigger than the middle
    local drew = false
    do
      local okMP, MonPack = pcall(V.require, "MonPack")
      if okMP and MonPack and MonPack.drawIcon then
        local box = r * 1.42
        g.setColor(1, 1, 1, 1)
        local okD, d = pcall(MonPack.drawIcon, mon and mon.species,
                             cx - box * 0.5, cy - box * 0.5 - r * 0.02, box)
        drew = okD and d or false
      end
    end
    local okPM, PartyMenu = pcall(require, "src.ui.PartyMenu")
    if not drew and okPM and PartyMenu and PartyMenu.drawIcon and battle.game then
      local s = (r * 1.5) / 16
      g.setColor(1, 1, 1, 1)
      g.push()
      g.translate(cx - 8 * s, cy - 8 * s)
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
        C.text(initial, cx - tw / 2, cy - 4.5 * kk, kk)
      end
    end
    -- the rim: the type's colour, gold over it for the real turn
    g.setColor(0, 0, 0, 0.55)
    g.setLineWidth(9)
    g.circle("line", cx, cy, r + 1)
    if atCrest and golden then
      g.setColor(GOLD[1], GOLD[2], GOLD[3], 0.35)
      g.setLineWidth(16)
      g.circle("line", cx, cy, r + 2)
      g.setColor(GOLD[1], GOLD[2], GOLD[3], 1)
      g.setLineWidth(6)
      g.circle("line", cx, cy, r + 1)
      g.setColor(1, 0.96, 0.8, 0.9)
      g.setLineWidth(1.5)
      g.circle("line", cx, cy, r - 3)
    else
      g.setColor(tcol[1], tcol[2], tcol[3], 1)
      g.setLineWidth(atCrest and 6 or 5)
      g.circle("line", cx, cy, r + 1)
      local hi = atCrest and PALE or { 1, 1, 1 }
      g.setColor(hi[1], hi[2], hi[3], atCrest and 0.9 or 0.35)
      g.setLineWidth(1.5)
      g.circle("line", cx, cy, r - 3)
    end
    g.setLineWidth(1)
    -- the crown or the chevron
    if atCrest then
      if golden then
        crown(g, cx, cy - r - 22, r * 0.9, GOLD)
      else
        g.setColor(PALE[1], PALE[2], PALE[3], 0.95)
        g.setLineWidth(4)
        g.line(cx - r * 0.3, cy - r - 8, cx, cy - r - 18, cx + r * 0.3, cy - r - 8)
        g.setLineWidth(1)
      end
    end
    -- the order badge
    if order then
      local bx, by, br = cx + r * 0.72, cy + r * 0.72, r * 0.3
      local first = order == 1
      g.setColor(0, 0, 0, 0.6)
      g.circle("fill", bx + 1, by + 2, br + 1)
      if first then g.setColor(GOLD[1], GOLD[2], GOLD[3], 1)
      else g.setColor(0.35, 0.37, 0.42, 1) end
      g.circle("fill", bx, by, br)
      g.setColor(1, 1, 1, 0.8)
      g.setLineWidth(1.5)
      g.circle("line", bx, by, br)
      g.setLineWidth(1)
      local C = capsule()
      local label = tostring(order)
      if C then
        local kk = (br * 1.25) / 9
        local tw = C.textWidth(label) * kk
        g.setColor(first and 0.25 or 0.05, first and 0.15 or 0.05, 0.02, 1)
        C.text(label, bx - tw / 2, by - 4.5 * kk, kk)
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

local function now()
  return (love.timer and love.timer.getTime and love.timer.getTime()) or 0
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
  local t = now()

  local gy = shot.groundY or 0
  local pB = { shot.playerCell[1], gy, shot.playerCell[2] }
  local eB = { shot.enemyCell[1], gy, shot.enemyCell[2] }
  local P0 = F.vadd(pB, R.up, BattleRibbon.P0_UP)
  local P2 = F.vadd(eB, R.up, BattleRibbon.P2_UP)
  local mid = { (pB[1] + eB[1]) / 2, gy, (pB[3] + eB[3]) / 2 }
  local P1 = F.vadd(mid, R.up, BattleRibbon.CREST_UP)

  -- the ribbon: a beam -- wide glow, a core, and light FLOWING along it
  -- toward the crest owner (short bright dashes marching on the arc)
  local pts, cum = {}, { 0 }
  for i = 0, BattleRibbon.SAMPLES do
    local p = bezier(P0, P1, P2, i / BattleRibbon.SAMPLES, F)
    local sx, sy = R.project(p)
    if not sx then return false end
    pts[#pts + 1] = sx
    pts[#pts + 1] = sy
    if i > 0 then
      local dx, dy = sx - pts[#pts - 3], sy - pts[#pts - 2]
      cum[i + 1] = cum[i] + math.sqrt(dx * dx + dy * dy)
    end
  end
  local GOLD = BattleRibbon.GOLD
  local prevBlend, prevA = g.getBlendMode()
  g.setColor(0, 0, 0, 0.25)
  g.setLineWidth(7)
  g.line(pts)
  g.setColor(GOLD[1], GOLD[2], GOLD[3], 0.30)
  g.setLineWidth(11)
  g.line(pts)
  g.setColor(1, 0.97, 0.85, 0.85)
  g.setLineWidth(2.5)
  g.line(pts)
  -- the flow: dashes every 46 px, 18 px long, drifting toward the crest
  -- owner's end (the player sits at t=0, the enemy at t=1)
  local total = cum[#cum]
  local dir = (S.crest == "enemy") and 1 or -1
  local phase = (t * 90 * dir) % 46
  pcall(g.setBlendMode, "add", "alphamultiply")
  g.setLineWidth(3.5)
  for i = 1, #cum - 1 do
    local s0, s1 = cum[i], cum[i + 1]
    -- a dash covers [k*46+phase, +18) for integer k
    local d0 = ((s0 - phase) % 46)
    if d0 < 18 or (s1 - s0) > 46 - d0 then
      local a = 0.55
      g.setColor(GOLD[1], GOLD[2] + 0.1, GOLD[3] + 0.3, a)
      g.line(pts[i * 2 - 1], pts[i * 2], pts[i * 2 + 1], pts[i * 2 + 2])
    end
  end
  if prevA ~= nil then pcall(g.setBlendMode, prevBlend, prevA)
  else pcall(g.setBlendMode, prevBlend or "alpha") end
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
      local ord = (S.crest == side) and 1 or 2
      -- the face follows the mon's animation frame (MonPack), so the
      -- coin's portrait moves like the mon on the field
      local frame = 0
      do
        local okMP, MonPack = pcall(V.require, "MonPack")
        if okMP and MonPack and MonPack.frameOf then
          frame = MonPack.frameOf(mon.species, false)
        end
      end
      local key = tostring(mon.species) .. ":"
                  .. (atCrest and (S.golden and "G" or "C") or "-") .. ord
                  .. ":" .. frame
      if slot.key ~= key then
        local okF = pcall(drawFace, slot, battle, mon, S.golden, atCrest, ord)
        if not (okF and slot.canvas) then return false end
        slot.key = key
      end
      local crestness = math.max(0, 1 - math.abs(S.t[side]
                                 - BattleRibbon.CREST) / 0.37)
      local size = BattleRibbon.SIZE + BattleRibbon.CREST_GROW * crestness
      -- the crest coin breathes
      if atCrest then size = size * (1 + 0.03 * math.sin(t * 3.4)) end
      local c = bezier(P0, P1, P2, S.t[side], F)
      -- a coin on the move leaves a trail of ghosts along the arc
      local rest = (side == "player") and BattleRibbon.REST_P or BattleRibbon.REST_E
      local target = (S.crest == side) and BattleRibbon.CREST or rest
      local moving = math.abs(target - S.t[side]) > 0.015
      if moving and slot.canvas then
        local back = (target > S.t[side]) and -1 or 1
        pcall(g.setBlendMode, "add", "alphamultiply")
        for k = 1, 3 do
          local tt = S.t[side] + back * k * 0.035
          if tt > 0 and tt < 1 then
            local gc = bezier(P0, P1, P2, tt, F)
            local gm = F.hang(slot, shot, gc, R.right, R.up, size * (1 - k * 0.08), size * (1 - k * 0.08))
            if gm then
              g.setColor(GOLD[1], GOLD[2], GOLD[3], 0.35 - k * 0.09)
              g.draw(gm)
            end
          end
        end
        if prevA ~= nil then pcall(g.setBlendMode, prevBlend, prevA)
        else pcall(g.setBlendMode, prevBlend or "alpha") end
      end
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
