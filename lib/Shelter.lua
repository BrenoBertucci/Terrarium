-- What a town DOES when it starts raining: it empties.
--
-- The complaint this exists for is a fair one. The mod grew a sky that
-- clouds over, rain that falls, ground that soaks through and pools that
-- gather in it -- and underneath all of that the street went on exactly as
-- it had in the sun. The same people standing in the same places, the same
-- stray Pokemon strolling the same beats, in a downpour. Weather that
-- nobody in the world reacts to is scenery, and scenery is what the whole
-- rest of this mod is trying not to be.
--
-- So: when it comes down hard enough, the people go inside and the strays
-- go with them, and when it passes they come back out.
--
-- ------- what "inside" means here, and why it is a DOORWAY
--
-- The obvious version -- take the NPC out of `ow.npcs`, put it back when the
-- sky clears -- is the one this deliberately does not do for the map's own
-- people, and the reason is `npcByIndex`.
--
-- The engine's scripts find an NPC by its object index by WALKING ow.npcs
-- (OverworldController:npcByIndex), and Kanto's outdoor scripts do it a lot:
-- Pallet's Oak is index 1, Pewter's youngster is 5, the Rocket outside the
-- museum is 2. An NPC that is not in the list is not findable, and a script
-- that asks for one and is handed nil does not degrade -- it walks into the
-- nil. A graphics mod that can break the story on a rainy Tuesday has not
-- earned the feature.
--
-- What it does instead is put them IN THE DOORWAY: each civilian walks to
-- the nearest door on the map, steps onto the door cell itself and stands
-- there facing into the house, and stays until the shower passes. The street
-- is empty, which is the thing you can see; they are still in the cast list,
-- addressable, script-findable and exactly where the engine expects to find
-- them, which is the thing you cannot. And they are still TALKABLE, which
-- turns out to be better than vanishing: somebody sheltering in a doorway is
-- somebody you can go and stand next to.
--
-- The STREET POKEMON do vanish, and they are allowed to because this mod
-- made them. A CityLife pet is not in any map record, has no object index
-- and no script has ever heard of it, so it can be dropped and re-spawned
-- with nothing downstream noticing. So it goes in the door and is gone --
-- which also means the town is genuinely empty of Pokemon rather than
-- lined with them, and that is the read the shot wants.
--
-- ------- who moves and who does not
--
-- WANDERERS ONLY, and no trainers. An NPC whose movement record says WALK is
-- somebody out and about, and somebody out and about goes in out of the
-- rain. An NPC whose record says STAY is standing where the map put them on
-- purpose -- the guard at the gate, the clerk behind the counter, the man
-- who has to be beside the sign for his line to make sense -- and moving one
-- is rewriting the map rather than reacting to the weather. A trainer's
-- facing IS their line of sight, so a trainer is never touched here for the
-- same reason AmbientLife's glance never touches one.
--
-- Which leaves, in a Gen 1 town, most of the people: the wanderers are the
-- population and the STAY objects are the furniture.
--
-- ------- how they walk
--
-- One cell at a time, through the engine's own step. NPC:update handles a
-- step ALREADY IN PROGRESS before it looks at `frozen` -- so setting
-- targetX/targetY, `moving` and `progress` and then freezing the NPC hands
-- the whole animation to the engine and stops its own wandering in the same
-- move. Nothing here runs a timeline, tweens a pixel or draws anything: a
-- sheltering NPC walks at exactly the rate every other NPC walks at, because
-- it is the same code doing it.
--
-- The route to the door is greedy -- close the bigger gap first, try the
-- other axis when that is blocked, and give up into a shrug after a few
-- refusals. No path is planned, and none should be: a Gen 1 town is open
-- ground with buildings in it, the doors are on the open ground, and a
-- pathfinder here would be a lot of machinery to arrive at the same three
-- steps. What the shrug is for is the corner cases -- a fenced yard, a door
-- behind a ledge -- where the honest answer is that this person cannot get
-- there, and standing still facing the rain is a better failure than
-- shuffling against a wall forever.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local Weather = V.require("Weather")
local CityLife = V.require("CityLife")

local Collision = require("src.world.Collision")
local Map = require("src.world.Map")
local NPC = require("src.world.NPC")

local Shelter = {}

local function game()
  return require("src.core.Game")
end

Shelter.setting = ModSetting.new("shelter", "SHELTER",
                                 { "on", "off" }, { "ON", "OFF" })

function Shelter.enabled()
  return Shelter.setting:get() == "on"
end

function Shelter.row()
  return Shelter.setting:row()
end

