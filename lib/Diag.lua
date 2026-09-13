-- What this build actually is, printed on the screen it is running on.
--
-- ------- WHY THIS EXISTS
--
-- A phone cannot be asked anything.  `print` does not reach logcat from a
-- mod, `io` and `os.getenv` are not in the sandbox (src/mods/Sandbox.lua),
-- the save folder is not readable over adb on a modern Android, and the one
-- input channel that works -- a screenshot -- carries pixels and nothing
-- else.  So the only way to get a fact off that device is to DRAW it.
--
-- That gap cost this mod a whole round trip: a Poco X7 came back with "the
-- new tower does not load and neither does the new shop", both of which
-- stand perfectly well on every machine here, at every shader rung, at every
-- RES rung, with the crypt samplers refused and with the uniforms forced to
-- mediump.  Nothing reproducible, and nothing to ask.  One screenshot of
-- this panel would have said which version was installed, which rung the
-- driver took, what the rows are set to and how many models the map built --
-- and any one of those answers would have ended the guessing.
--
-- ------- WHAT IT IS CAREFUL ABOUT
--
-- Every read is a pcall and every line degrades to a "?" rather than taking
-- the frame with it: a diagnostic that can crash is worse than no
-- diagnostic, because it fires exactly on the machines that are already
-- unwell.  It ships OFF, it is one row on the OPTIONS page, and when it is
-- off this file costs one boolean test per frame.

local V = ...

local ModSetting = V.require("ModSetting")

local Diag = {}

Diag.setting = ModSetting.new("diag", "DIAG", { "off", "on" }, { "OFF", "ON" })

function Diag.on()
  local ok, v = pcall(Diag.setting.get, Diag.setting)
  return ok and v == "on"
end

function Diag.row() return Diag.setting:row() end

-- The map the last frame drew, captured in drawWorld because `present` is
-- handed a canvas and nothing else.
-- The map OBJECT, not its id: Structures.peek keys its cache on `map.id` but
-- takes the map, and handing it a string reads `("X").id`, which is nil, and
-- the count comes back "?" forever.  (It did.)
local lastMap = nil
function Diag.note(state)
  if not Diag.on() then return end
  local ok, m = pcall(function() return state and state.map end)
  lastMap = ok and m or nil
end

-- `mod.version` if the loader filled it, else the literal main.lua carries.
local function version()
  local m = V.mod
  local v = m and (m.version or (m.manifest and m.manifest.version))
  return tostring(v or (V.VERSION or "?"))
end

