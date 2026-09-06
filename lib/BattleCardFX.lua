-- BattleCardFX -- the chosen move's element on its card, from AUTHORED
-- sheets.
--
-- The first cut of this drew the element with primitives (bolts as
-- polylines, flames as triangles) and read as exactly that. This one
-- plays hand-drawn pixel-art VFX (Pimen's spell packs, see
-- assets/vfx/LICENSE.md) on the card's glass: a strike coming down, a
-- fire burning at the foot, a water column, ice crystals, dark
-- tendrils -- looping or bursting, placed by a small table per type.
--
-- Every sprite is drawn as a four-corner textured mesh whose corners go
-- through the pane mapper, so it tilts and swings with the card. A
-- cheap bloom: the same frame drawn additive first, a little larger and
-- translucent, then plain -- which is what turns a 48 px flame into a
-- light on the glass rather than a sticker.
--
-- Presentational only; nothing here reads or writes the battle.
local V = ...
local BattleCardFX = {}

local now = function()
  return (love.timer and love.timer.getTime and love.timer.getTime()) or 0
end

-- ------- the sheets: file, frame size, grid, and which frames play
-- `loop` = { first, last } plays forever; `shot` = { first, last } plays
-- once per spawn. Frames count from 0, row-major.
BattleCardFX.SHEETS = {
  thunderstrike = { file = "pimen_thunderstrike.png", fw = 64, fh = 64, cols = 13, n = 13, fps = 24 },
  thundersplash = { file = "pimen_thundersplash.png", fw = 48, fh = 48, cols = 14, n = 14, fps = 24 },
  firebreath    = { file = "pimen_firebreath.png",    fw = 48, fh = 48, cols = 8,  n = 24, fps = 14 },
  explosion2    = { file = "pimen_explosion2.png",    fw = 48, fh = 48, cols = 18, n = 18, fps = 20 },
  watersplash   = { file = "pimen_watersplash.png",   fw = 66, fh = 77, cols = 5,  n = 20, fps = 16 },
  waterimpact   = { file = "pimen_waterimpact.png",   fw = 64, fh = 64, cols = 4,  n = 16, fps = 18 },
  ice2active    = { file = "pimen_ice2active.png",    fw = 32, fh = 32, cols = 8,  n = 8,  fps = 10 },
  ice1hit       = { file = "pimen_ice1hit.png",       fw = 32, fh = 32, cols = 12, n = 12, fps = 18 },
  dark2         = { file = "pimen_dark2.png",         fw = 48, fh = 64, cols = 16, n = 16, fps = 12 },
  dark1         = { file = "pimen_dark1.png",         fw = 40, fh = 32, cols = 10, n = 20, fps = 12 },
  holy2         = { file = "pimen_holy2.png",         fw = 48, fh = 48, cols = 16, n = 16, fps = 14 },
  rocks         = { file = "pimen_rocks.png",         fw = 48, fh = 48, cols = 6,  n = 12, fps = 14 },
  earthbump     = { file = "pimen_earthbump.png",     fw = 64, fh = 64, cols = 3,  n = 9,  fps = 14 },
  hit1          = { file = "pimen_hit1.png",          fw = 48, fh = 48, cols = 7,  n = 7,  fps = 20 },
  hit2          = { file = "pimen_hit2.png",          fw = 48, fh = 48, cols = 7,  n = 7,  fps = 20 },
  smoke2        = { file = "pimen_smoke2.png",        fw = 64, fh = 64, cols = 13, n = 13, fps = 14 },
  leaf          = { file = "wind_leaf.png",           fw = 16, fh = 16, cols = 15, n = 15, fps = 10 },
  breath        = { file = "wind_breath.png",         fw = 48, fh = 32, cols = 12, n = 12, fps = 16 },
}

