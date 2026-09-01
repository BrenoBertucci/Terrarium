-- The glass reacting to the fight: physics and weather for the UI.
--
-- Every panel in the battle costume hangs at a world position, and this
-- module is what makes that mean something beyond parallax. Three systems,
-- all read-only against the engine:
--
-- THE WAVE. A move beginning drops a light telegraph at the ATTACKER's
-- cell, so the fan and the dialog start rocking before the blow; a
-- landed hit (the same flash/shake edges the attack camera reads) then
-- drops a shockwave at the DEFENDER's cell. Each panel reports its
-- world centre and gets pushed away from the origin on a damped spring,
-- delayed by its own distance -- the blow visibly travels THROUGH the UI,
-- near panels first, far panels late. A quake move (fx.shake) hits
-- harder. This is what "the panels are objects in the arena" feels like,
-- and no screen-space HUD can fake the stagger.
--
-- THE BOB. Every panel floats on its own slow phase, a fraction of a
-- world pixel. Panels that hold perfectly still read as pinned to the
-- lens; panels that breathe read as suspended in the air they stand in.
--
-- THE WEATHER. While a move plays, its TYPE (data.moves[animName].type --
-- the engine's own lookup, see its draw path) throws matching weather at
-- the dialog box: electricity crawls the border, water beads and runs
-- down the pane, rock kicks dust and pebbles off it, fire sheds embers,
-- ice grows crystals, poison rises in bubbles. A status LANDING does the
-- same on the box (paralysis arcs, the user's own example), and a mon
-- that HAS a status carries a quiet tick of it on its own capsule for as
-- long as it lasts. All of it is drawn through the pane mappers, in the
-- panels' own face space -- so the weather tilts, slides and swings with
-- the glass it is falling on.
--
-- Purely presentational, like everything else here. Nothing reaches
-- damage, timing or scripts; a confused effect is a battle with plain
-- glass.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local BattleHudXY = V.require("BattleHudXY")

local BattleGlassFX = {}

BattleGlassFX.ENABLED = true

-- ------- the wave
BattleGlassFX.WAVE_SPEED = 240   -- world px per second, origin outward
BattleGlassFX.KICK = 0.8         -- world px of shove at the origin
BattleGlassFX.DECAY = 5.5        -- per second, on the spring
BattleGlassFX.HZ = 7             -- the spring's ring
BattleGlassFX.QUAKE = 1.8        -- fx.shake moves hit this much harder
BattleGlassFX.TELEGRAPH = 0.45   -- a move beginning, at the attacker

-- ------- the bob
BattleGlassFX.BOB = 0.14         -- world px, peak
BattleGlassFX.BOB_PERIOD = 3.1

-- ------- the weather, per move type and per status
BattleGlassFX.ELEM_KIND = {
  ELECTRIC = "spark", WATER = "drops", ICE = "frost",
  ROCK = "debris", GROUND = "debris", FIRE = "ember", POISON = "bubbles",
}
BattleGlassFX.STATUS_KIND = {
  PAR = "spark", PSN = "bubbles", TOX = "bubbles",
  BRN = "ember", FRZ = "frost", SLP = "zz",
}
BattleGlassFX.STATUS_COLOR = {
  PAR = { 1.0, 0.87, 0.35 }, PSN = { 0.72, 0.42, 0.78 },
  TOX = { 0.72, 0.42, 0.78 }, BRN = { 0.96, 0.55, 0.25 },
  FRZ = { 0.70, 0.90, 0.95 }, SLP = { 0.75, 0.78, 0.86 },
}
BattleGlassFX.ELEM_FALLBACK = { 0.8, 0.82, 0.9 }

local Box = nil
local function box()
  if Box == nil then
    local ok, B = pcall(V.require, "BattleBoxXY")
    Box = (ok and B) or false
  end
  return Box or nil
end

local function now()
  return (love.timer and love.timer.getTime and love.timer.getTime()) or 0
end

-- deterministic per-frame noise: effects reseed by quantised time, never
-- by math.random, so a paused frame draws the same picture twice
local function prand(a, b)
  local x = math.sin(a * 127.1 + (b or 0) * 311.7) * 43758.5453
  return x - math.floor(x)
end

-- ------- state
local S = {
  wave = nil,        -- { ox, oy, oz, t, amp }
  bobSeed = {},
  elem = nil,        -- { kind, color, untilT, born }
  burst = nil,       -- status burst on the dialog box
  parts = {},        -- [key] = particle systems
  lastDraw = {},     -- [key] = last overlay time, for particle dt
  prev = {},
  defenderIsPlayer = false,
}

function BattleGlassFX.debug()
  return {
    wave = S.wave and { t = S.wave.t, amp = S.wave.amp } or nil,
    elem = S.elem and S.elem.kind or nil,
    burst = S.burst and S.burst.kind or nil,
  }
end


-- a wave dropped at a world origin. Telegraph and hit both go through
-- here, so a second caller cannot invent a parallel spring.
function BattleGlassFX.pulse(ox, oy, oz, amp)
  if not BattleGlassFX.ENABLED then return false end
  if ox == nil then return false end
  S.wave = { ox = ox, oy = oy or 0, oz = oz or 0,
             t = 0, amp = amp or 1.0 }
  return true
end

-- ------- watching the fight (called from OverworldBattle.update)
function BattleGlassFX.observe(battle, dt, arena, groundY)
  if not BattleGlassFX.ENABLED then return end
  dt = dt or 0
  if S.wave then
    S.wave.t = S.wave.t + dt
    if S.wave.t > 1.4 then S.wave = nil end
  end
  local t = now()
  if S.elem and t > S.elem.untilT then S.elem = nil end
  if S.burst and t > S.burst.untilT then S.burst = nil end
  if not battle then
    S.prev = {}
    return
  end

  local playing = battle.animPlaying and true or false
  -- a move begins: its type is the weather (the engine's own lookup --
  -- data.moves[anim] -- so a non-move anim quietly finds nothing)
  if playing and not S.prev.playing then
    S.defenderIsPlayer = not (battle.animAttackerIsPlayer and true or false)
    -- telegraph: the fan and the dialog start rocking when the move
    -- begins, then get slammed when it lands (the hit wave below)
    local att = arena and (S.defenderIsPlayer and arena.enemy
                                             or arena.player)
    if att then
      BattleGlassFX.pulse(att[1], (groundY or 0) + 8, att[2],
                          BattleGlassFX.TELEGRAPH)
    end
    local B = box()
    local data = battle.data and battle.data.moves
    local def = data and battle.animName and data[battle.animName]
    local tname = def and B and B.typeName(def.type)
    local kind = tname and BattleGlassFX.ELEM_KIND[tname]
    if kind then
      S.elem = { kind = kind,
                 color = (B and B.TYPE_COLOR[tname])
                         or BattleGlassFX.ELEM_FALLBACK,
                 untilT = t + 10, born = t }
      S.parts["msg:" .. kind] = nil
    end
  end
  if not playing and S.prev.playing and S.elem then
    S.elem.untilT = math.min(S.elem.untilT, t + 0.5)
  end

  -- the hit lands: drop the wave at the defender's cell. Three symptoms,
  -- because no single one covers both settings: fx.flash and fx.shake
  -- fire on the animations-OFF path, and with animations ON the hit
  -- reaches the pics without touching either -- the bar STARTING TO
  -- DRAIN is the landed hit's one guaranteed tell (same lesson
  -- BattleShot learned).
  local function draining(b)
    if not (b and b.mon and b.shownHP) then return false end
    return b.shownHP > b.mon.hp
  end
  local fx = battle.fx
  local flash = (fx and (fx.flash or 0) > 0) and true or false
  local quake = (fx and (fx.shake or 0) > 0) and true or false
  local drain = draining(battle.player) or draining(battle.enemy)
  if (flash and not S.prev.flash) or (quake and not S.prev.quake)
     or (drain and not S.prev.drain) then
    local cell = arena and (S.defenderIsPlayer and arena.player
                                               or arena.enemy)
    if cell then
      BattleGlassFX.pulse(cell[1], (groundY or 0) + 8, cell[2],
                          (quake and not S.prev.quake)
                          and BattleGlassFX.QUAKE or 1.0)
    end
  end

  -- a status LANDS: the dialog box catches it (paralysis arcs and kin)
  for _, side in ipairs({ "player", "enemy" }) do
    local b = battle[side]
    local st = b and b.mon and b.mon.status
    local key = "st_" .. side
    if st ~= S.prev[key] and type(st) == "string" and st ~= "" then
      local tag = st:upper():sub(1, 3)
      local kind = BattleGlassFX.STATUS_KIND[tag]
      if kind then
        S.burst = { kind = kind,
                    color = BattleGlassFX.STATUS_COLOR[tag]
                            or BattleGlassFX.ELEM_FALLBACK,
                    untilT = t + 2.6, born = t }
        S.parts["msg:" .. kind] = nil
      end
    end
    S.prev[key] = st
  end

  S.prev.playing, S.prev.flash, S.prev.quake, S.prev.drain =
    playing, flash, quake, drain
end

-- ------- the physics: what a panel adds to its own centre
--
-- `center` is the panel's world position BEFORE the size pull; R is the
-- shared rig. Returns offsets along the rig's right and up.
function BattleGlassFX.jolt(id, center, R)
  if not BattleGlassFX.ENABLED then return 0, 0 end
  local t = now()
  local seed = S.bobSeed[id]
  if not seed then
    seed = ((id:byte(1) or 7) * 1.31 + #id * 2.7) % (2 * math.pi)
    S.bobSeed[id] = seed
  end
  local dU = BattleGlassFX.BOB
             * math.sin(t * 2 * math.pi / BattleGlassFX.BOB_PERIOD + seed)
  local dR = 0
  local w = S.wave
  if w then
    local dx = center[1] - w.ox
    local dy = center[2] - w.oy
    local dz = center[3] - w.oz
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    local tau = w.t - dist / BattleGlassFX.WAVE_SPEED
    if tau > 0 then
      local mag = w.amp * BattleGlassFX.KICK
                  * math.exp(-tau * BattleGlassFX.DECAY)
                  * math.sin(tau * 2 * math.pi * BattleGlassFX.HZ)
      local inv = (dist > 1e-3) and (1 / dist) or 0
      local px, py, pz = dx * inv, dy * inv, dz * inv
      dR = dR + mag * (px * R.right[1] + py * R.right[2] + pz * R.right[3])
      dU = dU + mag * (px * R.up[1] + py * R.up[2] + pz * R.up[3])
    end
  end
  return dR, dU
end

-- ------- the weather's brushes
--
-- Everything below draws in a pane's own pixel space through `map`, so
-- the effects lean and swing with the glass. `ss` is screen pixels per
-- pane pixel, for line widths and radii.

local g = nil -- love.graphics, bound per draw call batch

local function line2(map, x1, y1, x2, y2)
  local ax, ay = map(x1, y1)
  local bx, by = map(x2, y2)
  if ax and bx then g.line(ax, ay, bx, by) end
end

local function drawSpark(map, ss, W, H, color, age)
  local t = now()
  local step = math.floor(t * 14)
  local inten = math.min(1, 2.5 - (age or 0))
  for i = 1, 7 do
    if prand(step, i) < 0.9 * inten then
      -- a bolt crawling one border: pick an edge and a spot on it
      local e = math.floor(prand(step, i + 11) * 4) % 4
      local u = 0.1 + 0.8 * prand(step, i + 23)
      local x, y, dxE, dyE
      if e == 0 then x, y, dxE, dyE = u * W, 4, 1, 0
      elseif e == 1 then x, y, dxE, dyE = W - 4, u * H, 0, 1
      elseif e == 2 then x, y, dxE, dyE = u * W, H - 4, 1, 0
      else x, y, dxE, dyE = 4, u * H, 0, 1 end
      local nx, ny = dyE, dxE          -- inward-ish
      local pts = { { x, y } }
      local len = (H * 0.20)
      for k = 1, 3 do
        local j = (prand(step, i * 7 + k) - 0.5) * 2
        pts[#pts + 1] = { pts[k][1] + dxE * len * (0.6 + 0.4 * j)
                          + nx * len * j,
                          pts[k][2] + dyE * len * (0.6 + 0.4 * j)
                          + ny * len * j * 0.8 }
      end
      g.setColor(color[1], color[2], color[3], 0.65)
      g.setLineWidth(math.max(2, 6.5 * ss))
      for k = 1, #pts - 1 do
        line2(map, pts[k][1], pts[k][2], pts[k + 1][1], pts[k + 1][2])
      end
      g.setColor(1, 1, 1, 0.9)
      g.setLineWidth(math.max(1, 2 * ss))
      for k = 1, #pts - 1 do
        line2(map, pts[k][1], pts[k][2], pts[k + 1][1], pts[k + 1][2])
      end
    end
  end
  g.setLineWidth(1)
end

-- stateful particle pools, per effect key
local function pool(key)
  local p = S.parts[key]
  if not p then p = { list = {}, acc = 0, born = now() }; S.parts[key] = p end
  local last = S.lastDraw[key] or now()
  local dt = math.max(0, math.min(0.1, now() - last))
  S.lastDraw[key] = now()
  return p, dt
end

local function drawDrops(key, map, ss, W, H, color)
  local p, dt = pool(key)
  p.acc = p.acc + dt * 26
  while p.acc >= 1 do
    p.acc = p.acc - 1
    p.list[#p.list + 1] = { x = prand(#p.list, p.born) * W,
                            y = prand(#p.list, 3.3) * H * 0.35,
                            vy = 40 + 200 * prand(#p.list, 7.7),
                            r = 3.5 + 5 * prand(#p.list, 9.1), life = 1.4 }
  end
  for i = #p.list, 1, -1 do
    local d = p.list[i]
    d.vy = d.vy + 420 * dt
    d.y = d.y + d.vy * dt
    d.life = d.life - dt
    if d.life <= 0 or d.y > H - 6 then
      table.remove(p.list, i)
    else
      local sx, sy = map(d.x, d.y)
      if sx then
        g.setColor(color[1], color[2], color[3], 0.55)
        g.circle("fill", sx, sy, d.r * ss)
        g.setColor(1, 1, 1, 0.7)
        g.circle("fill", sx - d.r * ss * 0.3, sy - d.r * ss * 0.3,
                 d.r * ss * 0.3)
      end
    end
  end
end

local function drawRisers(key, map, ss, W, H, color, opts)
  -- embers and bubbles share a chassis: things born low that climb
  local p, dt = pool(key)
  p.acc = p.acc + dt * opts.rate
  while p.acc >= 1 do
    p.acc = p.acc - 1
    p.list[#p.list + 1] = { x = (0.08 + 0.84 * prand(#p.list, p.born)) * W,
                            y = H - 10,
                            vy = -(opts.vy0 + opts.vy1
                                   * prand(#p.list, 5.5)),
                            r = opts.r0 + opts.r1 * prand(#p.list, 8.8),
                            ph = prand(#p.list, 2.2) * 6.28, life = 1.5 }
  end
  local t = now()
  for i = #p.list, 1, -1 do
    local d = p.list[i]
    d.y = d.y + d.vy * dt
    d.life = d.life - dt
    if d.life <= 0 or d.y < 8 then
      table.remove(p.list, i)
    else
      local wob = opts.wobble and math.sin(t * 3 + d.ph) * 6 or 0
      local sx, sy = map(d.x + wob, d.y)
      if sx then
        local a = math.min(1, d.life)
                  * (opts.flicker and (0.5 + 0.5 * prand(math.floor(t * 20),
                                                         i)) or 0.8)
        g.setColor(color[1], color[2], color[3], a * 0.75)
        if opts.hollow then
          g.setLineWidth(math.max(1, 1.6 * ss))
          g.circle("line", sx, sy, d.r * ss)
        else
          g.circle("fill", sx, sy, d.r * ss)
        end
      end
    end
  end
  g.setLineWidth(1)
end

local function drawDebris(key, map, ss, W, H, color)
  local p, dt = pool(key)
  if not p.spawned then
    p.spawned = true
    for i = 1, 14 do
      p.list[#p.list + 1] = { x = (0.1 + 0.8 * prand(i, 1.1)) * W,
                              y = H - 12,
                              vx = (prand(i, 2.2) - 0.5) * 240,
                              vy = -(140 + 260 * prand(i, 3.3)),
                              r = 2.5 + 4 * prand(i, 4.4), life = 1.0 }
    end
  end
  for i = #p.list, 1, -1 do
    local d = p.list[i]
    d.vy = d.vy + 900 * dt
    d.x = d.x + d.vx * dt
    d.y = d.y + d.vy * dt
    d.life = d.life - dt
    if d.life <= 0 then
      table.remove(p.list, i)
    else
      local sx, sy = map(d.x, d.y)
      if sx then
        g.setColor(color[1] * 0.7, color[2] * 0.6, color[3] * 0.4,
                   math.min(1, d.life * 1.6) * 0.85)
        g.circle("fill", sx, sy, d.r * ss)
      end
    end
  end
end

local function drawFrost(map, ss, W, H, color, age)
  local grow = math.min(1, (age or 1) * 2.2)
  for i = 1, 7 do
    local edge = i % 2 == 0
    local x = edge and (prand(i, 4.2) < 0.5 and 14 or W - 14)
              or (0.12 + 0.76 * prand(i, 6.6)) * W
    local y = edge and (0.15 + 0.7 * prand(i, 8.4)) * H
              or (prand(i, 5.1) < 0.5 and 12 or H - 12)
    local len = (7 + 8 * prand(i, 7.3)) * grow
    g.setColor(color[1], color[2], color[3], 0.85)
    g.setLineWidth(math.max(1, 1.8 * ss))
    for k = 0, 4 do
      local a = k * math.pi * 2 / 5 + i
      line2(map, x, y, x + math.cos(a) * len, y + math.sin(a) * len * 0.9)
    end
  end
  g.setLineWidth(1)
end

local function drawZz(key, map, ss, W, H, color)
  local p, dt = pool(key)
  p.acc = p.acc + dt * 1.4
  while p.acc >= 1 do
    p.acc = p.acc - 1
    p.list[#p.list + 1] = { x = W - 46, y = 26, life = 1.6,
                            ph = prand(#p.list, 3.9) * 6.28 }
  end
  local t = now()
  for i = #p.list, 1, -1 do
    local d = p.list[i]
    d.y = d.y - 26 * dt
    d.x = d.x + math.sin(t * 2 + d.ph) * 14 * dt
    d.life = d.life - dt
    if d.life <= 0 then
      table.remove(p.list, i)
    else
      local sx, sy = map(d.x, d.y)
      if sx then
        local th = (16 + (1.6 - d.life) * 12) * ss
        BattleHudXY.text("Z", sx, sy, th,
                         { color[1], color[2], color[3],
                           math.min(1, d.life) * 0.9 })
      end
    end
  end
end

local KIND_DRAW = {
  spark = function(key, map, ss, W, H, color, age)
    drawSpark(map, ss, W, H, color, age)
  end,
  drops = function(key, map, ss, W, H, color)
    drawDrops(key, map, ss, W, H, color)
  end,
  ember = function(key, map, ss, W, H, color)
    drawRisers(key, map, ss, W, H, color,
               { rate = 9, vy0 = 40, vy1 = 60, r0 = 2, r1 = 2.5,
                 flicker = true })
  end,
  bubbles = function(key, map, ss, W, H, color)
    drawRisers(key, map, ss, W, H, color,
               { rate = 5, vy0 = 22, vy1 = 30, r0 = 3.5, r1 = 4,
                 wobble = true, hollow = true })
  end,
  debris = function(key, map, ss, W, H, color)
    drawDebris(key, map, ss, W, H, color)
  end,
  frost = function(key, map, ss, W, H, color, age)
    drawFrost(map, ss, W, H, color, age)
  end,
  zz = function(key, map, ss, W, H, color)
    drawZz(key, map, ss, W, H, color)
  end,
}

local function drawKind(key, kind, map, ss, W, H, color, age)
  local fn = KIND_DRAW[kind]
  if not fn then return end
  g = love.graphics
  fn(key, map, ss, W, H, color, age)
  g.setColor(1, 1, 1, 1)
end

-- ------- the dialog box's overlay: the move's weather, and status bursts
function BattleGlassFX.overlayMsg(map, ss, W, H)
  if not BattleGlassFX.ENABLED then return end
  local t = now()
  if S.elem and t <= S.elem.untilT then
    drawKind("msg:" .. S.elem.kind, S.elem.kind, map, ss, W, H,
             S.elem.color, t - S.elem.born)
  end
  if S.burst and t <= S.burst.untilT then
    drawKind("msg:" .. S.burst.kind, S.burst.kind, map, ss, W, H,
             S.burst.color, t - S.burst.born)
  end
end

-- ------- a capsule's quiet tick, while its mon carries a status
BattleGlassFX.TICK_ON = 0.9    -- seconds visible...
BattleGlassFX.TICK_OFF = 2.4   -- ...out of this cycle
function BattleGlassFX.overlayStatus(id, map, ss, W, H, status)
  if not BattleGlassFX.ENABLED then return end
  if type(status) ~= "string" or status == "" then return end
  local tag = status:upper():sub(1, 3)
  local kind = BattleGlassFX.STATUS_KIND[tag]
  if not kind then return end
  local cycle = BattleGlassFX.TICK_ON + BattleGlassFX.TICK_OFF
  local seed = (id:byte(#id) or 0) * 0.37
  if ((now() + seed) % cycle) > BattleGlassFX.TICK_ON then return end
  drawKind(id .. ":" .. kind, kind, map, ss, W, H,
           BattleGlassFX.STATUS_COLOR[tag] or BattleGlassFX.ELEM_FALLBACK, 1)
end

return BattleGlassFX
