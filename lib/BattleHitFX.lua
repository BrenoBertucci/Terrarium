-- Attacks as events in the arena, not as GB pictures on a billboard.
--
-- The engine still plays its own pic anims; this module never touches
-- them. What it does is watch the same read-only seams the attack camera
-- and the glass already watch -- animPlaying, fx.flash, fx.shake, the
-- bar starting to drain -- and, when a move is thrown or a hit lands,
-- put something IN THE SHOT at the cell it belongs to: a typed CHARGE
-- sheet at the attacker when the move begins, a typed HIT sheet at the
-- defender when it connects, a projectile streak across the arena while
-- the anim plays, and a typed dent in the grass around the defender only.
-- The glass already drops a shockwave on the hit and a telegraph wave
-- when the move starts; this is the matching picture, and the matching
-- dent.
--
-- Type comes from the engine's own lookup (data.moves[animName] through
-- BattleBoxXY.typeName), the same reading the weather uses. FIRE skips
-- the grass -- embers are already falling on the pane. Everything else
-- flattens a disc around the defender, sized for the blow.
--
-- Drawn onto shot.canvas after the 3D pass and before the frost, so the
-- glass includes the flash and the HUD / fan still sit on top. The
-- IMPACT options row is left alone: battle plays force their way past
-- it, tagged so a finish can sweep them without wiping an overworld
-- demo that happens to be live.
--
-- Purely presentational, like everything else here. Nothing reaches
-- damage, timing or scripts; a confused effect is a battle with the
-- engine's own anims and nothing on the canvas.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Vfx = V.require("Vfx")

local BattleHitFX = {}

BattleHitFX.ENABLED = true

-- Authored bt_* sheets (tools/make_battle_sprites.py), not the eight OGA
-- explosions. Charge and hit are different events -- never the same play
-- at two scales of one blob. Tints come from BattleBoxXY.TYPE_COLOR.
BattleHitFX.TYPE_FX = {
  NORMAL   = { charge = "bt_slash",  hit = "bt_slash"  },
  FIGHTING = { charge = "bt_fist",   hit = "bt_fist"   },
  FLYING   = { charge = "bt_charge", hit = "bt_slash"  },
  POISON   = { charge = "bt_wisp",   hit = "bt_wisp"   },
  GROUND   = { charge = "bt_charge", hit = "bt_burst"  },
  ROCK     = { charge = "bt_charge", hit = "bt_shards" },
  BUG      = { charge = "bt_leaves", hit = "bt_leaves" },
  GHOST    = { charge = "bt_wisp",   hit = "bt_spiral" },
  FIRE     = { charge = "bt_charge", hit = "bt_burst"  },
  WATER    = { charge = "bt_spray",  hit = "bt_spray"  },
  GRASS    = { charge = "bt_leaves", hit = "bt_leaves" },
  ELECTRIC = { charge = "bt_charge", hit = "bt_bolt"   },
  PSYCHIC  = { charge = "bt_spiral", hit = "bt_spiral" },
  ICE      = { charge = "bt_charge", hit = "bt_shards" },
  DRAGON   = { charge = "bt_beam",   hit = "bt_beam"   },
}

local Box = nil
local function box()
  if Box == nil then
    local ok, B = pcall(V.require, "BattleBoxXY")
    Box = (ok and B) or false
  end
  return Box or nil
end

local Grass = nil
local function grass()
  if Grass == nil then
    local ok, G = pcall(V.require, "Grass3D")
    Grass = (ok and G) or false
  end
  return Grass or nil
end

local Glass = nil
local function glass()
  if Glass == nil then
    local ok, G = pcall(V.require, "BattleGlassFX")
    Glass = (ok and G) or false
  end
  return Glass or nil
end

-- ------- state
local S = {
  prev = {},
  playing = false,
  lastKey = nil,
  lastSide = nil,
  tname = nil,
  def = nil,
  attackerIsPlayer = false,
  chargeKey = nil,
  hitKey = nil,
  tint = nil,
  fromCell = nil,
  toCell = nil,
  groundY = 0,
  born = 0,
  midPulsed = false,
  sparkAt = nil,
  -- the arena answering the blow (see the section below)
  spot = nil,        -- { born, untilT, cell } -- the spotlight on the attacker
  light = nil,       -- { born, cell, tint, big } -- the flash at the defender
  debris = {},       -- voxel cubes kicked off the floor
  marks = {},        -- what the blow left on the ground
  tags = {},         -- damage numbers in the air
  shown = {},        -- [side] = shownHP last frame, for the damage read
  maxHP = {},        -- [side] = maxHP last frame
}

local function now()
  return (love.timer and love.timer.getTime and love.timer.getTime()) or 0
end

-- ------- the arena answers
--
-- A blow in Clair Obscur is not a sprite on a sprite: the light changes,
-- the ground takes it, something flies. Four presentational systems
-- here, all fed by the same edges observe() already reads:
--
-- THE SPOTLIGHT. While a move plays the frame darkens toward its
-- corners around the ATTACKER -- the eye is dragged to whoever is
-- acting, and the arena looks lit for the moment rather than evenly.
-- THE FLASH. The landed hit lights the DEFENDER's cell in the move's
-- colour: an additive glow that reaches the floor and the far wall for
-- a third of a second, sized to the blow.
-- THE DEBRIS. The floor is voxels; a blow kicks a handful of them off
-- the defender's cell -- cubes that arc, fall, bounce once and settle,
-- tinted by the element. Drawn as projected squares with a darker
-- bottom face, which at this size IS a cube.
-- THE MARK. What stays: a scorch for fire, a puddle for water, frost
-- for ice, a burnt ring for electricity, a crater ring for rock and
-- ground, a scuff of dust for the rest. Drawn INSIDE the 3D pass
-- between the terrain and the mons (BattleScene calls drawGround), so
-- the mark lies UNDER the defender's feet and takes the hour's light
-- and the sun's shadow like any geometry -- an overlay would paint it
-- over the sprite.
-- THE NUMBER. The damage, read off the bar's own drain (shownHP last
-- frame minus hp now, the same tell the wave uses), floats up from the
-- defender's capsule as a gold figure on a sliver of glass, bigger for
-- a bigger share of the bar.
BattleHitFX.SPOT_DARK = 0.52       -- how dark the far corners go
BattleHitFX.SPOT_IN = 0.18         -- seconds to fade the spotlight in
BattleHitFX.SPOT_OUT = 0.30        -- ...and out after the move
BattleHitFX.FLASH_LIFE = 0.36
BattleHitFX.FLASH_REACH = 1.1      -- radius, in mon squares (canvas px)
BattleHitFX.DEBRIS_N = 14
BattleHitFX.DEBRIS_LIFE = 1.6
BattleHitFX.MARK_LIFE = 16.0       -- a scorch outlasts the round it came from
BattleHitFX.MARK_FADE = 4.0        -- the last seconds of MARK_LIFE fade out
BattleHitFX.TAG_LIFE = 1.25
BattleHitFX.TAG_RISE = 0.14        -- of a mon square, over the life
BattleHitFX.TAG_H = 0.10           -- glyph height, of a mon square...
BattleHitFX.TAG_H_BIG = 0.08       -- ...plus this for a hit that takes the bar
BattleHitFX.GOLD = { 1.0, 0.84, 0.40 }

