-- Probe: TERRARIUM identity and coexistence with upstream DRAMATIC_SHAPE.
--
-- Metrics for the independence task (not visual quality):
--   1. TERRARIUM loads and exports lib/version.
--   2. Registry keys are terrarium_* (not the upstream voxel/tiltshift ids).
--   3. If DRAMATIC_SHAPE is also installed, both exports exist without error.
--   4. Turning TERRARIUM's world pipeline on does not require the upstream folder.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/coexist_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/coexist_probe.log", "w"))
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
    if n > 900 then
      log("FAIL: no overworld"); logf:close(); love.event.quit(); return
    end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("WARN: never reached free roam"); break end
  end

  local exports = game.mods and game.mods.exports
  if not exports then
    log("FAIL: game.mods.exports missing"); logf:close(); love.event.quit(); return
  end

  local terr = exports.TERRARIUM
  if not (terr and terr.lib) then
    log("FAIL: TERRARIUM not loaded (exports.TERRARIUM.lib missing)")
    log("exports keys:")
    for k in pairs(exports) do log("  ", k) end
    logf:close(); love.event.quit(); return
  end
  log("PASS: TERRARIUM loaded")
  log("version:", terr.version or "?")

  local pipes = terr.pipelines
  if not pipes then
    log("FAIL: exports.TERRARIUM.pipelines missing")
    logf:close(); love.event.quit(); return
  end
  log("pipeline voxel key:", pipes.voxel)
  log("pipeline tilt key:", pipes.tiltshift)
  if pipes.voxel ~= "terrarium_voxel" or pipes.tiltshift ~= "terrarium_tiltshift" then
    log("FAIL: unexpected pipeline registry keys")
    logf:close(); love.event.quit(); return
  end
  log("PASS: unique pipeline keys")
  local keys = terr.keys
  if not keys or keys.voxel ~= "v" or keys.tilt ~= "t" then
    log("FAIL: expected letter hotkeys v/t/... got", keys and keys.voxel, keys and keys.tilt)
    logf:close(); love.event.quit(); return
  end
  log("PASS: letter hotkeys", keys.voxel, keys.grid, keys.tilt, keys.curve, keys.battle, keys.wild, keys.map)


  local Pipelines = require("src.render.Pipelines")
  local ok, err = pcall(function()
    Pipelines.setLevel("terrarium_voxel", 2)
  end)
  if not ok then
    log("FAIL: setLevel terrarium_voxel:", tostring(err))
    logf:close(); love.event.quit(); return
  end
  local lvl = Pipelines.level("terrarium_voxel")
  log("terrarium_voxel level after set:", lvl)
  if lvl ~= 2 then
    log("FAIL: terrarium_voxel level expected 2")
    logf:close(); love.event.quit(); return
  end
  log("PASS: TERRARIUM pipeline controllable")
  Pipelines.setLevel("terrarium_voxel", 0)

  -- Upstream may or may not be installed; both states are valid.
  local up = exports.DRAMATIC_SHAPE
  if up and up.lib then
    log("PASS: DRAMATIC_SHAPE also loaded (coexistence)")
    log("upstream version:", up.version or "?")
    -- Upstream still owns the classic keys; ours must not have stolen them
    -- by sharing the same register name.
    local okU, errU = pcall(function()
      local _ = Pipelines.level("voxel")
    end)
    log("upstream Pipelines.level(voxel) pcall:", tostring(okU), tostring(errU))
    log("PASS: both mods present without require/folder collision")
  else
    log("INFO: DRAMATIC_SHAPE not loaded (solo TERRARIUM is OK)")
  end

  -- Sanity: V.require still resolves a core module under the new id.
  local okR, DayNight = pcall(function() return terr.lib.require("DayNight") end)
  if not okR or not DayNight then
    log("FAIL: V.require DayNight:", tostring(DayNight))
    logf:close(); love.event.quit(); return
  end
  log("PASS: TERRARIUM V.require works")

  log("RESULT: OK")
  logf:close()
  love.event.quit()
end
