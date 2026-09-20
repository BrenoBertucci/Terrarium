-- PARRY: the timing ring the concept boards have always had, finally wired.
--
-- lib/BattleRibbon.lua closes with the reason this did not exist: "The
-- concept's OTHER half, the parry-timing ring, is deliberately not here: it
-- would touch damage resolution, and this costume's law is that nothing
-- presentational reaches the rules." That law held for every module in this
-- directory and it still does -- this file is not presentational. It is the
-- one piece of the costume that was ASKED to be a rule, and it is kept alone
-- in its own file, behind its own row, for exactly that reason.
--
-- WHY THE TURN HAS TO BE DEFERRED, and why nothing else would do. The engine
-- has no pause between "the foe attacks" and "your HP drops": resolveTurn
-- queues one closure per side, and when the foe's closure runs it computes the
-- damage, subtracts it from mon.hp and queues the bar drain -- all inside a
-- single frame (BattleState:executeAction -> performMove -> EffectRegistry
-- .runDamaging -> BattleState:applyDamage). By the time the move's ANIMATION
-- plays, the health is already gone; the animation is a replay. So there is
-- nothing to "hold": the window has to be MANUFACTURED by not running the
-- foe's closure yet, and putting it back on the queue behind a wait row.
--
-- That wait row is the engine's own ({ wait = n }, BattleState:updateQueue),
-- which is why this does not wrap updateQueue: that pump is also the lockstep
-- for link battles and the gate on the queue-drained transition, and a mod
-- returning true from it freezes more than a turn.
--
-- WHERE THE REDUCTION LANDS. BattleState:applyDamage, not the engine's
-- `battle.damage` hook. The hook only sees Damage.compute, and COUNTER, the
-- OHKO moves, SUPER FANG and every fixed-damage move reach the defender
-- without ever going through it (EffectRegistry.runDamaging picks them from
-- record.chooseDamage instead). applyDamage is the one gate all of them pass.
-- A parry that worked on Tackle and did nothing against Horn Drill would be
-- worse than no parry.
--
-- THE CLOCK IS THE WAIT ROW ITSELF. `battle.waitFrames` counts down to zero
-- and the deferred closure runs on the frame it reaches it -- so waitFrames IS
-- "frames until this hits me", exactly, with no second clock of ours to drift
-- against it. The ring drawn below is that number and nothing else.
--
-- WHAT IT NEVER DOES. It never raises damage, never adds a punish window, and
-- never reads the foe's roll: a missed press is the damage the game was going
-- to deal anyway. The worst outcome of pressing at the wrong time is the
-- vanilla outcome.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local BattleParry = {}

BattleParry.setting = ModSetting.new("battleparry", "PARRY",
                                     { "on", "off" }, { "LIGADO", "DESLIGADO" })

function BattleParry.enabled()
  return BattleParry.setting:get() ~= "off"
end

-- ------- the window, in engine frames
--
-- WINDOW is how long the foe winds up. Long enough to read the move's name off
-- the chip and commit, short enough that a fight does not become a QTE between
-- every turn. PERFECT is the Clair Obscur-sized band -- eight frames, ~130 ms,
-- which is a read and not a guess -- and GOOD is the generous ring around it
-- so a player who is merely close is not treated as a player who did nothing.
BattleParry.WINDOW = 66
BattleParry.PERFECT_AT = 8      -- frames-to-impact at or under this = PERFECT
BattleParry.GOOD_AT = 22        -- ...and at or under this = GOOD

-- What each grade leaves of the blow. Not zero for PERFECT: a Pokemon battle
-- that can be taken to no damage by one button is a battle with no other
-- decisions in it, and the HP bar is this game's whole tension curve.
BattleParry.PERFECT_MULT = 0.25
BattleParry.GOOD_MULT = 0.60

-- One press per window. Mashing from the first frame therefore SPENDS the
-- attempt on an early read rather than covering the whole band for free --
-- which is the only thing that makes the band mean anything -- but it still
-- costs no more than never pressing at all.
BattleParry.GRADES = { perfect = "PERFECT", good = "GOOD", early = "MISS" }

-- The live window. Module state rather than a field on the battle: the engine
-- checkpoints battlers, and a key this mod invented does not belong in a save.
local P = nil

-- Statuses that make the wind-up a lie: a sleeping or frozen foe is not about
-- to hit anybody, and a ring counting down to nothing teaches the player to
-- distrust the ring.
local DEAD_STATUS = { SLP = true, FRZ = true }

local function moveDef(battle, action)
  if type(action) ~= "table" or action.special or not action.id then return nil end
  return battle.data and battle.data.moves and battle.data.moves[action.id]
