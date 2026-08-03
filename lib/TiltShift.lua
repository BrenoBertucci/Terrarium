-- Voxel world mode: tilt-shift post-process (the miniature-diorama look).
--
-- A depth-of-field fake that reads perfectly on a tilted voxel scene: a
-- horizontal band through the view centre (where the camera focuses -- the
-- player) stays sharp, and the frame blurs progressively toward the top
-- and bottom edges, with a slight saturation lift to sell the model-photo
-- feel. It runs on the finished voxel canvas as two separable gaussian
-- passes, so it costs two fullscreen draws and touches nothing in the 3D
-- pass itself.
--
-- This is a render pipeline in its own right -- a worldPresent pass, which
-- is the stage that post-processes the finished world BEFORE the UI
-- composites over it. That placement is the whole point: a miniature-photo
-- blur belongs on the diorama, not on the dialog box in front of it.
--
-- The engine owns the level: the T-SHIFT options row, its hotkey, the
-- OFF -> 1 -> 2 -> 3 -> OFF ladder and persistence in
-- save.options.pipelines all come from the render_pipelines record in
-- main.lua, and the current level arrives through update(). Each step
-- narrows the sharp band, deepens the blur and pushes the saturation a
-- little further.
--
-- Because worldPresent only runs when some pipeline rendered the world,
-- this draws over the voxel scene and nothing else. With it off (or on any
-- failure -- headless, no shader support) apply() hands the canvas back
-- untouched, so every other path is byte-for-byte what it always was.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Quality = V.require("Quality")

local TiltShift = {}

TiltShift.level = 0
TiltShift.LABELS = { "OFF", "1", "2", "3" }

-- The strength ladder. `spacing` is the gap between the gaussian's taps
-- at full blur, as a fraction of the canvas height (so the miniature
-- reads the same in a window and fullscreen; the blur's reach is 4x the
-- spacing per pass, and the two passes compound). `band` is the
-- half-height of the fully sharp zone and `range` the ramp to full blur,
-- both in canvas-uv units. The focus line sits at the vertical centre
-- because that is where the voxel camera parks the player.
TiltShift.FOCUS_Y = 0.5
TiltShift.PRESETS = {
  [1] = { spacing = 0.0016, band = 0.14, range = 0.42, saturation = 1.10 },
  [2] = { spacing = 0.0028, band = 0.10, range = 0.36, saturation = 1.18 },
  [3] = { spacing = 0.0042, band = 0.07, range = 0.30, saturation = 1.28 },
}

local SHADER = [[
  uniform vec2 dir;        // one texel step along the axis being blurred
  uniform float focusY;
  uniform float band;
  uniform float range;
  uniform float spacing;   // gap between taps at full blur, in texels
  uniform float boost;     // 0 = plain blur pass, 1 = final pass (color pop)
  uniform float saturation;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float d = abs(tc.y - focusY) - band;
    float s = clamp(d / range, 0.0, 1.0);
    s = s * s;             // ease in, so the band edge has no visible seam
    // The same 9-tap gaussian, gathered in 5 fetches.
    //
    // The taps either side of the centre come in adjacent pairs, and a
    // LINEARLY filtered sample placed between two texels already returns
    // their weighted sum -- so each pair costs one fetch rather than two if
    // the sample is placed at the pair's weighted midpoint. The offsets and
    // weights below are that reduction of the kernel above: 1.3846 carries
    // taps 1 and 2, 3.2308 carries taps 3 and 4, and the weights are the
    // pairs' sums. This is not a cheaper blur, it is the same blur -- the
    // canvases are already set to linear filtering for exactly this reason
    // (the tap offsets were never whole texels to begin with).
    //
    // Four fewer dependent fetches per pixel, over two full-screen passes,
    // is worth having anywhere and is worth a great deal on a phone.
    vec2 o = dir * (s * spacing);
    vec4 sum = Texel(tex, tc) * 0.2270270270;
    sum += (Texel(tex, tc + 1.3846153846 * o)
            + Texel(tex, tc - 1.3846153846 * o)) * 0.3162162162;
    sum += (Texel(tex, tc + 3.2307692308 * o)
            + Texel(tex, tc - 3.2307692308 * o)) * 0.0702702703;
    if (boost > 0.5) {
      float luma = dot(sum.rgb, vec3(0.299, 0.587, 0.114));
      sum.rgb = mix(vec3(luma), sum.rgb, saturation);
    }
    return sum * color;
  }
]]

local shader = nil            -- nil = untried, false = unavailable
local ping, pong, cw, ch = nil, nil, 0, 0
local out, ow, oh = nil, 0, 0

local function getShader()
  if shader == nil then
    local ok, sh = pcall(function() return love.graphics.newShader(SHADER) end)
    shader = (ok and sh) or false
  end
  return shader or nil
end

local function getCanvases(w, h)
  if not ping or cw ~= w or ch ~= h then
    local ok, a = pcall(love.graphics.newCanvas, w, h)
    if not ok then return nil end
    local okB, b = pcall(love.graphics.newCanvas, w, h)
    if not okB then return nil end
    -- the gaussian's fractional tap offsets need linear filtering
    a:setFilter("linear", "linear")
    b:setFilter("linear", "linear")
    ping, pong, cw, ch = a, b, w, h
  end
  return ping, pong
end

-- The full-size canvas the reduced blur is scaled back up into. Only ever
-- built when the blur runs under the panel's resolution; at RES FULL the
-- two gaussian passes land at full size already and this is never touched.
--
-- Nearest, like the scene canvas it follows: the sharp band is the whole
-- point of a tilt-shift, and a bilinear stretch would soften exactly the
-- part the pass exists to keep in focus. The blurred ends are smooth data
-- and come up smooth either way.
local function getOut(w, h)
  if out and ow == w and oh == h then return out end
  local ok, c = pcall(love.graphics.newCanvas, w, h)
  if not ok then return nil end
  c:setFilter("nearest", "nearest")
  out, ow, oh = c, w, h
  return out
