-- Auto-farm: pick a Pokemon and a bot trains it.
--
-- The A-FARM row names a party slot. While it is set, a bot drives the
-- game the way a very patient player would:
--
--   on the map   it walks the tall grass (or a cave floor -- anywhere the
--                encounter records say wild Pokemon live). With the WILD
--                row on it hunts the visible ones: picks the nearest
--                roamer standing in the grass and walks INTO it, which is
--                the same bump that starts the fight for a player. With
--                WILD off it paces the grass and lets the engine's own
--                dice roll the encounters.
--
--   in a fight   it always picks the strongest move against what it is
--                actually facing -- power, STAB, the type chart and
--                accuracy, with the self-destructive and the situational
--                (Explosion, Dream Eater on something awake, charge
--                turns) discounted for what they are. If the trained
--                Pokemon drops low in a wild fight it runs instead.
--
--   at level-up  when a fifth move arrives, it answers the forget prompt
--                BY VALUE: the new move and the four known ones are
--                scored (damage output for attacks, a curated worth for
--                status moves, redundant same-type coverage discounted),
--                and the lowest-value move is the one forgotten -- unless
--                that would be the new move itself, in which case it is
--                politely declined. HM moves are never forgotten, exactly
--                as the engine forbids. Thunderbolt is never lost to
--                Growl.
--
-- The chosen Pokemon is swapped to the FRONT of the party first, because
-- Gen 1 gives its experience to the Pokemon that fought: the lead is the
-- one sent out, so the lead is the one that grows. The row follows the
-- swap (it reads P1 afterwards), so the menu never lies about which slot
-- is being trained.
--
-- The bot STOPS ITSELF -- and sets its own row OFF, so the state is
-- visible -- rather than grind a party into the ground: when the trained
-- Pokemon's HP falls low on the map, when it faints, when its damaging
-- moves are out of PP, or when there is nothing near to fight. It never
-- throws a ball, never uses an item, never touches the Safari Zone
-- (a Safari fight is immediately run from), and never presses a button
-- while a menu it does not recognise is open UNLESS a battle put it
-- there.
--
-- ------- how it presses buttons
--
-- Through the engine's own Input queue, on the engine's own boundary for
-- exactly this: Game:step runs the `input.step` hook "before Input:step
-- promotes queued edges so a button chosen here is visible to this logic
-- tick" -- the seam the engine documents for autoplay and driver mods,
-- which is what this is. A press lands in pressQueue, the step promotes it
-- to a real one-step edge, and every wasPressed reader consumes it exactly
-- as it would a thumb's; a held direction is Input.state, which is what
-- the overworld's isDown walk reads. Riding the logic step also means the
-- bot farms correctly under fast-forward, where the render-frame hooks
-- fall behind the game they would be driving.
--
-- Nothing here reaches into a menu's internals to MAKE it do things --
-- the one liberty taken is setting a menu's own cursor index before the
-- press, which the engine's update recomputes from row/col arithmetic
-- without complaint.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local TypeChart = require("src.battle.TypeChart")
local Collision = require("src.world.Collision")
local Strings = require("src.core.Strings")

local AutoFarm = {}

-- OFF first: a bot that drives the save is nothing to default on.
AutoFarm.setting = ModSetting.new("autofarm", "A-FARM",
                                  { "off", 1, 2, 3, 4, 5, 6 },
                                  { "OFF", "P1", "P2", "P3", "P4", "P5", "P6" })

local function game()
  return require("src.core.Game")
end

-- ------- state
local DIRS = { "up", "down", "left", "right" }
local state = {
  armed = false,        -- the chosen mon is at the front and being trained
  engaged = false,      -- a battle has been seen since the last free-roam frame
  cool = 0,             -- frames until the next press
  heldDir = nil,
  lastX = nil, lastY = nil, stuck = 0,
  pending = {},         -- synthetic presses whose state needs clearing
}

-- ------- the thumb
local function input()
  local Game = game()
  return Game and Game.input
end

local function releasePending()
  local inp = input()
  if not inp then return end
  for i = #state.pending, 1, -1 do
    local btn = state.pending[i]
    local sources = inp.sources and inp.sources[btn]
    if not (sources and next(sources)) then
      inp.state[btn] = false
    end
    table.remove(state.pending, i)
  end
end

