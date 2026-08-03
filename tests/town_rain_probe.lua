-- Probe: the town empties when it rains, and fills back up when it stops.
--
-- Both halves have to be counted, and the second one is the half that
-- matters. "The street is empty" is not a claim a screenshot settles: an
-- empty street and a street whose people this mod has permanently deleted
-- look exactly the same, and only one of them is the feature. So every
-- number here is taken THREE times -- dry, wet, and dry again -- and the
-- test is that the third reading matches the first.
--
-- What is checked, and what each one would be hiding if it were not:
--
--   the CAST SIZE (#ow.npcs).  Must never change. Nothing here delists a map
--   NPC, on purpose -- the engine's scripts find people by walking that list
--   (npcByIndex), so a sheltering NPC that left it is a story that breaks on
--   a rainy Tuesday. If this number ever moves, that rule has been broken.
--
--   WHERE the civilians are standing. Under a shower they should be ON door
--   cells; before and after, on the cells the map authored. A count of who
--   is on a door is the whole feature in one integer.
--
--   the TRAINERS and the STAY objects. Must not move and must not turn. This
--   is the guard rail: a trainer's facing is their line of sight, and a
--   shopkeeper standing where the map put them is the map's authorship.
--
--   the STREET POKEMON. These DO leave -- they are this mod's own and no
--   script has heard of them -- so the count goes to zero under the shower
--   and comes back after it. A count that stays zero afterwards is a
--   spawner this probe caught still being held.
--
--   CONVERSATIONS. Two civilians facing each other, which is the routine
--   beat worth having. Counted rather than looked at for the usual reason:
--   one frame of two people talking and one frame of two people who happen
--   to be pointed at each other are the same picture.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/DRAMATIC_SHAPE/tests/town_rain_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/town_rain_probe.log", "w"))
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
    wait(3)
  end

  love.math.setRandomSeed(20260802)

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit()
      return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.DRAMATIC_SHAPE and exports.DRAMATIC_SHAPE.lib
  if not lib then
    log("FAIL: DRAMATIC_SHAPE not loaded"); logf:close(); love.event.quit()
    return
  end
  log("version:", exports.DRAMATIC_SHAPE.version)

  local Shelter = lib.require("Shelter")
  local Routines = lib.require("Routines")
  local CityLife = lib.require("CityLife")
  local Weather = lib.require("Weather")
  local GroundFX = lib.require("GroundFX")
  local DayNight = lib.require("DayNight")
  local NPC = require("src.world.NPC")
  local Pipelines = require("src.render.Pipelines")

  Shelter.setting:sync("on")
  Routines.setting:sync("on")
  CityLife.setting:sync("on")
  GroundFX.setting:sync("on")
  DayNight.setting:sync("day")
  Pipelines.setLevel("voxel", 4)

  game.overworld:setMap("VIRIDIAN_CITY", 4, 16, "down")
  wait(240)

  local ow = game.overworld
  local map = ow.map
  log(("map %s  doors: %d"):format(map.id, #Shelter.doorsFor(map)))
  if #Shelter.doorsFor(map) == 0 then
    log("  FAIL: no doors found -- there is nowhere for anybody to go")
  end

  -- Where the map put everybody, before anything here has touched them. Every
  -- later reading is compared against this rather than against a description
  -- of it.
  local home = {}
  for _, npc in ipairs(ow.npcs) do
    if getmetatable(npc) == NPC then
      home[npc] = { npc.cellX, npc.cellY, npc.facing,
                    npc.def and npc.def.trainerClass or false,
                    npc.wanders or false }
    end
  end

  local function census(tag)
    local cast, onDoor, moved, pets = 0, 0, 0, 0
    local trainerMoved, stayMoved = 0, 0
    for _, e in ipairs(ow.entities or {}) do
      if e.townPet then pets = pets + 1 end
    end
    for _, npc in ipairs(ow.npcs) do
      if getmetatable(npc) == NPC then
        cast = cast + 1
        local h = home[npc]
        if h then
          local away = npc.cellX ~= h[1] or npc.cellY ~= h[2]
          if away then
            moved = moved + 1
            if h[4] then trainerMoved = trainerMoved + 1 end
            if not h[5] then stayMoved = stayMoved + 1 end
          end
          local ok, door = pcall(map.isDoorTileCell, map, npc.cellX, npc.cellY)
          if ok and door then onDoor = onDoor + 1 end
        end
      end
    end
    log("")
    log(("[%s] rain=%.2f  indoors=%s"):format(
      tag, select(2, Weather.visible()) or 0, tostring(Shelter.indoors())))
    log(("  cast=%d  held=%d  onDoor=%d  awayFromHome=%d  townPets=%d  "
         .. "chatting=%d"):format(cast, Shelter.count(), onDoor, moved, pets,
                                  Routines.chatting(ow)))
    if trainerMoved > 0 then
      log(("  FAIL: %d TRAINER(S) moved -- a trainer's cell and facing are "
           .. "their line of sight"):format(trainerMoved))
    end
    if stayMoved > 0 then
      log(("  FAIL: %d STAY object(s) moved -- those are the map's own "
           .. "authorship, not a mood"):format(stayMoved))
    end
    return cast, onDoor, moved, pets
  end

  -- ------- 1. dry
  local cast0, door0, moved0, pets0 = census("dry")
  shot("60_town_dry.png")

  -- ------- give the routines long enough to be caught at it
  --
  -- The beat clock runs to eleven seconds, so a single reading proves
  -- nothing about whether anybody's head ever moves. Watched for a while
  -- instead, and the claim is that facings CHANGE -- which is a count of
  -- changes over time, not a state.
  local turns, chats = 0, 0
  local was = {}
  for npc in pairs(home) do was[npc] = npc.facing end
  for _ = 1, 60 do
    wait(30)
    for npc in pairs(home) do
      if npc.facing ~= was[npc] then turns = turns + 1; was[npc] = npc.facing end
    end
    chats = math.max(chats, Routines.chatting(ow))
  end
  log("")
  log(("routines over 30s: %d facing changes, best %d people talking at once")
      :format(turns, chats))
  if turns == 0 then
    log("  FAIL: nobody ever looked anywhere -- the street is still furniture")
  end
  shot("61_town_routines.png")

  -- ------- 2. wet
  Weather.setting:sync("rain")
  GroundFX.SOAK = 3
  -- long enough for the delay to elapse and for everybody to WALK there:
  -- across a town at sixteen frames a cell, that is the length of this wait
  -- rather than an instant
  wait(1500)
  local cast1, door1, moved1, pets1 = census("raining")
  shot("62_town_raining.png")

  if cast1 ~= cast0 then
    log(("  FAIL: the cast list changed under the shower (%d -> %d). Nothing "
         .. "here may delist a map NPC -- npcByIndex walks that list")
        :format(cast0, cast1))
  end
  if door1 <= door0 then
    log("  FAIL: nobody ended up in a doorway -- the street did not empty")
  end
  if pets1 > 0 then
    log(("  FAIL: %d street Pokemon still out in the rain"):format(pets1))
  end

  -- ------- 3. dry again, and this is the reading that matters
  Weather.setting:sync("off")
  wait(1800)
  local cast2, door2, moved2, pets2 = census("cleared")
  shot("63_town_cleared.png")

  if cast2 ~= cast0 then
    log(("  FAIL: cast %d -> %d after the shower"):format(cast0, cast2))
  end
  if moved2 > moved0 then
    log(("  FAIL: %d people never walked home (was %d before the shower)")
        :format(moved2, moved0))
  end
  if pets2 == 0 and pets0 > 0 then
    log("  FAIL: the street Pokemon never came back -- the spawner is still "
        .. "being held")
  end
  if Shelter.count() > 0 then
    log(("  FAIL: %d people are still held by the shelter after it cleared")
        :format(Shelter.count()))
  end

  -- ------- 4. and the map change, which is the path that has no time to walk
  --
  -- Everybody must be handed back instantly and exactly. A person left
  -- mid-stride in a doorway when the map unloads is a person standing in a
  -- doorway on a map they do not belong to.
  Weather.setting:sync("rain")
  wait(1200)
  log("")
  log(("mid-shower, held=%d -- now leaving the map"):format(Shelter.count()))
  game.overworld:setMap("ROUTE_1", 8, 12, "up")
  wait(120)
  game.overworld:setMap("VIRIDIAN_CITY", 4, 16, "down")
  wait(120)
  Weather.setting:sync("off")
  wait(600)
  local cast3 = census("after a map change")
  if cast3 ~= cast0 then
    log(("  FAIL: cast %d -> %d across a map change"):format(cast0, cast3))
  end

  log("")
  log("done -- " .. OUT)
  logf:close()
  love.event.quit()
end
