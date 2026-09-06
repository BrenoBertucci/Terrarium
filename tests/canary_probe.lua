-- Probe: the culling-box canary from mariocam_probe, alone and talkative.
-- Parks on ROUTE_17, turns the camera a half turn (looking SOUTH down a
-- 2300-pixel-tall map), and lists EVERY chunk the yaw-aware box culls that
-- is within reach and projects -- once against the giant virtual viewport
-- the canary uses, once against the real one -- with where it stands
-- relative to the eye, so a "hole" behind the camera can be told from one
-- on the screen.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/canary_probe.log", "w"))
  local function log(s) logf:write(s, "\n"); logf:flush() end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit() return end
  end
  while game.stack:top() ~= game.overworld do tap("a"); wait(10) end

  local lib = game.mods.exports.TERRARIUM.lib
  local MarioCam = lib.require("MarioCam")
  local VoxelScene = lib.require("VoxelScene")
  local ShadowMap = lib.require("ShadowMap")
  local Voxel3D = lib.require("Voxel3D")
  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local MiniMap = lib.require("MiniMap")
  local AutoFarm = lib.require("AutoFarm")
  local Pipelines = require("src.render.Pipelines")
  Pipelines.setLevel("terrarium_voxel", 4)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  MiniMap.setting:setIndex(3, game)
  Weather.setting:setIndex(2, game)
  AutoFarm.setting:setIndex(1, game)

  local CLOCK = 300
  local function hold(frames)
    for _ = 1, frames do DayNight.clock = CLOCK; coroutine.yield() end
  end
  local function releaseDirs()
    local st = game.input.state
    for _, d in ipairs({ "up", "down", "left", "right" }) do
      st[d] = false
      if game.input.sources then game.input.sources[d] = nil end
    end
    game.input.pressQueue = {}
  end

  local function onScreen(ch, W, H)
    for _, x in ipairs({ ch.x0, ch.x1 }) do
      for _, y in ipairs({ 0, ch.ymax or 0 }) do
        for _, z in ipairs({ ch.z0, ch.z1 }) do
          local px, py = Voxel3D.project(x, y, z)
          if px and px >= 0 and px <= W and py >= 0 and py <= H then
            return true
          end
        end
      end
    end
    return false
  end
  local function nearestTo(ch, x, z)
    local dx = math.max(ch.x0 - x, 0, x - ch.x1)
    local dz = math.max(ch.z0 - z, 0, z - ch.z1)
    return math.sqrt(dx * dx + dz * dz)
  end
  local function kept(ch, b)
    return ch.x1 >= b[1] and ch.x0 <= b[3]
           and ch.z1 + (ch.ymax or 0) >= b[2] and ch.z0 <= b[4]
  end

  MarioCam.setting:setIndex(2, game)
  game.overworld:setMap("ROUTE_17", 9, 60, "up")
  hold(300)
  releaseDirs()
  MarioCam.recenter()
  for _ = 1, 2 do game:keypressed("e") hold(90) end
  hold(150)
  local p = game.overworld.player
  local yaw = math.deg(MarioCam.viewYaw())
  local lk = MarioCam.lakitu
  log(("player cell (%d,%d) at (%.0f,%.0f); viewYaw %.1f; eye (%.0f,%.0f,%.0f) focus (%.0f,%.0f,%.0f); lift %.1f pull %.2f")
      :format(math.floor((p.px + 8) / 16), math.floor((p.py + 8) / 16), p.px, p.py, yaw,
              lk.curPos[1], lk.curPos[2], lk.curPos[3],
              lk.curFocus[1], lk.curFocus[2], lk.curFocus[3],
              MarioCam.pullState.lift, MarioCam.pullState.t))

  local terrain = select(1, VoxelScene.prefetch(game.overworld))
  local lv = VoxelScene.lastView
  local W, H = love.graphics.getDimensions()
  local reach = ShadowMap.groundReach(lv[4], VoxelScene.FAR_CAP)
  local b = VoxelScene.bounds(lv[1], lv[2], lv[3], lv[4], false)
  log(("lastView centre (%.0f,%.0f) vw %.0f vh %.0f; reach %.0f; box x[%.0f..%.0f] z[%.0f..%.0f]; real viewport %dx%d")
      :format(lv[1], lv[2], lv[3], lv[4], reach, b[1], b[3], b[2], b[4], W, H))
  for _, vp in ipairs({ { 4096, 4096, "virtual 4096" }, { W, H, "real" } }) do
    local seen, holes = 0, 0
    for _, ch in ipairs(terrain.chunks or {}) do
      if onScreen(ch, vp[1], vp[2]) and nearestTo(ch, lv[1], lv[2]) <= reach then
        seen = seen + 1
        if not kept(ch, b) then
          holes = holes + 1
          local corners = {}
          for _, x in ipairs({ ch.x0, ch.x1 }) do
            for _, z in ipairs({ ch.z0, ch.z1 }) do
              local px, py = Voxel3D.project(x, 0, z)
              corners[#corners + 1] = px and ("(%.0f,%.0f)"):format(px, py) or "nil"
            end
          end
          log(("  %s HOLE: chunk x[%.0f..%.0f] z[%.0f..%.0f] ymax %.0f; %.0f px from the view centre; "
               .. "eye is at z %.0f (chunk is %s of the eye); ground corners project to %s")
              :format(vp[3], ch.x0, ch.x1, ch.z0, ch.z1, ch.ymax or 0,
                      nearestTo(ch, lv[1], lv[2]), lk.curPos[3],
                      (ch.z1 < lk.curPos[3]) and "NORTH (behind)" or "south (in front)",
                      table.concat(corners, " ")))
        end
      end
    end
    log(("%s viewport: %d chunks on screen and within reach, %d culled by the yaw-aware box")
        :format(vp[3], seen, holes))
  end
  logf:close()
  love.event.quit()
end
