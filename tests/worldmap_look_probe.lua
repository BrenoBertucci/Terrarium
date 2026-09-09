-- Look probe: open the town map and photograph what comes up.
--
-- Everything before this measured seams. This one measures the picture, and
-- it is the only thing that can: a region that builds, reports 120k vertices
-- and draws a black screen passes every check but the one that matters.
--
-- Screenshots are taken by WAITING ON THE CALLBACK. A shot scheduled and
-- then slept on for N frames photographs the state AFTER it, which in a
-- probe that moves a camera between shots means every frame is labelled with
-- the wrong pose.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/worldmap_look_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/worldmap_look.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local function hold(b, frames)
    for _ = 1, frames do
      game.input.pressQueue[#game.input.pressQueue + 1] = b
      coroutine.yield()
    end
  end
  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()); f:close() end
      done = true
    end)
    local spin = 0
    while not done and spin < 300 do coroutine.yield(); spin = spin + 1 end
    log("  shot " .. name .. (done and "" or "  TIMED OUT"))
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
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end
  local WM = lib.require("WorldMap3D")
  local function report(tag)
    local r = WM.report()
    local ks = {}
    for k, v in pairs(r) do ks[#ks + 1] = tostring(k) .. "=" .. tostring(v) end
    table.sort(ks)
    log(tag .. ": " .. table.concat(ks, " "))
  end
  report("before opening")

  -- open the map the way a player does: the MAP row of the start menu
  local TownMap = require("src.ui.TownMap")
  local okN, screen = pcall(TownMap.new, game)
  if not okN then
    log("FAIL: TownMap.new: " .. tostring(screen))
    logf:close(); love.event.quit(); return
  end
  game.stack:push(screen)
  wait(4)
  log("map open: " .. tostring(game.stack:top() == screen))
  log("sel=" .. tostring(screen.sel) .. " playerLoc="
      .. tostring(screen.playerLoc and screen.playerLoc.name))

  -- the build, caught mid-flight and then finished
  wait(6)
  shot("00_building.png")
  local waited = 0
  while not WM.report().built and waited < 900 do wait(6); waited = waited + 6 end
  log("built after ~" .. waited .. " frames of waiting")
  report("after build")
  do
    local q = WM.questReport()
    local ks = {}
    for k, v in pairs(q) do ks[#ks + 1] = tostring(k) .. "=" .. tostring(v) end
    table.sort(ks)
    log("QUEST: " .. table.concat(ks, "  "))
  end
  if not WM.report().built then
    log("FAIL: never built")
    logf:close(); love.event.quit(); return
  end

  -- the camera opens wide and settles: photograph the settle, not the throw
  wait(120)
  shot("01_region.png")

  -- every placed map: is its land actually IN the grid, and does its pin
  -- land where its geometry is?
  log("")
  log("placed maps (solid = cells carrying land, sx/sy = where the pin went)")
  for _, p in ipairs(WM.debugPlaces()) do
    log(("  %-22s grid=(%3d,%3d) %3dx%-3d solid=%-5d sea=%-5d pin=(%d,%d)")
        :format(p.id, p.gx, p.gy, p.w, p.h, p.solid, p.sea, p.sx, p.sy))
  end
  log("")

  -- the cursor moves, the camera leans
  hold("up", 1); wait(60)
  log("sel=" .. tostring(screen.sel) .. " -> "
      .. tostring(screen.locs and screen.locs[screen.sel]
                  and screen.locs[screen.sel].name))
  shot("02_cursor_moved.png")

  -- A zooms in on the selection
  WM.toggleZoom(); wait(110)
  report("after A")
  shot("03_zoomed.png")

  -- left orbits
  hold("left", 40); wait(40)
  shot("04_orbited.png")

  -- and the water, a second later, to see that it is actually moving
  wait(45)
  shot("05_water_later.png")

  -- SELECT looks straight down
  WM.toggleTopDown(); wait(110)
  shot("06_topdown.png")

  -- walk the cursor a few places and photograph one of them
  WM.toggleZoom(); wait(90)     -- back to the region
  for _ = 1, 8 do hold("up", 1); wait(10) end
  wait(80)
  log("sel now: " .. tostring(screen.locs and screen.locs[screen.sel]
                              and screen.locs[screen.sel].name))
  shot("07_elsewhere.png")
  WM.toggleZoom(); wait(120)
  shot("08_elsewhere_close.png")

  -- the far south: Cinnabar's island is the smallest placed map and the one
  -- most likely to be missing without anyone noticing
  log("focus CINNABAR_ISLAND: " .. tostring(WM.debugFocus("CINNABAR_ISLAND")))
  wait(140)
  shot("10_cinnabar.png")

  -- and B still closes it
  hold("b", 1); wait(30)
  log("closed: " .. tostring(game.stack:top() ~= screen))
  shot("09_after_close.png")
  report("after close")

  log("")
  log("DONE")
  logf:close()
  wait(2)
  love.event.quit()
end
