-- The RES governor, proved without a GPU.
--
-- lib/AutoQuality.lua is the one piece of this optimisation that cannot be
-- checked by looking at a frame: it is a control loop, and the failure modes
-- of a control loop are things that happen over hundreds of frames -- it
-- flaps, it walks off the end of its ladder, it acts on a hitch, it never
-- settles.  None of those show up in a screenshot and all of them are
-- reproducible arithmetic.
--
-- So this drives the module with SYNTHETIC frame times from a fake machine
-- and asserts on where it lands.  It needs no love.graphics, which is the
-- point: it runs in `lupa` on the desktop in a fraction of a second, and it
-- runs against exactly the code that ships.
--
--   run:  tools/run_autoquality_offline.cmd
--         (or: python tools/run_autoquality_offline.py)

local ROOT = ...
ROOT = ROOT or "."

-- ------- the smallest V the module needs
--
-- AutoQuality requires Device, and Device is entirely about love.graphics.
-- Rather than stub love, the fake V hands AutoQuality a fake Device: the
-- module under test is the governor, and what it needs from a device is two
-- numbers and a boolean.
local fakeDevice = { mobile_ = true, w = 2712, h = 1220 }
function fakeDevice.mobile() return fakeDevice.mobile_ end
function fakeDevice.panel() return fakeDevice.w, fakeDevice.h end

local clock = { t = 0 }

local V = {}
local cache = {}
function V.require(name)
  if name == "Device" then return fakeDevice end
  if cache[name] then return cache[name] end
  local chunk = assert(loadfile(ROOT .. "/lib/" .. name .. ".lua"))
  cache[name] = chunk(V)
  return cache[name]
end

-- love.timer.getTime is the governor's only clock; the test owns it, so a
-- "frame" is exactly as long as the test says it is.
love = love or {}
love.timer = { getTime = function() return clock.t end }

local AQ = V.require("AutoQuality")

local fails, checks = 0, 0
local function check(ok, what, detail)
  checks = checks + 1
  if ok then
    print(("  PASS  %s"):format(what))
  else
    fails = fails + 1
    print(("  FAIL  %s%s"):format(what, detail and ("  -- " .. detail) or ""))
  end
end

-- Run `n` frames that each take `ms`, and return where the rung ended up.
local function run(n, ms)
  for _ = 1, n do
    clock.t = clock.t + ms / 1000
    AQ.frame()
  end
  return AQ.divisor()
end

local function restart(mobile, w, h)
  fakeDevice.mobile_, fakeDevice.w, fakeDevice.h = mobile, w, h
  AQ.invalidate()
  clock.t = 0
  AQ.changes = 0
end

print("== 1. the pixel budget picks the first rung ==")
-- The panel that reported the bug, and the window this mod was written on.
restart(true, 2712, 1220)
check(AQ.divisor() == 4, "Poco X7 (2712x1220, mobile) seeds at 1/4",
      "got 1/" .. AQ.divisor())
restart(true, 1600, 720)
check(AQ.divisor() == 3, "a 1600x720 phone seeds at 1/3",
      "got 1/" .. AQ.divisor())
restart(false, 1536, 864)
check(AQ.divisor() == 1, "the 1536x864 desktop window seeds at FULL",
      "got 1/" .. AQ.divisor())
restart(false, 3840, 2160)
check(AQ.divisor() == 3, "a 4K desktop seeds at 1/3 (8.3 Mpx over budget)",
      "got 1/" .. AQ.divisor())

print("")
print("== 2. it walks DOWN when the frames do not fit ==")
-- ------- AND WHY THIS MACHINE HAS TO BE FILL-BOUND
--
-- The first version of this case fed a CONSTANT 90 ms at every rung and
-- asserted the walk reached the floor.  That machine is not a slow machine,
-- it is a machine whose frame time does not depend on resolution at all --
-- and walking such a machine to the floor is the Poco X7 bug (case 2b), not
-- the behaviour this case is for.  A rung is only "too rich" if the rung
-- below it is cheaper, so the fake machine has to actually charge for pixels.
local function fillBound(base, fill)
  return function() return base + fill / (AQ.divisor() ^ 2) end
end

-- Run `n` frames whose length is whatever `f()` says, given the rung the
-- governor is currently on.
local function runF(n, f)
  for _ = 1, n do
    clock.t = clock.t + f() / 1000
    AQ.frame()
  end
  return AQ.divisor()
end

restart(true, 2712, 1220)
-- 5 ms of fixed cost and 3000 ms-pixels of fill: 192 ms at 1/4, 88 at 1/6,
-- 52 at 1/8.  Every rung is past DOWN_MS and every step buys a lot.
local d = runF(2000, fillBound(5, 3000))
check(d == 8, "a fill-bound machine walks all the way to the 1/8 floor",
      "got 1/" .. d)
check(AQ.changes >= 2, "and it took more than one step to get there",
      "changes = " .. AQ.changes)
check(not AQ.inert, "and it never goes inert: every step paid for itself")

print("")
print("== 2b. THE POCO X7: A RUNG THAT BUYS NOTHING ==")
-- The bug this governor shipped with.  On the reporter's phone the frame
-- cost the same at 339x152 as it did at 1356x610, because the money was
-- going to geometry and to a panel-sized present blit that RES does not
-- touch.  Every rung "did not hold", every rung got marked on the way past,
-- and the walk ran to 1/8 and could never climb back -- `moves 6`, RES 1/8,
-- and then 16.6 ms in an interior with the image still on the floor.
--
-- A step down is now a hypothesis and the next window is the test.  One
-- step is taken, it buys nothing, it is UNDONE, and the governor stops.
restart(true, 2712, 1220)
d = run(2000, 90)                  -- 90 ms at every rung: flat in resolution
check(AQ.inert, "a flat-cost machine puts the governor inert")
check(d == 4, "and RES is put back where it started, not on the floor",
      "got 1/" .. d)
