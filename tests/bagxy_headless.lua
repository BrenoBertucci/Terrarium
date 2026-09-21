-- Headless: bag symbols and hop timing still exist.
--
-- loadfiles BattleScreenXY / BattleNav with a stub V. Does not blit and
-- does not need love.graphics. Run from the Terrarium root:
--   lua tests/bagxy_headless.lua
-- or the engine's lua.exe, same way as tests/carry_headless_test.lua.
local HERE = (debug.getinfo(1, "S").source:match("^@(.*)[/\\]") or ".")

love = love or {}
love.timer = love.timer or { getTime = function() return 0 end }

local V = {
  path = HERE .. "/..",
  mod = { log = { warn = function() end } },
}
local loaded = {}
function V.require(n)
  -- the real thing for these two: the pocket tabs pick their word through
  -- Lang, and a stub that always answers English would test the stub
  if n == "Lang" or n == "ModSetting" then
    if not loaded[n] then
      loaded[n] = assert(loadfile(HERE .. "/../lib/" .. n .. ".lua"))(V)
    end
    return loaded[n]
  end
  if n == "BattleHudXY" then
    return {
      available = function() return true end,
      textWidth = function(s) return #(tostring(s or "")) * 10 end,
      text = function() end,
    }
  end
  if n == "BattleBoxXY" then
    return {
      popScale = function() return 1 end,
      shadowText = function() end,
      _art = function() return nil end,
    }
  end
  error("unexpected require " .. tostring(n))
end

local fail = 0
local function expect(got, want, tag)
  if got == want then
    print("PASS  " .. tag)
  else
    fail = fail + 1
    print("FAIL  " .. tag .. " got=" .. tostring(got) .. " want=" .. tostring(want))
  end
end

