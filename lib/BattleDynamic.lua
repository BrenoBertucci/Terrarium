-- One row for the whole dynamic battle costume.
--
-- Every piece of the package already keeps its own gate -- the attack
-- camera's `enabled`, the fan's, the panels', the weather's, the
-- ribbon's, the capsules' WORLD flag -- and every draw path behind those
-- gates already degrades to the classic presentation it replaced (flat
-- rows, corner capsules, the plain rig). This module is one hand on all
-- of them: DINAMICA is the costume as built, CLASSICA is a fight that
-- stands still -- the camera holds the rig, the menu and the box lie
-- flat on the glass, the capsules pin to the window corners (still
-- wearing Unova's bars: the ART is not what this row is about), and
-- nothing bobs, rocks or rains.
--
-- The flip is safe mid-battle by construction: every gate is consulted
-- per frame, and the classic paths are the fallbacks the dynamic ones
-- were built over. Applied at every battle's door too, so a persisted
-- CLASSICA holds from the first frame.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local BattleDynamic = {}

BattleDynamic.setting = ModSetting.new("battledyn", "COMBAT",
                                       { "dynamic", "classic" },
                                       { "DINAMICA", "CLASSICA" })

function BattleDynamic.wantsDynamic()
  return BattleDynamic.setting:get() ~= "classic"
end

-- the gates, by module and field -- each module stays its own master;
-- this row only writes what a probe (or a hand on the module) could
local GATES = {
  { "BattleShot", "enabled" },
  { "BattleFanXY", "ENABLED" },
  { "BattlePanelsXY", "ENABLED" },
  { "BattleGlassFX", "ENABLED" },
  { "BattleRibbon", "ENABLED" },
  { "BattleHitFX", "ENABLED" },
}

function BattleDynamic.apply()
  local on = BattleDynamic.wantsDynamic()
  for _, gate in ipairs(GATES) do
    local ok, M = pcall(V.require, gate[1])
    if ok and M then M[gate[2]] = on end
  end
  -- the capsules keep Unova's bars either way; CLASSICA only sends them
  -- back to the window corners, and clears the world debug so a probe
  -- can tell which placement is live rather than reading a stale one
  local okC, Cap = pcall(V.require, "BattleCapsule")
  if okC and Cap then
    Cap.WORLD = on
    if not on then Cap._world = nil end
  end
  return on
end

-- OPTIONS row: cycle then apply. The manager page writes through
-- mod.options_changed (main.lua), which calls onOptionsChanged here.
function BattleDynamic.setting:row()
  local self_ = self
  return {
    id = ((V.mod and V.mod.id) or "TERRARIUM") .. ":" .. self.key,
    label = self.label,
    value = function() return self_.labels[self_:read()] end,
    step = function(game, dir)
      self_:cycle(game, dir)
      BattleDynamic.apply()
      return true
    end,
  }
end

function BattleDynamic.onOptionsChanged(value)
  BattleDynamic.setting:sync(value)
  BattleDynamic.apply()
end

return BattleDynamic
