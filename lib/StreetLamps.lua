-- Street lamps for the towns at night.
--
-- The DAYTIME row already lights WINDOWS (DayNight.windowLight + the glass
-- path in Voxel3D).  What a dark night still lacks is something on the
-- STREET itself -- Gen 1 towns are empty of lamps, and a DEEP night with
-- nothing between the windows is a town with no middle.  This file plants
-- posts on outdoor maps that are not routes (the same "is a town" test
-- CityLife uses), three hand-built models of them, and draws the heads
-- full-bright in lamp colour after dark so they read as lit rather than as
-- dim props under the hour's tint.
--
-- Placement is deterministic off the map id and cell, so the same lamp
-- stands on the same corner every load.  Nothing is written to the save.
-- The LAMPS row turns the whole feature off; N-DARK on DayNight decides how
-- much darkness the lamps are answering.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local Voxel3D = V.require("Voxel3D")
local Mat4 = V.require("Mat4")
local DayNight = V.require("DayNight")

local Map = require("src.world.Map")

local StreetLamps = {}

local function game()
  return require("src.core.Game")
end

StreetLamps.setting = ModSetting.new("lamps", "LAMPS",
                                     { true, false },
                                     { "ON", "OFF" })

function StreetLamps.enabled()
  local ok, v = pcall(StreetLamps.setting.get, StreetLamps.setting)
  return ok and v == true
end

-- How far apart two posts may stand, in cells.  Closer and a town is a
-- forest of poles; further and a block has none.
StreetLamps.SPACING = 6

-- Max posts per map.  A full Kanto city has room for more, but each is a
-- mesh draw and a shadow caster, and a phone-shaped view does not want
-- fifty of them.
StreetLamps.MAX = 28

-- ------- is this a town
--
-- Outdoor map with no grass encounter table.  Same rule CityLife uses, so
-- a route keeps its wild grass and gets no posts, and Viridian Forest
-- (canopy) is not a street.
local function isTown(map)
  if not (map and map.def and Map.isOutdoor(map.def)) then return false end
  if DayNight.isCanopy(map) then return false end
  local Game = game()
  local encDef = Game and Game.data and Game.data.encounters
                 and Game.data.encounters[map.id]
  if encDef and encDef.grass and (encDef.grass.rate or 0) > 0 then
    return false
  end
  return true
end

local function hasSolidNeighbor(map, cx, cy)
  for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
    local nx, ny = cx + d[1], cy + d[2]
    if map:inBounds(nx, ny)
       and not map:isWalkableCell(nx, ny)
       and not map:isWaterCell(nx, ny) then
      return true
    end
  end
  return false
end

-- Stable 0..1 from map id + cell, no love.math so a probe and a play agree.
local function cellHash(mapId, cx, cy)
  local s = tostring(mapId or "") .. ":" .. cx .. "," .. cy
  local h = 2166136261
  for i = 1, #s do
    h = (h * 16777619 + s:byte(i)) % 2147483647
  end
  return (h % 10007) / 10007
end

-- ------- the three models
--
-- Built once as local-space meshes (feet on y = 0, centred on xz).  Style
-- names are the only thing a site remembers; the mesh is shared.
--
--   classic  thin pole, single lantern box on top
--   twin     same pole, two lanterns side by side (main streets)
--   globe    thicker pole, taller lantern (plazas / gym roads)

local templates = nil          -- { classic={pole,head}, ... }
local lampTex = nil            -- 2x1: metal | warm glass

local function ensureTex()
  if lampTex then return lampTex end
  if not (love and love.image and love.graphics) then return nil end
  local ok, data = pcall(love.image.newImageData, 2, 1)
  if not ok or not data then return nil end
  -- u≈0: dark metal pole.  u≈1: warm lantern glass (daytime look; at night
  -- the head is flattened to lampColor and this texel barely matters).
  pcall(data.setPixel, data, 0, 0, 0.28, 0.26, 0.24, 1)
  pcall(data.setPixel, data, 1, 0, 0.95, 0.78, 0.40, 1)
  local okI, img = pcall(love.graphics.newImage, data)
  if not okI or not img then return nil end
  pcall(img.setFilter, img, "nearest", "nearest")
  lampTex = img
  return lampTex
end

