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

-- ------- the tilt and the splash
--
-- A pane is not only SHOVED by the wave: it is turned. The push arrives
-- on one side of the glass first, so the pane yaws about its own up axis
-- by an angle that follows the shove -- the panels "lean away" from the
-- blow the way the concept sheet drew them, and lean back on the spring.
-- And the moment the wave front reaches a pane it leaves a mark ON the
-- glass: cracks radiating from the near edge for a physical blow, rings
-- and a wash of the element's colour for the rest. Drawn through the
-- pane mappers like the weather, so the mark tilts with the pane.
BattleGlassFX.TILT = 0.16        -- radians of yaw per world px of shove
BattleGlassFX.TILT_MAX = 0.42
BattleGlassFX.SPLASH_LIFE = 1.15 -- seconds a mark stays on the glass
BattleGlassFX.SPLASH_MIN = 0.55  -- the wave amp below which no mark lands
BattleGlassFX.PHYSICAL = {
  NORMAL = true, FIGHTING = true, FLYING = true, ROCK = true,
  GROUND = true, BUG = true,
}

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
  waveKind = nil,    -- the playing move's type, for the marks on the glass
  waveId = 0,
  reached = {},      -- [pane id] = wave id whose front already passed it
  splash = {},       -- [pane id] = { born, kind, color, ox, oy, oz, amp }
  foot = {},         -- [pane id] = { corners on the ground, t }
  lastTilt = {},     -- [pane id] = radians, for the debug read
}

function BattleGlassFX.debug()
  local nSplash, maxTilt = 0, 0
  local ids = {}
  for id in pairs(S.splash) do nSplash = nSplash + 1; ids[id] = true end
  for _, v in pairs(S.lastTilt) do
    if math.abs(v) > maxTilt then maxTilt = math.abs(v) end
  end
  local nFoot = 0
  for _ in pairs(S.foot) do nFoot = nFoot + 1 end
  return {
    wave = S.wave and { t = S.wave.t, amp = S.wave.amp, kind = S.wave.kind }
           or nil,
    elem = S.elem and S.elem.kind or nil,
    burst = S.burst and S.burst.kind or nil,
    splashes = nSplash,
    splashIds = ids,
    maxTilt = maxTilt,
    footprints = nFoot,
  }
end


-- a wave dropped at a world origin. Telegraph and hit both go through
-- here, so a second caller cannot invent a parallel spring. `kind` is
-- the move's type name; it defaults to the type of the move playing.
function BattleGlassFX.pulse(ox, oy, oz, amp, kind)
  if not BattleGlassFX.ENABLED then return false end
  if ox == nil then return false end
  S.waveId = S.waveId + 1
  S.wave = { ox = ox, oy = oy or 0, oz = oz or 0,
             t = 0, amp = amp or 1.0, kind = kind or S.waveKind,
             id = S.waveId }
  return true
end

-- ------- a pane's footprint on the ground, for the contact shadow
--
-- Every pane reports the world rectangle it floats over (its centre
-- BEFORE the size pull, its own right/up and its world size); the arena
-- pass reads these back and lays a flat dark quad on the floor under
-- each one, depth-tested like the mons' own shadows. A panel with a
-- shadow on the ground stands IN the arena; one without floats on the
-- lens. Read the frame after it is written -- the panels draw after
-- the scene -- which no one can see.
BattleGlassFX.FOOT_ALPHA = 0.26
BattleGlassFX.FOOT_LIFE = 0.3     -- a pane not reported for this long is gone
function BattleGlassFX.footprint(id, c, cr, cu, w, h, groundY)
  if not (BattleGlassFX.ENABLED and id and c and cr and cu) then return end
  local hw, hh = (w or 0) * 0.5, (h or 0) * 0.5
  if hw <= 0 or hh <= 0 then return end
  local gy = (groundY or 0)
  -- the print is the pane laid flat: its own right on the ground, and a
  -- depth along its up's ground component (a pane stands nearly upright,
  -- so that component alone would be a hairline -- the depth is held to
  -- a fraction of the pane's height so the shadow reads as a shape)
  local fx, fz = cu[1], cu[3]
  local fl = math.sqrt(fx * fx + fz * fz)
  if fl < 1e-4 then
    fx, fz = -cr[3], cr[1]
    fl = math.sqrt(fx * fx + fz * fz)
    if fl < 1e-4 then return end
  end
  fx, fz = fx / fl, fz / fl
  local hd = hh * 0.28
  local function corner(sx, sy)
    return { c[1] + cr[1] * sx + fx * sy, gy, c[3] + cr[3] * sx + fz * sy }
  end
  S.foot[id] = { corner(-hw, hd), corner(hw, hd),
                 corner(hw, -hd), corner(-hw, -hd), t = now() }
end

