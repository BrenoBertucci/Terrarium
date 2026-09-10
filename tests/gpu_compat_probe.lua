-- Probe: does the 3D pass build on THIS driver, and does its fallback ladder
-- catch a driver that refuses part of it?
--
-- Two questions, and the second is the one that has never been asked. Android
-- players reported the mode simply not coming up -- no error, no crash, the
-- OPTIONS row still reading ON. That is Voxel3D.available() returning false,
-- which is exactly "the scene shader did not build", and the shader is one
-- 26 KB monolith: any single construct the driver refuses takes the whole
-- diorama with it.
--
-- Two constructs in it are refusable by a conformant GLES2 driver:
--
--   * the VERTEX stage samples three textures (waterField, crushMap,
--     wearMap). GLES2 may expose ZERO vertex texture image units, and a
--     vertex shader that samples on such a driver does not read vec4(0) --
--     it fails to LINK.
--   * the fragment stage binds ten samplers where GLES2 guarantees eight.
--
-- Voxel3D.shader() now walks a ladder, dropping one of those per rung. This
-- probe checks the ladder two ways:
--
--   BUILD    every rung compiles. A desktop GL takes rung 1 and the lower
--            rungs are never reached, so a GLSL error inside an #ifdef that
--            only fires on the devices that NEED the fallback would ship
--            undetected -- the same class of bug over again.
--   REFUSE   a fake driver that says no to the constructs an Adreno part
--            says no to, stood up in front of the real ladder. This is the
--            only honest answer available here to "does the fallback work",
--            because no machine in this room has the GPU that motivated it.
--
--   POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/gpu_compat_probe.lua \
--   ./gen1recomp.exe
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/gpu_compat_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

  local fails = 0
  local function check(ok, what)
    if not ok then fails = fails + 1 end
    log((ok and "PASS " or "FAIL ") .. what)
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
    log("FAIL: TERRARIUM not loaded -- the mod itself did not come up.")
    log("      That is a Lua error at load, not a shader problem.")
    logf:close(); love.event.quit(); return
  end
  local Voxel3D = lib.require("Voxel3D")

  -- ------- 1. the device report, verbatim
  --
  -- This is the block a player is asked to paste into a bug report, so it is
  -- printed here exactly as they would see it -- if it is unreadable or
  -- missing a field, that shows up now rather than in a support thread.
  log("---------------- Voxel3D.report() ----------------")
  log(Voxel3D.report())
  log("--------------------------------------------------")
  check(#Voxel3D.report() > 40, "report() returns something worth pasting")

  -- ------- 2. every rung builds on this driver
  local derivs = select(2, pcall(love.graphics.getSupported))
  local hasDerivs = derivs and derivs.shaderderivatives == true
  for i = 1, (Voxel3D.rungCount or 0) do
   for p = 1, (Voxel3D.precCount or 1) do
    for _, grid in ipairs({ false, true }) do
      local ok, info = Voxel3D.buildRung(i, grid, p)
      local tag = "rung " .. i .. "/prec " .. p .. (grid and " +grid" or "")
      if not ok and grid and not hasDerivs then
        -- The wireframe legitimately refuses where the driver has no shader
        -- derivatives. A device fact, not this probe's business.
        log("skip " .. tag .. ": no shader derivatives on this driver")
      else
        check(ok, tag .. " (" .. tostring(info):gsub("\n", " | ") .. ")")
      end
    end
   end
  end

  -- ------- 3. the mode came up here, at the top rung
  check(Voxel3D.available(), "Voxel3D.available() on this driver")
  check(Voxel3D.rung == 1,
        "settled on rung 1 (" .. tostring(Voxel3D.rungName())
        .. ") -- a desktop GL should need no fallback")
  check(#Voxel3D.compileLog == 0,
        "no refusals recorded (" .. #Voxel3D.compileLog .. ")")

  -- ------- 4. THE FAKE ADRENO
  --
  -- newShader is replaced by one that refuses any source carrying the define
  -- for a construct the simulated driver does not have, and the ladder is
  -- made to start over. Each case names the rung it must land on and what
  -- must still be true afterwards: the mode ON, and a refusal on record.
  --
  -- The last case is the floor -- a driver that refuses something the ladder
  -- has no answer for. It has to end with available() false and FOUR recorded
  -- refusals, because that is the state a bug report is written from, and it
  -- is the only outcome here that is still allowed to lose the mode.
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
    local ok, err = pcall(body)
    love.graphics.newShader = realNewShader
    Voxel3D.resetShaders()
    if not ok then error(err, 0) end
  end

  local CASES = {
    { name  = "no vertex texture units (the Adreno report)",
      block = { "#define VERTEX_TEX 1" },
      rung  = 2, expect = "no-vtf" },
    { name  = "only 8 fragment samplers",
      block = { "#define CRYPT_MATS 1" },
      rung  = 3, expect = "no-crypt" },
    { name  = "neither",
      block = { "#define VERTEX_TEX 1", "#define CRYPT_MATS 1" },
      rung  = 4, expect = "minimal" },
  }
  for _, c in ipairs(CASES) do
    withDriverRefusing(c.block, function()
      local sh = Voxel3D.shader()
      check(sh ~= nil, "[" .. c.name .. "] the mode still builds")
      check(Voxel3D.rung == c.rung and Voxel3D.rungName() == c.expect,
            "[" .. c.name .. "] landed on rung " .. c.rung .. " "
            .. c.expect .. " (got " .. Voxel3D.rung .. " "
            .. tostring(Voxel3D.rungName()) .. ")")
      check(Voxel3D.available(), "[" .. c.name .. "] available() stays true")
      check(#Voxel3D.compileLog == c.rung - 1,
            "[" .. c.name .. "] " .. (c.rung - 1) .. " refusal(s) recorded, "
            .. "not swallowed (" .. #Voxel3D.compileLog .. ")")
      local rep = Voxel3D.report()
      check(rep:find("fake driver", 1, true) ~= nil,
            "[" .. c.name .. "] the driver's own words reach report()")
    end)
  end

  -- ------- 4b. THE STRICT DRIVER (the Mali report)
  --
  -- The one the rung ladder could not catch. GLSL ES 1.00 links a uniform by
  -- precision as well as by name; the vertex stage defaults to highp and LOVE
  -- gives the fragment stage `precision mediump float;`, so every uniform the
  -- water block declares -- and both stages declare them, because the vertex
  -- displaces the sheet and the fragment repaints it -- was highp on one side
  -- and mediump on the other. Desktop GL has no precision qualifiers at all
  -- and Adreno waves it through; Mali reads the spec and refuses the LINK.
  --
  -- The refusal landed on all four rungs at once, which is why the ladder
  -- built for the Adreno report did nothing for it: there was no rung left to
  -- fall to. So precision is now a walk of its own, OUTSIDE the rungs, and
  -- this case is the one that proves the fall works.
  withDriverRefusing({ "#define VXHP highp" }, function()
    local sh = Voxel3D.shader()
    check(sh ~= nil, "[strict uniform precision] the mode still builds")
    check(Voxel3D.precName() == "mediump",
          "[strict uniform precision] fell to mediump uniforms (got "
          .. tostring(Voxel3D.precName()) .. ")")
    check(Voxel3D.rung == 1,
          "[strict uniform precision] and kept every feature -- precision is "
          .. "not a rung (got rung " .. Voxel3D.rung .. ")")
    check(Voxel3D.available(),
          "[strict uniform precision] available() stays true")
  end)

  -- ------- THE FRAGMENT STAGE'S fp32 DEFAULT, REFUSED
  --
  -- This is the case that matters most, because the thing it guards already
  -- shipped broken once.  1.34.0-beta put `precision highp float;` into the
  -- pixel stage unconditionally and the whole 3D mode stopped coming up on
  -- the phone -- LOVE forward-declares `effect` at its own mediump default
  -- BEFORE the mod's source, and a definition whose parameters disagree with
  -- its prototype does not compile on GLES.  Desktop cannot see it: there the
  -- qualifiers are #defined to nothing and the two agree trivially.
  --
  -- So FRAG_HIGHP became a rung of its own, and a rung is only worth having
  -- if dropping it is TESTED.  A driver that refuses it must land on the fp16
  -- fragment stage every Android build has always run, with the mode ON and
  -- every feature intact -- a picture with static in it rather than no
  -- picture.
  withDriverRefusing({ "#define FRAG_HIGHP 1" }, function()
    local sh = Voxel3D.shader()
    check(sh ~= nil, "[no fragment highp] the mode still builds")
    check(Voxel3D.fragName() == "fp16",
          "[no fragment highp] fell to the fp16 fragment stage (got "
          .. tostring(Voxel3D.fragName()) .. ")")
    check(Voxel3D.rung == 1 and Voxel3D.precName() == "highp",
          "[no fragment highp] and gave up NOTHING else (got rung "
          .. Voxel3D.rung .. " / " .. tostring(Voxel3D.precName()) .. ")")
    check(Voxel3D.available(), "[no fragment highp] available() stays true")
    -- TWO fragment rungs carry that define now -- the raised default and
    -- the named list -- so a driver that refuses the define refuses both:
    -- two modes at each of two uniform precisions at each of four rungs.
    check(#Voxel3D.compileLog == 16,
          "[no fragment highp] all sixteen refused squares are on record ("
          .. #Voxel3D.compileLog .. ")")
  end)

  -- ------- THE RAISED DEFAULT REFUSED, THE NAMED LIST KEPT
  --
  -- This is the Mali-G615 exactly: it refused `precision highp float;` on
  -- every square in 1.34.1-beta, and then accepted every VXFP declaration in
  -- 1.34.2-beta without a single refusal.  So the middle rung is not a
  -- theoretical one -- it is the rung that device actually lands on, and the
  -- only reason it still gets fp32 anywhere at all.
  withDriverRefusing({ "#define VX_GLOBAL_HP 1" }, function()
    local sh = Voxel3D.shader()
    check(sh ~= nil, "[no raised default] the mode still builds")
    check(Voxel3D.fragName() == "fp32-lite",
          "[no raised default] fell to the NAMED declarations, not to fp16 "
          .. "(got " .. tostring(Voxel3D.fragName()) .. ")")
    check(Voxel3D.rung == 1 and Voxel3D.precName() == "highp",
          "[no raised default] and gave up nothing else (got rung "
          .. Voxel3D.rung .. " / " .. tostring(Voxel3D.precName()) .. ")")
    check(Voxel3D.available(), "[no raised default] available() stays true")
    check(#Voxel3D.compileLog == 8,
          "[no raised default] the eight refused squares are on record ("
          .. #Voxel3D.compileLog .. ")")
  end)

  -- Blocked on a line the SHADER source ALWAYS carries, not on a define. The
  -- first version of this used "#define SUN_ONE_TAP", which the build only
  -- emits when soft shadows are off -- so on a machine with them on the fake
  -- driver refused nothing and the case passed by not running.
  withDriverRefusing({ "varying float vShade;" }, function()
    local sh = Voxel3D.shader()
    check(sh == nil, "[nothing builds] shader() gives up rather than lying")
    check(not Voxel3D.available(), "[nothing builds] available() is false")
    -- Four rungs, at each of two uniform precisions, at each of THREE
    -- answers to "how does the fragment stage get its fp32" -- raise the
    -- default, raise the named declarations, or neither: twenty-four
    -- squares.  The ladder has to have tried every one before it is allowed
    -- to give up, and a bug report written from here should show all of
    -- them.  (Eight, then sixteen, now twenty-four; the number is spelled
    -- out rather than computed so that adding a rung and not thinking about
    -- it fails this test.)
    check(#Voxel3D.compileLog == 24,
          "[nothing builds] all twenty-four refusals on record ("
          .. #Voxel3D.compileLog .. ")")
    local rep = Voxel3D.report()
    check(rep:find("OFF", 1, true) ~= nil,
          "[nothing builds] report() says the mode is off")
    log("---- what a player would be asked to paste ----")
    log(rep)
    log("----------------------------------------------")
  end)

  -- ------- 5. and the real driver is back
  check(Voxel3D.available() and Voxel3D.rung == 1,
        "the real driver is restored after the fakes")

  log("")
  log(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  logf:close()
  love.event.quit()
end