-- One axis-aligned box as six quads.  u selects the atlas column (0 metal,
-- 1 lamp).  shade is the face shade the scene multiplies by.
local function addBox(verts, indices, x0, y0, z0, x1, y1, z1, u, shade)
  local faces = {
    -- +X -X +Y -Y +Z -Z
    { { x1, y0, z0 }, { x1, y0, z1 }, { x1, y1, z1 }, { x1, y1, z0 }, 0.85 },
    { { x0, y0, z1 }, { x0, y0, z0 }, { x0, y1, z0 }, { x0, y1, z1 }, 0.70 },
    { { x0, y1, z0 }, { x1, y1, z0 }, { x1, y1, z1 }, { x0, y1, z1 }, 1.00 },
    { { x0, y0, z1 }, { x1, y0, z1 }, { x1, y0, z0 }, { x0, y0, z0 }, 0.55 },
    { { x0, y0, z1 }, { x1, y0, z1 }, { x1, y1, z1 }, { x0, y1, z1 }, 0.90 },
    { { x1, y0, z0 }, { x0, y0, z0 }, { x0, y1, z0 }, { x1, y1, z0 }, 0.75 },
  }
  local v = u or 0
  for _, f in ipairs(faces) do
    local base = #verts
    local s = shade * f[5]
    for i = 1, 4 do
      local c = f[i]
      verts[#verts + 1] = { c[1], c[2], c[3], v, 0.5, s }
    end
    Voxel3D.pushQuad(indices, base / 4)
  end
end

local function bakePart(boxes)
  local verts, indices = {}, {}
  for _, b in ipairs(boxes) do
    addBox(verts, indices, b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8])
  end
  return Voxel3D.newMesh(verts, indices)
end

local function buildTemplates()
  if templates then return templates end
  -- classic: 2x2 pole to y=18, 5x5x4 lantern on top
  local classicPole = bakePart({
    { -1, 0, -1, 1, 18, 1, 0, 0.9 },
    { -1.5, 0, -1.5, 1.5, 1.5, 1.5, 0, 0.75 },   -- base plinth
  })
  local classicHead = bakePart({
    { -2.5, 17, -2.5, 2.5, 21, 2.5, 1, 1.0 },
    { -1.5, 21, -1.5, 1.5, 22.5, 1.5, 0, 0.85 }, -- cap
  })
  -- twin: same pole, two lanterns
  local twinPole = bakePart({
    { -1, 0, -1, 1, 17, 1, 0, 0.9 },
    { -1.5, 0, -1.5, 1.5, 1.5, 1.5, 0, 0.75 },
    { -5, 16, -1, 5, 17.5, 1, 0, 0.8 },           -- crossbar
  })
  local twinHead = bakePart({
    { -6.5, 15.5, -2, -3.5, 19.5, 2, 1, 1.0 },
    { 3.5, 15.5, -2, 6.5, 19.5, 2, 1, 1.0 },
  })
  -- globe: thicker shaft, chunky lantern
  local globePole = bakePart({
    { -1.5, 0, -1.5, 1.5, 16, 1.5, 0, 0.9 },
    { -2, 0, -2, 2, 2, 2, 0, 0.75 },
  })
  local globeHead = bakePart({
    { -3, 15, -3, 3, 21, 3, 1, 1.0 },
    { -2, 21, -2, 2, 22.5, 2, 0, 0.85 },
  })
  templates = {
    classic = { pole = classicPole, head = classicHead },
    twin = { pole = twinPole, head = twinHead },
    globe = { pole = globePole, head = globeHead },
  }
  return templates
end

local STYLES = { "classic", "twin", "globe" }

-- ------- per-map site cache
--
-- key -> { {cx, cy, style, wx, wz}, ... }
local cache = {}

