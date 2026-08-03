-- Voxel world mode: the sound of the place.
--
-- The diorama has butterflies, fireflies, birds crossing the sky and grass
-- bending in the wind, and all of it happens in silence over the map's own
-- looping song. This is the other half: crickets after dark, birdsong in the
-- morning, water moving where there is water to move, and rain when it rains.
--
-- ------- recorded, with the synth kept underneath it
--
-- This shipped once as pure synthesis -- every sound a Game Boy channel
-- program, not a byte of audio on disk -- and it was the wrong call. The
-- reasoning was sound and the result was not: a square-wave blip is a
-- convincing menu beep and an unconvincing cricket, and at the level ambience
-- has to sit, under the map's own looping song, a thin blip is not quiet, it
-- is inaudible. The synth reproduces a Game Boy's sound effects perfectly,
-- because that is exactly what they are. It cannot do a field at dusk,
-- because a field at dusk is a hundred overlapping sources and the hardware
-- has four.
--
-- So the beds are real recordings now, in `assets/audio/`, all five CC0 --
-- see that folder's CREDITS.md for who recorded each and for why nothing here
-- is CC-BY or CC-BY-SA.
--
-- The channel programs are still here and still registered, one per bed, and
-- they earn their place as the FALLBACK: a file missing, an assets folder
-- stripped out of a build, a driver that will not decode Vorbis. Then the bed
-- drops to the synth and the ambience is worse rather than gone. That is what
-- the programs were always actually good for.
--
-- They are registered ids either way (`DS_AMB_CRICKET` and friends), so a
-- sound pack can override one through the engine's own sfx registry.
--
-- ------- beds, not blips
--
-- The other half of what was wrong, and the deeper half. Crickets were
-- scheduled as discrete chirps on a countdown -- which is what the synth
-- could manage -- but a real cricket field is one continuous thing whose
-- LEVEL moves. So four of the five LOOP, and what the world does is crossfade
-- them: nightfall brings the crickets up rather than switching them on,
-- walking away from a river takes the river down, a shower brings the rain up
-- over ten seconds beside the sky going grey. Only thunder is a one-shot,
-- because a thunderclap is one.
--
-- ------- what decides each level
--
-- The same clocks the rest of the mod runs on. DayNight says what hour it is
-- (crickets at night, the dawn chorus in the morning), Weather says what is
-- coming down, and the map itself says whether there is water within earshot
-- -- counted by LOOKING, in cells, rather than by a list of maps with ponds
-- on them. Indoors everything stops but one: RAIN KEEPS PLAYING INDOORS,
-- quieter and pitched down, because standing in a house listening to it come
-- down outside is the best thing weather does.
--
-- Deliberately NOT gated on voxel mode. Every other ambient thing in this mod
-- is a drawing and needs a diorama to be drawn on; a sound needs no camera,
-- so the flat 2D world gets the crickets too.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local DayNight = V.require("DayNight")
local Weather = V.require("Weather")

local Map = require("src.world.Map")

local AmbientSound = {}

AmbientSound.setting = ModSetting.new("ambsound", "SOUNDS",
                                      { "on", "off" }, { "ON", "OFF" })

function AmbientSound.enabled()
  return AmbientSound.setting:get() == "on"
end

function AmbientSound.row()
  return AmbientSound.setting:row()
end

local function game()
  return require("src.core.Game")
end

-- ------- the programs
--
-- Registers, not hertz: the Game Boy's square channels are tuned by an 11-bit
-- period register, and the frequency it makes is 131072 / (2048 - register).
-- So the numbers climb toward 2048 as the pitch rises, and the last few dozen
-- values are the whole top octave -- which is where insects live.
local function freq(hz)
  return math.max(0, math.min(0x7FF, math.floor(2048 - 131072 / hz + 0.5)))
end

-- The noise channel's parameter byte: shift in the high nibble, the divisor
-- code in the low three bits (bit 3 is the 7-bit LFSR width, left clear
-- throughout -- the short LFSR is tonal and metallic, which is a laser, not
-- weather). Higher shift is a lower, rougher noise.
local function noise(shift, divisor)
  return shift * 16 + divisor
