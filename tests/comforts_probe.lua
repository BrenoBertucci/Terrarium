-- Probe: the four conveniences of 1.14.0, plus the puddles' own reflection.
--
--    9  EXP for the team    who gets paid and with what divisor, asked of
--                           the decision itself with a recording applyShare,
--                           so the answer is a table of numbers rather than
--                           a feeling about a battle
--   10  the box             boxes filled to capacity on purpose, then a
--                           catch and a PC open against them
--   11  the bag             a deliberately scrambled inventory sorted, and
--                           the pockets checked for being contiguous and in
--                           order
--   12  rename              the submenu hook asked for its list, then the
--                           naming screen actually driven to a new name
--   RT  the puddle          the constants the two files must agree on, the
--                           three size steps, and a shot of a reflecting
--                           pool with the sky in it
--
--   POKEPORT_VERSION=yellow \
--   DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/DRAMATIC_SHAPE/tests/comforts_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/comforts_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n")
    logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(btn)
    game.input.pressQueue[#game.input.pressQueue + 1] = btn
    coroutine.yield()
  end
  local function shot(name)
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
    wait(3)
  end

  love.math.setRandomSeed(20260802)

  local frames = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); frames = frames + 1
    if frames > 900 then log("FAIL: no overworld") logf:close()
      love.event.quit() return end
  end
  frames = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); frames = frames + 11
    if frames > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.DRAMATIC_SHAPE and exports.DRAMATIC_SHAPE.lib
  if not lib then
    log("FAIL: DRAMATIC_SHAPE not loaded"); logf:close(); love.event.quit()
    return
  end
  log("version:", exports.DRAMATIC_SHAPE.version)

  local ExpShare = lib.require("ExpShare")
  local Comforts = lib.require("Comforts")
  local GroundFX = lib.require("GroundFX")
  local RayFX = lib.require("RayFX")
  local Voxel3D = lib.require("Voxel3D")
  local QoL = lib.require("QoL")
  local Weather = lib.require("Weather")
  local DayNight = lib.require("DayNight")
  local WorldCurve = lib.require("WorldCurve")
  local Pipelines = require("src.render.Pipelines")
  local Runtime = require("src.mods.Runtime")

  QoL.setting:sync("on")

  -- =====================================================================
  log("")
  log("== 9. EXP for the whole team ==")

  log("engine offers battle.exp_award:",
      tostring(Runtime.wantsHook("battle.exp_award")))
  if not Runtime.wantsHook("battle.exp_award") then
    log("  FAIL: nothing wrapped the award")
  end

  -- a party of four: two that fought, one that did not, one fainted
  local Pokemon = require("src.pokemon.Pokemon")
  local function mk(species, level, hp)
    local mon = Pokemon.new(game.data, species, level)
    mon.hp = hp
    return mon
  end
  game.save.party = { mk("PIKACHU", 10, 20), mk("PIDGEY", 8, 15),
                      mk("RATTATA", 6, 12), mk("CATERPIE", 5, 0) }
  local party = game.save.party

  local function awardWith(mode)
    ExpShare.setting:sync(mode)
    local seen = {}
    local ctx = {
      participants = 1,
      alive = { party[1] },          -- only PIKACHU fought
      applyShare = function(mon, split, announce)
        seen[#seen + 1] = { mon = mon, split = split, announce = announce }
      end,
    }
    local vanillaRan = false
    ExpShare.award(function() vanillaRan = true end, ctx)
    return seen, vanillaRan
  end

  local function nameOf(mon)
    return mon.nickname or game.data.pokemon[mon.species].name
  end

  for _, mode in ipairs({ "team", "split", "off" }) do
    local seen, vanilla = awardWith(mode)
    if mode == "off" then
      log(("%-5s -> vanilla ran: %s, own payments: %d"):format(
        mode, tostring(vanilla), #seen))
      if not vanilla then log("  FAIL: OFF did not fall through") end
      if #seen > 0 then log("  FAIL: OFF paid somebody itself") end
    else
      local parts = {}
      for _, p in ipairs(seen) do
        parts[#parts + 1] = ("%s/%d%s"):format(nameOf(p.mon), p.split,
                                               p.announce and "*" or "")
      end
      log(("%-5s -> %d paid: %s   (* = says so on screen)"):format(
        mode, #seen, table.concat(parts, " ")))
      if #seen ~= 3 then
        log("  FAIL: expected the three standing mons, got " .. #seen)
      end
      local announced = 0
      for _, p in ipairs(seen) do if p.announce then announced = announced + 1 end end
      if announced ~= 1 then
        log("  FAIL: " .. announced .. " text boxes; only the fighter should talk")
      end
      for _, p in ipairs(seen) do
        if p.mon.hp <= 0 then log("  FAIL: a fainted mon was paid") end
      end
    end
  end
  do
    local team = select(1, awardWith("team"))
    local split = select(1, awardWith("split"))
    log(("divisor: TEAM %d vs SPLIT %d (SPLIT should be 3x on a party of 3)")
        :format(team[1].split, split[1].split))
    if split[1].split ~= team[1].split * 3 then
      log("  FAIL: SPLIT is not the total shared out")
    end
  end
  ExpShare.setting:sync("team")

  -- =====================================================================
  log("")
  log("== 10. the box that fills up ==")

  local Boxes = require("src.pokemon.Boxes")
  local boxes = Boxes.ensure(game.save)
  for i = 1, Boxes.COUNT do boxes[i] = {} end
  game.save.currentBox = 1
  for _ = 1, Boxes.CAPACITY do
    table.insert(boxes[1], mk("RATTATA", 3, 10))
  end
  log(("box 1 filled: %d/%d, current=%d"):format(
    #boxes[1], Boxes.CAPACITY, game.save.currentBox))
  log("next box with room:", tostring(Comforts.nextRoomyBox(game.save)))
  if Comforts.nextRoomyBox(game.save) ~= 2 then
    log("  FAIL: did not roll forward to box 2")
  end

  -- a catch with a full party and a full box 1
  local caught = mk("PIDGEY", 4, 12)
  local landed = Boxes.deposit(game.save, caught)
  Comforts.onCaught({ destination = "box", mon = caught })
  log(("caught -> box %s; the PC now opens on box %d"):format(
    tostring(landed), game.save.currentBox))
  if game.save.currentBox ~= landed then
    log("  FAIL: the current box did not follow the catch")
  end

  -- and the PC's own deposit, which refuses on a full box
  game.save.currentBox = 1
  local BoxMenu = require("src.ui.BoxMenu")
  local pc = BoxMenu.new(game)
  log(("PC opened with box 1 full -> current=%d"):format(game.save.currentBox))
  if game.save.currentBox == 1 then
    log("  FAIL: the PC still opened on the full box")
  end
  if pc and game.stack and game.stack:top() == pc then game.stack:pop() end

  -- and it leaves a box with room alone
  game.save.currentBox = 3
  BoxMenu.new(game)
  log(("PC opened with box 3 empty -> current=%d (want 3)"):format(
    game.save.currentBox))
  if game.save.currentBox ~= 3 then
    log("  FAIL: it moved off a box that had room")
  end
  while game.stack:top() ~= game.overworld do game.stack:pop() end
  for i = 1, Boxes.COUNT do boxes[i] = {} end
  game.save.currentBox = 1

  -- =====================================================================
  log("")
  log("== 11. the bag, in pockets ==")

  local Bag = require("src.inventory.Bag")
  game.save.inventory = {}
  game.save.bagOrder = nil
  for _, id in ipairs({ "TM_01", "POTION", "BICYCLE", "ULTRA_BALL", "ANTIDOTE",
                        "HM_01", "NUGGET", "POKE_BALL", "FULL_RESTORE",
                        "SUPER_POTION", "TM_50", "GREAT_BALL", "SS_TICKET" }) do
    if game.data.items[id] then
      game.save.inventory[id] = 1
      local order = Bag.order(game.save)
      order[#order + 1] = id
    end
  end
  local before = {}
  for _, id in ipairs(Bag.order(game.save)) do before[#before + 1] = id end
  log("before: " .. table.concat(before, " "))
  Comforts.sortBag(game.save, game.data)
  local after = Bag.order(game.save)
  local line, pockets = {}, {}
  for _, id in ipairs(after) do
    local p = Comforts.pocketOf(id, game.data.items[id])
    line[#line + 1] = ("%s(%d)"):format(id, p)
    pockets[#pockets + 1] = p
  end
  log("after:  " .. table.concat(line, " "))
  local ordered = true
  for i = 2, #pockets do
    if pockets[i] < pockets[i - 1] then ordered = false end
  end
  log("pockets contiguous and in order:", tostring(ordered))
  if not ordered then log("  FAIL: the pockets are interleaved") end

  -- the navigation the engine's own hook grants, asked the way the bag asks
  local opts = Runtime.call("ui.list_menu", function(o) return o end,
                            { wrap = nil, pageJump = nil, keyRepeat = nil },
                            { game = game, kind = "bag", itemCount = #after })
  log(("bag list: wrap=%s pageJump=%s keyRepeat=%s"):format(
    tostring(opts.wrap), tostring(opts.pageJump), tostring(opts.keyRepeat)))
  if not (opts.wrap and opts.pageJump and opts.keyRepeat) then
    log("  FAIL: the bag did not get its navigation")
  end
  local other = Runtime.call("ui.list_menu", function(o) return o end,
                             { wrap = nil }, { game = game, kind = "shop" })
  log("a SHOP list is left alone:", tostring(other.wrap == nil))
  if other.wrap ~= nil then log("  FAIL: it reached a list that is not the bag") end

  -- =====================================================================
  log("")
  log("== 12. rename, whenever you like ==")

  local mon = party[1]
  local items = Runtime.call("ui.party.submenu", function(_, it) return it end,
                             game,
                             { { label = "STATS", action = "stats" },
                               { label = "SWITCH", action = "switch" } },
                             mon, { battle = nil, overworld = game.overworld })
  local labels, renameEntry = {}, nil
  for _, it in ipairs(items) do
    labels[#labels + 1] = it.label
    if it.label == "RENAME" then renameEntry = it end
  end
  log("party submenu: " .. table.concat(labels, " / "))
  if not renameEntry then log("  FAIL: no RENAME on the submenu") end
  if renameEntry and not renameEntry.onSelect then
    log("  FAIL: RENAME carries no onSelect for the dispatcher")
  end

  -- and in a BATTLE it stays away
  local inBattle = Runtime.call("ui.party.submenu", function(_, it) return it end,
                                game, { { label = "SWITCH", action = "battle_switch" } },
                                mon, { battle = {}, overworld = nil })
  local hasRename = false
  for _, it in ipairs(inBattle) do
    if it.label == "RENAME" then hasRename = true end
  end
  log("offered mid-battle:", tostring(hasRename), "(want false)")
  if hasRename then log("  FAIL: RENAME reached the battle party menu") end

  -- now actually drive it
  if renameEntry then
    log("before:", tostring(mon.nickname))
    renameEntry.onSelect(mon, game)
    wait(6)
    local screen = game.stack:top()
    log("naming screen is up:", tostring(screen ~= game.overworld))
    shot("50_rename_screen.png")
    -- typed through the screen's own confirm rather than by assignment,
    -- so the path a player takes is the path measured
    if screen and screen.glyphs then
      screen.glyphs = { "S", "P", "A", "R", "K", "Y" }
      screen:confirm()
      wait(6)
    end
    log("after: ", tostring(mon.nickname))
    if mon.nickname ~= "SPARKY" then log("  FAIL: the rename did not take") end
    -- and clearing it puts the species back
    renameEntry.onSelect(mon, game)
    wait(6)
    local s2 = game.stack:top()
    if s2 and s2.glyphs then s2.glyphs = {}; s2:confirm(); wait(6) end
    log("cleared ->", tostring(mon.nickname), "(want nil)")
    if mon.nickname ~= nil then log("  FAIL: clearing did not restore the species") end
  end
  while game.stack:top() ~= game.overworld do game.stack:pop() end

  -- =====================================================================
  log("")
  log("== RT: the puddle reflects, and grows ==")

  -- A puddle is identified by the MARK the ground row stamps into the scene
  -- buffer's alpha, not by the height it floats at -- so what has to agree
  -- is the tag, and the float heights are free to be whatever wins the depth
  -- test. (They used to have to be spread across the fraction window; see
  -- GroundFX.PUDDLE for that history and why it is over.)
  log(("puddle tag: stamped %.6f, read %.6f +/- %.4f"):format(
    Voxel3D.PUDDLE_TAG, RayFX.PUDDLE_TAG, RayFX.PUDDLE_TAG_W))
  if math.abs(Voxel3D.PUDDLE_TAG - RayFX.PUDDLE_TAG) > 1e-6 then
    log("  FAIL: the two files disagree, so no puddle can ever reflect")
  end
  if RayFX.PUDDLE_TAG_W >= (1 - RayFX.PUDDLE_TAG) then
    log("  FAIL: the tag window reaches opaque geometry -- everything on "
        .. "screen would reflect")
  end
  log(("puddles float at %.2f, drifts at %.2f, prints at %.2f")
      :format(GroundFX.PUDDLE, GroundFX.DRIFT, GroundFX.PRINT))

  for _, a in ipairs({ 0.0, 0.2, 0.34, 0.5, 0.67, 0.9, 1.0 }) do
    log(("amount %.2f -> size step %d of %d"):format(
      a, GroundFX.step(a), GroundFX.STEPS))
  end

  GroundFX.setting:sync("on")
  RayFX.setting:sync("max")
  WorldCurve.setting:sync(3)
  DayNight.setting:sync("day")
  Pipelines.setLevel("voxel", 5)
  -- slow enough that the three size steps are three different moments,
  -- fast enough that the probe is not a coffee break
  GroundFX.SOAK, GroundFX.DRY = 22, 6

  -- a paved spot with room, found rather than written down
  game.overworld:setMap("VIRIDIAN_CITY", 5, 5, "down")
  wait(60)
  local m = game.overworld.map
  local bx, by, best = 10, 10, -1
  for cy = 2, (m.height or 20) - 3 do
    for cx = 2, (m.width or 20) - 3 do
      if m:isWalkableCell(cx, cy) and not m:isGrassCell(cx, cy)
         and not m:isWaterCell(cx, cy) and not m:warpAtCell(cx, cy) then
        local n = 0
        for dy = -2, 2 do for dx = -2, 2 do
          if m:inBounds(cx + dx, cy + dy) and m:isWalkableCell(cx + dx, cy + dy)
             and not m:isGrassCell(cx + dx, cy + dy) then n = n + 1 end
        end end
        if n > best then bx, by, best = cx, cy, n end
      end
    end
  end
  game.overworld:setMap("VIRIDIAN_CITY", bx, by, "down")
  wait(150)

  -- DRAINED FIRST, and the sky switched off to do it. The earlier sections
  -- take minutes of game time with the WEATHER row at AUTO, so by the time
  -- this runs it has usually rained already -- the first run's three "steps"
  -- were all step three, because the ground was at 0.79 before the shower
  -- was even asked for.
  Weather.setting:sync("off")
  local drained = 0
  while GroundFX.wetness() > 0.02 and drained < 3000 do
    wait(20); drained = drained + 20
  end
  log(("drained to wet=%.2f in %d frames"):format(GroundFX.wetness(), drained))
  wait(120)
  shot("51_dry.png")

  local function amount()
    return math.max(0, (GroundFX.wetness() - GroundFX.PUDDLE_FROM)
                       / (1 - GroundFX.PUDDLE_FROM))
  end

  Weather.setting:sync("rain")
  local steps = {}
  for want = 1, GroundFX.STEPS do
    local spun = 0
    while (amount() <= 0 or GroundFX.step(amount()) < want) and spun < 4000 do
      wait(10); spun = spun + 10
    end
    local tag = ("5%d_puddle_step%d"):format(want + 1, want)
    steps[want] = GroundFX.wetness()
    log(("%s: wet=%.2f step=%d draws=%d"):format(
      tag, GroundFX.wetness(), GroundFX.step(amount()), GroundFX.lastDraws))
    shot(tag .. ".png")
  end
  if GroundFX.lastDraws == 0 then log("  FAIL: no puddle meshes drawn") end
  if steps[3] and steps[1] and steps[3] - steps[1] < 0.3 then
    log("  FAIL: the three shots are all the same moment")
  end

  -- ------- and the reflection itself, which is the claim
  --
  -- A/B at the same spot on the same frame's worth of rain, because a
  -- puddle reflecting a grey sky and a puddle not reflecting anything are
  -- the same picture until you have both.
  RayFX.setting:sync("off")
  wait(60)
  shot("55_puddle_RTX_OFF.png")
  RayFX.setting:sync("max")
  wait(60)
  shot("56_puddle_RTX_MAX.png")
  log("RTX A/B shot at wet=" .. ("%.2f"):format(GroundFX.wetness()))

  log("")
  log("done -- " .. OUT)
  logf:close()
  love.event.quit()
end
