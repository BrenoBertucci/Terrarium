-- The phone, reproduced on the desktop, because the phone is not here.
--
-- Three reports came back from a Poco X7 (Mali-G615 MC2) running 1.33.0-beta:
-- speckled NOISE over everything and worse on water, the new Lavender tower
-- not standing, and the new Poke Mart interior not standing.  None of the
-- three happens on this machine at this machine's settings, so the first job
-- is to make this machine answer to the phone's settings instead.
--
-- Four things are different on that device and all four can be forced here:
--
--   MOBILE   Device.mobile() is what RES AUTO's pixel budget, the RTX AUTO
--            gate, the capped shadow ladder and the FULL preset's blur all
--            branch on.  Forced true.
--   RES      AUTO on a 3.31 Mpx panel picks 1/4.  Forced, so the noise is
--            looked at through the same upscale the player is looking
--            through.
--   RUNG     GLES2 guarantees eight fragment samplers and the full rung
--            binds ten, so a conformant driver drops the mod to `no-crypt`
--            -- and lib/Shop.lua:24 says in as many words that the SHOP
--            borrows the crypt's two sampler pairs.  If that rung is what
--            the phone took, the tower's stone and the shop's surfaces are
--            gone for exactly the documented reason.  Forced with the same
--            fake driver tests/gpu_compat_probe.lua uses.
--   DPISCALE lib/RenderTarget.dpi exists so the Android allocation can be
--            reproduced here.  Reported, not forced: 2.625 would make every
--            target seven times the pixels again and this probe is about
--            what the frame LOOKS like, not what it costs.
--
-- Each condition is shot at Lavender Town (the tower), inside a Poke Mart
-- (the shop) and in a city (the noise), so one run answers all three.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/phone_repro_probe.lua gen1recomp