end

-- A cricket's stridulation: three thin blips, the last one held. Duty 0 is
-- the 12.5% pulse -- the reediest waveform the hardware has, which is what an
-- insect rubbing its wings together sounds like on this chip.
local CRICKET = {
  channels = { { hw = 1, program = {
    { duty = 0 },
    { squareNote = { len = 2, volume = 9, fade = 2, frequency = freq(4200) } },
    { rest = 1 },
    { squareNote = { len = 2, volume = 9, fade = 2, frequency = freq(4200) } },
    { rest = 1 },
    { squareNote = { len = 3, volume = 10, fade = 2, frequency = freq(4000) } },
  } } },
}

-- The songbird: a rising three-note phrase and a falling two-note answer,
-- with a beat of silence between them, on the 50% duty that is closest to a
-- whistle. Two syllables is what makes it read as a bird rather than as a
-- menu beep -- one tone at any pitch is UI.
local BIRD = {
  channels = { { hw = 1, program = {
    { duty = 2 },
    { squareNote = { len = 2, volume = 8, fade = 0, frequency = freq(2100) } },
    { squareNote = { len = 2, volume = 9, fade = 0, frequency = freq(2500) } },
    { squareNote = { len = 3, volume = 9, fade = 2, frequency = freq(3000) } },
    { rest = 3 },
    { squareNote = { len = 2, volume = 8, fade = 0, frequency = freq(2900) } },
    { squareNote = { len = 4, volume = 9, fade = 2, frequency = freq(2400) } },
  } } },
}

-- The other bird: a chatter rather than a song, for the small ones hopping
-- about the ground. Duty 1 (25%) is thinner and brighter than the whistle.
--
-- No bed of its own any more -- the recorded birdsong is a whole wood at once
-- and needs no second voice beside it. Kept and kept REGISTERED because it
-- costs nothing to and it is a real id a sound pack or another mod can reach
-- for; the fallback chain names BIRD, not this.
local CHIRP = {
  channels = { { hw = 1, program = {
    { duty = 1 },
    { squareNote = { len = 1, volume = 8, fade = 1, frequency = freq(3300) } },
    { rest = 1 },
    { squareNote = { len = 1, volume = 8, fade = 1, frequency = freq(3600) } },
    { rest = 1 },
    { squareNote = { len = 1, volume = 8, fade = 1, frequency = freq(3300) } },
  } } },
}

-- Water on a bank: noise that swells and ebbs. The negative fade is a RISE --
-- the fade nibble is signed, and the engine reads bit 3 as "grow instead of
-- decay" -- so the first note comes up out of nothing and the second falls
-- away, which is one wave arriving and leaving.
local LAP = {
  channels = { { hw = 4, program = {
    { noiseNote = { len = 10, volume = 1, fade = -2, parameter = noise(5, 7) } },
    { noiseNote = { len = 14, volume = 6, fade = 3, parameter = noise(5, 7) } },
  } } },
}

-- Rain: the noise channel held open for a little over two seconds, LOOPED by
-- the source rather than by the program (an effect's own loop command is
-- refused by the synth -- an SFX that never ended would never render).
--
-- The parameter changes on every note and that is the load-bearing part. The
-- synth reseeds the LFSR at each new event, so a bed of identical notes would
-- replay the identical 267ms of noise over and over -- a 3.7 Hz flutter, and
-- once you hear it you cannot stop hearing it. Different shifts and divisors
-- clock the register at different rates, so no two segments are the same
-- sound, and the loop point lands inside a change rather than on one.
local RAIN = {
  channels = { { hw = 4, program = {
    { noiseNote = { len = 16, volume = 6, fade = 0, parameter = noise(5, 7) } },
    { noiseNote = { len = 13, volume = 7, fade = 0, parameter = noise(4, 6) } },
    { noiseNote = { len = 16, volume = 6, fade = 0, parameter = noise(5, 5) } },
    { noiseNote = { len = 11, volume = 7, fade = 0, parameter = noise(6, 7) } },
    { noiseNote = { len = 15, volume = 6, fade = 0, parameter = noise(5, 4) } },
    { noiseNote = { len = 12, volume = 7, fade = 0, parameter = noise(4, 5) } },
    { noiseNote = { len = 16, volume = 6, fade = 0, parameter = noise(5, 6) } },
    { noiseNote = { len = 14, volume = 7, fade = 0, parameter = noise(6, 6) } },
    { noiseNote = { len = 13, volume = 6, fade = 0, parameter = noise(4, 7) } },
    { noiseNote = { len = 15, volume = 7, fade = 0, parameter = noise(5, 3) } },
  } } },
}

