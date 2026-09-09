-- Probe 5: where can a full-resolution frame be painted, with the map open?
--
-- Probe 4 killed the obvious route: the world stage does not run behind an
-- opaque screen, so the present hook never fires and StartMenuXY's split
-- (silence the draw, paint from the pipeline) has nothing to paint from.
-- What is left is the screen's own draw, which is handed the 160x144 UI
-- canvas -- the exact canvas that throws away every pixel worth drawing.
--
-- Two ways out, and this measures both rather than picking one:
--
--   A. UNBIND. Inside the shadowed draw, setCanvas() to the window, paint
--      full resolution, restore the UI canvas and leave it EMPTY. Works only
--      if the engine's own composite of that empty canvas does not paint
--      over what we just put on the window -- i.e. only if it blits rather
--      than clears.
--   B. A LATER HOOK. Ask the engine what pipeline stages exist at all. If
--      there is a whole-frame stage (not a world one), it is the right seam
--      and A is a hack around a door that was already open.
--
-- The screenshot is what decides A, and it is taken by WAITING ON THE
-- CALLBACK -- a shot scheduled and then slept on photographs the state
-- AFTER it, which has falsified probes in this mod before.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/worldmap5.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  -- wait for the CALLBACK, never a fixed number of frames
  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()); f:close() end
      done = true
    end)
    local spin = 0
    while not done and spin < 240 do coroutine.yield(); spin = spin + 1 end
    log("  shot " .. name .. (done and " ok" or " TIMED OUT") .. " after "
        .. spin .. " frames")
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld"); logf:close(); love.event.quit()
      return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end
  wait(45)

  --------------------------------------------------------- B. WHAT STAGES EXIST
  log("=== B. the pipeline schema ===")
  local okS, Schemas = pcall(require, "src.mods.Schemas")
  if okS and type(Schemas) == "table" then
    local ks = {}
    for k, v in pairs(Schemas) do ks[#ks + 1] = tostring(k) .. ":" .. type(v) end
    table.sort(ks)
    log("Schemas: " .. table.concat(ks, " "))
    local rp = Schemas.render_pipelines or Schemas.renderPipelines
    if type(rp) == "table" then
      local function deep(t, prefix, depth)
        if depth > 3 then return end
        local rows = {}
        for k, v in pairs(t) do rows[#rows + 1] = tostring(k) .. ":" .. type(v) end
        table.sort(rows)
        log(prefix .. " = " .. table.concat(rows, " "))
        for k, v in pairs(t) do
          if type(v) == "table" and depth < 3 then deep(v, prefix .. "." .. tostring(k), depth + 1) end
        end
      end
      deep(rp, "render_pipelines", 1)
    end
  else
    log("no src.mods.Schemas (" .. tostring(Schemas) .. ")")
  end
  -- and what a registered pipeline is allowed to carry, from our own
  local mods = game.mods
  log("game.mods fields: " .. (function()
    local ks = {}
    for k, v in pairs(mods or {}) do ks[#ks + 1] = tostring(k) .. ":" .. type(v) end
    table.sort(ks); return table.concat(ks, " ") end)())
  for _, name in ipairs({ "src.render.Renderer", "src.core.Screen",
                          "src.ui.Stack", "src.core.Stack" }) do
    local ok, M = pcall(require, name)
    if ok and type(M) == "table" then
      local fns = {}
      for k, v in pairs(M) do
        if type(v) == "function" then fns[#fns + 1] = tostring(k) end
      end
      table.sort(fns)
      log(name .. ": " .. table.concat(fns, " "))
    end
  end

  ------------------------------------------------------------- A. THE UNBIND
  log("")
  log("=== A. painting the window from inside the screen's draw ===")
  local TownMap = require("src.ui.TownMap")
  local okN, screen = pcall(TownMap.new, game)
  if not okN then
    log("TownMap.new failed"); logf:close(); love.event.quit(); return
  end

  local mode = "silent"   -- silent | window | both
  local origDraw = TownMap.draw
  local reports = 0
  rawset(screen, "draw", function(self, ...)
    if mode == "silent" then
      return                      -- draw nothing at all: is the frame empty?
    elseif mode == "window" or mode == "both" then
      local prev = love.graphics.getCanvas()
      local okU = pcall(function()
        love.graphics.setCanvas()               -- the window itself
        local w, h = love.graphics.getDimensions()
        love.graphics.push("all")
        love.graphics.setColor(0.9, 0.1, 0.15, 1)
        love.graphics.rectangle("fill", 0, 0, w, h * 0.5)
        love.graphics.setColor(0.1, 0.8, 0.3, 1)
        love.graphics.rectangle("fill", 0, h * 0.5, w * 0.5, h * 0.5)
        love.graphics.pop()
      end)
      pcall(love.graphics.setCanvas, prev)
      if reports < 2 then
        reports = reports + 1
        log("  painted window ok=" .. tostring(okU)
            .. " prevCanvas=" .. tostring(prev ~= nil))
      end
      if mode == "both" then return origDraw(self, ...) end
      return
    end
    return origDraw(self, ...)
  end)

  game.stack:push(screen)
  wait(30)
  log("map open, top is map? " .. tostring(game.stack:top() == screen))

  mode = "silent"
  if screen.markPlayerRedraw then pcall(screen.markPlayerRedraw, screen) end
  wait(20)
  shot("A0_silent.png")

  mode = "window"
  wait(20)
  shot("A1_window.png")

  mode = "both"
  wait(20)
  shot("A2_both.png")

  -- does the screen redraw every frame, or only when dirty? A camera needs
  -- every frame, so this is the difference between a diorama and a slideshow.
  local seen = 0
  rawset(screen, "draw", function(self, ...) seen = seen + 1 end)
  local before = seen
  wait(60)
  log("screen draw calls in 60 frames (nothing marking it dirty): "
      .. (seen - before))

  -- ...and with the cursor moving?
  before = seen
  for _ = 1, 6 do tap("up"); wait(9) end
  log("screen draw calls in ~60 frames while pressing up: " .. (seen - before))

  tap("b"); wait(20)
  log("closed? " .. tostring(game.stack:top() ~= screen))

  log("")
  log("DONE")
  logf:close()
  wait(2)
  love.event.quit()
end
