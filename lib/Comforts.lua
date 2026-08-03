-- Three more mercies, on the QOL row with the rest of them.
--
-- ------- 1. the box that fills up
--
-- In the original, catching a Pokemon with a full party and a full box
-- simply fails: the ball is spent, the Pokemon is gone, and the game says
-- the box is full. This engine already fixed the worst of that -- its
-- `Boxes.deposit` walks all twelve boxes and uses the first with room, and
-- its own comment names the divergence -- so the catch does not fail here
-- until every one of the two hundred and forty slots is taken.
--
-- What is left is that nothing FOLLOWS it. The Pokemon lands in box 4, the
-- message says "transferred to someone's PC", and the PC still opens on box
-- 1 with the new arrival three boxes away and no hint that it moved. So the
-- current box follows the catch: open the PC and you are looking at what you
-- just caught.
--
-- (The message itself is left alone. It is queued inside the battle's own
-- text chain before this can know where the Pokemon went, and rewriting a
-- line the engine is in the middle of saying is a worse trade than a player
-- opening the PC and finding it.)
--
-- And the PC's own DEPOSIT still refuses on a full box (BoxMenu prints
-- "BOX n is full!" and stops), which is the same dead end one screen over.
-- That rolls forward too, on the same rule the catch already follows.
--
-- ------- 2. the bag, in pockets
--
-- Gen 1's bag is one flat list of twenty slots in pickup order. Find a
-- Potion in Viridian and it is item 3 forever, with the Bicycle, four TMs
-- and a Nugget between it and the next Potion. There are no pockets --
-- pockets arrive in Gen 2 -- and the only tool the original gives you is
-- SELECT to swap two entries, one pair at a time.
--
-- So the list is SORTED into what Gen 2 would have called pockets: balls,
-- medicine, TMs and HMs, key items, and everything else, in that order,
-- each group alphabetical. Nothing is hidden, nothing is added, and the
-- order is the SAVE's own order (`Bag.order`) rewritten in place -- so a
-- shop, a toss, the PC and the battle bag all see the same list, because
-- there is only one.
--
-- Sorted when the bag OPENS, which is the honest place: it is a sort, and a
-- sort that only happened once would drift out of order with the next item
-- picked up. The cost is that the original's manual SELECT-swap ordering
-- does not survive the next open. That is the trade the row is making, and
-- OFF is still the full 1996 friction.
--
-- The engine's own `ui.list_menu` hook does the rest: the bag wraps top to
-- bottom, LEFT and RIGHT jump a page, and holding a direction scrolls. On a
-- twenty-slot list with no pockets those three were most of the friction.
--
-- ------- 3. a nickname, whenever you like
--
-- Gen 1 offers the naming screen once, in the second between catching a
-- Pokemon and it going into the party, and never again. There is no NAME
-- RATER in Kanto -- he is a Gen 2 building -- so a nickname typed in a
-- hurry at level 5 is that Pokemon's name for the rest of the game.
--
-- So RENAME joins the party menu's own submenu, beside STATS and SWITCH,
-- through the hook the engine put there for it (`ui.party.submenu`, whose
-- dispatcher takes an `onSelect` for exactly this). It opens the game's own
-- naming screen, with the mon's current name already in it, and writes
-- `mon.nickname` -- the same field the catch path writes.
--
-- Clearing the name (delete everything, then ED) puts the SPECIES name
-- back, which is what a Pokemon with no nickname is: the engine reads
-- `mon.nickname or species.name` everywhere, so nil is not a missing value,
-- it is the answer.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local QoL = V.require("QoL")

local Comforts = {}

local function game()
  return require("src.core.Game")
end

function Comforts.enabled()
  return QoL.enabled()
end

-- =====================================================================
-- the box

-- Which box holds this exact Pokemon, or nil. Identity, not species: two
-- Rattata in two boxes are two Rattata.
local function boxHolding(save, mon)
  local Boxes = require("src.pokemon.Boxes")
  local boxes = Boxes.ensure(save)
  for i = 1, Boxes.COUNT do
    for _, m in ipairs(boxes[i] or {}) do
      if m == mon then return i end
    end
  end
  return nil
