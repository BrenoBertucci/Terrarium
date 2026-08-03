-- Probe: the hidden-item glints land on the cells the GAME says are buried,
-- and go out when one is taken.
--
-- Verified against `field.hiddenItems` with a stub projection that records
-- every world point asked about, rather than by looking at a screenshot: at
-- this camera angle a glint on the right cell and a glint one cell over are
-- indistinguishable by eye, and "it drew something" is not the claim.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/DRAMATIC_SHAPE/tests/hidden_glint_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/hidden_glint.log", "w"))
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
  local fails = 0
  local function check(ok, what)
    log((ok and "  OK   " or "  FAIL ") .. what)
    if not ok then fails = fails + 1 end
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
  local Hidden = lib.require("HiddenItems")
  local QoL = lib.require("QoL")
  QoL.setting:sync("on")

  -- Collect the glints Hidden.draw asks about, over a whole pulse period so
  -- a cell that happened to be at the dark end of its cycle still shows up.
  local function glints()
    local seen = {}
    for _ = 1, 130 do
      local function stub(wx, wy, wz)
        local cx, cy = math.floor(wx / 16), math.floor(wz / 16)
        seen[cx .. "," .. cy] = true
        return 100, 100, 1
      end
      pcall(Hidden.draw, stub, 6)
      coroutine.yield()
    end
    local out = {}
    for k in pairs(seen) do out[#out + 1] = k end
    table.sort(out)
    return out, seen
  end

  -- a map with buried items and room to stand in the middle of them
  local field = game.data.field
  local best, bestN = nil, 0
  for id, list in pairs(field.hiddenItems or {}) do
    if game.data.maps[id] and #list > bestN then best, bestN = id, #list end
  end
  log("richest map for buried items: " .. tostring(best) .. " with " .. bestN)

  for _, mapId in ipairs({ "VIRIDIAN_CITY", best }) do
    local list = field.hiddenItems[mapId]
    if list and #list > 0 then
      log("")
      log("== " .. mapId .. " ==")
      -- stand on the first buried cell so everything is inside REACH
      game.overworld:setMap(mapId, list[1].x, list[1].y, "down")
      wait(70)

      local want = {}
      for _, h in ipairs(list) do
        log(("  data says: %-14s at cell %d,%d"):format(h.item, h.x, h.y))
        want[h.x .. "," .. h.y] = true
      end
      local remaining, total = Hidden.remaining()
      log(("  module sees %d buried, %d still untaken"):format(total, remaining))
      check(total == #list, "the module found every buried item on this map")

      local got, seen = glints()
      log("  glints drawn at cells: " .. table.concat(got, "  "))
      local p = game.overworld.player
      local expected = 0
      for _, h in ipairs(list) do
        local key = game.overworld.map.id .. "_" .. h.x .. "_" .. h.y
        local taken = (game.save.hiddenTaken or {})[key]
        local near = math.abs(h.x - p.cellX) <= 12
                     and math.abs(h.y - p.cellY) <= 12
        if near and not taken then
          expected = expected + 1
          check(seen[h.x .. "," .. h.y] == true,
                ("a glint landed on %d,%d (%s)"):format(h.x, h.y, h.item))
        end
      end
      -- and NOTHING anywhere else
      local strays = 0
      for _, k in ipairs(got) do if not want[k] then strays = strays + 1 end end
      check(strays == 0, ("no glint on a cell with nothing buried (%d stray)")
            :format(strays))
      log(("  %d expected in range"):format(expected))

      -- ------- taking one puts its light out
      if expected > 0 then
        local h = nil
        for _, cand in ipairs(list) do
          if math.abs(cand.x - p.cellX) <= 12
             and math.abs(cand.y - p.cellY) <= 12 then h = cand break end
        end
        local key = game.overworld.map.id .. "_" .. h.x .. "_" .. h.y
        game.save.hiddenTaken = game.save.hiddenTaken or {}
        game.save.hiddenTaken[key] = true
        local _, after = glints()
        check(after[h.x .. "," .. h.y] ~= true,
              ("taking %d,%d put its glint out"):format(h.x, h.y))
        game.save.hiddenTaken[key] = nil     -- leave the save as we found it
      end

      -- ------- the QOL row switches it off
      QoL.setting:sync("off")
      local off = glints()
      check(#off == 0, "the QOL row switches the glints off")
      QoL.setting:sync("on")
    end
  end

  log("")
  log(fails == 0 and "ALL CHECKS PASSED" or (fails .. " CHECK(S) FAILED"))
  logf:close()
  love.event.quit()
end
