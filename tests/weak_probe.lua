-- Does this machine read as a weak GPU, and did the three gates move?
--
-- lib/Device.weak() was added because Device.mobile() answers false on an
-- integrated desktop part, and three defaults were reading mobile() as if it
-- meant "can this GPU afford the extras". This prints what the gates now
-- decide, on whatever machine it is run on.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/weak_probe.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
    logf:write(table.concat(p, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    game.input.pressQueue[#game.input.pressQueue + 1] = "a"
    wait(10); n = n + 11
    if n > 1500 then break end
  end
  local lib = game.mods and game.mods.exports
              and game.mods.exports.TERRARIUM and game.mods.exports.TERRARIUM.lib
  if not lib then log("FAIL: not loaded"); logf:close(); love.event.quit(); return end

  local Device = lib.require("Device")
  local RayFX  = lib.require("RayFX")
  local Pipelines = require("src.render.Pipelines")

  log("gpu:      ", Device.describe())
  log("all:      ", Device.info().all)
  log("mobile(): ", tostring(Device.mobile()))
  log("weak():   ", tostring(Device.weak()))
  log("")
  log("SCREEN FX row value:  ", tostring(RayFX.setting:get()))
  log("SCREEN FX resolves to:", tostring(RayFX.level and RayFX.level() or "?"))
  log("T-SHIFT level:        ", tostring(Pipelines.level("terrarium_tiltshift")))
  log("T-SHIFT max:          ", tostring(Pipelines.maxLevel("terrarium_tiltshift")))
  log("")
  log("done")
  logf:close()
  love.event.quit()
end