end

-- Is this the beat a parry is for: the FOE swinging something that lands on
-- the player's mon and takes HP off it.
local function wants(battle, user, target, action)
  if not BattleParry.enabled() then return nil end
  if battle.result then return nil end
  if user ~= battle.enemy or target ~= battle.player then return nil end
  if not (user.mon and target.mon) then return nil end
  if (user.mon.hp or 0) <= 0 or (target.mon.hp or 0) <= 0 then return nil end
  if DEAD_STATUS[user.mon.status] then return nil end
  local def = moveDef(battle, action)
  if not def then return nil end
  if (def.power or 0) <= 0 or def.category == "status" then return nil end
  return def
end

-- ------- the press
--
-- Called from main.lua's own key wrap (and the pad hook) at EVENT time, not
-- polled: a perfect band eight frames wide cannot be read off a per-frame
-- isDown without losing a press to a frame boundary.
-- The whole verdict, as arithmetic over one number: frames left until the blow
-- lands. Pure on purpose -- it is the part that can be wrong in a way no
-- screenshot would show, and tests/battleparry_offline.lua reads the bands off
-- this without a battle anywhere.
function BattleParry.gradeFor(left)
  left = tonumber(left) or 0
  if left <= BattleParry.PERFECT_AT then return "perfect" end
  if left <= BattleParry.GOOD_AT then return "good" end
  return "early"
end

local function charge()
  local ok, C = pcall(V.require, "BattleCharge")
  return ok and C or nil
end

function BattleParry.press()
  if not (P and P.battle and not P.grade) then return false end
  -- CHARGE is the parry's fuel (lib/BattleCharge.lua). No fuel, no grade: the
  -- press is refused rather than spent as a miss, so an empty meter costs the
  -- player nothing but the parry itself.
  local C = charge()
  if C and not C.payParry(P.battle) then return false end
  local left = P.battle.waitFrames or 0
  P.grade, P.gradeAt = BattleParry.gradeFor(left), left
  return true
end

function BattleParry.multFor(grade)
  if grade == "perfect" then return BattleParry.PERFECT_MULT end
  if grade == "good" then return BattleParry.GOOD_MULT end
  return 1
end

-- What the probe reads instead of a screenshot.
function BattleParry.debug()
  if not P then return nil end
  return { open = true, left = P.battle and P.battle.waitFrames or 0,
           window = BattleParry.WINDOW, move = P.moveName,
           grade = P.grade, gradeAt = P.gradeAt }
end

-- The verdict the last closed window reached, kept one beat longer than the
-- window so the chip can flash it and a probe can read it after the hit.
BattleParry.last = nil

-- Open and close, as two named doors rather than two assignments buried in a
-- closure: they are the only writes to the live window, the deferred turn uses
-- them, and tests/battleparry_offline.lua drives the real ones instead of a
-- copy that could drift away from what a fight actually runs.
function BattleParry._open(battle, moveName, moveType)
  P = { battle = battle, moveName = moveName, moveType = moveType, grade = nil }
  BattleParry.last = nil
end

-- Closing hands back the grade and leaves it in `last` for the chip's flash.
function BattleParry._close()
  local grade = P and P.grade or nil
  local mult = BattleParry.multFor(grade)
  BattleParry.last = { grade = grade, mult = mult,
                       move = P and P.moveName, at = 0 }
  P = nil
  return grade, mult
end

