-- Trees3D.ready / buildsInFlight, headless, against the REAL bake.
--
-- The probe's whole settle() loop hangs on this state machine being right:
-- a ready() that never goes true burns 6000 ticks and reports a stall that
-- did not happen, and one that goes true early puts the build back inside
-- the sample -- which is the bug the poll was written to remove. Both are
-- cheap to catch here and expensive to catch in a game round.
--
-- Run from the mod root (it reads assets/ground/tree/ off the disk):
--   luajit tests/trees_ready_offline.lua
--   ...or through tools/luacheck.py's runtime, see the probe notes.

-- GroundFX's own threshold, restated rather than required: pulling that
-- module in headless would drag love.graphics behind it. If it moves
-- there, this fails and says so, which is the point.
local function GroundCanopyDry() return 0.45 end

local fails = 0
local function check(ok, msg)
  print((ok and "ok    " or "FAIL  ") .. msg)
  if not ok then fails = fails + 1 end
end

-- ---- the smallest world Trees3D will run in
local drawn = {}
local stubs = {}
stubs.Voxel3D = {
  available = function() return true end,
  packedShade = function() end,
  draw = function() end,
  newMesh = function(verts, indices)
    return { nv = #verts, ni = #indices, setTexture = function() end }
  end,
}
stubs.Mat4 = { translate = function() return {} end }
stubs.ShadowMap = {
  snug = function(m) return m end,
  draw = function(mesh) drawn[#drawn + 1] = mesh end,
}

local sitesByMap = {}
stubs.Structures = {
  forMap = function(map) return { treeSites = sitesByMap[map.id] } end,
}

local V = {
  path = ".",
  require = function(name) return stubs[name] end,
}

-- love, only as much of it as the loader touches
local fakeImage = { setFilter = function() end }
love = {
  graphics = { newImage = function() return fakeImage end },
}

local chunk = assert(loadfile("lib/Trees3D.lua"))
local Trees3D = chunk(V)

-- ---- the bake has to be there or nothing below means anything
check(Trees3D.available(), "bake loads offline (" ..
      table.concat(Trees3D.loaded(), ",") .. ")")
if not Trees3D.available() then os.exit(1) end

local meta = Trees3D.meta()
check(meta and meta.tris > 0, "template metadata: " ..
      (meta and (meta.tris .. " tris, " .. meta.trunkTris .. " trunk") or "none"))

-- ---- a map with a known number of sites
local N = 40
local sites = {}
for i = 1, N do sites[i] = { mx = (i % 8) * 16, mz = math.floor(i / 8) * 16, r = 8 } end
sitesByMap.TEST = sites
local map = { id = "TEST" }

-- cold: nothing drawn yet
local done, state, sd, stot = Trees3D.ready(map)
check(not done and state == "cold", "before any draw: " .. state)
check(select(2, Trees3D.buildsInFlight()) == 0, "nothing in flight yet")

-- one draw = one slice, and NOT one site more
Trees3D.draw(map, true, 0, 0)
done, state, sd, stot = Trees3D.ready(map)
check(state == "building", "after one draw: " .. state)
check(sd == Trees3D.SLICE_SITES,
      "one draw stamped exactly SLICE_SITES: " .. sd .. " of " .. stot)
check(stot == N, "total is the site count: " .. stot)

-- ready() must be a READ. Polling it must not move the build.
for _ = 1, 50 do Trees3D.ready(map) end
check(select(3, Trees3D.ready(map)) == Trees3D.SLICE_SITES,
      "polling ready() 50 times advanced nothing")

local _, owed = Trees3D.buildsInFlight()
check(owed == N - Trees3D.SLICE_SITES, "sites owed = " .. owed)

-- and the build completes in exactly the arithmetic number of draws
local want = math.ceil(N / Trees3D.SLICE_SITES)
local draws = 1
while not Trees3D.ready(map) and draws < 500 do
  Trees3D.draw(map, true, 0, 0)
  draws = draws + 1
end
check(draws == want, "completed in " .. draws .. " draws (arithmetic says "
      .. want .. ")")
done, state, sd, stot = Trees3D.ready(map)
check(done and state == "ready", "final state: " .. state)
check(sd == N and stot == N, "progress reports " .. sd .. "/" .. stot)
check(select(2, Trees3D.buildsInFlight()) == 0, "nothing left in flight")

-- ---- THE SUN PASS CONSUMES THE BUILD, IT DOES NOT ADVANCE IT.
--
-- Both passes used to go through meshesFor, so a constructing frame
-- stamped two slices and SLICE_SITES cost double what it reads as (2.00
-- draws/tick, measured on ROUTE_2). Nothing about that was visible from
-- inside the game -- the forest simply arrived, and the frames it cost
-- looked like the frames it was supposed to cost.
sitesByMap.SUNTEST = sites
local sunMap = { id = "SUNTEST" }
Trees3D.draw(sunMap, true, 0, 0)
local before = select(3, Trees3D.ready(sunMap))
check(before == Trees3D.SLICE_SITES, "one draw stamped one slice: " .. before)
for _ = 1, 20 do Trees3D.castShadows(sunMap, 0, 0) end
check(select(3, Trees3D.ready(sunMap)) == before,
      "20 shadow passes advanced nothing (still " .. before .. ")")
Trees3D.draw(sunMap, true, 0, 0)
check(select(3, Trees3D.ready(sunMap)) == before + Trees3D.SLICE_SITES,
      "and the scene pass still advances exactly one slice")

-- ---- the terminal state, which settle() must break on rather than spin
sitesByMap.EMPTY = {}
local empty = { id = "EMPTY" }
Trees3D.draw(empty, true, 0, 0)
done, state = Trees3D.ready(empty)
check(not done and state == "hulls", "a map with no sites: " .. state)
for _ = 1, 20 do Trees3D.draw(empty, true, 0, 0) end
check(select(2, Trees3D.ready(empty)) == "hulls", "and it STAYS hulls")

-- over the ceiling is the other way in
local many = {}
for i = 1, Trees3D.MAX_TREES + 1 do many[i] = { mx = i, mz = 0, r = 8 } end
sitesByMap.HUGE = many
local huge = { id = "HUGE" }
Trees3D.draw(huge, true, 0, 0)
check(select(2, Trees3D.ready(huge)) == "hulls",
      "over MAX_TREES is terminal too")

-- ---- the shadow caster is the CARD-LESS mesh, and the switch picks it
drawn = {}
Trees3D.SHADOW_SOLID_ONLY = true
Trees3D.castShadows(map, 0, 0)
local solid = drawn[1]
drawn = {}
Trees3D.SHADOW_SOLID_ONLY = false
Trees3D.castShadows(map, 0, 0)
local full = drawn[1]
check(solid and full, "both casters drew")
if solid and full then
  check(solid.ni < full.ni, string.format(
        "card-less caster is smaller: %d indices vs %d (%.0f%% of the "
        .. "triangles)", solid.ni, full.ni, solid.ni / full.ni * 100))
  check(solid.nv == full.nv,
        "same vertex buffer, only the index list differs")
  -- The number, not just the inequality. A boundary bug in the card
  -- derivation left this at 100% while every count in the probe passed,
  -- so pin it to the bake's own arithmetic: 420 tris of which 120 are
  -- cards leaves 300 solid.
  local perTree = solid.ni / 3 / N
  check(math.abs(perTree - 300) < 0.5, string.format(
        "%.1f solid tris per tree (the bake says 300 of 420)", perTree))
end
Trees3D.SHADOW_SOLID_ONLY = true

-- ---- A BUILD NOBODY IS DRAWING ANY MORE MUST BE THROWN AWAY.
--
-- Slices only land while the map is drawn, so walking away froze the
-- build where it stood: the buffers stayed resident and the sites it owed
-- were owed forever. The probe sat 6000 ticks on that.
Trees3D.invalidate()
local walked = {}
for i = 1, 300 do walked[i] = { mx = i * 3, mz = 0, r = 8 } end
-- The map we arrive on needs enough sites to still be building when the
-- sweep is due, so the two assertions below are about the sweep and not
-- about which map happened to finish first.
local arrived = {}
for i = 1, (Trees3D.RETIRE_AFTER + 40) * Trees3D.SLICE_SITES do
  arrived[i] = { mx = i, mz = 8, r = 8 }
end
sitesByMap.WALKED, sitesByMap.ARRIVED = walked, arrived
local left, here = { id = "WALKED" }, { id = "ARRIVED" }

Trees3D.draw(left, true, 0, 0)          -- start a build, then leave
Trees3D.draw(left, true, 0, 0)
check(select(2, Trees3D.ready(left)) == "building", "the map we leave is mid-build")
local owedAway = select(2, Trees3D.buildsInFlight())
check(owedAway > 0, "it owes " .. owedAway .. " sites when we walk off")

for _ = 1, Trees3D.RETIRE_AFTER + 4 do Trees3D.draw(here, true, 0, 0) end
check(select(2, Trees3D.ready(left)) == "cold",
      "after RETIRE_AFTER advances elsewhere it is retired, not frozen")
check(select(2, Trees3D.ready(here)) == "building",
      "and the map we are ON is untouched by the sweep")

-- and it must not retire a build that is still being advanced
Trees3D.invalidate()
for _ = 1, Trees3D.RETIRE_AFTER * 2 do Trees3D.draw(here, true, 0, 0) end
local st = select(2, Trees3D.ready(here))
check(st == "building" or st == "ready",
      "a build advanced every call survives the sweep (" .. st .. ")")

-- ---- CANOPY COVERAGE LANDS UNDER THE TREE THAT CASTS IT.
--
-- The coverage pass and the mesh stamp read the same `placement`, and the
-- entire point of factoring that out was that they cannot drift. This
-- checks the property rather than the refactor: stamp ONE site, take the
-- centroid of the geometry it produced, take the centroid of the cells the
-- coverage pass reported, and require them to agree. A jitter or a scale
-- that got out of step moves one and not the other.
--
-- Deliberately NOT recomputing the expected position from the same
-- arithmetic -- that would be a copy of the pair this is here to rule out.
do
  -- A CELL CENTRE, not a cell corner. 512 is 32 cells exactly, which puts
  -- the crown on the corner where four cells meet and splits its cover
  -- four ways -- the first version of this test did that and read a peak
  -- of 0.303, which says something true about corners and nothing about
  -- whether a tree shelters the ground under it.
  local one = { { mx = 32 * 16 + 8, mz = 32 * 16 + 8, r = 8 } }
  sitesByMap.COVER = one
  local coverMap = { id = "COVER" }

  local st = { sites = one, names = Trees3D.loaded(), buckets = {}, shadow = {} }
  for k = 1, #st.names do
    st.buckets[k] = { verts = {}, indices = {} }
    st.shadow[k] = { verts = {}, indices = {} }
  end
  Trees3D.stampRange(st, 1, 1)

  -- centroid of the CANOPY vertices only -- the trunk sits at the axis and
  -- would drag the answer toward it whatever the crown did
  local gx, gz, gw = 0, 0, 0
  for k = 1, #st.names do
    local tpl = Trees3D.templates[st.names[k]]
    local v = st.buckets[k].verts
    for i = 1, #v do
      local w = (tpl.weights and tpl.weights[i]) or 0
      gx = gx + v[i][1] * w; gz = gz + v[i][3] * w; gw = gw + w
    end
  end
  gx, gz = gx / math.max(gw, 1e-9), gz / math.max(gw, 1e-9)

  local cx_, cz_, cw, cells, maxCover = 0, 0, 0, 0, 0
  local n = Trees3D.eachCanopyCell(coverMap, function(cx, cy, cover)
    cx_ = cx_ + (cx * 16 + 8) * cover
    cz_ = cz_ + (cy * 16 + 8) * cover
    cw = cw + cover
    cells = cells + 1
    if cover > maxCover then maxCover = cover end
  end)
  check(n and n >= 4, "coverage reported " .. tostring(n) .. " cells for 1 site")
  check(maxCover <= 1, string.format("cover never exceeds 1: peak %.3f",
                                     maxCover))
  -- A crown is wider than a cell, so the cell under one has to come back
  -- SHELTERED rather than nominally covered. Sampling the cell centre only
  -- reported 0.039 here and would have made the whole feature a no-op that
  -- every count still passed.
  check(maxCover > 0.5, string.format(
        "the cell under a crown is properly covered: peak %.3f", maxCover))
  if cw > 0 then
    cx_, cz_ = cx_ / cw, cz_ / cw
    local dx, dz = cx_ - gx, cz_ - gz
    local d = math.sqrt(dx * dx + dz * dz)
    check(d < 16, string.format(
          "coverage centroid is under the crown: %.1f px from the geometry "
          .. "(one cell is 16)", d))
  end

  -- ---- AND WHAT A REAL WOOD LOOKS LIKE
  --
  -- One tree is the easy case. A route is 862 sites on adjacent cells, and
  -- what the ground effects actually read is the DEEP INTERIOR of that --
  -- where several crowns overlap. Combined the way GrassWear combines
  -- them: deepest wins, because two canopies over one cell is the same sky
  -- blocked twice rather than twice the shade.
  local wood = {}
  for gy = 0, 4 do
    for gx = 0, 4 do
      wood[#wood + 1] = { mx = (40 + gx) * 16 + 8, mz = (40 + gy) * 16 + 8,
                          r = 8 }
    end
  end
  sitesByMap.WOOD = wood
  local best, cells2 = {}, 0
  Trees3D.eachCanopyCell({ id = "WOOD" }, function(cx, cy, cover)
    local k = cy * 4096 + cx
    if cover > (best[k] or 0) then
      if not best[k] then cells2 = cells2 + 1 end
      best[k] = cover
    end
  end)
  local mid = best[(40 + 2) * 4096 + (40 + 2)] or 0
  local open = best[(40 + 12) * 4096 + (40 + 12)] or 0
  check(mid > GroundCanopyDry(), string.format(
        "the middle of a wood is sheltered: %.3f (GroundFX needs >= 0.45 "
        .. "to keep the ground dry)", mid))
  check(open == 0, "and open ground well clear of it stays at 0")
  check(cells2 >= 25, "a 25-site wood covers " .. cells2 .. " cells")

  -- and a map with nothing on it reports nothing rather than zero cells
  sitesByMap.NOTREES = {}
  check(Trees3D.eachCanopyCell({ id = "NOTREES" }, function() end) == nil,
        "a map with no sites reports nil, not an empty sweep")
end

-- ---- invalidate really does reset the progress bookkeeping
Trees3D.invalidate()
check(select(2, Trees3D.ready(map)) == "cold", "invalidate() returns to cold")

print(fails == 0 and "PASS all" or ("FAIL " .. fails))
os.exit(fails == 0 and 0 or 1)
