-- Probe: the UlithiumDragon Center+Mart front-facing sprite (B05
-- `pokecenter`, t.sprite) end to end. Logs every link of the chain so a
-- silent fallback to the Gen1 kit -- or an empty lot -- is named, not
-- guessed:
--   1. mod:read on the PNG (bytes)          -> the file reaches the mod
--   2. love.image.newImageData(bytes)       -> LOVE decodes it
--   3. Buildings.spriteImage(rel)           -> GPU image bound
--   4. Buildings.stats()["OVERWORLD:N"]     -> voxelized (voxels/shell/quads)
--   5. Structures.forMap(map).spriteQuads   -> stamped on this map
--   6. ChunkMesher.sprites/spriteTex(map)   -> mesh + texture at draw time
--   7. Voxel3D.shader / shaderError         -> the 3D pass is really up
-- plus a screenshot per city with the player standing under the Center.
--
-- POKEPORT_VERSION=yellow DS_PROBE_DIR=<dir> \
-- POKEPORT_DRIVER=mods/TERRARIUM/tests/pokecenter_sprite_probe.lua gen1recomp
return function(game)
  local OUT = os.getenv("DS_PROBE_DIR") or "."
  local logf = assert(io.open(OUT .. "/pokecenter_sprite_probe.log", "w"))
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
    if n > 900 then log("FAIL: no overworld") logf:close() love.event.quit()
      return end
  end
  n = 0
  while game.stack:top() ~= game.overworld do
    tap("a"); wait(10); n = n + 11
    if n > 1500 then log("FAIL: never reached free roam") break end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.TERRARIUM and exports.TERRARIUM.lib
  if not lib then
    log("FAIL: TERRARIUM not loaded"); logf:close(); love.event.quit()
    return
  end
  log("version:", exports.TERRARIUM.version)

  local DayNight = lib.require("DayNight")
  local Weather = lib.require("Weather")
  local Voxel3D = lib.require("Voxel3D")
  local Structures = lib.require("Structures")
  local Buildings = lib.require("Buildings")
  local ChunkMesher = lib.require("ChunkMesher")

  Weather.setting:sync("off")
  DayNight.setting:sync("day")
  local ww, wh = love.graphics.getDimensions()
  log(("window: %dx%d"):format(ww, wh))

  local REL = "assets/buildings/ulithium_poke_center_mart.png"

  -- 1. raw bytes through the sanctioned mod API
  do
    local mod = lib.mod
    log("lib.mod:", tostring(mod), "mod.read:", tostring(mod and mod.read))
    if mod and mod.read then
      local ok, bytes = pcall(mod.read, mod, REL)
      log(("1 mod:read ok=%s type=%s bytes=%s"):format(tostring(ok),
          type(bytes), type(bytes) == "string" and #bytes or tostring(bytes)))
      -- 2. decode
      if ok and type(bytes) == "string" then
        local okB, bd = pcall(love.data.newByteData, bytes)
        log("2a newByteData ok=", okB, tostring(bd))
        if okB then
          local okI, id = pcall(love.image.newImageData, bd)
          log("2b newImageData(ByteData) ok=", okI, tostring(id))
          if okI and id and id.getDimensions then
            local w, h = id:getDimensions()
            local r, g, b, a = id:getPixel(math.floor(w / 2), math.floor(h / 2))
            log(("2c dims %dx%d centre rgba=%.2f %.2f %.2f %.2f"):format(
                w, h, r, g, b, a))
          end
        end
        local okF, fd = pcall(love.filesystem and love.filesystem.newFileData
                              or function() error("no lf") end, bytes, "x.png")
        log("2d newFileData ok=", okF, tostring(fd))
      end
    end
  end

  -- 3. GPU image as the mesher will look it up
  do
    local ok, img = pcall(Buildings.spriteImage, REL)
    log("3 spriteImage ok=", ok, tostring(img))
    if ok and img and img.getDimensions then
      local w, h = img:getDimensions()
      log(("3 spriteImage dims %dx%d"):format(w, h))
    end
  end

  local function shot(name)
    local done = false
    love.graphics.captureScreenshot(function(data)
      local f = io.open(OUT .. "/" .. name, "wb")
      if f then f:write(data:encode("png"):getString()) f:close() end
      done = true
    end)
    for _ = 1, 600 do
      if done then return true end
      coroutine.yield()
    end
    return false
  end

  local function voxelUp(guard)
    for _ = 1, guard or 900 do
      if Voxel3D.lampLights ~= nil then return true end
      coroutine.yield()
    end
    return false
  end

  local function lockCell(guard)
    local last, stable = nil, 0
    for _ = 1, guard or 1200 do
      local p = game.overworld.player
      local cur = p and (tostring(p.cellX) .. "," .. tostring(p.cellY)) or "?"
      if cur == last then stable = stable + 1 else stable, last = 0, cur end
      if stable >= 45 then return true, cur end
      coroutine.yield()
    end
    return false, last
  end

  -- player two cells south of each Center's door (B05 door = (x+1, y+3))
  local CITIES = {
    { id = "VIRIDIAN_CITY", x = 23, y = 27 },
    { id = "PEWTER_CITY", x = 13, y = 27 },
  }

  for _, c in ipairs(CITIES) do
    local ok, err = pcall(function()
      game.overworld:setMap(c.id, c.x, c.y, "up")
    end)
    if not ok then
      log(c.id, "FAIL: setMap error", tostring(err))
    else
      wait(60)
      local map = game.overworld.map
      log("")
      log(("[%s] map=%s tileset=%s"):format(c.id, tostring(map.id),
          tostring(map.tileset and map.tileset.id)))
      log("  voxel pass up:", voxelUp() and "PASS" or "FAIL")
      local locked, cell = lockCell()
      log(("  player cell locked: %s at (%s)"):format(
          locked and "PASS" or "FAIL", tostring(cell)))
      wait(200)

      -- 4. models built
      local okS, stats = pcall(Buildings.stats)
      if okS and stats then
        local keys = {}
        for k in pairs(stats) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
          local st = stats[k]
          log(("  4 model %s voxels=%s shell=%s quads=%s"):format(k,
              tostring(st.voxels), tostring(st.shell), tostring(st.quads)))
        end
      else
        log("  4 Buildings.stats FAIL", tostring(stats))
      end

      -- 5. stamped quads on this map
      local S = Structures.forMap(map)
      local own = 0
      for _, q in ipairs(S.objectQuads) do if q.own then own = own + 1 end end
      local sq = S.spriteQuads
      log(("  5 objectQuads=%d (building own=%d) spriteQuads=%s tex=%s")
          :format(#S.objectQuads, own, sq and #sq or "nil",
                  sq and sq[1] and tostring(sq[1].tex) or "nil"))
      if sq and sq[1] then
        local q = sq[1]
        log(("  5 spriteQuads[1] = (%s,%s,%s) uv=%s,%s,%s,%s shade=%s"):format(
            q[1][1], q[1][2], q[1][3],
            q.uv and q.uv[1], q.uv and q.uv[2], q.uv and q.uv[3],
            q.uv and q.uv[4], tostring(q.shade)))
        local ymax, ymin = -1e9, 1e9
        for _, qq in ipairs(sq) do
          for i = 1, 4 do
            if qq[i][2] > ymax then ymax = qq[i][2] end
            if qq[i][2] < ymin then ymin = qq[i][2] end
          end
        end
        log(("  5 spriteQuads y range %s..%s"):format(ymin, ymax))
      end

      -- 6. mesher slots
      local okM, mesh = pcall(ChunkMesher.sprites, map)
      local okT, tex = pcall(ChunkMesher.spriteTex, map)
      log(("  6 ChunkMesher.sprites ok=%s %s | spriteTex ok=%s %s"):format(
          tostring(okM), tostring(mesh), tostring(okT), tostring(tex)))
      if okM and mesh and mesh.getVertexCount then
        log("  6 mesh vertices:", mesh:getVertexCount(),
            "texture:", tostring(mesh:getTexture()))
      end

      -- 6b. the mesher's slot is empty: rebuild the SAME mesh here, with
      -- the error kept instead of swallowed, so the failing link is named
      if not (okM and mesh) and sq and #sq > 0 then
        log(("  6b lua mem before: %.1f MB"):format(
            collectgarbage("count") / 1024))
        local okR, err = pcall(function()
          local verts, indices, n = {}, {}, 0
          for _, q in ipairs(sq) do
            for i = 1, 4 do
              local c = q[i]
              local uv = q.uv and q.uv[i] or { q.u, q.v }
              verts[#verts + 1] = { c[1], c[2], c[3], uv[1], uv[2], q.shade }
            end
            Voxel3D.pushQuad(indices, n)
            n = n + 1
          end
          log(("  6b verts=%d indices=%d mem=%.1f MB"):format(#verts,
              #indices, collectgarbage("count") / 1024))
          local okN, m = pcall(love.graphics.newMesh, Voxel3D.FORMAT, verts,
                               "triangles", "static")
          log("  6b newMesh ok=", okN, tostring(m))
          if okN and m then
            local okV, e2 = pcall(m.setVertexMap, m, indices)
            log("  6b setVertexMap ok=", okV, tostring(e2))
            local okD, e3 = pcall(m.getVertexMap, m)
            log("  6b vertex map read ok=", okD,
                okD and (e3 and #e3 or "nil") or tostring(e3))
          end
          local m2 = Voxel3D.newMesh(verts, indices)
          log("  6b Voxel3D.newMesh ->", tostring(m2))
        end)
        log("  6b replicate ok=", okR, tostring(err))
        log(("  6b lua mem after: %.1f MB"):format(
            collectgarbage("count") / 1024))
      end

      -- 7. shader status
      local okSh, sh = pcall(Voxel3D.shader)
      log(("  7 shader ok=%s %s err=%s"):format(tostring(okSh), tostring(sh),
          tostring(Voxel3D.shaderError)))

      log("  shot:", shot(c.id .. "_center.png") and "PASS" or "FAIL")
    end
  end

  log("")
  log("DONE")
  logf:close()
  love.event.quit()
end
