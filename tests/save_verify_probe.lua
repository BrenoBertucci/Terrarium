-- Does the edited save load, and is the world it loads the one that was written?
-- Read-only: it looks and quits.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/save_verify.log", "w"))
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
  local ow = game.overworld
  local p = ow and ow.player
  log("map    ", tostring(ow and ow.map and ow.map.id),
      " cell (", tostring(p and p.cellX), ",", tostring(p and p.cellY), ")")
  local save = game.save or (game.data and game.data.save)
  local party = (save and save.party) or (game.party)
  if not party and game.getParty then party = game.getParty() end
  if party then
    log("party:")
    for i, mon in ipairs(party) do
      local mv = {}
      for _, m in ipairs(mon.moves or {}) do mv[#mv + 1] = tostring(m.id) end
      log(("  %d. %-9s lv%-3d hp %d/%d  %s"):format(
        i, tostring(mon.species), mon.level or -1, mon.hp or -1,
        (mon.stats and mon.stats.hp) or -1, table.concat(mv, ", ")))
    end
  else
    log("(party not reachable from here)")
  end
  local inv = save and save.inventory
  if inv then
    local badges = {}
    for k, v in pairs(inv) do
      if tostring(k):find("BADGE") then badges[#badges + 1] = tostring(k) end
    end
    table.sort(badges)
    log("badges: ", table.concat(badges, ", "))
  end
  local flags = save and save.flags
  if flags then log("EVENT_BEAT_KOGA = ", tostring(flags.EVENT_BEAT_KOGA)) end
  log("done")
  logf:close()
  love.event.quit()
end
