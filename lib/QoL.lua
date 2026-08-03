-- Quality of life: three small mercies, one row.
--
--   TYPE HINTS   in battle, every damaging move on the FIGHT menu carries a
--                marker against the Pokemon actually standing there: a
--                green + where it hits super effective, a grey - where it
--                is resisted, a red x where it cannot touch. Computed from
--                the same TypeChart the damage formula reads, so the hint
--                can never disagree with the number. The official games
--                took until 2019 to do this.
--
--   AUTO-REPEL   when a Repel is one step from wearing off and the bag
--                holds another, it is used -- weakest first, through the
--                engine's own ItemEffects so the step counter, the message
--                and the bag bookkeeping are exactly a player's. A line of
--                text says so (silently, into the log, while the auto-farm
--                bot owns the controls -- a text box would stop it).
--
--   HMs ON A     press A at a cuttable tree and CUT happens; press A
--                facing water and SURF mounts; press A at a boulder and
--                STRENGTH wakes up. No menu, no party list, no submenu.
--                Every gate the party menu applies still applies -- the
--                badge, the move in the party, the engine's own
--                side-effect-free checks (useCutFieldMove /
--                useSurfFieldMove) -- so this cannot do anything the menu
--                would have refused. It only skips the walk through it.
--
-- The A-press additions are deliberately conservative about what an A
-- press MEANS. An NPC (or a roamer, or a street Pokemon) at the facing
-- cell always wins -- nothing here runs at all. Tall grass is excluded
-- from auto-CUT even though the menu allows it, because A in a meadow is
-- for talking to what is standing in it, not for mowing it. And while
-- already surfing, A keeps its vanilla meaning entirely -- walking onto
-- the shore is how a surf ends.
--
-- One OPTIONS row, ON/OFF, because every one of these changes what the
-- game does on input, and a purist should get to keep the 1996 frictions.
-- (The auto-farm's own potion-sipping lives in AutoFarm and is not gated
-- here: a bot that was told to farm is already past purism.)

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local AutoFarm = V.require("AutoFarm")

local Strings = require("src.core.Strings")

local QoL = {}

QoL.setting = ModSetting.new("qol", "QOL", { "on", "off" }, { "ON", "OFF" })

function QoL.enabled()
  return QoL.setting:get() == "on"
end

local function game()
  return require("src.core.Game")
end