local function sitesFor(map)
  if not map or not map.id then return {} end
  local hit = cache[map.id]
  if hit then return hit end
  if not isTown(map) then
    cache[map.id] = {}
    return cache[map.id]
  end

  -- Map cells use widthCells/heightCells (not .width/.height — those are nil
  -- on this engine's Map).
  local w = map.widthCells or map.width or 0
  local h = map.heightCells or map.height or 0
  local candidates = {}
  for cy = 2, h - 3 do
    for cx = 2, w - 3 do
      if map:isWalkableCell(cx, cy)
         and not map:isWaterCell(cx, cy)
         and not map:warpAtCell(cx, cy)
         and not (map.isGrassCell and map:isGrassCell(cx, cy)) then
        local r = cellHash(map.id, cx, cy)
        local sidewalk = hasSolidNeighbor(map, cx, cy)
        -- Sidewalk cells preferred (r < 0.55); open plaza cells rarer
        -- (r < 0.12) so a big square still gets a few posts.
        if (sidewalk and r < 0.55) or ((not sidewalk) and r < 0.12) then
          candidates[#candidates + 1] = {
            cx = cx, cy = cy, r = r, sidewalk = sidewalk,
            wx = cx * 16 + 8, wz = cy * 16 + 8,
          }
        end
      end
    end
  end
  -- sidewalks first so plazas fill the gaps rather than taking the budget
  table.sort(candidates, function(a, b)
    if a.sidewalk ~= b.sidewalk then return a.sidewalk end
    return a.r < b.r
  end)

  local placed, sites = {}, {}
  local gap = StreetLamps.SPACING
  for _, c in ipairs(candidates) do
    if #sites >= StreetLamps.MAX then break end
    local ok = true
    for _, p in ipairs(placed) do
      if math.abs(p.cx - c.cx) < gap and math.abs(p.cy - c.cy) < gap then
        ok = false; break
      end
    end
    if ok then
      local style = STYLES[1 + math.floor(c.r * #STYLES) % #STYLES]
      sites[#sites + 1] = {
        cx = c.cx, cy = c.cy, wx = c.wx, wz = c.wz, style = style,
      }
      placed[#placed + 1] = c
    end
  end
  cache[map.id] = sites
  return sites
end

function StreetLamps.invalidate()
  cache = {}
  templates = nil
  lampTex = nil
end

-- ------- draw
--
-- Pole under the hour's light (casts a real shadow when the sun pass runs).
-- Head: after dusk, flattened to DayNight.lampColor so DEEP night does not
-- snuff it out.  Daytime heads keep their warm texel under the ordinary
-- tint and read as unlit glass.

function StreetLamps.draw(map, outdoor)
  if not StreetLamps.enabled() then return end
  if not outdoor then return end
  if not Voxel3D.available() then return end
  local sites = sitesFor(map)
  if #sites == 0 then return end
  local tpl = buildTemplates()
  local tex = ensureTex()
  if not tpl or not tex then return end

  local lit = 0
  if outdoor then
    local ok, n = pcall(DayNight.windowLight)
    if ok and n then lit = n end
  end
  local lampColor = DayNight.lampColor()

  -- poles first (receive shade, cast via sun path if included — see cast)
  for _, s in ipairs(sites) do
    local t = tpl[s.style] or tpl.classic
    if t and t.pole then
      local m = Mat4.translate(s.wx, 0, s.wz)
      Voxel3D.draw(t.pole, tex, m, 0, m)
    end
  end

  -- heads: glow when the hour has lamps on
  if lit > 0.05 then
    -- amount climbs with the hour so dusk is a half-glow and midnight is full
    local amount = 0.40 + 0.60 * lit
    Voxel3D.flatten(lampColor, amount)
  end
  for _, s in ipairs(sites) do
    local t = tpl[s.style] or tpl.classic
    if t and t.head then
      local m = Mat4.translate(s.wx, 0, s.wz)
      Voxel3D.draw(t.head, tex, m, 0, m)
    end
  end
  if lit > 0.05 then
    Voxel3D.flatten(nil)
  end
end

-- Shadow casters for the sun pass: poles only (heads are small and would
-- speck the ground).  Same snug transform convention as figures.
function StreetLamps.castShadows(map)
  if not StreetLamps.enabled() then return end
  if not Voxel3D.available() then return end
  local sites = sitesFor(map)
  if #sites == 0 then return end
  local tpl = buildTemplates()
  local tex = ensureTex()
  if not (tpl and tex) then return end
  local ShadowMap = V.require("ShadowMap")
  for _, s in ipairs(sites) do
    local t = tpl[s.style] or tpl.classic
    if t and t.pole then
      local m = Mat4.translate(s.wx, 0, s.wz)
      pcall(ShadowMap.draw, t.pole, tex, ShadowMap.snug(m))
    end
  end
end

-- For probes / debug: how many posts a map would get.
function StreetLamps.count(map)
  return #sitesFor(map)
end

return StreetLamps
