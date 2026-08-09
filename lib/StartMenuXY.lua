-- The start menu, drawn at the window's own resolution.
--
-- THE PROBLEM THIS EXISTS TO SOLVE. The engine's menu draws into the 160x144
-- UI canvas -- measured, by asking `love.graphics.getCanvas()` from inside the
-- menu's own draw. Every pixel of a 5x interface pack put through that canvas
-- is thrown away on the way to the screen: the "modernised" menu would come
-- out at Game Boy resolution wearing different colours, which is the one
-- outcome not worth the work.
--
-- So the menu is not redrawn where the engine draws it. It is drawn where the
-- MINIMAP is drawn -- into the finished world canvas, in screen pixels, from
-- the render pipeline's present hook (see main.lua, beside MiniMap.present).
-- That canvas is the full window, so the art arrives at the size it was cut
-- at.
--
-- Two halves, and both are needed or the frame shows two menus:
--   * this file DRAWS the X/Y menu onto the world canvas, and
--   * it SILENCES the engine's own draw -- on the menu INSTANCE, never on the
--     class. `src.ui.StartMenu.new` hands back a `src.ui.Menu`, and the two
--     share a metatable: blanking `draw` there would blank every list in the
--     game, the bag and the party included.
--
-- What is NOT touched: the menu's behaviour. Cursor movement, wrapping,
-- scrolling, what each row does, which rows exist -- all still the engine's,
-- read out of `menu.index` and `menu.items` each frame. This file is a
-- costume, not a rewrite, and the MAP row it draws comes from
-- lib/StartMenuMap.lua rather than from here.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local StartMenuXY = {}

StartMenuXY.ENABLED = true
StartMenuXY.ASSET_DIR = "assets/menuxy/"

-- Which icon goes with which row, matched on the row's own LABEL, lowercased.
-- Matched on the label rather than on the index because the list is not fixed:
-- this mod adds MAPA, the build adds LINK and MODS, and a row matched by
-- position would put the bag's satchel next to the pokedex the moment
-- anything else inserts a row.
--
-- The player's own name is a row too (it opens the trainer card), and it can
-- be anything -- so it is the fallback rather than an entry: any row this
-- table does not know gets the notepad.
-- Keyed on the label with its ACCENTS STRIPPED, not on the label itself.
--
-- Lua's string.lower only moves A-Z: "OPÇÕES":lower() is "opÇÕes", with the
-- cedilla and the tilde still upper case and still two bytes each. Keying on
-- the accented spelling therefore missed, and the options row came up wearing
-- the notepad -- visible in the frame, invisible in any log. `key()` below
-- drops every byte over 127, so "OPÇÕES" and "POKéDEX" arrive as "opes" and
-- "pokdex" and the table is written in those terms. Ugly to read, and it is
-- the only form that cannot be wrong about a language this game ships in six
-- of.
StartMenuXY.ICONS = {
  pokdex = "icon_dex",   pokedex = "icon_dex",
  pokmon = "icon_party", pokemon = "icon_party",
  itens = "icon_bag",    item = "icon_bag",
  mochila = "icon_bag",  bag = "icon_bag",
  mapa = "icon_map",     map = "icon_map",
  salvar = "icon_save",  save = "icon_save",
  opes = "icon_options", opcoes = "icon_options",
  option = "icon_options", options = "icon_options",
}
StartMenuXY.ICON_FALLBACK = "icon_report"

-- lower-case, ASCII only. See ICONS.
local function iconKey(label)
  if type(label) ~= "string" then return "" end
  return (label:lower():gsub("[\128-\255]", ""))
end

-- Geometry, all as fractions of the WINDOW so the menu is one object at any
-- size. The panel hangs off the right edge, which is where the engine's own
-- menu is anchored (`anchor = "topright"`) -- the shape changes, the corner
-- does not.
StartMenuXY.WIDTH_FRAC = 0.30      -- of window width
StartMenuXY.MIN_W, StartMenuXY.MAX_W = 240, 460
StartMenuXY.MARGIN_FRAC = 0.02
StartMenuXY.ROW_H_FRAC = 0.082     -- of window height, per row
StartMenuXY.MIN_ROW_H = 34
StartMenuXY.PAD = 10               -- inside the panel, screen px

