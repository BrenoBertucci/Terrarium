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
}

local function now()
  return (love.timer and love.timer.getTime and love.timer.getTime()) or 0
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
  }
end

function BattleHitFX.clear()
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
  end

  -- the hit lands: HIT at the defender, and a typed dent in the grass
  -- around that cell only. The glass already owns the hit wave.
  if (flash and not S.prev.flash) or (quake and not S.prev.quake)
     or (drain and not S.prev.drain) then
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
    splatDefender(tname, quake and not S.prev.quake, cell)
    S.sparkAt = now()
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
    local painted = Vfx.draw(projectUsingShotVp(shot), 1, { force = true })
    drew = painted and true or false
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

return BattleHitFX
