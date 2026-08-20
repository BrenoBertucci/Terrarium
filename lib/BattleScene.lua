-- Overworld battles: one frame of the arena, as geometry.
--
-- The same world the free-roam mode draws, from a placed camera instead of
-- the orbit, at the WINDOW's own pixel resolution -- not the GB's. The
-- backdrop reaches the screen through Renderer's worldOverride, the seam a
-- render pipeline's finished world image already composites through, which
-- is drawn one canvas pixel to one screen pixel; the 160x144 battle screen
-- then blits over it in the classic letterbox. So the world is as crisp as
-- the free-roam diorama and the pics, HUDs and text box stay exactly the
-- chunky GB art they are.
--
-- Rendering the whole window rather than just the letterbox means the
-- framing has to be split in two. The RIG frames the GB's 160x144 (see
-- BattleCam, which is solved against coordinates in that frame); this
-- module widens the lens by exactly the ratio the window bears to the
-- letterbox, so the letterbox sub-rectangle of what gets rendered is
-- bit-for-bit the framing the rig asked for, and everything outside it is
-- extra picture. That is what lets the two mons be PINNED: their cells
-- project to the same GB coordinates at any window size or zoom.
--
-- Characters are deliberately absent. The overworld cast is culled for the
-- length of the battle (see OverworldBattle), so this pass has terrain,
-- grass and flowers and nothing that walks -- the arena is empty, which is
-- what makes it an arena.
--
-- Everything expensive is shared with the free-roam mode rather than
-- duplicated: the same chunk meshes out of ChunkMesher, the same palette
-- atlas out of TerrainAtlas, the same sun out of ShadowMap. A battle on a
-- map already meshed for walking around costs the frame it draws and
-- nothing else.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local Voxel3D = V.require("Voxel3D")
local ShadowMap = V.require("ShadowMap")
local ChunkMesher = V.require("ChunkMesher")
local TerrainAtlas = V.require("TerrainAtlas")
local VoxelScene = V.require("VoxelScene")
local BattleCam = V.require("BattleCam")
local BattleBillboard = V.require("BattleBillboard")
local DayNight = V.require("DayNight")
local AntiAlias = V.require("AntiAlias")
local VoxelGrid = V.require("VoxelGrid")
local Quality = V.require("Quality")
local Wind = V.require("Wind")
local PaletteFX = require("src.render.PaletteFX")
local Map = require("src.world.Map")

local BattleScene = {}

-- ------- LET'S GO capture mode's stake in this scene
--
-- One table while a capture session runs, nil otherwise (see
-- lib/CatchThrow.lua, which owns it):
--
--   hidePlayer   the player's side stays out of the shot entirely -- no
--                card here, no model (Stadium reads this same table), no
--                pinned back pic (OverworldBattle reads it too)
--   shrink       the foe's scale while the ball drinks it in, applied
--                about its chest so it collapses toward the beam
--   draw(pull)   the Poke Ball, drawn after the Stadium models -- same
--                depth buffer, same flash window, same camera
--   cast(sm)     the same ball into the sun's pass
--   sig()        a term for the cached shadow signature, so a ball in
--                flight re-casts and a resting scene does not
--   drawGB(b)    the 2D layer (ring, labels), drawn by OverworldBattle's
--                BattleState:draw wrap in the GB frame
--
-- It lives HERE, not on OverworldBattle, because every consumer below
-- already requires BattleScene and the one file that writes it requires
-- both -- this is the spot with no require cycle.
BattleScene.capture = nil

-- The GB frame the battle screen is drawn in, and the frame BattleCam's rig
-- is solved against.
BattleScene.GB_W = 160
BattleScene.GB_H = 144

-- A map cell in world pixels: the overworld square a mon stands on, which is
-- both what the arena is measured in and what a mon is sized to.
BattleScene.CELL = 16

-- How far into black a shadow goes in the arena, against the free-roam
-- mode's own lighter setting.
BattleScene.SHADOW_ALPHA = 0.68

-- Which rung of the sky ramp an indoor void is painted with.
local INDOOR_SHADE = 4

