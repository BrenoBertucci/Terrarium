-- Probe: the GLOW row and the follower, in the places they were built for.
--
-- The output that matters is the screenshots; the log carries what a
-- picture cannot settle -- whether the follower spawned and where, whether
-- the palette's darkness was handed to the light (darkWorld false while the
-- engine still says ow.dark), how many lights the field drew and what the
-- masks cost to build.
--
-- The party is edited IN MEMORY for the length of the run (lead swapped to
-- a Charmander, Yellow's own Pikachu put in its ball so this mod's follower
-- is the one out). Nothing here saves.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/glow_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/glow_probe.log", "w"))
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
    local done = false
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      done = true
    end)
    local guard = 0
    while not done and guard < 240 do coroutine.yield(); guard = guard + 1 end
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
  game.input:reset()

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end
  log("version:", exports.TERRARIUM.version)

  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local ChunkMesher = lib.require("ChunkMesher")
  local Glow = lib.require("Glow")
  local Follower = lib.require("Follower")
  local Voxel3D = lib.require("Voxel3D")
  local Pipelines = require("src.render.Pipelines")
  local PaletteFX = require("src.render.PaletteFX")
  Weather.setting:sync("off")
  Pipelines.setLevel("terrarium_voxel", 4)
  Glow.setting:sync(true)
  Follower.setting:sync(true)

  local save = game.save
  local party = save.party or {}
  local oldLead = party[1] and party[1].species
  if party[1] then party[1].species = "CHARMANDER" end
  save.pikachuInBall = true

  local ow = game.overworld
  local function settle()
    local quiet, guard = 0, 0
    while quiet < 45 and guard < 2400 do
      coroutine.yield(); guard = guard + 1
      if ChunkMesher.pending() == 0 then quiet = quiet + 1 else quiet = 0 end
    end
    game.input:reset()
    wait(30)
  end
  local function walk(dir, frames)
    for _ = 1, frames do game.input.state[dir] = true; coroutine.yield() end
    game.input.state[dir] = false
    game.input:reset()
  end
  local function report(tag)
    local f = Follower.current()
    local pika = nil
    for _, e in ipairs(ow.npcs or {}) do if e.pikachuFollower then pika = e end end
    local st = Glow.stats
    log(("%s map=%s player=%d,%d follower=%s pika=%s dark=%s darkWorld=%s owns=%s "
         .. "glowLive=%s refused=%s field=%s sources=%d built=%d buildMs=%.2f")
        :format(tag, ow.map.id, ow.player.cellX, ow.player.cellY,
                f and (f.species .. "@" .. f.cellX .. "," .. f.cellY) or "none",
                pika and (pika.cellX .. "," .. pika.cellY) or "none",
                tostring(ow.dark), tostring(PaletteFX.darkWorld()),
                tostring(Glow.ownsDark), tostring(Voxel3D.glowLive),
                tostring(Voxel3D.glowRefused), tostring(Voxel3D.glow ~= nil),
                st.sources or 0, st.built or 0, st.buildMs or 0))
  end
  local function visit(mapId, cx, cy, facing)
    ow:setMap(mapId, cx, cy, facing or "down")
    settle()
  end
  local function sources(tag)
    for i, s in ipairs(Glow.debugList()) do
      log(("  %s src%d x=%.0f z=%.0f h=%.0f reach=%.0f a=%.2f")
          :format(tag, i, s.x, s.z, s.h, s.reach, s.a))
    end
  end
  do
    local vd = game.data.maps.VIRIDIAN_CITY
    local w = vd and vd.warps and vd.warps[1]
    if w then
      local keys = {}
      for k, v in pairs(w) do keys[#keys + 1] = k .. "=" .. tostring(v) end
      table.sort(keys)
      log("warp1:", table.concat(keys, " "))
    end
  end

  -- ------- ROCK TUNNEL, before FLASH
  save.flashLit = nil
  DayNight.setting:sync("day")
  visit("ROCK_TUNNEL_1F", 20, 18, "down")
  walk("down", 40)
  settle()
  report("rock-dark")
  shot("glow_rock_dark.png")

  -- the same, GLOW OFF: the engine's own palette darkness comes back
  Glow.setting:sync(false)
  wait(4)
  settle()
  report("rock-dark-off")
  shot("glow_rock_dark_off.png")
  Glow.setting:sync(true)
  wait(4)
  settle()

  -- ------- ROCK TUNNEL, after FLASH
  save.flashLit = true
  ow:setDark(false)
  settle()
  report("rock-flash")
  shot("glow_rock_flash.png")
  save.flashLit = nil

  -- ------- MT. MOON with Yellow's own Pikachu out
  save.pikachuInBall = false
  if party[1] then party[1].species = oldLead end
  visit("MT_MOON_1F", 20, 18, "down")
  walk("left", 40)
  settle()
  report("mtmoon-pika")
  shot("glow_mtmoon_pika.png")

  -- ------- VIRIDIAN at night, a Charmander at heel
  save.pikachuInBall = true
  if party[1] then party[1].species = "CHARMANDER" end
  DayNight.setting:sync("night")
  visit("VIRIDIAN_CITY", 20, 24, "down")
  walk("right", 40)
  settle()
  report("viridian-night")
  sources("viridian")
  shot("glow_viridian_night.png")
  Glow.setting:sync(false)
  wait(4)
  settle()
  report("viridian-night-off")
  shot("glow_viridian_night_off.png")
  Glow.setting:sync(true)

  -- ------- talking to it: turn to face the follower, press A. It must hop
  -- (and cry), and no text box may open -- the talkTo wrap answered it.
  do
    local f = Follower.current()
    local p = ow.player
    if f then
      local dx, dy = f.cellX - p.cellX, f.cellY - p.cellY
      local dir = (dx < 0 and "left") or (dx > 0 and "right")
                  or (dy < 0 and "up") or "down"
      p.facing = dir
      wait(2)
      tap("a")
      wait(4)
      log(("talk: faced=%s follower=%d,%d hop=%d topIsOverworld=%s"):format(
        dir, f.cellX, f.cellY, f.hop or -1, tostring(game.stack:top() == ow)))
      wait(40)
      game.input:reset()
    else
      log("talk: no follower")
    end
  end

  -- ------- the POWER PLANT, where the wild ones are the lights
  DayNight.setting:sync("day")
  visit("POWER_PLANT", 5, 30, "up")
  wait(240)
  report("powerplant")
  sources("plant")
  shot("glow_powerplant.png")

  -- ------- the mask cost, warm: walk the Charmander around a lit block
  local b0, m0, c0 = Glow.stats.built, Glow.stats.buildMs, Glow.stats.cpuMs or 0
  walk("up", 64)
  walk("right", 64)
  settle()
  -- and again over the same cells: the cache should answer all of it
  local b1, m1, c1 = Glow.stats.built, Glow.stats.buildMs, Glow.stats.cpuMs or 0
  walk("left", 64)
  walk("down", 64)
  settle()
  local nb = b1 - b0
  log(("walk-cost masks=%d ms=%.2f per=%.3f cpu-per=%.3f"):format(nb, m1 - m0,
      nb > 0 and (m1 - m0) / nb or 0, nb > 0 and (c1 - c0) / nb or 0))
  log(("walk-back masks=%d ms=%.2f"):format(Glow.stats.built - b1,
      Glow.stats.buildMs - m1))

  -- ------- A FIGHT IN THE DARK: Flamethrower in Rock Tunnel
  local oldMoves = party[1] and party[1].moves
  if party[1] then
    party[1].species = "CHARMANDER"
    party[1].moves = { { id = "FLAMETHROWER", pp = 15 } }
  end
  save.flashLit = nil
  visit("ROCK_TUNNEL_1F", 20, 18, "down")
  local BattleState = require("src.battle.BattleState")
  local battle = BattleState.newWild(game, "GEODUDE", 12)
  battle.onFinish = function(result) ow:afterBattle(result, battle) end
  ow:pushBattle(battle)
  local guard = 0
  while game.stack:top() ~= battle and guard < 600 do wait(1); guard = guard + 1 end
  wait(360)
  report("battle-idle")
  shot("glow_battle_idle.png")
  -- FIGHT, then the one move
  local sawAnim, shotMid, shotHit = false, false, false
  local tries = 0
  while not shotHit and tries < 40 do
    tries = tries + 1
    if not battle.animPlaying then tap("a") end
    for _ = 1, 30 do
      coroutine.yield()
      if battle.animPlaying and battle.animName == "FLAMETHROWER" then
        if not sawAnim then sawAnim = true; wait(18) end
        if not shotMid then
          log("battle anim", battle.animName, "attackerIsPlayer",
              tostring(battle.animAttackerIsPlayer))
          shot("glow_battle_throw.png")
          shotMid = true
        end
      elseif sawAnim and not battle.animPlaying and not shotHit then
        wait(3)
        shot("glow_battle_hit.png")
        shotHit = true
        break
      end
    end
  end
  log("battle shots mid", tostring(shotMid), "hit", tostring(shotHit))
  if party[1] then party[1].moves = oldMoves end

  -- put the save back as it was, in memory, before quitting
  if party[1] then party[1].species = oldLead end
  save.pikachuInBall = nil
  log("DONE")
  logf:close()
  love.event.quit()
end
