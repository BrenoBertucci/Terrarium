-- The move cards: thick pixel plates, alive in pixel art.
--
-- Drawn to the battle concepts (Chama Impetuosa, Impulso Voltaico, Lamina
-- Glacial, Jato Corrente, Onda Mental): a cream card with a dark stepped
-- pixel rim and a visible thickness, its type on a coloured tab with a
-- pixel icon, and -- on the raised card only -- the element wrapped round
-- it: a glow hugging the rim, ribbons of the element orbiting the card
-- (behind it on one side, in front of it on the other), glowing pixel
-- squares drifting off, and the type's own set piece: lightning crawling
-- the edges, ice crystals grown out of the corners, a water drop, rings of
-- psychic light. Confirming a move plays the concept's use strip: the card
-- charges, is thrown at the foe with its element trailing, and bursts.
--
-- PIXEL ART, FLUID: every effect here is geometry rasterised into an
-- offscreen canvas at a fraction of the window's resolution (Vox.PIXEL) and
-- blown back up with nearest filtering -- so a ribbon, a bolt, a glow band
-- come out as hard pixels on a fixed grid while their positions move
-- continuously. A soft copy of the same canvas (linear, four taps, added)
-- is the bloom. Nothing is a sprite sheet on a clock: motion is as smooth
-- as the frame rate.
--
-- The face is for reading. What stands behind the hand is drawn before the
-- cards (the cards cover it); in front, nothing is ever laid across a
-- card's face -- a ribbon or a square passing over one is taken to pass
-- behind it.
--
-- Same footing as the fan: world points projected with the shot's own
-- matrix, drawn on the finished frame -- the effects parallax with the
-- drift and swing with the attack camera exactly as the cards do.
-- Presentational only; every entry point is pcall'd by its caller.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Vox = {}

Vox.ENABLED = true

local sin, cos, floor, sqrt = math.sin, math.cos, math.floor, math.sqrt
local abs, max, min, pi, exp = math.abs, math.max, math.min, math.pi, math.exp
local TAU = pi * 2

-- ------- the knobs (world pixels: a map cell is 16, a card 4.6 x 6.4)
Vox.PIXEL = 3              -- window pixels per effect pixel
Vox.BLOOM = 0.20           -- per tap of the eight-tap bloom
Vox.BLOOM_TAP = 1.6        -- effect pixels
Vox.SLAB = 0.30            -- the card's thickness: stacked plates behind it
-- the glow round the raised card's rim: outward reach (world px), alpha
Vox.GLOW = { { 0.10, 0.95 }, { 0.22, 0.55 }, { 0.38, 0.28 }, { 0.58, 0.12 } }
Vox.RIB_SEGS = 34
Vox.MAX_PARTS = 240
Vox.FX_VERTS = 30000
Vox.CHARGE_TIME = 0.30
Vox.THROW_TIME = 0.46
Vox.FOLD_TIME = 0.30
Vox.GROW = 0.35            -- seconds for the set pieces to come up
Vox.TEXT_ZONE = 0.80       -- the part of a face nothing is drawn across (its text)

local W3 = { 1, 1, 1 }