-- ------- the seams
function BattleParry.install(BattleState)
  if BattleState.terrariumParryHook then return end

  local innerAct = BattleState.executeAction
  function BattleState:executeAction(user, target, action)
    if self.terrariumParryResolving or P then
      return innerAct(self, user, target, action)
    end
    -- The foe's action can still be REPLACED inside executeAction (a trainer
    -- class may swap it) unless it was forced, so resolving that swap HERE is
    -- what lets the chip name the move truthfully -- and setting the engine's
    -- own forced flag is what stops it being rolled a second time when the
    -- deferred call finally runs.
    if user == self.enemy and not user.isPlayer and not self.enemyActionForced then
      local okA, swapped = pcall(self.trainerAIAction, self)
      if okA and swapped then action = swapped end
      self.enemyActionForced = true
    end
    local def = wants(self, user, target, action)
    if not def then return innerAct(self, user, target, action) end

    BattleParry._open(self, def.name or action.id, def.type)
    -- the foe's turn, put back on the queue behind the engine's own wait row
    table.insert(self.queue, 1, { fn = function()
      local grade, mult = BattleParry._close()
      if grade == "perfect" then
        local okC, Charge = pcall(V.require, "BattleCharge")
        if okC and Charge then pcall(Charge.gain, self, Charge.PARRY_GAIN) end
      end
      self.terrariumParryArmed = (mult < 1) and mult or nil
      self.terrariumParryResolving = true
      local ok, err = pcall(innerAct, self, user, target, action)
      self.terrariumParryResolving = nil
      self.terrariumParryArmed = nil
      if not ok then error(err, 0) end
    end })
    -- The hold is written STRAIGHT onto the engine's own counter rather than
    -- queued as a { wait = n } row, and the difference is a real frame. A
    -- queued row is not read until the NEXT pump, so for one frame the window
    -- would be open while waitFrames still held whatever the last row left --
    -- and press() grades off that number. Measured: the window opened
    -- reporting zero frames left, which is the perfect band, which would have
    -- handed a free PERFECT to anyone holding the button down. Setting it here
    -- means the clock is correct on the first frame the ring is drawn.
    self.waitFrames = BattleParry.WINDOW
  end

  -- The single gate every damage road passes, formula and fixed alike. The
  -- SUBSTITUTE branch is left alone on purpose: the doll is taking the blow,
  -- there is nobody behind it to time anything, and applyDamage returns before
  -- mon.hp is touched anyway.
  local innerDmg = BattleState.applyDamage
  function BattleState:applyDamage(target, dmg)
    local mult = self.terrariumParryArmed
    if mult and target == self.player and not target.substituteHP
       and (dmg or 0) > 0 then
      dmg = math.max(1, math.floor(dmg * mult))
    end
    return innerDmg(self, target, dmg)
  end

  -- A fight that ends mid-window (a faint, a run, a script closing the state)
  -- must not leave the window latched: the next battle would open with a stale
  -- verdict armed. finish() is the one door out.
  local innerFinish = BattleState.finish
  function BattleState:finish(...)
    if P and P.battle == self then P = nil end
    self.terrariumParryArmed, self.terrariumParryResolving = nil, nil
    local okC, Charge = pcall(V.require, "BattleCharge")
    if okC and Charge then pcall(Charge.reset) end
    return innerFinish(self, ...)
  end

  BattleState.terrariumParryHook = true
end

-- ------- the picture
--
-- Two things, both over everything else in the frame: a ring closing on the
-- player's own mon (the thing being timed) and the chip the boards draw on the
-- right, "Y PARRY / Perfect timing reduces damage."
-- The ring is sized off the mon's OWN on-screen span, not off world cells.
-- Measured: at 3.2 cells the opening ring was wider than the arena and read as
-- a screen-wide halo rather than as a thing closing on the defender -- and a
-- cell is a fixed world distance, so the same number frames a Rattata and
-- swallows a Snorlax. A multiple of the sprite's span frames both.
BattleParry.RING_OUT = 1.85      -- ring radius at the window's start, x span
BattleParry.RING_IN = 0.58       -- ...and at the instant of impact
BattleParry.RING_UP = 1.7        -- how far over the cell the ring is centred
BattleParry.GOLD = { 1.00, 0.84, 0.40 }
BattleParry.HOT = { 1.00, 0.42, 0.34 }

local function fan()
  local ok, F = pcall(V.require, "BattleFanXY")
  return ok and F or nil
end

local function chip(g, x, y, w, h, title, line, accent)
  local Hud = V.require("BattleHudXY")
  local r = 12
  g.setColor(0.07, 0.08, 0.11, 0.86)
  g.rectangle("fill", x, y, w, h, r, r)
  g.setColor(accent[1], accent[2], accent[3], 0.20)
  g.setLineWidth(6)
  g.rectangle("line", x, y, w, h, r, r)
  g.setColor(accent[1], accent[2], accent[3], 0.95)
  g.setLineWidth(2)
  g.rectangle("line", x, y, w, h, r, r)
  g.setLineWidth(1)
  local th = h * 0.34
  Hud.text(title, x + w * 0.06, y + h * 0.13, th, accent)
  if line then
    local lh = h * 0.24
    Hud.text(line, x + w * 0.06, y + h * 0.58, lh, { 0.88, 0.90, 0.96, 1 })
  end
end