-- Thunder: a crack at shift 3 and a rumble that walks down to shift 8, which
-- is about 150 Hz -- the bottom of what this hardware can make and exactly
-- why the original's own earthquake and explosion sounds live down there.
local THUNDER = {
  channels = { { hw = 4, program = {
    { noiseNote = { len = 3, volume = 13, fade = 0, parameter = noise(3, 7) } },
    { noiseNote = { len = 16, volume = 12, fade = 6, parameter = noise(7, 7) } },
    { noiseNote = { len = 16, volume = 8, fade = 5, parameter = noise(8, 7) } },
    { noiseNote = { len = 14, volume = 5, fade = 4, parameter = noise(8, 6) } },
  } } },
}

-- id -> spec, in the order they are registered. The ids carry the mod's own
-- prefix because the sfx registry is one flat namespace shared with the ROM's
-- two hundred effects.
AmbientSound.PROGRAMS = {
  { "DS_AMB_CRICKET", CRICKET },
  { "DS_AMB_BIRD", BIRD },
  { "DS_AMB_CHIRP", CHIRP },
  { "DS_AMB_LAP", LAP },
  { "DS_AMB_RAIN", RAIN },
  { "DS_AMB_THUNDER", THUNDER },
}

-- ------- registration
--
-- Assembled once, at load, and handed to the engine's sfx registry. Assembly
-- touches no love.* at all (ChipAsm says so in as many words), so this runs
-- on a headless boot and in the mod manager's dry load without a graphics or
-- audio context existing yet.
--
-- Failure here retires the feature rather than the mod: a bad byte in a
-- program below should cost the crickets, not the diorama.
local defs = {}
local broken = false

function AmbientSound.register(mod)
  local ok, err = pcall(function()
    local ChipAsm = require("src.audio.ChipAsm")
    for _, entry in ipairs(AmbientSound.PROGRAMS) do
      local def = ChipAsm.sfx(entry[2])
      defs[entry[1]] = def
      if mod and mod.content and mod.content.sfx then
        mod.content.sfx:register(entry[1], def)
      end
    end
  end)
  if ok then return true end
  broken = true
  if V.mod and V.mod.log then
    V.mod.log:warn("ambient sound failed to assemble: %s -- the sounds are "
                   .. "off for this session", tostring(err))
  end
  return false
end

-- The def to render: the REGISTRY's answer first, so a sound pack that
-- overrode one of these ids with a file gets played instead, and ours only as
-- the fallback for a boot where the registry has not merged yet.
local function def(name)
  local Game = game()
  local sfx = Game and Game.data and Game.data.audio and Game.data.audio.sfx
  return (sfx and sfx[name]) or defs[name]
end


