-- Probe: does the TREES row actually swap the forest?
--
-- A/B on one map: TREES 3D vs VOXEL, flipped through the same path the
-- manager page uses (onOptionsChanged -> remesh), with a long settle so
-- the sliced tree build and the chunk rebuild both finish before the shot.
-- Also asserts the discontinued grass path stays down: Grass3D.wantsMesh()
-- must be false whatever the save says.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/trees_toggle_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/trees_toggle_probe.log", "w"))
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

  love.math.setRandomSeed(20260818)

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

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end
  log("version:", exports.TERRARIUM.version)

  local Trees3D = lib.require("Trees3D")
  local Grass3D = lib.require("Grass3D")
  local Voxel3D = lib.require("Voxel3D")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local AutoFarm = lib.require("AutoFarm")
  local Pipelines = require("src.render.Pipelines")

  Weather.setting:sync("off")
  DayNight.setting:sync("day")
  AutoFarm.setting:sync("off")
  log("grass wantsMesh (must be false):", tostring(Grass3D.wantsMesh()))

  pcall(Pipelines.setLevel, "terrarium_voxel", 4)
  local function wait3D(cap)
    for i = 1, (cap or 600) do
      if Voxel3D.lampLights ~= nil then return i end
      coroutine.yield()
    end
    return -1
  end
  wait(60); wait3D(600)

  local ok = pcall(function()
    game.overworld:setMap("ROUTE_1", 10, 18, "down")
  end)
  if not ok then
    log("FAIL: setMap"); logf:close(); love.event.quit(); return
  end
  Voxel3D.lampLights = nil
  log("3D up after", wait3D(600), "frames")
  wait(200)

  Trees3D.onOptionsChanged("3d")
  -- the tree build is sliced (SLICE_SITES) and the chunks rebuild on the
  -- budget pump; ROUTE_2's 862 sites took ~145 frames, so 400 clears a
  -- route with margin
  wait(400)
  log("A: setting=" .. tostring(Trees3D.setting:get())
      .. " available=" .. tostring(Trees3D.available()))
  shot("trees_3d.png")

  Trees3D.onOptionsChanged("voxel")
  wait(400)
  log("B: setting=" .. tostring(Trees3D.setting:get())
      .. " available=" .. tostring(Trees3D.available()))
  shot("trees_voxel.png")

  Trees3D.onOptionsChanged("3d")
  logf:close()
  love.event.quit()
end