-- ------- per type: the card's colours
--
-- tab: the header band; ink: the type word on it; bar: the PP meter, a
-- gradient from empty end to full end; glow: the rim light and ribbons;
-- hot: the brightest core (the ribbon heads, the rim's inner band).
Vox.PAL = {
  FIRE = { tab = { 0.98, 0.80, 0.72 }, ink = { 0.55, 0.12, 0.06 },
           bar = { { 0.86, 0.16, 0.10 }, { 1.0, 0.58, 0.12 }, { 1.0, 0.86, 0.26 } },
           glow = { 1.0, 0.48, 0.10 }, hot = { 1.0, 0.92, 0.55 } },
  ELECTRIC = { tab = { 0.98, 0.86, 0.26 }, ink = { 0.20, 0.17, 0.05 },
               bar = { { 0.95, 0.76, 0.06 }, { 1.0, 0.92, 0.25 } },
               glow = { 1.0, 0.86, 0.22 }, hot = { 1.0, 1.0, 0.80 } },
  ICE = { tab = { 0.80, 0.92, 0.96 }, ink = { 0.12, 0.22, 0.32 },
          bar = { { 0.32, 0.62, 0.92 }, { 0.62, 0.88, 1.0 } },
          glow = { 0.50, 0.78, 1.0 }, hot = { 0.92, 0.98, 1.0 } },
  WATER = { tab = { 0.78, 0.90, 0.97 }, ink = { 0.10, 0.22, 0.34 },
            bar = { { 0.20, 0.58, 0.90 }, { 0.45, 0.86, 0.98 } },
            glow = { 0.32, 0.68, 1.0 }, hot = { 0.85, 0.96, 1.0 } },
  PSYCHIC = { tab = { 0.94, 0.76, 0.89 }, ink = { 0.28, 0.10, 0.24 },
              bar = { { 0.88, 0.28, 0.64 }, { 0.98, 0.52, 0.82 } },
              glow = { 0.95, 0.38, 0.85 }, hot = { 1.0, 0.82, 0.96 } },
  GRASS = { tab = { 0.80, 0.93, 0.70 }, ink = { 0.12, 0.30, 0.08 },
            bar = { { 0.30, 0.66, 0.18 }, { 0.58, 0.88, 0.32 } },
            glow = { 0.45, 0.90, 0.30 }, hot = { 0.85, 1.0, 0.70 } },
  POISON = { tab = { 0.88, 0.76, 0.92 }, ink = { 0.30, 0.08, 0.34 },
             bar = { { 0.56, 0.22, 0.64 }, { 0.78, 0.46, 0.86 } },
             glow = { 0.70, 0.35, 0.95 }, hot = { 0.90, 0.75, 1.0 } },
  GROUND = { tab = { 0.95, 0.87, 0.68 }, ink = { 0.40, 0.26, 0.08 },
             bar = { { 0.72, 0.52, 0.22 }, { 0.92, 0.78, 0.44 } },
             glow = { 0.95, 0.72, 0.35 }, hot = { 1.0, 0.92, 0.70 } },
  ROCK = { tab = { 0.88, 0.84, 0.70 }, ink = { 0.34, 0.28, 0.12 },
           bar = { { 0.58, 0.50, 0.28 }, { 0.80, 0.72, 0.46 } },
           glow = { 0.85, 0.72, 0.42 }, hot = { 1.0, 0.92, 0.72 } },
  FIGHTING = { tab = { 0.96, 0.76, 0.70 }, ink = { 0.50, 0.10, 0.06 },
               bar = { { 0.72, 0.14, 0.10 }, { 0.95, 0.40, 0.26 } },
               glow = { 1.0, 0.42, 0.22 }, hot = { 1.0, 0.86, 0.70 } },
  FLYING = { tab = { 0.86, 0.84, 0.98 }, ink = { 0.22, 0.20, 0.45 },
             bar = { { 0.52, 0.48, 0.90 }, { 0.78, 0.76, 1.0 } },
             glow = { 0.72, 0.74, 1.0 }, hot = { 0.97, 0.97, 1.0 } },
  BUG = { tab = { 0.88, 0.92, 0.66 }, ink = { 0.28, 0.32, 0.04 },
          bar = { { 0.55, 0.64, 0.10 }, { 0.78, 0.88, 0.30 } },
          glow = { 0.72, 0.88, 0.22 }, hot = { 0.95, 1.0, 0.65 } },
  GHOST = { tab = { 0.82, 0.78, 0.92 }, ink = { 0.22, 0.14, 0.38 },
            bar = { { 0.40, 0.30, 0.62 }, { 0.62, 0.52, 0.86 } },
            glow = { 0.60, 0.45, 0.95 }, hot = { 0.88, 0.80, 1.0 } },
  DRAGON = { tab = { 0.80, 0.76, 0.98 }, ink = { 0.20, 0.10, 0.50 },
             bar = { { 0.40, 0.22, 0.92 }, { 0.62, 0.52, 1.0 } },
             glow = { 0.50, 0.40, 1.0 }, hot = { 0.82, 0.80, 1.0 } },
  NORMAL = { tab = { 0.92, 0.90, 0.80 }, ink = { 0.30, 0.28, 0.20 },
             bar = { { 0.62, 0.60, 0.44 }, { 0.84, 0.82, 0.66 } },
             glow = { 1.0, 0.92, 0.62 }, hot = { 1.0, 1.0, 0.88 } },
}

local LABEL_PT = {
  NORMAL = "NORMAL", FIRE = "FOGO", WATER = "ÁGUA", GRASS = "PLANTA",
  ELECTRIC = "ELÉTRICO", ICE = "GELO", FIGHTING = "LUTADOR",
  POISON = "VENENO", GROUND = "TERRA", FLYING = "VOADOR",
  PSYCHIC = "PSÍQUICO", BUG = "INSETO", ROCK = "PEDRA", GHOST = "FANTASMA",
  DRAGON = "DRAGÃO",
}

-- ------- the type icons on the tab, pixel masks (a digit is a palette entry)
Vox.ICONS = {
  FIRE = { pal = { { 0.72, 0.10, 0.04 }, { 1.0, 0.42, 0.06 }, { 1.0, 0.80, 0.22 }, { 1.0, 0.97, 0.72 } },
    rows = { ".....1.....", "....12.....", "....121....", "...1221..1.", "...12221.1.",
             "..1223221..", "..12333221.", ".1223443221", ".1234443321", ".1234444321",
             "..12344321.", "...122221..", "....1111..." } },
  WATER = { pal = { { 0.08, 0.26, 0.70 }, { 0.22, 0.52, 0.95 }, { 0.52, 0.78, 1.0 }, { 0.95, 0.99, 1.0 } },
    rows = { ".....1.....", ".....1.....", "....121....", "....121....", "...12221...",
             "...12221...", "..1222221..", "..1242221..", ".122432221.", ".122322221.",
             ".122222221.", "..1222221..", "...11111..." } },
  GRASS = { pal = { { 0.10, 0.38, 0.10 }, { 0.28, 0.66, 0.18 }, { 0.55, 0.88, 0.30 }, { 0.62, 0.48, 0.20 } },
    rows = { ".........11", ".......1221", ".....12232.", "....122331.", "...122331..",
             "..12233121.", "..1233221..", ".123322221.", ".13322221..", ".1322221...",
             "..42221....", ".4.111.....", "4.........." } },
  ELECTRIC = { pal = { { 0.30, 0.22, 0.02 }, { 1.0, 0.84, 0.14 }, { 1.0, 1.0, 0.82 } },
    rows = { "......1111.", ".....1221..", "....1231...", "...1231....", "..1233111..",
             ".12333321..", "..1113331..", "....1321...", "...1231....", "..1231.....",
             "..121......", ".121.......", ".11........" } },
  ICE = { pal = { { 0.30, 0.60, 0.88 }, { 0.40, 0.70, 0.96 }, { 0.80, 0.95, 1.0 } },
    rows = { ".....2.....", "...2.2.2...", "....222....", ".2...2...2.", "..2..2..2..",
             "...2.2.2...", "22222322222", "...2.2.2...", "..2..2..2..", ".2...2...2.",
             "....222....", "...2.2.2...", ".....2....." } },
  ROCK = { pal = { { 0.28, 0.23, 0.18 }, { 0.48, 0.40, 0.30 }, { 0.64, 0.56, 0.43 }, { 0.80, 0.74, 0.60 } },
    rows = { "...11111...", "..1233321..", ".123443221.", "12344332221", "12343322221",
             "12333222211", "12232222121", ".1222221221", ".12221122..", "..111111..." } },
  GROUND = { pal = { { 0.42, 0.27, 0.10 }, { 0.80, 0.62, 0.30 }, { 0.95, 0.82, 0.50 } },
    rows = { ".....1.....", "....121....", "...12321...", "..1233321..", "..1232321..",
             ".123222321.", ".122232221.", "12223222221", "11111111111" } },
  POISON = { pal = { { 0.22, 0.06, 0.28 }, { 0.56, 0.24, 0.62 }, { 0.80, 0.55, 0.86 }, { 0.55, 1.0, 0.35 } },
    rows = { "..1111111..", ".122333221.", "12233333221", "12311311321", "12314314321",
             "12311311321", ".122232221.", "..1222221..", "..1313131..", "..1212121..",
             "...11111..." } },
  PSYCHIC = { pal = { { 0.55, 0.12, 0.40 }, { 0.95, 0.45, 0.75 }, { 1.0, 0.76, 0.90 }, { 1.0, 1.0, 1.0 } },
    rows = { "...11111...", "..1222221..", ".122111221.", "12213331221", "12133333121",
             "12133433121", "12133333121", "12213331221", ".122111221.", "..1222221..",
             "...11111..." } },
  GHOST = { pal = { { 0.22, 0.14, 0.36 }, { 0.48, 0.34, 0.72 }, { 0.72, 0.62, 0.94 }, { 1.0, 1.0, 1.0 }, { 0.10, 0.06, 0.16 } },
    rows = { "...11111...", "..1233321..", ".123333321.", ".134333431.", "12344334421",
             "12333333321", "12335553321", "12333333321", "12333333321", "12323232321",
             ".1.1.1.1.1." } },
  FIGHTING = { pal = { { 0.48, 0.07, 0.05 }, { 0.84, 0.17, 0.11 }, { 1.0, 0.46, 0.36 }, { 0.96, 0.93, 0.88 } },
    rows = { "..111111...", ".12222221..", "1223322221.", "1233322221.", "1233222221.",
             "1222222211.", "12222222121", ".1222221221", "..111112221", "...14441221",
             "...144411..", "...14441...", "...11111..." } },
  FLYING = { pal = { { 0.45, 0.48, 0.66 }, { 0.76, 0.73, 0.96 }, { 1.0, 1.0, 1.0 } },
    rows = { "1..........", "21.........", "321........", "3321.......", "33321......",
             "233321.....", "2333321....", ".23333321..", "..233333321", "...22333332",
             "....1122221", "......1111." } },
  BUG = { pal = { { 0.18, 0.28, 0.05 }, { 0.60, 0.72, 0.15 }, { 0.82, 0.92, 0.36 }, { 0.12, 0.10, 0.08 } },
    rows = { "...4...4...", "....4.4....", "...12221...", "..1233321..", "4.1223221.4",
             ".412232214.", "..1222221..", "4.1223221.4", ".412232214.", "..1222221..",
             "...12221...", "....111...." } },
  DRAGON = { pal = { { 0.18, 0.10, 0.45 }, { 0.44, 0.22, 0.97 }, { 0.66, 0.56, 1.0 }, { 1.0, 0.85, 0.20 }, { 1.0, 1.0, 1.0 } },
    rows = { ".1.........", ".21..1.....", ".221.21....", "..22122111.", "..222222221",
             ".1232422221", "12333222221", "1233222111.", "12322221...", ".1255511...",
             "..11111...." } },
  NORMAL = { pal = { { 0.74, 0.58, 0.24 }, { 0.97, 0.90, 0.62 }, { 1.0, 1.0, 0.92 } },
    rows = { ".....1.....", "....121....", "....131....", "11112321111", ".123333321.",
             "..1233321..", "..1232321..", ".1231.1321.", ".121...121.", ".1.......1." } },
}

-- ------- small masks for the drifting matter: 1 the colour, 2 its light
Vox.MASKS = {
  snow = { "...2...", ".2.1.2.", "..111..", "2111112", "..111..", ".2.1.2.", "...2..." },
  drop = { "..1..", "..1..", ".121.", ".121.", "11211", "11111", ".111." },
  leaf = { "...11", ".1121", "11211", "1211.", "21..." },
  star = { "..1..", "..2..", "12221", "..2..", "..1.." },
  bubble = { ".111.", "12..1", "1...1", "1...1", ".111." },
  feather = { ".1.", "121", "121", "121", "121", ".1.", ".1." },
  wisp = { ".11.", "1221", "1221", ".11.", ".1..", "..1." },
  spark = { ".1.", "121", ".1." },
  -- the water card's own drop, big and shaded (1 deep, 2 body, 3 light)
  bigdrop = { "....1....", "....1....", "...121...", "...121...", "..12221..",
              "..12221..", ".1222221.", ".1322221.", "132222221", "132222221",
              "133222221", ".1322221.", "..11111.." },
}

-- ------- per type: what wraps the raised card
--
-- ribbons: an orbit round the card. `a` turns the hoop about the card's up
-- (so one side passes in front, one behind), `tilt` leans it about the
-- card's right, `rx`/`ry` its radii in half-extents, `speed` rad/s, `len`
-- the trail in radians, `width` world px, `rise` a spiral along the card's
-- up (world px per radian), `wob` a wave on it, `full` a whole ring with
-- `base` alpha and a bright travelling head. `head`/`tail` colour the trail.
-- parts: the drifting pixel matter (see emitOne). set: the set piece.
Vox.FX = {
  FIRE = {
    ribbons = {
      { a = 40, tilt = 12, rx = 1.95, ry = 1.25, speed = 2.6, len = 3.6, width = 0.95, rise = 0.30,
        head = { 1.0, 0.96, 0.60 }, tail = { 0.92, 0.22, 0.04 }, core = { 1, 1, 0.85 } },
      { a = -36, tilt = -16, rx = 1.85, ry = 1.12, speed = -2.1, len = 3.0, width = 0.70, phase = 2.2,
        head = { 1.0, 0.84, 0.32 }, tail = { 0.82, 0.16, 0.04 }, core = { 1, 0.95, 0.7 } },
    },
    parts = { rate = 40, px = { 2, 3 }, from = "rim", up = { 2, 5 }, spread = 2.2, grav = -8,
              drag = 1.2, life = { 0.6, 1.2 }, flicker = true, floor = "die",
              ramp = { { 1, 0.97, 0.70 }, { 1, 0.70, 0.16 }, { 0.92, 0.28, 0.06 }, { 0.40, 0.20, 0.16 } } },
    shed = 24,
  },
  ELECTRIC = {
    ribbons = {},
    parts = { rate = 30, px = { 1, 3 }, from = "around", out = 1, spread = 2.5, grav = 0, drag = 1,
              zap = 6, life = { 0.4, 0.9 }, twinkle = true, floor = "die",
              ramp = { { 1, 1, 0.85 }, { 1, 0.86, 0.20 } } },
    set = "bolts",
  },
  ICE = {
    ribbons = {
      { a = 42, tilt = 10, rx = 1.95, ry = 1.22, speed = 1.5, len = 4.4, width = 0.55,
        head = { 1.0, 1.0, 1.0 }, tail = { 0.45, 0.72, 1.0 }, core = { 1, 1, 1 } },
    },
    parts = { rate = 16, px = { 1, 2 }, from = "around", up = { -0.6, 0.4 }, spread = 1.2, grav = 3,
              drag = 1.5, wobble = 1.2, life = { 1.4, 2.4 }, twinkle = true, floor = "settle",
              ramp = { { 1, 1, 1 }, { 0.72, 0.90, 1 } }, mask = { "snow", 0.5 } },
    set = "crystals",
  },
  WATER = {
    ribbons = {
      { a = 40, tilt = 18, rx = 1.95, ry = 1.30, speed = 2.3, len = 3.8, width = 0.85, rise = 0.45,
        head = { 0.95, 1.0, 1.0 }, tail = { 0.16, 0.50, 0.95 }, core = { 1, 1, 1 } },
      { a = -36, tilt = -14, rx = 1.85, ry = 1.18, speed = -1.9, len = 3.2, width = 0.70, phase = 3.0,
        rise = -0.3, head = { 0.90, 0.98, 1.0 }, tail = { 0.20, 0.55, 0.95 }, core = { 1, 1, 1 } },
    },
    parts = { rate = 18, px = { 2, 4 }, from = "around", up = { -0.3, 0.6 }, spread = 0.8, grav = 0,
              drag = 1.6, wobble = 0.8, life = { 1.2, 2.2 }, floor = "die", alpha = 0.85,
              ramp = { { 0.80, 0.94, 1 }, { 0.45, 0.78, 1 } } },
    shed = 8,
    set = "drop",
  },
  PSYCHIC = {
    ribbons = {
      { a = 0, tilt = 76, rx = 1.60, ry = 0.95, cy = -0.35, speed = 1.7, len = TAU, width = 0.30,
        full = true, base = 0.50, head = { 1.0, 0.88, 0.98 }, tail = { 0.92, 0.30, 0.80 } },
      { a = 0, tilt = 68, rx = 1.85, ry = 1.10, cy = 0.05, speed = -1.2, len = TAU, width = 0.26,
        full = true, base = 0.42, phase = 1.5, head = { 1.0, 0.82, 0.98 }, tail = { 0.85, 0.28, 0.85 } },
      { a = 0, tilt = 82, rx = 1.38, ry = 0.80, cy = 0.42, speed = 2.3, len = TAU, width = 0.22,
        full = true, base = 0.40, phase = 3.1, head = { 1.0, 0.92, 1.0 }, tail = { 0.95, 0.40, 0.88 } },
    },
    parts = { rate = 24, px = { 1, 4 }, from = "around", up = { 0.3, 1.2 }, spread = 1, grav = -1,
              drag = 1.2, life = { 1.0, 1.8 }, twinkle = true, floor = "die",
              ramp = { { 1, 0.75, 0.95 }, { 0.90, 0.40, 0.85 } } },
  },
  GRASS = {
    ribbons = {
      { a = 40, tilt = 10, rx = 1.95, ry = 1.25, speed = 2.0, len = 3.4, width = 0.60, rise = 0.25,
        head = { 0.85, 1.0, 0.60 }, tail = { 0.20, 0.55, 0.12 }, core = { 0.95, 1, 0.8 } },
    },
    parts = { rate = 7, px = { 1, 1 }, from = "top", up = { 0.5, 2 }, spread = 3, grav = 6, drag = 1.8,
              wobble = 2.2, life = { 2.0, 3.0 }, floor = "settle",
              ramp = { { 0.55, 0.88, 0.30 }, { 0.30, 0.66, 0.18 } }, mask = { "leaf", 1 } },
    shed = 5,
  },
  BUG = {
    ribbons = {
      { a = 40, tilt = 6, rx = 1.9, ry = 1.2, speed = 3.0, len = 2.6, width = 0.45, wob = 0.25,
        head = { 0.95, 1.0, 0.55 }, tail = { 0.45, 0.55, 0.08 }, core = { 1, 1, 0.8 } },
    },
    parts = { rate = 12, px = { 1, 2 }, from = "rim", out = 3, spread = 2, grav = 0, drag = 0.4,
              zap = 5, life = { 1.0, 1.8 }, floor = "die",
              ramp = { { 0.70, 0.82, 0.20 }, { 0.30, 0.40, 0.08 } } },
  },
  POISON = {
    ribbons = {
      { a = 40, tilt = 14, rx = 1.9, ry = 1.25, speed = 1.8, len = 3.4, width = 0.65, wob = 0.18,
        head = { 0.88, 0.70, 1.0 }, tail = { 0.40, 0.10, 0.50 }, core = { 0.95, 0.85, 1 } },
    },
    parts = { rate = 10, px = { 1, 2 }, from = "foot", up = { 2, 4 }, spread = 1.2, grav = -2,
              drag = 1.2, wobble = 1.6, life = { 1.0, 1.6 }, pop = true, floor = "die",
              ramp = { { 0.80, 0.55, 0.95 }, { 0.60, 1.0, 0.45 } }, mask = { "bubble", 1 } },
  },
  GROUND = {
    ribbons = {
      { a = 44, tilt = 4, rx = 2.0, ry = 1.1, speed = 1.6, len = 3.8, width = 0.75, rise = -0.2,
        head = { 1.0, 0.90, 0.62 }, tail = { 0.55, 0.36, 0.14 }, core = { 1, 0.96, 0.8 } },
    },
    parts = { rate = 9, px = { 1, 3 }, from = "foot", up = { 1, 5 }, spread = 3, grav = 60, drag = 0.4,
              life = { 1.2, 2.0 }, floor = "bounce",
              ramp = { { 0.92, 0.78, 0.46 }, { 0.62, 0.45, 0.22 } } },
  },
  ROCK = {
    ribbons = {
      { a = 42, tilt = 8, rx = 1.95, ry = 1.2, speed = 1.4, len = 3.2, width = 0.70,
        head = { 0.95, 0.88, 0.66 }, tail = { 0.45, 0.38, 0.26 }, core = { 1, 0.95, 0.8 } },
    },
    parts = { rate = 7, px = { 2, 3 }, from = "foot", up = { -1, 1.5 }, spread = 2, grav = 70,
              drag = 0.1, life = { 1.6, 2.4 }, floor = "bounce",
              ramp = { { 0.70, 0.62, 0.48 }, { 0.46, 0.38, 0.28 } } },
  },
  FIGHTING = {
    ribbons = {
      { a = 40, tilt = 10, rx = 1.9, ry = 1.25, speed = 3.2, len = 2.4, width = 0.75,
        head = { 1.0, 0.92, 0.70 }, tail = { 0.85, 0.16, 0.08 }, core = { 1, 1, 0.9 } },
    },
    parts = { rate = 8, px = { 1, 2 }, from = "rim", out = 5, spread = 2, grav = 18, drag = 1,
              life = { 0.5, 0.9 }, floor = "die",
              ramp = { { 1, 0.88, 0.60 }, { 0.95, 0.30, 0.15 } }, mask = { "spark", 0.5 } },
    set = "beat",
  },
  FLYING = {
    ribbons = {
      { a = 40, tilt = 20, rx = 2.0, ry = 1.3, speed = 3.0, len = 2.8, width = 0.40, rise = 0.5,
        head = { 1, 1, 1 }, tail = { 0.62, 0.66, 0.95 }, core = { 1, 1, 1 } },
      { a = -36, tilt = -12, rx = 1.85, ry = 1.15, speed = 2.6, len = 2.4, width = 0.32, phase = 2.5,
        head = { 1, 1, 1 }, tail = { 0.70, 0.72, 1.0 } },
    },
    parts = { rate = 6, px = { 1, 1 }, from = "rim", out = 1.5, up = { 2, 4 }, spread = 1, grav = -1,
              drag = 0.6, spiral = 5, life = { 1.4, 2.2 }, floor = "settle",
              ramp = { { 1, 1, 1 } }, mask = { "feather", 1 } },
  },
  GHOST = {
    ribbons = {
      { a = 40, tilt = 16, rx = 1.9, ry = 1.3, speed = 1.3, len = 4.0, width = 0.70, wob = 0.3,
        head = { 0.90, 0.80, 1.0 }, tail = { 0.30, 0.18, 0.55 }, core = { 0.95, 0.9, 1 } },
    },
    parts = { rate = 6, px = { 1, 1 }, from = "foot", up = { 1.5, 3 }, spread = 1.5, grav = -1.5,
              drag = 0.8, wobble = 2.4, life = { 1.4, 2.2 }, fade = true, floor = "die",
              ramp = { { 0.85, 0.75, 1 }, { 0.50, 0.36, 0.72 } }, mask = { "wisp", 1 } },
  },
  DRAGON = {
    ribbons = {
      { a = 40, tilt = 14, rx = 1.95, ry = 1.3, speed = 2.4, len = 3.6, width = 0.75, rise = 0.35,
        head = { 0.88, 0.84, 1.0 }, tail = { 0.35, 0.18, 0.90 }, core = { 0.95, 0.95, 1 } },
      { a = -36, tilt = -14, rx = 1.85, ry = 1.2, speed = -2.4, len = 3.2, width = 0.62, phase = 3.1,
        head = { 0.72, 0.92, 1.0 }, tail = { 0.15, 0.40, 0.95 }, core = { 0.9, 1, 1 } },
    },
    parts = { rate = 14, px = { 1, 3 }, from = "foot", up = { 3, 6 }, spread = 0.6, grav = -2,
              drag = 0.5, spiral = 9, life = { 0.8, 1.3 }, floor = "die",
              ramp = { { 0.75, 0.66, 1 }, { 0.44, 0.22, 0.97 }, { 0.30, 0.60, 1 } } },
  },
  NORMAL = {
    ribbons = {
      { a = 40, tilt = 10, rx = 1.9, ry = 1.25, speed = 1.8, len = 3.2, width = 0.50,
        head = { 1, 1, 0.92 }, tail = { 0.78, 0.66, 0.36 }, core = { 1, 1, 1 } },
    },
    parts = { rate = 8, px = { 1, 1 }, from = "around", spread = 0.5, grav = 0, drag = 2,
              life = { 0.6, 1.1 }, twinkle = true, floor = "die",
              ramp = { { 1, 1, 0.9 }, { 0.97, 0.86, 0.50 } }, mask = { "star", 0.6 } },
  },
}

-- ------- lazy siblings
local Fan, Box, Lang = nil, nil, nil
local function fan()
  if Fan == nil then
    local ok, F = pcall(V.require, "BattleFanXY")
    Fan = (ok and F) or false
  end
  return Fan or nil
end
local function box()
  if Box == nil then
    local ok, B = pcall(V.require, "BattleBoxXY")
    Box = (ok and B) or false
  end
  return Box or nil
end
local function pick(en, pt)
  if Lang == nil then
    local ok, L = pcall(V.require, "Lang")
    Lang = (ok and L) or false
  end
  return (Lang and Lang.pick) and Lang.pick(en, pt) or en
end
Vox.pick = pick

local function clock()
  return (love.timer and love.timer.getTime and love.timer.getTime()) or 0
end

local function clamp01(x) return x < 0 and 0 or (x > 1 and 1 or x) end
local function mix(a, b, t)
  return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

-- the card's colours for a type (derived from the type colour when a type
-- has no entry of its own)
function Vox.palette(tname)
  local p = Vox.PAL[tname or ""]
  if p then return p end
  local B = box()
  local tc = (B and tname and B.TYPE_COLOR[tname]) or { 0.66, 0.66, 0.47 }
  return { tab = mix(tc, W3, 0.55), ink = mix(tc, { 0, 0, 0 }, 0.6),
           bar = { mix(tc, { 0, 0, 0 }, 0.15), mix(tc, W3, 0.3) },
           glow = tc, hot = mix(tc, W3, 0.6) }
