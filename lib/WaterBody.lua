-- Voxel world mode: HOW BIG the water under this pixel is.
--
-- The swell has always been one number for the whole world. `Water.swell()`
-- reads the row, adds rain, wind and stored chop, and hands the same
-- amplitude to Vermilion's sea and to the fountain in Cerulean. The pond in
-- a town gets an ocean's wave because nothing in the pipeline has ever known
-- that a pond is small.
--
-- `Water.bodyFreq` looks like it knew, and did not:
--
--   0.90 + 0.35 * sin(wx * 0.0039) * cos(wz * 0.0045)
--
-- That is a sine field in WORLD SPACE. It varies with where you are standing
-- and not at all with what you are standing in -- two ponds a hundred pixels
-- apart get different waves, and one pond that happens to straddle a lobe
-- gets two. It also moves the FREQUENCY and never the amplitude, so the
-- number that actually needed to know about size was the one it did not
-- touch. This file is the thing it was a stand-in for.
--
-- WHAT IS MEASURED, and why it is two numbers rather than one:
--
--   FETCH   distance from this cell to the nearest shore, in cells. A
--           multi-source BFS seeded on every LAND cell at once, which is a
--           distance transform in disguise and costs one pass over the grid.
--           This is the gradient INSIDE a body: the middle of a lake is open
--           water and the last two cells before the bank are not, which is
--           what makes a wave die into a shoreline instead of slamming into
--           it at full height.
--
--   AREA    the size of the connected body this cell belongs to, as
--           sqrt(cells) so it reads as a LENGTH rather than as an area.
--           This is the hard cap the fetch cannot give: fetch alone says the
--           middle of a 6x6 pond is three cells from shore, which is the
--           same three cells you get in a channel of the sea, and the pond
--           would come out choppier than it has any right to be. Area says
--           "this whole thing is small" and nothing inside it may exceed it.
--
-- `min` of the two, and the min is the point. A big lake still calms at its
-- edges (fetch wins there) and a small pond is calm everywhere (area wins
-- everywhere in it).
--
-- WHAT THE TEXTURE HOLDS IS THE COMPLEMENT -- `calm`, 1 - size -- and that
-- is a failure mode rather than a preference. The vertex stage reads this
-- through a VERTEX TEXTURE FETCH, which desktop GL always has and GLES2 is
-- permitted to give zero units for. A driver that cannot do the fetch hands
-- back zero. Stored as size, zero means "puddle" and every ocean in the game
-- would go flat on that device with no error anywhere. Stored as calm, zero
-- means "open water" -- which is exactly the behaviour this file replaced,
-- so the worst case is the old build and not a broken one. Same for the
-- clamp outside the baked region: past the edge of the known world there is
-- no shore recorded, and open is the honest guess.
--
-- WHAT IT DOES NOT MEASURE is the wind's own fetch -- the run of open water
-- UPWIND of a point, which is the term that actually grows a sea in the real
-- physics, and which changes every time Wind.DIR turns. That is a directional
-- sweep over this same grid and it belongs on top of this, not instead of it.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local WaterBody = {}

-- One cell of the 2D game is 16 world pixels, and one texel here is one
-- cell. A lake's shape has no detail finer than the tile it is authored on,
-- so anything denser is storing the same number twice.
WaterBody.CELL = 16

-- Cells from the bank at which water counts as fully open. Ten is 160 world
-- pixels -- ten tiles, about a screen and a half of the 2D game -- and it is
-- picked off the maps rather than off a formula: it is roughly the half-width
-- of the widest inland water in Kanto (the Route 12 / 13 channels), so those
-- reach open in the middle and the town ponds never do.
WaterBody.FETCH_CELLS = 10

-- sqrt(cells) at which a whole body counts as open. 26 is a 26x26-tile lake
-- -- bigger than every pond, smaller than every stretch of sea.
WaterBody.AREA_CELLS = 26

