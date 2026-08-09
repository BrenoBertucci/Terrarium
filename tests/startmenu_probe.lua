-- Probe: what IS the overworld's start menu, and how would a row be added?
--
-- Two jobs here and both need the same answer. The menu is to be redrawn in
-- X/Y art, and it is to gain a MAP row so the town map stops being something
-- you reach by opening the bag and using an item. Neither can be written
-- against a guess: the engine ships inside the executable, so its menu is
-- discovered by opening one and looking at it.
--
-- Reports the screen object on top of the stack after Start is pressed -- its
-- metatable's name if it has one, its fields, its methods, and (the thing
-- that actually decides the shape of the work) whether its ENTRIES are a
-- table it builds and holds, or a list baked into a draw call.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/startmenu_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/startmenu.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local function shot(name)
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
    end)
    wait(4)
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit()
      return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end
  wait(60)

  local function brief(v)
    local t = type(v)
    if t == "string" then return ("%q"):format(#v > 60 and v:sub(1, 60) or v) end
    if t == "number" or t == "boolean" then return tostring(v) end
    return t
  end
  local function dump(label, tbl, depth)
    if type(tbl) ~= "table" then log(label .. " = " .. brief(tbl)); return end
    local keys = {}
    for k in pairs(tbl) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    log(("%s: %d keys"):format(label, #keys))
    for _, k in ipairs(keys) do
      local v = tbl[k]
      if v == nil then v = tbl[tonumber(k)] end
      if type(v) == "table" and (depth or 0) < 1 then
        dump("  " .. label .. "." .. k, v, (depth or 0) + 1)
      else
        log(("  %s.%s = %s"):format(label, k, brief(v)))
      end
    end
  end

  -- START. The engine's own button name is what the input layer calls it;
  -- if the tap does nothing the log says so rather than the probe hanging.
  local before = game.stack:top()
  tap("start"); wait(45)
  local menu = game.stack:top()
  log("start opened something new: " .. tostring(menu ~= before))
  if menu == before then
    -- some builds name it differently; try the other spellings before giving up
    for _, name in ipairs({ "Start", "START", "select" }) do
      tap(name); wait(30)
      menu = game.stack:top()
      if menu ~= before then log("opened with button: " .. name) break end
    end
  end
  if menu == before then
    log("FAIL: Start did not open a menu")
    logf:close(); love.event.quit(); return
  end
  shot("startmenu.png")

  local mt = getmetatable(menu)
  log("menu metatable: " .. tostring(mt))
  if mt and mt.__index then
    log("  __index type: " .. type(mt.__index))
    if type(mt.__index) == "table" then
      local ms = {}
      for k, v in pairs(mt.__index) do
        ms[#ms + 1] = k .. "(" .. type(v):sub(1, 4) .. ")"
      end
      table.sort(ms)
      log("  methods: " .. table.concat(ms, " "))
    end
  end
  dump("menu", menu)

  -- The entries. Whatever they are called, they are the list a MAP row has to
  -- be inserted into -- so anything list-shaped gets printed in full.
  for _, key in ipairs({ "entries", "items", "options", "rows", "choices",
                         "labels", "list" }) do
    local v = menu[key]
    if type(v) == "table" then
      log(("menu.%s has %d array entries:"):format(key, #v))
      for i = 1, #v do log(("   [%d] = %s"):format(i, brief(v[i]))) end
    end
  end

  -- The shape of ONE entry. This is the thing a MAP row has to imitate, and
  -- imitating it wrongly is a crash in a menu the player opens constantly.
  for i = 1, #(menu.items or {}) do
    local it = menu.items[i]
    local ks = {}
    for k, v in pairs(it) do ks[#ks + 1] = k .. "=" .. brief(v) end
    table.sort(ks)
    log(("  items[%d]: %s"):format(i, table.concat(ks, "  ")))
  end

  -- Can the town map be opened directly? If TownMap.new takes the game and
  -- nothing else, the new row is a two-line action; if it needs state the
  -- bag's use-handler assembles, it is not, and better to find out here.
  do
    local ok, TownMap = pcall(require, "src.ui.TownMap")
    if ok and TownMap and TownMap.new then
      local made, screen = pcall(TownMap.new, game)
      log("TownMap.new(game) -> " .. tostring(made) .. " " ..
          (made and type(screen) or tostring(screen)))
      if made and type(screen) == "table" then
        local ks = {}
        for k in pairs(screen) do ks[#ks + 1] = k end
        table.sort(ks)
        log("  screen keys: " .. table.concat(ks, " "))
        game.stack:push(screen)
        wait(60)
        shot("townmap.png")
        log("  pushed; top is the map: " .. tostring(game.stack:top() == screen))
      end
    end
  end

  -- And the town map, which is what the new row has to open. Look for the
  -- screen module and for the item that currently reaches it.
  for _, path in ipairs({ "src.ui.TownMap", "src.ui.TownMapScreen",
                          "src.ui.MapScreen", "src.screens.TownMap" }) do
    local ok, mod = pcall(require, path)
    log(("require %-24s -> %s"):format(path, ok and type(mod) or "no"))
    if ok and type(mod) == "table" then
      local ks = {}
      for k in pairs(mod) do ks[#ks + 1] = k end
      table.sort(ks)
      log("   keys: " .. table.concat(ks, " "))
    end
  end
  local items = game.data and game.data.items
  if type(items) == "table" then
    for id, def in pairs(items) do
      local s = tostring(id):upper()
      if s:find("MAP") then
        log("item " .. tostring(id) .. ":")
        dump("  def", def, 1)
      end
    end
  end

  -- Which module IS this, and does the player carry a town map? The row has
  -- to be inserted by wrapping the menu's constructor, so the module path
  -- matters; and it should only appear when the map is actually owned, which
  -- is the condition the bag already imposes today.
  for _, path in ipairs({ "src.ui.StartMenu", "src.ui.Menu", "src.ui.ListMenu",
                          "src.ui.OverworldMenu" }) do
    local ok, mod = pcall(require, path)
    local isIt = ok and type(mod) == "table" and mod.new ~= nil
    log(("require %-22s -> %s%s"):format(path, ok and type(mod) or "no",
        isIt and (getmetatable(menu) and mod.__index == getmetatable(menu).__index
                  and "  <-- SAME metatable" or "  (has new)") or ""))
  end
  local inv = game.player and (game.player.items or game.player.bag
                               or game.player.inventory)
  log("player inventory field: " .. type(inv))
  if type(inv) == "table" then
    local n = 0
    for i, e in pairs(inv) do
      n = n + 1
      if n <= 6 then
        local ks = {}
        if type(e) == "table" then
          for k, v in pairs(e) do ks[#ks + 1] = k .. "=" .. brief(v) end
        end
        log(("  inv[%s] = %s %s"):format(tostring(i), brief(e),
                                         table.concat(ks, " ")))
      end
    end
    log("  entries: " .. n)
  end

  logf:close()
  love.event.quit()
end