local function press(btn)
  local inp = input()
  if not inp then return end
  inp.pressQueue[#inp.pressQueue + 1] = btn
  state.pending[#state.pending + 1] = btn
end

-- Hold exactly `dir` (or nothing). A real key the player is physically
-- holding is left alone -- its own release will clear it.
local function hold(dir)
  local inp = input()
  if not inp then return end
  for _, d in ipairs(DIRS) do
    if d ~= dir then
      local sources = inp.sources and inp.sources[d]
      if not (sources and next(sources)) then
        inp.state[d] = false
      end
    end
  end
  if dir then inp.state[dir] = true end
  state.heldDir = dir
end

-- ------- stopping
local function off(reason)
  local Game = game()
  hold(nil)
  state.armed, state.engaged = false, false
  state.lastX, state.lastY, state.stuck = nil, nil, 0
  if AutoFarm.setting:get() ~= "off" then
    AutoFarm.setting:setIndex(1, Game)
  end
  if reason and V.mod and V.mod.log then
    V.mod.log:info("auto-farm stopped: %s", reason)
  end
end

function AutoFarm.farming()
  return state.armed and AutoFarm.setting:get() ~= "off"
end

-- ------- scoring a move, in and out of battle
--
-- One function, two callers. In battle `foe` is the enemy battler and the
-- score is expected damage against IT; at the learn prompt there is no
-- enemy, so effectiveness is neutral and the score is the move's general
-- worth in this mon's hands.

-- What a zero-power move is worth, by effect. Tuned for a WILD-GRIND bot,
-- which is why the sweeping battle-openers (sleep, paralysis) score high
-- and the six-turn setup plays score low: a farmed fight is over in three
-- turns. HEAL is Recover/Softboiled/Rest and keeps the grind going, so it
-- keeps a high seat.
local STATUS_VALUE = {
  SLEEP_EFFECT = 55, PARALYZE_EFFECT = 45, HEAL_EFFECT = 50,
  SPECIAL_UP2_EFFECT = 45, ATTACK_UP2_EFFECT = 40, SPEED_UP2_EFFECT = 35,
  DEFENSE_UP2_EFFECT = 25, SUBSTITUTE_EFFECT = 25, CONFUSION_EFFECT = 25,
  POISON_EFFECT = 20, LEECH_SEED_EFFECT = 20, LIGHT_SCREEN_EFFECT = 20,
  REFLECT_EFFECT = 20, EVASION_UP1_EFFECT = 18, ATTACK_UP1_EFFECT = 15,
  SPECIAL_UP1_EFFECT = 15, DISABLE_EFFECT = 12, SPEED_UP1_EFFECT = 10,
  DEFENSE_UP1_EFFECT = 10, ACCURACY_DOWN1_EFFECT = 10, HAZE_EFFECT = 8,
  SPEED_DOWN1_EFFECT = 8, ATTACK_DOWN1_EFFECT = 6, DEFENSE_DOWN1_EFFECT = 6,
  SPECIAL_DOWN1_EFFECT = 6, EVASION_DOWN1_EFFECT = 5, TRANSFORM_EFFECT = 10,
  FOCUS_ENERGY_EFFECT = 5, MIST_EFFECT = 5, MIMIC_EFFECT = 5,
  CONVERSION_EFFECT = 3, TELEPORT_EFFECT = 2, ROAR_EFFECT = 2,
  SPLASH_EFFECT = 0,
}

-- The fixed-damage class has no power to read, so it gets a flat seat in
-- the same currency as `power * modifiers` below.
local FLAT_VALUE = {
  SPECIAL_DAMAGE_EFFECT = 45,   -- Seismic Toss, Night Shade, Dragon Rage
  SUPER_FANG_EFFECT = 40,
  OHKO_EFFECT = 20,             -- 30% accuracy already priced in
}

local function scoreMove(def, userTypes, foe)
  if not def then return 0 end
  local e = def.effect

  -- fixed damage first: the generated data gives these a power of 1 (the
  -- engine computes the real number from level or HP), so the power branch
  -- below would price a Seismic Toss like a Splash
  if FLAT_VALUE[e] then return FLAT_VALUE[e] end

  if (def.power or 0) <= 1 then
    local v = STATUS_VALUE[e]
    if v == nil then v = 8 end   -- an unknown status effect is worth a seat
    return v * 0.01              -- ...at the LEARN prompt; see the callers
  end

  local acc = (def.accuracy or 100) / 100
  local stab = 1
  for _, t in ipairs(userTypes or {}) do
    if t == def.type then stab = 1.5 end
  end
  local eff = 1
  if foe then
    -- TypeChart loads itself when a battle is built, which is the only
    -- time this branch runs with the game in play -- but a probe (or a
    -- future caller) may arrive first, so load on demand rather than
    -- assert on order
    local okE, e10 = pcall(TypeChart.effectiveness, def.type,
                           foe.curTypes or {})
    if not okE then
      local Game = game()
      if Game and Game.data then pcall(TypeChart.load, Game.data) end
      okE, e10 = pcall(TypeChart.effectiveness, def.type, foe.curTypes or {})
    end
    eff = okE and (e10 / 10) or 1
    if eff <= 0 then return 0 end
  end
  local s = (def.power or 0) * acc * stab * eff

  if e == "EXPLODE_EFFECT" then
    s = s * 0.05                 -- trading the farmed mon for one wild kill
  elseif e == "DREAM_EATER_EFFECT" then
    if foe and (not foe.mon or foe.mon.status ~= "SLP") then return 0 end
    s = s * 0.5                  -- needs a sleeper even at its best
  elseif e == "HYPER_BEAM_EFFECT" then
    s = s * 0.8                  -- the recharge turn
  elseif e == "CHARGE_EFFECT" or e == "FLY_EFFECT"
         or e == "RAZOR_WIND_EFFECT" then
    s = s * 0.55                 -- two turns for one hit
  elseif e == "JUMP_KICK_EFFECT" then
    s = s * 0.9                  -- crash damage on a miss
  elseif e == "TWO_TO_FIVE_ATTACKS_EFFECT" then
    s = s * 3                    -- power is per hit; three lands on average
  elseif e == "ATTACK_TWICE_EFFECT" then
    s = s * 2
  elseif e == "DRAIN_HP_EFFECT" then
    s = s * 1.15                 -- damage that also keeps the grind going
  elseif e == "RECOIL_EFFECT" then
    s = s * 0.85
  end
  return s
end

-- ------- the learn-a-move verdict
--
-- Five candidates, four seats. Every candidate is valued in the mon's own
-- hands (STAB, no particular enemy), then redundant coverage is discounted:
-- a damaging move whose type is already covered by a STRONGER damaging move
-- in the same set is worth much less than its raw number -- which is
-- exactly the judgment "don't replace Thunderbolt with Thundershock, do
-- replace Thundershock with Thunderbolt" needs, from either direction.
--
-- Status moves keep their curated worth (STATUS_VALUE is in the same 0..60
-- currency as discounted damage numbers), so a Growl (6) loses its seat to
-- any real attack, and a Sleep Powder (55) keeps its seat against most.
local HM_MOVES = {
  CUT = true, FLY = true, SURF = true, STRENGTH = true, FLASH = true,
}

local function hmMoves()
  local Game = game()
  local list = Game and Game.data and Game.data.constants
               and Game.data.constants.hmMoves
  if not list then return HM_MOVES end
  local out = {}
  for _, id in ipairs(list) do out[id] = true end
  return out
end

local function setValue(ids, moves, userTypes)
  local total = 0
  for _, id in ipairs(ids) do
    local def = moves[id]
    local v
    if def and FLAT_VALUE[def.effect] then
      v = FLAT_VALUE[def.effect]
    elseif def and (def.power or 0) > 1 then
      v = scoreMove(def, userTypes, nil)
      -- coverage discount: outclassed by a same-type attack in this set
      for _, other in ipairs(ids) do
        local od = other ~= id and moves[other]
        if od and not FLAT_VALUE[od.effect] and (od.power or 0) > 1
           and od.type == def.type
           and scoreMove(od, userTypes, nil) > v then
          v = v * 0.35
        end
      end
    elseif def then
      v = STATUS_VALUE[def.effect]
      if v == nil then v = 8 end
      -- two copies of the same status effect: the second seat is wasted
      for _, other in ipairs(ids) do
        local od = other ~= id and moves[other]
        if od and (od.power or 0) <= 1 and od.effect == def.effect then
          v = v * 0.5
          break
        end
      end
    else
      v = 0
    end
    total = total + v
  end
  return total
end

-- Which slot to forget for `newId`, or nil to decline the new move.
function AutoFarm.chooseForget(mon, newId)
  local Game = game()
  local moves = Game and Game.data and Game.data.moves
  if not (moves and moves[newId] and mon and mon.moves) then return nil end
  local hm = hmMoves()

  local Pokemon = Game.data.pokemon[mon.species]
  local userTypes = Pokemon and Pokemon.types or {}

  local ids = {}
  for i, mv in ipairs(mon.moves) do ids[i] = mv.id end

  -- baseline: decline, keep the four we have
  local best, bestSlot = setValue(ids, moves, userTypes), nil
  for slot = 1, #ids do
    if not hm[ids[slot]] then
      local trial = { unpack(ids) }
      trial[slot] = newId
      local v = setValue(trial, moves, userTypes)
      -- a strict improvement, with a nudge of hysteresis so the bot does
      -- not trade sideways on rounding
      if v > best * 1.02 + 0.5 then
        best, bestSlot = v, slot
      end
    end
  end
  return bestSlot
end

-- ------- in a fight
local function bestMoveIndex(battle)
  local user, foe = battle.player, battle.enemy
  local moves = battle.data and battle.data.moves
  if not (user and foe and moves) then return nil end
  local best, bestScore = nil, -1
  for i, mv in ipairs(user.curMoves or {}) do
    if (mv.pp or 0) > 0 and user.disabledSlot ~= i then
      local s = scoreMove(moves[mv.id], user.curTypes, foe)
      if s > bestScore then best, bestScore = i, s end
    end
  end
  return best, bestScore
end

-- exposed for the probe suite: which move the bot would pick, and why
AutoFarm.bestMove = bestMoveIndex

local function cool(n) state.cool = n end

local function battleTick(battle)
  state.engaged = true
  hold(nil)
  if state.cool > 0 then state.cool = state.cool - 1; return end

  local mon = battle.player and battle.player.mon
  -- the trained mon going down is the hard stop: the forced-replacement
  -- menu that follows belongs to the player, not to a bot that just lost
  -- the thing it was told to protect
  if mon and mon.hp <= 0 then off("the trained Pokemon fainted"); return end

  local phase = battle.phase
  if phase == "messages" then
    press("a"); cool(6); return
  end

  -- a Safari fight has no move menu and nothing to train on: leave
  if battle.safari then
    if phase == "menu" then
      battle.menuIndex = 4          -- RUN
      press("a"); cool(10)
    end
    return
  end

  if phase == "menu" then
    local low = mon and mon.stats and mon.stats.hp
                and (mon.hp / mon.stats.hp) < 0.25
    -- a fight the mon cannot win is not worth its PP either: every
    -- damaging move immune or empty (a Normal-only mon in the Tower's
    -- ghosts, say) reads as hopeless
    local _, score = bestMoveIndex(battle)
    local hopeless = (score or 0) < 1
    if (low or hopeless) and battle.kind == "wild" then
      if hopeless and not low then
        -- running from what it cannot hurt, again and again, is a loop:
        -- three in a row means this map's grass is simply immune to this
        -- moveset, and the row switches itself off instead of spinning
        state.hopeless = (state.hopeless or 0) + 1
        if state.hopeless >= 3 then
          off("the wild Pokemon here are immune to every damaging move")
          return
        end
      end
      battle.menuIndex = 4          -- RUN, and live to grind again
    else
      state.hopeless = 0
      battle.menuIndex = 1          -- FIGHT
    end
    press("a"); cool(10); return
  end

  if phase == "moveSelect" then
    local idx = bestMoveIndex(battle)
    if idx then
      battle.moveIndex = idx
      press("a")
    else
      press("b")                    -- no usable move: back out, let the
    end                             -- menu's own Struggle path answer
    cool(10); return
  end

  if phase == "mimicSelect" then
    press("a"); cool(10); return
  end
end

-- ------- on the map
local STEP = { up = { 0, -1 }, down = { 0, 1 },
               left = { -1, 0 }, right = { 1, 0 } }

-- Whether the bot is willing to step off `dir`: on the map, never onto a
-- warp (a bot that wanders into a Pokemon Center is farming nothing) and
-- never off the map's edge (a route connection is a warp with no tile).
local function safeDir(ow, dir)
  local p = ow.player
  local cx, cy = Collision.target(p.cellX, p.cellY, dir)
  local map = ow.map
  if not map:inBounds(cx, cy) then return false end
  if map:warpAtCell(cx, cy) then return false end
  return true
end

-- Is this cell somewhere wild Pokemon live? Grass on a route; any walkable
-- floor where the map keeps its encounters indoors (a cave, the Mansion).
local function wildFloor(ow)
  local Game = game()
  local map = ow.map
  local encDef = Game.data.encounters and Game.data.encounters[map.id]
  if not (encDef and encDef.grass and (encDef.grass.rate or 0) > 0) then
    return nil
  end
  local indoor = Game.data.field.indoorEncounters
  local isIndoor = indoor and map.def.index and indoor.firstIndoorMap
                   and map.def.index >= indoor.firstIndoorMap
                   and map.def.tileset ~= indoor.excludedTileset
  if isIndoor then return "floor" end
  if map.tileset and map.tileset.grassTile then return "grass" end
  return nil
end

local function cellFarms(ow, terrain, cx, cy)
  if terrain == "grass" then return ow.map:isGrassCell(cx, cy) end
  return terrain == "floor"
end

local function nearestRoamer(ow)
  local p = ow.player
  local best, bestD = nil, 1e9
  for _, e in ipairs(ow.entities or {}) do
    if e.roamer and not e.dead then
      local d = math.abs(e.cellX - p.cellX) + math.abs(e.cellY - p.cellY)
      if d < bestD then best, bestD = e, d end
    end
  end
  return best, bestD
end

-- Walk one axis toward (tx, ty), preferring the longer axis, falling back
-- to the other, falling back to anything safe. The anti-stuck below is
-- what rescues it from a dead end.
local function walkToward(ow, tx, ty)
  local p = ow.player
  local dx, dy = tx - p.cellX, ty - p.cellY
  local firstAxis = math.abs(dx) >= math.abs(dy)
  local prefer = {}
  if dx ~= 0 then prefer[#prefer + 1] = dx > 0 and "right" or "left" end
  if dy ~= 0 then prefer[#prefer + 1] = dy > 0 and "down" or "up" end
  if #prefer == 2 and not firstAxis then
    prefer[1], prefer[2] = prefer[2], prefer[1]
  end
  for _, dir in ipairs(prefer) do
    if safeDir(ow, dir) then hold(dir); return end
  end
  -- boxed on both wanted axes: any safe direction beats standing still
  local order = { DIRS[love.math.random(4)], DIRS[love.math.random(4)] }
  for _, dir in ipairs(order) do
    if safeDir(ow, dir) then hold(dir); return end
  end
  hold(nil)
end

-- Pace the wild ground: keep walking while the next cell farms, otherwise
-- turn toward a neighbouring cell that does.
local function pace(ow, terrain)
  local p = ow.player
  local dir = state.heldDir
  if dir and safeDir(ow, dir) then
    local cx, cy = Collision.target(p.cellX, p.cellY, dir)
    if cellFarms(ow, terrain, cx, cy) and ow.map:isWalkableCell(cx, cy)
       and love.math.random(12) > 1 then    -- an occasional turn, for the look
      hold(dir)
      return
    end
  end
  local shuffled = { DIRS[1], DIRS[2], DIRS[3], DIRS[4] }
  for i = 4, 2, -1 do
    local j = love.math.random(i)
    shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
  end
  for _, d in ipairs(shuffled) do
    if safeDir(ow, d) then
      local cx, cy = Collision.target(p.cellX, p.cellY, d)
      if cellFarms(ow, terrain, cx, cy) and ow.map:isWalkableCell(cx, cy) then
        hold(d)
        return
      end
    end
  end
  hold(nil)
end

-- Find wild ground to stand on when the bot is not already on it: the
-- nearest farmable cell in a spiral of rings around the player.
local function nearestWildCell(ow, terrain)
  local p = ow.player
  for r = 1, 12 do
    for dy = -r, r do
      for dx = -r, r do
        if math.max(math.abs(dx), math.abs(dy)) == r then
          local cx, cy = p.cellX + dx, p.cellY + dy
          if ow.map:inBounds(cx, cy) and ow.map:isWalkableCell(cx, cy)
             and not ow.map:warpAtCell(cx, cy)
             and cellFarms(ow, terrain, cx, cy) then
            return cx, cy
          end
        end
      end
    end
  end
  return nil
end

-- The medicine cabinet, weakest first: the cheap potions are burned before
-- the FULL RESTOREs the player is saving for the Elite Four.
local POTIONS = {
  "POTION", "SUPER_POTION", "HYPER_POTION", "MAX_POTION", "FULL_RESTORE",
}

-- One sip from the bag, through the engine's own ItemEffects -- so the
-- heal cap, the Heal_HP sound and the Pikachu-happiness bump are exactly
-- what a player's use would have been -- and the engine's own Bag.remove,
-- so the slot count and the bag order stay honest.
local function tryPotion(Game, mon)
  local inv = Game.save.inventory or {}
  for _, id in ipairs(POTIONS) do
    if (inv[id] or 0) > 0 then
      local ItemEffects = require("src.inventory.ItemEffects")
      local result = ItemEffects.use(Game.data, Game.save, id, mon)
      if result == "consumed" then
        require("src.inventory.Bag").remove(Game.save, id, 1)
        if V.mod and V.mod.log then
          V.mod.log:info("auto-farm: used a %s", id)
        end
        return true
      end
    end
  end
  return false
end

local function overworldTick(ow)
  state.engaged = false
  if ow.transitioning then hold(nil); return end
  -- a script owns the cast (a trainer marching over, a cutscene): stand
  -- still and let it finish -- its dialog is genericTick's to advance
  if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then
    hold(nil)
    return
  end

  local Game = game()
  local mon = Game.save.party[1]
  if not mon then off("the party is empty"); return end
  if mon.hp <= 0 then off("the trained Pokemon fainted"); return end
  -- Below half health the bot drinks from the bag before it walks on --
  -- one potion per beat, until the mon is topped back over the line, which
  -- is what makes the farm genuinely AFK. It stops (and switches the row
  -- off) only when the HP is critical AND the bag has nothing left to
  -- give.
  if mon.stats and mon.stats.hp and mon.stats.hp > 0 then
    local frac = mon.hp / mon.stats.hp
    if frac < 0.5 then
      if state.potionCool and state.potionCool > 0 then
        state.potionCool = state.potionCool - 1
        hold(nil)
        return
      end
      if tryPotion(Game, mon) then
        state.potionCool = 20      -- a beat between sips, for the sound
        hold(nil)
        return
      end
      if frac < 0.25 then
        off("HP is low and the bag has no potions -- heal up first")
        return
      end
    end
  end
  -- out of damaging PP: the next fight would be Struggle
  local hasPP = false
  local moves = Game.data.moves
  for _, mv in ipairs(mon.moves or {}) do
    local def = moves[mv.id]
    if def and (def.power or 0) > 0 and (mv.pp or 0) > 0 then
      hasPP = true
      break
    end
  end
  if not hasPP then off("no PP left on any damaging move"); return end

  local terrain = wildFloor(ow)
  if not terrain then
    off("this map has no wild Pokemon to farm")
    return
  end

  -- anti-stuck: three seconds without moving a cell means walled in;
  -- shake loose in a random safe direction
  local p = ow.player
  if p.cellX == state.lastX and p.cellY == state.lastY then
    state.stuck = state.stuck + 1
  else
    state.stuck = 0
    state.lastX, state.lastY = p.cellX, p.cellY
  end
  if state.stuck > 180 then
    state.stuck = 0
    local d = DIRS[love.math.random(4)]
    if safeDir(ow, d) then hold(d) end
    return
  end

  -- hunt the visible ones first: walking INTO a roamer is the same bump
  -- that starts the fight for a player (WildRoamers.bumped)
  local roamer, dist = nearestRoamer(ow)
  if roamer and dist <= 24 then
    walkToward(ow, roamer.cellX, roamer.cellY)
    return
  end

  -- no one visible: stand in the wild ground and pace it. If the WILD row
  -- is off this is where the engine's own dice roll on every step; if it
  -- is on, pacing is what carries the bot until the next roamer walks in
  -- from off the edge.
  if cellFarms(ow, terrain, p.cellX, p.cellY) then
    pace(ow, terrain)
  else
    local tx, ty = nearestWildCell(ow, terrain)
    if tx then
      walkToward(ow, tx, ty)
    else
      off("no wild ground within reach")
    end
  end
end

-- ------- between the two: text boxes, evolution, level-up screens
--
-- Only pressed through when a battle put the screen there (state.engaged)
-- or a map script did (a trainer walking over to say "I like shorts!" is a
-- dialog the fight is waiting behind, and the bot cannot be seen without
-- being stopped by it). The player opening their own START menu mid-farm
-- is neither, and does not get a bot mashing A inside it.
local function genericTick(ow)
  local scripted = ow and ow.runner and ow.runner.isRunning
                   and ow.runner:isRunning()
  if not (state.engaged or scripted) then return end
  if state.cool > 0 then state.cool = state.cool - 1; return end
  press("a")
  cool(10)
end

-- ------- arming: the chosen mon leads the party
local function arm(Game, ow)
  local sel = AutoFarm.setting:get()
  if sel == "off" then return false end
  local party = Game.save.party
  local slot = tonumber(sel) or 1
  local mon = party[slot]
  if not mon then
    off(("party slot %d is empty"):format(slot))
    return false
  end
  if slot ~= 1 then
    -- only on solid ground: never reorder a party mid-battle or mid-warp
    if not (Game.stack and Game.stack:top() == ow) or ow.transitioning then
      return false
    end
    party[1], party[slot] = party[slot], party[1]
    AutoFarm.setting:setIndex(2, Game)      -- index 2 is P1: follow the swap
    if V.mod and V.mod.log then
      V.mod.log:info("auto-farm: %s moved to the front of the party",
                     tostring(mon.nickname or mon.species))
    end
  end
  state.armed = true
  return true
end

-- ------- per-frame, from the voxel pipeline's update hook
--
-- Same survival rule as WildRoamers: nothing a bot can get wrong is worth
-- the diorama, so a throw retires the feature for the session and puts the
-- controls back in the player's hands.
local failed = false

local function tick()
  local Game = game()
  if not (Game and Game.save and Game.save.party) then return end
  releasePending()

  if AutoFarm.setting:get() == "off" then
    if state.armed or state.heldDir then
      hold(nil)
      state.armed, state.engaged = false, false
    end
    return
  end

  local ow = Game.overworld
  if not ow then return end
  if not state.armed and not arm(Game, ow) then return end

  local top = Game.stack and Game.stack:top()
  if top == ow then
    overworldTick(ow)
  elseif top and top.phase and top.player and top.enemy then
    battleTick(top)
  else
    hold(nil)
    genericTick(ow)
  end
end

function AutoFarm.update()
  if failed then return end
  local ok, err = pcall(tick)
  if ok then return end
  failed = true
  pcall(hold, nil)
  if V.mod and V.mod.log then
    V.mod.log:warn("auto-farm failed: %s -- the bot is off for this session",
                   tostring(err))
  end
end

-- ------- the one seam: the forget-a-move prompt
--
-- Every path that teaches a full mon a move -- level-up in battle,
-- evolution's own learnset check -- funnels through MoveLearnMenu, and its
-- enter() is the moment the prompt would stop a bot dead. While the farm
-- is running it is answered by value instead (chooseForget above); with the
-- farm off, enter() is the engine's own, untouched. The replacement writes
-- the same record the menu's own A-press writes and leaves through the same
-- finish(), so the "1, 2 and... Poof!" text, the onDone chain and the
-- stack are exactly as a player's answer leaves them.
function AutoFarm.install()
  local MoveLearnMenu = require("src.ui.MoveLearnMenu")
  if MoveLearnMenu.dramaticShapeFarmHook then return end
  local inner = MoveLearnMenu.enter
  function MoveLearnMenu:enter()
    if not AutoFarm.farming() then return inner(self) end
    local ok, err = pcall(function()
      local slot = AutoFarm.chooseForget(self.mon, self.newMoveId)
      if slot then
        local old = self.mon.moves[slot]
        local mdef = self.game.data.moves[self.newMoveId]
        self.forgot = self.game.data.moves[old.id].name
        self.mon.moves[slot] = { id = self.newMoveId, pp = mdef.pp }
        self:finish(true)
      else
        self:finish(false)
      end
    end)
    if not ok then
      if V.mod and V.mod.log then
        V.mod.log:warn("auto-farm learn verdict failed: %s", tostring(err))
      end
      return inner(self)
    end
  end
  MoveLearnMenu.dramaticShapeFarmHook = true
end

return AutoFarm
