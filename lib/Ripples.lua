-- Voxel world mode: the water REMEMBERS what touched it.
--
-- Everything else the surface does is analytic -- three sine trains, a size
-- field, a wake painted from where the swimmers are THIS frame. Nothing in it
-- can answer "what happened here a second ago", so nothing in it can make a
-- ring: a ring is the memory of a touch, travelling outward from where it
-- was. That is a wave equation, and this file is one.
--
--   THE FIELD   a height per cell on a small grid that follows the player
--               (N x N cells of CELL world pixels -- 96 x 4 = 384 px, a
--               screen and a half), stepped at a FIXED rate with the
--               standard explicit scheme:
--
--                  next = (2 h - prev + C2 * laplacian(h)) * damp
--
--               C2 = (SPEED / RATE / CELL)^2 is the Courant number squared;
--               2D is stable below 0.5 and this runs at ~0.11.
--
--               The laplacian is the ISOTROPIC nine-point one (four edges
--               weighted 4, four corners weighted 1, over 6). The textbook
--               five-point stencil is cheaper and wrong here: on a grid this
--               coarse it carries a wave faster along the axes than along the
--               diagonals, and a drop's ring comes out an OCTAGON -- which is
--               exactly what the first build of this showed on Route 21.
--
--   THE BANKS   every cell the size field (lib/WaterBody.lua) classed as
--               LAND is pinned at zero. A pinned boundary REFLECTS, with the
--               sign flipped -- so a ring that reaches the bank comes back,
--               and two rings crossing interfere, because that is what the
--               equation does and nobody had to write it down.
--
--   THE EDGE    the grid's own border is not a bank, it is the end of what
--               is simulated; a wall there would bounce rings back off open
--               water. So the outer SPONGE cells damp harder the nearer the
--               edge they sit, and what reaches the edge is swallowed.
--
--   THE SOURCES poke (a drop: rain, a splash, a bobber dipping), push (a
--               body moving through the water, laid every step it moves --
--               faster than a ring travels, and the rings pile into a V on
--               their own) and emit (something bobbing in place: a slow
--               train of rings, the waterfall picture).
--
-- What the shader gets is a texture the size of the grid (lib/Voxel3D.lua,
-- rippleMap): R the height, G/B its slope (so the sheet gets a normal with
-- one fetch, not five), A the FROTH -- white water left where something hit
-- hard, decaying on its own clock. PIXEL-only in the shader: the sheet is
-- not displaced by it, it is SHADED by it, which is what keeps this off the
-- vertex-texture-fetch question entirely (see VERTEX_TEX in Voxel3D).
--
-- It sleeps. When nothing has touched the water for a second and the last
-- ring has died under the noise floor, the step stops, the texture stops
-- uploading and the shader skips its fetch (`rippleOn` = 0). A pond nobody
-- is standing in costs nothing.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local WaterBody = V.require("WaterBody")

local Ripples = {}

Ripples.N = 96              -- cells a side
Ripples.CELL = 4            -- world px per cell (a map cell is 16)
Ripples.RATE = 30           -- steps per second, fixed: the scheme is only
                            -- stable for the Courant number it was sized at
Ripples.SPEED = 40          -- world px/s a ring travels
Ripples.DAMP = 0.992        -- per step; a ring is gone in about four seconds
Ripples.SPONGE = 10         -- cells of absorbing border
Ripples.SPONGE_DAMP = 0.80  -- what the outermost of them keeps per step
Ripples.RECENTER = 16       -- cells the player may wander before the grid follows
Ripples.MAX_STEPS = 3       -- catch-up per frame: a hitch is not a flood
Ripples.MAX_EMIT = 24       -- oscillating sources alive at once
Ripples.H_ENC = 4           -- height range the texture holds: +-2 world px
Ripples.FROTH_DECAY = 0.955 -- per step
Ripples.SLEEP_H = 0.02      -- world px: under this everywhere, the water is still
                            -- (one texel step of R is H_ENC/255 = 0.016 px)
Ripples.SLEEP_STEPS = 30    -- ...for this many steps, and the field sleeps

-- for the probes
Ripples.steps = 0
Ripples.uploads = 0
Ripples.pokes = 0
Ripples.recenters = 0
Ripples.maxAbs = 0

