-- What the painted ground (lib/LavenderGroundKit.lua) costs a frame in the
-- heaviest of the new worlds -- Viridian with its three roads in view, and
-- Cerulean -- the kit off, on, on, off: a palindrome, so warm-up and heat
-- charge both sides alike. Off, the drawn tiles lie flat as they always did.
-- Vsync off, the mesher's queue drained first, 400 steps a condition.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/ground_cost_probe.log", "w"))
  local function log(s) file:write(s, "\n"); file:flush() end
  for _ = 1, 1200 do
    if game.overworld and game.stack and game.stack:top() == game.overworld then break end
    if game.input then game.input.pressQueue[#game.input.pressQueue + 1] = "a" end
    coroutine.yield()
  end
  if not game.overworld then log("FAIL no overworld"); file:close(); love.event.quit(); return end
  local lib = game.mods.exports.TERRARIUM.lib
  local Structures, Cam = lib.require("Structures"), lib.require("MarioCam")
  local Voxel = lib.require("Voxel3D")
  require("src.render.Pipelines").setLevel("terrarium_voxel", 4)
  require("src.render.Pipelines").setLevel("terrarium_tiltshift", 0)
  lib.require("AutoFarm").setting:sync("off")
  lib.require("Weather").setting:sync("off")
  lib.require("DayNight").setting:sync("day")
  Cam.setting:sync("on")
  local function settle(n)
    for _ = 1, n do
      for _, d in ipairs({ "up", "down", "left", "right" }) do
        game.input.state[d] = false
        if game.input.sources then game.input.sources[d] = nil end
      end
      game.input.pressQueue = {}
      coroutine.yield()
    end
  end
  local function enter(mapId, cx, cy)
    Voxel.lampLights = nil
    game.overworld:setMap(mapId, cx, cy, "down")
    for _ = 1, 20000 do
      if Structures.peek(game.overworld.map) and Voxel.lampLights then break end
      settle(1)
    end
    settle(300)
  end
  local Kit, Mesher = lib.require("LavenderGroundKit"), lib.require("ChunkMesher")
  local function measure(mapId, cx, cy, enabled)
    Kit.ENABLED = enabled
    Mesher.invalidate()
    enter(mapId, cx, cy)
    -- every build queued (this map, its neighbours) done before a frame is timed
    local waited = 0
    while Mesher.pending() > 0 and waited < 30000 do settle(1); waited = waited + 1 end
    settle(600)
    local quads = 0
    for _, q in ipairs(Structures.forMap(game.overworld.map).spriteQuads or {}) do
      if q.tex and q.tex:find("ground_", 1, true) then quads = quads + 1 end
    end
    love.window.setVSync(0)
    local t, n = {}, 400
    for i = 1, n do
      local a = love.timer.getTime()
      settle(1)
      t[i] = (love.timer.getTime() - a) * 1000
    end
    love.window.setVSync(1)
    local sum = 0
    for i = 1, n do sum = sum + t[i] end
    table.sort(t)
    log(("%-13s ground %s  mean %.2f  p50 %.2f  p95 %.2f  max %.2f ms  (%d ground quads, waited %d)"):format(
      mapId, enabled and "ON " or "OFF", sum / n, t[n / 2], t[math.floor(n * 0.95)], t[n], quads, waited))
  end
  for _, where in ipairs({ { "VIRIDIAN_CITY", 19, 12 }, { "CERULEAN_CITY", 20, 19 } }) do
    measure(where[1], where[2], where[3], false)
    measure(where[1], where[2], where[3], true)
    measure(where[1], where[2], where[3], true)
    measure(where[1], where[2], where[3], false)
  end
  Kit.ENABLED = nil
  file:close()
  love.event.quit()
end