-- The grid is capped and downsampled rather than refused: a map plus four
-- neighbours can be a few hundred cells on a side, and past this the field
-- is measured every second cell (then every third, ...). Costs the shoreline
-- gradient a little sharpness at the very largest neighbourhoods and never
-- costs a frame.
WaterBody.MAX_TEXELS = 256

-- A ring of unknown around the union, so a body that runs off the edge of
-- the drawn world is not given a coastline it does not have.
WaterBody.MARGIN = 2

-- Cell classes in the scratch grid.
local LAND, WATER, UNKNOWN = 0, 1, 2

-- The one baked field. Rebuilt when the live neighbourhood changes; there is
-- never a reason to hold two, since the previous one describes a world that
-- is no longer being drawn.
local field = nil     -- { image, data, ox, oz, w, h, step, key } | nil
local failed = {}     -- key -> true, so a bake that threw is not retried
                      -- every frame for as long as the player stands there

local function mapCells(def)
  -- def.width / def.height are in 2x2-tile BLOCKS (see VoxelScene's
  -- neighbour masks: `nb.ox + nb.map.def.width * 32`), so a block is 32
  -- world pixels and two cells on a side.
  local w = tonumber(def and def.width) or 0
  local h = tonumber(def and def.height) or 0
  return math.floor(w * 2), math.floor(h * 2)
end

