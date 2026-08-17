-- Voxel world mode: the wind you can SEE.
--
-- Wind.lua bends the grass; this file fills the air when grass is not on
-- screen. Particles are cel-hard grit, seeds and dashes (assets/vfx/wind_*.png,
-- authored by tools/make_wind_sprites.py) -- not soft photo-smoke circles.
--
-- Kinds (picked by weather + wind strength):
--   grit    tiny hard dust pixels low over the ground (dry air)
--   seed    elongated pollen/seed mid height (dry breeze+)
--   dash    velocity-aligned streak (gale / gust front)
--   spray   seed-shaped, rain-tinted (shower)
--   snow    grit-shaped, white (snow)
--
-- Gust front: rank of dashes + a short curl frame strip, same Wind.gust
-- envelope the grass already bows to.

local V = ...

local DayNight = V.require("DayNight")
local Wind = V.require("Wind")
local Weather = V.require("Weather")
local Quality = V.require("Quality")

local Map = require("src.world.Map")

local WindFX = {}

local function game()
  return require("src.core.Game")
end

local rand = love.math.random

-- Below this tip-reach the air shows nothing. Calm stays calm.
WindFX.FLOOR = 0.48

WindFX.MAX = 140               -- hard ceiling; Quality.windStreaks cuts by RES
WindFX.REACH = 12
WindFX.SPAWN_AHEAD = 5
WindFX.SPAWN_WIDE = 8
WindFX.SPEED = 28              -- world px/s per unit Wind.amount
WindFX.TAIL = 0.14

WindFX.FRONT_AT = 0.70
WindFX.FRONT_WAIT = 2.5
WindFX.FRONT_WIDE = 8
WindFX.FRONT_N = 8

-- Flat palettes on the 5-bit lattice. Dust has several warm greys so a
-- field of grit is not one identical tint; spray/snow stay singular.
WindFX.DUST = { 0.92, 0.86, 0.68 }
WindFX.DUST_B = { 0.86, 0.78, 0.58 }   -- dirtier
WindFX.DUST_C = { 0.96, 0.92, 0.80 }   -- pale sand
WindFX.DUST_D = { 0.78, 0.70, 0.52 }   -- dark grit
WindFX.SEED = { 0.78, 0.84, 0.55 }
WindFX.SEED_B = { 0.88, 0.76, 0.42 }   -- dry chaff
WindFX.SPRAY = { 0.72, 0.82, 0.96 }
WindFX.BLOWN = { 0.96, 0.97, 1.00 }
WindFX.DASH = { 0.94, 0.90, 0.80 }
WindFX.LEAF = {
  { 1.00, 1.00, 1.00 },
  { 0.82, 1.10, 0.52 },
  { 1.15, 1.02, 0.40 },
  { 1.12, 0.50, 0.28 },
  { 0.70, 0.42, 0.24 },
  { 0.95, 0.34, 0.26 },
  { 0.55, 0.75, 0.32 },
  { 0.80, 0.62, 0.36 },
}

local motes = {}
local frontCool = 0

local imgs = nil     -- { grit, seed, dash, swirl, swirlQ, swirlN } | false

local function loadImgs()
  if imgs ~= nil then return imgs or nil end
  local function one(name)
    local path = V.path .. "/assets/vfx/" .. name
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then
      pcall(img.setFilter, img, "nearest", "nearest")
      return img
    end
    return nil
  end
  local grit = one("wind_dust.png")
  local seed = one("wind_mote.png")
  local dash = one("wind_streak.png")
  local puff = one("wind_puff.png")
  local swirl = one("wind_swirl.png")
  local leaves = one("leaves.png")
  local swirlQ, swirlN = nil, 0
  if swirl then
    local fh = swirl:getHeight()
    swirlN = math.max(1, math.floor(swirl:getWidth() / math.max(1, fh)))
    swirlQ = {}
    for i = 0, swirlN - 1 do
      swirlQ[i] = love.graphics.newQuad(i * fh, 0, fh, fh, swirl:getDimensions())
    end
  end
  if not (grit or seed or dash or swirl or puff) then
    imgs = false
    return nil
  end
  local leafQ, leafN = nil, 0
  if leaves then
    local fw = 16
    leafN = math.max(1, math.floor(leaves:getWidth() / fw))
    leafQ = {}
    for i = 0, leafN - 1 do
      leafQ[i] = love.graphics.newQuad(i * fw, 0, fw, fw, leaves:getDimensions())
    end
  end
  imgs = {
    grit = grit, seed = seed or grit, dash = dash or seed,
    puff = puff, swirl = swirl, swirlQ = swirlQ, swirlN = swirlN,
    leaves = leaves, leafQ = leafQ, leafN = leafN,
  }
  return imgs
end

