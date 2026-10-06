-- The CRT row: the whole frame, world and UI, shown on a television.
--
-- Not an overlay of stripes. Each preset is a set with an electronics path
-- and a tube, and the shader (assets/crt/crt.glsl) follows the signal the
-- way the set does:
--
--   SIGNAL  the frame is read along every scanline the beam will draw. A PVM
--           or a Trinitron on RGB only loses bandwidth; HOME and RF go through
--           an NTSC encoder and a set's decoder, so a one-pixel dither -- which
--           on this raster sits right under the colour subcarrier -- is taken
--           for colour, dissolves out of the luma and comes back as a faint
--           rainbow: the waterfall on a Mega Drive, done to Kanto's grass on
--           purpose. RF adds the aerial: snow, a ghost, a hum bar, a picture
--           that does not quite hold still. The phosphor is still glowing from
--           the frame before.
--   GLOW    the light scattered inside the faceplate (halation), small and
--           blurred.
--   TUBE    the beam's spot gets WIDER when it is brighter, so lit lines swell
--           until they nearly touch and dark lines thin to threads; three
--           beams that do not land together at the edges; a phosphor mask in
--           the panel's own pixels (aperture grille, slot or dot); curved
--           glass with rounded corners; the room in the glass.
--
-- ------- WHY ITS OWN PASS AND NOT THE ENGINE'S SHADER FX
--
-- The engine can run libretro's own presets (src/render/ShaderFX.lua): the
-- best CRT shaders there are. It is still the wrong foundation here:
--   * it needs a native bridge DLL to translate presets, a download of the
--     preset pack the game does not ship, and GLSL 3 -- none of which a GLES2
--     phone has, and the phones are half of who plays this mod;
--   * the presets that look like this (crt-royale, guest-advanced, Mega Bezel)
--     are 8-30 passes deep and far past a 1.5 ms budget on an Intel UHD;
--   * none of them knows that the Game Boy draws one line per pixel row, where
--     the world's dither is, what time it is in Kanto, or that it is raining.
-- So this is a render pipeline's `present` pass of the mod's own -- every
-- number tuned against this game, GLES2-safe, with its own rows and words.
-- And it HOLDS one of the two, the way the mod already holds TILT and GBC FX:
-- a ShaderFX preset whose name says CRT and this row cannot both be on (see
-- holdShaderFX). Whichever the player switched on last wins.
--
-- ------- THE RASTER
--
-- One scanline per Game Boy pixel row, phase-locked to the UI's rows. That is
-- what a Game Boy picture on a television IS -- 144 lines, the Super Game
-- Boy's centre -- and it is the only raster on which the 2D world's pixels
-- land whole on a line instead of straddling two. The 3D world and the
-- high-resolution cards are sampled onto the same lines, the way a PlayStation
-- game was: a scanline has the vertical resolution of a scanline. The mask is
-- sized to the panel instead (a television has ~500-700 triads across
-- whatever its size), in whole pixels so it can never beat against them.
--
-- ------- OFF COSTS NOTHING
--
-- The pipeline's level follows this row (CRT.update): OFF is level 0, the
-- engine sees no present pass, and the frame goes to the screen exactly as it
-- did before this file existed -- no extra canvas, no extra blit. The level
-- stays 1 through the power-off moment and drops when the dot has faded.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local RenderTarget = V.require("RenderTarget")
local Device = V.require("Device")

local CRT = {}

CRT.setting = ModSetting.new("crt", "CRT",
  { "off", "auto", "pvm", "trinitron", "home", "rf" },
  { "OFF", "AUTO", "PVM", "TRINITRON", "HOME", "RF" })
  :translate("CRT", { "DESLIGADO", "AUTO", "PVM", "TRINITRON", "CASA", "RF" })

-- The cabinet around the tube. Each set brings its own (a PVM's grey metal,
-- a Trinitron's black, the living-room set's graphite, the old aerial set's
-- wood) -- this only says whether to draw it.
CRT.frameSetting = ModSetting.new("crtframe", "CRT FRAME", { "off", "on" },
                                  { "OFF", "ON" })
  :translate("MOLDURA", { "DESLIGADA", "LIGADA" })

