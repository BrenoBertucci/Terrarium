-- Voxel world mode: the built terrain, kept on disk.
--
-- Entering a map runs `runGeometry` over the whole thing -- every tile, every
-- structure, every kit -- and turns the result into GPU meshes. Measured on
-- the reference machine (`tests/sink_probe.lua`), a full settle is SIX TO
-- ELEVEN SECONDS per map, and it happens on every visit and again on every
-- launch, because nothing about it is remembered.
--
-- That is the frame-time tail. `probe_out_f5_perf/buildings_perf_probe.log`
-- measures p95 of 41-66 ms and p99 of 47-195 ms against a p50 of 23-29 ms:
-- the average is a playable frame and the experience is not, because the
-- ninety-fifth percentile is sixteen frames a second. The analysis is the
-- same work every time and its answer is the same answer every time.
--
-- So: keep the answer.
--
-- ------- WHAT IS KEPT
--
-- Not the meshes -- a GPU object cannot be written down. What is kept is
-- exactly what `newPackSink` already builds on the way to making one: the
-- little-endian float32 vertex stream, plus each chunk's culling box and its
-- quad count. Indices are NOT kept, because they never were: every quad's six
-- indices are a pure function of its ordinal, so they are regenerated on load
-- the same way they are regenerated on a cold build.
--
-- Reloading is therefore the cheap half of a build with the expensive half
-- deleted: bytes -> ByteData -> Mesh, and no geometry pass at all.
--
-- ------- WHY THE IDENTITY IS PARANOID
--
-- The failure this must not have is not a crash. It is a world that is
-- quietly WRONG -- last week's ledges, a forest from before the row was
-- flipped, a town built by an older version of Structures -- because a wrong
-- world does not announce itself, it gets reported as a different bug weeks
-- later. Every byte is therefore refused unless the payload names the exact
-- format, the exact geometry generation and the exact settings that produced
-- it (see `MeshCache.identity`), and a payload that does not parse cleanly is
-- refused rather than patched up.
--
-- Refusing is always safe: the caller simply builds, which is what it did
-- before this file existed. There is no path here that can make the game
-- worse than no cache at all -- that is the property to preserve in any
-- change to this file.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local MeshCache = {}

-- ------- VERSIONS
--
-- FORMAT changes when the byte layout below changes. GEOM changes when the
-- GEOMETRY changes -- a new kit, a fix in Structures, a different chunk size.
--
-- They are separate because they fail differently: a FORMAT change makes old
-- bytes unreadable, and a GEOM change makes them readable and wrong. Only one
-- of those is dangerous, and it is the one a developer forgets.
--
-- THE SAFETY VALVE, because somebody will forget: the mod's own version
-- string is folded into the identity too (see `identity` below). Terrarium
-- bumps its version for every release, so a forgotten GEOM bump still misses
-- the cache on every machine that installs the new build -- the worst case is
-- a stale cache between two DEV builds carrying the same version string,
-- which is a rebuild away and never reaches a player.
MeshCache.FORMAT = 1
MeshCache.GEOM = 1

-- "TRMC", little-endian, as one uint32 -- cheaper to compare than a string
-- and impossible to half-match.
local MAGIC = 0x434D5254

-- A payload bigger than this is refused rather than written. mod.storage caps
-- a value at 512 MiB and its crash-safe write moves the bytes several times
-- (stage, read back, compare, .bak, main, read back, compare), so a payload
-- that approaches the cap costs seconds of disk on a laptop. A route's
-- terrain is a few megabytes; anything near this is a bug upstream, and
-- writing it would be the cache making the game worse.
MeshCache.MAX_BYTES = 48 * 1024 * 1024

local FLOAT = "<fffff"          -- x0, z0, x1, z1, ymax
local unpack = unpack or table.unpack

local function have()
  return love and love.data and love.data.pack and love.data.unpack
         and love.data.newByteData
end