-- The panel behind the rows. Drawn rather than blitted: the pack's own menu
-- plate is a pink-white sheet built for a 3DS top screen and it fights a
-- lit diorama. A dark glass panel is what lets the world stay visible behind
-- the menu, which is the whole reason this mode exists.
StartMenuXY.PANEL = { 0.09, 0.10, 0.13, 0.86 }
StartMenuXY.PANEL_EDGE = { 0.55, 0.60, 0.70, 0.55 }
StartMenuXY.ROW_SELECTED = { 0.20, 0.52, 0.86, 0.95 }
StartMenuXY.TEXT = { 1, 1, 1, 1 }
StartMenuXY.TEXT_DIM = { 0.78, 0.80, 0.85, 1 }

local images = {}

local function art(name)
  local hit = images[name]
  if hit ~= nil then return hit or nil end
  local okA, Assets = pcall(require, "src.render.Assets")
  if not okA or not Assets then images[name] = false; return nil end
  local path = V.path .. "/" .. StartMenuXY.ASSET_DIR .. name .. ".png"
  local okE, exists = pcall(Assets.exists, path)
  if not (okE and exists) then images[name] = false; return nil end
  local ok, img = pcall(Assets.image, path)
  if not (ok and img) then images[name] = false; return nil end
  pcall(img.setFilter, img, "linear", "linear")
  images[name] = img
  return img
end

-- The alphabet is the battle HUD's -- the same 5x pack, already cut and
-- measured (see lib/BattleHudXY.lua and data/hudxy_glyphs.lua). One font in
-- the mod rather than two copies of one font.
local BattleHudXY = V.require("BattleHudXY")

function StartMenuXY.available()
  if not StartMenuXY.ENABLED then return false end
  if not BattleHudXY.available() then return false end
  return art("icon_dex") ~= nil
end

-- The menu on top of the stack, or nil. Identified by SHAPE rather than by
-- class: `screenId` is what the engine stamps on it, and an items array with
-- an index is what this file actually needs -- a build that renames the
-- screen still gets its menu drawn, and a screen that is not a menu cannot
-- be mistaken for one.
function StartMenuXY.current(game)
  local top = game and game.stack and game.stack:top()
  if type(top) ~= "table" then return nil end
  if top.screenId ~= "StartMenu" then return nil end
  if type(top.items) ~= "table" or type(top.index) ~= "number" then
    return nil
  end
  return top
end

local function iconFor(label)
  return StartMenuXY.ICONS[iconKey(label)] or StartMenuXY.ICON_FALLBACK
end

local function setColor(c, a)
  love.graphics.setColor(c[1], c[2], c[3], (a or 1) * (c[4] or 1))
end

-- A rounded panel, drawn from primitives. love.graphics.rectangle takes a
-- radius, and a menu is not the place to spend a texture on a rectangle.
local function panel(x, y, w, h)
  local r = math.min(14, h * 0.5, w * 0.5)
  setColor(StartMenuXY.PANEL)
  love.graphics.rectangle("fill", x, y, w, h, r, r)
  setColor(StartMenuXY.PANEL_EDGE)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x, y, w, h, r, r)
  love.graphics.setLineWidth(1)
end

