-- Probe: did the paving art land on the underground passage floor, and
-- ONLY there?
--
-- The class is recognised from the map's TILESET plus two colour boxes plus
-- vUp plus a height (see lib/FloorArt.lua). Three ways that can be wrong,
-- and none of them shows up in a number:
--
--   TOO NARROW   a box misses the field or the lattice and half the floor
--                keeps the flat tileset colour -- patchy.
--   TOO WIDE     a box catches something else on the same sheet.
--   WRONG SHEET  the colours also occur elsewhere -- (247, 82, 49) is the
--                overworld's FLOWER -- so an overworld map is shot too, and
--                a flowerbed wearing paving is the failure being watched
--                for.
--
-- So the shots are the test. Per map: art off, art on. Plus one overworld
-- map that must be IDENTICAL in both, because the tileset gate should have
-- switched the whole feature off there.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/floor_art_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/floor_art_probe.log", "w"))
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

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end

  local FloorArt = lib.require("FloorArt")
  local Voxel3D = lib.require("Voxel3D")
  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local Pipelines = require("src.render.Pipelines")

  Weather.setting:sync("off")
  DayNight.setting:sync("day")

  local art = FloorArt.art()
  local aw, ah = 0, 0
  if art then aw, ah = art:getDimensions() end
  log(("asset: %dx%d scale=%d mix=%.2f yMax=%.1f")
      :format(aw, ah, FloorArt.scale(), FloorArt.mix(), FloorArt.Y_MAX))
  if not art then log("FAIL: assets/floor/floor.png did not load") end

  pcall(Pipelines.setLevel, "terrarium_voxel", 4)
  -- lampLights is written by VoxelScene.render, so it going non-nil says the
  -- 3D pass ran -- OUTDOORS. A passage has no street lamps, so the list stays
  -- nil there and this reports -1 on maps whose 3D pass is running perfectly
  -- well. Hence the flat settle after it: on an interior the -1 is expected
  -- and the wait is what actually buys the frame.
  local function wait3D(cap)
    for i = 1, (cap or 600) do
      if Voxel3D.lampLights ~= nil then return i end
      coroutine.yield()
    end
    return -1
  end
  wait(60); wait3D(600)

  for _, m in ipairs({
    { id = "UNDERGROUND_PATH_NORTH_SOUTH", x = 2, y = 6,  tag = "ns",
      want = true },
    { id = "UNDERGROUND_PATH_WEST_EAST",   x = 12, y = 2, tag = "we",
      want = true },
    -- the control: same colours live on the overworld sheet as FLOWERS, and
    -- the tileset gate is the only thing keeping them out
    { id = "FUCHSIA_CITY", x = 18, y = 20, tag = "control", want = false },
  }) do
    local ok = pcall(function()
      game.overworld:setMap(m.id, m.x, m.y, "down")
    end)
    if not ok then
      log("SKIP " .. m.id)
    else
      Voxel3D.lampLights = nil
      local up = wait3D(600)
      wait(200)
      local map = game.overworld and game.overworld.map
      local sheet = map and map.tileset and map.tileset.image or "?"
      local on = FloorArt.on()
      log(("[%s] 3D up=%s tileset=%s on=%d want=%s -> %s")
          :format(m.id, tostring(up), tostring(sheet), on, tostring(m.want),
                  ((on == 1) == m.want) and "PASS" or "FAIL"))

      -- and the corridor's own lighting: how many fittings the row put down,
      -- and whether the shader is actually being handed them
      local Underpass = lib.require("Underpass")
      local row = Underpass.matches(map) and Underpass.row(map) or {}
      local live = Voxel3D.lampLights or {}
      log(("[%s] lamps: row=%d sent=%d height=%s")
          :format(m.id, #row, #live, tostring(Voxel3D.lampHeight)))

      local keep = FloorArt.ART_MIX
      FloorArt.ART_MIX = 0.0; wait(20); shot(("floor_a_off_%s.png"):format(m.tag))
      FloorArt.ART_MIX = keep; wait(20); shot(("floor_b_on_%s.png"):format(m.tag))
      -- Lights off, art on: separates "the corridor got a shape" from "the
      -- corridor got a texture", which otherwise land in one picture.
      --
      -- Through Underpass.ENABLED, NOT by nilling Voxel3D.lampLights: render
      -- rewrites that list every frame, so the first version of this shot
      -- came back byte-identical to the one above it and said nothing.
      -- ENABLED is the WHOLE package -- the fittings AND the ambient dim
      -- they are meant to be seen against -- so this pair is "with lighting"
      -- against "without", not "lamps" against "no lamps". Naming it
      -- nolamp made the first reading of it wrong: the corridor came back
      -- half as bright with the feature on, which looked like the lamps
      -- failing and was actually the dim doing its job unaccompanied.
      Underpass.ENABLED = false; wait(20)
      shot(("floor_c_nolight_%s.png"):format(m.tag))
      Underpass.ENABLED = true; wait(20)
    end
  end

  logf:close()
  love.event.quit()
end
