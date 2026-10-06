-- Probe: does the 3D pass survive the probe's own setting switches?
-- (perf_attribution_probe saw VoxelScene.render stop being called after it
-- flipped SCREEN FX / RES, with nothing in errors.lua.) Counts render calls
-- per 60 frames and shoots after each switch.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/perf_switch.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b) game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield() end
  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      done = true
    end)
    local g = 0
    while not done and g < 240 do coroutine.yield(); g = g + 1 end
  end
  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do wait(1); n = n + 1; if n > 900 then break end end
  n = 0
  while game.stack:top() ~= game.overworld do tap("a"); wait(10); n = n + 11; if n > 1500 then break end end
  local lib = game.mods.exports.TERRARIUM.lib
  local RayFX, Quality, Voxel3D, VoxelScene = lib.require("RayFX"), lib.require("Quality"), lib.require("Voxel3D"), lib.require("VoxelScene")
  local Pipelines = require("src.render.Pipelines")
  local Runtime = package.loaded["src.mods.Runtime"] or package.loaded["src.core.Runtime"]
  local calls, nils = 0, 0
  local inner = VoxelScene.render
  VoxelScene.render = function(...)
    calls = calls + 1
    local c = inner(...)
    if not c then nils = nils + 1 end
    return c
  end
  local function sync(s, v) pcall(s.sync, s, v) end
  local p = game.overworld.player
  p.surfing = true
  pcall(function() game.overworld:setMap("ROUTE_21", 8, 14, "down") end)
  p.surfing = true
  wait(600)
  local function probe(tag)
    calls, nils = 0, 0
    wait(60)
    log(("%-14s render calls %d (nil %d) level=%s FX=%s RES=%s shaderErr=%s"):format(tag, calls, nils,
      tostring(Pipelines.level("terrarium_voxel")), tostring(RayFX.setting:get()),
      tostring(Quality.setting:get()), tostring(Voxel3D.shaderError)))
    shot("sw_" .. tag .. ".png")
  end
  local fx0, res0 = RayFX.setting:get(), Quality.setting:get()
  probe("start")
  sync(RayFX.setting, "off"); probe("fx_off")
  sync(RayFX.setting, fx0); probe("fx_back")
  sync(Quality.setting, 2); probe("res_half")
  sync(Quality.setting, res0); probe("res_back")
  -- what the engine thinks of the pipeline
  local okB, broken = pcall(function() return Pipelines.broken or Pipelines._broken end)
  log("pipelines.broken", tostring(okB and broken))
  if type(broken) == "table" then for k, v in pairs(broken) do log("  broken", tostring(k), tostring(v)) end end
  if Runtime and Runtime.errors then
    for i, e in ipairs(Runtime.errors) do log("runtime error", i, tostring(e.message or e.msg or e)) end
  end
  logf:close()
  love.event.quit()
end
