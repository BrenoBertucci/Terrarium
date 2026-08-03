-- How much you can carry, on two rows.
--
-- Gen 1's bag holds twenty distinct items and ninety-nine of each, and both
-- numbers are the same kind of relic: they are what fit in the Game Boy's
-- save RAM, not a design decision anybody would make twice. Twenty slots is
-- the one that actually bites -- five HMs, a fistful of TMs, the fossils, the
-- Bike Voucher, the S.S. Ticket and the key items are most of it before a
-- single Potion goes in, and the game's answer is a trip to a PC.
--
-- ------- two limits, two rows, and they are enforced in different places
--
-- SLOTS is the number of distinct items. The engine exposes it: `Bag.capacity`
-- reads `Data.constants.bagSize` and falls back to twenty, and its own header
-- says in as many words that mods may replace the limit through it. So that
-- is what this does -- the documented front door, no wrap, nothing patched.
-- The same registry carries `partyMax`, `boxSize`, `levelCap` and `coinCap`
-- if any of those ever wants a row of its own.
--
-- STACK is how many of one thing. That one is NOT exposed: `Bag.add` tests
-- `> 99` inline, so it takes a wrap -- the same shape CityLife's `talkTo`
-- hook has, and with the same rule, which is that the engine's own answer is
-- asked FIRST and a yes is final. Only a NO gets a second look, and only when
-- the reason for it was the stack cap rather than a full bag.
--
-- ------- "unlimited" is a number, and this is honest about that
--
-- `bagSize` has to be a number, so MAX is not infinity -- it is 999, against
-- a game that ships about a hundred and ten distinct items. You cannot fill
-- it, which is the thing the row is promising, but the code does not pretend
-- to a limit it does not have. Same for the stack: MAX is 9999, which is four
-- digits because the bag menu draws a quantity as `"x" .. n` with no width,
-- and five would start pushing the item name.
--
-- ------- what this does NOT lift, because it is somewhere else
--
-- A single PURCHASE is still capped at ninety-nine (`ShopMenu` clamps it, and
-- the quantity selector is a two-digit box). With a raised stack you can buy
-- ninety-nine, walk out, walk back in and buy ninety-nine more -- the cap on
-- the pile is gone, the cap on one transaction is not. Lifting that means
-- rewriting the quantity box, which is a UI this mod has no business in.
--
-- Tossing has the same two-digit box, so a four-figure pile comes back down
-- ninety-nine at a time. That one is arguably a feature.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local Carry = {}

-- ------- the ladders
--
-- MAX leads both, because that is what these rows are for and a setting whose
-- default is "the limit you already had" is a setting nobody finds -- the
-- same argument the RTX row's default is made on. Cycling walks DOWN from
-- there through the vanilla number and back round, so the original behaviour
-- is always one stop away and is never something you have to go looking for.
Carry.setting = ModSetting.new("bag", "BAG",
                               { "max", "20", "50", "99" },
                               { "MAX", "20", "50", "99" })

Carry.stackSetting = ModSetting.new("stack", "STACK",
                                    { "max", "99", "255", "999" },
                                    { "MAX", "99", "255", "999" })

-- What each rung means as a number. MAX is a number too -- see the header.
local SLOTS = { max = 999, ["20"] = 20, ["50"] = 50, ["99"] = 99 }
local STACK = { max = 9999, ["99"] = 99, ["255"] = 255, ["999"] = 999 }

function Carry.row() return Carry.setting:row() end
function Carry.stackRow() return Carry.stackSetting:row() end

function Carry.slots()
  local ok, v = pcall(Carry.setting.get, Carry.setting)
  return (ok and SLOTS[v]) or SLOTS.max
end

function Carry.stackCap()
  local ok, v = pcall(Carry.stackSetting.get, Carry.stackSetting)
  return (ok and STACK[v]) or STACK.max
end

-- ------- the slots, through the constants registry
--
-- POLLED rather than pushed once, and for the reason main.lua's `voidFill`
-- is: the value can change from the OPTIONS row, from the mod manager's own
-- page and from applyOptions on a load, and none of those three announces
-- it. `Bag.capacity` reads the registry on every call, so keeping the
-- registry current is the whole of the job -- one integer compare a frame.
--
-- Writing a number the engine seeded itself, in the place it documented for
-- it. Nothing here is patched and nothing is saved: `Data.constants` is
-- rebuilt from the generated data on every boot, so a player who uninstalls
-- this mod gets twenty slots back with no migration and no stranded save.
local applied = nil

local function applySlots()
  local want = Carry.slots()
  if applied == want then return end
  local ok, Data = pcall(require, "src.core.Data")
  if not (ok and Data and Data.constants) then return end
  Data.constants.bagSize = want
  applied = want
end

-- ------- the stack, through a wrap
--
-- The engine is asked first and its YES is final -- so every rule it holds
-- that is not the stack cap (badges, a genuinely full bag, the order list)
-- still decides, and none of it is copied here to drift out of date.
--
-- A NO is re-examined exactly once, and the question is which limit said no.
-- If the item is already in the bag it HAS a slot, so the only thing left
-- that could have refused is the ninety-nine; if it is not, ask the engine's
-- own two public counters whether there was room. Everything else -- badges,
-- a bag with no space -- falls through to the original answer untouched.
function Carry.install()
  local ok, Bag = pcall(require, "src.inventory.Bag")
  if not (ok and Bag) then return false end
  if Bag.dramaticShapeCarryHook then return true end

  local inner = Bag.add
  Bag.add = function(save, id, qty, data)
    if inner(save, id, qty, data) then return true end

    local cap = Carry.stackCap()
    if cap <= 99 then return false end
    if not (save and save.inventory and id) then return false end
    if Bag.isBadge(id) then return false end

    local inv = save.inventory
    local have = inv[id] or 0
    local add = qty or 1
    if have + add > cap then return false end

    if have == 0 then
      -- no slot yet: the refusal was the bag being full unless it was not,
      -- and only the engine's own counters can say which
      local okC, slots, capacity = pcall(function()
        return Bag.slots(save), Bag.capacity(data)
      end)
      if not okC or slots >= capacity then return false end
      inv[id] = add
      local okO, order = pcall(Bag.order, save)
      if okO and order then table.insert(order, id) end
      return true
    end

    inv[id] = have + add
    return true
  end

  Bag.dramaticShapeCarryHook = true
  return true
end

-- Rides the same update hook every other clock in this mod does, ahead of
-- the camera gate: what fits in the bag is not a question about the camera,
-- and the row has to keep working with voxel mode switched off.
function Carry.update()
  pcall(applySlots)
end

return Carry
