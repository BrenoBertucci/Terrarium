-- Probe: WHICH shader refused to build, and did it take the 3D pass with it?
--
-- The mod fell back to the flat renderer with ANIME on. There are only a
-- few ways that happens and they are not guesses -- each one is a value
-- that can be read:
--
--   * Voxel3D.available() is false, which is exactly Voxel3D.shader() ~= nil.
--     If the ANIME_CEL variant will not build, that returns nil, and every
--     caller treats it as "stay on the 2D path" -- silently, which is the
--     whole reason this file exists.
--   * RayFX's own rung will not build. That one is NOT fatal: apply() hands
--     the scene back untouched. Reported anyway so it is not confused with
--     the first.
--   * The variants build but a uniform never arrives, so the bands quantise
--     against animeBands = 0 and the world goes to one step of light. That
--     looks broken without anything having failed, so the sent values are
--     read back rather than assumed.
--
-- Every variant is compiled EXPLICITLY here rather than waiting for one to
-- be reached: the point is to learn which combinations this driver accepts,
-- not which one today's settings happened to ask for.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/anime_compile_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/anime_compile_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
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

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded -- the mod itself did not come up.")
    log("      That is a Lua error at load, not a shader problem.")
    logf:close(); love.event.quit(); return
  end
  log("version:", exports.TERRARIUM.version)

  local function req(name)
    local ok, m = pcall(lib.require, name)
    if not ok then log("REQUIRE FAILED:", name, tostring(m)) end
    return ok and m or nil
  end

  local Voxel3D = req("Voxel3D")
  local RayFX   = req("RayFX")
  local Anime   = req("Anime")
  local Quality = req("Quality")
  local Vfx     = req("Vfx")

  log("")
  log("---- settings as the game has them ----")
  if Anime then log("  ANIME  =", Anime.level(), " cel:", tostring(Anime.cel()),
                   " screen:", tostring(Anime.screen())) end
  if RayFX then log("  RTX    =", RayFX.level()) end
  if Quality then log("  RES    = 1/" .. tostring(Quality.scale()),
                     " SHADOWS =", Quality.shadows()) end
  if Vfx then log("  IMPACT =", Vfx.level()) end

  log("")
  log("---- THE question ----")
  if Voxel3D then
    log("  Voxel3D.available() =", tostring(Voxel3D.available()))
    log("  Voxel3D.shader()    =", tostring(Voxel3D.shader() ~= nil))
    log("  Voxel3D.shaderError =", tostring(Voxel3D.shaderError))
  end

  -- Walk the whole matrix. Each rung is its own compilation behind a
  -- define, so "does this driver take it" is several questions and the
  -- answer to each is otherwise only visible as an effect quietly missing.
  log("")
  log("---- scene shader, every variant ----")
  if Voxel3D and Anime and Quality then
    local realAnime = Anime.setting.index
    local realShadow = Quality.shadowSetting.index
    for _, av in ipairs({ "off", "cel", "full" }) do
      for _, sv in ipairs({ "low", "high", "soft" }) do
        Anime.setting:sync(av)
        Quality.shadowSetting:sync(sv)
        Voxel3D.shaderError = nil
        local ok, sh = pcall(Voxel3D.shader, false)
        log(("  ANIME=%-4s SHADOWS=%-4s -> %s%s")
            :format(av, sv,
                    (ok and sh) and "built" or "REFUSED",
                    Voxel3D.shaderError
                      and ("  | " .. tostring(Voxel3D.shaderError):gsub("\n", " ¶ "))
                      or ""))
      end
    end
    Anime.setting.index = realAnime
    Quality.shadowSetting.index = realShadow
  end

  log("")
  log("---- screen-space pass, every rung ----")
  if RayFX and Anime then
    local realAnime = Anime.setting.index
    for _, av in ipairs({ "off", "full" }) do
      Anime.setting:sync(av)
      for _, lv in ipairs({ "ao", "rt", "max" }) do
        RayFX.shaderError = nil
        local ok, built = pcall(RayFX.compile, lv)
        log(("  ANIME=%-4s RTX=%-3s -> %s%s")
            :format(av, lv,
                    (ok and built) and "built" or "REFUSED",
                    RayFX.shaderError
                      and ("  | " .. tostring(RayFX.shaderError):gsub("\n", " ¶ "))
                      or ""))
      end
    end
    Anime.setting.index = realAnime
  end

  log("")
  log("---- did the uniforms arrive ----")
  log("  (a variant that builds but never receives animeBands quantises")
  log("   against zero, which is one step of light and looks like a fault)")
  if Anime then
    log("  Anime.BANDS =", Anime.BANDS, " CELL =", Anime.CELL,
        " DITHER =", Anime.DITHER)
  end

  log("")
  log("Read the first REFUSED line above. A refusal on the scene shader is")
  log("what drops the whole diorama to the flat renderer; a refusal on the")
  log("screen-space pass costs only that pass.")
  logf:close()
  love.event.quit()
end
