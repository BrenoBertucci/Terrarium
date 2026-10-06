-- Probe: does every rung of the scene shader compile with and without the
-- GLOW field, at both uniform precisions? The desktop driver only ever
-- builds the rung it lands on, so a GLSL error inside an #ifdef that only
-- the fallbacks carry would ship unseen (the lesson in
-- tests/gpu_compat_probe.lua). This asks all sixteen explicitly.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/glow_compile.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  for _ = 1, 30 do coroutine.yield() end
  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then log("FAIL: not loaded") logf:close() love.event.quit() return end
  local Voxel3D = lib.require("Voxel3D")
  local fails = 0
  for rung = 1, Voxel3D.rungCount do
    for prec = 1, Voxel3D.precCount do
      for _, glow in ipairs({ false, true }) do
        for _, grid in ipairs({ false, true }) do
          local ok, what = Voxel3D.buildRung(rung, grid, prec, glow)
          if not ok then fails = fails + 1 end
          log(("rung=%d prec=%d glow=%s grid=%s -> %s %s"):format(
            rung, prec, tostring(glow), tostring(grid), ok and "OK" or "FAIL",
            ok and "" or tostring(what):sub(1, 600)))
        end
      end
    end
  end
  log("available", tostring(Voxel3D.available()), "glowLive",
      tostring(Voxel3D.glowLive), "refused", tostring(Voxel3D.glowRefused))
  for i, e in ipairs(Voxel3D.compileLog or {}) do
    log("compileLog", i, e.key, e.name, e.prec, tostring(e.glow),
        tostring(e.err):sub(1, 400))
  end

  -- A DRIVER THAT REFUSES THE FIELD. The ladder must give up the glow and
  -- nothing else: the mode comes up, on the rung and precision it would
  -- have had, with glowRefused set -- and the caves stay lit (Glow.ambient
  -- reads the refusal). The pattern is the define line itself, which the
  -- shader source never writes on its own.
  local realNew = love.graphics.newShader
  love.graphics.newShader = function(src, ...)
    if type(src) == "string" and src:find("#define GLOW_FIELD 1", 1, true) then
      error("fake driver: refusing the glow field")
    end
    return realNew(src, ...)
  end
  Voxel3D.resetShaders()
  Voxel3D.glowWanted = true
  local sh = Voxel3D.shader()
  local okLadder = sh ~= nil and Voxel3D.glowRefused == true
                   and Voxel3D.rung == 1 and Voxel3D.glowLive == false
  log(("fake-driver: built=%s refused=%s rung=%s glowLive=%s -> %s"):format(
    tostring(sh ~= nil), tostring(Voxel3D.glowRefused), tostring(Voxel3D.rung),
    tostring(Voxel3D.glowLive), okLadder and "OK" or "FAIL"))
  if not okLadder then fails = fails + 1 end
  local Glow = lib.require("Glow")
  local lit = { 1, 1, 1 }
  local fakeCave = { id = "ROCK_TUNNEL_1F", def = {} }
  local kept = Glow.ambient(fakeCave, lit, false)
  local okAmb = kept == lit
  log("fake-driver: cave ambient untouched ->", okAmb and "OK" or "FAIL")
  if not okAmb then fails = fails + 1 end
  love.graphics.newShader = realNew
  Voxel3D.resetShaders()

  log(fails == 0 and "ALL PASS" or ("FAILS " .. fails))
  logf:close()
  love.event.quit()
end
