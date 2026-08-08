-- Sprite-sheet effects in the overlay pass: the hand-drawn half of the
-- anime look.
--
-- The ANIME row (lib/Anime.lua) does the part a shader can do -- light in
-- flat steps, a rim, a line. It cannot draw an impact. An impact in an
-- animated frame is ART: somebody drew thirty pictures of an explosion and
-- the frame shows them one after another. So this file plays sprite sheets,
-- and the sheets are CC0 packs off OpenGameArt rather than anything
-- generated here (see assets/vfx/LICENSE.md).
--
-- ------- where it draws, and why there
--
-- The OVERLAY pass, beside the butterflies and the rain -- not the 3D pass.
-- GroundFX's header draws the distinction this file is on the other side
-- of: a puddle belongs UNDER the person standing in it and therefore has to
-- be decal geometry, while a butterfly IS in front of the world and belongs
-- in the overlay. An impact flash is the second kind. It is not lit by the
-- hour, it does not take the sun's shadow, and nothing in the world stands
-- in front of it -- it is drawn ON the picture, which is exactly what the
-- overlay is.
--
-- Anchored through Voxel3D.project like everything else there, so an effect
-- played at a world cell stays on that cell as the camera orbits, and it
-- scales with the camera rung instead of sitting at a fixed pixel size.
--
-- ------- ADDITIVE, and that is not a detail
--
-- These sheets are drawn as light: bright cores on black, with the black
-- meant to disappear. Alpha-blended they carry a grey box around every
-- flash. Added, the black contributes nothing and the core blows out --
-- which is what an impact frame does in an animated cel, and it is also the
-- one place this mod deliberately leaves the Game Boy's palette behind.
--
-- ------- what it costs, which is nearly nothing until it plays
--
-- Sheets are loaded ON FIRST USE and then kept (ImageCache's own reasoning:
-- a handful of small images for a whole session). Nothing is loaded at all
-- if the row is OFF or if no effect ever fires, so a player who never turns
-- this on pays a table and a require.
--
-- A playing effect is one quad. The frame is picked by arithmetic on a
-- Quad's viewport -- no per-frame texture, no canvas, no shader. The cap
-- below is a draw-call budget in the same spirit as Quality.starCount, and
-- for the same machine.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local Quality = V.require("Quality")

local Vfx = {}

Vfx.setting = ModSetting.new("vfx", "IMPACT",
                             { "off", "on" },
                             { "OFF", "ON" })

-- How many effects may be alive at once. Past this the oldest is dropped
-- rather than the newest refused: the newest is the one the player just
-- caused, and dropping it is the one failure they would actually notice.
Vfx.MAX_LIVE = 8

-- World pixels an effect spans at scale 1, before its own per-play scale.
-- A mon in this world is about 16 world pixels tall, so the default reads
-- as an effect half again its subject's height.
Vfx.SIZE = 24

-- How far off the ground the effect's CENTRE sits, in world pixels. Zero
-- would bury the bottom half of every flash in the floor.
Vfx.LIFT = 8

local defs                 -- key -> definition, from data/vfx.lua
local images = {}          -- key -> Image (or false: tried and failed)
local quads = {}           -- key -> reusable Quad
local live = {}            -- the playing effects

local function definitions()
  if defs then return defs end
  defs = {}
  local ok, list = pcall(V.data, "vfx")
  if ok and type(list) == "table" then
    for _, d in ipairs(list) do
      if d.key then defs[d.key] = d end
    end
  end
  return defs
end

