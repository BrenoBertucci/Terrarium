-- Probe: what each ambient program costs to synthesize, in milliseconds on
-- this machine. The rain bed is two and a bit seconds of PCM walked sample by
-- sample in Lua, and it is rendered lazily -- so the question that decides
-- whether it needs warming is simply how long that one frame is.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/DRAMATIC_SHAPE/tests/ambsound_cost_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/ambsound_cost.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b
    coroutine.yield()
  end

  local f = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); f = f + 1; if f > 900 then break end
  end
  f = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); f = f + 11; if f > 1500 then break end
  end

  local lib = game.mods.exports.DRAMATIC_SHAPE.lib
  local AmbientSound = lib.require("AmbientSound")
  local ChipAudio = require("src.core.ChipAudio")
  local sfx = game.data.audio.sfx

  log("synthesis cost, one render each (this is a lazy one-off per session):")
  local worst, worstName = 0, "-"
  for _, entry in ipairs(AmbientSound.PROGRAMS) do
    local name = entry[1]
    local t0 = love.timer.getTime()
    local src = ChipAudio.newSfx(game.data, name, 0, 0x80, sfx[name])
    local ms = (love.timer.getTime() - t0) * 1000
    log(("  %-16s %7.1f ms  source=%s"):format(name, ms, tostring(src ~= nil)))
    if ms > worst then worst, worstName = ms, name end
  end
  log(("worst: %s at %.1f ms (%.1f frames at 60fps)"):format(
    worstName, worst, worst / 16.67))

  logf:close()
  love.event.quit()
end