end

function Vox.typeLabel(tname)
  if not tname then return pick("MOVE", "GOLPE") end
  return pick(tname, LABEL_PT[tname] or tname)
end

-- Draw a type's icon into whatever canvas is bound, `h` tall (whole pixels
-- of the mask), right edge at `right`. Answers the width it took.
function Vox.icon(tname, right, y, h)
  local ic = Vox.ICONS[tname or ""] or Vox.ICONS.NORMAL
  local rows = ic.rows
  local H, Wd = #rows, 0
  for _, r in ipairs(rows) do Wd = max(Wd, #r) end
  local k = max(1, floor(h / H))
  local x = right - Wd * k
  local g = love.graphics
  for ry, r in ipairs(rows) do
    for rx = 1, #r do
      local c = ic.pal[tonumber(r:sub(rx, rx)) or 0]
      if c then
        g.setColor(c[1], c[2], c[3], 1)
        g.rectangle("fill", x + (rx - 1) * k, y + (ry - 1) * k, k, k)
      end
    end
  end
  g.setColor(1, 1, 1, 1)
  return Wd * k
end

-- Deterministic: a probe's frames must repeat, so nothing here draws on
-- math.random. Park-Miller stays inside a double's exact integers.
local seed = 20260924
local function rnd()
  seed = (seed * 16807) % 2147483647
  return seed / 2147483647
end
local function range(t) return t[1] + (t[2] - t[1]) * rnd() end

local function hash(a, b)
  local s = sin(a * 127.1 + b * 311.7) * 43758.5453
  return s - floor(s)
end

local function easeOutBack(t)
  if t <= 0 then return 0 end
  if t >= 1 then return 1 end
  local x = t - 1
  return 1 + 2.70158 * x * x * x + 1.70158 * x * x
end

-- ------- vectors
local function vadd(a, b, k)
  k = k or 1
  return { a[1] + b[1] * k, a[2] + b[2] * k, a[3] + b[3] * k }
end
local function vnorm(v)
  local d = sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
  if d < 1e-6 then return { 0, 0, 0 } end
  return { v[1] / d, v[2] / d, v[3] / d }
end
local function vcross(a, b)
  return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3],
           a[1] * b[2] - a[2] * b[1] }
end
local function vrot(v, a, ang)
  local c, s = cos(ang), sin(ang)
  local dot = v[1] * a[1] + v[2] * a[2] + v[3] * a[3]
  local cr = vcross(a, v)
  return { v[1] * c + cr[1] * s + a[1] * dot * (1 - c),
           v[2] * c + cr[2] * s + a[2] * dot * (1 - c),
           v[3] * c + cr[3] * s + a[3] * dot * (1 - c) }
end

-- ------- state
local S = {
  frame = 0, fanFrame = -1, lastFan = -1, prevPhase = nil,
  pose = {},          -- [i] = the card as last drawn
  quads = {},         -- [i] = its face on screen, 4 corners
  sel = nil, selType = nil, selAt = 0,
  parts = {}, bursts = {}, flights = {},
  back = {},          -- [i] = the slab's plate slots
  emitAcc = 0, shedAcc = 0, lastEmit = nil, lastStep = nil, beat = nil,
  groundY = 0, map = nil, floorCache = {}, handDepth = nil, ctx = nil,
  dbg = { slabs = 0, parts = 0, type = nil, flights = 0, launches = 0,
          folds = 0, fxverts = 0, ribbons = 0, bursts = 0 },
}