-- ------- THE IDENTITY
--
-- Everything that changes what the mesher emits, folded into one short
-- string. A mismatch is a miss, and a miss is a build.
--
-- The rows are asked for their VALUE rather than their index, because an
-- index is a position in a ladder and ladders get reordered -- that is how a
-- stale entry would come back wearing a fresh fingerprint.
local IDENTITY_ROWS = {
  -- the five modules that call ChunkMesher.invalidate, i.e. the five that
  -- change geometry rather than shading
  { "Trees3D", "setting" },
  { "Grass3D", "setting" },
  { "LedgeKit", "setting" },
  { "TowerKit", "setting" },
  { "CryptKit", "setting" },
}

local function rowValue(modName, field)
  local ok, mod = pcall(V.require, modName)
  if not ok or not mod then return "?" end
  local setting = mod[field]
  if not setting or not setting.get then return "?" end
  local okV, v = pcall(setting.get, setting)
  if not okV then return "?" end
  return tostring(v)
end

-- A string folded into the identity by whoever wants every entry to miss.
-- Probes set it to make a genuinely COLD arm without deleting anything --
-- which matters here because the engine's storage backend on this build has
-- no getDirectoryItems, so list() answers "storage_unavailable" and a wipe
-- cannot enumerate. Empty in the game.
MeshCache.SALT = ""

