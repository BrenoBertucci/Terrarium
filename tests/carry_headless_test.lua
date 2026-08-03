package.path = "eng/?.lua;" .. package.path
local Data = { constants = { bagSize = 20 } }
package.loaded["src.core.Data"] = Data
local Bag = require("src.inventory.Bag")

local V = { mod = { id="DS" } }
local settings = {}
V.require = function(n)
  if n == "ModSetting" then
    return { new = function(key, label, values)
      settings[key] = { value = values[1] }
      return { get = function() return settings[key].value end,
               row = function() return {} end }
    end }
  end
end
-- Resolved from this file's own location rather than from an absolute path.
-- It was hardcoded to one machine's home directory, which both leaked a
-- username into the repository and meant the test could only ever run for the
-- person who wrote it. `...` is the chunk name LOVE/Lua hands a script, so
-- this works from any working directory and in any clone.
local HERE = (debug.getinfo(1, "S").source:match("^@(.*)[/\\]") or ".")
local Carry = assert(loadfile(HERE .. "/../lib/Carry.lua"))(V)

local function fresh() return { inventory = {}, bagOrder = {} } end
local function pass(c,m) print((c and "PASS  " or "FAIL  ")..m) end

-- vanilla first
settings.bag.value, settings.stack.value = "20", "99"
Carry.update()
pass(Bag.capacity(Data) == 20, "vanilla: capacity 20")
local s = fresh()
for i=1,20 do Bag.add(s,"ITEM"..i,1) end
pass(Bag.add(s,"ITEM21",1) == false, "vanilla: 21st distinct item refused")
s = fresh(); Bag.add(s,"POTION",99)
pass(Bag.add(s,"POTION",1) == false, "vanilla: stack past 99 refused")

Carry.install()
pass(Bag.dramaticShapeCarryHook == true, "install: hook set")
pass(Carry.install() == true, "install: idempotent")

-- vanilla behaviour must SURVIVE the wrap
settings.bag.value, settings.stack.value = "20", "99"
Carry.update()
s = fresh(); for i=1,20 do Bag.add(s,"ITEM"..i,1) end
pass(Bag.add(s,"ITEM21",1) == false, "wrapped+vanilla: 21st still refused")
s = fresh(); Bag.add(s,"POTION",99)
pass(Bag.add(s,"POTION",1) == false, "wrapped+vanilla: stack past 99 still refused")

-- MAX slots
settings.bag.value = "max"; Carry.update()
pass(Bag.capacity(Data) == 999, "MAX: capacity 999")
s = fresh(); local okAll = true
for i=1,150 do if not Bag.add(s,"ITEM"..i,1) then okAll=false end end
pass(okAll and Bag.slots(s)==150, "MAX: 150 distinct items fit (slots="..Bag.slots(s)..")")
Bag.order(s)  -- engine self-heals its own trailing duplicate here
pass(#s.bagOrder == 150, "MAX: bagOrder tracked all 150")

-- MAX stack
settings.stack.value = "max"
s = fresh(); Bag.add(s,"POTION",99)
local ok=true; for i=1,50 do if not Bag.add(s,"POTION",50) then ok=false end end
pass(ok and s.inventory.POTION==2599, "MAXstack: pile grew to "..tostring(s.inventory.POTION))
pass(Bag.add(s,"POTION",9000) == false, "MAXstack: refused past 9999 cap")

-- 255 rung
settings.stack.value = "255"
s = fresh(); Bag.add(s,"POTION",99); Bag.add(s,"POTION",99); Bag.add(s,"POTION",57)
pass(s.inventory.POTION == 255, "255: reached exactly 255")
pass(Bag.add(s,"POTION",1) == false, "255: refused past 255")

-- badges must never be touched
settings.stack.value = "max"
s = fresh(); Bag.add(s,"BOULDERBADGE",1)
pass(s.inventory.BOULDERBADGE==1 and #s.bagOrder==0, "badge: not a bag slot")

-- full bag + raised stack: a NEW item must still be refused
settings.bag.value = "20"; settings.stack.value = "max"; Carry.update()
s = fresh(); for i=1,20 do Bag.add(s,"ITEM"..i,1) end
pass(Bag.add(s,"NEWITEM",1) == false, "full bag + MAX stack: new item still refused")
pass(Bag.add(s,"ITEM1",500) == true and s.inventory.ITEM1==501, "full bag: existing stack still grows")