local BattleScreenXY = assert(loadfile(HERE .. "/../lib/BattleScreenXY.lua"))(V)
expect(type(BattleScreenXY.drawBag), "function", "drawBag exists")
expect(type(BattleScreenXY.POCKET_ORDER), "table", "POCKET_ORDER exported")
expect(BattleScreenXY.POCKET_ORDER[1], "items", "pocket 1 items")
expect(BattleScreenXY.POCKET_ORDER[2], "cura", "pocket 2 cura")
expect(BattleScreenXY.POCKET_ORDER[3], "balls", "pocket 3 balls")
expect(BattleScreenXY.POCKET_ORDER[4], "tm", "pocket 4 tm")
expect(#BattleScreenXY.POCKET_ORDER, 4, "four pockets")
-- the pocket tabs, in both languages: English is the default (values[1] of
-- Lang.setting, and what an unread stored value falls back to), Portuguese
-- is one sync away. The four keys are internal and never change.
local Lang = V.require("Lang")
expect(Lang.get(), "en", "language defaults to en")
expect(BattleScreenXY.pocketLabel("items"), "ITEMS", "EN label ITEMS")
expect(BattleScreenXY.pocketLabel("cura"), "MEDICINE", "EN label MEDICINE")
expect(BattleScreenXY.pocketLabel("balls"), "BALLS", "EN label BALLS")
expect(BattleScreenXY.pocketLabel("tm"), "TM/HM", "EN label TM/HM")
Lang.setting:sync("pt")
expect(BattleScreenXY.pocketLabel("items"), "ITENS", "PT label ITENS")
expect(BattleScreenXY.pocketLabel("cura"), "CURA", "PT label CURA")
expect(BattleScreenXY.pocketLabel("balls"), "BOLAS", "PT label BOLAS")
expect(BattleScreenXY.pocketLabel("tm"), "TM/HM", "PT label TM/HM")

-- the battle command buttons read their word the same way, and every
-- reader of COMMANDS[i].label must CALL it -- a string there is what broke
-- three draw sites the first time this row was wired
local BattleBoxXY = assert(loadfile(HERE .. "/../lib/BattleBoxXY.lua"))(V)
expect(type(BattleBoxXY.COMMANDS[1].label), "function", "label is a function")
expect(BattleBoxXY.COMMANDS[2].label(), "TROCAR", "PT switch says TROCAR")
expect(BattleBoxXY.COMMANDS[4].label(), "FUGIR", "PT run says FUGIR")
Lang.setting:sync("en")
expect(BattleBoxXY.COMMANDS[1].label(), "ATTACK", "EN fight says ATTACK")
expect(BattleBoxXY.COMMANDS[2].label(), "SWITCH", "EN pkmn says SWITCH")
expect(BattleBoxXY.COMMANDS[3].label(), "ITEMS", "EN bag says ITEMS")
expect(BattleBoxXY.COMMANDS[4].label(), "FLEE", "EN run says FLEE")

local StartMenuMap = assert(loadfile(HERE .. "/../lib/StartMenuMap.lua"))(V)
expect(StartMenuMap.label(), "MAP", "EN map row says MAP")
Lang.setting:sync("pt")
expect(StartMenuMap.label(), "MAPA", "PT map row says MAPA")
Lang.setting:sync("en")
expect(type(BattleScreenXY.BAG_GOLD), "table", "BAG_GOLD")

local BattleNav = assert(loadfile(HERE .. "/../lib/BattleNav.lua"))(V)
local hopTime = tonumber(BattleNav.HOP_TIME) or 0
if hopTime == 0.22 then
  print("PASS  HOP_TIME 0.22")
else
  fail = fail + 1
  print("FAIL  HOP_TIME " .. tostring(hopTime))
end
expect(type(BattleNav.draw), "function", "BattleNav.draw")
expect(type(BattleNav.pin), "function", "BattleNav.pin")
expect(type(BattleScreenXY.tick), "function", "tick exists")

-- draw() pcall path still returns boolean (stubs, no real blit)
love.graphics = love.graphics or {}
love.graphics.push = love.graphics.push or function() end
love.graphics.pop = love.graphics.pop or function() end
love.graphics.setColor = love.graphics.setColor or function() end
love.graphics.rectangle = love.graphics.rectangle or function() end
love.graphics.setLineWidth = love.graphics.setLineWidth or function() end
love.graphics.getBlendMode = love.graphics.getBlendMode or function() return "alpha" end
love.graphics.setBlendMode = love.graphics.setBlendMode or function(mode, alphamode)
  if alphamode == nil then
    return
  end
end
love.graphics.draw = love.graphics.draw or function() end
love.graphics.newQuad = love.graphics.newQuad or function()
  error("newQuad should be cached / pcalled")
end

local emptyGame = { stack = { top = function() return nil end } }
local shot = { scale = 4, lx = 0, ly = 0, pw = 640, ph = 480 }
local r0 = BattleScreenXY.draw(emptyGame, {}, shot)
expect(type(r0), "boolean", "draw() pcall path returns boolean")
expect(r0, false, "draw() no screen is false")

local bag = {
  items = { { value = "POTION", label = "POTION", right = 1 } },
  index = 1,
  scroll = 0,
  onSelectKey = function() end,
  footer = "$0",
  title = "ITEMS",
}
local bagGame = {
  stack = { top = function() return bag end },
  data = { items = {} },
  input = { wasPressed = function() return false end },
}
local r1 = BattleScreenXY.draw(bagGame, {}, shot)
expect(type(r1), "boolean", "draw(bag) returns boolean")
expect(r1, true, "draw(bag) succeeds or falls back")
local inst = BattleScreenXY.tick(bagGame)
expect(inst, true, "tick installs bag")

local tiny = { scale = 1, lx = 0, ly = 0, pw = 160, ph = 144 }
local r2 = BattleScreenXY.draw(bagGame, {}, tiny)
expect(type(r2), "boolean", "draw(tiny) returns boolean")

if fail == 0 then print("PASS") else print("FAIL count=" .. fail) os.exit(1) end
