# Drive tests/leaf_litter_offline.lua in a real Lua 5.1 (lupa), which is the
# dialect LuaJIT speaks, so the store under test is the one that ships.
#
#   python tools/run_leaf_litter_offline.py
#
# Exits non-zero when a check fails, so it can gate a release.
import sys, io, os
import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rt = lua51.LuaRuntime(unpack_returned_tuples=True)
src = io.open(os.path.join(ROOT, "tests", "leaf_litter_offline.lua"),
              encoding="utf-8").read()
load = rt.eval("function(s) return assert(loadstring(s, '@leaf_litter_offline.lua')) end")
chunk = load(src)
try:
    chunk(ROOT.replace(os.sep, "/"))
except Exception as e:
    print("LUA ERROR:", e)
    sys.exit(2)