function Vox.debug()
  S.dbg.parts = #S.parts
  S.dbg.flights = #S.flights
  S.dbg.bursts = #S.bursts
  return S.dbg
end

function Vox.clear()
  S.parts, S.bursts, S.flights = {}, {}, {}
  S.map, S.floorCache, S.handDepth = nil, {}, nil
  S.pose, S.sel, S.prevPhase, S.quads = {}, nil, nil, {}
end

-- ------- projection
local function context(shot)
  local F = fan()
  if not (F and shot and shot.vp) then return nil end
  local R = F.rig(shot)
  if not R then return nil end
  S.groundY = shot.groundY or S.groundY
  return { vp = shot.vp, pw = shot.pw, ph = shot.ph, eye = shot.eye,
           right = R.right, up = R.up, dir = R.dir, groundY = shot.groundY or 0,
           shot = shot, cw = F.CARD_W, ch = F.CARD_H }
end

local function projXY(ctx, x, y, z)
  local vp = ctx.vp
  local cw = vp[13] * x + vp[14] * y + vp[15] * z + vp[16]
  if cw <= 1e-6 then return nil end
  return ((vp[1] * x + vp[2] * y + vp[3] * z + vp[4]) / cw * 0.5 + 0.5) * ctx.pw,
         ((vp[5] * x + vp[6] * y + vp[7] * z + vp[8]) / cw * 0.5 + 0.5) * ctx.ph
end

local function inQuad(q, x, y)
  local sign = 0
  for k = 0, 3 do
    local j = (k + 1) % 4
    local x1, y1 = q[k * 2 + 1], q[k * 2 + 2]
    local x2, y2 = q[j * 2 + 1], q[j * 2 + 2]
    local c = (x2 - x1) * (y - y1) - (y2 - y1) * (x - x1)
    if c ~= 0 then
      local sg = c > 0 and 1 or -1
      if sign == 0 then sign = sg elseif sg ~= sign then return false end
    end
  end
  return true
end

-- over the READING part of a face: its rectangle pulled in off the rim,
-- so a ribbon may pass over a card's border (as in the concepts) but never
-- over what the card says
local function overFace(x, y)
  for _, q in pairs(S.quads) do
    if q and inQuad(q, x, y) then return true end
  end
  return false
end

local guard = nil
local function overGuard(x, y)
  return guard ~= nil and inQuad(guard, x, y)
end

local function normalOf(ctx, center, cr, cu)
  local n = vnorm(vcross(cr, cu))
  local e = ctx.eye
  if n[1] * (e[1] - center[1]) + n[2] * (e[2] - center[2])
     + n[3] * (e[3] - center[3]) < 0 then
    n = { -n[1], -n[2], -n[3] }
  end
  return n
end

-- a card-local point: x, y in WORLD px along the card's right and up, f
-- along its facing
local function onCard(pose, x, y, f)
  local c, cr, cu, n = pose.center, pose.cr, pose.cu, pose.n
  f = f or 0
  return { c[1] + cr[1] * x + cu[1] * y + n[1] * f,
           c[2] + cr[2] * x + cu[2] * y + n[2] * f,
           c[3] + cr[3] * x + cu[3] * y + n[3] * f }
end

-- ------- the pixel canvas: a triangle batch rasterised at 1/PIXEL
local fb = { pool = {}, slice = {}, n = 0, last = 0 }
local bx0, by0, bx1, by1 = 0, 0, 0, 0
local fxCanvas, fxW, fxH, fxQuad = nil, 0, 0, nil

local function fxReset()
  fb.n = 0
  bx0, by0, bx1, by1 = math.huge, math.huge, -math.huge, -math.huge
end
fxReset()

-- one vertex, in EFFECT pixels
local function fvert(x, y, r, g, b, a)
  if fb.n >= Vox.FX_VERTS then return end
  fb.n = fb.n + 1
  local t = fb.pool[fb.n]
  if not t then t = { 0, 0, 0, 0, 1, 1, 1, 1 }; fb.pool[fb.n] = t end
  t[1], t[2] = x, y
  t[5], t[6], t[7], t[8] = clamp01(r), clamp01(g), clamp01(b), clamp01(a)
  fb.slice[fb.n] = t
  if x < bx0 then bx0 = x end
  if x > bx1 then bx1 = x end
  if y < by0 then by0 = y end
  if y > by1 then by1 = y end
end

-- a quad from four WINDOW points, two colours: c1 on 1-2, c2 on 3-4
local function fquad2(x1, y1, x2, y2, x3, y3, x4, y4, c1, a1, c2, a2)
  local k = 1 / Vox.PIXEL
  x1, y1, x2, y2 = x1 * k, y1 * k, x2 * k, y2 * k
  x3, y3, x4, y4 = x3 * k, y3 * k, x4 * k, y4 * k
  fvert(x1, y1, c1[1], c1[2], c1[3], a1)
  fvert(x2, y2, c1[1], c1[2], c1[3], a1)
  fvert(x3, y3, c2[1], c2[2], c2[3], a2)
  fvert(x1, y1, c1[1], c1[2], c1[3], a1)
  fvert(x3, y3, c2[1], c2[2], c2[3], a2)
  fvert(x4, y4, c2[1], c2[2], c2[3], a2)
end

local function fquad(x1, y1, x2, y2, x3, y3, x4, y4, c, a)
  fquad2(x1, y1, x2, y2, x3, y3, x4, y4, c, a, c, a)
end

local function ftri(x1, y1, x2, y2, x3, y3, c, a)
  local k = 1 / Vox.PIXEL
  fvert(x1 * k, y1 * k, c[1], c[2], c[3], a)
  fvert(x2 * k, y2 * k, c[1], c[2], c[3], a)
  fvert(x3 * k, y3 * k, c[1], c[2], c[3], a)
end

-- a square on the effect grid itself: the pixel art's own unit
local function fpix(px, py, s, c, a)
  local x, y = floor(px + 0.5), floor(py + 0.5)
  fvert(x, y, c[1], c[2], c[3], a); fvert(x + s, y, c[1], c[2], c[3], a)
  fvert(x + s, y + s, c[1], c[2], c[3], a); fvert(x, y, c[1], c[2], c[3], a)
  fvert(x + s, y + s, c[1], c[2], c[3], a); fvert(x, y + s, c[1], c[2], c[3], a)
end

-- a mask centred on (px, py) effect pixels, `k` effect pixels a cell
local function fmask(rows, px, py, k, c, light, a)
  local H, Wd = #rows, #rows[1]
  local x0 = floor(px - Wd * k * 0.5 + 0.5)
  local y0 = floor(py - H * k * 0.5 + 0.5)
  for ry = 1, H do
    local r = rows[ry]
    for rx = 1, #r do
      local ch = r:byte(rx)
      if ch == 49 then fpix(x0 + (rx - 1) * k, y0 + (ry - 1) * k, k, c, a)
      elseif ch == 50 then fpix(x0 + (rx - 1) * k, y0 + (ry - 1) * k, k, light, a)
      elseif ch == 51 then fpix(x0 + (rx - 1) * k, y0 + (ry - 1) * k, k, W3, a) end
    end
  end
end

-- a thick segment between two WORLD points lying in a plane whose in-plane
-- perpendicular is `perp` (world), `w` world px wide, colour per end
local function fseg(ctx, p1, p2, perp, w1, w2, c1, a1, c2, a2)
  local h1, h2 = w1 * 0.5, w2 * 0.5
  local ax, ay = projXY(ctx, p1[1] - perp[1] * h1, p1[2] - perp[2] * h1, p1[3] - perp[3] * h1)
  local bx, by = projXY(ctx, p1[1] + perp[1] * h1, p1[2] + perp[2] * h1, p1[3] + perp[3] * h1)
  local cx, cy = projXY(ctx, p2[1] + perp[1] * h2, p2[2] + perp[2] * h2, p2[3] + perp[3] * h2)
  local dx, dy = projXY(ctx, p2[1] - perp[1] * h2, p2[2] - perp[2] * h2, p2[3] - perp[3] * h2)
  if not (ax and bx and cx and dx) then return end
  fquad2(ax, ay, bx, by, cx, cy, dx, dy, c1, a1, c2, a2)
end

local TAPS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 },
               { -1.4, -1.4 }, { 1.4, -1.4 }, { -1.4, 1.4 }, { 1.4, 1.4 } }

-- Rasterise the batch at 1/PIXEL and lay it on the frame: the soft copy
-- first (the bloom), then the hard pixels.
local function fxFlush(ctx)
  if fb.n == 0 then return end
  local g = love.graphics
  local P = Vox.PIXEL
  local cw, ch = math.ceil(ctx.pw / P), math.ceil(ctx.ph / P)
  if not fxCanvas or fxW ~= cw or fxH ~= ch then
    local ok, c = pcall(g.newCanvas, cw, ch, { dpiscale = 1 })
    if not (ok and c) then fxReset(); return end
    fxCanvas, fxW, fxH = c, cw, ch
    fxQuad = g.newQuad(0, 0, cw, ch, cw, ch)
  end
  if not fb.mesh then
    local ok, m = pcall(g.newMesh, Vox.FX_VERTS, "triangles", "stream")
    if not (ok and m) then fxReset(); return end
    fb.mesh = m
  end
  for i = fb.n + 1, fb.last do fb.slice[i] = nil end
  fb.last = fb.n
  fb.mesh:setVertices(fb.slice)
  fb.mesh:setDrawRange(1, fb.n)
  S.dbg.fxverts = S.dbg.fxverts + fb.n
  local prev = g.getCanvas()
  local pb, pa = g.getBlendMode()
  local sx, sy, sw, sh = g.getScissor()
  g.setScissor()
  g.setCanvas(fxCanvas)
  g.clear(0, 0, 0, 0)
  g.push()
  g.origin()
  g.setBlendMode("alpha")
  g.setColor(1, 1, 1, 1)
  g.draw(fb.mesh)
  g.pop()
  g.setCanvas(prev)
  if sx then g.setScissor(sx, sy, sw, sh) end
  local pad = 4
  local x0 = max(0, floor(bx0) - pad)
  local y0 = max(0, floor(by0) - pad)
  local x1 = min(cw, math.ceil(bx1) + pad)
  local y1 = min(ch, math.ceil(by1) + pad)
  if x1 > x0 and y1 > y0 then
    fxQuad:setViewport(x0, y0, x1 - x0, y1 - y0, cw, ch)
    fxCanvas:setFilter("linear", "linear")
    g.setBlendMode("add", "premultiplied")
    local b, t = Vox.BLOOM, Vox.BLOOM_TAP
    g.setColor(b, b, b, b)
    for _, o in ipairs(TAPS) do
      g.draw(fxCanvas, fxQuad, (x0 + o[1] * t) * P, (y0 + o[2] * t) * P, 0, P, P)
    end
    fxCanvas:setFilter("nearest", "nearest")
    g.setBlendMode("alpha", "premultiplied")
    g.setColor(1, 1, 1, 1)
    g.draw(fxCanvas, fxQuad, x0 * P, y0 * P, 0, P, P)
  end
  g.setBlendMode(pb or "alpha", pa)
  g.setColor(1, 1, 1, 1)
  fxReset()