-- ------- the draw
--
-- `canvas` is the finished world canvas in SCREEN pixels -- the same surface
-- MiniMap.present paints on, and the reason this looks like X/Y art instead
-- of like a Game Boy menu wearing it.
function StartMenuXY.present(canvas)
  if not (canvas and StartMenuXY.available()) then return canvas end
  -- same one-liner MiniMap uses; the Game module IS the running game
  local okG, Game = pcall(require, "src.core.Game")
  local menu = okG and StartMenuXY.current(Game) or nil
  if not menu then return canvas end

  local cw = canvas.getWidth and canvas:getWidth() or 0
  local ch = canvas.getHeight and canvas:getHeight() or 0
  if cw < 1 or ch < 1 then return canvas end

  local g = love.graphics
  local prevCanvas = g.getCanvas and g.getCanvas() or nil
  local prevBlend, prevAlpha = g.getBlendMode()
  local okBind = pcall(g.setCanvas, canvas)
  if not okBind then return canvas end
  pcall(g.setBlendMode, "alpha")

  pcall(function()
    local items = menu.items
    local n = #items
    local w = math.max(StartMenuXY.MIN_W,
                       math.min(StartMenuXY.MAX_W, cw * StartMenuXY.WIDTH_FRAC))
    local rowH = math.max(StartMenuXY.MIN_ROW_H, ch * StartMenuXY.ROW_H_FRAC)
    local pad = StartMenuXY.PAD
    local m = math.floor(cw * StartMenuXY.MARGIN_FRAC + 0.5)

    -- Only what the engine says is on screen. `scroll` and `maxVisible` are
    -- the menu's own, so a list longer than the panel scrolls exactly as the
    -- engine's does -- including the MAP row this mod inserted, which is what
    -- makes the insertion safe rather than merely lucky.
    local first = (menu.scroll or 0) + 1
    local last = math.min(n, first + (menu.maxVisible or n) - 1)
    local shown = last - first + 1
    if shown < 1 then return end

    local h = shown * rowH + pad * 2
    local x = cw - w - m
    local y = m

    panel(x, y, w, h)

    local iconD = rowH * 0.74
    local textH = rowH * 0.46
    for i = first, last do
      local it = items[i]
      local ry = y + pad + (i - first) * rowH
      local selected = (i == menu.index)
      if selected then
        setColor(StartMenuXY.ROW_SELECTED)
        g.rectangle("fill", x + 4, ry + 2, w - 8, rowH - 4, 8, 8)
      end
      local icon = art(iconFor(it and it.label))
      if icon then
        local iw, ih = icon:getDimensions()
        local s = iconD / math.max(iw, ih)
        g.setColor(1, 1, 1, 1)
        g.draw(icon, x + pad + 2, ry + (rowH - ih * s) * 0.5, 0, s, s)
      end
      local label = it and it.label or ""
      BattleHudXY.text(label, x + pad + iconD + 12,
                       ry + (rowH - textH) * 0.5, textH,
                       selected and StartMenuXY.TEXT or StartMenuXY.TEXT_DIM)
    end

    -- A list that scrolls says so. Two chevrons rather than a scrollbar: the
    -- panel is eight rows tall at most and a bar would be longer than the
    -- thing it measures.
    if first > 1 or last < n then
      setColor(StartMenuXY.PANEL_EDGE)
      local cxm = x + w - pad - 4
      if first > 1 then
        g.polygon("fill", cxm - 5, y + 7, cxm + 5, y + 7, cxm, y + 1)
      end
      if last < n then
        g.polygon("fill", cxm - 5, y + h - 7, cxm + 5, y + h - 7, cxm, y + h - 1)
      end
    end
    g.setColor(1, 1, 1, 1)
  end)

  if prevCanvas then pcall(g.setCanvas, prevCanvas) else pcall(g.setCanvas) end
  pcall(g.setBlendMode, prevBlend or "alpha", prevAlpha)
  g.setColor(1, 1, 1, 1)
  return canvas
end

-- ------- silencing the engine's menu
--
-- On the INSTANCE. `src.ui.StartMenu.new` returns a `src.ui.Menu` and the two
-- share a metatable (probed), so a blank `draw` on the class would blank the
-- bag, the party and every other list in the game. An instance field shadows
-- the metatable's method for that object alone, and the object is thrown away
-- when the menu closes.
--
-- The original is kept and restored if the X/Y menu ever cannot draw: a
-- frame with no menu at all is worse than a Game Boy one.
function StartMenuXY.install()
  local ok, StartMenu = pcall(require, "src.ui.StartMenu")
  if not (ok and StartMenu and StartMenu.new) then return false end
  if StartMenu.terrariumXYMenu then return true end

  local inner = StartMenu.new
  StartMenu.new = function(game, ...)
    local menu = inner(game, ...)
    if type(menu) == "table" then
      local engineDraw = menu.draw
      menu.draw = function(self, ...)
        -- asked per frame, not per menu: the setting can change under it
        if StartMenuXY.available() then return end
        if engineDraw then return engineDraw(self, ...) end
        local mt = getmetatable(self)
        local classDraw = mt and mt.__index and mt.__index.draw
        if classDraw then return classDraw(self, ...) end
      end
    end
    return menu
  end
  StartMenu.terrariumXYMenu = true
  return true
end

return StartMenuXY
