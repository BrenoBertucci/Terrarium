-- Probe 6: Renderer.endFrame as the seam.
--
-- Probe 5 ruled out painting the window from inside the screen's draw: the
-- engine composites the (now empty, white) 160x144 UI canvas over the window
-- afterwards, so everything painted early is covered. The screenshot is
-- white, which is that canvas.
--
-- What is left is a hook that runs AFTER the composite. src.render.Renderer
-- carries beginFrame / endFrame / blitCanvas, and this measures three things
-- about them:
--
--   * is endFrame called once per FRAME (a camera needs 60, not the 15 the
--     screen's throttled draw gets),
--   * does painting there survive to the screenshot,
--   * and what is bound when it runs -- window or canvas.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/worldmap6.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()); f:close() end
      done = true
    end)
    local spin = 0
    while not done and spin < 240 do coroutine.yield(); spin = spin + 1 end
    log("  shot " .. name .. (done and " ok" or " TIMED OUT"))
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end
  wait(45)

  local Renderer = require("src.render.Renderer")
  local frames, ends, blits = 0, 0, 0
  local paint = false
  local canvasAtEnd = "?"

  local origEnd = Renderer.endFrame
  Renderer.endFrame = function(...)
    ends = ends + 1
    local r = { origEnd(...) }
    if ends <= 2 or paint then
      local c = love.graphics.getCanvas()
      canvasAtEnd = c and "canvas" or "window"
    end
    if paint then
      pcall(function()
        local prev = love.graphics.getCanvas()
        love.graphics.setCanvas()
        local w, h = love.graphics.getDimensions()
        love.graphics.push("all")
        love.graphics.setColor(0.85, 0.12, 0.18, 1)
        love.graphics.rectangle("fill", 0, 0, w, h * 0.5)
        love.graphics.setColor(0.10, 0.75, 0.35, 1)
        love.graphics.rectangle("fill", 0, h * 0.5, w * 0.5, h * 0.5)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("ENDFRAME PAINTS HERE", 40, 40)
        love.graphics.pop()
        love.graphics.setCanvas(prev)
      end)
    end
    return unpack(r)
  end

  local origBlit = Renderer.blitCanvas
  if origBlit then
    Renderer.blitCanvas = function(...) blits = blits + 1; return origBlit(...) end
  end

  local e0, b0 = ends, blits
  wait(60)
  log("in 60 frames of free roam: endFrame=" .. (ends - e0)
      .. " blitCanvas=" .. (blits - b0))
  log("canvas bound when endFrame runs: " .. canvasAtEnd)

  -- open the town map, silence its draw, and paint from endFrame
  local TownMap = require("src.ui.TownMap")
  local okN, screen = pcall(TownMap.new, game)
  if not okN then log("no screen"); logf:close(); love.event.quit(); return end
  rawset(screen, "draw", function() end)
  game.stack:push(screen)
  wait(25)
  log("map open: " .. tostring(game.stack:top() == screen))

  e0, b0 = ends, blits
  wait(60)
  log("in 60 frames with the map open: endFrame=" .. (ends - e0)
      .. " blitCanvas=" .. (blits - b0))

  shot("B0_silenced.png")
  paint = true
  wait(10)
  shot("B1_endframe.png")
  paint = false

  Renderer.endFrame = origEnd
  if origBlit then Renderer.blitCanvas = origBlit end
  tap("b"); wait(20)
  log("")
  log("DONE")
  logf:close()
  wait(2)
  love.event.quit()
end
