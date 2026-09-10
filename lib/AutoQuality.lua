-- The RES rung, chosen by the machine instead of by a guess.
--
-- ------- WHY A GOVERNOR AND NOT A BIGGER TABLE OF DEFAULTS
--
-- lib/Quality.lua's own header says it plainly: "there is no benchmarking a
-- phone from here."  That is the honest constraint, and every fixed default
-- written against it is a bet placed blind.  RES 1/2 was such a bet, and on
-- the Poco X7 it lost twice over: 1/2 of a 2712x1220 panel is 827k pixels,
-- three times what 1/2 of the development machine's 1536x864 window is, on a
-- GPU with a fraction of the fill rate.  The divisor is the wrong unit.  A
-- render target is expensive in PIXELS, and the same divisor means a
-- different number of pixels on every device that will ever run this.
--
-- So AUTO does two things a constant cannot:
--
--   1. It starts from a PIXEL BUDGET rather than a divisor, so the first
--      frame on any panel lands near the same amount of work.
--   2. It then MEASURES, and walks the ladder until the frames fit.  A
--      device nobody has ever tested tunes itself in about two seconds.
--
-- ------- WHY IT CANNOT OSCILLATE
--
-- The obvious governor -- step down when slow, step up when fast -- flaps
-- forever at any rung boundary, and on a vsynced display it flaps at EVERY
-- boundary, because a capped 16.7ms frame is indistinguishable from a frame
-- with headroom to spare.  Flapping is worse than a bad constant: the
-- diorama visibly changes resolution twice a second.
--
-- The fix is memory, not a wider dead band.  A rung that has been stepped
-- DOWN from is marked, and the climb never returns to a marked rung.  So the
-- walk is monotone: it climbs at most once through each rung, marks the
-- first one that does not hold, and settles one below it for the session.
-- The dead band is still there (it stops a single hitch from moving
-- anything) but it is not what guarantees convergence.
--
-- ------- WHAT IT REFUSES TO MEASURE
--
-- Only frames the 3D pass actually drew, sampled once per drawWorld.  And
-- not all of those: a mesh build, a shader compile, a texture bake or the OS
-- scheduling something else produces a frame that is evidence about the
-- hitch and not about the rung.  This mod streams chunk meshes in slices and
-- bakes roamer art on first sight, so those frames are common and they are
-- exactly the frames a naive average would act on.
--
-- ------- AND WHY THAT TEST CANNOT BE AN ABSOLUTE NUMBER
--
-- The first version of this file rejected anything over 250 ms flat.  On the
-- device the whole effort is aimed at -- one frame a second, i.e. 1000 ms --
-- that rejects EVERY frame, so the ring never fills, the governor never
-- fires, and the one machine that needed it most was the one machine it
-- could not run on.  A threshold that assumes the machine is already fast is
-- not a threshold, it is the assumption being tested.
--
-- So the test is RELATIVE: a sample is an outlier when it is several times
-- what this device has been doing.  Before anything has been accepted there
-- is nothing to be several times of, so the first samples are taken on a
-- hard ceiling generous enough for a genuinely broken device (HARD_MS) and
-- the running average takes over from there.  On a 20 ms machine the gate
-- settles at 250 ms exactly as before; on a 1000 ms machine it settles at
-- 4000 ms and the walk down happens.
--
-- ------- WHAT IT DOES NOT TOUCH
--
-- Only the RES row, and only while the player has left it on AUTO.  Every
-- other row in lib/Quality.lua stays exactly where the player put it.  A
-- governor that turned features off to hit a frame rate would be a governor
-- that undoes the reason somebody installed this.

local V = ...
local Device = V.require("Device")

local AutoQuality = {}

-- Richest first.  1/5 and 1/7 are missing on purpose: the steps a player can
-- SEE should be worth seeing, and each rung here is at least 1.3x the pixels
-- of the next.  1/8 is the floor because at a phone's fitScale that is about
-- one canvas texel per world pixel -- below it the diorama is rendering
-- coarser than the art it is drawing.
AutoQuality.LADDER = { 1, 2, 3, 4, 6, 8 }