-- what each element leaves on the floor: the brush and its colour.
-- `ring` draws a crater rim rather than a disc; `size` in world px.
BattleHitFX.MARK = {
  FIRE     = { kind = "scorch", size = 34, color = { 0.16, 0.10, 0.08 } },
  ELECTRIC = { kind = "scorch", size = 26, color = { 0.22, 0.18, 0.10 } },
  WATER    = { kind = "puddle", size = 32, color = { 0.42, 0.58, 0.86 } },
  ICE      = { kind = "frost",  size = 34, color = { 0.82, 0.94, 0.98 } },
  ROCK     = { kind = "crater", size = 40, color = { 0.34, 0.26, 0.16 } },
  GROUND   = { kind = "crater", size = 44, color = { 0.36, 0.28, 0.16 } },
  GRASS    = { kind = "dust",   size = 26, color = { 0.30, 0.46, 0.22 } },
  POISON   = { kind = "puddle", size = 26, color = { 0.50, 0.28, 0.56 } },
  PSYCHIC  = { kind = "frost",  size = 30, color = { 0.86, 0.60, 0.80 } },
}
BattleHitFX.MARK_DEFAULT = { kind = "dust", size = 24,
                             color = { 0.42, 0.38, 0.30 } }

-- deterministic noise for the brushes (a paused frame draws the same)
local function nz(a, b)
  local x = math.sin(a * 127.1 + (b or 0) * 311.7) * 43758.5453
  return x - math.floor(x)
end

local function copyCell(cell)
  if not cell then return nil end
  return { cell[1], cell[2] }
end

local function typeTint(tname)
  local B = box()
  local c = (B and tname and B.TYPE_COLOR and B.TYPE_COLOR[tname])
            or (B and B.TYPE_FALLBACK)
            or { 1, 1, 1 }
  return { c[1], c[2], c[3] }
end

local function keysFor(tname)
  local row = tname and BattleHitFX.TYPE_FX[tname]
  if row then return row.charge, row.hit end
  return "bt_slash", "bt_slash"
end

-- deterministic per-frame noise: a paused frame draws the same picture twice
local function prand(a, b)
  local x = math.sin(a * 127.1 + (b or 0) * 311.7) * 43758.5453
  return x - math.floor(x)
end

