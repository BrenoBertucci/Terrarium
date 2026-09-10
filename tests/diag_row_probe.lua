-- Where the DIAG row actually is, photographed.
--
-- The row was wired and the panel was tested, but "it is on the OPTIONS page"
-- was an assertion about code, not about what a player sees.  This walks the
-- path a player walks -- START, OPTION, down to the row -- and shoots each
-- step, so the answer to "how do I turn it on" is a picture rather than
-- directions.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/diag_row_probe.lua gen1recomp

return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/diag_row_probe.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
    logf:write(table.concat(p, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local function shot(name)
    local img, got = nil, false
    love.graphics.captureScreenshot(function(i) img = i; got = true end)
    local g = 0
    while not got and g < 240 do wait(1); g = g + 1 end
    if img then img:encode("png", name); log("SHOT " .. name)
    else log("FAIL " .. name) end
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld"); logf:close(); love.event.quit(); return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit(); return
  end
  local Pipelines = require("src.render.Pipelines")
  Pipelines.setLevel("terrarium_voxel", 3)
  wait(120)

  -- START opens the menu the player already knows
  local roam = game.stack:top()
  tap("start"); wait(60)
  local menu = game.stack:top()
  if menu == roam or type(menu.items) ~= "table" then
    log("FAIL: no start menu"); logf:close(); love.event.quit(); return
  end
  log("start menu rows:")
  for i, it in ipairs(menu.items) do
    log(("  %d %s"):format(i, tostring(type(it) == "table"
                                       and (it.label or it.text or it.id) or it)))
  end
  shot("diagrow_1_startmenu.png")

  -- down to OPTION and in
  local want = nil
  for i, it in ipairs(menu.items) do
    local s = tostring(type(it) == "table" and (it.label or it.text or it.id) or it)
    if s:upper():find("OP") then want = i end
  end
  if not want then
    log("FAIL: no OPTION row in the start menu"); logf:close(); love.event.quit(); return
  end
  log("OPTION is row " .. want .. ", cursor at " .. tostring(menu.index))
  local guard = 0
  while (menu.index or 1) ~= want and guard < 24 do
    tap("down"); wait(12); guard = guard + 1
  end
  tap("a"); wait(90)
  shot("diagrow_2_options.png")

  -- and what the options screen is actually offering
  local opt = game.stack:top()
  local rows = opt and (opt.rows or opt.items)
  if type(rows) == "table" then
    log("options rows:")
    for i, r in ipairs(rows) do
      local label = type(r) == "table" and (r.label or r.id) or tostring(r)
      local value = ""
      if type(r) == "table" and type(r.value) == "function" then
        local ok, v = pcall(r.value)
        if ok then value = "  = " .. tostring(v) end
      end
      log(("  %2d %-12s %s"):format(i, tostring(label), value))
    end
  else
    log("options screen exposes no row list we can read (top = "
        .. tostring(opt and opt.screenId or "?") .. ")")
  end

  -- scroll far enough that DIAG is on screen whatever the list length
  for _ = 1, 6 do tap("down"); wait(10) end
  shot("diagrow_3_options_scrolled.png")

  log("done")
  logf:close()
  love.event.quit()
end
