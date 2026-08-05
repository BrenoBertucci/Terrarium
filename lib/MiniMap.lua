-- Cheap orientation HUD for free-roam overworld.
--
-- Not the classic Town Map item, not a second world simulation, not a
-- full-screen pass. A small cel-shaded radar in the corner that drinks the
-- engine's own map record (cells, warps, connections, player) and draws a
-- handful of rectangles.
--
--   ON     always-on mini radar: paper frame, player pulse, facing, nearby
--          landmark icons (Center / Gym / Gate / Mart by warp dest name).
--   FULL   same, plus a 4-colour cell grid of the current map and edge
--          arrows for route connections. Regenerated only when the map
--          (or RES rung) changes -- not every frame.
--   OFF    nothing. Exists so a cost palindrome can measure ON vs OFF and
--          so a purist can hide it.
--
-- Memory contract: no region-sized buffer, no second screen-sized canvas,
-- no noise / normal maps. FULL may hold one Image of at most GRID_MAX²
-- RGBA (~37 KB at 96²) and releases it on map leave / OFF. Always-on
-- RAM is a few landmark rows in a Lua table.
--
-- Draw placement: worldPresent, AFTER tilt-shift, so the radar is not
-- blurred with the diorama and is not RES-downsampled with the 3D pass.
-- Purely presentational -- never writes collision, flags, warps or scripts.

local V = ...

local ModSetting = V.require("ModSetting")
local Quality = V.require("Quality")

local MiniMap = {}

-- Ladder: default ON (cheap always-on). FULL is the denser local view.
MiniMap.setting = ModSetting.new("minimap", "MAP",
                                 { "on", "full", "off" },
                                 { "ON", "FULL", "OFF" })

function MiniMap.enabled()
  local ok, v = pcall(MiniMap.setting.get, MiniMap.setting)
  return ok and v ~= "off"
end

function MiniMap.mode()
  local ok, v = pcall(MiniMap.setting.get, MiniMap.setting)
  if ok and (v == "on" or v == "full" or v == "off") then return v end
  return "on"
end

-- ------- palette (four flat tones + accents; cel-paper, not Unreal)

local COL = {
  paper   = { 0.93, 0.89, 0.76, 0.92 },
  ink     = { 0.18, 0.14, 0.11, 1.00 },
  walk    = { 0.72, 0.80, 0.52, 1.00 },
  water   = { 0.42, 0.62, 0.82, 1.00 },
  block   = { 0.52, 0.46, 0.38, 1.00 },
  player  = { 0.92, 0.22, 0.18, 1.00 },
  center  = { 0.95, 0.95, 0.98, 1.00 },
  gym     = { 0.78, 0.45, 0.18, 1.00 },
  gate    = { 0.55, 0.35, 0.72, 1.00 },
  mart    = { 0.28, 0.55, 0.88, 1.00 },
  route   = { 0.25, 0.45, 0.30, 1.00 },
  edge    = { 0.12, 0.10, 0.08, 1.00 },
}

-- ------- landmark kind from a warp destination map id

local function landmarkKind(dest)
  if type(dest) ~= "string" then return nil end
  local u = dest:upper()
  if u:find("POKECENTER", 1, true) or u:find("POKEMON_CENTER", 1, true)
     or u:find("PKMN_CENTER", 1, true) then
    return "center"
  end
  if u:find("GYM", 1, true) then return "gym" end
  if u:find("GATE", 1, true) then return "gate" end
  if u:find("MART", 1, true) then return "mart" end
  return nil
end

local function landmarkColor(kind)
  return COL[kind] or COL.ink
end

-- ------- live state (rebuilt on map / cell / mode / RES change)

local cache = {
  mapId = nil,
  mode = nil,
  res = nil,
  w = 0, h = 0,           -- map cells
  landmarks = {},         -- { cx, cy, kind, dest }
  connections = {},       -- { dir = "north"|..., map = id }
  -- FULL grid image (released on invalidate)
  gridImage = nil,
  gridW = 0, gridH = 0,
  -- last player sample for dirty checks / probe
  cellX = nil, cellY = nil, facing = nil,
  -- last drawn radar metrics for probe
  last = nil,
}

