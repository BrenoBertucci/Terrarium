-- Probe: is the air behind the building actually behind it now?
--
-- The complaint T3 exists to answer was not a guess -- it was written into
-- the code. main.lua paints the wind and the weather inside
-- Voxel3D.beginOverlay, and that call sets no depth mode at all, so every
-- mote crossed in front of the mountain and blew through every roof.
--
-- ------- WHY THIS IS ONE MOTE AND NOT A FIELD
--
-- The first version of this probe tried to isolate the field statistically
-- by subtracting a WIND OFF frame. WIND OFF also stops the GRASS, so the
-- difference it measured was a meadow bending, and 95% of the frame came
-- back "lit". Statistics cannot separate a hundred random motes from a
-- moving world.
--
-- So: WindFX.HOLD freezes the field, WindFX.pinOne parks exactly one
-- magenta mote where this probe wants it, and WindFX.WORLD_PASS switches
-- between the overlay paint and the scene-pass geometry in the same build.
-- Magenta because Pallet Town is greens, greys and red roofs, and nothing
-- in a Game Boy palette is red and blue at once -- so a pixel with r and b
-- high and g low is the fixture and can be nothing else.
--
-- Two placements, four frames:
--
--   INSIDE a house, below its roof line. Overlay must SHOW it (that is the
--   bug). The scene pass must HIDE it (that is the fix).
--
--   OUT in the open, over grass. Both must show it -- otherwise the scene
--   pass is not occluding, it is simply failing to draw.
--
-- The second placement is what stops a broken draw from reading as a
-- successful occlusion, which is the one way this measurement could lie.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/particles_occlusion_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/particles_occlusion.log", "w"))
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
    coroutine.yield(); coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit() return end
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

  local WindFX   = lib.require("WindFX")
  local Wind     = lib.require("Wind")
  local Weather  = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Quality  = lib.require("Quality")
  local Pipelines = require("src.render.Pipelines")

  Weather.setting:sync("off")
  DayNight.setting:sync("day")
  Wind.setting:sync(2)              -- BREEZE: the gate wants wind above FLOOR
  Quality.setting:sync(1)
  Pipelines.setLevel("terrarium_voxel", 4)

  local CELL_X, CELL_Y = 12, 12
  local ow = game.overworld
  ow:setMap("PALLET_TOWN", CELL_X, CELL_Y, "up")
  wait(600)
  local p = ow.player
  log(("map %s  player %d,%d"):format(ow.map.id, p.cellX, p.cellY))

  -- ------- FIND A ROOF
  --
  -- The tallest column within reach, which in a town is a house. Its own
  -- ground height against the player's is how far below its roof line a
  -- mote has to sit to be genuinely inside it.
  local pgx, pgz = p.cellX * 16 + 8, p.cellY * 16 + 8
  local pg = WindFX.groundAt(pgx, pgz)
  local bx, bz, bg = nil, nil, -1e9
  for dx = -6, 6 do
    for dy = -8, 2 do
      local wx, wz = (p.cellX + dx) * 16 + 8, (p.cellY + dy) * 16 + 8
      local g = WindFX.groundAt(wx, wz)
      if g > bg then bg, bx, bz = g, wx, wz end
    end
  end
  log(("player ground %.1f | tallest column at %.0f,%.0f ground %.1f (%+.1f)")
      :format(pg, bx or -1, bz or -1, bg, bg - pg))
  if not bx or (bg - pg) < 8 then
    log("FAIL: no column tall enough to hide anything -- nothing to test")
    logf:close(); love.event.quit(); return
  end

  -- ------- OPEN GROUND, for the control
  --
  -- The lowest column in the same sweep: whatever the town's floor is.
  local ox, oz, og = nil, nil, 1e9
  for dx = -6, 6 do
    for dy = -2, 6 do
      local wx, wz = (p.cellX + dx) * 16 + 8, (p.cellY + dy) * 16 + 8
      local g = WindFX.groundAt(wx, wz)
      if g < og then og, ox, oz = g, wx, wz end
    end
  end
  log(("open ground at %.0f,%.0f height %.1f"):format(ox, oz, og))

  WindFX.HOLD = true

  local function place(tag, x, y, z)
    local okp = WindFX.pinOne("puff", x, y, z, 9)
    wait(30)
    log(("  %-18s pinned=%s motes=%d y=%.1f")
        :format(tag, tostring(okp), WindFX.count(), y))
  end

  -- ------- INSIDE the house: halfway up from the town floor to its roof
  local insideY = pg + (bg - pg) * 0.5
  WindFX.WORLD_PASS = false
  place("inside/overlay", bx, insideY, bz)
  shot("occl_inside_overlay.png")

  WindFX.WORLD_PASS = true
  place("inside/world", bx, insideY, bz)
  wait(20)
  log(("    scene-pass batches drawn: %d"):format(WindFX.lastBatches))
  shot("occl_inside_world.png")

  -- ------- OUT IN THE OPEN: the control that must survive both
  local openY = og + 10
  WindFX.WORLD_PASS = false
  place("open/overlay", ox, openY, oz)
  shot("occl_open_overlay.png")

  WindFX.WORLD_PASS = true
  place("open/world", ox, openY, oz)
  wait(20)
  log(("    scene-pass batches drawn: %d"):format(WindFX.lastBatches))
  shot("occl_open_world.png")

  -- ------- AND THE WHOLE FIELD, WHICH ONE MOTE CANNOT SPEAK FOR
  --
  -- The fixture above proves the depth test arrived. It says nothing about
  -- whether a HUNDRED motes still look like weather -- the geometry path
  -- changed how a mote is sized (world units, not screen pixels) and how
  -- it is oriented (a card leaned by the camera's pitch, not a rotated
  -- 2D sprite), and either could be wrong in a way a single parked puff
  -- would never show.
  -- A pinned mote is never culled -- that is the whole point of pinning --
  -- so releasing HOLD is not enough: the fixture would ride along into the
  -- frames below and sit there as a magenta blob. Clear the field first.
  WindFX.HOLD = false
  WindFX.clear()
  Wind.setting:sync(4)                    -- GALE: the densest field there is
  ow:setMap("PALLET_TOWN", CELL_X, CELL_Y, "up")
  wait(300)

  WindFX.WORLD_PASS = false
  wait(240)
  log(("  full field / overlay: motes %d"):format(WindFX.count()))
  shot("occl_field_overlay.png")

  WindFX.WORLD_PASS = true
  wait(240)
  log(("  full field / world:   motes %d  batches %d")
      :format(WindFX.count(), WindFX.lastBatches))
  shot("occl_field_world.png")

  log("done")
  logf:close()
  love.event.quit()
end