-- Every effect this build carries, in a stable order -- for the probe and
-- for the demo key, which walks it.
function Vfx.keys()
  local out = {}
  for k in pairs(definitions()) do out[#out + 1] = k end
  table.sort(out)
  return out
end

function Vfx.level()
  local ok, v = pcall(Vfx.setting.get, Vfx.setting)
  if ok and (v == "off" or v == "on") then return v end
  return "off"
end

function Vfx.enabled()
  return Vfx.level() == "on"
end

function Vfx.row()
  return Vfx.setting:row()
end

-- Loaded on first use and remembered, including the FAILURE: a sheet that
-- will not decode on this driver must not be retried once per frame for the
-- rest of the session. `false` is the memo for "asked, and the answer was
-- no" -- the same shape TerrainAtlas uses for an atlas it gave up on.
local function sheet(key)
  local held = images[key]
  if held ~= nil then return held or nil end
  local d = definitions()[key]
  if not d then images[key] = false return nil end
  local path = (V.path or "") .. "/assets/vfx/" .. d.file
  local ok, img = pcall(love.graphics.newImage, path)
  if not ok or not img then
    -- Read through the mod's own reader as a second try: a mod living
    -- inside a mounted .love archive is not on love's filesystem the way a
    -- loose folder is.
    local ok2, data = pcall(function()
      return V.mod:read("assets/vfx/" .. d.file)
    end)
    if ok2 and data then
      local ok3, fd = pcall(love.filesystem.newFileData, data, d.file)
      if ok3 then
        local ok4, img2 = pcall(love.graphics.newImage, fd)
        if ok4 then img = img2 else img = nil end
      end
    end
  end
  if not img then
    Vfx.loadError = "could not load assets/vfx/" .. tostring(d.file)
    images[key] = false
    return nil
  end
  -- Nearest, not linear. These were resampled down to a frame the diorama
  -- actually draws at, and the world they land in is a pixel grid -- a
  -- linear filter would leave a soft flash over a hard world.
  pcall(img.setFilter, img, "nearest", "nearest")
  images[key] = img
  quads[key] = love.graphics.newQuad(0, 0, d.frameW, d.frameH,
                                     img:getWidth(), img:getHeight())
  return img
end

-- ------- the public seam
--
-- Anything that wants an effect calls this. Deliberately the whole API:
-- a caller says WHAT, WHERE and optionally how big -- it does not get to
-- reach into the list, and nothing here needs to know why it was asked.
--
--   Vfx.play("bighit", wx, wy, wz, { size = 32, scale = 1.2 })
--
-- Silent and harmless on every failure -- row off, unknown key, no sheet.
-- An effect that cannot draw must never be the reason a frame is lost.
function Vfx.play(key, wx, wy, wz, opts)
  if not Vfx.enabled() then return false end
  local d = definitions()[key]
  if not d then return false end
  opts = opts or {}
  if #live >= Vfx.MAX_LIVE then table.remove(live, 1) end
  live[#live + 1] = {
    key = key,
    x = wx or 0,
    y = (wy or 0) + (opts.lift or Vfx.LIFT),
    z = wz or 0,
    t = 0,
    size = opts.size or Vfx.SIZE,
    mul = opts.scale or 1,
    -- Frames are held for a whole number of source frames at the pack's own
    -- rate, so the animation runs at the speed it was drawn at whatever the
    -- game is doing.
    dur = d.frames / math.max(d.fps or 30, 1),
  }
  return true
end

function Vfx.clear()
  live = {}
end

function Vfx.liveCount()
  return #live
end

-- Advanced on real seconds rather than on frames: an effect drawn at 20 fps
-- and one drawn at 60 have to last the same wall time, or the whole thing
-- speeds up on a better machine.
function Vfx.update(dt)
  if #live == 0 then return end
  dt = dt or 0
  local i = 1
  while i <= #live do
    local e = live[i]
    e.t = e.t + dt
    if e.t >= e.dur then table.remove(live, i) else i = i + 1 end
  end
end

-- `project` is Voxel3D.project (wx, wy, wz) -> screen x, y -- the same
-- camera every other overlay drawing is anchored through, which is what
-- keeps an effect on its cell while the camera orbits.
function Vfx.draw(project, scale)
  if not Vfx.enabled() or #live == 0 then return end
  if not (project and love and love.graphics) then return end
  local g = love.graphics
  scale = scale or 1

  -- The same rung everything else in this mod hangs its budget on. At the
  -- cheapest render scale the frame is a fraction of the pixels and an
  -- effect is a smear, so fewer of them are drawn at once -- the oldest go
  -- first, exactly as they do at the cap.
  local budget = Vfx.MAX_LIVE
  local q = Quality.scale()
  if q >= 4 then budget = 2 elseif q == 3 then budget = 4 end
  local first = math.max(1, #live - budget + 1)

  local r, gg, b, a = g.getColor()
  local blend, alphaMode = g.getBlendMode()
  -- See the header: these sheets are light on black, and added is the mode
  -- that makes the black vanish. pcall because a driver without a separate
  -- alpha mode takes the two-argument form and nothing else.
  pcall(g.setBlendMode, "add", "alphamultiply")

  for i = first, #live do
    local e = live[i]
    local img = sheet(e.key)
    local d = definitions()[e.key]
    if img and d and quads[e.key] then
      local sx, sy = project(e.x, e.y, e.z)
      if sx and sy then
        -- Which cell of the grid. Clamped rather than wrapped: a rounding
        -- error at the very last frame must end the animation, not restart
        -- it for one frame.
        local n = math.floor(e.t * (d.fps or 30))
        if n < 0 then n = 0 end
        if n > d.frames - 1 then n = d.frames - 1 end
        local col = n % d.cols
        local row = math.floor(n / d.cols)
        quads[e.key]:setViewport(col * d.frameW, row * d.frameH,
                                 d.frameW, d.frameH)

        -- One number turns world pixels into screen pixels here: the same
        -- `scale` the rest of the overlay draws in, times the effect's own
        -- size against the sheet's frame. Anchored at the frame's CENTRE so
        -- a flash is centred on the cell it was played at rather than
        -- hanging down and right of it.
        local px = (e.size * e.mul * scale) / math.max(d.frameW, d.frameH)

        -- Fade out over the last third. The packs end on a dissipating
        -- frame already, but they end on it abruptly; a tail on the alpha
        -- is what stops an impact from being switched off mid-air.
        local k = e.t / math.max(e.dur, 0.0001)
        local fade = k > 0.66 and (1 - (k - 0.66) / 0.34) or 1
        if fade < 0 then fade = 0 end

        g.setColor(1, 1, 1, fade)
        pcall(g.draw, img, quads[e.key], sx, sy, 0, px, px,
              d.frameW * 0.5, d.frameH * 0.5)
      end
    end
  end

  pcall(g.setBlendMode, blend, alphaMode)
  g.setColor(r, gg, b, a)
end

return Vfx
