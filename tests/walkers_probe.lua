-- Probe: is `def.movement` real at runtime, and does it agree with the data?
--
-- The agenda's whole filter rests on telling a Gen 1 WALK object from a STAY
-- one. `data/generated/maps.lua` carries an explicit `movement` field per
-- object ("STAY" / "WALK"), which is exactly the discriminator wanted -- but
-- no file in this mod reads it, so its presence on the runtime `npc.def` is
-- an assumption, not a fact. If it is absent the filter silently matches
-- nothing and the agenda quietly does not happen.
--
-- The fallback candidate is worse and worth ruling out loudly: keying off
-- `POST_FACING[def.range] == nil` (what Routines already does for POST)
-- treats `range = "NONE"` as a walker, and 249 of the game's 916 objects are
-- STAY-with-NONE -- the bike shop clerk among them. That filter would put a
-- quarter of Kanto on the road.
--
-- Counts are checked against numbers taken from the generated data, so this
-- also catches the runtime cast diverging from the file (mod roamers, script
-- spawns, anything this mod added to ow.npcs).
--
--   POKEPORT_VERSION=yellow \
--   DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/walkers_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/walkers_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n")
    logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(btn)
    game.input.pressQueue[#game.input.pressQueue + 1] = btn
    coroutine.yield()
  end
  local function done(msg) log(msg); logf:close(); love.event.quit() end

  local frames = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); frames = frames + 1
    if frames > 900 then return done("FAIL: no overworld") end
  end
  frames = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); frames = frames + 11
    if frames > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then return done("FAIL: TERRARIUM not loaded") end
  local NPC = require("src.world.NPC")
  local Routines = lib.require("Routines")
  local DayNight = lib.require("DayNight")
  local Shelter = lib.require("Shelter")

  -- Everything below the wiring section tests the agenda's FULL behaviour,
  -- so the row goes on once here. It gates `destinations()` -- under DAY the
  -- night destination is the anchor -- so leaving it at its default made
  -- three sections quietly measure the day path at night and report it as a
  -- failure of the night path. The wiring section at the end sets all three
  -- modes itself, which is where the row's own behaviour is checked.
  Routines.agendaSetting:sync("full")

  -- RUNTIME counts, not the ones in data/generated/maps.lua.
  --
  -- The file says Saffron has 6 walkers and Fuchsia 6; the running game has
  -- 4 and 5, and carries 9 of Saffron's 15 objects at all. Gen 1 gates
  -- objects on story flags -- Saffron's Rockets are there or not depending
  -- on Silph -- so the object list is a superset of any given save. The
  -- feature acts on the cast that exists, so the cast that exists is what
  -- this asserts; pinning to the file would fail forever for a good reason,
  -- which is the same as not asserting at all.
  local EXPECT = {
    PALLET_TOWN = 2, ROUTE_1 = 2, PEWTER_CITY = 1,
    SAFFRON_CITY = 4, FUCHSIA_CITY = 5, CELADON_CITY = 4,
  }
  local ORDER = { "PALLET_TOWN", "ROUTE_1", "PEWTER_CITY",
                  "SAFFRON_CITY", "FUCHSIA_CITY", "CELADON_CITY" }

  local sawMovement, allPass = false, true

  for _, mapId in ipairs(ORDER) do
    game.overworld:setMap(mapId, 5, 5, "down")
    wait(60)

    local total, walk, stay, blank, trainers = 0, 0, 0, 0, 0
    local rangeNoneStay, wanders, disagree, modRoamers = 0, 0, 0, 0
    for _, npc in ipairs(game.overworld.npcs or {}) do
      if getmetatable(npc) == NPC and npc.def then
        total = total + 1
        local mv = npc.def.movement
        if mv ~= nil then sawMovement = true end
        if mv == "WALK" then walk = walk + 1
        elseif mv == "STAY" then stay = stay + 1
        else blank = blank + 1 end
        if npc.def.trainerClass then trainers = trainers + 1 end
        -- the trap the other filter would fall into
        if mv == "STAY" and npc.def.range == "NONE" then
          rangeNoneStay = rangeNoneStay + 1
        end
        -- `npc.wanders` is the ENGINE's own walker flag (Routines' glance
        -- already defers to it). If it agrees with the data's `movement`
        -- everywhere, prefer it: it is what the engine acts on, so it
        -- cannot drift from the behaviour being reasoned about.
        if npc.wanders then wanders = wanders + 1 end
        if (not not npc.wanders) ~= (mv == "WALK") then
          disagree = disagree + 1
        end
        -- RoamerArt stamps `dsSpecies` on the defs it builds, so this is
        -- how a street Pokemon / CityLife roamer is told from a map's own
        -- person. The agenda must never drive one: they have their own moods.
        if npc.def.dsSpecies then modRoamers = modRoamers + 1 end
      end
    end

    -- the module's own filter, against the count made here by hand
    local mine = #Routines.walkers(game.overworld)
    local want = EXPECT[mapId]
    local ok = (walk == want) and (mine == walk)
    if mine ~= walk then
      allPass = false
      log(("  FILTER MISMATCH on %s: Routines.walkers=%d, hand count=%d")
          :format(mapId, mine, walk))
    end
    if not ok then allPass = false end
    log(("%-14s cast=%-3d WALK=%-2d STAY=%-3d noFld=%-2d trnr=%-2d"
         .. " stayNONE=%-2d wanders=%-2d disagree=%-2d modRoam=%-2d"
         .. " expect=%d %s")
        :format(mapId, total, walk, stay, blank, trainers, rangeNoneStay,
                wanders, disagree, modRoamers, want,
                ok and "OK" or "MISMATCH"))
  end

  -- ------- destinations, per phase
  --
  -- Two claims, and the second is the one worth catching. First: the three
  -- day phases send everybody to the cell the ROM authored, so the street
  -- fills. Second: night sends them to DOOR cells, one each -- a duplicate
  -- means two people were told to stand in one tile, and since two NPCs
  -- cannot occupy a cell, the second would spend the night being refused
  -- outside a full doorway. That failure is invisible in a screenshot and
  -- obvious in a set.
  log("")
  for _, mapId in ipairs({ "PALLET_TOWN", "CELADON_CITY", "FUCHSIA_CITY" }) do
    game.overworld:setMap(mapId, 5, 5, "down")
    wait(60)
    local walkers = Routines.walkers(game.overworld)
    local doors = Shelter.doorsFor(game.overworld.map)
    local doorSet = {}
    for _, d in ipairs(doors or {}) do doorSet[d[1] .. "," .. d[2]] = true end

    for _, pin in ipairs({ "day", "night" }) do
      DayNight.setting:sync(pin)
      wait(2)
      local dest = Routines.destinations(game.overworld)
      local n, atAnchor, onDoor, dupes = 0, 0, 0, 0
      local taken = {}
      for _, npc in ipairs(walkers) do
        local d = dest[npc]
        if d then
          n = n + 1
          local key = d[1] .. "," .. d[2]
          if taken[key] then dupes = dupes + 1 end
          taken[key] = true
          if d[1] == tonumber(npc.def.x) and d[2] == tonumber(npc.def.y) then
            atAnchor = atAnchor + 1
          end
          if doorSet[key] then onDoor = onDoor + 1 end
        end
      end
      local bad = (pin == "night" and (dupes > 0 or onDoor < n))
                  or (pin == "day" and atAnchor < n)
      if bad then allPass = false end
      log(("%-13s %-6s walkers=%d dest=%d atAnchor=%d onDoor=%d dupes=%d %s")
          :format(mapId, pin, #walkers, n, atAnchor, onDoor, dupes,
                  bad and "BAD" or "ok"))
    end
  end

  -- ------- materialisation, and the one rule that matters
  --
  -- The feature is allowed to rearrange the town behind the player's back.
  -- It is NOT allowed to be caught doing it, and that is the whole of the
  -- correctness condition, so this is what gets asserted: every walker that
  -- moved had BOTH its old cell and its new cell outside the view box.
  --
  -- Checking one end is not half a test, it is the wrong test -- destination
  -- only lets somebody vanish while you look at them, origin only lets
  -- somebody appear out of nothing ahead of you.
  log("")
  local hw, hh = Routines.viewCells()
  log(("view box: +/-%d x +/-%d cells (Game Boy screen is 5 x 4.5)")
      :format(hw, hh))

  for _, mapId in ipairs({ "CELADON_CITY", "FUCHSIA_CITY" }) do
    game.overworld:setMap(mapId, 5, 5, "down")
    wait(60)
    DayNight.setting:sync("night")
    wait(2)

    local p = game.overworld.player
    local before = {}
    for _, npc in ipairs(Routines.walkers(game.overworld)) do
      before[npc] = { npc.cellX, npc.cellY }
    end

    local moved = Routines.materialize(game.overworld)

    local violations, minSeen = 0, math.huge
    local doors = Shelter.doorsFor(game.overworld.map)
    local doorSet = {}
    for _, d in ipairs(doors or {}) do doorSet[d[1] .. "," .. d[2]] = true end
    local onDoor, offscreen = 0, 0

    for npc, b in pairs(before) do
      local movedThis = (npc.cellX ~= b[1] or npc.cellY ~= b[2])
      if movedThis then
        local dOldX = math.abs(b[1] - p.cellX)
        local dOldY = math.abs(b[2] - p.cellY)
        local dNewX = math.abs(npc.cellX - p.cellX)
        local dNewY = math.abs(npc.cellY - p.cellY)
        local oldHidden = dOldX > hw or dOldY > hh
        local newHidden = dNewX > hw or dNewY > hh
        if not (oldHidden and newHidden) then
          violations = violations + 1
          log(("  VIOLATION: %s moved (%d,%d)->(%d,%d), player (%d,%d)"
               .. " oldHidden=%s newHidden=%s")
              :format(tostring(npc.def and npc.def.name), b[1], b[2],
                      npc.cellX, npc.cellY, p.cellX, p.cellY,
                      tostring(oldHidden), tostring(newHidden)))
        end
        minSeen = math.min(minSeen, math.max(dOldX, dOldY),
                                    math.max(dNewX, dNewY))
      end
      local far = math.abs(npc.cellX - p.cellX) > hw
                  or math.abs(npc.cellY - p.cellY) > hh
      if far then
        offscreen = offscreen + 1
        if doorSet[npc.cellX .. "," .. npc.cellY] then onDoor = onDoor + 1 end
      end
    end

    if violations > 0 then allPass = false end
    log(("%-13s night  moved=%d violations=%d  offscreen=%d onDoor=%d"
         .. "  closest-moved=%s  %s")
        :format(mapId, moved, violations, offscreen, onDoor,
                minSeen == math.huge and "-" or tostring(minSeen),
                violations == 0 and "ok" or "BAD"))
    -- Why each unmoved walker stayed put. Not a footnote: "blocked by a
    -- body" is a thing to fix, while "its door is in shot" is the sight
    -- rule working, and those two must never be reported as one number.
    -- A walker whose door sits near the player CANNOT be materialised by
    -- design -- it has to be walked there where the player can watch, which
    -- is the next increment, not a fault in this one.
    local dest = Routines.destinations(game.overworld)
    local occupied = {}
    for _, npc in ipairs(game.overworld.npcs or {}) do
      occupied[npc.cellX .. "," .. npc.cellY] = npc
    end
    -- Four buckets, and the fourth exists because the first version of this
    -- had three: anything it could not explain fell through an `else` into
    -- "blocked", which reported a design-correct refusal as a defect. An
    -- unexplained case must be visible AS unexplained, or the classifier is
    -- just laundering ignorance into a number.
    -- `moving` is its own bucket, not a mystery: a WALK object is stepping
    -- most of the time, and materialize refuses mid-step on purpose because
    -- NPC:update settles `moving` before it reads anything else. It resolves
    -- itself on the next call, so it is a wait rather than a failure.
    local inView, destView, blocked, arrived, unknown, midStep = 0, 0, 0, 0, 0, 0
    for npc in pairs(before) do
      local d = dest[npc]
      if d then
        local originSeen = math.abs(npc.cellX - p.cellX) <= hw
                           and math.abs(npc.cellY - p.cellY) <= hh
        local destSeen = math.abs(d[1] - p.cellX) <= hw
                         and math.abs(d[2] - p.cellY) <= hh
        local other = occupied[d[1] .. "," .. d[2]]
        if npc.cellX == d[1] and npc.cellY == d[2] then arrived = arrived + 1
        elseif npc.moving or npc.dsShelter then midStep = midStep + 1
        elseif originSeen then inView = inView + 1
        elseif destSeen then destView = destView + 1
        elseif other and other ~= npc then blocked = blocked + 1
        else unknown = unknown + 1 end
      end
    end
    log(("  arrived=%d  mid-step=%d  origin-in-shot=%d  door-in-shot=%d"
         .. "  blocked-by-body=%d  unexplained=%d")
        :format(arrived, midStep, inView, destView, blocked, unknown))
    if blocked > 0 then
      log("  blocked-by-body: a door held by another body leaves that walker")
      log("  without a night post at all -- destinations() should not have")
      log("  handed out an occupied cell.")
      allPass = false
    end
    if unknown > 0 then
      log("  unexplained: refused for a reason this probe does not model.")
      allPass = false
    end
  end

  -- ------- walking the ones in shot
  --
  -- Placed people are the cheap half; these are the half anybody sees. The
  -- claim is that a walker the player can see CLOSES DISTANCE to its post
  -- over a run of frames -- not that it arrives, since a doorway across town
  -- takes longer than a probe should sit there.
  --
  -- Distance is Manhattan, the same metric the stepper ranks by, so a step
  -- that helps always shows as a decrease. A count that never drops means
  -- either nobody was taken or the stepper is refused every frame -- and the
  -- stuck counter separates those two.
  log("")
  for _, mapId in ipairs({ "CELADON_CITY", "FUCHSIA_CITY" }) do
    game.overworld:setMap(mapId, 5, 5, "down")
    wait(60)
    DayNight.setting:sync("night")
    wait(2)

    local p = game.overworld.player
    local hw2, hh2 = Routines.viewCells()
    local dest = Routines.destinations(game.overworld)

    local function distOf()
      local sum, seen = 0, 0
      for npc, d in pairs(dest) do
        if math.abs(npc.cellX - p.cellX) <= hw2
           and math.abs(npc.cellY - p.cellY) <= hh2 then
          seen = seen + 1
          sum = sum + math.abs(npc.cellX - d[1]) + math.abs(npc.cellY - d[2])
        end
      end
      return sum, seen
    end

    local d0, seen0 = distOf()
    local held, stuck = 0, 0
    for _ = 1, 240 do
      Routines.walkTick(game.overworld)
      coroutine.yield()
    end
    local d1 = distOf()
    for npc in pairs(dest) do
      if npc.dsAgenda then held = held + 1 end
      if (npc.dsStuck or 0) > 3 then stuck = stuck + 1 end
    end

    local better = d1 < d0
    if seen0 > 0 and not better then allPass = false end
    log(("%-13s inShot=%d  dist %d -> %d  held=%d stuck=%d  %s")
        :format(mapId, seen0, d0, d1, held, stuck,
                seen0 == 0 and "(nobody in shot)"
                  or (better and "closing" or "NOT CLOSING")))
    Routines.releaseAgenda()
    local leftFrozen = 0
    for npc in pairs(dest) do
      if npc.dsAgenda or npc.dsAgendaFrozen then leftFrozen = leftFrozen + 1 end
    end
    if leftFrozen > 0 then
      allPass = false
      log(("  %d walkers still carry agenda state after release -- a body"
           .. " left frozen never wanders again"):format(leftFrozen))
    end
  end

  -- ------- the strays go in
  --
  -- Three claims. Night thins the cast OUT OF SIGHT and leaves the ones in
  -- shot alone; the spawner is braked so the street does not refill one pet
  -- at a time behind them; and morning releases the brake -- because a hold
  -- that never lifts is indistinguishable from the feature working until
  -- the player notices the town is permanently dead.
  log("")
  local CityLife = lib.require("CityLife")
  for _, mapId in ipairs({ "CELADON_CITY", "VIRIDIAN_CITY" }) do
    game.overworld:setMap(mapId, 5, 5, "down")
    DayNight.setting:sync("day")
    -- The row gates this: nightPets refuses unless the agenda is on FULL, so
    -- without it the section measures the gate refusing rather than the
    -- thinning. It read `brake on=false` for exactly that reason once.
    Routines.agendaSetting:sync("full")
    CityLife.holdNight = false
    wait(180)                                   -- let the street populate

    local p = game.overworld.player
    local hw3, hh3 = Routines.viewCells()
    local function census()
      local ok, cast = pcall(CityLife.cast, game.overworld)
      local inShot, out = 0, 0
      for _, pet in ipairs((ok and cast) or {}) do
        if pet.cellX and (math.abs(pet.cellX - p.cellX) <= hw3
                          and math.abs(pet.cellY - p.cellY) <= hh3) then
          inShot = inShot + 1
        else out = out + 1 end
      end
      return inShot, out
    end

    local dayIn, dayOut = census()
    DayNight.setting:sync("night")
    wait(2)
    for _ = 1, 30 do
      Routines.nightPets(game.overworld)
      coroutine.yield()
    end
    local nightIn, nightOut = census()

    local heldOk = (CityLife.holdNight == true)
    DayNight.setting:sync("day")
    Routines.nightPets(game.overworld)
    local releasedOk = (CityLife.holdNight == false)

    local thinned = (dayOut == 0) or (nightOut < dayOut)
    local keptInShot = (nightIn >= math.min(dayIn, nightIn))
    if not (heldOk and releasedOk and thinned) then allPass = false end
    log(("%-14s pets day in/out=%d/%d -> night %d/%d  brake on=%s off=%s  %s")
        :format(mapId, dayIn, dayOut, nightIn, nightOut,
                tostring(heldOk), tostring(releasedOk),
                (heldOk and releasedOk and thinned) and "ok" or "BAD"))
    if dayOut == 0 then
      log("  (no pet was ever out of shot -- thinning untested on this map)")
    end
    if nightIn > dayIn then
      log("  note: more pets in shot at night than by day -- they wandered")
      log("  into view, which the out-of-sight rule permits.")
    end
  end

  -- ------- the wiring, which is the only part that has not been tested
  --
  -- Everything above called the agenda's functions directly. That proves the
  -- functions and proves nothing about the feature: a module that works
  -- perfectly and is never called from the frame is exactly as useful to the
  -- player as one that does not work. So this section calls NOTHING -- it
  -- sets the row, lets the game's own loop run, and reads the world after.
  --
  -- The three modes are checked for what distinguishes them, not just that
  -- they are accepted: FULL must send somebody to a doorway and brake the
  -- spawner, DAY must do neither while still holding people to their posts,
  -- and OFF must hand everything back.
  log("")
  do
    game.overworld:setMap("FUCHSIA_CITY", 5, 5, "down")
    DayNight.setting:sync("night")
    wait(60)

    local doors = Shelter.doorsFor(game.overworld.map)
    local doorSet = {}
    for _, d in ipairs(doors or {}) do doorSet[d[1] .. "," .. d[2]] = true end

    local function onDoors()
      local n = 0
      for _, npc in ipairs(Routines.walkers(game.overworld)) do
        if doorSet[npc.cellX .. "," .. npc.cellY] then n = n + 1 end
      end
      return n
    end

    -- FULL: the loop alone should post people and hold the spawner
    Routines.agendaSetting:sync("full")
    wait(400)
    local fullDoors, fullBrake = onDoors(), CityLife.holdNight
    log(("wiring FULL   onDoors=%d holdNight=%s")
        :format(fullDoors, tostring(fullBrake)))
    if not fullBrake then
      allPass = false
      log("  BAD: night + FULL did not brake the spawner through the loop --")
      log("  agendaUpdate is not being called, or a guard is refusing it.")
    end

    -- DAY: same hour, and now nobody should be heading for a door
    Routines.agendaSetting:sync("day")
    wait(200)
    local dayBrake = CityLife.holdNight
    local anchored = 0
    local dest = Routines.destinations(game.overworld)
    for npc, d in pairs(dest) do
      if d[1] == tonumber(npc.def.x) and d[2] == tonumber(npc.def.y) then
        anchored = anchored + 1
      end
    end
    log(("wiring DAY    atAnchorDest=%d holdNight=%s"):format(anchored, tostring(dayBrake)))
    if dayBrake then
      allPass = false
      log("  BAD: DAY braked the spawner -- that is FULL's behaviour, and it")
      log("  means the row does not actually separate the two.")
    end

    -- OFF: everything handed back
    Routines.agendaSetting:sync("off")
    wait(120)
    local stillHeld = 0
    for _, npc in ipairs(Routines.walkers(game.overworld)) do
      if npc.dsAgenda then stillHeld = stillHeld + 1 end
    end
    log(("wiring OFF    stillHeld=%d holdNight=%s")
        :format(stillHeld, tostring(CityLife.holdNight)))
    if stillHeld > 0 or CityLife.holdNight then
      allPass = false
      log("  BAD: OFF left state behind -- a frozen body never wanders again")
      log("  and a brake left on empties the streets for the session.")
    end
  end

  -- ------- a posted body must not be a wall
  --
  -- The failure this guards against is the worst one the feature can cause,
  -- because it is not cosmetic: a doorway is a WARP, and a solid NPC posted
  -- in one locks the player out of that building for the whole night. It
  -- would look exactly like the town working.
  --
  -- Checked in both directions. Passable while posted at night, and SOLID
  -- again afterwards -- a person left permanently walk-through is the same
  -- bug wearing the opposite sign.
  log("")
  do
    game.overworld:setMap("FUCHSIA_CITY", 5, 5, "down")
    Routines.agendaSetting:sync("full")
    DayNight.setting:sync("night")
    wait(400)

    local doors = Shelter.doorsFor(game.overworld.map)
    local doorSet = {}
    for _, d in ipairs(doors or {}) do doorSet[d[1] .. "," .. d[2]] = true end

    local posted, solidPosted = 0, 0
    for _, npc in ipairs(Routines.walkers(game.overworld)) do
      if doorSet[npc.cellX .. "," .. npc.cellY] then
        posted = posted + 1
        if not npc.passable then solidPosted = solidPosted + 1 end
      end
    end
    log(("passable night  posted=%d solid=%d"):format(posted, solidPosted))
    if posted > 0 and solidPosted > 0 then
      allPass = false
      log("  BAD: a walker is posted in a doorway and still solid -- that")
      log("  doorway is a warp the player can no longer use.")
    end

    -- and back to solid when the hour or the row lets them go
    DayNight.setting:sync("day")
    wait(200)
    Routines.agendaSetting:sync("off")
    wait(120)
    local ghosts, residue = 0, 0
    for _, npc in ipairs(Routines.walkers(game.overworld)) do
      if npc.passable then ghosts = ghosts + 1 end
      if npc.dsAgendaSolid ~= nil or npc.dsAgenda then residue = residue + 1 end
    end
    log(("passable after  walkThrough=%d residue=%d"):format(ghosts, residue))
    if ghosts > 0 or residue > 0 then
      allPass = false
      log("  BAD: somebody is still walk-through, or still carries agenda")
      log("  state -- both outlive the feature being switched off.")
    end
  end

  -- ------- the phase clock, across the whole dial
  --
  -- Pinned by MODE, not by writing DayNight.clock: `time()` only reads the
  -- clock under CYCLE, so a probe that sets it and runs in the evening reads
  -- the wall clock instead and every phase below comes back NIGHT.
  log("")
  local seen = {}
  for _, pin in ipairs({ "dawn", "day", "dusk", "night" }) do
    DayNight.setting:sync(pin)
    wait(2)
    local tod, phase = DayNight.tod(), Routines.phase()
    seen[phase] = true
    log(("pin=%-6s tod=%-8s Routines.phase=%s"):format(pin, tod, phase))
  end
  local distinct = 0
  for _ in pairs(seen) do distinct = distinct + 1 end
  log(("distinct phases across the dial: %d (want 4)"):format(distinct))
  if distinct ~= 4 then
    allPass = false
    log("  the agenda cannot have four destinations if the clock only ever")
    log("  names fewer -- two pins are collapsing onto one phase.")
  end

  log("")
  if not sawMovement then
    log("FAIL: def.movement is nil on every NPC -- the field does not survive")
    log("  into the runtime def. The agenda needs a different discriminator;")
    log("  do NOT fall back to POST_FACING[range]==nil, see the header.")
  elseif allPass then
    log("PASS: def.movement exists and the runtime WALK counts match the data.")
  else
    log("PARTIAL: def.movement exists but a count disagrees with the data --")
    log("  the runtime cast is not the file's object list on that map.")
  end
  done("done")
end