end

-- The first box with room, starting at the current one and wrapping -- the
-- same walk Boxes.deposit does, asked without depositing anything.
function Comforts.nextRoomyBox(save)
  local Boxes = require("src.pokemon.Boxes")
  local boxes = Boxes.ensure(save)
  for off = 0, Boxes.COUNT - 1 do
    local i = ((save.currentBox - 1 + off) % Boxes.COUNT) + 1
    if #(boxes[i] or {}) < Boxes.CAPACITY then return i end
  end
  return nil
end

function Comforts.onCaught(payload)
  if not Comforts.enabled() then return end
  if not (payload and payload.destination == "box" and payload.mon) then return end
  local Game = game()
  local save = Game and Game.save
  if not save then return end
  local box = boxHolding(save, payload.mon)
  if not box then return end
  -- the PC opens where the new arrival is, rather than on the box that was
  -- full when it got there
  save.currentBox = box
  Comforts.lastBox = box
end

-- =====================================================================
-- the bag

-- The pockets, in the order Gen 2 would have shown them. Answered from the
-- item's OWN record wherever the record says something -- `keyItem` is the
-- engine's own flag, and the HM/TM prefixes are the ids the extractor
-- writes -- so a total conversion's items sort by the same questions.
local POCKET = { ball = 1, medicine = 2, machine = 3, key = 4, other = 5 }

local BALLS = {
  POKE_BALL = true, GREAT_BALL = true, ULTRA_BALL = true,
  MASTER_BALL = true, SAFARI_BALL = true,
}

-- The medicine chest, by what the item DOES rather than by a list of names
-- where the engine gives an answer, and by name where it does not.
local MEDICINE = {
  POTION = true, SUPER_POTION = true, HYPER_POTION = true,
  MAX_POTION = true, FULL_RESTORE = true, REVIVE = true, MAX_REVIVE = true,
  ANTIDOTE = true, BURN_HEAL = true, ICE_HEAL = true, AWAKENING = true,
  PARLYZ_HEAL = true, FULL_HEAL = true, ELIXER = true, MAX_ELIXER = true,
  ETHER = true, MAX_ETHER = true, FRESH_WATER = true, SODA_POP = true,
  LEMONADE = true, MOOMOO_MILK = true,
}

function Comforts.pocketOf(id, def)
  if BALLS[id] or (def and def.ball) then return POCKET.ball end
  if MEDICINE[id] then return POCKET.medicine end
  if id:find("^TM_") or id:find("^HM_") then return POCKET.machine end
  if def and def.keyItem then return POCKET.key end
  return POCKET.other
end