-- Long lines are WRAPPED rather than cut.  The first version truncated the
-- driver's refusal at 60 characters, and the one screenshot that came back
-- from the phone said `1st: Cannot compile pixel shader code:` and stopped --
-- the colon, and then the part that would have said WHY.  A diagnostic that
-- crops the answer is a diagnostic that costs a round trip.
local function wrapTo(text, width, out, indent)
  text = tostring(text or "")
  while #text > width do
    local cut = width
    for i = width, math.max(1, width - 18), -1 do
      if text:sub(i, i) == " " then cut = i break end
    end
    out[#out + 1] = (indent or "") .. text:sub(1, cut)
    text = text:sub(cut + 1):gsub("^%s+", "")
    indent = "      "
  end
  if #text > 0 then out[#out + 1] = (indent or "") .. text end
end

local function try(f, ...)
  local ok, a = pcall(f, ...)
  if ok and a ~= nil then return a end
  return nil
end

-- A module, and whether it is even here.  A mod module that throws while
-- LOADING is swallowed by V.require's caller and its whole feature simply is
-- not there, with nothing said -- which is one of the two shapes the missing
-- tower could have.  This is how that shape becomes visible.
local function mod(name)
  local ok, m = pcall(V.require, name)
  if not ok or not m then return nil, "LOAD FAILED" end
  return m, nil
end

local function rowOf(name, key)
  local m, err = mod(name)
  if not m then return err end
  local s = m[key or "setting"]
  if not s then return "no row" end
  local i = try(s.read, s)
  if not i then return "?" end
  return tostring(s.labels and s.labels[i] or s.values[i])
end

local function kitLine(label, name, enabledFn)
  local m, err = mod(name)
  if not m then return ("%s %s"):format(label, err) end
  local fn = m[enabledFn or "enabled"]
  if type(fn) ~= "function" then return ("%s loaded"):format(label) end
  local ok, on = pcall(fn)
  return ("%s %s"):format(label, ok and (on and "ON" or "off") or "ERR")
end

function Diag.lines()
  local out = {}
  local function add(s) out[#out + 1] = s end

  add("TERRARIUM " .. version())

  local Device = mod("Device")
  add(Device and (try(Device.report) or "device ?") or "Device LOAD FAILED")

  local Voxel3D = mod("Voxel3D")
  if Voxel3D then
    local refusals = 0
    local log = Voxel3D.compileLog
    if type(log) == "table" then refusals = #log end
    add(("shader   rung=%s prec=%s frag=%s refusals=%d avail=%s")
          :format(tostring(try(Voxel3D.rungName) or "?"),
                  tostring(try(Voxel3D.precName) or "?"),
                  tostring(try(Voxel3D.fragName) or "?"),
                  refusals,
                  tostring(try(Voxel3D.available))))
    if refusals > 0 and type(log[1]) == "table" then
      -- The driver's own words are the whole point of this line, so they get
      -- as many rows as they need.  Newlines come back in these strings, and
      -- a newline inside a love.graphics.print is a line that overprints the
      -- box, so they are flattened first.
      local msg = tostring(log[1].err or "?"):gsub("%s+", " ")
      wrapTo(msg, 96, out, "  1st: ")
    end
  else
    add("Voxel3D LOAD FAILED")
  end

  local Quality = mod("Quality")
  local AutoQuality = mod("AutoQuality")
  if Quality then
    add(("RES      %s -> 1/%s   SHADOWS %s")
          :format(rowOf("Quality", "setting"),
                  tostring(try(Quality.scale) or "?"),
                  rowOf("Quality", "shadowSetting")))
    if AutoQuality then
      add("  auto: " .. tostring(try(AutoQuality.report) or "?"))
    end
  end

  local RayFX = mod("RayFX")
  add(("SCREENFX %s -> %s   PFX %s")
        :format(rowOf("RayFX", "setting"),
                RayFX and tostring(try(RayFX.level) or "?") or "?",
                rowOf("Quality", "particleSetting")))

  add(("rows     TOWER=%s SHOP=%s CRYPT=%s TREES=%s")
        :format(rowOf("TowerKit"), rowOf("Shop"), rowOf("Crypt"),
                rowOf("Trees3D")))

  add(table.concat({ kitLine("TowerKit", "TowerKit"),
                     kitLine("ShopKit", "ShopKit"),
                     kitLine("CryptKit", "CryptKit"),
                     kitLine("RoomKit", "RoomKit") }, "  "))

  -- How many MODELS the current map actually built.  This is the number that
  -- separates "the kit is off" from "the kit ran and produced nothing".
  local Structures = mod("Structures")
  local built = "?"
  if Structures and lastMap then
    local list = try(Structures.peek, lastMap)
    if type(list) == "table" then
      local n = 0
      for _, v in pairs(list) do
        if type(v) == "table" then n = n + 1 end
      end
      built = tostring(n)
    elseif list == nil then
      -- peek answers nil until the scene pass has built the map, which is
      -- itself worth seeing: "not built yet" and "built nothing" are two
      -- different bugs.
      built = "not built"
    end
  end
  local id = "?"
  if lastMap then
    local okI, v = pcall(function() return lastMap.id end)
    if okI and v then id = tostring(v) end
  end
  add(("map      %s   models=%s"):format(id, built))

  return out
end

-- Drawn on the FINISHED canvas, like the radar and the start menu: this has
-- to be readable, so it must not go through the RES-downsampled 3D pass.
function Diag.present(canvas)
  if not (Diag.on() and canvas) then return canvas end
  local g = love.graphics
  local ok = pcall(function()
    local w, h = canvas:getDimensions()
    local prev = g.getCanvas()
    local pr, pg, pb, pa = g.getColor()
    local prevFont = g.getFont()
    local prevBlend, prevAlpha = g.getBlendMode()
    g.setCanvas(canvas)
    g.setBlendMode("alpha", "alphamultiply")
    g.setShader()
    -- sized to the panel rather than to a constant: 12pt is unreadable on a
    -- 2712-wide phone and enormous in a small window
    local s = math.max(1, math.floor(w / 640))
    local lines = Diag.lines()
    local font = prevFont or g.newFont(12)
    g.setFont(font)
    local lh = font:getHeight() * s
    local pad = 6 * s
    local bw = 0
    for _, l in ipairs(lines) do
      bw = math.max(bw, font:getWidth(l) * s)
    end
    -- and shrink to fit rather than running off the edge: the GPU line is the
    -- longest and it is the one a bug report most needs whole.  A screenshot
    -- with the driver string cut in half is a screenshot that has to be
    -- taken again.
    if bw > w - pad * 2 and bw > 0 then
      s = s * (w - pad * 2) / bw
      lh = font:getHeight() * s
      bw = w - pad * 2
    end
    g.setColor(0, 0, 0, 0.72)
    g.rectangle("fill", 0, 0, bw + pad * 2, lh * #lines + pad * 2)
    g.setColor(1, 1, 1, 1)
    for i, l in ipairs(lines) do
      g.print(l, pad, pad + (i - 1) * lh, 0, s, s)
    end
    g.setFont(prevFont or font)
    g.setColor(pr, pg, pb, pa)
    g.setBlendMode(prevBlend or "alpha", prevAlpha)
    if prev then g.setCanvas(prev) else g.setCanvas() end
  end)
  if not ok then pcall(g.setCanvas) end
  return canvas
end

return Diag