check(AQ.changes <= 2, "and it cost one step down and one step back",
      "changes = " .. AQ.changes)

-- The latch has to survive: a thousand more slow frames must not restart the
-- grind, because the answer does not change by being asked again.
local wasInert = AQ.changes
run(3000, 90)
check(AQ.changes == wasInert, "and it stays put once latched",
      "changes " .. wasInert .. " -> " .. AQ.changes)

-- ...but a window resize is a different question, and clears it.
AQ.invalidate()
check(not AQ.inert, "a resize clears the latch")

print("")
print("== 3. it walks UP when there is room, and STOPS ==")
restart(true, 2712, 1220)
d = run(3000, 8)
check(d == 1, "sustained 8 ms climbs to FULL", "got 1/" .. d)

print("")
print("== 4. it does not oscillate: the anti-flap memory ==")
-- The nastiest real case.  A vsynced 60 Hz display reports 16.7 ms whatever
-- the rung, right up until the rung is too rich and the frame collapses to
-- 50 ms.  A naive governor climbs, collapses, drops, sees 16.7 again, climbs
-- again -- forever, and the player watches the diorama change resolution
-- twice a second.
restart(true, 2712, 1220)
local CEILING = 3          -- 1/3 holds; anything richer does not
local flips = 0
for _ = 1, 6000 do
  clock.t = clock.t + ((AQ.divisor() < CEILING) and 0.050 or 0.0167)
  AQ.frame()
  local _ = 0
end
local settled = AQ.divisor()
check(settled == CEILING, "settles exactly on the rung that holds",
      "got 1/" .. settled)
check(AQ.changes <= 6, "and gets there in a handful of moves, not hundreds",
      "changes = " .. AQ.changes)

-- and once settled it stays settled for a long, quiet run
local before = AQ.changes
for _ = 1, 6000 do
  clock.t = clock.t + 0.0167
  AQ.frame()
end
check(AQ.changes == before, "no further moves once settled",
      "changes went " .. before .. " -> " .. AQ.changes)

print("")
print("== 5. a hitch is not evidence ==")
restart(true, 2712, 1220)
run(600, 12)                       -- comfortably fast: it has climbed
local afterFast = AQ.divisor()
moves = AQ.changes
-- a mesh build, a shader compile, a roamer bake: seconds of 400 ms frames
run(200, 400)
check(AQ.changes == moves, "400 ms frames move nothing (over OUTLIER_MS)",
      "changes " .. moves .. " -> " .. AQ.changes)
check(AQ.divisor() == afterFast, "and the rung is where it was")

print("")
print("== 5b. A DEVICE THAT IS SLOW EVERYWHERE ==")
-- The regression test for the bug this file's own first version had: the
-- outlier gate was a flat 250 ms, and the machine this whole effort exists
-- for was running at 1000 ms a frame.  Every sample looked like a hitch, the
-- ring never filled, and the governor sat there doing nothing at one frame a
-- second.  A threshold that assumes the machine is already fast cannot be
-- used to find out whether it is.
--
-- What this case is really asserting is that the frames are ACCEPTED at all
-- -- that the gate scales with the machine.  It used to assert that as "it
-- reaches the floor", which only worked because the fake machine's cost was
-- flat in the rung; that is now case 2b's job.  A slow machine that is slow
-- for reasons RES cannot fix is supposed to stop, and the proof the gate did
-- its work is that the governor MOVED and reached a verdict at all.
restart(true, 2712, 1220)
d = run(1200, 1000)                -- one frame a second, sustained
check(AQ.changes > 0, "1000 ms frames are accepted, so the governor fires",
      "changes = " .. AQ.changes .. ", still 1/" .. d)
check(AQ.inert, "and a machine that is slow at every rung stops rather than "
                .. "grinding to the floor")
-- The same machine, but one where the pixels really are the cost: it has to
-- reach the floor, and the relative gate is what lets it get there.
restart(true, 2712, 1220)
d = runF(1600, fillBound(40, 15000))   -- 978 ms at 1/4, 275 at 1/6, 274...
check(d == 8, "a slow machine that IS fill-bound still reaches the floor",
      "got 1/" .. d .. " after " .. AQ.changes .. " moves")

-- and the gate still has to reject a genuine hitch ON such a device: four
-- seconds is a bake, not a frame, whatever the baseline is
restart(true, 2712, 1220)
run(600, 300)
moves = AQ.changes
run(120, 20000)
check(AQ.changes == moves, "20 s frames are still refused on a slow device",
      "changes " .. moves .. " -> " .. AQ.changes)

print("")
print("== 6. it never leaves the ladder ==")
restart(true, 2712, 1220)
run(4000, 5000)                    -- absurd, but all of it outliers
check(AQ.divisor() >= 1 and AQ.divisor() <= 8, "divisor stays in range")
restart(true, 2712, 1220)
for i = 1, 4000 do
  clock.t = clock.t + ((i % 2 == 0) and 0.200 or 0.001)
  AQ.frame()
end
local dd = AQ.divisor()
local inLadder = false
for _, v in ipairs(AQ.LADDER) do if v == dd then inLadder = true end end
check(inLadder, "alternating fast/slow still lands on a real rung",
      "got 1/" .. tostring(dd))

print("")
print(("%d checks, %d failures"):format(checks, fails))
if fails > 0 then os.exit(1) end