local function releaseGrid()
  if cache.gridImage and cache.gridImage.release then
    pcall(cache.gridImage.release, cache.gridImage)
  end
  cache.gridImage, cache.gridW, cache.gridH = nil, 0, 0
end

function MiniMap.invalidate()
  releaseGrid()
  cache.mapId, cache.mode, cache.res = nil, nil, nil
  cache.landmarks, cache.connections = {}, {}
  cache.w, cache.h = 0, 0
  cache.last = nil
end

local function game()
  return require("src.core.Game")
end

-- Radar pixel size from Quality.scale() (RES divisor 1..4).
-- scale 1 → 80, 2 → 64, 3 → 48, 4 → 40. At 3/4 FULL still drops to mini
-- detail (no grid) so RES-low never pays a per-cell scan every map.
local function radarSize(res, mode)
  if res <= 1 then return (mode == "full") and 96 or 80 end
  if res == 2 then return (mode == "full") and 80 or 64 end
  if res == 3 then return 48 end
  return 40
end

local function wantGrid(res, mode)
  return mode == "full" and res <= 2
end

-- Scan warps once per map. Cheap: outdoor towns have a few dozen warps.
local function collectLandmarks(map)
  local list = {}
  local warps = (map.def and map.def.warps) or {}
  for _, w in ipairs(warps) do
    local kind = landmarkKind(w.destMap)
    if kind and w.x and w.y then
      list[#list + 1] = {
        cx = w.x, cy = w.y, kind = kind, dest = w.destMap,
      }
    end
  end
  return list
end

