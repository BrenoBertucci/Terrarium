-- CHARGE: the parry's own fuel.
--
-- The concept board draws a CHARGE meter under the player's HP. It is spent on
-- one thing and one thing only: the parry (lib/BattleParry.lua). Moves are paid
-- for in PP, exactly as the game always paid for them -- a first cut of this
-- file also charged every move a COST read off its PP, and was taken back out
-- on the player's ruling: attacking is the game's economy, defending is this
-- one.
--
-- THE LOOP. A parry press spends PARRY_COST; every completed turn gives REGEN
-- back; a PERFECT refunds PARRY_GAIN. With the defaults (2 / 1 / 2) a player
-- who reads the foe on the beat can parry every single swing, and one who is
-- merely close can parry every other -- the meter is what turns the timing
-- into something worth practising instead of a coin flip each turn.
--
-- Switched off, the meter is not drawn and the parry is free.
--
-- The foe has no meter: it does not parry.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local BattleCharge = {}

BattleCharge.setting = ModSetting.new("battlecharge", "CHARGE",
                                      { "on", "off" }, { "LIGADO", "DESLIGADO" })

function BattleCharge.enabled()
  return BattleCharge.setting:get() ~= "off"
end

-- ------- the numbers (tuning knobs: the loop above is what they buy)
BattleCharge.MAX = 5
BattleCharge.START = 3
BattleCharge.REGEN = 1          -- per completed turn
BattleCharge.PARRY_COST = 2     -- per parry press, early presses included
BattleCharge.PARRY_GAIN = 2     -- refunded by a PERFECT

-- One battle's meter. Keyed on the battle object rather than stored on it:
-- the engine serialises battlers into checkpoints (src/core/BattleCheckpoint),
-- and a field this mod invented riding along in a save file is a field some
-- future build has to keep understanding.
local S = { battle = nil, ap = 0 }

local function sync(battle)
  if not battle then return nil end
  if S.battle ~= battle then
    S.battle, S.ap = battle, BattleCharge.START
  end
  return S
end

-- What the HUD draws. It has no battle to hand in -- BattleHudXY.read is given
-- a battler, which has no way back to the fight -- so an UNSYNCED meter
-- answers START rather than zero: START is exactly what it is about to be, and
-- zero would paint one frame of an empty meter at the top of every battle.
function BattleCharge.read()
  if not BattleCharge.enabled() then return nil, nil end
  if not S.battle then return BattleCharge.START, BattleCharge.MAX end
  return math.max(0, math.min(BattleCharge.MAX, S.ap or 0)), BattleCharge.MAX
end

-- Is there fuel for one parry? Off means free.
function BattleCharge.canParry(battle)
  if not BattleCharge.enabled() then return true end
  local s = sync(battle)
  return s ~= nil and s.ap >= BattleCharge.PARRY_COST
end

-- Pay for one parry press. True when it was paid (or the meter is off), false
-- when there is not enough -- the press is then refused, not graded.
function BattleCharge.payParry(battle)
  if not BattleCharge.canParry(battle) then return false end
  if BattleCharge.enabled() then
    local s = sync(battle)
    s.ap = s.ap - BattleCharge.PARRY_COST
  end
  return true
end

function BattleCharge.gain(battle, n)
  if not BattleCharge.enabled() then return end
  local s = sync(battle)
  if not s then return end
  s.ap = math.max(0, math.min(BattleCharge.MAX, s.ap + (n or 1)))
end

-- A fight ended: forget it, so the next one starts at START rather than at
-- whatever the last one left behind.
function BattleCharge.reset()
  S.battle, S.ap = nil, 0
end

-- ------- the seam: endOfTurn is the one beat that happens exactly once per
-- round, which is what REGEN is counted in.
function BattleCharge.install(BattleState)
  if BattleState.terrariumChargeHook then return end
  local innerEnd = BattleState.endOfTurn
  function BattleState:endOfTurn(...)
    BattleCharge.gain(self, BattleCharge.REGEN)
    return innerEnd(self, ...)
  end
  BattleState.terrariumChargeHook = true
end

-- OPTIONS row: cycle, and drop the live meter so a fight that continues with
-- the row switched back on starts from START rather than from a stale value.
function BattleCharge.setting:row()
  local self_ = self
  return {
    id = ((V.mod and V.mod.id) or "TERRARIUM") .. ":" .. self.key,
    label = self.label,
    value = function() return self_.labels[self_:read()] end,
    step = function(game, dir)
      self_:cycle(game, dir)
      BattleCharge.reset()
      return true
    end,
  }
end

function BattleCharge.onOptionsChanged(value)
  BattleCharge.setting:sync(value)
  BattleCharge.reset()
end

return BattleCharge