function BattleGlassFX.footprints()
  local t = now()
  local out = {}
  for id, f in pairs(S.foot) do
    if t - (f.t or 0) > BattleGlassFX.FOOT_LIFE then
      S.foot[id] = nil
    else
      out[#out + 1] = f
    end
  end
  return out
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
  for id, sp in pairs(S.splash) do
    if t - sp.born > BattleGlassFX.SPLASH_LIFE then S.splash[id] = nil end
  end
  if not battle then
    S.prev = {}
    S.splash = {}
    S.reached = {}
    S.foot = {}
    S.waveKind = nil
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
    -- the type rides the waves this move drops, for the marks on the glass
    S.waveKind = tname
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
  -- ...and WHEN: the pending edge (shownHP > hp) comes a second before
  -- the anim -- the engine writes hp first. The blow is the anim's end
  -- with a drain pending, or the flash/shake on the anims-off path, or
  -- the bar starting to move as the last resort; once per pending
  -- episode (the same reading BattleHitFX takes).
  if drain and not S.prev.drain then
    S.episode = (S.episode or 0) + 1
    S.hitFor = nil
  end
  local moving = false
  S.shownWas = S.shownWas or {}
  for _, sd in ipairs({ "player", "enemy" }) do
    local b = battle[sd]
    if b and b.shownHP and S.shownWas[sd] and b.shownHP < S.shownWas[sd] then
      moving = true
    end
    S.shownWas[sd] = b and b.shownHP or nil
  end
  local animEnd = drain and (not playing) and S.prev.playing
  local landed = (flash and not S.prev.flash) or (quake and not S.prev.quake)
                 or animEnd or (drain and moving)
  if landed and drain and S.hitFor == S.episode then landed = false end
  if landed then
    if drain then S.hitFor = S.episode end
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
  if not BattleGlassFX.ENABLED then return 0, 0, 0 end
  local t = now()
  local seed = S.bobSeed[id]
  if not seed then
    seed = ((id:byte(1) or 7) * 1.31 + #id * 2.7) % (2 * math.pi)
    S.bobSeed[id] = seed
  end
  local dU = BattleGlassFX.BOB
             * math.sin(t * 2 * math.pi / BattleGlassFX.BOB_PERIOD + seed)
  local dR = 0
  local tilt = 0
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
      local alongR = px * R.right[1] + py * R.right[2] + pz * R.right[3]
      dR = dR + mag * alongR
      dU = dU + mag * (px * R.up[1] + py * R.up[2] + pz * R.up[3])
      -- the turn: a push arriving across the pane's right yaws it about
      -- its up; a push straight at its face does not turn it at all
      tilt = -mag * alongR * BattleGlassFX.TILT
      if tilt > BattleGlassFX.TILT_MAX then tilt = BattleGlassFX.TILT_MAX
      elseif tilt < -BattleGlassFX.TILT_MAX then
        tilt = -BattleGlassFX.TILT_MAX end
      -- the front reaches this pane: one mark per wave per pane, and
      -- only a real hit leaves one (the telegraph is too soft)
      if S.reached[id] ~= w.id then
        S.reached[id] = w.id
        if (w.amp or 0) >= BattleGlassFX.SPLASH_MIN then
          local B = box()
          local kind = w.kind
          S.splash[id] = {
            born = t, kind = kind, amp = w.amp,
            physical = (kind == nil) or BattleGlassFX.PHYSICAL[kind] or false,
            color = (kind and B and B.TYPE_COLOR and B.TYPE_COLOR[kind])
                    or { 1, 1, 1 },
            ox = w.ox, oy = w.oy, oz = w.oz,
          }
        end
      end
    end
  end
  S.lastTilt[id] = tilt
  return dR, dU, tilt
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

-- ------- the chosen move's element, alive on its card
--
-- The card under the cursor is not a label with a colour: it is the
-- move, and the move's element runs on its glass. Three layers, all
-- through the pane mapper so they tilt and swing with the card:
--   the WEATHER  -- the element's own particles (the box's brushes,
--                   plus a few cut for the types the box never rains),
--   the CRAWL    -- one signature per type: lightning crawling the
--                   edges, flames licking the foot, a swell rolling the
--                   lower third, frost growing in from the corners,
--                   rings breathing out of the centre...,
--   the RUNNER   -- a bright bead of the element's colour running the
--                   perimeter, and an additive halo breathing outside it.
-- Keyed by card id so each card keeps its own particle pool.
BattleGlassFX.TYPE_WEATHER = {
  ELECTRIC = "spark", WATER = "drops", ICE = "frost", FIRE = "ember",
  POISON = "bubbles", ROCK = "debris", GROUND = "debris",
  GRASS = "leaves", BUG = "leaves", PSYCHIC = "rings", GHOST = "wisps",
  FLYING = "streaks", DRAGON = "ember", FIGHTING = "glint",
  NORMAL = "glint",
}

-- leaves: drift DOWN the card, swaying, in two greens
local function drawLeaves(key, map, ss, W, H, color)
  local p, dt = pool(key)
  p.acc = p.acc + dt * 4
  while p.acc >= 1 do
    p.acc = p.acc - 1
    local n = #p.list
    p.list[n + 1] = { x = (0.08 + 0.84 * prand(n, 2.1)) * W, y = -8,
                      vy = 55 + 40 * prand(n, 3.3), ph = prand(n, 4.4) * 6.28,
                      r = 4 + 3 * prand(n, 5.5), life = 3.2,
                      dark = prand(n, 6.6) < 0.5 }
  end
  local t = now()
  for i = #p.list, 1, -1 do
    local d = p.list[i]
    d.y = d.y + d.vy * dt
    d.x = d.x + math.sin(t * 2.2 + d.ph) * 40 * dt
    d.life = d.life - dt
    if d.life <= 0 or d.y > H + 10 then
      table.remove(p.list, i)
    else
      local sx, sy = map(d.x, d.y)
      if sx then
        local k = d.dark and 0.7 or 1.15
        g.setColor(color[1] * k, color[2] * k, color[3] * k, 0.9)
        g.push()
        g.translate(sx, sy)
        g.rotate(t * 3 + d.ph)
        g.ellipse("fill", 0, 0, d.r * ss, d.r * 0.45 * ss)
        g.pop()
      end
    end
  end
end

-- rings: breathing out of the centre, three at a time
local function drawRings(map, ss, W, H, color)
  local t = now()
  local cx, cy = W * 0.5, H * 0.5
  g.setLineWidth(math.max(1.5, 3 * ss))
  for k = 0, 2 do
    local f = ((t * 0.55) + k / 3) % 1
    local rad = f * W * 0.6
    local a = (1 - f) * 0.8
    local pts = {}
    for s = 0, 28 do
      local ang = s / 28 * 2 * math.pi
      local x, y = map(cx + math.cos(ang) * rad, cy + math.sin(ang) * rad * 1.3)
      if not x then pts = nil break end
      pts[#pts + 1] = x; pts[#pts + 1] = y
    end
    if pts and #pts >= 6 then
      g.setColor(color[1], color[2], color[3], a)
      g.line(pts)
    end
  end
  g.setLineWidth(1)
end

-- streaks: wind lines crossing the card, fast
local function drawStreaks(key, map, ss, W, H, color)
  local p, dt = pool(key)
  p.acc = p.acc + dt * 7
  while p.acc >= 1 do
    p.acc = p.acc - 1
    local n = #p.list
    p.list[n + 1] = { x = -30, y = (0.1 + 0.8 * prand(n, 7.7)) * H,
                      vx = 380 + 260 * prand(n, 8.8), len = 40 + 50 * prand(n, 9.9),
                      life = 1.2 }
  end
  g.setLineWidth(math.max(1, 2 * ss))
  for i = #p.list, 1, -1 do
    local d = p.list[i]
    d.x = d.x + d.vx * dt
    d.life = d.life - dt
    if d.x > W + 40 or d.life <= 0 then
      table.remove(p.list, i)
    else
      g.setColor(1, 1, 1, 0.55)
      line2(map, d.x - d.len, d.y, d.x, d.y)
      g.setColor(color[1], color[2], color[3], 0.5)
      line2(map, d.x - d.len * 0.5, d.y + 3, d.x, d.y + 3)
    end
  end
  g.setLineWidth(1)
end

-- glint: four-point sparkles popping about the face
local function drawGlint(map, ss, W, H, color)
  local t = now()
  for i = 1, 6 do
    local f = ((t * 0.9) + prand(i, 11.1)) % 1
    local x = (0.1 + 0.8 * prand(i, 12.2)) * W
    local y = (0.1 + 0.8 * prand(i, 13.3)) * H
    local s = math.sin(f * math.pi) * (10 + 8 * prand(i, 14.4))
    if s > 0.5 then
      g.setLineWidth(math.max(1, 2 * ss))
      g.setColor(1, 1, 1, 0.9)
      line2(map, x - s, y, x + s, y)
      line2(map, x, y - s, x, y + s)
      g.setColor(color[1], color[2], color[3], 0.7)
      line2(map, x - s * 0.5, y - s * 0.5, x + s * 0.5, y + s * 0.5)
      line2(map, x - s * 0.5, y + s * 0.5, x + s * 0.5, y - s * 0.5)
    end
  end
  g.setLineWidth(1)
end

-- a glowing stroke: a wide translucent pass, a mid pass, a white core.
-- Drawn additive by the callers, which is what makes it LIGHT rather
-- than paint: the wide pass bleeds into the glass, the core stays hot
local function glowLine(pts, color, width, ss, a)
  a = a or 1
  if #pts < 4 then return end
  g.setColor(color[1], color[2], color[3], 0.20 * a)
  g.setLineWidth(math.max(4, width * 4.0 * ss))
  g.line(pts)
  g.setColor(color[1], color[2], color[3], 0.55 * a)
  g.setLineWidth(math.max(2, width * 1.8 * ss))
  g.line(pts)
  g.setColor(1, 1, 1, 0.95 * a)
  g.setLineWidth(math.max(1, width * 0.75 * ss))
  g.line(pts)
  g.setLineWidth(1)
end

-- one jagged bolt from (x0,y0) to (x1,y1), `segs` kinks, seeded; with
-- `branch` a fork leaves one of the kinks at a slant, shorter
local function bolt(map, ss, x0, y0, x1, y1, segs, seed, color, width, branch)
  local pts = {}
  local dx, dy = x1 - x0, y1 - y0
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1 then return end
  local nx, ny = -dy / len, dx / len
  local kinks = {}
  for s = 0, segs do
    local f = s / segs
    local jag = (s > 0 and s < segs) and (prand(seed, s) - 0.5) * len * 0.26 or 0
    local wx, wy = x0 + dx * f + nx * jag, y0 + dy * f + ny * jag
    kinks[#kinks + 1] = { wx, wy }
    local x, y = map(wx, wy)
    if not x then return end
    pts[#pts + 1] = x; pts[#pts + 1] = y
  end
  glowLine(pts, color, width, ss)
  if branch and segs >= 3 then
    local k = kinks[2 + math.floor(prand(seed, 77) * (segs - 2))]
    local ang = math.atan2(dy, dx) + (prand(seed, 78) < 0.5 and -0.9 or 0.9)
    local bl = len * (0.25 + 0.25 * prand(seed, 79))
    bolt(map, ss, k[1], k[2], k[1] + math.cos(ang) * bl,
         k[2] + math.sin(ang) * bl, 4, seed + 5, color, width * 0.6, false)
  end
end

-- glowing rings breathing out of a point
local function glowRings(map, ss, cx, cy, reach, color, t, rate, n)
  for k = 0, (n or 3) - 1 do
    local f = ((t * (rate or 0.5)) + k / (n or 3)) % 1
    local rad = f * reach
    local a = (1 - f) * 0.9
    local pts = {}
    for s = 0, 30 do
      local ang = s / 30 * 2 * math.pi
      local x, y = map(cx + math.cos(ang) * rad, cy + math.sin(ang) * rad * 1.3)
      if not x then pts = nil break end
      pts[#pts + 1] = x; pts[#pts + 1] = y
    end
    if pts then glowLine(pts, color, 1.6, ss, a) end
  end
end

-- the pane's own corners, for fills
local function paneQuad(map, W, H, m)
  m = m or 0
  local x1, y1 = map(-m, -m); local x2, y2 = map(W + m, -m)
  local x3, y3 = map(W + m, H + m); local x4, y4 = map(-m, H + m)
  if x1 and x2 and x3 and x4 then
    return { x1, y1, x2, y2, x3, y3, x4, y4 }
  end
end

local CRAWL = {}
-- ELECTRIC: bolts crawling the edges, forking; a big one across now
-- and then, and the whole pane flashing white with it
CRAWL.ELECTRIC = function(map, ss, W, H, color, t)
  local frame = math.floor(t * 18)        -- re-seeded 18 times a second
  pcall(g.setBlendMode, "add", "alphamultiply")
  for k = 1, 4 do
    local seed = frame * 7 + k * 131
    local edge = math.floor(prand(seed, 1) * 4)
    local a, b = prand(seed, 2), prand(seed, 3)
    local lo, hi = math.min(a, b), math.max(a, b)
    if hi - lo < 0.18 then hi = math.min(1, lo + 0.18) end
    local x0, y0, x1, y1
    if edge == 0 then x0, y0, x1, y1 = lo * W, 6, hi * W, 6
    elseif edge == 1 then x0, y0, x1, y1 = W - 6, lo * H, W - 6, hi * H
    elseif edge == 2 then x0, y0, x1, y1 = lo * W, H - 6, hi * W, H - 6
    else x0, y0, x1, y1 = 6, lo * H, 6, hi * H end
    bolt(map, ss, x0, y0, x1, y1, 7, seed, color, 2.0, prand(seed, 4) < 0.6)
  end
  if prand(frame, 9) < 0.22 then
    local seed = frame * 3 + 17
    bolt(map, ss, prand(seed, 4) * W, 0, prand(seed, 5) * W, H, 11, seed,
         color, 3.0, true)
    local q = paneQuad(map, W, H)
    if q then
      g.setColor(1, 1, 1, 0.16)
      g.polygon("fill", q)
    end
  end
  -- static: a haze of tiny arcs at the corners
  for k = 1, 6 do
    local seed = frame * 5 + k * 17
    local cx = (prand(seed, 21) < 0.5) and 18 or W - 18
    local cy = (prand(seed, 22) < 0.5) and 18 or H - 18
    bolt(map, ss, cx, cy, cx + (prand(seed, 23) - 0.5) * 50,
         cy + (prand(seed, 24) - 0.5) * 50, 3, seed, color, 1.0, false)
  end
  pcall(g.setBlendMode, "alpha", "alphamultiply")
end
-- FIRE: tongues of flame in three layers licking up from the foot,
-- taller and hotter, with an additive bloom over the whole blaze
CRAWL.FIRE = function(map, ss, W, H, color, t)
  local n = 11
  local layers = {
    { 1.00, { 0.85, 0.12, 0.05 }, 0.85 },
    { 0.68, { 1.00, 0.50, 0.08 }, 0.90 },
    { 0.38, { 1.00, 0.92, 0.55 }, 0.95 },
  }
  for _, L in ipairs(layers) do
    local scale, col, alpha = L[1], L[2], L[3]
    for i = 1, n do
      local x = (i - 0.5) / n * W
      local ph = prand(i, 21.1) * 6.28
      local h = H * (0.14 + 0.22 * (0.5 + 0.5 * math.sin(t * 8 + ph))
                      * (0.55 + 0.45 * prand(i, 22.2))) * scale
      local w = W / n * 0.62 * (0.7 + 0.3 * scale)
      local sway = math.sin(t * 6 + ph * 2) * w * 0.5
      local ax, ay = map(x - w, H + 2)
      local bx, by = map(x + w, H + 2)
      local mx, my = map(x + sway * 0.5, H - h * 0.55)
      local cx, cy = map(x + sway, H - h)
      if ax and bx and cx and mx then
        g.setColor(col[1], col[2], col[3], alpha)
        g.polygon("fill", ax, ay, bx, by, cx, cy)
        g.polygon("fill", ax, ay, mx, my, cx, cy)
      end
    end
  end
  -- the bloom: additive orange over the foot, breathing with the flames
  pcall(g.setBlendMode, "add", "alphamultiply")
  local ax, ay = map(-10, H + 10); local bx, by = map(W + 10, H + 10)
  local cx, cy = map(W + 10, H * 0.55); local dx, dy = map(-10, H * 0.55)
  if ax and bx and cx and dx then
    g.setColor(1, 0.45, 0.1, 0.22 + 0.08 * math.sin(t * 9))
    g.polygon("fill", ax, ay, bx, by, cx, cy, dx, dy)
  end
  -- sparks leaping off the tips
  local frame = math.floor(t * 12)
  for k = 1, 6 do
    local seed = frame * 3 + k * 41
    local sx, sy = map((0.05 + 0.9 * prand(seed, 1)) * W,
                       H * (0.45 + 0.3 * prand(seed, 2)))
    if sx then
      g.setColor(1, 0.85, 0.4, 0.9)
      g.circle("fill", sx, sy, (2 + 2 * prand(seed, 3)) * ss)
    end
  end
  pcall(g.setBlendMode, "alpha", "alphamultiply")
end
-- WATER: two swells rolling the lower third, foam crests glowing,
-- and a caustic shimmer above the water line
CRAWL.WATER = function(map, ss, W, H, color, t)
  local function swell(base, amp, speed, alpha, crestW)
    local fill, crest = {}, {}
    for s = 0, 28 do
      local f = s / 28
      local y = base + math.sin(f * 6.28 * 1.5 - t * speed) * H * amp
                + math.sin(f * 6.28 * 3.3 + t * speed * 0.7) * H * amp * 0.45
      local x, yy = map(f * W, y)
      if not x then return end
      crest[#crest + 1] = x; crest[#crest + 1] = yy
      fill[#fill + 1] = x; fill[#fill + 1] = yy
    end
    local bx, by = map(W, H + 2); local ax, ay = map(0, H + 2)
    if not (bx and ax) then return end
    fill[#fill + 1] = bx; fill[#fill + 1] = by
    fill[#fill + 1] = ax; fill[#fill + 1] = ay
    g.setColor(color[1] * 0.8, color[2] * 0.9, color[3], alpha)
    pcall(g.polygon, "fill", fill)
    pcall(g.setBlendMode, "add", "alphamultiply")
    glowLine(crest, { 0.8, 0.95, 1 }, crestW, ss, 0.9)
    pcall(g.setBlendMode, "alpha", "alphamultiply")
  end
  swell(H * 0.62, 0.05, 2.6, 0.40, 1.4)
  swell(H * 0.74, 0.04, 3.4, 0.55, 2.0)
  -- caustics: wandering bright arcs above the water line
  pcall(g.setBlendMode, "add", "alphamultiply")
  for k = 1, 5 do
    local ph = prand(k, 33.3) * 6.28
    local cx = (0.15 + 0.7 * prand(k, 34.4)) * W + math.sin(t * 1.3 + ph) * 18
    local cy = H * (0.15 + 0.35 * prand(k, 35.5)) + math.cos(t * 1.1 + ph) * 12
    local pts = {}
    for s = 0, 8 do
      local a = ph + s / 8 * 2.4 + t * 0.8
      local x, y = map(cx + math.cos(a) * 16, cy + math.sin(a) * 9)
      if not x then pts = nil break end
      pts[#pts + 1] = x; pts[#pts + 1] = y
    end
    if pts then glowLine(pts, { 0.7, 0.9, 1 }, 1.0, ss, 0.5 + 0.3 * math.sin(t * 3 + ph)) end
  end
  pcall(g.setBlendMode, "alpha", "alphamultiply")
end
-- ICE: frost growing in from every corner, glowing, and a cold
-- vignette breathing at the edges, with snow drifting down
CRAWL.ICE = function(map, ss, W, H, color, t)
  pcall(g.setBlendMode, "add", "alphamultiply")
  local grow = 0.55 + 0.35 * math.sin(t * 1.5)
  for i = 1, 12 do
    local corner = i % 4
    local x = (corner == 0 or corner == 3) and 10 + 40 * prand(i, 4.2)
              or W - 10 - 40 * prand(i, 4.2)
    local y = (corner <= 1) and 10 + 50 * prand(i, 8.4)
              or H - 10 - 50 * prand(i, 8.4)
    local len = (10 + 14 * prand(i, 7.3)) * grow
    for k = 0, 5 do
      local a = k * math.pi / 3 + i * 0.4
      local pts = {}
      local x0, y0 = map(x, y)
      local x1, y1 = map(x + math.cos(a) * len, y + math.sin(a) * len)
      if x0 and x1 then
        glowLine({ x0, y0, x1, y1 }, { 0.85, 0.97, 1 }, 1.0, ss, 0.8)
        -- the little side spurs of a snowflake
        local mx, my = x + math.cos(a) * len * 0.6, y + math.sin(a) * len * 0.6
        local sx0, sy0 = map(mx, my)
        local sx1, sy1 = map(mx + math.cos(a + 0.9) * len * 0.3,
                             my + math.sin(a + 0.9) * len * 0.3)
        if sx0 and sx1 then
          glowLine({ sx0, sy0, sx1, sy1 }, { 0.85, 0.97, 1 }, 0.7, ss, 0.6)
        end
      end
    end
  end
  -- the cold at the edges
  local q = paneQuad(map, W, H, 4)
  if q then
    g.setColor(0.6, 0.9, 1, 0.10 + 0.05 * math.sin(t * 2))
    g.setLineWidth(math.max(6, 26 * ss))
    g.polygon("line", q)
    g.setLineWidth(1)
  end
  pcall(g.setBlendMode, "alpha", "alphamultiply")
end
-- PSYCHIC / DRAGON: glowing rings out of the centre and a spiral of
-- motes wheeling round it
CRAWL.PSYCHIC = function(map, ss, W, H, color, t)
  pcall(g.setBlendMode, "add", "alphamultiply")
  glowRings(map, ss, W * 0.5, H * 0.5, W * 0.62, color, t, 0.55, 4)
  for k = 1, 18 do
    local f = (k / 18 + t * 0.12) % 1
    local a = f * 6.28 * 2.2 + t * 1.6
    local r = f * W * 0.48
    local x, y = map(W * 0.5 + math.cos(a) * r, H * 0.5 + math.sin(a) * r * 1.3)
    if x then
      g.setColor(1, 1, 1, 0.9 * (1 - f))
      g.circle("fill", x, y, (2 + 3 * (1 - f)) * ss)
      g.setColor(color[1], color[2], color[3], 0.5 * (1 - f))
      g.circle("fill", x, y, (5 + 5 * (1 - f)) * ss)
    end
  end
  pcall(g.setBlendMode, "alpha", "alphamultiply")
end
CRAWL.DRAGON = CRAWL.PSYCHIC
-- GHOST: a violet vignette that flickers, and a slow dark swirl with
-- two pale eyes drifting through it
CRAWL.GHOST = function(map, ss, W, H, color, t)
  local a = 0.22 + 0.14 * math.sin(t * 9) * math.sin(t * 3.7)
  local q = paneQuad(map, W, H)
  if q then
    g.setColor(color[1] * 0.5, color[2] * 0.3, color[3] * 0.7, a)
    g.polygon("fill", q)
  end
  pcall(g.setBlendMode, "add", "alphamultiply")
  for k = 0, 2 do
    local pts = {}
    for s = 0, 24 do
      local f = s / 24
      local ang = f * 6.28 * 1.5 + t * 0.9 + k * 2.1
      local r = f * W * 0.4
      local x, y = map(W * 0.5 + math.cos(ang) * r, H * 0.5 + math.sin(ang) * r * 1.3)
      if not x then pts = nil break end
      pts[#pts + 1] = x; pts[#pts + 1] = y
    end
    if pts then glowLine(pts, color, 1.2, ss, 0.35) end
  end
  local ex = W * 0.5 + math.sin(t * 0.7) * W * 0.2
  local ey = H * 0.4 + math.cos(t * 0.5) * H * 0.15
  for _, off in ipairs({ -14, 14 }) do
    local x, y = map(ex + off, ey)
    if x then
      g.setColor(0.9, 0.85, 1, 0.55 + 0.35 * math.sin(t * 5))
      g.circle("fill", x, y, 4 * ss)
    end
  end
  pcall(g.setBlendMode, "alpha", "alphamultiply")
end
-- FIGHTING: impact bursts with a shock ring, popping about the face
CRAWL.FIGHTING = function(map, ss, W, H, color, t)
  pcall(g.setBlendMode, "add", "alphamultiply")
  for b = 0, 1 do
    local frame = math.floor(t * 3.5 + b * 0.5)
    local f = (t * 3.5 + b * 0.5) % 1
    local x = (0.15 + 0.7 * prand(frame, 31 + b)) * W
    local y = (0.15 + 0.7 * prand(frame, 32 + b)) * H
    local r = (1 - f) * 34 + 6
    for k = 0, 9 do
      local a = k * math.pi / 5 + f * 0.8
      local x0, y0 = map(x + math.cos(a) * r * 0.35, y + math.sin(a) * r * 0.35)
      local x1, y1 = map(x + math.cos(a) * r, y + math.sin(a) * r)
      if x0 and x1 then
        glowLine({ x0, y0, x1, y1 }, color, 1.6, ss, (1 - f))
      end
    end
    glowRings(map, ss, x, y, 60, color, t * 0 + f, 1, 1)
  end
  pcall(g.setBlendMode, "alpha", "alphamultiply")
end
-- ROCK / GROUND: a dust band settling along the foot, cracks in the
-- glass that stay, and a tremor of grit
CRAWL.ROCK = function(map, ss, W, H, color, t)
  local ax, ay = map(0, H); local bx, by = map(W, H)
  local cx, cy = map(W, H * 0.78); local dx, dy = map(0, H * 0.78)
  if ax and bx and cx and dx then
    g.setColor(color[1], color[2], color[3], 0.34 + 0.08 * math.sin(t * 2))
    g.polygon("fill", ax, ay, bx, by, cx, cy, dx, dy)
  end
  g.setLineWidth(math.max(1.5, 2.5 * ss))
  for i = 1, 4 do
    local x0 = (0.1 + 0.8 * prand(i, 51)) * W
    local y0 = (0.1 + 0.8 * prand(i, 52)) * H
    local x, y = x0, y0
    for s = 1, 5 do
      local nx = x + (prand(i, 53 + s) - 0.5) * 40
      local ny = y + (prand(i, 60 + s) - 0.5) * 40
      g.setColor(0.1, 0.08, 0.05, 0.7)
      line2(map, x, y, nx, ny)
      x, y = nx, ny
    end
  end
  g.setLineWidth(1)
end
CRAWL.GROUND = CRAWL.ROCK

local POOLED = { leaves = true, streaks = true, wisps = true, drops = true,
                 ember = true, bubbles = true, debris = true, spark = true }
local function typeWeather(key, kind, map, ss, W, H, color)
  if kind == "leaves" then drawLeaves(key, map, ss, W, H, color)
  elseif kind == "rings" then drawRings(map, ss, W, H, color)
  elseif kind == "streaks" then drawStreaks(key, map, ss, W, H, color)
  elseif kind == "glint" then drawGlint(map, ss, W, H, color)
  elseif kind == "wisps" then
    drawRisers(key, map, ss, W, H, color,
               { rate = 6, vy0 = 18, vy1 = 26, r0 = 6, r1 = 8,
                 wobble = true, hollow = true })
  else
    local fn = KIND_DRAW[kind]
    if fn then fn(key, map, ss, W, H, color, 1) end
  end
end

-- `mode` "frame" draws only the halo, the runners and the glints -- the
-- frame around the authored sheets BattleCardFX plays; nil draws the
-- primitive weather and crawl too (kept for a type with no sheet)
function BattleGlassFX.overlayType(id, map, ss, W, H, tname, strength, mode)
  if not BattleGlassFX.ENABLED then return false end
  if not (id and map and W and H and W > 0 and H > 0) then return false end
  strength = strength or 1
  if strength <= 0.01 then return false end
  local frameOnly = (mode == "frame")
  local ok, err = pcall(function()
    g = love.graphics
    local t = now()
    local B = box()
    local color = (tname and B and B.TYPE_COLOR and B.TYPE_COLOR[tname])
                  or { 1, 0.84, 0.4 }
    local prevBlend, prevA = g.getBlendMode()
    local prevW = g.getLineWidth()
    -- the halo: three breathing layers outside the glass, additive,
    -- and the colour glowing in from the rim
    pcall(g.setBlendMode, "add", "alphamultiply")
    local breath = 0.6 + 0.4 * math.sin(t * 4.1)
    for _, L in ipairs({ { 18, 0.26 }, { 40, 0.14 }, { 68, 0.07 } }) do
      local q = paneQuad(map, W, H, L[1] + 8 * breath)
      if q then
        g.setColor(color[1], color[2], color[3], L[2] * breath * strength)
        g.polygon("fill", q)
      end
    end
    local q = paneQuad(map, W, H, 2)
    if q then
      g.setColor(color[1], color[2], color[3], 0.30 * breath * strength)
      g.setLineWidth(math.max(6, 22 * ss))
      g.polygon("line", q)
      g.setLineWidth(1)
    end
    -- the weather, twice over for density, then the type's crawl
    pcall(g.setBlendMode, "alpha", "alphamultiply")
    if not frameOnly then
      local kind = tname and BattleGlassFX.TYPE_WEATHER[tname] or "glint"
      typeWeather(id .. ":type:" .. kind, kind, map, ss, W, H, color)
      if POOLED[kind] then
        typeWeather(id .. ":type2:" .. kind, kind, map, ss, W, H, color)
      end
      local crawl = tname and CRAWL[tname]
      if crawl then crawl(map, ss, W, H, color, t) end
    end
    -- sparkles over every element
    pcall(g.setBlendMode, "add", "alphamultiply")
    drawGlint(map, ss, W, H, color)
    -- the runners: two beads of the colour chasing round the perimeter
    -- with long glowing tails
    local per = 2 * (W + H)
    local function at(d)
      d = d % per
      if d < W then return d, 0
      elseif d < W + H then return W, d - W
      elseif d < 2 * W + H then return W - (d - W - H), H
      else return 0, H - (d - 2 * W - H) end
    end
    for bead = 0, 1 do
      local head = (t * 1.1 * per + bead * per * 0.5) % per
      local pts = {}
      for k = 0, 16 do
        local x, y = at(head - k * 12)
        local sx, sy = map(x, y)
        if not sx then pts = nil break end
        pts[#pts + 1] = sx; pts[#pts + 1] = sy
      end
      if pts then
        -- the tail fades: drawn in three chunks of falling alpha
        for c = 0, 2 do
          local seg = {}
          for k = c * 10 + 1, math.min(#pts, c * 10 + 12) do seg[#seg + 1] = pts[k] end
          if #seg >= 4 then
            glowLine(seg, color, 2.6 - c * 0.7, ss, (1 - c * 0.3) * strength)
          end
        end
        local hx, hy = pts[1], pts[2]
        g.setColor(1, 1, 1, 0.95 * strength)
        g.circle("fill", hx, hy, 4 * ss)
        g.setColor(color[1], color[2], color[3], 0.5 * strength)
        g.circle("fill", hx, hy, 9 * ss)
      end
    end
    g.setLineWidth(prevW or 1)
    if prevA ~= nil then pcall(g.setBlendMode, prevBlend, prevA)
    else pcall(g.setBlendMode, prevBlend or "alpha") end
    g.setColor(1, 1, 1, 1)
  end)
  if not ok then
    S.typeErr = tostring(err)
    pcall(love.graphics.setColor, 1, 1, 1, 1)
    return false
  end
  S.typeDraws = (S.typeDraws or 0) + 1
  S.typeLast = tname
  return true
end

function BattleGlassFX.typeDebug()
  return { draws = S.typeDraws or 0, last = S.typeLast, err = S.typeErr }
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

-- ------- the mark the wave leaves on a pane
--
-- Where the front struck is the point of the pane nearest the wave's
-- origin, found on screen: the origin projected, clamped into the pane's
-- own footprint, read back as pane pixels. A physical blow CRACKS the
-- glass from there -- jagged white lines that shoot out in the first
-- tenth of a second and fade; an elemental one RIPPLES it -- rings in
-- the element's colour spreading from the point -- and both wash the
-- pane in the colour for a few frames. `proj` maps a world point to the
-- screen (the rig's own project); without it the mark lands mid-pane.
local function paneBody(id, map, ss, W, H, proj)
  if not BattleGlassFX.ENABLED then return false end
  local sp = id and S.splash[id]
  if not sp then return false end
  local t = now()
  local age = t - sp.born
  local life = BattleGlassFX.SPLASH_LIFE
  if age < 0 or age > life then return false end
  if not (map and W and H and W > 0 and H > 0) then return false end
  g = love.graphics

  -- the strike point, in pane pixels
  local ix, iy = W * 0.5, H * 0.5
  if not sp.px then
    -- (`proj and proj(...)` would keep ONE return value -- Lua's `and`
    -- truncates a call's list -- so the branch is spelled out)
    local ox, oy
    if proj then ox, oy = proj({ sp.ox, sp.oy, sp.oz }) end
    local ax, ay = map(0, 0)
    local bx, by = map(W, 0)
    local cx, cy = map(W, H)
    local dx, dy = map(0, H)
    if ox and ax and bx and cx and dx then
      local x0 = math.min(ax, bx, cx, dx)
      local x1 = math.max(ax, bx, cx, dx)
      local y0 = math.min(ay, by, cy, dy)
      local y1 = math.max(ay, by, cy, dy)
      local u = (x1 > x0) and (ox - x0) / (x1 - x0) or 0.5
      local v = (y1 > y0) and (oy - y0) / (y1 - y0) or 0.5
      u = math.max(0.06, math.min(0.94, u))
      v = math.max(0.08, math.min(0.92, v))
      ix, iy = u * W, v * H
    end
    sp.px, sp.py = ix, iy
  else
    ix, iy = sp.px, sp.py
  end

  local col = sp.color or { 1, 1, 1 }
  local fade = 1 - age / life
  local amp = math.min(1.6, sp.amp or 1)
  local seed = math.floor(sp.born * 37)
  local prevBlend, prevA = g.getBlendMode()
  local prevW = g.getLineWidth()

  -- the wash: the whole pane takes the colour for a few frames. Plain
  -- alpha, not additive -- the glass is light, and light added to
  -- light is nothing
  local wash = math.max(0, 1 - age / 0.32)
  if wash > 0 then
    pcall(g.setBlendMode, "alpha", "alphamultiply")
    local pts = {}
    local ax, ay = map(0, 0); local bx, by = map(W, 0)
    local cx, cy = map(W, H); local dx, dy = map(0, H)
    if ax and bx and cx and dx then
      pts = { ax, ay, bx, by, cx, cy, dx, dy }
      g.setColor(col[1], col[2], col[3], 0.34 * wash * amp)
      pcall(g.polygon, "fill", pts)
    end
  end

  if sp.physical then
    -- cracks: each shoots out to its full length in the first 0.12 s
    pcall(g.setBlendMode, "alpha", "alphamultiply")
    local grow = math.min(1, age / 0.12)
    local n = 7
    local reach = math.max(W, H) * (0.34 + 0.22 * amp)
    for i = 1, n do
      local a = (i / n) * 2 * math.pi + prand(seed, i) * 0.8
      local len = reach * (0.55 + 0.45 * prand(seed, i + 40)) * grow
      local x, y = ix, iy
      local pts = { x, y }
      local k = 4
      for s = 1, k do
        local f = s / k
        local jag = (prand(seed, i * 9 + s) - 0.5) * len * 0.22
        local ca, sa = math.cos(a), math.sin(a)
        x = ix + ca * len * f - sa * jag
        y = iy + sa * len * f + ca * jag
        pts[#pts + 1] = x
        pts[#pts + 1] = y
      end
      -- through the mapper, so the crack lies IN the glass
      local scr = {}
      for p = 1, #pts, 2 do
        local sx, sy = map(pts[p], pts[p + 1])
        if not sx then scr = nil break end
        scr[#scr + 1] = sx
        scr[#scr + 1] = sy
      end
      if scr and #scr >= 4 then
        -- ink first: the glass is light, and a crack in light glass is
        -- a dark line with a bright edge, not a white one
        g.setColor(0.08, 0.08, 0.11, 0.80 * fade)
        g.setLineWidth(math.max(2.5, 6 * ss))
        pcall(g.line, scr)
        g.setColor(col[1] * 0.4 + 0.6, col[2] * 0.4 + 0.6,
                   col[3] * 0.4 + 0.6, 0.95 * fade)
        g.setLineWidth(math.max(1, 2 * ss))
        pcall(g.line, scr)
      end
    end
    -- the strike itself: a bright fleck that shrinks
    local fx, fy = map(ix, iy)
    if fx then
      local r = (8 + 10 * amp) * ss * math.max(0, 1 - age / 0.25)
      if r > 0.5 then
        pcall(g.setBlendMode, "add", "alphamultiply")
        g.setColor(1, 1, 1, 0.9)
        pcall(g.circle, "fill", fx, fy, r)
      end
    end
  else
    -- ripples: three rings, born a beat apart, spreading and thinning.
    -- Plain alpha in the element's colour over an ink ring, for the same
    -- reason as the cracks: additive light vanishes on light glass
    pcall(g.setBlendMode, "alpha", "alphamultiply")
    -- held to the pane: the mapper extrapolates past the glass, and a
    -- ring that leaves it stops being a ripple IN it
    local reach = math.max(W, H) * (0.5 + 0.12 * amp)
    for ring = 0, 2 do
      local ra = age - ring * 0.11
      if ra > 0 then
        local f = ra / (life - ring * 0.11)
        if f < 1 then
          local rad = reach * (1 - (1 - f) * (1 - f))
          local a = (1 - f) * 0.7
          local pts = {}
          local segs = 26
          for s = 0, segs do
            local ang = s / segs * 2 * math.pi
            local sx, sy = map(ix + math.cos(ang) * rad,
                               iy + math.sin(ang) * rad * 0.82)
            if not sx then pts = nil break end
            pts[#pts + 1] = sx
            pts[#pts + 1] = sy
          end
          if pts and #pts >= 6 then
            g.setColor(0.08, 0.08, 0.11, a * 0.7)
            g.setLineWidth(math.max(2.5, (6 - ring) * ss))
            pcall(g.line, pts)
            g.setColor(col[1], col[2], col[3], a)
            g.setLineWidth(math.max(1.2, (3.5 - ring * 0.7) * ss))
            pcall(g.line, pts)
          end
        end
      end
    end
  end

  g.setLineWidth(prevW or 1)
  if prevA ~= nil then pcall(g.setBlendMode, prevBlend, prevA)
  else pcall(g.setBlendMode, prevBlend or "alpha") end
  g.setColor(1, 1, 1, 1)
  S.paneDraws = (S.paneDraws or 0) + 1
  S.lastPane = { id = id, ix = ix, iy = iy, age = age,
                 physical = sp.physical and true or false }
  return true
end

-- guarded here as well as at the callers, so a brush that throws is
-- READABLE (paneDebug) rather than a pane that quietly never marks
function BattleGlassFX.overlayPane(id, map, ss, W, H, proj)
  local ok, drew = pcall(paneBody, id, map, ss, W, H, proj)
  if not ok then
    S.paneErr = tostring(drew)
    pcall(love.graphics.setColor, 1, 1, 1, 1)
    return false
  end
  return drew
end

function BattleGlassFX.paneDebug()
  return { draws = S.paneDraws or 0, last = S.lastPane, err = S.paneErr }
end

return BattleGlassFX