-- ------- the recordings
--
-- The chip programs above are the FALLBACK now, not the product. They were
-- the product for one version and they were the wrong answer: a square wave
-- blip is a convincing menu beep and an unconvincing cricket, and at the
-- level ambience wants to sit -- under the map's own music -- a thin blip is
-- not quiet, it is inaudible. The synth can do a Game Boy's sound effects
-- because that is what a Game Boy's sound effects are. It cannot do a field
-- at dusk, because a field at dusk is a hundred overlapping sources and the
-- hardware has four.
--
-- So the real thing, recorded, in `assets/audio/`. Every file is CC0 -- see
-- that folder's CREDITS.md for who recorded each one, and for why nothing
-- here is CC-BY or CC-BY-SA (a share-alike recording would reach out and set
-- terms on the whole mod).
--
-- The programs stay, and stay registered, for the case that matters: a file
-- missing, a build without the assets folder, a driver that will not decode
-- Vorbis. Then the bed falls back to the synth and the feature is worse
-- rather than gone.
--
-- ------- and they are BEDS, not blips
--
-- The other half of what was wrong. Crickets were scheduled as discrete
-- chirps on a countdown, which is what the synth could manage; a recording of
-- crickets is a continuous field whose LEVEL moves. So four of the five loop
-- and are crossfaded by how much of them the world wants right now -- night
-- brings the crickets up, walking away from the water takes the water down,
-- a shower brings the rain up over ten seconds. Only thunder is a one-shot,
-- because a thunderclap is one.
local AUDIO = "assets/audio/"

-- key -> { file, fallback program id, gain }
--
-- `gain` is per bed and they are NOT equal: these are five different
-- recordings at five different levels, and the mix is the point. Crickets and
-- rain carry a scene, birdsong sits behind one, water is a detail you notice
-- when you are near it.
AmbientSound.BEDS = {
  crickets = { file = "crickets.mp3", chip = "DS_AMB_CRICKET", gain = 0.85 },
  birds    = { file = "birds.ogg",    chip = "DS_AMB_BIRD",    gain = 0.55 },
  water    = { file = "water.ogg",    chip = "DS_AMB_LAP",     gain = 0.70 },
  rain     = { file = "rain.ogg",     chip = "DS_AMB_RAIN",    gain = 1.00 },
}

AmbientSound.THUNDER = { file = "thunder.ogg", chip = "DS_AMB_THUNDER",
                         gain = 1.0 }

-- ------- decoding
--
-- Decoded to a SoundData and rebuilt into a Source rather than handed to
-- love.audio.newSource as a path, and the reason is the loop seam.
--
-- A looping Source repeats its buffer end to start with no gap, so a bed only
-- sounds continuous if the BUFFER starts and ends in the sound. Dead air on
-- either end becomes a hole you hear once every time round and then cannot
-- stop hearing.
--
-- The first cut of this comment blamed MP3 encoder padding, which is the
-- famous cause and, here, the wrong one. Measured (tests/ambient_beds_probe):
--
--     crickets.mp3   head    0   tail     0 samples
--     rain.ogg       head    0   tail     0
--     water.ogg      head    0   tail     0
--     birds.ogg      head 3104   tail 36817   -- 65ms + 767ms
--     thunder.ogg    head 1919   tail 39786   -- 40ms + 829ms
--
-- The decoder already handles the MP3's padding, and the two files that need
-- trimming are Oggs -- not because of their format but because the person
-- recording them left the tape running. Which is the better argument for
-- doing this at all: the fix is not for a format quirk, it is for recordings,
-- and every recording anyone drops into that folder later gets it too.
--
-- Cost, on the machine this was written on: 104ms to decode the longest file
-- and 16ms to copy it (1.5M stereo samples). Once per bed per session, on the
-- frame that bed first comes up, and the trim is skipped outright for the
-- three files that need none.
local SILENCE = 0.004         -- below this a sample counts as nothing

local function stripSilence(data)
  local n = data:getSampleCount()
  local channels = data:getChannelCount()
  if n < 64 then return data end

  local function loud(i)
    for c = 1, channels do
      local ok, v = pcall(data.getSample, data, i, c)
      if ok and math.abs(v or 0) > SILENCE then return true end
    end
    return false
  end

  local first, last = 0, n - 1
  while first < last and not loud(first) do first = first + 1 end
  while last > first and not loud(last) do last = last - 1 end
  if first == 0 and last == n - 1 then return data end     -- nothing to trim
  local count = last - first + 1
  -- a file that is mostly silence is not one this understood; hand back what
  -- we were given rather than a quarter of it
  if count < n / 4 then return data end

  local out = love.sound.newSoundData(count, data:getSampleRate(),
                                      data:getBitDepth(), channels)
  for i = 0, count - 1 do
    for c = 1, channels do
      out:setSample(i, c, data:getSample(first + i, c))
    end
  end
  return out
