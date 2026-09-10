-- One place where every render target in this mod is made, and one reason
-- for it.
--
-- ------- love.graphics.newCanvas(w, h) DOES NOT MAKE A w-BY-h TEXTURE
--
-- It makes a canvas whose *unit* size is w by h and whose *pixel* size is
-- `w * dpiscale` by `h * dpiscale`, where dpiscale defaults to
-- `love.graphics.getDPIScale()`.  On a desktop that is 1 and the two are the
-- same number, which is why this was invisible for the whole life of the mod.
-- On Android it is the display density: 2.625 on the 420dpi panel this was
-- first measured against, and 2.625 again on the Poco X7 (Mali-G615 MC2,
-- 2712x1220) that reported the VOXEL row running at about one frame a second.
--
-- 2.625 squared is 6.9.  So every render target in the 3D path was SEVEN
-- TIMES the pixels the code believed it had asked for:
--
--   the scene canvas   RES 1/2 of 2712x1220 = 1356x610 = 0.83 Mpx intended,
--                      3560x1601 = 5.70 Mpx allocated
--   the present canvas 2712x1220 = 3.31 Mpx intended,
--                      7119x3202 = 22.79 Mpx allocated -- a render target
--                      seven times the area of the screen it is shown on,
--                      91 MB of it, blitted every frame
--   the depth buffer   the same 5.70 Mpx, and it is a READABLE depth canvas,
--                      so a tile-based GPU writes all of it out to memory
--   the shadow map     the LOW rung asks for 512x512 and gets 1344x1344
--   and the same again for RayFX, TiltShift, Bloom, Weather and the DOF pair
--
-- That is the whole shape of the phone report.  RES could not rescue it,
-- because RES divides a number that is then multiplied back by 2.625 twice;
-- turning rows off could not rescue it, because the cost is in the targets
-- and not in what is drawn into them.
--
-- ------- WHY dpiscale = 1 IS THE FIX AND NOT A COMPROMISE
--
-- The size the render path asks for is ALREADY in framebuffer pixels: see
-- `sceneSize` in main.lua, which deliberately reads
-- love.graphics.getPixelDimensions() rather than the context's unit size,
-- because the engine composites the returned canvas at 1/dpi and that only
-- covers the window when the canvas carries the panel's pixel count.
--
-- So `dpiscale = 1` changes nothing about the canvas's UNIT size -- the
-- composite, the projection, the FX closures and every uv in every shader
-- see exactly the numbers they saw before.  It changes only the pixel count
-- behind them, from 6.9x what was asked for to what was asked for.  On
-- desktop it is a no-op by definition (dpiscale is already 1).
--
-- ------- AND WHY IT IS A MODULE INSTEAD OF A SETTINGS TABLE
--
-- Because the defect is silent, symmetrical and easy to reintroduce: a new
-- pass adds `love.graphics.newCanvas(w, h)`, it looks exactly like the
-- fifteen calls around it, it is right on every machine in the room and
-- seven times too big on every phone.  Four files in this mod (BattleFanXY,
-- BattlePanelsXY, BattleRibbon, MonPack) had already learned this
-- separately and pass `{ dpiscale = 1 }` by hand; the render path never did.
-- Routing every allocation through one function makes the rule structural,
-- and `RenderTarget.dpi` gives the probes a way to REPRODUCE the phone's
-- allocation on a desktop (tests/dpi_canvas_probe.lua) instead of taking
-- this note on faith.

local RenderTarget = {}

-- What every canvas this module makes is scaled by.  1 is the answer for
-- every device; the probes set it to 2.625 to reproduce the Android
-- allocation on a machine whose own dpiscale is 1.
RenderTarget.dpi = 1

-- Total pixels currently held in canvases made through here, so a probe (or
-- a future budget) can ask what the frame is costing in memory rather than
-- inferring it.  Keyed by the canvas itself; a released canvas is dropped by
-- the caller through `RenderTarget.release`.
RenderTarget.pixels = 0
local held = setmetatable({}, { __mode = "k" })

local function account(c)
  if not c then return end
  local ok, w, h = pcall(c.getPixelDimensions, c)
  if not ok then return end
  held[c] = w * h
  RenderTarget.pixels = RenderTarget.pixels + w * h
end

-- Give a canvas back.  Safe with nil and safe with a canvas this module did
-- not make, because both are things the call sites already do.
function RenderTarget.release(c)
  if not c then return end
  local n = held[c]
  if n then
    RenderTarget.pixels = RenderTarget.pixels - n
    held[c] = nil
  end
  if c.release then pcall(c.release, c) end
end

-- The settings table for a canvas of this mod's, with the caller's own
-- fields (format, readable, msaa) carried through untouched.  Returned as a
-- fresh table every call: LOVE reads it synchronously, but a shared table
-- would let one call site's `format` leak into the next one's.
function RenderTarget.settings(extra)
  local s = { dpiscale = RenderTarget.dpi }
  if extra then
    for k, v in pairs(extra) do s[k] = v end
    -- an explicit dpiscale from a caller still wins, because the probes
    -- need to be able to say so
    if extra.dpiscale then s.dpiscale = extra.dpiscale end
  end
  return s
end

-- newCanvas with this mod's rule applied.  Returns nil rather than raising,
-- which is what every call site in the mod already expects: a render target
-- that could not be allocated is a pass that does not run, never a crash.
function RenderTarget.new(w, h, extra)
  if not (love and love.graphics and love.graphics.newCanvas) then return nil end
  w = math.max(1, math.floor(w or 1))
  h = math.max(1, math.floor(h or 1))
  local ok, c = pcall(love.graphics.newCanvas, w, h, RenderTarget.settings(extra))
  if not (ok and c) then return nil end
  account(c)
  return c
end

-- The first format in `formats` the driver accepts, or nil.  Depth canvases
-- are the one place in the mod that shops around: a driver that refuses
-- depth24stencil8 may still take depth24 or depth16, and the difference
-- between the second and the third is a pass rather than a crash.
function RenderTarget.newFormat(w, h, formats, extra)
  for _, fmt in ipairs(formats) do
    local s = RenderTarget.settings(extra)
    s.format = fmt
    local c = RenderTarget.new(w, h, s)
    if c then return c, fmt end
  end
  return nil
end

return RenderTarget