-- ------- THE SETS
--
-- Distances along a line are in GAME BOY PIXELS (gb) so a preset reads the
-- same at every window size; the beam's spot is in LINES; convergence is in
-- panel pixels at 1080p and scales with the panel.
CRT.PRESETS = {
  -- Sony's studio monitor. RGB in, 600-900 lines of resolution out, so the
  -- picture is as sharp as the console made it; the spot is small even when
  -- bright, which is THE look: black between every line, everywhere.
  pvm = {
    rgb = true, hdiv = 1, blur = 0.16, sharpen = 0.30,
    sigma = { 0.15, 0.32 }, bright = 1.32, gammaIn = 2.4,
    warp = { 0.010, 0.016 }, corner = 0.025,
    conv = { 0.10, -0.10, 0.15, -0.15 }, convY = { 0.0, 0.0 },
    mask = 0, triads = 720, maskDark = 0.30, maskBoost = 1.32,
    wires = 0.10,
    halation = 0.03, gapFill = 0.015, sat = 1.05,
    white = { 0.96, 0.99, 1.06 }, vignette = 0.06, knee = 0.80,
    decay = { 0.18, 0.22, 0.10 },
    cabinet = { 0.18, 0.18, 0.19 }, grain = 0.10, gloss = 0.25, wood = false,
  },
  -- A living-room Trinitron of the late nineties on S-Video: an aperture
  -- grille, a tube curved one way only, the two damper wires across it, and
  -- colour that was always a little too good.
  trinitron = {
    rgb = true, hdiv = 2, blur = 0.28, sharpen = 0.14,
    sigma = { 0.20, 0.42 }, bright = 1.16, gammaIn = 2.35,
    warp = { 0.0, 0.035 }, corner = 0.035,
    conv = { 0.35, -0.25, 0.55, -0.45 }, convY = { 0.03, -0.02 },
    mask = 0, triads = 600, maskDark = 0.38, maskBoost = 1.28,
    wires = 0.16,
    halation = 0.05, gapFill = 0.03, sat = 1.16,
    white = { 1.0, 1.0, 1.02 }, vignette = 0.16, knee = 0.82,
    decay = { 0.26, 0.30, 0.14 },
    cabinet = { 0.055, 0.055, 0.06 }, grain = 0.04, gloss = 0.55, wood = false,
  },
  -- The family television on the composite jack: a slot mask, a curved
  -- tube, warm whites, and NTSC doing to the picture what NTSC did.
  home = {
    rgb = false, hdiv = 2, fsc = 0.55, linePhase = 0.5, framePhase = 0.0,
    melt = 1.0, art = 0.22, crawl = 0.30, chromaSat = 1.06, ySoft = 0.10,
    chromaShift = 1.0, snow = 0.006, jitter = 0.12,
    sigma = { 0.22, 0.45 }, bright = 1.14, gammaIn = 2.35,
    warp = { 0.032, 0.042 }, corner = 0.05,
    conv = { 0.55, -0.45, 1.10, -0.95 }, convY = { 0.05, -0.04 },
    mask = 1, triads = 520, maskDark = 0.42, maskBoost = 1.26,
    wires = 0.0,
    halation = 0.07, gapFill = 0.04, sat = 1.10,
    white = { 1.05, 1.0, 0.91 }, vignette = 0.26, knee = 0.84,
    decay = { 0.30, 0.32, 0.16 },
    static = true,
    cabinet = { 0.16, 0.155, 0.15 }, grain = 0.12, gloss = 0.3, wood = false,
  },
  -- An older set on the aerial input, channel 3: everything HOME does plus
  -- the air -- snow, a ghost a fraction of a line late, a hum bar rolling up,
  -- lines that will not quite hold.
  rf = {
    rgb = false, hdiv = 2, fsc = 0.55, linePhase = 0.5, framePhase = 0.5,
    melt = 1.0, art = 0.35, crawl = 0.55, chromaSat = 0.92, ySoft = 0.32,
    chromaShift = 1.6, snow = 0.05, jitter = 0.45,
    ghost = 0.20, ghostDelay = 1.6, hum = 0.06, humSpeed = 0.045, wobble = 0.35,
    sigma = { 0.25, 0.48 }, bright = 1.16, gammaIn = 2.3,
    warp = { 0.045, 0.055 }, corner = 0.07,
    conv = { 0.8, -0.7, 1.5, -1.3 }, convY = { 0.07, -0.06 },
    mask = 2, triads = 480, maskDark = 0.45, maskBoost = 1.24,
    wires = 0.0,
    halation = 0.09, gapFill = 0.05, sat = 1.0,
    white = { 1.06, 1.0, 0.88 }, vignette = 0.36, knee = 0.85,
    decay = { 0.32, 0.34, 0.18 },
    static = true,
    cabinet = { 0.36, 0.22, 0.12 }, grain = 0.16, gloss = 0.2, wood = true,
  },
}

