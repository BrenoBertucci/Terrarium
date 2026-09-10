-- What machine this is, asked once, from the only witness a mod is allowed.
--
-- The mod sandbox blocks `love.system` (src/mods/Sandbox.lua names it in
-- BLOCKED_LOVE) and blocks `os.getenv`, so "am I on a phone" cannot be asked
-- the obvious way.  What IS allowed is love.graphics.getRendererInfo, and it
-- happens to answer better than the OS would: what this mod needs to know is
-- not the operating system but the GPU's ARCHITECTURE, because every
-- expensive thing in the render path is expensive for tile-based reasons.
--
--   OpenGL ES + Mali / Adreno / PowerVR / Apple  =  a tiler, a shared memory
--   bus in the 10-20 GB/s range, and a fragment budget one to two orders of
--   magnitude under the desktop this mod was written on.
--
-- The reason this file exists at all is that the mod had NO device detection
-- of any kind.  Every default in lib/Quality.lua was chosen for "a phone" in
-- the abstract and then applied to every machine equally, which means the
-- phone got a default a desktop could have used and the desktop got a
-- default that made it look worse than it is.  A default that cannot see the
-- device is a guess wearing a number.
--
-- Everything here is cached after the first call and every call is wrapped:
-- this is consulted from inside the render path, where a throw takes the
-- frame with it.

local Device = {}

local info = nil

-- name, version, vendor, device -- the four strings LOVE gets from the GL
-- driver.  On the Poco X7 this reads roughly:
--   name    "OpenGL ES"
--   version "OpenGL ES 3.2 v1.r51p1-01eac0.<hash>"
--   vendor  "ARM"
--   device  "Mali-G615-MC2"
local function renderer()
  if info then return info end
  local ok, name, version, vendor, dev = pcall(love.graphics.getRendererInfo)
  if ok then
    info = { name = name or "", version = version or "",
             vendor = vendor or "", device = dev or "" }
  else
    info = { name = "", version = "", vendor = "", device = "" }
  end
  info.all = (info.name .. " " .. info.version .. " " ..
              info.vendor .. " " .. info.device):lower()
  return info
end

function Device.info() return renderer() end

function Device.describe()
  local r = renderer()
  if r.device ~= "" then return r.device .. " / " .. r.name end
  return r.name ~= "" and r.name or "(unknown GPU)"
end

-- ------- IS THIS A TILE-BASED MOBILE GPU
--
-- Two independent tests, either of which is enough, because either one alone
-- has a way to be wrong: a desktop can report an ES context (ANGLE, a GLES
-- emulator, a headless CI runner), and a vendor string can be missing.  What
-- neither of them does is produce a FALSE POSITIVE together with the other,
-- and the cost of a false positive here is only a conservative default that
-- the player -- or the governor in lib/AutoQuality.lua -- walks straight back
-- up within a couple of seconds.
local MOBILE_GPUS = {
  "mali", "adreno", "powervr", "apple a", "apple m", "videocore",
  "immortalis",   -- Arm's current top end, which does not say "Mali"
  "xclipse",      -- Samsung's RDNA part, a tiler in every way that matters
}

local isMobile = nil
function Device.mobile()
  if isMobile ~= nil then return isMobile end
  local r = renderer()
  local es = r.name:lower():find("es", 1, true) ~= nil
             or r.version:lower():find("opengl es", 1, true) ~= nil
  local gpu = false
  for _, needle in ipairs(MOBILE_GPUS) do
    if r.all:find(needle, 1, true) then gpu = true; break end
  end
  isMobile = es or gpu
  return isMobile
end

-- The panel, in real framebuffer pixels.  This is the number that decides
-- everything downstream and the number the mod was getting wrong by
-- inference: the machine this was written on is 1536x864 and the phone that
-- reported one frame a second is 2712x1220, which is two and a half times
-- the pixels through a GPU with a fraction of the fill rate.
function Device.panel()
  local ok, w, h = pcall(love.graphics.getPixelDimensions)
  if ok and w and h and w > 0 and h > 0 then return w, h end
  local ok2, w2, h2 = pcall(love.graphics.getDimensions)
  if ok2 and w2 and h2 and w2 > 0 and h2 > 0 then return w2, h2 end
  return 1280, 720
end

function Device.panelPixels()
  local w, h = Device.panel()
  return w * h
end

-- The dpi scale LOVE would give a canvas that did not ask.  Not used to size
-- anything -- lib/RenderTarget.lua pins every render target at 1 -- but worth
-- reporting, because a value other than 1 is the single fact that explains
-- the whole Android performance history of this mod.
function Device.dpiScale()
  local ok, s = pcall(love.graphics.getDPIScale)
  if ok and type(s) == "number" and s > 0 then return s end
  return 1
end

function Device.report()
  local w, h = Device.panel()
  return ("gpu: %s | mobile: %s | panel: %dx%d (%.2f Mpx) | dpiscale: %.3f")
    :format(Device.describe(), tostring(Device.mobile()), w, h,
            w * h / 1e6, Device.dpiScale())
end

-- Window resize, hot reload: the panel is re-read every call anyway, but the
-- renderer strings are cached and a reload should not keep a stale one.
function Device.invalidate()
  info, isMobile = nil, nil
end

return Device