-- ------- where the GB frame sits inside the window
function BattleScene.letterbox()
  local Renderer = require("src.render.Renderer")
  local pw, ph = BattleScene.pixelSize()
  local s = Renderer:fitScale()
  return math.floor((pw - BattleScene.GB_W * s) / 2),
         math.floor((ph - BattleScene.GB_H * s) / 2),
         s, pw, ph
end

function BattleScene.pixelSize()
  if love.graphics.getPixelDimensions then
    local pw, ph = love.graphics.getPixelDimensions()
    if pw and ph and pw > 0 and ph > 0 then return pw, ph end
  end
  return love.graphics.getDimensions()
end

function BattleScene.letterboxFov(fovGB, ph, s)
  local span = BattleScene.GB_H * s
  if span <= 0 then return fovGB end
  return 2 * math.atan(math.tan(fovGB / 2) * ph / span)
end

local function paletteFor(state, home)
  return function(map)
    return PaletteFX.pal(require("src.core.Game").data,
                         state:paletteNameFor(map or home))
  end
end

local function prefetchArena(state, host)
  if host == state.map then return VoxelScene.prefetch(state) end
  local live = { [host.id] = true, [state.map.id] = true }
  for _, nb in ipairs(state.neighbors or {}) do live[nb.map.id] = true end
  ChunkMesher.setLive(live)
  TerrainAtlas.setLive(live)
  ChunkMesher.request(host, false, nil, true)
  local terrain, water = ChunkMesher.pair(host, false)
  if not terrain then terrain, water = ChunkMesher.pair(host, true) end
  return terrain, {}, water, {}
end

local function monMatrix(tex, x, groundY, z, mirror)
  local k = BattleBillboard.FULL_W / BattleBillboard.FULL_PIC
  local w = BattleScene.GB_W * k
  local h = BattleScene.GB_H * k
  local ox = -((tex.ax / BattleScene.GB_W) - 0.5) * w
  local oy = -((BattleScene.GB_H - tex.ay) / BattleScene.GB_H) * h
  local yaw = BattleBillboard.yawToward(x, z, Voxel3D.eye)
  local card = Mat4.mul(Mat4.translate(ox, oy, 0), Mat4.scale(w, h, 1))
  if mirror then card = Mat4.mul(Mat4.scale(-1, 1, 1), card) end
  return Mat4.mul(Mat4.mul(Mat4.translate(x, groundY, z), Mat4.rotateY(yaw)), card)
end

