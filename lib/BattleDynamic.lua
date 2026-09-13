-- One row for the whole dynamic battle costume.
--
-- Every piece of the package already keeps its own gate -- the attack
-- camera's `enabled`, the fan's, the panels', the weather's, the
-- ribbon's, the capsules' WORLD flag -- and every draw path behind those
-- gates already degrades to the classic presentation it replaced (flat
-- rows, corner capsules, the plain rig). This module is one hand on all
-- of them, across four levels:
--
--   DINAMICA  the costume as built: the camera moves, the panels float,
--             the capsules hang beside their own mon.
--   CLASSICA  a fight that stands still -- the camera holds the rig, the
--             menu and the box lie flat on the glass, the capsules pin
--             to the window corners (still wearing Unova's bars: the ART
--             is not what this row is about), and nothing bobs, rocks or
--             rains.
--   MINIMA    the same corner-pinned name/HP/EXP reading and the message
--             text ("Um RATTATA selvagem apareceu!" and the like), but
--             no command menu and no move-selection screen -- that is
--             left for another mod to draw (a different battle UI, like
--             Kanto Gear), or for a battle to sit in until one does.
--   DESLIGADA nothing this mod draws at all: no box, no HUD, no menu, no
--             frost. Just the 3D scene, the models, and whatever hit FX
--             are independently on -- the way a fresh install would
--             look, and the level to pick to hand the whole battle
--             screen to another mod's own UI instead of this one's.
--
-- The flip is safe mid-battle by construction: every gate is consulted
-- per frame, and each level's paths are the fallbacks the level above it
-- was built over. Applied at every battle's door too, so a persisted
-- choice holds from the first frame.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local BattleDynamic = {}

BattleDynamic.setting = ModSetting.new("battledyn", "COMBAT",
                                       { "dynamic", "classic", "minimal", "off" },
                                       { "DINAMICA", "CLASSICA", "MINIMA", "DESLIGADA" })

function BattleDynamic.mode()
  return BattleDynamic.setting:get()
end

function BattleDynamic.wantsDynamic()
  return BattleDynamic.mode() == "dynamic"
end

-- CLASSICA and MINIMA still wear the corner-pinned box and HUD; only
-- DESLIGADA takes them off and draws nothing in their place.
function BattleDynamic.wantsCostume()
  return BattleDynamic.mode() ~= "off"
end

function BattleDynamic.wantsMinimal()
  return BattleDynamic.mode() == "minimal"
end

function BattleDynamic.wantsOff()
  return BattleDynamic.mode() == "off"
end

-- the gates, by module and field -- each module stays its own master;
-- this row only writes what a probe (or a hand on the module) could.
-- Tied to DINAMICA specifically: these are the moving parts CLASSICA and
-- MINIMA hold still, not the costume itself (see COSTUME_GATES below).
-- BattleHitFX is deliberately NOT here -- hit FX are an independent
-- polish layer, not part of this row's own presentation, and stay on
-- (their own default) at every level including DESLIGADA.
local GATES = {
  { "BattleShot", "enabled" },
  { "BattleFanXY", "ENABLED" },
  { "BattlePanelsXY", "ENABLED" },
  { "BattleGlassFX", "ENABLED" },
  { "BattleRibbon", "ENABLED" },
}

-- the costume itself -- the box and HUD reskin -- on for DINAMICA,
-- CLASSICA and MINIMA alike, off only for DESLIGADA
local COSTUME_GATES = {
  { "BattleBoxXY", "ENABLED" },
  { "BattleHudXY", "ENABLED" },
}

function BattleDynamic.apply()
  local on = BattleDynamic.wantsDynamic()
  for _, gate in ipairs(GATES) do
    local ok, M = pcall(V.require, gate[1])
    if ok and M then M[gate[2]] = on end
  end
  local costume = BattleDynamic.wantsCostume()
  for _, gate in ipairs(COSTUME_GATES) do
    local ok, M = pcall(V.require, gate[1])
    if ok and M then M[gate[2]] = costume end
  end
  local minimal = BattleDynamic.wantsMinimal()
  local off = BattleDynamic.wantsOff()
  -- MINIMA: the box still speaks for the "messages" phase, but gets out
  -- of the way for "menu"/"moveSelect" -- neither drawing its own
  -- command UI there nor forcing the engine's, so another mod's own
  -- battle-UI hook (or the engine's, absent one) is what the player
  -- sees.
  local okB, Box = pcall(V.require, "BattleBoxXY")
  if okB and Box then
    Box.HIDE_COMMANDS = minimal
    -- DESLIGADA: suppressed outright, never falling back to the engine's
    -- own box the way a plain `available()==false` would (see
    -- BattleBoxXY.install) -- this level means nothing this mod touches
    -- shows at all, so a different battle UI has a clean frame to draw
    -- on.
    Box.SUPPRESS = off
  end
  local okH, Hud = pcall(V.require, "BattleHudXY")
  if okH and Hud then Hud.SUPPRESS = off end
  -- the capsules keep Unova's bars in CLASSICA and MINIMA alike; only
  -- DINAMICA hangs them beside their own mon, and clears the world debug
  -- so a probe can tell which placement is live rather than reading a
  -- stale one
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
