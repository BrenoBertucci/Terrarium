-- MonPack -- newer battle sprites for the mons, served in place of the
-- engine's two-bit pics.
--
-- The engine draws each battler from a 56x56 Game Boy pic and colours it
-- through a four-shade palette (PaletteFX: SGB zones, or ADVANCED's
-- per-species palette). This pack carries a full-colour sprite per
-- species (assets/mons/front|back/<name>.png, Gen 5 Black/White art
-- cropped to its bounding box -- see tools/install_mon_pack.py) and
-- OverworldBattle's picImage seam hands it to the engine instead of the
-- pic whenever a battle is staged on the map. A full-colour pic has no
-- DMG shades to remap, which the engine itself already allows for
-- (BattleState fadeImage's trueColor rule): under ADVANCED the mon
-- simply keeps its own colours, and the hour's tint reaches it in the
-- 3D pass like everything else standing on the field.
--
-- Keyed by the species id with everything but letters and digits
-- dropped and lower-cased: NIDORAN_F -> nidoranf, MR_MIME -> mrmime.
local V = ...
local MonPack = {}

MonPack.ENABLED = true
-- the pack's sprites are 96 px art; drawn into the billboard texture at
-- this scale (the texture is rendered at DENSITY x the Game Boy frame,
-- so SCALE * DENSITY is the integer the pixels are actually blown up by
-- -- 2, pixel-perfect) a full sprite stands 64 GB px, a Gen 1 pic's 56
MonPack.SCALE = 2 / 3
MonPack.DENSITY = 3
-- on the menu (BACK SPRITES), where the engine draws the back pic at the
-- GB's own 2x: half of that keeps 96 px inside the 160x144 frame
MonPack.MENU_SCALE = 0.5

local images = {}      -- [side .. ":" .. key] = Image | false (the still)
local silhouettes = {} -- same key -> black Image | false
local stats = { served = 0, missed = 0, lastKey = nil, frames = 0 }

-- ------- the animated strips (assets/mons/anim, data/mons_anim.lua)
--
-- The engine draws a battler as ONE image, so an animated mon is a
-- CANVAS the size of a frame that MonPack repaints from the strip when
-- the clock says the next frame is due (tick, called once per update
-- before the side textures are rendered). picImage, the icons and the
-- silhouette all read that canvas, so the same frame shows everywhere.
-- Every animated mon keeps its own clock; a species not in the strips
-- falls back to the still.
local anim = nil       -- key -> { file, w, h, cols, n, d } | false once looked up
local strips = {}      -- key -> Image | false
local live = {}        -- key -> { canvas, quad, t, frame, meta, strip }
MonPack.ANIMATED = true

local function animMeta()
  if anim ~= nil then return anim or nil end
  local ok, tbl = pcall(V.data, "mons_anim")
  if ok and type(tbl) == "table" then anim = tbl else anim = false end
  return anim or nil
end

local function stripImage(id, meta)
  local held = strips[id]
  if held ~= nil then return held or nil end
  local rel = "assets/mons/anim/" .. meta.file
  local path = (V.path or "") .. "/" .. rel
  local ok, img = pcall(love.graphics.newImage, path)
  if not (ok and img) and V.mod and V.mod.read then
    local okR, bytes = pcall(function() return V.mod:read(rel) end)
    if okR and bytes then
      local okF, fd = pcall(love.filesystem.newFileData, bytes, "strip.png")
      if okF and fd then ok, img = pcall(love.graphics.newImage, fd) end
    end
  end
  if ok and img then
    pcall(img.setFilter, img, "nearest", "nearest")
    strips[id] = img
    return img
  end
  strips[id] = false
  return nil
end

local function paint(L)
  local g = love.graphics
  local meta = L.meta
  local f = L.frame - 1
  local col, row = f % meta.cols, math.floor(f / meta.cols)
  L.quad:setViewport(col * meta.w, row * meta.h, meta.w, meta.h)
  local prev = g.getCanvas()
  local r, gg, b, a = g.getColor()
  local blend, alphaMode = g.getBlendMode()
  g.setCanvas(L.canvas)
  g.clear(0, 0, 0, 0)
  g.setBlendMode("alpha", "alphamultiply")
  g.setColor(1, 1, 1, 1)
  g.draw(L.strip, L.quad, 0, 0)
  if prev then g.setCanvas(prev) else g.setCanvas() end
  if alphaMode ~= nil then g.setBlendMode(blend, alphaMode)
  else g.setBlendMode(blend or "alpha") end
  g.setColor(r, gg, b, a)
  stats.frames = stats.frames + 1
end

-- the live animation for a side+key, made on first ask; nil without a strip
local function liveFor(side, key)
  local id = side .. ":" .. key
  local L = live[id]
  if L ~= nil then return L or nil end
  local metaAll = animMeta()
  local meta = metaAll and metaAll[id]
  if not (MonPack.ANIMATED and meta and meta.n and meta.n > 0) then
    live[id] = false
    return nil
  end
  local strip = stripImage(id, meta)
  if not strip then live[id] = false return nil end
  local ok, cv = pcall(love.graphics.newCanvas, meta.w, meta.h, { dpiscale = 1 })
  if not (ok and cv) then live[id] = false return nil end
  cv:setFilter("nearest", "nearest")
  L = { canvas = cv, strip = strip, meta = meta, frame = 1, t = 0,
        quad = love.graphics.newQuad(0, 0, meta.w, meta.h,
                                     strip:getDimensions()),
        painted = false, used = 0 }
  live[id] = L
  return L
end

-- advance every live animation by dt; repaint the ones whose frame
-- changed (and any never painted). Called from OverworldBattle.update.
function MonPack.tick(dt)
  dt = dt or 0
  if dt < 0 then dt = 0 elseif dt > 0.25 then dt = 0.25 end
  for _, L in pairs(live) do
    if L then
      local meta = L.meta
      L.t = L.t + dt * 1000
      local hold = meta.d[L.frame] or 100
      local moved = false
      local guard = 0
      while L.t >= hold and guard < meta.n do
        L.t = L.t - hold
        L.frame = (L.frame % meta.n) + 1
        hold = meta.d[L.frame] or 100
        moved = true
        guard = guard + 1
      end
      if moved or not L.painted then
        pcall(paint, L)
        L.painted = true
      end
    end
  end
end

-- the frame a species is showing, for a cache key that must follow it
function MonPack.frameOf(species, back)
  local key = MonPack.keyOf and MonPack.keyOf(species)
  if not key then return 0 end
  local L = live[(back and "back" or "front") .. ":" .. key]
  return L and L.frame or 0
end

local function keyOf(species)
  if type(species) ~= "string" then return nil end
  local k = species:lower():gsub("[^a-z0-9]", "")
  return (#k > 0) and k or nil
end
MonPack.keyOf = keyOf

local function load(side, key)
  local id = side .. ":" .. key
  local held = images[id]
  if held ~= nil then return held or nil end
  local rel = "assets/mons/" .. side .. "/" .. key .. ".png"
  local path = (V.path or "") .. "/" .. rel
  local ok, img = pcall(love.graphics.newImage, path)
  if not (ok and img) and V.mod and V.mod.read then
    local okR, bytes = pcall(function() return V.mod:read(rel) end)
    if okR and bytes then
      local okF, fd = pcall(love.filesystem.newFileData, bytes, key .. ".png")
      if okF and fd then ok, img = pcall(love.graphics.newImage, fd) end
    end
  end
  if ok and img then
    pcall(img.setFilter, img, "nearest", "nearest")
    images[id] = img
    return img
  end
  images[id] = false
  return nil
end

-- the sprite for a species, front or back; nil when the pack has none
function MonPack.image(species, back)
  if not MonPack.ENABLED then return nil end
  local key = keyOf(species)
  if not key then return nil end
  -- animated first: the live canvas showing the current frame
  local L = liveFor(back and "back" or "front", key)
  if L then
    if not L.painted then pcall(paint, L); L.painted = true end
    stats.served = stats.served + 1
    stats.lastKey = key
    return L.canvas
  end
  local img = load(back and "back" or "front", key)
  if img then
    stats.served = stats.served + 1
    stats.lastKey = key
  else
    stats.missed = stats.missed + 1
  end
  return img
end

function MonPack.has(species, back)
  if not MonPack.ENABLED then return false end
  local key = keyOf(species)
  if not key then return false end
  local side = back and "back" or "front"
  return (liveFor(side, key) or load(side, key)) and true or false
end

-- the same sprite as a black silhouette: what the engine shows while
-- the intro slides the pair in and through a blackout
function MonPack.silhouette(species, back)
  local key = keyOf(species)
  if not key then return nil end
  local id = (back and "back" or "front") .. ":" .. key
  local held = silhouettes[id]
  if held ~= nil then return held or nil end
  -- an animated mon's silhouette is its first frame (the intro is short
  -- and a silhouette that moved would draw the eye to the wrong thing)
  local img = MonPack.image(species, back) or load(back and "back" or "front", key)
  if not img then silhouettes[id] = false return nil end
  local ok, out = pcall(function()
    local w, h = img:getDimensions()
    local cv = love.graphics.newCanvas(w, h, { dpiscale = 1 })
    local prev = love.graphics.getCanvas()
    love.graphics.setCanvas(cv)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.draw(img)
    love.graphics.setColor(1, 1, 1, 1)
    if prev then love.graphics.setCanvas(prev) else love.graphics.setCanvas() end
    cv:setFilter("nearest", "nearest")
    return cv
  end)
  silhouettes[id] = (ok and out) or false
  return silhouettes[id] or nil
end

-- The sprite as an ICON: fitted inside a `size` box whose top-left is
-- (x, y), centred, feet on the box's floor -- for the turn ribbon's
-- medallions and the party screen's rows, which used to carry the
-- engine's 16 px two-bit party icon. Drawn smooth when shrunk (a pixel
-- sprite dropped below 1:1 with nearest sampling loses whole rows) and
-- crisp when blown up. `opts.bob` lifts it a few pixels (a chosen row's
-- idle); `opts.alpha` fades it (a fainted mon).
function MonPack.drawIcon(species, x, y, size, opts)
  local img = MonPack.image(species, false)
  if not img then return false end
  opts = opts or {}
  local w, h = img:getDimensions()
  local s = math.min(size / w, size / h)
  local g = love.graphics
  local shrink = s < 1
  if shrink then pcall(img.setFilter, img, "linear", "linear") end
  local r, gg, b, a = g.getColor()
  g.setColor(r, gg, b, a * (opts.alpha or 1))
  g.draw(img, x + (size - w * s) * 0.5, y + size - h * s - (opts.bob or 0),
         0, s, s)
  g.setColor(r, gg, b, a)
  if shrink then pcall(img.setFilter, img, "nearest", "nearest") end
  return true
end

function MonPack.debug()
  local n = 0
  for _, L in pairs(live) do if L then n = n + 1 end end
  return { served = stats.served, missed = stats.missed, lastKey = stats.lastKey,
           frames = stats.frames, live = n }
end

return MonPack