function MeshCache.identity()
  local parts = {
    "f" .. MeshCache.FORMAT,
    "g" .. MeshCache.GEOM,
    "s" .. tostring(MeshCache.SALT or ""),
    "m" .. tostring((V.mod and V.mod.manifest and V.mod.manifest.version)
                    or (V.mod and V.mod.version) or "?"),
  }
  for _, row in ipairs(IDENTITY_ROWS) do
    parts[#parts + 1] = row[1]:sub(1, 2) .. "=" .. rowValue(row[1], row[2])
  end
  return table.concat(parts, ";")
end

-- ------- THE BYTE LAYOUT
--
--   u4  magic
--   u4  format version
--   s4  identity string
--   u4  group count            (2: terrain, then the water surface)
--   per group:
--     u4  chunk count
--     per chunk:
--       f f f f f   x0 z0 x1 z1 ymax
--       u4          quad count
--       s4          packed float32 vertex bytes
--   u4  total quads across every group, repeated
--
-- The trailing quad total is the integrity check, and it is deliberately not
-- a hash. mod.storage already guarantees the BYTES on disk (it stages, reads
-- back and compares before it commits -- see the engine's Storage.lua), so
-- what is left to catch is a truncated or mis-parsed payload, and for that a
-- value that can only be computed by walking the whole structure is both
-- cheaper than md5 over ten megabytes and a better test of the parse. A
-- payload that ends early fails on a length check long before it gets here.

-- `records` is { terrain = {chunk...}, water = {chunk...} }, each chunk
-- { x0, z0, x1, z1, ymax, quads, bytes }.
-- `variant` is per-entry rather than global: the FULL slot is built with a
-- list of neighbour-body masks (see runGeometry), and that list comes from
-- whichever neighbours the overworld currently has in hand. It is normally
-- the same list every time for a given map, because connections are map
-- data -- but "normally" is not "always", and a full mesh written with a
-- partial mask set and read back with a complete one is a border ring
-- standing through a neighbour's ground. So the mask set is fingerprinted
-- into the entry: a different one is a MISS, which costs a build, instead of
-- a hit, which would cost a wrong world.
function MeshCache.pack(records, variant)
  if not have() then return nil, "love.data.pack unavailable" end
  local out, n = {}, 0
  local function put(s) n = n + 1; out[n] = s end
  local groups = { records.terrain or {}, records.water or {} }
  local id = MeshCache.identity() .. "|" .. tostring(variant or "")
  put(love.data.pack("string", "<I4I4s4I4", MAGIC, MeshCache.FORMAT, id,
                     #groups))
  local quadTotal = 0
  for _, chunks in ipairs(groups) do
    put(love.data.pack("string", "<I4", #chunks))
    for _, ch in ipairs(chunks) do
      quadTotal = quadTotal + ch.quads
      put(love.data.pack("string", FLOAT, ch.x0, ch.z0, ch.x1, ch.z1, ch.ymax))
      put(love.data.pack("string", "<I4s4", ch.quads, ch.bytes))
    end
  end
  put(love.data.pack("string", "<I4", quadTotal))
  local blob = table.concat(out)
  if #blob > MeshCache.MAX_BYTES then
    return nil, ("payload %d bytes is over the %d ceiling")
                  :format(#blob, MeshCache.MAX_BYTES)
  end
  return blob
end

-- Returns the records, or nil plus a reason. EVERY failure path returns nil:
-- a half-understood payload is refused, never repaired.
function MeshCache.unpack(blob, wantIdentity)
  if not have() then return nil, "love.data.unpack unavailable" end
  if type(blob) ~= "string" or #blob < 16 then return nil, "too short" end
  local ok, res, why = pcall(function()
    local magic, fmt, id, nGroups, at =
      love.data.unpack("<I4I4s4I4", blob)
    if magic ~= MAGIC then return nil, "bad magic" end
    if fmt ~= MeshCache.FORMAT then
      return nil, ("format %d, want %d"):format(fmt, MeshCache.FORMAT)
    end
    if wantIdentity and id ~= wantIdentity then
      -- both strings, because "changed" without saying to what is how a
      -- cache that never hits looks exactly like a cache that is working
      return nil, ("identity: on disk [%s] wanted [%s]"):format(id, wantIdentity)
    end
    if nGroups ~= 2 then return nil, "group count " .. tostring(nGroups) end
    local names = { "terrain", "water" }
    local records, quadTotal = {}, 0
    for g = 1, nGroups do
      local nChunks
      nChunks, at = love.data.unpack("<I4", blob, at)
      local chunks = {}
      for i = 1, nChunks do
        local x0, z0, x1, z1, ymax
        x0, z0, x1, z1, ymax, at = love.data.unpack(FLOAT, blob, at)
        local quads, bytes
        quads, bytes, at = love.data.unpack("<I4s4", blob, at)
        -- the one structural invariant worth asserting: the vertex stream
        -- must be exactly four vertices of six float32 per quad. A payload
        -- that disagrees is not a payload this file wrote.
        if #bytes ~= quads * 4 * 6 * 4 then
          return nil, ("chunk %d: %d bytes for %d quads"):format(i, #bytes, quads)
        end
        quadTotal = quadTotal + quads
        chunks[i] = { x0 = x0, z0 = z0, x1 = x1, z1 = z1, ymax = ymax,
                      quads = quads, bytes = bytes }
      end
      records[names[g]] = chunks
    end
    local tail = love.data.unpack("<I4", blob, at)
    if tail ~= quadTotal then
      return nil, ("quad total %d, walked %d"):format(tail, quadTotal)
    end
    return records
  end)
  if not ok then return nil, "malformed: " .. tostring(res) end
  -- pcall hands back every return value, so the REASON a refusal gave
  -- survives; catching only the first would turn every distinct refusal into
  -- the same unhelpful word in the log.
  if type(res) ~= "table" then return nil, tostring(why or res or "malformed") end
  return res
end

-- ------- THE SHELF
--
-- mod.storage, not mod.cache. Geometry does not depend on the save file, so
-- installation scope would be the better fit on paper and mod.cache offers
-- it -- but mod.cache has no list(), no crash-safe staging and a 64 MiB file
-- cap, which turns "wipe the cache" into an index this file would have to
-- maintain and "the power went out mid-write" into a payload that reads back
-- as garbage. mod.storage stages, reads back, compares and keeps a .bak
-- (engine src/mods/Storage.lua), and needs no permission. The price is that
-- the cache is per playthrough and a second save slot builds its own.
--
-- The API as a mod sees it (engine src/mods/Loader.lua):
--   mod.storage:writeBytes(game, key, bytes) -> true | false, code, message
--   mod.storage:readBytes(game, key)         -> bytes | nil, code, message
--   mod.storage:list(game, prefix)           -> { key... } | nil, code, message
--   mod.storage:delete(game, key)
--
-- Before a playthrough exists -- the title screen -- every one of these
-- answers "not_in_playthrough". That is not an error here, it is Tuesday:
-- there is no save to hang a cache off yet, so the cache is simply off and
-- the mesher builds exactly as it always did.
local PREFIX = "mesh"

local function storage()
  local mod = V.mod
  if not (mod and mod.storage) then return nil end
  return mod.storage
end

-- What the cache actually did, for the probe and for a bug report. Counts
-- only; nothing here changes behaviour.
MeshCache.stats = { hits = 0, misses = 0, writes = 0, bytes = 0, refused = 0,
                    why = {} }

function MeshCache.resetStats()
  MeshCache.stats = { hits = 0, misses = 0, writes = 0, bytes = 0, refused = 0,
                      why = {} }
end

function MeshCache.available()
  return have() and storage() ~= nil
end

-- Map ids are engine constants (ROUTE_2, VIRIDIAN_CITY) and already safe,
-- but a key is a path and this file should not be the thing that finds out
-- otherwise.
local function safe(seg)
  return (tostring(seg or ""):gsub("[^%w_%-]", "_"))
end

-- THE VARIANT BELONGS IN THE KEY, NOT ONLY IN THE IDENTITY.
--
-- This was the bug that made the cache never hit. The FULL slot of a map is
-- requested by two different callers with two different mask sets --
-- VoxelScene passes the neighbour-body masks, BattleScene passes nil -- and
-- with the variant only inside the payload they both wrote to
-- `mesh/<map>/full`. Each one's write clobbered the other's, so whichever
-- read came next found a payload whose variant did not match, refused it,
-- rebuilt, and overwrote again. Hits stayed at zero forever while the writes
-- ran twice per visit: a cache that was pure cost.
--
-- Given its own key each variant keeps its own entry and neither can
-- overwrite the other. The fingerprint is hashed because a mask set is a
-- long string and a key is a path; md5 through love.data is a C call, and
-- eight hex characters is plenty to separate the two or three mask sets a
-- map ever has.
local function variantTag(variant)
  if variant == nil or variant == "" then return nil end
  local ok, hex = pcall(function()
    return love.data.encode("string", "hex", love.data.hash("md5", variant))
  end)
  if ok and type(hex) == "string" and #hex >= 8 then return hex:sub(1, 8) end
  -- no hashing available: fold the string by hand rather than drop the
  -- distinction, because dropping it is the bug this exists to fix
  local h = 5381
  for i = 1, #variant do
    h = (h * 33 + variant:byte(i)) % 4294967296
  end
  return ("%08x"):format(h)
end

function MeshCache.key(mapId, slot, variant)
  local tag = variantTag(variant)
  return PREFIX .. "/" .. safe(mapId) .. "/"
         .. safe(slot) .. (tag and ("_" .. tag) or "")
end

-- Records for this map and slot, or nil plus a reason. A reason is never an
-- error: every one of them means "build it", which is what the caller did
-- before this file existed.
function MeshCache.load(game, mapId, slot, variant)
  local st = storage()
  if not (st and have()) then return nil, "unavailable" end
  local ok, bytes, code = pcall(st.readBytes, st, game,
                                MeshCache.key(mapId, slot, variant))
  if not ok then return nil, "read threw" end
  if type(bytes) ~= "string" then
    MeshCache.stats.misses = MeshCache.stats.misses + 1
    return nil, tostring(code or "not_found")
  end
  local rec, why = MeshCache.unpack(bytes,
                     MeshCache.identity() .. "|" .. tostring(variant or ""))
  if rec then
    MeshCache.stats.hits = MeshCache.stats.hits + 1
  else
    MeshCache.stats.refused = MeshCache.stats.refused + 1
    -- keep the last few reasons: "refused" on its own says a payload was not
    -- trusted and not WHY, and the difference between a stale identity and a
    -- variant that is never the same twice is the difference between a cache
    -- that works and one that is pure cost
    local w = MeshCache.stats.why
    if #w < 8 then
      w[#w + 1] = ("%s/%s v=%s: %s"):format(tostring(mapId), tostring(slot),
                                            tostring(variant), tostring(why))
    end
  end
  return rec, why
end

function MeshCache.save(game, mapId, slot, records, variant)
  local st = storage()
  if not (st and have() and records) then return false, "unavailable" end
  local blob, err = MeshCache.pack(records, variant)
  if not blob then return false, err end
  local key = MeshCache.key(mapId, slot, variant)
  local w = MeshCache.stats.why
  if #w < 16 then
    w[#w + 1] = ("WROTE %s/%s v=%s"):format(tostring(mapId), tostring(slot),
                                            tostring(variant))
  end
  indexAdd(game, key)
  local ok, wrote, code, detail = pcall(st.writeBytes, st, game, key, blob)
  -- The failure REASON, not just the fact. A write that reports success and
  -- is then read back as the previous session's bytes is impossible against
  -- the engine's writeBytes, which verifies `main` before returning true --
  -- so a stale read means the write did not actually succeed, and the code
  -- it returned is the whole answer.
  if not ok or not wrote then
    local w = MeshCache.stats.why
    if #w < 16 then
      w[#w + 1] = ("WRITE FAILED %s: %s / %s"):format(key, tostring(code),
                                                      tostring(detail))
    end
  end
  if not ok then return false, "write threw" end
  if not wrote then return false, tostring(code or "refused") end
  MeshCache.stats.writes = MeshCache.stats.writes + 1
  MeshCache.stats.bytes = MeshCache.stats.bytes + #blob
  return true, #blob
end

-- Every cached map, dropped. Used by the OPTIONS row and by anything that
-- changes geometry in a way the identity cannot see.
-- Every cached map, dropped. Returns how many were deleted, how many were
-- listed, and why not when the answer is none -- because the first version
-- of this returned a bare 0 for both "nothing cached" and "the listing
-- failed", and a probe that wipes nothing and then reports a COLD build is a
-- probe measuring a warm one. That is exactly what happened: twelve paired
-- measurements compared a warm build against a warm build and read as noise.
-- ------- THE INDEX, BECAUSE list() IS NOT THERE
--
-- The engine's Storage.list answers "storage_unavailable" unless the backend
-- can enumerate a directory, and on this build it cannot. Without a listing
-- there is no way to find what was written -- so a wipe has nothing to wipe,
-- and entries orphaned by an identity change would sit on disk forever.
--
-- So the keys are written down. One small table value beside the payloads,
-- appended to on every save. It is allowed to be wrong in the harmless
-- direction (naming a key that is already gone); it must not be wrong in the
-- other, so it is written BEFORE the payload it names.
local INDEX_KEY = PREFIX .. "/index"

local function indexAdd(game, key)
  local st = storage()
  if not st then return end
  pcall(function()
    local got = st:read(game, INDEX_KEY)
    local list = (type(got) == "table" and got) or {}
    for i = 1, #list do if list[i] == key then return end end
    list[#list + 1] = key
    st:write(game, INDEX_KEY, list)
  end)
end

function MeshCache.wipe(game)
  local st = storage()
  if not st then return 0, 0, "no storage" end
  -- the index first, and the listing only as a bonus where it works
  local keys = {}
  pcall(function()
    local got = st:read(game, INDEX_KEY)
    if type(got) == "table" then keys = got end
  end)
  local okL, listed = pcall(st.list, st, game, PREFIX)
  if okL and type(listed) == "table" then
    local seen = {}
    for _, k in ipairs(keys) do seen[k] = true end
    for _, k in ipairs(listed) do
      if not seen[k] and k ~= INDEX_KEY then keys[#keys + 1] = k end
    end
  end
  local n = 0
  for _, key in ipairs(keys) do
    local okD, done = pcall(st.delete, st, game, key)
    if okD and done ~= false then n = n + 1 end
  end
  pcall(function() st:delete(game, INDEX_KEY) end)
  return n, #keys, nil
end

-- ------- A PLAIN MESH, NOT A CHUNKED GROUP
--
-- The terrain is chunks with boxes. The grass and the flowers are ONE mesh
-- each, and they are what a map build actually spends its time on: sampling
-- the build stage once a frame (tests/cache_probe.lua) puts 166-277 frames
-- in the grass pass against 58-88 in the whole terrain geometry. Grass3D
-- stamps every tuft into a Lua table per vertex, which is the same disease
-- newPackSink cured in the mesher and is untouched here on purpose -- the
-- cold build still pays it. What the cache removes is paying it AGAIN.
--
-- Indices ARE stored for these, unlike the terrain. A terrain quad's six
-- indices are a function of its ordinal; a stamped template's are whatever
-- the template says, repeated at an offset, and reconstructing that would
-- mean keeping the template in step with the cache forever.
function MeshCache.packVerts(verts)
  if not have() then return nil end
  local parts, np = {}, 0
  local buf, nb = {}, 0
  for i = 1, #verts do
    local v = verts[i]
    buf[nb + 1], buf[nb + 2], buf[nb + 3] = v[1], v[2], v[3]
    buf[nb + 4], buf[nb + 5], buf[nb + 6] = v[4], v[5], v[6]
    nb = nb + 6
    if nb >= 768 then
      np = np + 1
      parts[np] = love.data.pack("string", "<" .. string.rep("f", nb),
                                 unpack(buf, 1, nb))
      nb = 0
    end
  end
  if nb > 0 then
    np = np + 1
    parts[np] = love.data.pack("string", "<" .. string.rep("f", nb),
                               unpack(buf, 1, nb))
  end
  return table.concat(parts), #verts
end

-- The index list, ZERO-BASED. Voxel3D.newMesh is handed a 1-based Lua table
-- and LOVE subtracts for you; the raw-Data overload does not, and a cache
-- that forgot this would render every mesh one vertex out of step -- which
-- looks like a shear, not like an off-by-one.
function MeshCache.packIdx(indices)
  if not have() then return nil end
  local parts, np = {}, 0
  local buf, nb = {}, 0
  for i = 1, #indices do
    buf[nb + 1] = indices[i] - 1
    nb = nb + 1
    if nb >= 1024 then
      np = np + 1
      parts[np] = love.data.pack("string", "<" .. string.rep("I4", nb),
                                 unpack(buf, 1, nb))
      nb = 0
    end
  end
  if nb > 0 then
    np = np + 1
    parts[np] = love.data.pack("string", "<" .. string.rep("I4", nb),
                               unpack(buf, 1, nb))
  end
  return table.concat(parts), #indices
end

-- One plain mesh as a record, or nil when there is nothing to keep.
function MeshCache.blobOf(verts, indices)
  if not (have() and verts and #verts > 0) then return nil end
  local vb, n = MeshCache.packVerts(verts)
  if not vb then return nil end
  local ib, m = MeshCache.packIdx(indices or {})
  return { verts = vb, n = n, idx = ib or "", m = m or 0 }
end

-- The aux payload: the meshes that are not the terrain. Same magic and
-- identity discipline as the terrain payload, its own format tag so the two
-- can never be read as each other.
local AUX_MAGIC = 0x58554154      -- "TAUX"

function MeshCache.packAux(blobs, variant)
  if not have() then return nil, "unavailable" end
  local names = { "grass", "flowers" }
  local out = { love.data.pack("string", "<I4I4s4I4", AUX_MAGIC,
                               MeshCache.FORMAT,
                               MeshCache.identity() .. "|" .. tostring(variant or ""),
                               #names) }
  local total = 0
  for _, name in ipairs(names) do
    local b = blobs[name]
    if b then
      out[#out + 1] = love.data.pack("string", "<s4I4s4I4s4", name, b.n,
                                     b.verts, b.m, b.idx)
      total = total + b.n
    else
      out[#out + 1] = love.data.pack("string", "<s4I4s4I4s4", name, 0, "", 0, "")
    end
  end
  out[#out + 1] = love.data.pack("string", "<I4", total)
  local blob = table.concat(out)
  if #blob > MeshCache.MAX_BYTES then return nil, "over the ceiling" end
  return blob
end

function MeshCache.unpackAux(blob, wantIdentity)
  if not have() then return nil, "unavailable" end
  if type(blob) ~= "string" or #blob < 16 then return nil, "too short" end
  local ok, res, why = pcall(function()
    local magic, fmt, id, count, at = love.data.unpack("<I4I4s4I4", blob)
    if magic ~= AUX_MAGIC then return nil, "bad magic" end
    if fmt ~= MeshCache.FORMAT then return nil, "format" end
    if wantIdentity and id ~= wantIdentity then return nil, "identity changed" end
    local blobs, total = {}, 0
    for _ = 1, count do
      local name, n, verts, m, idx
      name, n, verts, m, idx, at = love.data.unpack("<s4I4s4I4s4", blob, at)
      if n > 0 then
        if #verts ~= n * 6 * 4 then return nil, name .. ": vertex bytes" end
        if #idx ~= m * 4 then return nil, name .. ": index bytes" end
        blobs[name] = { verts = verts, n = n, idx = idx, m = m }
        total = total + n
      end
    end
    local tail = love.data.unpack("<I4", blob, at)
    if tail ~= total then return nil, "vertex total" end
    return blobs
  end)
  if not ok then return nil, "malformed: " .. tostring(res) end
  if type(res) ~= "table" then return nil, tostring(why or res or "malformed") end
  return res
end

function MeshCache.loadAux(game, mapId)
  local st = storage()
  if not (st and have()) then return nil, "unavailable" end
  local ok, bytes, code = pcall(st.readBytes, st, game, MeshCache.key(mapId, "aux"))
  if not ok then return nil, "read threw" end
  if type(bytes) ~= "string" then return nil, tostring(code or "not_found") end
  return MeshCache.unpackAux(bytes, MeshCache.identity() .. "|")
end

function MeshCache.saveAux(game, mapId, blobs)
  local st = storage()
  if not (st and have() and blobs) then return false, "unavailable" end
  local blob, err = MeshCache.packAux(blobs, "")
  if not blob then return false, err end
  local key = MeshCache.key(mapId, "aux")
  indexAdd(game, key)
  local ok, wrote, code = pcall(st.writeBytes, st, game, key, blob)
  if not ok then return false, "write threw" end
  if not wrote then return false, tostring(code or "refused") end
  MeshCache.stats.writes = MeshCache.stats.writes + 1
  MeshCache.stats.bytes = MeshCache.stats.bytes + #blob
  return true, #blob
end

-- Does a write come back? Nothing about meshes, identities or maps -- just
-- bytes into mod.storage and straight back out, twice, under a key nothing
-- else uses.
--
-- This exists because the cache reported six successful writes and then read
-- back the content of a PREVIOUS session at the same keys, which is a claim
-- about the storage layer and not about anything in this file. Ten lines
-- settle it either way, and they run in a second without building a map.
function MeshCache.storageCheck(game)
  local st = storage()
  if not st then return nil, "no storage" end
  local key = PREFIX .. "/selftest"
  local a = "TERRARIUM-A-" .. string.rep("a", 64)
  local b = "TERRARIUM-B-" .. string.rep("b", 64)
  local okW, wrote, code = pcall(st.writeBytes, st, game, key, a)
  if not okW then return false, "write threw: " .. tostring(wrote) end
  if not wrote then return false, "write refused: " .. tostring(code) end
  local okR, got = pcall(st.readBytes, st, game, key)
  if not okR then return false, "read threw: " .. tostring(got) end
  if got ~= a then
    return false, ("first read came back %s (%d bytes), not what was written")
                    :format(type(got) == "string" and got:sub(1, 20) or tostring(got),
                            type(got) == "string" and #got or -1)
  end
  -- and OVERWRITE, which is what the cache actually does on every miss
  local okW2, wrote2, code2 = pcall(st.writeBytes, st, game, key, b)
  if not okW2 or not wrote2 then
    return false, "overwrite refused: " .. tostring(code2 or wrote2)
  end
  local okR2, got2 = pcall(st.readBytes, st, game, key)
  if not okR2 then return false, "second read threw" end
  if got2 ~= b then
    return false, ("OVERWRITE DID NOT STICK: read back %s")
                    :format(type(got2) == "string" and got2:sub(1, 20) or tostring(got2))
  end
  pcall(st.delete, st, game, key)
  return true, "write, read, overwrite and read again all agree"
end

-- ------- SELF-CHECK
--
-- A round trip through the real pack and unpack, asserting the structure and
-- the bytes come back identical, plus the three refusals that matter: a bad
-- magic, a stale identity and a truncated tail. Runs without a GPU and
-- without a map, so it can be called from any probe -- and it is the only
-- test here that proves the LAYOUT rather than the plumbing.
function MeshCache.selfCheck()
  if not have() then return nil, "love.data unavailable" end
  local function vbytes(quads)
    local floats = quads * 4 * 6
    local t = {}
    for i = 1, floats do t[i] = (i % 17) * 0.25 - 2 end
    return love.data.pack("string", "<" .. string.rep("f", floats), unpack(t))
  end
  local records = {
    terrain = {
      { x0 = -96, z0 = -96, x1 = 352, z1 = 160, ymax = 48,
        quads = 3, bytes = vbytes(3) },
      { x0 = 160, z0 = 0, x1 = 608, z1 = 160, ymax = 0,
        quads = 1, bytes = vbytes(1) },
    },
    water = {
      { x0 = 0, z0 = 0, x1 = 256, z1 = 64, ymax = -2,
        quads = 2, bytes = vbytes(2) },
    },
  }
  local blob, err = MeshCache.pack(records, "selfcheck")
  if not blob then return false, "pack failed: " .. tostring(err) end
  local id = MeshCache.identity() .. "|selfcheck"
  local back, why = MeshCache.unpack(blob, id)
  if not back then return false, "unpack failed: " .. tostring(why) end
  for _, name in ipairs({ "terrain", "water" }) do
    local a, b = records[name], back[name]
    if #a ~= #b then
      return false, ("%s: %d chunks back, %d in"):format(name, #b, #a)
    end
    for i = 1, #a do
      for _, f in ipairs({ "x0", "z0", "x1", "z1", "ymax", "quads" }) do
        if a[i][f] ~= b[i][f] then
          return false, ("%s chunk %d field %s: %s vs %s")
                          :format(name, i, f, a[i][f], b[i][f])
        end
      end
      if a[i].bytes ~= b[i].bytes then
        return false, ("%s chunk %d: %d bytes back, %d in")
                        :format(name, i, #b[i].bytes, #a[i].bytes)
      end
    end
  end
  -- and the three refusals
  if MeshCache.unpack(blob, id .. "x") then
    return false, "a changed identity was accepted"
  end
  if MeshCache.unpack(blob:sub(1, #blob - 8), id) then
    return false, "a truncated payload was accepted"
  end
  if MeshCache.unpack("XXXX" .. blob:sub(5), id) then
    return false, "a bad magic was accepted"
  end
  return true, ("%d bytes round-tripped; stale, truncated and corrupt refused")
                 :format(#blob)
end

return MeshCache
