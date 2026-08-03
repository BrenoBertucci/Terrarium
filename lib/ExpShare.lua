-- Experience for the whole team.
--
-- Gen 1 pays the Pokemon that FOUGHT, and nothing else. That one rule is
-- the reason a Gen 1 party is really one Pokemon and five passengers: the
-- only way to bring a second one along is to send it out, let it take a
-- hit, and switch back -- every battle, six times over, for the whole game.
-- Nobody enjoys that. It is not difficulty, it is bookkeeping, and the
-- series itself deleted it: by Gen 6 the EXP. SHARE is a switch you flip
-- once and the party levels together.
--
-- This is that switch. Three rungs:
--
--   TEAM   every Pokemon still standing gets what the fighters got. The
--          party keeps pace with the lead and the swap-in tax is gone.
--   SPLIT  the same total is divided among everyone still standing, so
--          six Pokemon level six times slower each. The party still moves
--          together; the CURVE is the one the game was balanced on.
--   OFF    the original's rule, exactly.
--
-- TEAM is first, so it is the default and what an unreadable stored value
-- falls back to -- this row exists because the default is worth changing.
--
-- ------- through the engine's own front door
--
-- `battle.exp_award` is a hook the engine put there for precisely this. Its
-- own comment names the case: "so a mod can replace it wholesale (e.g. a
-- flat undivided share to every non-fainted party mon) without re-deriving
-- participants/alive". So nothing here computes experience, reads a growth
-- rate, or touches a level: `ctx.applyShare(mon, split, announce)` is the
-- same helper vanilla uses, and the only thing this file decides is WHO it
-- is called for and with what divisor.
--
-- What that buys is that everything downstream still happens by itself --
-- the level-up jingle, the stat box, the move a Pokemon learns on the way
-- up, the evolution check after the battle. A mod that had added experience
-- by writing to `mon.exp` would have had to reproduce all of it and would
-- have got one of them wrong.
--
-- ------- and the text, which is where a good idea turns into a bad one
--
-- `announce` is what prints "X gained N EXP. Points!". Vanilla's EXP.ALL
-- announces for EVERY mon, which is six text boxes to press through after
-- every single fight -- and this row exists to remove friction, so shipping
-- it that way would have traded a swap for a swap's worth of button
-- presses.
--
-- So only the Pokemon that FOUGHT announces. The rest are paid silently and
-- the player finds out the way they would want to: the party is a few
-- levels higher next time they look at it. The exp is real either way; what
-- is dropped is the paperwork.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local ExpShare = {}

ExpShare.setting = ModSetting.new("expshare", "EXP",
                                  { "team", "split", "off" },
                                  { "TEAM", "SPLIT", "OFF" })

function ExpShare.enabled()
  return ExpShare.setting:get() ~= "off"
end

function ExpShare.row()
  return ExpShare.setting:row()
end

-- Whether this mon took part in the fight, so it is the one that gets the
-- line of text. `ctx.alive` is the engine's own list of participants that
-- can still be paid; everybody else on the party is along for the ride.
local function fought(ctx, mon)
  for _, m in ipairs(ctx.alive or {}) do
    if m == mon then return true end
  end
  return false
end

-- The award, replacing the engine's own. Called with the vanilla function
-- as `next` so OFF is a straight pass-through -- byte-identical to the mod
-- not being installed, EXP.ALL and all.
function ExpShare.award(next, ctx)
  local mode = ExpShare.setting:get()
  if mode == "off" or not ctx or not ctx.applyShare then return next(ctx) end

  local Game = require("src.core.Game")
  local party = (Game.save and Game.save.party) or {}
  local standing = {}
  for _, mon in ipairs(party) do
    -- fainted mons are paid nothing, which is the one part of the original
    -- rule worth keeping: a Pokemon that was knocked out did not learn
    -- anything from the fight it lost
    if (mon.hp or 0) > 0 then standing[#standing + 1] = mon end
  end
  if #standing == 0 then return next(ctx) end

  -- TEAM: the participants' own divisor for everybody, so a Pokemon left in
  -- the party earns what the one that fought earned.
  -- SPLIT: that divisor times the number standing, so the same total is
  -- shared out and the game's own pace survives.
  local split = math.max(1, ctx.participants or 1)
  if mode == "split" then split = split * #standing end

  for _, mon in ipairs(standing) do
    -- marked BEFORE the first payment, not after: the installer below falls
    -- back to the vanilla award if this throws, and a throw halfway down the
    -- party would otherwise pay the fighters twice
    ExpShare.paid = true
    ctx.applyShare(mon, split, fought(ctx, mon))
  end
end

function ExpShare.install(mod)
  -- next() FIRST is deliberately NOT what happens here, and this is the one
  -- hook in the mod where that is right: this REPLACES the award rather
  -- than decorating it, and calling vanilla as well would pay the
  -- participants twice. OFF calls next() and nothing else, which is the
  -- pass-through every other rung's absence would give.
  mod.hooks:wrap("battle.exp_award", function(next, ctx)
    ExpShare.paid = false
    local ok, err = pcall(ExpShare.award, next, ctx)
    if ok then return end
    if V.mod and V.mod.log then
      V.mod.log:warn("exp share failed: %s -- %s", tostring(err),
                     ExpShare.paid and "the award was already part-paid"
                                    or "the vanilla award ran instead")
    end
    if not ExpShare.paid then return next(ctx) end
  end)
end

return ExpShare
