-- Probe: first Gold (Gen 2) boot with TERRARIUM marked gen2compat.
--
--   POKEPORT_VERSION=gold DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/gold_boot_probe.lua gen1recomp
--
-- Not a feature probe: the question is only "does the mod LOAD, and what
-- does the compat layer complain about".  Dumps the loader status, every
-- Logger line (the Gen2Compat facade warns through it), then turns the
-- voxel pipeline on and screenshots, so the first real render failure has
-- a picture attached.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/gold_boot.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end

  local Logger = require("src.core.Logger")
  local seen = 0
  local function drainLogger(tag)
    local h = Logger.history
    if #h > seen then
      for i = seen + 1, #h do log(tag, h[i]) end
      seen = #h
    end
  end

  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      local ok, err = pcall(function()
        local fd = data:encode("png")
        local f = assert(io.open(OUT .. "/" .. name, "wb"))
        f:write(fd:getString()); f:close()
      end)
      if not ok then log("shot FAIL", name, tostring(err)) end
      done = true
    end)
    local n = 0
    while not done and n < 120 do wait(1); n = n + 1 end
    log("shot", name, done and "ok" or "TIMEOUT")
  end

  local GameVersion = require("src.core.GameVersion")
  local Version = require("src.core.Version")
  log("engine", Version.engine, "game", GameVersion.get(),
      "generation", GameVersion.generation())

  -- world up?
  local n = 0
  while not (game.world and game.world.map) do
    wait(1); n = n + 1
    drainLogger("[boot]")
    if n > 3600 then
      log("FAIL: no world after 3600 frames")
      drainLogger("[end]")
      logf:close(); love.event.quit(); return
    end
  end
  log("world up after", n, "frames; map =", tostring(game.world.map.id))
  drainLogger("[boot]")

  -- mod status
  local status = game.modStatus or (game.mods and game.mods.status
    and game.mods:status())
  if status then
    for _, m in ipairs(status.available or {}) do
      log(("mod %s state=%s enabled=%s note=%s error=%s"):format(
        tostring(m.id), tostring(m.state), tostring(m.enabled),
        tostring(m.note), tostring(m.error)))
    end
    for i, e in ipairs(status.errors or {}) do log("loader error", i, e) end
  else
    log("no modStatus")
  end

  local exports = game.mods and game.mods.exports
  local T = exports and exports.TERRARIUM
  log("TERRARIUM exports:", T and "present" or "ABSENT")

  wait(60)
  shot("gold_before.png")
  drainLogger("[idle]")

  -- voxel pipeline on
  local Pipelines = require("src.render.Pipelines")
  local ok, err = pcall(function()
    local max = Pipelines.maxLevel and Pipelines.maxLevel("terrarium_voxel")
    log("terrarium_voxel maxLevel =", tostring(max))
    Pipelines.setLevel("terrarium_voxel", max or 1)
  end)
  if not ok then log("setLevel FAIL:", tostring(err)) end
  wait(240)
  drainLogger("[voxel]")
  shot("gold_voxel.png")

  -- a few steps so movement / npc / weather code paths run
  local input = game.input
  if input and input.pressQueue then
    for _ = 1, 6 do
      input.pressQueue[#input.pressQueue + 1] = "down"
      wait(20)
    end
    log("walked 6 taps")
  else
    log("no input.pressQueue; skipped walking")
  end
  wait(120)
  drainLogger("[walk]")
  shot("gold_walk.png")

  drainLogger("[end]")
  log("done")
  logf:close()
  love.event.quit()
end
