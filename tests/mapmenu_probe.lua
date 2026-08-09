-- Probe: is the MAP row in the start menu, and does choosing it open the map?
--
-- Two separate claims and the second is the one worth testing. A row that
-- appears with the right label and does nothing when pressed is the failure
-- this catches: the label is read off `menu.items`, but whether the map opens
-- is only knowable by pressing A on it and looking at what the stack is
-- holding afterwards.
--
-- The row is also DRIVEN rather than called: the probe walks the cursor down
-- with the same button presses a player would use, so the test covers the
-- insertion index and the menu's own scrolling as well as the action.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/mapmenu_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/mapmenu.log", "w"))
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
  local StartMenuMap = lib.require("StartMenuMap")
  log("install() reports: " .. tostring(StartMenuMap.install()))

  local roam = game.stack:top()
  tap("start"); wait(45)
  local menu = game.stack:top()
  if menu == roam or type(menu.items) ~= "table" then
    log("FAIL: no start menu"); logf:close(); love.event.quit(); return
  end
  shot("mapmenu_open.png")

  local at = nil
  for i = 1, #menu.items do
    local label = menu.items[i] and menu.items[i].label
    log(("  [%d] %s"):format(i, tostring(label)))
    if label == StartMenuMap.LABEL then at = i end
  end
  log(("MAP row: %s (menu has %d rows, cursor starts at %s)")
      :format(at and ("row " .. at) or "ABSENT", #menu.items,
              tostring(menu.index)))
  if not at then
    log("FAIL: the row was not inserted")
    logf:close(); love.event.quit(); return
  end
  -- it has to be under ITENS, not merely present
  local above = menu.items[at - 1] and menu.items[at - 1].label
  log("row above it: " .. tostring(above))

  -- Drive the cursor to it the way a player would, then press A.
  local guard = 0
  while menu.index ~= at and guard < 40 do
    tap(menu.index < at and "down" or "up"); wait(8); guard = guard + 1
  end
  log(("cursor reached %s after %d presses (wanted %d)")
      :format(tostring(menu.index), guard, at))
  wait(10)
  shot("mapmenu_cursor.png")

  -- Which canvas does the menu draw INTO? This decides whether X/Y art can be
  -- used at all: the pack is 5x, and a menu that draws into the 160x144 UI
  -- canvas would have every one of those pixels thrown away on the way to the
  -- screen. Asked from inside the menu's own draw, because that is the only
  -- moment the answer is true.
  do
    local seen = nil
    local inner = menu.draw
    menu.draw = function(self, ...)
      if not seen then
        local c = love.graphics.getCanvas()
        if c then
          local w, h = c:getDimensions()
          seen = ("canvas %dx%d"):format(w, h)
        else
          seen = ("no canvas; screen %dx%d")
                 :format(love.graphics.getWidth(), love.graphics.getHeight())
        end
      end
      return inner(self, ...)
    end
    wait(20)
    menu.draw = inner
    log("menu draws into: " .. tostring(seen))
  end

  tap("a"); wait(90)
  local top = game.stack:top()
  local opened = (top ~= menu) and (top ~= roam)
  log("after A, stack top changed: " .. tostring(opened))
  -- and it is the MAP, not just something: TownMap's screens carry these
  local looksLikeMap = type(top) == "table" and top.locs ~= nil
                       and top.playerLoc ~= nil
  log("top looks like the town map (locs + playerLoc): "
      .. tostring(looksLikeMap))
  shot("mapmenu_after_a.png")

  logf:close()
  love.event.quit()
end