local function openSky(map)
  if not (map and map.def) then return false end
  if not Map.isOutdoor(map.def) then return false end
  return not DayNight.isCanopy(map)
end

-- What the air carries + palette + brightness.
local function climate()
  local kind = Weather.visible()
  if kind == "rain" then return "spray", WindFX.SPRAY, 0.72 end
  if kind == "snow" then return "snow", WindFX.BLOWN, 0.88 end
  return "dry", WindFX.DUST, 0.78
end

local function budget()
  local n = WindFX.MAX
  local ok, q = pcall(Quality.windStreaks)
  if ok and tonumber(q) then n = math.floor(q) end
  if n < 0 then n = 0 end
  if n > WindFX.MAX then n = WindFX.MAX end
  return n
end

-- Pick a particle kind that makes sense for this climate and wind strength.
-- Stronger wind → more seeds/dashes mixed in; weak breeze stays mostly grit.
local function pickKind(amount, front, climateKind)
  if front then return "dash" end
  if climateKind == "rain" then
    return rand() < 0.75 and "spray" or "dash"
  end
  if climateKind == "snow" then
    return rand() < 0.80 and "snow" or "dash"
  end
  local r = rand()
  if amount < 0.75 then
    -- light air: almost all grit, rare seed / one lost leaf
    if r < 0.78 then return "grit" end
    if r < 0.90 then return "puff" end
    if r < 0.97 then return "seed" end
    return "leaf"
  elseif amount < 1.40 then
    if r < 0.38 then return "grit" end
    if r < 0.52 then return "puff" end
    if r < 0.70 then return "seed" end
    if r < 0.88 then return "leaf" end
    return "dash"
  else
    -- gale: the air is full of what the trees just lost
    if r < 0.18 then return "grit" end
    if r < 0.28 then return "puff" end
    if r < 0.42 then return "seed" end
    if r < 0.82 then return "leaf" end
    return "dash"
  end
end

local function dustTint()
  local r = rand()
  if r < 0.28 then return WindFX.DUST end
  if r < 0.52 then return WindFX.DUST_B end
  if r < 0.76 then return WindFX.DUST_C end
  return WindFX.DUST_D
end

local function seedTint()
  return (rand() < 0.55) and WindFX.SEED or WindFX.SEED_B
end