-- The scene canvas the first frame aims for, before anything is measured.
--
-- Desktop: 1.6 Mpx clears a 1536x864 window at RES FULL, which is what a
-- desktop player expects to get and what this mod has always given them.
--
-- Mobile: 0.22 Mpx.  Deliberately BELOW what a Mali-G615 can hold, because
-- the walk is upward and the first seconds of the session are the ones the
-- player judges the mod on.  On the Poco X7's 3.31 Mpx panel this picks 1/4
-- (0.207 Mpx); the governor is then free to find 1/3 or 1/2 if they hold.
AutoQuality.BUDGET_DESKTOP = 1600000
AutoQuality.BUDGET_MOBILE  = 220000

-- The frame the governor is aiming at, and the band around it.  30 fps
-- rather than 60: this is a diorama on a phone, and a stable 30 looks far
-- better than a 45 that dips.  DOWN is generous (22 fps) so only a rung that
-- is genuinely not holding moves; UP is strict (45 fps) so a rung is only
-- climbed to when there is room for the cost of the climb, which is roughly
-- 1.8x at every step.
AutoQuality.TARGET_MS = 33.4
AutoQuality.DOWN_MS   = 45.0
AutoQuality.UP_MS     = 22.0

-- ------- AND WHAT A STEP DOWN HAS TO BUY TO BE KEPT
--
-- The monotone walk above has one unstated premise: that stepping down makes
-- the frame faster.  When it does not, every rung "does not hold", every rung
-- gets marked, and the walk that was supposed to settle one below the first
-- bad rung runs all the way to the floor instead -- permanently, because a
-- marked rung is never climbed back to.
--
-- That is not hypothetical.  It is what the Poco X7 report shows: `moves 6`,
-- RES pinned at 1/8, and then a median of 16.6 ms in LAVENDER_MART -- far
-- under UP_MS -- with the resolution still on the floor because every rung
-- above it had been marked on the way down.  1/8 of a 3.31 Mpx panel is a
-- 339x152 scene canvas; a frame that still costs 26-34 ms at 339x152 is not
-- paying for pixels, and no further division was ever going to find the
-- money.  Worse, below FULL this mod ADDS a panel-sized present canvas, a
-- clear and an upscale blit (see Voxel3D.endScene), so the low rungs carry a
-- fixed cost the high ones do not.
--
-- So a step down is now a HYPOTHESIS, and the window after it is the test.
-- If the step did not buy at least GAIN_MIN of the median it was taken
-- against (never less than GAIN_MS, so a fast machine is not held to a
-- fraction of nothing), then RES is not what this frame is spending on: the
-- step is UNDONE, the rung it came from is un-marked, and the governor goes
-- INERT -- it stops moving RES for the session rather than grinding down an
-- axis that does not pay.
--
-- Convergence still holds, and for a stronger reason than before: every
-- mark now has a measurement behind it, and the one path that used to mark
-- rungs without evidence ends the walk instead of continuing it.
AutoQuality.GAIN_MIN = 0.12      -- fraction of the pre-step median
AutoQuality.GAIN_MS  = 3.0       -- ...but never a smaller absolute win
-- The floor of the outlier gate, and its multiplier over what this device
-- has actually been doing.  The gate is the larger of the two, so a fast
-- machine keeps the old flat 250 ms and a slow one scales with itself.
AutoQuality.OUTLIER_MS  = 250.0
AutoQuality.OUTLIER_MUL = 4.0
-- What counts as a frame at all before there is an average to compare
-- against.  Four seconds is past anything a render path does and well past
-- anything worth measuring; it exists to keep a first-frame shader compile
-- out of the average, not to judge the device.
AutoQuality.HARD_MS = 4000.0