-- ------- the thresholds, and why there are two of them
--
-- One threshold would flicker. A shower's power wanders around its peak, so
-- a single line at 0.5 has the whole town walking to the door and back every
-- time it crosses -- which is the single most obviously broken thing this
-- could do. So: it takes a HARD rain to send them in and a genuinely
-- stopping one to bring them back out, with a wide dead band between where
-- nothing changes its mind.
--
-- And the going-in line has a DELAY on it, because that is what people do.
-- Nobody moves at the first drop; they finish what they were doing, and then
-- it is obviously not stopping and they go. Ten seconds is long enough to
-- read as a decision and short enough that the player, who is standing in
-- it, sees the street clear rather than finding it already cleared.
Shelter.GO_IN_ABOVE = 0.50      -- rain power that sends the street indoors
Shelter.COME_OUT_BELOW = 0.12   -- and the power it takes to bring them back
Shelter.GO_IN_DELAY = 10        -- seconds of it before anybody moves
Shelter.COME_OUT_DELAY = 6      -- and the pause before they come back out

-- How many refusals a walker takes before it gives up on reaching its door
-- and simply stands its ground. Counted per NPC and reset by every step that
-- lands, so it measures being STUCK rather than being slowed down by a
-- crowd at the door.
Shelter.PATIENCE = 14

-- Snow does not send anybody in. A Gen 1 town in the snow is a town in the
-- snow -- people are out in it, that is the picture -- and a route that
-- emptied at the first flake would delete the one weather the GROUND row
-- looks best under. This is about RAIN.
--
-- `falling` and not `visible`, and the difference is a bug this would
-- otherwise have. `visible` is "is there rain to DRAW here", which is false
-- the instant the player steps into a shop -- and the town outside does not
-- stop raining because you went indoors to buy a Potion. Read that way, the
-- shower would end every time the player opened a door and the whole street
-- would file back out into it. `falling` is "what is the weather doing in
-- Kanto", which is the question this module is actually asking. Weather's own
-- header draws exactly this distinction; this is the other side of it.
local function pouring()
  local kind, power = Weather.falling()
  if kind ~= "rain" then return 0 end
  return power or 0
end

local state = { mapId = nil, inside = false, timer = 0 }

-- Everybody this module has taken responsibility for on the current map, so
-- a release does not have to trust a scan to find them all again. Weak keys:
-- an NPC that leaves with its map takes its entry with it rather than
-- pinning a dead object here, which is the same arrangement GroundFX's
-- footprint tracker uses and for the same reason.
local held = setmetatable({}, { __mode = "k" })

-- ------- the doors
--
-- Read straight off the map record rather than scanned for: `def.warps` is
-- the list the engine itself builds `warpAt` from, so this is the same set of
-- cells, already gathered. Cached per map because it cannot change.
--
-- DOOR TILES only where a map has any. A warp is not always a door -- it is
-- also a cave mouth, a staircase, a warp pad and the hole in Rocket HQ's
-- floor -- and "goes in out of the rain" means a building. On an outdoor
-- Kanto map the door tiles are the buildings, which is the whole list this
-- wants; if a map turns out to have warps and no door tiles, every warp is
-- allowed rather than leaving that map's people standing in it.
local doorCache = {}

