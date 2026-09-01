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
function V.require(n)
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
expect(BattleScreenXY.POCKET_LABEL.items, "ITENS", "label ITENS")
expect(BattleScreenXY.POCKET_LABEL.cura, "CURA", "label CURA")
expect(BattleScreenXY.POCKET_LABEL.balls, "BOLAS", "label BOLAS")
expect(BattleScreenXY.POCKET_LABEL.tm, "TM/HM", "label TM/HM")
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
