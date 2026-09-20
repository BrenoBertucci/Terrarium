"""Run tests/battleparry_offline.lua with no game, no LOVE and no ROM.

The parry's verdict and the charge meter's arithmetic are pure functions over
three numbers; this drives them in a bare Lua (lupa) with the mod's own V
namespace stubbed, so a wrong band or an off-by-one on the window fails in a
second instead of in a fight.

    py tools/run_battleparry_offline.py

Exits non-zero on the first failing check, so it can gate a deploy.
Needs: py -m pip install lupa
"""

import os
import sys

from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BOOT = r"""
local root = ...
-- the mod namespace main.lua builds, with just the two doors lib/ uses
local V = {}
local cache = {}
function V.require(name)
  local hit = cache[name]
  if hit ~= nil then return hit end
  local path = root .. "/lib/" .. name .. ".lua"
  local f = assert(io.open(path, "rb"), "missing module: " .. path)
  local src = f:read("*a"); f:close()
  -- lib/BattleScene.lua and lib/VoxelScene.lua carry a UTF-8 BOM; strip one
  -- here so a module that grows one later does not fail as a syntax error
  if src:sub(1, 3) == "\239\187\191" then src = src:sub(4) end
  local chunk = assert(load(src, "@lib/" .. name .. ".lua"))
  local value = chunk(V)
  cache[name] = value
  return value
end
function V.data(name)
  local path = root .. "/data/" .. name .. ".lua"
  local f = io.open(path, "rb")
  if not f then return nil end
  local src = f:read("*a"); f:close()
  local chunk = load(src, "@data/" .. name .. ".lua")
  return chunk and chunk(V) or nil
end
V.mod = nil            -- no save, no persisted options: every row reads default
return V
"""


def main() -> int:
    lua = LuaRuntime(unpack_returned_tuples=True)
    root = ROOT.replace("\\", "/")

    # A LOVE stub is not needed by the two modules under test (they only reach
    # for love.graphics inside draw), but an accidental reach should read as a
    # loud failure rather than as a nil index three frames later.
    lua.execute(
        "love = setmetatable({}, { __index = function(_, k)"
        ' error("offline: love." .. tostring(k) .. " is not available", 2)'
        " end })"
    )

    V = lua.eval("(function(...) %s end)" % BOOT)(root)

    with open(os.path.join(ROOT, "tests", "battleparry_offline.lua"),
              encoding="utf-8-sig") as fh:
        src = fh.read()
    chunk = lua.eval("(function(src) return assert(load(src, '@battleparry_offline')) end)")(src)
    fails = chunk(V)
    return 1 if fails and int(fails) > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
