-- Probe: is a baked roamer actually TELLABLE from the next one?
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/roamer_bake_probe.lua gen1recomp
--
-- The bug this exists for was reported as "Sandshrew almost looks like
-- Charmander, and Growlithe is unintelligible", and the fix for it (REV 3:
-- edge-only outline bias, cell floor 12, head crop) was verified by looking.
-- Looking is how the bug shipped in the first place: every one of these reads
-- fine while you already know which species you asked for.
--
-- So this asks it as a number. Two of them:
--
--   MUD    what share of a mon's ink came out DARK. The defect the edge-only
--          outline bias targets is interior hatch winning whole cells, and a
--          mon that is 90% black is a silhouette whatever else is true of it.
--
--   TWIN   how close the closest OTHER species is, as the share of the 16x16
--          frame where the two disagree. This is the metric that matches the
--          complaint: nobody minds a rough sprite, they mind two sprites they
--          cannot tell apart. Reported per species and as a leaderboard.
--
-- Both are computed off frame 0 of whatever def RoamerArt hands out, so this
-- measures the SHIPPED sheets when the pack is installed and the BAKE when it
-- is not -- and it says which it did, because comparing one against the other
-- would be measuring two different features.
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/roamer_bake_probe.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
    logf:write(table.concat(p, " ") .. "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local function bail(why)
    log("FAIL " .. why); logf:close(); love.event.quit()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then return bail("no ow") end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then return bail("no lib") end
  log("version", exports.TERRARIUM.version)

  local RoamerArt = lib.require("RoamerArt")
  local Assets = require("src.render.Assets")
  local Game = require("src.core.Game")
  if not RoamerArt.available() then return bail("RoamerArt reports broken") end
  log("REV", RoamerArt.REV)

  -- ------- collect one 16x16 shade grid per species
  --
  -- Quantised to four states (clear / light / mid / dark) off LUMINANCE, not
  -- off the red channel: the bake is grey and the shipped Gen-2 sheets are
  -- not, and a metric that only works on one of them cannot answer "did this
  -- get better" after a pack is installed.
  local F = RoamerArt.FRAME
  local function gridOf(def)
    local ok, img = pcall(Assets.imageData, def.image)
    if not (ok and img) then return nil end
    local g, ink, dark = {}, 0, 0
    for y = 0, F - 1 do
      for x = 0, F - 1 do
        local okp, r, gg, b, a = pcall(img.getPixel, img, x, y)
        local s = 0
        if okp and (a or 0) >= 0.5 then
          local lum = 0.299 * r + 0.587 * gg + 0.114 * b
          if lum > 0.66 then s = 1 elseif lum > 0.33 then s = 2 else s = 3 end
          ink = ink + 1
          if s == 3 then dark = dark + 1 end
        end
        g[y * F + x] = s
      end
    end
    return g, ink, dark
  end

  local names, grids, mud = {}, {}, {}
  local shipped, baked, skipped = 0, 0, 0
  for species in pairs(Game.data and Game.data.pokemon or {}) do
    -- mayBake = true: this is the one caller that WANTS the write, so a cold
    -- save measures the same thing a warm one does.
    local ok, def = pcall(RoamerArt.def, species, true)
    if ok and def and def.image then
      local g, ink, dark = gridOf(def)
      if g and ink > 0 then
        names[#names + 1] = species
        grids[species] = g
        mud[species] = dark / ink
        if def.trueColor then shipped = shipped + 1 else baked = baked + 1 end
      else skipped = skipped + 1 end
    else skipped = skipped + 1 end
  end
  table.sort(names)
  log(("species %d  (shipped sheets %d, front-pic bakes %d, skipped %d)")
      :format(#names, shipped, baked, skipped))
  if shipped > 0 and baked > 0 then
    log("MIXED SET -- some species wear the pack and some wear the bake.")
    log("  the TWIN numbers below compare across both and are not a clean read")
    log("  of either. Run again with assets/roamers/*.png moved aside.")
  end
  if #names < 2 then return bail("nothing to compare") end

  -- ------- MUD
  local worst = {}
  for _, s in ipairs(names) do worst[#worst + 1] = s end
  table.sort(worst, function(a, b) return mud[a] > mud[b] end)
  log("")
  log("=== MUD: share of a mon's ink that came out DARK")
  local sum = 0
  for _, s in ipairs(names) do sum = sum + mud[s] end
  log(("mean %.3f over %d species"):format(sum / #names, #names))
  for i = 1, math.min(10, #worst) do
    log(("  %-14s %.3f"):format(worst[i], mud[worst[i]]))
  end

  -- ------- TWIN
  --
  -- O(n^2) over 151 species and 256 cells is ~5.8M comparisons, which is a
  -- couple of seconds once. Cheaper than being wrong about it.
  local function dist(a, b)
    local ga, gb, d = grids[a], grids[b], 0
    for i = 0, F * F - 1 do if ga[i] ~= gb[i] then d = d + 1 end end
    return d / (F * F)
  end
  local twin, twinOf = {}, {}
  for i = 1, #names do
    local a = names[i]
    local best, bestS = 1e9, nil
    for j = 1, #names do
      if i ~= j then
        local d = dist(a, names[j])
        if d < best then best, bestS = d, names[j] end
      end
    end
    twin[a], twinOf[a] = best, bestS
  end
  local rank = {}
  for _, s in ipairs(names) do rank[#rank + 1] = s end
  table.sort(rank, function(a, b) return twin[a] < twin[b] end)
  log("")
  log("=== TWIN: closest other species, as share of the frame that DIFFERS")
  log("    (lower = harder to tell apart. 0.000 would be identical art.)")
  for i = 1, math.min(15, #rank) do
    local s = rank[i]
    log(("  %-14s %.3f  vs %s"):format(s, twin[s], tostring(twinOf[s])))
  end

  -- the two the report named, called out whatever they rank
  log("")
  log("=== the reported pair")
  if grids.SANDSHREW and grids.CHARMANDER then
    log(("  SANDSHREW vs CHARMANDER  %.3f"):format(dist("SANDSHREW", "CHARMANDER")))
  end
  for _, s in ipairs({ "SANDSHREW", "GROWLITHE", "PIKACHU", "ONIX", "EKANS" }) do
    if grids[s] then
      log(("  %-10s mud %.3f  twin %.3f (%s)")
          :format(s, mud[s], twin[s], tostring(twinOf[s])))
    end
  end

  log("")
  log("done")
  logf:close()
  love.event.quit()
end
