-- Probe: WHAT PAINTS THE CHECKER ON THE CAVE STAIRS.
--
-- The tile art of the stair cell ($15/$16) is four plain treads; the 3D
-- shot has a dithered patch over its eastern half. That patch is drawn by
-- SOMETHING, and the honest way to name it is to turn one system off at a
-- time from the same camera and diff the pixels.
--
-- One position (Seafoam B4F, two cells north of the stair at 7,11), one
-- shot per configuration, and a mean-absolute-difference against the
-- baseline printed for each so the answer is a number and not a squint.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/cave_ab_probe.lua ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/cave_ab.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
    logf:write(table.concat(p, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end
  local function finish(m) if m then log(m) end logf:close() love.event.quit() end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then return finish("FAIL: no overworld") end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then return finish("FAIL: TERRARIUM not loaded") end
  log("version:", exports.TERRARIUM.version)

  local function req(m) local ok, v = pcall(lib.require, m); return ok and v or nil end
  local GroundFX = req("GroundFX")
  local RayFX    = req("RayFX")
  local Anime    = req("Anime")
  local Quality  = req("Quality")
  local DayNight = req("DayNight")
  local Weather  = req("Weather")
  local Light    = req("Light")
  local Voxel3D  = req("Voxel3D")
  local Grass3D  = req("Grass3D")
  local Crypt    = req("Crypt")
  local function sync(s, v) if s then pcall(s.sync, s, v) end end

  -- the captured frame kept in memory, so the diff is done here and not by
  -- a second tool afterwards
  local function grab()
    local out = nil
    love.graphics.captureScreenshot(function(data) out = data end)
    local g = 0
    while out == nil and g < 240 do coroutine.yield(); g = g + 1 end
    return out
  end
  local function save(img, name)
    if not img then return end
    local f = io.open(OUT .. "/" .. name, "wb")
    if f then f:write(img:encode("png"):getString()) f:close() end
  end
  -- mean absolute difference over the stair's screen box, 0..255
  local function diff(a, b, x0, y0, x1, y1)
    if not (a and b) then return -1 end
    local w, h = a:getDimensions()
    x0 = math.max(0, math.min(w - 1, x0)); x1 = math.max(0, math.min(w - 1, x1))
    y0 = math.max(0, math.min(h - 1, y0)); y1 = math.max(0, math.min(h - 1, y1))
    local sum, cnt = 0, 0
    for y = y0, y1, 2 do
      for x = x0, x1, 2 do
        local r1, g1, b1 = a:getPixel(x, y)
        local r2, g2, b2 = b:getPixel(x, y)
        sum = sum + math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2)
        cnt = cnt + 3
      end
    end
    return cnt > 0 and (sum / cnt) * 255 or -1
  end

  sync(Weather and Weather.setting, "off")
  sync(DayNight and DayNight.setting, "day")
  sync(Quality and Quality.setting, 2)

  local function settle()
    Voxel3D.lampLights = nil
    for _ = 1, 300 do
      if Voxel3D.lampLights ~= nil then break end
      coroutine.yield()
    end
    wait(150)
  end

  local function go()
    pcall(function()
      game.overworld:setMap("SEAFOAM_ISLANDS_B4F", 7, 9, "down")
    end)
    wait(30)
    -- the player walks on after setMap; park him again and let him stop
    pcall(function()
      game.overworld:setMap("SEAFOAM_ISLANDS_B4F", 7, 9, "down")
    end)
    wait(40)
    settle()
  end

  -- everything ON is the baseline
  local CASES = {
    { name = "base",       apply = function()
        sync(GroundFX and GroundFX.setting, "on")
        sync(RayFX and RayFX.setting, "rt")
        sync(Anime and Anime.setting, "on")
        sync(Grass3D and Grass3D.setting, "on")
        sync(Light and Light.setting, "on")
      end },
    { name = "ground_off", apply = function() sync(GroundFX and GroundFX.setting, "off") end },
    { name = "rayfx_off",  apply = function() sync(RayFX and RayFX.setting, "off") end },
    { name = "anime_off",  apply = function() sync(Anime and Anime.setting, "off") end },
    { name = "light_off",  apply = function() sync(Light and Light.setting, "off") end },
    { name = "crypt_off",  apply = function()
        sync(Crypt and Crypt.setting, "off")
        sync(Crypt and Crypt.fxSetting, "off")
      end },
  }

  local base = nil
  for i, c in ipairs(CASES) do
    -- always start from everything on, then apply this case's single change
    CASES[1].apply()
    if i > 1 then c.apply() end
    go()
    local img = grab()
    save(img, ("caveab_%d_%s.png"):format(i, c.name))
    if i == 1 then
      base = img
      log(("[%s] baseline saved"):format(c.name))
    else
      -- the stair sits just south of the player, a bit right of centre
      local d = diff(base, img, 700, 480, 880, 700)
      local dAll = diff(base, img, 0, 0, 1000000, 1000000)
      log(("[%s] stairbox MAD=%.2f  whole-frame MAD=%.2f"):format(c.name, d, dAll))
    end
  end
  finish("done")
end