end

-- ------- the floor under a thing: the map's own ground at that cell
local function floorAt(x, z)
  local map = S.map
  if not map then return S.groundY end
  local cx, cy = floor(x / 16), floor(z / 16)
  local k = cx * 4096 + cy
  local h = S.floorCache[k]
  if h == nil then
    h = false
    if map.inBounds and map:inBounds(cx, cy) then
      local okV, VS = pcall(V.require, "VoxelScene")
      if okV and VS then
        local ok, gh = pcall(VS.groundAt, map, cx, cy)
        if ok and type(gh) == "number" then h = gh end
      end
    end
    S.floorCache[k] = h
  end
  return h or nil
end

-- ------- the matter
local function spawn(p)
  if #S.parts >= Vox.MAX_PARTS then return nil end
  S.parts[#S.parts + 1] = p
  return p
end

local function rimPoint()
  local side = floor(rnd() * 4)
  local r = rnd() * 2 - 1
  if side == 0 then return r, 1, 0, 1
  elseif side == 1 then return 1, r, 1, 0
  elseif side == 2 then return r, -1, 0, -1 end
  return -1, r, -1, 0
end

local function emitOne(ctx, spec, pose, burstK, at)
  local hw, hh = ctx.cw * 0.5, ctx.ch * 0.5
  local x, y, ou, ov, f = 0, 0, 0, 0, 0
  local from = spec.from
  if at then
    x, y, f = at[1], at[2], at[3] or 0
  elseif from == "foot" then x, y, f = (rnd() * 2 - 1) * hw, -hh, -(0.3 + rnd() * 0.6)
  elseif from == "top" then x, y, f = (rnd() * 2 - 1) * hw, hh, -(0.3 + rnd() * 0.6)
  elseif from == "around" then
    local a = rnd() * TAU
    local r = 1.15 + rnd() * 0.5
    x, y, f = cos(a) * hw * r * 1.1, sin(a) * hh * r, (rnd() - 0.5) * 1.6
  else
    local u, v
    u, v, ou, ov = rimPoint()
    x, y = u * hw + ou * 0.2, v * hh + ov * 0.2
  end
  local p = onCard(pose, x, y, f)
  local cr, cu, n = pose.cr, pose.cu, pose.n
  local k = burstK or 1
  local up = spec.up and range(spec.up) or 0
  local out = (spec.out or 0) * k
  local sp = (spec.spread or 0) * k
  local a, b, c = (rnd() - 0.5) * sp, (rnd() - 0.5) * sp, (rnd() - 0.5) * sp * 0.5
  if k > 1 and not spec.out then
    -- a burst blows the matter away from the card's centre
    local dx, dy = x / hw, y / hh
    a, b = a + dx * 4 * k, b + dy * 4 * k
  end
  local px = spec.px or { 1, 2 }
  return spawn({
    x = p[1], y = p[2], z = p[3],
    vx = cu[1] * up + cr[1] * (a + ou * out) + cu[1] * (b + ov * out) + n[1] * c,
    vy = cu[2] * up + cr[2] * (a + ou * out) + cu[2] * (b + ov * out) + n[2] * c,
    vz = cu[3] * up + cr[3] * (a + ou * out) + cu[3] * (b + ov * out) + n[3] * c,
    age = 0, life = range(spec.life or { 0.6, 1.2 }), spec = spec,
    px = px[1] + floor(rnd() * (px[2] - px[1] + 1)),
    seed = rnd() * 100, side = { cr[1], cr[2], cr[3] },
    ox = pose.center[1], oz = pose.center[3],
    masked = spec.mask and rnd() < spec.mask[2],
  })
end

local function specFor(tname)
  local fx = Vox.FX[tname or ""] or Vox.FX.NORMAL
  return fx.parts, fx
end

local function burst(ctx, tname, pose, count, k)
  local spec = specFor(tname)
  for _ = 1, count do emitOne(ctx, spec, pose, k or 2) end
end

local function speck(x, y, z, vx, vy, vz, px, col, life, opts)
  opts = opts or {}
  return spawn({
    x = x, y = y, z = z, vx = vx, vy = vy, vz = vz, age = 0, life = life,
    px = px, seed = rnd() * 100, side = { 1, 0, 0 }, ox = x, oz = z,
    spec = { grav = opts.grav or 70, drag = opts.drag or 0.3,
             floor = opts.floor or "die", ramp = { col } },
  })
end

local function rampColor(ramp, f)
  local n = #ramp
  if n == 1 then return ramp[1] end
  local x = clamp01(f) * (n - 1)
  local i = min(n - 2, floor(x))
  local t = x - i
  local a, b = ramp[i + 1], ramp[i + 2]
  return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t,
           a[3] + (b[3] - a[3]) * t }
end

local function touchFloor(p, spec)
  local gy = floorAt(p.x, p.z)
  if not gy then return p.y < S.groundY - 40 end
  if p.y > gy + 0.1 or p.vy > 0 then return false end
  local fl = spec.floor
  if fl == "splash" then
    local c = rampColor(spec.ramp, 1)
    for i = 1, 3 do
      local a = i / 3 * TAU + rnd()
      speck(p.x, gy + 0.2, p.z, cos(a) * 5, 6 + rnd() * 5, sin(a) * 5, 1, c, 0.35)
    end
    return true
  elseif fl == "settle" then
    p.y, p.vx, p.vy, p.vz, p.settled = gy + 0.1, 0, 0, 0, true
    return false
  elseif fl == "bounce" then
    if abs(p.vy) < 6 then
      p.y, p.vx, p.vy, p.vz, p.settled = gy + 0.1, 0, 0, 0, true
    else
      p.y, p.vy = gy + 0.1, -p.vy * 0.42
      p.vx, p.vz = p.vx * 0.7, p.vz * 0.7
    end
    return false
  end
  return true
end