-- ------- AUTO
--
-- A phone panel holds 400-500 pixels to the inch: no mask survives that, and
-- every pass is paid for on a tiler. So a phone gets the Trinitron in its
-- LITE form (no mask, no convergence, no persistence, a coarser signal).
-- Anything else gets the living-room set -- the one most people actually had.
function CRT.autoKey()
  if Device.mobile() then return "trinitron", true end
  return "home", false
end

-- What the row resolves to: a preset key (and whether it is the LITE form),
-- or nil for OFF.
function CRT.resolve()
  local v = CRT.setting:get()
  if v == "off" or v == nil then return nil end
  if v == "auto" then return CRT.autoKey() end
  if CRT.PRESETS[v] then return v, Device.mobile() end
  return nil
end

-- The preset as drawn: the LITE form strips the costly parts; a driver that
-- refused part of the shader strips those too (see `refused`).
local refused = {}
CRT.refused = refused

local function lite(P)
  local L = {}
  for k, v in pairs(P) do L[k] = v end
  L.mask = 3
  L.conv = { 0, 0, 0, 0 }
  L.hdiv = 3
  L.decay = nil
  L.lite = true
  return L
end

function CRT.preset(key, isLite)
  local P = CRT.PRESETS[key]
  if not P then return nil end
  if isLite then P = lite(P) end
  return P
end

-- ------- THE ROOM
--
-- What the glass reflects. The room follows Kanto's clock, because that is
-- where the player is sitting: by day a window off to the upper left, cold and
-- wide; at dusk the same window gone gold; at night the room's own lamp -- and
-- with GLOW on, that lamp is lit, a warm smudge in the upper right and the
-- blacks lifted toward amber. With GLOW off the room is dark at night and the
-- tube reflects almost nothing. A lightning strike outside lights the room
-- for a tenth of a second, cold.
CRT.room = { r = 0.62, g = 0.68, b = 0.78, lift = 0.0055, x = -0.62, y = -0.70,
             size = 0.46, strength = 0.022, flash = 0 }

function CRT.roomTarget()
  local okD, DayNight = pcall(V.require, "DayNight")
  local okG, Glow = pcall(V.require, "Glow")
  local mix = { day = 1 }
  if okD and DayNight and DayNight.mix then
    local ok, m = pcall(DayNight.mix, DayNight.time())
    if ok and m then mix = m end
  end
  local lampOn = okG and Glow and Glow.enabled and Glow.enabled()
  local lamp = { 1.0, 0.78, 0.48 }
  if okD and DayNight.lampColor then
    local ok, c = pcall(DayNight.lampColor)
    if ok and c then lamp = c end
  end
  -- weights for the window (day), the gold window (twilight) and the lamp
  local win = (mix.day or 0) + (mix.golden or 0)
  local gold = (mix.dawn or 0) + (mix.dusk or 0)
  local night = (mix.night or 0) + (mix.violet or 0)
  local L = lampOn and 1 or 0.18
  local function at(a, b, c)
    return win * a + gold * b + night * (lampOn and c or c * 0.2)
  end
  return {
    r = at(0.62, 0.95, lamp[1]), g = at(0.68, 0.72, lamp[2] * 0.92),
    b = at(0.78, 0.48, lamp[3] * 0.8),
    lift = win * 0.0055 + gold * 0.0050 + night * 0.0045 * L,
    -- where the light comes from: the window up-left, the lamp up-right
    x = (win + gold) * -0.62 + night * 0.58,
    y = -0.70,
    size = (win + gold) * 0.46 + night * 0.30,
    strength = win * 0.022 + gold * 0.026 + night * 0.034 * L,
  }
end

local function stepRoom(dt)
  local okT, target = pcall(CRT.roomTarget)
  if not okT then return end
  local k = 1 - math.exp(-(dt or 0) * 1.5)
  local R = CRT.room
  for _, f in ipairs({ "r", "g", "b", "lift", "x", "y", "size", "strength" }) do
    R[f] = R[f] + (target[f] - R[f]) * k
  end
  local okW, Weather = pcall(V.require, "Weather")
  local fl = 0
  if okW and Weather and Weather.flash then
    local ok, f = pcall(Weather.flash)
    if ok and f then fl = f end
  end
  R.flash = fl * 0.06
end

-- ------- THE MOMENTS
--
-- on        the set coming on: dark, then a white line across the middle that
--           opens into the picture, overshoots a hair and settles, the tube
--           still warming for a second after (and the degauss coil's thump
--           that every set gave at power-on).
-- off       the picture falls to a line, the line to a point, and the point
--           burns on in the dark of the glass and fades.
-- degauss   changing set: the coil's field shakes the picture and knocks the
--           colour off true in swirls that ring down.
-- static    between channels: a burst of snow and a roll while the set finds
--           sync again. HOME and RF only, on every new map.
CRT.DURATION = { on = 1.6, off = 1.05, degauss = 1.5, static = 0.42 }

