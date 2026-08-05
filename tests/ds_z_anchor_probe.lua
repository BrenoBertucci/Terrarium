-- Diagnostic: where does the sleeper's Z actually land?
--
-- Interiors.draw is handed a stub projection that records every world point
-- it is asked about, so the Z's anchor can be compared against the sleeper's
-- own position and the player's -- which a screenshot at this camera angle
-- cannot tell apart.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/z_anchor.log", "w"))
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

  local lib = game.mods.exports.TERRARIUM.lib
  local Interiors = lib.require("Interiors")
  Interiors.setting:sync("on")

  for _, id in ipairs({ "CERULEAN_MELANIES_HOUSE", "REDS_HOUSE_1F",
                        "COPYCATS_HOUSE_1F", "VERMILION_TRADE_HOUSE" }) do
    game.overworld:setMap(id, 3, 5, "down")
    wait(80)
    local pet = nil
    for _, e in ipairs(game.overworld.entities or {}) do
      if e.housePet then pet = e end
    end
    local p = game.overworld.player
    log(("== %s"):format(id))
    log(("  player px,py = %d,%d  cell %d,%d"):format(
      p.px, p.py, p.cellX, p.cellY))
    if pet then
      log(("  sleeper %s px,py = %d,%d  cell %d,%d"):format(
        pet.species, pet.px, pet.py, pet.cellX, pet.cellY))
    else
      log("  no sleeper here")
    end
    local asked = {}
    local function stub(wx, wy, wz)
      asked[#asked + 1] = { wx, wy, wz }
      return 100, 100, 1          -- a valid screen point, so the draw proceeds
    end
    Interiors.draw(stub, 6)
    log(("  Interiors.draw asked about %d world points:"):format(#asked))
    for i, a in ipairs(asked) do
      log(("    %2d  x=%7.1f  y=%6.1f  z=%7.1f"):format(i, a[1], a[2], a[3]))
    end
    -- the LAST point is the Z (the mugs go first); compare it to the sleeper
    if pet and #asked > 0 then
      local a = asked[#asked]
      log(("  last point vs sleeper: dx=%.1f dz=%.1f  (want ~6 and ~-2)")
          :format(a[1] - pet.px, a[3] - pet.py))
      log(("  last point vs player : dx=%.1f dz=%.1f")
          :format(a[1] - p.px, a[3] - p.py))
    end
  end

  logf:close()
  love.event.quit()
end