local function spawn(px, pz, amount, opts)
  if #motes >= budget() then return end
  opts = opts or {}
  local dx, dz = Wind.DIR[1] or 1, Wind.DIR[2] or 0
  local back = (opts.back or WindFX.SPAWN_AHEAD) * 16
  -- wider scatter when the wind is hard so the stream fills the view
  local wide = WindFX.SPAWN_WIDE * (0.75 + 0.55 * math.min(1.4, amount))
  local side = (opts.side ~= nil) and opts.side
               or (rand() * 2 - 1) * wide * 16
  local x = px - dx * back - dz * side
  local z = pz - dz * back + dx * side
  local climateKind = opts.climate or "dry"
  local kind = opts.kind or pickKind(amount, opts.front, climateKind)

  -- Height by kind: grit skims the grass, seeds float mid, dashes higher.
  local y
  if kind == "grit" or kind == "snow" then
    y = 1.8 + rand() * 6
  elseif kind == "puff" then
    y = 3 + rand() * 8
  elseif kind == "leaf" then
    y = 6 + rand() * 18
  elseif kind == "seed" or kind == "spray" then
    y = 5 + rand() * 12
  else
    y = 5 + rand() * 14
  end

  local tint
  if kind == "grit" or kind == "puff" then
    tint = dustTint()
  elseif kind == "seed" then
    tint = seedTint()
  elseif kind == "leaf" then
    tint = WindFX.LEAF[rand(1, #WindFX.LEAF)]
  end

  motes[#motes + 1] = {
    x = x, z = z, y = y,
    kind = kind,
    seed = rand() * 6.2831,
    t = 0,
    ttl = (kind == "dash" and (1.0 + rand() * 1.1))
       or (kind == "grit" and (1.2 + rand() * 1.6))
       or (kind == "puff" and (1.3 + rand() * 1.5))
       or (kind == "leaf" and (2.2 + rand() * 2.8))
       or (1.6 + rand() * 2.2),
    fast = 0.55 + rand() * 0.90,
    lift = (rand() * 2 - 1) * (kind == "dash" and 3 or (kind == "leaf" and 8 or 6)),
    spin = (rand() * 2 - 1) * ((kind == "leaf" and (3.5 + rand() * 5))
                            or ((kind == "seed" or kind == "puff") and 4.5 or 1.6)),
    frame = kind == "leaf" and rand(0, 15) or 0,
    flip = rand() < 0.5 and -1 or 1,
    front = opts.front or false,
    -- wide size range so a cloud of grit is not one stamp
    size = 0.45 + rand() * 1.05,
    tint = tint,
  }
end

local function spawnFront(px, pz, amount, climateKind)
  local n = WindFX.FRONT_N
  if n < 1 then return end
  local cap = budget()
  local wide = WindFX.FRONT_WIDE * 16
  for i = 1, n do
    if #motes >= cap then break end
    local f = (n > 1) and ((i - 1) / (n - 1) * 2 - 1) or 0
    spawn(px, pz, amount, {
      back = WindFX.SPAWN_AHEAD + 1.5,
      side = f * wide + (rand() * 2 - 1) * 8,
      front = true,
      kind = "dash",
      climate = climateKind,
    })
  end
end

function WindFX.clear()
  if #motes > 0 then motes = {} end
end

function WindFX.update(dt, voxelOn)
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
  frontCool = frontCool - dt

  local amount = 0
  local okA, n = pcall(Wind.amount)
  if okA then amount = n or 0 end

  local cap = budget()
  local Game = game()
  local ow = Game and Game.overworld
  local live = voxelOn and cap > 0 and amount > WindFX.FLOOR
                and ow and ow.map and ow.player
                and openSky(ow.map)
                and Game.stack and Game.stack:top() == ow
                and not ow.transitioning
  if not live then
    WindFX.clear()
    return
  end

  local climateKind = select(1, climate())
  local p = ow.player
  local px, pz = p.cellX * 16, p.cellY * 16

  -- Density scales hard with wind: weak breeze = a few specks, gale = a
  -- stream. Quadratic so the middle of AUTO does not already look full.
  local headroom = math.max(0, cap - WindFX.FRONT_N)
  local t = (amount - WindFX.FLOOR) / 1.35
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  local want = math.floor(2 + (t * t) * (headroom - 2))
  if want > headroom then want = headroom end
  if want < 0 then want = 0 end
  local standing = 0
  for i = 1, #motes do
    if not motes[i].front then standing = standing + 1 end
  end
  -- refill faster under a gale so the field stays dense as motes expire
  local burst = 2 + math.floor(t * 10)
  for _ = 1, math.min(burst, math.max(0, want - standing)) do
    spawn(px, pz, amount, { climate = climateKind })
  end

  local gust = 0
  local okG, g = pcall(Wind.gust)
  if okG then gust = g or 0 end
  if gust >= WindFX.FRONT_AT and frontCool <= 0 then
    frontCool = WindFX.FRONT_WAIT
    spawnFront(px, pz, amount, climateKind)
  end

  local dx, dz = Wind.DIR[1] or 1, Wind.DIR[2] or 0
  local speed = amount * WindFX.SPEED
  local reach = WindFX.REACH * 16 + 48
  for i = #motes, 1, -1 do
    local m = motes[i]
    m.t = m.t + dt
    local v = speed * m.fast
    -- grit slower and more ground-bound; dashes ride the full wind
    if m.kind == "grit" or m.kind == "snow" then
      v = v * 0.68
    elseif m.kind == "puff" then
      v = v * 0.85
    elseif m.kind == "leaf" then
      v = v * (0.78 + 0.20 * math.sin(m.t * 3.1 + m.seed))
    elseif m.kind == "dash" then
      v = v * 1.18
    end
    -- curl across bearing: air tumbles; dead-straight = bullets
    local curl = math.sin(m.t * 2.1 + m.seed) * 0.28
               + math.sin(m.t * 4.6 + m.seed * 1.7) * 0.12
    m.vx = dx * v - dz * v * curl
    m.vz = dz * v + dx * v * curl
    m.x = m.x + m.vx * dt
    m.z = m.z + m.vz * dt
    -- bob: seeds/puffs tumble more; grit barely
    local bob = 3.0
    if m.kind == "leaf" then bob = 9.5
    elseif m.kind == "seed" or m.kind == "spray" then bob = 7.5
    elseif m.kind == "puff" then bob = 5.5 end
    m.y = m.y + (m.lift + math.sin(m.t * 2.8 + m.seed) * bob) * dt * 0.55
    if m.y < 0.8 then m.y = 0.8 end
    if m.y > 28 then m.y = 28 end
    m.ang = (m.ang or 0) + (m.spin or 0) * dt
    if m.t >= m.ttl
       or math.abs(m.x - px) > reach or math.abs(m.z - pz) > reach then
      table.remove(motes, i)
    end
  end
end

local function imgFor(pack, kind)
  if not pack then return nil end
  if kind == "dash" then return pack.dash end
  if kind == "leaf" then return pack.leaves end
  if kind == "seed" or kind == "spray" then return pack.seed end
  if kind == "puff" then return pack.puff or pack.grit end
  if kind == "grit" or kind == "snow" then return pack.grit end
  return pack.grit or pack.seed
end

local function colourFor(m, base)
  if m.tint then return m.tint end
  if m.kind == "seed" then return WindFX.SEED end
  if m.kind == "dash" and base == WindFX.DUST then return WindFX.DASH end
  return base
end

function WindFX.draw(project, scale)
  if #motes == 0 then return end
  local g = love.graphics
  local climateKind, baseCol, bright = climate()
  local prevBlend, prevAlpha = g.getBlendMode()
  g.setBlendMode("alpha")

  local pack = loadImgs()
  local scl = scale or 1

  -- standing first, front second (front overdraws = closer read)
  for pass = 0, 1 do
    local wantFront = (pass == 1)
    for i = 1, #motes do
      local m = motes[i]
      if (m.front and true or false) == wantFront then
        local sx, sy, ps = project(m.x, m.y, m.z)
        if sx then
          local fade = math.min(1, m.t * 4, (m.ttl - m.t) * 2.5)
          local a = bright * fade * (wantFront and 1.2 or 1.0)
          if a > 0.02 then
            local s = math.max(1, scl * (ps or 1))
            local col = colourFor(m, baseCol)
            if climateKind == "rain" then col = WindFX.SPRAY end
            if climateKind == "snow" then col = WindFX.BLOWN end

            local ang = m.ang or 0
            local vx, vz = m.vx or 0, m.vz or 0
            -- align dashes to travel
            if m.kind == "dash" or wantFront then
              local ex, ey = project(m.x - vx * WindFX.TAIL,
                                     m.y, m.z - vz * WindFX.TAIL)
              if ex then ang = math.atan2(sy - ey, sx - ex) end
            end

            -- Gust front: curl strip (opens over life) + thin dash under it
            if wantFront and pack and pack.swirl and pack.swirlQ then
              local u = math.min(1, math.max(0, m.t / math.max(0.001, m.ttl)))
              local qi = math.min(pack.swirlN - 1, math.floor(u * pack.swirlN))
              local q = pack.swirlQ[qi]
              if q then
                local fh = pack.swirl:getHeight()
                local px = math.max(5, s * 2.6)
                g.setColor(col[1], col[2], col[3], math.min(1, a * 0.9))
                pcall(g.draw, pack.swirl, q, sx, sy, ang,
                      px / fh, px / fh, fh * 0.5, fh * 0.5)
              end
            end

            local use = imgFor(pack, m.kind)
            if m.kind == "leaf" and pack and pack.leaves and pack.leafQ then
              local n = pack.leafN or 1
              local q = pack.leafQ[(m.frame or 0) % n]
              local flip = math.sin(ang * 0.5)
              local sxS = ((flip >= 0) and 1 or -1) * (m.flip or 1)
              local squash = 0.55 + 0.45 * math.abs(flip)
              local px = math.max(4, s * 1.7 * (m.size or 1))
              g.setColor(col[1], col[2], col[3], math.min(1, a))
              if q then
                pcall(g.draw, pack.leaves, q, sx, sy, ang,
                      sxS * px / 16, squash * px / 16, 8, 8)
              end
            elseif use then
              local iw = use:getWidth()
              local ih = use:getHeight()
              if iw > 0 and ih > 0 then
                local px
                local stretchX, stretchY = 1, 1
                if m.kind == "dash" then
                  px = math.max(5, s * 2.0 * (m.size or 1))
                  stretchX, stretchY = 2.6, 0.85
                elseif m.kind == "seed" or m.kind == "spray" then
                  px = math.max(3.5, s * 1.5 * (m.size or 1))
                  stretchX, stretchY = 1.5, 0.9
                elseif m.kind == "puff" then
                  px = math.max(4, s * 1.8 * (m.size or 1))
                  stretchX, stretchY = 1.2, 1.1
                else
                  -- grit / snow: small hard dots, size varies a lot
                  px = math.max(2.5, s * 1.05 * (m.size or 1))
                  stretchX, stretchY = 1.0, 1.0
                end
                g.setColor(col[1], col[2], col[3], math.min(1, a))
                pcall(g.draw, use, sx, sy, ang,
                      (px * stretchX) / iw, (px * stretchY) / ih,
                      iw * 0.5, ih * 0.5)
              end
            else
              g.setColor(col[1], col[2], col[3], math.min(1, a))
              local d = math.max(1, s * (m.kind == "dash" and 2.5 or 1.0))
              if m.kind == "dash" then
                g.rectangle("fill", sx - d * 1.4, sy - 0.5, d * 2.8, math.max(1, s * 0.5))
              else
                g.rectangle("fill", sx - d * 0.4, sy - d * 0.4, d * 0.8, d * 0.8)
              end
            end
          end
        end
      end
    end
  end

  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  g.setColor(1, 1, 1, 1)
end

function WindFX.count()
  return #motes
end

return WindFX
