-- Is qol_toggles loaded, and is FIELD MOVES ALL actually on?
--
-- This gates a save edit: with FIELD MOVES ALL working, FLY no longer needs a
-- move slot and the slot can hold an attack. If the mod is NOT working and the
-- slot has been spent anyway, the player has simply lost FLY -- so the edit
-- must not happen until this says yes.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/qol_check.log", "w"))
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
  wait(60)

  local M = game.mods
  local loaded = {}
  for k, v in pairs((M and M.loaded) or {}) do
    loaded[#loaded + 1] = tostring((type(v) == "table" and (v.id or (v.manifest and v.manifest.id))) or k)
  end
  table.sort(loaded)
  log("mods.loaded: ", table.concat(loaded, ", "))
  log("qol_toggles disabled? ", tostring((M and M.disabled and M.disabled.qol_toggles) or false))
  log("erros:")
  for k, v in pairs((M and M.errors) or {}) do log("   ", tostring(k), " = ", tostring(v):sub(1, 200)) end

  -- its stored options, which is where the four switches live
  local mo = M and M.modOptions and M.modOptions.qol_toggles
  if mo then
    log("modOptions.qol_toggles:")
    for k, v in pairs(mo) do log("   ", tostring(k), " = ", tostring(v)) end
  else
    log("modOptions.qol_toggles = (nada gravado ainda -- usa os defaults)")
  end

  local ex = M and M.exports and M.exports.qol_toggles
  log("exporta algo: ", tostring(ex ~= nil))
  if type(ex) == "table" then
    for k, v in pairs(ex) do log("   export ", tostring(k), " = ", type(v)) end
  end
  log("done")
  logf:close()
  love.event.quit()
end
