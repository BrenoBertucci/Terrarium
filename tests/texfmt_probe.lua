-- Probe: what compressed texture formats this machine can actually take,
-- and how much texture the mod is carrying in the first place.
--
-- Asked because "convert the textures to KTX2 / DDS" is a reasonable thing
-- to want and an unreasonable thing to assume. Three facts decide it and
-- none of them can be guessed from here:
--
--   1  which compressed formats LOVE reports on THIS GPU
--   2  what the mod's own images actually cost decoded
--   3  whether that number is anywhere near the frame budget
--
-- Fast: no walking, no weather, no screenshots. Reaches free roam, asks,
-- writes, quits.
--
--   POKEPORT_VERSION=yellow \
--   DS_PROBE_DIR=<dir> \
--   POKEPORT_DRIVER=mods/TERRARIUM/tests/texfmt_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/texfmt_probe.log", "w"))
  local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    logf:write(table.concat(parts, " "), "\n"); logf:flush()
  end
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function tap(b)
    game.input.pressQueue[#game.input.pressQueue + 1] = b; coroutine.yield()
  end

  local n = 0
  while not (game.overworld and game.stack and game.stack:top()) do
    wait(1); n = n + 1
    if n > 900 then log("FAIL: no overworld") logf:close()
      love.event.quit() return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end

  log(("love %d.%d.%d (%s)"):format(love.getVersion()))
  local ok, name, ver, vendor, dev = pcall(love.graphics.getRendererInfo)
  if ok then
    log(("renderer: %s %s"):format(tostring(name), tostring(ver)))
    log(("gpu:      %s %s"):format(tostring(vendor), tostring(dev)))
  end

  -- ------- 1. what the driver will take
  log("--- compressed formats reported by love.graphics.getImageFormats")
  local okf, formats = pcall(love.graphics.getImageFormats)
  if okf and type(formats) == "table" then
    -- The ones that matter for a 2D mod's art: BC7 is what a DDS export
    -- would target on a desktop GPU, DXT5 is the old universal one, and
    -- ASTC/ETC2 are the mobile families this build also ships to.
    local want = { "DXT1", "DXT3", "DXT5", "BC4", "BC5", "BC6H", "BC7",
                   "ETC1", "ETC2rgb", "ETC2rgba", "ASTC4x4", "PVR1rgba4" }
    local have, missing = {}, {}
    for _, f in ipairs(want) do
      if formats[f] then have[#have + 1] = f else missing[#missing + 1] = f end
    end
    log("supported:   " .. (#have > 0 and table.concat(have, " ") or "(none)"))
    log("unsupported: " .. (#missing > 0 and table.concat(missing, " ") or "(none)"))
    local all = 0
    for _ in pairs(formats) do all = all + 1 end
    log("total formats reported: " .. all)
  else
    log("getImageFormats unavailable on this build")
  end

  -- KTX2 is a CONTAINER, not a format, and it is not one LOVE reads --
  -- love.image opens .dds / .ktx (v1) / .pvr / .astc. Recorded here so the
  -- question does not have to be re-asked from memory.
  log("container support: .dds yes, .ktx (v1) yes, .ktx2 NO (love.image)")

  -- ------- 2. what the mod's own art costs decoded
  log("--- the mod's images, decoded (w*h*4 bytes -- what the GPU holds)")
  local files = {
    "assets/ground/grass/grass.png",
    "assets/ground/lamppost/lamppost.png",
    "assets/water/water.png",
    "assets/ground/print.png",
    "assets/ground/puddle.png",
    "assets/ground/snow-crust-1.png",
    "assets/ground/snow-crust-2.png",
    "assets/ground/snow-crust-3.png",
    "assets/ground/snow-ground-1.png",
    "assets/ground/snow-ground-2.png",
    "assets/ground/snow-ground-3.png",
  }
  local mod = game.mods and game.mods.exports and game.mods.exports.TERRARIUM
  local root = (mod and mod.path) or "mods/TERRARIUM"
  local total = 0
  for _, rel in ipairs(files) do
    local path = root .. "/" .. rel
    local okd, data = pcall(love.image.newImageData, path)
    if okd and data then
      local w, h = data:getWidth(), data:getHeight()
      local bytes = w * h * 4
      total = total + bytes
      log(("  %-42s %4dx%-4d  %7.1f KB"):format(rel, w, h, bytes / 1024))
    else
      log(("  %-42s (not readable from here)"):format(rel))
    end
  end
  log(("total decoded: %.2f MB"):format(total / 1048576))
  log(("at BC7 (4 bits/px, 1/8 of RGBA8): %.2f MB -- saving %.2f MB")
        :format(total / 8 / 1048576, total * 7 / 8 / 1048576))

  log("")
  log("Read this against the frame budget, not on its own: a saving in "
      .. "texture memory is a saving in BANDWIDTH and VRAM. It does not "
      .. "touch vertex work, and the grass pass is vertex work.")

  logf:close()
  love.event.quit()
end