end

-- The SFX volume row, as a 0..1 scale. Read every frame rather than cached,
-- so the row takes effect immediately, exactly as it does for the engine's
-- own sounds.
local function sfxScale()
  local Game = game()
  local opts = Game and Game.save and Game.save.options
  local level = opts and opts.sfxVol
  if level == nil then level = 7 end
  level = math.max(0, math.min(7, level))
  return level / 7
end

-- The ambience's own ceiling. Raised a long way from where the synthesized
-- version sat: real recordings have real noise floors and sit UNDER music
-- rather than beside it, so the number that made a square-wave blip merely
-- quiet made a cricket field silent.
AmbientSound.GAIN = 0.85

-- ------- sources
--
-- One decoded Source per sound, built lazily -- a player who never sees rain
-- never pays for the rain bed. Cached as `false` on failure, so a missing
-- file is tried once, logged once, and then costs nothing.
local sources = {}

local function fromFile(spec)
  local path = V.path .. "/" .. AUDIO .. spec.file
  local ok, data = pcall(love.sound.newSoundData, path)
  if not (ok and data) then return nil, tostring(data) end
  local trimmed = data
  local okt, out = pcall(stripSilence, data)
  if okt and out then trimmed = out end
  local oks, src = pcall(love.audio.newSource, trimmed, "static")
  if not (oks and src) then return nil, tostring(src) end
  return src
end

-- the synth, for when the recording is not there
local function fromChip(name)
  local Game = game()
  local d = def(name)
  if not (Game and Game.data and d) then return nil, "no program" end
  local ok, src = pcall(require("src.core.ChipAudio").newSfx,
                        Game.data, name, 0, 0x80, d)
  if not (ok and src) then return nil, tostring(src) end
  return src
end

local function sourceFor(key, spec)
  local hit = sources[key]
  if hit ~= nil then return hit or nil end
  if not love.audio then
    sources[key] = false
    return nil
  end
  local src, err = fromFile(spec)
  if not src then
    -- the recording is not usable: say so ONCE, then fall back to the synth,
    -- so the ambience is worse rather than absent
    if V.mod and V.mod.log then
      V.mod.log:warn("ambient sound: %s unusable (%s) -- falling back to the "
                     .. "synthesized program", spec.file, tostring(err))
    end
    src = fromChip(spec.chip)
  end
  if not src then
    sources[key] = false
    return nil
  end
  sources[key] = src
  return src
end

-- ------- the beds
--
-- Each carries a level that eases toward what the world wants. Up quickly
-- (weather arrives, you walk up to a river), down more slowly (a shower
-- trails off), which is also what keeps a walk through a doorway from
-- sounding like a switch being thrown.
local beds = {}

for key in pairs(AmbientSound.BEDS) do
  beds[key] = { src = nil, level = 0 }
end

local function driveBed(key, want, dt, pitch)
  local spec = AmbientSound.BEDS[key]
  local bed = beds[key]
  if not (spec and bed) then return end

  want = math.max(0, math.min(1, want or 0))
  local rate = want > bed.level and 0.8 or 0.35
  local step = rate * (dt or 0)
  if math.abs(want - bed.level) <= step then
    bed.level = want
  else
    bed.level = bed.level + (want > bed.level and step or -step)
  end

  if bed.level <= 0.002 then
    if bed.src then
      pcall(bed.src.stop, bed.src)
      bed.src = nil
    end
    return
  end
  if not bed.src then
    bed.src = sourceFor(key, spec)
    if not bed.src then return end
    pcall(bed.src.setLooping, bed.src, true)
    pcall(bed.src.play, bed.src)
  end
  pcall(bed.src.setPitch, bed.src, pitch or 1)
  pcall(bed.src.setVolume, bed.src,
        AmbientSound.GAIN * sfxScale() * spec.gain * bed.level)
