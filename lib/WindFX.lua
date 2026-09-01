-- Voxel world mode: the wind you can SEE.
--
-- Wind.lua bends the grass; this file fills the air when grass is not on
-- screen. What it fills it with is the animated strips in WindFX.SHEETS
-- (Pimen's swoosh, crescent, puff, vortex and dust kick) and the coloured
-- leaf strip -- and the RULES written above that table, which are the
-- whole point of this file.
--
-- Kinds the wind itself spawns (picked by weather + wind strength):
--   ribbon   the swoosh, aligned to travel        (dry, more in a gale)
--   curl     a small crescent turning over        (dry breeze)
--   leaf     a leaf tumbling, three colourways    (any dry air, rain)
--   wetpuff  a small puff, tinted like the spray  (rain, snow)
--   kick     dust thrown off the ground           (dry gust front only)
--   whirl    a vortex standing on the ground      (gale gust front only)
--
-- Kinds only WindFX.emit's callers spawn (VegFX, SprayFX, StepFX), drawn
-- as the authored cel stamps (assets/vfx/wind_*.png from
-- tools/make_wind_sprites.py): grit, seed, dash, spray, snow, puff.
--
-- Gust front: a rank of ribbons across the view + the ground kicked once
-- (+ the whirl, sometimes), on the same Wind.gust envelope the grass
-- already bows to.

local V = ...

local DayNight = V.require("DayNight")
local Wind = V.require("Wind")
local Weather = V.require("Weather")
local Quality = V.require("Quality")
local Voxel3D = V.require("Voxel3D")
local Particles = V.require("Particles")
local ParticleMesh = V.require("ParticleMesh")

local Map = require("src.world.Map")

local WindFX = {}

local function game()
  return require("src.core.Game")
end

local rand = love.math.random

-- Below this tip-reach the air shows nothing. Calm stays calm.
WindFX.FLOOR = 0.48

-- ------- WHICH PASS THE FIELD IS PAINTED IN
--
-- true  = geometry inside the scene pass, depth-tested (WindFX.drawWorld)
-- false = the old overlay paint, in front of everything (WindFX.draw)
--
-- Kept as a switch rather than deleted, and not out of sentiment: the two
-- paths differ ONLY in whether the world is allowed to hide a mote, so
-- flipping this in one build and screenshotting both is the entire proof
-- that occlusion arrived and nothing else moved with it. See
-- tests/particles_occlusion_probe.lua.
WindFX.WORLD_PASS = true

-- Freeze the field: no clear, no spawn, no step. Set by probes that have
-- placed their own fixture with pinOne and need it to be the only thing on
-- screen -- the ordinary update would refill the air around it within a
-- frame, and stilling the WIND instead would take the clear() path and
-- delete the fixture along with everything else.
WindFX.HOLD = false

-- Was 140, and that was a laptop's number rather than a squall's. The
-- field is drawn as sprite batches over a handful of images, so what it
-- costs is a table per mote and fill rate; QUALITY still cuts it by RES
-- for anyone who wants it cut.
WindFX.MAX = 380               -- hard ceiling; Quality.windStreaks cuts by RES
WindFX.REACH = 12
WindFX.SPAWN_AHEAD = 5
WindFX.SPAWN_WIDE = 8
WindFX.SPEED = 28              -- world px/s per unit Wind.amount
WindFX.TAIL = 0.14

WindFX.FRONT_AT = 0.70
WindFX.FRONT_WAIT = 2.5
WindFX.FRONT_WIDE = 8

-- ------- THE DOWNLOADED SHEETS, AND THE RULES THEY PLAY BY
--
-- Five strips cut from Pimen's Wind Spell Effect 01/02 and Smoke n Dust 03
-- (tools/install_pimen_wind.py; provenance and licence in
-- assets/vfx/LICENSE.md). They replace an earlier set of OpenGameArt sheets
-- whose first wiring put them INTO the standing field: every grain, puff
-- and dash became a 96 px animation, turned by its own spin, its clip
-- stretched over a random lifetime, up to three hundred of them at once.
-- Pretty, and noise -- because a sheet is not a mote. A mote is a thing
-- the air carries; a sheet is an EVENT with a beginning and an end. So:
--
--   1. The air's sheets (ribbon, curl, wet puff) ARE the standing field, a
--      few at a time (STANDING_MAX), each born inside the view. The ground
--      sheet (dust kick) and the hero (whirl) play only at a GUST FRONT
--      -- the Wind.gust envelope the grass bows to -- with slots kept for
--      them (FRONT_RESERVE) so a full field cannot crowd the front out.
--   2. A sheet plays its clip once at its own frame rate; its lifetime IS
--      the clip's length, never a random draw. The two that loop (curl,
--      whirl) dwell for a written span (`dwell` + up to `jitter`) instead.
--   3. A sheet keeps its authored up. The ribbon alone follows its travel,
--      and flips instead of turning over when the wind runs left. Nothing
--      spins.
--   4. A sheet has one size, in world px. No per-mote size jitter.
--   5. Ground sheets (whirl, dust kick) stand on the ground under them:
--      no bob, no lift, no flutter.
--   6. At most ONE hero (the whirl) is in the air, and only in a gale --
--      and today none: HERO_CHANCE is 0. A vortex at the player's feet
--      was one more thing happening at the player's feet.
--   7. The grey cel stamps (grit, seed, dash, puff, spray, snow) are not
--      drawn by the wind any more: a screen of grey specks over the path
--      read as dirt on the lens, and the authored 16 px leaf silhouettes
--      read as no leaf at all. Their kinds, images and draw code stay,
--      for WindFX.emit's other callers -- and a "leaf" emitted by VegFX
--      is a sheet now too, so a leaf torn off a tree tumbles like one.
--   8. Dry air plays the swoosh. Wet air plays the puff, tinted like the
--      spray. The ground is kicked only if KICK is on -- it is off: a
--      dust burst on the path read as a fart from nowhere.
--   9. The wind is BACKGROUND. Everything but the leaf rides high -- up
--      by the tree crowns (`band`) -- and faint (`alpha`), so it reads as
--      weather passing over the diorama, never as a thing happening at
--      the player's feet. The leaf is the one piece at eye level and at
--      full strength, because a leaf is a thing and a gust is not.
--
-- A sheet mote is a mote whose kind names a row here. The solver steps it
-- like any other (its own KINDS row says how it moves); only the draw is
-- different, and both draw paths read it through sheetCard() below.
--
--   img      key in the sprite pack       fw/fh   frame size, px
--   cols/n   grid columns / frame count   fps     the clip's own clock
--   hw       half-width in world px (height follows the frame's aspect)
--   align    turn with travel (rule 3)    loop    replay instead of ending;
--            lifetime is then `dwell` + rand * `jitter` seconds
--   ground   stand on the ground; `foot` is how much of the half-height
--            sits above it (1 = the card's bottom edge is the ground)
--   climate  take the spray / blown tint in wet air (rule 8)
--   variants the strip holds this many copies of the clip side by side
--            (colourways); a mote picks one at birth and keeps it
--   band     { lo, hi } world px above the ground the sheet lives in
--            (rule 9); absent = the field's own 6..14 above the ground
--   alpha    strength of the card (rule 9); absent = 1
WindFX.SHEETS = {
  -- EdgeLoopRepeat's leaf, tumbling: fall / spring / winter colourways.
  -- The tumble is the clip's; the mote itself never spins (rule 3).
  leaf    = { img = "leaf",    fw = 16, fh = 16, cols = 15, n = 5,  fps = 10,
              hw = 4.5,  loop = true, dwell = 2.2, jitter = 2.8, variants = 3 },
  -- Wind Breath: a swoosh with leaves in its tail. THE wind you see --
  -- high and faint, passing over the crowns.
  ribbon  = { img = "breath",  fw = 48, fh = 32, cols = 11, n = 11, fps = 16,
              hw = 14.0, align = true, band = { 30, 48 }, alpha = 0.30 },
  -- Wind Projectile: a small crescent turning over. The breeze's mote.
  curl    = { img = "curl",    fw = 32, fh = 32, cols = 6,  n = 6,  fps = 12,
              hw = 5.0,  loop = true, dwell = 1.4, jitter = 1.2,
              band = { 28, 44 }, alpha = 0.30 },
  -- Smoke n Dust 5: a small puff. The wet air's mote, tinted.
  wetpuff = { img = "wetpuff", fw = 32, fh = 32, cols = 6,  n = 6,  fps = 14,
              hw = 7.0,  climate = true, band = { 26, 44 }, alpha = 0.35 },
  -- Pull in: a vortex, looping on the ground. The gale's hero, faint.
  whirl   = { img = "whirl",   fw = 48, fh = 48, cols = 7,  n = 7,  fps = 12,
              hw = 12.0, loop = true, dwell = 3.0, jitter = 1.5,
              ground = true, foot = 1.0, alpha = 0.35 },
  -- Smoke n Dust 1: dust thrown up and settling. The front's ground.
  kick    = { img = "kick",    fw = 80, fh = 64, cols = 9,  n = 9,  fps = 16,
              hw = 12.0, ground = true, foot = 0.85 },
}

WindFX.STANDING_MAX = 10       -- the standing field, sheets and leaves
WindFX.FRONT_SHEETS = 4        -- ribbons (or wet puffs) per front
WindFX.FRONT_RESERVE = 6       -- slots the standing field may not take
WindFX.KICK = false            -- dry fronts kick dust off the ground (rule 8)
WindFX.HERO_AT = 1.40          -- Wind.amount() the whirl needs (gale)
-- The whirl is OFF (rule 6): the only two things in the air are the leaf
-- and the background wind. Wired and measured; a number turns it back on.
WindFX.HERO_CHANCE = 0         -- per front, when eligible and none live
WindFX.SHEET_IN = 0.10         -- fade guards against a pop, under the
WindFX.SHEET_OUT = 0.25        -- clip's own first and last frames
-- A card turns only in its own plane, so travel along z can be hinted at
-- but not drawn; this is how much of it leaks into the tilt.
WindFX.SHEET_TILT = 0.5
-- Where a sheet is born, in cells upwind of the player. A sheet's life is
-- its clip and nothing else, so it has to be born where it will be SEEN,
-- not six cells upwind like the rank of dashes that flies in.
WindFX.SHEET_BACK = { leaf = 2.0, ribbon = 2.5, curl = 3.0, wetpuff = 2.5,
                      whirl = 3.0, kick = 0.5 }

-- How much of the field's own speed one unit of eddy is worth (T7): the
-- solver samples Wind.turbAt per mote and converts at speed * TURB. Half
-- the mean at full envelope is strong texture that still transports --
-- the eddies are zero-mean, so the field swirls without losing its wind.
WindFX.TURB = 0.5

-- Flat palettes on the 5-bit lattice. Dust has several warm greys so a
-- field of grit is not one identical tint; spray/snow stay singular.
WindFX.DUST = { 0.92, 0.86, 0.68 }
WindFX.DUST_B = { 0.86, 0.78, 0.58 }   -- dirtier
WindFX.DUST_C = { 0.96, 0.92, 0.80 }   -- pale sand
WindFX.DUST_D = { 0.78, 0.70, 0.52 }   -- dark grit
WindFX.SEED = { 0.78, 0.84, 0.55 }
WindFX.SEED_B = { 0.88, 0.76, 0.42 }   -- dry chaff
WindFX.SPRAY = { 0.72, 0.82, 0.96 }
WindFX.BLOWN = { 0.96, 0.97, 1.00 }
WindFX.DASH = { 0.94, 0.90, 0.80 }
WindFX.LEAF = {
  { 1.00, 1.00, 1.00 },
  { 0.82, 1.10, 0.52 },
  { 1.15, 1.02, 0.40 },
  { 1.12, 0.50, 0.28 },
  { 0.70, 0.42, 0.24 },
  { 0.95, 0.34, 0.26 },
  { 0.55, 0.75, 0.32 },
  { 0.80, 0.62, 0.36 },
}

-- ------- WHAT SEPARATES ONE MOTE FROM ANOTHER, AS A TABLE
--
-- These are the numbers that used to be an if-chain inside the update
-- loop. Same values, read from here instead of branched to -- which is
-- what lets lib/Particles.lua integrate a leaf and a grain of grit
-- through one piece of arithmetic, and what lets the drag task change how
-- they differ in one place rather than in a ladder of elseifs.
--
-- `mass` and `area` are written down and read by nothing today: they are
-- the drag task's inputs, and putting them here now means that task is a
-- change to a solver rather than a change to every kind.
WindFX.KINDS = {
  grit  = { speed = 0.68, bob = 3.0, mass = 0.40, area = 0.30 },
  snow  = { speed = 0.68, bob = 3.0, mass = 0.22, area = 0.90 },
  puff  = { speed = 0.85, bob = 5.5, mass = 0.18, area = 1.20 },
  seed  = { speed = 1.00, bob = 7.5, mass = 0.30, area = 1.40 },
  spray = { speed = 1.00, bob = 7.5, mass = 0.55, area = 0.60 },
  dash  = { speed = 1.18, bob = 3.0, mass = 0.50, area = 0.35 },
  -- a leaf does not travel at one speed: it stalls, catches, and goes
  -- again. That pulse was the one per-kind rule the old loop could not
  -- write as a constant, so a kind's speed is allowed to be a function of
  -- the particle and its age.
  leaf  = {
    speed = function(p, t) return 0.78 + 0.20 * math.sin(t * 3.1 + (p.seed or 0)) end,
    bob = 9.5, mass = 0.12, area = 2.20,
  },
  -- the sheets (rules 3 and 5). The ribbon flies straight like a dash;
  -- the curl drifts and wanders like a seed; the wet puff drifts like a
  -- puff; the whirl crawls, heavy; the dust kick is the ground itself and
  -- does not move at all.
  ribbon  = { speed = 1.18, bob = 0,   mass = 0.50, area = 0.35, curlA = 0, curlB = 0 },
  curl    = { speed = 0.90, bob = 3.0, mass = 0.30, area = 1.00 },
  wetpuff = { speed = 0.85, bob = 0,   mass = 0.30, area = 1.20, curlA = 0, curlB = 0 },
  whirl   = { speed = 0.30, bob = 0,   mass = 4.00, area = 1.00, curlA = 0, curlB = 0 },
  kick    = { speed = 0,    bob = 0,   mass = 0,    area = 1.00, curlA = 0, curlB = 0 },
}

-- Rule 5 as clamps: a ground sheet's height above the ground under it is
-- fixed to where its foot lands, so the solver's own clamp holds it there
-- through every step -- including the frame it is born on.
for name, s in pairs(WindFX.SHEETS) do
  local k = WindFX.KINDS[name]
  if s.ground then
    local foot = s.hw * (s.fh / s.fw) * (s.foot or 1)
    k.lowClamp, k.highClamp = foot, foot
  elseif s.band then
    -- rule 9 as clamps too: the solver keeps a high sheet high
    k.lowClamp, k.highClamp = s.band[1], s.band[2]
  end
end

local field = Particles.newField(WindFX.KINDS, WindFX.MAX)
local frontCool = 0

-- The wind's OWN standing motes. VegFX, SprayFX and StepFX put theirs in
-- this field through WindFX.emit (marked veg / src), and with the field
-- capped at STANDING_MAX a dozen grass seeds were enough to fill the count
-- and leave the wind itself nothing to spawn.
local function ownStanding(m) return not m.front and not m.veg and not m.src end

-- The step's context, reused. Building it fresh each frame was a table per
-- frame handed straight to the collector -- small against what the engine
-- allocates anyway, but this file has just finished pooling its motes for
-- exactly that reason and it would be odd to pool a hundred tables and then
-- drop one on the floor every frame.
local stepCtx = {}

-- Diagnostics for the same reason Weather.ticks exists: a probe found this
-- field frozen at 102 motes under a budget of 44, which the per-frame
-- setCap makes impossible if the update ran at all. `ticks` says whether
-- it was called; `lastGate` says which of the seven conditions in `live`
-- sent it home if it was.
WindFX.ticks = 0
WindFX.ticksLive = 0
WindFX.lastGate = "never ran"
WindFX.fronts = 0          -- gust fronts spawned so far (probes)

local imgs = nil     -- { grit, seed, dash, swirl, swirlQ, swirlN } | false

local function loadImgs()
  if imgs ~= nil then return imgs or nil end
  local function one(name)
    local path = V.path .. "/assets/vfx/" .. name
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then
      pcall(img.setFilter, img, "nearest", "nearest")
      return img
    end
    return nil
  end
  local grit = one("wind_dust.png")
  local seed = one("wind_mote.png")
  local dash = one("wind_streak.png")
  local puff = one("wind_puff.png")
  local swirl = one("wind_swirl.png")
  local leaves = one("leaves.png")
  local leaf = one("wind_leaf.png")
  local breath = one("wind_breath.png")
  local curl = one("wind_curl.png")
  local whirl = one("wind_whirl.png")
  local kick = one("wind_kick.png")
  local wetpuff = one("wind_wetpuff.png")
  local swirlQ, swirlN = nil, 0
  if swirl then
    local fh = swirl:getHeight()
    swirlN = math.max(1, math.floor(swirl:getWidth() / math.max(1, fh)))
    swirlQ = {}
    for i = 0, swirlN - 1 do
      swirlQ[i] = love.graphics.newQuad(i * fh, 0, fh, fh, swirl:getDimensions())
    end
  end
  if not (grit or seed or dash or swirl or puff) then
    imgs = false
    return nil
  end
  local leafQ, leafN = nil, 0
  if leaves then
    local fw = 16
    leafN = math.max(1, math.floor(leaves:getWidth() / fw))
    leafQ = {}
    for i = 0, leafN - 1 do
      leafQ[i] = love.graphics.newQuad(i * fw, 0, fw, fw, leaves:getDimensions())
    end
  end
  imgs = {
    grit = grit, seed = seed or grit, dash = dash or seed,
    puff = puff, swirl = swirl, swirlQ = swirlQ, swirlN = swirlN,
    leaves = leaves, leafQ = leafQ, leafN = leafN,
    -- the sheets, under the names WindFX.SHEETS[*].img use
    leaf = leaf, breath = breath, curl = curl, whirl = whirl, kick = kick,
    wetpuff = wetpuff,
    -- overlay-path quads for them, built on first use
    sheetQ = {},
  }
  return imgs
end

-- The sprite pack, for the other emitters that draw the same dust
-- through their own fields (StepFX is the first). One load, one texture
-- identity, no second copy of wind_dust.png in memory.
function WindFX.pack()
  return loadImgs()
end

-- ------- how high the ground is under a mote
--
-- Cached per cell for the frame: a field of three hundred motes asking the
-- terrain its own question three hundred times a frame is the sort of
-- thing that turns a cheap effect into an expensive one, and the answer
-- for a given cell cannot change inside one frame.
local ghCache, ghFrame = {}, -1

local function groundUnder(wx, wz)
  local Game = game()
  local ow = Game and Game.overworld
  local map = ow and ow.map
  if not map then return 0 end
  local t = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
  if t ~= ghFrame then
    for k in pairs(ghCache) do ghCache[k] = nil end
    ghFrame = t
  end
  local cx = math.floor((wx or 0) / 16)
  local cy = math.floor((wz or 0) / 16)
  local key = cx * 4096 + cy
  local h = ghCache[key]
  if h then return h end
  local VoxelScene = V.require("VoxelScene")
  local ok, v = pcall(VoxelScene.groundAt, map, cx, cy)
  h = (ok and tonumber(v)) or 0
  ghCache[key] = h
  return h
end

local function openSky(map)
  if not (map and map.def) then return false end
  if not Map.isOutdoor(map.def) then return false end
  return not DayNight.isCanopy(map)
end

-- What the air carries + palette + brightness. The kind is the weather's
-- own word ("rain", "snow", "dry"): every consumer compares against
-- those, and this used to answer "spray" for rain, which nothing ever
-- matched -- a shower got the dry mix and the dry tint.
local function climate()
  local kind = Weather.visible()
  if kind == "rain" then return "rain", WindFX.SPRAY, 0.72 end
  if kind == "snow" then return "snow", WindFX.BLOWN, 0.88 end
  return "dry", WindFX.DUST, 0.78
end

local function budget()
  local n = WindFX.MAX
  local ok, q = pcall(Quality.windStreaks)
  if ok and tonumber(q) then n = math.floor(q) end
  if n < 0 then n = 0 end
  if n > WindFX.MAX then n = WindFX.MAX end
  return n
end

-- ------- WHAT THE STANDING FIELD IS MADE OF (rules 1, 7, 8)
--
-- The strength of the wind is a VOCABULARY, not a density: a breeze is
-- leaves adrift and small crescents turning over; a wind is those plus
-- the odd swoosh; a gale is mostly swooshes. Rain soaks the air -- the
-- sheet is the wet puff, tinted like the spray -- and still tears leaves
-- off, because a wet gale strips a tree faster than a dry one. Snow is
-- the puff alone, blown white.
local function pickKind(amount, front, climateKind)
  if front then return (climateKind == "dry") and "ribbon" or "wetpuff" end
  if climateKind == "snow" then return "wetpuff" end
  local r = rand()
  if climateKind == "rain" then
    return (r < 0.55) and "wetpuff" or "leaf"
  end
  if amount < 0.75 then
    if r < 0.50 then return "leaf" end
    if r < 0.90 then return "curl" end
    return "ribbon"
  elseif amount < 1.40 then
    if r < 0.35 then return "leaf" end
    if r < 0.60 then return "curl" end
    return "ribbon"
  end
  if r < 0.30 then return "leaf" end
  if r < 0.40 then return "curl" end
  return "ribbon"
end

local spawnSheet   -- defined below spawn(); the two are mutually aware

local function dustTint()
  local r = rand()
  if r < 0.28 then return WindFX.DUST end
  if r < 0.52 then return WindFX.DUST_B end
  if r < 0.76 then return WindFX.DUST_C end
  return WindFX.DUST_D
end

local function seedTint()
  return (rand() < 0.55) and WindFX.SEED or WindFX.SEED_B
end

local function spawn(px, pz, amount, opts)
  if field:count() >= budget() then return end
  opts = opts or {}
  local dx, dz = Wind.DIR[1] or 1, Wind.DIR[2] or 0
  local back = (opts.back or WindFX.SPAWN_AHEAD) * 16
  -- wider scatter when the wind is hard so the stream fills the view
  local wide = WindFX.SPAWN_WIDE * (0.75 + 0.55 * math.min(1.4, amount))
  local side = (opts.side ~= nil) and opts.side
               or (rand() * 2 - 1) * wide * 16
  local x = px - dx * back - dz * side
  local z = pz - dz * back + dx * side
  local climateKind = opts.climate or "dry"
  local kind = opts.kind or pickKind(amount, opts.front, climateKind)
  -- a sheet is born by its own rules, not by the ladder below
  if WindFX.SHEETS[kind] then
    return spawnSheet(kind, px, pz, side, opts.front)
  end

  -- Height by kind: grit skims the grass, seeds float mid, dashes higher.
  -- measured from the ground under the spawn, not from world zero
  local floor = groundUnder(x, z)
  local y
  if kind == "grit" or kind == "snow" then
    y = floor + 1.8 + rand() * 6
  elseif kind == "puff" then
    y = floor + 3 + rand() * 8
  elseif kind == "leaf" then
    y = floor + 6 + rand() * 18
  elseif kind == "seed" or kind == "spray" then
    y = floor + 5 + rand() * 12
  else
    y = floor + 5 + rand() * 14
  end

  local tint
  if kind == "grit" or kind == "puff" then
    tint = dustTint()
  elseif kind == "seed" then
    tint = seedTint()
  elseif kind == "leaf" then
    tint = WindFX.LEAF[rand(1, #WindFX.LEAF)]
  end

  -- A claimed slot is a WIPED slot, so nothing carries over from whoever
  -- held it last; every field this kind reads is written here.
  local m = field:claim()
  if not m then return end
  m.x, m.z, m.y = x, z, y
  m.kind = kind
  m.seed = rand() * 6.2831
  m.t = 0
  m.ttl = (kind == "dash" and (1.0 + rand() * 1.1))
       or (kind == "grit" and (1.2 + rand() * 1.6))
       or (kind == "puff" and (1.3 + rand() * 1.5))
       or (kind == "leaf" and (2.2 + rand() * 2.8))
       or (1.6 + rand() * 2.2)
  m.fast = 0.55 + rand() * 0.90
  m.lift = (rand() * 2 - 1) * (kind == "dash" and 3 or (kind == "leaf" and 8 or 6))
  m.spin = (rand() * 2 - 1) * ((kind == "leaf" and (3.5 + rand() * 5))
                            or ((kind == "seed" or kind == "puff") and 4.5 or 1.6))
  m.frame = kind == "leaf" and rand(0, 15) or 0
  m.flip = rand() < 0.5 and -1 or 1
  m.front = opts.front or false
  -- wide size range so a cloud of grit is not one stamp; a leaf keeps to
  -- a narrow one, because a leaf at half size is a speck again
  m.size = (kind == "leaf") and (0.8 + rand() * 0.4) or (0.45 + rand() * 1.05)
  m.tint = tint
  m.ang = 0
end

-- ------- T11: SPAWN AT AN EXACT POINT
--
-- spawn() above answers "put something in the AIR around the player" and
-- picks its own position from the wind. An emitter that knows WHERE a
-- particle comes from -- a tree crown shedding the leaf, a grass tuft
-- letting a seed go (VegFX) -- needs the opposite: the position is the
-- point, everything else defaults like spawn()'s. Same budget, same
-- field, same draw; `opts` overrides ttl/size/tint/lift/spin/fast, and
-- opts.veg marks the mote as vegetation-born so a probe can tell a leaf
-- torn OFF A TREE from the generic storm leaf pickKind carries in.
function WindFX.emit(kind, x, y, z, opts)
  if field:count() >= budget() then return false end
  opts = opts or {}
  local m = field:claim()
  if not m then return false end
  m.x, m.z, m.y = x, z, y
  m.kind = kind or "grit"
  m.seed = rand() * 6.2831
  m.t = 0
  m.ttl = opts.ttl or (1.6 + rand() * 2.2)
  m.fast = opts.fast or (0.55 + rand() * 0.90)
  m.lift = opts.lift or ((rand() * 2 - 1) * 6)
  m.spin = opts.spin or ((rand() * 2 - 1)
             * ((kind == "leaf" and (3.5 + rand() * 5)) or 3))
  m.frame = kind == "leaf" and rand(0, 15) or 0
  m.flip = rand() < 0.5 and -1 or 1
  m.front = false
  m.size = opts.size or (0.45 + rand() * 1.05)
  m.tint = opts.tint
  m.ang = 0
  m.veg = opts.veg or nil
  -- which emitter this mote was born from ("water", ...), for probes that
  -- need to judge one emitter's motes among everybody else's
  m.src = opts.src or nil
  if opts.vx then m.vx, m.vz = opts.vx, opts.vz or 0 end
  return true
end

-- for probes that need to look at the motes themselves
function WindFX.count() return field:count() end
function WindFX.get(i) return field:get(i) end

-- ------- A SHEET, BORN
--
-- Every field the solver and sheetCard() read is written here, and the
-- rules are visible as the constants: no spin, no lift, size 1, a seed of
-- 0, and a lifetime that is the clip's own (rule 2) or the hero's dwell.
spawnSheet = function(name, px, pz, side, front)
  local s = WindFX.SHEETS[name]
  if not s then return false end
  if field:count() >= budget() then return false end
  local dx, dz = Wind.DIR[1] or 1, Wind.DIR[2] or 0
  local back = (WindFX.SHEET_BACK[name] or WindFX.SPAWN_AHEAD) * 16
  local x = px - dx * back - dz * side
  local z = pz - dz * back + dx * side
  local hh = s.hw * (s.fh / s.fw)
  local floor = groundUnder(x, z)
  local y
  if s.ground then
    y = floor + hh * (s.foot or 1)
  elseif s.band then
    y = floor + s.band[1] + rand() * (s.band[2] - s.band[1])
  else
    y = floor + 6 + rand() * 8
  end
  local m = field:claim()
  if not m then return false end
  m.x, m.z, m.y = x, z, y
  m.kind = name
  m.seed = 0
  m.t = 0
  if s.loop then
    m.ttl = (s.dwell or 1) + rand() * (s.jitter or 0)
  else
    m.ttl = s.n / s.fps
  end
  m.fast = 1
  m.lift = 0
  m.spin = 0
  m.frame = 0
  m.flip = 1
  m.front = front and true or false
  m.size = 1
  m.tint = nil
  m.ang = 0
  -- colourway, picked once. The leaf's are fall / spring / winter; most
  -- of what blows around is the first two
  if s.variants then
    local r = rand()
    m.variant = (r < 0.45) and 0 or ((r < 0.85) and 1 or 2)
  end
  return true
end

local function isHero(m) return m.kind == "whirl" end

-- One gust front: a rank of the climate's sheet across the view, the
-- ground kicked once, and -- in a gale, sometimes -- the hero.
local function spawnFront(px, pz, amount, climateKind)
  WindFX.fronts = (WindFX.fronts or 0) + 1
  local wide = WindFX.FRONT_WIDE * 16

  -- rule 8: the air's sheet follows the climate
  local air = (climateKind == "dry") and "ribbon" or "wetpuff"
  local ns = WindFX.FRONT_SHEETS
  for i = 1, ns do
    local f = (ns > 1) and ((i - 1) / (ns - 1) * 2 - 1) or 0
    spawnSheet(air, px, pz, f * wide * 0.6 + (rand() * 2 - 1) * 6, true)
  end

  -- rule 8: only dry ground has dust to kick
  if WindFX.KICK and climateKind == "dry" then
    spawnSheet("kick", px, pz, (rand() * 2 - 1) * wide * 0.3, true)
  end

  -- rule 6: the hero, alone, and only in a gale
  if amount >= WindFX.HERO_AT and rand() < WindFX.HERO_CHANCE
     and field:countIf(isHero) == 0 then
    spawnSheet("whirl", px, pz, (rand() * 2 - 1) * wide * 0.5, true)
  end
end

function WindFX.clear()
  field:clear()
end

function WindFX.update(dt, voxelOn)
  WindFX.ticks = WindFX.ticks + 1
  if WindFX.HOLD then WindFX.lastGate = "HOLD" return end
  dt = tonumber(dt) or 0
  if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
  frontCool = frontCool - dt

  local amount = 0
  local okA, n = pcall(Wind.amount)
  if okA then amount = n or 0 end

  local cap = budget()
  -- the live ceiling is the RES rung's, not WindFX.MAX -- and it moves
  -- when the row does, so it is pushed every frame rather than at build
  field:setCap(cap)
  local Game = game()
  local ow = Game and Game.overworld
  local live = voxelOn and cap > 0 and amount > WindFX.FLOOR
                and ow and ow.map and ow.player
                and openSky(ow.map)
                and Game.stack and Game.stack:top() == ow
                and not ow.transitioning
  if not live then
    WindFX.lastGate =
      (not voxelOn and "voxelOn=false")
      or (cap <= 0 and "budget=0")
      or (amount <= WindFX.FLOOR and "wind below FLOOR")
      or (not (ow and ow.map and ow.player) and "no overworld/map/player")
      or (not openSky(ow.map) and "indoors (no open sky)")
      or (not (Game.stack and Game.stack:top() == ow) and "overworld not on top")
      or (ow.transitioning and "map transitioning")
      or "unknown"
    WindFX.clear()
    return
  end
  WindFX.lastGate = "live"
  WindFX.ticksLive = WindFX.ticksLive + 1

  local climateKind = select(1, climate())
  local p = ow.player
  local px, pz = p.cellX * 16, p.cellY * 16

  -- Density scales hard with wind: weak breeze = a few specks, gale = a
  -- stream. Quadratic so the middle of AUTO does not already look full.
  -- Rule 1: the field is a handful of sheets and leaves, not a cloud of
  -- specks, and the front always finds a slot.
  local headroom = math.max(0, cap - WindFX.FRONT_RESERVE)
  if headroom > WindFX.STANDING_MAX then headroom = WindFX.STANDING_MAX end
  local t = (amount - WindFX.FLOOR) / 1.35
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  local want = math.floor(2 + (t * t) * (headroom - 2))
  if want > headroom then want = headroom end
  if want < 0 then want = 0 end
  local standing = field:countIf(ownStanding)
  -- refill faster under a gale so the field stays dense as motes expire
  local burst = 2 + math.floor(t * 10)
  for _ = 1, math.min(burst, math.max(0, want - standing)) do
    spawn(px, pz, amount, { climate = climateKind })
  end

  local gust = 0
  local okG, g = pcall(Wind.gust)
  if okG then gust = g or 0 end
  if gust >= WindFX.FRONT_AT and frontCool <= 0 then
    frontCool = WindFX.FRONT_WAIT
    spawnFront(px, pz, amount, climateKind)
  end

  -- ------- AND FROM HERE THE AIR IS ONE PIECE OF ARITHMETIC
  --
  -- What used to be sixty lines here -- the band lookup, the per-kind
  -- speed ladder, the two-sine curl, the bob, the ground clamp and the
  -- reach cull -- is lib/Particles.lua now, and the weather's own world
  -- motes will step through the same code. The numbers did not change;
  -- where they live did. Verified as statistics rather than as a claim:
  -- tests/particles_parity_probe.lua samples the field before and after
  -- and prints its own noise floor to judge the difference against.
  --
  -- floorAt is not optional in practice. The clamp used to be an absolute
  -- 0.8..28, which is right on a route's dirt and wrong everywhere worth
  -- standing: a town's paving is raised, so on it the whole dust field ran
  -- INSIDE the street, and on a roof it ran through the tiles. Measuring
  -- from the ground under each mote is what fixed that, and it is why the
  -- solver takes a function rather than two numbers.
  stepCtx.dirX = Wind.DIR[1] or 1
  stepCtx.dirZ = Wind.DIR[2] or 0
  stepCtx.speed = amount * WindFX.SPEED
  -- the eddies (T7): world px/s per unit of Wind.turbAt, this field's own
  -- conversion just like `speed` is
  stepCtx.turbulence = amount * WindFX.SPEED * WindFX.TURB
  stepCtx.floorAt = groundUnder
  stepCtx.originX, stepCtx.originZ = px, pz
  stepCtx.reach = WindFX.REACH * 16 + 48
  field:step(dt, stepCtx)
end

local function imgFor(pack, kind)
  if not pack then return nil end
  if kind == "dash" or kind == "ribbon" then return pack.dash end
  if kind == "leaf" then return pack.leaves end
  if kind == "seed" or kind == "spray" then return pack.seed end
  if kind == "puff" then return pack.puff or pack.grit end
  if kind == "grit" or kind == "snow" then return pack.grit end
  return pack.grit or pack.seed
end

local function colourFor(m, base)
  if m.tint then return m.tint end
  if m.kind == "seed" then return WindFX.SEED end
  if m.kind == "dash" and base == WindFX.DUST then return WindFX.DASH end
  return base
end

-- ------- ONE SHEET MOTE, DESCRIBED FOR EITHER PASS
--
-- Frame, orientation, size and colour of a sheet mote come from here for
-- BOTH the overlay paint and the scene pass, so the two cannot drift.
--
--   returns spec, frame, flipX, ang, r, g, b, a   -- or nil: draw nothing
--
-- `ang` is in the scene card's sense (counter-clockwise, up is up); the
-- overlay, whose y runs down, negates it.
local function sheetCard(m, climateKind)
  local s = WindFX.SHEETS[m.kind]
  if not s then return nil end
  local t = m.t or 0
  local ttl = m.ttl or 1
  -- rule 2: the clip's own clock
  local f = math.floor(t * s.fps)
  if s.loop then
    f = f % s.n
  elseif f > s.n - 1 then
    f = s.n - 1
  end
  -- a colourway is the same clip further along the strip
  if s.variants then f = f + ((m.variant or 0) % s.variants) * s.n end
  -- full strength: the strip carries its own colour and envelope, and the
  -- stamps' `bright` (a tint's brightness) would only wash it out
  local a = math.min(1, t / WindFX.SHEET_IN, (ttl - t) / WindFX.SHEET_OUT)
  a = a * (s.alpha or 1)               -- rule 9: background stays faint
  if a <= 0.02 then return nil end
  -- rule 3: authored up. The ribbon alone follows its travel, and flips
  -- rather than turning over when the wind runs the other way; the tilt
  -- dips the leading edge toward the camera when the travel has any z.
  local ang, flip = 0, 1
  if s.align then
    local vx = m.vx or Wind.DIR[1] or 1
    local vz = m.vz or Wind.DIR[2] or 0
    if vx < 0 then flip = -1; vx = -vx end
    ang = -flip * math.atan2(vz * WindFX.SHEET_TILT, vx)
  end
  local r, g, b = 1, 1, 1
  if s.climate then
    local c = (climateKind == "rain" and WindFX.SPRAY)
           or (climateKind == "snow" and WindFX.BLOWN)
    if c then r, g, b = c[1], c[2], c[3] end
  end
  return s, f, flip, ang, r, g, b, a
end

-- The overlay path draws through quads; one per sheet frame, kept.
local function sheetQuad(pack, kind, s, f)
  local img = pack[s.img]
  if not img then return nil end
  local qs = pack.sheetQ[kind]
  if not qs then qs = {}; pack.sheetQ[kind] = qs end
  local q = qs[f]
  if not q then
    local iw, ih = img:getDimensions()
    local ok, made = pcall(love.graphics.newQuad,
      (f % s.cols) * s.fw, math.floor(f / s.cols) * s.fh, s.fw, s.fh, iw, ih)
    if not ok then return nil end
    q = made
    qs[f] = q
  end
  return img, q
end

function WindFX.draw(project, scale)
  if WindFX.WORLD_PASS then return end
  local live = field:count()
  if live == 0 then return end
  local g = love.graphics
  local climateKind, baseCol, bright = climate()
  local prevBlend, prevAlpha = g.getBlendMode()
  g.setBlendMode("alpha")

  local pack = loadImgs()
  local scl = scale or 1

  -- standing first, front second (front overdraws = closer read)
  for pass = 0, 1 do
    local wantFront = (pass == 1)
    for i = 1, live do
      local m = field:get(i)
      if (m.front and true or false) == wantFront then
        local sx, sy, ps = project(m.x, m.y, m.z)
        if sx then
          local fade = math.min(1, m.t * 4, (m.ttl - m.t) * 2.5)
          local a = bright * fade * (wantFront and 1.2 or 1.0)
          if a > 0.02 then
            local s = math.max(1, scl * (ps or 1))
            local col = colourFor(m, baseCol)
            if climateKind == "rain" then col = WindFX.SPRAY end
            if climateKind == "snow" then col = WindFX.BLOWN end

            local ang = m.ang or 0
            local vx, vz = m.vx or 0, m.vz or 0
            -- align dashes to travel
            if m.kind == "dash" or wantFront then
              local ex, ey = project(m.x - vx * WindFX.TAIL,
                                     m.y, m.z - vz * WindFX.TAIL)
              if ex then ang = math.atan2(sy - ey, sx - ex) end
            end

            local spec = WindFX.SHEETS[m.kind]
            local use = imgFor(pack, m.kind)
            if spec then
              -- a sheet: its own clock, size and up (sheetCard)
              local sh, f, flip, sang, r, gg, b, sa = sheetCard(m, climateKind)
              local img, q = nil, nil
              if sh and pack then img, q = sheetQuad(pack, m.kind, sh, f) end
              if img and q then
                local px = s * sh.hw * 2
                g.setColor(r, gg, b, sa)
                pcall(g.draw, img, q, sx, sy, -sang,
                      flip * px / sh.fw, px / sh.fw, sh.fw * 0.5, sh.fh * 0.5)
              end
            elseif m.kind == "leaf" and pack and pack.leaves and pack.leafQ then
              local n = pack.leafN or 1
              local q = pack.leafQ[(m.frame or 0) % n]
              local flip = math.sin(ang * 0.5)
              local sxS = ((flip >= 0) and 1 or -1) * (m.flip or 1)
              local squash = 0.55 + 0.45 * math.abs(flip)
              local px = math.max(4, s * 1.7 * (m.size or 1))
              g.setColor(col[1], col[2], col[3], math.min(1, a))
              if q then
                pcall(g.draw, pack.leaves, q, sx, sy, ang,
                      sxS * px / 16, squash * px / 16, 8, 8)
              end
            elseif use then
              local iw = use:getWidth()
              local ih = use:getHeight()
              if iw > 0 and ih > 0 then
                local px
                local stretchX, stretchY = 1, 1
                if m.kind == "dash" then
                  px = math.max(5, s * 2.0 * (m.size or 1))
                  stretchX, stretchY = 2.6, 0.85
                elseif m.kind == "seed" or m.kind == "spray" then
                  px = math.max(3.5, s * 1.5 * (m.size or 1))
                  stretchX, stretchY = 1.5, 0.9
                elseif m.kind == "puff" then
                  px = math.max(4, s * 1.8 * (m.size or 1))
                  stretchX, stretchY = 1.2, 1.1
                else
                  -- grit / snow: small hard dots, size varies a lot
                  px = math.max(2.5, s * 1.05 * (m.size or 1))
                  stretchX, stretchY = 1.0, 1.0
                end
                g.setColor(col[1], col[2], col[3], math.min(1, a))
                pcall(g.draw, use, sx, sy, ang,
                      (px * stretchX) / iw, (px * stretchY) / ih,
                      iw * 0.5, ih * 0.5)
              end
            else
              g.setColor(col[1], col[2], col[3], math.min(1, a))
              local d = math.max(1, s * (m.kind == "dash" and 2.5 or 1.0))
              if m.kind == "dash" then
                g.rectangle("fill", sx - d * 1.4, sy - 0.5, d * 2.8, math.max(1, s * 0.5))
              else
                g.rectangle("fill", sx - d * 0.4, sy - d * 0.4, d * 0.8, d * 0.8)
              end
            end
          end
        end
      end
    end
  end

  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  g.setColor(1, 1, 1, 1)
end

-- ------- AND THE SAME FIELD, AS GEOMETRY IN THE SCENE PASS
--
-- The draw above paints into the OVERLAY, which has no depth test by
-- construction -- so every mote in it passed in front of the mountain and
-- through the roof, always. This one hands the field to the scene pass as
-- cards, and the depth buffer answers both.
--
-- Deliberately NOT a rewrite of the look. Image, colour, alpha and angle
-- are read through the very same imgFor / colourFor / climate the overlay
-- draw uses, so the only thing that differs between the two paths is
-- whether the geometry in front of a mote is allowed to hide it. That is
-- what makes the change checkable: anything else that moved is a bug.
--
-- Size does change register, and has to. The overlay sized a mote in
-- SCREEN pixels and multiplied by the projection's own scale to fake
-- perspective; a card of a given WORLD size shrinks with distance because
-- it genuinely is further away. The constants carried over are the old
-- screen numbers read as world pixels -- which is what they always meant
-- at the focus plane, where the projection's scale is one.
local builder = nil

-- Per-kind card size in world pixels, and how it is stretched. Lifted
-- straight out of the overlay draw's ladder so the two agree.
local CARD = {
  dash  = { 2.0, 2.6, 0.85 },
  seed  = { 1.5, 1.5, 0.90 },
  spray = { 1.5, 1.5, 0.90 },
  puff  = { 1.8, 1.2, 1.10 },
  grit  = { 1.05, 1.0, 1.0 },
  snow  = { 1.05, 1.0, 1.0 },
}

function WindFX.drawWorld()
  if not WindFX.WORLD_PASS then return 0 end
  local live = field:count()
  if live == 0 then return 0 end
  local pack = loadImgs()
  if not pack then return 0 end
  local climateKind, baseCol, bright = climate()
  builder = builder or ParticleMesh.newBuilder(WindFX.MAX)

  local leafN = pack.leafN or 1
  local describe = function(m)
    local kind = m.kind

    -- ------- a sheet: one card of the clip's current frame
    if WindFX.SHEETS[kind] then
      local s, f, flip, ang, r, g, b, a = sheetCard(m, climateKind)
      if not s then return nil end
      local img = pack[s.img]
      if not img then return nil end
      local iw, ih = img:getDimensions()
      if iw < 1 or ih < 1 then return nil end
      local u0 = ((f % s.cols) * s.fw) / iw
      local v0 = (math.floor(f / s.cols) * s.fh) / ih
      local u1, v1 = u0 + s.fw / iw, v0 + s.fh / ih
      if flip < 0 then u0, u1 = u1, u0 end
      return img, u0, v0, u1, v1, s.hw, s.hw * (s.fh / s.fw), ang, r, g, b, a
    end

    -- ------- a mote: the authored stamp, as before the sheets (rule 7)
    local img = imgFor(pack, kind)
    if not img then return nil end
    local fade = math.min(1, m.t * 4, (m.ttl - m.t) * 2.5)
    local a = bright * fade * (m.front and 1.2 or 1.0)
    if a <= 0.02 then return nil end
    if a > 1 then a = 1 end
    local col = colourFor(m, baseCol)
    if climateKind == "rain" then col = WindFX.SPRAY end
    if climateKind == "snow" then col = WindFX.BLOWN end

    local u0, v0, u1, v1 = 0, 0, 1, 1
    if kind == "leaf" and pack.leaves then
      -- the strip is leafN frames wide; pick this mote's own
      local f = (m.frame or 0) % leafN
      u0 = f / leafN
      u1 = (f + 1) / leafN
    end

    -- A dash points where it goes. The overlay always aligned it from the
    -- projection; this pass was turning it by its spin, which is the one
    -- thing a streak must not do.
    local ang = m.ang or 0
    if kind == "dash" then
      local vx, vz = m.vx or 0, m.vz or 0
      if vx ~= 0 or vz ~= 0 then
        local flip = (vx < 0) and -1 or 1
        ang = -flip * math.atan2(vz * WindFX.SHEET_TILT, math.abs(vx))
      end
    end

    local c = CARD[kind] or CARD.grit
    local base = c[1] * (m.size or 1)
    local hw = base * c[2] * 0.5
    local hh = base * c[3] * 0.5
    if hw < 0.5 then hw = 0.5 end
    if hh < 0.5 then hh = 0.5 end
    return img, u0, v0, u1, v1, hw, hh, ang, col[1], col[2], col[3], a
  end

  local mesh, batches = builder:build(field, describe)
  if not mesh then WindFX.lastBatches = 0 return 0 end
  -- Depth WRITES on. These sprites are hard cutouts -- white pixels and
  -- fully transparent ones, nothing between (tools/make_wind_sprites.py
  -- authors them that way on purpose) -- and the scene shader discards the
  -- transparent half before it does anything else. So a mote writing its
  -- own depth is honest, and it buys the field its own sorting: a grain in
  -- front of another grain hides it, with no sort in Lua.
  local drew = Voxel3D.drawParticles(mesh, nil, batches, true)
  WindFX.lastBatches = drew
  return drew
end

-- ------- A FIELD OF EXACTLY ONE MOTE, PUT WHERE THE PROBE WANTS IT
--
-- Statistics cannot settle occlusion. The first attempt tried to isolate
-- the field by subtracting a WIND OFF frame -- but WIND OFF also stops the
-- grass, so what it measured was a meadow rather than a mote, and 95% of
-- the frame came back "lit".
--
-- One mote, parked, is unambiguous instead: put inside a building it must
-- DRAW through the overlay and VANISH through the scene pass, and put in
-- the open it must survive both. Two frames, two pixel counts, nothing to
-- interpret.
--
-- `pinned` is what keeps the solver's hands off it -- including the ground
-- clamp, which would otherwise lift a mote placed inside a house up onto
-- its roof and quietly test nothing at all.
function WindFX.pinOne(kind, x, y, z, size)
  field:clear()
  local m = field:claim()
  if not m then return false end
  m.x, m.z, m.y = x, z, y
  m.kind = kind or "puff"
  m.seed = 0
  m.t = 0.5              -- past the fade-in, so alpha is full at once
  m.ttl = 1e6
  m.fast, m.lift, m.spin = 0, 0, 0
  m.frame, m.flip = 0, 1
  m.front = false
  m.size = size or 6
  m.ang = 0
  m.vx, m.vz = 0, 0
  -- magenta: Pallet Town's roofs are red and its grass is green, but
  -- nothing in a Game Boy Pokemon palette is red AND blue at once, so
  -- a pixel with r and b high and g low can only be this mote
  m.tint = { 1.0, 0.0, 1.0 }
  m.pinned = true
  return true
end

-- The ground height under a point, so a probe can place a mote relative to
-- the surface it is testing against rather than to world zero.
function WindFX.groundAt(x, z)
  return groundUnder(x, z)
end

-- How many colour batches the last scene-pass draw actually issued. Zero
-- means the field reached the pass and nothing came out, which is a
-- different failure from an empty field and has to be visible as such.
WindFX.lastBatches = -1

function WindFX.count()
  return field:count()
end

-- ------- WHAT THE FIELD IS DOING, AS NUMBERS
--
-- Aggregates rather than a dump, because the point of them is a BEFORE and
-- an AFTER that have to match: the solver extraction in lib/Particles.lua
-- is a port, and a port whose motion changed is a port nobody can sign
-- off. Individual motes are seeded from love.math.random and will never
-- line up run to run; the statistics of a steady field will.
--
-- Sampled by tests/particles_parity_probe.lua over hundreds of frames of a
-- pinned wind, which is what turns these into something with a tolerance.
function WindFX.stats(out)
  out = out or {}
  local n = field:count()
  out.n = n
  out.kinds = out.kinds or {}
  for k in pairs(out.kinds) do out.kinds[k] = nil end
  local sumV, sumY, sumAge, sumDX, sumDZ, sumSpin = 0, 0, 0, 0, 0, 0
  local minY, maxY = 1e9, -1e9
  for i = 1, n do
    local m = field:get(i)
    local vx, vz = m.vx or 0, m.vz or 0
    sumV = sumV + math.sqrt(vx * vx + vz * vz)
    sumY = sumY + (m.y or 0)
    if (m.y or 0) < minY then minY = m.y or 0 end
    if (m.y or 0) > maxY then maxY = m.y or 0 end
    sumAge = sumAge + ((m.ttl and m.ttl > 0) and (m.t / m.ttl) or 0)
    sumSpin = sumSpin + math.abs(m.spin or 0)
    -- ground-relative spread is what a reach cull actually shapes, and it
    -- is measured from the mote's own floor rather than from world zero
    local g = groundUnder(m.x, m.z)
    sumDX = sumDX + math.abs((m.y or 0) - g)
    sumDZ = sumDZ + (m.size or 0)
    out.kinds[m.kind] = (out.kinds[m.kind] or 0) + 1
  end
  local d = (n > 0) and n or 1
  out.meanSpeed = sumV / d
  out.meanY = sumY / d
  out.meanAboveGround = sumDX / d
  out.meanSize = sumDZ / d
  out.meanAge = sumAge / d
  out.meanSpin = sumSpin / d
  out.minY = (n > 0) and minY or 0
  out.maxY = (n > 0) and maxY or 0
  return out
end

return WindFX