-- Frames of evidence before anything moves, and frames of quiet after a move
-- before the next one.  45 is about a second and a half at the target, which
-- is long enough that a passing cloud of particles cannot move the rung and
-- short enough that a player never sits at 5 fps wondering.
AutoQuality.WINDOW  = 45
AutoQuality.SETTLE  = 60

-- ------- state
local idx = nil                  -- index into LADDER, nil until first pick
local ring, ringN, ringHead = {}, 0, 1
local avg = nil                  -- running mean of accepted frames, ms
local scratch = {}               -- reused by median(); this runs every frame
local sinceChange = 0
local lastT = nil
local tried = {}                 -- LADDER index -> true once proven too rich
-- The step down currently on trial: the rung it came from, and the median it
-- was taken against.  nil when no step is awaiting its verdict.
local pendFrom, pendBefore = nil, nil
-- Latched once a step down is found to have bought nothing: RES is not what
-- this device is spending its frame on, so stop spending image quality on it.
AutoQuality.inert = false
AutoQuality.changes = 0          -- how many times the rung moved this session
AutoQuality.lastReason = "not started"

local function budget()
  return Device.mobile() and AutoQuality.BUDGET_MOBILE
                          or AutoQuality.BUDGET_DESKTOP
end

-- The richest rung whose scene canvas fits the budget.  Falls through to the
-- cheapest rung rather than to the richest: a panel so large that even 1/8
-- misses the budget is a panel that wants 1/8.
function AutoQuality.pick(w, h)
  local b = budget()
  for i, d in ipairs(AutoQuality.LADDER) do
    if math.floor(w / d) * math.floor(h / d) <= b then return i end
  end
  return #AutoQuality.LADDER
end

local function reset(reason)
  ring, ringN, ringHead = {}, 0, 1
  -- `avg` deliberately SURVIVES a rung change: it is what the outlier gate
  -- is scaled against, and the frame after a step down is not a different
  -- machine.  Only invalidate() clears it.
  sinceChange = 0
  lastT = nil
  AutoQuality.lastReason = reason
end

-- The divisor to render at right now.  Safe to call before the first frame:
-- it seeds itself from the panel.
function AutoQuality.divisor()
  if not idx then
    local w, h = Device.panel()
    idx = AutoQuality.pick(w, h)
    AutoQuality.lastReason =
      ("seeded 1/%d from %dx%d against a %.2f Mpx budget")
        :format(AutoQuality.LADDER[idx], w, h, budget() / 1e6)
  end
  return AutoQuality.LADDER[idx]
end

function AutoQuality.index() return idx end

-- A reused table rather than a fresh one: this runs on every rendered frame
-- once the window is full, and 45 entries of garbage per frame is 2700 a
-- second handed to a collector that is already the reason some of those
-- frames were slow.
local function median()
  for i = 1, ringN do scratch[i] = ring[i] end
  for i = ringN + 1, #scratch do scratch[i] = nil end
  table.sort(scratch)
  return scratch[math.ceil(ringN / 2)]
end

local function move(to, reason)
  idx = to
  AutoQuality.changes = AutoQuality.changes + 1
  reset(reason)
end