local function ease(u) u = math.max(0, math.min(1, u)) return u * u * (3 - 2 * u) end
local function lerp(a, b, u) return a + (b - a) * math.max(0, math.min(1, u)) end

-- The animation's uniforms at time t into `kind`. Pure: the probes and the
-- lab sample it frame by frame.
function CRT.moment(kind, t)
  local a = { vs = 1, hs = 1, flare = 0, degauss = 0, clock = t or 0,
              static = 0, roll = 0, spotRx = 1, spotRy = 1, spotI = 0 }
  if kind == "on" then
    if t < 0.10 then
      a.vs, a.flare = 0.004, -1
    elseif t < 0.20 then
      local u = (t - 0.10) / 0.10
      a.vs, a.hs = 0.004, lerp(0.15, 1, ease(u))
      a.flare = 2.6
      a.spotRx, a.spotRy, a.spotI = 1.1 * a.hs, 0.025, 0.55
    elseif t < 0.52 then
      local u = (t - 0.20) / 0.32
      local e = 1 - (1 - u) ^ 3
      a.vs = lerp(0.004, 1.03, e)
      a.flare = lerp(2.6, -0.25, u)
      a.spotRx, a.spotRy, a.spotI = 1.1, lerp(0.025, 0.4, u), lerp(0.55, 0, u)
    else
      local u = (t - 0.52)
      a.vs = 1 + 0.03 * math.exp(-u * 9) * math.cos(u * 26)
      a.flare = lerp(-0.25, 0, u / 1.0)
      a.degauss = 0.32 * math.exp(-u * 3.2)
    end
  elseif kind == "off" then
    if t < 0.13 then
      local u = t / 0.13
      a.vs = lerp(1, 0.006, u * u)
      a.flare = lerp(0, 1.6, u)
    elseif t < 0.29 then
      local u = (t - 0.13) / 0.16
      a.vs = 0.006
      a.hs = lerp(1, 0.004, 1 - (1 - u) ^ 2)
      a.flare = lerp(1.6, 3.2, u)
      a.spotRx, a.spotRy, a.spotI = math.max(0.02, a.hs * 1.1), 0.02, lerp(0.4, 0.9, u)
    else
      local u = t - 0.29
      a.vs, a.hs = 0.006, 0.004
      a.flare = -1
      a.spotRx = 0.018 + u * 0.03
      a.spotRy = a.spotRx
      a.spotI = 1.1 * math.exp(-u * 4.2)
    end
  elseif kind == "degauss" then
    a.degauss = 1.0 * math.exp(-t * 2.3) * (0.62 + 0.38 * math.cos(t * 13.8))
    a.roll = 0.012 * math.exp(-t * 11) * math.cos(t * 44)
  elseif kind == "static" then
    local u = t / CRT.DURATION.static
    a.static = 0.9 * (1 - u) ^ 1.5
    a.roll = 0.16 * (1 - ease(u * 1.15))
  end
  return a
end

-- ------- the state machine

local shown, shownLite = nil, false    -- the set on screen, nil = off
local anim = nil                        -- { kind = ..., t = ... }
local lastMap = nil
CRT.frameNo = 0

function CRT.active()
  return shown ~= nil
end

function CRT.animating()
  return anim and anim.kind or nil
end

local function start(kind)
  anim = { kind = kind, t = 0 }
end

-- ------- holding SHADER FX's own CRT presets off (and being held off)

local CRT_NAMES = { "crt", "royale", "lottes", "guest", "koko", "bezel", "pvm",
                    "trinitron", "scanline", "aperture", "slotmask", "shadowmask",
                    "dotmask", "zfast", "hyllian", "easymode", "caligari", "cgwg",
                    "newpixie", "geom", "gtu", "tvout", "ntsc", "phosphor" }

function CRT.isCRTName(name)
  name = tostring(name or ""):lower()
  for _, n in ipairs(CRT_NAMES) do
    if name:find(n, 1, true) then return true end
  end
  return false
end

local sfxSeen = {}       -- slot -> the preset name seen there last frame
local sfxBaseline = false