end

-- Thunder is the one one-shot, so it gets a couple of clones: two claps can
-- overlap in a storm, and a second one cutting the first off short is about
-- the most obviously fake thing a weather system can do.
local thunderVoices = nil

local function playThunder(volume, pitch)
  if not love.audio then return end
  if thunderVoices == nil then
    local base = sourceFor("thunder", AmbientSound.THUNDER)
    if not base then
      thunderVoices = false
      return
    end
    thunderVoices = { base }
    for _ = 2, 3 do
      local ok, clone = pcall(base.clone, base)
      if ok and clone then thunderVoices[#thunderVoices + 1] = clone end
    end
  end
  if not thunderVoices then return end
  for _, src in ipairs(thunderVoices) do
    local ok, playing = pcall(src.isPlaying, src)
    if not (ok and playing) then
      pcall(src.setVolume, src,
            AmbientSound.GAIN * sfxScale() * AmbientSound.THUNDER.gain
            * (volume or 1))
      pcall(src.setPitch, src, pitch or 1)
      pcall(src.play, src)
      return
    end
  end
end

function AmbientSound.silence()
  for _, bed in pairs(beds) do
    if bed.src then pcall(bed.src.stop, bed.src) end
    bed.src, bed.level = nil, 0
  end
  if type(thunderVoices) == "table" then
    for _, src in ipairs(thunderVoices) do pcall(src.stop, src) end
  end
end

-- ------- is there water within earshot
--
-- Counted by LOOKING, in cells, rather than kept as a list of maps with ponds
-- on them: a route with one pond in the corner should only sound like water
-- when the player is in that corner. Re-counted every WATER_EVERY seconds and
-- held between -- the answer moves at walking pace, and a per-frame scan of a
-- hundred cells for a sound effect is not a trade worth making.
local WATER_REACH = 7             -- cells
local WATER_EVERY = 0.6           -- seconds between counts

local water = { at = 0, near = 0 }

local function countWater(ow)
  local map, p = ow.map, ow.player
  local best = 0
  for dy = -WATER_REACH, WATER_REACH do
    for dx = -WATER_REACH, WATER_REACH do
      local cx, cy = p.cellX + dx, p.cellY + dy
      if map:inBounds(cx, cy) and map:isWaterCell(cx, cy) then
        local d = math.max(math.abs(dx), math.abs(dy))
        local closeness = 1 - d / (WATER_REACH + 1)
        if closeness > best then best = closeness end
      end
    end
  end
  return best
end

-- ------- what the world wants to hear
--
-- Every bed is a number between nothing and all of it, worked out fresh each
-- frame from the same clocks the rest of the mod runs on: DayNight says what
-- hour it is, Weather says what is coming down, and the map itself says
-- whether there is water within earshot. Nothing here SCHEDULES anything --
-- the crossfades in driveBed are the whole of the behaviour, which is why
-- nightfall does not switch the crickets on, it brings them up.
local failed = false

local function tick(dt)
  local Game = game()
  local ow = Game and Game.overworld

  local live = AmbientSound.enabled() and ow and ow.map and ow.player
               and Game.stack and Game.stack:top() == ow
               and not ow.transitioning
  if not live then
    -- a menu, a battle or a warp: everything eases down rather than cutting,
    -- so a battle that starts in the rain does not snap the rain off
    for key in pairs(beds) do driveBed(key, 0, dt) end
    return
  end

  local outdoor = Map.isOutdoor(ow.map.def) or false
  local canopy = DayNight.isCanopy(ow.map)
  local open = outdoor or canopy
  local tod = DayNight.tod()
  local day = tod == "DAY"
  local morning = tod == "MORNING"
  local evening = tod == "EVENING"
  local night = tod == "NIGHT"

  local kind, power = Weather.falling()
  local raining = kind == "rain"
  local snowing = kind == "snow"

  -- ------- rain
  --
  -- The one bed that plays INDOORS, at a third and pitched down: that is a
  -- roof over your head, and it is the best thing weather does. Snow gets the
  -- same bed far quieter and an octave down, which is not snow falling (snow
  -- falling is silent) but the wind that is bringing it.
  local rainWant, rainPitch = 0, 1
  if raining then
    rainWant = power * (outdoor and 1 or 0.34)
    rainPitch = outdoor and 1 or 0.75
  elseif snowing then
    rainWant = power * (outdoor and 0.28 or 0.10)
    rainPitch = 0.5
  end
  driveBed("rain", rainWant, dt, rainPitch)

  -- Thunder, which this module does not decide. Weather owns the STRIKE
  -- because a strike is a picture first -- the sky lights up and the rumble
  -- arrives afterwards, by a delay that stands for how far away it was --
  -- and `thunderDue` is Weather handing that delay over the instant it is up.
  -- It answers once per strike and hands back the distance, so the far ones
  -- are slower and quieter and the near ones crack.
  local far = Weather.thunderDue()
  if far then
    playThunder(0.35 + 0.65 * (1 - far), 0.80 + far * 0.35)
  end

  -- ------- crickets and birds
  --
  -- Both fade WITH the hour rather than switching on it, so dusk is one bed
  -- coming up as the other goes down instead of a handover. And both stop in
  -- the rain, which anyone who has been outside knows without being told.
  local wet = (raining and power > 0.3) and power or 0
  local dry = 1 - math.min(1, wet)

  local cricketWant = 0
  if open then
    if night then cricketWant = 1
    elseif evening then cricketWant = 0.55
    elseif morning then cricketWant = 0.12 end
  end
  driveBed("crickets", cricketWant * dry, dt)

  local birdWant = 0
  if open then
    -- the dawn chorus is a real thing and worth having: a morning wood is
    -- louder than a noon one
    if morning then birdWant = 1
    elseif day then birdWant = 0.62
    elseif evening then birdWant = 0.22 end
  end
  driveBed("birds", birdWant * dry, dt)

  -- ------- the water
  --
  -- Outdoors only, and only where there IS water: a cave's underground lake
  -- would want its own drip rather than a shoreline, and a shoreline heard in
  -- a room is a bug. The level follows how close the nearest water cell is,
  -- so walking up to a pond brings it in and walking away takes it out --
  -- which is the whole reason this is a bed and not a splash on a timer.
  water.at = water.at - dt
  if water.at <= 0 then
    water.at = WATER_EVERY
    local okw, near = pcall(countWater, ow)
    water.near = okw and near or 0
  end
  driveBed("water", outdoor and water.near or 0, dt)
end

-- Rides the voxel pipeline's update hook with everything else that has a
-- clock. A throw retires the sounds for the session rather than the frame --
-- the same contract CityLife and WildRoamers hold, and for the same reason.
function AmbientSound.update(dt)
  if failed then return end
  local ok, err = pcall(tick, dt or 0)
  if ok then return end
  failed = true
  pcall(AmbientSound.silence)
  if V.mod and V.mod.log then
    V.mod.log:warn("ambient sound failed: %s -- the sounds are off for this "
                   .. "session", tostring(err))
  end
end

-- Hot reload drops the decoded sources; the files and the programs are both
-- still good, so only the sources are thrown away and the next play rebuilds
-- them. On the engine's own asset-flush fan-out, which is where every other
-- cache in this mod hangs (RoamerArt, TerrainAtlas) and where the engine's
-- own audio caches hang too -- so an edited file is re-read exactly when the
-- engine's own would be.
function AmbientSound.invalidate()
  pcall(AmbientSound.silence)
  for _, src in pairs(sources) do
    if src then pcall(src.stop, src) end
  end
  sources = {}
  thunderVoices = nil
end

pcall(function()
  require("src.render.Assets").register(AmbientSound.invalidate)
end)

return AmbientSound

