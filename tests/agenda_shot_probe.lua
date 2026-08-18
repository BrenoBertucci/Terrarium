-- Probe: what the agenda LOOKS like, and whether the day leash twitches.
--
-- Everything measured so far about the agenda is a count or a distance, and
-- both can be right while the thing on screen is wrong -- which is exactly
-- how the flock nearly shipped as a speck with correct arithmetic behind it.
--
-- Two questions, and only one of them is answered by a picture.
--
--   THE PICTURE. One town, one camera, four phases. Same cell, same facing,
--   same settle time, so the only thing moving between the four frames is
--   the hour and what the people did about it.
--
--   THE LEASH. `walkTick` only counts somebody as arrived when they stand on
--   the authored cell EXACTLY, so a walker that drifts one step is walked
--   back every time. That is either "a person who keeps their post" or "a
--   person fighting a floor tile", and a screenshot cannot tell those apart
--   because both are one sprite standing near one cell. What separates them
--   is the TRACE: a purposeful walker visits several cells and returns now
--   and then; a tethered one bounces between two and is at the anchor half
--   the time it is looked at.
--
--   POKEPORT_VERSION=yellow \
--   DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/agenda_shot_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/agenda_shot_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n")
    logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(btn)
    game.input.pressQueue[#game.input.pressQueue + 1] = btn
    coroutine.yield()
  end
  local function done(msg) log(msg); logf:close(); love.event.quit() end
  local function shot(name)
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
    wait(10)
  end

  local frames = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); frames = frames + 1
    if frames > 900 then return done("FAIL: no overworld") end
  end
  frames = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); frames = frames + 11
    if frames > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then return done("FAIL: TERRARIUM not loaded") end
  local Routines = lib.require("Routines")
  local DayNight = lib.require("DayNight")
  local Voxel3D  = lib.require("Voxel3D")

  local MAP = os.getenv("DS_PROBE_MAP") or "FUCHSIA_CITY"
  local MX = tonumber(os.getenv("DS_PROBE_X")) or 5
  local MY = tonumber(os.getenv("DS_PROBE_Y")) or 5

  game.overworld:setMap(MAP, MX, MY, "down")
  wait(60)
  Routines.agendaSetting:sync("full")

  -- The 3D pass is not up when setMap returns, and a shot taken before it is
  -- the 2D renderer's picture of a 3D feature.
  local waited = 0
  while Voxel3D.lampLights == nil and waited < 900 do wait(1); waited = waited + 1 end
  if Voxel3D.lampLights == nil then
    return done("FAIL: 3D pass never came up -- every shot would be the 2D path")
  end
  log(("map=%s player=(%d,%d)  3D up after %d frames"):format(MAP, MX, MY, waited))

  local p = game.overworld.player
  local hw, hh = Routines.viewCells()

  -- ------- four phases, four frames
  --
  -- 300 frames of settle each: the palette ramps into a phase rather than
  -- cutting, and a shot taken on the ramp differs from its neighbour across
  -- the whole frame, which buries the local difference being looked for.
  log("")
  for _, phase in ipairs({ "dawn", "day", "dusk", "night" }) do
    DayNight.setting:sync(phase)
    wait(300)

    local walkers = Routines.walkers(game.overworld)
    local inShot = 0
    for _, npc in ipairs(walkers) do
      if math.abs(npc.cellX - p.cellX) <= hw
         and math.abs(npc.cellY - p.cellY) <= hh then
        inShot = inShot + 1
      end
    end
    shot(("agenda_%s.png"):format(phase))
    log(("%-6s tod=%-8s walkers=%d inShot=%d")
        :format(phase, tostring(DayNight.tod()), #walkers, inShot))
  end

  -- ------- the leash, traced rather than photographed
  --
  -- Ten seconds of DAY, sampled four times a second. Per walker: how many
  -- distinct cells it stood on, how much of the time it was exactly on its
  -- authored cell, and how far it ever got from it.
  --
  -- Reading it: `distinct` of 1-2 with `atAnchor` over about half is the
  -- tethered case -- somebody being walked back the moment they step off.
  -- Several distinct cells with a low anchor share is an ordinary wanderer
  -- that happens to stay near its post, which is the intent.
  log("")
  DayNight.setting:sync("day")
  wait(180)

  -- Held/frozen are sampled too, because "does not move" has two very
  -- different causes and only one of them is this feature's fault. If a
  -- walker sits still while the agenda has never taken it and it is not
  -- frozen by us, then the engine is not wandering it -- a script owns it, a
  -- fence hems it in, or the ROM gave it nowhere to go -- and it stood just
  -- as still before any of this existed.
  local seen, atAnchor, maxDist, samples = {}, {}, {}, 0
  local anchors, heldBy, wasFrozen = {}, {}, {}
  for _, npc in ipairs(Routines.walkers(game.overworld)) do
    seen[npc], atAnchor[npc], maxDist[npc] = {}, 0, 0
    heldBy[npc], wasFrozen[npc] = 0, 0
    anchors[npc] = { tonumber(npc.def.x), tonumber(npc.def.y) }
  end

  for _ = 1, 40 do
    samples = samples + 1
    for npc, anchor in pairs(anchors) do
      if npc.dsAgenda then heldBy[npc] = heldBy[npc] + 1 end
      if npc.frozen then wasFrozen[npc] = wasFrozen[npc] + 1 end
      local key = npc.cellX .. "," .. npc.cellY
      seen[npc][key] = true
      if anchor[1] and npc.cellX == anchor[1] and npc.cellY == anchor[2] then
        atAnchor[npc] = atAnchor[npc] + 1
      end
      if anchor[1] then
        local d = math.abs(npc.cellX - anchor[1]) + math.abs(npc.cellY - anchor[2])
        if d > maxDist[npc] then maxDist[npc] = d end
      end
    end
    wait(15)
  end

  log(("leash trace over %d samples (%.0fs of DAY)"):format(samples, samples * 15 / 60))
  local tethered = 0
  for npc, anchor in pairs(anchors) do
    local n = 0
    for _ in pairs(seen[npc]) do n = n + 1 end
    local share = atAnchor[npc] / samples
    local still = (n <= 2 and share >= 0.5)
    local ours = (heldBy[npc] > 0) or (wasFrozen[npc] > 0)
    local tight = still and ours
    if tight then tethered = tethered + 1 end
    log(("  %-28s anchor=(%s,%s) distinct=%d atAnchor=%.0f%% maxDist=%d"
         .. " held=%d frozen=%d %s")
        :format(tostring(npc.def and npc.def.name),
                tostring(anchor[1]), tostring(anchor[2]),
                n, share * 100, maxDist[npc], heldBy[npc], wasFrozen[npc],
                tight and "<-- TETHERED BY US"
                  or (still and "<-- still, but not ours" or "")))
  end
  log("")
  if tethered > 0 then
    log(("VERDICT: %d walker(s) look tethered -- bouncing on or beside the")
        :format(tethered))
    log("  authored cell. Widening the leash to a 2-3 cell radius, and only")
    log("  pulling back beyond it, is the fix.")
  else
    log("VERDICT: nobody is pinned to their cell; the leash reads as a post")
    log("  rather than as a tether.")
  end

  done("done")
end