function BattleParry.draw(battle, shot)
  if not (battle and shot and shot.playerCell) then return false end
  local open = P and P.battle == battle
  local flash = BattleParry.last
  if not (open or flash) then return false end
  local g = love.graphics
  local F = fan()
  local R = F and F.rig(shot)

  -- the ring, only while the window is open and only if the arena projects
  if open and R then
    local left = math.max(0, math.min(BattleParry.WINDOW,
                                      battle.waitFrames or 0))
    local t = 1 - left / BattleParry.WINDOW           -- 0 at open, 1 at impact
    local gy = shot.groundY or 0
    local base = { shot.playerCell[1], gy, shot.playerCell[2] }
    local cx, cy = R.project(F.vadd(base, R.up, BattleParry.RING_UP))
    if cx then
      -- the ring's SIZE is the clock, and the unit is the defender's own
      -- on-screen span, so it frames whatever mon is standing there at
      -- whatever distance the attack camera has swung to
      local span = shot.playerSpan
      if not span or span < 8 then
        -- no span on the shot: fall back to one projected world cell rather
        -- than to a pixel count that would mean nothing at another zoom
        local ex, ey = R.project(F.vadd(base, R.right, 1))
        span = (ex and math.sqrt((ex - cx) ^ 2 + (ey - cy) ^ 2) * 2) or 80
      end
      local rad = span * (BattleParry.RING_OUT
                          + (BattleParry.RING_IN - BattleParry.RING_OUT) * t)
      local hot = left <= BattleParry.GOOD_AT
      local col = hot and BattleParry.GOLD or { 0.72, 0.80, 0.95 }
      -- the target ring: where the closing ring will be at the perfect beat
      local tgt = span * BattleParry.RING_IN
      g.setColor(BattleParry.GOLD[1], BattleParry.GOLD[2], BattleParry.GOLD[3],
                 0.30)
      g.setLineWidth(2)
      g.circle("line", cx, cy, tgt)
      -- the closer
      for i = 3, 1, -1 do
        g.setColor(col[1], col[2], col[3], (hot and 0.13 or 0.07) * i)
        g.setLineWidth(3 + i * 3)
        g.circle("line", cx, cy, rad)
      end
      g.setColor(col[1], col[2], col[3], hot and 1 or 0.85)
      g.setLineWidth(3)
      g.circle("line", cx, cy, rad)
      g.setLineWidth(1)
      if P.grade then
        -- already spent: say so, and stop pretending the ring still matters
        local spent = BattleParry.GRADES[P.grade]
        local col2 = (P.grade == "early") and BattleParry.HOT or BattleParry.GOLD
        local Hud = V.require("BattleHudXY")
        local h = shot.ph * 0.035
        local w = Hud.textWidth(spent) * (h / 84)
        Hud.text(spent, cx - w * 0.5, cy - rad - h * 1.4, h, col2)
      end
    end
  end

  -- the chip, on the right where the boards put it
  local cw = math.min(340, shot.pw * 0.26)
  local ch = cw * 0.30
  local cxp = shot.pw - cw - shot.pw * 0.018
  local cyp = shot.ly + shot.ph * 0.30
  if open then
    local left = battle.waitFrames or 0
    local accent = (left <= BattleParry.GOOD_AT) and BattleParry.GOLD
                                                 or { 0.78, 0.84, 0.98 }
    local C = charge()
    if C and not P.grade and not C.canParry(battle) then
      -- say it BEFORE the press, not after: a ring the player cannot answer
      -- has to look unanswerable, or the refused press reads as a broken key
      accent = { 0.55, 0.58, 0.66 }
      chip(g, cxp, cyp, cw, ch, "Y  PARRY", "Not enough CHARGE", accent)
    else
      chip(g, cxp, cyp, cw, ch, "Y  PARRY",
           P.moveName and ("Incoming: " .. tostring(P.moveName))
                       or "Perfect timing reduces damage.", accent)
    end
  elseif flash then
    -- one second of verdict after the window closes, so the player learns
    -- what their press was worth instead of inferring it from the bar
    flash.at = (flash.at or 0) + 1
    if flash.at > 90 then BattleParry.last = nil; return true end
    local label = flash.grade and BattleParry.GRADES[flash.grade] or nil
    if not label then return true end
    local accent = (flash.grade == "early") and BattleParry.HOT
                                             or BattleParry.GOLD
    chip(g, cxp, cyp, cw, ch, label,
         ("damage x%.2f"):format(flash.mult or 1), accent)
  end
  g.setColor(1, 1, 1, 1)
  return true
end

-- OPTIONS row. Switching it off mid-battle is safe by construction: the flag
-- is consulted when a window would OPEN, and a window already open still
-- resolves through its own closure.
function BattleParry.setting:row()
  local self_ = self
  return {
    id = ((V.mod and V.mod.id) or "TERRARIUM") .. ":" .. self.key,
    label = self.label,
    value = function() return self_.labels[self_:read()] end,
    step = function(game, dir) self_:cycle(game, dir) return true end,
  }
end

function BattleParry.onOptionsChanged(value)
  BattleParry.setting:sync(value)
end

return BattleParry
