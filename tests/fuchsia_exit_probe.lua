-- Leaving Fuchsia Gym closes the game. Reproduce it, and watch the state stack.
--
-- Reported: beat Koga, walked out of the gym, the window closed. The mod's own
-- errors.lua has nothing, which means it was not the render pipeline failing
-- (that path is pcall'd and logged) -- so either a Lua error escaped to LOVE's
-- handler, or something below Lua took the process down.
--
-- There is a prior sighting. The LedgeKit probe run of 2026-09-06 died at
-- Fuchsia too: "log terminates at [FUCHSIA_CITY], 8 checks, 71 bank models
-- cached, cause not seen". The console was never captured. This is that
-- capture, finally.
--
-- What it watches, once a frame:
--   * the STATE STACK depth, because the one error this game has logged from
--     this area is "Maximum stack depth reached (more pushes than pops?)" and
--     a stack that climbs and never falls names the bug on its own;
--   * the map, so the exact step that kills it is on the last line;
--   * lua memory, because "the window closed with no error" is also what
--     running out of it looks like.
--
-- Everything is flushed per line. A log that ends mid-sentence is the whole
-- finding when the process dies.
--
--   POKEPORT_VERSION=yellow \
--   DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/fuchsia_exit_probe.lua gen1recomp --console

return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/fuchsia_exit_probe.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
    logf:write(table.concat(p, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end

  local function depth()
    local s = game.stack
    if not s then return -1 end
    -- the stack keeps its entries in an array part under one of these names
    for _, f in ipairs({ "items", "list", "states", "stack" }) do
      local v = rawget(s, f)
      if type(v) == "table" then return #v end
    end
    local n = 0
    for k, v in pairs(s) do
      if type(k) == "number" then n = n + 1 end
    end
    return n
  end

  local function where()
    local ow = game.overworld
    local m = ow and ow.map
    local p = ow and ow.player
    return ("%s (%s,%s) stack=%d top=%s mem=%.1fMB"):format(
      tostring(m and m.id), tostring(p and p.cellX), tostring(p and p.cellY),
      depth(), tostring(game.stack and game.stack:top() == ow and "overworld" or "other"),
      collectgarbage("count") / 1024)
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    game.input.pressQueue[#game.input.pressQueue + 1] = "a"
    wait(10); n = n + 11
    if n > 1500 then break end
  end

  local lib = game.mods and game.mods.exports
              and game.mods.exports.TERRARIUM and game.mods.exports.TERRARIUM.lib

  log("== leaving Fuchsia Gym ==")
  log("mod loaded: ", tostring(lib ~= nil))
  log("engine ", tostring(game.version or "?"))
  log("start  ", where())

  -- Straight to the gym, at the cell the save has the player standing on.
  game.overworld:setMap("FUCHSIA_GYM", 1, 6, "down")
  wait(120)
  log("in gym ", where())

  -- Walk DOWN, one press at a time, logging every step. The exit is south of
  -- where the save left him; whichever step crosses the warp is the last line
  -- in this file if it is the one that kills the process.
  for step = 1, 14 do
    game.input.pressQueue[#game.input.pressQueue + 1] = "down"
    wait(14)
    log(("down %-2d "):format(step), where())
    local m = game.overworld and game.overworld.map
    if m and m.id ~= "FUCHSIA_GYM" then
      log("LEFT THE GYM -- now on ", tostring(m.id))
      break
    end
  end

  wait(90)
  log("after  ", where())

  -- And the other way it happens in play: the warp taken directly.
  log("-- now the same exit as a warp --")
  game.overworld:setMap("FUCHSIA_GYM", 1, 6, "down")
  wait(120)
  log("back in", where())
  local ok, err = pcall(function()
    game.overworld:setMap("FUCHSIA_CITY", 5, 27, "down")
  end)
  log("setMap FUCHSIA_CITY ok=", tostring(ok), " err=", tostring(err))
  wait(180)
  log("end    ", where())

  -- ------- WHERE THE 800 MEGABYTES GO
  --
  -- The line above this one is the finding: walking out of the gym is fine,
  -- and entering FUCHSIA_CITY takes the Lua heap from about 35 MB to 840.
  -- LuaJIT on x64 cannot grow its heap indefinitely, so a spike of that size
  -- plus textures is how a process dies with no error and no log -- which is
  -- what "the game closed" looks like from the outside.
  --
  -- So: load it again from cold, sampling the heap against the build stage
  -- once a frame. The pass that owns the jump owns the bug.
  log("")
  log("== what allocates on the way into Fuchsia City ==")
  local ChunkMesher = lib and lib.require and lib.require("ChunkMesher")
  local Trees3D = lib and lib.require and lib.require("Trees3D")
  if not ChunkMesher then log("(no ChunkMesher -- mod not loaded)") else
    collectgarbage("collect")
    ChunkMesher.invalidate()
    if Trees3D then Trees3D.invalidate() end
    collectgarbage("collect")
    log(("baseline after a full collect: %.1f MB"):format(collectgarbage("count") / 1024))

    game.overworld:setMap("PALLET_TOWN", 10, 8, "down")
    wait(150)
    collectgarbage("collect")
    log(("PALLET_TOWN settled:           %.1f MB"):format(collectgarbage("count") / 1024))

    ChunkMesher.invalidate()
    if Trees3D then Trees3D.invalidate() end
    collectgarbage("collect")
    local before = collectgarbage("count") / 1024
    log(("before Fuchsia:                %.1f MB"):format(before))

    game.overworld:setMap("FUCHSIA_CITY", 5, 27, "down")
    local peak, peakPass = before, "?"
    local seen = {}
    for i = 1, 900 do
      coroutine.yield()
      local mb = collectgarbage("count") / 1024
      local st = ChunkMesher.stage
      local pass = (st and st.pass) or "idle"
      if mb > peak then peak, peakPass = mb, pass end
      local s = seen[pass]
      if not s then seen[pass] = { lo = mb, hi = mb, n = 1 }
      else
        if mb < s.lo then s.lo = mb end
        if mb > s.hi then s.hi = mb end
        s.n = s.n + 1
      end
      if i % 60 == 0 then
        log(("  +%3d frames  %7.1f MB  pass=%-12s pending=%d")
              :format(i, mb, pass, ChunkMesher.pending()))
      end
    end
    log(("PEAK %.1f MB, first reached during pass '%s'"):format(peak, peakPass))
    log("  heap range seen per pass:")
    for pass, s in pairs(seen) do
      log(("    %-14s %7.1f .. %7.1f MB over %d frames  (grew %.1f)")
            :format(pass, s.lo, s.hi, s.n, s.hi - s.lo))
    end
    collectgarbage("collect")
    local live = collectgarbage("count") / 1024
    log(("after a full collect:          %.1f MB  (live)"):format(live))

    -- WHO HOLDS IT. Estimating from table counts was wrong by an order of
    -- magnitude, so this asks the only question that cannot be argued with:
    -- drop a cache, collect, and see how much the heap fell. Attribution by
    -- subtraction, one holder at a time.
    log("")
    log("  == attributing the live heap, by dropping caches ==")
    local function mb() collectgarbage("collect"); return collectgarbage("count") / 1024 end
    local base = mb()
    log(("    start                       %7.1f MB"):format(base))
    local function drop(name, fn)
      local before = mb()
      local ok, err = pcall(fn)
      local after = mb()
      log(("    %-26s %7.1f MB  (freed %6.1f) %s")
            :format(name, after, before - after, ok and "" or ("ERR " .. tostring(err))))
    end
    drop("Trees3D.invalidate", function()
      lib.require("Trees3D").invalidate()
    end)
    drop("TerrainAtlas (live={})", function()
      lib.require("TerrainAtlas").setLive({})
    end)
    drop("ImageCache", function()
      local IC = lib.require("ImageCache")
      if IC.clear then IC.clear() elseif IC.invalidate then IC.invalidate() end
    end)
    drop("ChunkMesher.invalidate()", function()
      ChunkMesher.invalidate()
    end)
    drop("Structures.invalidate()", function()
      lib.require("Structures").invalidate()
    end)
    log(("    TOTAL FREED                 %7.1f MB of %.1f"):format(base - mb(), base))

    -- WHAT IS STILL HELD. The meshes are GPU objects and barely show in the
    -- Lua heap, so half a gigabyte of LIVE Lua is somebody's cached tables.
    -- Structures keeps a per-map record of every quad it emitted, and a quad
    -- is a table of four corner tables plus uv and shade -- so the count
    -- below, times roughly six tables each, is the answer or it is not.
    local okS, Structures = pcall(lib.require, "Structures")
    if okS and Structures then
      local S = Structures.forMap(game.overworld.map)
      local function n(t) return type(t) == "table" and #t or -1 end
      log("  Structures cache for FUCHSIA_CITY:")
      local total = 0
      for _, name in ipairs({ "spriteQuads", "grassQuads", "flowerQuads",
                              "objectQuads", "grassInstances", "figures",
                              "treeSites", "roundStamps" }) do
        local c = n(S[name])
        if c >= 0 then total = total + c end
        log(("    %-16s %8d"):format(name, c))
      end
      log(("    %-16s %8d entries -> roughly %d Lua tables at ~6 each")
            :format("TOTAL", total, total * 6))
    end
  end

  log("done -- reached the end without dying")
  logf:close()
  love.event.quit()
end
