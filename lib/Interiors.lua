-- Voxel world mode: the insides of houses, lived in.
--
-- The AMBIENT row already reaches indoors for the one thing it can: civilian
-- NPCs glance at you as you pass, and a shopkeeper is a civilian. What it
-- cannot do is put anything IN a room, because everything it owns is a
-- butterfly over tall grass or a bird under an open sky, and a house has
-- neither. So a room with two people in it is still a room with two people in
-- it and nothing else -- which is what every Gen 1 interior is.
--
-- Two things go in, and they are deliberately at opposite ends of what this
-- mod is allowed to do.
--
-- ------- the sleeping Pokemon, which is a REAL object
--
-- A family's Meowth asleep on the floor. It is a genuine map entity -- the
-- same Roamer the WILD row stands in the grass and the TOWN row walks down
-- the street, wearing the same baked overworld sheet of its own front pic --
-- so the engine y-sorts it, the sun throws its shadow, the palette bake
-- colours it, the diorama cuts its card, and pressing A at it wakes it up.
-- It is asleep, so it is frozen: it never takes a step, never wanders, and
-- never picks a fight. Press A and it stirs, yawns its own cry, and goes back
-- to sleep.
--
-- WHICH houses have one is decided by the map's own NAME and nothing else --
-- a hash, not a die. That is the load-bearing choice in this file: a random
-- roll would put a cat in a different house every time you walked in, and a
-- cat that teleports between houses is not a pet, it is a spawner. Hashed, a
-- house either has a cat or does not, forever, and it is always the same cat
-- asleep in the same corner. Which is what makes it somebody's.
--
-- ------- the steam, which is PURELY a drawing
--
-- A mug left on the table, still hot. Wisps rising off it, drawn in the same
-- overlay pass the ambient life composites through, anchored to the world by
-- the same camera. Nothing stands anywhere: no cell, no entity, no collision,
-- no interaction -- if you walk through where the steam is, you walk through
-- it, because it is steam.
--
-- WHERE a table is comes from the mod's own shape profile rather than from a
-- list of coordinates. Every interior tileset this mod has hand-authored
-- names its `table` and `counter` tiles by id (data/voxel_heights.lua), for
-- the entirely different purpose of extruding them to the right height, and
-- that list answers "is there a tabletop at this cell" for free. So a mug
-- lands on a table in a house nobody wrote a line of code about, and a total
-- conversion that adds its own tileset gets mugs on its tables by pinning
-- them the way it already had to.
--
-- Same hash, same reason: the same table in the same house always has the
-- mug, and the one across the room never does.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local RoamerArt = V.require("RoamerArt")
local Roamer = V.require("Roamer")
local TileShape = V.require("TileShape")

local Collision = require("src.world.Collision")
local Map = require("src.world.Map")
local Strings = require("src.core.Strings")

local Interiors = {}

Interiors.setting = ModSetting.new("indoor", "INDOOR",
                                   { "on", "off" }, { "ON", "OFF" })

function Interiors.enabled()
  return Interiors.setting:get() == "on"
end

function Interiors.row()
  return Interiors.setting:row()
end

local function game()
  return require("src.core.Game")
end

-- ------- which rooms are HOMES
--
-- By tileset, which is the only honest way: Gen 1 has no "this is a house"
-- flag, but it does have one tileset per KIND of interior, and the house
-- tilesets are drawn as houses -- dining tables, bookcases, beds, a TV. A gym
-- is a gym, a Mart is a shop, a cave is a cave, and none of them has anybody
-- living in it.
--
-- The three named oddities are the same rooms with their own atlases: Red's
-- two floors, and the Beach House by the Cycling Road.
Interiors.HOMES = {
  HOUSE = true,
  REDS_HOUSE_1 = true,
  REDS_HOUSE_2 = true,
  BEACH_HOUSE = true,
}

local function isHome(map)
  if not (map and map.def) then return false end
  if Map.isOutdoor(map.def) then return false end
  local tileset = map.def.tileset
  return (tileset and Interiors.HOMES[tileset]) and true or false
end