return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/phone_repro_probe.log", "w"))
  local function log(...)
    local p = {}
    for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
    logf:write(table.concat(p, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
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

  local Quality      = lib.require("Quality")
  local Device       = lib.require("Device")
  local RenderTarget = lib.require("RenderTarget")
  local Voxel3D      = lib.require("Voxel3D")
  local RayFX        = lib.require("RayFX")
  local Weather      = lib.require("Weather")
  local DayNight     = lib.require("DayNight")
  local Wind         = lib.require("Wind")
  local MiniMap      = lib.require("MiniMap")
  local AutoFarm     = lib.require("AutoFarm")
  local ChunkMesher  = lib.require("ChunkMesher")
  local Pipelines    = require("src.render.Pipelines")

  Pipelines.setLevel("terrarium_voxel", 3)
  Pipelines.setLevel("terrarium_tiltshift", 0)
  MiniMap.setting:sync("off")
  AutoFarm.setting:sync("off")
  Weather.setting:sync("off")
  Wind.setting:sync(0)
  DayNight.setting:sync("day")

  local CLOCK = 300
  local function hold(f)
    for _ = 1, f do DayNight.clock = CLOCK; coroutine.yield() end
    DayNight.clock = CLOCK
  end

  -- ------- what this machine is, before anything is faked
  log("== the real machine ==")
  log("  " .. tostring(select(2, pcall(Device.report))))
  log(("  RenderTarget.dpi = %s"):format(tostring(RenderTarget.dpi)))
  log("")

  -- ------- force the phone's answers
  --
  -- Device.mobile is a plain function on a plain table, so it is replaced
  -- rather than mocked: everything downstream (Quality, RayFX, main.lua's
  -- FULL preset) asks the same question through the same door.
  local realMobile = Device.mobile
  Device.mobile = function() return true end
  Quality.invalidate()                 -- the pixel budget's answer changed

  local realNewShader = love.graphics.newShader
  local function withDriverRefusing(patterns, body)
    love.graphics.newShader = function(src, ...)
      for _, pat in ipairs(patterns) do
        if type(src) == "string" and src:find(pat, 1, true) then
          error("fake driver: unsupported construct (" .. pat .. ")", 0)
        end
      end
      return realNewShader(src, ...)
    end
    Voxel3D.resetShaders()
    Voxel3D.rung, Voxel3D.prec = 1, 1
    local ok, err = pcall(body)
    love.graphics.newShader = realNewShader
    Voxel3D.resetShaders()
    Voxel3D.rung, Voxel3D.prec = 1, 1
    if not ok then log("  ERROR: " .. tostring(err)) end
  end

  -- Where to stand, and what each shot is for.
  -- LAVENDER_TOWN (10,10) facing DOWN is the tower's own hero shot, lifted
  -- from tests/lavender_tower_probe.lua rather than guessed: the first run of
  -- this probe stood at (12,12) facing up and photographed the houses with
  -- the tower behind the camera.
  local SPOTS = {
    { "lavender", "LAVENDER_TOWN",  10, 10, "down" }, -- the tower
    { "mart",     "VIRIDIAN_MART",   4,  6, "up" },   -- the shop, inside
    { "water",    "CERULEAN_CITY",  16, 16, "up" },   -- the noise, on water
    { "route",    "ROUTE_1",         8, 12, "up" },   -- the noise, on grass
  }

  local function shoot(tag)
    for _, s in ipairs(SPOTS) do
      local okMap = pcall(function()
        game.overworld:setMap(s[2], s[3], s[4], s[5])
      end)
      if not okMap then
        log(("  SKIP %-9s %s"):format(s[1], s[2]))
      else
        -- poll the build rather than counting frames: a half-streamed map
        -- photographs as a missing building, which is precisely the thing
        -- this probe is trying to tell apart from a missing MODEL
        local quiet, guard = 0, 0
        while quiet < 45 and guard < 2400 do
          hold(1); guard = guard + 1
          local okP, p = pcall(ChunkMesher.pending)
          if okP and (tonumber(p) or 1) == 0 then quiet = quiet + 1 else quiet = 0 end
        end
        pcall(function() game.overworld:setMap(s[2], s[3], s[4], s[5]) end)
        hold(60)
        local shot, got = nil, false
        love.graphics.captureScreenshot(function(img) shot = img; got = true end)
        local g2 = 0
        while not got and g2 < 240 do hold(1); g2 = g2 + 1 end
        if shot then
          shot:encode("png", ("phone_%s_%s.png"):format(tag, s[1]))
          log(("  SHOT %-9s %-16s rung=%s prec=%s res=1/%d")
                :format(s[1], s[2],
                        tostring(select(2, pcall(Voxel3D.rungName))),
                        tostring(select(2, pcall(Voxel3D.precName))),
                        Quality.scale()))
        else
          log(("  FAIL %-9s no screenshot"):format(s[1]))
        end
      end
    end
  end

  -- ------- A: the phone's settings, the driver this machine actually has
  -- RES is FORCED, not left on AUTO.  The first run of this probe left it on
  -- AUTO and every shot came back at 1/1: the governor is doing its job, this
  -- machine is fast, and it climbed straight past the rung the phone is stuck
  -- on.  What is being looked at here is what 1/4 LOOKS like, so 1/4 is set.
  RayFX.setting:sync("auto")
  log(("  RTX AUTO on a 'mobile' device resolves to %s")
        :format(tostring(select(2, pcall(RayFX.level)))))
  log(("  RES AUTO would seed at 1/%d here (this panel is %s)")
        :format((function()
                   Quality.setting:sync("auto"); Quality.invalidate()
                   return Quality.scale()
                 end)(), "1536x864, not the phone's 2712x1220"))
  Quality.setting:sync(4)
  log("")
  log("== A: mobile defaults, full shader rung, RES 1/4 ==")
  shoot("A_full")
  log("")

  -- ------- B: and now the rung a conformant GLES2 driver would take
  --
  -- Ten fragment samplers against the eight GLES2 guarantees, so CRYPT_MATS
  -- comes off.  This is the case lib/Shop.lua's header describes, and if it
  -- is what the phone took then the shop and the tower's stone are supposed
  -- to be gone -- which turns "it does not load" into a known, documented
  -- consequence with a known place to fix it.
  log("== B: the same, with CRYPT_MATS refused (the 8-sampler driver) ==")
  withDriverRefusing({ "#define CRYPT_MATS 1" }, function()
    Quality.setting:sync(4)
    log(("  landed on rung %s / %s")
          :format(tostring(select(2, pcall(Voxel3D.rungName))),
                  tostring(select(2, pcall(Voxel3D.precName)))))
    shoot("B_nocrypt")
  end)
  log("")

  -- ------- C: and the mediump floor, which is where the noise would come from
  --
  -- The shadow map is an rgba8 canvas carrying a packed 16-bit depth.  Decode
  -- that at fp16 and the comparison loses about five bits, which is shadow
  -- acne -- a dense speckle over every lit surface, worst where the geometry
  -- is finest.  That is what the report describes, so it gets its own shot.
  log("== C: the same, forced to mediump uniforms ==")
  withDriverRefusing({ "#define VXHP highp" }, function()
    Quality.setting:sync(4)
    log(("  landed on rung %s / %s")
          :format(tostring(select(2, pcall(Voxel3D.rungName))),
                  tostring(select(2, pcall(Voxel3D.precName)))))
    shoot("C_mediump")
  end)

  -- ------- D: the same at RES 1/2, which is what the mod defaulted to before
  --
  -- The point of the pair: anything that looks worse in A than in D is a cost
  -- of the rung AUTO now picks, not a bug in the render path.
  log("")
  log("== D: the same, at RES 1/2 (the old default) ==")
  Quality.setting:sync(2)
  shoot("D_half")

  Device.mobile = realMobile
  Quality.setting:sync("auto")
  Quality.invalidate()
  log("")
  log("done")
  logf:close()
  love.event.quit()
end