-- ------- the type hints
--
-- Drawn OVER the classic move menu, after the engine's own drawTextArea
-- has laid it out: names start at column 6 (x=48), one row of 8 per move,
-- so the marker lands flush after each name. The longest Gen 1 move name
-- is 12 characters, which puts its marker at x=144 -- the last interior
-- column of the (4,12) 16-wide box -- so nothing can ever land on the
-- border. One character always, for that reason.
local function drawHints(battle, foe)
  local Font = require("src.render.Font")
  local TypeChart = require("src.battle.TypeChart")
  local g = love.graphics
  for i, mv in ipairs(battle.player.curMoves) do
    local def = battle.data.moves[mv.id]
    -- damaging moves only: a status move has no matchup to hint, and the
    -- fixed-damage class (power 1 in the data) ignores type entirely
    if def and (def.power or 0) > 1 then
      local ok, eff = pcall(TypeChart.effectiveness, def.type,
                            foe.curTypes or {})
      if ok then
        local mark
        if eff == 0 then
          g.setColor(0.72, 0.13, 0.13, 1)
          mark = "x"
        elseif eff > 10 then
          g.setColor(0.10, 0.48, 0.16, 1)
          mark = "+"
        elseif eff < 10 then
          g.setColor(0.47, 0.47, 0.47, 1)
          mark = "-"
        end
        if mark then
          Font.draw(mark, 48 + #(def.name or "") * 8, 96 + i * 8)
        end
      end
    end
  end
  g.setColor(0, 0, 0, 1)
end

-- ------- auto-repel
--
-- Watched rather than hooked: the step counter is decremented in the
-- middle of onStepComplete with no seam of its own, but the value is a
-- plain field, and one frame at 1 is the whole signal -- the engine only
-- shows "wore off" at 0, so acting at 1 replaces the expiry before it can
-- happen. Weakest repel first, so the cheap ones are burned before the
-- MAX the player is saving.
local REPELS = { "REPEL", "SUPER_REPEL", "MAX_REPEL" }

local function autoRepel(Game, ow)
  if (Game.save.repelSteps or 0) ~= 1 then return end
  local inv = Game.save.inventory or {}
  for _, id in ipairs(REPELS) do
    if (inv[id] or 0) > 0 then
      local ItemEffects = require("src.inventory.ItemEffects")
      local Bag = require("src.inventory.Bag")
      local result = ItemEffects.use(Game.data, Game.save, id)
      if result == "consumed" then
        Bag.remove(Game.save, id, 1)
        local item = Game.data.items[id]
        local name = (item and item.name) or id
        if AutoFarm.farming() then
          -- a text box would stop the bot dead waiting for an A press;
          -- the log carries the fact instead
          if V.mod and V.mod.log then
            V.mod.log:info("auto-repel: used another %s", name)
          end
        else
          local TextBox = require("src.render.TextBox")
          Game.stack:push(TextBox.new(Game,
            Strings("REPEL wore off.\f%s used\nanother %s!",
                    Game.save.player.name, name)))
        end
      end
      return
    end
  end
end

-- ------- per-frame, from the voxel pipeline's update hook
--
-- Same survival contract as every other feature: a throw retires QoL for
-- the session, never the diorama.
local failed = false

local function tick()
  if not QoL.enabled() then return end
  local Game = game()
  local ow = Game and Game.overworld
  if not (ow and ow.map and Game.save and Game.stack) then return end
  if Game.stack:top() ~= ow then return end
  if ow.transitioning then return end
  autoRepel(Game, ow)
end

function QoL.update()
  if failed then return end
  local ok, err = pcall(tick)
  if ok then return end
  failed = true
  if V.mod and V.mod.log then
    V.mod.log:warn("QoL failed: %s -- off for this session", tostring(err))
  end
end

-- ------- HMs on the A button
--
-- Everything below runs BEFORE the engine's own interact, and only when
-- nothing is standing at the facing cell -- an NPC's claim on the A button
-- always wins. The checks are the engine's own side-effect-free ones, and
-- the badges are the same gates the party menu applies at list time.
local function fieldMoveA(ow)
  local Game = game()
  local p = ow.player
  local fx, fy = p:facingCell()
  if not ow.map:inBounds(fx, fy) then return false end
  if ow:npcAtCell(fx, fy) then return false end

  -- CUT, on the tree and the gym plant only. Tall grass is deliberately
  -- excluded even though the menu would allow it: an A press in a meadow
  -- is for talking to what is standing in it, not for mowing it (and this
  -- mod stands things in it).
  local ts = ow.map.def.tileset
  local tile = ow.map:cellTile(fx, fy)
  local cuttable = (ts == "OVERWORLD" and tile == 0x3d)
                   or (ts == "GYM" and tile == 0x50)
  if cuttable and Game.save.inventory.CASCADEBADGE
     and ow:useCutFieldMove() == "ok" then
    ow:tryCut(fx, fy)
    return true
  end

  -- SURF, mounting only: while already surfing the A button keeps its
  -- vanilla meaning, and walking onto the shore is how a surf ends
  if not p.surfing and Game.save.inventory.SOULBADGE
     and ow:useSurfFieldMove() == "ok" then
    ow:trySurf(fx, fy)
    return true
  end

  return false
end

function QoL.install()
  local OverworldState = require("src.world.OverworldController")
  local BattleState = require("src.battle.BattleState")
  local Map = require("src.world.Map")

  -- A at a tree / the water
  if not OverworldState.dramaticShapeQolHook then
    local inner = OverworldState.interact
    function OverworldState:interact()
      if QoL.enabled() then
        local ok, handled = pcall(fieldMoveA, self)
        if ok and handled then return end
      end
      return inner(self)
    end
    OverworldState.dramaticShapeQolHook = true
  end

  -- A at a boulder: STRENGTH wakes up, exactly as the party menu would
  -- have woken it -- the same flag, the same one-map lifetime (cleared on
  -- every map load, like the original's BIT_STRENGTH_ACTIVE). Once it is
  -- active the wrap stands down and the boulder's own text answers again.
  if not OverworldState.dramaticShapeQolBoulderHook then
    local inner = OverworldState.talkTo
    function OverworldState:talkTo(npc)
      if QoL.enabled() and npc and npc.def and Map.isPushable(npc.def)
         and not self.strengthActive then
        local Game = game()
        local mon = Game.save.inventory.RAINBOWBADGE
                    and self:partyKnows("STRENGTH")
        if mon then
          self.strengthActive = true
          local name = mon.nickname
                       or Game.data.pokemon[mon.species].name
          local TextBox = require("src.render.TextBox")
          Game.stack:push(TextBox.new(Game,
            Strings("%s used\nSTRENGTH!\fIt can move\nboulders around!",
                    name)))
          return
        end
      end
      return inner(self, npc)
    end
    OverworldState.dramaticShapeQolBoulderHook = true
  end

  -- the type hints, over the classic move menu. The wide layout draws its
  -- move grid in WideBattle and is left alone -- staged battles pin the
  -- layout to OG anyway (see main.lua), which is where this mod lives.
  if not BattleState.dramaticShapeHintHook then
    local inner = BattleState.drawTextArea
    function BattleState:drawTextArea()
      inner(self)
      if not QoL.enabled() then return end
      if self.phase ~= "moveSelect" or self:wideLayout() then return end
      -- the unnamed ghost keeps its mystery: hinting "your Normal moves
      -- cannot touch it" is the Silph Scope's reveal, answered early
      if self.ghost then return end
      local foe = self.enemy
      if foe and foe.curTypes then pcall(drawHints, self, foe) end
    end
    BattleState.dramaticShapeHintHook = true
  end

  QoL.installPoisonMercy(OverworldState)
end

-- ------- RUN: hold B and the walk is a jog
--
-- The engine put a hook here on purpose -- `movement.speed`, whose own
-- comment names "running shoes, dash" as the reason it exists -- so this is
-- the documented front door rather than a wrap on Player:tryMove.
--
-- It is NOT the GAME SPEED row, and the difference is the point. That row
-- runs the whole game faster: battles, text, animations, the lot. This is
-- the overworld walk and nothing else, so the parts of the game that are
-- paced on purpose stay paced.
--
-- Ten frames a step against the walk's sixteen. Deliberately NOT the bike's
-- eight: the bicycle is an item you go and get, it is faster than this, and
-- a mod that made walking match it would have quietly deleted it. And while
-- the bike IS under you this stands down entirely, for the same reason.
--
-- B, because on the overworld B is the button that does nothing. It is
-- cancel in every menu and run-away in every battle, and neither of those
-- reaches this hook -- Player:tryMove is only called from a free-roam step.
QoL.RUN_FRAMES = 10

function QoL.runSpeed(frames, ctx)
  if not QoL.enabled() then return frames end
  if ctx and ctx.onBike then return frames end     -- the bike is faster; leave it
  if ctx and ctx.surfing then return frames end    -- surfing has its own pace
  local input = ctx and ctx.input
  if not (input and input.isDown) then return frames end
  local ok, held = pcall(input.isDown, input, "b")
  if not (ok and held) then return frames end
  -- never SLOWER than we found it: a mod ahead of this one that already
  -- sped the step up keeps its answer
  return math.min(frames or 16, QoL.RUN_FRAMES)
end

-- ------- POISON stops at 1 HP instead of killing
--
-- Field poison in Gen 1 takes 1 HP every fourth step and will walk a
-- Pokemon all the way to nothing -- and a whole party to a black-out, which
-- costs money and puts you back at the last Center. Gen 4 stopped it at 1
-- HP and nobody has ever wanted it back.
--
-- Done WITHOUT touching the damage loop, which also handles the faint
-- messages, the Pikachu happiness penalty and the black-out: a mon that
-- would die is simply not poisoned as far as that loop can see. Its status
-- is lifted for the length of the call and put straight back, so it stays
-- poisoned -- it still needs an Antidote, it just cannot be killed by the
-- walk there.
--
-- The wrap only ever REMOVES damage, so nothing downstream can be surprised
-- by it: a step that hurt nobody is a step the original also allowed.
-- A field on QoL rather than a `local function`, and not for style: install()
-- above calls this, and a `local` declared further down the file is a nil
-- GLOBAL to everything above it -- silently, until the first call. A field is
-- looked up when it is called, so the order stops mattering.
function QoL.installPoisonMercy(OverworldState)
  if OverworldState.dramaticShapeQolPoisonHook then return end
  local inner = OverworldState.applyFieldPoison
  if not inner then return end

  function OverworldState:applyFieldPoison()
    if not QoL.enabled() then return inner(self) end
    local Game = require("src.core.Game")
    local party = Game.save and Game.save.party or {}
    local held = nil
    for _, mon in ipairs(party) do
      if mon.status == "PSN" and (mon.hp or 0) <= 1 then
        held = held or {}
        held[#held + 1] = mon
        mon.status = nil
      end
    end
    if not held then return inner(self) end
    local ok, out = pcall(inner, self)
    for _, mon in ipairs(held) do mon.status = "PSN" end
    if not ok then error(out, 0) end
    return out
  end

  OverworldState.dramaticShapeQolPoisonHook = true
end

-- ------- TRADE evolutions, without a second console
--
-- Kadabra, Machoke, Graveler and Haunter evolve by TRADE and by nothing
-- else, which on a single machine means they do not evolve at all. Four
-- species -- Alakazam, Machamp, Golem, Gengar -- are simply not in a solo
-- game. That is not difficulty, it is a hardware assumption from 1996 that
-- stopped being true.
--
-- So the TRADE method learns to answer a level-up as well. Through the
-- engine's own `evolution.check` hook, which exists to "cancel or force any
-- evolution" in as many words -- no evolution code is touched, and a real
-- link trade still evolves them the moment it completes, because the
-- original check is asked FIRST and its yes is final.
--
-- One level for all four, and 37 because that is where the games themselves
-- put the equivalent stone-and-level evolutions of that power tier. Change
-- the number here and every trade evolution moves with it.
QoL.TRADE_LEVEL = 37

function QoL.tradeEvolution(should, game, mon, evo, trigger)
  if should then return should end            -- a real trade already said yes
  if not QoL.enabled() then return should end
  if not (evo and evo.method == "TRADE") then return should end
  if not (trigger and trigger.kind == "levelup") then return should end
  if not (mon and (mon.level or 0) >= QoL.TRADE_LEVEL) then return should end
  return true
end

return QoL