-- ------- the hash
--
-- A small, stable string hash, and it is stable ACROSS SESSIONS on purpose:
-- love.math.random is seeded per run, and a pet that moved house between two
-- sessions would undo the whole point (see the header). Nothing here is
-- cryptographic and nothing needs to be -- it only has to give the same
-- answer for the same name every time, on every machine.
--
-- Multiply-and-add rather than the usual xor mix, and deliberately: this runs
-- on LuaJIT, where `~` is not an operator and `//` is not a division, so the
-- 5.3 spelling of a hash is a syntax error rather than a slow path. Plain
-- arithmetic under 2^31 stays exact in a double and needs no bit library.
local function hash(text, salt)
  local h = 5381
  local s = tostring(text) .. "|" .. tostring(salt or "")
  for i = 1, #s do
    h = (h * 33 + s:byte(i)) % 2147483647
  end
  return h
end

-- 0..1 from a hash, for a threshold; and an integer in 1..n, for a pick.
-- Different slices of the same number, so one hash answers both without the
-- two agreeing with each other.
local function unit(h) return (math.floor(h / 977) % 100000) / 100000 end
local function pick(h, n) return h % n + 1 end

-- ------- who is asleep in there
--
-- Companions and strays -- the same reasoning the TOWN row's pacifist pool
-- was picked on, minus everything that would not curl up indoors. Filtered
-- against the loaded dataset at spawn, so a total conversion without a
-- MEOWTH simply lands on another name.
Interiors.SLEEPERS = {
  "MEOWTH", "MEOWTH", "MEOWTH",     -- the cat asleep by the fire, three times
  "PIKACHU", "CLEFAIRY", "JIGGLYPUFF", "EEVEE", "VULPIX", "GROWLITHE",
  "PSYDUCK", "ODDISH", "SLOWPOKE", "RATTATA",
}

-- Roughly two houses in five have one -- and this is a threshold on a HASH
-- rather than on a die, so on any given map set it delivers whatever it
-- delivers instead of converging on the number. On Gen 1's own twenty-six
-- houses it lands eleven, of which one or two lose their pet to a room with
-- nowhere against a wall to sleep, so the shipped game sees nine or ten.
-- Tuned against the probe's own survey rather than picked: at 0.42 the same
-- twenty-six names only answered seven.
Interiors.PET_ODDS = 0.47

Interiors.SLEEP_LINES = {
  "%s is fast\nasleep.",
  "%s is curled up\nby the wall.",
  "%s stirs, then\ngoes back to sleep.",
  "%s is dreaming\nabout something.",
  "%s yawns and\nrolls over.",
}

