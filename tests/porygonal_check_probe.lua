-- Did Porygonal 0.6.5 detect Terrarium as its renderer?
--
-- 0.6.5's release note is "add Terrarium as a supported renderer candidate",
-- and its shipped adapter is byte-identical to the one Terrarium generates --
-- so this should now work WITHOUT the local compat/porygonal patch. Before
-- 0.6.5 the log said "No compatible 3D renderer was detected" and the
-- characters stayed flat.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/porygonal_check.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
    logf:write(table.concat(p, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
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
  wait(90)

  -- exports only lists mods that EXPORT something, so a mod that loads
  -- silently is invisible there. Ask the registry itself.
  local M = game.mods
  log("game.mods campos:")
  for k, v in pairs(M or {}) do log("   ", tostring(k), " = ", type(v)) end
  for _, field in ipairs({ "loaded", "list", "active", "all", "byId", "entries", "order" }) do
    local t = M and M[field]
    if type(t) == "table" then
      local names = {}
      for k, v in pairs(t) do
        local id = (type(v) == "table" and (v.id or (v.manifest and v.manifest.id))) or k
        names[#names + 1] = tostring(id)
      end
      table.sort(names)
      log("  mods." .. field .. ": ", table.concat(names, ", "))
    end
  end
  if M and M.find then
    for _, id in ipairs({ "PORYGONAL_OVERWORLD_CHARACTERS", "TERRARIUM", "wild_skies" }) do
      local ok, found = pcall(M.find, M, id)
      if not ok then ok, found = pcall(M.find, id) end
      log("  find(", id, ") -> ", tostring(ok and found ~= nil and found ~= false))
    end
  end
  log("mods.disabled:")
  for k, v in pairs((M and M.disabled) or {}) do
    log("   ", tostring(k), " = ", type(v) == "table" and "<table>" or tostring(v))
    if type(v) == "table" then
      for k2, v2 in pairs(v) do log("       ", tostring(k2), " = ", tostring(v2)) end
    end
  end
  log("mods.errors:")
  for k, v in pairs((M and M.errors) or {}) do
    if type(v) == "table" then
      log("   ", tostring(k), ":")
      for k2, v2 in pairs(v) do log("       ", tostring(k2), " = ", tostring(v2):sub(1, 200)) end
    else
      log("   ", tostring(k), " = ", tostring(v):sub(1, 200))
    end
  end
  log("mods.content (ids vistos no disco):")
  for k, v in pairs((M and M.content) or {}) do
    local id = (type(v) == "table" and (v.id or (v.manifest and v.manifest.id))) or k
    log("   ", tostring(k), " -> ", tostring(id))
  end

  local ex = M and M.exports
  log("exports:")
  for id, _ in pairs(ex or {}) do log("   ", tostring(id)) end

  local P = ex and ex.PORYGONAL_OVERWORLD_CHARACTERS
  if not P then
    log("Porygonal nao exporta nada (pode ser normal)")
  else
    for _, k in ipairs({ "RendererManager", "rendererManager", "renderers" }) do
      local rm = P[k]
      if rm then
        log("achou ", k, " active=", tostring(rm.active and (rm.active.id or rm.active.name) or rm.active))
      end
    end
  end

  local T = ex and ex.TERRARIUM
  log("TERRARIUM exporta lib: ", tostring(T and T.lib ~= nil))
  if T and T.lib then
    local okV, Voxel3D = pcall(T.lib.require, "Voxel3D")
    log("Voxel3D.available(): ", tostring(okV and Voxel3D.available and Voxel3D.available()))
  end
  log("map: ", tostring(game.overworld and game.overworld.map and game.overworld.map.id))
  log("done")
  logf:close()
  love.event.quit()
end