-- Every map the scene is drawing, with its offset in world pixels. The
-- current map is the origin; neighbours carry the same ox/oy the meshes are
-- translated by, so this grid and the geometry cannot disagree about where
-- a shoreline is.
local function places(state)
  local out = {}
  if not (state and state.map and state.map.def) then return out end
  out[1] = { map = state.map, ox = 0, oz = 0 }
  for _, nb in ipairs(state.neighbors or {}) do
    if nb.map and nb.map.def then
      out[#out + 1] = { map = nb.map, ox = nb.ox or 0, oz = nb.oy or 0 }
    end
  end
  return out
end

local function liveKey(list)
  local parts = {}
  for i, p in ipairs(list) do
    parts[i] = string.format("%s@%d,%d", tostring(p.map.id), p.ox, p.oz)
  end
  return table.concat(parts, "|")
end

-- The union of every drawn map, in CELLS, padded by MARGIN.
local function unionCells(list)
  local cell = WaterBody.CELL
  local x0, z0, x1, z1
  for _, p in ipairs(list) do
    local cw, ch = mapCells(p.map.def)
    if cw > 0 and ch > 0 then
      local a = math.floor(p.ox / cell)
      local b = math.floor(p.oz / cell)
      local c, d = a + cw, b + ch
      if not x0 or a < x0 then x0 = a end
      if not z0 or b < z0 then z0 = b end
      if not x1 or c > x1 then x1 = c end
      if not z1 or d > z1 then z1 = d end
    end
  end
  if not x0 then return nil end
  local m = WaterBody.MARGIN
  return x0 - m, z0 - m, x1 + m, z1 + m
end

-- LAND / WATER / UNKNOWN for one world cell. UNKNOWN is the answer for a
-- cell no drawn map covers, and it is a third class rather than land on
-- purpose: land is a shore and stops a wave, and the edge of what we happen
-- to be rendering is neither.
local function classify(list, gx, gz)
  for _, p in ipairs(list) do
    local cw, ch = mapCells(p.map.def)
    local lx = gx - math.floor(p.ox / WaterBody.CELL)
    local lz = gz - math.floor(p.oz / WaterBody.CELL)
    if lx >= 0 and lz >= 0 and lx < cw and lz < ch then
      local m = p.map
      if type(m.isWaterCell) ~= "function" then return LAND end
      return m:isWaterCell(lx, lz) and WATER or LAND
    end
  end
  return UNKNOWN
end

-- ------- the bake
--
-- Three passes over one flat array, and none of them allocate per cell:
--   1. classify
--   2. multi-source BFS from every land cell -> distance to shore
--   3. flood fill the water into connected bodies -> area, and whether the
--      body runs off into UNKNOWN (in which case it is open, whatever its
--      visible area says)
local function bake(list)
  local x0, z0, x1, z1 = unionCells(list)
  if not x0 then return nil end

  local cw, ch = x1 - x0, z1 - z0
  if cw < 1 or ch < 1 then return nil end
  local step = 1
  while math.ceil(cw / step) > WaterBody.MAX_TEXELS
     or math.ceil(ch / step) > WaterBody.MAX_TEXELS do
    step = step + 1
  end
  local w = math.ceil(cw / step)
  local h = math.ceil(ch / step)
  local n = w * h

  -- pass 1
  local kind = {}
  for j = 0, h - 1 do
    local base = j * w
    for i = 0, w - 1 do
      kind[base + i + 1] = classify(list, x0 + i * step, z0 + j * step)
    end
  end

  -- pass 2: BFS seeded on every land cell at once. `dist` is in TEXELS;
  -- multiply by step to read it back in cells.
  local dist = {}
  local queue, qh, qt = {}, 1, 0
  for k = 1, n do
    if kind[k] == LAND then
      dist[k] = 0
      qt = qt + 1
      queue[qt] = k
    else
      dist[k] = -1
    end
  end
  while qh <= qt do
    local k = queue[qh]
    qh = qh + 1
    local d = dist[k] + 1
    local i = (k - 1) % w
    local j = math.floor((k - 1) / w)
    -- 4-connected: a diagonal gap in a tile map is not a way round a bank
    if i > 0            then local m = k - 1
      if dist[m] < 0 and kind[m] == WATER then dist[m] = d; qt = qt + 1; queue[qt] = m end end
    if i < w - 1        then local m = k + 1
      if dist[m] < 0 and kind[m] == WATER then dist[m] = d; qt = qt + 1; queue[qt] = m end end
    if j > 0            then local m = k - w
      if dist[m] < 0 and kind[m] == WATER then dist[m] = d; qt = qt + 1; queue[qt] = m end end
    if j < h - 1        then local m = k + w
      if dist[m] < 0 and kind[m] == WATER then dist[m] = d; qt = qt + 1; queue[qt] = m end end
  end

  -- pass 3: connected bodies. `comp` names each water cell's body; `area`
  -- counts it; `open` remembers whether the body ever touched UNKNOWN, which
  -- means it continues past the world we can see and its visible area is a
  -- lower bound rather than its size.
  local comp, area, open = {}, {}, {}
  local nComp = 0
  local st = {}
  for k = 1, n do
    if kind[k] == WATER and not comp[k] then
      nComp = nComp + 1
      local id = nComp
      local a, isOpen = 0, false
      local sp = 1
      st[1] = k
      comp[k] = id
      while sp > 0 do
        local c = st[sp]
        sp = sp - 1
        a = a + 1
        local i = (c - 1) % w
        local j = math.floor((c - 1) / w)
        -- unrolled rather than a visit() closure: this loop runs once per
        -- water cell in the neighbourhood and a closure per iteration is a
        -- table allocation per cell, on the frame a map crossing lands
        local m
        if i > 0 then
          m = c - 1
          if kind[m] == UNKNOWN then isOpen = true
          elseif kind[m] == WATER and not comp[m] then
            comp[m] = id; sp = sp + 1; st[sp] = m end
        else isOpen = true end
        if i < w - 1 then
          m = c + 1
          if kind[m] == UNKNOWN then isOpen = true
          elseif kind[m] == WATER and not comp[m] then
            comp[m] = id; sp = sp + 1; st[sp] = m end
        else isOpen = true end
        if j > 0 then
          m = c - w
          if kind[m] == UNKNOWN then isOpen = true
          elseif kind[m] == WATER and not comp[m] then
            comp[m] = id; sp = sp + 1; st[sp] = m end
        else isOpen = true end
        if j < h - 1 then
          m = c + w
          if kind[m] == UNKNOWN then isOpen = true
          elseif kind[m] == WATER and not comp[m] then
            comp[m] = id; sp = sp + 1; st[sp] = m end
        else isOpen = true end
      end
      area[id] = a
      open[id] = isOpen
    end
  end

  -- ------- to pixels
  if not (love and love.image and love.image.newImageData) then return nil end
  local data = love.image.newImageData(w, h)
  local fetchFull = math.max(1, WaterBody.FETCH_CELLS)
  local areaFull = math.max(1, WaterBody.AREA_CELLS)
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      local k = j * w + i + 1
      local size01 = 1
      if kind[k] == WATER then
        local d = dist[k]
        -- a water cell the BFS never reached is enclosed by UNKNOWN alone:
        -- no shore anywhere near it, so it is open
        local fetch01 = 1
        if d and d >= 0 then
          fetch01 = math.min(1, (d * step) / fetchFull)
        end
        local id = comp[k]
        local area01 = 1
        if id and not open[id] then
          -- sqrt(cells) so the number reads as a LENGTH: doubling a lake's
          -- width should double this, not quadruple it
          area01 = math.min(1, math.sqrt(area[id] * step * step) / areaFull)
        end
        size01 = math.min(fetch01, area01)
        -- calm in RED, and the channel is chosen for the failure mode. A
        -- sampler a driver could not bind -- or a vertex stage with zero
        -- texture units -- reads back vec4(0, 0, 0, 1): the colour channels
        -- are zero and ALPHA IS ONE. calm in alpha would come back 1 on
        -- exactly the devices that cannot read it, and every ocean in the
        -- game would go to puddle amplitude with nothing logged anywhere.
        -- In red it comes back 0, which is open water, which is the build
        -- this file replaced.
        --
        -- G / B are the two terms unmixed, for the probe. Nothing in the
        -- render path reads them.
        data:setPixel(i, j, 1 - size01, fetch01, area01, 1)
      elseif kind[k] == LAND then
        -- LAND IS THE CALMEST VALUE IN THE FIELD, not a don't-care. Water
        -- geometry near a bank bilinearly taps the texels across it, so
        -- whatever land holds is what the last half-cell of every lake ramps
        -- toward -- and the tap is the only shoaling term this shader has.
        --
        -- Held at open (calm 0) it ramped the wrong way: the field ran 0.9 in
        -- the first water cell to 0 on the bank, so the swell GREW into the
        -- shore and stepped by nearly the whole range in sixteen pixels. The
        -- offline probe caught it as a discontinuity, which is what it is --
        -- a wave that gets taller as the water gets shallower is not a small
        -- error in a shoreline, it is the shoreline upside down.
        data:setPixel(i, j, 1, 0, 0, 1)
      else
        -- UNKNOWN -- past the edge of the drawn world -- is the OPPOSITE, and
        -- this is exactly why the two are separate classes. There is no shore
        -- recorded out there because there is no map out there, and a sea
        -- that runs off the neighbourhood must not be given a coastline the
        -- world does not have.
        data:setPixel(i, j, 0, 0, 0, 1)
      end
    end
  end

  local ok, img = pcall(love.graphics.newImage, data)
  if not ok or not img then return nil end
  -- LINEAR, and it is load-bearing: the vertex stage displaces by
  -- Y = f(XZ) and the surface stays watertight only while f is continuous
  -- in XZ. A nearest tap would step the amplitude at every cell border and
  -- open a seam down the middle of every lake.
  pcall(img.setFilter, img, "linear", "linear")
  pcall(img.setWrap, img, "clamp", "clamp")

  return {
    image = img, data = data,
    ox = x0 * WaterBody.CELL, oz = z0 * WaterBody.CELL,
    w = w, h = h, step = step,
    -- world pixels one texel covers, which is what the shader needs to turn
    -- a world XZ into a UV
    span = WaterBody.CELL * step,
  }
end

-- ------- the live field

-- Called from VoxelScene.prefetch with the frame's state. Rebuilds only when
-- the drawn neighbourhood changes, which is a map crossing and nothing else.
function WaterBody.refresh(state)
  local list = places(state)
  if #list == 0 then return end
  local key = liveKey(list)
  if field and field.key == key then return end
  if failed[key] then return end
  local ok, built = pcall(bake, list)
  if not ok or not built then
    failed[key] = true
    WaterBody.drop()
    return
  end
  built.key = key
  if field and field.image and field.image.release then
    pcall(field.image.release, field.image)
  end
  field = built
end

function WaterBody.field()
  return field
end

function WaterBody.image()
  return field and field.image or nil
end

-- Origin and inverse extent, in the shape the shader wants:
--   uv = (world.xz - origin) * invSize
-- Texel i covers world [ox + i*span, ox + (i+1)*span), so its CENTRE is at
-- ox + (i+0.5)*span and lands at uv (i+0.5)/w -- which is what makes this
-- expression a plain divide with no half-texel term in it.
function WaterBody.uvParams()
  if not field then return nil end
  return field.ox, field.oz,
         1 / (field.span * field.w), 1 / (field.span * field.h)
end

-- ------- the CPU twin
--
-- Bilinear, because the shader's tap is bilinear and the surfer's feet ride
-- Water.surfaceAt while the mesh under them rides the vertex stage. Nearest
-- here would put the two on different oceans wherever the field changes,
-- which is every shoreline -- the one place a body in the water is most
-- likely to be looked at closely.
local function tap(f, i, j)
  if i < 0 then i = 0 elseif i > f.w - 1 then i = f.w - 1 end
  if j < 0 then j = 0 elseif j > f.h - 1 then j = f.h - 1 end
  local r = f.data:getPixel(i, j)
  return r
end

-- `calm` at a world XZ: 0 open water, 1 the smallest puddle. Outside the
-- baked field, and with no field at all, the answer is 0 -- see the note at
-- the top on why the complement is what is stored.
function WaterBody.calmAt(wx, wz)
  local f = field
  if not (f and f.data) then return 0 end
  local fx = (((tonumber(wx) or 0) - f.ox) / f.span) - 0.5
  local fz = (((tonumber(wz) or 0) - f.oz) / f.span) - 0.5
  local i0 = math.floor(fx)
  local j0 = math.floor(fz)
  local tx = fx - i0
  local tz = fz - j0
  local a = tap(f, i0,     j0)
  local b = tap(f, i0 + 1, j0)
  local c = tap(f, i0,     j0 + 1)
  local d = tap(f, i0 + 1, j0 + 1)
  local top = a + (b - a) * tx
  local bot = c + (d - c) * tx
  return top + (bot - top) * tz
end

-- 1 open water .. 0 the smallest puddle. The number Water actually shapes
-- the swell with.
function WaterBody.sizeAt(wx, wz)
  local n = 1 - WaterBody.calmAt(wx, wz)
  if n < 0 then return 0 elseif n > 1 then return 1 end
  return n
end

function WaterBody.on()
  return field ~= nil
end

-- Always-bound stand-in for the scene shader's waterField sampler. An
-- unbound sampler is a driver-dependent crash rather than a fallback (the
-- rule Water.artBlank and GlassMask.blank already follow), so the switch is
-- the `waterFieldOn` uniform and never the binding.
--
-- BLACK, deliberately: red is the complement, so 0 is open water and a frame
-- that somehow reads this anyway gets the pre-field ocean.
local blank = nil     -- Image | false
function WaterBody.blank()
  if blank == nil then
    local ok, img = pcall(function()
      local d = love.image.newImageData(1, 1)
      d:setPixel(0, 0, 0, 0, 0, 1)
      local i = love.graphics.newImage(d)
      pcall(i.setFilter, i, "nearest", "nearest")
      return i
    end)
    blank = (ok and img) or false
  end
  return blank or nil
end

-- Hot reload / window resize / a map registry that moved under us.
function WaterBody.drop()
  if field and field.image and field.image.release then
    pcall(field.image.release, field.image)
  end
  field = nil
  if blank and blank ~= false and blank.release then
    pcall(blank.release, blank)
  end
  blank = nil
end

function WaterBody.invalidate()
  WaterBody.drop()
  failed = {}
end

return WaterBody
