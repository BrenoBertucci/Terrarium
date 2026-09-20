-- Render the real exteriors with temporary cameras; verify selection and
-- map isolation. Settings are synced in memory, never saved by this probe.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local file = assert(io.open(out .. "/lavender_houses_probe.log", "w"))
  local function log(s) file:write(s, "\n"); file:flush() end
  local function wait(n) for _=1,n do coroutine.yield() end end
  local failures = 0
  local function check(ok, message)
    log((ok and "PASS " or "FAIL ") .. message)
    if not ok then failures = failures + 1 end
  end
  for _=1,1200 do
    if game.overworld and game.stack and game.stack:top() == game.overworld then break end
    if game.input then game.input.pressQueue[#game.input.pressQueue+1] = "a" end
    wait(1)
  end
  if not game.overworld then log("FAIL no overworld"); file:close(); love.event.quit(); return end
  local lib = game.mods.exports.TERRARIUM.lib
  local Buildings, Structures = lib.require("Buildings"), lib.require("Structures")
  local Cam, Voxel = lib.require("MarioCam"), lib.require("Voxel3D")
  local Day = lib.require("DayNight")
  require("src.render.Pipelines").setLevel("terrarium_voxel", 4)
  require("src.render.Pipelines").setLevel("terrarium_tiltshift", 0)
  lib.require("Weather").setting:sync("off")
  lib.require("AutoFarm").setting:sync("off")
  Day.setting:sync("day")
  Cam.setting:sync("off") -- fixed inspection camera; keep orbit culling
  local camera, originalCamera = nil, Cam.camera
  Cam.camera = function() return camera or originalCamera() end
  local function release()
    for _, d in ipairs({"up","down","left","right"}) do
      game.input.state[d] = false
      if game.input.sources then game.input.sources[d] = nil end
    end
    game.input.pressQueue = {}
  end
  local function settle(n)
    for _=1,n do release(); coroutine.yield() end
  end
  game.overworld:setMap("LAVENDER_TOWN", 10, 16, "down")
  for _=1,1800 do
    local count=0
    for key in pairs(Buildings.stats()) do if key:find("@lavender:",1,true) then count=count+1 end end
    if count==3 and Voxel.lampLights then break end
    settle(1)
  end
  settle(180)
  log("map id=" .. tostring(game.overworld.map.id) .. " name=" .. tostring(game.overworld.map.def.id))
  local count=0
  for key, st in pairs(Buildings.stats()) do
    if key:find("@lavender:",1,true) then
      count=count+1
      log(key .. " voxels=" .. st.voxels .. " quads=" .. st.quads)
    end
  end
  check(count==3, "three Lavender models built")
  check(not Buildings.lastError, "building error=" .. tostring(Buildings.lastError))
  check(Voxel.shader() ~= nil and not Voxel.shaderError, "voxel shader compiled")
  local map = game.overworld.map
  local S = Structures.forMap(map)
  local quads=0
  for _, q in ipairs(S.spriteQuads or {}) do
    if q.tex == "assets/buildings/lavender_materials.png" then quads=quads+1 end
  end
  check(quads > 10000, "authored material meshes stamped: " .. quads)
  for _, cell in ipairs({{6,8},{2,12},{6,12}}) do
    check(Buildings.tallAt(map,cell[1],cell[2]) >= 50, "camera height at " .. cell[1] .. "," .. cell[2])
  end
  local function shot(name, eye, focus, hour)
    Day.setting:sync(hour or "day")
    camera={eye=eye,focus=focus,fov=math.rad(55),curve=0}
    settle(150)
    local pending=true
    love.graphics.captureScreenshot(function(data)
      local f=assert(io.open(out .. "/" .. name .. ".png","wb"))
      f:write(data:encode("png"):getString()); f:close(); pending=false
    end)
    for _=1,120 do if not pending then break end; settle(1) end
    check(not pending, "captured " .. name)
  end
  shot("fuji_day", {193,85,210}, {126,23,144})
  shot("cubone_day", {14,82,290}, {65,22,209})
  shot("name_rater_day", {195,88,288}, {128,23,209})
  shot("fuji_rear", {181,83,84}, {128,23,144})
  shot("lavender_overview", {256,193,364}, {106,22,175})
  shot("fuji_dusk", {193,85,210}, {126,23,144}, "dusk")
  shot("fuji_night", {193,85,210}, {126,23,144}, "night")
  camera=nil
  Day.setting:sync("day")
  Cam.setting:sync("off") -- compass input for the real door/warp check
  for _, door in ipairs({{7,10,"MR_FUJIS_HOUSE"},
                         {3,14,"LAVENDER_CUBONE_HOUSE"},
                         {7,14,"NAME_RATERS_HOUSE"}}) do
    game.overworld:setMap("LAVENDER_TOWN",door[1],door[2],"up")
    settle(100)
    game.overworld:setMap("LAVENDER_TOWN",door[1],door[2],"up")
    release()
    for _=1,240 do
      if game.overworld.map.def.id ~= "LAVENDER_TOWN" then break end
      game.input.pressQueue[#game.input.pressQueue+1]="up"
      coroutine.yield()
    end
    release()
    check(game.overworld.map.def.id == door[3], "walk through door into " .. door[3])
  end
  game.overworld:setMap("FUCHSIA_CITY", 10, 25, "down")
  settle(300)
  local other=Structures.forMap(game.overworld.map)
  local leaked=false
  for _,q in ipairs(other.spriteQuads or {}) do
    if q.tex == "assets/buildings/lavender_materials.png" then leaked=true end
  end
  check(not leaked, "Fuchsia retains its original houses")
  Cam.camera=originalCamera
  log("RESULT " .. (failures==0 and "PASS" or (failures .. " failures")))
  file:close()
  love.event.quit()
end