local function doorsOf(map)
  local got = doorCache[map.id]
  if got then return got end
  local doors, any = {}, {}
  for _, w in ipairs((map.def and map.def.warps) or {}) do
    if w.x and w.y then
      any[#any + 1] = { w.x, w.y }
      local ok, isDoor = pcall(map.isDoorTileCell, map, w.x, w.y)
      if ok and isDoor then doors[#doors + 1] = { w.x, w.y } end
    end
  end
  if #doors == 0 then doors = any end
  doorCache[map.id] = doors
  return doors
end

-- The nearest door that nobody else is already walking to. Manhattan, which
-- is the metric the walk itself uses -- ranking by a distance the walker
-- cannot travel in would send people past a door they could have reached.
--
-- `claimed` is what keeps a town from filing every one of its people into
-- one doorway. Two NPCs cannot stand in the same cell, so the second would
-- arrive, be refused, and burn its patience shuffling outside a door that is
-- already full; spreading them over the doors the map has puts one person in
-- each, which is also what a street looks like when it starts raining.
local function pickDoor(map, cx, cy, claimed)
  local doors = doorsOf(map)
  local best, bestD = nil, nil
  local fallback, fallbackD = nil, nil
  for _, d in ipairs(doors) do
    local dist = math.abs(d[1] - cx) + math.abs(d[2] - cy)
    if not fallbackD or dist < fallbackD then fallback, fallbackD = d, dist end
    local key = d[1] .. "," .. d[2]
    if not claimed[key] and (not bestD or dist < bestD) then
      best, bestD = d, dist
    end
  end
  return best or fallback
end

-- ------- one step, through the engine's own walk
--
-- Returns true once the walker is standing on the cell it was sent to.
--
-- The two directions are tried longer-gap-first, which on open ground is a
-- straight line with one bend in it. `Collision.canMove` is the engine's own
-- test, so a sheltering NPC is refused by the same walls, ledges and bodies
-- that refuse a wandering one -- including the player, who can stand in a
-- doorway and be an obstacle, which is a thing worth being able to do.
--
-- Warp cells are stepped ONTO deliberately, and that is the one rule here
-- that departs from NPC:update. The engine's wander refuses a warp so that a
-- wanderer does not walk out of the map; nothing is walking out of anything
-- here, because a warp only fires for the player.
local function stepToward(map, entities, walker, tx, ty)
  if walker.moving then return false end
  local dx, dy = tx - walker.cellX, ty - walker.cellY
  if dx == 0 and dy == 0 then return true end

  local order = {}
  local function want(dir) if dir then order[#order + 1] = dir end end
  local horiz = dx > 0 and "right" or (dx < 0 and "left" or nil)
  local vert = dy > 0 and "down" or (dy < 0 and "up" or nil)
  if math.abs(dx) >= math.abs(dy) then want(horiz) want(vert)
  else want(vert) want(horiz) end

  for _, dir in ipairs(order) do
    if Collision.canMove(map, entities, walker, dir) then
      local nx, ny = Collision.target(walker.cellX, walker.cellY, dir)
      walker.facing = dir
      walker.targetX, walker.targetY = nx, ny
      walker.moving = true
      walker.progress = 0
      -- a step that LANDED clears the count, so patience measures being
      -- stuck rather than being held up: somebody waiting their turn behind
      -- a crowded doorway is making progress between refusals and should not
      -- run out of it
      walker.dsStuck = 0
      return false
    end
  end
  -- refused on both axes: turn to face the way it wanted to go anyway, so a
  -- walker held up at a corner is visibly still trying to get somewhere
  walker.facing = order[1] or walker.facing
  walker.dsStuck = (walker.dsStuck or 0) + 1
  return false
end

-- ------- who is a civilian
--
-- The same three tests AmbientLife's glance holds, and one more. A trainer
-- is never touched (their facing is their sight line); a script's NPC is
-- never touched (it is mid-sentence); and a STAY object is never touched,
-- because standing there is its job rather than its mood.
local function civilian(npc)
  if getmetatable(npc) ~= NPC then return false end
  if not npc.def or npc.def.trainerClass then return false end
  if npc.dsShelter then return true end        -- already ours, keep it
  if not npc.wanders then return false end
  if npc.frozen then return false end
  return true
end

-- ------- taking somebody in, and letting them go
--
-- `home` is where the map put them, remembered the moment they are taken so
-- the walk back has somewhere to go. Their own facing goes with it: a
-- shopkeeper who came back from the rain facing a different way from the one
-- the map authored is a small wrongness that never stops being visible.
local function take(map, npc, claimed)
  local door = pickDoor(map, npc.cellX, npc.cellY, claimed)
  if not door then return false end
  claimed[door[1] .. "," .. door[2]] = true
  npc.dsHomeX, npc.dsHomeY = npc.cellX, npc.cellY
  npc.dsHomeFacing = npc.facing
  npc.dsDoorX, npc.dsDoorY = door[1], door[2]
  npc.dsShelter = "in"
  npc.dsStuck = 0
  -- frozen stops its OWN wander; a step already set up still animates,
  -- because NPC:update settles `moving` before it ever reads this
  npc.frozen = true
  held[npc] = true
  return true
end

-- Hand an NPC back exactly as it was found -- and this must work from any
-- state, at any moment, because the reasons it gets called are a map change,
-- a battle, the row being switched off and the module throwing. `snap` puts
-- them back on their own cell instantly rather than walking them: those are
-- the paths where there is no time to walk, and a person left mid-stride in
-- a doorway when the map unloads is a person standing in a doorway on a map
-- they do not belong to.
-- ------- and the thing that would have locked the player out of every shop
-- in Kanto
--
-- A door cell is one cell, and a Gen 1 door is reachable from exactly one
-- side -- it is a hole in a wall. So an NPC standing in a doorway is an NPC
-- standing in the only cell the player can enter that building through, and
-- `Collision.occupied` refuses it: a shower would have shut the Mart, the
-- Center and every house on the map for as long as it lasted. Which is not a
-- charming detail, it is a soft lock with a timer on it.
--
-- The engine already has the answer and has had it since Yellow: `passable`
-- is the flag the companion Pikachu wears so the player walks straight
-- through it (Collision.occupied, pikachu_follow.asm). Somebody sheltering
-- in a doorway wears it too, and the player brushes past them into the shop
-- -- which is also, exactly, what you do.
--
-- Set on ARRIVAL rather than when they are taken. On the way there they
-- block like anybody else, which is what makes a second person queue behind
-- the first instead of walking through them.
local function makePassable(npc)
  if npc.dsWasPassable == nil then npc.dsWasPassable = npc.passable or false end
  npc.passable = true
end

local function release(npc, snap)
  if not npc.dsShelter then return end
  if npc.dsWasPassable ~= nil then
    npc.passable = npc.dsWasPassable or nil
    npc.dsWasPassable = nil
  end
  if snap then
    if npc.dsHomeX then
      npc.cellX, npc.cellY = npc.dsHomeX, npc.dsHomeY
      npc.px, npc.py = npc.cellX * 16, npc.cellY * 16
      npc.targetX, npc.targetY = nil, nil
      npc.moving = false
      npc.progress = 0
    end
    if npc.dsHomeFacing then npc.facing = npc.dsHomeFacing end
  end
  npc.frozen = false
  npc.dsShelter = nil
  npc.dsHomeX, npc.dsHomeY, npc.dsHomeFacing = nil, nil, nil
  npc.dsDoorX, npc.dsDoorY = nil, nil
  npc.dsStuck = nil
  held[npc] = nil
end

-- Everybody, at once, without walking anybody anywhere.
--
-- `forget` says whether the SHOWER is over as well as the walk. It is not, on
-- the path this is called from most: a map change hands back the people on
-- the map being left, and the rain outside goes on raining. Clearing the
-- phase there would restart the ten-second delay every time the player
-- opened a door, so a town crossed in a downpour would be full of people
-- every time you stepped back out into it.
local function releaseAll(snap, forget)
  for npc in pairs(held) do pcall(release, npc, snap) end
  held = setmetatable({}, { __mode = "k" })
  if forget then
    CityLife.holdSpawns = false
    state.inside = false
    state.timer = 0
  end
end

-- ------- the street Pokemon, which really do go inside
--
-- Same walk, and then they are dropped -- see the header for why they may be
-- and the people may not. `CityLife.holdSpawns` is what stops the spawner
-- refilling the street behind them one pet at a time, which would otherwise
-- turn "the town emptied" into "the town is full of Pokemon queueing at a
-- door".
local function petsIn(ow, map, claimed)
  for _, pet in ipairs(CityLife.cast(ow)) do
    if not pet.dsShelter then
      local door = pickDoor(map, pet.cellX, pet.cellY, claimed)
      if door then
        pet.dsShelter = "in"
        pet.dsDoorX, pet.dsDoorY = door[1], door[2]
        pet.dsStuck = 0
        pet.frozen = true
      end
    end
    if pet.dsShelter then
      if stepToward(map, ow.entities, pet, pet.dsDoorX, pet.dsDoorY)
         or (pet.dsStuck or 0) >= Shelter.PATIENCE then
        -- home is a house it was never in and never has to come out of: the
        -- spawner makes a new one when the sky clears
        CityLife.remove(ow, pet)
      end
    end
  end
end

-- ------- per-frame
local failed = false

local function tick()
  local Game = game()
  local ow = Game and Game.overworld
  if not (ow and ow.map and ow.player and ow.npcs and ow.entities) then return end
  if Game.stack and Game.stack:top() ~= ow then return end
  if ow.transitioning then return end
  -- a script owns the cast while it runs, and an NPC walking itself into a
  -- doorway underneath a cutscene is the mod arguing with the game
  if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then return end

  -- The people on the map being LEFT are handed back, and the shower is not
  -- forgotten with them -- see releaseAll. Walking into a shop in a downpour
  -- and out again should not restart the clock.
  if state.mapId ~= ow.map.id then
    releaseAll(true, false)
    state.mapId = ow.map.id
  end

  local dt = (love.timer and love.timer.getDelta and love.timer.getDelta()) or 0
  local power = pouring()

  -- ------- the phase, decided ABOVE the map gate
  --
  -- Whether Kanto's towns are indoors is a fact about the sky, so it is
  -- worked out whatever map the player happens to be standing on. Only the
  -- CAST is gated below: indoors there is nobody here to send in, but the
  -- shower outside carries on and the street the player walks back out onto
  -- is already empty rather than emptying.
  --
  -- The dead band is what stops it flickering: a shower's power wanders
  -- around its peak, and a single line would have the whole town walking to
  -- the door and back every time it crossed. Only the two outer lines move
  -- the clock; anything between them leaves the street exactly as it is.
  if not Shelter.enabled() then
    if next(held) or CityLife.holdSpawns then releaseAll(true, true) end
    return
  end

  if not state.inside and power >= Shelter.GO_IN_ABOVE then
    state.timer = state.timer + dt
    if state.timer >= Shelter.GO_IN_DELAY then
      state.inside, state.timer = true, 0
      CityLife.holdSpawns = true
    end
  elseif state.inside and power <= Shelter.COME_OUT_BELOW then
    state.timer = state.timer + dt
    if state.timer >= Shelter.COME_OUT_DELAY then
      state.inside, state.timer = false, 0
      CityLife.holdSpawns = false
      for npc in pairs(held) do
        npc.dsShelter = "home"
        npc.dsStuck = 0
        -- and they solidify again the moment they step back out. `passable`
        -- is for somebody pressed into a doorway the player needs to get
        -- through; somebody walking back up the street is a person, and
        -- walking through one of those is the bug that flag would be.
        if npc.dsWasPassable ~= nil then
          npc.passable = npc.dsWasPassable or nil
          npc.dsWasPassable = nil
        end
      end
    end
  else
    state.timer = 0
  end

  -- ------- and only NOW the cast
  --
  -- Towns and routes alike: the rule is an open sky and people to send in,
  -- and a route's gate guards and fishermen get out of the rain for the same
  -- reason a town's do. Indoors there is nobody here who is in it -- the
  -- phase above has already been updated and carries on without them.
  local map = ow.map
  if not Map.isOutdoor(map.def) then return end

  local claimed = {}
  for npc in pairs(held) do
    if npc.dsDoorX then claimed[npc.dsDoorX .. "," .. npc.dsDoorY] = true end
  end

  if state.inside then
    -- anybody new to the map, or newly eligible, joins the exodus
    for _, npc in ipairs(ow.npcs) do
      if not npc.dsShelter and civilian(npc) then take(map, npc, claimed) end
    end
    pcall(petsIn, ow, map, claimed)
  end

  for npc in pairs(held) do
    -- Re-assert the freeze. A player who talks to somebody on their way to a
    -- door hands them to the script, and the script hands them back UNFROZEN
    -- -- at which point their own wander would start fighting this one for
    -- the same `moving` field. Safe to do here and nowhere else: this whole
    -- tick has already returned early if a script is running, so there is
    -- never a conversation in progress at this line.
    if not npc.frozen then npc.frozen = true end

    if npc.dsShelter == "in" then
      if stepToward(map, ow.entities, npc, npc.dsDoorX, npc.dsDoorY) then
        -- arrived: face INTO the house rather than back out at the weather.
        -- A door in this game is drawn on the wall above the cell you stand
        -- on, so "up" is into it, and somebody facing up in a doorway reads
        -- as somebody who has just gone in.
        npc.facing = "up"
        makePassable(npc)
      elseif (npc.dsStuck or 0) >= Shelter.PATIENCE then
        -- cannot get there. Stand still rather than shuffle: an NPC grinding
        -- against a fence for the length of a shower is worse than one who
        -- is simply caught out in it.
        npc.dsShelter = "stuck"
      end
    elseif npc.dsShelter == "home" then
      if stepToward(map, ow.entities, npc, npc.dsHomeX, npc.dsHomeY)
         or (npc.dsStuck or 0) >= Shelter.PATIENCE * 2 then
        release(npc, true)
      end
    end
  end
end

function Shelter.update()
  if failed then return end
  local ok, err = pcall(tick)
  if ok then return end
  failed = true
  -- put everybody back where the map put them before retiring: a feature
  -- that throws halfway through moving the cast must not leave the cast
  -- moved. Same contract every other module here holds.
  pcall(releaseAll, true, true)
  if V.mod and V.mod.log then
    V.mod.log:warn("shelter failed: %s -- the town stays out in the rain "
                   .. "for this session", tostring(err))
  end
end

-- ------- for the probe
--
-- "The town empties" is a claim about a count, and a count is checkable in a
-- way a screenshot of an empty street is not -- an empty street and a street
-- whose people were never spawned look identical.
function Shelter.count()
  local n = 0
  for _ in pairs(held) do n = n + 1 end
  return n
end

function Shelter.indoors()
  return state.inside
end

function Shelter.doorsFor(map)
  return doorsOf(map)
end

function Shelter.invalidate()
  doorCache = {}
end

return Shelter
