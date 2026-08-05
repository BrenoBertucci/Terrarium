-- Probe: the snow, and nothing else.
--
-- The full ground probe walks the ecology tables, a shower, a drying, an
-- indoor check and a route's roamers before it ever reaches the snow -- which
-- is minutes of waiting to look at one constant. This pins the cover, takes
-- the pictures and quits.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/snow_shot.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/snow_shot.log", "w"))
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
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit() return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11; if n > 1500 then break end
  end

  local lib = game.mods.exports.TERRARIUM.lib
  local GroundFX = lib.require("GroundFX")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local Voxel3D = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")

  GroundFX.setting:sync("on")
  DayNight.setting:sync("day")
  Pipelines.setLevel("terrarium_voxel", 5)
  -- fast enough that the three steps are three short waits rather than a
  -- coffee break, and nothing else in the mod is asked to do anything
  GroundFX.SETTLE, GroundFX.MELT = 6, 4
  Weather.setting:sync("snow")

  -- a spot with buildings, hedges and open ground in one frame -- found, not
  -- written down
  game.overworld:setMap("VIRIDIAN_CITY", 5, 5, "down")
  wait(60)
  local m = game.overworld.map
  local bx, by, best = 10, 10, -1
  for cy = 2, (m.height or 20) - 3 do
    for cx = 2, (m.width or 20) - 3 do
      if m:isWalkableCell(cx, cy) and not m:isWaterCell(cx, cy) then
        local open, raised = 0, 0
        for dy = -3, 3 do for dx = -3, 3 do
          if m:inBounds(cx + dx, cy + dy) then
            if m:isWalkableCell(cx + dx, cy + dy) then open = open + 1
            else raised = raised + 1 end
          end
        end end
        -- both, so the shot shows the ground AND the things standing on it
        local score = math.min(open, raised * 2)
        if score > best then bx, by, best = cx, cy, score end
      end
    end
  end
  game.overworld:setMap("VIRIDIAN_CITY", bx, by, "up")
  wait(150)
  log(("standing at %d,%d"):format(bx, by))

  for _, want in ipairs({ 0, 1, 2, 3 }) do
    if want == 0 then
      Weather.setting:sync("off")
      local spun = 0
      while GroundFX.cover() > 0.02 and spun < 2000 do wait(20); spun = spun + 20 end
      Weather.setting:sync("snow")
    else
      local spun = 0
      while GroundFX.step(GroundFX.cover()) < want and spun < 3000 do
        wait(10); spun = spun + 10
      end
    end
    wait(30)
    log(("step %d: cover=%.2f  voxel tint=%.2f  decal draws=%d"):format(
      want, GroundFX.cover(), GroundFX.snowTint(game.overworld.map),
      GroundFX.lastDraws))
    shot(("6%d_snow_step%d.png"):format(want, want))
  end

  -- and the row still switches every bit of it off, tint included
  GroundFX.setting:sync("off")
  wait(30)
  log(("GROUND off: tint=%.2f draws=%d (want 0 / 0)"):format(
    GroundFX.snowTint(game.overworld.map), GroundFX.lastDraws))
  if GroundFX.snowTint(game.overworld.map) > 0 or GroundFX.lastDraws > 0 then
    log("  FAIL: the row does not switch the snow off")
  end
  shot("65_snow_ground_OFF.png")

  log("done")
  logf:close()
  love.event.quit()
end