-- One rendered frame of the 3D pass.  Called from the drawWorld hook, which
-- runs exactly once per frame the mode is actually on screen -- unlike the
-- update hook, which the engine may tick several times between two frames
-- and which keeps running while the mode is off.
function AutoQuality.frame()
  if not idx then AutoQuality.divisor() end
  local ok, now = pcall(love.timer.getTime)
  if not ok or not now then return end
  local prev = lastT
  lastT = now
  if not prev then return end
  local ms = (now - prev) * 1000
  sinceChange = sinceChange + 1

  -- A build, a bake, a compile or the OS. Not evidence about the rung, and
  -- the frames that follow one are not either -- the ring is left as it was.
  -- See the header: the gate is relative to what this device has been doing,
  -- because an absolute one cannot see a device that is slow everywhere.
  if ms <= 0 then return end
  local gate = avg and math.max(AutoQuality.OUTLIER_MS,
                                avg * AutoQuality.OUTLIER_MUL)
                    or AutoQuality.HARD_MS
  if ms > gate then return end
  avg = avg and (avg + (ms - avg) / 16) or ms

  ring[ringHead] = ms
  ringHead = ringHead % AutoQuality.WINDOW + 1
  if ringN < AutoQuality.WINDOW then ringN = ringN + 1 end

  if ringN < AutoQuality.WINDOW then return end
  if sinceChange < AutoQuality.SETTLE then return end

  local m = median()
  local last = #AutoQuality.LADDER

  -- ------- THE VERDICT ON THE LAST STEP DOWN, BEFORE ANY NEW DECISION
  --
  -- This window is the first clean one at the new rung, so it is the evidence
  -- the step was taken on credit against.  See GAIN_MIN.
  if pendFrom then
    local from, before = pendFrom, pendBefore
    pendFrom, pendBefore = nil, nil
    local need = math.max(AutoQuality.GAIN_MS, before * AutoQuality.GAIN_MIN)
    if (before - m) >= need then
      -- The step paid. NOW the rung it came from has a measurement behind it,
      -- so mark it and let the walk carry on exactly as it always did.
      tried[from] = true
    else
      -- It did not. Undo it, un-mark the rung it came from, and stop: the
      -- frame is not being spent on pixels and dividing them again cannot
      -- change that.
      AutoQuality.inert = true
      move(from, ("1/%d bought %.1f ms over 1/%d (needed %.1f) -- RES is not "
                  .. "the cost here; held at 1/%d")
                   :format(AutoQuality.LADDER[idx], before - m,
                           AutoQuality.LADDER[from], need,
                           AutoQuality.LADDER[from]))
      return
    end
  end

  -- Latched: the axis was measured and does not pay. Keep sampling so the
  -- report stays honest, but never move again.
  if AutoQuality.inert then return end

  if m > AutoQuality.DOWN_MS and idx < last then
    -- This rung may not hold -- but that is a hypothesis until the window at
    -- the rung below shows what the step actually bought. Record what it is
    -- being judged against; the block above delivers the verdict.
    pendFrom, pendBefore = idx, m
    move(idx + 1, ("stepped down to 1/%d: %.1f ms median over %d frames")
                    :format(AutoQuality.LADDER[idx + 1], m, AutoQuality.WINDOW))
    return
  end

  if m < AutoQuality.UP_MS and idx > 1 and not tried[idx - 1] then
    move(idx - 1, ("stepped up to 1/%d: %.1f ms median over %d frames")
                    :format(AutoQuality.LADDER[idx - 1], m, AutoQuality.WINDOW))
    return
  end
end

-- The player picked a rung by hand, or the window changed size.  The pixel
-- budget answer is different for a different window, and a rung that failed
-- at one size says nothing about another.
function AutoQuality.invalidate()
  idx, tried, avg = nil, {}, nil
  -- The verdict in flight was about a rung at the old size, and the latch was
  -- a conclusion about a frame that no longer exists. Both go.
  pendFrom, pendBefore = nil, nil
  AutoQuality.inert = false
  reset("invalidated")
end

-- Everything a report or a probe wants to know, in one line.
function AutoQuality.report()
  local m = (ringN >= AutoQuality.WINDOW) and median() or nil
  return ("RES AUTO = 1/%d (%s) | window %d/%d%s | moves %d%s")
    :format(AutoQuality.divisor(), AutoQuality.lastReason,
            ringN, AutoQuality.WINDOW,
            m and (" | median %.1f ms"):format(m) or "",
            AutoQuality.changes,
            AutoQuality.inert and " | INERT"
              or (pendFrom and " | on trial" or ""))
end

return AutoQuality