-- ------- where it sleeps
--
-- Against a WALL and away from the DOOR, which between them keep a sleeping
-- animal out of the one route through a small room. A pet is a real entity
-- and real entities block, exactly like the street Pokemon do -- the answer
-- is not to make it walk-through (a cat you can stand inside is worse), it is
-- to put it where nobody was going to walk anyway.
--
-- Walked in a fixed order and chosen by hash rather than sampled at random,
-- so this answers the same cell every time it is asked about the same map.
local function bedCell(map, seed)
  local spots = {}
  for cy = 0, map.heightCells - 1 do
    for cx = 0, map.widthCells - 1 do
      if map:isWalkableCell(cx, cy) and not map:warpAtCell(cx, cy) then
        -- against something: at least one neighbour is not floor
        local walled = false
        for _, d in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
          local nx, ny = cx + d[1], cy + d[2]
          if not map:inBounds(nx, ny) or not map:isWalkableCell(nx, ny) then
            walled = true
          end
        end
        -- and clear of every door by two cells, so the way in is never it
        local nearDoor = false
        for _, w in ipairs(map.def.warps or {}) do
          if math.abs(w.x - cx) <= 1 and math.abs(w.y - cy) <= 1 then
            nearDoor = true
          end
        end
        if walled and not nearDoor then
          spots[#spots + 1] = { cx, cy }
        end
      end
    end
  end
  if #spots == 0 then return nil end
  local spot = spots[pick(seed, #spots)]
  return spot[1], spot[2]
end

-- ------- the mugs
--
-- Every cell in the room whose TOP-LEFT tile the shape profile calls a
-- tabletop. The top-left tile is the one the cell rules already judge a cell
-- by (TileShape.at), and a table's own art puts its surface there.
--
-- Recomputed on arrival and cached per map, because it cannot change: the
-- shapes come from the tileset and the tiles come from the block layer, and
-- a block edit invalidates far more than this (ChunkMesher.refresh) already.
local TABLETOPS = { table = true, counter = true }

local function mugCells(map)
  local ok, shapes = pcall(TileShape.forMap, map)
  if not ok or not shapes then return {} end
  local out = {}
  for cy = 0, map.heightCells - 1 do
    for cx = 0, map.widthCells - 1 do
      local tile = map:tileAt(cx * 2, cy * 2)
      local shape = tile and shapes[tile]
      if shape and TABLETOPS[shape.class] then
        -- about one tabletop cell in four carries a mug: a table with a mug
        -- on every square of it is a canteen, not a kitchen
        local h = hash(map.id, "mug" .. cx .. "," .. cy)
        if unit(h) < 0.26 then
          out[#out + 1] = {
            -- a spot ON the top rather than in the middle of the cell, and
            -- the tabletop's own drawn height (shape.h) is where it stands
            x = cx * 16 + 4 + (h % 7),
            z = cy * 16 + 4 + (math.floor(h / 7) % 7),
            y = (shape.h or 12) + 1,
            seed = unit(hash(map.id, "phase" .. cx .. "," .. cy)) * 6.2831,
          }
        end
      end
    end
  end
  return out
end

-- ------- state
--
-- Nothing here is written to a save. A pet exists for as long as the map it
-- belongs to is loaded, and is rebuilt from the same hash the next time --
-- which is the same thing as persisting it, without persisting anything.
local state = { mapId = nil, pet = nil, mugs = {} }

local function drop(ow, pet)
  for i = #(ow.npcs or {}), 1, -1 do
    if ow.npcs[i] == pet then table.remove(ow.npcs, i) end
  end
  for i = #(ow.entities or {}), 1, -1 do
    if ow.entities[i] == pet then table.remove(ow.entities, i) end
  end
end

local function sweep(ow)
  for i = #(ow.entities or {}), 1, -1 do
    local e = ow.entities[i]
    if e and e.housePet then drop(ow, e) end
  end
  for i = #(ow.npcs or {}), 1, -1 do
    local e = ow.npcs[i]
    if e and e.housePet then drop(ow, e) end
  end
  state.pet = nil
end

local function placePet(ow)
  local Game = game()
  local map = ow.map
  local seed = hash(map.id, "pet")
  if unit(seed) >= Interiors.PET_ODDS then return nil end

  local species
  for i = 0, 5 do
    local name = Interiors.SLEEPERS[pick(seed + i * 7919, #Interiors.SLEEPERS)]
    if Game.data.pokemon[name] then species = name break end
  end
  if not species then return nil end

  local def = RoamerArt.def(species, true)
  if not def then return nil end

  local cx, cy = bedCell(map, seed)
  if not cx then return nil end
  if Collision.occupied(ow.entities, cx, cy) then return nil end

  -- level 5 and never used: a sleeper is not a battler, and the field is
  -- only there because Roamer wants one
  local pet = Roamer.new(def, species, 5, "indoor", cx, cy)
  -- NOT a roamer (WildRoamers must not prune it, and walking into it must not
  -- start a fight) and not a town pet (CityLife's A-press is not this one).
  -- Asleep: frozen so the engine's npc walk never steps it, and `wanders`
  -- cleared so nothing else thinks it might.
  pet.roamer = nil
  pet.housePet = true
  pet.frozen = true
  pet.wanders = false
  pet.facing = "down"
  ow.npcs[#ow.npcs + 1] = pet
  ow.entities[#ow.entities + 1] = pet
  return pet
end

-- ------- per-frame
--
-- Rides the voxel pipeline's update hook like every other clock in this mod,
-- and does almost nothing on almost every frame: the room only changes when
-- the MAP does, so the whole body below is one comparison in the common case.
local failed = false

local function tick()
  local Game = game()
  local ow = Game and Game.overworld
  if not (ow and ow.map and ow.player and ow.npcs and ow.entities) then return end
  if Game.stack and Game.stack:top() ~= ow then return end
  if ow.transitioning then return end
  if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then return end

  if not (Interiors.enabled() and isHome(ow.map)) then
    if state.mapId ~= nil then
      sweep(ow)
      state.mapId, state.mugs = nil, {}
    end
    return
  end

  if state.mapId == ow.map.id then return end
  sweep(ow)
  state.mapId = ow.map.id
  state.mugs = mugCells(ow.map)
  -- the art bake can defer on the frame a species is first met (RoamerArt
  -- spends a budget per pass), and a nil pet here simply means the next
  -- arrival on this map gets one -- so the map id is left set either way and
  -- the room is not re-scanned every frame waiting for it
  state.pet = placePet(ow)
end

function Interiors.update()
  if failed then return end
  local ok, err = pcall(tick)
  if ok then return end
  failed = true
  V.mod.log:warn("interior life failed: %s -- the houses are empty for this "
                 .. "session", tostring(err))
  local Game = game()
  local ow = Game and Game.overworld
  if ow and ow.entities then pcall(sweep, ow) end
  state.mapId, state.mugs = nil, {}
end

-- ------- the draw
--
-- Inside the voxel overlay pass (main.lua's drawWorld), with the same project
-- function the ambient life anchors through: `scale` is pixels per world
-- pixel at the camera's focus and project's third return is this point's own
-- perspective correction, so a mug across the room is smaller than the one on
-- the near table for the same reason the table is.
--
-- Two drawings, and both are cel-shaded flat: hard-edged rectangles in two
-- tones, no gradients and no soft alpha ramps except the one that carries a
-- wisp away. A soft-edged puff of steam over a world made of voxels would be
-- the one thing on screen that looked like a photograph.
Interiors.STEAM_COLOR = { 0.93, 0.95, 0.98 }
Interiors.MUG_LIGHT = { 0.85, 0.86, 0.88 }
Interiors.MUG_DARK = { 0.42, 0.44, 0.50 }

-- How far a wisp climbs before it is gone, in world pixels, how long that
-- takes, and how many are in the air at once. Slow, because steam is slow and
-- a fast one reads as smoke -- but SHORT, which the probe's shots decided: at
-- eleven pixels the column climbed clear of the cup and read as four specks
-- floating near a mug rather than as steam coming off one. A plume has to
-- touch the thing it is coming out of.
Interiors.RISE = 7
Interiors.PERIOD = 2.0
Interiors.WISPS = 4

-- and how solid a wisp gets at its strongest. The first cut was 0.62, which
-- over a dark interior ceiling came out at about a fifth of white -- present
-- in the draw-call count and invisible on the screen, which is the exact
-- failure the battle HUD's ink taught this mod to check for.
Interiors.STEAM_ALPHA = 0.92

-- ------- the Zs
--
-- Over the sleeper's head, and drawn rather than written: the font's own
-- glyphs are black-with-alpha (setColor multiplies, so black stays black --
-- see the battle HUD's ink problem), and this is a pale mark on a room that
-- may be any shade. So it is three bars in a Z, which is legible at four
-- pixels and owes the charmap nothing.
Interiors.Z_COLOR = { 0.96, 0.97, 1.00 }
Interiors.Z_PERIOD = 3.2

local function drawZ(g, x, y, s, alpha)
  local c = Interiors.Z_COLOR
  local t = math.max(1, s * 0.35)
  g.setColor(c[1], c[2], c[3], alpha)
  g.rectangle("fill", x - s, y - s, s * 2, t)              -- top bar
  g.rectangle("fill", x - s, y + s - t, s * 2, t)          -- bottom bar
  -- the diagonal, as three steps: a rotated quad would be the only
  -- non-axis-aligned thing in the diorama
  g.rectangle("fill", x + s * 0.35, y - s + t, t, s * 0.7)
  g.rectangle("fill", x - s * 0.1, y - s * 0.2, t, s * 0.7)
  g.rectangle("fill", x - s * 0.6, y + s * 0.3, t, s * 0.7 - t)
end

function Interiors.draw(project, scale)
  if state.mapId == nil then return end
  if #state.mugs == 0 and not state.pet then return end
  local g = love.graphics
  local prevBlend, prevAlpha = g.getBlendMode()
  g.setBlendMode("alpha")
  local now = (love.timer and love.timer.getTime()) or 0

  -- ------- the mugs, and what is coming off them
  for _, mug in ipairs(state.mugs) do
    local sx, sy, ps = project(mug.x, mug.y, mug.z)
    if sx then
      local s = math.max(1, scale * (ps or 1))

      -- the cup: a two-tone block with a lighter rim, which is every mug
      -- anybody ever drew at this size
      local c = Interiors.MUG_DARK
      g.setColor(c[1], c[2], c[3], 0.95)
      g.rectangle("fill", sx - s * 1.1, sy - s * 2.2, s * 2.2, s * 2.2)
      c = Interiors.MUG_LIGHT
      g.setColor(c[1], c[2], c[3], 0.95)
      g.rectangle("fill", sx - s * 1.1, sy - s * 2.2, s * 2.2, s * 0.7)

      -- and four wisps, each a quarter of a cycle behind the last, so the
      -- column is continuous rather than a puff that restarts
      c = Interiors.STEAM_COLOR
      local n = Interiors.WISPS
      for i = 0, n - 1 do
        local k = ((now / Interiors.PERIOD) + mug.seed + i / n) % 1
        local hgt = k * Interiors.RISE
        local wx = math.sin((mug.seed + k * 6.2831) * 1.7) * 1.6 * k
        local wsx, wsy = project(mug.x + wx, mug.y + 1 + hgt, mug.z)
        if wsx then
          -- fades IN as it leaves the cup and OUT as it climbs, so no wisp
          -- ever pops on or off -- but it is at FULL strength through the
          -- middle third rather than only touching it at one instant, which
          -- is the difference between steam and a flicker
          local a = math.min(1, k * 6, (1 - k) * 2.2) * Interiors.STEAM_ALPHA
          local d = math.max(1, s * (0.6 + k * 0.8))
          g.setColor(c[1], c[2], c[3], a)
          g.rectangle("fill", wsx - d * 0.5, wsy - d * 0.5, d, d)
        end
      end
    end
  end

  -- ------- the sleeper's Zs
  --
  -- Anchored a little above and to the side of its head rather than dead
  -- centre, which is where a comic puts them and also keeps them off the
  -- sprite's own outline.
  local pet = state.pet
  if pet and not pet.dead then
    local k = (now / Interiors.Z_PERIOD) % 1
    -- Close to the head rather than off to the side: six world pixels is
    -- a little over a third of a cell, which clears the sprite's outline
    -- and still reads as belonging to it. The first cut put it at nine and
    -- eased the alpha to a single peak, and between the two the mark spent
    -- most of its cycle faint and half a cell away from the animal it was
    -- about -- countable in the draw calls and not findable on the screen.
    local sx, sy, ps = project(pet.px + 6, 18 + k * 8, pet.py - 2)
    if sx then
      local s = math.max(1, scale * (ps or 1)) * 1.8
      drawZ(g, sx, sy, s, math.min(1, k * 5, (1 - k) * 2.5) * 0.95)
    end
  end

  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  g.setColor(1, 1, 1, 1)
end

-- ------- pressing A at one
--
-- It stirs and settles: its own cry, a line about what it is doing, and
-- nothing else -- no battle, no catch, no menu. Chained behind the wraps
-- WildRoamers and CityLife already hold on this method (each checks its own
-- mark and passes everything else along), and idempotent for the same hot
-- reload reason.
local function speciesName(Game, species)
  local def = Game.data.pokemon[species]
  return (def and def.name) or species
end

local function talk(ow, pet)
  local Game = game()
  local TextBox = require("src.render.TextBox")
  pcall(function()
    local src = require("src.core.Sound").playCry(Game.data, pet.species)
    -- a sleepy cry: the same cry the species has, slowed down, which is what
    -- the engine's own GROWL does to one (Sound.playMoveCry)
    if src then pcall(src.setPitch, src, 0.78) end
  end)
  local line = Interiors.SLEEP_LINES[
    love.math.random(#Interiors.SLEEP_LINES)]
  Game.stack:push(TextBox.new(Game,
    Strings(line, speciesName(Game, pet.species))))
end

function Interiors.install()
  local OverworldState = require("src.world.OverworldController")
  if OverworldState.dramaticShapeIndoorHook then return end
  local inner = OverworldState.talkTo
  function OverworldState:talkTo(npc)
    if npc and npc.housePet and not npc.dead then
      pcall(talk, self, npc)
      return
    end
    return inner(self, npc)
  end
  OverworldState.dramaticShapeIndoorHook = true
end

return Interiors