local function collectConnections(map)
  local list = {}
  local conns = (map.def and map.def.connections) or {}
  for dir, c in pairs(conns) do
    if type(c) == "table" and c.map then
      list[#list + 1] = { dir = dir, map = c.map, offset = c.offset or 0 }
    end
  end
  return list
end

-- Build a tiny Image of the map's walkability. Subsamples so the longest
-- side is at most `side` pixels. One ImageData allocation, then Image;
-- ImageData is discarded so only the GPU texture (or LOVE Image) remains.
local GRID_MAX = 96

local function buildGrid(map, side)
  local mw = map.widthCells or (map.def and map.def.width and map.def.width * 2) or 0
  local mh = map.heightCells or (map.def and map.def.height and map.def.height * 2) or 0
  if mw < 1 or mh < 1 then return nil, 0, 0 end
  side = math.min(side, GRID_MAX)
  local scale = math.max(mw, mh) / side
  if scale < 1 then scale = 1 end
  local gw = math.max(1, math.floor(mw / scale + 0.5))
  local gh = math.max(1, math.floor(mh / scale + 0.5))
  if gw > GRID_MAX then gw = GRID_MAX end
  if gh > GRID_MAX then gh = GRID_MAX end

  local ok, imgData = pcall(love.image.newImageData, gw, gh)
  if not ok or not imgData then return nil, 0, 0 end

  for gy = 0, gh - 1 do
    for gx = 0, gw - 1 do
      local cx = math.floor(gx * scale)
      local cy = math.floor(gy * scale)
      if cx >= mw then cx = mw - 1 end
      if cy >= mh then cy = mh - 1 end
      local r, g, b, a = COL.block[1], COL.block[2], COL.block[3], 1
      local inb = true
      if map.inBounds then
        local okB, yes = pcall(map.inBounds, map, cx, cy)
        inb = okB and yes
      end
      if not inb then
        r, g, b, a = COL.paper[1], COL.paper[2], COL.paper[3], 0.4
      else
        local water = false
        if map.isWaterCell then
          local okW, yes = pcall(map.isWaterCell, map, cx, cy)
          water = okW and yes
        end
        if water then
          r, g, b = COL.water[1], COL.water[2], COL.water[3]
        else
          local walk = false
          if map.isWalkableCell then
            local okA, yes = pcall(map.isWalkableCell, map, cx, cy)
            walk = okA and yes
          end
          if walk then
            r, g, b = COL.walk[1], COL.walk[2], COL.walk[3]
          end
        end
      end
      imgData:setPixel(gx, gy, r, g, b, a)
    end
  end

  local okI, image = pcall(love.graphics.newImage, imgData)
  if imgData.release then pcall(imgData.release, imgData) end
  if not okI or not image then return nil, 0, 0 end
  if image.setFilter then
    pcall(image.setFilter, image, "nearest", "nearest")
  end
  return image, gw, gh
end

local function ensureCache(map, mode, res)
  if cache.mapId == map.id and cache.mode == mode and cache.res == res
     and cache.landmarks then
    return
  end
  cache.mapId = map.id
  cache.mode = mode
  cache.res = res
  cache.w = map.widthCells or 0
  cache.h = map.heightCells or 0
  cache.landmarks = collectLandmarks(map)
  cache.connections = collectConnections(map)
  releaseGrid()
  if wantGrid(res, mode) then
    local side = radarSize(res, mode) - 4
    cache.gridImage, cache.gridW, cache.gridH = buildGrid(map, side)
  end
end

-- ------- cheap ambient tint (optional, no cyclic dep)

local function paperTint()
  local paper = { COL.paper[1], COL.paper[2], COL.paper[3], COL.paper[4] }
  -- night: slightly cooler / darker paper
  local okDN, DayNight = pcall(V.require, "DayNight")
  if okDN and DayNight and DayNight.hours then
    local okH, h = pcall(DayNight.hours)
    if okH and type(h) == "number" then
      if h < 5 or h >= 20 then
        paper[1] = paper[1] * 0.72
        paper[2] = paper[2] * 0.74
        paper[3] = paper[3] * 0.88
      elseif h < 7 or h >= 18 then
        paper[1] = paper[1] * 0.95
        paper[2] = paper[2] * 0.90
        paper[3] = paper[3] * 0.85
      end
    end
  end
  local okW, Weather = pcall(V.require, "Weather")
  if okW and Weather and Weather.falling and Weather.falling() then
    local p = (Weather.power and Weather.power()) or 0.5
    paper[3] = paper[3] + 0.06 * p
    paper[1] = paper[1] * (1 - 0.04 * p)
  end
  return paper
end

-- Map cell → radar pixel (origin top-left of inner area).
local function cellToRadar(cx, cy, mw, mh, inner)
  if mw < 1 then mw = 1 end
  if mh < 1 then mh = 1 end
  local x = (cx + 0.5) / mw * inner
  local y = (cy + 0.5) / mh * inner
  return x, y
end

local function facingDelta(facing)
  if facing == "up" or facing == "UP" then return 0, -1 end
  if facing == "down" or facing == "DOWN" then return 0, 1 end
  if facing == "left" or facing == "LEFT" then return -1, 0 end
  if facing == "right" or facing == "RIGHT" then return 1, 0 end
  return 0, 1
end

local function drawIcon(g, kind, x, y, s)
  local c = landmarkColor(kind)
  g.setColor(c[1], c[2], c[3], 1)
  if kind == "center" then
    -- white cross on a small red plate
    g.setColor(0.85, 0.15, 0.15, 1)
    g.rectangle("fill", x - s, y - s, s * 2, s * 2)
    g.setColor(1, 1, 1, 1)
    g.rectangle("fill", x - s * 0.25, y - s * 0.85, s * 0.5, s * 1.7)
    g.rectangle("fill", x - s * 0.85, y - s * 0.25, s * 1.7, s * 0.5)
  elseif kind == "gym" then
    g.rectangle("fill", x - s * 0.9, y - s * 0.9, s * 1.8, s * 1.8)
    g.setColor(COL.ink[1], COL.ink[2], COL.ink[3], 1)
    g.rectangle("line", x - s * 0.9, y - s * 0.9, s * 1.8, s * 1.8)
  elseif kind == "gate" then
    g.rectangle("fill", x - s, y - s * 0.6, s * 2, s * 1.2)
  else -- mart / default
    g.rectangle("fill", x - s * 0.7, y - s * 0.7, s * 1.4, s * 1.4)
  end
end

local function drawConnArrow(g, dir, ox, oy, size, pad)
  local cx, cy = ox + size * 0.5, oy + size * 0.5
  local s = math.max(3, size * 0.08)
  g.setColor(COL.route[1], COL.route[2], COL.route[3], 1)
  if dir == "north" or dir == "up" then
    g.polygon("fill", cx, oy + pad, cx - s, oy + pad + s * 1.6,
              cx + s, oy + pad + s * 1.6)
  elseif dir == "south" or dir == "down" then
    g.polygon("fill", cx, oy + size - pad, cx - s, oy + size - pad - s * 1.6,
              cx + s, oy + size - pad - s * 1.6)
  elseif dir == "west" or dir == "left" then
    g.polygon("fill", ox + pad, cy, ox + pad + s * 1.6, cy - s,
              ox + pad + s * 1.6, cy + s)
  elseif dir == "east" or dir == "right" then
    g.polygon("fill", ox + size - pad, cy, ox + size - pad - s * 1.6, cy - s,
              ox + size - pad - s * 1.6, cy + s)
  end
end

-- ------- public draw (into the finished world canvas, screen pixels)

function MiniMap.present(canvas)
  if not MiniMap.enabled() then
    cache.last = { drawn = false, reason = "off" }
    return canvas
  end
  if not canvas then
    cache.last = { drawn = false, reason = "no-canvas" }
    return canvas
  end

  local Game = game()
  local ow = Game and Game.overworld
  if not (ow and ow.map and ow.player) then
    cache.last = { drawn = false, reason = "no-overworld" }
    return canvas
  end
  -- Stand down during warps / non-free-roam: same gate Weather uses.
  if ow.transitioning then
    cache.last = { drawn = false, reason = "transitioning" }
    return canvas
  end
  if Game.stack and Game.stack:top() and Game.stack:top() ~= ow then
    cache.last = { drawn = false, reason = "not-free-roam" }
    return canvas
  end

  local map, p = ow.map, ow.player
  local mode = MiniMap.mode()
  local res = Quality.scale()
  ensureCache(map, mode, res)

  local size = radarSize(res, mode)
  local pad = 2
  local inner = size - pad * 2
  local cw = canvas.getWidth and canvas:getWidth() or 0
  local ch = canvas.getHeight and canvas:getHeight() or 0
  if cw < 1 or ch < 1 then
    cache.last = { drawn = false, reason = "bad-canvas" }
    return canvas
  end

  -- Bottom-right corner, with a small margin so it does not kiss the edge.
  local margin = math.max(6, math.floor(math.min(cw, ch) * 0.02))
  local ox = cw - size - margin
  local oy = ch - size - margin

  local mw = cache.w > 0 and cache.w or 1
  local mh = cache.h > 0 and cache.h or 1
  local px, py = cellToRadar(p.cellX or 0, p.cellY or 0, mw, mh, inner)
  cache.cellX, cache.cellY = p.cellX, p.cellY
  cache.facing = p.facing

  local g = love.graphics
  local prevCanvas = g.getCanvas and g.getCanvas() or nil
  local okBind = pcall(g.setCanvas, canvas)
  if not okBind then
    cache.last = { drawn = false, reason = "bind-fail" }
    return canvas
  end

  local prevBlend, prevAlpha = g.getBlendMode()
  g.setBlendMode("alpha")
  g.setShader()
  g.setDepthMode()

  local paper = paperTint()
  -- Drop shadow (1 px)
  g.setColor(0, 0, 0, 0.35)
  g.rectangle("fill", ox + 2, oy + 2, size, size)
  -- Paper plate
  g.setColor(paper[1], paper[2], paper[3], paper[4])
  g.rectangle("fill", ox, oy, size, size)
  -- Ink border
  g.setColor(COL.edge[1], COL.edge[2], COL.edge[3], 1)
  g.setLineWidth(2)
  g.rectangle("line", ox + 0.5, oy + 0.5, size - 1, size - 1)

  -- FULL grid (nearest-neighbour stretch into the inner square)
  if cache.gridImage and wantGrid(res, mode) then
    g.setColor(1, 1, 1, 1)
    g.draw(cache.gridImage, ox + pad, oy + pad, 0,
           inner / cache.gridW, inner / cache.gridH)
  end

  -- Connection arrows (always when we have any; cheap polygons)
  if res <= 2 then
    for _, c in ipairs(cache.connections) do
      drawConnArrow(g, c.dir, ox, oy, size, pad + 1)
    end
  end

  -- Landmark icons (skip on lowest RES)
  if res <= 2 then
    local iconS = math.max(1.5, size / 28)
    for _, lm in ipairs(cache.landmarks) do
      local lx, ly = cellToRadar(lm.cx, lm.cy, mw, mh, inner)
      drawIcon(g, lm.kind, ox + pad + lx, oy + pad + ly, iconS)
    end
  end

  -- Player pulse + facing arrow
  local now = (love.timer and love.timer.getTime()) or 0
  local pulse = 0.65 + 0.35 * math.sin(now * 5.5)
  local pr = math.max(2, size / 22) * (0.85 + 0.15 * pulse)
  local pxx, pyy = ox + pad + px, oy + pad + py
  g.setColor(COL.player[1], COL.player[2], COL.player[3], 0.35 * pulse)
  g.circle("fill", pxx, pyy, pr * 1.8)
  g.setColor(COL.player[1], COL.player[2], COL.player[3], 1)
  g.circle("fill", pxx, pyy, pr)
  g.setColor(1, 1, 1, 0.9)
  g.circle("fill", pxx, pyy, pr * 0.35)

  local fdx, fdy = facingDelta(p.facing)
  local tip = pr * 2.4
  g.setColor(COL.ink[1], COL.ink[2], COL.ink[3], 1)
  g.polygon("fill",
    pxx + fdx * tip, pyy + fdy * tip,
    pxx + fdy * pr * 0.7 - fdx * pr * 0.2,
    pyy - fdx * pr * 0.7 - fdy * pr * 0.2,
    pxx - fdy * pr * 0.7 - fdx * pr * 0.2,
    pyy + fdx * pr * 0.7 - fdy * pr * 0.2)

  g.setLineWidth(1)
  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  if prevCanvas then pcall(g.setCanvas, prevCanvas) else pcall(g.setCanvas) end

  cache.last = {
    drawn = true,
    mode = mode,
    res = res,
    mapId = map.id,
    cellX = p.cellX,
    cellY = p.cellY,
    facing = p.facing,
    size = size,
    ox = ox, oy = oy,
    -- player position inside the radar, in [0,1] of the map
    u = (p.cellX + 0.5) / mw,
    v = (p.cellY + 0.5) / mh,
    radarPx = px, radarPy = py,
    mw = mw, mh = mh,
    landmarks = cache.landmarks,
    nLandmarks = #cache.landmarks,
    nConnections = #cache.connections,
    hasGrid = cache.gridImage ~= nil,
    gridW = cache.gridW, gridH = cache.gridH,
  }
  return canvas
end

-- Probe / diagnostics: last frame's draw report + live engine coords.
function MiniMap.report()
  local Game = game()
  local ow = Game and Game.overworld
  local p = ow and ow.player
  local map = ow and ow.map
  local r = cache.last or { drawn = false }
  return {
    mode = MiniMap.mode(),
    enabled = MiniMap.enabled(),
    drawn = r.drawn,
    reason = r.reason,
    mapId = map and map.id or r.mapId,
    engineCellX = p and p.cellX,
    engineCellY = p and p.cellY,
    engineFacing = p and p.facing,
    reportCellX = r.cellX,
    reportCellY = r.cellY,
    cellMatch = r.drawn and p
      and r.cellX == p.cellX and r.cellY == p.cellY or false,
    u = r.u, v = r.v,
    size = r.size,
    nLandmarks = r.nLandmarks or #cache.landmarks,
    landmarks = cache.landmarks,
    nConnections = r.nConnections or #cache.connections,
    hasGrid = r.hasGrid,
    gridW = r.gridW, gridH = r.gridH,
    res = r.res or Quality.scale(),
    mapW = cache.w, mapH = cache.h,
  }
end

-- Force a mode without touching persistence (probe palindrome).
function MiniMap.forceMode(mode)
  if mode == "on" or mode == "full" or mode == "off" then
    MiniMap.setting:sync(mode)
    if mode == "off" then MiniMap.invalidate() end
  end
end

return MiniMap