local function step(dt)
  local keep = {}
  for _, p in ipairs(S.parts) do
    p.age = p.age + dt
    local spec = p.spec
    local alive = p.age < p.life
    if alive and not p.settled then
      local k = exp(-(spec.drag or 0) * dt)
      p.vx, p.vy, p.vz = p.vx * k, p.vy * k, p.vz * k
      p.vy = p.vy - (spec.grav or 0) * dt
      if spec.zap and rnd() < dt * spec.zap then
        local a = vnorm({ rnd() - 0.5, rnd() - 0.5, rnd() - 0.5 })
        local m = 5 + rnd() * 5
        p.vx, p.vy, p.vz = a[1] * m, a[2] * m, a[3] * m
      end
      local wx, wz = 0, 0
      if spec.wobble then
        local w = cos(p.age * 5 + p.seed) * spec.wobble
        wx, wz = p.side[1] * w, p.side[3] * w
      end
      p.x = p.x + (p.vx + wx) * dt
      p.y = p.y + p.vy * dt
      p.z = p.z + (p.vz + wz) * dt
      if spec.spiral then
        local dx, dz = p.x - p.ox, p.z - p.oz
        local r = sqrt(dx * dx + dz * dz)
        local w = spec.spiral / max(0.8, r) * dt
        local c, s = cos(w), sin(w)
        p.x, p.z = p.ox + dx * c - dz * s, p.oz + dx * s + dz * c
      end
      if touchFloor(p, spec) then alive = false end
    end
    if not alive and spec.pop and not p.popped then
      p.popped = true
      local c = rampColor(spec.ramp, 1)
      for i = 1, 4 do
        local a = i / 4 * TAU
        speck(p.x, p.y, p.z, cos(a) * 4, 2 + rnd() * 3, sin(a) * 4, 1, c, 0.25,
              { grav = 8 })
      end
    end
    if alive then keep[#keep + 1] = p end
  end
  S.parts = keep
end

-- "behind" is what stands farther from the lens than the hand, "front"
-- the rest (never across a face), nil everything
local function pushParticles(ctx, side)
  local hd = S.handDepth
  local ex, ey, ez = ctx.eye[1], ctx.eye[2], ctx.eye[3]
  local dx, dy, dz = ctx.dir[1], ctx.dir[2], ctx.dir[3]
  local P = Vox.PIXEL
  for _, p in ipairs(S.parts) do
    local keep = true
    if side and hd then
      local d = (p.x - ex) * dx + (p.y - ey) * dy + (p.z - ez) * dz
      if side == "behind" then keep = d > hd else keep = d <= hd end
    elseif side == "behind" then
      keep = false
    end
    local sx, sy
    if keep then
      sx, sy = projXY(ctx, p.x, p.y, p.z)
      keep = sx ~= nil
    end
    if keep and side == "front" and overFace(sx, sy) then keep = false end
    if keep then
      local spec = p.spec
      local f = p.age / p.life
      local a = spec.alpha or 1
      if spec.fade then a = a * sin(min(1, f) * pi)
      elseif f > 0.7 then a = a * (1 - f) / 0.3 end
      if spec.twinkle then a = a * (0.35 + 0.65 * abs(sin(p.age * 9 + p.seed))) end
      local c = rampColor(spec.ramp, f)
      if spec.flicker then
        local k = 0.8 + 0.4 * hash(p.seed, floor(p.age * 20))
        c = { c[1] * k, c[2] * k, c[3] * k }
      end
      local px, py = sx / P, sy / P
      if p.masked and spec.mask then
        fmask(Vox.MASKS[spec.mask[1]], px, py, p.px, c, mix(c, W3, 0.6), a)
      else
        local s = p.px
        fpix(px - s * 0.5, py - s * 0.5, s, c, a)
        if s >= 3 then fpix(px - s * 0.5 + 1, py - s * 0.5 + 1, s - 2, mix(c, W3, 0.6), a)
        elseif s == 2 then fpix(px - 1, py - 1, 1, mix(c, W3, 0.6), a) end
      end
    end
  end
end

-- ------- the raised card's dressing
--
-- `amp` scales every light (the use strip charges it past 1), `speedK` and
-- `radK` the ribbons' pace and reach, `age` how long it has been up.
local RECT = { { -1, 1 }, { 1, 1 }, { 1, -1 }, { -1, -1 } }

local function rimCorners(ctx, pose, off)
  local hw, hh = ctx.cw * 0.5 + off, ctx.ch * 0.5 + off
  local out = {}
  for i, d in ipairs(RECT) do
    local p = onCard(pose, d[1] * hw, d[2] * hh, -0.05)
    local x, y = projXY(ctx, p[1], p[2], p[3])
    if not x then return nil end
    out[i] = { x, y }
  end
  return out
end

-- the light hugging the rim: bands stepping outward, hot to faint
local function pushGlow(ctx, pose, pal, amp, now)
  local pulse = 0.82 + 0.18 * sin(now * 4.4)
  local inner = rimCorners(ctx, pose, -0.06)
  if not inner then return end
  for k, band in ipairs(Vox.GLOW) do
    local outer = rimCorners(ctx, pose, band[1] * (0.9 + 0.2 * amp))
    if not outer then return end
    local col = (k == 1) and pal.hot or pal.glow
    local a = band[2] * min(1.4, amp) * pulse
    for e = 1, 4 do
      local e2 = e % 4 + 1
      fquad(inner[e][1], inner[e][2], inner[e2][1], inner[e2][2],
            outer[e2][1], outer[e2][2], outer[e][1], outer[e][2], col, min(1, a))
    end
    inner = outer
  end
end

local function sgn(x) return x < 0 and -1 or 1 end

-- the orbiting ribbons, the part on `pass`'s side of the card
local function pushRibbons(ctx, pose, fx, now, pass, amp, speedK, radK)
  local C, cr, cu, n = pose.center, pose.cr, pose.cu, pose.n
  local hw, hh = ctx.cw * 0.5, ctx.ch * 0.5
  local N = Vox.RIB_SEGS
  local cnt = 0
  for _, rb in ipairs(fx.ribbons or {}) do
    local a, t = math.rad(rb.a or 0), math.rad(rb.tilt or 0)
    local X = { cr[1] * cos(a) + n[1] * sin(a), cr[2] * cos(a) + n[2] * sin(a),
                cr[3] * cos(a) + n[3] * sin(a) }
    local Y = { cu[1] * cos(t) + n[1] * sin(t), cu[2] * cos(t) + n[2] * sin(t),
                cu[3] * cos(t) + n[3] * sin(t) }
    local rx, ry = hw * rb.rx * radK, hh * rb.ry * radK
    local dirn = sgn(rb.speed)
    local head = (rb.phase or 0) + now * rb.speed * speedK
    local len = rb.len or 3
    local prev = nil
    for i = 0, N do
      local f = i / N
      local th = head - (1 - f) * len * dirn
      local c, s = cos(th), sin(th)
      local rise = (rb.rise or 0) * (th - head) * dirn
      local wob = rb.wob and sin(th * 3 + now * 4) * rb.wob or 0
      local ox = X[1] * rx * c + Y[1] * ry * s
      local oy = X[2] * rx * c + Y[2] * ry * s
      local oz = X[3] * rx * c + Y[3] * ry * s
      local lift = rise + wob + (rb.cy or 0) * hh
      local p = { C[1] + ox + cu[1] * lift, C[2] + oy + cu[2] * lift,
                  C[3] + oz + cu[3] * lift }
      local rl = sqrt(ox * ox + oy * oy + oz * oz)
      local perp = { ox / rl, oy / rl, oz / rl }
      local depth = ox * n[1] + oy * n[2] + oz * n[3]
      local w = rb.width * (rb.full and 1 or (0.40 + 0.60 * f)) * (0.8 + 0.2 * amp)
      local al
      if rb.full then
        local hl = max(0, cos(th - head)) ^ 8
        al = (rb.base or 0.35) + (1 - (rb.base or 0.35)) * hl
      else
        -- solid along its body, fading in over the last of the tail
        al = (0.45 + 0.55 * f ^ 1.2) * min(1, f / 0.18)
      end
      al = min(1, al * amp)
      local col = mix(rb.tail, rb.head, rb.full and (max(0, cos(th - head)) ^ 4) or f ^ 1.5)
      if prev then
        local front = (depth + prev.depth) >= 0
        if (pass == "front") == front then
          local ok = true
          if front then
            local mx, my = projXY(ctx, (p[1] + prev.p[1]) * 0.5, (p[2] + prev.p[2]) * 0.5,
                                  (p[3] + prev.p[3]) * 0.5)
            ok = mx and not overGuard(mx, my)
          end
          if ok then
            fseg(ctx, prev.p, p, perp, prev.w, w, prev.col, prev.al, col, al)
            if rb.core then
              -- the hot line down the middle: what makes it read as light
              local ca, cb = prev.al * prev.f, al * f
              fseg(ctx, prev.p, p, perp, prev.w * 0.34, w * 0.34, rb.core, ca, rb.core, cb)
            end
            cnt = cnt + 1
          end
        end
      end
      prev = { p = p, depth = depth, w = w, al = al, col = col, f = f }
    end
    rb._headP = prev and prev.p
  end
  S.dbg.ribbons = S.dbg.ribbons + cnt
end

-- ELECTRIC: bolts crawling the rim, re-struck fourteen times a second --
-- each one a zigzag hugging a stretch of the card's edge, some forking off
-- into the air, one leaping clear of the card
local function rimAt(s, hw, hh)
  s = s % 1
  local L = 4 * hw + 4 * hh
  local d = s * L
  if d < 2 * hw then return -hw + d, hh, 0, 1, 1, 0 end
  d = d - 2 * hw
  if d < 2 * hh then return hw, hh - d, 1, 0, 0, -1 end
  d = d - 2 * hh
  if d < 2 * hw then return hw - d, -hh, 0, -1, -1, 0 end
  d = d - 2 * hw
  return -hw, -hh + d, -1, 0, 0, 1
end

local function pushBolts(ctx, pose, pal, now, amp, count, reach)
  local hw, hh = ctx.cw * 0.5, ctx.ch * 0.5
  local tick = floor(now * 14)
  local bs = (tick * 7919) % 2147483646 + 1
  local function lr()
    bs = (bs * 16807) % 2147483647
    return bs / 2147483647
  end
  local cr, cu = pose.cr, pose.cu
  local R = reach or 1
  local function strike(pts)
    for i = 2, #pts do
      local a = onCard(pose, pts[i - 1][1], pts[i - 1][2], 0.1)
      local b = onCard(pose, pts[i][1], pts[i][2], 0.1)
      local mx, my = projXY(ctx, (a[1] + b[1]) * 0.5, (a[2] + b[2]) * 0.5, (a[3] + b[3]) * 0.5)
      if mx and not overGuard(mx, my) then
        local sx, sy = pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]
        local sl = max(1e-4, sqrt(sx * sx + sy * sy))
        local perp = { (cr[1] * -sy + cu[1] * sx) / sl, (cr[2] * -sy + cu[2] * sx) / sl,
                       (cr[3] * -sy + cu[3] * sx) / sl }
        fseg(ctx, a, b, perp, 0.36, 0.36, pal.glow, 0.7 * amp, pal.glow, 0.7 * amp)
        fseg(ctx, a, b, perp, 0.12, 0.12, pal.hot, amp, pal.hot, amp)
      end
    end
  end
  for _ = 1, count do
    local s0 = lr()
    local span = (0.10 + lr() * 0.16) * R
    local K = 9
    local pts = {}
    local side = 1
    for k = 0, K do
      local x, y, nx, ny = rimAt(s0 + span * k / K, hw, hh)
      local off = (0.12 + lr() * 0.40) * R
      side = -side
      local j = (k == 0 or k == K) and 0.1 or (0.1 + (side > 0 and off or off * 0.25))
      pts[#pts + 1] = { x + nx * j, y + ny * j }
    end
    strike(pts)
    -- a fork off the middle, out into the air
    if lr() < 0.6 then
      local m = pts[1 + floor(K / 2)]
      local x, y, nx, ny, tx, ty = rimAt(s0 + span * 0.5, hw, hh)
      local fork = { { m[1], m[2] } }
      local fx, fy = m[1], m[2]
      for _ = 1, 3 do
        fx = fx + nx * (0.35 + lr() * 0.3) * R + tx * (lr() - 0.5) * 0.6
        fy = fy + ny * (0.35 + lr() * 0.3) * R + ty * (lr() - 0.5) * 0.6
        fork[#fork + 1] = { fx, fy }
      end
      strike(fork)
    end
  end
  -- one bolt leaps clear of the card, off a corner into the air
  local corner = floor(lr() * 4)
  local cx = (corner == 0 or corner == 3) and -hw or hw
  local cy = (corner < 2) and hh or -hh
  local dx, dy = cx > 0 and 0.6 or -0.6, cy > 0 and 0.8 or -0.8
  local pts = { { cx, cy } }
  local x, y = cx, cy
  for _ = 1, 5 do
    x = x + dx * (0.5 + lr() * 0.3) * R + (lr() - 0.5) * 0.5
    y = y + dy * (0.5 + lr() * 0.3) * R + (lr() - 0.5) * 0.5
    pts[#pts + 1] = { x, y }
  end
  strike(pts)
end

-- ICE: crystals grown out of the corners, lit on one facet
local SHARDS = {
  { u = 0.98, v = 0.94, ang = 58, len = 2.3, w = 1.05, d = 0.00 },
  { u = 1.0, v = 0.74, ang = 18, len = 1.6, w = 0.80, d = 0.06 },
  { u = 0.82, v = 1.0, ang = 96, len = 1.5, w = 0.74, d = 0.10 },
  { u = -0.98, v = -0.88, ang = 222, len = 1.9, w = 0.92, d = 0.12 },
  { u = -0.80, v = -1.0, ang = 262, len = 1.2, w = 0.66, d = 0.18 },
  { u = 1.0, v = -0.45, ang = -12, len = 1.1, w = 0.58, d = 0.22 },
  { u = -1.0, v = 0.30, ang = 174, len = 1.0, w = 0.54, d = 0.26 },
}
local ICE_LIT, ICE_MID, ICE_DARK = { 0.93, 0.98, 1.0 }, { 0.66, 0.86, 1.0 }, { 0.42, 0.66, 0.95 }
local ICE_EDGE = { 0.16, 0.34, 0.62 }

local function pushCrystals(ctx, pose, now, age, amp, scale)
  local hw, hh = ctx.cw * 0.5, ctx.ch * 0.5
  local cr, cu = pose.cr, pose.cu
  for i, sd in ipairs(SHARDS) do
    local gr = easeOutBack(clamp01((age - sd.d) / Vox.GROW)) * (scale or 1)
    if gr > 0 then
      local a = math.rad(sd.ang)
      local D = { cr[1] * cos(a) + cu[1] * sin(a), cr[2] * cos(a) + cu[2] * sin(a),
                  cr[3] * cos(a) + cu[3] * sin(a) }
      local Pp = { -cr[1] * sin(a) + cu[1] * cos(a), -cr[2] * sin(a) + cu[2] * cos(a),
                   -cr[3] * sin(a) + cu[3] * cos(a) }
      local B = onCard(pose, sd.u * hw, sd.v * hh, 0.12)
      local L, w = sd.len * gr, sd.w * gr * 0.5
      local function at(along, across)
        local p = { B[1] + D[1] * along + Pp[1] * across, B[2] + D[2] * along + Pp[2] * across,
                    B[3] + D[3] * along + Pp[3] * across }
        return projXY(ctx, p[1], p[2], p[3])
      end
      local blx, bly = at(0, -w)
      local brx, bry = at(0, w)
      local mlx, mly = at(L * 0.7, -w * 0.9)
      local mrx, mry = at(L * 0.7, w * 0.9)
      local cbx, cby = at(0, 0)
      local cmx, cmy = at(L * 0.7, 0)
      local tpx, tpy = at(L, 0)
      local ox1, oy1 = at(-0.08, -w * 1.18)
      local ox2, oy2 = at(-0.08, w * 1.18)
      local ox3, oy3 = at(L * 0.7, w * 1.12)
      local ox4, oy4 = at(L * 1.07, 0)
      local ox5, oy5 = at(L * 0.7, -w * 1.12)
      if blx and brx and mlx and mrx and cbx and cmx and tpx and ox1 and ox2 and ox3 and ox4 and ox5 then
        local al = 0.95 * min(1, amp)
        -- the dark outline first: the pixel-art edge the shard reads by
        ftri(ox1, oy1, ox2, oy2, ox3, oy3, ICE_EDGE, al)
        ftri(ox1, oy1, ox3, oy3, ox5, oy5, ICE_EDGE, al)
        ftri(ox5, oy5, ox3, oy3, ox4, oy4, ICE_EDGE, al)
        ftri(blx, bly, mlx, mly, cmx, cmy, ICE_LIT, al)
        ftri(blx, bly, cmx, cmy, cbx, cby, ICE_LIT, al)
        ftri(mlx, mly, tpx, tpy, cmx, cmy, ICE_LIT, al)
        ftri(cbx, cby, cmx, cmy, mrx, mry, ICE_DARK, al)
        ftri(cbx, cby, mrx, mry, brx, bry, ICE_DARK, al)
        ftri(cmx, cmy, tpx, tpy, mrx, mry, ICE_MID, al)
        -- a glint running up the spine
        local gt = (now * 0.8 + i * 0.37) % 1.6
        if gt < 1 then
          local gx, gy = at(L * 0.85 * gt, 0)
          if gx then fpix(gx / Vox.PIXEL - 0.5, gy / Vox.PIXEL - 0.5, 1, W3, al) end
        end
      end
    end
  end
end

-- WATER: the big drop bobbing off the card's top-left corner
local function pushDrop(ctx, pose, now, age, amp)
  local hw, hh = ctx.cw * 0.5, ctx.ch * 0.5
  local gr = easeOutBack(clamp01(age / Vox.GROW))
  if gr <= 0 then return end
  local p = onCard(pose, -hw * 1.30, hh * 1.06 + sin(now * 2.4) * 0.25, 0.3)
  local x, y = projXY(ctx, p[1], p[2], p[3])
  if not x then return end
  local x2 = projXY(ctx, p[1] + pose.cr[1], p[2] + pose.cr[2], p[3] + pose.cr[3])
  local wpx = abs((x2 or x) - x) / Vox.PIXEL      -- effect px per world px
  local k = max(1, floor(wpx * 1.7 * gr / 13 + 0.5))
  local rows = Vox.MASKS.bigdrop
  local H, Wd = #rows, #rows[1]
  local x0 = floor(x / Vox.PIXEL - Wd * k * 0.5 + 0.5)
  local y0 = floor(y / Vox.PIXEL - H * k * 0.5 + 0.5)
  local deep, body, light = { 0.10, 0.30, 0.78 }, { 0.26, 0.58, 0.98 }, { 0.72, 0.90, 1.0 }
  for ry = 1, H do
    local r = rows[ry]
    for rx = 1, #r do
      local ch = r:byte(rx)
      local c = (ch == 49 and deep) or (ch == 50 and body) or (ch == 51 and light)
      if c then fpix(x0 + (rx - 1) * k, y0 + (ry - 1) * k, k, c, min(1, amp)) end
    end
  end
end

-- the dressing for one card, one side of it
local function textQuad(ctx, pose)
  local hw, hh = ctx.cw * 0.5 * Vox.TEXT_ZONE, ctx.ch * 0.5 * Vox.TEXT_ZONE
  local q = {}
  for _, d in ipairs(RECT) do
    local p = onCard(pose, d[1] * hw, d[2] * hh, 0)
    local x, y = projXY(ctx, p[1], p[2], p[3])
    if not x then return nil end
    q[#q + 1] = x; q[#q + 1] = y
  end
  return q
end

local function dress(ctx, pose, now, pass, amp, speedK, radK, age)
  guard = textQuad(ctx, pose)
  local tname = pose.tname
  local pal = Vox.palette(tname)
  local fx = Vox.FX[tname or ""] or Vox.FX.NORMAL
  if pass == "behind" then pushGlow(ctx, pose, pal, amp, now) end
  pushRibbons(ctx, pose, fx, now, pass, amp, speedK, radK)
  if pass == "front" then
    if fx.set == "bolts" then pushBolts(ctx, pose, pal, now, amp, 4, 1)
    elseif fx.set == "crystals" then pushCrystals(ctx, pose, now, age, amp)
    elseif fx.set == "drop" then pushDrop(ctx, pose, now, age, amp) end
  end
  guard = nil
end

-- ------- the burst where a thrown card breaks
local function pushBursts(ctx, now)
  local keep = {}
  local P = Vox.PIXEL
  for _, b in ipairs(S.bursts) do
    local t = now - b.t0
    if t < 0.7 then
      keep[#keep + 1] = b
      local pal = Vox.palette(b.tname)
      local x, y = projXY(ctx, b.p[1], b.p[2], b.p[3])
      local x2 = x and projXY(ctx, b.p[1] + ctx.right[1], b.p[2] + ctx.right[2], b.p[3] + ctx.right[3])
      if x and x2 then
        local wpx = abs(x2 - x)            -- window px per world px
        -- the flash: a disc of light, white core in the type's glow
        local f = clamp01(t / 0.12)
        local fade = 1 - clamp01((t - 0.1) / 0.35)
        if fade > 0 then
          for ring = 3, 1, -1 do
            local R = wpx * (1.5 + ring * 1.4) * (0.4 + 0.6 * f)
            local col = (ring == 1) and W3 or ((ring == 2) and pal.hot or pal.glow)
            local al = fade * ((ring == 1) and 1 or (ring == 2 and 0.8 or 0.5))
            local segs = 18
            for k = 0, segs - 1 do
              local a1, a2 = k / segs * TAU, (k + 1) / segs * TAU
              ftri(x, y, x + cos(a1) * R, y + sin(a1) * R, x + cos(a2) * R, y + sin(a2) * R, col, al)
            end
          end
        end
        -- the shock ring, expanding and thinning
        local rr = wpx * (2 + t * 26)
        local th = wpx * 0.6 * (1 - t / 0.7)
        local al = 1 - t / 0.7
        local segs = 28
        for k = 0, segs - 1 do
          local a1, a2 = k / segs * TAU, (k + 1) / segs * TAU
          local c1, s1, c2, s2 = cos(a1), sin(a1) * 0.55, cos(a2), sin(a2) * 0.55
          fquad(x + c1 * rr, y + s1 * rr, x + c2 * rr, y + s2 * rr,
                x + c2 * (rr + th), y + s2 * (rr + th), x + c1 * (rr + th), y + s1 * (rr + th),
                pal.glow, al)
        end
        -- the type's own last word
        if b.tname == "ELECTRIC" and t < 0.35 then
          local pose = { center = b.p, cr = ctx.right, cu = ctx.up,
                         n = { -ctx.dir[1], -ctx.dir[2], -ctx.dir[3] } }
          guard = nil
          pushBolts(ctx, pose, pal, now, 1, 7, 1.8)
        elseif b.tname == "ICE" then
          local pose = { center = b.p, cr = ctx.right, cu = ctx.up,
                         n = { -ctx.dir[1], -ctx.dir[2], -ctx.dir[3] } }
          pushCrystals(ctx, pose, now, t * 1.5, 1 - clamp01((t - 0.35) / 0.35), 1.6)
        elseif b.tname == "PSYCHIC" then
          for ring = 1, 3 do
            local r2 = wpx * (1 + (t * 12 + ring * 1.2))
            local a2 = (1 - t / 0.7) * 0.9
            for k = 0, 23 do
              local a1, a3 = k / 24 * TAU, (k + 1) / 24 * TAU
              fquad(x + cos(a1) * r2, y + sin(a1) * r2 * 0.35, x + cos(a3) * r2, y + sin(a3) * r2 * 0.35,
                    x + cos(a3) * (r2 + 3 * P), y + sin(a3) * (r2 + 3 * P) * 0.35,
                    x + cos(a1) * (r2 + 3 * P), y + sin(a1) * (r2 + 3 * P) * 0.35, pal.glow, a2)
            end
          end
        end
      end
    end
  end
  S.bursts = keep
end

-- ------- the slab: the card's own face, stacked behind it as plates
local PLATES = { { 1.0, { 0.10, 0.08, 0.08 } }, { 0.5, { 0.36, 0.30, 0.27 } } }
local function drawSlab(ctx, i, pose, sc, alpha)
  local F = fan()
  if not (F and pose.tex) then return end
  local g = love.graphics
  S.back[i] = S.back[i] or { {}, {} }
  for k, pl in ipairs(PLATES) do
    local slot = S.back[i][k]
    slot.canvas = pose.tex
    local c = onCard(pose, 0, 0, -Vox.SLAB * pl[1])
    local ok, m = pcall(F.hang, slot, ctx.shot, c, pose.cr, pose.cu,
                        ctx.cw * sc, ctx.ch * sc)
    if ok and m then
      g.setColor(pl[2][1], pl[2][2], pl[2][3], alpha or 1)
      g.draw(m)
    end
  end
  g.setColor(1, 1, 1, 1)
end

-- ------- the fan's hooks
--
-- fanBegin: before the cards -- what stands behind the hand. card: each
-- card, BEFORE its face is drawn (it lays the slab). fanEnd: after.
function Vox.fanBegin(shot, now)
  if not Vox.ENABLED then return end
  local ctx = context(shot)
  S.ctx = ctx
  if not ctx then return end
  S.dbg.fxverts, S.dbg.slabs, S.dbg.ribbons = 0, 0, 0
  if now - S.lastFan > 0.25 then
    S.sel, S.selType, S.pose, S.lastEmit = nil, nil, {}, nil
  end
  S.lastFan = now
  S.fanFrame = S.frame
  S.quads = {}
  fxReset()
  pushParticles(ctx, "behind")
  fxFlush(ctx)
end

function Vox.card(i, sel, tname, center, cr, cu, deal, raise, refuse, tex, now)
  local ctx = S.ctx
  if not (Vox.ENABLED and ctx) then return end
  local n = normalOf(ctx, center, cr, cu)
  local pose = { center = center, cr = cr, cu = cu, n = n, tname = tname,
                 tex = tex, refuse = refuse, sel = sel }
  S.pose[i] = pose
  if deal <= 0 then return end
  do
    local hw, hh = ctx.cw * 0.5, ctx.ch * 0.5
    local q = {}
    for _, d in ipairs(RECT) do
      local p = onCard(pose, d[1] * hw * Vox.TEXT_ZONE, d[2] * hh * Vox.TEXT_ZONE, 0)
      local x, y = projXY(ctx, p[1], p[2], p[3])
      if not x then q = nil; break end
      q[#q + 1] = x; q[#q + 1] = y
    end
    S.quads[i] = q
  end
  if sel and (S.sel ~= i or S.selType ~= tname) then
    S.sel, S.selType, S.selAt = i, tname, now
    if deal >= 1 and not refuse then burst(ctx, tname, pose, 14, 2) end
  end
  if sel and not refuse then
    local age = now - S.selAt
    local up = clamp01(age / 0.2) * clamp01(deal)
    fxReset()
    dress(ctx, pose, now, "behind", up, 1, 0.9 + 0.1 * up, age)
    fxFlush(ctx)
  end
  drawSlab(ctx, i, pose, 1, 1)
  S.dbg.slabs = S.dbg.slabs + 1
end

function Vox.fanEnd(shot, now)
  local ctx = S.ctx
  if not (Vox.ENABLED and ctx) then return end
  local sum, cnt = 0, 0
  local e, d = ctx.eye, ctx.dir
  for _, p in pairs(S.pose) do
    local c = p.center
    sum = sum + (c[1] - e[1]) * d[1] + (c[2] - e[2]) * d[2] + (c[3] - e[3]) * d[3]
    cnt = cnt + 1
  end
  S.handDepth = (cnt > 0) and sum / cnt or nil
end

-- in front of the hand, after the turn ribbon (see Vox.draw)
local function drawHand(ctx, now)
  local pose = S.sel and S.pose[S.sel]
  local dt = S.lastEmit and min(0.1, max(0, now - S.lastEmit)) or 0
  S.lastEmit = now
  fxReset()
  if pose and not pose.refuse then
    local age = now - S.selAt
    local up = clamp01(age / 0.2)
    dress(ctx, pose, now, "front", up, 1, 0.9 + 0.1 * up, age)
    local spec, fx = specFor(pose.tname)
    S.emitAcc = S.emitAcc + dt * spec.rate
    local k = 0
    while S.emitAcc >= 1 and k < 12 do
      S.emitAcc = S.emitAcc - 1
      emitOne(ctx, spec, pose)
      k = k + 1
    end
    if S.emitAcc > 1 then S.emitAcc = 0 end
    -- squares shed off the ribbons' heads
    if fx.shed then
      S.shedAcc = S.shedAcc + dt * fx.shed
      while S.shedAcc >= 1 do
        S.shedAcc = S.shedAcc - 1
        local rb = fx.ribbons[1 + floor(rnd() * #fx.ribbons)]
        local hp = rb and rb._headP
        if hp then
          local c = rampColor(spec.ramp, rnd() * 0.5)
          speck(hp[1], hp[2], hp[3], (rnd() - 0.5) * 3, 1 + rnd() * 2, (rnd() - 0.5) * 3,
                1 + floor(rnd() * 2), c, 0.5 + rnd() * 0.5, { grav = -2, drag = 1.5 })
        end
      end
    end
    -- FIGHTING's beat: every 1.2 s the card punches out a ring of sparks
    if fx.set == "beat" then
      local beat = floor(now / 1.2)
      if S.beat ~= beat then
        S.beat = beat
        burst(ctx, pose.tname, pose, 12, 2.5)
      end
    end
  end
  pushParticles(ctx, "front")
  fxFlush(ctx)
end

-- ------- the use strip: charge, throw, burst (and the fold)
local function startFlight(kind, pose)
  S.flights[#S.flights + 1] = {
    kind = kind, pose = pose, t0 = clock(), slot = { canvas = pose.tex }, idx = #S.flights + 100,
  }
  if kind == "launch" then S.dbg.launches = S.dbg.launches + 1
  else S.dbg.folds = S.dbg.folds + 1 end
end

-- where a flight is now: pose, scale, alpha, and its dressing's knobs
local function flightPose(ctx, fl, now)
  local t = now - fl.t0
  local p0 = fl.pose
  if fl.kind == "launch" then
    local ch, th = Vox.CHARGE_TIME, Vox.THROW_TIME
    if t < ch then
      -- the charge: it holds, trembles, and its element winds up
      local k = t / ch
      local j = sin(now * 70) * 0.05 * k
      local pose = { center = onCard(p0, j, 0, 0.6 * k), cr = p0.cr, cu = p0.cu, n = p0.n,
                     tname = p0.tname, tex = p0.tex }
      return pose, 1 + 0.08 * k, 1, false, 1 + 1.2 * k, 1 + 2.5 * k, 1 - 0.2 * k
    end
    local e = clamp01((t - ch) / th)
    local done = e >= 1
    e = e * e * (3 - 2 * e) * 0.3 + e * e * 0.7
    local ec = ctx.shot.enemyCell or ctx.shot.playerCell
    local target = { ec[1], ctx.groundY + 8, ec[2] }
    local a = onCard(p0, 0, 0, 0.6)
    local mid = { (a[1] + target[1]) * 0.5, (a[2] + target[2]) * 0.5 + 9, (a[3] + target[3]) * 0.5 }
    local u = 1 - e
    local center = { u * u * a[1] + 2 * u * e * mid[1] + e * e * target[1],
                     u * u * a[2] + 2 * u * e * mid[2] + e * e * target[2],
                     u * u * a[3] + 2 * u * e * mid[3] + e * e * target[3] }
    local cr = vrot(p0.cr, ctx.up, e * TAU)
    cr = vrot(cr, ctx.dir, e * 0.5)
    local cu = vrot(p0.cu, ctx.dir, e * 0.5)
    local pose = { center = center, cr = cr, cu = cu, n = normalOf(ctx, center, cr, cu),
                   tname = p0.tname, tex = p0.tex }
    return pose, 1.08 - 0.3 * e, 1, done, 2.2, 3.5, 0.7
  end
  local e = clamp01(t / Vox.FOLD_TIME)
  local done = t >= Vox.FOLD_TIME
  e = e * e
  local pc = ctx.shot.playerCell
  local target = { pc[1], ctx.groundY + 5, pc[2] }
  local c0 = p0.center
  local center = { c0[1] + (target[1] - c0[1]) * e, c0[2] + (target[2] - c0[2]) * e + sin(e * pi) * 2,
                   c0[3] + (target[3] - c0[3]) * e }
  local cr = vrot(p0.cr, ctx.up, e * pi)
  local pose = { center = center, cr = cr, cu = p0.cu, n = normalOf(ctx, center, cr, p0.cu),
                 tname = p0.tname, tex = p0.tex }
  return pose, 1 - 0.8 * e, 1 - 0.6 * e, done, 0, 1, 1
end

local function finishFlight(ctx, fl, pose)
  if fl.kind == "launch" then
    S.bursts[#S.bursts + 1] = { p = pose.center, tname = pose.tname, t0 = clock() }
    burst(ctx, pose.tname, pose, 36, 3.5)
    pcall(function()
      V.require("BattleGlassFX").pulse(pose.center[1], pose.center[2], pose.center[3],
                                       0.7, pose.tname)
    end)
  else
    burst(ctx, pose.tname, pose, 6, 1.5)
  end
end

local function drawFlights(ctx, now)
  local F = fan()
  if not F or #S.flights == 0 then return end
  local g = love.graphics
  local live = {}
  S.quads = {}
  -- behind: the glow and the back half of the ribbons, for every flight
  fxReset()
  for _, fl in ipairs(S.flights) do
    local pose, sc, alpha, done, amp, spK, radK = flightPose(ctx, fl, now)
    if done then
      finishFlight(ctx, fl, pose)
    else
      live[#live + 1] = { fl = fl, pose = pose, sc = sc, alpha = alpha, amp = amp,
                          spK = spK, radK = radK }
      if amp > 0 then dress(ctx, pose, now, "behind", amp, spK, radK, 1) end
    end
  end
  fxFlush(ctx)
  -- the cards themselves: slab, face, and the heat of the throw
  for _, L in ipairs(live) do
    local fl, pose = L.fl, L.pose
    drawSlab(ctx, fl.idx, pose, L.sc, L.alpha)
    local toward = vcross(pose.cr, pose.cu)
    local e3 = ctx.eye
    local facing = toward[1] * (e3[1] - pose.center[1]) + toward[2] * (e3[2] - pose.center[2])
                   + toward[3] * (e3[3] - pose.center[3])
    if facing > 0 and fl.slot.canvas then
      local ok, m = pcall(F.hang, fl.slot, ctx.shot, pose.center, pose.cr, pose.cu,
                          ctx.cw * L.sc, ctx.ch * L.sc)
      if ok and m then
        g.setColor(1, 1, 1, L.alpha)
        g.draw(m)
        if fl.kind == "launch" then
          local heat = clamp01((now - fl.t0) / Vox.CHARGE_TIME) * 0.35
          if heat > 0 then
            local pb, pa = g.getBlendMode()
            local pal = Vox.palette(pose.tname)
            g.setBlendMode("add")
            g.setColor(pal.glow[1], pal.glow[2], pal.glow[3], heat)
            g.draw(m)
            g.setBlendMode(pb or "alpha", pa)
          end
        end
      end
    end
    g.setColor(1, 1, 1, 1)
  end
  -- front: the ribbons' near half, the set pieces, the trail
  fxReset()
  for _, L in ipairs(live) do
    if L.amp > 0 then
      dress(ctx, L.pose, now, "front", L.amp, L.spK, L.radK, 1)
      if L.fl.kind == "launch" then
        local spec = specFor(L.pose.tname)
        for _ = 1, 3 do emitOne(ctx, spec, L.pose, 2) end
      end
    end
  end
  local keep = {}
  for k, L in ipairs(live) do
    keep[#keep + 1] = L.fl
    -- a card in flight is still a card: the matter keeps off its words
    S.quads[k] = textQuad(ctx, L.pose)
  end
  S.flights = keep
end

-- ------- the battle's hooks
local observe
function Vox.observe(battle, dt, arena)
  S.frame = S.frame + 1
  if not Vox.ENABLED then return end
  -- a failure here is swallowed by the caller's pcall; kept for the probe
  local ok, err = pcall(observe, battle, dt, arena)
  if not ok then S.dbg.err = tostring(err) end
end

observe = function(battle, dt, arena)
  local map = arena and arena.map
  if map ~= S.map then S.map, S.floorCache = map, {} end
  -- the WALL clock: the battle ticks at a fixed step whatever the frame
  -- rate, and on a slow machine that ran the matter in slow motion
  local now = clock()
  local rdt = S.lastStep and (now - S.lastStep) or (dt or 0)
  S.lastStep = now
  step(max(0, min(rdt, 0.1)))
  local phase = battle and battle.phase
  if S.prevPhase == "moveSelect" and phase ~= "moveSelect" then
    -- B (back to the menu) folds the hand; anything else is the chosen
    -- move leaving, unless it was refused (no PP, disabled)
    local chosen = (phase ~= "menu") and S.sel or nil
    local cp = chosen and S.pose[chosen]
    if cp and cp.refuse then chosen = nil end
    for i, pose in pairs(S.pose) do
      startFlight((i == chosen) and "launch" or "fold", pose)
    end
    S.pose, S.sel, S.quads = {}, nil, {}
  end
  S.prevPhase = phase
end

-- draw: every frame, after the turn ribbon. While the hand is up it is
-- what stands in front of it; once the list closes, the use strip and
-- whatever is still falling.
function Vox.draw(battle, shot)
  if not Vox.ENABLED then return end
  if S.fanFrame == S.frame then
    local ctx = S.ctx
    if ctx then drawHand(ctx, clock()) end
    return
  end
  S.handDepth = nil
  if #S.parts == 0 and #S.flights == 0 and #S.bursts == 0 then return end
  local ctx = context(shot)
  if not ctx then return end
  S.ctx = ctx
  local now = clock()
  S.dbg.fxverts, S.dbg.ribbons = 0, 0
  drawFlights(ctx, now)        -- leaves the front batch open
  pushBursts(ctx, now)
  pushParticles(ctx, "front")
  fxFlush(ctx)
  S.quads = {}
end

return Vox
