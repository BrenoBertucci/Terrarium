-- Probe: the snow is OFF the drawing.
--
-- What this is checking is a removal and a replacement. The snow on a
-- figure used to be white mixed into the sprite card's own texels by the
-- scene shader (Voxel3D's coat block, driven by Voxel3D.coat). It is a
-- quad standing on the drawing's top edges now (SnowField.cap), owned by
-- lib/SnowOnFX.lua the way lib/RainOnFX.lua owns the rain's drops.
--
-- Three ways that can be wrong and still look finished:
--
--   1. The paint is still on. `coat` is set per draw and read by the
--      shader, so nothing errors if it stays non-zero -- the new quad just
--      draws on TOP of the old whitening and the complaint is unfixed.
--      So the max `Voxel3D.coat` in effect across a snowy scene is
--      sampled at the draw itself, not asserted from the flag.
--   2. The cap builds and never draws. A mesh that fails to build returns
--      nil and the loop skips it in silence, which looks exactly like
--      "the snow melted". So cap meshes are tagged as they are made and
--      counted as they reach Voxel3D.draw.
--   3. The cap is one shape for everybody. The whole reason it is built
--      per column is that a sprite sheet is not a person-shaped promise:
--      Pikachu, a roamer and the player have their tops in different
--      places. capTop is read for every sprite on the map and the spread
--      is logged -- one number for all of them means the profile is not
--      being read.
--
-- And an A/B in one run, same camera, same snowfall: the old look (paint
-- on, cap off) and the new one (paint off, cap on), a few frames apart.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/snow_on_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/snow_on_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  -- wait for the CALLBACK: a shot scheduled and then given N yields
  -- photographs whatever the game moved on to
  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      done = true
    end)
    local guard = 0
    while not done and guard < 240 do coroutine.yield(); guard = guard + 1 end
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit() return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end
  game.input:reset()

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then log("FAIL: TERRARIUM not loaded") logf:close() love.event.quit() return end
  log("terrarium:", exports.TERRARIUM.version)

  local Voxel3D = lib.require("Voxel3D")
  local SnowField = lib.require("SnowField")
  local SnowOnFX = lib.require("SnowOnFX")
  local Weather = lib.require("Weather")
  local GroundFX = lib.require("GroundFX")
  local DayNight = lib.require("DayNight")
  local Wind = lib.require("Wind")
  local Pipelines = require("src.render.Pipelines")

  GroundFX.setting:sync("on")
  DayNight.setting:sync("day")
  Wind.setting:sync(2)
  pcall(function() lib.require("MarioCam").setting:sync("off") end)
  GroundFX.SETTLE, GroundFX.MELT = 6, 4
  Weather.setting:sync("snow")

  -- ------- instruments
  --
  -- capMeshes: every mesh SnowField.cap handed back, so a draw of one is
  -- identifiable at Voxel3D.draw. Weak keys, like every other mesh table
  -- in this mod.
  local capMeshes = setmetatable({}, { __mode = "k" })
  local capBuilds, capNil = 0, 0
  -- WHOSE sheet the cap was asked for. With a 3D character mod driving the
  -- pass the figures it replaced must get none, and the wild Pokemon --
  -- which it has no model for and which are still cards -- must still get
  -- theirs. A count alone cannot tell those two apart; the sheet names can.
  local capSheets = {}
  local realCap = SnowField.cap
  SnowField.cap = function(def, frame, k, cut)
    local mesh, img = realCap(def, frame, k, cut)
    if mesh then
      capMeshes[mesh] = true
      capBuilds = capBuilds + 1
      if def and def.image then capSheets[def.image] = true end
    else capNil = capNil + 1 end
    return mesh, img
  end

  local stat = { draws = 0, capDraws = 0, maxCoat = 0, coatDraws = 0 }
  local realDraw = Voxel3D.draw
  Voxel3D.draw = function(mesh, texture, model, pull, sunModel, sway, ...)
    stat.draws = stat.draws + 1
    if capMeshes[mesh] then stat.capDraws = stat.capDraws + 1 end
    local c = tonumber(Voxel3D.coat) or 0
    if c > 0 then stat.coatDraws = stat.coatDraws + 1 end
    if c > stat.maxCoat then stat.maxCoat = c end
    return realDraw(mesh, texture, model, pull, sunModel, sway, ...)
  end
  local function zero()
    stat.draws, stat.capDraws, stat.maxCoat, stat.coatDraws = 0, 0, 0, 0
    capBuilds, capNil = 0, 0
  end

  -- ------- a snowed town
  game.overworld:setMap("VIRIDIAN_CITY", 17, 20, "down")
  wait(120)
  game.input:reset()
  local up = false
  for f = 1, 600 do
    coroutine.yield()
    if f % 60 == 0 then Pipelines.setLevel("terrarium_voxel", 4) end
    if stat.draws > 400 then up = true break end
  end
  log("voxel pass:", up and "up" or "FAIL never drew",
      "| level", tostring(Pipelines.level("terrarium_voxel")))

  local spun = 0
  while GroundFX.cover() < 0.70 and spun < 3000 do wait(10); spun = spun + 10 end
  log(("cover %.2f after %d frames | depth %s | gate %s")
      :format(GroundFX.cover(), spun,
              tostring(GroundFX.snowDepth(game.overworld.map)),
              tostring(SnowOnFX.lastGate)))

  -- let the cap climb
  wait(420)
  local p = game.overworld.player
  log(("SnowOnFX: ambient %.2f | capOf(player) %.2f | paintOf(player) %.2f | PAINT %s")
      :format(SnowOnFX.ambient(), SnowOnFX.capOf(p), SnowOnFX.paintOf(p),
              tostring(SnowOnFX.PAINT)))
  -- which body is standing there, and therefore which snow it wears
  local solid = SnowOnFX.solid()
  log(("character pass: %s -> %s")
      :format(solid and "SOLID (a 3D character mod took the billboard seam)"
                     or "CARD (sprite billboards)",
              solid and "no cap; the snow a walker makes is what the boots throw up"
                     or "SnowField.cap, a ridge on the drawing's top edges"))

  -- ------- 3. is the profile actually per sprite
  local seen, tops, lo, hi = {}, {}, nil, nil
  local function noteTop(e, who)
    local def = e and e.sprite and e.sprite.def
    if not (def and def.image) or seen[def.image] then return end
    seen[def.image] = true
    local t = SnowField.capTop(def, 0)
    tops[#tops + 1] = ("%s=%s(%s)"):format(who, tostring(t), def.image:match("([^/\\]+)$") or "?")
    if t then
      if not lo or t < lo then lo = t end
      if not hi or t > hi then hi = t end
    end
  end
  noteTop(p, "player")
  for i = 1, #(game.overworld.npcs or {}) do
    noteTop(game.overworld.npcs[i], "npc" .. i)
    if #tops >= 8 then break end
  end
  log("capTop per sprite: " .. table.concat(tops, "  "))
  log(("  spread: %s..%s"):format(tostring(lo), tostring(hi)))

  -- ------- the A/B, same camera, same snowfall
  --
  -- OLD: the shader paints the card's texels and no quad is built.
  -- A CAP_MIN above 1 is a cap that can never clear its own threshold.
  local keepMin = SnowField.CAP_MIN
  SnowOnFX.PAINT = true
  SnowField.CAP_MIN = 2
  zero(); wait(90)
  shot("snowon_A_painted.png")
  log(("OLD (paint on, cap off): draws %d | coat>0 on %d draws, max %.2f"
       .. " | cap meshes built %d, drawn %d")
      :format(stat.draws, stat.coatDraws, stat.maxCoat, capBuilds, stat.capDraws))
  local old = { coatDraws = stat.coatDraws, maxCoat = stat.maxCoat,
                capDraws = stat.capDraws }

  -- NEW: nothing on the texels, a quad on the edges.
  SnowOnFX.PAINT = false
  SnowField.CAP_MIN = keepMin
  local sheds0, flakes0 = SnowOnFX.sheds, Weather.figureFlakes
  zero(); wait(90)
  shot("snowon_B_capped.png")
  -- and WHY, for the one figure the eye goes to. A cap that is not drawn
  -- looks exactly like a cap that melted, so ask the builder directly with
  -- the same arguments the draw loop would have handed it.
  do
    local VS = lib.require("VoxelScene")
    local sprite, _, _, facing, phase, flip = p:pose()
    local def = sprite and sprite.def
    local fr, mir = VS._frameFor(def, facing, phase, flip)
    local sink = 0
    local okd, depth = pcall(GroundFX.snowDepth, game.overworld.map)
    if okd and depth then
      local oks, s = pcall(SnowField.sink, depth)
      sink = (oks and s) or 0
    end
    -- realCap, NOT the wrapped one: asking the builder here is a question,
    -- not a draw, and going through the wrapper would file the player's
    -- sheet under "wore a cap this frame" and fail the solid verdict below
    -- on the strength of the probe's own question
    local mesh = realCap(def, fr, SnowOnFX.capOf(p), sink)
    log(("  player: k %.2f frame %s mirror %s sink %s -> cap mesh %s")
        :format(SnowOnFX.capOf(p), tostring(fr), tostring(mir), tostring(sink),
                mesh and "built" or "NONE"))
  end
  log(("NEW (paint off, cap on): draws %d | coat>0 on %d draws, max %.2f"
       .. " | cap meshes built %d, drawn %d (nil %d)")
      :format(stat.draws, stat.coatDraws, stat.maxCoat, capBuilds,
              stat.capDraws, capNil))

  -- ------- walking in it
  --
  -- Two things happen while a walker crosses a drift, and the shot has to
  -- be taken WHILE they are walking: both are half-second motes, so a
  -- picture a few frames after the last step is a picture of neither.
  --
  --   the KICK   what the boots throw up out of the ground (lib/StepFX.lua,
  --              white on snow). World space, so it is the same effect
  --              whatever is standing in the boots -- and on the solid
  --              path it is the whole of it.
  --   the SHED   clumps letting go of the snow lying on them. Card path
  --              only: nothing is drawn on a solid body to come off it.
  local StepFX = lib.require("StepFX")
  local function snowMotes()
    local c, b = 0, 0
    for i = 1, StepFX.count() do
      local m = StepFX.get(i)
      if m and m.snow then
        c = c + 1
        if m.kind == "burst" then b = b + 1 end
      end
    end
    return c, b
  end
  local emitted0 = StepFX.emitted
  local peakKick, peakBurst = 0, 0

  -- Walk a stretch and take the picture MID-STRIDE, with a trail of motes
  -- still alive behind the boots. Repeated per candidate tint and size,
  -- because the first reading of this was the real problem: the powder
  -- fires (45 alive at the peak, measured) and cannot be SEEN -- it is
  -- near-white at 0.62 alpha over a near-white field, which is no contrast
  -- at all. The same trap as the rain's additive light over white paving.
  local function walkShot(name)
    -- LEFT and RIGHT, not up and down. The camera looks over the walker's
    -- shoulder, so powder thrown off a boot on a northward walk comes up
    -- behind the body and the frame shows none of it; walking across the
    -- shot puts the plume beside them where it can be seen.
    local dirs = { "left", "right" }
    local taken = false
    for k = 1, 2 do
      local dir = dirs[k]
      for f = 1, 70 do
        game.input.state[dir] = true
        coroutine.yield()
        local live, bursts = snowMotes()
        if live > peakKick then peakKick = live end
        if bursts > peakBurst then peakBurst = bursts end
        -- on a BURST, not on any snow mote: the clip is the thing being
        -- judged and it lives half a second, so a frame chosen by the
        -- grain count is a frame of the grains
        if not taken and f > 20 and bursts >= 2 then
          game.input.state[dir] = false
          shot(name)
          taken = true
          game.input.state[dir] = true
        end
      end
      game.input.state[dir] = false
    end
    game.input:reset()
    if not taken then shot(name) end
  end

  -- candidate powders: today's, and two that give the airborne snow a
  -- shaded underside to read against the ground it came out of
  local powders = {
    { "a_old",   { 0.95, 0.97, 1.00 }, 1.35 },
    { "b_now",   StepFX.SNOW, StepFX.SNOW_SIZE },
  }
  for _, w in ipairs(powders) do
    StepFX.SNOW, StepFX.SNOW_SIZE = w[2], w[3]
    wait(20)
    walkShot(("snowon_W_%s.png"):format(w[1]))
  end
  log(("walk: StepFX emitted +%d | snow motes alive, peak %d (bursts %d)"
       .. " | shed +%d clumps")
      :format(StepFX.emitted - emitted0, peakKick, peakBurst,
              SnowOnFX.sheds - sheds0))
  wait(60)

  -- ------- verdicts
  log("")
  if old.coatDraws == 0 then
    log("INCONCLUSIVE: the OLD arm painted nothing either -- was it snowing?")
  elseif stat.coatDraws > 0 then
    log(("FAIL: the paint is STILL ON -- coat>0 on %d draws (max %.2f) with"
         .. " SnowOnFX.PAINT false"):format(stat.coatDraws, stat.maxCoat))
  else
    log(("PASS: the snow is off the drawing -- coat>0 on %d draws in the old"
         .. " arm, 0 in the new"):format(old.coatDraws))
  end

  do
    local playerSheet = p.sprite and p.sprite.def and p.sprite.def.image
    local names, onPlayer, others = {}, false, 0
    for sheet in pairs(capSheets) do
      names[#names + 1] = sheet:match("[^/]+$") or sheet
      if sheet == playerSheet then onPlayer = true else others = others + 1 end
    end
    table.sort(names)
    log("cap asked for: " .. (next(names) and table.concat(names, " ") or "nobody"))
    if solid then
      if onPlayer then
        log("FAIL: the player wears a card's cap while a 3D mod is drawing"
            .. " their body -- sprite-shaped snow on a shape that is gone")
      elseif others > 0 then
        log(("PASS: nothing on the bodies the 3D mod replaced, and the %d"
             .. " sheets that still draw as cards keep their cap")
            :format(others))
      else
        log("INCONCLUSIVE: nothing wore a cap at all -- was any roamer out?")
      end
    end
  end

  if solid then
    -- the count verdict belongs to the card path; above is the solid one
  elseif stat.capDraws > 0 then
    log(("PASS: the cap draws -- %d quads reached Voxel3D.draw (%d built)")
        :format(stat.capDraws, capBuilds))
  else
    log(("FAIL: no cap reached the draw (built %d, nil %d, capOf(player) %.2f)")
        :format(capBuilds, capNil, SnowOnFX.capOf(p)))
  end

  if peakBurst > 0 then
    log(("PASS: the boots throw snow up -- %d motes at the peak, %d of them"
         .. " the powder clip"):format(peakKick, peakBurst))
  elseif peakKick > 0 then
    log(("FAIL: %d motes but not one BURST -- the clip is not being emitted"
         .. " (is assets/vfx/snow_burst.png installed?)"):format(peakKick))
  else
    log("FAIL: walking through the drift threw nothing up")
  end

  if lo and hi and hi > lo then
    log(("PASS: the cap follows each sprite -- tops span %d..%d px"):format(lo, hi))
  elseif lo then
    log(("INCONCLUSIVE: every sprite on this map tops out at %d px"):format(lo))
  else
    log("FAIL: no sprite profile could be read at all")
  end

  if solid then
    log(("shed on the solid path: %d clumps -- the roamers' own, the bodies"
         .. " the mod replaced wear nothing to drop")
        :format(SnowOnFX.sheds - sheds0))
  elseif SnowOnFX.sheds - sheds0 > 0 then
    log(("PASS: figures shed snow (%d clumps)"):format(SnowOnFX.sheds - sheds0))
  else
    log("FAIL: nothing was shed while capped and walking")
  end
  if SnowOnFX.lastError then log("  SnowOnFX error:", SnowOnFX.lastError) end

  Weather.setting:sync("off")
  log("done")
  logf:close()
  love.event.quit()
end