local N = Ripples.N
local h, p, q = {}, {}, {}  -- now, the step before, scratch
local froth = {}
local wet = {}              -- 1 water, 0 bank (pinned)
local damp = {}             -- per cell, sponge folded in
local emitters = {}
local ox, oz = nil, nil     -- grid origin, in CELLS (world px / CELL)
local fieldRef = nil        -- the WaterBody bake the walls were read from
local acc = 0
local still = 0
local awake = false
local dirty = false
local data, image = nil, nil
local blank = nil

local function clear(t, v)
  for k = 1, N * N do t[k] = v end
end
clear(h, 0); clear(p, 0); clear(q, 0); clear(froth, 0)
clear(wet, 1); clear(damp, Ripples.DAMP)

local function sponge(i, j)
  local s = Ripples.SPONGE
  local e = math.min(i, j, N - 1 - i, N - 1 - j)
  if e >= s then return 1 end
  if e <= 0 then return 0 end
  local t = e / s
  return Ripples.SPONGE_DAMP + (1 - Ripples.SPONGE_DAMP) * t * t
end

-- The banks under the grid, read off the size field's own classification.
-- A cell no drawn map covers (nil) counts as water: past the edge of the
-- known world the honest guess is "more sea", same as WaterBody's.
local function rebuildWalls()
  local cell = Ripples.CELL
  local lookup = Ripples.isWaterAt or WaterBody.isWaterAt
  for j = 0, N - 1 do
    local wz = (oz + j + 0.5) * cell
    for i = 0, N - 1 do
      local k = j * N + i + 1
      local w = lookup((ox + i + 0.5) * cell, wz)
      wet[k] = (w == false) and 0 or 1
      damp[k] = Ripples.DAMP * sponge(i, j)
    end
  end
end

-- Slide the field by (di, dj) cells so the water under the player keeps the
-- rings it already had; what scrolls in is still water.
local function shift(di, dj)
  for _, t in ipairs({ h, p, froth }) do
    for j = 0, N - 1 do
      for i = 0, N - 1 do
        local si, sj = i + di, j + dj
        local v = 0
        if si >= 0 and sj >= 0 and si < N and sj < N then
          v = t[sj * N + si + 1]
        end
        q[j * N + i + 1] = v
      end
    end
    for k = 1, N * N do t[k] = q[k] end
  end
end

-- Keep the grid centred on (wx, wz). Returns true when it moved.
function Ripples.follow(wx, wz)
  local cell = Ripples.CELL
  local cx = math.floor(wx / cell) - N / 2
  local cz = math.floor(wz / cell) - N / 2
  local f = WaterBody.field and WaterBody.field() or nil
  if ox == nil or f ~= fieldRef then
    -- first frame, or a different drawn world: nothing carries over
    ox, oz, fieldRef = cx, cz, f
    clear(h, 0); clear(p, 0); clear(froth, 0)
    emitters = {}
    rebuildWalls()
    dirty = true
    return true
  end
  local di, dj = cx - ox, cz - oz
  if math.abs(di) < Ripples.RECENTER and math.abs(dj) < Ripples.RECENTER then
    return false
  end
  if awake then shift(di, dj) end
  ox, oz = cx, cz
  rebuildWalls()
  Ripples.recenters = Ripples.recenters + 1
  dirty = true
  return true
end

local function cellOf(wx, wz)
  if not ox then return nil end
  local fx = wx / Ripples.CELL - ox - 0.5
  local fz = wz / Ripples.CELL - oz - 0.5
  return fx, fz
end

-- A drop: `amount` world px of displacement at the centre (negative pushes
-- the water DOWN, which is what a thing landing on it does), falling off
-- over `radius` world px. `foam` 0..1 leaves white water behind.
function Ripples.poke(wx, wz, amount, radius, foam)
  local fx, fz = cellOf(tonumber(wx) or 0, tonumber(wz) or 0)
  if not fx then return false end
  local r = math.max(tonumber(radius) or 3, Ripples.CELL * 0.75) / Ripples.CELL
  local i0, i1 = math.floor(fx - r), math.ceil(fx + r)
  local j0, j1 = math.floor(fz - r), math.ceil(fz + r)
  if i1 < 1 or j1 < 1 or i0 > N - 2 or j0 > N - 2 then return false end
  local a = tonumber(amount) or 0
  local fo = tonumber(foam) or 0
  local r2 = r * r
  for j = math.max(j0, 1), math.min(j1, N - 2) do
    for i = math.max(i0, 1), math.min(i1, N - 2) do
      local dx, dz = i - fx, j - fz
      local d2 = dx * dx + dz * dz
      if d2 <= r2 then
        local k = j * N + i + 1
        -- a raised cosine: smooth to the rim, so the drop itself does not
        -- ring at the grid's own frequency
        local w = 0.5 + 0.5 * math.cos(math.pi * math.sqrt(d2 / r2))
        h[k] = h[k] + a * w * wet[k]
        if fo > 0 then
          local v = froth[k] + fo * w
          froth[k] = (v > 1) and 1 or v
        end
      end
    end
  end
  Ripples.pokes = Ripples.pokes + 1
  awake = true
  still = 0
  return true
