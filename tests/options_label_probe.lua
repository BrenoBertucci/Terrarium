-- Probe: the row that used to be called RTX reads SCREEN FX on the menu.
--
-- Counted:
--   the OPTIONS menu built through the engine's own ui.options.rows hook
--   carries the mod's row under the id TERRARIUM:rayfx, its label is
--   "SCREEN FX", its value is one of AUTO / SSR / AO / OFF / MAX, and no
--   row anywhere on that menu still says "RTX";
--   the label FITS: the engine prints a row's label at x=16 on a 160 px
--   line (src/ui/OptionRows.lua, fits(16) = 18 glyphs) and clips or
--   marquees past that, so a label of 18 or fewer is printed whole;
--   the mod manager's schema for the same key carries the same words.
-- And a shot of the menu with the cursor on the row, at whatever rung the
-- save holds, and after one step right.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/options_label_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/options_label_probe.log", "w"))
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
  if not lib then log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return end
  log("version:", exports.TERRARIUM.version)

  local RayFX = lib.require("RayFX")
  local OptionsMenu = require("src.ui.OptionsMenu")
  local FITS = math.floor((160 - 16) / 8)

  -- ------- 1. the setting itself
  log(("setting: key=%s label=%q labels=%s values=%s")
      :format(RayFX.setting.key, RayFX.setting.label,
              table.concat(RayFX.setting.labels, "/"),
              table.concat(RayFX.setting.values, "/")))
  local okLabel = RayFX.setting.label == "SCREEN FX"
  if not okLabel then log("  FAIL: the row's label is not SCREEN FX") end
  if #RayFX.setting.label > FITS then
    log(("  FAIL: label is %d glyphs, the menu prints %d"):format(#RayFX.setting.label, FITS))
  end
  for i, l in ipairs(RayFX.setting.labels) do
    if l == "RT" or l == "RTX" then log("  FAIL: rung " .. i .. " still reads " .. l) end
  end
  local schema = RayFX.setting:schema("")
  log(("schema: type=%s label=%q choices=%d"):format(schema.type, schema.label, #schema.choices))
  if schema.label ~= "SCREEN FX" then log("  FAIL: the manager page's label differs") end

  -- ------- 2. the menu, through the engine's own hook
  --
  -- The mod's rows are offered from the 3D pipeline's own menu, so the
  -- pipeline has to be up: rung 4 (the diorama, short of FULL), the way
  -- the other probes stand it up.
  local Pipelines = require("src.render.Pipelines")
  log("pipeline level before: " .. tostring(Pipelines.level("terrarium_voxel")))
  Pipelines.setLevel("terrarium_voxel", 4)
  wait(60)
  log("pipeline level now: " .. tostring(Pipelines.level("terrarium_voxel")))
  -- the hook chain itself: if the mod's link throws, the engine keeps the
  -- vanilla rows and only warns in its log, so ask each link directly
  local Runtime = require("src.mods.Runtime")
  local chain = Runtime.hooks and Runtime.hooks.chains and Runtime.hooks.chains["ui.options.rows"]
  log("hook chain links: " .. tostring(chain and #chain or 0))
  for i, e in ipairs(chain or {}) do
    local okH, res = pcall(e.callback, function(g, r) return r end, game, {})
    log(("  link %d owner=%s ok=%s -> %s"):format(i, tostring(e.owner), tostring(okH),
        okH and (type(res) == "table" and (#res .. " rows") or tostring(res)) or tostring(res)))
  end
  local menu = OptionsMenu.new(game)
  game.stack:push(menu)
  wait(10)
  local stale, found, rowId = {}, nil, nil
  local function scan(rows)
    for _, row in ipairs(rows or {}) do
      local label = tostring(row.label or "")
      if label:find("RTX", 1, true) then stale[#stale + 1] = label end
      -- the id is <mod id>:rayfx, and the mod id is whatever the loader
      -- gave us -- match on the key rather than guessing the prefix
      local id = tostring(row.id or "")
      if id:sub(-6) == ":rayfx" then found = row; rowId = id end
    end
  end
  scan(menu.rows); scan(menu.view)
  local ids = {}
  for _, row in ipairs(menu.view or {}) do ids[#ids + 1] = tostring(row.id) end
  log(("view: %d rows (%s)  flat rows: %d"):format(#(menu.view or {}), table.concat(ids, ","), #(menu.rows or {})))
  log("row id: " .. tostring(rowId))
  local flat = {}
  for _, row in ipairs(menu.rows or {}) do flat[#flat + 1] = tostring(row.id) end
  log("flat ids: " .. table.concat(flat, ","))
  if found then
    local value = found.value and found.value(game) or "?"
    log(("menu row: label=%q value=%q"):format(tostring(found.label), tostring(value)))
    if found.label ~= "SCREEN FX" then log("  FAIL: the menu row's label is not SCREEN FX") end
  else
    log("  FAIL: no row keyed rayfx on the options menu")
  end
  if #stale > 0 then
    log("  FAIL: rows still saying RTX: " .. table.concat(stale, ", "))
  else
    log("no row on the menu says RTX")
  end

  -- cursor on the row, and a picture of it
  local screen = rowId and menu:focusRow(rowId)
  wait(30)
  local top = game.stack:top()
  log(("focused: screen=%s top-is-menu=%s index=%s scroll=%s")
      :format(tostring(screen ~= nil), tostring(top == menu), tostring(top.index), tostring(top.scroll)))
  local rows = top.view or top.rows
  local under = rows and rows[top.index]
  if under then
    log(("row under cursor: id=%s label=%q value=%q")
        :format(tostring(under.id), tostring(under.label),
                tostring(under.value and under.value(game))))
    if under.id ~= rowId then log("  FAIL: the cursor is not on the row") end
  end
  shot("options_screenfx_cursor.png")
  -- one step right: the value should be the next rung (or wrap to AUTO)
  local before = RayFX.setting:read()
  tap("right"); wait(30)
  local after = RayFX.setting:read()
  log(("after right: rung %d -> %d, reads %q")
      :format(before, after, tostring(RayFX.setting.labels[after])))
  shot("options_screenfx_stepped.png")
  -- and back where it was, so the save is not touched
  tap("left"); wait(20)
  log(("restored: rung %d"):format(RayFX.setting:read()))

  log("done")
  logf:close()
  love.event.quit()
end