local function holdShaderFX(game)
  local ok, SFX = pcall(require, "src.render.ShaderFX")
  if not (ok and SFX and SFX.activeEntry and SFX.SLOTS) then return end
  for _, slot in ipairs(SFX.SLOTS) do
    local entry = SFX.activeEntry(slot)
    local name = entry and entry.name
    local isCRT = name and CRT.isCRTName(name)
    if isCRT and CRT.resolve() then
      if sfxBaseline and sfxSeen[slot] ~= name then
        -- the player just put a CRT preset on in SHADER FX: it wins, this
        -- row steps down to OFF (and says so the next time the menu opens)
        CRT.setting:setIndex(1, game)
      else
        -- this row came on (or both were on at boot): the preset steps down
        pcall(SFX.deactivate, slot)
        local opts = game and game.save and game.save.options
        local key = SFX.OPTION_KEY and SFX.OPTION_KEY[slot]
        if opts and key then
          opts[key] = nil
          if game.writeOptions then pcall(game.writeOptions, game) end
        end
        name = nil
      end
    end
    sfxSeen[slot] = name
  end
  sfxBaseline = true
end

-- The pipeline's tick: the row, the moments, the room. Runs every frame
-- whatever the level (Pipelines.update ticks them all), which is what lets
-- this switch the level itself.
function CRT.update(dt, game)
  dt = math.min(dt or 0, 0.1)
  pcall(holdShaderFX, game)
  local want, wantLite = CRT.resolve()
  if want ~= shown or (want and wantLite ~= shownLite) then
    if want and shown == nil and not (anim and anim.kind == "off") then
      start("on")
    elseif want and anim and anim.kind == "off" then
      start("on")
    elseif want == nil and shown ~= nil then
      if not (anim and anim.kind == "off") then start("off") end
    elseif want and shown then
      start("degauss")
    end
    if want ~= nil then shown, shownLite = want, wantLite end
  end
  -- a new map is a new channel, on the sets that have a tuner in the way
  local okG, map = pcall(function() return game.overworld.map.id end)
  map = okG and map or nil
  if map and lastMap and map ~= lastMap and shown and CRT.PRESETS[shown].static
     and not anim then
    start("static")
  end
  lastMap = map or lastMap
  if anim then
    anim.t = anim.t + dt
    if anim.t >= CRT.DURATION[anim.kind] then
      if anim.kind == "off" then shown = nil end
      anim = nil
    end
  end
  stepRoom(dt)
end

