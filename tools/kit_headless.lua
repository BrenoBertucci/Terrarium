-- HEADLESS RENDER HARNESS -- the Lua half.
--
-- Runs a REAL kit module out of lib/ with no game around it: no LOVE, no
-- window, no atlas upload, no mesher. The point is to look at voxel
-- geometry in seconds instead of the ~60 a game launch plus a screenshot
-- probe costs, and to catch the errors that are LOGIC (a signature that
-- never matches, a model that returns nil, a wall that emits its own
-- seam) rather than shading.
--
-- What it fakes:
--
--   love        image/graphics/filesystem/timer, enough for a kit to LOAD
--               and to read one preloaded ImageData. Nothing draws.
--   V           the mod namespace main.lua builds: V.require resolves to
--               lib/<name>.lua (with V passed as the vararg, exactly as
--               the game does), V.data to data/<name>.lua, V.path and
--               V.mod.read to the mod tree on disk.
--   ModSetting  a stand-in with the real module's surface, whose rows are
--               FORCED to the values the job names -- so a probe can ask
--               for CRYPT=new, CRYPT-FX=off without a save file.
--
-- What it reproduces from lib/Buildings.lua (which is NOT called: `read`
-- and `emit` are locals in that file, so this is a transcription, and the
-- one place this harness can drift from the game -- see kit_headless.md):
--
--   read        composite the template out of the atlas and flood the
--               silhouette in from the border -> { W, H, col, ax, ay,
--               inside }, the sprite table every kit's `model` is handed.
--   emit        walk every voxel of the box and merge runs of
--               texel-adjacent exposed faces into quads, honouring the
--               PHANTOM rule (a negative index OCCLUDES for the
--               hidden-face test and the corner AO but is never drawn),
--               the per-direction SHADE table, the model's own `tint`,
--               and the post-merge corner AO.
--
-- Driven by tools/kit_headless.py, which writes a job file and reads the
-- binary face dump back. Never run by the game.

local job = assert(loadfile(assert(KH_JOB, "KH_JOB not set")))()

local floor, min, max = math.floor, math.min, math.max
local schar, sbyte = string.char, string.byte

local root = job.root:gsub("\\", "/")
if root:sub(-1) ~= "/" then root = root .. "/" end