function BattleHitFX.debug()
  return {
    playing = S.playing,
    live = (Vfx.battleCount and Vfx.battleCount()) or 0,
    lastKey = S.lastKey,
    lastSide = S.lastSide,
    chargeKey = S.chargeKey,
    hitKey = S.hitKey,
    projectile = (S.playing and S.fromCell and S.toCell) and true or false,
    spot = S.spot and true or false,
    light = S.light and (now() - S.light.born) < BattleHitFX.FLASH_LIFE
            and true or false,
    debris = #S.debris,
    marks = #S.marks,
    markKind = S.marks[#S.marks] and S.marks[#S.marks].kind or nil,
    tags = #S.tags,
    lastDamage = S.lastDamage,
    shadows = S.lastShadows or 0,
    flashFrames = S.flashDrew or 0,
    spotFrames = S.spotDrew or 0,
  }
end

function BattleHitFX.clear()
  S.spot = nil
  S.light = nil
  S.debris = {}
  S.marks = {}
  S.tags = {}
  S.shown = {}
  S.maxHP = {}
  S.lastDamage = nil
  S.prev = {}
  S.playing = false
  S.lastKey = nil
  S.lastSide = nil
  S.tname = nil
  S.def = nil
  S.attackerIsPlayer = false
  S.chargeKey = nil
  S.hitKey = nil
  S.tint = nil
  S.fromCell = nil
  S.toCell = nil
  S.groundY = 0
  S.born = 0
  S.midPulsed = false
  S.sparkAt = nil
  if Vfx.clearBattle then Vfx.clearBattle() end
end

local function draining(b)
  if not (b and b.mon and b.shownHP) then return false end
  return b.shownHP > b.mon.hp
end

local function moveType(battle)
  local B = box()
  local data = battle and battle.data and battle.data.moves
  local def = data and battle.animName and data[battle.animName]
  local tname = def and B and B.typeName(def.type)
  return tname, def
end

local function playAt(key, cell, groundY, side, opts)
  if not (key and cell) then return false end
  opts = opts or {}
  opts.force = true
  opts.battle = true
  local ok, played = pcall(Vfx.play, key, cell[1], groundY or 0, cell[2], opts)
  if ok and played then
    S.lastKey = key
    S.lastSide = side
    return true
  end
  return false
end

local function splatDefender(tname, quake, cell)
  if not cell then return end
  if tname == "FIRE" then return end
  local G = grass()
  if not (G and G.splat) then return end
  local r, s = 22, 1.3
  if tname == "GROUND" or tname == "ROCK" or quake then
    r, s = 36, 1.8
  elseif tname == "WATER" or tname == "ICE" then
    r, s = 24, 1.1
  end
  pcall(G.splat, cell[1], cell[2], r, s)
end

-- ------- watching the fight (called from OverworldBattle.update)
function BattleHitFX.observe(battle, dt, arena, groundY)
  if not BattleHitFX.ENABLED then return end
  if not battle then
    S.prev = {}
    S.playing = false
    return
  end

  local playing = battle.animPlaying and true or false
  S.playing = playing
  local fx = battle.fx
  local flash = (fx and (fx.flash or 0) > 0) and true or false
  local quake = (fx and (fx.shake or 0) > 0) and true or false
  local drain = draining(battle.player) or draining(battle.enemy)
  local t = now()

  -- the ageing: debris settles, marks fade, tags float off, the
  -- spotlight goes out after the move
  do
    local i = 1
    while i <= #S.debris do
      if t - S.debris[i].born > BattleHitFX.DEBRIS_LIFE then
        table.remove(S.debris, i)
      else i = i + 1 end
    end
    i = 1
    while i <= #S.marks do
      if t - S.marks[i].born > BattleHitFX.MARK_LIFE then
        table.remove(S.marks, i)
      else i = i + 1 end
    end
    i = 1
    while i <= #S.tags do
      if t - S.tags[i].born > BattleHitFX.TAG_LIFE then
        table.remove(S.tags, i)
      else i = i + 1 end
    end
    if S.spot and S.spot.untilT
       and t - S.spot.untilT > BattleHitFX.SPOT_OUT then
      S.spot = nil
    end
    if S.light and t - S.light.born > BattleHitFX.FLASH_LIFE then
      S.light = nil
    end
  end
  -- the move ends: the spotlight starts going out
  if S.spot and not playing and S.prev.playing and not S.spot.untilT then
    S.spot.untilT = t
  end

  -- a move begins: CHARGE at the attacker's cell. The glass drops its
  -- own telegraph wave from the same edge; this is the matching picture.
  if playing and not S.prev.playing then
    S.attackerIsPlayer = battle.animAttackerIsPlayer and true or false
    local tname, def = moveType(battle)
    S.tname, S.def = tname, def
    local chargeKey, hitKey = keysFor(tname)
    S.chargeKey, S.hitKey = chargeKey, hitKey
    S.tint = typeTint(tname)
    S.groundY = groundY or 0
    S.fromCell = copyCell(arena and (S.attackerIsPlayer and arena.player
                                                       or arena.enemy))
    S.toCell = copyCell(arena and (S.attackerIsPlayer and arena.enemy
                                                     or arena.player))
    S.born = now()
    S.midPulsed = false
    playAt(chargeKey, S.fromCell, S.groundY,
           S.attackerIsPlayer and "player" or "enemy",
           { scale = 0.85, tint = S.tint })
    -- and the spotlight closes in on the attacker
    if S.fromCell then
      S.spot = { born = t, cell = copyCell(S.fromCell), untilT = nil }
    end
  end

  -- the hit lands: HIT at the defender, and a typed dent in the grass
  -- around that cell only. The glass already owns the hit wave.
  --
  -- WHEN it lands, measured: with animations on the engine writes the
  -- new hp FIRST (the bar is now "pending": shownHP > hp), types the
  -- "X used Y!" line, plays the anim, and only then drains the bar. The
  -- pending edge is therefore a full second EARLY -- a flash there lights
  -- a mon standing still while the box types. The blow is the END of
  -- the anim while a drain is pending; on the anims-off path fx.flash /
  -- fx.shake still mark it, and the bar starting to MOVE is the last
  -- resort. One hit per pending episode, whichever tell comes first.
  local pending = drain
  if pending and not S.prev.drain then
    S.episode = (S.episode or 0) + 1
    S.hitFor = nil
  end
  local moving = false
  for _, sd in ipairs({ "player", "enemy" }) do
    local b = battle[sd]
    if b and b.shownHP and S.shown[sd] and b.shownHP < S.shown[sd] then
      moving = true
    end
  end
  local animEnd = pending and (not playing) and S.prev.playing
  local landed = (flash and not S.prev.flash) or (quake and not S.prev.quake)
                 or animEnd or (pending and moving)
  if landed and pending and S.hitFor == S.episode then landed = false end
  if landed then
    if pending then S.hitFor = S.episode end
    local tname = S.tname
    if not tname then
      tname, S.def = moveType(battle)
      S.tname = tname
    end
    if not S.hitKey then
      local c, h = keysFor(tname)
      S.chargeKey, S.hitKey = S.chargeKey or c, h
      S.tint = S.tint or typeTint(tname)
    end
    local defenderIsPlayer = not S.attackerIsPlayer
    local cell = arena and (defenderIsPlayer and arena.player or arena.enemy)
    if not S.toCell then S.toCell = copyCell(cell) end
    playAt(S.hitKey, cell, groundY or S.groundY,
           defenderIsPlayer and "player" or "enemy",
           { scale = 1.35, size = 40, tint = S.tint })
    local isQuake = quake and not S.prev.quake
    splatDefender(tname, isQuake, cell)
    S.sparkAt = now()

    -- the damage, off the bar: what it showed last frame less what the
    -- mon has now. Zero on a miss or a status move, and no tag then.
    local side = defenderIsPlayer and "player" or "enemy"
    local b = battle[side]
    local dmg, frac = 0, 0
    if b and b.mon and S.monRef and S.monRef[side] == b.mon then
      local was = S.shown[side] or b.shownHP or b.mon.hp or 0
      dmg = math.floor((was or 0) - (b.mon.hp or 0) + 0.5)
      local mx = S.maxHP[side] or b.mon.maxHP or b.mon.maxHp
                 or (b.mon.stats and b.mon.stats.hp) or was or 1
      frac = dmg / math.max(1, mx)
    end
    if dmg > 0 then
      S.lastDamage = dmg
      S.tags[#S.tags + 1] = { born = t, dmg = dmg, frac = frac,
                              side = side, cell = copyCell(cell),
                              tint = S.tint }
    end

    -- the arena answers: the flash, the debris, the mark
    if cell then
      local big = isQuake and 1.6 or (0.8 + math.min(1, frac * 2.5) * 0.8)
      S.light = { born = t, cell = copyCell(cell), tint = S.tint,
                  big = big }
      local gy = groundY or S.groundY or 0
      local seed = math.floor(t * 61)
      local n = BattleHitFX.DEBRIS_N + (isQuake and 8 or 0)
      for i = 1, n do
        local a = nz(seed, i) * 2 * math.pi
        local sp = 22 + 48 * nz(seed, i + 31)
        S.debris[#S.debris + 1] = {
          born = t, x = cell[1] + (nz(seed, i + 7) - 0.5) * 6,
          y = gy + 1, z = cell[2] + (nz(seed, i + 13) - 0.5) * 6,
          vx = math.cos(a) * sp, vz = math.sin(a) * sp,
          vy = 55 + 95 * nz(seed, i + 19),
          s = 0.35 + 0.55 * nz(seed, i + 23), tint = S.tint,
          bounced = false, gy = gy,
        }
      end
      local spec = (tname and BattleHitFX.MARK[tname])
                   or BattleHitFX.MARK_DEFAULT
      S.marks[#S.marks + 1] = {
        born = t, kind = spec.kind, size = spec.size * (isQuake and 1.3 or 1),
        color = spec.color, x = cell[1], z = cell[2],
        seed = seed, mesh = nil,
      }
      if #S.marks > 6 then table.remove(S.marks, 1) end
    end
  end

  -- what the bars show, for next frame's damage read. A side whose mon
  -- CHANGED (a switch, a faint) starts over: the bar filling up for the
  -- newcomer is not a blow on it.
  S.monRef = S.monRef or {}
  for _, side in ipairs({ "player", "enemy" }) do
    local b = battle[side]
    if b and b.mon then
      if S.monRef[side] ~= b.mon then
        S.monRef[side] = b.mon
        S.shown[side] = b.mon.hp
      else
        S.shown[side] = b.shownHP or b.mon.hp
      end
      S.maxHP[side] = b.mon.maxHP or b.mon.maxHp
                      or (b.mon.stats and b.mon.stats.hp) or S.maxHP[side]
    end
  end

  S.prev.playing, S.prev.flash, S.prev.quake, S.prev.drain =
    playing, flash, quake, drain
end

-- world -> shot.canvas pixels, through the snapshotted viewProjection.
-- vp already flipped clip Y into LOVE's Y-down (see BattleScene.toGB).
local function projectUsingShotVp(shot)
  local vp, pw, ph = shot.vp, shot.pw, shot.ph
  return function(wx, wy, wz)
    if not (vp and pw and ph) then return nil end
    local cx = vp[1] * wx + vp[2] * wy + vp[3] * wz + vp[4]
    local cy = vp[5] * wx + vp[6] * wy + vp[7] * wz + vp[8]
    local cw = vp[13] * wx + vp[14] * wy + vp[15] * wz + vp[16]
    if (not cw) or cw <= 1e-6 then return nil end
    return (cx / cw * 0.5 + 0.5) * pw, (cy / cw * 0.5 + 0.5) * ph
  end
end

local TRAVEL = 0.72

local function drawProjectile(g, shot, project)
  if not (S.playing and S.fromCell and S.toCell) then return end
  local lift = (S.groundY or 0) + (Vfx.LIFT or 8)
  local x0, y0 = project(S.fromCell[1], lift, S.fromCell[2])
  local x1, y1 = project(S.toCell[1], lift, S.toCell[2])
  if not (x0 and x1) then return end

  local elapsed = now() - (S.born or now())
  local u = elapsed / TRAVEL
  if u < 0 then u = 0 elseif u > 1 then u = 1 end
  local k = 1 - (1 - u) * (1 - u)   -- ease out

  -- mid-travel knock on the glass, once per move
  if (not S.midPulsed) and k >= 0.45 then
    S.midPulsed = true
    local G = glass()
    if G and G.pulse then
      local mx = (S.fromCell[1] + S.toCell[1]) * 0.5
      local mz = (S.fromCell[2] + S.toCell[2]) * 0.5
      pcall(G.pulse, mx, lift, mz, 0.35)
    end
  end

  local hx = x0 + (x1 - x0) * k
  local hy = y0 + (y1 - y0) * k
  local dx, dy = x1 - x0, y1 - y0
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 4 then return end
  local nx, ny = -dy / len, dx / len
  local ux, uy = dx / len, dy / len

  local span = math.max(shot.playerSpan or 0, shot.enemySpan or 0)
  if span < 8 then span = 32 end
  local px = math.max(2, span * 0.10)

  local tn = S.tint or { 1, 1, 1 }
  local tname = S.tname or "NORMAL"
  local fade = k < 0.85 and 1 or (1 - (k - 0.85) / 0.15)
  if fade < 0 then fade = 0 end

  local seed = math.floor((S.born or 0) * 50)

  if tname == "ELECTRIC" then
    -- jagged polyline to the head, plus 2-3 forks
    g.setLineWidth(math.max(1.5, px * 0.45))
    g.setColor(tn[1], tn[2], tn[3], 0.85 * fade)
    local n = 7
    local pts = { x0, y0 }
    for i = 1, n do
      local t = (i / n) * k
      local j = (prand(seed, i) - 0.5) * px * 2.4
      pts[#pts + 1] = x0 + dx * t + nx * j
      pts[#pts + 1] = y0 + dy * t + ny * j
    end
    pcall(g.line, pts)
    g.setColor(1, 1, 1, 0.7 * fade)
    g.setLineWidth(math.max(1, px * 0.22))
    pcall(g.line, pts)
    for f = 1, 3 do
      local t = (0.25 + 0.2 * f) * k
      if t > 0.08 then
        local bx = x0 + dx * t
        local by = y0 + dy * t
        local side = (f % 2 == 0) and 1 or -1
        g.setColor(tn[1], tn[2], tn[3], 0.7 * fade)
        g.setLineWidth(math.max(1, px * 0.28))
        pcall(g.line, bx, by,
              bx + nx * side * px * 2.8 + ux * px * 1.4,
              by + ny * side * px * 2.8 + uy * px * 1.4)
      end
    end
    g.setLineWidth(1)

  elseif tname == "WATER" or tname == "ICE" then
    local n = 8
    for i = 1, n do
      local t = (i / n) * k
      local j = (prand(seed, i + 3) - 0.5) * px * 0.8
      local x = x0 + dx * t + nx * j
      local y = y0 + dy * t + ny * j
      local r = (i == n and px * 0.55 or px * 0.32)
      g.setColor(tn[1], tn[2], tn[3], (0.45 + 0.5 * (i / n)) * fade)
      pcall(g.rectangle, "fill", x - r, y - r, r * 2, r * 2)
    end

  elseif tname == "FIRE" then
    for i = 1, 5 do
      local t = (0.12 + 0.18 * (i - 1))
      if t <= k then
        local drift = (k - t) * px * 2.2
        local j = (prand(seed, i + 9) - 0.5) * px
        local x = x0 + dx * t + nx * j
        local y = y0 + dy * t + ny * j - drift
        local s = px * (0.55 + 0.2 * (i % 2))
        g.setColor(tn[1], tn[2], tn[3], (0.85 - (k - t) * 0.7) * fade)
        pcall(g.rectangle, "fill", x - s * 0.4, y - s, s * 0.8, s)
      end
    end

  elseif tname == "GRASS" or tname == "BUG" then
    for i = 1, 5 do
      local t = (0.10 + 0.18 * (i - 1))
      if t <= k then
        local spin = (k - t) * 6 + i
        local j = (prand(seed, i + 2) - 0.5) * px * 1.2
        local x = x0 + dx * t + nx * j
        local y = y0 + dy * t + ny * j
        local s = px * 0.7
        g.setColor(tn[1], tn[2], tn[3], 0.9 * fade)
        local ca, sa = math.cos(spin), math.sin(spin)
        pcall(g.polygon, "fill",
              x + ca * s, y + sa * s * 0.45,
              x - sa * s * 0.4, y + ca * s * 0.4,
              x - ca * s, y - sa * s * 0.45,
              x + sa * s * 0.4, y - ca * s * 0.4)
      end
    end

  elseif tname == "PSYCHIC" or tname == "GHOST" or tname == "DRAGON" then
    local gap = px * 0.85
    g.setLineWidth(math.max(1, px * 0.22))
    g.setColor(tn[1], tn[2], tn[3], 0.55 * fade)
    pcall(g.line, x0 + nx * gap, y0 + ny * gap, hx + nx * gap, hy + ny * gap)
    pcall(g.line, x0 - nx * gap, y0 - ny * gap, hx - nx * gap, hy - ny * gap)
    g.setLineWidth(math.max(2, px * 0.55))
    g.setColor(tn[1], tn[2], tn[3], 0.9 * fade)
    pcall(g.line, x0, y0, hx, hy)
    g.setColor(1, 1, 1, 0.65 * fade)
    g.setLineWidth(math.max(1, px * 0.22))
    pcall(g.line, x0, y0, hx, hy)
    g.setLineWidth(1)

  elseif tname == "ROCK" or tname == "GROUND" then
    for i = 1, 6 do
      local t = (0.08 + 0.15 * (i - 1))
      if t <= k then
        local fall = (k - t) * (k - t) * px * 3.5
        local j = (prand(seed, i + 7) - 0.5) * px * 1.6
        local x = x0 + dx * t + nx * j
        local y = y0 + dy * t + ny * j + fall
        local s = px * (0.45 + 0.25 * (i % 3))
        g.setColor(tn[1], tn[2], tn[3], 0.85 * fade)
        pcall(g.rectangle, "fill", x - s * 0.5, y - s * 0.5, s, s)
      end
    end

  elseif tname == "POISON" then
    for i = 1, 5 do
      local t = (0.10 + 0.16 * (i - 1))
      if t <= k then
        local rise = (k - t) * px * 2.4
        local wob = math.sin((k + i) * 5.0) * px * 0.5
        local x = x0 + dx * t + nx * wob
        local y = y0 + dy * t - rise
        local s = px * (0.7 - (k - t) * 0.25)
        g.setColor(tn[1], tn[2], tn[3], 0.8 * fade)
        pcall(g.rectangle, "fill", x - s, y - s, s * 2, s * 1.6)
        pcall(g.rectangle, "fill", x - s * 0.5, y - s * 1.4, s, s)
      end
    end

  else
    -- FIGHTING / NORMAL / FLYING: a short slash tick that travels, not
    -- a full line the whole time
    local tick = math.max(px * 2.2, span * 0.22)
    local tx0 = hx - ux * tick * 0.5
    local ty0 = hy - uy * tick * 0.5
    local tx1 = hx + ux * tick * 0.5
    local ty1 = hy + uy * tick * 0.5
    -- slash is slightly rotated off the path
    local ox, oy = nx * px * 0.4, ny * px * 0.4
    g.setLineWidth(math.max(2, px * 0.7))
    g.setColor(tn[1], tn[2], tn[3], 0.95 * fade)
    pcall(g.line, tx0 + ox, ty0 + oy, tx1 - ox, ty1 - oy)
    g.setColor(1, 1, 1, 0.7 * fade)
    g.setLineWidth(math.max(1, px * 0.28))
    pcall(g.line, tx0 + ox, ty0 + oy, tx1 - ox, ty1 - oy)
    g.setLineWidth(1)
  end
end

-- ------- the light: two radial images, built once
--
-- GLOW is white with a soft alpha falloff, drawn additive for the flash.
-- VIGN is opaque, white at the centre and dark at the rim, drawn with
-- multiply -- laid over the frame centred on the attacker it darkens
-- everything but them. Big enough that its rim reaches past every corner
-- from any point in frame (see the scale at the draw).
local GLOW, VIGN = nil, nil
local function radials()
  if GLOW ~= nil then return GLOW or nil, VIGN or nil end
  local ok = pcall(function()
    local N = 128
    local gd = love.image.newImageData(N, N)
    local vd = love.image.newImageData(N, N)
    local c = (N - 1) * 0.5
    for y = 0, N - 1 do
      for x = 0, N - 1 do
        local r = math.sqrt((x - c) ^ 2 + (y - c) ^ 2) / c
        local a = math.max(0, 1 - r)
        gd:setPixel(x, y, 1, 1, 1, a * a)
        -- clear core, then a smooth rise of darkness to the rim: black
        -- at an alpha that peaks at SPOT_DARK, so drawn plain over the
        -- frame it darkens the corners and leaves the centre alone
        local k
        if r < 0.28 then k = 0
        else
          local u = math.min(1, (r - 0.28) / 0.72)
          k = u * u * (3 - 2 * u)
        end
        vd:setPixel(x, y, 0, 0, 0, BattleHitFX.SPOT_DARK * k)
      end
    end
    GLOW = love.graphics.newImage(gd)
    VIGN = love.graphics.newImage(vd)
    GLOW:setFilter("linear", "linear")
    VIGN:setFilter("linear", "linear")
  end)
  if not ok then GLOW, VIGN = false, false end
  return GLOW or nil, VIGN or nil
end

-- one overworld square where the mons stand, in CANVAS pixels: the shot
-- reports its spans in Game Boy pixels (BattleScene.toGB), so they are
-- scaled up by the letterbox here -- a card is FULL_W world units on a
-- side and the pic covers its square, so this is also the mon's size
local function spanOf(shot)
  local span = math.max(shot.playerSpan or 0, shot.enemySpan or 0)
  if span < 8 then span = 32 end
  return span * (shot.scale or 1)
end

-- the spotlight, multiplied over the finished shot around the attacker
local function drawSpot(g, shot, project)
  local sp = S.spot
  if not (sp and sp.cell) then return false end
  local _, vign = radials()
  if not vign then return false end
  local t = now()
  local k = math.min(1, (t - sp.born) / BattleHitFX.SPOT_IN)
  if sp.untilT then
    k = k * math.max(0, 1 - (t - sp.untilT) / BattleHitFX.SPOT_OUT)
  end
  if k <= 0.01 then return false end
  local lift = (S.groundY or 0) + (Vfx.LIFT or 8)
  local cx, cy = project(sp.cell[1], lift, sp.cell[2])
  if not cx then return false end
  local pw, ph = shot.pw or 0, shot.ph or 0
  if pw <= 0 or ph <= 0 then return false end
  -- the image's half-size must reach the farthest corner from the centre
  local far = math.max(cx, pw - cx)
  local fary = math.max(cy, ph - cy)
  local reach = math.sqrt(far * far + fary * fary) * 1.02
  local iw = vign:getWidth()
  local sc = (reach * 2) / iw
  local blend, alphaMode = g.getBlendMode()
  pcall(g.setBlendMode, "alpha", "alphamultiply")
  -- the fade rides the draw alpha: the image is black with the
  -- darkness in its alpha, so k scales the whole vignette at once
  g.setColor(1, 1, 1, k)
  g.draw(vign, cx, cy, 0, sc, sc, iw * 0.5, iw * 0.5)
  if alphaMode ~= nil then pcall(g.setBlendMode, blend, alphaMode)
  else pcall(g.setBlendMode, blend or "alpha") end
  g.setColor(1, 1, 1, 1)
  S.spotDrew = (S.spotDrew or 0) + 1
  return true
end

-- the flash at the defender, additive
local function drawFlash(g, shot, project)
  local L = S.light
  if not (L and L.cell) then return false end
  local glow = radials()
  if not glow then return false end
  local age = now() - L.born
  if age < 0 or age > BattleHitFX.FLASH_LIFE then return false end
  local f = 1 - age / BattleHitFX.FLASH_LIFE
  local lift = (S.groundY or 0) + (Vfx.LIFT or 8)
  local cx, cy = project(L.cell[1], lift, L.cell[2])
  if not cx then return false end
  local span = spanOf(shot)
  local rad = span * BattleHitFX.FLASH_REACH * (L.big or 1)
              * (0.7 + 0.3 * (1 - f))
  local iw = glow:getWidth()
  local sc = (rad * 2) / iw
  local tn = L.tint or { 1, 1, 1 }
  local blend, alphaMode = g.getBlendMode()
  pcall(g.setBlendMode, "add", "alphamultiply")
  g.setColor(tn[1], tn[2], tn[3], 0.55 * f * f)
  g.draw(glow, cx, cy, 0, sc, sc, iw * 0.5, iw * 0.5)
  -- a hot white core, gone twice as fast
  local core = math.max(0, 1 - age / (BattleHitFX.FLASH_LIFE * 0.45))
  if core > 0 then
    g.setColor(1, 1, 1, 0.5 * core)
    g.draw(glow, cx, cy, 0, sc * 0.35, sc * 0.35, iw * 0.5, iw * 0.5)
  end
  -- and a slab of the colour on the floor: the light reaching the ground
  g.setColor(tn[1], tn[2], tn[3], 0.28 * f)
  local gx, gy = project(L.cell[1], (S.groundY or 0) + 0.5, L.cell[2])
  if gx then
    g.draw(glow, gx, gy, 0, sc * 0.9, sc * 0.42, iw * 0.5, iw * 0.5)
  end
  if alphaMode ~= nil then pcall(g.setBlendMode, blend, alphaMode)
  else pcall(g.setBlendMode, blend or "alpha") end
  g.setColor(1, 1, 1, 1)
  S.flashDrew = (S.flashDrew or 0) + 1
  return true
end

-- the voxel debris: stepped here on real time, drawn as projected cubes
local DEBRIS_G = 260
local function drawDebris(g, shot, project)
  if #S.debris == 0 then return false end
  local t = now()
  local dt = t - (S.debrisT or t)
  S.debrisT = t
  if dt < 0 then dt = 0 elseif dt > 0.05 then dt = 0.05 end
  local span = spanOf(shot)
  -- screen px per world px where the mons stand, for the cube size
  local ppw = span / 16
  -- one CC0 star at impact is already a glint; a cube is a chip of the
  -- floor, never smaller than a couple of pixels
  local blend, alphaMode = g.getBlendMode()
  pcall(g.setBlendMode, "alpha", "alphamultiply")
  local drew = false
  for _, d in ipairs(S.debris) do
    if d.y > d.gy or d.vy > 0 or not d.bounced then
      d.vy = d.vy - DEBRIS_G * dt
      d.x = d.x + d.vx * dt
      d.y = d.y + d.vy * dt
      d.z = d.z + d.vz * dt
      if d.y < d.gy then
        d.y = d.gy
        if not d.bounced then
          d.bounced = true
          d.vy = -d.vy * 0.35
          d.vx, d.vz = d.vx * 0.5, d.vz * 0.5
        else
          d.vy, d.vx, d.vz = 0, 0, 0
        end
      end
    end
    local age = t - d.born
    local a = 1 - math.max(0, (age - BattleHitFX.DEBRIS_LIFE * 0.6)
                              / (BattleHitFX.DEBRIS_LIFE * 0.4))
    local sx, sy = project(d.x, d.y + d.s, d.z)
    if sx and a > 0 then
      local px = math.max(1.5, d.s * ppw)
      local tn = d.tint or { 1, 1, 1 }
      -- the cube: a lit top square over a darker front face
      g.setColor(0.55 + 0.35 * tn[1], 0.55 + 0.35 * tn[2],
                 0.55 + 0.35 * tn[3], a)
      g.rectangle("fill", sx - px * 0.5, sy - px * 0.5, px, px * 0.55)
      g.setColor(0.25 + 0.3 * tn[1], 0.25 + 0.3 * tn[2],
                 0.25 + 0.3 * tn[3], a)
      g.rectangle("fill", sx - px * 0.5, sy + px * 0.05, px, px * 0.5)
      drew = true
    end
  end
  if alphaMode ~= nil then pcall(g.setBlendMode, blend, alphaMode)
  else pcall(g.setBlendMode, blend or "alpha") end
  g.setColor(1, 1, 1, 1)
  return drew
end

-- ------- onto the finished 3D image, under the frost and the HUD
function BattleHitFX.draw(shot)
  if not BattleHitFX.ENABLED then return false end
  if not (shot and shot.canvas and shot.vp) then return false end
  if not (love and love.graphics) then return false end
  local g = love.graphics
  local drew = false
  local ok = pcall(function()
    local prev = g.getCanvas()
    g.setCanvas(shot.canvas)
    -- the spotlight first: the sheets and the flash must not be dimmed
    local pok, pd = pcall(drawSpot, g, shot, projectUsingShotVp(shot))
    if pok and pd then drew = true end
    local painted = Vfx.draw(projectUsingShotVp(shot), 1, { force = true })
    drew = drew or (painted and true or false)
    local dok, dd = pcall(drawDebris, g, shot, projectUsingShotVp(shot))
    if dok and dd then drew = true end
    -- projectile: additive type-colored streak after the sheets
    local r, gg, b, a = g.getColor()
    local blend, alphaMode = g.getBlendMode()
    pcall(g.setBlendMode, "add", "alphamultiply")
    if S.playing and S.fromCell and S.toCell then
      local pok = pcall(drawProjectile, g, shot, projectUsingShotVp(shot))
      if pok then drew = true end
    end

    -- one CC0 star at impact (additive). Typed sheets stay; this is a glint.
    pcall(function()
      if S.sparkAt and S.toCell then
        local age = now() - S.sparkAt
        if age >= 0 and age < 0.18 then
          local project = projectUsingShotVp(shot)
          local lift = (S.groundY or 0) + (Vfx.LIFT or 8)
          local hx, hy = project(S.toCell[1], lift, S.toCell[2])
          if hx then
            local B = box()
            local img = B and B._art and B._art("fx/9_pointed_star")
            local fade = math.sin((1 - age / 0.18) * math.pi)
            local tn = S.tint or { 1, 1, 1 }
            pcall(g.setBlendMode, "add", "alphamultiply")
            if img then
              pcall(img.setFilter, img, "nearest", "nearest")
              local iw, ih = img:getDimensions()
              local span = math.max(shot.playerSpan or 0, shot.enemySpan or 0)
              if span < 8 then span = 32 end
              local sc = (span * 0.55) / math.max(1, ih)
              g.setColor(tn[1], tn[2], tn[3], 0.80 * fade)
              g.draw(img, hx, hy, 0, sc, sc, iw * 0.5, ih * 0.5)
              drew = true
            end
          end
        end
      end
    end)
    if alphaMode ~= nil then
      pcall(g.setBlendMode, blend, alphaMode)
    else
      pcall(g.setBlendMode, blend or "alpha")
    end
    -- the flash last, over everything the blow put in the shot
    local fok, fd = pcall(drawFlash, g, shot, projectUsingShotVp(shot))
    if fok and fd then drew = true end
    g.setColor(r, gg, b, a)
    g.setCanvas(prev)
  end)
  if not ok then
    pcall(g.setCanvas)
    pcall(g.setBlendMode, "alpha")
    pcall(g.setColor, 1, 1, 1, 1)
    return false
  end
  return drew
end

-- ------- a blow on demand, for the probe and for tuning by eye
--
-- Fires the whole answer -- flash, debris, mark, figure -- at a cell,
-- typed, without a move being thrown. Reads nothing from the battle.
function BattleHitFX.demo(tname, cell, groundY, dmg, quake)
  if not (cell and cell[1] and cell[2]) then return false end
  local t = now()
  local tint = typeTint(tname)
  local gy = groundY or S.groundY or 0
  S.groundY = gy
  S.light = { born = t, cell = copyCell(cell), tint = tint,
              big = quake and 1.6 or 1.2 }
  local seed = math.floor(t * 61)
  for i = 1, BattleHitFX.DEBRIS_N + (quake and 8 or 0) do
    local a = nz(seed, i) * 2 * math.pi
    local sp = 22 + 48 * nz(seed, i + 31)
    S.debris[#S.debris + 1] = {
      born = t, x = cell[1] + (nz(seed, i + 7) - 0.5) * 6,
      y = gy + 1, z = cell[2] + (nz(seed, i + 13) - 0.5) * 6,
      vx = math.cos(a) * sp, vz = math.sin(a) * sp,
      vy = 55 + 95 * nz(seed, i + 19),
      s = 0.35 + 0.55 * nz(seed, i + 23), tint = tint,
      bounced = false, gy = gy,
    }
  end
  local spec = (tname and BattleHitFX.MARK[tname]) or BattleHitFX.MARK_DEFAULT
  S.marks[#S.marks + 1] = {
    born = t, kind = spec.kind, size = spec.size * (quake and 1.3 or 1),
    color = spec.color, x = cell[1], z = cell[2], seed = seed, mesh = nil,
  }
  if #S.marks > 6 then table.remove(S.marks, 1) end
  if dmg and dmg > 0 then
    S.lastDamage = dmg
    S.tags[#S.tags + 1] = { born = t, dmg = dmg, frac = math.min(1, dmg / 120),
                            side = "enemy", cell = copyCell(cell), tint = tint }
  end
  local G = glass()
  if G and G.pulse then
    pcall(G.pulse, cell[1], gy + 8, cell[2], quake and G.QUAKE or 1.0, tname)
  end
  return true
end

-- ------- on the floor, inside the 3D pass
--
-- Called by BattleScene.render between the terrain and the mons, with
-- the scene's shader bound. Two things go down: the marks the blows
-- left, and the contact shadows of the floating panes (their footprints
-- from BattleGlassFX, reported when they last drew). Both are flat quads
-- in Voxel3D's own vertex format, depth-tested and not written
-- (beginDecals), a world pixel above the floor so the test is not a
-- coin toss (SHADOW_EPS is too thin for a decal: half the quad wins and
-- half loses). The shader discards alpha under 0.5, so a mark's SHAPE is
-- in its texture's alpha and its tone in the RGB; the fade rides the
-- draw colour's alpha.
local Voxel3DMod = nil
local function voxel3d()
  if Voxel3DMod == nil then
    local ok, M = pcall(V.require, "Voxel3D")
    Voxel3DMod = (ok and M) or false
  end
  return Voxel3DMod or nil
end

BattleHitFX.MARK_EPS = 1.0

local TEX = {}
local WHITE = nil
local function whiteTex()
  if WHITE ~= nil then return WHITE or nil end
  local ok, img = pcall(function()
    local d = love.image.newImageData(2, 2)
    d:mapPixel(function() return 1, 1, 1, 1 end)
    return love.graphics.newImage(d)
  end)
  WHITE = (ok and img) or false
  return WHITE or nil
end

-- one texture per brush, 48 px, ragged by hashed noise
local function markTexture(kind)
  if TEX[kind] ~= nil then return TEX[kind] or nil end
  local ok, img = pcall(function()
    local N = 48
    local d = love.image.newImageData(N, N)
    local c = (N - 1) * 0.5
    d:mapPixel(function(x, y)
      local dx, dy = (x - c) / c, (y - c) / c
      local r = math.sqrt(dx * dx + dy * dy)
      local ang = math.atan2(dy, dx)
      -- a lumpy edge: the radius wobbles with the angle
      local lump = 0.78 + 0.22 * (0.5 + 0.5 * math.sin(ang * 5 + 1.3)
                                  * math.cos(ang * 3 - 0.4))
      local n = nz(x, y)
      local a, tone = 0, 1
      if kind == "crater" then
        -- a rim: the ring between 0.55 and the lumpy edge, darker
        -- outside, lighter inside where the floor is thrown up
        if r > 0.52 * lump and r <= lump then
          a = 1
          local u = (r - 0.52 * lump) / (0.48 * lump)
          tone = 0.55 + 0.6 * (1 - u)
          if n > 0.82 then a = 0 end
        end
      elseif kind == "puddle" then
        if r <= lump * 0.92 then
          a = 1
          -- glossy: lighter toward the centre and a glint off-centre
          tone = 0.75 + 0.25 * (1 - r)
          local gx, gy = dx + 0.25, dy + 0.25
          if gx * gx + gy * gy < 0.06 then tone = 1.35 end
        end
      elseif kind == "frost" then
        if r <= lump then
          -- crystals: a starry cut, bright, with holes
          local star = 0.5 + 0.5 * math.cos(ang * 6)
          if r < 0.35 or (star * (1 - r) > 0.18 and n > 0.25) then
            a = 1
            tone = 0.85 + 0.35 * (1 - r)
          end
        end
      elseif kind == "dust" then
        if r <= lump and n > 0.35 + r * 0.5 then
          a = 1
          tone = 0.9 + 0.3 * n
        end
      else -- scorch
        if r <= lump then
          a = 1
          -- black heart, browning to the edge, pocked
          tone = 0.55 + 0.9 * r * r
          if n > 0.9 and r > 0.4 then a = 0 end
        end
      end
      return tone, tone, tone, a
    end)
    local im = love.graphics.newImage(d)
    im:setFilter("nearest", "nearest")
    return im
  end)
  TEX[kind] = (ok and img) or false
  return TEX[kind] or nil
end

local function quadMesh(V3, cx, y, cz, size, ax, az)
  -- ax/az: an axis to lay the square along (the panes' right); default
  -- world-aligned
  ax = ax or 1; az = az or 0
  local bx, bz = -az, ax
  local h = size * 0.5
  local verts = {
    { cx - ax * h - bx * h, y, cz - az * h - bz * h, 0, 0, 1 },
    { cx + ax * h - bx * h, y, cz + az * h - bz * h, 1, 0, 1 },
    { cx + ax * h + bx * h, y, cz + az * h + bz * h, 1, 1, 1 },
    { cx - ax * h + bx * h, y, cz - az * h + bz * h, 0, 1, 1 },
  }
  local map = {}
  V3.pushQuad(map, 0)
  return V3.newMesh(verts, map)
end

function BattleHitFX.drawGround(host, arena, groundY)
  S.lastShadows = 0
  if not BattleHitFX.ENABLED then return false end
  local V3 = voxel3d()
  if not (V3 and V3.beginDecals and V3.draw and V3.newMesh) then
    return false
  end
  local g = love.graphics
  local t = now()
  local y = (groundY or 0) + BattleHitFX.MARK_EPS
  local drew = 0
  local ok = pcall(function()
    V3.beginDecals(false)
    -- the marks
    for _, m in ipairs(S.marks) do
      local age = t - m.born
      local fadeStart = BattleHitFX.MARK_LIFE - BattleHitFX.MARK_FADE
      local a = 1
      if age > fadeStart then
        a = math.max(0, 1 - (age - fadeStart) / BattleHitFX.MARK_FADE)
      end
      -- the first frames grow it in: a mark that pops full-size reads
      -- as placed, one that spreads reads as made
      local grow = math.min(1, age / 0.22)
      grow = 1 - (1 - grow) * (1 - grow)
      local tex = markTexture(m.kind)
      if tex and a > 0 then
        if not m.mesh or m.grow ~= grow then
          -- puddles pool wider than they land; craters are the size of
          -- the blow. Re-meshed only while growing (a handful of frames).
          m.mesh = quadMesh(V3, m.x, y, m.z, m.size * (0.35 + 0.65 * grow),
                            math.cos(m.seed), math.sin(m.seed))
          m.grow = grow
        end
        if m.mesh then
          local c = m.color
          g.setColor(c[1], c[2], c[3], a)
          V3.draw(m.mesh, tex, nil, 0)
          drew = drew + 1
        end
      end
    end
    -- the contact shadows of the panes
    local G = glass()
    local feet = G and G.footprints and G.footprints()
    local white = whiteTex()
    if feet and #feet > 0 and white then
      local verts, map = {}, {}
      local n = 0
      for _, f in ipairs(feet) do
        for k = 1, 4 do
          local p = f[k]
          verts[#verts + 1] = { p[1], y, p[3], (k == 2 or k == 3) and 1 or 0,
                                (k >= 3) and 1 or 0, 1 }
        end
        V3.pushQuad(map, n)
        n = n + 1
      end
      local mesh = V3.newMesh(verts, map)
      if mesh then
        g.setColor(0, 0, 0, (G.FOOT_ALPHA or 0.26))
        V3.draw(mesh, white, nil, 0)
        S.lastShadows = n
      end
    end
    V3.endDecals()
  end)
  if not ok then
    pcall(V3.endDecals)
    pcall(g.setColor, 1, 1, 1, 1)
    return false
  end
  return drew > 0 or (S.lastShadows or 0) > 0
end

-- ------- the damage number, over the HUD
--
-- Called from snapHUDs after the capsules, with the shot's canvas bound.
-- The figure rises from the defender's capsule (its last screen
-- position, from BattleCapsule) or, without one, from the mon itself.
local Capsule = nil
local function capsule()
  if Capsule == nil then
    local ok, C = pcall(V.require, "BattleCapsule")
    Capsule = (ok and C) or false
  end
  return Capsule or nil
end

function BattleHitFX.drawTop(battle, shot)
  if not BattleHitFX.ENABLED then return false end
  if #S.tags == 0 then return false end
  if not (shot and shot.vp and love and love.graphics) then return false end
  local g = love.graphics
  local t = now()
  local span = spanOf(shot)
  local project = projectUsingShotVp(shot)
  local C = capsule()
  local drew = false
  local ok = pcall(function()
    local blend, alphaMode = g.getBlendMode()
    pcall(g.setBlendMode, "alpha", "alphamultiply")
    for _, tag in ipairs(S.tags) do
      local age = t - tag.born
      local u = age / BattleHitFX.TAG_LIFE
      if u >= 0 and u < 1 then
        -- where: over the defender's head -- the figure belongs to the
        -- blow, and the capsule already says what is left
        local cx, cy
        if tag.cell then
          -- the card's own world height (a full pic stands FULL_W tall
          -- as well as wide -- see BattleBillboard): the figure sits at
          -- the shoulder, in WORLD height, so the camera's swing cannot
          -- drop it onto the face or lift it off the frame
          local okB, BB = pcall(V.require, "BattleBillboard")
          local cardH = (okB and BB and BB.FULL_W) or 40
          -- the near mon's capsule hangs at its shoulder; its figure
          -- sits lower, at the chest, so the two never overprint
          local at = (tag.side == "player") and 0.50 or 0.82
          cx, cy = project(tag.cell[1], (S.groundY or 0) + cardH * at,
                           tag.cell[2])
        end
        if not cx then
          local W = C and C._world and C._world[tag.side]
          if W and W[1] then cx, cy = W[1], W[2] end
        end
        if cx then
          -- the pop: overshoot in the first tenth, then a slow rise
          local pop = (u < 0.12) and (1 + 0.55 * math.sin(u / 0.12 * math.pi))
                      or 1
          local rise = span * BattleHitFX.TAG_RISE * (1 - (1 - u) * (1 - u))
          local a = (u < 0.7) and 1 or (1 - (u - 0.7) / 0.3)
          local big = BattleHitFX.TAG_H
                      + math.min(1, (tag.frac or 0) * 2.2) * BattleHitFX.TAG_H_BIG
          local th = span * big * pop          -- glyph height in px
          local str = tostring(tag.dmg)
          local tw
          local k = th / 9
          if C and C.textWidth then
            tw = C.textWidth(str) * k
          else
            tw = #str * th * 0.7
          end
          local px = cx - tw * 0.5
          local py = cy - rise - th * 1.6
          -- the sliver of glass under it
          local padX, padY = th * 0.45, th * 0.28
          -- kept in frame: the attack camera lifts the far mon toward
          -- the top edge, and a figure over its head would leave the shot
          local pw, ph = shot.pw or 0, shot.ph or 0
          if pw > 0 and ph > 0 then
            px = math.max(padX + 4, math.min(pw - tw - padX - 4, px))
            if py < padY + 4 and tag.cell then
              -- no room over the shoulder: the figure sits on the chest
              -- instead of on the capsule's own line at the top edge
              local okB, BB = pcall(V.require, "BattleBillboard")
              local cardH = (okB and BB and BB.FULL_W) or 40
              local _, chest = project(tag.cell[1],
                                       (S.groundY or 0) + cardH * 0.45,
                                       tag.cell[2])
              if chest then py = chest - rise * 0.5 - th * 0.5 end
            end
            py = math.max(padY + 4, math.min(ph - th - padY - 4, py))
          end
          local gold = BattleHitFX.GOLD
          g.setColor(0.06, 0.07, 0.10, 0.55 * a)
          g.rectangle("fill", px - padX, py - padY, tw + 2 * padX,
                      th + 2 * padY, th * 0.35, th * 0.35)
          g.setColor(gold[1], gold[2], gold[3], 0.85 * a)
          g.setLineWidth(math.max(1, th * 0.07))
          g.rectangle("line", px - padX, py - padY, tw + 2 * padX,
                      th + 2 * padY, th * 0.35, th * 0.35)
          g.setLineWidth(1)
          -- the figure: gold, with a dark shadow a hair under it
          if C and C.text then
            g.setColor(0, 0, 0, 0.8 * a)
            C.text(str, px + th * 0.06, py + th * 0.06, k)
            g.setColor(gold[1], gold[2], gold[3], a)
            C.text(str, px, py, k)
          else
            g.setColor(gold[1], gold[2], gold[3], a)
            g.print(str, px, py, 0, th / 12, th / 12)
          end
          drew = true
        end
      end
    end
    if alphaMode ~= nil then pcall(g.setBlendMode, blend, alphaMode)
    else pcall(g.setBlendMode, blend or "alpha") end
    g.setColor(1, 1, 1, 1)
  end)
  if not ok then
    pcall(g.setColor, 1, 1, 1, 1)
    return false
  end
  return drew
end

return BattleHitFX