local function monCards(arena, groundY, textures)
  local out = {}
  if not textures then return out end
  local cap = BattleScene.capture
  for _, side in ipairs({ "enemy", "player" }) do
    local tex = textures[side]
    local cell = (side == "player") and arena.player or arena.enemy
    if side == "player" and cap and cap.hidePlayer then tex = nil end
    if tex and tex.canvas and cell then
      local mirror = (side == "player") and not tex.trainer
      local model = monMatrix(tex, cell[1], groundY, cell[2], mirror)
      if side == "enemy" and cap and cap.shrink then
        local k = cap.shrink
        local ax, ay, az = cell[1], groundY + 8, cell[2]
        model = Mat4.mul(
          Mat4.mul(Mat4.translate(ax, ay, az),
                   Mat4.mul(Mat4.scale(k, k, k),
                            Mat4.translate(-ax, -ay, -az))),
          model)
      end
      out[#out + 1] = { tex = tex.canvas, model = model }
    end
  end
  return out
end

BattleScene.monCards = monCards

function BattleScene.fxCard(arena, groundY, anchors)
  local p, e = anchors.player, anchors.enemy
  local dgb = e[1] - p[1]
  if math.abs(dgb) < 1 then return nil end
  local GW, GH = BattleScene.GB_W, BattleScene.GB_H
  local Px, Py, Pz = arena.player[1], groundY, arena.player[2]
  local Ex, Ey, Ez = arena.enemy[1], groundY, arena.enemy[2]
  local s = BattleBillboard.FULL_W / BattleBillboard.FULL_PIC
  local Mx, My, Mz = (Px + Ex) / 2, groundY, (Pz + Ez) / 2

  local eye = Voxel3D.eye
  local yaw = BattleBillboard.yawToward(Mx, Mz, eye)
  local nx, nz = math.sin(yaw), math.cos(yaw)
  local rx, rz = math.cos(yaw), -math.sin(yaw)

  local function inPlane(qx_, qy_, qz_)
    if eye then
      local dqx, dqy, dqz = qx_ - eye[1], qy_ - eye[2], qz_ - eye[3]
      local denom = dqx * nx + dqz * nz
      if math.abs(denom) > 1e-6 then
        local t = ((Mx - eye[1]) * nx + (Mz - eye[3]) * nz) / denom
        qx_ = eye[1] + dqx * t
        qy_ = eye[2] + dqy * t
        qz_ = eye[3] + dqz * t
      end
    end
    return (qx_ - Mx) * rx + (qz_ - Mz) * rz, qy_ - My
  end
  
  local pax, pay = inPlane(Px, Py, Pz)
  local eax, eay = inPlane(Ex, Ey, Ez)

  if math.abs(eax - pax) < 4 then
    local ux = (Ex - Px) / dgb
    local uy = (Ey - Py - s * (p[2] - e[2])) / dgb
    local uz = (Ez - Pz) / dgb
    local cx = Px + ux * (0.5 * GW - p[1])
    local cy = Py + uy * (0.5 * GW - p[1]) + s * (p[2] - GH)
    local cz = Pz + uz * (0.5 * GW - p[1])
    local nl = math.sqrt(ux * ux + uz * uz)
    local fx, fz = 0, 1
    if nl > 1e-9 then fx, fz = uz / nl, -ux / nl end
    return { ux * GW, 0, fx, cx,
             uy * GW, s * GH, 0, cy,
             uz * GW, 0, fz, cz,
             0, 0, 0, 1 }
  end

  local ux = (eax - pax) / dgb
  local uy = (eay - pay - s * (p[2] - e[2])) / dgb
  local cxp = pax + ux * (0.5 * GW - p[1])
  local cyp = pay + uy * (0.5 * GW - p[1]) + s * (p[2] - GH)
  return { rx * ux * GW, 0, nx, Mx + rx * cxp,
           uy * GW, s * GH, 0, My + cyp,
           rz * ux * GW, 0, nz, Mz + rz * cxp,
           0, 0, 0, 1 }
end

local function shadowSignature(state, arena, terrain, nbMesh, token)
  local host = arena.map or state.map
  local parts = { "battle", host.id, arena.x, arena.y, arena.shape,
                  tostring(arena.turn or 0),
                  tostring(terrain), tostring(token or 0),
                  math.floor(ShadowMap.KX * 128),
                  math.floor(ShadowMap.KZ * 128) }
  local cap = BattleScene.capture
  if cap and cap.sig then
    local okSig, sig = pcall(cap.sig)
    parts[#parts + 1] = okSig and sig or "cap"
  end
  for i = 1, #nbMesh do parts[#parts + 1] = tostring(nbMesh[i]) end
  return table.concat(parts, ",")
end

local function castShadows(state, arena, terrain, nbMesh, cx, cy, vw, vh,
                           atlasFor, cards, token, host, neighbors,
                           water, nbWater, groundY)
  if not ShadowMap.available() then return end
  local sig = shadowSignature(state, arena, terrain, nbMesh, token)
  if not ShadowMap.stale(sig) then return end
  if not ShadowMap.begin(cx, cy, vw, vh) then return end

  local discs = arena.discs and true or false
  local drawTerrain = (not discs) or arena.showTerrain

  if discs then
    pcall(function()
      V.require("StadiumStage").cast(ShadowMap, arena, groundY or 0)
    end)
    pcall(function() V.require("Stadium").cast(ShadowMap) end)
  end

  -- Only cast map shadows if the terrain is meant to be visible
  if drawTerrain then
    local casters = Quality.neighbourShadows() and neighbors or {}

    ShadowMap.drawGroup(terrain, atlasFor(host), nil, nil)
    for i, nb in ipairs(casters) do
      ShadowMap.drawGroup(nbMesh[i], atlasFor(nb.map), Mat4.translate(nb.ox, 0, nb.oy), nil)
    end
    
    ShadowMap.draw(water, atlasFor(host), nil)
    for i, nb in ipairs(casters) do
      ShadowMap.draw(nbWater and nbWater[i], atlasFor(nb.map),
                     Mat4.translate(nb.ox, 0, nb.oy))
    end
    
    ShadowMap.draw(ChunkMesher.flowers(host), atlasFor(host),
                   ShadowMap.snug(nil))
    for _, nb in ipairs(casters) do
      ShadowMap.draw(ChunkMesher.flowers(nb.map), atlasFor(nb.map),
                     ShadowMap.snug(Mat4.translate(nb.ox, 0, nb.oy)))
    end
  end

  ShadowMap.sprites(true)
  for _, card in ipairs(cards or {}) do
    ShadowMap.draw(BattleBillboard.mesh(), card.tex,
                   ShadowMap.snug(card.model))
  end
  ShadowMap.sprites(false)
  
  local cap = BattleScene.capture
  if cap and cap.cast then pcall(cap.cast, ShadowMap) end

  ShadowMap.finish(sig)
end

function BattleScene.groundY(map, arena)
  if arena and arena.discs then return 0 end
  local ok, h = pcall(VoxelScene.groundAt, map,
                      arena.playerCell[1], arena.playerCell[2])
  return (ok and h) or 0
end

function BattleScene.toGB(vp, wx, wy, wz, lx, ly, s, pw, ph)
  local cx = vp[1] * wx + vp[2] * wy + vp[3] * wz + vp[4]
  local cy = vp[5] * wx + vp[6] * wy + vp[7] * wz + vp[8]
  local cw = vp[13] * wx + vp[14] * wy + vp[15] * wz + vp[16]
  if cw <= 1e-6 then return nil end
  local px = (cx / cw * 0.5 + 0.5) * pw
  local py = (cy / cw * 0.5 + 0.5) * ph
  return (px - lx) / s, (py - ly) / s
end

BattleScene.FLASH_COLOR = { 1, 1, 1 }
BattleScene.FLASH_STRENGTH = 0.5

local function tickTiles()
  local Game = require("src.core.Game")
  local ow = Game and Game.overworld
  local top = Game and Game.stack and Game.stack:top()
  if top and ow and top == ow then return end
  pcall(require("src.render.TileRenderer").tick)
end

function BattleScene.render(state, arena, textures, token)
  if not (state and state.map and arena) then return nil end
  if not Voxel3D.available() then return nil end
  tickTiles()

  local host = arena.map or state.map
  local neighbors = (host == state.map) and (state.neighbors or {}) or {}
  local outdoor = host.def and Map.isOutdoor(host.def) or false
  
  Voxel3D.skyAmount = outdoor and 1 or 0
  DayNight.applyRig(outdoor)
  Voxel3D.tint = DayNight.tint(outdoor or DayNight.isCanopy(host))
  
  local GlassMask = V.require("GlassMask")
  Voxel3D.glassMask = outdoor and GlassMask.texture(host.tileset) or nil
  Voxel3D.glassNight = outdoor and DayNight.windowLight() or 0
  Voxel3D.glassGlint = 0
  
  Voxel3D.lampColor = DayNight.lampColor()
  Voxel3D.lampLights = nil
  Voxel3D.lampFlicker = 0

  local ForestAtmos = V.require("ForestAtmos")
  local atmos = ForestAtmos.frame(host)
  Voxel3D.fog = atmos and { color = atmos.fog.color,
                            density = atmos.fog.density * 0.5,
                            start = atmos.fog.start,
                            heightK = atmos.fog.heightK } or nil

  local discs = arena.discs and true or false
  -- Control terrain rendering: Hides terrain for standard stadium voids, 
  -- but keeps it if requested explicitly with arena.showTerrain
  local drawTerrain = (not discs) or arena.showTerrain

  local terrain, nbMesh, water, nbWater
  if drawTerrain then
    terrain, nbMesh, water, nbWater = prefetchArena(state, host)
    if not terrain then return nil end
  else
    nbMesh, water, nbWater = {}, nil, {}
  end

  local lx, ly, s, pw, ph = BattleScene.letterbox()
  if not (pw > 0 and ph > 0 and s > 0) then return nil end

  local palette = paletteFor(state, host)
  local function atlasFor(map)
    return TerrainAtlas.forMap(map, VoxelScene._modeColors(palette, map))
  end

  local groundY = BattleScene.groundY(host, arena)
  
  local cam, pitch, capFrameH
  local cap = BattleScene.capture
  if cap and cap.rig then
    local okRig, c, p, fh = pcall(cap.rig, arena, groundY)
    if okRig and c then cam, pitch, capFrameH = c, p or math.rad(80), fh end
  end
  if not cam then cam, pitch = BattleCam.rig(arena, groundY) end
  cam.fov = BattleScene.letterboxFov(cam.fov, ph, s)

  local cx, cy = arena.mid[1], arena.mid[2]
  local vh = (capFrameH or BattleCam.frameH(arena)) * ph / (BattleScene.GB_H * s)
  local vw = vh * pw / ph

  Voxel3D.camera = cam
  Voxel3D.viewProjection(cx, cy, vw, vh)
  local cards = monCards(arena, groundY, textures)
  Voxel3D.camera = nil
  castShadows(state, arena, terrain, nbMesh, cx, cy, vw, vh, atlasFor,
              cards, token, host, neighbors, water, nbWater, groundY)

  local sky = VoxelScene.skyColor(host, 1) or VoxelScene.skyShade(INDOOR_SHADE, 1)

  if discs and VoxelScene.skyColor(host, 1) then
    local Sky = V.require("Sky")
    local okDress, dressed = pcall(Sky.dress, sky)
    if okDress and dressed then sky = dressed end
  end

  Voxel3D.camera = cam
  local sunWas = Voxel3D.SHADOW_ALPHA
  Voxel3D.SHADOW_ALPHA = BattleScene.SHADOW_ALPHA * DayNight.shadowScale(outdoor)
  
  local gridWas = VoxelGrid.override
  VoxelGrid.override = true
  
  local out = nil
  local ok, err = pcall(function()
    local rw, rh = AntiAlias.expand(pw, ph)
    if not Voxel3D.beginScene(rw, rh, cx, cy, vw, vh, sky, "battle") then
      return
    end
    
    if discs then
      V.require("StadiumStage").draw(arena, groundY)
    end
    
    -- Only draw the actual map if terrain is toggled ON
    if drawTerrain then
      Voxel3D.drawGroup(terrain, atlasFor(host), nil, nil, nil, nil)
      for i, nb in ipairs(neighbors) do
        Voxel3D.drawGroup(nbMesh[i], atlasFor(nb.map),
                          Mat4.translate(nb.ox, 0, nb.oy), nil, nil, nil)
      end
      
      if water then Voxel3D.draw(water, atlasFor(host)) end
      for i, nb in ipairs(neighbors) do
        if nbWater and nbWater[i] then
          Voxel3D.draw(nbWater[i], atlasFor(nb.map),
                       Mat4.translate(nb.ox, 0, nb.oy))
        end
      end
    end

    local flashing = textures and textures.flash
    if flashing then
      Voxel3D.flatten(BattleScene.FLASH_COLOR, BattleScene.FLASH_STRENGTH)
    end
    
    Voxel3D.seams(false)
    Voxel3D.glass(false)
    for _, card in ipairs(monCards(arena, groundY, textures)) do
      Voxel3D.draw(BattleBillboard.mesh(), card.tex, card.model,
                   BattleBillboard.PULL, ShadowMap.snug(card.model))
    end
    Voxel3D.glass(true)
    Voxel3D.seams(true)
    
    local okStadium, stadiumErr = pcall(function()
      V.require("Stadium").draw(BattleBillboard.PULL)
    end)
    if not okStadium then V.require("Stadium").report(stadiumErr) end
    
    local cap = BattleScene.capture
    if cap and cap.draw then pcall(cap.draw, BattleBillboard.PULL) end
    
    pcall(function()
      V.require("ShinyFx").draw(arena, groundY, BattleBillboard.PULL)
    end)
    
    if flashing then Voxel3D.flatten(nil) end
    
    -- Grass and Wind only process if the terrain is drawn
    if drawTerrain then
      local pull = VoxelScene.pull(math.max(pitch, 0.05))
      local sway = Wind.amount()
      local grassTex = atlasFor(host)
      do
        local ok, G = pcall(V.require, "Grass3D")
        if ok and G and G.available and G.available() and G.texture() then
          grassTex = G.texture()
        end
      end
      
      Voxel3D.draw(ChunkMesher.grass(host), grassTex, nil, pull, nil, sway)
      for _, nb in ipairs(neighbors) do
        Voxel3D.draw(ChunkMesher.grass(nb.map), grassTex,
                     Mat4.translate(nb.ox, 0, nb.oy), pull, nil, sway)
      end
      
      local fpull = math.max(0, pull - 8 * math.sin(math.max(pitch, 0.05)))
      local fsway = sway * Wind.FLOWER_SHARE
      Voxel3D.draw(ChunkMesher.flowers(host), atlasFor(host), nil, fpull,
                   ShadowMap.snug(nil), fsway)
      for _, nb in ipairs(neighbors) do
        Voxel3D.draw(ChunkMesher.flowers(nb.map), atlasFor(nb.map),
                     Mat4.translate(nb.ox, 0, nb.oy), fpull,
                     ShadowMap.snug(Mat4.translate(nb.ox, 0, nb.oy)), fsway)
      end
    end

    local canvas = AntiAlias.resolve(Voxel3D.endScene(), pw, ph, "battle")
    if not canvas then return end

    local vp = Voxel3D.vp
    local pmx, pmy = BattleScene.toGB(vp, arena.player[1], groundY, arena.player[2], lx, ly, s, pw, ph)
    local emx, emy = BattleScene.toGB(vp, arena.enemy[1], groundY, arena.enemy[2], lx, ly, s, pw, ph)
    if not (pmx and emx) then return end
    
    local half = BattleScene.CELL / 2
    local function cellSpan(wx, wz)
      local x1, y1 = BattleScene.toGB(vp, wx - half, groundY, wz, lx, ly, s, pw, ph)
      local x2, y2 = BattleScene.toGB(vp, wx + half, groundY, wz, lx, ly, s, pw, ph)
      local x3, y3 = BattleScene.toGB(vp, wx, groundY, wz - half, lx, ly, s, pw, ph)
      local x4, y4 = BattleScene.toGB(vp, wx, groundY, wz + half, lx, ly, s, pw, ph)
      if not (x1 and x2 and x3 and x4) then return nil end
      local ew = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
      local ns = math.sqrt((x4 - x3) ^ 2 + (y4 - y3) ^ 2)
      return math.max(ew, ns)
    end
    local pSpan = cellSpan(arena.player[1], arena.player[2])
    local eSpan = cellSpan(arena.enemy[1], arena.enemy[2])
    if not (pSpan and eSpan) then return end
    
    out = {
      canvas = canvas,
      player = { pmx, pmy },
      enemy = { emx, emy },
      playerSpan = pSpan,
      enemySpan = eSpan,
      lx = lx, ly = ly, scale = s, pw = pw, ph = ph,
      eye = { cam.eye[1], cam.eye[2], cam.eye[3] },
      focus = { cam.focus[1], cam.focus[2], cam.focus[3] },
      vp = vp,
      -- and the hour's light, for anything drawn over this shot that is NOT
      -- geometry and so never went past the shader that applied it -- the back
      -- pic pinned to the menu (see OverworldBattle.backPinned). Neutral
      -- indoors, which is what DayNight.tint answers for a room.
      tint = Voxel3D.tint,
    }
  end)
  -- the placed camera is ours for exactly this pass; anything else that
  -- renders (the free-roam pipeline, next frame) must find the orbit back
  Voxel3D.camera = nil
  Voxel3D.SHADOW_ALPHA = sunWas
  VoxelGrid.override = gridWas
  if not ok then
    -- endScene never ran, so the canvas is still bound and the shader still
    -- set; put the frame back the way it was found before rethrowing
    pcall(love.graphics.setShader)
    pcall(love.graphics.setDepthMode)
    pcall(love.graphics.setCanvas)
    error(err, 0)
  end
  return out
end

return BattleScene