-- Errors are DEDUPED and capped: a signature that fails once fails on
-- every placement, and 66 copies of one line hide the other two.
local errors, seenError = {}, {}
local function note(fmt, ...)
  local s = select("#", ...) > 0 and fmt:format(...) or fmt
  if seenError[s] then
    seenError[s] = seenError[s] + 1
    return
  end
  seenError[s] = 1
  errors[#errors + 1] = s
end
local function finishErrors()
  for i, s in ipairs(errors) do
    local n = seenError[s]
    if n and n > 1 then errors[i] = ("%s  (x%d)"):format(s, n) end
  end
end

-- ---------------------------------------------------------- image data --
--
-- Whatever Python decoded for us: a flat channel dump plus its size. The
-- surface is LOVE's ImageData as far as anything in lib/ uses it
-- (getPixel returns 0..1 floats, getDimensions returns w, h).

local function readAll(path, mode)
  local f = io.open(path, mode or "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function imageData(path, w, h, chan)
  local bytes = readAll(path)
  if not bytes then return nil end
  local o = { __kh = path }
  function o:getDimensions() return w, h end
  function o:getWidth() return w end
  function o:getHeight() return h end
  function o:getPixel(x, y)
    x, y = floor(x), floor(y)
    if x < 0 or y < 0 or x >= w or y >= h then return 0, 0, 0, 0 end
    local i = (y * w + x) * chan + 1
    if chan == 1 then
      local v = sbyte(bytes, i) / 255
      return v, v, v, 1
    end
    local r, g, b, a = sbyte(bytes, i, i + 3)
    return r / 255, g / 255, b / 255, a / 255
  end
  return o
end

local atlas = assert(imageData(job.atlas.path, job.atlas.w, job.atlas.h, 4),
                     "atlas dump missing: " .. tostring(job.atlas.path))

-- Assets a kit reads through V.mod.read + love.image.newImageData (the
-- crypt's wall height map is the case). Keyed by the mod-relative path
-- the kit asks for; the sentinel below is what V.mod.read hands back for
-- one, so newImageData can recognise it without decoding a PNG in Lua.
local SENTINEL = "\1KH-PRELOAD\1"
local preload = {}
for _, p in ipairs(job.preload or {}) do
  local d = imageData(p.path, p.w, p.h, p.chan)
  if d then preload[p.rel] = d else note("preload failed: %s", p.rel) end
end

-- ------------------------------------------------------------- the love --

local function stubTable()
  return setmetatable({}, { __index = function() return function() end end })
end

love = {
  image = {
    newImageData = function(v)
      if type(v) == "string" then
        local rel = v:match("^" .. SENTINEL .. "(.+)$")
        if rel and preload[rel] then return preload[rel] end
        -- a bare path: strip the mod root and try again
        local p = v:gsub("\\", "/")
        local tail = p:sub(#root + 1)
        if preload[tail] then return preload[tail] end
        error("kit_headless: no preloaded image for " .. tostring(v), 0)
      end
      error("kit_headless: newImageData wants a preloaded path", 0)
    end,
  },
  -- the kit hands bytes to newByteData and the result to newImageData;
  -- our "bytes" are the sentinel, so this is identity
  data = { newByteData = function(s) return s end },
  graphics = stubTable(),
  filesystem = setmetatable({
    getInfo = function() return nil end,
    read = function() return nil end,
  }, { __index = function() return function() end end }),
  timer = { getTime = os.clock },
  math = stubTable(),
  window = stubTable(),
}

-- -------------------------------------------------------------- the V --

local V = { path = root:sub(1, -2) }
V.mod = {
  id = "TERRARIUM",
  path = V.path,
  read = function(_, rel)
    if preload[rel] then return SENTINEL .. rel end
    return readAll(root .. rel)
  end,
}

-- The ModSetting stand-in: the real module's surface, reading from the
-- job's forced table instead of a save file. `job.settings` is keyed by
-- the setting KEY ("crypt", "cryptfx", "tower", ...); an unnamed row
-- falls back to values[1], which is what the shipped default is.
local forced = job.settings or {}
local MS = {}
MS.__index = MS
function MS.new(key, label, values, labels)
  return setmetatable({ key = key, label = label,
                        values = values, labels = labels }, MS)
end
function MS:read()
  local want = forced[self.key]
  if want ~= nil then
    for i, v in ipairs(self.values) do if v == want then return i end end
    note("setting %s: no such value %s", tostring(self.key), tostring(want))
  end
  return 1
end
function MS:get() return self.values[self:read()] end
function MS:level() return self:read() - 1 end
function MS:setIndex(i)
  local n = #self.values
  i = ((i - 1) % n + n) % n + 1
  forced[self.key] = self.values[i]
  return self.values[i]
end
function MS:cycle(_, dir) return self:setIndex(self:read() + (dir or 1)) end
function MS:sync(value) if value ~= nil then forced[self.key] = value end end
function MS:row()
  local self_ = self
  return { id = "TERRARIUM:" .. self.key, label = self.label,
           value = function() return self_.labels[self_:read()] end,
           step = function(_, dir) self_:cycle(nil, dir) return true end }
end
function MS:schema() return { key = self.key, label = self.label } end

local stubbed = {}
for _, name in ipairs(job.stubs or {}) do stubbed[name] = true end

local modules = { ModSetting = MS }
function V.require(name)
  local hit = modules[name]
  if hit ~= nil then return hit end
  if stubbed[name] then
    modules[name] = stubTable()
    return modules[name]
  end
  local rel = "lib/" .. name .. ".lua"
  local src = readAll(root .. rel)
  if not src then error("kit_headless: missing " .. rel, 0) end
  local chunk, err = load(src, "@" .. root .. rel)
  if not chunk then error("kit_headless: " .. rel .. ": " .. err, 0) end
  local value = chunk(V)
  modules[name] = value
  return value
end

local dataFiles = {}
function V.data(name)
  local hit = dataFiles[name]
  if hit ~= nil then return hit end
  local rel = "data/" .. name .. ".lua"
  local src = assert(readAll(root .. rel), "missing " .. rel)
  local chunk, err = load(src, "@" .. root .. rel)
  if not chunk then error("kit_headless: " .. rel .. ": " .. err, 0) end
  local value = chunk(V)
  dataFiles[name] = value
  return value
end
function V.uncacheData(name) dataFiles[name] = nil end

-- ------------------------------------------------- Buildings constants --
--
-- PHANTOM is read off the REAL module so the harness cannot drift from
-- it (and so a broken lib/Buildings.lua fails loudly here). SHADE is a
-- local in that file and has to be transcribed -- see kit_headless.md.

local PHANTOM = -1
local buildingsOk = false
do
  local ok, B = pcall(V.require, "Buildings")
  if ok and type(B) == "table" then
    buildingsOk = true
    if type(B.PHANTOM) == "number" then PHANTOM = B.PHANTOM end
  else
    note("lib/Buildings.lua did not load: %s", tostring(B))
  end
end

local SHADE = { top = 0.95, south = 1.0, north = 0.68,
                side = 0.78, bottom = 0.5 }

-- --------------------------------------------------------------- read --
--
-- Transcribed from Buildings.read: composite the template's tiles (with
-- `paint` standing in for `tiles` when it carries one, and `topRows`
-- composited above), classify each texel into the four GB shades, then
-- flood the OUTSIDE in from every border side the template does not
-- `seal`.

local WHITE, GREY, DARK, BLACK = 0, 1, 2, 3

local function shadeOf(r, g, b, a)
  if a == 0 then return WHITE end
  local v = min(r, g, b)
  if v <= 0.25 then return BLACK end
  if v <= 0.55 then return DARK end
  if v <= 0.85 then return GREY end
  return WHITE
end

local function readSprite(t, data, perRow)
  local tiles = t.paint or t.tiles
  if t.topRows then
    local src = tiles
    tiles = {}
    for _, row in ipairs(t.topRows) do tiles[#tiles + 1] = row end
    for _, row in ipairs(src) do tiles[#tiles + 1] = row end
  end
  local bh, bw = #tiles, #t.tiles[1]
  local W, H = bw * 8, bh * 8
  local col, ax, ay = {}, {}, {}
  for sy = 0, H - 1 do
    local row = tiles[floor(sy / 8) + 1]
    for sx = 0, W - 1 do
      local tile = row[floor(sx / 8) + 1]
      local px = (tile % perRow) * 8 + sx % 8
      local py = floor(tile / perRow) * 8 + sy % 8
      local i = sy * W + sx
      ax[i], ay[i] = px, py
      local r, g, b, a = data:getPixel(px, py)
      col[i] = shadeOf(r, g, b, a)
    end
  end

  local outside = {}
  local queue, n = {}, 0
  local function seed(x, y)
    local i = y * W + x
    if not outside[i] and col[i] <= GREY then
      outside[i] = true
      n = n + 1
      queue[n] = i
    end
  end
  local seal = t.seal or ""
  local function sealed(side) return string.find(seal, side, 1, true) ~= nil end
  for x = 0, W - 1 do
    if not sealed("n") then seed(x, 0) end
    if not sealed("s") then seed(x, H - 1) end
  end
  for y = 0, H - 1 do
    if not sealed("w") then seed(0, y) end
    if not sealed("e") then seed(W - 1, y) end
  end
  while n > 0 do
    local i = queue[n]
    n = n - 1
    local x, y = i % W, floor(i / W)
    if x + 1 < W then seed(x + 1, y) end
    if x > 0 then seed(x - 1, y) end
    if y + 1 < H then seed(x, y + 1) end
    if y > 0 then seed(x, y - 1) end
  end

  local inside = {}
  for i = 0, W * H - 1 do inside[i] = not outside[i] end
  return { W = W, H = H, col = col, ax = ax, ay = ay, inside = inside }
end

-- ------------------------------------------------------- read a sheet --
--
-- The OTHER sprite source: Buildings.readSprite, the `spriteBand` path,
-- where the template is drawn on an authored PNG instead of composited
-- out of the four-grey tileset (lib/ShopKit.lua's shop_sheet.png). Same
-- struct plus `role` and `path`; the flood comes in through fully
-- transparent pixels rather than through light ones, and ax/ay are the
-- sheet's own pixels because the sheet IS the atlas.

local ROLE_WALL, ROLE_ROOF, ROLE_AWNING, ROLE_BALL = 1, 2, 3, 4
local ROLE_PLANT, ROLE_POST, ROLE_GLASS, ROLE_WINDOW = 5, 6, 7, 8

local function classify(r, g, b, a, sy, H)
  if a < 0.04 then return 0 end
  local u = sy / H
  if g > r + 0.08 and g > b + 0.04 and g > 0.22 then return ROLE_PLANT end
  if r > g + 0.10 and r > b + 0.08 and r > 0.32 then
    if u < 0.50 then return ROLE_BALL end
    if u > 0.84 then return ROLE_POST end
    if u < 0.64 then return ROLE_AWNING end
    return ROLE_POST
  end
  if min(r, g, b) > 0.70 and u > 0.38 and u < 0.62 then return ROLE_BALL end
  if u < 0.34 and b > r + 0.06 and b > 0.28 then return ROLE_ROOF end
  if max(r, g, b) < 0.38 and u > 0.50 and u < 0.86 then return ROLE_WINDOW end
  if u > 0.52 and u < 0.88 and b > r + 0.04 and b > 0.35 then
    return ROLE_GLASS
  end
  return ROLE_WALL
end

local function readSheet(data, rel)
  local W, H = data:getDimensions()
  if not W or not H or W < 4 or H < 4 then return nil end
  local col, ax, ay, inside, role, alpha = {}, {}, {}, {}, {}, {}
  for sy = 0, H - 1 do
    for sx = 0, W - 1 do
      local i = sy * W + sx
      local r, g, b, a = data:getPixel(sx, sy)
      ax[i], ay[i] = sx, sy
      col[i] = shadeOf(r, g, b, a)
      alpha[i] = a
      role[i] = classify(r, g, b, a, sy, H)
    end
  end
  local outside = {}
  local queue, n = {}, 0
  local function seed(x, y)
    local i = y * W + x
    if not outside[i] and (alpha[i] or 0) < 0.04 then
      outside[i] = true
      n = n + 1
      queue[n] = i
    end
  end
  for x = 0, W - 1 do seed(x, 0) seed(x, H - 1) end
  for y = 0, H - 1 do seed(0, y) seed(W - 1, y) end
  while n > 0 do
    local i = queue[n]
    n = n - 1
    local x, y = i % W, floor(i / W)
    if x + 1 < W then seed(x + 1, y) end
    if x > 0 then seed(x - 1, y) end
    if y + 1 < H then seed(x, y + 1) end
    if y > 0 then seed(x, y - 1) end
  end
  local nIn = 0
  for i = 0, W * H - 1 do
    inside[i] = not outside[i]
    if inside[i] then nIn = nIn + 1 end
  end
  if nIn < 32 then return nil end
  return { W = W, H = H, col = col, ax = ax, ay = ay,
           inside = inside, role = role, path = rel }
end

-- --------------------------------------------------------------- emit --
--
-- Transcribed from Buildings.emit. Same cell walk, same PHANTOM rule
-- (`v >= 0` is what makes a negative index occlude without drawing),
-- same greedy runs, same corner AO, same `tint` hook. The uv maths is
-- replaced by the run's first texel's ATLAS coordinate, which is what
-- the Python side colours a face with.
--
-- Faces come back as a flat array of 20 numbers each:
--   1..12  four corners, x y z
--  13..16  the four corner shades
--  17,18   the run's first texel in the atlas (ax, ay)
--     19   direction: 1 s(+z) 2 n(-z) 3 up(+y) 4 down(-y) 5 e(+x) 6 w(-x)
--     20   0 (padding, so the record is a clean 20 x uint16)

local DIR_S, DIR_N, DIR_UP, DIR_DN, DIR_E, DIR_W = 1, 2, 3, 4, 5, 6

local function emit(m, sp, sink)
  local Wm = m.W
  local stats = { voxels = 0, shell = 0, faces = 0 }
  local cell = {}

  local zmin, zmax, ytop = m.zmin, m.zmax, m.ytop
  local xmin, xmax = m.xmin or 0, m.xmax or (Wm - 1)
  local zn = zmax - zmin + 1
  local xn = xmax - xmin + 1

  local function ci(x, y, z)
    if x < xmin or x > xmax or y < 0 or y > ytop or z < zmin or z > zmax then
      return nil
    end
    return cell[(y * zn + (z - zmin)) * xn + (x - xmin)]
  end
  for y = 0, ytop do
    for z = zmin, zmax do
      local base = (y * zn + (z - zmin)) * xn - xmin
      for x = xmin, xmax do
        local v = m.at(x, y, z)
        cell[base + x] = v
        if v and v >= 0 then stats.voxels = stats.voxels + 1 end
      end
    end
  end
  for y = 0, ytop do
    for z = zmin, zmax do
      for x = xmin, xmax do
        local v = ci(x, y, z)
        if v and v >= 0 and not (ci(x + 1, y, z) and ci(x - 1, y, z)
            and ci(x, y + 1, z) and ci(x, y - 1, z)
            and ci(x, y, z + 1) and ci(x, y, z - 1)) then
          stats.shell = stats.shell + 1
        end
      end
    end
  end

  local AO_STEP, AO_FLOOR = 0.09, 0.25
  local function aoCorner(s1, s2, dg)
    local k = 0
    if s1 then k = k + 1 end
    if s2 then k = k + 1 end
    if dg and not (s1 and s2) then k = k + 1 end
    if k == 0 then return 1 end
    local f = 1 - AO_STEP * k
    if f < AO_FLOOR then f = AO_FLOOR end
    return f
  end

  -- PARITY: lib/Buildings.lua's `contact` hook -- a per-CORNER factor in
  -- the model's own voxels, folded into the UP faces' corner shades. It is
  -- transcribed here for the same reason the rest of emit is: a harness
  -- that cannot see a kit's shadow would have reported ShopKit's contact
  -- field as a no-op.
  local contactOf = m.contact
  local function cf(x, y, z)
    if not contactOf then return 1 end
    return contactOf(x, y, z)
  end

  local tintOf = m.tint
  local function lit(shade, y, i, dir)
    if not tintOf then return shade end
    return shade * tintOf(y, i, dir, shade)
  end

  local ax, ay = sp.ax, sp.ay
  local function put(c1, c2, c3, c4, i, dir, base, f1, f2, f3, f4)
    stats.faces = stats.faces + 1
    sink(c1[1], c1[2], c1[3], c2[1], c2[2], c2[3],
         c3[1], c3[2], c3[3], c4[1], c4[2], c4[3],
         base * f1, base * f2, base * f3, base * f4,
         ax[i] or 0, ay[i] or 0, dir)
  end

  local function runX(y, z, dx, dy, dz, x)
    local i0 = ci(x, y, z)
    local strip, n = nil, 1
    while true do
      if n > xn then break end
      local nx = x + n
      local i = ci(nx, y, z)
      if not i or i < 0 or ci(nx + dx, y + dy, z + dz) then break end
      local prev = ci(nx - 1, y, z)
      if ay[i] ~= ay[prev] then break end
      local d = ax[i] - ax[prev]
      if d == 1 then
        if strip == false then break end
        strip = true
      elseif d == 0 then
        if strip == true then break end
        strip = false
      else
        break
      end
      n = n + 1
    end
    return i0, strip == true, n
  end

  -- ---- +-Z: the facade, the roof's rims. Merge along x.
  for _, d in ipairs({ 1, -1 }) do
    local shade = d == 1 and SHADE.south or SHADE.north
    local dir = d == 1 and DIR_S or DIR_N
    for y = 0, ytop do
      for z = zmin, zmax do
        local x = xmin
        while x <= xmax do
          local v = ci(x, y, z)
          if v and v >= 0 and not ci(x, y, z + d) then
            local i, _, n = runX(y, z, 0, 0, d, x)
            local zf = d == 1 and (z + 1) or z
            local zo = z + d
            local xl, xr = x - 1, x + n
            local xe0, xe1 = x, x + n - 1
            local yd, yu = y - 1, y + 1
            local sBL = aoCorner(ci(xl, y, zo), ci(xe0, yd, zo), ci(xl, yd, zo))
            local sBR = aoCorner(ci(xr, y, zo), ci(xe1, yd, zo), ci(xr, yd, zo))
            local sTR = aoCorner(ci(xr, y, zo), ci(xe1, yu, zo), ci(xr, yu, zo))
            local sTL = aoCorner(ci(xl, y, zo), ci(xe0, yu, zo), ci(xl, yu, zo))
            if d == 1 then
              put({ x, y, zf }, { x + n, y, zf },
                  { x + n, y + 1, zf }, { x, y + 1, zf },
                  i, dir, lit(shade, y, i, "s"), sBL, sBR, sTR, sTL)
            else
              put({ x + n, y, zf }, { x, y, zf },
                  { x, y + 1, zf }, { x + n, y + 1, zf },
                  i, dir, lit(shade, y, i, "n"), sBR, sBL, sTL, sTR)
            end
            x = x + n
          else
            x = x + 1
          end
        end
      end
    end
  end

  -- ---- +-Y: roof surfaces, undersides. Merge along x.
  for _, d in ipairs({ 1, -1 }) do
    local shade = d == 1 and SHADE.top or SHADE.bottom
    local dir = d == 1 and DIR_UP or DIR_DN
    for y = 0, ytop do
      if not (d == -1 and y == 0) then
        for z = zmin, zmax do
          local x = xmin
          while x <= xmax do
            local v = ci(x, y, z)
            if v and v >= 0 and not ci(x, y + d, z) then
              local i, _, n = runX(y, z, 0, d, 0, x)
              local yf = d == 1 and (y + 1) or y
              local yo = y + d
              local xl, xr = x - 1, x + n
              local xe0, xe1 = x, x + n - 1
              local zd, zu = z - 1, z + 1
              local f1 = aoCorner(ci(xl, yo, z), ci(xe0, yo, zd), ci(xl, yo, zd))
              local f2 = aoCorner(ci(xr, yo, z), ci(xe1, yo, zd), ci(xr, yo, zd))
              local f3 = aoCorner(ci(xr, yo, z), ci(xe1, yo, zu), ci(xr, yo, zu))
              local f4 = aoCorner(ci(xl, yo, z), ci(xe0, yo, zu), ci(xl, yo, zu))
              if d == 1 then
                put({ x, yf, z }, { x + n, yf, z },
                    { x + n, yf, z + 1 }, { x, yf, z + 1 },
                    i, dir, lit(shade, y, i, "up"),
                    f1 * cf(x, yf, z), f2 * cf(x + n, yf, z),
                    f3 * cf(x + n, yf, z + 1), f4 * cf(x, yf, z + 1))
              else
                put({ x, yf, z + 1 }, { x + n, yf, z + 1 },
                    { x + n, yf, z }, { x, yf, z },
                    i, dir, lit(shade, y, i, "down"), f4, f3, f2, f1)
              end
              x = x + n
            else
              x = x + 1
            end
          end
        end
      end
    end
  end

  -- ---- +-X: the flanks. Merge along z, one texel each.
  for _, d in ipairs({ 1, -1 }) do
    local dir = d == 1 and DIR_E or DIR_W
    for y = 0, ytop do
      for x = xmin, xmax do
        local z = zmin
        while z <= zmax do
          local i = ci(x, y, z)
          if i and i >= 0 and not ci(x + d, y, z) then
            local n = 1
            while z + n <= zmax do
              local j = ci(x, y, z + n)
              if j ~= i or ci(x + d, y, z + n) then break end
              n = n + 1
            end
            local xf = d == 1 and (x + 1) or x
            local xo = x + d
            local zl, zr = z - 1, z + n
            local ze0, ze1 = z, z + n - 1
            local yd, yu = y - 1, y + 1
            local fBn = aoCorner(ci(xo, y, zr), ci(xo, yd, ze1), ci(xo, yd, zr))
            local fB0 = aoCorner(ci(xo, y, zl), ci(xo, yd, ze0), ci(xo, yd, zl))
            local fT0 = aoCorner(ci(xo, y, zl), ci(xo, yu, ze0), ci(xo, yu, zl))
            local fTn = aoCorner(ci(xo, y, zr), ci(xo, yu, ze1), ci(xo, yu, zr))
            if d == 1 then
              put({ xf, y, z + n }, { xf, y, z },
                  { xf, y + 1, z }, { xf, y + 1, z + n },
                  i, dir, lit(SHADE.side, y, i, "e"), fBn, fB0, fT0, fTn)
            else
              put({ xf, y, z }, { xf, y, z + n },
                  { xf, y + 1, z + n }, { xf, y + 1, z },
                  i, dir, lit(SHADE.side, y, i, "w"), fB0, fBn, fTn, fT0)
            end
            z = z + n
          else
            z = z + 1
          end
        end
      end
    end
  end

  return stats
end

-- ------------------------------------------------------- the face sink --
--
-- 20 x uint16 big-endian per face. Coordinates carry a +1024 bias (a
-- model may stand at x = -6), shades are x1000.

local BIAS = 1024
local outFile = assert(io.open(job.out, "wb"), "cannot write " .. job.out)
local bytes, bl = {}, 0
local chunks, cn = {}, 0

local function flushBytes()
  if bl > 0 then
    cn = cn + 1
    chunks[cn] = schar(unpack(bytes, 1, bl))
    bl = 0
    if cn >= 256 then
      outFile:write(table.concat(chunks, "", 1, cn))
      cn = 0
    end
  end
end

local function u16(v)
  if v < 0 then v = 0 elseif v > 65535 then v = 65535 end
  v = floor(v)
  bytes[bl + 1] = floor(v / 256)
  bytes[bl + 2] = v % 256
  bl = bl + 2
  if bl >= 512 then flushBytes() end
end

local totalFaces = 0

-- Replaying a built model at a new offset: emit() runs ONCE per distinct
-- signature (as Buildings.build caches one model per key) and the faces
-- are kept, then stamped per placement -- which is what makes 66
-- placements over 47 models cost 47 builds. `tex` is which image the
-- run's ax/ay index: 0 the map's tileset, 1..n an authored sheet.
local function replay(faces, ox, oz, tex)
  local n = #faces
  for k = 1, n, 19 do
    u16(faces[k] + ox + BIAS)      u16(faces[k + 1] + BIAS)  u16(faces[k + 2] + oz + BIAS)
    u16(faces[k + 3] + ox + BIAS)  u16(faces[k + 4] + BIAS)  u16(faces[k + 5] + oz + BIAS)
    u16(faces[k + 6] + ox + BIAS)  u16(faces[k + 7] + BIAS)  u16(faces[k + 8] + oz + BIAS)
    u16(faces[k + 9] + ox + BIAS)  u16(faces[k + 10] + BIAS) u16(faces[k + 11] + oz + BIAS)
    u16(faces[k + 12] * 1000) u16(faces[k + 13] * 1000)
    u16(faces[k + 14] * 1000) u16(faces[k + 15] * 1000)
    u16(faces[k + 16]) u16(faces[k + 17]) u16(faces[k + 18]) u16(tex)
    totalFaces = totalFaces + 1
  end
end

-- ------------------------------------------------------------ the world --

local function keyOf(tx, ty) return (ty + 64) * 4096 + (tx + 64) end

local G = job.grid
local gw, gh, gt = G.w, G.h, G.tiles
local function tileAt(x, y)
  if x < 0 or y < 0 or x >= gw or y >= gh then return nil end
  return gt[y * gw + x + 1]
end

local map = { def = { id = job.map.id, name = job.map.id,
                      width = job.map.width, height = job.map.height },
              id = job.map.id,
              tileset = { id = job.tileset, image = job.atlas.image,
                          imageWidth = job.atlas.w, imageHeight = job.atlas.h,
                          tilesPerRow = job.atlas.perRow } }

local Kit = V.require(job.kit)
if type(Kit) ~= "table" or type(Kit.model) ~= "function" then
  error(("kit_headless: lib/%s.lua exposes no model()"):format(job.kit), 0)
end
-- `signature` is OPTIONAL. A kit that decides its model per PLACEMENT
-- (CryptKit: which sides face the room, how tall the row stands) has
-- one; a kit whose model depends only on the TEMPLATE (ShopKit: one
-- band per template, out of one room function) does not, and its
-- signature is just the template's id -- one model per template, which
-- is what Buildings.build's plain branch caches anyway.
local hasSig = type(Kit.signature) == "function"

-- The authored sheets the config named, by mod-relative path, with the
-- index the face dump records so the render knows which image an ax/ay
-- belongs to (0 is the map's own tileset).
local sheets = {}
for k, s in ipairs(job.sheets or {}) do
  local d = imageData(s.path, s.w, s.h, s.chan)
  if d then
    local sp = readSheet(d, s.rel)
    if sp then
      sp.__tex = k
      sheets[s.rel] = sp
    else
      note("sheet unreadable (too small, or nothing opaque): %s", s.rel)
    end
  else
    note("sheet dump missing: %s", s.rel)
  end
end

-- Buildings.build asks the kit's own row before it models anything, and
-- an off kit stamps NOTHING and claims nothing (the profile's class pins
-- stand the tiles instead). Reproduced so `--set crypt=classic` answers
-- the way the game does.
local kitOn = true
if type(Kit.enabled) == "function" then
  local okE, on = pcall(Kit.enabled)
  kitOn = (not okE) or (on ~= false)
end

local spec = V.data("voxel_heights")
local list = spec and spec.buildings and spec.buildings[job.tileset]
if type(list) ~= "table" then
  error(("kit_headless: data/voxel_heights.lua has no buildings.%s")
        :format(job.tileset), 0)
end

local skip = {}
local report = { kit = job.kit, map = job.map.id, tileset = job.tileset,
                 templates = {}, models = {}, placements = {} }

local function placedOn(t)
  if not t.maps then return true end
  return t.maps[job.map.id] and true or false
end

local built = {}               -- key -> { faces = {...}, stats = {...} }
local mark = job.mark
local only = job.only
local perRow = job.atlas.perRow

local tw, th = job.map.width * 4, job.map.height * 4
local t0all = os.clock()

for index, t in ipairs(list) do
  local mine = (mark == nil) or (t[mark] ~= nil)
  if only and tostring(t.id) ~= only then mine = false end
  local tstat = { id = tostring(t.id), index = index, mine = mine and 1 or 0,
                  placements = 0, models = 0, faces = 0, seconds = 0 }
  report.templates[#report.templates + 1] = tstat
  if type(t.tiles) == "table" and #t.tiles > 0 and placedOn(t) then
    local bh, bw = #t.tiles, #t.tiles[1]
    local where = t.where
    local first = t.tiles[1][1]
    local sp = nil
    for ty = 0, th - bh do
      for tx = 0, tw - bw do
        local free = tileAt(tx, ty) == first
        if free and where then
          free = tx >= where[1] and ty >= where[2]
                 and tx <= where[3] and ty <= where[4]
        end
        if free then
          for r = 0, bh - 1 do
            for c = 0, bw - 1 do
              if skip[keyOf(tx + c, ty + r)] then free = false break end
            end
            if not free then break end
          end
        end
        if free then
          for r = 1, bh do
            local row = t.tiles[r]
            for c = 1, #row do
              if tileAt(tx + c - 1, ty + r - 1) ~= row[c] then free = false break end
            end
            if not free then break end
          end
        end
        if free then
          local claim, maskOf = true, nil
          if mine and not kitOn then
            -- the row is off: no model, no claim
            claim = false
            tstat.placements = tstat.placements + 1
          elseif mine then
            local tp = os.clock()
            -- Which drawing this template is read from: an authored
            -- sheet it names (`t.sprite`), the kit's default sheet, or
            -- the map's own tileset composited by `read`.
            if not sp then
              local rel = t.sprite or job.sheet
              sp = rel and sheets[rel] or nil
              if rel and not sp then
                note("%s: no sheet loaded for %s", tstat.id, tostring(rel))
              end
              sp = sp or readSprite(t, atlas, perRow)
            end
            local sig
            if hasSig then
              local okS, got = pcall(Kit.signature, t, tileAt, tx, ty, map)
              if okS then sig = got
              else note("%s signature @%d,%d: %s", tstat.id, tx, ty,
                        tostring(got)) end
            else
              sig = tostring(t.id or index)
            end
            if sig ~= nil then
              sig = tostring(sig)
              local key = index .. "@" .. sig
              local hit = built[key]
              if not hit then
                local tb = os.clock()
                local faces = {}
                local nf = 0
                local okM, m, why = pcall(Kit.model, sp, t, sig)
                if okM and m then
                  local st = emit(m, sp, function(
                      a1, a2, a3, a4, a5, a6, a7, a8, a9, a10,
                      a11, a12, a13, a14, a15, a16, a17, a18, a19)
                    faces[nf + 1] = a1   faces[nf + 2] = a2   faces[nf + 3] = a3
                    faces[nf + 4] = a4   faces[nf + 5] = a5   faces[nf + 6] = a6
                    faces[nf + 7] = a7   faces[nf + 8] = a8   faces[nf + 9] = a9
                    faces[nf + 10] = a10 faces[nf + 11] = a11 faces[nf + 12] = a12
                    faces[nf + 13] = a13 faces[nf + 14] = a14 faces[nf + 15] = a15
                    faces[nf + 16] = a16 faces[nf + 17] = a17 faces[nf + 18] = a18
                    faces[nf + 19] = a19
                    nf = nf + 19
                  end)
                  hit = { faces = faces, stats = st, claimMask = m.claimMask,
                          seconds = os.clock() - tb, sig = sig,
                          tex = sp.__tex or 0 }
                else
                  note("%s model @%s: %s", tstat.id, sig,
                       tostring(okM and why or m))
                  hit = { faces = {}, stats = { voxels = 0, shell = 0, faces = 0 },
                          seconds = os.clock() - tb, sig = sig, tex = 0 }
                end
                built[key] = hit
                tstat.models = tstat.models + 1
                report.models[#report.models + 1] = {
                  key = key, id = tstat.id, sig = sig,
                  faces = hit.stats.faces, voxels = hit.stats.voxels,
                  shell = hit.stats.shell, seconds = hit.seconds }
              end
              -- Buildings.stamp: an empty model claims nothing
              if #hit.faces == 0 then claim = false end
              maskOf = hit.claimMask
              replay(hit.faces, tx * 8, ty * 8, hit.tex or 0)
              tstat.faces = tstat.faces + hit.stats.faces
              tstat.placements = tstat.placements + 1
              tstat.seconds = tstat.seconds + (os.clock() - tp)
              report.placements[#report.placements + 1] = {
                id = tstat.id, tx = tx, ty = ty, sig = sig,
                faces = hit.stats.faces, ms = (os.clock() - tp) * 1000 }
            else
              claim = false
            end
          else
            -- not this kit's template: claim its cells anyway, so the
            -- first-claim-wins order Buildings.build relies on holds
            tstat.placements = tstat.placements + 1
          end
          if claim then
            -- Buildings.stamp: `claimRows` when the grid matches more
            -- rows than the model stands on; `claimMask` when a model
            -- shares its cell with tiles that are not its own
            local rows = t.claimRows or bh
            local mask = maskOf
            for r = 0, rows - 1 do
              for c = 0, bw - 1 do
                if not mask or mask[r * bw + c + 1] then
                  skip[keyOf(tx + c, ty + r)] = true
                end
              end
            end
          end
        end
      end
    end
  end
end

flushBytes()
if cn > 0 then outFile:write(table.concat(chunks, "", 1, cn)) end
outFile:close()

report.seconds = os.clock() - t0all
report.faces = totalFaces
report.models_total = 0
for _ in pairs(built) do report.models_total = report.models_total + 1 end
report.placements_total = #report.placements
report.buildings_loaded = buildingsOk and 1 or 0
report.kit_enabled = kitOn and 1 or 0
report.phantom = PHANTOM
finishErrors()
report.errors = errors

-- ------------------------------------------------------- the report ---
--
-- JSON, hand-rolled: the harness has no json library and the report is
-- flat numbers and short strings.

local function esc(s)
  return (tostring(s):gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    return ("\\u%04x"):format(c:byte())
  end))
end

local function enc(v)
  local tv = type(v)
  if tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "0" end
    if v == floor(v) then return ("%d"):format(v) end
    return ("%.6f"):format(v)
  end
  if tv == "boolean" then return v and "true" or "false" end
  if tv ~= "table" then return '"' .. esc(v) .. '"' end
  if #v > 0 or next(v) == nil then
    local out = {}
    for i = 1, #v do out[i] = enc(v[i]) end
    return "[" .. table.concat(out, ",") .. "]"
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  local out = {}
  for i, k in ipairs(keys) do out[i] = '"' .. esc(k) .. '":' .. enc(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end

local rf = assert(io.open(job.report, "wb"))
rf:write(enc(report))
rf:close()
