-- Run in the PC build via POKEPORT_DRIVER; saves real menu/card screenshots.
return function(game)
  local out = assert(os.getenv("DS_PROBE_DIR"))
  local log = assert(io.open(out .. "/gen1_ui.log", "w"))
  local function check(ok, label)
    log:write((ok and "PASS " or "FAIL ") .. label .. "\n"); log:flush()
    assert(ok, label)
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b) game.input.pressQueue[#game.input.pressQueue + 1] = b; wait(1) end
  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      local f = assert(io.open(out .. "/" .. name .. ".png", "wb"))
      f:write(data:encode("png"):getString()); f:close(); done = true
    end)
    for _ = 1, 90 do if done then return end; wait(1) end
    check(false, "screenshot callback")
  end
  for _ = 1, 900 do
    if game.overworld and game.stack and game.stack:top() then break end
    wait(1)
  end
  for _ = 1, 150 do
    if game.stack:top() == game.overworld then break end
    tap("a"); wait(10)
  end
  local V = game.mods.exports.TERRARIUM.lib
  local Hud, Fan = V.require("BattleHudXY"), V.require("BattleFanXY")
  local Dyn = V.require("BattleDynamic")
  Dyn.setting:sync("dynamic"); Dyn.apply()
  V.require("DayNight").setting:sync("day")
  V.require("Weather").setting:sync("off")
  local battle = require("src.battle.BattleState").newWild(game, "SNORLAX", 35)
  check(battle and not battle.dead, "wild battle created")
  game.overworld:pushBattle(battle)
  for _ = 1, 120 do
    if battle.phase == "menu" then break end
    tap("a"); wait(10)
  end
  check(battle.phase == "menu", "command menu")
  wait(60); shot("menu")
  battle.menuIndex = 1; tap("a"); wait(80)
  check(battle.phase == "moveSelect", "attack selection")
  check(Fan.debug() and Fan.debug().n == #battle.player.curMoves, "all attack cards drawn")
  shot("attacks")
  local old = battle.moveIndex
  tap("right"); wait(50)
  check(battle.moveIndex ~= old, "directional card selection")
  shot("attacks_selected")
  -- Inspect the same render function used by the live fan, without a test API.
  local face
  for i = 1, 80 do
    local name, value = debug.getupvalue(Fan.draw, i)
    if not name then break end
    if name == "drawFace" then face = value; break end
  end
  check(type(face) == "function", "live card renderer found")
  local animate
  for i = 1,80 do
    local name,value = debug.getupvalue(Fan.draw,i)
    if not name then break end
    if name == "animateFace" then animate=value; break end
  end
  check(type(animate) == "function", "live animation compositor found")
  local mv = battle.player.curMoves[1]
  local def = battle.data.moves[mv.id]
  local clock = love.timer.getTime
  local animationOk, animationErr = pcall(function()
    for _, kind in ipairs({"ELECTRIC","WATER","FIRE","GRASS","ICE","GHOST",
      "POISON","PSYCHIC","DRAGON","ROCK","GROUND","FIGHTING","FLYING","NORMAL","BUG"}) do
      local slot = {}
      face(slot,mv,def,true,false,false,3,false)
      local base = slot.canvas:newImageData()
      local first, changed = nil,false
      for frame=1,12 do
        love.timer.getTime = function() return 100+frame*0.45 end
        local canvas = animate(slot,"test:"..kind,kind,0.85,false)
        local data = canvas:newImageData()
        for _, point in ipairs({{50,110},{100,181},{50,260},{200,270},{200,330},{150,358}}) do
          local a,b = {data:getPixel(point[1],point[2])},{base:getPixel(point[1],point[2])}
          for channel=1,4 do assert(a[channel]==b[channel],kind.." obscured reading band") end
        end
        local bytes = data:encode("png"):getString()
        if first and first ~= bytes then changed=true end
        first=first or bytes
        if frame==5 then
          local f=assert(io.open(out.."/animated_"..kind..".png","wb"))
          f:write(bytes);f:close()
        end
      end
      check(changed,"animated and readable "..kind)
      check(animate(slot,"test:"..kind,kind,0.85,true)==slot.canvas,"disabled animation "..kind)
    end
  end)
  love.timer.getTime = clock
  check(animationOk,tostring(animationErr or "all animation frames verified"))
  for _, state in ipairs({"normal", "selected", "disabled", "charge", "empty", "low"}) do
    local slot = {}
    local sample = {}
    for k, v in pairs(mv) do sample[k] = v end
    if state == "empty" then sample.pp = 0 end
    if state == "low" then sample.pp = 1 end
    check(face(slot, sample, def, state == "selected", false,
      state == "disabled", 3, state == "charge"), "card state " .. state)
    if state == "empty" or state == "low" or state == "disabled" then
      check(slot.ppState == state, "PP state " .. state)
    end
    local f = assert(io.open(out .. "/card_" .. state .. ".png", "wb"))
    f:write(slot.canvas:newImageData():encode("png"):getString()); f:close()
  end
  local cv = love.graphics.newCanvas(960, 480)
  local previous = love.graphics.getCanvas()
  love.graphics.setCanvas(cv); love.graphics.clear(0.22, 0.27, 0.26, 1)
  for i, hp in ipairs({121, 60, 12, 0}) do
    check(Hud.block({name="BLASTOISE",level=38,hp=hp,maxHP=121,
      isPlayer=true,charge=i,chargeMax=5}, 20 + ((i-1)%2)*470,
      30 + math.floor((i-1)/2)*220, 440, 0.65), "HUD health " .. hp)
  end
  love.graphics.setCanvas(previous)
  local f = assert(io.open(out .. "/hud_states.png", "wb"))
  f:write(cv:newImageData():encode("png"):getString()); f:close()
  tap("b"); wait(50)
  check(battle.phase == "menu", "back to menu")
  battle.menuIndex = 1; tap("a"); wait(30)
  tap("a"); wait(10)
  check(battle.phase ~= "moveSelect", "selected attack accepted")
  shot("attack_message")
  log:close(); love.event.quit()
end
