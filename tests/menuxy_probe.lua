-- Probe: is the X/Y start menu on screen, and is the Game Boy's one gone?
--
-- Both halves, because either alone is a broken frame and neither is visible
-- in a count of "is there a menu". The readings:
--
--   THE X/Y MENU IS THERE   its selected row is a saturated blue
--   (0.20, 0.52, 0.86) that nothing in the engine's 4-shade UI can produce.
--   Counted in the right-hand quarter of the frame, where the panel is.
--
--   THE ENGINE'S IS GONE    the old menu is an opaque WHITE box with a black
--   border, drawn in the same corner. Near-white pixels there are the tell,
--   and they have to fall to roughly nothing -- not merely change.
--
-- The A/B is StartMenuXY.ENABLED, which switches both halves together: with
-- it off the instance's draw falls through to the engine's, which is the
-- fallback a driver without the art would get.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/menuxy_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/menuxy.log", "w"))
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
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
    wait(4)
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit()
      return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end
  wait(60)

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end
  local StartMenuXY = lib.require("StartMenuXY")
  local TiltShift = lib.require("TiltShift")
  log("install: " .. tostring(StartMenuXY.install()))
  log("available: " .. tostring(StartMenuXY.available()))
  log("tiltshift level: " .. tostring(TiltShift.level))

  local roam = game.stack:top()
  tap("start"); wait(60)
  local menu = game.stack:top()
  if menu == roam or type(menu.items) ~= "table" then
    log("FAIL: no start menu"); logf:close(); love.event.quit(); return
  end
  log(("menu: %d rows, cursor %s, scroll %s, maxVisible %s")
      :format(#menu.items, tostring(menu.index), tostring(menu.scroll),
              tostring(menu.maxVisible)))
  log("found by StartMenuXY.current: "
      .. tostring(StartMenuXY.current(game) ~= nil))

  -- control pair first: the menu is static, so two shots of it must match,
  -- and anything they do not agree on is not something to read below.
  shot("menuxy_control_a.png")
  shot("menuxy_control_b.png")

  shot("menuxy_on.png")
  StartMenuXY.ENABLED = false; wait(30); shot("menuxy_off.png")
  StartMenuXY.ENABLED = true;  wait(30)

  -- and the cursor, because the selected row is drawn from menu.index and a
  -- highlight that does not move is a menu that only looks like it works
  tap("down"); wait(20)
  log("cursor after one down: " .. tostring(menu.index))
  shot("menuxy_moved.png")

  -- scrolled to the bottom: exercises menu.scroll and the chevrons
  for _ = 1, 8 do tap("down"); wait(6) end
  wait(20)
  log(("after eight more downs: index=%s scroll=%s")
      :format(tostring(menu.index), tostring(menu.scroll)))
  shot("menuxy_scrolled.png")

  logf:close()
  love.event.quit()
end