-- ------- the uniforms
--
-- Everything the passes are sent, from a preset and the frame's geometry.
-- Pure -- no love, no state -- so tools/crt_lab/serve.py runs this very
-- function through lupa and the lab shows exactly what the game will.
--
--   env.W, env.H    the frame in panel pixels
--   env.sp          panel pixels per Game Boy pixel (the UI's scale)
--   env.top         panel y of the UI's first row (the lines lock to it)
--   env.frame       a frame counter;  env.seed  0..1, new every frame
--   env.clock       seconds, for the slow things (the hum bar)
--   env.bezel       draw the cabinet
--   env.anim        CRT.moment(...) or nil
--   env.room        CRT.room
--   env.dt          the frame's length, for the persistence
function CRT.uniforms(P, env)
  local W, H = env.W, env.H
  local sp = math.max(1, env.sp or (H / 144))
  local per = sp
  local top = (env.top or 0) % per
  local rows = math.ceil((H - top) / per) + 2
  local RW = math.max(16, math.floor(W / (P.hdiv or 2) + 0.5))
  local GW = math.max(16, math.floor(RW / 4 + 0.5))
  local GH = math.max(8, math.floor(GW * H / W + 0.5))
  local k1080 = W / 1920
  local a = env.anim or CRT.moment(nil, 0)
  local R = env.room or CRT.room

  -- the picture's rectangle: the whole frame, or inset in its cabinet with
  -- more cabinet below than above, the way a set's controls sit
  local tx, ty, tw, th = 0, 0, W, H
  if env.bezel then
    tw, th = math.floor(W * 0.84 + 0.5), math.floor(H * 0.84 + 0.5)
    tx = math.floor((W - tw) / 2 + 0.5)
    ty = math.floor((H - th) * 0.40 + 0.5)
  end
  local T = math.max(2, math.floor(W / (P.triads or 600) + 0.5))

  local signalDefines, tubeDefines = {}, {}
  if not P.rgb then signalDefines[#signalDefines + 1] = "COMPOSITE" end
  if (P.ghost or 0) > 0 then signalDefines[#signalDefines + 1] = "GHOST" end
  if (P.snow or 0) > 0 or (P.hum or 0) > 0 then signalDefines[#signalDefines + 1] = "NOISE" end
  if P.decay then signalDefines[#signalDefines + 1] = "PERSIST" end
  local conv = P.conv or { 0, 0, 0, 0 }
  if conv[1] ~= 0 or conv[2] ~= 0 or conv[3] ~= 0 or conv[4] ~= 0 then
    tubeDefines[#tubeDefines + 1] = "CONVERGE"
  end
  if env.bezel then tubeDefines[#tubeDefines + 1] = "FRAME" end

  -- persistence: per-frame survival in light, carried into the gamma the
  -- signal pass stores, and stretched to this frame's real length
  local decay = { 0, 0, 0 }
  if P.decay then
    local frames = math.max(0.25, (env.dt or (1 / 60)) * 60)
    for i = 1, 3 do decay[i] = (P.decay[i] ^ frames) ^ (1 / 2.2) end
  end

  local cyc = sp / (P.fsc or 0.55)
  local half = th * 0.5
  local u = {
    RW = RW, RH = rows, GW = GW, GH = GH, frame = env.bezel and true or false,
    T = T, per = per, top = top,
    signalDefines = signalDefines, tubeDefines = tubeDefines,
    signal = {
      srcSize = { W, H, 1 / W, 1 / H },
      raster = { per, top, rows, 1 / rows },
      carrier = { cyc, P.linePhase or 0.5, ((P.framePhase or 0) * (env.frame or 0)) % 1, cyc / 4 },
      decode = { P.melt or 0, P.art or 0, P.crawl or 0, P.chromaSat or 1 },
      band = { (P.blur or 0.25) * sp, P.ySoft or 0, P.chromaShift or 0, P.sharpen or 0 },
      air = { P.snow or 0, P.ghost or 0, (P.ghostDelay or 0) * sp, (P.jitter or 0) * k1080 },
      hum = { P.hum or 0, ((env.clock or 0) * (P.humSpeed or 0)) % 1,
              (P.wobble or 0) * k1080, env.seed or 0 },
      decay = decay,
    },
    tube = {
      outSize = { W, H, 1 / W, 1 / H },
      tube = { tx, ty, tw, th },
      raster = { per, top, rows, 1 / rows },
      geom = { P.warp[1], P.warp[2], P.corner or 0.04, 1.5 / half },
      beam = { P.sigma[1], P.sigma[2], P.bright or 1.15, P.gammaIn or 2.35 },
      conv = { conv[1] * k1080, conv[2] * k1080, conv[3] * k1080, conv[4] * k1080 },
      convY = { (P.convY or {})[1] or 0, (P.convY or {})[2] or 0, P.wires or 0,
                math.max(1, 1.2 * k1080) },
      mask = { P.mask or 3, T, P.maskDark or 0.4, P.maskBoost or 1.25 },
      glowK = { P.halation or 0.08, P.gapFill or 0.04, 1 / 2.2, P.sat or 1 },
      shade = { P.vignette or 0.2, P.knee or 0.82, 0, 0 },
      white = P.white or { 1, 1, 1 },
      room = { R.r, R.g, R.b, R.lift },
      spec = { R.x, R.y, R.size, R.strength },
      anim = { a.vs, a.hs, a.flare, a.degauss },
      anim2 = { a.clock, a.static, a.roll, R.flash or 0 },
      spot = { a.spotRx, a.spotRy, a.spotI, 0 },
      detail = { P.detail or 1, P.detailGap or 0.45, 0, 0 },
      spill = { 0.10, 0.9, 0, 0 },
    },
    bezel = {
      outSize = { W, H, 1 / W, 1 / H },
      tube = { tx, ty, tw, th },
      geom = { P.warp[1], P.warp[2], P.corner or 0.04, 1.5 / half },
      plastic = P.cabinet or { 0.1, 0.1, 0.1 },
      finish = { P.grain or 0.1, P.gloss or 0.3, math.max(6, 14 * k1080), P.wood and 1 or 0 },
    },
  }
  return u
end

-- ------- the GPU side

local source = nil
local shaders = {}          -- variant key -> Shader | false
local noise = nil
local Rt, Gt, bezel = {}, {}, nil
local rKey, bezelKey = nil, nil
local out, outKey = nil, nil
local cur = 1
local reported = false

local function glslSource()
  if source == nil then
    local mod = V.mod
    local ok, text = pcall(function() return mod:read("assets/crt/crt.glsl") end)
    source = (ok and text) or false
  end
  return source or nil
end

local function highpOK()
  local ok, sup = pcall(love.graphics.getSupported)
  if not (ok and sup) then return true end
  if sup.pixelshaderhighp == nil then return true end
  return sup.pixelshaderhighp
end

local function build(pass, defines)
  local key = pass .. ":" .. table.concat(defines, ",")
  local hit = shaders[key]
  if hit ~= nil then return hit or nil, key end
  local src = glslSource()
  if not src then shaders[key] = false return nil, key end
  local head = { "#define " .. pass }
  for _, d in ipairs(defines) do head[#head + 1] = "#define " .. d end
  local ok, sh = pcall(love.graphics.newShader, table.concat(head, "\n") .. "\n" .. src)
  if not ok then
    refused[#refused + 1] = key .. ": " .. tostring(sh):sub(1, 400)
    sh = false
  end
  shaders[key] = sh
  return sh or nil, key
end

-- Strip a refused define list down until the driver takes it: the ladder.
-- Order is cheapest-to-lose first; the bare pass (no defines) is the floor.
local DROP = { "FRAME", "GHOST", "NOISE", "COMPOSITE", "PERSIST", "CONVERGE" }

local function ladder(pass, defines)
  local list = {}
  for _, d in ipairs(defines) do list[#list + 1] = d end
  for i = 0, #DROP do
    if i > 0 then
      for j = #list, 1, -1 do if list[j] == DROP[i] then table.remove(list, j) end end
    end
    local sh = build(pass, list)
    if sh then return sh, list end
  end
  return nil
end

local function noiseImage()
  if noise then return noise end
  local ok, img = pcall(function()
    local d = love.image.newImageData(256, 256)
    local rnd = love.math.newRandomGenerator(1985)
    d:mapPixel(function() return rnd:random(), rnd:random(), rnd:random(), rnd:random() end)
    local im = love.graphics.newImage(d)
    im:setFilter("nearest", "nearest")
    im:setWrap("repeat", "repeat")
    return im
  end)
  noise = ok and img or false
  return noise or nil
end

function CRT.available()
  if not (love and love.graphics and love.graphics.newShader) then return false end
  return ladder("PASS_TUBE", {}) ~= nil and ladder("PASS_SIGNAL", {}) ~= nil
end

local function send(sh, name, v)
  if sh:hasUniform(name) then pcall(sh.send, sh, name, v) end
end

local function sendAll(sh, t)
  for k, v in pairs(t) do send(sh, k, v) end
end

local function targets(u, W, H, dpi)
  local key = table.concat({ u.RW, u.RH, u.GW, u.GH }, "x")
  if rKey ~= key then
    for i = 1, 2 do RenderTarget.release(Rt[i]); RenderTarget.release(Gt[i]) end
    Rt = { RenderTarget.new(u.RW, u.RH), RenderTarget.new(u.RW, u.RH) }
    Gt = { RenderTarget.new(u.GW, u.GH), RenderTarget.new(u.GW, u.GH) }
    for i = 1, 2 do
      if not (Rt[i] and Gt[i]) then rKey = nil return false end
      Rt[i]:setFilter("linear", "linear")
      Gt[i]:setFilter("linear", "linear")
      love.graphics.setCanvas(Rt[i]); love.graphics.clear(0, 0, 0, 1)
    end
    love.graphics.setCanvas()
    rKey = key
  end
  local oKey = W .. "x" .. H .. "@" .. dpi
  if outKey ~= oKey then
    RenderTarget.release(out)
    out = RenderTarget.new(W / dpi, H / dpi, { dpiscale = dpi })
    if out then out:setFilter("linear", "linear") end
    outKey = out and oKey or nil
    bezelKey = nil
  end
  return out ~= nil
end

-- Where the UI's rows start, in panel pixels, and how tall one is: the
-- lines lock to them. The renderer's own answer when it has one.
local function rows(ctx, H)
  local ok, r = pcall(function() return require("src.render.Renderer"):frameRects() end)
  if ok and r and r.Up and r.Up > 0 then
    return r.Up, (r.uoy or 0) * (r.dpiY or 1)
  end
  return (ctx and ctx.scale) or math.max(1, math.floor(H / 144)), 0
end

local clock = 0

local function report(defs)
  if reported or #refused == 0 then return end
  reported = true
  print("TERRARIUM CRT: this driver refused part of the CRT shader; running "
        .. table.concat(defs, ",") .. "\n  " .. table.concat(refused, "\n  "))
end

-- Run the set over `canvas` (the finished frame) and return what to show.
function CRT.present(canvas, ctx)
  if not shown or not canvas then return canvas end
  local P = CRT.preset(shown, shownLite)
  if not P then return canvas end
  local okD, W, H = pcall(canvas.getPixelDimensions, canvas)
  if not okD then return canvas end
  local dpi = canvas.getDPIScale and canvas:getDPIScale() or 1
  local sp, top = rows(ctx, H)
  local frameOn = CRT.frameSetting:get() == "on"
  local dt = love.timer and love.timer.getDelta and love.timer.getDelta() or (1 / 60)
  clock = clock + dt
  CRT.frameNo = CRT.frameNo + 1
  if not highpOK() then P = lite(P) end
  local u = CRT.uniforms(P, {
    W = W, H = H, sp = sp, top = top, frame = CRT.frameNo,
    seed = love.math.random(), clock = clock, bezel = frameOn, dt = dt,
    anim = anim and CRT.moment(anim.kind, anim.t) or nil, room = CRT.room,
  })
  local sigSh, sigDefs = ladder("PASS_SIGNAL", u.signalDefines)
  local glowSh = ladder("PASS_GLOW", {})
  local tubeSh, tubeDefs = ladder("PASS_TUBE", u.tubeDefines)
  if not (sigSh and glowSh and tubeSh) then return canvas end
  report(sigDefs)
  local nz = noiseImage()
  if not nz then return canvas end
  if not targets(u, W, H, dpi) then return canvas end
  local usesFrame = false
  for _, d in ipairs(tubeDefs) do if d == "FRAME" then usesFrame = true end end

  local g = love.graphics
  local prevBlend, prevAlpha = g.getBlendMode()
  local ok = pcall(function()
    g.setColor(1, 1, 1, 1)
    g.setBlendMode("replace", "premultiplied")
    canvas:setFilter("linear", "linear")
    local curR, prevR = Rt[cur], Rt[3 - cur]
    -- the cabinet, once per size and set
    if usesFrame then
      local bk = outKey .. shown .. tostring(shownLite)
      if bezelKey ~= bk then
        local bz = ladder("PASS_BEZEL", {})
        if bz then
          if not bezel or bezel:getWidth() ~= out:getWidth() or bezel:getHeight() ~= out:getHeight() then
            RenderTarget.release(bezel)
            bezel = RenderTarget.new(W / dpi, H / dpi, { dpiscale = dpi })
          end
          if bezel then
            g.setCanvas(bezel)
            g.setShader(bz)
            sendAll(bz, u.bezel)
            -- soft noise for the plastic and the veneer, then back to the
            -- per-texel noise the signal and the static need
            nz:setFilter("linear", "linear")
            send(bz, "noiseTex", nz)
            g.draw(canvas, 0, 0)
            if g.flushBatch then g.flushBatch() end
            nz:setFilter("nearest", "nearest")
            bezelKey = bk
          end
        end
      end
    end
    -- the signal, one row per scanline
    g.setCanvas(curR)
    g.setShader(sigSh)
    sendAll(sigSh, u.signal)
    send(sigSh, "prevTex", prevR)
    send(sigSh, "noiseTex", nz)
    local cw, ch = canvas:getDimensions()
    g.draw(canvas, 0, 0, 0, u.RW / cw, u.RH / ch)
    -- the glow: down and across, then up and down
    g.setShader(glowSh)
    g.setCanvas(Gt[1])
    send(glowSh, "dir", { 1.5 / u.GW, 0 })
    g.draw(curR, 0, 0, 0, u.GW / u.RW, u.GH / u.RH)
    g.setCanvas(Gt[2])
    send(glowSh, "dir", { 0, 1.5 / u.GH })
    g.draw(Gt[1])
    -- the tube. The frame itself goes in once more, nearest-filtered, for
    -- the detail finer than a line (see the shader: a Game Boy row has to
    -- read back as one flat value there, and bilinear would blend the rows)
    if g.flushBatch then g.flushBatch() end
    canvas:setFilter("nearest", "nearest")
    g.setCanvas(out)
    g.setShader(tubeSh)
    sendAll(tubeSh, u.tube)
    send(tubeSh, "glowTex", Gt[2])
    send(tubeSh, "noiseTex", nz)
    send(tubeSh, "srcTex", canvas)
    if usesFrame and bezel then send(tubeSh, "bezelTex", bezel) end
    local ow, oh = out:getDimensions()
    g.draw(curR, 0, 0, 0, ow / u.RW, oh / u.RH)
    if g.flushBatch then g.flushBatch() end
  end)
  canvas:setFilter("linear", "linear")
  g.setCanvas()
  g.setShader()
  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  if not ok then return canvas end
  cur = 3 - cur
  return out
end

-- Drop the GPU objects (window resize, hot reload).
function CRT.invalidate()
  for i = 1, 2 do RenderTarget.release(Rt[i]); RenderTarget.release(Gt[i]) end
  RenderTarget.release(out); RenderTarget.release(bezel)
  Rt, Gt, out, bezel = {}, {}, nil, nil
  rKey, outKey, bezelKey = nil, nil, nil
end

-- For the probes: put the set in a known state without the row's moments.
function CRT.force(key, isLite, kind, t)
  shown, shownLite = key, isLite and true or false
  anim = kind and { kind = kind, t = t or 0 } or nil
end

return CRT
