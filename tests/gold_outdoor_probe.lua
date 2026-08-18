-- Probe: TERRARIUM's voxel pass on a Gold OUTDOOR map.
--
--   POKEPORT_VERSION=gold DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/gold_outdoor_probe.lua gen1recomp
--
-- Warps to New Bark Town, turns the voxel pipeline to max, lets the bake
-- settle, and screenshots.  Every Logger line is drained around each move
-- so a facade warning lands beside the step that provoked it.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/gold_outdoor.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end

  local Logger = require("src.core.Logger")
  local seen = 0
  local function drain(tag)
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

  local n = 0
  while not (game.world and game.world.map) do
    wait(1); n = n + 1
    if n > 3600 then log("FAIL: no world"); logf:close(); love.event.quit(); return end
  end
  drain("[boot]")

  -- outside, into the town the intro house sits in
  local ok, err = pcall(function()
    game.world:setMap("NEW_BARK_TOWN", 8, 8, "down")
  end)
  log("setMap NEW_BARK_TOWN:", ok and "ok" or ("FAIL " .. tostring(err)))
  wait(120)
  drain("[warp]")
  shot("outdoor_2d.png")

  local Pipelines = require("src.render.Pipelines")
  local okL, errL = pcall(function()
    Pipelines.setLevel("terrarium_voxel",
      Pipelines.maxLevel and Pipelines.maxLevel("terrarium_voxel") or 1)
  end)
  if not okL then log("setLevel FAIL:", tostring(errL)) end
  -- the bake walks the map over frames; give it a while on this hardware
  for i = 1, 6 do
    wait(120)
    drain("[voxel" .. i .. "]")
  end
  shot("outdoor_voxel.png")

  -- walk a little so crush / npc / weather paths run outdoors
  local input = game.input
  if input and input.pressQueue then
    for _ = 1, 4 do input.pressQueue[#input.pressQueue + 1] = "down"; wait(24) end
    for _ = 1, 4 do input.pressQueue[#input.pressQueue + 1] = "left"; wait(24) end
  end
  drain("[walk]")
  shot("outdoor_walk.png")

  -- and the tiltshift present pass on top
  local okT, errT = pcall(function()
    Pipelines.setLevel("terrarium_tiltshift",
      Pipelines.maxLevel and Pipelines.maxLevel("terrarium_tiltshift") or 1)
  end)
  if not okT then log("tilt setLevel FAIL:", tostring(errT)) end
  wait(120)
  drain("[tilt]")
  shot("outdoor_tilt.png")

  drain("[end]")
  log("done")
  logf:close()
  love.event.quit()
end