-- ------- what each type plays, in pane units (W, H are the pane's)
--
-- An EMITTER: sheet, frames (loop or shot), size as a fraction of the
-- pane WIDTH, where (a function of W, H and a random r in 0..1 giving
-- the sprite's centre), rate (spawns per second for shots), count (live
-- loops), blend ("add" or "alpha"), tint, and glow (the bloom's alpha).
local function R(a, b, r) return a + (b - a) * r end
BattleCardFX.TYPES = {
  ELECTRIC = {
    { sheet = "thunderstrike", shot = { 0, 12 }, size = 0.75, rate = 3.2, blend = "add", glow = 0.5,
      at = function(W, H, r1, r2) return R(0.2, 0.8, r1) * W, R(0.25, 0.7, r2) * H end },
    { sheet = "thundersplash", shot = { 0, 13 }, size = 0.42, rate = 4.5, blend = "add", glow = 0.4,
      at = function(W, H, r1, r2) return R(0.1, 0.9, r1) * W, R(0.75, 0.95, r2) * H end },
  },
  -- FIRE (concept 15, MEDIUM): flames licking the card's EDGES from
  -- inside the rim -- a row along the foot, tongues up the two sides
  -- to mid-height -- and the centre left clean for the name. The
  -- whole-face grid of the first cut was thrown out as too much.
  -- FIRE (concept 15, MEDIUM): the rim glows orange and PIXEL flames
  -- lick in from the foot and up both sides, the centre clean. Not a
  -- sheet: a "Doom fire" buffer -- heat sources along the foot and the
  -- lower sides, propagating upward with decay and a sideways wind,
  -- shown through a five-tone palette in fat pixels. That is the
  -- chunky, continuous, moving flame of the concept; chained sprites
  -- were not.
  FIRE = {
    rim = { color = { 1.0, 0.55, 0.15 }, alpha = 0.55 },
    -- fat pixels (28 across the card), gentle decay and little wind:
    -- that is what turns the classic noise into clean tongues
    doomfire = { cols = 28, rows = 40, sideUp = 0.50, heat = 14,
                 decay = 2.4, wind = 0.22, sideHeat = 0.5 },
  },
  -- WATER: splashes bursting up from the foot, and impact sprays
  -- popping about the face -- the pillar loops of the first cut read
  -- as blue cylinders and were thrown out
  -- WATER: the card FULL of water -- a translucent body filling it from
  -- the foot to a rolling waterline, splashes breaking on that line,
  -- sprays inside the body, bubbles rising through it
  -- WATER (concept 16, MEDIUM): the card as a glass tank HALF full --
  -- a clear body up to a rolling waterline at mid-height, bubbles
  -- rising through it, an occasional small splash breaking on the
  -- line -- and the name above the water, dry
  WATER = {
    fill = { level = 0.56, amp = 0.022, color = { 0.36, 0.62, 0.96 }, alpha = 0.42,
             bubbles = 7 },
    { sheet = "watersplash", shot = { 0, 13 }, size = 0.34, rate = 0.9, blend = "alpha", glow = 0.35,
      at = function(W, H, r1, r2) return R(0.15, 0.85, r1) * W, 0.56 * H + 0.06 * H end },
  },
  ICE = {
    { sheet = "ice2active", loop = { 0, 7 }, size = 0.55, count = 3, blend = "alpha", glow = 0.45,
      at = function(W, H, r1, r2, i) return ({ 0.2, 0.5, 0.8 })[i] * W, 0.88 * H end },
    { sheet = "ice1hit", shot = { 0, 11 }, size = 0.5, rate = 2.4, blend = "add", glow = 0.5,
      at = function(W, H, r1, r2) return R(0.15, 0.85, r1) * W, R(0.15, 0.7, r2) * H end },
  },
  GHOST = {
    { sheet = "dark2", loop = { 0, 15 }, size = 0.55, count = 3, blend = "alpha", glow = 0.3,
      at = function(W, H, r1, r2, i) return ({ 0.22, 0.5, 0.78 })[i] * W, 0.72 * H end },
  },
  POISON = {
    { sheet = "dark1", loop = { 0, 19 }, size = 0.5, count = 3, blend = "alpha", glow = 0.35,
      tint = { 0.75, 0.35, 0.95 },
      at = function(W, H, r1, r2, i) return ({ 0.25, 0.5, 0.75 })[i] * W, R(0.3, 0.85, r2) * H end },
  },
  PSYCHIC = {
    { sheet = "holy2", loop = { 0, 15 }, size = 0.9, count = 1, blend = "add", glow = 0.5,
      tint = { 1.0, 0.55, 0.8 }, at = function(W, H) return 0.5 * W, 0.5 * H end },
    { sheet = "holy2", shot = { 0, 15 }, size = 0.45, rate = 1.6, blend = "add", glow = 0.4,
      tint = { 1.0, 0.7, 0.9 },
      at = function(W, H, r1, r2) return R(0.15, 0.85, r1) * W, R(0.2, 0.8, r2) * H end },
  },
  DRAGON = {
    { sheet = "holy2", loop = { 0, 15 }, size = 0.9, count = 1, blend = "add", glow = 0.5,
      tint = { 0.6, 0.4, 1.0 }, at = function(W, H) return 0.5 * W, 0.5 * H end },
    { sheet = "explosion2", shot = { 7, 17 }, size = 0.4, rate = 1.8, blend = "add", glow = 0.5,
      tint = { 0.7, 0.5, 1.0 },
      at = function(W, H, r1, r2) return R(0.15, 0.85, r1) * W, R(0.3, 0.8, r2) * H end },
  },
  ROCK = {
    { sheet = "earthbump", shot = { 0, 8 }, size = 0.5, rate = 2.4, blend = "alpha", glow = 0.2,
      at = function(W, H, r1, r2) return R(0.15, 0.85, r1) * W, R(0.7, 0.9, r2) * H end },
    { sheet = "rocks", shot = { 0, 11 }, size = 0.4, rate = 2.8, blend = "alpha", glow = 0.15,
      at = function(W, H, r1, r2) return R(0.1, 0.9, r1) * W, R(0.2, 0.7, r2) * H end },
    { sheet = "smoke2", shot = { 0, 12 }, size = 0.55, rate = 1.6, blend = "alpha", glow = 0.1,
      tint = { 0.8, 0.7, 0.55 },
      at = function(W, H, r1, r2) return R(0.2, 0.8, r1) * W, 0.85 * H end },
  },
  FIGHTING = {
    { sheet = "hit1", shot = { 0, 6 }, size = 0.5, rate = 4.0, blend = "add", glow = 0.5,
      at = function(W, H, r1, r2) return R(0.15, 0.85, r1) * W, R(0.15, 0.85, r2) * H end },
    { sheet = "hit2", shot = { 0, 6 }, size = 0.42, rate = 3.0, blend = "add", glow = 0.5,
      at = function(W, H, r1, r2) return R(0.15, 0.85, r1) * W, R(0.15, 0.85, r2) * H end },
  },
  NORMAL = {
    { sheet = "hit2", shot = { 0, 6 }, size = 0.36, rate = 2.6, blend = "add", glow = 0.45,
      tint = { 1.0, 0.95, 0.75 },
      at = function(W, H, r1, r2) return R(0.15, 0.85, r1) * W, R(0.15, 0.85, r2) * H end },
  },
  GRASS = {
    { sheet = "leaf", loop = { 0, 4 }, size = 0.16, count = 7, blend = "alpha", glow = 0.15,
      drift = { vy = 0.32, sway = 0.12 }, variants = 3,
      at = function(W, H, r1, r2) return R(0.08, 0.92, r1) * W, R(-0.2, 0.9, r2) * H end },
  },
  FLYING = {
    { sheet = "breath", shot = { 0, 11 }, size = 0.7, rate = 2.2, blend = "add", glow = 0.4,
      travel = { vx = 0.9 },
      at = function(W, H, r1, r2) return -0.2 * W, R(0.15, 0.85, r2) * H end },
  },
}
BattleCardFX.TYPES.BUG = BattleCardFX.TYPES.GRASS
BattleCardFX.TYPES.GROUND = BattleCardFX.TYPES.ROCK

BattleCardFX.ENABLED = true

-- ------- images, memoised (a failure is remembered as false)
local images = {}
local function image(key)
  local held = images[key]
  if held ~= nil then return held or nil end
  local d = BattleCardFX.SHEETS[key]
  if not d then images[key] = false return nil end
  local path = (V.path or "") .. "/assets/vfx/" .. d.file
  local ok, img = pcall(love.graphics.newImage, path)
  if not (ok and img) and V.mod and V.mod.read then
    -- through the mod's own reader, as Vfx does: a mod inside a mounted
    -- archive is not on love's filesystem the way a loose folder is
    local okR, bytes = pcall(function() return V.mod:read("assets/vfx/" .. d.file) end)
    if okR and bytes then
      local okF, fd = pcall(love.filesystem.newFileData, bytes, d.file)
      if okF and fd then ok, img = pcall(love.graphics.newImage, fd) end
    end
  end
  if ok and img then
    pcall(img.setFilter, img, "nearest", "nearest")
    images[key] = img
    return img
  end
  images[key] = false
  return nil
end

-- one scratch mesh, four corners, re-pointed per sprite
local mesh = nil
local function scratch()
  if mesh ~= nil then return mesh or nil end
  local ok, m = pcall(love.graphics.newMesh, 4, "fan", "stream")
  mesh = (ok and m) or false
  return mesh or nil
end

local function prand(a, b)
  local x = math.sin(a * 127.1 + (b or 0) * 311.7) * 43758.5453
  return x - math.floor(x)
end

-- ------- the live instances, per card id
local S = { pools = {}, draws = 0, last = nil, err = nil }

local function pool(id, tname)
  local key = id .. ":" .. tostring(tname)
  local p = S.pools[key]
  if not p then
    p = { list = {}, acc = {}, t = now(), seed = 0, tname = tname }
    S.pools[key] = p
  end
  return p
end

-- draw one frame of a sheet as a mapped quad centred on (cx, cy) in pane
-- units, `w` x `h` pane units, through `map`
local function drawFrame(map, img, d, frame, cx, cy, w, h, color, alpha,
                         mirror)
  local m = scratch()
  if not (m and img) then return false end
  local iw, ih = img:getDimensions()
  local cols = d.cols
  local col = frame % cols
  local row = math.floor(frame / cols)
  local u0, v0 = col * d.fw / iw, row * d.fh / ih
  local u1, v1 = u0 + d.fw / iw, v0 + d.fh / ih
  if mirror then u0, u1 = u1, u0 end
  local hw, hh = w * 0.5, h * 0.5
  local x1, y1 = map(cx - hw, cy - hh)
  local x2, y2 = map(cx + hw, cy - hh)
  local x3, y3 = map(cx + hw, cy + hh)
  local x4, y4 = map(cx - hw, cy + hh)
  if not (x1 and x2 and x3 and x4) then return false end
  local r, g, b = color[1], color[2], color[3]
  m:setVertices({
    { x1, y1, u0, v0, r, g, b, alpha },
    { x2, y2, u1, v0, r, g, b, alpha },
    { x3, y3, u1, v1, r, g, b, alpha },
    { x4, y4, u0, v1, r, g, b, alpha },
  })
  m:setTexture(img)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(m)
  return true
end

-- Draw the element for card `id` of type `tname` on a pane W x H through
-- `map`; `strength` 0..1 scales every alpha (the raise fades it in).
function BattleCardFX.draw(id, map, ss, W, H, tname, strength)
  if not BattleCardFX.ENABLED then return false end
  if not (id and map and W and H and W > 0 and H > 0) then return false end
  local spec = tname and BattleCardFX.TYPES[tname]
  if not spec then return false end
  strength = strength or 1
  if strength <= 0.01 then return false end
  local g = love.graphics
  local drew = false
  local ok, err = pcall(function()
    local t = now()
    local p = pool(id, tname)
    local dt = t - p.t
    p.t = t
    if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
    local prevBlend, prevA = g.getBlendMode()

    -- the rim: the glass's edge glowing in the element's colour, inside
    -- the pane (the fire's orange rim of concept 15)
    if spec.rim then
      local rm = spec.rim
      local q = {}
      local ok4 = true
      for _, c in ipairs({ { 2, 2 }, { W - 2, 2 }, { W - 2, H - 2 }, { 2, H - 2 } }) do
        local x, y = map(c[1], c[2])
        if not x then ok4 = false break end
        q[#q + 1] = x; q[#q + 1] = y
      end
      if ok4 then
        pcall(g.setBlendMode, "add", "alphamultiply")
        local pulse = 0.8 + 0.2 * math.sin(t * 6.3)
        g.setColor(rm.color[1], rm.color[2], rm.color[3], rm.alpha * 0.35 * pulse * strength)
        g.setLineWidth(math.max(6, 18 * ss))
        pcall(g.polygon, "line", q)
        g.setColor(rm.color[1], rm.color[2], rm.color[3], rm.alpha * pulse * strength)
        g.setLineWidth(math.max(2.5, 6 * ss))
        pcall(g.polygon, "line", q)
        g.setColor(1, 0.9, 0.7, rm.alpha * 0.6 * pulse * strength)
        g.setLineWidth(math.max(1, 2 * ss))
        pcall(g.polygon, "line", q)
        g.setLineWidth(1)
        drew = true
      end
    end

    -- the doom fire: stepped at its own rate, then the buffer's image
    -- laid over the whole pane in fat pixels, additive glow under plain
    if spec.doomfire then
      local D = spec.doomfire
      local st = p.fire
      if not st then
        st = { cols = D.cols, rows = D.rows, heat = {}, acc = 0, seed = 1 }
        for i = 1, D.cols * D.rows do st.heat[i] = 0 end
        local okI, idata = pcall(love.image.newImageData, D.cols, D.rows)
        if okI and idata then
          st.data = idata
          local okM, img = pcall(love.graphics.newImage, idata)
          if okM and img then
            pcall(img.setFilter, img, "nearest", "nearest")
            st.img = img
          end
        end
        p.fire = st
      end
      if st.img then
        local cols, rows, heat = st.cols, st.rows, st.heat
        st.acc = st.acc + dt
        local stepped = false
        -- 24 steps a second, whatever the frame rate
        while st.acc >= 1 / 24 do
          st.acc = st.acc - 1 / 24
          stepped = true
          -- the sources: the foot at full heat, the sides cooling with
          -- height so the flames taper to mid-card
          local base = (rows - 1) * cols
          for c = 0, cols - 1 do
            heat[base + c + 1] = D.heat
          end
          local upTo = math.floor(rows * (1 - D.sideUp))
          local sideK = D.sideHeat or 0.6
          for r = upTo, rows - 1 do
            local f = (r - upTo) / math.max(1, rows - 1 - upTo)
            local h = math.floor(D.heat * sideK * (0.3 + 0.7 * f))
            heat[r * cols + 1] = h
            heat[r * cols + cols] = h
          end
          -- the spread: every cell takes the one below it, cooled by a
          -- random step and, now and then, blown a pixel sideways
          local dk = D.decay or 3.2
          local wind = D.wind or 0.33
          for r = 0, rows - 2 do
            local row = r * cols
            local below = row + cols
            for c = 0, cols - 1 do
              st.seed = (st.seed * 1103515245 + 12345) % 2147483648
              local rnd = st.seed / 2147483648
              st.seed = (st.seed * 1103515245 + 12345) % 2147483648
              local rnd2 = st.seed / 2147483648
              local decay = math.floor(rnd * dk)
              local src = heat[below + c + 1]
              local dc = c
              if rnd2 < wind * 0.5 then dc = c - 1
              elseif rnd2 > 1 - wind * 0.5 then dc = c + 1 end
              if dc < 0 then dc = 0 elseif dc >= cols then dc = cols - 1 end
              local v = src - decay
              if v < 0 then v = 0 end
              heat[row + dc + 1] = v
            end
          end
          -- the sources' rows themselves stay put (rows-1 and rows-2)
        end
        if stepped or not st.painted then
          -- the palette: five tones, alpha from the heat, in fat pixels
          local maxH = D.heat
          st.data:mapPixel(function(x, y)
            local v = heat[y * cols + x + 1] or 0
            if v <= 2 then return 0, 0, 0, 0 end
            local f = v / maxH
            if f < 0.25 then return 0.45, 0.06, 0.02, 0.85
            elseif f < 0.45 then return 0.85, 0.16, 0.04, 0.95
            elseif f < 0.68 then return 1.0, 0.45, 0.08, 1
            elseif f < 0.92 then return 1.0, 0.78, 0.18, 1
            else return 1.0, 0.95, 0.62, 1 end
          end)
          pcall(st.img.replacePixels, st.img, st.data)
          st.painted = true
        end
        -- the whole pane, one mapped quad
        local m = scratch()
        if m then
          local x1, y1 = map(0, 0); local x2, y2 = map(W, 0)
          local x3, y3 = map(W, H); local x4, y4 = map(0, H)
          if x1 and x2 and x3 and x4 then
            m:setTexture(st.img)
            for pass = 1, 2 do
              local a = (pass == 1) and 0.28 * strength or strength
              m:setVertices({
                { x1, y1, 0, 0, 1, 1, 1, a }, { x2, y2, 1, 0, 1, 1, 1, a },
                { x3, y3, 1, 1, 1, 1, 1, a }, { x4, y4, 0, 1, 1, 1, 1, a },
              })
              pcall(g.setBlendMode, pass == 1 and "add" or "alpha", "alphamultiply")
              g.setColor(1, 1, 1, 1)
              g.draw(m)
            end
            drew = true
          end
        end
      end
    end

    -- the body: a fill from the foot up to a rolling line (the water)
    local fill = spec.fill
    if fill then
      local pts = {}
      local okPts = true
      for s = 0, 24 do
        local f = s / 24
        local y = fill.level * H
                  + math.sin(f * 6.28 * 1.5 - t * 2.4) * fill.amp * H
                  + math.sin(f * 6.28 * 3.1 + t * 1.7) * fill.amp * 0.5 * H
        local x, yy = map(f * W, y)
        if not x then okPts = false break end
        pts[#pts + 1] = x; pts[#pts + 1] = yy
      end
      local bx, by = map(W, H); local ax, ay = map(0, H)
      if okPts and bx and ax then
        local line = {}
        for k = 1, #pts do line[k] = pts[k] end
        pts[#pts + 1] = bx; pts[#pts + 1] = by
        pts[#pts + 1] = ax; pts[#pts + 1] = ay
        pcall(g.setBlendMode, "alpha", "alphamultiply")
        local c = fill.color
        g.setColor(c[1], c[2], c[3], (fill.alpha or 0.5) * strength)
        pcall(g.polygon, "fill", pts)
        -- the waterline: a bright crest with a soft glow under it
        pcall(g.setBlendMode, "add", "alphamultiply")
        g.setColor(0.7, 0.9, 1, 0.35 * strength)
        g.setLineWidth(math.max(3, 8 * ss))
        pcall(g.line, line)
        g.setColor(1, 1, 1, 0.9 * strength)
        g.setLineWidth(math.max(1.5, 2.5 * ss))
        pcall(g.line, line)
        g.setLineWidth(1)
        -- the bubbles: small rings rising through the body on their
        -- own phases, gone as they reach the line
        for b = 1, (fill.bubbles or 0) do
          local period = 2.2 + 1.6 * prand(b, 9.1)
          local f = ((t / period) + prand(b, 9.2)) % 1
          local by = H - f * (H - fill.level * H - 6)
          local bxp = (0.1 + 0.8 * prand(b, 9.3)) * W
                      + math.sin(t * 1.7 + b) * 0.03 * W
          local sx, sy = map(bxp, by)
          if sx then
            local rr = (2.5 + 2.5 * prand(b, 9.4)) * ss
            g.setColor(0.85, 0.95, 1, (0.75 - 0.5 * f) * strength)
            g.setLineWidth(math.max(1, 1.3 * ss))
            g.circle("line", sx, sy, rr)
            g.setColor(1, 1, 1, (0.5 - 0.3 * f) * strength)
            g.circle("fill", sx - rr * 0.35, sy - rr * 0.35, rr * 0.28)
          end
        end
        g.setLineWidth(1)
        -- caustics: three soft light arcs wandering across the bottom
        for k = 1, 3 do
          local ph = prand(k, 9.5) * 6.28
          local cxp = (0.2 + 0.6 * prand(k, 9.6)) * W + math.sin(t * 0.9 + ph) * 0.12 * W
          local cyp = H * (0.78 + 0.12 * prand(k, 9.7)) + math.cos(t * 0.7 + ph) * 0.04 * H
          local arc = {}
          for s = 0, 8 do
            local a = ph + s / 8 * 2.6 + t * 0.6
            local x, y = map(cxp + math.cos(a) * 0.14 * W, cyp + math.sin(a) * 0.05 * H)
            if not x then arc = nil break end
            arc[#arc + 1] = x; arc[#arc + 1] = y
          end
          if arc then
            g.setColor(0.8, 0.95, 1, (0.18 + 0.1 * math.sin(t * 2 + ph)) * strength)
            g.setLineWidth(math.max(2, 5 * ss))
            pcall(g.line, arc)
          end
        end
        g.setLineWidth(1)
        drew = true
      end
    end

    -- spawn: loops keep `count` alive, shots arrive at `rate`
    for ei, e in ipairs(spec) do
      local d = BattleCardFX.SHEETS[e.sheet]
      if d then
        if e.loop then
          local alive = 0
          for _, inst in ipairs(p.list) do
            if inst.ei == ei then alive = alive + 1 end
          end
          for i = alive + 1, e.count or 1 do
            p.seed = p.seed + 1
            local r1, r2 = prand(p.seed, 1), prand(p.seed, 2)
            local x, y = e.at(W, H, r1, r2, i)
            p.list[#p.list + 1] = {
              ei = ei, born = t - prand(p.seed, 3) * 2, x = x, y = y,
              variant = e.variants and math.floor(prand(p.seed, 4) * e.variants) or 0,
              ph = prand(p.seed, 5) * 6.28, i = i,
            }
          end
        else
          p.acc[ei] = (p.acc[ei] or 0) + dt * (e.rate or 1)
          while p.acc[ei] >= 1 do
            p.acc[ei] = p.acc[ei] - 1
            p.seed = p.seed + 1
            local r1, r2 = prand(p.seed, 1), prand(p.seed, 2)
            local x, y = e.at(W, H, r1, r2, 1)
            p.list[#p.list + 1] = { ei = ei, born = t, x = x, y = y,
                                    variant = 0, ph = prand(p.seed, 5) * 6.28 }
          end
        end
      end
    end

    -- step and draw
    local i = 1
    while i <= #p.list do
      local inst = p.list[i]
      local e = spec[inst.ei]
      local d = e and BattleCardFX.SHEETS[e.sheet]
      local img = d and image(e.sheet)
      local dead = false
      if not (e and d and img) then
        dead = true
      else
        local age = t - inst.born
        local first, last
        local frame
        if e.loop then
          first, last = e.loop[1], e.loop[2]
          local n = last - first + 1
          frame = first + (math.floor(age * d.fps) % n)
        else
          first, last = e.shot[1], e.shot[2]
          local f = first + math.floor(age * d.fps)
          if f > last then dead = true end
          frame = f
        end
        if e.drift then
          inst.y = inst.y + e.drift.vy * H * dt
          inst.x = inst.x + math.sin(t * 2.2 + inst.ph) * e.drift.sway * W * dt
          if inst.y > H + 0.1 * H then dead = true end
          -- a riser (bubbles) leaves at the waterline and is reborn below
          if e.respawnBelow and inst.y < (spec.fill and spec.fill.level or 0) * H then
            dead = true
          end
        end
        if e.travel then
          inst.x = inst.x + e.travel.vx * W * dt
          if inst.x > W * 1.3 then dead = true end
        end
        if not dead then
          local w = (e.sizeOf and e.sizeOf(inst.i or 1) or e.size) * W
          local h = w * d.fh / d.fw
          local cx, cy = inst.x, inst.y
          -- a variant strip (the leaves): frame offset by variant * n
          local fr = frame + (inst.variant or 0) * (e.loop and (e.loop[2] - e.loop[1] + 1) or 0)
          local tint = e.tint or { 1, 1, 1 }
          -- clip to the pane: a sprite that leaves the glass is cut, not
          -- drawn over the world (the mapper extrapolates past the pane)
          if cx > -w * 0.5 and cx < W + w * 0.5 and cy > -h * 0.5 and cy < H + h * 0.5 then
            -- the bloom first, additive, a little larger
            local mirror = e.mirrorOdd and ((inst.i or 1) % 2 == 0)
            if (e.glow or 0) > 0 then
              pcall(g.setBlendMode, "add", "alphamultiply")
              drawFrame(map, img, d, fr, cx, cy, w * 1.18, h * 1.18, tint,
                        e.glow * strength, mirror)
            end
            pcall(g.setBlendMode, e.blend == "add" and "add" or "alpha",
                  "alphamultiply")
            if drawFrame(map, img, d, fr, cx, cy, w, h, tint, strength, mirror) then
              drew = true
            end
          end
        end
      end
      if dead then table.remove(p.list, i) else i = i + 1 end
    end
    if prevA ~= nil then pcall(g.setBlendMode, prevBlend, prevA)
    else pcall(g.setBlendMode, prevBlend or "alpha") end
    g.setColor(1, 1, 1, 1)
  end)
  if not ok then
    S.err = tostring(err)
    pcall(love.graphics.setColor, 1, 1, 1, 1)
    pcall(love.graphics.setBlendMode, "alpha")
    return false
  end
  if drew then
    S.draws = S.draws + 1
    S.last = tname
  end
  return drew
end

-- forget a card's pool (a fan folded away): the next raise starts fresh
function BattleCardFX.clear(id)
  if id then
    for key in pairs(S.pools) do
      if key:sub(1, #id + 1) == id .. ":" then S.pools[key] = nil end
    end
  else
    S.pools = {}
  end
end

function BattleCardFX.debug()
  local n = 0
  for _, p in pairs(S.pools) do n = n + #p.list end
  return { draws = S.draws, last = S.last, err = S.err, live = n }
end

return BattleCardFX