-- Sort the save's own bag order into pockets, each alphabetical by the name
-- the menu actually prints. In place, because there is exactly one order and
-- every screen reads it.
function Comforts.sortBag(save, data)
  local Bag = require("src.inventory.Bag")
  local order = Bag.order(save)
  if not (order and #order > 1) then return false end
  local items = (data and data.items) or {}
  local key = {}
  for _, id in ipairs(order) do
    local def = items[id]
    key[id] = { Comforts.pocketOf(id, def), (def and def.name) or id }
  end
  table.sort(order, function(a, b)
    local ka, kb = key[a], key[b]
    if ka[1] ~= kb[1] then return ka[1] < kb[1] end
    if ka[2] ~= kb[2] then return ka[2] < kb[2] end
    return a < b
  end)
  return true
end

-- =====================================================================
-- the nickname

local function speciesName(Game, mon)
  local def = Game.data and Game.data.pokemon and Game.data.pokemon[mon.species]
  return (def and def.name) or mon.species
end

function Comforts.rename(mon, g)
  local Game = g or game()
  local NamingScreen = require("src.ui.NamingScreen")
  Game.stack:push(NamingScreen.new(Game, {
    title = require("src.core.Strings")("%s's NICKNAME?", speciesName(Game, mon)),
    -- the SPECIES name, not the current nickname, and that is what makes
    -- clearing work: `default` is what the screen falls back to when nothing
    -- was typed, so defaulting to the old name meant an empty box handed
    -- the old name straight back and the nickname could never be removed
    default = speciesName(Game, mon),
    maxLen = 10,
    onDone = function(name)
      -- an empty name is not a name: nil puts the species back, which is
      -- what the rest of the engine already reads as "no nickname"
      name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if name == "" or name == speciesName(Game, mon) then
        mon.nickname = nil
      else
        mon.nickname = name
      end
    end,
  }))
end

-- =====================================================================
-- the seams

function Comforts.install(mod)
  -- THE CATCH. An event rather than a wrap: the engine announces where a
  -- caught Pokemon went, and all this has to do is follow it.
  mod.events:on("pokemon.caught", function(payload)
    pcall(Comforts.onCaught, payload)
  end)

  -- THE PC. BoxMenu's deposit refuses outright when the current box is full,
  -- and its check reads `save.currentBox` -- so moving that to a box with
  -- room BEFORE the menu is built is the whole fix, with no reimplementation
  -- of the deposit and no second copy of the capacity rule.
  --
  -- Only when the current box is FULL: a box with room in it is the box the
  -- player left the PC on, and moving them off it would be the mod deciding
  -- where they wanted to be.
  local BoxMenu = require("src.ui.BoxMenu")
  if not BoxMenu.dramaticShapeBoxHook then
    local inner = BoxMenu.new
    function BoxMenu.new(g, ...)
      if Comforts.enabled() then
        local ok, Boxes = pcall(require, "src.pokemon.Boxes")
        if ok and g and g.save then
          local active = Boxes.active(g.save)
          if active and #active >= Boxes.CAPACITY then
            local roomy = Comforts.nextRoomyBox(g.save)
            if roomy then g.save.currentBox = roomy end
          end
        end
      end
      return inner(g, ...)
    end
    BoxMenu.dramaticShapeBoxHook = true
  end

  -- THE BAG. Sorted on the way in, through the same constructor the start
  -- menu and the battle bag both call.
  local BagMenu = require("src.ui.BagMenu")
  if not BagMenu.dramaticShapeBagHook then
    local inner = BagMenu.new
    function BagMenu.new(g, ...)
      if Comforts.enabled() and g and g.save then
        pcall(Comforts.sortBag, g.save, g.data)
      end
      return inner(g, ...)
    end
    BagMenu.dramaticShapeBagHook = true
  end

  -- and the list itself, through the engine's own hook for it. Only the BAG
  -- is touched: `kind` tells the lists apart, and a shop or the dex asking
  -- for hold-to-scroll is a different decision from this one.
  mod.hooks:wrap("ui.list_menu", function(next, opts, ctx)
    local out = next(opts, ctx) or opts
    if not Comforts.enabled() then return out end
    if not (ctx and ctx.kind == "bag") then return out end
    out.wrap = true
    out.pageJump = true
    out.keyRepeat = true
    return out
  end)

  -- THE NICKNAME. Appended rather than inserted: STATS and SWITCH are where
  -- muscle memory expects them, and the field moves after them are what the
  -- original's own dynamic list looks like. `onSelect` is the engine's
  -- documented route for a hook-injected entry.
  mod.hooks:wrap("ui.party.submenu", function(next, g, items, mon, ctx)
    local out = next(g, items, mon, ctx) or items
    if not Comforts.enabled() then return out end
    -- not mid-battle: the party menu there is "bring out which POKéMON",
    -- and a keyboard over a fight is not a thing anybody wants
    if ctx and ctx.battle then return out end
    if not mon then return out end
    out[#out + 1] = {
      label = require("src.core.Strings")("RENAME"),
      onSelect = function(m, gg) Comforts.rename(m or mon, gg) end,
    }
    return out
  end)
end

return Comforts