end

-- Something bobbing in place: a train of rings at `freq` Hz for `life`
-- seconds, fading in and out. `key` names a source the caller OWNS: asking
-- again moves it and extends its life from now, so a caller that re-asks
-- every frame gets one unbroken train that fades out half a second after it
-- stops asking -- not a new source, and not a stack of them.
function Ripples.emit(wx, wz, amount, freq, life, key)
  local e
  if key ~= nil then
    for _, o in ipairs(emitters) do
      if o.key == key then e = o break end
    end
  end
  life = tonumber(life) or 1
  if not e then
    if #emitters >= Ripples.MAX_EMIT then table.remove(emitters, 1) end
    e = { key = key, t = 0 }
    emitters[#emitters + 1] = e
    e.life = life
  else
    e.life = e.t + life
  end
  e.x, e.z = tonumber(wx) or 0, tonumber(wz) or 0
  e.a = tonumber(amount) or 0.3
  e.f = tonumber(freq) or 1
  awake = true
  still = 0
  return e
end

function Ripples.stop(key)
  for i = #emitters, 1, -1 do
    if emitters[i].key == key then table.remove(emitters, i) end
  end
end

local function stepOnce()
  local dt = 1 / Ripples.RATE
  -- the sources first, as displacement this step
  for i = #emitters, 1, -1 do
    local e = emitters[i]
    e.t = e.t + dt
    if e.t >= e.life then
      table.remove(emitters, i)
    else
      local env = math.min(1, e.t * 4, (e.life - e.t) * 2)
      local s = math.sin(e.t * e.f * 2 * math.pi)
      -- one cell of radius and a small amount per step: an emitter is a
      -- slow push, integrated, not a hammer
      local fx, fz = cellOf(e.x, e.z)
      if fx then
        local i0, j0 = math.floor(fx + 0.5), math.floor(fz + 0.5)
        if i0 >= 1 and j0 >= 1 and i0 <= N - 2 and j0 <= N - 2 then
          local k = j0 * N + i0 + 1
          h[k] = h[k] + e.a * env * s * 0.25 * wet[k]
        end
      end
    end
  end

  local C2 = (Ripples.SPEED / Ripples.RATE / Ripples.CELL) ^ 2
  local fd = Ripples.FROTH_DECAY
  local peak = 0
  for j = 1, N - 2 do
    local row = j * N
    for i = 1, N - 2 do
      local k = row + i + 1
      local c = h[k]
      local lap = (4 * (h[k - 1] + h[k + 1] + h[k - N] + h[k + N])
                   + h[k - N - 1] + h[k - N + 1] + h[k + N - 1] + h[k + N + 1]
                   - 20 * c) / 6
      local v = (c + c - p[k] + C2 * lap) * damp[k] * wet[k]
      q[k] = v
      if v > peak then peak = v elseif -v > peak then peak = -v end
      froth[k] = froth[k] * fd
    end
  end
  -- the border ring is outside the loop and stays zero
  p, h, q = h, q, p
  Ripples.maxAbs = peak
  Ripples.steps = Ripples.steps + 1
  if peak < Ripples.SLEEP_H and #emitters == 0 then
    still = still + 1
    if still >= Ripples.SLEEP_STEPS then
      awake = false
      clear(h, 0); clear(p, 0); clear(froth, 0)
    end
  else
    still = 0
  end
  dirty = true
end

-- ------- the texture

local function clamp01(n)
  if n < 0 then return 0 elseif n > 1 then return 1 end
  return n
end

function Ripples.encode(k)
  local hv = h[k]
  local gx = (h[k + 1] - h[k - 1]) / (2 * Ripples.CELL)
  local gz = (h[k + N] - h[k - N]) / (2 * Ripples.CELL)
  return clamp01(0.5 + hv / Ripples.H_ENC), clamp01(0.5 + gx),
         clamp01(0.5 + gz), clamp01(froth[k])
end

local function upload()
  if not (love and love.image and love.graphics) then return end
  if not data then
    local ok, d = pcall(love.image.newImageData, N, N)
    if not ok then return end
    data = d
  end
  local enc = Ripples.encode
  for j = 0, N - 1 do
    for i = 0, N - 1 do
      if i == 0 or j == 0 or i == N - 1 or j == N - 1 then
        data:setPixel(i, j, 0.5, 0.5, 0.5, 0)
      else
        data:setPixel(i, j, enc(j * N + i + 1))
      end
    end
  end
  if image then
    pcall(image.replacePixels, image, data)
  else
    local ok, img = pcall(love.graphics.newImage, data)
    if not ok then return end
    image = img
    -- linear: the rings are a smooth field and the shader wants it smooth
    -- between four-pixel cells; clamp: past the edge is still water
    pcall(img.setFilter, img, "linear", "linear")
    pcall(img.setWrap, img, "clamp", "clamp")
  end
  Ripples.uploads = Ripples.uploads + 1
end

-- ------- the frame

-- `live` is the caller's gate: the overworld is on top, voxel mode is on,
-- no transition. Off, the field holds still (a menu is not time passing on
-- the lake) -- and keeps what it has for when the world comes back.
function Ripples.update(dt, live, wx, wz)
  if not live then return end
  if wx then Ripples.follow(wx, wz) end
  if not awake then return end
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 end
  acc = acc + dt
  local step = 1 / Ripples.RATE
  local n = 0
  while acc >= step and n < Ripples.MAX_STEPS do
    acc = acc - step
    stepOnce()
    n = n + 1
    if not awake then break end
  end
  if acc > step then acc = 0 end
  if dirty and awake then
    upload()
    dirty = false
  end
end

-- Is there anything for the sheet to show?
function Ripples.live()
  return awake and image ~= nil
end

function Ripples.image()
  return image
end

-- Always-bound stand-in (unbound is a driver-dependent crash; the switch is
-- the `rippleOn` uniform, never the binding): flat water, no froth.
function Ripples.blank()
  if blank == nil then
    local ok, img = pcall(function()
      local d = love.image.newImageData(1, 1)
      d:setPixel(0, 0, 0.5, 0.5, 0.5, 0)
      return love.graphics.newImage(d)
    end)
    blank = (ok and img) or false
  end
  return blank or nil
end

-- origin (world px) and 1 / extent, for uv = (xz - origin) * inv. Texel i
-- covers [ox + i, ox + i + 1) cells, so its centre lands on (i + 0.5) / N.
function Ripples.uvParams()
  if not ox then return 0, 0, 0 end
  local cell = Ripples.CELL
  return ox * cell, oz * cell, 1 / (N * cell)
end

-- The CPU twin: height in world px at (wx, wz), bilinear like the shader's
-- tap, so a body floating here rides the same rings the sheet paints.
function Ripples.heightAt(wx, wz)
  if not awake then return 0 end
  local fx, fz = cellOf(tonumber(wx) or 0, tonumber(wz) or 0)
  if not fx then return 0 end
  local i0, j0 = math.floor(fx), math.floor(fz)
  if i0 < 0 or j0 < 0 or i0 >= N - 1 or j0 >= N - 1 then return 0 end
  local tx, tz = fx - i0, fz - j0
  local k = j0 * N + i0 + 1
  local a, b, c, d = h[k], h[k + 1], h[k + N], h[k + N + 1]
  local top = a + (b - a) * tx
  local bot = c + (d - c) * tx
  return top + (bot - top) * tz
end

-- Hot reload / the mode going off: forget everything, keep nothing bound.
function Ripples.reset()
  clear(h, 0); clear(p, 0); clear(froth, 0)
  emitters = {}
  ox, oz, fieldRef = nil, nil, nil
  awake, still, acc, dirty = false, 0, 0, false
end

-- for the offline test: the raw field
function Ripples._state()
  return { h = h, p = p, froth = froth, wet = wet, N = N,
           ox = ox, oz = oz, awake = awake, emitters = emitters }
end

return Ripples
