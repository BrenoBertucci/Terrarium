-- The start menu's MAP row.
--
-- The town map is the one thing in this game you look at constantly and reach
-- most slowly: Start, ITENS, scroll to the MAPA key item, A, and only then the
-- map -- five inputs and two menus deep to answer "where am I". Every other
-- thing on that menu is one input from the top.
--
-- So it gets a row of its own. Nothing about the map SCREEN changes: the row
-- pushes `src.ui.TownMap`, which is the same screen the key item opens, built
-- the same way (probed: `TownMap.new(game)` takes the game and nothing else,
-- and the screen it returns pushes onto the stack and runs). This file only
-- shortens the route to it.
--
-- WHERE IT SITS. Directly under ITENS, which is where the map lives today --
-- somebody who knows the old route finds the new one on the way to the old
-- one. Not at the top: the first row is POKeDEX and moving it would make a
-- menu people navigate by muscle memory lie to them.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local StartMenuMap = {}

StartMenuMap.ENABLED = true

-- What the row says. The engine's own item is called MAPA in this build's
-- strings (data item TOWN_MAP, name = "MAPA"), so the row borrows that rather
-- than inventing a second word for the same object.
StartMenuMap.LABEL = "MAPA"

-- The row this one goes under, matched case-insensitively against the menu's
-- own labels. A build whose ITENS row is spelled differently gets the row
-- appended at the end instead of not at all -- see insertAt.
StartMenuMap.AFTER = "ITENS"

-- Whether the row appears only when the town map is actually carried.
--
-- It SHOULD, and the reason it defaults to false is that this mod could not
-- find the inventory to ask: `game.player` has no items/bag/inventory field
-- (probed), so the check would have to guess at where the bag lives and a
-- wrong guess hides the row from somebody who owns the map. Failing OPEN is
-- the harmless direction -- a row that opens a map you have not been given is
-- a small break in the game's own gating; a row that vanishes for no reason
-- is a bug report.
StartMenuMap.REQUIRE_ITEM = false
StartMenuMap.ITEM_ID = "TOWN_MAP"

-- Best-effort: does the player carry the town map? Returns nil for "cannot
-- tell", which is different from false and is why the caller treats the two
-- differently.
function StartMenuMap.carriesMap(game)
  local bag = game and (game.bag or (game.player and game.player.bag)
                        or (game.save and game.save.items))
  if type(bag) ~= "table" then return nil end
  for _, entry in pairs(bag) do
    local id = type(entry) == "table" and (entry.id or entry.item) or entry
    if id == StartMenuMap.ITEM_ID then return true end
  end
  return false
end

function StartMenuMap.open(game)
  local ok, TownMap = pcall(require, "src.ui.TownMap")
  if not (ok and TownMap and TownMap.new) then return false end
  local made, screen = pcall(TownMap.new, game)
  if not (made and screen) then return false end
  local pushed = pcall(function() game.stack:push(screen) end)
  return pushed
end

-- Where the row goes: just after the row whose label matches AFTER, or at the
-- end if there is no such row. Never before the first entry and never past
-- the last -- an index outside the list is a menu that crashes on open, and
-- this is the menu the player opens most.
function StartMenuMap.insertAt(items)
  local want = StartMenuMap.AFTER:lower()
  for i = 1, #items do
    local label = items[i] and items[i].label
    if type(label) == "string" and label:lower() == want then return i + 1 end
  end
  return #items + 1
end

function StartMenuMap.row(game)
  return {
    label = StartMenuMap.LABEL,
    onSelect = function() StartMenuMap.open(game) end,
  }
end

-- ------- the seam
--
-- StartMenu.new builds the menu and hands back a `src.ui.Menu` -- the two
-- share a metatable (probed), so the list is a plain array of
-- { label, onSelect } on the returned object and the row can simply be
-- inserted into it. Wrapping StartMenu.new rather than Menu.new on purpose:
-- Menu is the class every list in the game is built from, and adding a row to
-- all of them is not what this is for.
--
-- Idempotent, like the battle hooks, so a hot reload cannot stack two rows.
function StartMenuMap.install()
  local ok, StartMenu = pcall(require, "src.ui.StartMenu")
  if not (ok and StartMenu and StartMenu.new) then return false end
  if StartMenu.terrariumMapRow then return true end

  local inner = StartMenu.new
  StartMenu.new = function(game, ...)
    local menu = inner(game, ...)
    if not (StartMenuMap.ENABLED and type(menu) == "table"
            and type(menu.items) == "table") then
      return menu
    end
    -- nil means "could not tell" and is treated as yes; see REQUIRE_ITEM
    if StartMenuMap.REQUIRE_ITEM
       and StartMenuMap.carriesMap(game) == false then
      return menu
    end
    -- never twice on the same menu, whatever else wraps this
    for i = 1, #menu.items do
      if menu.items[i] and menu.items[i].label == StartMenuMap.LABEL then
        return menu
      end
    end
    table.insert(menu.items, StartMenuMap.insertAt(menu.items),
                 StartMenuMap.row(game))
    -- The menu sizes and scrolls off its own list. maxVisible and the cursor
    -- clamp are the two things a longer list can break, and the class already
    -- has the answer to the second -- so ask it rather than reimplementing it.
    if menu.clampScroll then pcall(menu.clampScroll, menu) end
    return menu
  end
  StartMenu.terrariumMapRow = true
  return true
end

return StartMenuMap