end

function TiltShift.setLevel(level)
  level = math.floor(tonumber(level) or 0)
  if level < 0 then level = 0 end
  if level > 3 then level = 3 end
  TiltShift.level = level
end

-- The pipeline's per-frame tick: the engine hands over the level the
-- player has the T-SHIFT row set to.  No tween -- unlike the camera angle,
-- a blur strength has nothing to ease through.
function TiltShift.update(_, level)
  TiltShift.setLevel(level)
end

function TiltShift.levelLabel(level)
  return TiltShift.LABELS[(level or TiltShift.level) + 1] or "OFF"
end

function TiltShift.active()
  return TiltShift.level > 0
end

function TiltShift.reset()
  TiltShift.level = 0
end

-- Run the effect over `canvas` and return the processed canvas. Returns
-- the input unchanged when the effect is off or cannot run (headless, no
-- shader support), so the caller composites exactly what it was handed.
function TiltShift.apply(canvas)
  local preset = TiltShift.PRESETS[TiltShift.level]
  if not (preset and canvas) then return canvas end
  local sh = getShader()
  if not sh then return canvas end
  local w, h = canvas:getDimensions()

  -- Blur at the resolution the scene was RENDERED at, not the one it was
  -- scaled up to.
  --
  -- What arrives here at RES 1/2 is a half-resolution diorama already
  -- stretched over the panel: every 2x2 block of it is one rendered pixel.
  -- Running two full-screen gaussians across that is paying four times over
  -- to blur detail that is not in the image -- and this pass was, after the
  -- scene and the sun, the most expensive thing left in the frame.
  --
  -- So the first pass downsamples as it blurs (one draw, not two: the
  -- scale-down IS the draw), the second blurs the small image, and a plain
  -- copy puts it back on the panel. Three passes instead of two, but two of
  -- them are a quarter the size or less -- about a third of the fetches at
  -- 1/2, a ninth at 1/3.
  --
  -- At RES FULL the divisor is 1, the small canvases ARE full size, and the
  -- copy is skipped entirely: the original two-pass path, unchanged.
  local div = Quality.scale()
  local bw = math.max(1, math.floor(w / div))
  local bh = math.max(1, math.floor(h / div))

  local a, b = getCanvases(bw, bh)
  if not a then return canvas end
  local final = (bw ~= w or bh ~= h) and getOut(w, h) or nil
  if final == nil and (bw ~= w or bh ~= h) then return canvas end

  -- Worked out against the PANEL and then converted into blur-canvas
  -- texels, rather than worked out against the blur canvas directly. Same
  -- number of frame-heights of reach either way, but this way turning RES
  -- down does not also turn the blur up: a performance row that quietly
  -- restyled the picture would be a bad row.
  local spacing = math.max(0.75, math.min(3, h * preset.spacing)) / div
  local prevBlend, prevAlpha = love.graphics.getBlendMode()

  -- the voxel canvas filters nearest for its 1:1 blit; the blur taps need
  -- linear, restored below so the composite path sees what it expects
  canvas:setFilter("linear", "linear")
  love.graphics.setShader(sh)
  love.graphics.setColor(1, 1, 1, 1)
  -- replace, not alpha-blend: these are image-processing copies
  love.graphics.setBlendMode("replace", "premultiplied")
  pcall(sh.send, sh, "focusY", TiltShift.FOCUS_Y)
  pcall(sh.send, sh, "band", preset.band)
  pcall(sh.send, sh, "range", preset.range)
  pcall(sh.send, sh, "spacing", spacing)
  pcall(sh.send, sh, "saturation", preset.saturation)

  local ok = pcall(function()
    -- horizontal, downsampling on the way in: `dir` is one BLUR texel, so
    -- the kernel's reach is measured in the small canvas even though it is
    -- sampling the big one
    love.graphics.setCanvas(a)
    pcall(sh.send, sh, "dir", { 1 / bw, 0 })
    pcall(sh.send, sh, "boost", 0)
    love.graphics.draw(canvas, 0, 0, 0, bw / w, bh / h)
    -- vertical, and the saturation lift on the way out
    love.graphics.setCanvas(b)
    pcall(sh.send, sh, "dir", { 0, 1 / bh })
    pcall(sh.send, sh, "boost", 1)
    love.graphics.draw(a)
    -- and back onto the panel, shader off: this one is a copy.
    -- Nearest for the stretch, and only for the stretch -- b filters linear
    -- because pass two samples it at fractional offsets, but the sharp band
    -- is the whole argument of a tilt-shift and a bilinear upscale would
    -- soften exactly the part that is supposed to be in focus.
    if final then
      love.graphics.setCanvas(final)
      love.graphics.setShader()
      b:setFilter("nearest", "nearest")
      love.graphics.draw(b, 0, 0, 0, w / bw, h / bh)
      b:setFilter("linear", "linear")
    end
  end)

  love.graphics.setCanvas()
  love.graphics.setShader()
  love.graphics.setBlendMode(prevBlend or "alpha", prevAlpha)
  canvas:setFilter("nearest", "nearest")
  if not ok then return canvas end
  return final or b
end

-- Drop the GPU objects (window resize, hot reload).
function TiltShift.invalidate()
  ping, pong, cw, ch = nil, nil, 0, 0
  out, ow, oh = nil, 0, 0
end

return TiltShift
