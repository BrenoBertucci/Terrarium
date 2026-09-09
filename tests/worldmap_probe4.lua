-- Probe 4: does anything of ours still run while the town map is open?
--
-- StartMenuXY's trick -- silence the engine's draw, paint from the render
-- pipeline's present hook -- depends on the WORLD still being drawn behind
-- the menu. The start menu is transparent, so it is. The town map declares
-- `isOpaque = true`, and an opaque screen is exactly the kind a stack stops
-- descending past: if the world stage is skipped, the present hook never
-- fires and the whole approach is wrong before a line of it is written.
--
-- So: count present calls with the map open, and look at what canvas the
-- screen's own draw is handed. Then find out which buttons the screen does
-- not already use, because a camera needs one.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/worldmap4.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
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

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  local MiniMap = lib.require("MiniMap")

  -- count the mod's present hook
  local presents = 0
  local origPresent = MiniMap.present
  MiniMap.present = function(c) presents = presents + 1; return origPresent(c) end

  -- and count the screen's own draw, and what canvas it gets
  local TownMap = require("src.ui.TownMap")
  local draws, canvasInfo = 0, "never drawn"
  local origDraw = TownMap.draw

  local function measure(label, frames)
    local p0, d0 = presents, draws
    wait(frames)
    log(("%-28s present=%-4d screendraw=%-4d over %d frames")
        :format(label, presents - p0, draws - d0, frames))
  end

  log("=== baseline: free roam ===")
  measure("free roam", 60)

  ------------------------------------------------------------------ OPEN IT
  log("")
  log("=== opening the town map ===")
  local screen
  local okN, made = pcall(TownMap.new, game)
  if okN and made then
    screen = made
    -- shadow draw on the INSTANCE (never the class -- lib/StartMenuXY.lua)
    rawset(screen, "draw", function(self, ...)
      draws = draws + 1
      if draws == 1 or draws == 30 then
        local c = love.graphics.getCanvas()
        if c then
          local okD, w, h = pcall(function() return c:getWidth(), c:getHeight() end)
          canvasInfo = okD and (w .. "x" .. h) or "canvas, dims?"
        else
          canvasInfo = "NO canvas (drawing straight to the window)"
        end
        local sw, sh = love.graphics.getDimensions()
        log("  inside screen draw #" .. draws .. ": canvas=" .. canvasInfo
            .. "  gfx dims=" .. sw .. "x" .. sh)
      end
      return origDraw(self, ...)
    end)
    game.stack:push(screen)
    wait(30)
    log("stack top is the map? " .. tostring(game.stack:top() == screen))
    measure("map open", 90)
    log("screen draw canvas: " .. canvasInfo)

    ---------------------------------------------------------------- BUTTONS
    log("")
    log("=== which buttons the screen uses ===")
    local function state()
      return ("sel=%s mode=%s playerLoc=%s stackTop=%s"):format(
        tostring(screen.sel), tostring(screen.mode),
        tostring(screen.playerLoc and screen.playerLoc.name),
        tostring(game.stack:top() == screen and "map" or "GONE"))
    end
    log("before      : " .. state())
    for _, b in ipairs({ "up", "down", "left", "right", "select", "start", "a" }) do
      if game.stack:top() ~= screen then
        log("  (map already closed -- stopping button sweep at " .. b .. ")")
        break
      end
      tap(b); wait(12)
      log(("after %-7s: %s"):format(b, state()))
    end

    -- and what the list looks like around the cursor
    if screen.locs and screen.sel then
      local s = screen.sel
      for i = math.max(1, s - 1), math.min(#screen.locs, s + 1) do
        local L = screen.locs[i]
        log(("  locs[%d] %s x=%s y=%s%s"):format(i, tostring(L.name),
            tostring(L.x), tostring(L.y), i == s and "   <== sel" or ""))
      end
    end

    if game.stack:top() == screen then
      tap("b"); wait(20)
      log("after b     : stack top is map? " .. tostring(game.stack:top() == screen))
    end
  else
    log("TownMap.new failed: " .. tostring(made))
  end

  log("")
  log("=== back in free roam ===")
  wait(20)
  measure("free roam again", 60)

  MiniMap.present = origPresent
  log("")
  log("DONE")
  logf:close()
  wait(2)
  love.event.quit()
end
