-- Does selecting GRASS = 3D actually load the authored bake?
--
-- The void run raised, from Grass3D.meta():
--     mods/TERRARIUM/lib/Grass3D.lua:114: love.filesystem is not available
--     to mods, use mod.storage and mod:read
-- Line 114 is readBinary's own first guard:
--     if love and love.filesystem and love.filesystem.read then
-- Dereferencing love.filesystem is what the engine blocks, so the guard
-- throws instead of failing to false -- and readBinary never reaches its
-- fallbacks (2: src.render.Assets, 3: native file under V.path).
--
-- available() is only reached when the row is "mesh", so the player on
-- VOXEL never triggers it. This asks the question directly: flip the row to
-- mesh in RAM and see whether the tufts can load.

return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/grass_row_probe.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
    logf:write(table.concat(p, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end

  local lib = game.mods and game.mods.exports
              and game.mods.exports.TERRARIUM and game.mods.exports.TERRARIUM.lib
  if not lib then log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return end
  local Grass3D = lib.require("Grass3D")

  local saved = Grass3D.setting:get()
  log("stored GRASS row: " .. tostring(saved))

  -- is love.filesystem even reachable from mod code?
  local okLF, errLF = pcall(function() return love.filesystem end)
  log(("love.filesystem reachable from mod code: %s%s")
        :format(tostring(okLF), okLF and "" or ("  -- " .. tostring(errLF))))

  log("")
  log("row = voxel (as stored):")
  log(("  wantsMesh=%s"):format(tostring(Grass3D.wantsMesh())))
  local ok1, r1 = pcall(Grass3D.available)
  log(("  available() -> ok=%s result=%s"):format(tostring(ok1), tostring(r1)))

  log("")
  log("row = mesh (what the player would pick as GRASS = 3D):")
  Grass3D.setting:sync("mesh")
  wait(30)
  log(("  wantsMesh=%s"):format(tostring(Grass3D.wantsMesh())))
  local ok2, r2 = pcall(Grass3D.available)
  log(("  available() -> ok=%s result=%s"):format(tostring(ok2), tostring(r2)))
  local ok3, r3 = pcall(Grass3D.meta)
  log(("  meta()      -> ok=%s result=%s"):format(tostring(ok3),
        (ok3 and type(r3) == "table")
          and ("height=" .. tostring(r3.height) .. " verts=" .. tostring(r3.verts))
          or tostring(r3)))

  -- let it run a few seconds with the row flipped: does the game survive?
  log("")
  log("  holding 240 frames with GRASS=3D to see if anything throws...")
  wait(240)
  log("  survived 240 frames")

  Grass3D.setting:sync(saved)
  wait(30)
  log("")
  log("restored GRASS row: " .. tostring(Grass3D.setting:get()))
  log("done")
  logf:close()
  love.event.quit()
end
